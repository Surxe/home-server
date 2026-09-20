#!/usr/bin/env bash
# wrf-pipeline/install.sh — deploy the WRF orchestrator systemd service.
# Invoked by ../install.sh after WRF volume setup. Idempotent. Requires root.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "wrf-pipeline/install.sh: run as root"; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
say(){ printf '\n\033[1m-- %s\033[0m\n' "$*"; }

say "wrf-pipeline: deploying orchestrator service"

# Deploy the service unit
install -m 0644 "$HERE/wrf-orchestrator.service" /etc/systemd/system/wrf-orchestrator@.service
systemctl daemon-reload

# Verify the secrets template exists (user must populate /etc/home-server/wrf-orchestrator.env)
if [ ! -f /etc/home-server/wrf-orchestrator.env ]; then
  cat "$HERE/wrf-orchestrator.env.example" > /etc/home-server/wrf-orchestrator.env.example
  echo "  !! Secrets file /etc/home-server/wrf-orchestrator.env not found."
  echo "  Template saved to $HERE/wrf-orchestrator.env.example"
  echo "  Populate /etc/home-server/wrf-orchestrator.env with:"
  echo "    STEAM_USERNAME=<...>"
  echo "    STEAM_PASSWORD=<...>"
  echo "    GH_DATA_REPO_PAT=<...>"
  echo "  Then the service will be ready to trigger."
else
  echo "  ✓ secrets file exists"
fi

say "orchestrator service ready"
echo
echo "To invoke the pipeline for a detected patch version:"
echo "  sudo systemctl start wrf-orchestrator@2026-08-22.service"
echo
echo "Monitor the run:"
echo "  sudo journalctl -u wrf-orchestrator@2026-08-22 -f"
echo
