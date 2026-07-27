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

The GLES 3 requirement came from **Gio**, not from Tailscale. Once the UI moved to Jetpack
Compose it renders through Android's standard hardware canvas, which is perfectly happy on
GLES 2.0. **This is confirmed on real hardware** — see [Status](#status).

The Android-8 floor turns out to be separable from that fix. The commit that raised it
([`bf0e56469f`](https://github.com/tailscale/tailscale-android/commit/bf0e56469f))
touched 19 files, and its entire `build.gradle` change was one line:

```diff
-        minSdkVersion 22
+        minSdkVersion 26
```

No dependency was added or upgraded with it. So this repo checks out a **finished** release
and restores the old floor, in both places it is enforced:

| | |
|---|---|
| `android/build.gradle` | `minSdkVersion` → 22 |
| `gomobile bind` | `-androidapi` → 22 |

Overriding only the first yields an APK that installs and then dies in native code.

Default target is **1.64.0** — the earliest release with a complete Compose UI (working
settings screen and exit-node picker), and therefore the least accumulated reliance on
API 26+. Built `armeabi-v7a`-only, the single ABI these devices use. Tailscale dropped
Google Play Services before this release, so nothing here depends on services Fire OS
lacks.

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

**Working.** Verified on a Fire TV Stick 2nd gen (AFTT), Fire OS 5.2.9.5 — current-stable
Tailscale **1.98.8** with seven patches, routing traffic through an exit node.

| | |
|---|---|
| Builds at minSdk 22 | ✅ incl. `gomobile bind -androidapi 22` |
| Compose UI on GLES 2.0 | ✅ the original blocker |
| Login / tunnel / DERP | ✅ `derp-16 (mia)`, ~72 ms |
| Online, health clear | ✅ |
| Peer list | ✅ |
| **Exit node routing** | ✅ 1 MB download → **1,113,884 bytes over `tun0`** |

See [STATUS.md](STATUS.md) for the patch-by-patch breakdown, how to set an exit node from
a shell, and how to read the Go-side logs.

> Older releases are superseded and retained only as evidence:
> [RC1](../../releases/tag/1.59.53-fireos5-rc1) renders but its screens are stubs;
> [RC2](../../releases/tag/1.64.0-fireos5-rc2) has a complete UI but an older Go core and
> the connectivity bugs.

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
