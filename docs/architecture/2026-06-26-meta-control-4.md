# Meta-control panel #4 — SYNTHESIS & VERDICT — 2026-06-26

**Trigger:** E3-epic boundary + reorder ratification
**Version:** 3.49.1 · main green · `verify --require` = 25 control-checks · 0 failed · `doctor` PASS
**Profile:** light (5-lens) · Kit-Steward synthesis (PROPOSE-only; human ratifies & commits)
**Decision under review:** the proposed reorder — E3-first (build E1/E5/E6 *through* E3 as dogfood); E5 after E3; pull `T2-team-live` forward; E1 after E3; E9/E11 → ≤2-slice verticals.

---

## 1. Verdict

> **GO-WITH-CONDITIONS.**

The reorder's spine is sound and the substrate premise is genuinely (mostly) true: E3 is the core thesis, it is already sliced thin, and the safety substrate it leans on (containment E4a–e, cost kill-switch E4d, SoD E4e, the guard, cadenced meta-control) is the most-exercised part of the kit. Zero **Blockers** survived the verify pass. Every High is **fix-forward** and none breaks the verified path or a headline claim — they are framing/sequencing corrections, not stop-the-line defects.

The one place the panel **overrides the proposal on substance** (not merely amends framing): the lenses are unanimous (4/5 explicit) that **"build E1/E5/E6 *through* E3 as dogfood" inverts a dependency E3's own design names** — E1 (oracle) and E5 (sensor) are *inputs* E3 consumes, not fan-outs of it. This is the F5 "build-ahead-of-need" error the 2026-06-23 consolidation audit was convened to stop, repeated one level up. The fix is cheap and does not delay E3: lead with a **thin** slice of each, then fan the breadth out through proven E3. That correction is folded into the ratified order below as a **condition**, not a blocker.

Why not plain GO: the dependency-inversion and the runaway-guard-has-no-caller gap are real and would bite during the first E3 dogfood run if unaddressed. Why not NO-GO: nothing is broken, the corrections are pre-build planning items, and E3a can start the moment they are reflected in the E3 kickoff plan.

---

## 2. Adversarial verify pass (every material finding independently re-checked)

| # | Lens | Claim | Verdict | Note |
|---|------|-------|---------|------|
| V1 | 4 | "E5 has NO reference today" | **REFUTED (downgraded)** | `conformance/observability-ready.sh` + `observability-readiness.md` exist (records SLO/telemetry *posture*; Manual rows for live emit). The *script reference* exists. |
| V1b | 4 | "E5 has no live SENSOR; traces/scorecards empty; agent-ops fixture-only" | **CONFIRMED** | `ls scripts/` = agent-trace/scorecard/tier-advice only; ROADMAP-KIT.md:144 "tested on fixtures only"; no live trace→scorecard run exists. The *sensor* gap is real even though a posture-check exists. |
| V2 | 4 | "build E1/E5/E6 through E3 is circular" | **CONFIRMED** | E3 design §9 E3d = "golden-path-style execution" (needs a test-battery to prove); §10 needs containment + a sensor. Validator-built-by-thing-under-test = F5 (consolidation-audit:21). |
| V3 | 2/3 | "4 of 7 §10 containment items unproven/absent" | **CONFIRMED** | §10 read directly (design:123–135). Items 1 (per-agent worktree isolation), 6 (conflict-safe parallel writes — `grep conflict-safe conformance/` = 0 hits), 7 (guard at fleet scale) unbuilt; 3/4 (per-agent scoped tokens, prod-cred SoD) attestation/static-structural only. Proven: 2 (egress, ts-node), 5 (kill-switch). So 2 cleanly proven, 2 attestation-only, 3 unbuilt. |
| V4 | 1/3 | "`scripts/runaway-guard.sh` called by NO live loop/adapter" | **CONFIRMED** | `grep -rn runaway-guard adapters/ scripts/ profiles/ .github/` (excl. the script itself) = **0 hits**; `grep budget.conf adapters/ profiles/` = 0. Design:92 "orchestration stays harness-local" → by design, nothing wires it yet. The conformance lock is `--selftest` only (verify.sh:81). |
| V5 | 4 | "clear M2-ratification-hardening security residue FIRST" | **REFUTED (downgraded to Low)** | ROADMAP-KIT.md:261 + CHANGELOG [3.49.1]: items (a) future-pin, (b) verdict-enum normalize, (d) ver_gt dedup **all SHIPPED**. Item **(c) explicit `/docs/governance/` CODEOWNERS rule is ABSENT** (`.github/CODEOWNERS` = `*`, `/.github/`, `/profiles/` only). BUT `* @SeaBrad72` already routes governance docs to a non-author owner → the airtightness is functionally met by the wildcard; the explicit belt-and-suspenders line named in (c) is the only residue. Not a "clear-first" blocker. |
| V6 | 5 | "mode-dial `prototype` ≡ `team` is a dead-letter" | **CONFIRMED** | `scripts/incept.sh:194` — single `prototype|team)` branch, identical `conditional-obligations.md`; only `enterprise)` differs. Routed to T4 (unbuilt). The "prototype = ceremony relief" name is a false promise today. |
| V7 | 2 | claims.tsv omits scope qualifiers (runaway / version-tag / containment) | **CONFIRMED** | claims.tsv:28 "PROVEN to contain" (no "ts-node reference"); :34 "enforces token/step/agent ceilings" (no "reported usage / best-effort tally / if-called"); :35 "VERSION agrees with the git tag state" (no "N/A in tagless PR CI"). CHANGELOG bodies are honest; the registry (the adopter-facing assertion) is not. |
| V8 | 2 | EXEC-BRIEF "+30% / +23.5%" unsourced | **CONFIRMED** | EXEC-BRIEF.md:13,23 "directional industry benchmark data", no citation anywhere; ROADMAP-KIT.md:11 lists it as open T1 residue. |
| V9 | 1 | "E3c early" framing unsupported by design doc | **CONFIRMED** | Design §9 labels E3c = "Orchestration patterns (fan-out/pipeline/adversarial-verify)" — NOT human-in-the-loop. The ex-E14 escalation fold has no assigned slice position. The reorder asserts a slice that the design hasn't decomposed. |

