# Status — where this stands, and how to resume

Last updated 2026-07-26. Work is **paused mid-investigation**, not abandoned.

Read this first, then [FINDINGS.md](FINDINGS.md) for the evidence behind each claim.

---

## One-line summary

Tailscale **1.98.8** (current stable) runs on Fire OS 5 / API 22 with **four patches**.
It installs, renders, logs in, brings up a tunnel, connects to DERP, and shows **online**
on the tailnet with no health warnings. One bug remains: **the peer list renders empty**,
so the exit-node picker has nothing to choose from.

### ✅ Socket binding — FIXED (patch 0004)

`bindSocketToNetwork()` failed on API 22 for two reasons: the `NetworkRequest` callback
never fires (so `cachedDefaultNetwork` was permanently null), and
`Network.bindSocket(FileDescriptor)` is API 23 anyway. Fixed by falling back to
`VpnService.protect(fd)` (API 14), the platform's own mechanism for keeping a VPN app's
sockets outside its tunnel. Confirmed on hardware:

```
bindSocketToActiveNetwork: API 22 < 23; VpnService.protect(fd=78) -> true
derphttp.Client.Recv: connecting to derp-16 (mia)
derp-16 connected; connGen=1     derp=16 derpdist=16v4:72ms
health(warnable=no-derp-connection): ok      health: Health updated: null
```

This resolved three of the four symptoms: the relay warning, the device showing offline,
and the health icon.

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
| **DERP relay** | ✅ derp-16 (mia) connected, ~72 ms |
| **Online on the tailnet** | ✅ no "offline" marker, health warnings clear |
| **Peer list / exit-node choices** | ❌ **open — renders empty** |

## The open blocker: peer list renders empty

**Corrected assumption.** The empty peer list was previously assumed to be downstream of
the socket-binding fault. It is not — it survives with DERP connected and the node online,
so it is an independent bug.

The Go layer has the peers. Proven by the Go-side log, *after* the fix:

```
wgcfg: skipped unselected exit nodes from 1 nodes: exit-node-host (nXXXXXXXXXXXCNTRL)
wgcfg: skipped expired peers from 1 nodes: desktop-a (nYYYYYYYYYYYCNTRL)
```

("skipped unselected" is normal — an exit node you have not chosen.) But the UI shows no
devices and the exit-node picker lists none.

### Where to look

`PeerCategorizer.regenerateGroupedPeers()` in `ui/util/PeerHelper.kt`:

```kotlin
fun regenerateGroupedPeers(netmap: Netmap.NetworkMap) {
    val peers: List<Tailcfg.Node> = netmap.Peers ?: return   // ← silent bail
```

If the Kotlin-side `netmap.Peers` is null, every peer-derived list is empty with **no
exception** — which matches: logcat shows no `kotlinx.serialization` errors at all.

Prime suspect: the Go→Kotlin netmap JSON bridge. `Notifier` deserialises the netmap into
`Netmap.NetworkMap`; if `Peers` fails to populate (field-name mismatch, or the notify mask
not requesting peers), everything downstream is empty and silent.

Note the ordering seen in logs — `ExitNodePickerViewModel: Created` at `00:14:45`, netmap
arriving `00:14:49` — so also worth ruling out a flow-collection race where the UI never
recomposes on a late netmap.

### Next steps

1. Add a temporary `TSLog.d` in `regenerateGroupedPeers` logging `netmap.Peers?.size` and
   whether `netmap` itself is null. One rebuild answers whether it is a null-Peers problem
   or a never-called problem.
2. If `Peers` is null: dump the raw notify JSON at the `Notifier` boundary and compare
   against `Netmap.NetworkMap`'s `@Serializable` fields.
3. If `regenerateGroupedPeers` is never called: the netmap flow is not reaching the UI —
   look at `Notifier.netmap` collection and the notify mask.

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
| `0004-protect-socket-fallback-api22` | `Network.bindSocket` is API 23 → `VpnService.protect(fd)` | 1 + service instance tracking |

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

1. **Instrument `regenerateGroupedPeers`** — see "The open blocker" above. One rebuild
   distinguishes null-`Peers` from never-called.
2. Depending on the answer, chase the notify JSON bridge or the flow collection.
3. Optional: patch 0005 for the `USE_EXIT_NODE` worker crash, if bypassing the UI is still
   wanted once the picker works.
4. Optional: fix `NetworkChangeCallback` so a real network gets cached — `protect()` works
   but pins to nothing, which is weaker than `bindSocket` on a multi-uplink device.
5. `TS_DEBUG_TLS_DIAL` remains untried. The system CA store cannot validate DERP's chain
   (`tls=20`; chain now ends at ISRG Root X2 / Root YE), but Tailscale bakes X1+X2 in and
   the fallback is compiled in, so this is believed **not** to be the cause. Unverified at
   runtime — worth ruling out if binding turns out to be a red herring.

## Gotcha: poison-pill work items

The `USE_EXIT_NODE` broadcast persists a WorkManager job that crashes the app on **every**
start (`CoroutineWorker.getForegroundInfo: Not implemented`). Clear it without losing the
login:

```sh
adb shell run-as com.tailscale.ipn rm -f databases/androidx.work.workdb*
```

`files/profile-data` holds the Tailscale login and is untouched by this.

## Fallback that needs no code

Run Tailscale **upstream of the stick** — a travel router or home router as the exit-node
client, with the Fire Stick as an ordinary Wi-Fi client. Gets exit-node routing on the TV
with a maintained client and no patched fork.

## Device under test

Fire TV Stick 2nd gen — `AFTT` / `tank`, retail **LY73PR**, Fire OS 5.2.9.5, Android 5.1.1
(API 22), armeabi-v7a, Mali-450 (GLES 2.0), 1920x1080 @ 320dpi, 895 MB RAM.
Reached at `192.168.1.50:5555` over adb.
