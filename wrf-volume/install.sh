#!/usr/bin/env bash
# wrf-volume/install.sh — ensure /srv/dev/wrf (the WRF pipeline data volume, WRF_ROOT)
# is mounted from the thick LV pve/wrf. Idempotent. The fstab line is `nofail`, so
# this is harmless before the volume is provisioned (see provision-shrink.sh for the
# one-time LVM carve). Run as root (called by ../install.sh).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "wrf-volume/install.sh: run as root"; exit 1; }

DEV=/dev/pve/wrf
MNT=/srv/dev/wrf
say(){ printf '\n\033[1m-- %s\033[0m\n' "$*"; }

say "wrf-volume: ensuring fstab mount for $MNT"
mkdir -p "$MNT"
if ! grep -qE "[[:space:]]$MNT[[:space:]]" /etc/fstab; then
  echo "$DEV  $MNT  ext4  defaults,nofail,x-systemd.device-timeout=10  0  2" >> /etc/fstab
  echo "  added fstab line for $MNT"
  systemctl daemon-reload || true
else
  echo "  $MNT already in fstab"
fi

if [ -b "$DEV" ]; then
  mountpoint -q "$MNT" || mount "$MNT"
  if mountpoint -q "$MNT"; then
    chown dev:dev "$MNT"
    chmod 2775 "$MNT"
    echo "  mounted $MNT (size $(df -h --output=size "$MNT" | tail -1 | tr -d ' ')), owned by dev:dev"
  else
    echo "  !! $DEV present but $MNT did not mount — investigate" >&2
    exit 1
  fi
else
  echo "  $DEV not present yet — volume unprovisioned. fstab line is nofail, so boot is safe."
  echo "  Provision it once with: sudo $(dirname "$0")/provision-shrink.sh  then reboot."
fi
