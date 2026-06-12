# Hosted-Tracker Bootstrap (Slice 9h) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `incept --backlog jira` emit a concrete, project-stamped `JIRA-SETUP.md` (and a convention-tier stub for the other hosted trackers), and add a three-state `tracker-contract.sh` that verifies a live Jira against the §6 work-item contract.

**Architecture:** Two new `templates/` setup guides incept copies+stamps; new `case "$BACKLOG"` arms in `scripts/incept.sh`; a new POSIX-sh three-state verifier (`tracker-contract.sh`, grep-based core so `--selftest` runs cred-free in CI); doc pointers + CI wiring. Additive → MINOR v2.37.0.

**Tech Stack:** Markdown + POSIX `sh` + `curl` (live path only). Verified by `tracker-contract.sh --selftest`, `dash -n`, a temp `incept` bootstrap, `backlog-adapters.sh`, `check-links.sh`.

---

## Execution notes
- **One control-plane `cp`:** Task 5 (`.github/workflows/ci.yml`). `scripts/incept.sh` is agent-editable (not control-plane); the two scripts/templates likewise.
- **Three-state honesty:** `tracker-contract.sh` follows `branch-protection.sh` — live PASS/FAIL with creds, **UNVERIFIED (exit 2)** without, `--selftest` on fixtures. The Only-Assignee transition condition is **attested, not auto-verified**.
- **Zero-dependency core:** the contract check is grep-based (no `jq`); `curl` only on the live path.
- **Anonymization** ([[kit-anonymization]]): templates use placeholders, never a real Jira URL/org.
- **Branch:** `feature/slice-9h-hosted-tracker` (holds the spec, commit `cafcf85`).

## File structure

| File | Responsibility |
|------|----------------|
| `templates/JIRA-SETUP-TEMPLATE.md` (new) | Deep Jira setup: 6 statuses · Size/Risk fields · Only-Assignee condition · verify pointer |
| `templates/TRACKER-SETUP-TEMPLATE.md` (new) | Convention-tier stub for github/ado/linear/gitlab |
| `scripts/incept.sh` (modify) | `case "$BACKLOG"`: jira → JIRA-SETUP.md, hosted → TRACKER-SETUP.md, md unchanged |
| `conformance/tracker-contract.sh` (new) | Three-state Jira §6 verifier + `--selftest` |
| `docs/work-tracking/adapters.md` (modify) | Jira section → JIRA-SETUP + verifier pointer |
| `conformance/README.md` (modify) | index row |
| `.github/workflows/ci.yml` (modify, **human cp**) | `tracker-contract.sh --selftest` step |
| `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md` (modify) | 2.37.0; 9h → shipped |

---

## Task 1: The two setup templates

**Files:** Create `templates/JIRA-SETUP-TEMPLATE.md`, `templates/TRACKER-SETUP-TEMPLATE.md`

- [ ] **Step 1: `templates/JIRA-SETUP-TEMPLATE.md`** — write:

```markdown
# [Project Name] — Jira Setup (work-item contract)

> **Template.** `incept --backlog jira` wrote this. Follow it once to make a Jira project satisfy the kit's §6 work-item contract (`DEVELOPMENT-PROCESS.md` §6), then verify with `sh conformance/tracker-contract.sh`. Full mapping rationale: `docs/work-tracking/adapters.md` (Jira).

## 1. Workflow statuses (the six §6 states + Blocked)
Create/rename the project workflow statuses to exactly:
`Backlog → Ready → In Progress → In Review → Released → Done`, plus `Blocked` (a status or the built-in flag). The board columns mirror these; moving a card is a state change.

## 2. Required custom fields
- **Size** — a select field (e.g. `XS/S/M/L`). **Do NOT use Story Points as size** — the kit forbids estimation-as-forecast (`DEVELOPMENT-PROCESS.md` §1).
- **Risk** — a select or short-text field for risk/complexity.
- Map the rest 1:1: Summary→title · Description (or an Acceptance Criteria field)→intent + acceptance · Assignee→owner · the development panel auto-links branches/commits/PRs.

## 3. The atomic claim — "Only Assignee" transition condition (load-bearing)
This is what makes Jira a **server-enforced** single-owner claim — the strongest of the hosted set. Without it you are on the **convention tier** (last-writer-wins).
1. Project settings → **Workflows** → edit the active workflow.
2. Select the transition **into `In Progress`**.
3. Add a **Condition** → **"Only Assignee"** (or "Only the reporter/assignee can execute"), so only the current assignee can move a card to In Progress.
4. Publish the workflow.

Now claiming = assign to the agent, then transition; a second agent cannot perform the transition → no double-claim.

## 4. Verify
Set `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_TOKEN` (an Atlassian API token), then:
`sh conformance/tracker-contract.sh`
It verifies the six states + Size/Risk fields live, and reminds you to confirm the Only-Assignee condition (which basic REST cannot introspect — it is **attested**, not auto-verified).
```

