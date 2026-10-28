#!/bin/sh
# ci-selftest-coverage.sh — every selftest-capable kit check has its `--selftest` wired into CI.
# Closes the drift class where a conformance script ships a `--selftest` but is never referenced
# in .github/workflows/ci.yml, so a regression in that CHECKER'S OWN LOGIC would never be caught
# on push. This regression-locks the checker's logic; it does NOT by itself prove the checker's
# verdict runs against the kit repo — that is the check's own real-path CI step (or a Review/Manual
# row; see conformance/README.md). Scans the kit's own checks (conformance/*.sh, scripts/*.sh,
# hooks/pre-push); any that support `--selftest` MUST be referenced by basename in ci.yml.
# Fail-closed: lists every unwired check.
#
# Self-exclusion: this script excludes ITSELF from the scan. Its own presence in ci.yml is a
# one-time maintainer bootstrap (a meta-check can't non-circularly verify its own wiring); if it
# were not in ci.yml, nothing here would run on push anyway, so the point is moot. See
# conformance/README.md.
#   sh conformance/ci-selftest-coverage.sh [--selftest]
#   sh conformance/ci-selftest-coverage.sh --legs conformance-selftests    (SWAS-409 C29: the legs partition the capable set; see below)
# Exit: 0 = all wired · 1 = an unwired selftest-capable check · 2 = bad usage. POSIX sh; dash-clean.
set -eu
cd "$(dirname "$0")/.."

CI_FILE="${KIT_CI_FILE:-.github/workflows/ci.yml}"
SELF=ci-selftest-coverage.sh

# scan <ci_file> <file>...: for each file that contains "--selftest" (and is not SELF), assert its
# basename appears in <ci_file>. Prints WIRED/UNWIRED per file; returns 1 if any is unwired.
scan() {
  _ci=$1; shift
  _miss=0
  for f in "$@"; do
    [ -f "$f" ] || continue
    _base=$(basename "$f")
    [ "$_base" = "$SELF" ] && continue
    # "Ships a --selftest" means it HANDLES the flag, not merely mentions it: strip comments
    # first, so a doc comment like "(no --selftest)" in a sourced helper isn't miscounted.
    sed 's/#.*//' "$f" | grep -q -- '--selftest' || continue
    # "Wired" means the basename appears in an EXECUTION context, not merely mentioned: strip
    # comments and `name:` label lines first, so a step titled after a script (or a commented-out
    # step) is never mistaken for one that actually runs it.
    if sed 's/#.*//' "$_ci" 2>/dev/null | grep -vE '^[[:space:]]*-?[[:space:]]*name:' | grep -Fq "$_base"; then
      echo "WIRED:   $_base"
    else
      echo "UNWIRED: $_base"; _miss=1
    fi
  done
  return $_miss
}

