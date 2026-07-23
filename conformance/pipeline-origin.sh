#!/bin/sh
# pipeline-origin.sh — incept STAMPS a pipeline-origin marker into the CI pipeline it installs,
# and that marker is NON-COLLIDING with cp_kit_replace's kit-own EREs.
#
# WHY (CP7R5-GATE-AUTHORITY §4, ratified 2026-07-22 — option P2). `verify-enforced-wired.sh` must
# tell DRIFT (the kit installed the pipeline and someone stripped a step) apart from an UNMET
# DOCUMENTED MERGE OBLIGATION (the adopter owns the pipeline — the brownfield path
# docs/adoption/brownfield.md instructs them to merge the gate-ids by hand). Nothing in an adopter
# tree recorded which of those two it is: `grep -cE 'Kit-own CI|Sparkwright'` is 0 for all 11 emitted
# pipelines, and `.kit-manifest` records the EXPORT's file list (workflows are export-ignored), never
# an installed path. P2 puts the provenance INTO the artifact it describes, written by the act of
# installation, so it cannot go stale relative to that artifact and survives a rename.
#
# THE DATA-SAFETY INVARIANT THIS CHECK EXISTS FOR. cp_kit_replace (scripts/incept.sh) overwrites a
# destination that matches its kit-own ERE and preserves anything else. If the origin marker ever
# MATCHED that ERE, installing it would silently flip incept from PRESERVE to OVERWRITE on a re-run
# and clobber an adopter's edited CI. Case-sensitivity is too fragile a basis for that claim, so this
# check derives BOTH the marker and the EREs from scripts/incept.sh itself and asserts non-collision
# against the real values — plus a live incept over a marker-bearing pipeline that must be preserved.
#
# What it changes: nothing (read-only verification; drives real incepts inside a trap-cleaned temp dir).
# Guardrails: three-state (0 ok · 1 violation · 2 UNVERIFIED); marker + EREs derived from scripts/incept.sh,
# never from a hand-copied duplicate; every fixture tree lives under one trap-cleaned mktemp root.
#
# HONEST CEILING: this proves the marker IS WRITTEN on both install paths, that a brownfield-PRESERVED
# adopter pipeline is NOT stamped, and that the marker does not collide with the overwrite EREs. It does
# NOT prove an adopter cannot REMOVE the marker. Under §4 that removal is an accepted self-assertion of
# ownership BECAUSE it downgrades enforcement to a DISCLOSED N/A rather than a silent pass — but that
# downgrade is Task 2 (verify-enforced-wired.sh) and is NOT shipped with this check; today a missing step
# still hard-FAILs. This check makes no claim about un-removability, and no verdict it prints is one.
#   sh conformance/pipeline-origin.sh            # real run (drives incept)
#   sh conformance/pipeline-origin.sh --selftest # mutation proof it has teeth
# Exit: 0 = ok · 1 = violation · 2 = UNVERIFIED (git absent, setup failed). POSIX sh.
set -eu

# The contract string. Task 2's disposition matrix reads exactly this; incept must write exactly this.
MARKER='# kit-pipeline-origin: emitted'
GH_WF='.github/workflows/ci.yml'
GL_WF='.gitlab-ci.yml'
STACK='typescript-node'          # the one profile shipping BOTH a ci.yml and a ci.gitlab-ci.yml

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
if [ -d "$SCRIPT_DIR/../profiles" ]; then
  REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
elif [ -d "$SCRIPT_DIR/../../profiles" ]; then
  REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
else
  REPO_ROOT="$SCRIPT_DIR"
fi

# Kit-self N/A guard (mirrors harness-ceiling-disclosed.sh) — it MUST precede the git/mktemp
# preconditions below, not follow them. Both modes drive incept from a `git archive HEAD` export, which is
# meaningless on an already-incepted adopter tree; if the guard sat after them, an adopter container
# without `git` would exit 2 = UNVERIFIED, and verify.sh --require treats UNVERIFIED as a failure — a
# blocking RED on every such adopter for a check that is N/A there. N/A-skip when BOTH kit markers are
# absent (the export strips both; golden-path.yml is control-plane + export-ignored, so the marker set is
# un-spoofable). Placed before the mode dispatch so it covers BOTH `run` and `--selftest`.
if [ ! -f "$REPO_ROOT/docs/ROADMAP-KIT.md" ] && [ ! -f "$REPO_ROOT/.github/workflows/golden-path.yml" ]; then
  echo "pipeline-origin: N/A — kit-self check (not applicable outside the kit repo)"
  exit 0
