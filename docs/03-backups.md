# 03 — Backups & archives

Two goals: **cheap backup**, **cheap restore**. Four mechanisms exist on this box and
they are easy to confuse — this is the map. Two are real backups to the **USB stick**
(`/mnt/backup`, 227 GB), one is an **offsite** copy to Backblaze B2, and one
(LVM snapshots) is a **local rollback point, not a backup at all**.

## At a glance

| Mechanism | Scope (what) | Location | How often | Storage cost | Retrieve time | Retrieve effort / cost |
| --- | --- | --- | --- | --- | --- | --- |
| **LVM-thin snapshot** | Whole VM-100 disk, point-in-time (copy-on-write) | **Host** thin pool `pve/data` — *same disk, same box* | **Manual**, before each mod/game change | Only diverged blocks (≈0 at creation, grows over time) | **Seconds** (`qm rollback`) | Trivial one command — **but discards newer state**, and dies with the disk |
| **vzdump** | **Entire** Valheim VM (OS + Docker + game install + world), consistent | USB stick `/mnt/backup/vzdump/*.vma.zst` | **Daily 04:00**, keep-last=6 (~6 days) | ~6–16 GB per image (zstd); ~40–90 GB for 6 | ~10–20 min (`qmrestore` a 16 GB image) | Moderate — restores the whole VM in one action. Most-restorable |
| **restic → flash** | Host config (`/etc/pve`, fstab, network) + repo checkout. **Not the world** (see note) | USB stick `/mnt/backup/restic-repo` (encrypted, dedup) | Twice daily 03:00 & 15:00, keep-within 14d + prune | Tiny — ~13 MB source; ~28 dedup'd snapshots ≈ **15–30 MB** | Seconds–minutes (single file); minutes (full) | Low — pick any snapshot/path. Needs restic password |
| **restic → B2** | Valheim **world only** (`/srv/valheim/config`, 1.1 GB) | Backblaze B2 bucket (scoped key); **runs inside the VM** | Every other day 12:30 UTC, keep-within 14d + prune | Cloud, dedup; ~7 snapshots sharing chunks ≈ **1.5–2 GB total** | Minutes (download ~1 GB over the home link) | Low effort; small **B2 egress $** (~$0.01/GB). Needs key + restic password |

> **Status (2026-09-13):** vzdump→flash ✅ running. restic→B2 ✅ running (5 snapshots,
> `restic check` clean). **restic→flash ❌ not yet running** — the timer is enabled but
> was never started and the repo is uninitialized (0 snapshots). Start it with
> `sudo systemctl start hs-restic-flash.service` (inits the repo), then
> `sudo systemctl start hs-restic-flash.timer`. Until then the world's flash copy exists
> **only inside the vzdump VM images**, not as a file-level restic repo.

## The four, in words

### 1. LVM-thin snapshots — rollback points, NOT backups
Created by hand (the `/add-valheim-mod` skill runs `qm snapshot 100 pre_<change>`) right
before a risky mod or game change, so a bad change is one `qm rollback` away. They live
on the **same LVM-thin pool as the live VM disk**, so they protect against *bad changes*,
never against disk failure or box loss — that is why they are not in the 3-2-1 tally
below. They are also the thing behind the "N LVM snapshots" line in the health hook: the
count (not the space) trips a WARN at ≥8 because forgotten snapshots slowly eat thin-pool
space as the origin diverges. **Prune stale ones** after a change is confirmed good:
`sudo qm delsnapshot 100 <name>`.

### 2. vzdump — whole guest to the stick (daily)
Mode **snapshot** (needs the QEMU guest agent) = a consistent image without stopping the
server; `zstd` compressed. Retention is **count-based (keep-last=6), not 14 days** —
images are large (~16 GB each) and don't dedup, so a 14-day twice-daily rotation would
blow past the stick. This is the one place the 14-day rule doesn't apply. Driven by
`systemd/hs-vzdump-valheim.{service,timer}` → `backups/vzdump-valheim.sh`.

