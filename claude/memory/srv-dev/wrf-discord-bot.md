---
name: wrf-discord-bot
description: WRFrontiersDB Discord bot ([[name]] lookups) runs on the host as hs-wrf-discord-bot.service; where its config/token live, how to deploy + verify, known failures
metadata:
  type: reference
---

The **WRFrontiersDB Discord bot** (code: sibling clone `/srv/dev/repos/WRFrontiersDB-Discord-Bot`,
see its `CLAUDE.md`) runs **on the host**, not in a VM, as `hs-wrf-discord-bot.service` (user
`dev`, long-running). It answers `[[name]]`, `/wrf` and `/about` (which Data commit the
bot, Site and Visualizer are on), and replies to wrf-db.info `/models?a=<code>` links with the
builds' parts, in Ethan's personal test server.

- **Config-as-code:** the options (`DATA_DIR`, `GUILD_IDS`, `ENABLED_SERVICES`) are in
  `systemd/hs-wrf-discord-bot.service`. Only the token is outside the repo:
  `/etc/home-server/wrf-discord-bot.env` (root 600; never read it). The unit is skipped until that
  file exists.
- **Data:** it only reads the pipeline's `/srv/dev/repos/WRFrontiersDB-Data` clone, and reloads
  within 10 min of a patch-day push.
- **Embed text:** the Site's English page meta descriptions, from `wrf-db.info/meta_descriptions.json`.
  Fetched at startup and again within 10 min of each Site deploy the pipeline records in
  `SITE_DEPLOY_STATE` (`WRFrontiersDB-Orchestrator/data/site_deploy_state.json`). Stale embed text?
  Check that file's `run_id` against the JSON's `build_id`; the bot logs "The Site still
  serves meta descriptions from build ..." while they differ. The file is the Site's deploy
  record (see [[wrf-deployed]]), so it also gives the Site's `data_commit`.
- **Deploy a change** (bot code or unit): `sudo wrf-discord-bot/install.sh` rebuilds the venv,
  clears any start-limit failure and restarts. **Verify:**
  `journalctl -u hs-wrf-discord-bot -n 20` shows `Logged in as wrf-db#1514`.
- **Known failures:**
  - `PrivilegedIntentsRequired`: Message Content Intent is off in the Developer Portal.
  - `LoginFailure`: bad token.
  - After 5 failed starts in 10 min the unit stops retrying (start limit). The installer's
    `reset-failed` clears that.
  - A logged "Data refresh failed" while the pipeline re-clones Data is harmless; the bot keeps
    the previous data.
