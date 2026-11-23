<p align="center">
  <img src="https://github.com/user-attachments/assets/9f9d46df-698f-414e-9ead-0b0f0eb6805b" alt="tailscale-firetv-fireos5 banner" width="640">
</p>

<p align="center">
  <em>Current Tailscale on Fire OS 5 and other Android 5.1 to 7.1 devices the official app no longer supports.</em>
</p>

<p align="center">
  <a href="https://github.com/drogers0/tailscale-firetv-fireos5/releases/latest"><img src="https://img.shields.io/github/v/release/drogers0/tailscale-firetv-fireos5?color=blue" alt="Latest release"></a>
  <a href="https://github.com/drogers0/tailscale-firetv-fireos5/releases"><img src="https://img.shields.io/github/downloads/drogers0/tailscale-firetv-fireos5/total?color=green" alt="Total downloads"></a>
  <a href="docs/DEVICES.md"><img src="https://img.shields.io/badge/Android_API-22--25-orange" alt="Android API 22 to 25"></a>
  <a href="https://github.com/drogers0/tailscale-firetv-fireos5/actions/workflows/ci.yml"><img src="https://github.com/drogers0/tailscale-firetv-fireos5/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/scripts-MIT-lightgrey" alt="Scripts: MIT"></a>
</p>

---

An unofficial build of the current stable **Tailscale Android client** for **API 22 to 25** (Fire OS 5 and 6), including devices with **OpenGL ES 2.0** GPUs. It lowers upstream's API 26 floor and patches the calls that break below it.

```console
$ gh release download -R drogers0/tailscale-firetv-fireos5 -p '*.apk*'
$ shasum -a 256 -c tailscale-fireos5-*.apk.sha256
tailscale-fireos5-1.104.5-minsdk22-armeabi-v7a.apk: OK
$ adb install -r tailscale-fireos5-*.apk
Success
```

