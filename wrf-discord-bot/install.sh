#!/usr/bin/env bash
# wrf-discord-bot/install.sh — build/refresh the WRFrontiersDB-Discord-Bot clone's
# venv on this box so hs-wrf-discord-bot.service can run it, then enable + (re)start
# the bot if its token is staged. Idempotent; run as root (called by ../install.sh).
# Guarded on the sibling clone being present.
#
# The bot repo (github.com/Surxe/WRFrontiersDB-Discord-Bot) is generic — it carries
# no home-server config. This box supplies:
#   - the token            -> /etc/home-server/wrf-discord-bot.env (root 600, by hand)
#   - options + running it -> systemd/hs-wrf-discord-bot.service
# This script only owns the one box-local build step the generic repo can't: the venv.
#
# Secrets are NOT installed here — only reported. See wrf-discord-bot.env.example.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CLONE=/srv/dev/repos/WRFrontiersDB-Discord-Bot
SECRET=/etc/home-server/wrf-discord-bot.env
UNIT=hs-wrf-discord-bot.service
[ "$(id -u)" -eq 0 ] || { echo "wrf-discord-bot/install.sh: run as root"; exit 1; }

say() { printf '\n\033[1m-- %s\033[0m\n' "$*"; }

if [ ! -d "$CLONE/.git" ]; then
  echo "wrf-discord-bot: clone not found at $CLONE — skipping (git clone https://github.com/Surxe/WRFrontiersDB-Discord-Bot.git there to enable)"
  exit 0
fi

# Build/refresh the project venv AS dev (dev owns the clone). Idempotent: venv
# no-ops if .venv exists; pip install is a fast up-to-date check. Editable install,
# so a pull of the clone is live on the next restart without a reinstall.
say "wrf-discord-bot: building/refreshing venv (as dev)"
runuser -u dev -- bash -euc '
  cd "'"$CLONE"'"
  [ -d .venv ] || python3 -m venv .venv
  .venv/bin/pip install -q -e .
'
echo "  venv ready at $CLONE/.venv"

systemctl daemon-reload || true
if [ ! -f "/etc/systemd/system/$UNIT" ]; then
  echo "  $UNIT not linked yet — run systemd/install.sh (or ../install.sh)"
  exit 0
fi

# Enable + restart only once the token exists (the unit also guards itself with
# ConditionPathExists). Restart, not just start, so a venv/code refresh takes effect.
if [ -f "$SECRET" ]; then
  say "wrf-discord-bot: token present ($SECRET) — enabling + restarting $UNIT"
  systemctl enable "$UNIT"
  systemctl restart "$UNIT" && echo "  restarted $UNIT"
else
  say "wrf-discord-bot: token NOT present — bot left disabled"
  echo "  create $SECRET (root 600) from: $REPO/wrf-discord-bot/wrf-discord-bot.env.example"
  echo "  then re-run this installer (or: systemctl enable --now $UNIT)"
fi
echo "wrf-discord-bot: install done."
