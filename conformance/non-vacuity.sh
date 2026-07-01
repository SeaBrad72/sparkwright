#!/bin/sh
# non-vacuity.sh — mutation-testing gate for conformance checks. Neuters each targeted check's FAIL
# path (on a TEMP COPY written NEXT TO the check so its $0-relative sourcing still resolves), runs its
# --selftest, and flags a SURVIVING mutant = a vacuous check (a selftest that does not actually catch a
# broken check). Automates the kit's non-vacuity law as a standing gate (was a per-slice manual
# discipline). Author-INDEPENDENT: no per-check declared kills.
#   sh conformance/non-vacuity.sh            # live sweep over the verify.sh control set; exit 1 on a survivor
#   sh conformance/non-vacuity.sh --selftest # self-teeth (mechanism): load-bearing killed, vacuous survives
# Exit: 0 = all targeted checks load-bearing (mutants KILLED) or honestly UNCOVERED · 1 = a survivor
#   (vacuous check) or --selftest failure · 2 = usage. POSIX sh; dash-clean.
#
# SAFETY INVARIANT (fail-safe): only ever report KILLED when CERTAIN. Route EVERY uncertainty to a
# loud, enumerated UNCOVERED (with a reason). Fail the sweep only on a CERTAIN SURVIVED. So the tally
# is deliberately conservative — fewer KILLED, more UNCOVERED — because a false KILL would HIDE a
# vacuous check (the one direction that must never happen).
#
# HONEST CEILING (heuristic disclosures):
#   - Region delimitation is HEURISTIC: the selftest/oracle region is everything from the FIRST
#     selftest marker to EOF; only lines strictly BEFORE it are mutated. A post-build diff VOIDs the
#     mutant to UNCOVERED (region-ambiguous) if any change landed at/after the marker.
#   - Run context: a mutant that cannot even start unmutated at its run location (non-sibling-safe /
#     $0-relative sourcing that does not resolve) is UNCOVERED (context/run-location), never KILLED.
#   - Some checks are STRUCTURALLY un-mutation-testable IN PLACE: a SELF-SCANNING check (e.g.
#     mode-enforcement-blind.sh greps its own conformance/ tree and would see the harness's sibling
#     temp copy) is caught by the run-location guard and reported UNCOVERED — that is a structural
#     property of the check, NOT an idiom gap to chase.
#   - Equivalent mutants (a survivor whose only neutered idiom is bare control-flow return/exit 1 that
#     a passing selftest may not observe) are SURFACED for manual review as UNCOVERED (CTL-only), not
#     killed and not failed.
#   Proves each selftest catches the FAIL-PATH operator class — NOT every conceivable weakness. A
#   strong automated floor, not a completeness proof.
set -eu
cd "$(dirname "$0")/.." 2>/dev/null || true

# ── first_marker <src> : print the 1-based line number where the selftest ORACLE region begins — the
#    earliest of a  ^selftest()  function definition OR an  if [ ... --selftest ... ]  block opener
#    (the two kit oracle conventions that carry fixtures + assertions). A bare  --selftest)  case arm is
#    used ONLY as a fallback when neither exists (it is usually an arg-parse mode-setter or the tail
#    dispatch, not the oracle body). Prints 0 if no marker at all. LC_ALL=C: byte-safe (some checks
#    carry multibyte chars in comments; awk char scanning must not choke on them).
first_marker() {
  LC_ALL=C awk '
    /^[[:space:]]*selftest[[:space:]]*\(\)/ { if (fn==0) fn=NR }
    /^[[:space:]]*if[[:space:]].*--selftest/ { if (ifb==0) ifb=NR }
    /--selftest\)/ { if (arm==0) arm=NR }
    END {
      m=0
      if (fn>0)  m=fn
      if (ifb>0 && (m==0 || ifb<m)) m=ifb
      if (m==0 && arm>0) m=arm     # fallback: no fn / if-block, only a case arm
      print m
    }
  ' "$1"
}

