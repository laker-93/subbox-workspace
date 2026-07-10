# qa-runner — daily unattended continuous-UX loop with a phone bridge

Runs the `continuous-ux` QA loop on **this Mac** once a day, fixes what it can
(including coordinated cross-repo fixes — see `docs/qa.md`), **opens a PR per fix**
for you to review, and talks to your phone over Discord. After you merge a PR it
**syncs the merged code back** into the QA worktrees and continues.

## Why local, not a cloud routine

The loop drives the real Electron client and the local Traefik/Docker stack
(per-user Navidrome/beets containers). None of that exists in an Anthropic cloud
agent, so it has to run where the stack runs. launchd triggers it; Discord is the
phone channel; GitHub PRs are the review surface.

## How it fits together

```
launchd: qa-poller   (every 15 s, cheap — no claude)
  └─ pull-directives.sh
       ├─ your Discord messages → feishin-qa/docs/qa/directives.md (PENDING)
       └─ commands: `status` → live run + open PRs; `directives` → the queue;
          `pause`/`resume`

launchd: qa-runner   (05:00 daily)
  └─ run-daily.sh
       ├─ (skip if paused)
       ├─ sync-merged.sh   → rebase claude/continuous-ux onto development/main
       │                     (drops fixes whose PRs you merged; pulls new code)
       ├─ claude -p "/continuous-ux" × QA_CYCLES   (each a fresh cycle, local stack)
       │     └─ per verified fix → commit → open-pr.sh → one PR (label qa-auto)
       └─ discord.py post  → digest: cycles, PRs opened, commits, blocked items
```

Inbound reuses the loop's own steering surface: it **already reads `directives.md`
first every cycle**, so a phone message just becomes a PENDING directive.

## The bug → PR → merge → sync flow

1. Loop finds a bug, fixes it, **verifies before committing** (re-drives the exact
   flow; cross-repo = both sides live). Commits to `claude/continuous-ux`.
2. `open-pr.sh` cherry-picks that one commit onto a fresh branch off the real base
   (`development` for subbox-app, `main` for pymix) in a *throwaway* git worktree,
   pushes, and opens **one PR per fix** (label `qa-auto`). The PR URL is posted to
   Discord and recorded in `bugs.md`. A cross-repo fix opens **two cross-linked PRs**
   that must be merged together.
3. You review + merge on GitHub (from your phone).
4. The next daily run starts with `sync-merged.sh`: `git fetch` + rebase
   `claude/continuous-ux` onto the updated base. Your merged fix has the same
   patch-id upstream, so rebase **drops it** and pulls in the new code — then the
   loop continues. Conflicts abort cleanly and are flagged in the digest; nothing
   is ever force-pushed or merged by the loop.

## Using it from your phone

In the private Discord channel:

- **See what it's doing**: post **`status`** → replies whether a batch is running
  right now (which cycle of `QA_CYCLES`) and the open PRs waiting on you (answered
  within ~15 s by the poller).
- **See the queue**: post **`directives`** → replies with the `IN PROGRESS` +
  `PENDING` directives (what `status` used to show).
- **Steer / add a directive**: post any other message → becomes a PENDING directive
  the loop picks up next cycle.
- **Review fixes**: tap the PR links it posts; merge the good ones.
- **Pause / resume**: post `pause` (daily runs skip) or `resume`.

It's asynchronous — a background daily loop can't block waiting for you mid-cycle.
Want a directive acted on now? Run `./run-daily.sh` on the Mac.

## One-time setup

1. **`gh` + git push**: `gh auth status` should be logged in. If pushing over HTTPS,
   run `gh auth setup-git` once so `git push` has a credential helper (or make the
   worktree remotes SSH). The loop opens PRs with `gh`.
2. **Discord bot**: already in your guild. In the Developer Portal enable **Message
   Content Intent** so it can read your replies; it needs *Manage Channels* only for
   `setup-channel.sh`.
3. **Private channel**: `./setup-channel.sh` → creates admin-only `#qa-runner`,
   prints its id (keeps QA chatter out of public community channels).
4. **Config**: `cp config.env.example config.env`, set `QA_DISCORD_CHANNEL_ID`.
5. **Smoke-test**: `./status.sh` (read-only), then `./run-daily.sh` for a full batch.
6. **Install the schedules**:
   ```
   cp com.subbox.qa-runner.plist com.subbox.qa-poller.plist ~/Library/LaunchAgents/
   launchctl load ~/Library/LaunchAgents/com.subbox.qa-runner.plist
   launchctl load ~/Library/LaunchAgents/com.subbox.qa-poller.plist
   ```
   Edit paths / the daily `Hour` in the plists first if this repo isn't at the
   default location.

## Safety

The loop's hard rules (`docs/qa.md` + the journal READMEs it reads first) bound it:
local dev stack only, never staging/prod, verify-before-commit gate absolute
(including cross-repo pairs), one fix commit per repo per cycle. It **now pushes and
opens PRs** (you asked for it) but **never merges and never force-pushes** — you are
the merge gate. It runs headless with `--permission-mode bypassPermissions` because
no human approves tool calls live; those rules are what keep an unattended run safe.

## Operating

- Per-run output: `state/logs/<timestamp>/` (`cycle-N.log` each + `digest.md`).
  launchd stdout/err: `state/{launchd,poller}.*.log`.
- Stop: `launchctl unload ~/Library/LaunchAgents/com.subbox.qa-{runner,poller}.plist`
- Docker Desktop must be running for the stack; the digest flags "stack not
  detected" if it isn't up at run time.
