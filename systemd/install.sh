#!/usr/bin/env bash
# systemd/install.sh — install the home-server systemd units (symlink-into-repo, so
# editing a unit here IS editing the live unit), reload, and start the timers.
# Idempotent; run as root. Called by ../install.sh. Secrets are NOT installed here.
#
# Scope: the HOST units only — wifi, host backups (flash restic), and the todo hub. The
# Valheim units (mod checks, Discord feeds, guest vzdump) moved to the valheim-server repo
# and are installed by /srv/dev/repos/valheim-server/systemd/install.sh (run by
# ../install.sh as a final step, or standalone).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
UNIT_DIR=/etc/systemd/system
[ "$(id -u)" -eq 0 ] || { echo "systemd/install.sh: run as root"; exit 1; }

say() { printf '\n\033[1m-- %s\033[0m\n' "$*"; }

# All repo-maintained unit files (link them so the repo is the source of truth).
UNITS=(
  home-server-wifi.service
  hs-restic-flash.service   hs-restic-flash.timer
  hs-todo-classify.service      hs-todo-classify.timer
  hs-todo-sync.service          hs-todo-sync.path   # push-on-commit -> hub (see todo repo)
)
# Timer(s) this installer activates. (`enable --now` on a *timer* only starts its
# schedule; it does not run the job immediately.) The backup timer's enable-state is left
# to bootstrap.sh / the operator so this installer never silently flips backup behaviour.
TIMERS=(hs-todo-classify.timer)

say "linking units into $UNIT_DIR"
for u in "${UNITS[@]}"; do
  if [ -f "$REPO/systemd/$u" ]; then
    ln -sfn "$REPO/systemd/$u" "$UNIT_DIR/$u"
    echo "  linked $u"
  else
    echo "  skip (missing in repo): $u"
  fi
done
chmod +x "$REPO/todo/classify-drain.sh" 2>/dev/null || true

say "reload + enable timers"
systemctl daemon-reload
for t in "${TIMERS[@]}"; do
  systemctl enable --now "$t" && echo "  enabled --now $t"
done
# Path watcher(s): `enable --now` on a .path starts watching immediately. The store
# clone must exist for the watched .git/logs/HEAD to be present; skip cleanly if not.
for p in hs-todo-sync.path; do
  if [ -e /srv/dev/repos/todo/.git/logs/HEAD ]; then
    systemctl enable --now "$p" && echo "  enabled --now $p"
  else
    echo "  $p: skipped (todo store clone not present at /srv/dev/repos/todo yet)"
  fi
done
# home-server-wifi.service is owned/enabled by bootstrap.sh; not touched here
# (restarting it would drop the host's uplink). Backup timer reported, not changed:
for t in hs-restic-flash.timer; do
  echo "  $t: $(systemctl is-enabled "$t" 2>/dev/null || echo 'not-enabled')  (enable with: systemctl enable --now $t)"
done
echo "systemd units installed."
