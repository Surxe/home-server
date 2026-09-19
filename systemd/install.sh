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
  hs-wrf-discount-watch.service hs-wrf-discount-watch.timer  # WRF discount announce watch (see wrf-news-research repo)
  hs-steam-price-refresh.service hs-steam-price-refresh.timer  # daily Steam price refresh (see steam-price-tracker repo)
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
# WRF discount watch: enable the poll timer only if the wrf-news-research clone is
# present (the .service also guards itself via ConditionPathExists). `enable --now`
# on a timer only arms the schedule; it does not run the check immediately.
if [ -f /srv/dev/repos/WRFrontiers-News-Scraper/scripts/watch_discount.py ]; then
  systemctl enable --now hs-wrf-discount-watch.timer && echo "  enabled --now hs-wrf-discount-watch.timer"
else
  echo "  hs-wrf-discount-watch.timer: skipped (WRFrontiers-News-Scraper clone not present at /srv/dev/repos/WRFrontiers-News-Scraper yet)"
fi
# hs-steam-price-refresh.timer is linked above but ENABLED by steam-tracker/install.sh,
# right after it builds the tracker clone's venv (the timer's real prerequisite) — that
# avoids a first-run ordering gap, since this installer runs before the venv exists.
# home-server-wifi.service is owned/enabled by bootstrap.sh; not touched here
# (restarting it would drop the host's uplink). Backup timer reported, not changed:
for t in hs-restic-flash.timer; do
  echo "  $t: $(systemctl is-enabled "$t" 2>/dev/null || echo 'not-enabled')  (enable with: systemctl enable --now $t)"
done
echo "systemd units installed."
