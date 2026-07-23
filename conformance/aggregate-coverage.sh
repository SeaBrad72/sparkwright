#!/bin/sh
# aggregate-coverage.sh — every conformance/*.sh is accounted for by exactly one of three categories,
# so a check cannot exist outside BOTH suites unnoticed.
#   usage: sh conformance/aggregate-coverage.sh [--selftest] [--root=<dir>]
# Exit: 0 = every file accounted for · 1 = an unaccounted file, a stale/contradictory exclusion, or a
# vacuous (zero-file) scan · POSIX sh; dash-clean.
#
# WHY THIS EXISTS (CP7R5-GATE-AUTHORITY, D3). The kit runs two suites — the portable `verify.sh`
# battery and its own workflows — and NOTHING stated how they relate. The measured consequence was
# CI ⊄ verify.sh AND verify.sh ⊄ CI simultaneously: an adopter could be remote-green and locally-red
# on a required gate. The fix (all 11 emitted pipelines now run `verify.sh --require`) closes the
# gap that existed; THIS check keeps a new one from opening, which is the row's acceptance criteria
# verbatim — "a check that fails when one suite gains a required gate the other lacks".
#
# THE THREE CATEGORIES — see conformance/aggregate-exclusions.txt for the contract in full:
#   REGISTERED  named in conformance/verify.sh                (portable; adopters run it)
#   WORKFLOW    named in .github/workflows/*.yml              (enforced, kit-only)
#   LIBRARY     listed in aggregate-exclusions.txt            (sourced, never run; not a check)
#
# ★ HONEST CEILING — read before trusting a green. The WORKFLOW category counts a check whose name
# appears on a workflow line that is NEITHER a `#` comment NOR a `name:` label (see classify/_wf_exec).
# That rejects the two forms that most commonly create a false "covered" — a comment naming a check,
# and a step's `name:` label — but it does NOT prove the name sits in an actual `run:` command: a name
# in an `env:`/`with:`/`uses:` value, or in a non-executing string, still counts. Tightening this to a
# true `run:`-context matcher (single-line + block-scalar, awk-tracked like verify-enforced-wired.sh's
# _ep_github) is boarded as a follow-up — it also closes the IDENTICAL ceiling in ci-selftest-coverage.sh,
# which uses the same strip-and-match shape, so the two should move together. And even a true run:
# matcher is weaker than being REACHED at runtime: a step can be gated by an `if:`, negated, or skipped,
# and this check cannot see that. So a green here proves every check is ACCOUNTED FOR (named on a
# non-comment, non-label workflow line), never that every one actually RUNS. Do not let it stand in for that.
#
# SECOND CEILING: this check is NOT mutation-swept. conformance/non-vacuity.sh targets the verify.sh
# CONTROL SET, and this check is deliberately kit-only (measured: 56 UNACCOUNTED on a real incepted
# tree), so it sits outside the sweep — `non-vacuity.sh --only aggregate-coverage.sh` correctly
# reports "matched no targeted check". Its teeth are the --selftest below, run as its own CI step.
# That is the same posture as non-vacuity-wired.sh, and it is a weaker guarantee than the swept
# checks enjoy — stated here rather than left for someone to discover.
set -eu

ROOT="."
SELFTEST=0
for _a in "$@"; do
  case "$_a" in
    --root=*)   ROOT=${_a#--root=} ;;
    # Dispatch on the FLAG, not on $1. Accepting --selftest in the loop while dispatching on "${1:-}"
    # meant `--root=/tmp/x --selftest` ran a REAL scan of /tmp/x while the caller believed it had
    # self-tested — a silent no-op in the one command whose whole job is to prove the check works.
    --selftest) SELFTEST=1 ;;
    *) echo "FAIL: unknown argument '$_a'"; exit 1 ;;
  esac
done

# _lib_listed <root> <basename> -> 0 iff the basename has a LINE with a non-empty reason after the tab.
# A bare basename with no reason does NOT count: an unreasoned exclusion is exactly the silent
# widening this file exists to prevent, so it must fail rather than quietly pass.
_lib_listed() {
  _ll_f="$1/conformance/aggregate-exclusions.txt"
  [ -f "$_ll_f" ] || return 1
  grep -v '^[[:space:]]*#' "$_ll_f" \
    | grep -E "^$2[[:space:]]+[^[:space:]]" >/dev/null 2>&1
}

