# Core-Doc Trim (Slice 9k-b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Conservatively tighten the three core governing docs (removing only redundancy/verbosity, preserving every normative line) and add a `doc-budget.sh` ratchet so they cannot silently re-bloat.

**Architecture:** Prose-tightening edits to `DEVELOPMENT-PROCESS.md` / `DEVELOPMENT-STANDARDS.md` / `CLAUDE.md` (no section renumbering, every conformance-grepped marker preserved); a new line-budget ratchet; CI wiring. The deliverable's safety is the **full existing conformance suite staying green** + a line-by-line content checklist + the security-owner lens. Additive/MINOR → v2.38.0.

**Tech Stack:** Markdown + POSIX `sh`. Verified by the whole conformance suite, `doc-budget.sh --selftest`, `dash -n`, `check-links.sh`, and a content-preservation audit.

---

## Execution notes
- **This is the most governance-sensitive slice** (heavy edits to the 3 governing docs). The trim **removes only**: literal restated framing, redundant preamble, over-explanation duplicating a normative statement, and stack/example detail with an existing `profiles/`/`docs/` home. It **never removes a normative statement** — only tightens wording, keeping meaning + every grepped marker.
- **Mechanical gate:** after each trim, the **entire conformance suite must stay green** — `verify.sh` + `dor-defined` + `conditional-gates` + `backlog-adapters` + `guard-wired` + `agent-autonomy` + `ci-gates` + `check-links`. They grep the normative markers; a lost requirement fails CI.
- **One control-plane `cp`:** Task 6 (`.github/workflows/ci.yml`).
- **Branch:** `feature/slice-9k-b-core-doc-trim` (holds the spec, commit `ef66cdc`).

## The CONTENT CHECKLIST (must all survive — possibly reworded, never removed)
Confirm each is still present after every trim (this is the "retain all that is necessary" guarantee):
1. The **6-stage loop** (Discover → Plan → Build → Review → Release → Operate) + the stage table.
2. **§2 roles** — the persona table incl. the dedicated/shared annotation + the conditional-gate rows added in 9i/9j.
3. **§5 Discovery** prompts incl. the UX/a11y lens → A11Y-SIGNOFF.
4. **§6 work-item contract** — the six states · required fields · **atomic claim**; the named backlog backend table (drift-locked by `backlog-adapters.sh`).
5. **§7 gates** — the universal set + the **conditional trio** rows verbatim (`Accessibility** *(user-facing UI)*`, `Eval gate** *(AI features)*`, `Resilience readiness** *(deployable services)*`), DoR, DoD, threat-model, compliance, deployable, DR.
6. **§9 environments** — Dev → QA → UAT → Prod promotion + the UAT-SIGNOFF reference.
7. **§13 autonomy tiers** + the agent guard / capability-boundary language.
8. **The Definition of Ready** entry-gate reference (drift-locked by `dor-defined.sh`).
9. Every `§N` heading and its number (no renumbering).

## Cut-vs-keep method (apply to each doc)
**CUT (safe):** sentences that restate a point already made; multi-clause framing that can be one clause; "Purpose/Applies to/Status/Relationship/Last-Updated" preambles trimmed to the essential; parenthetical asides that re-explain a defined term; example lists that duplicate `profiles/`/`docs/` content (replace with the reference).
**KEEP (never cut):** any normative MUST/required statement; gate names + triggers; the checklist items above; tables that encode the contract; cross-reference targets (`§N`, file names).

---

## Task 1: Tighten `DEVELOPMENT-PROCESS.md` (the main target, ~466 lines)

**Files:** Modify `DEVELOPMENT-PROCESS.md`

- [ ] **Step 1: Record the before-size.** Run: `awk 'END{print NR}' DEVELOPMENT-PROCESS.md` → note N_before (currently 466).

