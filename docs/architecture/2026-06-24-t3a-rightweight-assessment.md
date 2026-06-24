# T3a — Right-Weighting Assessment (meta-control run #2)

**Date:** 2026-06-24 · **Kit version:** v3.48.0 · **Method:** meta-control panel — 5 per-surface assessors (aggressive default-cut) → safety-verify (default unsafe→keep) → synthesis · **Trigger:** consolidation T3a · **Profile:** right-weighting.

> **Headline finding (the reassuring one): the kit is not bloated-with-rot.** Run under an *aggressive
> default-cut* bias, the assessment found the **enforcement surface fully justified** — conformance (84
> files) and the §14 gates (12) proposed **zero** cuts; every check/gate has distinct, evidenced
> protection. The real right-weighting is **modest and confined to docs, templates, profile-labels, and
> the epic backlog** — confirming the consolidation verdict "bones sound; overgrowth not rot," *by the
> mechanism, not by assertion.*

---

## ★ Design-intent correction (owner-challenged, 2026-06-24) — SUPERSEDES the aggressive ledger below

The owner correctly flagged that **"low usage / few inbound references" is a weak, potentially
policy-violating cut criterion** for a kit whose philosophy is *front-load rigor + conditional
obligations* (rare ≠ cuttable), *harness-neutral fallbacks*, *persona coverage*, *compliance
crosswalks*, and *progressive disclosure (de-emphasize, don't remove)*. A third **design-intent verify
pass** re-judged every proposed cut asking *"does this exist for a deliberate design/compliance/persona/
process reason low-usage doesn't capture?"* — default KEEP unless genuinely **redundant** (content
duplicated elsewhere) or **dead** (completed build artifact captured in CHANGELOG + live code).

**Result: 4 reversals, and the rest are content-preserving — there are essentially NO functional deletions.**

| # | Item | Corrected verdict | Why |
|---|---|---|---|
| 1 | `SPEC-TEMPLATE` | **consolidate-safe** *(content must migrate)* | SPEC = Plan-phase + harness-neutral manual fallback; only safe if its numbered-reqs/personas/out-of-scope migrate into an "extended" FEATURE-REQUEST. Plain delete → keep. |
| 2 | CODE-REVIEW-CHECKLIST → REVIEW-RECORD | **consolidate-safe** *(stay a distinct rubric block)* | checklist (what-to-check) vs record (what-was-found) — fold as a rubric block, not prose. |
| 3 | JIRA-SETUP → TRACKER-SETUP | **REVERSED → keep-deliberate** | distinct *tiers*: server-enforced (Jira "Only Assignee") vs convention. Architecturally load-bearing in §6. Keep both. |
| 4 | AI-POLICY → enterprise | **relabel-safe** *(relocate, not remove)* | ISO 42001 Clause 5.2 artifact; co-locate with the AI-governance crosswalk; needs incept.sh update. |
| 5 | platform-safety-boundary stub | **REVERSED → keep-deliberate** | enterprise/auditor framing ("guard is a speed bump; these 4 controls prevent damage") ≠ practitioner how-to (containment.md). Keep both + cross-ref. |
| 6 | harness-enforcement-evidence stub | **REVERSED → keep-deliberate** | contract (harness-adapters) vs **evidence** (the proof artifact) — the kit's own contract→reference→conformance separation. Keep both. |
| 7 | frame/shape → discovery-loop | **consolidate-safe** *(grow sections + update conformance)* | thin per-stage pages; safe only if discovery-loop gains FRAME/SHAPE sections + discovery-complete.sh updated atomically. |
| 8 | 6 E-series design docs + 5 plans | **dead-retire** | genuinely dead build artifacts (captured in CHANGELOG + live code). Keep e3-design (live spec), consolidation-audit, meta-control-first-run. |
| 9 | relabel 5 profiles experimental | **relabel-safe** | honesty win, nothing removed. |
| 10 | E12+E14→E3 · E13 dissolve · E8 defer | **consolidate/dead/defer** | concerns preserved (folded/parked), not discarded. **E9, E11 → REVERSED to scope-challenge only** (distinct concerns: env-promotion flow; AI-artifact lifecycle/audit — would be lost if dissolved). |

