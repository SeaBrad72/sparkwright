# Slice 9 Arc — Honest Assurance & Adoption Reach (remediation roadmap)

**Source:** the 9-agent independent review at [docs/superpowers/reviews/2026-06-09-independent-multiagent-review.md](superpowers/reviews/2026-06-09-independent-multiagent-review.md).
**Goal:** close every gap that review found, in priority order, until the kit's headline — *"drop into a regulated, PBS-scale, children's-data org with relative assurance that agents cannot cause damage"* — holds end-to-end, not partially.
**Method:** each sub-slice runs the kit's own loop (brainstorm → spec → plan → subagent build → PR → **human ratification** → merge). Analysis runs that *inform* a fix are scheduled immediately before it. We close the arc by **re-running the same 9-agent review** to prove the gap is gone.

**Economics baseline (measured 2026-06-09):** an agent operating by-the-book carries **~24K tokens** of standing governance per feature (core 3 docs ~16.5K + global 2 ~4.6K + 1 profile + 2 templates), before reading any feature code. Whole-kit weight ≈ 21,880 lines of Markdown. This is the number R11 must move.

**Versioning note:** most slices are additive → MINOR (2.25.0+). One slice (**9j**) contains a genuine fork — *promote a11y/load/eval to universally-required CI gates* (a new required gate = **MAJOR / realizes a clean 3.0.0**) **vs.** *honestly demote them in the DoD to human-attested rows* (MINOR). Decision taken at 9j brainstorm.

---

## The stepped plan

Legend: **B** = build slice (loop pass) · **A** = analysis run (no production change; produces a findings artifact) · Sev = highest finding severity addressed.

### Stage I — Empirical baseline (fast, grounds everything)
| Step | Type | What | Informs | Status |
|------|:----:|------|---------|--------|
| **A1** | A | Token-economics instrumentation — static surface measured; optional deeper pass measures a real feature transcript's governance load | 9k, economics tier | **baseline done** (~24K/feature) |
| **A6** | A | Empirical dogfood timing — actually run `incept.sh` in clean temp repos on 2–3 stacks, walk one feature end-to-end, capture real time-to-first-feature + every friction point | 9f, 9g (validates the doc-read persona inferences) | pending |
| **A3** | A | Cross-doc consistency linter — sweep 21.8k lines for claim/version drift the link-checker can't catch (badge≠VERSION, Stage 1–4 dangling ref class) | 9a, 9k (the check becomes a tool) | pending |

### Stage II — Tier 0: protect the spirit (false-assurance + safety holes)
| Step | Type | What | Sev | Ver |
|------|:----:|------|:---:|:---:|
| **A2** | A | **Adversarial guard red-team** — *do, don't read*: fuzz destructive patterns, encodings, quoting, MCP-tool paths against the live guard; enumerate every bypass (review already found 5: `find -delete`, `truncate`, `shred`, single-file `rm`, exfil) | — | — |
| **9b** ✅ | B | **Guard hardening & scope** (R2) — *shipped v2.25.0.* Red-team battery 16%→~91%; best-effort self/control-plane protection (closes the self-disable P0 via common verbs/paths; interpreters remain the documented tail); honest reframe; partial exfil + capability-family cloud rules; real boundary documented as Org-owned (`platform-safety-boundary.md`). Residuals by design: interpreter-exfil + var-indirection (deliberate-evasion → platform boundary). MCP-tool coverage deferred to 9d (runtime portability). | P1 | MINOR ✅ |
| **9a** ✅ | B | **Conformance honesty** (R1) — *shipped v2.26.0.* Three-state `branch-protection.sh` (no silent pass; UNVERIFIED=exit 2; CI/`--require`→FAIL); new `verify.sh` classified aggregate ([control] vs [doc]) with an honest footer; README taxonomy + "what a green run means". Surfaced a real gap: the kit's own `main` is unprotected (repo-admin follow-up). Evidence-artifact slots deferred (depth, not Tier-0). | P2 | MINOR ✅ |

### Stage III — Tier 1: adoption reach
| Step | Type | What | Sev | Ver |
|------|:----:|------|:---:|:---:|
| **9c** ✅ | B | **Brownfield ratchet/waiver** (R3) — *shipped v2.27.0.* `WAIVER-REGISTER.md` + `waivers-valid.sh` (governed exception: no expired/non-negotiable/over-90d/missing-field), `coverage-ratchet.sh` (no-regression-below-baseline), brownfield §5 ramp + §14/§13 tie-ins. Non-negotiable: secret-scan + branch-protection. | P0¹ | MINOR ✅ |
| **9d** | B | **CI-platform + runtime portability** (R4) — a non-GitHub CI reference (GitLab and/or ADO) + `incept.sh --ci` flag; extract the guard deny-matrix into a runtime-agnostic core + one second-runtime reference (generic pre-exec/pre-push hook) | P1 | MINOR |
| **A5** | A | **Competitive benchmark** — position vs other agentic-SDLC / paved-road offerings; sharpen the differentiation for the exec brief | — | — |
| **9e** | B | **Exec brief + org rollout** (R5) — `EXECUTIVE-BRIEF.md` (assures-vs-Org-owned, SOC2/ISO in one table, honest safety boundary, adoption effort); `org-rollout.md` (pilot→expand, central profile ownership, fleet upgrade); **fix the Stage 1–4 dangling ref** | P1 | MINOR |

