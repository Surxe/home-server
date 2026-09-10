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

# Installers to run, in order. Add more here as subsystems get their own installer.
INSTALLERS=(
  "$REPO/systemd/install.sh"
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
