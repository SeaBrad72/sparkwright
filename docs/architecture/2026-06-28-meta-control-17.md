# Meta-control panel #17 — skill-spine brick #9, the kit's own `evals` skill (Phase 2, AI-native)

**Date:** 2026-06-28
**Trigger:** per-slice M verdict (condition A5) for skill-spine brick #9 (v3.66.0) — second brick of Skill-Spine Phase 2.
**Profile:** light (5-lens).
**Verdict:** **GO** — 0 blockers, 0 unaddressed highs; 3 Low routed to a single count-neutral sweep + an observation.

Brick #9 = the kit's own `evals` skill (`skills/evals/SKILL.md`) — eval-driven development, the AI-native sibling of `tdd`, a **KIT-ORIGINAL** (no superpowers equivalent; it *adds* the craft superpowers lacks, does not replace one). FLOOR-only invoke-by-read, wired **dual-seat** to the Engineer (eval-driven build) and the Security-reviewer (red-team/safety lens), both asserted. Designed + planned by dogfooding the kit's own design/plan skills (9th self-host). Built AMBER; dual-reviewed (reviewer APPROVE + security-reviewer PASS, 0 findings — it audited the eval-security content itself); independently proven on a fresh clone.

## The 5 lenses

| Lens | Verdict | Evidence |
|------|---------|----------|
| Scope-coherence & proportion | GREEN | 22 paths, no new gate/claim-row/guard. Dual-seat is NOT ceremony: `check_evals_skill` has 3 distinct FAIL lines (markers, Engineer-ref, Security-ref); cases 22/23 prove each ref-leg independently load-bearing. The Security leg is genuine — red-team/jailbreak/prompt-injection is a §7 *security* gate, distinct from the Engineer's eval-driven build. The skill POINTS AT existing infra (EVAL-PLAN / eval-ready.sh / §7 gate / AI-SYSTEM-CARD) and does not duplicate it (all 6 pointed-at targets exist). |
| Honesty & over-claim | GREEN | Kit-original framing verified: claims.tsv says "bricks #1-8 replace superpowers; evals adds the AI-native craft superpowers lacks" — no "replaces superpowers" coupled to evals. Probabilistic-green honest ("green is a threshold, NOT 0 failures; a probabilistic system has a failure rate by nature"). No runtime over-claim — the skill cedes enforcement to the §7 Eval gate ("the gate is the teeth; this skill is the craft"). Design §5 names the honest ceiling. |
| Enforcement integrity (green-while-dark) | GREEN | Re-proven on a fresh clone: SHA-256 applied==reviewed for SKILL.md + verifier (no confabulation); selftest 23/23; shellcheck clean; `verify --require` 31/0 failed; idempotent; structural `check_keystone` GREEN with `skills/evals` indexed. Cases 21/22/23 load-bearing. Marker-strength caveat (Low-1): 4 of 5 markers are generic eval vocabulary — consistent with the declared declaration-check ceiling (the §7 gate is the real teeth), but thinner than debugging's markers. |
| Direction & sequencing | GREEN | Evals is the right Phase-2 brick #2. **The structural keystone check (v3.65.0) demonstrably protected this slice** — the build could not land without indexing the evals row (`check_keystone` enumerates disk; `_keystone_ok` was forced to emit `skills/evals`); the live keystone indexes it. Panel-#16 Low-1 fully folded (zero stale "seven" in the keystone). Open & routed: M1/M2 count-drift (→ sweep), tag-time CI gate (banked), brick #10 discovery (next). |
| Right-weighting & adoptability | GREEN | Invoke-by-read, zero adopter burden, invisible until an adopter builds an AI feature. Heavy live-eval-harness deferred to the future E6 epic; this is the cheap FLOOR craft brick. |

Standing "integration-capability / no-dead-ends" lens: **N/A** — FLOOR skill + verifier extension.

## Findings