> [!IMPORTANT]
> **Unofficial community build.** Not affiliated with, endorsed by, or supported by Tailscale Inc. See [Legal](#legal).

## Compatibility

| Device | |
|---|---|
| Fire TV Stick 1st gen (`AFTM`) and 2nd gen (`AFTT`), Fire TV 3rd gen (`AFTN`), Fire TV Cube 1st gen (`AFTA`), Fire 7 (2017), Fire (2015) | **Needs this build.** GLES 2.0 GPU: 1.62.0 and earlier don't render, 1.64.0 and later need API 26. |
| GLES 3 devices at API 22 to 25, such as Fire TV 1st and 2nd gen, Fire TV Stick 4K 1st gen, and Fire HD and HDX tablets on Fire OS 5 | **Benefits.** Tailscale 1.62.0 runs; this build adds every fix since. |
| Android 8.0 and later (API 26+), including Fire OS 7 and later | Use the official app. |

Only the Fire TV Stick 2nd gen (`AFTT`) has been tested. [docs/DEVICES.md](docs/DEVICES.md) lists every model, including non-Amazon hardware.

## Installation

You need `adb` ([platform-tools](https://developer.android.com/tools/releases/platform-tools)). The [`gh` CLI](https://cli.github.com) is optional and needs `gh auth login` once.

1. On the Fire TV, turn on Settings > My Fire TV (Device on older firmware) > Developer options > ADB debugging. The IP address is under Settings > My Fire TV > About > Network.
2. Run `adb connect <ip>:5555` and accept the prompt on the TV. `adb shell getprop ro.product.model` gives the model code for the table above, and `adb shell getprop ro.build.version.sdk` should print 22 to 25.
3. Download the `.apk` and `.apk.sha256` from the [latest release](https://github.com/drogers0/tailscale-firetv-fireos5/releases/latest), or with `gh release download` as shown at the top.
4. Verify with `shasum -a 256 -c *.apk.sha256` (`sha256sum -c` on Linux), then run `adb install -r tailscale-fireos5-*.apk`.
   On Windows, compare `certutil -hashfile <apk> SHA256` with the `.sha256` file, and give `adb install` the full filename.
5. Open Tailscale from the app list and log in.

To upgrade, install the new APK the same way; login and settings carry over. Releases after `1.98.8-fireos5-r1` add reconnect after reboot (see [Limitations](#limitations)), fix two crashes, and stop DNS falling back to a public resolver.

Optional: from a clone of this repo, `./scripts/device-check.sh <ip>:5555` reports the device's API level, ABI and GLES version.

New releases are built and signed by CI from a tag on `main` as drafts, then published by hand ([docs/RELEASING.md](docs/RELEASING.md)).

<details>
<summary>Build from source</summary>

```sh
git clone https://github.com/drogers0/tailscale-firetv-fireos5
cd tailscale-firetv-fireos5
make build                             # prerequisites and options: docs/BUILD.md
adb install -r dist/tailscale-fireos5-*.apk
```

A local build is signed with your debug key, so it cannot install over a release APK (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`). Run `adb uninstall com.tailscale.ipn` first; this clears the login.

</details>

## Why this exists

| | Runs on Android 5.1? | Renders on GLES 2.0? |
|---|---|---|
| Tailscale ≤ 1.62.0 (Gio UI) | Yes | **No** |
| Tailscale ≥ 1.64.0 (Compose UI) | **No** (minSdk 26) | Yes |

Upstream raised the floor to API 26 with a one-line `minSdkVersion` change, with no new dependency behind it. Details: [docs/BACKGROUND.md](docs/BACKGROUND.md).

## Status

Last full hardware test: Fire TV Stick 2nd gen (Fire OS 5.2.9.5) on 1.98.8, where install, GLES 2.0 rendering, login, DERP relay, peer list and exit-node routing all work. Release 1.104.5 passed the API 22 emulator tests in CI and a logged-in emulator test against a real tailnet ([docs/TESTING.md](docs/TESTING.md)). Each release names the upstream version it carries; `main` can be ahead. Details and patches: [docs/STATUS.md](docs/STATUS.md).

## Limitations

- **Reconnect after reboot needs one launch first.** On API 22 to 23, a boot receiver stands in for always-on VPN (API 24+). It reconnects only if Tailscale was connected at shutdown and the app has been opened since install or force-stop. Fire OS signals boot about two minutes after power-on, so expect the tunnel back after roughly 2.5 minutes. Verified on the emulator, not yet on a Fire TV ([details](docs/STATUS.md#reboot-behaviour)). If it does not reconnect, opening the app does; login and exit-node choice persist.
- **Single ABI.** APKs are `armeabi-v7a`, which arm64 devices also run. For arm64-only devices, build with `GOMOBILE_TARGET=android/arm64`.
- **Debuggable.** Releases are debug builds re-signed with this project's key, so `run-as` can read logs, and anyone with ADB access can read app data.
- **No side-by-side install.** This build uses the official app ID `com.tailscale.ipn` with a different signing key, so switching between it and the official app needs an uninstall.
- **Slow first launch.** 5 to 7 seconds on a Fire TV Stick 2nd gen.

## Documentation

- [STATUS](docs/STATUS.md): what works, patches, signing, Go-side logs
- [BUILD](docs/BUILD.md): prerequisites, options, troubleshooting
- [TESTING](docs/TESTING.md): test tiers, local and CI
- [RELEASING](docs/RELEASING.md): bump PRs and signed releases
- [DEVICES](docs/DEVICES.md): per-model compatibility
- [BACKGROUND](docs/BACKGROUND.md) and [FINDINGS](docs/FINDINGS.md): why the gap exists, investigation record

## Contributing

Reports from devices other than `AFTT` help most. Include `./scripts/device-check.sh` output, the release tag (or `TS_REF` if you built it), and `adb logcat` around the failure ([reading Go-side logs](docs/STATUS.md#reading-the-go-side-logs)). Redact tailnet hostnames, IPs and auth URLs.

Before opening a PR, run `make check`. See [docs/TESTING.md](docs/TESTING.md).

If this helped, a ⭐ helps others find it: `gh api --method PUT user/starred/drogers0/tailscale-firetv-fireos5`

## Legal

Tailscale is [BSD-3-Clause](https://github.com/tailscale/tailscale-android/blob/main/LICENSE). "Tailscale" is a trademark of Tailscale Inc., used here only to name the software. **Report problems with these builds here, not to Tailscale.**

The build scripts and docs in this repo are [MIT](LICENSE) © 2026 drogers0. That license does not cover the Tailscale source they compile.
