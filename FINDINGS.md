# Findings

Research behind this repo, with the evidence for each claim. Recorded so the conclusions
can be re-checked rather than taken on faith — and so the dead ends don't get re-explored.

Investigated 2026-07-26 against a Fire TV Stick 2nd gen (`AFTT`), Fire OS 5.2.9.5.

---

## 1. The device

Read directly off the hardware over adb:

```
ro.build.version.release  5.1.1
ro.build.version.sdk      22
ro.product.model          AFTT          (codename "tank", retail LY73PR)
ro.build.version.name     Fire OS 5.2.9.5 (688806320)
ro.product.cpu.abilist    armeabi-v7a,armeabi
ro.opengles.version       131072        = 0x20000 = OpenGL ES 2.0
```

```
SurfaceFlinger GLES: ARM, Mali-450 MP, OpenGL ES 2.0
wm density: 320    wm size: 1920x1080    MemTotal: 895216 kB
```

Two hard constraints: **API 22** and **OpenGL ES 2.0**. No arm64, no x86.

## 2. Old Tailscale clients still work with the control plane

Worth establishing first, because if the control plane rejected old clients none of the
rest would matter. Tailscale publishes no minimum-client-version policy that I could find,
so this was settled empirically.

**Tailscale v1.2.2 (Nov 2020) — 5.7 years old — installed and reached the control plane:**

```
control: RegisterReq: got response; nodeKeyExpired=false, machineAuthorized=false; authURL=true
control: AuthURL is https://login.tailscale.com/a/<redacted>
Switching ipn state NoState -> NeedsLogin (WantRunning=true)
control: direct.WaitLoginURL
```

**Conclusion: client age is not the blocker.** Registration, auth URL issuance, and state
transition all succeeded against the current control plane.

## 3. The real blocker is the GPU, not the API level

The same run then died:

```
fatal error: no support for OpenGL ES 3 nor EXT_sRGB
```

Tailscale's UI up to early 2024 was built on [Gio](https://gioui.org), which needs OpenGL
ES 3, or GLES 2 plus `EXT_sRGB`. The Mali-450 offers neither. The process reaches
`NeedsLogin` and exits — and login cannot be completed without a UI.

This is why "just use an older APK" fails, and why it's easy to misdiagnose: the app
installs fine, the network layer works, and the logs look healthy right up until the first
frame.

## 4. The minSdk timeline is non-monotonic

Traced through every commit touching `android/build.gradle` in `tailscale/tailscale-android`:

| Date | minSdk | Commit |
|---|---|---|
| 2020-04-17 | 23 | `5109987e18` initial commit |
| 2020-08-11 | 22 | `39cb01da42` |
| 2020-08-11 | 23 | `f25b5bbcba` |
| **2020-08-13** | **22** | `b6d6f57261` |
| **2024-03-13** | **26** | `bf0e56469f` "android: Add settings screen (#196)" |

**Tailscale supported API 22 continuously for 3.5 years**, from 2020-08-13 to 2024-03-13.

> ⚠️ It went 23 → 22 → 23 → 22 → 26. A binary search over this history returns a **wrong
> answer** — it reports 23 as the floor while the shipped v1.2.2 APK is demonstrably 22.
> Scan linearly.

## 5. The one-commit window

The commit immediately before the minSdk bump:

```
3926cf4b5611d444dae7efc50499f477371e7327
2024-03-13T12:53:47Z
android: add main screen device details and basic nav (#191)
```

At that commit the UI is **already Jetpack Compose**, verified in
`android/src/main/java/com/tailscale/ipn/MainActivity.kt`:

```kotlin
import androidx.activity.compose.setContent
import androidx.navigation.compose.NavHost
...
setContent { AppTheme { ... } }
```

Compose renders through Android's standard hardware canvas — **no GLES 3 requirement.**

The module carries the full VPN plumbing — `IPNService.java`, `App.java`,
`StartVPNWorker`, `QuickToggleService`, `MDMSettings.kt`.

> ### ⚠️ Corrected 2026-07-26 — this commit's UI is a set of stubs
>
> An earlier revision of this document claimed the screens were complete because
> `SettingsView.kt` and `ExitNodePicker.kt` exist at this commit. **That inference was
> wrong.** The files exist; the screens do not. Confirmed on device (RC1) and in source:
>
> ```kotlin
> @Composable
> fun Settings(viewModel: SettingsViewModel) {
>     Column { Text(text = "Future Home of Settings") }
> }
> ```
>
> On hardware, RC1 renders correctly and then does nothing: Connect is inert and Settings
> shows "Future Home of Settings". `MainViewModel.toggleVpn()` and `IpnManager.startVPN()`
> are wired to the buttons, but the surrounding flow (VPN consent, LocalAPI) was still
> under construction.
>
> The next commit being titled *"Add settings screen"* was the clue, and it was explained
> away rather than checked. **Presence of a file is not evidence of a working screen.**
>
> What this commit *does* prove is the graphics claim — see §9.

The manifest declares `LEANBACK_LAUNCHER`, so it is TV-aware.

