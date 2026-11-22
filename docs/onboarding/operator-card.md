# Operator card: what you approve, what you type, what the red messages mean

One page for the person, not the agent. The agent reads the four core documents.
Where setups differ, a line starts with Solo:, Team: or Jira:.

## What you approve

- The design, before any code is written. Then the merge, once the pull request is green.
- Solo: you type the GO yourself, and the admin merge is yours alone.
- Team: a forge Approve from someone who did not write it. With GO_ACT=review, an Approve with
  no words is the GO.
- Jira: you also move the cards the agent cannot (it has no account of its own yet).

## What you type

Only a person does these. Each is one line.

- `sh scripts/preflight.sh`, `sh scripts/sparkwright doctor`: full 25-50 min [estimate, 2026-10-14,
  may be low]. `--quick`: status lines in 3 s [measured 2026-11-15, v3.247.0, n = 1], plus up to
  about 20 s of tracker reads [timeout limit]; skips conformance. See `docs/operations/doctor.md`.
- `/hooks` and `/status`, once per session: the guard hook is listed, Project settings is on.
- The egress merge that preflight prints, into `~/.claude/settings.json`, once per machine.
- `gh auth refresh -h github.com -s workflow`, so the agent may push workflow files.
- Admin, real terminal: `sh scripts/branch-protection-apply.sh --replace` (team: add `--team`).
- Jira: make the two accounts and the token, then set the `KIT_TRACKER_USER` and
  `KIT_TRACKER_TOKEN` Actions secrets. If your own token is the CI reader, the tracker setup
  check prints FAIL by design: create the agent account.

## What the red messages mean

Each entry is the exact text the kit prints, the file it comes from, and the one thing to do.

<!-- operator-card:entries:begin -->
### `escape card R<n> <slug>`
From: .claude/hooks/guard-core.sh
Do: the agent takes that row's one retry, once. You do nothing unless it stops.

### `Next: stop and escalate.`
From: .claude/hooks/guard-core.sh
Do: the agent stops and shows you the command. You decide. Do not set the override because it asks.

### `escape card R1 quoted-alternation`
From: .claude/hooks/guard-core.sh
Do: the agent retries once with `grep -e A -e B <path>`, or the Grep tool.

### `escape card R30 cp-write`
From: .claude/hooks/guard-core.sh
Do: the agent makes kit-file changes in a dev clone, then opens a pull request.

### `Next: push a feature branch and open a PR instead`
From: .claude/hooks/guard-core.sh
Do: expected after the first push. Every later change goes through a pull request.

### `agent-guard: the guard hook did not return a decision`
From: conformance/guard-wired.sh
Do: relaunch the session in the project root. (The hook command is in .claude/settings.json.)

### `FAIL egress: NOT ENFORCED and UNDECLARED [static]`
From: scripts/preflight.sh
Do: do the one-time egress merge that preflight prints under that line.

### `FAIL boundary: OFF and UNDECLARED`
From: scripts/preflight.sh
Do: you (not the agent) turn it on, or declare the opt-out with part=all in
.kit/boundary-optout.conf.

### `Overall: FAIL  (`
From: scripts/doctor.sh
Do: the parenthesis says why: it names the failed part, or says to run doctor without --quick.
<!-- operator-card:entries:end -->
