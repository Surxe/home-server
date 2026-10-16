#!/usr/bin/env bash
# hs-tmp-watch.sh — email a warning when /tmp grows past a threshold.
# Driven by systemd/hs-tmp-watch.{service,timer} on the Proxmox host.
#
# Why it matters on THIS box: /tmp is a tmpfs, i.e. it lives in RAM, and under memory
# pressure its pages are pushed out to the swap partition. Every GB parked in /tmp
# (agent scratchpads, build caches, downloads) is RAM + swap that the Valheim VM and
# the host services can't use. On 2026-10-15 ~2 GB of stale Claude scratch was ~2 GB
# of the 3.2 GB of swap in use.
#
# Credentials are NOT in the repo: the service pulls them from
#   /etc/home-server/host-alerts.env   (root:root 0600, see host/host-alerts.env.example)
# via EnvironmentFile, so they arrive here as env vars:
#   SMTP_HOST SMTP_PORT SMTP_USER SMTP_PASS MAIL_FROM MAIL_TO
#
# Re-nag policy: one email when /tmp crosses the threshold, then at most one per
# TMP_WATCH_RENAG_HOURS while it stays above; dropping back below resets it. State
# lives outside the repo in /var/lib/hs-tmp-watch/.
#
# Usage:
#   host/hs-tmp-watch.sh           # check; email if over threshold (and not recently)
#   host/hs-tmp-watch.sh --force   # email now regardless of threshold/state (test send)
#   host/hs-tmp-watch.sh --dry-run # print the email instead of sending it
#
# Exit: 0 = ok (emailed or nothing to do); 1 = wanted to email but SMTP unconfigured
# or the send failed (so the unit shows failed, which hs-health.sh also surfaces).
set -euo pipefail

: "${TMP_WATCH_PATH:=/tmp}"
: "${TMP_WATCH_PCT:=50}"            # alert when used >= this % of the tmpfs size
: "${TMP_WATCH_RENAG_HOURS:=24}"
: "${TMP_WATCH_STATE_DIR:=/var/lib/hs-tmp-watch}"
: "${SMTP_HOST:=smtp.gmail.com}" "${SMTP_PORT:=587}"
export TMP_WATCH_PATH TMP_WATCH_PCT SMTP_HOST SMTP_PORT

FORCE=0 DRY=0
for a in "$@"; do
  case "$a" in
    --force) FORCE=1 ;;
    --dry-run) DRY=1 ;;
    *) echo "usage: $0 [--force] [--dry-run]" >&2; exit 2 ;;
  esac
done

read -r SIZE USED PCT < <(df -P -B1 "$TMP_WATCH_PATH" | awk 'NR==2 {gsub("%","",$5); print $2, $3, $5}')
STAMP="$TMP_WATCH_STATE_DIR/last-alert"
mkdir -p "$TMP_WATCH_STATE_DIR"

if [ "$FORCE" -eq 0 ]; then
  if [ "$PCT" -lt "$TMP_WATCH_PCT" ]; then
    rm -f "$STAMP"
    echo "tmp-watch: $TMP_WATCH_PATH at ${PCT}% (< ${TMP_WATCH_PCT}%) — ok"
    exit 0
  fi
  if [ -f "$STAMP" ] && [ -n "$(find "$STAMP" -mmin -$((TMP_WATCH_RENAG_HOURS * 60)))" ]; then
    echo "tmp-watch: $TMP_WATCH_PATH at ${PCT}% — already alerted within ${TMP_WATCH_RENAG_HOURS}h, not re-sending"
    exit 0
  fi
fi

# Report inputs, handed to python via env. awk NR<=N (not head) caps the lists: head
# would close the pipe early and SIGPIPE the pipeline under pipefail.
TOP="$(du -x -s -B1 "$TMP_WATCH_PATH"/* "$TMP_WATCH_PATH"/.[!.]* 2>/dev/null | sort -rn \
       | awk 'NR<=10 {printf "  %8.1f MB  %s\n", $1/1048576, $2}')"
CLAUDE_TOP="$(du -x -s -B1 "$TMP_WATCH_PATH"/claude-*/-*/* 2>/dev/null | sort -rn \
       | awk 'NR<=5 {printf "  %8.1f MB  %s\n", $1/1048576, $2}')"
SWAP="$(free -h | awk '/^Mem:|^Swap:/ {printf "  %-5s total %s, used %s, free %s\n", $1, $2, $3, $4}')"
export SIZE USED PCT TOP CLAUDE_TOP SWAP FORCE DRY

python3 - <<'PY'
import os, smtplib, ssl, sys
from email.message import EmailMessage

e = os.environ
gb = lambda b: "%.1f GB" % (int(b) / 1073741824)
path, pct = e["TMP_WATCH_PATH"], e["PCT"]

lines = [
    "%s on home-server is at %s%% of its tmpfs size (%s of %s; alert threshold %s%%)."
    % (path, pct, gb(e["USED"]), gb(e["SIZE"]), e["TMP_WATCH_PCT"]),
    "",
    "Reminder: /tmp is a tmpfs, so it lives in RAM and spills into the SWAP PARTITION",
    "under pressure. Everything sitting in /tmp is backup memory (RAM + swap) that the",
    "Valheim VM and the other host services are competing for. Clear what you don't need.",
    "",
    "Memory / swap now:",
    e["SWAP"],
    "",
    "Largest entries in %s:" % path,
    e["TOP"] or "  (none)",
]
if e.get("CLAUDE_TOP"):
    lines += ["", "Largest Claude session scratch dirs (safe to delete once the session has ended):",
              e["CLAUDE_TOP"]]
lines += ["",
          "Clean up e.g.:  sudo du -sh %s/* | sort -h" % path,
          "Old Claude scratch:  find %s/claude-*/ -mindepth 2 -maxdepth 2 -type d -mtime +1" % path,
          "",
          "Sent by hs-tmp-watch.timer (home-server repo: host/hs-tmp-watch.sh)."]

msg = EmailMessage()
msg["Subject"] = "[home-server] %s is %s%% full (RAM/swap-backed)" % (path, pct)
msg["From"] = e.get("MAIL_FROM", "")
msg["To"] = e.get("MAIL_TO", "")
msg.set_content("\n".join(lines))

if e["DRY"] == "1":
    print(msg)
    sys.exit(0)

missing = [k for k in ("MAIL_FROM", "MAIL_TO", "SMTP_USER", "SMTP_PASS") if not e.get(k)]
if missing:
    print("tmp-watch: SMTP not configured (missing %s in /etc/home-server/host-alerts.env); "
          "%s is at %s%%." % (", ".join(missing), path, pct), file=sys.stderr)
    sys.exit(1)

try:
    with smtplib.SMTP(e["SMTP_HOST"], int(e["SMTP_PORT"]), timeout=30) as s:
        s.ehlo(); s.starttls(context=ssl.create_default_context()); s.ehlo()
        s.login(e["SMTP_USER"], e["SMTP_PASS"])
        s.send_message(msg)
except (smtplib.SMTPException, OSError) as exc:
    print("tmp-watch: email failed: %s" % exc, file=sys.stderr)
    sys.exit(1)
print("tmp-watch: emailed MAIL_TO — %s at %s%%" % (path, pct))
PY

# Only a real (non-forced, non-dry) alert arms the re-nag window.
[ "$FORCE" -eq 0 ] && [ "$DRY" -eq 0 ] && touch "$STAMP"
exit 0
