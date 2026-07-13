# QA — the continuous-UX loop

Subbox's QA is not a test suite you run once. It is a **long-running, self-paced
loop** that emulates a real user's end-to-end experience of the platform, fixes
bugs and small UX friction conservatively, and writes down what it verified so
the next run doesn't start from zero. This doc is the cross-repo orientation for
it; the loop's own operating rules live in the journals it reads (below).

But the same machinery is **reusable outside the loop**: while building a feature
you can point a QA test at your working-tree code, and any reusable test you add
is automatically picked up by the loop. That two-way reuse is the whole design —
see "Reusing the framework beyond the loop" below.

## The architecture, in layers

The QA system is five layers, each decoupled from the next. The loop is only the
top two; the lower three are the reusable substrate a feature developer shares
with it.

| Layer | Lives in | Role | Detail doc |
|---|---|---|---|
| **Orchestration** | `qa-runner/` (bash + `discord.py` + launchd) | Runs the loop unattended daily, files issues/PRs, syncs merged code back, bridges to Discord. Knows nothing about *what* a test does. | `qa-runner/README.md` |
| **Loop policy** | `.claude/skills/continuous-ux/SKILL.md` | Defines one cycle: pick work → drive → fix/log → journal. | this doc + the skill |
| **Persistent state** | `docs/qa/*` in each QA worktree | The loop's only memory: `bugs / ux-notes / features / log / directives`. | "The journals" below |
| **Named test capabilities** | `test-<feature>` skills in `.claude/skills/` | Repeatable, pass/fail regressions for one feature — the reuse seam (below). | each skill's `SKILL.md` |
| **Executable primitives** | `<worktree>/scripts/qa/*.mjs` + `scripts/ui-snapshot-shared.mjs` | The actual Playwright journeys and shared login/session/`resolveAppEntry` helpers every driver is built on. | "Driving the app" below |

The orchestration layer (`qa-runner/`) is fully self-contained and documented in
its own README — don't duplicate it here. This doc owns the middle three layers.

## The two moving parts

**1. The skill.** `subbox-workspace/.claude/skills/continuous-ux/SKILL.md` defines
one *cycle* of the loop. It's invoked repeatedly via `/loop` (or when the user
says "run the UX loop" / "continue the continuous-ux loop"). Each cycle is a
**fresh context with no memory of previous cycles** — everything it needs to
continue is on disk in the journals.

**2. Two dedicated QA worktrees.** The loop never works on the main checkouts. It
works on two sibling git worktrees pinned to branch `claude/continuous-ux`:

| Worktree | Worktree of | Branch base | Has UI? |
|---|---|---|---|
| `../feishin-qa` (client) | `subbox-app` / `../feishin` | `development` | yes (Electron) |
| `../pymix-qa` (backend) | `../pymix` | `main` | no |

> These are real `git worktree`s of the two core repos — same remotes, a separate
> `claude/continuous-ux` branch and working tree so the loop's commits never touch
> the checkout you're actively developing in. If a worktree is renamed (e.g.
> `../subbox-app-qa`), the skill accounts for it; resolve by relative path.

pymix has no UI of its own, so its "user experience" is whatever subbox-app users
feel *because of* pymix behavior — slow imports, flaky syncs, confusing errors the
client surfaces verbatim. Backend cycles exercise the API directly (curl/httpie
against `https://pymix.docker.localhost`) or trace a client symptom back to pymix.

## The journals — the loop's only memory

Each worktree has a `docs/qa/` directory. **Read these before anything else** each
cycle; they are the source of truth and contain the hard rules.

| File | What it is | Which worktree |
|---|---|---|
| `README.md` | Mission, hard rules, and a feature/workflow **coverage checklist** | both |
| `directives.md` | **User-steered focus.** Checked *first*, every cycle — a PENDING/IN-PROGRESS entry always beats the loop's own rotation. Kept lean: only PENDING/IN-PROGRESS live here | client only |
| `directives-archive.md` | Completed directives, compacted to one line + a link to the feature doc. **The loop never reads it** — inert history for a human | client only |
| `bugs.md` | Correctness bugs, `OPEN` (unverified/risky/cross-repo) vs `FIXED` (links commit) | both |
| `ux-notes.md` | UX friction — rough-but-working, not outright wrong; `OPEN` / `RESOLVED` / `IMPROVED` | client only |
| `features/*.md` | One file per feature/workflow, **written only once actually driven and verified** (not from reading source) — treated as ground truth for "expected behavior" thereafter | both |
| `log.md` | One terse line per cycle: timestamp, area, outcome (`verified` / `documented` / `bug-fixed` / `ux-improved` / `logged` / `blocked`) | both |

### How the user steers it

