#!/usr/bin/env bash
# gta6-watcher/install.sh -- build/refresh the gta6-emulation-watcher clone's venv on
# this box so hs-gta6-watch.service can run it, then arm its daily timer. Idempotent;
# run as root (called by ../install.sh). Guarded on the sibling clone being present.
#
# The watcher repo (github.com/Surxe/gta6-emulation-watcher) is generic -- it carries
# no box config. This box supplies:
#   - SMTP secrets + recipient -> /etc/home-server/gta6-watcher.env (root 600, by hand)
#   - the schedule + calling   -> systemd/hs-gta6-watch.{service,timer}
# This script only owns the box-local build step the generic repo can't: the venv.
#
# Secrets are NOT installed here -- only reported. See gta6-watcher.env.example.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CLONE=/srv/dev/repos/gta6-emulation-watcher
SECRET=/etc/home-server/gta6-watcher.env
TIMER=hs-gta6-watch.timer
[ "$(id -u)" -eq 0 ] || { echo "gta6-watcher/install.sh: run as root"; exit 1; }

say() { printf '\n\033[1m-- %s\033[0m\n' "$*"; }

if [ ! -d "$CLONE/.git" ]; then
  echo "gta6-watcher: clone not found at $CLONE -- skipping (gh repo clone Surxe/gta6-emulation-watcher there to enable)"
  exit 0
fi

# Build/refresh the venv AS dev (dev owns the clone). venv no-ops if it exists; pip
# install is a fast up-to-date check.
say "gta6-watcher: building/refreshing venv (as dev)"
runuser -u dev -- bash -euc '
  cd "'"$CLONE"'"
  [ -d .venv ] || python3 -m venv .venv
  .venv/bin/pip install -q -r requirements-dev.txt
'
echo "  venv ready at $CLONE/.venv"

# Arm the daily timer now that its prerequisite (the venv) exists. `enable --now` on a
# timer only arms the schedule; it does not run the job immediately.
say "gta6-watcher: enabling daily timer"
systemctl daemon-reload || true
if [ -f "/etc/systemd/system/$TIMER" ]; then
  systemctl enable --now "$TIMER" && echo "  enabled --now $TIMER"
else
  echo "  $TIMER not linked yet -- run systemd/install.sh (or ../install.sh)"
fi

# Report the secret's status (never create/read/echo it).
if [ -f "$SECRET" ]; then
  say "gta6-watcher: SMTP secret present ($SECRET) -- email enabled if fully filled"
else
  say "gta6-watcher: SMTP secret NOT present"
  echo "  digests go to the journal only until $SECRET exists (root 600)."
  echo "  stage it with:  install -m 600 /etc/home-server/host-alerts.env $SECRET"
  echo "  or create it from: $REPO/gta6-watcher/gta6-watcher.env.example"
fi
echo "gta6-watcher: install done."
