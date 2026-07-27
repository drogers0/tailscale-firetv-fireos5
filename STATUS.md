# Status — WORKING

Last updated 2026-07-26.

Tailscale **1.98.8** (current stable) runs on **Fire OS 5 / Android 5.1 / API 22** with
seven patches, and **routes traffic through an exit node**.

---

## Verified end-to-end

On a Fire TV Stick 2nd gen (`AFTT`, Fire OS 5.2.9.5, Mali-450 / GLES 2.0):

| | |
|---|---|
| Builds at `MIN_SDK=22` | ✅ `gomobile bind -androidapi 22` included |
| Installs on API 22 | ✅ versionCode 468, targetSdk 35 |
| Compose UI on GLES 2.0 | ✅ |
| Login | ✅ persists across restarts |
| Tunnel | ✅ `tun0`, `100.64.0.10` |
| DERP relay | ✅ `derp-16 (mia)`, ~72 ms |
| Online to control plane | ✅ no "offline" marker |
| Health warnings | ✅ clear |
| Peer list | ✅ `Peers=6`, grouped by user |
| **Exit node** | ✅ **`exit-node-host.othernet.ts.net`** |
| **Traffic through exit node** | ✅ **1 MB download → 1,113,884 bytes over `tun0`** |
| Survives reboot | ❌ VPN does not auto-start — see below |

> **Measuring exit-node routing:** public egress IP is useless here — the exit node's owner
> shares the household connection, so stick and laptop report the same IP. Use the byte
> counters instead. Without an exit node, public-internet traffic never traverses `tun0`.
>
> ```sh
> adb shell cat /sys/class/net/tun0/statistics/rx_bytes
> adb shell curl -s -o /dev/null -w '%{size_download}\n' http://speedtest.tele2.net/1MB.zip
> adb shell cat /sys/class/net/tun0/statistics/rx_bytes
> ```

## Reboot behaviour

