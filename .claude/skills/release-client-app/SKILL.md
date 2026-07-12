---
name: release-client-app
description: Cut a new release of the subbox-app client (Feishin fork) through its GitHub Actions CI — bump the version, squash-merge the PR into development, push a v* tag to build the laker93/player Docker image on Docker Hub, and dispatch publish.yml to publish the GitHub Release (desktop binaries). Use when the user wants to "release the client app", "cut a client release", "publish a new subbox-app / player version", "do the app release", "trigger the release build", or similar. This is the CI flow in docs/deployment.md — NOT the manual pymix buildx flow (that's /build-and-push-image). Does not deploy to prod (manual SSH) and does not touch pymix.
---

# Release the client app (subbox-app)

Drives a client release through `../subbox-app`'s GitHub Actions CI, as documented
in `docs/deployment.md` → "Releasing the client app (subbox-app) via CI". Produces
two artifacts: the prod Docker image `laker93/player:<version>` (+ `:latest`) and
the GitHub Release with desktop binaries.

The client repo is `laker-93/subbox-app` on GitHub; on this machine it may be cloned
as `../subbox-app` **or** `../feishin`. All `gh` commands below take
`--repo laker-93/subbox-app`. The default/base branch is **`development`**.

## 0. Confirm scope and check for cross-repo coupling

- Confirm which PR (number) is being released, or that the change is already on
  `development`.
- **Does this release need backend changes?** If the feature relies on a new pymix
  endpoint/field (e.g. SoundCloud wishlist links → `soundcloud_url` column + parse
  logic), the pymix image must be **built, deployed, and migrated first**, or the
  released client will call an endpoint prod can't serve. Flag this to the user;
  pymix release/deploy is out of scope for this skill (see `/build-and-push-image`
  and `docs/deployment.md`). Only proceed with the client release once the user
  confirms the backend side is handled.

## 1. Get the PR green

Client CI lint runs `eslint --max-warnings=0`, so **a single `prettier/prettier`
warning fails lint and skips the release `publish` job.**

```bash
gh pr checks <N> --repo laker-93/subbox-app
```

If lint is red, fix it locally (`node_modules/.bin/eslint --fix <file>` — note the
bin has a `node` shebang; if `node` isn't on PATH, run
`<node> node_modules/eslint/bin/eslint.js --fix <file>`), commit, push, and re-check
until `lint` / `wait-for-lint` pass. `UNSTABLE` with only the macOS/Windows
`publish (…)` PR-preview builds still running is fine — those aren't required and
aren't the prod artifact.

## 2. Bump the version

Pick the next semver (patch unless the user says otherwise), e.g. `1.10.6` →
`1.10.7`. Edit `package.json` `"version"` and commit on the PR branch:

```
chore(release): bump version to X.Y.Z
```

The GitHub Release name is read from this field. Push it with the lint fix.

## 3. Confirm before the irreversible steps

Steps 4–6 are outward-facing and hard to reverse (they merge to the default branch
and publish to Docker Hub + the public releases page). Show the user the exact
version/tag and get explicit confirmation before running them, unless already
clearly authorized in this session.

## 4. Squash-merge the PR into `development`

```bash
gh pr merge <N> --repo laker-93/subbox-app --squash \
  --subject "<summary> + release X.Y.Z (#<N>)" \
  --body "<what changed>"
```

Confirm it merged and note the merge commit SHA:

```bash
gh pr view <N> --repo laker-93/subbox-app --json state,mergeCommit \
  -q '.state + " " + .mergeCommit.oid'
```

## 5. Tag the merge commit → builds the Docker image

```bash
git fetch origin development --tags
git tag -a vX.Y.Z <merge-sha> -m "Release X.Y.Z: <summary>"
git push origin vX.Y.Z
```

The `v*` tag push triggers `publish-docker-hub.yml` → builds & pushes
`laker93/player:X.Y.Z` **and `:latest`** (multi-arch, prod API URLs) to Docker Hub.
This is the image the prod host pulls. (It also triggers `publish-docker-auto.yml`,
a GHCR mirror.) Confirm the run started:

```bash
gh run list --repo laker-93/subbox-app --workflow publish-docker-hub.yml --limit 3
```

## 6. Publish the GitHub Release (desktop binaries)

This is a **separate manual dispatch** of `publish.yml` on `development` (the version
is read from `package.json`):

```bash
gh workflow run publish.yml --repo laker-93/subbox-app --ref development
gh run list --repo laker-93/subbox-app --workflow publish.yml --limit 2
```

electron-builder builds Windows/macOS/Linux artifacts and publishes the Release
`vX.Y.Z` at <https://github.com/laker-93/subbox-app/releases>.

## 7. Report

Both builds run long (Docker image ~9–10 min; the release build across three OSes
~20–30 min). Tell the user the version, the two run URLs, and that they can be left
unattended. Remind them:

- **Prod deploy is a separate manual step** (SSH + `docker compose pull && up -d`
  on the droplet — see `docs/deployment.md`). This skill does not deploy.
- If there was backend coupling (step 0), the matching `laker93/pymix` image +
  migration must be deployed for the feature to work end to end.
