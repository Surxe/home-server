---
name: valheim-server
description: The modded Valheim dedicated server — where it runs, how to drive it, current state
metadata:
  type: project
---

Modded Valheim dedicated server "**BaldurianQuat**", hosted on this box in **Proxmox VM 100**
as a Docker container (`lloesche/valheim-server`, container name `valheim`). Crossplay-only
(PlayFab relay, no port forwarding); friends join by code + password.

**Operate it from `/home/dev` (no SSH to the guest):**
`sudo qm guest exec 100 -- /bin/bash -lc 'docker ... '` (guest agent runs as root; JSON out —
pipe through python3 for `out-data`). World + config bind-mounted at `/srv/valheim/config`
(precious) on the VM host; game install at `/srv/valheim/data` (throwaway).

**Repo:** `/srv/dev/repos/home-server/valheim/` — `docker-compose.yml`, `mods.manifest`,
`stage-mods.sh` (deploy mods to the VM), `check-mod-updates.sh` (poll Thunderstore),
`hooks/sync-plugins.sh` (PRE_SERVER_RUN_HOOK so auto-updates keep mods loaded).

**State (2026-09): on Valheim 1.0 (l-1.0.7, Unity 6).** The old mods broke on 1.0, so the
server runs a reduced set (ModSentry + DropThat); the Jotunn stack (Jotunn/Huginn/FarmGrid)
is disabled pending 1.0 rebuilds — **Jotunn 2.30.0 + DropThat 3.1.5 shipped and are the
re-enable signal** (a daily systemd job, `hs-mod-check`, emails Ethan when such updates land).
Difficulty is vanilla/Normal, no world modifiers. Full detail: [[valheim-1.0-mod-status]],
[[valheim-server-ops]]. Snapshot before mod/game changes (`qm snapshot 100 ...`).
