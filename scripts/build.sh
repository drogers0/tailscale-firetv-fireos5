#!/usr/bin/env bash
#
# Build Tailscale for Fire OS 5 / Android 5.1 (API 22) on OpenGL ES 2.0 hardware.
#
# Pinned to the last upstream commit where the Compose UI and minSdkVersion 22 coexist.
# See FINDINGS.md for why that specific commit, and BUILD.md for prerequisites.

set -euo pipefail

# ---- pinned inputs ----------------------------------------------------------
TS_REPO="https://github.com/tailscale/tailscale-android.git"
TS_COMMIT="3926cf4b5611d444dae7efc50499f477371e7327"   # 2024-03-13, last Compose + minSdk 22
NDK_VERSION="23.1.7779620"                              # required by upstream build.gradle
SDK_PLATFORM="platforms;android-34"                     # compileSdkVersion 34
SDK_BUILD_TOOLS="build-tools;34.0.0"

# ---- tunables ---------------------------------------------------------------
TS_ARCH="${TS_ARCH:-arm}"          # arm = armeabi-v7a only; the big time saver
WORKDIR="${WORKDIR:-.build}"
SKIP_TESTS="${SKIP_TESTS:-1}"
GRADLE_HEAP="${GRADLE_HEAP:-6g}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/$WORKDIR/tailscale-android"
DIST="$REPO_ROOT/dist"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ---- 1. preflight -----------------------------------------------------------
info "Preflight"

command -v git   >/dev/null || die "git not found"
command -v curl  >/dev/null || die "curl not found"
command -v go    >/dev/null || die "go not found (needed to bootstrap Tailscale's pinned toolchain)"

# JDK 17. AGP 8.1.4 targets 17; 21 fails late and opaquely, so refuse up front.
if [ -z "${JAVA_HOME:-}" ]; then
  if [ "$(uname)" = "Darwin" ] && /usr/libexec/java_home -v 17 >/dev/null 2>&1; then
    JAVA_HOME="$(/usr/libexec/java_home -v 17)"
  elif [ -d /usr/lib/jvm/java-17-openjdk-amd64 ]; then
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
  fi
fi
[ -n "${JAVA_HOME:-}" ] || die "JDK 17 not found. Install it and/or set JAVA_HOME. See BUILD.md."
export JAVA_HOME

JAVA_MAJOR="$("$JAVA_HOME/bin/java" -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/')"
[ "$JAVA_MAJOR" = "17" ] || die "JAVA_HOME points at JDK $JAVA_MAJOR; AGP 8.1.4 needs JDK 17. See BUILD.md."
info "JDK 17: $JAVA_HOME"

# Android SDK
if [ -z "${ANDROID_SDK_ROOT:-}" ]; then
  if [ "$(uname)" = "Darwin" ]; then ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
  else ANDROID_SDK_ROOT="$HOME/Android/Sdk"; fi
fi
export ANDROID_SDK_ROOT ANDROID_HOME="$ANDROID_SDK_ROOT"
mkdir -p "$ANDROID_SDK_ROOT"
info "Android SDK: $ANDROID_SDK_ROOT"

# Disk (need ~5 GB)
avail_kb="$(df -Pk "$ANDROID_SDK_ROOT" | tail -1 | awk '{print $4}')"
[ "$avail_kb" -gt 5242880 ] || warn "less than 5 GB free at $ANDROID_SDK_ROOT — build may fail"

# ---- 2. Android SDK packages ------------------------------------------------
SDKMANAGER="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$SDKMANAGER" ]; then
  info "Installing Android command-line tools"
  case "$(uname)" in
    Darwin) TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-mac-9477386_latest.zip" ;;
    Linux)  TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-9477386_latest.zip" ;;
    *) die "unsupported platform $(uname)" ;;
  esac
  tmp="$ANDROID_SDK_ROOT/.tmp.$$"; mkdir -p "$tmp"
  curl -fsSL -o "$tmp/tools.zip" "$TOOLS_URL"
  unzip -q "$tmp/tools.zip" -d "$tmp"
  mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
  rm -rf "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  mv "$tmp/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  rm -rf "$tmp"
fi

need_pkg() { [ ! -d "$ANDROID_SDK_ROOT/$1" ]; }
MISSING=()
need_pkg "ndk/$NDK_VERSION"     && MISSING+=("ndk;$NDK_VERSION")
need_pkg "platforms/android-34" && MISSING+=("$SDK_PLATFORM")
need_pkg "build-tools/34.0.0"   && MISSING+=("$SDK_BUILD_TOOLS")

