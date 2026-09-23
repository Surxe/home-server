#!/usr/bin/env bash
# install.sh — top-level installer for the home-server host. Orchestrates the
# per-area installers (systemd units, ...). Each sub-installer is idempotent and
# self-contained, so this is safe to re-run. Run as root.
#
# Relationship to bootstrap.sh: bootstrap.sh is the full first-boot host apply
# (network/interfaces, wifi service, fstab, sleep masking, guest checks). install.sh
# is the modular component installer you call to (re)install a subsystem — it wires the
# host systemd units + agent context, and delegates the whole Valheim subsystem to the
# sibling valheim-server repo. Both use the same symlink-into-repo model, so running
# either keeps the live units == the repos.
#
# Secrets are never installed by these scripts — only their locations under
# /etc/home-server/ (see each *.env.example).
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
[ "$(id -u)" -eq 0 ] || { echo "run as root:  sudo $0"; exit 1; }

# Non-fatal problems are collected and replayed in an end-of-run summary rather
# than left to scroll away mid-install. Unlike the workstation's install.sh, the
# sub-installers here are independent scripts (two in sibling repos) with no shared
# lib to source, so warn() lives only at THIS orchestrator level — child-emitted
# messages aren't captured, only the orchestrator's own. FAILED collects steps that
# exited non-zero (see the run loop); the install continues past each and exits
# non-zero at the end if any failed.
WARNINGS=()
FAILED=()
warn(){ echo "!! $*" >&2; WARNINGS+=("$*"); }

# --- self-sync: fast-forward THIS home-server repo to origin before deploying, so a
#     run always ships the latest committed host config rather than a stale checkout
#     (the shared dev-env + valheim-server clones get the same refresh further down).
#     We fetch once, then fast-forward ONLY if the branch is purely behind its upstream
#     — a dirty tree or a diverged history is left untouched and merely reported, so
#     local work is never clobbered. Git runs as dev because the repo is dev-owned (a
#     root pull would leave root-owned objects behind). Because this script lives in the
#     repo being updated, a fast-forward that moves HEAD is followed by an exec of the
#     refreshed install.sh so the rest of the run uses the new tree; HS_SELF_SYNCED
#     guards against an exec loop. Runs before logging so the aborted first pass leaves
#     no stray log — the re-exec'd run writes the real one.
if [ -z "${HS_SELF_SYNCED:-}" ] && [ -d "$REPO/.git" ]; then
  runuser -u dev -- git -C "$REPO" fetch -q origin 2>/dev/null || true
  hs_base="$(runuser -u dev -- git -C "$REPO" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  if [ -n "$hs_base" ]; then
    hs_behind="$(runuser -u dev -- git -C "$REPO" rev-list --count "HEAD..$hs_base" 2>/dev/null || echo 0)"
    hs_ahead="$(runuser -u dev -- git -C "$REPO" rev-list --count "$hs_base..HEAD" 2>/dev/null || echo 0)"
    if [ "${hs_behind:-0}" -gt 0 ]; then
      if [ "${hs_ahead:-0}" -eq 0 ] && runuser -u dev -- git -C "$REPO" merge --ff-only -q "$hs_base" 2>/dev/null; then
        echo ">> home-server fast-forwarded $hs_behind commit(s) to $hs_base — re-running install.sh"
        exec env HS_SELF_SYNCED=1 bash "$0" "$@"
      else
        warn "home-server is $hs_behind commit(s) behind $hs_base but could not fast-forward (local commits or dirty tree) — continuing with current checkout"
      fi
    fi
  fi
fi

# Log this run to a timestamped file and keep the last KEEP_LOGS runs (pruneable
# logging). All stdout/stderr is tee'd, so the log captures the same output the
# terminal shows. The very first line printed is the log path, so it's obvious
# where to look afterwards.
LOG_DIR="/var/log/home-server"
KEEP_LOGS=10
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
# Prune older logs first (before the new one exists), keeping the newest KEEP_LOGS.
ls -1t "$LOG_DIR"/install-*.log 2>/dev/null | tail -n +$((KEEP_LOGS + 1)) | xargs -r rm -f || true
exec > >(tee -a "$LOG_FILE") 2>&1
# tee runs async via process substitution; wait for it on exit so no output is
# lost/raced when the script finishes (otherwise even the first line can vanish).
TEE_PID=$!
trap 'exec >&- 2>&-; wait "$TEE_PID" 2>/dev/null' EXIT
echo "logging to $LOG_FILE"