**The VPN does not come up by itself after a reboot.** The app process is started (by
WorkManager's `RescheduleReceiver`) but no tunnel is established.

This is upstream behaviour, not a patch gap: Tailscale's Android manifest declares **no
`BOOT_COMPLETED` receiver** — the `RECEIVE_BOOT_COMPLETED` permission comes from
WorkManager. Upstream relies on Android's **always-on VPN**, which is API 24+ and
unavailable here (`settings get secure always_on_vpn_app` returns `null` on Fire OS 5).

**Workaround:** open the Tailscale app once after a reboot. Everything else persists —
login, chosen exit node, prefs. Verified: after a cold boot, launching the app restored the
tunnel and exit-node routing (1,116,625 bytes over `tun0`) with no reconfiguration.

## Build

```sh
TS_REF=1.98.8-t1241b225b-gbcbaf1889 MIN_SDK=22 ./scripts/build.sh
```

~12 s incremental, a few minutes cold. Patches apply automatically; the build hard-fails
if any does not.

## The seven patches

| # | Fixes | API |
|---|---|---|
| 0001 | `NotificationChannel`, unguarded in `App.onCreate()` | 26 |
| 0002 | `QuickToggleService : TileService`, 2 call sites | 24 |
| 0003 | `getForegroundService` / `startForegroundService`, 2 sites | 26 |
| 0004 | `Network.bindSocket` → `VpnService.protect(fd)` | 23 |
| 0005 | netmap decode: `decodeFromString`, not `decodeFromStream` | — |
| 0006 | drop `setExpedited` from `IPNReceiver` work requests | 31 |
| 0007 | `coreLibraryDesugaring` for `java.time` | 26 |

Upstream runs at minSdk 26, so guards that became dead code were dropped over time. All of
these are that, **except 0005** — which is not API-related at all.

### 0005 is the interesting one

```
IllegalArgumentException: Bad position (limit 16257): -122
```

`decodeFromStream` reads through a ~16 KB buffer and corrupts a multi-byte UTF-8 sequence
straddling the boundary. Only the netmap notification is large enough to reach it (28 KB
here), and only when a non-ASCII character lands on the seam — in this case a device named
with a curly apostrophe. State and Prefs notifications are small and always decoded fine,
so **peers silently never arrived while everything else worked**. The exception escaped the
Go callback and the entire notification was dropped, with no error anywhere.

Upstream is exposed to this too, given a large enough netmap with non-ASCII at the wrong
offset. It is luck, not API level.

### 0004 — the connectivity fix

`bindSocketToNetwork()` failed two ways on API 22: the `NetworkRequest` callback never
fires (`cachedDefaultNetwork` permanently null), and `Network.bindSocket(FileDescriptor)`
is API 23 regardless — a `NoSuchMethodError`, which the surrounding `catch (Exception)`
would not have caught. Fixed with `VpnService.protect(fd)` (API 14), the platform's own
mechanism for keeping a VPN app's sockets outside its tunnel. Upstream never needs it
because `bindSocket` is strictly better at API 23+.

## Setting an exit node

The UI picker works. To do it from a shell:

```sh
adb shell am broadcast -a com.tailscale.ipn.USE_EXIT_NODE \
  -n com.tailscale.ipn/.IPNReceiver \
  --es exitNode 'exit-node-host.othernet.ts.net' --ez allowLanAccess true
```

The name must match `displayName` (`ComputedName ?: Name`) **exactly** — for a shared node
that is the full FQDN, not the short hostname. A mismatch fails silently apart from a
notification.

Routes only take effect once the tunnel is re-established, so reconnect afterwards:

```sh
adb shell am broadcast -a com.tailscale.ipn.DISCONNECT_VPN -n com.tailscale.ipn/.IPNReceiver
adb shell am broadcast -a com.tailscale.ipn.CONNECT_VPN    -n com.tailscale.ipn/.IPNReceiver
```

Confirm with `ip route show table <vpn table>` — expect ~46 `tun0` routes splitting
`0.0.0.0/0` (`0.0.0.0/5`, `8.0.0.0/7`, `32.0.0.0/3`, `64.0.0.0/2`, …) with the local LAN
carved out when `allowLanAccess=true`. The table number changes between installs; find it
via `ip rule`.

## Signing

Releases are signed with a durable key so published APKs form a coherent upgrade chain.
Gradle's default debug key is generated per-machine, so without this two people building
the same commit produce APKs that cannot upgrade over one another.

```sh
./scripts/build.sh
./scripts/sign-apk.sh          # signs the newest APK in dist/, refreshes the .sha256
```

Signer: `CN=tailscale-firetv-fireos5`, SHA-256 `b6e56d68…53b5`.

The key **lives in the repo, encrypted**: `secrets/tailscale-firetv-release.jks.gpg`
(GPG symmetric, AES-256, SHA-512 KDF, 65M iterations). It travels with the repo and survives
machine loss. See [secrets/README.md](secrets/README.md).

The passphrase is the one thing that cannot live in the repo — otherwise cloning it would be
enough to sign as you. `sign-apk.sh` resolves it in this order:

| | Source |
|---|---|
| 1 | `TS_KEYSTORE_PASSWORD` env var — CI, from GitHub secrets |
| 2 | **macOS Keychain** — service `tailscale-firetv-release`, account `firetv` |
| 3 | `~/.keystores/tailscale-firetv-release.pass` — legacy |
| 4 | interactive prompt |

The keystore itself resolves as: `TS_KEYSTORE_BASE64` (CI) → encrypted file in the repo →
plain local `.jks`. Verified working with **no local keystore and no env vars** — decrypted
from the repo with the Keychain passphrase.

GitHub secrets (`TS_KEYSTORE_BASE64`, `TS_KEYSTORE_PASSWORD`, `TS_KEY_ALIAS`) remain set for
CI. Note they are **write-only** — you cannot read them back — which is exactly why the
encrypted copy in the repo is the real backup.

Store the passphrase on a new machine with:

```sh
security add-generic-password -U -s tailscale-firetv-release -a firetv -w
```

We re-sign the debug-built APK rather than building the `release` variant, because that
variant enables `minifyEnabled` + `shrinkResources`, and ProGuard is a genuine risk to
kotlinx.serialization and the gomobile JNI bindings. Re-signing ships the exact bytes we
tested. The APK therefore stays **debuggable**, which is also what makes `run-as` log
reading possible.

## Reading the Go-side logs

Tailscale's Go logs never reach logcat. The APK is a **debug** build
(`android:debuggable=true`), so:

```sh
adb shell run-as com.tailscale.ipn cat files/ipn.log..log1.txt
```

JSON-per-line logtail records; they rotate fast, so pull promptly. This is the only way to
see netmap, DERP, `wgcfg` and socket-binding activity. Kotlin crashes still go to logcat.

## Gotcha: poison-pill work items

A failed `USE_EXIT_NODE` broadcast (pre-0006) persists a WorkManager job that crashes the
app on **every** start. Clear it without losing the login:

```sh
adb shell run-as com.tailscale.ipn rm -f databases/androidx.work.workdb*
```

`files/profile-data` holds the login and is untouched.

## Device under test

Fire TV Stick 2nd gen — `AFTT` / `tank`, retail **LY73PR**, Fire OS 5.2.9.5, Android 5.1.1
(API 22), armeabi-v7a, Mali-450 (GLES 2.0), 1920x1080 @ 320 dpi, 895 MB RAM.

## Possible follow-ups

Everything needed works. Optional polish:

1. `NetworkChangeCallback` never fires on API 22, so `protect()` pins to nothing. Equivalent
   on a single-uplink device; would matter on multi-uplink.
2. Patch 0005 is arguably worth reporting upstream — the `decodeFromStream` UTF-8 boundary
   bug is not API-22-specific.
3. Launch is slow, 5-7 s to first frame, on this hardware.
