# Plan — non-vacuity continuous gate (automatic mutation testing of conformance checks)

**Goal:** Ship `conformance/non-vacuity.sh` — a mutation-testing harness that neuters each targeted check's FAIL path, runs its `--selftest`, and flags any surviving mutant (a vacuous check) — wired weekly into drift-watch + doctor advisory, with its own self-teeth.

**Architecture:** A POSIX-sh harness with two modes: a **live sweep** (default; mutate each control-set check + run its selftest; exit 1 on any survivor) and a **`--selftest`** (self-teeth: a load-bearing fixture is KILLED, a vacuous fixture SURVIVES). Placement mirrors `meta-control-fresh.sh` (drift-watch job = the live sweep enforcement point; doctor = advisory; per-PR runs only `--selftest`).

**Tech stack:** POSIX sh (dash-clean), awk (region detection), sed (mutation), GitHub Actions.

**Global constraints (verbatim from the spec):**
- Mutate a **temp copy only** — never the real check file. Mutate the **check-logic region only** (exclude the selftest region) so the oracle's fixtures/assertions aren't corrupted.
- MVP operator = **neuter the FAIL path** (`return 1`/`exit 1`/`fail=1`/`st=1`/`rc=1` → success), syntax-preserving. One high-value operator; more are banked follow-on.
- **No silent skips:** a check whose selftest region can't be confidently detected, or that has no FAIL-path idiom, is reported **UNCOVERED** — never silently passed.
- The harness carries its **own non-vacuity** (self-teeth). Honest ceiling stated: proves the FAIL-path operator class is caught, not total non-vacuity.
- No change to any existing check's *logic*; no `guard-core.sh` change.

**Build model: AMBER.** New conformance harness + CI workflow + doctor + registry — all control-plane. Author under `scratchpad/non-vacuity/`, one idempotent `apply.py` (version finishing folded), clone-prove, hand to human.

---

## File map

| File | Change |
|---|---|
| `conformance/non-vacuity.sh` | **new** — mutation-testing harness (sweep + `--selftest` self-teeth) |
| `.github/workflows/drift-watch.yml` | + `non-vacuity` job (weekly live sweep — the enforcement point) |
| `scripts/doctor.sh` | + advisory block (mirror the `meta-control-fresh` block; never gates) |
| `conformance/claims.tsv` | + `non-vacuity-gate` row (verifier = `non-vacuity.sh --selftest`) |
| `conformance/claims-registry.sh` | + `non-vacuity-gate` in `REQUIRED_IDS` |
| `conformance/verify.sh` | + `check control non-vacuity sh conformance/non-vacuity.sh --selftest` |
| `VERSION` · `README.md` · `CHANGELOG.md` | version finishing 3.83.0 → 3.84.0 (folded into apply.py) |

All control-plane → one `apply.py`; serialize (single engineer). **Per-PR runs only `--selftest`** (the mechanism); the slow live sweep runs only in drift-watch.

---

## Task 1 — `conformance/non-vacuity.sh`: the harness

### 1a. Header + modes
```sh
#!/bin/sh
# non-vacuity.sh — mutation-testing gate for conformance checks. Neuters each targeted check's FAIL
# path (on a TEMP COPY), runs its --selftest, and flags a SURVIVING mutant = a vacuous check (a
# selftest that does not actually catch a broken check). Automates the kit's non-vacuity law as a
# standing gate (was a per-slice manual discipline). Author-INDEPENDENT: no per-check declared kills.
#   sh conformance/non-vacuity.sh            # live sweep over the verify.sh control set; exit 1 on a survivor
#   sh conformance/non-vacuity.sh --selftest # self-teeth (mechanism): load-bearing killed, vacuous survives
# Exit: 0 = all targeted checks load-bearing (mutants KILLED) or honestly UNCOVERED · 1 = a survivor
#   (vacuous check) or --selftest failure · 2 = usage. POSIX sh; dash-clean.
# HONEST CEILING: proves each selftest catches the FAIL-PATH operator class — NOT every conceivable
# weakness (equivalent-mutant limit). A strong automated floor, not a completeness proof.
set -eu
cd "$(dirname "$0")/.." 2>/dev/null || true
```

