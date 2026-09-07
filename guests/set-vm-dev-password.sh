#!/bin/bash
# set-vm-dev-password.sh — apply the Valheim VM's `dev` break-glass console password
# to the running guest from the host-only secret file. Run once after the VM is up
# (guest agent responding), e.g. as the last step of provisioning / after a rebuild.
#
# The password is NEVER stored in this repo. Secret file (root, 600), also in Ethan's
# password manager:   /etc/home-server/valheim-vm-dev.password
# To (re)generate:  tr -dc 'A-Za-z0-9._-' </dev/urandom | head -c 32 > that file
set -euo pipefail
VMID="${VMID:-100}"
SECRET=/etc/home-server/valheim-vm-dev.password

[ -r "$SECRET" ] || { echo "FATAL: $SECRET missing (create it root:600; store a copy in a password manager)"; exit 1; }
# Transfer via base64 so any password characters survive the guest-exec shell intact.
B64="$(base64 -w0 "$SECRET")"
out="$(qm guest exec "$VMID" -- bash -c "printf 'dev:%s' \"\$(printf %s '$B64' | base64 -d | tr -d '\n')\" | chpasswd")"
echo "$out" | grep -q '"exitcode" : 0' && echo "dev password applied to VM $VMID" || { echo "$out"; exit 1; }
