---
name: run-local-stack
description: Bring up a locally-built pymix or player image in the local dev stack (../traefik/docker-compose.yml) for dev testing. Use when the user has just built an image with --load and wants to "run it locally", "test this in dev", "bring up the new image", or similar. Does not build the image and does not touch staging/prod.
---

# Run local stack

Point the local dev stack at a locally-built image and bring up that service.

The dev stack lives in `../traefik/docker-compose.yml` (a sibling repo,
`git@github.com:laker-93/traefik.git`) — **not** `../pymix/docker-compose.yml`,
which is vestigial. See `docs/deployment.md` for the full picture.

## 1. Confirm the image exists locally

```bash
docker images laker93/pymix:<TAG>     # or laker93/player:<TAG>
```

If it's not there, the image needs building first (see `/build-and-push-image` or
the "Local builds for dev testing" section of `docs/deployment.md` for the
`--load` build command) — don't build it as part of this skill unless asked.

## 2. Update the compose file

In `../traefik/docker-compose.yml`, find the `pymix` (or `player`) service's
`image:` line and set it to the new tag, e.g.:

```yaml
  pymix:
    image: laker93/pymix:<TAG>
```

Use Edit for this — it's a one-line tag change.

## 3. Bring up the service

```bash
cd ../traefik
docker compose up -d <service>     # pymix or player
```

`docker compose up -d <service>` only recreates that service (and starts
dependencies like `pymix-postgres` if not already running) — it won't touch the
rest of the stack.

## 4. Verify

```bash
docker logs <service> --tail 40
```

For `pymix`, confirm Alembic migrations ran (look for `Running upgrade ... ->` in
the logs) and that the app started (`Application startup complete.` /
`Uvicorn running on http://0.0.0.0:8002`).

Optionally hit the API through Traefik to confirm routes are registered:

```bash
curl -sk https://pymix.docker.localhost/pymix/openapi.json | python3 -c \
  "import json,sys; print(list(json.load(sys.stdin)['paths']))"
```

This is local-only — never apply these steps to the Mac mini (staging) or droplet
(prod) hosts.
