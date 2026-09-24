#!/usr/bin/env bash
# wrf-pipeline/install.sh — deploy the WRF orchestrator systemd service and wire the
# SITE stage (node via nvm, Data symlinks, wrf-design submodule, npm deps).
# Invoked by ../install.sh after WRF volume setup. Idempotent. Requires root.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "wrf-pipeline/install.sh: run as root"; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
REPOS="$(cd "$HERE/../.." && pwd)"   # /srv/dev/repos (sibling clones live here)
SITE_DIR="$REPOS/WRFrontiersDB-Site"
DATA_DIR="$REPOS/WRFrontiersDB-Data"
say(){ printf '\n\033[1m-- %s\033[0m\n' "$*"; }

# Resolve the nvm-managed node bin dir for the dev user (used both to build the site
# now and to put node on the service's PATH via a drop-in). Empty if nvm/node absent.
node_bin_dir(){
  runuser -l dev -c 'export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh" >/dev/null 2>&1; command -v node' 2>/dev/null \
    | { read -r n && dirname "$n"; } || true
}

say "wrf-pipeline: deploying orchestrator service"

install -m 0644 "$HERE/wrf-orchestrator.service" /etc/systemd/system/wrf-orchestrator@.service

# Drop-in: prepend nvm's node bin to the service PATH so the SITE stage's `npm run
# build` resolves. Resolved at install time (not hardcoded) so nvm version bumps are
# picked up on the next install. If node is absent, EXPORT/PARSE still work off the
# unit's own PATH; only SITE needs node.
DROPIN_DIR=/etc/systemd/system/wrf-orchestrator@.service.d
NODE_BIN="$(node_bin_dir)"
if [ -n "$NODE_BIN" ]; then
  mkdir -p "$DROPIN_DIR"
  cat > "$DROPIN_DIR/10-node-path.conf" <<EOF
[Service]
Environment=PATH=$NODE_BIN:/usr/games:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF
  echo "  node on service PATH via drop-in: $NODE_BIN"
else
  rm -f "$DROPIN_DIR/10-node-path.conf" 2>/dev/null || true
  echo "  !! nvm node not found for dev — SITE stage will not build until node is installed"
fi
systemctl daemon-reload

# Verify the secrets file exists (user must populate /etc/home-server/wrf-orchestrator.env)
mkdir -p /etc/home-server
if [ ! -f /etc/home-server/wrf-orchestrator.env ]; then
  install -m 0644 "$HERE/wrf-orchestrator.env.example" /etc/home-server/wrf-orchestrator.env.example
  echo "  !! Secrets file /etc/home-server/wrf-orchestrator.env not found."
  echo "  Template copied to /etc/home-server/wrf-orchestrator.env.example — fill in:"
  echo "    STEAM_USERNAME=<...>  STEAM_PASSWORD=<...>  GH_DATA_REPO_PAT=<...>"
  echo "  Optional run-report email: SMTP_USER=<...> SMTP_PASSWORD=<...> EMAIL_TO=<...>"
else
  echo "  ✓ secrets file exists"
fi

# --- SITE stage setup ------------------------------------------------------------
# The Astro site reads the sibling Data repo at build time via process.cwd()/
# WRFrontiersDB-Data and serves its textures from public/WRFrontiersDB-Data; both
# are gitignored symlinks. It also needs the wrf-design submodule and npm deps.
say "wrf-pipeline: wiring SITE stage"
if [ -d "$SITE_DIR/.git" ]; then
  if [ ! -d "$DATA_DIR" ]; then
    echo "  !! Data repo missing at $DATA_DIR — clone it; SITE build will fail without it"
  fi
  # Data symlinks (gitignored) -> sibling Data repo.
  ln -sfnT "$DATA_DIR" "$SITE_DIR/WRFrontiersDB-Data"
  mkdir -p "$SITE_DIR/public"
  ln -sfnT "$DATA_DIR" "$SITE_DIR/public/WRFrontiersDB-Data"
  chown -h dev:dev "$SITE_DIR/WRFrontiersDB-Data" "$SITE_DIR/public/WRFrontiersDB-Data"
  echo "  Data symlinks in place"

  # Submodule (vendor/wrf-design) + node deps, as dev under nvm. npm ci only when the
  # lockfile is newer than node_modules (or deps absent), so re-runs are cheap.
  runuser -l dev -c "
    set -e
    export NVM_DIR=\"\$HOME/.nvm\"; . \"\$NVM_DIR/nvm.sh\" >/dev/null 2>&1
    cd '$SITE_DIR'
    git submodule update --init --recursive
    if [ ! -d node_modules ] || [ package-lock.json -nt node_modules ]; then
      echo '  npm ci (installing site deps)'; npm ci
    else
      echo '  site deps up to date'
    fi
  "
else
  echo "  Site repo not at $SITE_DIR — skipping SITE setup (clone it to enable the site build)"
fi

say "orchestrator service ready"
cat <<'EOF'

Trigger the pipeline for a detected patch version:
  sudo systemctl start wrf-orchestrator@2026-09-15.service
Monitor:
  sudo journalctl -u 'wrf-orchestrator@*' -f
EOF
