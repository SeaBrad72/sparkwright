#!/bin/sh
# selftest-hermetic.sh — the fixture-hermeticity lane (PHASE-B-HYGIENE H2 / FIXTURE-HERMETICITY-LANE).
#
# THE CLASS THIS CLOSES (third recurrence; panel #38 finding 3-H2): a check's --selftest reads
# something AMBIENT it did not itself set — global git identity/config (B2 §10-A9: 25 GO-leg FAILs
# on a runner with no identity), or the surrounding repo's notes-refs/object-store/kit markers
# (B3 HIGH-A, B4 H-4). All three instances were green on every reviewer's tree and dead on a runner;
# every prior cure was instance-scoped. This lane detects the CLASS: every targeted --selftest must
# pass under TWO FACES whose non-overlap is measured, not assumed:
#   face (a) STRIPPED ENV — B2 §10-A9's exact recipe: GIT_CONFIG_GLOBAL=/dev/null
#            GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.useConfigOnly
#            GIT_CONFIG_VALUE_0=true, HOME = a bare mktemp dir, GIT_AUTHOR_*/GIT_COMMITTER_* unset.
#            Catches ambient IDENTITY/CONFIG reads (a clone does NOT: it inherits global identity —
#            measured by the B2 round-3 executor, independently confirmed).
#   face (b) `git clone --no-local` of the containing repo into mktemp, selftest run inside it.
#            Catches ambient NOTES-REFS/OBJECT-STORE reads (a clone carries neither).
#
# MODES
#   --touched         changed files vs merge-base(HEAD, $HERMETIC_BASE [default origin/main]),
#                     intersected with the selftest-capable roster. Empty target => N/A, rc 0.
#                     An UNDERIVABLE base/merge-base FAILS LOUD (rc 1) — never a silent pass.
#   --all             the full roster. NOT wired per-PR (measured: ~163 selftests x ~1.4s median
#                     x 2 faces = minutes — incompatible with per-PR latency and with `git push`).
#   <path>...         explicit targets (any file path; face (b) needs it inside a git repo).
#   --selftest        this lane's own fixture battery (hermetic by construction).
#
# ROSTER semantics = conformance/ci-selftest-coverage.sh's exactly: scan conformance/*.sh
# scripts/*.sh hooks/pre-push; capability = `--selftest` survives comment-strip.
#
# EXCLUSIONS: conformance/hermetic-exclusions.txt (the aggregate-exclusions.txt precedent) —
# basename<TAB>reason; a reasonless entry FAILS the lane. That file is a BYPASS SURFACE and its
# header says so. It ships EMPTY.
#
# WHERE THIS BINDS (stated plainly — design self-review finding 3): the per-PR CI step is what
# BINDS; the pre-push rhythm line in skills/build is CONDUCT and will drift.
# ADOPTER SCOPE (security F6, design §10-A1): the per-PR `--touched` face is KIT-CI-only — no
# emitted adopter pipeline wires this step; adopters must wire it in their own pipeline or run
# `--touched`/`--all` manually. The exported binding today is this lane's `--selftest` via
# `verify.sh --require`. HONEST CEILINGS:
# touched-scope means a pre-existing ambient read in an UNTOUCHED selftest sleeps until that file
# is next edited (--all exists for a scheduled sweep); face (b) clones the repo's HEAD, so an
# UNCOMMITTED target fails loud with the reason (commit first — the pre-push/CI callers always run
# on committed trees); this lane does NOT close NON-VACUITY-HOOK-SCOPE (sweep REACHABILITY is a
# different axis); the 4/163 collateral sample does not prove the other 159 run collateral-free
# under strip — a genuinely-collateral case gets an exclusion-with-reason, never a silent skip.
#
# Usage: sh conformance/selftest-hermetic.sh [--touched | --all | <path>... | --selftest]
# Exit: 0 = every targeted selftest passed both faces (or N/A) · 1 = a face failed / lane misuse
#       (underivable base, unreasoned exclusion, uncommitted target) · 2 = bad usage. POSIX sh.
set -eu

TAB=$(printf '\t')
BASE="${HERMETIC_BASE:-origin/main}"
EXCL_FILE="conformance/hermetic-exclusions.txt"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

