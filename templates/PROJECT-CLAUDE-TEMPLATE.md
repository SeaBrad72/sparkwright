# [Project Name] — Claude Project Guide

## 1. Entry contract — do this BEFORE any mutating action

**Five acts, every slice, before the first edit / commit / PR.** The skills in `skills/` govern process work here (index: `skills/using-skills/SKILL.md`).

1. **Derive the change class.** Put the changed paths in a file, one per line, and run `sh conformance/promotion-readiness.sh --class --changed <listing>`. Pass the listing file, never a path — a path argument gets its CONTENTS classified. `conformance/agent-boundary.sh --state` is not a classifier; without `--changed` it answers `NONE`. Never self-assert the class.
2. **Read the governing skill; name it in act 4 if the class asks** — `skills/<name>/SKILL.md`. Design before code, evidence before "done"; search `docs/governance/DECISIONS.md` for a ruling on this surface.
3. **Claim the row** this work satisfies on the board this project declared (backends: `docs/work-tracking/adapters.md`). No row, no build.
4. **Carry the Entry Declaration as commit trailers, proportional to the class** — Ordinary owes `Kit-Row` + `Kit-Class`; Sensitive/Control-plane owe `Kit-Stage` + `Kit-Skill` too (`Kit-Intent`, `Kit-Ceremony`, `Kit-Stop` optional). `conformance/loop-state.sh` checks the DERIVED class's required set on your PR's final commit: present once each, row on the board, class matching; a volunteered field is validated too. Enforced by default; `LOOP_STATE_MODE: observe` in `adopter-gates.yml` opts out.
5. **State the ceremony budget in one line**, derived from the class, so the owner can veto it in a sentence. Push board edits before you ask for review; seek approval only on the final diff.

> ⚠️ **The trailer block must be the LAST paragraph of the commit message, and contiguous.** A blank line inside it truncates it — git reads only the paragraph after the blank, so every `Kit-*` field above it is lost.

## The entry contract above is kit-owned

> **Do not edit, reword or renumber the section above.** It is the kit's entry contract, held **byte-identical in every adapter's declared `contextFile`** (`adapters/*/adapter.json`) so that every harness reads the same one. A generated project charter carries it because `claude-code` declares `CLAUDE.md` — and after Inception that name belongs to *this* file, not the kit's principles doc (which is renamed `ENGINEERING-PRINCIPLES.md`). The project's **own** numbered sections are a separate sequence and begin at *§1 Overview* below; the `(§N)` labels elsewhere in this file refer to that sequence.
>
> **This heading is what CLOSES the contract.** The locked region runs from the `##` above to the next `##` — this one — so everything below is yours to fill in, and anything inserted *above* it (even a blank line) breaks byte-equality. `conformance/agents-brief.sh` compares the region, not a marker: keeping the heading while appending to the section is exactly the case it exists to refuse.
>
> **Three placement rules go with it**, because comparing the section is not enough — each of these was measured green before it was closed:
> 1. §1 must be this document's **first** `## ` section. Only blank lines and the single `# ` title may precede it. Prose, a status line or a `### 0. …` heading above it renders *first*, and an entry contract an agent reads second is not an entry contract.
> 2. Nothing between §1 and this heading — the region runs to here.
> 3. **This heading must render visible text.** `## <!-- -->`, `## &nbsp;` and a zero-width-space heading are refused: they render as no heading at all, putting whatever follows flush under act 5.
>
> **Inception (Phase 0) is exempt from §1.** The five acts govern *loop* work — the slices that change a repo that already exists. `incept` is the one-time bootstrap that **creates** the repo and its control plane, so at that moment there is no board to claim a row on, no branch to carry trailers on, and no change class to derive. §1 binds from the **first feature branch** onward. See the "Inception exception" in `skills/design/SKILL.md` and `skills/build/SKILL.md`, and "Bootstrap order (incept-first)" in `DEVELOPMENT-PROCESS.md` §3.

---