**Net corrected T3:** content-preserving consolidations (1,2,4,7) + relabel (9) + dead-build-doc retirement (8) + backlog reorg (E12/E14→E3, E13 dissolve, E8 defer) — and **keep** JIRA-SETUP, platform-safety-boundary, harness-enforcement-evidence, E9, E11. This is right-weighting *by organization + honesty*, not subtraction of capability — fully consistent with the kit's front-load-rigor design.

---

## Per-surface verdicts (post-safety-verify) — NOTE: corrected by the design-intent pass above

| Surface | retire | merge/stub | relabel | keep | notes |
|---|---|---|---|---|---|
| **conformance** (84 files / 31 claims) | 0 | 0 | — | **84** | Fully justified. "Boilerplate" is a **T4 refactor** (`wf-helpers.sh` extraction), not a retirement. Load-bearing-but-small warnings: `review-lane.sh`, `waivers-valid.sh`, `mcp-policy.sh` (look cuttable, aren't). |
| **gates** (§14: 7 required + 5 conditional) | 0 | 0 | — | **12** | All distinct enforcement value. `license-compliance` is the weakest but still real. sbom/provenance already correctly split. |
| **templates** (25) | 1 | 2 | — | 22 | retire SPEC; merge CODE-REVIEW-CHECKLIST→REVIEW-RECORD, JIRA-SETUP→TRACKER-SETUP; move AI-POLICY→enterprise. |
| **docs** (61) | 6 (deferred) | 2 stubs + frame/shape | — | ~52 | stub platform-safety-boundary + harness-enforcement-evidence (preserve links); frame/shape→discovery-loop (needs conformance change); **ADR-000-stack merge KILLED** by safety-verify. |
| **profiles** (10) | 0 | 0 | **5** | 10 | relabel java-spring/kotlin/dotnet/rust/data-engineering **experimental**; first-class = ts-node/python/go/ml/terraform. |

---

## Cut ledger (safety-verified, grouped into T3c slices)

**Group 1 — direct docs/templates (low-risk; delete/stub + update prose refs + check-links):**
- **Retire `templates/SPEC-TEMPLATE.md`** — *mitigation:* repoint 2 backtick mentions in `TEST-PLAN-TEMPLATE.md`; absorb its distinct value (numbered reqs/personas/out-of-scope) into FEATURE-REQUEST as an optional "extended spec" section.
- **Merge `CODE-REVIEW-CHECKLIST.md` → `REVIEW-RECORD-TEMPLATE.md`** — *mitigation:* update 2 backtick mentions (DEVELOPMENT-PROCESS §109, code-quality.md).
- **Stub `docs/enterprise/platform-safety-boundary.md`** (content → `containment.md`, keep a forwarding stub at the path — 32 inbound links). **Safe.**
- **Stub `docs/operations/harness-enforcement-evidence.md`** (content → `harness-adapters.md`, keep forwarding stub — 4+ inbound links incl. 3 adapter READMEs). **Safe.**

**Group 2 — needs a control-plane change (apply.py + review, atomic with the move):**
- **Merge `JIRA-SETUP-TEMPLATE.md` → `TRACKER-SETUP-TEMPLATE.md`** — `scripts/incept.sh:278` copies it on `--backlog jira`; the move requires an incept.sh update.
- **Move `AI-POLICY-TEMPLATE.md` → `docs/enterprise/`** — `scripts/incept.sh:221` copy-loop hard-codes `templates/` prefix; needs incept.sh update.
- **Merge `docs/discovery/frame.md` + `shape.md` → `discovery-loop.md`** — `conformance/discovery-complete.sh:17-18,29-30` checks `[ -f frame.md ]`/`[ -f shape.md ]` **and** discovery-loop links them → double gate (conformance + check-links); needs discovery-complete.sh update first.

**Group 3 — deferred retirement (atomic, post-CHANGELOG-absorption):**
- **Retire the 6 completed E-series design docs** (`2026-06-22-e4a-containment-audit`, `2026-06-23-{e4-work-mount-fix, e4a-prime-token-scope, e4b-image-vuln-gate, e4c-dast-runtime-security, e4e-author-not-approver-sod}`) **+ their 5 companion superpowers plan docs atomically** (the plan docs' inbound design-doc links would otherwise break check-links). Only ROADMAP/CHANGELOG reference them; rationale is captured in CHANGELOG + live implementation. Keep `e3-…-design.md` (E3 not built yet — live spec).

**Group 4 — profile relabel (fully safe, no control-plane):**
- **Relabel 5 profiles `experimental`** (java-spring, kotlin, dotnet, rust, data-engineering). Label in each profile's `Status:` field + the `STACK-SELECTION.md` matrix row. First-class = ts-node/python/go/ml/terraform. **Honesty win** (only ts-node is maintainer-executed). *Paired finding:* 9/10 profile `ci.yml` use floating `actions/checkout@v4` while the kit preaches SHA-pinning — a do-as-I-say gap to fix in the same slice (candidate; or route to T4).

**KILLED by safety-verify:** ADR-000-stack→ADR-000-EXAMPLE merge (template→output relationship, incept.sh:285 depends on both).

## Keep ledger (earned its keep under aggressive bias)

- **All 84 conformance files + all 12 gates** — the enforcement surface is justified, not bloat. (The single biggest result.)
- All conformance-locked docs (removing any breaks a live check).
- The highly-linked operations docs (review-lane 37 inbound, runtime-guards 35, containment 25, etc.).
- All 10 profiles (relabel, don't remove — `adopter-export --profile` already prunes unused ones).

---

## Epic-kill recommendations (for T3d ratification)

| Epic | Verdict | Rationale |
|---|---|---|
| E1, E3, E5, E6 | **keep** | distinct, evidenced epics |
| **E12** context-engineering | **merge → E3** | it's how E3 agents share state (handoff/memory) — an E3 slice, not an epic |
| **E14** human-in-loop | **merge → E3** | escalation is an orchestration primitive — an E3 slice |
| **E13** FinOps | **kill** → E4d (cost/runaway) + E6 (LLM cost tracing) | nothing left it uniquely owns; infra-cost is platform-owned/out-of-scope |
| **E9** env/promotion · **E11** AI-artifact lifecycle | **keep but scope-challenge at brainstorm** | each may be ≤2-slice verticals, not full epics (E9: the env model already exists; E11 overlaps E6) |
| **E8** process remainder | **defer** | M already covers "self-adapting process"; the Agile-ritual half is speculative pre-E3 |

Net feature epics: **10 → ~6** (E1/E3/E5/E6/E9/E11), E3 absorbing E12+E14, E13 dissolved, E8 deferred.

## Release-line input (for T3d)

Stay on the **3.x line**; a **1.0 is premature**. T2 established the kit is **pre-adoption** (n=2 synthetic, no external human); a 1.0 should gate on **feature-complete + E10 + a real external adopter**. The right-weighting being *modest* (not a rescue) supports a confident 3.x cadence, not a defensive rewrite.

## ★ Scope finding: T3b (retirement mechanism) may DESCOPE

F6 motivated T3b as a "two-way ratchet" to *retire conformance checks/claims*. But the assessment found **zero conformance/claim retirements needed** — there's nothing on the enforcement surface to retire. The actual retirements are **docs/templates**, handled by ordinary edits (delete + update refs + check-links) — no special mechanism required. **Recommendation:** descope T3b from a full retirement-mechanism build to a lightweight **"retire convention"** doc (how to retire a doc/template/claim safely, incl. the check-links + conformance-ref discipline this run used), OR fold it into T3c. Confirm at the checkpoint.

---

## Honest ceilings

- This is the **panel's 2nd run** (logged below) — analysis only; **nothing is cut** in T3a. Each cut becomes a T3c slice with its own verification (and security-review for any control-plane touch).
- Aggressive bias produced broad proposals; the safety-verify pulled back the unsafe ones (1 killed, 3 control-plane-gated, 2 reshaped to stubs). The *net* right-weighting is deliberately modest.
- Owner ratifies the cut ledger, the epic kills, and the release-line before any T3b/c/d work.

_Logged as meta-control run #2 in `docs/governance/meta-control-log.md`._