fi

command -v git >/dev/null 2>&1 || { echo "UNVERIFIED: git not installed (needed to build the pristine export)"; exit 2; }

TMPROOT=$(mktemp -d) || { echo "UNVERIFIED: mktemp failed"; exit 2; }
# shellcheck disable=SC2064 # expand TMPROOT now — it is fixed for the life of the process
# EXIT alone leaks the whole fixture root on ^C / kill — and leaked full-repo fixture trees have twice
# filled this project's work machine. Trap the interrupt signals too.
trap "rm -rf '$TMPROOT'" EXIT INT TERM

PRISTINE="$TMPROOT/pristine"
SENTINEL='# ADOPTER-OWNED SENTINEL — must survive incept'

# --- shared check logic ------------------------------------------------------------------------

# classify_pipeline <file> — the provenance verdict Task 2 consumes: emitted | adopter | none.
classify_pipeline() {
  [ -f "$1" ] || { printf 'none\n'; return 0; }
  if grep -qF "$MARKER" "$1"; then printf 'emitted\n'; else printf 'adopter\n'; fi
}

# incept_marker <incept.sh> — the marker literal incept ACTUALLY writes (single source of truth).
incept_marker() {
  awk -F"'" '/^PIPELINE_ORIGIN_MARKER=/ { print $2; exit }' "$1"
}

# checker_marker <verify-enforced-wired.sh> — the marker literal the DISPOSITION CHECKER classifies by.
# verify-enforced-wired.sh runs on ADOPTER trees, which have no scripts/incept.sh, so it must carry the
# marker string itself rather than derive it. That duplication is a drift risk with a fail-OPEN failure
# mode: if the checker's marker diverged from incept's, the checker would read incept's real marker as
# "absent", classify every kit-emitted pipeline ADOPTER-owned, and silently downgrade the whole gate to
# N/A. This kit-only check IS able to see both files, so it locks them equal (D-2).
checker_marker() {
  awk -F"'" '/^PIPELINE_ORIGIN_MARKER=/ { print $2; exit }' "$1"
}

# kit_own_ere <incept.sh> <github|gitlab> — the overwrite ERE the install call site actually passes.
kit_own_ere() {
  if [ "$2" = github ]; then
    awk -F"'" '/install_pipeline .*\.github\/workflows\/ci\.yml/ { print $2; exit }' "$1"
  else
    awk -F"'" '/install_pipeline .* \.gitlab-ci\.yml /            { print $2; exit }' "$1"
  fi
}

# make_pristine_export — build ONCE the tree an adopter actually incepts: `git archive HEAD` (export
# semantics), then OVERLAY the worktree content of every modified tracked file so the run exercises the
# incept.sh UNDER CHANGE, not the committed one (a no-op in CI; load-bearing during development — it is
# what makes RED->GREEN real). Same idiom as conformance/harness-ceiling-disclosed.sh.
make_pristine_export() {
  mkdir -p "$PRISTINE"
  ( cd "$REPO_ROOT" && git archive HEAD ) | ( cd "$PRISTINE" && tar -xf - ) || return 1
  _mods=$( cd "$REPO_ROOT" && git diff --name-only HEAD ) || return 1
  for _mf in $_mods; do
    [ -f "$PRISTINE/$_mf" ] || continue          # export-ignored or deleted -> not in the adopter tree
    cp "$REPO_ROOT/$_mf" "$PRISTINE/$_mf" || return 1
  done
  # Setup anchors — fail LOUDLY rather than green the assertions below against a broken fixture.
  [ -f "$PRISTINE/scripts/incept.sh" ]                     || return 1
  [ -f "$PRISTINE/profiles/$STACK/ci.yml" ]                || return 1
  [ -f "$PRISTINE/profiles/$STACK/ci.gitlab-ci.yml" ]      || return 1
  # The export must not already carry an installed pipeline, or every "stamped" leg is vacuous.
  [ ! -f "$PRISTINE/$GH_WF" ] && [ ! -f "$PRISTINE/$GL_WF" ] || return 1
  return 0
}

