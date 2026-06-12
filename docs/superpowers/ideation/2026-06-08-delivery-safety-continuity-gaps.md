# First-pass gap analysis — continuous & safe delivery, and continuity

**Status:** APPROVED — this is the Slice 8 arc-of-record (decisions locked 2026-06-08).

## Locked decisions (Slice 8)
- **Structure:** consolidated arc **8a–8f**, sequenced, each its own ratified PR (stop-early optionality).
- **Ordering:** continuity + enforcement gates first; delivery-automation references later.
- **Frameworks:** folded into their slices (NIST 800-34 → 8c DR; DSOMM → 8b/8f maturity), no standalone crosswalk.

**The arc:**
1. **8a** — Incident Response standard + blameless postmortem template (fixes the PROCESS §9 → STANDARDS dangling ref).
2. **8b** — Release-readiness "Definition of Deployable" conformance checklist (gates Release; DSOMM anchor).
3. **8c** — DR / backup-restore drill reference + conformance checklist + BIA-at-Inception (NIST 800-34 anchor).
4. **8d** — Resilience + load/soak verification checklist.
5. **8e** — Progressive-delivery reference + post-deploy smoke gate.
6. **8f** — DORA metrics collection reference (DSOMM maturity anchor).

Each pairs a **reference/contract** with a **conformance check** where applicable — the kit's enforce-don't-document signature.

---

