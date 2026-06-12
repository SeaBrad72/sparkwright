# A7 Residual Cleanup (Slice 10) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clear the five residuals the A7 re-review surfaced — `gh` preflight, the solo `enforce_admins` trap, the Jira `--deep` verifier, the brownfield `.gitignore` line, and lifting the reversible-amend over-block.

**Architecture:** Small targeted edits across preflight / docs / a profile / `tracker-contract.sh` / the guard core. One control-plane `cp` (`guard-core.sh`). Verified by the existing conformance suite + the scripts' `--selftest`. Additive → MINOR v2.39.0.

**Tech Stack:** POSIX `sh` + Markdown. The guard change is loosening one over-block; the destructive-action battery (`agent-autonomy.sh`) stays green.

---

## Execution notes
- **One control-plane `cp`:** Task 5 (`.claude/hooks/guard-core.sh`, applied with `KIT_GUARD_SELFEDIT=1`). Everything else is agent-editable.
- **Security-owner lens** on the guard diff — confirm ONLY the amend deny is removed.
- **Branch:** `feature/slice-10-residual-cleanup` (holds the spec, commit `4216a88`).
- **Anonymization** ([[kit-anonymization]]): generic.

## File structure

| File | Responsibility |
|------|----------------|
| `scripts/preflight.sh` (modify) | soft `recommend()` for `gh` + auth; `--selftest` |
| `START-HERE.md` (modify) | Solo track sets `enforce_admins: false` |
| `profiles/typescript-node/BRANCH-PROTECTION.md` (modify) | "Solo scale" note |
| `conformance/tracker-contract.sh` (modify) | `--deep` Only-Assignee introspection + fixtures |
| `templates/JIRA-SETUP-TEMPLATE.md` (modify) | point at `--deep` |
| `docs/adoption/brownfield.md` (modify) | `.gitignore` instruction |
| `.claude/hooks/guard-core.sh` (modify, **human cp**) | remove the amend deny |
| `conformance/agent-autonomy.sh` (modify) | `assert_allow 'git commit --amend'` |
| `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md` (modify) | 2.39.0; A7-residuals cleared |

---

## Task 1: `gh` soft-recommend in preflight

**Files:** Modify `scripts/preflight.sh`

- [ ] **Step 1: Add the `rec`/`recommend()` helper.** Find:
```sh
miss=0
need() {  # need <tool> <install-hint>
  if command -v "$1" >/dev/null 2>&1; then
    echo "  ok   $1"
  else
    echo "  MISS $1 — $2"
    miss=1
  fi
}
```
Replace with (adds `rec=0` + a warns-not-fails `recommend()`):
```sh
miss=0; rec=0
need() {  # need <tool> <install-hint>
  if command -v "$1" >/dev/null 2>&1; then
    echo "  ok   $1"
  else
    echo "  MISS $1 — $2"
    miss=1
  fi
}
recommend() {  # recommend <tool> <why+hint> — warns, never fails the run
  if command -v "$1" >/dev/null 2>&1; then
    echo "  ok   $1"
  else
    echo "  warn $1 — $2"
    rec=1
  fi
}
```

- [ ] **Step 2: Add the recommended-tools block.** Find:
```sh
need jq  "brew install jq | apt-get install jq | dnf install jq"
need git "git-scm.com/downloads"
need sh  "any POSIX shell"
```
Insert AFTER that block:
```sh

echo "Recommended (GitHub-based flows — skip on GitLab/ADO):"
recommend gh "GitHub CLI — needed for the branch-protection setup at Inception (cli.github.com)"
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then echo "  ok   gh auth (logged in)"; else echo "  warn gh auth — run 'gh auth login' before the branch-protection step"; rec=1; fi
fi
```

