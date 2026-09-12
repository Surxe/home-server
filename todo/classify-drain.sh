#!/usr/bin/env bash
# classify-drain.sh — the home-server's todo job: sync the shared hub, classify
# any un-classified captures through the local `claude` CLI, publish the new meta
# back to the hub. Classification runs ONLY here; the workstation triggers this
# same script over SSH (todo repo's TODO_REMOTE_CLASSIFY_CMD). See the todo repo
# README (cross-box model) for the three-stream design.
#
# Invoked by hs-todo-classify.service (daily timer) AND over SSH from the
# workstation's `todo classify`. Runs as `dev`. A systemd/non-interactive shell
# omits ~/.local/bin (where `claude` lives), so PATH is set explicitly. Sync is
# best-effort: an unreachable hub is not fatal, and `classify` no-ops when there
# is nothing un-classified.
set -euo pipefail
export PATH="${HOME:-/home/dev}/.local/bin:$PATH"

TODO_DIR="${TODO_DIR:-/srv/dev/repos/todo}"
TODO="$TODO_DIR/bin/todo"
[ -x "$TODO" ] || { echo "classify-drain: todo bin not found at $TODO" >&2; exit 1; }

branch="$(git -C "$TODO_DIR" symbolic-ref --short -q HEAD || echo master)"

# Pull workstation captures/status from the hub (local bare repo on this box).
git -C "$TODO_DIR" pull --rebase --quiet hub "$branch" 2>/dev/null \
    || echo "classify-drain: hub pull failed (continuing with local state)" >&2

# Classify locally. TODO_CLASSIFY_REMOTE must stay UNSET here, or this would try to
# bounce back to itself; the service/ssh environments deliberately omit it.
unset TODO_CLASSIFY_REMOTE
TODO_DIR="$TODO_DIR" "$TODO" classify

# Publish the freshly-appended meta back to the hub for the workstation to pull.
git -C "$TODO_DIR" push --quiet hub 2>/dev/null \
    || echo "classify-drain: hub push failed (will retry next run)" >&2