fresh_tree() {  # echo a fresh, un-incepted copy of the pristine export (mktemp: unique per subshell call)
  _ft=$(mktemp -d "$TMPROOT/t.XXXXXX") || return 1
  cp -R "$PRISTINE/." "$_ft/" || return 1
  printf '%s\n' "$_ft"
}

plant_adopter_pipeline() {  # <tree> <rel-path> [extra-line] — a pre-existing, adopter-owned pipeline
  mkdir -p "$(dirname "$1/$2")"
  {
    [ -n "${3:-}" ] && printf '%s\n' "$3"
    printf '%s\n' "$SENTINEL"
    printf 'name: adopter\njobs:\n  build:\n    steps:\n      - run: echo hi\n'
  } > "$1/$2"
}

run_incept() {  # <tree> <github|gitlab> [extra-flag...] -> rc (output swallowed; the FILE is the assertion)
  _ri_tree=$1; _ri_ci=$2; shift 2
  ( cd "$_ri_tree" && sh scripts/incept.sh --name OriginProbe --intent-owner probe \
      --stack "$STACK" --backlog md --ci "$_ri_ci" --harness claude-code --noninteractive "$@" >/dev/null 2>&1 )
}

# (positive) a pipeline CARRYING the marker classifies emitted; one WITHOUT it classifies adopter.
assert_classify() {  # <file> <expected>
  _got=$(classify_pipeline "$1")
  [ "$_got" = "$2" ] && return 0
  echo "FAIL: classify_pipeline($1) = '$_got', expected '$2'"
  return 1
}

# (positive, real tree) incept installs the pipeline AND stamps the marker as LINE 1. Line 1 is
# load-bearing, not cosmetic: curate_db_backed -> strip_db_region deletes the bounded
# `# >>> kit:db-backed` … `# <<< kit:db-backed` region AFTER the §5 wiring block, so a marker placed
# inside that region would be deleted on a --no-db incept. A marker at the top survives.
assert_stamped() {  # <tree> <github|gitlab> <rel-path> [extra-incept-flag...]
  _as_t=$1; _as_ci=$2; _as_p=$3; shift 3
  run_incept "$_as_t" "$_as_ci" "$@" || true   # incept's rc is not the assertion — the installed FILE is
  set -- "$_as_t" "$_as_ci" "$_as_p"
  if [ ! -f "$1/$3" ]; then
    echo "FAIL: $2 — incept installed no pipeline at $3"; return 1
  fi
  if [ "$(classify_pipeline "$1/$3")" != emitted ]; then
    echo "FAIL: $2 — the installed pipeline $3 lacks the origin marker (classified adopter)"; return 1
  fi
  if [ "$(head -1 "$1/$3")" != "$MARKER" ]; then
    echo "FAIL: $2 — the origin marker is not line 1 of $3 (it must sit above the kit:db-backed region)"; return 1
  fi
  return 0
}

# (negative / data-safety) the marker incept WRITES must not match the ERE that makes cp_kit_replace
# OVERWRITE. A collision would silently turn a brownfield preserve into a clobber of an edited CI.
assert_non_colliding() {  # <marker> <ere> <label>
  if [ -z "$2" ]; then
    echo "FAIL: could not derive the $3 kit-own ERE from scripts/incept.sh (fail-closed)"; return 1
  fi
  if printf '%s\n' "$1" | grep -qE "$2"; then
    echo "FAIL: the origin marker '$1' MATCHES the $3 kit-own ERE '$2' — installing it would flip incept from preserve to OVERWRITE on re-run and clobber an adopter's edited CI"
    return 1
  fi
  return 0
}

