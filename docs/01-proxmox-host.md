# 01 — Proxmox host install and base config

Goal: a headless Proxmox VE host on the laptop, reachable by SSH from Ethan's
home PC, with a break-glass admin login and lid/suspend disabled. Done **at the
laptop** until SSH works, then remote.

## 0. Pre-flight (at the laptop, in BIOS/UEFI)

- Set boot order to boot the USB installer.
- Enable virtualization: **VT-x/AMD-V** and, if present, **VT-d/IOMMU** (needed
  for clean VM CPU passthrough; harmless if unused).
- Note the wifi chipset (`lspci`/`lsusb` from any live Linux) — some need
  **non-free firmware**, which affects the installer choice below.

## 1. Installer

Proxmox VE ships as a Debian-based ISO. Two honest options:

- **Proxmox VE ISO (recommended):** flash to USB (Ventoy or `dd`), install. It is
  Debian under the hood; you get the web UI and `pve` tooling out of the box.
- **Debian first, then add the Proxmox repo:** more steps, only worth it if the
  Proxmox ISO cannot see the wifi/disk.

Wifi caveat for the installer: the Proxmox installer expects **wired** networking.
If the laptop has no ethernet, the cleanest path is: install with wifi *unconfigured*
(or via a temporary USB-ethernet dongle if you have one), finish install, then
bring wifi up by hand in step 3.

### Disk layout (480GB, single disk)

- Filesystem: **ext4** (matches Ethan's simplicity preference; ZFS is overkill
  for a single disk and eats RAM).
- Let the installer create the default **LVM + LVM-thin** layout.
- Suggested: ~30GB for the host root (`/`), remainder to the **thin pool** for
  guest disks. Thin-provisioning means you do not pre-size each guest; you grow
  guest disks later on demand.

## 2. First boot and updates

- Proxmox defaults to the **enterprise apt repo**, which fails without a
  subscription. Switch to the **no-subscription** repo before `apt update`
  (disable `pve-enterprise.list`, add the `pve-no-subscription` repo). Document
  the exact lines you used here once done.
- `apt update && apt full-upgrade`, reboot.

## 3. Networking — wifi host (READ THIS, it is the sharp edge)

Proxmox networking assumes wired + a **bridge** (`vmbr0`). **Bridging does not
work over wifi**: access points drop frames with a MAC they did not authenticate,
so VMs bridged onto wifi cannot get their own L2 presence.

This is fine for us because **Valheim crossplay is outbound-only** (PlayFab relay,
no inbound ports). So:

- Bring the host wifi up with **wpa_supplicant** (install non-free firmware first
  if the chipset needs it). Give the host a **static IP** or a DHCP reservation so
  SSH is predictable.
- Give VMs a **NAT/routed** network instead of a bridge: an internal bridge
  (`vmbr0`, no physical port) plus **iptables masquerade** out through the wifi
  interface. VMs get outbound internet; nothing inbound is needed for crossplay.
- If ethernet ever becomes available, switch to a normal bridge and delete the
  NAT — simpler and lower-latency. Note that as a future option, do not block on it.

Record the final `/etc/network/interfaces`, the wpa_supplicant unit, and the
masquerade rule in the `home-server` repo (see `04-repo-and-bootstrap.md`).

## 4. Headless — no graphics

Nothing to do beyond *not* installing a desktop. Proxmox is headless by default.
Do not install KDE/Wayland/Xorg or any GPU/gaming driver. The Valheim dedicated
server renders nothing.

## 5. Lid and suspend (bake into bootstrap, do not rely on memory)

A closed-lid laptop server must never sleep. Set in `logind`:

```
# /etc/systemd/logind.conf.d/home-server.conf
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
```

And mask sleep for good measure:

```
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

`systemctl restart systemd-logind` (or reboot). This file goes in the repo and is
applied by `bootstrap.sh`, so a rebuild re-enforces it automatically.

## 6. SSH — key-only from the home PC (DEFERRED)

> Deferred for now. Ethan works at the **local console**; Claude runs on the box
> itself. Set this up later when remote access is wanted. Kept here as the
> future recipe.


On the host:

- Ensure `openssh-server` is installed and enabled.
- Add Ethan's home-PC public key to the login account's `~/.ssh/authorized_keys`.
- Harden `sshd_config`:
  ```
  PasswordAuthentication no
  PermitRootLogin prohibit-password   # key-only root, or 'no' if using a sudo user
  KbdInteractiveAuthentication no
  ```
  Optionally bind SSH to the LAN IP only.
- `systemctl restart ssh`. Verify key login **before** closing the password door
  in a way that could lock you out.

Shared-apartment note: SSH is encrypted, so tenants cannot read the session. The
only exposure is that anything on the subnet can *attempt* login — key-only auth
defeats that. Host-key verification on first connect guards against ARP-spoof MITM.

## 7. Break-glass admin

Keep one recovery path that does not depend on Claude or on a config Claude might
break:

- A separate admin user (or `root`) with a **strong password stored in Ethan's
  password manager**, not on the box.
- This account is for recovery only — not day-to-day, not used by Claude.
- Because it exists, a botched sudo/SSH/network change is recoverable from the
  laptop keyboard rather than a reinstall.

## Exit criteria for today's step 1

- Proxmox web UI reachable locally (`https://<host-ip>:8006`) — or just a working
  root console; SSH is deferred.
- Host is on wifi with outbound internet (for Claude's API + Valheim crossplay).
- Host survives lid-close without suspending.
- Break-glass credential saved off-box.
