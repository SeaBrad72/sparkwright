# E1-thin · Design — integration + e2e test layers (the E3 oracle)

**Date:** 2026-06-26
**Status:** Approved (brainstorm) — ready for implementation plan
**Slice:** E1-thin — the first thin slice of the E1 "test battery references" epic. Ratified as step 1 of the post-panel-#4 order (`docs/architecture/2026-06-26-meta-control-4.md`): lead E3 with the thin inputs it consumes.
**Classification:** Mixed — scaffold tests + docs are non-control-plane (direct); the conformance gate + registration are control-plane → AMBER `apply.py` + dual review.

---

## 1. Goal & role

Add the **integration** and **e2e** test layers to the typescript-node reference profile (today: unit tests + a separate post-deploy container smoke gate), each *demonstrated* in the reference **and** *conditionally gated* for adopters. The in-suite battery (fast, no Docker) becomes the **oracle E3's orchestrator runs** (`npm test`) on every integrated branch to prove an orchestrated build is correct — the reason the panel sequenced this *before* E3.

This is the smallest slice that proves the pattern **layer → gate → scaffold demonstration**. The full E1 breadth (contract · security · a11y · property-based · load) fans out *after* E3, through E3.

---

## 2. Components

### 2a. `profiles/typescript-node/scaffold/test/integration.test.ts` *(non-control-plane — direct)*
Tests the **wiring** of the flag-controlled greeting path: starts the Express app in-process on an ephemeral port (`app.listen(0)`), issues a real HTTP request via global `fetch` (Node 24 — **zero new deps**, no `supertest`) to the greeting endpoint with the feature flag OFF then ON, asserts status + body reflect the flag. Distinct from the pure-logic unit tests (`flags.test.ts`/`health.test.ts`) — it exercises flag registry → route handler → HTTP response *integrated*. Tears down (`server.close()`).

### 2b. `profiles/typescript-node/scaffold/test/e2e.test.ts` *(non-control-plane — direct)*
A full **user journey** against an in-test server: liveness (`/healthz`) → the greeting flow → assert the complete path behaves end-to-end. **Distinct from smoke** (smoke = post-deploy infra sanity in golden-path; this = journey correctness, in-suite, runnable by E3 without Docker). A tiny local start/stop helper inline — no shared-helper extraction (that's E1-full's concern).

### 2c. `conformance/test-layers-ready.sh` *(control-plane → AMBER)* — **stack-neutral**
A conditional, three-state gate mirroring `conformance/test-data-ready.sh`:
- **Applicability trigger:** the project has a **service surface** (a `Dockerfile`, a compose service, or an HTTP server entrypoint). No service surface (CLI/library) → **N/A** (e2e not applicable).
- **Detection is stack-neutral, by broad convention** — NOT ts-file-naming. It looks for a test path whose name contains `integration` and one containing `e2e` (case-insensitive) under common test roots (`test/`, `tests/`, `spec/`, `e2e/`, plus stack idioms like `*_test.go` / `test_*.py`). So `test_integration.py`, `integration_test.go`, `e2e/`, `*.e2e.test.ts` all satisfy it.
- **PASS:** service surface + both layers present. **FAIL:** service surface + a layer missing. **N/A:** no service surface.
- Ships `--selftest` (fixtures: service+both→PASS, service+missing→FAIL, no-service→N/A).
- **Honest ceiling (documented in the script + an ops note):** it verifies the layer is *present by convention*, not that the tests are meaningful; and it is *behaviorally proven only on the ts-node reference* (golden-path runs those tests). For other stacks it is a presence gate until those profiles are built out (E1-full).

### 2d. Registration *(control-plane → AMBER)*
Register by mirroring `test-data-ready`: a `verify.sh` `check doc` line + a `ci.yml` `--selftest` step + a `conformance/README.md` index row. NOT in `claims.tsv`/`REQUIRED_IDS` (the precedent isn't either).

---

## 3. Stack-neutrality — gate universal, demonstration on the reference

This follows the kit's established **"proven-on-reference, provided-for-all"** pattern (same shape as E4 containment, E4c runtime-security):
- **The gate (`test-layers-ready.sh`) is stack-NEUTRAL** — applies to any adopter project on any stack; detection is convention-based, not language-specific.
- **The demonstration (2a/2b example tests) is ts-node only** — the kit's maturity-verified reference profile, the one golden-path actually boots and runs. Other profiles receive the demonstration as they are built out (E1-full, through E3).
- **Behaviorally proven** on ts-node (golden-path executes the tests); a **presence gate** elsewhere. Stated honestly; no claim that non-ts profiles have proven integration/e2e tests.

---

## 4. Deliberately NOT touched

- **`golden-path.yml`** — no change. Vitest auto-discovers `test/**/*.test.ts`, so the existing `npm test` step already runs the two new tests (the "wired"/proven half — verified, not modified).
- **The §14 "five conditional gates"** (a11y/load/eval/SAST/license) — untouched. Integration/e2e are test-*pyramid* layers already covered by the gate-3 test suite; `test-layers-ready` is a *completeness* check (own claim), **not** a new §14 gate — so `claim-gate-counts.sh` stays correct.
- **No `supertest`** — zero-dep (`app.listen(0)` + global `fetch`).

---

## 5. Scope / YAGNI

**In:** integration + e2e layers in the ts-node reference (zero-dep, in-suite), the stack-neutral conditional gate + registration, an ops note documenting the convention + honest ceiling.
**Out (deliberate):** the rest of the E1 battery (contract/security/a11y/property-based/load); demonstrations in non-ts profiles; a shared HTTP test helper; any `golden-path`/§14 change. All deferred to E1-full (post-E3).

---

## 6. Process

Mixed control-plane:
- **Direct (non-control-plane):** the two scaffold tests + the ops note.
- **AMBER (control-plane):** `conformance/test-layers-ready.sh` + claims.tsv + claims-registry + ci.yml — built in scratch, `apply.py`, dual review (reviewer + security-reviewer), **clone dry-run validated the right way** (incl. a *non-service-surface* fixture and a *non-ts* stack shape so the stack-neutral detection is proven, not just ts-proven) → Bradley applies/merges. Bundle the version bump as a patch at release (TBD at handoff).

---

## Honest-ceiling summary
- **Guarantees:** the ts-node reference demonstrates + behaviorally proves integration + e2e layers (golden-path runs them); a stack-neutral conditional gate requires the layers when a service surface exists, N/A otherwise; the in-suite battery is the runnable oracle E3 consumes.
- **Does not guarantee:** that an adopter's integration/e2e tests are *meaningful* (presence-by-convention only); that non-ts profiles have *proven* layers (presence gate until E1-full); contract/security/a11y/property/load coverage (out of scope).
