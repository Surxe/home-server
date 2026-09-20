# home-server

Config-as-code + restore entry point for the headless Proxmox home server (an old
laptop). The box is **disposable**: a wrecked box is a scripted rebuild, not a weekend.
See `docs/` (mirrored handoff runbook `00`–`07`) for the full design.

## Layout
- `host/` — `/etc/network/interfaces`, wifi bring-up script, logind lid drop-in.
- `systemd/` — `home-server-wifi.service` (wifi persistence), the host backup pair
  `hs-restic-flash.{service,timer}`,
  `hs-todo-classify.{service,timer}` (daily 13:00 CT todo classify + hub sync),
  `hs-todo-sync.{service,path}` (push this box's todo commits to the hub on each
  commit — event-driven, the home-server twin of the workstation's todo-sync.path),
  `hs-wrf-discount-watch.{service,timer}` (poll the WRF news feed 4x/day: scrape the
  latest posts, and on a new weekly discount dispatch the discount-visualizer — see
  the WRFrontiers-News-Scraper repo; enabled only when that clone is present),
  `hs-steam-price-refresh.{service,timer}` (daily Steam price refresh + at/below-threshold
  email alerts — see the `steam-tracker/` area and the steam-price-tracker repo; enabled
  when that clone's venv is built), and `install.sh` (unit installer).
- `steam-tracker/` — the Steam price-tracker subsystem's box-local config: the
  config-as-code tracked-app list (`tracked_apps.json`, edited via the `add-steam-app`
  skill), the SMTP secret template (`steam-tracker.env.example` → live
  `/etc/home-server/steam-tracker.env`, root 600), and `install.sh` (builds the generic
  `steam-price-tracker` clone's venv + arms the daily timer). The tracker *code* is the
  generic sibling clone `/srv/dev/repos/steam-price-tracker`.
- `todo/` — this box is the hub + classifier for the shared cross-box `todo` store
  (bare repo `/srv/dev/repos/todo.git` + working clone). `classify-drain.sh` runs the
  classify job (pull hub, classify, push meta). Push-back to the workstation is not
  needed: the workstation pulls from the hub when it reads (`list`/`show`), since it
  always reaches this box but not vice-versa. See the `todo-cross-box` memory note and
  the todo repo's README (Cross-box) for the full sync design.
- `backups/` — host flash restic (`restic-flash.sh`) + retention + `backup.env.example`.
  (The Valheim guest vzdump + offsite B2 world backup moved to the valheim-server repo.)
- `guests/` — generic `create-vm.sh` (parameterized Proxmox VM creator) + `set-vm-dev-password.sh`.
  The Valheim server itself — Docker/mod config, its VM wrapper, mod tooling, the systemd
  feeds that watch it — lives in the sibling **valheim-server** repo
  (`/srv/dev/repos/valheim-server`).
- `install.sh` — top-level installer; calls the per-area installers (systemd, todo, agent
  context, shared dev-env) and the sibling valheim-server installer when that clone is present.
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