- [ ] **Step 3: Extend the selftest to prove `recommend` never fails.** Find (inside the `--selftest` block):
```sh
  if stack_tools python >/dev/null 2>&1; then echo "PASS: known stack mapped"; else echo "FAIL: known stack not mapped"; fail=1; fi
  [ "$fail" -eq 0 ] && { echo "OK: preflight selftest"; exit 0; } || { echo "FAIL: preflight selftest"; exit 1; }
```
Replace with:
```sh
  if stack_tools python >/dev/null 2>&1; then echo "PASS: known stack mapped"; else echo "FAIL: known stack not mapped"; fail=1; fi
  miss=0; recommend kit_definitely_absent_tool_xyz "x" >/dev/null 2>&1
  if [ "$miss" -eq 0 ]; then echo "PASS: recommend warns without failing (miss untouched)"; else echo "FAIL: recommend set miss"; fail=1; fi
  [ "$fail" -eq 0 ] && { echo "OK: preflight selftest"; exit 0; } || { echo "FAIL: preflight selftest"; exit 1; }
```

- [ ] **Step 4: Verify + commit.**
  Run: `dash -n scripts/preflight.sh && echo "syntax OK"`.
  Run: `sh scripts/preflight.sh --selftest; echo "exit=$?"` → all PASS + `OK: preflight selftest`, exit 0.
  Run: `sh scripts/preflight.sh >/dev/null 2>&1; echo "live exit=$?"` → exit 0 if jq/git/sh present (the `gh` warning never changes the exit code).
  ```bash
  git add scripts/preflight.sh
  git commit -m "feat(preflight): 9-residual — soft-recommend gh + auth for GitHub flows (warns, never fails)"
  ```

---

## Task 2: Solo-track `enforce_admins` fix

**Files:** Modify `START-HERE.md`, `profiles/typescript-node/BRANCH-PROTECTION.md`

- [ ] **Step 1: START-HERE solo-track bullet.** Find:
```
- **builder ≠ reviewer, solo.** You still open a PR and let CI gate it, then **merge your own PR via owner admin-merge.** GitHub records the admin bypass — that log *is* your audit trail of "solo maintainer self-ratified." When a second engineer joins, the required-review rule starts enforcing real review with **zero reconfiguration.**
```
Replace with:
```
- **builder ≠ reviewer, solo.** Open a PR, let CI gate it, then **merge your own PR via owner admin-merge** (`gh pr merge --admin`). At solo scale set **`enforce_admins: false`** in your branch protection so the admin-merge is permitted — GitHub records the bypass, and that log *is* your audit trail of "solo maintainer self-ratified." When a second engineer joins, flip `enforce_admins` back to **`true`**: the required-review rule then enforces real review (you can no longer self-merge), with no other reconfiguration.
```

