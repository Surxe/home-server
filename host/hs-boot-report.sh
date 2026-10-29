#!/usr/bin/env bash
# hs-boot-report.sh — email one report at every boot: when the host started and
# whether the previous boot ended cleanly. Driven by systemd/hs-boot-report.service.
#
# Why: a host that loses power (or crashes) and comes back sends no other email — every
# alert path assumes the box was up the whole time (WRFrontiersDB ADR-0024, "the guest,
# the host or the home connection is down"). A restart is the cheap moment to notice.
# It does NOT cover an outage the host never comes back from; only an outside heartbeat
# would catch that.
#
# Clean vs unclean: a clean shutdown/reboot makes PID 1 log "Reached target
# shutdown.target" (or final/reboot/poweroff/halt.target) and systemd-shutdown log
# "Syncing filesystems..." near the end of that boot's journal. Only PID 1 and
# systemd-shutdown entries are matched: user managers (systemd --user) also reach their
# own shutdown.target on every logout, which would otherwise look like a clean stop.
# No marker, or no journal at all for the previous boot => "unclean (power loss or
# crash)". This needs a persistent journal (/var/log/journal); with a volatile one there
# is never a previous boot and every report says unclean.
#
# Credentials are NOT in the repo: the service pulls them from
#   /etc/home-server/host-alerts.env   (root:root 0600, see host/host-alerts.env.example)
# via EnvironmentFile, so they arrive here as env vars:
#   SMTP_HOST SMTP_PORT SMTP_USER SMTP_PASS MAIL_FROM MAIL_TO
#
# Wifi comes up late (home-server-wifi.service), so before composing the email this
# waits up to BOOT_REPORT_WAIT seconds for a default route, then retries the send
# BOOT_REPORT_TRIES times, BOOT_REPORT_RETRY_SEC apart.
#
# Usage:
#   host/hs-boot-report.sh           # build the report and email it
#   host/hs-boot-report.sh --dry-run # print the email instead of sending (no waiting)
#
# Exit: 0 = emailed (or dry run); 1 = SMTP unconfigured or every send attempt failed
# (so the unit shows failed, which hs-health.sh also surfaces).
set -euo pipefail

: "${BOOT_REPORT_WAIT:=300}"        # max seconds to wait for a default route
: "${BOOT_REPORT_TRIES:=10}"        # send attempts
: "${BOOT_REPORT_RETRY_SEC:=30}"    # pause between send attempts
: "${UPLINK_IF:=wlp1s0}"            # the host's only uplink (see host/hs-wifi-up.sh)
: "${POWER_AC:=/sys/class/power_supply/ACAD}"
: "${POWER_BAT:=/sys/class/power_supply/BAT1}"
: "${SMTP_HOST:=smtp.gmail.com}" "${SMTP_PORT:=587}"
export BOOT_REPORT_TRIES BOOT_REPORT_RETRY_SEC UPLINK_IF SMTP_HOST SMTP_PORT

DRY=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
  esac
done

# Read a sysfs attribute, or "n/a" when the file is absent (other hardware, no battery).
sysval() { cat "$1" 2>/dev/null || echo "n/a"; }

# Wait for the uplink before composing, so the network line reflects send time.
if [ "$DRY" -eq 0 ]; then
  waited=0
  until ip -4 route show default 2>/dev/null | grep -q . || [ "$waited" -ge "$BOOT_REPORT_WAIT" ]; do
    sleep 5; waited=$((waited + 5))
  done
fi

HOST="$(hostname)"
BOOT_TIME="$(uptime -s 2>/dev/null || echo unknown)"

# Previous boot: the clean-shutdown marker (see header) and the very last entry. Each
# is empty when the previous boot's journal is missing. grep -E rather than journalctl
# -g so this does not depend on journalctl's PCRE2 support.
MARK_RE='Reached target (shutdown|final|reboot|poweroff|halt)\.target|Syncing filesystems'
PREV_MARK="$(journalctl -q --no-pager -b -1 -o short-iso _PID=1 + SYSLOG_IDENTIFIER=systemd-shutdown 2>/dev/null \
             | grep -E "$MARK_RE" | tail -n 1 || true)"
PREV_LAST="$(journalctl -q --no-pager -b -1 -n 1 -o short-iso 2>/dev/null | tail -n 1 || true)"
# Boot list as JSON (first_entry/last_entry in usec); python picks out boots 0 and -1.
BOOTS_JSON="$(journalctl -q --no-pager --list-boots -o json 2>/dev/null || true)"

AC_ONLINE="$(sysval "$POWER_AC/online")"
BAT_STATUS="$(sysval "$POWER_BAT/status")"
BAT_CAP="$(sysval "$POWER_BAT/capacity")"

