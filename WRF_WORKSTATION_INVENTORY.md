# WRF GPU/mapper stack — workstation inventory (for the home-server port)

Authoritative read-only inventory of the WRF patch-day pipeline's **EXPORT/mapper**
stack as it exists today on the workstation (`ethan-debian`, Debian 13 trixie).
Produced to let the home-server session replicate the stack as **config-as-code**
in the `home-server` repo without re-deriving anything.

Every fact below is tagged **PORTABLE** (GPU-agnostic — copies as-is), **NVIDIA-SPECIFIC**
(needs an AMD/RADV equivalent, named where known), or **UNSURE**. Secrets are referenced
by location only, never by value.

---

## 1. OS/kernel baseline

**PORTABLE** (server is also Debian 13 trixie, so this is the natural diff target).

```text
$ uname -a
Linux ethan-debian 6.12.107+deb13-amd64 #1 SMP PREEMPT_DYNAMIC Debian 6.12.107-1 (2026-08-29) x86_64 GNU/Linux
```

`/etc/os-release`:
```text
PRETTY_NAME="Debian GNU/Linux 13 (trixie)"
VERSION_ID="13"
VERSION_CODENAME=trixie
DEBIAN_VERSION_FULL=13.7
```

- Kernel: `6.12.107+deb13-amd64` (Debian's backports `+deb13` series).
- `lsb_release -a`: Debian GNU/Linux 13 (trixie), Release 13.

---

## 2. GPU hardware + driver stack

**NVIDIA-SPECIFIC** — this whole section is the vendor-specific part the AMD port must swap.

### Hardware
```text
$ lspci -nnk | grep -iA3 -E 'vga|3d'
08:00.0 VGA compatible controller [0300]: NVIDIA Corporation GB205 [GeForce RTX 5070] [10de:2f04] (rev a1)
	Subsystem: ASUSTeK Computer Inc. Device [1043:89f2]
	Kernel driver in use: nvidia
	Kernel modules: nouveau, nvidia_drm, nvidia
```

### Driver
```text
$ nvidia-smi --query-gpu=name,driver_version,vbios_version --format=csv
NVIDIA GeForce RTX 5070, 595.71.05, 98.05.28.00.AD
```

- Driver package: `nvidia-driver` **595.71.05-1**, built from the **open** kernel module
  (`nvidia-kernel-open-dkms 595.71.05-1`). Installed from Debian repos (not NVIDIA's
  runfile) — `nvidia-driver-pinning-595.71.05` confirms the pinned apt path.
- Loaded kernel modules: `nvidia`, `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm`
  (`lsmod | grep -iE 'nvidia|nouveau'`).

### Vulkan ICD + device selection
```text
$ ls /usr/share/vulkan/icd.d/
gfxstream_vk_icd.json  intel_hasvk_icd.json  intel_icd.json  lvp_icd.json
nouveau_icd.json  nvidia_icd.json  radeon_icd.json  virtio_icd.json
```
- `VK_ICD_FILENAMES` is **unset** on the workstation (both in dev's login env and the
  pipeline env) — the loader auto-selects the NVIDIA ICD. The NVIDIA ICD manifest is:
```json
{ "library_path": "libGLX_nvidia.so.0", "api_version": "1.4.329" }
```
- `vulkaninfo --summary` (run as dev with `XDG_RUNTIME_DIR=/run/user/1001`, no DISPLAY):
```text
Vulkan Instance Version: 1.4.309
GPU0: apiVersion=1.4.329  deviceType=DISCRETE_GPU  deviceName=NVIDIA GeForce RTX 5070
      driverID=DRIVER_ID_NVIDIA_PROPRIETARY  driverName=NVIDIA  driverInfo=595.71.05
GPU1: apiVersion=1.4.305  deviceName=llvmpipe (LLVM 19.1.7, 256 bits)
      driverName=llvmpipe  driverInfo=Mesa 25.0.7-2+deb13u1 (LLVM 19.1.7)
```
- Loader version: `libvulkan1` **1.4.309.0-1**; `vulkan-tools` **1.4.304.0+dfsg1-1**.

### Mesa / GL / EGL / VA userspace (relevant because the whole stack is present)
| Package | Version |
| --- | --- |
| `libdrm2` / `libdrm-amdgpu1` / `libdrm-radeon1` | 2.4.124-2 |
| `libegl1` / `libgl1` / `libglvnd0` / `libglx0` | 1.7.0-1+b2 |
| `libegl-mesa0` / `libglx-mesa0` / `libgbm1` / `libgl1-mesa-dri` | 25.0.7-2+deb13u1 |
| `mesa-vulkan-drivers` / `mesa-libgallium` | 25.0.7-2+deb13u1 |
| `mesa-va-drivers` / `mesa-vdpau-drivers` | 25.0.7-2+deb13u1 |
| `libva2` / `libva-drm2` / `libva-x11-2` / `libva-wayland2` | 2.22.0-3 |
| `libegl-nvidia0` / `libglx-nvidia0` / `libgles-nvidia1|2` | 595.71.05-1 |
| `nvidia-vulkan-icd` / `nvidia-egl-icd` | 595.71.05-1 |
| `xwayland` | 2:24.1.6-1 |

### AMD-port note
The AMD equivalent for everything NVIDIA here is **already present** in the same Debian
install: `mesa-vulkan-drivers` (RADV) + `libdrm-amdgpu1` + the `amdgpu` kernel module,
selected via `/usr/share/vulkan/icd.d/radeon_icd.json`. No proprietary driver is involved.
On the server (Renoir/Vega iGPU) the loader would auto-select RADV; if it ever doesn't,
pin it with `VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json`.

---

## 3. gamescope

**PORTABLE** (same package source exists for trixie on the server). The *crash-on-teardown*
behaviour below is the one NVIDIA-specific quirk (and it's harmless, so nothing to port).

- **Provenance:** Debian **trixie-backports/contrib** — NOT built from source.
  ```text
  $ apt-cache policy gamescope
  Installed: 3.16.22+ds-1~bpo13+1
  Candidate: 3.16.22+ds-1~bpo13+1
   *** 3.16.22+ds-1~bpo13+1 100
       100 http://deb.debian.org/debian trixie-backports/contrib amd64 Packages
  ```
- Install command (from `WRFrontiers-Exporter/README.md` "Linux setup"):
  `sudo apt-get -t trixie-backports install gamescope`.
- Binary: `/usr/games/gamescope` (root-owned 0755). Version:
  ```text
  $ /usr/games/gamescope --version
  gamescope version 3.16.22+ds-1~bpo13+1 (gcc 14.2.0)
  ```
- **No reproducible build recipe exists** — it is a stock apt package, so the server just
  installs the same backports package. (The earlier handoff note said gamescope is "not in
  trixie's repos" — more precisely it is not in trixie's *main* archive; it ships in
  `trixie-backports/contrib`, which the Exporter README already documents correctly.)
- **NVIDIA-specific quirk:** on the RTX 5070, gamescope's headless backend segfaults on
  teardown (`failed to read Wayland events: Broken pipe`, exit 139). Harmless for the
  mapper — UE4SS writes the `.usmap` and exits before teardown, and the exporter keys
  success off the `.usmap` existing, not the exit code (see §7). On AMD/RADV this teardown
  crash likely does not occur, but it changes nothing either way.

---

## 4. WRF-Compat-Tools / Proton runtime

**PORTABLE** (Proton/Wine + the TLS patch are GPU-agnostic; DXVK/vkd3d-proton select the
Vulkan ICD at runtime and will pick RADV on the AMD box).

### Where it lives + how it's referenced
- Runtime dir: `/srv/dev/wrf/proton/GE-Proton10-34-WRF-TLS`
  - `version` file: `1774238111 GE-Proton10-34-WRF-TLS`
  - `compatibilitytool.vdf` present; `proton` launcher + `files/` tree present.
- Referenced by the Exporter as `PROTON_PATH`
  (`/srv/dev/wrf/proton/GE-Proton10-34-WRF-TLS` in `WRFrontiers-Exporter/.env`, and
  overridden on every orchestrated run by the orchestrator's derived
  `repos.proton_path` = `WRF_ROOT/proton/GE-Proton10-34-WRF-TLS`).
- Wine prefix: `/srv/dev/wrf/prefix` (`WINE_PREFIX`; created on first launch, currently
  683 MB).

### How it was obtained (config-as-code, reproducible)
Obtained from the `Surxe/WRF-Compat-Tools` repo (`/srv/dev/repos/WRF-Compat-Tools`) via
`Steam/setup.sh --target <dir>`, which re-assembles a split `GE-Proton10-34-WRF-TLS.tar.zst.part-*`
archive from `Steam/runtime/`, verifies `SHA256SUMS`, then verifies the patched
`files/lib/wine/x86_64-unix/ntdll.so` sha256 before installing.

Provenance (`Steam/source/README.md`):
- Base: **GE-Proton10-34** (`GloriousEggroll/proton-ge-custom`), commit `721dd76896b434fe3c1328ea533e0b25b4af04d5`.
- Wine submodule: `ValveSoftware/wine`, commit `1729f00e17e879f98f9df1f2bca86bc5d21a65df`.
- Local patch: `ntdll-rebase-stale-tls-pointers.patch` (applied by
  `patches/protonprep-valve-staging.sh`), verified `ntdll.so` sha256
  `47e9fddf687792d041b2517e7ec24e7b8c0bc393d65b80261237a7c802fa893e`.

The game-specific launch overrides the mapper uses are also GPU-agnostic
(`WINEDLLOVERRIDES="GCLay.dll=d;GCLay64.dll=d;dwmapi=n,b"` and `SteamDeck=1`).

---

## 5. DepotDownloader / Steam (+ BatchExport)

**PORTABLE** (pure CPU/network tools — no GPU).

### DepotDownloader
- Install method: auto-downloaded by the Exporter's `src/dependency_manager.py`
  (`install_depot_downloader`) from `SteamRE/DepotDownloader` GitHub release,
  `DepotDownloader-linux-x64.zip`, extracted to `WRFrontiers-Exporter/src/steam/DepotDownloader/`.
- Version: `version.txt` = `DepotDownloader_3.4.0`.
- Binary: `.../src/steam/DepotDownloader/DepotDownloader` — **ELF x86-64, self-contained**
  (NativeAOT publish; `ldd` links only libc/libstdc++/libgcc/libpthread, no .NET runtime
  libs). No dotnet runtime required. (dotnet 9.0.318 / .NET Core 9.0.20 IS installed
  system-wide for unrelated projects, but DepotDownloader does not use it.)
- Steam credentials come only from env (`STEAM_USERNAME`/`STEAM_PASSWORD`), never argv —
  see §6/§7 for the secret location.

### BatchExport (same dependency step, for completeness)
- `CUE4P-BatchExport` (`Surxe/CUE4P-BatchExport`) v1.5.3, native ELF, at
  `WRFrontiers-Exporter/src/batch_export/BatchExport/`. Linux native libs auto-installed
  next to it by the dependency step: `oodle-data-shared.dll` (OodleUE release
  `2026-06-04-1357`), `Detex.dll` (built from source `hglm/detex`), `libSkiaSharp.so`
  (SkiaSharp 3.119.1 NuGet). All GPU-agnostic.

---

## 6. User / permissions / runtime env

**PORTABLE** — the `render`/`video` groups, `loginctl` linger, and `/dev/dri` ownership are
the standard Linux mechanism for **both** vendors; the server's AMD iGPU exposes the same
`/dev/dri/renderD128` + `card0` nodes and groups.

```text
$ id dev
uid=1001(dev) gid=1002(dev) groups=1002(dev),44(video),992(render),1001(developers)

$ getent group render video developers
render:x:992:dev
video:x:44:ethan,dev
developers:x:1001:ethan,dev
```

- Grant mechanism (config-as-code, documented in
  `my-system/users-and-permissions/groups.md`), applied once by a sudo user:
  ```bash
  sudo usermod -aG render,video dev
  sudo loginctl enable-linger dev
  ```
- Linger / persistent runtime dir:
  ```text
  $ loginctl show-user dev | grep -iE 'Linger|RuntimePath|UID'
  UID=1001  RuntimePath=/run/user/1001  State=lingering  Linger=yes
  $ ls -ld /run/user/1001
  drwx------ 9 dev dev 340 Sep 20 10:19 /run/user/1001
  ```
- Device nodes (Debian default udev; `/etc/udev/rules.d/` is **empty** — no custom rules):
  ```text
  $ ls -la /dev/dri/
  crw-rw----+ 1 root video  226,   0  card0
  crw-rw----+ 1 root render 226, 128  renderD128
  ```

---

## 7. The exact mapper invocation + full environment

This is the section that concentrates the NVIDIA-relevant details — in practice there are
**almost none**: the env carries no `__NV_*`/`__GLX_*`/`MESA_*`/`RADV_*`/`DRI_PRIME`/`VK_ICD_FILENAMES`
values, so the port is mostly "swap the driver, everything else is identical".

### Command (built in `WRFrontiers-Exporter/src/mapper/linux_mapper.py`)
```text
gamescope --backend headless -W 1280 -H 720 -r 60 -- \
  umu-run /srv/dev/wrf/data/steam-download/13_2017027/WRFrontiers/Binaries/Win64/WRFrontiers-Win64-Shipping.exe
```
- `Shipping.exe` confirmed present (187,997,312 bytes).
- gamescope offscreen size is fixed at 1280×720 (`_GAMESCOPE_W/H`), refresh `-r 60`.
- Non-headless variant (`HEADLESS=false`) drops the gamescope wrapper and runs
  `umu-run <exe>` on the ambient `DISPLAY`.

### Environment, composed across three layers
1. **Ethan launcher** `my-system/users/ethan/localbin/wrf-orchestrator` (deployed to
   `~ethan/.local/bin`): sources `~ethan/.config/wrf-orchestrator/secrets.env` (chmod 600,
   ethan-owned) and hops to dev preserving only the three secrets:
   `sudo -u dev --preserve-env=STEAM_USERNAME,STEAM_PASSWORD,GH_DATA_REPO_PAT -H ...`.
   The `env_keep` whitelist is config-as-code in
   `my-system/system/etc-sudoers.d/devbridge-env` (`Defaults:ethan env_keep += "STEAM_USERNAME STEAM_PASSWORD"`, `"GH_DATA_REPO_PAT"`).
2. **dev-side entry** `WRFrontiersDB-Orchestrator/bin/run-pipeline`: sources dev's nvm
   (`$NVM_DIR/nvm.sh`, needed only by the SITE stage's `npm`), `cd`s into the orchestrator,
   `exec`s `.venv/bin/python src/run.py`.
3. **Export stage** `WRFrontiersDB-Orchestrator/src/stages/export.py` — for the mapper
   (when `should_get_mapper` && `headless`) it sets:
   - `XDG_RUNTIME_DIR=/run/user/1001`
   - `PATH=/usr/games:<PATH>` (gamescope lives at `/usr/games/gamescope`, not on dev's PATH)
   - **`DISPLAY` is popped** (pure headless)
   - passes `--wine-prefix /srv/dev/wrf/prefix --proton-path /srv/dev/wrf/proton/GE-Proton10-34-WRF-TLS`
     and the derived steam-download/mapper/exports dirs on the CLI.
4. **Mapper** `linux_mapper.py::_build_env` adds, on top of the inherited env:
   - `WINEPREFIX=/srv/dev/wrf/prefix`
   - `GAMEID=0`
   - `PROTONPATH=/srv/dev/wrf/proton/GE-Proton10-34-WRF-TLS`
   - `WINEDLLOVERRIDES="GCLay.dll=d;GCLay64.dll=d;dwmapi=n,b"` (dwmapi proxy loads UE4SS)
   - `SteamDeck=1`

### Explicitly NOT set (verified against source)
No `VK_ICD_FILENAMES`, no `DRI_PRIME`, no `PROTON_*` beyond `PROTONPATH`, no `MESA_*`/`RADV_*`/`__NV_*`/`__GLX_*`.
`VK_ICD_FILENAMES` is also unset in the ambient environment (§2).

### Validated NVIDIA result (quoted from `my-system/users-and-permissions/groups.md`, 2026-08-22)
```text
sudo -u dev env -i HOME=/home/dev XDG_RUNTIME_DIR=/run/user/1001 \
  PATH=/usr/games:/usr/bin:/bin \
  gamescope --backend headless -W 1280 -H 720 -- <child>
```
…initializes fully (Vulkan picks the NVIDIA device, compositor + Xwayland come up), then
segfaults on teardown (exit 139) — harmless for the mapper.

### UNSURE / decisions the AMD port must make
- Whether the Renoir/Vega iGPU (shared system RAM, far less than the RTX 5070's VRAM) can
  initialize gamescope headless + Proton + the game's D3D (DXVK/vkd3d-proton → RADV) far
  enough for UE4SS to dump the `.usmap`. The mapper only needs engine init + one frame, so
  VRAM pressure is *probably* fine, but this is the single open question and must be tested
  live on the server.
- Nothing in the env is NVIDIA-specific to remove — the difference is purely the driver
  (RADV vs NVIDIA proprietary) and possibly the gamescope teardown behaviour.

---

## 8. Approx. disk footprint (`/srv/dev/wrf`)

```text
$ du -sh /srv/dev/wrf          →  36G
  data/steam-download          →  15G   (DepotDownloader game install)
  data/exports                 →  20G   (full BatchExport JSON run)
  data/textures                → 128M
  data/parsed                  →  29M
  data/mapper                  → 7.1M
  proton/                      → 1.4G
  prefix/                      → 683M
```

- The `steam-download` manifest currently downloaded: `manifest.txt` = `5891357370822898705`.
- **Sizing guidance:** a full patch-day EXPORT (download + BatchExport) holds ~35 GB on the
  workstation; the home-server's dedicated WRF volume should be sized **≥ 40–50 GB** to
  absorb one download + one export in flight.

---

## 9. Already config-as-code vs manual

| Concern | Status | Where |
| --- | --- | --- |
| OS / Debian base | manual (standard install) | — |
| GPU driver (NVIDIA) | manual apt install | `nvidia-driver` 595.71.05-1 (Debian); **AMD box instead uses `mesa-vulkan-drivers` + `amdgpu`** |
| gamescope | manual apt install (backports) | `gamescope` 3.16.22+ds-1~bpo13+1; install cmd documented in `WRFrontiers-Exporter/README.md` |
| `render`/`video` groups + linger | **config-as-code doc**; grant applied once by sudo | `my-system/users-and-permissions/groups.md` (`usermod` + `loginctl enable-linger`) |
| Proton runtime | **config-as-code** (vendored + installer + provenance) | `WRF-Compat-Tools/Steam/setup.sh`, `Steam/runtime/`, `Steam/source/README.md` |
| DepotDownloader / BatchExport / UE4SS / native libs | **config-as-code** (auto-download at runtime) | `WRFrontiers-Exporter/src/dependency_manager.py` |
| Mapper command + env | **config-as-code** | `WRFrontiers-Exporter/src/mapper/linux_mapper.py`, `WRFrontiersDB-Orchestrator/src/stages/export.py`, `src/repos.py` |
| Path derivation (`WRF_ROOT`, `REPOS_DIR`) | **config-as-code** | `WRFrontiersDB-Orchestrator/src/repos.py` |
| Secrets (Steam creds, GH PAT) | manual, ethan-owned, mode 600 | `~ethan/.config/wrf-orchestrator/secrets.env` (location only) |
| Ethan→dev launcher + sudoers whitelist | **config-as-code** | `my-system/users/ethan/localbin/wrf-orchestrator`, `my-system/system/etc-sudoers.d/devbridge-env` |
| nvm for SITE stage | **config-as-code** | `WRFrontiersDB-Orchestrator/bin/run-pipeline` |

### Open items / gaps to flag back
1. **AMD headless-capable mapper is untested** — the one question the workstation cannot
   answer; needs a live gamescope+Proton+UE4SS dump attempt on the Renoir iGPU.
2. **No NVIDIA-specific env/flag to strip** — the port is driver substitution, not
   flag surgery. If the AMD loader ever selects the wrong ICD, force
   `VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.json`.
3. The sudoers **bridge rule** (`NOPASSWD: sudo -u dev`) is not yet captured in
   `my-system` (noted in `devbridge-env`); only the env whitelist is. Replicate the rule
   itself on the server as part of the ethan→dev launcher work.
