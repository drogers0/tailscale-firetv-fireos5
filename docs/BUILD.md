# Building

Produces `dist/tailscale-fireos5-<ver>-minsdk22-armeabi-v7a.apk` from a chosen upstream
release, with the API floor overridden back to 22. The trailing ABI follows what you
targeted — `arm64-v8a`, or `universal` for a multi-ABI build.

Roughly **10 minutes** cold on a fast connection; most of that is the ~1 GB Android NDK.
Subsequent builds reuse the checkout and caches and take a couple of minutes.

## The API floor is enforced twice

This is the part that is easy to get wrong. From 1.64.0 onward, lowering the floor requires
patching **both** of these — the script does it for you:

| Where | Upstream | Patched to |
|---|---|---|
| `android/build.gradle.kts` | `minSdk = 26` | `minSdk = 22` |
| `gomobile bind` | `-androidapi 26` | `-androidapi 22` |

> [!WARNING]
> Patch only the Gradle value and you get an APK that installs cleanly and then dies in
> native code. The native `libtailscale.aar` carries its own independent gate.

Because the floor is overridden rather than natively supported, the risk moves from
compile time to **run time**. Watch for `NoSuchMethodError`, `NoClassDefFoundError`, and
`VerifyError` — each means the code reached for an API newer than 22.

---

## Prerequisites

| Requirement | Why | Notes |
|---|---|---|
| **JDK** (the major pinned as `JDK=` in `scripts/build.sh`) | upstream's Gradle daemon criteria and AGP | see [below](#the-pinned-jdk-is-required) |
| **Android SDK** | the platform, build-tools and cmdline-tools pinned in `scripts/build.sh` | script installs what's missing |
| **NDK** (the `NDK_VERSION` pin) | cgo cross-compile for `armeabi-v7a` | ~1 GB; exact version required |
| **~5 GB disk** | SDK + NDK + Gradle caches | |
| `git`, `curl`, `unzip` | | |
| `shellcheck`, `python3` | `make check` | `brew install shellcheck` / `apt install shellcheck`. The `verify-apk` tests skip without an SDK `aapt2` and platform (`android.jar`) |

### macOS

```sh
brew install --cask "temurin@$(sed -n 's/^JDK=//p' scripts/build.sh)"
# Android SDK: Android Studio, or `brew install --cask android-commandlinetools`
```

### Debian / Ubuntu

```sh
sudo apt install -y "openjdk-$(sed -n 's/^JDK=//p' scripts/build.sh)-jdk" git curl unzip
```

### The pinned JDK is required

Upstream's `gradle/gradle-daemon-jvm.properties` names the JDK major its Gradle daemon must
run on, and Gradle downloads one when `JAVA_HOME` does not match. The build script therefore
checks `JAVA_HOME`'s major version against the `JDK` pin in `scripts/build.sh` before
anything slow, and refuses to start on any other.

Point it at the right one explicitly if you have several installed:

```sh
# macOS
export JAVA_HOME=$(/usr/libexec/java_home -F -v "$(sed -n 's/^JDK=//p' scripts/build.sh)")
# Linux
export JAVA_HOME=/usr/lib/jvm/java-"$(sed -n 's/^JDK=//p' scripts/build.sh)"-openjdk-amd64
```

With `JAVA_HOME` unset, the script tries `java_home -F -v <JDK>`, then
`~/.local/jdks/jdk-<JDK>*`, then the Debian path (`<JDK>` is the `JDK=` pin), and checks each
candidate's major version itself: plain `java_home -v <JDK>` silently returns another JDK
when that major is not registered.

## Build

```sh
make build
```

The Make targets are thin wrappers around the scripts:

