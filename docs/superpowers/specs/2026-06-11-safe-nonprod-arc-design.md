# Safe Non-Prod — arc design (SNP-1 test-data · SNP-2 preview environments)

**Status:** design (brainstorm), pre-plan. Approved: a **two-slice arc**, **test-data first** (dependency order), **a light conditional readiness check each** (N/A-able, mirrors `observability-ready` / `dr-ready`).
**Origin:** the two deferred items from the feature-coverage analysis — the remaining paved-road gaps after the Responsible-AI arc.

---

## Problem

Two non-prod gaps, linked by a dependency:
- **Test data:** the kit says "never use prod data unsanitized" (env strategy) but gives **no *how*** — no synthetic/anonymized/seed guidance, no cross-stack pattern. A real gap for a privacy-sensitive adopter (PII / children's data → COPPA).
- **Preview environments:** the env model (`DEVELOPMENT-PROCESS.md` §9: Dev→QA→UAT→Prod) has **no per-PR ephemeral environment** — the modern paved-road that lets reviewers exercise a change running, not just read the diff (accelerates Review/Acceptance).

**Dependency:** a preview environment must be **seeded with safe (non-prod) data** — exactly what test-data management provides. So **SNP-1 underpins SNP-2**.

## The reframe (largely connective, not net-new)

This arc mostly *wires existing controls* into the non-prod lifecycle:
- Safe test data ← the COPPA-grade masking / data-minimization framing from the RAI arc.
- Preview-env credentials ← **scoped short-lived tokens + containment** (Slice 11c).
- Preview-env isolation / no-prod-data ← the env strategy + the new test-data patterns.

So the net-new is: two stack-neutral guidance docs, two light conditional checks, a STANDARDS principle, a PROCESS §9 contract addition, and per-stack tool references.

## Governing principles (binding)

1. **Governance as accelerant.** Preview environments *speed* review; safe test data *unblocks* realistic testing without privacy risk. No friction-for-its-own-sake.
2. **Conditional + proportional.** Test-data check binds only on a **data surface** (N/A for a pure-compute CLI). Preview-env check binds only on a **deploy surface** (N/A for a library). A tiny tool opts out with a one-line reason (the §9 tier-collapse precedent).
3. **US-aware privacy.** Non-prod data with PII / children's data → synthetic or masked (COPPA-grade); never raw prod data. Ties to the RAI data-minimization line + `compliance-crosswalk` privacy rows.
4. **Greenfield + brownfield drop-in.** Docs/templates/POSIX-sh checks; no runtime install.
5. **Honesty invariant.** A green check proves the approach is **declared/recorded**, never that the data is *actually* masked or the preview env is *actually* isolated/torn-down. Those are **Manual** rows (the team verifies no prod data leaks; the operator verifies teardown). Necessary, not sufficient.

---

## Slice SNP-1 — Cross-stack test-data management · (vMINOR)

### Components
- **`docs/operations/test-data-management.md`** (new, stack-neutral) — the patterns: the **data-classification → handling rule** (public → real ok; PII / children's / confidential → **synthetic or masked**, never raw prod); **synthetic generation** (per-stack tools → profiles); **anonymization / masking** (mask-on-extract if refreshing from prod — never copy raw prod down); **deterministic seeds** for reproducible tests; the "prod-data-in-non-prod" anti-pattern. Honest: the kit gives the pattern; the team produces the data.
- **`conformance/test-data-readiness.md`** (new) — **Auto** (a data-handling project records its test-data approach) vs **Manual** (the data is *actually* synthetic/masked · no prod data leaked into non-prod · children's data handled per COPPA).
- **`conformance/test-data-ready.sh`** (new) — conditional, fail-closed; **binds on a data surface** (reuse `dr-ready.sh`'s `has_data_surface`: DB URL in `.env.example`, a `migrations/`/`prisma`/`alembic` dir, or a DB service in compose). When bound → assert RUNBOOK records a **`Test data:`** approach (not the `[approach]` placeholder). N/A otherwise. `--selftest` (no-data → N/A; data + recorded → OK; data + placeholder → FAIL; data + missing → FAIL).
- **`templates/RUNBOOK-TEMPLATE.md`** — add a `Test data:` record line (in §2 Test/build), L1-clean.
- **Per-stack tooling** — a one-line synthetic-data tool note in the profiles (e.g. Faker / factory_boy / @faker-js / gofakeit), where natural.

### Wiring
- `conformance/verify.sh` (`check doc test-data-ready`); CI `--selftest` step (control-plane `cp`); `conformance/README.md` + `audit-evidence-checklist.md` rows; `DEVELOPMENT-STANDARDS.md` testing section principle + pointer; `compliance-crosswalk` privacy row (test data masked) if a natural home.

### Release
`VERSION` → 2.51.0; MINOR.

---

## Slice SNP-2 — Ephemeral / preview environments · (vMINOR)

### Components
- **`DEVELOPMENT-PROCESS.md` §9** — add **ephemeral preview environments** as a recommended practice for deployable services: per-PR create → reviewers exercise → **auto-teardown on merge/close**; isolated (namespace/db-per-PR); **seeded with safe test data (→ SNP-1)**; **scoped short-lived credentials (→ containment)**; **TTL / cost cap**; **never prod data or secrets**. Recommended, not required (tier-collapse precedent stands).
- **`docs/operations/preview-environments.md`** (new, stack-neutral) — the lifecycle + the **security guardrails** (no prod data → SNP-1; scoped creds → containment; TTL/auto-teardown → no forgotten attack surface; no secrets in preview; isolation per PR). The value: accelerates Review/Acceptance.
- **`conformance/preview-environments-readiness.md`** (new) — **Auto** (a deployable project records its preview-env approach) vs **Manual** (envs actually spin up per PR · actually tear down · actually isolated · no prod data).
- **`conformance/preview-env-ready.sh`** (new) — conditional on a **deploy surface** (mirror `observability-ready.sh` exactly: Dockerfile / deploy workflow). When bound → assert RUNBOOK records a **`Preview environments:`** approach (or explicit N/A-with-reason). N/A for non-deployed. `--selftest`.
- **`templates/RUNBOOK-TEMPLATE.md`** — add a `Preview environments:` record line (§4 Deploy area). **Profile reference** — a per-PR `environment:` preview pattern note in a profile.

### Wiring
- `verify.sh` (`check doc preview-env-ready`); CI `--selftest` step (`cp`); README + audit rows; PROCESS §9 contract; `docs/operations/` index if any.

### Release
`VERSION` → 2.52.0; MINOR.

---

## Cross-arc checks (both slices)

- New scripts: `dash -n` clean; `--selftest` green; **N/A at the kit root** (the kit is a framework — no data surface, no deploy surface); fresh RUNBOOK template → FAIL (no false PASS); L1-clean placeholder detection (keyed on literal token; comments token-free).
- Conditional + proportional: non-data / non-deployed projects → N/A (zero overhead).
- `check-links`, `doc-budget`, `verify.sh` green; bootstrap-into-temp unaffected.

## Governance

Each slice: feature branch → PR → **Bradley merges** (agent never self-merges). PROCESS/STANDARDS edits → security-owner lens. Each `ci.yml` step **folds into the slice PR** (apply on the branch before the PR — the convention set after the RAI-1 CI straggler). Generic/anonymized ([[kit-anonymization]]).

## Out of scope / deferred

- Running the infra (the kit declares + guides; the platform runs preview envs / produces data) — Org-owned.
- A specific preview-env tool (Vercel previews / Argo / Helm-per-PR / Heroku review apps) — named as references, not mandated.
- Generating the actual synthetic dataset — the team's job; the kit gives the pattern + per-stack tool.
