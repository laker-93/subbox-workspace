---
name: continuous-ux
description: Run one cycle of the continuous UX loop for subbox — emulate a real user's end-to-end experience of subbox-app (and pymix behind it), fix bugs and small UX friction conservatively, and document verified behavior for future cycles. Invoked repeatedly via /loop. Use when the user says "run the UX loop", "continue the continuous-ux loop", or /loop invokes this skill on its own.
---

# Continuous UX loop — one cycle

You are one cycle of a long-running, self-paced loop. **You have no memory of
previous cycles except what's written on disk** — the journals below are the
only continuity. Read before acting; write before finishing.

The mission is broader than bug-hunting: emulate a real user's end-to-end
experience of subbox (subbox-app client + pymix backend), notice both
outright bugs and UX friction (confusing, slow, or inconsistent — even if
technically "working"), and conservatively fix what you can verify. **No new
features, no refactors, no redesigns.** You improve what exists; you don't
add to it.

## Where things live

- Client worktree: `../feishin-qa` (or `../subbox-app-qa` if renamed), branch
  `claude/continuous-ux`, based on `development`.
- Backend worktree: `../pymix-qa`, branch `claude/continuous-ux`, based on `main`.
- Journals: `docs/qa/{README,directives,bugs,ux-notes,log}.md` in each
  worktree (pymix-qa has no `ux-notes.md` — it has no UI of its own).
- Local dev stack: `../traefik/docker-compose.yml` (traefik, player, pymix,
  pymix-postgres, filebrowser, per-user containers). Usually already running
  — check with `docker ps` before assuming you need to bring it up.

Read `../feishin-qa/docs/qa/README.md` and `../pymix-qa/docs/qa/README.md` in
full if you haven't already this session — they contain the hard rules
(conservative fix bar, one commit per repo per cycle, open a PR per fix but
never merge, never touch staging/prod, cross-repo coupling rule) and are the
source of truth if
anything here conflicts.

## Step 1 — figure out what this cycle works on

