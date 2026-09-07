# 07 — Current status and box-Claude's first tasks

READ THIS FIRST if you are Claude running on the home-server box. It records the
exact state the box was left in during the initial hands-on session, and the
immediate work to do. Then read `00`-`06` for the full plan.

## Where things stand (as of the handoff)

**Host**
- Proxmox VE 9.2 (Debian 13 base) installed on the single ~480GB disk, ext4 + LVM-thin.
- Hostname: `home-server.lan`. Single disk, no ZFS.
- Headless, no desktop (as intended).
- Secure Boot and Fast Boot were disabled in BIOS to boot the installer; leave off.

**apt**
- Enterprise repos were disabled (renamed to `*.sources.disabled`): `pve-enterprise.sources`, `ceph.sources`.
- Added `/etc/apt/sources.list.d/pve-no-subscription.sources` (trixie, pve-no-subscription, signed by proxmox-archive-keyring). `apt update` is clean.
- `debian.sources` (Debian trixie + security) is intact.

**Networking — WORKS AT RUNTIME ONLY, NOT PERSISTENT (this is the #1 fix)**
- Wifi: Intel AX200 = interface `wlp1s0`. Associated to the house SSID.
- Got a DHCP lease: `192.168.0.239/24`, gateway `192.168.0.1`. Online (pings + apt work).
- wpa config: `/etc/wpa_supplicant/wpa_supplicant-wlp1s0.conf` (created via wpa_passphrase, chmod 600).
- The installer wrote a bogus static bridge `vmbr0 = 192.168.100.2/24` with `gateway 192.168.100.1` in `/etc/network/interfaces`. That dead gateway HIJACKS the default route on boot and black-holes traffic.
- It was worked around **at runtime only**: `ip route del default via 192.168.100.1 dev vmbr0` then a dhclient renew installed `default via 192.168.0.1 dev wlp1s0`.
- NOTHING here survives a reboot: wifi won't auto-start, and vmbr0's dead gateway will come back.

**Packages installed**
- Wifi stack (ferried in as .debs from a Trixie box): `wpasupplicant iw libnl-3-200 libnl-genl-3-200 libnl-route-3-200 libpcsclite1 wireless-regdb`. Also `rfkill`, `curl`, `sudo`, `nodejs`(v20)+`npm`.

**Users**
- `root`: has the install password. This is the **break-glass** account (console recovery).
- `dev`: created with `adduser --disabled-password`; no login password; **passwordless sudo** via `/etc/sudoers.d/dev`. Reached by `su - dev` from root. This is the account Claude runs as.

**Claude Code**
- Installed via the native installer (Node 20 was too old for the npm build, which needs Node >=22). Binaries in `/root/.local/bin` and `/home/dev/.local/bin`. Version 2.1.x.
- Runs as `dev` with `--dangerously-skip-permissions` (root refuses that flag). Authed as `dev`.

**SSH**
- Proxmox's default root-password SSH is on and was used from Ethan's home PC to complete the browserless auth (copy-paste the long URL). Not yet hardened.

## Box-Claude's first tasks (in order)

1. **MAKE NETWORKING PERSISTENT BEFORE ANY REBOOT.** Two parts:
   - Auto-start wifi on boot for `wlp1s0` using the existing
     `/etc/wpa_supplicant/wpa_supplicant-wlp1s0.conf` (e.g. enable
     `wpa_supplicant@wlp1s0` and give `wlp1s0` a dhcp stanza, or an equivalent
     that reliably brings the link up + DHCP). Verify it actually reconnects.
   - Remove the dead `gateway 192.168.100.1` line from the `vmbr0` stanza in
     `/etc/network/interfaces` so it stops stealing the default route. Keep
     `vmbr0` itself for later VM networking, just without that gateway.
   - Only trust it after a test reboot brings the box back online unattended.
2. **Harden SSH** to key-only (add Ethan's home-PC public key; disable password
   + root password login) once persistence is confirmed — see `01` section 6.
3. Then proceed with the plan: VM NAT/bridge networking (`01` section 3), the
   Valheim VM (`02` + `SERVER-HANDOFF.md` + `drop_that.drop_table.cfg` in this
   dir), backups (`03`), and the repo + bootstrap (`04`).

## Still needs Ethan (not blocking task 1)

- Valheim: server name, world name, server password.
- Secrets: restic password; B2 `valheim-world` bucket + scoped key; GitHub
  `Surxe/home-server` repo + ruleset + Surxe-dev PAT.
- Dedicating the 210GB USB stick as the backup target (it was used to ferry the
  wifi debs and these docs; reformat to a real backup fs when ready).
