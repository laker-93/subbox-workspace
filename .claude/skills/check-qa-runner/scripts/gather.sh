#!/usr/bin/env bash
# Gather raw qa-runner status data for the last N days (default 2). Read-only.
# Prints structured sections for the calling model to synthesize into a summary —
# it does no interpretation itself (which failures are "real" vs transient,
# whether a 0-cycle night matters, etc).
set -uo pipefail

DAYS="${1:-2}"
WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
QA_DIR="$WORKSPACE/qa-runner"
STATE_DIR="$QA_DIR/state"
FEISHIN_QA="$WORKSPACE/../feishin-qa"
PYMIX_QA="$WORKSPACE/../pymix-qa"

CUTOFF_EPOCH=$(( $(date +%s) - DAYS * 86400 ))
CUTOFF_DATE=$(date -j -f %s "$CUTOFF_EPOCH" +%Y-%m-%d 2>/dev/null || date -d "@$CUTOFF_EPOCH" +%Y-%m-%d)

echo "# qa-runner status — last $DAYS day(s) (since $CUTOFF_DATE)"
echo

# --- launchd health -----------------------------------------------------------
echo "## launchd agents"
for label in com.subbox.qa-runner com.subbox.qa-poller; do
  line="$(launchctl list 2>/dev/null | grep -F "$label" || true)"
  if [[ -n "$line" ]]; then
    echo "$label: $line   (columns: PID  last-exit-status  label)"
  else
    echo "$label: NOT LOADED"
  fi
done
if [[ -f "$STATE_DIR/paused" ]]; then
  echo "PAUSED: yes (qa-runner/state/paused exists — daily runs are being skipped)"
else
  echo "PAUSED: no"
fi
echo

# --- per-run digests + cycle-log error scan -----------------------------------
echo "## Runs in window"
any_run=0
for rundir in $(ls -d "$STATE_DIR"/logs/*/ 2>/dev/null | sort); do
  ts="$(basename "$rundir")"                      # YYYYMMDD-HHMMSS
  run_epoch="$(date -j -f "%Y%m%d-%H%M%S" "$ts" +%s 2>/dev/null || date -d "${ts:0:8} ${ts:9:2}:${ts:11:2}:${ts:13:2}" +%s 2>/dev/null || echo 0)"
  [[ "$run_epoch" -lt "$CUTOFF_EPOCH" ]] && continue
  any_run=1
  echo "### run $ts"
  if [[ -f "$rundir/digest.md" ]]; then
    sed 's/^/    /' "$rundir/digest.md"
  else
    echo "    (no digest.md — run may still be in progress or crashed before posting)"
  fi
  for cyclelog in "$rundir"cycle-*.log; do
    [[ -f "$cyclelog" ]] || continue
    n="$(basename "$cyclelog")"
    # Flag known connectivity/infra failure signatures distinctly from normal
    # cycle output (which is long and not meant to be dumped here).
    if grep -qE 'API Error|Request timed out|Connection closed|ENOTFOUND|ECONNREFUSED' "$cyclelog"; then
      sig="$(grep -m1 -E 'API Error|Request timed out|Connection closed|ENOTFOUND|ECONNREFUSED' "$cyclelog")"
      echo "    ⚠️  $n: $sig"
    fi
  done
  echo
done
[[ "$any_run" == 0 ]] && echo "(no runs found in this window)"
echo

# --- issues filed in window ----------------------------------------------------
echo "## Bug issues filed in window"
if [[ -f "$STATE_DIR/issues.log" ]]; then
  awk -F'\t' -v t="$CUTOFF_EPOCH" 'NF>=2 && $1>=t {print "  " $2 "  (" $3 ")"}' "$STATE_DIR/issues.log"
else
  echo "  (no issues.log)"
fi
echo

# --- journal log.md entries in window (both QA worktrees) ---------------------
# Entries start a line with a YYYY-MM-DD date (optionally + " HH:MM"); everything
# up to the next such line is one entry. We filter on that leading date.
for pair in "feishin-qa:$FEISHIN_QA" "pymix-qa:$PYMIX_QA"; do
  name="${pair%%:*}"; wt="${pair#*:}"
  logf="$wt/docs/qa/log.md"
  echo "## $name journal entries (docs/qa/log.md) in window"
  if [[ -f "$logf" ]]; then
    awk -v cutoff="$CUTOFF_DATE" '
      /^2[0-9]{3}-[0-9]{2}-[0-9]{2}/ {
        d = substr($0, 1, 10)
        show = (d >= cutoff)
      }
      show { print }
    ' "$logf"
  else
    echo "  (no log.md at $logf)"
  fi
  echo
done

# --- currently-open bugs (not time-scoped — a standing health check) ----------
for pair in "feishin-qa:$FEISHIN_QA" "pymix-qa:$PYMIX_QA"; do
  name="${pair%%:*}"; wt="${pair#*:}"
  bugsf="$wt/docs/qa/bugs.md"
  echo "## $name currently-OPEN bugs (docs/qa/bugs.md, ### headings under ## OPEN)"
  if [[ -f "$bugsf" ]]; then
    awk '/^## OPEN/{f=1;next} /^## /{f=0} f && /^### /{print}' "$bugsf"
  else
    echo "  (no bugs.md at $bugsf)"
  fi
  echo
done

# --- open PRs from the loop still awaiting review ------------------------------
echo "## Open qa-auto PRs awaiting review"
for wt in "$FEISHIN_QA" "$PYMIX_QA"; do
  [[ -d "$wt" ]] || continue
  slug="$(git -C "$wt" remote get-url origin 2>/dev/null | sed -E 's#.*github\.com[:/]##; s#\.git$##')"
  [[ -n "$slug" ]] || continue
  rows="$(gh pr list --repo "$slug" --state open --label qa-auto \
            --json number,title,url --jq '.[] | "  #\(.number) \(.title) — \(.url)"' 2>/dev/null)"
  [[ -n "$rows" ]] && { echo "$slug:"; echo "$rows"; }
done
echo
