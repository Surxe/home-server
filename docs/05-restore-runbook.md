# 05 — Restore runbook (the 30-minute rebuild)

This is the payoff doc. If the laptop dies, the disk corrupts, or Claude bricks
something beyond a snapshot rollback, this is how you get back. Keep it accurate —
its correctness is the entire justification for letting Claude "go ham."

## Restore ladder — try the cheapest that fits

| Scope of damage | Restore action | Time |
| --- | --- | --- |
| Bad mod/game update | Proxmox **snapshot rollback** of the Valheim guest | seconds |
| Valheim guest broken/lost | Restore latest **vzdump** of the guest | minutes |
| Host config messed up | Re-run **`bootstrap.sh`** (re-links + rewrites config) | minutes |
| World corrupted, guest fine | `restic restore` the world from **flash or B2** into `/srv/valheim/config` (stop the container first — see below) | minutes |
| Total loss (new/wiped disk) | Full rebuild below | ~30 min + data restore |

## Restoring the world into a live guest (don't clobber your own restore)

The running Valheim server holds the world in memory and **autosaves over
`/srv/valheim/config/worlds_local` on its own schedule**, and the lloesche image
also runs a periodic **auto-update + restart** loop. Either one will overwrite a
world you drop in underneath a live server. So when restoring *just the world*
(flash or B2) into an otherwise-healthy guest:

1. **Stop the container first** — `docker stop valheim`. It flushes once, then
   autosave *and* the auto-update loop stop, so nothing rewrites the files while
   you restore. (Re-confirmed in the 2026-09-07 drill: skip this and the live
   server saves the old world back over the restore within a minute.)
2. `restic restore <snap> --target / --include /srv/valheim/config/worlds_local`
   — scope the `--include` so you don't clobber the BepInEx/mods tree.
3. Verify the restored `.db` (size / mtime / sha256) **before** restarting.
4. `docker start valheim`, then confirm the 4 plugins load and a join code prints.

## Verifying a restore is faithful (hash timing matters)

To prove the restored world matches the backup, the reference hash must be taken
at the **same instant as the backup** — ideally from a *stopped* server, or read
out of the backup itself. A hash captured from a live server *after* the backup
will **not** match: the world keeps autosaving and drifts ahead of the frozen
copy (this is exactly why the vzdump restore in the 2026-09-07 drill "mismatched"
— the reference hash was ~30 min newer than the snapshot, not a corrupt restore).
Freshness corollary:

- A **vzdump** is only as current as the **last autosave before the snapshot**
  (Valheim persists periodically, not continuously) — a whole-VM restore can lose
  up to one autosave interval of progress.
- The **B2 world snapshot** is the freshest single-file world copy; use it to roll
  the world forward after a vzdump restore when you need the latest state (the
  drill did exactly this: vzdump for the VM, then B2 for the current world).

## Full rebuild from bare metal

Prereqs kept **off-box**: the restic password + B2 keys (Ethan's password
manager), the USB stick, and network access.

1. **Install Proxmox** on the disk (`01-proxmox-host.md`, steps 1-2). Default
   ext4 + LVM-thin.
2. **Bring up networking** (wifi + NAT) enough to reach GitHub — either re-run the
   relevant bits by hand or restore `/etc/network` from restic first.
3. **Clone the repo:** `git clone https://github.com/Surxe/home-server` into its
   standard path.
4. **Run `bootstrap.sh`:** re-creates symlinks, rewrites fstab/logind/sshd/sudoers,
   recreates the Valheim guest definition.
5. **Mount the stick**, verify with `restic check`.
6. **Restore host file-level bits** from restic if not already covered by bootstrap.
7. **Restore the Valheim guest** from the latest **vzdump** on the stick (this is
   faster and more complete than rebuilding the VM from scratch + re-installing
   mods).
   - If the vzdump is unavailable/stale: recreate the VM per `02-valheim-vm.md`,
     re-stage the pinned mod DLLs from the manifest, then restore the **world**:
8. **Restore the world:** from the stick (vzdump already includes it), or
   `restic restore` from the **B2 `valheim-world`** repo (the bucket-scoped key
   can read it).
9. **Re-supply secrets** into Ethan's env/launcher (restic pw, B2 keys) — bootstrap
   prints these as manual follow-ups; it never stores them.
10. **Verify:** server boots, ModSentry active, crossplay code prints, a test
    client joins. Re-add Ethan's SSH key if the account was recreated.

## What is intentionally NOT restorable from offsite

- The full host image and the Valheim VM image are **reproducible**, not archived
  offsite. If both the disk and the stick are gone simultaneously, you rebuild
  from the repo (config) + B2 (world) + re-fetched pinned mods. That is by design:
  the only irreplaceable artifact (the world) is the only one with an offsite copy.

## Keep this honest

- After any structural change (new service, new mount, new guest), update this
  runbook and re-time a drill.
- Run the `03-backups.md` test-restore periodically. An untested runbook is
  fiction.