# ── mutate <src> <dst> <metafile> <mark> : write a FAIL-path-neutered copy of <src> to <dst>, mutating
#    ONLY lines strictly BEFORE <mark> (the oracle region begins at <mark> and runs to EOF, emitted
#    VERBATIM). No brace/fi counting — so a stray `fi`/`}` in a string or comment can never corrupt the
#    region boundary (the false-KILL vector the reviewer found). Writes the sentinel
#    "APPLIED=<n>;ACC=<a>;CTL=<c>;MARK=<mark>" to <metafile>. (If <mark> is 0 the caller has already
#    ruled the check UNCOVERED=no-selftest-region and does not call mutate.)
# Accumulator idiom = ANY  <var>=1  at a word boundary (records a verdict VALUE the selftest reads
# back). Control-flow idiom = bare  return 1 / exit 1  (reachable only on an error path). Both are
# neutered to their success form; only accumulator survivors are true vacuities.
mutate() {
  LC_ALL=C awk -v mark="$4" '
    function is_wchar(ch) { return (ch ~ /[A-Za-z0-9_]/) }
    # neuter(line): at word boundaries, flip  return 1->return 0, exit 1->exit 0 (CONTROL), and any
    # <var>=1 -> <var>=0 (ACCUMULATOR). Sets NCH/NACC/NCTL; returns the new line.
    function neuter(line,   n, i, out, matched, before, after, lb, rb, j, name) {
      NCH = 0; NACC = 0; NCTL = 0; out = ""; n = length(line); i = 1
      while (i <= n) {
        matched = 0
        # -- control-flow: "return 1" / "exit 1" --
        if (substr(line, i, 8) == "return 1") {
          before = (i == 1) ? "" : substr(line, i-1, 1)
          after  = (i+8 > n) ? "" : substr(line, i+8, 1)
          lb = (before == "" || !is_wchar(before)); rb = (after == "" || !is_wchar(after))
          if (lb && rb) { out = out "return 0"; i += 8; NCH++; NCTL++; matched = 1 }
        }
        if (!matched && substr(line, i, 6) == "exit 1") {
          before = (i == 1) ? "" : substr(line, i-1, 1)
          after  = (i+6 > n) ? "" : substr(line, i+6, 1)
          lb = (before == "" || !is_wchar(before)); rb = (after == "" || !is_wchar(after))
          if (lb && rb) { out = out "exit 0"; i += 6; NCH++; NCTL++; matched = 1 }
        }
        # -- accumulator: <var>=1  (var = [_A-Za-z][_A-Za-z0-9]*) at a left word boundary, followed by
        #    end-or-non-word (so var=10 / var=1x do NOT match) --
        if (!matched) {
          before = (i == 1) ? "" : substr(line, i-1, 1)
          if ((before == "" || !is_wchar(before)) && substr(line, i, 1) ~ /[_A-Za-z]/) {
            j = i; name = ""
            while (j <= n && substr(line, j, 1) ~ /[_A-Za-z0-9]/) { name = name substr(line, j, 1); j++ }
            if (substr(line, j, 2) == "=1") {
              after = (j+2 > n) ? "" : substr(line, j+2, 1)
              if (after == "" || !is_wchar(after)) {
                out = out name "=0"; i = j + 2; NCH++; NACC++; matched = 1
              }
            }
          }
        }
        if (!matched) { out = out substr(line, i, 1); i++ }
      }
      return out
    }
    BEGIN { applied = 0; applied_acc = 0; applied_ctl = 0 }
    {
      line = $0
      # mutate ONLY the check-logic region: lines strictly BEFORE the oracle marker.
      if (NR < mark) {
        line = neuter(line)
        if (NCH > 0) { applied += NCH; applied_acc += NACC; applied_ctl += NCTL }
      }
      print line
    }
    END {
      print "APPLIED=" applied ";ACC=" applied_acc ";CTL=" applied_ctl ";MARK=" mark > "/dev/stderr"
    }
  ' "$1" > "$2" 2>"$3"
  tail -1 "$3"
}

# ── _cleanup <file...> : remove each path if present (no-fail). Called verdict-agnostically by judge.
_cleanup() { for _f in "$@"; do [ -e "$_f" ] && rm -f "$_f" 2>/dev/null || true; done; }

# ── _mktemp_in <dir> <prefix> : make a GUARANTEED-UNIQUE temp file inside <dir> and echo its full path.
#    Uses mktemp (unique even for many checks within the same wall-clock second) — NOT a home-grown
#    random token: awk srand() reseeds only once per second, so a seconds-granularity token collides for
#    every check judged in the same second (constant $$), which used to leave .nv-* files behind and
#    poison a later self-scanning check (grep -rl descends into dotfiles). The template uses TRAILING
#    X's only (portable — BSD mktemp does NOT expand X's followed by a suffix; it would create a literal
#    `.nv-XXXXXX.sh` and re-open the collision). The mutant is run via `sh <file>`, so no .sh extension
#    is needed. The `.nv-` prefix keeps any (SIGKILL-only) leftover identifiable + .gitignore-matchable.
_mktemp_in() {
  _d=$1; _pfx=$2
  _t=$(cd "$_d" && mktemp "./${_pfx}XXXXXX") || return 1
  printf '%s/%s\n' "$_d" "$(basename "$_t")"
}