if [ ${#MISSING[@]} -gt 0 ]; then
  info "Installing SDK packages: ${MISSING[*]}  (NDK is ~1 GB)"
  yes 2>/dev/null | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true
  "$SDKMANAGER" "${MISSING[@]}"
else
  info "SDK packages already present"
fi

# ---- 3. source checkout -----------------------------------------------------
if [ ! -d "$SRC/.git" ]; then
  info "Fetching upstream commit ${TS_COMMIT:0:12} (shallow)"
  mkdir -p "$SRC"
  git -C "$SRC" init -q
  git -C "$SRC" remote add origin "$TS_REPO" 2>/dev/null || true
  git -C "$SRC" fetch -q --depth 1 origin "$TS_COMMIT"
  git -C "$SRC" checkout -q FETCH_HEAD
else
  info "Reusing checkout at $SRC"
  git -C "$SRC" checkout -q "$TS_COMMIT" 2>/dev/null || true
fi

actual="$(git -C "$SRC" rev-parse HEAD)"
[ "$actual" = "$TS_COMMIT" ] || die "checkout is at $actual, expected $TS_COMMIT"

# ---- 4. Tailscale's pinned Go toolchain -------------------------------------
# The tailscale_go build tag needs their fork; stock Go will not do. Mirrors upstream's
# Makefile, which resolves the version through tailscale.com/cmd/printdep.
info "Resolving Tailscale Go toolchain"
GO_VER="$(cd "$SRC" && go run tailscale.com/cmd/printdep --go)"
TOOLCHAINDIR="${TOOLCHAINDIR:-$HOME/.cache/tailscale-android-go-$GO_VER}"
if [ ! -x "$TOOLCHAINDIR/bin/go" ]; then
  info "Downloading Go $GO_VER toolchain"
  GO_URL="$(cd "$SRC" && go run tailscale.com/cmd/printdep --go-url)"
  mkdir -p "$TOOLCHAINDIR"
  curl -fsSL "$GO_URL" | tar --strip-components=1 -C "$TOOLCHAINDIR" -zx
else
  info "Go $GO_VER toolchain cached"
fi
export PATH="$TOOLCHAINDIR/bin:$PATH"
export GOROOT=
info "go: $(go version)"

# ---- 5. build ipn.aar (the Go/cgo layer) ------------------------------------
VERSIONNAME="$(grep -m1 versionName "$SRC/android/build.gradle" 2>/dev/null | sed -E 's/.*"(.*)".*/\1/' || true)"
[ -n "$VERSIONNAME" ] || VERSIONNAME="$(grep -m1 versionName "$SRC/android_legacy/build.gradle" | sed -E 's/.*"(.*)".*/\1/')"
VERSIONNAME_SHORT="${VERSIONNAME%%-*}"
info "Version: $VERSIONNAME"

info "Building ipn.aar for arch='$TS_ARCH' (upstream default is all four ABIs)"
mkdir -p "$SRC/android/libs"
ARCH_FLAG=(); [ -n "$TS_ARCH" ] && ARCH_FLAG=(-arch "$TS_ARCH")
( cd "$SRC" && go run gioui.org/cmd/gogio \
    -ldflags "-X tailscale.com/version.longStamp=$VERSIONNAME -X tailscale.com/version.shortStamp=$VERSIONNAME_SHORT" \
    -buildmode archive \
    -target android \
    "${ARCH_FLAG[@]}" \
    -appid com.tailscale.ipn \
    -tags novulkan,tailscale_go \
    -o android/libs/ipn.aar \
    github.com/tailscale/tailscale-android/cmd/tailscale )

[ -f "$SRC/android/libs/ipn.aar" ] || die "ipn.aar was not produced"
info "ipn.aar: $(du -h "$SRC/android/libs/ipn.aar" | cut -f1)"

# ---- 6. assemble the APK ----------------------------------------------------
# Upstream ships -Xmx2g, which invites GC thrash on Compose.
GP="$SRC/android/gradle.properties"
if ! grep -q "^org.gradle.parallel" "$GP" 2>/dev/null; then
  {
    echo "org.gradle.parallel=true"
    echo "org.gradle.caching=true"
    echo "kotlin.incremental=true"
  } >> "$GP"
fi
sed -i.bak -E "s/^org\.gradle\.jvmargs=.*/org.gradle.jvmargs=-Xmx${GRADLE_HEAP} -XX:MaxMetaspaceSize=1g/" "$GP" && rm -f "$GP.bak"

GRADLE_TASKS=(assembleFdroidDebug)
[ "$SKIP_TESTS" = "1" ] || GRADLE_TASKS=(test assembleFdroidDebug)

info "Gradle: ${GRADLE_TASKS[*]}"
( cd "$SRC/android" && ./gradlew --no-daemon "${GRADLE_TASKS[@]}" )

APK="$SRC/android/build/outputs/apk/fdroid/debug/android-fdroid-debug.apk"
[ -f "$APK" ] || die "expected APK not found at $APK"

# ---- 7. verify + publish ----------------------------------------------------
mkdir -p "$DIST"
OUT="$DIST/tailscale-fireos5-${VERSIONNAME}-armeabi-v7a.apk"
cp "$APK" "$OUT"

info "Verifying against device constraints (API 22 / armeabi-v7a)"
if ! python3 "$REPO_ROOT/scripts/verify-apk.py" --require-min-sdk 22 --require-abi armeabi-v7a "$OUT"; then
  rm -f "$OUT"
  die "verification failed — artifact rejected, not written to dist/"
fi

( cd "$DIST" && shasum -a 256 "$(basename "$OUT")" > "$(basename "$OUT").sha256" )

echo
bold "Built: $OUT"
bold "sha256: $(cut -d' ' -f1 < "$OUT.sha256")"
cat <<EOF

Next:
  adb connect <fire-stick-ip>:5555
  ./scripts/device-check.sh <fire-stick-ip>:5555
  adb install -r "$OUT"

Then watch the launch — the failure this build targets is immediate:
  adb logcat -c
  adb shell monkey -p com.tailscale.ipn -c android.intent.category.LAUNCHER 1
  adb logcat | grep -iE "tailscale|gio|opengl|egl|glerror|fatal"
EOF