Check in this order, stop at the first match. In `directives.md` you only need
the `PENDING` and `IN PROGRESS` sections — the `DONE` section is just a pointer
to `directives-archive.md`, which you never need to read (it's inert history).

1. **`../feishin-qa/docs/qa/directives.md` → IN PROGRESS.** Resume it. Read
   its notes to figure out which sub-step it's on.
2. **`directives.md` → PENDING** (oldest first). Start it: move to IN
   PROGRESS, write your sub-step breakdown into its notes before doing
   anything else.
3. **`bugs.md` / `ux-notes.md` → OPEN**, in either journal. Pick one (prefer
   ones flagged as likely-fixable over ones flagged as needing a design
   call). Re ­verify it's still reproducible before attempting a fix.
4. **Coverage checklist** in either README — pick the next unchecked item.
   Alternate between client-only areas, backend-only workflows, and
   cross-cutting journeys that touch both; don't grind the same repo for many
   cycles in a row if the other has unchecked items.
5. **Self-directed discovery** (nothing above left — no directive, no OPEN
   item, every checklist row is `[x]`). You are never out of work; generate
   your own. Skim the last ~10 `log.md` lines first so you don't repeat a
   recent cycle, then pick the **least-recently-exercised** of these, rotating:
   - **Regression sweep.** Re-drive the feature whose `features/*.md` was
     verified longest ago (or one whose code moved — `sync-merged.sh` rebases
     onto the updated base each run, so a just-merged PR is prime ground).
     Confirm real behavior still matches the doc. A mismatch is a regression —
     treat it like any found bug (fix conservatively or log OPEN), and refresh
     the feature doc with the re-verified date. **If a `test-<feature>` skill
     covers that area, invoke it instead of re-deriving the journey by hand** —
     these skills (see the "Reusable `test-*` skills" note under Step 2) are the
     canonical, repeatable regressions. Enumerate the ones available in your
     skills list (names starting `test-`) and prefer the one whose feature doc
     was verified longest ago; any new `test-*` skill the user adds is therefore
     automatically in this rotation with no change here.
   - **Edge / error-state probing.** Take a covered happy path and exercise its
     unhappy edges a real user hits: empty states, invalid/oversized input,
     network failure mid-flow, slow/large libraries, rapid or concurrent
     actions, cancel/back mid-operation. Log friction to `ux-notes.md`, bugs to
     `bugs.md`.
   - **New coverage.** When any of the above surfaces a sub-flow, route, or
     interaction not yet tracked, **add a new row to the relevant README
     checklist** (the lists invite this) and drive it — this is how coverage
     grows itself over time rather than staying a fixed list.

   Discovery stays inside the same hard rules: you're finding and fixing/logging
   issues in what exists, never adding features or redesigning. When in doubt,
   log it OPEN rather than fix.

If a directive is large (spans multiple user actions/screens/repos — e.g.
"bulk-add N tracks, verify upload integrity, partition into playlists,
confirm efficient download"), treat each cycle as one sub-step, not the whole
thing. Update the directive's notes with exactly where you got to and what's
next, so the next cycle (fresh context) can pick up mid-journey correctly.

## Step 1½ — reconcile bug-tracking issues (cheap; every cycle)

Every `bugs.md` OPEN entry should have a GitHub issue behind it, and **a closed
issue means the bug was fixed in the base** — that's how the loop knows a bug is
fixed. Before the cycle's main work, reconcile; it's a couple of `gh` calls per
repo and keeps `bugs.md` honest:

- **Backfill.** Any OPEN `bugs.md` entry **without** an `Issue:` link (an older
  bug, or one logged before this was wired up) → file one now with
  `../subbox-workspace/qa-runner/open-issue.sh <that worktree> "<summary>"
  "<repro/evidence>"` and add the `Issue:` line. Every open bug must be tracked.
- **Close-out.** For each OPEN entry **with** an `Issue:` link, check the issue —
  `gh issue view <n> --repo <slug> --json state -q .state`. If it's `CLOSED`, the
  fix reached the base: either a QA PR you opened got merged, **or the user fixed
  it themselves in the main checkout and merged it**. Re-drive the exact flow to
  confirm the symptom is actually gone, then move the entry `OPEN → FIXED`, noting
  how it closed (the merged PR URL, or "fixed externally in `<base>` — issue
  #<n>"). If the symptom still reproduces despite a closed issue, **reopen it**
  (`gh issue reopen <n> --repo <slug>`) and record that in the entry — never
  silently mark a still-broken bug fixed.

This is the whole point of the issue trail: you (or the loop) can fix a bug in the
main checkout, merge it with `Closes #<n>`, and the next run notices the closed
issue and updates the journal on its own — no hand-editing of `bugs.md`.

## Step 2 — get a real app to drive

> **Run every driver in the foreground — never background a journey and yield.**
> This cycle often runs headless (`claude -p`, from `qa-runner/run-daily.sh`).
> In that mode, the moment you stop emitting tool calls and "wait" for a
> background job, the process **exits** — no interactive turn resumes it when
> the job finishes, so the journey's result is never processed and the cycle
> produces nothing (no verification, no `log.md` line, no commit). Therefore:
> run each Playwright/driver/monitor invocation as a **blocking** `Bash` call
> (default foreground) and let it finish before you continue. Do **not** pass
> `run_in_background: true` for a driver, and do **not** use `Monitor` /
> `ScheduleWakeup` to poll for a driver you launched. If a journey is slow, set
> a generous `timeout` on the blocking call (e.g. 300000–600000 ms) instead of
> backgrounding it. A cycle must never end with a driver still running.

Prefer the fastest loop that still reflects real behavior:

- **Client-only changes**: build with **`pnpm exec electron-vite build --mode
  development`** in `../feishin-qa` (NOT plain `pnpm run build:electron` — that
  defaults to Vite production mode and bakes in the real prod URL
  `pymix.sub-box.net` instead of the local stack `pymix.docker.localhost`; you'd
  then be driving the app against **production**, violating the hard rules). Then
  launch via Playwright's `_electron` — extend
  `scripts/ui-snapshot-electron.mjs` / `scripts/ui-snapshot-shared.mjs`
  rather than reinventing login/session handling. Put new driver scripts
  under `../feishin-qa/scripts/qa/`, importing the shared helpers
  (`performLogin`, `getCredentials`, `forceFreshLogin`, `waitForRouteSettled`,
  `hashUrl`). Take real actions (click, fill, drag, wait for state) — this is
  about exercising the app, not just screenshotting it. For a **multi-step flow
  with a long/async operation** (download, upload, import), drive it to a
  *terminal state* and treat a timeout as a real failure: `Promise.race` the
  success UI (e.g. "Download Complete") against the error UI, with a bounded
  timeout whose expiry means the flow **hung** — a hang is a bug to report, not a
  slow pass. Tap the Electron main process's stdout
  (`electronApp.process().stdout`) to capture the `[Subbox]` main-side logs.
  `scripts/qa/download-all.mjs` is the worked example of this pattern (sync →
  download all playlists → assert done-or-error, never hang).
- **pymix changes**: pymix runs in the local stack from a **pre-built Docker
  image**, not live-mounted source — editing `../pymix-qa` does not
  automatically apply. To verify a pymix-side fix:
  1. Check the shared `pymix` container looks idle first — `docker logs
     pymix --tail 50` for recent/in-flight activity. **This container may be
     in use by the user's own manual testing at the same time you're
     running.** If anything looks in-flight, don't restart it this cycle —
     log the fix as ready-but-unverified in `bugs.md` and move on.
  2. `docker buildx build --platform linux/amd64 --build-arg ... -t
     laker93/pymix:qa-local -f Dockerfile . --load` from `../pymix-qa`
     (mirrors the "Local builds for dev testing" flow in
     `docs/deployment.md` — pymix must build `linux/amd64` even on this
     arm64 laptop, since its `taglib` dependency won't compile under arm64
     (laker-93/pymix#27); it runs under emulation locally).
  3. Point `../traefik/docker-compose.yml`'s `pymix` service at
     `laker93/pymix:qa-local`, `docker compose up -d pymix`, confirm clean
     startup (`docker logs pymix --tail 40`, Alembic migration ran).
  4. Verify, then note in `log.md` that you restarted the shared container
     (so the user isn't confused later about why the tag changed).
  5. Run `pytest pymix/tests` (venv at `../pymix-qa/.venv`) before committing
     any pymix fix, in addition to the live-driven verification.
- For journeys needing bulk test data (e.g. "500 tracks"), generate it into a
  clearly-scratch location and, where the flow being tested is the import
  itself, real files; don't fabricate results by hand. Use an obviously-named
  test user/library so it's not confused with the user's own real data. Note
  in the relevant `features/*.md` where the scratch data lives so a later
  cycle can reuse or clean it up instead of re-generating it blind.
- To exercise the **wishlist → download → import** path in the background, use
  the `wishlist-import-dev` skill: it seeds the `test260526` wishlist via the
  pymix API and runs `../subbox-slskd/scripts/download_wishlist.py` against the
  local stack (dry-run + capped by default). Good for keeping the import path
  covered without a full manual journey. It's local-dev/test-user only and
  self-cleans; read its SKILL.md for the resolve-state gate and watch-dir wiring.
- **Reusable `test-*` skills — the canonical regression drivers.** A skill named
  `test-<feature>` (e.g. `test-watch-download-concurrency`) is a repeatable,
  pass/fail regression for one feature: it wraps a driver in `scripts/qa/`, reads
  a `docs/qa/features/<feature>.md` doc, and launches via `resolveAppEntry` (so it
  can drive this worktree's build **or**, with `QA_APP_ENTRY`, an uncommitted build
  in the main checkout). **When one exists for the area you're working, run it via
  its skill rather than hand-rolling the flow** — it's the source of truth for that
  feature's expected behavior, and the same skill the user runs by hand during
  feature work. The set is open: any `test-*` skill in your skills list is fair
  game, and the Step 5 regression sweep rotates through them automatically. (Pure
  exercisers like `wishlist-import-dev` — non-deterministic seed/download helpers,
  not pass/fail — are deliberately **not** `test-*`; invoke them situationally.)
  When a directive makes you build a durable new regression driver, prefer wiring
  it up as a `test-<feature>` skill so both you and the user inherit it.

## Step 3 — do the work

- Drive the journey like a real user would, across screens, not one route in
  isolation.
- When something looks wrong, cross-reference source in both worktrees to
  find the actual root cause before deciding it's a bug.
- **Bug or friction found:**
  - **First, file a GitHub tracking issue for it — every bug gets one,** whether
    or not you can also fix it this cycle. Check the matching `bugs.md` entry
    doesn't already carry an `Issue:` link (if it does, it's already filed — do
    **not** re-file). Otherwise run `../subbox-workspace/qa-runner/open-issue.sh
    <that worktree path> "<one-line summary>" "<repro + evidence + hypothesis>"`
    — it files the issue on the real repo (labelled `qa-bug`) and prints the URL.
    Paste that URL into the `bugs.md` entry as an `Issue: <url>` line. The daily
    digest links every issue filed this run. (A pure UX-friction note in
    `ux-notes.md` does not need an issue — this is for `bugs.md` correctness bugs.)
  - Confidently root-caused, scoped, single-repo, and you can fully
    re-verify the fix by re-running the same flow → implement it, run that
    repo's own checks (client: `pnpm typecheck && pnpm lint-code`; pymix:
    `pytest pymix/tests`), re-drive the flow to confirm, then **one commit**
    on that repo's `claude/continuous-ux` branch. Reference the journal entry
    in the commit message, and include a `Closes #<n>` line (n = the issue
    number from the bug's `Issue:` URL) so merging the PR auto-closes the
    tracking issue. Then **open a PR for it**: run
    `../subbox-workspace/qa-runner/open-pr.sh <that worktree path>` (HEAD =
    the fix commit) — it cuts a clean branch off the repo's base
    (`development`/`main`), copies the commit body (so `Closes #<n>` carries into
    the PR), pushes, opens **one PR labelled `qa-auto`**, and prints the URL. Put
    that PR URL in the `bugs.md` `FIXED` entry alongside the existing `Issue:`
    link. Never merge — when you merge the PR, GitHub closes the issue.
  - Needs a matching change in the *other* repo to fix the user-facing
    symptom → implement **both** sides (one commit per repo on each
    `claude/continuous-ux` branch), but commit **only** after re-driving the
    full flow with both changes live: rebuild the pymix image to
    `laker93/pymix:qa-local` and swap the running container (confirm it's idle
    first) *and* rebuild the Electron client, then reproduce the original
    symptom and confirm it's gone. Cross-reference both commit SHAs in the two
    `bugs.md` files. A cross-repo bug gets **an issue on each affected repo**
    (`open-issue.sh` on each worktree, cross-linked in their bodies); each repo's
    fix commit carries `Closes #<n>` for *its own* repo's issue. Then open
    **two PRs** — `open-pr.sh` on each worktree — and cross-link them (`gh pr
    comment` each with the other's URL, noting they must be merged together). If
    you can't verify both sides end-to-end this cycle, do **not** ship a one-sided
    fix — log both sides OPEN and stop there (the issues stay open, tracking it).
  - Ambiguous, subjective, or you can't fully verify → log to `bugs.md` /
    `ux-notes.md` as OPEN with enough detail (repro, evidence, hypothesis)
    that a future cycle — or the user — can pick it up cold. The `bugs.md`
    tracking issue you filed above stays open; that's how the user picks it up
    and tracks whether it later gets fixed in `development`/`main`.
- Write or update the relevant `features/*.md` with what you actually
  verified (behavior, not source-reading assumptions).
- Update `directives.md` if you were working one. If you fully verified a
  directive end-to-end this cycle, **compact it to a one-line + link entry in
  `directives-archive.md` and delete it from `directives.md`** (the full
  writeup already lives in `features/*.md`) — keep `directives.md` lean so every
  cycle reads it cheaply.
- Append one line to `log.md`.
- Kill any Electron process / dangling browser context you launched.

## Hard limits (repeated from the journals — do not relax)

- Bug fixes and small UX improvements only. Never new features/refactors/redesigns.
- Conservative: verified fix or it doesn't get committed.
- One fix commit per cycle, per repo, max.
- Run drivers in the **foreground** and finish them within the cycle — never
  background a journey and yield waiting for a completion notification. Under
  headless `claude -p` that just kills the cycle silently (see Step 2).
- Never push, never open a PR, never merge to `development`/`main`.
- Never touch staging or prod, ever, for any reason.
- Never run destructive DB ops or touch a real user's per-user container.
- Never skip or bypass `SUBBOX_ID` tagging on the pymix side.
- If blocked (dev stack down, credentials missing, nothing left to do) —
  log it plainly in `log.md` as `blocked` with why, and end the cycle rather
  than retrying in a hot loop. Let the loop's own pacing back off.