# ── region_intact <orig> <mut> <mark> : belt-and-suspenders. Returns 0 iff NO changed line is at or
#    after <mark> (the first selftest marker). A mutation landing in the oracle region VOIDs the run.
region_intact() {
  # diff by line number; report the first differing line. Uses awk (no external diff dependency drift).
  _bad=$(LC_ALL=C awk -v mark="$3" '
    NR==FNR { a[FNR]=$0; na=FNR; next }
    { if ($0 != a[FNR] && FNR >= mark) { print FNR; exit } }
    END {}
  ' "$1" "$2")
  [ -z "$_bad" ]
}

# ── judge <check.sh> : print a one-line verdict; return 0=KILLED · 1=SURVIVED · 2=UNCOVERED · 3=ERROR.
#    Thin wrapper: allocate the two temp paths (mutant + ctl copy) up-front with mktemp (unique), run
#    the core, then clean up ALL temp files VERDICT-AGNOSTICALLY (every branch: KILLED/SURVIVED/
#    UNCOVERED/ERROR) so nothing is ever left in conformance/ (which a self-scanning check like
#    mode-enforcement-blind would otherwise descend into via grep -rl and be poisoned by).
judge() {
  _jchk=$1
  _jdir=$(dirname "$_jchk")
  _jmut=""; _jctl=""
  set +e
  _judge_core "$_jchk"
  _jrc=$?
  set -e
  # verdict-agnostic cleanup — runs no matter which branch _judge_core returned from.
  _cleanup "$_jmut" "$_jmut.meta" "$_jctl"
  return "$_jrc"
}

# ── _judge_core <check.sh> : the actual verdict logic. Sets the outer _jmut / _jctl (so judge's
#    cleanup can remove them) BEFORE any early return, so no path leaks a temp file.
_judge_core() {
  _chk=$1
  _base=$(basename "$_chk")
  _dir=$(dirname "$_chk")
  # 1. sanity — the UNMUTATED check's --selftest must pass in its OWN directory, else it is pre-broken.
  if ! sh "$_chk" --selftest >/dev/null 2>&1; then
    echo "ERROR: $_base — its own --selftest FAILS unmutated (pre-broken; cannot mutation-test)"
    return 3
  fi
  # 2. locate the oracle region marker. mark==0 => no recognisable selftest region => UNCOVERED.
  _mark=$(first_marker "$_chk"); [ -n "$_mark" ] || _mark=0
  if [ "$_mark" = 0 ]; then
    echo "UNCOVERED: $_base — no recognisable --selftest region (reason: no-selftest-region)"
    return 2
  fi
  # build the mutant NEXT TO the check (so $0-relative sourcing / cd .. resolves), unique via mktemp.
  _jmut=$(_mktemp_in "$_dir" ".nv-mut-") || { echo "ERROR: $_base — mktemp failed for the mutant"; return 3; }
  _sent=$(mutate "$_chk" "$_jmut" "$_jmut.meta" "$_mark")
  case "$_sent" in
    APPLIED=0*)
      echo "UNCOVERED: $_base — no FAIL-path idiom in the check region before the oracle (reason: no-idiom)"
      return 2 ;;
  esac
  _acc=$(printf '%s' "$_sent" | sed -n 's/.*;ACC=\([0-9]*\).*/\1/p'); [ -n "$_acc" ] || _acc=0
  # 2b. region invariant — a mutation must NEVER land at/after the first selftest marker (oracle guard).
  if ! region_intact "$_chk" "$_jmut" "$_mark"; then
    echo "UNCOVERED: $_base — a mutation would land in the oracle region (reason: region-ambiguous)"
    return 2
  fi
  # 2c. certainty guard — run an UNMUTATED copy AT THE MUTANT'S RUN LOCATION. If it does not pass there,
  #     the mutant would crash for a context reason (sibling sourcing / $0-relative / a self-scanning
  #     check that sees our own temp file) and any "kill" would be a FALSE kill. Report UNCOVERED
  #     (context/run-location), never KILLED.
  _jctl=$(_mktemp_in "$_dir" ".nv-ctl-") || { echo "ERROR: $_base — mktemp failed for the ctl copy"; return 3; }
  cp "$_chk" "$_jctl"
  set +e
  sh "$_jctl" --selftest >/dev/null 2>&1
  _ctlrc=$?
  set -e
  if [ "$_ctlrc" != 0 ]; then
    echo "UNCOVERED: $_base — an unmutated copy does not pass at the mutant run location (reason: context/run-location)"
    return 2
  fi
  # 3. run the MUTANT's selftest at the run location.
  set +e
  sh "$_jmut" --selftest >/dev/null 2>&1
  _rc=$?
  set -e
  if [ "$_rc" != 0 ]; then
    echo "KILLED: $_base (selftest caught the neutered FAIL path; ${_sent})"
    return 0
  fi
  # SURVIVED. A genuine vacuity is one whose ACCUMULATOR-flip (a recorded verdict the selftest reads
  # back) survived. A CTL-only survivor (ACC=0) may be an equivalent mutant OR a reachable-CTL vacuity
  # the selftest does not observe — SURFACE it loudly for manual review as UNCOVERED (counted, NOT a
  # silent skip, NOT a sweep failure — equivalent mutants would otherwise create noise).
  if [ "$_acc" = 0 ]; then
    echo "UNCOVERED: $_base — a control-flow FAIL neuter survived but no accumulator idiom was mutated (reason: CTL-only — selftest may not observe the check's exit code; manual review) (${_sent})"
    return 2
  fi
  echo "SURVIVED: $_base — VACUOUS: its --selftest passes even when the check cannot FAIL — an accumulator-flip went uncaught (${_sent})"
  return 1
}

