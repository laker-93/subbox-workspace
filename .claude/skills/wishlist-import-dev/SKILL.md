---
name: wishlist-import-dev
description: Seed the local-dev Subbox wishlist and run the subbox-slskd download_wishlist script against the dev stack to exercise the Soulseek-download → watch-dir-import path end to end. Use when the user (or the continuous-ux QA loop) wants to "add items to the wishlist in dev", "run download_wishlist against dev", "test importing music in the background", or otherwise drive the wishlist → download → import flow locally. Local dev stack only — never staging/prod.
---

# Wishlist import — dev exercise

Drive the wishlist import journey against the **local dev stack** only: add
one or more items to a test user's wishlist via the pymix API, then run
`../subbox-slskd/scripts/download_wishlist.py` against dev so slskd fetches the
missing tracks and pymix's watch-dir importer ingests them. This is meant to be
run in the background by the `continuous-ux` loop to keep the import path
exercised, so it inherits that loop's conservative rules.

**Hard boundaries (do not relax):**
- **Local dev stack only.** `pymix.docker.localhost` / `navidrome<user>.docker.localhost`.
  Never point any part of this at `sub-box.net` or any live instance.
- **Test user only.** Default `test260526` (below). Never seed or download into
  a real user's wishlist/library.
- **Real downloads over Soulseek are slow and non-deterministic.** Default to a
  small `--max-downloads` and start with `--dry-run` to confirm wiring before
  pulling real files. Don't queue large batches in a background QA cycle.

## The dev environment (verified)

| Thing | Value |
|---|---|
| pymix API base | `https://pymix.docker.localhost/pymix` (self-signed TLS → `curl -k` / `--insecure`; plain `http` 301-redirects) |
| Wishlist auth | `?username=<user>` query param — the wishlist API needs **only the username**, no password |
| Test user | `test260526` / `1234test260526` (from `../feishin-qa/.env.ui-snapshot.local`) — matches the `navidrometest260526` / `beetstest260526` containers |
| Per-user Navidrome | `https://navidrometest260526.docker.localhost` |
| Downloader | `../subbox-slskd/scripts/download_wishlist.py` — stdlib only, run with a bare `python3` (no venv/pip) |
| slskd | Runs on the **host**, not in the compose stack. Default web port `5030`. Started via `../subbox-slskd/scripts/run-slskd-macos.sh`; creds cached in `../subbox-slskd/scripts/slskd-credentials.env` |

Paths are relative to the workspace root (the parent of `subbox-workspace`), per
the sibling-repo convention in the root `CLAUDE.md`.

## Step 0 — preflight

1. Stack up? `docker ps` — expect `pymix`, `pymix-postgres`, `traefik`,
   `filebrowser`, and `navidrometest260526`. If `pymix` is missing/unhealthy,
   the stack isn't up — stop and report; don't try to bring it up as part of a
   background cycle.
2. **Is the `pymix` container busy?** `docker logs pymix --tail 30` — the user
   may be manually testing against the same shared container. If an import /
   job looks in-flight, don't add load this cycle; log and stop.
3. pymix reachable? `curl -sk -o /dev/null -w '%{http_code}\n' \
   "https://pymix.docker.localhost/pymix/wishlist?username=test260526&status=wishlist"`
   → expect `200`.

## Step 1 — add wishlist items (deterministic; always works)

Auth is the `username` query param only. Two endpoints:

**Single item** — `POST /wishlist`. Body needs `artist`+`title`, **or** a
`youtube_url` / `bandcamp_url` / `soundcloud_url`:

```bash
curl -sk -X POST "https://pymix.docker.localhost/pymix/wishlist?username=test260526" \
  -H "Content-Type: application/json" \
  -d '{"artist":"Aphex Twin","title":"Xtal","album":"Selected Ambient Works 85-92"}'
```

**Bulk** — `POST /wishlist/bulk`, body `{"items":[ {…}, {…} ]}` (same per-item
shape). Prefer this when seeding several rows.

Optional item fields: `album`, `youtube_url` / `youtube_video_id`,
`bandcamp_url`, `soundcloud_url`. A row with a URL but no artist/title still
gets created; a row with **neither** a URL nor any artist/title is rejected
(400).

**Naming for QA:** so seeded rows are obviously scratch and easy to clean up,
give them a recognisable marker (e.g. album `"qa-scratch"`), and prefer real,
common tracks that actually exist on Soulseek if you intend to download them —
a made-up title will never match and the download step becomes a no-op.

### The `resolve_state` gate — you usually have to wait

