#!/usr/bin/env bash
# Shared setup for the QA runner scripts. Sourced, not executed.
set -euo pipefail

QA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$QA_DIR/.." && pwd)"          # subbox-workspace root

# Discord bot token (gitignored, workspace root).
if [[ -f "$WORKSPACE/discord-credentials.env" ]]; then
  set -a; . "$WORKSPACE/discord-credentials.env"; set +a
fi

# Runner config (machine-specific; gitignored).
if [[ -f "$QA_DIR/config.env" ]]; then
  set -a; . "$QA_DIR/config.env"; set +a
else
  echo "qa-runner: missing config.env — copy config.env.example and fill it in." >&2
  exit 1
fi

: "${QA_DISCORD_CHANNEL_ID:?set QA_DISCORD_CHANNEL_ID in config.env}"
: "${DISCORD_BOT_TOKEN:?DISCORD_BOT_TOKEN not found (discord-credentials.env)}"
: "${QA_CYCLES:=6}"
: "${QA_MODEL:=claude-opus-4-8}"

STATE_DIR="$QA_DIR/state"
mkdir -p "$STATE_DIR"

FEISHIN_QA="$WORKSPACE/../feishin-qa"
PYMIX_QA="$WORKSPACE/../pymix-qa"
DIRECTIVES="$FEISHIN_QA/docs/qa/directives.md"
PAUSE_FLAG="$STATE_DIR/paused"

: "${QA_FEISHIN_BASE:=development}"   # subbox-app PR base
: "${QA_PYMIX_BASE:=main}"           # pymix PR base
: "${QA_PR_LABEL:=qa-auto}"          # label on every PR the loop opens

discord_post() { python3 "$QA_DIR/discord.py" post "$QA_DISCORD_CHANNEL_ID" "$1"; }

# owner/repo slug from a worktree's origin remote (handles ssh + https URLs).
repo_slug() { git -C "$1" remote get-url origin | sed -E 's#.*github\.com[:/]##; s#\.git$##'; }

# PR base branch for a given QA worktree.
base_for() {
  case "$1" in
    *pymix-qa*)                      echo "$QA_PYMIX_BASE" ;;
    *feishin-qa*|*subbox-app-qa*)    echo "$QA_FEISHIN_BASE" ;;
    *) echo "$QA_FEISHIN_BASE" ;;
  esac
}
