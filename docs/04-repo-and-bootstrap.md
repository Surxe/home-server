# 04 — The `home-server` repo and bootstrap

The repo is the **source of truth for config** and the **entry point for restore**.
It is small text; GitHub is not its backup, it is how a rebuild starts:
`git clone` then `bootstrap.sh`.

## Repo identity and auth

- **Owner:** the **Surxe** GitHub account (a new repo, e.g. `Surxe/home-server`).
- **Not** folded into `my-system` — this is a separate machine with its own repo.
- **Box auth:** the server authenticates to GitHub as **Surxe-dev** (the PAT dev
  already uses on the workstation). Branch rulesets let Surxe-dev **push branches
  but not merge** protected `main`.
- **Publish model:** Claude on the box **auto-commits locally** (local commits need
  no GitHub identity) and pushes a feature branch as Surxe-dev. **Ethan merges the
  PR from his home PC** as Surxe when he is ready. This satisfies: repo attached to
  Surxe, Claude cannot operate as Surxe, only Ethan publishes.
- **Day-one exception:** while first standing the box up, do not fuss with
  one-PR-per-commit. Commit freely locally; open a single "initial home-server"
  PR at the end for Ethan to review.

## Deploy model: symlink-into-repo (not copy)

The workstation's `install.sh` copies files because a privilege boundary forbids
symlinking dev-writable content into Ethan's space. **That boundary does not exist
here** (single dev/Claude-owned box), so use the cleaner GNU-Stow-style model:

- Repo holds the real files.
- The **live location symlinks back into the repo**:
  `/etc/systemd/system/valheim.service -> /srv/.../home-server/systemd/valheim.service`.
- Same inode, so editing the repo file *is* editing the live config — no apply
  step, and Claude's tests exercise exactly what ships.

### Files that cannot be symlinks -> `bootstrap.sh`

Some targets refuse or ignore symlinks. For these, `bootstrap.sh` writes/links
them idempotently:

- `/etc/fstab` (cannot be a symlink) — the stick's UUID mount lives here.
- `/etc/pve/*` — Proxmox's special cluster FS; managed via `pvesh`/`qm`/`pct`,
  not symlinks. Store the guest **definitions/creation scripts** in the repo and
  have bootstrap recreate guests.
- sudoers, some systemd unit paths — write real files.

So the rule is: **symlink where safe, bootstrap the rest.**

### Guests are PUSHED, not symlinked

The symlink model is host-only. A guest VM has no access to the host's repo checkout, so
its config is **pushed into the guest over the QEMU guest agent** (`qm guest exec`), then
applied inside it. For the Valheim VM this is scripted: **`guests/vm-apply-valheim.sh`**
(push `valheim/` config → run `stage-mods.sh` → restart the container). The full deploy
model, the BepInEx `config`-symlink gotcha, and the ModSentry/Jotunn plugin rules are
documented in **`valheim/README.md`** — read it before touching the Valheim mod set.

## What the repo tracks

- Host: `/etc/network/interfaces`, wpa_supplicant unit, NAT/masquerade rule,
  `logind` lid config, `sshd_config` drop-ins, apt repo list.
- Backups: vzdump schedule, restic wrapper + retention policy, the B2 world-save
  upload script (no secrets — see below).
- Valheim: `docker-compose.yml`, the BepInEx/ModSentry staging layout, pinned mod
  manifest (mirror of `SERVER-HANDOFF.md`), DropThat config.
- Guest definitions: scripts to recreate the Valheim VM (`qm`-based) so a rebuild
  reconstructs it.
- `bootstrap.sh`: the idempotent apply step.

## What the repo must NEVER contain

- Restic password, B2 keys, SSH private keys, server passwords, PATs, `DEEPSEEK_API_KEY`. Secrets stay
  in Ethan's model (env/launcher), documented by *location* only. See Ethan's
  `no-email-in-repos` / secrets-policy conventions.
- The world save itself (binary, churns; belongs in vzdump + B2, not git).

## bootstrap.sh contract

Running `bootstrap.sh` on a fresh Proxmox host must be **idempotent** and get from
bare host to running services:

1. Create symlinks from live locations into the repo (skip if already correct).
2. Write the non-symlinkable files (fstab mount, logind, sshd drop-in, sudoers).
3. Recreate guests from the `qm` definitions (skip if present).
4. Print the manual follow-ups it cannot do (restore data from backup, supply
   secrets, fetch pinned mod DLLs).

Keep it readable and Debian-native — no magic. It is the thing that makes the
30-minute rebuild real.
