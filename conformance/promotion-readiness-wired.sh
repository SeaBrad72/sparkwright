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

  # --- RENAME legs (PROMOTION-RENAME-CLASS-DOWNGRADE / T2) --------------------------------------
  # Git detects renames by default and `--name-only` emits ONLY THE DESTINATION, so a control-plane
  # file moved to an ordinary path was classified on its destination alone and the §13 ceremony
  # downgraded to agent-autonomous. These legs need the SOURCE to exist in the BASE commit, which
  # mkrepo (which only ever ADDS a path on the branch) cannot express — hence a second builder.
  # FIXTURE CONSTRAINT (L10): <src> must be a THIRD control-plane path — never `conformance/
  # promotion-readiness.sh` (the producer this fixture copies in and EXECUTES via derive_cls) and never
  # `.claude/hooks/guard-core.sh`. Moving either destroys the script the leg needs, or sets GUARD_OK=0
  # so the leg passes VACUOUSLY through the control-plane fail-safe — green for the wrong reason.
  mkrepo_mv() {  # <repo> <src> <dst> : <src> committed on main, then `git mv`d to <dst> on the branch
    _r="$1"; _s="$2"; _dt="$3"
    mkdir -p "$_r/conformance" "$_r/.claude/hooks" "$_r/$(dirname "$_s")"
    cp "$PR" "$_r/conformance/promotion-readiness.sh"
    cp .claude/hooks/guard-core.sh "$_r/.claude/hooks/guard-core.sh"
    printf 'name: deploy\n' > "$_r/$_s"
    ( cd "$_r" && git init -q && git config user.email t@t && git config user.name t \
        && git config diff.renames true \
        && git add -A && git commit -q -m base && git branch -M main && git checkout -q -b feat )
    mkdir -p "$_r/$(dirname "$_dt")"
    ( cd "$_r" && git mv "$_s" "$_dt" && git commit -q -m rename )
  }
  # PREMISE ASSERTION — the leg below is MEANINGLESS unless the UNFIXED derivation would have collapsed
  # this rename. A host with diff.renames=false (global config, GIT_CONFIG_GLOBAL, or
  # GIT_CONFIG_PARAMETERS) emits BOTH paths even WITHOUT `--no-renames`, so the mutant SURVIVES and the
  # banner still credits the leg. obligation-lib.sh MEASURED exactly that (referenced BY NAME), which is
  # why mkrepo_mv pins `diff.renames true` in the fixture's OWN config (local outranks global, and the
  # producer runs with its cwd inside the fixture). This asserts the pin actually took: default flags
  # must collapse to EXACTLY ONE path. FAIL, never skip — a skipped premise is an unproven leg.
  assert_collapses() {  # <repo> : the default derivation must report exactly 1 path
    _ac=$( ( cd "$1" && git diff --name-only main...HEAD | grep -c . ) 2>/dev/null || echo 0 )
    if [ "$_ac" = 1 ]; then echo "PASS: premise — unfixed derivation collapses the rename to 1 path"
    else echo "FAIL: premise — unfixed derivation reported $_ac paths, expected 1; diff.renames pin did not take, so the rename leg proves NOTHING"; st=1; fi
  }
  # PAIRED LIVENESS ANCHOR — the destination path, committed as a plain ADD, MUST classify `ordinary`.
  # Without this the rename leg below is green for free: if `docs/deploy-notes.yml` were itself
  # control-plane for any reason, the leg would pass whether or not the rename was un-collapsed, and
  # it would keep passing with the fix reverted. This leg is what makes the next one mean something.
  dck ordinary     'docs/deploy-notes.yml'         rename-dest-live
  # THE FIX: the ONLY change is a git mv OFF a control-plane path. Pre-fix the derivation yields
  # `docs/deploy-notes.yml` alone -> `ordinary`; with `--no-renames` the deleted SOURCE reappears ->
  # `control-plane`. Deleting `--no-renames` from promotion-readiness.sh reds exactly this leg.
  _mv="$d/derive-rename"
  mkrepo_mv "$_mv" '.github/workflows/deploy.yml' 'docs/deploy-notes.yml' >/dev/null 2>&1
  assert_collapses "$_mv"
  _got=$(derive_cls "$_mv")
  if [ "$_got" = control-plane ]; then echo "PASS: derive rename-off-control-plane -> $_got"
  else echo "FAIL: derive rename-off-control-plane want control-plane got $_got — rename detection is ON by default and emits the destination only, so the derivation must pass --no-renames"; st=1; fi

  # --- NO-BASE FALLBACK legs (H3) ---------------------------------------------------------------
  # The `[ -n "$base" ]` else-branch is WORKTREE-vs-HEAD, not branch-vs-base. Measured: with one dirty
  # ORDINARY file it returned that single path, so n=1, the n=0 fail-safe never fired, and every
  # COMMITTED control-plane change was invisible -> `ordinary`. An underivable base is now a DERIVE
  # FAILURE, so it fail-safes to control-plane. This fixture has NO `main` and NO `origin/main`, so it
  # is the only leg that reaches that branch — and it is the branch EVERY adopter whose default branch
  # is not `main` (master/trunk/develop) actually runs.
  mkrepo_nobase() {  # <repo> : a control-plane file committed on a branch named neither main nor origin/main, + a dirty ordinary file
    _r="$1"
    mkdir -p "$_r/conformance" "$_r/.claude/hooks" "$_r/.github/workflows"
    cp "$PR" "$_r/conformance/promotion-readiness.sh"
    cp .claude/hooks/guard-core.sh "$_r/.claude/hooks/guard-core.sh"
    printf 'name: deploy\n' > "$_r/.github/workflows/deploy.yml"
    printf 'clean\n' > "$_r/ordinary.txt"          # TRACKED at base — see the note below
    ( cd "$_r" && git init -q && git config user.email t@t && git config user.name t \
        && git add -A && git commit -q -m base && git branch -M trunk )
    # The dirty path MUST be TRACKED-and-MODIFIED, never a fresh untracked file: `git diff --name-only
    # HEAD` does NOT report untracked paths, so an untracked file leaves the worktree diff EMPTY, n=0,
    # and the leg then passes through the n=0 fail-safe instead of through the derive-failure guard it
    # exists to test. Caught by mutation: with the guard removed the leg SURVIVED (vacuous green).
    printf 'dirty\n' > "$_r/ordinary.txt"          # the ONE dirty ordinary path that used to mask everything
  }
  _nb="$d/derive-nobase"
  mkrepo_nobase "$_nb" >/dev/null 2>&1
  # LIVENESS: prove the fixture really has no derivable base (else this leg tests the normal path).
  if ( cd "$_nb" && git merge-base HEAD origin/main >/dev/null 2>&1 || git merge-base HEAD main >/dev/null 2>&1 ); then
    echo "FAIL: no-base fixture HAS a derivable base — the H3 leg would not reach the fallback"; st=1
  else
    echo "PASS: premise — no-base fixture has neither main nor origin/main"
  fi
  _got=$(derive_cls "$_nb")
  if [ "$_got" = control-plane ]; then echo "PASS: derive no-base + dirty-ordinary -> $_got (fail-closed)"
  else echo "FAIL: derive no-base + dirty-ordinary want control-plane got $_got — an underivable base must be a DERIVE FAILURE, not a worktree diff that hides committed control-plane changes"; st=1; fi

  # --- NEWLINE-IN-FILENAME leg (H1) -------------------------------------------------------------
  # `tr '\0' '\n'` SPLITS a path containing a literal newline, and each fragment is classified alone.
  # That is a DOWNGRADE, not a cosmetic limit: is_control_plane_path carries SUFFIX-constrained patterns
  # (`agents/*.agent.md`), so `agents/evil<newline>.agent.md` becomes `agents/evil` + `.agent.md` and
  # NEITHER matches. The derivation now detects a newline in the NUL stream and fail-safes instead.
  mkrepo_nl() {  # <repo> : commit a path whose NAME contains a literal newline
    _r="$1"
    mkdir -p "$_r/conformance" "$_r/.claude/hooks" "$_r/agents"
    cp "$PR" "$_r/conformance/promotion-readiness.sh"
    cp .claude/hooks/guard-core.sh "$_r/.claude/hooks/guard-core.sh"
    ( cd "$_r" && git init -q && git config user.email t@t && git config user.name t \
        && git add -A && git commit -q -m base && git branch -M main && git checkout -q -b feat )
    _nl=$(printf 'agents/evil\n.agent.md')      # interior newline survives command substitution
    printf 'x\n' > "$_r/$_nl" 2>/dev/null || return 1
    ( cd "$_r" && git add -A && git commit -q -m crafted )
  }
  _nlr="$d/derive-newline"
  if mkrepo_nl "$_nlr" >/dev/null 2>&1; then
    # PREMISE: the fixture must really carry a newline in a path, else the leg proves nothing. Counted
    # from the NUL stream, which is exactly what the production detector reads.
    _nlc=$( ( cd "$_nlr" && git diff --name-only -z main...HEAD 2>/dev/null | LC_ALL=C tr -cd '\n' | wc -c | tr -d ' ' ) )
    if [ "${_nlc:-0}" -ge 1 ]; then echo "PASS: premise — fixture path really contains a literal newline"
    else echo "FAIL: premise — fixture carries NO newline in any path ($_nlc); the H1 leg proves nothing"; st=1; fi
    _got=$(derive_cls "$_nlr")
    if [ "$_got" = control-plane ]; then echo "PASS: derive newline-in-filename -> $_got (fail-closed, not split-and-classify)"
    else echo "FAIL: derive newline-in-filename want control-plane got $_got — a split path lets a SUFFIX-constrained control-plane pattern (agents/*.agent.md) miss both fragments"; st=1; fi
  else
    echo "FAIL: could not build a newline-in-filename fixture — the H1 leg did not run (do NOT read this as a pass)"; st=1
  fi

  # --- CLASSIFY-BEFORE-STRIP invariant leg (I5) -------------------------------------------------
  # The render strip MUST NOT move ahead of classify_path. This is not theoretical: `.env.example` has an
  # EXPLICIT early-return to `ordinary`, so `.env.example\001` classifies `sensitive` (it is not the
  # exempt literal) while its STRIPPED form classifies `ordinary`. Stripping first therefore LOWERS a
  # class — the fail-open direction — and the mutant that does it otherwise survives every other leg.
  # NOTE — this leg must read the RENDERED per-path label, NOT `--class`. `--class` computes the aggregate
  # in the aggregation loop, a DIFFERENT classify_path call site from the render line; a mutant that wraps
  # only the render line's classify_path in _render_safe SURVIVES a --class-driven leg (measured). The
  # per-path label in section 1 is the only output that observes the render site's classification.
  _envf="$d/env-invariant.txt"
  printf '.env.example\001\n' > "$_envf"
  _envout=$( sh "$PR" --no-verify --changed "$_envf" 2>&1 || true )
  case "$_envout" in
    *"[sensitive]"*) echo "PASS: the RENDER site classifies RAW bytes (.env.example+control byte -> [sensitive])" ;;
    *"[ordinary]"*) echo "FAIL: the render site labelled '.env.example'+control-byte [ordinary] — the strip has moved AHEAD of classify_path, and because .env.example has an explicit early-return to ordinary that LOWERS the class (fail-open)"; st=1 ;;
    *) echo "FAIL: could not read a per-path class label from the surfacing; the I5 invariant leg proves nothing"; st=1 ;;
  esac
  # And the aggregate must agree — the same path via --class (the aggregation call site).
  _got=$( sh "$PR" --class --no-verify --changed "$_envf" 2>/dev/null )
  if [ "$_got" = sensitive ]; then echo "PASS: the AGGREGATE site also classifies raw (-> sensitive)"
  else echo "FAIL: aggregate classified '$_got', want sensitive"; st=1; fi

  # --- RENDER-SAFETY leg (H2) -------------------------------------------------------------------
  # A crafted filename must not forge or hide a line on the surface a human reads to give the GO.
  # Feeds a control-byte-bearing path via --changed (the render path is shared) and asserts the raw
  # CR/ESC bytes do NOT reach stdout while the true aggregate line still does.
  _inj="$d/inject.txt"
  printf 'docs/note\r\033[2K\033[1A ordinary.md\n.github/workflows/real.yml\n' > "$_inj"
  _out=$( sh "$PR" --changed "$_inj" --no-verify 2>&1 || true )
  # DETECTOR NOTE: `grep '[\000-\010…]'` does NOT work — POSIX bracket expressions do not interpret
  # octal escapes, so that pattern matches literal backslashes/digits and reds on clean output (it did).
  # `tr` DOES interpret octal, so strip-and-compare is the correct detector. It is not tautological with
  # the fix: the fix strips per-PATH, this asserts over the WHOLE surfacing, so a leak from any other
  # un-stripped print site is still caught.
  _clean=$( printf '%s' "$_out" | LC_ALL=C tr -d '\000-\010\013-\037\177' )
  if [ "$_clean" != "$_out" ]; then
    echo "FAIL: render leaked raw control bytes from a path name — a crafted filename can forge the GO surface"; st=1
  else
    echo "PASS: render strips control bytes from crafted path names"
  fi
  case "$_out" in
    *"Change-class (aggregate): control-plane"*) echo "PASS: render-safety leg still reports the TRUE aggregate" ;;
    *) echo "FAIL: render-safety leg lost the true aggregate line (expected control-plane)"; st=1 ;;
  esac

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
