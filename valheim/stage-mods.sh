#!/bin/bash
# stage-mods.sh — deploy the authoritative mod set into the BepInEx tree with the
# ModSentry policy layout. Runs INSIDE the Valheim VM. Idempotent.
#
# DLL source per mod: ./dll/<dll> if present (byte-exact repo copy); else download the
# pinned Thunderstore zip and extract <dll>. Either way the DLL is SHA-256 verified.
#
#   plugin   -> BepInEx/plugins/<name>/<dll>            (loaded on the server)
#   required -> BepInEx/config/ModSentry_Required/<dll> (hash reference copy)
#   optional -> BepInEx/config/ModSentry_Optional/<dll> (hash reference copy)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="${HERE}/mods.manifest"
DLLDIR="${HERE}/dll"
CACHE="${HERE}/mod-cache"; mkdir -p "$CACHE"
BEPINEX=/srv/valheim/config/bepinex
PLUGINS="${BEPINEX}/plugins"; REQ="${BEPINEX}/config/ModSentry_Required"
OPT="${BEPINEX}/config/ModSentry_Optional"; CFG="${BEPINEX}/config"

[ -d "$BEPINEX" ] || { echo "BepInEx tree missing ($BEPINEX). Start the server once (BEPINEX=true) first."; exit 1; }
mkdir -p "$PLUGINS" "$REQ" "$OPT" "$CFG"
# Clear prior staging so removed mods don't linger.
rm -rf "$PLUGINS/ModSentry" "$PLUGINS/Drop_That" "$PLUGINS/Jotunn" "$PLUGINS/Huginn_Map" \
       "$PLUGINS/GlassPieces" "$PLUGINS/FarmGrid"
rm -f "$REQ"/*.dll "$OPT"/*.dll

resolve_dll() {  # sets DLLPATH for name/dll/sha/url; verifies sha256
  local name="$1" dll="$2" sha="$3" url="$4"
  if [ -f "${DLLDIR}/${dll}" ]; then DLLPATH="${DLLDIR}/${dll}"
  else
    local zip="${CACHE}/${name}.zip"
    [ -f "$zip" ] || curl -sSL -o "$zip" "$url"
    local ex="${CACHE}/${name}"; rm -rf "$ex"; mkdir -p "$ex"; unzip -oq "$zip" -d "$ex"
    DLLPATH="$(find "$ex" -type f -name "$dll" | head -1)"
    [ -n "$DLLPATH" ] || { echo "  $dll not found in $url"; exit 1; }
  fi
  echo "${sha}  ${DLLPATH}" | sha256sum -c - >/dev/null || { echo "  SHA MISMATCH: $dll"; exit 1; }
}

while IFS='|' read -r name version dll sha role url; do
  case "$name" in ''|\#*) continue;; esac
  name="${name//[[:space:]]/}"; dll="${dll//[[:space:]]/}"; sha="${sha//[[:space:]]/}"
  role="${role//[[:space:]]/}"; url="${url//[[:space:]]/}"
  resolve_dll "$name" "$dll" "$sha" "$url"
  case "$role" in *plugin*)  install -D "$DLLPATH" "${PLUGINS}/${name}/${dll}"; echo "plugin   ${name}/${dll}";; esac
  case "$role" in *required*) cp "$DLLPATH" "${REQ}/${dll}"; echo "required ${dll}";;
                  *optional*) cp "$DLLPATH" "${OPT}/${dll}"; echo "optional ${dll}";; esac
done < "$MANIFEST"

[ -f "${HERE}/drop_that.drop_table.cfg" ] && cp "${HERE}/drop_that.drop_table.cfg" "${CFG}/drop_that.drop_table.cfg" && echo "config   drop_that.drop_table.cfg"

# lloesche syncs /config/bepinex/plugins into its runtime tree ADDITIVELY (no delete),
# so removed mods would linger there and still load. Wipe it; it re-syncs from /config
# on container start.
RUNTIME_PLUGINS=/srv/valheim/data/bepinex/BepInEx/plugins
[ -d "$RUNTIME_PLUGINS" ] && rm -rf "$RUNTIME_PLUGINS" && echo "cleared runtime plugin cache (re-syncs from /config on start)"

echo; echo "== plugins (loaded) =="; ls -1 "$PLUGINS"
echo "== ModSentry_Required =="; ls -1 "$REQ"
echo "== ModSentry_Optional =="; ls -1 "$OPT"
echo; echo "Restart to load:  docker compose -f /srv/valheim/docker-compose.yml restart"
