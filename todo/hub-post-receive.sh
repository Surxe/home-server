#!/usr/bin/env bash
# post-receive hook for the todo hub (the bare repo /srv/dev/repos/todo.git on this
# home-server). On every push to the hub, best-effort nudge the workstation to pull,
# so server-side changes (fresh meta from classify, or a `done` marked here)
# propagate to ethan-debian without it polling.
#
# Reachability is asymmetric: the workstation can always reach this always-on box
# (its `todo-hub` ssh alias), but this box can only reach the workstation while that
# desktop is awake. So this is fire-and-forget: detached (new session), bounded
# (ConnectTimeout), and a silent no-op when the workstation is unreachable OR the
# reverse-ssh alias isn't set up yet — the workstation then catches up on its next
# own commit-sync (its todo-sync.path). This never blocks or fails the push.
#
# The reverse ssh alias + key live in dev's ~/.ssh ON THIS BOX (out of the repo,
# mirroring the workstation's `todo-hub` alias — no host/IP is committed). Until you
# add a `todo-workstation` Host entry there, this hook is inert (harmless). Override
# the alias with TODO_WORKSTATION_SSH.
#
# Installed by home-server/todo/install.sh, which copies this into the bare repo's
# hooks/post-receive. Loop-safe: the nudge is a pull only (never pushes back), and a
# fast-forward pull that finds nothing new produces no hub push, so no hook re-fires.

WS="${TODO_WORKSTATION_SSH:-todo-workstation}"

# Detach into a new session with stdio closed so `git push` returns immediately and
# is never held open by the ssh round-trip.
setsid ssh -o ConnectTimeout=8 -o BatchMode=yes "$WS" \
    'git -C /srv/dev/repos/todo pull --rebase --quiet hub master' \
    </dev/null >/dev/null 2>&1 &

exit 0
