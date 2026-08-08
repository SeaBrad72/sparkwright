# Engineering Principles & Definition of Done

## 1. Entry contract — do this BEFORE any mutating action

**Five acts, every slice, before the first edit / commit / PR.** Process work here is governed by this repo's own roster (`skills/` + `agents/`) — a foreign skill library in your environment does not govern it; use the kit's own `skills/<name>`, per the foreign→kit map in `skills/using-skills/SKILL.md`.

1. **Derive the change class** — `sh conformance/promotion-readiness.sh --class --changed <listing>`, where `<listing>` is a file *containing* the changed paths, one per line. **Passing a path directly classifies that file's CONTENTS, not its path** — always pass a listing. That classifier is guard-core-only and under-detects adapter-declared paths, so run the union-aware check too: `sh conformance/agent-boundary.sh --changed <listing> --ratified 0` (rc 1 = an unratified control-plane path). `--state` is **not** a classifier — it emits a ratification-state label, and with no `--changed` it answers `NONE` for every path on earth. Class is derived, never self-asserted.
2. **Read the governing kit skill, and name it** — `skills/<name>/SKILL.md`; index + foreign→kit map at `skills/using-skills/SKILL.md`. Design before code; evidence before "done" — **and search `docs/governance/DECISIONS.md` for a prior ruling on the surface you are about to change.**
3. **Claim the backlog row** this work satisfies — in whichever backend this project declared (`docs/work-tracking/adapters.md` maps them; the kit's own is `BACKLOG.md`). No row, no build; board it first.
4. **Carry the Entry Declaration** as commit trailers — `Kit-Row`, `Kit-Stage`, `Kit-Class`, `Kit-Skill`, plus advisory `Kit-Intent`, `Kit-Ceremony`, `Kit-Stop`. **Gate-checked on the PR head commit by `conformance/loop-state.sh`**: all four must be present, parse as git trailers and occur exactly once; the skill must **resolve** to a real stage-appropriate `skills/<name>/` and the class must **equal** `promotion-readiness.sh --class` (guard-core scope), while the row is only **matched** as a substring on the board — weaker than naming a row. The advisory three are **not** enforced. **Ceiling:** a merge-time attestation — **no ordering claim**, no proof the skill was read or followed, **and it does not survive the squash onto `main`: the trailers live only on the PR head commit** (measured — PR heads carry six `Kit-*` trailers each; the merged commits carry zero).
5. **State the ceremony budget in one line**, derived from the class, so the owner can veto it in a sentence instead of discovering it hours later. Sequence board/ledger edits into pushes that **precede** the review request — bind the row by branch name in the first push, and ask for approval only on the final diff (`DEVELOPMENT-PROCESS.md` §6 board-edit ordering).

> ⚠️ **The trailer block must be the LAST paragraph of the commit message, and contiguous.** A blank line before `Co-Authored-By:` silently drops every `Kit-*` field — git parses no trailers at all, while a grep-based check still passes the commit (measured).

## What this document is

**The authoritative guide for any team — human or agent — building with this kit.** It states the *principles* and the *Definition of Done*. The detailed flow lives in `DEVELOPMENT-PROCESS.md`; the quality bar in `DEVELOPMENT-STANDARDS.md` (+ your `profiles/<stack>.md`). When they overlap, **this file wins**.

**Status:** MANDATORY — exceptions require explicit approval.

## Roster authority (this repo uses its own roster)

§1 states the rule; this is its scope and its ranking. The roster covers **all process work here** — design, plan, build, tdd, review, verification, debugging, evals, discovery, operating. **A foreign skill library in your environment does not govern this repo**: an injected "invoke my skill first" keystone (e.g. superpowers) sits at the *default/skill* tier and does **not** outrank this file.
**Precedence:** explicit user instruction → the kit's roster → any foreign default; an explicit user request for a foreign skill is always honored — **preference, not prohibition** (say so when you substitute a kit skill, so the user can choose).

---

## The document set

| Document | Role |
|----------|------|
| **`CLAUDE.md`** (this) | Principles + Definition of Done. Authoritative. |
| **`DEVELOPMENT-PROCESS.md`** | How work flows & improves — the agentic SDLC (Inception → loop → operate). |
| **`DEVELOPMENT-STANDARDS.md`** | The universal quality bar — stack-neutral. |
| **`profiles/<stack>.md`** | The concrete *how* for your chosen stack (config, examples, commands). Selected at Inception. |
| **`templates/`** | Project + intake/ops templates: `PROJECT-CLAUDE`, `BACKLOG`, `RUNBOOK`, `FEATURE-REQUEST` (incl. an optional *Extended spec*), `TASK-CONTEXT-CONTRACT`, `EVAL-PLAN`, `THREAT-MODEL`, `AI-SYSTEM-CARD`, `AI-POLICY`, `AI-TRANSPARENCY-SIGNOFF`, `AI-ARTIFACT-LINEAGE`, `TEST-PLAN`, `UAT-SIGNOFF`, `A11Y-SIGNOFF`, `WAIVER-REGISTER`, `POSTMORTEM`, `BIA` (+ tracker-setup templates). |
| **`START-HERE.md`** | Run this first — it walks you through Inception, including choosing your stack. |
| **`MAINTAINING.md`** | How the kit itself is built, versioned (`VERSION`, `CHANGELOG.md`), and contributed back to — the contract/reference/conformance convention. |
| **`conformance/`** | Executable checks/checklists proving a reference implementation satisfies its contract. |
| **`docs/enterprise/`** | Enterprise addendum — compliance crosswalk (SOC 2 · ISO 27001:2022 · NIST SSDF · SLSA) + AI-governance crosswalk (NIST AI RMF · ISO 42001 · US state law · OWASP), secrets-at-scale, ratification RBAC, audit-evidence. |
| **`docs/`** (other) | `work-tracking/adapters.md` (backlog backends), `adoption/brownfield.md` (existing-repo adoption + `.claude/` hygiene), `adoption/vc-hosts.md` (bring-your-own git host), `adoption/DEPLOYMENT-ENVIRONMENT.md` (bring-your-own deploy target), `operations/` (live-system guidance: progressive delivery, resilience verification, DORA metrics, secrets-for-AI), `continuity/` (recovery/DR: backup-restore drill, BIA). |

New here? **Read `START-HERE.md`.**

---

## Core Principles

1. **Production-grade from day one** — no demos. Everything is shippable.
2. **Test-driven** — tests (and, for AI features, evals) are written with the code, not after. Quality is built in.
3. **Architecture before implementation** — design and discuss trade-offs before building.
4. **Automated quality gates** — if it isn't automated, it isn't enforced. CI on every push.
5. **Security & governance are foundational** — built into every line from the start, not bolted on.
6. **The loop closes** — production teaches the next iteration; learning routes back into an artifact (the "adjust" step).

## Working style (human ↔ agent)

- **Architecture first** — discuss approach before code.
- **Agents propose, humans ratify** — agents never silently change the standards/process that govern them.
- **Concise** — lead with the answer.
- **Full lifecycle, every time** — no skipped phases (see `DEVELOPMENT-PROCESS.md`).

---

## Security (non-negotiable)

> **Authoritative summary.** These are the non-negotiable rules in brief; the full bar (secrets-at-scale, cost governance, per-rule detail) is their expansion in `DEVELOPMENT-STANDARDS.md` §2. This summary and that expansion must agree.

- **Secrets:** never commit keys/passwords/tokens. Env vars + a committed `.env.example`. **Disclosure:** ship a `SECURITY.md` (coordinated-disclosure + a real contact); verified by `conformance/security-policy.sh`.
- **Input validation:** validate and sanitize all input at system boundaries (schema-validate).
- **Injection:** parameterized queries / ORM — never string-interpolate untrusted input.
- **AuthN/Z:** hash passwords (strong adaptive hash); least-privilege tokens, short expiry.
- **PII:** never send to third parties without consent; redact in logs; deletable on request.
- **Audit logging:** immutable trail for critical operations.
- **AI features:** runtime guards (output validation, prompt-injection defense) **and** dev-time evals (see standards).

> Concrete libraries/config for these live in your `profiles/<stack>.md`.

---

## Definition of "Ready"

The **entry gate** — an item is NOT ready to enter Build until ALL mandatory items are true. (The Definition of Done below is the **exit gate**: safe to ship.) Conditional items are quick applicability checks — mark **N/A** when they don't apply.

**Mandatory**
- **Acceptance criteria** — written and testable (how we'll know it's done).
- **INVEST-sliced** — a small, independent, vertical increment (not a phase or an epic).
- **Dependencies known** — blocking deps, data, and access identified.
- **Success metric / hypothesis** — a measurable statement of what "worked" means (§5 Discovery).

**Conditional flags** *(flag the obligation now so no downstream gate is a surprise)*
- **Threat-model / privacy review** *(if sensitive/regulated/personal data)* — flagged for the §7 security gate; threat model + a DPIA-lite when Confidential/Restricted (`templates/THREAT-MODEL-TEMPLATE.md`, `templates/PRIVACY-REVIEW-TEMPLATE.md`; verified by `conformance/privacy-ready.sh`).
- **UX/a11y obligation** *(if a user-facing surface)* — flagged; recorded later in the a11y sign-off (the Accessibility item below).
- **Eval criteria** *(if an AI feature)* — flagged for the §7 eval gate; the feature carries an AI System Card (`templates/AI-SYSTEM-CARD-TEMPLATE.md`).
- **Compliance obligation** *(if a regulated domain)* — flagged for the §7 compliance gate.

- **Change-class** *(always — derived, not self-asserted)* — Ordinary / Sensitive / Control-plane is **derived at promotion** (path-heuristics + the guard's `is_control_plane_path`), defaulting to the higher class when uncertain; Sensitive / Control-plane raise the downstream gate. See the promotion contract (`docs/governance/promotion-contract.md`).

If any **mandatory** box is unchecked, the item is **not Ready** — it does not enter Build.

---

## Definition of "Done"

A feature is NOT done until ALL are true:

**Code** — implemented · self- and peer/agent-reviewed · no lint/type/compiler warnings.
**Tests** — unit + integration (+ e2e for critical flows) passing · 80%+ coverage (100% on critical paths) · edge/error cases covered · **AI features: evals pass and don't regress**.
**CI/CD** — pipeline green · build succeeds · the 7 required gates pass, incl. secret-scan and SBOM+provenance · the conditional gates (the five in `DEVELOPMENT-STANDARDS.md` §14) pass where their trigger applies, else N/A-with-reason · no known high/critical vulnerabilities in production/runtime dependencies.
**Docs** — README, API docs, ADRs, and **RUNBOOK** updated · `.env.example` current · known issues/tech-debt captured · **project resumable cold by another engineer or agent**.
**Review & merge** — PR reviewed (builder ≠ sole reviewer; **builder ≠ ratifier**) · approved · merged · branch deleted. The merge is a recorded **GO/NO-GO** judgment (not a keystroke) against a **promotion-readiness** surfacing whose content is the DoD + acceptance criteria; on that recorded GO the **agent may actuate** the merge/tag (control-plane included) bound to the approved SHA — see the promotion contract (`docs/governance/promotion-contract.md`). The judgment is the control; the keystroke is not.
**Accessibility** — keyboard-navigable · screen-reader/contrast checks pass (for user-facing UI); recorded in an a11y sign-off (`templates/A11Y-SIGNOFF-TEMPLATE.md`).
**Production** — deployed · smoke-tested (post-deploy gate; `docs/operations/progressive-delivery.md`) · no errors in logs · rollback path ready · monitoring/alerting on critical paths · **DR proven for data services** (`conformance/dr-readiness.md`).

**If any box is unchecked, it isn't done.**

---

## Quality standards (universal)

- **Functions** small and single-purpose; prefer early returns over deep nesting.
- **Naming** meaningful; no throwaway names except loop counters.
- **Money** in exact decimal types, never floats.
- **DB** indexed, paginated, no N+1; schema changes via versioned migrations.
- **Errors** structured with codes; retry external calls with backoff; circuit-break unreliable deps.
- **Observability** structured logs, error tracking, performance monitoring.

> Language-specific expression of these is in your `profiles/<stack>.md`.

---

**Remember:** this kit is portable by design. Keep this file stack-neutral — anything stack-specific belongs in a profile, anything project-specific belongs in the project's own `CLAUDE.md`.