# (coherence) the marker incept writes IS the contract string Task 2's matrix reads.
assert_marker_is_contract() {  # <derived-marker>
  if [ -z "$1" ]; then
    echo "FAIL: scripts/incept.sh declares no PIPELINE_ORIGIN_MARKER (fail-closed)"; return 1
  fi
  [ "$1" = "$MARKER" ] && return 0
  echo "FAIL: incept writes '$1' but the contract marker is '$MARKER'"
  return 1
}

# (coherence, D-2) the marker incept WRITES equals the marker the DISPOSITION CHECKER classifies BY.
# A divergence is fail-OPEN: the checker would read incept's real marker as absent and downgrade every
# emitted pipeline to a silent adopter-owned N/A. Both are DERIVED from their files, never hand-copied.
assert_markers_agree() {  # <incept-marker> <checker-marker>
  if [ -z "$2" ]; then
    echo "FAIL: conformance/verify-enforced-wired.sh declares no PIPELINE_ORIGIN_MARKER (fail-closed)"; return 1
  fi
  [ "$1" = "$2" ] && return 0
  echo "FAIL: incept writes '$1' but verify-enforced-wired.sh classifies by '$2' — a divergence downgrades every kit-emitted pipeline to a silent adopter-owned N/A"
  return 1
}

# (brownfield) a pipeline incept PRESERVED is an adopter's file — it must come back unchanged and
# UNSTAMPED. cp_kit_replace returns 0 on BOTH branches, so a blind post-call prepend would stamp a
# preserved adopter pipeline kit-emitted; the install path mirrors the write condition instead.
assert_preserved_unstamped() {  # <tree> <github|gitlab> <rel-path>
  run_incept "$1" "$2" || true
  if [ ! -f "$1/$3" ]; then
    echo "FAIL: brownfield $2 — the adopter's pipeline $3 was DELETED"; return 1
  fi
  if ! grep -qF "$SENTINEL" "$1/$3"; then
    echo "FAIL: brownfield $2 — the adopter's pipeline $3 was OVERWRITTEN (sentinel gone)"; return 1
  fi
  if grep -qF "$MARKER" "$1/$3"; then
    echo "FAIL: brownfield $2 — a PRESERVED adopter pipeline was stamped kit-emitted"; return 1
  fi
  return 0
}

# (re-run invariant, live) a pipeline already carrying the marker incept writes must still take the
# PRESERVE branch — the non-collision claim proven on a real tree rather than on a string.
assert_marked_preserved() {  # <tree> <github|gitlab> <rel-path> <marker-as-written>
  run_incept "$1" "$2" || true
  if [ ! -f "$1/$3" ]; then
    echo "FAIL: re-run $2 — a marker-bearing pipeline at $3 was DELETED"; return 1
  fi
  if ! grep -qF "$SENTINEL" "$1/$3"; then
    echo "FAIL: re-run $2 — a pipeline carrying the origin marker was CLOBBERED (sentinel gone): the marker collides with the kit-own overwrite ERE"; return 1
  fi
  if [ "$(grep -cF "$4" "$1/$3")" != 1 ]; then
    echo "FAIL: re-run $2 — the origin marker was re-stamped onto an already-marked pipeline (duplicate)"; return 1
  fi
  return 0
}

