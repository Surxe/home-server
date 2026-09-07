#!/bin/bash
# restic-flash.sh — file-level backup to the USB stick (twice daily).
# Scope: host config + this repo + the Valheim world dir. Dedup+encrypted+checked.
# Retention: keep-within 14d then prune. Secrets come from /etc/home-server/backup.env.
set -euo pipefail

ENV_FILE=/etc/home-server/backup.env
BACKUP_MNT=/mnt/backup
REPO="${BACKUP_MNT}/restic-repo"

# shellcheck disable=SC1090
[ -r "$ENV_FILE" ] || { echo "FATAL: $ENV_FILE missing (restic password not staged)"; exit 1; }
source "$ENV_FILE"
export RESTIC_PASSWORD_FILE

# Guard: a backup to a missing mount is a silent no-op — refuse it.
mountpoint -q "$BACKUP_MNT" || { echo "FATAL: $BACKUP_MNT not mounted"; exit 1; }
export RESTIC_REPOSITORY="$REPO"

# First run inits the repo (needs the password to exist).
restic snapshots >/dev/null 2>&1 || restic init

# Paths to protect. The repo checkout captures all symlinked host config;
# also grab the non-symlinked bits and the world save directly.
PATHS=(
  /srv/dev/repos/home-server
  /etc/fstab
  /etc/network/interfaces.orig-preclaude
  /etc/pve
  /srv/valheim/config
)
EXISTING=(); for p in "${PATHS[@]}"; do [ -e "$p" ] && EXISTING+=("$p"); done

restic backup --verbose --tag flash "${EXISTING[@]}"
restic forget --keep-within 14d --prune
restic check