_(Original first-pass analysis below, retained for context.)_
**Frame:** The kit is **strong at the contract level** for delivery and safety; the real gaps are (1) contracts not yet backed by a **conformance check** or **reference implementation** (the kit's own "if it isn't automated, it isn't enforced" test), and (2) genuinely thin depth in **continuity (BC/DR, incident response, resilience verification)**.

---

## What the kit already covers (so we don't re-invent it)

| Area | Where | Depth |
|------|-------|-------|
| Promotion Dev→QA→UAT→Prod, human-gated prod | PROCESS §9 | Contract + env-protected deploy reference (7a) |
| Feature flags + kill-switch + flag-debt retirement | PROCESS §10 | Contract |
| Expand-contract / zero-downtime / reversible migrations | PROCESS §10 | Contract |
| Progressive delivery (canary / blue-green; auto-canary as maturity step) | PROCESS §10 | **Contract only — no reference** |
| Rollback preference order (flag-off → redeploy prev → revert) | PROCESS §10 | Contract; RUNBOOK rollback section |
| Supply-chain: SBOM + provenance (lang artifact + **image digest**) | STANDARDS §14, 5e, 7c | **Enforced** (CI gates + conformance) |
| SLOs / error budgets (soft → hard-gate at maturity) | PROCESS §9 | Contract |
| DORA four + agentic metrics (review latency, retro closure) | PROCESS §14 | **Defined but not instrumented** |
| Observability, resilience (retry/backoff/circuit-breakers/degradation) | STANDARDS §3, §4 | Contract |
| Backups, verify-restore, RPO/RTO in RUNBOOK | STANDARDS §10 | **Contract only — no reference/drill/check** |

**Takeaway:** the *thinking* is largely done. The leverage is converting the strongest contracts into **enforced checks + reference implementations**, and deepening **continuity**.

---

## Gaps, by theme (prioritized within each)

### A. Continuity / BC-DR — the thinnest area, and existential for a enterprise-scale, regulated, customer+affiliate-data adopter

- **A1 — No Incident Response standard, and a broken cross-reference.** PROCESS §9 says "P0/P1 escalate to **Incident Response + postmortem** (`DEVELOPMENT-STANDARDS.md`)" — but STANDARDS has **no incident-response section**. The pointer dangles. Missing: severity matrix (P0–P3 exists in §9 only), incident roles (commander / comms / scribe), comms cadence, declared SEV criteria, and a **blameless postmortem template** in `templates/` (there is none). *High value, low effort, fixes a real dangling ref.*
- **A2 — DR is prose-only; no reference, no drill enforcement.** §10 says "verify restore at least once per project (recurring-maintenance)" — but nothing references *how* to run a restore drill, and no conformance proves a drill happened. For regulated data this is the gap that matters most. Missing: a **backup-restore drill runbook/reference**, a **DR conformance checklist** (like `15-factor-checklist.md`), tiered RTO/RPO by service criticality, and a **Business Impact Analysis (BIA)** prompt at Inception. *High value.*
- **A3 — No resilience/chaos or load verification.** §4 asserts circuit-breakers/retries/graceful degradation as *principles*; nothing verifies them. Best practice: lightweight **fault-injection drill** (kill a dependency in staging), and **load/soak testing before launch** (your global standards require it; the kit doesn't). Missing: a **resilience-verification checklist** + a load-test reference. *Medium-high.*
- **A4 — Data-continuity specifics for the regulated case.** Right-to-erasure path *testing*, retention-schedule *enforcement*, PII inventory — mapped as Org-owned in the 6a privacy family, but no reference/check that the erasure code path actually works. *Medium (overlaps Org-owned boundary).* 

### B. Safe delivery — strong contract, enforcement/reference gaps

- **B1 — "Definition of Deployable" / release-readiness gate.** §10 says "every release declares its rollback path before it ships" — but nothing *checks* it. Propose a **release-readiness checklist** (rollback tested · smoke tests defined · monitoring/alerts wired · migration reversible · flag owner+expiry) as a conformance checklist gating Release, mirroring how 15-factor gates Review. *High value — converts "safe delivery" from prose to enforced.*
- **B2 — Progressive delivery has no reference implementation.** §10 describes canary/blue-green + automated canary analysis; 7c shipped k8s/Helm *deploy* refs but **not progressive rollout**. Missing: a reference (Argo Rollouts / Flagger canary, or a flag-driven staged rollout workflow) + the auto-canary-analysis hook tied to SLOs (§9). *Medium-high.*
- **B3 — Post-deploy smoke / synthetic verification is thin.** DoD says "smoke-tested" but there's no smoke-test reference or a **post-deploy verification gate** in the deploy pipeline. Missing: a smoke/health-check reference + gate. *Medium.*
- **B4 — End-to-end CD promotion pipeline is reference-thin.** The promotion *model* (§9) is described and 7c added an env-protected prod-deploy job, but there's no executable **Dev→QA→UAT→Prod promotion pipeline** reference wiring the gates together. *Medium.*
- **B5 — SLSA level + signed commits/tags.** 7c gives image provenance (SLSA-ish) but there's no declared **SLSA target level**, no hermetic/reproducible-build verification beyond prose, and no **signed-commit/tag** option. *Medium (maturity).*

### C. Continuous delivery — strong, with measurement/maturity gaps

- **C1 — DORA metrics defined but not instrumented.** §14 maps to DORA but nothing *collects* them. Measurement is the precondition for the soft→hard-gating the kit already describes. Missing: a **DORA-collection reference** (from GitHub deployments/Actions) + a flow-metrics dashboard pattern. *Medium-high — unlocks the maturity gates already designed.*
- **C2 — Change-freeze / risk-tiering hook.** Enterprise CD (and a public broadcaster around high-traffic events) needs **change-freeze windows** and risk-tiered change advisory. Missing: a freeze-window / change-risk configuration hook. *Low-medium.*
- **C3 — Explicit branching standard.** Trunk-based is *implied* by feature flags (§10) but not stated as a standard. *Low.*

### D. Cross-cutting framing
The kit nods to DORA (§14), SLSA (provenance), NIST SSDF (5e/6a). Two maturity frameworks aren't mapped and could anchor a maturity ladder: **OWASP DSOMM** (DevSecOps maturity — the kit's soft→gating stages are DSOMM-shaped) and **NIST 800-34** (contingency planning — the A-theme continuity gap). Mapping to these would extend the 6a compliance-crosswalk pattern.

---

## Proposed shortlist for discussion (a candidate "Slice 8" set)

Ordered by value × (fit with the kit's enforce-don't-document philosophy):

1. **Incident Response standard + blameless postmortem template** (A1) — fixes the dangling ref; table-stakes; ~1 small slice.
2. **Release-readiness "Definition of Deployable" conformance checklist** (B1) — converts safe-delivery contract → enforced gate; high leverage, low effort.
3. **DR / backup-restore drill reference + conformance checklist + BIA prompt** (A2) — the continuity centerpiece; existential for the adopter profile.
4. **Resilience + load/soak verification checklist** (A3) — verifies §4's principles.
5. **Progressive-delivery reference + post-deploy smoke gate** (B2+B3) — the executable half of §10's progressive delivery.
6. **DORA metrics collection reference** (C1) — instruments §14, unlocks maturity gating.

Each is a kit-loop slice (brainstorm → spec → plan → subagent execution → ratified PR), and most pair a **reference** with a **conformance check** — the kit's signature move.

**Open questions for the morning:**
- Scope: one consolidated "continuity & safe-delivery hardening" arc (Slice 8) vs. cherry-pick the top 2–3?
- For the adopter (enterprise-scale, regulated): does continuity (A2/A1) outrank delivery-automation references (B2/B4), or do we want both?
- DSOMM / NIST 800-34 crosswalk now (extends 6a), or defer?
