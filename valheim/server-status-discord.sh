#!/usr/bin/env bash
# server-status-discord.sh — post the Valheim server status (up / down + players online)
# to a Discord webhook. Driven by systemd/hs-valheim-status.{service,timer} every 30 min
# as a heartbeat (it posts on EVERY run, not only on change).
#
# Runs on the Proxmox HOST as root and reaches the guest over the QEMU agent (no SSH) —
# the same model as the rest of valheim ops. Player count comes from the server's own
# periodic "Connections N ZDOS:..." log line: this crossplay server answers neither an
# external A2S query nor the lloesche STATUS_HTTP endpoint, but it logs that line about
# every ~10 min, so a 30-min heartbeat reads a value at most ~10 min stale (the post
# shows the "as of" time so staleness is visible).
#
# The webhook URL is a secret and is NOT in the repo. The service pulls it from
#   /etc/home-server/valheim-status.env   (root:root 0600, see *.env.example)
# via EnvironmentFile, so it arrives here as an env var:
#   DISCORD_WEBHOOK_URL          (required to post)
#   VALHEIM_VMID (default 100)   VALHEIM_CONTAINER (default valheim)   [optional overrides]
#
# Exit codes: 0 = ok (posted, or webhook unconfigured -> logged and skipped);
#             1 = the webhook POST itself failed.
set -euo pipefail

: "${VALHEIM_VMID:=100}"
: "${VALHEIM_CONTAINER:=valheim}"
export VALHEIM_VMID VALHEIM_CONTAINER

python3 - <<'PY'
import os, re, json, subprocess, urllib.request, urllib.error

VMID      = os.environ.get("VALHEIM_VMID", "100")
CONTAINER = os.environ.get("VALHEIM_CONTAINER", "valheim")
WEBHOOK   = os.environ.get("DISCORD_WEBHOOK_URL")

def run(cmd, timeout):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None

# 1. VM state (host-side, cheap).
vm_state = "unknown"
r = run(["qm", "status", VMID], 30)
if r and r.returncode == 0:
    parts = r.stdout.split()          # "status: running"
    if len(parts) >= 2:
        vm_state = parts[1].strip()

# 2. If the VM is up, one guest-agent round trip for container state + name + players.
server_name = None
container_running = None
players = None
players_asof = None
if vm_state == "running":
    guest_cmd = (
        'sn=$(docker inspect -f "{{range .Config.Env}}{{println .}}{{end}}" %s 2>/dev/null '
        '| sed -n "s/^SERVER_NAME=//p"); echo "SERVER_NAME=$sn"; '
        'cs=$(docker inspect -f "{{.State.Running}}" %s 2>/dev/null || echo error); '
        'echo "CONTAINER=$cs"; '
        'docker logs --tail 5000 %s 2>&1 | grep -E "Connections [0-9]+ ZDOS" | tail -1'
        % (CONTAINER, CONTAINER, CONTAINER)
    )
    r = run(["qm", "guest", "exec", VMID, "--", "/bin/bash", "-lc", guest_cmd], 90)
    out = ""
    if r and r.returncode == 0:
        try:
            out = json.loads(r.stdout).get("out-data", "") or ""
        except Exception:
            out = ""
    for line in out.splitlines():
        if line.startswith("SERVER_NAME="):
            server_name = line.split("=", 1)[1].strip() or None
        elif line.startswith("CONTAINER="):
            container_running = (line.split("=", 1)[1].strip() == "true")
        m = re.search(r"Connections (\d+)", line)
        if m:
            players = int(m.group(1))
            t = re.search(r"(\d\d/\d\d/\d{4} \d\d:\d\d:\d\d):\s+Connections", line)
            if t:
                players_asof = t.group(1)

# 3. Reduce to one status.
if vm_state != "running":
    headline, color = "\U0001F534 DOWN", 0xE74C3C          # red
    detail = "VM %s is %s" % (VMID, vm_state)
    players_txt = "\u2014"
elif container_running is False:
    headline, color = "\U0001F534 DOWN", 0xE74C3C
    detail = "VM up, but the `%s` container is not running" % CONTAINER
    players_txt = "\u2014"
elif container_running is None:
    headline, color = "\U0001F7E0 UNKNOWN", 0xF39C12       # orange
    detail = "VM up, but the guest agent did not answer"
    players_txt = "?"
else:
    headline, color = "\U0001F7E2 UP", 0x2ECC71            # green
    detail = "VM + container running"
    if players is None:
        players_txt = "? (no report yet — server logs count ~every 10 min)"
    else:
        players_txt = str(players) + (" (as of %s)" % players_asof if players_asof else "")

title = "Valheim — %s" % (server_name or "server")

if not WEBHOOK:
    print("valheim-status: DISCORD_WEBHOOK_URL not set "
          "(stage /etc/home-server/valheim-status.env) — would have posted: "
          "%s | players=%s | %s" % (headline, players_txt, detail))
    raise SystemExit(0)

payload = {
    "username": "home-server",
    "embeds": [{
        "title": title,
        "color": color,
        "fields": [
            {"name": "Status",         "value": "%s — %s" % (headline, detail), "inline": False},
            {"name": "Players online", "value": players_txt,                    "inline": True},
        ],
    }],
}
req = urllib.request.Request(
    WEBHOOK, data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json",
             "User-Agent": "home-server-valheim-status/1.0"})
try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        resp.read()
except urllib.error.HTTPError as e:
    body = e.read()[:200].decode("utf-8", "replace")
    print("valheim-status: webhook POST failed: HTTP %s %s" % (e.code, body))
    raise SystemExit(1)
except Exception as e:
    print("valheim-status: webhook POST failed: %s" % e)
    raise SystemExit(1)

print("valheim-status: posted -> %s | players=%s" % (headline, players_txt))
PY
