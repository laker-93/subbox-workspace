#!/usr/bin/env python3
"""Tiny Discord REST helper for the QA runner — stdlib only, no pip deps.

Usage:
  discord.py post   <channel_id> <text>        # post a message (chunks >2000 chars)
  discord.py fetch  <channel_id> [after_id]     # print human messages after an id, oldest first
  discord.py mkchan <guild_id>   <name>         # create an admin-only private text channel, print its id

Auth: reads DISCORD_BOT_TOKEN from the environment (sourced from
discord-credentials.env by lib.sh). The bot must be in the guild; for `fetch`
to see message text, enable "Message Content Intent" in the Developer Portal.
"""
import json
import os
import sys
import urllib.error
import urllib.request

API = "https://discord.com/api/v10"


def _req(method, path, body=None):
    token = os.environ["DISCORD_BOT_TOKEN"]
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        API + path,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bot {token}",
            "Content-Type": "application/json",
            "User-Agent": "subbox-qa-runner (https://sub-box.net, 1.0)",
        },
    )
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        sys.stderr.write(f"Discord {method} {path} -> {e.code}: {e.read().decode()}\n")
        raise


def _chunks(text, n=1900):
    # Split on line boundaries where possible so code/log lines stay intact.
    out, cur = [], ""
    for line in text.splitlines(keepends=True):
        if len(cur) + len(line) > n:
            if cur:
                out.append(cur)
            # a single very long line still has to be hard-split
            while len(line) > n:
                out.append(line[:n])
                line = line[n:]
            cur = line
        else:
            cur += line
    if cur:
        out.append(cur)
    return out or [""]


def post(channel_id, text):
    for chunk in _chunks(text):
        _req("POST", f"/channels/{channel_id}/messages", {"content": chunk})


def fetch(channel_id, after_id=None):
    path = f"/channels/{channel_id}/messages?limit=100"
    if after_id:
        path += f"&after={after_id}"
    msgs = _req("GET", path) or []
    # API returns newest-first; we want oldest-first, humans only (skip bots).
    for m in sorted(msgs, key=lambda x: int(x["id"])):
        if m.get("author", {}).get("bot"):
            continue
        content = (m.get("content") or "").strip()
        if not content:
            continue
        author = m.get("author", {}).get("username", "you")
        print(json.dumps({"id": m["id"], "author": author, "content": content}))


def mkchan(guild_id, name):
    # type 0 = text; deny VIEW_CHANNEL (0x400) for @everyone so only admins + the
    # bot see it. In a personal guild you (owner/admin) still see it; the public
    # community does not.
    ch = _req(
        "POST",
        f"/guilds/{guild_id}/channels",
        {
            "name": name,
            "type": 0,
            "topic": "subbox QA runner: daily digests + your replies steer the loop",
            "permission_overwrites": [
                {"id": guild_id, "type": 0, "deny": str(0x400)},  # @everyone role == guild id
            ],
        },
    )
    print(ch["id"])


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "post":
        post(sys.argv[2], sys.argv[3])
    elif cmd == "fetch":
        fetch(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    elif cmd == "mkchan":
        mkchan(sys.argv[2], sys.argv[3])
    else:
        sys.stderr.write(__doc__)
        sys.exit(2)
