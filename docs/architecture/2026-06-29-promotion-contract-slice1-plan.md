# Plan — Proportional Promotion Contract, Slice 1 (model + standards keystone)

**Planned via the kit's own `plan` skill** (`skills/plan/SKILL.md`). Source design (owner-ratified, PR #222): `docs/architecture/2026-06-29-proportional-promotion-contract-design.md` → "Build model" slice 1.

---

## Goal
Document the proportional promotion contract — the `rigor = f(rung × change-class)` model, the change-class definitions, the deferral-not-waiver ratchet, the promotion-readiness + GO/NO-GO contract, and DoD/acceptance-criteria-as-content — into the kit's governing docs, and lock it with one conformance check that proves the model is stated coherently and **cannot silently relax the control-plane column**.

## Architecture
Pure authoring + one doc-coherence guard. A new canonical model doc (`docs/governance/promotion-contract.md`) holds the matrix and definitions; `DEVELOPMENT-PROCESS.md` §9 (Environments) and §13 (Agent Governance) gain short proportional-promotion subsections that **reference** the model doc (single source of truth, no duplication); `CLAUDE.md`'s DoR/DoD gain pointer lines. A new `conformance/promotion-contract-documented.sh` (modeled on `assurance-tiers.sh`) asserts the model's load-bearing invariants are present and the control-plane column is human-governed, with a `--selftest` whose load-bearing negative is a doc that relaxes the control-plane column → must FAIL. Wired as a `[control]` check + a new `promotion-contract` claim.

## Tech Stack
POSIX sh (`/bin/sh`, dash-clean) for the conformance check; Markdown for docs; Python 3 stdlib for the AMBER `apply.py`. No new dependencies.

## Global Constraints (verbatim from the design spec)
- **Control-plane column stays human-ratified at every applicable rung.** "The redesign does **not** relax this; it relaxes the *Ordinary* class where the ceremony is currently miscalibrated."
- **Fail-safe derivation:** "when classification is uncertain, default to the **higher** class … a change cannot relax itself by mislabeling."
- **Relaxation = deferral, not waiver:** "A change that skipped ceremony at Spike carries **no relaxation upward** … Rigor ratchets at every promotion."
- **GO/NO-GO judgment, not keystroke:** "the human renders an explicit GO whose depth equals the cell's rigor … Execution after GO is delegable … the judgment is the control."
- **Honest ceilings:** judgment quality is un-gateable; the classifier is fail-safe not omniscient; solo SoD cannot be truly satisfied (named via the state label, not faked green).
- **Right-weight / default-KEEP:** "Most of it is *connecting/proportioning/documenting what exists* … not new machinery." Slice 1 adds **no new gate, no enforcement, no behavior change** — only documentation + a documentation-drift guard.
- Stack-neutrality: the model doc and process prose stay stack-neutral; nothing leaks `~/.claude/CLAUDE.md` maintainer context (harness-neutrality boundary).

## Build model — **AMBER** (control-plane)
Every file in this slice is control-plane (governing docs, `conformance/`, `claims*`, `verify.sh`, `ci.yml`, `VERSION`). Therefore: author under `scratchpad/promotion-contract-s1/`, assemble an **idempotent `apply.py`**, clone-prove it (selftest + verify), and hand to a human to apply. **No silent agent commit.** The governance marker + meta-control-log close is a separate human-applied step (M2-S5 — guard-blocked from the agent). Version finishing (VERSION→`3.76.0`, README badge, CHANGELOG) is folded INTO `apply.py`.

---

## File-structure map (every file, single responsibility)

### New files
| File | Responsibility |
|------|----------------|
| `docs/governance/promotion-contract.md` | **The canonical model doc.** The matrix (3 change-classes × 5 rungs), change-class definitions + fail-safe derivation, deferral-not-waiver ratchet, promotion-readiness + GO/NO-GO contract, DoD/acceptance-criteria-as-content, solo↔team state label, honest ceilings. The single source of truth everything else references. |
| `conformance/promotion-contract-documented.sh` | Doc-coherence guard: asserts the model doc states each invariant marker and the control-plane column is human-governed; `--selftest` proves the control-plane-relaxation negative FAILS. |

