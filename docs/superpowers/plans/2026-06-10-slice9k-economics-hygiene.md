# Economics & Hygiene (Slice 9k) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a load-first `AGENTS.md` brief (cuts the standing per-feature governance load), fix canonical-home/pointer drift for the DoD and security, and kill the recurring README badge drift with a `badge-version.sh` check that has a `--fix` sync.

**Architecture:** One new ≤1-page `AGENTS.md` (index → §-pointers, defers to `CLAUDE.md`); two new POSIX-sh conformance checks (`badge-version.sh` assert+`--fix`, `agents-brief.sh` exists+refs+line-bound); label-only edits to CLAUDE.md/STANDARDS security + a §7 DoD pointer fix; CI wiring. Additive → MINOR v2.35.0.

**Tech Stack:** Markdown + POSIX `sh`. Verified by `badge-version.sh --selftest`, `agents-brief.sh --selftest`, `dash -n`, `check-links.sh`, and a diff-review confirming the security edit is labels-only.

---

## Execution notes
- **One control-plane `cp`:** Task 6 (`.github/workflows/ci.yml`). The two new scripts live in `conformance/` (agent-editable); `CLAUDE.md`/`DEVELOPMENT-STANDARDS.md`/`DEVELOPMENT-PROCESS.md`/`README.md`/`AGENTS.md` are governing/published docs but not guard-protected — edited as proposals, ratified by merge.
- **`CLAUDE.md` security edit is LABELS ONLY** — it must not add, remove, or reword any security rule; it only marks the section as the authoritative summary and points at the STANDARDS §2 expansion. Security-owner lens at review.
- **Badge ordering:** `badge-version.sh --fix` sets the badge to the CURRENT `VERSION` (2.34.0) in Task 3 — BEFORE the CI assert is wired in Task 6 — so CI is never red on the branch. Task 7's release bump re-runs `--fix` → 2.35.0.
- **Anonymization** ([[kit-anonymization]]): generic throughout.
- **Branch:** `feature/slice-9k-economics-hygiene` (holds the spec already, commit `825790b`).

## File structure

| File | Responsibility |
|------|----------------|
| `AGENTS.md` (new) | ≤1-page load-first brief: loop · gates · security · agent boundary · stack — each with a §-pointer; defers to `CLAUDE.md` |
| `conformance/badge-version.sh` (new) | Assert README badge == `VERSION`; `--fix` rewrites; `--selftest` |
| `conformance/agents-brief.sh` (new) | `AGENTS.md` exists + references canonical docs + ≤ line bound; `--selftest` |
| `DEVELOPMENT-PROCESS.md` (modify) | §7 DoD pointer `DEVELOPMENT-STANDARDS.md` → `CLAUDE.md` |
| `CLAUDE.md` (modify) | Security section labeled authoritative summary (+ pointer to STANDARDS §2) — labels only |
| `DEVELOPMENT-STANDARDS.md` (modify) | §2 labeled the expansion of the CLAUDE.md summary |
| `README.md` (modify) | version badge synced (v2.34.0 in Task 3, v2.35.0 at release) |
| `conformance/README.md` (modify) | two index rows |
| `.github/workflows/ci.yml` (modify, **human cp**) | both checks + selftests |
| `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md` (modify) | 2.35.0; 9k → shipped; add 9k-b (core-doc trim) row |

---

## Task 1: `AGENTS.md` — the load-first brief

**Files:** Create `AGENTS.md`

- [ ] **Step 1: Write `AGENTS.md`** (≤ 80 lines; must reference `CLAUDE.md`, `DEVELOPMENT-PROCESS.md`, `DEVELOPMENT-STANDARDS.md`):

