#!/usr/bin/env bash
#
# Emulator smoke tests for the API 22 patch series, with no tailnet. Boots a fresh
# Android 5.1 (API 22) emulator, installs the `make build-emu` APK, and checks each patch's
# behaviour over adb: logcat, dumpsys, appops, and uiautomator text lookups where a tap is
# unavoidable (never screen coordinates).
#
# Usage: ./scripts/emu-test.sh [apk]    # default: the newest $DIST/*-<emulator ABI>.apk
#
# Environment:
#   EMU_ARCH          amd64 (x86_64 image, CI) or arm64 (arm64-v8a image, Apple Silicon);
#                     default from `uname -m`. `make emu-test` passes the Makefile's value.
#   DIST              where `make build-emu` puts its APK, relative to the repo root;
#                     default .build/dist-emu (under WORKDIR), the same as the Makefile.
#   ANDROID_SDK_ROOT  as for build.sh. Missing emulator packages are installed into it.
#
# The same script runs locally and in CI. It always creates its own AVD (tsfire-api22,
# recreated each run so every run starts logged out with no VPN consent) on its own port,
# and stops that emulator on exit, so other emulators are never touched. Logs go to
# $WORKDIR/emu-test/ (default .build); on failure it also saves a screenshot, a UI dump
# and dumpsys output.

set -euo pipefail

# ---- pinned inputs (CI keys its emulator cache on these two lines) ----------
EMU_API=22
EMU_TAG=google_apis   # the only API 22 image family with both x86_64 and arm64-v8a builds

# ---- fixed settings ---------------------------------------------------------
AVD=tsfire-api22
PORT=5584             # serial emulator-5584; away from the default 5554 a developer uses
PKG=com.tailscale.ipn
BOOT_TIMEOUT=300

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO_ROOT/${WORKDIR:-.build}/emu-test"
DIST="$REPO_ROOT/${DIST:-${WORKDIR:-.build}/dist-emu}"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
pass() { printf '\033[32mPASS\033[0m %s\n' "$*"; }

case "${EMU_ARCH:-$(uname -m)}" in
  amd64|x86_64)  ABI=x86_64 ;;
  arm64|aarch64) ABI=arm64-v8a ;;
  *) die "unsupported EMU_ARCH '${EMU_ARCH:-$(uname -m)}' — want amd64 or arm64" ;;
esac
IMAGE="system-images;android-$EMU_API;$EMU_TAG;$ABI"