- [ ] **Step 2: Tighten the header + §1 framing.** These are pure preamble. Example — the header block (lines ~3-11) and §1 (lines ~15-23) restate the doc's purpose three times. Tighten the **Purpose/Applies-to/Status/Relationship/Last-Updated** stack to the essential (keep the `CLAUDE.md`-is-authoritative line and the MANDATORY status), and reduce §1's two framing paragraphs (the "Governing Lens" + the "second pattern" paragraph) to the single load-bearing principle blockquote plus one sentence. **Keep** the principle itself and the "Definition of Ready, acceptance criteria, demo/acceptance, retrospectives, adversarial review" list (those are referenced practices).

- [ ] **Step 3: Sweep the remaining sections for redundancy** (§2–§17), applying the cut-vs-keep method. Tighten restated framing and over-explanation **within** each section; do **not** remove or renumber any `## N.` heading, any table, or any normative line. Concretely: collapse multi-sentence restatements to one; drop parentheticals that re-define an already-defined term; where a passage enumerates stack/example detail that lives in a profile or `docs/` file, replace the enumeration with the reference.

- [ ] **Step 4: Verify nothing normative was lost — THE GATE.**
  ```sh
  sh conformance/check-links.sh 2>&1 | tail -1
  sh conformance/dor-defined.sh >/dev/null && echo "DoR ok"
  sh conformance/conditional-gates.sh >/dev/null && echo "conditional-gates ok"
  sh conformance/backlog-adapters.sh >/dev/null && echo "backlog-adapters ok"
  sh conformance/agent-autonomy.sh >/dev/null && echo "agent-autonomy ok"
  sh conformance/guard-wired.sh >/dev/null 2>&1; echo "guard-wired exit=$? (0 or non-applicable)"
  sh conformance/verify.sh 2>&1 | tail -1
  for h in "## 6." "## 7." "## 9." "## 13." "Definition of Ready" "Accessibility** *(user-facing UI)*" "Eval gate** *(AI features)*" "Resilience readiness** *(deployable services)*"; do grep -qF "$h" DEVELOPMENT-PROCESS.md && echo "keep ok: $h" || echo "LOST: $h"; done
  awk 'END{print NR}' DEVELOPMENT-PROCESS.md   # N_after; record the delta
  ```
  Expected: all conformance green; every `keep ok:` present (zero `LOST:`); N_after < N_before.

- [ ] **Step 5: Commit.**
  ```bash
  git add DEVELOPMENT-PROCESS.md
  git commit -m "docs(9k-b): tighten DEVELOPMENT-PROCESS.md prose (no renumbering; all markers + normative lines preserved)"
  ```

---

## Task 2: Tighten `DEVELOPMENT-STANDARDS.md` (lighter, ~309 lines)

**Files:** Modify `DEVELOPMENT-STANDARDS.md`

- [ ] **Step 1: Record before-size.** Run: `awk 'END{print NR}' DEVELOPMENT-STANDARDS.md` → N_before (currently 309).

- [ ] **Step 2: Tighten the header + verbose prose**, applying the cut-vs-keep method. **Keep verbatim:** the §14 seven-gate table, the "Conditional gates (a11y/load/eval)" note + `SLSA Build L2` declaration (9j), the §2 security non-negotiables (incl. the authoritative-summary blockquote from 9k), the commit/tag-signing subsection, the brownfield-exception note. Tighten only restated framing and over-explanation around them.

- [ ] **Step 3: Verify — THE GATE.**
  ```sh
  sh conformance/check-links.sh 2>&1 | tail -1
  for m in "seven required gates" "SLSA Build L2" "Conditional gates" "Commit & tag signing" "secret-scan"; do grep -qF "$m" DEVELOPMENT-STANDARDS.md && echo "keep ok: $m" || echo "LOST: $m"; done
  sh conformance/ci-gates.sh profiles/typescript-node/ci.yml | tail -1   # gate-id contract unaffected
  sh conformance/verify.sh 2>&1 | tail -1
  awk 'END{print NR}' DEVELOPMENT-STANDARDS.md   # N_after
  ```
  Expected: links green; every `keep ok:`; N_after ≤ N_before.

