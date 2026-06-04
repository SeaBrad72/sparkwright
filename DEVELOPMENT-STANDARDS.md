# Development Standards — Universal Quality Bar

**Purpose:** Define *what good looks like* — stack-neutral. These standards hold for **any** language or framework.

**Applies to:** All code, all projects, all contributors (human and AI).

**Status:** MANDATORY — exceptions require explicit approval.

**Relationship to other docs:** The **quality bar** companion to `DEVELOPMENT-PROCESS.md` (the flow) and `CLAUDE.md` (principles + Definition of Done).

> **Universal vs. profile.** This document states *principles and requirements* that don't depend on your stack. The *concrete how* — config files, code examples, exact commands, recommended libraries — lives in **`profiles/<your-stack>.md`**, chosen at Inception (`DEVELOPMENT-PROCESS.md` §3). Wherever you see **→ profile**, the specifics are there. If your profile and a universal requirement ever conflict, the universal requirement wins.

---

## 1. Core Principles

1. **Production-grade from day one** — shippable, scalable software regardless of size.
2. **Test-driven** — tests/evals written alongside (or before) implementation.
3. **Architecture before implementation** — design first, every time.
4. **Automated quality gates** — CI enforces; humans don't police what a machine can.
5. **Security, governance & guardrails are foundational** — from the first line.

---

## 2. Security, Governance & Guardrails

Apply to EVERY project, EVERY feature. Non-negotiable. **→ profile** for the concrete libraries/snippets in your stack.

### Secrets management
Never commit secrets (API keys, DB credentials, signing keys, passwords, tokens). Load from environment; fail fast if a required secret is missing. Keep real values in an untracked local env file; commit a `.env.example` with placeholders.

### Input validation & sanitization
Validate and sanitize **all** input at system boundaries against an explicit schema. Reject by default. Validate on **every** mutation path, not just create.

### Injection prevention
Use parameterized queries or an ORM. Never build queries/commands by string-concatenating untrusted input. Escape output for its sink (HTML, shell, SQL, etc.).

### Authentication & authorization
Hash passwords with a strong adaptive function. Issue least-privilege, short-expiry tokens with minimal claims. Authorize every protected action server-side. Audit every `!`/non-null assertion — guard optional values at runtime.

### PII & sensitive data
Never send PII to third-party services without consent. Redact in logs. Support deletion on request (right to erasure). Encrypt at rest and in transit.

### Cost management & governance
For paid/external services (incl. LLM/compute): rate-limit, track usage, and alert on budget burn. Treat agent/compute spend as a first-class cost.

### AI / agent security
- **Prompt-injection defense** — never let user input override system instructions; treat tool outputs as untrusted.
- **Output validation** — validate model output against a schema before acting; gate high-risk actions on confidence/criteria.
- **Capability boundaries** — agents act only within explicitly granted capabilities (see governance in `DEVELOPMENT-PROCESS.md` §13).

### Audit logging
Log all critical operations to an immutable trail: who, what, when, on which resource.

---

## 3. Observability

- **Structured logging** (machine-parseable in production; human-readable in dev). Every entry: timestamp, level, message, request/correlation ID, service.
- **Log levels** used correctly: ERROR (needs investigation) · WARN (handled but notable) · INFO (normal milestones) · DEBUG (off in prod).
- **Never log** secrets, tokens, full card numbers, or unneeded PII.
- **Error tracking** + **performance monitoring** wired for production. Alert on error spikes and health-check failures. **→ profile** for tools.

---

## 4. Resilience & Error Handling

- **Structured errors** with codes — not bare strings.
- **Idempotency** for retryable operations (idempotency keys).
- **Retry with exponential backoff** for transient external failures.
- **Circuit breakers** around unreliable dependencies.
- **Graceful degradation** — handle the unhappy path; never assume the happy path. **→ profile** for idioms.

---

## 5. Code Quality

- **Functions** small (target < 20 lines, extract beyond ~50) and single-purpose.
- **Early returns** over deep nesting.
- **Meaningful names** — no single-letter names except loop counters.
- **Comments** explain *why*, not *what*; keep them true or delete them.
- **No dead code, no committed debug output, no hardcoded values** that belong in config.
- **Money** in exact decimal types, never floating point.

---

## 6. Database & Performance