```markdown
# AGENTS.md — Agent Operating Brief

> **Index, not authority.** This is the ≤1-page brief an agent loads *first*. `CLAUDE.md` is authoritative; when this and a full doc disagree, the full doc wins. **Load a full doc only when your task touches it** — that keeps the per-feature context small.

## The loop
Discover → Plan → Build → Review → Release → Operate, with retrospectives closing each pass. Full flow, stages, and cadence: **`DEVELOPMENT-PROCESS.md`**.

## The gates (where humans ratify)
- **Definition of Ready** — the entry gate before Build (acceptance criteria · INVEST slice · deps · success metric · conditional flags). **`CLAUDE.md`**.
- **Definition of Done** — the exit gate before an item is closed. **`CLAUDE.md`**.
- **7 required CI gates** — on every PR; the contract is the gate-ids, not a vendor. **`DEVELOPMENT-STANDARDS.md` §14**.
- Conditional gates (threat-model, eval, compliance, deployable, DR readiness) — **`DEVELOPMENT-PROCESS.md` §7**.

## Security (non-negotiable)
Secrets in env / a managed store, never committed · validate input at boundaries · parameterized queries / ORM · least-privilege, short-lived tokens · PII consent + redaction + erasure · immutable audit trail · AI: prompt-injection defense + output validation + evals. Summary in **`CLAUDE.md`**; full bar in **`DEVELOPMENT-STANDARDS.md` §2**.

## The agent boundary
Agents act only within granted capabilities; the runtime guard blocks destructive and control-plane actions. **Agents propose; humans ratify** — never self-merge, never edit the control plane (guard, CI, CODEOWNERS, settings) without a human applying it. Autonomy tiers + guard: **`DEVELOPMENT-PROCESS.md` §13**.

## Your stack
Concrete commands, libraries, and CI live in **`profiles/<stack>.md`** (chosen at Inception). New here? Start at **`START-HERE.md`**.
```

- [ ] **Step 2: Verify line bound + references + links.**
  Run: `awk 'END{print NR}' AGENTS.md` → a number ≤ 80.
  Run: `for r in CLAUDE.md DEVELOPMENT-PROCESS.md DEVELOPMENT-STANDARDS.md; do grep -q "$r" AGENTS.md && echo "ref ok $r" || echo "MISSING $r"; done` → 3 × `ref ok`.
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → `OK: all relative Markdown links resolve`.
  Run: `grep -niE "PBS|public.media|bradley" AGENTS.md || echo clean` → `clean`.

- [ ] **Step 3: Commit.**
  ```bash
  git add AGENTS.md
  git commit -m "docs(9k): AGENTS.md — load-first agent operating brief (index → §-pointers)"
  ```

---

## Task 2: `conformance/agents-brief.sh`

**Files:** Create `conformance/agents-brief.sh`

- [ ] **Step 1: Write the check** (completeness + line-bound + two-tree `--selftest`, no `rm`):

