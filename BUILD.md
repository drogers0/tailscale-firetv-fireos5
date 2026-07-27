# Building

Produces `dist/tailscale-fireos5-<ver>-minsdk22-armeabi-v7a.apk` from a chosen upstream
release, with the API floor overridden back to 22.

Roughly **10 minutes** cold on a fast connection; most of that is the ~1 GB Android NDK.
Subsequent builds reuse the checkout and caches and take a couple of minutes.

## The API floor is enforced twice

This is the part that is easy to get wrong. From 1.64.0 onward, lowering the floor requires
patching **both** of these — the script does it for you:

| Where | Upstream | Patched to |
|---|---|---|
| `android/build.gradle` | `minSdkVersion 26` | `minSdkVersion 22` |
| `gomobile bind` | `-androidapi 26` | `-androidapi 22` |

Patch only the Gradle value and you get an APK that installs cleanly and then dies in
native code. The native `libtailscale.aar` carries its own independent gate.

Because the floor is overridden rather than natively supported, the risk moves from
compile time to **run time**. Watch for `NoSuchMethodError`, `NoClassDefFoundError`, and
`VerifyError` — each means the code reached for an API newer than 22.

---

## Prerequisites

| Requirement | Why | Notes |
|---|---|---|
| **JDK 17** | AGP 8.1.4 targets it | **Not 21.** See [below](#jdk-17-is-not-optional) |
| **Android SDK** | `platforms;android-34`, `build-tools;34.0.0`, `cmdline-tools` | script installs what's missing |
| **NDK 23.1.7779620** | cgo cross-compile for `armeabi-v7a` | ~1 GB; exact version required |
| **Go** (any recent) | bootstraps Tailscale's pinned toolchain | system Go is only used to fetch the pinned one |
| **~5 GB disk** | SDK + NDK + Gradle caches | |
| `git`, `curl`, `unzip` | | |

### macOS

```sh
brew install --cask temurin@17
brew install go
# Android SDK: Android Studio, or `brew install --cask android-commandlinetools`
```

### Debian / Ubuntu

```sh
sudo apt install -y openjdk-17-jdk golang-go git curl unzip
```

### JDK 17 is not optional

AGP 8.1.4 officially supports JDK 17; JDK 21 support arrived in AGP 8.2. Building with 21
typically fails deep into the Gradle run with an opaque Kotlin or Jetifier error, after
you've already paid for the whole download. The build script refuses to start on the wrong
JDK rather than let you discover this twenty minutes in.

Point it at the right one explicitly if you have several installed:

```sh
# macOS
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
# Linux
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
```

## Build

```sh
./scripts/build.sh
```

Override anything via environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `TS_REF` | `1.64.0-t78dc8622d-gfd2ca6fa940` | upstream tag or commit to build |
| `MIN_SDK` | `22` | API floor; patched into Gradle **and** gomobile |
| `GOMOBILE_TARGET` | `android/arm` | `android` for all ABIs (slower, larger) |
| `ANDROID_SDK_ROOT` | `~/Library/Android/sdk` (mac), `~/Android/Sdk` (linux) | SDK location |
| `JAVA_HOME` | autodetected JDK 17 | |
| `WORKDIR` | `.build` | scratch checkout, one dir per ref |
| `SKIP_TESTS` | `1` | set `0` to run upstream unit tests |

### Choosing `TS_REF`

| Ref | UI | Notes |
|---|---|---|
| `3926cf4b56` | **stubs** | renders, but Connect is inert and Settings is a placeholder. Historical interest only |
| **`1.64.0-…`** | complete | **default.** Earliest finished Compose UI → least API-26 creep |
| `1.68.0-…` / `1.76.2-…` / `1.78.0-…` | complete | newer; 1.78.0 adds *"don't show permissions for TV"*, but more API-26 exposure |

If 1.64.0 hits a runtime `NoSuchMethodError`, try a *newer* ref (bug may be fixed) or
raise `MIN_SDK` and accept the device is out of reach.

## What it does

1. **Preflight** — verifies JDK 17, Go and the SDK; refuses to start on the wrong JDK.
2. **Installs missing SDK packages** via `sdkmanager` (NDK, platform-34, build-tools).
3. **Shallow-fetches** the single ref — no history clone. Re-runs reset any prior patches
   so overrides always apply to pristine sources.
4. **Go toolchain** — uses upstream's `tool/go` wrapper when present (it fetches
   Tailscale's own pinned Go), otherwise falls back to system Go.
5. **Applies the API-floor overrides** (both places, see above) and writes a
   `local.properties` stub, without which `getLocalProperty()` breaks configuration.
6. **Builds the native library** — auto-detects the recipe: `gomobile bind` against
   `./libtailscale` on 1.64.0+, or legacy `gogio` on older refs. One ABI, not four.
7. **Assembles the APK** — picks `assembleFdroidDebug` or `assembleDebug` depending on
   whether the ref still has flavors, and skips the `test` task.
8. **Verifies** with `scripts/verify-apk.py`, which hard-fails on `minSdk` too high or a
   missing ABI. A rejected artifact is deleted rather than written to `dist/`.

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

## Install and test

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

> Reaching `NeedsLogin` proves only that *networking* works — the Gio builds get that far
> too, then die. The UI has to actually render.

## Troubleshooting

**`Could not determine java version` / Kotlin daemon crash**
Wrong JDK. See [JDK 17 is not optional](#jdk-17-is-not-optional).

**`NDK not configured` / `ndkVersion 23.1.7779620 not found`**
The version is pinned by upstream's `build.gradle`. Newer NDKs are not drop-in.

```sh
"$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" 'ndk;23.1.7779620'
```

**Gradle OOM / GC overhead**
Compose compilation is memory-hungry and upstream ships `-Xmx2g`. The script raises this
to 6 GB. On a small machine, lower it in `.build/.../android/gradle.properties`.

**`gogio: unknown flag -arch`**
Very old `gioui.org/cmd`. Drop to `TS_ARCH=` to build all ABIs (slower, larger).

**Build succeeds, `verify-apk.py` fails on minSdk**
Gradle picked up the wrong module. The APK must come from `android/`, not
`android_legacy/` — the latter is the Gio app and will crash on GLES 2.0 hardware.

## Reproducibility

Pinned: the upstream commit (full SHA), the Go toolchain (via upstream's `printdep`), the
NDK version, `compileSdk 34`, and AGP 8.1.4.

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