- [ ] **Step 4: Commit.**
  ```bash
  git add DEVELOPMENT-STANDARDS.md
  git commit -m "docs(9k-b): tighten DEVELOPMENT-STANDARDS.md prose (gates/SLSA/security preserved verbatim)"
  ```

---

## Task 3: Tighten `CLAUDE.md` (minimal, ~111 lines)

**Files:** Modify `CLAUDE.md`

- [ ] **Step 1: Record before-size.** Run: `awk 'END{print NR}' CLAUDE.md` → N_before (currently 111).

- [ ] **Step 2: Light tighten only.** `CLAUDE.md` is the lean authoritative file — touch sparingly. **Keep verbatim:** the entire `## Definition of "Ready"` block, the `## Definition of "Done"` block (incl. `the 7 required gates pass` + the conditional-gates clause), the `## Security (non-negotiable)` summary + its authoritative-summary blockquote. Tighten only the doc-set table preamble / any restated framing.

- [ ] **Step 3: Verify — THE GATE.**
  ```sh
  git diff CLAUDE.md   # confirm only framing tightened; the DoR/DoD/Security blocks intact
  for m in 'Definition of "Ready"' 'Definition of "Done"' 'the 7 required gates pass' 'Security (non-negotiable)'; do grep -qF "$m" CLAUDE.md && echo "keep ok: $m" || echo "LOST: $m"; done
  sh conformance/dor-defined.sh >/dev/null && echo "DoR ok"
  sh conformance/check-links.sh 2>&1 | tail -1
  awk 'END{print NR}' CLAUDE.md   # N_after
  ```
  Expected: every `keep ok:`; DoR ok; links green; N_after ≤ N_before.

- [ ] **Step 4: Commit.**
  ```bash
  git add CLAUDE.md
  git commit -m "docs(9k-b): light tighten of CLAUDE.md framing (DoR/DoD/Security blocks untouched)"
  ```

---

## Task 4: Full preservation audit (content checklist + suite)

**Files:** none (verification only)

- [ ] **Step 1: Run the entire conformance suite — the mechanical proof.**
  ```sh
  sh conformance/verify.sh 2>&1 | tail -3
  for c in dor-defined conditional-gates backlog-adapters agent-autonomy persona-artifacts badge-version agents-brief; do
    sh conformance/$c.sh >/dev/null 2>&1 && echo "$c OK" || echo "$c CHECK (exit $?)"
  done
  sh conformance/check-links.sh 2>&1 | tail -1
  ```
  Expected: `verify.sh` → `RESULT: OK`; each check OK; links resolve. **Any failure = a normative marker was cut → fix before proceeding.**

- [ ] **Step 2: Confirm the content checklist by eye.** For each of the 9 checklist items in this plan's "CONTENT CHECKLIST", grep/scan the relevant doc and confirm it is present (reworded is fine). Record any that read as weakened (not just shortened) and restore them.

---

## Task 5: `conformance/doc-budget.sh` (the ratchet)

**Files:** Create `conformance/doc-budget.sh`; modify `conformance/README.md`

- [ ] **Step 1: Measure the post-trim sizes** to set the budgets.
  Run: `for f in CLAUDE.md DEVELOPMENT-PROCESS.md DEVELOPMENT-STANDARDS.md; do printf "%s %s\n" "$f" "$(awk 'END{print NR}' "$f")"; done` and the total. Set each budget = the doc's post-trim line count **rounded up to the next 10** (small headroom so a future one-line clarification doesn't nuisance-fail); set `TOTAL_BUDGET` = the rounded sum.

- [ ] **Step 2: Write `conformance/doc-budget.sh`** (fill the three `:NN` budgets + `TOTAL_BUDGET` with the Step-1 numbers):

