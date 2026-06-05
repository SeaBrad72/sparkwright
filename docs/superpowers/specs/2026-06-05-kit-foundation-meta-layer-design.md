# Design — Agentic SDLC Kit: Foundation / Meta-Layer Increment

**Date:** 2026-06-05
**Status:** Approved (brainstorming) — pending spec review
**Author:** Bradley James + agent
**Scope of this spec:** The first ("Foundation") increment of turning the Agentic SDLC Kit from a documentation kit into a drop-in, governed, self-iterating **template framework** for enterprise product / design / engineering teams.

---

## 1. Background & goal

The kit today is 12 Markdown files: excellent doctrine (process loop, universal standards, profiles, templates) but **all intent, little mechanism**. The goal is to make it something an enterprise team with *limited AI-engineering experience* can drop in and move forward with immediately, under a robust CI/CD + governance pipeline — while remaining a **template they own and evolve**, not a cage.

A prior assessment identified seven gap-fillers (CI, agent layer, bootstrap script, template fixes, enterprise profiles, enterprise addendum, LICENSE). Three framing decisions from the user reshape that list and add two deliverables:

### The three governing decisions

1. **Every deliverable = Contract + Reference + Conformance.**
   - **Contract** — binding, stack-neutral requirement (lives in the standards/process docs).
   - **Reference implementation** — a working, *adaptable* artifact (a file, script, or config) the team copies and reshapes. The kit *offers* it; the team *owns* it.
   - **Conformance check** — an executable script or checklist proving an implementation still satisfies the contract.
   - This resolves the dictate-vs-create tension permanently: the kit **dictates the contract** and **offers the implementation**. It is the same "universal standard + profile" split the kit already uses, generalized to every artifact.

2. **The kit is a versioned internal platform product that dogfoods its own loop.**
   - Semver + a kit-level `CHANGELOG`. Teams adopt a version and can pull updates.
   - A downstream team's **L3 process retro** that improves the kit raises a PR back to the canonical kit (agents propose, humans ratify — the kit's existing rule).
   - The kit is built with the same loop it prescribes.

3. **15-Factor architecture is a binding contract, conditional by project type.**
   - Hoffman's *Beyond the Twelve-Factor App* (12 Heroku factors + API-first, Telemetry, AuthN/Z).
   - A mapped section in the standards, with a conformance checklist gating at the Review/architecture gate. Factors that don't apply to a project type (e.g. port binding for a CLI) are explicitly marked **N/A with reason** — same conditional pattern as the existing threat-model / eval gates.

### The full program (7 work-streams, this spec covers only the Foundation)

The original seven gap-fillers plus two new deliverables (kit-as-product, 15-Factor) reorganize into **seven work-streams**. The Foundation **absorbs** three of them — LICENSE, kit-as-product, and 15-Factor — because they are doc-only and define the meta-layer. The remaining six are independent slices.

| # | Deliverable | Contract status | Main new work |
|---|---|---|---|
| **F** | **Foundation / meta-layer** (this spec) — absorbs LICENSE + kit-as-product + 15-Factor | establishes the convention | docs only |
| 1 | CI/CD | mostly written | reference `ci.yml` + CODEOWNERS + conformance |
| 2 | Agent layer | written (§13) | `.claude/` settings, hooks, subagents + conformance |
| 3 | Inception bootstrap | written (8-step gate) | `init` script + conformance |
| 4 | Templates | written (DoD/§6) | fix BACKLOG, add RUNBOOK + template-lint |
| 5 | Enterprise profiles | `_TEMPLATE.md` exists | Python + Java profiles w/ real configs |
| 6 | Enterprise addendum | partial | compliance/RBAC/secrets-at-scale + audit checklist |

Deliverables 1–6 are **out of scope for this spec** and are sequenced in `docs/ROADMAP-KIT.md` (produced by this increment). Each becomes its own spec → plan → build.

---

## 2. Foundation increment — scope

Doc-only. Ten touch-points (six new files, four edits):