| Target | Does |
|---|---|
| `make check` | shellcheck, `verify-apk` tests, and `scripts/build.sh --patch-only` (toolchain pins match `TS_REF`, the series applies, no stream JSON decode remains; needs only git) |
| `make build` | full build of the armeabi-v7a APK into `dist/` |
| `make build-emu` | the same for the local emulator ABI (arm64 on arm64 hosts, x86_64 elsewhere), into `.build/dist-emu/` so `dist/` keeps only shippable APKs |
| `make emu-test` | boots a fresh API 22 emulator (its own AVD, `tsfire-api22`, on port 5584), installs the `build-emu` APK and runs `scripts/emu-test.sh`'s adb smoke checks; installs the emulator and image on first use; logs in `.build/emu-test/` |
| `make emu-test-net` | `emu-test`, then logs the emulator in to a real tailnet and checks the tunnel, reboots and a network change; needs `TS_AUTHKEY` (environment or `.env`), see [TESTING.md](TESTING.md) |
| `make lint` | build plus Android Lint, `NewApi` only; its APK goes to `.build/dist-lint/` |
| `make clean` | removes `.build/` (or `WORKDIR`); `dist/` is kept |

Tunables stay environment variables read by `scripts/build.sh`; `make build TS_REF=…` and
`TS_REF=… make build` both work:

| Variable | Default | Purpose |
|---|---|---|
| `TS_REF` | pinned in `scripts/build.sh` | upstream release tag that `patches/` is for |
| `MIN_SDK` | `22` | API floor; patched into Gradle **and** gomobile |
| `GOMOBILE_TARGET` | `android/arm` | `android/arm64` for arm64-only; bare `android` for all ABIs (slower, larger) |
| `ANDROID_SDK_ROOT` | `~/Library/Android/sdk` (mac), `~/Android/Sdk` (linux) | SDK location |
| `JAVA_HOME` | autodetected, the pinned JDK | |
| `WORKDIR` | `.build` | scratch checkout, one dir per ref |
| `DIST` | `dist` | APK output dir, absolute or relative to the repo root; `make build-emu`, `emu-test` and `emu-test-net` use the Makefile's `EMU_DIST` (`.build/dist-emu`), `make lint` uses `LINT_DIST` (`.build/dist-lint`). An APK already at the output path is overwritten only if it is debug-signed, so a release-signed one is never replaced |
| `GRADLE_HEAP` | `6g` | Gradle's `-Xmx`; build.sh writes it into the checkout's `gradle.properties` on every run |
| `SKIP_TESTS` | `1` | set `0` to run upstream unit tests (debug variant) |
| `LINT` | `0` | `1` runs Android Lint, `NewApi` only, with `patches/lint.xml`'s ignores |

### `TS_REF` and the patch series

`patches/*.patch` is one series for the default `TS_REF`. Another ref needs the series rebased
in the same change. `scripts/build.sh` supports upstream's current build layout only. A ref
whose toolchain differs from the pins stops at once and prints the pin lines to change. A
patch that does not apply stops the build, naming the hunk.

## What it does

1. **Shallow-fetches** the single ref — no history clone. Re-runs reset any prior patches
   so overrides always apply to pristine sources.
2. **Checks the toolchain pins** against the checkout, then **applies the patch series**,
   `patches/*.patch` (fatal if there is none), then rejects any stream JSON decode (0005).
   A non-applying patch fails here, before any SDK download; `--patch-only` stops here.
3. **Preflight** — verifies the pinned JDK and the SDK; refuses to start on the wrong JDK.
4. **Installs missing SDK packages** via `sdkmanager` (the pinned SDK packages).
5. **Go toolchain** — upstream's `tool/go` wrapper (it fetches Tailscale's own pinned Go);
   a ref without it, or a `tool/go` that yields no toolchain, is fatal.
6. **Applies the API-floor overrides** (both places, see above), **generates
   `tailscale.version`**, then **builds the native library** with `gomobile bind` against
   `./libtailscale`, using upstream's `GOMOBILE_BUILD_TAGS`. One ABI, not four.
7. **Assembles the APK** — `assembleDebug`, with a versionCode derived from the upstream
   commit — plus debug unit tests with `SKIP_TESTS=0`, and NewApi lint with `LINT=1`.
8. **Verifies** with `scripts/verify-apk.py`, which hard-fails on `minSdk` too high or
   the Go native library missing for the ABI you targeted, or for `armeabi-v7a` in a
   multi-ABI build, or a versionCode other than the one passed to Gradle. A rejected
   artifact is deleted rather than written to the output directory.

Output:

