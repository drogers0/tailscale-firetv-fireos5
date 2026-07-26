# Building

Produces `dist/tailscale-fireos5-<version>-armeabi-v7a.apk` from upstream source pinned at
commit `3926cf4b5611d444dae7efc50499f477371e7327`.

Roughly **10 minutes** on a modern machine with a fast connection. Most of that is
downloading the ~1 GB Android NDK.

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
| `ANDROID_SDK_ROOT` | `~/Library/Android/sdk` (mac), `~/Android/Sdk` (linux) | SDK location |
| `JAVA_HOME` | autodetected JDK 17 | |
| `TS_ARCH` | `arm` | `arm,arm64` to also build 64-bit |
| `WORKDIR` | `.build` | scratch checkout |
| `SKIP_TESTS` | `1` | set `0` to run upstream unit tests |

## What it does

1. **Preflight** — verifies JDK 17, Go, disk space, and the SDK; fails fast on any gap.
2. **Installs missing SDK packages** via `sdkmanager` (accepting licenses).
3. **Shallow-fetches** exactly one commit — no history clone.
4. **Fetches Tailscale's pinned Go toolchain** into
   `~/.cache/tailscale-android-go-<ver>`, matching upstream's `Makefile`. The
   `tailscale_go` build tag needs their fork; stock Go will not do.
5. **Builds `ipn.aar`** with `gogio -arch arm` — **one ABI instead of four**, the single
   biggest time saving.
6. **Assembles the APK** with `./gradlew assembleFdroidDebug`, skipping the `test` task.
7. **Verifies** the result with `scripts/verify-apk.py` — hard-fails if `minSdk > 22` or
   `armeabi-v7a` is missing, so a silently-wrong artifact can't reach `dist/`.

Output:

```
dist/tailscale-fireos5-<version>-armeabi-v7a.apk
dist/tailscale-fireos5-<version>-armeabi-v7a.apk.sha256
```

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
