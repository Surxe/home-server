#!/usr/bin/env python3
"""hs-availability.py — an availability log for the WRF bot (and later the API), and a
monthly email of how much of the month each was down.

Why: WRFrontiersDB ADR-0006 (G-0006-9) moves the API and bot to a rented server when
home downtime crosses a threshold, and ADR-0024 (G-0024-5) needs that downtime measured
without an outside service. So the host measures it itself:

  sample   (hs-availability.timer, every 5 min) appends one tab-separated line to
           AVAIL_LOG: epoch, ISO time, then uplink / bot / api, each ok | down | n/a.
  report   (hs-availability-report.timer, monthly) reads the log for a month and emails
           hours down, availability and the longest outage per check.

A gap in the log means nothing was running to write it, i.e. the host was off; gaps
longer than AVAIL_GAP_SEC count as down for every check. That is how a power cut or a
dead host shows up, which no email sent from the host could otherwise report.

The checks:
  uplink  HTTPS GET of UPLINK_URL (Discord's public gateway endpoint) answers 200.
  bot     BOT_HEARTBEAT was touched within BOT_MAX_AGE seconds. The bot touches it every
          minute while connected to Discord (its HEARTBEAT_FILE option), so a bot that is
          running but disconnected counts as down. Unset => n/a.
  api     API_URL answers 200. Unset (the API does not exist yet) => n/a.
A check is "n/a" when it is not configured; n/a time is left out of the month's total.

Discord's or Cloudflare's own outages count as ours: users see them the same way.

Credentials for `report` come from /etc/home-server/host-alerts.env via the unit's
EnvironmentFile (SMTP_HOST SMTP_PORT SMTP_USER SMTP_PASS MAIL_FROM MAIL_TO); never here.

Usage:
  host/hs-availability.py sample
  host/hs-availability.py report [--month YYYY-MM] [--dry-run]   # default: last month
"""
import argparse
import os
import smtplib
import ssl
import sys
import time
import urllib.request
from datetime import datetime
from email.message import EmailMessage

e = os.environ
LOG = e.get("AVAIL_LOG", "/var/lib/home-server/availability.log")
GAP = int(e.get("AVAIL_GAP_SEC", "600"))            # longer than this between samples = host off
UPLINK_URL = e.get("UPLINK_URL", "https://discord.com/api/v10/gateway")
BOT_HEARTBEAT = e.get("BOT_HEARTBEAT", "")
BOT_MAX_AGE = int(e.get("BOT_MAX_AGE", "180"))
API_URL = e.get("API_URL", "")
THRESHOLD_H = float(e.get("AVAIL_THRESHOLD_HOURS", "7"))  # G-0006-9: over this, two months running
CHECKS = ("uplink", "bot", "api")


def http_ok(url):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "home-server-availability"})
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status == 200
    except OSError:
        return False


def sample():
    bot = "n/a"
    if BOT_HEARTBEAT:
        try:
            bot = "ok" if time.time() - os.stat(BOT_HEARTBEAT).st_mtime <= BOT_MAX_AGE else "down"
        except OSError:
            bot = "down"
    row = {
        "uplink": "ok" if http_ok(UPLINK_URL) else "down",
        "bot": bot,
        "api": ("ok" if http_ok(API_URL) else "down") if API_URL else "n/a",
    }
    now = time.time()
    line = "\t".join([str(int(now)), datetime.fromtimestamp(now).astimezone().isoformat(timespec="seconds")]
                     + [row[c] for c in CHECKS])
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, "a") as f:
        f.write(line + "\n")


def read_log():
    rows = []
    try:
        with open(LOG) as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) == 2 + len(CHECKS):
                    rows.append((int(parts[0]), dict(zip(CHECKS, parts[2:]))))
    except FileNotFoundError:
        pass
    rows.sort(key=lambda r: r[0])
    return rows


def month_bounds(month):
    start = datetime.strptime(month, "%Y-%m").astimezone()
    end = start.replace(year=start.year + 1, month=1) if start.month == 12 else start.replace(month=start.month + 1)
    return start.timestamp(), end.timestamp()


def spans(rows, ws, we, now):
    """Yield (start, end, states, is_gap) covering [ws, we), from the first sample on.
    Each sample covers up to GAP seconds after it; the rest of a longer gap is a gap,
    yielded with the sample before it (so an unconfigured check stays n/a there)."""
    for i, (t, states) in enumerate(rows):
        nxt = rows[i + 1][0] if i + 1 < len(rows) else min(now, we)
        covered = min(nxt, t + GAP)
        for a, b, is_gap in ((t, covered, False), (covered, nxt, True)):
            a, b = max(a, ws), min(b, we)
            if b > a:
                yield a, b, states, is_gap


