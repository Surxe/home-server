#!/bin/bash
# create-valheim-vm.sh — (re)create the Valheim VM from the Debian 13 cloud image.
# Idempotent-ish: refuses if the VMID already exists (destroy it first to rebuild).
set -euo pipefail

VMID="${VMID:-100}"
NAME=valheim
MEM=4096
CORES=3
DISK_GROW=+28G                     # cloud image is ~2G; grow to ~30G
BRIDGE=vmbr0
IPCFG="ip=192.168.100.10/24,gw=192.168.100.1"
NAMESERVER="1.1.1.1"
STORAGE=local-lvm
IMG="${IMG:-/home/dev/vmimg/debian-13-genericcloud-amd64.qcow2}"
SNIPPET_SRC="$(cd "$(dirname "$0")" && pwd)/cloud-init-valheim.yaml"
SNIPPET_DIR=/var/lib/vz/snippets

if qm status "$VMID" >/dev/null 2>&1; then
  echo "VM $VMID already exists. To rebuild: qm stop $VMID; qm destroy $VMID --purge"; exit 1
fi
[ -f "$IMG" ] || { echo "cloud image missing: $IMG"; exit 1; }

# snippets content type must be enabled on 'local'
pvesm set local --content $(pvesm status -content snippets >/dev/null 2>&1 && echo backup,iso,vztmpl,snippets || echo backup,iso,vztmpl,snippets) 2>/dev/null || true
install -d "$SNIPPET_DIR"
cp -v "$SNIPPET_SRC" "$SNIPPET_DIR/cloud-init-valheim.yaml"

qm create "$VMID" \
  --name "$NAME" --memory "$MEM" --cores "$CORES" --cpu host \
  --net0 "virtio,bridge=${BRIDGE}" \
  --scsihw virtio-scsi-single --serial0 socket --vga serial0 \
  --agent enabled=1 --ostype l26 --onboot 1

qm set "$VMID" --scsi0 "${STORAGE}:0,import-from=${IMG}"
qm set "$VMID" --boot order=scsi0
qm set "$VMID" --ide2 "${STORAGE}:cloudinit"
qm set "$VMID" --ipconfig0 "$IPCFG"
qm set "$VMID" --nameserver "$NAMESERVER"
qm set "$VMID" --cicustom "user=local:snippets/cloud-init-valheim.yaml"
qm resize "$VMID" scsi0 "$DISK_GROW"

echo "Created VM $VMID. Start with: qm start $VMID"
