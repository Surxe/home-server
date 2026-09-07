#!/bin/bash
# vzdump-valheim.sh — whole-guest image of the Valheim VM to the stick (twice daily).
# Mode snapshot (needs qemu-guest-agent) = consistent image without stopping the server.
# Retention is COUNT-based (vzdump images are large + don't dedup): keep last 6 (~3 days).
set -euo pipefail

ENV_FILE=/etc/home-server/backup.env
BACKUP_MNT=/mnt/backup
DUMPDIR="${BACKUP_MNT}/vzdump"

# shellcheck disable=SC1090
[ -r "$ENV_FILE" ] && source "$ENV_FILE" || true
: "${VALHEIM_VMID:?set VALHEIM_VMID in $ENV_FILE (the Valheim VM id)}"

mountpoint -q "$BACKUP_MNT" || { echo "FATAL: $BACKUP_MNT not mounted"; exit 1; }
install -d "$DUMPDIR"

vzdump "$VALHEIM_VMID" \
  --dumpdir "$DUMPDIR" \
  --mode snapshot \
  --compress zstd \
  --prune-backups keep-last=6 \
  --notes-template '{{guestname}} {{node}}'
