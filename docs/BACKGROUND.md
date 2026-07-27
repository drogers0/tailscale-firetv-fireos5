# Background — why this repo exists

Getting Tailscale onto a 2016-era Fire TV Stick fails from both directions, and the two
failures conceal each other.

| | Runs on Android 5.1? | Renders on OpenGL ES 2.0? |
|---|---|---|
| Tailscale ≤ 1.62.0 (Gio UI) | **Yes** (minSdk 22) | **No** — needs GLES 3 |
| Tailscale ≥ 1.64.0 (Compose UI) | **No** (minSdk 26) | Yes |

Older releases install and connect, then die rendering their first frame:

```
fatal error: no support for OpenGL ES 3 nor EXT_sRGB
```

Newer releases fixed that by replacing the [Gio](https://gioui.org) UI with Jetpack
Compose — but by then the floor had moved to Android 8.0. The usual conclusion is that the
gap is unbridgeable.

## Why it isn't

The GLES 3 requirement came from **Gio**, not from Tailscale. Compose renders through
Android's standard hardware canvas, which is perfectly happy on GLES 2.0.

And the Android-8 floor is separable from that fix. The commit that raised it
([`bf0e56469f`](https://github.com/tailscale/tailscale-android/commit/bf0e56469f)) touched
19 files, and its entire `build.gradle` change was one line:

```diff
-        minSdkVersion 22
+        minSdkVersion 26
```

No dependency was added or upgraded alongside it. The floor was a judgment call, not a
technical requirement — so this repo checks out a finished release and restores it.

## The floor is enforced in two places

| | |
|---|---|
| `android/build.gradle` | `minSdkVersion` |
| `gomobile bind` | `-androidapi` |

Overriding only the first yields an APK that installs and then dies in native code.

## Why 1.98.8 rather than an older release

Decided empirically rather than by argument. The codebase splits in two, and the risks sit
in different halves:

| Layer | Risk if old | Risk if new |
|---|---|---|
| Go / `libtailscale` — WireGuard, control protocol, crypto | **security**, control-plane drift | none |
| Kotlin/Java UI | none | **API-26 assumptions** |

Freezing on 2024's 1.64.0 freezes *both*. Building both and counting:

| | 1.64.0 | 1.98.8 |
|---|---|---|
| Patches needed | 1 | 6 (+1 build flag) |
| `gomobile bind -androidapi 22` | works | works |
| Manifest merger at minSdk 22 | clean | clean |

Five extra patches buys two years of security fixes in the layer that carries traffic, and
cheap rebases as upstream moves. No library rejected minSdk 22, and the native layer
cross-compiles for API 22 without complaint — upstream's real debt is a handful of API
guards that rotted once they became dead code at minSdk 26.

## Device compatibility

Developed and verified on:

| | |
|---|---|
| Device | Fire TV Stick (2nd generation) |
| Model / codename | `AFTT` / `tank` — retail marking **LY73PR** |
| Fire OS | 5.2.9.5 (`288.6.8.8_user_688806320`) |
| Android | 5.1.1, **API 22** |
| ABI | `armeabi-v7a` (no arm64, no x86) |
| GPU | ARM **Mali-450 MP**, `ro.opengles.version=131072` (**GLES 2.0**) |
| Display | 1920x1080 @ 320 dpi |
| RAM | 895 MB |

### What actually gates it

Nothing here is Amazon-specific. Two things decide whether this build runs:

| | |
|---|---|
| **API 22–25** | 22 is this build's floor; at 26+ the [official client](https://tailscale.com/docs/install/android) installs, so use that instead |
| **`armeabi-v7a`** | the published APKs are single-ABI. arm64 devices accept v7a; a v7a-less device needs `GOMOBILE_TARGET=android/arm64 ./scripts/build.sh` |

GLES 2.0 is *not* a third gate — Compose is happy on either. It only decides **which
problem you had**: on GLES 2.0 nothing worked at all, while on GLES 3 hardware below API 26
the last Gio release (1.62.0) did render, so what this build buys is two years of fixes.

### Amazon Fire devices

The official client requires **Android 8.0 / API 26**, which leaves out every Fire OS 5
device (API 22) *and* every Fire OS 6 one (API 25) — all of them 32-bit `armeabi-v7a`
([Amazon device specs](https://developer.amazon.com/docs/device-specs/device-specifications.html),
[Fire OS versions](https://developer.amazon.com/docs/fire-tv/fire-os-overview.html)):

| | API | GLES | |
|---|---|---|---|
| **Fire TV Stick 2nd gen** — `AFTT` / `tank` | 22 | **2.0** | verified above |
| Fire TV Stick 1st gen — `AFTM` / `montoya` | 22 | **2.0** | VideoCore IV; same double failure as `AFTT` |
| Fire 7 tablet (2017, 7th gen) | 22 | **2.0** | Mali-450 MP4 |
| Fire tablet (2015, 5th gen) | 22 | **2.0** | Mali-450 |
| Fire TV 1st gen — `AFTB` / `bueller` | 22 | 3.0 | Adreno 320 — API floor only |
| Fire TV 2nd gen — `AFTS` / `sloane` | 22 | 3.0 | PowerVR GX6250 |
| Fire HD 6/7 (2014), Fire HD 8/10 (2015–2017) | 22 | 3.0–3.1 | PowerVR / Mali-T720 |
| Fire OS 6 — `AFTN`, Cube 1st gen, Stick 4K 1st gen, Fire TV Edition sets | 25 | 3.x | |

**Not needed for** Fire OS 7 and later (API 28+) — Fire TV Stick 3rd gen, Stick 4K 2nd gen,
2020-and-later tablets. Use the [official client](https://tailscale.com/docs/install/amazon-fire).

### Non-Amazon devices

Any Android 5.1–7.1 device is in range, and cheap 2015–2016 hardware often lands in the
GLES 2.0 class as well — ARM's Utgard GPUs (**Mali-400 / Mali-450**) never supported
GLES 3, so those are the `AFTT` case exactly:

| | |
|---|---|
| Samsung Galaxy J3 (2016) — `SM-J320H`, `SM-J320F` | Android 5.1.1, Spreadtrum SC8830/SC9830, **Mali-400 MP2**, v7a |
| Amlogic S805 TV boxes (MXQ and its clones) | Android 5.1, **Mali-450**, v7a — abandoned by their vendors in 2016 |
| Budget Allwinner / Rockchip tablets of the same era | commonly Android 5.1 with a Mali-400-class GPU |

> [!NOTE]
> Sibling model numbers are not interchangeable. The US Galaxy J3 (2016) shipped an
> Exynos 3475 with a Mali-T720 (GLES 3.1) instead, and some J3 variants later took an
> Android 6/7 update — still inside API 22–25, so this build applies either way, but check
> the device rather than the marketing name.

Everything outside the verified row is **untested**. Please open an issue with
`scripts/device-check.sh` output if you try one.
