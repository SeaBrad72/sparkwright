#!/bin/sh
# incept-first-run-green.sh — the STACK-AGNOSTIC "first-run green" detector (KW3).
#
# Proves a generalizable property, not a hardcoded five-item patch:
#
#   For an archetype's reference scaffold, every mechanism the archetype is expected to ship is
#   activated to a GREEN-or-LEGIBLY-SKIPPED state — no mechanism is present-but-misconfigured-red.
#
# The check body carries ZERO stack-specific knowledge: all archetype specifics (which mechanisms,
# their config-shape assertions, preconditions, skip-reasons) live in a per-archetype MANIFEST
# (manifest-<stack>.txt). KW4/KW8 add one manifest per stack — same engine, zero check rework.
#
#   sh incept-first-run-green.sh --selftest              # the GATED proof (good fixture + 5 negatives + lock self-negative)
#   sh incept-first-run-green.sh [--manifest M] [TARGET] # evaluate an archetype dir (default profiles/typescript-node)
# Exit: 0 = every mechanism GREEN-or-SKIPPED/N-A . 1 = a MISCONFIGURED-RED mechanism . 2 = usage/setup.
# POSIX sh; dash-clean. Fail-closed: a missing/unreadable manifest or ci.yml, or an unknown predicate
# verb, resolves to MISCONFIGURED / error — never a silent pass.
#
# Config-shape assertions are the ALWAYS-RUN, tool-free, deterministic core — and, as of CP-5, ALL
# this script claims to be. The old "opportunistic LIVE-GATE" layer was DELETED (see the note at its
# former site below): it skipped when the tool was absent — and kit CI never installed semgrep, so it
# ALWAYS skipped — scanned the wrong scope when it did run, and was advisory-only. It could not fail.
# The REAL live proof is the `artifact-gate` CI job: export -> incept -> the adopter's own
# `verify.sh --require` + the exact emitted SAST command, ON THE ARTIFACT, blocking.
#
# HONEST CEILING: proves the shipped archetype's gates are green-or-legibly-skipped on first run;
# cannot prove a mechanism no scaffold exercises (an adopter who later adds payments hits wiring this
# lock never saw). Live external attestation (real SLSA, a live cloud DB) is the adopter's CI, not here.
set -euf

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

# --- Resolve the repo root across authoring (scratchpad/kw3) + installed (conformance/) layouts. ---
if [ -d "$SCRIPT_DIR/../profiles" ]; then
  REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
elif [ -d "$SCRIPT_DIR/../../profiles" ]; then
  REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
else
  REPO_ROOT="$SCRIPT_DIR"
fi

# --- Fixtures + manifest default resolution (env-overridable so a neutered COPY run out of a tmp dir
#     still finds the originals; mirrors the sibling locks' co-located-then-installed resolution). ---
FIXTURES="${KW3_FIXTURES:-$SCRIPT_DIR/fixtures}"
MANIFEST_DEFAULT="${KW3_MANIFEST:-}"
resolve_manifest_default() {  # echoes a manifest path for TARGET basename, or empty
  _base="$1"
  if [ -n "$MANIFEST_DEFAULT" ]; then printf '%s\n' "$MANIFEST_DEFAULT"; return 0; fi
  for _cand in \
    "$SCRIPT_DIR/manifest-$_base.txt" \
    "$SCRIPT_DIR/incept-manifests/$_base.txt" \
    "$REPO_ROOT/conformance/incept-manifests/$_base.txt"; do
    [ -f "$_cand" ] && { printf '%s\n' "$_cand"; return 0; }
  done
  return 1
}

# ===========================================================================================
# PREDICATE ENGINE — the stack-agnostic vocabulary. NO archetype token appears here; the manifest
# supplies every regex/path. Returns 0 = holds, 1 = does not hold, 2 = unknown verb (fail-closed).
# (The function-def line below is the neutralization target for the lock self-negative — do not rename.)
# ===========================================================================================
predicate_holds() {
  _pd="$1"; _verb="$2"; _arg="$3"
  # present/absent evaluate the LIVE config (comment-stripped CI_CODE) so a token that appears only
  # in a comment neither satisfies `present` nor trips `absent` (the R1/agentops-sensor lesson). The
  # `comment` verb matches the RAW ci.yml — for intentional in-repo explanations (e.g. the provenance
  # legible skip-reason, which is by-design a comment).
  case "$_verb" in
    always)  return 0 ;;
    present) grep -Eq -- "$_arg" "$CI_CODE" 2>/dev/null ;;
    absent)  if grep -Eq -- "$_arg" "$CI_CODE" 2>/dev/null; then return 1; else return 0; fi ;;
    comment) grep -Eq -- "$_arg" "$CI" 2>/dev/null ;;
    scaffold)
      [ -d "$_pd/scaffold" ] || return 1
      grep -rEq -- "$_arg" "$_pd/scaffold" 2>/dev/null ;;
    scaffoldfile)
      # arg = "<relpath> <ERE>" — grep <ERE> within scaffold/<relpath> ONLY (precise, file-scoped:
      # binds the assertion to a NAMED scaffold file, e.g. the .gitignore build-output exclusion,
      # rather than any file under scaffold/). Missing file -> does not hold.
      _sf=${_arg%% *}; case "$_arg" in *' '*) _sre=${_arg#* } ;; *) _sre='' ;; esac
      [ -f "$_pd/scaffold/$_sf" ] || return 1
      grep -Eq -- "$_sre" "$_pd/scaffold/$_sf" 2>/dev/null ;;
    file)    [ -f "$_pd/$_arg" ] ;;
    *)       echo "MISCONFIGURED: unknown predicate verb '$_verb' (fail-closed)" >&2; return 2 ;;
  esac
}

# --- CP-2: the opportunistic "live-gate" was DELETED here. It could not fail. ---
#
# It claimed to be a bonus live proof that a fresh incept lands green. It was three ways vacuous:
#   * it SKIPPED when the tool was absent — and kit CI never installed semgrep, so it always skipped;
#   * if it HAD run, it scanned `$DIR/scaffold/src` — NOT `.` — the exact single-subdir narrowing the
#     emitted CI's own comment forbids, so it would have scanned a clean subtree and missed the 22
#     blocking findings that were sitting in the kit's retained conformance/ + scripts/ + docs YAML;
#   * a non-zero result was ADVISORY ONLY and never touched the return code.
# So the one check that promised "first run is green" was structurally UNFALSIFIABLE, and CP-1 shipped
# under it for 119 versions. A check that cannot fail is worse than no check: it manufactures
# confidence. It is deleted rather than repaired.
#
# The REAL proof now lives in the `artifact-gate` CI job: export -> incept -> run the adopter's own
# `verify.sh --require` AND the exact emitted SAST command, ON THE ARTIFACT, blocking.
# The deterministic config-SHAPE assertions in the manifests below are unaffected — those work, and
# they are what this script is actually for.

