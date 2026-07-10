#!/usr/bin/env bash
# Open ONE clean PR for a single verified fix. The loop calls this right after it
# commits a fix to claude/continuous-ux. It cherry-picks that one commit onto a
# fresh branch off the repo's real base (development/main) in a THROWAWAY worktree
# — so the loop's own working tree is never disturbed — pushes, and opens the PR.
#
# Usage: open-pr.sh <qa-worktree-path> [commit-ish]     (commit-ish defaults to HEAD)
# Prints the PR URL on success.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WT="${1:?usage: open-pr.sh <qa-worktree> [commit]}"
COMMIT="${2:-HEAD}"
WT="$(cd "$WT" && pwd)"
BASE="$(base_for "$WT")"
SLUG="$(repo_slug "$WT")"

sha="$(git -C "$WT" rev-parse --short "$COMMIT")"
subject="$(git -C "$WT" log -1 --format=%s "$COMMIT")"
body_txt="$(git -C "$WT" log -1 --format=%b "$COMMIT")"

# branch name: qa-fix/<slugified-subject>-<sha>
branch_slug="$(printf '%s' "$subject" \
  | sed -E 's/^(fix|feat|chore|bug)(\([^)]*\))?:\s*//I; s/[^a-zA-Z0-9]+/-/g; s/^-+|-+$//g' \
  | cut -c1-40 | tr 'A-Z' 'a-z')"
branch="qa-fix/${branch_slug:-fix}-${sha}"

git -C "$WT" fetch --quiet origin "$BASE"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/qa-pr.XXXXXX")"
cleanup() { git -C "$WT" worktree remove --force "$tmp" 2>/dev/null || rm -rf "$tmp"; }
trap cleanup EXIT

# Fresh worktree at the base, new branch, cherry-pick just this fix.
git -C "$WT" worktree add -q -b "$branch" "$tmp" "origin/$BASE"
if ! git -C "$tmp" cherry-pick "$sha" >/dev/null 2>&1; then
  git -C "$tmp" cherry-pick --abort 2>/dev/null || true
  echo "open-pr: cherry-pick of $sha onto origin/$BASE conflicts — PR not opened." >&2
  echo "         (fix likely depends on unmerged QA commits; resolve manually.)" >&2
  exit 1
fi

git -C "$tmp" push -q -u origin "$branch"

pr_body="$(printf '%s\n\n---\nOpened automatically by the subbox QA loop (continuous-ux) from commit %s on claude/continuous-ux.\nReview and merge; the next daily run rebases claude/continuous-ux onto %s to pull the merged code in.' "$body_txt" "$sha" "$BASE")"

url="$(gh pr create --repo "$SLUG" --base "$BASE" --head "$branch" \
        --title "$subject" --body "$pr_body" --label "$QA_PR_LABEL" 2>/dev/null)" || {
  # label may not exist yet — retry once creating it, then without it as last resort.
  gh label create "$QA_PR_LABEL" --repo "$SLUG" --color FBCA04 \
     --description "Opened by the subbox QA loop" >/dev/null 2>&1 || true
  url="$(gh pr create --repo "$SLUG" --base "$BASE" --head "$branch" \
          --title "$subject" --body "$pr_body" --label "$QA_PR_LABEL" 2>/dev/null)" \
    || url="$(gh pr create --repo "$SLUG" --base "$BASE" --head "$branch" \
              --title "$subject" --body "$pr_body")"
}

echo "$url"
