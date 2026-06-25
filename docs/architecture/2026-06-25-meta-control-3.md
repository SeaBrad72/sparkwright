# Meta-control run #3 — M2-epic boundary (2026-06-25, v3.48.16)

**Trigger:** M2-epic boundary (the cadenced meta-control freshness gate shipped, S1–S3) + discharge of the
2026-06-25 `DEFERRED` seed row. **Profile:** light+ — the 5 lenses + 3 M2-specific dimensions
(harness-neutrality, agent-governance/security, adopter-proportion). **Verdict: GO-WITH-CONDITIONS.**

This is the first *real* run of the M machinery, and it earned its keep on the first outing: it found a
**confirmed cross-slice gap in M2's own headline guarantee** that six rounds of per-slice dual review
could not see — exactly the direction/proportion/honesty drift class testing and CI cannot catch.

## Verdict

**GO-WITH-CONDITIONS.** M2's mechanism is real and works for its primary purpose (a forgotten panel
fires OVERDUE — proven, with teeth: 5/5 mutation tests caught, desync fail-closed, doctor non-gating,
no vacuous pass). `verify --require` is green on the kit; no remote-exploitable path; the kit is
pre-adoption. **Zero blockers.** But two confirmed HIGHs are fix-forward, one of which breaks a headline
claim, and the honesty of the "ships green" framing is only made true by *this* run logging a genuine
verdict (not a second deferral).

## Conditions (M2 is "done" only when these are met)

- **C1 — discharge the deferral (this run).** Log a real GO-WITH-CONDITIONS row at 3.48.16 and advance
  the marker to `3.48.16 GO-WITH-CONDITIONS`. Satisfies Honesty-F1 / Direction-F3 / Scope-F2(seed). ✅ done by this close.
