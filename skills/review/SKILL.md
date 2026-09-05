---
name: review
description: Use when reviewing a diff or PR before merge — the kit's own code-review skill (replaces, does not depend on, superpowers requesting-code-review). The reviewing craft: adversarially verify each finding, filter by confidence, judge against the kit's standards, and emit one honest verdict. Wired to the Reviewer seat (and the security-reviewer's security lens).
---

# Review — the reviewing craft: adversarial, confidence-filtered, honest

The kit's own code-review skill: how to review a change well. The Reviewer seat's craft (the security-reviewer applies the same craft through a security lens). Replaces (does not depend on) superpowers `requesting-code-review`. The *requesting/dispatch* side (convening a reviewer) is the Orchestrator's job, not this skill.

<!-- The frontmatter and discipline headings below are conformance-load-bearing:
     conformance/orchestrator-loop-wired.sh greps this file for kit-distinctive markers
     (name: review, ## When to use, Confidence, adversarial, builder, NEEDS-FIXES).
     conformance/doc-markers.sh validation-terminal-state additionally greps for the third
     terminal state (FAITHFUL-FAILURE) + its cross-surface markers.
     Edits that drop or rename them can turn the skill-spine lock RED. -->

## When to use
After each task in subagent-driven development, after a feature, and always before merge to main. Review early, review often — catching an issue early beats debugging a cascade later.

## The craft (the proven spine)
1. **Review a crafted diff, not the author's history.** Look at the change (the diff + the requirements it claims to meet) with fresh eyes — you did not write it.
2. **Judge against the rubric:** correctness + unhandled edge/error cases; DEVELOPMENT-STANDARDS §2 (security) and §5 (code quality); the §14 CI gates; tests that cover the change and assert behaviour, not implementation.
3. **Group findings by severity** — Critical / Important / Minor — each with `file:line` and a concrete fix.
4. **Emit one honest verdict — APPROVE or NEEDS-FIXES.** Fix Critical/Important before proceeding; note Minor.

## The kit's review disciplines (what makes this MORE than generic code review — apply to EVERY review)
- **Adversarially verify each finding before you report it.** Try to *refute* it: does the bug actually reproduce, is the `file:line` real, would the fix matter? A finding you cannot substantiate is noise — drop it or downgrade it. This is the kit's non-vacuity law at the review level: a finding that cannot be made to fail is not a finding. Honest adversarial verification is the heart of the craft.
- **Confidence-based filtering — signal over nitpicks.** Report only what you are confident matters. A review buried in style Minors hides the one Critical. Bikeshedding is a failure mode, not thoroughness.
- **The builder is never the reviewer.** Independence is the point — the builder never reviews-and-merges its own work (DEVELOPMENT-PROCESS §12). Two lenses review in parallel: the Reviewer (correctness/standards) and the security-reviewer (the §7 security gate).
- **Review behaviour, scoped to the diff.** Assert behaviour, not implementation detail; do not expand scope beyond the change; do not re-litigate decisions the plan already made — raise them as findings and let the owner adjudicate.
- **Grade the operator-facing prose of a gate with the gate.** Check-run text, refusal messages, and recording instructions are part of the mechanism — a gate whose prose instructs a retired workaround fails on its first live subject (meta-control #41 retro-3, from the C8 reviewer HIGH).
- **Fix the class, not the instance.** Every fix has twins: the sibling function, the sibling profile, the sibling selftest, the sibling doc. Ask of each fix "which one is this fix's twin?" — then name the twin and grade it, or state why there is none. A fix applied at one site while its twins keep the defect is how a closed row reopens under a new number (this is why the K10 sweep found the same broken SBOM command in three profiles when the row named two).
- **Honest verdict — never rubber-stamp.** NEEDS-FIXES on any real Critical or Important. An APPROVE means you would stake the merge on it.

## Push back
If a finding is wrong, the author pushes back with technical reasoning (code or tests that prove it works) and the reviewer adjudicates. A finding that contradicts what the plan mandates is the owner's call — surface it; do not silently drop or enforce it.

## Terminal state
**A file, not only a message.** The review record `docs/reviews/<date>-<row-slug>.md` (from `templates/REVIEW-RECORD-TEMPLATE.md`), **appended per round** — one Rounds row per round naming the commit reviewed, the seat, the verdict and the finding count — plus the severity-grouped findings list (each `file:line` + concrete fix) and one verdict — APPROVE or NEEDS-FIXES — returned to the Orchestrator for routing. Since `LOOP-STAGE-ARTIFACT-GATE` (2026-09-04) the file is graded: `conformance/review-lane.sh` refuses a record whose Builder equals its Reviewer, whose rounds cite commits outside the PR, whose last round is not APPROVE, whose findings lack a disposition in the grammar (`fixed <sha>` · `accepted — <reason>` · `waived — WAIVER-<id>`) — and a `fixed <sha>` must name a commit **inside this PR**, or it is refused (`RL-FIX-OUTSIDE`): a fix outside the PR is a fix this PR does not carry — whose design-promised controls do not resolve to an executable `path::test-name`, or which carries no security-review verdict. **The record alone is self-attested** (`D-240805-3`) — what makes it evidence is a non-author **Approve on the graded head**. The approver types nothing (`D-240904-2`), and since `REVIEW-LANE-WAITING-IS-GREEN` (2026-09-05) it is **branch protection**, not `review-lane`, that enforces it: `dismiss_stale_reviews` means an approval carried across a fix push does not count, and `require_last_push_approval` means the pusher cannot approve their own push. The reviewer reports; it never merges. Before the human Go/No-Go, if the change carries a taste-surface, ensure the increment was demonstrated for the human's taste judgment (`skills/demonstrate`) and its verdict recorded — correctness review alone does not answer whether it is *good*. The reviewer's verdict is a `basis:` input to the human GO; it never ratifies — `builder ≠ ratifier` (peer to `builder ≠ reviewer`), and actuation follows **approve→execute→log** (execute + log + verify `shipped == approved`).

## Validation-task terminal state — FAITHFUL-FAILURE (the third verdict)
A **third** terminal state, available ONLY when the task under review declares its class in its **Task Context Contract** (§12).
That declared class must be **validation / field-test**. For an ordinary implementation task the APPROVE / NEEDS-FIXES binary above is unchanged — FAITHFUL-FAILURE is opt-in and never the default.

- **FAITHFUL-FAILURE** — the validation task was executed *faithfully* (methodology correct, cold-integrity held) AND it surfaced a real defect in the **subject-under-test**. **The test succeeded; the subject failed** — this is NOT an implementation failure and NOT NEEDS-FIXES.
  - **Requires:** the discovered defect(s) are routed to the **originating backlog** via the feedback ledger (`KIT-FEEDBACK` / `FIELD-REPORT`) — logged out-of-band, not lost.
  - **Forbids (cold-integrity):** the reviewer must NOT prescribe or perform a repair of the **subject-under-test** inside the vehicle — a repair in the vehicle contaminates the evidence and voids the test. Route it out; never fix it in place.
  - **faithful methodology is the precondition** — a validation task run *un*faithfully, or one that repaired what it was exercising, is `NEEDS-FIXES` as usual, so the verdict cannot be used to dodge a real fix.

**Honest ceiling:** this doctrine is documented and locked for coherence; whether a live reviewer applies it correctly is un-gateable (as with `skills/using-skills`' auto-load convention).