| Action | File | Purpose |
|---|---|---|
| new | `LICENSE` | Apache-2.0 — unblock distribution |
| new | `CHANGELOG.md` | kit's own history (Keep a Changelog + semver) |
| new | `VERSION` | machine-readable version marker (`1.0.0`) |
| new | `MAINTAINING.md` | versioning, release, upstream-contribution; defines the contract/reference/conformance convention |
| new | `conformance/README.md` | explains the conformance pattern; holds the 15-factor checklist |
| new | `conformance/15-factor-checklist.md` | the first conformance check |
| new | `docs/ROADMAP-KIT.md` | the kit's own backlog — the 6 remaining slices, sequenced |
| edit | `DEVELOPMENT-STANDARDS.md` | new 15-Factor section + fill the gaps it exposes |
| edit | `DEVELOPMENT-PROCESS.md` | §7 Review gate: conditional 15-factor conformance; §8 L3: upstream contribution |
| edit | `README.md` + `templates/PROJECT-CLAUDE-TEMPLATE.md` | version + "how the kit is built"; "Kit version adopted" field |

**Non-goals (this increment):** no scripts, no CI YAML, no `.claude/` tooling, no new profiles. Those are later slices. This increment only establishes the meta-layer so every later slice inherits a settled pattern.

---

## 3. Detailed design

### 3.1 Contract / Reference / Conformance convention (`MAINTAINING.md`)

`MAINTAINING.md` is the new home for "how the kit is built and maintained." It documents:

- **The three-part artifact pattern** with a worked example (CI: contract in standards → `ci.yml` reference in profile → conformance script).
- **Where each part lives:** contracts in `DEVELOPMENT-STANDARDS.md` / `DEVELOPMENT-PROCESS.md` (stack-neutral); reference impls in `profiles/` or the repo root, marked "copy & adapt"; conformance checks in `conformance/`.
- **The rule:** a team may rewrite any reference implementation freely *as long as the conformance check still passes*. The contract is law; the implementation is theirs.

### 3.2 Kit-as-product mechanics

