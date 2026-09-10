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

**State (2026-09): on Valheim 1.0 (l-1.0.7, Unity 6).** Server plugins: **ModSentry 1.0.17 +
DropThat 3.1.5 + Jotunn 2.30.0 + BetterCarts 1.1.0** (Jotunn/DropThat on their 1.0 builds;
Jotunn 2.30.0 no longer crashes on connect). **BetterCarts** (TastyChickenLegs; quick
attach/detach, 4-player push, tunable cart weight/damage) added 2026-09-10 as `plugin+required`
— last Thunderstore release 1.1.0 is pre-1.0 (2025-11-15) but tested to load CLEAN on 1.0
(Harmony patches bind, its server ConfigSync RPC registers); deps only BepInEx, not Jotunn.
**FarmGrid 1.0.0 re-enabled** as a client-side **optional** mod (ModSentry_Optional) — verified
2026-09-10 to load clean under Jotunn 2.30.0 (Jotunn was its only blocker; no new FarmGrid
version needed). Still **disabled** (both tested 2026-09-10 on
their current versions and NOT ok — need a real 1.0 rebuild, not just Jotunn):
**GlassPieces 1.2.5** (still TypeLoadException/VTable on 1.0; depends only on BepInEx so Jotunn
never applied) and **Huginn Map 1.0.5** (now *loads* under Jotunn but its own map-share
`Minimap.ReadExploredArray` + boat `ZoneSystem.m_activeArea` calls hit 1.0-removed game APIs, so
its headline features are broken). A daily systemd job `hs-mod-check` emails Ethan when a
disabled mod updates. Difficulty is vanilla/Normal, no world modifiers.

**"Will a disabled mod work now that its dep updated?" test recipe:** stage it as a `plugin`
(server-side) in a scratch manifest, restart, and read `BepInEx/LogOutput.log` for the LATEST
boot (log is appended across restarts — anchor on the last `Chainloader started`). A
`TypeLoadException`/"could not be instantiated" at load = hard break (needs rebuild); a clean
`Loading [..]` with no errors = loads; `Method/Field not found` warnings = it loads but uses
game APIs 1.0 changed (functionally broken). Then restore + apply via `guests/vm-apply-valheim.sh`.

**Gotchas:** VM is **4 cores** (was 3) — the extra core is headroom so a mod that pegs the
game threads can't starve the guest agent (that locked it out on 2026-09-10; recover by
`qm stop`/`qm set --cores`/`qm start`, then stop the container during boot). Do NOT leave
DropThat `WriteDropTablesToFiles` enabled — it pegs the server on world start (use it briefly
to dump prefab ids, then off). Full detail: [[valheim-1.0-mod-status]], [[valheim-server-ops]].
Snapshot before mod/game changes (`qm snapshot 100 ...`).
