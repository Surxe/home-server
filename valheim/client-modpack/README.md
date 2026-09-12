# BaldurianQuat — Valheim client mods (documentation)

> ⚠️ **Valheim 1.0 mod set.** Required: **ModSentry, Drop That, Jotunn, BetterCarts,
> OneMapToRuleThemAll**; plus **FarmGrid**, **FirstPersonMode**, and **FavoriteItems** (optional).
> Still removed on 1.0: **GlassPieces** (throws a TypeLoadException on 1.0) and **Huginn Map**
> (loads but its map-share/boat features use game APIs 1.0 removed) — both need a real 1.0
> rebuild before they come back. See `../mods.manifest` for full status.

This directory is **documentation only** — there is no distributable modpack zip and no
setup/build script. The server enforces the mod set itself (ModSentry compares each client's
mod versions + SHA-256 against the server policy), so the source of truth for what clients
must install is the server plus the tables below.

- `INSTALL.md` — the client install guide: required vs optional mods at their exact pinned
  versions (Thunderstore packages), how to install via r2modman or manually, and the
  join-code / password notes.
- `../mods.manifest` — the authoritative manifest the server enforces (mod name, version,
  SHA-256, role, Thunderstore download URL).

**Client set (Valheim 1.0, current):** **ModSentry, Drop That, Jotunn, BetterCarts,
OneMapToRuleThemAll** (required) + **FarmGrid**, **FirstPersonMode**, **FavoriteItems**
(optional). Removed until they ship a 1.0 build: ~~GlassPieces, Huginn Map~~.
