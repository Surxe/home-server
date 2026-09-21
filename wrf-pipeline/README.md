# WRF Pipeline — Section F: Orchestrator Service & Probe Integration

This directory contains the systemd infrastructure for the WRF (War Robots Frontiers) pipeline orchestrator, which runs on patch day to export, parse, and publish game data.

## Architecture

The pipeline orchestrator (`WRFrontiersDB-Orchestrator`) is triggered by a patch-detection probe:

```
PICS Probe (detects patch, exit 10)
    ↓
systemctl start wrf-orchestrator@{game_version}.service
    ↓
Orchestrator stage pipeline (export → parse → push → site)
    ↓
Old patch versions pruned (keep 2 most recent)
```

## Files

- **`wrf-orchestrator.service`** — systemd service template (parameterized with `@{game_version}`)
  - Runs orchestrator with `--patch-day --game-version={game_version}`
  - Injects secrets via `EnvironmentFile=/etc/home-server/wrf-orchestrator.env`
  - Runs as `dev:dev` with GPU runtime configured for headless mapper
  - Timeout: 3600s (1 hour, covers 30+ min mapper export on iGPU)
  - Retry on failure: 1 attempt after 5 minutes

- **`wrf-orchestrator.env.example`** — secrets template (user must populate)
  - `STEAM_USERNAME`, `STEAM_PASSWORD`, `GH_DATA_REPO_PAT`
  - Deployed to `/etc/home-server/wrf-orchestrator.env` (root 0600, never in repo)

- **`install.sh`** — idempotent deployment script
  - Installs service unit to `/etc/systemd/system/wrf-orchestrator@.service`
  - Writes a `10-node-path.conf` drop-in that puts nvm's node bin on the service PATH (resolved at install time, so nvm version bumps are picked up on re-install)
  - Verifies secrets file exists (warns if missing)
  - Wires the SITE stage (see below)

## SITE stage (Astro build via nvm)

The SITE stage runs `npm run build` in `WRFrontiersDB-Site`. Node is provided by
**nvm** for the `dev` user — the installer resolves nvm's node bin dir and puts it on
the service PATH via the drop-in, so `npm` resolves without sourcing nvm at runtime.
EXPORT and PARSE don't need node and run off the unit's own PATH.

The installer also sets up the build's inputs (all gitignored / not tracked in the Site repo):

- **Data symlinks** → sibling Data repo:
  - `WRFrontiersDB-Site/WRFrontiersDB-Data` — build reads JSON via `process.cwd()/WRFrontiersDB-Data/current/...`
  - `WRFrontiersDB-Site/public/WRFrontiersDB-Data` — textures served as `/WRFrontiersDB-Data/textures/*.png`
- **`vendor/wrf-design` submodule** — `git submodule update --init` (design tokens / CSS)
- **npm deps** — `npm ci` (only when `package-lock.json` is newer than `node_modules`)

Validated 2026-09-20: 650 pages build in ~23s on this box under the service's exact PATH.

## Secrets Setup

Before the service can run, populate the secrets file:

```bash
cat > /etc/home-server/wrf-orchestrator.env <<EOF
STEAM_USERNAME=<your-steam-username>
STEAM_PASSWORD=<your-steam-password>
GH_DATA_REPO_PAT=<your-github-pat>
EOF
sudo chmod 0600 /etc/home-server/wrf-orchestrator.env
```

Same secrets model as `steam-tracker` and `restic` on this host.

## Manual Trigger

To manually run the pipeline for a detected patch (e.g., 2026-08-22):

```bash
sudo systemctl start wrf-orchestrator@2026-08-22.service
```

Monitor the run in real-time:

```bash
sudo journalctl -u wrf-orchestrator@2026-08-22 -f
```

View the full orchestrator logs under `/srv/dev/wrf/logs/{YYYY-MM-DD_HHMMSS}/` (see Logging).

## Probe Integration (Section F)

The patch probe is `src/probe.py` in the `WRFrontiersDB-Orchestrator` clone, run on a
timer by the `hs-wrf-update-probe.service`/`.timer` units (see `../systemd/`). It does
an anonymous Steam PICS check, and on a new public manifest GID it:

1. Derives the version id from the manifest's unix timestamp (UTC day, `yyyy-mm-dd`,
   with a `-N` suffix for a 2nd+ patch the same day — see the orchestrator's
   `src/versioning.py`).
2. Hands off via its `--on-patch-cmd`, which `hs-wrf-update-probe.service` sets to:
   ```
   sudo -n systemctl start --no-block wrf-orchestrator@{version}.service
   ```
   The probe substitutes `{version}` and runs it (shell-free). `--no-block` returns
   at once, so the poll doesn't wait for the 30+ min pipeline.
3. Only advances its state (marks the GID seen) **after** the hand-off is accepted.

### Probe Exit Codes

