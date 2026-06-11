# Task Context Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a kit-native, tool-neutral **Task Context Contract (TCC)** — a declared four-sided context envelope (Reads · Writes · Prohibitions) that binds a qualifying agent build step and is verified by the same reviewers.

**Architecture:** A new `templates/` artifact carries the substance (format + framing + proportionality + honesty + worked example). `DEVELOPMENT-PROCESS.md` §12/§13 get a tiny tool-neutral pointer + auditability extension; `CLAUDE.md` + §15 get discoverability pointers. Advisory in v1 — no conformance script, no behaviour change.

**Tech Stack:** Markdown only. No code, no new runtime deps.

**Spec:** `docs/superpowers/specs/2026-06-11-task-context-contract-design.md`

**Constraints:** `DEVELOPMENT-PROCESS.md` is at 462/470 lines (`doc-budget.sh`); keep §12/§13/§15 edits within the 8-line headroom or raise the budget deliberately (never trim governance text). The §12/§13 edits are governing-doc changes → security-owner lens before the PR.

---

## File structure

| File | Change | Responsibility |
|------|--------|----------------|
| `templates/TASK-CONTEXT-CONTRACT-TEMPLATE.md` | CREATE | the TCC format + all guidance (the substance) |
| `DEVELOPMENT-PROCESS.md` | MODIFY | §12 dispatch bullet · §13 auditability sentence · §15 artifact-flow row |
| `CLAUDE.md` | MODIFY | add `TASK-CONTEXT-CONTRACT` to the `templates/` inline list (line 17) |
| `VERSION` · `README.md` · `CHANGELOG.md` | MODIFY | release v2.45.0 |

Branch: `feature/task-context-contract` (created off main; spec committed on it).

---

## Task 1: The template — `templates/TASK-CONTEXT-CONTRACT-TEMPLATE.md`

**Files:** Create `templates/TASK-CONTEXT-CONTRACT-TEMPLATE.md`

- [ ] **Step 1: Create the file** with exactly this content:

````markdown
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
````

- [ ] **Step 2: Link check.**

Run: `sh conformance/check-links.sh 2>&1 | tail -1`
Expected: `OK: all relative Markdown links resolve`

- [ ] **Step 3: Commit.**

```bash
git add templates/TASK-CONTEXT-CONTRACT-TEMPLATE.md
git commit -m "feat(templates): Task Context Contract template (declared per-step context envelope; tool-neutral, proportional)"
```

---

## Task 2: Process wiring — `DEVELOPMENT-PROCESS.md` §12/§13/§15 + `CLAUDE.md`

**Files:** Modify `DEVELOPMENT-PROCESS.md`, `CLAUDE.md`

- [ ] **Step 1: §12 — add the "Context-bound dispatch" bullet.** In `DEVELOPMENT-PROCESS.md` §12 (Multi-Agent Coordination), immediately AFTER the `**Stakeholder visibility.**` bullet (the last bullet in that list), add:

```markdown
- **Context-bound dispatch.** Every qualifying agent step (proportionality rule in the template) carries a **Task Context Contract** (`templates/TASK-CONTEXT-CONTRACT-TEMPLATE.md`) — its Reads (constraints/inputs), Writes, and Prohibitions — and **the reviewer receives the same contract**, so review verifies against it rather than generically. Tool-neutral: the kit owns the contract; a runtime realizes it (Claude Code as the subagent dispatch + reviewer prompt; others their own way) — "one contract, many runtimes," as with the guard and CI.
```

- [ ] **Step 2: §13 — extend the Auditability sentence.** Find (in `### Auditability`):

```markdown
Every agent action is **traceable**: which agent, what, when, against which work item — via commit/PR attribution, work-item ownership, and L1 retro notes. No anonymous agent changes.
```

Replace with (appends one clause; no new line):

```markdown
Every agent action is **traceable**: which agent, what, when, against which work item, and bound by which governing clauses (its Task Context Contract) — via commit/PR attribution, work-item ownership, the TCC, and L1 retro notes. No anonymous agent changes.
```

- [ ] **Step 3: §15 — add the artifact-flow row.** In the §15 Artifact Flow table, add a row after the `Code + tests` row:

```markdown
| Task Context Contract | Build (dispatch) | per qualifying agent step | building agent / controller |
```

- [ ] **Step 4: `CLAUDE.md` — add to the templates list.** On line 17, in the `templates/` inline list, append `TASK-CONTEXT-CONTRACT` (extends the comma list; no new line):

Find:
```markdown
| **`templates/`** | Project + intake/ops templates: `PROJECT-CLAUDE`, `BACKLOG`, `RUNBOOK`, `FEATURE-REQUEST`, `SPEC`, `POSTMORTEM`, `BIA`. |
```
Replace:
```markdown
| **`templates/`** | Project + intake/ops templates: `PROJECT-CLAUDE`, `BACKLOG`, `RUNBOOK`, `FEATURE-REQUEST`, `SPEC`, `TASK-CONTEXT-CONTRACT`, `POSTMORTEM`, `BIA`. |
```

- [ ] **Step 5: Verify budget + links.**

Run: `sh conformance/doc-budget.sh; echo "exit=$?"`
Expected: PASS, exit 0. **If `DEVELOPMENT-PROCESS.md` exceeds 470 lines, STOP and report** — do not trim governance text; raising the budget is a ratified, security-owner-gated change, surfaced separately.

