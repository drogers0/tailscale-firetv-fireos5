# Status — where this stands, and how to resume

Last updated 2026-07-26. Work is **paused mid-investigation**, not abandoned.

Read this first, then [FINDINGS.md](FINDINGS.md) for the evidence behind each claim.

---

## One-line summary

Tailscale **1.98.8** (current stable) builds and runs on Fire OS 5 / API 22 with three
patches — it installs, renders, logs in, and brings up a tunnel — but it **cannot stay
reachable on the tailnet** because `IPNService.bindSocketToNetwork()` fails on Android 5.1.
That is the open blocker.

## What works

| | |
|---|---|
| Build at `MIN_SDK=22` | ✅ `TS_REF=1.98.8-t1241b225b-gbcbaf1889 MIN_SDK=22 ./scripts/build.sh` |
| `gomobile bind -androidapi 22` | ✅ Go/native layer compiles clean on current code |
| Gradle `assembleDebug` at minSdk 22 | ✅ no manifest-merger rejection |
| Installs on API 22 | ✅ versionCode 468, targetSdk 35 |
| Compose UI renders on GLES 2.0 | ✅ the original blocker, solved |
| Login | ✅ completes, profile persists |
| Tunnel comes up | ✅ `tun0`, `100.64.0.10`, `fd7a:115c:a1e0::d636:597b` |
| Settings / exit-node screens | ✅ render; prefs writes succeed |

## The open blocker

```
[unexpected] IPNService.bindSocketToNetwork(53) returned false
App: bindSocketToActiveNetwork: no cached default network; noop
```

Tailscale binds its own sockets to the underlying network so its traffic escapes the
tunnel. On API 22 this fails repeatedly — no default network is ever cached, so outbound
sockets go unbound.

**Every remaining symptom is downstream of this single fault:**

| Symptom | Why |
|---|---|
| Health warning "could not connect to the 'Miami' relay server" | DERP socket cannot bind |
| Control plane shows the device **offline, last seen Nm ago** | connection cannot be held |
| Device list empty in the UI | netmap never fully arrives |
| Exit node absent from the picker | no peers ⇒ nothing to list |

The exit node was never missing. `exit-node-host` **is** in the netmap — proven by the
Go-side log:

```
wgcfg: skipped unselected exit nodes from 1 nodes: exit-node-host (nXXXXXXXXXXXCNTRL)
```

("skipped unselected" is normal: an exit node you have not chosen.)

This is **not** a missing version guard. `ConnectivityManager` network-binding behaves
differently on API 22, in the code path that keeps the client reachable. Fixing it means
reworking network binding for an API level upstream dropped in 2024.

## Reading the Go-side logs — the key technique

Tailscale's Go logs never reach logcat. Because we build a **debug** APK
(`android:debuggable=true`), `run-as` reaches the app's private data:

```sh
adb shell run-as com.tailscale.ipn ls -la files
adb shell run-as com.tailscale.ipn cat files/ipn.log..log1.txt
```

`ipn.log..log{1,2}.txt` are JSON-per-line logtail records and rotate quickly — pull them
promptly after reproducing. This is the only way to see netmap, DERP, wgcfg and
`bindSocketToNetwork` activity. Kotlin-side crashes still go to logcat.

## Patches (all in `patches/1.98.8/`)

Applied automatically by `build.sh`; it hard-fails if one does not apply.

| Patch | Fixes | Call sites |
|---|---|---|
| `0001-guard-NotificationChannel-api26` | `NotificationChannel` is API 26 | 1 |
| `0002-guard-QuickToggleService-api24` | `QuickToggleService : TileService` is API 24 | 2 |
| `0003-guard-foreground-service-api26` | `getForegroundService` / `startForegroundService` | 2 |

`0001` must keep `notificationManager = NotificationManagerCompat.from(this)` **outside**
the guard — it is a `lateinit` that `notifyStatus()` needs, and guarding it too yields
`UninitializedPropertyAccessException`.

## Known-broken paths (documented, not fixed)

**`USE_EXIT_NODE` broadcast.** The receiver is exported and looked like a way to set an
exit node without the UI:

```sh
adb shell am broadcast -a com.tailscale.ipn.USE_EXIT_NODE \
  -n com.tailscale.ipn/.IPNReceiver --es exitNode 'exit-node-host' --ez allowLanAccess true
```

It crashes on API 22, independently of everything above:

```
java.lang.IllegalStateException: Not implemented
    at androidx.work.CoroutineWorker.getForegroundInfo$suspendImpl(CoroutineWorker.kt:100)
```

`UseExitNodeWorker` is enqueued as **expedited** work. Below API 31 WorkManager runs
expedited jobs as a foreground service and calls `getForegroundInfo()`, which the worker
does not override. A fourth patch (drop `setExpedited`, or override `getForegroundInfo`)
would fix the crash — but the worker would still fail, because it needs peers.

## If resuming — next steps in order

1. **Instrument `bindSocketToActiveNetwork`.** Find why no default network is cached on
   API 22. `App.kt` / `IPNService.kt`; look at the `ConnectivityManager` callback that
   populates it — `NetworkCallback` registration differs pre-API 23
   (`registerDefaultNetworkCallback` is API 24).
2. If a default network can be cached, re-test: DERP should connect, the device should
   go online, peers should populate, and the exit node should appear — all four together.
3. Only then revisit the `USE_EXIT_NODE` worker crash (patch 4), if the UI still needs
   bypassing.
4. `TS_DEBUG_TLS_DIAL` remains untried. The system CA store cannot validate DERP's chain
   (`tls=20`; chain now ends at ISRG Root X2 / Root YE), but Tailscale bakes X1+X2 in and
   the fallback is compiled in, so this is believed **not** to be the cause. Unverified at
   runtime — worth ruling out if binding turns out to be a red herring.

## Fallback that needs no code

Run Tailscale **upstream of the stick** — a travel router or home router as the exit-node
client, with the Fire Stick as an ordinary Wi-Fi client. Gets exit-node routing on the TV
with a maintained client and no patched fork.

## Device under test

Fire TV Stick 2nd gen — `AFTT` / `tank`, retail **LY73PR**, Fire OS 5.2.9.5, Android 5.1.1
(API 22), armeabi-v7a, Mali-450 (GLES 2.0), 1920x1080 @ 320dpi, 895 MB RAM.
Reached at `192.168.1.50:5555` over adb.