### 3. restic → flash — file-level host config history (twice daily)
Repo on the stick at `/mnt/backup/restic-repo`; password from `/etc/home-server/backup.env`
(never committed). Scope: Proxmox host config (`/etc/pve`, `/etc/fstab`, `/etc/network`)
and the `home-server` repo checkout — ~13 MB total, most of it the repo's `.git`.
`--keep-within 14d` + `restic prune`; `restic check` after each run (occasionally
`--read-data` to catch flash bit-rot). Driven by
`systemd/hs-restic-flash.{service,timer}` → `backups/restic-flash.sh`. **Guarded:** refuses
to run if `/mnt/backup` isn't mounted (a backup to a missing mount is a silent no-op).

> **The world is NOT in this repo.** `restic-flash.sh` lists `/srv/valheim/config`, but
> that path lives **inside VM 100** and is absent on the Proxmox host where this runs, so
> the path is silently skipped. The world reaches flash only via **vzdump** (whole-VM
> image) and offsite only via **B2** (below). To also get the world into this repo it would
> have to be pulled out of the guest first (e.g. a guest-side `tar` to a host-visible path,
> or run a restic-flash-world backup inside the VM like the B2 one does).

### 4. restic → B2 — the world, offsite (every other day)
The only offsite copy, and the only copy of the *irreplaceable* thing that isn't on the
box. Separate restic repo on a **dedicated, bucket-scoped B2 key** (read+write+delete for
prune) so the box can touch only `valheim-world`, never Ethan's personal `b2-backup`.
**Runs inside VM 100** (the world dir is local to the guest) via
`valheim/backup/valheim-b2-world.{service,timer}` → `backups/restic-b2-world.sh`. Same
`--keep-within 14d` + prune + check.

> **On prune and "deltas":** restic snapshots are **not** a full-plus-incrementals chain —
> each snapshot is a complete, independently-restorable set of references to content-addressed
> chunks, and identical chunks are stored once and shared. `prune` is reference-counted GC: it
> frees a chunk only when **no** surviving snapshot references it, so ageing out the oldest
> snapshot can never orphan a chunk the newer ones still need. The stored size is the union of
> chunks across the kept snapshots, which is why it plateaus rather than growing forever. restic
> also never forgets the latest snapshot, so a long backup gap can't prune you down to nothing.

## The USB stick — honest risk and mitigation
A thumb stick has no SMART, cheap NAND, and fails **suddenly and silently**; unpowered it
can bit-rot over months. Two mitigations make flash-primary acceptable:

1. **restic's integrity check** (`restic check`, periodically `--read-data`) actively
   detects corruption, so a dying stick announces itself — *once restic→flash is running.*
2. The **world gets a second home on B2**, so the stick may be the only copy of the bulk,
   but never the only copy of the irreplaceable world.

Mount by UUID in `/etc/fstab` so a rebuild remounts it the same way. If Ethan buys an
external **SSD**, swap the stick for it — same commands, better medium. Don't block on it.

## Secrets placement
Restic passwords and the B2 key are secrets: they live in `/etc/home-server/backup.env`
(mode 600), **never** in this repo, never world-readable. The bucket-scoped B2 key limits
blast radius even if leaked. The restic **encryption** password also lives in Ethan's
password manager, so a total-loss restore is possible.

## 3-2-1 scorecard (honest)
- **Copy 1:** live data on the server.
- **Copy 2:** the USB stick (vzdump always; restic once its backup is started).
- **Copy 3 (offsite):** B2 — **world only**.

Host config and the VM image are **not** offsite by design — they're reproducible (repo +
`bootstrap.sh` + re-pull mods). The only thing that truly can't be regenerated is the
world, and that's the thing with a third, offsite copy. (LVM snapshots are **not** a copy
in this tally — same disk, same box.)

## Test-restore (the step everyone skips)
Periodically restore the latest vzdump into a *throwaway* VM and boot it, and
`restic restore` the world from B2 into a scratch dir. A backup you've never restored is a
hope, not a backup. Full procedure: `05-restore-runbook.md`.
