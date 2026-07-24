#!/bin/sh
# promotion-readiness-wired.sh — regression-lock for the change-class classifier: prove it is
# DERIVED + FAIL-SAFE (defaults UP, never silently ordinary) and that a mislabel cannot downgrade.
# Part of the Proportional Promotion Contract (docs/governance/promotion-contract.md), slice 2.
#   sh conformance/promotion-readiness-wired.sh [--selftest]
# Exit: 0 = ok · 1 = drift · 2 = usage. POSIX sh; dash-clean.
set -eu
cd "$(dirname "$0")/.." 2>/dev/null || true
PR="conformance/promotion-readiness.sh"

cls() { sh "$PR" --changed "$1" --class --no-verify 2>/dev/null; }  # <changed-file> -> class

# ---- the DISPOSITION lock (DRIFT-1 dual review) ------------------------------------------------
# promotion-readiness.sh's disposition() emits the cell a HUMAN READS when rendering the GO. It was
# graded by NOTHING: `control-plane:integration) echo "Agent autonomous — auto-merge on green"` would
# have left every gate green, because promotion-contract-documented.sh only reads the .md and
# governing-docs-current.sh only greps .md for the retired signature. The human's own decision
# surface could teach agent-autonomy at the decision point. Now the emitter's control-plane arms are
# graded by the SAME human-governance rules as the contract doc — statically, over the source's case
# arms (no need to execute the function).
#
# cp_dispositions <file>: print the emitted string of every `control-plane:*)` case arm, one per line.
cp_dispositions() {
  sed -n 's/^[[:space:]]*control-plane:[^)]*)[[:space:]]*echo[[:space:]]*"\([^"]*\)".*/\1/p' "$1"
}

# grade_dispositions <file>: FAIL if any control-plane disposition relaxes to non-human governance,
# or names no explicit human-governed disposition at all. Empty extraction => FAIL (no vacuous green).
grade_dispositions() {
  _src=$1; _bad=0; _n=0
  while IFS= read -r _cell; do
    [ -n "$_cell" ] || continue
    _n=$((_n + 1))
    if printf '%s' "$_cell" | grep -qiE 'no human gate|(agent|orchestrator|bot|model|llm)[ -]?(self|merge|commit|appl|tag|push|actuat|autonom|ratif|approv|govern)|by (the |an |a )?(agent|orchestrator|bot|model|llm)|unattended|self-govern|auto|delegat'; then
      echo "FAIL: control-plane disposition relaxed — the surfacing tells the human '$_cell'"; _bad=1; continue
    fi
    if ! printf '%s' "$_cell" | grep -qiE 'human-authored|control-plane-ratification|human ratif|human-gated|human gate|meta-control|N/A'; then
      echo "FAIL: control-plane disposition '$_cell' names no human-governed disposition"; _bad=1
    fi
  done <<EOF
$(cp_dispositions "$_src")
EOF
  if [ "$_n" -eq 0 ]; then
    echo "FAIL: no control-plane dispositions found in $_src — vacuous grade, not a pass"; return 1
  fi
  [ "$_bad" -eq 0 ] || return 1
  echo "OK: $_n control-plane disposition(s) human-governed"
  return 0
}

