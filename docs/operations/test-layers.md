# Test Layers — Convention, Gate, and Honest Ceiling

The kit gates four test-pyramid layers. This doc names them, explains what the `test-layers-ready` gate
proves (and does not prove), and orients the in-suite battery as the oracle E3's orchestrator consumes.
Stack-neutral; per-stack tool choices live in your profile. Pairs with `docs/operations/test-data-management.md`
and the E3 design (`docs/architecture/2026-06-22-e3-agentic-orchestration-design.md`).

## The four layers the kit gates

| Layer | When it runs | What it tests |
|-------|-------------|---------------|
| **Unit + coverage (≥80%)** | Every `npm test` / golden-path | Isolated functions and units; the `coverage-ratchet` gate enforces 80% floor with no regression |
| **Integration** | Every `npm test` / golden-path | A live service receiving real HTTP requests (in-suite, no Docker; `server.listen(0)` + `fetch`) |
| **E2E** | Every `npm test` / golden-path | Full user journey across the running server (in-suite; the same binary, not a separate deploy) |
| **Smoke** | Post-deploy (container boot) | Deployed-artifact sanity: can the container start and answer a health check? |

**Smoke ≠ e2e.** Smoke is a post-deploy artifact check — it proves the container boots and responds. E2E
is an in-suite journey correctness check — it proves the code does what it should. Both matter; neither
substitutes for the other.

**The in-suite battery (unit + integration + e2e, all run by `npm test`) is the oracle E3's orchestrator
runs.** It is fast (no Docker), deterministic, and available on every integrated branch — the right input
for an agentic fan-out that re-integrates through the gates.

## The `test-layers-ready` gate — what it checks

`conformance/test-layers-ready.sh` is a **conditional, three-state gate** that enforces layer presence
when a project has a service surface:

- **Applicability trigger:** the project has a service surface — a `Dockerfile`, a Compose file with a
  `services:` block, or an HTTP server entrypoint. **No service surface (CLI, library) → N/A;** e2e is
  not meaningful and the gate skip-passes.
- **Detection is stack-neutral, by convention** — it looks for a test path whose name contains `integration`
  or `e2e` (case-insensitive). This covers the common idioms across stacks:

  | Example path | Matched? |
  |---|---|
  | `test/integration.test.ts` | yes (`integration`) |
  | `test_integration.py` | yes (`integration`) |
  | `integration_test.go` | yes (`integration`) |
  | `e2e/journey.test.ts` | yes (`e2e`) |
  | `spec/e2e_spec.rb` | yes (`e2e`) |

- **Exit states:** `PASS` — service surface + both layers present. `FAIL` — service surface + a layer missing.
  `N/A` — no service surface.

## Honest ceiling — what the gate does NOT prove

State this plainly:

1. **Presence, not quality.** The gate verifies that a path matching the convention exists. It does not
   verify that the test at that path is meaningful, exercises the right paths, or asserts anything useful.
   A file named `integration.test.ts` containing a no-op satisfies the gate. Test quality is the concern
   of `docs/operations/test-quality.md` (mutation testing, property-based testing).

2. **A non-test file whose path matches also satisfies the gate.** A source file at
   `src/integration-helpers.ts` contains `integration` — the gate counts it. This is an accepted
   E1-thin scope limitation; tighter scoping (restricting to known test-file extensions) is deferred
   to E1-full.

3. **Behaviourally proven on ts-node only.** The integration and e2e layers are *executed* by the
   golden-path CI run on the ts-node reference. For all other stacks the gate is a presence check
   until those profiles are built out in E1-full and beyond. The gate is stack-neutral; the proof is
   ts-node-specific.

## What the green gate proves — and doesn't

A passing `test-layers-ready.sh` confirms:

- The project has a service surface and both integration + e2e layers are present by convention.
- OR the project has no service surface and e2e is correctly marked N/A.

It does **not** confirm that the layers contain meaningful tests, that the tests pass, or that coverage
on those layers meets any threshold. Those are addressed by the unit-coverage gate, `test-quality.md`,
and the reviewer gate respectively.

## See also

- `docs/operations/test-data-management.md` — safe non-prod data for tests that need a datastore
- `docs/architecture/2026-06-22-e3-agentic-orchestration-design.md` — E3 orchestration design (the
  in-suite battery is the oracle E3's orchestrator runs per integrated branch)
- `docs/operations/test-quality.md` — going beyond coverage: mutation testing and property-based testing
- `conformance/test-layers-ready.sh` — the executable gate (run `sh conformance/test-layers-ready.sh [project-dir]`)