# ===========================================================================================
# resolve_mechanism — evaluate the current block (shared vars: id/precond/whenabsent/asserts/
# skipreason/fixhint) against DIR/CI. Updates counters + RC. Prints the per-mechanism verdict.
# ===========================================================================================
resolve_mechanism() {
  [ -n "$id" ] || return 0
  _pv=${precond%% *}; case "$precond" in *' '*) _pa=${precond#* } ;; *) _pa='' ;; esac

  if predicate_holds "$DIR" "$_pv" "$_pa"; then
    # precondition holds -> the mechanism is expected live; evaluate config-shape asserts (ALL hold).
    _mis=0; _failed=''
    _oifs=$IFS; IFS='
'
    for _a in $asserts; do
      IFS=$_oifs
      [ -n "$_a" ] || { IFS='
'; continue; }
      _av=${_a%% *}; case "$_a" in *' '*) _aa=${_a#* } ;; *) _aa='' ;; esac
      if predicate_holds "$DIR" "$_av" "$_aa"; then :; else _mis=1; _failed=$_a; break; fi
      IFS='
'
    done
    IFS=$_oifs
    if [ "$_mis" = 0 ]; then
      echo "  [GREEN] $id — config-shape correct"
      GREENS=$((GREENS + 1))
    else
      echo "  [RED]   $id — MISCONFIGURED: assertion not satisfied: '$_failed'"
      echo "          fix: $fixhint"
      REDS=$((REDS + 1)); RC=1
    fi
  else
    if [ "$whenabsent" = na ]; then
      echo "  [N/A]   $id — $skipreason"
      NAS=$((NAS + 1))
    else
      echo "  [SKIP]  $id — $skipreason"
      SKIPS=$((SKIPS + 1))
    fi
  fi
}

reset_block() { id=''; precond=''; whenabsent='skip'; asserts=''; skipreason=''; fixhint=''; }

# ===========================================================================================
# P1.2 (T1b) — the `--date` reproducible-stamp seam, proven by LIVE incept runs.
#
# WHY HERE: this file is the kit's "what does a fresh incept actually produce?" lock, and it is
# CI-wired (`--selftest`). `--date` changes exactly that: the stamped **Created:** date.
#
# WHY IT MATTERS (the blocker this section exists to make impossible): `kit-update` reconstructs the
# adopter's base tree by re-running incept over the vendored kit-base and passing the ADOPTION date it
# parsed out of their CLAUDE.md. If incept ever stamps TODAY when a pin was intended, the diff shows a
# phantom conflict in CLAUDE.md + ADR-000-stack.md — files nobody touched. A fail-open in the exact
# seam whose only job is to prevent a false alarm. So the rejection path is asserted, not assumed:
# an empty/ill-formed `--date` must EXIT 2, never silently fall back to today.
#
# And the counterweight: incept runs ONCE per adopter and cannot be re-run. The DEFAULT (no `--date`)
# must still stamp today — that invariant is asserted FIRST, before any pinning case.
# ===========================================================================================
INCEPT_PRISTINE=''

make_pristine_export() {  # build ONCE: the tree an adopter actually incepts. rc 1 = setup failed.
  INCEPT_PRISTINE=$(mktemp -d) || return 1
  # `git archive HEAD` — not `cp -R` — because EXPORT SEMANTICS are load-bearing here: .gitattributes
  # export-ignores `docs/architecture/`, so the adopter's tree has NO ADR-000-stack.md and incept
  # therefore CREATES and STAMPS it. A raw worktree copy carries the kit's own ADR-000-stack.md, incept's
  # `[ -f ... ] ||` guard short-circuits, and the ADR assertion below would test nothing.
  ( cd "$REPO_ROOT" && git archive HEAD ) | ( cd "$INCEPT_PRISTINE" && tar -xf - ) || return 1
  # Overlay the WORKTREE content of every modified tracked file. `git archive` archives HEAD; without
  # this the run would exercise the COMMITTED incept.sh, not the one under change — a green that proves
  # the wrong artifact. No-op in CI (HEAD is the tree under test); load-bearing during development.
  #
  # NOT `... | while read`: `return` on the right of a pipeline exits the SUBSHELL, not this function, so
  # a failed `cp` was silently swallowed — and because make_pristine_export is called in an `if !`
  # condition, POSIX suppresses `set -e` inside it too. The HEAD files are still present, the anchors
  # below still pass, and the whole suite runs against the COMMITTED incept.sh: precisely "a green that
  # proves the wrong artifact", the thing the paragraph above exists to prevent. Command-substitute the
  # file list instead, so the loop (and its `return 1`) runs in THIS shell. The unquoted `$_mods` split
  # is glob-safe: the script is `set -euf`, so pathname expansion is off.
  _mods=$( cd "$REPO_ROOT" && git diff --name-only HEAD ) || return 1
  for _mf in $_mods; do
    [ -f "$INCEPT_PRISTINE/$_mf" ] || continue   # export-ignored or deleted -> not in the adopter tree
    cp "$REPO_ROOT/$_mf" "$INCEPT_PRISTINE/$_mf" || return 1
  done
  # Setup anchors — fail LOUDLY rather than let a broken fixture green the assertions below.
  [ -f "$INCEPT_PRISTINE/scripts/incept.sh" ] || return 1
  [ -f "$INCEPT_PRISTINE/CLAUDE.md" ] || return 1
  # If the export ever STOPPED stripping docs/architecture/, incept would skip the ADR stamp and the
  # ADR assertions would be testing a pre-existing file. Refuse to run rather than report on that.
  [ ! -e "$INCEPT_PRISTINE/docs/architecture/ADR-000-stack.md" ] || return 1
  return 0
}

fresh_export_tree() {  # echo a fresh, un-incepted copy of the pristine export
  # SAFETY (critical): refuse if the pristine export was never built. An EMPTY $INCEPT_PRISTINE makes
  # `cp -R "$INCEPT_PRISTINE/."` expand to `cp -R "/."` — copying the ENTIRE ROOT FILESYSTEM into a temp
  # dir (a catastrophic disk-filling runaway). Callers MUST run make_pristine_export first; fail loud, never
  # copy root.
  [ -n "$INCEPT_PRISTINE" ] && [ -d "$INCEPT_PRISTINE/scripts" ] || return 1
  _ft=$(mktemp -d) || return 1
  cp -R "$INCEPT_PRISTINE/." "$_ft/" || return 1
  printf '%s\n' "$_ft"
}

run_incept() {  # <tree> [extra incept args...] -> rc; combined output in $INCEPT_OUT
  _it="$1"; shift
  if INCEPT_OUT=$( cd "$_it" && sh scripts/incept.sh --name DateProbe --intent-owner probe \
       --stack typescript-node --backlog md --ci github --noninteractive "$@" 2>&1 ); then
    return 0
  else
    return $?
  fi
}

stamped_claude() { grep -c "^\*\*Created:\*\* $2\$" "$1/CLAUDE.md" 2>/dev/null || true; }
stamped_adr()    { grep -c "^\*\*Date:\*\* $2\$" "$1/docs/architecture/ADR-000-stack.md" 2>/dev/null || true; }

# A §3 config-list stamp: "- **<Field>** (§x): <value> …". Counts lines whose value STARTS with <value>
# as a whole token — the trailing template annotation survives the stamp, so anchor on the token, not
# on end-of-line. (This is the SAME shape kit-update.sh's stamp_list parser reads.)
stamped_cfg() {  # <tree> <field-ERE> <value-ERE>
  grep -Ec "^- \*\*$2\*\* \(§[^)]*\): $3( |\$)" "$1/CLAUDE.md" 2>/dev/null || true
}
# The UNFILLED slot still carries its bracketed choice-list. A stamp must REPLACE it, not sit beside it.
unstamped_cfg() {  # <tree> <field-ERE>
  grep -Ec "^- \*\*$2\*\* \(§[^)]*\): \[" "$1/CLAUDE.md" 2>/dev/null || true
}
# Every §3 occurrence of the field, stamped or not. Used to fail CLOSED: "no bracketed placeholder" is
# trivially true when the SLOT DOES NOT EXIST, so the placeholder assertion must also demand the slot
# be there, exactly once. (Absence must never read as cleanliness — the presence-check lesson.)
anyline_cfg() {  # <tree> <field-ERE>
  grep -Ec "^- \*\*$2\*\* \(§[^)]*\): " "$1/CLAUDE.md" 2>/dev/null || true
}
slot_filled_once() {  # <tree> <field-ERE>
  [ "$(anyline_cfg "$1" "$2")" = 1 ] && [ "$(unstamped_cfg "$1" "$2")" = 0 ]
}

incept_date_tests() {  # appends to $st (0 = all good)
  if ! make_pristine_export; then
    echo "selftest FAIL: --date fixture setup — could not build the pristine export tree (fail-closed)"; st=1; return 0
  fi

  # --- (a) THE DEFAULT IS UNCHANGED: no --date -> TODAY. Asserted first, because incept runs once per
  #         adopter and cannot be re-run: a regression here is unrecoverable for them. ---
  _today=$(date +%Y-%m-%d)
  _t=$(fresh_export_tree) || { echo "selftest FAIL: --date fixture (a) — no tree"; st=1; return 0; }
  if run_incept "$_t"; then
    if [ "$(stamped_claude "$_t" "$_today")" = 1 ]; then
      echo "selftest PASS: no --date -> CLAUDE.md stamps TODAY ($_today) — THE DEFAULT IS UNCHANGED"
    else
      echo "selftest FAIL: no --date did not stamp today ($_today) in CLAUDE.md"; st=1
    fi
    if [ "$(stamped_adr "$_t" "$_today")" = 1 ]; then
      echo "selftest PASS: no --date -> ADR-000-stack.md stamps TODAY ($_today)"
    else
      echo "selftest FAIL: no --date did not stamp today ($_today) in ADR-000-stack.md"; st=1
    fi
  else
    echo "selftest FAIL: incept WITHOUT --date exited non-zero (rc=$?)"; printf '%s\n' "$INCEPT_OUT" | tail -5 | sed 's/^/    /'; st=1
  fi
  rm -rf "$_t"

  # --- (b) A PINNED date reaches BOTH stamped files — and today's date reaches NEITHER. ---
  _t=$(fresh_export_tree) || { echo "selftest FAIL: --date fixture (b) — no tree"; st=1; return 0; }
  if run_incept "$_t" --date 2020-01-02; then
    if [ "$(stamped_claude "$_t" 2020-01-02)" = 1 ]; then
      echo "selftest PASS: --date 2020-01-02 -> CLAUDE.md carries 2020-01-02"
    else
      echo "selftest FAIL: --date 2020-01-02 did not reach CLAUDE.md"; st=1
    fi
    if [ "$(stamped_adr "$_t" 2020-01-02)" = 1 ]; then
      echo "selftest PASS: --date 2020-01-02 -> ADR-000-stack.md carries 2020-01-02"
    else
      echo "selftest FAIL: --date 2020-01-02 did not reach ADR-000-stack.md"; st=1
    fi
    # The load-bearing half of the pin: TODAY must appear in NEITHER stamp. A "stamps both" bug would
    # satisfy the two asserts above and still fabricate the phantom conflict kit-update exists to avoid.
    if [ "$(stamped_claude "$_t" "$_today")" = 0 ] && [ "$(stamped_adr "$_t" "$_today")" = 0 ]; then
      echo "selftest PASS: with a pin, TODAY ($_today) appears in NEITHER stamp (the pin REPLACES, not adds)"
    else
      echo "selftest FAIL: a pinned run still stamped today ($_today) somewhere"; st=1
    fi
  else
    echo "selftest FAIL: incept --date 2020-01-02 exited non-zero (rc=$?)"; printf '%s\n' "$INCEPT_OUT" | tail -5 | sed 's/^/    /'; st=1
  fi
  rm -rf "$_t"

  # --- (c) REJECTION PATH: every ill-formed --date must EXIT 2 — never fall open to today.
  #         '' is the BLOCKER case (`reqval` checks ARITY, not emptiness). '2026-1-1' is the un-padded
  #         shape. '2026-01-01/w /tmp/x' is the sed-injection shape (the value is interpolated into a
  #         `sedi` replacement). 2026-00-00 / 2026-13-32 / 2026-01-32 are the calendar cases.
  #
  #         ONE FRESH TREE PER CASE, deliberately: the first RED of this suite showed why. `--date ''`
  #         fell open — it stamped today and exited 0 — which INCEPTED the shared tree, so every later
  #         case returned rc=1 ("already incepted") instead of its own verdict. A shared tree lets one
  #         bug mask the next; independent trees make each case say only what it knows. ---
  for _bad in '' '2026-1-1' '2026-01-01/w /tmp/x' '2026-00-00' '2026-13-32' '2026-01-32' 'today'; do
    _t=$(fresh_export_tree) || { echo "selftest FAIL: --date fixture (c) — no tree"; st=1; return 0; }
    _rc=0; run_incept "$_t" --date "$_bad" || _rc=$?
    if [ "$_rc" -eq 2 ]; then
      echo "selftest PASS: --date '$_bad' -> REFUSED (exit 2)"
    else
      echo "selftest FAIL: --date '$_bad' -> rc=$_rc (expected 2 — an ill-formed pin must NEVER fall open to today)"; st=1
    fi
    # A refusal that already mutated the tree is not a refusal: assert the tree is untouched.
    if [ ! -e "$_t/ENGINEERING-PRINCIPLES.md" ] && [ "$(stamped_claude "$_t" "$_today")" = 0 ]; then
      echo "selftest PASS: --date '$_bad' left the tree PRISTINE (no rename, no stamp)"
    else
      echo "selftest FAIL: --date '$_bad' MUTATED the tree despite being invalid"; st=1
    fi
    rm -rf "$_t"
  done

  # --- (d) SOURCE INVARIANT (m2): every value interpolated into a `sedi` replacement goes through
  #         esc(). A no-op on a valid YYYY-MM-DD; the net that keeps the sed-injection surface closed
  #         if the accepted date format is ever widened.
  #
  #         THIS GREPS SOURCE, ON PURPOSE — do not "fix" it into a behavioural test. `--date` validation
  #         bounds the value to `[0-9-]` (case (c) above proves every other shape EXITS 2), so esc() is
  #         provably UNREACHABLE by behaviour today: no accepted input contains a `&`, `/` or `\` for it
  #         to escape. A behavioural assertion here could therefore only test a value the parser already
  #         refuses — it would pass identically with esc() deleted, i.e. it would be vacuous. The invariant
  #         being held is a FUTURE one ("if someone widens the format, the escape is already there"), and
  #         a source-level lock is the only thing that can hold it. Deleting esc() must break THIS line;
  #         that is the entire point. If you make the date format richer, replace this with the behavioural
  #         case the widening makes reachable — do not simply drop it. ---
  if grep -Eq '^DATE=\$\(esc ' "$REPO_ROOT/scripts/incept.sh"; then
    echo "selftest PASS: incept's DATE is esc'd before interpolation (every sed value is esc'd)"
  else
    echo "selftest FAIL: incept's DATE reaches a sedi replacement WITHOUT esc() — the invariant is broken"; st=1
  fi

  rm -rf "$INCEPT_PRISTINE"; INCEPT_PRISTINE=''
}

# ===========================================================================================
# P1.2 (T3b) — the LAST TWO inception inputs incept never recorded: the CI PLATFORM (`--ci`) and the
# DB ARCHETYPE (`--no-db`). Proven by LIVE incept runs, same as `--date` above.
#
# WHY IT MATTERS: `kit-update` reconstructs the adopter's base by REPLAYING incept over kit-base with the
# inputs the project recorded. Every input is a CLAUDE.md §3 stamp — these two were not, so T3 INFERRED
# them from evidence in the tree. Inference where a FACT is available is exactly the class of error this
# project keeps paying for, and here it is provably wrong: incept `--ci gitlab` leaves the exported
# kit-own `.github/workflows/ci.yml` in place, so "the GitHub workflow exists ⇒ --ci github" misreads
# EVERY GitLab adopter. A wrong base does not lose data — it MISATTRIBUTES kit files to the adopter and
# cries CONFLICT on files nobody touched, at the exact moment the tool must be trusted.
#
# So: record the FACT. These assertions are what make the stamp a fact rather than a hope.
# ===========================================================================================
stamp_case() {  # <label> <expect-ci> <expect-db> [extra incept args...]  — appends to $st
  _lbl=$1; _xci=$2; _xdb=$3; shift 3
  _t=$(fresh_export_tree) || { echo "selftest FAIL: stamp fixture ($_lbl) — no tree"; st=1; return 0; }
  if run_incept "$_t" "$@"; then
    if [ "$(stamped_cfg "$_t" 'CI platform' "$_xci")" = 1 ]; then
      echo "selftest PASS: [$_lbl] -> CLAUDE.md §3 stamps **CI platform**: $_xci"
    else
      echo "selftest FAIL: [$_lbl] did not stamp **CI platform**: $_xci in CLAUDE.md §3"; st=1
    fi
    if [ "$(stamped_cfg "$_t" 'DB archetype' "$_xdb")" = 1 ]; then
      echo "selftest PASS: [$_lbl] -> CLAUDE.md §3 stamps **DB archetype**: $_xdb"
    else
      echo "selftest FAIL: [$_lbl] did not stamp **DB archetype**: $_xdb in CLAUDE.md §3"; st=1
    fi
    # The load-bearing half: the stamp REPLACES the bracketed choice-list. A stamp that ADDED a line and
    # left the placeholder would satisfy the two asserts above, and kit-update's parser (which takes the
    # FIRST match) would still read `[github` — i.e. UNDECLARED — and silently fall back to inference.
    # Fail-CLOSED: each slot must exist EXACTLY ONCE and carry no bracket (a missing slot is not "clean").
    if slot_filled_once "$_t" 'CI platform' && slot_filled_once "$_t" 'DB archetype'; then
      echo "selftest PASS: [$_lbl] -> both slots exist EXACTLY ONCE and are FILLED (placeholder replaced, not duplicated)"
    else
      echo "selftest FAIL: [$_lbl] a §3 slot is missing, duplicated, or still bracketed — it reads as UNDECLARED"; st=1
    fi
  else
    echo "selftest FAIL: incept [$_lbl] exited non-zero (rc=$?)"; printf '%s\n' "$INCEPT_OUT" | tail -5 | sed 's/^/    /'; st=1
  fi
  rm -rf "$_t"
}

incept_stamp_tests() {  # appends to $st (0 = all good)
  if ! make_pristine_export; then
    echo "selftest FAIL: stamp fixture setup — could not build the pristine export tree (fail-closed)"; st=1; return 0
  fi
  # DEFAULTS first (incept runs ONCE per adopter — a regression in the default is unrecoverable for them):
  # `--ci github` is run_incept's baseline, and the ts-node reference archetype is DB-backed.
  stamp_case DEFAULT github db-backed
  # The case the inference gets WRONG. --ci gitlab is only wired for typescript-node today (the stack
  # run_incept uses), which is exactly why it is testable here.
  stamp_case CI-GITLAB gitlab db-backed --ci gitlab
  # --no-db: the other un-recorded input. Orthogonal to the CI platform, so the CI stamp must NOT move.
  stamp_case NO-DB github no-db --no-db
  rm -rf "$INCEPT_PRISTINE"; INCEPT_PRISTINE=''
}

# ===========================================================================================
# CP-7 recert (K5) — PRUNE UNSELECTED PROFILES. The emitted CI runs whole-tree SAST; a fresh export
# ships ALL stack profiles, so scanning a FOREIGN profile's scaffold (profiles/python/scaffold/tests
# urllib) reddened a TS adopter's FIRST CI on code they never wrote. incept now removes every stack
# profile except the selected one (mirroring adopter-export --profile). Proven by a LIVE incept over
# the UNPRUNED pristine export (make_pristine_export = git archive HEAD + worktree overlay = all
# profiles). LOAD-BEARING BY CONSTRUCTION: the pre-fix incept left all 10 profiles, so every assertion
# below FAILs without the prune (the manifest ones catch a disk-pruned-but-manifest-stale regression,
# which would give kit-update a phantom-deletion base). BOTH manifests are checked — working tree AND
# the kit-base ref (capture_kit_base staged the UNPRUNED set before $STACK was known, so the prune must
# reach the stage too, else kit-update reads a foreign-listing kit-base:.kit-manifest first).
# ===========================================================================================
# The KEPT set — profiles/ entries that are NOT a foreign stack profile and must survive the prune.
# `.gitignore` joined this set in v3.171.0 (CP7R5-K4-IGNORE): profiles/.gitignore is a TREE-LEVEL file
# carrying build-output ignore rules for every profile, and it must outlive the prune — that is the whole
# point of it existing (per-profile scaffold ignore files die with their profile, which was the K4 defect).
# Omitting it here counts a correctly-kept file as a foreign leftover and reddens the reconcile assertions.
manifest_foreign_count() {  # <manifest-text> — count profiles/ lines that are NOT the kept set (expect 0)
  printf '%s\n' "$1" | grep -E '^profiles/' \
    | grep -vE '^profiles/(typescript-node/|typescript-node\.md$|ratification\.yml$|_TEMPLATE\.md$|\.gitignore$)' \
    | grep -c . || true
}
incept_prune_tests() {  # appends to $st (0 = all good)
  # Build via adopter-export (NOT make_pristine_export): only adopter-export WRITES the .kit-manifest
  # this suite's reconcile assertions read (git archive HEAD ships no manifest — it is export-generated).
  _pt=$(mktemp -d) || { echo "selftest FAIL: prune fixture — no tmpdir (fail-closed)"; st=1; return 0; }
  _pe="$_pt/exp"
  if ! sh "$REPO_ROOT/scripts/adopter-export.sh" "$_pe" >"$_pt/exp.log" 2>&1; then
    echo "selftest FAIL: prune fixture — adopter-export failed"; sed 's/^/    /' "$_pt/exp.log"; st=1; rm -rf "$_pt"; return 0
  fi
  # git archive HEAD ships the COMMITTED incept.sh; overlay the worktree one under test (mirrors
  # make_pristine_export's worktree overlay) so the suite exercises THIS incept.sh, not HEAD's.
  cp "$REPO_ROOT/scripts/incept.sh" "$_pe/scripts/incept.sh" \
    || { echo "selftest FAIL: prune fixture — incept overlay failed"; st=1; rm -rf "$_pt"; return 0; }
  if run_incept "$_pe"; then   # run_incept baseline is --stack typescript-node
    # (a) foreign profile DIRS gone; the selected one + the non-stack-dir files kept.
    _foreign=$(ls -d "$_pe"/profiles/*/ 2>/dev/null | sed 's#.*/profiles/##; s#/$##' | grep -vxF typescript-node | tr '\n' ' ')
    if [ -z "$_foreign" ] && [ -d "$_pe/profiles/typescript-node" ]; then
      echo "selftest PASS: incept pruned every foreign profile dir, kept profiles/typescript-node"
    else
      echo "selftest FAIL: after incept, foreign profile dirs remain ('$_foreign') or the selected profile is missing"; st=1
    fi
    if [ -f "$_pe/profiles/ratification.yml" ] && [ -f "$_pe/profiles/_TEMPLATE.md" ]; then
      echo "selftest PASS: incept kept the non-stack-dir files (ratification.yml, _TEMPLATE.md)"
    else
      echo "selftest FAIL: incept pruned a non-stack-dir file (ratification.yml / _TEMPLATE.md) it must keep"; st=1
    fi
    # CP7R5-K4-IGNORE — profiles/.gitignore MUST survive the prune. This is not bookkeeping: the whole
    # defect was that build-output ignore rules lived INSIDE the profiles the prune deletes. If a future
    # change let the prune take this file too, K4 returns silently — an adopter's first `git add -A`
    # starts committing generated artifacts again and verify.sh --require goes red on an untouched tree.
    if [ -f "$_pe/profiles/.gitignore" ] && grep -q '^obj/$' "$_pe/profiles/.gitignore" 2>/dev/null; then
      echo "selftest PASS: incept kept profiles/.gitignore with its rules intact (K4 cannot return silently)"
    else
      echo "selftest FAIL: profiles/.gitignore did not survive the prune (or lost its rules) — K4 REGRESSION"; st=1
    fi
    # (b) WORKING-TREE .kit-manifest: zero foreign-profile lines, selected profile still listed.
    _wman=$(cat "$_pe/.kit-manifest" 2>/dev/null || true)
    _wf=$(manifest_foreign_count "$_wman")
    _wk=$(printf '%s\n' "$_wman" | grep -cE '^profiles/typescript-node/' || true)
    if [ "$_wf" = 0 ] && [ "$_wk" -gt 0 ]; then
      echo "selftest PASS: working-tree .kit-manifest reconciled (0 foreign lines, $_wk kept-profile lines)"
    else
      echo "selftest FAIL: working-tree .kit-manifest not reconciled (foreign=$_wf kept=$_wk)"; st=1
    fi
    # (c) kit-base REF .kit-manifest: same — kit-update reads THIS first, so a stale base = phantom deletions.
    _bman=$( cd "$_pe" && git show kit-base:.kit-manifest 2>/dev/null || true )
    if [ -n "$_bman" ]; then
      _bf=$(manifest_foreign_count "$_bman")
      _bk=$(printf '%s\n' "$_bman" | grep -cE '^profiles/typescript-node/' || true)
      if [ "$_bf" = 0 ] && [ "$_bk" -gt 0 ]; then
        echo "selftest PASS: kit-base:.kit-manifest reconciled (0 foreign lines, $_bk kept-profile lines)"
      else
        echo "selftest FAIL: kit-base:.kit-manifest not reconciled (foreign=$_bf kept=$_bk) — kit-update would rebuild a phantom-deletion base"; st=1
      fi
    else
      echo "selftest FAIL: no kit-base:.kit-manifest after incept (expected the captured base)"; st=1
    fi
  else
    echo "selftest FAIL: incept (prune suite) exited non-zero (rc=$?)"; printf '%s\n' "$INCEPT_OUT" | tail -5 | sed 's/^/    /'; st=1
  fi
  rm -rf "$_pt"
}

# ===========================================================================================
# CP-7 recert (K3) — INERT CODEOWNERS. incept copied profiles/<stack>/CODEOWNERS verbatim, so a fresh
# adopter shipped an ACTIVE @your-org/* rule; with require_code_owner_reviews on, those non-existent
# owners block EVERY merge. incept now comments every active rule (inert) and seeds an active `*  @handle`
# rule ONLY when --intent-owner is an explicit @handle (OWNER is free text otherwise; a blind substitution
# is invalid CODEOWNERS syntax). Proven by LIVE incept over the pristine export. LOAD-BEARING: pre-fix
# incept shipped an active @your-org line, so T-a/T-c/T-d FAIL without the fix; T-b proves the "active
# placeholder" predicate has teeth (a dead always-pass predicate reds here).
# ===========================================================================================
codeowners_active_placeholder() {  # <file> -> rc 0 iff an ACTIVE (uncommented) @your-org line exists
  grep -Eq '^[[:space:]]*[^#].*@your-org' "$1" 2>/dev/null
}
codeowners_active_rule_count() {  # <file> -> count of active (uncommented) ownership rule lines
  grep -Ec '^[[:space:]]*[^#[:space:]].*@' "$1" 2>/dev/null || true
}
codeowners_inert_tests() {  # appends to $st (0 = all good)
  # T-b FIRST (predicate teeth, no incept needed): a hand-built ACTIVE @your-org file must trip the predicate,
  # and a COMMENTED one must NOT — else T-a would false-pass or false-fail on our own inert output.
  _cb=$(mktemp -d) || { echo "selftest FAIL: codeowners fixture — no tmpdir (fail-closed)"; st=1; return 0; }
  printf '%s\n' '*            @your-org/engineering' > "$_cb/CODEOWNERS"
  if codeowners_active_placeholder "$_cb/CODEOWNERS"; then
    echo "selftest PASS: active-placeholder predicate has teeth (an active @your-org line is detected)"
  else
    echo "selftest FAIL: active-placeholder predicate did NOT detect an active @your-org line (VACUOUS)"; st=1
  fi
  printf '%s\n' '# *            @your-org/engineering' > "$_cb/CODEOWNERS"
  if codeowners_active_placeholder "$_cb/CODEOWNERS"; then
    echo "selftest FAIL: predicate flagged a COMMENTED @your-org line as active (would break inert output)"; st=1
  else
    echo "selftest PASS: commented @your-org line correctly treated as inert"
  fi
  rm -rf "$_cb"

  # Build the pristine export ONCE for the fresh_export_tree calls below — SELF-CONTAINED: the prune test
  # above uses adopter-export (not make_pristine_export), so $INCEPT_PRISTINE is NOT guaranteed set here.
  # (Skipping this is what let fresh_export_tree see an empty $INCEPT_PRISTINE and copy the root filesystem.)
  make_pristine_export || { echo "selftest FAIL: codeowners fixture — make_pristine_export failed"; st=1; return 0; }

  # T-a (inert) + T-d (bare-name inert): fresh_export_tree carries the under-test incept.sh (make_pristine_
  # export's worktree overlay), so no adopter-export/overlay-cp needed — cheaper (cp -R) and mirrors T-e/T-f.
  # baseline run_incept passes `--intent-owner probe` (a bare NON-@ token) -> the emitted .github/CODEOWNERS
  # must ship NO active @your-org rule and ZERO active rules.
  _t=$(fresh_export_tree) || { echo "selftest FAIL: codeowners inert fixture — no tree"; st=1; return 0; }
  if run_incept "$_t"; then
    _co="$_t/.github/CODEOWNERS"
    if [ -f "$_co" ] && ! codeowners_active_placeholder "$_co"; then
      echo "selftest PASS: emitted .github/CODEOWNERS ships NO active @your-org rule (owner-review can't block)"
    else
      echo "selftest FAIL: emitted .github/CODEOWNERS has an ACTIVE @your-org rule (K3 regression) or is missing"; st=1
    fi
    _arc=$(codeowners_active_rule_count "$_co")
    if [ "${_arc:-1}" = 0 ]; then
      echo "selftest PASS: bare-name intent-owner -> fully inert CODEOWNERS (0 active rules)"
    else
      echo "selftest FAIL: bare-name intent-owner left $_arc active rule(s) (expected 0 — inert)"; st=1
    fi
  else
    echo "selftest FAIL: incept (codeowners inert run) exited non-zero (rc=$?)"; printf '%s\n' "$INCEPT_OUT" | tail -5 | sed 's/^/    /'; st=1
  fi
  rm -rf "$_t"

  # T-c (seed): live incept with an explicit @handle -> ONE active `*  @handle` rule, still no active @your-org.
  _t=$(fresh_export_tree) || { echo "selftest FAIL: codeowners seed fixture — no tree"; st=1; return 0; }
  if run_incept "$_t" --intent-owner '@sw-test-owner'; then
    _co="$_t/.github/CODEOWNERS"
    if grep -Eq '^[[:space:]]*\*[[:space:]]+@sw-test-owner$' "$_co" 2>/dev/null && ! codeowners_active_placeholder "$_co"; then
      echo "selftest PASS: explicit @handle intent-owner -> active '*  @sw-test-owner' seed, no active @your-org"
    else
      echo "selftest FAIL: @handle intent-owner did not seed an active '*  @sw-test-owner' rule (or left active @your-org)"; st=1
    fi
  else
    echo "selftest FAIL: incept (codeowners seed run) exited non-zero (rc=$?)"; printf '%s\n' "$INCEPT_OUT" | tail -5 | sed 's/^/    /'; st=1
  fi
  rm -rf "$_t"

  # T-e (INJECTION guard, dual-review Important): a control-char / multi-line --intent-owner must be
  # REFUSED at parse (exit 2, reject-by-default like --stack/T9) — never flowed into a `sed` stamp (where it
  # died with a cryptic "unescaped newline") nor into the CODEOWNERS seed (a per-line handle validator would
  # pass the first line and inject the rest as ACTIVE rules, re-opening K3). Load-bearing: exit 2 + no
  # CODEOWNERS written; the discriminating message (not just the exit code) is asserted.
  _t=$(fresh_export_tree) || { echo "selftest FAIL: codeowners inject fixture — no tree"; st=1; return 0; }
  _rc=0; run_incept "$_t" --intent-owner "$(printf '@acme\n/pwned/  @intruder')" || _rc=$?
  if [ "$_rc" = 2 ] && printf '%s\n' "$INCEPT_OUT" | grep -q 'intent-owner contains control characters' \
       && [ ! -f "$_t/.github/CODEOWNERS" ]; then
    echo "selftest PASS: control-char/multi-line --intent-owner REFUSED (exit 2), no CODEOWNERS written (no injection)"
  else
    echo "selftest FAIL: control-char --intent-owner rc=$_rc (expected 2) / message missing / CODEOWNERS written — injection or cryptic-fail path"; st=1
    grep -nE '@intruder|/pwned/' "$_t/.github/CODEOWNERS" 2>/dev/null | sed 's/^/    injected> /'
  fi
  rm -rf "$_t"

  # T-f (SIBLING, dual-review sibling-surfacing): --name has the SAME free-text -> sed-stamp flow, so a
  # control-char --name is refused at parse too (the guard is not intent-owner-only).
  _t=$(fresh_export_tree) || { echo "selftest FAIL: codeowners name-sibling fixture — no tree"; st=1; return 0; }
  _rc=0; run_incept "$_t" --name "$(printf 'Proj\n@evil')" || _rc=$?
  if [ "$_rc" = 2 ] && printf '%s\n' "$INCEPT_OUT" | grep -q 'name contains control characters'; then
    echo "selftest PASS: control-char --name REFUSED at parse (exit 2, sibling of the intent-owner guard)"
  else
    echo "selftest FAIL: control-char --name rc=$_rc (expected 2) / message missing — sed-stamp injection sibling not guarded"; st=1
  fi
  rm -rf "$_t"
}

# ===========================================================================================
# T9 — SECURITY BLOCKER: `--stack` sed-injection -> arbitrary file write (CONTROL-PLANE). The stack
# flows into a `#`-delimited `sedi` stamp in incept.sh, and kit-update REPLAYS incept with the stack
# read back out of an adopter-controlled CLAUDE.md — so an unvalidated stack is an arbitrary-write sink
# in a script every adopter runs. The reproduced PoC used sed's `w` to write a file at rc=0:
#   incept ... --stack 'ts#;w ..PWNED_ARBITRARY_WRITE'   # => writes ..PWNED_ARBITRARY_WRITE, rc=0.
#
# Two defenses in depth, both asserted by LIVE incept runs (same shape as the --date suite):
#   1. --stack is validated against the shipped profiles/ registry, reject-by-default, at PARSE time
#      (before any file mutation) — exactly as --ci/--harness/--team are.
#   2. esc() escapes the `#` delimiter, so even a #-bearing value that somehow reached the stamp cannot
#      terminate the `s#..#..#` program (belt-and-braces; a direct esc() unit below).
# ===========================================================================================
incept_stack_tests() {  # appends to $st (0 = all good)
  if ! make_pristine_export; then
    echo "selftest FAIL: --stack fixture setup — could not build the pristine export tree (fail-closed)"; st=1; return 0
  fi

  # --- (a) THE REGRESSION THAT MATTERS: every VALID shipped stack still incepts unchanged. The valid
  #         set is DERIVED from profiles/<stack>/ (one source of truth) — never a hardcoded list that
  #         would drift out of sync with what the registry check accepts. run_incept passes a fixed
  #         `--stack typescript-node`; the trailing `--stack $_sk` overrides it (last flag wins). ---
  # `find`, not a `profiles/*/` glob: this script runs `set -euf`, so pathname expansion is OFF.
  _stacks=$(find "$REPO_ROOT/profiles" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's#.*/##' || true)
  [ -n "$_stacks" ] || { echo "selftest FAIL: --stack (a) — no profiles/<stack>/ registry found (fail-closed)"; st=1; }
  for _sk in $_stacks; do
    _t=$(fresh_export_tree) || { echo "selftest FAIL: --stack fixture (a) — no tree"; st=1; return 0; }
    _rc=0; run_incept "$_t" --stack "$_sk" || _rc=$?
    if [ "$_rc" -eq 0 ] && [ "$(stamped_cfg "$_t" 'Stack profile' "$_sk")" = 1 ] && slot_filled_once "$_t" 'Stack profile'; then
      echo "selftest PASS: valid --stack '$_sk' -> incepts (rc=0) and stamps §3 **Stack profile**: $_sk (registry accepts every shipped stack)"
    else
      echo "selftest FAIL: valid --stack '$_sk' -> rc=$_rc / stamp missing — the registry check REJECTED a legitimate stack (REGRESSION)"; st=1
    fi
    rm -rf "$_t"
  done

  # --- (b) THE BLOCKER: an unvalidated / injection stack must be REFUSED (exit 2), write NO file, and
  #         leave the tree PRISTINE. `ts#;w <path>` is the reproduced sed-injection PoC (both an absolute
  #         detect-path and the literal brief payload); 'nonesuch' is a plain unknown; '-oops' proves a
  #         value starting with `-` is consumed as the stack VALUE (not mis-parsed as a flag) and then
  #         rejected. ONE FRESH TREE PER CASE (a fell-open case would incept the shared tree and mask the
  #         next), mirroring the --date suite. ---
  _pwn="${TMPDIR:-/tmp}/kw-stack-pwn-$$"
  for _bad in "ts#;w $_pwn" 'ts#;w ..PWNED_ARBITRARY_WRITE' 'nonesuch' '-oops'; do
    rm -f "$_pwn"
    _t=$(fresh_export_tree) || { echo "selftest FAIL: --stack fixture (b) — no tree"; st=1; return 0; }
    _rc=0; run_incept "$_t" --stack "$_bad" || _rc=$?
    if [ "$_rc" -eq 2 ]; then
      echo "selftest PASS: --stack '$_bad' -> REFUSED (exit 2, reject-by-default vs the profiles/ registry)"
    else
      echo "selftest FAIL: --stack '$_bad' -> rc=$_rc (expected 2 — an unvalidated stack is a sed-injection / arbitrary-write sink)"; st=1
    fi
    if [ ! -e "$_t/ENGINEERING-PRINCIPLES.md" ] && [ ! -e "$_pwn" ] && [ ! -e "$_t/..PWNED_ARBITRARY_WRITE" ]; then
      echo "selftest PASS: --stack '$_bad' left the tree PRISTINE and wrote NO file (no sed 'w' fired, no mutation)"
    else
      echo "selftest FAIL: --stack '$_bad' MUTATED the tree or wrote a file despite being invalid (ARBITRARY WRITE)"; st=1
    fi
    rm -rf "$_t"
  done
  rm -f "$_pwn"

  # --- (c) esc() UNIT — the hardening that closes the `#`-delimited stamp sinks even if a #-bearing
  #         value ever reached one. BEHAVIOURAL, not a source grep: pull the real esc() definition out
  #         of incept.sh, feed a `w <path>` injection through it into a genuine `s#..#..#` program, and
  #         assert (1) NO file is written and (2) the `#` survives as a literal (the payload round-trips).
  #         With esc() escaping `#`, the delimiter can no longer terminate the program. ---
  _epwn="${TMPDIR:-/tmp}/kw-esc-pwn-$$"; rm -f "$_epwn"
  _escline=$(grep -E '^esc\(\) \{' "$REPO_ROOT/scripts/incept.sh" 2>/dev/null || true)
  if [ -n "$_escline" ]; then
    eval "$_escline"
    _payload="a#;w $_epwn"
    # `|| _res=...` + 2>/dev/null: an UN-hardened esc() lets the payload's `#` split the program so sed
    # tries to open the `w` target and exits non-zero — that must fail this assertion CLEANLY, not abort
    # the whole selftest under `set -e` (and the sed error must not leak to the log).
    _res=$(printf 'X\n' | sed "s#X#$(esc "$_payload")#" 2>/dev/null) || _res='<sed-injection-fired>'
    if [ ! -e "$_epwn" ] && [ "$_res" = "$_payload" ]; then
      echo "selftest PASS: esc() escapes the # delimiter -> a 'w <path>' payload cannot terminate a s#..# program (no write; # survives literal)"
    else
      echo "selftest FAIL: esc() did NOT neutralize the # delimiter — the sed-injection sink is still open (wrote=$([ -e "$_epwn" ] && echo yes || echo no), res='$_res')"; st=1
    fi
    rm -f "$_epwn"
  else
    echo "selftest FAIL: esc() unit — could not locate the esc() definition in incept.sh (fail-closed)"; st=1
  fi

  # --- (d) SOURCE INVARIANT (mirrors the --date (d) lock): esc()'s escaped character class MUST include
  #         the `#` delimiter. Deleting `#` from the class must break THIS line — the future-proofing that
  #         keeps every `#`-delimited stamp sink closed even if the behavioural payload above is ever lost. ---
  if grep -Eq "^esc\(\) \{.*sed 's/\[[^]]*#[^]]*\]" "$REPO_ROOT/scripts/incept.sh"; then
    echo "selftest PASS: esc()'s escaped set includes the # delimiter (source lock — every #-delimited stamp is safe)"
  else
    echo "selftest FAIL: esc() no longer escapes # — the #-delimited stamp sinks are exposed"; st=1
  fi

  rm -rf "$INCEPT_PRISTINE"; INCEPT_PRISTINE=''
}

# ===========================================================================================
# run_check TARGET MANIFEST — parse the manifest block-by-block, resolve each mechanism, print a
# verdict + the honest ceiling. Sets RC (0 clean / 1 misconfigured-red / 2 setup error).
# ===========================================================================================
run_check() {
  DIR="$1"; MANIFEST="$2"; CI="$DIR/ci.yml"
  RC=0; GREENS=0; SKIPS=0; NAS=0; REDS=0
  [ -f "$MANIFEST" ] || { echo "MISCONFIGURED: manifest not found: $MANIFEST (fail-closed)" >&2; RC=2; return 2; }
  [ -f "$CI" ]       || { echo "MISCONFIGURED: ci.yml not found: $CI (fail-closed)" >&2; RC=2; return 2; }

  # LIVE-config view: strip `#` comments so present/absent assert the live YAML, not documentation.
  CI_CODE="${TMPDIR:-/tmp}/kw3-cicode-$$.yml"
  # Clean up the temp file on ANY exit path (incl. the fail-closed sed return below) — no $$-temp leak.
  trap 'rm -f "$CI_CODE"' EXIT
  sed 's/#.*//' "$CI" > "$CI_CODE" 2>/dev/null || { echo "MISCONFIGURED: cannot read ci.yml: $CI (fail-closed)" >&2; RC=2; return 2; }

  echo "first-run-green: archetype $DIR"
  echo "  manifest: $MANIFEST"

  reset_block
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    _key=${line%%:*}
    case "$line" in *': '*) _val=${line#*: } ;; *) _val='' ;; esac
    case "$_key" in
      id)           [ -n "$id" ] && resolve_mechanism; reset_block; id=$_val ;;
      precondition) precond=$_val ;;
      when-absent)  whenabsent=$_val ;;
      assert)       asserts="${asserts}${_val}