# ── target_set : the conformance scripts wired as control checks that expose a --selftest mode.
target_set() {
  grep -E '^check control' conformance/verify.sh 2>/dev/null \
    | grep -oE 'conformance/[a-z0-9-]+\.sh' | sort -u \
    | while IFS= read -r _f; do
        [ -f "$_f" ] || continue
        grep -q -- '--selftest' "$_f" 2>/dev/null && printf '%s\n' "$_f"
      done
}

# ── sweep_clean : remove EVERY harness artifact (.nv-mut-* / .nv-ctl-* [+ .meta]) from each targeted
#    check's directory. The `.nv-` prefix is written ONLY by this harness (via _mktemp_in), so this is
#    unambiguous + safe. Per-judge cleanup already removes each judge's own files; this is a
#    ROOT-CAUSE-AGNOSTIC belt-and-suspenders that guarantees the sweep NEVER leaves an artifact behind,
#    even if a check's own selftest machinery (e.g. adopter-export-wired's git-archive→verify chain)
#    produces a straggler in a way a single judge can't see. Run at sweep start (defensive vs. an
#    earlier SIGKILLed run) AND end (the guarantee a self-scanning check like mode-enforcement-blind is
#    never poisoned by a leaked mutant on a LATER verify/CI run).
sweep_clean() {
  for _d in $(target_set | while IFS= read -r _t; do dirname "$_t"; done | sort -u); do
    for _g in "$_d"/.nv-mut-* "$_d"/.nv-ctl-*; do
      [ -e "$_g" ] && rm -f "$_g" 2>/dev/null || true
    done
  done
}

# ── sweep : mutate every targeted check + tally. exit 1 iff any CERTAIN SURVIVED.
sweep() {
  _killed=0; _survived=0; _uncovered=0; _error=0; _total=0
  sweep_clean   # defensive: clear any straggler from a prior interrupted run before we start
  echo "non-vacuity sweep (mutation testing of the control-set conformance checks)"
  echo "------------------------------------------------------------------------"
  for _c in $(target_set); do
    _total=$((_total + 1))
    set +e
    _line=$(judge "$_c"); _v=$?
    set -e
    printf '  %s\n' "$_line"
    case "$_v" in
      0) _killed=$((_killed + 1)) ;;
      1) _survived=$((_survived + 1)) ;;
      2) _uncovered=$((_uncovered + 1)) ;;
      *) _error=$((_error + 1)) ;;
    esac
  done
  sweep_clean   # GUARANTEE: no harness artifact survives the sweep (never poison a later scan)
  echo "------------------------------------------------------------------------"
  printf 'non-vacuity sweep: %d killed · %d survived · %d uncovered · %d error (of %d targeted)\n' \
    "$_killed" "$_survived" "$_uncovered" "$_error" "$_total"
  echo "HONEST CEILING: KILLED only when CERTAIN; every ambiguity (region / run-context / CTL-only)"
  echo "is surfaced as an enumerated UNCOVERED, never a silent skip and never a false KILL."
  if [ "$_survived" != 0 ]; then
    echo "RESULT: FAIL — a surviving mutant means a VACUOUS check (its --selftest is not load-bearing). Fix that selftest."
    return 1
  fi
  if [ "$_error" != 0 ]; then
    echo "RESULT: FAIL — a targeted check's own --selftest is already broken (see ERROR above)."
    return 1
  fi
  echo "RESULT: OK — every targeted check is load-bearing (mutant KILLED) or honestly UNCOVERED."
  return 0
}

