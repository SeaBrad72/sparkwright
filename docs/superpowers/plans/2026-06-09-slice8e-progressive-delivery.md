# Slice 8e — Progressive-delivery reference + smoke gates — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the progressive-delivery reference (multi-stage smoke gates, canary/blue-green, canary analysis), wire a stack-neutral smoke gate into the §14 `deploy-prod` reference, and tighten the existing 8b deployable checklist's smoke row — no new conformance script.

**Architecture:** A reference slice. One new doc (`docs/operations/progressive-delivery.md`) + targeted edits to §14 (smoke-gate snippet), the 8b checklist (tighten rows 5/6), §10, the DoD, and the conformance README. The existing 8b `definition-of-deployable.md` is the conformance — 8e completes the reference leg of the triad.

**Tech Stack:** Markdown, GitHub Actions YAML (inert reference snippet), `git`.

**Spec:** `docs/superpowers/specs/2026-06-09-slice8e-progressive-delivery-design.md`

---

## File structure

| File | Responsibility | Change |
|------|----------------|--------|
| `docs/operations/progressive-delivery.md` | Strategies + multi-stage smoke + canary analysis + rollback | **Create** |
| `DEVELOPMENT-STANDARDS.md` §14 | `deploy-prod` reference gains deploy → smoke → rollback-on-fail | Modify (1 block) |
| `conformance/definition-of-deployable.md` | Tighten rows 5 + 6 (blank) + row 6 worked | Modify (3 rows) |
| `DEVELOPMENT-PROCESS.md` §10 | Reference the new doc | Modify (1 line) |
| `CLAUDE.md` DoD Production line | "smoke-tested" → reference the gate pattern | Modify (1 line) |
| `conformance/README.md` | Pairing note (no new check) | Modify (1 note) |
| `VERSION` / `CHANGELOG.md` / `docs/ROADMAP-KIT.md` | Release meta | Modify |

---

### Task 1: Create `docs/operations/progressive-delivery.md`

**Files:**
- Create: `docs/operations/progressive-delivery.md`

- [ ] **Step 1: Create the file with EXACTLY this content**

```markdown
# Progressive Delivery — Reference

How to roll out a release **without big-bang risk**: validate on a slice before full exposure, and gate every promotion with a smoke/synthetic check. Stack-neutral; tooling is a project/Org choice. The executable half of `DEVELOPMENT-PROCESS.md` §10 (Safe Change Delivery). Pairs with the Release gate `conformance/definition-of-deployable.md`.

> **Principle — reduce blast radius.** Never expose 100% of users to an unverified release. Ship to a slice, prove it, then widen. The cheapest rollback is the one you make before you widen.

## Strategies
- **Staged rollout** — staging → small % → full. The §10 default and the Stage-1 baseline; no special tooling needed.
- **Canary** — deploy to a small **production** slice (e.g. 1–5% of traffic), **smoke it and run canary analysis** (watch error rate / latency / saturation vs. the SLO, §9), then **widen or abort**. A failed canary never reaches most users.
- **Blue-green** — deploy to the idle **green** stack, **smoke green at zero live traffic**, then cut traffic over; keep **blue** warm for instant rollback.

## Smoke / validation gates — at every promotion boundary
Smoke is not just a post-deploy afterthought. Gate **each** boundary; a failed check **stops promotion / rolls back**, it does not just log:
1. **Lower environments (QA/UAT)** — smoke/acceptance before promoting toward prod (`DEVELOPMENT-PROCESS.md` "Environments & promotion").
2. **Canary slice / green stack — before widening or cutover** *(highest-value gate)* — smoke the slice while its blast radius is still 1–5% (canary) or zero live traffic (green). This is the validation that happens **before** the rollout reaches production at large.
3. **After full rollout** — a final smoke to confirm the fully-promoted release.

## Automated canary analysis
Define **abort thresholds** against the SLO / error budget (§9): error rate, p95/p99 latency, saturation (CPU/memory/connections). The analysis is the **automated "validate-before-widening" gate** — it widens on green, aborts and rolls back on breach. Follows the same **soft → gating** maturity progression as error budgets (§9): start by watching, promote to auto-abort at scale.

## Rollback
Per §10 preference order: **flag-off → redeploy previous → revert + redeploy**. In canary/blue-green, the lowest-blast-radius rollback is structural: **don't widen** (canary) or **don't cut over** (green) — the bad release never reaches full traffic. Every release declares its rollback path before it ships (§10).

## Tooling (Org-owned)
Argo Rollouts, Flagger, a service-mesh canary, or a **flag-driven** staged rollout (§10 feature flags) are platform choices. The kit standardizes the **practice** — slice → smoke → analyze → widen-or-abort — not the tool.
```