- **Exit 0** — No new patch (or first-run baseline).
- **Exit 10** — New patch detected **and handed off**; state advanced.
- **Exit 1** — Probe error *or a failed hand-off*. State is left untouched, so the
  next poll re-detects and retries. The version assignment is idempotent, so the
  retry reuses the same version id.

`SuccessExitStatus=10` in the probe unit means a detected patch is a *successful*
run; only exit 1 marks the unit failed.

### Manual trigger

The hand-off is just `systemctl start`, so a patch can always be run by hand:
```bash
sudo systemctl start wrf-orchestrator@2026-09-15.service
```

## Data Retention (t-0122)

After each successful pipeline run:
- **Static folder**: `/srv/dev/wrf/data/steam-download/` (reused across patches, patched in place by DepotDownloader)
- **Versioned folders**: `/srv/dev/wrf/data/{exports,parsed,textures,mapper}/{game_version}/`
  - Named by ISO date: `2026-08-22`, `2026-08-29`, etc.
  - Oldest versions pruned, keeping only the 2 most recent patches

The pruning happens automatically at the end of each orchestrator run (see `repos.prune_old_versions(keep=2)` in `WRFrontiersDB-Orchestrator/src/run.py`).

Typical footprint after pruning:
- Static steam-download: ~15–50 GB (depends on game size and active patches)
- 2 versioned patch sets: ~35 GB × 2 = ~70 GB
- Proton prefix + other tools: ~2 GB
- **Total**: ~60–120 GB on a 68 GB volume (safe margin with DepotDownloader's in-place patching)

## Workflow on Patch Day

1. **Probe runs** (`hs-wrf-update-probe.timer`)
2. **Probe detects patch** → derives `{version}`, runs `sudo -n systemctl start --no-block wrf-orchestrator@{version}.service`, advances state, exits 10
3. **Orchestrator service starts**:
   - Verifies WRF data volume is mounted
   - Loads secrets from `/etc/home-server/wrf-orchestrator.env`
   - Runs pipeline stages (export, parse, push, site)
4. **Pipeline succeeds** → old versions are pruned
5. **Logs are captured** in journalctl (search by service name or unit)

## Logging

The orchestrator writes logs to two places, teed in real-time (no block-buffering):

**Journalctl** — all subprocess output (export, parse, site stages)
```bash
sudo journalctl -u wrf-orchestrator@2026-09-15 -f              # live
sudo journalctl -u wrf-orchestrator@2026-09-15 -n 100         # last 100 lines
sudo journalctl -u 'wrf-orchestrator@*' -f                     # all runs
```

**Per-stage log files** — under `/srv/dev/wrf/logs/{YYYY-MM-DD_HHMMSS}/`
- `run.log` — banners, stage start/stop markers
- `01-export.log` — DepotDownloader, mapper, BatchExport
- `02-parse.log` — JSON parsing, texture export
- `03-site.log` — Astro build output (650 pages)

Example after a run:
```bash
ls -la /srv/dev/wrf/logs/2026-09-20_190815/
# run.log, 01-export.log, 02-parse.log, 03-site.log

tail -50 /srv/dev/wrf/logs/2026-09-20_190815/01-export.log
```

Each run's logs live in its own timestamped directory, so multiple concurrent runs (if triggered in quick succession) don't interleave. Output streams line-by-line to both journalctl and disk.

## Troubleshooting

### Service won't start: "EnvironmentFile=/etc/home-server/wrf-orchestrator.env missing"

→ Create `/etc/home-server/wrf-orchestrator.env` with the required secrets (see Secrets Setup above).

### Service times out after 1 hour

→ The mapper stage on an iGPU can take 30+ minutes. If it's consistently exceeding 1 hour, increase `TimeoutStartSec=` in the service unit (see `/etc/systemd/system/wrf-orchestrator@.service`).

### GPU runtime not found in service

→ The service sets `XDG_RUNTIME_DIR=/run/user/1000` (dev's UID). Verify dev's runtime dir exists:
```bash
ls -la /run/user/1000/
```
If missing, run `loginctl enable-linger dev` (already done by `wrf-gpu/install.sh`).

### View real-time logs

```bash
# All orchestrator runs
sudo journalctl -u 'wrf-orchestrator@*' -f

# Specific version
sudo journalctl -u wrf-orchestrator@2026-08-22 -f

# Include the full stage logs (stderr/stdout combined)
sudo journalctl -u wrf-orchestrator@2026-08-22 -o verbose
```

## Related Docs

- **`WRFrontiersDB-Orchestrator/README.md`** — orchestrator CLI, stage pipeline, options
- **`WRFrontiersDB-Orchestrator/src/run.py`** — pipeline entry point, versioned dirs, pruning
- **`PICS`** (sibling repo) — patch-detection probe, triggers orchestrator on patch found