def summarise(rows, ws, we, now):
    out = {}
    for c in CHECKS:
        watched = down = gap = 0.0
        outages = []
        for a, b, states, is_gap in spans(rows, ws, we, now):
            if states[c] == "n/a":
                continue
            watched += b - a
            if is_gap or states[c] == "down":
                down += b - a
                gap += (b - a) if is_gap else 0
                if outages and outages[-1][1] >= a:
                    outages[-1][1] = b
                else:
                    outages.append([a, b])
        longest = max(outages, key=lambda o: o[1] - o[0]) if outages else None
        out[c] = {"watched": watched, "down": down, "gap": gap, "longest": longest, "count": len(outages)}
    return out


def fmt_h(sec):
    return "%.1f h" % (sec / 3600)


def fmt_t(ts):
    return datetime.fromtimestamp(ts).astimezone().strftime("%Y-%m-%d %H:%M")


def report(month, dry):
    ws, we = month_bounds(month)
    now = time.time()
    rows = read_log()
    s = summarise(rows, ws, we, now)
    host = os.uname().nodename
    lines = ["Availability for %s, %s to %s, measured on %s." % (month, fmt_t(ws), fmt_t(min(we, now)), host), ""]
    over = []
    for c in CHECKS:
        r = s[c]
        if not r["watched"]:
            lines.append("%-7s not measured" % c)
            continue
        pct = 100 * (1 - r["down"] / r["watched"])
        lines.append("%-7s %6.2f%%  down %s of %s watched, %d outage(s), %s of it with the host off"
                     % (c, pct, fmt_h(r["down"]), fmt_h(r["watched"]), r["count"], fmt_h(r["gap"])))
        if r["longest"]:
            a, b = r["longest"]
            lines.append("        longest outage %s, %s to %s" % (fmt_h(b - a), fmt_t(a), fmt_t(b)))
        if c in ("bot", "api") and r["down"] > THRESHOLD_H * 3600:
            over.append(c)
    lines += [
        "",
        "Threshold (WRFrontiersDB ADR-0006, G-0006-9): move the API and bot to a rented server",
        "after more than %g h down in each of two months running, or any one outage over 24 h." % THRESHOLD_H,
    ]
    if over:
        lines.append("OVER the monthly threshold this month: %s." % ", ".join(over))
    lines += ["", "Log: %s (%d samples in total)." % (LOG, len(rows)),
              "Sent by hs-availability-report.service (home-server repo: host/hs-availability.py)."]

    msg = EmailMessage()
    bot = s["bot"]
    head = ("bot %.2f%%" % (100 * (1 - bot["down"] / bot["watched"]))) if bot["watched"] else "bot not measured"
    msg["Subject"] = "[home-server] availability %s: %s%s" % (month, head, " (OVER threshold)" if over else "")
    msg["From"] = e.get("MAIL_FROM", "")
    msg["To"] = e.get("MAIL_TO", "")
    msg.set_content("\n".join(lines) + "\n")

    if dry:
        for k in ("Subject", "From", "To"):
            print("%s: %s" % (k, msg[k]))
        print()
        print(msg.get_content(), end="")
        return 0
    missing = [k for k in ("MAIL_FROM", "MAIL_TO", "SMTP_USER", "SMTP_PASS") if not e.get(k)]
    if missing:
        print("availability: SMTP not configured (missing %s)" % ", ".join(missing), file=sys.stderr)
        return 1
    with smtplib.SMTP(e.get("SMTP_HOST", "smtp.gmail.com"), int(e.get("SMTP_PORT", "587")), timeout=30) as smtp:
        smtp.ehlo(); smtp.starttls(context=ssl.create_default_context()); smtp.ehlo()
        smtp.login(e["SMTP_USER"], e["SMTP_PASS"])
        smtp.send_message(msg)
    print("availability: emailed MAIL_TO for %s" % month)
    return 0


def last_month():
    first = datetime.now().astimezone().replace(day=1)
    return (first.replace(year=first.year - 1, month=12) if first.month == 1
            else first.replace(month=first.month - 1)).strftime("%Y-%m")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("sample")
    rp = sub.add_parser("report")
    rp.add_argument("--month", default=None, help="YYYY-MM (default: last month)")
    rp.add_argument("--dry-run", action="store_true", help="print the email instead of sending")
    a = ap.parse_args()
    if a.cmd == "sample":
        sample()
        return 0
    return report(a.month or last_month(), a.dry_run)


if __name__ == "__main__":
    sys.exit(main())
