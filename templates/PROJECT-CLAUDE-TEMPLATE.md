# [Project Name] — Claude Project Guide

## 1. Entry contract — do this BEFORE any mutating action

**Five acts, every slice, before the first edit / commit / PR.** Process work here is governed by this repo's own roster (`skills/` + `agents/`) — a foreign skill library in your environment does not govern it; use the kit's own `skills/<name>`, per the foreign→kit map in `skills/using-skills/SKILL.md`.

1. **Derive the change class** — `sh conformance/promotion-readiness.sh --class --changed <listing>`, where `<listing>` is a file *containing* the changed paths, one per line. **Passing a path directly classifies that file's CONTENTS, not its path** — always pass a listing. That classifier covers guard-core **and** the adapter-declared union since S2; `sh conformance/agent-boundary.sh --changed <listing> --ratified 0` (rc 1 = an unratified control-plane path) remains the gate's own authority and is worth running as a cross-check. `--state` is **not** a classifier — it emits a ratification-state label, and with no `--changed` it answers `NONE` for every path on earth. Class is derived, never self-asserted.
2. **Read the governing kit skill, and name it** — `skills/<name>/SKILL.md`; index + foreign→kit map at `skills/using-skills/SKILL.md`. Design before code; evidence before "done" — **and search `docs/governance/DECISIONS.md` for a prior ruling on the surface you are about to change.**
3. **Claim the backlog row** this work satisfies — in whichever backend this project declared (`docs/work-tracking/adapters.md` maps them; the kit's own is `BACKLOG.md`). No row, no build; board it first.
4. **Carry the Entry Declaration** as commit trailers — `Kit-Row`, `Kit-Stage`, `Kit-Class`, `Kit-Skill`, plus advisory `Kit-Intent`, `Kit-Ceremony`, `Kit-Stop`. **Gate-checked on the PR head commit by `conformance/loop-state.sh`** — in the kit's own repository a **required, hard-blocking** context on the kit's own CI, bound live per the kit's `REQUIRED-CHECKS.md`; on a tree incepted from the kit it is the **observe-mode** check-run `incept` installs (`profiles/adopter-gates.yml`), posting `neutral` until the adopter flips `LOOP_STATE_MODE` to `enforce`; on GitLab it is wired manually (`docs/operations/gitlab-adoption.md`), and before Inception nothing is installed at all (the enforced / advisory / declared axis: `docs/positioning/sparkwright-overview.md`). **The gate:** all four must be present, parse as git trailers and occur exactly once; the skill must **resolve** to a real stage-appropriate `skills/<name>/` and the class must **equal** `promotion-readiness.sh --class` (guard-core and the adapter-declared union, when the union is derivable), while the row is only **matched** as a substring on the board — weaker than naming a row. The advisory three are **not** enforced. **Ceiling:** a merge-time attestation — **no ordering claim**, no proof the skill was read or followed, **and it does not survive the squash onto `main`: the trailers live only on the PR head commit** (measured — PR heads carry six `Kit-*` trailers each; the merged commits carry zero).
5. **State the ceremony budget in one line**, derived from the class, so the owner can veto it in a sentence instead of discovering it hours later. Sequence board/ledger edits into pushes that **precede** the review request — bind the row by branch name in the first push, and ask for approval only on the final diff (`DEVELOPMENT-PROCESS.md` §6 board-edit ordering).

> ⚠️ **The trailer block must be the LAST paragraph of the commit message, and contiguous.** A blank line before `Co-Authored-By:` silently drops every `Kit-*` field — git parses no trailers at all, while a grep-based check still passes the commit (measured).

## The entry contract above is kit-owned

> **Do not edit, reword or renumber the section above.** It is the kit's entry contract, held **byte-identical in every adapter's declared `contextFile`** (`adapters/*/adapter.json`) so that every harness reads the same one. A generated project charter carries it because `claude-code` declares `CLAUDE.md` — and after Inception that name belongs to *this* file, not the kit's principles doc (which is renamed `ENGINEERING-PRINCIPLES.md`). The project's **own** numbered sections are a separate sequence and begin at *§1 Overview* below; the `(§N)` labels elsewhere in this file refer to that sequence.
>
> **This heading is what CLOSES the contract.** The locked region runs from the `##` above to the next `##` — this one — so everything below is yours to fill in, and anything inserted *above* it (even a blank line) breaks byte-equality. `conformance/agents-brief.sh` compares the region, not a marker: keeping the heading while appending to the section is exactly the case it exists to refuse.
>
> **Three placement rules go with it**, because comparing the section is not enough — each of these was measured green before it was closed:
> 1. §1 must be this document's **first** `## ` section. Only blank lines and the single `# ` title may precede it. Prose, a status line or a `### 0. …` heading above it renders *first*, and an entry contract an agent reads second is not an entry contract.
> 2. Nothing between §1 and this heading — the region runs to here.
> 3. **This heading must render visible text.** `## <!-- -->`, `## &nbsp;` and a zero-width-space heading are refused: they render as no heading at all, putting whatever follows flush under act 5.

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
- **Data classification** (§privacy): [Public / Internal / Confidential / Restricted] — the highest tier this project handles. Confidential/Restricted ⇒ a privacy review (`docs/enterprise/data-governance.md`; verified by `conformance/privacy-ready.sh`).
- **Operator fluency** (§onboarding): [Novice / Adjacent / Practitioner] — the human operator's enterprise-SDLC experience; the agent adapts its assistance accordingly (`ONBOARDING.md`; behaviour in `docs/operations/operator-fluency.md`).
- **Process mode** (§ ceremony): [lean / enterprise] — how much ceremony incept scaffolds + (S4) surfaces (ceremony only; solo-vs-team governance is the separate `enforce_admins` / `docs/operations/review-lane.md` axis). Does **not** change which controls are ENFORCED: every gate keys on its detected trigger (Dockerfile, `evals/`, data surface, classification), never on this field.
- **Governance** (§ solo/team): [solo / team] — solo = admin-merge (`enforce_admins:false`); team = non-author approval + second-reviewer SoD (`enforce_admins:true`). Enforced server-side (branch protection), not by this field; this records the fork chosen at Inception (`docs/operations/review-lane.md`).
- **Branch protection** (§branch-protection): [github-verified | attested: <host + mechanism>] — how `main` is protected. GitHub is **verified live** at Inception-Done (`conformance/inception-done.sh`); other hosts the kit can't yet query require this **attestation** (`docs/adoption/vc-hosts.md`). Fill deliberately — do not auto-stamp.
- **Target harness(es)** (§harness-neutrality): [claude-code] — the LLM/agent harness(es) this project runs; each is verified against the boundary contract at Inception (`docs/operations/harness-adapters.md`). Record *why* this harness fits in the Harness fit rationale field below.
- **Review routing / ownership** (§11): [who/which agent reviews what; CODEOWNERS link]
- **WIP limits:** [per-stage or global cap]
- **Environments** (§ "Environments & promotion"): Dev → QA → UAT → Prod — [per-tier deploy trigger]; [if collapsing tiers, name which you use + one-line reason]. Production promotion is human-gated.
- **Agentic** *(does this project run autonomous agents?)*: [yes / no] — **yes** ⇒ declare the agent-run trace posture in RUNBOOK §8 (`Agent-ops:`); see `docs/operations/agentic-ops.md`. Verified by `conformance/agentops-ready.sh`.

### Harness neutrality

> The harness (§harness-neutrality) is a concretization axis — choose it by *fit*, not by "it's the default." Record the fit reason in the `#### Harness fit rationale` field below; `conformance/harness-decision-integrity.sh` rejects bias-appeal and requires a cited fit dimension. Only `claude-code` is a **verified** harness (the kit self-hosts on it); `gemini` / `codex` / `cursor` are **experimental** — declared against the boundary contract, not exercised end-to-end (unproven), not "supported." Maturity cards + fit rubric: `docs/operations/harness-adapters.md`.

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
