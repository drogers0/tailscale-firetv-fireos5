# Tailscale for Fire OS 5 (Fire TV Stick 2nd gen)

Unofficial, reproducible build of the **Tailscale Android client** for **Fire OS 5 /
Android 5.1 (API 22)** devices with **OpenGL ES 2.0** GPUs — hardware the official app
cannot support.

Tracks Tailscale's current stable release, patched to run at API 22. Each
[release](../../releases) names the upstream version it carries.

> [!IMPORTANT]
> **Unofficial community build.** Not affiliated with, endorsed by, or supported by
> Tailscale Inc. See [Legal](#legal).

## Status — working

Verified on a Fire TV Stick 2nd gen (`AFTT`), Fire OS 5.2.9.5, on 1.98.8; 1.104.5 also passed
tiers 0-3. Each release is checked on a Fire TV Stick before it is published.

| | |
|---|---|
| Installs and renders on GLES 2.0 | ✅ |
| Login, tunnel, DERP relay | ✅ ~72 ms |
| Online to control plane, health clear | ✅ |
| Peer list | ✅ |
| **Exit-node routing** | ✅ 1 MB download → **1,113,884 bytes over `tun0`** |
| Auto-start after reboot | ⚠️ patch 0008, unverified on Fire TV; see [STATUS.md](docs/STATUS.md#reboot-behaviour) |

## Quick start

```sh
git clone git@github.com:drogers0/tailscale-firetv-fireos5.git
cd tailscale-firetv-fireos5

./scripts/device-check.sh <fire-stick-ip>:5555   # confirm API 22 + GLES 2.0
make build                                       # see docs/BUILD.md for prerequisites
adb install -r dist/tailscale-fireos5-*.apk
```

> [!TIP]
> Prefer not to build? Download the APK from the [latest release](../../releases/latest) and
> check it against the `.sha256` beside it. CI builds and signs each release from a tagged
> commit on `main`, and each one is checked on a Fire TV Stick before it is published
> ([docs/RELEASING.md](docs/RELEASING.md)).

## Documentation

| | |
|---|---|
| [docs/STATUS.md](docs/STATUS.md) | what works, patches, verification method, gotchas |
| [docs/BUILD.md](docs/BUILD.md) | prerequisites, build, troubleshooting, reproducibility |
| [docs/TESTING.md](docs/TESTING.md) | test tiers, running them locally and in CI, the release checklist |
| [docs/RELEASING.md](docs/RELEASING.md) | how upstream releases become bump PRs and signed draft releases |
| [docs/DEVICES.md](docs/DEVICES.md) | which hardware this is for — every Fire TV and Fire tablet model, plus non-Amazon devices |
| [docs/BACKGROUND.md](docs/BACKGROUND.md) | why the gap exists, why track current stable |
| [docs/FINDINGS.md](docs/FINDINGS.md) | investigation record, including disproven theories |

## Legal

Tailscale is licensed **BSD-3-Clause**, which permits redistributing built binaries; the
upstream `LICENSE` is preserved in every artifact produced here.

"Tailscale" is a trademark of Tailscale Inc. This project is not affiliated with or
endorsed by them, uses the name only to identify what the software is, and should not be
mistaken for an official distribution. **Do not report problems with these builds to
Tailscale** — open an issue here.

> [!CAUTION]
> Release APKs are debug builds re-signed with this project's release key, and they share the
> upstream application ID `com.tailscale.ipn`, so they cannot be installed alongside an
> official Tailscale build. An APK you build yourself carries your own debug key: uninstall a
> release before installing it.

Build scripts here are MIT licensed ([LICENSE](LICENSE)) — that covers the scripts only,
not the Tailscale source they compile.
