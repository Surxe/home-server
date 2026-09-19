#!/usr/bin/env bash
# steam-tracker/install.sh — build/refresh the steam-price-tracker clone's venv on
# this box so the hs-steam-price-refresh unit can run it. Idempotent; run as root
# (called by ../install.sh). Guarded on the sibling clone being present.
#
# The tracker repo (github.com/Surxe/steam-price-tracker) is generic — it carries
# no home-server config. This box supplies:
#   - the tracked-app list  -> steam-tracker/tracked_apps.json (config-as-code, here)
#   - SMTP secrets          -> /etc/home-server/steam-tracker.env (root 600, by hand)
#   - the schedule + calling -> systemd/hs-steam-price-refresh.{service,timer}
# This script only owns the one box-local build step the generic repo can't: the venv.
#
# Secrets are NOT installed here — only reported. See steam-tracker.env.example.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CLONE=/srv/dev/repos/steam-price-tracker
SECRET=/etc/home-server/steam-tracker.env
[ "$(id -u)" -eq 0 ] || { echo "steam-tracker/install.sh: run as root"; exit 1; }

say() { printf '\n\033[1m-- %s\033[0m\n' "$*"; }

if [ ! -d "$CLONE/.git" ]; then
  echo "steam-tracker: clone not found at $CLONE — skipping (git clone https://github.com/Surxe/steam-price-tracker.git there to enable)"
  exit 0
fi

# Build/refresh the project venv AS dev (dev owns the clone). Idempotent: python's
# venv module no-ops if .venv already exists; pip install is a fast up-to-date check.
say "steam-tracker: building/refreshing venv (as dev)"
runuser -u dev -- bash -euc '
  cd "'"$CLONE"'"
  [ -d .venv ] || python3 -m venv .venv
  .venv/bin/pip install -q -r requirements-dev.txt
'
echo "  venv ready at $CLONE/.venv"

# Arm the daily timer now that its prerequisite (the venv) exists. systemd/install.sh
# links the unit files (and runs first), so a daemon-reload here is belt-and-suspenders
# for the standalone case. `enable --now` on a timer only arms the schedule; it does
# NOT run a refresh immediately. Idempotent.
say "steam-tracker: enabling daily refresh timer"
systemctl daemon-reload || true
if [ -f /etc/systemd/system/hs-steam-price-refresh.timer ]; then
  systemctl enable --now hs-steam-price-refresh.timer && echo "  enabled --now hs-steam-price-refresh.timer"
else
  echo "  hs-steam-price-refresh.timer not linked yet — run systemd/install.sh (or ../install.sh)"
fi

# Report the secret's status (never create/read/echo it).
if [ -f "$SECRET" ]; then
  say "steam-tracker: SMTP secret present ($SECRET) — email enabled if fully filled"
else
  say "steam-tracker: SMTP secret NOT present"
  echo "  email stays off until $SECRET exists (root 600)."
  echo "  create it from: $REPO/steam-tracker/steam-tracker.env.example"
fi
echo "steam-tracker: install done."
