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

  # --- `--changed-files` LIST-SEAM legs (C8, GOVERNANCE-RECORD-PR-HAS-NO-DESIGN-BASIS) -----------
  # The list mode EXPORTS the derived change-set so a consumer never re-derives it. Its whole value is
  # that it is the SAME walk `--class` does, so these legs run on the SAME fixtures as the derivation
  # legs above — a list proven on a `--changed` listing would prove nothing (that path bypasses git
  # entirely, the tautology the derivation legs exist to avoid).
  # SETS $_lv and $_lrc IN THIS SHELL — never `_lv=$(lst …)`. A command substitution is a SUBSHELL, so
  # an rc assigned inside one is lost and the caller reads an UNBOUND variable under `set -u`
  # (measured on first write: the whole selftest died at the first list leg).
  lst() {  # <repo>
    _lrc=0
    _lv=$( ( cd "$1" && sh conformance/promotion-readiness.sh --changed-files ) 2>/dev/null ) || _lrc=$?
  }
  # LIVENESS — the list names the path the branch actually added, and nothing else. Reuses the
  # ordinary-live fixture, so a green here is positive evidence the derivation genuinely ran.
  _lr="$d/derive-ordinary-live"
  lst "$_lr"
  if [ "$_lrc" = 0 ] && [ "$_lv" = 'src/util/format.ts' ]; then
    echo "PASS: --changed-files lists exactly the derived change-set (rc 0)"
  else echo "FAIL: --changed-files rc=$_lrc list='$_lv', want rc 0 and exactly 'src/util/format.ts'"; st=1; fi
  # THE PROPERTY ITS CONSUMER DEPENDS ON — `--no-renames` reaches the LIST, not just the class. The
  # governance diff-shape guard in conformance/ceremony-binding.sh subsets this list against an
  # allowed set; if a `git mv` off a control-plane path emitted the destination ALONE, the moved-away
  # SOURCE would vanish from the set and a workflow deletion would launder through that gate. This is
  # the leg that makes "one derivation authority" mean something rather than sounding good.
  lst "$d/derive-rename"
  if [ "$_lrc" = 0 ] && printf '%s\n' "$_lv" | grep -qF '.github/workflows/deploy.yml' \
     && printf '%s\n' "$_lv" | grep -qF 'docs/deploy-notes.yml'; then
    echo "PASS: --changed-files un-collapses a rename (BOTH source and destination reach the consumer)"
  else echo "FAIL: --changed-files rc=$_lrc list='$_lv' — a rename collapsed to its destination, so a consumer subsetting this list cannot see the moved-away source"; st=1; fi
  # FAIL CLOSED, BOTH DERIVE-FAILURE CAUSES. `--class` fail-safes UP to control-plane; a LIST has no
  # equivalent safe value to invent, and an empty list would be read as "nothing outside my allowed
  # set" — fail-OPEN by construction. So the failure is an rc (3) and the list is EMPTY.
  lst "$d/derive-nobase"
  if [ "$_lrc" = 3 ] && [ -z "$(printf '%s' "$_lv" | tr -d '[:space:]')" ]; then
    echo "PASS: --changed-files with no resolvable base -> rc 3, nothing printed (fail closed)"
  else echo "FAIL: --changed-files no-base rc=$_lrc list='$_lv', want rc 3 and an EMPTY list — a consumer reading rc 0 + no paths would conclude the change-set is clean"; st=1; fi
  if [ -d "$d/derive-newline" ]; then
    lst "$d/derive-newline"
    if [ "$_lrc" = 3 ]; then
      echo "PASS: --changed-files with a newline-bearing path -> rc 3 (refuses to emit a set that would be read wrong)"
    else echo "FAIL: --changed-files newline rc=$_lrc, want 3 — a line-delimited list cannot carry that path, and splitting it hands the consumer fragments"; st=1; fi
  else
    echo "FAIL: the newline fixture is absent, so the --changed-files newline leg did not run (do NOT read this as a pass)"; st=1
  fi
  # THE HONEST EMPTY. A head its base already contains has an EMPTY change-set, and that is rc 0 with
  # no output — distinct from the derive failure above. ceremony-binding's hermetic fixtures depend on
  # this being a pass rather than a refusal.
  _lrc=0
  # RESTORE THE FIXTURE BRANCH (build review LOW-7). This probe moves HEAD to `main`; leaving it there
  # would silently change what EVERY later leg reusing this fixture derives — a leg that passes only
  # because a neighbour moved its HEAD is the shared-state class this suite avoids everywhere else.
  _lv=$( ( cd "$d/derive-ordinary-live" && git checkout -q main \
             && sh conformance/promotion-readiness.sh --changed-files; \
           _r=$?; git checkout -q feat 2>/dev/null || true; exit $_r ) 2>/dev/null ) || _lrc=$?
  if [ "$_lrc" = 0 ] && [ -z "$_lv" ]; then
    echo "PASS: --changed-files on a head its base already contains -> rc 0, empty list (honest, not a failure)"
  else echo "FAIL: --changed-files empty-diff rc=$_lrc list='$_lv', want rc 0 with no output"; st=1; fi
  # THE TWO SEAMS ARE MUTUALLY EXCLUSIVE — they carry DIFFERENT exit contracts (--class is advisory
  # and always 0; --changed-files fails closed with 3), so a run answering both would hand one caller
  # the other's contract and a `0` would be unreadable.
  _lrc=0
  ( sh "$PR" --class --changed-files ) >/dev/null 2>&1 || _lrc=$?
  if [ "$_lrc" = 2 ]; then echo "PASS: --class + --changed-files -> rc 2 usage refusal"
  else echo "FAIL: --class + --changed-files returned $_lrc, want 2"; st=1; fi

  # --- A2: CASE-INSENSITIVE CLASSIFICATION -------------------------------------------------------
  # On a case-INSENSITIVE filesystem (the macOS default, and this kit's own dev platform) a case
  # variant resolves to the REAL file while a byte-literal matcher classified it `ordinary` — so the
  # guard could be edited out of the way, and the required §13 gate derived `ordinary`, by typing one
  # capital letter. Measured before the fix: all four families below returned `ordinary`.
  _casef="$d/case-variants.txt"
  for _cv in ".Claude/hooks/guard-core.sh" ".github/Workflows/ci.yml" "Conformance/verify.sh" "Claude.md"; do
    printf '%s\n' "$_cv" > "$_casef"
    _got=$( sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
    if [ "$_got" = control-plane ]; then echo "PASS: case variant '$_cv' -> control-plane"
    else echo "FAIL: case variant '$_cv' want control-plane got $_got — a case variant resolves to the real control-plane file on a case-insensitive filesystem, so classifying it ordinary silently downgrades the §13 ceremony"; st=1; fi
  done
  # LOAD-BEARING EXACT-CASE ANCHORS. Folding the SUBJECT while leaving an uppercase-bearing PATTERN in
  # place declassifies that pattern — measured on the first draft of this change, which turned all four
  # of these `ordinary`. A generic "exact-case paths still work" fixture over .claude/ or skills/ passes
  # while these four are broken, so they are named individually and must stay named.
  for _cv in "CODEOWNERS" "CLAUDE.md" "DEVELOPMENT-STANDARDS.md" "DEVELOPMENT-PROCESS.md"; do
    printf '%s\n' "$_cv" > "$_casef"
    _got=$( sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
    if [ "$_got" = control-plane ]; then echo "PASS: exact-case anchor '$_cv' -> control-plane"
    else echo "FAIL: exact-case anchor '$_cv' want control-plane got $_got — the pattern list carries an uppercase byte that can never match a folded subject, so this governing document is now UNPROTECTED"; st=1; fi
  done
  # ⚠️ THE LEGS THAT MAKE PATTERN-LOWERCASING LOAD-BEARING. The four anchors above are NOT sufficient:
  # is_control_plane_path tries the LITERAL pattern first, so a pattern accidentally left uppercase
  # still matches its own exact-case path and those legs stay green (measured — this exact mutation
  # survived them). What an uppercase pattern actually breaks is every OTHER casing of that file, which
  # is the whole point of the fold. These legs fail the moment any pattern regains an uppercase byte.
  for _cv in "codeowners" "claude.md" "development-standards.md" "development-process.md"; do
    printf '%s\n' "$_cv" > "$_casef"
    _got=$( sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
    if [ "$_got" = control-plane ]; then echo "PASS: folded form '$_cv' -> control-plane"
    else echo "FAIL: folded form '$_cv' want control-plane got $_got — the matching pattern still carries an uppercase byte, so it can only ever match its own exact casing and every variant of this governing document is UNPROTECTED"; st=1; fi
  done

  # ⚠️ I2 — THE FOLD MUST NOT CAPTURE ORDINARY APPLICATION CODE. Folding every pattern
  # unconditionally was measured to make `src/Adapters/Repo.cs`, `Adapters/Http/StripeAdapter.cs` and
  # `Skills/Onboarding.cs` derive control-plane. PascalCase directories are the language convention in
  # profiles/dotnet, profiles/java-spring and profiles/kotlin, and `Adapters/` is the idiomatic
  # ports-and-adapters folder — so on a case-SENSITIVE runner every ordinary PR touching `Adapters/**`
  # would demand non-author ratification: a MERGE BLOCK clearable only with `--admin`, defeating §13
  # rather than enforcing it. The fold is therefore two-tier (kit-owned names always; generic directory
  # prefixes only where the filesystem actually makes the variant resolve). These legs pin the split.
  #
  # NOTE the legs below run on WHATEVER filesystem CI provides. On a case-sensitive runner they assert
  # `ordinary`; on a case-insensitive one the variant genuinely IS the same directory, so control-plane
  # is correct there. Assert the tier-1 invariant unconditionally and the tier-2 one only where it holds.
  for _cv in "src/Adapters/Repo.cs" "Adapters/Http/StripeAdapter.cs" "Skills/Onboarding.cs"; do
    printf '%s\n' "$_cv" > "$_casef"
    _got=$( sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
    if [ "$_got" = ordinary ]; then echo "PASS: PascalCase app path '$_cv' -> ordinary (I2: no false control-plane)"
    elif [ "$_got" = control-plane ] && sh -c ". \"$(dirname "$PR")/../.claude/hooks/guard-core.sh\" 2>/dev/null; _fs_case_insensitive" 2>/dev/null; then
      # ACCEPT ONLY `control-plane` here. An earlier draft accepted ANY value on a case-insensitive
      # filesystem, so `sensitive` or a garbled classifier output would have passed. And resolve the
      # guard core from $PR rather than a hardcoded `./` — a CWD-relative probe silently fails when the
      # selftest is run from anywhere else, sending the leg down the FAIL branch for the wrong reason.
      echo "PASS: PascalCase app path '$_cv' -> control-plane on a case-INSENSITIVE filesystem (the variant resolves to the real directory here, so this is correct)"
    else
      echo "FAIL: PascalCase app path '$_cv' want ordinary got $_got on a case-SENSITIVE filesystem — the fold is capturing ordinary application code and would merge-block every dotnet/java-spring/kotlin PR touching it"; st=1
    fi
  done

  # ★ FOLD MONOTONICITY, over EVERY TRACKED PATH. This is a PROPERTY, not an example, and no anchor list
  # can catch its violation — which is exactly how it was missed. The fold's only sound invariant is:
  #     is_control_plane_path(p)  =>  is_control_plane_path(tolower(p))
  # Folding may PRESERVE control-plane-ness, never CREATE it. A draft where the always-folded tier was
  # BROADER than the canonical pattern set violated it for four real files — `.github/ISSUE_TEMPLATE/*`,
  # `.github/PULL_REQUEST_TEMPLATE.md`, `.claude/README.md` — flipping GitHub's own uppercase
  # conventions to control-plane on every platform and merge-blocking any PR that edits a bug-report
  # template. Runs with the fold's conditional tier DISABLED so it tests the unconditional tier alone,
  # which is where the invariant must hold on every filesystem.
  # ★★★ THE `ALIVE` SENTINEL (GUARD-PATH-ENUMERATION-INCOMPLETE S2 M4), AND IT APPLIES TO **BOTH**
  # `sh -c … 2>/dev/null` BLOCKS IN THIS FILE — this one and the synthetic-family one below.
  # THE DEFECT IT CLOSES: both blocks report violations by PRINTING them, and both are read as
  # "empty output ⇒ no violations". But `sh -c` parses its whole script before running a line of it,
  # so ONE typo anywhere inside makes the block emit NOTHING — and with stderr sent to /dev/null the
  # sweep announced a clean tree it had never walked. A silent always-pass is precisely what the
  # kit's own non-vacuity law forbids: the block must PROVE it ran.
  # HOW: the block's last act is to print `ALIVE`. The evaluator requires that sentinel as the FINAL
  # line; anything else — empty output, a truncated run, a shell that died mid-sweep — is a FAIL, not
  # a pass. Each site carries a syntax-error mutant leg proving the flip.
  #
  # _sentinel_eval <raw-output> — sets $_sv_state to NORUN (no sentinel: the block never completed),
  # DIRTY (ran, and reported violations) or CLEAN (ran, nothing to report), and $_sv_bad to the
  # reported lines with the sentinel removed. Shared by both sites so neither can drift its own
  # liveness rule. (`NORUN`, not `DEAD` — the synthetic block already uses `DEAD` in its own
  # violation vocabulary for "classifies ordinary", and two meanings for one token in one diagnostic
  # is how a reader mis-diagnoses a red.)
  _sentinel_eval() {
    _sv_bad=$( printf '%s\n' "$1" | grep -v '^ALIVE$' | grep -v '^[[:space:]]*$' || true )
    if [ "$( printf '%s\n' "$1" | tail -1 )" != ALIVE ]; then _sv_state=NORUN
    elif [ -n "$_sv_bad" ]; then _sv_state=DIRTY
    else _sv_state=CLEAN; fi
  }

  _inv_core="$(dirname "$PR")/../.claude/hooks/guard-core.sh"
  if [ -f "$_inv_core" ] && command -v git >/dev/null 2>&1 && git -C "$(dirname "$PR")/.." rev-parse HEAD >/dev/null 2>&1; then
    # THE BODY IS A VALUE, not an inline string, so the mutant leg below can run the SAME body with a
    # syntax error appended and prove the sentinel actually discriminates.
    _inv_body='
      . '"$_inv_core"' 2>/dev/null
      _kit_fs_ci=0
      while IFS= read -r p; do
        case "$p" in *[A-Z]*) : ;; *) continue ;; esac
        if is_control_plane_path "$p"; then
          l=$(printf "%s" "$p" | LC_ALL=C tr "A-Z" "a-z")
          is_control_plane_path "$l" || printf "%s\n" "$p"
        fi
      done
      printf "ALIVE\n"'
    _inv_raw=$( git -C "$(dirname "$PR")/.." ls-files | sh -c "$_inv_body" 2>/dev/null )
    _sentinel_eval "$_inv_raw"
    case "$_sv_state" in
      CLEAN) echo "PASS: fold monotonicity holds over every tracked path (control-plane is preserved by folding, never created) — sweep proven ALIVE" ;;
      NORUN) echo "FAIL: the fold-monotonicity sweep produced NO ALIVE sentinel — the block did not run to completion (a parse error, a dead \`.\`, or a shell that died mid-sweep), and its empty output was previously read as a clean tree"; st=1 ;;
      *)
        echo "FAIL: fold monotonicity VIOLATED — these paths classify control-plane but their folded form does not, so the always-folded tier is BROADER than the canonical set and is MANUFACTURING control-plane classifications (each one merge-blocks an ordinary PR):"
        printf '%s\n' "$_sv_bad" | sed 's/^/         /'
        st=1 ;;
    esac
    # LOAD-BEARING NEGATIVE for the sentinel: the same body made unparseable must read as DEAD, not
    # as a clean sweep. Without this leg the sentinel is decoration.
    # ⚠️ THE SYNTAX ERROR GOES AT THE **TOP** OF THE BODY, AND THAT IS MEASURED, NOT STYLISTIC.
    # `sh -c` does NOT parse the whole string before running it — it reads and executes
    # incrementally, so an error APPENDED after the body lets every earlier line (the sentinel
    # included) run first and the mutant reports CLEAN. Measured on this machine's `sh` and on
    # `/bin/sh`: `sh -c 'printf "ALIVE\n"<newline>if then fi'` prints ALIVE and THEN errors, rc 2.
    # An error at the top is the faithful model of the defect: nothing runs, output is empty, and
    # empty output is exactly what the pre-sentinel check read as a clean sweep.
    # `|| true` IS LOAD-BEARING, not tidiness: this mutant is MEANT to exit non-zero, and under
    # `set -e` a command substitution whose command fails ABORTS the whole selftest — measured here
    # on first write, at 39 of 101 legs, rc 2, with no diagnostic naming the cause. Same shape as the
    # `changeset_at_api_cap` caller's guard in agent-boundary.sh.
    _inv_mraw=$( git -C "$(dirname "$PR")/.." ls-files | sh -c "if then fi
$_inv_body" 2>/dev/null ) || true
    _sentinel_eval "$_inv_mraw"
    if [ "$_sv_state" = NORUN ]; then echo "PASS: a syntax-error mutant of the fold-monotonicity block reads as NORUN, not as a clean sweep"
    else echo "FAIL: a syntax-error mutant of the fold-monotonicity block evaluated to '$_sv_state' — the ALIVE sentinel does not discriminate, so an unparseable sweep still ships green"; st=1; fi
  else
    echo "FAIL: could not run the fold-monotonicity sweep (guard core or git unavailable) — do NOT read this as a pass"; st=1
  fi

  # ★ THE SAME INVARIANTS, OVER SYNTHETIC NEVER-TRACKED FAMILY PATHS (GUARD-PATH-ENUMERATION-INCOMPLETE
  # S1). ⚠️ The sweep above walks `git ls-files`, and that census is BLIND on exactly the territory this
  # slice added: `.claude/commands/` and `.claude/plugins/` do not exist in the tree at all (tracked or
  # on disk), and `scripts/zz-*` / `profiles/zz-*` are names no file carries. A tracked-path sweep
  # therefore proves the subset relation only where it was never in doubt — which is why the family
  # work needs its own legs rather than inheriting that green. Three properties, evaluated by calling
  # the two matcher tiers DIRECTLY on invented paths:
  #   liveness  — each synthetic family path must classify control-plane AT ALL. Without this anchor
  #               every implication below is vacuously true and the whole block is decoration.
  #   subset    — _cpp_kitowned(p) => _cpp_match(p). Tier 1 folds on every platform, so it may never be
  #               BROADER than the set it folds; when it was, four real GitHub-convention files flipped
  #               ordinary -> control-plane on every platform.
  #   monotone  — is_control_plane_path(P) => is_control_plane_path(tolower(P)), with the conditional
  #               tier forced OFF so the unconditional tier is tested on every filesystem.
  # The negatives are load-bearing: a component merely ENDING in a family name (`myscripts/`,
  # `foo.claude/`, `subagents.md`) is NOT a member, and if it ever becomes one this block goes RED.
  # ⚠️ THE SECOND `sh -c` SITE, AND IT CARRIES THE SAME `ALIVE` SENTINEL (S2 M4). The row that opened
  # this work named only the sweep above; the S2 probe found this block has the identical shape and
  # the identical silent-always-pass failure mode — a parse error anywhere inside it emitted nothing,
  # stderr went to /dev/null, and `[ -z "$_syn_out" ]` announced every invariant intact.
  if [ -f "$_inv_core" ]; then
    _syn_body='
      . '"$_inv_core"' 2>/dev/null
      _kit_fs_ci=0
      for p in .claude/commands/x.md .claude/plugins/y.json .claude/newdir/deep/z.txt \
               vendor/pkg/.claude/commands/x.md scripts/zz-nonexistent.sh \
               scripts/zz-new/deep.sh profiles/zz-fake/ci.yml \
               profiles/zz-fake/scaffold/scripts/build.sh AGENTS.md REQUIRED-CHECKS.md \
               .gitattributes docs/.gitattributes; do
        if ! is_control_plane_path "$p"; then printf "DEAD %s\n" "$p"; fi
        if _cpp_kitowned "$p"; then
          if ! _cpp_match "$p"; then printf "SUBSET %s\n" "$p"; fi
        fi
        u=$(printf "%s" "$p" | LC_ALL=C tr "a-z" "A-Z")
        if is_control_plane_path "$u"; then
          l=$(printf "%s" "$u" | LC_ALL=C tr "A-Z" "a-z")
          if ! is_control_plane_path "$l"; then printf "MONOTONE %s\n" "$u"; fi
        fi
      done
      for n in myscripts/x.sh myprofiles/x.yml foo.claude/settings.json v2.claude/x subagents.md; do
        if is_control_plane_path "$n"; then printf "OVERMATCH %s\n" "$n"; fi
      done
      # ★ THE RELIEVED SUBTREES, ORDINARY IN **BOTH TIERS** (GUARD-CLAUDE-HOME-INSTRUMENTATION-FP).
      # `.claude/projects/` and `.claude/plans/` are the harness'"'"'s own workspace — agent memory and
      # plan-mode files — which S1'"'"'s `*/.claude/*` family caught as collateral, breaking both
      # workflows in every session (measured 2026-08-17). The relief arm sits FIRST in each `case`.
      # ⚠️ WHAT THIS BLOCK IS AND IS NOT WORTH, STATED HONESTLY (an earlier draft over-claimed it and
      # a reviewer refuted the claim by measurement). A one-sided RELIEF is ALREADY caught at the
      # verdict level on every filesystem: relief missing from Tier 2 reds the lowercase relief ALLOW
      # legs, and relief missing from Tier 1 reds the CASE-VARIANT relief ALLOW leg FS-independently,
      # because once `_cpp_kitowned` returns 0 the wrapper returns immediately and the conditional
      # Tier-2 re-check never runs. These RELIEF legs are therefore a DIRECT restatement of the
      # Tier 1 ⊆ Tier 2 invariant at the tier boundary — cheap, and they name the violation instead
      # of leaving a reader to infer it from a verdict — not the only thing standing between the kit
      # and a one-sided relief. The leg that IS load-bearing on its own is BRIGHTLINE-T1 below.
      for r in .claude/projects/x .claude/plans/x.md .claude/projects/p1/memory/MEMORY.md \
               /home/kituser/.claude/projects/p1/memory/x.md /home/kituser/.claude/plans/x.md; do
        if is_control_plane_path "$r"; then printf "RELIEF %s\n" "$r"; fi
        if _cpp_kitowned "$r";        then printf "RELIEF-T1 %s\n" "$r"; fi
        if _cpp_match "$r";           then printf "RELIEF-T2 %s\n" "$r"; fi
      done
      # …and the bright line the relief must NOT cross, evaluated through the same direct calls: three
      # names in the SAME directory that stay control-plane. Without these the relief block above
      # would pass just as happily against a relief arm widened to the whole `.claude/` family.
      # ⚠️ THE **TIER-1** HALF IS ASSERTED SEPARATELY, AND IT IS NOT REDUNDANT — MEASURED. A widening
      # confined to `_cpp_kitowned` leaves `is_control_plane_path` answering control-plane on a
      # case-INSENSITIVE filesystem (the conditional Tier-2 re-check catches it) and on the lowercase
      # spelling everywhere, so the `BRIGHTLINE` line above sees NOTHING and the guard-route
      # case-variant fixture kills it only on a case-SENSITIVE runner. Calling Tier 1 directly is what
      # makes that mutant die on every platform instead of only on CI.
      for b in .claude/settings.json /home/kituser/.claude/hooks/x /home/kituser/.claude/agents/y.md; do
        if ! is_control_plane_path "$b"; then printf "BRIGHTLINE %s\n" "$b"; fi
        if ! _cpp_kitowned "$b";        then printf "BRIGHTLINE-T1 %s\n" "$b"; fi
      done
      printf "ALIVE\n"
      exit 0'
    _syn_out=$( sh -c "$_syn_body" 2>/dev/null )
    _sentinel_eval "$_syn_out"
    case "$_sv_state" in
      CLEAN) echo "PASS: synthetic never-tracked family paths — live (all control-plane), Tier 1 ⊆ Tier 2, fold-monotone, no family over-match on look-alike siblings, and the relieved workspace subtrees are ordinary in BOTH tiers while the bright line holds — block proven ALIVE" ;;
      NORUN) echo "FAIL: the synthetic family-path block produced NO ALIVE sentinel — it did not run to completion (a parse error, a dead \`.\`, or a shell that died mid-block), and its empty output was previously read as every invariant holding"; st=1 ;;
      *)
        echo "FAIL: the synthetic family-path invariants broke — DEAD=classifies ordinary (derivation lost), SUBSET=Tier 1 broader than Tier 2 (manufacturing classifications), MONOTONE=folding CREATED control-plane-ness, OVERMATCH=a look-alike sibling was captured, RELIEF/RELIEF-T1/RELIEF-T2=the .claude/projects|plans relief is MISSING or ONE-SIDED (the harness's own memory and plan-mode writes are broken again), BRIGHTLINE/BRIGHTLINE-T1=the relief widened past projects|plans onto a real instrumentation surface:"
        printf '%s\n' "$_sv_bad" | sed 's/^/         /'
        st=1 ;;
    esac
    # LOAD-BEARING NEGATIVE for this site's sentinel, same shape as the sweep's above.
    # Error at the TOP and `|| true`, for the two measured reasons recorded at the sweep's mutant
    # above (incremental parsing; `set -e` on a failing command substitution).
    _syn_mout=$( sh -c "if then fi
$_syn_body" 2>/dev/null ) || true
    _sentinel_eval "$_syn_mout"
    if [ "$_sv_state" = NORUN ]; then echo "PASS: a syntax-error mutant of the synthetic family-path block reads as NORUN, not as every invariant holding"
    else echo "FAIL: a syntax-error mutant of the synthetic family-path block evaluated to '$_sv_state' — the ALIVE sentinel does not discriminate here, so an unparseable block still ships green"; st=1; fi
  else
    echo "FAIL: could not evaluate the synthetic family-path invariants (guard core unavailable) — do NOT read this as a pass"; st=1
  fi

  # ══ S2 M3 — THE CENSUS / AGREEMENT LOCK ═════════════════════════════════════════════════════════
  # TWO legs, and their evidential value is NOT the same. Saying so in the check's own output is the
  # point: a green here must not be read as proving more than it does.
  #
  #   LEG (a) — THE RE-FORK TRIPWIRE. Over every tracked path: guard-CP ⇒ class-CP. It is GREEN BY
  #     CONSTRUCTION today, because classify_path DELEGATES to is_control_plane_path — the two cannot
  #     differ while the guard loads. That is exactly why it exists: it is the leg that reds the day
  #     someone re-implements the control-plane set on the merge side, which is the ten-day
  #     guard-ALLOW/class-ordinary split (GUARD-PATH-ENUMERATION-INCOMPLETE S1) made un-repeatable.
  #     Its killer mutant below is NON-OPTIONAL — a by-construction-green leg with no mutant is
  #     decoration.
  #   LEG (b) — THE LIVE PROPERTY S2 CREATES. Every ADAPTER-DECLARED path derives control-plane at
  #     `--class`. Born meaningful, not vacuous: before S2 it was false for three of the fourteen
  #     declared entries, and dropping the union consult reds it today.
  #
  # ⚠️ DIRECTION IS ONE-WAY, DELIBERATELY (design §4, vet Q5). `class ⊇ guard` and `class ⊇ union`.
  # The converses are NOT asserted and must not be: the union legitimately overlaps the guard set
  # (four manifests declare `.github/workflows/`, `CODEOWNERS`), so `guard ⊇ union` is factually
  # false at HEAD and would red on day one. Whether a union-only discriminator still EXISTS is
  # phase-gate's sole authority (its T3 canary); two authorities for one property diverge the day the
  # manifest set shifts. The union-only figure below is therefore REPORTED and asserted NOWHERE.
  #
  # ⚠️ LEG (b) IS EVALUATED OVER THE **DECLARED ENTRIES**, NOT OVER `git ls-files` — and that is a
  # measurement, not a preference. NONE of the three union-only entries (`GEMINI.md`, `.gemini/`,
  # `.cursor/rules/`) is tracked in this repository, so a tracked-path-only leg (b) would match zero
  # union-only paths and stay green with the union consult deleted: vacuous in exactly its target
  # case. The entries are probed directly instead, and each probe is verified to actually match the
  # entry before it is used.
  _cen_repo="$(dirname "$PR")/.."
  _cen_ad="${KIT_ADAPTERS_DIR:-$_cen_repo/adapters}"
  # _census <classifier-script> <cwd-root> — writes leg-a divergences ("A <path>") and leg-b
  # divergences ("B <entry> <probe> <class>") to stdout, plus a final ALIVE sentinel. Takes the
  # classifier as an ARGUMENT so the shipped build and each mutant run the IDENTICAL census.
  _census() {
    _cn_root="$2"; _cn_all="$d/census-all.txt"; _cn_probe="$d/census-probe.txt"
    git -C "$_cen_repo" ls-files > "$_cn_all" 2>/dev/null || return 1
    # ONE classifier invocation for the whole tree — the per-path render IS the classifier's own
    # verdict for each path, so this reads the real thing rather than re-deriving it.
    ( cd "$_cn_root" && sh "$1" --no-verify --changed "$_cn_all" ) 2>/dev/null \
      | awk '/^   \[/ { c=$0; sub(/^   \[/,"",c); sub(/\].*$/,"",c); p=$0; sub(/^   \[[a-z-]*\] /,"",p); print c "\t" p }' \
      > "$d/census-class.tsv"
    # LEG (a), in-process against the guard's own matcher — ONE pass, which also produces the
    # informational union-only tally (a second sweep for it cost 3s of the budget for a figure this
    # loop already has every input for).
    awk -F'\t' '{print $2 "\t" $1}' "$d/census-class.tsv" | sh -c '
      . '"$_inv_core"' 2>/dev/null
      . '"$(dirname "$PR")/union-lib.sh"' 2>/dev/null
      _u=$( kit_union_derive "'"$_cen_ad"'" ) || _u=""
      case "$_u" in *[A-Z]*) _u=$( printf "%s" "$_u" | LC_ALL=C tr "A-Z" "a-z" ) ;; esac
      _only=0
      while IFS="	" read -r p c; do
        [ -n "$p" ] || continue
        if is_control_plane_path "$p"; then
          [ "$c" = control-plane ] || printf "A %s (class said %s)\n" "$p" "$c"
        elif kit_path_in_union "$p" "$_u"; then
          _only=$((_only+1))
        fi
      done
      printf "ONLY %s\n" "$_only"
      printf "ALIVE\n"'
  }
  # THE PROBE SET — one probe path per declared union entry, each proven to match its own entry
  # before it is trusted. An entry that cannot be probed is a FAIL, never a skip.
  _cen_probes=$( sh -c '
    . '"$(dirname "$PR")/union-lib.sh"' 2>/dev/null
    u=$( kit_union_derive "'"$_cen_ad"'" ) || u=""
    # `set -f` FOR THE SAME REASON kit_path_in_union carries it (REV-M1/SEC-F4): `for e in $u`
    # needs WORD splitting but must NOT get PATHNAME expansion. A manifest entry such as
    # `conformance/*` would otherwise expand to the existing files, so this loop would probe real
    # filenames instead of the DECLARED ENTRY — leg (b) would silently stop speaking for the entry
    # it names, and a glob entry matching nothing on disk would vanish from the probe set entirely.
    set -f
    for e in $u; do
      case "$e" in
        */) p="${e}zz-census-probe.txt" ;;
        *"*"*) p=$( printf "%s" "$e" | sed "s%[*]%zz-census-probe%g" ) ;;
        *"?"*) p=$( printf "%s" "$e" | sed "s%[?]%z%g" ) ;;
        *) p="$e" ;;
      esac
      if kit_path_in_union "$p" "$u"; then printf "%s\t%s\n" "$e" "$p"
      else printf "%s\tUNPROBEABLE\n" "$e"; fi
    done
    set +f
    printf "ALIVE\n"' 2>/dev/null ) || _cen_probes=""
  _sentinel_eval "$_cen_probes"
  if [ "$_sv_state" = NORUN ]; then
    echo "FAIL: the census could not derive the adapter-union probe set (no ALIVE sentinel) — do NOT read this as a pass"; st=1
  elif [ -z "$_sv_bad" ]; then
    echo "FAIL: the census derived ZERO adapter-union entries, so leg (b) would be vacuous — this repository declares controlPlanePaths in its manifests, so an empty union is a broken derivation, not an empty set"; st=1
  else
    _cen_nprobe=$( printf '%s\n' "$_sv_bad" | grep -c . )
    _cen_unpr=$( printf '%s\n' "$_sv_bad" | grep -c 'UNPROBEABLE' || true )
    if [ "$_cen_unpr" != 0 ]; then
      echo "FAIL: $_cen_unpr adapter-union entr(y|ies) could not be turned into a probe path, so leg (b) cannot speak for them:"
      printf '%s\n' "$_sv_bad" | grep 'UNPROBEABLE' | sed 's/^/         /'; st=1
    fi
    # WHICH MANIFESTS CONTRIBUTED (vet L-3) — so a `_TEMPLATE` edit that widens the union stays
    # legible in the check's own output rather than having to be inferred from a path list.
    _cen_mans=$( sh -c '
      for m in "'"$_cen_ad"'"/*/adapter.json; do
        [ -f "$m" ] || continue
        n=$( jq -r ".controlPlanePaths[]? // empty" "$m" 2>/dev/null | grep -c . ) || n=0
        [ "$n" = 0 ] || printf "%s(%s) " "$( basename "$( dirname "$m" )" )" "$n"
      done' 2>/dev/null )
    echo "INFO: census — adapter union = $_cen_nprobe declared entr(y|ies) from: ${_cen_mans:-<none>}"
    # LEG (b) — one classifier run over every probe path.
    printf '%s\n' "$_sv_bad" | awk -F'\t' '{print $2}' > "$d/census-probes.txt"
    _cen_bout=$( sh "$PR" --no-verify --changed "$d/census-probes.txt" 2>/dev/null \
                 | awk '/^   \[/ && !/^   \[control-plane\]/ { print }' ) || true
    if [ -z "$_cen_bout" ]; then
      echo "PASS: census leg (b) — every one of the $_cen_nprobe adapter-declared paths derives control-plane at --class (the property S2 creates; it was FALSE for the union-only entries before)"
    else
      echo "FAIL: census leg (b) — adapter-declared path(s) do NOT derive control-plane at --class, so the required ratification gate and every merge gate that derives through --class classify the same diff differently:"
      printf '%s\n' "$_cen_bout" | sed 's/^/         /'; st=1
    fi
  fi
  # ★★★ _census_grade <raw> — THE ONE GRADER FOR A CENSUS RUN, AND IT EXISTS BECAUSE THE MUTANT LEG
  # HAD ITS OWN AND THAT ONE COULD NOT FAIL (security review SEC-F1, reproduced before fixing).
  # The census emits THREE kinds of line: `A <path>` divergences, one informational `ONLY <n>` tally,
  # and the `ALIVE` sentinel. `_sentinel_eval` only strips ALIVE, so `_sv_bad` is NEVER empty — the
  # `ONLY` line is always there — and any completed run reads DIRTY. The real leg below stripped
  # `ONLY` before grading; the MUTANT leg did not, so it was asserting "the run completed", not "the
  # mutant produced divergences". Measured: with the census's `A` printf deleted outright, the
  # fork-the-source leg still reported `PASS … (1 divergent path(s))` — the 1 being the tally line.
  # THE FIX IS THE SHARED GRADER, not a second strip at the second site: two graders for one output
  # shape is what drifted in the first place. It grades POSITIVELY on `^A ` rather than on
  # "something was left over", so a future fourth line-kind cannot silently read as a divergence either.
  _census_grade() {  # <raw> -> sets _sv_state (NORUN|CLEAN|DIRTY), _sv_bad (A-lines only), _cen_only
    _sentinel_eval "$1"
    _cen_only=$( printf '%s\n' "$1" | sed -n 's/^ONLY //p' | head -1 )
    _sv_bad=$( printf '%s\n' "$1" | grep '^A ' || true )
    [ "$_sv_state" = NORUN ] || { if [ -n "$_sv_bad" ]; then _sv_state=DIRTY; else _sv_state=CLEAN; fi; }
  }
  # LEG (a) over the tracked tree.
  _cen_araw=$( _census "$PR" "$_cen_repo" ) || _cen_araw=""
  _census_grade "$_cen_araw"
  case "$_sv_state" in
    NORUN) echo "FAIL: the census leg (a) sweep produced no ALIVE sentinel — it did not run, and an empty result must never be read as agreement"; st=1 ;;
    CLEAN) echo "PASS: census leg (a) — over $( git -C "$_cen_repo" ls-files | grep -c . ) tracked paths, every guard-side control-plane verdict is matched at --class. ⚠️ READ THIS HONESTLY: the two AGREE BY CONSTRUCTION today (classify_path delegates to is_control_plane_path), so this leg proves no divergence exists rather than that one was searched for. It exists for the RE-FORK — the day the merge side grows its own copy of the control-plane set — and the mutant leg below is what keeps it from being decoration." ;;
    *)     echo "FAIL: census leg (a) — path(s) the GUARD denies as control-plane derive a lower class at --class. That is the guard-ALLOW/class-ordinary split this family of rows exists to prevent: the guard blocks the edit while the merge side says an ordinary review is enough."
           printf '%s\n' "$_sv_bad" | sed 's/^/         /'; st=1 ;;
  esac
  # INFORMATIONAL, ASSERTED NOWHERE (see the one-way note above): how many TRACKED paths the union
  # catches that the guard does not, tallied by the leg-(a) pass itself. On this repository the
  # union-only entries are untracked, so this is expected to read 0 — which is precisely why leg (b)
  # probes the ENTRIES instead of the tracked tree.
  echo "INFO: census — ${_cen_only:-?} tracked path(s) are control-plane to the adapter union ALONE (reported, asserted nowhere: the union-only-discriminator property is phase-gate's T3 canary, and two authorities for one property diverge)"

  # ── THE TWO KILLER MUTANTS. Neither leg above is evidence without them.
  _cen_mroot="$d/census-mutant"
  mkdir -p "$_cen_mroot/conformance" "$_cen_mroot/.claude/hooks"
  cp "$(dirname "$PR")/union-lib.sh" "$_cen_mroot/conformance/union-lib.sh"
  cp "$_inv_core" "$_cen_mroot/.claude/hooks/guard-core.sh"
  ln -s "$( cd "$_cen_ad" && pwd )" "$_cen_mroot/adapters" 2>/dev/null || cp -R "$_cen_ad" "$_cen_mroot/adapters"
  _cen_mut() {  # <name> <sed-expr> -> builds $_cen_mut_path, or returns 1 having reported the FAIL
    _cm_p="$_cen_mroot/conformance/promotion-readiness.sh"
    sed "$2" "$PR" > "$_cm_p"
    if cmp -s "$PR" "$_cm_p"; then
      echo "FAIL: the census '$1' mutant was NOT BUILT (the anchor did not match), so the leg it kills is unproven"; st=1; return 1
    fi
    if ! sh -n "$_cm_p" 2>/dev/null; then
      echo "FAIL: the census '$1' mutant does not parse, so it would answer nothing for every path and report VACUOUS rather than killing anything"; st=1; return 1
    fi
    _cen_mut_path="$_cm_p"; return 0
  }
  # MUTANT 1 — FORK THE CLASS SOURCE. classify_path stops delegating to the guard's matcher; the
  # merge side now has its own (empty) idea of the control-plane set. Leg (a) must red.
  if _cen_mut fork-the-source 's%^  if \[ "\$GUARD_OK" = 1 \] && is_control_plane_path%  if false \&\& [ "$GUARD_OK" = 1 ] \&\& is_control_plane_path%'; then
    _cen_mraw=$( _census "conformance/promotion-readiness.sh" "$_cen_mroot" ) || _cen_mraw=""
    # THE SAME GRADER THE REAL LEG USES — see _census_grade. Grading this with a bare
    # `_sentinel_eval` is what made this leg unable to fail.
    _census_grade "$_cen_mraw"
    if [ "$_sv_state" = DIRTY ]; then
      echo "PASS: census leg (a) is LIVE — a classifier that stops delegating to the guard's matcher reds it ($( printf '%s\n' "$_sv_bad" | grep -c . ) divergent path(s))"
    else
      echo "FAIL: census leg (a) is VACUOUS — the fork-the-source mutant evaluated to '$_sv_state', so leg (a) would stay green against a merge side carrying its own control-plane set"; st=1
    fi
  fi
  # MUTANT 2 — DROP THE UNION CONSULT. Exactly the pre-S2 classifier. Leg (b) must red.
  if _cen_mut drop-the-union 's%^  if \[ -n "\$UNION_LIST" \] && kit_path_in_union%  if false \&\& [ -n "$UNION_LIST" ] \&\& kit_path_in_union%'; then
    _cen_bmut=$( ( cd "$_cen_mroot" && sh conformance/promotion-readiness.sh --no-verify --changed "$d/census-probes.txt" ) 2>/dev/null \
                 | awk '/^   \[/ && !/^   \[control-plane\]/ { print }' ) || true
    if [ -n "$_cen_bmut" ]; then
      echo "PASS: census leg (b) is LIVE — a classifier with the union consult removed reds it ($( printf '%s\n' "$_cen_bmut" | grep -c . ) adapter-declared path(s) fall to a lower class)"
    else
      echo "FAIL: census leg (b) is VACUOUS — with the union consult REMOVED every adapter-declared path still derived control-plane, so this leg is satisfied by the very build S2 replaced"; st=1
    fi
  fi

  # FALSE-POSITIVE anchors: folding must not drag ordinary paths in.
  # `.claude/README.md` was HERE until GUARD-PATH-ENUMERATION-INCOMPLETE S1 made `.claude/*` a family;
  # it is asserted control-plane in the leg below now. The move is deliberate and disclosed: everything
  # inside the agent's own instrumentation directory is governing, and the anchoring property this list
  # protects is still carried by the `foo.claude/` sibling legs in the synthetic block above.
  for _cv in "README.md" "docs/notes.md" "src/App.tsx" ".github/ISSUE_TEMPLATE/bug_report.md" ".github/PULL_REQUEST_TEMPLATE.md"; do
    printf '%s\n' "$_cv" > "$_casef"
    _got=$( sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
    if [ "$_got" = ordinary ]; then echo "PASS: ordinary path '$_cv' stays ordinary after the fold"
    else echo "FAIL: ordinary path '$_cv' want ordinary got $_got — case folding over-matched"; st=1; fi
  done
  # THE MERGE-SIDE LEG, ASSERTED AND NOT INHERITED (GUARD-PATH-ENUMERATION-INCOMPLETE S1, AC1).
  # `classify_path` delegates to the guard, so it is TEMPTING to argue the class flips "by construction"
  # once the guard does. That argument is a derivation, not a measurement, and the row exists because a
  # guard-ALLOW / class-`ordinary` pair let `scripts/branch-protection-apply.sh` merge unratified for ten
  # days. Each family member is re-derived here through the real `--class` surface. The `zz-*` names are
  # in no list and their directories do not exist — a change that greens them by ENUMERATION has
  # defeated the row rather than met it.
  for _cv in "scripts/publish-public.sh" "scripts/branch-protection-apply.sh" "scripts/zz-nonexistent.sh" \
             "profiles/adopter-gates.yml" "profiles/zz-fake/ci.yml" ".claude/commands/x.md" \
             ".claude/plugins/y.json" ".claude/README.md" "AGENTS.md" "REQUIRED-CHECKS.md" \
             ".gitattributes" "docs/.gitattributes"; do
    printf '%s\n' "$_cv" > "$_casef"
    _got=$( sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
    if [ "$_got" = control-plane ]; then echo "PASS: derived family member '$_cv' -> control-plane at --class"
    else echo "FAIL: derived family member '$_cv' want control-plane got $_got — the guard denies writes to it while the merge-side class says an ordinary review is enough, which is precisely the guard-vs-class split this row was opened on"; st=1; fi
  done
  # …and the merge-side negatives: a look-alike sibling must NOT acquire a ratification demand.
  for _cv in "myscripts/x.sh" "myprofiles/x.yml" "foo.claude/settings.json" "subagents.md"; do
    printf '%s\n' "$_cv" > "$_casef"
    _got=$( sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
    if [ "$_got" = ordinary ]; then echo "PASS: family look-alike '$_cv' stays ordinary at --class"
    else echo "FAIL: family look-alike '$_cv' want ordinary got $_got — the family matched a SUBSTRING instead of a path SEGMENT and is now demanding ratification on ordinary adopter files"; st=1; fi
  done
  # THE M2 CLASS FACE OF THE HOME-INSTRUMENTATION RELIEF, PINNED AS A RECORDED DECISION (design
  # docs/architecture/2026-08-17-guard-claude-home-fp-design.md §4, vet M2). The relief is by SUBTREE
  # NAME, not by location, so it also relaxes the MERGE side: a repo that tracked
  # `.claude/projects/…` or `.claude/plans/…` would derive `ordinary` at `--class`, and a PR adding
  # such a file would merge without control-plane ratification. No harness reads repo-side copies of
  # these subtrees today, and the alternative ($HOME-anchored patterns) makes matching env-dependent —
  # so the face is ACCEPTED and pinned here rather than left to be discovered. If a future slice
  # location-scopes the relief, this leg goes RED and is re-taken deliberately.
  # ⚠️ THE FACE HAS **TWO** HALVES AND THIS LEG IS ONLY ONE OF THEM (reviewer M-2, measured). The
  # other merge-side surface is `conformance/agent-boundary.sh`, which answers "no control-plane
  # paths" for the same subject; it carries its own selftest row (plus a non-relieved sibling as its
  # load-bearing negative) so both halves red together instead of one being left behind.
  for _cv in ".claude/projects/evil.md" ".claude/plans/evil.md"; do
    printf '%s\n' "$_cv" > "$_casef"
    _got=$( sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
    if [ "$_got" = ordinary ]; then echo "PASS: relieved workspace subtree '$_cv' -> ordinary at --class (the ACCEPTED merge-side face of the home-instrumentation relief, design §4 M2)"
    else echo "FAIL: relieved workspace subtree '$_cv' got $_got — either the relief is gone (and the harness's own memory/plan writes are broken again) or the class surface disagrees with the guard, which is the guard-vs-class split this family's rows exist to prevent"; st=1; fi
  done
  # ══ S2 M1 — THE ADAPTER-UNION HALF OF `--class` (GUARD-PATH-ENUMERATION-INCOMPLETE S2) ═══════════
  # The defect these legs close: `GEMINI.md`, `.gemini/*` and `.cursor/rules/*` are control-plane to
  # the REQUIRED ratification gate (which unions guard-core with the adapter manifests) and were
  # `ordinary` here — so loop-state and ceremony-binding, which both derive through this classifier,
  # passed a PR carrying a gate-approved-WRONG `Kit-Class: ordinary` trailer that the ratification
  # gate then blocked. `classify_path` now consults the SAME union, through the SAME matching
  # authority (conformance/union-lib.sh), which is what stops the two gates disagreeing.
  # ⚠️ THE MATCHER IS SHARED, NOT RE-IMPLEMENTED, and the case-variant + glob legs below are what
  # prove it: a second matcher in classify_path would re-fork the semantics one layer down
  # (`.Cursor/rules/x` gating at ratification while deriving ordinary here).
  for _cv in "GEMINI.md" ".gemini/config.yaml" ".cursor/rules/foo.md"; do
    printf '%s\n' "$_cv" > "$_casef"
    _got=$( sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
    if [ "$_got" = control-plane ]; then echo "PASS: adapter-declared path '$_cv' -> control-plane at --class (union half live)"
    else echo "FAIL: adapter-declared path '$_cv' want control-plane got $_got — the ratification gate treats it as control-plane and this classifier does not, so a PR touching it derives a gate-approved-WRONG ordinary trailer"; st=1; fi
    # …and the PER-PATH RENDER must agree with the aggregate. The aggregate is a different call site
    # from the render line (the I5 leg above measured a mutant that moved only one of them), so the
    # surfacing a human reads to give the GO gets its own assertion.
    _rout=$( sh "$PR" --no-verify --changed "$_casef" 2>/dev/null || true )
    case "$_rout" in
      *"[control-plane] $_cv"*) echo "PASS: adapter-declared path '$_cv' renders [control-plane] per-path too" ;;
      *) echo "FAIL: adapter-declared path '$_cv' did not render as [control-plane] in the per-path listing — the render site and the aggregate site disagree"; st=1 ;;
    esac
  done
  # AGGREGATE over a MIXED listing: one adapter-declared path among ordinary ones must lift the whole
  # change-set. This is the shape a real PR has, and the shape the fail-safe cannot fake (n>0, guard
  # loaded, base readable).
  printf 'README.md\nsrc/util/format.ts\nGEMINI.md\n' > "$_casef"
  _got=$( sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
  if [ "$_got" = control-plane ]; then echo "PASS: mixed listing with ONE adapter-declared path aggregates control-plane"
  else echo "FAIL: mixed listing with GEMINI.md aggregated '$_got', want control-plane — highest-class-wins must see the union half"; st=1; fi
  # CASE VARIANT through the REAL manifest set. `.cursor/rules/` is declared lowercase; the shared
  # matcher folds BOTH sides, so one capital letter must not buy an ordinary class here any more than
  # it does at the ratification gate.
  printf '%s\n' ".Cursor/rules/x.md" > "$_casef"
  _got=$( sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
  if [ "$_got" = control-plane ]; then echo "PASS: adapter-union CASE VARIANT '.Cursor/rules/x.md' -> control-plane at --class"
  else echo "FAIL: adapter-union case variant got $_got — classify_path is matching the union with its OWN byte-literal matcher instead of the shared path_in_union, so the two gates disagree by one capital letter"; st=1; fi
  # GLOB-BEARING union entry, against a HERMETIC manifest set. Every union leg above uses a glob-free
  # entry, so the glob branch of the shared matcher could be deleted and they would all stay green.
  _globdir="$d/glob-adapters/probe"
  mkdir -p "$_globdir"
  printf '{"controlPlanePaths":["zz-globprobe/*"]}\n' > "$_globdir/adapter.json"
  printf '%s\n' "zz-globprobe/deep/file.txt" > "$_casef"
  _got=$( KIT_ADAPTERS_DIR="$d/glob-adapters" sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
  if [ "$_got" = control-plane ]; then echo "PASS: GLOB union entry 'zz-globprobe/*' -> control-plane at --class"
  else echo "FAIL: glob union entry got $_got — the shared matcher's glob branch is not reached from classify_path"; st=1; fi
  printf '%s\n' "elsewhere/deep/file.txt" > "$_casef"
  _got=$( KIT_ADAPTERS_DIR="$d/glob-adapters" sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
  if [ "$_got" = ordinary ]; then echo "PASS: GLOB union entry does NOT match outside its subtree"
  else echo "FAIL: glob union entry captured 'elsewhere/deep/file.txt' as $_got — an over-matching glob turns every PR control-plane"; st=1; fi
  # ── THE LOAD-BEARING NEGATIVES. Without these the union consult could be an unconditional
  # control-plane arm and every positive above would still be green.
  # `my.gemini/x` and `GEMINI.md.bak` are the ANCHORING pair: union entries are matched exactly, as a
  # trailing-'/' directory prefix, or as a glob — never as a substring.
  for _cv in "README.md" "docs/notes.md" "src/App.tsx" "my.gemini/x.yaml" "GEMINI.md.bak" \
             "docs/gemini-notes.md" "notes/.cursor-rules.md"; do
    printf '%s\n' "$_cv" > "$_casef"
    _got=$( sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
    if [ "$_got" = ordinary ]; then echo "PASS: union look-alike '$_cv' stays ordinary at --class"
    else echo "FAIL: union look-alike '$_cv' want ordinary got $_got — the union is matching a SUBSTRING and is now demanding control-plane ceremony on ordinary files"; st=1; fi
  done
  # …and the #557 relieved workspace subtrees must not be re-captured by the union half either (the
  # relief is asserted above against the GUARD half; this is the same subject through the new half).
  for _cv in ".claude/projects/evil.md" ".claude/plans/evil.md"; do
    printf '%s\n' "$_cv" > "$_casef"
    _got=$( sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
    if [ "$_got" = ordinary ]; then echo "PASS: relieved subtree '$_cv' stays ordinary through the UNION half too"
    else echo "FAIL: relieved subtree '$_cv' got $_got via the union half — the home-instrumentation relief is broken again by the other door"; st=1; fi
  done

  # ── THE AVAILABILITY PREDICATE, PINNED EXACTLY AS THE DESIGN SPECIFIES IT (§3, vet H2).
  # Two states, and conflating them is the defect: OK-EMPTY (no manifests at all) is a LEGITIMATE
  # tree — the guard-core floor alone, NEVER a fail-safe, because an adapter-less repo classifying
  # every PR control-plane is a ceremony DoS. UNAVAILABLE (manifests EXIST but the mechanism is
  # broken) fail-safes UP and DISCLOSES, because a silently-skipped corrupt manifest is the whole
  # defect class this row exists for.
  _emptyad="$d/empty-adapters"; mkdir -p "$_emptyad"
  printf 'src/util/format.ts\n' > "$_casef"
  _got=$( KIT_ADAPTERS_DIR="$_emptyad" sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
  if [ "$_got" = ordinary ]; then echo "PASS: OK-EMPTY (no adapter manifests) -> the guard floor alone, ordinary (no ceremony DoS)"
  else echo "FAIL: OK-EMPTY got $_got — an adapter-less or hand-rolled tree must classify on the guard floor, not fail-safe every PR to control-plane"; st=1; fi
  _badad="$d/broken-adapters/probe"; mkdir -p "$_badad"
  printf 'this is not json {{{\n' > "$_badad/adapter.json"
  _got=$( KIT_ADAPTERS_DIR="$d/broken-adapters" sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
  if [ "$_got" = control-plane ]; then echo "PASS: UNAVAILABLE (a manifest exists and does not parse) -> fail-safed to control-plane"
  else echo "FAIL: UNAVAILABLE got $_got — a corrupt adapter manifest silently narrowed the control-plane set, which is exactly the silent under-detection this row exists for"; st=1; fi
  # ⚠️ STDERR, NEVER STDOUT (vet L-1). loop-state and ceremony-binding both read `--class` stdout with
  # `tail -1`; a disclosure printed there turns every degraded run into a DERIVE FAILURE at both merge
  # gates. Assert the channel AND the remedy, because a disclosure that does not name the fix is a
  # log line, not a disclosure.
  _uo=$( KIT_ADAPTERS_DIR="$d/broken-adapters" sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null )
  if [ "$_uo" = control-plane ]; then echo "PASS: under UNAVAILABLE, --class stdout is EXACTLY the class token (no disclosure on stdout)"
  else echo "FAIL: under UNAVAILABLE, --class stdout was '$_uo' — a consumer reading it with tail -1 now sees prose, not a class"; st=1; fi
  _ue=$( KIT_ADAPTERS_DIR="$d/broken-adapters" sh "$PR" --class --no-verify --changed "$_casef" 2>&1 >/dev/null || true )
  case "$_ue" in
    *"adapter.json"*) echo "PASS: under UNAVAILABLE, stderr names the failing manifest" ;;
    *) echo "FAIL: under UNAVAILABLE, stderr does not name the failing manifest: '$_ue'"; st=1 ;;
  esac
  case "$_ue" in
    *jq*) echo "PASS: under UNAVAILABLE, stderr names the remedy (jq)" ;;
    *) echo "FAIL: under UNAVAILABLE, stderr names no remedy: '$_ue'"; st=1 ;;
  esac
  # ── THE PREDICATE'S OTHER TWO ARMS, WHICH SHIPPED UNTESTED (review REV-I5). §3 pins UNAVAILABLE as
  # "manifests exist ∧ (NO JQ ∨ any parse failure)". Only the parse-failure disjunct had a leg, so the
  # `command -v jq` half could have been deleted and every leg above stayed green — and that half is
  # the one an adopter actually meets (a runner without jq), not a corrupt manifest.
  # jq is removed by PATH-SHADOWING, the pattern conformance/backlog-presence.sh's i1/no-jq leg uses:
  # a symlink farm of the real PATH with jq omitted, so every OTHER tool the classifier needs still
  # resolves and the leg tests the absence of jq rather than the absence of a shell.
  _njq="$d/nojq-path"; mkdir -p "$_njq"; _njq_ok=1
  while IFS= read -r _np; do
    [ -n "$_np" ] || continue; [ -d "$_np" ] || continue
    for _nb in "$_np"/*; do
      { [ -f "$_nb" ] && [ -x "$_nb" ]; } || continue
      _nn=${_nb##*/}; [ "$_nn" = jq ] && continue
      [ -e "$_njq/$_nn" ] || ln -s "$_nb" "$_njq/$_nn" 2>/dev/null
    done
  done <<PATH_EOF
