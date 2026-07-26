# Tailscale for Fire OS 5 (Fire TV Stick 2nd gen)

An unofficial, reproducible build of the **Tailscale Android client** that actually runs on
**Fire OS 5 / Android 5.1 (API 22)** hardware with an **OpenGL ES 2.0** GPU — devices the
official app cannot support.

> **Unofficial community build.** Not affiliated with, endorsed by, or supported by
> Tailscale Inc. See [Legal](#legal).

---

## The problem

Getting Tailscale onto a 2016-era Fire TV Stick fails from both directions, and the two
failures hide each other:

| | Runs on Android 5.1? | Renders on OpenGL ES 2.0? |
|---|---|---|
| Tailscale ≤ 1.62.0 (Gio UI) | **Yes** (minSdk 22) | **No** — needs GLES 3 |
| Tailscale ≥ 1.64.0 (Compose UI) | **No** (minSdk 26) | Yes |

Older releases install and connect, then die rendering their first frame:

```
fatal error: no support for OpenGL ES 3 nor EXT_sRGB
```

Newer releases fixed that by replacing the [Gio](https://gioui.org) UI with Jetpack
Compose — but by then the floor had moved to Android 8.0.

The usual advice is that this gap is unbridgeable. It isn't, quite.

## The fix

Upstream commit [`3926cf4b56`](https://github.com/tailscale/tailscale-android/commit/3926cf4b5611d444dae7efc50499f477371e7327)
(2024-03-13) is the **last commit where the Compose rewrite and `minSdkVersion 22` coexist.**
The very next commit raised the floor to 26. Tailscale never shipped a release from that
window, so this combination has never existed as a downloadable APK.

This repo builds it.

- **Compose UI** → renders through Android's standard hardware canvas, no GLES 3 required
- **minSdk 22** → installs on Android 5.1
- **fdroid flavor** → no Google Play Services, which Fire OS lacks
- **armeabi-v7a only** → the single ABI these devices use

Upstream Go module pinned at `tailscale.com v1.61.0-pre.0.20240311120500-7429e8912acb`,
so the client is roughly **v1.61/1.62 era** — about two years newer than the last APK that
will otherwise start on this hardware.

## Verified target device

Everything here was developed against, and tested on:

| | |
|---|---|
| Device | Fire TV Stick (2nd generation) |
| Model / codename | `AFTT` / `tank` — retail marking **LY73PR** |
| Fire OS | 5.2.9.5 (`288.6.8.8_user_688806320`) |
| Android | 5.1.1, **API 22** |
| ABI | `armeabi-v7a` (no arm64, no x86) |
| GPU | ARM **Mali-450 MP**, `ro.opengles.version=131072` (**GLES 2.0**) |
| Display | 1920x1080 @ 320 dpi |
| RAM | 895 MB total |

Check your own device before building:

```sh
./scripts/device-check.sh <adb-target>
```

### Should also apply to

Any Fire OS 5 device reporting API 22 and GLES 2.0 — e.g. Fire TV Stick 1st gen (`AFTB`),
Fire TV 1st/2nd gen (`AFTB`/`AFTS`). **Untested.** If you try one, please open an issue
with the output of `device-check.sh`.

### Not needed for

Fire TV devices released after 2018. Those run Fire OS 6+ / Android 7+ with GLES 3
hardware — use the [official Tailscale client](https://tailscale.com/docs/install/amazon-fire).

## Status

| | |
|---|---|
| Builds reproducibly | see [BUILD.md](BUILD.md) |
| Installs on API 22 | ✅ verified |
| Reaches control plane | ✅ verified (even the 2020 client does) |
| UI renders on GLES 2.0 | ⏳ **the open question this repo exists to answer** |
| Login / exit node selection | ⏳ untested |

The Compose module was an unshipped, in-flight rewrite when this commit was cut, and
Tailscale raised minSdk to 26 immediately afterward — possibly because they hit a runtime
problem at API 22. That risk is real and unproven either way. Releases here are published
as **release candidates** until confirmed on hardware.

## Quick start

```sh
git clone git@github.com:drogers0/tailscale-firetv-fireos5.git
cd tailscale-firetv-fireos5
./scripts/build.sh                       # ~10 min, see BUILD.md for prerequisites
adb connect <fire-stick-ip>:5555
adb install -r dist/tailscale-fireos5-*.apk
```

Prefer not to build? Grab an APK from
[Releases](https://github.com/drogers0/tailscale-firetv-fireos5/releases) and verify its
`sha256` against the checksum published alongside it.

## Documentation

- **[BUILD.md](BUILD.md)** — prerequisites, build, troubleshooting, reproducibility
- **[FINDINGS.md](FINDINGS.md)** — how the minSdk window was found, GLES root-cause
  evidence, and everything ruled out along the way

## Legal

Tailscale is licensed **BSD-3-Clause**; that license permits redistribution of built
binaries, and the upstream `LICENSE` is preserved in every artifact produced here.

"Tailscale" is a trademark of Tailscale Inc. This project is not affiliated with or
endorsed by them, uses the name only to identify what the software is, and should not be
mistaken for an official distribution. **Do not report problems with these builds to
Tailscale.** Open an issue here instead.

APKs are **debug-signed** (`assembleFdroidDebug`) and share the upstream application ID
`com.tailscale.ipn`, so they cannot be installed alongside an official Tailscale build.

Build scripts in this repo are MIT licensed — see [LICENSE](LICENSE). That covers the
scripts only, not the Tailscale source they compile.
