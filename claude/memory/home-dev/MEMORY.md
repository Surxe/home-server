# Memory index — home-server (project: /home/dev)

Curated, repo-maintained memory for the home-server box, installed from
`home-server/claude/memory/home-dev/`. One line per memory; read the note you need.
(More memories to come — networking, backups, host/Proxmox — as they're written.)

- [Valheim server](valheim-server.md) — modded Valheim dedicated server (VM 100); drive via `qm guest exec`; on 1.0 with a reduced mod set
- [DropThat prefab dump](dropthat-prefab-dump.md) — how to dump prefab/drop-table ids safely (enable → generate → STOP, or it hogs the VM)
- [Valheim mod inventory](valheim-mod-inventory.md) — list installed mods (required/optional + version): `valheim/list-installed-mods.sh`; the 4 Discord feeds incl. `hs-mod-announce` (agent-triggered mod-change diff via the announce-valheim-mods skill)
- [Valheim status edge notifier](valheim-status-edge-notifier.md) — up/down Discord posts are EDGE-triggered on start/stop (3-min probe) + daily heartbeat; why it's not a Claude hook
- [Host health check](host-health.md) — run `host/hs-health.sh` for a graded (OK/WARN/CRIT, exit 0/1/2) report of load/mem/temp/thin-pool/uplink/VMs; run as root
