#!/bin/bash
# build-modpack.sh — assemble the BaldurianQuat client modpack zip from the verified,
# hash-pinned DLLs in ../dll/. Output: a BepInEx/plugins/ layout + INSTALL.md + SHA256SUMS.
# Usage: ./build-modpack.sh [output-dir]   (default /tmp/BaldurianQuat-modpack)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DLL="$HERE/../dll"
OUT="${1:-/tmp/BaldurianQuat-modpack}"
# Client-side set = mods.manifest required + optional (must match the server policy).
# Valheim 1.0: ModSentry, DropThat, Jotunn, BetterCarts, OneMapToRuleThemAll (required)
# + FarmGrid, FirstPersonMode (optional, 2026-09-11). GlassPieces and Huginn Map are
# DISABLED on 1.0 (see ../mods.manifest) — not here.
CLIENT_DLLS=(Landoria.ModSentry.dll Valheim.DropThat.dll Jotunn.dll BetterCarts.dll OneMapToRuleThemAll.dll FarmGrid.dll FirstPersonMode.dll)
rm -rf "$OUT"; mkdir -p "$OUT/BepInEx/plugins"
for d in "${CLIENT_DLLS[@]}"; do cp "$DLL/$d" "$OUT/BepInEx/plugins/$d"; done
cp "$HERE/INSTALL.md" "$OUT/INSTALL.md"
( cd "$OUT/BepInEx/plugins" && sha256sum *.dll ) > "$OUT/SHA256SUMS.txt"
python3 - "$OUT" <<'PY'
import zipfile,os,sys
root=sys.argv[1]; z=root+".zip"
with zipfile.ZipFile(z,"w",zipfile.ZIP_DEFLATED) as zf:
    for dp,_,fs in os.walk(root):
        for f in fs:
            full=os.path.join(dp,f)
            zf.write(full, os.path.join(os.path.basename(root), os.path.relpath(full,root)))
print("built",z)
PY