```sh
#!/bin/sh
# agents-brief.sh — keep AGENTS.md a real load-first brief, not a fourth standards doc (Slice 9k).
# Asserts: (a) AGENTS.md exists; (b) it points at each canonical doc; (c) it stays within the line bound.
#   sh conformance/agents-brief.sh [--selftest]
# Exit: 0 = ok · 1 = a gap · 2 = bad usage. POSIX sh; dash-clean.
set -eu

BRIEF="AGENTS.md"
MAX_LINES=80
REFS="CLAUDE.md DEVELOPMENT-PROCESS.md DEVELOPMENT-STANDARDS.md"

# check_brief <brief> <max-lines>: print PASS/FAIL; return 1 on any gap.
check_brief() {
  bf=$1; max=$2; f=0
  if [ ! -f "$bf" ]; then echo "FAIL: missing $bf"; return 1; fi
  n=$(awk 'END{print NR}' "$bf")
  if [ "$n" -le "$max" ]; then
    echo "PASS: $bf is $n lines (<= $max)"
  else
    echo "FAIL: $bf is $n lines (> $max — keep it a brief)"; f=1
  fi
  for r in $REFS; do
    if grep -q "$r" "$bf"; then echo "PASS: $bf points at $r"; else echo "FAIL: $bf does not reference $r"; f=1; fi
  done
  return $f
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  # gap tree: no refs AND over a tiny bound -> must be detected
  g=$(mktemp -d)
  printf 'line one\nline two\nline three\n' > "$g/AGENTS.md"
  if check_brief "$g/AGENTS.md" 2 >/dev/null 2>&1; then
    echo "FAIL: selftest — gap not detected"; sfail=1
  else
    echo "PASS: selftest — missing refs / over-bound detected"
  fi
  # complete tree: refs present, within bound
  ok=$(mktemp -d)
  printf '# brief\nsee CLAUDE.md\nsee DEVELOPMENT-PROCESS.md\nsee DEVELOPMENT-STANDARDS.md\n' > "$ok/AGENTS.md"
  if check_brief "$ok/AGENTS.md" 80 >/dev/null 2>&1; then
    echo "PASS: selftest — complete brief passes"
  else
    echo "FAIL: selftest — complete brief wrongly rejected"; sfail=1
  fi
  [ "$sfail" -eq 0 ] && { echo "OK: agents-brief selftest"; exit 0; } || { echo "FAIL: agents-brief selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: agents-brief.sh [--selftest]" >&2; exit 2 ;;
esac

echo "AGENTS.md brief check:"
if check_brief "$BRIEF" "$MAX_LINES"; then
  echo "OK: AGENTS.md exists, points at the canonical docs, and is within the line bound"
  exit 0
else
  echo "FAIL: AGENTS.md brief incomplete (see above)"
  exit 1
fi
```

- [ ] **Step 2: Make executable + dash-check.**
  Run: `chmod +x conformance/agents-brief.sh && dash -n conformance/agents-brief.sh && echo "syntax OK"` → `syntax OK`.

- [ ] **Step 3: Run selftest + real + bad usage.**
  Run: `sh conformance/agents-brief.sh --selftest; echo "exit=$?"` → two `PASS …` + `OK: agents-brief selftest`, `exit=0`.
  Run: `sh conformance/agents-brief.sh; echo "exit=$?"` → after Task 1, all PASS + `OK: …`, `exit=0`.
  Run: `sh conformance/agents-brief.sh --bogus; echo "exit=$?"` → usage on stderr, `exit=2`.

- [ ] **Step 4: Commit.**
  ```bash
  git add conformance/agents-brief.sh
  git commit -m "feat(conformance): 9k — agents-brief.sh (AGENTS.md exists + refs + line-bound; --selftest)"
  ```

---

## Task 3: `conformance/badge-version.sh` + sync the badge

**Files:** Create `conformance/badge-version.sh`; modify `README.md` (via `--fix`)

- [ ] **Step 1: Write the check** (assert + `--fix` + two-tree `--selftest`):

```sh
#!/bin/sh
# badge-version.sh — keep the README version badge in lockstep with VERSION (Slice 9k).
#   sh conformance/badge-version.sh            assert the badge == VERSION (CI gate; exit 1 on drift)
#   sh conformance/badge-version.sh --fix      rewrite the badge from VERSION (idempotent)
#   sh conformance/badge-version.sh --selftest fixture: drift fails, --fix syncs, synced passes
# Exit: 0 = ok · 1 = drift · 2 = bad usage. POSIX sh; dash-clean.
set -eu

VERSION_FILE="VERSION"
README="README.md"

read_version() { tr -d '[:space:]' < "$1"; }

# badge_version <readme>: echo the digits inside the first `vX.Y.Z` token, or empty.
badge_version() {
  grep -oE '`v[0-9]+\.[0-9]+\.[0-9]+`' "$1" 2>/dev/null | head -1 | tr -d '`v'
}