- [ ] **Step 2: `templates/TRACKER-SETUP-TEMPLATE.md`** — write:

```markdown
# [Project Name] — [BACKEND] Setup (work-item contract)

> **Template.** `incept --backlog [BACKEND]` wrote this. `[BACKEND]` is a **convention-tier** backend: its claim is enforced by discipline (assign-when-empty + re-read), not by server config. Full mapping: `docs/work-tracking/adapters.md` (find the `[BACKEND]` section).

## Board = the six §6 states
Create board columns for `Backlog → Ready → In Progress → In Review → Released → Done` (+ `Blocked` as a column or label). Moving a card is a state change (`DEVELOPMENT-PROCESS.md` §6).

## Required fields
title · intent (why) · acceptance criteria · Size (not story points) · Risk · owner · links (spec / PR / milestone) — map these to the backend's native fields/labels per `adapters.md`.

## The claim (convention tier — be honest about it)
Assignment is last-writer-wins, so the claim is **narrowed, not closed**: claim only when the owner field is **empty**, set it, then **re-read after writing** to detect a lost race. Two agents that both read "empty" can both write; the re-read is how the loser finds out. For server-enforced claiming, use Jira (`JIRA-SETUP` via `incept --backlog jira`).
```

- [ ] **Step 3: Verify + commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.
  Run: `grep -niE "enterprise|public.media|bradley|atlassian.net/[a-z]" templates/JIRA-SETUP-TEMPLATE.md templates/TRACKER-SETUP-TEMPLATE.md || echo clean` → `clean` (no real Jira URL).
  ```bash
  git add templates/JIRA-SETUP-TEMPLATE.md templates/TRACKER-SETUP-TEMPLATE.md
  git commit -m "docs(9h): JIRA-SETUP + TRACKER-SETUP templates (hosted-tracker bootstrap guides)"
  ```

---

## Task 2: `incept.sh` — emit a setup artifact per backend

**Files:** Modify `scripts/incept.sh`

- [ ] **Step 1: Replace the backlog case block.** Find:
```sh
case "$BACKLOG" in
  md) [ -f BACKLOG.md ] || { cp templates/BACKLOG-TEMPLATE.md BACKLOG.md; sedi "s/\[Project Name\]/${ENAME}/g" BACKLOG.md; } ;;
  *)  echo "note: backlog backend '$BACKLOG' selected — declare it in CLAUDE.md §3 and map it via docs/work-tracking/adapters.md; no BACKLOG.md created." ;;
esac
```
Replace with:
```sh
case "$BACKLOG" in
  md) [ -f BACKLOG.md ] || { cp templates/BACKLOG-TEMPLATE.md BACKLOG.md; sedi "s/\[Project Name\]/${ENAME}/g" BACKLOG.md; } ;;
  jira)
    [ -f JIRA-SETUP.md ] || { cp templates/JIRA-SETUP-TEMPLATE.md JIRA-SETUP.md; sedi "s/\[Project Name\]/${ENAME}/g" JIRA-SETUP.md; }
    echo "note: backlog backend 'jira' selected — JIRA-SETUP.md written; configure it, then verify with 'sh conformance/tracker-contract.sh'. Declare the backend in CLAUDE.md §3." ;;
  *)
    [ -f TRACKER-SETUP.md ] || { cp templates/TRACKER-SETUP-TEMPLATE.md TRACKER-SETUP.md; sedi "s/\[Project Name\]/${ENAME}/g; s/\[BACKEND\]/${BACKLOG}/g" TRACKER-SETUP.md; }
    echo "note: backlog backend '$BACKLOG' selected (convention-tier) — TRACKER-SETUP.md written; map it via docs/work-tracking/adapters.md. Declare it in CLAUDE.md §3." ;;
esac
```

