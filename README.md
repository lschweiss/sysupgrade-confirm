# sysupgrade-confirm

**Confirmed sysupgrade for dual-firmware OpenWrt devices** — arm before you
flash, confirm after it boots, or the device automatically flips back to the
previous firmware.

> Status: **pre-release (0.1.x)** — piloting on Linksys MX5300/MX8500.
> Not yet submitted to openwrt/packages; the interface may still change.

## The problem

OpenWrt's recurring upgrade failure mode is not a bad kernel — it's firmware
that **boots cleanly with a broken network** (config migration surprise,
package regression), leaving the device unreachable. Dual-firmware devices
have a bootloader boot-counter failback, but any boot that reaches userspace
resets the counter: the bootloader considers a dead-network boot a *success*.

`safe-upgrade` (LibreMesh) has the right confirm-or-revert semantics but is
LibreRouter-specific; `luci-app-advanced-reboot` is manual partition
switching; owut/ASU deliver images but do no post-boot validation. This
package fills the gap generically.

## How it works — two independent layers

1. **Layer 1 (bootloader, untouched):** kernel panic/hang → userspace never
   runs → the stock boot-counter flips partitions. We never suppress or race
   the stock `bootcount`/`resetbc` mechanism.
2. **Layer 2 (this package):** firmware boots but is not confirmed within a
   deadline → explicit revert: set the boot-partition variable back and
   reboot. Independent of the boot counter, so the stock counter committing
   the boot does not disarm us.

### Flow

```
sysupgrade-confirm arm      # pre-flash (owut hook does this automatically)
  -> writes /etc/sysupgrade-confirm/pending
     {previous partition, deadline, one-time token}
  -> rides the sysupgrade config backup into the new firmware

# first boot of the new firmware:
procd starts the countdown daemon (monotonic /proc/uptime — a device with
no NTP cannot be fooled). Any ONE of these confirms:
  a) SSH:      sysupgrade-confirm
  b) Browser:  ubus 'sysupgrade-confirm confirm {token}' (anonymous ACL,
               single-use token generated at flash time)
  c) Optional auto-checks (uci): gateway ping / WAN reach, N consecutive passes

# no confirm before the deadline:
fw_setenv boot_part <previous>; reboot   -> back on the old firmware
```

### Commands

| command | effect |
|---|---|
| `sysupgrade-confirm` | confirm the running firmware (clears pending) |
| `sysupgrade-confirm status [--json]` | pending state, deadline, remaining |
| `sysupgrade-confirm arm` | arm the window (normally via the owut hook) |
| `sysupgrade-confirm revert` | flip the boot partition and reboot **now** |

## owut / Attended Sysupgrade integration

owut already has the hook we need: `pre_install` runs after image
verification, before flashing, and a non-zero exit **aborts the flash**.
This package points `attendedsysupgrade.owut.pre_install` at a run-parts
dispatcher (`/etc/owut.d/pre-install.d/`), installs its arming hook as
`50-sysupgrade-confirm`, and preserves any pre-existing operator hook as
`10-preexisting`. Arm failure = no flash — fail-safe.

## Self-carrying across flashes

All files (including the init script and its rc.d symlink) are listed in
`/lib/upgrade/keep.d/sysupgrade-confirm`, so they ride the sysupgrade config
backup and preinit restores them **before rc.d runs**. The revert guard
therefore works even when the image being flashed is a vanilla build without
the package. Only binary dependency: `fw_printenv`/`fw_setenv`
(uboot-envtools), present in Linksys MX default images. For
`sysupgrade -n` (no config keep), inject a minimal tarball with
`sysupgrade -f` if you still want the guard.

## Board support

Board descriptions use the `luci-app-advanced-reboot` device-JSON format
(`/usr/share/sysupgrade-confirm/boards/*.json`; the two shipped files
originate from that app's data). Phase 1: Linksys **MX5300** and **MX8500**
(`boot_part` flip via U-Boot env). Phase 2: dual-boot devices whose
bootloaders never count (TP-Link `tp_boot_idx` style). Adding a board is
usually a copy-paste JSON. `arm` refuses (and thereby aborts the flash) on
boards without a table entry.

## Installing

As an OpenWrt feed:

```
src-git sysupgradeconfirm https://github.com/lschweiss/sysupgrade-confirm.git
```

then `./scripts/feeds update sysupgradeconfirm && ./scripts/feeds install
sysupgrade-confirm luci-app-sysupgrade-confirm` and select under
Utilities / LuCI → Applications.

## Known limits (honest edition)

- Single-partition devices get nothing from this package.
- Browser confirm fails benignly if the LAN IP changes intentionally during
  the upgrade or HTTPS certs regenerate — use the CLI path or a longer
  window for those upgrades.
- A `sysupgrade -n` without the `-f` tarball degrades to layer 1 only.
- The anonymous rpcd surface is exactly `status` (pending flag + timers) and
  token-gated `confirm`; review `acl.d/sysupgrade-confirm.json` before
  deploying somewhere this matters.

## Roadmap

- Full LuCI pre-flash flow: arm from the flash page, hold the token in JS,
  poll across the reboot, auto-confirm on first answer (the successful poll
  *is* the client-path health check).
- Phase-2 boards; `luci-app-attendedsysupgrade` upstream PR for arming.
- Submission to openwrt/packages after ≥2 release cycles of production use.

## License

GPL-2.0-or-later. Copyright (C) 2026 Chip Schweiss.
