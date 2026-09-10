---
name: home-server-install
description: >-
  Use this WHENEVER you edit code in the home-server repo that install.sh deploys —
  systemd units under systemd/, the Claude context under claude/ (CLAUDE.md, memory,
  skills), or anything a sub-installer copies/symlinks. It enforces the rule: an edit
  isn't done until it's installed live AND verified. If you tested it yourself and it
  passed, Ethan's review is not required; if you couldn't test it, say so and leave it
  for him. Trigger on any such edit, before you report the change as complete.
---

# Apply-and-verify home-server changes

The home-server box is config-as-code: editing a repo file is only half the job — the
**live system must be updated to match, and the change must be verified.** This skill is
the checklist for closing that loop after you edit anything `install.sh` deploys.

## When this applies

Any edit under the home-server repo to code with a deploy step, i.e. anything
`install.sh` (via its sub-installers) puts onto the box:

- `systemd/*.service` / `*.timer` — symlinked into `/etc/systemd/system`; systemd needs a
  daemon-reload (and often a restart) to pick up changes.
- `claude/CLAUDE.md`, `claude/skills/**`, `claude/memory/**` — **copied** to `~/.claude`,
  so a repo edit does NOT reach the live area until you re-install.
- Scripts a unit runs in place (e.g. `valheim/notify-mod-updates.sh`,
  `valheim/check-mod-updates.sh`, `host/hs-wifi-up.sh`) — live immediately from the repo
  path, but still must be **tested**.

If the edit is to VM-side Valheim assets instead (`docker-compose.yml`, `mods.manifest`,
`hooks/sync-plugins.sh`) those deploy to the guest via `stage-mods.sh` / the container, not
`install.sh` — the same apply-and-verify discipline holds; just use that deploy path.

## The loop — do all four

1. **Edit** the repo file.
2. **Install** — run the installer so the live system matches the repo:
   - Whole box: `sudo /srv/dev/repos/home-server/install.sh`
   - Faster, targeted: the relevant sub-installer, e.g.
     `sudo /srv/dev/repos/home-server/systemd/install.sh` (units) or
     `/srv/dev/repos/home-server/claude/install.sh` (Claude context; run as dev, or it
     drops to dev when run as root).
   Installers are idempotent — safe to re-run.
3. **Verify** it actually works (see per-type checks below). This is the important step.
4. **Report honestly**:
   - Verified and passed → done. **No Ethan review needed.**
   - Could NOT verify it yourself (needs a secret you don't have, a reboot, a real backup
     stick, someone to join the server, etc.) → say exactly what's unverified and leave it
     for Ethan. Never claim "done/tested" for something you only installed.

## Verify, by type

- **systemd unit/timer:** installer runs `daemon-reload`. Then
  `systemctl status <unit>` (loaded, no error), `systemctl list-timers <timer>` (next run
  set). For a oneshot service that's safe to run now: `sudo systemctl start <svc>` and read
  `journalctl -u <svc> -n 30` for success. (A service that hard-fails on missing secrets is
  "unverified", not "broken" — note it.)
- **Claude context (`claude/`):** after `claude/install.sh`, confirm the file landed:
  `~/.claude/CLAUDE.md`, `~/.claude/skills/<name>/SKILL.md`, and memory under
  `~/.claude/projects/-<proj>/memory/`. A skill/CLAUDE change is only picked up by a NEW
  session, so verify the file content, not live behavior.
- **A script:** run it (or a dry-run / `--help` / a read-only path) and check the output.

## Rules

- Idempotent, non-destructive, understand-before-change; keep repo == live.
- **No secrets in the repo** — only their `/etc/...` locations (e.g.
  `/etc/home-server/mod-notify.env`). Never read or print secrets.
- Commit/push when asked; branch off `main`.