- [ ] **Step 2: BRANCH-PROTECTION.md solo note.** In `profiles/typescript-node/BRANCH-PROTECTION.md`, find the line `  "enforce_admins": true,` and insert a comment/line immediately ABOVE the JSON block (do not break the JSON). Locate the prose line that precedes the config (or add a note right after the config block). Concretely, append this sentence to the paragraph that introduces the config (the one ending before the JSON), or add it as a standalone line directly after the closing of the config block:
```
> **Solo scale:** set `"enforce_admins": false` so the owner can admin-merge their own PR (the audit-trailed self-ratification of `START-HERE.md`'s solo track); flip to `true` the moment a second reviewer exists.
```
(Read the file first; place the `>` note adjacent to the `enforce_admins` setting without altering the JSON's validity.)

- [ ] **Step 3: Verify (conformance unaffected) + commit.**
  Run: `sh conformance/branch-protection.sh --selftest; echo "exit=$?"` → still OK, exit 0 (the check never asserted `enforce_admins`).
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.
  ```bash
  git add START-HERE.md profiles/typescript-node/BRANCH-PROTECTION.md
  git commit -m "docs(9-residual): solo track sets enforce_admins:false so owner admin-merge works (flip to true with a 2nd reviewer)"
  ```

---

## Task 3: Jira `--deep` Only-Assignee verifier

**Files:** Modify `conformance/tracker-contract.sh`, `templates/JIRA-SETUP-TEMPLATE.md`

- [ ] **Step 1: Rewrite `conformance/tracker-contract.sh`** to add `--deep` (the base behavior is unchanged; `--deep` adds the workflow-condition introspection, combinable with `--selftest` and the live path):

```sh
#!/bin/sh
# tracker-contract.sh — verify a Jira instance satisfies the §6 work-item contract (Slice 9h; --deep 10).
# Three-state, like branch-protection.sh:
#   creds (JIRA_BASE_URL + JIRA_EMAIL + JIRA_TOKEN) -> live REST check -> PASS/FAIL
#   no creds                                         -> UNVERIFIED (exit 2; never a silent pass)
#   --selftest                                       -> run the contract logic on fixtures (CI-safe)
# Base run checks the six §6 states + Size/Risk fields. With --deep, ALSO introspects the workflow
# (/rest/api/3/workflow/search?expand=transitions.rules) to VERIFY the In-Progress transition carries
# an assignee-restriction condition (the Only-Assignee atomic claim) — turning "attested" into
# "verified". The deep matcher is best-effort: Jira workflow JSON shape varies (Cloud/Server), so it
# matches a broad assignee-restriction marker; the parse logic is proven in --selftest on a fixture.
# Zero-dependency core (grep-based); curl only on the live path. POSIX sh; dash-clean.
# Exit: 0 = satisfied · 1 = a gap · 2 = UNVERIFIED / bad usage.
set -eu

REQUIRED="Backlog Ready In-Progress In-Review Released Done Blocked Size Risk"

# check_blob <file>: every required name must appear as an EXACT quoted value (whitespace-insensitive).
check_blob() {
  bf=$1; f=0
  if [ ! -f "$bf" ]; then echo "FAIL: missing $bf"; return 1; fi
  norm=$(tr -s '[:space:]' '-' < "$bf")
  for name in $REQUIRED; do
    if printf '%s' "$norm" | grep -qF -- "\"$name\""; then
      echo "PASS: contract names '$name'"
    else
      echo "FAIL: contract omits '$name'"; f=1
    fi
  done
  return $f
}

# deep_check <file>: the workflow JSON must carry an assignee-restriction condition. Best-effort,
# broad matcher (the In-Progress transition's Only-Assignee rule). Return 1 if absent.
deep_check() {
  bf=$1
  if [ ! -f "$bf" ]; then echo "FAIL: missing $bf"; return 1; fi
  if grep -Eiq 'onlyassignee|assignee[^"]*condition|"is[_-]?assignee"' "$bf"; then
    echo "PASS: deep — workflow carries an assignee-restriction condition (Only-Assignee → server-enforced claim)"
    return 0
  fi
  echo "FAIL: deep — no assignee-restriction condition found (the atomic claim is NOT server-enforced — see JIRA-SETUP.md §3)"
  return 1
}

# live_check <base-url>: fetch statuses + fields, run check_blob (no attest line — caller handles deep/attest).
live_check() {
  base=$1; tmp=$(mktemp)
  curl -fsS -u "$JIRA_EMAIL:$JIRA_TOKEN" "$base/rest/api/3/status" >> "$tmp" 2>/dev/null || {
    echo "FAIL: could not reach $base/rest/api/3/status"; rm -f "$tmp"; return 1; }
  curl -fsS -u "$JIRA_EMAIL:$JIRA_TOKEN" "$base/rest/api/3/field" >> "$tmp" 2>/dev/null || {
    echo "FAIL: could not reach $base/rest/api/3/field"; rm -f "$tmp"; return 1; }
  if check_blob "$tmp"; then rc=0; else rc=1; fi
  rm -f "$tmp"; return $rc
}

# deep_live <base-url>: fetch the workflow with transition rules, run deep_check.
deep_live() {
  base=$1; tmp=$(mktemp)
  curl -fsS -u "$JIRA_EMAIL:$JIRA_TOKEN" "$base/rest/api/3/workflow/search?expand=transitions.rules" >> "$tmp" 2>/dev/null || {
    echo "FAIL: could not reach $base/rest/api/3/workflow/search"; rm -f "$tmp"; return 1; }
  if deep_check "$tmp"; then rc=0; else rc=1; fi
  rm -f "$tmp"; return $rc
}

# --- arg parse: --deep and --selftest combine in any order ---
DEEP=0; SELFTEST=0
for a in "$@"; do
  case "$a" in
    --deep) DEEP=1 ;;
    --selftest) SELFTEST=1 ;;
    "") : ;;
    *) echo "usage: tracker-contract.sh [--deep] [--selftest]" >&2; exit 2 ;;
  esac
done

if [ "$SELFTEST" -eq 1 ]; then
  sfail=0
  okf=$(mktemp); printf '"Backlog" "Ready" "In Progress" "In Review" "Released" "Done" "Blocked" "Size" "Risk"\n' > "$okf"
  if check_blob "$okf" >/dev/null 2>&1; then echo "PASS: selftest — conformant config passes"; else echo "FAIL: selftest — conformant wrongly rejected"; sfail=1; fi
  gapf=$(mktemp); printf '"Backlog" "Ready" "In Progress" "In Review" "Released" "Done" "Blocked" "Size"\n' > "$gapf"
  if check_blob "$gapf" >/dev/null 2>&1; then echo "FAIL: selftest — gap (missing Risk) not detected"; sfail=1; else echo "PASS: selftest — gap detected"; fi
  nmf=$(mktemp); printf '"Backlog" "Ready for Dev" "In Progress" "In Review" "Released" "Done" "Blocked" "Size" "Risk"\n' > "$nmf"
  if check_blob "$nmf" >/dev/null 2>&1; then echo "FAIL: selftest — loose 'Ready for Dev' wrongly accepted"; sfail=1; else echo "PASS: selftest — near-miss status name rejected"; fi
  # deep fixtures: a workflow WITH the Only-Assignee condition must pass; one WITHOUT must fail.
  okd=$(mktemp); printf '{"values":[{"transitions":[{"name":"In Progress","rules":{"conditions":[{"type":"OnlyAssigneeCondition"}]}}]}]}\n' > "$okd"
  if deep_check "$okd" >/dev/null 2>&1; then echo "PASS: selftest — deep accepts Only-Assignee condition"; else echo "FAIL: selftest — deep wrongly rejected the condition"; sfail=1; fi
  gapd=$(mktemp); printf '{"values":[{"transitions":[{"name":"In Progress","rules":{"conditions":[]}}]}]}\n' > "$gapd"
  if deep_check "$gapd" >/dev/null 2>&1; then echo "FAIL: selftest — deep missed an absent condition"; sfail=1; else echo "PASS: selftest — deep detects an absent condition"; fi
  rm -f "$okf" "$gapf" "$nmf" "$okd" "$gapd"
  [ "$sfail" -eq 0 ] && { echo "OK: tracker-contract selftest"; exit 0; } || { echo "FAIL: tracker-contract selftest"; exit 1; }
fi

if [ -n "${JIRA_BASE_URL:-}" ] && [ -n "${JIRA_EMAIL:-}" ] && [ -n "${JIRA_TOKEN:-}" ]; then
  echo "Jira contract check (live: $JIRA_BASE_URL):"
  ok=0
  if live_check "$JIRA_BASE_URL"; then :; else ok=1; fi
  if [ "$DEEP" -eq 1 ]; then
    echo "Deep: Only-Assignee transition condition (workflow introspection):"
    if deep_live "$JIRA_BASE_URL"; then :; else ok=1; fi
  else
    echo "ATTESTED (not auto-verified): confirm the Only-Assignee condition, or re-run with --deep to verify it — see JIRA-SETUP.md."
  fi
  if [ "$ok" -eq 0 ]; then
    if [ "$DEEP" -eq 1 ]; then echo "OK: Jira satisfies the §6 contract (incl. the verified Only-Assignee claim)"; else echo "OK: Jira satisfies the §6 contract"; fi
    exit 0
  else
    echo "FAIL: Jira does not satisfy the §6 contract (see above)"; exit 1
  fi
else
  echo "UNVERIFIED: set JIRA_BASE_URL + JIRA_EMAIL + JIRA_TOKEN to verify a live Jira (exit 2, not a pass)."
  echo "  Configure per JIRA-SETUP.md; this is the kit's honest 'cannot run != pass' (conformance/README.md)."
  exit 2
fi
```

- [ ] **Step 2: Make executable + dash + selftest + UNVERIFIED + bad usage.**
  Run: `chmod +x conformance/tracker-contract.sh && dash -n conformance/tracker-contract.sh && echo "syntax OK"`.
  Run: `sh conformance/tracker-contract.sh --selftest; echo "exit=$?"` → conformant/gap/near-miss + the 2 deep lines all PASS, `OK`, exit 0.
  Run: `env -u JIRA_BASE_URL -u JIRA_EMAIL -u JIRA_TOKEN sh conformance/tracker-contract.sh --deep; echo "exit=$?"` → UNVERIFIED, exit 2.
  Run: `sh conformance/tracker-contract.sh --bogus; echo "exit=$?"` → usage, exit 2.

- [ ] **Step 3: JIRA-SETUP §4 points at `--deep`.** In `templates/JIRA-SETUP-TEMPLATE.md`, find:
```
`sh conformance/tracker-contract.sh`
It verifies the six states + Size/Risk fields live, and reminds you to confirm the Only-Assignee condition (which basic REST cannot introspect — it is **attested**, not auto-verified).
```
Replace with:
```
`sh conformance/tracker-contract.sh`
It verifies the six states + Size/Risk fields live. Add **`--deep`** to also introspect the workflow and **verify** the In-Progress transition carries the Only-Assignee condition (turning the atomic claim from *attested* into *verified*):
`sh conformance/tracker-contract.sh --deep`
```

- [ ] **Step 4: Commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1`.
  ```bash
  git add conformance/tracker-contract.sh templates/JIRA-SETUP-TEMPLATE.md
  git commit -m "feat(conformance): 9-residual — tracker-contract --deep verifies the Only-Assignee condition (attested→verified)"
  ```

---

## Task 4: Brownfield `.gitignore` instruction

**Files:** Modify `docs/adoption/brownfield.md`

- [ ] **Step 1: Append the instruction.** Find:
```
3. Leave `.claude/settings.local.json` alone — it is **gitignored** (personal, per-developer). Do not copy the kit's over yours.
```
Replace with:
```
3. Leave `.claude/settings.local.json` alone — it is **gitignored** (personal, per-developer). Do not copy the kit's over yours. **Add `.claude/settings.local.json` to your repo's `.gitignore`** if it isn't already — the kit's own `.gitignore` has the line, but your existing repo's won't, and the personal overrides must never be committed.
```

- [ ] **Step 2: Verify + commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1`.
  ```bash
  git add docs/adoption/brownfield.md
  git commit -m "docs(9-residual): brownfield — instruct adding settings.local.json to the adopter's own .gitignore"
  ```

---

## Task 5: Lift the amend over-block (control-plane `cp`) + regression-lock

**Files:** Modify `conformance/agent-autonomy.sh` (agent); `.claude/hooks/guard-core.sh` (**human cp**)

- [ ] **Step 1: Add the allow-assert to `agent-autonomy.sh`.** Find:
```sh
assert_allow "git commit"          '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"x\""}}'
```
Insert immediately AFTER it:
```sh
assert_allow "git commit --amend"  '{"tool_name":"Bash","tool_input":{"command":"git commit --amend --no-edit"}}'
```
(This will FAIL until the guard-core deny is removed in Step 3 — that is expected; it is the regression-lock for the new behavior.)

- [ ] **Step 2: Build the guard-core candidate (no direct edit — it is control-plane).** Read `.claude/hooks/guard-core.sh` with the Read tool. Write a copy to `/tmp/guard-core.sh.s10` (Write tool) that is **identical except** the 3-line amend-deny block is removed:
```sh
  if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+commit[[:space:]]+.*--amend'; then
    { printf '%s' '13: git commit --amend rewrites history - human-gated.'; return 1; }
  fi
```
Everything else (force-push, non-fast-forward, `reset --hard`, `git clean -fdx`, destructive matrix, control-plane protection) stays byte-for-byte.

- [ ] **Step 3: Validate the candidate before handing it over.**
  Run: `dash -n /tmp/guard-core.sh.s10 && echo "syntax OK"`.
  Run the deny/allow battery against the candidate by sourcing it:
  ```sh
  sh -c '. /tmp/guard-core.sh.s10
    for c in "git commit --amend --no-edit" "git commit -m x"; do guard_check_command "$c" >/dev/null 2>&1 && echo "ALLOW ok: $c" || echo "DENY (unexpected): $c"; done
    for c in "git push --force origin main" "git reset --hard HEAD~2" "rm -rf /tmp/x" "git push origin main"; do guard_check_command "$c" >/dev/null 2>&1 && echo "ALLOW (UNEXPECTED): $c" || echo "DENY ok: $c"; done'
  ```
  Expected: `ALLOW ok: git commit --amend …` and `git commit -m x`; `DENY ok:` for force-push / reset --hard / rm -rf / push-to-main. (Confirms ONLY amend changed.)
  Run: `diff .claude/hooks/guard-core.sh /tmp/guard-core.sh.s10` → only the 3 amend-deny lines removed.

- [ ] **Step 4: Hand to Bradley (human `cp`, control-plane + self-edit flag).** Present exactly:
  ```bash
  cd ~/Development/agentic-sdlc-kit && KIT_GUARD_SELFEDIT=1 cp /tmp/guard-core.sh.s10 .claude/hooks/guard-core.sh && git add .claude/hooks/guard-core.sh conformance/agent-autonomy.sh && git commit -m "fix(guard): 9-residual — allow reversible git commit --amend (force-push/non-ff still denied); regression-locked"
  ```
  Wait for confirmation, THEN continue.

- [ ] **Step 5: Verify post-cp — the whole guard battery green.**
  Run: `sh conformance/agent-autonomy.sh; echo "exit=$?"` → all PASS incl. the new amend allow + every force-push/destructive deny, exit 0.
  Run: `sh scripts/kit-guard --selftest >/dev/null && echo "kit-guard OK"`; `sh hooks/pre-push --selftest >/dev/null && echo "pre-push OK"`; `sh conformance/guard-core-sourced.sh >/dev/null && echo "single-core OK"`.

---

## Task 6: Release (VERSION / CHANGELOG / roadmap)

**Files:** Modify `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md`

- [ ] **Step 1: `VERSION`** → replace `2.38.0` with `2.39.0`.

- [ ] **Step 2: Sync badge.**
  Run: `sh conformance/badge-version.sh --fix` → `fixed: README badge set to v2.39.0`. Run: `sh conformance/badge-version.sh; echo exit=$?` → PASS exit 0.

- [ ] **Step 3: CHANGELOG entry** above `## [2.38.0]`:
  ```markdown
  ## [2.39.0] - 2026-06-10

  A7 residual cleanup (Slice 10). Clears the small backlog the arc-closure re-review surfaced. **MINOR** — additive checks/docs + one guard over-block lifted; no governance bar lowered.

  ### Added / Changed
  - **`preflight.sh`** soft-recommends `gh` + auth for GitHub flows (warns, never fails — GitLab/ADO unaffected).
  - **Solo/lite track** now sets `enforce_admins: false` so the owner admin-merge self-ratification actually works (flip to `true` with a second reviewer); the reference `BRANCH-PROTECTION.md` carries a solo note. Conformance unaffected (`branch-protection.sh` never asserted `enforce_admins`).
  - **`tracker-contract.sh --deep`** introspects the Jira workflow and **verifies** the Only-Assignee transition condition (the atomic claim moves from *attested* to *verified*); three-state, fixture-tested.
  - **Brownfield guide** instructs adding `.claude/settings.local.json` to the adopter's own `.gitignore`.
  - **Guard:** lifted the over-block on the reversible `git commit --amend` (force-push / non-fast-forward / `reset --hard` stay denied); regression-locked by an `agent-autonomy.sh` allow-case.
  ```

- [ ] **Step 4: roadmap note.** In `docs/ROADMAP-SLICE9.md`, append to the A7 row (or just below the closing line) a one-liner:
  ```markdown

  **Post-arc (v2.39.0):** the A7 residual backlog (gh preflight · solo `enforce_admins` trap · Jira `--deep` · brownfield `.gitignore` · amend over-block) was cleared in **Slice 10**.
  ```

- [ ] **Step 5: Verify + commit.**
  Run: `cat VERSION` → `2.39.0`. Run: `sh conformance/check-links.sh 2>&1 | tail -1`.
  ```bash
  git add VERSION README.md CHANGELOG.md docs/ROADMAP-SLICE9.md
  git commit -m "chore(release): 2.39.0 — A7 residual cleanup (Slice 10)"
  ```

---

## Task 7: Final verification + independent review + PR

- [ ] **Step 1: Full local sweep.**
  ```sh
  sh scripts/preflight.sh --selftest >/dev/null && echo "preflight OK"
  sh conformance/tracker-contract.sh --selftest >/dev/null && echo "tracker selftest OK"
  env -u JIRA_BASE_URL -u JIRA_EMAIL -u JIRA_TOKEN sh conformance/tracker-contract.sh --deep >/dev/null 2>&1; test $? -eq 2 && echo "deep UNVERIFIED honesty OK"
  sh conformance/agent-autonomy.sh >/dev/null && echo "agent-autonomy OK (amend allowed; force-push denied)"
  sh conformance/branch-protection.sh --selftest >/dev/null && echo "branch-protection OK"
  dash -n scripts/preflight.sh && dash -n conformance/tracker-contract.sh && echo "dash OK"
  sh conformance/verify.sh 2>&1 | tail -1
  sh conformance/check-links.sh 2>&1 | tail -1
  ```
  Expected: all OK; `verify.sh` RESULT: OK.

- [ ] **Step 2: Independent review (builder ≠ sole reviewer; the guard edit is a control-plane safety surface → security-owner lens).** Dispatch a reviewer on `git diff main...HEAD`: (a) the guard diff removes **only** the amend deny — force-push, non-fast-forward, `reset --hard`, destructive matrix, and control-plane protection are intact (confirm via `agent-autonomy.sh` green + the diff); reversible amend is genuinely safe given force-push stays denied; (b) `preflight` `recommend()` warns without affecting exit code (GitLab adopters not blocked); (c) the solo `enforce_admins:false` guidance is correct and doesn't weaken the team default or trip `branch-protection.sh`; (d) `tracker-contract.sh --deep` POSIX correctness (arg parse, `deep_check` matcher, three-state, `--selftest` deep fixtures genuinely catch an absent condition), and the deep matcher's best-effort nature is honestly documented; (e) anonymization. Fix findings.

- [ ] **Step 3: Push + open PR.**
  ```bash
  git push -u origin feature/slice-10-residual-cleanup
  gh pr create --base main --head feature/slice-10-residual-cleanup \
    --title "Slice 10 — A7 Residual Cleanup (v2.39.0)" --body-file /tmp/pr-s10-body.md
  ```
  (Write `/tmp/pr-s10-body.md`: the five residuals closed, the guard loosening with the safety argument, one cp.)

- [ ] **Step 4: Confirm CI green; hand to Bradley to ratify (merge).** Agent never self-merges.

---

## Self-review (against the spec)
- **Spec coverage:** gh preflight (T1) · solo enforce_admins (T2) · Jira --deep (T3) · brownfield gitignore (T4) · amend lift + regression-lock (T5) · MINOR 2.39.0 (T6) · review + PR (T7). All five residuals + release covered.
- **Placeholder scan:** preflight + tracker-contract are complete code; the guard change is an exact 3-line removal validated by a source-test; doc edits have exact anchors. No placeholders.
- **Consistency:** the `recommend()`/`rec` names are defined in T1 and used consistently; the `--deep`/`deep_check`/`deep_live` names match across T3 body + selftest; the amend allow-case in T5 Step 1 matches the deny removed in T5 Step 2; version 2.39.0 consistent across VERSION + badge + CHANGELOG (T6).
```
