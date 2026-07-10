#!/usr/bin/env python3
"""Classify inbound Discord messages (one JSON object per stdin line, as emitted
by `discord.py fetch`): recognised commands are echoed as `CMD:<name>` on stdout
for the shell to handle; everything else is filed as a PENDING directive in
directives.md. Advances the last-seen id. Kept as its own file (not a heredoc) so
the piped messages reach stdin — `python3 - <<EOF` would steal stdin for the script.

Env: DIRECTIVES (path to directives.md), LAST_FILE (path to last-seen-id state).
"""
import datetime
import json
import os
import sys

COMMANDS = {"status", "directives", "directive", "pause", "resume"}

path = os.environ["DIRECTIVES"]
last_file = os.environ["LAST_FILE"]
entries, last_id, out = [], None, []

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    m = json.loads(line)
    last_id = m["id"]
    content = m["content"].strip()
    key = content.lstrip("/").strip().lower()
    if key in COMMANDS:
        out.append("CMD:" + ("directives" if key == "directive" else key))
        continue
    today = datetime.date.today().isoformat()
    req = content.replace("\n", " ").strip()
    entries.append(
        f"### From phone (Discord) — {today}\n"
        f"Added: {today}\n"
        f"Request: {req}\n"
        f"Notes: submitted via Discord by {m['author']}; break into sub-steps as needed.\n"
    )

if entries:
    text = open(path).read()
    text = text.replace("_(none — see IN PROGRESS)_\n", "", 1)
    idx = text.index("## PENDING")
    close = text.index("-->", idx) + len("-->")
    text = text[:close] + "\n\n" + "\n".join(entries) + text[close:]
    open(path, "w").write(text)
if last_id:
    open(last_file, "w").write(last_id)

sys.stderr.write(f"pull-directives: {len(entries)} directive(s) filed\n")
print("\n".join(out))
