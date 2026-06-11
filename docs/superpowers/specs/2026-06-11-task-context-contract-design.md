# Task Context Contract (TCC) — design

**Status:** design approved (brainstorm), pre-plan.
**Version target:** v2.45.0 — **MINOR** (additive template + tool-neutral process convention; no behaviour change, no new gate).
**Origin:** evaluation of the ICM paper (arXiv:2603.16021v2) — its declared per-stage "Inputs" contract and reference-vs-working distinction exposed a real gap: the kit governs its *outputs* with declared, verifiable contracts (spec → gates → conformance) but governs the *agent's context* tacitly (the controller→subagent dispatch is freeform judgment, unrecorded and un-auditable).

---

## Problem

When an agent step is dispatched (a plan Task → a subagent), three things are decided by tacit controller judgment and left unrecorded:
1. **Which governing clauses bind it** (which standards / profile / spec sections it must obey).
2. **What it may read vs. write** (its inputs to transform vs. its declared outputs).
3. **What it must NOT do** (scope/blast-radius prohibitions).

The backlog (`DEVELOPMENT-PROCESS.md` §6) governs **work items** (stories, across people/time — coordination, prioritization, acceptance). It cannot and should not govern **agent steps** (a 2–5-minute action inside a story) — that altitude would flood a tracker with micro-sub-tasks. So there is no artifact for *how an agent was bound while performing one piece of the work*. That gap is invisible when a human builds (the engineer "knows the standards") but becomes a real assurance gap when an agent builds at scale: you cannot prove, per action, which governance bound it, nor reproduce it.

## Goal

Apply the kit's own "declare the contract, make it inspectable" discipline one altitude up — to the build/dispatch layer — via a **Task Context Contract (TCC)**: a declared, four-sided envelope that binds a qualifying agent step and is verified by the same reviewers. Tool-neutral (the kit owns the contract; runtimes realize it their way), advisory in v1, proportional to risk.

## Non-goals (v1)

