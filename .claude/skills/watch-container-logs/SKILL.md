---
name: watch-container-logs
description: Fetch or follow the logs of a running container on staging or prod via the Portainer API (not SSH). Use when the user says "watch/check/tail the pymix logs on staging", "get prod logs for navidrome<user>", "what's in the beets logs on staging", or similar. Read-only — never restarts or modifies a container.
---

# Watch container logs (staging / prod)

Pull logs for any container on staging or prod through Portainer's Docker API
proxy, using `scripts/portainer_logs.py` (stdlib-only Python, no pip deps).

## 1. Gather inputs

- **Environment**: `staging` or `prod`. If the user doesn't say, ask — don't
  assume, especially since staging and prod are separate live hosts.
- **Container name**: e.g. `pymix`, `navidrome<user>`, `beets<user>`,
  `pymix-postgres`. Exact name preferred; a unique substring also works (the
  script resolves it against the live container list and errors out if it's
  ambiguous or not found).
- **Tail length**: default 200 lines if the user doesn't specify.
- **Live tail vs snapshot**: "watch" or "follow" implies `--follow`; "check"
  or "show me" implies a one-shot tail. `--follow` is bounded polling, not a
  raw `docker logs -f` stream (see "How it works" — the naive stream just
  hangs through Portainer's proxy). Default window is 60s at 5s intervals;
  pass `--duration`/`--interval` to change that. It always returns on its
  own, so it's safe to run as a normal (non-backgrounded) call.

## 2. Credentials

Reads `PORTAINER_USERNAME` / `PORTAINER_PASSWORD` from
`portainer-credentials.env` at the workspace root (gitignored, sibling to
`discord-credentials.env`). If that file doesn't exist yet, tell the user to
create it from `portainer-credentials.env.example` and stop — don't ask them
to paste credentials into the chat.

## 3. Run it

From this workspace root:

```bash
python3 .claude/skills/watch-container-logs/scripts/portainer_logs.py <env> <container> [--tail N] [--since UNIX_TS]
python3 .claude/skills/watch-container-logs/scripts/portainer_logs.py <env> <container> --follow [--duration S] [--interval S]
```

Examples:

```bash
# one-shot: last 200 lines of pymix on staging
python3 .claude/skills/watch-container-logs/scripts/portainer_logs.py staging pymix

# watch pymix on prod for the next 2 minutes, polling every 5s
python3 .claude/skills/watch-container-logs/scripts/portainer_logs.py prod pymix --follow --duration 120

# a specific user's navidrome container on staging, last 500 lines
python3 .claude/skills/watch-container-logs/scripts/portainer_logs.py staging navidrome<username> --tail 500
```

## How it works

- Both environments are separate Portainer instances, endpoint ID `4` on
  each: `https://portainer.staging.sub-box.net` and
  `https://portainer.sub-box.net` (see `ENV_BASE_URLS` in the script if these
  ever change).
- The script logs in via `POST /api/auth` to get a short-lived JWT, resolves
  the container name to an ID via `GET
  /api/endpoints/4/docker/containers/json`, then fetches
  `GET /api/endpoints/4/docker/containers/{id}/logs?stdout=true&stderr=true&tail=...`.
- Docker's log stream is multiplexed (8-byte-framed stdout/stderr) unless the
  container was started with a TTY; the script inspects the container first
  and demuxes automatically, so what you see is plain text either way.
- `--follow` does **not** open Docker's native `logs -f` stream — through
  Portainer's proxy that request hangs indefinitely (confirmed by testing:
  no bytes, not even the initial tail, arrive until the connection is torn
  down). Instead it prints the initial tail, then polls
  `logs?since=<last-seen-timestamp>` every `--interval` seconds for
  `--duration` seconds total, deduping by timestamp, and always returns.

## Scope

This skill is read-only log retrieval. It never restarts, stops, or execs
into a container — if the user wants to act on something in the logs (e.g.
restart pymix), treat that as a separate, explicit, confirmed action per this
workspace's rule on treating staging/prod as live instances.
