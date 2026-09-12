#!/usr/bin/env bash
# systemd/install.sh — install the home-server systemd units (symlink-into-repo, so
# editing a unit here IS editing the live unit), reload, and start the timers.
# Idempotent; run as root. Called by ../install.sh. Secrets are NOT installed here.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
UNIT_DIR=/etc/systemd/system
[ "$(id -u)" -eq 0 ] || { echo "systemd/install.sh: run as root"; exit 1; }

say() { printf '\n\033[1m-- %s\033[0m\n' "$*"; }

# All repo-maintained unit files (link them so the repo is the source of truth).
UNITS=(
  home-server-wifi.service
  hs-restic-flash.service   hs-restic-flash.timer
  hs-vzdump-valheim.service hs-vzdump-valheim.timer
  hs-mod-check.service      hs-mod-check.timer
  hs-todo-classify.service  hs-todo-classify.timer
)
# Timer(s) this installer activates. (`enable --now` on a *timer* only starts its
# schedule; it does not run the job immediately.) We activate only the mod-check timer
# here; the backup timers' enable-state is left to bootstrap.sh / the operator so this
# installer never silently flips backup behaviour.
TIMERS=(hs-mod-check.timer hs-todo-classify.timer)

say "linking units into $UNIT_DIR"
for u in "${UNITS[@]}"; do
  if [ -f "$REPO/systemd/$u" ]; then
    ln -sfn "$REPO/systemd/$u" "$UNIT_DIR/$u"
    echo "  linked $u"
  else
    echo "  skip (missing in repo): $u"
  fi
done
chmod +x "$REPO/valheim/notify-mod-updates.sh" "$REPO/valheim/check-mod-updates.sh" "$REPO/todo/classify-drain.sh" 2>/dev/null || true

say "reload + enable timers"
systemctl daemon-reload
for t in "${TIMERS[@]}"; do
  systemctl enable --now "$t" && echo "  enabled --now $t"
done
# home-server-wifi.service is owned/enabled by bootstrap.sh; not touched here
# (restarting it would drop the host's uplink). Backup timers reported, not changed:
for t in hs-restic-flash.timer hs-vzdump-valheim.timer; do
  echo "  $t: $(systemctl is-enabled "$t" 2>/dev/null || echo 'not-enabled')  (enable with: systemctl enable --now $t)"
done

say "checks"
ENVF=/etc/home-server/mod-notify.env
if [ ! -f "$ENVF" ]; then
  echo "  TODO: mod-update emails need SMTP creds. Do:"
  echo "      install -d -m 700 /etc/home-server"
  echo "      cp $REPO/valheim/mod-notify.env.example $ENVF && chmod 600 $ENVF"
  echo "      # then edit $ENVF and set SMTP_PASS (Gmail app password)"
  echo "  Test:  systemctl start hs-mod-check.service && journalctl -u hs-mod-check.service -n 20"
else
  echo "  ok: $ENVF present"
fi
echo "  next mod-check run: $(systemctl show -p NextElapseUSecRealtime --value hs-mod-check.timer 2>/dev/null || echo '(unknown)')"
echo "systemd units installed."