APK="${1:-}"
if [ -z "$APK" ]; then
  for f in "$DIST"/*-"$ABI".apk; do
    if [ -e "$f" ] && { [ -z "$APK" ] || [ "$f" -nt "$APK" ]; }; then APK="$f"; fi
  done
fi
[ -f "$APK" ] || die "no $DIST/*-$ABI.apk; run make build-emu first"

if [ -z "${ANDROID_SDK_ROOT:-}" ]; then
  if [ "$(uname)" = "Darwin" ]; then ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
  else ANDROID_SDK_ROOT="$HOME/Android/Sdk"; fi
fi
SDK="$ANDROID_SDK_ROOT"
# The emulator and avdmanager read ANDROID_HOME first; CI runners preset it to another SDK.
export ANDROID_SDK_ROOT ANDROID_HOME="$SDK"
TOOLS="$SDK/cmdline-tools/latest/bin"
[ -x "$TOOLS/sdkmanager" ] || die "no SDK command-line tools in $SDK; run make build-emu first"

# ---- 1. APK checks (no emulator) --------------------------------------------
info "APK: $APK"
# Installable on this emulator: minSdk and the Go library for its ABI.
python3 "$REPO_ROOT/scripts/verify-apk.py" --require-min-sdk "$EMU_API" --require-abi "$ABI" "$APK" \
  || die "$APK does not fit the API $EMU_API $ABI emulator"
# 0007: java.time is API 26; core library desugaring rewrites it to j$.time. The paths
# that call it (key expiry) need a netmap, so at this tier the check is on the dex.
n="$(unzip -p "$APK" 'classes*.dex' | LC_ALL=C grep -ac 'Lj\$/time/')" || true
[ "${n:-0}" -gt 0 ] || die "0007: no desugared j\$.time classes in the dex"
pass "0007 java.time is desugared (j\$.time in the dex)"

# ---- 2. emulator packages and AVD -------------------------------------------
MISSING=()
[ -x "$SDK/platform-tools/adb" ]   || MISSING+=("platform-tools")
[ -x "$SDK/emulator/emulator" ]    || MISSING+=("emulator")
[ -d "$SDK/system-images/android-$EMU_API/$EMU_TAG/$ABI" ] || MISSING+=("$IMAGE")
if [ ${#MISSING[@]} -gt 0 ]; then
  info "Installing SDK packages: ${MISSING[*]}"
  yes 2>/dev/null | "$TOOLS/sdkmanager" --licenses >/dev/null 2>&1 || true
  "$TOOLS/sdkmanager" "${MISSING[@]}"
fi

export ANDROID_SERIAL="emulator-$PORT"
adb() { "$SDK/platform-tools/adb" "$@"; }

if adb devices | grep -E "^${ANDROID_SERIAL}[[:space:]]+device$" >/dev/null; then
  die "$ANDROID_SERIAL is already running; stop it first (adb -s $ANDROID_SERIAL emu kill)"
fi
rm -rf "$OUT"; mkdir -p "$OUT"
echo no | "$TOOLS/avdmanager" create avd -n "$AVD" -k "$IMAGE" -d pixel --force > "$OUT/avdmanager.log" 2>&1 \
  || die "avdmanager failed; see $OUT/avdmanager.log"

# ---- helpers ----------------------------------------------------------------
# Pipelines below never use grep -q: with pipefail, an early grep exit makes the writer
# die of SIGPIPE and turns a match into a failure.
log()     { adb logcat -d -b all -v threadtime 2>/dev/null; }    # this boot only
app_lines() {  # app_lines < DUMP: the lines logged by the app's processes; fails if it has none
  local l pids
  l="$(cat)"
  pids="$(printf '%s\n' "$l" | grep -oE "Start proc [0-9]+:$PKG/" | grep -oE '[0-9]+' | paste -sd '|' - || true)"
  [ -n "$pids" ] || return 1
  printf '%s\n' "$l" | awk -v re="^($pids)\$" '$3 ~ re'
}
app_log() { log | app_lines; }   # this boot
SCAN=0        # 1 while the app runs: every wait then also fails fast on a crash
no_crash() {  # die on a crash, a native fatal signal, a failed worker or a missing API
  local l a hits
  l="$(log)" || die "$1: adb logcat failed"   # one snapshot per call
  # Checked here, not in app_lines: a die inside $(...) or a pipeline ends only that subshell.
  a="$(printf '%s\n' "$l" | app_lines)" || die "$1: no $PKG process in this boot's log"
  hits="$(printf '%s\n' "$a" | awk '
    $5 ~ /^[WEF]$/ && /FATAL EXCEPTION|Fatal signal|failed because it threw|NoSuchMethodError|NoClassDefFoundError|VerifyError/ { print; n = 2; next }
    n-- > 0' || true)"
  hits+="${hits:+$'\n'}$(printf '%s\n' "$l" | grep -E "ANR in $PKG|Process $PKG \(pid [0-9]+\) has died" || true)"
  [ -z "$hits" ] || { printf '%s\n' "$hits" | head -20 >&2; die "$1: the app crashed or hit a missing API"; }
}
wait_for() {  # wait_for SECONDS DESCRIPTION CMD...: retry CMD once a second
  local t="$1" what="$2" end=$((SECONDS + $1)); shift 2
  until { [ "$SCAN" = 0 ] || no_crash "$what"; } && "$@"; do
    [ "$SECONDS" -lt "$end" ] || die "timed out after ${t}s waiting for: $what"
    sleep 1
  done
}
app_logged() { app_log | grep -E -- "$1" >/dev/null; }
logged()     { log | grep -E -- "$1" >/dev/null; }      # any process
wait_log()   { wait_for "${3:-30}" "$1" app_logged "$2"; }    # DESCRIPTION REGEX [SECONDS]
booted() {
  kill -0 "$EMU_PID" 2>/dev/null || die "emulator exited; see $OUT/emulator.log"
  [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]
}
boot_id()  { adb shell cat /proc/sys/kernel/random/boot_id 2>/dev/null | tr -d '\r' || true; }
rebooted() { local id; id="$(boot_id)"; [ -n "$id" ] && [ "$id" != "$1" ]; }
focused()  { adb shell dumpsys activity activities | grep -E "mFocusedActivity: .*$1" >/dev/null; }
ui_dump()  {   # /sdcard is not mounted on these images; uiautomator then writes nothing
  # API 22's adb shell always exits 0, and a failed dump ("could not get idle state") leaves
  # the previous file, so delete it first and accept only a complete hierarchy.
  local f=/data/local/tmp/ui.xml x
  adb shell rm -f "$f"
  adb shell uiautomator dump "$f" >/dev/null
  x="$(adb exec-out cat "$f")"
  case "$x" in *'</hierarchy>'*) printf '%s\n' "$x" ;; *) return 1 ;; esac
}
ui_has()   { ui_dump | grep -F "text=\"$1\"" >/dev/null; }
tap_text() {   # tap the centre of the first node whose text is one of the arguments
  local ui t b end=$((SECONDS + 15))
  while :; do   # a window can take focus before its views are laid out
    ui="$(ui_dump | tr '>' '\n')" || true   # an incomplete dump is retried below
    for t in "$@"; do
      b="$(printf '%s\n' "$ui" | grep -F "text=\"$t\"" | grep -oE 'bounds="[^"]*"' | head -1 | tr -c '0-9' ' ')" || true
      if [ -n "$b" ]; then
        # shellcheck disable=SC2086  # split the four bounds numbers
        set -- $b   # x1 y1 x2 y2
        adb shell input tap $(( ($1 + $3) / 2 )) $(( ($2 + $4) / 2 ))
        return 0
      fi
    done
    [ "$SECONDS" -lt "$end" ] || die "none of [$*] on screen after 15s; visible: $(printf '%s\n' "$ui" | grep -oE 'text="[^"]+"' | head -10 | paste -sd ' ' -)"
    sleep 1
  done
}
notified() { adb shell dumpsys notification | grep -E "NotificationRecord\(.*pkg=$PKG .*flags=0x10 " >/dev/null; }
ipn_foreground() {
  adb shell dumpsys activity services "$PKG/.IPNService" | awk '
    /ServiceRecord\{.*com\.tailscale\.ipn\/\.IPNService/ { f = 1; next }
    /ServiceRecord\{/ { f = 0 }
    f && /isForeground=true/ { ok = 1 }
    END { exit !ok }'
}
default_net() { app_log | grep -oE 'cachedDefaultNetwork=[0-9]+' | tail -1 | grep -oE '[0-9]+' || true; }
new_default_net() { local n; n="$(default_net)"; [ -n "$n" ] && [ "$n" != "$1" ]; }

reboot_app() {  # reboot_app LABEL: save this boot's log, reboot, wait until the app starts
  local id t0
  log > "$OUT/logcat-boot$BOOT.txt"
  id="$(boot_id)"
  [ -n "$id" ] || die "$1: could not read boot_id"
  SCAN=0
  adb shell svc power reboot  # a runtime shutdown flushes appops; adb reboot does not
  BOOT=$((BOOT + 1)); t0=$SECONDS
  wait_for 120 "$1: the reboot" rebooted "$id"
  wait_for "$BOOT_TIMEOUT" "$1: boot after reboot" booted
  info "Rebooted in $((SECONDS - t0))s"
  adb logcat -G 4M
  wait_for 60 "$1: the app started at boot" logged "Start proc [0-9]+:$PKG/"
  SCAN=1
}

finish() {
  local rc=$?
  if [ "$rc" != 0 ] && [ -n "${EMU_PID:-}" ]; then
    log > "$OUT/logcat-boot$BOOT.txt" || true
    adb exec-out screencap -p > "$OUT/screen.png" 2>/dev/null || true
    ui_dump > "$OUT/ui.xml" 2>/dev/null || true
    { adb shell dumpsys activity services "$PKG"; adb shell dumpsys notification; } \
      > "$OUT/dumpsys.txt" 2>/dev/null || true
    info "Failure logs in $OUT"
  fi
  if [ -n "${EMU_PID:-}" ] && kill -0 "$EMU_PID" 2>/dev/null; then
    adb emu kill >/dev/null 2>&1 || kill "$EMU_PID" 2>/dev/null || true
    wait "$EMU_PID" 2>/dev/null || true
  fi
  exit "$rc"
}
trap finish EXIT

# ---- 3. boot and install ----------------------------------------------------
info "$("$SDK/emulator/emulator" -version 2>/dev/null | sed -n 1p)"
info "Booting $AVD ($IMAGE) as $ANDROID_SERIAL"
BOOT=1; t0=$SECONDS
"$SDK/emulator/emulator" -avd "$AVD" -port "$PORT" -no-window -no-audio -no-boot-anim \
  -no-snapshot -gpu swiftshader_indirect > "$OUT/emulator.log" 2>&1 &
EMU_PID=$!
wait_for "$BOOT_TIMEOUT" "boot" booted
info "Booted in $((SECONDS - t0))s"
adb logcat -G 4M        # keep the whole boot in the ring buffer; reset by every reboot
adb install "$APK" >/dev/null
adb shell pm path "$PKG" | grep -F 'package:' >/dev/null || die "install of $APK failed"

# ---- 4. checks, in an order where each leaves the state the next needs -------
# 0011 + 0006: CONNECT_VPN before any launch (logged out, no consent) runs StartVPNWorker
# through WorkManager, which must post the "open Tailscale" notification.
adb shell am broadcast -a "$PKG.CONNECT_VPN" -n "$PKG/.IPNReceiver" >/dev/null
SCAN=1
wait_log "0011/0006 StartVPNWorker to run" "Worker result FAILURE for Work .*StartVPNWorker"
wait_for 10 "0011 the 'open Tailscale' notification" notified
pass "0011 CONNECT_VPN without consent posts the notification; 0006 worker runs"

# 0002 + 0010: launch; the network callback must pick a default network at startup.
adb shell am start -n "$PKG/.MainActivity" >/dev/null   # no -W: it never returns if launch crashes
wait_log "0010 initial default network" "onAvailable: cachedDefaultNetwork=[0-9]+ iface=[a-z0-9]+"
pass "0002 launch without missing-API errors; 0010 default network $(default_net) at startup"

# 0009: the first launch asks for VPN consent; cancelling it must show the app's dialog.
wait_for 30 "the VPN consent dialog" focused "com.android.vpndialogs/.ConfirmDialog"
tap_text Cancel                                   # this dialog ignores the back key
wait_log "0009 consent denial handled" "VpnPermission: Permission was denied by the user"
wait_for 15 "0009 'VPN permission needed' dialog" ui_has "VPN permission needed"
pass "0009 consent denied: 'VPN permission needed', no crash"
tap_text Cancel

# 0010: losing the network and getting a new one must move the default network.
old="$(default_net)"
[ -n "$old" ] || die "0010: no default network logged before the data toggle"
adb shell svc data disable
wait_log "network $old lost" "onLost: network $old"
adb shell svc data enable
wait_for 60 "0010 a new default network" new_default_net "$old"
pass "0010 data off/on: default network $old -> $(default_net)"

# 0001 + 0003: grant consent through appops (what the dialog's OK does), then start the
# login flow, which runs IPNService as a foreground service with its notification.
adb shell appops set "$PKG" ACTIVATE_VPN allow
tap_text "Get Started" "Connect"
wait_for 30 "0001/0003 IPNService in the foreground" ipn_foreground
no_crash "0001/0003"        # a crash right after the service went foreground
pass "0001 0003 IPNService is foreground"
adb shell input keyevent KEYCODE_HOME             # leave the login page it opened

# 0008: reboot while logged out, with consent. BootReceiver must decide to stay
# disconnected (WantRunning=false), with no crash and no tunnel.
reboot_app 0008
wait_log "0008 BootReceiver's decision" "BootReceiver: boot: WantRunning=false; staying disconnected" 60
adb shell netcfg | grep -E '^tun0 ' >/dev/null && die "0008: tun0 is up while logged out"
no_crash 0008
pass "0008 reboot while logged out: BootReceiver stays disconnected, no crash, no tunnel"
log > "$OUT/logcat-boot$BOOT.txt"

bold "Emulator smoke tests passed in ${SECONDS}s"