### Stage IV — Tier 2: usability & persona completeness
| Step | Type | What | Sev | Ver |
|------|:----:|------|:---:|:---:|
| **9f** | B | **Beginner on-ramp** (R6) — `preflight.sh` prerequisites check; **disclose the CLAUDE.md→ENGINEERING-PRINCIPLES rename** in onboarding + incept banner; one-page `GLOSSARY.md`; a solo/lite track (how one person satisfies builder≠reviewer; deferrable gates) | P0¹ | MINOR |
| **9g** | B | **Stack-decision aid** (R7) — comparison matrix + per-profile "Best for / Avoid when"; address multi-stack/full-stack (SPA + API); stop silently defaulting the undecided to typescript-node | P0¹ | MINOR |
| **9h** | B | **Hosted-tracker bootstrap + contract check** (R8) — `incept.sh --backlog jira` emits a concrete `JIRA-SETUP.md` (states, fields, the "Only Assignee" transition); add `tracker-contract.sh` that can verify a live Jira instance | P0¹ | MINOR |
| **9i** | B | **Persona symmetry** (R9) — `TEST-PLAN-TEMPLATE.md` for QA; a lightweight auditable sign-off record (signer/date/gate/evidence) for QA-UAT & Designer-a11y; annotate the persona table to distinguish "dedicated artifact" from "works through someone else's" | P1 | MINOR |

### Stage V — Fidelity + economics
| Step | Type | What | Sev | Ver |
|------|:----:|------|:---:|:---:|
| **9j** | B | **Best-practice fidelity** (R10) — declare **SLSA level** + signed commits/tags path; add **NIST SSDF** crosswalk column; **a11y/load/eval: promote-to-gate (MAJOR) or honest-demote (MINOR)** ← decision fork; pin reference `ci.yml` `uses:` to full SHAs (reference must satisfy its own pinning contract) | P2 | **MINOR or MAJOR** |
| **9k** | B | **Economics & hygiene** (R11) — a ≤1-page **agent operating brief** loaded per feature with §-pointers to expand; **de-dup DoD + security** to one canonical home; **badge-from-VERSION** CI check (ends the recurring drift). Target: cut the ~24K/feature governance load materially | P2 | MINOR |

### Stage VI — Prove the gap is closed
| Step | Type | What |
|------|:----:|------|
| **A4** | A | **Auditor simulation** — agent role-plays a SOC2/ISO assessor and tries to break the evidence chain (e.g. the SBOM-vs-attested-digest gap the reference itself admits) |
| **A7** | A | **Re-run this 9-agent review** — confirm the persona scores lift and the convergent findings are resolved. *"To understand that there ultimately is really not a gap."* This is the arc's exit gate. |

¹ P0 *for that persona* — not a P0 safety defect, but the single largest usability hole in that persona's journey.

---

## Why this order

1. **Tier 0 first** — the false-assurance gap (9a) and guard holes (9b) are the only findings that *actively erode* the trust the rest of the kit earns. The red-team (A2) runs first so 9b closes a real enumerated list, not a guess.
2. **Analysis informs the fix it precedes** — A2→9b, A5→9e, A6→9f/9g, A1→9k. We never build a fix blind when a cheap analysis would aim it.
3. **Reach before polish** — Tier 1 (brownfield, portability, exec) widens *who can adopt at all*; Tier 2 polishes *how well each persona is served*.
4. **Economics late but explicit** — 9k condenses the governance surface only after we know its final shape (every prior slice adds/moves docs); measuring first (A1) and trimming last avoids churning the operating brief.
5. **Close the loop** — A7 re-runs the very review that started the arc. The kit's sixth principle is "the loop closes"; the remediation arc dogfoods it.

## Tracking
- Each step lands as its own PR, ratified by you, then this table's Status updates.
- Convergent findings #1–#5 from the review map to: #1→9a, #2→9b, #3→9d, #4→9c, #5→9i.
- The arc is **not** done until A7 shows the score lift and no unresolved P0/P1.

---

**Created:** 2026-06-09 · **Owner:** Bradley (ratifier) · **Status:** approved-pending → Stage I/II on go.
