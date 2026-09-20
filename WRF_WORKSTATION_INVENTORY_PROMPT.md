# WRF GPU/mapper stack inventory — for the home-server port

**Read this on the workstation (`ethan-debian`) and carry it out in full.**

**Context.** We're porting the WRF patch-day pipeline's **EXPORT/mapper** stage from this
workstation to the **home-server** (an always-on headless Proxmox laptop, Debian 13
trixie). The home-server will run the *full* pipeline, so its GPU + gamescope + Proton
(WRF-Compat-Tools) + DepotDownloader stack must be reproduced there as **config-as-code
checked into the `home-server` repo**.

**Your job:** produce ONE complete, authoritative inventory of how this stack is set up on
THIS workstation, so the home-server session can replicate it without re-deriving anything.
Read existing docs/memory FIRST (don't redo effort — e.g. `my-system/users-and-permissions/
groups.md`, the `WRFrontiers-Exporter` README/source, the `WRF-Compat-Tools` README), then
verify each fact against the live system. **Read-only: install nothing, change nothing.**

**Critical difference to keep front-of-mind.** The workstation GPU is **[confirm exact
model + driver — believed NVIDIA]**; the home-server GPU is an **AMD Renoir (Radeon Vega)
integrated GPU** (`/dev/dri/renderD128`, headless, PVE kernel). For every item below, tag it
**PORTABLE** (GPU-agnostic), **NVIDIA-SPECIFIC** (needs an AMD/RADV equivalent — name it if
you know it), or **UNSURE**. The one genuinely open question on the server side is whether
the AMD iGPU drives headless gamescope+Proton differently, so capture every NVIDIA-specific
driver/flag/env detail an AMD port would have to swap.

For each fact: cite the command you ran + its output, and the config-as-code file path if
there is one. **Do NOT include secret values** (Steam creds, GH PAT) — refer to them by
location only.

## Sections

1. **OS/kernel baseline** — `uname -a`, Debian version (to diff against the server).

2. **GPU hardware + driver stack** — GPU model (`lspci`), graphics driver + exact version,
   loaded kernel modules, the Vulkan ICD in use (`VK_ICD_FILENAMES`, `vulkaninfo --summary`
   driver/device line), mesa version. Full package list **with versions** for the whole GPU
   userspace (vulkan driver + loader + tools, libdrm, EGL/GL, vainfo).

3. **gamescope** — the key unknown (it is NOT in trixie's repos). How was it installed —
   built from source? a third-party/backports repo? a vendored binary/.deb? Give exact
   provenance, `gamescope --version`, the binary path (README says `/usr/games/gamescope` —
   confirm), and **if compiled, the full reproducible build recipe**: source repo + commit,
   build-deps, meson/configure flags, install prefix.

4. **WRF-Compat-Tools / Proton runtime** — how the customized Proton 10 runtime
   (`OwendB1/WRF-Compat-Tools`) is obtained + installed, where it lives on disk, its
   version/commit, how the Exporter references it (path/env), the Proton/wine prefix
   location, and any winetricks/extra deps or first-run setup. Include the repo's own
   README/setup notes.

5. **DepotDownloader / Steam** — install method (package? dotnet tool? vendored binary?),
   version, location, runtime deps (e.g. dotnet runtime version).

6. **User / permissions / runtime env** — `dev`'s uid + group memberships (esp.
   `render`/`video`), how those grants are made config-as-code (cite the mechanism + file),
   how the persistent `XDG_RUNTIME_DIR` is provided (loginctl linger? tmpfiles.d? systemd?)
   and its exact path, plus any udev rules for `/dev/dri`.

7. **The exact mapper invocation** — the precise `gamescope … --backend headless … --
   <proton> …` command line the Exporter/orchestrator runs for the mapper, and the COMPLETE
   environment it runs under: every env var injected or relied on — `XDG_RUNTIME_DIR`,
   `PATH` additions, `VK_ICD_FILENAMES`, `DRI_PRIME`, `PROTON_*`, `STEAM_COMPAT_*`,
   `WINEPREFIX`, `MESA_*`/`RADV_*`/`__NV_*`/`__GLX_*`, gamescope resolution/flags, etc. Pull
   this from the `WRFrontiers-Exporter` source, the orchestrator's export stage, and any live
   launcher. **This section is where NVIDIA-specifics concentrate — flag each one.**

8. **Approx. disk footprint** — size of the Steam depot download (the installed game dir) and
   of a full exports+textures run, so the server can size its dedicated volume.

9. **Already config-as-code vs manual** — for each section, say whether it's already checked
   into a repo (which file) or was done by hand, so the server session knows what's
   authoritative to copy vs what must be authored fresh.

## Before returning
Self-check against this list; only hand back once every section is filled or explicitly
marked N/A. Flag any gap where the AMD port needs a decision the workstation can't answer.
Return the whole thing as one markdown report to bring back to the home-server session.
