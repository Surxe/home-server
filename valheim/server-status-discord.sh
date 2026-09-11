#!/usr/bin/env bash
# server-status-discord.sh — post Valheim server status (up/down + players, WITH NAMES)
# to a Discord webhook. Two modes:
#
#   --edge       (frequent poll, every few min via hs-valheim-status-edge.timer)
#                Post ONLY when the up/down state CHANGES vs the last recorded state —
#                i.e. the server just started or just stopped. Quiet otherwise. This is
#                the "someone ran start/stop" notifier; it does NOT depend on who cycled
#                the server (Claude, cron, the mod PRE_SERVER_RUN_HOOK, or Ethan by hand)
#                because it watches the server's actual state, not a command.
#   --heartbeat  (default; daily via hs-valheim-status.timer)
#                Post the current status unconditionally — a liveness "yes, still here"
#                that also re-baselines the edge state.
#
# WHY edge instead of a Claude Code hook: a Claude hook only fires for a start/stop typed
# in a Claude session, fires the instant the command returns (before the ~40-60s the
# server needs to be healthy), and can't see restarts done by cron/systemd/the auto-update
# hook. Watching real state here covers every case and only announces UP once it's truly up.
# See the `valheim-status-edge-notifier` memory.
#
# Runs on the Proxmox HOST as root, reaching the guest over the QEMU agent (no SSH). This
# crossplay server answers neither an external A2S query nor the lloesche STATUS_HTTP
# endpoint, so count + names come from the server's own log (pure parsing):
#   * count = latest "Connections N ZDOS:.." line (logged ~every 10 min; the post shows
#     its "as of" time so staleness is visible).
#   * names = replay of "Got character ZDOID from <name> : <peerid>:.." (join) minus
#     "Destroying abandoned non persistent zdo <peerid> .. owner <peerid>" (leave), reset
#     whenever a "Connections 0" proves the server was empty.
# Edge polls do a CHEAP probe first (qm status + one `docker inspect`, no log parse) and
# only do the expensive name-gather when they're actually about to post, so polling every
# few minutes stays light on the guest agent.
#
# The webhook URL is a secret, NOT in the repo. The services pull it from
#   /etc/home-server/discord-server-status.env   (root:root 0600, see *.env.example)
# via EnvironmentFile:
#   DISCORD_WEBHOOK_URL              (required to post)
#   VALHEIM_VMID (default 100)   VALHEIM_CONTAINER (default valheim)   [optional overrides]
#   VALHEIM_STATUS_STATE_FILE (default /var/lib/home-server/valheim-status.state)
#
# Exit codes: 0 = ok (posted, skipped-no-change, initialized baseline, or webhook
#             unconfigured -> logged and skipped);   1 = the webhook POST itself failed.
set -euo pipefail

: "${VALHEIM_VMID:=100}"
: "${VALHEIM_CONTAINER:=valheim}"
: "${VALHEIM_STATUS_STATE_FILE:=/var/lib/home-server/valheim-status.state}"

MODE=heartbeat
case "${1:-}" in
  --edge)              MODE=edge ;;
  --heartbeat|""|-h)   MODE=heartbeat ;;
  *) echo "server-status-discord.sh: unknown arg: $1 (use --edge or --heartbeat)" >&2; exit 2 ;;
esac

export VALHEIM_VMID VALHEIM_CONTAINER VALHEIM_STATUS_STATE_FILE
export VALHEIM_STATUS_MODE="$MODE"

python3 - <<'PY'
import os, re, json, subprocess, urllib.request, urllib.error

VMID       = os.environ.get("VALHEIM_VMID", "100")
CONTAINER  = os.environ.get("VALHEIM_CONTAINER", "valheim")
WEBHOOK    = os.environ.get("DISCORD_WEBHOOK_URL")
MODE       = os.environ.get("VALHEIM_STATUS_MODE", "heartbeat")
STATE_FILE = os.environ.get("VALHEIM_STATUS_STATE_FILE",
                            "/var/lib/home-server/valheim-status.state")

def run(cmd, timeout):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None

def guest_out(cmd, timeout):
    """Run a shell command inside the guest via the QEMU agent; return its stdout ('' on fail)."""
    r = run(["qm", "guest", "exec", VMID, "--", "/bin/bash", "-lc", cmd], timeout)
    if r and r.returncode == 0:
        try:
            return json.loads(r.stdout).get("out-data", "") or ""
        except Exception:
            return ""
    return ""

# --- cheap probe: coarse up/down/unknown WITHOUT the expensive log parse ----------------
def cheap_state():
    """Return one of 'up' | 'down' | 'unknown' using only quick calls."""
    r = run(["qm", "status", VMID], 30)
    vm_state = "unknown"
    if r and r.returncode == 0:
        parts = r.stdout.split()          # "status: running"
        if len(parts) >= 2:
            vm_state = parts[1].strip()
    if vm_state != "running":
        # A confidently-off VM (stopped/paused/…) is DOWN; a failed qm call is unknown.
        return "down" if vm_state != "unknown" else "unknown"
    cs = guest_out('docker inspect -f "{{.State.Running}}" %s 2>/dev/null || echo error'
                   % CONTAINER, 30).strip()
    if cs == "true":
        return "up"
    if cs == "false":
        return "down"
    return "unknown"                       # guest agent didn't answer / docker error