**Design-intent check on every cut/defer/shrink recommendation:** E9 (env/promotion governance) and E11 (AI-artifact lifecycle) — both default-KEEP confirmed: neither redundant (no other home for promotion-gate enforcement / AI-artifact audit) nor dead. Shrinking *scope* (epic → ≤2-slice vertical) is legitimate right-weighting, not a drop. **Nothing is cut.** No "low-usage" cut was attempted by any lens.

---

## 3. Ledger-1 — verified-as-quality (probed and held)

1. **The release-coherence gate works — proven in production.** The v3.49.1 `version-tag-coherent` gate caught a *real* skipped VERSION bump (3.49.0 tag on VERSION 3.49.0 mismatch) on its own release. CHANGELOG [3.49.1]; the incident self-disclosed and was fixed. The mechanism that was supposed to catch green-while-dark caught it.
2. **The tagless-CI near-miss was caught and banked.** The meta-control future-pin check passed a `git clone .` dry-run but would have failed real tagless CI; fixed (lenient-when-tags-unavailable) + lesson recorded in CHANGELOG [3.49.1]. The dry-run≠CI gap is now a known retro learning, not a latent trap.
3. **Applicability-as-detected-trigger genuinely spares the solo adopter (re-confirmed).** conformance/README.md:41–52 + M3 verified-N/A test + incept mode curation: ~half the 25 checks require a trigger a first solo project lacks. Runtime weight < on-paper weight. `conformance/mode-enforcement-blind.sh` (CI-locked) proves mode can never weaken a gate.
4. **The runaway kill-switch is a correct, immutable, conformance-locked *tool*.** `runaway-guard.sh` (step/check/reset) self-tests pass; ceiling `.kit/budget.conf` is agent-immutable (Write/Edit + shell-redirect deny, regression-locked in `agent-autonomy`); dual-reviewed incl. adversarial security verify of the fail-closed path. (Its *enforcement-in-a-loop* is E3-gated — see Ledger-2 #2.)
5. **M2 ratification self-cert gap is closed mechanically.** M2-S5 (v3.48.17): `docs/governance/.meta-control-last` + `meta-control-log.md` are control-plane (guard-core.sh deny) — an agent cannot author the marker/log. Three of four M2-hardening sub-items (a/b/d) shipped in v3.49.1; the wildcard CODEOWNERS already routes governance review to a non-author.
6. **T2 FLOOR governance is proven.** sod-check.sh 9/9 fixtures; solo self-merge BLOCK proven; agent-review genuinely adversarial (T2 findings). Only *live* enforce_admins + true 2-human approval remain (external-resource-gated, not a logic gap).
7. **E3 is right-sized as an epic.** Design §9 = 4 thin proven verticals anchored to the E2 playbook; only 2 new standing agents in the first slice. The proportion of the "E3 first" move is sound (Lens 1 Medium).

---

## 4. Ledger-2 — fix-forward (ranked, grouped into workstreams)

**No Blockers.** Highs are fix-forward, ordered so the E3-enabling ones come first.

### Workstream A — E3 kickoff-plan preconditions (do at E3 brainstorm/plan, before E3a Build)
- **[High] A1 — §10 containment-contract status table.** The E3 plan must carry a proven / attestation-only / unbuilt table for all 7 §10 items, naming items 1 & 6 as E3b build-obligations and 3/4 as E3 pre-conditions. Kills the "substrate built" over-read. *(Lens 1, 2)*
- **[High] A2 — wire `runaway-guard.sh step` into the E3 orchestration loop as E3a's first integration call-site.** Until a loop calls it, E3 dogfood runs have no live runaway ceiling beyond the platform cap. The guard is finished; this is one call site. *(Lens 1, 3)*
- **[High] A3 — lead E3 with E1-thin (oracle) + E5-thin (sensor).** E1-thin = one integration + one e2e layer wired+gated in the ts-node reference (today: flags.test.ts + health.test.ts only). E5-thin = one OTel-style trace emission + one real scorecard from the Orchestrator-to-be. Both ship BEFORE E3a; the *breadth* of E1/E5/E6 fans out after. Resolves the circular-dependency (V2). *(Lens 4)*
- **[High] A4 — position the human-in-the-loop/escalation (ex-E14) slice explicitly.** It is NOT today's E3c (V9). Assign it a slice id + position at brainstorm; the owner intent (collaboration-with-humans early) wants it ahead of E3b mechanics. *(Lens 1, 4)*
- **[High] A5 — enter E3 slice-by-slice, each with its own affirmative per-epic M verdict.** A 6-slice E3 (E3a–d + ex-E12 memory + ex-E14 escalation) entered wholesale violates the kit's own INVEST/proven-slice rule. *(Lens 4)*

### Workstream B — claims-registry honesty cleanups (cheap; one-line each; do alongside A)
- **[Medium] B1** — claims.tsv:34 runaway → append "on *reported* usage (agent-immutable config; best-effort tally; enforced when the orchestration loop calls it)". *(Lens 2, 3)*
- **[Medium] B2** — claims.tsv:28 containment-audit → append "— ts-node reference". *(Lens 2)*
- **[Medium] B3** — claims.tsv:35 version-tag-coherent → append "(enforced at tag-push; N/A in tagless PR CI)". *(Lens 2, 3)*
- **[Low] B4** — runaway ops doc honest-ceiling note: "installed + conformance-locked; enforcement path active only when an orchestrator calls it — until E3a, a ready floor with no caller." *(Lens 1)*

### Workstream C — adoptability / solo on-ramp (do before/alongside E3 — E3 widens the team signal)
- **[High] C1 — resolve the mode-dial `prototype`≡`team` dead-letter (T4).** Either genuinely lighten `prototype` output (skip BIA pointer / compliance table; pre-fill RUNBOOK skeleton) without weakening any enforced gate, OR collapse to "team / enterprise" with honest labels. E3 adds a 2nd "team" signal; leaving the false promise widens the solo gap. *(Lens 5)*
- **[Medium] C2 — partition `templates/` → core / conditional / enterprise.** Still flat (25 entries); E3 will add agent/orchestration templates → flat list gets worse. *(Lens 5)*
- **[Low] C3 — surface the solo/lite track earlier in START-HERE** (currently line 119; add to the "Who are you?" table). *(Lens 5)*

### Workstream D — verify.sh label honesty (chore; not blocking E3)
- **[Medium] D1 — relabel `version-tag-coherent` and `meta-control-fresh` in verify.sh** so the `[control]` tag reflects that the per-PR invocation is selftest/N/A only and the live enforcement lives in release-coherence.yml / drift-watch. Prevents future green-while-dark confusion. *(Lens 3)*
- **[Low] D2 — note in conformance/README** that `ci-selftest-coverage` proves the present-direction only (not stale ci.yml dead-references). *(Lens 3)*

### Workstream E — residue & sourcing
- **[Low] E1 — add explicit `/docs/governance/ @SeaBrad72` to `.github/CODEOWNERS`** (M2-hardening item c; belt-and-suspenders over the wildcard). *(Lens 4 verify, V5)*
- **[Low] E2 — fix EXEC-BRIEF unsourced stats** (cite DORA/a real study, or soften to non-numeric). Open T1 residue. *(Lens 2)*

### Workstream F — T2-team-live (external-dependency track; parallelize)
- **[Medium] F1 — provision the 2nd forge identity + org/paid repo DURING E3/E5 build, not after.** It is provisioning-gated, not a kit build. Run T2-team-live after E3a+E3c exist (so the live 2-human flow governs something real). **Include the solo-discoverability probe (T2 finding #5) with a pass/fail outcome** — do not run it as a team-path-only validation. *(Lens 1, 4, 5)*

---

## 5. The ratified next-order (synthesized)

The ratified order (ROADMAP-KIT.md:18) was: E1 · E5 · E3 · E6 · E9 · E11 → E10 → R.
The proposal was: E3-first (E1/E5/E6 *through* it) · E5 · T2-team-live · E1 · E9/E11-shrunk → E10 → R.

**Ratified synthesis — "E3 is the spine; lead it with the thin inputs it consumes; gate each slice":**

0. **M2-hardening residue close** — item (c) explicit governance CODEOWNERS line (E1). Trivial; clears the last named security sub-item. *(NOT a gate on E3 — the wildcard already covers it — but cheap to bank.)*
1. **E1-thin** — one integration + one e2e layer wired+gated in ts-node reference. The oracle E3d uses. (~1 slice)
2. **E5-thin** — one OTel-style trace emission + one real scorecard from the Orchestrator-to-be. The sensor E3's runs need. (~1 slice)
3. **E3 — decomposed, each slice its own M verdict (never entered as one epic):**
   - **E3a — thin 4-seat loop** (Orchestrator + Engineer×N + Reviewer + Security): fan-out → contain (E4 substrate) → integrate end-to-end. **Wire `runaway-guard.sh step` here (A2).** Resolve the neutral agent-definition format (design §5 open item).
   - **E3-escalation (ex-E14) — EARLY** (human-in-the-loop / escalation; the owner's collaboration headline; gates T2-team-live). Positioned ahead of E3b mechanics. *(This is the slice the BRIEF called "E3c early" — give it a real id at brainstorm; it is NOT design-§9's E3c.)*
   - **E3b — orchestration mechanics** (worktree-isolation, atomic-claim, WIP-limits, conflict re-sync — §10 items 1 & 6 proven here).
   - **E3d — phase→agent flow + behaviour conformance** (golden-path execution the roster runs).
   - **E3-memory (ex-E12) — LAST** (persistent named-agent state/handoff). Ephemeral subagents suffice for E3a–d; this is depth, not foundation.
4. **T2-team-live** — run after E3a + E3-escalation exist (live enforce_admins + 2-human approval + **solo-discoverability probe**). Provisioning parallelized during steps 1–3 (F1).
5. **E5-full** — error-tracking, on-call/SLA, the trust dashboard — fanned out through proven E3.
6. **E6** — AI-native depth (eval depth, prompt-injection/red-team, LLM cost/quality tracing) — fanned out through proven E3.
7. **E1-full** — remaining pyramid breadth (contract, a11y, security layers) — fanned out through proven E3.
8. **E9-vertical (≤2 slices)** then **E11-vertical (≤2 slices)** — confirm ≤2-slice scope at each per-epic M brainstorm (do not pre-build).
9. **E10 capstone** — holistic "is this too much?" + external-adopter validation + maintenance model.
10. **R** — subtractive refactor sweep, last.

**Parallel/standing (not in the sequence):** C1 mode-dial + C2 templates partition (adoptability, before/alongside E3); B1–B4 claim cleanups; D1 label honesty; E2 EXEC-BRIEF sourcing.

**Crux:** the reorder is right that E3 is the spine and T2-team-live comes forward; it is wrong that E1/E5 *trail* E3 as fan-outs — a thin slice of each must **lead** E3 (oracle + sensor the design consumes), and E3 enters as 5 M-gated slices with escalation early and agent-memory last.

---

## 6. Retro fold-in (last N slices: E4d, M2-ratification-hardening + its 2 release incidents)

| Learning | Source | Routes into |
|----------|--------|-------------|
| A gate can validate the script but not its *call site* — "installed" ≠ "enforced in a loop". E4d shipped conformance-locked yet uncalled. | E4d / V4 | **DEVELOPMENT-STANDARDS** (a control claim must name its enforcement *path*, not just the artifact) + **claims-registry convention** (B1) |
| Building the perimeter before the building (F5) recurs — E4 sized to an unbuilt E3's §10; the reorder nearly repeated it (E1/E5 through E3). | consolidation-audit + V2 | **DEVELOPMENT-PROCESS** §Discovery (add a "validator-independence" check: never build the oracle/sensor with the thing under test) |
| A `git clone .` dry-run is NOT real tagless CI — the future-pin check passed the dry-run, failed real CI. | M2-hardening incident #2 | **MAINTAINING.md** (release verification must run the *actual* CI checkout shape, esp. fetch-depth) |
| A skipped VERSION bump is invisible to per-PR CI; only the tag-push job catches it. The gate worked — but its scope must be stated. | M2-hardening incident #1 | **claims-registry** (B3) + **verify.sh label** (D1) |
| The meta-control self-cert gap (S4 finding) was real and is now mechanically closed — confirms the panel machinery earns its keep. | M2-S5 | **meta-control.md** (no change needed; banked as Ledger-1 evidence) |
| `prototype`≡`team` has been a known false-promise across M1→M3→now without resolution — recurring un-actioned finding. | V6 / Lens 5 | **ROADMAP backlog** (escalate T4 mode-dial from "tracked" to scheduled before E3, C1) |

---

## 7. Routing

**Become ROADMAP / backlog entries (feature/sequencing):**
- The ratified order in §5 → update `docs/ROADMAP-KIT.md` item 5 (the build order) + the E3 epic decomposition (5 M-gated slices).
- A1–A5 (E3 kickoff-plan preconditions) → E3 brainstorm/plan checklist.
- C1 (mode-dial T4), C2 (templates partition) → scheduled backlog, before/alongside E3.
- F1 (T2-team-live provisioning + solo-discoverability probe) → parallel track entry.

**Become human-ratified guardrail / standards PRs (control-plane — agent proposes, human commits):**
- B1–B3 → `conformance/claims.tsv` edits (adopter-facing assertions; human ratifies).
- D1 → `conformance/verify.sh` label change.
- E1 → `.github/CODEOWNERS` governance line.
- Retro fold-ins → `DEVELOPMENT-STANDARDS` (claim-must-name-enforcement-path), `DEVELOPMENT-PROCESS` (validator-independence check), `MAINTAINING.md` (real-CI-shape release verification).

**Doc-only (no ratification):**
- B4 (runaway ops honest-ceiling note), D2 (conformance/README direction note), E2 (EXEC-BRIEF sourcing), C3 (START-HERE solo track surfacing).

---

## 8. Ready-to-commit snippets

### (a) Verdict log row — append to `docs/governance/meta-control-log.md`

```
| 2026-06-26 | 3.49.1 | E3-epic boundary + reorder ratification | light (5-lens) | GO-WITH-CONDITIONS | docs/architecture/2026-06-26-meta-control-4.md | 0 blockers · 7 high (all fix-forward: §10 status table, wire runaway-guard in E3a, lead E3 with E1-thin+E5-thin oracle/sensor, position escalation slice, gate E3 slice-by-slice, mode-dial T4, T2-team-live provisioning) · reorder GO with the E1/E5-lead-E3 correction; nothing cut (E9/E11 KEEP-shrunk) |
```

### (b) Marker — overwrite `docs/governance/.meta-control-last`

```
3.49.1 GO-WITH-CONDITIONS
```
