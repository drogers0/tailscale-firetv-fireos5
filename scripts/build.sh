#!/usr/bin/env bash
#
# Build Tailscale for Fire OS 5 / Android 5.1 (API 22) on OpenGL ES 2.0 hardware.
#
# Upstream declares minSdkVersion 26 from 2024-03-13 onward, but that bump was a one-line
# decision, not a dependency change (see docs/FINDINGS.md). This script checks out a
# chosen upstream ref and overrides the API floor in both places it is enforced:
#
#   1. android/build.gradle   -> minSdkVersion
#   2. gomobile bind          -> -androidapi   (the native AAR has its own gate)
#
# Overriding only the first produces an APK that installs and then dies in native code.
#
# Usage: ./scripts/build.sh [--patch-only]
#   --patch-only  fetch TS_REF, apply its patch series, then stop. Needs only git (tier 0).
#
# See docs/BUILD.md for prerequisites and TS_REF choices.

set -euo pipefail

# ---- pinned inputs ----------------------------------------------------------
TS_REPO="https://github.com/tailscale/tailscale-android.git"
# Match the documented release and the available API-22 patch series.
TS_REF="${TS_REF:-1.98.8-t1241b225b-gbcbaf1889}"
NDK_VERSION="${NDK_VERSION:-23.1.7779620}"

# ---- tunables ---------------------------------------------------------------
MIN_SDK="${MIN_SDK:-22}"           # device API level
TS_ARCH="${TS_ARCH:-arm}"          # legacy gogio recipe only; empty = every ABI
GOMOBILE_TARGET="${GOMOBILE_TARGET:-android/arm}"   # modern recipe; arm = armeabi-v7a
WORKDIR="${WORKDIR:-.build}"
SKIP_TESTS="${SKIP_TESTS:-1}"
GRADLE_HEAP="${GRADLE_HEAP:-6g}"
PATCH_SERIES="${PATCH_SERIES:-}"   # dir under patches/; default: patches/$TS_REF, then patches/<version>
LINT="${LINT:-0}"                  # 1 = also run Android Lint, NewApi only (scripts/lint-newapi.gradle)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/$WORKDIR/tailscale-android-${TS_REF##*-}"
DIST="$REPO_ROOT/dist"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
java_major() { "$1/bin/java" -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/'; }

PATCH_ONLY=0
case "${1:-}" in
  "") ;;
  --patch-only) PATCH_ONLY=1 ;;
  *) die "usage: $0 [--patch-only]" ;;
esac

# gomobile/gogio arch name -> Android ABI directory name. Used for the artifact
# filename and for the ABI assertion in step 11, so both follow what was built.
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
# Resolved before any fetch, so a bad or missing series fails at once.
info "Preflight  (ref=$TS_REF  minSdk=$MIN_SDK)"
if [ -n "$PATCH_SERIES" ]; then
  PATCHDIR="$REPO_ROOT/patches/$PATCH_SERIES"
  [ -d "$PATCHDIR" ] || die "no patch series patches/$PATCH_SERIES"
else
  PATCHDIR="$REPO_ROOT/patches/$TS_REF"
  [ -d "$PATCHDIR" ] || PATCHDIR="$REPO_ROOT/patches/${TS_REF%%-*}"
fi
if [ "$PATCH_ONLY" = 1 ] && [ ! -d "$PATCHDIR" ]; then
  die "no patch series for $TS_REF; nothing to check"
fi

# ---- 2. checkout ------------------------------------------------------------
command -v git >/dev/null || die "git not found"
if [ ! -d "$SRC/.git" ]; then
  info "Fetching $TS_REF (shallow)"
  mkdir -p "$SRC"
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

# ---- 3. per-ref patches -----------------------------------------------------
# Upstream runs at minSdk 26, so API-guard rot accumulates: calls to APIs newer
# than 22 that upstream can never hit. Each patch here fixes one, and is scoped
# to a single ref so it is obvious what diverges from upstream and why.
if [ -d "$PATCHDIR" ]; then
  n=0
  for p in "$PATCHDIR"/*.patch; do
    [ -e "$p" ] || continue
    if git -C "$SRC" apply --check "$p" 2>/dev/null; then
      git -C "$SRC" apply "$p"
      info "Applied patch: $(basename "$p")"
      n=$((n+1))
    else
      die "patch does not apply to $TS_REF: $(basename "$p")"
    fi
  done
  if [ "$PATCH_ONLY" = 1 ]; then
    [ "$n" -gt 0 ] || die "patches/$(basename "$PATCHDIR") has no *.patch; nothing to check"
    bold "Patch check passed for $TS_REF ($n patches)"
    exit 0
  fi
else
  info "No patches for $TS_REF"
fi

# ---- 4. preflight -----------------------------------------------------------
for c in curl unzip; do command -v $c >/dev/null || die "$c not found"; done

if [ -z "${JAVA_HOME:-}" ]; then
  for c in "$( [ "$(uname)" = Darwin ] && /usr/libexec/java_home -F -v 17 2>/dev/null )" \
           "$HOME"/.local/jdks/jdk-17*/Contents/Home "$HOME"/.local/jdks/jdk-17* \
           /usr/lib/jvm/java-17-openjdk-amd64; do
    if [ -x "$c/bin/java" ] && [ "$(java_major "$c")" = 17 ]; then JAVA_HOME="$c"; break; fi
  done