- [ ] **Step 2: Verify the three arms in a temp bootstrap.**
  ```sh
  for b in md jira github; do
    t=$(mktemp -d); git archive HEAD | tar -x -C "$t"
    ( cd "$t" && sh scripts/incept.sh --noninteractive --name DemoApp --intent-owner CI --stack typescript-node --backlog "$b" >/dev/null 2>&1 )
    case "$b" in
      md)   [ -f "$t/BACKLOG.md" ] && echo "md → BACKLOG.md ok" || echo "md FAIL" ;;
      jira) [ -f "$t/JIRA-SETUP.md" ] && grep -q "DemoApp" "$t/JIRA-SETUP.md" && echo "jira → JIRA-SETUP.md ok" || echo "jira FAIL" ;;
      github) [ -f "$t/TRACKER-SETUP.md" ] && grep -q "github" "$t/TRACKER-SETUP.md" && echo "github → TRACKER-SETUP.md ok" || echo "github FAIL" ;;
    esac
  done
  ```
  Expected: `md → BACKLOG.md ok`, `jira → JIRA-SETUP.md ok`, `github → TRACKER-SETUP.md ok`.
  Run: `dash -n scripts/incept.sh && echo "incept syntax OK"`.

- [ ] **Step 3: Commit.**
  ```bash
  git add scripts/incept.sh
  git commit -m "feat(incept): 9h — emit JIRA-SETUP.md (jira) / TRACKER-SETUP.md (hosted) at Inception"
  ```

---

## Task 3: `conformance/tracker-contract.sh`

**Files:** Create `conformance/tracker-contract.sh`

- [ ] **Step 1: Write the verifier** (three-state + grep-based core + `--selftest`):

```sh
#!/bin/sh
# tracker-contract.sh — verify a Jira instance satisfies the §6 work-item contract (Slice 9h).
# Three-state, like branch-protection.sh:
#   creds (JIRA_BASE_URL + JIRA_EMAIL + JIRA_TOKEN) -> live REST check -> PASS/FAIL
#   no creds                                         -> UNVERIFIED (exit 2; never a silent pass)
#   --selftest                                       -> run the contract logic on fixtures (CI-safe)
# The six §6 states + Size/Risk fields are checked live; the "Only Assignee" transition CONDITION is
# reported ATTESTED (basic REST cannot cheaply introspect workflow conditions — green != verified).
# Zero-dependency core (grep-based); curl only on the live path. POSIX sh; dash-clean.
# Exit: 0 = contract satisfied · 1 = a gap · 2 = UNVERIFIED / bad usage.
set -eu

# Six §6 states (+ Blocked) and the two required custom fields, as single shell words
# (spaces normalized to hyphens below so "In Progress" matches "In-Progress").
REQUIRED="Backlog Ready In-Progress In-Review Released Done Blocked Size Risk"

# check_blob <file>: every required name must appear (whitespace-insensitive); return 1 on any miss.
check_blob() {
  bf=$1; f=0
  if [ ! -f "$bf" ]; then echo "FAIL: missing $bf"; return 1; fi
  norm=$(tr -s '[:space:]' '-' < "$bf")
  for name in $REQUIRED; do
    if printf '%s' "$norm" | grep -q -- "$name"; then
      echo "PASS: contract names '$name'"
    else
      echo "FAIL: contract omits '$name'"; f=1
    fi
  done
  return $f
}

# live_check <base-url>: fetch statuses + fields, run check_blob; attest the transition condition.
live_check() {
  base=$1; tmp=$(mktemp)
  curl -fsS -u "$JIRA_EMAIL:$JIRA_TOKEN" "$base/rest/api/3/status" >> "$tmp" 2>/dev/null || {
    echo "FAIL: could not reach $base/rest/api/3/status"; rm -f "$tmp"; return 1; }
  curl -fsS -u "$JIRA_EMAIL:$JIRA_TOKEN" "$base/rest/api/3/field" >> "$tmp" 2>/dev/null || {
    echo "FAIL: could not reach $base/rest/api/3/field"; rm -f "$tmp"; return 1; }
  if check_blob "$tmp"; then rc=0; else rc=1; fi
  rm -f "$tmp"
  echo "ATTESTED (not auto-verified): confirm the In-Progress transition has the Only-Assignee condition — see JIRA-SETUP.md."
  return $rc
}

case "${1:-}" in
  --selftest)
    sfail=0
    okf=$(mktemp); printf 'Backlog Ready In Progress In Review Released Done Blocked Size Risk\n' > "$okf"
    if check_blob "$okf" >/dev/null 2>&1; then echo "PASS: selftest — conformant config passes"; else echo "FAIL: selftest — conformant wrongly rejected"; sfail=1; fi
    gapf=$(mktemp); printf 'Backlog Ready In Progress In Review Released Done Blocked Size\n' > "$gapf"   # missing Risk
    if check_blob "$gapf" >/dev/null 2>&1; then echo "FAIL: selftest — gap (missing Risk) not detected"; sfail=1; else echo "PASS: selftest — gap detected"; fi
    [ "$sfail" -eq 0 ] && { echo "OK: tracker-contract selftest"; exit 0; } || { echo "FAIL: tracker-contract selftest"; exit 1; }
    ;;
  "") : ;;
  *) echo "usage: tracker-contract.sh [--selftest]" >&2; exit 2 ;;
esac

if [ -n "${JIRA_BASE_URL:-}" ] && [ -n "${JIRA_EMAIL:-}" ] && [ -n "${JIRA_TOKEN:-}" ]; then
  echo "Jira contract check (live: $JIRA_BASE_URL):"
  if live_check "$JIRA_BASE_URL"; then
    echo "OK: Jira names the six §6 states + Size/Risk fields"
    exit 0
  else
    echo "FAIL: Jira does not satisfy the §6 contract (see above)"
    exit 1
  fi
else
  echo "UNVERIFIED: set JIRA_BASE_URL + JIRA_EMAIL + JIRA_TOKEN to verify a live Jira (exit 2, not a pass)."
  echo "  Configure per JIRA-SETUP.md; this is the kit's honest 'cannot run != pass' (conformance/README.md)."
  exit 2
fi
```