- **No self-improving loop.** The recurring-violation → promote-to-standing-constraint/lint/guard hook (ICM §6.3 fused with the kit's retros/ratchets) is a **fast-follow** — it needs TCCs in real use before its feedback design can be grounded.
- **No conformance drift-guard.** Advisory-first (the 11d "don't pre-build enforcement" lesson). A `conformance/tcc-defined.sh` may follow once the format proves out.
- **No superpowers dependency.** Verified: the kit's runtime deps are `jq`/`git`/`sh` (+ `gh` at Inception). The TCC is a kit-owned template + convention; superpowers is authoring-only.
- **No folder rename.** The cosmetic `docs/superpowers/` naming coupling is a separate, optional cleanup — out of scope here.

---

## The artifact: `templates/TASK-CONTEXT-CONTRACT-TEMPLATE.md`

A four-sided declared envelope for one agent build step, in the kit's guidance-blockquote template style. The substance (framing, proportionality, honesty) lives here — not in the line-budget-constrained core docs.

**Format (full form):**
```markdown
## Task Context Contract — <task name>
> Parent: <backlog item / spec / plan-task ref>

### Reads
- **Constraints (obey — cite the governing clause):**
  - DEVELOPMENT-STANDARDS.md §14 (gate ids) · profiles/<stack>.md §lint
- **Inputs (transform — the material):**
  - specs/<spec>.md §"<section>" · <prior task output → file>

### Writes (declared outputs — and nothing else)
- <exact path(s) this step may create/modify>

### Prohibitions (do NOT)
- touch control-plane files (.claude/ · .github/workflows · scripts/kit-guard)
- add a dependency · weaken an existing gate · <task-specific>
```

**Guidance blocks baked into the template:**
- **Constraints vs. material framing.** Constraints are *internalized as rules to obey*; Inputs are *material to transform*. A runtime presents them as two distinct labelled sections so the agent gets a clear signal of what binds vs. what to act on (ICM's reference-vs-working distinction).
- **Proportionality rule.** A **full** TCC is mandatory when a task touches a **governing surface** (control-plane / standards / CI / guard), is **security-sensitive**, OR is **multi-file** (writes > 1). Otherwise a **one-line default** suffices (cite the obvious constraint + the single output). Mirrors the kit's conditional-gate philosophy (a11y/load/eval bind only on trigger). The one-line form is shown in the template.
- **Precedence on conflict.** When constraints conflict, the kit's existing precedence applies: `CLAUDE.md` > `DEVELOPMENT-PROCESS.md` > `DEVELOPMENT-STANDARDS.md` > `profiles/<stack>.md`.
- **Honesty note.** A *present* TCC means the binding was **declared**, never that it was **obeyed** — only the spec-compliance + code-quality review verifies obedience. (The honesty invariant applied to this layer, so a TCC's presence never reads as false assurance.)
- **One filled worked example** (a real task — e.g. an `egress-policy.sh`-style step) so the format is concrete.

## Process wiring (tool-neutral) — `DEVELOPMENT-PROCESS.md`

Kept deliberately tiny (line budget: DEVELOPMENT-PROCESS.md at 462/470). The substance is in the template; the core doc only points and deepens.

- **§12 Multi-Agent Coordination** — add one bullet, *"Context-bound dispatch"*: every qualifying agent step (proportionality rule) carries a **Task Context Contract** (`templates/TASK-CONTEXT-CONTRACT-TEMPLATE.md`) — its Reads (constraints/inputs), Writes, and Prohibitions; **the reviewer receives the same contract**, so review verifies against it rather than generically. One bullet, ≤ 2 lines.
- **§13 Auditability** — extend the existing sentence (*"traceable: which agent, what, when, against which work item"*) → append *"…and bound by which governing clauses (its Task Context Contract)."* Zero net new lines (edit one line).
- **Tool-neutral framing** — folded into the §12 bullet (no separate paragraph): the TCC is a *format*; in Claude Code it is realized as the subagent dispatch prompt (constraints/material split) + the reviewer prompt; other runtimes express it their way. "One contract, many runtimes," as with the guard and CI.

If the §12 bullet pushes DEVELOPMENT-PROCESS.md over its 470-line budget, **raise the budget via the ratified `doc-budget.sh` mechanism — do NOT trim governance text to fit** (and surface it for security-owner ratification, since it is a governing-doc change).

## Where it's referenced

- `templates/` gains the new template; `START-HERE.md` / `CLAUDE.md` template tables and `DEVELOPMENT-PROCESS.md` §15 (Artifact Flow) get a one-line pointer where the other templates are listed, so the artifact is discoverable.

---

## Honesty & scope guardrails

- **Declared ≠ obeyed** (honesty note above).
- **Proportional, not universal** (proportionality rule) — avoids the process-theater the kit otherwise rejects.
- **Advisory before enforced** — convention + template + example in v1; conformance deferred.

## Testing / verification

- `check-links.sh`, `doc-budget.sh` green (the latter is the real constraint — keep §12/§13 edits within budget or raise it deliberately).
- A reviewer can read the template + the §12/§13 convention and produce a valid TCC for a sample task (the worked example demonstrates it).
- No conformance script in v1 (by decision).

## Governance

Feature branch → PR → **human ratification** (Bradley merges; agent never self-merges). The §12/§13 edits are governing-doc changes → **security-owner lens** (§13). No control-plane `cp` (templates/ and DEVELOPMENT-PROCESS.md are editable). Kit stays generic/anonymized ([[kit-anonymization]]).

## Deferred / follow-on

1. **Self-improving loop** (fast-follow): recurring TCC-constraint violations (surfaced at the §8 retro / §13 agent-quality metrics) → promote to a standing constraint, a lint rule, or a guard rule.
2. **`conformance/tcc-defined.sh`** drift-guard — only once the format has settled in real use.
3. **`docs/superpowers/` → neutral name** cleanup (anonymization nit) — separate slice.