fi
[ -n "${JAVA_HOME:-}" ] || die "JDK 17 not found. Set JAVA_HOME. See docs/BUILD.md."
export JAVA_HOME
JAVA_MAJOR="$(java_major "$JAVA_HOME")"
[ "$JAVA_MAJOR" = "17" ] || die "JAVA_HOME is JDK $JAVA_MAJOR; AGP needs JDK 17. See docs/BUILD.md."
info "JDK 17: $JAVA_HOME"

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

MISSING=()
[ -d "$ANDROID_SDK_ROOT/ndk/$NDK_VERSION" ]  || MISSING+=("ndk;$NDK_VERSION")
[ -d "$ANDROID_SDK_ROOT/platforms/android-34" ] || MISSING+=("platforms;android-34")
[ -d "$ANDROID_SDK_ROOT/build-tools/34.0.0" ]   || MISSING+=("build-tools;34.0.0")
if [ ${#MISSING[@]} -gt 0 ]; then
  info "Installing SDK packages: ${MISSING[*]}"
  yes 2>/dev/null | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true
  "$SDKMANAGER" "${MISSING[@]}"
else
  info "SDK packages present"
fi
export ANDROID_NDK_HOME="$ANDROID_SDK_ROOT/ndk/$NDK_VERSION"

# ---- 6. Go toolchain --------------------------------------------------------
if [ -x "$SRC/tool/go" ]; then
  GO="$SRC/tool/go"                      # upstream wrapper; fetches its own pinned Go
  info "Using upstream tool/go"
else
  command -v go >/dev/null || die "go not found ($TS_REF has no tool/go)"
  GO="go"
  info "Using system go: $(go version)"
fi

# gomobile shells out to a bare `go`, so the pinned toolchain must win on PATH.
# Otherwise a modern system Go compiles the ref's pinned x/tools and fails with
#   tokeninternal.go: invalid array length -delta * delta
# which looks like a source bug but is really a toolchain mismatch.
GOROOT_PINNED="$( cd "$SRC" && "$GO" env GOROOT 2>/dev/null || true )"
if [ -n "$GOROOT_PINNED" ] && [ -x "$GOROOT_PINNED/bin/go" ]; then
  export PATH="$GOROOT_PINNED/bin:$PATH"
  info "Pinned Go on PATH: $("$GOROOT_PINNED/bin/go" version)"
elif [ "$GO" != go ]; then
  die "tool/go did not yield a toolchain (rerun: cd $SRC && tool/go version)"
else
  warn "could not resolve a pinned GOROOT; gomobile will use whatever go is on PATH"
fi

# ---- 7. apply the API-floor overrides ---------------------------------------
BG="$SRC/android/build.gradle"
CUR_MIN="$(grep -oE 'minSdkVersion +[0-9]+' "$BG" | head -1 | grep -oE '[0-9]+')"
if [ "$CUR_MIN" != "$MIN_SDK" ]; then
  info "Overriding minSdkVersion $CUR_MIN -> $MIN_SDK"
  sed -i.bak -E "s/minSdkVersion +[0-9]+/minSdkVersion $MIN_SDK/" "$BG" && rm -f "$BG.bak"
fi

# getLocalProperty() reads local.properties; absent keys break configuration.
[ -f "$SRC/android/local.properties" ] || cat > "$SRC/android/local.properties" <<EOF
sdk.dir=$ANDROID_SDK_ROOT
githubUsername=
githubPassword=
github2FASecret=
EOF

# ---- 8. tailscale.version ---------------------------------------------------
# Must precede the native build: version-ldflags.sh does `source tailscale.version`,
# and 1.78.0+ build.gradle reads it via getVersionProperty().
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

if [ -d "$SRC/libtailscale" ]; then
  # Modern recipe: gomobile bind. The -androidapi flag is a second, independent
  # API gate — leaving it at 26 yields an APK that installs then dies natively.
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
  LDFLAGS=""
  if [ -x "$SRC/version-ldflags.sh" ]; then
    LDFLAGS="$( cd "$SRC" && ./version-ldflags.sh )" \
      || die "version-ldflags.sh failed; refusing to build an unstamped AAR (it would SIGABRT on launch)"
    case "$LDFLAGS" in
      *version.longStamp=?*) : ;;
      *) die "version-ldflags.sh produced no longStamp; refusing to build an unstamped AAR" ;;
    esac
  fi
  TAGS=""
  if [ -x "$SRC/build-tags.sh" ]; then TAGS="$("$SRC/build-tags.sh" 2>/dev/null || true)"; fi

  GOMOBILE_ARGS=(bind -target "$GOMOBILE_TARGET" -androidapi "$MIN_SDK")
  [ -n "$TAGS" ]    && GOMOBILE_ARGS+=(-tags "$TAGS")
  [ -n "$LDFLAGS" ] && GOMOBILE_ARGS+=(-ldflags "-w $LDFLAGS")
  GOMOBILE_ARGS+=(-o android/libs/libtailscale.aar ./libtailscale)

  ( cd "$SRC" && gomobile "${GOMOBILE_ARGS[@]}" )
  [ -f "$SRC/android/libs/libtailscale.aar" ] || die "libtailscale.aar was not produced"
  info "libtailscale.aar: $(du -h "$SRC/android/libs/libtailscale.aar" | cut -f1)"
