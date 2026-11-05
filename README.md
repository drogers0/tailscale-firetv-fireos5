<p align="center">
  <img src="https://github.com/user-attachments/assets/9f9d46df-698f-414e-9ead-0b0f0eb6805b" alt="tailscale-firetv-fireos5 banner" width="640">
</p>

<p align="center">
  <em>Recent Tailscale releases on a 2016 Fire TV Stick, and on any Android 5.1 to 7.1 device the official app no longer supports.</em>
</p>

<p align="center">
  <a href="https://github.com/drogers0/tailscale-firetv-fireos5/releases/latest"><img src="https://img.shields.io/github/v/release/drogers0/tailscale-firetv-fireos5?color=blue" alt="Latest release"></a>
  <a href="https://github.com/drogers0/tailscale-firetv-fireos5/releases"><img src="https://img.shields.io/github/downloads/drogers0/tailscale-firetv-fireos5/total?color=green" alt="Total downloads"></a>
  <a href="docs/DEVICES.md"><img src="https://img.shields.io/badge/Android_API-22--25-orange" alt="Android API 22 to 25"></a>
  <a href="https://github.com/drogers0/tailscale-firetv-fireos5/actions/workflows/ci.yml"><img src="https://github.com/drogers0/tailscale-firetv-fireos5/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/scripts-MIT-lightgrey" alt="Scripts: MIT"></a>
</p>

---

An unofficial, reproducible build of the **Tailscale Android client** for **Fire OS 5 / Android 5.1 (API 22)** and up, on devices with **OpenGL ES 2.0** GPUs. It tracks Tailscale's current stable release, restores the API 22 floor, and patches the calls that need it; releases can lag `main`, and each [release](https://github.com/drogers0/tailscale-firetv-fireos5/releases) names the upstream version it carries. **Exit-node routing** works, verified on a Fire TV Stick 2nd gen.

```console
$ adb connect 192.168.1.50:5555
$ gh release download -R drogers0/tailscale-firetv-fireos5 -p '*.apk*'
$ shasum -a 256 -c tailscale-fireos5-*.apk.sha256
tailscale-fireos5-1.98.8-minsdk22-armeabi-v7a.apk: OK
$ adb install -r tailscale-fireos5-*.apk
Success
```

