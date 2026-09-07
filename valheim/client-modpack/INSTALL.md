# BaldurianQuat — Valheim modpack (client install)

To join the **BaldurianQuat** server you must run this **exact** mod set. The server
(ModSentry) checks every mod's version + hash and **kicks any client that doesn't match** —
so don't mix versions or let mods auto-update.

Server password: **quat-bald-1.0**
Join code: given separately (it's a crossplay code — **it changes whenever the server
restarts**, e.g. on update days, so use the latest one shared).

---

## The mods (exact versions — must match)

| Mod | Version | Thunderstore package |
|---|---|---|
| BepInEx pack | 5.4.2333 | denikson / BepInExPack_Valheim |
| Jotunn (library) | 2.29.2 | ValheimModding / Jotunn |
| ModSentry | 1.0.17 | Landoria / ModSentry |
| Drop That | 3.1.4 | ASharpPen / Drop_That |
| Huginn Map | 1.0.5 | NightOfGames / Huginn_Map |
| GlassPieces | 1.2.5 | blacks7ar / GlassPieces |
| FarmGrid (optional) | 1.0.0 | Galateam / FarmGrid |

FarmGrid is optional (allowed but not required). The other five are required.

---

## Method A — r2modman / Thunderstore Mod Manager (recommended, easiest)

Cross-platform, handles BepInEx for you, and pulls the exact files (so hashes match).

1. Install **r2modman** (or Thunderstore Mod Manager) and pick **Valheim**.
2. Create a new profile, e.g. `BaldurianQuat`.
3. Install each package above **at the exact version listed** (use the package's
   *Versions* tab if it defaults to a newer one). Installing Jotunn and Drop That will
   offer BepInEx as a dependency — accept it (5.4.2333).
4. First launch: **Start Modded** from r2modman, load any world once so Huginn writes
   its config, then quit. (Optional Huginn tweak below.)
5. Launch modded → Join Game → **Join by code** → enter the code → password `quat-bald-1.0`.

Do **not** click "update" on these mods later — versions must stay pinned to the server.

---

## Method B — Manual install (the DLLs in this pack)

Use this if you already have BepInEx set up, or prefer manual.

1. Install **BepInExPack_Valheim 5.4.2333** into your Valheim folder first
   (from Thunderstore: denikson / BepInExPack_Valheim). On Windows this means copying
   `winhttp.dll`, `doorstop_config.ini`, and the `BepInEx/` folder into the game dir
   (…/steamapps/common/Valheim). Launch once so BepInEx generates its folders, then quit.
2. Copy the **six `.dll` files** from `BepInEx/plugins/` in this pack into your game's
   `…/Valheim/BepInEx/plugins/` folder.
3. Launch the game once and load a world (so Huginn writes its config), then quit.
4. Join: Join by code → password `quat-bald-1.0`.

Verify your DLLs match (optional): the SHA-256 of each file is in `SHA256SUMS.txt`.

---

## Optional: Huginn map scan radius

The server crew uses `PoiScanRadius = 10` (default is 30) — a personal display setting,
not enforced. To match: after launching once, edit
`…/Valheim/BepInEx/config/nightofgames.huginn.cfg`, set `PoiScanRadius = 10`, save,
restart the game. (r2modman: Config Editor → Huginn Map.)

---

## If you get disconnected immediately

That's almost always ModSentry rejecting a mod mismatch (not a network issue):
- Make sure you have **all five required mods at the exact versions** above — a missing,
  extra, or wrong-version mod gets you kicked.
- Remove any other Valheim mods for this profile — **extra** mods are rejected too.
- If you have ModSentry installed, it will tell you on-screen exactly what's wrong.
- Double-check you used the **current** join code (it changes on server restart).
