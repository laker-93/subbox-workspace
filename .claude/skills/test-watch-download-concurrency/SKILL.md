---
name: test-watch-download-concurrency
description: Drive the subbox-app end-to-end regression test that proves a playlist download progresses cleanly while the watch-dir uploader is active (the watcher is deferred for the whole download, then resumes). Use when the user wants to "test the watch/download concurrency fix", "check that a watch-dir upload doesn't crash/hang an in-progress download", "verify the watchPaused / stream.pipeline sync fix", or re-run this regression. Local dev stack only. Runs scripts/qa/watch-download-concurrency.mjs in the ../feishin-qa worktree; can point at an uncommitted fix in the main ../feishin checkout via QA_APP_ENTRY.
---

# Test: watch-dir upload vs. in-progress download

Verify the coordination in subbox-app `src/main/features/core/sync/index.ts` that
keeps a **playlist download** clean while the **watch-dir uploader** is running.
Background, verified behavior, and gotchas live in the feature doc:
`../feishin-qa/docs/qa/features/watch-download-concurrency.md`. **Read it first.**

The fix (two parts): a module-level `watchPaused` flag the download sets (after
awaiting any in-flight poll) and clears in a `finally`, so `pollAndUpload()`
early-returns and the watch upload is **deferred** for the whole download; and
`stream.pipeline` (not `.pipe()`) so a mid-download source error rejects instead
of leaving the download Promise hung forever.

**Local dev stack only. Never staging/prod.** No code changes — this only drives
and observes.

## What the driver does

`../feishin-qa/scripts/qa/watch-download-concurrency.mjs` launches the built
Electron app, starts the real watcher on a temp folder holding a track, warms it
up, then fires a real download and **times it by awaiting the
`sync:download-playlists` IPC promise** (its resolve == the moment the `finally`
clears `watchPaused`). It asserts: download resolves cleanly (returns
`tracksExported`); **zero** watch scan/upload ticks inside the download window;
watcher resumes after. Prints a per-tick timeline and `OVERALL: PASS/FAIL`.

## Steps

1. **Stack up?** `docker ps` — expect `traefik`, `pymix`, `player`,
   `navidrometest260526`, `beetstest260526`, `pymix-postgres`, `filebrowser`. If
   not, bring the stack up (`../traefik/docker-compose.yml`) first.
2. **pymix idle?** `docker logs pymix --tail 20` — if the user is mid-manual-test,
   pause. This test only reads/downloads (no destructive server writes), but be
   courteous.
3. **Build the app under test** (dev mode — bakes the local `pymix.docker.localhost`
   URL; plain `build:electron` would bake the prod URL):
   - Testing an **uncommitted fix** in the main checkout: build there —
     `cd ../feishin && pnpm exec electron-vite build --mode development` — and run
     with `QA_APP_ENTRY=../feishin/out/main/index.js`.
   - Testing this QA worktree's own build: `cd ../feishin-qa && pnpm exec
     electron-vite build --mode development` (once the fix has landed here).
   Confirm the fix compiled in: `grep -c watchPaused out/main/index.js` (>0) and
   `grep -o 'stream/promises' out/main/index.js`.
4. **Run the small case** (fast sanity):
   ```bash
   cd ../feishin-qa
   QA_APP_ENTRY=../feishin/out/main/index.js QA_PLAYLIST=Kodzo \
     node scripts/qa/watch-download-concurrency.mjs
   ```
   Expect `OVERALL: PASS`.
5. **Run the "large amount of missing tracks" case** — the real scenario. Empty
   the dev library (all tracks become missing → a multi-second download spanning
   many poll cycles), **backing it up first, and restore after**:
   ```bash
   D="$HOME/Library/Application Support/subbox-dev"; cp -a "$D/music" /tmp/subbox-music-bk
   rm -rf "$D/music"/*
   QA_APP_ENTRY=../feishin/out/main/index.js QA_PLAYLIST=__ALL__ \
     node scripts/qa/watch-download-concurrency.mjs
   rm -rf "$D/music"; cp -a /tmp/subbox-music-bk "$D/music"   # ALWAYS restore
   ```
   Expect a multi-second `download IPC window`, `tracksExported` = the full set,
   **0 active ticks** during the window (vs. ~N polls that would normally fire),
   watcher resumed after, and `OVERALL: PASS`.
6. **Restore the dev library** if you emptied it (step 5's last line). Verify it's
   back: `find "$HOME/Library/Application Support/subbox-dev/music" -type f | wc -l`.

## Interpreting failure

- **`FAIL` on "completed cleanly" with a hang** (window ≈ 180s, `ok=false`) — the
  download Promise never settled: the core bug the fix prevents. Real regression.
- **`FAIL` on "no work during download"** (>0 active ticks) — a watch poll ran
  concurrently: `watchPaused` isn't engaging. Check it's set before the first
  `await` and cleared only in `finally`; confirm the window is IPC-bounded (the
  driver already does this — see the feature doc's gotchas).
- **`err=Must have a username or session ID`** — the pymix session wasn't
  bootstrapped; the driver runs "Preview Download" first to fix this, so this
  means that UI step didn't complete (check the playlist name resolved).

Env knobs: `QA_PLAYLIST` (name(s) / `__ALL__`), `QA_POLL_MS` (default 800),
`QA_RB_XML=1` (also fetch the Rekordbox XML — off by default, unrelated path).