$(printf '%s\n' "$PATH" | tr ':' '\n')
PATH_EOF
  if PATH="$_njq" command -v jq >/dev/null 2>&1; then
    echo "FAIL: the jq-less PATH farm still resolves jq, so the no-jq leg below would prove nothing"; st=1; _njq_ok=0
  elif ! PATH="$_njq" command -v tr >/dev/null 2>&1; then
    echo "FAIL: the jq-less PATH farm lost tools other than jq, so a red below would not be about jq"; st=1; _njq_ok=0
  fi
  if [ "$_njq_ok" = 1 ]; then
    printf 'README.md\n' > "$_casef"
    _got=$( PATH="$_njq" sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
    if [ "$_got" = control-plane ]; then echo "PASS: UNAVAILABLE via NO JQ (manifests present, jq absent) -> fail-safed to control-plane"
    else echo "FAIL: with jq absent and manifests present, --class answered '$_got' — the adapter-declared surface was unreadable and the class did NOT fail-safe, which is a silently narrowed control-plane set on every jq-less runner"; st=1; fi
    _ue=$( PATH="$_njq" sh "$PR" --class --no-verify --changed "$_casef" 2>&1 >/dev/null || true )
    case "$_ue" in
      *jq*) echo "PASS: the NO-JQ arm discloses on stderr and names the remedy (install jq)" ;;
      *) echo "FAIL: the NO-JQ arm disclosed nothing actionable on stderr: '$_ue'"; st=1 ;;
    esac
    # …and OK-EMPTY must STILL be the guard floor with jq absent: no manifests means no mechanism is
    # needed, so this is not an UNAVAILABLE state and must not fail-safe. Without this pair, "fail-safe
    # whenever jq is missing" would pass the leg above and re-introduce the ceremony DoS.
    printf 'src/util/format.ts\n' > "$_casef"
    _got=$( PATH="$_njq" KIT_ADAPTERS_DIR="$_emptyad" sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
    if [ "$_got" = ordinary ]; then echo "PASS: NO JQ + NO manifests is still OK-EMPTY -> ordinary (the predicate is a CONJUNCTION, not 'jq missing')"
    else echo "FAIL: no-jq with NO manifests answered '$_got' — an adapter-less tree on a jq-less runner now demands control-plane ceremony for every PR (the DoS §3 excludes)"; st=1; fi
  fi
  # THE SHARED UNIT ITSELF UNRESOLVABLE. `KIT_UNION_LIB` selects the matcher; pointed at nothing, the
  # adapter half cannot be evaluated at all. Manifests are present here, so this is UNAVAILABLE.
  printf 'README.md\n' > "$_casef"
  _got=$( KIT_UNION_LIB=/nonexistent-union-lib.sh sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
  if [ "$_got" = control-plane ]; then echo "PASS: KIT_UNION_LIB unresolvable (manifests present) -> fail-safed to control-plane"
  else echo "FAIL: with the shared union unit unresolvable, --class answered '$_got' — one unresolvable path silently removes the adapter half of the control-plane set"; st=1; fi
  _ue=$( KIT_UNION_LIB=/nonexistent-union-lib.sh sh "$PR" --class --no-verify --changed "$_casef" 2>&1 >/dev/null || true )
  case "$_ue" in
    *union-lib.sh*) echo "PASS: the unresolvable-unit arm names the remedy (restore conformance/union-lib.sh)" ;;
    *) echo "FAIL: the unresolvable-unit arm disclosed nothing naming the unit: '$_ue'"; st=1 ;;
  esac
  # ── AN **ENV-SUPPLIED** EMPTY UNION IS NEVER SILENT (review REV-I1). OK-EMPTY stays the guard floor
  # — fail-safing would let one variable inflict a ceremony DoS — but it must not happen unannounced.
  # MEASURED before this disclosure: `KIT_ADAPTERS_DIR=<empty dir>` made a GEMINI.md-only change-set
  # derive `ordinary` with rc 0 and ZERO bytes of stderr, i.e. an ambient variable moved a governing
  # path out of the control-plane set leaving no trace. Both halves are asserted: the class (still the
  # floor) and the disclosure (now present, and naming the variable).
  printf 'GEMINI.md\n' > "$_casef"
  _got=$( KIT_ADAPTERS_DIR="$_emptyad" sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
  if [ "$_got" = ordinary ]; then echo "PASS: env-supplied empty union still classifies on the guard floor (no ceremony DoS by variable)"
  else echo "FAIL: env-supplied empty union answered '$_got'; OK-EMPTY must stay the guard floor"; st=1; fi
  _ue=$( KIT_ADAPTERS_DIR="$_emptyad" sh "$PR" --class --no-verify --changed "$_casef" 2>&1 >/dev/null || true )
  case "$_ue" in
    *KIT_ADAPTERS_DIR*) echo "PASS: an ENV-SUPPLIED empty union is DISCLOSED on stderr and names the variable" ;;
    *) echo "FAIL: KIT_ADAPTERS_DIR pointed at an empty directory silently emptied the adapter half — a governing path derives ordinary with no trace: '$_ue'"; st=1 ;;
  esac
  # …and THE LOAD-BEARING NEGATIVE: a tree that is adapter-less ON ITS OWN, with no variable set, must
  # stay SILENT. Otherwise every adopter who ships no manifests gets a warning on every run and the
  # disclosure degrades into noise to scroll past — and, worse, this leg would pass against a build
  # that warned unconditionally, which would prove nothing about the env-scoping. Needs a real tree
  # (an unset variable resolves relative to the classifier's own root), so one is built.
  _noad="$d/no-adapters"
  mkdir -p "$_noad/conformance" "$_noad/.claude/hooks"
  cp "$PR" "$_noad/conformance/promotion-readiness.sh"
  cp "$(dirname "$PR")/union-lib.sh" "$_noad/conformance/union-lib.sh"
  cp "$_inv_core" "$_noad/.claude/hooks/guard-core.sh"
  printf 'GEMINI.md\n' > "$_noad/changed.txt"
  _nao=$( ( cd "$_noad" && sh conformance/promotion-readiness.sh --class --no-verify --changed changed.txt ) 2>"$d/noad.err" | tail -1 ) || true
  _ue=$( cat "$d/noad.err" 2>/dev/null || true )
  if [ "$_nao" = ordinary ] && [ -z "$_ue" ]; then
    echo "PASS: an adapter-less TREE (no variable set) is OK-EMPTY, classifies on the guard floor, and stays SILENT"
  elif [ -n "$_ue" ]; then
    echo "FAIL: an adapter-less tree with NO variable set still disclosed ('$_ue') — the warning is unconditional, so every adapter-less adopter is warned on every run and the env-scoped leg above proves nothing"; st=1
  else
    echo "FAIL: an adapter-less tree answered '$_nao', want ordinary (OK-EMPTY is the guard floor, never a fail-safe)"; st=1
  fi

  # ── THE DEGRADED-RENDER FIXTURE (design §5, the narrowed fallback gap). With the guard core absent
  # the AGGREGATE already fail-safes to control-plane — but the per-path listing printed `[ordinary]`
  # for governing paths directly above it, so the artifact a human reads to render the §13 GO
  # CONTRADICTED ITSELF. Build a tree with no guard core and assert the contradiction is dead.
  _degr="$d/degraded"
  mkdir -p "$_degr/conformance"
  cp "$PR" "$_degr/conformance/promotion-readiness.sh"
  [ -f conformance/union-lib.sh ] && cp conformance/union-lib.sh "$_degr/conformance/union-lib.sh"
  printf 'conformance/x.sh\nREADME.md\n' > "$_degr/changed.txt"
  _dout=$( ( cd "$_degr" && sh conformance/promotion-readiness.sh --no-verify --changed changed.txt ) 2>/dev/null || true )
  case "$_dout" in
    *"Change-class (aggregate): control-plane"*) : ;;
    *) echo "FAIL: the degraded fixture did not fail-safe the AGGREGATE to control-plane, so this leg is not testing the contradiction"; st=1 ;;
  esac
  case "$_dout" in
    *"[ordinary]"*)
      echo "FAIL: with the guard core ABSENT the per-path render still labels a path [ordinary] directly above an aggregate of control-plane — a self-contradicting surfacing on the artifact a human reads to give the §13 GO"; st=1 ;;
    *) echo "PASS: degraded classifier — the per-path render no longer contradicts the fail-safed aggregate" ;;
  esac

  # SENSITIVE tier is a SEPARATE matcher from the control-plane one and needed its own fold.
  for _cv in "Auth/x.ts" "k.PEM" ".ENV"; do
    printf '%s\n' "$_cv" > "$_casef"
    _got=$( sh "$PR" --class --no-verify --changed "$_casef" 2>/dev/null | tail -1 )
    if [ "$_got" = sensitive ]; then echo "PASS: sensitive case variant '$_cv' -> sensitive"
    else echo "FAIL: sensitive case variant '$_cv' want sensitive got $_got — the sensitive tier is a second matcher and folds independently of is_control_plane_path"; st=1; fi
  done

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
