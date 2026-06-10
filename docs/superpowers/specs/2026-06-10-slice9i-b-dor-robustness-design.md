# Slice 9i-b — Definition-of-Ready Robustness (design)

**Date:** 2026-06-10 · **Arc:** Slice 9, Tier 2 (fast-follow of 9i) · **Version target:** MINOR → **v2.34.0**
**Input:** the kit enumerates the **Definition of Done** as an authoritative block in `CLAUDE.md`, but the **Definition of Ready** exists only as a scattered parenthetical — a gate row (§7 "criteria present, sliced, deps known"), a ritual line (§11), a Plan-phase requirement (§4 table), the backlog "Ready" column, and a WALKTHROUGH mention. Nowhere is it enumerated. The user's intent: *"ensure development on a story/feature doesn't proceed without its requirements being met"* — an explicit, auditable entry gate, peer to the DoD.

## Scope (ratified at brainstorm)
Promote the DoR to a first-class enumerated checklist living in `CLAUDE.md` as a true peer to the DoD (entry gate vs exit gate); tie it to the Ready→Build gate and the `FEATURE-REQUEST` intake template; guard it with a completeness drift-guard. Docs/templates + one completeness check + CI wiring. No new loop machinery, no per-feature content validation.

## The 8 DoR items
Four mandatory, four conditional flags. Each conditional flag maps to a gate the kit **already has** downstream (§7) — so a "Ready" item never slams into an unflagged gate.

| # | Item | Kind | Maps to |
|---|------|------|---------|
| 1 | Acceptance criteria written (testable) | mandatory | Review / acceptance |
| 2 | INVEST-sliced — small vertical increment | mandatory | §11 ritual |
| 3 | Dependencies known | mandatory | §7 DoR |
| 4 | Success metric / hypothesis stated | mandatory | §5 Discovery prompt |
| 5 | Threat-model flagged *(if sensitive)* | conditional | §7 Threat-model gate |
| 6 | UX/a11y obligation flagged *(if user-facing surface)* | conditional | DoD Accessibility item + §5 lens |
| 7 | Eval criteria flagged *(if AI feature)* | conditional | §7 Eval gate |
| 8 | Compliance obligation flagged *(if regulated)* | conditional | §7 Compliance gate |

The conditional items are quick applicability checks ("N/A" for a small internal increment) — they keep the DoR from feeling heavyweight while ensuring no downstream gate is a surprise.

## Components

### 1. `CLAUDE.md` — the canonical DoR block (governing surface)
A new `## Definition of "Ready"` block immediately **above** the existing `## Definition of "Done"`. Framed explicitly: **DoR = entry gate ("safe to start?")**; **DoD = exit gate ("safe to ship?")**. Lists the 8 items (4 mandatory + 4 conditional-with-their-gate). One closing line: "If any mandatory box is unchecked, the item is not Ready — it does not enter Build." This is the authoritative source; everything else points here.

**Governance note:** `CLAUDE.md` is the authoritative principles file. This edit *adds* an entry gate; it must not alter or weaken the DoD. The DoD block is left byte-for-byte unchanged. Security-owner lens at review confirms additive-only.

### 2. `DEVELOPMENT-PROCESS.md` — point to canonical, don't duplicate
Minimal edits so the three existing DoR references name the canonical block rather than re-describing it:
- **§7 gate row** (the "Definition of Ready | Safe to start? (criteria present, sliced, deps known)" row) → append a pointer to the enumerated DoR in `CLAUDE.md`.
- **§11 ritual** ("Definition of Ready — readiness gate before Build.") → append the same pointer.
- **§4 Plan-phase line** ("Must reach **Definition of Ready**.") → append the pointer.
No list duplication — one source of truth, three referrers.

### 3. `templates/FEATURE-REQUEST-TEMPLATE.md` — fill-to-ready at intake
A `## Definition of Ready` section so an item is filled-to-ready when raised: the 4 mandatory items as `- [ ]` checkboxes; the 4 conditional items as flag-or-`N/A`. Guidance blockquote points at the canonical `CLAUDE.md` block. This is the roadmap's "tie to FEATURE-REQUEST" — the entry gate becomes a thing you fill, not a thing you remember.

### 4. `templates/BACKLOG-TEMPLATE.md` — the "Ready" column
The existing "Ready" column blockquote ("Passed Definition of Ready (criteria present, sliced, deps known). Safe to start.") points at the enumerated checklist in `CLAUDE.md`, so the board's Ready lane and the canonical definition agree.

### 5. `conformance/dor-defined.sh` — completeness drift-guard
Same shape as `persona-artifacts.sh` (Slice 9i). Asserts:
- (a) `CLAUDE.md` contains a `Definition of "Ready"` block;
- (b) `DEVELOPMENT-PROCESS.md` §7 references the DoR;
- (c) `templates/FEATURE-REQUEST-TEMPLATE.md` carries a `Definition of Ready` section.
`--selftest` with a two-tree fixture (a gap tree that must fail-detect + a complete tree that must pass), **no `rm`**. Completeness, not content-equality. POSIX sh, `dash -n` clean. Wired into kit CI (**one control-plane `cp`**).

## Files

| File | Change | Owner |
|------|--------|-------|
| `CLAUDE.md` | **New `## Definition of "Ready"` block** above the DoD (DoD untouched) | agent (governing surface → security-owner lens) |
| `DEVELOPMENT-PROCESS.md` | §7 / §11 / §4 references point to the canonical DoR | agent |
| `templates/FEATURE-REQUEST-TEMPLATE.md` | **New `## Definition of Ready` checklist section** | agent |
| `templates/BACKLOG-TEMPLATE.md` | "Ready" column → points at the enumerated DoR | agent |
| `conformance/dor-defined.sh` | **New** — completeness drift-guard + `--selftest` | agent |
| `conformance/README.md` | index row | agent |
| `.github/workflows/ci.yml` | `dor-defined.sh` step + selftest | **human `cp`** |
| `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md` | 2.34.0; 9i-b row → shipped | agent |

## Verification
- `sh conformance/dor-defined.sh` → PASS (DoR block present + §7 references + FEATURE-REQUEST carries it); `--selftest` detects a synthesized gap and accepts a complete tree.
- `dash -n conformance/dor-defined.sh` clean.
- `sh conformance/check-links.sh` green (new references resolve).
- `sh conformance/verify.sh` OK; existing checks unaffected.
- `git diff main..HEAD -- CLAUDE.md` shows the DoD block byte-for-byte unchanged; the only addition is the new DoR block (diff-reviewed under the security-owner lens).
- Anonymization: generic ([[kit-anonymization]]).
- Governance: feature branch → PR → human ratification; the `.github/workflows` step via human `cp`.

## Out of scope / deferred
- **Per-feature DoR content validation** (auto-judging "is this sliced small enough?" / "are these criteria testable?") — a human-judgment gate, same boundary the kit draws for the UAT/a11y sign-offs. The drift-guard + the fill-to-ready template deliver "explicit + auditable" without per-record machinery.
- **Changing the DoD** — 9i-b only adds the entry gate; the exit gate is untouched.
- **New gates** — the DoR surfaces the entry gate that already exists; it introduces no new downstream gate (items 5–8 map to gates the kit already ships).

## Known implications
- The kit now states both gates symmetrically in one authoritative file: enter on the DoR, exit on the DoD. The "8-item DoR" is the new bar an item clears before Build.
- A future DoR item must be added to the `CLAUDE.md` block and (if it has a template home) reflected in `FEATURE-REQUEST`; the drift-guard ensures the block + template + §7 stay wired together.
