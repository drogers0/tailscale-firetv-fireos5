# VPN recovery after reboot

Patch `0008-restore-legacy-vpn-after-boot.patch` restores a previously enabled VPN on
Android 5.1–6 (API 22–23), where Android's always-on VPN startup is unavailable.

The boot receiver starts restoration only when VPN consent is already granted. The
service reads saved preferences and restores only if `WantRunning` is true. Later
connection or stop commands invalidate pending reads. Service shutdown cancels the
read scope. Android's null-intent service restart uses the same saved-state check.

On Android 7+, the boot receiver does nothing; startup remains controlled by the
system's always-on VPN setting.

## Prerequisites

- Open the app once after installation, complete login, grant VPN permission, and
  enable the connection.
- Open it again after using Android's force-stop command. Android suppresses boot
  delivery to a force-stopped app until it is launched again.
- A working network is required. Boot recovery does not scan for or configure Wi-Fi.

Build the patched release with:

```sh
TS_REF=1.98.8-t1241b225b-gbcbaf1889 MIN_SDK=22 SKIP_TESTS=0 ./scripts/build.sh
```

## Verification

The restore-gate regression tests cover saved connection intent, manual disconnect,
missing VPN consent, and a later command superseding an earlier restore request.

Device checks used SH-01J, Android 5.1.1 / API 22 / ARMv7, build 01.02.06, with both
this patch and the separate network recovery patch installed:

- A reboot restored the tunnel without opening a settings screen or the app.
  Bidirectional peer traffic worked while the screen was off.
- After manual disconnect, another reboot retained `WantRunning=false` and did not
  create a tunnel.

These checks do not establish boot recovery on Fire OS or another physical device.
Initial Wi-Fi discovery varied between reboots. Long-duration sleep and physical
device testing on current Android remain unverified.
