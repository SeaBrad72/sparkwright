# Proportional Promotion Contract — Slice 3: proportional gates + honest team/solo state label

**Date:** 2026-06-30
**Status:** Owner-approved (design gate passed 2026-06-30)
**Epic:** Proportional Promotion Contract (`docs/governance/promotion-contract.md`); epic design `2026-06-29-proportional-promotion-contract-design.md`.
**Slice:** 3 of 4. Prior: Slice 1 model/standards keystone (v3.76.0), Slice 2 advisory change-class classifier + surfacing (v3.81.0). Next: Slice 4 (relax agent-commit + delegable execution post-GO).
**Change-class:** Control-plane (touches CI + the `agent-boundary` gate) → human-ratified; built AMBER.

---

## Problem (what this slice fixes)

Slice 1 documented the contract matrix; Slice 2 shipped the *advisory* classifier that surfaces a change-set's class but never gates (`promotion-readiness.sh`, exit 0 always, exposing a stable `--class` seam "slice 3 consumes"). Two things the matrix promises are still un-enforced and the gate still lies about one of them:

1. **The `control-plane-ratification` gate emits a lying binary.** Today it concludes `success` / `action_required` / `failure` (`.github/workflows/ci.yml:351-389`, driven by `conformance/agent-boundary.sh`). It never names *which* separation-of-duties (SoD) reality produced the conclusion — a real second-reviewer approval (team) versus a logged solo admin-override (the compensating control). `docs/operations/review-lane.md` already documents that distinction in prose; the gate does not surface it.
2. **The gate is not class-aware.** It is binary (control-plane present or not). The human rendering a GO does not see the change-class (`ordinary | sensitive | control-plane`) the matrix proportions rigor against — even though Slice 2 already derives it.

## Goal

Make the gate **honest and class-aware** without adding a parallel gate. Every new output is a *derivation of signals the gate already computes* (`ratified` from a non-author approval; control-plane-presence from `is_control_plane_path`). This is "make the gate tell the truth," not "build new machinery."

**Auto-GO is explicitly out of scope** (owner-ratified 2026-06-30). The trust-modulated auto-approval at Ordinary×Integration depends on `scripts/agent-scorecard.sh` having real accumulated trace data ("scorecard live"), which it does not. Wiring it now would either never fire (thin-data fail-safe → "steady, no directive") or relax approval on an unproven trust signal (violates honest-ceiling). It defers to a Slice-4-adjacent follow-on gated on "scorecard live"; when it lands it inherits the scorecard's asymmetry (instant auto-downgrade on regression, human-ratified raise on earned). The **Spike×Ordinary "no human gate"** cell stands as already designed — its safety is blast-radius-zero + the deferral-not-waiver ratchet, not a trust score; and the kit itself rarely operates at Spike (it is mostly an adopter-facing prescription).

---

## The two derivations (the design's core)

At gate time (pre-merge, PR context) the gate already holds `control-plane-present` and `ratified`. The honest state label is a pure function of those two:

| control-plane present? | `ratified` (non-author approval present?) | State label |
|---|---|---|
| yes | 1 | `RATIFIED-BY-SECOND-REVIEWER` — team; SoD genuinely exercised |
| yes | 0 | `SOLO-ADMIN-OVERRIDE-LOGGED` — solo; the only merge path is the logged `enforce_admins:false` admin-override; honestly weaker, and the label says so |
| no | (either) | *(no label — N/A; the gate is green, there is nothing to ratify)* |

**Honest ceiling (stated up front).** The label is a **pre-merge projection**, not a post-merge audit record. In the solo case it reads "*will be* `SOLO-ADMIN-OVERRIDE-LOGGED` if merged via admin-override" — it names the SoD reality the merge will have; it cannot observe the future keystroke. The slice changes **no solo behaviour**: solo still merges via logged `--admin`. It makes the gate *tell the truth* about that; it does not fake a second reviewer (epic design §"Solo vs team"; `review-lane.md` §"Compliance honesty").

---

## Human-facing legibility (owner requirement, 2026-06-30)

