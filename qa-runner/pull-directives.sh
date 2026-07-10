#!/usr/bin/env bash
# The frequent (every ~15 s) inbound poller — cheap, no `claude`. Reads new
# Discord messages and either:
#   • handles a command   — `status` (is a batch running + open PRs),
#                           `directives` (the IN PROGRESS / PENDING queue),
#                           `pause` / `resume` (toggle daily runs)
#   • or files it as a directive — appended to feishin-qa/docs/qa/directives.md
#     PENDING, which the loop reads first every cycle.
# Idempotent via a last-seen message id.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

LAST_FILE="$STATE_DIR/last-message-id"
AFTER="$(cat "$LAST_FILE" 2>/dev/null || true)"

MSGS="$(python3 "$QA_DIR/discord.py" fetch "$QA_DISCORD_CHANNEL_ID" "$AFTER")"
[[ -z "$MSGS" ]] && { echo "pull-directives: no new messages"; exit 0; }

# process_inbound.py (a real file, not a heredoc — otherwise the heredoc would
# steal stdin from the piped messages): files directives, advances the last-seen
# id, and prints one `CMD:<name>` line per recognised command message.
cmds="$(printf '%s\n' "$MSGS" | DIRECTIVES="$DIRECTIVES" LAST_FILE="$LAST_FILE" \
        python3 "$QA_DIR/process_inbound.py")"

# Handle commands (dedupe each — one reply per command is enough).
handled_status=0
handled_directives=0
while IFS= read -r c; do
  case "$c" in
    CMD:status)
      [[ "$handled_status" == 1 ]] && continue
      handled_status=1
      discord_post "$("$QA_DIR/status.sh")" ;;
    CMD:directives)
      [[ "$handled_directives" == 1 ]] && continue
      handled_directives=1
      discord_post "$("$QA_DIR/directives.sh")" ;;
    CMD:pause)
      touch "$PAUSE_FLAG"
      discord_post "⏸️ Paused — daily runs will skip until you post \`resume\`." ;;
    CMD:resume)
      rm -f "$PAUSE_FLAG"
      discord_post "▶️ Resumed — the next scheduled run will execute." ;;
  esac
done <<< "$cmds"