run() {
  [ -f "$CI_FILE" ] || { echo "ci-selftest-coverage: CI file not found ($CI_FILE)"; return 1; }
  if scan "$CI_FILE" conformance/*.sh scripts/*.sh hooks/pre-push; then
    echo "ci-selftest-coverage: OK (every selftest-capable check is wired into CI; self-excluded)"
    return 0
  fi
  echo "ci-selftest-coverage: FAIL — the UNWIRED check(s) above ship a --selftest but are absent"
  echo "  from $CI_FILE. Add a CI step that runs each (e.g. 'sh conformance/<name>.sh --selftest')."
  return 1
}

# ══ C29 (SWAS-409, CI-SHAPING S4) — `--legs <join>`: the selftest legs PARTITION the capable set ═══════════
# `conformance-selftests` runs as legs conformance-selftests-1..n and a join of the old name. The join runs this mode on its OWN checkout (the
# commit every leg ran): R = (every selftest-capable check, the scan above) minus H must each be invoked in exactly one leg, as a token-bounded
# WHOLE LINE `(sh|bash) (conformance|scripts|hooks)/<base> --selftest`, optionally followed by plain argument words. A substring never counts
# (`guard-wired.sh` inside `roster-guard-wired.sh`, a script name in an X step's text); `echo conformance/x.sh`, a missing `--selftest`, a
# `--selftest-core`, and `… || true` on the line do not count either. MISSING / DUPLICATE / FOREIGN (outside R, or in H) / EMPTY leg each red
# and name their cause; no leg job at all is also a red (nothing to partition is not a pass).
# CEILING (stated): this proves each member is invoked once, whole-line, in a leg that the join also requires to have concluded `success`
# under the default shell's `-e` (ci-gates.sh --shard-join grades that). It does not prove the member's own selftest is meaningful (that
# is each check's own non-vacuity), and a member wrapped in a multi-line `if … fi` or a subshell inside a step still counts: review owns that.
#
# H (T0 of SWAS-409, recorded in docs/plans/2026-10-26-selftest-shards-409.md §2.6): the capable basenames with NO step in the selftests job.
# Adding a check homed outside that job is a deliberate control-plane edit here, with its reason.
#   (a) homed in a named other job, whose own `--selftest` runs there:
#       doctor-wired sparkwright-verbs (cf-doctor) · adopter-export-wired brownfield-walk (cf-export) · claim-gate-counts claims-registry
#       drift-watch-wired cost-governance-ready (cf-claims) · secret-scan-wired (secret-scan) · verify (cf-verify-enforced) · check-links
#       (docs-links) · loop-state (loop-state) · boundary-redteam (its full --selftest runs in the diff-gated boundary-redteam job; the
#       selftests job holds only the mutant-free --selftest-core, a non-counting step, BR15/BR16 in ci-gates.sh)
#   (b) bare or live only: no `--selftest` anywhere in ci.yml. A PRE-EXISTING GAP this slice names and does not fix (the conductor boards it):
#       discovery-complete onboarding-complete shim-coverage template-detectors-aligned ci-classify-changes inception-done backlog-presence
#       repo-ownership
#   (c) this script itself (the scan excludes SELF).
LEGS_H="doctor-wired.sh sparkwright-verbs.sh adopter-export-wired.sh brownfield-walk.sh claim-gate-counts.sh claims-registry.sh drift-watch-wired.sh cost-governance-ready.sh secret-scan-wired.sh verify.sh check-links.sh loop-state.sh boundary-redteam.sh discovery-complete.sh onboarding-complete.sh shim-coverage.sh template-detectors-aligned.sh ci-classify-changes.sh inception-done.sh backlog-presence.sh repo-ownership.sh"
# X: steps excluded WHOLE by step-name prefix; nothing inside their run text counts. Each with its declared argv (T0, plan §2.6):
#   Sandbox enforcement (guard-wired.sh --sandbox-enforce) · SAST parse coverage (inline; its text names tracker-jira.sh, tracker-cred.sh,
#   review-lane.sh, scripts/promotion-verify.sh) · kit-guard CLI self-test (scripts/kit-guard --selftest, not a .sh) · Stack- and
#   Deploy-decision-integrity self-test (exec wrappers of decision-integrity.sh, not capable) · Boundary red-team core self-test
#   (boundary-redteam.sh --selftest-core, non-counting).
LEGS_X="Sandbox enforcement|SAST parse coverage|kit-guard CLI self-test|Stack-decision-integrity self-test|Deploy-decision-integrity self-test|Boundary red-team core self-test"

# legs_scan <ci_file> <join> <x-prefixes> -> records: `L <leg>` per leg job, `I <leg> <base>` per counted invocation, `X <leg>` per excluded step.
# Line-based awk at the indents the kit's workflows use (jobs at 2, steps at 6, step keys at 8): not a YAML parser, the same ceiling as ci-gates.sh.
legs_scan() {
  awk -v join="$2" -v xs="$3" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    function isx(n,   i, k, xp) { k = split(xs, xp, "|"); for (i = 1; i <= k; i++) if (xp[i] != "" && index(n, xp[i]) == 1) return 1; return 0 }
    function addinv(l,   w, b) {
      l = trim(l)
      if (l !~ re) return
      split(l, w, " "); b = w[2]; sub(/^[^\/]*\//, "", b)
      buf = buf " " b
    }
    function flush() {
      if (instep && leg != "") {
        if (isx(sname)) print "X " leg
        else { n = split(buf, bs, " "); for (i = 1; i <= n; i++) print "I " leg " " bs[i] }
      }
      instep = 0; sname = ""; buf = ""; inb = 0
    }
    BEGIN { re = "^(sh|bash) (conformance|scripts|hooks)/[A-Za-z0-9._-]+ --selftest( [A-Za-z0-9._/=: -]*)?$"; leg = "" }
    /^[^ \t#]/ { flush(); leg = ""; next }
    /^  [A-Za-z0-9_-]+:([ \t]|$)/ {
      flush(); j = $1; sub(/:$/, "", j); leg = ""
      if (j ~ ("^" join "-[0-9]+$")) { leg = j; print "L " leg }
      next
    }
    leg == "" { next }
    { t = trim($0); if (t == "" || substr(t, 1, 1) == "#") next }
    /^      - / { flush(); instep = 1; line = "        " substr($0, 9) }
    !/^      - / { line = $0 }
    {
      if (inb) {
        if (match(line, /[^ ]/) - 1 > 8) { addinv(line); next }
        inb = 0
      }
      if (line ~ /^        name:/) { v = trim(substr(line, 14)); if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2); sname = v; next }
      if (line ~ /^        run:/) {
        v = trim(substr(line, 13))
        if (v ~ /^[|>][-+]?$/) { inb = 1; next }
        addinv(v)
      }
    }
    END { flush() }' "$1"
}

# legs_check <ci_file> <join> <root> <h-list> <x-prefixes> -> rc 0 when the legs partition R; each break is named. Arguments, never the environment.
legs_check() {
  _lc_ci=$1; _lc_join=$2; _lc_root=$3; _lc_h=$4; _lc_x=$5
  [ -f "$_lc_ci" ] || { echo "ci-selftest-coverage --legs: FAIL — CI file not found ($_lc_ci)"; return 1; }
  _lc_rec=$(legs_scan "$_lc_ci" "$_lc_join" "$_lc_x")
  if ! printf '%s\n' "$_lc_rec" | grep -q '^L '; then
    echo "ci-selftest-coverage --legs: FAIL — no leg jobs named $_lc_join-<n> in $_lc_ci (fail-closed: nothing to partition is not a pass)"; return 1
  fi
  _lc_cap=$( (cd "$_lc_root" && scan "$_lc_ci" conformance/*.sh scripts/*.sh hooks/pre-push 2>/dev/null) | sed -n 's/^\(UN\)\{0,1\}WIRED: *//p' | tr '\n' ' ' || :)
  if [ -z "${_lc_cap# }" ]; then
    echo "ci-selftest-coverage --legs: FAIL — the scan found no selftest-capable check under $_lc_root (a broken scan is not a pass)"; return 1
  fi
  _lc_bad=$(printf '%s\n' "$_lc_rec" | awk -v cap="$_lc_cap" -v hl="$_lc_h" '
    BEGIN { n = split(cap, c, " "); for (i = 1; i <= n; i++) if (c[i] != "") iscap[c[i]] = 1
            n = split(hl, hh, " "); for (i = 1; i <= n; i++) inh[hh[i]] = 1 }
    $1 == "L" { nm[$2] = 0 }
    $1 == "I" {
      nm[$2]++; occ[$3]++; where[$3] = where[$3] " " $2
      if (inh[$3]) print "FOREIGN " $3 " in " $2 " (an H member: its selftest runs in another job)"
      else if (!iscap[$3]) print "FOREIGN " $3 " in " $2 " (not a selftest-capable check of this tree)"
    }
    END {
      for (b in iscap) if (!inh[b] && occ[b] == 0) print "MISSING " b " (a selftest-capable check with no whole-line --selftest invocation in any leg)"
      for (b in occ) if (occ[b] > 1 && iscap[b] && !inh[b]) print "DUPLICATE " b " (invoked " occ[b] " times, in:" where[b] ")"
      for (l in nm) if (nm[l] == 0) print "EMPTY leg " l " (no member invocation)"
      print "END-OF-GRADE"
    }') || { echo "ci-selftest-coverage --legs: FAIL — the grading awk aborted (a grader that did not finish is not a pass)"; return 1; }
  case "$_lc_bad" in
    *END-OF-GRADE) : ;;
    *) echo "ci-selftest-coverage --legs: FAIL — the grading awk did not reach its end marker (a grader that did not finish is not a pass)"; return 1 ;;
  esac
  _lc_bad=$(printf '%s\n' "$_lc_bad" | grep -v '^END-OF-GRADE$' | sort || :)
  if [ -n "$_lc_bad" ]; then
    printf '%s\n' "$_lc_bad"
    echo "ci-selftest-coverage --legs: FAIL — the legs of $_lc_join do not partition the selftest-capable set (each break is named above)"
    return 1
  fi
  _lc_nl=$(printf '%s\n' "$_lc_rec" | grep -c '^L ')
  _lc_ni=$(printf '%s\n' "$_lc_rec" | grep -c '^I ')
  echo "ci-selftest-coverage --legs: OK ($_lc_ni invocations in $_lc_nl legs of $_lc_join partition the selftest-capable set minus H)"
  return 0
}

