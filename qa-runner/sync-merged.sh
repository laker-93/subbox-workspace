#!/usr/bin/env bash
# Pull merged fixes back into the QA worktrees. Run at the START of each daily run
# (before any cycle), while the loop is idle. For each worktree: fetch, then rebase
# claude/continuous-ux onto the updated base. A fix whose PR you merged has the same
# patch-id upstream, so rebase DROPS it automatically; the new base code comes in.
# On conflict it aborts cleanly (leaving the branch as-is) and reports — never
# force-pushes, never leaves a half-rebased tree.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

report=""
for WT in "$FEISHIN_QA" "$PYMIX_QA"; do
  [[ -d "$WT" ]] || continue
  base="$(base_for "$WT")"
  name="$(basename "$WT")"

  # Don't rebase over a dirty tree or a rebase already in progress.
  if [[ -n "$(git -C "$WT" status --porcelain)" ]]; then
    report+="• $name: skipped sync (uncommitted changes present)"$'\n'
    continue
  fi

  git -C "$WT" fetch --quiet origin "$base"
  before="$(git -C "$WT" rev-parse origin/"$base")"
  onto_local="$(git -C "$WT" merge-base HEAD origin/"$base")"
  if [[ "$before" == "$onto_local" ]]; then
    report+="• $name: already up to date with $base"$'\n'
    continue
  fi

  if git -C "$WT" rebase --quiet "origin/$base" 2>/dev/null; then
    report+="• $name: rebased claude/continuous-ux onto $base (merged fixes dropped)"$'\n'
  else
    git -C "$WT" rebase --abort 2>/dev/null || true
    report+="⚠️ $name: rebase onto $base hit conflicts — left as-is, sync manually"$'\n'
  fi
done

printf '%s' "$report"