else
  # Legacy recipe: gogio archive.
  info "Native: gogio (arch=${TS_ARCH:-all})"
  if [ -n "$TS_ARCH" ]; then TARGET_ABI="$(abi_for "$TS_ARCH")"; ABI_LABEL="$TARGET_ABI"; fi
  VN="$(grep -m1 versionName "$BG" 2>/dev/null | sed -E 's/.*"(.*)".*/\1/' || true)"
  ARCH_FLAG=(); [ -n "$TS_ARCH" ] && ARCH_FLAG=(-arch "$TS_ARCH")
  ( cd "$SRC" && "$GO" run gioui.org/cmd/gogio \
      -ldflags "-X tailscale.com/version.longStamp=$VN -X tailscale.com/version.shortStamp=${VN%%-*}" \
      -buildmode archive -target android "${ARCH_FLAG[@]}" \
      -appid com.tailscale.ipn -tags novulkan,tailscale_go \
      -o android/libs/ipn.aar github.com/tailscale/tailscale-android/cmd/tailscale )
  [ -f "$SRC/android/libs/ipn.aar" ] || die "ipn.aar was not produced"
fi

# ---- 10. gradle -------------------------------------------------------------
GP="$SRC/android/gradle.properties"
grep -q "^org.gradle.parallel" "$GP" 2>/dev/null || printf 'org.gradle.parallel=true\norg.gradle.caching=true\nkotlin.incremental=true\n' >> "$GP"
if grep -q "^org.gradle.jvmargs" "$GP" 2>/dev/null; then
  sed -i.bak -E "s/^org\.gradle\.jvmargs=.*/org.gradle.jvmargs=-Xmx${GRADLE_HEAP} -XX:MaxMetaspaceSize=1g/" "$GP" && rm -f "$GP.bak"
else
  echo "org.gradle.jvmargs=-Xmx${GRADLE_HEAP} -XX:MaxMetaspaceSize=1g" >> "$GP"
fi

# Flavors were removed once Tailscale dropped Play Services; pick whichever exists.
if grep -qi "fdroid" "$BG"; then
  VARIANT=FdroidDebug
  APK_GLOB="$SRC/android/build/outputs/apk/fdroid/debug/*.apk"
else
  VARIANT=Debug
  APK_GLOB="$SRC/android/build/outputs/apk/debug/*.apk"
fi
GRADLE_ARGS=(--no-daemon --continue "assemble$VARIANT")
[ "$SKIP_TESTS" = "1" ] || GRADLE_ARGS+=("test${VARIANT}UnitTest")
if [ "$LINT" = "1" ]; then
  # NewApi only: calls to APIs above MIN_SDK are the bug class this repo patches.
  GRADLE_ARGS+=(-I "$REPO_ROOT/scripts/lint-newapi.gradle" "lint$VARIANT")
  if [ -f "$PATCHDIR/lint.xml" ]; then export TS_LINT_CONFIG="$PATCHDIR/lint.xml"; fi
fi

info "Gradle: ${GRADLE_ARGS[*]}"
( cd "$SRC/android" && ./gradlew "${GRADLE_ARGS[@]}" )

APK="$(ls -1 $APK_GLOB 2>/dev/null | head -1)"
[ -n "$APK" ] && [ -f "$APK" ] || die "no APK produced under $APK_GLOB"

# ---- 11. verify + publish ---------------------------------------------------
mkdir -p "$DIST"
OUT="$DIST/tailscale-fireos5-${TS_REF%%-*}-minsdk${MIN_SDK}-${ABI_LABEL}.apk"
cp "$APK" "$OUT"

info "Verifying (minSdk <= $MIN_SDK, $TARGET_ABI present)"
if ! python3 "$REPO_ROOT/scripts/verify-apk.py" --require-min-sdk "$MIN_SDK" --require-abi "$TARGET_ABI" "$OUT"; then
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
