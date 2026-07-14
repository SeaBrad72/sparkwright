#!/bin/sh
# non-vacuity.sh — mutation-testing gate for conformance checks. Neuters each targeted check's FAIL
# path (on a TEMP COPY written NEXT TO the check so its $0-relative sourcing still resolves), runs its
# --selftest, and flags a SURVIVING mutant = a vacuous check (a selftest that does not actually catch a
# broken check). Automates the kit's non-vacuity law as a standing gate (was a per-slice manual
# discipline). Author-INDEPENDENT: no per-check declared kills.
#   sh conformance/non-vacuity.sh                    # live sweep over the verify.sh control set; exit 1 on a survivor
#   sh conformance/non-vacuity.sh --selftest         # self-teeth (mechanism): load-bearing killed, vacuous survives
#   sh conformance/non-vacuity.sh --only <check.sh>  # DEV-ONLY: sweep a SINGLE control check (basename) in seconds
#     instead of the full ~6-min set. CI ALWAYS runs the full sweep (no --only); --only can never narrow what CI
#     enforces. A --only that matches no targeted check exits 2 (a targeted sweep evaluating nothing is never a pass).
# Exit: 0 = all targeted checks load-bearing (mutants KILLED) or honestly UNCOVERED · 1 = a survivor
#   (vacuous check) or --selftest failure · 2 = usage / a zero-match --only. POSIX sh; dash-clean.
# A bare sweep over an EMPTY control set intentionally returns 1 (fail-closed) — a sweep that evaluated
#   nothing must never report success — so wiring the CI job before registering any `^check control` rows
#   reads as a red, not a false green.
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
#   - mutate() has NO lexer: it neuters a <var>=1 token wherever it appears BEFORE the marker, including
#     inside a COMMENT or string. A literal <var>=1 in a pre-marker comment thus becomes a phantom
#     accumulator (inflates ACC). Keep such tokens out of pre-marker comments; the ACC census is the tell.
#   - Equivalent mutants (a survivor whose only neutered idiom is bare control-flow return/exit 1 that
#     a passing selftest may not observe) are SURFACED for manual review as UNCOVERED (CTL-only), not
#     killed and not failed.
#   Proves each selftest catches the FAIL-PATH operator class — NOT every conceivable weakness. A
#   strong automated floor, not a completeness proof.
set -eu
cd "$(dirname "$0")/.." 2>/dev/null || true
ONLY=""              # single check to judge (basename); set ONLY via --only <name> on argv, NEVER from
                     # the environment — the bare/CI path can never be narrowed. Empty = the whole set.
SHARD_I=""           # CI shard coordinates; set ONLY via --shard <i>/<n> on argv, NEVER from the
SHARD_N=""           # environment. LITERAL assignments on purpose: they overwrite any inherited env var
                     # of the same name, so a decoy `SHARD_N=99` in the environment cannot narrow what CI
                     # enforces. Same law as ONLY (proved behaviorally by F1/F6 in --selftest). Empty =
                     # unsharded (the whole set). A shard that targets NOTHING is a FAILURE, never a
                     # vacuous pass — sharding must never become a way to gut the gate (F5).

