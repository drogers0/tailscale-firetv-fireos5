# CLAUDE.md

## Goal: functional parity with upstream

This repo builds current stable Tailscale Android for devices the official app does not support
(Fire OS 5 / API 22, GLES 2.0). The build must behave as upstream's release does on a
supported device. Every change to upstream behaviour must meet one of these rules:

- **Guard:** an API that does not exist below its level is skipped, and nothing the user sees
  or relies on is lost. Example: a Quick Settings tile has nowhere to appear below API 24.
- **Substitute:** a different mechanism is allowed only when upstream's mechanism is not
  available on the target devices, and the substitute delivers the same function.
  Example: 0008's `BOOT_COMPLETED` receiver stands in for Android's always-on VPN, which
  does not exist below API 24.
- **Security fix:** a change that only removes exposure this build creates. It must match what
  upstream's release build does. Example: 0012.

Anything else is a parity gap, even when it is convenient for building or testing.

- Do not add features, remove features, or change defaults.
- Every patch header comment states which rule it meets and why it is needed.
- When a substitute covers less than upstream's mechanism does, document what is missing in
  `docs/STATUS.md`. If the gap can be closed, close it.
- Upstream bugs that also occur on supported devices are not parity debt. Document them, but
  do not patch them.
