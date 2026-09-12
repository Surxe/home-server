# Ideas (informal scratchpad)

Rough, uncommitted-to ideas for making home-server work well across many small Claude
sessions. Not a roadmap — just notes so they aren't lost. Prune freely.

- **Per-subsystem memory + a session-starter.** As memory grows (networking, backups,
  Proxmox host, each guest), keep one brief memory file per subsystem so a focused session
  loads only what it needs. Maybe a tiny `/prime valheim` style skill/command that pulls
  the right memory + docs + the subsystem's install/deploy command into context at the top
  of a session.

- **CLAUDE.md as a subsystem map.** Add a small table in the global CLAUDE.md: subsystem →
  its memory note, its docs page, and its one deploy command. That single lookup is often
  all a small session needs to orient.

- **`install.sh --check` (dry-run/verify mode).** A no-write mode that reports drift
  (repo vs live: unit symlinks present? daemon-reload needed? ~/.claude files match?) so a
  session can confirm "repo == live" without applying. Would pair well with the
  home-server-install skill's verify step.

- **Auto-regenerate MEMORY.md.** A builder that rebuilds the memory index from the
  frontmatter of the memory files, so the index can't drift from the files (my-system does
  something like this for CLAUDE.md sections).

- **Move the two detailed Valheim session-notes into the curated library.** Right now
  `valheim-server-ops` and `valheim-1.0-mod-status` live only in live memory, not the repo;
  fold the durable bits into repo-tracked memory when curating the next batch.

- **A `track-new-mod` skill.** Adding a mod today is a multi-step, easy-to-fumble ritual:
  resolve the Thunderstore namespace/name/version, pin it with its SHA-256 in
  `valheim/mods.manifest` (right `plugin`/`plugin+required`/`ModSentry_Optional` class),
  drop the DLL in `valheim/dll/`, run `stage-mods.sh`, decide client-side vs server-side +
  the ModSentry policy folder, update the client docs, apply with `vm-apply-valheim.sh`,
  restart, then confirm a clean load in `BepInEx/LogOutput.log`. A skill would encode that
  sequence (with the 1.0 load-test recipe from the valheim memory note) so a focused session
  can add a mod correctly without rediscovering the gotchas. Pairs with the mod-update
  alerts (`hs-mod-check` email / `hs-mod-check-discord`) that already flag when to adopt one.
