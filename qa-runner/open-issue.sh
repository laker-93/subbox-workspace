#!/usr/bin/env bash
# File a GitHub issue for a bug the loop found — the tracking record for a problem
# the loop logs in a worktree's docs/qa/bugs.md. The loop calls this the moment it
# logs a *new* bug (every bug gets an issue, fixed same-cycle or not), then writes the
# printed issue URL back into that bugs.md entry as an `Issue:` line. That link is the
# *primary* dedup key: a fresh-context cycle reads bugs.md first, so an entry that
# already carries an `Issue:` link is never re-filed.
#
# That primary key lives only in the journal, and a cycle that crashes/times out
# between filing an issue and committing bugs.md orphans it — the issue exists on
# GitHub but the journal has no record, so the next cycle rediscovers the same bug
# and would file a duplicate (this happened: pymix#32 and #33 were the same bug).
# As a second, independent line of defense this script itself checks GitHub — which
# survives a crashed cycle even when the local journal doesn't — for an existing open
# `qa-bug` issue matching <dedup-key> before creating a new one, and hands back the
# existing URL instead of filing a duplicate.
#
# When a fix PR whose body says `Closes #<n>` merges into the base, GitHub closes the
# issue automatically — so the issue's open/closed state tracks whether the bug is
# fixed in development/main.
#
# Usage: open-issue.sh <qa-worktree-path> <title> <body> <dedup-key>
#   dedup-key: a short, stable string identifying the code area — an endpoint
#   (e.g. "POST /rekordbox/export"), a function/file ref (e.g. "rekordbox_export"
#   or "rb_import_export.py"), or similar. Pick something that would appear in a
#   future cycle's own repro/body for the *same* bug even if the title/wording
#   differs. Searched via `gh issue list -S`, scoped to open qa-bug issues.
# Prints the issue URL on success (a freshly filed one, or a pre-existing match).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WT="${1:?usage: open-issue.sh <qa-worktree> <title> <body> <dedup-key>}"
TITLE="${2:?usage: open-issue.sh <qa-worktree> <title> <body> <dedup-key>}"
BODY="${3:?usage: open-issue.sh <qa-worktree> <title> <body> <dedup-key>}"
KEY="${4:?usage: open-issue.sh <qa-worktree> <title> <body> <dedup-key>}"
WT="$(cd "$WT" && pwd)"
SLUG="$(repo_slug "$WT")"
BASE="$(base_for "$WT")"

# --- Dedup check: does an open qa-bug issue already cover this area? ---------
existing="$(gh issue list --repo "$SLUG" --label "$QA_BUG_LABEL" --state open \
  --search "$KEY" --json url --jq '.[0].url' 2>/dev/null || true)"
if [[ -n "$existing" ]]; then
  echo "open-issue: found existing open $QA_BUG_LABEL issue matching \"$KEY\" — not filing a duplicate ($existing)" >&2
  echo "$existing"
  exit 0
fi

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