# _esc <s>: escape regex metacharacters in a basename. Unescaped, the `.` in `foo.sh` is a wildcard —
# a matcher that can say YES to the wrong file is the same class of defect as one that says yes to a
# comment. (Review finding M5.) The class covers every ERE metacharacter a basename could carry:
# `. [ \ * ^ $ + ? ( ) { } |` — so e.g. `a+b.sh` cannot spuriously match `aab.sh`.
_esc() { printf '%s' "$1" | sed 's/[].[\*^$+?(){}|]/\\&/g'; }

# _wf_exec <root> <escaped-basename> -> 0 iff the check's name appears on a workflow line that is
# NEITHER a `#` comment NOR a `name:` label. This rejects the two forms that most commonly fake a
# "covered" (a comment naming a check; a step's `name:` label) — the HIGH-3 defect — but it is NOT a
# true execution-context matcher: a name in an `env:`/`with:`/`uses:` value or a non-executing string
# still passes. A single-line `run:.*` anchor was rejected because it would MISS block-scalar (`run: |`)
# invocations — the form most kit checks use — turning real checks UNACCOUNTED; the honest full fix is a
# run:-context awk matcher (boarded, and shared with ci-selftest-coverage.sh, which uses this same
# strip-and-match shape). See the HONEST CEILING note above. (Review finding HIGH-3, partial.)
_wf_exec() {
  sed 's/#.*//' "$1"/.github/workflows/*.yml 2>/dev/null \
    | grep -vE '^[[:space:]]*-?[[:space:]]*name:' \
    | grep -qE "conformance/$2([[:space:]]|$)"
}

# classify <root> <basename> -> REGISTERED | WORKFLOW | LIBRARY | UNACCOUNTED
#
# REGISTERED requires a REAL DISPATCH LINE, not a mention. The first version grepped for the bare
# basename anywhere in verify.sh, so a COMMENT satisfied it — and this very slice added a comment
# naming aggregate-coverage.sh, which made the check classify ITSELF as registered. Deleting its only
# execution site would then have left the coverage lock green while the check ran nowhere: the exact
# inverse of what it exists to prove. (Review finding M3/I3, CONFIRMED by both reviewers.)
classify() {
  _c_root="$1"; _c_b="$2"; _c_e=$(_esc "$2")
  if grep -qE "^[[:space:]]*check[[:space:]]+(control|doc)[[:space:]]+.*conformance/$_c_e([[:space:]]|$)" \
       "$_c_root/conformance/verify.sh" 2>/dev/null; then echo REGISTERED; return; fi
  if _wf_exec "$_c_root" "$_c_e"; then echo WORKFLOW; return; fi
  if _lib_listed "$_c_root" "$_c_b";                                                            then echo LIBRARY;  return; fi
  echo UNACCOUNTED
}

# _scan <root> -> 0 all accounted, 1 otherwise. Drives the REAL classify(), never a replica.
_scan() {
  _s_root="$1"; _s_rc=0; _s_n=0
  for _s_f in "$_s_root"/conformance/*.sh; do
    [ -f "$_s_f" ] || continue
    _s_n=$((_s_n + 1))
    _s_b=$(basename "$_s_f")
    case "$(classify "$_s_root" "$_s_b")" in
      UNACCOUNTED)
        echo "FAIL: $_s_b is in NEITHER suite and is not a declared library."
        echo "      Register it in conformance/verify.sh (portable), wire it as a workflow step"
        echo "      (kit-only), or declare it with a reason in conformance/aggregate-exclusions.txt."
        _s_rc=1 ;;
    esac
  done
  # A zero-file scan must FAIL. Without this, pointing the check at a tree with no conformance/
  # directory would report success over nothing at all.
  [ "$_s_n" != 0 ] || { echo "FAIL: scanned ZERO conformance/*.sh under '$_s_root' — refusing to pass vacuously"; _s_rc=1; }
  # A LIBRARY entry naming a file that does not exist is stale, and a stale list is how an exclusion
  # outlives its justification. An entry that is ALSO registered is a contradiction: it claims the
  # file is not a check while verify.sh runs it as one.
  if [ -f "$_s_root/conformance/aggregate-exclusions.txt" ]; then
    # awk's default field splitting handles BOTH tab and space. A `read` with IFS=' ' does NOT split
    # on tab, which silently yields "name<TAB>firstword" as the basename — caught here by the
    # positive selftest leg, not by any of the negative ones.
    for _e_b in $(grep -v '^[[:space:]]*#' "$_s_root/conformance/aggregate-exclusions.txt" | awk 'NF {print $1}'); do
      [ -f "$_s_root/conformance/$_e_b" ] || { echo "FAIL: exclusion lists '$_e_b', which does not exist (stale entry)"; _s_rc=1; }
      # The contradiction check must cover BOTH suites. Checking only verify.sh left a real bypass:
      # a check enforced ONLY as a workflow step could be relabelled a LIBRARY and silently retired —
      # delete the step, add one line here, and no gate objects. (Review finding M4, CONFIRMED.)
      _e_e=$(_esc "$_e_b")
      if grep -qE "^[[:space:]]*check[[:space:]]+(control|doc)[[:space:]]+.*conformance/$_e_e([[:space:]]|$)" \
           "$_s_root/conformance/verify.sh" 2>/dev/null; then
        echo "FAIL: '$_e_b' is declared a LIBRARY but verify.sh runs it as a check (contradiction)"; _s_rc=1
      fi
      if _wf_exec "$_s_root" "$_e_e"; then
        echo "FAIL: '$_e_b' is declared a LIBRARY but a workflow runs it as a check (contradiction)"; _s_rc=1
      fi
    done
  fi
  [ "$_s_rc" = 0 ] && echo "OK: all $_s_n conformance/*.sh accounted for (registered | workflow-wired | declared library)"
  return "$_s_rc"
}

# selftest() — the CI non-vacuity sweep mutates only lines ABOVE this marker, so every kill-assertion
# below stays live. Helpers placed above would be neutered along with the code they test.
if [ "$SELFTEST" = 1 ]; then
  d=$(mktemp -d) || { echo "aggregate-coverage --selftest: FAIL (no tmpdir)"; exit 1; }
  st=0
  _mk() { # _mk <name> — a fixture root with one check per category
    mkdir -p "$d/$1/conformance" "$d/$1/.github/workflows"
    printf 'check control a sh conformance/a.sh\n'      > "$d/$1/conformance/verify.sh"
    # verify.sh is ITSELF a conformance/*.sh and so must be accounted for like any other — in the
    # real tree it classifies WORKFLOW because ci.yml runs it. A fixture that omits this is not a
    # "fully-accounted" tree at all, which is how the positive leg earns its keep.
    printf 'run: sh conformance/b.sh\nrun: sh conformance/verify.sh --require\n' > "$d/$1/.github/workflows/ci.yml"
    printf '#\n' > "$d/$1/conformance/a.sh"
    printf '#\n' > "$d/$1/conformance/b.sh"
    printf '#\n' > "$d/$1/conformance/c.sh"
    printf 'c.sh\ta declared library, sourced never run\n' > "$d/$1/conformance/aggregate-exclusions.txt"
  }
  _mk good
  _scan "$d/good" >/dev/null || { echo "FAIL: selftest — a fully-accounted fixture must PASS"; st=1; }

  # Each category is load-bearing: drop its evidence and the file must become UNACCOUNTED.
  _mk drop_reg;  printf '\n' > "$d/drop_reg/conformance/verify.sh"
  _scan "$d/drop_reg" >/dev/null && { echo "FAIL: selftest — a check missing from BOTH suites must FAIL"; st=1; }
  _mk drop_wf;   printf '\n' > "$d/drop_wf/.github/workflows/ci.yml"
  _scan "$d/drop_wf" >/dev/null && { echo "FAIL: selftest — a workflow-only check losing its step must FAIL"; st=1; }
  _mk drop_lib;  printf '#\n' > "$d/drop_lib/conformance/aggregate-exclusions.txt"
  _scan "$d/drop_lib" >/dev/null && { echo "FAIL: selftest — an undeclared library must FAIL"; st=1; }

  # A reasonless exclusion must NOT satisfy the list — the whole point of naming exclusions.
  _mk noreason; printf 'c.sh\n' > "$d/noreason/conformance/aggregate-exclusions.txt"
  _scan "$d/noreason" >/dev/null && { echo "FAIL: selftest — a REASONLESS exclusion wrongly satisfied the list"; st=1; }

  # A stale entry (names a file that does not exist) must FAIL, or an exclusion outlives its subject.
  _mk stale; printf 'c.sh\treal\nghost.sh\tnames a file that does not exist\n' > "$d/stale/conformance/aggregate-exclusions.txt"
  _scan "$d/stale" >/dev/null && { echo "FAIL: selftest — a STALE exclusion entry wrongly passed"; st=1; }

  # A file both declared a library AND registered is a contradiction, not a belt-and-braces pass.
  _mk contra; printf 'c.sh\treal\na.sh\tclaims a REGISTERED check is not a check\n' > "$d/contra/conformance/aggregate-exclusions.txt"
  _scan "$d/contra" >/dev/null && { echo "FAIL: selftest — a LIBRARY entry contradicting verify.sh wrongly passed"; st=1; }

  # M3: a COMMENT mention in verify.sh must NOT count as REGISTERED.
  _mk comment_only
  printf '# see conformance/a.sh for the pattern\n' > "$d/comment_only/conformance/verify.sh"
  printf 'run: sh conformance/b.sh\nrun: sh conformance/verify.sh --require\n' > "$d/comment_only/.github/workflows/ci.yml"
  _scan "$d/comment_only" >/dev/null && { echo "FAIL: selftest — a COMMENT mention wrongly counted as REGISTERED"; st=1; }

  # M4: a workflow-enforced check must NOT be retirable by relabelling it a LIBRARY.
  _mk contra_wf
  printf 'c.sh\treal\nb.sh\tclaims a WORKFLOW-enforced check is not a check\n' > "$d/contra_wf/conformance/aggregate-exclusions.txt"
  _scan "$d/contra_wf" >/dev/null && { echo "FAIL: selftest — a LIBRARY entry contradicting a WORKFLOW step wrongly passed"; st=1; }

  # HIGH-3: a check named ONLY in a workflow COMMENT must NOT count as WORKFLOW. b.sh appears solely in
  # a `#` comment (its `run:` step is gone), so it must fall through to UNACCOUNTED. Before the arm was
  # tightened this fixture PASSed wrongly (the comment satisfied the permissive grep).
  _mk wf_comment
  printf 'run: sh conformance/verify.sh --require\n# runs conformance/b.sh as part of the suite\n' > "$d/wf_comment/.github/workflows/ci.yml"
  _scan "$d/wf_comment" >/dev/null && { echo "FAIL: selftest — a check named only in a workflow COMMENT wrongly counted as WORKFLOW"; st=1; }

  # M3: _esc must be load-bearing. a.sh is genuinely UNACCOUNTED; axsh is REGISTERED. If _esc were a
  # no-op, a.sh's regex (`.` as a wildcard) would spuriously match axsh's registration line, a.sh
  # would be misclassified REGISTERED, and the scan would wrongly PASS. It must FAIL.
  mkdir -p "$d/esc/conformance" "$d/esc/.github/workflows"
  printf 'check control axsh sh conformance/axsh\n' > "$d/esc/conformance/verify.sh"
  printf 'run: sh conformance/verify.sh --require\n' > "$d/esc/.github/workflows/ci.yml"
  printf '#\n' > "$d/esc/conformance/a.sh"
  _scan "$d/esc" >/dev/null && { echo "FAIL: selftest — _esc no-op let a.sh match axsh's registration"; st=1; }

  # THE VACUITY LEG (review M1): a conformance/ with NO .sh at all must FAIL via the zero-guard — not
  # via UNACCOUNTED. The old leg wrote conformance/verify.sh into the fixture, so it failed as
  # UNACCOUNTED (verify.sh isn't a scanned check) and mutating the zero-guard to always-true SURVIVED.
  # With zero .sh present, the ONLY thing that can fail this leg is the zero-guard, so that mutation
  # now goes RED.
  mkdir -p "$d/empty/conformance"
  _scan "$d/empty" >/dev/null && { echo "FAIL: selftest — a ZERO-file scan must FAIL, never pass vacuously"; st=1; }

  rm -rf "$d" 2>/dev/null || true
  if [ "$st" = 0 ]; then
    echo "OK: aggregate-coverage selftest (each of the 3 categories load-bearing; reasonless, stale"
    echo "                       and contradictory exclusions rejected; zero-file scan FAILs)"
    exit 0
  fi
  exit 1
fi

_scan "$ROOT"
