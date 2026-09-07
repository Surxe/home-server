# Home server conversion — overview and decisions

This directory is the working handoff for converting an old laptop into an
always-on home server. It is meant to travel: build the base from Ethan's home
PC, then copy this whole directory onto the server, install Claude Code there,
and let it drive the rest.

Read the docs in order. Modify them as reality diverges — they are a living
runbook, not a spec.

## The one idea that drives everything

The box is **disposable**. Claude has near-total freedom on it precisely because
a wrecked box is a ~30-minute scripted rebuild, not a weekend. Every decision
below serves two goals: **cheap backup** and **cheap restore**.

## Decisions locked

| Area | Decision |
| --- | --- |
| Host OS | **Proxmox VE** on the metal (Debian-based, so "Debian core" holds) |
| Graphics | **None** — fully headless. No desktop, no Wayland/X, no GPU driver |
| Valheim | Its own **VM** running **Docker** + `lloesche/valheim-server` |
| Valheim access | ModSentry **crossplay join code + password + matching mods**. No IP, no port forwarding |
| Networking | Host on **wifi** (see caveat in 01); Valheim VM uses **NAT/routed**, not a bridge |
| Storage | LVM-thin, thin-provisioned; grow disks later as needed |
| Backups | Flash stick **twice/day** (vzdump whole guests + restic host/files); B2 **every other day** (restic) |
| Retention | restic `--keep-within 14d` + prune; vzdump keeps a small **count** (images do not dedup) |
| World save | Backed up to **both** flash and B2. B2 = a dedicated **`valheim-world`** bucket, key **scoped to that bucket only** (box cannot see other B2 backups) |
| Config source of truth | New **`home-server`** GitHub repo, owned by **Surxe** |
| Repo auth on box | Box authenticates as **Surxe-dev**; can push branches only, cannot merge |
| Publish model | Claude auto-commits locally; opens/updates a PR; **Ethan merges from home PC** |
| Config deploy | **symlink-into-repo** (live path -> repo file) + a thin `bootstrap.sh` for files that cannot be symlinks |
| Accounts | Single `dev`/Claude-owned box + a separate **break-glass admin** login kept for recovery |
| Admin access | **Local console for now** — Ethan runs Claude at the laptop keyboard. SSH key-only / Tailscale deferred to later |

## Deliberately deferred (not today)

- Jellyfin and its media library (media is re-acquirable; excluded from backup).
- WRF and other project data trees.
- Jellyfin hardware transcoding (the only future reason to add a GPU driver).
- Tailscale / off-network admin access.

## Today's critical path

1. `01-proxmox-host.md` — install Proxmox, network, headless, break-glass admin.
   (SSH is deferred; Ethan works at the local console for now — see `06-ethan-tasks.md`.)
2. `02-valheim-vm.md` — VM + Docker + modded Valheim, friends joining by crossplay code.
3. Get it running, confirm a friend can join.
4. Then: copy this dir + repo onto the box, install Claude Code, proceed with
   `03-backups.md`, `04-repo-and-bootstrap.md`, `05-restore-runbook.md`.

## Hands-on vs remote

The ISO install, BIOS/boot order, and wifi firmware must be done **physically at
the laptop** — SSH does not exist yet. Everything after the host is on the
network and reachable can be driven remotely (and eventually by Claude on the
box itself).

## Related existing docs

- `../valheim-mods/SERVER-HANDOFF.md` — the authoritative mod version/hash
  manifest and ModSentry policy-folder layout. `02-valheim-vm.md` references it
  rather than duplicating it.
- `/srv/dev/repos/my-system` — the workstation's context repo. This server gets
  its **own** repo; do not fold it into my-system.
