# Meta-control panel #8 — light 5-lens per-slice M verdict — skill-spine brick #1 (design skill) — 2026-06-27

**Trigger:** per-slice M verdict (condition A5) for the kit's own `design` skill. **Profile:** light (5-lens) · Kit-Steward synthesis (PROPOSE-only; human ratifies & commits).
**Version under review:** 3.57.0 (AMBER-staged `scratchpad/design-skill/apply.py`; human applies). Freshness: FRESH.
**Inputs:** design `2026-06-27-design-skill-design.md`; landing diff (post-fix). Dual review: **correctness APPROVE; security REQUEST-CHANGES → PASS** (two-matcher gap fixed). All findings below independently repro-verified.

---

## 1. Verdict

> **GO.** 0 blockers · 0 unaddressed highs · 2 Low fix-forward (→ brick #2).

A thin, honestly-scoped, non-vacuous, harness-neutral vertical that genuinely reduces the superpowers dependency (ships a referenced design methodology, not a pointer). The security two-matcher gap and the correctness cosmetics were caught + resolved in dual review; the verify pass re-confirmed the fix is live at both matchers.

## 2. Per-lens findings (each repro-verified)

1. **Enforcement-integrity / teeth — PASS.** `check_skill` greps 6 kit-distinctive markers + the orchestrator reference; case-5 (missing `## When to use`) → exit 1 (repro'd). Exact casing parity SKILL↔grep (`grep -qF` all FOUND). A generic superpowers paraphrase fails. Quality un-gateable (named ceiling) — but for a skill, authored guidance is the correct shape.
2. **Harness-neutrality — PASS.** Invoke-by-read is universal (markdown, no plugin needed); both orchestrator defs reference it. FLOOR-only-first honest (formal `skills` adapter dimension + native bindings deferred to brick #2; no F5 build-ahead).
3. **Honest-ceiling — PASS.** Claim = structural (exists/well-formed/referenced) — exactly what's proven; `claims-registry` PASS. "guard-immutable" now true at BOTH matchers (re-verified: tool matcher + both shell regexes + 4 agent-autonomy fixtures). "FULL replacement of superpowers" honestly scoped to brick #1 / E10 acceptance; bootstrap-use acknowledged.
4. **Right-weight / proportion — PASS.** "No new gate" real (extends `orchestrator-loop-wired.sh`, shared verifier, one claim). Proportionate (one FLOOR skill vs the rejected Architect-seat / deferred E3-flow). Genuinely reduces the dependency (one of ~8 skills, incremental but real).
5. **Integration-capability / no dead-ends — PASS.** Clean homes for brick #2 (plan skill, `skills` adapter dimension, native bindings), the banked E3-flow, the parallel roster track. The skill hands off "to the plan skill" (the brick-#2 seam, named not built). No build-ahead.

## 3. Verify pass (material findings re-checked)
Teeth non-vacuous (case-5 repro'd) · casing parity confirmed · `skills/` closed at BOTH shell matchers (4 fixtures PASS, env-unset) · **refuted:** the first-run `sed -i skill FAIL` was a `KIT_GUARD_SELFEDIT=1` env artifact (re-ran clean) and the `adopter-export HEAD` error was a reconstructed-copy git artifact — neither a regression.

## 4. Ledger 1 — verified-as-quality
Skill teeth non-vacuous + casing-exact; `skills/` guard-immutable at both matchers (3rd-recurrence gap closed); FLOOR-only-first honest; ceiling truthful; right-weight real (no new gate); AMBER discipline correct.

## 5. Ledger 2 — fix-forward (→ brick #2, non-blocking)
- **Low-1 (cosmetic):** `scratchpad/design-skill/apply.py:10` docstring references the gitignored plan path. Harmless (throwaway applier).
- **Low-2 (banked):** the SKILL prose phrasings (`Design-intent lens`, `RE-SELECT`, `Honest ceiling`) are load-bearing for the grep — a future copy-edit could silently break the gate; add an inline "conformance-load-bearing" note at brick #2.

## 6. Retro fold-in (the headline — a recurrence-3 process signal)
**The two-matcher guard gap has recurred 3×** — escalate.sh (`81fb3a4`), M2-S5 verdict-state (`42ef955`), and `skills/` (this slice). All three were caught by *security review*, never proactively by the author. **Recommended route (endorsed): add a discipline to the kit's OWN `design` skill** (which this slice ships) so the next author is prompted at design time:

> **Control-plane completeness.** When a slice makes a path control-plane, add it to **all three** guard surfaces — `is_control_plane_path` (Edit/Write tool), shell-matcher-1 (general mutation deny), shell-matcher-2 (redirect/co-occurrence deny) — **plus** an agent-autonomy fixture per mutation form (Write / redirect / sed-i deny, read allow). The Edit/Write deny alone is not enough; the shell back-door is the recurring gap.

More durable in the skill (prompts *before* the gap is built) than a standards note (consulted after); self-consistent with the slice's own thesis ("bake in the kit's disciplines"). **Route as a brick-#2 follow-on edit to `skills/design/SKILL.md`** (human-ratified PR, since `skills/` is now guard-immutable); secondary home `DEVELOPMENT-STANDARDS.md` §2.

## 7. Routing
- Verdict-log row + marker (§8) → human commit (control-plane). Verdict artifact = this file.
- Brick-#2 follow-ons: control-plane-completeness discipline → `skills/design/SKILL.md`; Low-1/Low-2 cosmetics. No divergence from plan (this is the ratified SKILLS-track brick #1; roster track parallel; E3-flow banked).

## 8. Ready-to-commit

**Verdict-log row** → append to `docs/governance/meta-control-log.md`:

```
| 2026-06-27 | 3.57.0 | skill-spine brick #1 per-slice M verdict (A5) | light (5-lens) | GO | docs/architecture/2026-06-27-meta-control-8.md | 0 blockers · 0 highs · 2 Low fix-forward (apply.py docstring path; SKILL prose load-bearing-for-grep note). Teeth non-vacuous (case-5 repro'd, 6 markers exact-casing parity); FLOOR harness-neutral + FLOOR-only-first honest; ceiling truthful (structural-proven, quality-ungateable, FULL-replacement scoped to brick #1/E10); right-weight real (no new gate, shared verifier, one claim); skills/ guard-immutable at BOTH matchers (3rd-recurrence gap closed, 4 fixtures PASS). RETRO: two-matcher gap recurred 3x -> route a control-plane-completeness discipline INTO skills/design/SKILL.md (brick #2 follow-on). |
```

**Marker** → overwrite `docs/governance/.meta-control-last`:

```
3.57.0 GO
```
