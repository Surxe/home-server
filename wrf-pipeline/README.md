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
  - Verifies secrets file exists (warns if missing)

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

View the full orchestrator logs in `/srv/dev/wrf/logs/orchestrator/2026-08-22/`.

## Probe Integration (Section F)

The PICS probe (in the sibling `PICS` repo) is responsible for:

1. Detecting when a new patch is available for WRFrontiers
2. On detection (exit 10), extracting the patch version (ISO date, e.g., `2026-08-22`)
3. Triggering the orchestrator service:
   ```bash
   systemctl start wrf-orchestrator@{detected_version}.service
   ```

### Probe Exit Codes

- **Exit 0** — No new patch
- **Exit 10** — New patch detected; orchestrator service should be triggered with the detected version

The probe can inject the detected version into the service start command via a wrapper script or directly via `systemctl`.

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

1. **PICS probe runs** (timer or event-driven)
2. **Probe detects patch** → exits 10, calls `systemctl start wrf-orchestrator@{version}.service`
3. **Orchestrator service starts**:
   - Verifies WRF data volume is mounted
   - Loads secrets from `/etc/home-server/wrf-orchestrator.env`
   - Runs pipeline stages (export, parse, push, site)
4. **Pipeline succeeds** → old versions are pruned
5. **Logs are captured** in journalctl (search by service name or unit)

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
