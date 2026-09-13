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

# TODO_DIR is the CODE repo (holds bin/todo + the classify prompt); TODO_STORE_DIR
# is the DATA repo (the streams; syncs over the hub). All git ops act on the store.
TODO_DIR="${TODO_DIR:-/srv/dev/repos/todo}"
TODO_STORE_DIR="${TODO_STORE_DIR:-/srv/dev/repos/todo-store}"
TODO="$TODO_DIR/bin/todo"
[ -x "$TODO" ] || { echo "classify-drain: todo bin not found at $TODO" >&2; exit 1; }

branch="$(git -C "$TODO_STORE_DIR" symbolic-ref --short -q HEAD || echo master)"

# Pull workstation captures/status from the hub (local bare repo on this box).
# On failure, ABORT the rebase before continuing — otherwise a conflict leaves the
# checkout mid-rebase with conflict markers written into status.jsonl, which then
# breaks `classify` (jq chokes on the markers). Mirrors bin/todo's sync_pull. With
# the store's `status.jsonl merge=union` this should no longer conflict, but the
# abort keeps a bad pull non-fatal regardless.
if ! git -C "$TODO_STORE_DIR" pull --rebase --quiet hub "$branch" 2>/dev/null; then
    git -C "$TODO_STORE_DIR" rebase --abort 2>/dev/null || true
    echo "classify-drain: hub pull failed (continuing with local state)" >&2
fi

# Classify locally. TODO_CLASSIFY_REMOTE must stay UNSET here, or this would try to
# bounce back to itself; the service/ssh environments deliberately omit it.
unset TODO_CLASSIFY_REMOTE
TODO_DIR="$TODO_DIR" TODO_STORE_DIR="$TODO_STORE_DIR" "$TODO" classify

# Publish the freshly-appended meta back to the hub for the workstation to pull.
git -C "$TODO_STORE_DIR" push --quiet hub 2>/dev/null \
    || echo "classify-drain: hub push failed (will retry next run)" >&2
