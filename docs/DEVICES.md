# Device compatibility

Which hardware this build is for. The Fire TV Stick is the device it was developed against,
but nothing about the build is Amazon-specific.

Amazon rows come from Amazon's own
[device specifications](https://developer.amazon.com/docs/device-specs/device-specifications.html),
[Fire TV model codes](https://developer.amazon.com/docs/device-specs/identify-fire-tv-devices.html),
[Fire tablet model codes](https://developer.amazon.com/docs/device-specs/ft-identify-tablet-devices.html)
and [Fire OS version mapping](https://developer.amazon.com/docs/fire-tv/fire-os-overview.html).

## Verified

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

## What gates it

Two things decide whether this build runs:

| | |
|---|---|
| **API 22–25** | Android 5.1 through 7.1. 22 is this build's floor — API 21 and below cannot install it at all. At 26+ the [official client](https://tailscale.com/docs/install/android) works, so use that instead |
| **`armeabi-v7a`** | the published APKs are single-ABI. arm64 devices accept v7a; a v7a-less device needs `GOMOBILE_TARGET=android/arm64 ./scripts/build.sh` |

GLES 2.0 is *not* a third gate — Compose renders on either. It only decides **which problem
you had**:

| | |
|---|---|
| **GLES 2.0**, API 22–25 | nothing ever worked: new releases won't install, old ones install and die on the first frame |
| **GLES 3.x**, API 22–25 | 1.62.0 (Mar 2024) does render, so only the API floor bites — what this build buys is two years of fixes in the layer carrying your traffic |

Two things that vary with API level rather than hardware:

- **Always-on VPN is API 24+.** The [reboot gap](STATUS.md#reboot-behaviour) is a property
  of API 22–23, not of this build — on an API 24/25 device upstream's own mechanism should
  be available. Untested.
- **RAM.** Verified at 895 MB. Sub-512 MB devices are untested.

When in doubt, ask the device: `./scripts/device-check.sh <ip>:5555` prints the API level,
ABI list and `ro.opengles.version` and gives a verdict.

## Amazon Fire devices

The official client requires **Android 8.0 / API 26**, so every Fire OS 5 device (API 22)
*and* every Fire OS 6 one (API 25) is out of its reach. All are 32-bit `armeabi-v7a`. Model
codes are what `ro.product.model` reports.

### Fire TV — Fire OS 5, API 22

| | Model / codename | GPU | GLES |
|---|---|---|---|
| **Fire TV Stick 2nd gen** (2016–2019) | `AFTT` / tank | Mali-450 MP4 | **2.0** ✅ verified |
| Fire TV Stick Basic Edition (2017) | `AFTT` | Mali-450 MP4 | **2.0** — same model code |
| Fire TV Stick 1st gen (2014) | `AFTM` / montoya | Broadcom VideoCore IV | **2.0** |
| Fire TV 1st gen (2014) | `AFTB` / bueller | Adreno 320 | 3.0 |
| Fire TV 2nd gen (2015) | `AFTS` / sloane | PowerVR Rogue GX6250 | 3.0 |
| Element 4K Fire TV (2017) | `AFTRS` | — | — |

Amazon has withdrawn the specs for the Element set, so its GPU is unknown — run
`device-check.sh` if you have one.

### Fire TV — Fire OS 6, API 25

Still below the official client's floor. All GLES 3.x, so the API level is the only barrier.

| | Model |
|---|---|
| Fire TV 3rd gen (2017) | `AFTN` |
| Fire TV Cube 1st gen (2018) | `AFTA` |
| Fire TV Stick 4K 1st gen (2018) | `AFTMM` |
| Nebula / TCL Soundbar Fire TV Edition (2019) | `AFTMM` |
| Insignia 4K Fire TV (2018) | `AFTJMST12` |
| Toshiba 4K Fire TV (2018–2019) | `AFTKMST12` |
| Toshiba HD Fire TV (2018–2020) | `AFTBAMR311` |
| Insignia HD Fire TV (2018–2020) | `AFTEAMR311` |
| Onida HD Fire TV (2019) | `AFTLE` |
| Onida HD/FHD Fire TV (2020) | `AFTTIFF55` |
| AmazonBasics HD/FHD Fire TV (2020) | `AFTBU001` |

### Fire tablets — Fire OS 5, API 22

Two of these are exact `AFTT` matches — same Mali-450, same GLES 2.0, same API level.

| | Model | GPU | GLES |
|---|---|---|---|
| Fire 7 (2017, 7th gen) | `KFAUWI` | Mali-450 MP4 | **2.0** |
| Fire (2015, 5th gen) | `KFFOWI` | Mali-450 | **2.0** |
| Fire HD 8 (2017, 7th gen) | `KFDOWI` | Mali-T720 MP2 | 3.1 |
| Fire HD 10 (2017, 7th gen) | `KFSUWI` | PowerVR GX6250 | 3.1 |
| Fire HD 8 (2016, 6th gen) | `KFGIWI` | Mali-T720 MP2 | 3.1 |
| Fire HD 8 (2015, 5th gen) | `KFMEWI` | — | 3.0 |
| Fire HD 10 (2015, 5th gen) | `KFTBWI` | — | 3.0 |
| Fire HDX 8.9 (2014, 4th gen) | `KFSAWI` / `KFSAWA` | Adreno 420 | 3.1 |
| Fire HD 7 (2014, 4th gen) | `KFASWI` | PowerVR G6200 | 3.0 |
| Fire HD 6 (2014, 4th gen) | `KFARWI` | PowerVR G6200 | 3.0 |

There are no Fire OS 6 tablets — the Fire OS 6 generation was Fire TV only, and Fire HD 8
(2018) now reports Fire OS 7.

### Out of range

| | |
|---|---|
| Fire OS 7 and 8 (API 28/30) | Fire TV Stick 3rd gen and Lite, Stick 4K 2nd gen, Stick 4K Max, Cube 2nd/3rd gen, Fire TV 2/4-Series, Omni, and 2018-and-later tablets. Use the [official client](https://tailscale.com/docs/install/amazon-fire) |
| Fire OS 4 and earlier (API 19 ↓) | Kindle Fire HDX 7 / HDX 8.9 / HD 7 (2013) at API 19, 2012 models at API 15, 2011 at API 10 — under this build's floor, nothing to be done |
| Vega OS | Fire TV Stick 4K Select (2025) and Stick HD (2026) are not Android at all, which is why Tailscale lists the 4K Select as unsupported |

## Non-Amazon devices

Any Android 5.1–7.1 device is in range. The GLES 2.0 half of the problem is decided
entirely by GPU family, so you can read it off the silicon:

| GPU family | GLES | |
|---|---|---|
| **ARM Mali-400 / 450 / 470** (Utgard) | **2.0** | never supported ES 3 at all — the `AFTT` case |
| **Broadcom VideoCore IV** | **2.0** | Fire TV Stick 1st gen, Raspberry Pi-class silicon |
| **PowerVR SGX 5-series** (540, 544) | **2.0** | older MediaTek / TI OMAP; usually below the API 22 floor |
| **Qualcomm Adreno 2xx** (200–225) | **2.0** | Android 4.x era, so usually below the floor too |
| **Vivante GC1000 / GC2000** | **2.0** | i.MX6-class tablets and boards |
| Adreno 3xx and up, Mali-T / Mali-G, PowerVR Rogue | 3.0+ | API level is the only barrier |

Mali-400/450 is the one that matters, because it is what nearly all cheap 2014–2017 silicon
shipped:

| SoC | GPU | Typical Android | Found in |
|---|---|---|---|
| Amlogic S805 / S812 | Mali-450 MP2 / MP6 | 5.1 | MXQ, M8S and the whole clone-box wave; vendor updates stopped in 2016 |
| Amlogic S905 / S905X | Mali-450 MP3 | 5.1, 6.0, 7.1 | the 2016–2017 TV-box generation |
| Rockchip RK3128 / RK3229 | Mali-400 MP2 | 5.1, 7.1 | budget boxes and HDMI sticks |
| Rockchip RK3328 | Mali-450 MP2 | 7.1 | later budget boxes |
| MediaTek MT6580 | Mali-400 MP2 | 5.1, 6.0 | very large volume of sub-$100 phones |
| Spreadtrum SC7731 / SC8830 / SC9830 | Mali-400 MP2 | 5.1 | entry-level phones incl. some Galaxy J variants |
| Allwinner A33 / A64 / H3 | Mali-400 MP2 / Mali-450 | 5.1, 6.0 | white-label tablets and boxes |

A named example, since model numbers are the usual point of confusion: the **Samsung
Galaxy J3 (2016)** `SM-J320H` / `SM-J320F` is Android 5.1.1 on a Spreadtrum SC8830/SC9830
with a **Mali-400 MP2** — GLES 2.0, `armeabi-v7a`, the `AFTT` case exactly.

> [!NOTE]
> Sibling model numbers are not interchangeable. The US Galaxy J3 (2016) shipped an Exynos
> 3475 with a Mali-T720 (GLES 3.1) instead, and some J3 variants later took an Android 6/7
> update — still inside API 22–25 either way, but check the device, not the marketing name.
> Amlogic **S912** is likewise the exception in its family: Mali-T820, GLES 3.2.

### GLES 3, but still stranded below API 26

The larger group. Any device whose final Android was 5.1, 6.0 or 7.x cannot run current
Tailscale, regardless of GPU — including a lot of hardware people still keep around:

| | Last Android |
|---|---|
| Nexus 5, Nexus 7 (2013) | 6.0.1 |
| Nexus 6, Nexus 9 | 7.1.1 |
| Galaxy S5, Galaxy Note 4, Note Edge | 6.0.1 |
| LG G3, Moto G 2nd/3rd gen, Xperia Z3, OnePlus One | 6.0 / 6.0.1 |
| Razer Forge TV | 6.0.1 |

Watch the boundary in both directions: **Galaxy S4** topped out at 5.0.1 — API 21, under
this build's floor — while **Nexus Player** and **Xiaomi Mi Box 3** did receive Oreo and are
therefore served by the official client.

Everything outside the verified `AFTT` row is **untested**. Please open an issue with
`scripts/device-check.sh` output if you try one.