### Modified files
| File | Change |
|------|--------|
| `DEVELOPMENT-PROCESS.md` | §9 *Environments & promotion*: add a short "Proportional promotion (rung × change-class)" subsection that frames the existing Dev/QA/UAT/Prod tiers as the rungs and points to the model doc. §13 *Agent Governance*: add a "Change-class & the promotion contract" subsection connecting the autonomy tiers (who acts) to the change-class axis (what's changing), with the deferral-not-waiver ratchet + GO/NO-GO-not-keystroke, pointing to the model doc. |
| `CLAUDE.md` | DoR: one pointer line under the conditional flags noting change-class is derived at promotion. DoD: one pointer line on the Review/Production rows noting the GO/NO-GO judgment + promotion-readiness surfacing live in the promotion contract. (Pointers only — `CLAUDE.md` stays the authoritative *summary*; the model doc holds detail.) |
| `conformance/claims.tsv` | Add row: `promotion-contract` claim. |
| `conformance/claims-registry.sh` | Add `promotion-contract` to `REQUIRED_IDS`. |
| `conformance/verify.sh` | Add `check control promotion-contract sh conformance/promotion-contract-documented.sh`. |
| `.github/workflows/ci.yml` | Add a step running `sh conformance/promotion-contract-documented.sh --selftest` (mirrors the existing per-control selftest steps). |
| `VERSION` | `3.75.0` → `3.76.0` (folded into apply.py). |
| `README.md` | Version badge bump (folded into apply.py). |
| `CHANGELOG.md` | New `3.76.0` entry (folded into apply.py). |

### Human-applied separately (NOT in apply.py — guard-blocked, M2-S5)
| File | Change |
|------|--------|
| `docs/governance/meta-control-log.md` | Panel #27 row + marker → `3.76.0 GO`. Delivered as a copy-paste `GOVERNANCE-CLOSE.md`. |
| `docs/ROADMAP-KIT.md` | Tick "Slice 1" done in the priority sequence (small edit; can ride the same PR by hand or fold into apply.py as a non-guarded doc — **decision: fold into apply.py**, it's a plain roadmap edit, not a marker). |

---

## Tasks

### Task 1 — The canonical model doc (`docs/governance/promotion-contract.md`)
**Deliverable:** the model doc exists and states every load-bearing invariant the conformance check will assert.

Because this is a documentation deliverable, the "test" is the conformance check (Task 2) — they're authored as a pair (test-first: write the check's required markers list, then author the doc to satisfy it). TDD order:

1. **(red)** Draft the `MARKERS` the check will require (Task 2 step 1) — the list below — and run the check against an empty/stub doc: expect FAIL (missing markers).
2. **(green)** Author `docs/governance/promotion-contract.md` containing, each as an explicit, greppable statement:
   - **Title + status** line ("canonical model", references the design doc).
   - **The model sentence:** `rigor = f(rung × change-class)`, trust as a modulator (a dial, not a third axis).
   - **The matrix** — a Markdown table with the three change-class columns headed exactly **Ordinary**, **Sensitive**, **Control-plane**, and the five rung rows **Spike**, **Integration**, **Release candidate**, **Staging/UAT**, **Production**. The Control-plane column's cells each state a human-governed disposition (e.g. `Human-authored`, `AMBER apply + control-plane-ratification`, `human ratify + meta-control`, `N/A`) — **never** an "agent autonomous" disposition. (This is the row the negative test guards.)
   - **Change-class definitions** — Control-plane (path-derived, names `is_control_plane_path`), Sensitive (path-heuristic + declared + reviewer-confirmable), Ordinary (default).
   - **Fail-safe derivation** statement — "default to the higher class; derived not self-asserted; verified at the promotion gate."
   - **Deferral-not-waiver** statement — "no relaxation upward; rigor ratchets at every promotion; gates fire on the whole accumulated change."
   - **Promotion-readiness surfacing** — what it contains (change, change-class, blast radius, proven-vs-attested, DoD + acceptance-criteria status, what could regress).
   - **GO/NO-GO judgment, not keystroke** — depth equals the cell; execution delegable post-GO; the judgment is the control.
   - **DoD + acceptance criteria as the content of the RC go/no-go** (frame vs content).
   - **Solo vs team** — the two state labels verbatim: `RATIFIED-BY-SECOND-REVIEWER` and `SOLO-ADMIN-OVERRIDE-LOGGED`; never claims a protection not exercised.
   - **Honest ceilings** — the three from the design.
   - A "What this slice does / does not do" note: documents the model; adds no enforcement (that's slices 2–4).
3. **(green)** Run `sh conformance/promotion-contract-documented.sh docs/governance/promotion-contract.md` → expect PASS.
4. **Commit** (into the scratchpad working tree).

**Honest ceiling:** this task proves the model is *written down coherently*. It does not prove anyone *follows* it — enforcement is slices 2–4; judgment quality stays un-gateable (stated in the doc).

**Parallel-safety:** must serialize with Task 2 (same marker contract). Tasks 3–4 (process/CLAUDE edits) are disjoint files and may run after Task 1's marker list is frozen.

### Task 2 — The conformance guard (`conformance/promotion-contract-documented.sh`)
**Deliverable:** a POSIX-sh check with `--selftest`, modeled on `assurance-tiers.sh`, that (a) passes against the real model doc and (b) has a load-bearing negative.

1. **(red)** Write `check_file <doc>` that asserts:
   - Each required prose marker is present (`grep -qiE` per marker): the model sentence, fail-safe-derivation, deferral-not-waiver, GO/NO-GO-not-keystroke, promotion-readiness, both state-label tokens, and the matrix header containing all three change-class column names.
   - **The load-bearing structural assertion:** in the matrix, the **Control-plane column never carries an "autonomous"/"no human gate" disposition.** Implemented by locating each rung row and asserting its Control-plane cell matches a human-governed token (`Human-authored|AMBER|ratify|meta-control|human|N/A`) and does NOT match `autonomous|no human gate|agent self`. (Mirror assurance-tiers' "match the row, compare the cell exactly, not a substring anywhere" discipline so prose elsewhere can't mask a revert.)
   Run against a stub → FAIL.
2. **(green)** Run against the Task-1 doc → PASS.
3. **(red→green) `--selftest`** with `mktemp` fixtures (leave fixtures in place — no `rm -rf`, per the 7e guard convention in `assurance-tiers.sh`):
   - **good** fixture (all markers + human-governed control-plane cells) → must PASS.
   - **missing-marker** fixture (drop the deferral-not-waiver line) → must FAIL.
   - **control-plane-relaxed** fixture (the load-bearing negative: a matrix whose Control-plane × Integration cell reads `Agent autonomous`) → must FAIL. *This is the non-vacuity anchor — a dead/always-pass check fails this case.*
   - **prose-mask** fixture (control-plane cell reverted to `Agent autonomous` but a prose line elsewhere says "control-plane stays human") → must FAIL (cell wins, not substring).
4. **(green)** `sh conformance/promotion-contract-documented.sh --selftest` → OK; `sh conformance/shellcheck.sh` clean; confirm dash-clean (`dash conformance/promotion-contract-documented.sh --selftest`).
5. **Commit.**

**Honest ceiling:** the check proves the model is *documented* with a human-governed control-plane column. It does NOT prove the running gates enforce it (that's the `agent-boundary`/`control-plane-ratification` gates, unchanged here). Stated in the check's header comment.

**Parallel-safety:** serialize with Task 1 (shared marker contract).

### Task 3 — `DEVELOPMENT-PROCESS.md` §9 + §13 extensions
**Deliverable:** both sections gain a short proportional-promotion subsection referencing the model doc; existing content unchanged.

1. **(red)** Add to the check (Task 2) two cross-reference assertions OR keep them out of the lock — **decision:** keep §9/§13 cross-refs OUT of the conformance lock to avoid over-coupling the guard to prose churn; instead self-review verifies the references resolve. (Rationale: the lock guards the *model's* invariants; the process-doc pointers are navigational. Over-locking prose creates brittle false-reds — a known T4 theme.)
2. **(green)** §9 *Environments & promotion*: after the tiers table, add ~5 lines: "These tiers are the **rungs** of the promotion contract; rigor at each promotion scales with rung × change-class (`docs/governance/promotion-contract.md`). Production stays human-gated (already stated). Relaxation is deferral-not-waiver — gates fire in full at each promotion on the whole accumulated change."
3. **(green)** §13 *Agent Governance*, after the autonomy-tiers + ratification subsections: add a "Change-class & the promotion contract" subsection (~8 lines): the autonomy tiers answer *who acts*; the **change-class** axis (Ordinary / Sensitive / Control-plane) answers *what's changing*; together they set ceremony via the contract matrix. The **GO/NO-GO is a recorded judgment, not a keystroke** (execution delegable post-GO). The **Control-plane column stays human-ratified** — this redesign does not relax it. Point to `docs/governance/promotion-contract.md`.
4. **(verify)** `sh conformance/check-links.sh` passes (new internal links resolve); self-review the prose reads coherently with the existing tiers.
5. **Commit.**

**Parallel-safety:** disjoint file from Tasks 1/2/4 → may run in parallel after the model-doc path is fixed.

### Task 4 — `CLAUDE.md` DoR/DoD pointer lines
**Deliverable:** DoR and DoD each gain one pointer line to the promotion contract; the file stays the authoritative summary.

1. **(green)** DoR conditional-flags area: add a line — change-class (Ordinary/Sensitive/Control-plane) is **derived at promotion, not self-asserted** (`docs/governance/promotion-contract.md`); Sensitive/Control-plane raise the gate.
2. **(green)** DoD: on the **Review & merge** + **Production** rows, add that the human **GO/NO-GO** at Release-candidate/Production is a recorded judgment against a **promotion-readiness surfacing** (DoD + acceptance-criteria are its content) — per the promotion contract.
3. **(verify)** `sh conformance/check-links.sh`; confirm `CLAUDE.md`-wins-on-overlap is preserved (pointers, not contradictions). Re-read against `DEVELOPMENT-STANDARDS.md §2` summary↔expansion agreement rule — no divergence introduced.
4. **Commit.**

**Parallel-safety:** disjoint file → parallel with Task 3.

### Task 5 — Wiring (claims, registry, verify, ci) + version finishing in `apply.py`
**Deliverable:** the claim is registered everywhere the kit requires (6-point registration, doc-check variant) and the version is finished; all assembled idempotently in `apply.py`.

1. `conformance/claims.tsv`: add
   `promotion-contract\tthe proportional promotion contract is documented coherently (rigor=f(rung×change-class); matrix of 3 change-classes × 5 rungs with the control-plane column human-governed; fail-safe derivation; deferral-not-waiver ratchet; GO/NO-GO-not-keystroke; solo/team state labels) in docs/governance/promotion-contract.md + referenced from DEVELOPMENT-PROCESS §9/§13 + CLAUDE.md DoR/DoD\tsh conformance/promotion-contract-documented.sh --selftest`
2. `conformance/claims-registry.sh`: append `promotion-contract` to `REQUIRED_IDS`.
3. `conformance/verify.sh`: add `check control promotion-contract  sh conformance/promotion-contract-documented.sh` (with the live doc-path default, near the other doc-coherence controls e.g. after `assurance-tiers`).
4. `.github/workflows/ci.yml`: add a step `- run: sh conformance/promotion-contract-documented.sh --selftest` in the conformance job (mirror the `assurance-tiers` / per-control selftest steps).
5. **Adopter-export carve:** check whether `docs/governance/` and `docs/architecture/` are already export-ignored (`adopter-export.sh` + `.gitattributes`). The model doc is kit-governance, likely already carved with `docs/governance/`. **Verify, don't assume** — if `docs/governance/` ships to adopters, the model doc SHOULD ship (it's adopter-useful guidance, unlike dated design docs). **Decision:** model doc ships to adopters (it's reference guidance); the *plan* and *design* docs under `docs/architecture/` stay carved per the existing T4 `export-ignore docs/architecture/` item. Confirm at build time.
6. **Version finishing (in apply.py):** `VERSION`→`3.76.0`; `README.md` badge; `CHANGELOG.md` `## [3.76.0]` entry. Also tick Slice 1 in `docs/ROADMAP-KIT.md`.
7. **(verify)** On a fresh `git clone .` (tagless — per the tagless-clone-CI standing practice): run `sh conformance/promotion-contract-documented.sh --selftest`, `sh conformance/verify.sh --require` (expect `promotion-contract` PASS, control-plane-ratification the only by-design red), `sh conformance/claims-registry.sh`, `sh conformance/shellcheck.sh`, and re-run `apply.py` to prove idempotence.
8. **Commit** the assembled `apply.py` + `applied-diff.patch` into scratchpad.

**Honest ceiling:** `verify.sh` PASS proves the claim's *check* passes (model documented coherently). It does not prove slices 2–4 exist — the claim's text is scoped to "documented," not "enforced."

---

## Self-review (skill step 6)

**Spec coverage** — every design "Build model · slice 1" requirement maps to a task:
- matrix + change-class defs + deferral-ratchet + promotion-readiness + GO/NO-GO + DoD-as-content → Task 1 (model doc) ✓
- into `DEVELOPMENT-PROCESS.md` (§13 + Environments) → Task 3 ✓
- CLAUDE.md DoR/DoD references → Task 4 ✓
- "a conformance check that the model is documented coherently and consistently with the existing tiers" → Task 2 ✓ (the consistency-with-tiers angle = the control-plane-column-stays-human structural assertion + §9/§13 framing the existing Dev/QA/UAT/Prod tiers as rungs)
- "Mostly authoring; low code. Unblocks the rest." → honored: no enforcement, no behavior change ✓

**Placeholder scan** — no "add error handling / handle edge cases / write tests for the above." Each task carries concrete content, exact paths, exact commands + expected outcomes. ✓

**Type/name consistency** — claim id `promotion-contract` used identically in claims.tsv / REQUIRED_IDS / verify.sh / ci.yml. Check filename `promotion-contract-documented.sh` consistent throughout. Model doc path `docs/governance/promotion-contract.md` consistent. ✓

**Non-vacuity** — Task 2 step 3 names the load-bearing negative (control-plane-relaxed fixture must FAIL) and the prose-mask anti-gaming fixture, exactly mirroring the proven `assurance-tiers.sh` discipline. ✓

**AMBER routing** — all control-plane files identified up front; assembled into `apply.py`; governance-marker close split out as human-applied (M2-S5). Version finishing folded in. ✓

**Honest ceiling per task** — stated for Tasks 1, 2, 5. ✓

**Decisions made at plan-time (flagged for owner):**
1. **Model doc location** = `docs/governance/promotion-contract.md` (beside `meta-control-log.md`; ships to adopters as reference). *Alternative: `docs/` top-level.*
2. **§9/§13 cross-refs kept OUT of the conformance lock** (navigational pointers; locking prose invites brittle false-reds — a known T4 theme). The lock guards the model doc's invariants only.
3. **Roadmap tick folded into apply.py** (plain doc edit, not a governance marker).

**Open questions deferred to enforcement slices (not blocking Slice 1):** exact relaxed gate set (slice 3); acceptance-criteria sourcing across trackers (slice 2); trust-modulation auto-GO scope (slice 3). All documented in the design's "Open questions for plan-time" and restated in the model doc as "enforced in slices 2–4."

## Terminal state
This saved, self-reviewed plan. Hand to the kit `tdd` + build flow (a fresh agent per task; Tasks 3 & 4 may parallelize). Dual review (independent Reviewer + Security-reviewer) before the human ship sequence.
