#!/usr/bin/env bash
# wrf-gpu/install.sh — host GPU/export dependencies for the WRF pipeline's
# EXPORT/mapper stage, as config-as-code. Idempotent; run as root (called by
# ../install.sh).
#
# The mapper launches WR:Frontiers under Proton via `gamescope --backend headless`,
# which needs a working Vulkan driver + gamescope + the dev user in the GPU groups
# with a persistent XDG_RUNTIME_DIR. On the workstation these come "for free"
# alongside its NVIDIA stack; this box is a headless AMD Renoir/Vega iGPU (amdgpu,
# /dev/dri/renderD128) where NONE of it was installed. This script installs the AMD
# equivalents — pure Debian packages, no proprietary driver:
#
#   * RADV Vulkan driver (mesa-vulkan-drivers) + vulkan-tools (for vulkaninfo)
#   * gamescope — NOT in trixie main; it ships in trixie-backports/contrib, so we
#     drop in the backports apt source (apt/debian-backports.sources) and pull it
#     from there (matches WRFrontiers-Exporter/README.md's documented install).
#   * dev in the render+video groups, and loginctl linger so /run/user/<uid> is
#     always present for the headless gamescope session (a fresh `sudo -u dev`
#     initgroups is what actually grants the groups to the mapper run).
#
# It does NOT touch /srv/dev/wrf, Proton, or the game download — those live on the
# dedicated WRF volume (provisioned separately) and in WRF-Compat-Tools.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "wrf-gpu/install.sh: run as root"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"

say() { printf '\n\033[1m-- %s\033[0m\n' "$*"; }

DEV_USER=dev
BACKPORTS_SRC=/etc/apt/sources.list.d/debian-backports.sources
RUNTIME_PKGS=(mesa-vulkan-drivers vulkan-tools)   # RADV + vulkaninfo, from trixie main
BACKPORTS_PKGS=(gamescope)                          # from trixie-backports

need_update=0

# 1. Backports apt source (deb822). Copy only if absent/changed, and remember to
#    refresh the apt cache when we do.
say "wrf-gpu: ensuring trixie-backports apt source"
if ! cmp -s "$HERE/apt/debian-backports.sources" "$BACKPORTS_SRC"; then
  install -m 0644 "$HERE/apt/debian-backports.sources" "$BACKPORTS_SRC"
  echo "  installed $BACKPORTS_SRC"
  need_update=1
else
  echo "  $BACKPORTS_SRC already current"
fi

# 2. Install the runtime Vulkan stack (idempotent — apt no-ops if satisfied). Refresh
#    the cache first if we just added the backports source, or if gamescope (our
#    backports canary) isn't present yet.
if ! dpkg -s gamescope >/dev/null 2>&1; then need_update=1; fi
if [ "$need_update" = 1 ]; then
  say "wrf-gpu: apt-get update"
  apt-get update
fi

say "wrf-gpu: installing RADV + vulkan-tools (trixie main)"
DEBIAN_FRONTEND=noninteractive apt-get install -y "${RUNTIME_PKGS[@]}"

say "wrf-gpu: installing gamescope (trixie-backports)"
DEBIAN_FRONTEND=noninteractive apt-get install -y -t trixie-backports "${BACKPORTS_PKGS[@]}"

# 3. GPU group membership + persistent runtime dir for dev. usermod re-add and
#    enable-linger are both idempotent.
say "wrf-gpu: granting dev the render+video groups"
usermod -aG render,video "$DEV_USER"
id "$DEV_USER"

say "wrf-gpu: enabling loginctl linger for dev (persistent /run/user/<uid>)"
loginctl enable-linger "$DEV_USER"
loginctl show-user "$DEV_USER" 2>/dev/null | grep -iE 'UID|Linger|RuntimePath' || true

# 4. Verify the stack the mapper needs is actually present.
say "wrf-gpu: verifying"
ok=1
# gamescope installs to /usr/games (not on root's default PATH); the mapper prepends
# /usr/games itself, so check the absolute path rather than `command -v`.
GAMESCOPE_BIN=/usr/games/gamescope
if [ -x "$GAMESCOPE_BIN" ]; then
  echo "  gamescope: $("$GAMESCOPE_BIN" --version 2>&1 | grep -o 'gamescope version.*' | head -1)"
else
  echo "  !! gamescope missing at $GAMESCOPE_BIN"; ok=0
fi
if ls /usr/share/vulkan/icd.d/radeon_icd*.json >/dev/null 2>&1; then
  echo "  RADV ICD: $(ls /usr/share/vulkan/icd.d/radeon_icd*.json)"
else
  echo "  !! RADV ICD (radeon_icd) not found under /usr/share/vulkan/icd.d/"; ok=0
fi
[ "$ok" = 1 ] && echo "wrf-gpu: install done." || { echo "wrf-gpu: install INCOMPLETE — see warnings above" >&2; exit 1; }
