---
name: todo-cross-box
description: This box is the hub + classifier for the shared cross-box `todo` store — the bare repo, classify-drain.sh, the 13:00 timer, and the jq/claude/git-identity deps it needs
metadata:
  type: project
---

The `todo` dev-idea capture system (repo `Surxe/todo`) is **shared between Ethan's
workstation and this box**. The workstation captures; **this box is the source of
truth and the only place classification runs**. Design (three append-only streams,
single-writer-per-box, derived classification-state) is in the todo repo's README.

## Layout on this box
- **Bare repo `/srv/dev/repos/todo.git`** — the hub / source of truth. Everyone
  pushes/pulls it.
- **Working clone `/srv/dev/repos/todo`** — owned by `dev`; its `hub` remote points
  at the local bare (file path, no SSH). `classify` runs here.
- **`home-server/todo/classify-drain.sh`** — the job: `git pull hub` → `todo classify`
  (local `claude`, appends `meta.jsonl`) → `git push hub`. Runs as `dev`.
- **`hs-todo-classify.{service,timer}`** — runs the drain **daily at 13:00
  America/Chicago** (`User=dev`, `Persistent=true`). The workstation's `todo classify`
  also invokes this same script over SSH (its `TODO_REMOTE_CLASSIFY_CMD`), so classify
  happens here whether scheduled or triggered.

## Deps this box needs (or classify silently does nothing)
These are **required** for the drain; all were set manually during setup and are
**not yet in `bootstrap.sh`** (see below):
- **`jq`** — `apt install jq`. `todo` hard-requires it; missing jq → the drain errors out.
- **`claude`** on PATH — lives in `~dev/.local/bin`, which a non-interactive/systemd
  shell drops, so `classify-drain.sh` prepends it to `PATH` itself.
- **A `dev` git identity** — `git config --global user.name/user.email` for `dev`.
  Without it `git commit` fails, and `todo`'s `commit()` swallows the error (`|| true`),
  so `meta` gets appended but **never committed or pushed** — classify looks like it
  worked ("classified N") but nothing propagates back to the workstation. Set to
  `Surxe-dev` / the Surxe GitHub noreply, matching the workstation.

## TODO (disposable-rebuild gap)
`bootstrap.sh` should install `jq` and set `dev`'s git identity so a scripted rebuild
reproduces this without manual steps. Also worth hardening `todo`'s `commit()` to warn
instead of swallowing a failed commit. See [[memories-live-in-this-repo]] for how this
note is maintained.