> **Template.** Copy to a new project's `CLAUDE.md` during Inception (Phase 0, see `DEVELOPMENT-PROCESS.md` §3). Fill every `[...]`. Delete guidance blockquotes once filled. This file declares the project's identity and its per-project configuration of the global process/standards.

**Project:** [name]
**Intent owner:** [who owns the why]
**Status:** [Inception / Active / Maintenance / Paused]
**Created:** [date]
**Kit version adopted:** [vX.Y.Z — the Sparkwright release this project was incepted from; see the kit's `CHANGELOG.md`]

---

## Inherited standards (do not duplicate)

This project follows Sparkwright (the agentic SDLC kit). Read these (paths relative to wherever the kit lives in/by your repo), do not restate them here:

- **Principles + Definition of Done:** `CLAUDE.md`
- **Process (the flow):** `DEVELOPMENT-PROCESS.md`
- **Standards (the universal bar):** `DEVELOPMENT-STANDARDS.md`
- **Your stack profile (the concrete how):** `profiles/<your-stack>.md`

This file holds only what is **specific to this project**.

---

## 1. Overview

**Problem:** [what problem this solves, for whom]
**Vision / success metrics:** [how we know it's working]
**Scope boundaries:** [what's explicitly in / out]

## 2. Tech stack (ADR-000)

> Chosen at Inception via a spike; full rationale + alternatives in `docs/architecture/ADR-000-*.md`.

- **Language(s) / runtime:** [...]
- **Framework(s):** [...]
- **Data store:** [...]
- **Testing:** [...]
- **Deploy target / hosting:** [...]
- **Key libraries / services:** [...]

## 3. Per-project process configuration

> These are the knobs `DEVELOPMENT-PROCESS.md` says are set per project.

- **Backlog backend** (§6): [`BACKLOG.md` / GitHub / Jira / Azure DevOps / Linear / GitLab] — [link] (mapping: `docs/work-tracking/adapters.md`)
- **Stack profile** (§2): [typescript-node / go / python / rust / dotnet / java / data-engineering / …] — the kit profile this project was incepted with (`incept --stack`). It determines the scaffold, the emitted CI, and which `profiles/*` survived the export prune. Recorded because it was the **one inception input nothing wrote down**, and a kit update must prune a new export to the same shape to compare it against `kit-base` (`docs/operations/kit-base.md`).
- **CI platform** (§14): [github / gitlab] — the CI platform this project was incepted with (`incept --ci`); github wires `.github/workflows/ci.yml`, gitlab wires `.gitlab-ci.yml`. The contract is the gate-ids, not the platform (`docs/operations/ci-platforms.md`). Recorded because it is an inception **input**: a kit update replays incept over `kit-base` and must wire the *same* platform, or every CI file reads as a conflict (`docs/operations/kit-base.md`).
- **DB archetype** (§ archetype): [db-backed / no-db] — whether inception kept the reference DB archetype (default) or ran `incept --no-db`, which strips the `kit:db-backed` CI region, the `.db-backed` marker, the DB/Redis `.env.example` lines and `scripts/dr-drill.sh`. Recorded for the same reason as the CI platform: it is an inception **input**, and after the fact the tree can only be *guessed* at (`docs/operations/kit-base.md`).
- **Autonomy-tier defaults** (§12): [defaults, or deltas from the standard action→tier matrix]
  - e.g. `deploy to staging → L2 (autonomous behind smoke gate)`; everything else inherits defaults
- **SLO / error-budget posture** (§9): [soft track-and-guide / hard-gating] — [target SLOs if defined]
- **Data classification** (§privacy): [Public / Internal / Confidential / Restricted] — the highest tier this project handles. Confidential/Restricted ⇒ a privacy review (`docs/enterprise/data-governance.md`; verified by `conformance/readiness.sh privacy-ready`).
- **Operator fluency** (§onboarding): [Novice / Adjacent / Practitioner] — the human operator's enterprise-SDLC experience; the agent adapts its assistance accordingly (the "New to enterprise SDLC?" section of `START-HERE.md`; behaviour in `docs/operations/operator-fluency.md`).
- **Process mode** (§ ceremony): [lean / enterprise] — how much ceremony incept scaffolds + (S4) surfaces (ceremony only; solo-vs-team governance is the separate `enforce_admins` / `docs/operations/review-lane.md` axis). Does **not** change which controls are ENFORCED: every gate keys on its detected trigger (Dockerfile, `evals/`, data surface, classification), never on this field.
- **Governance** (§ solo/team): [solo / team] — solo = admin-merge (`enforce_admins:false`); team = non-author approval + second-reviewer SoD (`enforce_admins:true`). Enforced server-side (branch protection), not by this field; this records the fork chosen at Inception (`docs/operations/review-lane.md`).
- **Branch protection** (§branch-protection): [github-verified | attested: <host + mechanism>] — how `main` is protected. GitHub is **verified live** at Inception-Done (`conformance/inception-done.sh`); other hosts the kit can't yet query require this **attestation** (`docs/adoption/vc-hosts.md`). Fill deliberately — do not auto-stamp.
- **Target harness(es)** (§harness-neutrality): [claude-code] — the LLM/agent harness(es) this project runs; each is verified against the boundary contract at Inception (`docs/operations/harness-adapters.md`). Record *why* this harness fits in the Harness fit rationale field below.
- **Review routing / ownership** (§11): [who/which agent reviews what; CODEOWNERS link]
- **WIP limits:** [per-stage or global cap]
- **Environments** (§ "Environments & promotion"): Dev → QA → UAT → Prod — [per-tier deploy trigger]; [if collapsing tiers, name which you use + one-line reason]. Production promotion is human-gated.
- **Agentic** *(does this project run autonomous agents?)*: [yes / no] — **yes** ⇒ declare the agent-run trace posture in RUNBOOK §8 (`Agent-ops:`); see `docs/operations/agentic-ops.md`. Verified by `conformance/readiness.sh agentops-ready`.

### Harness neutrality

> The harness (§harness-neutrality) is a concretization axis — choose it by *fit*, not by "it's the default." Record the fit reason in the `#### Harness fit rationale` field below; `conformance/harness-decision-integrity.sh` rejects bias-appeal and requires a cited fit dimension. Only `claude-code` is a **verified** harness (the kit self-hosts on it); `codex` is **floor-verified** (the universal-layer floor exercised end-to-end in a cold field test — no native bonus); `gemini` / `cursor` are **experimental** — declared against the boundary contract, not exercised end-to-end (unproven), not "supported." Maturity cards + fit rubric: `docs/operations/harness-adapters.md`.

#### Harness fit rationale

[why this harness fits — cite a fit dimension: IDE / CI / MCP / multi-agent / native-hooks / offline / model-family …]

## 4. Roles (this project)

> Fill each function from `DEVELOPMENT-PROCESS.md` §2 with a human or agent. One may hold several; builder ≠ reviewer; humans ratify. For a role-oriented view (PO/BA · Designer · QA · DevOps/SRE mapped to these functions), see the **Personas** table in §2.

| Function | Who/what |
|----------|----------|
| Intent owner | [...] |
| Lead / integrator | [...] |
| Builder(s) | [...] |
| Reviewer(s) | [...] |
| On-call / operator | [...] |
| Security owner | [...] |

## 5. Quickstart

> Stack-appropriate, copy-paste-ready. Keep current (artifact-flow owner: building agent).

```bash
# install
[...]
# run locally
[...]
# test
[...]
# build
[...]
```

## 6. Project conventions & gotchas

> Only non-obvious, project-specific things. Patterns that generalize go to the pattern library, not here.

- [convention or gotcha]
- [convention or gotcha]

## 7. Key references

- **Repo:** [link]
- **Live / staging URLs:** [links]
- **Backlog / board:** [link]
- **Roadmap:** [link]
- **RUNBOOK:** `./RUNBOOK.md`

---

**Last Updated:** [date]
