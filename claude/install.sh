#!/usr/bin/env bash
# claude/install.sh — deploy this repo's Claude context to the dev user's global
# Claude area (~dev/.claude). Copy-based (dev owns these files) and additive: it
# refreshes/adds files but does NOT prune ones deleted from the repo. Idempotent.
#
# Runnable standalone as dev (no root needed), or as a step of ../install.sh (run as
# root, in which case the writes are done AS dev via runuser so nothing in dev's home
# ends up root-owned). Mirrors the my-system users/dev-* installer pattern.
#
#   claude/CLAUDE.md        -> ~dev/.claude/CLAUDE.md                     (global; always loaded)
#   claude/skills/<name>/   -> ~dev/.claude/skills/<name>/                (global skills)
#   claude/memory/<proj>/   -> ~dev/.claude/projects/-<proj>/memory/      (project-scoped memory;
#                                                                          <proj> = abs path, '/'->'-',
#                                                                          leading dash dropped)
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DEV_HOME="$(getent passwd dev | cut -d: -f6)"; DEV_HOME="${DEV_HOME:-/home/dev}"
CLAUDE_DIR="$DEV_HOME/.claude"

# Run a command AS dev: directly if we already are dev, else via runuser (root only).
as_dev() {
  if [ "$(id -un)" = dev ]; then "$@"; else runuser -u dev -- "$@"; fi
}
say() { printf '  %s\n' "$*"; }

echo "== claude context install (-> $CLAUDE_DIR) =="

# 1. Global CLAUDE.md — loaded in every session on this box.
if [ -f "$HERE/CLAUDE.md" ]; then
  as_dev install -D -m 0644 "$HERE/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
  say "CLAUDE.md -> $CLAUDE_DIR/CLAUDE.md"
fi

# 2. Skills -> global skills dir (available in all sessions).
if [ -d "$HERE/skills" ]; then
  as_dev mkdir -p "$CLAUDE_DIR/skills"
  as_dev cp -a "$HERE/skills/." "$CLAUDE_DIR/skills/"
  say "skills -> $CLAUDE_DIR/skills/  ($(ls -1 "$HERE/skills" | tr '\n' ' '))"
fi

# 3. Memory -> project-scoped memory dirs. One subdir per project under memory/.
if [ -d "$HERE/memory" ]; then
  for d in "$HERE"/memory/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    dst="$CLAUDE_DIR/projects/-$name/memory"
    as_dev mkdir -p "$dst"
    as_dev cp -a "$d." "$dst/"
    say "memory ($name) -> $dst"
  done
fi

echo "claude context installed."