Upstream Go module at this commit: `tailscale.com v1.61.0-pre.0.20240311120500-7429e8912acb`.

### Caveats, stated plainly

- `go.mod` still lists `gioui.org`, and `gogio` is still the *packaging* tool for the Go
  archive. The launcher activity is `MainActivity` (Compose), not `GioActivity` — but if
  anything still instantiates a Gio GL surface, the crash could recur. Static analysis
  can't fully exclude this.
- The `android/` module was an **unshipped, in-flight rewrite**. Tailscale raised minSdk to
  26 one commit later, so they never validated it at API 22 — possibly *because* it didn't
  work there.

Only building and running it settles both.

## 6. Why the two-row compatibility table is misleading

The widely repeated framing is:

| Version | Runs on 5.1? | Gio bug |
|---|---|---|
| Older APK | Yes | Likely |
| Current app | No | Fixed |

The missing row is that the Compose rewrite landed **weeks before** the Android-8 floor.
Tailscale announced the Gio removal in April 2024, but the code merged 2024-03-13 while
minSdk was still 22.

Crucially, that window was never released:

- `android_legacy/` (the Gio module, minSdk 22) remained the **shipping** app until it was
  deleted on **2024-04-17** — commit `81acaef5b7` *"android: rip android_legacy (#335)"*.
- Official **1.62.0** shipped **2024-04-12** — five days *before* that deletion — so it is
  still Gio-based despite being listed as minAPI 22.
- By tag **1.64.0**, `android/build.gradle` is already `minSdkVersion 26`.

**No official release has ever paired the Compose UI with minSdk 22.**

## 7. Everything ruled out

### Prebuilt APKs

| Source | Finding |
|---|---|
| `pkgs.tailscale.com/stable/` | Only `tailscale-android-universal-1.98.8.apk`, **Android 8+**. No archive — probed 1.40/1.44/1.50/1.54/1.56/1.58/1.60/1.62: all HTTP 404 |
| GitHub releases | 28 releases, 22 with APK assets: **v1.2.2** (2020, Gio) then **1.76.2+** (minSdk 26). Nothing between |
| Tags v1.4 – v1.10 | exist, but carry no APK assets |
| F-Droid | packaging began **Dec 2025**; 1.92.3 / 1.96.2 / 1.96.4, all **Android 8+** |
| IzzyOnDroid | `com.tailscale.ipn` not present (HTTP 404) |
| APKMirror "Android 5.1+" | newest is **1.62.0** (2024-04-12) — pre-legacy-rip, therefore **Gio**, therefore crashes |

### Prior art

- Tailscale officially supports **"most Fire TV devices released after 2018"**. `AFTT` is
  2016 — outside the support envelope.
- GitHub repo search surfaced only plain mirrors (`sffej`, `edgesky`, `liuyuyu2020`,
  `iisimpler`) — no fork targeting old Fire TV or lowering minSdk.
- No community build recipe found.

> **Gap in this search:** xdaforums.com returned HTTP 403, so the main Fire TV + Tailscale
> thread could not be read, and forum content indexes poorly. This is *no evidence found*,
> not proof of absence.

## 9. On-device result: the GPU problem is solved

RC1 (built from `3926cf4b56`) was installed on the AFTT and launched.

```
I/ActivityManager: Displayed com.tailscale.ipn/.MainActivity: +4s662ms
performance:FirstFramesTotal ... Counter=1
```

A screenshot confirms a fully drawn Compose UI — "Please Login" header, settings gear, a
*Not Connected / Connect to your tailnet* card. Correct colors, fonts and 1920x1080 layout.

- **No** `no support for OpenGL ES 3 nor EXT_sRGB`
- **No** `FATAL EXCEPTION`, no `glGetError`
- Only `libgio.so` mentions are benign linker warnings (`unused DT entry`)
- Launch is slow: 4.7 s to first frame, 5.2 s total, 16 dropped frames

**Compose renders on a Mali-450 / OpenGL ES 2.0 GPU.** The blocker that defeats every
downloadable option is real, and it is beaten. What RC1 lacks is a finished app around it.

## 10. The API floor is enforced in two places

Correcting a second wrong assumption: patching `minSdkVersion` in `android/build.gradle` is
**not sufficient** on 1.64.0+. The native library has its own independent gate:

```make
gomobile bind -target android -androidapi 26 \
    -o android/libs/libtailscale.aar ./libtailscale
```

Override only the Gradle value and you get an APK that installs and then dies in native
code. `scripts/build.sh` patches both.

Also note the native recipe changed: `gogio` built the legacy Gio app, while the Compose
app is built by `gomobile bind` against `./libtailscale`. By 1.78.0 `gogio` is gone.

### Why overriding the floor is plausible

The bump commit `bf0e56469f` touched 19 files, and its **entire** `build.gradle` change was:

```diff
-        minSdkVersion 22
+        minSdkVersion 26
```

No dependency was added or upgraded alongside it. The floor was a judgment call, not a
forced consequence — so restoring 22 on a later, finished release is worth testing. The
risk moves from compile-time to runtime: `NoSuchMethodError` / `VerifyError` if the code
calls an API newer than 22.

