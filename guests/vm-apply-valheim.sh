#!/bin/bash
# vm-apply-valheim.sh — deploy this repo's Valheim config INTO the Valheim VM and apply it.
# Run on the Proxmox HOST. Uses the QEMU guest agent (no SSH into the VM needed).
#
#   1. push valheim/{docker-compose.yml,mods.manifest,stage-mods.sh,drop_that.drop_table.cfg}
#      into the VM at /srv/valheim/
#   2. run stage-mods.sh in the VM (verifies DLL hashes, lays plugins + ModSentry policy,
#      mirrors the runtime plugin cache) — DLLs are downloaded+verified in the VM if absent
#   3. docker compose restart (BepInEx reloads; the crossplay join code rotates)
#
# Does NOT manage secrets/values: /etc/valheim/valheim.env is set by hand on the VM.
set -euo pipefail
VMID="${VMID:-100}"
VDIR="$(cd "$(dirname "$0")/../valheim" && pwd)"

# run a command in the guest, print its stdout, return the GUEST's exit code
gx() {
  local out; out="$(qm guest exec "$VMID" --timeout "${GX_TIMEOUT:-60}" -- "$@")" || return 127
  python3 - "$out" <<'PY'
import sys,json
d=json.loads(sys.argv[1]); sys.stdout.write(d.get("out-data","")); sys.stderr.write(d.get("err-data",""))
sys.exit(int(d.get("exitcode",0) or 0))
PY
}
push() {  # push <hostfile> <vmpath>
  local b64; b64="$(base64 -w0 "$1")"
  gx bash -c "install -d \"\$(dirname '$2')\"; echo '$b64' | base64 -d > '$2'" >/dev/null && echo "pushed $2"
}

qm agent "$VMID" ping >/dev/null 2>&1 || { echo "FATAL: VM $VMID guest agent not responding"; exit 1; }

for f in docker-compose.yml mods.manifest stage-mods.sh drop_that.drop_table.cfg; do
  push "$VDIR/$f" "/srv/valheim/$f"
done
gx bash -c "chmod +x /srv/valheim/stage-mods.sh" >/dev/null

echo "== staging mods in VM =="
GX_TIMEOUT=180 gx bash -lc "cd /srv/valheim && ./stage-mods.sh"

echo "== restarting container =="
GX_TIMEOUT=120 gx bash -lc "cd /srv/valheim && docker compose restart"
echo "done. watch: qm guest exec $VMID -- bash -lc \"docker logs --tail 40 valheim | grep -aE 'Loading \\[|join code'\""
