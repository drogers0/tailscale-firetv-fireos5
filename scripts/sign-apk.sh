#!/usr/bin/env bash
#
# Re-sign a built APK with a stable release key.
#
# Why this exists: Gradle signs debug builds with ~/.android/debug.keystore, which is
# generated per-machine. Two people building the same commit get APKs that cannot upgrade
# over one another, and a published release could not be upgraded in place at all. Signing
# with one durable key makes published APKs a coherent upgrade chain.
#
# We re-sign rather than build the `release` variant because that variant enables
# minifyEnabled + shrinkResources, and ProGuard is a real risk to kotlinx.serialization and
# the gomobile JNI bindings. Re-signing keeps the exact bytes we tested.
#
# The keystore and its password live OUTSIDE the repo and must never be committed — not
# even encrypted, since this repo is intended to be public and a published signing key
# cannot be un-published.
#
# Usage:
#   ./scripts/sign-apk.sh [apk]              # defaults to the newest APK in dist/
#
# Environment:
#   TS_KEYSTORE       default ~/.keystores/tailscale-firetv-release.jks
#   TS_KEYSTORE_PASS_FILE
#                     default ~/.keystores/tailscale-firetv-release.pass
#   TS_KEY_ALIAS      default firetv
#   TS_KEYSTORE_BASE64 / TS_KEYSTORE_PASSWORD
#                     CI path, supplied from GitHub repo secrets
#   TS_KEYSTORE_ENCRYPTED
#                     optional path to a gpg-encrypted keystore (kept out of tree)
#
# Create a keystore once with:
#   keytool -genkeypair -v -keystore "$TS_KEYSTORE" -alias firetv \
#           -keyalg RSA -keysize 4096 -validity 10950

set -euo pipefail

KEYSTORE="${TS_KEYSTORE:-$HOME/.keystores/tailscale-firetv-release.jks}"
PASSFILE="${TS_KEYSTORE_PASS_FILE:-$HOME/.keystores/tailscale-firetv-release.pass}"
ALIAS="${TS_KEY_ALIAS:-firetv}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Intentionally NOT stored in this repo — see STATUS.md. Set TS_KEYSTORE_ENCRYPTED to
# an out-of-tree gpg-encrypted keystore if you prefer that to a plain .jks on disk.
ENCRYPTED="${TS_KEYSTORE_ENCRYPTED:-}"
KEYCHAIN_SERVICE="tailscale-firetv-release"
KEYCHAIN_ACCOUNT="firetv"

CLEANUP_KS=""
cleanup() { [ -n "$CLEANUP_KS" ] && rm -f "$CLEANUP_KS"; }
trap cleanup EXIT

# ---- resolve the passphrase -------------------------------------------------
# 1. TS_KEYSTORE_PASSWORD   (CI, from GitHub secrets)
# 2. macOS Keychain         (local default)
# 3. local password file    (legacy)
# 4. interactive prompt
resolve_pass() {
  if [ -n "${TS_KEYSTORE_PASSWORD:-}" ]; then printf '%s' "$TS_KEYSTORE_PASSWORD"; return; fi
  if command -v security >/dev/null 2>&1; then
    if p=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null); then
      printf '%s' "$p"; return
    fi
  fi
  if [ -n "$PASSFILE" ] && [ -f "$PASSFILE" ]; then cat "$PASSFILE"; return; fi
  read -rsp "Keystore passphrase: " p </dev/tty; echo >/dev/tty
  printf '%s' "$p"
}

# ---- resolve the keystore ---------------------------------------------------
# 1. TS_KEYSTORE_BASE64      (CI, from GitHub secrets)
# 2. TS_KEYSTORE_ENCRYPTED   (optional out-of-tree gpg-encrypted keystore)
# 3. plain on-disk keystore  (default: ~/.keystores/tailscale-firetv-release.jks)
if [ -n "${TS_KEYSTORE_BASE64:-}" ]; then
  CLEANUP_KS="$(mktemp -t tsks)"; chmod 600 "$CLEANUP_KS"
  printf '%s' "$TS_KEYSTORE_BASE64" | base64 --decode > "$CLEANUP_KS"
  KEYSTORE="$CLEANUP_KS"
  info "keystore: TS_KEYSTORE_BASE64 (CI secret)"
elif [ -n "$ENCRYPTED" ] && [ -f "$ENCRYPTED" ]; then
  command -v gpg >/dev/null 2>&1 || die "gpg needed to decrypt $ENCRYPTED"
  PASS="$(resolve_pass)"
  CLEANUP_KS="$(mktemp -t tsks)"; chmod 600 "$CLEANUP_KS"
  printf '%s' "$PASS" | gpg --batch --quiet --passphrase-fd 0 \
      --decrypt "$ENCRYPTED" > "$CLEANUP_KS" 2>/dev/null \
    || die "could not decrypt $ENCRYPTED (wrong passphrase?)"
  KEYSTORE="$CLEANUP_KS"
  info "keystore: $(basename "$ENCRYPTED") (decrypted to a temp file, removed on exit)"
else
  info "keystore: $KEYSTORE"
fi

APK="${1:-}"
if [ -z "$APK" ]; then
  APK="$(ls -t "$REPO_ROOT"/dist/*.apk 2>/dev/null | grep -v -- '-unsigned' | head -1 || true)"
fi
[ -n "$APK" ] && [ -f "$APK" ] || die "no APK found; pass one explicitly"

[ -f "$KEYSTORE" ] || die "keystore not found: $KEYSTORE (see header for how to create one)"

APKSIGNER="$(ls "${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"/build-tools/*/apksigner 2>/dev/null | tail -1 || true)"
[ -n "$APKSIGNER" ] || die "apksigner not found in the Android SDK build-tools"

[ -n "${PASS:-}" ] || PASS="$(resolve_pass)"

info "Signing $(basename "$APK")"
"$APKSIGNER" sign \
  --ks "$KEYSTORE" \
  --ks-key-alias "$ALIAS" \
  --ks-pass "pass:$PASS" \
  --key-pass "pass:$PASS" \
  "$APK"

info "Verifying"
"$APKSIGNER" verify --print-certs "$APK" | grep -E "Signer #1 certificate (DN|SHA-256)" || true

# refresh the checksum so it matches the signed bytes
( cd "$(dirname "$APK")" && shasum -a 256 "$(basename "$APK")" > "$(basename "$APK").sha256" )
info "sha256: $(cut -d' ' -f1 < "$APK.sha256")"

cat <<EOF

Signed with the durable release key. Anyone upgrading from a differently-signed build
(including earlier debug-signed releases) must uninstall first:

  adb uninstall com.tailscale.ipn
  adb install $(basename "$APK")
EOF
