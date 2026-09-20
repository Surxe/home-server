#!/usr/bin/env bash
# wrf-volume/provision-shrink.sh — ONE-TIME: stage the initramfs one-shot that
# shrinks pve/root (96G -> 40G) and carves the thick pve/wrf (68G) data volume for
# the WRF pipeline, then rebuild + verify the initramfs. It does NOT reboot; the
# shrink happens on the next boot (root must be unmounted). Run as root.
#
# This is deliberately NOT wired into install.sh — you provision the volume once.
# The persistent mount lives in wrf-volume/install.sh (fstab, nofail). After the
# reboot succeeds, remove the one-shot with the cleanup step printed below.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "provision-shrink.sh: run as root"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK=/etc/initramfs-tools/hooks/wrf-provision
PRE=/etc/initramfs-tools/scripts/local-premount/wrf-provision

if lvs pve/wrf >/dev/null 2>&1; then
  echo "pve/wrf already exists — the volume is already provisioned. Nothing to stage."
  echo "(If the one-shot is still installed, remove it: rm -f $HOOK $PRE && update-initramfs -u)"
  exit 0
fi

echo "== staging the WRF-volume initramfs one-shot =="
install -m 0755 "$HERE/initramfs/hook" "$HOOK"
install -m 0755 "$HERE/initramfs/premount" "$PRE"
update-initramfs -u

img="/boot/initrd.img-$(uname -r)"
echo
echo "== verifying $img contains the one-shot + its tools =="
# NB: lsinitramfs's streaming parser fails on this box's uncompressed concatenated-cpio
# initramfs ("unmkinitramfs: cpio failed"), so verify by extracting + searching instead.
vdir="$(mktemp -d)"
trap 'rm -rf "$vdir"' EXIT
unmkinitramfs "$img" "$vdir" >/dev/null 2>&1 || true
miss=0
for f in resize2fs mkfs.ext4 e2fsck; do
  if find "$vdir" -name "$f" 2>/dev/null | grep -q .; then echo "  ok: $f"; else echo "  MISSING: $f"; miss=1; fi
done
if find "$vdir" -path '*/local-premount/wrf-provision' 2>/dev/null | grep -q .; then
  echo "  ok: local-premount/wrf-provision"
else
  echo "  MISSING: local-premount/wrf-provision"; miss=1
fi
if [ "$miss" != 0 ]; then
  echo "!! initramfs is missing pieces — NOT safe to reboot. Aborting." >&2
  exit 1
fi

cat <<EOF

initramfs one-shot staged + verified. It is idempotent and abort-safe (fs shrunk
before LV; any failure leaves root mountable and boot continues).

NEXT (deliberate, human-observed):
  1. Ensure a fresh backup exists (hs-restic-flash).
  2. Gracefully shut down VM 100:   sudo qm shutdown 100
  3. Reboot:                        sudo reboot
     -> on the way up, root shrinks to 40G and pve/wrf (68G) is created + formatted
        BEFORE root mounts.
  4. Back up: verify + finish in a fresh session:
       sudo /srv/dev/repos/home-server/wrf-volume/install.sh   # fstab mount + chown dev
       # confirm, then remove the one-shot so it never runs again:
       sudo rm -f $HOOK $PRE && sudo update-initramfs -u
EOF