**Whenever a human is needed, the surface they read must be legible and unambiguous on its own** — no jargon-only output, no implied knowledge. The stable tokens (`RATIFIED-BY-SECOND-REVIEWER` / `SOLO-ADMIN-OVERRIDE-LOGGED`) are **machine identifiers** (the conformance lock greps for them; they must stay byte-stable), but every human-facing surface — the `control-plane-ratification` check-run title and summary — **pairs the token with plain language** answering five questions:

1. **What happened** — what changed and its change-class.
2. **What it means** — why this is gated (a §13 governance merge-gate, *not* a build failure / no test failed).
3. **The honest SoD state** — second-reviewer vs. solo admin-override, said plainly.
4. **What to do next** — the concrete action(s), with the exact command for the solo path.
5. **Where to read more** — `docs/operations/review-lane.md`.

The single surface that matters most is the **`action_required`** state — the only conclusion where a human is actually required. Canonical copy (the build implements this, not terse strings):

> **Title:** `Ratification required — a control-plane change is awaiting a human`
>
> **Summary:**
> `What changed: a control-plane change (the kit's own guardrails / CI / standards / governance). Change-class: control-plane.`
> `Why: control-plane changes must be ratified by a human before merge. This is a §13 governance merge-gate, NOT a build failure — no test failed.`
> `Current SoD state: SOLO-ADMIN-OVERRIDE-LOGGED — no non-author approval is present yet, so the only merge path is a logged solo admin-override (honestly weaker than a second reviewer).`
> `To proceed: (a) get a non-author approval on this PR → becomes RATIFIED-BY-SECOND-REVIEWER; or (b) solo — merge via 'gh pr merge --squash --admin --delete-branch'; GitHub logs the override as the audit trail.`
> `More: docs/operations/review-lane.md.`

The `success` state is similarly glossed (`ratified by a second reviewer` vs. `no control-plane change — nothing to ratify`); the `failure` state states plainly that the gate could not evaluate the diff and is the one conclusion that *is* a real error. **Principle:** the token is for the machine, the sentence is for the human — every human-needed surface carries both.

---

## Mechanics — where each piece lives

Kit principle: decision logic stays pure and `--selftest`-able in a conformance script; CI only wires inputs → outputs.

### 1. State label → `conformance/agent-boundary.sh`
Add a pure `ratification_state()` derivation (sibling to `boundary_decide`, sourcing the same `is_control_plane_path`) that emits the label from `(control-plane-present, ratified)`. Because it is pure, the **selftest exercises it in-process** — that is where the teeth live.

- The gate's **pass/fail teeth are unchanged**: control-plane still requires ratification, fail-closed; the three-state (0 hold / 1 violation / 2 unverified, with CI/`--require` escalation) is untouched.
- The label is **additive output** — a new line / a new flag (`--state` or appended to the existing verdict text) the CI step reads. Exact surface pinned at plan time; constraint: it must not change exit codes (so existing callers and the existing selftest cases stay green).

### 2. Class-awareness → surfaced in `.github/workflows/ci.yml`
The `control-plane-ratification` step calls Slice 2's seam: `sh conformance/promotion-readiness.sh --class --no-verify --changed /tmp/changed.txt`. The aggregate class enriches the check-run **title/summary** (names the `class × rung` cell; points Sensitive changes at `review-lane.md`'s high-risk lane).

- `--no-verify` keeps it cheap and pure (classification only; no `verify.sh` sub-invocation — avoids cost and any circularity in CI).
- The class does **not** change the gate's pass/fail. Sensitive changes get **no new blocking mechanism** — `review-lane.md` (the high-risk lane, recorded `REVIEW-RECORD` + `security-reviewer`) is already the home for that rigor; duplicating it in CI would be ceremony (right-weight / anti-ceremony discipline).
- The rung at this gate is **Integration** (PR). The label and class are surfaced for the human GO; nothing here auto-approves.

### 3. Lock → new claim `proportional-gate` (`conformance/proportional-gate-wired.sh`)
A wiring lock (mirrors `promotion-readiness-wired.sh` / `golden-path-filter-parity.sh`) asserting:
- (a) `agent-boundary.sh` can emit **both** labels (drives `ratification_state()` over team and solo fixtures and checks the exact tokens);
- (b) `ci.yml` surfaces the state label **and** calls `promotion-readiness.sh --class` in the `control-plane-ratification` step.