### 1b. The mutation operator (FAIL-path neuter) — `mutate_failpath <src> <dst> <region-guard-file>`
Apply, **only outside the selftest region** (see 1c), these syntax-preserving subs:
```sh
# sed program applied line-by-line to NON-selftest lines (selftest lines pass through verbatim):
#   s/\<return 1\>/return 0/g
#   s/\<exit 1\>/exit 0/g
#   s/\<\(fail\|st\|rc\)=1\>/\1=0/g
```
Implement via awk (1c) so region-exclusion + substitution happen in one pass. Count substitutions actually applied; **0 subs applied ⇒ UNCOVERED** (no FAIL-path idiom in the check region).

### 1c. Region detection (awk state machine) — exclude the selftest region from mutation
The dominant kit convention is a `selftest()` function + a trailing dispatch `case`. Detect and exclude the **`selftest()` function body** by brace-matching:
```awk
# awk -v applied=0 : emit each line; mutate only when NOT in the selftest region.
# in_st=0; depth=0
# On a line matching /^[[:space:]]*selftest[[:space:]]*\(\)[[:space:]]*\{?/  -> in_st=1; depth += (count of "{" - "}") on this line
# While in_st: depth += (#"{" - #"}"); when depth<=0 -> in_st=0 (region closed)
# Also treat an inline "--selftest" arm as in-region: from a line matching /--selftest\)/ until the next /;;/,
#   and from /if \[ .*--selftest.* \]/ until the matching /^fi/ .
# When in_st==1 -> print line verbatim (NO mutation).
# When in_st==0 -> apply the three FAIL-path gsubs; if any changed the line, applied++ .
# END: print "APPLIED=" applied  (to stderr or a sentinel the caller reads)
```
**Confidence guard:** if a `selftest()`/`--selftest` marker is present but the region never closes (brace imbalance — e.g. heredoc braces), OR no selftest region is found at all, the check is **UNCOVERED** (do not mutate — never risk corrupting the oracle). Emit the reason.

> Heredoc caveat (design-acknowledged): a `selftest()` body containing a heredoc with unbalanced `{` can miscount. The confidence guard catches imbalance → UNCOVERED, not a false result. Widening the detector (heredoc-aware) is a banked follow-on.

### 1d. Per-check verdict — `judge <check.sh>`
```sh
# 1. sanity: unmutated `sh <check> --selftest` MUST exit 0 (else the check is already broken -> report ERROR, exit 1 for the sweep).
# 2. build mutant temp copy via 1c; read APPLIED count.
#    APPLIED==0  -> print "UNCOVERED: <check> (no FAIL-path idiom in the check region)"; return 2 (uncovered).
# 3. run `sh <mutant> --selftest` (capture exit; set +e around it).
#    exit != 0   -> "KILLED: <check> (selftest caught the neutered FAIL path)"; return 0.
#    exit == 0   -> "SURVIVED: <check> — VACUOUS: its --selftest passes even when the check cannot FAIL"; return 1.
```
Temp copies via `mktemp` (left in place; 7e no-`rm` convention). `chmod +x` not needed (invoked via `sh`).

### 1e. The live sweep (default mode) — `sweep`
```sh
# target set = the conformance scripts referenced by `check control ... sh conformance/<x>.sh --selftest` in verify.sh.
#   extract: grep -E '^check control' conformance/verify.sh | grep -oE 'conformance/[a-z0-9-]+\.sh' | sort -u
#   filter to those whose file contains a --selftest mode.
# for each: judge; tally killed/survived/uncovered; print a one-line verdict each.
# print "non-vacuity sweep: N killed · M survived · K uncovered (of T targeted)".
# exit 1 if any SURVIVED; else exit 0 (uncovered is surfaced, not a failure — honest coverage).
```

### 1f. Dispatch
```sh
case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "")         sweep; exit $? ;;
  *) echo "usage: non-vacuity.sh [--selftest]" >&2; exit 2 ;;
esac
```

---

## Task 2 — `non-vacuity.sh --selftest` (self-teeth: the harness's own non-vacuity)