# assert_badge <version-file> <readme>: print PASS/FAIL; return 1 on drift.
assert_badge() {
  v=$(read_version "$1"); b=$(badge_version "$2")
  if [ -z "$b" ]; then echo "FAIL: no \`vX.Y.Z\` badge found in $2"; return 1; fi
  if [ "$b" = "$v" ]; then echo "PASS: README badge v$b matches VERSION $v"; return 0; fi
  echo "FAIL: README badge v$b != VERSION $v (run: sh conformance/badge-version.sh --fix)"; return 1
}

# fix_badge <version-file> <readme>: rewrite the first badge token from VERSION (idempotent).
fix_badge() {
  v=$(read_version "$1"); tmp="$2.tmp.$$"
  sed "s/\`v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\`/\`v$v\`/" "$2" > "$tmp" && mv "$tmp" "$2"
  echo "fixed: README badge set to v$v"
}

case "${1:-}" in
  --selftest)
    sfail=0
    d=$(mktemp -d)
    printf '2.34.0\n' > "$d/VERSION"
    printf '# X\n\n`v2.24.0` · Apache-2.0\n' > "$d/README.md"
    if assert_badge "$d/VERSION" "$d/README.md" >/dev/null 2>&1; then
      echo "FAIL: selftest — drift not detected"; sfail=1
    else
      echo "PASS: selftest — drift detected"
    fi
    fix_badge "$d/VERSION" "$d/README.md" >/dev/null 2>&1
    if assert_badge "$d/VERSION" "$d/README.md" >/dev/null 2>&1; then
      echo "PASS: selftest — --fix synced the badge"
    else
      echo "FAIL: selftest — --fix did not sync"; sfail=1
    fi
    [ "$sfail" -eq 0 ] && { echo "OK: badge-version selftest"; exit 0; } || { echo "FAIL: badge-version selftest"; exit 1; }
    ;;
  --fix)
    fix_badge "$VERSION_FILE" "$README"; exit 0
    ;;
  "")
    if assert_badge "$VERSION_FILE" "$README"; then exit 0; else exit 1; fi
    ;;
  *)
    echo "usage: badge-version.sh [--fix|--selftest]" >&2; exit 2
    ;;
esac
```

- [ ] **Step 2: Make executable + dash-check.**
  Run: `chmod +x conformance/badge-version.sh && dash -n conformance/badge-version.sh && echo "syntax OK"` → `syntax OK`.

- [ ] **Step 3: Selftest + prove it catches the live drift.**
  Run: `sh conformance/badge-version.sh --selftest; echo "exit=$?"` → `PASS: … drift detected` + `PASS: … --fix synced` + `OK`, `exit=0`.
  Run: `sh conformance/badge-version.sh; echo "exit=$?"` → CURRENTLY **FAIL** (`README badge v2.24.0 != VERSION 2.34.0`), `exit=1`. This proves the drift is real.

- [ ] **Step 4: Sync the live badge with `--fix`.**
  Run: `sh conformance/badge-version.sh --fix` → `fixed: README badge set to v2.34.0`.
  Run: `sh conformance/badge-version.sh; echo "exit=$?"` → now `PASS`, `exit=0`.
  Run: `git diff README.md` → confirm the ONLY change is the badge token `` `v2.24.0` `` → `` `v2.34.0` ``.

- [ ] **Step 5: Bad usage + commit.**
  Run: `sh conformance/badge-version.sh --bogus; echo "exit=$?"` → usage on stderr, `exit=2`.
  ```bash
  git add conformance/badge-version.sh README.md
  git commit -m "feat(conformance): 9k — badge-version.sh (assert + --fix); sync README badge to v2.34.0"
  ```

---

## Task 4: Canonical-home + pointer fixes (labels only)

**Files:** Modify `DEVELOPMENT-PROCESS.md`, `CLAUDE.md`, `DEVELOPMENT-STANDARDS.md`

- [ ] **Step 1: §7 DoD pointer → `CLAUDE.md`.** In `DEVELOPMENT-PROCESS.md`, find:
```
| **Definition of Done** | Truly complete? (per `DEVELOPMENT-STANDARDS.md`) | Automated + human |
```
Replace with:
```
| **Definition of Done** | Truly complete? (the enumerated exit gate in `CLAUDE.md`; quality bar in `DEVELOPMENT-STANDARDS.md`) | Automated + human |
```

- [ ] **Step 2: Label the CLAUDE.md security summary.** In `CLAUDE.md`, find the security heading:
```
## Security (non-negotiable)
```
Replace with:
```
## Security (non-negotiable)

