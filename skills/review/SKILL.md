---
name: review
description: Use when reviewing a diff or PR before merge — the kit's own code-review skill (replaces, does not depend on, superpowers requesting-code-review). The reviewing craft: adversarially verify each finding, filter by confidence, judge against the kit's standards, and emit one honest verdict. Wired to the Reviewer seat (and the security-reviewer's security lens).
---

# Review — the reviewing craft: adversarial, confidence-filtered, honest

The kit's own code-review skill: how to review a change well. The Reviewer seat's craft (the security-reviewer applies the same craft through a security lens). Replaces (does not depend on) superpowers `requesting-code-review`. The *requesting/dispatch* side (convening a reviewer) is the Orchestrator's job, not this skill.

<!-- The frontmatter and discipline headings below are conformance-load-bearing:
     conformance/orchestrator-loop-wired.sh greps this file for kit-distinctive markers
     (name: review, ## When to use, Confidence, adversarial, builder, NEEDS-FIXES).
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
- **Honest verdict — never rubber-stamp.** NEEDS-FIXES on any real Critical or Important. An APPROVE means you would stake the merge on it.

## Push back
If a finding is wrong, the author pushes back with technical reasoning (code or tests that prove it works) and the reviewer adjudicates. A finding that contradicts what the plan mandates is the owner's call — surface it; do not silently drop or enforce it.

## Terminal state
A severity-grouped findings list (each `file:line` + concrete fix) and one verdict — APPROVE or NEEDS-FIXES — returned to the Orchestrator for routing. The reviewer reports; it never merges.