echo "== home-server install =="

# Refresh the shared dev-env clone first so this box deploys the latest shared
# layer (a stale clone silently ships old fragments — e.g. missing the ds/key
# export). Pull as dev to keep the clone dev-owned; warn and continue on error.
if [ -d "$REPO/../dev-env/.git" ]; then
  if runuser -u dev -- git -C "$REPO/../dev-env" pull --ff-only; then
    echo ">> dev-env clone updated"
  else
    warn "dev-env clone update failed — continuing with existing checkout"
  fi
fi

# Refresh the sibling valheim-server clone too (the Valheim subsystem lives there now).
# Same warn-and-continue as dev-env: a missing/behind clone must not abort the host install.
if [ -d "$REPO/../valheim-server/.git" ]; then
  if runuser -u dev -- git -C "$REPO/../valheim-server" pull --ff-only; then
    echo ">> valheim-server clone updated"
  else
    warn "valheim-server clone update failed — continuing with existing checkout"
  fi
fi

# Installers to run, in order. Add more here as subsystems get their own installer.
INSTALLERS=(
  "$REPO/systemd/install.sh"   # host systemd units (root)
  "$REPO/todo/install.sh"      # shared `todo` CLI -> dev's ~/.local/bin (writes as dev)
  "$REPO/claude/install.sh"    # dev's agent context: box-local AGENTS.md, skills, memory -> ~/.agents + ~/.dsh (writes as dev)
  "$REPO/../dev-env/install.sh"  # shared dev config layer: portable skills/cc/ds/memories + dsh plugin (writes as dev)
  "$REPO/steam-tracker/install.sh"  # steam-price-tracker venv build + daily timer (self-guards on the sibling clone)
  "$REPO/wrf-probe/install.sh"      # WRFrontiersDB-Orchestrator venv build + patch-probe timer (self-guards on the sibling clone)
  "$REPO/wrf-gpu/install.sh"        # host GPU/export deps (RADV + gamescope + dev GPU groups/linger) for the mapper stage
  "$REPO/wrf-volume/install.sh"     # /srv/dev/wrf data-volume fstab mount (nofail; one-time carve is provision-shrink.sh)
  "$REPO/wrf-pipeline/install.sh"   # WRF orchestrator systemd service (triggered by probe on patch detection)
)
# Valheim subsystem lives in the sibling valheim-server repo — include it only if that
# clone is present (its systemd units + agent context; root, drops to dev where needed).
if [ -f "$REPO/../valheim-server/install.sh" ]; then
  INSTALLERS+=("$REPO/../valheim-server/install.sh")
else
  warn "valheim-server clone not found at $REPO/../valheim-server — skipping its install"
fi

for inst in "${INSTALLERS[@]}"; do
  # Resolve how to run this step; a missing installer is a config error, so record
  # it and carry on rather than aborting the whole host install.
  if [ -x "$inst" ]; then
    echo ">> $inst"; runner=("$inst")
  elif [ -f "$inst" ]; then
    echo ">> bash $inst"; runner=(bash "$inst")
  else
    echo "!! missing installer: $inst — recording and continuing" >&2
    FAILED+=("$inst (missing)")
    continue
  fi
  # Per-installer failure isolation: a non-zero exit is recorded and the install
  # CONTINUES (the `if` condition is set -e's standard exemption, so a failing step
  # doesn't trip this orchestrator's set -e). The guarantee is per-installer: each
  # sub-installer's own set -e still stops it at its first hard error.
  if "${runner[@]}"; then :; else
    rc=$?
    FAILED+=("$inst (exit $rc)")
    echo "!! installer FAILED (exit $rc) — continuing: $inst" >&2
  fi
done

# --- end-of-run summary: replay warnings, then failed installers, so neither gets
#     lost in the scrollback. Exit non-zero if anything failed, so a caller (or the
#     tee'd log's reader) can tell a run was only partially applied. ---
if [ "${#WARNINGS[@]}" -gt 0 ]; then
  echo
  echo "== warnings (${#WARNINGS[@]}) =="
  for w in "${WARNINGS[@]}"; do echo "   $w"; done
fi
if [ "${#FAILED[@]}" -gt 0 ]; then
  echo
  echo "== FAILED installers (${#FAILED[@]}) =="
  for f in "${FAILED[@]}"; do echo "   $f"; done
  echo
  echo "== home-server install complete (with ${#FAILED[@]} failed) =="
  exit 1
fi

echo
echo "== home-server install complete =="
