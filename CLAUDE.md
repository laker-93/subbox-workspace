# Subbox Workspace — cross-repo entry point

This repo is **not** an application. It is the orientation layer to read first when
working on **subbox**, a self-hosted music platform with DJ-workflow features: it moves
a user's library and playlist structure between DJ software (Rekordbox, Serato) and
Subsonic (served by Navidrome), and plays it back through a desktop/web client.

Subbox has two halves that meet at one HTTP seam (the **pymix API**):

| Half | Repo | What it is |
|---|---|---|
| **Client** | `subbox-app` (`../subbox-app`, cloned as `../feishin` on this machine) | Electron + React 19 desktop/web player (fork of Feishin). Browsing, playback, sync, sharing UI. |
| **Backend** | `pymix` (`../pymix`) | FastAPI ETL service. Converts libraries between Rekordbox/Serato and Subsonic; orchestrates per-user Docker stacks. |

Two more siblings support them: `../subbox-slskd` (standalone Soulseek wishlist
downloader, a pymix-API client) and `../traefik` (the docker-compose dev stack). The
repos, their remotes, paths, and per-repo doc indexes are all in `docs/repositories.md`.

## Read order

1. **This file** — what the platform is and how the repos relate.
2. `docs/repositories.md` — the repos and where each one's own docs live.
3. `docs/architecture.md` — the system end to end (client → pymix API → per-user containers).
4. `docs/integration.md` — the pymix HTTP seam, and what must change in lockstep on both sides.
5. `docs/adding-a-feature.md` — the concrete cross-repo workflow for shipping a feature.
6. `docs/deployment.md` — dev/staging/prod, the `laker93/pymix` and `laker93/player` images.
7. `docs/qa.md` — the QA architecture: the `continuous-ux` loop and the reusable `scripts/qa/` substrate.

Then read the target repo's own docs (`../subbox-app/`, `../pymix/`) — don't duplicate them here.

## Where does my change go?

| Change | Repo(s) |
|---|---|
| Playback, UI, routing, theming, stores | `subbox-app` only |
| Library transform (RB/Serato ↔ Subsonic), import/export, orchestration, DB schema | `pymix` only |
| A user-facing feature backed by new server work (new sync option, export format, …) | **both** — pymix endpoint + subbox-app client/UI (`docs/integration.md`) |
| Music-server capability (Navidrome/Subsonic) | `subbox-app` only (the `ControllerEndpoint` abstraction) |
| slskd/Soulseek run + wishlist-download scripts | `subbox-slskd` only (consumes the pymix wishlist API over HTTP) |
| QA / continuous-UX loop work | the `../pymix-qa` / `../feishin-qa` worktrees on `claude/continuous-ux` (`docs/qa.md`) |

## Working principles

- **Don't duplicate repo docs here.** This workspace holds only cross-cutting context;
  anything specific to one repo belongs in that repo's docs — link to it instead of copying.
- **Cross-repo changes ship together.** A pymix endpoint change and its subbox-app client
  change are one logical feature — plan and review them as a pair (`docs/integration.md`).
- **`subbox_id` is the cross-system track identity** — a UUID tagged into every file that
  survives moves between systems; almost all pymix track logic keys off it. Never add an
  ingest path that skips tagging. (Detail: `../pymix/CLAUDE.md`.)
- **The client only ever targets Navidrome/Subsonic.** A Jellyfin controller exists
  (inherited from Feishin) but Subbox will never run against it — don't let it shape design.
- **subbox-app is a fork of Feishin.** Match upstream patterns in shared code so future
  merges stay clean. Subbox-only code (pymix, sync, sharing, filebrowser) has no upstream.
- **Treat any live instance as production.** Neither repo has a separate prod safety
  harness — don't write to a running DB or user containers without explicit confirmation.
