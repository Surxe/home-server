# home-server — operating context for AI assistants

This machine is a **headless Proxmox host** (an old laptop): the **home-server**. It
exists to run **server-like systems** — game servers, background services, anything
meant to be always-on — **off of Ethan's home PC** and onto dedicated, disposable
infrastructure. Ethan's workstation itself is documented separately in the
**`my-system`** repo (config-as-code for his dual-boot desktop); this box follows the
same "the machine is a scripted rebuild, not a weekend" philosophy for the server side.

- **This repo** (`/srv/dev/repos/home-server`) is the source of truth: host config,
  systemd units, backups, guest VMs, and the Valheim server. Config-as-code, symlink /
  copy into live paths. Secrets never live here — only their locations under `/etc/`.
- **`my-system`** can be cloned at `/srv/dev/repos/my-system` as a **read-only
  reference** for conventions (installer layout, the `install` skill, CLAUDE/memory/skill
  structure). Do not modify it from here.

## The box, briefly
- Proxmox host; uplink is **wifi** (`home-server-wifi.service`), internal NAT bridge
  `vmbr0` for guests. You manage it from **`/home/dev`** as root via `sudo`.
- Guests run in VMs. **Valheim = VM 100.** No SSH into guests — drive them with
  `sudo qm guest exec 100 -- ...` (QEMU guest agent) → `docker ...` inside.
- Deep, current per-topic detail lives in **memory** (see the memory index) and in
  `docs/` (`00`–`07` runbook).

## How work is organized (why this file exists)
The goal is **small, focused Claude sessions** instead of one giant one. So:
- **This CLAUDE.md** (global, always loaded) is the top-level orientation.
- **Memory** carries per-subsystem state — start by reading the memory index at
  `~/.claude/projects/-home-dev/memory/MEMORY.md`, then load only the note you need.
- **Skills** encode repeatable procedures. Notably **`home-server-install`**: run it
  whenever you edit repo code that `install.sh` deploys.

## Working rules
- **After editing anything `install.sh` deploys, install it and verify it** — follow the
  `home-server-install` skill. If you tested it yourself and it passed, Ethan's review is
  not required; if you couldn't test it, say so and leave it for him.
- No secrets in the repo. Don't touch SSH keys, passwords, SMTP/API tokens, backup creds.
- Prefer simple, Debian/Proxmox-native, idempotent solutions; understand before changing.
- Commit/push when asked; branch off `main` for changes.
