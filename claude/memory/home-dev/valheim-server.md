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

**State (2026-09): on Valheim 1.0 (l-1.0.7, Unity 6).** Server runs **ModSentry 1.0.17 +
DropThat 3.1.5 + Jotunn 2.30.0** (Jotunn/DropThat updated to their 1.0 builds; Jotunn 2.30.0
no longer crashes on connect). Still disabled until they ship 1.0 builds: **GlassPieces**
(client TypeLoadException), **Huginn Map + FarmGrid** (need Jotunn but not rebuilt). A daily
systemd job `hs-mod-check` emails Ethan when a disabled mod updates. Difficulty is
vanilla/Normal, no world modifiers.

**Gotchas:** VM is **4 cores** (was 3) — the extra core is headroom so a mod that pegs the
game threads can't starve the guest agent (that locked it out on 2026-09-10; recover by
`qm stop`/`qm set --cores`/`qm start`, then stop the container during boot). Do NOT leave
DropThat `WriteDropTablesToFiles` enabled — it pegs the server on world start (use it briefly
to dump prefab ids, then off). Full detail: [[valheim-1.0-mod-status]], [[valheim-server-ops]].
Snapshot before mod/game changes (`qm snapshot 100 ...`).