A freshly hand-typed row lands with `resolve_state: "pending"`. pymix's
background resolve loop then corrects it to a canonical MusicBrainz match
(`resolved`, or `nomatch` if it gives up). **`download_wishlist.py` skips any
row still `pending`** (it won't search Soulseek on an unresolved typo). So after
seeding, poll until the rows you added are no longer `pending`:

```bash
curl -sk "https://pymix.docker.localhost/pymix/wishlist?username=test260526&status=wishlist" \
  | python3 -c 'import sys,json; [print(i["resolve_state"],"|",i["artist"],"-",i["title"]) for i in json.load(sys.stdin)["items"]]'
```

Give the resolve loop a bit of time; re-poll rather than busy-looping. Only
proceed to the download step once your rows read `resolved`/`nomatch`.

## Step 2 — run the downloader against dev

**Prereqs:** slskd running on the host, and its **download directory wired to
the test user's watch dir** so pymix auto-imports (Step 3). If slskd isn't up,
start it in a separate terminal — suggest the user run
`! ../subbox-slskd/scripts/run-slskd-macos.sh` (it caches creds and prints a
ready-filled command). Confirm it's listening: `curl -s -o /dev/null -w '%{http_code}\n'
http://127.0.0.1:5030` (a non-connection-refused response means it's up).

slskd web creds are cached in `../subbox-slskd/scripts/slskd-credentials.env`
as `SLSKD_RUN_USERNAME` / `SLSKD_RUN_PASSWORD`. Map them onto the script's
flags. **Start with `--dry-run` and a hard cap:**

```bash
set -a; . ../subbox-slskd/scripts/slskd-credentials.env; set +a
python3 ../subbox-slskd/scripts/download_wishlist.py \
  --pymix-url    https://pymix.docker.localhost/pymix \
  --username     test260526 --password 1234test260526 \
  --navidrome-url https://navidrometest260526.docker.localhost \
  --slskd-url    http://127.0.0.1:5030 \
  --slskd-username "$SLSKD_RUN_USERNAME" --slskd-password "$SLSKD_RUN_PASSWORD" \
  --insecure \
  --max-downloads 1 \
  --dry-run
```

Flag notes:
- `--insecure` is **required** for the local self-signed TLS on both
  `pymix.docker.localhost` and `navidrometest260526.docker.localhost`.
- `--username`/`--password`: pymix identifies the wishlist owner by `username`
  alone; the `--password` is used for the **Navidrome** (Subsonic) "do I already
  own this?" lookup — hence the local `--navidrome-url` override (the script's
  default is the prod `navidrome<user>.sub-box.net`).
- `--max-downloads 1` (or a small N) — cap background load.
- Drop `--dry-run` for a real run once the dry run shows it resolving/searching
  the rows you seeded.
- `--help` lists the full flag set (match thresholds, `--watch`, timeouts, etc.).

The script searches Navidrome per wishlist row, downloads only the missing ones
through slskd into the watch dir, and PATCHes each pulled row to
`status: downloaded`. It never writes `available` itself.

## Step 3 — where downloads must land for import (local-dev caveat)

pymix's watch-dir auto-import (`poll_watchdir`, no endpoint) ingests files from
`/user-updownloads/<user>/watch/` inside the stack. On this machine that's the
Docker **named volume** `user-updownloads` (not a host bind mount), so a
host-run slskd cannot write straight into it. Two ways to bridge for a dev test:

- Point slskd's download dir at a host folder, then move finished files into the
  volume, e.g. `docker cp <file> filebrowser:/data/users/test260526/watch/`
  (filebrowser mounts the volume at `/data/users`), **or**
- Upload the finished file into the test user's `watch/` via filebrowser
  (`https://browser.docker.localhost`).

Either way the file lands in `…/test260526/watch/`, pymix's watcher **moves**
it out, beets-imports it (tagging `SUBBOX_ID`), and Navidrome can then match it.
If you only need to exercise the **import** half (not the Soulseek half), you can
drop a real audio file straight into that watch dir and skip slskd entirely.

## Step 4 — verify the round-trip

1. Downloaded rows flip to `status: downloaded` (the script does this):
   `…/wishlist?username=test260526&status=downloaded`.
2. pymix's reconcile loop promotes `downloaded → available` once the file is
   imported and Navidrome matches it. Re-poll `…&status=available`, or force it:
   `curl -sk -X POST "https://pymix.docker.localhost/pymix/wishlist/reconcile?username=test260526"`.
3. Confirm the track is actually in the library via Navidrome
   (`https://navidrometest260526.docker.localhost`) or in the client.

## Step 5 — clean up

Background QA seeding accumulates. Delete scratch rows you added (identify them
by your `qa-scratch` marker), so the test user's wishlist doesn't drift:

```bash
curl -sk -X DELETE "https://pymix.docker.localhost/pymix/wishlist/<wishlist_id>?username=test260526"
```

Remove any scratch audio you dropped into the watch/library if it was purely a
wiring probe. If you swapped or restarted the shared `pymix` container, note it
in the loop's `log.md` (per the continuous-ux rules) so the user isn't confused
later.

## If blocked

Stack down, slskd not running, pymix container busy with the user's own
testing, or rows stuck `pending` — **log it plainly and stop** (in the QA loop,
one line in `log.md` as `blocked` with why). Don't retry in a hot loop; let the
loop's pacing back off.