- [ ] **Step 2: Make executable + dash-check.**
  Run: `chmod +x conformance/tracker-contract.sh && dash -n conformance/tracker-contract.sh && echo "syntax OK"`.

- [ ] **Step 3: Run selftest + UNVERIFIED + bad usage.**
  Run: `sh conformance/tracker-contract.sh --selftest; echo "exit=$?"` → `PASS: … conformant config passes` + `PASS: … gap detected` + `OK: …`, `exit=0`.
  Run: `env -u JIRA_BASE_URL -u JIRA_EMAIL -u JIRA_TOKEN sh conformance/tracker-contract.sh; echo "exit=$?"` → `UNVERIFIED: …`, `exit=2`.
  Run: `sh conformance/tracker-contract.sh --bogus; echo "exit=$?"` → usage on stderr, `exit=2`.

- [ ] **Step 4: Commit.**
  ```bash
  git add conformance/tracker-contract.sh
  git commit -m "feat(conformance): 9h — tracker-contract.sh three-state Jira §6 verifier (+ --selftest)"
  ```

---

## Task 4: Doc pointers + conformance index

**Files:** Modify `docs/work-tracking/adapters.md`, `conformance/README.md`

- [ ] **Step 1: adapters.md Jira pointer.** Find the Jira Fit-notes line:
```
- **Fit notes** — strongest workflow modeling and enterprise governance; a real server-enforced claim *when the transition condition is configured*. Heavyweight; resist the Story-Points-as-size trap.
```
Append a new line immediately after it:
```
- **Bootstrap & verify** — `incept --backlog jira` writes a project-stamped `JIRA-SETUP.md` (statuses · Size/Risk fields · the Only-Assignee condition); `sh conformance/tracker-contract.sh` verifies the live instance (states/fields verified; the transition condition attested).
```

- [ ] **Step 2: conformance/README index row.** After the `branch-protection.sh` row, add:
```markdown
| `tracker-contract.sh` | script | Slice 9h — a Jira instance satisfies the §6 work-item contract (six states + Size/Risk fields, live); three-state (UNVERIFIED without creds); the Only-Assignee claim is attested | CI (`--selftest`) / adopter (live) |
```

- [ ] **Step 3: Verify + commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.
  ```bash
  git add docs/work-tracking/adapters.md conformance/README.md
  git commit -m "docs(9h): adapters.md Jira bootstrap+verify pointer; conformance index row"
  ```

---

## Task 5: Wire `--selftest` into CI (control-plane `cp`)

**Files:** Modify `.github/workflows/ci.yml` (build `/tmp` → human applies)