> **Authoritative summary.** These are the non-negotiable rules in brief; the full bar (secrets-at-scale, cost governance, per-rule detail) is their expansion in `DEVELOPMENT-STANDARDS.md` §2. This summary and that expansion must agree.
```
(Insert the blockquote directly under the heading; do NOT change any of the security bullets below it.)

- [ ] **Step 3: Label the STANDARDS §2 expansion.** In `DEVELOPMENT-STANDARDS.md`, find:
```
## 2. Security, Governance & Guardrails

Apply to EVERY project, EVERY feature. Non-negotiable. **→ profile** for the concrete libraries/snippets in your stack.
```
Replace with:
```
## 2. Security, Governance & Guardrails

Apply to EVERY project, EVERY feature. Non-negotiable. **→ profile** for the concrete libraries/snippets in your stack. This section is the **expansion** of the authoritative summary in `CLAUDE.md` ("Security (non-negotiable)") — the two must agree.
```

- [ ] **Step 4: Verify (security rules unchanged) + commit.**
  Run: `git diff CLAUDE.md` — confirm the ONLY change is the added blockquote under the heading; every security bullet is untouched.
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.
  ```bash
  git add DEVELOPMENT-PROCESS.md CLAUDE.md DEVELOPMENT-STANDARDS.md
  git commit -m "docs(9k): one canonical home per concept — DoD→CLAUDE.md, security summary↔expansion labeled (no rule changed)"
  ```

---

## Task 5: conformance index rows

**Files:** Modify `conformance/README.md`

- [ ] **Step 1: Add two rows.** In the table `| Check | Type | Contract it proves | Gate |`, after the `dor-defined.sh` row, add:
```markdown
| `badge-version.sh` | script | Slice 9k — the README version badge equals `VERSION` (drift-guard with `--fix` sync) | CI |
| `agents-brief.sh` | script | Slice 9k — `AGENTS.md` exists, points at the canonical docs, and stays within the brief line-bound | CI |
```

- [ ] **Step 2: Verify + commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.
  ```bash
  git add conformance/README.md
  git commit -m "docs(9k): conformance index rows for badge-version.sh + agents-brief.sh"
  ```

---

## Task 6: Wire both checks into CI (control-plane `cp`)

**Files:** Modify `.github/workflows/ci.yml` (build `/tmp` → human applies)

- [ ] **Step 1: Build candidate.** Read `.github/workflows/ci.yml` with the Read tool. Write a copy to `/tmp/ci.yml.9k` (use the Write tool — do NOT `cp`/`sed` the control-plane path) with FOUR steps added to the `conformance` job immediately after the `Definition-of-Ready self-test` step:
  ```yaml
      - name: README badge matches VERSION (no drift)
        run: sh conformance/badge-version.sh
      - name: Badge-version self-test
        run: sh conformance/badge-version.sh --selftest
      - name: AGENTS.md load-first brief (exists + refs + line-bound)
        run: sh conformance/agents-brief.sh
      - name: AGENTS.md brief self-test
        run: sh conformance/agents-brief.sh --selftest
  ```

- [ ] **Step 2: Validate the candidate.**
  Run: `ruby -ryaml -e 'd=YAML.load_file("/tmp/ci.yml.9k"); puts d["jobs"].keys.join(",")'` → `conformance,bootstrap,docs-links`.
  Run: `diff .github/workflows/ci.yml /tmp/ci.yml.9k` → the only diff is the four added steps (8 `>` lines). (`diff` is read-only; the guard allows it.)

- [ ] **Step 3: Hand to Bradley (human `cp`).** Present exactly:
  ```bash
  cd /Users/bradleyjames/Development/agentic-sdlc-kit && cp /tmp/ci.yml.9k .github/workflows/ci.yml && git add .github/workflows/ci.yml && git commit -m "ci(kit): 9k — gate badge-version + agents-brief (+ selftests)"
  ```
  Wait for confirmation before continuing.

---

## Task 7: Release (VERSION / badge / CHANGELOG / roadmap + 9k-b row)

**Files:** Modify `VERSION`, `README.md`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md`

