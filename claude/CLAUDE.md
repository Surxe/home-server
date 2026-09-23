# home-server — operating context for AI assistants

This machine is a **headless Proxmox host** (an old laptop): the **home-server**. It
exists to run **server-like systems** — game servers, background services, anything
meant to be always-on — **off of Ethan's home PC** and onto dedicated, disposable
infrastructure. Ethan's workstation itself is documented separately in the
**`my-system`** repo (config-as-code for his dual-boot desktop); this box follows the
same "the machine is a scripted rebuild, not a weekend" philosophy for the server side.

- **This repo** (`/srv/dev/repos/home-server`) is the source of truth for the HOST:
  Proxmox/host config, wifi, host backups, the generic VM-create mechanism, and the
  cross-box `todo` hub. Config-as-code, symlink / copy into live paths. Secrets never
  live here — only their locations under `/etc/`.
- **`valheim-server`** (`/srv/dev/repos/valheim-server`, a sibling clone) owns the whole
  **Valheim server** subsystem now — its Docker/mod config, VM provisioning, the systemd
  feeds that watch it, world backups, docs, and its own agent skills + memory. This box's
  `install.sh` runs valheim-server's installer as a final step. Edit Valheim things there.
- **`my-system`** can be cloned at `/srv/dev/repos/my-system` as a **read-only
  reference** for conventions (installer layout, the `install` skill, CLAUDE/memory/skill
  structure). Do not modify it from here.

## The box, briefly
- Proxmox host; uplink is **wifi** (`home-server-wifi.service`), internal NAT bridge
  `vmbr0` for guests. You manage it from **`/home/dev`** as root via `sudo`.
- Guests run in VMs. **Valheim = VM 100** (its config/tooling lives in the
  `valheim-server` repo). No SSH into guests — drive them with
  `sudo qm guest exec 100 -- ...` (QEMU guest agent) → `docker ...` inside.
- Deep, current per-topic detail lives in **memory** (see the memory index) and in
  `docs/` (host runbook; the Valheim VM runbook is in the valheim-server repo).

## How work is organized (why this file exists)
The goal is **small, focused sessions** instead of one giant one. So:
- **This file** (global, always loaded as `~/.agents/AGENTS.md`, symlinked to
  `~/.claude/CLAUDE.md` and `~/.dsh/AGENTS.md`) is the top-level orientation for
  both Claude Code and the DeepSeek Harness on this box.
- **Memory** carries per-subsystem state — start by reading the memory index at
  `~/.agents/memory/MEMORY.md` (symlinked to `~/.claude/projects/-srv-dev/memory/`),
  then load only the note you need. The DeepSeek Harness reads the same notes from
  `~/.dsh/memory/` via the `memory-standard` plugin.
- **Skills** encode repeatable procedures, shared from `~/.agents/skills/`. Notably
  **`home-server-install`**: run it whenever you edit host-repo code that `install.sh`
  deploys. (Valheim work has its own skills — `add-valheim-mod`, `restart-valheim`,
  `valheim-server-install`, … — installed from the valheim-server repo.)

## Working rules
- **After editing anything `install.sh` deploys, install it and verify it** — follow the
  `home-server-install` skill. If you tested it yourself and it passed, Ethan's review is
  not required; if you couldn't test it, say so and leave it for him.
- No secrets in the repo. Don't touch SSH keys, passwords, SMTP/API tokens, backup creds.
- Prefer simple, Debian/Proxmox-native, idempotent solutions; understand before changing.
- Commit/push when asked; branch off `main` for changes.
