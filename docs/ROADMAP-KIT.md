# Kit Roadmap — Remaining Work

The kit's **own backlog** (dogfooding `DEVELOPMENT-PROCESS.md` §6). Each remaining item ships as a **contract → reference → conformance** vertical (`MAINTAINING.md` §1), in priority order, each with its own spec → plan → build → dual-review → ratify.

**Current state:** `v3.75.0`. **Epic E5 (observability / operate-loop) complete.** Skill spine = 10 content skills + the `using-skills` keystone. Roster = Orchestrator (Architect/Product/Ops hats) · Engineer×N · Reviewer · Security-reviewer · Kit-Steward (meta-control).

> **Completed history is NOT tracked here.** Every shipped slice (v1.0.0 → v3.75.0) lives in `CHANGELOG.md` (per-version detail) and `git log` (full record). This file holds **only open work** — rewritten 2026-06-29 to stop carrying the full historical arc inline. Per-slice design docs are in `docs/architecture/`; per-slice meta-control verdicts in `docs/governance/meta-control-log.md`.

---

## ★ Priority sequence (2026-06-29, owner-approved)

The theme: **clean the board → lay the governance foundation → de-risk the one compounding smell → fix integrity defects → validate teams → resume feature/depth epics → capstone.** Each feature epic enters Build only on an affirmative per-epic meta-control verdict.

