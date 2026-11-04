#!/usr/bin/env bash
#
# Print the notes for a draft GitHub release of a signed APK. Used by
# .github/workflows/release.yml; run it locally to preview them.
#
# Usage: scripts/release-notes.sh TAG APK
#   TAG  the release tag, <upstream version>-fireos5-r<N>
#   APK  the signed APK; APK.sha256 must sit beside it (sign-apk.sh writes it)

set -euo pipefail

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
[ $# -eq 2 ] || die "usage: $0 TAG APK"
TAG="$1" APK="$2"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF="$(sed -n 's/^PINNED_REF=//p' "$REPO_ROOT/scripts/build.sh")"
CERT="$(sed -n 's/^CERT_SHA256=//p' "$REPO_ROOT/scripts/sign-apk.sh")"
SHA="$(cut -d' ' -f1 < "$APK.sha256")" || die "no $APK.sha256"
[ -n "$REF" ] && [ -n "$CERT" ] && [ -n "$SHA" ] || die "cannot read PINNED_REF, CERT_SHA256 or the sha256"
NAME="$(basename "$APK")"
REPO_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-drogers0/tailscale-firetv-fireos5}"
PATCHES="$(for p in "$REPO_ROOT"/patches/*.patch; do printf -- '- <code>%s</code>\n' "$(basename "$p" .patch)"; done)"

# <code> rather than backticks, so the heredoc needs no escaping.
cat <<EOF
<!-- Draft: run the hardware checklist in docs/TESTING.md ("Before a release") on this APK, record the result here, then publish. -->
Tailscale **${REF%%-*}** for Fire OS 5 / Android 5.1 (API 22). Upstream:
[release](https://github.com/tailscale/tailscale-android/releases/tag/$REF) ·
[changelog](https://tailscale.com/changelog#client).

| | |
|---|---|
| File | <code>$NAME</code> |
| sha256 | <code>$SHA</code> |
| Upstream ref | <code>$REF</code> |
| ABI, minSdk | armeabi-v7a, 22 |
| Signing | release key, certificate SHA-256 <code>$CERT</code> |

## Install

    adb connect <fire-stick-ip>:5555
    adb install -r $NAME

Upgrades in place over earlier releases from this repo. An official Tailscale install, or a build
you signed yourself, has to be uninstalled first.

## Patches

$PATCHES

What each one fixes: [docs/STATUS.md]($REPO_URL/blob/$TAG/docs/STATUS.md#patches).
${GITHUB_RUN_ID:+
Built and signed by [this workflow run]($REPO_URL/actions/runs/$GITHUB_RUN_ID).}
EOF