legs_run() {  # <join> -> only the selftests join has an R/H/X
  [ "$1" = conformance-selftests ] || { echo "usage: ci-selftest-coverage.sh --legs conformance-selftests" >&2; return 2; }
  legs_check "$CI_FILE" "$1" . "$LEGS_H" "$LEGS_X"
}

selftest() {
  sfail=0
  d=$(mktemp -d)
  printf '#!/bin/sh\necho run --selftest\n' > "$d/foo-check.sh"
  printf '#!/bin/sh\necho run --selftest\n' > "$d/bar-check.sh"
  printf '#!/bin/sh\necho no flag here\n'    > "$d/plain.sh"
  # dirty: foo wired, bar NOT -> must FAIL naming bar
  printf 'jobs:\n  x:\n    steps:\n      - run: sh conformance/foo-check.sh --selftest\n' > "$d/ci-bad.yml"
  if scan "$d/ci-bad.yml" "$d/foo-check.sh" "$d/bar-check.sh" >/dev/null 2>&1; then
    echo "FAIL: selftest — unwired check not detected"; sfail=1
  else
    echo "PASS: selftest — unwired check detected"
  fi
  # clean: both wired -> must PASS
  printf 'jobs:\n  x:\n    steps:\n      - run: sh foo-check.sh\n      - run: sh bar-check.sh\n' > "$d/ci-ok.yml"
  if scan "$d/ci-ok.yml" "$d/foo-check.sh" "$d/bar-check.sh" >/dev/null 2>&1; then
    echo "PASS: selftest — all-wired passes"
  else
    echo "FAIL: selftest — all-wired wrongly failed"; sfail=1
  fi
  # a script WITHOUT --selftest is ignored (not required in ci)
  if scan "$d/ci-ok.yml" "$d/plain.sh" >/dev/null 2>&1; then
    echo "PASS: selftest — non-selftest script ignored"
  else
    echo "FAIL: selftest — non-selftest script wrongly required"; sfail=1
  fi
  legs_cells
  echo "ci-selftest-coverage --selftest: fixtures left in $d"
  [ "$sfail" -eq 0 ] && { echo "OK: ci-selftest-coverage selftest"; exit 0; } || { echo "FAIL: ci-selftest-coverage selftest"; exit 1; }
}

