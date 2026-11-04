#!/usr/bin/env bash
#
# Build Tailscale for Fire OS 5 / Android 5.1 (API 22) on OpenGL ES 2.0 hardware.
#
# Upstream declares minSdk 26 from 2024-03-13 onward, but that bump was a one-line
# decision, not a dependency change (see docs/FINDINGS.md). This script checks out a
# chosen upstream ref and overrides the API floor in both places it is enforced:
#
#   1. android/build.gradle.kts -> minSdk
#   2. gomobile bind            -> -androidapi   (the native AAR has its own gate)
#
# Overriding only the first produces an APK that installs and then dies in native code.
#
# Usage: ./scripts/build.sh [--patch-only]
#   --patch-only  fetch TS_REF, apply the patch series, then stop. Needs only git (tier 0).
#
# See docs/BUILD.md for prerequisites and the patch series.

set -euo pipefail

# ---- pinned inputs ----------------------------------------------------------
TS_REPO="https://github.com/tailscale/tailscale-android.git"
# The release the patch series in patches/ is for.
TS_REF="${TS_REF:-1.104.5-t788384763-gd8673104f}"
# Toolchain. Each pin except CMDLINE_TOOLS must equal what TS_REF declares; the build
# checks that right after the checkout. CI keys its SDK cache on the four SDK package
# NAME= lines (.github/actions/setup-build). Keep each pin a bare NAME=value (no quotes or
# trailing comment): CI and the docs read these lines with sed.
JDK=21
NDK_VERSION=23.1.7779620
CMDLINE_TOOLS=9477386
SDK_PLATFORM=android-36
BUILD_TOOLS=36.0.0

# ---- tunables ---------------------------------------------------------------
MIN_SDK="${MIN_SDK:-22}"           # device API level
GOMOBILE_TARGET="${GOMOBILE_TARGET:-android/arm}"   # arm = armeabi-v7a
WORKDIR="${WORKDIR:-.build}"
DIST="${DIST:-dist}"               # APK output dir; relative paths are from the repo root
SKIP_TESTS="${SKIP_TESTS:-1}"
GRADLE_HEAP="${GRADLE_HEAP:-6g}"
LINT="${LINT:-0}"                  # 1 = also run Android Lint, NewApi only (scripts/lint-newapi.gradle)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/$WORKDIR/tailscale-android-${TS_REF##*-}"
case "$DIST" in /*) ;; *) DIST="$REPO_ROOT/$DIST" ;; esac

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
java_major() { "$1/bin/java" -version 2>&1 | sed -nE 's/.* version "([0-9]+).*/\1/p' | head -1; }

PATCH_ONLY=0
case "${1:-}" in
  "") ;;
  --patch-only) PATCH_ONLY=1 ;;
  *) die "usage: $0 [--patch-only]" ;;
esac

# gomobile arch name -> Android ABI directory name. Used for the artifact
# filename and for the ABI assertion in the verify step, so both follow what was built.
abi_for() {
  case "$1" in
    arm)   echo armeabi-v7a ;;
    arm64) echo arm64-v8a ;;
    386)   echo x86 ;;
    amd64) echo x86_64 ;;
    *)     die "unsupported arch '$1' — want arm, arm64, 386 or amd64" ;;
  esac
}

