---
name: upload-music-dev
description: Upload music into the dev Subbox library by driving the app's Sync -> Watch (watch-dir uploader) UI, pointed at a source directory of audio files. Use when the user wants to "upload tracks/music to dev", "test the upload / watch functionality", "add N tracks from <dir> to the dev app", "populate the dev library via upload", or similar. Copies the source files into a throwaway staging watch dir first, so the originals are never mutated. Local dev stack only — writes to a live per-user container. Runs scripts/qa/watch-upload.mjs in the ../feishin-qa worktree; can drive an uncommitted build in ../feishin via QA_APP_ENTRY.
---

# Upload music via the watch-dir uploader (dev)

Upload audio files into the logged-in dev user's Subbox library through the real
**Sync → Watch** UI, pointed at a **source directory**. Verified behavior, the
upload path, and gotchas live in the feature doc:
`../feishin-qa/docs/qa/features/watch-upload.md`. **Read it first.**

The driver `../feishin-qa/scripts/qa/watch-upload.mjs`:

1. **Copies** up to `QA_UPLOAD_LIMIT` audio files from `QA_SOURCE_DIR` into a
   throwaway staging dir (recursive, relative paths preserved). Copy, never move —
   **the watcher writes a `SUBBOX_ID` tag into every file it sees, so we never let
   it touch the originals.**
2. Launches the Electron build, logs in (shared helpers), stubs the native folder
   picker → staging dir.
3. Drives the genuine UI: **Sync → Watch → Select Directory → Start Watching**,
   then records `sync:watch-progress` and waits for the uploader to drain.

## Boundaries — read before running

- **Writes to a live dev user.** Uploads land in that user's per-user container
  (filebrowser → pymix import → Navidrome). **Local dev stack only. Never
  staging/prod.** This is a mutating exerciser, not a read-only test.
- **`subbox` vs `subbox-dev`.** The source dir is anything you point at (e.g. the
  personal `~/Library/Application Support/subbox/music`). It is *not* the dev
  local library (`subbox-dev/music`, which is the *download* destination). Fine to
  upload *from* `subbox/music` — the driver copies, so those originals stay
  pristine.
- **Build in dev mode** so the app targets `pymix.docker.localhost` — plain
  `build:electron` bakes the prod URL.

## Steps

1. **Stack up?** `docker ps` — expect `traefik`, `pymix`, `player`,
   `navidrometest260526`, `beetstest260526`, `pymix-postgres`, `filebrowser`. If
   not, bring up `../traefik/docker-compose.yml` first.
2. **pymix idle & right account?** `docker logs pymix --tail 20`. Confirm with the
   user *which* dev account should receive the upload (default test account
   `test260526`) — this writes real tracks into that user's library.
3. **Build the app under test** (dev mode):
   - Uncommitted build in the main checkout: `cd ../feishin && pnpm exec
     electron-vite build --mode development`, then run with
     `QA_APP_ENTRY=../feishin/out/main/index.js`.
   - This QA worktree's own build: `cd ../feishin-qa && pnpm exec electron-vite
     build --mode development`.
4. **Run the uploader:**
   ```bash
   cd ../feishin-qa
   QA_SOURCE_DIR="$HOME/Library/Application Support/subbox/music" \
   QA_UPLOAD_LIMIT=500 \
   QA_APP_ENTRY=../feishin/out/main/index.js \
     node scripts/qa/watch-upload.mjs
   ```
   Drop `QA_UPLOAD_LIMIT` to upload every file found. Watch the progress lines
   climb `uploaded=k/N`; expect `OVERALL: DONE`.
5. **Verify server-side (optional, async).** The watcher finishes at the
   filebrowser hand-off; the tracks then flow through pymix import + a Navidrome
   rescan before they appear in the library UI. Give it a minute, then check in
   the app (Albums/Songs) or `docker logs pymix` for the import.

## Env knobs

| Var | Default | Meaning |
|---|---|---|
| `QA_SOURCE_DIR` | — (**required**) | Directory of audio files to upload (recursed) |
| `QA_UPLOAD_LIMIT` | all | Max files to copy/upload |
| `QA_APP_ENTRY` | this worktree's build | `out/main/index.js` to launch |
| `QA_POLL_MS` | 2000 | Watch poll interval |
| `QA_WATCH_DIR` | fresh mkdtemp | Explicit staging dir |
| `QA_KEEP_WATCH_DIR` | unset | Keep the staging dir on exit |
| `QA_UPLOAD_TIMEOUT_MS` | 1200000 | Cap waiting for the uploader to drain |

## Interpreting the result

- **`DONE`, `uploaded == copied`** — all staged files uploaded.
- **`DONE`, `uploaded < copied`** — the rest were already present server-side
  (deduped by the "already uploaded" skip). Not an error.
- **`TIMED OUT`** — the uploader never drained within `QA_UPLOAD_TIMEOUT_MS`.
  Check the `main [Subbox]` log lines the driver prints (filebrowser 401s, EPIPE,
  a corrupt file that TagLib can't open → no `SUBBOX_ID`), and raise the timeout
  for very large batches.
