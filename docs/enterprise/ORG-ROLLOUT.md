# Org Rollout Playbook

How an organization adopts this kit across many teams **without big-bang risk** — start advisory on one team, tighten as evidence accumulates, then run the whole fleet at full strictness. Stack-neutral. This is also the **canonical home of the Stage 1–4 maturity model** (below); other docs link here rather than re-defining it.

> **Principle — tighten with evidence, not by decree.** Gates blocking on day one across an org teaches teams to fake green. Start advisory, prove the loop on a slice, then make each gate blocking as the org earns the right to it. The waiver register (`../../templates/WAIVER-REGISTER.md`) is how you stay honest while you climb.

---

## Adoption stages — Pilot → Expand → Fleet

A rollout moves through three org-scope stages. Each has explicit **entry** and **exit** criteria; you do not advance until exit is met.

### Pilot
- **Scope:** 1–2 teams, one stack (one `profiles/<stack>.md`).
- **Posture:** gates **advisory** (they run and report, they do not block); waivers liberal and time-boxed (`../../templates/WAIVER-REGISTER.md`); branch protection on so segregation of duties is real from day one.
- **Goal:** learn the loop — Discover → Plan → Build → Review → Release → Done — and read a conformance run without fear.
- **Entry:** a stack chosen at Inception (`../../START-HERE.md`); a profile in place.
- **Exit:** at least one feature shipped through the **full** Discover→…→Done loop; the team can run and **understand** `../../conformance/verify.sh` output (what each gate checks, why it would fail).

### Expand
- **Scope:** several teams, possibly more than one stack.
- **Posture:** coverage ratchet on (`../../scripts/coverage-ratchet.sh`) — no regression below each repo's committed baseline; gates **blocking on *changed* code** (new/modified code must pass; legacy is waived, not faked); branch protection + `CODEOWNERS` + ratification RBAC (`ratification-rbac.md`) on across all participating repos.
- **Goal:** the loop becomes the default way of working, not a pilot experiment.
- **Entry:** Pilot exit met; a platform/governance owner identified for the org's kit copy.
- **Exit:** all participating teams on **protected `main`** (builder ≠ sole merger enforced); an **active, validated waiver register** per repo (`../../conformance/waivers-valid.sh` green) with every open waiver owned, time-boxed, and ratified.

### Fleet
- **Scope:** org-wide.
- **Posture:** **all 7 required §14 gates blocking** (`../../DEVELOPMENT-STANDARDS.md` §14), incl. `secret-scan`, `branch-protection`, supply-chain (SBOM + provenance); **central profile ownership** (the platform/governance team owns the org's kit copy); the kit is **version-pinned** per repo; the **fleet-upgrade process** (below) runs as routine maintenance.
- **Goal:** uniform quality bar across every repo, upgrades rolled deliberately.
- **Entry:** Expand exit met; waivers trending toward zero.
- **Exit:** there is no exit — Fleet is the steady state. Maturity continues to tighten per the stages below.

---

## Maturity stages (1–4): tightening conformance at scale

The adoption stages above describe **org scope** (how many teams). This describes **conformance strictness** (how hard the gates bite) — the dimension a single repo or team climbs over time. The two are related but independent: a Fleet-scope org still moves repos up these strictness stages as they earn it.

| Stage | Conformance posture |
|-------|---------------------|
| **Stage 1** *(new / pilot)* | Core gates **advisory**; waivers **liberal** (time-boxed); progressive-delivery basics — **staged rollout** (`../operations/progressive-delivery.md`, the Stage-1 baseline); **branch protection on**. |
| **Stage 2** | Gates **blocking on *changed* code**; **coverage ratchet** from a committed baseline (`../../scripts/coverage-ratchet.sh`); **`secret-scan` + `branch-protection` non-negotiable** (never waivable, per `../../templates/WAIVER-REGISTER.md`). |
| **Stage 3** | **All 7 required §14 gates blocking** (`../../DEVELOPMENT-STANDARDS.md` §14); **supply-chain enforced** — SBOM + build provenance; **waivers expiring toward zero**. |
| **Stage 4** *(production scale)* | **SRE-style hard gating** — error-budget / DORA freezes (`../operations/dora-metrics.md`) block promotion on breach; **zero waivers**; **full attestation** (every released artifact carries SBOM + provenance, audit evidence complete). |

This single progression **unifies the maturity mentions previously scattered across the kit** — the DORA error-budget gating that hardens from soft to blocking, progressive-delivery's "Stage-1 baseline" staged rollout, and error-budget-driven promotion freezes are all the *same climb*, expressed here as Stage 1 → Stage 4. Other docs point to this anchor rather than re-defining their own ladder.

---

## Fleet upgrade — rolling a new kit *version* across many repos

At Fleet scope the kit itself is a versioned dependency. Each adopter **pins a version**, recorded in that project's `CLAUDE.md` under **"Kit version adopted"**. Upgrading a repo is a deliberate, evidence-gated step — not an ambient drift.

**Per-repo upgrade sequence:**
1. **Read the delta.** Review `../../CHANGELOG.md` from the pinned version to the target — what changed, and especially whether any *required gate* was added (a **MAJOR** bump).
2. **Re-run conformance.** Run `../../conformance/verify.sh` against the repo under the new version to see what newly fails.
3. **Absorb new required gates via the waiver ramp.** A MAJOR that adds a required gate may legitimately fail a repo on day one. Record a tracked, time-boxed, ratified waiver (`../../templates/WAIVER-REGISTER.md`) — never silently disable the gate — and drive it to zero. (`secret-scan` and `branch-protection` are never waivable, so a MAJOR touching those is a hard blocker to fix, not waive.)
4. **Bump the pin.** Update "Kit version adopted" in the repo's `CLAUDE.md` once conformance is green (or green-with-ramping-waivers).

**Central profile ownership.** A **platform / governance team owns the org's kit copy** — the canonical profiles, gate definitions, and the org's version pin policy. Teams consume it; they do not fork the standards. Changes to the governing docs or gate definitions follow *agents propose, humans ratify* **at scale**: the security owner ratifies governing-doc and gate changes per `ratification-rbac.md`, so an org-wide tightening is an accountable, auditable event — not a silent push.

---

> **See also:** `README.md` (enterprise addendum index), `ratification-rbac.md` (who may ratify what), `../../MAINTAINING.md` (how the kit is versioned), `ROI-MODEL.md` (the cost/benefit case for the climb — sibling doc).
