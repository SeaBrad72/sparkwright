# Kit Foundation / Meta-Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Agentic SDLC Kit into a versioned, self-iterating, drop-in template framework by landing the doc-only meta-layer: the contract/reference/conformance convention, kit-as-product versioning, the 15-Factor architecture contract, and licensing.

**Architecture:** Pure documentation increment on branch `feature/kit-foundation-meta-layer`. Six new files + four edits. No scripts, no CI YAML, no `.claude/` tooling (those are later slices in `docs/ROADMAP-KIT.md`). Each task creates/edits one file, verifies with a concrete consistency/conformance check, and commits. The kit stays internally consistent (`CLAUDE.md` authoritative on overlap; standards stay stack-neutral).

**Tech Stack:** Markdown; git; `grep`/`rg` for verification; Apache-2.0 license text. Spec: `docs/superpowers/specs/2026-06-05-kit-foundation-meta-layer-design.md`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `LICENSE` (new) | Apache-2.0 text + copyright notice |
| `VERSION` (new) | single line `1.0.0` — canonical version source |
| `CHANGELOG.md` (new) | kit's own history (Keep a Changelog + semver) |
| `MAINTAINING.md` (new) | the contract/reference/conformance convention; versioning, release, upstream-contribution |
| `conformance/README.md` (new) | explains the conformance pattern; indexes checks |
| `conformance/15-factor-checklist.md` (new) | the first conformance check; filled for the TS profile |
| `docs/ROADMAP-KIT.md` (new) | kit's own backlog: the 6 remaining slices, sequenced |
| `DEVELOPMENT-STANDARDS.md` (edit) | new §13 "15-Factor Architecture" + gap-factor requirements |
| `DEVELOPMENT-PROCESS.md` (edit) | §7 Review-gate row; §8 L3 upstream-contribution clause |
| `README.md` + `templates/PROJECT-CLAUDE-TEMPLATE.md` (edit) | version surfacing; "how the kit is built"; adopted-version field |

Build order: licensing/versioning first (foundational, standalone) → MAINTAINING (defines the convention) → conformance → standards → process → README/template → roadmap → final validation + PR.

**Precondition:** you are on branch `feature/kit-foundation-meta-layer` (already created; the spec commit lives there). Verify with `git branch --show-current`.

---

### Task 1: LICENSE (Apache-2.0)

**Files:**
- Create: `LICENSE`

- [ ] **Step 1: Write the LICENSE file**

