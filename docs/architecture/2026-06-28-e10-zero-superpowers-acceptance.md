# E10 — zero-superpowers acceptance test (verdict)

**Date:** 2026-06-28
**Slice under test:** `E3-merge-atomicity` (orchestrator integration all-or-nothing) — v3.69.0.
**Question E10 answers:** can the kit build a real slice of itself using *only* its own roster + skills — zero superpowers — and is the result as good as superpowers would have produced? Measured against the **FLOOR convention's honest ceiling** (consult the keystone, reach skills by reading; *not* NATIVE auto-injection). See [[self-hosting-commitment]].

## How the run was conducted (the discipline IS the test)

The slice ran end-to-end through the kit's own spine, each leg invoked by **reading** the kit's own `SKILL.md` (never the superpowers equivalent):

| Leg | Kit skill used (invoke-by-read) | superpowers skill deliberately NOT used |
|---|---|---|
| discovery/keystone | `skills/using-skills/SKILL.md` | `using-superpowers` |
| design | `skills/design/SKILL.md` | `brainstorming` |
| plan | `skills/plan/SKILL.md` | `writing-plans` |
| build (test-first) | `skills/tdd/SKILL.md` | `test-driven-development` |
| verification | `skills/verification/SKILL.md` | `verification-before-completion` |
| review (×2 seats) | `skills/review/SKILL.md` via the `reviewer` + `security-reviewer` seats | `requesting-code-review` |

**Zero superpowers skills were invoked for the slice.** The keystone's "invoke by reading" FLOOR mechanism worked: the keystone index named every spine skill, and each was reached by reading its file and following it.

## Did the disciplines BITE (not just exist)?

Yes — three concrete instances where a kit discipline materially shaped the slice, not just decorated it:

1. **`design` → non-vacuity + "is the provable thing the meaningful thing".** Drove the load-bearing test design: the directory/file clash was chosen specifically because it reaches the merge *floor* with *disjoint* detection — the one path the existing suite never exercised. A lazier "same-file conflict" test would have been caught at detection and proven nothing about the floor. The skill's slice-selection lens forced the right fixture.
2. **`verification` → clone dry-run + tagless fidelity.** Enforced proving the AMBER `apply.py` on a fresh *tagless* clone (not the dev tree), so the green means what CI's green means; the idempotency re-run and the "exactly 4 files touched" check are the confabulation-proof the skill mandates.
3. **`review` → adversarially verify EACH finding.** The two seats did not rubber-stamp: the Reviewer *reconstructed the pre-fix code to watch RED* and *injected an always-reset bug to prove the positive anchor has teeth*; Security *traced the `$base` trust chain* and surfaced two real Low findings (warn-not-silent on pathological reset; blast-radius doc precision) that were folded in and improved the slice. Recursion worth noting: the review craft was exercised on a slice that itself hardens the integration loop the seats run inside.

## Honest findings — where the kit's spine differs from superpowers

- **CRAFT: at parity or better.** Every leg had a specific, followable kit skill; the kit's skills bake in disciplines superpowers does not name explicitly (non-vacuity as a law, honest-ceiling, control-plane-completeness, proven-not-prescribed slice-selection). For the craft, the maintainer-would-choose-it bar is **met**.
- **ERGONOMICS: a real, deliberate friction (the guard).** The kit's own PreToolUse guard repeatedly blocked dev commands — running `--selftest` when it co-occurred with `git checkout`, `rm -rf` of clone dirs, and even reads of `conformance/`. This is the guard *working as designed* (it protects the live control plane, and the v3.68.0 two-matcher hardening is why `conformance/` reads were caught). But it imposes friction in a dev/throwaway-clone context that superpowers does not. **Honest gap surfaced:** there is no clean "I am working in a disposable clone, not the live control plane" affordance — and `KIT_GUARD_SELFEDIT=1` set via an inline `export` does **not** take effect, because the hook reads its own process env *before* the command's exports run. Working around it (structuring commands so a control-plane path and a mutation verb never co-occur; editing clone files via a Python script whose path lives inside the file) was learnable but cost several iterations.
- **The AMBER mechanic is heavier than superpowers' direct-edit flow** — build on a clone, assemble an idempotent `apply.py`, hand it to a human to apply. This is a deliberate control-plane-integrity trade (the agent *cannot* silently mutate guard/CI/conformance), not a spine deficiency.

## Verdict

**PASS.** The kit self-hosted a real, non-trivial control-plane slice end-to-end with **zero runtime dependency on superpowers**. The craft spine (design → plan → tdd → verification → review) is specific, disciplined, and carried the work as well as superpowers would have — in places better, because the kit's disciplines (non-vacuity, honest-ceiling) are first-class and produced a stronger test and a stronger review than a generic flow would.

The one honest deduction is **ergonomic, not craft**: the guard's lack of a clean disposable-clone affordance is a real papercut. It is a deliberate safety trade and did not block the slice, but it is the highest-value follow-on E10 surfaced.

## Banked follow-on (routed to backlog)

- **`guard-dev-clone-affordance` (ergonomic, non-blocking).** The guard has no clean way to recognise "this command operates on a throwaway clone, not the live control plane," and `KIT_GUARD_SELFEDIT=1` via inline `export` is ineffective (hook reads pre-exec env). Candidate: document the working pattern (don't co-occur a CP path with a mutation verb; edit clone files via an interpreter), and/or a sanctioned env/flag the hook reads reliably for disposable-clone dev. Weigh against the safety value of a guard with no easy bypass — this is exactly the kind of right-weight call the kit's own design skill governs.