```sh
#!/bin/sh
# doc-budget.sh — ratchet the core governing-doc size so they cannot silently re-bloat (Slice 9k-b).
# Asserts each core doc (and the core-3 total) is at/under a line budget set at the post-trim size.
# Raising a budget is a DELIBERATE, ratified change — edit the constants below in a reviewed PR (the
# same governed-bump pattern as the coverage ratchet). This prevents drift; it does not forbid growth.
#   sh conformance/doc-budget.sh [--selftest]
# Exit: 0 = within budget · 1 = over budget · 2 = bad usage. POSIX sh; dash-clean.
set -eu

# Per-doc line budgets (post-9k-b sizes, rounded up to the next 10). "<path>:<max-lines>".
BUDGETS="CLAUDE.md:NN DEVELOPMENT-PROCESS.md:NN DEVELOPMENT-STANDARDS.md:NN"
TOTAL_BUDGET=NN

# check_one <path> <max>: print PASS/FAIL; return 1 if over budget or missing.
check_one() {
  p=$1; max=$2
  if [ ! -f "$p" ]; then echo "FAIL: missing $p"; return 1; fi
  n=$(awk 'END{print NR}' "$p")
  if [ "$n" -le "$max" ]; then echo "PASS: $p $n/$max lines"; return 0; fi
  echo "FAIL: $p $n lines > budget $max (re-bloat — tighten, or raise the budget in a ratified PR)"; return 1
}

run_budgets() {
  f=0; total=0
  for entry in $BUDGETS; do
    p=${entry%:*}; max=${entry#*:}
    check_one "$p" "$max" || f=1
    n=$(awk 'END{print NR}' "$p" 2>/dev/null || echo 0); total=$((total + n))
  done
  if [ "$total" -le "$TOTAL_BUDGET" ]; then echo "PASS: core-3 total $total/$TOTAL_BUDGET lines"; else echo "FAIL: core-3 total $total > $TOTAL_BUDGET (re-bloat)"; f=1; fi
  return $f
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  d=$(mktemp -d); printf 'a\nb\nc\n' > "$d/doc.md"   # 3 lines
  if check_one "$d/doc.md" 2 >/dev/null 2>&1; then echo "FAIL: selftest — over-budget not detected"; sfail=1; else echo "PASS: selftest — over-budget detected"; fi
  if check_one "$d/doc.md" 5 >/dev/null 2>&1; then echo "PASS: selftest — within-budget passes"; else echo "FAIL: selftest — within-budget wrongly rejected"; sfail=1; fi
  [ "$sfail" -eq 0 ] && { echo "OK: doc-budget selftest"; exit 0; } || { echo "FAIL: doc-budget selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: doc-budget.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Core-doc budget:"
if run_budgets; then
  echo "OK: core docs within budget"
  exit 0
else
  echo "FAIL: a core doc is over budget (see above)"
  exit 1
fi
```

- [ ] **Step 3: Make executable + dash-check + run.**
  Run: `chmod +x conformance/doc-budget.sh && dash -n conformance/doc-budget.sh && echo "syntax OK"`.
  Run: `sh conformance/doc-budget.sh --selftest; echo "exit=$?"` → 2 PASS + OK, exit 0.
  Run: `sh conformance/doc-budget.sh; echo "exit=$?"` → all PASS (each doc + total within budget), exit 0.
  Run: `sh conformance/doc-budget.sh --bogus; echo "exit=$?"` → exit 2.

- [ ] **Step 4: conformance/README index row.** After the `tracker-contract.sh` row, add:
  ```markdown
  | `doc-budget.sh` | script | Slice 9k-b — the core governing docs stay within their post-trim line budget (no silent re-bloat); budgets raised only by a ratified PR | CI |
  ```

- [ ] **Step 5: Verify + commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.
  ```bash
  git add conformance/doc-budget.sh conformance/README.md
  git commit -m "feat(conformance): 9k-b — doc-budget.sh core-doc line ratchet (+ --selftest)"
  ```

---

## Task 6: Wire `doc-budget.sh` into CI (control-plane `cp`)

**Files:** Modify `.github/workflows/ci.yml` (build `/tmp` → human applies)

