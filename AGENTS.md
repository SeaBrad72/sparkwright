# AGENTS.md — Agent Operating Brief

## 1. Entry contract — do this BEFORE any mutating action

⚠️ **Start the session in this repository's root, not a parent or a subfolder:** Claude Code loads the guard hooks only from the launch directory. If your launch directory (it is in your context) is not this root, stop before any edit and tell the human, who can confirm with `/hooks`. **Five acts, every slice, before the first edit / commit / PR.** The skills in `skills/` govern process work here (index: `skills/using-skills/SKILL.md`).

1. **Derive the change class.** Put the changed paths in a file, one per line, and run `sh conformance/promotion-readiness.sh --class --changed <listing>`. Pass the listing file, never a path — a path argument gets its CONTENTS classified. `conformance/agent-boundary.sh --state` is not a classifier; without `--changed` it answers `NONE`. Never self-assert the class.
2. **Read the governing skill; name it in act 4 if the class asks** — `skills/<name>/SKILL.md`. Design before code, evidence before "done"; search `docs/governance/DECISIONS.md` for a ruling on this surface; a design answers the twelve lenses in `skills/design/SKILL.md`.
3. **Claim the row by its id** — the backticked `ROW-ID` that leads its Item cell (`[A-Z0-9][A-Z0-9-]*`), with `sh scripts/board.sh claim <ROW-ID>`; that id is your `Kit-Row` value. No row, no build.
4. **Carry the Entry Declaration as commit trailers, proportional to the class** — Ordinary owes `Kit-Row` + `Kit-Class`; Sensitive/Control-plane owe `Kit-Stage` + `Kit-Skill` too (`Kit-Intent`, `Kit-Ceremony`, `Kit-Stop` optional). `conformance/loop-state.sh` (stage→skill map: `sh conformance/loop-state.sh --help`) checks the DERIVED class's required set on your PR's final commit: present once each, row on the board, class matching; a volunteered field is validated too. Enforced by default; `LOOP_STATE_MODE: observe` in `adopter-gates.yml` opts out.
5. **State the ceremony budget in one line**, derived from the class, so the owner can veto it in a sentence. Push board edits before you ask for review; seek approval only on the final diff. **Seats:** the conductor dispatches each build task to a **builder** seat, each review to a **reviewer** seat, and on Sensitive or Control-plane work a separate **security** seat. Each is typed by its `agents/*.agent.md` definition and dispatched through the harness's native binding where one exists (`START-HERE.md` step 7, `docs/operations/harness-adapters.md`). The conductor prefers a typed builder seat; when it builds, the Builder line says `conductor` (conduct, not enforced). The review record names each seat's role; `review-lane` grades the names and cannot see the dispatch.

**One command:** `sparkwright start <ROW-ID> [--changed <listing>]` runs acts 1 and 3 and prints this trailer block; the printed class is provisional — the gate re-derives it.

> ⚠️ **The trailer block must be the LAST paragraph of the commit message, and contiguous.** A blank line inside it truncates it — git reads only the paragraph after the blank, so every `Kit-*` field above it is lost.

> **Guard refused a command?** See `docs/operations/runtime-guards.md` §*The escape card*: one sanctioned retry per the escape card, else stop and escalate.

## What this file is

> **Index, not authority.** This is the ≤1-page brief for every harness whose adapter declares `AGENTS.md` as its `contextFile` (see `adapters/*/adapter.json` — the manifests are the enumeration, so adding a harness never dates this line). §1 above is **byte-identical in every adapter's declared `contextFile`** — enforced byte-for-byte by `conformance/agents-brief.sh`, so whichever document your harness auto-loads, the entry contract you read is the same one. Nothing may sit above §1, between §1 and this heading, or behind an empty closing heading; that whole zone is the locked one. The **principles doc** is authoritative — `CLAUDE.md` in the kit, `ENGINEERING-PRINCIPLES.md` once a project has been incepted (Inception renames it and stamps a project charter over `CLAUDE.md`); when this brief and a full doc disagree, the full doc wins. **Load a full doc only when your task touches it** — that keeps the per-feature context small. **Inception (Phase 0) is exempt from §1:** the five acts govern *loop* work, while `incept` is the one-time bootstrap that creates the repo and its control plane — there is no board, branch or change class yet. §1 binds from the first feature branch onward (`skills/design/SKILL.md`, `skills/build/SKILL.md`, `DEVELOPMENT-PROCESS.md` §3 "Bootstrap order").

## The loop
Discover → Plan → Build → Review → Release → Operate, with retrospectives closing each pass. Full flow, stages, and cadence: **`DEVELOPMENT-PROCESS.md`**.

