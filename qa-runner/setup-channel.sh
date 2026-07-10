#!/usr/bin/env bash
# One-time: create the private #qa-runner channel (admin + bot only) and print its
# id. Paste that id into config.env as QA_DISCORD_CHANNEL_ID. Safe to skip if you'd
# rather make the channel by hand — any channel the bot can see works.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh" 2>/dev/null || {
  # lib.sh needs config.env, which we don't have yet on first run — load just creds.
  QA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  WORKSPACE="$(cd "$QA_DIR/.." && pwd)"
  set -a; . "$WORKSPACE/discord-credentials.env"; set +a
}
: "${DISCORD_GUILD_ID:?DISCORD_GUILD_ID not found in discord-credentials.env}"
name="${1:-qa-runner}"
id="$(python3 "$QA_DIR/discord.py" mkchan "$DISCORD_GUILD_ID" "$name")"
echo "Created #$name -> channel id: $id"
echo "Put this in qa-runner/config.env:  QA_DISCORD_CHANNEL_ID=$id"
