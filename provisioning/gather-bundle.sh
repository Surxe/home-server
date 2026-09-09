#!/bin/bash
# gather-bundle.sh — build the offline "first-contact" bundle for a new home-server box.
#
# Run this on ANY working Debian box that matches the target's release (the target is
# Proxmox VE 9 = Debian 13 "trixie", so run it on a trixie box — e.g. the dev
# workstation). It downloads the wifi userspace + common firmware as .debs and drops a
# pristine copy of this repo alongside them, onto a destination you then carry to the
# new machine (a flashdrive).
#
# The bundle solves the cold-start chicken-and-egg: a fresh Proxmox box has no wifi
# client and therefore no internet, so it cannot apt-install the wifi client. This
# bundle carries it. Everything else (Debian cloud image, Node/Claude, mods) the box
# fetches itself once first-contact.sh brings it online — see NEW-DEVICE.md.
#
# Usage:  ./gather-bundle.sh /path/to/flash-mount
#         (creates /path/to/flash-mount/home-server-bundle/)
set -euo pipefail

DEST="${1:-}"
[ -n "$DEST" ] || { echo "usage: $0 <destination-dir, e.g. a flash mountpoint>"; exit 1; }
[ -d "$DEST" ] || { echo "destination not found: $DEST"; exit 1; }

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="$DEST/home-server-bundle"
DEBS="$BUNDLE/wifi-debs"

# The target is trixie; warn (don't hard-fail) if this box differs, since the .debs
# must match the target's release to install cleanly.
if . /etc/os-release 2>/dev/null && [ "${VERSION_CODENAME:-}" != "trixie" ]; then
  echo "WARNING: this box is '${VERSION_CODENAME:-unknown}', target is trixie."
  echo "         The wifi .debs must match the target release. Continue only if you know they line up."
  read -rp "         Proceed anyway? [y/N] " a; [ "$a" = y ] || exit 1
fi

echo "== Preparing $BUNDLE"
mkdir -p "$DEBS"

# Generic WPA userspace (hardware-independent) — the exact set that was missing on a
# fresh Proxmox install. libnl trio + libpcsclite1 are wpasupplicant's non-base deps.
WIFI_PKGS=(wpasupplicant iw rfkill wireless-regdb
           libnl-3-200 libnl-genl-3-200 libnl-route-3-200 libpcsclite1)
# Common wifi-chip firmware (device-specific; best-effort — the base install often
# already has what a given chip needs, but bundling covers a different future laptop).
FW_PKGS=(firmware-iwlwifi firmware-realtek firmware-misc-nonfree)

echo "== Downloading WPA userspace .debs"
( cd "$DEBS" && apt-get download "${WIFI_PKGS[@]}" )

echo "== Downloading common wifi firmware .debs (best-effort)"
for p in "${FW_PKGS[@]}"; do
  ( cd "$DEBS" && apt-get download "$p" ) 2>/dev/null \
    && echo "   + $p" \
    || echo "   - $p unavailable here (enable the non-free-firmware component to include it) — skipped"
done

echo "== Snapshotting the repo (committed state) -> home-server-repo.tar.gz"
git -C "$REPO" archive --format=tar.gz --prefix=home-server/ -o "$BUNDLE/home-server-repo.tar.gz" HEAD

echo "== Copying the new-device runbook to the bundle root"
cp "$REPO/provisioning/NEW-DEVICE.md"        "$BUNDLE/NEW-DEVICE.md"
cp "$REPO/provisioning/offline-bundle.manifest" "$BUNDLE/offline-bundle.manifest"

sync
echo
echo "Bundle ready at: $BUNDLE"
echo "  wifi-debs/            $(ls "$DEBS" | wc -l) packages"
echo "  home-server-repo.tar.gz  (contains provisioning/first-contact.sh + bootstrap.sh)"
echo
echo "Next: safely unmount the flash, take it to the new box, and follow NEW-DEVICE.md."
