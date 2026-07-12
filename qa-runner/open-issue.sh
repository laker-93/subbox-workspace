#!/usr/bin/env bash
# File ONE GitHub issue for a bug the loop found — the tracking record for a problem
# the loop logs in a worktree's docs/qa/bugs.md. The loop calls this the moment it
# logs a *new* bug (every bug gets an issue, fixed same-cycle or not), then writes the
# printed issue URL back into that bugs.md entry as an `Issue:` line. That link is the
# dedup key: a fresh-context cycle reads bugs.md first, so an entry that already carries
# an `Issue:` link is never re-filed. When a fix PR whose body says `Closes #<n>` merges
# into the base, GitHub closes the issue automatically — so the issue's open/closed
# state tracks whether the bug is fixed in development/main.
#
# Usage: open-issue.sh <qa-worktree-path> <title> <body>
# Prints the issue URL on success.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WT="${1:?usage: open-issue.sh <qa-worktree> <title> <body>}"
TITLE="${2:?usage: open-issue.sh <qa-worktree> <title> <body>}"
BODY="${3:?usage: open-issue.sh <qa-worktree> <title> <body>}"
WT="$(cd "$WT" && pwd)"
SLUG="$(repo_slug "$WT")"
BASE="$(base_for "$WT")"

issue_body="$(printf '%s\n\n---\nFiled automatically by the subbox QA loop (continuous-ux). Full repro/evidence lives in this repo'\''s docs/qa/bugs.md on the claude/continuous-ux branch. A fix PR into %s that references this issue (Closes #<n>) closes it on merge.' "$BODY" "$BASE")"

create() { gh issue create --repo "$SLUG" --title "$TITLE" --body "$issue_body" "$@"; }

url="$(create --label "$QA_BUG_LABEL" 2>/dev/null)" || true
if [[ -z "$url" ]]; then
  # label may not exist yet — create it once, retry, then fall back to no label.
  gh label create "$QA_BUG_LABEL" --repo "$SLUG" --color D73A4A \
     --description "Bug found by the subbox QA loop" >/dev/null 2>&1 || true
  url="$(create --label "$QA_BUG_LABEL" 2>/dev/null)" || true
fi
[[ -z "$url" ]] && { url="$(create 2>/dev/null)" || true; }
if [[ -z "$url" ]]; then
  echo "open-issue: gh issue create failed for $SLUG" >&2
  exit 1
fi

# Record for the daily digest — run-daily.sh reads lines newer than the run start,
# so the digest can link exactly the issues filed this run without grepping model output.
printf '%s\t%s\t%s\n' "$(date +%s)" "$url" "$SLUG" >> "$STATE_DIR/issues.log"

echo "$url"