- [ ] **Step 2: Link check**

Run: `sh conformance/check-links.sh; echo "exit=$?"`
Expected: `exit=0`.

- [ ] **Step 3: Commit**

```bash
git add docs/operations/progressive-delivery.md
git commit -m "docs(operations): add progressive-delivery reference

Stack-neutral how-to: staged/canary/blue-green, smoke gates at every
promotion boundary (incl. the canary/green slice before widening),
automated canary analysis tied to SLOs (§9), rollback. Tooling Org-owned.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

## Important notes
- Create ONLY `docs/operations/progressive-delivery.md`. Preserve special chars (—, →, §). Do NOT run `inception-done.sh`.

## Report Format
Report: Status, exact output of Step 2, commit SHA, any concerns.

---

### Task 2: §14 `deploy-prod` smoke gate

**Files:**
- Modify: `DEVELOPMENT-STANDARDS.md` (§14 `deploy-prod` reference block)

- [ ] **Step 1: Replace the single deploy step with the deploy → smoke → rollback-on-fail pattern**

Find this EXACT block (the `steps:` of the `deploy-prod` reference):
```
  steps:
    - run: echo "promote the verified artifact to production"
```
Replace with:
```
  steps:
    - run: echo "promote the verified artifact to production (canary/blue-green — see docs/operations/progressive-delivery.md)"
    - name: smoke
      run: echo "run post-deploy smoke tests against the new release (and the canary slice before widening)"
    - name: rollback-on-smoke-failure
      if: failure()
      run: echo "smoke failed — roll back (flag-off / redeploy previous) per DEVELOPMENT-PROCESS.md §10"
```

- [ ] **Step 2: Verify**

Run:
```bash
grep -c "name: smoke" DEVELOPMENT-STANDARDS.md
grep -c "rollback-on-smoke-failure" DEVELOPMENT-STANDARDS.md
grep -c "if: failure()" DEVELOPMENT-STANDARDS.md
sh conformance/check-links.sh; echo "exit=$?"
```
Expected: first `1`; second `1`; third `1`; links `exit=0`.

> Note: this is an inert doc snippet inside `DEVELOPMENT-STANDARDS.md` (a `.md`), NOT a profile workflow — `ci-gates.sh` does not validate it, so no gate-id impact.

- [ ] **Step 3: Commit**

```bash
git add DEVELOPMENT-STANDARDS.md
git commit -m "feat(standards): add post-deploy smoke gate to §14 deploy-prod reference

deploy -> smoke -> rollback-on-fail (the if: failure() step makes it a
gate, not just a log). Stack-neutral, inert; adopters wire real commands.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

## Important notes
- ONLY `DEVELOPMENT-STANDARDS.md`. One block. Preserve YAML indentation (4-space `steps:` items, matching the existing block). Do NOT run `inception-done.sh`.

## Report Format
Report: Status, exact output of Step 2, commit SHA, any concerns.

---

### Task 3: Tighten the 8b checklist rows 5 + 6

**Files:**
- Modify: `conformance/definition-of-deployable.md` (blank rows 5 + 6; worked-example row 6)

- [ ] **Step 1: Tighten blank row 5 (progressive-delivery reference)**

Find this EXACT row:
```
| 5 | Progressive-delivery plan — canary / blue-green / staged (§10); N/A at Stage 1 with reason *(wired)* | | | Manual |
```
Replace with:
```
| 5 | Progressive-delivery plan — canary / blue-green / staged (§10; `docs/operations/progressive-delivery.md`); N/A at Stage 1 with reason *(wired)* | | | Manual |
```

- [ ] **Step 2: Tighten blank row 6 (smoke gate + multi-stage)**

Find this EXACT row:
```
| 6 | Smoke test **defined** and post-deploy result recorded *(tested)* | | | Manual |
```
Replace with:
```
| 6 | **Post-deploy smoke gate wired (deploy → smoke → rollback-on-fail), and smoke run at each promotion boundary** incl. the canary/green slice before widening (`docs/operations/progressive-delivery.md`); result recorded *(tested)* | | | Manual |
```

- [ ] **Step 3: Update worked-example row 6 evidence**

Find this EXACT row:
```
| 6 | Smoke defined + result *(tested)* | Y | post-deploy smoke job; run #1423 green | Manual ✅ |
```
Replace with:
```
| 6 | Smoke gate + multi-stage *(tested)* | Y | smoke gate in `deploy-prod` (rollback-on-fail); canary smoked before widening; run #1423 green | Manual ✅ |
```

- [ ] **Step 4: Verify**