### Version selection

| Tag | Settings screen | Native build | Flavors | play-services |
|---|---|---|---|---|
| `3926cf4b56` | **stub** | gogio | fdroid/play | 0 |
| 1.64.0 | real | gomobile | none | 0 |
| 1.68.0 | real | gomobile | none | 0 |
| 1.76.2 | real | gomobile | none | 0 |
| 1.78.0 | real | gomobile | none | 0 |

`play-services` is 0 everywhere — Tailscale dropped Play Services, which is why the
fdroid/play split disappeared. Good news for Fire OS, which has no Play Services.

**1.64.0 is the chosen target**: earliest release with a complete UI, therefore the least
accumulated reliance on API 26+.

## 11. Current stable (1.98.8) is viable to build — guard rot is only 3 patches

Testing the "patch new code rather than freeze on old code" decision empirically:

| | 1.64.0 | 1.98.8 |
|---|---|---|
| Patches needed to launch | 1 | 3 |
| `gomobile bind -androidapi 22` | works | works |
| Manifest merger at minSdk 22 | clean | clean |
| Go core age | Apr 2024 | current |

The API-26 floor is a **declaration**, not a dependency: no library rejected minSdk 22 and
the native layer cross-compiles for API 22 without complaint. Upstream's real debt is a
handful of API guards that rotted once they became dead code at minSdk 26.

Crashes found, in the order they surfaced (each hidden behind the previous):

1. `NoClassDefFoundError: NotificationChannel` — API 26, unguarded in `App.onCreate()`
2. `SIGABRT`, Go panic in `version.init.0()` — **build-script bug**, see below
3. `NoClassDefFoundError: QuickToggleService` — `TileService`, API 24, 2 call sites
4. `UninitializedPropertyAccessException` — regression from patch 1 placing the guard
   above a `lateinit` assignment
5. `NoSuchMethodError: getForegroundService` — API 26, on the Connect path

Note 5: `startForegroundForLogin()` wraps its call in `catch (e: Exception)`, which would
**not** have caught it — `NoSuchMethodError` is an `Error`.

### The version-stamp trap

`version-ldflags.sh` does a relative `source tailscale.version`. Invoking it by absolute
path from elsewhere silently fails; combined with `|| true` this produced an **unstamped
AAR** that built and installed cleanly, then aborted at startup:

```
//go:build tailscale_go && android
// panic if the builder is screwed up and we fail to stamp a valid version string.
```

The guard is deliberate and it worked exactly as intended. `build.sh` now generates
`tailscale.version` before the native build, runs the script with the correct CWD, and
hard-fails if no `longStamp` is produced.

## 12. The real blocker: socket binding on API 22

Not a version guard, and the reason this is paused:

```
[unexpected] IPNService.bindSocketToNetwork(53) returned false
App: bindSocketToActiveNetwork: no cached default network; noop
```

Tailscale binds its own sockets to the underlying network so its traffic escapes the
tunnel. On Android 5.1 no default network is ever cached, so those sockets go unbound.
One fault, four symptoms: the DERP "relay server unavailable" warning, the device showing
**offline** to the control plane, an empty peer list, and an empty exit-node picker.

The exit node was present in the netmap the whole time:

```
wgcfg: skipped unselected exit nodes from 1 nodes: exit-node-host (nXXXXXXXXXXXCNTRL)
```

Likely cause: `registerDefaultNetworkCallback()` is API 24. See [STATUS.md](STATUS.md).

### Corrections recorded here deliberately

- **"Shared devices cannot be used as exit nodes"** — wrong. A search summary said so; the
  user's Mac lists `exit-node-host.othernet.ts.net` (owned by another user, on another
  tailnet) as a usable exit node, `ExitNodeOption: True`, `AllowedIPs` including
  `0.0.0.0/0` and `::/0`. Direct observation beat the secondary source.
- **The stale system CA store** — a real finding (`tls=20`; DERP now chains to ISRG Root
  X2 / Root YE, which a 2015 trust store lacks) but **not** the cause. Tailscale bakes
  X1+X2 in via `net/bakedroots`, enabled unless built `ts_omit_bakedroots`. Our tags are
  only `tailscale_go`, so the fallback is compiled in.
- **MDM settings showing "not set"** — normal. `MDMSetting` carries `(value, wasExplicitlySet)`;
  unset means "use default". Values arrive via `RestrictionsManager.applicationRestrictions`,
  always empty on a non-enrolled device.

## 8. Verification method

APK metadata was read by parsing the binary `AndroidManifest.xml`, never inferred from
version numbers or filenames. Every load-bearing claim was cross-checked with two
independent parsers (`pyaxmlparser` and `androguard`) plus the `build.gradle` at the
matching tag.

That mattered: v1.2.2's `build.gradle` at its own tag says `minSdkVersion 22`, while a
naive bisect of the file's history reports 23.

`scripts/verify-apk.py` implements the same check and gates the build.