# ── first_marker <src> : print the 1-based line number where the selftest ORACLE region begins — the
#    earliest of a  ^selftest()  function definition OR an  if [ ... --selftest ... ]  block opener
#    (the two kit oracle conventions that carry fixtures + assertions). An  if [ … --selftest … ]  block
#    opener counts only when it tests a positional arg (`$1`/`${1`) — an `if ! sh child --selftest`
#    INVOCATION of another script's selftest is not a dispatch and must not win over the real oracle. A
#    bare  --selftest)  case arm is used ONLY as a fallback when neither exists (it is usually an
#    arg-parse mode-setter or the tail dispatch, not the oracle body). Prints 0 if no marker at all.
#    LC_ALL=C: byte-safe (some checks carry multibyte chars in comments; awk char scanning must not
#    choke on them).
first_marker() {
  LC_ALL=C awk '
    /^[[:space:]]*selftest[[:space:]]*\(\)/ { if (fn==0) fn=NR }
    /^[[:space:]]*if[[:space:]].*--selftest/ && ($0 ~ /\$1/ || $0 ~ /\$\{1/) { if (ifb==0) ifb=NR }
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

# ── has_selftest_dispatch <file> : 0 iff <file> exposes a real --selftest ORACLE region (first_marker>0);
#    1 if --selftest appears only as a non-dispatch substring (e.g. a fixture payload). This is the
#    membership predicate for the mutation target set: a check with no dispatch region is NOT
#    selftest-bearing, so there is no selftest for a mutant to prove vacuous — it is reported SKIPPED, never
#    UNCOVERED (which would falsely imply a wider operator could reach a verdict on a selftest that isn't there).
has_selftest_dispatch() { [ "$(first_marker "$1")" != 0 ]; }

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
      echo "UNCOVERED: $_base — no mutable FAIL-path idiom before the oracle; this check's teeth live in its --selftest region or a sibling helper, so mutating this file cannot fail its selftest (reason: no-idiom)"
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

# ── shard_filter : partition the target list across SHARD_N parallel CI legs, emitting only leg SHARD_I.
#    Round-robin on line number ((NR-1) % n == i-1) over the DETERMINISTIC, `sort -u`-ordered list. Two
#    properties make this safe to shard a governance gate on:
#      COMPLETE — every line satisfies exactly one residue class, so shards 1..N are a true PARTITION:
#                 their union is the full set and they never overlap. No check can fall between legs.
#                 (Asserted behaviorally by F5b in --selftest, which reassembles the union and diffs it
#                 against the unsharded set — a partition bug fails the build, it does not go unnoticed.)
#      BALANCED — round-robin interleaves rather than blocks, so the expensive checks spread evenly across
#                 legs without needing per-check timings (which we do not have and would rot).
#    A no-op when SHARD_N is empty: the bare/CI full sweep is byte-for-byte unchanged.
shard_filter() {
  [ -n "$SHARD_N" ] || { cat; return 0; }
  awk -v i="$SHARD_I" -v n="$SHARD_N" '((NR - 1) % n) == (i - 1)'
}

# ── target_set : the conformance scripts wired as control checks that expose a --selftest mode.
#    Sharding is applied LAST, after every membership filter, so a shard is always a strict subset of the
#    true target set — never a different set.
target_set() {
  grep -E '^check control' conformance/verify.sh 2>/dev/null \
    | grep -oE 'conformance/[a-z0-9-]+\.sh' | sort -u \
    | while IFS= read -r _f; do
        [ -f "$_f" ] || continue
        [ -z "$ONLY" ] || [ "$(basename "$_f")" = "$ONLY" ] || continue
        grep -q -- '--selftest' "$_f" 2>/dev/null || continue
        has_selftest_dispatch "$_f" && printf '%s\n' "$_f"
      done \
    | shard_filter
}

# ── nonbearing_set : control checks whose file contains the --selftest substring but expose NO dispatch
#    region (first_marker==0). These are NOT mutation-testable (no selftest oracle to prove vacuous); the
#    sweep prints them as SKIPPED so the exclusion is visible (no silent cap), never counted UNCOVERED.
nonbearing_set() {
  grep -E '^check control' conformance/verify.sh 2>/dev/null \
    | grep -oE 'conformance/[a-z0-9-]+\.sh' | sort -u \
    | while IFS= read -r _f; do
        [ -f "$_f" ] || continue
        [ -z "$ONLY" ] || [ "$(basename "$_f")" = "$ONLY" ] || continue
        grep -q -- '--selftest' "$_f" 2>/dev/null || continue
        has_selftest_dispatch "$_f" || printf '%s\n' "$_f"
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
  # F2 — explicit re-entrancy guard. non-vacuity.sh is itself a targeted check; when the full sweep
  # judges it, the mutant's --selftest re-enters sweep. Terminate LOUDLY rather than recurse (a CI hang
  # is worse than a CI failure). The flag value is 'y' (NOT '=1') so the mutation harness — which
  # neuters a <var>=1 accumulator before the marker — cannot flip it: the guard stays inert to
  # mutation, keeping non-vacuity.sh's own ACC measurement unchanged.
  if [ -n "${NV_IN_SWEEP:-}" ]; then
    echo "FAIL: non-vacuity sweep re-entered itself (re-entrancy guard)" >&2; return 2
  fi
  NV_IN_SWEEP=y; export NV_IN_SWEEP
  _killed=0; _survived=0; _uncovered=0; _error=0; _total=0
  sweep_clean   # defensive: clear any straggler from a prior interrupted run before we start
  echo "non-vacuity sweep (mutation testing of the control-set conformance checks)"
  echo "------------------------------------------------------------------------"
  for _s in $(nonbearing_set); do
    printf '  SKIPPED: %s — not selftest-bearing (--selftest present only as a fixture payload; no dispatch region)\n' "$(basename "$_s")"
  done
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
  # A sweep that evaluated NOTHING must never report success — the very law this tool enforces.
  if [ "$_total" = 0 ]; then
    if [ -n "$ONLY" ]; then
      echo "FAIL: --only '$ONLY' matched no targeted check (a targeted sweep that evaluates nothing must never report success)" >&2
      return 2
    fi
    # F5 — an EMPTY SHARD is a gate FAILURE, never a vacuous pass. This is the anti-cheat that makes
    # sharding safe: without it, `--shard 9/9` on a 4-check set would evaluate nothing, exit 0, and a CI
    # leg would report GREEN having mutation-tested precisely zero checks. Sharding must never become a
    # way to gut the gate — so an empty leg is as loud as an empty control set.
    if [ -n "$SHARD_N" ]; then
      echo "FAIL: shard $SHARD_I/$SHARD_N targeted no check (an empty shard must never report success — is SHARD_N larger than the control set?)" >&2
      return 1
    fi
    # F4 — a BARE sweep whose control set is empty is a gate FAILURE (return 1), not a vacuous OK.
    echo "FAIL: the control set is empty — no targeted check to mutation-test (a sweep that evaluates nothing must never report success)" >&2
    return 1
  fi
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

# ── bare_sweep : the bare/CI dispatch body. Resets BOTH narrowing mechanisms — ONLY and the SHARD
#    coordinates — to empty, then runs the FULL sweep, so the bare/CI path can NEVER be narrowed by an
#    inherited environment: it always sweeps the WHOLE control set. The SHARD reset is defense-in-depth
#    and deliberate: there must be exactly ONE way to narrow this gate (an explicit argv --shard), and the
#    bare arm must not be it. Without the reset the invariant would hold only by accident (SHARD_* happen
#    to be unset on that path); with it, the invariant is EXPLICIT and behaviorally testable (F1/F6).
#    This is a one-line delegation, NOT a test hook: no env read, no early exit. selftest proves the reset
#    by overriding sweep() in a subshell (POSIX lets a subshell shadow a function) and observing what
#    actually reaches it — no test-only env var, no fail-open code path, lives in production.
bare_sweep() { ONLY=""; SHARD_I=""; SHARD_N=""; sweep; }

# ── shard_sweep <i> <n> : the CI shard dispatch body. Like bare_sweep it RESETS ONLY, so a sharded CI leg
#    can never be narrowed twice (an inherited ONLY on top of a shard would silently reduce a leg to one
#    check while still reporting GREEN). The shard coordinates arrive as POSITIONAL ARGUMENTS from argv —
#    never from the environment — and are validated before any check runs. Bad coordinates EXIT 2 (usage):
#    a leg that cannot state which slice of the gate it enforces must not run a partial gate and pass.
shard_sweep() {
  _si=$1; _sn=$2
  case "$_si" in ''|*[!0-9]*) echo "usage: non-vacuity.sh --shard <i>/<n>  (i and n must be positive integers)" >&2; exit 2 ;; esac
  case "$_sn" in ''|*[!0-9]*) echo "usage: non-vacuity.sh --shard <i>/<n>  (i and n must be positive integers)" >&2; exit 2 ;; esac
  [ "$_sn" -ge 1 ] || { echo "FAIL: --shard n must be >= 1 (got $_sn)" >&2; exit 2; }
  [ "$_si" -ge 1 ] || { echo "FAIL: --shard i must be >= 1 (got $_si)" >&2; exit 2; }
  [ "$_si" -le "$_sn" ] || { echo "FAIL: --shard i ($_si) exceeds n ($_sn) — that leg does not exist" >&2; exit 2; }
  ONLY=""; SHARD_I=$_si; SHARD_N=$_sn
  echo "non-vacuity: SHARD $_si of $_sn (this leg enforces a strict subset; the union of all $_sn legs is the full control set)"
  sweep
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

  # INVOCATION-VS-DISPATCH fixture (fix ②) — a check whose body contains a spurious
  #   `if ! sh "$prog" --selftest ...` INVOCATION line (no $1/${1) placed BEFORE its real selftest(), with
  #   a load-bearing `fail=1` accumulator between them. Under the OLD marker rule the invocation line wins
  #   -> the accumulator is protected -> UNCOVERED(no-idiom). Under the fix the real selftest() is the
  #   marker -> the accumulator is mutated -> the negative fixture flips -> KILLED. (Reproduces the harness's
  #   OWN blind spot: non-vacuity.sh's line-177 `if ! sh "$_chk" --selftest` was masking selftest() @304.)
  cat > "$d/inv.sh" <<'EOF'
#!/bin/sh
set -eu
prog=child.sh
warm() {
  if ! sh "$prog" --selftest >/dev/null 2>&1; then echo warned; fi
}
check_x() { fail=0; grep -q TOKEN "$1" || fail=1; [ "$fail" = 0 ] && echo PASS || { echo FAIL; return 1; }; }
selftest() {
  st=0; t=$(mktemp -d); printf 'TOKEN\n' > "$t/y"; : > "$t/n"
  check_x "$t/y" >/dev/null || { echo pos; st=1; }
  check_x "$t/n" >/dev/null && { echo neg; st=1; }
  [ "$st" = 0 ] && echo "inv --selftest: OK" || { echo "inv --selftest: FAIL" >&2; return 1; }
}
case "${1:-}" in --selftest) selftest; exit $? ;; *) check_x "$2"; exit $? ;; esac
EOF
  # unit: first_marker must pick the real selftest() line, NOT the spurious invocation line.
  _exp=$(grep -n '^selftest()' "$d/inv.sh" | cut -d: -f1)
  _got=$(first_marker "$d/inv.sh")
  if [ "$_got" = "$_exp" ]; then echo "PASS: first_marker skips an --selftest INVOCATION line, picks the real dispatch"; else echo "FAIL: first_marker picked a non-dispatch line (got $_got, want $_exp)"; st=1; fi
  # end-to-end: the accumulator between the invocation line and the real selftest must be mutated -> KILLED.
  set +e
  ( judge "$d/inv.sh" ) >/dev/null 2>&1; iv=$?
  set -e
  if [ "$iv" = 0 ]; then echo "PASS: invocation-masked accumulator -> mutant KILLED (marker fix load-bearing)"; else echo "FAIL: invocation-masked check not killed (got $iv, want 0=KILLED)"; st=1; fi

  # PAYLOAD-ONLY fixture (fix ①) — a check that runs assertions directly; `--selftest` appears ONLY inside
  #   quoted payload strings, never as a dispatch. It is NOT selftest-bearing and must be EXCLUDED from the
  #   mutation target set (reported SKIPPED), not counted UNCOVERED. (Reproduces agent-autonomy.sh, whose
  #   only `--selftest` occurrences are guard/escalate command payloads.)
  cat > "$d/payload.sh" <<'EOF'