Run:
```bash
grep -c "rollback-on-fail" conformance/definition-of-deployable.md
grep -c "docs/operations/progressive-delivery.md" conformance/definition-of-deployable.md
sh conformance/check-links.sh; echo "exit=$?"
sh conformance/deployable-ready.sh --selftest >/dev/null 2>&1; echo "deployable-selftest=$?"
```
Expected: first `1`; second `2` (rows 5 + 6); links `exit=0`; `deployable-selftest=0` (the script is unchanged — only checklist prose changed).

- [ ] **Step 5: Commit**

```bash
git add conformance/definition-of-deployable.md
git commit -m "feat(conformance): tighten deployable smoke row to the gate + multi-stage

Row 6 now requires the post-deploy smoke GATE (deploy -> smoke ->
rollback-on-fail) and smoke at each promotion boundary (canary/green
before widening); rows 5/6 reference docs/operations/progressive-delivery.md.
Rows stay Manual (behavioural). No script change.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

## Important notes
- ONLY `conformance/definition-of-deployable.md`. Three rows. Preserve special chars (→, ✅, §). The Auto/Manual column is UNCHANGED (rows 5/6 stay Manual). Do NOT run `inception-done.sh`.

## Report Format
Report: Status, exact output of Step 4, commit SHA, any concerns.

---

### Task 4: Wire §10 + DoD + README references

**Files:**
- Modify: `DEVELOPMENT-PROCESS.md` (§10 progressive-delivery line)
- Modify: `CLAUDE.md` (DoD Production line)
- Modify: `conformance/README.md` (pairing note)

- [ ] **Step 1: Reference the doc from §10**

Find this EXACT line:
```
- **Default:** staged rollout (staging → small % → full). **Maturity step:** automated canary analysis. Same soft→gating progression as error budgets.
```
Replace with:
```
- **Default:** staged rollout (staging → small % → full). **Maturity step:** automated canary analysis. Same soft→gating progression as error budgets. **Reference: `docs/operations/progressive-delivery.md`** (strategies, multi-stage smoke gates, canary analysis).
```

- [ ] **Step 2: Reference the gate pattern from the DoD**

Find this EXACT line:
```
**Production** — deployed · smoke-tested · no errors in logs · rollback path ready · monitoring/alerting on critical paths · **DR proven for data services** (`conformance/dr-readiness.md`).
```
Replace with:
```
**Production** — deployed · smoke-tested (post-deploy gate; `docs/operations/progressive-delivery.md`) · no errors in logs · rollback path ready · monitoring/alerting on critical paths · **DR proven for data services** (`conformance/dr-readiness.md`).
```

- [ ] **Step 3: Add the pairing note to conformance/README.md**

Find this EXACT line (the last `>` note in the file):
```
> **Note on `inception-done.sh` at the kit root:** this gate is *expected to FAIL* when run against the kit's own repository — the kit is the reference/template **source**, not an instantiated project (it has no `ADR-000`, `RUNBOOK.md`, etc.). It passes only inside a project that has completed Inception. Do not "fix" the kit root to satisfy it.
```
Insert this note DIRECTLY AFTER it (a blank line, then):
```
> **Progressive delivery (reference, no separate check):** `definition-of-deployable.md`'s progressive-delivery + smoke-gate rows pair with [`../docs/operations/progressive-delivery.md`](../docs/operations/progressive-delivery.md) for the *how* (canary/blue-green + smoke gates at every promotion boundary). The checklist is the conformance; the reference completes the triad.
```

- [ ] **Step 4: Verify**

Run:
```bash
grep -c "Reference: \`docs/operations/progressive-delivery.md\`" DEVELOPMENT-PROCESS.md
grep -c "post-deploy gate; \`docs/operations/progressive-delivery.md\`" CLAUDE.md
grep -c "Progressive delivery (reference, no separate check)" conformance/README.md
sh conformance/check-links.sh; echo "exit=$?"
```
Expected: first `1`; second `1`; third `1`; links `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add DEVELOPMENT-PROCESS.md CLAUDE.md conformance/README.md
git commit -m "docs: reference progressive-delivery from §10, DoD, conformance README

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

## Important notes
- THREE files, one edit each. Preserve special chars (→, ·, §). The README note uses a real Markdown link `[...](../docs/operations/progressive-delivery.md)` — `check-links.sh` validates it, so the path must be correct (relative to `conformance/`). Do NOT run `inception-done.sh`.

## Report Format
Report: Status, exact output of Step 4, commit SHA, any concerns.

---

### Task 5: Version bump, CHANGELOG, ROADMAP

**Files:**
- Modify: `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-KIT.md`

