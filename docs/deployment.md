# Deployment

Three environments, all Docker-based:

| Env | Host | Compose source | Fronted by |
|---|---|---|---|
| **dev** | local machine | `../traefik/docker-compose.yml` | `*.docker.localhost` (Traefik, local certs) |
| **staging** | Mac mini | that host's own compose file (not in this workspace) | `*.staging.sub-box.net` |
| **prod** | DigitalOcean droplet | that host's own compose file (not in this workspace) | `*.sub-box.net` |

Two images are published to Docker Hub:

| Image | Repo | Dockerfile |
|---|---|---|
| `laker93/pymix` | `../pymix` | `../pymix/Dockerfile` |
| `laker93/player` | `../subbox-app` | `../subbox-app/Dockerfile` |

`../pymix/docker-compose.yml` is a vestigial standalone compose file (references a
`traefik_default` network that doesn't exist locally) — **not** the active dev
stack. The real dev stack is `../traefik` (a third sibling repo,
`git@github.com:laker-93/traefik.git`).

---

## The dev stack (`../traefik`)

`../traefik/docker-compose.yml` brings up the whole local platform on the `proxy`
Docker network:

- `traefik` — reverse proxy, terminates TLS for `*.docker.localhost` using the
  certs in `../traefik/certs/`.
- `player` (`laker93/player:...`) — routed at `https://www.docker.localhost`.
- `pymix` + `pymix-postgres` — routed at `https://pymix.docker.localhost` /
  `/pymix`. `pymix` runs with `APP_ENVIRONMENT=prod` config (see
  `../pymix/pymix/config/config.prod.yaml`) even in dev — "prod" here just means
  "the config that talks to real per-user containers", not the production
  environment.
- `browser` (filebrowser) — routed at `https://browser.docker.localhost` / `/browser`.
- Per-user containers (e.g. `navidrome<user>`, `beets<user>`) run alongside these,
  created by `pymix` via the mounted Docker socket.

Credentials (`POSTGRES_USER`/`POSTGRES_PASSWORD`) come from `../traefik/.env`
(gitignored, not in the repo).

Prereqs (one-time): `docker network create proxy`.

---

## Versioning

The two images use **different release flows**:

- **Client** (`../subbox-app` → `laker93/player`) ships through its **GitHub Actions
  CI**: bump `package.json`, merge to `development`, push a `v*` tag (builds the
  Docker image) and dispatch `publish.yml` (cuts the GitHub Release). This is the
  flow actually used for client releases — see
  **[Releasing the client app (CI pipeline)](#releasing-the-client-app-subbox-app-via-ci)**
  below, or the `/release-client-app` skill.
- **Backend** (`../pymix` → `laker93/pymix`) is still built and pushed **manually**
  with `docker buildx` (the `/build-and-push-image` skill), then deployed by SSH.

General rules for the manual pymix flow:

- Pick the **next version manually** (e.g. `v1.1.302` → `v1.1.303`). pymix and the
  client don't have to move in lockstep — bump whichever image changed. (The client
  tracks its own semver in `package.json`, e.g. `1.10.7`.)
- Always build `--platform linux/amd64` (both the staging Mac mini and the prod
  droplet, and the dev `pymix`/`player` images, run/expect amd64 — Apple Silicon
  runs them under emulation).
- Push both a versioned tag and `:latest` if staging/prod compose files track
  `:latest` for that image (check the compose file on the target host first —
  some pin an explicit version).

---

## Building images

### `laker93/pymix`

```bash
cd ../pymix
docker buildx build \
  --platform linux/amd64 \
  -t laker93/pymix:v1.1.303 \
  -f Dockerfile . \
  --push
```

### `laker93/player`

The player image bakes in environment-specific API URLs at **build time** via
`BUILD_MODE`, which selects `.env.<mode>` (`../subbox-app/.env.production`,
`.env.staging`, `.env.development` — see `web.vite.config.ts`). This means a
**separate image per target environment** (the staging build points at
`pymix.staging.sub-box.net`, the prod build at `pymix.sub-box.net`).

```bash
cd ../subbox-app

# prod build (BUILD_MODE=production is the Dockerfile default)
docker buildx build \
  --platform linux/amd64 \
  -t laker93/player:v1.1.303 \
  -f Dockerfile . \
  --push

# staging build
docker buildx build \
  --platform linux/amd64 \
  --build-arg BUILD_MODE=staging \
  -t laker93/player:v1.1.303-staging \
  -f Dockerfile . \
  --push
```

Use the `/build-and-push-image` skill to run either of these interactively.

---

## Releasing the client app (subbox-app) via CI

The client is **not** cut with the manual buildx flow above. It releases through
`../subbox-app`'s GitHub Actions workflows. Two artifacts come out of one release:
the **prod Docker image** (`laker93/player`) and the **GitHub Release** (desktop
binaries at <https://github.com/laker-93/subbox-app/releases>). Use the
`/release-client-app` skill to drive this; the manual steps are:

1. **Get the PR green, on `development`.** Client PRs target the `development`
   default branch. CI lint runs `eslint --max-warnings=0` — even a single
   `prettier/prettier` *warning* fails lint and **skips** the release `publish`
   job. If lint is red, fix it (`eslint --fix <file>`), commit, push, re-check
   (`gh pr checks <N> --repo laker-93/subbox-app`).
2. **Bump the version.** Edit `package.json` `"version"` (semver patch, e.g.
   `1.10.6` → `1.10.7`) in a `chore(release): bump version to X.Y.Z` commit on the
   PR branch. The Release name comes from this field.
3. **Squash-merge into `development`.**
   ```bash
   gh pr merge <N> --repo laker-93/subbox-app --squash \
     --subject "<summary> + release X.Y.Z (#<N>)"
   ```
4. **Tag the merge commit → builds the Docker image.**
   ```bash
   git fetch origin development --tags
   git tag -a vX.Y.Z <merge-sha> -m "Release X.Y.Z: <summary>"
   git push origin vX.Y.Z
   ```
   The `v*` tag push triggers `publish-docker-hub.yml` → builds and pushes
   `laker93/player:X.Y.Z` **and `:latest`** (multi-arch amd64/arm64/arm-v7, prod
   API URLs baked in via the default `BUILD_MODE=production`) to Docker Hub. This
   is the image the prod host pulls. (The same tag also triggers
   `publish-docker-auto.yml`, a GHCR mirror.)
5. **Publish the GitHub Release + desktop binaries.** This is a *separate, manual*
   dispatch of `publish.yml` on `development` (how `1.10.6` was cut):
   ```bash
   gh workflow run publish.yml --repo laker-93/subbox-app --ref development
   ```
   electron-builder builds Windows/macOS/Linux artifacts and publishes the Release
   `vX.Y.Z` (version read from `package.json`).

**Verify:**
- Docker image: `gh run list --repo laker-93/subbox-app --workflow publish-docker-hub.yml` (~9–10 min).
- Release: `gh run list --repo laker-93/subbox-app --workflow publish.yml` (~20–30 min; then the entry appears on the releases page).

**Deploy** the new image to prod is still the manual SSH step below.

**Cross-repo coupling:** if the client release depends on new backend behaviour
(a new pymix endpoint or field — e.g. SoundCloud wishlist links, which need
`link_parse_service` + a `soundcloud_url` column), **release and deploy
`laker93/pymix` and run its Alembic migration on the target DB first**, so the
freshly-released client never calls an endpoint prod can't serve yet. See
`docs/integration.md`.

---

## Local builds for dev testing

To test a code change locally before cutting a real release, build with `--load`
(no `--push`) so the image lands directly in the local Docker daemon:

```bash
cd ../pymix    # or ../subbox-app
docker buildx build \
  --platform linux/amd64 \
  -t laker93/pymix:vX.Y.Z \
  -f Dockerfile . \
  --load
```

Then point `../traefik/docker-compose.yml`'s `pymix` (or `player`) service at that
tag and `docker compose up -d <service>` from `../traefik`. The
`/run-local-stack` skill does the tag-bump + `docker compose up -d` step.

For `pymix`, Alembic migrations run automatically on container startup (see
`../pymix/docs/dev.md`) — check `docker logs pymix` to confirm the migration ran.

---

## Deploying

Deploys are **manual** — SSH into the target host, then:

```bash
# on the mac mini (staging) or droplet (prod)
cd <path-to-compose-dir>          # wherever that host's docker-compose.yml lives
# update the image tag in docker-compose.yml if it's pinned to a version
docker compose pull
docker compose up -d
```

Notes:
- Staging and prod each have their own `docker-compose.yml` on that host; this
  workspace doesn't track them.
- `APP_ENVIRONMENT` for pymix is `dev` | `prod` (see `../pymix/pymix/config/`) —
  staging runs pymix with `APP_ENVIRONMENT=prod` config, pointed at staging infra
  via that host's compose file and env vars.
- Treat staging and prod as live instances — confirm before pulling/restarting if
  anyone else might be using them (per this workspace's working principles).