# ---- 1. patch series --------------------------------------------------------
# One series, patches/*.patch, for TS_REF: every ref this script supports needs it, so an
# empty one is fatal. Checked before any fetch.
info "Build  (ref=$TS_REF  minSdk=$MIN_SDK)"
PATCHDIR="$REPO_ROOT/patches"
PATCHES=("$PATCHDIR"/*.patch)
[ -e "${PATCHES[0]}" ] || die "no patches/*.patch"

# ---- 2. checkout ------------------------------------------------------------
command -v git >/dev/null || die "git not found"
# Reuse only a checkout that has a commit: a fetch that failed after `git init` would
# otherwise be reused, and every patch would then fail as if upstream had drifted.
if ! { [ -d "$SRC/.git" ] && git -C "$SRC" rev-parse -q --verify HEAD >/dev/null 2>&1; }; then
  info "Fetching $TS_REF (shallow)"
  rm -rf "$SRC"; mkdir -p "$SRC"
  git -C "$SRC" init -q
  git -C "$SRC" remote add origin "$TS_REPO" 2>/dev/null || true
  git -C "$SRC" fetch -q --depth 1 origin "$TS_REF"
  git -C "$SRC" checkout -q FETCH_HEAD
else
  info "Reusing checkout at $SRC"
fi
info "HEAD: $(git -C "$SRC" rev-parse HEAD)"

# checkout alone leaves patch-added files that can block the next build.
# Keep ignored build outputs and .gobin rather than discarding caches with -x.
git -C "$SRC" checkout -q -- . 2>/dev/null || true
git -C "$SRC" clean -fdq -e .gobin

# The pins must match what upstream declares; a mismatch otherwise surfaces deep in Gradle
# as an SDK download or a daemon-JVM provisioning error. Checked in --patch-only too, so
# tier 0 reports a toolchain bump the moment upstream makes one, with every new value at once.
STALE=()
pin() {   # pin NAME PINNED FILE SED_SCRIPT: SED_SCRIPT prints the value upstream declares
  local up
  up="$(sed -nE "$4" "$SRC/android/$3" 2>/dev/null | head -1)" || true
  [ -n "$up" ] || die "$TS_REF: cannot read $1 from android/$3; upstream changed its build layout"
  [ "$up" = "$2" ] || STALE+=("$1=$up")
}
pin JDK          "$JDK"          gradle/gradle-daemon-jvm.properties 's/^toolchainVersion=//p'
pin SDK_PLATFORM "$SDK_PLATFORM" gradle.properties                   's/^androidApiLevel=(.*)/android-\1/p'
pin BUILD_TOOLS  "$BUILD_TOOLS"  gradle.properties                   's/^androidBuildToolsVersion=//p'
pin NDK_VERSION  "$NDK_VERSION"  build.gradle.kts                    's/^ *ndkVersion = "(.*)"/\1/p'
[ ${#STALE[@]} -eq 0 ] || die "$TS_REF needs new toolchain pins; set these lines in scripts/build.sh:
$(printf '%s\n' "${STALE[@]}")"
info "Toolchain pins match $TS_REF (JDK $JDK, $SDK_PLATFORM, build-tools $BUILD_TOOLS, NDK $NDK_VERSION)"

# ---- 3. patches -------------------------------------------------------------
# Upstream runs at minSdk 26, so API-guard rot accumulates: calls to APIs newer
# than 22 that upstream can never hit. Each patch here fixes one, so it is obvious
# what diverges from upstream and why.
for p in "${PATCHES[@]}"; do
  if git -C "$SRC" apply --check "$p" 2>/dev/null; then
    git -C "$SRC" apply "$p"
    info "Applied patch: $(basename "$p")"
  else
    git -C "$SRC" apply --check -v "$p" >&2 || true   # show which file and hunk failed
    die "patch does not apply to $TS_REF: $(basename "$p")"
  fi
done
# 0005's bug class, which NewApi lint cannot see: below API 24, decoding JSON from a
# stream (decodeFromStream, decodeToSequence) fails on any body over 16 KB. A call site
# upstream adds must join 0005 before it ships.
# grep exits 1 for no match and 2 when it cannot scan; only the first is a pass.
hits="$(cd "$SRC" && grep -rlE 'decode(FromStream|ToSequence) *[<(]' android/src/main)" \
  || [ $? = 1 ] || die "cannot scan $TS_REF's android/src/main for stream JSON decodes"
[ -z "$hits" ] || die "stream JSON decode called in ${hits//$'\n'/, }; extend patch 0005"
if [ "$PATCH_ONLY" = 1 ]; then
  bold "Patch check passed for $TS_REF (${#PATCHES[@]} patches)"
  exit 0
fi

# ---- 4. preflight -----------------------------------------------------------
for c in curl unzip; do command -v $c >/dev/null || die "$c not found"; done

if [ -z "${JAVA_HOME:-}" ]; then
  for c in "$( [ "$(uname)" = Darwin ] && /usr/libexec/java_home -F -v "$JDK" 2>/dev/null )" \
           "$HOME"/.local/jdks/jdk-"$JDK"*/Contents/Home "$HOME"/.local/jdks/jdk-"$JDK"* \
           /usr/lib/jvm/java-"$JDK"-openjdk-*; do
    if [ -n "$c" ] && [ -x "$c/bin/java" ] && [ "$(java_major "$c")" = "$JDK" ]; then JAVA_HOME="$c"; break; fi
  done
fi
[ -n "${JAVA_HOME:-}" ] || die "JDK $JDK not found. Set JAVA_HOME. See docs/BUILD.md."
export JAVA_HOME
JAVA_MAJOR="$(java_major "$JAVA_HOME")" || die "cannot run $JAVA_HOME/bin/java"
# Gradle's daemon-JVM criteria (gradle-daemon-jvm.properties) would otherwise download a JDK.
[ "$JAVA_MAJOR" = "$JDK" ] || die "JAVA_HOME is JDK $JAVA_MAJOR; $TS_REF builds with JDK $JDK. See docs/BUILD.md."
info "JDK $JDK: $JAVA_HOME"

if [ -z "${ANDROID_SDK_ROOT:-}" ]; then
  if [ "$(uname)" = "Darwin" ]; then ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
  else ANDROID_SDK_ROOT="$HOME/Android/Sdk"; fi
fi
export ANDROID_SDK_ROOT ANDROID_HOME="$ANDROID_SDK_ROOT"
mkdir -p "$ANDROID_SDK_ROOT"
info "Android SDK: $ANDROID_SDK_ROOT"

# ---- 5. SDK packages --------------------------------------------------------
SDKMANAGER="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$SDKMANAGER" ]; then
  info "Installing Android command-line tools"
  case "$(uname)" in
    Darwin) TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-mac-${CMDLINE_TOOLS}_latest.zip" ;;
    Linux)  TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS}_latest.zip" ;;
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

