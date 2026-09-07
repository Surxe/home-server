# 03 — Backups

Two goals: **cheap backup**, **cheap restore**.

Cadence:
- **Flash stick — twice a day:** vzdump (whole guests) + restic (host/files/world).
- **B2 — every other day:** restic (world save).
- The **Valheim world is backed up to both** flash and B2.

Primary target: a **USB stick** (210GB free). Offsite: a narrow B2 copy of the
world.

## The layering (use each tool where it fits)

| What | Tool | Target | Why |
| --- | --- | --- | --- |
| Whole guests (Valheim VM) | **vzdump** | flash | Most-restorable: restore the entire VM in one action |
| Host config + file-level + world | **restic** | flash | Dedup, encryption, snapshots, integrity checks |
| World save, offsite | **restic** | B2 (own bucket) | Offsite copy; key scoped so box sees only this bucket |

## The USB stick — honest risk and mitigation

A USB thumb stick has no SMART, cheap NAND, and fails **suddenly and silently**;
unpowered it can bit-rot over months. Two mitigations make flash-only acceptable:

1. **restic's integrity check** (`restic check`, periodically `--read-data`)
   actively detects corruption, so a dying stick announces itself.
2. The **world save gets a second home** on B2 (below). The stick may be the only
   copy of the *bulk*, but never the only copy of the irreplaceable world.

If Ethan ever buys an external **SSD**, swap the stick for it and the whole worry
goes away — same commands, better medium. Note, do not block on it.

Mount the stick at a stable path (by UUID in `/etc/fstab`, so a rebuild remounts
it the same way). Confirm it is mounted before every backup run (a backup to a
missing mount is a silent no-op — guard against it).

## vzdump — whole guests (flash, twice a day)

- Back up the Valheim guest to the stick twice a day.
- Mode **snapshot** (with the QEMU guest agent installed) for a consistent image
  without stopping the server.
- Compression: `zstd`.
- **Retention is count-based, NOT 14 days** — vzdump images are large and do not
  dedup, so twice-daily 14-day retention (~28 images) would blow past 210GB. Keep
  a small rotation instead (e.g. **last 6** = ~3 days) and tune to fit the stick.
  This is the one place the 14-day rule does not apply; size forces a count.
- Schedule via the Proxmox backup scheduler, or a systemd timer, twice daily.

## restic — flash (twice a day)

- Repo on the stick: `restic -r /mnt/stick/restic-repo`.
- Password from a file, **not** committed anywhere (see secrets note below).
- Scope: Proxmox host config (`/etc/pve` export, `/etc/network`, custom units),
  the `home-server` repo checkout, file-level odds and ends, **and the Valheim
  world dir** (`/srv/valheim/config`). The world thus lands on flash via both
  vzdump (whole guest) and restic (the dir) — cheap thanks to dedup.
- **Retention: `--keep-within 14d` then `restic prune`.** restic keeps every
  snapshot until told otherwise; chunking makes 14 days of history cheap, but the
  prune is what enforces the window.
- Integrity: run `restic check` after backups; occasionally `--read-data` to catch
  flash bit-rot.

## restic -> B2 (world save, offsite, every other day)

Now that the B2 bucket may be **read + write**, use restic here too — same tool,
same dedup and integrity, and restore no longer needs a hand-applied key.

- Create a **dedicated B2 bucket** `valheim-world`, separate from `b2-backup`.
- Create a B2 **application key scoped to only that bucket** with read + write +
  delete (delete is needed for `prune`). Scoping is the safeguard: the box can
  read and write **only** `valheim-world` and can never see Ethan's personal
  `b2-backup` bucket.
- A **separate restic repo** on that bucket
  (`restic -r b2:valheim-world:...`), backing up `/srv/valheim/config` every other
  day. Same `--keep-within 14d` + prune.
- Restore is straightforward from the box or from Ethan's PC — the key can read.

## Secrets placement (do not park in the box's plain files)

- Restic passwords, B2 key: these are secrets. Follow Ethan's existing model —
  injected via environment / a launcher, never committed to the `home-server`
  repo, never in a world-readable file. The B2 key being **bucket-scoped** limits
  blast radius even if leaked — it can touch only `valheim-world`, never
  `b2-backup`.
- The restic *encryption* password also lives in Ethan's password manager (his
  stated plan) so a total-loss restore is possible.

## 3-2-1 scorecard (be honest about where we are)

- Copy 1: live data on the server.
- Copy 2: the USB stick (vzdump + restic).
- Copy 3 (offsite): B2, **world save only**.

Host config and the Valheim VM image are **not** offsite — they are reproducible
(repo + `bootstrap.sh` + re-pull mods), so that is acceptable by design. The only
thing that truly cannot be regenerated is the world, and that is the thing with a
third, offsite copy.

## Test-restore (the step everyone skips)

Schedule a periodic drill: restore the latest vzdump into a *throwaway* VM and
boot it; `restic restore` the world from B2 into a scratch dir. A backup you have
never restored is a hope, not a backup.
