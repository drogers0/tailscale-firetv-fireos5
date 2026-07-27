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

**Should also apply to** any Fire OS 5 device reporting API 22 and GLES 2.0 — Fire TV Stick
1st gen (`AFTB`), Fire TV 1st/2nd gen (`AFTB`/`AFTS`). Untested; please open an issue with
`scripts/device-check.sh` output if you try one.

**Not needed for** Fire TV devices released after 2018 — Fire OS 6+ / Android 7+ with GLES 3
hardware. Use the [official client](https://tailscale.com/docs/install/amazon-fire).