- [ ] **Step 1: Bump VERSION**

Replace the contents of `VERSION` (`2.22.0`) with:
```
2.23.0
```

- [ ] **Step 2: Add the CHANGELOG entry**

Insert this entry IMMEDIATELY ABOVE the `## [2.22.0] - 2026-06-09` line:
```markdown
## [2.23.0] - 2026-06-09

Slice 8e — Progressive-delivery reference + smoke gates. Fifth sub-slice of Slice 8 (continuity & safe-delivery hardening). Closes gaps B2 (progressive delivery had no reference) + B3 (post-deploy smoke verification was thin). The reference leg of a triad whose contract (§10) and conformance (8b Definition of Deployable) already shipped.

### Added
- **`docs/operations/progressive-delivery.md`** — a stack-neutral reference: staged / canary / blue-green strategies; **smoke gates at every promotion boundary** (lower-env → the canary/green slice *before* widening → post-full-rollout); automated canary analysis tied to SLOs / error budget (§9); rollback. Tooling (Argo Rollouts / Flagger / flag-driven) named Org-owned.
- **`DEVELOPMENT-STANDARDS.md` §14** — the `deploy-prod` reference now shows **deploy → smoke → rollback-on-fail** (the `if: failure()` step makes it a gate, not a log).

### Changed
- **`conformance/definition-of-deployable.md`** — the smoke row is tightened from "smoke defined + result recorded" to "**post-deploy smoke gate wired (deploy → smoke → rollback-on-fail), and smoke run at each promotion boundary** incl. the canary/green slice before widening"; rows 5/6 reference the new doc. Rows stay Manual (behavioural). No script change.
- **`DEVELOPMENT-PROCESS.md` §10**, **`CLAUDE.md` DoD**, **`conformance/README.md`** reference the new doc.

### Note
MINOR (2.23.0): additive — a reference + a tightened checklist row. **No new conformance script**: a post-deploy smoke *gate* is a pipeline behaviour (step ordering + failure semantics) that a cross-stack YAML grep can't reliably detect, so it stays a Manual checklist row with a reference (honest enforcement, not theatre). No new CI gate-id; §14's gate set unchanged.
```

- [ ] **Step 3: Add the ROADMAP row**

In `docs/ROADMAP-KIT.md`, insert this row IMMEDIATELY AFTER the `8d ✅` row:
```
| 8e ✅ | **Progressive-delivery + smoke gates** *(shipped v2.23.0)* | process §10 + standards §14 + 8b checklist | `progressive-delivery.md` + §14 smoke-gate + tightened deployable smoke row | `check-links.sh` + the (tightened) Definition-of-Deployable checklist |
```

- [ ] **Step 4: Verify**

