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

## Layout on this box (code and DATA are SEPARATE repos since the split)
- **Code repo `/srv/dev/repos/todo`** (`bin/todo` + the classify prompt) — tracks
  **GitHub `Surxe/todo`**: `origin` = `https://github.com/Surxe/todo.git`; pull code
  changes from there. It is NOT synced over any local bare. (The old bare
  `/srv/dev/repos/todo.git` is a vestigial pre-split leftover — nothing feeds it any
  more; don't point this clone at it.)
- **DATA store `/srv/dev/repos/todo-store`** (the three streams) — owned by `dev`; its
  `hub` remote is the **local bare `/srv/dev/repos/todo-store.git`** (file path, no SSH),
  which the workstation pushes to over SSH. All classify git ops act on the store.
- **`home-server/todo/classify-drain.sh`** — the job: `git pull hub` (the STORE) →
  `todo classify` (local `claude`, appends `meta.jsonl`) → `git push hub`. Runs as `dev`.
- **`hs-todo-classify.{service,timer}`** — runs the drain **daily at 13:00
  America/Chicago** (`User=dev`, `Persistent=true`). The workstation's `todo classify`
  also invokes this same script over SSH (its `TODO_REMOTE_CLASSIFY_CMD`), so classify
  happens here whether scheduled or triggered.

## Gotcha: the code clone must track GitHub, not the local bare
On 2026-09-23 this box's `todo` code clone (`/srv/dev/repos/todo`) still had
`origin`/`hub` pointing at the pre-split local bare `/srv/dev/repos/todo.git`, so
`git pull` + `todo/install.sh` kept redeploying a **stale `bin/todo`** — missing the
`show latest` change that had been pushed to GitHub — with no warning. Fix was to
re-point `origin` at `Surxe/todo` and fast-forward. `todo/install.sh` copies whatever
is in the checkout without checking freshness, so **after a code change lands on the
workstation, run `git -C /srv/dev/repos/todo pull` here before (re-)installing.**

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
