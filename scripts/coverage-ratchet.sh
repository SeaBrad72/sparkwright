#!/bin/sh
# coverage-ratchet.sh — stack-neutral "no-regression-below-baseline" coverage gate for
# brownfield adoption. A legacy repo can't hit the absolute 80% floor on day one, so during
# the adoption window gate on "coverage did not DROP below the recorded baseline" instead —
# then ratchet the baseline up each sprint toward 80% (the DoD target the waiver drives to).
#
# Stack-agnostic: you extract your current coverage percent per your stack and pass it in;
# this script only compares numbers and manages the baseline file.
#   usage: sh scripts/coverage-ratchet.sh <current-percent> [baseline-file]   (default .coverage-baseline)
#          sh scripts/coverage-ratchet.sh --selftest
# PASS if current >= baseline (prints the new floor when you improve); FAIL if it regresses.
# First run with no baseline file seeds the floor from <current> and passes.
set -eu

is_num() { printf '%s' "$1" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; }
# a coverage percent is a number in [0,100]
is_pct() { is_num "$1" && awk -v n="$1" 'BEGIN{exit !(n>=0 && n<=100)}'; }
# ge A B -> exit 0 if A >= B (decimal-tolerant)
ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>=b)}'; }
gt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>b)}'; }

ratchet() {
  cur=$1; base_file=$2
  if ! is_pct "$cur"; then echo "coverage-ratchet: current coverage '$cur' is not a percent in [0,100]" >&2; return 2; fi
  if [ ! -f "$base_file" ]; then
    printf '%s\n' "$cur" > "$base_file"
    echo "coverage-ratchet: seeded baseline $cur in $base_file (first run) — OK. Commit this file; raise it as coverage improves."
    return 0
  fi
  base=$(head -n1 "$base_file" | tr -d '[:space:]')
  if ! is_pct "$base"; then echo "coverage-ratchet: baseline '$base' in $base_file is not a percent in [0,100]" >&2; return 2; fi
  if ge "$cur" "$base"; then
    if gt "$cur" "$base"; then
      echo "coverage-ratchet: OK — $cur% ≥ baseline $base% (improved). Bump the floor: echo $cur > $base_file"
    else
      echo "coverage-ratchet: OK — $cur% holds the baseline $base%."
    fi
    return 0
  fi
  echo "FAIL: coverage regressed — $cur% is below the baseline $base% ($base_file). Coverage may not drop during the adoption ramp."
  return 1
}

selftest() {
  st=0; d=$(mktemp -d 2>/dev/null || printf '/tmp/crst.%s' "$$"); mkdir -p "$d"
  exp() { ratchet "$1" "$2" >/dev/null 2>&1 && g=0 || g=$?; if [ "$g" = "$3" ]; then echo "selftest PASS: $4"; else echo "selftest FAIL: $4 (want $3 got $g)"; st=1; fi; }
  # seed-on-first-run
  exp 41 "$d/a" 0 "no baseline -> seed + pass"
  [ "$(cat "$d/a")" = "41" ] && echo "selftest PASS: baseline seeded to 41" || { echo "selftest FAIL: baseline not seeded"; st=1; }
  # hold
  exp 41 "$d/a" 0 "equal to baseline -> pass"
  # improve
  exp 55.5 "$d/a" 0 "above baseline -> pass"
  # regress
  printf '60\n' > "$d/b"; exp 59.9 "$d/b" 1 "below baseline -> FAIL"
  # bad input
  exp abc "$d/b" 2 "non-numeric current -> error(2)"
  exp 150 "$d/b" 2 "out-of-range (>100) current -> error(2)"
  [ "$st" = "0" ] && echo "coverage-ratchet --selftest: OK"
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "") echo "usage: sh scripts/coverage-ratchet.sh <current-percent> [baseline-file] | --selftest" >&2; exit 2 ;;
  *) ratchet "$1" "${2:-.coverage-baseline}"; exit $? ;;
esac
