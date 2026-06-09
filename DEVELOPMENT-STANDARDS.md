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

### Secrets at scale
`.env` is the floor (local dev). For shared, staging, and production environments — and any regulated data — secrets belong in a **managed secret store** (HashiCorp Vault or a cloud KMS + secrets manager), never in env files baked into images or in committed state. Requirements: a central store with **least-privilege access policies**; **rotation** — prefer **short-lived / dynamic** secrets issued per-workload over long-lived static ones; **no plaintext secrets in state, logs, or images**; CI **fetches secrets at run time** (e.g. OIDC → cloud role, reusing the §14 push-only attestation pattern), never storing them in the workflow; **break-glass** access is time-boxed and audited. → `docs/enterprise/secrets-at-scale.md` for patterns and the per-stack client.

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

## 13. 15-Factor Architecture

The architectural contract for **deployable services**, after Hoffman's *Beyond the Twelve-Factor App* (the 12 Heroku factors plus API-first, Telemetry, and Auth). It is **binding but conditional**: factors that don't apply to a project type (a CLI, batch job, or library has no port binding or horizontal-concurrency story) are marked **N/A with a one-line reason** at the architecture review — the same conditional pattern as the threat-model and eval gates. Conformance is checked at the **Review gate** (`DEVELOPMENT-PROCESS.md` §7) via `conformance/15-factor-checklist.md`. Stack-specific *how* lives in **→ profile**. For a containerized service, **the image is the unit of dev/prod parity** — local dev (devcontainer / compose) builds from the same Dockerfile that ships to production.

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
| 9 | **Dev/prod parity** | Keep all tiers (Dev/QA/UAT/Prod) as similar as possible (same backing-service types, small time/personnel/tooling gaps). | **→ profile** |
| 10 | **Admin processes** | Run one-off and admin tasks (migrations, backfills) as first-class, versioned processes in an identical environment — never manual production surgery. | §6 |
| 11 | **Port binding** | A service is self-contained and exports itself by binding to a port; no injection into a runtime web server. | **→ profile** |
| 12 | **Stateless processes** | Processes are stateless and share-nothing; any persistent state lives in a backing service, never in process memory or local disk between requests. | §6; backing services (Factor 8) |
| 13 | **Concurrency** | Scale out horizontally via the process model rather than only scaling a single process up. | **→ profile** |
| 14 | **Telemetry** | Emit metrics, distributed traces, and health signals — not just logs — so the running system is observable. | §3 |
| 15 | **Authentication & Authorization (AuthN/Z)** | Treat identity and least-privilege authorization as architecture: authenticate every actor, authorize every protected action server-side. | §2 |

**New requirements this section adds to the universal bar** (previously uncovered, now binding for services):

- **Dependencies (Factor 3)** — a committed lockfile is mandatory; production builds pin exact versions; no reliance on globally-installed tools.
- **Disposability (Factor 7)** — services handle SIGTERM/SIGINT, stop accepting new work, drain in-flight requests within a bounded grace period, and rely on idempotency (§4) so an abrupt kill is safe.
- **Backing services (Factor 8)** — every datastore/cache/queue/external API is reached through configuration (a URL/credential in the environment), so it can be swapped (local ↔ managed) without code change.
- **Dev/prod parity (Factor 9)** — all tiers (Dev/QA/UAT/Prod) use the same *types* of backing services; document any deliberate gap in the RUNBOOK. For a containerized service, the **image** is the unit of parity — local dev (devcontainer/compose) builds from the same Dockerfile that ships (§14 container image supply-chain).
- **Stateless processes (Factor 12)** — no sticky in-process or local-disk session state; horizontal scaling and disposability depend on this.
- **Concurrency (Factor 13)** — the scaling model is the process model; document expected concurrency and how the service scales out.
- **Telemetry depth (Factor 14)** — observability is metrics + traces + health, extending §3 beyond logs.

---

## 14. CI/CD Pipeline

Automated quality gates are the contract's teeth: *if it isn't automated, it isn't enforced.* Every project's CI **must run, on every pull request, seven required gates** before code can merge. Tool choices are stack-specific — **→ profile**.