LINK_STATE="$(sysval "/sys/class/net/$UPLINK_IF/operstate")"
DEFAULT_ROUTE="$(ip -4 route show default 2>/dev/null | awk 'NR==1' || true)"
export HOST BOOT_TIME PREV_MARK PREV_LAST BOOTS_JSON AC_ONLINE BAT_STATUS BAT_CAP \
       LINK_STATE DEFAULT_ROUTE DRY

python3 - <<'PY'
import json, os, smtplib, ssl, sys, time
from datetime import datetime
from email.message import EmailMessage

e = os.environ

def ts(usec):
    return datetime.fromtimestamp(int(usec) / 1e6).astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")

def dur(sec):
    sec = int(sec)
    d, sec = divmod(sec, 86400); h, sec = divmod(sec, 3600); m = sec // 60
    return ("%dd " % d if d else "") + "%dh %02dm" % (h, m)

# Boots 0 (this one) and -1 (previous) from journalctl --list-boots.
boots = {}
try:
    for b in json.loads(e["BOOTS_JSON"] or "[]"):
        boots[int(b["index"])] = b
except (ValueError, KeyError, TypeError):
    pass
prev = boots.get(-1)

if e["PREV_MARK"]:
    verdict = "clean"
    detail = "shutdown marker: " + e["PREV_MARK"]
elif e["PREV_LAST"]:
    verdict = "UNCLEAN (power loss or crash)"
    detail = "no shutdown marker; last entry: " + e["PREV_LAST"]
else:
    verdict = "UNCLEAN (power loss or crash)"
    detail = "no journal for the previous boot (first boot, journal rotated, or not persistent)"

if prev:
    span = "%s -> %s  (up %s)" % (ts(prev["first_entry"]), ts(prev["last_entry"]),
                                  dur((int(prev["last_entry"]) - int(prev["first_entry"])) / 1e6))
else:
    span = "unavailable"

ac = {"1": "online", "0": "OFFLINE (on battery)"}.get(e["AC_ONLINE"], e["AC_ONLINE"])
bat = e["BAT_STATUS"] + ("" if e["BAT_CAP"] == "n/a" else ", %s%%" % e["BAT_CAP"])
link = "%s %s" % (e["UPLINK_IF"], e["LINK_STATE"])
route = e["DEFAULT_ROUTE"] or "none"

lines = [
    "%s booted at %s." % (e["HOST"], e["BOOT_TIME"]),
    "",
    "Previous boot ended:  %s" % verdict,
    "  %s" % detail,
    "Previous boot:        %s" % span,
    "",
    "AC power:             %s" % ac,
    "Battery (BAT1):       %s" % bat,
    "Uplink:               %s; default route: %s" % (link, route),
    "",
    "An unclean end usually means the power was cut for longer than the battery lasted,",
    "or the kernel hung. Check guests came back:  qm list ; pct list",
    "Previous boot's tail:  journalctl -b -1 -n 50",
    "",
    "Sent by hs-boot-report.service (home-server repo: host/hs-boot-report.sh).",
]

msg = EmailMessage()
tag = "" if verdict == "clean" else " after UNCLEAN shutdown"
msg["Subject"] = "[home-server] %s booted%s" % (e["HOST"], tag)
msg["From"] = e.get("MAIL_FROM", "")
msg["To"] = e.get("MAIL_TO", "")
msg.set_content("\n".join(lines))

if e["DRY"] == "1":
    # Headers + decoded body (print(msg) would show the quoted-printable wire form).
    for k in ("Subject", "From", "To"):
        print("%s: %s" % (k, msg[k]))
    print()
    print(msg.get_content(), end="")
    sys.exit(0)

missing = [k for k in ("MAIL_FROM", "MAIL_TO", "SMTP_USER", "SMTP_PASS") if not e.get(k)]
if missing:
    print("boot-report: SMTP not configured (missing %s in /etc/home-server/host-alerts.env)"
          % ", ".join(missing), file=sys.stderr)
    sys.exit(1)

tries, pause = int(e["BOOT_REPORT_TRIES"]), int(e["BOOT_REPORT_RETRY_SEC"])
for n in range(1, tries + 1):
    try:
        with smtplib.SMTP(e["SMTP_HOST"], int(e["SMTP_PORT"]), timeout=30) as s:
            s.ehlo(); s.starttls(context=ssl.create_default_context()); s.ehlo()
            s.login(e["SMTP_USER"], e["SMTP_PASS"])
            s.send_message(msg)
        print("boot-report: emailed MAIL_TO (attempt %d) — previous boot %s" % (n, verdict))
        sys.exit(0)
    except (smtplib.SMTPException, OSError) as exc:
        print("boot-report: attempt %d/%d failed: %s" % (n, tries, exc), file=sys.stderr)
        if n < tries:
            time.sleep(pause)
sys.exit(1)
PY