#!/bin/sh
set -eu
run_case() { printf '%s\n' "$1" >/dev/null; }
run_case '{"tool":"Bash","command":"sh scripts/kit-guard --selftest"}'
run_case '{"tool":"Bash","command":"sh scripts/escalate.sh --selftest"}'
[ -n "${CI:-}" ] || true
EOF
  if has_selftest_dispatch "$d/payload.sh"; then echo "FAIL: payload-only --selftest wrongly treated as selftest-bearing"; st=1; else echo "PASS: payload-only --selftest -> not selftest-bearing (SKIPPED, not UNCOVERED)"; fi
  if has_selftest_dispatch "$d/good.sh"; then echo "PASS: a genuine --selftest dispatch -> selftest-bearing (included)"; else echo "FAIL: a genuine dispatch was wrongly excluded"; st=1; fi

  # --only: filters target_set to a single check (dev ergonomic; CI always runs the full sweep).
  _n=$(ONLY=script-disclosure.sh target_set | wc -l | tr -d ' ')
  if [ "$_n" = 1 ]; then echo "PASS: --only narrows target_set to one check"; else echo "FAIL: --only narrowed to $_n, want 1"; st=1; fi
  # A targeted sweep that matches NOTHING must never report success — that is the very defect
  # this tool exists to find. It must exit 2 (usage), not 0.
  set +e; ( NV_IN_SWEEP='' ONLY=no-such-check.sh; sweep ) >/dev/null 2>&1; _z=$?; set -e
  if [ "$_z" = 2 ]; then echo "PASS: --only with no match -> exit 2 (never a vacuous success)"; else echo "FAIL: zero-match --only returned $_z, want 2"; st=1; fi

  # F4 (regression): a BARE sweep whose control set is legitimately empty must FAIL (return 1), never
  # print "OK ... of 0 targeted". Drive it against a real fixture tree whose conformance/verify.sh
  # registers NO control checks — this does NOT weaken target_set, it gives it a genuinely empty set.
  # NV_IN_SWEEP='' clears any inherited guard flag so the fixture runs a real (empty) sweep instead of
  # tripping the F2 re-entrancy guard (which would return 2, not the 1 under test).
  mkdir -p "$d/f4/conformance"
  printf '#!/bin/sh\n# fixture: no control checks registered\n' > "$d/f4/conformance/verify.sh"
  cp "$0" "$d/f4/conformance/non-vacuity.sh"
  set +e; NV_IN_SWEEP='' sh "$d/f4/conformance/non-vacuity.sh" >/dev/null 2>&1; _fe=$?; set -e
  if [ "$_fe" = 1 ]; then echo "PASS: bare sweep with an empty control set -> FAIL (return 1), never a vacuous OK"; else echo "FAIL: bare empty control set returned $_fe, want 1"; st=1; fi

  # F1 (regression): the bare/CI dispatch must IGNORE an inherited ONLY. A gate the environment can
  # silently narrow is the very vacuity this tool exists to detect. Drive the REAL bare_sweep (the exact
  # body the bare/CI arm runs) with an inherited ONLY set, and stub sweep() in a subshell to report the
  # ONLY it actually sees. bare_sweep resets ONLY to "" before calling sweep, so the stub MUST observe
  # ONLY=[] — proving the bare/CI path cannot be narrowed. Fully behavioral (runs the real seam with the
  # real ONLY inheritance), instant (the stub returns at once), and NO production hook / early exit / env
  # var. If bare_sweep stopped resetting ONLY, the stub would see the inherited value and this FAILs.
  _bo=$( ONLY=script-disclosure.sh; sweep() { printf 'ONLY=[%s]\n' "$ONLY"; }; bare_sweep )
  if [ "$_bo" = "ONLY=[]" ]; then echo "PASS: bare/CI dispatch ignores an inherited ONLY (cannot be narrowed)"; else echo "FAIL: bare/CI dispatch honored env ONLY ($_bo) -- CI can be silently narrowed"; st=1; fi

  # ── F5 — an EMPTY SHARD must FAIL, never report a vacuous success. This is THE anti-cheat that makes it
  # safe to shard a governance gate. A leg that mutation-tests zero checks and exits 0 is a GREEN check
  # attesting nothing — precisely the vacuity this tool exists to detect, reintroduced by the very
  # mechanism meant to speed it up. Drive the REAL dispatch with coordinates whose residue class is empty
  # (n far larger than the control set) and require a non-zero exit.
  set +e; NV_IN_SWEEP='' sh "$0" --shard 999/999 >/dev/null 2>&1; _es=$?; set -e
  if [ "$_es" != 0 ]; then echo "PASS: an empty shard FAILs (exit $_es) — a leg that tests nothing never reports success"; else echo "FAIL: an empty shard exited 0 — sharding can silently gut the gate"; st=1; fi

  # ── F5b — COMPLETENESS: shards 1..n must be a true PARTITION of the unsharded target set. This is the
  # property the whole design rests on: if a check fell between two legs, every leg would be GREEN and
  # that check would be mutation-tested by NOBODY — a silent hole in the gate, invisible forever. Prove it
  # by reassembling the union from the real shard_filter and diffing against the real unsharded set. A
  # partition bug fails the build here rather than going unnoticed in CI.
  _full=$(SHARD_I="" SHARD_N="" target_set | sort)
  for _n in 2 3 4 7; do
    _union=$(_i=1; while [ "$_i" -le "$_n" ]; do SHARD_I=$_i SHARD_N=$_n target_set; _i=$((_i + 1)); done | sort)
    if [ "$_union" = "$_full" ]; then
      echo "PASS: shards 1..$_n reassemble EXACTLY the unsharded target set (a true partition — no check falls between legs)"
    else
      echo "FAIL: shards 1..$_n do NOT reassemble the target set — a check would be tested by no leg"; st=1
    fi
  done
  # Overlap is the other half of "partition": a check tested twice is only wasteful, but a shard_filter
  # that emitted everything on every leg would ALSO satisfy the union test above while destroying the
  # speedup. Require the legs to be disjoint by counting.
  _cnt_full=$(printf '%s\n' "$_full" | grep -c . || true)
  _cnt_legs=$(_i=1; while [ "$_i" -le 4 ]; do SHARD_I=$_i SHARD_N=4 target_set; _i=$((_i + 1)); done | grep -c . || true)
  if [ "$_cnt_full" = "$_cnt_legs" ]; then echo "PASS: shards 1..4 are DISJOINT ($_cnt_legs = $_cnt_full checks, no duplication)"; else echo "FAIL: shard legs overlap ($_cnt_legs emitted vs $_cnt_full targets)"; st=1; fi

  # ── F6 — the bare/CI dispatch must IGNORE inherited SHARD coordinates, exactly as F1 requires of ONLY.
  # A gate the ENVIRONMENT can narrow is a gate an attacker (or a stray export) can silently reduce to one
  # check while CI still prints GREEN. There must be exactly ONE way to narrow this sweep — an explicit
  # argv --shard — and the bare arm must not be it. Drive the REAL bare_sweep with SHARD_* set and stub
  # sweep() in a subshell to report what actually reached it.
  _bs=$( SHARD_I=1; SHARD_N=99; sweep() { printf 'SHARD=[%s/%s]\n' "$SHARD_I" "$SHARD_N"; }; bare_sweep )
  if [ "$_bs" = "SHARD=[/]" ]; then echo "PASS: bare/CI dispatch ignores inherited SHARD coords (cannot be narrowed by the environment)"; else echo "FAIL: bare/CI dispatch honored an inherited SHARD ($_bs) -- CI can be silently narrowed"; st=1; fi

  [ "$st" = 0 ] && echo "non-vacuity --selftest: OK" || { echo "non-vacuity --selftest: FAIL" >&2; return 1; }
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  --only)     ONLY="${2:-}"
              [ -n "$ONLY" ] || { echo "usage: non-vacuity.sh --only <check.sh>" >&2; exit 2; }
              sweep; exit $? ;;
  --shard)    # CI dispatch, parallel leg. Coordinates come from ARGV ONLY (never the environment) — an
              # env-narrowable control gate is exactly the vacuity this tool exists to detect. Every leg
              # enforces a strict subset; an EMPTY leg FAILS (F5); the union of legs 1..n is the full set
              # (F5b). The ci.yml matrix that fans these out is locked by conformance/non-vacuity-wired.sh,
              # so CI cannot declare n=4 and silently run only 3 legs.
              _sarg="${2:-}"
              [ -n "$_sarg" ] || { echo "usage: non-vacuity.sh --shard <i>/<n>" >&2; exit 2; }
              case "$_sarg" in */*) : ;; *) echo "usage: non-vacuity.sh --shard <i>/<n>  (expected the form i/n, got '$_sarg')" >&2; exit 2 ;; esac
              shard_sweep "${_sarg%%/*}" "${_sarg##*/}"; exit $? ;;
  "")         # bare/CI dispatch: the FULL sweep. bare_sweep resets ONLY so an inherited environment ONLY
              # can never narrow what CI enforces. No env var can short-circuit this arm — it always sweeps.
              bare_sweep; exit $? ;;
  *) echo "usage: non-vacuity.sh [--selftest | --only <check.sh> | --shard <i>/<n>]" >&2; exit 2 ;;
esac
