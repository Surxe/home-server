# BaldurianQuat client modpack

> ⚠️ **Valheim 1.0 (2026-09-09): do NOT install Jotunn, Huginn Map, or FarmGrid right now.**
> The 1.0 update broke **Jotunn 2.29.2**, and Huginn Map + FarmGrid depend on it — installing
> them will stop you loading into the server. The current joinable set is **ModSentry, DropThat,
> GlassPieces** only. Ethan will let Claude know when Jotunn ships a 1.0 build, and this pack +
> the server policy will be updated together. See `../mods.manifest` for details.

The mod set friends install to join the server. Byte-identical to the server policy
(ModSentry enforces version + SHA-256), sourced from ../dll/ (hash-pinned in ../mods.manifest).

- `INSTALL.md` — install guide (r2modman + manual), server password, join-code note.
- `SHA256SUMS.txt` — expected DLL hashes for verification.
- `build-modpack.sh` — assembles the distributable zip from ../dll/.

Client set (Valheim 1.0, current): **ModSentry, DropThat, GlassPieces** (required).
Temporarily removed until Jotunn is 1.0-compatible: ~~Jotunn, Huginn Map, FarmGrid~~.
