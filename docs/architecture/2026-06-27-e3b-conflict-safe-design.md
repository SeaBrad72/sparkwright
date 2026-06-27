# E3b — conflict-safe parallel writes (architecture / design)

**Date:** 2026-06-27
**Epic / slice:** E3 → **E3b** (orchestration mechanics, §10 **item 6** — conflict-safe parallel writes). §10 item 1 (per-agent FS scope), atomic-claim, and WIP-limits are **deferred** (see §8).
**Status:** Design converged (brainstorm, owner-ratified 2026-06-27). Ready for the implementation plan.
**Tracked here** (not `docs/superpowers/specs/`) because later E3 slices depend on it and it must be resumable cold by a fresh instance — same rationale as the E3a / escalation designs.

**Reads-first for a cold resume:** the §10 containment contract (`2026-06-22-e3-agentic-orchestration-design.md` §10 item 6), the E3a loop this extends (`scripts/orchestrator-run.sh` integration block + `docs/operations/orchestration.md`), and the trusted-layer span discipline this reuses (`kit.denied` in `orchestrator-run.sh`, `kit.escalated` in the escalation slice).

## 0. Why this slice (not FS-isolation) — the decision trail

E3b's first candidate was **§10 item 1 (per-agent FS isolation)**. Grounding it showed the behavioural proof would be **hollow**: the only harness-neutral thing provable is that a *sandboxed fixture* (a deterministic script) stays in its mount — a tautology of docker's mount namespace that proves the actor *not* at risk, while the actor that *is* at risk (a live LLM subagent the loop can't containerize) rides the harness's own sandbox, structurally unprovable in a FLOOR. E4a's `containment-audit` already proves the container FS boundary that *is* meaningful. So FS-isolation would have been either behavioural theater or honest-but-thin attestation.

**Item 6 is the sound choice:** "two parallel writes can't silently corrupt shared state" is a real correctness property, **behaviourally provable end-to-end** (it inspects real git diffs, so it governs live *and* fixture engineers identically), not redundant with E4a, and it guards a real regression. It advances the kit's *proven-not-prescribed* thesis where FS-isolation could not.

## 1. What E3b is

Before integrating the parallel engineers' branches, the orchestrator **detects when two engineers' changed-file sets overlap** and **refuses to merge** — failing closed with an explicit, trace-visible signal *before* any corrupting merge. It turns git's implicit detect-by-failure into an explicit, proactive, observable, **locked** mechanic, so concurrent file-mutating agents can never silently corrupt shared state.

## 2. The gap it closes (honest about the existing floor)

Today, overlap → the sequential `git merge --no-edit "e3a/$slice"` conflicts → `exit 1` (the integration loop's `||` arm). The **no-silent-corruption floor already exists** via git's merge semantics — but it is:
- **post-hoc** — discovered mid-merge, leaving conflict state in the working tree;
- **unobservable** — no trace signal; the operate-loop never sees that a conflict happened;
- **untested** — nothing proves it; a regression to `git merge -X ours` (or a `--strategy` flag) would **silently drop a side** and CI would stay green.

Item 6 makes the guarantee **proactive** (refuse before merging), **observable** (a trace signal), and **regression-locked** (a behavioural proof).

## 3. The mechanic

After the engineers return (the `$built` branch list) and **before** the integration merge loop, in `scripts/orchestrator-run.sh`:

1. For each built branch, compute its changed-file set relative to the run's base: `git diff --name-only <base>..e3a/$slice` (base = the HEAD the worktrees were cut from).
2. Check for **intersection** across the built branches (any file claimed by ≥2 slices).
3. **Overlap → halt fail-closed:**
   - emit a **trusted-layer** `kit.conflict=true` span naming the file + the two slices (set only by the orchestrator from the computed sets — never agent-supplied, same discipline as `kit.denied`/`kit.escalated`);
   - print an explicit `conflict: slices 'X' and 'Y' both modified 'F' — refusing integration`;
   - stop **without attempting any merge** (the tree stays clean — no conflict markers).
4. **Disjoint → integrate** via the merge loop.

**Rename-divergence (closed at security review):** the diff uses **`--no-renames`** so a rename surfaces *both* the deleted source and the added target — two slices renaming the same source to different targets thus still collide on the source (a plain rename-detecting `--name-only` would see disjoint `{A}` vs `{B}` and miss it). **The merge loop is the fail-closed floor** for anything the changed-file granularity can still miss: on a merge failure it **aborts the half-merge (clean tree), removes worktrees, and emits the same trusted `kit.conflict` span** — so any residual git catches is *also* clean + observable, never a dirty tree with dangling worktrees.

This is **detection-by-inspection** replacing detection-by-failure: observable, regression-proof, clean-tree, and composing with the existing `kit.denied`/`kit.escalated` trusted-span pattern.

## 4. The proof (non-vacuous; extends the existing `orchestrator-loop` selftest)

- **Conflicting fixture mode:** `scripts/fixtures/engineer-fixture.sh` gains an opt-in — when `FIXTURE_CONFLICT_FILE` is set, it writes *that shared path* (with slice-specific content) instead of the slice-scoped `built-by-<slice>.txt`, so two slices genuinely overlap. Default behaviour (disjoint) is unchanged.
- **POSITIVE (existing):** disjoint fixtures (`alpha`, `beta`) integrate cleanly — already asserted by `orchestrator-run.sh --selftest`.
- **NEGATIVE (new):** two conflicting fixtures → overlap **detected**, run halts, a `kit.conflict=true` span is present, the merge is **not attempted**, and the shared file is **not silently single-sided** on the integration branch.
- **Non-vacuity:** the positive (disjoint integrates) **and** the negative (overlap detected + refused) together mean neither a dead loop (fails the positive) nor a detection-skipping regression (overlap silently merges → fails the negative) can pass. Same anti-vacuous structure as `kit.denied`.

## 5. Conformance — right-weighted (no new parallel gate)

Responding to the conformance-bloat critique (T3/T4): **no new `*-wired.sh` script.**
- **New claim `conflict-safe-integration`** (`claims.tsv`): "parallel-engineer writes to overlapping files are detected and refused before integration — no silent corruption; proven by golden-path on conflicting fixtures." Honest qualifier: *changed-file-set granularity; the no-corruption floor is git's, the mechanic makes it proactive + observable + locked.*
- **The behavioural proof lives in the extended `orchestrator-run.sh --selftest`** (the overlap case), run by the **existing `orchestrator-loop` golden-path job** (no new job).
- **The wiring assertion extends `conformance/orchestrator-loop-wired.sh`** — it additionally asserts the loop contains the conflict-detection (`git diff --name-only` overlap check) + the `kit.conflict` trusted span. The `conflict-safe-integration` claim's verifier is `orchestrator-loop-wired.sh` (one script, two claims — the registry allows a shared verifier).
- Wired into `verify.sh` / CI selftest / `drift-watch` / `doctor` via the existing orchestrator-loop entries (the extended lock covers it).

## 6. §10 status flip

Item 6: *"avoided — clean disjoint slices only"* → **"proven mechanic (E3b): overlap detected + refused before integration; trace-visible (`kit.conflict`); no silent corruption."** Updates the E3 spine §10 table + `docs/operations/orchestration.md`. Item 1 stays *used-not-enforced (container case proven by E4a; live = harness sandbox)*; items 2–5/7 unchanged.

## 7. Honest ceiling (named, not built)

- **Changed-file-set granularity** (`git diff --name-only --no-renames`) — detects two agents touching the *same path*, including renames of the same source (via `--no-renames`); it does **not** detect *semantic* conflicts between edits to *different* files (that is correctness review, not an integration mechanic). The **merge loop is the fail-closed floor** for any residual the changed-file check misses — it aborts + emits `kit.conflict` + cleans up, so even a missed overlap halts cleanly and observably (never a dirty tree). Stated plainly in the claim + ops doc.
- **Detect + refuse, not resolve** — the **full re-sync / precedence procedure** (rebase, retry, ordered precedence, partial integration) is **deferred** to a later increment when a real fleet needs graceful resolution (F5 — no dynamic-queue/large-fan-out need at N=2).
- **Governs live + fixture identically** — it inspects real git diffs, so the mechanic is genuinely harness-neutral behaviour for both a fixture and a live LLM engineer (this is *why* it was chosen over FS-isolation, whose meaningful case was unprovable in a FLOOR).
- **Conservative `--no-renames` false-positive** — a benign single rename (one slice renames F→G while another edits F) is *refused* even though git could auto-merge it. Fail-safe and on-contract (slices are meant disjoint; refuse-don't-resolve is the §7 posture) — accepted.
- **Non-atomic merge-floor residual** (security-review follow-on) — the sequential merge loop integrates slices one by one, so if the **fail-closed floor** trips on slice N (a conflict class the changed-file granularity can't see, e.g. file/dir-type — only reachable on a detection-miss, off the disjoint-slice contract), slices 1..N-1 are already integrated while N is refused. The tree is clean, worktrees are removed, and a `kit.conflict` span is emitted (observable, no corruption) — but the integration is **not atomic**. This is a *pre-existing* E3a sequential-merge property (not an E3b regression). **Banked follow-on:** snapshot before the merge loop and `git reset --hard <base>` (or integrate on a scratch branch, fast-forward only on full success) to make a floor trip leave the branch exactly as it was pre-loop.

## 8. Out of scope / deferred (named)

- **§10 item 1 (FS isolation)** — container case proven by E4a; live case = harness sandbox (an honest ceiling, surfaced in the E3a design). Not re-opened here (the per-worktree behavioural probe was rejected as hollow — see §0).
- **Atomic-claim / WIP-limits** — no dynamic-work-queue need at N=2 (disjoint slices assigned upfront); F5 build-ahead; deferred.
- **Graceful conflict re-sync/precedence** (§7) — deferred; this slice detects + refuses.
- **EC3** (escalation: `escalate.sh` expose ratifier so the loop stops re-deriving the verdict slug) — its own micro-slice; unrelated to integration.

## 9. Build approach

- **Control-plane** (`scripts/orchestrator-run.sh` edit, `scripts/fixtures/engineer-fixture.sh` conflict mode, `conformance/orchestrator-loop-wired.sh` + `conformance/claims.tsv` + `conformance/claims-registry.sh` REQUIRED_IDS + `conformance/verify.sh` label, the §10 design + `orchestration.md` edits) → built **AMBER**: `scratchpad/e3b-conflict-safe/apply.py`, clone dry-run incl. `conformance/shellcheck.sh`, **dual review** (reviewer + security-reviewer — security lens: is `kit.conflict` trusted-layer / un-spoofable? is the overlap detection *complete* — can an engineer evade it, e.g. via rename/mode-only/symlink edits? does it fail closed when `git diff` errors?). **Light 5-lens meta-control panel** (per-slice A5). Version finishing folded into `apply.py`. Both `orchestrator-run.sh` and `engineer-fixture.sh` are already control-plane (guard `is_control_plane_path`); no new guard entry needed.
- **Release:** `commit → push → PR → merge → sh scripts/release-tag.sh` (the human; agent stops at hand-off per `merge-tag-authority`).

## 10. Convergence record (owner-ratified 2026-06-27)

Item 6 chosen over FS-isolation (FS-isolation's provable case is hollow; item 6 is real behaviour, harness-neutral end-to-end — §0). Mechanic = **proactive detect-by-inspection** (changed-file-set overlap before merge) with a trusted-layer `kit.conflict` span + fail-closed halt, replacing implicit detect-by-failure. Proof = extend `orchestrator-run.sh --selftest` with a conflicting-fixture overlap case (non-vacuous: positive disjoint-integrates + negative overlap-refused). Conformance right-weighted (extend `orchestrator-loop-wired.sh` + one claim, no new gate). Re-sync procedure + atomic-claim/WIP + FS-isolation re-open + EC3 all deferred/split. **Next: the implementation plan (writing-plans).**