" ;;
      skip-reason)  skipreason=$_val ;;
      fix-hint)     fixhint=$_val ;;
      *)            : ;;
    esac
  done < "$MANIFEST"
  [ -n "$id" ] && resolve_mechanism

  echo "  ---"
  echo "  summary: $GREENS GREEN, $SKIPS SKIPPED-WITH-REASON, $NAS N/A, $REDS MISCONFIGURED-RED"
  echo "  honest ceiling: proves the shipped archetype's gates are green-or-legibly-skipped on first"
  echo "  run; cannot prove a mechanism no scaffold exercises. This is a CONFIG-SHAPE proof: it shows"
  echo "  the gates are WIRED, never that they PASS on a real tree. The artifact-gate CI job proves"
  echo "  that (export -> incept -> the adopter's verify.sh --require + the exact SAST command)."
  if [ "$REDS" -gt 0 ]; then
    echo "FAIL: $REDS misconfigured-red mechanism(s) — first run would NOT be green"
  else
    echo "OK: every expected mechanism is GREEN-or-legibly-SKIPPED on first run"
  fi
  rm -f "$CI_CODE"
  return "$RC"
}

# ===========================================================================================
# --selftest — the NON-VACUITY heart. Good fixture (liveness) + 5 mutated-config negatives + a
# mandatory LOCK SELF-NEGATIVE. Self-contained: fixtures under $FIXTURES, uses the delivered manifest.
# ===========================================================================================
selftest() {
  st=0
  # DISK-SPACE PREFLIGHT (seatbelt): the live-incept sub-tests below build full-repo temp trees. Refuse to
  # START if free space is under the floor, so a conformance run can NEVER fill the disk — worst case is a
  # loud abort telling you to free space, not a wedged machine. Kit-dev safety; CI runners have ample space.
  # (Checks the REAL $TMPDIR here, before the base-dir redirection below.)
  # Ephemeral CI (GitHub Actions etc.) DISCARDS its disk after the run, so the hazard this guards — filling
  # a PERSISTENT dev machine — doesn't exist there, and a low-but-sufficient runner (~14 GiB free) must not
  # false-abort. Coverage is UNCHANGED: CI has ample disk and still runs every test; only the "should I
  # start?" resource gate is skipped where disk is throwaway. Local dev keeps the seatbelt.
  if [ -z "${CI:-}${GITHUB_ACTIONS:-}" ]; then
    _kw3_floor_kb=20971520   # 20 GiB
    _kw3_avail_kb=$(df -k "${TMPDIR:-/tmp}" 2>/dev/null | awk 'NR==2 {print $4}')
    case "$_kw3_avail_kb" in
      ''|*[!0-9]*) echo "selftest: WARN — could not read free space for ${TMPDIR:-/tmp}; proceeding" >&2 ;;
      *) if [ "$_kw3_avail_kb" -lt "$_kw3_floor_kb" ]; then
           echo "selftest ABORT: only $((_kw3_avail_kb / 1024 / 1024)) GiB free in ${TMPDIR:-/tmp} (need >= 20 GiB)." >&2
           echo "  The live-incept conformance tests build full-repo temp trees; refusing to run rather than fill the disk." >&2
           echo "  Free space (clear \$TMPDIR/tmp.* and 'sudo tmutil deletelocalsnapshots /'), then re-run." >&2
           return 1
         fi ;;
    esac
  fi
  # DISK HYGIENE (kit-dev): every live-incept sub-test builds a full-repo mktemp tree. Nest them ALL under
  # ONE base and trap-clean it, so an INTERRUPTED run (kill / SIGTERM-timeout / ENOSPC / Ctrl-C) can't
  # orphan gigabytes of trees — the leak that silently reached ~294 GB over the CP-7 arc. Sub-tests still
  # rm their own dirs (early free); this trap is the crash backstop. Only SIGKILL escapes it (uncatchable).
  # This is kit-DEVELOPMENT machinery (this check N/As on an adopter tree); the trap keeps kit builds clean.
  _kw3_tmpbase=$(mktemp -d) || { echo "selftest FAIL: cannot create temp base (fail-closed)"; return 1; }
  # EXIT does the single cleanup; a signal just exits (which fires EXIT) — never RESUME after a signal, or
  # execution limps on into a base the handler already deleted.
  trap 'rm -rf "$_kw3_tmpbase"' EXIT
  trap 'exit 143' TERM
  trap 'exit 130' INT
  TMPDIR="$_kw3_tmpbase"; export TMPDIR
  MAN="$(resolve_manifest_default typescript-node)" \
    || { echo "selftest FAIL: cannot resolve the TS/Node manifest"; return 1; }

  # --- LIVENESS ANCHOR: the good fixture -> every mechanism GREEN-or-SKIPPED, exit 0. ---
  if out=$(KW3_NOLIVE=1 sh "$0" --manifest "$MAN" "$FIXTURES/good" 2>&1); then
    if printf '%s\n' "$out" | grep -q '\[RED\]'; then
      echo "selftest FAIL: good fixture emitted a [RED] verdict"; printf '%s\n' "$out" | sed 's/^/    /'; st=1
    else
      echo "selftest PASS: good fixture -> all GREEN-or-SKIPPED (exit 0)"
    fi
  else
    echo "selftest FAIL: good fixture exited non-zero"; printf '%s\n' "$out" | sed 's/^/    /'; st=1
  fi

  # --- N/A path: a non-DB good fixture -> db-postgres omitted as N/A (not a skip), rest GREEN, exit 0. ---
  if out=$(KW3_NOLIVE=1 sh "$0" --manifest "$MAN" "$FIXTURES/good-nodb" 2>&1); then
    if printf '%s\n' "$out" | grep -q '\[N/A\][[:space:]]*db-postgres'; then
      echo "selftest PASS: non-DB fixture -> db-postgres omitted as N/A (omit != skip)"
    else
      echo "selftest FAIL: non-DB fixture did not mark db-postgres N/A"; printf '%s\n' "$out" | sed 's/^/    /'; st=1
    fi
  else
    echo "selftest FAIL: non-DB fixture exited non-zero"; printf '%s\n' "$out" | sed 's/^/    /'; st=1
  fi

  # --- 5 LOAD-BEARING NEGATIVES: each mutated fixture -> FAIL naming that mechanism. ---
  check_negative() {  # fixture-dir mechanism-id
    _fx="$1"; _mech="$2"
    # Capture rc via `if` — a bare `_o=$(...)` under set -e would abort on the (expected) non-zero exit.
    if _o=$(KW3_NOLIVE=1 sh "$0" --manifest "$MAN" "$FIXTURES/$_fx" 2>&1); then _rc=0; else _rc=$?; fi
    if [ "$_rc" -ne 0 ] && printf '%s\n' "$_o" | grep -q "\[RED\][[:space:]]*$_mech"; then
      echo "selftest PASS: $_fx -> MISCONFIGURED-RED naming '$_mech' (rc=$_rc)"
    else
      echo "selftest FAIL: $_fx (rc=$_rc) did not RED-name '$_mech'"; printf '%s\n' "$_o" | sed 's/^/    /'; st=1
    fi
  }
  check_negative bad-db-postgres        db-postgres
  check_negative bad-sast-narrowed      sast-scoped
  check_negative bad-secret-gitignore   secret-gate
  check_negative bad-provenance-ungated provenance-gated
  check_negative bad-agent-trace        agent-trace-emit

  # --- P1.2 (T1b): the `--date` reproducible-stamp seam, on LIVE incept runs. Skipped inside the
  #     neutered inner run (KW3_INNER): that run exists to prove `predicate_holds` is load-bearing, and
  #     these live incepts are orthogonal to it — running them twice would only cost CI time. ---
  if [ -z "${KW3_INNER:-}" ]; then
    incept_date_tests
    incept_stamp_tests
    incept_stack_tests
    incept_prune_tests
    codeowners_inert_tests
  fi

  # --- ★ LOCK SELF-NEGATIVE (mandatory): neutralize the detector (predicate_holds -> always-true) and
  #     assert its --selftest FAILS. A dead/always-green detector must NOT pass — else the whole proof
  #     is theater. Skipped inside the inner (neutered) run via KW3_INNER to avoid recursion. ---
  if [ -z "${KW3_INNER:-}" ]; then
    NEUT="${TMPDIR:-/tmp}/kw3-neutered-$$-detector.sh"
    awk '/^predicate_holds\(\) \{$/ { print; print "  return 0  # NEUTERED (lock self-negative)"; next } { print }' "$0" > "$NEUT"
    if grep -q 'NEUTERED' "$NEUT"; then
      if KW3_INNER=1 KW3_NOLIVE=1 KW3_FIXTURES="$FIXTURES" KW3_MANIFEST="$MAN" sh "$NEUT" --selftest >/dev/null 2>&1; then
        echo "selftest FAIL: LOCK SELF-NEGATIVE did NOT fire — a neutered always-green detector still PASSED (VACUOUS)"; st=1
      else
        echo "selftest PASS: LOCK SELF-NEGATIVE fired — the neutered always-green detector FAILS its own selftest (asserts are LOAD-BEARING)"
      fi
    else
      echo "selftest FAIL: LOCK SELF-NEGATIVE setup — neutralization did not land in the copy"; st=1
    fi
    rm -f "$NEUT"
  fi

  if [ "$st" = 0 ]; then
    echo "OK: incept-first-run-green selftest — anchor + N/A + 5 load-bearing negatives + lock self-negative"
  else
    echo "FAIL: incept-first-run-green selftest"
  fi
  return "$st"
}

