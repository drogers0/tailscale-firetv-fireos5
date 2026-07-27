# Device compatibility

Which hardware this build is for. The Fire TV Stick is the device it was developed against,
but nothing about the build is Amazon-specific.

Amazon rows come from Amazon's own
[device specifications](https://developer.amazon.com/docs/device-specs/device-specifications.html),
[Fire TV model codes](https://developer.amazon.com/docs/device-specs/identify-fire-tv-devices.html),
[Fire tablet model codes](https://developer.amazon.com/docs/device-specs/ft-identify-tablet-devices.html)
and [Fire OS version mapping](https://developer.amazon.com/docs/fire-tv/fire-os-overview.html).

## What gates it

Two things decide whether this build runs at all:

| | |
|---|---|
| **API 22–25** | Android 5.1 through 7.1. 22 is this build's floor — API 21 and below cannot install it. At 26+ the official client works, so use that |
| **`armeabi-v7a`** | the published APKs are single-ABI. arm64 devices accept v7a; a v7a-less device needs `GOMOBILE_TARGET=android/arm64 ./scripts/build.sh` |

GLES 2.0 is *not* a third gate — Compose renders on either. It only separates 🔴 `Required`
from 🟡 `Recommended` in the table below, and it follows from the GPU family:

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

## The table

**Verdict** — how badly you need this build:

- 🔴 **Required** — this build or nothing. GLES 2.0 at API 22–25: current releases refuse to
  install, and pre-1.64.0 releases install then die on the first frame.
- 🟡 **Recommended** — this build, or a two-year-old release. GLES 3.x at API 22–25: the
  official client still won't install, but 1.62.0 (Mar 2024) renders — so what you gain is
  two years of fixes rather than a working app.
- 🟢 **Official** — API 26+. Use the [official client](https://tailscale.com/docs/install/android).
- ⚫ **Neither** — below the API 22 floor, or not Android. Nothing here helps.

**Tested** — ✅ verified on hardware, — untested.

<table>
<thead>
<tr><th align="left">Device</th><th align="left">Model</th><th align="left">API</th><th align="left">GPU</th><th align="left">GLES</th><th align="left">Verdict</th><th align="left">Tested</th></tr>
</thead>
<tbody>
<tr><th colspan="7" align="center">🔹&nbsp; AMAZON FIRE TV &nbsp;🔹</th></tr>
<tr><td>Fire TV Stick 2nd gen (2016–2019)</td><td><code>AFTT</code> / tank</td><td>22</td><td>Mali-450 MP4</td><td><b>2.0</b></td><td>🔴 <b>Required</b></td><td>✅</td></tr>
<tr><td>Fire TV Stick Basic Edition (2017)</td><td><code>AFTT</code></td><td>22</td><td>Mali-450 MP4</td><td><b>2.0</b></td><td>🔴 <b>Required</b></td><td>— †</td></tr>
<tr><td>Fire TV Stick 1st gen (2014)</td><td><code>AFTM</code> / montoya</td><td>22</td><td>Broadcom VideoCore IV</td><td><b>2.0</b></td><td>🔴 <b>Required</b></td><td>—</td></tr>
<tr><td>Fire TV 3rd gen (2017)</td><td><code>AFTN</code></td><td>25</td><td>Mali-450 MP3 (Amlogic S905Z)</td><td><b>2.0</b></td><td>🔴 <b>Required</b></td><td>—</td></tr>
<tr><td>Fire TV Cube 1st gen (2018)</td><td><code>AFTA</code></td><td>25</td><td>Mali-450 MP3 (Amlogic S905Z)</td><td><b>2.0</b></td><td>🔴 <b>Required</b></td><td>—</td></tr>
<tr><td>Fire TV 1st gen (2014)</td><td><code>AFTB</code> / bueller</td><td>22</td><td>Adreno 320</td><td>3.0</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><td>Fire TV 2nd gen (2015)</td><td><code>AFTS</code> / sloane</td><td>22</td><td>PowerVR Rogue GX6250</td><td>3.0</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><td>Fire TV Stick 4K 1st gen (2018)</td><td><code>AFTMM</code></td><td>25</td><td>IMG GE8300 (MT8695)</td><td>3.2</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><td>Nebula / TCL Soundbar Fire TV Edition (2019)</td><td><code>AFTMM</code></td><td>25</td><td>IMG GE8300 (MT8695)</td><td>3.2</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><td>Element 4K Fire TV (2017)</td><td><code>AFTRS</code></td><td>22</td><td>ARM Mali, model unstated</td><td>?</td><td>🟡 Recommended ‡</td><td>—</td></tr>
<tr><td>Insignia 4K Fire TV (2018)</td><td><code>AFTJMST12</code></td><td>25</td><td>unpublished</td><td>?</td><td>🟡 Recommended ‡</td><td>—</td></tr>
<tr><td>Toshiba 4K Fire TV (2018–2019)</td><td><code>AFTKMST12</code></td><td>25</td><td>unpublished</td><td>?</td><td>🟡 Recommended ‡</td><td>—</td></tr>
<tr><td>Toshiba HD Fire TV (2018–2020)</td><td><code>AFTBAMR311</code></td><td>25</td><td>unpublished</td><td>?</td><td>🟡 Recommended ‡</td><td>—</td></tr>
<tr><td>Insignia HD Fire TV (2018–2020)</td><td><code>AFTEAMR311</code></td><td>25</td><td>unpublished</td><td>?</td><td>🟡 Recommended ‡</td><td>—</td></tr>
<tr><td>Onida HD Fire TV (2019)</td><td><code>AFTLE</code></td><td>25</td><td>unpublished</td><td>?</td><td>🟡 Recommended ‡</td><td>—</td></tr>
<tr><td>Onida HD/FHD Fire TV (2020)</td><td><code>AFTTIFF55</code></td><td>25</td><td>unpublished</td><td>?</td><td>🟡 Recommended ‡</td><td>—</td></tr>
<tr><td>AmazonBasics HD/FHD Fire TV (2020)</td><td><code>AFTBU001</code></td><td>25</td><td>unpublished</td><td>?</td><td>🟡 Recommended ‡</td><td>—</td></tr>
<tr><th colspan="7" align="center">🔹&nbsp; AMAZON FIRE TABLETS <i>— no Fire OS 6 generation existed</i> &nbsp;🔹</th></tr>
<tr><td>Fire 7 (2017, 7th gen)</td><td><code>KFAUWI</code></td><td>22</td><td>Mali-450 MP4</td><td><b>2.0</b></td><td>🔴 <b>Required</b></td><td>—</td></tr>
<tr><td>Fire (2015, 5th gen)</td><td><code>KFFOWI</code></td><td>22</td><td>Mali-450</td><td><b>2.0</b></td><td>🔴 <b>Required</b></td><td>—</td></tr>
<tr><td>Fire HD 8 (2017, 7th gen)</td><td><code>KFDOWI</code></td><td>22</td><td>Mali-T720 MP2</td><td>3.1</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><td>Fire HD 10 (2017, 7th gen)</td><td><code>KFSUWI</code></td><td>22</td><td>PowerVR GX6250</td><td>3.1</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><td>Fire HD 8 (2016, 6th gen)</td><td><code>KFGIWI</code></td><td>22</td><td>Mali-T720 MP2</td><td>3.1</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><td>Fire HD 8 (2015, 5th gen)</td><td><code>KFMEWI</code></td><td>22</td><td>unpublished</td><td>3.0</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><td>Fire HD 10 (2015, 5th gen)</td><td><code>KFTBWI</code></td><td>22</td><td>unpublished</td><td>3.0</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><td>Fire HDX 8.9 (2014, 4th gen)</td><td><code>KFSAWI</code> / <code>KFSAWA</code></td><td>22</td><td>Adreno 420</td><td>3.1</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><td>Fire HD 7 (2014, 4th gen)</td><td><code>KFASWI</code></td><td>22</td><td>PowerVR G6200</td><td>3.0</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><td>Fire HD 6 (2014, 4th gen)</td><td><code>KFARWI</code></td><td>22</td><td>PowerVR G6200</td><td>3.0</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><th colspan="7" align="center">🔹&nbsp; NON-AMAZON <i>— Model is the SoC where the row is a class</i> &nbsp;🔹</th></tr>
<tr><td>MXQ, M8S and the clone-box wave</td><td>Amlogic S805 / S812</td><td>22</td><td>Mali-450 MP2 / MP6</td><td><b>2.0</b></td><td>🔴 <b>Required</b></td><td>—</td></tr>
<tr><td>The 2016–17 TV-box generation</td><td>Amlogic S905 / S905X</td><td>22–25</td><td>Mali-450 MP3</td><td><b>2.0</b></td><td>🔴 <b>Required</b></td><td>—</td></tr>
<tr><td>Budget boxes and HDMI sticks</td><td>Rockchip RK3128 / RK3229</td><td>22–25</td><td>Mali-400 MP2</td><td><b>2.0</b></td><td>🔴 <b>Required</b></td><td>—</td></tr>
<tr><td>Later budget boxes</td><td>Rockchip RK3328</td><td>25</td><td>Mali-450 MP2</td><td><b>2.0</b></td><td>🔴 <b>Required</b></td><td>—</td></tr>
<tr><td>Sub-$100 phones, very high volume</td><td>MediaTek MT6580</td><td>22–23</td><td>Mali-400 MP2</td><td><b>2.0</b></td><td>🔴 <b>Required</b></td><td>—</td></tr>
<tr><td>Galaxy J3 2016 <code>SM-J320H</code> / <code>SM-J320F</code>, entry phones</td><td>Spreadtrum SC7731 / SC8830 / SC9830</td><td>22</td><td>Mali-400 MP2</td><td><b>2.0</b></td><td>🔴 <b>Required</b></td><td>—</td></tr>
<tr><td>White-label tablets and boxes</td><td>Allwinner A33 / A64 / H3</td><td>22–23</td><td>Mali-400 MP2 / Mali-450</td><td><b>2.0</b></td><td>🔴 <b>Required</b></td><td>—</td></tr>
<tr><td>Nexus 5</td><td>—</td><td>23</td><td>Adreno 330</td><td>3.0</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><td>Nexus 7 (2013)</td><td>—</td><td>23</td><td>Adreno 320</td><td>3.0</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><td>Nexus 6</td><td>—</td><td>25</td><td>Adreno 420</td><td>3.1</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><td>Nexus 9</td><td>—</td><td>25</td><td>Tegra K1</td><td>3.1</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><td>Galaxy S5</td><td>—</td><td>23</td><td>Adreno 330</td><td>3.0</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><td>Galaxy Note 4 / Note Edge</td><td>—</td><td>23</td><td>Adreno 420 / Mali-T760</td><td>3.1</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><td>LG G3</td><td>—</td><td>23</td><td>Adreno 330</td><td>3.0</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><td>Moto G 2nd / 3rd gen</td><td>—</td><td>23</td><td>Adreno 305 / 306</td><td>3.0</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><td>Xperia Z3</td><td>—</td><td>23</td><td>Adreno 330</td><td>3.0</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><td>OnePlus One</td><td>—</td><td>23</td><td>Adreno 330</td><td>3.0</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><td>Razer Forge TV</td><td>—</td><td>23</td><td>Adreno 420</td><td>3.1</td><td>🟡 Recommended</td><td>—</td></tr>
<tr><th colspan="7" align="center">🔹&nbsp; OUT OF RANGE <i>— this build is not the answer</i> &nbsp;🔹</th></tr>
<tr><td>Fire TV Stick 3rd gen / Lite, Stick 4K 2nd gen, Stick 4K Max, Cube 2nd/3rd gen, Fire TV 2/4-Series, Omni</td><td>various</td><td>28–30</td><td>various</td><td>3.2</td><td>🟢 Official</td><td>—</td></tr>
<tr><td>Fire tablets, 2018 and later</td><td>various</td><td>28–30</td><td>various</td><td>3.1+</td><td>🟢 Official</td><td>—</td></tr>
<tr><td>Nexus Player</td><td>—</td><td>26</td><td>PowerVR G6430</td><td>3.1</td><td>🟢 Official</td><td>—</td></tr>
<tr><td>Xiaomi Mi Box 3</td><td>—</td><td>26</td><td>Mali-450</td><td><b>2.0</b></td><td>🟢 Official §</td><td>—</td></tr>
<tr><td>Galaxy S4</td><td>—</td><td>21</td><td>Adreno 320 / Mali-T628</td><td>3.0</td><td>⚫ Neither</td><td>—</td></tr>
<tr><td>Kindle Fire HDX 7 / HDX 8.9 / HD 7 (2013)</td><td><code>KFTHWI</code> / <code>KFAPWI</code> / <code>KFSOWI</code></td><td>19</td><td>Adreno 330</td><td>—</td><td>⚫ Neither</td><td>—</td></tr>
<tr><td>Kindle Fire HD 7 / HD 8.9, Kindle Fire (2012)</td><td><code>KFTT</code> / <code>KFJWI</code> / <code>KFOT</code></td><td>15</td><td>PowerVR SGX540</td><td>—</td><td>⚫ Neither</td><td>—</td></tr>
<tr><td>Kindle Fire (2011)</td><td>—</td><td>10</td><td>PowerVR SGX540</td><td>—</td><td>⚫ Neither</td><td>—</td></tr>
<tr><td>Fire TV Stick 4K Select (2025), Stick HD (2026)</td><td><code>AFTCA002</code> / <code>AFTCL001</code></td><td>n/a</td><td>—</td><td>—</td><td>⚫ Neither ¶</td><td>—</td></tr>
</tbody>
</table>

**†** Reports the same `AFTT` model code as the verified device and is the same hardware,
but was not separately tested.

**‡** Amazon has withdrawn the specs for these sets, so their GLES level is unknown. The
verdict is 🟡 `Recommended` at minimum; if the GPU turns out to be Mali-450, as it is on
much TV silicon of that era, it is 🔴 `Required`. Run `device-check.sh` and open an issue.

**§** The instructive row: GLES 2.0 hardware that Oreo carried to API 26, so the official
client installs and Compose renders on it. GLES 2.0 alone was never the barrier.

**¶** Runs **Vega OS**, which is not Android at all — which is why Tailscale lists the
4K Select as unsupported. No Android APK helps there.

> [!NOTE]
> Sibling model numbers are not interchangeable. The US Galaxy J3 (2016) shipped an Exynos
> 3475 with a Mali-T720 (GLES 3.1) instead, and some J3 variants later took an Android 6/7
> update — still inside API 22–25 either way, but check the device, not the marketing name.
> Amlogic **S912** is likewise the exception in its family: Mali-T820, GLES 3.2.

Everything outside the ✅ row is **untested**. Please open an issue with
`scripts/device-check.sh` output if you try one.
