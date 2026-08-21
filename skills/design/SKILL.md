---
name: design
description: Use BEFORE any creative or feature work — turning an idea, request, or epic into a validated, owner-approved design/spec. The kit's own design+brainstorm skill (replaces, does not depend on, superpowers brainstorming). Establishes intent, requirements, approaches, and an approved design before any implementation.
---

# Design — turn an idea into a validated, honestly-scoped design

The kit's own design skill: take an idea → a design the owner has approved, through collaborative dialogue plus the kit's design disciplines. Replaces (does not depend on) superpowers `brainstorming`.

<HARD-GATE>
Do NOT write code, scaffold a project, or take any implementation action until you have presented a design and the owner has approved it. Every slice, however simple. A "simple" change gets a short design — but it is still presented and approved.
</HARD-GATE>

### Inception exception (Phase 0 is not a loop feature)
The HARD-GATE above governs **loop** work — features, components, behaviour changes. It **does not
govern Phase-0 Inception**: running `incept` is the one-time bootstrap that *creates* the repo and its
control plane, not a loop feature. Inception has its own design gate (the charter + ADR-000, fit/maturity-
disclosed and conformance-enforced; see `DEVELOPMENT-PROCESS.md` §3), satisfied *within* Inception — so
architecture-first still holds at Phase 0, it is simply gated there. **Do not commit a spec before
`incept`** — there is no repo yet, and a pre-incept commit breaks `inception-done`'s fixture build.
`incept`'s ownership/guard refusals stay in force.

<!-- The frontmatter and the discipline headings below are conformance-load-bearing:
     conformance/orchestrator-loop-wired.sh greps this file for kit-distinctive markers.
     Edits that drop or rename them can turn the skill-spine lock RED. -->

## When to use
Before any feature, component, behaviour change, or new project — the moment implementation would otherwise begin.

## The flow (the proven spine)
1. **Explore context first** — read the codebase, the kit's principles (`CLAUDE.md` / `DEVELOPMENT-STANDARDS.md`), recent commits, the relevant design docs. Never design from assumptions.
   **Search the decision record — `docs/governance/DECISIONS.md` — for a prior ruling on the surface you are about to change, and cite it by row identifier before proposing a mechanism on it.** A conclusion re-derived from scratch is the disease that record exists to cure; the ruling may already answer you, or already have vetoed you.
2. **Clarify — one question at a time** (multiple-choice where possible): purpose, constraints, success criteria. Do not batch questions.
3. **Propose 2-3 approaches** with trade-offs; lead with a recommendation and why.
4. **Present the design in sections** scaled to complexity; get approval per section.
5. **HARD GATE — owner approval before any implementation.**
6. **Write the spec** to `docs/architecture/<date>-<topic>-design.md` (tracked, cold-resumable) or `docs/superpowers/specs/` (local); commit it.
7. **Self-review the spec** — placeholders, internal consistency, scope, ambiguity; fix inline.
8. **Owner reviews the written spec**, then hand to the **plan** skill. Do NOT start implementation from this skill.

## Design provenance — four sources, two artifact shapes
A design does not have to be *authored* by the slice that is governed by it. Provenance and artifact are different things:

| # | Provenance of the design | The slice's design act |
|---|---|---|
| P1 | Authored in this slice | **originate** it (steps 1-8 above) |
| P2 | Provided by the owner | **review + confirm** it |
| P3 | A previous slice, or an initiative design of record | **review + confirm** it |
| P4 | A backlog story carrying a reviewable design link (tracker-hosted — Jira et al.) | **review + confirm** it |

**The invariant:** whatever the provenance, the slice commits an **in-repo design artifact**, and that artifact is what the design GO binds to. For P1 that artifact is an **originating design**; for P2-P4 it is a **confirming design**. Both are full design artifacts of equal standing — they differ in content, never in status. A slice governed by an already-ratified design therefore never has to choose between churning that document and skipping the design stage: it writes a confirming design instead.

A **confirming design** records a judgment, and must carry:
- **What it confirms** — a *stable* reference to the source: repo path + section for P2/P3; for a tracker-hosted or otherwise out-of-repo source, the URL **plus** the story key **plus** the page/revision id — never a bare link.
- **Captured substance** — for an out-of-repo source, enough of the design's substance that the confirmation still means something if the source is changed, restricted, or deleted. An out-of-repo design is mutable and this repository cannot see it change.
- **Scope coverage** — does that design actually govern *this* slice's scope, or is there a gap?
- **Sizing** — does the inherited estimate still hold for this slice? This is the cheapest place to catch a mis-sized slice, and the place it has been missed.
- **Deltas** — what differs from the inherited design, or explicitly *none, and why*.
- **Obligations inherited** — the contracts this slice must carry forward.