Run:
```bash
cat VERSION
grep -c "## \[2.23.0\]" CHANGELOG.md
grep -c "8e ✅" docs/ROADMAP-KIT.md
sh conformance/check-links.sh; echo "exit=$?"
```
Expected: `2.23.0`; `1`; `1`; links `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add VERSION CHANGELOG.md docs/ROADMAP-KIT.md
git commit -m "chore(release): 2.23.0 — progressive-delivery reference + smoke gates (8e)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

## Important notes
- ONLY those three files. Insert-only for CHANGELOG/ROADMAP. Preserve special chars (—, →, ·, §, ✅). Do NOT run `inception-done.sh`.

## Report Format
Report: Status, exact output of Step 4, commit SHA, any concerns.

---

### Task 6: Full conformance sweep + push + PR (stop for ratification)

**Files:** none (verification + push only)

- [ ] **Step 1: Run every conformance check**

Run:
```bash
sh conformance/check-links.sh; echo "links=$?"
for p in profiles/*/ci.yml; do sh conformance/ci-gates.sh "$p" >/dev/null 2>&1 || echo "FAIL $p"; done; echo "ci-gates done"
sh conformance/profile-completeness.sh >/dev/null 2>&1; echo "profiles=$?"
sh conformance/agent-autonomy.sh >/dev/null 2>&1; echo "autonomy=$?"
sh conformance/container-supply-chain.sh >/dev/null 2>&1; echo "containers=$?"
sh conformance/backlog-adapters.sh >/dev/null 2>&1; echo "backlog=$?"
sh conformance/guard-wired.sh >/dev/null 2>&1; echo "guard=$?"
sh conformance/deployable-ready.sh --selftest >/dev/null 2>&1; echo "deployable-selftest=$?"
sh conformance/dr-ready.sh --selftest >/dev/null 2>&1; echo "dr-selftest=$?"
sh conformance/resilience-ready.sh --selftest >/dev/null 2>&1; echo "resilience-selftest=$?"
```
Expected: `links=0`, no `FAIL` from ci-gates, all the rest `=0`.

- [ ] **Step 2: Final spec-coverage greps**

Run:
```bash
ls docs/operations/progressive-delivery.md
grep -c "name: smoke" DEVELOPMENT-STANDARDS.md                                # 1
grep -c "rollback-on-fail" conformance/definition-of-deployable.md           # 1
grep -c "smoke gates at every promotion boundary\|every promotion boundary" docs/operations/progressive-delivery.md  # >=1
cat VERSION                                                                   # 2.23.0
```

- [ ] **Step 3: Confirm clean tree + push**

```bash
git status --short    # only the pre-existing untracked .firecrawl/
git push -u origin feature/slice-8e-progressive-delivery
```

- [ ] **Step 4: Open the PR (do NOT merge — human ratification gate)**

```bash
gh pr create --title "Slice 8e — Progressive-delivery reference + smoke gates (v2.23.0)" \
  --body "$(cat <<'EOF'
Closes gaps B2 + B3 (Slice 8 arc). Ships the reference leg of progressive delivery — the contract (§10) and conformance (8b Definition of Deployable) already existed.

## What
- **`docs/operations/progressive-delivery.md`** — staged / canary / blue-green; **smoke gates at every promotion boundary** (lower-env → canary/green *before* widening → post-rollout); automated canary analysis tied to SLOs (§9); rollback. Tooling Org-owned.
- **§14 `deploy-prod` reference** — deploy → smoke → rollback-on-fail (the `if: failure()` step makes it a gate).
- **Tightened 8b smoke row** — from "smoke defined + recorded" to "post-deploy smoke gate wired (deploy → smoke → rollback-on-fail), and smoke run at each promotion boundary incl. the canary/green slice before widening". Rows stay Manual; references the new doc.
- **§10 / DoD / conformance README** reference the doc.

## Why reference-only (no new script)
A post-deploy smoke *gate* is a pipeline behaviour (step ordering + failure semantics) that a cross-stack YAML grep can't reliably detect — a flaky gate is worse than an honest checklist row. 8b already gates 'progressive-delivery plan' + 'smoke referenced'; 8e ships the missing reference and sharpens the smoke row to require the *gate*. Multi-stage framing (validate the canary BEFORE full exposure) is the heart of the slice.

## Verification
All conformance green; `deployable-ready.sh --selftest` unchanged-green; **MINOR -> 2.23.0** (no new CI gate-id; §14 gate set unchanged).

## Governance
Governing-doc surface (PROCESS §10, STANDARDS §14, DoD) -> **security-owner lens**. Agent does not self-merge — this PR stops for human ratification.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: STOP for human ratification**

Do not merge. Report the PR URL + green conformance to Bradley (governing-doc change → security-owner lens per §13/RBAC).

---

## Self-Review

**1. Spec coverage:**
- Deliverable A (progressive-delivery reference) → Task 1. ✅
- Deliverable B (§14 smoke gate) → Task 2. ✅
- Deliverable C (tighten 8b rows 5/6 blank + worked) → Task 3. ✅
- Deliverable D (§10 reference) → Task 4 Step 1. ✅
- Deliverable E (DoD reference) → Task 4 Step 2. ✅
- Deliverable F (README note) → Task 4 Step 3. ✅
- Meta → Task 5. ✅
- Multi-stage smoke framing (§2/§5 of spec) → Task 1 (the doc's "every promotion boundary" section) + Task 3 (row 6 "each promotion boundary … canary/green before widening"). ✅
- No new script (spec §3) → no task creates one; Task 3 Step 4 asserts `deployable-selftest=0` unchanged. ✅

**2. Placeholder scan:** No "TBD/implement later". The `echo "..."` lines in the §14 snippet are intentional inert reference commands (house style: "adopters wire it"). The doc and all edits are given in full. ✅

**3. Consistency:** `docs/operations/progressive-delivery.md` path is identical across Task 1 (create), Task 2 (§14 prose), Task 3 (rows 5/6), Task 4 (§10/DoD/README), CHANGELOG, ROADMAP. The "rollback-on-fail" string in the tightened row 6 (Task 3 Step 2) matches the Task 3 Step 4 grep and the Task 6 Step 2 grep. The §14 `name: smoke` / `rollback-on-smoke-failure` / `if: failure()` strings in Task 2 Step 1 match the Task 2 Step 2 greps. The README note uses a real Markdown link (validated by `check-links.sh`); the §10/DoD references are backtick paths (not link-checked) — both consistent with how the kit references docs. ✅
