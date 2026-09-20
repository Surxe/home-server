#!/usr/bin/env bash
# wrf-probe/install.sh — build/refresh the WRFrontiersDB-Orchestrator clone's venv
# on this box so the hs-wrf-update-probe unit can run src/probe.py, then arm its
# poll timer. Idempotent; run as root (called by ../install.sh). Guarded on the
# sibling clone being present.
#
# The Orchestrator repo (github.com/Surxe/WRFrontiersDB-Orchestrator) owns the
# probe itself (src/probe.py + its data/ state file + steam[client] in its
# requirements.txt). This box supplies only the schedule + calling:
#   systemd/hs-wrf-update-probe.{service,timer}
# and the one box-local build step the generic repo can't: the venv.
#
# The probe is anonymous — it carries NO secrets, so (unlike steam-tracker) there
# is no env file to install or report. (The eventual real download needs owned
# Steam creds, but that's the orchestrator pipeline's concern, not the probe's.)
set -euo pipefail

CLONE=/srv/dev/repos/WRFrontiersDB-Orchestrator
[ "$(id -u)" -eq 0 ] || { echo "wrf-probe/install.sh: run as root"; exit 1; }

say() { printf '\n\033[1m-- %s\033[0m\n' "$*"; }

if [ ! -d "$CLONE/.git" ]; then
  echo "wrf-probe: clone not found at $CLONE — skipping (git clone https://github.com/Surxe/WRFrontiersDB-Orchestrator.git there to enable)"
  exit 0
fi

# Build/refresh the project venv AS dev (dev owns the clone). Idempotent: venv
# no-ops if .venv exists; pip install is a fast up-to-date check. steam[client]
# pulls a gevent/eventemitter stack — the first build is not instant.
say "wrf-probe: building/refreshing venv (as dev)"
runuser -u dev -- bash -euc '
  cd "'"$CLONE"'"
  [ -d .venv ] || python3 -m venv .venv
  .venv/bin/pip install -q -r requirements.txt
'
echo "  venv ready at $CLONE/.venv"

# Arm the poll timer now that its prerequisite (the venv) exists. systemd/install.sh
# links the unit files (and runs first); a daemon-reload here is belt-and-suspenders
# for the standalone case. `enable --now` on a timer only arms the schedule; it does
# NOT run a probe immediately. Idempotent.
say "wrf-probe: enabling poll timer"
systemctl daemon-reload || true
if [ -f /etc/systemd/system/hs-wrf-update-probe.timer ]; then
  systemctl enable --now hs-wrf-update-probe.timer && echo "  enabled --now hs-wrf-update-probe.timer"
else
  echo "  hs-wrf-update-probe.timer not linked yet — run systemd/install.sh (or ../install.sh)"
fi
echo "wrf-probe: install done."
