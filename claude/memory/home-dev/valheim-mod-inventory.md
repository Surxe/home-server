---
name: valheim-mod-inventory
description: List the currently installed Valheim mods (required/optional + version) — the manual command
metadata:
  type: reference
---

To see what mods are installed on the Valheim server right now, grouped by ModSentry role
(required / optional / server-only) with each mod's version, run on the host:

```
/srv/dev/repos/home-server/valheim/list-installed-mods.sh
```

It prints a table (read-only). Source of truth is `valheim/mods.manifest` — the enabled
(non-commented) lines are what `stage-mods.sh` deploys, so under the repo==live invariant
they ARE what's installed; commented-out mods (disabled, waiting on a 1.0 build) are excluded.
The BepInEx pack is provided by the lloesche image and isn't listed.

Add `--post` to send the list to Discord (`list-installed-mods.sh --post`, needs
`DISCORD_WEBHOOK_URL`). That's what the daily systemd timer **`hs-mod-list.timer`** (09:10)
does automatically, posting to the **#valheim-server-status** channel webhook
(`/etc/home-server/discord-server-status.env`). That one webhook is shared by all three
Valheim Discord feeds: `hs-valheim-status` (hourly up/down + players),
`hs-mod-list` (this daily inventory), and `hs-mod-check-discord` (mod version-update
alerts). See [[valheim-server]].