Run: `sh conformance/check-links.sh 2>&1 | tail -1`
Expected: `OK: all relative Markdown links resolve`

- [ ] **Step 6: Commit.**

```bash
git add DEVELOPMENT-PROCESS.md CLAUDE.md
git commit -m "docs(process): wire Task Context Contract into §12 dispatch + §13 auditability + §15 artifact flow (tool-neutral, advisory)"
```

---

## Task 3: Release (VERSION / CHANGELOG / badge)

**Files:** Modify `VERSION`, `README.md`, `CHANGELOG.md`

- [ ] **Step 1: `VERSION`** → `2.45.0`: `printf '2.45.0\n' > VERSION`.

- [ ] **Step 2: Badge sync.** `sh conformance/badge-version.sh --fix && sh conformance/badge-version.sh; echo "exit=$?"` → `PASS: README badge v2.45.0 matches VERSION 2.45.0`, exit 0.

- [ ] **Step 3: CHANGELOG** — insert above the current top entry (`## [2.44.0] - …`). No `[2.45.0]:` link-def (recent convention omits them):

```markdown
## [2.45.0] - 2026-06-11

Task Context Contract (TCC) — declared per-step context envelope. Applies the kit's "declare the contract, make it inspectable" discipline to the build/dispatch layer: a qualifying agent step now carries a declared Reads (constraints/inputs) · Writes · Prohibitions contract, verified by the same reviewers. **MINOR** — additive template + tool-neutral process convention; advisory (no new gate), no behaviour change.

### Added
- **`templates/TASK-CONTEXT-CONTRACT-TEMPLATE.md`** — the four-sided contract + constraints-vs-material framing, the proportionality rule (full TCC on governing-surface OR security OR multi-file; one-line default otherwise), conflict precedence, the honesty note (declared ≠ obeyed), reviewer-binding, and a worked example.
- **`DEVELOPMENT-PROCESS.md`** — §12 "Context-bound dispatch" convention (tool-neutral; reviewer receives the same contract), §13 Auditability extended to record which governing clauses bound each action, §15 artifact-flow row.

### Notes
- **Advisory in v1** — no conformance drift-guard yet (added only once the format proves out). The self-improving "recurring-violation → promote" loop is a deferred fast-follow.
- Origin: evaluation of the ICM paper (arXiv:2603.16021v2), whose declared per-stage inputs + reference-vs-working distinction surfaced the gap. No new runtime dependency; superpowers remains authoring-only.
```

- [ ] **Step 4: Verify + commit.**

Run: `cat VERSION && sh conformance/check-links.sh 2>&1 | tail -1`

```bash
git add VERSION README.md CHANGELOG.md
git commit -m "chore(release): 2.45.0 — Task Context Contract"
```

---

## Task 4: Final verify + independent security-owner review + PR

- [ ] **Step 1: Full verify.**

```sh
sh conformance/doc-budget.sh >/dev/null && echo "doc-budget OK"
sh conformance/check-links.sh >/dev/null && echo "links OK"
sh conformance/badge-version.sh >/dev/null && echo "badge OK"
sh conformance/verify.sh 2>&1 | tail -1
```
Expected: all OK; `verify.sh` RESULT: OK.

- [ ] **Step 2: Independent security-owner-lens review** (governing-doc change → §13). Dispatch a reviewer against `git diff main...HEAD`: confirm (a) the §12/§13 edits are additive and weaken no existing governance (auditability sentence still says everything it did, plus the TCC clause); (b) the TCC is honestly framed (declared ≠ obeyed; advisory, not a gate); (c) it introduces no superpowers/runtime dependency and stays tool-neutral; (d) proportionality is explicit (not universal — no process-theater); (e) `doc-budget`/`check-links` green. Fold cheap findings; carry the rest.

- [ ] **Step 3: Push + open PR** (Bradley merges — agent never self-merges).

```bash
git push -u origin feature/task-context-contract
gh pr create --base main --head feature/task-context-contract --title "Task Context Contract — declared per-step context envelope (v2.45.0)" --body "<summary: declared Reads/Writes/Prohibitions contract binding each qualifying agent step, verified by the same reviewers; tool-neutral, advisory, proportional; origin ICM paper; no superpowers/runtime dep; MINOR>"
```

- [ ] **Step 4: Report** the PR number + merge command (`gh pr merge <n> --squash --admin --delete-branch`) and the deferred fast-follows (self-improving loop; optional `tcc-defined.sh`; the `docs/superpowers/` rename nit).

---

## Verification (whole slice)

- `templates/TASK-CONTEXT-CONTRACT-TEMPLATE.md` exists; `check-links.sh` resolves it.
- `DEVELOPMENT-PROCESS.md` within the 470-line budget after the edits; `doc-budget.sh` PASS.
- §13 Auditability still asserts the original traceability *plus* the TCC clause (no governance removed).
- `verify.sh` RESULT: OK; badge = v2.45.0.
- No conformance script added (advisory v1, by decision). No superpowers/runtime dependency introduced.
- Governance: feature branch → PR → human ratification; security-owner lens on the §12/§13 governing-doc edits.