Add a directive in `../feishin-qa/docs/qa/directives.md` (either tell the running
loop session directly, or edit the file's `PENDING` section by hand). A directive
can be a large multi-step journey; the loop breaks it into sub-steps across
cycles and only retires it to `directives-archive.md` (a one-line + link entry)
once verified end-to-end.

## One cycle, in order

1. **Pick the work** — first match wins: client `directives.md` IN PROGRESS →
   PENDING → an `OPEN` entry in either `bugs.md`/`ux-notes.md` → next unchecked
   item on a README coverage checklist → **self-directed discovery** (once all
   of the above are exhausted): a regression sweep of the oldest-verified
   feature, edge/error-state probing of a covered happy path, and expanding the
   checklist with sub-flows it finds. So the loop never runs dry — with no user
   directive it keeps discovering its own work. Don't grind one repo when the
   other has open items.
2. **Get a real app to drive** (see below) — actually click/fill/sync, don't just
   screenshot.
3. **Fix conservatively, or log it.** A fix ships only if it's confidently
   root-caused and re-verified by re-running the exact flow. A single-repo fix is
   one commit on that repo. A **cross-repo** fix is now allowed too, but only as a
   coordinated pair verified end-to-end with *both* sides live (see the hard rule
   below); if you can't verify both sides this cycle, log both `bugs.md` files as
   `OPEN` instead.
4. **Write it down** — update the relevant `features/*.md`, the directive notes,
   and append one line to `log.md`. Kill any Electron/browser process you spawned.

## Driving the app

Everything runs against the **local dev stack** (`../traefik/docker-compose.yml`:
traefik, player, pymix, pymix-postgres, filebrowser, per-user containers) —
usually already up; `docker ps` before assuming otherwise.

**Client (subbox-app):** build Electron, then launch via Playwright `_electron`,
reusing the shared helpers in `../feishin-qa/scripts/ui-snapshot-shared.mjs`
(`performLogin`, `getCredentials`, `forceFreshLogin`, `waitForRouteSettled`).
Put new driver scripts under `../feishin-qa/scripts/qa/` (e.g. `sync-smoke.mjs`),
not in the snapshot scripts.

> **Build trap:** use `pnpm exec electron-vite build --mode development`, **not**
> plain `pnpm run build:electron`. The latter defaults to Vite production mode and
> bakes in the real prod pymix URL (`pymix.sub-box.net`) instead of the local
> stack (`pymix.docker.localhost`).

A dev build's **local library** is isolated to `~/Library/Application
Support/subbox-dev/music` (the `-dev` suffix `getAppPath()` applies when
`NODE_ENV === 'development'`), separate from a staging/prod `subbox/music`
collection on the same machine — so the loop can drive sync download/export
without touching a real personal library. It starts empty and populates via
download (the populated test libraries live server-side in the per-user
`navidrome<user>` containers, not this local mirror).

Known local dev test account (in `.env.ui-snapshot.local`, gitignored):
`test260526` / `1234test260526` — matches the `navidrometest260526` /
`beetstest260526` containers and has a real populated library, so it's good for
realistic journeys, not just empty-state smoke.

**Backend (pymix):** pymix runs from a **pre-built Docker image**, not live-mounted
source — editing `../pymix-qa` does nothing until you rebuild. To verify a fix:

1. Check the shared `pymix` container is idle first (`docker logs pymix --tail 50`)
   — **the user may be manually testing against it simultaneously.** If anything's
   in-flight, log the fix as ready-but-unverified and move on; don't restart it.
2. `docker buildx build --platform linux/amd64 ... -t laker93/pymix:qa-local -f
   Dockerfile . --load` from `../pymix-qa`. **pymix must be built `linux/amd64` even
   on this arm64 laptop** — its `taglib` dependency won't compile under an arm64
   build ([laker-93/pymix#27](https://github.com/laker-93/pymix/issues/27)), so
   pymix builds as amd64 and runs under emulation locally.
3. Point the traefik compose `pymix` service at `laker93/pymix:qa-local`,
   `docker compose up -d pymix`, confirm clean startup (Alembic ran).
4. Note in `log.md` that you swapped the running container's tag.
5. Run `pytest pymix/tests` (venv at `../pymix-qa/.venv`) before committing.

## Reusing the framework beyond the loop

The loop is not the only consumer of the QA drivers and test skills. The design is
deliberately **bidirectional** — the same primitives serve a feature developer and
the loop, so neither has to reinvent the other's tests.

### Direction 1 — drive a QA test against the code you're editing

Every driver in `../feishin-qa/scripts/qa/*.mjs` launches the Electron build via
`resolveAppEntry()` (exported from `scripts/ui-snapshot-shared.mjs`). By default it
launches **this worktree's** build (`feishin-qa/out/main/index.js`); set
`QA_APP_ENTRY` to launch a build from anywhere else — most usefully an **uncommitted
fix in your main dev checkout**:

```bash
# build your working-tree change (dev mode — bakes the LOCAL pymix URL)
cd ../feishin && pnpm exec electron-vite build --mode development
# run any QA journey against that build
cd ../feishin-qa
QA_APP_ENTRY=../feishin/out/main/index.js node scripts/qa/watch-download-concurrency.mjs
```

This is what makes a request like *"test the latest code against the concurrent
upload/download case"* just work: the test lives in the QA worktree, but it drives
**your** binary. `resolveAppEntry` is a shared convention — every driver honors
`QA_APP_ENTRY`, not just one.

### Direction 2 — reusable `test-<feature>` skills, shared both ways

A skill named **`test-<feature>`** (e.g. `test-watch-download-concurrency`) is the
reuse unit: a repeatable, pass/fail regression for one feature. Each one is three
colocated pieces —

- a driver at `../feishin-qa/scripts/qa/<feature>.mjs` (launches via `resolveAppEntry`),
- a verified-behavior doc at `../feishin-qa/docs/qa/features/<feature>.md`,
- the `SKILL.md` that ties them together and states the local-dev-only boundaries.

Because it's a skill, **both** consumers reach it the same way:

- **You**, mid-feature, invoke it by name to regression-check your change (Direction 1
  applies — it can target your uncommitted build via `QA_APP_ENTRY`).
- **The loop** enumerates `test-*` skills in its self-directed regression sweep
  (`SKILL.md` Step 5) and rotates through them, preferring the one whose feature doc
  was verified longest ago. **Any new `test-*` skill you add is therefore picked up
  automatically — no change to the loop.**

So the flow is symmetric: a regression you build while shipping a feature becomes a
loop regression for free, and a driver the loop builds is one you can run by hand.
When a directive has the loop build a durable new driver, it should wrap it as a
`test-<feature>` skill for exactly this reason.

> **Not every QA skill is a `test-*`.** Non-deterministic *exercisers* — e.g.
> `wishlist-import-dev`, which seeds a wishlist and kicks off real Soulseek
> downloads (dry-run/capped by default) — are intentionally **not** `test-*`: they
> have no clean pass/fail. The loop invokes them situationally rather than as part
> of the regression rotation. Reserve `test-<feature>` for repeatable assertions.

## Hard rules (do not relax — repeated from the journals)

- **Bug fixes and small UX improvements only.** No new features, refactors, or
  redesigns.
- **Conservative:** a fix is committed only after re-running the exact flow that
  exposed the issue. Anything uncertain, subjective, or cross-repo is logged, not
  committed.
- **One fix commit per cycle, per repo, max**, on `claude/continuous-ux` only.
- **Open a PR per verified fix; never merge.** After committing a verified fix to
  `claude/continuous-ux`, cut a clean PR branch off the real base and open **one PR
  per fix** (`qa-runner/open-pr.sh` does the cherry-pick-into-a-throwaway-worktree +
  push + `gh pr create`): base `development` for subbox-app, `main` for pymix. Label
  it `qa-auto`, record the PR URL in the matching `bugs.md` `FIXED` entry. **Never
  merge, never force-push a shared branch.** The user reviews and merges on GitHub;
  the next daily run syncs the merged code back (`qa-runner/sync-merged.sh` rebases
  `claude/continuous-ux` onto the updated base, dropping the merged fix). A
  cross-repo fix opens **two PRs, cross-linked and merged together.**
- **Every bug is tracked as a GitHub issue.** When the loop logs a bug in a
  `bugs.md`, it files an issue (`qa-runner/open-issue.sh`, label `qa-bug`) on the
  real repo and records the URL as an `Issue:` line in the entry. A fix commit/PR
  carries `Closes #<n>`, so merging it closes the issue — an open `qa-bug` issue
  means "still broken in the base". Each cycle reconciles: any OPEN `bugs.md` entry
  whose issue is now closed (a merged QA PR **or** a fix you pushed to the main
  checkout yourself) is re-verified and moved to `FIXED`. This is how a bug you fix
  by hand gets picked up and closed out without editing the journal manually.
- **Never touch staging or prod.** Local dev stack only. Never run destructive DB
  ops or write to a real user's per-user container.
- **Never bypass `SUBBOX_ID` tagging** on the pymix side (see root `CLAUDE.md`).
- **Cross-repo fixes ship as a coordinated pair, never one-sided.** A pymix fix
  that needs a matching subbox-app change (or vice versa) is one feature: implement
  both sides (one commit per repo, each on its own `claude/continuous-ux` branch)
  and commit them **only** after re-driving the full flow with *both* changes live
  — rebuild the pymix image to `laker93/pymix:qa-local` and swap the running
  container **and** rebuild the Electron client, then reproduce the original symptom
  and confirm it's gone. If you can't verify both sides end-to-end this cycle (e.g.
  the shared `pymix` container is busy with the user's manual testing, or the flow
  won't drive), fall back to logging both `bugs.md` files as `OPEN` and stop — the
  verify-before-commit gate is absolute. Record both commit SHAs in both `bugs.md`
  files (mark them `FIXED`).
