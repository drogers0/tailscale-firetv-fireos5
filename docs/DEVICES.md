# Device compatibility

Which hardware this build is for. The Fire TV Stick is the device it was developed against,
but nothing about the build is Amazon-specific.

Every table below uses the same columns, so rows can be compared across sections:

| Column | |
|---|---|
| **Verdict** | `Required` — this build or nothing. GLES 2.0 at API 22–25: current releases refuse to install, and pre-1.64.0 releases install then die on the first frame |
| | `Recommended` — this build or a two-year-old release. GLES 3.x at API 22–25: the official client still won't install, but Tailscale 1.62.0 (Mar 2024) does render, so what you gain is two years of fixes rather than a working app |
| | `Official` — API 26+. Use the [official client](https://tailscale.com/docs/install/android) |
| | `Neither` — below this build's API 22 floor, or not Android. Nothing here helps |
| **Tested** | ✅ verified on hardware · — untested |

Amazon rows come from Amazon's own
[device specifications](https://developer.amazon.com/docs/device-specs/device-specifications.html),
[Fire TV model codes](https://developer.amazon.com/docs/device-specs/identify-fire-tv-devices.html),
[Fire tablet model codes](https://developer.amazon.com/docs/device-specs/ft-identify-tablet-devices.html)
and [Fire OS version mapping](https://developer.amazon.com/docs/fire-tv/fire-os-overview.html).

## Verified

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

## What gates it

Two things decide whether this build runs at all:

| | |
|---|---|
| **API 22–25** | Android 5.1 through 7.1. 22 is this build's floor — API 21 and below cannot install it. At 26+ the official client works, so use that |
| **`armeabi-v7a`** | the published APKs are single-ABI. arm64 devices accept v7a; a v7a-less device needs `GOMOBILE_TARGET=android/arm64 ./scripts/build.sh` |

GLES 2.0 is *not* a third gate — Compose renders on either. It only separates `Required`
from `Recommended`, and it follows from the GPU family:

| GPU family | GLES | |
|---|---|---|
| **ARM Mali-400 / 450 / 470** (Utgard) | **2.0** | never supported ES 3 at all — by far the most common case |
| **Broadcom VideoCore IV** | **2.0** | Fire TV Stick 1st gen, Raspberry Pi-class silicon |
| **PowerVR SGX 5-series** (540, 544) | **2.0** | older MediaTek / TI OMAP, usually below the API 22 floor |
| **Qualcomm Adreno 2xx** (200–225) | **2.0** | Android 4.x era, so usually below the floor too |
| **Vivante GC1000 / GC2000** | **2.0** | i.MX6-class tablets and boards |
| Adreno 3xx and up, Mali-T / Mali-G, PowerVR Rogue | 3.0+ | API level is the only barrier |

Two things that vary with API level rather than hardware:

- **Always-on VPN is API 24+.** The [reboot gap](STATUS.md#reboot-behaviour) is a property
  of API 22–23, not of this build — on an API 24/25 device upstream's own mechanism should
  be available. Untested.
- **RAM.** Verified at 895 MB. Sub-512 MB devices are untested.

When in doubt, ask the device: `./scripts/device-check.sh <ip>:5555` prints the API level,
ABI list and `ro.opengles.version`, and gives a verdict.

## Amazon Fire TV — Fire OS 5, API 22

| Device | Model | API | GPU | GLES | Verdict | Tested |
|---|---|---|---|---|---|---|
| Fire TV Stick 2nd gen (2016–2019) | `AFTT` / tank | 22 | Mali-450 MP4 | **2.0** | **Required** | ✅ |
| Fire TV Stick Basic Edition (2017) | `AFTT` | 22 | Mali-450 MP4 | **2.0** | **Required** | — |
| Fire TV Stick 1st gen (2014) | `AFTM` / montoya | 22 | Broadcom VideoCore IV | **2.0** | **Required** | — |
| Fire TV 1st gen (2014) | `AFTB` / bueller | 22 | Adreno 320 | 3.0 | Recommended | — |
| Fire TV 2nd gen (2015) | `AFTS` / sloane | 22 | PowerVR Rogue GX6250 | 3.0 | Recommended | — |
| Element 4K Fire TV (2017) | `AFTRS` | 22 | ARM Mali, model unstated | ? | Recommended † | — |

The Basic Edition reports the same `AFTT` model code as the verified device and is the same
hardware, but was not separately tested.

## Amazon Fire TV — Fire OS 6, API 25

Below the official client's API 26 floor, so still stranded. **Two of these are GLES 2.0** —
Amazon put the Mali-450 Amlogic S905Z in both the pendant Fire TV and the first Cube, so on
those the old Gio releases crash exactly as they do on `AFTT`.

| Device | Model | API | GPU | GLES | Verdict | Tested |
|---|---|---|---|---|---|---|
| Fire TV 3rd gen (2017) | `AFTN` | 25 | Mali-450 MP3 (Amlogic S905Z) | **2.0** | **Required** | — |
| Fire TV Cube 1st gen (2018) | `AFTA` | 25 | Mali-450 MP3 (Amlogic S905Z) | **2.0** | **Required** | — |
| Fire TV Stick 4K 1st gen (2018) | `AFTMM` | 25 | IMG GE8300 (MT8695) | 3.2 | Recommended | — |
| Nebula / TCL Soundbar Fire TV Edition (2019) | `AFTMM` | 25 | IMG GE8300 (MT8695) | 3.2 | Recommended | — |
| Insignia 4K Fire TV (2018) | `AFTJMST12` | 25 | unpublished | ? | Recommended † | — |
| Toshiba 4K Fire TV (2018–2019) | `AFTKMST12` | 25 | unpublished | ? | Recommended † | — |
| Toshiba HD Fire TV (2018–2020) | `AFTBAMR311` | 25 | unpublished | ? | Recommended † | — |
| Insignia HD Fire TV (2018–2020) | `AFTEAMR311` | 25 | unpublished | ? | Recommended † | — |
| Onida HD Fire TV (2019) | `AFTLE` | 25 | unpublished | ? | Recommended † | — |
| Onida HD/FHD Fire TV (2020) | `AFTTIFF55` | 25 | unpublished | ? | Recommended † | — |
| AmazonBasics HD/FHD Fire TV (2020) | `AFTBU001` | 25 | unpublished | ? | Recommended † | — |

> [!NOTE]
> † Amazon has withdrawn the specs for these sets, so their GLES level is unknown. The
> verdict is `Recommended` at minimum; if the GPU turns out to be Mali-450, as it is on
> much TV silicon of that era, it is `Required`. Run `device-check.sh` and open an issue.

## Amazon Fire tablets — Fire OS 5, API 22

Two of these are exact `AFTT` matches. There are no Fire OS 6 tablets — that generation was
Fire TV only, and Fire HD 8 (2018) now reports Fire OS 7.

| Device | Model | API | GPU | GLES | Verdict | Tested |
|---|---|---|---|---|---|---|
| Fire 7 (2017, 7th gen) | `KFAUWI` | 22 | Mali-450 MP4 | **2.0** | **Required** | — |
| Fire (2015, 5th gen) | `KFFOWI` | 22 | Mali-450 | **2.0** | **Required** | — |
| Fire HD 8 (2017, 7th gen) | `KFDOWI` | 22 | Mali-T720 MP2 | 3.1 | Recommended | — |
| Fire HD 10 (2017, 7th gen) | `KFSUWI` | 22 | PowerVR GX6250 | 3.1 | Recommended | — |
| Fire HD 8 (2016, 6th gen) | `KFGIWI` | 22 | Mali-T720 MP2 | 3.1 | Recommended | — |
| Fire HD 8 (2015, 5th gen) | `KFMEWI` | 22 | unpublished | 3.0 | Recommended | — |
| Fire HD 10 (2015, 5th gen) | `KFTBWI` | 22 | unpublished | 3.0 | Recommended | — |
| Fire HDX 8.9 (2014, 4th gen) | `KFSAWI` / `KFSAWA` | 22 | Adreno 420 | 3.1 | Recommended | — |
| Fire HD 7 (2014, 4th gen) | `KFASWI` | 22 | PowerVR G6200 | 3.0 | Recommended | — |
| Fire HD 6 (2014, 4th gen) | `KFARWI` | 22 | PowerVR G6200 | 3.0 | Recommended | — |

## Amazon — out of range

| Device | Model | API | GPU | GLES | Verdict | Tested |
|---|---|---|---|---|---|---|
| Fire TV Stick 3rd gen / Lite, Stick 4K 2nd gen, Stick 4K Max, Cube 2nd/3rd gen, Fire TV 2/4-Series, Omni | various | 28–30 | various | 3.2 | Official | — |
| Fire tablets, 2018 and later | various | 28–30 | various | 3.1+ | Official | — |
| Kindle Fire HDX 7 / HDX 8.9 / HD 7 (2013) | `KFTHWI` / `KFAPWI` / `KFSOWI` | 19 | Adreno 330 | — | Neither | — |
| Kindle Fire HD 7 / HD 8.9, Kindle Fire (2012) | `KFTT` / `KFJWI` / `KFOT` | 15 | PowerVR SGX540 | — | Neither | — |
| Kindle Fire (2011) | — | 10 | PowerVR SGX540 | — | Neither | — |
| Fire TV Stick 4K Select (2025), Stick HD (2026) | `AFTCA002` / `AFTCL001` | n/a | — | — | Neither | — |

The last row runs **Vega OS**, which is not Android at all — which is why Tailscale lists
the 4K Select as unsupported. No Android APK can help there.

## Non-Amazon — GLES 2.0 silicon

The `AFTT` case exactly, and much more common than the Fire hardware. `Model` here is the
SoC, since these ship under hundreds of brand names. API is what the class typically
shipped with.

| Device | Model | API | GPU | GLES | Verdict | Tested |
|---|---|---|---|---|---|---|
| MXQ, M8S and the clone-box wave | Amlogic S805 / S812 | 22 | Mali-450 MP2 / MP6 | **2.0** | **Required** | — |
| The 2016–17 TV-box generation | Amlogic S905 / S905X | 22–25 | Mali-450 MP3 | **2.0** | **Required** | — |
| Budget boxes and HDMI sticks | Rockchip RK3128 / RK3229 | 22–25 | Mali-400 MP2 | **2.0** | **Required** | — |
| Later budget boxes | Rockchip RK3328 | 25 | Mali-450 MP2 | **2.0** | **Required** | — |
| Sub-$100 phones, very high volume | MediaTek MT6580 | 22–23 | Mali-400 MP2 | **2.0** | **Required** | — |
| Galaxy J3 2016 `SM-J320H` / `SM-J320F`, entry phones | Spreadtrum SC7731 / SC8830 / SC9830 | 22 | Mali-400 MP2 | **2.0** | **Required** | — |
| White-label tablets and boxes | Allwinner A33 / A64 / H3 | 22–23 | Mali-400 MP2 / Mali-450 | **2.0** | **Required** | — |

> [!NOTE]
> Sibling model numbers are not interchangeable. The US Galaxy J3 (2016) shipped an Exynos
> 3475 with a Mali-T720 (GLES 3.1) instead, and some J3 variants later took an Android 6/7
> update — still inside API 22–25 either way, but check the device, not the marketing name.
> Amlogic **S912** is likewise the exception in its family: Mali-T820, GLES 3.2.

## Non-Amazon — GLES 3, stranded below API 26

The larger group. Any device whose final Android was 5.1, 6.0 or 7.x cannot run current
Tailscale regardless of GPU, which covers a lot of hardware people still keep around. The
last three rows are the boundary cases, and they fall on the other side.

| Device | Model | API | GPU | GLES | Verdict | Tested |
|---|---|---|---|---|---|---|
| Nexus 5 | — | 23 | Adreno 330 | 3.0 | Recommended | — |
| Nexus 7 (2013) | — | 23 | Adreno 320 | 3.0 | Recommended | — |
| Nexus 6 | — | 25 | Adreno 420 | 3.1 | Recommended | — |
| Nexus 9 | — | 25 | Tegra K1 | 3.1 | Recommended | — |
| Galaxy S5 | — | 23 | Adreno 330 | 3.0 | Recommended | — |
| Galaxy Note 4 / Note Edge | — | 23 | Adreno 420 / Mali-T760 | 3.1 | Recommended | — |
| LG G3 | — | 23 | Adreno 330 | 3.0 | Recommended | — |
| Moto G 2nd / 3rd gen | — | 23 | Adreno 305 / 306 | 3.0 | Recommended | — |
| Xperia Z3 | — | 23 | Adreno 330 | 3.0 | Recommended | — |
| OnePlus One | — | 23 | Adreno 330 | 3.0 | Recommended | — |
| Razer Forge TV | — | 23 | Adreno 420 | 3.1 | Recommended | — |
| Galaxy S4 — stopped at Android 5.0.1 | — | 21 | Adreno 320 / Mali-T628 | 3.0 | Neither | — |
| Nexus Player — did receive Oreo | — | 26 | PowerVR G6430 | 3.1 | Official | — |
| Xiaomi Mi Box 3 — did receive Oreo | — | 26 | Mali-450 | 2.0 | Official | — |

Mi Box 3 is the instructive one: GLES 2.0 hardware, but Oreo took it to API 26, so the
official client installs and Compose renders on it. GLES 2.0 alone was never the problem.

---

Everything outside the verified `AFTT` row is **untested**. Please open an issue with
`scripts/device-check.sh` output if you try one.
