# home-server

Config-as-code + restore entry point for the headless Proxmox home server (an old
laptop). The box is **disposable**: a wrecked box is a scripted rebuild, not a weekend.
See `docs/` (mirrored handoff runbook `00`–`07`) for the full design.

## Layout
- `host/` — `/etc/network/interfaces`, wifi bring-up script, logind lid drop-in.
- `systemd/` — `home-server-wifi.service` (wifi persistence), backup service/timer pairs,
  `hs-mod-check.{service,timer}` (daily Valheim mod-update email),
  `hs-todo-classify.{service,timer}` (daily 13:00 CT todo classify + hub sync), and
  `install.sh` (unit installer).
- `todo/` — `classify-drain.sh`: this box is the hub + classifier for the shared cross-box
  `todo` store (bare repo `/srv/dev/repos/todo.git` + working clone). See the
  `todo-cross-box` memory note.
- `backups/` — restic (flash + B2) and vzdump scripts, retention, `backup.env.example`.
- `valheim/` — `docker-compose.yml`, mod manifest + `stage-mods.sh`, DropThat loot cfg,
  `check-mod-updates.sh` (Thunderstore poll) + `notify-mod-updates.sh` (email on change).
- `guests/` — Valheim VM creation script + cloud-init.
- `install.sh` — top-level installer; calls the per-area installers (currently `systemd/install.sh`).
- `bootstrap.sh` — idempotent first-boot host apply: symlinks live paths into this repo, masks
  sleep, enables wifi, prints the manual follow-ups it cannot do.

## Deploy model
Symlink-into-repo: live paths symlink back to files here (same inode), so editing a repo
file *is* editing live config. `bootstrap.sh` establishes the links + the non-symlinkable
bits (fstab). Secrets never live here — only their *locations* (`/etc/home-server/backup.env`,
`/etc/valheim/valheim.env`).

## Rebuild (short form — see docs/05)
`git clone` → `bootstrap.sh` → mount backup stick → restore vzdump/world → supply secrets.

## Networking note
No physical ethernet: the host uplink is **wifi**, owned by `home-server-wifi.service`
(Proxmox's ifupdown2 wifi handling is unreliable, so wifi is kept out of it). `vmbr0` is
an internal NAT bridge (no uplink) for guest VMs; masquerade is out `wlp1s0`.
