#!/usr/bin/env bash
# install.sh — top-level installer for the home-server host. Orchestrates the
# per-area installers (systemd units, ...). Each sub-installer is idempotent and
# self-contained, so this is safe to re-run. Run as root.
#
# Relationship to bootstrap.sh: bootstrap.sh is the full first-boot host apply
# (network/interfaces, wifi service, fstab, sleep masking, guest checks). install.sh
# is the modular component installer you call to (re)install a subsystem — today it
# wires the systemd units (incl. the Valheim mod-update email alert). Both use the
# same symlink-into-repo model, so running either keeps the live units == this repo.
#
# Secrets are never installed by these scripts — only their locations under
# /etc/home-server/ (see each *.env.example).
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
[ "$(id -u)" -eq 0 ] || { echo "run as root:  sudo $0"; exit 1; }

echo "== home-server install =="

# Refresh the shared dev-env clone first so this box deploys the latest shared
# layer (a stale clone silently ships old fragments — e.g. missing the ds/key
# export). Pull as dev to keep the clone dev-owned; warn and continue on error.
if [ -d "$REPO/../dev-env/.git" ]; then
  if runuser -u dev -- git -C "$REPO/../dev-env" pull --ff-only; then
    echo ">> dev-env clone updated"
  else
    echo "!! dev-env clone update failed — continuing with existing checkout" >&2
  fi
fi

# Installers to run, in order. Add more here as subsystems get their own installer.
INSTALLERS=(
  "$REPO/systemd/install.sh"   # host systemd units (root)
  "$REPO/todo/install.sh"      # shared `todo` CLI -> dev's ~/.local/bin (writes as dev)
  "$REPO/claude/install.sh"    # dev's agent context: box-local AGENTS.md, skills, memory -> ~/.agents + ~/.dsh (writes as dev)
  "$REPO/../dev-env/install.sh"  # shared dev config layer: portable skills/cc/ds/memories + dsh plugin (writes as dev)
)

for inst in "${INSTALLERS[@]}"; do
  if [ -x "$inst" ]; then
    echo ">> $inst"
    "$inst"
  elif [ -f "$inst" ]; then
    echo ">> bash $inst"
    bash "$inst"
  else
    echo "!! missing installer: $inst" >&2
    exit 1
  fi
done

echo
echo "== home-server install complete =="
