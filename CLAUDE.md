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
relative paths — they may be cloned at a different root on another machine.

```
<workspace-root>/
├── subbox-workspace/   ← you are here (cross-repo docs only)
├── subbox-app/         ← ../subbox-app   (Electron/React client)
└── pymix/              ← ../pymix        (FastAPI backend)
```

From this repo: `../subbox-app` and `../pymix`.

## Read order when starting a task

1. **This file** — what the platform is and how the repos relate.
2. **`docs/repositories.md`** — the two repos, their relative paths, and where each
   repo's own detailed docs live.
3. **`docs/architecture.md`** — the system end to end (client → pymix API → per-user
   containers).
4. **`docs/integration.md`** — the pymix HTTP seam: how a renderer call reaches a
   FastAPI route, and what must change in lockstep on both sides.
5. **`docs/adding-a-feature.md`** — the concrete cross-repo workflow for shipping a
   feature.

Then, for repo-specific detail, **read that repo's own docs** (do not duplicate them
here):

- `subbox-app`: `../subbox-app/CLAUDE.md`, `../subbox-app/docs/ARCHITECTURE.md`,
  `../subbox-app/docs/ENV_SETTINGS.md`.
- `pymix`: `../pymix/CLAUDE.md`, `../pymix/.claude/docs/{architecture,api,data-model,workflows,dev}.md`.

## Division of labour (where does my change go?)

| Change | Repo(s) |
|---|---|
| Playback, UI, routing, theming, stores | `subbox-app` only |
| Library transform (RB/Serato ↔ Subsonic), import/export, container orchestration, DB schema | `pymix` only |
| A user-facing feature backed by new server work (e.g. a new sync option, a new export format) | **both** — pymix endpoint + subbox-app pymix API client/UI. See `docs/integration.md`. |
| Music-server capability that should work across Jellyfin/Navidrome/Subsonic | `subbox-app` only (the `ControllerEndpoint` abstraction) |

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
- **Cross-repo changes ship together.** A pymix endpoint change and its subbox-app
  client change are one logical feature; plan and review them as a pair.
- **Treat any live instance as production.** Neither repo has a separate prod safety
  harness. Don't write to a running DB or user containers without explicit
  confirmation.
