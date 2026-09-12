# lib-gx.sh — shared helpers for driving the Valheim VM (VM 100) over the QEMU guest agent.
# SOURCE this (don't execute). Runs on the Proxmox HOST and needs root — `qm` is root-only,
# so source it from a script you run with sudo. No SSH into the guest.
#
#   gx <cmd...>          run a command in the guest; prints its stdout+stderr, returns the
#                        GUEST's exit code (127 if the agent call itself failed)
#   gx_push <src> <dst>  copy a host file into the guest at <dst> (base64 over the agent)
#   gx_ready [tries] [to]  is the agent actually answering? (trivial exec, NOT `qm agent ping`)
#
# Env: VMID (default 100), GX_TIMEOUT seconds (default 60) — both overridable per call, e.g.
#   GX_TIMEOUT=180 gx bash -lc 'cd /srv/valheim && ./stage-mods.sh'
VMID="${VMID:-100}"

# gx_ready [tries=3] [timeout=15] — liveness probe. Fires a trivial `/bin/true` exec and checks
# the agent actually ran it. Do NOT use `qm agent ping` for this: on VM 100 ping false-negatives
# (reports "not running" while `qm guest exec` works). Gate any heavy read on this so we never
# fire an expensive exec at a busy/wedged agent (which can wedge it harder). Returns 0 if alive.
gx_ready() {
  local tries="${1:-3}" to="${2:-15}" i
  for ((i = 1; i <= tries; i++)); do
    qm guest exec "$VMID" --timeout "$to" -- /bin/true >/dev/null 2>&1 && return 0
    [ "$i" -lt "$tries" ] && sleep 8
  done
  return 1
}

gx() {
  local out
  out="$(qm guest exec "$VMID" --timeout "${GX_TIMEOUT:-60}" -- "$@")" || return 127
  python3 - "$out" <<'PY'
import sys, json
d = json.loads(sys.argv[1])
sys.stdout.write(d.get("out-data", "")); sys.stderr.write(d.get("err-data", ""))
sys.exit(int(d.get("exitcode", 0) or 0))
PY
}

gx_push() {  # gx_push <hostfile> <vmpath>
  local b64; b64="$(base64 -w0 "$1")"
  gx bash -c "install -d \"\$(dirname '$2')\"; echo '$b64' | base64 -d > '$2'" >/dev/null \
    && echo "pushed $2"
}
