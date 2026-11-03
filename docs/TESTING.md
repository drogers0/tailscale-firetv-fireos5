# Testing

Most regressions in the patch series can be caught without a Fire TV. Tiers 0-2 run the
same commands locally and in CI; tier 3 runs locally only. Only the release checklist at the
end needs hardware.

## Tiers

| Tier | What it catches | Runs | Command |
|---|---|---|---|
| 0 | a patch that no longer applies, shellcheck warnings, `verify-apk` regressions, stale toolchain pins, a stream JSON decode left in the patched tree | every PR, pushes to `main`, weekly upstream drift | `make check` |
| 1 | build breaks, `NewApi` calls above API 22 (Android Lint), upstream unit tests | every PR, pushes to `main`, weekly upstream drift | `LINT=1 SKIP_TESTS=0 make build` |
| 2 | API 22 runtime failures of each patch on an emulator, with no tailnet | PRs to `main`, pushes to `main` | `make build-emu emu-test` |
| 3 | the same emulator logged in to a real tailnet: tunnel, peers, reboots, network changes | by hand, locally | `make build-emu emu-test-net` |

A PR that changes only Markdown files or `docs/` skips tiers 0-2.

Tiers 2 and 3 boot an API 22 `google_apis` emulator (x86_64 under KVM in CI, arm64-v8a on Apple
Silicon) with its own AVD (`tsfire-api22`) on port 5584, so other emulators are never touched.
One script, `scripts/emu-test.sh`, runs both. It stops at the first failure
and keeps its logs in `.build/emu-test/`.

## What each emulator check covers

| Patch | Tier | Check |
|---|---|---|
| 0007 | 2 | desugared `j$.time` classes are in the dex |
| 0011 | 2 | `CONNECT_VPN` before any launch (logged out, no consent) runs `StartVPNWorker` as expedited work in WorkManager's foreground service and posts the "open Tailscale" notification |
| 0002, 0010 | 2 | launch with no missing-API error; a default network is picked at startup |
| 0009 | 2 | denying VPN consent shows "VPN permission needed", with no crash |
| 0010 | 2 | mobile data off and on moves the default network |
| 0001, 0003 | 2 | `IPNService` runs in the foreground |
| 0008 | 2 | a reboot while logged out: `BootReceiver` stays disconnected, no tunnel |
| (login) | 3 | an auth key logs in; state `Running`; a `tun` interface has a tailnet address |
| 0004 | 3 | sockets are protected (`VpnService.protect(fd=…) -> true`, never `false`); the host pings the emulator and the emulator pings the host |
| 0005 | 3 | the first `PeersChanged` update, which carries every peer, decodes (the debug build logs it), and the emulator's own address is in its peer list |
| 0007 | 3 | a node's details show a formatted key expiry (`java.time` at runtime) |
| 0010 | 3 | mobile data off and on while connected: a new default network, the tunnel still works |
| 0013 | 3 | across that network change the app never sets the VPN's underlying network (the listener half; the device check covers `newBuilder()`) |
| 0008 | 3 | a reboot while connected brings the tunnel back without opening the app; a disconnect followed by a reboot stays down |

Every wait also fails fast on a crash, a native fatal signal, a failed worker, a dropped IPN
notification or a `NoSuchMethodError` / `NoClassDefFoundError` / `VerifyError` in the app's log.
Every adb call is bounded (30 s; `adb install` 300 s), so a hung `adb shell` cannot outlast a
wait's deadline.

Known gaps:
- **0007** at tier 2 is static, because its `java.time` calls need a netmap. Tier 3 runs them by
  opening the details of a node whose key expires; tagged nodes, like the emulator, never expire.
- **0009** relies on a fresh install having no VPN consent, rather than revoking it.
- **0005 at tier 3.** The first `PeersChanged` update carries every peer (13 on the tailnet
  used so far), which may stay under 16 KB, and tier 3 then proves only that decoding works.
  The build-time guard against stream decodes covers the call sites; the release checklist
  covers a large payload on hardware.