> [!IMPORTANT]
> **Unofficial community build.** Not affiliated with, endorsed by, or supported by Tailscale Inc. See [Legal](#legal).

## Compatibility

The build runs on **API 22 to 25** (Android 5.1 to 7.1) with an **armeabi-v7a** ABI. The official client starts at API 26, so every Fire OS 5 and Fire OS 6 device is out of its reach.

- **Needs this build:** Fire TV Stick 1st gen (`AFTM`) and 2nd gen (`AFTT`), Fire TV 3rd gen (`AFTN`), Fire TV Cube 1st gen (`AFTA`), Fire 7 (2017) and Fire (2015) tablets. All have GLES 2.0 GPUs, which no older Tailscale release can render on.
- **Benefits from it:** GLES 3 devices at API 22 to 25, such as Fire TV 1st and 2nd gen and the Fire OS 5 Fire HD and HDX tablets. Tailscale 1.62.0 runs there; this build adds every fix since.
- **Use the official client:** Fire OS 7 and later (API 28+).

Only `AFTT` has been tested. [docs/DEVICES.md](docs/DEVICES.md) has the full per-model table, including non-Amazon hardware.

## Installation

You need `adb` from Android [platform-tools](https://developer.android.com/tools/releases/platform-tools) (`brew install android-platform-tools`, `apt install adb`, or `winget install Google.PlatformTools`). The [`gh` CLI](https://cli.github.com) is optional, for the one-line download; it needs `gh auth login` once.

1. **Enable ADB on the device.** On a Fire TV: Settings > My Fire TV (Device on older firmware) > Developer options > ADB debugging. The IP address is under Settings > My Fire TV > About > Network.
2. **Connect and check the device.** Accept the debugging prompt on the TV the first time:

   ```sh
   adb connect 192.168.1.50:5555
   adb shell getprop ro.product.model         # e.g. AFTT; compare with Compatibility above
   adb shell getprop ro.build.version.sdk     # 22 to 25
   ```

   With the repo cloned, `./scripts/device-check.sh 192.168.1.50:5555` checks API level, ABI and GLES version in one go.
3. **Download, verify and install** the `.apk` and its `.apk.sha256` from the [latest release](https://github.com/drogers0/tailscale-firetv-fireos5/releases/latest), as in the example above, or from the release page in a browser. On Linux without `shasum`, use `sha256sum -c`. On Windows (PowerShell), compare `certutil -hashfile <apk> SHA256` with the `.sha256` file instead of `shasum`, and pass the full filename to `adb install`.

   New releases are built and signed by CI from a tagged commit on `main`, and checked on a Fire TV Stick before they are published ([docs/RELEASING.md](docs/RELEASING.md)).

Then open Tailscale from the Fire TV's app list and log in.

<details>
<summary>Build from source</summary>

```sh
git clone https://github.com/drogers0/tailscale-firetv-fireos5
cd tailscale-firetv-fireos5
make build                             # see docs/BUILD.md for prerequisites
adb install -r dist/tailscale-fireos5-*.apk
```

Roughly 10 minutes cold, most of it the Android NDK download; a couple of minutes after that. Tunables (`TS_REF`, `MIN_SDK`, `GOMOBILE_TARGET`, ...) are environment variables, listed in [docs/BUILD.md](docs/BUILD.md#build).

A local build is signed with your own debug key, so it can never upgrade over a release APK, or the reverse: the install fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. Run `adb uninstall com.tailscale.ipn` first; this clears the login.

</details>

## Why this exists

Tailscale on this hardware fails from both directions:

| | Runs on Android 5.1? | Renders on OpenGL ES 2.0? |
|---|---|---|
| Tailscale ≤ 1.62.0 (Gio UI) | **Yes** (minSdk 22) | **No**, needs GLES 3 |
| Tailscale ≥ 1.64.0 (Compose UI) | **No** (minSdk 26) | Yes |

The GLES 3 requirement came from the Gio UI toolkit, which Compose replaced. The API 26 floor arrived in the same period, but as a one-line `minSdkVersion` change with no new dependency behind it. This repo restores the floor on a current release and patches the calls, mostly missing API guards, that break below API 26. The full story is in [docs/BACKGROUND.md](docs/BACKGROUND.md).

## Status

Verified on a Fire TV Stick 2nd gen (`AFTT`), Fire OS 5.2.9.5, running 1.98.8 (the table below). Whatever version `main` pins passes the API 22 emulator tests in CI; 1.104.5 also passed the emulator logged in to a real tailnet ([docs/TESTING.md](docs/TESTING.md)).

| | |
|---|---|
| Installs and renders on GLES 2.0 | ✅ |
| Login, tunnel, DERP relay | ✅ ~72 ms |
| Online to control plane, health clear | ✅ |
| Peer list | ✅ |
| **Exit-node routing** | ✅ 1 MB download, **1,113,884 bytes over `tun0`** |
| Reconnect after reboot (API 22 to 23) | ⚠️ not in 1.98.8; see [Limitations](#limitations) and [reboot behavior](docs/STATUS.md#reboot-behaviour) |

The patch series and what each patch fixes are in [docs/STATUS.md](docs/STATUS.md#patches).

## Documentation

| | |
|---|---|
| [docs/STATUS.md](docs/STATUS.md) | what works and how it was verified, patches, signing, reading Go-side logs, gotchas |
| [docs/BUILD.md](docs/BUILD.md) | prerequisites, build options, troubleshooting, reproducibility |
| [docs/TESTING.md](docs/TESTING.md) | test tiers, running them locally and in CI, the release checklist |
| [docs/RELEASING.md](docs/RELEASING.md) | how upstream releases become bump PRs and signed draft releases |
| [docs/DEVICES.md](docs/DEVICES.md) | every Fire TV and Fire tablet model, plus non-Amazon devices |
| [docs/BACKGROUND.md](docs/BACKGROUND.md) | why the gap exists, why track current stable |
| [docs/FINDINGS.md](docs/FINDINGS.md) | investigation record, including disproven theories |

## Limitations

- **`1.98.8-fireos5-r1` lacks patches 0008 to 0011.** Releases after it, and a source build of `main`, have them; 0012 fixes code 1.98.8 does not contain. On r1:
  - On API 22 to 23 (Fire OS 5) the VPN does not reconnect after a reboot, because upstream relies on always-on VPN (API 24+). Open the app once after a reboot; login and exit-node choice persist. Patch 0008 adds a boot receiver, verified on the API 22 emulator but not yet on a Fire TV.
  - With another VPN app active, the app crashes on API 22 instead of showing the VPN-conflict dialog. Turn the other VPN off (patch 0009).
  - Below API 26 the app misses the initial network state, so DNS falls back to a public resolver until the network changes (patch 0010).
  - A background connect request that cannot start the VPN crashes the app instead of posting a "connection failed" notification (patch 0011).
- **Single ABI.** Published APKs are `armeabi-v7a`. arm64 devices accept them; a device without v7a needs `GOMOBILE_TARGET=android/arm64 make build`.
- **Debuggable.** Releases are re-signed debug builds, which keeps `run-as` log reading possible but lets anyone with ADB access read app-private data.
- **No side-by-side install.** The APK keeps the upstream application ID `com.tailscale.ipn`, and releases are signed with this project's key, not Tailscale's. It cannot coexist with an official Tailscale install, and switching between them needs an uninstall.
- **Slow first launch.** 5 to 7 seconds to first frame on a Fire TV Stick 2nd gen.

## Contributing

Issues and pull requests are welcome. Reports from devices other than `AFTT` are the most useful thing you can send. Please include:

- The output of `./scripts/device-check.sh`
- The release tag you installed, or the `TS_REF` you built
- `adb logcat` around the failure, and `ipn.log` if the tunnel misbehaves (see [Reading the Go-side logs](docs/STATUS.md#reading-the-go-side-logs))

Redact tailnet hostnames, IPs and auth URLs before posting. Before opening a PR, run `make check`; CI also builds the APK and runs smoke tests on an API 22 emulator. See [docs/TESTING.md](docs/TESTING.md).

## Support

If this got Tailscale onto a device you had written off, a ⭐ helps others find it:

```bash
gh api --method PUT user/starred/drogers0/tailscale-firetv-fireos5
```

(or just click the star at the [top of this page](https://github.com/drogers0/tailscale-firetv-fireos5))

## Legal

Tailscale is licensed **BSD-3-Clause**, which permits redistributing built binaries with its [license notice](https://github.com/tailscale/tailscale-android/blob/main/LICENSE). The build scripts and documentation in this repo are MIT licensed ([LICENSE](LICENSE)); that covers them only, not the Tailscale source they compile.

"Tailscale" is a trademark of Tailscale Inc. This project is not affiliated with or endorsed by them, uses the name only to identify what the software is, and should not be mistaken for an official distribution. **Do not report problems with these builds to Tailscale.** Open an issue here.

## License

[MIT](LICENSE) © 2026 drogers0 (build scripts and documentation; see [Legal](#legal))