- [ ] **Step 1: Bump `VERSION`** → replace `2.34.0` with `2.35.0`.

- [ ] **Step 2: Sync the badge to the new version.**
  Run: `sh conformance/badge-version.sh --fix` → `fixed: README badge set to v2.35.0`.
  Run: `sh conformance/badge-version.sh; echo "exit=$?"` → `PASS`, `exit=0`. (Demonstrates the release `--fix` step that ends badge drift for good.)

- [ ] **Step 3: CHANGELOG entry** immediately above `## [2.34.0]`:
  ```markdown
  ## [2.35.0] - 2026-06-10

  Economics & hygiene (Slice 9k, Stage V of the "Honest Assurance & Adoption Reach" arc). A load-first agent brief, one canonical home per governance concept, and a self-healing version badge. **MINOR** — additive brief + two completeness checks + label-only doc edits; no governing rule changed.

  ### Added
  - **`AGENTS.md`** — a ≤1-page load-first operating brief (loop · gates · security · agent boundary · stack), each with a §-pointer; an index that defers to `CLAUDE.md`. Instructs agents to expand a full doc only when the task touches it — turning the standing per-feature governance load into an on-demand pull.
  - **`conformance/badge-version.sh`** — asserts the README badge equals `VERSION`; `--fix` rewrites it; `--selftest`. The release flow calls `--fix`, ending the recurring badge drift (was 10 versions stale).
  - **`conformance/agents-brief.sh`** — keeps `AGENTS.md` a brief: exists, points at the canonical docs, within a line-bound; `--selftest`.

  ### Changed
  - **One canonical home per concept:** the §7 Definition-of-Done gate now points at `CLAUDE.md` (its real home); the `CLAUDE.md` security section is labeled the authoritative summary and `DEVELOPMENT-STANDARDS.md` §2 its expansion — the layering is explicit, no rule changed.
  - **README version badge** synced to the current release (no longer stale).
  ```

- [ ] **Step 4: roadmap — mark 9k shipped + add the 9k-b row.** In `docs/ROADMAP-SLICE9.md`, replace the `9k` row:
  ```markdown
  | **9k** ✅ | B | **Economics & hygiene** (R11) — *shipped v2.35.0.* `AGENTS.md` load-first brief (on-demand governance load); one canonical home per concept (DoD→`CLAUDE.md`; security summary↔expansion labeled); `badge-version.sh` (assert + `--fix`, release-wired) + `agents-brief.sh` drift-guards. | P2 | MINOR ✅ |
  | **9k-b** | B | **Core-doc trim** (fast-follow of 9k) — tighten `CLAUDE.md` / `DEVELOPMENT-PROCESS.md` / `DEVELOPMENT-STANDARDS.md` prose and push detail to references, measured against the `AGENTS.md` brief-enabled load. Cut the ~24K/feature standing load materially, from data not feel. | P2 | MINOR |
  ```

- [ ] **Step 5: Verify + commit.**
  Run: `cat VERSION` → `2.35.0`. Run: `sh conformance/badge-version.sh; echo "exit=$?"` → `PASS exit=0`. Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.
  ```bash
  git add VERSION README.md CHANGELOG.md docs/ROADMAP-SLICE9.md
  git commit -m "chore(release): 2.35.0 — economics & hygiene (9k); record 9k-b core-doc trim"
  ```

