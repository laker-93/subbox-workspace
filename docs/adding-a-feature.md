# Adding a feature to the platform

A practical, repo-spanning workflow. Start here, then drop into the repo-specific
docs for the mechanics. The first job is always to decide **which half(s)** the
feature lives in.

## Step 0 — classify the feature

| If the feature is… | It touches… | Primary docs |
|---|---|---|
| Pure UI / playback / routing / theming | `subbox-app` only | `../subbox-app/CLAUDE.md`, `../subbox-app/docs/ARCHITECTURE.md` |
| A music-server capability for Navidrome/Subsonic | `subbox-app` only (`ControllerEndpoint`) | `../subbox-app/docs/ARCHITECTURE.md` §2 |
| A native/OS behaviour (MPV, media keys, file open) | `subbox-app` only (main+preload+renderer) | `../subbox-app/docs/ARCHITECTURE.md` §1 |
| A library transform / import / export / orchestration / schema change | `pymix` only | `../pymix/CLAUDE.md`, `../pymix/docs/{workflows,data-model,api}.md` |
| A DJ-workflow feature with new backend behaviour surfaced in the UI | **both** | `docs/integration.md` + both repos |

If unsure, sketch the data flow against `docs/architecture.md` and find which arrows
the feature adds or changes.

## Step 1 — plan against existing patterns

Read the relevant repo docs **before** reading source, then find the closest existing
feature and mirror it:

- subbox-app: pick a sibling under `src/renderer/features/<x>/` and copy its
  `routes/queries/mutations/components` shape. The add-a-feature cheat sheet in
  `../subbox-app/CLAUDE.md` lists the four common shapes.
- pymix: trace one existing request flow end to end
  (`../pymix/docs/architecture.md` has a worked example) before adding a
  parallel one.

## Step 2 — implement

### subbox-app-only feature
1. Music-server capability → add method to `ControllerEndpoint`
   (`src/shared/types/domain-types.ts`), implement in each
   `src/renderer/api/{navidrome,subsonic}/*-controller.ts` (the Jellyfin controller
   is upstream leftover — never a requirement; make the method optional if
   not all servers support it), add a React Query hook + query keys.
2. New page → `AppRoute` enum (`src/renderer/router/routes.ts`) +
   `app-router.tsx` + `features/<x>/routes/<x>-route.tsx`.
3. Native behaviour → `ipcMain.handle` in `src/main/`, expose in `src/preload/`, type
   in `src/preload/index.d.ts`, call via `window.api.*`.
4. `pnpm lint` (typecheck + eslint `--max-warnings=0` + stylelint). Run `pnpm i18next`
   if you added strings.

Full detail: `../subbox-app/CLAUDE.md` + `../subbox-app/docs/ARCHITECTURE.md`.

### pymix-only feature
1. Add/extend the router, resolving the user; delegate down through
   controller → orchestrator → client/handler. Keep dependencies pointing inward.
2. Register new collaborators as providers in `containers.py`; if you added a router,
   include it in `create_app` and add its module to `wire(...)` in `registration.py`.
3. Persisting data → new Alembic revision in `pymix/migrations/versions/` **and** the
   ORM model in `model/db_tables.py` (migrations auto-run on startup).
4. Never bypass `subbox_id` tagging on a new ingest path.
5. Run the tests (`pymix/pytest.ini`).

Full detail: `../pymix/CLAUDE.md` + `../pymix/docs/{architecture,workflows,data-model,dev}.md`.

### Cross-repo feature
Follow the **lockstep checklist** in `docs/integration.md` — backend route + logic
(+ migration + api.md) first, then client Zod types + api/controller + query hook +
UI. Ship them as a paired feature branch in each repo.

## Step 3 — verify

- subbox-app: `pnpm lint` proves types/style only. For player/native/IPC or any new
  UI path, run `pnpm dev` and exercise it — web/remote builds have no main process,
  so check those if your code branches on `is-electron`.
- pymix: it runs inside Docker with the socket and `/subbox` volume mounted (it can't
  fully run standalone). Use the dev_sandbox scripts and tests
  (`../pymix/docs/dev.md`).
- Cross-repo: point the running client at the running backend and exercise the full
  round trip. A passing typecheck does not prove the HTTP contract matches — the Zod
  parse can still fail at runtime.

## Step 4 — branches, commits, MRs

- Branch per repo; keep the two branches of a cross-repo feature named consistently
  so they're obviously a pair.
- Update the repo's own docs in the same change (api.md for new pymix endpoints; the
  relevant feature notes for subbox-app). Update files in **this** workspace only if
  the cross-repo relationship itself changed (a new integration path, a new repo).
- These generated docs are produced by `doc_gen.py`; if you change a doc's content,
  update the corresponding constant in `doc_gen.py` so a regen doesn't revert it.

## Anti-patterns

- Copying repo-specific detail into this workspace. Link instead.
- Changing a pymix response without updating the client Zod schema (runtime break).
- Adding an ingest path that doesn't tag `subbox_id`.
- Editing virtualized lists without checking which `react-window` version the
  component uses (two coexist in subbox-app).
- Importing `electron` in renderer code — route through preload.