# ── selftest : the harness's OWN non-vacuity (self-teeth). A load-bearing fixture must be KILLED; a
#    deliberately-vacuous fixture must SURVIVE (be flagged); the two verdicts must differ (proving the
#    kill-detection is real, not a constant). Build-time flip: force judge to always KILLED and the
#    vacuous assertion FAILs the selftest. Fixtures are self-contained (no sibling sourcing), so they
#    run cleanly from their own dir.
selftest() {
  st=0; d=$(mktemp -d)

  # Fixture GOOD — genuinely load-bearing: check_x() FAILs (fail=1) when TOKEN is absent, and the
  # selftest has a NEGATIVE fixture that expects that FAIL. Neutering fail=1 flips it -> KILLED.
  cat > "$d/good.sh" <<'EOF'
#!/bin/sh
set -eu
check_x() { fail=0; grep -q TOKEN "$1" || fail=1; [ "$fail" = 0 ] && echo PASS || { echo FAIL; return 1; }; }
selftest() {
  st=0; t=$(mktemp -d); printf 'TOKEN\n' > "$t/y"; : > "$t/n"
  check_x "$t/y" >/dev/null || { echo "st FAIL pos"; st=1; }
  check_x "$t/n" >/dev/null && { echo "st FAIL neg"; st=1; }
  [ "$st" = 0 ] && echo "good --selftest: OK" || { echo "good --selftest: FAIL" >&2; return 1; }
}
case "${1:-}" in --selftest) selftest; exit $? ;; *) check_x "$2"; exit $? ;; esac
EOF

  # Fixture VACUOUS — the selftest has ONLY a positive fixture (never asserts a FAIL). Neutering the
  # accumulator changes nothing the selftest checks -> SURVIVES -> must be FLAGGED.
  cat > "$d/vac.sh" <<'EOF'
#!/bin/sh
set -eu
check_x() { fail=0; grep -q TOKEN "$1" || fail=1; [ "$fail" = 0 ] && echo PASS || { echo FAIL; return 1; }; }
selftest() {
  st=0; t=$(mktemp -d); printf 'TOKEN\n' > "$t/y"
  check_x "$t/y" >/dev/null || { echo "st FAIL pos"; st=1; }
  [ "$st" = 0 ] && echo "vac --selftest: OK" || { echo "vac --selftest: FAIL" >&2; return 1; }
}
case "${1:-}" in --selftest) selftest; exit $? ;; *) check_x "$2"; exit $? ;; esac
EOF

  # Fixture STRAY-BRACE — a genuinely load-bearing check whose SELFTEST region contains a stray `}` and
  # `fi` inside a string/comment. Under the OLD brace/fi counter this closed the region early and a
  # mutation corrupted the oracle -> false KILL. Under the marker-only rule it must be handled safely:
  # the check IS load-bearing (fail=1 before the marker), so it must be KILLED — and NEVER a false KILL
  # from oracle corruption. (This reproduces the security reviewer's kill_exploit fixture, now safe.)
  cat > "$d/stray.sh" <<'EOF'