- **`VERSION`** — single line, `1.0.0`. The canonical version source.
- **`CHANGELOG.md`** — Keep a Changelog format; `1.0.0` entry describes the platformization. Every future slice adds an entry.
- **Adopted-version marker** — `PROJECT-CLAUDE-TEMPLATE.md` §2 gains: `Kit version adopted: vX.Y.Z`. Lets a project reason about drift and updates.
- **Upstream-contribution path** — `MAINTAINING.md` defines two flows:
  - *Release* — the platform team bumps `VERSION`, updates `CHANGELOG`, tags `vX.Y.Z`.
  - *Contribute-back* — a downstream L3 retro that finds a kit-level improvement opens a PR to canonical; humans ratify (reuses the kit's "agents propose, humans ratify" rule).
- **`DEVELOPMENT-PROCESS.md` §8** — the L3 row gains one clause: process-retro improvements to *kit-level* docs route upstream as a PR, not only to the local copy.

### 3.3 15-Factor Architecture section (`DEVELOPMENT-STANDARDS.md`)

New section. A mapping table + filled gaps. Current coverage audit:

| # | Factor | Today | Action |
|---|---|---|---|
| 1 | Codebase (one app/repo, version control) | implicit | name it; one-app-per-repo note |
| 2 | **API-first** *(new factor)* | §9 exists | reframe §9 to lead with API-first |
| 3 | Dependencies (lockfiles, pinning) | **missing from kit standards** | add bullet (was only in global CLAUDE.md) |
| 4 | Build, release, run (separated) | CI + process §10 | cross-reference |
| 5 | Config / credentials / code separation | §2 secrets | cross-reference + parity note |
| 6 | Logs as event streams | §3 | cross-reference |
| 7 | Disposability (graceful shutdown, fast start) | **missing** | add to §4 Resilience |
| 8 | Backing services as attached resources | **missing** | new bullet |
| 9 | Dev/prod parity | **missing** (in global CLAUDE only) | new bullet |
| 10 | Admin processes (one-off jobs, migrations) | §6 migrations | cross-reference |
| 11 | Port binding | profile | mark conditional; profile-level |
| 12 | Stateless processes | **missing** | new bullet |
| 13 | Concurrency (scale-out via process model) | **missing** | new bullet |
| 14 | **Telemetry** *(new factor)* | §3 logs-only | deepen to metrics + traces |
| 15 | **AuthN/Z** *(new factor)* | §2 | cross-reference |

**Seven factors have no home in the kit's stack-neutral standards today** (3, 7, 8, 9, 12, 13, and the metrics/traces depth of 14). This section adds them as binding requirements. Stack-specific *how* (e.g. graceful-shutdown code) stays in profiles, not here.

**Conditional-by-project-type:** the section states that deployment-architecture factors (11 port binding, 12 stateless, 13 concurrency, 7 disposability) are marked **N/A with a one-line reason** for non-service projects (CLI, batch, library). The architecture review records the determination.

### 3.4 Conformance pattern (`conformance/`)

- **`conformance/README.md`** — explains the pattern; lists checks (checklist-type and, later, script-type); states that checks run in the kit's own CI (a later slice) and at the relevant gate in adopting projects.
- **`conformance/15-factor-checklist.md`** — 15 rows, each: factor · applies? (Y/N + reason) · evidence/where-met. Used at the Review gate.

### 3.5 Review gate update (`DEVELOPMENT-PROCESS.md` §7)

Add one conditional gate row: **15-Factor conformance** — "Does the service's architecture satisfy the applicable factors?" Owner: reviewer + lead. Conditional (applies to deployable services; N/A-with-reason otherwise), consistent with threat-model/eval/compliance gates already in §7.

### 3.6 README + version surfacing

- `README.md` — add a version line (`v1.0.0`), a short "How the kit is built" subsection (the contract/reference/conformance convention, one paragraph, pointing to `MAINTAINING.md`), and replace the "[Choose a license...]" placeholder with "Apache-2.0 — see `LICENSE`."
- `templates/PROJECT-CLAUDE-TEMPLATE.md` — add the `Kit version adopted` field.

---

## 4. Validation (how we verify a doc-only increment)

- **Internal consistency:** no doc contradicts another; `CLAUDE.md` remains authoritative on overlap; the new 15-Factor section doesn't duplicate stack specifics (stays neutral).
- **Conformance self-test:** the 15-factor checklist is filled out *for the kit's reference profile* (typescript-node) as a worked example, proving the check is usable.
- **Cross-reference integrity:** every `→ profile` / section pointer added resolves to a real section.
- **No placeholders left** except intentional template `[...]` blanks in template files.
- **Provenance:** `CHANGELOG.md` `1.0.0` entry accurately lists what shipped.

---

## 5. Risks & mitigations

- **Doc bloat / losing the kit's tightness.** Mitigation: `MAINTAINING.md` and the 15-Factor section are net-new homes; we cross-reference rather than restate. Keep additions terse.
- **15-Factor over-application.** A team could treat all 15 as mandatory for a CLI. Mitigation: the conditional N/A-with-reason mechanism is explicit and demonstrated in the checklist.
- **Version drift between canonical and adopted copies.** Mitigation: the `Kit version adopted` marker + CHANGELOG make drift visible; full update-tooling is a later concern, not this increment.
- **Scope creep into scripts.** Mitigation: hard non-goal — this increment is doc-only; the conformance *scripts* arrive with their slices.

---

## 6. Out of scope (sequenced in `docs/ROADMAP-KIT.md`)

CI/CD reference + conformance · agent-governance layer (`.claude/`, hooks, subagents) · Inception bootstrap script · template fixes (BACKLOG flow-board, RUNBOOK) · enterprise profiles (Python, Java) · enterprise addendum (compliance mapping, secrets-at-scale, RBAC, audit evidence). Each is its own contract+reference+conformance slice, its own spec.

---

## 7. Definition of Done (this increment)

- All nine touch-points landed; internal-consistency and cross-reference checks pass.
- 15-Factor checklist filled for the TS reference profile as a worked example.
- `CHANGELOG` `1.0.0` entry written; `VERSION` = `1.0.0`.
- Committed on a feature branch; PR opened; human-ratified (this edits governing docs → human ratification required per the kit's own rule).