- **0 blockers · 0 unaddressed highs.**
- **Low-1 (observation, marker strength):** 4 of 5 evals markers (`eval-driven`, `judge`, `red-team`, `threshold`) are generic eval vocabulary; only `name: evals` is kit-specific — a generic stub named `evals` containing those nouns passes the markers. Consistent with the declared declaration-check ceiling (same class as every spine brick; the §7 gate is the real teeth), but thinner than debugging's. Route as an observation; when next touching the evals verifier, consider a more craft-specific marker (e.g. `judge-independence` or `probabilistic`).
- **Low-2 (M1, comment):** verifier comments `orchestrator-loop-wired.sh:697` ("all seven index paths") + `:857` ("indexes all seven spine skills") hardcode a stale count (now 8 content skills). Shell comments, never adopter-rendered, no green-while-dark (the gate is disk-truth). Route to the count-neutral sweep.
- **Low-3 (M2, narrative):** orchestrator defs `agents/orchestrator.agent.md:67` + `.claude/agents/orchestrator.md:22` narrate "the kit's **six spine skills** (design, plan, tdd, review, worktrees, verification)" — stale in count AND membership (omits debugging + evals). Agent-facing, but the enforcement substrate (the keystone) is correct + structurally gated, so routing is via the keystone (correct), only the def's summary undercounts. Out of this slice's scope (apply.py doesn't touch those files). Route to the sweep.

**The 2 Minors do not block** — M1 is a non-shipping comment; M2 is an agent-facing summary whose enforcement substrate is correct. Neither creates a false adopter headline nor a green-while-dark hole.

## Two ledgers

**Ledger 1 — verified-as-quality (ship with confidence):** SHA-256 applied==reviewed (SKILL + verifier, no confabulation); selftest 23/23; shellcheck clean; live verifier exit 0; `verify --require` 31/0 failed; idempotent; structural check_keystone GREEN with evals indexed (the v3.65.0 check forced the index row — it protected this slice); cases 21/22/23 independently load-bearing (3 distinct teeth); dual-seat non-vacuous; kit-original claim wording verified; probabilistic-green honesty explicit; no runtime over-claim (cedes to §7 gate); panel-#16 Low-1 fully folded (zero stale "seven" in keystone); skill points-at-not-duplicates the eval infra; the AI-security content (prompt-injection defense, output+authz validation, judge-independence, red-team-feeds-from-incidents, author-don't-run-live-provider) read end-to-end — no anti-patterns; FLOOR-only; zero adopter burden.

**Ledger 2 — fix-forward (ranked):**
1. **Count-neutral SWEEP (single deliberate slice)** — make the orchestrator-def enumeration (`agents/orchestrator.agent.md:67`, `.claude/agents/orchestrator.md:22`) count-neutral, and fix verifier comments `orchestrator-loop-wired.sh:697,857`. **Leave historical CHANGELOG/log entries** (point-in-time records — e.g. CHANGELOG's "six spine skills" was true at brick #7; do not rewrite). Optional: a tiny conformance grep banning a hardcoded spine-count in *live* (non-historical) prose, so the class self-closes. (M1+M2)
2. **Guard-hardening slice (banked from #16)** — add `conformance/` to `guard-core.sh:82/85` shell-redirect regex (two-matcher symmetry).
3. **Tag-time CI gate (banked from #15/#16)** — refuse to tag a red-CI commit.
4. **Marker-strength (observation)** — a more craft-specific evals marker, when next touching that verifier.

## Retro

- **A structural self-check pays off the slice it ships.** v3.65.0's disk-enumerating `check_keystone` forced this build to index the evals row — the keystone could not half-land. The banked-fix-pulled-forward (panel #16) protected #9 exactly as predicted. Structural enforcement at a boundary protects every subsequent slice; the cost of a stopgap compounds per slice.
- **Structural enforcement closes the gate but not the satellite narratives.** #16 made the keystone enforcement disk-truth and fixed the keystone prose — but the orchestrator-def enumeration + verifier comments still narrate "six/seven". Fixing the gate does not fix every hand-written satellite. Lesson: when a count becomes structurally enforced, sweep every hand-written satellite in the same arc, and consider banning live hardcoded counts. (→ Ledger-2 item 1 + the optional grep.)
- **Kit-original is a distinct honesty mode from replace-superpowers.** Bricks #1–8 had to not over-claim a replacement; #9 had to not falsely claim a replacement of something superpowers never had. The claim got it right. The spine now mixes replace-bricks and add-bricks; the claim must keep both framings legible as it grows.

**Next: brick #10 (`discovery`)** — the last Phase-2 craft brick, then E10. No resequencing.