# ===========================================================================================
# Dispatch
# ===========================================================================================
MODE=check
TARGET=''
MANIFEST_ARG=''
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) MODE=selftest; shift ;;
    --manifest) MANIFEST_ARG="${2:-}"; shift 2 ;;
    --) shift; break ;;
    -*) echo "usage: incept-first-run-green.sh [--selftest] [--manifest M] [TARGET]" >&2; exit 2 ;;
    *)  TARGET="$1"; shift ;;
  esac
done

# Kit-self N/A guard (mirrors adopter-export-wired.sh + its "kit-self pattern" guidance): this
# detector validates the KIT's OWN shipped profiles ship first-run-green — it has no meaning on an
# adopter's exported tree (already incepted). N/A-
# skip when BOTH kit markers are absent (the export strips both; golden-path.yml is control-plane +
# export-ignored, so the marker set is un-spoofable). In the kit repo both are present -> full run.
# Gated on KW3_INNER being unset: the lock self-negative's neutered copy runs from $TMPDIR (no markers)
# with KW3_INNER=1 — it MUST bypass this guard and actually run, else the self-negative can't fire.
if [ -z "${KW3_INNER:-}" ] && [ ! -f "$REPO_ROOT/docs/ROADMAP-KIT.md" ] && [ ! -f "$REPO_ROOT/.github/workflows/golden-path.yml" ]; then
  echo "incept-first-run-green: N/A — kit-self check (not applicable outside the kit repo)"
  exit 0
fi

if [ "$MODE" = selftest ]; then
  selftest; exit $?
fi

[ -n "$TARGET" ] || TARGET="$REPO_ROOT/profiles/typescript-node"
_base="$(basename "$TARGET")"
if [ -n "$MANIFEST_ARG" ]; then
  MAN="$MANIFEST_ARG"
else
  MAN="$(resolve_manifest_default "$_base")" \
    || { echo "MISCONFIGURED: no manifest for archetype '$_base' (looked for manifest-$_base.txt / incept-manifests/$_base.txt) — fail-closed" >&2; exit 2; }
fi
run_check "$TARGET" "$MAN"; exit $?