selftest() {
  st=0; d=$(mktemp -d)
  # Trap-clean: the derivation legs below create real git repos under $d. Leaking mktemp trees from
  # conformance selftests has twice filled this project's dev machine — clean up on every exit path.
  # `[ -n ]` guards the empty-var case so this can never widen to an unintended path.
  trap '[ -n "${d:-}" ] && rm -rf "$d"; :' EXIT INT TERM
  printf 'conformance/x.sh\n'                                        > "$d/cp.txt"
  printf 'src/auth/login.ts\n'                                       > "$d/sens.txt"
  printf 'deploy/id_rsa\n'                                           > "$d/key.txt"
  printf 'src/util/format.ts\n'                                      > "$d/ord.txt"
  printf 'src/util/format.ts\nsrc/auth/login.ts\nconformance/x.sh\n' > "$d/mix.txt"
  : > "$d/empty.txt"
  ck() {  # <want> <changed-file> <label>
    _g=$(cls "$2")
    if [ "$_g" = "$1" ]; then echo "PASS: $3 -> $_g"; else echo "FAIL: $3 want $1 got $_g"; st=1; fi
  }
  ck control-plane "$d/cp.txt"    "control-plane path"
  ck sensitive     "$d/sens.txt"  "sensitive path"
  ck sensitive     "$d/key.txt"   "private-key path (id_rsa) -> sensitive (superset of guard secret set)"
  ck ordinary      "$d/ord.txt"   "ordinary path"
  ck control-plane "$d/mix.txt"   "mixed -> highest wins"
  ck control-plane "$d/empty.txt" "empty set -> fail-safe up"
  ck control-plane "$d/no-such-file-$$.txt" "missing changed-file -> fail-safe up"
  # load-bearing negative: control-plane + sensitive must NOT downgrade to ordinary
  # (a classifier mutated to always-ordinary fails the cp/sens/mix checks above AND these).
  if [ "$(cls "$d/cp.txt")" = ordinary ]; then echo "FAIL: control-plane downgraded to ordinary"; st=1; fi
  if [ "$(cls "$d/sens.txt")" = ordinary ]; then echo "FAIL: sensitive downgraded to ordinary"; st=1; fi

  # --- DERIVATION legs (PROMOTION-PATH-QUOTING) -------------------------------------------------
  # Every `ck` leg above drives --changed, which BYPASSES the git derivation (promotion-readiness.sh
  # :61-66) — the branch where the path-quoting fail-open lived. A --changed fixture therefore passes
  # identically with and without the fix: a tautology. These legs stand up a REAL git repo and let the
  # check derive, which is the only construction that can observe the defect.
  # The producer cd's to its own ../, so each fixture carries COPIES of the producer and the guard
  # core. A fixture missing guard-core.sh would set GUARD_OK=0 and fail-safe to control-plane —
  # passing VACUOUSLY for the wrong reason. The `ordinary` liveness leg below is what excludes that:
  # it can only pass when the classifier is genuinely loaded and the derivation genuinely ran.
  derive_cls() {  # <repo> -> class derived from git, NOT from --changed
    ( cd "$1" && sh conformance/promotion-readiness.sh --class --no-verify 2>/dev/null )
  }
  mkrepo() {  # <repo> <path> : base commit on main, then <path> on a branch so a merge-base EXISTS
    _r="$1"; _p="$2"
    mkdir -p "$_r/conformance" "$_r/.claude/hooks"
    cp "$PR" "$_r/conformance/promotion-readiness.sh"
    cp .claude/hooks/guard-core.sh "$_r/.claude/hooks/guard-core.sh"
    ( cd "$_r" && git init -q && git config user.email t@t && git config user.name t \
        && git add -A && git commit -q -m base && git branch -M main && git checkout -q -b feat )
    mkdir -p "$_r/$(dirname "$_p")"
    printf 'x\n' > "$_r/$_p"
    ( cd "$_r" && git add -A && git commit -q -m probe )
  }
  dck() {  # <want> <path> <label> : build a repo committing <path>, derive, compare
    _want="$1"; _dr="$d/derive-$3"
    mkrepo "$_dr" "$2" >/dev/null 2>&1
    _got=$(derive_cls "$_dr")
    if [ "$_got" = "$_want" ]; then echo "PASS: derive $3 -> $_got"
    else echo "FAIL: derive $3 want $_want got $_got"; st=1; fi
  }
  # LIVENESS ANCHOR — must be `ordinary`. If the guard core failed to load, or the derivation
  # returned nothing, the fail-safe makes this control-plane and the leg goes RED. So a green here
  # is positive evidence that the two legs below are classifying a REAL derived path.
  dck ordinary     'src/util/format.ts'            ordinary-live
  # THE FIX: core.quotePath=true wraps a non-ASCII path in double quotes; the leading '"' defeats
  # is_control_plane_path, so this derives `ordinary` before the fix and `control-plane` after.
  dck control-plane '.github/workflows/déploy.yml' nonascii
  # `-z` is the STRICTLY STRONGER half: NUL output is never quoted, whereas core.quotePath=false
  # still quotes a path containing '"'. This leg is the only one that kills a -z-dropped mutant.
  dck control-plane '.github/workflows/de"ploy.yml' quote-in-name

  # --- the disposition lock, proven non-vacuous -------------------------------------------------
  if grade_dispositions "$PR" >/dev/null 2>&1; then
    echo "PASS: real control-plane dispositions are human-governed"
  else
    echo "FAIL: the real control-plane dispositions are NOT human-governed"; st=1
  fi

  # LOAD-BEARING NEGATIVE: an emitter that tells the human the agent merges on green must go RED.
  relax="$d/relaxed.sh"
  printf '    control-plane:integration) echo "Agent autonomous — auto-merge on green" ;;\n' > "$relax"
  if grade_dispositions "$relax" >/dev/null 2>&1; then
    echo "FAIL: a relaxed control-plane disposition passed (the surfacing is ungraded!)"; st=1
  else
    echo "PASS: relaxed control-plane disposition -> FAIL"
  fi

  # SELF-RATIFICATION at the decision point: the agent renders the ratification -> RED.
  selfr="$d/selfratify.sh"
  printf '    control-plane:integration) echo "control-plane-ratification rendered by the agent" ;;\n' > "$selfr"
  if grade_dispositions "$selfr" >/dev/null 2>&1; then
    echo "FAIL: agent-rendered ratification passed in the surfacing"; st=1
  else
    echo "PASS: agent-rendered ratification in the surfacing -> FAIL"
  fi

  # ANTI-VACUITY: an emitter with no control-plane arms at all must FAIL, never green.
  empty="$d/none.sh"
  printf '    ordinary:spike) echo "Agent autonomous (L3)" ;;\n' > "$empty"
  if grade_dispositions "$empty" >/dev/null 2>&1; then
    echo "FAIL: an emitter with ZERO control-plane dispositions passed (vacuous)"; st=1
  else
    echo "PASS: zero control-plane dispositions -> FAIL (no vacuous green)"
  fi

  if [ "$st" = 0 ]; then echo "OK: promotion-readiness-wired selftest"; else echo "FAIL: promotion-readiness-wired selftest"; fi
  return $st
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "") [ -f "$PR" ] || { echo "FAIL: missing $PR"; exit 1; }
      grade_dispositions "$PR" || exit 1
      echo "OK: promotion-readiness producer present"; exit 0 ;;
  *) echo "usage: promotion-readiness-wired.sh [--selftest]" >&2; exit 2 ;;
esac