# roster — selftest-capable scripts of the CURRENT repo (relative paths), ci-selftest-coverage
# semantics: the fixed scan set, capability = --selftest survives comment-strip.
roster() {
  for _f in conformance/*.sh scripts/*.sh hooks/pre-push; do
    [ -f "$_f" ] || continue
    sed 's/#.*//' "$_f" | grep -q -- '--selftest' || continue
    printf '%s\n' "$_f"
  done | sort -u
}

# validate_exclusions — every non-comment line must be basename<TAB>reason. rc 1 on a reasonless
# entry (an unreasoned exclusion is a silent widening — the defect the file exists to prevent).
validate_exclusions() {
  [ -f "$EXCL_FILE" ] || return 0
  while IFS= read -r _l; do
    case "$_l" in ''|\#*) continue ;; esac
    _r=${_l#*"$TAB"}
    if [ "$_r" = "$_l" ] || [ -z "$_r" ]; then
      echo "FAIL: $EXCL_FILE entry '$_l' carries no <TAB>reason — an unreasoned exclusion is a silent bypass"
      return 1
    fi
  done < "$EXCL_FILE"
  return 0
}

# excluded <path> — 0 (and prints the disposition) iff the basename is excluded-with-reason.
excluded() {
  [ -f "$EXCL_FILE" ] || return 1
  _b=$(basename "$1")
  while IFS= read -r _l; do
    case "$_l" in ''|\#*) continue ;; esac
    if [ "${_l%%"$TAB"*}" = "$_b" ]; then
      echo "  EXCLUDED: $_b — ${_l#*"$TAB"} ($EXCL_FILE)"
      return 0
    fi
  done < "$EXCL_FILE"
  return 1
}

_repo_of() { git -C "$(dirname "$1")" rev-parse --show-toplevel 2>/dev/null; }

# run_faces <path> — run <path> --selftest under both faces. 0 = both pass; 1 = a face failed,
# with the FACE, TARGET and captured output named (the operator must not need a re-run to see why).
run_faces() {
  _tgt=$1
  _top=$(_repo_of "$_tgt") || { echo "FAIL: $_tgt is not inside a git repo (face (b) needs one)"; return 1; }
  # pwd -P: git rev-parse --show-toplevel answers the PHYSICAL path, so the target's dir must be
  # canonicalized the same way or the prefix-strip fails on a symlinked tmpdir (macOS /var -> /private/var).
  _abs=$(CDPATH='' cd "$(dirname "$_tgt")" && pwd -P)/$(basename "$_tgt")
  _rel=${_abs#"$_top"/}
  _o="$WORK/face.out"

  # face (a): stripped environment (B2 §10-A9's exact recipe)
  _hh="$WORK/home.$$"; mkdir -p "$_hh"
  _fa=0
  (
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_AUTHOR_DATE GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_COMMITTER_DATE || true
    HOME=$_hh; GIT_CONFIG_GLOBAL=/dev/null; GIT_CONFIG_SYSTEM=/dev/null
    GIT_CONFIG_COUNT=1; GIT_CONFIG_KEY_0=user.useConfigOnly; GIT_CONFIG_VALUE_0=true
    export HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
    cd "$_top" && sh "$_rel" --selftest
  ) >"$_o" 2>&1 || _fa=$?
  if [ "$_fa" != 0 ]; then
    echo "FAIL: face (a) stripped-env — $_rel reds with no ambient identity/config (rc $_fa)."
    echo "  The selftest reads git identity/config it did not set (green on a dev tree, dead on a runner)."
    sed 's/^/    /' "$_o" | tail -30
    return 1
  fi
  echo "  PASS: face (a) stripped-env — $_rel"

  # face (b): a --no-local clone (no notes refs, no ambient object store; grades HEAD)
  _c="$WORK/clone.$$"; rm -rf "$_c"
  git clone --no-local --quiet "$_top" "$_c" 2>>"$_o" || { echo "FAIL: face (b) — cannot clone $_top"; sed 's/^/    /' "$_o" | tail -10; return 1; }
  if [ ! -f "$_c/$_rel" ]; then
    echo "FAIL: face (b) — $_rel is not in the clone: it is uncommitted. Face (b) grades HEAD; commit before running the lane."
    rm -rf "$_c"; return 1
  fi
  _fb=0
  ( cd "$_c" && sh "$_rel" --selftest ) >"$_o" 2>&1 || _fb=$?
  rm -rf "$_c"
  if [ "$_fb" != 0 ]; then
    echo "FAIL: face (b) clone — $_rel reds inside a fresh git clone --no-local (rc $_fb)."
    echo "  The selftest reads ambient notes-refs/object-store/worktree state a clone does not carry."
    sed 's/^/    /' "$_o" | tail -30
    return 1
  fi
  echo "  PASS: face (b) clone — $_rel"
  return 0
}

# touched_set — changed files vs merge-base(HEAD, $BASE), intersected with the roster.
# An underivable base FAILS LOUD: a lane that silently passes when it cannot see the diff is
# satisfiable by breaking the diff derivation.
touched_set() {
  git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1 || {
    echo "FAIL: base '$BASE' is not resolvable — cannot derive the touched set (fetch the base, or set HERMETIC_BASE). Refusing to silent-pass." >&2
    return 1
  }
  _mb=$(git merge-base HEAD "$BASE" 2>/dev/null) || {
    echo "FAIL: no merge-base between HEAD and '$BASE' (shallow history?) — deepen the fetch. Refusing to silent-pass." >&2
    return 1
  }
  git diff --name-only "$_mb" HEAD | sort -u > "$WORK/changed"
  roster > "$WORK/roster"
  comm -12 "$WORK/changed" "$WORK/roster"
}

# run_lane <path>... — the shared engine for every non-selftest mode.
run_lane() {
  validate_exclusions || return 1
  _fail=0; _ran=0
  for _t in "$@"; do
    [ -f "$_t" ] || { echo "FAIL: target not found: $_t"; _fail=1; continue; }
    excluded "$_t" && continue
    _ran=$((_ran + 1))
    echo "TARGET: $_t (both faces)"
    run_faces "$_t" || _fail=1
  done
  if [ "$_fail" != 0 ]; then
    echo "selftest-hermetic: FAIL — a targeted --selftest is not hermetic (face + output above)."
    return 1
  fi
  echo "selftest-hermetic: OK ($_ran target(s) passed both faces)"
  echo "  note: the per-PR --touched binding is kit-CI-only; adopter trees carry only this lane's --selftest via verify.sh --require — wire --touched into your own pipeline for per-PR coverage (design §10-A1)"
  return 0
}

# ---------------------------------------------------------------------------- selftest
selftest() {
  sfail=0
  _self=$(CDPATH='' cd "$(dirname "$0")" && pwd)/$(basename "$0")
  st="$WORK/st"; mkdir -p "$st"

  # 1. AMBIENT-IDENTITY fixture: a selftest doing a BARE `git commit` (no inline -c identity)
  #    => face (a) must RED it, through the whole lane (main path, not a direct function call).
  st_repo "$st/fa"
  st_script "$st/fa/conformance/ambient-check.sh" 'bare'
  st_commit "$st/fa"
  rc=0; out=$( cd "$st/fa" && sh "$_self" conformance/ambient-check.sh 2>&1 ) || rc=$?
  st_expect "ambient-identity fixture REDs on face (a)" 1 "$rc"
  printf '%s\n' "$out" | grep -q 'face (a)' || { echo "FAIL: selftest — the failure did not NAME face (a)"; sfail=1; }

  # 2. HERMETIC TWIN (inline -c identity) => both faces pass, rc 0 (liveness anchor: a lane that
  #    reds everything would pass leg 1 and be worse than useless).
  st_repo "$st/ft"
  st_script "$st/ft/conformance/hermetic-check.sh" 'inline'
  st_commit "$st/ft"
  rc=0; ( cd "$st/ft" && sh "$_self" conformance/hermetic-check.sh ) >/dev/null 2>&1 || rc=$?
  st_expect "hermetic twin passes both faces" 0 "$rc"

  # 3. AMBIENT-NOTES fixture: a selftest reading a notes ref it did not create => face (a) passes
  #    (the ref exists in the working repo) but face (b) must RED it (a clone carries no notes).
  st_repo "$st/fb"
  st_script "$st/fb/conformance/notes-check.sh" 'notes'
  st_commit "$st/fb"
  ( cd "$st/fb" && git -c user.email=t@kit -c user.name=kit notes --ref=amb add -m x HEAD ) >/dev/null 2>&1
  rc=0; out=$( cd "$st/fb" && sh "$_self" conformance/notes-check.sh 2>&1 ) || rc=$?
  st_expect "ambient-notes fixture REDs on face (b)" 1 "$rc"
  printf '%s\n' "$out" | grep -q 'face (b)' || { echo "FAIL: selftest — the failure did not NAME face (b)"; sfail=1; }

  # 4. --touched, empty intersection => N/A, rc 0 (with the reason printed).
  st_repo "$st/fc"; st_commit "$st/fc"
  ( cd "$st/fc" && git update-ref refs/remotes/origin/main HEAD ) >/dev/null 2>&1
  rc=0; out=$( cd "$st/fc" && sh "$_self" --touched 2>&1 ) || rc=$?
  st_expect "--touched with no touched roster files = N/A rc 0" 0 "$rc"
  printf '%s\n' "$out" | grep -q 'N/A' || { echo "FAIL: selftest — empty --touched did not say N/A"; sfail=1; }

  # 5. --touched picks up a touched roster script (positive discrimination), and passes on the twin.
  ( cd "$st/fc" && git update-ref refs/remotes/origin/main HEAD ) >/dev/null 2>&1
  st_script "$st/fc/conformance/hermetic-check.sh" 'inline'
  st_commit "$st/fc"
  rc=0; out=$( cd "$st/fc" && sh "$_self" --touched 2>&1 ) || rc=$?
  st_expect "--touched targets the touched hermetic script, both faces pass" 0 "$rc"
  printf '%s\n' "$out" | grep -q 'hermetic-check.sh' || { echo "FAIL: selftest — --touched did not target the touched script"; sfail=1; }

  # 6. --touched with an UNDERIVABLE base => FAIL LOUD rc 1 (never a silent pass).
  st_repo "$st/fd"; st_commit "$st/fd"
  rc=0; out=$( cd "$st/fd" && sh "$_self" --touched 2>&1 ) || rc=$?
  st_expect "--touched with no resolvable base = FAIL LOUD" 1 "$rc"
  printf '%s\n' "$out" | grep -qi 'base' || { echo "FAIL: selftest — the underivable-base failure did not name the base"; sfail=1; }

  # 7. exclusion-with-reason skips (rc 0, disposition printed); a REASONLESS entry FAILS the lane.
  printf '# fixture exclusions\nambient-check.sh\tfixture: planted non-hermetic selftest, excluded to prove the escape is dispositioned\n' > "$st/fa/conformance/hermetic-exclusions.txt"
  rc=0; out=$( cd "$st/fa" && sh "$_self" conformance/ambient-check.sh 2>&1 ) || rc=$?
  st_expect "excluded-with-reason target is skipped (rc 0)" 0 "$rc"
  printf '%s\n' "$out" | grep -q 'EXCLUDED' || { echo "FAIL: selftest — exclusion disposition not printed"; sfail=1; }
  printf 'ambient-check.sh\n' > "$st/fa/conformance/hermetic-exclusions.txt"
  rc=0; ( cd "$st/fa" && sh "$_self" conformance/ambient-check.sh ) >/dev/null 2>&1 || rc=$?
  st_expect "a reasonless exclusion entry FAILS the lane" 1 "$rc"

  # 8. an EXCLUSIONS-ONLY diff (touched∩roster empty) with a reasonless entry must STILL fail rc 1
  #    (reviewer 3: before the fix, the N/A exit ran before validate_exclusions — a PR touching only
  #    hermetic-exclusions.txt could widen the bypass surface unvalidated).
  st_repo "$st/fe"; st_commit "$st/fe"
  ( cd "$st/fe" && git update-ref refs/remotes/origin/main HEAD ) >/dev/null 2>&1
  printf 'anything.sh\n' > "$st/fe/conformance/hermetic-exclusions.txt"   # REASONLESS
  st_commit "$st/fe"
  rc=0; out=$( cd "$st/fe" && sh "$_self" --touched 2>&1 ) || rc=$?
  st_expect "exclusions-only --touched diff with a reasonless entry FAILS (no N/A bypass)" 1 "$rc"
  printf '%s\n' "$out" | grep -q 'no <TAB>reason' || { echo "FAIL: selftest — the exclusions-only failure did not name the reasonless entry"; sfail=1; }

  [ "$sfail" -eq 0 ] && { echo "selftest-hermetic --selftest: OK"; return 0; }
  echo "selftest-hermetic --selftest: FAIL"; return 1
}

# --- selftest-only helpers (BELOW selftest() on purpose: the non-vacuity sweep mutates only lines
#     BEFORE the marker; kill logic and fixture builders must sit in the protected oracle region) ---
st_repo() { # <dir> — an empty git repo (identity passed inline everywhere; hermetic by construction)
  mkdir -p "$1/conformance"
  ( cd "$1" && git init -q ) >/dev/null 2>&1
}
st_commit() { # <dir> — commit everything, inline identity
  ( cd "$1" && git add -A >/dev/null 2>&1 && git -c user.email=t@kit -c user.name=kit commit -q -m fixture --allow-empty ) >/dev/null 2>&1
}
st_script() { # <path> <kind: bare|inline|notes> — a fixture conformance script with a --selftest
  case $2 in
    bare)   printf '#!/bin/sh\ncase "${1:-}" in --selftest) d=$(mktemp -d); ( cd "$d" && git init -q && echo x > f && git add f && git commit -q -m s ) || { rm -rf "$d"; echo FAIL; exit 1; }; rm -rf "$d"; echo OK ;; esac\n' > "$1" ;;
    inline) printf '#!/bin/sh\ncase "${1:-}" in --selftest) d=$(mktemp -d); ( cd "$d" && git init -q && echo x > f && git add f && git -c user.email=t@k -c user.name=t commit -q -m s ) || { rm -rf "$d"; echo FAIL; exit 1; }; rm -rf "$d"; echo OK ;; esac\n' > "$1" ;;
    notes)  printf '#!/bin/sh\ncase "${1:-}" in --selftest) git rev-parse -q --verify refs/notes/amb >/dev/null || { echo "FAIL: notes ref missing"; exit 1; }; echo OK ;; esac\n' > "$1" ;;
  esac
}
st_expect() { # <label> <want-rc> <got-rc>
  if [ "$2" = "$3" ]; then echo "PASS: selftest — $1"
  else echo "FAIL: selftest — $1 (want rc $2, got $3)"; sfail=1; fi
}