**Ceiling — a confirming design can degrade into a rubber stamp, and that is NOT enforceable.** Judging whether a confirmation embodies real judgment is semantic, and a prose scanner over design documents is a standing veto in this kit. What a green design gate establishes is **narrower than it looks**: a substantive artifact exists, and a GO scoped to this change names it, with an approver identity matching that artifact commit's git *committer* field. The artifact's **coverage of this scope is NOT checked** — no predicate relates the artifact's content to the change — and the identity is **git-attested, not authenticated** (a note binds; it does not authenticate). Never read a green as "the design was reviewed well", never as "this design governs this change", and **never as "a human approved this design"** — an identity matching the commit's *committer* field can be an agent running under the owner's configured git identity, or **the forge itself** (a squash-merge commit's committer is the forge, and naming it satisfies the derivation; measured 2026-07-29).

<!-- The bold lead-in above deliberately reads "Ceiling" and NOT the two-word phrase used by the discipline
     bullet further down: conformance/orchestrator-loop-wired.sh anchors this file on that phrase, and a
     SECOND occurrence anywhere in this file silently disarms the lock — measured 2026-07-29, the lock
     returned rc 0 with the discipline bullet deleted. Keep that phrase to exactly ONE occurrence here.
     ⚠️ A comment quoting the phrase to explain this rule ALSO counts: that mistake was made and caught. -->

## The kit's design disciplines (what makes this MORE than generic brainstorming — apply to EVERY design)
- **Architecture-first.** Design and trade-offs before code; hand the owner the 5-10 lines of meaningful business logic, not boilerplate.
- **Design-intent lens — default-KEEP.** "Low usage / few references" is NOT a cut reason; cut only what is genuinely redundant (content exists elsewhere) or dead. Front-load rigor.
- **Is the provable thing the MEANINGFUL thing?** Before committing a slice, ask whether the proof you can build establishes the thing that matters or an easier adjacent thing. If the only harness-neutral proof is a tautology, or it re-proves an existing slice, or the value is mostly future/declarative → **RE-SELECT the slice.** (Proven-not-prescribed applies to slice *selection*, not just execution.)
- **Agents-vs-skills rule.** A standing agent (seat) is earned only by a distinct skill AND (distinct tools OR must-run-parallel/independent); otherwise it is a skill a seat invokes. Few agents, many skills.
- **Honest ceiling.** Name what is behaviourally provable versus attestation. Never let a green check imply more than it proves; state the ceiling in the design.
- **Non-vacuity.** Every proof needs a positive liveness anchor AND a load-bearing negative — a dead or always-pass mechanism must fail the test.
- **First-live-run dogfood.** A slice shipping a new mechanism records that mechanism's **first live run on its own slice** in the design's §10 amendment log — the mechanism's first real subject is the change that ships it (adopted `D-240811-2.4` from meta-control #39, where four consecutive first-runs each caught or honestly disclosed something: the scope leg caught its own brief's omission; the marker sweep redded its own CHANGELOG).
- **Control-plane completeness.** When a slice makes a path control-plane (the guard must protect it), lock it in all three guard matchers (`is_control_plane_path` for the Write/Edit path AND the two shell-redirect regexes) AND add an agent-autonomy fixture per mutation form (Write/Edit, `>` redirect, `sed -i`). This completeness gap has recurred 3 times and is caught only by security review — design it in up front.
- **Enumeration boards its detection sibling.** A check whose domain is an enumerated idiom (a verb lexicon, a skip-idiom list, a citation grammar) boards its detection-shaped sibling row at ship time, or states in the design why the enumeration is complete — three residuals of this class shipped in one phase (meta-control #41 retro-1).
- **Right-weight / anti-ceremony.** Prefer extending an existing gate to adding one; defer build-ahead (no infrastructure for needs that do not exist yet). **A design that adds a new `conformance/*.sh` must NAME the existing check it considered extending and why extension fails** — a surfaceable answer, the same shape as the enumeration bullet above, not a preference. Measured: as a bare preference this sentence did not bind — the 35 days after it shipped added 30,981 conformance lines and 39 new checks. `conformance/conformance-mass-budget.sh` is what makes the answer load-bearing: a new file costs a ratified `MAX_FILES` raise plus its ack line in `conformance/mass-acks.txt`, so growth without the answer simply reds. The gate can only tell that growth was *declared*; whether the answer is honest is the reviewer's job.
- **Progressive disclosure.** Make the rigorous path the default, surfaced progressively — a novice is not crushed, an expert is not constrained.

## Decompose if too large
If the request spans multiple independent subsystems, decompose into sub-projects first and design the first through this flow. Each sub-project gets its own design → plan → build cycle.

## Terminal state
A committed, owner-approved spec, handed to the **plan** skill. This skill never starts implementation. The committed spec **names the backlog item it satisfies** — the requirements → backlog trace link — and, when it is a **confirming** design, also names the design it confirms.
