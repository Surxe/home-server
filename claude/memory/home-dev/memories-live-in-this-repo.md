---
name: memories-live-in-this-repo
description: Write/edit home-server memories in this repo (claude/memory/home-dev/), never live in ~/.claude — then run install.sh
metadata:
  type: feedback
---

New or updated memories for the home-server box go in the **repo copy** at
`home-server/claude/memory/home-dev/<slug>.md` (and get indexed in that folder's
`MEMORY.md`) — **not** edited directly under `~dev/.claude/projects/-home-dev/memory/`.
That live path is a **deployment target**, refreshed by `home-server/claude/install.sh`
(copy-based). Editing it directly is overwritten on the next install and lost from git.

You are reading this note *from* the live dir, which is the irony: the fact that you
can see it here is only because it was authored in the repo and installed. Do the same
for the next one.

**Why:** memory is config-as-code like the rest of this repo — version-controlled,
reviewable, rebuildable. A note that exists only in `~/.claude` is invisible to git and
dies on rebuild/reinstall.

**How to apply:** author/edit the `.md` in `claude/memory/home-dev/`, add its one-line
pointer to `claude/memory/home-dev/MEMORY.md`, then deploy with
`home-server/claude/install.sh` (or the top-level `install.sh`). Mirrors the
workstation's [[memory-files-edit-in-repo]] / [[user-specific-via-my-system]] rules for
`my-system`.
