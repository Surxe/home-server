#!/bin/bash
# first-contact.sh — get a fresh, OFFLINE Proxmox box onto wifi, from the flash bundle.
#
# This is the one step that cannot be scripted from within the repo alone, because a
# bare Proxmox box has no wifi client and no internet to install one. Run it from the
# bundle that gather-bundle.sh produced. It:
#   1. installs the ferried wifi .debs (dpkg, offline),
#   2. switches Proxmox's apt repos from enterprise (401) to no-subscription,
#   3. brings wifi up at runtime from a prompted SSID/passphrase,
#   4. extracts the repo to /srv/dev/repos/home-server.
# It does NOT make wifi persistent and does NOT reboot — that's bootstrap.sh's job,
# which you run next (it installs home-server-wifi.service). See NEW-DEVICE.md.
#
# Run as root, from inside the bundle dir:  sudo ./first-contact.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run as root (sudo)"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"          # the bundle root on the flash
say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

say "1. Install ferried wifi packages (offline)"
if compgen -G "$HERE/wifi-debs/*.deb" >/dev/null; then
  dpkg -i "$HERE"/wifi-debs/*.deb || { echo "dpkg reported missing deps — list them and add to the bundle"; exit 1; }
else
  echo "no .debs found at $HERE/wifi-debs/ — is this the bundle dir?"; exit 1
fi

say "2. Fix Proxmox apt repos (enterprise 401 -> no-subscription)"
SL=/etc/apt/sources.list.d
for f in pve-enterprise.sources ceph.sources; do
  [ -f "$SL/$f" ] && mv "$SL/$f" "$SL/$f.disabled" && echo "  disabled $f"
done
if [ ! -f "$SL/pve-no-subscription.sources" ]; then
  cat > "$SL/pve-no-subscription.sources" <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
  echo "  added pve-no-subscription.sources"
fi

say "3. Bring wifi up"
# Detect the wireless interface (name varies per device: wlp1s0, wlp2s0, wlan0, ...).
WIF="$(for d in /sys/class/net/*/wireless; do [ -e "$d" ] && basename "$(dirname "$d")"; done | head -1)"
[ -n "$WIF" ] || { echo "no wireless interface found (is the wifi driver/firmware present? check 'dmesg | grep -i firmware')"; exit 1; }
echo "  wireless interface: $WIF"
rfkill unblock wifi 2>/dev/null || true

read -rp "  wifi SSID: " SSID
read -rsp "  wifi password: " PSK; echo
CONF="/etc/wpa_supplicant/wpa_supplicant-$WIF.conf"
install -d /etc/wpa_supplicant
wpa_passphrase "$SSID" "$PSK" > "$CONF"
chmod 600 "$CONF"
echo "  wrote $CONF"

ip link set "$WIF" up
# kill any stale supplicant on this iface, then start fresh
pkill -f "wpa_supplicant.*-i$WIF" 2>/dev/null || true
wpa_supplicant -B -i "$WIF" -c "$CONF"
echo "  associating..."; sleep 6
iw "$WIF" link | grep -q "Connected to" || { echo "  NOT associated — likely wrong SSID/password. Re-run."; exit 1; }
dhclient "$WIF"

say "4. Verify internet"
if ping -c2 -W3 1.1.1.1 >/dev/null 2>&1; then echo "  online."; else
  echo "  associated but no route — check 'ip route' for a stale installer default via vmbr0 and delete it."; fi

say "5. Extract the repo"
DEST=/srv/dev/repos
install -d "$DEST"
if [ -d "$DEST/home-server" ]; then
  echo "  $DEST/home-server already present — leaving it."
elif [ -f "$HERE/home-server-repo.tar.gz" ]; then
  tar -xzf "$HERE/home-server-repo.tar.gz" -C "$DEST"
  echo "  extracted -> $DEST/home-server"
else
  echo "  no home-server-repo.tar.gz in bundle; clone it once online instead."
fi

cat <<EOF

first-contact done. You are online at runtime (NOT yet persistent).
Next:
  1. cd $DEST/home-server && sudo ./bootstrap.sh   # makes wifi + config persistent
  2. Reboot and confirm it comes back online on its own.
  3. Continue with the online steps in provisioning/NEW-DEVICE.md.
EOF
