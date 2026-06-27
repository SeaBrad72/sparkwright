# Meta-control panel #7 — light 5-lens per-slice M verdict — E3b conflict-safe — 2026-06-27

**Trigger:** E3b per-slice adversarial go/no-go — condition **A5** (each E3 slice ships only on an affirmative per-slice M verdict). Freshness: FRESH (0 tags since 3.55.0; N=5) — discretionary per-slice run, not the cadence breaker.
**Version under review:** 3.56.0 (AMBER-staged `scratchpad/e3b-conflict-safe/apply.py`; human applies).
**Profile:** light (5-lens) · Kit-Steward synthesis — PROPOSE-only; human ratifies & commits.
**Inputs:** design `2026-06-27-e3b-conflict-safe-design.md`; landing diff (post-fix). Dual review: **correctness APPROVE; security REQUEST-CHANGES → all fixed → re-review PASS**. All findings below survived an adversarial verify pass (repro from the applied clone, not assertion).

---

## 1. Verdict

> **GO-WITH-CONDITIONS.** 0 blockers · 0 highs · 2 Low fix-forward.

The verified path holds end-to-end; no headline claim outruns its proof. The single ship-condition is cosmetic-honesty (a stale §10 owner label) and does not touch the proven path.

## 2. Per-lens findings

1. **Enforcement-integrity / teeth — GREEN.** Non-vacuous: overlap → refuse + `kit.conflict` + no silent integration; disjoint → clean; dueling-rename closed. **`--no-renames` proven load-bearing by sabotage** — removing only that token flips the dueling-rename assertion to `FAIL: silently integrated a side`. Wiring teeth (case 4: loop without `kit.conflict` → exit 1) non-vacuous. Trusted-layer: `kit.conflict` orchestrator-only, `agent.id=orchestrator`, computed from the orchestrator's own `git diff`; role-runner env scrubbed — un-spoofable. Cut-point algebra correct (single pre-loop `base`, worktrees from `HEAD`, `$built`-only iteration).
2. **Harness-neutrality — GREEN.** Pure git/sh on real diffs → governs live LLM + fixture identically. The only actor-specific surface is the fixture's opt-in conflict/rename modes, which feed the *same* detection path. shellcheck clean.
3. **Honest-ceiling — GREEN + 1 Low.** Claim/CHANGELOG/design carry the same honest qualifier (changed-file granularity; floor is git's; proven by golden-path on fixtures). No verb inflation. The non-atomic merge-floor residual + conservative `--no-renames` FP are documented (§7), the non-atomic one correctly attributed as a *pre-existing E3a* property. **Low:** §10 item-1 (FS scope) owner label still says "E3b/E4" though E3b declined FS-isolation — stale attribution (status text accurate).
4. **Right-weight / proportion — GREEN.** "No new gate" verified (shared verifier `orchestrator-loop-wired.sh`; proof rides existing selftest/golden-path; no gate-count drift). Not locking what git does — adds the three things git doesn't: proactive (clean tree), observable (`kit.conflict`), regression-locked. **FS-isolation→item-6 pivot legitimate:** E4a `containment-audit` already proves FS-scope behaviourally, so an E3b FS proof would be redundant (container) + hollow (live LLM); item 6 is real harness-neutral behaviour guarding a real regression.
5. **Integration-capability / no dead-ends — GREEN.** Re-sync procedure deferred with a named home (§7/§8, F5); atomicity follow-on banked with a concrete design; FS-isolation kept as harness-sandbox/E4. Fixture gained exactly two opt-in modes used by the proof — nothing speculative.

**Design-intent check:** nothing redundant or dead; the shared-verifier reuse is deliberate; the FS-isolation→item-6 pivot is legitimate.

## 3. Ledger 1 — verified-as-quality
Conflict detection non-vacuous (repro'd); `--no-renames` closure load-bearing (sabotage-proven); wiring teeth real; `kit.conflict` trusted-layer/un-spoofable; right-weight honored (no new gate, shared verifier, verify --selftest OK, shellcheck 104 files clean, claims-registry PASS both claims); cut-point algebra correct; honest ceilings all documented.

## 4. Ledger 2 — fix-forward
- **[Low · honesty] §10 FS-scope owner label stale** → re-label item 1 owner to "E4 (harness-sandbox; E3b declined)" in `orchestration.md` + `2026-06-26-e3a-...md`. **DISCHARGED pre-ship** (folded into this slice's apply.py).
- **[Low · banked] Atomic merge-floor reset** → snapshot + `git reset --hard <base>` (or scratch-branch fast-forward-on-success) so a floor trip leaves the branch pre-loop. Off-contract reachability only (detection-miss on a non-disjoint run). Routed to backlog `E3-merge-atomicity`.

## 5. Retro (the adjust step)
**Lesson:** *grounding a behavioural slice can reveal the proof is hollow before a line is written — and the right response is to pivot to a sounder slice, not to ship thin attestation.* E3b's first candidate (FS-isolation) was a tautology of docker's mount namespace (redundant with E4a; hollow for the live LLM); the owner pivoted to item 6 — real harness-neutral behaviour. The *proven-not-prescribed* thesis applied to slice **selection**, not just execution. **Proposed (human-ratified):** a one-line addition to the E3 spine design's slice-selection guidance — *"if a slice's only harness-neutral proof is a fixture tautology, re-select the slice."*

## 6. Routing
- §10 owner-label fix → DISCHARGED (apply.py). Atomicity → backlog `E3-merge-atomicity`. Retro slice-selection guidance → next E3 brainstorm (human-ratified). No re-plan; the FS-isolation→item-6 pivot is within the ratified "§10 items 1 & 6" scope.

## 7. Ready-to-commit (human ratifies)

**Verdict-log row** → append to `docs/governance/meta-control-log.md`:

```
| 2026-06-27 | 3.56.0 | E3b conflict-safe per-slice M verdict (A5) | light (5-lens) | GO-WITH-CONDITIONS | docs/architecture/2026-06-27-meta-control-7.md | 0 blockers · 0 highs · 2 Low (FS-scope owner-label DISCHARGED pre-ship; merge-floor atomicity banked). Teeth sabotage-repro'd (drop --no-renames → dueling-rename FAILs); kit.conflict trusted-layer/env-scrubbed; right-weight real (no new gate, shared verifier). FS-isolation→item-6 pivot legitimate (E4a proves FS-scope; item-6 is real harness-neutral behaviour). conflict-safe-integration holds. |
```

**Marker** → overwrite `docs/governance/.meta-control-last`:

```
3.56.0 GO-WITH-CONDITIONS
```
