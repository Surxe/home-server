#!/usr/bin/env bash
# install.sh — top-level installer for the home-server host. Orchestrates the
# per-area installers (systemd units, ...). Each sub-installer is idempotent and
# self-contained, so this is safe to re-run. Run as root.
#
# Relationship to bootstrap.sh: bootstrap.sh is the full first-boot host apply
# (network/interfaces, wifi service, fstab, sleep masking, guest checks). install.sh
# is the modular component installer you call to (re)install a subsystem — it wires the
# host systemd units + agent context, and delegates the whole Valheim subsystem to the
# sibling valheim-server repo. Both use the same symlink-into-repo model, so running
# either keeps the live units == the repos.
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

# Refresh the sibling valheim-server clone too (the Valheim subsystem lives there now).
# Same warn-and-continue as dev-env: a missing/behind clone must not abort the host install.
if [ -d "$REPO/../valheim-server/.git" ]; then
  if runuser -u dev -- git -C "$REPO/../valheim-server" pull --ff-only; then
    echo ">> valheim-server clone updated"
  else
    echo "!! valheim-server clone update failed — continuing with existing checkout" >&2
  fi
fi

# Installers to run, in order. Add more here as subsystems get their own installer.
INSTALLERS=(
  "$REPO/systemd/install.sh"   # host systemd units (root)
  "$REPO/todo/install.sh"      # shared `todo` CLI -> dev's ~/.local/bin (writes as dev)
  "$REPO/claude/install.sh"    # dev's agent context: box-local AGENTS.md, skills, memory -> ~/.agents + ~/.dsh (writes as dev)
  "$REPO/../dev-env/install.sh"  # shared dev config layer: portable skills/cc/ds/memories + dsh plugin (writes as dev)
)
# Valheim subsystem lives in the sibling valheim-server repo — include it only if that
# clone is present (its systemd units + agent context; root, drops to dev where needed).
if [ -f "$REPO/../valheim-server/install.sh" ]; then
  INSTALLERS+=("$REPO/../valheim-server/install.sh")
else
  echo "!! valheim-server clone not found at $REPO/../valheim-server — skipping its install" >&2
fi

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
