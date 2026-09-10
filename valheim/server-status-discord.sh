#!/usr/bin/env bash
# server-status-discord.sh — post the Valheim server status (up / down + players online,
# WITH NAMES) to a Discord webhook. Driven by systemd/hs-valheim-status.{service,timer}
# hourly as a heartbeat (it posts on EVERY run, not only on change).
#
# Runs on the Proxmox HOST as root and reaches the guest over the QEMU agent (no SSH) —
# the same model as the rest of valheim ops. This crossplay server answers neither an
# external A2S query nor the lloesche STATUS_HTTP endpoint, so both the count and the
# names come from the server's own log (pure parsing, no game query):
#   * count = latest "Connections N ZDOS:.." line (logged ~every 10 min; the post shows
#     its "as of" time so staleness is visible).
#   * names = replay of "Got character ZDOID from <name> : <peerid>:.." (join) minus
#     "Destroying abandoned non persistent zdo <peerid> .. owner <peerid>" (leave), reset
#     whenever a "Connections 0" proves the server was empty.
#
# The webhook URL is a secret and is NOT in the repo. The service pulls it from
#   /etc/home-server/discord-server-status.env   (root:root 0600, see *.env.example)
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

# 2. If the VM is up, one guest-agent round trip for container state + name + the log
#    lines we need to derive player COUNT and NAMES.
server_name = None
container_running = None
players = None
players_asof = None
player_names = []
if vm_state == "running":
    # Fetch: server name, container running-state, then the player-lifecycle log lines.
    #  * join/spawn : "Got character ZDOID from <name> : <peerid>:<n>"  (peerid 0 = death marker)
    #  * leave      : "Destroying abandoned non persistent zdo <peerid>:.. owner <peerid>"
    #  * count      : "Connections <N> ZDOS:.."  (authoritative count; N==0 => server empty)
    guest_cmd = (
        'sn=$(docker inspect -f "{{range .Config.Env}}{{println .}}{{end}}" %s 2>/dev/null '
        '| sed -n "s/^SERVER_NAME=//p"); echo "SERVER_NAME=$sn"; '
        'cs=$(docker inspect -f "{{.State.Running}}" %s 2>/dev/null || echo error); '
        'echo "CONTAINER=$cs"; '
        'docker logs %s 2>&1 | grep -E "Got character ZDOID from |'
        'Destroying abandoned non persistent zdo [0-9]+:[0-9]+ owner [0-9]+|'
        'Connections [0-9]+ ZDOS" | tail -4000'
        % (CONTAINER, CONTAINER, CONTAINER)
    )
    r = run(["qm", "guest", "exec", VMID, "--", "/bin/bash", "-lc", guest_cmd], 90)
    out = ""
    if r and r.returncode == 0:
        try:
            out = json.loads(r.stdout).get("out-data", "") or ""
        except Exception:
            out = ""
    # Replay the lifecycle chronologically. peerids are per-session (change on reconnect),
    # so we reset the tracked set every time the server logs Connections 0 (empty) — that
    # discards stale joins from earlier sessions in the same (long-lived) docker log.
    online = {}          # peerid -> name
    for line in out.splitlines():
        if line.startswith("SERVER_NAME="):
            server_name = line.split("=", 1)[1].strip() or None
            continue
        if line.startswith("CONTAINER="):
            container_running = (line.split("=", 1)[1].strip() == "true")
            continue
        m = re.search(r"Got character ZDOID from (.+?) : (\d+):\d+", line)
        if m and m.group(2) != "0":
            online[m.group(2)] = m.group(1); continue
        m = re.search(r"Destroying abandoned non persistent zdo (\d+):\d+ owner \1\b", line)
        if m:
            online.pop(m.group(1), None); continue
        m = re.search(r"Connections (\d+) ZDOS", line)
        if m:
            players = int(m.group(1))
            t = re.search(r"(\d\d/\d\d/\d{4} \d\d:\d\d:\d\d):\s+Connections", line)
            if t:
                players_asof = t.group(1)
            if players == 0:
                online.clear()
    seen = set()          # de-dup names, preserve first-seen order
    for nm in online.values():
        if nm not in seen:
            seen.add(nm); player_names.append(nm)

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
        players_txt = "? (awaiting first server report)"
    elif players == 0:
        players_txt = "0"
    else:
        if player_names:
            names = ", ".join(player_names)
            # If the count and the derived names disagree, trust the count and flag it.
            if len(player_names) != players:
                names += " (names may be incomplete)"
        else:
            names = "names unavailable"
        players_txt = "%d — %s" % (players, names)
        if players_asof:
            players_txt += "  (as of %s)" % players_asof

title = "Valheim — %s" % (server_name or "server")

if not WEBHOOK:
    print("valheim-status: DISCORD_WEBHOOK_URL not set "
          "(stage /etc/home-server/discord-server-status.env) — would have posted: "
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
