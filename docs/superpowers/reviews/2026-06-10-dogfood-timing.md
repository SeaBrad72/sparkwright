# A6 — Empirical Dogfood Timing & Friction

**Date:** 2026-06-10
**Method:** Actually ran `scripts/incept.sh --noninteractive` in clean temp repos on three representative stacks (`typescript-node`, `python`, `go`), each a fresh `git init` of the kit; walked the post-incept "next steps" and `conformance/inception-done.sh`; inspected the first-touch surface a beginner reads (`START-HERE.md`). Purpose: aim Slice 9f (beginner on-ramp) at *measured* friction, not inferred.

> **Bottom line:** The mechanical bootstrap is **not** the bottleneck — `incept` runs clean in ~0–1s on every stack, installs the pre-push guard, renames the principles doc, stamps the project files, and passes `inception-done.sh`. The beginner's cost is **cognitive and unguided**: missing-prerequisite failures with no preflight, a silent file rename that breaks the mental model formed from START-HERE, undefined vocabulary, and an implicit multi-person assumption a solo adopter can't satisfy. 9f should cut *cognitive* friction, not runtime.

## What works (measured)
- `incept --noninteractive` → **exit 0 on all three stacks**, wall time ~0–1s.
- Renames `CLAUDE.md` → `ENGINEERING-PRINCIPLES.md`, stamps a new project `CLAUDE.md` (`# [Project Name] — Claude Project Guide`), RUNBOOK, BACKLOG, ADR-000, wires CI, installs `.git/hooks/pre-push` (9d-b).
- `conformance/inception-done.sh` → **PASS** immediately after a non-interactive incept.
- Stack-neutral: identical clean behavior across ts-node / python / go.

## Friction findings (ranked — these aim 9f)

| # | Friction | Severity | Evidence |
|---|----------|:---:|----------|
| F1 | **No prerequisite preflight.** `incept`, the guard, and conformance require `jq`, `git`, and the stack toolchain, but nothing checks. 3 kit scripts hard-require `jq`; a beginner missing it gets a cryptic guard/conformance failure later, never "install jq first." | P0 | `grep "command -v" scripts/incept.sh` → 0; no `scripts/preflight.sh`; 3 scripts need `jq`. |
| F2 | **Silent `CLAUDE.md → ENGINEERING-PRINCIPLES.md` rename.** `incept` renames the principles doc and stamps a new project `CLAUDE.md`, but the run output never says so. START-HERE (read *before* incept) points at "`CLAUDE.md`" for principles/DoD; afterward that name is the *project* guide and principles moved. The "next steps" even say "Declare config in CLAUDE.md §3" — the *new* file — deepening the ambiguity. | P0/P1 | incept tail shows no rename notice; START-HERE role table cites `CLAUDE.md` for principles. |
| F3 | **No glossary.** "Inception," "the loop," "conformance," "ratification," "contract→reference→conformance," "L1/L2 autonomy," "Stage 1–4," "speed-bump-not-boundary" are used throughout with no one-page definitions. A newcomer to agentic development has no anchor. | P1 | START-HERE + PROCESS use all terms undefined; no `GLOSSARY.md`. |
| F4 | **No solo / lite track.** The kit assumes multiple people (builder ≠ sole reviewer, CODEOWNERS, ratification RBAC). A solo adopter cannot satisfy "builder ≠ sole reviewer" — exactly the case we hit dogfooding this kit (every merge is an admin-bypass). Nothing tells a solo dev the sanctioned path (owner admin-merge as logged self-ratification; which gates are deferrable). | P1 | builder≠reviewer in DoD; no solo guidance; observed via this repo's own branch protection. |
| F5 | **Judgment steps are unanchored.** Post-incept "next steps" (charter prose, ADR, config §3, roles §4) tell the beginner *what* to fill but not *what good looks like* for a first project. | P2 | incept next-steps output; mitigated partly by templates. |

## Timing interpretation
"Time-to-first-feature" for a beginner is dominated by **(a) unguided prerequisite discovery/install**, **(b) reading ~22K lines of governance to know what to do**, and **(c) recovering from the unexplained rename** — not by `incept` (≈1s). The leverage is **orientation**: a preflight that fails fast with fixes, a rename disclosure, a glossary, and a solo track. None require touching the loop machinery.

## Recommended 9f scope (R6)
1. **`scripts/preflight.sh`** — check `jq`, `git`, and stack toolchain presence; print exact install hints; exit non-zero with a clear message. Offer to run it first from START-HERE / incept.
2. **Disclose the rename** — a one-line incept banner ("principles moved to ENGINEERING-PRINCIPLES.md; this CLAUDE.md is now your project guide") + a note in START-HERE.
3. **`GLOSSARY.md`** — one page, the ~12 load-bearing terms.
4. **Solo / lite track** — how one person satisfies builder≠reviewer (owner admin-merge as logged self-ratification) and which gates are deferrable at solo scale (ties to the 9c waiver ramp + the 9e Stage 1–4 model).

## Out of scope for A6
A6 is measurement only — no production change. The fixes are Slice 9f. Deep multi-stack toolchain-install automation (beyond a presence check) stays out; preflight *detects and instructs*, it does not install.
