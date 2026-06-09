# `.claude/` — Agent Governance Layer

Enforces the **§13 autonomy matrix** and **§12 separations** (`DEVELOPMENT-PROCESS.md`) for Claude Code agents. This directory is **both** the kit's own governance **and** the reference adopters copy — drop it into your repo and adapt.

## Files
- **`settings.json`** — shared, committed. Permission `allow`/`ask`/`deny` globs + the PreToolUse hook wiring.
- **`settings.local.json`** — personal, **gitignored**. Your machine-local overrides; never committed.
- **`hooks/guard.sh`** — PreToolUse hook. A **best-effort speed bump, not a security boundary** (see Coverage boundary below). Denies irreversible / high-blast actions: recursive *and* scalpel rm (globs, data files, absolute paths), non-rm destruction (truncate/dd/shred/find -delete/rsync --delete/git clean/redirect-truncation), force-push, push-to-main, reset --hard, amend, package publish, destructive SQL / DB resets, cloud/infra destruction (terraform destroy, *-delete/terminate, helm uninstall, kubectl drain), obfuscation (decode|sh, eval $(), git -c push), partial exfiltration (scp/curl-upload/nc/rclone/mail), prod/infra deploy, writing secret files, and — absolutely — **modifying the guard, its config, CI gates, or CODEOWNERS** (`KIT_GUARD_SELFEDIT=1` is the human-only maintenance escape). Defers everything else to the permission globs. Matches the relevant *field* only (so editing a doc that mentions a dangerous command is not blocked); within a Bash command it errs toward over-blocking quoted dangerous strings.
- **`agents/reviewer.md`**, **`agents/security-reviewer.md`** — read-only review subagents enforcing builder ≠ reviewer and the security gate.

## Prerequisite
`guard.sh` requires **`jq`** (to parse the tool-call JSON safely). Install it (`brew install jq` / `apt-get install jq`). If jq is missing — or the tool input is not valid JSON — the guard denies mutating tools and allows read-only; it never runs unguarded silently.

## Adapting (per `DEVELOPMENT-PROCESS.md` §13)
Start conservative; raise an action's autonomy as agent-quality metrics earn it. Loosen by moving an entry from `deny`→`ask`→`allow` in `settings.json`, or by editing the deny patterns in `hooks/guard.sh`. Keep irreversible/high-blast actions human-gated.

## Conformance
`conformance/agent-autonomy.sh` proves the guard denies the irreversible battery and allows the safe one (including false-positive and bypass-resistance regressions). It runs in CI.

## Coverage boundary

This guard is a **best-effort speed bump for honest mistakes, not a security boundary.** A determined or compromised agent can bypass a shell deny-list (novel tools, interpreters, obfuscation), and exfiltration has no reliable command signature — an adversarial red-team (2026-06-09) confirmed a deny-list always has a bypass tail. The guard reduces *accidental* blast radius and protects its own integrity; it does not contain a hostile process.

The **real boundary** is platform-owned: a network-egress allowlist, separate production credentials, a sandboxed filesystem, and scoped short-lived tokens — see [`../docs/enterprise/platform-safety-boundary.md`](../docs/enterprise/platform-safety-boundary.md). Adopt the guard and the platform boundary together.

This guard also governs the **Claude Code agent runtime only**. A human at a shell, or a different agent runtime, is not covered. Those gaps are **Org-owned** (see `../docs/enterprise/README.md`).
