# BaldurianQuat client modpack

> ⚠️ **Valheim 1.0 mod set.** Required: **ModSentry, Drop That, Jotunn, BetterCarts,
> OneMapToRuleThemAll**; plus **FarmGrid** (optional). Still removed on 1.0: **GlassPieces** (throws a TypeLoadException on
> 1.0) and **Huginn Map** (loads but its map-share/boat features use game APIs 1.0 removed) —
> both need a real 1.0 rebuild before they come back. See `../mods.manifest` for full status.

The mod set friends install to join the server. Byte-identical to the server policy
(ModSentry enforces version + SHA-256), sourced from ../dll/ (hash-pinned in ../mods.manifest).

- `INSTALL.md` — install guide (r2modman + manual), server password, join-code note.
- `SHA256SUMS.txt` — expected DLL hashes for verification.
- `build-modpack.sh` — assembles the distributable zip from ../dll/.

Client set (Valheim 1.0, current): **ModSentry, Drop That, Jotunn, BetterCarts,
OneMapToRuleThemAll** (required) + **FarmGrid** (optional). Removed until they ship a 1.0 build:
~~GlassPieces, Huginn Map~~.
