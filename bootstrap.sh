#!/bin/bash
# bootstrap.sh — idempotent apply step for the home-server host.
# Gets a bare Proxmox host from `git clone` to the configured state. Safe to re-run:
# every action checks-then-acts. It NEVER stores secrets and NEVER reboots.
#
# Deploy model: symlink live paths back into this repo where safe; write real files
# where symlinks are refused (fstab); manage guests via qm.  See docs/04.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
link() { # link <target-in-repo> <live-path>
  local src="$1" dst="$2"
  [ -e "$src" ] || { echo "  skip (missing in repo): $src"; return; }
  if [ "$(readlink -f "$dst" 2>/dev/null)" = "$(readlink -f "$src")" ]; then
    echo "  ok: $dst -> $src"; return; fi
  install -d "$(dirname "$dst")"
  [ -e "$dst" ] && [ ! -L "$dst" ] && cp -a "$dst" "${dst}.orig-$(date +%s)" && echo "  backed up existing $dst"
  ln -sfn "$src" "$dst"; echo "  linked: $dst -> $src"
}

[ "$(id -u)" -eq 0 ] || { echo "run as root (sudo)"; exit 1; }

say "1. Symlinks (config-as-code)"
link "$REPO/host/interfaces"              /etc/network/interfaces
link "$REPO/host/logind-home-server.conf" /etc/systemd/logind.conf.d/home-server.conf
link "$REPO/host/hs-wifi-up.sh"           /usr/local/sbin/hs-wifi-up.sh
link "$REPO/systemd/home-server-wifi.service" /etc/systemd/system/home-server-wifi.service
# Host-side backups only: flash restic (host config + repo) + vzdump (whole guest).
# The offsite B2 WORLD backup runs INSIDE the Valheim VM (that's where the world is) —
# see valheim/backup/ + valheim/restic-b2-world.sh, installed during VM provisioning.
for u in hs-restic-flash hs-vzdump-valheim; do
  link "$REPO/systemd/$u.service" "/etc/systemd/system/$u.service"
  link "$REPO/systemd/$u.timer"   "/etc/systemd/system/$u.timer"
done
chmod +x "$REPO"/host/hs-wifi-up.sh "$REPO"/backups/*.sh "$REPO"/guests/*.sh 2>/dev/null || true

say "2. Non-symlinkable files + systemd state"
systemctl daemon-reload
# Immediate, restart-free suspend protection for a lidded laptop.
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
# Wifi persistence (own service; wlp1s0 kept out of ifupdown2).
systemctl enable home-server-wifi.service
# fstab backup mount: keep an existing line; otherwise print a follow-up (UUID differs per stick).
if ! grep -q '/mnt/backup' /etc/fstab; then
  if BK=$(findmnt -no UUID /mnt/backup 2>/dev/null) && [ -n "$BK" ]; then
    echo "UUID=$BK  /mnt/backup  ext4  defaults,nofail,x-systemd.device-timeout=10  0  2" >> /etc/fstab
    echo "  added /mnt/backup fstab line (UUID=$BK)"
  else
    echo "  TODO: format the backup stick ext4 + mount at /mnt/backup, then re-run (adds fstab line)."
  fi
else echo "  ok: /mnt/backup already in fstab"; fi

say "3. Guests"
if command -v qm >/dev/null && ! qm status 100 >/dev/null 2>&1; then
  echo "  Valheim VM (100) absent. Recreate with: $REPO/guests/create-valheim-vm.sh"
  echo "  (needs the Debian cloud image; see the script header.)"
else echo "  ok: VM 100 present (or qm unavailable)"; fi

say "4. Manual follow-ups bootstrap can NOT do"
cat <<'EOF'
  - REBOOT to confirm wifi + default route persist (home-server-wifi.service).
  - Stage secrets (never committed):
      * /etc/home-server/backup.env   (restic pw file + B2 bucket-scoped key)   [see backups/backup.env.example]
      * /etc/valheim/valheim.env      (server/world name + password)            [see valheim/valheim.env.example]
    Then enable timers: systemctl enable --now hs-restic-flash.timer hs-vzdump-valheim.timer hs-restic-b2-world.timer
  - Provide the real valheim-mods/SERVER-HANDOFF.md manifest; reconcile valheim/mods.manifest (incl. ModSentry + FarmGrid) and re-run valheim/stage-mods.sh.
  - Harden SSH to key-only (docs/01 section 6) once remote access is wanted.
EOF
echo
echo "bootstrap complete."
