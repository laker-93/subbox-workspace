# System architecture (end to end)

This is the **whole-platform** view. For the internals of either half, follow the
links into that repo's own docs — they are authoritative and kept current there.

## The big picture

```
┌─────────────────────────────────────────────────────────────┐
│  subbox-app  (../subbox-app)                                  │
│  Electron / web client                                       │
│                                                              │
│   renderer (React)                                           │
│     ├─ music-server controllers ──HTTP──► Navidrome/Subsonic │ playback, browse
│     │   (Jellyfin/Navidrome/Subsonic, one ControllerEndpoint)│
│     └─ pymix + filebrowser API clients ──HTTP──┐             │ DJ workflows
└────────────────────────────────────────────────┼────────────┘
                                                  │ the pymix API seam
                                                  ▼  (docs/integration.md)
┌─────────────────────────────────────────────────────────────┐
│  pymix  (../pymix)   FastAPI backend, root_path="/pymix"      │
│   routers → controllers → orchestrators → clients/handlers   │
│                         │                                     │
│   drives, per user:     ▼                                     │
│   ┌──────────────┬──────────────┬──────────────┐            │
│   │ navidrome{u} │  beets{u}    │ filebrowser  │  + postgres │
│   │ Subsonic srv │ tag/import   │ up/downloads │  (pymix DB) │
│   └──────────────┴──────────────┴──────────────┘            │
└─────────────────────────────────────────────────────────────┘
```

Two distinct HTTP paths leave the client:

1. **Music-server traffic** (browse, playback, playlists, scrobble) goes from the
   renderer's `ControllerEndpoint` adapter **straight to Navidrome/Subsonic** — it
   does not go through pymix. Detail: `../subbox-app/docs/ARCHITECTURE.md` §2.
2. **DJ-workflow traffic** (login, import RB/Serato, export, sync plans, storage
   checks) goes from the renderer's **pymix API client to the pymix backend**.
   Detail: `docs/integration.md`.

The same Navidrome instance is both the music server the client plays from *and* the
target pymix writes playlists into. That is why a pymix import shows up in the client
without any client-side push: pymix mutates Navidrome, the client reads Navidrome.

## Client side (subbox-app)

Three Electron contexts — main (Node), preload (`window.api` bridge), renderer
(React) — plus shared and remote builds. The renderer reaches native capabilities
only through `window.api`, and reaches servers through two families of HTTP clients
(music-server controllers vs. subbox services). Full treatment:
`../subbox-app/docs/ARCHITECTURE.md`.

## Backend side (pymix)

Layered and dependency-injected: thin routers resolve the user and delegate to
controllers, which orchestrate domain logic over clients (HTTP to Navidrome/beets)
and handlers (filesystem + Docker side effects). A lifespan watcher provides the
"drop a file in a watch dir and it auto-imports" path. Full treatment:
`../pymix/.claude/docs/architecture.md`.

## Per-user container topology

pymix spins up **one stack per user** (created on `POST /user/create`). Names follow
`navidrome{user}` / `beets{user}`; filebrowser and the pymix app/postgres are shared.
pymix talks to them over the Docker network and runs `beet` commands via
`docker.execute(...)`. The compose/env files for these live outside the repos, under
the mounted `/subbox` volume. Authoritative table:
`../pymix/.claude/docs/architecture.md` §"Container topology".

## The unit of identity: `subbox_id`

Every audio file carries a `SUBBOX_ID` UUID in its tags. It is the stable identity of
a track across Rekordbox, Serato, Navidrome, transcoding, and beets re-imports —
nearly all track-level backend logic keys off it. Any new ingest path must tag files.
Authoritative detail: `../pymix/CLAUDE.md` ("The one concept you must understand").

## Data flow of a track (import)

```
client uploads files (filebrowser)  ──►  pymix stages to beets data dir
   ──►  beet import (tags SUBBOX_ID, moves into /private-music/{user})
   ──►  Navidrome scans  ──►  pymix creates playlists from the RB/Serato structure
   ──►  client browses Navidrome and sees the new library + playlists
```

Step-by-step with exact paths and endpoints: `../pymix/.claude/docs/workflows.md`.

## Where to go next

- Crossing the client/backend boundary in a change → `docs/integration.md`
- Actually shipping a feature across both repos → `docs/adding-a-feature.md`