# ---------------------------------------------------------------------------- dispatch
case "${1:-}" in
  --selftest)
    selftest; exit $? ;;
  --touched)
    cd "$(git rev-parse --show-toplevel)" 2>/dev/null || { echo "selftest-hermetic: not a git repo" >&2; exit 2; }
    # Reviewer 3 (2026-08-07): validate BEFORE the empty-target N/A exit — an exclusions-only PR
    # (touched∩roster empty) must not slip a reasonless entry past the lane it widens.
    validate_exclusions || exit 1
    _set=$(touched_set) || exit 1
    if [ -z "$_set" ]; then
      echo "selftest-hermetic: N/A — no touched selftest-capable script (changed-set ∩ roster is empty vs $BASE)"
      exit 0
    fi
    # shellcheck disable=SC2086
    run_lane $_set; exit $? ;;
  --all)
    cd "$(git rev-parse --show-toplevel)" 2>/dev/null || { echo "selftest-hermetic: not a git repo" >&2; exit 2; }
    validate_exclusions || exit 1
    _set=$(roster)
    if [ -z "$_set" ]; then echo "selftest-hermetic: N/A — the roster is empty on this tree"; exit 0; fi
    # shellcheck disable=SC2086
    run_lane $_set; exit $? ;;
  "")
    echo "usage: selftest-hermetic.sh [--touched | --all | <path>... | --selftest]" >&2; exit 2 ;;
  *)
    run_lane "$@"; exit $? ;;
esac