- **0013 at tier 3.** Only the listener half is visible. `newBuilder()`'s `null` logs nothing,
  so it is checked on hardware.
- **NewApi lint is blind inside `@RequiresApi(TIRAMISU)` functions** (upstream's
  `MainActivity.onCreate` and `SearchView`): lint treats their bodies as running at API 33.
  `onCreate` is called only by the system, so none of its body (all of `setContent`) is linted.
  - Audit at 1.104.5: the only new `onCreate` code is the deep-link wiring, which is linted
    where it is defined. `SearchView`'s API-33 `OnBackInvokedCallback` is reachable only behind
    `MainView.kt`'s `SDK_INT >= TIRAMISU` gate.
  - Tier 2 launches `MainActivity` and is the backstop. Re-check both on every rebase.

## Tier 3

- **The host must be on the tailnet** (`tailscale ip -4`). On macOS, set `TAILSCALE` to the
  app's CLI if `tailscale` is not on `PATH`. The checks ping the emulator from the host.
- **Some node with an expiring key must be visible:** this machine (the default for your own
  devices), or a peer. Otherwise the run stops before boot and says so.
- **macOS:** firewall stealth mode drops ICMP, which fails the emulator-to-host ping.
- **Policy:** `"tagOwners": {"tag:fireos-ci": ["autogroup:admin"]}`. Under the default allow-all
  grant nothing else is needed. With a stricter policy, let `tag:fireos-ci` and the host reach
  each other.
- **Key:** an auth key that is reusable, ephemeral and tagged `tag:fireos-ci`.
- **`.env`:** put `TS_AUTHKEY=<auth key>` in `.env` at the repo root and `chmod 600 .env`. It
  is gitignored, only `make emu-test-net` reads it, and an exported `TS_AUTHKEY` wins.
  `TAILSCALE=<path>` can go there too. Never pass the key as `make emu-test-net TS_AUTHKEY=…`:
  make's argv and `MAKEFLAGS` would carry it into every recipe.

```sh
make build-emu emu-test-net
```

The key reaches the emulator as the app's `AuthKey` managed setting, written as root (the
`google_apis` images are `userdebug`), and is deleted once the emulator is logged in. It never
appears on a command line, on screen or in a UI dump. Saved logs are scrubbed of it at exit.

**What it leaves behind:** the ephemeral node, which Tailscale removes within an hour. The AVD
is deleted at exit.

**Where the key goes.** The app's managed-settings code logs the key's value into the Tailscale
client's own logs, which are uploaded to Tailscale, the key's issuer. This is true of any device
given an auth key through MDM. Use a short-expiry key if that matters to you.

## Before a release (hardware only)

On a Fire TV Stick (Fire OS 5):

- [ ] `scripts/device-check.sh` reports API 22 and GLES 2.0.
- [ ] The release APK installs (uninstall first if the signer differs), and the armeabi-v7a
      native library loads: no `UnsatisfiedLinkError`, no `SIGABRT` at start.
- [ ] The UI renders and navigates on Mali-450 / GLES 2.0 with the remote's D-pad, and `logcat`
      has no `glerror`. The app appears in the Amazon launcher.
- [ ] No Google Play services prompts or errors in `logcat` at start-up and login.
- [ ] Log in; the tunnel is up; peers are listed; the stick is reachable from another device.
      The tunnel is the `tunN` that `adb shell netcfg` lists as `UP` with a `100.x` address;
      it can be `tun1` after a reconnect.
- [ ] The tunnel stays up for at least 30 minutes.
- [ ] Exit-node traffic shows on the tunnel's counters (see the tip in
      [STATUS.md](STATUS.md#verified-end-to-end)).
- [ ] A reboot while connected brings the tunnel back (0008) on Fire OS, and other apps still
      see a network: Settings › Network or a streaming app shows connected (0013).
- [ ] A disconnect followed by a reboot stays down.
- [ ] `logcat` has no `failed to process IPN notification` and no `Bad position` (0005 on a
      real tailnet's peer list).

Everything else is covered by tiers 0-3.
