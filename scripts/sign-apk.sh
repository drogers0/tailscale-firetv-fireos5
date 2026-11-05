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
# CERT_SHA256 below pins the release certificate: a keystore with any other key (a wrong
# secret, a test key) fails here instead of shipping an APK that cannot upgrade in place.
# Someone signing with their own key changes that line.
#
# Create a keystore once with:
#   keytool -genkeypair -v -keystore "$TS_KEYSTORE" -alias firetv \
#           -keyalg RSA -keysize 4096 -validity 10950

set -euo pipefail

KEYSTORE="${TS_KEYSTORE:-$HOME/.keystores/tailscale-firetv-release.jks}"
PASSFILE="${TS_KEYSTORE_PASS_FILE:-$HOME/.keystores/tailscale-firetv-release.pass}"
ALIAS="${TS_KEY_ALIAS:-firetv}"
# The release certificate's SHA-256 (apksigner verify --print-certs). Bare NAME=value:
# scripts/release-notes.sh reads it with sed.
CERT_SHA256=b6e56d68dcbeb34236f90951e8e05f07e6a8dba90be17c0d82646a6a6da053b5

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Intentionally NOT stored in this repo — see docs/STATUS.md. Set TS_KEYSTORE_ENCRYPTED
# to an out-of-tree gpg-encrypted keystore if you prefer that to a plain .jks on disk.
ENCRYPTED="${TS_KEYSTORE_ENCRYPTED:-}"
KEYCHAIN_SERVICE="tailscale-firetv-release"
KEYCHAIN_ACCOUNT="firetv"

CLEANUP_KS="" SIGNED=""
cleanup() { rm -f ${CLEANUP_KS:+"$CLEANUP_KS"} ${SIGNED:+"$SIGNED" "$SIGNED.idsig"}; }
trap cleanup EXIT

# ---- resolve the passphrase -------------------------------------------------
# 1. TS_KEYSTORE_PASSWORD   (CI, from GitHub secrets)
# 2. macOS Keychain         (local default)
# 3. local password file    (legacy)
# 4. interactive prompt     (skipped without a terminal, as in CI)
# Called as PASS="$(resolve_pass)", so its die ends the script through set -e.
resolve_pass() {
  local p=""
  if [ -n "${TS_KEYSTORE_PASSWORD:-}" ]; then
    p="$TS_KEYSTORE_PASSWORD"
  elif command -v security >/dev/null 2>&1 \
    && p="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null)"; then
    :
  elif [ -n "$PASSFILE" ] && [ -f "$PASSFILE" ]; then
    p="$(cat "$PASSFILE")"
  else
    { read -rsp "Keystore passphrase: " p </dev/tty 2>/dev/tty && echo >/dev/tty; } 2>/dev/null || p=""
  fi
  [ -n "$p" ] || die "no keystore passphrase: set TS_KEYSTORE_PASSWORD (in CI, the repo secret), or store it in the Keychain or $PASSFILE"
  printf '%s' "$p"
}

# ---- resolve the keystore ---------------------------------------------------
# 1. TS_KEYSTORE_BASE64      (CI, from GitHub secrets)
# 2. TS_KEYSTORE_ENCRYPTED   (optional out-of-tree gpg-encrypted keystore)
# 3. plain on-disk keystore  (default: ~/.keystores/tailscale-firetv-release.jks)
if [ -n "${TS_KEYSTORE_BASE64:-}" ]; then
  CLEANUP_KS="$(mktemp "${TMPDIR:-/tmp}/tsks.XXXXXX")"; chmod 600 "$CLEANUP_KS"
  printf '%s' "$TS_KEYSTORE_BASE64" | base64 --decode > "$CLEANUP_KS"
  KEYSTORE="$CLEANUP_KS"
  info "keystore: TS_KEYSTORE_BASE64 (CI secret)"
elif [ -n "$ENCRYPTED" ] && [ -f "$ENCRYPTED" ]; then
  command -v gpg >/dev/null 2>&1 || die "gpg needed to decrypt $ENCRYPTED"
  PASS="$(resolve_pass)"
  CLEANUP_KS="$(mktemp "${TMPDIR:-/tmp}/tsks.XXXXXX")"; chmod 600 "$CLEANUP_KS"
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
  # shellcheck disable=SC2010  # dist/ names come from build.sh; no odd characters
  APK="$(ls -t "$REPO_ROOT"/dist/*.apk 2>/dev/null | grep -v -- '-unsigned' | head -1 || true)"
fi
[ -n "$APK" ] && [ -f "$APK" ] || die "no APK found; pass one explicitly"

[ -f "$KEYSTORE" ] || die "keystore not found: $KEYSTORE (in CI, set the TS_KEYSTORE_BASE64 repo secret; see the header for how to create one)"

APKSIGNER="$(ls "${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"/build-tools/*/apksigner 2>/dev/null | tail -1 || true)"
[ -n "$APKSIGNER" ] || die "apksigner not found in the Android SDK build-tools"

[ -n "${PASS:-}" ] || PASS="$(resolve_pass)"

# Sign a copy beside the APK and replace the APK only once the copy carries the release
# certificate, so a wrong key leaves the APK and its .sha256 untouched.
SIGNED="$(mktemp "$(dirname "$APK")/.$(basename "$APK").XXXXXX")"
info "Signing $(basename "$APK") with $APKSIGNER"
# env:, not pass:, so the passphrase never appears on a command line (ps, /proc).
TS_SIGN_PASS="$PASS" "$APKSIGNER" sign \
  --ks "$KEYSTORE" \
  --ks-key-alias "$ALIAS" \
  --ks-pass env:TS_SIGN_PASS \
  --key-pass env:TS_SIGN_PASS \
  --out "$SIGNED" \
  "$APK"

info "Verifying"
certs="$("$APKSIGNER" verify --print-certs "$SIGNED")" || die "apksigner verify failed on the signed copy of $APK"
# Every signer line must name the release key. build-tools 36 prints "Signer #1 certificate
# SHA-256 digest: ..."; 37 prints "V3.0 Signer: certificate SHA-256 digest: ...".
got="$(printf '%s\n' "$certs" | sed -n 's/^.*[Ss]igner.* certificate SHA-256 digest: //p' | sort -u)"
[ "$got" = "$CERT_SHA256" ] \
  || { printf '%s\n' "$certs" | grep -v '^WARNING' | head -20 >&2 || true
         die "signing $APK produced certificate $(printf '%s' "${got:-<none>}" | tr '\n' ' '), not the release key $CERT_SHA256 (wrong keystore or alias?); $APK is unchanged"; }
printf '%s\n' "$certs" | grep -E 'certificate (DN|SHA-256)'

chmod 644 "$SIGNED"
rm -f "$APK.idsig"
[ ! -f "$SIGNED.idsig" ] || mv "$SIGNED.idsig" "$APK.idsig"
mv "$SIGNED" "$APK"
SIGNED=""

# refresh the checksum so it matches the signed bytes
( cd "$(dirname "$APK")" && shasum -a 256 "$(basename "$APK")" > "$(basename "$APK").sha256" )
info "sha256: $(cut -d' ' -f1 < "$APK.sha256")"

cat <<EOF

Signed with the durable release key. A device running a build signed with any other key
(your own debug build, an official Tailscale install) must uninstall it first:

  adb uninstall com.tailscale.ipn
  adb install $(basename "$APK")
EOF