#!/bin/sh
set -eu
check_x() { fail=0; grep -q TOKEN "$1" || fail=1; [ "$fail" = 0 ] && echo PASS || { echo FAIL; return 1; }; }
selftest() {
  st=0; t=$(mktemp -d); printf 'TOKEN\n' > "$t/y"; : > "$t/n"
  # a stray brace } and keyword fi in this comment must NOT confuse the region boundary
  echo "a string with a } and fi inside it" >/dev/null
  check_x "$t/y" >/dev/null || { echo "st FAIL pos"; st=1; }
  check_x "$t/n" >/dev/null && { echo "st FAIL neg"; st=1; }
  [ "$st" = 0 ] && echo "stray --selftest: OK" || { echo "stray --selftest: FAIL" >&2; return 1; }
}
case "${1:-}" in --selftest) selftest; exit $? ;; *) check_x "$2"; exit $? ;; esac
EOF

  set +e
  ( judge "$d/good.sh" )  >/dev/null 2>&1; g=$?
  ( judge "$d/vac.sh" )   >/dev/null 2>&1; v=$?
  ( judge "$d/stray.sh" ) >/dev/null 2>&1; s=$?
  set -e

  if [ "$g" = 0 ]; then echo "PASS: load-bearing check -> mutant KILLED"; else echo "FAIL: load-bearing check not killed (got $g)"; st=1; fi
  if [ "$v" = 1 ]; then echo "PASS: vacuous check -> mutant SURVIVED (flagged)"; else echo "FAIL: vacuous check not flagged (got $v)"; st=1; fi
  # LOAD-BEARING NEGATIVE on the harness itself: the two verdicts MUST differ. If judge were mutated to
  # always return KILLED (0), g==v==0 and this assertion FAILs the selftest.
  if [ "$g" = "$v" ]; then echo "FAIL: harness cannot distinguish load-bearing from vacuous (g=$g v=$v)"; st=1; fi
  # stray-brace/fi in the oracle must NOT cause a false KILL: the check is load-bearing so KILLED is
  # correct, but the point is it is KILLED for the RIGHT reason (region intact), never corrupted.
  if [ "$s" = 0 ]; then echo "PASS: stray }/fi in oracle -> KILLED for the right reason (no region corruption)"; else echo "FAIL: stray }/fi mishandled (got $s, want 0=KILLED)"; st=1; fi

  # UNCOVERED fixture — no FAIL-path idiom -> judge returns 2 (surfaced, not a false pass).
  cat > "$d/unc.sh" <<'EOF'
#!/bin/sh
set -eu
check_x() { grep -q TOKEN "$1" && echo PASS; }
selftest() { t=$(mktemp -d); printf 'TOKEN\n' > "$t/y"; check_x "$t/y" >/dev/null; echo "unc --selftest: OK"; }
case "${1:-}" in --selftest) selftest; exit $? ;; *) check_x "$2"; exit $? ;; esac
EOF
  set +e
  ( judge "$d/unc.sh" ) >/dev/null 2>&1; u=$?
  set -e
  if [ "$u" = 2 ]; then echo "PASS: no-FAIL-path check -> UNCOVERED (surfaced, not a false pass)"; else echo "FAIL: no-FAIL-path check not reported UNCOVERED (got $u)"; st=1; fi

  # CONTEXT fixture — a check that SOURCES a sibling by $0-relative path. Run from a different dir the
  # sibling would be absent; the certainty guard must report UNCOVERED (context/run-location), NEVER a
  # false KILL. We build it in a subdir WITH its sibling so the unmutated copy passes in-place, then a
  # SECOND copy whose sibling is missing to prove the guard fires.
  mkdir -p "$d/ctx"
  cat > "$d/ctx/sib.sh" <<'EOF'
SIB_OK=1
EOF
  cat > "$d/ctx/ctxchk.sh" <<'EOF'
#!/bin/sh
set -eu
. "$(dirname "$0")/sib.sh"
check_x() { fail=0; [ "${SIB_OK:-0}" = 1 ] && grep -q TOKEN "$1" || fail=1; [ "$fail" = 0 ] && echo PASS || { echo FAIL; return 1; }; }
selftest() {
  st=0; t=$(mktemp -d); printf 'TOKEN\n' > "$t/y"; : > "$t/n"
  check_x "$t/y" >/dev/null || { echo pos; st=1; }
  check_x "$t/n" >/dev/null && { echo neg; st=1; }
  [ "$st" = 0 ] && echo "ctx --selftest: OK" || { echo "ctx --selftest: FAIL" >&2; return 1; }
}
case "${1:-}" in --selftest) selftest; exit $? ;; *) check_x "$2"; exit $? ;; esac
EOF
  # with the sibling present next to it, the mutant (also written next to it) resolves -> KILLED.
  set +e
  ( judge "$d/ctx/ctxchk.sh" ) >/dev/null 2>&1; c=$?
  set -e
  if [ "$c" = 0 ]; then echo "PASS: sibling-sourcing check (sibling present) -> KILLED at run location"; else echo "FAIL: sibling-sourcing check mis-verdicted (got $c, want 0=KILLED)"; st=1; fi

  [ "$st" = 0 ] && echo "non-vacuity --selftest: OK" || { echo "non-vacuity --selftest: FAIL" >&2; return 1; }
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "")         sweep; exit $? ;;
  *) echo "usage: non-vacuity.sh [--selftest]" >&2; exit 2 ;;
esac
