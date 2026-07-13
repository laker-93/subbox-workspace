---
name: test-sync-plan-matching
description: Drive the subbox-app + pymix end-to-end regression that proves a playlist download preview no longer reports tracks the user already has as "missing locally". Use when the user wants to "test the sync-plan false-missing fix", "check the duplicate-subbox_id / no-album-folder sync fixes", "verify tracks aren't wrongly reported missing in the download preview", or re-run this regression. Local dev stack only. Runs scripts/qa/sync-plan-classification.mjs + make-dup-playlist.mjs in the ../feishin-qa worktree; can point at an uncommitted client build in ../feishin via QA_APP_ENTRY, and requires a pymix image carrying the matched_subbox_ids fix.
---

# Test: sync-plan classification (no false "missing locally")

Verify the pair of fixes that stop the Sync → Download **preview** from flagging
tracks the user already has, correctly tagged, as missing:

- **pymix** `sync_plan()` (`pymix/routers/sync.py`) — tracks matched state by
  `subbox_id` value, not just Python object identity, so a playlist that lists the
  **same song more than once** is satisfied by a single local copy instead of
  reporting every duplicate-past-first as missing. Grep proof:
  `grep -c matched_subbox_ids pymix/routers/sync.py` > 0.
- **subbox-app** `scanLocalTracks()` (`src/main/features/core/sync/index.ts`) —
  a generic recursive walk (not a fixed `music/<artist>/<album>/<title>` depth), so
  a track stored with **no album folder** (`music/<artist>/<title>`) is discovered,
  tagged, and matched instead of silently skipped → always missing.

Full background and the exact numbers this test produced live in the feature doc
`../feishin-qa/docs/qa/features/sync-plan-classification.md`. **Read it first.**

**Local dev stack only. Never staging/prod.** The drivers only read/preview and
create a throwaway Subsonic playlist they delete on the next run.

## The drivers

- `../feishin-qa/scripts/qa/sync-plan-classification.mjs` — launches the built
  Electron app, logs in, bootstraps the pymix session via one UI "Preview
  Download", then calls `POST /sync/plan` directly (in-page fetch, same session the
  renderer uses) and prints the **structured** plan: `tracks requested / already
  present / MISSING / metadata updates`, plus the missing list. Asserts when
  `QA_EXPECT_MISSING` / `QA_EXPECT_PRESENT` are set (exit non-zero on mismatch).
  `localTracks` come from the **real** client scan (`sync:get-local-tracks`,
  exercising `scanLocalTracks`) unless `QA_LOCALTRACKS=<file.json>` overrides them.
- `../feishin-qa/scripts/qa/make-dup-playlist.mjs` — builds the change-A fixture: a
  Subsonic playlist ("QA Dup Test") listing one song `QA_DUP_COUNT` times (default
  3). **Pass `QA_SONG_ID` of a track that IS present in the dev local library and
  SUBBOX_ID-tagged** — otherwise every occurrence is legitimately missing and the
  test can't tell the fix from a genuinely-absent track.

## Setup

1. **Stack up?** `docker ps` — expect `traefik`, `pymix`, `player`,
   `navidrometest260526`, `beetstest260526`, `pymix-postgres`, `filebrowser`.
2. **pymix has the fix?** `docker exec pymix grep -c matched_subbox_ids
   /app/pymix/routers/sync.py`. If `0`, the running image predates the fix — the
   change-A test will (correctly) FAIL. Build+run a pymix image from the fix branch
   first (see `/build-and-push-image` / `/run-local-stack`). Change B (no-album
   folder) is client-only and does not need the pymix rebuild.
3. **Client build under test** (dev mode — bakes `pymix.docker.localhost`; plain
   `build:electron` would bake the prod URL):
   `cd ../feishin && pnpm exec electron-vite build --mode development`, then run
   drivers with `QA_APP_ENTRY=../feishin/out/main/index.js`. Confirm the fix
   compiled in: `grep -c 'walk\|processAudioFile' out/main/index.js` > 0.

## Run

Follow the cross-repo test plan
`subbox-workspace/docs/testplans/sync-plan-false-missing.md` for the full
sequence. The two core assertions:

```bash
cd ../feishin-qa

# Change A — duplicate subbox_id. Build the fixture on a PRESENT track, then assert.
QA_APP_ENTRY=../feishin/out/main/index.js QA_SONG_ID=<present-tagged-song-id> \
  node scripts/qa/make-dup-playlist.mjs                      # prints "QA Dup Test", 3 entries
QA_APP_ENTRY=../feishin/out/main/index.js QA_PLAYLIST="QA Dup Test" \
  QA_EXPECT_MISSING=0 QA_EXPECT_PRESENT=3 \
  node scripts/qa/sync-plan-classification.mjs               # expect OVERALL: PASS

# Change B — no-album-folder track (see the test plan for the mv/restore fixture steps).
QA_APP_ENTRY=../feishin/out/main/index.js QA_PLAYLIST="<playlist>" \
  QA_EXPECT_MISSING=<n> node scripts/qa/sync-plan-classification.mjs
```

## Interpreting failure

- **Change-A FAIL: `tracksMissing` = N-1, `tracksAlreadyPresent` = 1** — the exact
  pre-fix signature: only the first occurrence matched, the rest fell through to
  missing. Either the running pymix lacks `matched_subbox_ids` (rebuild it) or the
  fix regressed.
- **Change-B FAIL: the relocated track shows missing** — `scanLocalTracks` isn't
  discovering it at its depth; the fixed-depth walk is back, or the recursive walk
  skipped it. Check the driver's `localTracks` count and subboxId coverage line.
- **`POST /sync/plan failed: status=401/400`** — the pymix session didn't bootstrap;
  the UI "Preview Download" step didn't run (playlist row not found / not selected).
- Always kill any Electron process the driver spawned; delete the "QA Dup Test"
  playlist if you don't want it to linger (the next `make-dup-playlist` run does it).
