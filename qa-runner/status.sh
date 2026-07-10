#!/usr/bin/env bash
# Print a phone-friendly status: is a batch running right now (which cycle), plus
# the open PRs it's waiting for you to review. Used by the `status` Discord command
# and handy to run locally. The directive queue moved to the `directives` command
# (directives.sh) — this reports the live run, which status.sh previously ignored.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

echo "**subbox QA — status**"
[[ -f "$PAUSE_FLAG" ]] && echo "⏸️ PAUSED (post \`resume\` to re-enable daily runs)"

echo
echo "__Run__"
# run-daily.sh holds run.lock.d/pid for the duration of a batch (mkdir-atomic,
# removed on exit). A live pid means a batch is driving the stack right now; the
# newest logs/ dir is that run's, and its highest cycle-N.log is the current cycle.
pid="$(cat "$STATE_DIR/run.lock.d/pid" 2>/dev/null || true)"
if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
  rundir="$(ls -td "$STATE_DIR"/logs/*/ 2>/dev/null | head -1)"
  cyc="?"; started=""
  if [[ -n "$rundir" ]]; then
    cyc="$(ls "$rundir"cycle-*.log 2>/dev/null \
             | sed -E 's#.*/cycle-([0-9]+)\.log#\1#' | sort -n | tail -1)"
    b="$(basename "$rundir")"                    # e.g. 20260710-075555
    started=", started ${b:0:4}-${b:4:2}-${b:6:2} ${b:9:2}:${b:11:2}"
  fi
  echo "🟢 running — cycle ${cyc:-?}/${QA_CYCLES} (pid $pid$started)"
  echo "_(directive queue: post \`directives\`)_"
else
  echo "⚪ idle — no batch running. Post \`directives\` for the queue, or run \`./run-daily.sh\`."
fi

echo
echo "__Open PRs awaiting your review__"
any=0
for WT in "$FEISHIN_QA" "$PYMIX_QA"; do
  [[ -d "$WT" ]] || continue
  slug="$(repo_slug "$WT")"
  rows="$(gh pr list --repo "$slug" --state open --label "$QA_PR_LABEL" \
            --json number,title,url --jq '.[] | "#\(.number) \(.title) — \(.url)"' 2>/dev/null)"
  if [[ -n "$rows" ]]; then any=1; echo "$slug:"; echo "$rows"; fi
done
[[ "$any" == 0 ]] && echo "_(none)_"
