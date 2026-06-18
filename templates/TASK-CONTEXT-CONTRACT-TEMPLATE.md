# Task Context Contract (TCC) — TEMPLATE

> **Template.** The declared context envelope for **one agent build step** (a plan Task dispatched to an agent/subagent). It records what the step is bound by, may touch, and must not do — so the binding is auditable and reproducible, not tacit. Sits one altitude below the backlog work item (`DEVELOPMENT-PROCESS.md` §6): the backlog governs *work items*; the TCC governs *agent steps*. **Tool-neutral** — this is the format; a runtime realizes it (in Claude Code, as the subagent dispatch prompt + the reviewer prompt). See `DEVELOPMENT-PROCESS.md` §12 (Context-bound dispatch) and §13 (Auditability).

## When is a full TCC required? (proportionality)

A **full** TCC (all sections below) is mandatory when the step matches **any** of:
- **governing surface** — touches the control-plane (`.claude/` · `.github/workflows/` · `scripts/kit-guard` · `hooks/pre-push` · CODEOWNERS), the governing docs (`CLAUDE.md` / `DEVELOPMENT-PROCESS.md` / `DEVELOPMENT-STANDARDS.md`), a CI gate, or the guard;
- **security-sensitive** — auth, secrets, data boundaries, AI/prompt surfaces, anything flagged at the §7 security gate;
- **multi-file** — the step writes more than one file.

Otherwise a **one-line default** suffices (see the bottom of this template). Match the kit's conditional-gate philosophy: bind where the risk is, not everywhere.

## Full form

```markdown
## Task Context Contract — <task name>
> Parent: <backlog item id · spec ref · plan-task ref>

### Reads
- **Constraints (OBEY — cite the governing clause; do not paraphrase a rule, cite it):**
  - DEVELOPMENT-STANDARDS.md §14 (required CI gate ids)
  - profiles/<stack>.md §<section> (e.g. lint/test config)
  - <any pattern file the step must mirror>
- **Inputs (TRANSFORM — the material this step acts on):**
  - specs/<spec>.md §"<section>"
  - <prior task output → exact file path>

### Writes (declared outputs — and NOTHING else)
- <exact path(s) this step may create or modify>

### Budget (STOP at)
- **<token/$ ceiling>** — stop + escalate at the ceiling; do not silently exceed it. (A declared budget is a contract, not a mechanical stop — the platform spend-cap is the hard enforcement; `docs/operations/cost-governance.md`.)

### Prohibitions (do NOT)
- touch control-plane files unless this step's whole purpose is a ratified control-plane change
- add a runtime dependency
- weaken or delete an existing gate / conformance assertion
- <task-specific prohibition>
```

**Constraints vs. material — why the split.** *Constraints* are rules to **internalize and obey** ("write like this, satisfy these gates"); *Inputs* are material to **transform** ("turn this spec section into that script"). Present them as two distinct, labelled sections so the agent gets a clear signal of what binds versus what to act on.

**Precedence on conflict.** If two constraints conflict, the kit's order wins: `CLAUDE.md` > `DEVELOPMENT-PROCESS.md` > `DEVELOPMENT-STANDARDS.md` > `profiles/<stack>.md`.

**Honesty — declared ≠ obeyed.** A present TCC means the binding was **declared**, never that the step **obeyed** it. Only the two-stage review (spec-compliance, then code-quality) verifies obedience against this contract. A TCC on its own is not a green check.

**Reviewer binding.** The reviewer receives this same TCC and verifies against it: were the cited constraints satisfied, were only the declared outputs written, were the prohibitions respected? Review is contract-checked, not generic.

## Worked example (full form)

```markdown
## Task Context Contract — add a destructive-command rule to the guard
> Parent: BOARD-142 · specs/…-guard-hardening-design.md · plan Task 3

### Reads
- **Constraints (obey):**
  - DEVELOPMENT-PROCESS.md §13 (autonomy matrix — the gated/denied set)
  - kit POSIX-sh discipline: dash-clean, no `local`, no `[[ ]]`, no bashisms
  - conformance/agent-autonomy.sh (the corpus pattern to extend)
- **Inputs (transform):**
  - specs/…-guard-hardening-design.md §"new deny families"
  - the A-record enumerating the commands to deny

### Writes (declared outputs — and nothing else)
- .claude/hooks/guard-core.sh        (via control-plane cp — human-applied)
- conformance/agent-autonomy.sh      (new deny + over-block cases)

### Prohibitions (do NOT)
- weaken any existing deny rule or its conformance case
- self-apply the control-plane change (stage a /tmp candidate; human runs the cp)
- add a second deny-matrix implementation (single source of truth)
```

## One-line default (when a full TCC is not required)

> TCC: obey `<one clause>`; transform `<one input>`; write `<one file>`; no control-plane / deps. (full form N/A — single-file, non-governing, non-security task)
