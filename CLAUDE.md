# Engineering Principles & Definition of Done

**The authoritative guide for any team — human or agent — building with this kit.** It states the *principles* and the *Definition of Done*. The detailed flow lives in `DEVELOPMENT-PROCESS.md`; the quality bar in `DEVELOPMENT-STANDARDS.md` (+ your `profiles/<stack>.md`). When they overlap, **this file wins**.

**Status:** MANDATORY — exceptions require explicit approval.

---

## The document set

| Document | Role |
|----------|------|
| **`CLAUDE.md`** (this) | Principles + Definition of Done. Authoritative. |
| **`DEVELOPMENT-PROCESS.md`** | How work flows & improves — the agentic SDLC (Inception → loop → operate). |
| **`DEVELOPMENT-STANDARDS.md`** | The universal quality bar — stack-neutral. |
| **`profiles/<stack>.md`** | The concrete *how* for your chosen stack (config, examples, commands). Selected at Inception. |
| **`templates/`** | Project + intake/ops templates: `PROJECT-CLAUDE`, `BACKLOG`, `RUNBOOK`, `FEATURE-REQUEST`, `SPEC`. |
| **`START-HERE.md`** | Run this first — it walks you through Inception, including choosing your stack. |
| **`MAINTAINING.md`** | How the kit itself is built, versioned (`VERSION`, `CHANGELOG.md`), and contributed back to — the contract/reference/conformance convention. |
| **`conformance/`** | Executable checks/checklists proving a reference implementation satisfies its contract. |
| **`docs/enterprise/`** | Enterprise addendum — compliance crosswalk, secrets-at-scale, ratification RBAC, audit-evidence (maps the kit's controls to SOC 2 + ISO 27001:2022). |
| **`docs/`** (other) | `work-tracking/adapters.md` (backlog backends), `adoption/brownfield.md` (existing-repo adoption + `.claude/` hygiene). |

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

- **Secrets:** never commit keys/passwords/tokens. Env vars + a committed `.env.example`.
- **Input validation:** validate and sanitize all input at system boundaries (schema-validate).
- **Injection:** parameterized queries / ORM — never string-interpolate untrusted input.
- **AuthN/Z:** hash passwords (strong adaptive hash); least-privilege tokens, short expiry.
- **PII:** never send to third parties without consent; redact in logs; deletable on request.
- **Audit logging:** immutable trail for critical operations.
- **AI features:** runtime guards (output validation, prompt-injection defense) **and** dev-time evals (see standards).

> Concrete libraries/config for these live in your `profiles/<stack>.md`.

---

## Definition of "Done"

A feature is NOT done until ALL are true:

**Code** — implemented · self- and peer/agent-reviewed · no lint/type/compiler warnings.
**Tests** — unit + integration (+ e2e for critical flows) passing · 80%+ coverage (100% on critical paths) · edge/error cases covered · **AI features: evals pass and don't regress**.
**CI/CD** — pipeline green · build succeeds · the 7 required gates pass, incl. secret-scan and SBOM+provenance · no known high/critical vulnerabilities (per `DEVELOPMENT-STANDARDS.md` §14).
**Docs** — README, API docs, ADRs, and **RUNBOOK** updated · `.env.example` current · known issues/tech-debt captured · **project resumable cold by another engineer or agent**.
**Review & merge** — PR reviewed (builder ≠ sole reviewer) · approved · merged · branch deleted.
**Accessibility** — keyboard-navigable · screen-reader/contrast checks pass (for user-facing UI).
**Production** — deployed · smoke-tested · no errors in logs · rollback path ready · monitoring/alerting on critical paths.

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