- [ ] **Step 1: Build candidate.** Read `.github/workflows/ci.yml`; Write a copy to `/tmp/ci.yml.9kb` (Write tool — do NOT `cp`/`sed` the control-plane path) with TWO steps added to the `conformance` job immediately after the `Tracker-contract UNVERIFIED without creds (honest non-pass)` step:
  ```yaml
      - name: Core-doc budget (no silent re-bloat)
        run: sh conformance/doc-budget.sh
      - name: Doc-budget self-test
        run: sh conformance/doc-budget.sh --selftest
  ```

- [ ] **Step 2: Validate.**
  Run: `ruby -ryaml -e 'd=YAML.load_file("/tmp/ci.yml.9kb"); puts d["jobs"].keys.join(",")'` → `conformance,bootstrap,docs-links`.
  Run: `diff .github/workflows/ci.yml /tmp/ci.yml.9kb` → only the two added steps (4 `>` lines).

- [ ] **Step 3: Hand to Bradley (human `cp`).** Present exactly:
  ```bash
  cd /Users/bradleyjames/Development/agentic-sdlc-kit && cp /tmp/ci.yml.9kb .github/workflows/ci.yml && git add .github/workflows/ci.yml && git commit -m "ci(kit): 9k-b — gate core-doc budget + selftest"
  ```
  Wait for confirmation.

---

## Task 7: Release (VERSION / CHANGELOG / roadmap + measured delta)

**Files:** Modify `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md`

- [ ] **Step 1: `VERSION`** → replace `2.37.0` with `2.38.0`.

- [ ] **Step 2: Sync the badge.**
  Run: `sh conformance/badge-version.sh --fix` → `fixed: README badge set to v2.38.0`. Run: `sh conformance/badge-version.sh; echo exit=$?` → PASS exit 0.

- [ ] **Step 3: CHANGELOG entry** above `## [2.37.0]` — fill the before/after line counts from Tasks 1-3:
  ```markdown
  ## [2.38.0] - 2026-06-10

  Core-doc trim (Slice 9k-b, fast-follow of 9k). A conservative prose tightening of the three core governing docs plus a ratchet that prevents future bloat. **MINOR** — no governance content removed; every normative line, gate, and conformance marker preserved (proven by the full suite staying green). Measured: the arc had added only ~39 lines to the core-3; this trim removes pre-existing verbosity.

  ### Changed
  - **`DEVELOPMENT-PROCESS.md`** (<N_before>→<N_after> lines), **`DEVELOPMENT-STANDARDS.md`** (<N_before>→<N_after>), **`CLAUDE.md`** (<N_before>→<N_after>) — restated framing/preamble/over-explanation tightened; no section renumbered; the §6/§7/§9/§13 contract, DoD/DoR, security non-negotiables, conditional gates, and SLSA declaration all preserved.

  ### Added
  - **`conformance/doc-budget.sh`** — a per-doc + core-3 line-budget ratchet (no silent re-bloat); budgets raised only by a ratified PR. `--selftest`, CI-gated.
  ```

- [ ] **Step 4: roadmap — mark 9k-b shipped + update the economics note.** In `docs/ROADMAP-SLICE9.md`, replace the `9k-b` row:
  ```markdown
  | **9k-b** ✅ | B | **Core-doc trim** (fast-follow of 9k) — *shipped v2.38.0.* Conservative prose tighten of the 3 core docs (no governance removed; suite-green preservation proof + content checklist); `doc-budget.sh` ratchet prevents re-bloat. Measured: arc added only ~39 core-3 lines; economics already banked by `AGENTS.md`. | P2 | MINOR ✅ |
  ```
  And append to the **Economics baseline** note near the top: ` **Update (v2.38.0): the arc added only ~39 lines to the core-3; 9k-b tightened pre-existing verbosity and ratcheted the size (`conformance/doc-budget.sh`). The standing per-feature load is on-demand via `AGENTS.md` (9k).**`

- [ ] **Step 5: Verify + commit.**
  Run: `cat VERSION` → `2.38.0`. Run: `sh conformance/doc-budget.sh >/dev/null && echo "budget ok"`. Run: `sh conformance/check-links.sh 2>&1 | tail -1`.
  ```bash
  git add VERSION README.md CHANGELOG.md docs/ROADMAP-SLICE9.md
  git commit -m "chore(release): 2.38.0 — core-doc trim (9k-b); record before/after + ratchet"
  ```