```
dist/tailscale-fireos5-<ver>-minsdk22-armeabi-v7a.apk
dist/tailscale-fireos5-<ver>-minsdk22-armeabi-v7a.apk.sha256
```

## Signing

```sh
./scripts/sign-apk.sh        # newest APK in dist/, or pass a path
```

Uses `TS_KEYSTORE_BASE64` / `TS_KEYSTORE_PASSWORD` / `TS_KEY_ALIAS` when set (CI), else
`~/.keystores/tailscale-firetv-release.{jks,pass}`. See STATUS.md — note that GitHub
secrets cannot be read back, so the local keystore must be preserved.

A later `make build` of the same version refuses to overwrite the signed APK. Move it (for
example to a release folder), or build with `DIST=<dir>`.

## Install and test

Before a device, the emulator tiers in [TESTING.md](TESTING.md) catch most regressions.

```sh
adb connect <fire-stick-ip>:5555     # accept the on-screen prompt the first time
./scripts/device-check.sh <fire-stick-ip>:5555   # confirm API 22 + GLES 2.0
adb install -r dist/tailscale-fireos5-*.apk
```

Watch the launch — the failure mode this build targets is loud and immediate:

```sh
adb logcat -c
adb shell monkey -p com.tailscale.ipn -c android.intent.category.LAUNCHER 1
adb logcat | grep -iE "tailscale|gio|opengl|egl|glerror|fatal"
```

**Success** looks like a rendered UI plus a control-plane handshake:

```
control: RegisterReq: got response; ...; authURL=true
control: AuthURL is https://login.tailscale.com/a/...
Switching ipn state NoState -> NeedsLogin (WantRunning=true)
```

**Failure** — the bug that motivates this repo — looks like:

```
fatal error: no support for OpenGL ES 3 nor EXT_sRGB
```

or `fatal error: glGetError: 0x501`. Both mean the UI still wants GLES 3.

> [!IMPORTANT]
> Reaching `NeedsLogin` proves only that *networking* works — the Gio builds get that far
> too, then die. The UI has to actually render.

## Troubleshooting

**`Could not determine java version` / Kotlin daemon crash**
Wrong JDK. See [The pinned JDK is required](#the-pinned-jdk-is-required).

**`NDK not configured` / `ndkVersion … not found`**
The version is pinned by upstream's `build.gradle.kts`; build.sh's `NDK_VERSION` must match.
Newer NDKs are not drop-in.

```sh
"$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" "ndk;$(sed -n 's/^NDK_VERSION=//p' scripts/build.sh)"
```

**`needs new toolchain pins`**
Upstream changed its JDK, SDK platform, build-tools or NDK. Paste the printed `NAME=value`
lines into `scripts/build.sh`.

**Gradle OOM / GC overhead**
Compose compilation is memory-hungry and upstream ships `-Xmx2g`. The script raises this
to 6 GB. On a small machine, lower it with `GRADLE_HEAP`, e.g. `GRADLE_HEAP=3g make build`.

## Reproducibility

Pinned: the upstream commit, the Go toolchain (`tool/go`), the toolchain pins in
`scripts/build.sh` (JDK, SDK platform, build-tools, NDK), and `patches/`. The versionCode
derives from the upstream commit time.

Not pinned: Gradle's transitive dependency resolution, and the debug signing key — Android
generates a random `~/.android/debug.keystore` per machine. **Two builds on different
machines will not be byte-identical**, and installing a rebuild over an existing install
fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE` unless you uninstall first or reuse the
keystore. Compare `verify-apk.py` output rather than file hashes.

## Why not just download an APK?

Every avenue was checked and closed — details and evidence in [FINDINGS.md](FINDINGS.md):

| Source | Result |
|---|---|
| `pkgs.tailscale.com` | current release only; requires Android 8+ |
| GitHub releases | v1.2.2 (2020, Gio) then 1.76.2+ (minSdk 26) — nothing between |
| F-Droid | packaging began Dec 2025; all Android 8+ |
| IzzyOnDroid | not packaged |
| APKMirror "Android 5.1+" | tops out at 1.62.0 — **all Gio-based**, all crash on GLES 2.0 |

No release has ever paired the Compose UI with minSdk 22. That is the entire reason this
repo compiles from source.
