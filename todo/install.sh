#!/usr/bin/env bash
# todo/install.sh — put the shared `todo` CLI on dev's PATH on this box.
#
# The cross-box `todo` store's working clone lives at /srv/dev/repos/todo and its
# bin/todo is invoked by absolute path by classify-drain.sh — but nothing otherwise
# puts it on dev's PATH here, so an interactive `todo show`/`todo list` returns
# "command not found". This copies the bin into dev's ~/.local/bin (a copy, never a
# symlink into the dev-writable todo tree), mirroring the my-system users todo-dev
# step. dev's ~/.local/bin is already on its interactive PATH (that's where `claude`
# lives), so `todo` resolves after this runs.
#
# Runnable standalone as dev, or as a step of ../install.sh (run as root; the write
# is done AS dev via runuser so nothing in dev's home ends up root-owned). Idempotent.
set -euo pipefail

DEV_HOME="$(getent passwd dev | cut -d: -f6)"; DEV_HOME="${DEV_HOME:-/home/dev}"
TODO_BIN="${TODO_BIN:-/srv/dev/repos/todo/bin/todo}"

# Run a command AS dev: directly if we already are dev, else via runuser (root only).
as_dev() { if [ "$(id -un)" = dev ]; then "$@"; else runuser -u dev -- "$@"; fi; }
say() { printf '  %s\n' "$*"; }

echo "== todo bin install =="
if [ ! -e "$TODO_BIN" ]; then
  echo "!! todo bin not found at $TODO_BIN — skipping (is the todo clone present?)" >&2
  exit 0
fi
as_dev install -D -m 0755 "$TODO_BIN" "$DEV_HOME/.local/bin/todo"
say "installed $DEV_HOME/.local/bin/todo (copy of $TODO_BIN)"
