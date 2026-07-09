# The pymix API seam

This is the one place the two repos meet: the renderer's **pymix API client** talks
HTTP to the **pymix FastAPI backend**. Any DJ-workflow feature that needs new server
behaviour changes *both* sides, and they must stay in lockstep. This doc maps the
seam so you know exactly what to touch on each side.

> Music-server features (browse/playback/playlists on Navidrome/Subsonic) do
> **not** cross this seam — they use the in-app `ControllerEndpoint`
> abstraction and go straight to the server. See
> `../subbox-app/docs/ARCHITECTURE.md` §2. This doc is only about the **pymix** path.

## The two sides

### Backend — pymix (`../pymix`)
- App mounts at `root_path="/pymix"`, so every route is prefixed `/pymix` behind the
  proxy.
- Auth: a `session_id` cookie (set on create/login) **or** an explicit `username`
  (query/body); some endpoints also accept a Bearer token.
- CORS allows the subbox web origins with credentials; methods limited to
  GET/POST/DELETE/OPTIONS.
- Endpoints are grouped by router in `pymix/routers/`. The full catalogue is in
  `../pymix/docs/api.md` — treat that as the source of truth for what exists.

### Client — subbox-app (`../subbox-app`)
The pymix client is a subbox-only service, **outside** the music-server controller
abstraction:
- `src/renderer/api/pymix/` — the HTTP client (`*-api.ts`) and typed wrapper
  (`*-controller.ts`).
- `src/shared/api/pymix/pymix-types.ts` — request/response **Zod** schemas
  (`pymixType._parameters.*`).
- `src/renderer/features/{pymix,sync,sharing}/` — the React Query hooks
  (`queries/`, `mutations/`) and UI that call the client.

## Request lifecycle (a DJ-workflow call)

```
React component
  └─ React Query hook (features/<x>/queries|mutations)
       └─ pymix controller (src/renderer/api/pymix/*-controller.ts)   ← typed, Zod-validated
            └─ pymix api client (src/renderer/api/pymix/*-api.ts)     ← builds HTTP request
                 └─ HTTP ──►  /pymix/<route>
                                └─ pymix router (pymix/routers/*.py)   ← resolve user, delegate
                                     └─ controller → orchestrator → clients/handlers
                                          └─ mutates Navidrome / beets / filesystem
```

A long-running operation (import/export) returns a **job id** and is then polled:
the backend exposes progress endpoints (e.g. `/beets/import/progress`,
`/export/progress`) and the client polls them from a query hook. Don't expect a
synchronous result for import/export — model it as job + poll on both sides.

## Contract conventions to respect

- **Path prefix.** Client requests target `/pymix/...`. Don't drop or double the
  prefix.
- **User resolution.** Send the `session_id` cookie (with credentials) or a
  `username`. The backend's routers copy a guard block verbatim to resolve the user —
  match it when you add a route. (`../pymix/docs/api.md`,
  `../pymix/CLAUDE.md` "User resolution pattern".)
- **Response shape is not uniform.** Older pymix endpoints return a plain dict
  `{"success": bool, "reason": str, ...}` and swallow errors into `reason`; newer
  ones (`track.py`, `sync.py`) use Pydantic models and raise `HTTPException`. Mirror
  whichever the endpoint you touch uses, and validate it with the matching Zod schema
  on the client.
- **Types live on both sides.** A field added to a pymix response must be added to
  the Zod schema in `pymix-types.ts`, or the client will reject/ignore it.

## Changing the seam: the lockstep checklist

When a feature needs new backend behaviour:

**In `../pymix`:**
1. Add/extend the route in the right `pymix/routers/*.py` (resolve the user; pick the
   response style of that router).
2. Implement the logic down the layers (controller → orchestrator → client/handler);
   add a new provider in `containers.py` and wire the module in `registration.py` if
   you introduced a router.
3. If it persists data: new Alembic revision **and** matching ORM model
   (`../pymix/docs/data-model.md`, `dev.md`).
4. Update `../pymix/docs/api.md`.

**In `../subbox-app`:**
5. Add request/response **Zod** schemas in `src/shared/api/pymix/pymix-types.ts`.
6. Add the call to `src/renderer/api/pymix/*-api.ts` (HTTP) and `*-controller.ts`
   (typed wrapper).
7. Add a React Query hook under `features/<x>/queries|mutations/`; register cache
   keys in `src/renderer/api/query-keys.ts`.
8. Build/extend the UI under `features/{pymix,sync,sharing}/`.
9. `pnpm lint` must pass.

**Together:** verify against a running backend — a green typecheck does not prove the
contract matches. See `docs/adding-a-feature.md` for the full procedure.

## Gotchas at the boundary

- A backend response-shape change is a breaking change for the client even if the
  client "still compiles" — the Zod parse will fail at runtime. Change both sides in
  one feature branch pair.
- Auth differs per endpoint (cookie vs. Bearer vs. username). Check
  `../pymix/docs/api.md` for the specific endpoint before assuming.
- `subbox_id` is the join key for track-level data. If your feature correlates tracks
  across systems, key off `subbox_id`, not paths or titles.