run() {
  make_pristine_export || { echo "UNVERIFIED: could not build the pristine export tree (fail-closed)"; exit 2; }
  _incept="$PRISTINE/scripts/incept.sh"

  # (1) POSITIVE, fixture: the classifier reads the marker. Positive legs FIRST and deliberately —
  #     a classifier broken SHUT satisfies every negative leg in this file perfectly.
  printf '%s\njobs: {}\n' "$MARKER" > "$TMPROOT/marked.yml"
  printf 'jobs: {}\n'               > "$TMPROOT/unmarked.yml"
  assert_classify "$TMPROOT/marked.yml"   emitted || exit 1
  echo "OK: a pipeline carrying the origin marker classifies 'emitted'."
  assert_classify "$TMPROOT/unmarked.yml" adopter || exit 1
  echo "OK: a pipeline without it classifies 'adopter'."

  # (2) POSITIVE, real trees: a live incept on BOTH platforms stamps the installed pipeline.
  _t=$(fresh_tree) || { echo "UNVERIFIED: could not stage a fresh tree"; exit 2; }
  assert_stamped "$_t" github "$GH_WF" || exit 1
  echo "OK: incept --ci github stamps the origin marker as line 1 of $GH_WF (live incept)."
  _t=$(fresh_tree) || { echo "UNVERIFIED: could not stage a fresh tree"; exit 2; }
  assert_stamped "$_t" gitlab "$GL_WF" || exit 1
  echo "OK: incept --ci gitlab stamps the origin marker as line 1 of $GL_WF (live incept)."

  # (2b, F3) --no-db is the ONE scenario the LINE-1 requirement exists to protect: curate_db_backed ->
  # strip_db_region rewrites the installed pipeline AFTER the §5 wiring, deleting the bounded
  # `# >>> kit:db-backed` … `# <<< kit:db-backed` region. A marker at the top survives that rewrite; a
  # marker inside the region would be deleted. Asserting line 1 on a NON-DB incept is what proves it.
  _t=$(fresh_tree) || { echo "UNVERIFIED: could not stage a fresh tree"; exit 2; }
  assert_stamped "$_t" github "$GH_WF" --no-db || exit 1
  echo "OK: incept --ci github --no-db still stamps the origin marker as line 1 (survives strip_db_region)."

  # (3) NEGATIVE / data safety: the marker incept writes is the contract string AND collides with
  #     neither overwrite ERE. Both values are DERIVED from scripts/incept.sh, never hand-copied.
  _m=$(incept_marker "$_incept")
  assert_marker_is_contract "$_m" || exit 1
  assert_non_colliding "$_m" "$(kit_own_ere "$_incept" github)" github || exit 1
  assert_non_colliding "$_m" "$(kit_own_ere "$_incept" gitlab)" gitlab || exit 1
  echo "OK: the marker incept writes is the contract string and matches neither kit-own overwrite ERE."
  assert_markers_agree "$_m" "$(checker_marker "$PRISTINE/conformance/verify-enforced-wired.sh")" || exit 1
  echo "OK: incept's marker and verify-enforced-wired.sh's classifier marker are the same string (D-2)."

  # (4) BROWNFIELD: a preserved adopter pipeline is returned unchanged and UNSTAMPED, both platforms.
  _t=$(fresh_tree) || { echo "UNVERIFIED: could not stage a fresh tree"; exit 2; }
  plant_adopter_pipeline "$_t" "$GH_WF"
  assert_preserved_unstamped "$_t" github "$GH_WF" || exit 1
  echo "OK: brownfield github — the adopter's $GH_WF is preserved and NOT stamped (live incept)."
  _t=$(fresh_tree) || { echo "UNVERIFIED: could not stage a fresh tree"; exit 2; }
  plant_adopter_pipeline "$_t" "$GL_WF"
  assert_preserved_unstamped "$_t" gitlab "$GL_WF" || exit 1
  echo "OK: brownfield gitlab — the adopter's $GL_WF is preserved and NOT stamped (live incept)."

  # (5) RE-RUN INVARIANT: a pipeline already carrying the marker still takes the PRESERVE branch.
  _t=$(fresh_tree) || { echo "UNVERIFIED: could not stage a fresh tree"; exit 2; }
  plant_adopter_pipeline "$_t" "$GH_WF" "$_m"
  assert_marked_preserved "$_t" github "$GH_WF" "$_m" || exit 1
  echo "OK: re-run github — a marker-bearing $GH_WF is preserved, not clobbered and not re-stamped."

  echo "OK: pipeline-origin — incept stamps '$MARKER' on both install paths, leaves a brownfield-preserved"
  echo "    pipeline untouched, and the marker does not collide with the overwrite EREs."
  echo "    CEILING: this does NOT prove an adopter cannot REMOVE the marker — §4 accepts that removal as a"
  echo "    self-assertion of ownership. The downgrade-to-a-DISCLOSED-N/A that makes it acceptable is NOT"
  echo "    shipped yet: it is Task 2 (verify-enforced-wired.sh), which today still hard-FAILs a missing step."
  exit 0
}

