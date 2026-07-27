# Tailscale for Fire OS 5 (Fire TV Stick 2nd gen)

Unofficial, reproducible build of the **Tailscale Android client** for **Fire OS 5 /
Android 5.1 (API 22)** devices with **OpenGL ES 2.0** GPUs — hardware the official app
cannot support.

Current stable **Tailscale 1.98.8**, patched to run at API 22, **routing traffic through an
exit node**.

> [!IMPORTANT]
> **Unofficial community build.** Not affiliated with, endorsed by, or supported by
> Tailscale Inc. See [Legal](#legal).

## Status — working

Verified on a Fire TV Stick 2nd gen (`AFTT`), Fire OS 5.2.9.5:

| | |
|---|---|
| Installs and renders on GLES 2.0 | ✅ |
| Login, tunnel, DERP relay | ✅ ~72 ms |
| Online to control plane, health clear | ✅ |
| Peer list | ✅ |
| **Exit-node routing** | ✅ 1 MB download → **1,113,884 bytes over `tun0`** |
| Auto-start after reboot | ❌ open the app once; see [STATUS.md](docs/STATUS.md) |

## Quick start

```sh
git clone git@github.com:drogers0/tailscale-firetv-fireos5.git
cd tailscale-firetv-fireos5

./scripts/device-check.sh <fire-stick-ip>:5555   # confirm API 22 + GLES 2.0
./scripts/build.sh                               # see docs/BUILD.md for prerequisites
adb install -r dist/tailscale-fireos5-*.apk
```

> [!TIP]
> Prefer not to build? Take an APK from [Releases](../../releases) and check its `sha256`
> against the published checksum.

## Documentation

| | |
|---|---|
| [docs/STATUS.md](docs/STATUS.md) | what works, the seven patches, verification method, gotchas |
| [docs/BUILD.md](docs/BUILD.md) | prerequisites, build, troubleshooting, reproducibility |
| [docs/BACKGROUND.md](docs/BACKGROUND.md) | why the gap exists, why 1.98.8, device compatibility |
| [docs/FINDINGS.md](docs/FINDINGS.md) | investigation record, including disproven theories |

## Legal

Tailscale is licensed **BSD-3-Clause**, which permits redistributing built binaries; the
upstream `LICENSE` is preserved in every artifact produced here.

"Tailscale" is a trademark of Tailscale Inc. This project is not affiliated with or
endorsed by them, uses the name only to identify what the software is, and should not be
mistaken for an official distribution. **Do not report problems with these builds to
Tailscale** — open an issue here.

> [!CAUTION]
> APKs are **debug-signed** and share the upstream application ID `com.tailscale.ipn`, so
> they cannot be installed alongside an official Tailscale build.

Build scripts here are MIT licensed ([LICENSE](LICENSE)) — that covers the scripts only,
not the Tailscale source they compile.
