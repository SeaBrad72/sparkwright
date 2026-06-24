# Meta-control — first run (consolidation-order verdict)

**Date:** 2026-06-23 · **Version:** 3.48.0 (M1) · **Trigger:** manual (M's first use) · **Profile:** light (5-lens)
**Runbook:** `docs/operations/meta-control.md` · **Run by:** Kit-Steward panel (5 adversarial lens agents → verify pass → synthesis)

> M's first use, per its charter: *decide the rest of the consolidation order — validate the plan by the
> mechanism, not by assertion.* This is the panel run on the kit at `main` @ e99247b + M1 docs.

---

## Verdict: **GO-WITH-CONDITIONS**

The consolidation pivot is **correct and confirmed** — all five lenses independently agree the kit
accreted rigor faster than it validated fit, and that consolidating before E3 is the right
prescription. **Proceed**, subject to the conditions below. No NO-GO blocker exists on the kit itself
(it is pre-adoption and now honest about it); the Blocker-class findings are **CI enforcement-integrity
holes** that the consolidation's own T4 addresses — but they are more urgent than their current ranking.

The panel's recommended order **diverges** from the current reprioritized backlog (T2 pulled earlier;
E4d decoupled; E3 not default-first; a new CI-trust Blocker elevated). Per the kit's rule — *agents
propose, humans ratify* — this divergence is surfaced for Bradley's ratification; the backlog is **not**
edited by this run.

---

## How the run worked

5 lenses (scope-coherence · honesty · enforcement-integrity · direction · right-weighting), each an
independent adversarial agent under the evidence standard (file:line / command-output or dropped), then
an adversarial **verify pass** (refute-by-default) on the material findings. Convergence across
independent lenses is itself signal: over-build/proportion, the one-way ratchet (no retirement), and
declaration-vs-behaviour conformance gaps were each found by **multiple** lenses without coordination.

**Verify-pass adjudication of contested findings:** verify.sh-selftest gap **CONFIRMED** (new Blocker) ·
claims-registry swallowing (F2) **CONFIRMED** · *-wired NAMED-not-RUN (F7) **CONFIRMED** (design-acknowledged;
path-filter gap real) · mode-dial "cosmetic defect" **REFUTED** (it is a ratified, CI-locked invariant —
`conformance/mode-enforcement-blind.sh` — survives only as a naming/expectation critique) · ROADMAP
staleness **CONFIRMED** · DAST-on-toy-server **CONFIRMED** (scope already honestly disclosed in the
conformance header).

---

## Ledger 1 — verified-as-quality (probed deep, held)

- **The consolidation diagnosis is right.** All 5 lenses confirm "rigor outran validation"; the
  pivot (consolidate before E3) is the correct prescription. *(every lens)*