# --selftest — four mutants of incept.sh, applied ONE AT A TIME to their own fresh tree, each of which
# MUST flip a specific leg RED with its discriminating MESSAGE (asserting the message, not just a
# non-zero exit: an exit-code-only assertion is satisfied by any incidental failure). Mutating a PAIR
# and claiming the individuals are load-bearing produced three vacuous proofs in this slice's history —
# so the two stamp sites are mutated SEPARATELY.
selftest() {
  st=0
  make_pristine_export || { echo "selftest FAIL: could not build the pristine export tree (fail-closed)"; return 1; }

  # --- Mutant A: the marker is changed to one that COLLIDES with 'Kit-own CI|Sparkwright'. The
  #     non-collision leg MUST go RED, and so must the live re-run leg (the same claim on a real tree).
  _t=$(_mut_tree "s|^PIPELINE_ORIGIN_MARKER=.*|PIPELINE_ORIGIN_MARKER='# Sparkwright emitted'|") \
    || { echo "selftest FAIL: mutant A — no tree"; return 1; }
  _am=$(incept_marker "$_t/scripts/incept.sh")
  if [ "$_am" != '# Sparkwright emitted' ]; then
    echo "selftest FAIL: mutant A setup — the marker was not mutated in the copy (got '$_am')"; st=1
  elif out=$(assert_non_colliding "$_am" "$(kit_own_ere "$_t/scripts/incept.sh" github)" github 2>&1); then
    echo "selftest FAIL: mutant A (colliding marker) — the non-collision leg still PASSED (VACUOUS): $out"; st=1
  elif printf '%s\n' "$out" | grep -qF "MATCHES the github kit-own ERE"; then
    echo "selftest PASS: mutant A (colliding marker) caught by the non-collision leg -> $out"
  else
    echo "selftest FAIL: mutant A went RED but WITHOUT the 'MATCHES the ... kit-own ERE' message: $out"; st=1
  fi
  # Same mutation, live tree: a marker-bearing pipeline must now be CLOBBERED (that is the regression).
  plant_adopter_pipeline "$_t" "$GH_WF" "$_am"
  if out=$(assert_marked_preserved "$_t" github "$GH_WF" "$_am" 2>&1); then
    echo "selftest FAIL: mutant A (colliding marker) — the live re-run leg still PASSED (VACUOUS): $out"; st=1
  elif printf '%s\n' "$out" | grep -qF "was CLOBBERED"; then
    echo "selftest PASS: mutant A (colliding marker) caught on a LIVE tree -> $out"
  else
    echo "selftest FAIL: mutant A live leg went RED but WITHOUT the 'was CLOBBERED' message: $out"; st=1
  fi

  # --- Mutant B: the GITHUB install site is reverted to the unstamped copy. The github stamp leg MUST
  #     go RED. (Mutated ALONE — removing both stamps would not prove this one is load-bearing.)
  _t=$(_mut_tree "s|install_pipeline \(.*\.github/workflows/ci\.yml\)|cp_kit_replace \1|") \
    || { echo "selftest FAIL: mutant B — no tree"; return 1; }
  if grep -q "install_pipeline .*\.github/workflows/ci\.yml" "$_t/scripts/incept.sh"; then
    echo "selftest FAIL: mutant B setup — the github stamp site was not reverted in the copy"; st=1
  elif ! grep -q "install_pipeline .* \.gitlab-ci\.yml " "$_t/scripts/incept.sh"; then
    echo "selftest FAIL: mutant B setup — it removed the GITLAB site too (that is the 'I proved the pair' trap)"; st=1
  elif out=$(assert_stamped "$_t" github "$GH_WF" 2>&1); then
    echo "selftest FAIL: mutant B (github stamp removed) — the github leg still PASSED (VACUOUS): $out"; st=1
  elif printf '%s\n' "$out" | grep -qF "lacks the origin marker"; then
    echo "selftest PASS: mutant B (github stamp removed alone) caught -> $out"
  else
    echo "selftest FAIL: mutant B went RED but WITHOUT the 'lacks the origin marker' message: $out"; st=1
  fi

  # --- Mutant C: the GITLAB install site is reverted, ALONE. The gitlab stamp leg MUST go RED.
  _t=$(_mut_tree "s|install_pipeline \(.*\) \.gitlab-ci\.yml |cp_kit_replace \1 .gitlab-ci.yml |") \
    || { echo "selftest FAIL: mutant C — no tree"; return 1; }
  if grep -q "install_pipeline .* \.gitlab-ci\.yml " "$_t/scripts/incept.sh"; then
    echo "selftest FAIL: mutant C setup — the gitlab stamp site was not reverted in the copy"; st=1
  elif ! grep -q "install_pipeline .*\.github/workflows/ci\.yml" "$_t/scripts/incept.sh"; then
    echo "selftest FAIL: mutant C setup — it removed the GITHUB site too (that is the 'I proved the pair' trap)"; st=1
  elif out=$(assert_stamped "$_t" gitlab "$GL_WF" 2>&1); then
    echo "selftest FAIL: mutant C (gitlab stamp removed) — the gitlab leg still PASSED (VACUOUS): $out"; st=1
  elif printf '%s\n' "$out" | grep -qF "lacks the origin marker"; then
    echo "selftest PASS: mutant C (gitlab stamp removed alone) caught -> $out"
  else
    echo "selftest FAIL: mutant C went RED but WITHOUT the 'lacks the origin marker' message: $out"; st=1
  fi

  # --- Mutant D: the mirrored write condition is deleted, so the stamp becomes UNCONDITIONAL. The
  #     BROWNFIELD leg MUST go RED — this is the exact false-FAIL class the whole design removes.
  _t=$(_mut_drop '[ "$_ip_write" -eq 1 ] || return 0') \
    || { echo "selftest FAIL: mutant D — no tree"; return 1; }
  if grep -qF '[ "$_ip_write" -eq 1 ] || return 0' "$_t/scripts/incept.sh"; then
    echo "selftest FAIL: mutant D setup — the write-condition mirror was not removed from the copy"; st=1
  else
    plant_adopter_pipeline "$_t" "$GH_WF"
    if out=$(assert_preserved_unstamped "$_t" github "$GH_WF" 2>&1); then
      echo "selftest FAIL: mutant D (unconditional stamp) — the brownfield leg still PASSED (VACUOUS): $out"; st=1
    elif printf '%s\n' "$out" | grep -qF "was stamped kit-emitted"; then
      echo "selftest PASS: mutant D (unconditional stamp) caught -> $out"
    else
      echo "selftest FAIL: mutant D went RED but WITHOUT the 'was stamped kit-emitted' message: $out"; st=1
    fi
  fi

  # --- Mutant E (D-2): the DISPOSITION CHECKER's marker is diverged from incept's. The agreement leg
  #     MUST go RED — a divergence is fail-OPEN (the checker would classify every emitted pipeline
  #     adopter-owned and silently downgrade the whole gate to N/A).
  _t=$(_mut_checker) || { echo "selftest FAIL: mutant E — no tree"; return 1; }
  _em_i=$(incept_marker "$_t/scripts/incept.sh")
  _em_c=$(checker_marker "$_t/conformance/verify-enforced-wired.sh")
  if [ "$_em_c" = "$_em_i" ]; then
    echo "selftest FAIL: mutant E setup — the checker marker was not diverged (got '$_em_c')"; st=1
  elif out=$(assert_markers_agree "$_em_i" "$_em_c" 2>&1); then
    echo "selftest FAIL: mutant E (diverged checker marker) — the agreement leg still PASSED (VACUOUS): $out"; st=1
  elif printf '%s\n' "$out" | grep -qF "downgrades every kit-emitted pipeline"; then
    echo "selftest PASS: mutant E (diverged checker marker) caught -> $out"
  else
    echo "selftest FAIL: mutant E went RED but WITHOUT the divergence message: $out"; st=1
  fi

  # --- Mutant F (F3): incept is made to APPEND the marker at EOF instead of prepending it at line 1.
  #     The LINE-1 leg MUST go RED. Line 1 is the property that survives strip_db_region on a --no-db
  #     incept (a marker inside the kit:db-backed region would be deleted), so the leg runs --no-db.
  _t=$(_mut_eof) || { echo "selftest FAIL: mutant F — no tree"; return 1; }
  if ! grep -qF 'cat "$2"; printf' "$_t/scripts/incept.sh"; then
    echo "selftest FAIL: mutant F setup — the stamp was not moved to EOF in the copy"; st=1
  elif out=$(assert_stamped "$_t" github "$GH_WF" --no-db 2>&1); then
    echo "selftest FAIL: mutant F (EOF stamp under --no-db) — the line-1 leg still PASSED (VACUOUS): $out"; st=1
  elif printf '%s\n' "$out" | grep -qF "is not line 1"; then
    echo "selftest PASS: mutant F (EOF stamp under --no-db) caught -> $out"
  else
    echo "selftest FAIL: mutant F went RED but WITHOUT the 'is not line 1' message: $out"; st=1
  fi

  if [ "$st" = 0 ]; then
    echo "OK: pipeline-origin selftest — all SIX mutants (colliding marker · github stamp alone · gitlab stamp alone · unconditional stamp · diverged checker marker · EOF stamp) caught, each applied on its own."
    echo "    CEILING: the selftest proves these legs have teeth. It does NOT prove an adopter cannot remove the marker — §4 accepts that as a disclosed self-assertion of ownership."
  else
    echo "FAIL: pipeline-origin selftest"
  fi
  return "$st"
}

