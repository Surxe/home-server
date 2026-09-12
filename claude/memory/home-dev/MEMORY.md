# Memory index — home-server (project: /home/dev)

Curated, repo-maintained memory for the home-server box, installed from
`home-server/claude/memory/home-dev/`. One line per memory; read the note you need.
(More memories to come — networking, backups, host/Proxmox — as they're written.)

- [Valheim server](valheim-server.md) — modded Valheim dedicated server (VM 100); drive via `qm guest exec`; on 1.0 with a reduced mod set
- [DropThat prefab dump](dropthat-prefab-dump.md) — how to dump prefab/drop-table ids safely (enable → generate → STOP, or it hogs the VM)
- [Memories live in this repo](memories-live-in-this-repo.md) — write/edit home-server memories in claude/memory/home-dev/, then install.sh — never live in ~/.claude
- [Mod update: halt before docs](mod-update-halt-before-docs.md) — adding/updating mods: after server is up + verified, stop for Ethan's OK before docs or client mod docs
- [Valheim mod inventory](valheim-mod-inventory.md) — list installed mods (required/optional + version): `valheim/list-installed-mods.sh`; the 4 Discord feeds incl. `hs-mod-announce` (agent-triggered mod-change diff via the announce-valheim-mods skill)
- [Valheim add-mod tooling](valheim-add-mod.md) — add/bump/remove a mod: the `/add-valheim-mod` skill + its scripts (`mod-fetch.sh`, `verify-boot.sh`, `lib-gx.sh`)
- [Valheim status edge notifier](valheim-status-edge-notifier.md) — up/down Discord posts are EDGE-triggered on start/stop (3-min probe) + daily heartbeat; why it's not a Claude hook
- [Host health check](host-health.md) — run `host/hs-health.sh` for a graded (OK/WARN/CRIT, exit 0/1/2) report of load/mem/temp/thin-pool/uplink/VMs; run as root
- [Read logs targeted](read-logs-targeted.md) — always read logs in slices (tail/grep), never the whole file (a full read can hang the VM 100 agent)
- [Valheim VM agent](valheim-vm-agent.md) — check the VM 100 guest agent with a real exec (ping false-negatives); wait out world-load, don't retry-hammer, reboot last
- [Cross-box todo](todo-cross-box.md) — this box is the hub + classifier for the shared `todo` store: bare repo, `classify-drain.sh`, the 13:00 timer, and the jq/claude/git-identity deps it needs
