#!/usr/bin/env bash
# claude/install.sh — deploy this repo's agent context (global instructions,
# skills, memory) to the dev user's neutral `~/.agents` root, then symlink the
# Claude-specific paths into `~/.claude` and render the DeepSeek Harness memory
# into `~/.dsh/memory`. Copy-based (dev owns these files) and additive: it
# refreshes/adds files but does NOT prune ones deleted from the repo. Idempotent.
#
# Runnable standalone as dev (no root needed), or as a step of ../install.sh (run as
# root, in which case the writes are done AS dev via runuser so nothing in dev's home
# ends up root-owned). Mirrors the my-system users/dev-* installer pattern.
#
#   claude/CLAUDE.md        -> ~dev/.agents/AGENTS.md   (symlinked to ~/.claude/CLAUDE.md + ~/.dsh/AGENTS.md)
#   claude/skills/<name>/   -> ~dev/.agents/skills/<name>/  (symlinked to ~/.claude/skills; dsh reads natively)
#   claude/memory/<proj>/   -> ~dev/.agents/memory/      (symlinked to ~/.claude/projects/-<proj>/memory)
#                          +  ~dev/.dsh/memory/          (memory-standard format for the DeepSeek Harness)
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DEV_HOME="$(getent passwd dev | cut -d: -f6)"; DEV_HOME="${DEV_HOME:-/home/dev}"
CLAUDE_DIR="$DEV_HOME/.claude"
AGENTS_DIR="$DEV_HOME/.agents"
DSH_HOME_DIR="$DEV_HOME/.dsh"
DEV_ENV_REPO="$HERE/../../dev-env"

# Run a command AS dev: directly if we already are dev, else via runuser (root only).
as_dev() {
  if [ "$(id -un)" = dev ]; then "$@"; else runuser -u dev -- "$@"; fi
}
say() { printf '  %s\n' "$*"; }

# Point a live ~/.claude/~/.dsh path at a neutral ~/.agents target, as dev.
# Idempotent; a pre-existing real file/dir (the one-time migration) is moved aside
# to <path>.pre-agents rather than deleted.
ensure_agents_symlink() {   # $1 = target (must exist), $2 = link path
  local target="$1" link="$2"
  as_dev bash -c '
    set -euo pipefail
    target="$1"; link="$2"
    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
      echo "  symlink: target missing: $target" >&2; exit 1
    fi
    if [ -L "$link" ]; then
      [ "$(readlink "$link")" = "$target" ] && exit 0
      rm -f "$link"
    elif [ -e "$link" ]; then
      bak="$link.pre-agents"
      rm -rf "$bak"
      mv "$link" "$bak"
      echo "  symlink: moved existing $link -> $bak"
    fi
    mkdir -p "$(dirname "$link")"
    ln -s "$target" "$link"
    echo "  symlink: $link -> $target"
  ' _ "$target" "$link"
}

echo "== claude context install (-> $AGENTS_DIR, symlinked into $CLAUDE_DIR) =="

# 1. Global instructions -> neutral AGENTS.md, symlinked to both agents' paths.
if [ -f "$HERE/CLAUDE.md" ]; then
  as_dev install -D -m 0644 "$HERE/CLAUDE.md" "$AGENTS_DIR/AGENTS.md"
  say "AGENTS.md -> $AGENTS_DIR/AGENTS.md"
  ensure_agents_symlink "$AGENTS_DIR/AGENTS.md" "$CLAUDE_DIR/CLAUDE.md"
  ensure_agents_symlink "$AGENTS_DIR/AGENTS.md" "$DSH_HOME_DIR/AGENTS.md"
fi

# 2. Skills -> neutral skills dir (dsh reads ~/.agents/skills natively).
if [ -d "$HERE/skills" ]; then
  as_dev mkdir -p "$AGENTS_DIR/skills"
  as_dev cp -a "$HERE/skills/." "$AGENTS_DIR/skills/"
  say "skills -> $AGENTS_DIR/skills/  ($(ls -1 "$HERE/skills" | tr '\n' ' '))"
  ensure_agents_symlink "$AGENTS_DIR/skills" "$CLAUDE_DIR/skills"
fi

# 3. Memory -> project-scoped. One subdir per project under memory/.
if [ -d "$HERE/memory" ]; then
  for d in "$HERE"/memory/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    dst="$AGENTS_DIR/memory"
    as_dev mkdir -p "$dst"
    as_dev cp -a "$d." "$dst/"
    say "memory ($name) -> $dst"
    ensure_agents_symlink "$dst" "$CLAUDE_DIR/projects/-$name/memory"
    # DeepSeek Harness: same notes, memory-standard (mm) layout.
    if [ -f "$DEV_ENV_REPO/lib/memory-standard.py" ]; then
      as_dev python3 "$DEV_ENV_REPO/lib/memory-standard.py" render --src "$d" --dst "$DSH_HOME_DIR/memory" || \
        say "!! dsh memory render failed (see above)"
    else
      say "memory: no $DEV_ENV_REPO/lib/memory-standard.py — skipping dsh memory"
    fi
  done
fi

echo "claude context installed."