- **C2 — ratification-integrity fast-follow, BEFORE E4d (the load-bearing fix).** Close the confirmed
  self-certification gap (Ledger-2 #1). Until it ships, soften the headline claims (Honesty-F2).
- **C3 — roadmap truth (this close).** `docs/ROADMAP-KIT.md` still says "M2 NEXT"; flip M2 → done
  (S1 3.48.14 · S2 3.48.15 · S3 3.48.16 · S4 this run), bump Last-Updated.

## Ledger-2 — findings routed (by theme; severity = post-verify)

**#1 [HIGH · CONFIRMED by repro] The freshness circuit-breaker is self-certifiable — the verdict log +
marker are NOT control-plane.** Convergent across 3 lenses (security-F1, direction-F1, scope-F2).
- Repro: appended `| … | 3.48.16 | … | GO | … |` to `meta-control-log.md` + wrote `3.48.16 GO` to
  `.meta-control-last` (no panel) → `meta-control-fresh.sh` → `FRESH … rc=0`. Future-pin `99.0.0 GO`
  (synced) → `FRESH` forever (`count_newer` counts only tags strictly > marker). Serial `DEFERRED` →
  FRESH every cycle (no cap). `grep meta-control .claude/hooks/guard-core.sh` → 0 (not in
  `is_control_plane_path`); `sod-check.sh` has no verdict-authorship coverage.
- Why it matters: S3 locked the *enforcers* (agent defs) but not the *evidence of enforcement*. M2's
  headline — *"an autonomous squad cannot soften the circuit-breaker"* (`meta-control.md:154`),
  *"not a gate it can dodge forever"* (`:158`) — is **not met**. An agent with ordinary Write self-
  certifies, future-pins, or serial-defers the gate with no human and no mechanical block.
- Fix (one slice, "ratification integrity" — route as **M2-S5 / before E4d**): (a) add
  `docs/governance/.meta-control-last` + `docs/governance/meta-control-log.md` to
  `is_control_plane_path` (agent edits → `KIT_GUARD_SELFEDIT=1` / human); (b) reject a marker version
  greater than `max(tags_list)` (future-pin → FAIL); (c) cap consecutive `DEFERRED` (≥2 → OVERDUE
  regardless of count); (d) lock all three in `meta-control-fresh.sh --selftest` + an `agent-autonomy`
  deny case for the marker/log; (e) optionally `sod-check.sh` author≠approver on verdict rows.

**#2 [HIGH · CONFIRMED · pre-M2, surfaced here] Adopter export is RED on `verify --require`.**
- Repro: `adopter-export.sh … --profile typescript-node` → export → `sh conformance/verify.sh
  --require` → `feature-flags-wired`, `containment-audit`, `runtime-security` FAIL (each: "golden-path
  workflow not found: .github/workflows/golden-path.yml" — that workflow is export-ignored). The
  exported `ci.yml` runs `verify --require`, so an adopter's first push is RED.
- Why it matters: contradicts the kit's green-on-clone promise (a T2 headline). M2 didn't cause it, but
  M2 is the boundary that should catch it. `adopter-export-wired.sh` runs claims-registry on the export
  but NOT `verify --require`, so the lock missed it.
- Fix (route as a high-priority standalone item): make the 3 golden-path-coupled checks N/A-with-reason
  when `golden-path.yml` is absent (mirror meta-control-fresh's applicability self-detection); add
  `verify --require` on the exported tree to `adopter-export-wired.sh` so the lock would catch a recurrence.

**#3 [MEDIUM] Discoverability / on-ramp — the cadence is mis-shelved (right-weight-F2/F3/F4, adopter-F4,
harness-F4).** `grep meta-control` across README / START-HERE / CLAUDE / DEVELOPMENT-PROCESS → 0 hits;
only inbound link is a deep ops doc. No `templates/META-CONTROL-LOG-TEMPLATE.md` → an opt-in adopter
hits a fail-closed cliff with no example. `meta-control.md` front-loads the heavy apparatus before
disclosing it's N/A-by-default. Non-GitHub adopters have no documented enforcement path (drift-watch is
GitHub-only). Fix (a docs/on-ramp slice): pointer from DEVELOPMENT-PROCESS "adjust/improve" + README
tailoring list; ship a log template; add an N/A-by-default banner atop `meta-control.md`; one paragraph
on enforcing the cadence off GitHub Actions.

**#4 [LOW] Minor hardening.** (a) `claims-registry.sh` `REQUIRED_IDS` omits `meta-control-fresh`
(enforcement-F1 — silent-drop only incidentally caught). (b) `CHANGELOG` says "8 fixtures"; there are 10
(scope-F3). (c) `agent-autonomy.sh` has no shell-mutation case for `.claude/agents/*` (security-F4 —
believed-denied via the command-path regex but untested). (d) stale inline E4d routing in
`ROADMAP-KIT.md:232,234` (direction-F4). Fold into C2/C3 or a cleanup pass.

## Ledger-1 — confirmed sound (no action; the bones are good)

- **Enforcement integrity: GREEN.** Selftest has real teeth (5/5 mutations caught); desync fail-closed
  both directions; `sort -V`/awk parse robust; doctor truly non-gating; real-git-tag fixtures exercise
  the live path; no existing check drifted green. (enforcement lens, full pass)
- **Harness-neutrality: GREEN.** `meta-control-fresh.sh` is POSIX-sh and `.claude`-free; the runbook's
  *definition* is neutral with the Claude steward binding cleanly quarantined; S3's `.claude/agents/*`
  is confined to the Claude control-plane (the only conformance ref, `agent-autonomy.sh`, self-N/As
  without the Claude hook). Only seam: GitHub-Actions enforcement coupling (→ #3).
- **Applicability-as-detected-trigger** (not declared mode) genuinely spares the solo/vibe-coder
  (verified N/A on a clean adopter tree) and can't be mode-weakened (`mode-enforcement-blind` passes).
  The vibe-coder is not nagged — the primary adoptability bar is cleared.
- **E4d remains the right next feature move** (standalone safety gap, decoupled by the M1 panel) — but
  C2 (ratification integrity) should precede it.
- **The marker IS arguably redundant** with the log (scope-F1) — the sync-lock guards a hazard the
  dual-file design creates. Noted as a design-simplification candidate, but C2 makes the *marker* the
  control-plane anchor, which changes the calculus; revisit during C2.

## The meta-lesson (for the kit's own retro)

The panel's first real run found that M2's circuit-breaker can be softened by the very autonomous agent
it's meant to constrain — and that the kit's green-on-clone promise is broken — neither caught by
per-slice review. This is the panel justifying its existence: **build-time correctness review (per
slice) and direction/honesty review (the panel) are different controls, and the kit needs both.** It
also validates running the panel at the epic boundary rather than waiting for the N-tag clock.
