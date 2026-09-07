#!/bin/bash
# home-server wifi bring-up — reproduces the known-good runtime sequence so wifi
# survives reboot. Installed to /usr/local/sbin/hs-wifi-up.sh, run by
# home-server-wifi.service at boot. Idempotent: safe to re-run.
set -u
IFACE=wlp1s0
CONF=/etc/wpa_supplicant/wpa_supplicant-${IFACE}.conf

# Wait for the netdev to exist (the wifi driver creates it slightly after boot).
# The unit is also gated on the .device unit, but this makes the script safe alone.
for _ in $(seq 1 60); do
    [ -e "/sys/class/net/${IFACE}" ] && break
    sleep 1
done
[ -e "/sys/class/net/${IFACE}" ] || { echo "FATAL: ${IFACE} never appeared" >&2; exit 1; }

/usr/sbin/rfkill unblock wifi 2>/dev/null || true
/usr/sbin/ip link set "$IFACE" up 2>/dev/null || true

# Start wpa_supplicant for this iface only if not already running for it.
if ! pgrep -f "wpa_supplicant.*-i[ ]*${IFACE}" >/dev/null 2>&1; then
    /usr/sbin/wpa_supplicant -B -i "$IFACE" -c "$CONF"
fi

# Wait up to 30s for association (carrier).
for _ in $(seq 1 30); do
    if /usr/sbin/iw dev "$IFACE" link 2>/dev/null | grep -q "Connected to"; then
        break
    fi
    sleep 1
done

# Obtain/renew a DHCP lease (dhclient daemonizes and handles renewals).
if ! pgrep -f "dhclient.*${IFACE}" >/dev/null 2>&1; then
    /usr/sbin/dhclient "$IFACE"
fi
