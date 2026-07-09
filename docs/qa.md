# QA — the continuous-UX loop

Subbox's QA is not a test suite you run once. It is a **long-running, self-paced
loop** that emulates a real user's end-to-end experience of the platform, fixes
bugs and small UX friction conservatively, and writes down what it verified so
the next run doesn't start from zero. This doc is the cross-repo orientation for
it; the loop's own operating rules live in the journals it reads (below).

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
| `directives.md` | **User-steered focus.** Checked *first*, every cycle — a PENDING/IN-PROGRESS entry always beats the loop's own rotation | client only |
| `bugs.md` | Correctness bugs, `OPEN` (unverified/risky/cross-repo) vs `FIXED` (links commit) | both |
| `ux-notes.md` | UX friction — rough-but-working, not outright wrong; `OPEN` / `RESOLVED` / `IMPROVED` | client only |
| `features/*.md` | One file per feature/workflow, **written only once actually driven and verified** (not from reading source) — treated as ground truth for "expected behavior" thereafter | both |
| `log.md` | One terse line per cycle: timestamp, area, outcome (`verified` / `documented` / `bug-fixed` / `ux-improved` / `logged` / `blocked`) | both |

### How the user steers it

Add a directive in `../feishin-qa/docs/qa/directives.md` (either tell the running
loop session directly, or edit the file's `PENDING` section by hand). A directive
can be a large multi-step journey; the loop breaks it into sub-steps across
cycles and only moves it to `DONE` once verified end-to-end.

## One cycle, in order

1. **Pick the work** — first match wins: client `directives.md` IN PROGRESS →
   PENDING → an `OPEN` entry in either `bugs.md`/`ux-notes.md` → next unchecked
   item on a README coverage checklist. Don't grind one repo when the other has
   open items.
2. **Get a real app to drive** (see below) — actually click/fill/sync, don't just
   screenshot.
3. **Fix conservatively, or log it.** A fix ships only if it's confidently
   root-caused, single-repo, and re-verified by re-running the exact flow. Else it
   goes to `bugs.md`/`ux-notes.md` as `OPEN`. Cross-repo issues are **logged on
   both sides, never fixed one-sidedly.**
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
   Dockerfile . --load` from `../pymix-qa`.
3. Point the traefik compose `pymix` service at `laker93/pymix:qa-local`,
   `docker compose up -d pymix`, confirm clean startup (Alembic ran).
4. Note in `log.md` that you swapped the running container's tag.
5. Run `pytest pymix/tests` (venv at `../pymix-qa/.venv`) before committing.

## Hard rules (do not relax — repeated from the journals)

- **Bug fixes and small UX improvements only.** No new features, refactors, or
  redesigns.
- **Conservative:** a fix is committed only after re-running the exact flow that
  exposed the issue. Anything uncertain, subjective, or cross-repo is logged, not
  committed.
- **One fix commit per cycle, per repo, max**, on `claude/continuous-ux` only.
- **Never push, never open a PR, never merge** to `development`/`main`. The user
  reviews and pushes manually.
- **Never touch staging or prod.** Local dev stack only. Never run destructive DB
  ops or write to a real user's per-user container.
- **Never bypass `SUBBOX_ID` tagging** on the pymix side (see root `CLAUDE.md`).
- **Cross-repo bugs are logged on both sides, never fixed one-sidedly** — a pymix
  fix that needs a matching subbox-app change (or vice versa) is one feature; log
  both `bugs.md` files and stop.