MISSING=()
[ -d "$ANDROID_SDK_ROOT/ndk/$NDK_VERSION" ]       || MISSING+=("ndk;$NDK_VERSION")
[ -d "$ANDROID_SDK_ROOT/platforms/$SDK_PLATFORM" ] || MISSING+=("platforms;$SDK_PLATFORM")
[ -d "$ANDROID_SDK_ROOT/build-tools/$BUILD_TOOLS" ] || MISSING+=("build-tools;$BUILD_TOOLS")
if [ ${#MISSING[@]} -gt 0 ]; then
  info "Installing SDK packages: ${MISSING[*]}"
  yes 2>/dev/null | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true
  "$SDKMANAGER" "${MISSING[@]}"
else
  info "SDK packages present"
fi
export ANDROID_NDK_HOME="$ANDROID_SDK_ROOT/ndk/$NDK_VERSION"

# ---- 6. Go toolchain --------------------------------------------------------
GO="$SRC/tool/go"                        # upstream wrapper; fetches its own pinned Go
[ -x "$GO" ] || die "$TS_REF has no tool/go"

# gomobile shells out to a bare `go`, so the pinned toolchain must win on PATH.
# Otherwise a modern system Go compiles the ref's pinned x/tools and fails with
#   tokeninternal.go: invalid array length -delta * delta
# which looks like a source bug but is really a toolchain mismatch.
GOROOT_PINNED="$( cd "$SRC" && "$GO" env GOROOT 2>/dev/null || true )"
if [ -n "$GOROOT_PINNED" ] && [ -x "$GOROOT_PINNED/bin/go" ]; then
  export PATH="$GOROOT_PINNED/bin:$PATH"
  info "Pinned Go on PATH: $("$GOROOT_PINNED/bin/go" version)"
else
  die "tool/go did not yield a toolchain (rerun: cd $SRC && tool/go version)"
fi

# ---- 7. apply the API-floor overrides ---------------------------------------
BG="$SRC/android/build.gradle.kts"
CUR_MIN="$(sed -nE 's/^ *minSdk = ([0-9]+)$/\1/p' "$BG" 2>/dev/null)" || true
[ -n "$CUR_MIN" ] || die "no 'minSdk = N' line in $BG; upstream changed how it sets the API floor"
if [ "$CUR_MIN" != "$MIN_SDK" ]; then
  info "Overriding minSdk $CUR_MIN -> $MIN_SDK"
  sed -i.bak -E "s/^( *minSdk = )[0-9]+$/\1$MIN_SDK/" "$BG" && rm -f "$BG.bak"
fi

# ---- 8. tailscale.version ---------------------------------------------------
# Must precede the native build: version-ldflags.sh does `source tailscale.version`,
# and build.gradle.kts reads it via getVersionProperty().
#
# Getting this order wrong is not a soft failure. Without the stamp,
# version.Long() is empty and tailscale.com/version has an android+tailscale_go
# init() that panics on an invalid version — the app dies with SIGABRT at
# startup, long after a build that looked entirely successful.
if [ ! -f "$SRC/tailscale.version" ]; then
  info "Generating tailscale.version (mkversion)"
  ( cd "$SRC" && "$GO" run tailscale.com/cmd/mkversion > tailscale.version )
fi
[ -s "$SRC/tailscale.version" ] || die "tailscale.version is missing or empty"

# ---- 9. native library ------------------------------------------------------
mkdir -p "$SRC/android/libs"

# A multi-ABI build is named "universal" but must still carry armeabi-v7a; a
# single-ABI build is named and asserted as whatever arch it targeted.
ABI_LABEL="universal"; TARGET_ABI="armeabi-v7a"

# gomobile bind. The -androidapi flag is a second, independent API gate —
# leaving it at 26 yields an APK that installs then dies natively.
info "Native: gomobile bind (androidapi=$MIN_SDK, target=$GOMOBILE_TARGET)"
case "$GOMOBILE_TARGET" in
  *,*) ;;                                                     # list of targets
  */*) TARGET_ABI="$(abi_for "${GOMOBILE_TARGET#*/}")"; ABI_LABEL="$TARGET_ABI" ;;
  *)   ;;                                                     # bare "android"