- **Indexes** on queried columns; **pagination** on list endpoints; **no N+1** queries.
- **Schema changes** via versioned migrations only — never manual production DDL. (Migration *discipline* — expand-contract, zero-downtime — is in `DEVELOPMENT-PROCESS.md` §10.)
- **Performance/SLA targets** (tune per project): API < 200ms p95 standard / < 500ms complex; page TTI < 3s on a mid-tier connection; no unindexed query > 100ms without justification.
- **Core Web Vitals** "Good" for user-facing web. **Load-test** before any public launch. **→ profile** for query tooling and perf budgets.

---

## 7. Testing Standards

Tests are the regression suite. **Mock at boundaries, not internals. Test behavior, not implementation.** Rate-limiters and the like skip in test mode.

**Coverage:** 80% line coverage is the floor; **100% on critical paths** (auth, payments/orders, money math, compensation, anything irreversible).

**Testing pyramid** (prioritize top-down; add each when its trigger arrives):

| Type | Purpose | When |
|------|---------|------|
| **Unit** | Pure logic, validators, helpers | Day 1 with code |
| **Integration** | Service + datastore (mocked or real) | With services |
| **API / contract** | HTTP status, auth guards, payload shapes | When routes exist |
| **E2E** | Critical user journeys | Phase 2+ |
| **Smoke** | Post-deploy sanity | When CI/CD exists |
| **Load / stress** | Behavior under pressure | Pre-launch |
| **Security** | Injection, auth bypass, token manipulation | Every auth/data boundary |
| **AI evals** | Model/prompt quality + regression + red-team | With any AI feature |

**→ profile** for the test runner, structure, and example tests in your stack.

### AI Evaluations (eval-driven development)
For any feature whose behavior depends on a model or prompt, **evals are the test suite** — the dev-time bar, not just runtime guards. A prompt is production logic, held to the same bar as code.

- **Task quality** — outputs scored against a curated dataset + rubric (exact-match, graded criteria, or LLM-as-judge with a pinned judge + rubric).
- **Regression** — the eval suite runs in CI on any prompt/model/parameter change; a drop below threshold **fails the build** (the Eval gate, `DEVELOPMENT-PROCESS.md` §7).
- **Safety / red-team** — adversarial prompts, jailbreaks, harmful-output checks before shipping.
- **Discipline** — eval set is versioned with the code and grows from production misses and retros; pin the judge; evals *complement* runtime guards; track eval scores as a quality metric (decline = tech debt). **→ profile** for the eval harness.

---

## 8. Accessibility (user-facing UI)

WCAG 2.1 AA. Semantic elements (never style a `div` as a control). Full keyboard operability with visible focus. Alt text and labelled inputs. 4.5:1 contrast (3:1 large text). Respect reduced-motion. Run an automated a11y audit before shipping.

---

## 9. API Design & Compatibility

- **Versioned** from day one (e.g. `/v1`).
- **Additive changes only** without a version bump; never remove/rename response fields silently.
- **Deprecation period** before removing anything consumers depend on.
- **Documented** — every endpoint: request/response shapes, error codes, examples.

---

## 10. Data Management & Backup

- **Automated backups** for production data; **verify restore** works at least once per project (a recurring-maintenance item).
- **Retention & DR** — define RPO/RTO in the RUNBOOK (sensible defaults: RPO < 24h, RTO < 4h).
- **Migrations** versioned and reversible.

---

## 11. Documentation Standards

- **Code comments** for non-obvious logic, workarounds, and security/performance decisions.
- **README** — overview, stack, prerequisites, install, dev, test, build, deploy, env vars.
- **RUNBOOK** — setup, deploy, troubleshoot, rollback, RPO/RTO, test accounts, known issues. Must enable a **cold resume** by another engineer or agent.
- **ADRs** (`docs/architecture/`) — record significant decisions with context, alternatives, consequences. **ADR-000 records the stack choice.**
- **CHANGELOG** — every user-facing change (Keep a Changelog + semver).

---

## 12. Definition of "Done"

The authoritative checklist is in **`CLAUDE.md`**. A feature is done only when code, tests/evals, CI/CD, docs (incl. RUNBOOK), review/merge, accessibility, and production checks all pass. If any box is unchecked, it isn't done.

---

**Remember:** this is the *universal* bar. Keep stack-specifics out of this file — they belong in `profiles/<stack>.md`. That separation is what lets any team adopt these standards without inheriting someone else's technology choices.
