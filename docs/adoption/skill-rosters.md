# Skill-Roster Adapter Guide

The kit ships its **own process roster** — a spine of skills (`design`, `plan`, `tdd`, `review`, `verification`, …) indexed by its discovery keystone (`skills/using-skills/SKILL.md`). Your environment may also carry a **foreign process-skill library** (e.g. superpowers) that injects its own "use my skill first" keystone at session start. The kit **prefers its own roster** — as **preference, not prohibition**.

## The contract: the kit's roster is the default

The floor is a portable contract, not a lock: `CLAUDE.md`/`AGENTS.md` make the kit's roster the default for process work, and the keystone (`skills/using-skills/SKILL.md`) supersedes any foreign injected keystone — a foreign injection sits at the *default/skill* tier and does not outrank the repo's own law. This steers on **any** harness (it is documented convention, not an enforced auto-load). An explicit user request for a foreign skill is always honored — instruction priority wins.

## The opt-in dial *(Claude Code)*

For adopters who want **teeth**, a PreToolUse guard can intercept a foreign process-skill invocation. It is configured in `.kit/roster.conf` (mirrors `.kit/budget.conf`) and **ships off**:

- **`MODE=off|ask|deny`** — `off` (default): never intercept; the contract does the steering. `ask`: the user confirms each foreign process-skill call (the reason names the kit equivalent). `deny`: the call is blocked with a redirect to the kit equivalent. Only `off`, `ask`, and `deny` are recognized — any other value (typo, blank) fail-safes to `off`, so a mis-set dial never wedges the session.
- **`BLOCKLIST`** — space-separated process-library **namespaces**, seeded `superpowers`. Only these are ever intercepted.
- **`KIT_ROSTER_GUARD`** — an env var that overrides `MODE` for one session.

## Bring your own foreign library

Carrying a *different* foreign process library? Add its namespace to `BLOCKLIST` in `.kit/roster.conf`:

```
MODE=ask
BLOCKLIST="superpowers my-other-process-lib"
```

**Utility skills are never intercepted.** figma, LSPs, git helpers, MCP tools, and the like are not process-overlap and are absent from the blocklist — they always pass. Only libraries you *name* are touched.

## The `deny` override

`deny` is never an absolute prohibition. A user who genuinely wants a foreign skill sets `KIT_ROSTER_GUARD=off` (or `ask`) for that session — so even the hard setting preserves "preference, not prohibition."

## Honest ceiling

- **Claude-Code-only (NATIVE).** The dial needs PreToolUse hooks. Other harnesses rely on the **FLOOR contract alone** (`CLAUDE.md`/`AGENTS.md` + the keystone) — the steer, without the teeth.
- **The guard sees a tool call, not intent.** It cannot tell drift from a deliberate choice, so `deny` is blunt by nature. That is *why* it ships `off`, why `ask` is the recommended middle, and why `deny` always has the env override.
- A green run proves the dial is *wired and each mode behaves* (`conformance/roster-guard-wired.sh`), **not** that any real session ran with it on — enforcement is your opt-in.
