---
name: announce-valheim-mods
description: >-
  Post the current Valheim installed-mod list to the #valheim-server-status Discord channel,
  immediately, after you add/update/remove a mod. Use ONLY once the server has been restarted
  and verified stable (healthy + plugins loaded clean), so the announced list matches what is
  actually running. This is the manual counterpart to the daily hs-mod-list timer.
---

# Announce a Valheim mod change on Discord

When the mod set changes (a mod added, bumped, disabled, or removed via `mods.manifest`),
the daily `hs-mod-list.timer` (09:10) will eventually post the new list — but that can be up
to ~24h away. This skill posts the up-to-date list **now**, deliberately, so the channel
reflects the change as soon as it's actually live.

Do this **only after the server is verified stable from the restart** — otherwise you'd
announce a mod set that isn't really running (e.g. a plugin that failed to load and got
rolled back). The post reads `mods.manifest` (host source of truth), so it's independent of
server state; the stability gate is about *truthfulness*, not a technical dependency.

## Preconditions — all must hold before you post

1. **The mod change is applied.** `mods.manifest` edited, staged to the VM, and the server
   restarted to pick it up — see [restart-valheim](../restart-valheim/SKILL.md) and
   `valheim/stage-mods.sh` / `guests/vm-apply-valheim.sh`.
2. **The server is up and healthy.** The log shows a recent
   `Session ... is active with N player(s)` (the restart-valheim health check).
3. **It's actually stable, not crash-looping.** Wait ~60–90s after "active" and confirm it's
   *still* up, and that the changed plugin(s) loaded clean on the **latest** boot — no
   `TypeLoadException` / "could not be instantiated" / `Method/Field not found` in
   `BepInEx/LogOutput.log` for the last `Chainloader started`. (Per the mod-test recipe in the
   `valheim-server` memory.) If any of these fail, **fix or roll back first — do not post.**

## Post it

Fire the existing oneshot unit — it loads the webhook from
`/etc/home-server/discord-server-status.env` and runs `list-installed-mods.sh --post`, so you
never handle the secret:

```
sudo systemctl start hs-mod-list.service
```

Verify it actually posted (don't just assume):

```
journalctl -u hs-mod-list.service -n 10 --no-pager
```

Success looks like `mod-list: posted N mods (req=… opt=… server-only=…)`. If instead you see
`DISCORD_WEBHOOK_URL not set`, the webhook env isn't staged — that's an unverified/leave-for-Ethan
state, not a failure to retry.

Preview the exact list first (read-only, no post) if you want to eyeball it:

```
/srv/dev/repos/home-server/valheim/list-installed-mods.sh
```

## Notes

- One webhook (`#valheim-server-status`) is shared by all three Valheim feeds; this post is a
  normal embed on that channel — fine to send once per real change, but don't fire it
  repeatedly (no need to re-announce an unchanged list; the daily timer covers routine cadence).
- This is a Claude/host action driven by the manifest, so it also covers a change Ethan or a
  script made to `mods.manifest` — if the manifest changed and the server's stable, the list is
  postable regardless of who edited it.
