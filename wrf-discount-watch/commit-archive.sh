#!/usr/bin/env bash
# commit-archive.sh — commit + push the WRFrontiers-News-Scraper clone's archive/ after
# a scrape. Final step of hs-wrf-discount-watch.service; runs as dev (git identity +
# GitHub push auth live in dev's config).
#
# archive/ is the scraper repo's COMMITTED record of how WRF edits posts (it reuses
# article ids week to week, e.g. #272's discount title/body), so `git log -p archive/`
# is the edit history. Without this step every scrape just piles up uncommitted.
#
# Commits ONLY archive/, only when the clone is on master (never onto a branch someone
# is working on), and is a no-op when nothing changed. Also pushes any commit a previous
# run failed to push. Usage: commit-archive.sh [clone-dir]
set -euo pipefail

REPO=${1:-/srv/dev/repos/WRFrontiers-News-Scraper}
BRANCH=master
cd "$REPO"

cur=$(git branch --show-current)
if [ "$cur" != "$BRANCH" ]; then
  echo "commit-archive: clone is on '${cur:-detached HEAD}', not $BRANCH; skipping"
  exit 0
fi

git add -A -- archive
if git diff --cached --quiet -- archive; then
  echo "commit-archive: archive/ unchanged"
else
  # Name the articles in the subject: A = new post, M = WRF edited an existing one.
  ids() { git diff --cached --name-only --diff-filter="$1" -- archive/json \
            | sed -E 's#.*/([0-9]+)-.*#\1#' | sort -n | paste -sd, | sed 's/,/, /g'; }
  new=$(ids A); edited=$(ids M)
  detail=""
  [ -n "$new" ] && detail="new: $new"
  [ -n "$edited" ] && detail="${detail:+$detail; }edited: $edited"
  msg="archive: $(date +%F) scrape${detail:+ ($detail)}"
  # Pathspec commit: only archive/ goes in, even if something else is staged.
  git commit -q -m "$msg" -- archive
  echo "commit-archive: committed: $msg"
fi

# Rebase onto anything pushed from elsewhere, then push. A conflict (someone committed
# archive/ elsewhere) aborts cleanly and fails the unit rather than leaving a mid-rebase.
if ! git pull -q --rebase --autostash origin "$BRANCH"; then
  git rebase --abort 2>/dev/null || true
  echo "commit-archive: rebase onto origin/$BRANCH failed; left unpushed" >&2
  exit 1
fi
if [ -n "$(git rev-list "origin/$BRANCH..HEAD")" ]; then
  git push -q origin "HEAD:$BRANCH"
  echo "commit-archive: pushed to origin/$BRANCH"
fi
