# 06 — Ethan's tasks (do these; Claude cannot)

The plan: batch everything that needs Ethan — physical access, personal
credentials, accounts, value-choices — **up front**, so once Claude is running on
the box it can goal-loop the rest without stalling.

## Mode: LOCAL, no SSH (for now)

Ethan runs Claude **at the laptop keyboard**. No SSH, no remote access, no
keypair exchange yet. Remote access (SSH key-only, and/or Tailscale) is a
**later, optional** add — see `01-proxmox-host.md` section 6, deferred.

Consequence: several former tasks drop away — no home-PC public key, no
disable-password-auth, no static IP "so SSH is predictable" (a DHCP lease is
fine). Networking is still needed, but only for Claude's API access and Valheim's
outbound crossplay — not for reaching the box.

## The handoff line

Claude takes over once the box is: **installed -> on wifi -> Node + Claude Code
installed and authed -> secrets staged.** Everything above that line is Ethan;
everything below is Claude's loop.

Legend: [x] done, [~] partial/in progress, [ ] to do. Full current state is in
`07-status.md`.

## A. Physical / at the laptop

- [x] Make the Proxmox VE USB installer. (Ventoy failed the Proxmox cd-id check in
      every mode; ended up raw-`dd`ing the ISO to the stick. Also had to disable
      Secure Boot + Fast Boot in the InsydeH2O BIOS to boot it.)
- [x] BIOS/UEFI: boot order + virtualization enabled.
- [x] Run the installer: ext4 + LVM-thin, root password set.
- [~] The **210GB stick** — used to ferry the wifi `.deb`s and these handoff docs;
      still needs reformatting/dedicating as the backup target later.
- [x] No USB-ethernet dongle available; used wifi (see networking note below).

## B. Values to decide

- [x] **wifi SSID + password** — used to associate the AX200 (`wlp1s0`).
- [x] **hostname** — `home-server.lan`.
- [ ] **Valheim**: server name, world name, server password. STILL NEEDED.
- [x] **Account model** — `dev` user with passwordless sudo (Claude runs as this);
      `root` kept as break-glass. Done.

## C. Secrets to stage (off the repo, in Ethan's env/launcher model) — STILL NEEDED

- [ ] **Restic password** -> password manager, and readable by the box's backup runner.
- [ ] **B2**: create the `valheim-world` bucket + a **bucket-scoped** app key
      (read/write/delete on that bucket only).
- [ ] **GitHub**: create empty `Surxe/home-server`; set the branch ruleset
      (Surxe-dev pushes branches, cannot merge `main`); stage the **Surxe-dev PAT**
      on the box.

## D. The handoff itself

- [~] Copy this handoff dir onto the box (in progress — via the 210GB stick).
- [x] Install **Claude Code** on the box (native installer; Node 20 was too old for
      the npm build which needs Node >=22, so used the self-contained native build).
- [x] Run the **Anthropic auth login** — done over SSH from the home PC (the box is
      headless with no browser, and the auth URL is too long to retype, so SSH's
      copy-paste was the unlock).

## E. Discovered during setup (new work, now tracked)

- [x] Proxmox **enterprise apt repos** returned 401; disabled them and added the
      free `pve-no-subscription` repo. `apt update` clean.
- [ ] **Wifi persistence (box-Claude's FIRST task).** Wifi + the correct default
      route currently exist **only at runtime** — a reboot loses wifi auto-start and
      the installer's dead `vmbr0` gateway (`192.168.100.1`) reclaims the default
      route. Must: auto-start `wlp1s0` on boot from the existing wpa config, and
      strip the `gateway 192.168.100.1` line from `vmbr0`. DO NOT REBOOT until this
      is in place. See `07-status.md`.
- [ ] **Harden SSH** to key-only (Proxmox's default root-password SSH is currently
      on; it was used for the auth). After persistence is confirmed. See `01` §6.
- [ ] Later: bring up the **VM NAT/bridge** networking (`01` §3) once wifi is stable.

## Not on the list (so you do not go looking)

- **No router / port-forward** — Valheim crossplay is outbound-only.
- **No Steam account** — the dedicated server logs in anonymously (app 896660).
- **No SSH setup** — deferred; local console for now.

## What comes back to Ethan later (by design)

- **Merging the PR** Claude opens (from the home PC, as Surxe).
- **Giving friends** the crossplay join code + server password + the exact mod set.