# ── C29 cells (SWAS-409): the --legs partition, graded against fixture workflows ─────────────────────────
# Fixture shape: a root with capable scripts (a-d, g, roster-g, v), one non-capable script (x), and a workflow of leg jobs
# conformance-selftests-<n> built by _lg_leg. H (the capable names with no step in the job) and X (the step-name prefixes excluded whole)
# are passed as ARGUMENTS, never read from the environment: an env-redirectable list on a control-plane check is the vacuity this
# project forbids. Every negative must red AND name its cause; _lg_case judges the rc and the needle together.
_lg_step() { printf '      - name: %s self-test\n        run: sh conformance/%s.sh --selftest\n' "$1" "$1"; }
_lg_leg() {  # <n> <step-token>... : a leg job with the checkout prologue; a RAW:<printf-text> token is written as given
  printf '  conformance-selftests-%s:\n    needs: changes\n    steps:\n      - uses: actions/checkout@x\n' "$1"; shift
  for _lg_t in "$@"; do
    case "$_lg_t" in
      RAW:*) printf '%b' "${_lg_t#RAW:}" ;;
      *) _lg_step "$_lg_t" ;;
    esac
  done
}
_lg_ci() {  # <file> <leg-text>... : the workflow with a changes job, the given legs, and the join
  _lg_out=$1; shift
  printf 'jobs:\n  changes:\n    runs-on: x\n' > "$_lg_out"
  for _lg_p in "$@"; do printf '%s\n' "$_lg_p" >> "$_lg_out"; done
  printf '  conformance-selftests:\n    needs: [changes]\n    steps:\n      - name: join\n        run: echo join\n' >> "$_lg_out"
}
_lg_case() {  # <id> <desc> <want-rc> <needle|-> <ci> -> PASS when legs_check on the fixture root gives <want-rc> and prints <needle>
  if _lg_o=$(legs_check "$5" conformance-selftests "$_lg_root" "d.sh" "kit-guard CLI self-test" 2>&1); then _lg_rc=0; else _lg_rc=$?; fi
  _lg_ok=1
  [ "$_lg_rc" = "$3" ] || _lg_ok=0
  if [ "$4" != "-" ]; then case "$_lg_o" in *"$4"*) : ;; *) _lg_ok=0 ;; esac; fi
  if [ "$_lg_ok" = 1 ]; then echo "PASS: selftest — $1 $2"
  else echo "FAIL: selftest — $1 $2 (rc=$_lg_rc want $3; needle '$4'; out='$_lg_o')"; sfail=1; fi
}
legs_cells() {
  _lg_root="$d/lg"; mkdir -p "$_lg_root/conformance" "$_lg_root/scripts"
  for _lg_n in a b c d g roster-g v; do printf '#!/bin/sh\necho run --selftest\n' > "$_lg_root/conformance/$_lg_n.sh"; done
  printf '#!/bin/sh\necho plain\n' > "$_lg_root/conformance/x.sh"
  _lg_f="$d/lg-ci.yml"
  _lg_ci "$_lg_f" "$(_lg_leg 1 a b)" "$(_lg_leg 2 c g roster-g v)"
  _lg_case LG1 "a,b in leg 1 and c,g,roster-g,v in leg 2 (d is in H) -> OK" 0 "OK" "$_lg_f"
  _lg_ci "$_lg_f" "$(_lg_leg 1 a b)" "$(_lg_leg 2 g roster-g v)"
  _lg_case LG2 "c absent -> MISSING c.sh" 1 "MISSING c.sh" "$_lg_f"
  _lg_ci "$_lg_f" "$(_lg_leg 1 a b c g roster-g v)" "$(_lg_leg 2 a)"
  _lg_case LG3 "a in two legs -> DUPLICATE a.sh" 1 "DUPLICATE a.sh" "$_lg_f"
  _lg_ci "$_lg_f" "$(_lg_leg 1 a b x)" "$(_lg_leg 2 c g roster-g v)"
  _lg_case LG4 "a live non-capable script x in a leg -> FOREIGN x.sh" 1 "FOREIGN x.sh" "$_lg_f"
  _lg_ci "$_lg_f" "$(_lg_leg 1 a b d)" "$(_lg_leg 2 c g roster-g v)"
  _lg_case LG5 "an H member d in a leg -> FOREIGN d.sh" 1 "FOREIGN d.sh" "$_lg_f"
  _lg_ci "$_lg_f" "$(_lg_leg 1 a b c g roster-g v)" "$(_lg_leg 2)"
  _lg_case LG6 "a leg holding only the prologue -> EMPTY leg conformance-selftests-2" 1 "EMPTY leg conformance-selftests-2" "$_lg_f"
  _lg_ci "$_lg_f" "$(_lg_leg 1 a b g roster-g v 'RAW:      - name: c.sh self-test\n        run: echo nothing\n')"
  _lg_case LG7 "a basename only on a name: line -> still MISSING c.sh" 1 "MISSING c.sh" "$_lg_f"
  _lg_ci "$_lg_f" "$(_lg_leg 1 a b g roster-g v 'RAW:      - name: c\n        run: echo conformance/c.sh\n')"
  _lg_case LG8 "echo conformance/c.sh -> MISSING c.sh" 1 "MISSING c.sh" "$_lg_f"
  _lg_ci "$_lg_f" "$(_lg_leg 1 a b g roster-g v 'RAW:      - name: c\n        run: sh conformance/c.sh\n')"
  _lg_case LG9 "sh conformance/c.sh without --selftest -> MISSING c.sh" 1 "MISSING c.sh" "$_lg_f"
  _lg_ci "$_lg_f" "$(_lg_leg 1 a b g roster-g v 'RAW:      - name: c\n        run: sh conformance/c.sh --selftest || true\n')"
  _lg_case LG10 "sh conformance/c.sh --selftest || true -> MISSING c.sh" 1 "MISSING c.sh" "$_lg_f"
  _lg_ci "$_lg_f" "$(_lg_leg 1 a b c roster-g v)" "$(_lg_leg 2 g)"
  _lg_case LG11 "the substring pair: g.sh in leg 2 and roster-g.sh in leg 1 -> OK" 0 "OK" "$_lg_f"
  _lg_ci "$_lg_f" "$(_lg_leg 1 a b c roster-g v)" "$(_lg_leg 2)"
  _lg_case LG12 "the g.sh step deleted (roster-g.sh remains) -> MISSING g.sh, not hidden by the substring" 1 "MISSING g.sh" "$_lg_f"
  _lg_ci "$_lg_f" "$(_lg_leg 1 a b c g roster-g 'RAW:      - name: kit-guard CLI self-test (x)\n        run: sh scripts/promotion-v.sh --selftest\n')"
  _lg_case LG13 "an X step naming promotion-v.sh: v.sh is not counted from it -> MISSING v.sh, and no FOREIGN" 1 "MISSING v.sh" "$_lg_f"
  case "$_lg_o" in *FOREIGN*) echo "FAIL: selftest — LG13b an X step's text was graded as a foreign member: $_lg_o"; sfail=1 ;; *) echo "PASS: selftest — LG13b an X step's text is not graded as a foreign member" ;; esac
  _lg_ci "$_lg_f" "$(_lg_leg 1 a b)" "$(_lg_leg 2 g roster-g v 'RAW:      - name: two\n        run: |\n          sh conformance/c.sh --selftest\n          sh conformance/d-not-listed.sh --selftest\n')"
  _lg_case LG14 "two invocations in one step are both graded (c counted; d-not-listed.sh FOREIGN)" 1 "FOREIGN d-not-listed.sh" "$_lg_f"
  case "$_lg_o" in *"MISSING c.sh"*) echo "FAIL: selftest — LG14b the first invocation of a two-line step was not counted: $_lg_o"; sfail=1 ;; *) echo "PASS: selftest — LG14b the first invocation of a two-line step is counted" ;; esac
  printf 'jobs:\n  changes:\n    runs-on: x\n  conformance-selftests:\n    needs: [changes]\n    steps:\n      - run: echo join\n' > "$_lg_f"
  _lg_case LG15 "no leg jobs at all -> fail-closed" 1 "no leg jobs" "$_lg_f"
  if [ -f docs/ROADMAP-KIT.md ] || [ -f .github/workflows/golden-path.yml ]; then
    if legs_run conformance-selftests >/dev/null 2>&1; then echo "PASS: selftest — LG16 the live ci.yml's selftest legs partition the capable set (real tree)"
    else echo "FAIL: selftest — LG16 the live ci.yml's selftest legs do not partition the capable set: $(legs_run conformance-selftests 2>&1 | head -n 5 | tr '\n' ' ')"; sfail=1; fi
  else echo "SKIP: selftest — LG16 (not a kit tree)"; fi
  # Mutants of THIS script (LG-M1..M7): each is a sed-edited COPY under $d/mut and must make its named cell FAIL. The copy sits in a tree with no kit
  # marker, so it SKIPs this block and LG16 (it cannot nest copies of its own). A mutant equal to the original proves nothing (cmp guard).
  if [ -f docs/ROADMAP-KIT.md ] || [ -f .github/workflows/golden-path.yml ]; then
    # the positive control (R-M2): an UNMUTATED copy at the mutants' own path must pass its selftest, or "the copy reds" proves nothing (a copy that cannot run reds too)
    mkdir -p "$d/mut/conformance"; cp "$0" "$d/mut/conformance/ci-selftest-coverage.sh"
    if _lm_c=$(sh "$d/mut/conformance/ci-selftest-coverage.sh" --selftest 2>&1) && case "$_lm_c" in *"OK: ci-selftest-coverage selftest"*) : ;; *) false ;; esac; then
      echo "PASS: selftest — LG-M0 the unmutated copy at the mutants' path passes its own selftest (so a mutant that reds is the mutation)"
    else echo "FAIL: selftest — LG-M0 the unmutated copy does not pass its selftest: $(printf '%s' "$_lm_c" | tail -n 3 | tr '\n' ' ')"; sfail=1; fi
    _lg_mut LG-M1 "the MISSING test dropped" LG2 's/occ\[b\] == 0/occ[b] == -1/'
    _lg_mut LG-M2 "the DUPLICATE test dropped" LG3 's/occ\[b\] > 1/occ[b] > 999/'
    _lg_mut LG-M3 "prologue-only legs counted as members" LG6 's/\$1 == "L" { nm\[\$2\] = 0 }/$1 == "L" { nm[$2] = 1 }/'
    _lg_mut LG-M4 "name: lines counted as invocations" LG7 's/sname = v; next }/sname = v; split(v, nw, " "); buf = buf " " nw[1]; next }/'
    _lg_mut LG-M5 "an unanchored substring match of the basename" LG12 's/nm\[\$2\]++; occ\[\$3\]++;/nm[$2]++; occ[$3]++; for (b2 in iscap) if (b2 != $3 \&\& index($3, b2)) occ[b2]++;/'
    _lg_mut LG-M6 "the --selftest shape requirement dropped" LG9 's#^    BEGIN { re = ".*"; leg = "" }$#    BEGIN { re = "^(sh|bash) (conformance|scripts|hooks)/[A-Za-z0-9._-]+( .*)?$"; leg = "" }#'
    _lg_mut LG-M7 "names inside X steps counted" LG13b 's/if (xp\[i\] != "" \&\& index(n, xp\[i\]) == 1) return 1/if (0) return 1/'
  else echo "SKIP: selftest — LG-M1..M7 (not a kit tree)"; fi
}
_lg_mut() {  # <id> <desc> <cell-that-must-fail> <sed-expr>
  mkdir -p "$d/mut/conformance"
  sed "$4" "$0" > "$d/mut/conformance/ci-selftest-coverage.sh"
  if cmp -s "$0" "$d/mut/conformance/ci-selftest-coverage.sh"; then
    echo "FAIL: selftest — $1 the mutant equals the original (nothing to mutate; the line is not pinned)"; sfail=1; return 0
  fi
  if _lm_o=$(sh "$d/mut/conformance/ci-selftest-coverage.sh" --selftest 2>&1); then _lm_rc=0; else _lm_rc=$?; fi
  case "$_lm_o" in
    *"FAIL: selftest — $3 "*) [ "$_lm_rc" != 0 ] && { echo "PASS: selftest — $1 $2 -> the copy reds, cell $3 FAILs"; return 0; } ;;
  esac
  echo "FAIL: selftest — $1 $2 was NOT caught by cell $3 (rc=$_lm_rc)"; sfail=1
}

