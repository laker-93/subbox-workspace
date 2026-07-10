#!/usr/bin/env bash
# One daily batch: pull phone directives, run N continuous-ux cycles headless on
# the local stack, then post one digest to Discord. Launched by launchd once a day.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

RUN_TS="$(date '+%Y-%m-%d %H:%M')"
RUN_LOG_DIR="$STATE_DIR/logs/$(date '+%Y%m%d-%H%M%S')"
mkdir -p "$RUN_LOG_DIR"
ROOT="$(cd "$WORKSPACE/.." && pwd)"   # parent of all sibling repos

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# --- Single-run lock: never let two batches drive the stack at once ----------
# mkdir is atomic, so this is race-free. A stale lock (owner process gone) is
# cleared and reclaimed.
LOCKDIR="$STATE_DIR/run.lock.d"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  oldpid="$(cat "$LOCKDIR/pid" 2>/dev/null || true)"
  if [[ -n "$oldpid" ]] && kill -0 "$oldpid" 2>/dev/null; then
    log "another run (pid $oldpid) is active — exiting."
    exit 0
  fi
  log "clearing stale lock (owner pid ${oldpid:-unknown} is gone)."
  rm -rf "$LOCKDIR"; mkdir "$LOCKDIR"
fi
echo "$$" > "$LOCKDIR/pid"
trap 'rm -rf "$LOCKDIR"' EXIT

# --- 0. Respect a phone `pause` ----------------------------------------------
if [[ -f "$PAUSE_FLAG" ]]; then
  discord_post "⏸️ subbox QA is paused — skipping the $RUN_TS run. Post \`resume\` to re-enable."
  log "paused; skipping."; exit 0
fi

# --- 1. Inbound: fold any phone messages into directives.md -------------------
"$QA_DIR/pull-directives.sh" || log "pull-directives failed (continuing)"

# --- 1b. Pull merged PRs back into the QA worktrees, then continue ------------
sync_report="$("$QA_DIR/sync-merged.sh" || echo 'sync-merged failed (continuing)')"
log "sync:\n$sync_report"

# --- 2. Snapshot so we can diff what the batch produced -----------------------
feishin_log="$FEISHIN_QA/docs/qa/log.md"
pymix_log="$PYMIX_QA/docs/qa/log.md"
before_f=$(wc -l < "$feishin_log" 2>/dev/null || echo 0)
before_p=$(wc -l < "$pymix_log" 2>/dev/null || echo 0)
head_f=$(git -C "$FEISHIN_QA" rev-parse HEAD 2>/dev/null || echo none)
head_p=$(git -C "$PYMIX_QA" rev-parse HEAD 2>/dev/null || echo none)

stack_note=""
docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^pymix$' || \
  stack_note="⚠️ local stack (pymix container) not detected — cycles may be blocked."

# --- 3. Run the cycles (each a fresh `claude -p`, per the loop's design) -------
TIMEOUT=""
if command -v gtimeout >/dev/null 2>&1 && [[ -n "${QA_CYCLE_TIMEOUT:-}" ]]; then
  TIMEOUT="gtimeout $QA_CYCLE_TIMEOUT"
fi

completed=0
for i in $(seq 1 "$QA_CYCLES"); do
  log "cycle $i/$QA_CYCLES"
  if (cd "$WORKSPACE" && $TIMEOUT claude -p "/continuous-ux" \
        --model "$QA_MODEL" \
        --permission-mode bypassPermissions \
        --add-dir "$ROOT" \
        > "$RUN_LOG_DIR/cycle-$i.log" 2>&1); then
    completed=$((completed + 1))
  else
    log "cycle $i exited non-zero (see cycle-$i.log)"
  fi
done

# --- 4. Diff what happened ----------------------------------------------------
new_f=$(git -C "$FEISHIN_QA" log --oneline "$head_f"..HEAD 2>/dev/null || true)
new_p=$(git -C "$PYMIX_QA" log --oneline "$head_p"..HEAD 2>/dev/null || true)
after_f=$(wc -l < "$feishin_log" 2>/dev/null || echo 0)
after_p=$(wc -l < "$pymix_log" 2>/dev/null || echo 0)
logdelta_f=$(tail -n +"$((before_f + 1))" "$feishin_log" 2>/dev/null || true)
logdelta_p=$(tail -n +"$((before_p + 1))" "$pymix_log" 2>/dev/null || true)
blocked=$( { grep -hiE 'blocked' <<<"$logdelta_f$logdelta_p" || true; } )
# PRs opened this run (open-pr.sh prints the URL into the cycle logs).
prs=$( { grep -hoE 'https://github.com/[^ ]+/pull/[0-9]+' "$RUN_LOG_DIR"/cycle-*.log 2>/dev/null | sort -u || true; } )

# --- 5. Compose + post the digest ---------------------------------------------
{
  echo "**subbox QA — daily run $RUN_TS**"
  echo "Cycles completed: $completed/$QA_CYCLES"
  [[ -n "$stack_note" ]] && echo "$stack_note"
  echo
  if [[ -n "$prs" ]]; then
    echo "__PRs opened — review & merge (I'll sync after you merge)__"
    echo "$prs"
    echo
  fi
  if [[ -n "$new_f$new_p" ]]; then
    echo "__Fix commits (claude/continuous-ux)__"
    [[ -n "$new_f" ]] && { echo "subbox-app:"; echo "$new_f"; }
    [[ -n "$new_p" ]] && { echo "pymix:"; echo "$new_p"; }
  elif [[ -z "$prs" ]]; then
    echo "No fixes committed this run."
  fi
  if [[ "$sync_report" == *"⚠️"* ]]; then
    echo
    echo "__Merge-sync__"
    echo "$sync_report"
  fi
  echo
  if [[ -n "$logdelta_f$logdelta_p" ]]; then
    echo "__Cycle log__"
    [[ -n "$logdelta_f" ]] && echo "$logdelta_f"
    [[ -n "$logdelta_p" ]] && echo "$logdelta_p"
  fi
  if [[ -n "$blocked" ]]; then
    echo
    echo "🔴 **Blocked / needs you** — reply here to steer the next run:"
    echo "$blocked"
  fi
} > "$RUN_LOG_DIR/digest.md"

discord_post "$(cat "$RUN_LOG_DIR/digest.md")"
log "digest posted; done."
