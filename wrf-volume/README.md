# wrf-volume — dedicated `/srv/dev/wrf` data volume for the WRF pipeline

The WRF patch-day pipeline (`WRF_ROOT=/srv/dev/wrf`) holds tens of GB per patch
(steam-download ~15G, exports ~20G, Proton + prefix ~2G, plus textures/parsed/mapper),
and with keep-2 retention (t-0122) roughly double that. That must **not** live on
`pve-root` where a runaway export could wedge the hypervisor, so it gets its own
thick LVM volume, mounted at `/srv/dev/wrf`.

## Layout of this box's disk (single 476G NVMe, one VG `pve`)

`pve-root` was 96G but only ~9.4G used — hugely oversized. There were no free extents
for a separate volume, and root's ext4 cannot be shrunk while mounted. So we shrink it
**offline** and carve a thick data LV from the freed space:

```
pve/root  96G -> 40G     (frees 56G; ~9.4G used, 40G leaves comfortable headroom)
pve/wrf   68G  (new, thick, ext4)  -> mounted at /srv/dev/wrf
```

## Two parts

- **`provision-shrink.sh`** — ONE-TIME. Stages an idempotent, abort-safe initramfs
  one-shot (`initramfs/hook` + `initramfs/premount`) that, on the next boot and while
  root is unmounted, shrinks `pve/root` and creates + formats `pve/wrf`. It rebuilds
  and **verifies** the initramfs but does not reboot. Not wired into `install.sh` — you
  provision once. See the script's printed NEXT steps.

  Safety: the fs is always shrunk before the LV, and the LV only ever reduced to a size
  larger than the fs, so every partial/failed state leaves a mountable root; on any
  error the one-shot logs and lets the normal boot continue. It self-disables once
  `pve/wrf` exists. Remove it after success:
  `rm -f /etc/initramfs-tools/{hooks/wrf-provision,scripts/local-premount/wrf-provision} && update-initramfs -u`.

- **`install.sh`** — PERSISTENT. Ensures the `/srv/dev/wrf` fstab mount (`nofail`) and
  dev ownership. Wired into the top-level `install.sh`; harmless before provisioning
  (the LV simply isn't there yet).
