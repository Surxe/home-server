#!/bin/bash
# create-vm.sh — generic Proxmox VM creator from a Debian cloud image + a cloud-init
# snippet. The reusable mechanism behind guest provisioning on this host; per-guest
# specifics (VMID, name, specs, IP, image, cloud-init file) come in as env vars, so a
# guest repo can ship a thin wrapper that sets them and calls this (see the valheim-server
# repo's guests/create-valheim-vm.sh).
#
# Idempotent-ish: refuses if the VMID already exists (destroy it first to rebuild).
#
# Required env:  VMID  VM_NAME  IPCFG  IMG  SNIPPET_SRC
# Optional env (defaults shown):
#   MEM=2048  CORES=2  DISK_GROW=+28G  BRIDGE=vmbr0  NAMESERVER=1.1.1.1
#   STORAGE=local-lvm  SNIPPET_NAME=$(basename "$SNIPPET_SRC")
set -euo pipefail

: "${VMID:?set VMID}"
: "${VM_NAME:?set VM_NAME}"
: "${IPCFG:?set IPCFG (e.g. ip=192.168.100.10/24,gw=192.168.100.1)}"
: "${IMG:?set IMG (path to the Debian cloud .qcow2)}"
: "${SNIPPET_SRC:?set SNIPPET_SRC (path to the cloud-init yaml)}"

MEM="${MEM:-2048}"
CORES="${CORES:-2}"
DISK_GROW="${DISK_GROW:-+28G}"      # cloud image is ~2G; grow to ~30G
BRIDGE="${BRIDGE:-vmbr0}"
NAMESERVER="${NAMESERVER:-1.1.1.1}"
STORAGE="${STORAGE:-local-lvm}"
SNIPPET_NAME="${SNIPPET_NAME:-$(basename "$SNIPPET_SRC")}"
SNIPPET_DIR=/var/lib/vz/snippets

if qm status "$VMID" >/dev/null 2>&1; then
  echo "VM $VMID already exists. To rebuild: qm stop $VMID; qm destroy $VMID --purge"; exit 1
fi
[ -f "$IMG" ] || { echo "cloud image missing: $IMG"; exit 1; }
[ -f "$SNIPPET_SRC" ] || { echo "cloud-init snippet missing: $SNIPPET_SRC"; exit 1; }

# snippets content type must be enabled on 'local'
pvesm set local --content backup,iso,vztmpl,snippets 2>/dev/null || true
install -d "$SNIPPET_DIR"
cp -v "$SNIPPET_SRC" "$SNIPPET_DIR/$SNIPPET_NAME"

qm create "$VMID" \
  --name "$VM_NAME" --memory "$MEM" --cores "$CORES" --cpu host \
  --net0 "virtio,bridge=${BRIDGE}" \
  --scsihw virtio-scsi-single --serial0 socket --vga serial0 \
  --agent enabled=1 --ostype l26 --onboot 1

qm set "$VMID" --scsi0 "${STORAGE}:0,import-from=${IMG}"
qm set "$VMID" --boot order=scsi0
qm set "$VMID" --ide2 "${STORAGE}:cloudinit"
qm set "$VMID" --ipconfig0 "$IPCFG"
qm set "$VMID" --nameserver "$NAMESERVER"
qm set "$VMID" --cicustom "user=local:snippets/${SNIPPET_NAME}"
qm resize "$VMID" scsi0 "$DISK_GROW"

echo "Created VM $VMID ($VM_NAME). Start with: qm start $VMID"
