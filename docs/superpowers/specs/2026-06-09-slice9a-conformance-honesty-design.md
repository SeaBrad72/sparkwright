# Slice 9a — Conformance Honesty: "green ≠ verified" (design)

**Date:** 2026-06-09 · **Arc:** Slice 9 (Honest Assurance & Adoption Reach), Tier 0 · **Version target:** MINOR → **v2.26.0**
**Input:** the independent review's convergent finding #1 ([2026-06-09-independent-multiagent-review.md](../reviews/2026-06-09-independent-multiagent-review.md)) — conformance checks go green on *documentation/declaration* rather than *tested controls*, and `branch-protection.sh` passes when it cannot verify.

## Problem

A reader (or auditor) seeing an all-green conformance dashboard infers "the controls work." Two honesty gaps undermine that:

1. **`branch-protection.sh` silently exits 0 ("Informational") when it cannot verify** (no `gh`, no GitHub context). In an aggregate this is indistinguishable from a pass — yet `main` may be entirely unprotected. The kit's own CI does not even run it. A check that conflates "couldn't verify" with "verified OK" is exactly the false assurance the kit's anti-false-assurance principle condemns.
2. **No aggregate honesty surface.** Each readiness script is honest *in its own header and final NOTE* ("verifies documentation only, NOT that rollback was tested"), but that disclosure lives where a dashboard reader never looks. Nothing at the aggregate level states which green means *a working control* vs *a document exists*.

The individual readiness scripts (`deployable-ready`, `dr-ready`, `resilience-ready`) are already honest at the unit level — this slice does **not** rewrite them; it surfaces the distinction at the aggregate and fixes the one check that genuinely lies (silent pass).

## Design

### 1. Three-state `branch-protection.sh` (kill the silent pass)

Replace the binary OK / Informational-exit-0 with three outcomes:
- **exit 0** — verified protected (PR reviews + status checks required).
- **exit 1** — verified *not* protected, or a required setting missing (real fail).
- **exit 2** — **could not verify** (no `gh`, unauthenticated, or no GitHub remote). Prints `UNVERIFIED: …` — never the word OK/pass.

**Parse method (HTTP-status-based, not body-substring):** the decision keys on the **gh exit code / HTTP status**, never on grepping the response body for substrings. Only a genuine HTTP 200 (gh exit 0) reaches the required-settings check; a non-200 error body that merely *names* `required_pull_request_reviews`/`required_status_checks` can therefore never read as protected. 404 "Branch not protected" → FAIL; any other non-200 (403 admin-rights, 401, rate-limit, empty/transient) → UNVERIFIED. A `BP_STUB_RC`/`BP_STUB_BODY` seam makes every branch deterministically self-testable (incl. the spoof case). *(Added per the 9a security review — substring-grepping a discarded-status body was a residual false-PASS vector.)*

**CI escalation:** when `${CI:-}` is non-empty (GitHub Actions sets `CI=true`), an unverifiable result escalates to **exit 1 (FAIL)** — in CI the check *must* be runnable; a silent skip there is the dangerous case. A `--require` flag forces the same escalation anywhere (for adopters who wire it into a gate).

Add `--selftest` (mirrors the other conformance scripts): exercises the three states with stubbed conditions (force-no-gh path → exit 2 locally; `CI=1` + force-no-gh → exit 1), printing `branch-protection --selftest: OK`. Deterministic, no network.

POSIX sh, dash-clean. Update the header comment to describe the three-state contract.

### 2. `conformance/verify.sh` — executable aggregate honesty surface

A new runner that executes the kit-applicable conformance checks and prints a **classified** summary. Each check is tagged:
- **[control]** — verifies a live/remote/structural *working* control: `agent-autonomy.sh`, `branch-protection.sh`, `ci-gates.sh` (per profile), `guard-wired.sh`, `container-supply-chain.sh`, `backlog-adapters.sh`, `check-links.sh`.
- **[doc]** — verifies *documentation or recorded evidence exists*, not that the control was exercised: `deployable-ready.sh`, `dr-ready.sh`, `resilience-ready.sh`, and the `*-checklist.md` / `*-readiness.md` / `definition-of-deployable.md` presence checks.

Output per check: `[control|doc] <name> … PASS/FAIL/UNVERIFIED/N-A`. Footer states it plainly:

```
Summary: N control-checks verified · M doc-checks (records present, NOT independently tested) · K unverified · F failed
A green run proves controls hold AND release/DR/resilience safety is DOCUMENTED — it does NOT prove
those procedures were tested. See each check's NOTE and conformance/README.md "What a green run means".
```

Exit policy: **non-zero if any [control] check FAILs, or any check is UNVERIFIED under `--require`/CI**; doc-checks present-but-untested do not fail the run (they are honestly labelled, not hidden). N/A (conditional checks that don't apply) is a pass. `--selftest` runs a minimal classification self-check.

verify.sh is a *reporter that also gates on control failures* — it does not replace the individual CI steps; it gives humans and adopters one honest surface. The CI may call it, but per-step granularity in `ci.yml` stays.

Scope note in the script header: verify.sh classifies and runs; it inherits each check's own honesty (a [doc] PASS means the document/record exists, full stop).

### 3. `conformance/README.md` — document the taxonomy

- Add a **"Verifies"** column to the index table: `control` vs `documentation/evidence`.
- Add a short **"What a green run means — and doesn't"** section: control-checks prove a working/remote control; doc-checks prove a procedure is written down and (for readiness) a drill date is recorded, NOT that it was tested; UNVERIFIED ≠ pass; point to `verify.sh` as the honest aggregate.

## Files

| File | Change |
|------|--------|
| `conformance/branch-protection.sh` | Three-state exit (0/1/2) + CI/`--require` escalation + `--selftest` + header rewrite |
| `conformance/verify.sh` | **New** — classified aggregate runner ([control]/[doc]), honest footer, control-fail gating, `--selftest` |
| `conformance/README.md` | "Verifies" column + "What a green run means — and doesn't" section + verify.sh entry |
| `.github/workflows/ci.yml` | Add a step running `sh conformance/branch-protection.sh --selftest` and `sh conformance/verify.sh --selftest` (deterministic; no network) |
| `CHANGELOG.md`, `VERSION` | 2.26.0 entry |
| `docs/ROADMAP-SLICE9.md` | Mark 9a done |

## Verification
- `sh conformance/branch-protection.sh --selftest` → OK; three states behave (exit 2 locally w/o gh, exit 1 under CI w/o gh).
- `sh conformance/verify.sh` → classified summary; exit non-zero only on a control failure; `--selftest` OK.
- All existing conformance green; `check-links.sh` green (README links).
- dash-clean (`dash -n`) on both scripts.
- Governance: feature branch → PR → human ratification; this touches a governing-surface check (branch-protection) so the security-owner lens applies.

## Out of scope (future)
- Linked evidence artifacts (run-ids/log URLs) beyond the recorded dates the readiness scripts already assert — a depth item, not Tier-0 honesty.
- Rewriting the readiness scripts (already honest at the unit level).

## Known implications
- Adopters who ran `branch-protection.sh` in a local `&&` chain expecting exit 0 will now get exit 2 when unverifiable. This is intended (a silent pass was the bug); documented in the CHANGELOG and the script's `UNVERIFIED` message.
