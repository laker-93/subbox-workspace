# Test plan — "false missing-locally" sync fixes (subbox-app + pymix)

**For:** an AI agent (or engineer) executing e2e verification on the **local dev
stack**. Self-contained; assumes only the repo layout in
`subbox-workspace/CLAUDE.md`.

**Never run against staging or prod.** Every step here reads/previews or writes a
throwaway Subsonic playlist on the dev test account only.

---

## 1. What's under test

Two branches ship together as one logical fix: the Sync → Download **preview**
was reporting tracks the user already had, correctly tagged, as "missing
locally." Five changes, three of them worth real e2e coverage.

| # | Repo / branch | File | Change | The bug it fixes |
|---|---|---|---|---|
| **A** | pymix `add-subbox-id-recovery-scripts` | `pymix/routers/sync.py` `sync_plan()` | Matched state tracked by `subbox_id` **value**, not just object identity (`matched_subbox_ids`) | A playlist listing the **same song twice** reported every occurrence past the first as *missing*, even with a local copy present |
| **B** | subbox-app `fix/sync-plan-false-missing-tracks` | `src/main/features/core/sync/index.ts` `scanLocalTracks()` | Fixed-depth `artist/album/title` walk → **generic recursive walk** | A track stored with **no album folder** (`music/<artist>/<title>`) was silently skipped → always *missing* regardless of its SUBBOX_ID |
| **C** | subbox-app (same branch) | same file, download IPC | Watch uploader **paused** for the whole download (`watchPaused` + await in-flight poll) + `stream.pipeline` replaces `.pipe()` | A concurrent watch-upload dropped the download socket → download promise **hung forever** |
| **D** | subbox-app (same branch) | `getAppPath()` + `.env.*` + `app-config.ts` | Library dir from build-time `VITE_SUBBOX_APP_DIR` instead of runtime `NODE_ENV` | dev must stay isolated in `subbox-dev/`, staging/prod in `subbox/` |
| **E** | subbox-app (same branch) | `readSubboxId`/`writeSubboxId` | `findUserTextInformationFrame(..., false)` (don't create) + log unreadable tags | "tag present but unreadable" was indistinguishable from "no tag" (silent) |

A, B, C get dedicated tests below. D is a smoke check. E is observed as a side
effect (log line) during A/B.

**Common signal.** The bug for both A and B is the same user-visible symptom, so
the tests assert the same thing: **after the correct local files are present and
tagged, the plan reports 0 tracks "missing locally"** for the affected tracks.
The plan's `summary.tracksMissing` is the primary metric.

---

## 2. Capabilities this plan uses (already built)

| Capability | Location | Role |
|---|---|---|
| `sync-plan-classification.mjs` | `../feishin-qa/scripts/qa/` | Launches the app, logs in, bootstraps the pymix session via one UI "Preview Download", then `POST /sync/plan` and prints **structured** counts (`requested / present / MISSING / metadata`) + the missing list. Asserts on `QA_EXPECT_MISSING` / `QA_EXPECT_PRESENT`; exits non-zero on mismatch. |
| `make-dup-playlist.mjs` | `../feishin-qa/scripts/qa/` | Builds the change-A fixture: a Subsonic playlist ("QA Dup Test") listing one song `QA_DUP_COUNT`× (default 3). Idempotent (deletes a prior same-named playlist first). |
| `test-sync-plan-matching` skill | `subbox-workspace/.claude/skills/` | Named wrapper for this plan (re-run entry point for the QA loop). |
| `test-watch-download-concurrency` skill + `watch-download-concurrency.mjs` | existing | Covers change C unchanged. |

`sync-plan-classification.mjs` env vars: `QA_APP_ENTRY` (build to launch),
`QA_PLAYLIST` (name, comma-sep, required), `QA_LOCALTRACKS` (optional JSON
`LocalTrack[]` to send instead of a real scan), `QA_EXPECT_MISSING`,
`QA_EXPECT_PRESENT`, `QA_LIST_EXISTING=1`, `QA_MISSING_LIMIT`.

Credentials load automatically from `../feishin-qa/.env.ui-snapshot.local`.

---

## 3. Preconditions (do once, in order)

1. **Dev stack up.** `docker ps` shows: `traefik`, `pymix`, `player`,
   `navidrometest260526`, `beetstest260526`, `pymix-postgres`, `filebrowser`. If
   not, bring up `../traefik/docker-compose.yml`.

2. **pymix carries the change-A fix.**
   ```bash
   docker exec pymix grep -c matched_subbox_ids /app/pymix/routers/sync.py
   ```
   - `> 0` → ready.
   - `0` → the running image predates the fix. **Tests A/1 and A/3 will FAIL by
     design until you rebuild.** Build a pymix image from the fix branch and bring
     it up in the local stack (see `/build-and-push-image` then `/run-local-stack`,
     or the manual buildx flow in `docs/deployment.md`). Change B and C are
     client-only and do **not** need this.

   > Verified baseline: as of this plan's authoring the running `laker93/pymix:qa-local`
   > returned `0` (no fix) — see §6 for the pre-fix numbers that confirmed.

3. **Build the client under test (dev mode).** The fix lives on
   `fix/sync-plan-false-missing-tracks` in `../feishin`:
   ```bash
   cd ../feishin
   git branch --show-current            # expect fix/sync-plan-false-missing-tracks
   pnpm exec electron-vite build --mode development
   ```
   > **Build trap:** use `electron-vite build --mode development`, NOT
   > `pnpm run build:electron` (that bakes the prod `pymix.sub-box.net` URL).
   Confirm the fixes compiled in:
   ```bash
   grep -c watchPaused out/main/index.js        # >0  (change C)
   grep -c subboxDir out/main/index.js           # >0  (change D)
   grep -o 'stream/promises' out/main/index.js   # present (change C)
   ```
   All driver commands below use `QA_APP_ENTRY=../feishin/out/main/index.js`, run
   from `../feishin-qa`.

4. **Know the dev local library.** `~/Library/Application Support/subbox-dev/music`.
   Tests rely on some Kodzo tracks being present + SUBBOX_ID-tagged (they are, from
   prior runs). If empty, download the "Kodzo" playlist once through the app first.

---

## 4. The tests

### Test A/1 — pymix duplicate `subbox_id`, deterministic (change A)

**Purpose:** prove a playlist listing the same, locally-present song N× reports it
as present N×, not missing N-1×.

**Fixture:** pick a song that IS present in `subbox-dev/music` and tagged. A safe
choice is a non-missing Kodzo track. To find one, run a report-only pass first:
```bash
cd ../feishin-qa
QA_APP_ENTRY=../feishin/out/main/index.js QA_PLAYLIST=Kodzo QA_LIST_EXISTING=1 \
  node scripts/qa/sync-plan-classification.mjs
```
Any track under `--- existing ---` is present. Get its Subsonic id (the driver
prints artist/title; cross-reference via the app or `getPlaylist.view`). This
plan's authoring used **"Pat Martino — Welcome to a Prayer"**,
id `z3k1LP96daKuPtfovWXMvL`.

**Build the fixture and assert:**
```bash
QA_APP_ENTRY=../feishin/out/main/index.js QA_SONG_ID=<present-tagged-song-id> \
  QA_DUP_COUNT=3 node scripts/qa/make-dup-playlist.mjs
# → "QA Dup Test", 3 entries, all same: true

QA_APP_ENTRY=../feishin/out/main/index.js QA_PLAYLIST="QA Dup Test" \
  QA_EXPECT_MISSING=0 QA_EXPECT_PRESENT=3 \
  node scripts/qa/sync-plan-classification.mjs
```

**PASS:** `already present: 3`, `MISSING: 0`, `OVERALL: PASS`.
**Pre-fix signature (FAIL):** `already present: 1`, `MISSING: 2` — the two extra
occurrences listed under `--- missing ---` with the same artist/title. (This is
exactly what the unfixed image produced — §6.)

**Teardown:** the next `make-dup-playlist` run deletes it; or delete "QA Dup Test"
via the app / `deletePlaylist.view`.

---

### Test B/2 — no-album-folder track discovery (change B)

**Purpose:** prove a track stored at `music/<artist>/<title>` (no album folder) is
discovered by `scanLocalTracks` and matched, not reported missing.

**Fixture (relocate a present, tagged track up one level):**
```bash
D="$HOME/Library/Application Support/subbox-dev/music"
# Pick a present track that lives at <artist>/<album>/<title> and note its playlist.
# Example from a real library: Pat Martino / Live at Yoshi's / *.mp3 (in "Kodzo").
SRC="$D/Pat Martino/Live at Yoshi's"
cp -a "$SRC" /tmp/qa-noalbum-bk               # backup for restore
# Move its files up to <artist>/<title> (drop the album folder):
mv "$SRC"/*.mp3 "$D/Pat Martino"/ && rmdir "$SRC"
find "$D/Pat Martino" -maxdepth 1 -type f     # confirm files now sit directly under the artist
```

**Assert** (Kodzo has 9 tracks; before this fix the relocated Pat Martino track(s)
would be skipped → counted missing; after, they're found again). Baseline for
Kodzo with a complete library is `present 8, missing 1` (the genuinely-absent
Sammy Virji track — see §6). The relocated track must **not** add to missing:
```bash
cd ../feishin-qa
QA_APP_ENTRY=../feishin/out/main/index.js QA_PLAYLIST=Kodzo \
  QA_EXPECT_MISSING=1 node scripts/qa/sync-plan-classification.mjs
```
**PASS:** `MISSING: 1` (still just Sammy Virji), relocated track under
`--- existing ---` if you add `QA_LIST_EXISTING=1`. `OVERALL: PASS`.
**Pre-fix signature (FAIL):** `MISSING: 2+` — the relocated track(s) appear in the
missing list despite being present and tagged.

> Cross-check the scan actually reached the file: the driver prints
> `localTracks: real scan ... (N tracks); M carry a subboxId`. N should not drop
> after the move (recursive walk still finds it at the shallower depth).

**Teardown (always restore the library layout):**
```bash
D="$HOME/Library/Application Support/subbox-dev/music"
rm -f "$D/Pat Martino"/*.mp3
mkdir -p "$D/Pat Martino/Live at Yoshi's"
cp -a /tmp/qa-noalbum-bk/. "$D/Pat Martino/Live at Yoshi's/"
rm -rf /tmp/qa-noalbum-bk
```

---

### Test B/2b — recursive-walk regression sweep (change B, no fixture)

**Purpose:** the recursive rewrite must not lose tracks it used to find, and must
not crash on odd layouts (`_unknown` album folders, deep nesting, loose files).

```bash
cd ../feishin-qa
QA_APP_ENTRY=../feishin/out/main/index.js QA_PLAYLIST=Kodzo \
  node scripts/qa/sync-plan-classification.mjs
```
**PASS:** the `localTracks: real scan ... (N tracks)` line reports the full library
count with no error/exception, and Kodzo classifies `present 8 / missing 1`
(baseline). **Verified live:** N = 873 tracks, 858 with a subboxId, across mixed
depths including `<artist>/_unknown/` and `<artist>/<album>/` — clean.

---

### Test C — watch-upload vs. in-progress download (change C)

**Purpose:** the download stays clean (resolves; no hang) while the watch-dir
uploader is active, and the watcher resumes after.

**Reuse the existing skill/driver unchanged** — invoke `test-watch-download-concurrency`
(or run `scripts/qa/watch-download-concurrency.mjs`). Point it at the same build:
```bash
cd ../feishin-qa
QA_APP_ENTRY=../feishin/out/main/index.js QA_PLAYLIST=Kodzo \
  node scripts/qa/watch-download-concurrency.mjs
```
**PASS:** `OVERALL: PASS` — download resolved cleanly (`tracksExported` set), **0**
watch scan/upload ticks during the download window, watcher resumed after.
Run the "empty library / large download" variant from that skill for the real
multi-poll window (back up + restore the library as the skill instructs).
**Pre-fix signature:** download window ≈ 180s with `ok=false` (the hang), or >0
active ticks during the window.

---

### Test D — dev/prod library isolation smoke (change D)

**Purpose:** the `VITE_SUBBOX_APP_DIR` refactor still isolates the dev build to
`subbox-dev/`, and did not repoint dev at the shared `subbox/` library.

```bash
# Any dev-build run logs / uses subbox-dev. Quick check: the scan count matches
# subbox-dev, not the (larger) shared subbox library.
find "$HOME/Library/Application Support/subbox-dev/music" -type f \
  \( -name '*.mp3' -o -name '*.flac' -o -name '*.m4a' \) | wc -l
# Compare to the driver's "real scan (N tracks)" line — they must agree, and must
# NOT match a staging/prod subbox/music count on the same machine.
```
**PASS:** driver's scanned track count == `subbox-dev/music` file count. If a
`subbox/music` (no `-dev`) exists on the machine, confirm the numbers differ, i.e.
dev is not reading it. (`check-userdata.mjs` also reports the resolved path.)

---

### Test E — unreadable-tag logging (change E, observational)

While Tests A/B run, watch the main-process logs the driver captures on FAIL
(printed as `--- main logs (tail) ---`), or run the app and
`grep '\[subbox-id\] Failed to read SUBBOX_ID'`. **PASS:** no such lines for a
healthy library (all tags read cleanly); if one appears it names the exact file —
that file was previously being silently treated as untagged (the bug E fixes). Not
a gating test; it turns a silent failure into a diagnosable one.

---

## 5. Suggested order & pass gate

1. Preconditions §3 (build client; verify/rebuild pymix).
2. Test B/2b (report-only sweep — fastest, confirms the build + scan are healthy).
3. Test A/1 (duplicate) — the headline pymix fix.
4. Test B/2 (no-album folder) — the headline client fix. **Restore the library after.**
5. Test C (concurrency) via the existing skill.
6. Test D (isolation smoke), Test E (log scan) — cheap guardrails.

**Overall PASS** = A/1, B/2, B/2b, C all green, D confirms isolation, no unexpected
E log lines. Record the run in `../feishin-qa/docs/qa/log.md` and, if this is the
first green run, capture the numbers in
`../feishin-qa/docs/qa/features/sync-plan-classification.md`.

---

## 6. Verified reference numbers (captured while authoring this plan)

Against the **client fix build** + the **then-current unfixed pymix**
(`qa-local`, `matched_subbox_ids` count = 0), test account `test260526`:

- **Real scan (change B path):** 873 local tracks found across mixed depths, 858
  carrying a subboxId — no crash. Confirms the recursive walk works.
- **Kodzo baseline:** 9 requested → **8 present, 1 missing** (Sammy Virji &
  Interplanetary Criminal — "Damager (Hamdi Edit)", genuinely absent locally), 1
  metadata update. This 1-missing is correct, not a regression.
- **Test A/1 on unfixed pymix (bug reproduced):** "QA Dup Test" = Pat Martino —
  "Welcome to a Prayer" ×3 → **present 1, MISSING 2** (both extra occurrences in
  the missing list). After the pymix rebuild this must become **present 3,
  MISSING 0** — that flip is the change-A pass criterion.

These numbers are library-state-dependent; re-derive per environment, but the
**shape** (dup: 1-present/N-1-missing pre-fix → N-present/0-missing post-fix) is
the invariant to assert on.