---

## Task 8: Final verification + independent review + PR

- [ ] **Step 1: Full local sweep.**
  ```sh
  sh conformance/verify.sh 2>&1 | tail -1
  sh conformance/doc-budget.sh >/dev/null && echo "doc-budget OK"
  sh conformance/doc-budget.sh --selftest >/dev/null && echo "selftest OK"
  dash -n conformance/doc-budget.sh && echo "dash OK"
  sh conformance/check-links.sh 2>&1 | tail -1
  # content checklist markers all present:
  for m in "Definition of Ready" 'Definition of "Done"' "the 7 required gates pass" "SLSA Build L2" "Accessibility** *(user-facing UI)*" "Eval gate** *(AI features)*" "Resilience readiness** *(deployable services)*"; do grep -rqF "$m" CLAUDE.md DEVELOPMENT-PROCESS.md DEVELOPMENT-STANDARDS.md && echo "keep ok: $m" || echo "LOST: $m"; done
  ```
  Expected: `RESULT: OK`; doc-budget OK; every `keep ok:` (zero `LOST:`).

- [ ] **Step 2: Independent review (builder ≠ sole reviewer; CLAUDE.md + the two standards docs are governing surfaces → security-owner lens).** Dispatch a reviewer on `git diff main...HEAD`: (a) the diff is **prose-tightening only** — confirm NO normative statement, gate, requirement, or table row was removed or weakened (only reworded/shortened); walk the plan's 9-item CONTENT CHECKLIST and verify each survives; (b) **no section was renumbered** and no `§N`/file cross-reference broke (`check-links.sh` green); (c) every conformance-grepped marker is present (the suite is green — confirm `verify.sh` RESULT: OK); (d) `doc-budget.sh` POSIX correctness (the `for entry in $BUDGETS` parse, `check_one` exit codes, `--selftest` over/within fixtures, `set -eu`, `dash -n`) and that the budgets match the as-shipped sizes (with only small headroom); (e) the security-owner lens: no security/governance bar lowered. Report any line that reads as *weakened* vs merely *shorter*. Fix findings.

- [ ] **Step 3: Push + open PR.**
  ```bash
  git push -u origin feature/slice-9k-b-core-doc-trim
  gh pr create --base main --head feature/slice-9k-b-core-doc-trim \
    --title "Slice 9k-b — Core-Doc Trim (v2.38.0)" --body-file /tmp/pr-9kb-body.md
  ```
  (Write `/tmp/pr-9kb-body.md`: the measured premise (arc added ~39 lines), conservative tighten with the three-way preservation audit, the doc-budget ratchet, before/after deltas, one cp.)

- [ ] **Step 4: Confirm CI green; hand to Bradley to ratify (merge).** Agent never self-merges.

---

## Self-review (against the spec)
- **Spec coverage:** conservative trim of all three docs (T1-T3) · three-way preservation audit — suite + content checklist + security lens (T4, T8) · `doc-budget.sh` ratchet (T5) · CI cp (T6) · MINOR 2.38.0 + measured delta (T7) · review + PR (T8). All spec components covered.
- **Placeholder scan:** the `<N_before>/<N_after>` and `:NN` budget tokens are intentional measure-then-fill values (Task 1-3 / Task 5 Step 1 compute them); `doc-budget.sh` is otherwise complete; the trim tasks are judgment-method + a mechanical gate, the honest shape for prose work. No vague placeholders.
- **Consistency:** the conformance markers grepped in the per-task gates (T1/T2/T3) match the content checklist and the T8 final sweep; `doc-budget.sh`'s `BUDGETS`/`TOTAL_BUDGET` are set from the same post-trim measurement the CHANGELOG records; version 2.38.0 consistent across VERSION + badge + CHANGELOG + roadmap.
```
