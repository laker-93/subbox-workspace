---
name: build-and-run-player-local
description: Build the subbox-app player image locally with --load (BUILD_MODE=development, pointing at pymix.docker.localhost) and run it in the local dev stack (../traefik/docker-compose.yml). Use when the user wants to "build the client/player for local testing", "rebuild the app and test it locally", "deploy my client changes locally", or similar. Does not push to Docker Hub — for that, use /build-and-push-image instead.
---

# Build and run player locally

Build a local-only `laker93/player` image from the current `../subbox-app`
(`../feishin`) working tree and bring it up in the local dev stack, mirroring the
"Local builds for dev testing" flow used for `pymix` (see `docs/deployment.md` and
`/run-local-stack`).

## 1. Locate the client repo

The client repo may be checked out as `../subbox-app` or `../feishin` — use
whichever exists (see root `CLAUDE.md`).

## 2. Build with `--load`

Use `BUILD_MODE=development` so the build picks up `.env.development`
(`VITE_PYMIX_URL=https://pymix.docker.localhost`, etc.) — the URLs the local dev
stack actually serves. This requires the `build:web:development` script in
`package.json` (`vite build --config web.vite.config.ts --mode development`).

Pick a tag that won't collide with real release tags — append `-local`, e.g.
`v1.2.0-local`. If the user gives you a different tag, use that instead.

```bash
cd ../subbox-app   # or ../feishin
docker buildx build \
  --platform linux/amd64 \
  --build-arg BUILD_MODE=development \
  -t laker93/player:<VERSION>-local \
  -f Dockerfile . \
  --load
```

This is a local-only build (`--load`, no `--push`) — no confirmation needed before
running it, unlike the release flow in `/build-and-push-image`.

## 3. Point the local stack at the new image

In `../traefik/docker-compose.yml`, update the `player` service's `image:` line:

```yaml
  player:
    image: laker93/player:<VERSION>-local
```

## 4. Bring up the service

```bash
cd ../traefik
docker compose up -d player
```

## 5. Verify

```bash
docker logs player --tail 40
```

Confirm nginx started cleanly, then check `https://www.docker.localhost` in a
browser for the change. If `settings.js` or chunks 404/504, hard-refresh — Vite's
dep cache can go stale across rebuilds (not a code issue).

This is local-only — never apply these steps to the Mac mini (staging) or droplet
(prod) hosts.