- [ ] **Step 1: Build candidate.** Read `.github/workflows/ci.yml`; Write a copy to `/tmp/ci.yml.9h` (Write tool — do NOT `cp`/`sed` the control-plane path) with TWO steps added to the `conformance` job immediately after the `Action-pinning self-test` step:
  ```yaml
      - name: Tracker-contract self-test (Jira §6 verifier logic)
        run: sh conformance/tracker-contract.sh --selftest
      - name: Tracker-contract UNVERIFIED without creds (honest non-pass)
        run: 'if sh conformance/tracker-contract.sh; then echo "ERROR: expected UNVERIFIED (exit 2), got a pass"; exit 1; else test $? -eq 2; fi'
  ```
  (The second step asserts the honest three-state behavior under GitHub Actions' `bash -e`: a cred-free run must exit 2 = UNVERIFIED. The `if/then/else` form is required — a bare `sh …; test $? -eq 2` would trip `set -e` and die before `test`; and the `then` branch makes a silent-pass regression — script exits 0 without creds — fail the step loudly.)

- [ ] **Step 2: Validate.**
  Run: `ruby -ryaml -e 'd=YAML.load_file("/tmp/ci.yml.9h"); puts d["jobs"].keys.join(",")'` → `conformance,bootstrap,docs-links`.
  Run: `diff .github/workflows/ci.yml /tmp/ci.yml.9h` → only the two added steps (4 `>` lines).

- [ ] **Step 3: Hand to Bradley (human `cp`).** Present exactly:
  ```bash
  cd ~/Development/agentic-sdlc-kit && cp /tmp/ci.yml.9h .github/workflows/ci.yml && git add .github/workflows/ci.yml && git commit -m "ci(kit): 9h — gate tracker-contract selftest + UNVERIFIED-without-creds honesty"
  ```
  Wait for confirmation.

---

## Task 6: Release (VERSION / CHANGELOG / roadmap)

**Files:** Modify `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md`

- [ ] **Step 1: `VERSION`** → replace `2.36.0` with `2.37.0`.

- [ ] **Step 2: Sync the badge.**
  Run: `sh conformance/badge-version.sh --fix` → `fixed: README badge set to v2.37.0`. Run: `sh conformance/badge-version.sh; echo exit=$?` → PASS exit 0.

- [ ] **Step 3: CHANGELOG entry** above `## [2.36.0]`:
  ```markdown
  ## [2.37.0] - 2026-06-10

  Hosted-tracker bootstrap (Slice 9h, Tier 2 of the "Honest Assurance & Adoption Reach" arc). Turns hosted-tracker adoption from prose into a concrete setup artifact plus a contract verifier. **MINOR** — templates + an incept arm + a three-state conformance check; no API client shipped.

  ### Added
  - **`templates/JIRA-SETUP-TEMPLATE.md`** — `incept --backlog jira` emits a project-stamped guide: the six §6 statuses, Size/Risk fields (not Story Points), and the step-by-step **Only-Assignee transition condition** (the server-enforced single-owner claim).
  - **`templates/TRACKER-SETUP-TEMPLATE.md`** — convention-tier stub for github/ado/linear/gitlab (board = the six states; claim = assign-when-empty + re-read).
  - **`conformance/tracker-contract.sh`** — three-state Jira §6 verifier: live REST checks the states + Size/Risk fields, **UNVERIFIED (exit 2)** without creds, `--selftest` proves the logic in CI. The Only-Assignee condition is **attested, not auto-verified** (honest about REST's limits).

  ### Changed
  - **`scripts/incept.sh`** now writes the matching setup artifact for the chosen backend (`md`→BACKLOG.md unchanged).
  - **`docs/work-tracking/adapters.md`** (Jira) points at the bootstrap + verifier.
  ```

- [ ] **Step 4: roadmap — mark 9h shipped.** In `docs/ROADMAP-SLICE9.md`, replace the `9h` row:
  ```markdown
  | **9h** ✅ | B | **Hosted-tracker bootstrap + contract check** (R8) — *shipped v2.37.0.* `incept --backlog jira` emits a concrete `JIRA-SETUP.md` (states, Size/Risk fields, the Only-Assignee transition); convention-tier `TRACKER-SETUP.md` stub for the rest; `tracker-contract.sh` three-state Jira §6 verifier (live states/fields; UNVERIFIED without creds; Only-Assignee attested). | P0¹ | MINOR ✅ |
  ```

- [ ] **Step 5: Verify + commit.**
  Run: `cat VERSION` → `2.37.0`. Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.
  ```bash
  git add VERSION README.md CHANGELOG.md docs/ROADMAP-SLICE9.md
  git commit -m "chore(release): 2.37.0 — hosted-tracker bootstrap (9h)"
  ```

---

## Task 7: Final verification + independent review + PR

- [ ] **Step 1: Full local sweep.**
  ```sh
  sh conformance/tracker-contract.sh --selftest >/dev/null && echo "selftest OK"
  env -u JIRA_BASE_URL -u JIRA_EMAIL -u JIRA_TOKEN sh conformance/tracker-contract.sh >/dev/null 2>&1; test $? -eq 2 && echo "UNVERIFIED honesty OK (exit 2)"
  dash -n conformance/tracker-contract.sh && dash -n scripts/incept.sh && echo "dash OK"
  sh conformance/backlog-adapters.sh >/dev/null && echo "backlog-adapters still green"
  sh conformance/verify.sh 2>&1 | tail -1
  sh conformance/check-links.sh 2>&1 | tail -1
  # incept arms produce the right artifact:
  t=$(mktemp -d); git archive HEAD | tar -x -C "$t"; ( cd "$t" && sh scripts/incept.sh --noninteractive --name DemoApp --intent-owner CI --stack typescript-node --backlog jira >/dev/null 2>&1 ); [ -f "$t/JIRA-SETUP.md" ] && echo "incept jira → JIRA-SETUP.md ok"
  grep -rniE "enterprise|public.media|bradley|[a-z0-9]+\.atlassian\.net" templates/JIRA-SETUP-TEMPLATE.md templates/TRACKER-SETUP-TEMPLATE.md conformance/tracker-contract.sh || echo "anon clean"
  ```
  Expected: all OK; anon clean.

- [ ] **Step 2: Independent review (builder ≠ sole reviewer).** Dispatch a reviewer on `git diff main...HEAD`: (a) `tracker-contract.sh` POSIX correctness — the `set -eu`-safe `if check_blob; then rc=0; else rc=1; fi` (no bare `cmd; rc=$?`), the `tr -s '[:space:]' '-'` whitespace-normalization so "In Progress" matches "In-Progress", three-state exit codes (0/1/2), and that `--selftest` genuinely catches the gap (missing Risk) — not a rubber-stamp; (b) the **UNVERIFIED path is honest** — cred-free exits 2, never a silent pass, matching `branch-protection.sh` and the CI step that asserts `test $? -eq 2`; (c) the Only-Assignee condition is **attested, not claimed as verified**; (d) `incept.sh` arms produce the right artifact per backend and leave the `md` bootstrap (CI) unchanged; `backlog-adapters.sh` still green; (e) the templates are usable and contain **no real Jira URL/org** (anonymized); (f) the live `curl` path uses the creds safely (basic auth over the provided base URL; no creds logged). Fix findings.

- [ ] **Step 3: Push + open PR.**
  ```bash
  git push -u origin feature/slice-9h-hosted-tracker
  gh pr create --base main --head feature/slice-9h-hosted-tracker \
    --title "Slice 9h — Hosted-Tracker Bootstrap (v2.37.0)" --body-file /tmp/pr-9h-body.md
  ```
  (Write `/tmp/pr-9h-body.md`: incept emits JIRA-SETUP/TRACKER-SETUP, the three-state verifier with UNVERIFIED honesty + attested transition condition, zero-dep selftest, one cp.)

- [ ] **Step 4: Confirm CI green; hand to Bradley to ratify (merge).** Agent never self-merges.

---

## Self-review (against the spec)
- **Spec coverage:** JIRA-SETUP + TRACKER-SETUP templates (T1) · incept arms (T2) · three-state tracker-contract.sh (T3) · adapters/README pointers (T4) · CI cp incl. UNVERIFIED-honesty assertion (T5) · MINOR 2.37.0 + roadmap (T6) · review + PR (T7). All spec components covered.
- **Placeholder scan:** templates + script are complete literal content; incept arm has exact find/replace; the `[Project Name]`/`[BACKEND]` tokens are intentional incept-stamp placeholders, not plan placeholders. No gaps.
- **Consistency:** the nine `REQUIRED` tokens in `tracker-contract.sh` (the six states + Blocked + Size + Risk) match the statuses/fields the `JIRA-SETUP-TEMPLATE.md` tells the adopter to create; the selftest's conformant fixture lists exactly those names; version 2.37.0 consistent across VERSION + badge + CHANGELOG + roadmap (T6); the UNVERIFIED exit-2 contract is asserted identically in T3, the T5 CI step, and the T7 sweep.
```