| # | Gate | Requirement |
|---|------|-------------|
| 1 | **Lint** | Style/correctness linter passes with zero errors. |
| 2 | **Type-check** | Static type analysis passes (where the stack has types). |
| 3 | **Test + coverage** | Test suite passes; line coverage ≥ 80% (100% on critical paths, per §7). |
| 4 | **Build** | A production build/compile succeeds and is reproducible. |
| 5 | **Secret scan** | The diff/history is scanned for committed secrets; any finding fails the build. |
| 6 | **Dependency scan** | Dependencies are scanned for known vulnerabilities; a high/critical finding fails the build. |
| 7 | **Supply-chain integrity** | An **SBOM** is generated for the build, and **build provenance** is attested for released artifacts. |

**Branch protection (governance):** `main` is protected — no direct pushes; a green CI run is required to merge; and the **builder is never the sole merger** of their own change (an independent review is required, per `DEVELOPMENT-PROCESS.md` §2 and §12). This is where the autonomy boundary of `DEVELOPMENT-PROCESS.md` §13 is enforced mechanically.

**Provenance scope:** the SBOM and dependency/secret scans run on every PR; **build-provenance attestation attaches to a published build artifact** (there is nothing to attest on a change that produces no artifact). The pipeline owns provenance; the profile's reference shows where it attaches.

**Conformance:** a project's pipeline is verified by `conformance/ci-gates.sh <workflow>`, which asserts every required gate is declared (the Definition-of-Done "CI/CD" check, `CLAUDE.md`).

**CI security hardening (required posture, not a gate).** The provenance/attestation step requires `id-token: write`; grant it via a **separate job that runs only on push-to-main**, keeping the main gate job at `contents: read` so PR-triggered steps cannot mint an OIDC token a poisoned dependency could exfiltrate. Pin third-party actions to a full commit SHA in production. The cloud OIDC trust policy **MUST** restrict `sub` to the main-branch ref (`refs/heads/main`), never `pull_request`. The profile reference pipelines model this two-job split.

> This raises the supply-chain posture (gates 6–7) to the baseline for **all** projects — see `DEVELOPMENT-PROCESS.md` §10.

**Container image supply-chain (conditional).** *Applies only when a project ships a deployable service container image* — a library, CLI, batch job, or IaC module marks this **N/A with a one-line reason** (the same conditional pattern as the 15-factor gate, §13). When it applies, the image **MUST**:
- be built **multi-stage** (build tooling never ships in the runtime image);
- run as a **non-root** user;
- use a **minimal base** (distroless or slim);
- declare a **healthcheck**; and
- on release, carry **(a) an image SBOM** (CycloneDX, generated by scanning the built image — e.g. Syft) **and (b) a build-provenance attestation bound to the image digest** (`actions/attest-build-provenance` with `subject-name` + `subject-digest`, and `push-to-registry: true`), not merely the language artifact or a mutable tag.

The default registry is **GHCR**; the push-only `provenance` job additionally holds `packages: write` (still scoped to push-to-main, the PR job stays `contents: read`). This **does not** add a new universally-required gate — it strengthens the standard *for the service case*. Verified by `conformance/container-supply-chain.sh`, which is conditional on a `Dockerfile` being present.

**Promotion & production gate.** Changes promote Dev → QA → UAT → Prod (see `DEVELOPMENT-PROCESS.md` "Environments & promotion"); each promotion requires a green pipeline, and **production promotion requires human approval** via a protected deploy environment. Destructive operations against production are prohibited from automated agents (enforced by the `DEVELOPMENT-PROCESS.md` §13 guard); the human side is owned by platform controls.

**Reference — production deploy is human-gated by a protected environment** (inert here; adopters wire it):
```yaml
deploy-prod:
  needs: ci
  if: github.event_name == 'push' && github.ref == 'refs/heads/main'
  environment: production   # set required reviewers on this environment in repo settings
  runs-on: ubuntu-latest
  steps:
    - run: echo "promote the verified artifact to production"
```
Required reviewers on the `production` environment make the promotion human-gated at the platform level, complementing the `DEVELOPMENT-PROCESS.md` §13 agent guard.

---

**Remember:** this is the *universal* bar. Keep stack-specifics out of this file — they belong in `profiles/<stack>.md`. That separation is what lets any team adopt these standards without inheriting someone else's technology choices.