esac
export GOBIN="$SRC/.gobin"; mkdir -p "$GOBIN"
export PATH="$GOBIN:$PATH"
( cd "$SRC" && "$GO" install golang.org/x/mobile/cmd/gobind golang.org/x/mobile/cmd/gomobile )

# Do not swallow this failure — an unstamped build panics at runtime, not here.
LDFLAGS="$( cd "$SRC" && ./version-ldflags.sh )" \
  || die "version-ldflags.sh failed; refusing to build an unstamped AAR (it would SIGABRT on launch)"
case "$LDFLAGS" in
  *version.longStamp=?*) : ;;
  *) die "version-ldflags.sh produced no longStamp; refusing to build an unstamped AAR" ;;
esac
# Upstream's feature tags (its Makefile's GOMOBILE_BUILD_TAGS), so this AAR has the
# feature set upstream ships rather than one this script guessed.
UP_TAGS="$(sed -n 's/^GOMOBILE_BUILD_TAGS := //p' "$SRC/Makefile" 2>/dev/null)" || true
[ -n "$UP_TAGS" ] || die "no GOMOBILE_BUILD_TAGS in $TS_REF's Makefile; upstream changed its native build"
TAGS="$("$SRC/build-tags.sh")" || die "build-tags.sh failed"
TAGS+=" $UP_TAGS"

( cd "$SRC" && gomobile bind -target "$GOMOBILE_TARGET" -androidapi "$MIN_SDK" \
    -tags "$TAGS" -ldflags "-w $LDFLAGS" -o android/libs/libtailscale.aar ./libtailscale )
[ -f "$SRC/android/libs/libtailscale.aar" ] || die "libtailscale.aar was not produced"
info "libtailscale.aar: $(du -h "$SRC/android/libs/libtailscale.aar" | cut -f1)"