**Non-vacuity (load-bearing negative):** a mutation that makes `ratification_state()` always emit `RATIFIED-BY-SECOND-REVIEWER` must flip the solo selftest case to FAIL; a mutation removing the `--class` call from `ci.yml` must flip the wiring assertion to FAIL. Both proven by hand at build time and shipped as selftest cases.

---

## Files touched (all already control-plane → AMBER apply; no new guard-matcher work)

- `conformance/agent-boundary.sh` — `ratification_state()` + new selftest cases.
- `.github/workflows/ci.yml` — surface state label + class in the `control-plane-ratification` check-run.
- `conformance/proportional-gate-wired.sh` — **new** lock (+ register the `proportional-gate` claim in the claims registry / `claims.tsv`).
- `docs/governance/promotion-contract.md` — build-status table: Slice 3 → shipped (version stamped at ship).
- `DEVELOPMENT-PROCESS.md` §13 — one reference line that the ratification gate now emits the team/solo state label (additive; respect the doc-budget ratchet).
- `docs/operations/review-lane.md` — optional one-line cross-reference that the gate now surfaces the label it documents.
- `VERSION` · `CHANGELOG.md` · `README.md` — version finishing **folded into `apply.py`** (standing fix: the human keeps skipping the bump → red tag; fold it in so it cannot be skipped).

**Notably NOT touching `guard-core.sh`.** This is guard-*adjacent* (CI + the boundary gate), not guard-core editing — no new control-plane path is created, so the three-matcher completeness work does not apply. Still fail-closed enforcement, so the subagent-driven build + dual review (correctness + security) stands.

---

## Build & review plan

- **Build:** subagent-driven (owner-ratified) — a different mind builds against the plan than reviews it, because this is the epic's first fail-closed enforcement slice. Dogfood the kit's `plan` skill to produce the plan; the engineer subagent builds; AMBER `apply.py`, clone-proven.
- **Review:** dual — `reviewer` (correctness; builder ≠ reviewer) + `security-reviewer` (the SoD/label-honesty lens — the projection-tense and any way the label could over-claim a protection not exercised).
- **Meta-control:** per-slice panel (Kit-Steward), governance close as a **separate** human-run `governance-close.py` (the agent must not self-certify its own GO — M2-S5).
- **Ship:** standing flow — `apply.py` → governance close → commit (`git show --stat` confirms every expected file landed — the keystone-coupling lesson) → push → PR → green conformance → admin-merge (solo control-plane PR goes red on `control-plane-ratification` by design → `gh pr merge --squash --admin --delete-branch`) → `git checkout main && git pull && sh scripts/release-tag.sh`.

## Acceptance criteria

1. `agent-boundary.sh` emits `RATIFIED-BY-SECOND-REVIEWER` for a control-plane + ratified fixture and `SOLO-ADMIN-OVERRIDE-LOGGED` for a control-plane + unratified fixture, and no label for an ordinary diff — proven by `--selftest`, with the always-team mutation flipping the solo case to FAIL.
2. The `control-plane-ratification` check-run surfaces both the state label and the change-class; the class comes from `promotion-readiness.sh --class --no-verify`. **Legibility:** the human-needed (`action_required`) summary pairs the machine token with plain language covering all five questions (what changed · what it means · honest SoD state · what to do, incl. the exact solo command · where to read more) — verified by the lock greping the summary for the plain-language anchors *and* the token, not the token alone.
3. `conformance/proportional-gate-wired.sh --selftest` passes and is non-vacuous (both load-bearing negatives proven).
4. The gate's existing pass/fail behaviour and exit codes are unchanged (all current `agent-boundary --selftest` cases stay green).
5. Fresh-clone `verify --require` green; claim count +1; CHANGELOG/VERSION/README coherent at ship.

## Honest ceilings (recap — what this does NOT claim)
1. The label is a pre-merge projection, not a post-merge audit record.
2. Solo SoD is still not truly satisfied — the label *names* that; it does not fix it (out of scope, by design).
3. Class-awareness informs the human GO; it does not auto-decide. Judgment quality stays un-gateable (same ceiling as the `operating` skill).
