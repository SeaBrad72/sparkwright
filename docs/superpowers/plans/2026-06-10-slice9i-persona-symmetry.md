# Persona Symmetry (Slice 9i) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the QA and Designer personas the dedicated, auditable artifacts the persona table already promises (R9): a test-plan template, two per-gate sign-off records, an honest dedicated-vs-shared annotation, and the DoD/§9 tie-ins that name those records as evidence.

**Architecture:** Three new `templates/` files, annotations to `DEVELOPMENT-PROCESS.md` §2/§9/§5 and the `CLAUDE.md` DoD, a completeness drift-guard (`conformance/persona-artifacts.sh`), and CI wiring. Additive → MINOR v2.33.0.

**Tech Stack:** Markdown + POSIX `sh`. Verified by `persona-artifacts.sh --selftest`, `dash -n`, `check-links.sh`, and a diff-review of the governing-file edits.

---

## Execution notes
- **One control-plane `cp`:** Task 6 (`.github/workflows/ci.yml`). Everything else agent-editable (`conformance/persona-artifacts.sh` is in `conformance/`, not control-plane; `CLAUDE.md`/`DEVELOPMENT-PROCESS.md` are governing docs but not guard-protected — they're edited as proposals, ratified by your merge).
- **`CLAUDE.md` is the authoritative principles file** — its DoD edit is minimal (names an evidence artifact on the existing Accessibility line; adds no requirement) and gets the security-owner lens at review.
- **Anonymization** ([[kit-anonymization]]): generic throughout.
- **Branch:** `feature/slice-9i-persona-symmetry` (holds the spec already).

## File structure

| File | Responsibility |
|------|----------------|
| `templates/TEST-PLAN-TEMPLATE.md` (new) | QA's test plan: scope, levels, cases↔acceptance-criteria, environments, entry/exit |
| `templates/UAT-SIGNOFF-TEMPLATE.md` (new) | Auditable UAT acceptance record (gate/signer/role/date/verdict/evidence/decision) |
| `templates/A11Y-SIGNOFF-TEMPLATE.md` (new) | Auditable a11y sign-off (WCAG 2.1 AA checklist + axe/Lighthouse evidence) |
| `DEVELOPMENT-PROCESS.md` (modify) | §2 persona-table annotation; §9 UAT gate → UAT-SIGNOFF; §5 Designer lens → A11Y-SIGNOFF |
| `CLAUDE.md` (modify) | DoD Accessibility line → names A11Y-SIGNOFF as evidence |
| `conformance/persona-artifacts.sh` (new) | Completeness drift-guard + `--selftest` |
| `conformance/README.md` (modify) | index row |
| `START-HERE.md` (modify) | QA/Designer role rows link their templates |
| `.github/workflows/ci.yml` (modify, **human cp**) | `persona-artifacts.sh` step |
| `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md` (modify) | 2.33.0; 9i row → shipped; add 9i-b (DoR) fast-follow row |

---

## Task 1: The three templates

**Files:** Create `templates/TEST-PLAN-TEMPLATE.md`, `templates/UAT-SIGNOFF-TEMPLATE.md`, `templates/A11Y-SIGNOFF-TEMPLATE.md`

- [ ] **Step 1: `TEST-PLAN-TEMPLATE.md`.** Match the kit's `_TEMPLATE` guidance-blockquote voice (read `templates/SPEC-TEMPLATE.md` for tone). Sections:
  - Title + a `>` guidance blockquote ("Delete the guidance; fill each section. QA owns this artifact — the test lens of the Reviewer function, DEVELOPMENT-PROCESS §2/§12.").
  - **Feature / story** (link to FEATURE-REQUEST + spec) · **Scope & risk areas** · **Test levels** (unit / integration / e2e — what each covers here) · **Cases → acceptance criteria** (a small table mapping each test case to the acceptance criterion it verifies — the traceability tying QA to the PO's `FEATURE-REQUEST`) · **Environments** (Dev/QA per §9) · **Entry / exit criteria** · **Out of scope**.

- [ ] **Step 2: `UAT-SIGNOFF-TEMPLATE.md`.** A short structured record (not prose). Guidance blockquote + a fields table:
  ```markdown
  | Field | Value |
  |-------|-------|
  | Gate | UAT |
  | Feature / story | <link> |
  | Acceptance criteria verdict | met / not met (list any gaps) |
  | Test-plan reference | <link to the filled TEST-PLAN> |
  | Evidence | <links: test run, demo, screenshots> |
  | Decision | **accept** / reject |
  | Signer (role) | <name> (QA / PO) |
  | Date | YYYY-MM-DD |
  | Notes | |
  ```
  Guidance: "The auditable record for the §9 Dev→QA→**UAT** promotion gate ('UAT green + acceptance sign-off'). Attach to the PR or store under `docs/sign-offs/`."

- [ ] **Step 3: `A11Y-SIGNOFF-TEMPLATE.md`.** Same record shape, a11y-specific:
  ```markdown
  | Field | Value |
  |-------|-------|
  | Gate | Accessibility (WCAG 2.1 AA) |
  | Feature / story | <link> |
  | Keyboard-navigable | pass / fail |
  | Screen-reader | pass / fail |
  | Contrast ≥ 4.5:1 (3:1 large) | pass / fail |
  | Visible focus indicator | pass / fail |
  | prefers-reduced-motion respected | pass / fail / N/A |
  | Tool evidence | axe / Lighthouse run link + score |
  | Decision | **pass** / fail |
  | Signer (role) | <name> (Designer / a11y owner) |
  | Date | YYYY-MM-DD |
  | Notes | |
  ```
  Guidance: "The auditable evidence for the Definition-of-Done **Accessibility** item. Designer (or the a11y owner) signs at Review."

- [ ] **Step 4: Verify + commit.**
  Run: `git add templates/TEST-PLAN-TEMPLATE.md templates/UAT-SIGNOFF-TEMPLATE.md templates/A11Y-SIGNOFF-TEMPLATE.md && sh conformance/check-links.sh 2>&1 | tail -1` → links resolve.
  Run: `grep -niE "enterprise|public.media|bradley" templates/TEST-PLAN-TEMPLATE.md templates/UAT-SIGNOFF-TEMPLATE.md templates/A11Y-SIGNOFF-TEMPLATE.md || echo clean` → `clean`.
  ```bash
  git commit -m "docs(9i): TEST-PLAN + UAT-SIGNOFF + A11Y-SIGNOFF templates (QA/Designer dedicated artifacts)"
  ```

---

## Task 2: Persona-table annotation + §9/§5 refs

**Files:** Modify `DEVELOPMENT-PROCESS.md`

- [ ] **Step 1: Annotate the §2 persona table.** Read the table (the rows starting `| **Product Owner / BA** |` … `| **DevOps / SRE** |`). Replace the four data rows' "Entry → exit artifact" cells so they reference real templates and carry a dedicated/shared marker:
  - **Product Owner / BA** → `` `FEATURE-REQUEST` in → accepted increment out *(dedicated)* ``
  - **Designer** → `` design assets / UX handoff in → `A11Y-SIGNOFF` out *(dedicated)* ``
  - **QA Engineer** → `` `TEST-PLAN` in → `UAT-SIGNOFF` out *(dedicated)* ``
  - **DevOps / SRE** → `` promotion run in → operated service out — works through `RUNBOOK` *(shared)* ``
  Immediately AFTER the table, add a one-line legend:
  ```
  *Dedicated* = a template this persona owns in `templates/`; *shared* = the persona works through another artifact (no persona-specific template). The asymmetry is deliberate — not every lens needs its own template.
  ```

- [ ] **Step 2: §9 UAT gate → UAT-SIGNOFF.** Find the §9 promotion line "UAT green + acceptance sign-off (PO/QA)" and append a reference: `(record it with templates/UAT-SIGNOFF-TEMPLATE.md)`.

- [ ] **Step 3: §5 Designer UX/a11y lens → A11Y-SIGNOFF.** Find the §5 "UX & accessibility lens" line (it flags the WCAG 2.1 AA obligation) and append: `The Designer signs the WCAG check at Review using templates/A11Y-SIGNOFF-TEMPLATE.md.`

- [ ] **Step 4: Verify + commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve. Confirm all three names present in the doc: `for t in TEST-PLAN UAT-SIGNOFF A11Y-SIGNOFF; do grep -q "$t" DEVELOPMENT-PROCESS.md && echo "ok $t" || echo "MISSING $t"; done` → 3 ok.
  ```bash
  git add DEVELOPMENT-PROCESS.md
  git commit -m "docs(9i): annotate persona table (dedicated vs shared) + tie UAT/a11y gates to their sign-off records"
  ```

---

## Task 3: DoD tie-in (`CLAUDE.md`)

**Files:** Modify `CLAUDE.md`

- [ ] **Step 1: Name A11Y-SIGNOFF on the DoD Accessibility line.** Find:
  ```
  **Accessibility** — keyboard-navigable · screen-reader/contrast checks pass (for user-facing UI).
  ```
  Replace with:
  ```
  **Accessibility** — keyboard-navigable · screen-reader/contrast checks pass (for user-facing UI); recorded in an a11y sign-off (`templates/A11Y-SIGNOFF-TEMPLATE.md`).
  ```
  This names the auditable evidence for an obligation that already exists. Do NOT touch any other DoD line; add no new requirement.

- [ ] **Step 2: Verify (no requirement weakened) + commit.**
  Run: `git diff CLAUDE.md` — confirm the ONLY change is the Accessibility line gaining the sign-off reference. Run `sh conformance/check-links.sh 2>&1 | tail -1`.
  ```bash
  git add CLAUDE.md
  git commit -m "docs(9i): DoD Accessibility item names A11Y-SIGNOFF as its auditable evidence (no new requirement)"
  ```

---

## Task 4: `conformance/persona-artifacts.sh`

**Files:** Create `conformance/persona-artifacts.sh`

- [ ] **Step 1: Write the check** (completeness drift-guard + two-tree `--selftest`, no `rm` — same shape as `stack-selection.sh`):

```sh
#!/bin/sh
# persona-artifacts.sh — completeness drift-guard for the SDLC-persona artifacts (Slice 9i / R9).
# Asserts: (a) the three per-gate templates exist; (b) DEVELOPMENT-PROCESS.md §2 names each.
# Completeness, NOT content-equality. A persona artifact must be both shipped and referenced
# in the persona table, or this fails.
#   sh conformance/persona-artifacts.sh [--selftest]
# Exit: 0 = complete · 1 = a gap · 2 = bad usage. POSIX sh; dash-clean.
set -eu

TEMPLATES_DIR="templates"
PERSONA_DOC="DEVELOPMENT-PROCESS.md"
ARTIFACTS="TEST-PLAN UAT-SIGNOFF A11Y-SIGNOFF"

# check_tree <templates-dir> <persona-doc>: print PASS/FAIL; return 1 if any gap.
check_tree() {
  tdir=$1; doc=$2; f=0
  if [ ! -f "$doc" ]; then echo "FAIL: missing $doc"; return 1; fi
  for a in $ARTIFACTS; do
    tfile="$tdir/${a}-TEMPLATE.md"
    if [ -f "$tfile" ]; then echo "PASS: template $tfile exists"; else echo "FAIL: missing template $tfile"; f=1; fi
    if grep -q "$a" "$doc"; then echo "PASS: persona table names $a"; else echo "FAIL: $doc omits $a"; f=1; fi
  done
  return $f
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  # gap tree: no template files + doc names only one artifact -> must be detected
  g=$(mktemp -d); mkdir -p "$g/templates"
  printf '# proc\n| QA | TEST-PLAN |\n' > "$g/proc.md"
  if check_tree "$g/templates" "$g/proc.md" >/dev/null 2>&1; then
    echo "FAIL: selftest — gap not detected"; sfail=1
  else
    echo "PASS: selftest — missing templates / table refs detected"
  fi
  # complete tree: all three templates + all three names -> must pass
  ok=$(mktemp -d); mkdir -p "$ok/templates"
  for a in $ARTIFACTS; do printf '# %s\n' "$a" > "$ok/templates/${a}-TEMPLATE.md"; done
  printf '# proc\n| QA | TEST-PLAN -> UAT-SIGNOFF |\n| Designer | A11Y-SIGNOFF |\n' > "$ok/proc.md"
  if check_tree "$ok/templates" "$ok/proc.md" >/dev/null 2>&1; then
    echo "PASS: selftest — complete set passes"
  else
    echo "FAIL: selftest — complete set wrongly rejected"; sfail=1
  fi
  [ "$sfail" -eq 0 ] && { echo "OK: persona-artifacts selftest"; exit 0; } || { echo "FAIL: persona-artifacts selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: persona-artifacts.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Persona-artifact completeness:"
if check_tree "$TEMPLATES_DIR" "$PERSONA_DOC"; then
  echo "OK: persona artifacts present + named in the §2 table"
  exit 0
else
  echo "FAIL: persona artifacts incomplete (see above)"
  exit 1
fi
```

- [ ] **Step 2: Make executable + dash-check.**
  Run: `chmod +x conformance/persona-artifacts.sh && dash -n conformance/persona-artifacts.sh && echo "syntax OK"`

- [ ] **Step 3: Run selftest + real check.**
  Run: `sh conformance/persona-artifacts.sh --selftest; echo "exit=$?"` → two `PASS …` + `OK: persona-artifacts selftest`, exit 0.
  Run: `sh conformance/persona-artifacts.sh; echo "exit=$?"` → after Tasks 1–2, all 6 `PASS` (3 templates exist + 3 names present), `OK: …`, exit 0.

- [ ] **Step 4: Commit.**
  ```bash
  git add conformance/persona-artifacts.sh
  git commit -m "feat(conformance): 9i — persona-artifacts.sh completeness drift-guard (+ --selftest)"
  ```

---

## Task 5: START-HERE role rows + conformance index

**Files:** Modify `START-HERE.md`, `conformance/README.md`

- [ ] **Step 1: START-HERE role table.** In the "## Who are you? Start here" table, update the QA and Designer rows' "Then" / start cells to link their templates:
  - QA Engineer row — append to its cell: `→ own the test plan (templates/TEST-PLAN-TEMPLATE.md) and the UAT sign-off (templates/UAT-SIGNOFF-TEMPLATE.md)`.
  - Designer row — append: `→ sign the a11y check (templates/A11Y-SIGNOFF-TEMPLATE.md) at Review`.
  (Read the table first; keep its column structure intact — append within the existing cells, don't add columns.)

- [ ] **Step 2: conformance/README index row** (4-col table `| Check | Type | Contract it proves | Gate |`). After the `stack-selection.sh` row, add:
  ```markdown
  | `persona-artifacts.sh` | script | Slice 9i / R9 — the QA/Designer persona artifacts exist (TEST-PLAN, UAT-SIGNOFF, A11Y-SIGNOFF) and are named in the §2 persona table; drift-guard | CI |
  ```

- [ ] **Step 3: Verify + commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.
  ```bash
  git add START-HERE.md conformance/README.md
  git commit -m "docs(9i): START-HERE QA/Designer rows link their templates; conformance index row"
  ```

---

## Task 6: Wire persona-artifacts into CI (control-plane `cp`)

**Files:** Modify `.github/workflows/ci.yml` (build `/tmp` → human applies)

- [ ] **Step 1: Build candidate.** Read `.github/workflows/ci.yml`; copy to `/tmp/ci.yml.9i`; add to the `conformance` job after the `Stack-selection self-test` step:
  ```yaml
      - name: Persona-artifact completeness (QA/Designer templates present + named)
        run: sh conformance/persona-artifacts.sh
      - name: Persona-artifact self-test
        run: sh conformance/persona-artifacts.sh --selftest
  ```

- [ ] **Step 2: Validate.**
  Run: `ruby -ryaml -e 'd=YAML.load_file("/tmp/ci.yml.9i"); puts d["jobs"].keys.join(",")' && diff .github/workflows/ci.yml /tmp/ci.yml.9i`
  Expected: `conformance,bootstrap,docs-links`; diff = only the two added steps.

- [ ] **Step 3: Hand to Bradley.**
  ```bash
  cp /tmp/ci.yml.9i .github/workflows/ci.yml && git add .github/workflows/ci.yml && git commit -m "ci(kit): 9i — gate persona-artifacts completeness + selftest"
  ```

---

## Task 7: Release (VERSION / CHANGELOG / roadmap + 9i-b row)

**Files:** Modify `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md`

- [ ] **Step 1: `VERSION`** → `2.33.0`.

- [ ] **Step 2: CHANGELOG entry** above `## [2.32.0]`:
  ```markdown
  ## [2.33.0] - 2026-06-10

  Persona symmetry (Slice 9i, Tier 2 of the "Honest Assurance & Adoption Reach" arc). Closes the SDLC-personas finding (review 6/10): QA and Designer were named with "→ exit artifact" promises that dissolved. **MINOR** — additive templates + annotations + a completeness check; no new DoD requirement.

  ### Added
  - **`templates/TEST-PLAN-TEMPLATE.md`** — QA's dedicated artifact (scope, levels, cases↔acceptance-criteria traceability, environments, entry/exit).
  - **`templates/UAT-SIGNOFF-TEMPLATE.md`** / **`templates/A11Y-SIGNOFF-TEMPLATE.md`** — auditable per-gate sign-off records (signer/date/gate/evidence/decision; the a11y one carries the WCAG 2.1 AA checklist + axe/Lighthouse evidence).
  - **`conformance/persona-artifacts.sh`** — completeness drift-guard (templates exist + named in the §2 persona table); `--selftest`. CI-gated.

  ### Changed
  - **`DEVELOPMENT-PROCESS.md` §2 persona table annotated** dedicated-vs-shared (PO/QA/Designer own dedicated artifacts; DevOps/SRE works through the RUNBOOK) — the asymmetry is now explicit, not over-promised. §9 UAT gate and §5 Designer lens reference their sign-off records.
  - **`CLAUDE.md` DoD Accessibility line** names `A11Y-SIGNOFF` as its auditable evidence (no new requirement).
  ```

- [ ] **Step 3: roadmap — mark 9i shipped + add the 9i-b fast-follow row.** In `docs/ROADMAP-SLICE9.md`, replace the `9i` row:
  ```markdown
  | **9i** ✅ | B | **Persona symmetry** (R9) — *shipped v2.33.0.* `TEST-PLAN` + `UAT-SIGNOFF` + `A11Y-SIGNOFF` templates; §2 persona table annotated dedicated-vs-shared; DoD a11y line + §9 UAT gate name their sign-off records; `persona-artifacts.sh` drift-guard. | P1 | MINOR ✅ |
  | **9i-b** | B | **Definition-of-Ready robustness** (fast-follow of 9i) — promote the DoR from a scattered one-liner to a first-class enumerated checklist (peer to the DoD): acceptance criteria written · INVEST-sliced · deps known · threat-model flagged if sensitive · UX/a11y obligation flagged. Tie to the `Ready`→Build gate + `FEATURE-REQUEST`. So "development doesn't proceed without requirements met" is explicit + auditable. | P1 | MINOR |
  ```

- [ ] **Step 4: Verify + commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1 && cat VERSION`
  ```bash
  git add VERSION CHANGELOG.md docs/ROADMAP-SLICE9.md
  git commit -m "chore(release): 2.33.0 — persona symmetry (9i); record 9i-b DoR fast-follow"
  ```

---

## Task 8: Final verification + independent review + PR

- [ ] **Step 1: Full local sweep.**
  ```sh
  sh conformance/persona-artifacts.sh >/dev/null && echo "persona-artifacts OK"
  sh conformance/persona-artifacts.sh --selftest >/dev/null && echo "selftest OK"
  dash -n conformance/persona-artifacts.sh && echo "dash OK"
  sh conformance/verify.sh 2>&1 | tail -1
  sh conformance/check-links.sh 2>&1 | tail -1
  git diff main..HEAD -- CLAUDE.md   # confirm ONLY the Accessibility line changed
  grep -rniE "enterprise|public.media|bradley" templates/TEST-PLAN-TEMPLATE.md templates/UAT-SIGNOFF-TEMPLATE.md templates/A11Y-SIGNOFF-TEMPLATE.md conformance/persona-artifacts.sh || echo "anon clean"
  ```
  Expected: all OK; the `CLAUDE.md` diff is the single Accessibility line; anon clean.

- [ ] **Step 2: Independent review (builder ≠ sole reviewer; CLAUDE.md is a governing surface → security-owner lens).** Dispatch a reviewer on `git diff main...HEAD`: (a) the `CLAUDE.md` DoD edit adds **no new requirement** and weakens nothing — it only names evidence on the existing Accessibility line; (b) the persona-table annotation is honest (dedicated/shared correct; DevOps/SRE genuinely has no dedicated template); (c) `persona-artifacts.sh` POSIX correctness (`return $f`, two-tree selftest no-`rm`, exit codes, `set -eu`, `dash -n`); (d) the templates are usable and the sign-offs are genuinely auditable (structured fields, not prose); (e) anonymization. Fix findings.

- [ ] **Step 3: Push + open PR.**
  ```bash
  git push -u origin feature/slice-9i-persona-symmetry
  gh pr create --base main --head feature/slice-9i-persona-symmetry \
    --title "Slice 9i — Persona Symmetry (v2.33.0)" --body-file /tmp/pr-9i-body.md
  ```
  (Write `/tmp/pr-9i-body.md`: the three artifacts, honest dedicated-vs-shared annotation, DoD/§9 evidence tie-ins, drift-guard, one cp, the recorded 9i-b DoR fast-follow.)

- [ ] **Step 4: Confirm CI green; hand to Bradley to ratify (merge).** Agent never self-merges.

---

## Self-review (against the spec)
- **Spec coverage:** TEST-PLAN + UAT-SIGNOFF + A11Y-SIGNOFF (Task 1) · persona-table annotation + §9/§5 refs (Task 2) · DoD a11y evidence (Task 3) · completeness drift-guard (Task 4) · START-HERE/conformance links (Task 5) · CI cp (Task 6) · MINOR 2.33.0 + 9i-b roadmap row (Task 7) · review + PR (Task 8). All R9 pieces + the spec's §9-not-DoD UAT tie-in covered; 9i-b recorded per the user's fast-follow decision.
- **Placeholder scan:** template contents are concrete field tables; `persona-artifacts.sh` is complete code; doc edits have exact find/replace anchors. No placeholders.
- **Consistency:** the three artifact names (`TEST-PLAN`, `UAT-SIGNOFF`, `A11Y-SIGNOFF`) and the `${a}-TEMPLATE.md` filename pattern are used identically across Tasks 1, 2, 4, 6, 8; version 2.33.0 consistent in Task 7.
