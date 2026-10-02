#!/bin/bash
# restic-todo-b2.sh — offsite copy of the cross-box TODO STORE to Backblaze B2.
# RUNS ON THE HOST (this box is the todo hub; the bare store lives here at
# /srv/dev/repos/todo-store.git). This is the store's ONLY offsite copy — its tooling
# is on GitHub, but the captured/classified data here is irreplaceable, and restic->flash
# is on-box. Dedicated, bucket-scoped B2 key (so a leak can touch only the todo bucket,
# never the valheim-world bucket or Ethan's personal b2-backup). Shared restic encryption
# password. Driven by systemd/hs-todo-b2.{service,timer} (daily). keep-within 14d + prune.
set -euo pipefail

ENV_FILE=/etc/home-server/backup.env
STORE=/srv/dev/repos/todo-store.git

[ -r "$ENV_FILE" ] || { echo "FATAL: $ENV_FILE missing (B2 todo key / restic password not staged)"; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"

# Dedicated todo bucket + scoped key. Until these are staged, fail loudly rather than
# silently backing up nothing (or into the wrong bucket). See backups/backup.env.example.
: "${B2_TODO_ACCOUNT_ID:?B2_TODO_ACCOUNT_ID not set in $ENV_FILE (create the todo bucket + scoped key first)}"
: "${B2_TODO_ACCOUNT_KEY:?B2_TODO_ACCOUNT_KEY not set in $ENV_FILE}"
: "${B2_TODO_BUCKET:?B2_TODO_BUCKET not set in $ENV_FILE}"
: "${RESTIC_PASSWORD_FILE:?RESTIC_PASSWORD_FILE not set in $ENV_FILE}"

# restic reads its B2 credentials from the fixed names B2_ACCOUNT_ID / B2_ACCOUNT_KEY.
# Map the todo-scoped key onto them in THIS process only, so we never touch the
# valheim-world-scoped B2_ACCOUNT_* pair that also lives in this env file.
export B2_ACCOUNT_ID="$B2_TODO_ACCOUNT_ID"
export B2_ACCOUNT_KEY="$B2_TODO_ACCOUNT_KEY"
export RESTIC_PASSWORD_FILE
export RESTIC_REPOSITORY="b2:${B2_TODO_BUCKET}:restic"

[ -d "$STORE" ] || { echo "FATAL: $STORE not present (todo hub not set up)"; exit 1; }

restic snapshots >/dev/null 2>&1 || restic init
restic backup --verbose --tag todo "$STORE"
restic forget --keep-within 14d --prune
restic check
