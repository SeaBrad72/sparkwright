# Code Quality (lean) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lock the kit's own shell code with a shellcheck regression-check, and ship a code-quality **review lens** + per-stack complexity/duplication **recommendations** (not new gates) so adopters inherit enforceable-where-honest, reviewable quality.

**Architecture:** Part A — `conformance/shellcheck.sh` (conditional on shellcheck being installed; error/warning floor; `--selftest`). Part B — a `docs/operations/code-quality.md` reference + a `CODE-REVIEW-CHECKLIST.md` template + a `+0` fold of the code-quality lens into the §7 Review-gate row + a per-stack tooling line in all 10 profiles. **No new conditional gates** (complexity/duplication are demoted to `gate-lint` config recs). **No `*-ready.sh` for the lens** (review discipline isn't script-verifiable — honest classification).

**Tech Stack:** `sh` (dash-clean), Markdown, `shellcheck`. Spec: `docs/superpowers/specs/2026-06-12-code-quality-lean-design.md`. Branch: `feature/code-quality`. **Doc-budget:** core-3 at 900/900 — the §7 fold MUST be `+0`; **never change `TOTAL_BUDGET`** (the SP-2 lesson).

---

## Conventions
- `#!/bin/sh`, `set -eu`, dash-clean. CI step names colon-free (the #80 lesson).
- `--selftest` fixtures via mktemp, left in place (7e guard).
- Commit per task. Run `doc-budget.sh` after the §7 edit (must read 900/900).

---

## File Structure
- **Create** `conformance/shellcheck.sh` — lint the kit's shell code + `--selftest`.
- **Create** `docs/operations/code-quality.md` — review lens + per-stack complexity/duplication recs + consistency + reference reviewers.
- **Create** `templates/CODE-REVIEW-CHECKLIST.md` — the review-lens checklist.
- **Modify** `DEVELOPMENT-PROCESS.md` §7 Review row (line ~109) — `+0` fold naming the code-quality lens.
- **Modify** all 10 `profiles/<stack>.md` + `profiles/_TEMPLATE.md` — fold a complexity/duplication rec into the §1 Format/lint line.
- **Modify** `conformance/verify.sh` + `conformance/README.md` — `shellcheck` control row + registry row.
- **Hand-apply (control-plane, Bradley):** kit-CI install-shellcheck + run step.

---

## Task 1: `conformance/shellcheck.sh` + `--selftest` (TDD core)

**Files:** Create `conformance/shellcheck.sh`

- [ ] **Step 1: Write the check**

```sh
#!/bin/sh
# shellcheck.sh — lint the kit's OWN shell code (a regression-lock; the kit dogfoods quality).
# Floor: error + warning (POSIX -s sh). The kit's scripts are currently shellcheck-clean —
# this keeps them that way (dash -n only checks syntax, not lint). CONDITIONAL on shellcheck
# being installed: SKIP-pass if absent (a dev may not have it) — the kit CI installs it and
# runs it for real, so drift is caught in CI regardless.
#   sh conformance/shellcheck.sh [--selftest]
# Exit: 0 = clean or SKIP · 1 = a finding · 2 = bad usage. POSIX sh; dash-clean.
set -eu

# collect existing kit shell files into the positional params
collect() {
  set --
  for f in scripts/*.sh conformance/*.sh; do [ -f "$f" ] && set -- "$@" "$f"; done
  [ -f scripts/kit-guard ] && set -- "$@" scripts/kit-guard
  [ -f hooks/pre-push ]    && set -- "$@" hooks/pre-push
  printf '%s\n' "$@"
}

run() {
  command -v shellcheck >/dev/null 2>&1 || { echo "SKIP: shellcheck not installed (kit CI runs it for real)"; return 0; }
  # shellcheck disable=SC2046  # word-splitting the file list is intended here
  set -- $(collect)
  [ "$#" -gt 0 ] || { echo "shellcheck: no kit shell files found"; return 1; }
  if shellcheck -s sh -S warning "$@"; then
    echo "shellcheck: OK ($# kit shell file(s) clean at the error/warning floor)"
    return 0
  fi
  echo "shellcheck: FAIL (findings above) — fix or justify with a '# shellcheck disable=SCnnnn' + reason"
  return 1
}

selftest() {
  command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck --selftest: SKIP (shellcheck not installed)"; return 0; }
  d=$(mktemp -d)
  printf '#!/bin/sh\nx="hello"\nprintf "%%s\\n" "$x"\n' > "$d/clean.sh"
  printf '#!/bin/sh\nx=$1\necho $x\n' > "$d/dirty.sh"   # SC2086 (unquoted) + SC2034-ish
  shellcheck -s sh -S warning "$d/clean.sh" >/dev/null 2>&1 || { echo "selftest FAIL: clean fixture flagged"; return 1; }
  if shellcheck -s sh -S warning "$d/dirty.sh" >/dev/null 2>&1; then
    echo "selftest FAIL: dirty fixture not flagged"; return 1
  fi
  echo "shellcheck --selftest: OK (clean passes, dirty fails; fixtures left in $d)"
  return 0
}

case "${1:-}" in
  --selftest) selftest ;;
  "")         run ;;
  *)          echo "usage: shellcheck.sh [--selftest]" >&2; exit 2 ;;
esac
exit $?
```

- [ ] **Step 2: Run it against the kit (must be clean) + selftest**

Run: `sh conformance/shellcheck.sh; echo "exit=$?"` and `sh conformance/shellcheck.sh --selftest`
Expected: `shellcheck: OK (NN kit shell file(s) clean …)` exit 0; selftest `OK (clean passes, dirty fails)`. (If shellcheck isn't installed locally: `brew install shellcheck` / `apt-get install shellcheck` first, or expect the SKIP path.)

- [ ] **Step 3: dash-clean + that the script lints ITSELF clean**

Run: `dash -n conformance/shellcheck.sh && echo dash-clean && shellcheck -s sh -S warning conformance/shellcheck.sh && echo self-clean`
Expected: `dash-clean` then `self-clean` (the new script must itself pass — note the intentional `# shellcheck disable=SC2046` on the word-split line).

- [ ] **Step 4: Commit**

```bash
git add conformance/shellcheck.sh
git commit -m "feat(conformance): shellcheck.sh — lint the kit's own shell code (regression-lock)"
```

---

## Task 2: `docs/operations/code-quality.md` (the bulk)

**Files:** Create `docs/operations/code-quality.md`

- [ ] **Step 1: Create the file**

```markdown
# Code Quality — Review Lens, Complexity & Consistency

The kit already enforces a lot of quality mechanically: `gate-lint` (per-stack formatter + linter),
`gate-type-check`, `coverage-ratchet` (no-regression coverage), the pre-commit inner loop
(`dev-inner-loop.md`), and **test-quality** (mutation/property — `test-quality.md`). This file adds
the two things a metric can't fully cover: a **review lens** (judgment) and a **consistency** through-line,
plus how to switch on complexity/duplication via the lint gate you already have.

## The code-quality review lens (§7 Review gate)

At the Review gate, a reviewer (human or agent) checks dimensions a gate can't honestly score —
use `templates/CODE-REVIEW-CHECKLIST.md`:

- **Readability** — a new reader follows it without the author.
- **Simplicity (DRY / YAGNI)** — no needless abstraction; no copy-paste that should be one thing.
- **Function size & single-purpose** — small, one job; prefer early returns over deep nesting.
- **Naming** — meaningful; intention-revealing; no throwaway names (except loop counters).
- **Comment quality** — comments explain *why* / intent, not narrate the code; no comment-rot.
- **Type / interface design** — strong invariants, encapsulation; the type makes illegal states unrepresentable.
- **Cohesion / coupling** — a unit does one thing; changing internals doesn't ripple.
- **No dead code, no debug output, no hardcoded values** that belong in config.

These are **review discipline, not a fail-closed gate** — quality genuinely needs judgment, and gating it
would invite gaming. Reference reviewers (tool-neutral): `code-reviewer`, `code-simplifier`,
`comment-analyzer`, `type-design-analyzer` agent patterns can apply the lens.

## Complexity & duplication — configure the lint gate you already have

These ARE measurable, but they're **recommended `gate-lint` configuration**, not new gates (the existing
`gate-lint` enforces them when switched on; gating them separately invites the gaming/noise that keeps
test-quality recommended-not-gated). Turn them on per stack with sane starting ceilings:

| Stack | Complexity | Duplication |
|-------|-----------|-------------|
| typescript-node | ESLint `complexity` (≤10) / `sonarjs/cognitive-complexity` | `jscpd` |
| python · ml · data-engineering | `ruff` `C901` (mccabe) / `radon cc` | `jscpd` / `pylint` similarities |
| go | `gocyclo` / `gocognit` (via golangci-lint) | `dupl` (golangci-lint) |
| rust | `clippy::cognitive_complexity` | `jscpd` |
| java-spring · kotlin | `detekt` ComplexMethod / Checkstyle CyclomaticComplexity | `detekt` / CPD (PMD) |
| dotnet | Roslyn analyzers / SonarAnalyzer | `jscpd` |
| terraform | tflint / Checkov (policy is the bar) | `jscpd` (HCL) |

Start at a ceiling, ratchet down — a high number flags "refactor me," not "fail the build" (tune per project).

## Consistency (the through-line)

Cross-codebase consistency comes from three things together: **formatters** (already mandated — one style,
zero debate), **uniform complexity ceilings** (the same "too complex" everywhere), and the **same review
lens** applied at every PR. Consistency is a quality property, not a separate gate — it falls out of these.

## Honesty

A green lint/complexity run proves thresholds were met, not that the code is good; the review lens proves a
reviewer *looked*, not that they were right. Necessary, not sufficient — quality is earned at review, not asserted.
```

- [ ] **Step 2: Links + commit**

Run: `sh conformance/check-links.sh 2>&1 | tail -1`
```bash
git add docs/operations/code-quality.md
git commit -m "docs(operations): code-quality — review lens + complexity/duplication recs + consistency"
```

---

## Task 3: `templates/CODE-REVIEW-CHECKLIST.md`

**Files:** Create `templates/CODE-REVIEW-CHECKLIST.md`

- [ ] **Step 1: Create the template**

```markdown
# Code Review Checklist (Quality Lens)

> Apply at the §7 Review gate, alongside the correctness + security review. A reviewer (human or agent)
> marks each dimension. This is judgment, not a gate — flag concerns, don't rubber-stamp.

- [ ] **Readability** — a new reader follows it without the author present.
- [ ] **Simplicity (DRY / YAGNI)** — no needless abstraction; no copy-paste that should be one unit.
- [ ] **Function size & single-purpose** — small; one job; early returns over deep nesting.
- [ ] **Naming** — meaningful, intention-revealing (no throwaway names except loop counters).
- [ ] **Comment quality** — explains *why* / intent, not narration; no stale/rotted comments.
- [ ] **Type / interface design** — strong invariants + encapsulation; illegal states hard to represent.
- [ ] **Cohesion / coupling** — one responsibility; internal changes don't ripple to consumers.
- [ ] **Error handling** — structured, with codes; no swallowed errors / silent fallbacks.
- [ ] **No dead code · no debug output · no hardcoded values** that belong in config.
- [ ] **Tests** — meaningful (assert behavior, not implementation); critical paths covered.

**Reviewer:** [name/role] · **Verdict:** [approve / changes requested] · see `docs/operations/code-quality.md`.
```

- [ ] **Step 2: Links + commit**

Run: `sh conformance/check-links.sh 2>&1 | tail -1`
```bash
git add templates/CODE-REVIEW-CHECKLIST.md
git commit -m "feat(templates): CODE-REVIEW-CHECKLIST — the quality review lens"
```

---

## Task 4: §7 `+0` fold + per-stack lines (budget-critical)

**Files:** Modify `DEVELOPMENT-PROCESS.md`, all 10 `profiles/<stack>.md`, `profiles/_TEMPLATE.md`

- [ ] **Step 1: `+0` fold the lens into the §7 Review row (line ~109)**

In `DEVELOPMENT-PROCESS.md`, replace the existing Review row:
```markdown
| **Review** | "Did we build it *right*?" — code + adversarial/multi-lens + **security lens**, routed per ownership. | Merge gate (human) |
```
with (same one line, naming the quality lens — `+0`):
```markdown
| **Review** | "Did we build it *right*?" — code + adversarial/multi-lens + **security lens** + **code-quality lens** (`templates/CODE-REVIEW-CHECKLIST.md`), routed per ownership. | Merge gate (human) |
```

- [ ] **Step 2: Verify the budget held at 900**

Run: `sh conformance/doc-budget.sh`
Expected: `PASS: DEVELOPMENT-PROCESS.md 470/470` and `PASS: core-3 total 900/900` — **unchanged** (a `+0` text fold, no new line). **If core-3 shows 901, you added a line — recheck Step 1 replaced one line with one line.** Do NOT change `TOTAL_BUDGET`.

- [ ] **Step 3: Per-stack complexity/duplication line in all 10 profiles + `_TEMPLATE`**

In each `profiles/<stack>.md`, fold a clause onto the existing §1 **Format/lint** line (profiles are not budget-capped; appending is fine), e.g. for typescript-node:
```markdown
- **Format/lint/types:** Prettier · ESLint (`@typescript-eslint`) · `tsc --noEmit` · **Complexity/duplication** (recommended `gate-lint` config): ESLint `complexity` + `jscpd` (`docs/operations/code-quality.md`).
```
Use each stack's tools from the `code-quality.md` table (ruff C901/radon + jscpd for python·ml·data-eng; gocyclo + dupl for go; clippy cognitive-complexity for rust; detekt for java·kotlin; Roslyn/Sonar for dotnet; tflint/jscpd for terraform). For `_TEMPLATE.md`, use a generic placeholder line pointing at `code-quality.md`.

- [ ] **Step 4: Verify completeness + links**

Run: `sh conformance/profile-completeness.sh 2>&1 | tail -1 && sh conformance/check-links.sh 2>&1 | tail -1`
Expected: profiles complete; links OK.

- [ ] **Step 5: Commit**

```bash
git add DEVELOPMENT-PROCESS.md profiles/
git commit -m "feat: §7 code-quality lens (+0) + per-stack complexity/duplication recs (all profiles)"
```

---

## Task 5: Wire `shellcheck` into verify.sh + registry row

**Files:** Modify `conformance/verify.sh`, `conformance/README.md`

- [ ] **Step 1: verify.sh control-check row** — after the `check control image-supply …` row (or near the other controls):
```sh
check control shellcheck       sh conformance/shellcheck.sh
```

- [ ] **Step 2: Run the aggregate**

Run: `sh conformance/verify.sh 2>&1 | grep -E "shellcheck|RESULT"`
Expected: `[control] shellcheck PASS` (clean, or SKIP-pass if shellcheck absent) and `RESULT: OK`.

- [ ] **Step 3: Registry row** in `conformance/README.md` (mirror an existing control-check row): `shellcheck.sh` — lints the kit's own shell code (error/warning floor; conditional on shellcheck installed; CI installs it). Commit:
```bash
git add conformance/verify.sh conformance/README.md
git commit -m "feat(conformance): wire shellcheck into verify.sh + registry row"
```

---

## Task 6: Prepare the control-plane CI step (hand-apply for Bradley)

**Files:** Hand-apply (Bradley): `.github/workflows/ci.yml`

- [ ] **Step 1: Produce the step** (colon-free name; installs shellcheck so it runs for real, since the kit's checks otherwise SKIP it). For the `conformance:` job:
```yaml
      - name: Install shellcheck
        run: sudo apt-get update && sudo apt-get install -y shellcheck
      - name: Shellcheck the kit's own shell code
        run: sh conformance/shellcheck.sh
```
- [ ] **Step 2: Surface it in the PR body** (clean block, no `#` comments) with the `KIT_GUARD_SELFEDIT=1 git add … ; git commit` apply commands + a note to `gh run watch` for green. *(No repo change in this task.)*

---

## Task 7: Final verification + independent review + PR

- [ ] **Step 1: Full sweep**
```bash
sh conformance/shellcheck.sh
sh conformance/shellcheck.sh --selftest
dash -n conformance/shellcheck.sh && echo dash-clean
shellcheck -s sh -S warning conformance/shellcheck.sh && echo self-clean
sh conformance/check-links.sh
sh conformance/doc-budget.sh
sh conformance/verify.sh | tail -3
```
Expected: shellcheck OK; selftest OK; dash-clean; self-clean; links OK; **doc-budget core-3 900/900**; `verify.sh` RESULT: OK.

- [ ] **Step 2: Independent review (code-quality + security-owner lens).** Focus: (a) `shellcheck.sh` is itself shellcheck-clean and the `# shellcheck disable=SC2046` is justified (not masking a real issue); (b) SKIP-when-absent is honest (CI installs it — confirm the CI step does); (c) the `+0` §7 fold genuinely held core-3 at 900 and `TOTAL_BUDGET` is untouched at 900; (d) honesty wording (lint-floor ≠ bug-free; lens is discipline not a gate); (e) the demote framing is accurate (complexity/duplication are `gate-lint` config recs, not claimed as gates); (f) per-stack tooling reached all 10 profiles + `_TEMPLATE`.

- [ ] **Step 3: Address findings, then PR**
```bash
git push -u origin feature/code-quality
gh pr create --title "feat(quality): code-quality lens + shellcheck regression-lock (lean)" --body "<summary + the right-sized framing (no new gates, kit already shellcheck-clean) + +0 fold + Task-6 control-plane snippet + 2.58.0 note + merge command>"
```
Report the PR number + `gh pr merge <n> --squash --admin --delete-branch`. **Do not self-merge.**

---

## Self-review (plan author)
- **Spec coverage:** Part A shellcheck → Tasks 1/5/6. Part B review lens → Tasks 2/3 + §7 fold (Task 4). Complexity/duplication demoted-to-recs → Task 2 table + Task 4 per-stack lines. Consistency theme → Task 2. No new `*-ready.sh` (lens = discipline) → respected. Honesty → Tasks 1/2/3. **No gaps.**
- **Placeholder scan:** the checklist's `[name/role]`/`[verdict]` are intentional template fill-ins; no banned patterns.
- **Consistency:** the script name `shellcheck.sh`, the error/warning floor, the `+0` §7 fold, and "no new gate / no TOTAL_BUDGET change" are consistent across Tasks 1/4/5/7.
