# Subbox Workspace — cross-repo entry point

This repo is **not** an application. It is the orientation layer Claude reads first
when making changes to the **subbox** platform, which is split across two sibling
repositories checked out alongside this one.

## What subbox is

Subbox is a self-hosted music platform with DJ-workflow features. It lets a user
move their library and playlist structure **between DJ software (Rekordbox, Serato)
and Subsonic** (served by Navidrome), and play it back through a desktop/web client.

It has two halves:

| Half | Repo | What it is |
|---|---|---|
| **Client** | `subbox-app` | Electron + React 19 desktop/web music player (fork of Feishin). The UI for browsing, playback, sync, sharing. |
| **Backend** | `pymix` | FastAPI ETL service. Converts libraries between Rekordbox/Serato and Subsonic; orchestrates per-user Docker stacks (Navidrome, beets, filebrowser). |

The client calls the backend over HTTP (the **pymix API**). That HTTP seam is the
single integration point between the two repos — see `docs/integration.md`.

## Where the repos live

Both repos are **siblings of this one**, one level up. Always resolve them with
relative paths — they may be cloned at a different root, and under a different
directory name, on another machine.

```
<workspace-root>/
├── subbox-workspace/   ← you are here (cross-repo docs only)
├── subbox-app/         ← ../subbox-app   (Electron/React client; "subbox-app" on GitHub)
├── pymix/              ← ../pymix        (FastAPI backend)
├── subbox-slskd/       ← ../subbox-slskd (standalone slskd/Soulseek wishlist tooling)
└── traefik/            ← ../traefik      (local dev stack: Traefik + compose)
```

From this repo: `../subbox-app` and `../pymix`. A third sibling, `../traefik`
(`git@github.com:laker-93/traefik.git`), holds the docker-compose stack used to run
the whole platform locally for dev — see `docs/deployment.md`. A fourth,
`../subbox-slskd` (`git@github.com:laker-93/subbox-slskd.git`), holds standalone
Soulseek (slskd) scripts that download the wishlist tracks a user doesn't yet own —
it talks to the pymix wishlist API but ships separately so it can be handed to end
users on its own. See `docs/repositories.md`.

**Naming note:** the client repo is `laker-93/subbox-app` on GitHub (a fork of
`jeffvli/feishin`), but on **this machine** it's cloned as `../feishin`, not
`../subbox-app`. If `../subbox-app` doesn't exist, check `../feishin` — same repo,
just an older directory name carried over from before the fork was renamed.

## Read order when starting a task

1. **This file** — what the platform is and how the repos relate.
2. **`docs/repositories.md`** — the repos (two core + the `subbox-slskd` satellite),
   their relative paths, and where each repo's own detailed docs live.
3. **`docs/architecture.md`** — the system end to end (client → pymix API → per-user
   containers).
4. **`docs/integration.md`** — the pymix HTTP seam: how a renderer call reaches a
   FastAPI route, and what must change in lockstep on both sides.
5. **`docs/adding-a-feature.md`** — the concrete cross-repo workflow for shipping a
   feature.
6. **`docs/deployment.md`** — the dev/staging/prod environments, the
   `laker93/pymix` and `laker93/player` images, and how to build and deploy them.
7. **`docs/qa.md`** — the continuous-UX loop: the `continuous-ux` skill, the
   `../pymix-qa` / `../feishin-qa` QA worktrees, and the on-disk journals that
   carry state between cycles.

Then, for repo-specific detail, **read that repo's own docs** (do not duplicate them
here):

- `subbox-app`: `../subbox-app/CLAUDE.md`, `../subbox-app/docs/ARCHITECTURE.md`,
  `../subbox-app/docs/ENV_SETTINGS.md`.
- `pymix`: `../pymix/CLAUDE.md`, `../pymix/docs/{architecture,api,data-model,workflows,dev}.md`.

## Division of labour (where does my change go?)

| Change | Repo(s) |
|---|---|
| Playback, UI, routing, theming, stores | `subbox-app` only |
| Library transform (RB/Serato ↔ Subsonic), import/export, container orchestration, DB schema | `pymix` only |
| A user-facing feature backed by new server work (e.g. a new sync option, a new export format) | **both** — pymix endpoint + subbox-app pymix API client/UI. See `docs/integration.md`. |
| Music-server capability (Navidrome/Subsonic) | `subbox-app` only (the `ControllerEndpoint` abstraction) |
| slskd/Soulseek run-and-install scripts, or the wishlist downloader that fetches missing tracks | `subbox-slskd` only (standalone; consumes the pymix wishlist API over HTTP) |
| QA / continuous-UX loop work (driving the app, logging & conservatively fixing bugs and UX friction) | the `../pymix-qa` / `../feishin-qa` worktrees on branch `claude/continuous-ux`, via the `continuous-ux` skill. See `docs/qa.md`. |

## Working principles for this platform

- **Don't duplicate repo docs here.** This workspace holds only cross-cutting,
  project-wide context. Anything specific to one repo belongs in that repo's docs;
  link to it instead of copying.
- **`subbox_id` is the cross-system track identity.** A `SUBBOX_ID` UUID is written
  into each file's tags and survives transcoding, re-tagging, and moves between
  systems. Almost all track-level logic in pymix keys off it. Never introduce an
  ingest path that skips tagging. (Detail: `../pymix/CLAUDE.md`.)
- **subbox-app is a fork of Feishin.** When touching shared/feature code, match
  upstream patterns so future merges stay clean. Subbox-only code (pymix, sync,
  sharing, filebrowser integration) has no upstream.
- **The client only ever targets Navidrome/Subsonic.** A Jellyfin controller exists
  (inherited from upstream Feishin) but Subbox will never run against Jellyfin —
  do not let Jellyfin capabilities or limitations influence design decisions. New
  music-server features need only work on Navidrome/Subsonic; implementing the
  Jellyfin side is optional dead code kept only for merge cleanliness.
- **Cross-repo changes ship together.** A pymix endpoint change and its subbox-app
  client change are one logical feature; plan and review them as a pair.
- **Treat any live instance as production.** Neither repo has a separate prod safety
  harness. Don't write to a running DB or user containers without explicit
  confirmation.
