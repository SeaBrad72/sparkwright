# Test Quality — Beyond Coverage

**Coverage measures *execution*, not *assertion strength*.** A suite can run 80% of your lines and assert almost nothing — and that failure mode is **especially common when tests are AI-generated**: an agent will happily produce tests that exercise code paths to hit the coverage gate without checking the result. This doc adds the two practices that verify tests are actually *good*. Stack-neutral; the per-stack tool is a profile choice. Pairs with `DEVELOPMENT-STANDARDS.md` §7.

## Mutation testing — does the suite catch bugs?
A mutation tester **injects small bugs** (mutants) into your code — flips a `>` to `>=`, a `+` to `-`, deletes a line — and reruns your tests. If a test **fails**, the mutant is "killed" (good — your tests caught the bug). If all tests still **pass**, the mutant "survived" (your tests don't actually verify that behavior). The **mutation score** = killed ÷ total.

- **It is the honest test-quality signal** — the kit's "green ≠ verified" applied to the test suite itself: coverage is the gameable green; mutation score is the verified.
- **The agentic reason it matters:** mutation testing is the reliable catch for an agent that gamed the coverage gate with assertion-light tests. A high coverage % + a low mutation score = tests that run but don't test.
- **Cost-aware cadence (recommended, not a universal gate):** mutation runs are slow (they rerun the suite per mutant). **Run it on critical-path modules** (auth, money, anything irreversible — §7) and/or **nightly / pre-release**, not on every PR. Gating every PR on a full mutation run would tax iteration — that's why the kit recommends it rather than requiring it.
- **Per-stack tools → your profile:** e.g. Stryker (JS/TS/C#/Scala), `mutmut` / `cosmic-ray` (Python), PITest (JVM), `cargo-mutants` (Rust), `go-mutesting` (Go).

## Property-based testing — generated inputs find what examples miss
Instead of a few hand-picked example cases, a property-based test states an **invariant** ("decode(encode(x)) == x for all x", "the result is never negative") and the framework **generates hundreds of inputs**, shrinking any failure to a minimal counterexample.

- **The agentic reason it matters:** it finds the edge cases a human *or an agent* didn't think to write — the unknown unknowns. Excellent for pure logic, parsers, serializers, money math, validators.
- **Use it for** high-value pure functions and boundaries; it complements (does not replace) example-based TDD.
- **Per-stack tools → your profile:** e.g. fast-check (JS/TS), Hypothesis (Python), jqwik (JVM), proptest / quickcheck (Rust), gopter / rapid (Go).

## What this does — and doesn't
Both are **recommended quality practices, not fail-closed gates** (mutation is too slow to gate every PR; "good enough" property coverage is a judgment call). The kit names the principle and ships the per-stack tools; the team decides the cadence and the critical-path scope. A green coverage gate remains necessary — it is just not *sufficient* evidence of test quality.