---

## Task 8: Final verification + independent review + PR

- [ ] **Step 1: Full local sweep.**
  ```sh
  sh conformance/badge-version.sh >/dev/null && echo "badge OK"
  sh conformance/badge-version.sh --selftest >/dev/null && echo "badge selftest OK"
  sh conformance/agents-brief.sh >/dev/null && echo "brief OK"
  sh conformance/agents-brief.sh --selftest >/dev/null && echo "brief selftest OK"
  dash -n conformance/badge-version.sh && dash -n conformance/agents-brief.sh && echo "dash OK"
  sh conformance/verify.sh 2>&1 | tail -1
  sh conformance/check-links.sh 2>&1 | tail -1
  git diff main..HEAD -- CLAUDE.md     # confirm security edit is labels-only (one added blockquote; bullets untouched)
  grep -rniE "PBS|public.media|bradley" AGENTS.md conformance/badge-version.sh conformance/agents-brief.sh || echo "anon clean"
  ```
  Expected: all OK; the `CLAUDE.md` diff is a single added blockquote under the security heading; anon clean.

- [ ] **Step 2: Independent review (builder ≠ sole reviewer; CLAUDE.md is a governing surface → security-owner lens).** Dispatch a reviewer on `git diff main...HEAD`: (a) the `CLAUDE.md` security edit is **labels only** — no security rule added, removed, or reworded (only a summary↔expansion blockquote); (b) `AGENTS.md` is an honest index that defers to `CLAUDE.md` and does not contradict it, stays ≤ the line bound, and its §-pointers resolve; (c) `badge-version.sh` POSIX correctness (`assert_badge`/`fix_badge` functions, the `grep -oE | head | tr` extraction, `--fix` idempotence, exit codes 0/1/2, `set -eu`, `dash -n`) and that `--selftest` genuinely catches drift (not a rubber-stamp); (d) `agents-brief.sh` POSIX correctness (line-bound via `awk 'END{print NR}'`, refs loop, two-tree selftest no-`rm`, exit codes); (e) the §7 DoD pointer now names the correct home; (f) anonymization. Fix findings; re-review if non-trivial.

- [ ] **Step 3: Push + open PR.**
  ```bash
  git push -u origin feature/slice-9k-economics-hygiene
  gh pr create --base main --head feature/slice-9k-economics-hygiene \
    --title "Slice 9k — Economics & Hygiene (v2.35.0)" --body-file /tmp/pr-9k-body.md
  ```
  (Write `/tmp/pr-9k-body.md`: the load-first brief + economics lever, canonical-home/pointer fixes (labels only), the two drift-guards, the self-healing badge, one cp, the recorded 9k-b core-doc-trim fast-follow.)

- [ ] **Step 4: Confirm CI green; hand to Bradley to ratify (merge).** Agent never self-merges.

---

## Self-review (against the spec)
- **Spec coverage:** AGENTS.md brief (Task 1) · agents-brief.sh (Task 2) · badge-version.sh + badge sync (Task 3) · canonical-home/pointer + security labels (Task 4) · conformance index (Task 5) · CI cp (Task 6) · MINOR 2.35.0 + 9k-b row (Task 7) · review + PR (Task 8). All spec components + the labels-only guarantee + the deferred 9k-b trim covered.
- **Placeholder scan:** AGENTS.md content, both scripts, and the doc edits are complete literal content with exact anchors. No placeholders; the line-bound is the concrete `80`.
- **Consistency:** `MAX_LINES=80` in `agents-brief.sh` (Task 2) matches the "≤ 80 lines" bound AGENTS.md is written to (Task 1); `badge-version.sh`'s `assert_badge`/`fix_badge`/`badge_version` names are used identically across Task 3 and the selftest; the badge token regex `` `v[0-9]+\.[0-9]+\.[0-9]+` `` matches the README line-3 format; version 2.35.0 consistent across VERSION + badge + CHANGELOG (Task 7).
