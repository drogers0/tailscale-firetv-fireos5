#!/usr/bin/env bash
#
# Emulator smoke tests for the API 22 patch series, with no tailnet (EMU_NET=1 adds a real
# tailnet). Boots a fresh Android 5.1 (API 22) emulator, installs the `make build-emu` APK,
# and checks each patch's behaviour over adb: logcat, dumpsys, appops, and uiautomator text
# lookups where a tap is unavoidable (never screen coordinates for taps; list scrolls are
# slow drags inside the list's own bounds from the UI dump).
#
# Usage: [EMU_NET=1] ./scripts/emu-test.sh [apk]    # default: the newest $DIST/*-<emulator ABI>.apk
#
# Environment:
#   EMU_ARCH          amd64 (x86_64 image, CI) or arm64 (arm64-v8a image, Apple Silicon);
#                     default from `uname -m`. `make emu-test` passes the Makefile's value.
#   DIST              where `make build-emu` puts its APK (relative paths are from the repo
#                     root); default .build/dist-emu (under WORKDIR), the same as the Makefile.
#   ANDROID_SDK_ROOT  as for build.sh. Missing emulator packages are installed into it.
#   EMU_NET           1 = afterwards, log in to a real tailnet and run the tier 3 checks
#                     (make emu-test-net). Then also:
#   TS_AUTHKEY        EMU_NET=1: the emulator's auth key (tagged, ephemeral; docs/TESTING.md)
#   TAILSCALE         EMU_NET=1: this host's tailscale CLI, if not `tailscale` on PATH. The
#                     host must be on the same tailnet: the checks ping the emulator from it.
#
# The same script runs locally and in CI. It always creates its own AVD (tsfire-api22,
# recreated each run so every run starts logged out with no VPN consent; with EMU_NET=1 it
# is also deleted at exit) on its own port, and stops that emulator on exit, so other
# emulators are never touched. Logs go to $WORKDIR/emu-test/ (default .build); on failure
# it also saves a screenshot, a UI dump and dumpsys output.

set -euo pipefail

# ---- pinned inputs (CI keys its emulator cache on these two lines) ----------
EMU_API=22
EMU_TAG=google_apis   # the only API 22 image family with both x86_64 and arm64-v8a builds

