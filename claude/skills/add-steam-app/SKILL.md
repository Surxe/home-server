---
name: add-steam-app
description: Search Steam by game/product name and add the chosen app id to the home-server's tracked-apps list (with an optional USD price-alert threshold). Use when the user runs "/add-steam-app <game name>" or asks to add/track a new Steam game for price alerts on the home-server.
---

# add-steam-app

Resolve a game name to a Steam app id and register it in the home-server's
tracked-apps list for the daily price refresh (`hs-steam-price-refresh`).

Arguments: the game/product name to search for (everything after the command).

**Two locations matter:**

- The **generic tracker code** lives in the sibling clone
  `/srv/dev/repos/steam-price-tracker` — run its search/registry CLIs through its
  venv (`.venv/bin/python`). Do not reimplement search or config editing inline.
- The **tracked-app list is config-as-code owned by THIS repo (home-server)** at
  `steam-tracker/tracked_apps.json`. That is the file to edit — NOT the tracker
  clone's gitignored `data/`. Point the registry at it via `STEAM_TRACKER_APPS_PATH`.

Set once for the commands below:

```bash
TRACKER=/srv/dev/repos/steam-price-tracker
APPS=/srv/dev/repos/home-server/steam-tracker/tracked_apps.json
```

## Steps

1. **Search.** Run the search CLI with the user's term:

   ```bash
   cd "$TRACKER"
   .venv/bin/python -m steam_price_tracker.search "<game name>" --limit 10
   ```

   It prints a Markdown table of candidates (`#`, App ID, Type, Name). If it
   prints `_No matching apps found._` (exit code 2), tell the user and ask them
   to refine the name — do not guess an id.

2. **Present & ask.** Put the Markdown table directly into chat and ask the user
   to pick one by number or app id. Do not auto-select, even on a clear top hit —
   the user confirms. (Note `type`: `app` is a game/software; `dlc`, `bundle`,
   `music`, etc. may not be what they want.)

3. **Ask about a price alert (optional).** After they pick, share the app's
   **SteamDB price-history page** so they can pick a sensible target:

   ```
   https://steamdb.info/app/<app_id>/
   ```

   Post the link in chat (do NOT fetch/scrape it). Then ask whether they want a
   USD price-alert threshold — e.g. "alert me at or below $30". This per-app
   threshold is the whole point over a Steam wishlist. Optional; skip if declined.

4. **Register the confirmed choice** into the home-server list. Pass the exact
   product name; include `--threshold <usd>` only if the user gave one:

   ```bash
   cd "$TRACKER"

   # without an alert
   STEAM_TRACKER_APPS_PATH="$APPS" \
     .venv/bin/python -m steam_price_tracker.registry add <app_id> --name "<full product name>"

   # with an alert threshold in USD
   STEAM_TRACKER_APPS_PATH="$APPS" \
     .venv/bin/python -m steam_price_tracker.registry add <app_id> --name "<full product name>" --threshold <usd>
   ```

   **Priceability guard.** `registry add` first probes Steam for a current US
   price. If there is one it prints it (a nice confirmation) and proceeds. If
   Steam lists **no** US price — free, unreleased, region-locked, or a dynamic
   "complete the set" bundle (Steam returns `"data": []` for these) — it
   **refuses and exits 3 without registering**, because such an app can be
   tracked but will never price or alert (and used to crash the whole refresh).
   Surface that to the user; only re-run with `--force` if they explicitly want
   it tracked anyway:

   ```bash
   STEAM_TRACKER_APPS_PATH="$APPS" \
     .venv/bin/python -m steam_price_tracker.registry add <app_id> --name "<full product name>" --force
   ```

   Idempotent: an already-present id reports "already registered" and changes
   nothing. To add/change a threshold later:

   ```bash
   STEAM_TRACKER_APPS_PATH="$APPS" \
     .venv/bin/python -m steam_price_tracker.registry set-threshold <app_id> <usd>
   ```

5. **Commit in home-server.** The list is config-as-code in THIS repo, so remind
   the user to commit `steam-tracker/tracked_apps.json` here. **No reinstall is
   needed** — the `hs-steam-price-refresh` unit reads the file in place at each
   run, so the change is live for the next refresh once committed. (Do not commit
   for them.)

6. **Offer a first price fetch (optional).** Ask whether to pull an initial
   price now. If yes:

   ```bash
   cd "$TRACKER"
   STEAM_TRACKER_APPS_PATH="$APPS" .venv/bin/python -m steam_price_tracker <app_id>
   ```

   This also fetches and stores the product name the first time the app is priced.

## Notes

- The Steam search endpoint is US-scoped (`cc=us`), matching the tracker's
  US-only pricing.
- If the user already gave an exact app id (not a name), skip search and go
  straight to the alert question (step 3) and registration (step 4).
- For machine-readable search output, add `--format json`.
- To run a full refresh by hand (all tracked apps): `sudo systemctl start
  hs-steam-price-refresh.service` and check `journalctl -u hs-steam-price-refresh`.