def read_last():
    try:
        with open(STATE_FILE) as f:
            return f.read().strip() or None
    except Exception:
        return None

def write_state(s):
    try:
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        with open(STATE_FILE, "w") as f:
            f.write(s + "\n")
    except Exception as e:
        print("valheim-status: WARN could not write state file %s: %s" % (STATE_FILE, e))

# --- full status (expensive: player count + NAMES from the log) -------------------------
def full_status():
    """Return (headline, color, detail, players_txt, state_key, server_name)."""
    r = run(["qm", "status", VMID], 30)
    vm_state = "unknown"
    if r and r.returncode == 0:
        parts = r.stdout.split()
        if len(parts) >= 2:
            vm_state = parts[1].strip()

    server_name = None
    container_running = None
    players = None
    players_asof = None
    player_names = []
    if vm_state == "running":
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
        out = guest_out(guest_cmd, 90)
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
        seen = set()
        for nm in online.values():
            if nm not in seen:
                seen.add(nm); player_names.append(nm)

    if vm_state != "running":
        headline, color = "\U0001F534 DOWN", 0xE74C3C          # red
        detail = "VM %s is %s" % (VMID, vm_state)
        players_txt, state_key = "\u2014", "down"
    elif container_running is False:
        headline, color = "\U0001F534 DOWN", 0xE74C3C
        detail = "VM up, but the `%s` container is not running" % CONTAINER
        players_txt, state_key = "\u2014", "down"
    elif container_running is None:
        headline, color = "\U0001F7E0 UNKNOWN", 0xF39C12       # orange
        detail = "VM up, but the guest agent did not answer"
        players_txt, state_key = "?", "unknown"
    else:
        headline, color = "\U0001F7E2 UP", 0x2ECC71            # green
        detail = "VM + container running"
        state_key = "up"
        if players is None:
            players_txt = "? (awaiting first server report)"
        elif players == 0:
            players_txt = "0"
        else:
            if player_names:
                names = ", ".join(player_names)
                if len(player_names) != players:
                    names += " (names may be incomplete)"
            else:
                names = "names unavailable"
            players_txt = "%d — %s" % (players, names)
            if players_asof:
                players_txt += "  (as of %s)" % players_asof

    return headline, color, detail, players_txt, state_key, server_name

def post(headline, color, detail, players_txt, server_name, tag):
    title = "Valheim — %s" % (server_name or "server")
    if not WEBHOOK:
        print("valheim-status[%s]: DISCORD_WEBHOOK_URL not set "
              "(stage /etc/home-server/discord-server-status.env) — would have posted: "
              "%s | players=%s | %s" % (tag, headline, players_txt, detail))
        return 0
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
                 "User-Agent": "home-server-valheim-status/1.1"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            resp.read()
    except urllib.error.HTTPError as e:
        body = e.read()[:200].decode("utf-8", "replace")
        print("valheim-status[%s]: webhook POST failed: HTTP %s %s" % (tag, e.code, body))
        return 1
    except Exception as e:
        print("valheim-status[%s]: webhook POST failed: %s" % (tag, e))
        return 1
    print("valheim-status[%s]: posted -> %s | players=%s" % (tag, headline, players_txt))
    return 0

# --- decide, per mode -------------------------------------------------------------------
if MODE == "edge":
    state = cheap_state()
    last  = read_last()
    if state == "unknown":
        # Don't flap on a transient agent hiccup: no post, keep the last-known baseline.
        print("valheim-status[edge]: state unknown (agent didn't answer) — no post "
              "(last known: %s)" % (last or "none"))
        raise SystemExit(0)
    if last is None:
        # First run / lost state: adopt current as baseline silently, don't announce.
        write_state(state)
        print("valheim-status[edge]: initialized baseline to '%s' (no post)" % state)
        raise SystemExit(0)
    if state == last:
        print("valheim-status[edge]: no change (%s) — no post" % state)
        raise SystemExit(0)
    # Real transition -> gather full detail and announce.
    headline, color, detail, players_txt, state_key, server_name = full_status()
    # Trust the cheap edge read for the transition; if the full pass now reads 'unknown'
    # (agent went busy in the gap) fall back to a minimal announce of the cheap state.
    rc = post(headline, color, detail, players_txt, server_name, "edge")
    if rc == 0:
        write_state(state if state_key == "unknown" else state_key)
    raise SystemExit(rc)

# heartbeat (default): always post; re-baseline edge state when confident.
headline, color, detail, players_txt, state_key, server_name = full_status()
rc = post(headline, color, detail, players_txt, server_name, "heartbeat")
if rc == 0 and state_key in ("up", "down"):
    write_state(state_key)
raise SystemExit(rc)
PY