Write the **verbatim Apache License 2.0** text (the standard ~11KB body from https://www.apache.org/licenses/LICENSE-2.0.txt) into `LICENSE`. At the end, complete the appendix boilerplate copyright line exactly as:

```
   Copyright 2026 Bradley James

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
```

> If this kit is owned by a company rather than an individual, set the copyright holder to the legal entity name instead of "Bradley James" before committing.

- [ ] **Step 2: Verify the file is the real license, not a stub**

Run: `wc -l LICENSE && grep -c "Apache License" LICENSE && grep "Copyright 2026" LICENSE`
Expected: ~200+ lines; at least 1 "Apache License" match; the copyright line prints.

- [ ] **Step 3: Commit**

```bash
git add LICENSE
git commit -m "chore: add Apache-2.0 LICENSE"
```

---

### Task 2: VERSION + CHANGELOG

**Files:**
- Create: `VERSION`
- Create: `CHANGELOG.md`

- [ ] **Step 1: Write VERSION**

Create `VERSION` with exactly one line and a trailing newline:

```
1.0.0
```

- [ ] **Step 2: Write CHANGELOG.md**

Create `CHANGELOG.md`:

```markdown
# Changelog

All notable changes to the Agentic SDLC Kit are recorded here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-06-05

First product release — the kit becomes a versioned, drop-in template framework.

### Added
- `LICENSE` (Apache-2.0) — the kit is now licensed for distribution.
- `VERSION` + this `CHANGELOG.md` — the kit is a semver'd product.
- `MAINTAINING.md` — the contract/reference/conformance convention, and how the kit is versioned, released, and contributed back to (the kit dogfoods its own loop).
- `conformance/` — the conformance-check pattern and `15-factor-checklist.md` (the first check, filled for the TypeScript/Node reference profile).
- `DEVELOPMENT-STANDARDS.md` §13 — **15-Factor Architecture**: a binding, conditional-by-project-type contract mapping all 15 factors to where the kit enforces them. Adds previously-uncovered factors: dependencies, disposability, backing services, dev/prod parity, statelessness, concurrency, and telemetry depth.
- `docs/ROADMAP-KIT.md` — the kit's own backlog: the six remaining contract/reference/conformance slices, sequenced.
- "Kit version adopted" field in `templates/PROJECT-CLAUDE-TEMPLATE.md` — projects record the kit version they run.

### Changed
- `DEVELOPMENT-PROCESS.md` §7 — the Review gate adds a conditional **15-Factor conformance** check; §8 — the L3 process retro now routes kit-level improvements upstream as a PR to the canonical kit.
- `README.md` — version surfaced; "How the kit is built" (the contract/reference/conformance convention) added; license declared.

[1.0.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v1.0.0
```

- [ ] **Step 3: Verify version consistency**

Run: `cat VERSION && grep -c "## \[1.0.0\]" CHANGELOG.md`
Expected: `1.0.0`; one matching changelog heading.

- [ ] **Step 4: Commit**

```bash
git add VERSION CHANGELOG.md
git commit -m "feat: version the kit as a product (1.0.0 + changelog)"
```

---

### Task 3: MAINTAINING.md (the convention + kit-as-product)

**Files:**
- Create: `MAINTAINING.md`

- [ ] **Step 1: Write MAINTAINING.md**

Create `MAINTAINING.md`:

```markdown
# Maintaining the Kit

How the Agentic SDLC Kit is **built, versioned, and evolved**. The kit is an internal platform product: it is released with semver, it has a `CHANGELOG`, and — critically — **it is built with the same loop it prescribes**. This file governs the kit itself; it is not copied into adopting projects.

---

## 1. The artifact convention: Contract · Reference · Conformance

Every capability the kit ships has three parts. This is the same "universal standard + profile" split the kit already uses, generalized to every artifact.

| Part | What it is | Where it lives | Binding? |
|------|-----------|----------------|----------|
| **Contract** | The stack-neutral requirement — *what must be true* | `DEVELOPMENT-STANDARDS.md` / `DEVELOPMENT-PROCESS.md` / `CLAUDE.md` | **Yes** — law |
| **Reference implementation** | A working, adaptable artifact — *one way to satisfy it* | `profiles/<stack>.md`, repo root, or `.claude/` | No — copy & adapt |
| **Conformance check** | An executable script or checklist — *proof the impl satisfies the contract* | `conformance/` | **Yes** — must pass |

**The rule for adopters:** you may rewrite any reference implementation freely — change the CI file, swap the stack, restructure the scaffold — **as long as the matching conformance check still passes.** The contract is law; the implementation is yours.

**Worked example (CI/CD):**
- *Contract* — `DEVELOPMENT-STANDARDS.md`: "CI MUST enforce lint, type-check, test+coverage≥80%, build, and secret-scan; `main` is protected; the builder is never the sole merger."
- *Reference* — `.github/workflows/ci.yml` in the TypeScript profile (a later slice), marked "copy & adapt to your stack."
- *Conformance* — `conformance/ci-gates.<ext>` (a later slice) that asserts each gate fires.

A team on Python deletes the Node workflow, writes their own, and stays conformant because the gates still fire.

---

## 2. Versioning

- The canonical version lives in `VERSION` (single line) and is mirrored by the top entry of `CHANGELOG.md`.
- **Semantic versioning** applied to *governance impact*, not lines of prose:
  - **MAJOR** — a change to a binding contract that existing adopters must act on (a new required gate, a removed guarantee).
  - **MINOR** — additive: a new reference implementation, a new profile, a new optional capability.
  - **PATCH** — clarifications, typo fixes, non-binding wording.
- Adopting projects record the version they took in their `CLAUDE.md` (`Kit version adopted: vX.Y.Z`), so drift is visible.

## 3. Releasing (platform team)

1. Land the change on a feature branch via PR (the kit's own loop — see §5).
2. Bump `VERSION`; add a dated `CHANGELOG.md` entry under the new version.
3. Merge to `main`; tag `vX.Y.Z`; the tag is the release.

## 4. Contributing back (the closed loop, applied to the kit)

The kit is improved by the teams using it. When a downstream team's **L3 process retro** (`DEVELOPMENT-PROCESS.md` §8) surfaces a kit-level improvement — a clearer standard, a better reference impl, a missing conformance check — it does **not** stop at the local copy:

1. The team opens a **PR against the canonical kit** describing the improvement and the retro that motivated it.
2. **Agents propose, humans ratify** — the kit's standing rule. A human maintainer reviews and accepts/declines.
3. Accepted changes ship in the next release and flow to every adopter via §2.

This is what makes the kit *self-iterating*: the MD files, scripts, and reference impls are all subject to the same retrospective-and-refactor loop the kit prescribes for product code. A retro that changes nothing is theater — here, kit-level learning lands upstream.

## 5. The kit dogfoods its own loop

The canonical kit repo runs the process in `DEVELOPMENT-PROCESS.md`: feature branches → PR → human ratification for any change to governing docs; its own `CHANGELOG`; its own backlog (`docs/ROADMAP-KIT.md`); its own L3 retros. If a rule is too heavy to follow on the kit itself, that is evidence to fix the rule.

---

**Last Updated:** 2026-06-05
```

- [ ] **Step 2: Verify the convention and contribution path are documented**

Run: `grep -c "Contract" MAINTAINING.md && grep -c "humans ratify" MAINTAINING.md && grep "Kit version adopted" MAINTAINING.md`
Expected: multiple "Contract" matches; at least 1 "humans ratify"; the adopted-version line prints.

- [ ] **Step 3: Commit**

```bash
git add MAINTAINING.md
git commit -m "docs: add MAINTAINING.md (contract/reference/conformance + kit-as-product)"
```

---

### Task 4: conformance/ — the pattern and the first check

**Files:**
- Create: `conformance/README.md`
- Create: `conformance/15-factor-checklist.md`

- [ ] **Step 1: Write conformance/README.md**

Create `conformance/README.md`:

```markdown
# Conformance Checks

A **conformance check** proves that a reference implementation still satisfies its binding **contract** (see `../MAINTAINING.md` §1). Checks are how the kit — and every project that adopts it — enforces the contracts instead of merely describing them.

## Two kinds of check

- **Checklist** — a human/agent-completed list with explicit evidence per item. Used when judgment is required (e.g. architecture conformance). Gates at a human checkpoint.
- **Script** — an automated assertion runnable in CI. Used when the check is mechanical (e.g. "the CI pipeline runs a secret-scan step"). Gates in the pipeline.

## Where checks run

- **In the kit's own CI** (a later slice) — the kit proves it satisfies its own contracts.
- **In an adopting project** — at the gate named by the contract (Review, Definition of Done, etc., per `../DEVELOPMENT-PROCESS.md` §7).

## Index

| Check | Type | Contract it proves | Gate |
|-------|------|--------------------|------|
| `15-factor-checklist.md` | checklist | `DEVELOPMENT-STANDARDS.md` §13 (15-Factor Architecture) | Review (conditional) |

> Future slices add: `ci-gates` (CI/CD), `agent-autonomy` (governance), `template-lint` (templates), `profile-completeness` (profiles). See `../docs/ROADMAP-KIT.md`.
```

- [ ] **Step 2: Write conformance/15-factor-checklist.md (template + worked example)**

Create `conformance/15-factor-checklist.md`:

```markdown
# Conformance Check — 15-Factor Architecture

Proves a service satisfies the applicable factors of `DEVELOPMENT-STANDARDS.md` §13. **Checklist-type**, run at the **Review gate** (`DEVELOPMENT-PROCESS.md` §7). Conditional: deployment-architecture factors are marked **N/A with a one-line reason** for non-service projects (CLI, batch, library).

## How to use
Copy this file into your project (or your review record). For each factor: mark **Applies? (Y / N+reason)** and give **Evidence** (where/how it's met). The reviewer signs off only when every applicable factor has evidence.

## Checklist (blank)

| # | Factor | Applies? | Evidence (where/how met) |
|---|--------|----------|--------------------------|
| 1 | Codebase — one app, version-controlled, one repo | | |
| 2 | API-first — contract defined before implementation | | |
| 3 | Dependencies — declared & isolated; lockfile committed; pinned for prod | | |
| 4 | Build, release, run — strictly separated stages | | |
| 5 | Config — in the environment; code/config/credentials separated | | |
| 6 | Logs — emitted as event streams, not managed files | | |
| 7 | Disposability — fast startup, graceful shutdown | | |
| 8 | Backing services — attached resources, swappable by config | | |
| 9 | Dev/prod parity — environments kept as similar as possible | | |
| 10 | Admin processes — one-off/admin tasks run as first-class processes | | |
| 11 | Port binding — service is self-contained, exports via a port | | |
| 12 | Stateless processes — no sticky local state between requests | | |
| 13 | Concurrency — scale out via the process model | | |
| 14 | Telemetry — metrics, traces, and health, not just logs | | |
| 15 | AuthN/Z — identity and least-privilege authorization enforced | | |

## Worked example — TypeScript/Node reference profile (a deployable HTTP service)

| # | Factor | Applies? | Evidence |
|---|--------|----------|----------|
| 1 | Codebase | Y | one Git repo per service; `main` protected |
| 2 | API-first | Y | OpenAPI/Zod-typed route contracts defined before handlers |
| 3 | Dependencies | Y | `package-lock.json` committed; exact versions for prod (profile §1) |
| 4 | Build/release/run | Y | `tsc`/`next build` → deploy → `start`; CI separates them (profile §3–4) |
| 5 | Config | Y | `process.env` + fail-fast; `.env.local` gitignored; `.env.example` committed (profile §5) |
| 6 | Logs | Y | pino/winston JSON to stdout (profile §7) |
| 7 | Disposability | Y | handle SIGTERM; drain in-flight; idempotent retries (standards §4) |
| 8 | Backing services | Y | Postgres via `DATABASE_URL`; swappable without code change (profile §8) |
| 9 | Dev/prod parity | Y | Docker/devcontainer mirrors prod; same Postgres engine |
| 10 | Admin processes | Y | Prisma `migrate deploy`; one-off scripts via `node` (profile §8) |
| 11 | Port binding | Y | Express/Next binds `process.env.PORT` |
| 12 | Stateless | Y | no in-memory session; state in Postgres/Redis |
| 13 | Concurrency | Y | horizontal scale on the host; stateless processes permit it |
| 14 | Telemetry | Y | Sentry errors + health endpoint; metrics/traces wired (standards §3) |
| 15 | AuthN/Z | Y | bcrypt + JWT least-privilege; server-side authz on protected routes (profile §5) |

> A CLI tool would mark 11, 12, 13 **N/A — not a long-running networked service**, and still satisfy 1–10, 14, 15.
```

- [ ] **Step 3: Verify the check is usable and indexed**

Run: `grep -c "| 1 |" conformance/15-factor-checklist.md && grep "15-factor-checklist" conformance/README.md`
Expected: 2 (blank + worked-example rows for factor 1); the index line prints.

- [ ] **Step 4: Commit**

```bash
git add conformance/
git commit -m "feat: add conformance pattern + 15-factor checklist (first check)"
```

---

### Task 5: DEVELOPMENT-STANDARDS.md — the 15-Factor section

**Files:**
- Modify: `DEVELOPMENT-STANDARDS.md` (insert new §13 before the closing "Remember" line)

- [ ] **Step 1: Insert the 15-Factor section**

Use an exact-string edit. Find this closing block near the end of `DEVELOPMENT-STANDARDS.md`:

```
## 12. Definition of "Done"

The authoritative checklist is in **`CLAUDE.md`**. A feature is done only when code, tests/evals, CI/CD, docs (incl. RUNBOOK), review/merge, accessibility, and production checks all pass. If any box is unchecked, it isn't done.

---

**Remember:** this is the *universal* bar. Keep stack-specifics out of this file — they belong in `profiles/<stack>.md`. That separation is what lets any team adopt these standards without inheriting someone else's technology choices.
```

Replace it with (note the new §13 inserted between §12 and the closing line):

```
## 12. Definition of "Done"

The authoritative checklist is in **`CLAUDE.md`**. A feature is done only when code, tests/evals, CI/CD, docs (incl. RUNBOOK), review/merge, accessibility, and production checks all pass. If any box is unchecked, it isn't done.

---

## 13. 15-Factor Architecture

The architectural contract for **deployable services**, after Hoffman's *Beyond the Twelve-Factor App* (the 12 Heroku factors plus API-first, Telemetry, and Auth). It is **binding but conditional**: factors that don't apply to a project type (a CLI, batch job, or library has no port binding or horizontal-concurrency story) are marked **N/A with a one-line reason** at the architecture review — the same conditional pattern as the threat-model and eval gates. Conformance is checked at the **Review gate** (`DEVELOPMENT-PROCESS.md` §7) via `conformance/15-factor-checklist.md`. Stack-specific *how* lives in **→ profile**.

| # | Factor | Requirement | Where enforced |
|---|--------|-------------|----------------|
| 1 | **Codebase** | One application, version-controlled, one repo; many deploys from one codebase. | git workflow |
| 2 | **API-first** | Define the API contract before implementing; design consumers and providers against it. | §9 |
| 3 | **Dependencies** | Declare and isolate all dependencies; commit a lockfile; pin exact versions for production. Never rely on system-wide packages. | **→ profile** |
| 4 | **Build, release, run** | Strictly separate the stages; a release is an immutable build + config; runs are reproducible. | CI/CD; process §10 |
| 5 | **Config** | Store config in the environment; keep code, config, and credentials separate. | §2 |
| 6 | **Logs** | Treat logs as event streams to stdout/stderr; never manage log files in-process. | §3 |
| 7 | **Disposability** | Fast startup and graceful shutdown; handle termination signals, drain in-flight work, make operations idempotent so a killed process loses nothing. | §4 |
| 8 | **Backing services** | Treat datastores, caches, queues, and third-party APIs as attached resources, swappable by config with no code change. | §2; **→ profile** |
| 9 | **Dev/prod parity** | Keep development, staging, and production as similar as possible (same backing-service types, small time/personnel/tooling gaps). | **→ profile** |
| 10 | **Admin processes** | Run one-off and admin tasks (migrations, backfills) as first-class, versioned processes in an identical environment — never manual production surgery. | §6 |
| 11 | **Port binding** | A service is self-contained and exports itself by binding to a port; no injection into a runtime web server. | **→ profile** |
| 12 | **Stateless processes** | Processes are stateless and share-nothing; any persistent state lives in a backing service, never in process memory or local disk between requests. | §6; §8-this |
| 13 | **Concurrency** | Scale out horizontally via the process model rather than only scaling a single process up. | **→ profile** |
| 14 | **Telemetry** | Emit metrics, distributed traces, and health signals — not just logs — so the running system is observable. | §3 |
| 15 | **Authentication & Authorization** | Treat identity and least-privilege authorization as architecture: authenticate every actor, authorize every protected action server-side. | §2 |

**New requirements this section adds to the universal bar** (previously uncovered, now binding for services):

- **Dependencies (Factor 3)** — a committed lockfile is mandatory; production builds pin exact versions; no reliance on globally-installed tools.
- **Disposability (Factor 7)** — services handle SIGTERM/SIGINT, stop accepting new work, drain in-flight requests within a bounded grace period, and rely on idempotency (§4) so an abrupt kill is safe.
- **Backing services (Factor 8)** — every datastore/cache/queue/external API is reached through configuration (a URL/credential in the environment), so it can be swapped (local ↔ managed) without code change.
- **Dev/prod parity (Factor 9)** — local and production use the same *types* of backing services; document any deliberate gap in the RUNBOOK.
- **Stateless processes (Factor 12)** — no sticky in-process or local-disk session state; horizontal scaling and disposability depend on this.
- **Concurrency (Factor 13)** — the scaling model is the process model; document expected concurrency and how the service scales out.
- **Telemetry depth (Factor 14)** — observability is metrics + traces + health, extending §3 beyond logs.

---

**Remember:** this is the *universal* bar. Keep stack-specifics out of this file — they belong in `profiles/<stack>.md`. That separation is what lets any team adopt these standards without inheriting someone else's technology choices.
```

- [ ] **Step 2: Verify the section landed and stays stack-neutral**

Run: `grep -n "## 13. 15-Factor Architecture" DEVELOPMENT-STANDARDS.md && grep -c "→ profile" DEVELOPMENT-STANDARDS.md`
Expected: the heading prints with a line number; `→ profile` count increased (the new section adds several).

Run a stack-neutrality check (should find NO stack-specific tool names in the new section):
`sed -n '/## 13. 15-Factor/,/Remember/p' DEVELOPMENT-STANDARDS.md | grep -Ei "prisma|express|next\.js|pino|sentry|npm|bcrypt" || echo "OK: section is stack-neutral"`
Expected: `OK: section is stack-neutral`.

- [ ] **Step 3: Commit**

```bash
git add DEVELOPMENT-STANDARDS.md
git commit -m "feat: add 15-Factor Architecture contract (standards §13)"
```

---

### Task 6: DEVELOPMENT-PROCESS.md — Review gate + L3 upstream contribution

**Files:**
- Modify: `DEVELOPMENT-PROCESS.md` (§7 gate table; §8 L3 retro row)

- [ ] **Step 1: Add the 15-Factor conformance row to the §7 gate table**

Find this exact row block in the §7 "Gates & Checkpoints" table:

```
| **Compliance gate** *(regulated domains)* | Does this meet the regulatory bar before release? | Security owner + human |
| **Acceptance** | Did we build the *right thing*? (intent/need) | Intent owner |
```

Replace with:

```
| **Compliance gate** *(regulated domains)* | Does this meet the regulatory bar before release? | Security owner + human |
| **15-Factor conformance** *(deployable services)* | Does the architecture satisfy the applicable 15 factors? (`conformance/15-factor-checklist.md`) | Reviewer + lead |
| **Acceptance** | Did we build the *right thing*? (intent/need) | Intent owner |
```

- [ ] **Step 2: Update the conditional-gates sentence in §7**

Find this exact sentence:

```
Review and Acceptance fail *differently* and are kept distinct. Threat-model, eval, and compliance gates are **conditional** — they apply to sensitive / AI / regulated work respectively, not every item (don't impose them where they optimize nothing).
```

Replace with:

```
Review and Acceptance fail *differently* and are kept distinct. Threat-model, eval, compliance, and 15-factor gates are **conditional** — they apply to sensitive / AI / regulated / deployable-service work respectively, not every item (don't impose them where they optimize nothing).
```

- [ ] **Step 3: Extend the L3 process-retro row in §8 to route kit improvements upstream**

Find this exact row in the §8 Retrospectives table:

```
| **L3 · Process retro** | Periodic / when the process bites | Human | Process improvements → `DEVELOPMENT-PROCESS.md` + `DEVELOPMENT-STANDARDS.md` |
```

Replace with:

```
| **L3 · Process retro** | Periodic / when the process bites | Human | Process improvements → `DEVELOPMENT-PROCESS.md` + `DEVELOPMENT-STANDARDS.md`; **kit-level improvements → PR upstream to the canonical kit** (`MAINTAINING.md` §4; humans ratify) |
```

- [ ] **Step 4: Verify all three edits landed**

Run: `grep -c "15-Factor conformance\|15-factor gates" DEVELOPMENT-PROCESS.md && grep -c "PR upstream to the canonical kit" DEVELOPMENT-PROCESS.md`
Expected: 2 (the gate row + the conditional sentence); 1 (the L3 clause).

- [ ] **Step 5: Commit**

```bash
git add DEVELOPMENT-PROCESS.md
git commit -m "feat: add 15-factor Review gate + L3 upstream-contribution to process"
```

---

### Task 7: README + PROJECT-CLAUDE-TEMPLATE — version surfacing

**Files:**
- Modify: `README.md`
- Modify: `templates/PROJECT-CLAUDE-TEMPLATE.md`

- [ ] **Step 1: Add version + "How the kit is built" to README, and declare the license**

In `README.md`, find the title line:

```
# Agentic SDLC Kit
```

Replace with:

```
# Agentic SDLC Kit

`v1.0.0` · Apache-2.0 · [CHANGELOG](CHANGELOG.md) · [how the kit is maintained](MAINTAINING.md)
```

Then find the "What's inside" table's first row and add `MAINTAINING.md`/`CHANGELOG.md` references by replacing this row:

```
| **`START-HERE.md`** | Run first — walks you through Inception, including choosing your stack. |
```

with:

```
| **`START-HERE.md`** | Run first — walks you through Inception, including choosing your stack. |
| **`MAINTAINING.md`** | How the kit is built, versioned, and contributed back to (the contract/reference/conformance convention). |
```

Then add a "How the kit is built" subsection. Find this existing section heading:

```
## The core ideas
```

Insert immediately **before** it:

```
## How the kit is built

Every capability ships as three parts (full detail in `MAINTAINING.md`):

- **Contract** — the binding, stack-neutral requirement (in the standards/process docs).
- **Reference implementation** — a working artifact you copy and adapt (in a profile or the repo). You own it.
- **Conformance check** — proof the implementation still satisfies the contract (in `conformance/`).

So the kit **dictates the contract and offers the implementation**: rewrite the reference freely as long as the conformance check still passes. The kit is itself a versioned product (`VERSION`, `CHANGELOG.md`) that is built with the very loop it prescribes — improvements found by adopters flow back upstream as PRs.

```

Finally, fix the license line. Find:

```
## License
[Choose a license before distributing.]
```

Replace with:

```
## License
Apache-2.0 — see [`LICENSE`](LICENSE).
```

- [ ] **Step 2: Add the adopted-version field to the project template**

In `templates/PROJECT-CLAUDE-TEMPLATE.md`, find the header block:

```
**Project:** [name]
**Intent owner:** [who owns the why]
**Status:** [Inception / Active / Maintenance / Paused]
**Created:** [date]
```

Replace with:

```
**Project:** [name]
**Intent owner:** [who owns the why]
**Status:** [Inception / Active / Maintenance / Paused]
**Created:** [date]
**Kit version adopted:** [vX.Y.Z — the Agentic SDLC Kit release this project was incepted from; see the kit's `CHANGELOG.md`]
```

- [ ] **Step 3: Verify the surfacing**

Run: `grep -c "v1.0.0" README.md && grep -c "How the kit is built" README.md && grep "Kit version adopted" templates/PROJECT-CLAUDE-TEMPLATE.md && grep -c "Choose a license" README.md`
Expected: at least 1 `v1.0.0`; 1 "How the kit is built"; the adopted-version line prints; `0` "Choose a license" (placeholder removed).

- [ ] **Step 4: Commit**

```bash
git add README.md templates/PROJECT-CLAUDE-TEMPLATE.md
git commit -m "docs: surface version, build convention, license; add adopted-version field"
```

---

### Task 8: docs/ROADMAP-KIT.md — the kit's own backlog

**Files:**
- Create: `docs/ROADMAP-KIT.md`

- [ ] **Step 1: Write the roadmap**

Create `docs/ROADMAP-KIT.md`:

```markdown
# Kit Roadmap — Remaining Slices

The kit's **own backlog** (dogfooding `DEVELOPMENT-PROCESS.md` §6). The Foundation increment (this release, `v1.0.0`) established the meta-layer. Each remaining slice ships as a **contract → reference → conformance** vertical (`MAINTAINING.md` §1), in priority order, each with its own spec → plan → build.

| Order | Slice | Contract (mostly written) | Reference implementation to build | Conformance check |
|-------|-------|---------------------------|-----------------------------------|-------------------|
| 1 | **CI/CD** | standards (CI gates) + process §10 | `.github/workflows/ci.yml`, `CODEOWNERS`, branch-protection notes (TS profile) | `conformance/ci-gates` — asserts each gate fires |
| 2 | **Agent governance layer** | process §13 (autonomy tiers) | `.claude/settings.json` allowlist, hooks blocking irreversible actions, reviewer/security subagents | `conformance/agent-autonomy` — a tier breach is blocked |
| 3 | **Inception bootstrap** | START-HERE 8-step gate | `init` script: scaffold structure, CI, stamped project `CLAUDE.md`/`RUNBOOK`/`BACKLOG` | Inception-Done checklist, automated |
| 4 | **Template fixes** | DoD + process §6 | rewrite `BACKLOG-TEMPLATE.md` to the flow-board model; add `RUNBOOK-TEMPLATE.md` | `conformance/template-lint` — placeholders filled, matches §6 |
| 5 | **Enterprise profiles** | `profiles/_TEMPLATE.md` | `profiles/python.md` + `profiles/java-spring.md` with real config files | `conformance/profile-completeness` — every section filled |
| 6 | **Enterprise addendum** | standards §2 (partial) | compliance-control mapping (SOC2/ISO), secrets-at-scale (Vault/KMS) patterns, RBAC for ratification | `conformance/audit-evidence` checklist |

## Notes
- Order matches the "CI first" priority: governance is only *enforced* once CI and the agent layer are wired.
- Slices 1–2 convert the kit from *described* governance to *enforced* governance — highest leverage.
- Re-prioritize at the kit's L2/L3 retros; this order is the default, not a commitment.

---

**Last Updated:** 2026-06-05
```

- [ ] **Step 2: Verify the roadmap covers all six out-of-scope slices**

Run: `grep -c "conformance/" docs/ROADMAP-KIT.md`
Expected: 6 or more (one conformance check named per slice).

- [ ] **Step 3: Commit**

```bash
git add docs/ROADMAP-KIT.md
git commit -m "docs: add kit roadmap (six remaining contract/reference/conformance slices)"
```

---

### Task 9: Final validation + PR

**Files:** none created; verification + PR only.

- [ ] **Step 1: Cross-reference integrity — every referenced file exists**

Run:
```bash
for f in LICENSE VERSION CHANGELOG.md MAINTAINING.md conformance/README.md conformance/15-factor-checklist.md docs/ROADMAP-KIT.md; do
  test -f "$f" && echo "OK $f" || echo "MISSING $f"
done
```
Expected: seven `OK` lines, no `MISSING`.

- [ ] **Step 2: No leftover placeholder for the license; version is consistent everywhere**

Run:
```bash
grep -rn "Choose a license" . --include=*.md && echo "FAIL: placeholder remains" || echo "OK: no license placeholder"
grep -rl "1.0.0" VERSION CHANGELOG.md README.md
```
Expected: `OK: no license placeholder`; all three files listed for `1.0.0`.

- [ ] **Step 3: Internal-consistency spot check — authoritative-doc rule intact**

Run: `grep -n "CLAUDE.md.*authoritative\|when they overlap" CLAUDE.md DEVELOPMENT-STANDARDS.md DEVELOPMENT-PROCESS.md | head`
Expected: the precedence statements still present (we did not contradict `CLAUDE.md`'s authority).

- [ ] **Step 4: Fill the spec's DoD — confirm the 15-factor worked example exists**

Run: `grep -c "Worked example — TypeScript/Node" conformance/15-factor-checklist.md`
Expected: 1 (the spec requires the checklist be filled for the TS reference profile).

- [ ] **Step 5: Push and open the PR**

```bash
git push -u origin feature/kit-foundation-meta-layer
gh pr create --title "Kit Foundation / meta-layer: contract-reference-conformance, kit-as-product, 15-Factor" --body "$(cat <<'EOF'
## Summary
Foundation increment turning the kit into a versioned, self-iterating, drop-in template framework. Doc-only.

- Contract/reference/conformance convention (`MAINTAINING.md`)
- Kit-as-product: `VERSION` 1.0.0, `CHANGELOG.md`, adopted-version marker, upstream-contribution path
- 15-Factor Architecture contract (`DEVELOPMENT-STANDARDS.md` §13) + conformance checklist; fills 7 previously-uncovered factors
- Review-gate + L3 upstream-contribution wiring (`DEVELOPMENT-PROCESS.md`)
- Apache-2.0 LICENSE; `docs/ROADMAP-KIT.md` sequencing the six remaining slices

Spec: `docs/superpowers/specs/2026-06-05-kit-foundation-meta-layer-design.md`

## Ratification
This edits governing docs → **human ratification required** before merge (the kit's own rule).
EOF
)"
```
Expected: branch pushed; PR URL printed.

- [ ] **Step 6: Stop for human ratification**

Do **not** merge. Per `DEVELOPMENT-PROCESS.md` §8 and `CLAUDE.md`, changes to governing docs are human-ratified. Hand the PR to the intent owner/lead for review.

---

## Self-Review (completed by plan author)

**Spec coverage:** every spec §2 touch-point maps to a task — LICENSE→T1, VERSION/CHANGELOG→T2, MAINTAINING→T3, conformance→T4, STANDARDS 15-Factor→T5, PROCESS §7/§8→T6, README/template→T7, ROADMAP→T8, validation/DoD→T9. Spec §3.3 gap-factors all appear in T5's "new requirements" list. Spec §4 validation items appear in T9.

**Placeholder scan:** no TBD/TODO; LICENSE uses the verbatim Apache text (explicitly, not a stub); the only `[...]` are intentional template blanks in `PROJECT-CLAUDE-TEMPLATE.md`.

**Type/name consistency:** `conformance/15-factor-checklist.md`, `MAINTAINING.md` §1/§4, and `DEVELOPMENT-STANDARDS.md` §13 are referred to by identical paths/anchors across tasks; the §13 placement (between §12 and the closing "Remember") is fixed and used consistently by T5's edit and T6's gate reference.
