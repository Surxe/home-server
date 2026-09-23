# Memory index — home-server (project: /srv/dev)

Curated, repo-maintained memory for the home-server box. This section is installed from
`home-server/claude/memory/srv-dev/` and covers the HOST layer (Proxmox, wifi, host
backups, the todo hub). The Valheim server has its own section below, installed from the
sibling `valheim-server` repo. One line per memory; read the note you need.

- [Active box](active-box.md) — you're on the home server (Proxmox host); box-local memory = box identity
- [Memories live in this repo](memories-live-in-this-repo.md) — write/edit home-server memories in claude/memory/srv-dev/, then install.sh — never live in ~/.agents
- [Host health check](host-health.md) — run `host/hs-health.sh` for a graded (OK/WARN/CRIT, exit 0/1/2) report of load/mem/temp/thin-pool/uplink/VMs; run as root
- [Cross-box todo](todo-cross-box.md) — this box is the hub + classifier for the shared `todo` store: bare repo, `classify-drain.sh`, the 13:00 timer, and the jq/claude/git-identity deps it needs
