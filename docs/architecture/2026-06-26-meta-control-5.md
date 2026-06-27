# Meta-control panel #5 — SYNTHESIS & VERDICT — 2026-06-26

**Trigger:** E3a per-slice M verdict (condition A5) + freshness cadence (marker `3.49.1`, 3 tags elapsed → due at E3a)
**Version under review:** 3.52.0 (E3a ship version)
**Profile:** light (5-lens) · Kit-Steward synthesis (PROPOSE-only; human ratifies by committing)
**Slice state:** GREEN on clone dry-run — 27 control-checks, 0 failed.

---

## 1. Verdict

> **GO.**

Zero Blockers, zero Highs from the panel. The kit's first clean-GO panel (panels #1–#4 each found Highs) — earned because E3a is a genuinely thin, honestly-bounded slice that discharges exactly the three obligations panel #4 fixed (A1 §10 status table, A2 runaway-guard wired, A5 this panel) and nothing more.

Two procedural conditions attach (not defects): (1) the verdict row + marker are committed **inside** the E3a apply so `VERSION == marker == 3.52.0` (the gate's allowed ship-seam, never a future-pin); (2) version-finishing stays folded into `apply.py`.

A separate **dual technical review** (reviewer + security-reviewer, builder≠reviewer) ran in parallel and returned **NEEDS-FIXES** on two convergent matcher findings — the `agents/*` control-plane glob over-blocked adopters' own `src/agents/` code, and the roster was protected on the tool path but not the shell path. **Both were fixed before ship** (scope to `agents/*.agent.md` + mirror into both shell matchers + add the `redirect/sed over roster` regressions + add `orchestrator-loop` to `REQUIRED_IDS`). This panel's GO stands on the corrected slice.

---

## 2. The 5 lenses (summary)

- **Lens 1 — scope/proportion · HOLDS.** Right-sized as the thin slice; no later-slice scope pulled forward (only the 4 seats; no standalone skill library; no enforced isolation). Security def carries both hats but exercises only review (authored prose, not mechanism).
- **Lens 2 — honesty · HOLDS.** §10 status table present + truthful in design §7 and `docs/operations/orchestration.md`; claim text + CHANGELOG carry the live-vs-CI and mechanics-not-LLM-quality qualifiers; the honesty line is surfaced in three places.
- **Lens 3 — enforcement integrity · HOLDS.** A2 is the runaway kill-switch's first live call-site AND non-vacuously locked (the A2-teeth selftest fails a loop missing the metering call). The loop is genuinely exercised (real worktrees/guard/merge/spans in an isolated repo; breach→halt→denied→scorecard). `kit.denied` is trusted-layer only. The `orchestration` adapter dimension is a real binding seam (native on claude-code with 4 proof files; floor on others; lying-native guard enforces native proofs).
- **Lens 4 — direction/sequencing · HOLDS.** Matches ROADMAP item 5 step 3 exactly. Self-hosting commitment is owner-ratified and correctly bounded to the E10 acceptance test (not claimed for E3a).
- **Lens 5 — right-weighting/adoptability · HOLDS.** Kit-self N/A scoping + dual export-carve keep the new control off the solo on-ramp; one-page ops doc with the honest-ceiling table up front.

---

## 3. Ledger 1 — verified-as-quality

1. A2 discharged with teeth — runaway went from zero callers to a live call-site + a non-vacuous lock (closes the panel-#4 retro "a gate can validate the script but not its call-site").
2. The stand-in→real swap held byte-compatible through the unchanged `otel-to-scorecard.sh` → real `denial_rate`.
3. Trusted-denial integrity — `kit.denied` is exit-code-derived, never agent-supplied.
4. Honest ceiling surfaced in three places (CHANGELOG · ops-doc §10 · design §7/§9).
5. Adopter-neutral by construction (kit-self N/A + dual carve).

## 4. Ledger 2 — fix-forward (all folded into the E3a apply)

- **B1 (carried from panel #4)** — runaway claims.tsv qualifier: now true (a live caller exists). **Discharged in this apply.**
- **Dual-review must-fixes** — guard `agents/*` → `agents/*.agent.md` scope; shell-path parity (both matchers + regressions); `orchestrator-loop` → `REQUIRED_IDS`. **Fixed.**
- **Security Minors** — clear `OTEL_TRACE_FILE` for the role-runner (no forged spans); slice-name sanitization. **Fixed.**
- **Low** — self-host present-tense softened; post-step-metering honest-ceiling note added.
- **Deferred (routed to E3b)** — root `orchestrator-run` span is zero-duration (children are real-bracketed; scorecard reads children — cosmetic).

## 5. Retro fold-in (E1-thin · E5-thin · vtc-fix · E3a)

- "Ship a labelled stand-in at a stable seam, replace its body later" works end-to-end (E5-thin→E3a; trace contract held byte-compatible) → bank as a reusable slicing tactic.
- The panel-#4 retro ("a control claim must name its enforcement path") is now demonstrably actionable (E3a gave runaway a call-site + an A2-teeth lock).
- Export-carve discipline is now reflexive (kit-self N/A + dual carve pre-applied).
- Version-finishing-in-apply.py held (no 4th skipped bump).

## 6. Next per the ratified order

After E3a ships → E3-escalation (ex-E14, human-in-the-loop) **early** → E3b mechanics (enforced worktree isolation + conflict-safe writes — §10 items 1 & 6) → phase→agent flow → agent-memory **last**.
