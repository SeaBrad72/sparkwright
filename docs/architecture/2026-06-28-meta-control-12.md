# Meta-control panel #12 — skill-spine brick #5 (the kit's own `worktrees` / isolation skill)

**Date:** 2026-06-28
**Trigger:** per-slice M verdict (condition A5) for skill-spine brick #5 (v3.61.0).
**Profile:** light (5-lens).
**Verdict:** **GO.**

Brick #5 = the kit's own `worktrees` (isolation) skill (`skills/worktrees/SKILL.md`), a harness-neutral `using-git-worktrees`-equivalent (the isolation craft), FLOOR-only, wired to the **Orchestrator** seat (the seat that creates/ensures isolation). **Designed by dogfooding `skills/design/SKILL.md` and planned by dogfooding `skills/plan/SKILL.md`** — 4th self-host use. Built AMBER; dual-reviewed (reviewer APPROVE + security-reviewer PASS); independently proven on a clone (selftest 12/12, `verify --require` 31 controls / 0 failed, idempotent, Engineer def byte-unchanged [single-seat parity], bricks #1–4 preserved). The panel independently sabotage-reproduced the "generic paraphrase fails" claim (a name+native-only generic copy → exit 1).

## The 5 lenses

| Lens | Verdict | Evidence |
|------|---------|----------|
| Scope-coherence & proportion | GREEN | Lightest-possible increment: no new gate, no new claim row, no new guard. Reuses the `skills/*` glob + the single `skill-spine` claim + the shared `orchestrator-loop-wired.sh`. Orchestrator wiring is not a forced fit — `agents/orchestrator.agent.md` already said "Set up an isolated worktree per fanned-out Engineer" and tools already list `git (worktrees, merge)`; the skill makes a pre-existing responsibility concrete. The isolation mechanism is live (orchestrator-run.sh fan-out + E3b conflict-safe), so not ceremony on an empty surface. |
| Honesty & over-claim | GREEN | CHANGELOG/claim scoped to "toward full replacement (zero runtime dependency on superpowers)" — gated on E10, not claiming completion. Honest ceiling explicit + consistent across `SKILL.md` ("bounds blast-radius; NOT a security sandbox … cleanup best-effort/harness-owned"), CHANGELOG, and `docs/operations/orchestration.md`. No claim a worktree is a security/trust boundary. |
| Enforcement integrity (green-while-dark) | GREEN | Cases 11/12 load-bearing (selftest 12/12; case 11 drops `disjoint file sets` → exit 1; case 12 omits the Orchestrator reference → exit 1). Adversarial probe: a generic `using-git-worktrees` paraphrase (name+native only) is rejected exit 1 (missing `disjoint file sets`, `--no-renames`, `out-of-slice`). Gate teeth rest on the 3 high-entropy markers, not `native`. `grep -qF --` correctly terminates option parsing for `--no-renames`. |
| Direction & sequencing | GREEN | The fork (worktrees before verification-before-completion) is owner-ratified on clean single-seat ownership of an already-live mechanism; cross-cutting v-b-c deferred to #6 to avoid an artificial seat-wired verifier leg. Spine intact: #6 verification-before-completion → the `using-superpowers`-equivalent discovery keystone → E10. No accretion; nothing to resequence/merge/drop. |
| Right-weighting & adoptability | GREEN | ~40-line markdown SKILL, FLOOR-only invoke-by-read, progressive (when-to-use → detect-first → native-first → parallel-safety → conflict-safe → boundary → metering → honest ceiling). Invisible to a vibe-coder until they fan out; a precondition discipline for an architect. Rigor has not outrun fit for a guidance file. |

Standing "integration-capability / no-dead-ends" lens: **N/A** — no industry-standard integration surface (pure-markdown FLOOR skill).

## Findings

- **0 blockers · 0 High.**
- **2 Low — confirmed non-blocking, no fix (both = the dual-review Minors, independently re-confirmed):**
  - **L1 — `native` is a low-entropy marker.** The generic-paraphrase probe *contained* `native` yet was still rejected (the 3 distinctive markers carried the teeth). Dropping `native` to a 4-marker set would change no verdict; keeping it is harmless brick-#1–4 parity. Not load-bearing, not a weakness. Banked: consider trimming at a future brick (cosmetic; do not churn this slice).
  - **L2 — submodule-guard not grepped.** The skill names the submodule guard in prose but it is not a verifier marker. 5 markers already meets brick-#1–4 parity; not every discipline needs a grep tooth. Acceptable.
- **Enforcement caveat (standing, not a finding):** the check is a declaration check — a hollow stub stuffing all 5 marker strings passes. Identical to bricks #1–4 and named in the design's honest ceiling ("quality un-gateable — correct for a skill"). A markdown guidance file has no behaviour to verify; the teeth catch the realistic threat (a lazy generic copy), not an adversary who deliberately imports the kit's own distinctive phrases.

## Two ledgers

**Ledger 1 — verified-as-quality (ship with confidence):** apply clean + idempotent on a fresh clone (re-run no-op, VERSION pinned 3.61.0); `verify --require` 31 controls / 0 failed / 0 unverified; shellcheck clean; selftest 12/12 with cases 11/12 proven load-bearing; "generic paraphrase fails" sabotage-reproduced; bricks #1–4 intact + Engineer def byte-unchanged (single-seat parity); honest-ceiling consistent across SKILL/CHANGELOG/orchestration.md.

**Ledger 2 — fix-forward (ranked):** nothing blocking. Optional/banked: (a) trim `native` from the marker set at a future brick to keep markers maximally high-entropy (cosmetic); (b) if a later brick adds real isolation *behaviour* (worktree creation in a script), revisit a behaviour-level selftest — out of scope for a FLOOR skill.

## Retro

- **The skill-spine has reached steady-state economics.** Bricks #1→#5 each cost exactly: 1 new SKILL.md + 2 selftest cases + extend the shared verifier + extend the one `skill-spine` claim + version finishing — **zero new gates/claims/guards across five slices.** The increment isn't accreting ritual; it's amortizing one piece of infrastructure five times. The "no new gate, reuse the glob+claim" discipline (banked at brick #1) held.
- **The full core SDLC loop plus its isolation wrapper is now kit-self-hosted:** design → plan → build(tdd) → review (the loop) + worktrees (the wrapper) all exist as kit-authored skills; this slice was itself designed+planned by the kit's own design/plan skills (4th self-host). The remaining bricks (#6 verification-before-completion, then the discovery keystone) are the wrapper, not the core.
- **Standing process held:** governance close folds INTO the feature PR; release-tag only after `git checkout main && git pull`.

**Next spine brick: #6 = verification-before-completion** (the evidence-before-claims discipline this session has lived), then the `using-superpowers`-equivalent discovery keystone → **E10 zero-superpowers acceptance.**