1. **Roadmap rewrite** *(this file — housekeeping, done 2026-06-29).*
2. **Proportional Promotion Contract — Slice 1** (model/standards keystone). The governance foundation; changes how all later work is governed; low-risk authoring.
3. **`orchestrator-loop-wired.sh` refactor** (the one real refactoring candidate — see Refactoring below). Behavior-preserving, selftest-guarded; do it before it compounds further.
4. **T4 — CI-trust blockers** (honest integrity defects).
5. **Proportional Promotion Contract — Slices 2–4** (enforcement; guard-touching slices last, sequenced by risk).
6. **T2-team-live** (needs a 2nd forge identity; validates the contract's team side).
7. **E6 (AI-native eval depth) · E1-full (test-battery breadth) · E5-full** (the depth epics).
8. **E7 / E9 / E11 scoping brainstorms** (clarify what's genuinely left — some may be near-done).
9. **E10 capstone** (the 1.0 right-weight gate, last).

**Release-line:** stay on the **3.x line**; **1.0 is gated on feature-complete + E10 + a real external adopter** (the kit is pre-adoption; n=2 synthetic). Internal milestone count does not gate 1.0.

---

## Epics & larger units (open)

### Proportional Promotion Contract *(NEW — design ratified 2026-06-29)*
Redesign the human↔AI handoff so rigor is **proportional to rung × change-class** (not uniform/keystroke-centered): relax the safe low-blast 80%, harden the dangerous 20%, replace ratification keystrokes with recorded GO/NO-GO judgment (execution delegable post-GO), keep the control-plane human-governed, make `control-plane-ratification` emit a truthful team/solo state label. **~4 slices:** (1) model + standards keystone doc; (2) `promotion-readiness.sh` change-class derivation + surfacing; (3) proportional gates + the state label; (4) relax agent-commit + delegable execution post-GO. Design: `docs/architecture/2026-06-29-proportional-promotion-contract-design.md`.

### T4 — Conformance / CI-trust / UX hardening
**Highest-urgency sub-items (honest integrity defects):** run `verify.sh --require` per-PR (not just `--selftest`); assert ≥1 control PASS in `--selftest`; un-swallow `claims-registry` diagnostics (preserve three-state). **Plus:** widen golden-path path-filter (F7); extract the selftest harness → `wf-helpers.sh`; CODEOWNERS brownfield false-alarm on clean greenfield; `explain` blind to process-vocabulary; private-repo `enforce_admins` honesty note; `check-links.sh` code-span gotcha (greps raw text, false-fails on quoted Markdown link syntax inside backticks); export-ignore `docs/architecture/` from adopter exports (`.gitattributes` + `adopter-export.sh` IGN + lock — an S3-class control-plane slice); resolve the `prototype`≡`team` mode-dial dead-letter (C1, confirmed false-promise).

### T2-team-live
Live team-governance validation: real `enforce_admins`, true 2-human non-author approval, the one-flip-upgrade end-to-end, and the solo-discoverability probe (does a blocked cold adopter find `review-lane.md`?). **Blocked on provisioning** — needs a second forge identity + an org/paid repo (`enforce_admins` 404s on private free-tier). Bradley provisions, then run. Pairs naturally with the Promotion Contract (validates its team side).

### E3 — Agentic specialization & orchestration (spine, partially shipped)
Shipped: E3a thin loop (v3.52.0), escalation/HITL (v3.55.0), conflict-safe writes (v3.56.0), merge-atomicity (v3.69.0). **Remaining slices:** **phase→agent flow** (agent-phase state machine — not yet designed) · **agent-memory** (persistent cross-session state, ex-E12, "last") · *FS-isolation (§10 item 1) — informally parked: harness-sandbox posture exists, the provable case was deemed hollow.* Each remaining slice needs its own per-epic M verdict before build.

### E5-full *(E5 core complete; this is the narrow remainder)*
On-call / SLA / paging reference (currently prose-only, a Tier-3 blind spot) · managed-secrets rotation / break-glass reference · long-term storage / retention / vendor-backend guidance beyond the reference Jaeger.

### E6 — AI-native quality depth *(not started)*
Real eval harness (pinned judge, not the deterministic stub) · prompt-injection / red-team reference · LLM cost/quality tracing closed loop · `gate-eval` secret-exposure reference (C5).

### E1-full — Test battery breadth *(E1-thin shipped v3.50.0)*
Contract tests / API-contract layer · property-based · a11y (jest-axe for a web variant) · runtime-security test layer · conditional conformance per layer.

### E10 — Capstone / "is this too much?" *(the 1.0 gate, last)*
Holistic right-weight audit on the finished kit + one comprehensive end-to-end validation using only the kit's own roster + skills (zero superpowers — methodology piloted on the v3.69.0 slice) + the maintenance model.

### Loosely scoped — need a per-epic M brainstorm before they're "real"
- **E7 — best-practice & supply-chain adherence:** SAST/DAST completeness, SBOM/SLSA completion, secrets-at-scale (Vault/KMS) proven, enterprise-scale RBAC/compliance. *May be substantially done already (semgrep SAST, partial SLSA, `supply-chain-verify.sh` shipped) — brainstorm to find what's genuinely left.*
- **E9 — environment-promotion vertical (≤2 slices):** config-as-code + least-privilege detective verification reference (the env model already exists).
- **E11 — AI-artifact lifecycle / audit vertical (≤2 slices):** artifact provenance/audit trail. *May be absorbed by E6 — brainstorm to confirm it's distinct.*

### R — Refactoring
Scoped down to essentially **one real slice** (see Refactoring lens below): make `orchestrator-loop-wired.sh` data-driven. The broader "area-by-area refactor capstone" is small by design (continuous right-weighting kept the kit clean).

### Parked / inactive
- **E8 — process remainder / retro-facilitator:** deferred indefinitely (M already covers self-adapting process; the Agile-ritual half is speculative). *E12/E13/E14 dissolved into E3 / E4d / E6 — no work under those labels.*

---

## Refactoring lens (2026-06-29 scan — mostly clean)

The kit is broadly clean. **One real candidate, one watch-item, everything else appropriately sized** (the doc-budget ratchet on `DEVELOPMENT-PROCESS`/`STANDARDS` is actively preventing re-bloat — working as intended, not a smell).

- **#1 — Real, worth a slice: `conformance/orchestrator-loop-wired.sh` selftest fixtures.** Measured super-linear growth — each new skill brick costs ~128 lines (a `check_*_skill` fn + 2 cases + ~81 lines of retroactive boilerplate across all 27 existing cases). Fix: a `{skill, markers, seat}` table + one generic `check_skill` + an enumerating selftest harness. The 27-case selftest is its own complete behavior-preserving safety net. Worsens with every future brick → do it soon (priority #3).
- **#2 — Watch, don't touch yet: `guard-core.sh` `is_control_plane_path` per-script enumeration.** Linear growth with a 3-location sync risk (case + the two shell-redirect regexes). High-risk file → only refactor when a *cluster* of new scripts forces it; otherwise leave it.

---

## Banked follow-ons (small, non-blocking — each <1 slice)

Pull opportunistically or when a related slice makes them cheap:
- **`escalate-ops-trigger`** — wire an `ops-irreversible` trigger + option set into `scripts/escalate.sh` when a live consumer exists (the `operating` skill points at the seam; schema is B-ready).
- **`tier-checkpoint preemptive approval`** — Option B: an `escalate.sh` second caller for preemptive approval before a high-consequence autonomous step (B-ready, not wired).
- **`guard-dev-clone-affordance`** — a sanctioned env/flag so the guard reliably recognizes a throwaway-clone context (ergonomic).
- **Kit-Steward FLOOR parity** — backfill the Orchestrator-reference negative selftest for `check_skill`/`check_plan_skill` (bricks #1/#2).
- **`M2-ratification-hardening` residual** — future-pin shape (allow exactly the one unreleased seam version); verdict enum case-normalization; CODEOWNERS on `docs/governance/`; `ver_gt` dedup. (Backstopped by M2-S5; non-blocking.)
- **`adopter-conformance-carve`** — relocate kit-self checks under `conformance/kit-internal/` or graceful skip-missing (with a security review of the false-negative risk). ~75-file triage.
- **G8 / per-segment guard** — replace the guard's co-occurrence heuristic with per-segment command parsing (split on `;`/`&&`/`||`/`|`; judge each segment). Deferred — every narrow fix had confirmed bypasses; needs its own security pass.
- **Skills adapter dimension** — NATIVE bindings for a formal `skills` adapter in the `adapters/` manifests (deferred from brick #1; owner-ratified deferred).
- **Maintenance nits** — dep-scan prod-scoping consistency (TS `--omit=dev` vs others all-scopes); Node-20 action pin-refresh cadence; `claims.tsv`/`verify.sh [control]`-label honesty qualifiers; stale `docs/superpowers/{specs,plans}` path residue in `design`/`plan` SKILLs; P4 polish (RUNBOOK incident-response section, designer a11y handoff guidance, CI step-label renames, multi-stack scaffold IDE note).

---

## Not growing (deliberate)

- **No new skills planned** beyond the 10 shipped — the spine is complete.
- **No new standing seats** — Ops/SRE is a *hat* (demand-gated on a live system + distinct prod authority); Product is a *hat*; specialist roles (test-author, migration-author, threat-modeler, perf-optimizer, doc-writer) are *skills* a seat wears, not seats (agents-vs-skills rule: few agents, many skills).
