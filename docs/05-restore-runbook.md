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
| World corrupted, guest fine | `restic restore` the world from **flash or B2** into `/srv/valheim/config` | minutes |
| Total loss (new/wiped disk) | Full rebuild below | ~30 min + data restore |

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
