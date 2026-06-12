# Repositories

The subbox platform spans two repos, both siblings of this workspace. Resolve them
with relative paths; do not hardcode an absolute root (clones differ per machine).

```
../subbox-app    git@github.com:laker-93/subbox-app.git
../pymix         git@github.com:laker-93/pymix.git
```

For anything repo-specific, **read that repo's own docs** — this workspace only holds
cross-cutting context.

---

## `../subbox-app` — the client

Electron + React 19 desktop music player (also builds to web and a remote-control
app). Fork of [Feishin](https://github.com/jeffvli/feishin). Plays from Jellyfin,
Navidrome, and Subsonic/OpenSubsonic, and adds the DJ-workflow UI (pymix import,
sync, sharing, filebrowser).

- **Stack:** React 19 + TypeScript, `electron-vite`/`vite`, Mantine v8, TanStack
  React Query + Zustand. Package manager is **pnpm** (never npm/yarn).
- **Three runtime contexts:** `src/main/` (Electron Node process), `src/preload/`
  (typed `window.api` bridge), `src/renderer/` (React app), plus `src/shared/` and
  `src/remote/`. The renderer never imports `electron` directly.
- **Build before done:** `pnpm lint` (typecheck + eslint `--max-warnings=0` +
  stylelint).

**Its docs (read these for client work):**
| File | Covers |
|---|---|
| `../subbox-app/CLAUDE.md` | Orientation, runtime contexts, where things live, add-a-feature cheat sheet, conventions, gotchas. |
| `../subbox-app/docs/ARCHITECTURE.md` | Process model, the music-server `ControllerEndpoint` abstraction, subbox-specific services (pymix/filebrowser), state, routing, build targets. |
| `../subbox-app/docs/ENV_SETTINGS.md` | Env-driven settings for web/Docker first-run. |

---

## `../pymix` — the backend

FastAPI ETL service that transforms between Rekordbox/Serato and Subsonic, and
orchestrates a per-user stack of Docker containers (Navidrome, beets, filebrowser).
The package name `pymix` is legacy; the product is "subbox" (`sub-box.net`).

- **Stack:** Python 3.11, FastAPI + uvicorn, `dependency-injector`, SQLAlchemy 2.0
  (sync) + Alembic, Postgres. `python-on-whales` to drive Docker; `pyrekordbox`,
  `pyserato`, `pytaglib` for formats/tags.
- **Layered + DI:** routers → controllers → orchestrators → clients/handlers, wired
  in `containers.py`, built in `registration.py`, entry `runner.py`.
- **Runs inside Docker** with the Docker socket and `/subbox` host volume mounted —
  it shells out to each user's containers, so it can't fully run standalone.

**Its docs (read these for backend work):**
| File | Covers |
|---|---|
| `../pymix/CLAUDE.md` | Orientation, the `subbox_id` concept, architecture paragraph, load-bearing conventions, rough edges, do-nots. |
| `../pymix/docs/architecture.md` | Layers, DI wiring, lifespan/watcher, per-user container topology, external services, a request-flow example. |
| `../pymix/docs/api.md` | Every HTTP endpoint by router. |
| `../pymix/docs/data-model.md` | DB tables, domain models, the `subbox_id` mapping. |
| `../pymix/docs/workflows.md` | Import/export/sync/watch flows end to end; storage/staging paths. |
| `../pymix/docs/dev.md` | How to run, test, migrate; the dev_sandbox scripts. |

---

## Quick "where do I look?" index

| I need to understand… | Go to |
|---|---|
| What the platform is, how repos relate | this workspace: `CLAUDE.md` |
| The HTTP contract between client and backend | this workspace: `docs/integration.md` |
| How a renderer feature is structured | `../subbox-app/docs/ARCHITECTURE.md` §2–§6 |
| The pymix client inside the app | `../subbox-app/src/renderer/api/pymix/` + `../subbox-app/src/shared/api/pymix/pymix-types.ts` |
| What a pymix endpoint does | `../pymix/docs/api.md` |
| How a library transform actually runs | `../pymix/docs/workflows.md` |
| DB schema / migrations | `../pymix/docs/data-model.md` + `../pymix/docs/dev.md` |