# ---- fixed settings ---------------------------------------------------------
AVD=tsfire-api22
PORT=5584             # serial emulator-5584; away from the default 5554 a developer uses
PKG=com.tailscale.ipn
BOOT_TIMEOUT=300
NET="${EMU_NET:-0}"   # 1 = tier 3, on a real tailnet

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO_ROOT/${WORKDIR:-.build}/emu-test"
DIST="${DIST:-${WORKDIR:-.build}/dist-emu}"
case "$DIST" in /*) ;; *) DIST="$REPO_ROOT/$DIST" ;; esac

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
pass() { printf '\033[32mPASS\033[0m %s\n' "$*"; }

EMU_ARCH="${EMU_ARCH:-$(uname -m)}"
case "$EMU_ARCH" in
  amd64|x86_64)  ABI=x86_64 ;;
  arm64|aarch64) ABI=arm64-v8a ;;
  *) die "unsupported EMU_ARCH '$EMU_ARCH' — want amd64 or arm64" ;;
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

# ---- 1b. tailnet preflight (EMU_NET=1) --------------------------------------
# Validation only, before the first adb call, so no adb server is forked with the key in
# its environment.
if [ "$NET" = 1 ]; then
  [ -n "${TS_AUTHKEY:-}" ] || die "EMU_NET=1 needs TS_AUTHKEY (environment, or .env for make emu-test-net; check .env's syntax)"
  [[ "$TS_AUTHKEY" =~ ^tskey-auth-[A-Za-z0-9_-]+$ ]] || die "TS_AUTHKEY is not a tskey-auth-… key"
  export -n TS_AUTHKEY        # a shell variable from here on: no child process inherits it
  ts() { "${TAILSCALE:-tailscale}" "$@"; }   # this host's CLI; tier 3 only
  HOST_IP="$(ts ip -4 2>/dev/null | head -1)" || true
  [ -n "$HOST_IP" ] || die "this host is not on a tailnet (or set TAILSCALE to its CLI)"
  st="$(ts status --json 2>/dev/null)" || die "'tailscale status --json' failed on this host"
  # 0007: java.time runs where the app formats a key expiry. Tagged nodes, like the emulator,
  # never expire, so pick this host, or else a peer, whose key does. Mullvad nodes
  # (Location) are not listed by the app, and sharee nodes are not visible to a tagged node.
  # The IP is used to find the node on the emulator and is never printed.
  read -r T0007 T0007_WHO < <(printf '%s' "$st" | python3 -I -c '
import json, sys
s = json.load(sys.stdin)
for who, n in [("host", s["Self"])] + [("a peer", p) for p in (s.get("Peer") or {}).values()]:
    ips = [i for i in n.get("TailscaleIPs") or [] if "." in i]
    if n.get("KeyExpiry") and ips and not n.get("Location") and not n.get("ShareeNode"):
        print(ips[0], who)
        break') || true
  [ -n "${T0007:-}" ] || die "no node with an expiring key is visible from this host; enable key expiry for this machine in the admin console (0007 needs one)"
fi

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
# Every adb call is bounded: an `adb shell` to an emulator that is not up yet can block
# forever, and then no wait_for deadline (BOOT_TIMEOUT included) ever fires. perl's alarm
# survives exec, so adb itself gets SIGALRM (exit 142) and stays in the foreground.
# SIGALRM is reset in case the caller ignores it; stdin is /dev/null because `adb shell` on API 22
# would forward it to the device.
ADB_TIMEOUT=30        # seconds per call; adb install passes its own
adb() {
  local rc=0
  perl -e '$SIG{ALRM} = "DEFAULT"; alarm shift; exec @ARGV or die "exec $ARGV[0]: $!\n"' \
    "$ADB_TIMEOUT" "$SDK/platform-tools/adb" "$@" </dev/null || rc=$?
  [ "$rc" != 142 ] || printf 'adb %s: no answer in %ss; killed\n' "$1" "$ADB_TIMEOUT" >&2
  return "$rc"
}

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
no_crash() {  # die on a crash, a native fatal signal, a failed worker, a missing API or a dropped IPN notification
  local l a hits
  l="$(log)" || die "$1: adb logcat failed"   # one snapshot per call
  # Checked here, not in app_lines: a die inside $(...) or a pipeline ends only that subshell.
  a="$(printf '%s\n' "$l" | app_lines)" || die "$1: no $PKG process in this boot's log"
  hits="$(printf '%s\n' "$a" | awk '
    $5 ~ /^[WEF]$/ && /FATAL EXCEPTION|Fatal signal|failed because it threw|failed to process IPN notification|NoSuchMethodError|NoClassDefFoundError|VerifyError/ { print; n = 2; next }
    n-- > 0' || true)"
  hits+="${hits:+$'\n'}$(printf '%s\n' "$l" | grep -E "ANR in $PKG|Process $PKG \(pid [0-9]+\) has died" || true)"
  [ -z "$hits" ] || { printf '%s\n' "$hits" | head -20 >&2; die "$1: the app crashed, hit a missing API or dropped an IPN notification"; }
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
    if [ "$SECONDS" -ge "$end" ]; then
      # In net mode the screen lists tailnet devices and the target may be a peer's IP: keep
      # both out of logs that may be shared.
      [ "$NET" != 1 ] || die "the expected text is not on screen after 15s; see $OUT/ui.xml"
      die "none of [$*] on screen after 15s; visible: $(printf '%s\n' "$ui" | grep -oE 'text="[^"]+"' | head -10 | paste -sd ' ' -)"
    fi
    sleep 1
  done
}
notified() { adb shell dumpsys notification | grep -E "NotificationRecord\(.*pkg=$PKG .*flags=0x10 " >/dev/null; }
ipn_foreground() {
  adb shell dumpsys activity services "$PKG/.IPNService" | awk -v svc="$PKG/.IPNService" '
    /ServiceRecord\{/ && index($0, svc) { f = 1; next }
    /ServiceRecord\{/ { f = 0 }
    f && /isForeground=true/ { ok = 1 }
    END { exit !ok }'
}
ifaces() {   # netcfg; adb shell exits 0 even on failure (empty output), so require the lo line
  local nc
  nc="$(adb shell netcfg | tr -d '\r')"
  printf '%s\n' "$nc" | grep -E '^lo ' >/dev/null || return 1
  printf '%s\n' "$nc"
}
default_net() { app_log | grep -oE 'cachedDefaultNetwork=[0-9]+' | tail -1 | grep -oE '[0-9]+' || true; }
new_default_net() { local n; n="$(default_net)"; [ -n "$n" ] && [ "$n" != "$1" ]; }
data_toggle() {  # data_toggle LABEL: mobile data off and on; sets old and waits for a new default network
  old="$(default_net)"
  [ -n "$old" ] || die "$1: no default network logged before the data toggle"
  adb shell svc data disable
  wait_log "network $old lost" "onLost: network $old"
  adb shell svc data enable
  wait_for 60 "$1 a new default network" new_default_net "$old"
}

# Tier 3 (EMU_NET=1).
last_state() { grep -oE 'Switching ipn state [A-Za-z]+ -> [A-Za-z]+' | tail -1 | awk '{print $NF}'; }   # stdin: app log
in_state() {   # in_state STATE: the last ipn state switch this boot is to STATE
  local a; a="$(app_log)" || die "ipn state: no $PKG process in this boot's log"
  [ "$(printf '%s\n' "$a" | last_state)" = "$1" ]
}
running() {    # Running; die at once, with a fixed message, if control rejected the key
  local a; a="$(app_log)" || die "login: no $PKG process in this boot's log"
  # Fixed message: the server's text can include a key ID.
  printf '%s\n' "$a" | grep -E 'Received error: (invalid key|register request: http 4[0-9]{2})' >/dev/null \
    && die "control rejected TS_AUTHKEY (expired, revoked or already used?)"
  [ "$(printf '%s\n' "$a" | last_state)" = Running ]
}
policy_reads() { local a; a="$(app_log)" || die "login: no $PKG process in this boot's log"; printf '%s\n' "$a" | grep -c 'setting opts.AuthKey by syspolicy' || true; }
more_reads() { local n; n="$(policy_reads)" || exit 1; [ "$n" -gt "$1" ]; }   # policy_reads printed why
tun_ip() {     # the tailnet address of an UP tunN, if any; fails if netcfg gave no output
  # Not just tun0: each establish() makes a new tunN, and upstream (from 1.104.5) calls it twice
  # in a row when it connects, so the tunnel can be tun1 while a superseded tun0 lingers.
  local nc; nc="$(ifaces)" || return 1
  printf '%s\n' "$nc" | awk '$1 ~ /^tun[0-9]+$/ && $2 == "UP" && $3 ~ /^100\./ { split($3, a, "/"); print a[1]; exit }'
}
tun_up()     { local ip; ip="$(tun_ip)" || return 1; [ -n "$ip" ]; }
tun_down()   { local ip; ip="$(tun_ip)" || return 1; [ -z "$ip" ]; }
is_root()    { adb shell id 2>/dev/null | grep -F 'uid=0(' >/dev/null; }
dev_ok() {     # dev_ok CMD: CMD succeeded on the device (adb shell exits 0 on API 22; restorecon chats)
  [ "$(adb shell "($1) >/dev/null 2>&1 && echo ok" 2>/dev/null | tr -d '\r')" = ok ]
}
reachable()  { ts ping --icmp -c 1 --timeout 5s "$1" >/dev/null 2>&1; }            # host -> emulator
emu_reaches() { adb shell ping -c 3 -W 5 "$1" | grep -E ' [1-9][0-9]* received' >/dev/null; }
list_box() {   # stdin: a UI dump. Prints "x top bottom" of the first scrollable node (the list)
  tr '>' '\n' | grep -F 'scrollable="true"' | head -1 | grep -oE 'bounds="[^"]*"' \
    | tr -c '0-9' ' ' | awk '{ print int(($1 + $3) / 2), $2, $4 }'
}
swipe()      { adb shell input swipe "$1" "$2" "$1" "$3" 1500; }   # X FROM_Y TO_Y: a slow drag, no fling
scroll_to() {  # scroll_to SECONDS REGEX: from the top of the list, scroll down until a node text matches
  local end=$((SECONDS + $1)) ui prev='' x t b
  while [ "$SECONDS" -lt "$end" ]; do             # up to the top: until a drag changes nothing
    ui="$(ui_dump)" || { sleep 1; continue; }     # a failed dump: retry, never swipe blind
    [ "$ui" != "$prev" ] || break
    prev="$ui"
    read -r x t b < <(printf '%s' "$ui" | list_box) || break   # nothing scrollable: already all shown
    swipe "$x" $((t + (b - t) / 5)) $((b - (b - t) / 10))
  done
  prev=
  while [ "$SECONDS" -lt "$end" ]; do             # down, 60% of the list's height per drag
    ui="$(ui_dump)" || { sleep 1; continue; }
    printf '%s' "$ui" | grep -E "text=\"($2)\"" >/dev/null && return 0
    [ "$ui" != "$prev" ] || return 1              # unchanged after a drag: the end of the list
    prev="$ui"
    read -r x t b < <(printf '%s' "$ui" | list_box) || return 1
    swipe "$x" $((b - (b - t) / 5)) $((t + (b - t) / 5))
  done
  return 1
}

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
  local ADB_TIMEOUT=10   # after an adb hang, every diagnostic call below would hang as well
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
    for _ in {1..30}; do kill -0 "$EMU_PID" 2>/dev/null || break; sleep 1; done
    if kill -0 "$EMU_PID" 2>/dev/null; then kill -9 "$EMU_PID" 2>/dev/null || true; fi   # still up after 30 s
    wait "$EMU_PID" 2>/dev/null || true
  fi
  if [ "$NET" = 1 ]; then
    rm -rf "${KEYDIR:-}"
    "$TOOLS/avdmanager" delete avd -n "$AVD" >/dev/null 2>&1 \
      || echo "warning: could not delete AVD $AVD, whose disk holds TS_AUTHKEY; run: avdmanager delete avd -n $AVD" >&2
    # syspolicy logs restriction values at [v2]; logtail keeps that out of logcat, but a policy
    # read before the backend's log setup would land there. Scrub every saved file.
    TS_AUTHKEY="$TS_AUTHKEY" python3 -I - "$OUT" <<'PY' || rc=1
import os, pathlib, sys
k = os.environ["TS_AUTHKEY"].encode()
for p in pathlib.Path(sys.argv[1]).rglob("*"):
    if p.is_file() and k in (b := p.read_bytes()):
        p.write_bytes(b.replace(k, b"<TS_AUTHKEY redacted>"))
        print(f"warning: redacted TS_AUTHKEY from {p}", file=sys.stderr)
PY
  fi
  exit "$rc"
}
trap finish EXIT

# ---- 3. boot and install ----------------------------------------------------
# From the package metadata: on Linux, `emulator -version` prints nothing to stdout.
info "Emulator $(sed -n 's/^Pkg.Revision=//p' "$SDK/emulator/source.properties")"
info "Booting $AVD ($IMAGE) as $ANDROID_SERIAL"
BOOT=1; t0=$SECONDS
# -partition-size (MB): the default 800 MB /data fills up during dex2oat on the x86_64 image.
"$SDK/emulator/emulator" -avd "$AVD" -port "$PORT" -no-window -no-audio -no-boot-anim \
  -no-snapshot -gpu swiftshader_indirect -partition-size 2048 > "$OUT/emulator.log" 2>&1 &
EMU_PID=$!
wait_for "$BOOT_TIMEOUT" "boot" booted
info "Booted in $((SECONDS - t0))s"
adb logcat -G 4M        # keep the whole boot in the ring buffer; reset by every reboot
r="$(ADB_TIMEOUT=300 adb install "$APK" 2>&1)" || true
adb shell pm path "$PKG" | grep -F 'package:' >/dev/null || die "install of $APK failed: $(printf '%s\n' "$r" | tail -1)"

# ---- 4. checks, in an order where each leaves the state the next needs -------
# 0011: CONNECT_VPN before any launch (logged out, no consent) runs StartVPNWorker through
# WorkManager, which must post the "open Tailscale" notification. It is expedited work: below
# API 31 that runs in WorkManager's foreground service and calls getForegroundInfo(), which
# upstream implements from 1.104.5 (1.98.8 needed patch 0006 to avoid this path).
adb shell am broadcast -a "$PKG.CONNECT_VPN" -n "$PKG/.IPNReceiver" >/dev/null
SCAN=1
wait_log "0011 expedited work in WorkManager's foreground service" "WM-SystemFgDispatcher: Started foreground service"
wait_log "0011 StartVPNWorker to run" "Worker result FAILURE for Work .*StartVPNWorker"
wait_for 10 "0011 the 'open Tailscale' notification" notified
pass "0011 CONNECT_VPN without consent posts the notification; expedited worker ran in the foreground service"

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
data_toggle 0010
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
tun_down || die "0008: a tunnel is up while logged out (or netcfg failed)"
no_crash 0008
pass "0008 reboot while logged out: BootReceiver stays disconnected, no crash, no tunnel"
log > "$OUT/logcat-boot$BOOT.txt"

# ---- 5. tier 3: a real tailnet (EMU_NET=1) -----------------------------------
if [ "$NET" = 1 ]; then
  info "Tier 3: logging in (host $HOST_IP)"
  # The AuthKey app restriction, as an MDM would set it. API 22 keeps restrictions in this file
  # and re-reads it on every query; only root can write it.
  RES="/data/system/users/0/res_$PKG.xml"
  SCAN=0                                          # adbd restarts as root
  adb root >/dev/null 2>&1 || true
  wait_for 30 "adb as root" is_root
  SCAN=1
  KEYDIR="$(mktemp -d)"
  ( umask 077
    printf '<?xml version="1.0" encoding="utf-8" standalone="yes" ?>\n<restrictions>\n<entry key="AuthKey" type="s">%s</entry>\n</restrictions>\n' \
      "$TS_AUTHKEY" > "$KEYDIR/res.xml" )
  adb push "$KEYDIR/res.xml" /data/local/tmp/res.xml >/dev/null 2>&1 || die "adb push of the AuthKey restriction failed"
  rm -rf "$KEYDIR"
  dev_ok "mv /data/local/tmp/res.xml $RES && chown system:system $RES && chmod 600 $RES && restorecon $RES" \
    || die "could not install the AuthKey restriction"
  # A fresh process loads restrictions before the Go backend starts (App.initializeApp).
  adb shell am force-stop "$PKG"
  adb shell am start -n "$PKG/.MainActivity" >/dev/null   # no -W: it never returns if launch crashes
  wait_for 30 "the Log in button" ui_has "Log in"
  n="$(policy_reads)" || exit 1
  tap_text "Log in"
  wait_for 30 "login to take the key from the AuthKey restriction" more_reads "$n"
  wait_for 90 "state Running" running
  wait_for 30 "a tun interface with a tailnet address" tun_up
  EMU_IP="$(tun_ip)" || die "login: netcfg failed"
  dev_ok "rm $RES && [ ! -e $RES ]" || die "could not remove the AuthKey restriction"
  pass "login with an auth key: Running, tunnel $EMU_IP"

  # 0004: below API 23 the app's own sockets stay out of its tunnel through VpnService.protect().
  al="$(app_log)" || die "0004: no $PKG process in this boot's log"
  printf '%s\n' "$al" | grep -E 'VpnService\.protect\(fd=[0-9]+\) -> true' >/dev/null || die "0004: no protected socket"
  printf '%s\n' "$al" | grep -E 'VpnService\.protect\(fd=[0-9]+\) -> false' >/dev/null && die "0004: protect() failed"
  wait_for 60 "host -> emulator over the tailnet" reachable "$EMU_IP"
  emu_reaches "$HOST_IP" || die "emulator cannot reach the host $HOST_IP over the tailnet"
  no_crash 0004
  pass "0004 sockets protected; tunnel traffic both ways"

  # 0005: the first PeersChanged update, which carries every peer (InitialStatus arrives before
  # Running, with none), decodes: the debug build logs it only after a successful decode, and
  # no_crash fails on 'failed to process IPN notification'. The peer list is built from it.
  wait_log "0005 the first PeersChanged update decoded" "received bus update: .*peersChanged=[1-9]"
  wait_for 30 "0005 this device in the peer list" ui_has "$EMU_IP"
  pass "0005 peer list decoded (PeersChanged)"

  # 0007: peer details format a key expiry with java.time (TimeUtil).
  wait_for 90 "the 0007 target in the emulator's peer list (can tag:fireos-ci see the expiring node this host sees?)" \
    scroll_to 40 "${T0007//./\\.}"
  tap_text "$T0007"
  exp='in [0-9.]+ (minutes|hours|days|months|years)|under a minute|[0-9.]+ (minutes|hours|days|months|years) ago'
  wait_for 40 "0007 a formatted key expiry in its details" scroll_to 15 "$exp"
  pass "0007 java.time at runtime: key expiry of $T0007_WHO formatted"
  adb shell input keyevent KEYCODE_BACK

  # 0010: a network change while connected; the tunnel must follow the new network.
  data_toggle 0010
  wait_for 60 "host -> emulator after the network change" reachable "$EMU_IP"
  tun_up || die "0010: the tunnel is gone after the network change (or netcfg failed)"
  pass "0010 network change while connected: $old -> $(default_net), tunnel kept"

  # 0008: reboot while connected. BootReceiver restarts the VPN without the app being opened.
  reboot_app "0008 connected"
  wait_log "0008 BootReceiver reconnecting" "BootReceiver: boot: WantRunning=true" 60
  wait_for 90 "state Running after boot" in_state Running
  wait_for 30 "the tunnel after boot" tun_up
  ip="$(tun_ip)" || die "0008: netcfg failed"
  [ "$ip" = "$EMU_IP" ] || die "0008: tailnet address changed across the reboot"
  wait_for 60 "host -> emulator after boot" reachable "$EMU_IP"
  pass "0008 reboot while connected: tunnel back without opening the app"

  # 0008: disconnect, then reboot. The manual disconnect must survive the reboot.
  adb shell am broadcast -a "$PKG.DISCONNECT_VPN" -n "$PKG/.IPNReceiver" >/dev/null
  wait_for 30 "state Stopped" in_state Stopped
  wait_for 30 "the tunnel down" tun_down
  reboot_app "0008 disconnected"
  wait_log "0008 BootReceiver staying down" "BootReceiver: boot: WantRunning=false" 60
  for _ in {1..15}; do tun_down || die "0008: the tunnel came up after a manual disconnect (or netcfg failed)"; sleep 1; done
  no_crash 0008
  pass "0008 disconnect then reboot: stays down"
  log > "$OUT/logcat-boot$BOOT.txt"
fi

bold "Emulator $([ "$NET" = 1 ] && echo 'smoke and tailnet' || echo smoke) tests passed in ${SECONDS}s"
