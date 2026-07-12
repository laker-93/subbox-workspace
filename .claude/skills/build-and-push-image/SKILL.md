---
name: build-and-push-image
description: Build and push a versioned Docker image for pymix (laker93/pymix) or the subbox-app player (laker93/player) for a given environment. Use when the user wants to "build pymix", "build the player image", "cut a release image", "push a new version", or similar — for the manual docker buildx release flow described in docs/deployment.md. Does not deploy — staging/prod deploy (SSH + docker compose pull/up) stays manual.
---

# Build and push image

Build and push a versioned Docker image for one of the two subbox images, following
`docs/deployment.md`. This skill only builds and pushes — it never SSHes into
staging or prod.

## 1. Gather inputs

Ask (or infer from the user's request) for:

- **Which image**: `pymix` (`../pymix`, image `laker93/pymix`) or `player`
  (`../subbox-app`, image `laker93/player`).
- **Version tag**: e.g. `v1.1.303`. If the user doesn't give one, ask — don't guess
  a version bump.
- **For `player` only — environment**: `production` or `staging`. This selects
  `BUILD_MODE`, which bakes in the `.env.production` / `.env.staging` API URLs
  (`../subbox-app/.env.<mode>`). Default `production` if the user says "prod".

## 2. Confirm before pushing

`--push` publishes to a shared Docker Hub registry — this is visible to others and
not easily reversible. Show the exact command you're about to run and get explicit
confirmation before executing it.

## 3. Run the build

All builds use `--platform linux/amd64` (both staging Mac mini and prod droplet are
amd64 hosts).

### pymix

```bash
cd ../pymix
docker buildx build \
  --platform linux/amd64 \
  -t laker93/pymix:<VERSION> \
  -f Dockerfile . \
  --push
```

### player — production

```bash
cd ../subbox-app
docker buildx build \
  --platform linux/amd64 \
  -t laker93/player:<VERSION> \
  -f Dockerfile . \
  --push
```

### player — staging

```bash
cd ../subbox-app
docker buildx build \
  --platform linux/amd64 \
  --build-arg BUILD_MODE=staging \
  -t laker93/player:<VERSION>-staging \
  -f Dockerfile . \
  --push
```

## 4. After pushing

Tell the user the pushed tag(s) and remind them that deploying to staging/prod is a
separate, manual step (SSH + `docker compose pull && docker compose up -d` on the
target host — see `docs/deployment.md`). Don't attempt that step yourself unless
explicitly asked, and even then treat it as a risky action requiring confirmation.