case "${1:-}" in
  --selftest) selftest ;;
  --legs)
    [ "$#" -eq 2 ] || { echo "usage: ci-selftest-coverage.sh --legs conformance-selftests" >&2; exit 2; }
    # Same kit-repo detector as the bare mode below: an adopter's tree has no kit ci.yml legs to partition.
    if [ ! -f "docs/ROADMAP-KIT.md" ] && [ ! -f ".github/workflows/golden-path.yml" ]; then
      echo "ci-selftest-coverage --legs: N/A — kit-self check (not applicable outside the kit repo)"; exit 0
    fi
    legs_run "$2" ;;
  "")
    # Kit-repo detector (C1 / R3): this check only has meaning inside the kit's own repo.
    # OR-of-markers is fail-closed: golden-path.yml is control-plane + export-ignored (un-spoofable);
    # deleting only the unprotected ROADMAP-KIT.md marker cannot make the kit skip its own checks.
    # N/A-skip only when BOTH are absent (true adopter tree). When either is present, run full.
    if [ ! -f "docs/ROADMAP-KIT.md" ] && [ ! -f ".github/workflows/golden-path.yml" ]; then
      echo "ci-selftest-coverage: N/A — kit-self check (not applicable outside the kit repo)"; exit 0
    fi
    run ;;
  *)          echo "usage: ci-selftest-coverage.sh [--selftest]" >&2; exit 2 ;;
esac
exit $?