Build two fixture check-scripts in a temp dir, run `judge` on each, assert the verdicts:

```sh
selftest() {
  st=0; d=$(mktemp -d)

  # Fixture GOOD — genuinely load-bearing: check_x() FAILs (fail=1) when the token is absent, and the
  # selftest has a NEGATIVE fixture that expects that FAIL. Neutering fail=1 flips it -> KILLED.
  cat > "$d/good.sh" <<'EOF'
#!/bin/sh
set -eu
check_x() { fail=0; grep -q TOKEN "$1" || fail=1; [ "$fail" = 0 ] && echo PASS || { echo FAIL; return 1; }; }
selftest() {
  st=0; t=$(mktemp -d); printf 'TOKEN\n' > "$t/y"; : > "$t/n"
  check_x "$t/y" >/dev/null || { echo "st FAIL pos"; st=1; }
  check_x "$t/n" >/dev/null && { echo "st FAIL neg"; st=1; }   # NEGATIVE: absent token must FAIL
  [ "$st" = 0 ] && echo "good --selftest: OK" || { echo "good --selftest: FAIL" >&2; return 1; }
}
case "${1:-}" in --selftest) selftest; exit $? ;; *) check_x "$2"; exit $? ;; esac
EOF

  # Fixture VACUOUS — the selftest has ONLY a positive fixture (never asserts a FAIL). Neutering the
  # FAIL path changes nothing the selftest checks -> SURVIVES -> must be FLAGGED.
  cat > "$d/vac.sh" <<'EOF'
#!/bin/sh
set -eu
check_x() { fail=0; grep -q TOKEN "$1" || fail=1; [ "$fail" = 0 ] && echo PASS || { echo FAIL; return 1; }; }
selftest() {
  st=0; t=$(mktemp -d); printf 'TOKEN\n' > "$t/y"
  check_x "$t/y" >/dev/null || { echo "st FAIL pos"; st=1; }   # ONLY positive — vacuous
  [ "$st" = 0 ] && echo "vac --selftest: OK" || { echo "vac --selftest: FAIL" >&2; return 1; }
}
case "${1:-}" in --selftest) selftest; exit $? ;; *) check_x "$2"; exit $? ;; esac
EOF

  ( judge "$d/good.sh" ) >/dev/null 2>&1 && g=0 || g=$?   # expect KILLED -> return 0
  if [ "$g" = 0 ]; then echo "PASS: load-bearing check -> mutant KILLED"; else echo "FAIL: load-bearing check not killed (got $g)"; st=1; fi
  ( judge "$d/vac.sh" ) >/dev/null 2>&1 && v=0 || v=$?     # expect SURVIVED -> return 1
  if [ "$v" = 1 ]; then echo "PASS: vacuous check -> mutant SURVIVED (flagged)"; else echo "FAIL: vacuous check not flagged (got $v)"; st=1; fi

  # LOAD-BEARING NEGATIVE on the harness itself: if judge is mutated to always return KILLED (0),
  # the vacuous fixture would wrongly pass. Prove the distinction is real: good != vac verdict.
  [ "$g" = "$v" ] && { echo "FAIL: harness cannot distinguish load-bearing from vacuous"; st=1; }

  [ "$st" = 0 ] && echo "non-vacuity --selftest: OK" || { echo "non-vacuity --selftest: FAIL" >&2; return 1; }
  return "$st"
}
```
**Non-vacuity of the harness (build-time flip):** temporarily make `judge` always `return 0` → the vacuous-fixture assertion FAILs the selftest. Record the flip.

---

## Task 3 — wiring (mirror `meta-control-fresh`)

**3a. `.github/workflows/drift-watch.yml`** — add a new job after `meta-control-freshness` (separate job, cry-wolf hygiene):
```yaml
  non-vacuity:
    # The standing non-vacuity backstop: mutate each control-set check's FAIL path and assert its
    # --selftest catches it. A SURVIVOR (vacuous check) fails THIS job only. Per-PR CI runs only
    # `non-vacuity.sh --selftest` (mechanism); the live sweep runs here weekly.
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10  # v6.0.3
      - name: Non-vacuity sweep (a surviving mutant = a vacuous check — fix its selftest)
        run: sh conformance/non-vacuity.sh
```

