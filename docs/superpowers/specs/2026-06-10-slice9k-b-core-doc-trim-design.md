# Slice 9k-b — Core-Doc Trim (design)

**Date:** 2026-06-10 · **Arc:** Slice 9, Stage V (fast-follow of 9k) · **Version target:** MINOR → **v2.38.0**
**Input:** the deferred 9k fast-follow — tighten the core governing docs against the AGENTS.md brief-enabled load. **Measured first (this slice's premise):** the Slice 9 arc added only **~39 lines** to the core-3 (`CLAUDE.md` +22, `DEVELOPMENT-PROCESS.md` +3, `DEVELOPMENT-STANDARDS.md` +14); the core-3 front-load is **~13.4K tokens / 886 lines**, and `DEVELOPMENT-PROCESS.md` (466 lines) is *pre-existing* density, not arc bloat. The economics win (R11) was already banked by 9k's `AGENTS.md` (on-demand loading). So this slice is a **careful tighten of pre-existing verbosity + a ratchet to prevent future bloat — not a cut of anything the arc added.**

## Governing constraint (ratified): retain all that is necessary
The trim **removes only**: literal restated framing, redundant preamble, over-explanation that duplicates a normative statement already made, and stack/example detail that already has a `profiles/` or `docs/` home. It **never removes a normative statement** — at most it tightens wording while preserving meaning and every conformance-grepped marker. Enforced by a three-way preservation audit (below).

## Components

### 1. The trim (conservative, measured)
Targets, heaviest first:
- **`DEVELOPMENT-PROCESS.md`** (466 lines / ~7.3K tok) — the main opportunity; tighten restated framing, preamble, and over-explanation; relocate any stack/example detail to its existing reference home.
- **`DEVELOPMENT-STANDARDS.md`** (309 lines) — lighter pass on verbose prose.
- **`CLAUDE.md`** (111 lines) — minimal touch (already the lean authoritative file).

Realistic landing: a modest single-to-low-double-digit-% reduction, leaning to the conservative end. The number is an outcome of removing genuine redundancy, **not a target that forces cutting substance**.

**Hard rules:**
- **No section renumbering** — `§6`/`§7`/`§13`/`§14` etc. are referenced across docs + conformance; tighten *within* sections, never remove/merge numbered ones.
- **Preserve every conformance-grepped marker** (the suite fails CI otherwise): `the 7 required gates` · `Definition of Ready` · the §7 conditional-gate rows (`Accessibility** *(user-facing UI)*`, `Eval gate** *(AI features)*`, `Resilience readiness** *(deployable services)*`) · `SLSA Build L2` · the §6 backend table names · the §13 autonomy-tier language · `Definition of Done`.
- Governing surface → **security-owner lens** at review.

### 2. The preservation audit (three-way — this is the "retain all that is necessary" guarantee)
1. **Full conformance suite green** — `sh conformance/verify.sh` + every individual check (`dor-defined`, `conditional-gates`, `backlog-adapters`, `guard-wired`, `agent-autonomy`, `ci-gates`, `check-links`, …). These grep for the normative markers; a lost requirement fails CI mechanically.
2. **Content checklist** — an enumerated list (in the plan) of every normative element that must survive — the 6-stage loop · all §7 gates (universal 7 + conditional trio) · DoD · DoR (entry gate) · the security non-negotiables · autonomy tiers · the §6 work-item contract (states/fields/atomic-claim) · environments Dev→QA→UAT→Prod · SLSA L2. The reviewer confirms each is still present (possibly reworded, never removed).
3. **Security-owner-lens review** — confirms no security/governance requirement was weakened; the `git diff` is prose-tightening only.

### 3. `conformance/doc-budget.sh` (new) — ratchet the gain
Asserts each core doc and the core-3 total stay at/under a **line budget** set to the post-trim size (inverted `coverage-ratchet`): a future PR that re-bloats a core doc past budget fails CI. The budgets are constants in the script; raising one is a **deliberate, ratified** change (documented in the header — the same governed-bump pattern as the coverage ratchet). `--selftest`: an over-budget fixture fails, an at-budget fixture passes. POSIX sh, `dash -n` clean. CI-gated (**one control-plane `cp`**).

### 4. Measure + record
Record the before/after core-3 line/token delta in the CHANGELOG; update the ROADMAP economics-baseline note with the new measured core-3 figure and the finding that the arc added only ~39 lines.

## Files

| File | Change | Owner |
|------|--------|-------|
| `DEVELOPMENT-PROCESS.md` | tighten prose (no renumbering; markers preserved) | agent (governing → security-owner lens) |
| `DEVELOPMENT-STANDARDS.md` | lighter prose tighten | agent (governing → security-owner lens) |
| `CLAUDE.md` | minimal tighten | agent (governing → security-owner lens) |
| `conformance/doc-budget.sh` | **New** — per-doc + core-3 line ratchet + `--selftest` | agent |
| `conformance/README.md` | index row | agent |
| `.github/workflows/ci.yml` | `doc-budget.sh` + selftest | **human `cp`** |
| `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md` | 2.38.0; 9k-b → shipped; before/after delta | agent |

## Verification
- **The entire conformance suite is green after the trim** — the real proof no marker/requirement was lost.
- The content checklist (plan) is confirmed line-by-line by the reviewer.
- `sh conformance/doc-budget.sh` → PASS (docs within budget); `--selftest` detects an over-budget doc.
- `dash -n conformance/doc-budget.sh` clean.
- `sh conformance/check-links.sh` green (no broken anchors from the edits).
- `git diff main..HEAD` reviewed under the security-owner lens: prose-tightening only; no normative line removed.
- Before/after core-3 line/token delta recorded.

## Out of scope / deferred
- **Aggressive restructure** (moving sub-sections to new files) — rejected at brainstorm (high churn on anchors/xrefs/conformance).
- **Trimming AGENTS.md or templates** — 9k just shaped the brief.
- **Re-measuring the full ~24K** (globals + profile + templates) — 9k-b targets the core-3.

## Known implications
- The core docs get tighter without losing any governance; the ratchet prevents the slow re-bloat that the badge/brief work in 9k was about preventing.
- "Retain all that is necessary" is made auditable (the content checklist + the conformance suite), not just asserted.
- A future deliberate doc growth (a real new requirement) raises a `doc-budget.sh` constant as a ratified change — bloat is now a conscious decision, not drift.
