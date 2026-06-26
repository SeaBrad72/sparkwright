# Meta-control verdict log

The kit's own run history of the cadenced meta-control panel
([`../operations/meta-control.md`](../operations/meta-control.md)). Each row records one run.

> This is the **kit's instance**. Adopters keep their own log (start fresh). M2 export-ignores this
> file (it is kit-specific run history, like `ROADMAP-KIT.md`).

Format: `date · version · trigger · profile · verdict · verdict-artifact · one-line ledger summary`

| Date | Version | Trigger | Profile | Verdict | Artifact | Ledger summary |
|------|---------|---------|---------|---------|----------|----------------|
| 2026-06-23 | 3.48.0 | manual (M first use) | light (5-lens) | GO-WITH-CONDITIONS | [first-run](../architecture/2026-06-23-meta-control-first-run.md) | Consolidation pivot confirmed; recommends T2-before-T3/T4, decouple E4d, no-E3-default; new CI-trust Blockers (verify.sh selftest + claims-registry) → T4. |
| 2026-06-24 | 3.48.0 | T3a right-weighting | right-weighting (5-surface, aggressive default-cut) | KEEP-BIASED | [t3a-assessment](../architecture/2026-06-24-t3a-rightweight-assessment.md) | Enforcement surface (84 conformance + 12 gates) fully justified — ZERO cuts. Modest right-weighting: ~3 template cuts, 2 doc-stubs + frame/shape, retire 6+5 E-series build-docs, relabel 5 profiles experimental. Epics 10→~6 (E12+E14→E3, E13 dissolved, E8 defer). T3b may descope (nothing on enforcement surface to retire). Stay 3.x; 1.0 premature. |
| 2026-06-25 | 3.48.15 | M2-S2 freshness gate shipped | — (deferral) | DEFERRED | mechanism-first; full panel = M2-S4 | Gate introduced and seeded honestly; the due light 5-lens panel is M2-S4 — revisit by the next slice. |
| 2026-06-25 | 3.48.16 | M2-epic boundary (S4 close; discharges the 3.48.15 deferral) | light+ (5 lenses + harness-neutrality / agent-governance / adopter-proportion) | GO-WITH-CONDITIONS | [run #3](../architecture/2026-06-25-meta-control-3.md) | First real M run. CONFIRMED (repro): the circuit-breaker is self-certifiable — verdict log + marker are not control-plane → M2-S5 ratification-integrity BEFORE E4d. Also CONFIRMED: adopter export RED on `verify --require` (pre-M2, golden-path-coupled checks) → high-pri fix. Enforcement-integrity + harness-neutrality GREEN; applicability spares the solo adopter. |
| 2026-06-26 | 3.49.1 | E3-epic boundary + reorder ratification | light (5-lens) | GO-WITH-CONDITIONS | docs/architecture/2026-06-26-meta-control-4.md | 0 blockers · 7 fix-forward high · reorder GO with the E1/E5-lead-E3 correction; nothing cut |