- **T1 honesty genuinely shipped and holds.** F1 (file-count), F3 (maturity caveat in exported
  README + EXEC-BRIEF), F4 (downscoped headline verbs) verified present and correct; the kit is
  "substantially more honest" with candid honest ceilings. *(honesty lens; verify #5/#6)*
- **Mode-blind enforcement is a sound, drift-locked invariant.** `mode-enforcement-blind.sh` provably
  prevents any mode from weakening an applicable control — the "cosmetic defect" reading was refuted.
  *(verify #4)*
- **In-doc honesty discipline is good.** The `*-wired`/`runtime-security` checks self-label as static
  locks; the live proof lives (honestly) in golden-path. *(enforcement lens; verify #3)*
- **M1 works.** The panel ran end-to-end and produced evidence-backed, convergent findings — this run
  is the mechanism's own proof-of-function.

## Ledger 2 — fix-forward (ranked, grouped into workstreams)

### A. CI enforcement trustworthiness → fold into **T4** (elevated; the verify pass found a new Blocker)
- **[Blocker]** `verify.sh --selftest` is renderer-only and `conformance/verify.sh:21` uses
  `out=$(sh "$0" 2>&1) || true`, discarding the inner exit. Per-PR CI runs only `--selftest`
  (`ci.yml:221`); the real `--require` runs **weekly** (`drift-watch.yml:18`). → A PR that breaks a
  verify.sh-only `[control]` (e.g. `branch-protect`) passes per-PR CI. **Fix:** selftest must assert
  ≥1 `[control]` PASS + 0 FAIL + inner exit 0; add `verify.sh --require` as a per-PR step.
- **[Blocker]** `claims-registry.sh:25` runs `sh -c "$v" >/dev/null 2>&1` — swallows the verifier's own
  output and collapses *every* non-zero exit to FAIL, so an UNVERIFIED result (the third state
  `verify.sh` preserves per-check) is indistinguishable from a hard failure (F2). **Fix:** capture +
  print verifier output on failure; preserve the three-state distinction.
- **[High]** `*-wired` checks verify NAMED-not-RUN, and `golden-path.yml`'s path filter excludes
  `conformance/**` and `scaffold/src/**` → the live containment/runtime-security/flag proofs can drift
  without re-trigger (F7). **Fix:** widen the path filter, or document "periodic-only" honestly.

### B. Direction / sequencing correction → **the consolidation order itself**
- **[Blocker — direction]** **Resequence T2 (real validation) BEFORE T3 and T4.** You cannot
  right-weight (T3) or carve conformance for adopters (T4) without external / from-scratch evidence;
  the audit itself calls T2 "the actual gap-closer." Current backlog has T4→T3→T2 — reversed from the
  audit's own tier priority. *(Lens 4 + Lens 1, convergent)*
- **[High]** **Decouple E4d (cost/runaway kill-switch) from E3** and ship standalone — it's a safety
  gap that grows with every epic; it does not need the orchestration layer to be useful.
- **[High]** **Do not default E3-first** in the feature queue — require an affirmative per-epic M
  verdict; E1 (test battery) / E5 (observability) deepen *validation* and may rank above E3 (which
  expands *surface*). E3-first is the exact posture the pivot halted.
- **[Medium]** Tail epics E9/E11/E12/E13/E14 are unevidenced; T3 should **kill/merge** candidates
  (E12/E14 may be E3 slices; E13 overlaps E4d) before they accrete into another committed queue.

### C. Right-weighting / adoptability → **T3**
- **[High]** One-way ratchet confirmed (F6): 84 conformance files, 25 templates, ~167 adopter-visible
  `.md`, **no retirement mechanism**. **Fix:** a governed retire path; extend doc-budget across all
  docs (a total-count ratchet).
- **[High]** Adopter surface overwhelming for the vibe-coder span: ~470 (PROCESS) + ~319 (STANDARDS)
  lines of mandatory reading before code; flat `templates/`. **Fix:** a true 1-page fast path;
  partition `templates/` → core / conditional / enterprise.
- **[Medium]** The mode-dial **name** ("prototype") implies ceremony relief it does not deliver
  (enforcement is mode-blind *by sound design*). **Fix (honesty, not defect):** either make prototype
  reduce genuinely-optional non-floor ceremony, or reframe so it doesn't imply enforcement relief.

### D. Honesty residue → cheap T1 follow-on
- **[High]** EXEC-BRIEF / ROI-MODEL industry stats (+30% / +23.5%) are **unsourced**. Source or
  downgrade to "anecdotal."
- **[Medium]** "first-class profiles" (10) unqualified at point of claim (only ts-node executed);
  `adapters/README.md` omits 3 of 5 shipped adapters (codex/cursor/gemini).
- **[Low]** E4a/E4c CHANGELOG **bodies** still imply generic scope (add "ts-node reference");
  "curated" overstates the named adapters' differentiation from `generic`.

### E. Meta-control hygiene → finish M1 + **M2**
- **[High]** **Define N concretely** (recommend N=5 slices) — the cadence is unoperationalizable
  without it, and M2 needs it as input.
- **[Medium]** ROADMAP-KIT.md is **stale** — F3/F4 not marked ✅, "Last Updated" 2026-06-22. Update.
- **[Medium]** Log this run as the first verdict-log entry (the panel should use its own tracking from
  day one). *(done by this run)*
- **[Note]** M2 must follow promptly — until it ships, the trigger is discipline, not enforcement.

---

## Retro (the "adjust" step — what the last N slices taught)

The E4 burst (6 slices in <24h) plus this panel confirm the **F5 build-ahead-of-need pattern recurred
even as the audit was being written**, and the institutional control (M) was built *after* the decision
it was meant to inform. **Lesson:** M must run **before** committing the next epic, and N must be
defined and **enforced (M2)** or the same drift recurs. **Routing:** this verdict → ROADMAP-KIT.md
reprioritization (pending ratification); the N definition → `meta-control.md`; M2 → next slice.

---

## Recommended consolidation order (the divergence — for ratification)

| # | Current backlog | Panel recommends | Why the change |
|---|---|---|---|
| 1 | M (this) | **M (this) + define N + mark ROADMAP** | finish M hygiene; the cadence needs a concrete N |
| 2 | T4 | **T2 (real validation) FIRST** | can't right-weight/carve without external evidence; T2 = "the gap-closer" |
| 3 | T3 | **T3 (right-weight)** armed with T2 evidence | kill/merge tail epics here, with real signal |
| 4 | T2 | **T4 (conformance hardening)** — **elevate the verify.sh + claims-registry CI Blockers** | CI-trust holes are more urgent than their current rank |
| 5 | feature epics, E3 first | **M2 (enforcement) + E4d (decoupled)** before any feature epic | close the cadence loop + the growing safety gap first |
| 6 | — | **feature epics in per-epic M-ratified order** (not E3-default) | E1/E5 may precede E3; each epic gated by M |
| 7 | E10 + R | **E10 + R** (unchanged) | capstone |

**Net divergence from the current backlog:** (a) T2 moves from last-of-T to first-of-T; (b) the two
CI-trust Blockers are elevated within/ahead of T4; (c) E4d is decoupled from E3 and pulled forward;
(d) E3 loses its default-first slot — per-epic M ratification governs the feature order; (e) M2 is
explicitly sequenced before feature work.

> **This is a proposal. Ratification is Bradley's.** The backlog is not edited by this run.