**3b. `scripts/doctor.sh`** — add an advisory block after the `meta-control` block (never gates):
```sh
  # non-vacuity (advisory surfacing of the mutation-testing backstop; NEVER gates doctor)
  if [ -f "conformance/non-vacuity.sh" ]; then
    _nv_out=$(sh conformance/non-vacuity.sh 2>&1) || true
    printf '%s\n' "$_nv_out" | tail -1
  else
    echo "  non-vacuity: N/A (not present)"
  fi
```

**3c. Registry (3 coordinated edits):**
- `conformance/claims.tsv` append: `non-vacuity-gate␉every conformance check registered in verify.sh's control set is proven LOAD-BEARING: mutating its FAIL path makes its --selftest FAIL (a surviving mutant = a vacuous check); automated author-independent mutation testing, swept weekly in drift-watch; honest ceiling = the FAIL-path operator class, UNCOVERED checks surfaced not skipped␉sh conformance/non-vacuity.sh --selftest`
- `conformance/claims-registry.sh` line 17 `REQUIRED_IDS`: append ` non-vacuity-gate`.
- `conformance/verify.sh`: add after the `proportional-gate` line: `check control non-vacuity sh conformance/non-vacuity.sh --selftest`.

---

## Task 4 — version finishing + assemble apply.py + clone-prove

Idempotent `scratchpad/non-vacuity/apply.py` (Python file I/O; per-file buffer; anchor on stable substrings; VERSION 3.83.0→3.84.0 + README badge + CHANGELOG `## [3.84.0]`). **Clone-prove on a throwaway clone (real output):**
1. `shellcheck conformance/non-vacuity.sh` clean.
2. `sh conformance/non-vacuity.sh --selftest` → OK (load-bearing KILLED + vacuous SURVIVED-flagged) + the harness-flip recorded.
3. **Live-sweep dry run (the design's key proof):** `sh conformance/non-vacuity.sh` over the real control set → prints per-check KILLED/UNCOVERED, `exit 0`. Then **temporarily vacuify a real check** (e.g. delete its selftest's load-bearing negative fixture line in the clone), re-run the sweep → that check is **SURVIVED/flagged**, `exit 1`. Revert. Record both.
4. `actionlint .github/workflows/drift-watch.yml` clean (new job).
5. `sh scripts/doctor.sh` runs and surfaces the non-vacuity advisory line (never gates).
6. `sh conformance/claims-registry.sh` → `PASS: non-vacuity-gate`, coverage intact.
7. `sh conformance/verify.sh --require` → `RESULT: OK`, control count **+1** (39).
8. idempotent re-run = no-op; `git diff --stat` = the 7 files; `guard-core.sh` + existing check *logic* untouched.

---

## Dual review (builder ≠ reviewer)
- **`reviewer`** (correctness): the awk region detector (does it correctly exclude the selftest region? heredoc/brace edge → UNCOVERED not false result); the FAIL-path sed operators (syntax-preserving; `\<...\>` word-boundary correctness in the target awk/sed); KILLED/SURVIVED/UNCOVERED semantics; the sweep's target extraction from verify.sh; idempotent wiring; control count +1.
- **`security-reviewer`**: can the harness be gamed to hide a survivor (e.g., a check that self-detects mutation)? Does mutation ever touch the real tree (temp-copy only)? Is the UNCOVERED path a silent-skip risk (must be surfaced + not counted as pass-with-teeth)? Does the sweep execute only the kit's own checks (no untrusted input)?

## Ship (human; standard flow)
apply.py → separate `governance-close.py` (marker `3.84.0 GO` + meta-control-log row, panel #35) → commit (`git show --stat` all files) → push → PR → green conformance → `gh pr merge --squash --admin --delete-branch` → `git checkout main && git pull && sh scripts/release-tag.sh`.

## Spec coverage
AC1 → Task 1 (1b–1e). AC2 → Task 2. AC3 → Task 4 clone-prove step 3. AC4 → Task 3. AC5 → Task 4 steps 6–8.