# ---- 10. gradle -------------------------------------------------------------
GP="$SRC/android/gradle.properties"
grep -q "^org.gradle.parallel" "$GP" 2>/dev/null || printf 'org.gradle.parallel=true\norg.gradle.caching=true\nkotlin.incremental=true\n' >> "$GP"
if grep -q "^org.gradle.jvmargs" "$GP" 2>/dev/null; then
  sed -i.bak -E "s/^org\.gradle\.jvmargs=.*/org.gradle.jvmargs=-Xmx${GRADLE_HEAP} -XX:MaxMetaspaceSize=1g/" "$GP" && rm -f "$GP.bak"
else
  echo "org.gradle.jvmargs=-Xmx${GRADLE_HEAP} -XX:MaxMetaspaceSize=1g" >> "$GP"
fi

# Without VERSION_CODE_BASE, build.gradle.kts derives versionCode from the wall clock.
# Use the upstream commit's time instead (upstream's scheme: minutes since the epoch,
# times 10): the same ref always gets the same versionCode, and a newer ref a larger one.
COMMIT_TIME="$(git -C "$SRC" log -1 --format=%ct)" || die "cannot read the commit time of $TS_REF"
VERSION_CODE=$(( COMMIT_TIME / 60 * 10 ))
GRADLE_ARGS=(--no-daemon --continue -PVERSION_CODE_BASE="$VERSION_CODE" assembleDebug)
[ "$SKIP_TESTS" = "1" ] || GRADLE_ARGS+=(testDebugUnitTest)
if [ "$LINT" = "1" ]; then
  # NewApi only: calls to APIs above MIN_SDK are the bug class this repo patches.
  GRADLE_ARGS+=(-I "$REPO_ROOT/scripts/lint-newapi.gradle" lintDebug)
  export TS_LINT_CONFIG="$PATCHDIR/lint.xml"
fi

info "Gradle: ${GRADLE_ARGS[*]}"
( cd "$SRC/android" && ./gradlew "${GRADLE_ARGS[@]}" )

APK="$SRC/android/build/outputs/apk/debug/android-debug.apk"
[ -f "$APK" ] || die "Gradle produced no $APK"

# ---- 11. verify + publish ---------------------------------------------------
mkdir -p "$DIST"
OUT="$DIST/tailscale-fireos5-${TS_REF%%-*}-minsdk${MIN_SDK}-${ABI_LABEL}.apk"
# Never replace a release-signed APK (sign-apk.sh re-signs in place) with a debug build.
# apksigner runs `java` from PATH, and JAVA_HOME (found above) need not be on it.
if [ -f "$OUT" ] && ! PATH="$JAVA_HOME/bin:$PATH" "$ANDROID_SDK_ROOT/build-tools/$BUILD_TOOLS/apksigner" \
     verify --print-certs "$OUT" | grep -F 'CN=Android Debug' >/dev/null; then
  die "$OUT is not a debug build (release-signed, or apksigner could not read it); move it away first, or build into another directory with DIST=<dir>"
fi
cp "$APK" "$OUT"

# versionCode: an unknown -P is ignored, so a renamed property upstream would silently bring
# back the wall-clock versionCode.
info "Verifying (minSdk <= $MIN_SDK, $TARGET_ABI Go library present, versionCode $VERSION_CODE)"
if ! python3 "$REPO_ROOT/scripts/verify-apk.py" --require-min-sdk "$MIN_SDK" --require-abi "$TARGET_ABI" \
     --require-version-code "$VERSION_CODE" "$OUT"; then
  rm -f "$OUT"
  die "verification failed — artifact rejected"
fi
( cd "$DIST" && shasum -a 256 "$(basename "$OUT")" > "$(basename "$OUT").sha256" )

echo
bold "Built: $OUT"
bold "sha256: $(cut -d' ' -f1 < "$OUT.sha256")"
cat <<EOF

Install and test:
  adb uninstall com.tailscale.ipn        # debug key differs from any prior install
  adb install "$OUT"
  adb logcat -c
  adb shell am start -n com.tailscale.ipn/.MainActivity
  adb logcat | grep -iE "tailscale|gio|opengl|egl|glerror|fatal|NoSuchMethod|VerifyError"

With an overridden API floor, watch for NoSuchMethodError / NoClassDefFoundError /
VerifyError — those mean the code calls an API newer than $MIN_SDK.
EOF
