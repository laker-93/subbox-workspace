---
name: check-qa-runner
description: Check what the qa-runner (continuous-ux loop) actually did over a recent window — cycles run/failed, connectivity or infra errors, bugs found/filed, fixes committed, journal entries, currently-open bugs, and PRs awaiting review. Use when the user asks "check on the qa runner", "did the qa runner run", "what did QA find last night / over the last N days", "is the loop working", or similar status questions. Read-only.
---

# Check on the qa-runner

Answers "what happened" for the continuous-ux loop, distinct from *running* a
cycle (that's `/continuous-ux`) or checking a *live* in-progress batch (that's
`qa-runner/status.sh`, which only reports whether a run is active right now).
This skill looks backward over a window of days and separates three things
that are easy to conflate:

1. **Did the runner execute at all** (launchd firing, cycles completing vs.
   erroring out before doing any work).
2. **Did the cycles that ran find/fix anything** (journal entries, issues
   filed, PRs opened).
3. **What's still outstanding** (currently-OPEN bugs, unreviewed PRs) —
   not time-scoped, a standing snapshot.

Don't conflate them: a night with "0 cycles completed" found nothing because
nothing ran (infra failure) — that's a different, more urgent problem than a
night where cycles ran cleanly and genuinely found no bugs.

## Run it

```bash
bash .claude/skills/check-qa-runner/scripts/gather.sh <DAYS>
```

`DAYS` defaults to 2 if omitted. Pick it from the user's phrasing ("last
night" → 1, "the last couple days" → 2, "this week" → 7). The script is
read-only (launchctl list, gh pr list, and file reads only) and safe to run
directly — no confirmation needed.

It prints, in order:

- **launchd agents** — whether `com.subbox.qa-runner` / `com.subbox.qa-poller`
  are loaded, each one's last-exit-status column, and whether the runner is
  currently paused (`state/paused` flag).
- **Runs in window** — one block per `state/logs/<timestamp>/` run directory
  whose start time falls in the window: the posted digest verbatim, plus a
  `⚠️` line per cycle log that matched a known connectivity/infra failure
  signature (`API Error`, `ENOTFOUND`, `Request timed out`, `Connection
  closed`, `ECONNREFUSED`). Cycle logs are full `claude -p` transcripts —
  the script only flags the failure signatures, it does not dump full
  passing-cycle output (that's not useful for a status check).
- **Bug issues filed in window** — from `state/issues.log`, epoch-filtered.
- **Journal entries in window** — the actual `docs/qa/log.md` entries (one
  per cycle, terse but information-dense) from both `../feishin-qa` and
  `../pymix-qa`, date-filtered on each entry's leading `YYYY-MM-DD`.
- **Currently-OPEN bugs** — the live `## OPEN` section of each worktree's
  `docs/qa/bugs.md`, headings only (not time-scoped — this is "what's still
  broken right now," which matters even if none of it was found *this*
  window).
- **Open qa-auto PRs** — via `gh pr list`, labeled `qa-auto`, awaiting the
  user's review/merge.

## Synthesize, don't dump

The script's output is raw material, not the final answer — read it and
write a short status summary, the way you would after manually investigating:

- Lead with whether the runner actually ran and did work, since that's
  usually what "check on it" is really asking. A string of `0/N cycles
  completed` nights with the same error signature is the headline finding,
  not a footnote — say so plainly, and note if it's a **new** pattern vs.
  something already flagged (check `docs/qa/log.md`-adjacent context or ask
  if unsure whether the user already knows).
- If cycles did run: summarize what was verified/fixed/logged in plain
  language, not a re-paste of the journal's dense one-liners — pull out the
  bug, its issue number, and whether it was fixed or left OPEN for a design
  call.
- Mention currently-OPEN bugs and awaiting-review PRs only briefly (they're
  standing state, not new to this window) unless the user's question is
  specifically about outstanding work.
- If the window contains no runs at all (e.g. asked about a period before
  the runner existed, or it's been paused), say that plainly rather than
  presenting an empty report.

Keep the summary proportional to what happened — a clean night with one bug
found is a few sentences; several nights of infra failure deserves the
detail (which nights, what error, whether it's still happening now) since
that's actionable.
