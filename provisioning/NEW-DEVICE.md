# New-device setup — bare metal to running home server

The ordered checklist for standing this server up on a new/replacement laptop.
Steps 0-5 are the cold-start path (partly offline); the rest run once the box is
online. The design goal is a fast, repeatable rebuild — the box is disposable
because getting it back is this list plus restoring data.

What must travel by **flashdrive** (offline): only the repo + the wifi bundle
(`gather-bundle.sh` builds it). Everything else the box downloads itself once
online — see `offline-bundle.manifest`.

## 0. On a working box (e.g. the dev workstation) — build the flash bundle

```bash
cd /srv/dev/repos/home-server
./provisioning/gather-bundle.sh /media/<you>/<flash-mount>
```
Then safely unmount the flash and take it to the new laptop.
(Run this on a box matching the target's Debian release — trixie for Proxmox 9.)

## 1. Install Proxmox VE (at the laptop, manual)

- Flash the Proxmox VE ISO to a USB and boot it (BIOS: boot order, enable
  virtualization; disable Secure Boot + Fast Boot if they block the installer).
- Install: single disk, **ext4 + default LVM-thin**, set the **root password**
  (save it to your password manager — it is the console break-glass credential).
- Details and the wifi/network caveat: `docs/01-proxmox-host.md`.

## 2. First boot

- Log in as `root` at the console. Note the box has no working network yet
  (Proxmox can't configure wifi at install time).

## 3. First contact — get online (from the flash bundle)

- Plug in the flash, mount it, and run the bundle's first-contact script as root:
  ```bash
  mount /dev/sdX1 /mnt/usb            # the flash partition
  cd /mnt/usb/home-server-bundle
  ./first-contact.sh
  ```
- It installs the ferried wifi `.debs`, fixes the apt repos, prompts for your wifi
  SSID/password, brings wifi up, and extracts the repo to
  `/srv/dev/repos/home-server`. You are now online (runtime only, not yet persistent).

## 4. Apply the config (make it persistent)

```bash
cd /srv/dev/repos/home-server
sudo ./bootstrap.sh
```
Installs `home-server-wifi.service` (wifi persistence), the backup units, lid/sleep
protection, and the fstab backup mount. Idempotent.

## 5. Reboot and confirm

- Reboot. Confirm the box comes back **online unattended**:
  ```bash
  systemctl status home-server-wifi     # active (exited)
  ip route show default                  # via <gateway> dev <wifi-iface>
  ```
- If it fails: `/root/RECOVERY-home-server.md` (manual bring-up) and re-check the
  wifi service ordering.

## 6. Online steps (no flash needed — the box fetches these)

- **Node.js + Claude Code** (to run the loop on the box): native installer
  `curl -fsSL https://claude.ai/install.sh | bash` (system Node in trixie is too old
  for the npm build). Run/auth as the `dev` user. See `docs/07-status.md`.
- **Valheim VM**: `guests/create-valheim-vm.sh` (pulls the Debian cloud image),
  then `guests/vm-apply-valheim.sh`.
- **Secrets** (never on the flash, never in the repo):
  - `/etc/home-server/backup.env`  (restic password file + B2 bucket-scoped key) —
    template `backups/backup.env.example`.
  - `/etc/valheim/valheim.env`     (server/world name + password) —
    template `valheim/valheim.env.example`.
  - Then enable timers:
    `systemctl enable --now hs-restic-flash.timer hs-vzdump-valheim.timer` (host) and
    the in-VM `valheim-b2-world.timer`.
- **Mods**: reconcile `valheim/mods.manifest` to the real
  `SERVER-HANDOFF.md` and run `valheim/stage-mods.sh`.
- **GitHub push auth**: stage the Surxe-dev PAT (`git config --global
  credential.helper store` + a `git fetch`) so the box can push branches.

## 7. Harden / finish

- SSH to key-only (`docs/01-proxmox-host.md` section 6).
- Change any VM break-glass password.
- Restore data (world save, etc.) per `docs/05-restore-runbook.md`.

## The offline gap this closes

Previously the wifi bring-up was fully manual: we hand-downloaded the wifi `.debs`
on another PC and sneaker-netted them, because a fresh Proxmox box can't install a
wifi client without internet, and can't get internet without one. Steps 0 and 3
above now automate exactly that.