## The gates (where humans ratify)
- **Definition of Ready** — the entry gate before Build (acceptance criteria · INVEST slice · deps · success metric · conditional flags). **`CLAUDE.md`**.
- **Definition of Done** — the exit gate before an item is closed. **`CLAUDE.md`**.
- **7 required CI gates** — on every PR; the contract is the gate-ids, not a vendor. **`DEVELOPMENT-STANDARDS.md` §14**.
- Conditional gates — each binds only when its trigger applies. The **CI conditional-gate set** is enumerated authoritatively in **`DEVELOPMENT-STANDARDS.md` §14** (the same five the Definition of Done in `CLAUDE.md` cites); the fuller set of conditional **process checkpoints** is the table in **`DEVELOPMENT-PROCESS.md` §7**. This card does not restate the membership — cite those sources.

## Security (non-negotiable)
Secrets in env / a managed store, never committed; never read, print, measure, copy or reuse a secret or a token pasted into the conversation, not even its length or prefix; a human sets secrets; if a token appears in the conversation, stop and ask the human to rotate it; the kit's own board and tracker scripts (`sh scripts/board.sh`) are the sanctioned credential reader; never run a secret-store or Keychain command yourself (conduct, not enforced) · validate input at boundaries · parameterized queries / ORM · least-privilege, short-lived tokens · PII consent + redaction + erasure · immutable audit trail · AI: prompt-injection defense + output validation + evals. Summary in **`CLAUDE.md`**; full bar in **`DEVELOPMENT-STANDARDS.md` §2**.

## The agent boundary
Agents act only within granted capabilities; the runtime guard blocks destructive and control-plane actions. **Agents propose; humans ratify** — never self-merge **unratified work**, never edit the control plane (guard, CI, CODEOWNERS, settings) without a human applying it. The guard sees only **local** git, **not** a server-side `gh pr merge --admin` — so for a **control-plane** change or any `gh pr merge --admin` bypass, prepare the green PR and **hand the human the merge command**; admin-merge only on an explicit "you merge it." For **Ordinary/Sensitive** changes after a recorded GO, the agent may execute the normal (non-`--admin`) merge — execution is delegable post-GO (see `docs/governance/promotion-contract.md`). Autonomy tiers + guard: **`DEVELOPMENT-PROCESS.md` §13**; solo-track ratification + the code-owner trap: **`docs/operations/review-lane.md`**.

> **What the guard does not stop.** The command guard stops honest mistakes. It does **not** stop a prompt-injected agent that reads a secret through an interpreter (`python -c`, `node -e`) or sends data out.
>
> **What does.** The OS sandbox's read-deny on secret paths and its egress allowlist, on by default: the `sandbox` block in the shipped `.claude/settings.json`. Egress also needs one day-one step at user level, done by a person: merge `"sandbox": {"network": {"strictAllowlist": true, "allowedDomains": [<the hosts you use>]}}` into `~/.claude/settings.json` (once per machine; it applies to every project on it). Until it is done, preflight, run from a terminal, says `FAIL egress: NOT ENFORCED and UNDECLARED [static]`. If preflight says `FAIL boundary: OFF and UNDECLARED`, or `WARN boundary: OFF [static] (opted out <date>, ...)` when the opt-out is declared, you do not have these controls. Check: `sparkwright doctor --boundary` reads the settings across every scope and writes nothing; it is a static read, not a proof of what the shell can do, and the live probe follows in a later release.
>
> **What stays open**, and is not contained: until the user-level step is done, egress to an unlisted host rests on a prompt, OPEN in any permission mode that approves prompts without a person (auto, bypass); a forge comment or gist made with the agent's own credential; an attacker-supplied token sent to an allowed host; the session environment (`env` and `printenv` read credentials no path deny covers); MCP and browser tools, which run outside the sandbox; deferred execution (a poisoned cache or hook that runs later). Contract and per-harness status: [`docs/operations/agent-boundary-contract.md`](docs/operations/agent-boundary-contract.md).

## Working with the human
- **Operator fluency** (adapt to the human's level): `docs/operations/operator-fluency.md`
- **Running more than one session?** Read `agents/orchestrator.agent.md` (the conductor): checkout custody, the push slot, GO relays, pinned review checkouts.

## Your stack
Concrete commands, libraries, and CI live in **`profiles/<stack>.md`** (chosen at Inception). New here? Start at **`START-HERE.md`**.

## Roster authority (this repo uses its own roster)

§1 states the rule; this is its scope and its ranking. The roster covers **all process work here** — design, plan, build, tdd, review, verification, debugging, evals, discovery, operating. **A foreign skill library in your environment does not govern this repo**: an injected "invoke my skill first" keystone (e.g. superpowers) sits at the *default/skill* tier and does **not** outrank this file.
**Precedence:** explicit user instruction → the kit's roster → any foreign default; an explicit user request for a foreign skill is always honored — **preference, not prohibition** (say so when you substitute a kit skill, so the user can choose).
