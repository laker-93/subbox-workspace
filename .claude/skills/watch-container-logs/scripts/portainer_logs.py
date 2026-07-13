#!/usr/bin/env python3
"""Fetch or watch a Docker container's logs on staging/prod via Portainer's
Docker API proxy — stdlib only, no pip deps.

Usage:
  portainer_logs.py <env> <container> [--tail N] [--since WHEN]
  portainer_logs.py <env> <container> --follow [--duration S] [--interval S]

  <env>        staging | prod
  <container>  exact or unique-substring container name, e.g. pymix,
               navidrome<user>, beets<user>

Auth: reads PORTAINER_USERNAME / PORTAINER_PASSWORD from the environment, or
falls back to loading them from portainer-credentials.env at the workspace
root (gitignored) if they aren't already set.

Container logs come back from Docker as a multiplexed stdout/stderr stream
when the container has no TTY; this script inspects the container first
(Config.Tty) to decide whether to demux 8-byte-framed chunks or just stream
raw text.

--follow does NOT open Docker's native `logs -f` stream: through Portainer's
proxy that request just hangs (headers/body never flush until the connection
is torn down), which is useless for a tool call that must return. Instead
--follow polls: print the initial tail, then every --interval seconds fetch
only what's new (via `since=<last-seen-timestamp>`) for up to --duration
seconds total, so it always terminates.
"""
import argparse
import calendar
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ENV_BASE_URLS = {
    "staging": "https://portainer.staging.sub-box.net",
    "prod": "https://portainer.sub-box.net",
}
ENDPOINT_ID = 4


def _load_credentials_file():
    if "PORTAINER_USERNAME" in os.environ and "PORTAINER_PASSWORD" in os.environ:
        return
    script_dir = os.path.dirname(os.path.abspath(__file__))
    workspace_root = os.path.abspath(os.path.join(script_dir, "..", "..", "..", ".."))
    env_path = os.path.join(workspace_root, "portainer-credentials.env")
    if not os.path.isfile(env_path):
        return
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            os.environ.setdefault(key.strip(), value.strip())


def _auth(base):
    try:
        username = os.environ["PORTAINER_USERNAME"]
        password = os.environ["PORTAINER_PASSWORD"]
    except KeyError:
        sys.exit(
            "PORTAINER_USERNAME / PORTAINER_PASSWORD not set — put them in "
            "portainer-credentials.env at the workspace root."
        )
    req = urllib.request.Request(
        f"{base}/api/auth",
        data=json.dumps({"username": username, "password": password}).encode(),
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())["jwt"]
    except urllib.error.HTTPError as e:
        sys.exit(f"Portainer auth failed: {e.code} {e.read().decode(errors='replace')}")


def _get(base, jwt, path):
    req = urllib.request.Request(base + path, headers={"Authorization": f"Bearer {jwt}"})
    return urllib.request.urlopen(req)


def _resolve_container_id(base, jwt, name):
    with _get(base, jwt, f"/api/endpoints/{ENDPOINT_ID}/docker/containers/json?all=true") as r:
        containers = json.loads(r.read())
    exact = [c for c in containers if f"/{name}" in c.get("Names", [])]
    if len(exact) == 1:
        return exact[0]["Id"]
    candidates = [c for c in containers if any(name in n for n in c.get("Names", []))]
    if len(candidates) == 1:
        return candidates[0]["Id"]
    if not candidates:
        sys.exit(f"no container matching '{name}' found on this endpoint")
    names = ", ".join(n.lstrip("/") for c in candidates for n in c["Names"])
    sys.exit(f"'{name}' is ambiguous, matches: {names}")


def _is_tty(base, jwt, container_id):
    with _get(base, jwt, f"/api/endpoints/{ENDPOINT_ID}/docker/containers/{container_id}/json") as r:
        info = json.loads(r.read())
    return bool(info.get("Config", {}).get("Tty"))


def _demux_text(raw):
    buf, out = raw, []
    while len(buf) >= 8:
        size = int.from_bytes(buf[4:8], "big")
        if len(buf) < 8 + size:
            break
        out.append(buf[8 : 8 + size])
        buf = buf[8 + size :]
    return b"".join(out).decode(errors="replace")


def _fetch_text(base, jwt, container_id, tty, params):
    path = f"/api/endpoints/{ENDPOINT_ID}/docker/containers/{container_id}/logs?{urllib.parse.urlencode(params)}"
    try:
        with _get(base, jwt, path) as r:
            raw = r.read()
    except urllib.error.HTTPError as e:
        sys.exit(f"Portainer logs request failed: {e.code} {e.read().decode(errors='replace')}")
    return raw.decode(errors="replace") if tty else _demux_text(raw)


def _line_ts(line):
    # timestamps=true prefixes each line with an RFC3339Nano timestamp, e.g.
    # "2026-07-13T07:20:55.730407096Z <content>". Fixed-width/zero-padded, so
    # plain string comparison sorts correctly.
    ts, _, _ = line.partition(" ")
    return ts


def _epoch_seconds(ts):
    return calendar.timegm(time.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S"))


def _poll(base, jwt, container_id, tty, tail, duration, interval):
    text = _fetch_text(
        base, jwt, container_id, tty,
        {"stdout": "true", "stderr": "true", "tail": tail, "timestamps": "true"},
    )
    lines = [l for l in text.splitlines() if l]
    for l in lines:
        print(l)
    last_ts = _line_ts(lines[-1]) if lines else None
    sys.stdout.flush()

    start = time.monotonic()
    try:
        while time.monotonic() - start < duration:
            time.sleep(interval)
            params = {"stdout": "true", "stderr": "true", "tail": "1000", "timestamps": "true"}
            if last_ts:
                params["since"] = str(_epoch_seconds(last_ts))
            text = _fetch_text(base, jwt, container_id, tty, params)
            new_lines = [l for l in text.splitlines() if l and (not last_ts or _line_ts(l) > last_ts)]
            for l in new_lines:
                print(l)
            if new_lines:
                last_ts = _line_ts(new_lines[-1])
                sys.stdout.flush()
    except KeyboardInterrupt:
        pass
    sys.stderr.write(f"-- stopped polling after {duration}s (use --duration to change) --\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("env", choices=sorted(ENV_BASE_URLS))
    ap.add_argument("container")
    ap.add_argument("--tail", default="200", help="number of lines from the end (default 200; 'all' for everything)")
    ap.add_argument("--follow", action="store_true", help="poll for new lines after the initial tail (bounded, see --duration/--interval)")
    ap.add_argument("--duration", type=int, default=60, help="with --follow, total seconds to keep polling (default 60)")
    ap.add_argument("--interval", type=int, default=5, help="with --follow, seconds between polls (default 5)")
    ap.add_argument("--since", default=None, help="unix timestamp to start from")
    args = ap.parse_args()

    _load_credentials_file()
    base = ENV_BASE_URLS[args.env]
    jwt = _auth(base)
    container_id = _resolve_container_id(base, jwt, args.container)
    tty = _is_tty(base, jwt, container_id)

    if args.follow:
        _poll(base, jwt, container_id, tty, args.tail, args.duration, args.interval)
        return

    params = {"stdout": "true", "stderr": "true", "tail": args.tail, "timestamps": "true"}
    if args.since:
        params["since"] = args.since
    print(_fetch_text(base, jwt, container_id, tty, params), end="")


if __name__ == "__main__":
    main()
