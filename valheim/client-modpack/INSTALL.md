# BaldurianQuat — Valheim client mods (install guide)

> ⚠️ **Valheim 1.0 mod set.** Required: **ModSentry, Drop That, Jotunn, BetterCarts,
> OneMapToRuleThemAll**; plus **FarmGrid**, **FirstPersonMode**, and **FavoriteItems** (optional).
> Still **removed on 1.0** and NOT to be installed: **GlassPieces** (crashes on 1.0) and
> **Huginn Map** (loads but its map-share/boat features are broken on 1.0). Both will return
> once they ship a real 1.0 build.

To join the **BaldurianQuat** server you must run this **exact** mod set. The server
(ModSentry) checks every mod's version + hash and **kicks any client that doesn't match** —
so install exactly these versions and don't let mods auto-update.

The **server password** and the **join code** are shared separately (not in this doc).
The join code is a crossplay code and **changes whenever the server restarts** (e.g. on
update days). Good news: once you've joined once, Valheim remembers the server in your
**Join Game list**, and you can **rejoin from there without re-entering a code** even
after it rotates. The rotating code only matters for your **first** join (or if you
clear/lose the saved entry) — so a freshly-shared code is mainly for new players.

---

## The mods (exact versions — must match the server)

| Mod | Version | Thunderstore package | Install? |
|---|---|---|---|
| BepInEx pack | 5.4.2350 | denikson / BepInExPack_Valheim | ✅ yes (dependency) |
| ModSentry | 1.0.18 | Landoria / ModSentry | ✅ required |
| Drop That | 3.1.5 | ASharpPen / Drop_That | ✅ required |
| Jotunn (library) | 2.30.0 | ValheimModding / Jotunn | ✅ required (1.0 build) |
| BetterCarts | 1.1.1 | TastyChickenLegs / BetterCarts | ✅ required |
| OneMapToRuleThemAll | 2.8.1 | DrummerCraig / OneMapToRuleThemAll | ✅ required |
| FarmGrid | 1.0.0 | Galateam / FarmGrid | ➖ optional |
| FirstPersonMode | 1.3.12 | Azumatt / FirstPersonMode | ➖ optional |
| FavoriteItems | 1.1.0 | ronaldoniz / FavoriteItems | ➖ optional |
| GlassPieces | 1.2.5 | blacks7ar / GlassPieces | ❌ **skip — crashes on 1.0** |
| Huginn Map | 1.0.5 | NightOfGames / Huginn_Map | ❌ **skip — broken on 1.0** |

**Current required set (Valheim 1.0):** ModSentry, Drop That, Jotunn, BetterCarts, OneMapToRuleThemAll.
**FarmGrid** (build-placement grid), **FirstPersonMode** (first-person camera), and **FavoriteItems**
(Alt-click to mark inventory stacks as favorites) are optional — install whichever you want, skip the
rest; each is a personal preference and either way you can join. The two marked ❌ are **removed** on
1.0 (see the notice at the top) — do not install them until Ethan confirms they have a real 1.0 build.

---

## Method A — r2modman / Thunderstore Mod Manager (recommended, easiest)

Cross-platform, handles BepInEx for you, and pulls the exact files (so hashes match).

1. Install **r2modman** (or Thunderstore Mod Manager) and pick **Valheim**.
2. Create a new profile, e.g. `BaldurianQuat`.
3. Install each package above **at the exact version listed** (use the package's
   *Versions* tab if it defaults to a newer one). Installing Jotunn and Drop That will
   offer BepInEx as a dependency — accept it (5.4.2350).
4. Launch **Start Modded** once, load any world, then quit (lets the mods initialize).
5. Launch modded → Join Game → **Join by code** → enter the code → enter the password
   (code + password shared separately).

Do **not** click "update" on these mods later — versions must stay pinned to the server.

---

## Method B — Manual install (download the DLLs from Thunderstore)

Use this if you already have BepInEx set up, or prefer manual.

1. Install **BepInExPack_Valheim 5.4.2350** into your Valheim folder first
   (from Thunderstore: denikson / BepInExPack_Valheim). On Windows this means copying
   `winhttp.dll`, `doorstop_config.ini`, and the `BepInEx/` folder into the game dir
   (…/steamapps/common/Valheim). Launch once so BepInEx generates its folders, then quit.
2. For each mod in the table above, open its Thunderstore page, switch to the exact
   **version listed**, and download the zip. Extract its `.dll` into your game's
   `…/Valheim/BepInEx/plugins/` folder. (Skip the three optional mods if you don't want
   them — install the rest, they're required.)
3. Launch the game once, then quit.
4. Join: Join by code → enter the code → enter the password (both shared separately).

The exact SHA-256 for each mod's DLL is in `../mods.manifest` (the server enforces the same
hashes) if you want to verify a download by hand.

---

## If you get disconnected immediately

That's almost always ModSentry rejecting a mod mismatch (not a network issue):
- Make sure you have **all five required mods (ModSentry, Drop That, Jotunn, BetterCarts,
  OneMapToRuleThemAll) at the exact versions** above — a missing, extra, or wrong-version mod
  gets you kicked. (FarmGrid, FirstPersonMode, and FavoriteItems are allowed but optional;
  GlassPieces and Huginn Map are **not** allowed on 1.0 — remove them.)
- Remove any other Valheim mods for this profile — **extra** mods are rejected too.
- If you have ModSentry installed, it will tell you on-screen exactly what's wrong.
- Double-check you used the **current** join code (it changes on server restart).
