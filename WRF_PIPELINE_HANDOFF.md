# WRF pipeline → home-server (handoff)

High-level kickoff for the home-server session. **You (home-server Claude) do the
in-depth research and design; this is just orientation.** Written from the
workstation, where the pipeline lives today.

Source todo: **`t-0118` — "Move WRF pipeline invocation to home server"** (repo:
home-server, tags: wrf, automation).

## The goal, in one line

Today Ethan launches the War Robots: Frontiers patch-day data pipeline **by hand
on the workstation** (`ethan-debian`). We want the **always-on home server** to
be where that pipeline is *invoked* — ideally scheduled/automated — instead of
depending on the workstation being powered on. Exactly how much of the pipeline
*runs* on the home server vs. stays on the workstation is the open question you
need to resolve (see constraints).

## What you don't have yet — clone this first

The home server currently knows nothing about the orchestrator. The system is a
set of sibling repos under `/srv/dev/repos`, driven by one orchestrator:

- **`WRFrontiersDB-Orchestrator`** (`Surxe/WRFrontiersDB-Orchestrator`) — the
  driver. **Read its `README.md` first** — it documents the whole pipeline,
  the secrets model, and the launch wrappers. Start there.
- Its sibling stage repos (the orchestrator calls each repo's
  `.venv/bin/python src/run.py`):
  - `WRFrontiers-Exporter` — EXPORT (Steam download → mapper → BatchExport JSON)
  - `WRFrontiersDB-Parser` — PARSE + PUSH (parse JSON, push to the Data repo)
  - `WRFrontiersDB-Data` — the published data artifact (git repo the parser writes)
  - `WRFrontiersDB-Site` — SITE (`npm run build`)
  - `WRFrontiersDB-Design` — shared design system, vendored by the site as a
    submodule (not a stage the orchestrator runs)

Each sibling repo needs its **own `.venv`**. The orchestrator also has its own
`.venv` + a `.env` (non-secret paths/toggles).

## The pipeline, briefly

```
preflight ─▶ EXPORT ─▶ PARSE ─▶ (PUSH) ─▶ SITE
            (Exporter)  (Parser)          (Astro build)
```

Everything derives from one root: **`WRF_ROOT`** (default `/srv/dev/wrf`) and
`REPOS_DIR`. Working tree layout is in the `wrf-data-structure` memory note.

## Why this is non-trivial (the constraints that shape the design)

**1. The EXPORT stage needs a GPU.** The Exporter's mapper step launches WRF
under Proton via `gamescope --backend headless`, which needs GPU access. On the
workstation, `dev` was put in the `render`+`video` groups with a persistent
`XDG_RUNTIME_DIR` so it runs unattended. **The home server is a headless old
laptop (Proxmox host).** Whether it can run the mapper at all is the single
biggest question. Likely outcomes to research:
   - Split the pipeline: EXPORT stays on the workstation (GPU); PARSE/PUSH/SITE
     (or just the *invocation/scheduling*) move to the home server; **or**
   - The home server triggers the workstation remotely; **or**
   - Full relocation if the laptop's iGPU can drive the headless mapper.

**2. Steam download + disk.** EXPORT does a full DepotDownloader pull of the
game — bandwidth and disk footprint on the laptop matter.

**3. Node/nvm for SITE.** The SITE stage needs `node`/`npm`. The launch is a
non-interactive shell, so nvm must be sourced explicitly (the orchestrator's
`bin/run-pipeline` does this on the workstation).

**4. Secrets + privilege boundary must be replicated.** Three secrets
(`STEAM_USERNAME`, `STEAM_PASSWORD`, `GH_DATA_REPO_PAT`) live **only in ethan's
space**, mode 600, at `~ethan/.config/wrf-orchestrator/secrets.env` — never in
the repo, never readable by `dev`. An **ethan-owned launcher** (`wrf-orchestrator`,
today in `my-system` → `~ethan/.local/bin`) sources them and hops to `dev` via
`sudo -u dev --preserve-env=...`, so `dev` only sees them transiently. Replicating
this ethan→dev launcher pattern on the home server is part of the work.

## What the home server already has (WRF-adjacent)

- `hs-wrf-discount-watch.{service,timer}` — polls the WRF news feed 4×/day and
  dispatches the discount-visualizer on a new weekly discount (see the
  WRFrontiers-News-Scraper repo). Precedent for a WRF systemd feed on this box,
  and a model for how a scheduled WRF job is wired here.
- Deploy model here is **symlink-into-repo** + `install.sh`; new units/launchers
  for the pipeline invocation would be added to *this* repo the same way.

## Pointers

- `WRFrontiersDB-Orchestrator/README.md` + `STANDARDS.md` — authoritative.
- Memory notes worth pulling: `wrf-data-structure`, `secrets-for-dev-run-tools`,
  and the workstation `groups.md` reference (`my-system/users-and-permissions/`)
  for the render/video group grant the mapper depends on.
- Non-interactive runs use `--assume-manifest-confirmed true` (preflight
  otherwise makes a human eyeball the SteamDB manifest date).

## First questions to answer

1. Can the headless laptop run the EXPORT/mapper stage, or must EXPORT stay on
   the workstation? This decides the whole architecture.
2. If split: what's the trigger/handoff between boxes (SSH invoke? the home
   server pulls exported output? a shared `WRF_ROOT` over the network?).
3. Scheduling: is this a systemd timer on patch cadence, or an on-demand launch?
   How does preflight's manifest-date gate work unattended?