# --- selftest-only helpers, defined BELOW selftest() on purpose ---------------------------------
# The CI meta non-vacuity sweep (conformance/non-vacuity.sh) neuters FAIL-path idioms on the lines
# strictly BEFORE the selftest() marker and emits everything at/after it verbatim. A kill-assertion
# helper defined ABOVE the marker gets its own `return 1` flipped, so it can no longer register a
# survivor and the selftest goes vacuous. POSIX resolves calls at dispatch time, so defining these
# after selftest() is fine.

_mut_tree() {  # <sed-program> — a fresh tree whose scripts/incept.sh has ONE mutation applied
  _mt=$(fresh_tree) || return 1
  sed "$1" "$_mt/scripts/incept.sh" > "$_mt/scripts/incept.mut" \
    && mv "$_mt/scripts/incept.mut" "$_mt/scripts/incept.sh" || return 1
  printf '%s\n' "$_mt"
}

_mut_drop() {  # <fixed-string> — a fresh tree with the ONE line containing <fixed-string> deleted
  _md=$(fresh_tree) || return 1
  grep -vF "$1" "$_md/scripts/incept.sh" > "$_md/scripts/incept.mut" \
    && mv "$_md/scripts/incept.mut" "$_md/scripts/incept.sh" || return 1
  printf '%s\n' "$_md"
}

