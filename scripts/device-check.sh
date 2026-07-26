#!/usr/bin/env bash
#
# Report whether a device is one this build targets: API 22 and OpenGL ES 2.0.
# Read-only — queries only, changes nothing.
#
# Usage: ./scripts/device-check.sh [adb-target]
#        ./scripts/device-check.sh 192.168.1.50:5555

set -uo pipefail

TARGET="${1:-}"
ADB=(adb)
[ -n "$TARGET" ] && ADB=(adb -s "$TARGET")

command -v adb >/dev/null || { echo "error: adb not found" >&2; exit 1; }

if [ -n "$TARGET" ] && ! adb devices | grep -q "^$TARGET[[:space:]]*device$"; then
  echo "connecting to $TARGET ..."
  adb connect "$TARGET" >/dev/null 2>&1
  sleep 2
  adb devices | grep -q "^$TARGET[[:space:]]*device$" || {
    echo "error: $TARGET is not an authorized device." >&2
    echo "       If it shows 'unauthorized', accept the debugging prompt on the TV." >&2
    exit 1
  }
fi

g() { "${ADB[@]}" shell getprop "$1" 2>/dev/null | tr -d '\r'; }

SDK="$(g ro.build.version.sdk)"
REL="$(g ro.build.version.release)"
MODEL="$(g ro.product.model)"
NAME="$(g ro.build.version.name)"
ABILIST="$(g ro.product.cpu.abilist)"
GLES_RAW="$(g ro.opengles.version)"
GPU="$("${ADB[@]}" shell dumpsys SurfaceFlinger 2>/dev/null | grep -i "GLES:" | head -1 | sed 's/^[[:space:]]*//' | tr -d '\r')"
DENSITY="$("${ADB[@]}" shell wm density 2>/dev/null | tr -d '\r')"
SIZE="$("${ADB[@]}" shell wm size 2>/dev/null | tr -d '\r')"
MEM="$("${ADB[@]}" shell cat /proc/meminfo 2>/dev/null | awk '/MemTotal/{printf "%.0f MB", $2/1024}')"

# ro.opengles.version is a packed int: 0x20000 = 2.0, 0x30000 = 3.0, 0x30001 = 3.1
if [ -n "$GLES_RAW" ] 2>/dev/null && [ "$GLES_RAW" -eq "$GLES_RAW" ] 2>/dev/null; then
  GLES_MAJ=$(( GLES_RAW >> 16 ))
  GLES_MIN=$(( GLES_RAW & 0xFFFF ))
  GLES="$GLES_MAJ.$GLES_MIN (raw $GLES_RAW)"
else
  GLES="unknown"
  GLES_MAJ=0
fi

echo "=================================================================="
echo " Device"
echo "=================================================================="
printf "  model        : %s\n" "${MODEL:-?}"
printf "  firmware     : %s\n" "${NAME:-?}"
printf "  android      : %s (API %s)\n" "${REL:-?}" "${SDK:-?}"
printf "  abilist      : %s\n" "${ABILIST:-?}"
printf "  gpu          : %s\n" "${GPU:-?}"
printf "  opengl es    : %s\n" "$GLES"
printf "  display      : %s / %s\n" "${SIZE:-?}" "${DENSITY:-?}"
printf "  memory       : %s\n" "${MEM:-?}"
echo

echo "=================================================================="
echo " Verdict"
echo "=================================================================="

verdict=0

if [ "${SDK:-0}" -lt 22 ] 2>/dev/null; then
  echo "  ✗ API $SDK is below 22 — this build will NOT install."
  verdict=1
elif [ "${SDK:-0}" -ge 26 ] 2>/dev/null; then
  echo "  • API $SDK — you do not need this build."
  echo "    Use the official client: https://tailscale.com/docs/install/amazon-fire"
  verdict=2
else
  echo "  ✓ API $SDK — within range (this build declares minSdk 22)."
fi

case "$ABILIST" in
  *armeabi-v7a*) echo "  ✓ armeabi-v7a present." ;;
  *) echo "  ✗ armeabi-v7a not in abilist — the default single-ABI build won't run."
     echo "    Rebuild with e.g. TS_ARCH=arm64 ./scripts/build.sh"
     verdict=1 ;;
esac

if [ "$GLES_MAJ" -ge 3 ] 2>/dev/null; then
  echo "  • OpenGL ES $GLES_MAJ.x — the Gio rendering bug does not affect you."
  echo "    An official release for your API level will work fine."
else
  echo "  ✓ OpenGL ES 2.0 — exactly the hardware this build exists for."
  echo "    Gio-based releases (<= 1.62.0) crash here; this build uses Compose."
fi

echo
case $verdict in
  0) echo "  => Target device. Proceed with ./scripts/build.sh" ;;
  1) echo "  => Not supported by this build." ;;
  2) echo "  => Prefer the official client." ;;
esac

exit 0