_mut_checker() {  # a fresh tree where verify-enforced-wired.sh's marker is DIVERGED from incept's
  _mc=$(fresh_tree) || return 1
  sed "s|^PIPELINE_ORIGIN_MARKER=.*|PIPELINE_ORIGIN_MARKER='# kit-pipeline-origin: DIVERGED'|" \
    "$_mc/conformance/verify-enforced-wired.sh" > "$_mc/conformance/vew.mut" \
    && mv "$_mc/conformance/vew.mut" "$_mc/conformance/verify-enforced-wired.sh" || return 1
  printf '%s\n' "$_mc"
}

_mut_eof() {  # a fresh tree where incept APPENDS the marker (EOF) instead of prepending it (line 1)
  _me=$(fresh_tree) || return 1
  awk '
    /_ip_tmp.*&&.*mv.*_ip_tmp/ && /PIPELINE_ORIGIN_MARKER/ {
      print "    { cat \"$2\"; printf '\''%s\\n'\'' \"$PIPELINE_ORIGIN_MARKER\"; } > \"$_ip_tmp\" && mv \"$_ip_tmp\" \"$2\""
      next
    }
    { print }
  ' "$_me/scripts/incept.sh" > "$_me/scripts/incept.mut" \
    && mv "$_me/scripts/incept.mut" "$_me/scripts/incept.sh" || return 1
  printf '%s\n' "$_me"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "")         run ;;
  *)          echo "usage: pipeline-origin.sh [--selftest]" >&2; exit 2 ;;
esac
