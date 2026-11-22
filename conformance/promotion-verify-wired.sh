#!/bin/sh
# promotion-verify-wired.sh — regression-lock for the approve->execute->log integrity check
# (scripts/promotion-verify.sh). Proves the `check` mode is WIRED and NON-VACUOUS: a shipped ref /
# tag whose content does NOT carry the approved-sha MUST fail (exit 1); a bound record must never
# perturb the approved tree (tree-invariant); and the derived assurance label can never overclaim.
# Part of the Proportional Promotion Contract (docs/governance/promotion-contract.md), KW1 . D2.
#   sh conformance/promotion-verify-wired.sh [--selftest]
# Exit: 0 = ok . 1 = drift/vacuity . 2 = usage. POSIX sh; dash-clean.
#
# HONEST CEILING: this lock proves the INTEGRITY check works (shipped==approved is gateable), that
# the record BINDS tree-invariantly (git notes, not an in-tree file), and that the assurance label
# is HONEST (an unsigned commit can never be [signed: gpg]). It does NOT prove the agent actually
# ran it, nor that it waited for an explicit GO (`never-infer` is FLOOR discipline, un-gateable),
# nor that the note is tamper-evident (notes BIND, they do not AUTHENTICATE). It proves the
# gateable half only.
set -eu

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
VERIFY="$SCRIPT_DIR/promotion-verify.sh"                 # co-located (scratchpad authoring)
[ -f "$VERIFY" ] || VERIFY="$SCRIPT_DIR/../scripts/promotion-verify.sh"   # installed layout

# Build a throwaway git fixture exercising TREE-EQUALITY (shipped==approved = exact content match),
# the guarantee that neither false-FAILS a squash merge nor false-PASSES a revert / extra content.
#   BASE     — trunk root (VERSION 1.0.0, f.txt="a")
#   APPROVED — the reviewed feature tip (BASE + "b"); its tree is the approval fingerprint
#   SQUASH   — trunk after `git merge --squash` of the feature (NEW sha, NO ancestry link to
#              APPROVED) whose tree EQUALS APPROVED's tree  ← the squash-and-merge shape
#   v1.0.0   — correct tag ON the squash tip (tree==APPROVED, VERSION matches)
#   EXTRA    — SQUASH + one unapproved commit on top (tree now DIFFERS ← equality, not containment)
#   RC       — SQUASH + VERSION bump to 2.0.0, tagged v2.0.0 (tree/VERSION differ from APPROVED)
#   REVERT   — a lineage where APPROVED IS an ancestor (ancestry would FALSE-PASS) then reverted,
#              restoring BASE's tree ← tree equality correctly FAILS it
#   SIDE     — a divergent branch never merged to trunk (missing content)
# The GO record is bound as a git NOTE (refs/notes/promotions) on the approved-sha — NOT written into
# the tree — so recording it can never change what `check` compares (the tree-invariance property).
# The repo lives at $D/repo; sentinels ($D/.*) live OUTSIDE the work-tree so `git add`/checkout
# can never sweep them into a commit or delete them on branch switch.
build_fixture() {
  D="$1"; R="$D/repo"
  (
    set -e
    mkdir -p "$R"; cd "$R"
    git init -q
    git config user.email tester@example.com
    git config user.name  tester
    git config commit.gpgsign false
    printf '1.0.0\n' > VERSION
    printf 'a\n' > f.txt
    git add VERSION f.txt; git commit -qm base           # BASE (VERSION 1.0.0)
    git rev-parse --abbrev-ref HEAD > "$D/.TRUNK"         # the trunk branch name
    git rev-parse HEAD > "$D/.BASE"

    git checkout -q -b feat                               # the reviewed feature branch, off BASE
    printf 'b\n' >> f.txt
    git add f.txt; git commit -qm approved               # APPROVED = the reviewed tip (tree TA)
    git rev-parse HEAD > "$D/.APPROVED"

    git checkout -q "$(cat "$D/.TRUNK")"                  # back on trunk (still at BASE)
    git merge --squash feat >/dev/null 2>&1              # squash: stages the change, no commit yet
    git commit -qm 'squash-merge feat'                   # SQUASH: NEW sha, tree == TA, NOT desc. of APPROVED
    git rev-parse HEAD > "$D/.SQUASH"
    git tag v1.0.0                                       # correct tag on the squash tip

    git checkout -q -b extra "$(cat "$D/.SQUASH")"        # extra unapproved content rides on top
    printf 'c\n' >> f.txt
    git add f.txt; git commit -qm 'extra unapproved'     # EXTRA: tree DIFFERS from APPROVED
    git rev-parse HEAD > "$D/.EXTRA"

    git checkout -q -b rc "$(cat "$D/.SQUASH")"           # RC lane: bump VERSION, tag v2.0.0
    printf '2.0.0\n' > VERSION
    git add VERSION; git commit -qm 'rc bump'            # RC: VERSION 2.0.0 (tree differs)
    git rev-parse HEAD > "$D/.RC"
    git tag v2.0.0

    git checkout -q -b merged "$(cat "$D/.APPROVED")"     # APPROVED is the tip -> genuinely an ancestor
    git revert --no-edit HEAD >/dev/null 2>&1            # revert restores BASE's tree
    git rev-parse HEAD > "$D/.REVERT"

    git checkout -q -b side "$(cat "$D/.BASE")"           # divergent, never merged to trunk
    printf 'x\n' >> f.txt
    git add f.txt; git commit -qm side                  # SIDE = missing content
    git rev-parse HEAD > "$D/.SIDE"

    # DSG: a design commit on its own branch off BASE (SWAS-944). `record --gate design` refuses a basis the approved
    # commit does not track and touch, so the design-GO cells record here; APP's tree is unchanged by it.
    git checkout -q -b dsg "$(cat "$D/.BASE")"
    mkdir -p docs/architecture
    {
      printf '# Fixture design\n\n'
      printf 'This design describes the fixture change in several real lines so it is more than a stub.\n'
      printf 'It states the problem: the record step must bind a design GO to a design file that exists.\n'
      printf 'It states the approach: the approved commit adds this file, so the GO names a tracked artifact.\n'
      printf 'It states the trade-off: one extra branch in the fixture, no change to any other commit.\n'
      printf 'It states the test: record on this commit succeeds, record on a commit without it is refused.\n'
    } > docs/architecture/x-design.md
    git add docs/architecture/x-design.md; git commit -qm 'design'
    git rev-parse HEAD > "$D/.DSG"

    git checkout -q "$(cat "$D/.TRUNK")"                  # leave the work-tree on the clean squash tip
  )
}

# ⚠️ EVERY `record` BELOW THAT IS NOT A LEDGER-SYNC LEG PASSES `--no-push`, and that is not
# decoration. Since RECORD-FETCHES-AND-PUSHES-LEDGER, `record` is a transaction that fetches the
# ledger from `origin` first and REFUSES when it cannot read it — and this $R fixture is a bare
# `git init` with no remote at all, which is precisely the unreachable case. `--no-push` is the
# labelled offline escape those legs are entitled to: they are testing the note's CONTENT (shape,
# sanitising, projections), not its publication, which the ledger-sync legs at the end own.
selftest() {
  st=0
  # The shell the producer runs under: default `sh` (bash on macOS, dash on Debian CI). PROMOTION_VERIFY_SHELL=dash
  # runs every leg of the producer under dash on any host (dash's `echo` expands \0NNN — the A5 class).
  VSH="${PROMOTION_VERIFY_SHELL:-sh}"
  case "$VSH" in sh|dash|bash) ;; *) echo "FAIL: PROMOTION_VERIFY_SHELL must be sh|dash|bash (got '$VSH')"; return 1 ;; esac
  # SWAS-537 fix round 2: the evidence leg reads its layout at TWO locations (the gate's own checkout AND the repository it runs in), so a
  # fixture repository that a gate in a kit layout runs in must carry the same two facts (conformance/ci-gate-state.sh, and a `gate:` job in
  # .github/workflows/ci.yml); an adopter-looking one carries neither. Written untracked and listed in info/exclude: no cell sees a dirty tree.
  fx_layout() {  # <repo dir> <decider 0|1> <gate-job 0|1> [<marker 0|1> = the decider's: conformance/adopter-census.sh, the kit-only third fact (SWAS-641)]
    mkdir -p "$1/conformance" "$1/.github/workflows"
    rm -f "$1/conformance/ci-gate-state.sh" "$1/conformance/adopter-census.sh"
    if [ "$2" = 1 ]; then : > "$1/conformance/ci-gate-state.sh"; fi
    if [ "${4:-$2}" = 1 ]; then : > "$1/conformance/adopter-census.sh"; fi
    if [ "$3" = 1 ]; then printf 'jobs:\n  gate:\n    runs-on: x\n  changes:\n    needs: gate\n' > "$1/.github/workflows/ci.yml"
    else printf 'jobs:\n  changes:\n    runs-on: x\n' > "$1/.github/workflows/ci.yml"; fi
    _fx_ex="$(git -C "$1" rev-parse --git-path info/exclude)"
    case "$_fx_ex" in /*) ;; *) _fx_ex="$1/$_fx_ex" ;; esac
    mkdir -p "$(dirname "$_fx_ex")"
    printf '/conformance/ci-gate-state.sh\n/conformance/adopter-census.sh\n/.github/workflows/ci.yml\n' >> "$_fx_ex"
  }
  # SWAS-537 fix round 3: the general land/trace fixtures plant the layout of the gate copy UNDER TEST, never a fixed kit one. In the
  # exported, adopter-shaped tree conformance/ci-gate-state.sh and the workflow are export-ignored, so the gate reads adopter at its own
  # checkout; a repository planted kit would be a layout-mismatch and every land would refuse. Read the two facts the way the gate does
  # (pv_ev_lay_of): <root> -> "<decider 0|1> <marker 0|1> <gate-job 0|1>". The cells that assert an evidence refusal or a FLAG only exist on a kit tree.
  fx_facts() {
    _ffd=0; _ffm=0; _ffg=0
    if [ -f "$1/conformance/ci-gate-state.sh" ]; then _ffd=1; fi
    if [ -f "$1/conformance/adopter-census.sh" ]; then _ffm=1; fi
    if grep -q '^  gate:[[:space:]]*$' "$1/.github/workflows/ci.yml" 2>/dev/null; then _ffg=1; fi
    echo "$_ffd $_ffm $_ffg"
  }
  FX_OWN="$(dirname "$VERIFY")/.."
  fx_like_own() {  # <repo dir> [<gate checkout root> = the gate under test's own]
    _fff="$(fx_facts "${2:-$FX_OWN}")"
    fx_layout "$1" "${_fff%% *}" "${_fff##* }" "$(printf '%s' "$_fff" | cut -d' ' -f2)"
  }
  case "$(fx_facts "$FX_OWN")" in
    "1 1 1") FX_KIND=kit ;;
    "0 0 0"|"0 0 1") FX_KIND=adopter ;;
    *) FX_KIND=half ;;
  esac
  # Every skip is COUNTED and the count is printed on the final line, so a silent narrowing shows on the export lane (a kit tree says 0).
  FX_SKIPS=0
  fx_skip() { FX_SKIPS=$((FX_SKIPS + 1)); echo "selftest SKIP: $1 — not a kit tree (the evidence leg is N/A here)"; }
  fx_skip_note() { echo "($1 SKIPPED: not a kit tree, counted per skip line above)"; }
  D="$(mktemp -d)"; R="$D/repo"
  build_fixture "$D" || true
  for _s in .BASE .APPROVED .SQUASH .EXTRA .RC .REVERT .SIDE .TRUNK .DSG; do
    [ -f "$D/$_s" ] || { echo "FAIL: could not build git fixture (missing $_s)"; return 1; }
  done
  # .BASE and .RC are consumed inside build_fixture (BASE anchors branches; RC carries the v2.0.0
  # tag); the selftest asserts via the refs below. Only bind what the assertions reference.
  APP="$(cat "$D/.APPROVED")"; SQ="$(cat "$D/.SQUASH")"
  EXTRA="$(cat "$D/.EXTRA")"; REV="$(cat "$D/.REVERT")"
  SIDE="$(cat "$D/.SIDE")"; TRUNK="$(cat "$D/.TRUNK")"; DSG="$(cat "$D/.DSG")"

  # assert <want-rc> <label> <check-args...>
  assert() {
    _want="$1"; _lab="$2"; shift 2
    if ( cd "$R" && $VSH "$VERIFY" check "$@" >/dev/null 2>&1 ); then _got=0; else _got=$?; fi
    if [ "$_got" = "$_want" ]; then
      echo "PASS: $_lab (rc=$_got)"
    else
      echo "FAIL: $_lab want rc=$_want got rc=$_got"; st=1
    fi
  }

  # --- SQUASH positives: tree equality holds though the squash tip has NO ancestry link to
  #     APPROVED (the ancestry check false-FAILED these — the bug this fix closes) ---
  assert 0 "squash positive: squash tip tree == approved (no ancestry link)"  --ref "$SQ"    --approved-sha "$APP"
  assert 0 "squash positive via trunk branch ref"                             --ref "$TRUNK" --approved-sha "$APP"
  assert 0 "tag-on-squash positive: v1.0.0 tree == approved + VERSION match"  --ref v1.0.0   --approved-sha "$APP"

  # --- equality-not-containment NEGATIVE: the approved change IS present but extra unapproved
  #     content rides on top -> tree differs -> MUST FAIL (proves equality, not mere containment) ---
  assert 1 "extra-content NEGATIVE: approved+extra tree != approved"          --ref "$EXTRA" --approved-sha "$APP"

  # --- revert-after-merge NEGATIVE: APPROVED is genuinely an ancestor (ancestry FALSE-PASSED
  #     this) but the content was reverted -> tree differs -> MUST FAIL ---
  assert 1 "revert NEGATIVE: reverted tip tree != approved (ancestry would false-pass)" --ref "$REV" --approved-sha "$APP"

  # --- missing-content NEGATIVES (existing intent, still load-bearing) ---
  assert 1 "merge NEGATIVE: squash tip does NOT carry divergent side"         --ref "$SQ"    --approved-sha "$SIDE"
  # tag-on-wrong-commit / wrong-VERSION: v2.0.0 (VERSION 2.0.0) vs approved (VERSION 1.0.0)
  assert 1 "tag NEGATIVE: v2.0.0 tree/VERSION != approved's"                  --ref v2.0.0   --approved-sha "$APP"

  # =====================================================================================
  # S5a teeth (LOAD-BEARING): tree-invariance + note round-trip + label-can't-lie
  # =====================================================================================

  # --- TREE-INVARIANCE regression (directly regresses S4-finding #1): binding a GO record must
  #     NOT change the approved tree NOR dirty the work-tree. Old model appended to an in-tree
  #     promotion-log.md and merged -> the tree changed -> `check` false-failed. A git note binds
  #     OUTSIDE the tree. Load-bearing: a record that writes into the tree dirties the work-tree
  #     and/or changes the approved tree, and this block FAILs. ---
  APP_TREE_BEFORE="$( ( cd "$R" && git rev-parse "$APP^{tree}" ) )"
  if ( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$APP" --approved-by "solo maintainer" \
        --gate release-candidate --rung rc --class Ordinary \
        --scope "PR #999" --token "GO: merge #999 at $APP" --basis "reviewer APPROVE" >/dev/null 2>&1 ); then
    _rec=0; else _rec=$?; fi
  APP_TREE_AFTER="$( ( cd "$R" && git rev-parse "$APP^{tree}" ) )"
  DIRTY="$( ( cd "$R" && git status --porcelain ) )"
  if [ "$_rec" = 0 ] && [ "$APP_TREE_BEFORE" = "$APP_TREE_AFTER" ] && [ -z "$DIRTY" ]; then
    echo "PASS: tree-invariance: record bound a note WITHOUT changing the approved tree or dirtying the work-tree"
  else
    echo "FAIL: tree-invariance: record rc=$_rec, tree $APP_TREE_BEFORE->$APP_TREE_AFTER, dirty='$DIRTY'"; st=1
  fi
  # and `check` still holds after the record — the whole point: it can't false-fail on the record.
  assert 0 "tree-invariance: check still OK after record (note didn't perturb the tree)" --ref "$SQ" --approved-sha "$APP"

  # --- NOTE round-trip: record -> `log` lists it -> check resolves approved-sha from the note ---
  if ( cd "$R" && $VSH "$VERIFY" log 2>/dev/null | grep -q "$APP" ); then
    echo "PASS: note round-trip: log projects the recorded approved-sha"
  else
    echo "FAIL: note round-trip: log did not list $APP"; st=1
  fi
  assert 0 "note round-trip: check resolves latest approved-sha (APP) from the note" --ref "$SQ"
  # a LATER record binding the divergent SIDE -> resolve must now pick SIDE and FAIL.
  ( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$SIDE" --approved-by "solo maintainer" \
      --gate release-candidate --rung rc --class Ordinary \
      --scope "PR #1000" --token "GO: merge #1000 at $SIDE" >/dev/null 2>&1 ) \
    || { echo "FAIL: second record (SIDE) failed"; st=1; }
  assert 1 "note round-trip NEGATIVE: latest note (SIDE) tree != squash tip -> FAIL" --ref "$SQ"

  # --- LABEL-CAN'T-LIE (the non-vacuity anchor): the emitted label is DERIVED from the commit's
  #     evidence, never from input. On an UNSIGNED commit with a free-typed approver that is NOT the
  #     committer, the label MUST be [self-asserted] — never [signed: gpg]. (A smuggled bracket claim
  #     is now rejected outright at input — see the injection negatives below — so here we feed a
  #     CLEAN id and assert the derivation itself cannot overclaim.) ---
  ( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$APP" --approved-by "attacker" \
      --gate release-candidate --rung rc --class Ordinary \
      --scope "PR #1001" --token "GO clean" >/dev/null 2>&1 ) \
    || { echo "FAIL: label-can't-lie record failed"; st=1; }
  LABEL_LINE="$( ( cd "$R" && git notes --ref=promotions show "$APP" 2>/dev/null | grep '^approved-by:' ) || true )"
  if [ -z "$LABEL_LINE" ]; then
    # non-vacuity: the record MUST have been bound (an empty note = no evidence to judge -> FAIL,
    # never a spurious pass).
    echo "FAIL: label-can't-lie: no approved-by note bound on $APP (record did not write a note)"; st=1
  elif printf '%s' "$LABEL_LINE" | grep -q '\[signed: gpg\]'; then
    echo "FAIL: label-can't-lie: unsigned commit emitted [signed: gpg] (OVERCLAIM) -> $LABEL_LINE"; st=1
  else
    echo "PASS: label-can't-lie: unsigned commit did NOT get [signed: gpg] -> $LABEL_LINE"
  fi

  # =====================================================================================
  # BRANCH SCOPING (owner ruling D11, 2026-07-28; B2 Δ1′) — `--scope branch/<name>` is the key
  # conformance/ceremony-binding.sh --pre-push DERIVES, so a design GO can bind BEFORE a PR exists.
  # Three legs: the shape is ACCEPTED and round-trips into the note VERBATIM (the gate matches it
  # with `grep -F -x`, so a mangled or normalised value would silently satisfy nothing), and the two
  # shapes the gate could never match are refused AT THE FRONT DOOR rather than recorded dead.
  # =====================================================================================
  if ( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$DSG" --approved-by "solo maintainer" \
        --gate design --rung integration --class control-plane \
        --scope "branch/feat-b2-go" --token "GO: design at $DSG" \
        --basis "docs/architecture/x-design.md" >/dev/null 2>&1 ); then _brc=0; else _brc=$?; fi
  _bscope="$( ( cd "$R" && git notes --ref=promotions show "$DSG" 2>/dev/null \
                 | grep -c '^scope: branch/feat-b2-go$' ) || true )"
  if [ "$_brc" = 0 ] && [ "$_bscope" = 1 ]; then
    echo "PASS: branch scoping: --scope branch/<name> accepted and round-trips verbatim into the note"
  else
    echo "FAIL: branch scoping: record rc=$_brc, exact 'scope: branch/feat-b2-go' lines in note=$_bscope"; st=1
  fi
  # PV3 (SWAS-392, G1b): these two negatives pass --basis, so the design-GO-needs-a-basis refusal
  # (below) cannot be the reason they are refused, and they assert the SCOPE-SPECIFIC message as well
  # as rc 2. Without --basis, and asserting rc alone, they would stay green for the wrong refusal.
  _b2out="$( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$APP" --approved-by "solo maintainer" \
        --gate design --rung integration --class control-plane --scope "branch/" \
        --token "GO" --basis "docs/architecture/x-design.md" 2>&1 )" && _b2rc=0 || _b2rc=$?
  if [ "$_b2rc" = 2 ] && printf '%s' "$_b2out" | grep -qF "names no branch"; then
    echo "PASS: branch scoping NEGATIVE (PV3): a bare 'branch/' names no branch -> rc 2 with the scope message"
  else
    echo "FAIL: branch scoping NEGATIVE (PV3): 'branch/' should be rc 2 'names no branch', got rc=$_b2rc: $_b2out"; st=1
  fi
  _b3out="$( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$APP" --approved-by "solo maintainer" \
        --gate design --rung integration --class control-plane --scope "branch/feat+plus" \
        --token "GO" --basis "docs/architecture/x-design.md" 2>&1 )" && _b3rc=0 || _b3rc=$?
  if [ "$_b3rc" = 2 ] && printf '%s' "$_b3out" | grep -qF "may contain only"; then
    echo "PASS: branch scoping NEGATIVE (PV3): a name outside the gate's scope charset -> rc 2 with the scope message (not recorded dead)"
  else
    echo "FAIL: branch scoping NEGATIVE (PV3): 'branch/feat+plus' should be rc 2 'may contain only', got rc=$_b3rc: $_b3out"; st=1
  fi
  # REGRESSION: the NEW rule applies to the `branch/` shape ONLY. Existing scopes keep their existing
  # hygiene — this repo's own ledger holds scopes with a space ("PR #999"), and retrofitting the
  # charset onto every scope would refuse records the gates already accept.
  if ( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$DSG" --approved-by "solo maintainer" \
        --gate design --rung integration --class Ordinary --scope "PR #1005" \
        --token "GO" --basis "docs/architecture/x-design.md" >/dev/null 2>&1 ); then _b4rc=0; else _b4rc=$?; fi
  if [ "$_b4rc" = 0 ]; then
    echo "PASS: branch scoping: a non-branch scope with a space is still accepted (no retrofit)"
  else
    echo "FAIL: branch scoping: 'PR #1005' must still record, got rc=$_b4rc"; st=1
  fi

  # PV1 (SWAS-392, design 2.3a): `record --gate design` WITHOUT --basis is refused, rc 2, on every class,
  # and writes NO note (the ledger ref is byte-identical afterwards). The gate that reads a design GO
  # (ceremony-binding.sh) refuses a basis-less one as "names no artifact", so the front door refuses to
  # mint a design GO that can never bind. ONLY the exact gate value `design` is affected (PV2).
  for _pv1c in "Ordinary:PR #1013" "control-plane:branch/pv1-cp"; do
    _pv1cls="${_pv1c%%:*}"; _pv1sc="${_pv1c#*:}"
    _pv1pre="$( cd "$R" && git rev-parse -q --verify refs/notes/promotions 2>/dev/null || echo none )"
    _pv1out="$( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$APP" --approved-by "solo maintainer" \
          --gate design --rung integration --class "$_pv1cls" --scope "$_pv1sc" \
          --token "GO" 2>&1 )" && _pv1rc=0 || _pv1rc=$?
    _pv1post="$( cd "$R" && git rev-parse -q --verify refs/notes/promotions 2>/dev/null || echo none )"
    if [ "$_pv1rc" = 2 ] && [ "$_pv1pre" = "$_pv1post" ] && printf '%s' "$_pv1out" | grep -qF -e "--basis"; then
      echo "PASS: PV1 ($_pv1cls): record --gate design without --basis -> rc 2 naming --basis, ledger untouched"
    else
      echo "FAIL: PV1 ($_pv1cls): expected rc 2 naming --basis and an untouched ledger, got rc=$_pv1rc pre=$_pv1pre post=$_pv1post: $_pv1out"; st=1
    fi
  done
  # PV4 (F-2/M3): the LITERAL `(none recorded)` is the omitted-basis default, so it is refused as a --basis
  # for a design GO too (trimmed, case-insensitive) -- else the refusal above is bypassed by typing the default.
  for _pv4b in "(none recorded)" "  (None Recorded) "; do
    _pv4pre="$( cd "$R" && git rev-parse -q --verify refs/notes/promotions 2>/dev/null || echo none )"
    _pv4out="$( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$APP" --approved-by "solo maintainer" \
          --gate design --rung integration --class Ordinary --scope "PR #1015" \
          --token "GO" --basis "$_pv4b" 2>&1 )" && _pv4rc=0 || _pv4rc=$?
    _pv4post="$( cd "$R" && git rev-parse -q --verify refs/notes/promotions 2>/dev/null || echo none )"
    if [ "$_pv4rc" = 2 ] && [ "$_pv4pre" = "$_pv4post" ] && printf '%s' "$_pv4out" | grep -qF -e "none recorded"; then
      echo "PASS: PV4: record --gate design --basis '$_pv4b' -> rc 2, ledger untouched"
    else
      echo "FAIL: PV4: --basis '$_pv4b' on a design GO must be rc 2 with an untouched ledger, got rc=$_pv4rc: $_pv4out"; st=1
    fi
  done
  # PV2: any OTHER gate keeps the optional basis -- rc 0 and the literal default, unchanged.
  if ( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$APP" --approved-by "solo maintainer" \
        --gate release-candidate --rung rc --class Ordinary --scope "PR #1014" \
        --token "GO" >/dev/null 2>&1 ) \
     && ( cd "$R" && git notes --ref=promotions show "$APP" 2>/dev/null | grep -qx 'basis: (none recorded)' ); then
    echo "PASS: PV2: record with another gate and no --basis -> rc 0, 'basis: (none recorded)' unchanged"
  else
    echo "FAIL: PV2: a non-design gate without --basis must still record with 'basis: (none recorded)'"; st=1
  fi

  # SWAS-948 (C1, C1b, C2, C3) — `record` takes --gate and --rung from LISTED values, folded to the lowercase list spelling, at the front
  # door (rc 2, no note, the list and one worked example per gate printed). g9_refused asserts rc 2, an untouched ledger ref and two needles.
  g9_ledger() { ( cd "$R" && git rev-parse -q --verify refs/notes/promotions 2>/dev/null || echo none ); }
  g9_rec() {   # <gate> <rung> -> _g9rc, _g9out (a fresh scope; no --basis)
    if _g9out="$( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$APP" --approved-by "solo maintainer" \
          --gate "$1" --rung "$2" --class Ordinary --scope "PR #948" --token "GO" 2>&1 )"; then _g9rc=0; else _g9rc=$?; fi
  }
  g9_refused() {   # <label> <needle 1> <needle 2> <gate> <rung>
    _g9l="$1"; _g9n1="$2"; _g9n2="$3"; shift 3
    _g9pre="$(g9_ledger)"; g9_rec "$@"; _g9post="$(g9_ledger)"
    if [ "$_g9rc" = 2 ] && [ "$_g9pre" = "$_g9post" ] && printf '%s' "$_g9out" | grep -qF -e "$_g9n1" && printf '%s' "$_g9out" | grep -qF -e "$_g9n2"; then
      echo "PASS: $_g9l (rc 2, ledger untouched, the message and the list printed)"
    else
      echo "FAIL: $_g9l: want rc 2 + '$_g9n1' + '$_g9n2' + an untouched ledger; got rc $_g9rc pre=$_g9pre post=$_g9post; out=$_g9out"; st=1
    fi
  }
  G9_GATES="design · plan · governance · merge · release-candidate"
  G9_RUNGS="spike · integration · rc · staging · production"
  g9_refused "948-C1a: --gate desgin is refused" "invalid --gate 'desgin'" "$G9_GATES" desgin integration
  g9_refused "948-C1a: --gate promotion is refused (it means merge; the writers moved)" "invalid --gate 'promotion'" "$G9_GATES" promotion integration
  _nl='
'
  g9_refused "948-C1c: a gate with a trailing newline is refused, never silently cleaned" "--gate" "--gate" "merge${_nl}" integration
  g9_refused "948-C1: an empty --gate keeps the existing 'missing --gate' message and the usage text carries the list" "record: missing --gate" "design | plan | governance | merge | release-candidate" "" integration
  g9_refused "948-C1b: --gate Design folds to design and so gets the design-basis check (no --basis)" "--gate design requires --basis" "--basis" Design integration
  g9_refused "948-C2: --rung 'Release candidate' is refused (the list spelling is rc)" "invalid --rung 'Release candidate'" "$G9_RUNGS" merge "Release candidate"
  # C3: the note stores the lowercase list spelling. Asserted by the ABSENCE of the typed spelling as well as the presence of the folded
  # one, because earlier cells recorded lowercase lines on the same commit and a record that skipped the fold would still match those.
  if ( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$DSG" --approved-by "solo maintainer" \
        --gate Design --rung Integration --class control-plane --scope "branch/feat-948-fold" \
        --token "GO: 948 fold at $DSG" --basis "docs/architecture/x-design.md" >/dev/null 2>&1 ); then _g9c3=0; else _g9c3=$?; fi
  _g9note="$( ( cd "$R" && git notes --ref=promotions show "$DSG" 2>/dev/null ) || true )"
  if [ "$_g9c3" = 0 ] && printf '%s\n' "$_g9note" | grep -qx 'gate: design' && printf '%s\n' "$_g9note" | grep -qx 'rung: integration' \
     && ! printf '%s\n' "$_g9note" | grep -qx 'gate: Design' && ! printf '%s\n' "$_g9note" | grep -qx 'rung: Integration'; then
    echo "PASS: 948-C3: --gate Design --rung Integration records 'gate: design' and 'rung: integration' (the typed spelling is not stored)"
  else
    echo "FAIL: 948-C3: want rc 0, 'gate: design', 'rung: integration' and no 'gate: Design' / 'rung: Integration'; got rc $_g9c3; note=$_g9note"; st=1
  fi

  # =====================================================================================
  # KIT-ROW PROJECTION + `trace` (ENTRY-DECLARATION-SEVERED-ON-MAIN, 2026-08-30).
  #
  # THE PROBLEM THIS MEASURES. A squash merge composes a NEW commit message on the forge, so the
  # head commit's Kit-Row trailer does not survive onto the trunk: MEASURED 0/60 on this repo's
  # main. The record path is where it CAN survive — `record` projects the approved commit's
  # Kit-Row into the note through git's own trailer parser, and `trace` recovers it for a trunk
  # commit by TREE equality (the same fingerprint `check` uses), never by ancestry (which a squash
  # breaks) and never by re-parsing the trunk message (which carries nothing).
  #
  # CEILING, ASSERTED HERE AND NOWHERE OVERSTATED: this proves the row is RECOVERABLE, not that it
  # was RIGHT. `trace` inherits the GO record's assurance exactly — bind-not-authenticate
  # (D-240805-3) — and a forged note is as forgeable as it ever was.
  # =====================================================================================
  # A row-bearing head off trunk, and its squash-shaped landing whose TREE equals it but whose
  # message carries nothing. This is the real-world shape, built rather than modelled.
  ( cd "$R" && git checkout -q -b rowfeat "$TRUNK" \
      && printf 'row\n' > rowfile.txt && git add rowfile.txt \
      && printf 'row-bearing head\n\nbody\n\nKit-Row: DEMO-ROW-42\nKit-Class: ordinary\n' \
         | git commit -q -F - ) || { echo "FAIL: could not build the row fixture"; st=1; }
  ROWC="$( ( cd "$R" && git rev-parse rowfeat ) )"
  ( cd "$R" && git checkout -q "$TRUNK" && git merge --squash rowfeat >/dev/null 2>&1 \
      && git commit -qm 'squash-merge rowfeat (forge-composed message, no trailers)' ) \
    || { echo "FAIL: could not build the squashed row landing"; st=1; }
  SQROW="$( ( cd "$R" && git rev-parse HEAD ) )"

  # NON-VACUITY OF THE FIXTURE ITSELF: the squashed commit must genuinely carry NO parseable
  # Kit-Row. If it did, `trace` could pass by reading the trunk message and the whole leg would be
  # measuring nothing.
  if [ -n "$( ( cd "$R" && git log -1 --format='%(trailers:key=Kit-Row,valueonly)' "$SQROW" ) )" ]; then
    echo "FAIL: fixture is vacuous — the squashed commit carries a parseable Kit-Row trailer"; st=1
  fi

  ( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$ROWC" --approved-by "solo maintainer" \
      --gate merge --rung integration --class Ordinary --scope "PR #1010" \
      --token "GO: merge #1010 at $ROWC" >/dev/null 2>&1 ) \
    || { echo "FAIL: record on the row-bearing commit failed"; st=1; }
  if ( cd "$R" && git notes --ref=promotions show "$ROWC" 2>/dev/null | grep -qxF 'kit-row: DEMO-ROW-42' ); then
    echo "PASS: kit-row projection: record wrote the approved commit's Kit-Row into the note"
  else
    echo "FAIL: kit-row projection: the note on $ROWC carries no 'kit-row: DEMO-ROW-42' line"; st=1
  fi

  # ABSENT ⇒ `(none)`, NEVER INVENTED. SIDE carries no trailers; a record on it must say so rather
  # than guess, inherit, or omit the field (an omitted field is indistinguishable from an old note).
  ( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$SIDE" --approved-by "solo maintainer" \
      --gate merge --rung integration --class Ordinary --scope "PR #1011" \
      --token "GO clean" >/dev/null 2>&1 ) || { echo "FAIL: record on the trailerless commit failed"; st=1; }
  if ( cd "$R" && git notes --ref=promotions show "$SIDE" 2>/dev/null | grep -qxF 'kit-row: (none)' ); then
    echo "PASS: kit-row projection: a commit with no Kit-Row records '(none)', never an invented row"
  else
    echo "FAIL: kit-row projection: the note on $SIDE does not carry 'kit-row: (none)'"; st=1
  fi

  # THE RECOVERY ITSELF: trace on the SQUASHED trunk commit finds the row the trunk message lost.
  if ( cd "$R" && $VSH "$VERIFY" trace --ref "$SQROW" 2>/dev/null | grep -qF 'DEMO-ROW-42' ); then
    echo "PASS: trace: the row is recoverable for a squashed trunk commit that carries no trailer"
  else
    echo "FAIL: trace --ref $SQROW did not recover kit-row DEMO-ROW-42"; st=1
  fi

  # GO-IDENTITY-AND-LAND-SOD L9: trace APPENDS both identities at the END of the per-commit line (the
  # existing prefix stays byte-stable for any reader). The note above was recorded with no --go-by, so it
  # reads `(none recorded)`; re-recorded with --go-by (record supersedes) it reads `<name> [self-asserted]`.
  _tr_l9="$( ( cd "$R" && $VSH "$VERIFY" trace --ref "$SQROW" 2>/dev/null ) || true )"
  case "$_tr_l9" in
    *"gate: merge  scope: PR #1010  approved-by: solo maintainer [self-asserted]  go-by: (none recorded)") echo "PASS: trace L9: the per-commit line ends with the approver and 'go-by: (none recorded)' (prefix unchanged)" ;;
    *) echo "FAIL: trace L9: expected the line to end '...scope: PR #1010  approved-by: solo maintainer [self-asserted]  go-by: (none recorded)'; got: $_tr_l9"; st=1 ;;
  esac
  ( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$ROWC" --approved-by "solo maintainer" --go-by "Owner Fixture" \
      --gate merge --rung integration --class Ordinary --scope "PR #1010" \
      --token "GO: merge #1010 at $ROWC" >/dev/null 2>&1 ) || true
  _tr_l9="$( ( cd "$R" && $VSH "$VERIFY" trace --ref "$SQROW" 2>/dev/null ) || true )"
  case "$_tr_l9" in
    *"approved-by: solo maintainer [self-asserted]  go-by: Owner Fixture [self-asserted]") echo "PASS: trace L9: a recorded --go-by is printed beside the approver, labelled [self-asserted]" ;;
    *) echo "FAIL: trace L9: expected 'go-by: Owner Fixture [self-asserted]' at the end of the line; got: $_tr_l9"; st=1 ;;
  esac
  # trace prints note-derived text: a control byte (an ESC in a hand-written go-by) must not reach the terminal.
  ( cd "$R" && git notes --ref=promotions show "$ROWC" | sed "s/^go-by: .*/go-by: Bad$(printf '\033')Name [self-asserted]/" \
      | git notes --ref=promotions add -f -F - "$ROWC" ) >/dev/null 2>&1
  _tr_l9="$( ( cd "$R" && $VSH "$VERIFY" trace --ref "$SQROW" 2>/dev/null ) || true )"
  case "$_tr_l9" in
    *"go-by: BadName"*) if printf '%s' "$_tr_l9" | grep -q "$(printf '\033')"; then echo "FAIL: trace: an ESC byte reached the output"; st=1; else echo "PASS: trace: control bytes in a note's go-by are stripped from the printed line"; fi ;;
    *) echo "FAIL: trace: expected 'go-by: BadName' (control byte stripped, not the line dropped); got: $_tr_l9"; st=1 ;;
  esac
  ( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$ROWC" --approved-by "solo maintainer" --go-by "Owner Fixture" \
      --gate merge --rung integration --class Ordinary --scope "PR #1010" \
      --token "GO: merge #1010 at $ROWC" >/dev/null 2>&1 ) || true
  # L9 (ceremony-binding half): the design-gate remedy names the committer, not an unspecified <human>.
  if grep -qF "<the design commit's committer name or email>" "$SCRIPT_DIR/ceremony-binding.sh" \
     && ! grep -qF -e '--approved-by <human>' "$SCRIPT_DIR/ceremony-binding.sh" \
     && grep -qF 'A design GO binds to the COMMITTER' "$SCRIPT_DIR/ceremony-binding.sh"; then
    echo "PASS: L9: ceremony-binding's remedy names the design commit's committer, and says the GO binds to it"
  else
    echo "FAIL: L9: ceremony-binding.sh still says '--approved-by <human>' or lacks the 'binds to the COMMITTER' line"; st=1
  fi

  # NEGATIVE: a trunk commit with NO matching note must exit 1 and NAME the commit. EXTRA's tree
  # equals nothing that was ever recorded. Without this leg an always-0 trace passes everything.
  if ( cd "$R" && $VSH "$VERIFY" trace --ref "$EXTRA" >/dev/null 2>&1 ); then
    echo "FAIL: trace on a commit with no matching promotion note must exit 1, but it passed"; st=1
  else
    echo "PASS: trace NEGATIVE: a commit with no matching note exits 1 (recordless merge is loud)"
  fi

  # --recent: the RECORDLESS-MERGE leg the kit's own CI runs. SWAS-943: the trunk's only root (BASE) now reads as the Inception baseline,
  # so it no longer reds the window. The window is re-anchored on one UNRECORDED PARENTED trunk commit (on a scratch branch, so the
  # later cells' trunk is untouched) on top of the two recorded ones: it must RED and be named by the 12-character sha the trace prints.
  ( cd "$R" && git checkout -q -b tbneg "$TRUNK" && printf 'recordless\n' > recordless.txt && git add recordless.txt \
      && git commit -qm 'recordless trunk commit (no GO)' ) >/dev/null 2>&1 \
    || { echo "FAIL: could not build the recordless-trunk-commit fixture"; st=1; }
  _tr_neg12="$( ( cd "$R" && git rev-parse tbneg ) | cut -c1-12 )"
  _tr_out="$( ( cd "$R" && $VSH "$VERIFY" trace --recent 3 --from tbneg 2>&1 ) || true )"
  if ( cd "$R" && $VSH "$VERIFY" trace --recent 3 --from tbneg >/dev/null 2>&1 ); then
    echo "FAIL: trace --recent over a window containing a recordless merge must RED"; st=1
  else
    echo "PASS: trace --recent NEGATIVE: a recordless trunk commit reds the window"
  fi
  case "$_tr_out" in
    *"$_tr_neg12"*"no promotion note"*) echo "PASS: trace --recent names what it could not recover" ;;
    *) echo "FAIL: trace --recent red did not name the unrecoverable commit $_tr_neg12: $_tr_out"; st=1 ;;
  esac
  ( cd "$R" && git checkout -q "$TRUNK" && git branch -D tbneg ) >/dev/null 2>&1 || true

  # POSITIVE WINDOW: a window of exactly the one recorded commit must be GREEN. Paired with the
  # negative above, this is the discriminant — an always-red trace fails here, an always-green one
  # fails there.
  if ( cd "$R" && $VSH "$VERIFY" trace --recent 1 --from "$SQROW" >/dev/null 2>&1 ); then
    echo "PASS: trace --recent POSITIVE: a fully recorded window is green"
  else
    echo "FAIL: trace --recent over the single recorded commit $SQROW must be green"; st=1
  fi

  # THE SUMMARY MUST NOT OVERSTATE. Every note on this repo's main today predates the kit-row
  # projection, so a `--recent` verdict reading "N/N carry a recoverable board row" over N
  # `(not recorded)` lines would be the exact overstatement this repo bans. A green window whose
  # single commit DOES carry a projected row must report 1 projected and 0 pre-projection; the
  # counts must be reported separately from the note-binding count.
  _tr_sum="$( ( cd "$R" && $VSH "$VERIFY" trace --recent 1 --from "$SQROW" 2>&1 ) || true )"
  case "$_tr_sum" in
    *"bound to a promotion note"*"1 carry a projected board row; 0 predate"*)
      echo "PASS: trace --recent reports note-binding and ROW projection as separate counts" ;;
    *) echo "FAIL: trace --recent summary conflates 'bound to a note' with 'carries a row': $_tr_sum"; st=1 ;;
  esac

  # …and the pre-projection case is COUNTED, not silently credited. APP's note was written before
  # kit-row existed in this fixture's first records; re-record it WITHOUT a row-bearing commit and
  # the window must say so. (SIDE recorded `(none)` above — a positive statement, distinct from a
  # note that has no kit-row line at all.)
  case "$( ( cd "$R" && $VSH "$VERIFY" trace --ref "$SIDE" 2>&1 ) || true )" in
    *'kit-row: (none)'*) echo "PASS: trace prints '(none)' for an approved commit that carried no row" ;;
    *) echo "FAIL: trace did not report '(none)' for the trailerless approved commit"; st=1 ;;
  esac

  # ── MANY-TO-ONE TREE MATCH (security H-1 / review L2) ────────────────────────────────────────
  # Trees are not unique to commits. An EMPTY commit reproduces its parent's tree exactly, so it
  # matches its parent's note and would be credited with a GO nobody gave it — a recordless merge
  # wearing the previous merge's costume. Same shape as a revert-and-reapply pair. Within a window
  # each annotated sha may be claimed once, oldest first, so the BORROWER reds and not its victim.
  ( cd "$R" && git checkout -q "$TRUNK" && git commit -q --allow-empty -m 'empty commit (no tree change, no GO)' ) \
    || { echo "FAIL: could not build the empty-commit fixture"; st=1; }
  EMPTYC="$( ( cd "$R" && git rev-parse HEAD ) )"
  # NON-VACUITY OF THE FIXTURE: the empty commit's tree must really equal the recorded one's, or the
  # leg would be measuring an ordinary recordless merge instead of the borrowing case.
  if [ "$( ( cd "$R" && git rev-parse "$EMPTYC^{tree}" ) )" != "$( ( cd "$R" && git rev-parse "$SQROW^{tree}" ) )" ]; then
    echo "FAIL: fixture is vacuous — the empty commit's tree does not equal the recorded commit's"; st=1
  fi
  _tr_dup="$( ( cd "$R" && $VSH "$VERIFY" trace --recent 2 --from "$EMPTYC" 2>&1 ) || true )"
  if ( cd "$R" && $VSH "$VERIFY" trace --recent 2 --from "$EMPTYC" >/dev/null 2>&1 ); then
    echo "FAIL: an empty commit borrowing its parent's note must RED, but --recent 2 passed"; st=1
  else
    echo "PASS: shared-tree NEGATIVE: an empty commit cannot borrow its parent's promotion note"
  fi
  # …and it must name the BORROWER, not the commit that legitimately earned the note.
  case "$_tr_dup" in
    *"$EMPTYC"*"shared-tree"*|*"shared-tree"*"$EMPTYC"*)
      echo "PASS: the shared-tree red names the borrowing commit and says why" ;;
    *) echo "FAIL: the shared-tree red did not name $EMPTYC: $_tr_dup"; st=1 ;;
  esac

  # ── THE NOTE CARRIES THE TREE (first live run of the recordless-merge leg, CI PR #601) ────────
  # `record` now writes `approved-tree:`. Before that, `trace` resolved `approved-sha^{tree}` at
  # trace time, which silently required the approved COMMIT OBJECT to be present — true in a
  # developer clone, FALSE in a CI checkout where every approved-sha is a deleted PR-branch head.
  # These three legs pin the cure, its legacy fallback, and the honest failure in between.
  if ( cd "$R" && git notes --ref=promotions show "$ROWC" 2>/dev/null | grep -qE '^approved-tree: [0-9a-f]{40}$' ); then
    echo "PASS: record writes a 40-hex approved-tree: line into the note"
  else
    echo "FAIL: the note on $ROWC carries no well-formed 'approved-tree:' line"; st=1
  fi
  # THE PROPERTY THAT MATTERS: a note carrying approved-tree matches EVEN WHEN THE APPROVED COMMIT
  # OBJECT IS GONE. Built by hand-writing a note whose approved-sha is bogus (an object that has
  # never existed) but whose approved-tree is real — which is exactly the shape a CI checkout sees,
  # without needing to gc the fixture and risk collateral pruning.
  ( cd "$R" && git checkout -q "$TRUNK" && printf 'orphan\n' > orphan.txt && git add orphan.txt \
      && git commit -qm 'commit whose approver object will be unavailable' ) \
    || { echo "FAIL: could not build the orphan-tree fixture"; st=1; }
  ORPHANC="$( ( cd "$R" && git rev-parse HEAD ) )"
  ORPHANT="$( ( cd "$R" && git rev-parse "HEAD^{tree}" ) )"
  # 0000…0001 is a syntactically valid sha that names no object in any repository.
  ( cd "$R" && printf 'record: promotion GO (approve->execute->log)\napproved-sha: 0000000000000000000000000000000000000001\napproved-tree: %s\ngate: promotion\nkit-row: ORPHAN-ROW-7\nscope: PR #1013\n' "$ORPHANT" \
      | git notes --ref=promotions add -f -F - "$ORPHANC" ) >/dev/null 2>&1 \
    || { echo "FAIL: could not hand-write the tree-carrying note"; st=1; }
  _tr_orph="$( ( cd "$R" && $VSH "$VERIFY" trace --ref "$ORPHANC" 2>&1 ) || true )"
  case "$_tr_orph" in
    *ORPHAN-ROW-7*) echo "PASS: a note carrying approved-tree matches even though its approved-sha names no object" ;;
    *) echo "FAIL: a tree-carrying note did not match with an unresolvable approved-sha: $_tr_orph"; st=1 ;;
  esac

  # LEGACY NOTE + UNREACHABLE APPROVED-SHA → `unresolvable`, and it must RED. Distinct from
  # "recordless merge": a GO exists, the object to compute its tree does not, and the remedy is a
  # fetch rather than a governance repair. Same hand-written shape, minus the approved-tree line.
  ( cd "$R" && git checkout -q "$TRUNK" && printf 'legacy\n' > legacy.txt && git add legacy.txt \
      && git commit -qm 'commit whose note predates approved-tree' ) \
    || { echo "FAIL: could not build the legacy-note fixture"; st=1; }
  LEGACYC="$( ( cd "$R" && git rev-parse HEAD ) )"
  ( cd "$R" && printf 'record: promotion GO (approve->execute->log)\napproved-sha: 0000000000000000000000000000000000000002\ngate: promotion\nkit-row: LEGACY-ROW-8\nscope: PR #1014\n' \
      | git notes --ref=promotions add -f -F - "$LEGACYC" ) >/dev/null 2>&1 \
    || { echo "FAIL: could not hand-write the legacy note"; st=1; }
  _tr_leg="$( ( cd "$R" && $VSH "$VERIFY" trace --ref "$LEGACYC" 2>&1 ) || true )"
  if ( cd "$R" && $VSH "$VERIFY" trace --ref "$LEGACYC" >/dev/null 2>&1 ); then
    echo "FAIL: a legacy note whose approved-sha is unreachable must RED, but trace passed"; st=1
  else
    case "$_tr_leg" in
      *unresolvable*"not reachable from this checkout"*)
        echo "PASS: a legacy note with an unreachable approved-sha reports 'unresolvable' and reds" ;;
      *) echo "FAIL: the legacy-note red did not say 'unresolvable': $_tr_leg"; st=1 ;;
    esac
  fi

  # ── EMPTY WINDOW FAIL-SAFE (review M2). A green over zero commits asserts nothing, so it must be
  # a FAIL. Untested until now, which is the same shape as the thing it guards against.
  _tr_zero="$( ( cd "$R" && $VSH "$VERIFY" trace --recent 0 --from "$TRUNK" 2>&1 ) || true )"
  if ( cd "$R" && $VSH "$VERIFY" trace --recent 0 --from "$TRUNK" >/dev/null 2>&1 ); then
    echo "FAIL: trace --recent 0 must FAIL (a green over an empty window asserts nothing)"; st=1
  else
    case "$_tr_zero" in
      *"walked ZERO commits"*) echo "PASS: empty-window fail-safe: --recent 0 FAILs and says it walked zero commits" ;;
      *) echo "FAIL: --recent 0 failed for the wrong reason: $_tr_zero"; st=1 ;;
    esac
  fi

  # ── KIT-ROW CONTROL-CHAR ARM (review M3 / security L-2). kit-row is DERIVED after the shared
  # sanitiser loop has run, so it carries its OWN control-char arm — which nothing exercised. A
  # trailer value is PR-controlled text and the note body is line-structured, so an ESC (or a
  # newline) here forges a note line exactly as one in --token would. Must be rc 2 with NO note.
  ( cd "$R" && git checkout -q -b ctrlrow "$TRUNK" && printf 'x\n' > ctrl.txt && git add ctrl.txt \
      && printf 'row with a control char\n\nKit-Row: DEMO\033ROW\nKit-Class: ordinary\n' \
         | git commit -q -F - ) || { echo "FAIL: could not build the control-char row fixture"; st=1; }
  CTRLC="$( ( cd "$R" && git rev-parse ctrlrow ) )"
  if ( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$CTRLC" --approved-by "solo maintainer" \
        --gate merge --rung integration --class Ordinary --scope "PR #1012" \
        --token "GO clean" >/dev/null 2>&1 ); then _ctrc=0; else _ctrc=$?; fi
  _ctnote="$( ( cd "$R" && git notes --ref=promotions show "$CTRLC" 2>/dev/null ) || true )"
  if [ "$_ctrc" = 2 ] && [ -z "$_ctnote" ]; then
    echo "PASS: kit-row control-char arm: a Kit-Row carrying an ESC is refused rc=2 with NO note bound"
  else
    echo "FAIL: kit-row control-char arm: want rc=2 + no note, got rc=$_ctrc note='$_ctnote'"; st=1
  fi

  # ── THE CI STEP IS SHAPE-LOCKED (security M-3). The recordless-merge leg is only a control while
  # it actually runs: commenting the line out, or appending `|| true`, leaves a green job that
  # checks nothing — and a reviewer reading the workflow would see the step name and believe it.
  # Anchored on the kit's own ci.yml, since the step is kit-tree only by design.
  #
  # ⚠️ KIT-TREE ONLY, AND THE LATCH IS NOT THE FILE UNDER TEST. `.github/workflows/ci.yml` is
  # `export-ignore`d, so it is legitimately ABSENT from an adopter export — and a leg that FAILed on
  # its absence reds every adopter's first push (measured: green-on-clone went RED on exactly this).
  # But latching on "ci.yml exists" would be a DARK GATE: delete the workflow on the kit tree and the
  # lock would N/A itself into silence. So the latch is `docs/ROADMAP-KIT.md` — a kit-only document,
  # also export-ignored — exactly the pattern the doc-families fold established. On a kit tree an
  # absent or gutted ci.yml still FAILS; only an adopter tree sees N/A.
  _ci="$SCRIPT_DIR/../.github/workflows/ci.yml"
  if [ ! -f "$SCRIPT_DIR/../docs/ROADMAP-KIT.md" ]; then
    echo "N/A: ci.yml trace-step lock — not a kit tree (no docs/ROADMAP-KIT.md); the kit's own CI is export-ignored"
  elif [ ! -f "$_ci" ]; then
    echo "FAIL: this IS a kit tree (docs/ROADMAP-KIT.md present) but .github/workflows/ci.yml is missing — the recordless-merge leg cannot be locked"; st=1
  else
    _ciline="$(grep -n 'promotion-verify\.sh trace --recent' "$_ci" | grep -v '^\s*#' | head -1)"
    if [ -z "$_ciline" ]; then
      echo "FAIL: ci.yml carries no live 'promotion-verify.sh trace --recent' run-line — the recordless-merge leg is not wired (or was commented out)"; st=1
    else
      case "$_ciline" in
        *'#'*'promotion-verify'*)
          echo "FAIL: the only trace --recent line in ci.yml is COMMENTED OUT: $_ciline"; st=1 ;;
        *'|| true'*|*'|| :'*|*'continue-on-error'*)
          echo "FAIL: the trace --recent line in ci.yml is neutered by an ignore-failure suffix: $_ciline"; st=1 ;;
        *) echo "PASS: ci.yml carries a LIVE, non-ignored 'promotion-verify.sh trace --recent' run-line" ;;
      esac
    fi
  fi

  # READ-ONLY: trace must not write a note, move a ref, or dirty the work-tree.
  _tr_notes_before="$( ( cd "$R" && git rev-parse refs/notes/promotions ) )"
  ( cd "$R" && $VSH "$VERIFY" trace --ref "$SQROW" >/dev/null 2>&1 ) || true
  _tr_notes_after="$( ( cd "$R" && git rev-parse refs/notes/promotions ) )"
  _tr_dirty="$( ( cd "$R" && git status --porcelain ) )"
  if [ "$_tr_notes_before" = "$_tr_notes_after" ] && [ -z "$_tr_dirty" ]; then
    echo "PASS: trace is read-only (notes ref unmoved, work-tree clean)"
  else
    echo "FAIL: trace mutated something: notes $_tr_notes_before->$_tr_notes_after dirty='$_tr_dirty'"; st=1
  fi

  # =====================================================================================
  # INJECTION NEGATIVES (LOAD-BEARING, FIX 1/2): the note body is line-structured text, so a control
  # char in ANY free-text field, or a bracket in --approved-by, must be REJECTED (rc=2) — a forged
  # `[signed: gpg]`/`[authenticated:` line can NEVER enter the note body. Load-bearing: a stub that
  # skips sanitization records the forged line (rc != 2) AND the note comes to contain the underived
  # label -> both halves FAIL. The last SUCCESSFUL record on APP above left [self-asserted], so a
  # forbidden label appearing = the injection landed.
  # =====================================================================================
  # reject_inj <label> <record-args...>: require rc=2 AND the note on APP holds no underived
  # [signed: gpg]/[authenticated:] line.
  reject_inj() {
    _lab="$1"; shift
    if ( cd "$R" && $VSH "$VERIFY" record "$@" >/dev/null 2>&1 ); then _irc=0; else _irc=$?; fi
    _forged="$( ( cd "$R" && git notes --ref=promotions show "$APP" 2>/dev/null \
                   | grep -E '\[signed: gpg\]|\[authenticated:' ) || true )"
    if [ "$_irc" = 2 ] && [ -z "$_forged" ]; then
      echo "PASS: $_lab (rejected rc=2, no forged label in note)"
    else
      echo "FAIL: $_lab want rc=2 + clean note, got rc=$_irc forged='$_forged'"; st=1
    fi
  }

  NL_TOK="$(printf 'GO\napproved-by: forged [signed: gpg]')"
  reject_inj "injection NEGATIVE: newline+forged [signed: gpg] in --token rejected" \
    --approved-sha "$APP" --approved-by "solo maintainer" --gate merge --rung integration --class Ordinary \
    --scope "PR #1002" --token "$NL_TOK"

  NL_BASIS="$(printf 'reviewer APPROVE\napproved-by: forged [authenticated: github-review]')"
  reject_inj "injection NEGATIVE: newline+forged [authenticated: in --basis rejected" \
    --approved-sha "$APP" --approved-by "solo maintainer" --gate merge --rung integration --class Ordinary \
    --scope "PR #1003" --token "GO clean" --basis "$NL_BASIS"

  reject_inj "injection NEGATIVE: mid-string [signed: gpg] in --approved-by rejected" \
    --approved-sha "$APP" --approved-by "attacker [signed: gpg] and more" --gate merge --rung integration \
    --class Ordinary --scope "PR #1004" --token "GO clean"

  # =====================================================================================
  # LAND — the one transactional actuation verb (SESSION-SURFACE slice 3d F3, Option A; design
  # 2026-09-10 §3 F3). `land` RECORDS the GO, CONFIRMS the note reached ORIGIN, then MERGES, then
  # leaves the branch intact — so a merge cannot be actuated on the direct/control-plane path
  # without a SHARED (on-origin) recoverable note being written first: the honest-but-forgetful
  # #658 failure (a forgotten second `gh pr merge`, AND a note that never left the local clone).
  #
  # ⚠️ VERB-SCOPED, NOT A HARD GATE (design A1). Every assertion here is scoped to the verb: `land`
  # refuses a recordless merge ONLY on its own path; the universal net is the CI recordless-merge
  # backstop. These legs run against a REAL bare-repo origin (mkorigin, mirroring the ledger-sync
  # harness below) so land's step-2 on-origin confirm actually executes — the old bare-$R fixture
  # had no remote and only exercised a LOCAL `git notes show`, which is the exact #658 state. A STUB
  # `--merge-cmd` records that it ran (the live `gh pr merge` is out of a selftest's scope, as
  # `actuate`'s is). LOAD-BEARING: liveness (a valid record + stub merge writes the note ON ORIGIN
  # and runs the merge) is the discriminant partner of negative(i). Since this slice's fix, `land`
  # REFUSES `--no-push` (a landing merge must publish) and its delete/--admin matcher is TOKENIZED
  # on IFS, so tab-separated and bundled-short-cluster forms are covered too.
  # =====================================================================================
  LR2=landx
  LAND_MARK="$D/.land-merged"
  # A STANDALONE one-word merge-cmd stub: it touches the marker and does NOTHING else — no shell
  # operator. Since this slice's step-3b declines the guard's whole word-shape set (; & | { } , * ? [
  # and $ backtick < > \), the old `<cmd> && touch MARK` / `; touch MARK` chaining would itself trip the
  # metachar arm and MISATTRIBUTE every leg's refusal (vacuous: land would refuse for the `&&`, not the
  # leg's intended reason). Instead each leg passes `"$LAND_STUB" <dangerous-token>` — the stub is the
  # command, the flag a separate ARG — so each leg still asserts its OWN reason. "Merge ran" == marker
  # present; land refuses before eval => marker absent.
  LAND_STUB="$D/land-stub"
  printf '#!/bin/sh\ntouch %s\n' "'$LAND_MARK'" > "$LAND_STUB"
  chmod +x "$LAND_STUB"
  # mkorigin <name> -> a bare remote.git + clone A carrying one commit pushed to origin/main. Sets
  # $LO (fixture root), $LOA (clone dir), $LOSHA (its head), $LOTRUNK (its branch). onote <sha> ->
  # true iff a note under refs/notes/$LR2 is bound to <sha> on the ORIGIN copy (never the local one).
  mkorigin() {
    LO="$D/land-$1"; rm -rf "$LO"; mkdir -p "$LO"
    git init -q --bare -b main "$LO/remote.git"
    ( set -e; cd "$LO"
      git clone -q remote.git A 2>/dev/null
      cd A
      git config user.email t@example.com; git config user.name t; git config commit.gpgsign false
      printf 'a\n' > f.txt; git add f.txt; git commit -qm base
      git push -q origin HEAD:refs/heads/main )
    fx_like_own "$LO/A"
    LOA="$LO/A"; LOSHA="$(git -C "$LOA" rev-parse HEAD)"
    LOTRUNK="$(git -C "$LOA" rev-parse --abbrev-ref HEAD)"
  }
  onote() { git --git-dir="$LO/remote.git" notes --ref="$LR2" show "$1" >/dev/null 2>&1; }
  # lgh <approved-sha> <approver> -> a dir holding a `gh` shim that answers the forge-review derivation
  # as a team repo would: <approver> has an APPROVED review bound to <approved-sha>, the PR author is a
  # different login. SINCE GO-IDENTITY-AND-LAND-SOD a control-plane `land` merges only on that
  # authenticated non-author approval (and needs --go-by), so every land leg that is NOT about that bar
  # supplies it here and keeps asserting its OWN reason. The shim prints the post-`--jq` TSV directly (no
  # jq dependency); the derivation itself is exercised against real jq in promotion-actuate-wired.sh.
  lgh() {
    _lgd="$(mktemp -d "$D/gh.XXXXXX")"
    # SWAS-537: `land` and `trace` also read exact-head CI evidence. The optional 3rd argument shapes that forge: by default the PR is
    # ready and its light run on <approved-sha> completed green with the gate job (the PR's head ref is `feat`); cheap (every shard
    # skipped), nogate (a run from before the gate job), redrun (the run failed), norun (no run) and apierr (the forge refuses) are the
    # TR cells' (the land cells about this evidence live in promotion-actuate-wired.sh).
    _lgk="${3:-light}"; _lgc=success; [ "$_lgk" != cheap ] || _lgc=skipped
    _lgr=success; [ "$_lgk" != redrun ] || _lgr=failure
    printf '{"id":900,"path":".github/workflows/ci.yml","run_number":1,"run_attempt":1,"status":"completed","conclusion":"%s","head_sha":"%s","head_branch":"feat","head_repository":{"full_name":"acme/kit"},"event":"pull_request"}\n' "$_lgr" "$1" > "$_lgd/evrun"
    [ "$_lgk" != norun ] || : > "$_lgd/evrun"
    for _lj in changes conformance-core conformance-selftests cf-doctor cf-export cf-export-claims cf-verify-enforced cf-claims cf-green-on-clone guard-battery guard-delta boundary-redteam h2-hermetic conformance-docs docs-links 'non-vacuity (1)'; do
      if [ "$_lgk" = noh2 ] && [ "$_lj" = h2-hermetic ]; then continue; fi   # noh2: a post-SWAS-864 run without its h2-hermetic job (an adopter's CI never has one)
      printf '{"name":"%s","conclusion":"%s"}\n' "$_lj" "$_lgc"
    done > "$_lgd/evjobs"
    printf '{"name":"conformance","conclusion":"success"}\n' >> "$_lgd/evjobs"
    [ "$_lgk" = nogate ] || printf '{"name":"gate","conclusion":"success"}\n' >> "$_lgd/evjobs"
    {
      printf '#!/bin/sh\ncase "$*" in\n'
      if [ -n "${4:-}" ]; then printf '  *pulls/%s\\ *) exit 1 ;;\n' "$4"; fi   # the 4th argument: a PR number the forge answers 404 for
      if [ "$_lgk" = apierr ]; then printf '  *draft*|*/actions/*|*rate_limit*) exit 1 ;;\n'; fi
      if [ -n "${LGH_NORATE:-}" ]; then printf '  *rate_limit*) exit 1 ;;\n'; fi   # LGH_NORATE=1: the forge answers the reads but REFUSES the credential-only probe (`gh api rate_limit`)
      printf '  *draft*) printf "false\\t%%s\\tfeat\\tacme/kit\\tacme/kit\\n" "%s" ;;\n  */actions/workflows/*) cat "%s/evrun" ;;\n  */actions/runs/*) cat "%s/evjobs" ;;\n' "$1" "$_lgd" "$_lgd"
      # LGH_NOREV=1 (SWAS-207b): the ONE-ACCOUNT forge — the reviews call answers NOTHING, so no approval can be derived
      if [ -n "${LGH_NOREV:-}" ]; then printf '  */reviews*) : ;;\n'
      else printf '  */reviews*) printf "APPROVED\\t%%s\\t%%s\\tUser\\n" "%s" "%s" ;;\n' "$1" "$2"; fi
      printf '  *) printf "AuthorLogin\\n" ;;\nesac\n'
    } > "$_lgd/gh"
    chmod +x "$_lgd/gh"
    printf '%s\n' "$_lgd"
  }
  # lland <merge-cmd> <approved-sha> <class> <scope> [extra land args...] -> sets _ldc and _ld_out.
  # Runs in $LOA with PROMOTION_NOTES_REF=$LR2 so nothing here can touch the real ledger. A
  # `branch/<name>` scope is only a unique leg label here: the forge derivation needs a PR scope, so it
  # is sent as `PR #77` (the shim above answers for any PR number).
  lland() {
    _lmc="$1"; _lasha="$2"; _lcls="$3"; _lscope="$4"; shift 4
    case "$_lscope" in branch/?*) _lscope="PR #77" ;; esac
    _lghd="$(lgh "$_lasha" "solo maintainer")"
    if _ld_out="$( cd "$LOA" && PATH="$_lghd:$PATH" PROMOTION_NOTES_REF="$LR2" $VSH "$VERIFY" land \
          --ref 77 --merge-cmd "$_lmc" --approved-sha "$_lasha" --approved-by "solo maintainer" \
          --go-by "the owner" --gate release-candidate --rung rc --class "$_lcls" \
          --scope "$_lscope" --token "GO: land at $_lasha" "$@" 2>&1 )"; then _ldc=0; else _ldc=$?; fi
  }

  # SWAS-948 (C4, C5) — `land` folds --gate and --rung BEFORE any forge read or merge, and re-appends the FOLDED values for record, so the
  # (scope, gate) pick it reads back by finds the record it just wrote. The unlisted value arrives after lland's own valid pair (last wins).
  mkorigin g948gate
  rm -f "$LAND_MARK"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/g948-gate" --gate desgin
  if [ "$_ldc" = 2 ] && [ ! -f "$LAND_MARK" ] && ! onote "$LOSHA" && printf '%s' "$_ld_out" | grep -qF "land: invalid --gate 'desgin'"; then
    echo "PASS: 948-C4: land with an unlisted --gate is refused rc 2 before any merge, no note on origin"
  else
    echo "FAIL: 948-C4: want rc 2 + no merge + no note + \"land: invalid --gate 'desgin'\"; got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi
  mkorigin g948rung
  rm -f "$LAND_MARK"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/g948-rung" --rung "Release candidate"
  if [ "$_ldc" = 2 ] && [ ! -f "$LAND_MARK" ] && ! onote "$LOSHA" && printf '%s' "$_ld_out" | grep -qF "land: invalid --rung 'Release candidate'"; then
    echo "PASS: 948-C4: land with an unlisted --rung is refused rc 2 before any merge, no note on origin"
  else
    echo "FAIL: 948-C4: want rc 2 + no merge + no note + \"land: invalid --rung 'Release candidate'\"; got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi
  mkorigin g948nl
  rm -f "$LAND_MARK"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/g948-nl" --gate "merge${_nl}"
  if [ "$_ldc" = 2 ] && [ ! -f "$LAND_MARK" ] && ! onote "$LOSHA" && printf '%s' "$_ld_out" | grep -q -e 'land: invalid --gate'; then
    echo "PASS: 948-C4: land with a gate that has a trailing newline is refused rc 2 before any merge, no note on origin"
  else
    echo "FAIL: 948-C4: want rc 2 + no merge + no note for --gate 'merge<newline>'; got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi
  mkorigin g948fold
  rm -f "$LAND_MARK"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/g948-fold" --gate Merge --rung Integration
  _g9on="$(git --git-dir="$LO/remote.git" notes --ref="$LR2" show "$LOSHA" 2>/dev/null || true)"
  if [ "$_ldc" = 0 ] && [ -f "$LAND_MARK" ] && onote "$LOSHA" && printf '%s\n' "$_g9on" | grep -qx 'gate: merge' && printf '%s\n' "$_g9on" | grep -qx 'rung: integration' \
     && ! printf '%s\n' "$_g9on" | grep -qx 'gate: Merge' && ! printf '%s\n' "$_g9on" | grep -qx 'rung: Integration'; then
    echo "PASS: 948-C4 fold: land --gate Merge --rung Integration finds its own record, merges the stub, and the note on origin holds the lowercase spelling"
  else
    echo "FAIL: 948-C4 fold: want rc 0 + merge + note on origin with 'gate: merge' / 'rung: integration'; got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out note=$_g9on"; st=1
  fi
  # C5: a hand-planted legacy `gate: promotion` note (the 218 in the ledger) is still READ by log and sync. The legacy note is a real record
  # rewritten in place, so its shape is whatever record writes today.
  mkorigin g948leg
  g9_rl() {
    ( cd "$LOA" && PROMOTION_NOTES_REF="$LR2" $VSH "$VERIFY" record --no-push --approved-sha "$LOSHA" --approved-by "solo maintainer" \
        --gate merge --rung integration --class control-plane --scope "PR #948" --token "GO: 948 legacy" >/dev/null 2>&1 )
  }
  g9_rl || { echo "FAIL: 948-C5: could not record the fixture note"; st=1; }
  ( cd "$LOA" && git notes --ref="$LR2" show "$LOSHA" | sed 's/^gate: merge$/gate: promotion/' | git notes --ref="$LR2" add -f -F - "$LOSHA" ) >/dev/null 2>&1 \
    || { echo "FAIL: 948-C5: could not plant the legacy note"; st=1; }
  if git -C "$LOA" notes --ref="$LR2" show "$LOSHA" 2>/dev/null | grep -qx 'gate: promotion'; then :; else echo "FAIL: 948-C5: the planted note carries no 'gate: promotion' line (the cell would be vacuous)"; st=1; fi
  if _g9lg="$( cd "$LOA" && PROMOTION_NOTES_REF="$LR2" $VSH "$VERIFY" log 2>&1 )" && printf '%s' "$_g9lg" | grep -qF "$LOSHA"; then
    echo "PASS: 948-C5: log still reads a planted 'gate: promotion' note"
  else echo "FAIL: 948-C5: log did not list the planted legacy note; out=$_g9lg"; st=1; fi
  if _g9sy="$( cd "$LOA" && PROMOTION_NOTES_REF="$LR2" $VSH "$VERIFY" sync --dry-run 2>&1 )" && ! printf '%s' "$_g9sy" | grep -qF "invalid --gate"; then
    echo "PASS: 948-C5: sync --dry-run still accepts a planted 'gate: promotion' note (rc 0, no gate refusal)"
  else echo "FAIL: 948-C5: sync --dry-run refused or errored on the planted legacy note; out=$_g9sy"; st=1; fi
  # (the legacy-beside-new coexistence cell, 948-COEX, is in the go-bound area below, on a solo base where go-bound judges)

  # (+) LIVENESS: a valid record + a stub merge -> rc 0, the stub ran, AND the GO note is ON ORIGIN
  #     (not merely local — the property #658 was missing). This exercises step-2's on-origin confirm.
  mkorigin live
  rm -f "$LAND_MARK"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/land-live"
  if [ "$_ldc" = 0 ] && [ -f "$LAND_MARK" ] && onote "$LOSHA"; then
    echo "PASS: land liveness: a valid record + stub merge bound the GO note ON ORIGIN and ran the merge"
  else
    echo "FAIL: land liveness: want rc=0 + merge + note-on-origin, got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ) onorigin=$( onote "$LOSHA" && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # =====================================================================================
  # SWAS-537 TR1-TR4 — `trace --recent`'s DETECTIVE evidence leg (ruling Q1: it prints and counts, and the exit code NEVER moves). A trunk
  # commit bound to a note naming PR 55 is read through the forge shim (lgh's 3rd argument shapes the forge). Every cell asserts the
  # exit code beside the printed lines, because "rc unchanged" is the contract.
  TRD="$D/tr537"; rm -rf "$TRD"; mkdir -p "$TRD"
  ( set -e; cd "$TRD"; git init -q -b main; git config user.email t@example.com; git config user.name t; git config commit.gpgsign false
    printf 'a\n' > f.txt; git add f.txt; git commit -qm 'squash merge of PR 55'
    _trc="$(git rev-parse HEAD)"
    printf 'record: promotion GO (approve->execute->log)\napproved-sha: %s\napproved-tree: %s\ngate: promotion\nkit-row: TR-ROW\nscope: PR #55\n' "$_trc" "$(git rev-parse 'HEAD^{tree}')" \
      | git notes --ref=promotions add -f -F - "$_trc" ) >/dev/null 2>&1 || { echo "FAIL: could not build the TR fixture"; st=1; }
  TRC="$(git -C "$TRD" rev-parse HEAD)"; TRC12="$(printf '%s' "$TRC" | cut -c1-12)"
  fx_like_own "$TRD"
  tr_run() {   # <forge kind|NOCRED> -> _trx_rc, _trx_out (a window of exactly the one bound commit)
    if [ "$1" = NOCRED ]; then _trg="$(mktemp -d "$D/gh.XXXXXX")"; printf '#!/bin/sh\nexit 1\n' > "$_trg/gh"; chmod +x "$_trg/gh"
    else _trg="$(lgh "$TRC" x "$1")"; fi
    if _trx_out="$( cd "$TRD" && PATH="$_trg:$PATH" $VSH "$VERIFY" trace --recent "${TRN:-1}" --from main 2>&1 )"; then _trx_rc=0; else _trx_rc=$?; fi
  }
  tr_cell() {  # <label> <forge kind> <expected rc> <needle> [must-not-contain]
    tr_run "$2"
    if [ "$_trx_rc" = "$3" ] && printf '%s' "$_trx_out" | grep -qF -e "$4" \
       && { [ -z "${5:-}" ] || ! printf '%s' "$_trx_out" | grep -qF -e "$5"; }; then echo "PASS: $1 (rc $_trx_rc)"
    else echo "FAIL: $1: want rc $3 + '$4'${5:+ and no '$5'}; got rc $_trx_rc; out=$_trx_out"; st=1; fi
  }
  if [ "$FX_KIND" = adopter ]; then fx_skip "TR1/TR2a-c/TR3/TR3b/TR3c/TR4"; else
  tr_cell "TR1: exact-head light evidence -> no flag, 1 commit read" light 0 "evidence leg: 0 FLAG(s) over 1 commit(s) read" "FLAG admin-merge"
  tr_cell "TR2a: a cheap run -> FLAG + count, rc unchanged" cheap 0 "FLAG admin-merge: $TRC12 head $TRC12 merged without exact-head light evidence (needed-job-not-success:changes)"
  tr_cell "TR2a: the summary counts the flag" cheap 0 "evidence leg: 1 FLAG(s) over 1 commit(s) read"
  tr_cell "TR2b: a red run -> FLAG run-not-success" redrun 0 "(run-not-success)"
  tr_cell "TR2c: no run at all -> FLAG no-graded-run" norun 0 "(no-graded-run)"
  tr_cell "TR3: no forge credential -> ONE UNVERIFIED line, no flag, rc unchanged" NOCRED 0 "evidence leg: UNVERIFIED (the first forge read failed" "FLAG admin-merge"
  tr_cell "TR3b: a forge that refuses every read -> the same UNVERIFIED, never a flag and never an ok" apierr 0 "evidence leg: UNVERIFIED" "0 FLAG(s)"
  tr_run NOCRED
  if [ "$(printf '%s\n' "$_trx_out" | grep -c '^evidence leg: UNVERIFIED')" = 1 ]; then echo "PASS: TR3c: exactly one UNVERIFIED line"
  else echo "FAIL: TR3c: want exactly one UNVERIFIED line; out=$_trx_out"; st=1; fi
  tr_cell "TR4: a run from before the gate job -> accepted as pre-gate, no flag" nogate 0 "pre-gate" "FLAG admin-merge"
  fi
  # rc parity: with a recordless commit on top (rc 1 today) the evidence leg moves nothing, flagged, unverified or ok.
  ( cd "$TRD" && printf 'b\n' >> f.txt && git commit -qam 'recordless merge' ) >/dev/null 2>&1
  TRN=2
  for _trk in light cheap NOCRED; do
    tr_run "$_trk"
    if [ "$_trx_rc" = 1 ] && printf '%s' "$_trx_out" | grep -qF -e 'has no promotion note'; then echo "PASS: TR-RC: a recordless commit in the window still reds (rc 1) with the evidence leg '$_trk'"
    else echo "FAIL: TR-RC ($_trk): want rc 1; got $_trx_rc; out=$_trx_out"; st=1; fi
  done
  TRN=1

  # =====================================================================================
  # SWAS-537 FIX ROUND, the trace leg. M1: the leg turns OFF only on proof of no credential, the FIRST forge read in the window
  # failing; after a successful read, a failing per-PR read prints a per-commit UNVERIFIED line and the walk goes on; the summary
  # counts FLAG, ok and UNVERIFIED commits and says PARTIAL when some were read. H1: the leg is scoped to the kit pipeline (the
  # decider beside the classifier AND a `gate:` job in that checkout's ci.yml): neither -> ONE N/A line; exactly one -> UNVERIFIED
  # kit-pipeline-half-present. A cell with a trailing sed script is a MUTANT: it rewrites a throwaway COPY of the gate (never a
  # switch in the shipped file) and passes only if the same assertion then FAILS. The window is two trunk commits: A (note PR #55,
  # oldest, walked first) then B (note PR #56).
  TR2D="$D/tr537b"; rm -rf "$TR2D"; mkdir -p "$TR2D"
  ( set -e; cd "$TR2D"; git init -q -b main; git config user.email t@example.com; git config user.name t; git config commit.gpgsign false
    printf 'a\n' > f.txt; git add f.txt; git commit -qm 'squash merge of PR 55'
    _ta1="$(git rev-parse HEAD)"; printf '%s\n' "$_ta1" > .ta1
    printf 'record: promotion GO (approve->execute->log)\napproved-sha: %s\napproved-tree: %s\ngate: promotion\nkit-row: TR-ROW\nscope: PR #55\n' "$_ta1" "$(git rev-parse 'HEAD^{tree}')" \
      | git notes --ref=promotions add -f -F - "$_ta1"
    printf 'b\n' >> f.txt; git commit -qam 'squash merge of PR 56'
    _ta2="$(git rev-parse HEAD)"
    printf 'record: promotion GO (approve->execute->log)\napproved-sha: %s\napproved-tree: %s\ngate: promotion\nkit-row: TR-ROW\nscope: PR #56\n' "$_ta1" "$(git rev-parse 'HEAD^{tree}')" \
      | git notes --ref=promotions add -f -F - "$_ta2" ) >/dev/null 2>&1 || { echo "FAIL: could not build the TR2 fixture"; st=1; }
  TA1="$(cat "$TR2D/.ta1" 2>/dev/null || true)"; TA2="$(git -C "$TR2D" rev-parse HEAD)"; TA12="$(printf '%s' "$TA1" | cut -c1-12)"; TB12="$(printf '%s' "$TA2" | cut -c1-12)"
  tr_copy() {  # <dir> <decider 0|1> <gate-job 0|1> [<marker 0|1> = the decider's] : a COPY of the gate in a kit-or-adopter layout (the classifier is always beside it)
    mkdir -p "$1/scripts" "$1/conformance" "$1/.github/workflows"
    cp "$VERIFY" "$1/scripts/promotion-verify.sh"
    cp "$(dirname "$VERIFY")/../conformance/ci-classify-changes.sh" "$1/conformance/ci-classify-changes.sh"
    if [ "$2" = 1 ]; then : > "$1/conformance/ci-gate-state.sh"; fi
    if [ "${4:-$2}" = 1 ]; then : > "$1/conformance/adopter-census.sh"; fi
    if [ "$3" = 1 ]; then printf 'jobs:\n  gate:\n    runs-on: x\n  changes:\n    needs: gate\n' > "$1/.github/workflows/ci.yml"
    else printf 'jobs:\n  changes:\n    runs-on: x\n' > "$1/.github/workflows/ci.yml"; fi
  }
  # tr_lay <label> <decider> <gate-job> <forge kind> <404-pr|-> <rc> <needle> <must-not|-> [<sed-script> = a mutant] [<repo decider> <repo gate-job> = the copy's] [<copy marker> = the decider's] [<repo marker> = the repo decider's] — trace --recent 2 through a gate COPY
  tr_lay() {
    _tl_dir="$D/trlay"; rm -rf "$_tl_dir"; tr_copy "$_tl_dir" "$2" "$3" "${12:-$2}"; _tl_mut=0
    fx_layout "$TR2D" "${10:-$2}" "${11:-$3}" "${13:-${10:-${12:-$2}}}"
    if [ -n "${9:-}" ]; then
      _tl_mut=1; cp "$_tl_dir/scripts/promotion-verify.sh" "$_tl_dir/orig.sh"; sed "$9" "$_tl_dir/orig.sh" > "$_tl_dir/scripts/promotion-verify.sh"
      if cmp -s "$_tl_dir/orig.sh" "$_tl_dir/scripts/promotion-verify.sh"; then echo "FAIL: $1: the mutant script changed nothing (it no longer matches the gate)"; st=1; return 0; fi
    fi
    _trg="$(lgh "$TA1" x "$4" "$([ "$5" = - ] || printf '%s' "$5")")"
    if _tl_out="$( cd "$TR2D" && PATH="$_trg:$PATH" $VSH "$_tl_dir/scripts/promotion-verify.sh" trace --recent "${TRW:-2}" --from main 2>&1 )"; then _tl_rc=0; else _tl_rc=$?; fi
    if [ "$_tl_rc" = "$6" ] && printf '%s' "$_tl_out" | grep -qF -e "$7" && { [ "$8" = - ] || ! printf '%s' "$_tl_out" | grep -qF -e "$8"; }; then _tl_ok=0; else _tl_ok=1; fi
    if [ "$_tl_mut" = 1 ]; then
      if [ "$_tl_ok" = 0 ]; then echo "FAIL: $1: the mutant SURVIVED (the cell passed against the broken gate)"; st=1; else echo "PASS: $1: the mutant is killed (the cell fails against it)"; fi
    elif [ "$_tl_ok" = 0 ]; then echo "PASS: $1 (rc $_tl_rc)"
    else echo "FAIL: $1: want rc $6 + '$7'$([ "$8" = - ] || printf ' and no %s' "$8"); got rc $_tl_rc; out=$_tl_out"; st=1; fi
  }
  TRM1A="evidence leg: PARTIAL — 1 FLAG(s), 0 ok, 0 pre-gate, 1 UNVERIFIED over 1 commit(s) read"
  tr_lay "M1a: a FLAG for the cheap commit read first, then the 404 PR -> its own UNVERIFIED line, the walk goes on" 1 1 cheap 56 0 "evidence leg: $TB12 UNVERIFIED (forge read failed)" -
  tr_lay "M1a: ... and the FLAG line for the cheap one" 1 1 cheap 56 0 "FLAG admin-merge: $TA12 head $TA12 merged without exact-head light evidence (needed-job-not-success:changes)" -
  tr_lay "M1a: ... and the summary says PARTIAL with the counts" 1 1 cheap 56 0 "$TRM1A" "no commit was checked"
  # M1b (fix round 2): a failing FIRST read with a WORKING credential (the credential-only probe `gh api rate_limit` answers) is that commit's
  # own UNVERIFIED line and the walk goes on, so the newer cheap commit B is still FLAGged. M1d: the probe fails too -> the single line.
  tr_lay "M1b: a 404 on the OLDEST PR with a working credential -> that commit's own UNVERIFIED line" 1 1 cheap 55 0 "evidence leg: $TA12 UNVERIFIED (forge read failed)" "the first forge read failed"
  tr_lay "M1b: ... and the newer cheap commit is still FLAGged" 1 1 cheap 55 0 "FLAG admin-merge: $TB12 head $TA12 merged without exact-head light evidence (needed-job-not-success:changes)" -
  tr_lay "M1b: ... and the summary says PARTIAL with the counts" 1 1 cheap 55 0 "evidence leg: PARTIAL — 1 FLAG(s), 0 ok, 0 pre-gate, 1 UNVERIFIED over 1 commit(s) read" "no commit was checked"
  LGH_NORATE=1
  tr_lay "M1d: the FIRST read fails AND the credential probe fails -> the single UNVERIFIED line, no flag, no partial" 1 1 cheap 55 0 "evidence leg: UNVERIFIED (the first forge read failed" "PARTIAL"
  tr_lay "M1d: ... and it never claims there is no credential" 1 1 cheap 55 0 "evidence leg: UNVERIFIED" "no forge credential"
  tr_lay "M1d: ... and no per-commit line follows" 1 1 cheap 55 0 "evidence leg: UNVERIFIED" "FLAG admin-merge"
  tr_lay "M1m2-mutant: the leg is never turned off (the failed probe is ignored)" 1 1 cheap 55 0 "evidence leg: UNVERIFIED (the first forge read failed" "PARTIAL" 's/if \[ "\$_tr_ev_n" -eq 0 \] && ! gh api rate_limit >\/dev\/null 2>&1; then _tr_ev_on=0/if false; then _tr_ev_on=0/'
  tr_lay "M1m4-mutant: the probe verdict is inverted" 1 1 cheap 55 0 "evidence leg: UNVERIFIED (the first forge read failed" "PARTIAL" 's/&& ! gh api rate_limit/\&\& gh api rate_limit/'
  LGH_NORATE=
  tr_lay "M1c: every read ok -> the summary counts FLAG, ok and UNVERIFIED" 1 1 light - 0 "evidence leg: 0 FLAG(s) over 2 commit(s) read (2 ok, 0 pre-gate, 0 UNVERIFIED)" "PARTIAL"
  tr_lay "M1m1-mutant: any failed read turns the leg off" 1 1 cheap 56 0 "$TRM1A" "no commit was checked" 's/if \[ "\$_tr_ev_n" -eq 0 \] && ! gh api rate_limit >\/dev\/null 2>&1; then _tr_ev_on=0/if true; then _tr_ev_on=0/'
  tr_lay "M1m3-mutant: the probe is not made (a failing first read always turns the leg off)" 1 1 cheap 55 0 "evidence leg: $TA12 UNVERIFIED (forge read failed)" "the first forge read failed" 's/ && ! gh api rate_limit >\/dev\/null 2>&1; then _tr_ev_on=0/; then _tr_ev_on=0/'
  tr_lay "H1-TR-a: an adopter layout -> the N/A line, once, no flag" 0 0 cheap - 0 "exact-head CI evidence: N/A (not the kit's own CI pipeline)" "FLAG admin-merge"
  tr_lay "H1-TR-b: a kit layout with a cheap run -> the FLAG" 1 1 cheap - 0 "FLAG admin-merge: $TA12" "N/A"
  tr_lay "H1-TR-c: decider only -> UNVERIFIED kit-pipeline-half-present, no flag" 1 0 cheap - 0 "evidence leg: UNVERIFIED (kit-pipeline-half-present" "FLAG admin-merge" "" "" "" 0
  tr_lay "H1-TR-d: an adopter's own gate job (no decider, no marker) -> the N/A line, no flag (SWAS-641)" 0 1 cheap - 0 "exact-head CI evidence: N/A (not the kit's own CI pipeline)" "FLAG admin-merge"
  tr_lay "H1-TR-e: the marker only -> UNVERIFIED kit-pipeline-half-present, no flag (SWAS-641)" 0 0 cheap - 0 "evidence leg: UNVERIFIED (kit-pipeline-half-present" "FLAG admin-merge" "" "" "" 1
  # SWAS-864: PG_NEEDED lists the kit-only join h2-hermetic, so the exact-head predicate must stay kit-only. An adopter layout reads its CI as N/A
  # before any job list is read (pv_ci_evidence and trace both stop at the layout), so a run with no h2-hermetic job is never refused for it; the kit layout does refuse it.
  tr_lay "H2-TR-a: an adopter layout whose CI run has no h2-hermetic job -> the N/A line, never needed-job-missing:h2-hermetic" 0 0 noh2 - 0 "exact-head CI evidence: N/A (not the kit's own CI pipeline)" "needed-job-missing:h2-hermetic"
  tr_lay "H2-TR-b: a kit layout whose CI run has no h2-hermetic job -> FLAG naming needed-job-missing:h2-hermetic" 1 1 noh2 - 0 "needed-job-missing:h2-hermetic" "N/A"
  # H2m-TR-1 is killed by its positive N/A needle, as H1m-TR-1 is; its must-not on needed-job-missing:h2-hermetic is the stronger proof only when paired with H2-TR-b.
  tr_lay "H2m-TR-1-mutant: the adopter branch runs the leg, so the missing h2-hermetic is held against an adopter" 0 0 noh2 - 0 "exact-head CI evidence: N/A (not the kit's own CI pipeline)" "needed-job-missing:h2-hermetic" 's/^    adopter\/adopter) _pv_ev_layout=adopter ;;/    adopter\/adopter) _pv_ev_layout=kit ;;/'
  tr_lay "H1m-TR-1-mutant: the adopter branch runs the leg" 0 0 cheap - 0 "exact-head CI evidence: N/A (not the kit's own CI pipeline)" "FLAG admin-merge" 's/^    adopter\/adopter) _pv_ev_layout=adopter ;;/    adopter\/adopter) _pv_ev_layout=kit ;;/'
  tr_lay "H1m-TR-2-mutant: the kit branch skips the leg" 1 1 cheap - 0 "FLAG admin-merge: $TA12" "N/A" 's/^    kit\/kit)         _pv_ev_layout=kit ;;/    kit\/kit)         _pv_ev_layout=adopter ;;/'
  tr_lay "H1m-TR-3-mutant: the half branch skips the leg" 1 0 cheap - 0 "evidence leg: UNVERIFIED (kit-pipeline-half-present" "FLAG admin-merge" 's/^    half\/\*|\*\/half)   _pv_ev_layout=refuse;/    half\/*|*\/half)   _pv_ev_layout=adopter;/'
  # LM-TR (fix round 2): the layout is read at the gate's own checkout AND the repository trace runs in. A mismatch either way prints ONE
  # UNVERIFIED line naming the token and both layouts, flags nothing, and leaves the exit code alone; a mutant per branch.
  tr_lay "LM-TR-a: an adopter-looking gate copy in a kit-layout repository -> UNVERIFIED layout-mismatch naming both layouts, no flag" 0 0 cheap - 0 "evidence leg: UNVERIFIED (layout-mismatch: this script's checkout reads adopter and the repository it operates on reads kit)" "FLAG admin-merge" "" 1 1
  tr_lay "LM-TR-b: a kit-layout gate copy in an adopter repository -> UNVERIFIED layout-mismatch naming both layouts, no flag" 1 1 cheap - 0 "evidence leg: UNVERIFIED (layout-mismatch: this script's checkout reads kit and the repository it operates on reads adopter)" "FLAG admin-merge" "" 0 0
  tr_lay "LM-TR-c: the repository is half -> UNVERIFIED kit-pipeline-half-present naming both layouts" 1 1 cheap - 0 "evidence leg: UNVERIFIED (kit-pipeline-half-present: this script's checkout reads kit and the repository it operates on reads half)" "FLAG admin-merge" "" 1 0
  tr_lay "LM-TR-m1-mutant: the mismatch branch fails open (adopter, the N/A line)" 0 0 cheap - 0 "evidence leg: UNVERIFIED (layout-mismatch" "N/A" 's/^    \*)               _pv_ev_layout=refuse; _pv_ev_lay_reason=layout-mismatch ;;/    *)               _pv_ev_layout=adopter ;;/' 1 1
  tr_lay "LM-TR-m2-mutant: the repository location is never read" 0 0 cheap - 0 "evidence leg: UNVERIFIED (layout-mismatch" "N/A" 's/_pl_repo="\$(pv_ev_lay_of "\$_pl_top")"/_pl_repo="$_pl_own"/' 1 1
  # no repository at all: the trace verb needs a repository to walk, so the no-git branch is proved by the evidence verb (promotion-actuate-wired.sh LM-d).
  # L4: a third commit whose note is scoped to a branch names no PR; a window of just that commit prints the per-commit UNVERIFIED line.
  ( cd "$TR2D" && printf 'c\n' >> f.txt && git commit -qam 'merge of branch x' && _tc3="$(git rev-parse HEAD)" \
    && printf 'record: promotion GO (approve->execute->log)\napproved-sha: %s\napproved-tree: %s\ngate: promotion\nkit-row: TR-ROW\nscope: branch/x\n' "$_tc3" "$(git rev-parse 'HEAD^{tree}')" \
      | git notes --ref=promotions add -f -F - "$_tc3" ) >/dev/null 2>&1 || { echo "FAIL: could not extend the TR2 fixture"; st=1; }
  TRW=1
  tr_lay "L4: a branch-scoped note prints a per-commit UNVERIFIED line, never a read, and the summary says none was read" 1 1 light - 0 "UNVERIFIED (the note's scope is not a PR id" "FLAG admin-merge"
  tr_lay "L4: ... and no commit was read" 1 1 light - 0 "evidence leg: UNVERIFIED — no commit was read" "PARTIAL"
  TRW=2
  rm -rf "$D/trlay" 2>/dev/null || true

  # =====================================================================================
  # SWAS-724 — `record --token-file`: the owner's GO words from a file, verbatim, never re-spelled. The agent guard refuses
  # one bare word on a command line wherever it sits, so a GO whose words hold that word ("...the full security read...")
  # could not be recorded through --token. R27 reads command lines, not file contents, and the line that runs this check
  # carries no such word, so cell 1 writes it literally here. Own throwaway repo (an own ledger) under $D/tfroot:
  #   repo/ the work tree · t/ the TMPDIR every cell runs with · out/ a directory under NEITHER root.
  # Every refusal cell asserts rc 2, the loader's OWN sentence and a byte-identical ledger ref. A cell with a sed script is a
  # MUTANT (M-TF1..4): it rewrites a throwaway COPY of the producer and passes only if the same refusal cell then FAILS.
  # =====================================================================================
  TFB="$D/tfroot"; TFR="$TFB/repo"; TFT="$TFB/t"; TFO="$TFB/out"; TF_V="$VERIFY"
  rm -rf "$TFB"; mkdir -p "$TFR" "$TFT/.hid" "$TFO"
  ( set -e; cd "$TFR"; git init -q -b main; git config user.email t@example.com; git config user.name t; git config commit.gpgsign false
    printf 'a\n' > f.txt; git add f.txt; git commit -qm 'token-file fixture' ) >/dev/null 2>&1 || { echo "FAIL: could not build the token-file fixture"; st=1; }
  TFC="$(git -C "$TFR" rev-parse HEAD 2>/dev/null)" || TFC=none
  tf_ledger() { git -C "$TFR" rev-parse -q --verify refs/notes/promotions 2>/dev/null || echo none; }
  tf_rec() {   # <TMPDIR for the run> <record args...> -> _tf_rc, _tf_out
    _tf_td="$1"; shift
    if _tf_out="$( cd "$TFR" && TMPDIR="$_tf_td" $VSH "$TF_V" record --no-push --approved-sha "$TFC" --approved-by "solo maintainer" \
          --gate merge --rung integration --class Ordinary --scope "branch/tf724" "$@" 2>&1 )"; then _tf_rc=0; else _tf_rc=$?; fi
  }
  tf_note() { git -C "$TFR" notes --ref=promotions show "$TFC" 2>/dev/null | grep -v '^recorded-at:' || true; }
  tf_refused() {   # <TMPDIR> <needle> <record args...>: 0 only when rc 2 + the needle + the ledger ref unchanged
    _tfr_td="$1"; _tfr_nd="$2"; shift 2
    _tfr_pre="$(tf_ledger)"; tf_rec "$_tfr_td" "$@"; _tfr_post="$(tf_ledger)"
    [ "$_tf_rc" = 2 ] && [ "$_tfr_pre" = "$_tfr_post" ] && printf '%s' "$_tf_out" | grep -qF -e "$_tfr_nd"
  }
  tf_cell() {   # <label> <TMPDIR> <needle> <record args...>
    _tfc_l="$1"; shift
    if tf_refused "$@"; then echo "PASS: $_tfc_l (rc 2, the loader's sentence, ledger untouched)"
    else echo "FAIL: $_tfc_l: want rc 2 + '$2' + an untouched ledger; got rc $_tf_rc; out=$_tf_out"; st=1; fi
  }
  tf_mut() {   # <label> <sed script> <TMPDIR> <needle> <record args...>: the same refusal cell must FAIL against the mutant
    _tfm_l="$1"; _tfm_s="$2"; shift 2
    rm -rf "$D/tfmut"; mkdir -p "$D/tfmut/scripts" "$D/tfmut/conformance"
    cp "$VERIFY" "$D/tfmut/orig.sh"; cp "$(dirname "$VERIFY")/../conformance/ci-classify-changes.sh" "$D/tfmut/conformance/ci-classify-changes.sh" 2>/dev/null || true
    sed "$_tfm_s" "$D/tfmut/orig.sh" > "$D/tfmut/scripts/promotion-verify.sh"
    if cmp -s "$D/tfmut/orig.sh" "$D/tfmut/scripts/promotion-verify.sh"; then echo "FAIL: $_tfm_l: the mutant script changed nothing (it no longer matches the producer)"; st=1; return 0; fi
    TF_V="$D/tfmut/scripts/promotion-verify.sh"
    # killed only when the cell fails AND the mutant run RECORDED (rc 0), not merely failed for another reason;
    # TF_MUT_WANT (when set) is the approval-token the mutant must have written into the note.
    _tfm_dead=1
    if tf_refused "$@"; then _tfm_dead=0
    elif [ "$_tf_rc" != 0 ]; then _tfm_dead=0
    elif [ -n "${TF_MUT_WANT:-}" ] && [ "$(tf_note | sed -n 's/^approval-token: //p')" != "$TF_MUT_WANT" ]; then _tfm_dead=0; fi
    if [ "$_tfm_dead" = 0 ]; then echo "FAIL: $_tfm_l: the mutant SURVIVED, or failed for another reason (rc $_tf_rc; want rc 0, a recorded note${TF_MUT_WANT:+ with approval-token $TF_MUT_WANT}); out=$_tf_out"; st=1
    else echo "PASS: $_tfm_l: the mutant is killed (the refusal cell fails against it and the mutant recorded)"; fi
    TF_V="$VERIFY"
  }

  # Cell 1: the owner's words, with the R27 word, recorded from a file and read back byte-identical.
  printf '%s\n' 'GO 717 design, with the full security read, as recommended' > "$TFT/r27"
  tf_rec "$TFT" --token-file "$TFT/r27"
  _tf_got="$(tf_note | sed -n 's/^approval-token: //p')"; _tf_want="\"$(cat "$TFT/r27")\""
  if [ "$_tf_rc" = 0 ] && [ "$_tf_got" = "$_tf_want" ]; then echo "PASS: TF1: a token holding the R27 word records from a file, byte-identical in the note"
  else echo "FAIL: TF1: want rc 0 and the note's approval-token == $_tf_want; got rc $_tf_rc, '$_tf_got'; out=$_tf_out"; st=1; fi
  # Cell 2: parity. The same words (no R27 word) by --token and by --token-file write the same note bytes (but the timestamp).
  printf '%s\n' 'GO: merge #724 parity' > "$TFT/par"
  tf_rec "$TFT" --token 'GO: merge #724 parity'; _tf_rc1=$_tf_rc; _tf_n1="$(tf_note)"
  tf_rec "$TFT" --token-file "$TFT/par"; _tf_n2="$(tf_note)"
  if [ "$_tf_rc1" = 0 ] && [ "$_tf_rc" = 0 ] && [ -n "$_tf_n1" ] && [ "$_tf_n1" = "$_tf_n2" ]; then echo "PASS: TF2: --token and --token-file write byte-identical notes"
  else echo "FAIL: TF2: rc $_tf_rc1/$_tf_rc; notes differ or are empty: [$_tf_n1] vs [$_tf_n2]"; st=1; fi

  # Cell 3: the refusals. Fixtures are built here at run time (no literal control byte, NUL or secret shape in this file).
  printf '%s\n' 'GO fine' > "$TFT/good"; ln -s "$TFT/good" "$TFT/link"
  printf '%s\n' 'GO fine' > "$TFO/tok"; printf '%s\n' 'GO fine' > "$TFT/.hid/tok"
  printf 'GO\nGO\n' > "$TFT/nl"; printf 'GO\n\n' > "$TFT/nl2"; printf 'GO\000x\n' > "$TFT/nul"
  : > "$TFT/empty"; head -c 4097 /dev/zero | LC_ALL=C tr '\000' 'a' > "$TFT/big"
  printf 'GO\001x\n' > "$TFT/ctl"; printf 'GO ghp_%036d\n' 0 > "$TFT/sec"
  tf_cell "TF3a: --token (even empty) and --token-file together" "$TFT" "give the token one way" --token "" --token-file "$TFT/good"
  tf_cell "TF3b: --token-file given twice" "$TFT" "was given twice" --token-file "$TFT/good" --token-file "$TFT/good"
  tf_cell "TF3c: a symlink" "$TFT" "must not be a symlink" --token-file "$TFT/link"
  tf_cell "TF3d: a path under neither the repo root nor TMPDIR" "$TFT" "must sit under the repo root" --token-file "$TFO/tok"
  tf_cell "TF3e: a dot component below the root" "$TFT" "must sit under the repo root" --token-file "$TFT/.hid/tok"
  tf_cell "TF3f: an embedded newline" "$TFT" "must hold exactly one line" --token-file "$TFT/nl"
  tf_cell "TF3g: two trailing newlines" "$TFT" "must hold exactly one line" --token-file "$TFT/nl2"
  tf_cell "TF3h: a NUL byte (mapped, then refused as a control character)" "$TFT" "control character" --token-file "$TFT/nul"
  tf_cell "TF3i: an empty file" "$TFT" "must be 1..4096 bytes" --token-file "$TFT/empty"
  tf_cell "TF3j: 4097 bytes" "$TFT" "must be 1..4096 bytes" --token-file "$TFT/big"
  tf_cell "TF3k: a control byte" "$TFT" "control character" --token-file "$TFT/ctl"
  tf_cell "TF3l: a secret shape" "$TFT" "token shape" --token-file "$TFT/sec"
  tf_cell "TF3m: --token-file with no value" "$TFT" "needs a path" --token-file
  # Cell 3 additions (reviewer Minors): a lone newline holds no content; a path with a non-printable byte; a dot component
  # below the REPO root; a file under the repo root accepted (TMPDIR points elsewhere, so only the repo root admits it).
  printf '\n' > "$TFT/lone"
  tf_cell "TF3n: a file holding only a newline" "$TFT" "holds no content" --token-file "$TFT/lone"
  _tf_badp="$TFT/bad$(printf '\001')name"; printf '%s\n' 'GO fine' > "$_tf_badp"
  tf_cell "TF3o: a path with a non-printable byte" "$TFT" "printable ASCII" --token-file "$_tf_badp"
  mkdir -p "$TFR/.dot" "$TFR/docs"; printf '%s\n' 'GO fine' > "$TFR/.dot/tok"; printf '%s\n' 'GO in repo' > "$TFR/docs/tok"
  tf_cell "TF3p: a dot component below the repo root" "$TFO" "must sit under the repo root" --token-file "$TFR/.dot/tok"
  tf_rec "$TFO" --token-file "$TFR/docs/tok"
  if [ "$_tf_rc" = 0 ] && [ "$(tf_note | sed -n 's/^approval-token: //p')" = '"GO in repo"' ]; then echo "PASS: TF3q: a file under the repo root is accepted (TMPDIR elsewhere)"
  else echo "FAIL: TF3q: want rc 0 and 'GO in repo'; got rc $_tf_rc; out=$_tf_out"; st=1; fi
  # Cell 4: the boundary. A 4095-byte line plus its newline is exactly 4096 raw bytes: accepted, the line verbatim.
  head -c 4095 /dev/zero | LC_ALL=C tr '\000' 'a' > "$TFT/edge"; printf '\n' >> "$TFT/edge"
  tf_rec "$TFT" --token-file "$TFT/edge"
  _tf_got="$(tf_note | sed -n 's/^approval-token: //p')"; _tf_want="\"$(head -c 4095 "$TFT/edge")\""
  if [ "$_tf_rc" = 0 ] && [ "$_tf_got" = "$_tf_want" ]; then echo "PASS: TF4: a 4096-byte file (4095-byte line + newline) records, the line verbatim"
  else echo "FAIL: TF4: want rc 0 and the 4095-byte line verbatim; got rc $_tf_rc; out=$_tf_out"; st=1; fi
  # Mutants. TF_MUT_WANT is reset first so an inherited environment value cannot leak into M-TF1 and M-TF2.
  TF_MUT_WANT=
  tf_mut "M-TF1: the sentinel removed (a plain command substitution eats every trailing newline)" 's/; printf x)$/)/;s/^  _tf_v=\${_tf_v%x}$/  _tf_v=$_tf_v/' "$TFT" "must hold exactly one line" --token-file "$TFT/nl2"
  tf_mut "M-TF2: the containment test removed" 's/^  _pv_tf_contained "\$_tf_phys" \\$/  true \\/' "$TFT" "must sit under the repo root" --token-file "$TFO/tok"
  TF_MUT_WANT='"GOx"'
  tf_mut "M-TF3: the NUL mapping removed (a NUL is dropped silently: GOx)" 's/ | LC_ALL=C tr .\\000. .\\001.; printf x)$/; printf x)/' "$TFT" "control character" --token-file "$TFT/nul"
  TF_MUT_WANT=
  tf_mut "M-TF4: the secret-shape refusal removed" 's/^  if _pv_tf_secret "\$_tf_v"; then$/  if false; then/' "$TFT" "token shape" --token-file "$TFT/sec"

  # SWAS-902 — `record` refuses template text in angle brackets (`<your name>`) in the eight screened fields, rc 2, before any write.
  # Every refuse cell asserts rc 2, an untouched ledger and its variant's line (a token sends the owner's words back to the owner; the
  # other fields say to write the value without the brackets). A later flag overrides tf_rec's default (the loop's last value wins).
  PH_TOK="never edit their words yourself"; PH_VAL="Write the value without '<' and '>'"
  tf_cell "PH1: --go-by '<your name>' is refused" "$TFT" "$PH_VAL" --token 'GO fine' --go-by '<your name>'
  tf_cell "PH2: --token '<your approval, in your words>' is refused, the owner is asked" "$TFT" "$PH_TOK" --token '<your approval, in your words>'
  printf '%s\n' "<the owner's words>" > "$TFT/ph1"
  tf_cell "PH3a: --token-file holding '<the owner's words>' is refused with the fixed first line (no span)" "$TFT" "record: --token-file holds text in angle brackets, which reads as an unfilled template." --token-file "$TFT/ph1"
  # PH3b/PH3c read the same run's output (_tf_out, left by PH3a): the ask-the-owner line is there, and no byte of the file is echoed.
  if printf '%s' "$_tf_out" | grep -qF -e "$PH_TOK"; then echo "PASS: PH3b: the --token-file refusal carries the ask-the-owner line"
  else echo "FAIL: PH3b: the --token-file refusal lacks '$PH_TOK'; out=$_tf_out"; st=1; fi
  if printf '%s' "$_tf_out" | grep -qF -e "the owner's words"; then echo "FAIL: PH3c: the --token-file refusal echoed the file's text; out=$_tf_out"; st=1
  else echo "PASS: PH3c: the --token-file refusal echoes no byte of the file"; fi
  tf_cell "PH4: --basis '<path-to-the-design-artifact>' is refused" "$TFT" "$PH_VAL" --token 'GO fine' --basis '<path-to-the-design-artifact>'
  tf_cell "PH5: --approved-by '<reviewer login>' is refused" "$TFT" "$PH_VAL" --token 'GO fine' --approved-by '<reviewer login>'
  tf_cell "PH6: --scope 'PR #<PR number>' is refused" "$TFT" "$PH_VAL" --token 'GO fine' --scope 'PR #<PR number>'
  tf_cell "PH7: --token '<…>' (an ellipsis span) is refused" "$TFT" "$PH_TOK" --token '<…>'
  tf_cell "PH8: --token 'I approve; tell <name> it shipped' is refused (the disclosed over-refusal, pinned)" "$TFT" "$PH_TOK" --token 'I approve; tell <name> it shipped'
  ph_allow() {   # <label> <note key> <want value> <record args...>: rc 0 and the note holds the value as stored
    _pa_l="$1"; _pa_k="$2"; _pa_w="$3"; shift 3
    tf_rec "$TFT" "$@"; _pa_g="$(tf_note | sed -n "s/^$_pa_k: //p")"
    if [ "$_tf_rc" = 0 ] && [ "$_pa_g" = "$_pa_w" ]; then echo "PASS: $_pa_l (recorded: $_pa_g)"
    else echo "FAIL: $_pa_l: want rc 0 and $_pa_k '$_pa_w'; got rc $_tf_rc, '$_pa_g'; out=$_tf_out"; st=1; fi
  }
  ph_allow "PH9: --token 'Go, merge PR 2' records" approval-token '"Go, merge PR 2"' --token 'Go, merge PR 2'
  ph_allow "PH10: --token 'ship it <3' records (a digit after '<')" approval-token '"ship it <3"' --token 'ship it <3'
  ph_allow "PH11: --token 'a < b and x -> y' records (no template span)" approval-token '"a < b and x -> y"' --token 'a < b and x -> y'
  ph_allow "PH12: --token 'a <= b' records ('=' after '<')" approval-token '"a <= b"' --token 'a <= b'
  ph_allow "PH13: --go-by 'Pat Doe <pat@example.com>' records (git's Name <email> form)" go-by 'Pat Doe <pat@example.com> [self-asserted]' --token 'GO fine' --go-by 'Pat Doe <pat@example.com>'
  # Mutants. 1: the CALL in record removed (the shared predicate stays), so the refuse cells record instead. 2: the '@' exclusion removed
  # from the grammar, so the allow cell PH13 is refused (the check below passes only when the mutant refuses it, rc 2, with the new message).
  TF_MUT_WANT=
  tf_mut "M-PH1a: the record call removed -> PH1's '<your name>' go-by records" 's|^    if _pv_placeholder_span "\$_fv" >/dev/null; then   # PV-PLACEHOLDER-RECORD$|    if false; then   # PV-PLACEHOLDER-RECORD|' "$TFT" "$PH_VAL" --token 'GO fine' --go-by '<your name>'
  tf_mut "M-PH1b: the record call removed -> PH2's template token records" 's|^    if _pv_placeholder_span "\$_fv" >/dev/null; then   # PV-PLACEHOLDER-RECORD$|    if false; then   # PV-PLACEHOLDER-RECORD|' "$TFT" "$PH_TOK" --token '<your approval, in your words>'
  rm -rf "$D/tfmut"; mkdir -p "$D/tfmut/scripts" "$D/tfmut/conformance"
  cp "$VERIFY" "$D/tfmut/orig.sh"; cp "$(dirname "$VERIFY")/../conformance/ci-classify-changes.sh" "$D/tfmut/conformance/ci-classify-changes.sh" 2>/dev/null || true
  sed 's/<>@]/<>]/g' "$D/tfmut/orig.sh" > "$D/tfmut/scripts/promotion-verify.sh"
  if cmp -s "$D/tfmut/orig.sh" "$D/tfmut/scripts/promotion-verify.sh"; then echo "FAIL: M-PH2: the mutant script changed nothing (it no longer matches the producer)"; st=1
  else
    TF_V="$D/tfmut/scripts/promotion-verify.sh"; tf_rec "$TFT" --token 'GO fine' --go-by 'Pat Doe <pat@example.com>'; TF_V="$VERIFY"
    if [ "$_tf_rc" = 2 ] && printf '%s' "$_tf_out" | grep -qF -e "$PH_VAL"; then echo "PASS: M-PH2: the '@' exclusion removed -> PH13's 'Name <email>' go-by is refused (the mutant is killed)"
    else echo "FAIL: M-PH2: the mutant SURVIVED (want rc 2 and '$PH_VAL'; got rc $_tf_rc); out=$_tf_out"; st=1; fi
  fi
  rm -rf "$D/tfmut" "$TFB" 2>/dev/null || true

  # =====================================================================================
  # SWAS-207b — `land` in a SOLO-DECLARED repo. The base (origin's main) carries MERGE_RELATIONSHIP=solo, so the forge shim answers
  # NO reviews (one account) and `land` still records, confirms on origin and merges: step 0b (SoD) and 0d(ii) (the forge
  # pre-derivation) are skipped, `--go-by`, scope == ref, the whole-note match, the origin confirm and the vet stay, and step 2b
  # judges the SOLO BAR on the note read back from origin. Every negative asserts the merge marker is ABSENT and its OWN reason.
  # =====================================================================================
  # lsolo_base <dial-line|NONE> [claude-md-line] — commits .kit/dials.conf (and CLAUDE.md) onto the fixture base and pushes it as
  # origin's main; LOSHA becomes that commit, so the approved head is the base tip itself (its tree carries the declaration too).
  lsolo_base() {
    ( set -e; cd "$LOA"
      if [ "$1" != NONE ]; then mkdir -p .kit; printf '%s\n' "$1" > .kit/dials.conf; git add .kit/dials.conf; fi
      if [ -n "${2:-}" ]; then printf '%s\n' "$2" > CLAUDE.md; git add CLAUDE.md; fi
      git commit -qm "declare the merge relationship"; git push -q origin HEAD:refs/heads/main )
    LOSHA="$(git -C "$LOA" rev-parse HEAD)"
  }
  lsolo_report() {   # <label> <merge|refuse> <needle>: asserts rc, the marker and the label's own line from the last lland
    _lsl="$1"; _lsw="$2"; _lsn="$3"
    if [ "$_lsw" = merge ]; then
      if [ "$_ldc" = 0 ] && [ -f "$LAND_MARK" ] && onote "$LOSHA" && printf '%s' "$_ld_out" | grep -qF -e "$_lsn"; then
        echo "PASS: $_lsl"
      else
        echo "FAIL: $_lsl: want rc=0 + merge + note on origin + '$_lsn', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
      fi
    elif [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -qF -e "$_lsn"; then
      echo "PASS: $_lsl"
    else
      echo "FAIL: $_lsl: want rc!=0 + NO merge + '$_lsn', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
    fi
  }
  LGH_NOREV=1
  mkorigin lsolo; lsolo_base MERGE_RELATIONSHIP=solo
  rm -f "$LAND_MARK"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/ls-live"
  lsolo_report "land SOLO liveness: base declares solo, no forge review -> recorded, confirmed on origin, merged" merge "merge relationship: solo (origin/main"
  if git --git-dir="$LO/remote.git" notes --ref="$LR2" show "$LOSHA" | grep '^approved-by:' | grep -qF 'authenticated'; then
    echo "FAIL: land SOLO liveness: the recorded label claims an authenticated review that no forge gave"; st=1
  else
    echo "PASS: land SOLO liveness: the note on origin carries no authenticated label (nothing authenticates the solo GO)"
  fi
  # the author SoD (step 0b) is skipped in solo: the approver IS the commit author (one account)
  mkorigin lsolosod; lsolo_base MERGE_RELATIONSHIP=solo
  rm -f "$LAND_MARK"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/ls-sod" --approved-by t
  lsolo_report "land SOLO: approver == commit author is NOT refused (step 0b skipped) -> merged" merge "merge relationship: solo"
  # the solo bar's gate leg, at 2b on the note read back from origin: a design GO is not a merge GO
  mkorigin lsologate; lsolo_base MERGE_RELATIONSHIP=solo
  rm -f "$LAND_MARK"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/ls-gate" --gate plan
  lsolo_report "land SOLO NEGATIVE: gate 'plan' (a typed pre-build gate; SWAS-948 moved it off the unlisted 'design-arm') fails the solo bar at 2b, refused before the merge" refuse "pre-build gate"
  # --go-by stays REQUIRED in solo (0d(i) is kept)
  mkorigin lsologoby; lsolo_base MERGE_RELATIONSHIP=solo
  rm -f "$LAND_MARK"
  if _ld_out="$( cd "$LOA" && PATH="$(lgh "$LOSHA" "x"):$PATH" PROMOTION_NOTES_REF="$LR2" $VSH "$VERIFY" land --ref 77 --merge-cmd "$LAND_STUB" \
        --approved-sha "$LOSHA" --approved-by "solo maintainer" --gate release-candidate --rung rc \
        --class control-plane --scope "PR #77" --token "GO" 2>&1 )"; then _ldc=0; else _ldc=$?; fi
  lsolo_report "land SOLO NEGATIVE: no --go-by is still refused (0d(i) kept), nothing merged" refuse "--go-by"
  # SWAS-902: land reaches record's template-text refusal (solo, so no earlier team-mode refusal can pass for it): the new message, no merge,
  # no note on origin or in the clone's ledger. The later --go-by overrides lland's default one.
  mkorigin lsoloph; lsolo_base MERGE_RELATIONSHIP=solo
  rm -f "$LAND_MARK"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/ls-ph" --go-by '<the GO-giver>'
  lsolo_report "land SOLO NEGATIVE (SWAS-902): --go-by '<the GO-giver>' is refused by record's template-text check, nothing merged" refuse "Write the value without '<' and '>'"
  if onote "$LOSHA" || git -C "$LOA" notes --ref="$LR2" show "$LOSHA" >/dev/null 2>&1; then
    echo "FAIL: land SOLO NEGATIVE (SWAS-902): a note was written although the go-by was template text"; st=1
  else
    echo "PASS: land SOLO NEGATIVE (SWAS-902): no note on origin or in the clone's ledger"
  fi
  # a note planted on origin whose approved-tree is NOT the sha's tree: a post-receive hook on the bare origin rewrites the
  # note record just published, so land's step 2 reads the planted copy back and the solo bar's tree leg refuses it
  mkorigin lsolotree; lsolo_base MERGE_RELATIONSHIP=solo
  printf '#!/bin/sh\nfor o in $(git notes --ref=%s list | cut -d" " -f2); do\n  git notes --ref=%s show "$o" | sed "s/^approved-tree: .*/approved-tree: 0000000000000000000000000000000000000000/" \\\n    | GIT_COMMITTER_NAME=x GIT_COMMITTER_EMAIL=x@example.com GIT_AUTHOR_NAME=x GIT_AUTHOR_EMAIL=x@example.com git notes --ref=%s add -f -F - "$o"\ndone\n' "$LR2" "$LR2" "$LR2" > "$LO/remote.git/hooks/post-receive"
  chmod +x "$LO/remote.git/hooks/post-receive"
  rm -f "$LAND_MARK"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/ls-tree"
  lsolo_report "land SOLO NEGATIVE: a note planted on origin with approved-tree != the sha's tree is refused BEFORE the merge" refuse "approved-tree"
  # team unchanged: an UNDECLARED base keeps the authenticated-approval bar, so the same no-review run is refused at 0d(ii)
  mkorigin lteam
  rm -f "$LAND_MARK"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/ls-team"
  lsolo_report "land TEAM unchanged: an undeclared base + no forge review -> refused at 0d(ii), nothing merged" refuse "AUTHENTICATED NON-AUTHOR"
  # the declaration is read from the BASE, not the approved tree: the head declares solo, origin's main does not -> team bar
  mkorigin lsolobase
  ( set -e; cd "$LOA"; git checkout -q -b declares-solo; mkdir -p .kit; printf 'MERGE_RELATIONSHIP=solo\n' > .kit/dials.conf
    git add .kit/dials.conf; git commit -qm "declare solo in the PR" )
  LOSHA="$(git -C "$LOA" rev-parse HEAD)"
  rm -f "$LAND_MARK"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/ls-base"
  lsolo_report "land: the APPROVED TREE declares solo but origin's main does not -> the team bar refuses, nothing merged" refuse "AUTHENTICATED NON-AUTHOR"
  # a Governance team line on the base tightens a solo dial
  mkorigin lsologov; lsolo_base MERGE_RELATIONSHIP=solo '- **Governance** (§ solo/team): team — non-author approval'
  rm -f "$LAND_MARK"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/ls-gov"
  lsolo_report "land: base dial solo + CLAUDE.md Governance team -> the team bar, and the override is said" refuse "CLAUDE.md Governance: team overrides MERGE_RELATIONSHIP=solo"
  LGH_NOREV=""

  # (+claim) LAND RELEASES THE ROW'S OWN CLAIM [B2-SESSION-IDENTITY-LEDGER, design decision 6].
  #     `do_actuate` has released the claim since BOARD-CLAIM-MECHANISM §3.5; `do_land` ended at the
  #     merge with nothing. THE EIGHT STALE CLAIM REFS OF 2026-09-15 ARE THAT GAP — eight shipped
  #     slices whose close never released the row, and with B4's WIP ceiling live the next `claim`
  #     would have refused. Both verbs now call ONE shared helper after their verification.
  #     The fixture commit carries a `Kit-Row:` trailer, so `record`'s own projection (never a flag)
  #     is what names the row; the claim's branch does not exist on origin, so the release is
  #     P1-provable and needs no dial.
  mkorigin claimrel
  rm -f "$LAND_MARK"
  # ⚠️ THE FIXTURE IS P3, NOT P1, SINCE FIX ROUND 1 (H2). It used to give the claim a branch that was
  # absent from origin and lean on that as the proof. "Branch absent" is no longer a proof — under
  # one-push-per-PR it is the normal state of a healthy in-build slice — so the fixture now models
  # what a real land actually produces: the row sitting in `## Done` on the DEFAULT BRANCH's board,
  # which is exactly the state the merge creates and is why a land release is P3-provable by
  # construction. The claim's branch is `feat/land-live` and it EXISTS on origin, so nothing here
  # can pass on the withdrawn proof by accident.
  ( set -e; cd "$LOA"
    printf 'b\n' >> f.txt; git add f.txt
    printf '%s\n' '# Fixture — Backlog' '' '## Done' '' \
      '| Item | Closed | Retro/outcome |' '|------|--------|---------------|' \
      '| `ROW-LAND` — landed by the fixture | 2026-09-16 | L1 retro. Disposition: none — fixture. |' \
      > BACKLOG.md
    git add BACKLOG.md
    git commit -qm "land claim fixture

Kit-Row: ROW-LAND"
    git push -q origin HEAD:refs/heads/main
    git push -q origin HEAD:refs/heads/feat/land-live ) >/dev/null 2>&1
  git --git-dir="$LO/remote.git" symbolic-ref HEAD refs/heads/main
  LOSHA2="$(git -C "$LOA" rev-parse HEAD)"
  _cl_blob=$(printf 'row: ROW-LAND\nclaimant: Builder <b@example.com>\nbranch: feat/land-live\nclaimed-at: 2026-09-01T00:00:00Z\nsession: s-20260901-aaaabbbb (declared)\n' | git -C "$LOA" hash-object -w --stdin)
  _cl_tree=$(printf '100644 blob %s\tCLAIM\n' "$_cl_blob" | git -C "$LOA" mktree)
  _cl_commit=$(printf 'claim ROW-LAND\n' | git -C "$LOA" commit-tree "$_cl_tree")
  git -C "$LOA" push -q origin "$_cl_commit:refs/claims/ROW-LAND"
  if git --git-dir="$LO/remote.git" rev-parse --verify -q refs/claims/ROW-LAND >/dev/null; then
    echo "PASS: land releases the claim — the fixture claim ref EXISTS on origin before the land"
  else
    echo "FAIL: land releases the claim — the fixture claim ref was never created (the leg would be vacuous)"; st=1
  fi
  lland "$LAND_STUB" "$LOSHA2" control-plane "branch/land-claimrel"
  if [ "$_ldc" = 0 ] && [ -f "$LAND_MARK" ] \
     && ! git --git-dir="$LO/remote.git" rev-parse --verify -q refs/claims/ROW-LAND >/dev/null \
     && git --git-dir="$LO/remote.git" rev-parse --verify -q refs/claims-log/ROW-LAND >/dev/null; then
    echo "PASS: land releases the claim — after a verified merge the claim ref is GONE and a refs/claims-log entry exists"
  else
    echo "FAIL: land releases the claim: want rc=0 + merge + claim gone + a claims-log entry, got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ) claim=$( git --git-dir="$LO/remote.git" rev-parse --verify -q refs/claims/ROW-LAND >/dev/null && echo present || echo gone ); out=$_ld_out"; st=1
  fi
  # …AND A FAILING RELEASE IS A WARN, NEVER A MERGE FAILURE. The merge ALREADY HAPPENED; returning
  #     non-zero would report a successful, verified promotion as failed, and no rc can un-merge it.
  #     The failure is made honestly: the claim verbs are pointed at a remote that does not exist.
  mkorigin claimwarn
  rm -f "$LAND_MARK"
  ( set -e; cd "$LOA"
    printf 'c\n' >> f.txt; git add f.txt
    git commit -qm "land claim warn fixture

Kit-Row: ROW-LANDWARN"
    git push -q origin HEAD:refs/heads/main ) >/dev/null 2>&1
  LOSHA3="$(git -C "$LOA" rev-parse HEAD)"
  if _ld_out="$( cd "$LOA" && PATH="$(lgh "$LOSHA3" "solo maintainer"):$PATH" PROMOTION_NOTES_REF="$LR2" BOARD_CLAIM_REMOTE="$LO/no-such-remote.git" \
        $VSH "$VERIFY" land --ref 77 --merge-cmd "$LAND_STUB" --approved-sha "$LOSHA3" \
        --approved-by "solo maintainer" --go-by "the owner" --gate release-candidate --rung rc \
        --class control-plane --scope "PR #77" --token "GO: land at $LOSHA3" 2>&1 )"; then _ldc=0; else _ldc=$?; fi
  if [ "$_ldc" = 0 ] && [ -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q 'WARN' \
     && printf '%s' "$_ld_out" | grep -q 'board-claim.sh release ROW-LANDWARN --stale'; then
    echo "PASS: land releases the claim — a FAILING release is a WARN carrying the by-hand command, and land still returns 0"
  else
    echo "FAIL: land releases the claim (warn path): want rc=0 + merge + WARN + the by-hand command, got rc=$_ldc; out=$_ld_out"; st=1
  fi

  # (−no-push) --no-push is REFUSED: a landing merge must PUBLISH the GO record so it reaches origin;
  #     landing on a local-only note would reopen #658. rc != 0, the stub must NOT run, reason names
  #     --no-push. (Finding 1: the old land passed --no-push through to record and merged on a note
  #     that never left the clone.)
  mkorigin nopush
  rm -f "$LAND_MARK"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/land-np" --no-push
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q 'no-push'; then
    echo "PASS: land NEGATIVE(--no-push): a landing --no-push is refused, the merge did NOT run (closes #658)"
  else
    echo "FAIL: land NEGATIVE(--no-push): want rc!=0 + no merge + 'no-push', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−i) RECORD FAILS -> NO merge. A malformed --scope (`branch/` names no branch) reds `record` (rc 2)
  #      BEFORE any note is written, so the stub merge must NOT run and the reason is verb-scoped. The
  #      sha is PRESENT and the approver is not its author, so land's SoD (pv_sod_author_check) passes,
  #      and the class is control-plane so land's OWN class gate (F3-2) passes: the failure is genuinely
  #      record's. (This leg used to feed an UNRESOLVABLE sha; since ACTUATE-SOD-EMPTY-AUTHOR land's SoD
  #      refuses that first — SODEA-L1/METER(fix1 D) cover it. Discriminant partner of the liveness leg
  #      above; the bad-class case is caught by land's class gate — see NEGATIVE(unknown-class) below.)
  #      SINCE GO-IDENTITY-AND-LAND-SOD a bare `branch/` scope could never clear land's authenticated-
  #      approval bar (no PR to read reviews from), so land would refuse BEFORE record and this leg would
  #      stop reaching record at all. The record failure is made with an EMPTY --token instead (record
  #      refuses it rc 2 before any note), behind a bar that clears: the failure is still genuinely record's.
  mkorigin badscope
  rm -f "$LAND_MARK"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/land-badtoken" --token ""
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && ! onote "$LOSHA" && printf '%s' "$_ld_out" | grep -q 'will not merge'; then
    echo "PASS: land NEGATIVE(i): a record failure -> land refuses (verb-scoped), the merge did NOT run"
  else
    echo "FAIL: land NEGATIVE(i): want rc!=0 + no merge + 'will not merge', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−ii) A SPACE-separated --delete-branch is REFUSED and the merge does NOT run. `land` NEVER
  #       deletes a branch (D-240819-4) — the branch object holds the commit the GO note binds. The
  #       merge-cmd is `<stub> --delete-branch`: land refuses at the step-4 delete arm before eval, so
  #       the stub never runs and a missing marker proves the refusal.
  mkorigin delspace
  rm -f "$LAND_MARK"
  lland "$LAND_STUB --delete-branch" "$LOSHA" control-plane "branch/land-del"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q 'deletes a branch'; then
    echo "PASS: land NEGATIVE(ii): a space-separated --delete-branch is refused, the merge did NOT run"
  else
    echo "FAIL: land NEGATIVE(ii): want rc!=0 + no merge + 'deletes a branch', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−iii) A TAB-separated --delete-branch is REFUSED (the space-anchored glob missed this — Finding
  #        2). Tokenizing on IFS (which includes TAB) makes --delete-branch its own token regardless
  #        of the surrounding whitespace.
  mkorigin deltab
  rm -f "$LAND_MARK"
  _land_tabtok="$(printf '%s\t--delete-branch' "$LAND_STUB")"
  lland "$_land_tabtok" "$LOSHA" control-plane "branch/land-deltab"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q 'deletes a branch'; then
    echo "PASS: land NEGATIVE(iii): a TAB-separated --delete-branch is refused (IFS tokenization)"
  else
    echo "FAIL: land NEGATIVE(iii): want rc!=0 + no merge + 'deletes a branch', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−iv) A BUNDLED SHORT CLUSTER -sd (= --squash --delete-branch) is REFUSED (the space-anchored
  #       ' -d ' glob missed a bundled cluster — Finding 2). A single-dash token containing 'd' denies.
  mkorigin delcluster
  rm -f "$LAND_MARK"
  lland "$LAND_STUB -sd" "$LOSHA" control-plane "branch/land-sd"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q 'deletes a branch'; then
    echo "PASS: land NEGATIVE(iv): a bundled short cluster -sd is refused (single-dash token containing d)"
  else
    echo "FAIL: land NEGATIVE(iv): want rc!=0 + no merge + 'deletes a branch', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−v) --admin is REFUSED and the merge does NOT run (Finding 3: the --admin arm had no leg). Fed
  #      TAB-separated so it ALSO regresses the tokenization gap on the --admin arm (the old space
  #      glob would have missed this exact form). Approval authorizes promotion, never a bypass.
  mkorigin admin
  rm -f "$LAND_MARK"
  _land_admtok="$(printf '%s\t--admin' "$LAND_STUB")"
  lland "$_land_admtok" "$LOSHA" control-plane "branch/land-admin"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q -- '--admin'; then
    echo "PASS: land NEGATIVE(v): a TAB-separated --admin is refused, the merge did NOT run (deny arm has teeth)"
  else
    echo "FAIL: land NEGATIVE(v): want rc!=0 + no merge + '--admin', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−vii) --admin=VALUE is REFUSED (F3-1): the old EXACT-match --admin arm let the =value spelling
  #        through — --admin=true never exact-matched --admin, so a bypass rode in on a value suffix.
  #        A landing merge never needs --admin in ANY form, so --admin=* is refused as a class (the
  #        over-refusal of the cosmetic --admin=false is the correct, disclosed trade). Fed
  #        TAB-separated so it also covers the tokenization on the =value arm.
  mkorigin adminval
  rm -f "$LAND_MARK"
  _land_admvaltok="$(printf '%s\t--admin=true' "$LAND_STUB")"
  lland "$_land_admvaltok" "$LOSHA" control-plane "branch/land-adminval"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q -- '--admin'; then
    echo "PASS: land NEGATIVE(vii): --admin=true (=value spelling) is refused, the merge did NOT run"
  else
    echo "FAIL: land NEGATIVE(vii): want rc!=0 + no merge + '--admin', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−viii) A DOUBLE-QUOTED "--admin" is REFUSED (F3-1): the merge-cmd is one string, so a caller who
  #         quotes the flag leaves the quote bytes on the token here (this is a tokenize, not a shell
  #         re-lex). Stripping ' and " from each token before the case normalizes "--admin" -> --admin.
  mkorigin adminq
  rm -f "$LAND_MARK"
  _land_admqtok="$(printf '%s "--admin"' "$LAND_STUB")"
  lland "$_land_admqtok" "$LOSHA" control-plane "branch/land-adminq"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q -- '--admin'; then
    echo "PASS: land NEGATIVE(viii): a double-quoted \"--admin\" is refused (quote-strip before match)"
  else
    echo "FAIL: land NEGATIVE(viii): want rc!=0 + no merge + '--admin', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−ix) A SINGLE-QUOTED '--delete-branch' is REFUSED (F3-1): same quote-strip, so a quoted deletion
  #        flag cannot smuggle past the matcher.
  mkorigin delq
  rm -f "$LAND_MARK"
  _land_delqtok="$(printf "%s '--delete-branch'" "$LAND_STUB")"
  lland "$_land_delqtok" "$LOSHA" control-plane "branch/land-delq"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q 'deletes a branch'; then
    echo "PASS: land NEGATIVE(ix): a single-quoted '--delete-branch' is refused (quote-strip before match)"
  else
    echo "FAIL: land NEGATIVE(ix): want rc!=0 + no merge + 'deletes a branch', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−x) A SPLIT-QUOTE --del''ete-branch is REFUSED (F3-1): adjacent empty quotes inside a token
  #       survive word-splitting as the literal bytes --del''ete-branch; quote-strip reassembles
  #       --delete-branch before the case, so the split spelling cannot evade the delete arm.
  mkorigin delsplit
  rm -f "$LAND_MARK"
  _land_delsplittok="$(printf "%s --del''ete-branch" "$LAND_STUB")"
  lland "$_land_delsplittok" "$LOSHA" control-plane "branch/land-delsplit"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q 'deletes a branch'; then
    echo "PASS: land NEGATIVE(x): a split-quote --del''ete-branch is refused (quote-strip reassembles)"
  else
    echo "FAIL: land NEGATIVE(x): want rc!=0 + no merge + 'deletes a branch', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−xi) --admin=false is now ALSO refused (F3-1, the disclosed over-refusal trade): a landing merge
  #        never needs --admin in ANY form, so the whole --admin=* class is refused rather than
  #        exact-matching only bare --admin (which had opened --admin=true). This INVERTS the old
  #        POSITIVE(exact-match) leg — the correct trade, owner-ruled: over-refusing a cosmetic no-op
  #        beats leaving a =value bypass open.
  mkorigin adminfalse
  rm -f "$LAND_MARK"
  lland "$LAND_STUB --admin=false" "$LOSHA" control-plane "branch/land-adminfalse"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q -- '--admin'; then
    echo "PASS: land NEGATIVE(xi): --admin=false is refused too (--admin=* class; disclosed over-refusal)"
  else
    echo "FAIL: land NEGATIVE(xi): want rc!=0 + no merge + '--admin' for --admin=false, got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−xii/N1) A BACKSLASH-ESCAPED \--admin is REFUSED by the shell-metachar-decline arm. The token
  #        quote-strip removes only ' and ", NOT the backslash — so \--admin survives word-splitting as
  #        the literal bytes \--admin, matches NO deny arm (\--admin is not --admin, not --*, not -*d*),
  #        and the eval'd shell strips the backslash so `gh` sees the bare --admin and MERGES. The
  #        metachar-decline arm refuses ANY --merge-cmd carrying a word-shape metacharacter before the
  #        token scan (the default merge-cmd needs none). merge-cmd = `<stub> \--admin`: the flag is a
  #        separate ARG so the leg asserts the backslash reason ONLY (no `;` chaining, which the widened
  #        set would itself trip); a missing marker proves land refused before eval.
  mkorigin bslashadmin
  rm -f "$LAND_MARK"
  _mc_bsl="$(printf '%s \\--admin' "$LAND_STUB")"
  lland "$_mc_bsl" "$LOSHA" control-plane "branch/land-bslashadmin"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q 'shell metacharacter'; then
    echo "PASS: land NEGATIVE(xii): a backslash-escaped \\--admin merge-cmd is refused (metachar-decline), no merge"
  else
    echo "FAIL: land NEGATIVE(xii): want rc!=0 + no merge + 'shell metacharacter', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−xiii/N1) A COMMAND-SUBSTITUTION --$(echo admin) is REFUSED by the metachar-decline arm ($). Without
  #        it the eval'd shell would expand $(echo admin) to `admin`, forming --admin at merge time — a
  #        spelling the static token scan cannot see. merge-cmd = `<stub> --$(echo admin)`; a missing
  #        marker proves refusal.
  mkorigin dolladmin
  rm -f "$LAND_MARK"
  _mc_dol="$(printf '%s --$(echo admin)' "$LAND_STUB")"
  lland "$_mc_dol" "$LOSHA" control-plane "branch/land-dolladmin"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q 'shell metacharacter'; then
    echo "PASS: land NEGATIVE(xiii): a --\$(echo admin) command-substitution merge-cmd is refused (metachar-decline), no merge"
  else
    echo "FAIL: land NEGATIVE(xiii): want rc!=0 + no merge + 'shell metacharacter', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−xiv/N1) A BACKSLASH-SPLIT --del\ete-branch is REFUSED by the metachar-decline arm (backslash).
  #        --del\ete-branch is not --delete* (the backslash breaks the literal 'delete' prefix) and the
  #        eval'd shell strips the backslash so `gh` sees --delete-branch. merge-cmd = `<stub>
  #        --del\ete-branch`; a missing marker proves refusal.
  mkorigin bsldel
  rm -f "$LAND_MARK"
  _mc_bsldel="$(printf '%s --del\\ete-branch' "$LAND_STUB")"
  lland "$_mc_bsldel" "$LOSHA" control-plane "branch/land-bsldel"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q 'shell metacharacter'; then
    echo "PASS: land NEGATIVE(xiv): a backslash-split --del\\ete-branch merge-cmd is refused (metachar-decline), no merge"
  else
    echo "FAIL: land NEGATIVE(xiv): want rc!=0 + no merge + 'shell metacharacter', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−xv/N3) A BRACE-EXPANSION --{admin,} is REFUSED by the metachar-decline arm ({ } ,). THIS IS THE
  #        REAL N3 GAP: the token scan's `--*` arm swallowed --{admin,} as an inert flag (not --admin,
  #        not --delete*), and the guard tier ALSO allowed it — yet the eval'd shell expands --{admin,}
  #        to the two words `--admin` and `--` (bash) / a set -f-inert single word land never lexes, so
  #        `gh` receives --admin. Widening step-3b to the guard's word-shape set ({ } , * ? [ …) closes
  #        it. merge-cmd = `<stub> --{admin,}`; a missing marker proves refusal before eval.
  mkorigin brace1
  rm -f "$LAND_MARK"
  lland "$LAND_STUB --{admin,}" "$LOSHA" control-plane "branch/land-brace1"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q 'shell metacharacter'; then
    echo "PASS: land NEGATIVE(xv): a brace-expansion --{admin,} merge-cmd is refused (metachar-decline), no merge"
  else
    echo "FAIL: land NEGATIVE(xv): want rc!=0 + no merge + 'shell metacharacter', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−xvi/N3) An INNER brace --ad{m,}in is REFUSED too ({ } ,): bash expands it to `--admin --adin`, so
  #        --admin rides in. Same word-shape decline; merge-cmd = `<stub> --ad{m,}in`.
  mkorigin brace2
  rm -f "$LAND_MARK"
  lland "$LAND_STUB --ad{m,}in" "$LOSHA" control-plane "branch/land-brace2"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q 'shell metacharacter'; then
    echo "PASS: land NEGATIVE(xvi): an inner-brace --ad{m,}in merge-cmd is refused (metachar-decline), no merge"
  else
    echo "FAIL: land NEGATIVE(xvi): want rc!=0 + no merge + 'shell metacharacter', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−xvii/N3) A GLOB --admi[n] is REFUSED ([). If a file named `--admin` exists in cwd the eval'd shell
  #        expands --admi[n] to it; the bracket also makes the token unmatchable to a literal scan.
  #        Refused ANYWHERE (not only leading) — the merge-cmd is one eval'd string. merge-cmd =
  #        `<stub> --admi[n]`.
  mkorigin glob1
  rm -f "$LAND_MARK"
  lland "$LAND_STUB --admi[n]" "$LOSHA" control-plane "branch/land-glob1"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q 'shell metacharacter'; then
    echo "PASS: land NEGATIVE(xvii): a glob --admi[n] merge-cmd is refused (metachar-decline), no merge"
  else
    echo "FAIL: land NEGATIVE(xvii): want rc!=0 + no merge + 'shell metacharacter', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−xviii/N3) A GLUED SEPARATOR --admin; is REFUSED (;): the token scan sees the single token
  #        `--admin;` (; is not IFS), which `--*` swallows as inert, but the eval'd shell treats `;` as a
  #        command terminator so `gh … --admin` runs as its own command. merge-cmd = `<stub> --admin;`.
  mkorigin semi1
  rm -f "$LAND_MARK"
  lland "$LAND_STUB --admin;" "$LOSHA" control-plane "branch/land-semi1"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q 'shell metacharacter'; then
    echo "PASS: land NEGATIVE(xviii): a glued-separator --admin; merge-cmd is refused (metachar-decline), no merge"
  else
    echo "FAIL: land NEGATIVE(xviii): want rc!=0 + no merge + 'shell metacharacter', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−xix/N3) A GLUED PIPE --admin|x is REFUSED (|): same inert-token blindness, but the shell pipes
  #        `gh … --admin` into `x`. merge-cmd = `<stub> --admin|x`.
  mkorigin pipe1
  rm -f "$LAND_MARK"
  lland "$LAND_STUB --admin|x" "$LOSHA" control-plane "branch/land-pipe1"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q 'shell metacharacter'; then
    echo "PASS: land NEGATIVE(xix): a glued-pipe --admin|x merge-cmd is refused (metachar-decline), no merge"
  else
    echo "FAIL: land NEGATIVE(xix): want rc!=0 + no merge + 'shell metacharacter', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−xx/N3) A GLUED REDIRECT --admin>x is REFUSED (>): the shell strips `>x` as a redirection so `gh …
  #        --admin` runs. merge-cmd = `<stub> --admin>x`.
  mkorigin redir1
  rm -f "$LAND_MARK"
  lland "$LAND_STUB --admin>x" "$LOSHA" control-plane "branch/land-redir1"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q 'shell metacharacter'; then
    echo "PASS: land NEGATIVE(xx): a glued-redirect --admin>x merge-cmd is refused (metachar-decline), no merge"
  else
    echo "FAIL: land NEGATIVE(xx): want rc!=0 + no merge + 'shell metacharacter', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # =====================================================================================
  # LAND A9 — the hygiene re-read (T2-land-a9-hygiene; design docs/architecture/2026-09-26-tbg-wire-
  # local-design.md §8, D-240919-2(7)). A9 is HYGIENE, not a control — it NEVER hard-blocks land on a
  # can't-read; it refuses ONLY when a fresh re-read shows the row has demonstrably LEFT the
  # in-flight states. Reference pattern: hooks/pre-push's `_seam_tracker_prepare` (T1, 73c7cbd) — the
  # same conf/origin resolution, fixed record path, injectable shape, reader rc contract; a BOUNDED,
  # INTENTIONAL duplication (the file set forbids a shared helper here).
  # =====================================================================================
  LAND_A9_LIB="$SCRIPT_DIR/backlog-lib.sh"
  [ -f "$LAND_A9_LIB" ] || { echo "FAIL: land A9 fixture — conformance/backlog-lib.sh not found at $LAND_A9_LIB"; st=1; }

  # a9_setup <name> [push-conf:yes|no (default yes)] -> a fresh origin+clone (mkorigin) whose base
  # commit declares CLAUDE.md "Backlog backend: jira" and carries a `Kit-Row: AB-9` trailer (amended,
  # force-pushed so ORIGIN's main also carries it — asha, LOSHA, is this commit). Copies the REAL
  # backlog-lib.sh onto disk (untracked — read as a plain file, never via git) and writes
  # .kit/tracker.conf onto disk; when push-conf=yes that conf is ALSO committed+pushed to origin/main
  # (a second commit; LOSHA/asha stays the earlier trailer commit) so the S-2 origin-pin fetch
  # succeeds — when push-conf=no it exists locally only, exercising the "no origin pin" fail-closed
  # branch.
  a9_setup() {
    _a9_push="${2:-yes}"
    mkorigin "$1"
    printf 'Backlog backend: jira\n' > "$LOA/CLAUDE.md"
    git -C "$LOA" add CLAUDE.md
    git -C "$LOA" commit -q --amend -m "$(printf 'base\n\nKit-Row: AB-9')"
    git -C "$LOA" push -q -f origin HEAD:refs/heads/main
    LOSHA="$(git -C "$LOA" rev-parse HEAD)"
    mkdir -p "$LOA/conformance"
    cp "$LAND_A9_LIB" "$LOA/conformance/backlog-lib.sh"
    mkdir -p "$LOA/.kit"
    printf 'version=1\nbackend=jira\nbase_url=https://example.atlassian.net\nflavour=cloud\nauth=basic\nproject=AB\nstate.in-progress=In Progress\n' \
      > "$LOA/.kit/tracker.conf"
    if [ "$_a9_push" = yes ]; then
      git -C "$LOA" add .kit/tracker.conf
      git -C "$LOA" commit -q -m "add tracker conf"
      git -C "$LOA" push -q origin HEAD:refs/heads/main
      # SWAS-323b: a serial land needs origin's main to be an ancestor of the approved head. The trailer-carrying commit is therefore
      # re-made ON TOP of the conf commit (not pushed): it is still the approved sha (LOSHA) and still not origin's tip, and origin's main
      # still carries the conf for the origin-pin fetch.
      git -C "$LOA" commit -q --allow-empty -m "$(printf 'head\n\nKit-Row: AB-9')"
      LOSHA="$(git -C "$LOA" rev-parse HEAD)"
    fi
  }
  # a9_setup_md <name> -> the same trailer-carrying commit, but NO CLAUDE.md at all (undeclared
  # backend — the same byte-identical path an `md` board takes; resolve_backend's own `[ -f "$_c" ]`
  # guard answers empty on either shape).
  a9_setup_md() {
    mkorigin "$1"
    git -C "$LOA" commit -q --amend -m "$(printf 'base\n\nKit-Row: AB-9')"
    git -C "$LOA" push -q -f origin HEAD:refs/heads/main
    LOSHA="$(git -C "$LOA" rev-parse HEAD)"
    mkdir -p "$LOA/conformance"
    cp "$LAND_A9_LIB" "$LOA/conformance/backlog-lib.sh"
  }
  # a9_setup_declared_md <name> -> the same trailer-carrying commit, but CLAUDE.md EXPLICITLY
  # declares the md backend (`- **Backlog backend**: md`) rather than omitting the field — the
  # DECLARED-md shape, as distinct from a9_setup_md's UNDECLARED (no CLAUDE.md at all) shape. Both
  # resolve to the same `case` arm in do_land's A9 block (the `md` token itself), but only this leg
  # proves the DECLARED path is exercised, not merely inferred from the undeclared one.
  a9_setup_declared_md() {
    mkorigin "$1"
    printf -- '- **Backlog backend**: md\n' > "$LOA/CLAUDE.md"
    git -C "$LOA" add CLAUDE.md
    git -C "$LOA" commit -q --amend -m "$(printf 'base\n\nKit-Row: AB-9')"
    git -C "$LOA" push -q -f origin HEAD:refs/heads/main
    LOSHA="$(git -C "$LOA" rev-parse HEAD)"
    mkdir -p "$LOA/conformance"
    cp "$LAND_A9_LIB" "$LOA/conformance/backlog-lib.sh"
  }
  # a9_reader <state> -> sets $_a9r_path to a stub script that touches "<path>.ran" (proving it ran)
  # and WRITES a bound §4.3 record (loop-state.sh's own fixture grammar) with `row AB-9 state=<state>`
  # to whatever record path do_land passes it — offline, no credential, no network.
  a9_reader() {
    _a9r_state="$1"; _a9r_path="$D/land-a9-reader-$_a9r_state"
    cat > "$_a9r_path" <<EOF
#!/bin/sh
touch "$_a9r_path.ran"
_pin=\$( { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } < "\$1" | awk '{print \$1}')
{
  echo "kit-tracker-read 1"
  echo "backend jira"
  echo "pin sha256:\$_pin"
  echo "head \$5"
  echo "requested \$4"
  echo "read-day \$(date -u +%Y-%m-%d)"
  echo "credential ok"
  echo "verdict bound"
  echo "row \$4 state=$_a9r_state"
} > "\$3"
exit 0
EOF
    chmod +x "$_a9r_path"
  }
  # a9_reader_fail <rc> -> sets $_a9rf_path to a stub that touches its own ".ran" marker (so a leg can
  # prove whether it was invoked at all) and exits <rc> WITHOUT writing any record.
  a9_reader_fail() {
    _a9rf_path="$D/land-a9-reader-fail-$1"
    cat > "$_a9rf_path" <<EOF
#!/bin/sh
touch "$_a9rf_path.ran"
exit $1
EOF
    chmod +x "$_a9rf_path"
  }
  # a9_reader_badbind <tag> -> sets $_a9rb_path to a stub that touches its own ".ran" marker, EXITS 0
  # (a successful read), but writes a record whose `requested` id does NOT match the caller's row
  # (\$4) — `_seam_tracker_answer`'s own requested==caller-id check (backlog-lib.sh) then refuses,
  # so `seam_row_state` returns rc2 (UNVERIFIED, can't bind) even though the READER itself succeeded.
  # This is the "reader rc0 but seam can't bind" branch (do_land, ~:1463-1477): hygiene never
  # hard-blocks on a non-answer, so land must still PROCEED and the reader must still show as run.
  a9_reader_badbind() {
    _a9rb_path="$D/land-a9-reader-badbind-$1"
    cat > "$_a9rb_path" <<EOF
#!/bin/sh
touch "$_a9rb_path.ran"
_pin=\$( { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } < "\$1" | awk '{print \$1}')
{
  echo "kit-tracker-read 1"
  echo "backend jira"
  echo "pin sha256:\$_pin"
  echo "head \$5"
  echo "requested NOT-\$4"
  echo "read-day \$(date -u +%Y-%m-%d)"
  echo "credential ok"
  echo "verdict bound"
  echo "row \$4 state=in-review"
} > "\$3"
exit 0
EOF
    chmod +x "$_a9rb_path"
  }

  # (1) REFUSE-HYGIENE ANCHOR: a fresh re-read shows the landing row has LEFT the in-flight states
  #     (now `done`) -> LAND REFUSED, labelled HYGIENE, the merge does NOT run.
  a9_setup a9-refuse
  a9_reader "done"
  rm -f "$LAND_MARK"
  export LAND_TRACKER_READER="sh $_a9r_path"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/land-a9-refuse"
  unset LAND_TRACKER_READER
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && [ -f "$_a9r_path.ran" ] \
      && printf '%s' "$_ld_out" | grep -qi 'HYGIENE'; then
    echo "PASS: land A9(1): a fresh re-read showing the row left in-flight (done) REFUSES, labelled HYGIENE, no merge"
  else
    echo "FAIL: land A9(1): want rc!=0 + no merge + HYGIENE + reader invoked, got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ) ran=$( [ -f "$_a9r_path.ran" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (2) PROCEED NEGATIVE: still in-flight (`in-review`) -> do_land does NOT refuse at A9, the merge
  #     runs and the note lands on origin exactly as it would have before this leg existed.
  a9_setup a9-proceed
  a9_reader in-review
  rm -f "$LAND_MARK"
  export LAND_TRACKER_READER="sh $_a9r_path"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/land-a9-proceed"
  unset LAND_TRACKER_READER
  if [ "$_ldc" = 0 ] && [ -f "$LAND_MARK" ] && [ -f "$_a9r_path.ran" ] && onote "$LOSHA"; then
    echo "PASS: land A9(2): a fresh re-read showing the row STILL in-flight (in-review) proceeds — merge ran"
  else
    echo "FAIL: land A9(2): want rc=0 + merge + reader invoked + note-on-origin, got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ) ran=$( [ -f "$_a9r_path.ran" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (3a) CAN'T-READ, NO ORIGIN PIN: a recognised backend with a LOCAL tracker.conf but no copy on
  #      origin/main -> N/A, land PROCEEDS, and the reader is NEVER invoked (S-2 fail-closed: the
  #      token is not sent when there is nothing to pin-compare against).
  a9_setup a9-noorigin no
  a9_reader_fail 91
  rm -f "$LAND_MARK"
  export LAND_TRACKER_READER="sh $_a9rf_path"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/land-a9-noorigin"
  unset LAND_TRACKER_READER
  if [ "$_ldc" = 0 ] && [ -f "$LAND_MARK" ] && onote "$LOSHA" && [ ! -f "$_a9rf_path.ran" ]; then
    echo "PASS: land A9(3a): no origin tracker.conf to pin against -> N/A, land proceeds, reader NEVER invoked"
  else
    echo "FAIL: land A9(3a): want rc=0 + merge + note-on-origin + reader NOT invoked, got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ) ran=$( [ -f "$_a9rf_path.ran" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (3b) CAN'T-READ, READER REFUSAL/UNVERIFIED: the origin pin exists, but the reader itself cannot
  #      verify (no token / no adapter, rc!=0) -> N/A, land still PROCEEDS (hygiene never hard-blocks
  #      on a non-answer).
  a9_setup a9-cantread yes
  a9_reader_fail 92
  rm -f "$LAND_MARK"
  export LAND_TRACKER_READER="sh $_a9rf_path"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/land-a9-cantread"
  unset LAND_TRACKER_READER
  if [ "$_ldc" = 0 ] && [ -f "$LAND_MARK" ] && onote "$LOSHA" && [ -f "$_a9rf_path.ran" ]; then
    echo "PASS: land A9(3b): reader rc!=0 (unverified/no-adapter) -> N/A, land proceeds"
  else
    echo "FAIL: land A9(3b): want rc=0 + merge + note-on-origin + reader invoked, got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ) ran=$( [ -f "$_a9rf_path.ran" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (4) MD/UNDECLARED BYTE-IDENTICAL: no CLAUDE.md at all (the same shape an `md` board takes) ->
  #     the reader is NEVER invoked, land behaves exactly as it did before this leg existed.
  a9_setup_md a9-md
  a9_reader_fail 94
  rm -f "$LAND_MARK"
  export LAND_TRACKER_READER="sh $_a9rf_path"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/land-a9-md"
  unset LAND_TRACKER_READER
  if [ "$_ldc" = 0 ] && [ -f "$LAND_MARK" ] && onote "$LOSHA" && [ ! -f "$_a9rf_path.ran" ]; then
    echo "PASS: land A9(4): md/undeclared backend is byte-identical — the reader is NEVER invoked"
  else
    echo "FAIL: land A9(4): want rc=0 + merge + note-on-origin + reader NOT invoked, got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ) ran=$( [ -f "$_a9rf_path.ran" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (4b) DECLARED-MD BYTE-IDENTICAL: CLAUDE.md EXPLICITLY declares `Backlog backend: md` (rather
  #      than omitting the field, as leg (4) does) -> the same `md` arm, the reader is NEVER
  #      invoked, land proceeds exactly as it always has.
  a9_setup_declared_md a9-md-declared
  a9_reader_fail 95
  rm -f "$LAND_MARK"
  export LAND_TRACKER_READER="sh $_a9rf_path"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/land-a9-md-declared"
  unset LAND_TRACKER_READER
  if [ "$_ldc" = 0 ] && [ -f "$LAND_MARK" ] && onote "$LOSHA" && [ ! -f "$_a9rf_path.ran" ]; then
    echo "PASS: land A9(4b): an EXPLICITLY declared md backend is a no-op — the reader is NEVER invoked"
  else
    echo "FAIL: land A9(4b): want rc=0 + merge + note-on-origin + reader NOT invoked, got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ) ran=$( [ -f "$_a9rf_path.ran" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (5) READER RC0 BUT SEAM CAN'T BIND: the reader itself succeeds (rc0, writes a record), but the
  #     record's `requested` id does not match the landing row, so `seam_row_state` refuses (rc2,
  #     UNVERIFIED — `_seam_tracker_answer`'s requested==caller-id check). This is the
  #     `_land_srsrc != 0` (non-answer) proceed branch (do_land, ~:1463-1477), distinct from leg
  #     (3b)'s reader-level failure: HERE the reader ran and answered, but the ANSWER can't bind.
  #     Hygiene never hard-blocks on a non-answer -> land still PROCEEDS, and the reader shows as run.
  a9_setup a9-cantbind yes
  a9_reader_badbind a9-cantbind
  rm -f "$LAND_MARK"
  export LAND_TRACKER_READER="sh $_a9rb_path"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/land-a9-cantbind"
  unset LAND_TRACKER_READER
  if [ "$_ldc" = 0 ] && [ -f "$LAND_MARK" ] && onote "$LOSHA" && [ -f "$_a9rb_path.ran" ]; then
    echo "PASS: land A9(5): reader rc0 but the record can't bind (requested id mismatch) -> N/A, land proceeds, reader ran"
  else
    echo "FAIL: land A9(5): want rc=0 + merge + note-on-origin + reader invoked, got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ) ran=$( [ -f "$_a9rb_path.ran" ] && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # =====================================================================================
  # F3-2 — land is the CP/direct-path verb + inherits do_actuate's SoD (owner-ruled 2026-09-10).
  #   * land REFUSES --class ordinary|sensitive (→ actuate, which carries the forge-review label bar
  #     + SoD for those classes); proceeds ONLY for control-plane; refuses unknown/missing (allowlist).
  #   * land inherits do_actuate's SoD drift-control for its CP path: after the on-origin note confirm
  #     and before the merge, refuse if the approver is empty OR equals the author of --approved-sha.
  #   The liveness leg above already proves the POSITIVE — land PROCEEDS for control-plane when the
  #   approver ('solo maintainer') != the author ('t') — so it is not repeated here.
  # =====================================================================================

  # (−ord) land refuses --class ordinary → actuate. Refused BEFORE record runs, so no note is written
  #        and the stub merge must NOT run.
  mkorigin ord
  rm -f "$LAND_MARK"
  lland "$LAND_STUB" "$LOSHA" ordinary "branch/land-ord"
  if [ "$_ldc" != 0 ] && [ "$_ldc" != 3 ] && [ ! -f "$LAND_MARK" ] && ! onote "$LOSHA" && printf '%s' "$_ld_out" | grep -q 'actuate'; then
    echo "PASS: land NEGATIVE(ord): --class ordinary is refused (-> actuate), no record, no merge, and the rc is not 3 (3 means merged with a tree mismatch)"
  else
    echo "FAIL: land NEGATIVE(ord): want rc!=0 + no merge + no note + 'actuate', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ) note=$( onote "$LOSHA" && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−sens) land refuses --class sensitive → actuate too (same non-CP class family).
  mkorigin sens
  rm -f "$LAND_MARK"
  lland "$LAND_STUB" "$LOSHA" sensitive "branch/land-sens"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && ! onote "$LOSHA" && printf '%s' "$_ld_out" | grep -q 'actuate'; then
    echo "PASS: land NEGATIVE(sens): --class sensitive is refused (-> actuate), no record, no merge"
  else
    echo "FAIL: land NEGATIVE(sens): want rc!=0 + no merge + no note + 'actuate', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ) note=$( onote "$LOSHA" && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−unknown-class) an unrecognised class ('bogus') is refused ALLOWLIST-style — land proceeds only
  #        for control-plane; an unjudgeable class is never a permission. Refused BEFORE record, no
  #        note, no merge. (Land's class gate now intercepts a bad class that record used to red.)
  mkorigin ucls
  rm -f "$LAND_MARK"
  lland "$LAND_STUB" "$LOSHA" bogus "branch/land-ucls"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && ! onote "$LOSHA" && printf '%s' "$_ld_out" | grep -q 'allowlist'; then
    echo "PASS: land NEGATIVE(unknown-class): an unrecognised class is refused (allowlist), no record, no merge"
  else
    echo "FAIL: land NEGATIVE(unknown-class): want rc!=0 + no merge + no note + 'allowlist', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ) note=$( onote "$LOSHA" && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−sod) SoD: approver == author of the approved commit is REFUSED (builder != ratifier), BEFORE
  #        record runs — so a self-approval NEVER publishes a GO note on origin (N2: the check used to
  #        sit AFTER record+the on-origin confirm, so every SoD refusal left a PUBLISHED self-approved
  #        note the recordless-merge backstop trusts). The mkorigin base commit is authored by 't'; a
  #        trailing --approved-by t makes approver == author (last-wins in both land's peek and record).
  #        Assert NO note reached origin (! onote) AND the stub merge did NOT run.
  mkorigin sod
  rm -f "$LAND_MARK"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/land-sod" --approved-by t
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && ! onote "$LOSHA" && printf '%s' "$_ld_out" | grep -q 'builder != ratifier'; then
    echo "PASS: land NEGATIVE(sod): approver == author is refused (SoD) BEFORE record — no note on origin, no merge"
  else
    echo "FAIL: land NEGATIVE(sod): want rc!=0 + no merge + no note + 'builder != ratifier', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ) note=$( onote "$LOSHA" && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−sod-pad) SoD normalizes the approver like do_actuate: a padded --approved-by 't ' (trailing
  #        whitespace) is stripped to 't', which equals the author, so it is REFUSED (N2: land used to
  #        compare the RAW approver, so 't ' slipped past land's SoD though actuate — which strips
  #        whitespace before comparing — would refuse the note it writes). Refused BEFORE record too:
  #        no note, no merge.
  mkorigin sodpad
  rm -f "$LAND_MARK"
  lland "$LAND_STUB" "$LOSHA" control-plane "branch/land-sodpad" --approved-by "t "
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && ! onote "$LOSHA" && printf '%s' "$_ld_out" | grep -q 'builder != ratifier'; then
    echo "PASS: land NEGATIVE(sod-pad): a padded approver 't ' normalizes to the author and is refused (SoD) — no note, no merge"
  else
    echo "FAIL: land NEGATIVE(sod-pad): want rc!=0 + no merge + no note + 'builder != ratifier', got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ) note=$( onote "$LOSHA" && echo yes || echo no ); out=$_ld_out"; st=1
  fi

  # (−vi/+) POST-RUN RECOVERY: after a successful land whose stub actually squash-merges the feature
  #         into the trunk, `trace --recent 1` reads the trunk head bound to the GO note land wrote —
  #         the AC's proof that a merge actuated by this verb is recoverable, done POSITIVELY, over a
  #         real origin.
  mkorigin landtrace
  ( cd "$LOA" && git checkout -q -b landfeat \
      && printf 'land\n' > landfile.txt && git add landfile.txt \
      && printf 'land-verb head\n\nKit-Row: LAND-ROW-9\nKit-Class: control-plane\n' | git commit -q -F - ) \
    || { echo "FAIL: could not build the land feature fixture"; st=1; }
  LANDC="$( ( cd "$LOA" && git rev-parse landfeat ) )"
  # The merge itself needs `&&` and a `>` redirect, which the widened step-3b would refuse in a
  # merge-cmd string. Bake the real squash-merge into a STANDALONE stub and pass its path as the
  # one-word merge-cmd — the operators live INSIDE the script the shell runs, not in the eval'd string.
  LAND_TRACE_STUB="$D/land-trace-stub"
  printf '#!/bin/sh\ncd %s && git checkout -q %s && git merge --squash landfeat >/dev/null 2>&1 && git commit -qm %s\n' \
    "'$LOA'" "$LOTRUNK" "'squash-merge landfeat (land verb)'" > "$LAND_TRACE_STUB"
  chmod +x "$LAND_TRACE_STUB"
  lland "$LAND_TRACE_STUB" "$LANDC" control-plane "branch/landfeat"
  LANDTIP="$( ( cd "$LOA" && git rev-parse HEAD ) )"
  if [ "$_ldc" = 0 ] \
     && ( cd "$LOA" && PROMOTION_NOTES_REF="$LR2" $VSH "$VERIFY" trace --recent 1 --from "$LANDTIP" >/dev/null 2>&1 ); then
    echo "PASS: land + trace: a merge landed by land is recoverable — trace --recent binds the trunk head"
  else
    echo "FAIL: land + trace: rc=$_ldc, trace --recent 1 did not bind the trunk head $LANDTIP; out=$_ld_out"; st=1
  fi
  # =====================================================================================
  # RUNAWAY-METERING-LANDING-GATE T2 — `land` consults the per-slice meter (runaway-guard.sh meter)
  # behind the RUNAWAY_METERING_GATE dial, AFTER SoD and BEFORE record. LOAD-BEARING NEGATIVES: a refusal
  # writes NO note (checked on ORIGIN) and attempts NO merge (the stub would leave a marker). The dial is
  # read from the APPROVED tree (git show <sha>:.kit/dials.conf), never the working tree; env may only
  # escalate. Owner ruling F3 = Option A: a breached row PROCEEDS with a loud STOP line.
  # EVERY leg sandboxes the tally through a temp HOME (never the real $HOME, never the override env as
  # isolation) and runs the gate from a KIT LAYOUT COPY (scripts/ + .kit/budget.conf + conformance/) so
  # a leg can remove the classifier or the guard. The fixture origin is built from scratch (mkorigin), so
  # the legs need nothing from the repo they run in (they pass in a --depth 1 clone).
  # =====================================================================================
  MG_ROOT="$D/mg"; mkdir -p "$MG_ROOT"
  MG_SRC="$(cd "$(dirname "$VERIFY")" && pwd)"
  MG_ENVX=""
  # mg_layout <dir> [noclassifier|noguard] — a copy of the kit layout the gate resolves its siblings from.
  mg_layout() {
    _mgk="$1"; _mgv="${2:-}"
    rm -rf "$_mgk"; mkdir -p "$_mgk/scripts" "$_mgk/.kit" "$_mgk/conformance"
    cp "$VERIFY" "$_mgk/scripts/promotion-verify.sh"
    cp "$MG_SRC/../.kit/budget.conf" "$_mgk/.kit/budget.conf"
    printf '#!/bin/sh\nexit 0\n' > "$_mgk/scripts/board-claim.sh"
    if [ "$_mgv" = stubrc7 ]; then printf '#!/bin/sh\nexit 7\n' > "$_mgk/scripts/runaway-guard.sh"   # present, but exits an rc the gate has no named arm for
    elif [ "$_mgv" != noguard ]; then cp "$MG_SRC/runaway-guard.sh" "$_mgk/scripts/runaway-guard.sh"; fi
    [ "$_mgv" = noclassifier ] || cp "$MG_SRC/../conformance/ci-classify-changes.sh" "$_mgk/conformance/ci-classify-changes.sh"
  }
  MG_KIT="$MG_ROOT/kit"; mg_layout "$MG_KIT"
  MG_K="$MG_KIT"
  mg_put_dial() {   # writes the dial into the CURRENT tree (cwd) and stages it
    if [ "$_mgdial" = DIRLINK ]; then   # `.kit` ITSELF a 120000 symlink to a dir whose dials.conf says enforce
      rm -rf .kit kitreal; mkdir kitreal; printf 'RUNAWAY_METERING_GATE=enforce\n' > kitreal/dials.conf
      ln -s kitreal .kit; git add kitreal .kit; return 0
    fi
    if [ "$_mgdial" = GITLINK ]; then   # `.kit` a 160000 gitlink entry
      rm -rf .kit; git update-index --add --cacheinfo 160000,0123456789abcdef0123456789abcdef01234567,.kit; return 0
    fi
    mkdir -p .kit
    if [ "$_mgdial" = LINK ]; then
      printf 'RUNAWAY_METERING_GATE=enforce\n' > .kit/elsewhere.conf
      ln -s elsewhere.conf .kit/dials.conf
    else
      printf '%s\n' "$_mgdial" > .kit/dials.conf
    fi
    git add .kit
  }
  # mg_fx <name> <dial: NONE|LINK|<conf line>> <row: NONE|(none)|ROW> <kind: code|docs|rename> [feat|base]
  # -> a bare origin whose main carries x.sh (and the dial when `base`), plus a feature branch whose
  # head is $MG_ASHA. `docs`/`rename` change only a .md path / rename x.sh -> docs/x.md.
  mg_fx() {
    mkorigin "mg-$1"
    fx_layout "$LOA" 0 0   # the gate runs from a kit-layout COPY with no gate-state facts (an adopter's reading), so the repository it runs in reads adopter too
    _mgdial="$2"; _mgrow="$3"; _mgkind="$4"; _mgwhere="${5:-feat}"
    (
      set -e; cd "$LOA"
      printf '#!/bin/sh\n:\n' > x.sh; git add x.sh
      if [ "$_mgwhere" = base ] && [ "$_mgdial" != NONE ]; then mg_put_dial; fi
      git commit -qm base2; git push -q origin HEAD:refs/heads/main
      git checkout -q -b mgfeat
      [ -z "${MG_AUTHNAME:-}" ] || export GIT_AUTHOR_NAME="$MG_AUTHNAME"   # a leg may name the feature commit's author
      if [ "$_mgwhere" = feat ] && [ "$_mgdial" != NONE ]; then mg_put_dial; fi
      case "$_mgkind" in
        code)   printf 'c\n' > code.sh; git add code.sh ;;
        docs)   mkdir -p docs; printf 'hi\n' > docs/x.md; git add docs ;;
        rename) mkdir -p docs; git mv x.sh docs/x.md ;;
        codedocs) printf 'c\n' > code.sh; git add code.sh; git commit -qm codepart
                  mkdir -p docs; printf 'hi\n' > docs/x.md; git add docs ;;
      esac
      if [ "$_mgrow" = NONE ]; then printf 'mg feature\n\nKit-Class: control-plane\n' | git commit -q -F -
      else printf 'mg feature\n\nKit-Row: %s\nKit-Class: control-plane\n' "$_mgrow" | git commit -q -F -; fi
    ) || { echo "FAIL: could not build the metering-gate fixture $1"; st=1; }
    MG_ASHA="$(git -C "$LOA" rev-parse HEAD)"
    MG_H="$MG_ROOT/h-$1"; mkdir -p "$MG_H"
  }
  # mg_seed <row> <tokens> <agents> — a tally line for the fixture repo in the leg's temp HOME.
  mg_seed() {
    _mgkey="$(git -C "$LOA" rev-list --max-parents=0 --first-parent HEAD | tail -1)"
    mkdir -p "$MG_H/.local/state/sparkwright/runaway/$_mgkey"
    printf '1757900000 keyA %s %s %s\n' "$1" "$2" "$3" >> "$MG_H/.local/state/sparkwright/runaway/$_mgkey/tally.v2"
  }
  # mg_poison <row> — a tally the guard cannot read (rc 2). SWAS-302 (Q2 A2) dropped the unmetered-row refusal, so
  # the legs that proved the dial is read from the APPROVED tree (and the docs-only exemption) by a refusal now
  # take that refusal from this unreadable tally, which enforce still refuses.
  mg_poison() {
    mg_seed "$1" 1 1
    printf 'this line is not the tally grammar\n' >> "$MG_H/.local/state/sparkwright/runaway/$_mgkey/tally.v2"
  }
  # mg_land -> runs land from the fixture clone; the ambient redirection/dial env is scrubbed, $MG_ENVX re-adds a leg's own.
  mg_land() {
    rm -f "$LAND_MARK"
    _mgh="$(lgh "$MG_ASHA" "${MG_ABY:-solo maintainer}")"   # the authenticated non-author approval the CP bar needs
    if _ld_out="$( cd "$LOA/${MG_SUB:-}" && env -u KIT_RUNAWAY_SANDBOX -u RUNAWAY_TALLY -u RUNAWAY_BUDGET_CONFIG -u RUNAWAY_METERING_GATE \
          HOME="$MG_H" $MG_ENVX PATH="$_mgh:$PATH" PROMOTION_NOTES_REF="$LR2" $VSH "$MG_K/scripts/promotion-verify.sh" land \
          --ref 77 --merge-cmd "$LAND_STUB" --approved-sha "$MG_ASHA" --approved-by "${MG_ABY:-solo maintainer}" \
          --go-by "the owner" --gate release-candidate --rung rc --class control-plane \
          --scope "PR #77" --token "GO: land mg" 2>&1 )"; then _ldc=0; else _ldc=$?; fi
  }
  # mg_check <label> <proceed|refuse> <needle>... (a leading ! = must NOT appear)
  mg_check() {
    _mgl="$1"; _mgw="$2"; shift 2; _mgbad=""
    if [ "$_mgw" = proceed ]; then
      { [ "$_ldc" = 0 ] && [ -f "$LAND_MARK" ] && onote "$MG_ASHA"; } \
        || _mgbad="want rc 0 + merge + note on origin, got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no )"
    else
      { [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && ! onote "$MG_ASHA"; } \
        || _mgbad="want a refusal + NO merge + NO note on origin, got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ) note=$( onote "$MG_ASHA" && echo yes || echo no )"
    fi
    for _mgn in "$@"; do
      case "$_mgn" in
        '!'*) _mgn="${_mgn#!}"; if printf '%s' "$_ld_out" | grep -qF -- "$_mgn"; then _mgbad="$_mgbad; unexpected '$_mgn'"; fi ;;
        *)    printf '%s' "$_ld_out" | grep -qF -- "$_mgn" || _mgbad="$_mgbad; missing '$_mgn'" ;;
      esac
    done
    if [ -z "$_mgbad" ]; then echo "PASS: $_mgl [$VSH]"; else echo "FAIL: $_mgl [$VSH] — $_mgbad; out=$_ld_out"; st=1; fi
  }
  MG_DIAL_ENF='RUNAWAY_METERING_GATE=enforce'
  MG_DIAL_OBS='RUNAWAY_METERING_GATE=observe'

  # The legs run under the producer shell this run was given ($VSH) AND under dash explicitly when the
  # host has it (the A5 class: dash's echo expands \0NNN and its patterns differ) — so a plain
  # `sh conformance/promotion-verify-wired.sh --selftest` on macOS still proves the gate under dash.
  mg_legs() {
  # SWAS-302 Q2-A2 (owner: "2 A2"): the dial stays at enforce, and ONLY the refusal of a row with no meter line is
  # dropped. A row the conductor never metered lands (the unmetered line is a note, not a gate); a missing Kit-Row
  # and an absent guard STILL refuse, and a poisoned tally (rc 2) still refuses (the tests above and below).
  mg_fx a2unm "$MG_DIAL_ENF" ROW-A2U code; mg_land
  mg_check "land METER(A2, enforce, unmetered): PROCEEDS (merge + note), prints the unmetered line, names no step remedy" proceed \
    "unmetered: ROW-A2U" "!LAND REFUSED" "!step --row" "!never estimate"
  mg_fx a2norow "$MG_DIAL_ENF" NONE code; mg_land
  mg_check "land METER(A2 keeps, enforce, no Kit-Row): STILL refused — cannot meter an unnamed row" refuse "LAND REFUSED (metering gate)" "unnamed row"
  mg_fx a2nog "$MG_DIAL_ENF" ROW-A2G code; mg_layout "$MG_ROOT/kit-a2nog" noguard; MG_K="$MG_ROOT/kit-a2nog"; mg_land; MG_K="$MG_KIT"
  mg_check "land METER(A2 keeps, enforce, guard absent): STILL refused, naming the absence" refuse "LAND REFUSED (metering gate)" "the runaway guard script is absent (<path elided>)"

  mg_fx enfmet "$MG_DIAL_ENF" ROW-MG2 code; mg_seed ROW-MG2 100 2; mg_land
  mg_check "land METER(enforce, metered): proceeds and prints the meter line" proceed "metered: ROW-MG2 tokens(100/"

  mg_fx enfrc2 "$MG_DIAL_ENF" ROW-MG3 code; mg_seed ROW-MG3 100 2
  printf 'this line is not the tally grammar\n' >> "$MG_H/.local/state/sparkwright/runaway/$_mgkey/tally.v2"; mg_land
  mg_check "land METER(enforce, rc 2 poisoned tally): refused (fail-closed), no note, no merge" refuse "LAND REFUSED (metering gate)" "guard rc 2" "\$HOME…" "!$MG_H"

  mg_fx enfbr "$MG_DIAL_ENF" ROW-MG4 code; mg_seed ROW-MG4 999999999999 1; mg_land
  mg_check "land METER(enforce, breached, F3 Option A): PROCEEDS with the loud STOP line" proceed \
    "STOP: ROW-MG4 tokens(" "ceiling breached (landed anyway: approved)"
  if [ "$(printf '%s\n' "$_ld_out" | grep -c 'STOP: ROW-MG4')" -ge 2 ]; then
    echo "PASS: land METER(breached): the STOP line is repeated in the landing report (stderr at the gate, stdout summary)"
  else echo "FAIL: land METER(breached): the STOP line appears fewer than twice; out=$_ld_out"; st=1; fi

  mg_fx obsun "$MG_DIAL_OBS" ROW-MG5 code; mg_land
  mg_check "land METER(observe, unmetered): proceeds with the one line" proceed "unmetered: ROW-MG5 (observe — not gating)"

  mg_fx absent NONE ROW-MG6 code; mg_land
  mg_check "land METER(dial absent): silent — proceeds and prints nothing about the meter" proceed \
    "!metered" "!N/A: docs-only" "!metering gate" "!runaway"

  mg_fx docs "$MG_DIAL_ENF" ROW-MG7 docs base; mg_land
  mg_check "land METER(docs-only, enforce, unmetered): N/A — proceeds" proceed "N/A: docs-only change"

  mg_fx rename "$MG_DIAL_ENF" ROW-MG8 rename base; mg_poison ROW-MG8; mg_land
  mg_check "land METER(a .sh -> .md rename is NOT docs-only): refused in enforce" refuse "LAND REFUSED (metering gate)" "!N/A: docs-only"

  mg_fx nobase "$MG_DIAL_ENF" ROW-MG9 docs base; mg_poison ROW-MG9
  git -C "$LOA" remote set-url origin "$MG_ROOT/no-such-origin"; mg_land
  mg_check "land METER(remote unreachable -> no docs-only base): NOT docs-only — refused in enforce, says the base is unreadable (fix2 B)" refuse "LAND REFUSED (metering gate)" "!N/A: docs-only" \
    "docs-only exemption unavailable: cannot read origin's main"

  # fix round 1 (security HIGH): the dial read is FULL-TREE — from a SUBDIRECTORY the gate still reads the root .kit/dials.conf.
  mg_fx subdir "$MG_DIAL_ENF" ROW-MG21 code; mg_poison ROW-MG21; mkdir -p "$LOA/sub"; MG_SUB=sub; mg_land; MG_SUB=""
  mg_check "land METER(fix1 A): enforce + unreadable tally invoked from a SUBDIRECTORY -> still refused" refuse "LAND REFUSED (metering gate)" "guard rc 2"

  # fix round 1 (security MEDIUM): a refs/replace ref pointing the approved sha at a commit whose dial says observe must not de-escalate.
  mg_fx replace "$MG_DIAL_ENF" ROW-MG22 code; mg_poison ROW-MG22
  ( set -e; cd "$LOA"; git checkout -q -b crafted; printf 'RUNAWAY_METERING_GATE=observe\n' > .kit/dials.conf; git add .kit
    printf 'crafted\n\nKit-Row: ROW-MG22\nKit-Class: control-plane\n' | git commit -q -F -
    git replace -f "$MG_ASHA" "$(git rev-parse HEAD)"; git checkout -q mgfeat ) || { echo "FAIL: could not build the replace-ref fixture"; st=1; }
  mg_land
  mg_check "land METER(fix1 B): a replace ref redirecting the approved sha to an observe tree does NOT de-escalate -> refused" refuse "LAND REFUSED (metering gate)"

  # fix round 1 (security MEDIUM): the docs-only base is the REMOTE's main, not the local origin/main ref an agent can move.
  mg_fx movedbase "$MG_DIAL_ENF" ROW-MG23 codedocs base; mg_poison ROW-MG23
  git -C "$LOA" update-ref refs/remotes/origin/main "${MG_ASHA}^"; mg_land
  mg_check "land METER(fix1 C): a code+docs change with the LOCAL origin/main moved to the approved parent is NOT docs-only -> refused" refuse "LAND REFUSED (metering gate)" "!N/A: docs-only" "!docs-only exemption unavailable"

  # SWAS-245: ls-remote tail-matches and sorts, so a pushed a/refs/heads/main must not stand in for main.
  mg_fx decoyneg "$MG_DIAL_ENF" ROW-MG25 codedocs base; mg_poison ROW-MG25
  git -C "$LOA" push -q origin "${MG_ASHA}^:refs/heads/a/refs/heads/main"; mg_land
  mg_check "land METER(SWAS-245 MG25): a decoy branch a/refs/heads/main at the approved parent does NOT make a code+docs change docs-only -> refused" refuse "LAND REFUSED (metering gate)" "!N/A: docs-only"
  mg_fx decoypos "$MG_DIAL_ENF" ROW-MG26 docs base
  git -C "$LOA" push -q origin "$LOSHA:refs/heads/a/refs/heads/main"; mg_land
  mg_check "land METER(SWAS-245 MG26): a genuinely docs-only change with a decoy branch present reads the REAL main -> N/A, proceeds" proceed "N/A: docs-only change"

  # fix round 1 (security LOW): an approved sha that does not resolve cannot have its dial read -> the gate refuses
  # (env enforce; otherwise it stays silent and `record` refuses it — the existing NEGATIVE(i) is kept unchanged).
  mg_fx unres "$MG_DIAL_OBS" ROW-MG24 code
  _mg_real="$MG_ASHA"; MG_ASHA="0123456789abcdef0123456789abcdef01234567"; MG_ENVX="RUNAWAY_METERING_GATE=enforce"; mg_land; MG_ENVX=""
  _mg_out_unres="$_ld_out"; _mg_rc_unres="$_ldc"; MG_ASHA="$_mg_real"
  # ACTUATE-SOD-EMPTY-AUTHOR: SoD now speaks first (it cannot compare an unreadable author), so even in enforce the
  # refusal is the SoD reason, before the gate and before record. The gate's unresolvable-sha branch is a belt.
  if [ "$_mg_rc_unres" != 0 ] && printf '%s' "$_mg_out_unres" | grep -qF "is not in this clone — SoD cannot compare the approver to its author" \
     && ! printf '%s' "$_mg_out_unres" | grep -qF "(metering gate)" && [ ! -f "$LAND_MARK" ] && ! onote "$_mg_real"; then
    echo "PASS: land METER(fix1 D): an unresolvable approved sha is refused by SoD (before the gate), no merge, no note [$VSH]"
  else echo "FAIL: land METER(fix1 D): want a SoD refusal naming 'is not in this clone'; rc=$_mg_rc_unres out=$_mg_out_unres"; st=1; fi

  # SODEA-L1: an --approved-sha absent from the clone, dial in OBSERVE -> refused BY SoD with the new reason (not by
  # `record`), with the fetch remedy, and NO note on origin, NO merge.
  mg_fx sodl1 "$MG_DIAL_OBS" ROW-SL1 code
  _sl1_real="$MG_ASHA"; MG_ASHA="0123456789abcdef0123456789abcdef01234567"; mg_land; MG_ASHA="$_sl1_real"
  if [ "$_ldc" != 0 ] && printf '%s' "$_ld_out" | grep -qF "LAND REFUSED: the approved commit 0123456789abcdef0123456789abcdef01234567 is not in this clone" \
     && printf '%s' "$_ld_out" | grep -qF "git fetch origin" && ! printf '%s' "$_ld_out" | grep -qF "will not merge" \
     && [ ! -f "$LAND_MARK" ] && ! onote "0123456789abcdef0123456789abcdef01234567" && ! onote "$MG_ASHA"; then
    echo "PASS: SODEA-L1: land, unresolvable --approved-sha, observe -> refused by SoD with the fetch remedy (not by record); no note, no merge [$VSH]"
  else echo "FAIL: SODEA-L1: want the SoD reason + git fetch origin, no note, no merge; rc=$_ldc out=$_ld_out"; st=1; fi

  # SODEA-L2: --approved-by equal to the author's name, case-varied and whitespace-varied -> refused, NO note, NO merge.
  # (the author is 'Solo Maint'; the fixture would otherwise PROCEED on a distinct approver.)
  # The last two are full-ident spellings ('Name <email>' and a bare '<EMAIL>'; the fixture author's email is t@example.com).
  for _sl2 in 'solo maint' 'SOLO MAINT' 'Solo  Maint' ' Solo   Maint ' 'Solo Maint <t@example.com>' '<T@EXAMPLE.COM>'; do
    MG_AUTHNAME='Solo Maint'; mg_fx sodl2 "$MG_DIAL_OBS" ROW-SL2 code; MG_AUTHNAME=""
    MG_ABY="$_sl2"; mg_land; MG_ABY=""
    mg_check "SODEA-L2: land --approved-by '$_sl2' vs author 'Solo Maint' -> refused as a self-approval, NO note, NO merge" refuse "LAND REFUSED: approver" "equals the author of the approved commit"
  done

  # SODEA-L3: the fixture clone's OWN config sets log.showSignature=true and the approved commit is ssh-SIGNED, so an
  # unflagged `git show --format=%an` prints a signature line before the name. A real self-approval (approver == author)
  # must still be refused as one, NO note, NO merge. The fixture proves it is polluted, or the leg is not load-bearing.
  if ! command -v ssh-keygen >/dev/null 2>&1; then
    echo "N/A: SODEA-L3 (log.showSignature + signed commit): ssh-keygen is absent on this host, so no ssh-signed fixture can be built — NOT a PASS"
  else
    MG_AUTHNAME='Solo Maint'; mg_fx sodl3 "$MG_DIAL_OBS" ROW-SL3 code; MG_AUTHNAME=""
    # (an `&&` chain, not `set -e`: errexit is disabled inside an `if` condition)
    if ( cd "$LOA" && ssh-keygen -q -t ed25519 -N '' -f "$LO/k" && git config log.showSignature true \
         && GIT_AUTHOR_NAME='Solo Maint' git -c gpg.format=ssh -c user.signingkey="$LO/k.pub" commit -q -S --amend --no-edit ) >/dev/null 2>&1; then
      MG_ASHA="$(git -C "$LOA" rev-parse HEAD)"
      if [ "$(git -C "$LOA" show -s --format=%an "$MG_ASHA" 2>/dev/null | wc -l | tr -d ' ')" -lt 2 ]; then
        echo "FAIL: SODEA-L3 fixture: an unflagged %an read is NOT polluted, so the leg is not load-bearing"; st=1
      fi
      MG_ABY="Solo Maint"; mg_land; MG_ABY=""
      mg_check "SODEA-L3: log.showSignature=true + a signed approved commit, approver == author -> still refused as a self-approval, NO note, NO merge" refuse "LAND REFUSED: approver" "equals the author of the approved commit"
    else
      echo "N/A: SODEA-L3 (log.showSignature + signed commit): this host's git/ssh-keygen cannot make an ssh-signed commit — NOT a PASS"
    fi
  fi
  MG_AUTHNAME='Solo Maint'; mg_fx sodl2p "$MG_DIAL_OBS" ROW-SL2P code; MG_AUTHNAME=""
  MG_ABY="Solo Maintainer"; mg_land; MG_ABY=""
  mg_check "SODEA-L2 (liveness): a DIFFERENT approver 'Solo Maintainer' still lands — the fold is not a refuse-all" proceed

  mg_fx nocls "$MG_DIAL_ENF" ROW-MG10 docs base; mg_poison ROW-MG10; mg_layout "$MG_ROOT/kit-nocls" noclassifier; MG_K="$MG_ROOT/kit-nocls"; mg_land; MG_K="$MG_KIT"
  mg_check "land METER(classifier absent): NOT docs-only (fail-safe) — refused in enforce" refuse "LAND REFUSED (metering gate)" "!N/A: docs-only"

  mg_fx norow "$MG_DIAL_ENF" NONE code; mg_land
  mg_check "land METER(no Kit-Row trailer, enforce): refused — cannot meter an unnamed row" refuse "LAND REFUSED (metering gate)" "unnamed row"
  mg_fx nonerow "$MG_DIAL_ENF" '(none)' code; mg_land
  mg_check "land METER(Kit-Row: (none), enforce): refused" refuse "unnamed row"
  mg_fx norowobs "$MG_DIAL_OBS" NONE code; mg_land
  mg_check "land METER(no row, observe): proceeds with one line" proceed "unnamed row" "observe"

  mg_fx bad 'RUNAWAY_METERING_GATE=enforcee' ROW-MG11 code; mg_land
  mg_check "land METER(malformed conf value): reads as observe and WARNs on the conf side" proceed "WARN" ".kit/dials.conf" "unmetered: ROW-MG11 (observe — not gating)"

  mg_fx wtobs "$MG_DIAL_ENF" ROW-MG12 code; mg_poison ROW-MG12
  printf 'RUNAWAY_METERING_GATE=observe\n' > "$LOA/.kit/dials.conf"; mg_land
  mg_check "land METER(F1): the working tree says observe but the APPROVED tree says enforce -> refused" refuse "LAND REFUSED (metering gate)"
  mg_fx wtenf NONE ROW-MG13 code
  mkdir -p "$LOA/.kit"; printf 'RUNAWAY_METERING_GATE=enforce\n' > "$LOA/.kit/dials.conf"; mg_land
  mg_check "land METER(F1 converse): the working tree says enforce but the approved tree carries no key -> silent, proceeds" proceed "!metering gate" "!unmetered"

  mg_fx envobs "$MG_DIAL_ENF" ROW-MG14 code; mg_poison ROW-MG14; MG_ENVX="RUNAWAY_METERING_GATE=observe"; mg_land; MG_ENVX=""
  mg_check "land METER(F1): env =observe cannot de-escalate an enforcing approved tree -> refused, and says so" refuse "LAND REFUSED (metering gate)" "cannot de-escalate"
  mg_fx envenf NONE ROW-MG15 code; mg_poison ROW-MG15; MG_ENVX="RUNAWAY_METERING_GATE=enforce"; mg_land; MG_ENVX=""
  mg_check "land METER(F1): env =enforce escalates a tree with no key -> refused" refuse "LAND REFUSED (metering gate)"
  mg_fx envbad "$MG_DIAL_ENF" ROW-MG16 code; mg_poison ROW-MG16; MG_ENVX="RUNAWAY_METERING_GATE=bogus"; mg_land; MG_ENVX=""
  mg_check "land METER(F7): a garbage env value WARNs on the ENV side (worded apart from the conf side) and the tree still enforces" refuse "environment" "LAND REFUSED (metering gate)"

  mg_fx link LINK ROW-MG17 code; mg_land
  mg_check "land METER(F1 cond 2): a 120000 symlink dials entry reads observe with a loud line naming the symlink" proceed "symlink" "unmetered: ROW-MG17 (observe — not gating)"

  # fix round 3 (security F-A): `.kit` ITSELF a symlink or a gitlink made `ls-tree -- .kit/dials.conf` return
  # nothing -> mode `absent` -> the gate was SILENT. It must read observe LOUDLY, naming `.kit` and its mode.
  mg_fx dirlink DIRLINK ROW-MG30 code; mg_land
  mg_check "land METER(F-A): .kit itself a 120000 symlink reads observe with a WARN naming .kit (not silent)" proceed "WARN" ".kit" "120000" "unmetered: ROW-MG30 (observe — not gating)"
  mg_fx gitlink GITLINK ROW-MG31 code; mg_land
  mg_check "land METER(F-A): .kit a 160000 gitlink reads observe with a WARN naming .kit (not silent)" proceed "WARN" ".kit" "160000" "unmetered: ROW-MG31 (observe — not gating)"

  mg_fx sbx "$MG_DIAL_ENF" ROW-MG18 code
  mkdir -p "$MG_ROOT/sbx"; printf '1757900000 keyA ROW-MG18 100 1\n' > "$MG_ROOT/sbx/tally.v2"
  if ( cd "$LOA" && env HOME="$MG_H" KIT_RUNAWAY_SANDBOX="$MG_ROOT/sbx" RUNAWAY_TALLY="$MG_ROOT/sbx/tally.v2" \
         sh "$MG_KIT/scripts/runaway-guard.sh" meter --row ROW-MG18 >/dev/null 2>&1 ); then
    echo "PASS: land METER(F2) precondition: the sandbox env alone WOULD read ROW-MG18 as metered"
  else echo "FAIL: land METER(F2) precondition: the sandbox tally did not read as metered, the leg would be vacuous"; st=1; fi
  MG_ENVX="KIT_RUNAWAY_SANDBOX=$MG_ROOT/sbx RUNAWAY_TALLY=$MG_ROOT/sbx/tally.v2"; mg_land; MG_ENVX=""
  mg_check "land METER(F2): the sandbox env exported while the temp-HOME tally is unmetered -> the sandbox tally is NOT read (the row stays unmetered, noted, not refused)" proceed \
    "unmetered: ROW-MG18" "!metered: ROW-MG18 tokens("

  mg_fx noguard "$MG_DIAL_ENF" ROW-MG19 code; mg_layout "$MG_ROOT/kit-nog" noguard; MG_K="$MG_ROOT/kit-nog"; mg_land; MG_K="$MG_KIT"
  mg_check "land METER(F8): the guard script absent -> refused in enforce, naming the absence (deterministic under every shell)" refuse "LAND REFUSED (metering gate)" "the runaway guard script is absent (<path elided>)"

  mg_fx stub7 "$MG_DIAL_ENF" ROW-MG19B code; mg_layout "$MG_ROOT/kit-stub7" stubrc7; MG_K="$MG_ROOT/kit-stub7"; mg_land; MG_K="$MG_KIT"
  mg_check "land METER(F8b): a guard that is present but exits rc 7 -> the any-other-rc arm refuses in enforce (no fail-open on a crash)" refuse "LAND REFUSED (metering gate)" "exited rc 7"

  mg_fx obsrc2 "$MG_DIAL_OBS" ROW-MG20 code; mg_seed ROW-MG20 1 1
  printf 'this line is not the tally grammar\n' >> "$MG_H/.local/state/sparkwright/runaway/$_mgkey/tally.v2"; mg_land
  mg_check "land METER(observe, rc 2): ONE line, proceeds" proceed "guard rc 2" "observe"
  if [ "$(printf '%s\n' "$_ld_out" | grep -c 'guard rc 2')" = 1 ]; then echo "PASS: land METER(observe, rc 2): exactly one line [$VSH]"
  else echo "FAIL: land METER(observe, rc 2): not exactly one line [$VSH]; out=$_ld_out"; st=1; fi
  }
  MG_VSH_SAVED="$VSH"
  # `dash` is added only when the producer shell is not already dash: where /bin/sh IS dash (every Ubuntu
  # runner) a second dash pass runs every leg twice for nothing. If `sh` cannot be resolved, keep both.
  mg_sh_is_dash() { _mgp="$(command -v "$1" 2>/dev/null)" || return 1; _mgt="$(readlink -f "$_mgp" 2>/dev/null || readlink "$_mgp" 2>/dev/null || true)"
    case "$_mgt" in *dash*) return 0 ;; esac; return 1; }
  MG_SHELLS="$MG_VSH_SAVED"
  if [ "$MG_VSH_SAVED" != dash ] && ! mg_sh_is_dash "$MG_VSH_SAVED"; then MG_SHELLS="$MG_SHELLS dash"; fi
  for _mgsh in $MG_SHELLS; do
    command -v "$_mgsh" >/dev/null 2>&1 || continue
    VSH="$_mgsh"; mg_legs
  done
  VSH="$MG_VSH_SAVED"

  # SWAS-537 fix round 3, FXL: the general land fixtures follow the layout of the gate under test, and this runs in EVERY kind of tree
  # (the exported tree is adopter-shaped, so there the general cells above are the adopter/adopter reading; here an adopter-layout gate
  # COPY proves it on a kit tree too, the H1a shape). a: the fixture planted like the copy's own checkout (adopter) -> the N/A line, the
  # land proceeds. b: the OLD plant (both kit facts) against the same adopter copy -> REFUSED layout-mismatch, which is exactly what the
  # exported tree hit; it is the discriminant partner of a. c: the facts are read from the gate checkout, so the adopter copy reads 0 0.
  FXAD="$D/fxad"; mg_layout "$FXAD"
  fxl_land() {   # <repo dir> -> _ldc, _ld_out: a land of the repository's head through the adopter-layout gate COPY
    _fxsha="$(git -C "$1" rev-parse HEAD)"
    if _ld_out="$( cd "$1" && PATH="$(lgh "$_fxsha" "solo maintainer"):$PATH" PROMOTION_NOTES_REF="$LR2" $VSH "$FXAD/scripts/promotion-verify.sh" land \
          --ref 77 --merge-cmd "$LAND_STUB" --approved-sha "$_fxsha" --approved-by "solo maintainer" --go-by "the owner" \
          --gate release-candidate --rung rc --class control-plane --scope "PR #77" --token "GO: land at $_fxsha" 2>&1 )"; then _ldc=0; else _ldc=$?; fi
  }
  if [ "$(fx_facts "$FXAD")" = "0 0 0" ]; then echo "PASS: FXL-c: the layout facts are read at the gate checkout (an adopter-layout copy reads 0 0 0)"
  else echo "FAIL: FXL-c: an adopter-layout gate copy read '$(fx_facts "$FXAD")', not '0 0 0'"; st=1; fi
  mkorigin fxla; fx_like_own "$LOA" "$FXAD"; rm -f "$LAND_MARK"; fxl_land "$LOA"
  if [ "$_ldc" = 0 ] && [ -f "$LAND_MARK" ] && onote "$LOSHA" && printf '%s' "$_ld_out" | grep -qF -e "exact-head CI evidence: N/A"; then
    echo "PASS: FXL-a: an adopter-layout gate copy + a fixture planted like it -> the N/A line, the general land proceeds (merge + note on origin)"
  else echo "FAIL: FXL-a: want rc=0 + merge + note on origin + the N/A line, got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1; fi
  mkorigin fxlb; fx_layout "$LOA" 1 1; rm -f "$LAND_MARK"; fxl_land "$LOA"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -qF -e "layout-mismatch"; then
    echo "PASS: FXL-b: an adopter-layout gate copy + a kit-planted fixture (the old plant) -> REFUSED layout-mismatch, no merge"
  else echo "FAIL: FXL-b: want a layout-mismatch refusal and no merge, got rc=$_ldc merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ); out=$_ld_out"; st=1; fi

  rm -rf "$D"/land-*

  # =====================================================================================
  # LEDGER SYNC (RECORD-FETCHES-AND-PUSHES-LEDGER, design 2026-09-03 §6). `record` is a four-step
  # transaction — sync-in -> write -> publish -> unwind — so these legs need a REAL remote: each
  # builds its own bare "remote" plus two clones under $LROOT (trap-removed). Every leg drives the
  # FIXTURE ref through PROMOTION_NOTES_REF, so nothing here can touch the real ledger. Every
  # NEGATIVE asserts the rc AND the ledger state on BOTH sides (`git rev-parse` of the ref),
  # because "refused, but a dangling local record was left behind" is the exact failure this
  # transaction exists to prevent — an rc-only assertion would pass on it.
  # =====================================================================================
  LR=ledgerx
  LROOT="$D/ledger"
  trap 'rm -rf "$LROOT"' EXIT INT TERM
  mkdir -p "$LROOT"
  KITROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

  lpass() { if [ "$1" = 0 ]; then echo "PASS: $2"; else echo "FAIL: $2 -- $3"; st=1; fi; }
  lrev()  { git -C "$1" rev-parse -q --verify "refs/notes/$LR" 2>/dev/null || echo none; }
  rrev()  { git --git-dir="$1/remote.git" rev-parse -q --verify "refs/notes/$LR" 2>/dev/null || echo none; }
  lnote() { git -C "$1" notes --ref="$LR" show "$2" >/dev/null 2>&1; }
  rnote() { git --git-dir="$1/remote.git" notes --ref="$LR" show "$2" >/dev/null 2>&1; }
  rcount() { git --git-dir="$1/remote.git" rev-list --count "refs/notes/$LR" 2>/dev/null || echo 0; }

  # mkledger <name> -> $LF (fixture dir: remote.git + clones A and B). B carries its own unpushed
  # commit so the two sides record on DIFFERENT approved shas and the chain order is observable.
  mkledger() {
    LF="$LROOT/$1"
    mkdir -p "$LF"
    git init -q --bare -b main "$LF/remote.git"
    ( set -e
      cd "$LF"
      git clone -q remote.git A 2>/dev/null
      cd A
      git config user.email t@example.com; git config user.name t; git config commit.gpgsign false
      printf 'a\n' > f.txt
      mkdir -p docs/architecture
      printf '# X design\n\nThe x fixture design: a record names this file as its basis.\nIt carries several real lines so it is more than a stub.\nThe approved commit adds or touches it, as the record legs require.\n' > docs/architecture/x-design.md
      printf '# Y design\n\nThe y fixture design: a second tracked design file for a different basis.\nIt carries several real lines so it is more than a stub.\nThe approved commit adds or touches it, as the record legs require.\n' > docs/architecture/y-design.md
      git add f.txt docs/architecture/x-design.md docs/architecture/y-design.md; git commit -qm base
      git push -q origin HEAD:refs/heads/main
      cd "$LF"
      git clone -q remote.git B 2>/dev/null
      cd B
      git config user.email t@example.com; git config user.name t; git config commit.gpgsign false
      printf 'b-side change\n' >> docs/architecture/x-design.md
      git add docs/architecture/x-design.md; git commit -q -m b-side )
    ASHA="$(git -C "$LF/A" rev-parse HEAD)"
    BSHA="$(git -C "$LF/B" rev-parse HEAD)"
  }
  # la2 <clone-dir> -> a commit message `a2` that TOUCHES x-design.md (a design record's approved commit must touch its basis).
  la2() {
    printf 'a2 change\n' >> "$1/docs/architecture/x-design.md"
    git -C "$1" add docs/architecture/x-design.md
    git -C "$1" commit -q -m a2
  }
  # lrec <clone-dir> <approved-sha> <scope> [extra record args...] -> sets LRC and LOUT.
  lrec() {
    _cd="$1"; _cs="$2"; _cp="$3"; shift 3
    if LOUT="$( cd "$_cd" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e PROMOTION_NOTES_REF="$LR" $VSH "$VERIFY" record \
          --approved-sha "$_cs" --approved-by "solo maintainer" --gate design --rung integration \
          --class control-plane --scope "$_cp" --token "GO: $_cp" \
          --basis docs/architecture/x-design.md "$@" 2>&1 )"; then
      LRC=0; else LRC=$?; fi
  }
  # llog <clone-dir> [args...] -> sets LRC and LOUT
  llog() {
    _cd="$1"; shift
    if LOUT="$( cd "$_cd" && PROMOTION_NOTES_REF="$LR" $VSH "$VERIFY" log "$@" 2>&1 )"; then
      LRC=0; else LRC=$?; fi
  }
  # lracer <once|always> — writes A's `reference-transaction` hook: clone B records and PUBLISHES
  # (a real `record`, so it is the real race) the moment A's own ledger ref moves, i.e. in the
  # window between A's sync-in and A's push. THE HOOK CHOICE IS LOAD-BEARING (measured): a pre-push
  # hook fires AFTER git has already listed the remote's refs, so a race staged there produces the
  # server-side `cannot lock ref` variant instead of the non-fast-forward this design retries on.
  # reference-transaction fires before that listing, which is the window the row describes.
  lracer() {
    mkdir -p "$LF/hooks"
    { printf '#!/bin/sh\n[ "$1" = committed ] || exit 0\ngrep -q "refs/notes/%s" || exit 0\n' "$LR"
      if [ "$1" = once ]; then printf '[ -e "%s/.raced" ] && exit 0\n: > "%s/.raced"\n' "$LF" "$LF"; fi
      printf 'unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX\n'
      printf '( cd "%s/B" && PROMOTION_NOTES_REF=%s sh "%s" record --approved-sha %s \\\n' \
             "$LF" "$LR" "$VERIFY" "$BSHA"
      printf '  --approved-by racer --gate design --rung integration --class control-plane \\\n'
      printf '  --scope branch/racer-$$ --token "GO: racer" --basis docs/architecture/x-design.md ) >/dev/null 2>&1\nexit 0\n'
    } > "$LF/hooks/reference-transaction"
    chmod +x "$LF/hooks/reference-transaction"
    git -C "$LF/A" config core.hooksPath "$LF/hooks"
  }

  # --- (+) FIRST-EVER RECORD: the remote has NO notes ref. The `ls-remote --exit-code` probe (rc 2
  #     = absent) is what distinguishes this from "unreachable" — both FETCH rc 128 — so this leg
  #     and the unreachable leg below are the two halves of that split. Publish creates the ref. ---
  mkledger first
  lrec "$LF/A" "$ASHA" "branch/first"
  if [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q 'published' && rnote "$LF" "$ASHA" \
     && [ "$(lrev "$LF/A")" = "$(rrev "$LF")" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "ledger sync (+): first-ever record — absent remote ref, record creates and publishes it" "rc=$LRC out=$LOUT"

  # --- (+) FRESH RECORD onto a ledger that already exists: clone B has NO local notes ref, so the
  #     record can only land on top of A's if sync-in actually fetched. Chain must be 2, not 1. ---
  lrec "$LF/B" "$BSHA" "branch/second"
  if [ "$LRC" = 0 ] && rnote "$LF" "$BSHA" && rnote "$LF" "$ASHA" && [ "$(rcount "$LF")" = 2 ] \
     && [ "$(lrev "$LF/B")" = "$(rrev "$LF")" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "ledger sync (+): second clone fetches the remote chain and appends (chain=2, both records survive)" "rc=$LRC out=$LOUT"

  # --- (−) DIVERGED: A holds an unpublished record while the remote moved on. The non-forced fetch
  #     cannot fast-forward, so record REFUSES rc 2 and names the remedy — and neither side moves.
  #     (A forced `+` refspec here would silently DISCARD the local record: approach 1, struck.) ---
  _rpre="$(rrev "$LF")"
  lrec "$LF/A" "$ASHA" "branch/local-only" --no-push
  _adiv="$(lrev "$LF/A")"
  lrec "$LF/A" "$ASHA" "branch/blocked"
  if [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'diverged' \
     && printf '%s' "$LOUT" | grep -q -- '--unpushed' \
     && [ "$(lrev "$LF/A")" = "$_adiv" ] && [ "$(rrev "$LF")" = "$_rpre" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "ledger sync (−): local diverged -> rc 2 naming log --unpushed, BOTH refs untouched" "rc=$LRC out=$LOUT"

  # --- (+) `log --unpushed` is the remedy the refusal names, so it must actually list the
  #     unpublished record and only that one. ---
  llog "$LF/A" --unpushed
  if [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q "$ASHA" \
     && printf '%s' "$LOUT" | grep -qi 'unpublished' \
     && ! printf '%s' "$LOUT" | grep -q "$BSHA"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "ledger sync (+): log --unpushed lists the unpublished record and not the published one" "rc=$LRC out=$LOUT"

  # --- signposts (T3): the diverged refusal and the `log --unpushed` footer point at `sync` (a pin on
  #     the printed text, not a parse). The old advice, `git push origin refs/notes/...`, FAILS on a diverged ledger. ---
  lrec "$LF/A" "$ASHA" "branch/blocked2"
  if [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'ledger diverged' \
     && printf '%s' "$LOUT" | grep -q 'promotion-verify.sh sync' && printf '%s' "$LOUT" | grep -q 'sync --dry-run' \
     && ! printf '%s' "$LOUT" | grep -q 'publish them first'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "signpost (−): record's diverged refusal names 'promotion-verify.sh sync' (and --dry-run), not the push that fails" "rc=$LRC out=$LOUT"
  llog "$LF/A" --unpushed
  if [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q "$ASHA" \
     && [ "$(printf '%s\n' "$LOUT" | tail -n 1)" = '# reconcile: promotion-verify.sh sync  (preview: sync --dry-run)' ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "signpost (+): log --unpushed listing a record ends with the reconcile footer" "rc=$LRC out=$LOUT"
  mkledger nofooter
  lrec "$LF/A" "$ASHA" "branch/nf"
  llog "$LF/A" --unpushed
  if [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q '^# Unpublished promotion records' \
     && ! printf '%s' "$LOUT" | grep -q '(unpublished)' && ! printf '%s' "$LOUT" | grep -q 'reconcile'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "signpost (−): log --unpushed listing nothing prints no reconcile footer" "rc=$LRC out=$LOUT"
  # The guard's deny text (arm 13, raw `git notes` writes) names the verb (its old sentence advised the push).
  if grep -qF 'to reconcile a diverged ledger, use scripts/promotion-verify.sh sync' "$KITROOT/.claude/hooks/guard-core.sh" 2>/dev/null; then _lc=0; else _lc=1; fi
  lpass "$_lc" "signpost: the guard's raw-notes-write deny text names promotion-verify.sh sync" "guard-core=$KITROOT/.claude/hooks/guard-core.sh"

  # --- (+) `--no-push`: the LABELLED escape (argument only, never env, never the default). Local
  #     note written, OK line says UNPUBLISHED, remote never touched. ---
  mkledger nopush
  lrec "$LF/A" "$ASHA" "branch/np" --no-push
  if [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q 'UNPUBLISHED' && lnote "$LF/A" "$ASHA" \
     && [ "$(rrev "$LF")" = none ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "ledger sync (+): --no-push records locally, says UNPUBLISHED, leaves the remote alone" "rc=$LRC out=$LOUT"

  # --- (−) UNREACHABLE remote (the other half of the rc-128 split): refuse rc 2 naming the cause,
  #     and write NOTHING — an offline record is the race this row exists to end. ---
  _npre="$(lrev "$LF/A")"
  git -C "$LF/A" remote set-url origin "$LF/does-not-exist.git"
  la2 "$LF/A"
  _asha2="$(git -C "$LF/A" rev-parse HEAD)"
  lrec "$LF/A" "$_asha2" "branch/offline"
  if [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -qi 'reach' && ! lnote "$LF/A" "$_asha2" \
     && [ "$(lrev "$LF/A")" = "$_npre" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "ledger sync (−): unreachable remote -> rc 2 naming the cause, NO local note written" "rc=$LRC out=$LOUT"

  # --- (−) `log --unpushed` FAILS CLOSED when the remote is unreachable: UNKNOWN + rc 2, never the
  #     dangerous "0 unpushed" that would read as "everything is published". ---
  llog "$LF/A" --unpushed
  if [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'UNKNOWN'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "ledger sync (−): log --unpushed with an unreachable remote -> UNKNOWN, rc 2, never 0" "rc=$LRC out=$LOUT"

  # --- (−) SYMREF: a repointed ledger ref is refused BEFORE anything is written (guard bypass #8
  #     becomes a loud front-door refusal; fetch and plain update-ref write THROUGH a symref). ---
  mkledger symref
  git -C "$LF/A" update-ref refs/notes/decoy "$ASHA"
  git -C "$LF/A" symbolic-ref "refs/notes/$LR" refs/notes/decoy
  lrec "$LF/A" "$ASHA" "branch/sym"
  if [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'symbolic' \
     && [ "$(git -C "$LF/A" rev-parse refs/notes/decoy)" = "$ASHA" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "ledger sync (−): symbolic ledger ref -> rc 2 before any write, decoy target untouched" "rc=$LRC out=$LOUT"

  # --- (−) THE RACE, retried once: clone B records and publishes between A's fetch and A's push
  #     (a real `record` fired from A's own pre-push hook — the exact window). A must unwind, sync
  #     in again, re-write the SAME body and publish: chain = seed, racer, A. ---
  mkledger race
  lrec "$LF/A" "$ASHA" "branch/seed"
  la2 "$LF/A"
  _asha2="$(git -C "$LF/A" rev-parse HEAD)"
  lracer once
  lrec "$LF/A" "$_asha2" "branch/retry"
  if [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q 'published' && rnote "$LF" "$_asha2" \
     && rnote "$LF" "$BSHA" && [ "$(rcount "$LF")" = 3 ] \
     && [ "$(lrev "$LF/A")" = "$(rrev "$LF")" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "ledger sync (−): remote moved mid-record -> unwind, re-sync, retry ONCE, published (chain=3)" "rc=$LRC out=$LOUT"

  # --- (−) THE HOOK-REJECTION RACE, AS MEASURED. The design expected this repo's own pre-push hook
  #     to be the FIRST refuser of a non-ff ledger push. It is not, and the correction is pinned
  #     here rather than left as prose: git's client-side fast-forward check rejects a NON-FORCED
  #     non-ff push BEFORE any pre-push hook runs (measured: the hook prints nothing), so the
  #     rejection `record` sees is always the plain `(non-fast-forward)` one. The hook's own
  #     `13: non-fast-forward` refusal is reachable only on a FORCED push, which `record` never
  #     issues. What this leg therefore proves is the property that actually matters: with the kit
  #     hook live in the pushing repo, the raced record still unwinds, re-syncs and publishes — the
  #     guard does not deadlock the ledger's own publish (design §4.3, vet L1) — plus both halves of
  #     the measurement above, so a future git or guard change that reverses either goes RED. ---
  mkledger hookrace
  if [ -f "$KITROOT/hooks/pre-push" ] && [ -f "$KITROOT/.claude/hooks/guard-core.sh" ]; then
    lrec "$LF/A" "$ASHA" "branch/seed"
    la2 "$LF/A"
    _asha2="$(git -C "$LF/A" rev-parse HEAD)"
    lracer once
    mkdir -p "$LF/A/.claude/hooks"
    cp "$KITROOT/hooks/pre-push" "$LF/hooks/pre-push"
    cp "$KITROOT/.claude/hooks/guard-core.sh" "$LF/A/.claude/hooks/guard-core.sh"
    lrec "$LF/A" "$_asha2" "branch/hookretry"
    # NON-VACUITY PROBES: the hook must be LIVE in this clone (else the green above only re-proves
    # the remote-rejection leg), and the two rejection routes must stay where they were measured.
    _hplain="$( cd "$LF/A" && git push origin \
        "$(git rev-parse "refs/notes/$LR^"):refs/notes/$LR" 2>&1 || true )"
    _hforce="$( cd "$LF/A" && git push -f origin \
        "$(git rev-parse "refs/notes/$LR^"):refs/notes/$LR" 2>&1 || true )"
    if [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q 'published' && rnote "$LF" "$_asha2" \
       && [ "$(rcount "$LF")" = 3 ] \
       && printf '%s' "$_hplain" | grep -q 'non-fast-forward' \
       && ! printf '%s' "$_hplain" | grep -q 'kit guard' \
       && printf '%s' "$_hforce" | grep -q '13: non-fast-forward'; then _lc=0; else _lc=1; fi
    lpass "$_lc" "ledger sync (−): with the kit pre-push hook live the raced record still publishes; the hook's non-ff refusal is FORCED-push-only (git rejects a plain non-ff first)" "rc=$LRC out=$LOUT plain=$_hplain"
  else
    echo "FAIL: ledger sync: kit hooks/pre-push + guard-core.sh not found under $KITROOT (leg cannot run)"; st=1
  fi

  # --- (−) THE DOUBLE RACE: the remote moves on EVERY attempt. After the second rejection the
  #     record is unwound and REFUSED loudly — never retained locally, never published. ---
  mkledger race2
  lrec "$LF/A" "$ASHA" "branch/seed"
  la2 "$LF/A"
  _asha2="$(git -C "$LF/A" rev-parse HEAD)"
  lracer always
  lrec "$LF/A" "$_asha2" "branch/doomed"
  if [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'twice' && ! lnote "$LF/A" "$_asha2" \
     && ! rnote "$LF" "$_asha2"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "ledger sync (−): remote moved TWICE -> rc 2, no dangling local note, nothing published" "rc=$LRC out=$LOUT"

  # --- (−) A NON-NON-FF push failure (here: the remote declines the receive — the auth/protected-ref
  #     shape) must NOT retry: unwind once, refuse rc 2, and relay git's own stderr. ---
  mkledger authfail
  lrec "$LF/A" "$ASHA" "branch/seed"
  _rpre="$(lrev "$LF/A")"
  printf '#!/bin/sh\necho "FIXTURE-DENIED: ledger is read-only" >&2\nexit 1\n' > "$LF/remote.git/hooks/pre-receive"
  chmod +x "$LF/remote.git/hooks/pre-receive"
  la2 "$LF/A"
  _asha2="$(git -C "$LF/A" rev-parse HEAD)"
  lrec "$LF/A" "$_asha2" "branch/denied"
  if [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'FIXTURE-DENIED' \
     && ! printf '%s' "$LOUT" | grep -q 'twice' && ! lnote "$LF/A" "$_asha2" \
     && [ "$(lrev "$LF/A")" = "$_rpre" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "ledger sync (−): non-ff-UNRELATED push failure -> unwind, rc 2, git's stderr relayed, no retry" "rc=$LRC out=$LOUT"

  # --- (−) CAS REFUSAL: something moved the local ledger between the write and the unwind. The
  #     old-value operand makes update-ref a compare-and-swap, so the unwind REFUSES rather than
  #     clobbering the interloper — and `record` says so instead of claiming a clean rollback. ---
  mkledger casfail
  lrec "$LF/A" "$ASHA" "branch/seed"
  la2 "$LF/A"
  _asha2="$(git -C "$LF/A" rev-parse HEAD)"
  mkdir -p "$LF/hooks"
  { printf '#!/bin/sh\nunset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX\n'
    printf 'cd "%s/A" && git notes --ref=%s add -f -m sidecar %s >/dev/null 2>&1\nexit 1\n' \
           "$LF" "$LR" "$ASHA"
  } > "$LF/hooks/pre-push"
  chmod +x "$LF/hooks/pre-push"
  git -C "$LF/A" config core.hooksPath "$LF/hooks"
  lrec "$LF/A" "$_asha2" "branch/cas"
  if [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'NOT unwound' && lnote "$LF/A" "$_asha2"; then
    _lc=0; else _lc=1; fi
  lpass "$_lc" "ledger sync (−): the ledger moved under the record -> CAS refuses, rc 2 says NOT unwound" "rc=$LRC out=$LOUT"

  # --- (−) THE SCRATCH REF IS NOT TRUSTED EITHER (security review SEC-M1). `log --unpushed` answers
  #     by comparing the local ledger against a scratch ref it just fetched. If that ref is deleted
  #     or repointed between the fetch and the walk, `git rev-list` FAILS — and a `for x in $(…)`
  #     loop would swallow that failure and render it as a confident, empty "nothing unpublished",
  #     which is the one answer this mode must never produce by accident. Here a reference-transaction
  #     hook deletes the scratch the moment it appears, and the mode must say UNKNOWN, rc 2. ---
  mkledger scratch
  lrec "$LF/A" "$ASHA" "branch/seed"
  la2 "$LF/A"
  _asha2="$(git -C "$LF/A" rev-parse HEAD)"
  lrec "$LF/A" "$_asha2" "branch/np" --no-push
  mkdir -p "$LF/hooks"
  { printf '#!/bin/sh\n[ "$1" = committed ] || exit 0\n[ -e "%s/.dropped" ] && exit 0\n' "$LF"
    printf 'while read -r _o _n _r; do case "$_r" in refs/kit/notes-remote-*)\n'
    printf '  : > "%s/.dropped"; unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX\n' "$LF"
    printf '  cd "%s/A" && git update-ref -d "$_r" >/dev/null 2>&1 ;; esac; done\nexit 0\n' "$LF"
  } > "$LF/hooks/reference-transaction"
  chmod +x "$LF/hooks/reference-transaction"
  git -C "$LF/A" config core.hooksPath "$LF/hooks"
  llog "$LF/A" --unpushed
  if [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'UNKNOWN' \
     && ! printf '%s' "$LOUT" | grep -q "## $_asha2"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "ledger sync (−): the scratch ref vanishing mid-walk -> UNKNOWN, rc 2, never an empty '0 unpushed'" "rc=$LRC out=$LOUT"

  # --- (−) THE LEDGER REF NAME IS INPUT (security review SEC-M2). `PROMOTION_NOTES_REF` was a local
  #     `git notes --ref` selector; since this slice it also composes a FETCH and a PUSH refspec, so
  #     it is validated at the front door. The leg asserts rc 2 AND that the remote's ref list is
  #     byte-identical afterwards: refusing loudly but having already fetched or pushed something
  #     first would satisfy an rc-only assertion. ---
  _rrefs="$(git --git-dir="$LF/remote.git" for-each-ref --format='%(refname) %(objectname)' 2>/dev/null || echo none)"
  if LOUT="$( cd "$LF/A" && PROMOTION_NOTES_REF='*' $VSH "$VERIFY" record --approved-sha "$ASHA" \
        --approved-by x --gate design --rung integration --class control-plane --scope branch/x \
        --token GO --basis docs/architecture/x-design.md 2>&1 )"; then LRC=0; else LRC=$?; fi
  _rrefs2="$(git --git-dir="$LF/remote.git" for-each-ref --format='%(refname) %(objectname)' 2>/dev/null || echo none)"
  if [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'invalid PROMOTION_NOTES_REF' \
     && [ "$_rrefs" = "$_rrefs2" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "ledger sync (−): a ref name outside [A-Za-z0-9._-] -> rc 2 before any fetch or push (remote ref list unchanged)" "rc=$LRC out=$LOUT"

  # --- (+) A REACHABLE REMOTE WITH NO LEDGER AT ALL is not UNKNOWN — it is the strongest possible
  #     "unpublished": everything local is. Reported as such rather than as an alarm. ---
  mkledger nolist
  lrec "$LF/A" "$ASHA" "branch/np" --no-push
  llog "$LF/A" --unpushed
  if [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q 'every local record' \
     && printf '%s' "$LOUT" | grep -q "$ASHA" \
     && ! printf '%s' "$LOUT" | grep -q 'UNKNOWN'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "ledger sync (+): reachable remote with no ledger ref -> every local record listed as unpublished, rc 0" "rc=$LRC out=$LOUT"

  # =====================================================================================
  # `sync` (PROMOTION-LEDGER-SYNC-VERB, T1: classify / twin / voided / --dry-run). Fixtures are the
  # same bare-remote + two-clone shape; every leg asserts a POSITIVE ANCHOR first (the fixture
  # really diverged, so a vacuous "nothing to do" cannot pass), and after every sync no temp notes
  # ref (refs/notes/kit-sync-*, or a refs/notes/refs/* rewrite of a refs/kit/ name — I4) may survive
  # in the clone or the remote.
  # =====================================================================================
  # lsync <clone-dir> [args...] -> sets LRC and LOUT; also fails the run if a temp ref leaked.
  lsync() {
    _cd="$1"; shift
    if LOUT="$( cd "$_cd" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e PATH="${LSHIM_DIR:+$LSHIM_DIR:}$PATH" FAIL_GIT_SUB="${LSHIM_SUB:-}" PROMOTION_NOTES_REF="$LR" $VSH "$VERIFY" sync "$@" 2>&1 )"; then
      LRC=0; else LRC=$?; fi
    _leak="$(git -C "$_cd" for-each-ref 'refs/notes/kit-sync-*' 'refs/notes/refs/*' 'refs/kit/notes-remote-*' 2>/dev/null)$(git --git-dir="$LF/remote.git" for-each-ref 'refs/notes/kit-sync-*' 'refs/notes/refs/*' 'refs/kit/notes-remote-*' 2>/dev/null)"
    if [ -n "$_leak" ]; then echo "FAIL: sync leaked a temp notes ref: $_leak"; st=1; fi
  }
  lfetch() { git -C "$1" fetch -q origin "refs/notes/$LR:refs/notes/$LR" 2>/dev/null; }
  # ldiverged <clone-dir>: 0 when neither the local ledger nor origin's is an ancestor of the other.
  ldiverged() {
    _lt="$(lrev "$1")"; _rt="$(rrev "$LF")"
    git -C "$1" fetch -q origin "refs/notes/$LR:refs/kit/anchor-remote" 2>/dev/null || return 1
    if git -C "$1" merge-base --is-ancestor "$_lt" "$_rt" 2>/dev/null \
       || git -C "$1" merge-base --is-ancestor "$_rt" "$_lt" 2>/dev/null; then _r=1; else _r=0; fi
    git -C "$1" update-ref -d refs/kit/anchor-remote
    return $_r
  }
  # lforge <clone> <sha> <label>: rewrite that note's approved-by label by writing the body directly.
  lforge() {
    git -C "$1" notes --ref="$LR" show "$2" | sed "s/^\(approved-by: .*\) \[[^]]*\]\$/\1 [$3]/" > "$LF/forged.txt"
    git -C "$1" notes --ref="$LR" add -f -F "$LF/forged.txt" "$2"
  }
  lrefs() { git -C "$1" for-each-ref --format='%(refname) %(objectname)'; }

  # (+) 1. fast-forward only: local strictly behind origin.
  mkledger sfast
  lrec "$LF/A" "$ASHA" "branch/s1"
  lfetch "$LF/B"
  la2 "$LF/A"; _a2="$(git -C "$LF/A" rev-parse HEAD)"
  lrec "$LF/A" "$_a2" "branch/s1b"
  _bpre="$(lrev "$LF/B")"
  lsync "$LF/B"
  if [ "$_bpre" != "$(rrev "$LF")" ] && [ "$LRC" = 0 ] && [ "$(lrev "$LF/B")" = "$(rrev "$LF")" ] \
     && printf '%s' "$LOUT" | grep -q 'fast-forwarded'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (+): fast-forward only -> local == origin, rc 0" "rc=$LRC out=$LOUT"

  # (+) 2. publish-only: local strictly ahead; reported (dry-run says WOULD candidate), nothing written.
  mkledger spubonly
  lrec "$LF/A" "$ASHA" "branch/s2"
  lfetch "$LF/B"
  lrec "$LF/B" "$BSHA" "branch/s2b" --no-push
  _lpre="$(lrev "$LF/B")"; _rpre="$(rrev "$LF")"
  lsync "$LF/B" --dry-run
  if [ "$_lpre" != "$_rpre" ] && git -C "$LF/B" merge-base --is-ancestor "$_rpre" "$_lpre" \
     && [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q "WOULD candidate $BSHA" \
     && [ "$(lrev "$LF/B")" = "$_lpre" ] && [ "$(rrev "$LF")" = "$_rpre" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (+): publish-only (local ahead) -> --dry-run says WOULD candidate, writes nothing" "rc=$LRC out=$LOUT"

  # (+) 3. byte-identical twin -> no-op reconcile (local dropped to origin's tip; no twin report).
  mkledger sident
  lrec "$LF/A" "$ASHA" "branch/s3"
  git -C "$LF/A" notes --ref="$LR" show "$ASHA" > "$LF/body.txt"
  # A distinct committer date: two identical bodies committed in the same second would hash to the
  # SAME notes commit, and the fixture would not be divergent at all.
  GIT_COMMITTER_DATE="2001-01-01T00:00:00" GIT_AUTHOR_DATE="2001-01-01T00:00:00" \
    git -C "$LF/B" notes --ref="$LR" add -F "$LF/body.txt" "$ASHA"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsync "$LF/B"
  if [ "$_anc" = 0 ] && [ "$LRC" = 0 ] && [ "$(lrev "$LF/B")" = "$(rrev "$LF")" ] \
     && ! printf '%s' "$LOUT" | grep -q 'twin-origin-wins'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (+): byte-identical twin -> no-op, rc 0, local == origin" "anc=$_anc rc=$LRC out=$LOUT"

  # (+) 4. free-text twin -> twin-origin-wins; local then equals origin's bytes for that sha.
  #     Also (10): --dry-run first leaves the local ledger and BOTH ref lists byte-identical.
  mkledger stwin
  lrec "$LF/A" "$ASHA" "branch/s4"
  lrec "$LF/B" "$ASHA" "branch/s4" --no-push --token "different token" --basis "docs/architecture/y-design.md"
  # Force the recorded-at difference (same-second records would otherwise be equal), so the
  # "only approval-token / basis / recorded-at may differ" claim is exercised on all three.
  git -C "$LF/B" notes --ref="$LR" show "$ASHA" | sed 's/^recorded-at: .*/recorded-at: 2001-01-01T00:00:00Z/' > "$LF/ts.txt"
  git -C "$LF/B" notes --ref="$LR" add -f -F "$LF/ts.txt" "$ASHA"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  _l0="$(lrefs "$LF/B")"; _r0="$(git --git-dir="$LF/remote.git" for-each-ref --format='%(refname) %(objectname)')"
  lsync "$LF/B" --dry-run
  if [ "$_anc" = 0 ] && [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q "WOULD twin-origin-wins $ASHA" \
     && [ "$_l0" = "$(lrefs "$LF/B")" ] \
     && [ "$_r0" = "$(git --git-dir="$LF/remote.git" for-each-ref --format='%(refname) %(objectname)')" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (+): --dry-run prints WOULD twin-origin-wins and leaves local + remote ref lists byte-identical" "anc=$_anc rc=$LRC out=$LOUT"
  lsync "$LF/B"
  if [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q "twin-origin-wins $ASHA" \
     && [ "$(lrev "$LF/B")" = "$(rrev "$LF")" ] \
     && [ "$(git -C "$LF/B" notes --ref="$LR" show "$ASHA")" = "$(git -C "$LF/A" notes --ref="$LR" show "$ASHA")" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (+): free-text twin -> twin-origin-wins, local ledger then equals origin's for that sha" "rc=$LRC out=$LOUT"

  # (−) 5. identity twin (different label) -> rc 2, both notes printed, --discard-local named, nothing moved.
  mkledger sident2
  lrec "$LF/A" "$ASHA" "branch/s5"
  lrec "$LF/B" "$ASHA" "branch/s5" --no-push --token "local token"
  lforge "$LF/B" "$ASHA" "authenticated: github-review"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  _lpre="$(lrev "$LF/B")"
  lsync "$LF/B"
  if [ "$_anc" = 0 ] && [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'origin.s note' \
     && printf '%s' "$LOUT" | grep -q 'local note' && printf '%s' "$LOUT" | grep -q 'authenticated: github-review' \
     && printf '%s' "$LOUT" | grep -q 'approval-token: "GO: branch/s5"$' \
     && printf '%s' "$LOUT" | grep -q "sync --discard-local $ASHA" && [ "$(lrev "$LF/B")" = "$_lpre" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (−): identity twin (label differs) -> rc 2, both notes printed, --discard-local named, ledger untouched" "anc=$_anc rc=$LRC out=$LOUT"

  # (−) 6. --discard-local scopes to the sha it names: two refusing shas.
  mkledger sdisc
  la2 "$LF/A"; _a2="$(git -C "$LF/A" rev-parse HEAD)"
  git -C "$LF/A" push -q origin HEAD:refs/heads/main
  git -C "$LF/B" fetch -q origin
  lrec "$LF/A" "$ASHA" "branch/s6"
  lrec "$LF/A" "$_a2" "branch/s6b"
  lrec "$LF/B" "$ASHA" "branch/s6" --no-push --token "local token"
  lrec "$LF/B" "$_a2" "branch/s6b" --no-push --token "local token"
  lforge "$LF/B" "$ASHA" "signed: gpg"; lforge "$LF/B" "$_a2" "signed: gpg"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsync "$LF/B" --discard-local "$ASHA"
  _c1="$LRC"; _o1="$LOUT"
  lsync "$LF/B" --discard-local "$ASHA" --discard-local "$_a2"
  if [ "$_anc" = 0 ] && [ "$_c1" = 2 ] && printf '%s' "$_o1" | grep -q "REFUSED $_a2" \
     && ! printf '%s' "$_o1" | grep -q "REFUSED $ASHA" \
     && [ "$LRC" = 0 ] && [ "$(lrev "$LF/B")" = "$(rrev "$LF")" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (+): --discard-local <sha1> alone still refuses sha2 (rc 2); naming both -> rc 0, local == origin" "anc=$_anc c1=$_c1 o1=$_o1 rc=$LRC out=$LOUT"

  # (−) 7. voided upstream: origin once held the note and its tip no longer does.
  mkledger svoid
  lrec "$LF/A" "$ASHA" "branch/s7"
  lfetch "$LF/B"
  git --git-dir="$LF/remote.git" notes --ref="$LR" remove "$ASHA" 2>/dev/null \
    || GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e \
       git --git-dir="$LF/remote.git" notes --ref="$LR" remove "$ASHA"
  lrec "$LF/B" "$BSHA" "branch/s7b" --no-push
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  _lpre="$(lrev "$LF/B")"
  lsync "$LF/B"
  if [ "$_anc" = 0 ] && [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q "REFUSED $ASHA" \
     && printf '%s' "$LOUT" | grep -q 'VOIDED upstream' && printf '%s' "$LOUT" | grep -q "sync --discard-local $ASHA" \
     && [ "$(lrev "$LF/B")" = "$_lpre" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (−): voided upstream (published, removed on origin, kept locally) -> rc 2 naming the sha" "anc=$_anc rc=$LRC out=$LOUT"

  # (−) 8. offline -> rc 2, ledger unchanged.  (−) 9. symbolic ledger ref -> rc 2.
  mkledger soff
  lrec "$LF/B" "$BSHA" "branch/s8" --no-push
  _lpre="$(lrev "$LF/B")"
  git -C "$LF/B" remote set-url origin "$LF/does-not-exist.git"
  lsync "$LF/B"
  if [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'sync: cannot reach' && [ "$(lrev "$LF/B")" = "$_lpre" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (−): offline origin -> rc 2 naming the cause, ledger untouched" "rc=$LRC out=$LOUT"
  mkledger ssym
  git -C "$LF/A" update-ref refs/notes/decoy "$ASHA"
  git -C "$LF/A" symbolic-ref "refs/notes/$LR" refs/notes/decoy
  lsync "$LF/A"
  if [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'symbolic' \
     && [ "$(git -C "$LF/A" rev-parse refs/notes/decoy)" = "$ASHA" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (−): symbolic ledger ref -> rc 2 before any write, decoy untouched" "rc=$LRC out=$LOUT"

  # =====================================================================================
  # sync, fix round 1: the FAIL-OPEN CLASS. A git read that feeds the classification or the voided
  # arm must never turn "the read failed" into "no difference" / "no history": every one refuses
  # (rc 2, `REFUSED`, ledger unchanged). A `git` shim on PATH forces one named subcommand to fail
  # (exit 128) for the sync run only; each shimmed leg is red on a fail-open read and asserts the
  # ledger sha is unchanged. Also: the live "candidates exist" stop, the merge-only voided history,
  # the pathname-expansion loop, and a twin that differs only in trailing newlines.
  # =====================================================================================
  lshim() {
    mkdir -p "$LROOT/shim"
    printf '%s\n' '#!/bin/sh' \
      'if [ -n "${FAIL_GIT_SUB:-}" ] && [ "${1:-}" = "$FAIL_GIT_SUB" ]; then echo "shim: forced git $1 failure" >&2; exit 128; fi' \
      'if [ -n "${SLEEP_GIT_SUB:-}" ] && [ "${1:-}" = "$SLEEP_GIT_SUB" ]; then [ -z "${SLEEP_MARK:-}" ] || : > "$SLEEP_MARK"; sleep 3; fi' \
      'if [ -n "${REQUIRE_ROOT:-}" ] && [ "${1:-}" = log ]; then case " $* " in *" --name-only "*) case " $* " in *" --root "*) ;; *) echo "shim: log without --root" >&2; exit 128 ;; esac ;; esac; fi' \
      'if [ -n "${WAIT_GIT_SUB:-}" ] && [ "${1:-}" = "$WAIT_GIT_SUB" ] && [ ! -e "$WAIT_MARK.started" ]; then : > "$WAIT_MARK.started"; while [ ! -e "$WAIT_MARK.go" ]; do sleep 0.1; done; fi' \
      "exec \"$(command -v git)\" \"\$@\"" > "$LROOT/shim/git"
    chmod +x "$LROOT/shim/git"
  }
  # lsyncf <clone> <failing-subcommand> [sync args...]
  lsyncf() {
    lshim; _fc="$1"; LSHIM_DIR="$LROOT/shim"; LSHIM_SUB="$2"; shift 2
    lsync "$_fc" "$@"
    LSHIM_DIR=""; LSHIM_SUB=""
  }
  lgid() { GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e "$@"; }
  # lrefused: 0 when the last sync refused (rc 2, REFUSED) and never reported a WOULD/kept/candidate line.
  lrefused() {
    [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'REFUSED' \
      && ! printf '%s' "$LOUT" | grep -q 'WOULD candidate' && ! printf '%s' "$LOUT" | grep -q 'ledger reconciled'
  }
  # ltwinfix <name>: a diverged fixture where B holds a free-text twin of origin's note on ASHA.
  ltwinfix() {
    mkledger "$1"
    lrec "$LF/A" "$ASHA" "branch/$1"
    lrec "$LF/B" "$ASHA" "branch/$1" --no-push --token "different token"
  }

  # F1(a): origin's ledger ref names a TREE, not a commit -> refused (dry-run and live), local unchanged.
  mkledger sbadref
  lrec "$LF/B" "$BSHA" "branch/f1a" --no-push
  _lpre="$(lrev "$LF/B")"
  _fb="$(printf 'x' | git --git-dir="$LF/remote.git" hash-object -w --stdin)"
  _ft="$(printf '100644 blob %s\tfoo\n' "$_fb" | git --git-dir="$LF/remote.git" mktree)"
  git --git-dir="$LF/remote.git" update-ref "refs/notes/$LR" "$_ft"
  lsync "$LF/B" --dry-run; _c1="$LRC"; _o1="$LOUT"; _k1=1; lrefused && _k1=0
  lsync "$LF/B"
  if [ "$(git --git-dir="$LF/remote.git" cat-file -t "refs/notes/$LR")" = tree ] && [ "$_k1" = 0 ] && lrefused \
     && [ "$(lrev "$LF/B")" = "$_lpre" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F1(a) (−): origin ledger ref is a tree -> --dry-run and live both REFUSED rc 2, ledger unchanged, no temp ref" "c1=$_c1 o1=$_o1 rc=$LRC out=$LOUT"
  # F1(a'): the LOCAL ledger tip is not a commit either.
  mkledger sbadlocal
  lrec "$LF/A" "$ASHA" "branch/f1a2"
  lfetch "$LF/B"
  _fb="$(printf 'y' | git -C "$LF/B" hash-object -w --stdin)"
  _ft="$(printf '100644 blob %s\tfoo\n' "$_fb" | git -C "$LF/B" mktree)"
  git -C "$LF/B" update-ref "refs/notes/$LR" "$_ft"
  lsync "$LF/B" --dry-run
  if [ "$(git -C "$LF/B" cat-file -t "refs/notes/$LR")" = tree ] && lrefused && [ "$(lrev "$LF/B")" = "$_ft" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F1(a') (−): local ledger tip is a tree -> REFUSED rc 2, ledger unchanged" "rc=$LRC out=$LOUT"

  # F1(b): the voided-history `git log` fails -> refused (old code: history empty -> WOULD candidate).
  mkledger sf1b
  lrec "$LF/A" "$ASHA" "branch/f1b"
  lfetch "$LF/B"
  lgid git --git-dir="$LF/remote.git" notes --ref="$LR" remove "$ASHA"
  lrec "$LF/B" "$BSHA" "branch/f1bb" --no-push
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  _lpre="$(lrev "$LF/B")"
  lsyncf "$LF/B" log --dry-run
  if [ "$_anc" = 0 ] && lrefused && [ "$(lrev "$LF/B")" = "$_lpre" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F1(b) (−): the voided-history git log fails -> REFUSED rc 2, never WOULD candidate, ledger unchanged" "anc=$_anc rc=$LRC out=$LOUT"
  # F1(c): the classifying diff-tree fails (old code: no shas -> CAS to origin's tip, dropping local).
  ltwinfix sf1c
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  _lpre="$(lrev "$LF/B")"
  lsyncf "$LF/B" diff-tree
  if [ "$_anc" = 0 ] && lrefused && [ "$(lrev "$LF/B")" = "$_lpre" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F1(c) (−): the classifying git diff-tree fails -> REFUSED rc 2, ledger unchanged" "anc=$_anc rc=$LRC out=$LOUT"
  # F1(d): cat-file of a note blob fails.  F1(e): ls-tree fails.  Old code: both sides empty -> silently skipped.
  ltwinfix sf1d
  _lpre="$(lrev "$LF/B")"
  lsyncf "$LF/B" cat-file --dry-run; _c1="$LRC"; _o1="$LOUT"; _k1=1; lrefused && _k1=0
  _k2=1; printf '%s' "$_o1" | grep -q "cannot read origin's note blob" && _k2=0
  lsyncf "$LF/B" ls-tree --dry-run
  # C1: each refusal is asserted by ITS OWN message, so the leg isolates the specific rc check (a
  # generic REFUSED would stay green if the origin ls-tree check were dropped and the local one caught it).
  if [ "$_k1" = 0 ] && [ "$_k2" = 0 ] && lrefused && printf '%s' "$LOUT" | grep -q "cannot list origin's ledger tree" \
     && [ "$(lrev "$LF/B")" = "$_lpre" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F1(d,e) (−): a failed cat-file / ls-tree -> REFUSED rc 2 by its own message, ledger unchanged (never a silent skip)" "c1=$_c1 o1=$_o1 rc=$LRC out=$LOUT"
  # F1(f): the fast-forward ancestry probe errors (rc 128, not 1) -> refused, not read as "diverged".
  mkledger sf1f
  lrec "$LF/A" "$ASHA" "branch/f1f"
  lfetch "$LF/B"
  la2 "$LF/A"; _a2="$(git -C "$LF/A" rev-parse HEAD)"
  lrec "$LF/A" "$_a2" "branch/f1fb"
  _lpre="$(lrev "$LF/B")"
  lsyncf "$LF/B" merge-base --dry-run
  if [ "$_lpre" != "$(rrev "$LF")" ] && lrefused && ! printf '%s' "$LOUT" | grep -q 'WOULD' && [ "$(lrev "$LF/B")" = "$_lpre" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F1(f) (−): a failing merge-base is REFUSED rc 2 (not read as diverged), ledger unchanged" "rc=$LRC out=$LOUT"

  # F2(a) (converted in T2 from the T1 "publish step not yet built" stop): live, publish-only (local
  # strictly ahead) -> PUBLISHED: origin gains exactly the one new note, its new tip has ONE parent (its
  # old tip), the local ledger equals origin's, and no backup ref exists (nothing was dropped).
  mkledger sf2a
  lrec "$LF/A" "$ASHA" "branch/f2a"
  lfetch "$LF/B"
  lrec "$LF/B" "$BSHA" "branch/f2ab" --no-push
  _lpre="$(lrev "$LF/B")"; _rpre="$(rrev "$LF")"; _lb="$(git -C "$LF/B" notes --ref="$LR" list "$BSHA")"
  lsync "$LF/B"
  _np="$(git --git-dir="$LF/remote.git" cat-file -p "refs/notes/$LR" | grep -c '^parent ' || true)"
  if [ "$_lpre" != "$_rpre" ] && git -C "$LF/B" merge-base --is-ancestor "$_rpre" "$_lpre" && [ "$LRC" = 0 ] \
     && printf '%s' "$LOUT" | grep -q "published $BSHA" && [ "$_np" = 1 ] \
     && [ "$(git --git-dir="$LF/remote.git" rev-parse "refs/notes/$LR^")" = "$_rpre" ] \
     && [ "$(git --git-dir="$LF/remote.git" notes --ref="$LR" list "$BSHA")" = "$_lb" ] \
     && [ "$(lrev "$LF/B")" = "$(rrev "$LF")" ] \
     && [ -z "$(git -C "$LF/B" for-each-ref 'refs/kit/promotions-presync-*')" ] \
     && printf '%s' "$LOUT" | grep -q 'sync: reconciled — 1 published, 0 origin-wins, 0 discarded (no backup)'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F2(a) (+): live publish-only -> rc 0, note published byte-identical, one parent = origin's old tip, local == origin, no backup" "np=$_np rc=$LRC out=$LOUT"
  # F2(b) (converted): live, origin has NO ledger ref, a local record exists -> the push CREATES the ref
  # (a root commit: no parent), local == origin, one `published` line.
  mkledger sf2b
  lrec "$LF/B" "$BSHA" "branch/f2b" --no-push
  _lb="$(git -C "$LF/B" notes --ref="$LR" list "$BSHA")"
  lsync "$LF/B"
  if [ "$(git --git-dir="$LF/remote.git" cat-file -p "refs/notes/$LR" 2>/dev/null | grep -c '^parent ')" = 0 ] \
     && [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q "published $BSHA" && [ "$(rrev "$LF")" != none ] \
     && [ "$(git --git-dir="$LF/remote.git" notes --ref="$LR" list "$BSHA")" = "$_lb" ] \
     && [ "$(lrev "$LF/B")" = "$(rrev "$LF")" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F2(b) (+): live, origin has no ledger + a local record -> rc 0, ref created as a root commit, note byte-identical, local == origin" "rc=$LRC out=$LOUT"

  # F3: a note origin carried ONLY inside a merge commit (added and removed by merges) is still VOIDED.
  mkledger sf3
  lrec "$LF/A" "$ASHA" "branch/f3"
  lfetch "$LF/B"
  _rg="$LF/remote.git"
  _t1="$(git --git-dir="$_rg" rev-parse "refs/notes/$LR^{tree}")"
  _e="$(git --git-dir="$_rg" mktree </dev/null)"
  _e1="$(lgid git --git-dir="$_rg" commit-tree "$_e" -m e1)"; _e2="$(lgid git --git-dir="$_rg" commit-tree "$_e" -m e2)"
  _e3="$(lgid git --git-dir="$_rg" commit-tree "$_e" -m e3)"
  _m1="$(lgid git --git-dir="$_rg" commit-tree "$_t1" -p "$_e1" -p "$_e2" -m carried)"
  _m2="$(lgid git --git-dir="$_rg" commit-tree "$_e" -p "$_m1" -p "$_e3" -m voided)"
  git --git-dir="$_rg" update-ref "refs/notes/$LR" "$_m2"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  _lpre="$(lrev "$LF/B")"
  lsync "$LF/B" --dry-run
  if [ "$_anc" = 0 ] && [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q "REFUSED $ASHA" \
     && printf '%s' "$LOUT" | grep -q 'VOIDED upstream' && [ "$(lrev "$LF/B")" = "$_lpre" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F3 (−): a note carried only by merge commits and removed by a merge is VOIDED (git log -m), rc 2" "anc=$_anc rc=$LRC out=$LOUT"

  # F4: an origin notes-tree entry named '*' must not glob-expand into the clone's files (a file named
  # like a real sha would be classified twice). Exactly ONE `candidate` line for that sha.
  mkledger sf4
  lrec "$LF/B" "$BSHA" "branch/f4" --no-push
  : > "$LF/B/$BSHA"
  _fb="$(printf 'z' | git --git-dir="$LF/remote.git" hash-object -w --stdin)"
  _ft="$(printf '100644 blob %s\t*\n' "$_fb" | git --git-dir="$LF/remote.git" mktree)"
  _fc2="$(lgid git --git-dir="$LF/remote.git" commit-tree "$_ft" -m star)"
  git --git-dir="$LF/remote.git" update-ref "refs/notes/$LR" "$_fc2"
  lsync "$LF/B" --dry-run
  _n="$(printf '%s\n' "$LOUT" | grep -c "candidate $BSHA")"
  if [ "$LRC" = 0 ] && [ "$_n" = 1 ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F4 (−): a '*' path in origin's tree is not pathname-expanded (exactly one candidate line, rc 0)" "n=$_n rc=$LRC out=$LOUT"

  # F7: a twin differing ONLY in trailing newlines is a differing blob with the same identity: reported.
  mkledger sf7
  lrec "$LF/A" "$ASHA" "branch/f7"
  git -C "$LF/A" notes --ref="$LR" show "$ASHA" > "$LF/f7body.txt"
  printf '\n' >> "$LF/f7body.txt"
  _fb="$(git -C "$LF/B" hash-object -w "$LF/f7body.txt")"
  GIT_COMMITTER_DATE="2001-01-01T00:00:00" GIT_AUTHOR_DATE="2001-01-01T00:00:00" \
    git -C "$LF/B" notes --ref="$LR" add -f -C "$_fb" "$ASHA"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  _sa="$(git -C "$LF/A" notes --ref="$LR" show "$ASHA" | wc -c)"; _sb="$(git -C "$LF/B" notes --ref="$LR" show "$ASHA" | wc -c)"
  lsync "$LF/B" --dry-run
  if [ "$_anc" = 0 ] && [ "$_sa" != "$_sb" ] && [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q "WOULD twin-origin-wins $ASHA"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F7 (+): a twin differing only in trailing newlines (blob ids differ) still reports twin-origin-wins" "anc=$_anc sa=$_sa sb=$_sb rc=$LRC out=$LOUT"

  # =====================================================================================
  # sync, T2: re-validate (V1-V7), build on refs/notes/kit-sync-$$, back up (R2), swap, publish.
  # Every refusal leg builds a DIVERGED fixture whose local-only note is written by the REAL
  # `record --no-push` (so the candidate is valid until the leg damages exactly one thing), asserts the
  # ldiverged positive anchor, and asserts NOTHING moved: local ledger, origin ledger, both ref lists.
  # =====================================================================================
  rrefs() { git --git-dir="$LF/remote.git" for-each-ref --format='%(refname) %(objectname)'; }
  # lfix <name>: origin holds records on ASHA and a2 (published); B holds a local-only record on BSHA.
  lfix() {
    mkledger "$1"
    lrec "$LF/A" "$ASHA" "branch/$1a"
    lfetch "$LF/B"
    la2 "$LF/A"; _fa2="$(git -C "$LF/A" rev-parse HEAD)"
    lrec "$LF/A" "$_fa2" "branch/$1b"
    lrec "$LF/B" "$BSHA" "branch/$1c" --no-push
  }
  # lmut <clone> <sha> <sed-script>: rewrite that note's body (written DIRECTLY, bypassing record).
  lmut() {
    git -C "$1" notes --ref="$LR" show "$2" | sed "$3" > "$LF/mut.txt"
    git -C "$1" notes --ref="$LR" add -f -F "$LF/mut.txt" "$2"
  }
  # lsnap: snapshot local (B) + origin state before a sync; lunmoved: 0 when both are byte-identical after.
  lsnap() { _s_l="$(lrev "$LF/B")"; _s_lr="$(lrefs "$LF/B")"; _s_rr="$(rrefs)"; }
  lunmoved() { [ "$(lrev "$LF/B")" = "$_s_l" ] && [ "$(lrefs "$LF/B")" = "$_s_lr" ] && [ "$(rrefs)" = "$_s_rr" ]; }
  # lvrefused <field>: the last sync refused THIS candidate on that field, named both remedies, moved nothing.
  lvrefused() {
    [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q "REFUSED $BSHA" && printf '%s' "$LOUT" | grep -q "$1" \
      && printf '%s' "$LOUT" | grep -q "sync --discard-local $BSHA" && printf '%s' "$LOUT" | grep -q 'promotion-verify.sh record' \
      && ! printf '%s' "$LOUT" | grep -q "published" && lunmoved
  }
  # lvcase <description> <field>: the diverged anchor, then one sync that must refuse the candidate on <field>.
  lvcase() {
    if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
    lsnap; lsync "$LF/B"
    if [ "$_anc" = 0 ] && lvrefused "$2"; then _lc=0; else _lc=1; fi
    lpass "$_lc" "$1" "anc=$_anc rc=$LRC out=$LOUT"
  }

  # (+) T2-1: a valid local-only candidate (real `record --no-push`, I6 round trip) on a DIVERGED
  # ledger is published: origin has the note byte-identical, its new tip has EXACTLY ONE parent (its old
  # tip), no merge commit, every note origin already had is byte-identical (I1), and origin's ref list
  # differs ONLY in the ledger ref (I3). Also (9b): a run that dropped nothing makes no backup.
  lfix s2pub
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  _rpre="$(rrev "$LF")"; _lb="$(git -C "$LF/B" notes --ref="$LR" list "$BSHA")"
  _oa="$(git --git-dir="$LF/remote.git" notes --ref="$LR" list "$ASHA")"; _o2="$(git --git-dir="$LF/remote.git" notes --ref="$LR" list "$_fa2")"
  _rx="$(rrefs | grep -v " *refs/notes/$LR " || true)"
  lsync "$LF/B"
  _np="$(git --git-dir="$LF/remote.git" cat-file -p "refs/notes/$LR" | grep -c '^parent ' || true)"
  if [ "$_anc" = 0 ] && [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q "published $BSHA" \
     && [ "$(git --git-dir="$LF/remote.git" notes --ref="$LR" list "$BSHA")" = "$_lb" ] \
     && [ "$_np" = 1 ] && [ "$(git --git-dir="$LF/remote.git" rev-parse "refs/notes/$LR^")" = "$_rpre" ] \
     && [ "$(git --git-dir="$LF/remote.git" notes --ref="$LR" list "$ASHA")" = "$_oa" ] \
     && [ "$(git --git-dir="$LF/remote.git" notes --ref="$LR" list "$_fa2")" = "$_o2" ] \
     && [ "$(rrefs | grep -v " *refs/notes/$LR " || true)" = "$_rx" ] \
     && [ "$(lrev "$LF/B")" = "$(rrev "$LF")" ] && [ -z "$(git -C "$LF/B" for-each-ref 'refs/kit/promotions-presync-*')" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (+): a valid record --no-push candidate on a diverged ledger is published byte-identical; one parent = origin's old tip; I1 old notes identical; I3 only the ledger ref moved; no backup" "anc=$_anc np=$_np rc=$LRC out=$LOUT"

  # (−) T2-2: a FORGED [authenticated: github-review] on a branch-scoped note (body written directly).
  lfix s2forge; lforge "$LF/B" "$BSHA" "authenticated: github-review"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsnap; lsync "$LF/B"
  if [ "$_anc" = 0 ] && lvrefused 'approved-by'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (−): forged [authenticated: github-review] on a branch scope -> rc 2 naming approved-by, sha, both remedies; nothing moved" "anc=$_anc rc=$LRC out=$LOUT"
  # (−) T2-3: a forged [signed: gpg] (the fixture commits are unsigned: commit.gpgsign false).
  lfix s2gpg; lforge "$LF/B" "$BSHA" "signed: gpg"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsnap; lsync "$LF/B"
  if [ "$_anc" = 0 ] && lvrefused 'approved-by'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (−): forged [signed: gpg] on an unsigned commit -> rc 2 naming approved-by, nothing moved" "anc=$_anc rc=$LRC out=$LOUT"
  # (−) T2-4: an approved-tree that is 40-hex but not the commit's tree.
  lfix s2tree; lmut "$LF/B" "$BSHA" 's/^approved-tree: .*/approved-tree: 0000000000000000000000000000000000000000/'
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsnap; lsync "$LF/B"
  if [ "$_anc" = 0 ] && lvrefused 'approved-tree'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (−): approved-tree mismatch -> rc 2 naming approved-tree, nothing moved" "anc=$_anc rc=$LRC out=$LOUT"
  # (−) T2-5: kit-row mismatch — the commit carries `Kit-Row: A`, the note says B (anchor: the note said A first).
  mkledger s2row
  lrec "$LF/A" "$ASHA" "branch/s2rowa"; lfetch "$LF/B"
  la2 "$LF/A"; _fa2="$(git -C "$LF/A" rev-parse HEAD)"
  lrec "$LF/A" "$_fa2" "branch/s2rowb"
  printf 'b-row change\n' >> "$LF/B/docs/architecture/x-design.md"; git -C "$LF/B" add docs/architecture/x-design.md
  git -C "$LF/B" commit -q -m b-row -m "Kit-Row: A"; BSHA="$(git -C "$LF/B" rev-parse HEAD)"
  lrec "$LF/B" "$BSHA" "branch/s2rowc" --no-push
  _kanc=1; git -C "$LF/B" notes --ref="$LR" show "$BSHA" | grep -q '^kit-row: A$' && _kanc=0
  lmut "$LF/B" "$BSHA" 's/^kit-row: .*/kit-row: B/'
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsnap; lsync "$LF/B"
  if [ "$_anc" = 0 ] && [ "$_kanc" = 0 ] && lvrefused 'kit-row'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (−): kit-row mismatch (commit trailer A, note B) -> rc 2 naming kit-row, nothing moved" "anc=$_anc kanc=$_kanc rc=$LRC out=$LOUT"
  BSHA="$(git -C "$LF/B" rev-parse 'HEAD~1')"   # restore the plain b-side commit for later fixtures' lrec
  # (−) T2-6: an injected 13th line (a second approved-by:).
  lfix s2inj; { git -C "$LF/B" notes --ref="$LR" show "$BSHA"; echo 'approved-by: x [signed: gpg]'; } > "$LF/inj.txt"
  git -C "$LF/B" notes --ref="$LR" add -f -F "$LF/inj.txt" "$BSHA"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsnap; lsync "$LF/B"
  if [ "$_anc" = 0 ] && lvrefused 'grammar'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (−): an injected 13th line -> rc 2 naming the grammar (V1), nothing moved" "anc=$_anc rc=$LRC out=$LOUT"
  # (−) T2-7 (I6, the negative half; the positive half is T2-1): rename ONE key of a record's own note
  # and V1 rejects it — so if `record` ever changes a key, the validator reds instead of silently drifting.
  lfix s2key; lmut "$LF/B" "$BSHA" 's/^gate: /gaet: /'
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsnap; lsync "$LF/B"
  if [ "$_anc" = 0 ] && lvrefused 'grammar'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (−): one renamed key (gate: -> gaet:) -> rc 2 naming the grammar (V1), nothing moved" "anc=$_anc rc=$LRC out=$LOUT"
  # (−) T2-7b: --dry-run validates too (it is the owner's verification surface) — a forged note is refused, not WOULD-published.
  lfix s2dry; lforge "$LF/B" "$BSHA" "signed: gpg"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsnap; lsync "$LF/B" --dry-run
  if [ "$_anc" = 0 ] && lvrefused 'approved-by' && ! printf '%s' "$LOUT" | grep -q 'WOULD published'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (−): --dry-run re-validates candidates (a forged label is refused, rc 2, nothing moved)" "rc=$LRC out=$LOUT"
  # (+) T2-7c: --discard-local on the invalid candidate is its remedy (I2): the run then reconciles, a backup
  # exists, and origin never receives the forged note.
  lfix s2rem; lforge "$LF/B" "$BSHA" "signed: gpg"
  _rpre="$(rrev "$LF")"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsync "$LF/B" --discard-local "$BSHA"
  if [ "$_anc" = 0 ] && [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q "discarded-local $BSHA" && [ -z "$(git --git-dir="$LF/remote.git" notes --ref="$LR" list "$BSHA" 2>/dev/null)" ] \
     && [ "$(lrev "$LF/B")" = "$(rrev "$LF")" ] && [ "$(rrev "$LF")" = "$_rpre" ] \
     && [ "$(git -C "$LF/B" for-each-ref 'refs/kit/promotions-presync-*' | wc -l | tr -d ' ')" = 1 ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (+): --discard-local <invalid candidate> is the remedy: rc 0, origin never sees the note, one backup ref" "rc=$LRC out=$LOUT"

  # GO-IDENTITY-AND-LAND-SOD L8: the note grammar is 12 lines (legacy, no go-by) OR 13 (go-by at line 5).
  # (+) a LEGACY 12-line note (the go-by line removed from a real record's body) still publishes; (+) a
  # 13-line note carrying `go-by: <name> [self-asserted]` publishes byte-identical; (−) any other label on
  # go-by is refused naming it (the kit never authenticates the GO-giver); (−) a same-sha twin differing
  # ONLY in go-by is a different GO (identity), while one differing only in go-by-less legacy form is not.
  lfix s8leg; lmut "$LF/B" "$BSHA" '/^go-by: /d'
  _l8n="$(git -C "$LF/B" notes --ref="$LR" show "$BSHA" | wc -l | tr -d ' ')"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsync "$LF/B"
  if [ "$_anc" = 0 ] && [ "$_l8n" = 12 ] && [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q "published $BSHA" && rnote "$LF" "$BSHA"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync L8(a) (+): a LEGACY 12-line note (no go-by line) is accepted and published" "anc=$_anc lines=$_l8n rc=$LRC out=$LOUT"
  mkledger s8new
  lrec "$LF/A" "$ASHA" "branch/s8na"
  lrec "$LF/B" "$BSHA" "branch/s8nb" --no-push --go-by "owner-login"
  _l8n="$(git -C "$LF/B" notes --ref="$LR" show "$BSHA" | wc -l | tr -d ' ')"
  _l8g="$(git -C "$LF/B" notes --ref="$LR" show "$BSHA" | sed -n '5p')"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsync "$LF/B"
  if [ "$_anc" = 0 ] && [ "$_l8n" = 13 ] && [ "$_l8g" = 'go-by: owner-login [self-asserted]' ] && [ "$LRC" = 0 ] \
     && printf '%s' "$LOUT" | grep -q "published $BSHA" && [ "$(git --git-dir="$LF/remote.git" notes --ref="$LR" show "$BSHA" | sed -n '5p')" = "$_l8g" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync L8(b) (+): a 13-line note with 'go-by: owner-login [self-asserted]' at line 5 is accepted and published byte-identical" "anc=$_anc lines=$_l8n l5=$_l8g rc=$LRC out=$LOUT"
  for _l8lab in 'authenticated: github-review' 'committer' 'signed: gpg'; do
    _l8k=$((${_l8k:-0} + 1))
    lfix "s8forge$_l8k"; lrec "$LF/B" "$BSHA" "branch/s8forge${_l8k}c" --no-push --go-by "owner-login"   # lfix's own scope: this re-record supersedes (SWAS-323)
    lmut "$LF/B" "$BSHA" "s/^go-by: .*/go-by: owner-login [$_l8lab]/"
    lvcase "sync L8(c) (−): a go-by carrying [$_l8lab] is refused naming go-by (the GO-giver is never authenticated), nothing moved" 'go-by'
  done
  lfix s8blank; lrec "$LF/B" "$BSHA" "branch/s8blankc" --no-push --go-by "owner-login"
  lmut "$LF/B" "$BSHA" 's/^go-by: .*/go-by: owner-login/'
  lvcase "sync L8(c) (−): a go-by with no [self-asserted] label is refused naming go-by" 'go-by'
  # SWAS-902: `sync` re-validates a LOCAL-ONLY note as what record would write NOW, and record now refuses template text in angle brackets.
  # The notes are written directly (bypassing record); each cell refuses on the new line, publishes nothing, and moves nothing.
  lfix s902g; lmut "$LF/B" "$BSHA" 's/^go-by: .*/go-by: <your name> [self-asserted]/'
  lvcase "sync SWAS-902 (−): a local-only note whose go-by holds '<your name>' is refused naming the go-by field, nothing moved" 'go-by: template text in angle brackets'
  lfix s902t; lmut "$LF/B" "$BSHA" 's/^approval-token: .*/approval-token: "<your approval, in your words>"/'
  lvcase "sync SWAS-902 (−): a local-only note whose token holds template text is refused naming approval-token, nothing moved" 'approval-token: template text in angle brackets'
  # Mutant 3: the sync leg removed -> the same go-by note is PUBLISHED (the cell above fails against it; rc 0 and `published` prove the leg alone refused it).
  lfix s902m; lmut "$LF/B" "$BSHA" 's/^go-by: .*/go-by: <your name> [self-asserted]/'
  rm -rf "$D/phmut"; mkdir -p "$D/phmut/scripts" "$D/phmut/conformance"
  cp "$VERIFY" "$D/phmut/orig.sh"; cp "$(dirname "$VERIFY")/../conformance/ci-classify-changes.sh" "$D/phmut/conformance/ci-classify-changes.sh" 2>/dev/null || true
  sed 's|^  _pv_vc_placeholder .*# PV-PLACEHOLDER-SYNC.*$|  true|' "$D/phmut/orig.sh" > "$D/phmut/scripts/promotion-verify.sh"
  if cmp -s "$D/phmut/orig.sh" "$D/phmut/scripts/promotion-verify.sh"; then
    echo "FAIL: M-PH3: the mutant script changed nothing (it no longer matches the producer)"; st=1
  else
    if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
    _ph_v="$VERIFY"; VERIFY="$D/phmut/scripts/promotion-verify.sh"; lsync "$LF/B"; VERIFY="$_ph_v"
    if [ "$_anc" = 0 ] && [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q "published $BSHA"; then _lc=0; else _lc=1; fi
    lpass "$_lc" "sync M-PH3 (mutant): the sync leg removed -> the template-text go-by note is published (the mutant is killed)" "anc=$_anc rc=$LRC out=$LOUT"
  fi
  rm -rf "$D/phmut" 2>/dev/null || true
  # SAST-PARSE-MERGE-TOOL: one refuse cell per vet arm whose one-line `case` was split. Each pins its OWN message (a rewrite that
  # widens or drops a match turns it red); the cells pass on the code before the split too: they pin behaviour, not red-first.
  lfix s8brk; lrec "$LF/B" "$BSHA" "branch/s8brkc" --no-push --go-by "owner-login"
  lmut "$LF/B" "$BSHA" 's/^go-by: .*/go-by: owner[login [self-asserted]/'
  lvcase "sync SAST(−): a bracket inside the go-by name is refused with its own line" 'a bracket inside the name'
  lfix s8nolab; lrec "$LF/B" "$BSHA" "branch/s8nolabc" --no-push --go-by "owner-login"
  lmut "$LF/B" "$BSHA" 's/^approved-by: .*/approved-by: nolabel/'
  lvcase "sync SAST(−): an approved-by with no [label] is refused with its own line" "not '<id>"
  lfix s8idbr; lrec "$LF/B" "$BSHA" "branch/s8idbrc" --no-push --go-by "owner-login"
  lmut "$LF/B" "$BSHA" 's/^approved-by: .*/approved-by: a[b [self-asserted]/'
  lvcase "sync SAST(−): a bracket inside the approved-by id is refused with its own line" 'a bracket inside the id or the label'
  lfix s8dash; lrec "$LF/B" "$BSHA" "branch/s8dashc" --no-push --go-by "owner-login"
  lmut "$LF/B" "$BSHA" 's/^approved-sha: .*/approved-sha: -abc/'
  lvcase "sync SAST(−): an approved-sha starting with '-' is refused with its own line" "starts with '-'"
  lfix s8nom; lsync "$LF/B" --dry-run --discard-local 1234567890123456789012345678901234567890
  if [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -qF -e "--discard-local 1234567890123456789012345678901234567890 matched no refused or candidate record"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync SAST(+): a --discard-local naming no refused or candidate record is noted, not silently dropped (rc 0)" "rc=$LRC out=$LOUT"
  mkledger s8twin
  lrec "$LF/A" "$ASHA" "branch/s8t" --go-by "owner-login"
  lrec "$LF/B" "$ASHA" "branch/s8t" --no-push --token "local token" --go-by "SomeoneElse"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  _lpre="$(lrev "$LF/B")"
  lsync "$LF/B"
  if [ "$_anc" = 0 ] && [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'DIFFERENT identity' && printf '%s' "$LOUT" | grep -q "REFUSED $ASHA" \
     && printf '%s' "$LOUT" | grep -q 'go-by: SomeoneElse \[self-asserted\]' && [ "$(lrev "$LF/B")" = "$_lpre" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync L8(d) (−): a same-sha twin differing ONLY in go-by is a different GO -> rc 2 DIFFERENT identity, both notes printed, ledger untouched" "anc=$_anc rc=$LRC out=$LOUT"
  mkledger s8twin2
  lrec "$LF/A" "$ASHA" "branch/s8t2" --go-by "owner-login"
  lrec "$LF/B" "$ASHA" "branch/s8t2" --no-push --token "local token" --go-by "owner-login"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsync "$LF/B"
  if [ "$_anc" = 0 ] && [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q "twin-origin-wins $ASHA"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync L8(d) (+): the same twin with the SAME go-by is a free-text twin -> twin-origin-wins (the identity field is not a refuse-all)" "anc=$_anc rc=$LRC out=$LOUT"

  # SWAS-727 (test 13): `sync` gains two shapes, each the 13 lines plus lines after recorded-at: a ONE-ACT note (14 lines, `go-act: review`, one
  # authenticated login in go-by and approved-by, the token exactly "forge-review:<digits>") and a HELD-THEN-TYPED note (16 lines, `go-act: separate`,
  # `go-words` one quoted line of at most 1000 bytes, `go-words-sha256` 64 lowercase hex). A legacy note syncs unchanged (L8(a) above). The notes are
  # written DIRECTLY (bypassing record) from a real record's body, so each cell damages exactly one thing. The one-act shape also needs the forge to
  # re-derive its label (V7), so those cells put a `gh` shim on PATH that answers one APPROVED review by owner-rev on the sha under test.
  lgo() {  # <clone> <sha> <sed-script> [<line to append>...]
    _gc="$1"; _gs="$2"; _gsed="$3"; shift 3
    { git -C "$_gc" notes --ref="$LR" show "$_gs" | sed "$_gsed"; for _gl in "$@"; do printf '%s\n' "$_gl"; done; } > "$LF/go.txt"
    git -C "$_gc" notes --ref="$LR" add -f -F "$LF/go.txt" "$_gs"
  }
  _H64=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  _GH727="$LROOT/gh727"; mkdir -p "$_GH727"
  printf '%s\n' '#!/bin/sh' 'd=$(dirname "$0")' 'case "$*" in' \
    '  */reviews*) printf '"'"'APPROVED\t%s\towner-rev\tUser\t5551\n'"'"' "$(cat "$d/sha")" ;;' \
    '  *) printf '"'"'SeaBrad72\n'"'"' ;;' 'esac' > "$_GH727/gh"
  chmod +x "$_GH727/gh"
  _RVSED='s/^approved-by: .*/approved-by: owner-rev [authenticated: github-review]/; s/^go-by: .*/go-by: owner-rev [authenticated: github-review]/; s/^approval-token: .*/approval-token: "forge-review:5551"/; s/^scope: .*/scope: PR #260/'
  _HSED='s/^go-by: .*/go-by: owner-login [self-asserted]/'
  # (+) the held-then-typed shape: 16 lines, accepted and published byte-identical
  lfix s13held; lgo "$LF/B" "$BSHA" "$_HSED" 'go-act: separate' 'go-words: "GO, with the full security read"' "go-words-sha256: $_H64"
  _l13n="$(git -C "$LF/B" notes --ref="$LR" show "$BSHA" | wc -l | tr -d ' ')"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsync "$LF/B"
  if [ "$_anc" = 0 ] && [ "$_l13n" = 16 ] && [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q "published $BSHA" \
     && [ "$(git --git-dir="$LF/remote.git" notes --ref="$LR" show "$BSHA" | sed -n '14p')" = 'go-act: separate' ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync 13(a) (+): a held-then-typed 16-line note (64-hex hash, one-line go-words) is accepted and published" "anc=$_anc lines=$_l13n rc=$LRC out=$LOUT"
  # (−) the same note damaged in exactly one place: a 63-char hash, an uppercase hash, 1010 bytes of words, unquoted words, a bare go-act line, an unknown go-act, no named giver
  lfix s13h63; lgo "$LF/B" "$BSHA" "$_HSED" 'go-act: separate' 'go-words: "GO"' "go-words-sha256: ${_H64%?}"
  lvcase "sync 13(b) (−): a 63-character go-words-sha256 is refused naming it, nothing moved" 'go-words-sha256'
  lfix s13hup; lgo "$LF/B" "$BSHA" "$_HSED" 'go-act: separate' 'go-words: "GO"' "go-words-sha256: $(printf '%s' "$_H64" | tr a-f A-F)"
  lvcase "sync 13(b) (−): an uppercase go-words-sha256 is refused naming it, nothing moved" 'go-words-sha256'
  lfix s13hlong; lgo "$LF/B" "$BSHA" "$_HSED" 'go-act: separate' "go-words: \"$(awk 'BEGIN { for (i = 0; i < 1010; i++) printf "x" }')\"" "go-words-sha256: $_H64"
  lvcase "sync 13(b) (−): go-words of 1010 bytes is refused naming go-words, nothing moved" 'go-words'
  lfix s13hunq; lgo "$LF/B" "$BSHA" "$_HSED" 'go-act: separate' 'go-words: GO unquoted' "go-words-sha256: $_H64"
  lvcase "sync 13(b) (−): unquoted go-words is refused naming go-words, nothing moved" 'go-words'
  lfix s13hbare; lgo "$LF/B" "$BSHA" "$_HSED" 'go-act: separate'
  lvcase "sync 13(b) (−): go-act: separate with no go-words lines (14 lines) is refused as a grammar break, nothing moved" 'grammar'
  lfix s13hunk; lgo "$LF/B" "$BSHA" "$_HSED" 'go-act: maybe'
  lvcase "sync 13(b) (−): an unknown go-act value is refused naming go-act, nothing moved" 'go-act'
  lfix s13hnone; lgo "$LF/B" "$BSHA" 's/^zzz//' 'go-act: separate' 'go-words: "GO"' "go-words-sha256: $_H64"
  lvcase "sync 13(b) (−): a held-then-typed note with no named GO-giver is refused naming go-by, nothing moved" 'go-by'
  # (+) the one-act shape under the three conditions (go-act review, both labels authenticated, go-by = approved-by) with the forge answering
  lfix s13rev; printf '%s\n' "$BSHA" > "$_GH727/sha"; lgo "$LF/B" "$BSHA" "$_RVSED" 'go-act: review'
  _l13n="$(git -C "$LF/B" notes --ref="$LR" show "$BSHA" | wc -l | tr -d ' ')"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  _ppath="$PATH"; PATH="$_GH727:$PATH"; lsync "$LF/B"; PATH="$_ppath"
  if [ "$_anc" = 0 ] && [ "$_l13n" = 14 ] && [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q "published $BSHA" \
     && [ "$(git --git-dir="$LF/remote.git" notes --ref="$LR" show "$BSHA" | sed -n '14p')" = 'go-act: review' ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync 13(c) (+): a one-act 14-line note (go-act review, both labels authenticated, go-by = approved-by, token forge-review:<digits>) is accepted and published" "anc=$_anc lines=$_l13n rc=$LRC out=$LOUT"
  # (−) the one-act shape is not a way to publish a label the forge does not give: the same note with NO forge answer is refused at V7 (approved-by)
  lfix s13revnogh; lgo "$LF/B" "$BSHA" "$_RVSED" 'go-act: review'
  lvcase "sync 13(c) (−): the one-act note when the forge does not show the review (no gh shim) is refused naming approved-by" 'approved-by'
  # (−) each of the three conditions, one at a time (the forge answers throughout, so V7 is not the cause)
  lfix s13revdiff; printf '%s\n' "$BSHA" > "$_GH727/sha"; lgo "$LF/B" "$BSHA" "$_RVSED; s/^go-by: .*/go-by: someone-else [authenticated: github-review]/" 'go-act: review'
  _ppath="$PATH"; PATH="$_GH727:$PATH"; lvcase "sync 13(d) (−): a review-shaped note whose go-by differs from approved-by is refused naming go-by, nothing moved" 'go-by'; PATH="$_ppath"
  lfix s13revself; printf '%s\n' "$BSHA" > "$_GH727/sha"; lgo "$LF/B" "$BSHA" "$_RVSED; s/^go-by: .*/go-by: owner-rev [self-asserted]/" 'go-act: review'
  _ppath="$PATH"; PATH="$_GH727:$PATH"; lvcase "sync 13(d) (−): a review-shaped note whose go-by is [self-asserted] is refused naming go-by, nothing moved" 'go-by'; PATH="$_ppath"
  lfix s13revtok; printf '%s\n' "$BSHA" > "$_GH727/sha"; lgo "$LF/B" "$BSHA" "$_RVSED; s/^approval-token: .*/approval-token: \"GO: owner said so\"/" 'go-act: review'
  _ppath="$PATH"; PATH="$_GH727:$PATH"; lvcase "sync 13(d) (−): a review-shaped note whose token is not forge-review:<digits> is refused naming approval-token, nothing moved" 'approval-token'; PATH="$_ppath"
  lfix s13revtokx; printf '%s\n' "$BSHA" > "$_GH727/sha"; lgo "$LF/B" "$BSHA" "$_RVSED; s/^approval-token: .*/approval-token: \"forge-review:55x1\"/" 'go-act: review'
  _ppath="$PATH"; PATH="$_GH727:$PATH"; lvcase "sync 13(d) (−): a review-shaped note whose review id is not digits is refused naming approval-token, nothing moved" 'approval-token'; PATH="$_ppath"
  lfix s13revmore; printf '%s\n' "$BSHA" > "$_GH727/sha"; lgo "$LF/B" "$BSHA" "$_RVSED" 'go-act: review' 'go-words: "GO"'
  _ppath="$PATH"; PATH="$_GH727:$PATH"; lvcase "sync 13(d) (−): a one-act note with a 15th line is refused as a grammar break, nothing moved" 'grammar'; PATH="$_ppath"

  # SWAS-727: `trace` prints "GO = forge review <id> by <login>" for a one-act note, and nothing extra for any other (the prefix stays byte-stable).
  _T727="$D/trace727"; mkdir -p "$_T727"
  ( cd "$_T727" && git init -q && git config user.email t@e && git config user.name t && git config commit.gpgsign false \
      && printf 'a\n' > f.txt && git add f.txt && git commit -qm base ) >/dev/null 2>&1
  _t727s="$(git -C "$_T727" rev-parse HEAD)"
  ( cd "$_T727" && $VSH "$VERIFY" record --no-push --approved-sha "$_t727s" --approved-by owner-rev --gate release-candidate \
      --rung RC --class control-plane --scope "PR #260" --token GO --go-by owner >/dev/null 2>&1 )
  _t727o="$( cd "$_T727" && $VSH "$VERIFY" trace --ref "$_t727s" 2>&1 )" && _t727c=0 || _t727c=$?
  if [ "$_t727c" = 0 ] && ! printf '%s' "$_t727o" | grep -q 'GO = forge review'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "trace 727 (+): an ordinary note prints no 'GO = forge review' tail" "rc=$_t727c out=$_t727o"
  { git -C "$_T727" notes --ref=promotions show "$_t727s" | sed "$_RVSED"; printf '%s\n' 'go-act: review'; } > "$_T727/.n"
  git -C "$_T727" notes --ref=promotions add -f -F "$_T727/.n" "$_t727s"
  _t727o="$( cd "$_T727" && $VSH "$VERIFY" trace --ref "$_t727s" 2>&1 )" && _t727c=0 || _t727c=$?
  if [ "$_t727c" = 0 ] && printf '%s' "$_t727o" | grep -qF 'go-by: owner-rev [authenticated: github-review]  GO = forge review 5551 by owner-rev'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "trace 727 (+): a one-act note prints 'GO = forge review 5551 by owner-rev' at the end of the line" "rc=$_t727c out=$_t727o"
  { git -C "$_T727" notes --ref=promotions show "$_t727s" | sed 's/^approval-token: .*/approval-token: "forge-review:55x1"/'; } > "$_T727/.n"
  git -C "$_T727" notes --ref=promotions add -f -F "$_T727/.n" "$_t727s"
  _t727o="$( cd "$_T727" && $VSH "$VERIFY" trace --ref "$_t727s" 2>&1 )" && _t727c=0 || _t727c=$?
  if [ "$_t727c" = 0 ] && ! printf '%s' "$_t727o" | grep -q 'GO = forge review'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "trace 727 (−): a go-act review note whose token is not digits prints no GO tail (nothing is invented)" "rc=$_t727c out=$_t727o"

  # (−) T2-8: a non-fast-forward RACE. A holds a free-text twin of ASHA (so the run DROPS content and
  # makes a backup) plus a new record on a2; the racer (clone B, via A's reference-transaction hook)
  # records and PUBLISHES the instant A's CAS moves the ledger, so A's first push is rejected. A must
  # unwind, delete the backup THIS run made, retry once, and publish. Both records end on origin, and
  # exactly ONE backup ref survives (the retry's), never two.
  mkledger s2race
  lrec "$LF/A" "$ASHA" "branch/s2r1"
  lrec "$LF/B" "$BSHA" "branch/s2r2"
  lrec "$LF/A" "$ASHA" "branch/s2r1" --no-push --token "local twin"
  la2 "$LF/A"; _fa2="$(git -C "$LF/A" rev-parse HEAD)"
  lrec "$LF/A" "$_fa2" "branch/s2r3" --no-push
  if ldiverged "$LF/A"; then _anc=0; else _anc=1; fi
  _lpre="$(lrev "$LF/A")"
  lracer once
  lsync "$LF/A"
  _nb="$(git -C "$LF/A" for-each-ref 'refs/kit/promotions-presync-*' | wc -l | tr -d ' ')"
  if [ "$_anc" = 0 ] && [ -e "$LF/.raced" ] && [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q "published $_fa2" \
     && [ -n "$(git --git-dir="$LF/remote.git" notes --ref="$LR" list "$_fa2")" ] \
     && git --git-dir="$LF/remote.git" notes --ref="$LR" show "$BSHA" | grep -q 'scope: branch/racer-' \
     && [ "$(lrev "$LF/A")" = "$(rrev "$LF")" ] && [ "$_nb" = 1 ] \
     && [ "$(git -C "$LF/A" rev-parse "$(git -C "$LF/A" for-each-ref --format='%(refname)' 'refs/kit/promotions-presync-*')")" = "$_lpre" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (−): non-ff race -> first push rejected, unwound, backup of the failed attempt deleted, retried ONCE, published; both records on origin; exactly one backup" "anc=$_anc nb=$_nb rc=$LRC out=$LOUT"

  # (+) T2-9 + T2-10: R2 backup + I1/I3 in ONE run with a twin AND a candidate. The twin (differing local
  # bytes) is dropped for origin's, so a backup ref exists and points at the OLD local tip; the candidate is
  # published. Origin's twin note is byte-identical afterwards (I1), and origin's ref list differs from
  # before ONLY in the ledger ref (I3: no backup ref or temp ref is ever pushed).
  mkledger s2bk
  lrec "$LF/A" "$ASHA" "branch/s2bk"
  lrec "$LF/B" "$ASHA" "branch/s2bk" --no-push --token "local twin"
  lrec "$LF/B" "$BSHA" "branch/s2bk2" --no-push
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  _lpre="$(lrev "$LF/B")"; _oa="$(git --git-dir="$LF/remote.git" notes --ref="$LR" list "$ASHA")"; _rpre0="$(rrev "$LF")"
  _rx="$(rrefs | grep -v " *refs/notes/$LR " || true)"
  lsync "$LF/B"
  _bk="$(git -C "$LF/B" for-each-ref --format='%(refname)' 'refs/kit/promotions-presync-*')"
  if [ "$_anc" = 0 ] && [ "$LRC" = 0 ] && [ -n "$_bk" ] && [ "$(printf '%s\n' "$_bk" | wc -l | tr -d ' ')" = 1 ] \
     && [ "$(git -C "$LF/B" rev-parse "$_bk")" = "$_lpre" ] \
     && printf '%s' "$LOUT" | grep -q "sync: reconciled — 1 published, 1 origin-wins, 0 discarded (backup $_bk)"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (+): R2 — a twin-origin-wins with differing bytes leaves ONE backup ref at the old local tip; final line names it" "anc=$_anc bk=$_bk rc=$LRC out=$LOUT"
  if [ "$(rrev "$LF")" != "$_rpre0" ] && [ "$LRC" = 0 ] && [ -n "$(git --git-dir="$LF/remote.git" notes --ref="$LR" list "$BSHA")" ] \
     && [ "$(git --git-dir="$LF/remote.git" notes --ref="$LR" list "$ASHA")" = "$_oa" ] \
     && [ "$(rrefs | grep -v " *refs/notes/$LR " || true)" = "$_rx" ] \
     && [ -z "$(git --git-dir="$LF/remote.git" for-each-ref 'refs/kit/*')" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (+): I1 + I3 — origin's twin note byte-identical after; origin ref list differs only in the ledger; no backup/temp ref pushed" "rc=$LRC out=$LOUT"

  # (−) T2-11: origin has NO ledger and only discards would remain -> rc 2, the local ledger is never deleted.
  mkledger s2nolg
  lrec "$LF/B" "$BSHA" "branch/s2n" --no-push
  lsnap; lsync "$LF/B" --discard-local "$BSHA"
  if [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'origin has no ledger and nothing would remain to publish' \
     && printf '%s' "$LOUT" | grep -q 'record afresh' && [ "$(rrev "$LF")" = none ] && lunmoved \
     && [ -z "$(git -C "$LF/B" for-each-ref 'refs/kit/promotions-presync-*')" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (−): origin has no ledger + only a discard -> rc 2 'nothing would remain to publish', local ledger kept, no backup" "rc=$LRC out=$LOUT"

  # (−) C2: a BROKEN local ledger ref (points at a missing object) refuses with its own message; it must
  # never read as ABSENT (the old for-each-ref read skipped/blurred a broken ref).
  mkledger s2brk
  lrec "$LF/A" "$ASHA" "branch/s2brk"
  lfetch "$LF/B"
  printf '%s\n' 1111111111111111111111111111111111111111 > "$LF/B/.git/refs/notes/$LR"
  lsync "$LF/B"
  if [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'ledger ref .* is broken' \
     && [ "$(cat "$LF/B/.git/refs/notes/$LR")" = 1111111111111111111111111111111111111111 ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync C2 (−): a broken local ledger ref -> rc 2 'ledger ref ... is broken', the ref is left as found (never read as absent)" "rc=$LRC out=$LOUT"

  # (−) C9: a TERM during sync cleans up its temp refs AND EXITS 143 (the trap used to clean up and CONTINUE).
  # A diverged twin fixture; the shimmed ls-tree sleeps 3s (scratch ref already fetched), TERM lands, and the
  # script must stop: ledger unchanged (the old code went on to CAS it to origin's tip), no temp ref left.
  # (INT is not tested: a non-interactive background shell starts with SIGINT ignored, so it cannot be trapped.)
  ltwinfix s2term
  lshim
  _lpre="$(lrev "$LF/B")"
  ( cd "$LF/B" && PATH="$LROOT/shim:$PATH" SLEEP_GIT_SUB=ls-tree PROMOTION_NOTES_REF="$LR" exec $VSH "$VERIFY" sync > "$LF/term.out" 2>&1 ) &
  _tp=$!
  sleep 1
  kill -TERM "$_tp" 2>/dev/null || true
  if wait "$_tp"; then _trc=0; else _trc=$?; fi
  if [ "$_trc" = 143 ] && [ "$(lrev "$LF/B")" = "$_lpre" ] \
     && [ -z "$(git -C "$LF/B" for-each-ref 'refs/kit/notes-remote-*' 'refs/notes/kit-sync-*')" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync C9 (−): SIGTERM mid-sync -> temp refs cleaned AND exit 143 (does not continue), ledger unchanged" "trc=$_trc out=$(cat "$LF/term.out")"

  # =====================================================================================
  # sync T2, fix round 1. F1: DEFERRED SIGNALS. The C9 trap exited at once on INT/TERM, which broke
  # the publish-or-unwind guarantee (`record` AND `sync`): a TERM in the write->push->unwind window left
  # an UNPUBLISHED local note (the #658 stranded note), and a signal during the push left the publish
  # state unknown. The handler now only RECORDS the signal inside a critical section; on leaving it
  # the run exits with 130/143 having published or unwound. Outside a section it exits at once.
  # =====================================================================================
  # lsig <clone> <sleep-git-subcommand> <verb> [args...]: run the verb in the background with the git
  # shim SLEEPING (3s) on that subcommand; wait until the shim has started sleeping, send TERM, wait.
  lsig() {
    lshim; _sc="$1"; _ss="$2"; shift 2
    rm -f "$LF/sig.mark"
    ( cd "$_sc" && PATH="$LROOT/shim:$PATH" SLEEP_GIT_SUB="$_ss" SLEEP_MARK="$LF/sig.mark" PROMOTION_NOTES_REF="$LR" exec $VSH "$VERIFY" "$@" > "$LF/sig.out" 2>&1 ) &
    _sp=$!
    _sw=0; while [ ! -e "$LF/sig.mark" ] && [ "$_sw" -lt 100 ]; do sleep 0.1; _sw=$((_sw + 1)); done
    kill -TERM "$_sp" 2>/dev/null || true
    if wait "$_sp"; then LRC=0; else LRC=$?; fi
    LOUT="$(cat "$LF/sig.out")"
  }
  # lrejecthook: the fixture remote DECLINES every push (a pre-receive hook: not a non-ff, so never retried).
  lrejecthook() {
    printf '#!/bin/sh\necho declined-by-test\nexit 1\n' > "$LF/remote.git/hooks/pre-receive"
    chmod +x "$LF/remote.git/hooks/pre-receive"
  }
  # lput <clone> <object-name> <bodyfile>: add/replace a note ENTRY by plumbing (bypasses `notes add`'s
  # whitespace stripping and its object-must-exist check) as a new commit on the local ledger ref.
  lput() {
    _pb="$(git -C "$1" hash-object -w "$3")"; _pt="$(git -C "$1" rev-parse "refs/notes/$LR")"
    rm -f "$LF/lput.idx"
    GIT_INDEX_FILE="$LF/lput.idx" git -C "$1" read-tree "$_pt"
    GIT_INDEX_FILE="$LF/lput.idx" git -C "$1" update-index --add --cacheinfo "100644,$_pb,$2"
    _pn="$(GIT_INDEX_FILE="$LF/lput.idx" git -C "$1" write-tree)"
    _pc="$(lgid git -C "$1" commit-tree "$_pn" -p "$_pt" -m plumbed)"
    git -C "$1" update-ref "refs/notes/$LR" "$_pc"
  }
  # lsigfix <name>: diverged, with a twin (so a backup WOULD be made) and a valid candidate on BSHA.
  lsigfix() {
    mkledger "$1"
    lrec "$LF/A" "$ASHA" "branch/$1a"
    lrec "$LF/B" "$ASHA" "branch/$1a" --no-push --token "local twin"
    lrec "$LF/B" "$BSHA" "branch/$1b" --no-push
  }

  # (−) F1(a): `record`, TERM while the push sleeps and the remote then REJECTS -> the run still UNWINDS
  # (ledger back to its pre-record value, nothing unpublished) and exits 143.
  mkledger f1a
  lrec "$LF/A" "$ASHA" "branch/f1a0"
  lfetch "$LF/B"; _fpre="$(lrev "$LF/B")"
  lrejecthook
  lsig "$LF/B" push record --approved-sha "$BSHA" --approved-by "solo maintainer" --gate design --rung integration --class control-plane --scope branch/f1a --token "GO: f1a" --basis docs/architecture/x-design.md
  _frc="$LRC"; _fsout="$LOUT"
  llog "$LF/B" --unpushed
  if [ -e "$LF/sig.mark" ] && [ "$LRC" = 0 ] && [ "$(lrev "$LF/B")" = "$_fpre" ] && ! lnote "$LF/B" "$BSHA" \
     && ! printf '%s' "$LOUT" | grep -q "$BSHA"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F1(a) (−): record + TERM during a push the remote rejects -> ledger back at its pre-record value, nothing unpublished (log --unpushed lists no record)" "rrc=$_frc rout=$_fsout logrc=$LRC log=$LOUT"
  if [ "$_frc" = 143 ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F1(a) (−): ... and that record run exits 143" "rc=$_frc out=$_fsout"

  # (+) F1(b): `record`, TERM while the push sleeps and the push SUCCEEDS -> the note is on origin, the local
  # ledger equals origin, exit 143, and the published record is NOT unwound.
  mkledger f1b
  lrec "$LF/A" "$ASHA" "branch/f1b0"
  lfetch "$LF/B"
  lsig "$LF/B" push record --approved-sha "$BSHA" --approved-by "solo maintainer" --gate design --rung integration --class control-plane --scope branch/f1b --token "GO: f1b" --basis docs/architecture/x-design.md
  if [ "$LRC" = 143 ] && rnote "$LF" "$BSHA" && lnote "$LF/B" "$BSHA" && [ "$(lrev "$LF/B")" = "$(rrev "$LF")" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F1(b) (+): record + TERM during a push that SUCCEEDS -> note on origin, local == origin, exit 143, not unwound" "rc=$LRC out=$LOUT"

  # (−) F1(c): `sync`, TERM during the push with the remote rejecting -> the ledger is back at the old
  # local tip, THIS run's backup is deleted, exit 143 (nothing moved: local ledger, refs, origin).
  lsigfix f1c; lrejecthook
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsnap; lsig "$LF/B" push sync
  if [ "$_anc" = 0 ] && [ -e "$LF/sig.mark" ] && [ "$LRC" = 143 ] && lunmoved \
     && [ -z "$(git -C "$LF/B" for-each-ref 'refs/kit/promotions-presync-*' 'refs/notes/kit-sync-*')" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F1(c) (−): sync + TERM during a rejected push -> ledger back at the old local tip, this run's backup deleted, exit 143" "anc=$_anc rc=$LRC out=$LOUT"

  # (+) F1(d): `sync`, TERM BEFORE the critical section (a shimmed `git notes` sleeps during the BUILD) ->
  # no backup, no swap, ledger unchanged, no temp ref, exit 143. (Characterization: the section is not entered.)
  lsigfix f1d
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsnap; lsig "$LF/B" notes sync
  if [ "$_anc" = 0 ] && [ -e "$LF/sig.mark" ] && [ "$LRC" = 143 ] && lunmoved \
     && [ -z "$(git -C "$LF/B" for-each-ref 'refs/kit/promotions-presync-*' 'refs/notes/kit-sync-*' 'refs/kit/notes-remote-*')" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F1(d) (+): sync + TERM before the critical section (during the build) -> no backup, no swap, ledger unchanged, no temp ref, exit 143" "anc=$_anc rc=$LRC out=$LOUT"

  # =====================================================================================
  # sync T2, fix round 1. F2: the security-relevant re-validation checks each get their own leg (a
  # mutant deleting the check reds it). lfix + lvrefused idiom; every leg damages exactly ONE thing.
  # =====================================================================================
  # (lvcase is defined with lvrefused, above)
  # V2: approved-sha names a DIFFERENT resolvable commit.
  lfix f2v2; lmut "$LF/B" "$BSHA" "s/^approved-sha: .*/approved-sha: $ASHA/"
  lvcase "sync F2(1) (−): approved-sha rewritten to a DIFFERENT resolvable commit -> rc 2 naming approved-sha, nothing moved (V2)" 'approved-sha'
  # V5: a change-class outside record's vocabulary.
  lfix f2v5; lmut "$LF/B" "$BSHA" 's/^change-class: .*/change-class: bogus/'
  lvcase "sync F2(2) (−): change-class: bogus -> rc 2 naming change-class, nothing moved (V5)" 'change-class'
  # V6 + I5: a scope record would refuse, PLUS a forged label: the scope is named, approved-by is NOT (V6 runs before V7).
  lfix f2v6; lmut "$LF/B" "$BSHA" 's/^scope: .*/scope: branch\/a b/; s/^\(approved-by: .*\) \[[^]]*\]$/\1 [authenticated: github-review]/'
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsnap; lsync "$LF/B"
  if [ "$_anc" = 0 ] && lvrefused 'scope' && ! printf '%s' "$LOUT" | grep -q 'approved-by'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F2(3) (−): scope 'branch/a b' + a forged label -> rc 2 naming scope and NOT approved-by (V6, and V1-V6 before V7)" "anc=$_anc rc=$LRC out=$LOUT"
  # V1 control bytes: an embedded CR.
  lfix f2cr; lmut "$LF/B" "$BSHA" "s/^gate: .*/gate: de$(printf '\r')sign/"
  lvcase "sync F2(4) (−): an embedded CR in the body -> rc 2 naming the grammar check, nothing moved (V1 control bytes)" 'grammar'
  # The approved commit object is ABSENT locally: a note entry on a name that resolves to no object.
  lfix f2obj; _x=1234567890123456789012345678901234567890
  git -C "$LF/B" notes --ref="$LR" show "$BSHA" > "$LF/x.txt"; lput "$LF/B" "$_x" "$LF/x.txt"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsnap; lsync "$LF/B"
  if [ "$_anc" = 0 ] && [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q "REFUSED $_x" \
     && printf '%s' "$LOUT" | grep -q 'not present locally' && ! printf '%s' "$LOUT" | grep -q 'published' && lunmoved; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F2(5) (−): a candidate whose approved commit object is absent locally -> rc 2 naming the missing object, nothing moved" "anc=$_anc rc=$LRC out=$LOUT"
  # A remote hook that prints an ESC byte and DECLINES (not a non-ff): rc 2, ledger unwound, no presync ref, NO ESC in the output.
  lfix f2esc
  printf '#!/bin/sh\nprintf "nope \\033[31mred\\033[0m\\n"\nexit 1\n' > "$LF/remote.git/hooks/pre-receive"; chmod +x "$LF/remote.git/hooks/pre-receive"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsnap; lsync "$LF/B"
  if [ "$_anc" = 0 ] && [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'nope' && lunmoved \
     && [ -z "$(git -C "$LF/B" for-each-ref 'refs/kit/promotions-presync-*')" ] \
     && ! printf '%s' "$LOUT" | grep -q "$(printf '\033')"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F2(6) (−): a remote hook printing an ESC and declining -> rc 2, ledger unwound, no presync ref, no ESC byte relayed (git's text still shown)" "anc=$_anc rc=$LRC out=$LOUT"
  # A SECOND non-ff (`lracer always`): rc 2, the ledger unwound, this run's backup deleted.
  mkledger f2race
  lrec "$LF/A" "$ASHA" "branch/f2r1"
  lrec "$LF/B" "$BSHA" "branch/f2r2"
  lrec "$LF/A" "$ASHA" "branch/f2r1" --no-push --token "local twin"
  la2 "$LF/A"; _fa2="$(git -C "$LF/A" rev-parse HEAD)"
  lrec "$LF/A" "$_fa2" "branch/f2r3" --no-push
  if ldiverged "$LF/A"; then _anc=0; else _anc=1; fi
  _lpre="$(lrev "$LF/A")"
  lracer always
  lsync "$LF/A"
  git -C "$LF/A" config --unset core.hooksPath
  if [ "$_anc" = 0 ] && [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'moved twice' && [ "$(lrev "$LF/A")" = "$_lpre" ] \
     && [ -z "$(git -C "$LF/A" for-each-ref 'refs/kit/promotions-presync-*')" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F2(7) (−): a SECOND non-ff (racer always) -> rc 2 'moved twice', ledger unwound to the old local tip, this run's backup deleted" "anc=$_anc rc=$LRC out=$LOUT"

  # =====================================================================================
  # sync T2, fix round 1. F3: the ledger ref is resolved by its EXACT full name (no DWIM).
  # =====================================================================================
  mkledger f3
  lrec "$LF/A" "$ASHA" "branch/f3"
  git -C "$LF/B" branch "refs/notes/$LR" HEAD 2>/dev/null
  _dwim="$(git -C "$LF/B" rev-parse -q --verify "refs/notes/$LR" 2>/dev/null || true)"
  lsync "$LF/B"
  # positive anchor: the DWIM really resolves (a branch), yet no notes ref existed before the sync
  if [ -n "$_dwim" ] && git -C "$LF/B" show-ref --verify -q "refs/heads/refs/notes/$LR" 2>/dev/null; then _f3a=0; else _f3a=1; fi
  if [ "$_f3a" = 0 ] && [ "$LRC" = 0 ] && [ "$(lrev "$LF/B")" = "$(rrev "$LF")" ] && printf '%s' "$LOUT" | grep -q 'fast-forwarded'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F3 (−): a BRANCH named refs/notes/<ledger> and no notes ref -> the ledger reads as ABSENT (fast-forwarded to origin's), never as that branch" "dwim=$_dwim rc=$LRC out=$LOUT"

  # =====================================================================================
  # sync T2, fix round 1. F4: V1 is byte-exact with what `record` stores (`notes add -F` strips trailing whitespace).
  # =====================================================================================
  mkledger f4a
  lrec "$LF/A" "$ASHA" "branch/f4a" --basis ' '
  if [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'whitespace-only' && printf '%s' "$LOUT" | grep -q -- '--basis' && ! lnote "$LF/A" "$ASHA"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F4(a) (−): record --basis ' ' -> rc 2 '--basis is whitespace-only', no note" "rc=$LRC out=$LOUT"
  lrec "$LF/A" "$ASHA" "branch/f4a" --gate ' '
  if [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'whitespace-only' && printf '%s' "$LOUT" | grep -q -- '--gate' && ! lnote "$LF/A" "$ASHA"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F4(a) (−): record --gate ' ' -> rc 2 '--gate is whitespace-only', no note" "rc=$LRC out=$LOUT"
  # (b) a hand-minted note with a trailing SPACE on basis: (plumbed: `notes add` would strip it).
  lfix f4b
  git -C "$LF/B" notes --ref="$LR" show "$BSHA" | sed 's/^basis: .*/& /' > "$LF/ts.txt"; lput "$LF/B" "$BSHA" "$LF/ts.txt"
  lvcase "sync F4(b) (−): a trailing space on a body line -> rc 2 naming the grammar check (record never stores one)" 'grammar'
  # (c) recorded-at pinned to YYYY-MM-DDTHH:MM:SSZ or the literal 'unknown'.
  lfix f4c; lmut "$LF/B" "$BSHA" 's/^recorded-at: .*/recorded-at: yesterday/'
  lvcase "sync F4(c) (−): a malformed recorded-at -> rc 2 naming recorded-at" 'recorded-at'

  # =====================================================================================
  # sync T2, fix round 1. F5 (converted in T3 step 0): the postcondition read must not hide git's rc and
  # must pick the ONE line whose ref field is EXACTLY refs/notes/<ledger>. ls-remote patterns match
  # trailing path components, so a look-alike branch refs/heads/refs/notes/<ledger> answers too (and sorts
  # FIRST). (a) a look-alike at a STALE sha must not fail a successful publish nor be read as the answer.
  # (b) an origin that no longer answers the exact ref after the push -> POSTCONDITION FAILED rc 2.
  # (Two EXACT lines are not constructible: a ref name is unique in a repository.)
  # =====================================================================================
  lfix f5post
  printf '#!/bin/sh\ngit update-ref "refs/heads/refs/notes/%s" "$(git rev-parse "refs/notes/%s~1")"\nexit 0\n' "$LR" "$LR" > "$LF/remote.git/hooks/post-receive"
  chmod +x "$LF/remote.git/hooks/post-receive"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsync "$LF/B"
  _lk="$(git --git-dir="$LF/remote.git" for-each-ref "refs/heads/refs/notes/$LR" | grep -c .)"
  if [ "$_anc" = 0 ] && [ "$_lk" = 1 ] && [ "$LRC" = 0 ] && ! printf '%s' "$LOUT" | grep -q 'POSTCONDITION FAILED' \
     && [ "$(lrev "$LF/B")" = "$(rrev "$LF")" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F5a (+): origin also carries refs/heads/refs/notes/<ledger> (stale sha, answers first) -> the exact-ref line is chosen: rc 0, postcondition passes" "anc=$_anc lk=$_lk rc=$LRC out=$LOUT"
  lfix f5gone
  printf '#!/bin/sh\ngit update-ref -d "refs/notes/%s"\nexit 0\n' "$LR" > "$LF/remote.git/hooks/post-receive"
  chmod +x "$LF/remote.git/hooks/post-receive"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsync "$LF/B"
  if [ "$_anc" = 0 ] && [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'POSTCONDITION FAILED'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync F5b (−): the exact ref is absent on origin after the push -> POSTCONDITION FAILED rc 2" "anc=$_anc rc=$LRC out=$LOUT"

  # =====================================================================================
  # sync, WHOLE-BRANCH fix round 1 (A1-A7 from the whole-branch reviewer, B1-B7 from the security seat).
  # =====================================================================================
  # lputrm <git-dir-or-clone> <name>: remove one note ENTRY by plumbing, as a new commit on that repo's ledger.
  lputrm() {
    _rmt="$(git -C "$1" rev-parse "refs/notes/$LR")"
    _rmn="$(git -C "$1" ls-tree "$_rmt^{tree}" | grep -v "$(printf '\t')$2\$" | git -C "$1" mktree)"
    _rmc="$(lgid git -C "$1" commit-tree "$_rmn" -p "$_rmt" -m removed)"
    git -C "$1" update-ref "refs/notes/$LR" "$_rmc"
  }
  # lplant <clone> <symref-prefix> <verb> [args...]: run the producer with the git shim HOLDING its first
  # `rev-parse` (script line 56, before any mode runs), plant <prefix><its own pid> as a SYMBOLIC ref to the
  # ledger (the pid is `$!`: the subshell execs, so it IS the script's `$$`), then release it. Sets LRC/LOUT/_wpid.
  lplant() {
    lshim; _wc="$1"; _wf="$2"; shift 2
    rm -f "$LF/wait.started" "$LF/wait.go"
    ( cd "$_wc" && PATH="$LROOT/shim:$PATH" WAIT_GIT_SUB=rev-parse WAIT_MARK="$LF/wait" PROMOTION_NOTES_REF="${_wnr:-$LR}" exec $VSH "$VERIFY" "$@" > "$LF/plant.out" 2>&1 ) &
    _wpid=$!
    _ww=0; while [ ! -e "$LF/wait.started" ] && [ "$_ww" -lt 100 ]; do sleep 0.1; _ww=$((_ww + 1)); done
    git -C "$_wc" symbolic-ref "$_wf$_wpid" "refs/notes/${_wnr:-$LR}"
    : > "$LF/wait.go"
    if wait "$_wpid"; then LRC=0; else LRC=$?; fi
    LOUT="$(cat "$LF/plant.out")"
  }
  # lleaks <clone>: prints any temp/scratch notes ref left in the clone or on the remote.
  lleaks() {
    git -C "$1" for-each-ref 'refs/notes/kit-sync-*' 'refs/notes/refs/*' 'refs/kit/notes-remote-*' 2>/dev/null
    git --git-dir="$LF/remote.git" for-each-ref 'refs/notes/kit-sync-*' 'refs/notes/refs/*' 'refs/kit/notes-remote-*' 2>/dev/null
  }
  _esc="$(printf '\033')"

  # A1(a): the remedy for a candidate whose approved commit is ABSENT locally must be runnable — V2 prints
  # `sync --discard-local <sha>` for exactly this case, and the value used to be resolved to a COMMIT object.
  lfix a1a; _x=1234567890123456789012345678901234567890
  git -C "$LF/B" notes --ref="$LR" show "$BSHA" > "$LF/x.txt"; lput "$LF/B" "$_x" "$LF/x.txt"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  _rpre="$(rrev "$LF")"
  lsync "$LF/B" --discard-local "$_x" --discard-local "$BSHA"
  if [ "$_anc" = 0 ] && [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q "discarded-local $_x" \
     && [ "$(rrev "$LF")" = "$_rpre" ] && [ "$(lrev "$LF/B")" = "$_rpre" ] \
     && [ "$(git -C "$LF/B" for-each-ref 'refs/kit/promotions-presync-*' | wc -l | tr -d ' ')" = 1 ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync A1(a) (+): --discard-local <40-hex of an ABSENT commit> is accepted -> rc 0, origin unchanged, one backup ref" "anc=$_anc rc=$LRC out=$LOUT"
  # A1(a'): a short prefix resolves against the NOTE PATHS (not commits): unique -> accepted; unknown, ambiguous,
  # uppercase -> refused naming the value. --dry-run, so one fixture serves every variant.
  lfix a1p
  git -C "$LF/B" notes --ref="$LR" show "$BSHA" > "$LF/x.txt"; lput "$LF/B" "$_x" "$LF/x.txt"
  lsync "$LF/B" --dry-run --discard-local 12345678; _c1="$LRC"; _o1="$LOUT"
  lsync "$LF/B" --dry-run --discard-local dead; _c2="$LRC"; _o2="$LOUT"
  lsync "$LF/B" --dry-run --discard-local 12345678AB; _c3="$LRC"; _o3="$LOUT"
  lput "$LF/B" 1234567800000000000000000000000000000000 "$LF/x.txt"
  lsync "$LF/B" --dry-run --discard-local 12345678; _c4="$LRC"; _o4="$LOUT"
  if [ "$_c1" = 0 ] && printf '%s' "$_o1" | grep -q "WOULD discarded-local $_x" \
     && [ "$_c2" = 2 ] && printf '%s' "$_o2" | grep -q "dead" \
     && [ "$_c3" = 2 ] && printf '%s' "$_o3" | grep -q "12345678AB" \
     && [ "$_c4" = 2 ] && printf '%s' "$_o4" | grep -q "ambiguous"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync A1(a') (−/+): a unique note-path prefix is accepted; unknown / uppercase / ambiguous are refused naming the value" "c1=$_c1 o1=$_o1 c2=$_c2 o2=$_o2 c3=$_c3 o3=$_o3 c4=$_c4 o4=$_o4"
  # A1(b): a VOIDED note on an absent commit (published, removed on origin) — the voided refusal prints the same remedy.
  mkledger a1b
  lrec "$LF/A" "$ASHA" "branch/a1b"
  lfetch "$LF/B"
  git -C "$LF/B" notes --ref="$LR" show "$ASHA" > "$LF/x.txt"; lput "$LF/B" "$_x" "$LF/x.txt"
  git -C "$LF/B" push -q origin "refs/notes/$LR" 2>/dev/null
  lputrm "$LF/remote.git" "$_x"
  lrec "$LF/B" "$BSHA" "branch/a1bb" --no-push
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsync "$LF/B"; _c1="$LRC"; _o1="$LOUT"
  lsync "$LF/B" --discard-local "$_x"
  if [ "$_anc" = 0 ] && [ "$_c1" = 2 ] && printf '%s' "$_o1" | grep -q "VOIDED upstream" && printf '%s' "$_o1" | grep -q "sync --discard-local $_x" \
     && [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q "discarded-local $_x (voided upstream)" \
     && [ -z "$(git --git-dir="$LF/remote.git" ls-tree "refs/notes/$LR^{tree}" | grep "$_x" || true)" ] \
     && [ "$(git -C "$LF/B" for-each-ref 'refs/kit/promotions-presync-*' | wc -l | tr -d ' ')" = 1 ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync A1(b) (+): a VOIDED note on an absent commit — the printed remedy runs: rc 0, the voided note is not published, one backup ref" "anc=$_anc c1=$_c1 o1=$_o1 rc=$LRC out=$LOUT"

  # A2: config-sensitive porcelain. `log.showRoot=false` hides the ROOT commit's listing from a bare `git log
  # --name-only`; the voided-history read must pin `--root`. Anchors: the config really hides the root here, and
  # the flag really restores it (so a mutant dropping `--root` is caught even where the removal commit also lists it).
  mkledger a2root
  lrec "$LF/A" "$ASHA" "branch/a2r"
  lfetch "$LF/B"
  lgid git --git-dir="$LF/remote.git" notes --ref="$LR" remove "$ASHA"
  lrec "$LF/B" "$BSHA" "branch/a2rb" --no-push
  git -C "$LF/B" config log.showRoot false
  _h0="$(git -C "$LF/B" log --no-renames -m --name-only --format= "refs/notes/$LR" | tr -d '/')"
  _h1="$(git -C "$LF/B" log --root --no-renames -m --name-only --format= "refs/notes/$LR" | tr -d '/')"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  _lpre="$(lrev "$LF/B")"
  lsync "$LF/B"
  _o1="$LOUT"; _c1="$LRC"
  # The removal commit ALSO lists the path, so the config alone cannot flip this scenario: pin the FLAG itself.
  # The shim fails any `git log --name-only` that lacks `--root` (rc 128); the sync must still reach VOIDED.
  lshim
  if _o2="$( cd "$LF/B" && PATH="$LROOT/shim:$PATH" REQUIRE_ROOT=1 PROMOTION_NOTES_REF="$LR" $VSH "$VERIFY" sync 2>&1 )"; then _c2=0; else _c2=$?; fi
  if ! printf '%s\n' "$_h0" | grep -qx "$ASHA" && printf '%s\n' "$_h1" | grep -qx "$ASHA" \
     && [ "$_anc" = 0 ] && [ "$_c1" = 2 ] && printf '%s' "$_o1" | grep -q "REFUSED $ASHA" \
     && printf '%s' "$_o1" | grep -q 'VOIDED upstream' && [ "$(lrev "$LF/B")" = "$_lpre" ] \
     && [ "$_c2" = 2 ] && printf '%s' "$_o2" | grep -q 'VOIDED upstream' && ! printf '%s' "$_o2" | grep -q 'shim: log without --root'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync A2 (−): log.showRoot=false in the clone must not blind the voided arm (the FIRST-ever note, later removed) -> rc 2 VOIDED upstream, and the history read pins --root" "anc=$_anc c1=$_c1 o1=$_o1 c2=$_c2 o2=$_o2 h0=$_h0"

  # A3: V7 refuses a whitespace-only approver id, as `record` does (`approved-by:   [self-asserted]`).
  lfix a3; lmut "$LF/B" "$BSHA" 's/^approved-by: .*/approved-by:   [self-asserted]/'
  lvcase "sync A3 (−): a whitespace-only approver id -> rc 2 naming approved-by, nothing moved (V7)" 'approved-by'

  # A5 (dash `echo` expands \0NNN) + B2: a refusal message must never carry a control byte from note text
  # (A5: literal backslash-digits in the note's kit-row) or from a commit's own trailer (B2: a real ESC in Kit-Row).
  lfix a5; lmut "$LF/B" "$BSHA" 's/^kit-row: .*/kit-row: \\0033[2J/'
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsnap; lsync "$LF/B"
  if [ "$_anc" = 0 ] && lvrefused 'kit-row' && printf '%s' "$LOUT" | grep -qF '\0033[2J' \
     && ! printf '%s' "$LOUT" | grep -q "$_esc"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync A5 (−): note text carrying the literal characters backslash-0033[2J reaches a refusal as LITERAL text — no ESC byte (printf, not echo)" "anc=$_anc rc=$LRC out=$LOUT"
  lfix b2
  git -C "$LF/B" commit -q --allow-empty -m esc-row -m "Kit-Row: A${_esc}[2J"; _nb2="$(git -C "$LF/B" rev-parse HEAD)"
  git -C "$LF/B" notes --ref="$LR" show "$BSHA" | sed "s/^approved-sha: .*/approved-sha: $_nb2/" > "$LF/x.txt"; lput "$LF/B" "$_nb2" "$LF/x.txt"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsnap; lsync "$LF/B"
  if [ "$_anc" = 0 ] && [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q "REFUSED $_nb2" && printf '%s' "$LOUT" | grep -q "kit-row" \
     && printf '%s' "$LOUT" | grep -qF 'A[2J' && ! printf '%s' "$LOUT" | grep -q "$_esc" && lunmoved; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync B2 (−): a commit whose own Kit-Row trailer carries an ESC is printed CLEANED in the V4 refusal (no ESC byte)" "anc=$_anc rc=$LRC out=$LOUT"

  # A7: I4 — no temp/scratch notes ref survives a successful, a refused and a dry-run sync (clone AND remote).
  lfix i4dry; lsync "$LF/B" --dry-run; _r1="$LRC"; _k1="$(lleaks "$LF/B")"
  lfix i4ref; lforge "$LF/B" "$BSHA" "signed: gpg"; lsync "$LF/B"; _r2="$LRC"; _k2="$(lleaks "$LF/B")"
  lfix i4ok; lsync "$LF/B"; _r3="$LRC"; _k3="$(lleaks "$LF/B")"; _o3="$LOUT"
  if [ "$_r1" = 0 ] && [ "$_r2" = 2 ] && [ "$_r3" = 0 ] && printf '%s' "$_o3" | grep -q "published $BSHA" \
     && [ -z "$_k1$_k2$_k3" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync (+): I4 — no temp or scratch ref survives a successful, a refused and a dry-run sync" "r=$_r1/$_r2/$_r3 leaks=[$_k1|$_k2|$_k3]"

  # B1: a pre-planted SYMBOLIC ref at a temp-ref name must not be written through (nor deleted through by the
  # cleanup): the ledger itself would be clobbered / deleted. The run REFUSES, naming the ref; ledger + origin intact.
  lfix b1a
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  _lpre="$(lrev "$LF/B")"; _rpre="$(rrev "$LF")"
  lplant "$LF/B" "refs/notes/kit-sync-" sync
  if [ "$_anc" = 0 ] && [ "$LRC" = 2 ] && [ "$(lrev "$LF/B")" = "$_lpre" ] && [ "$(rrev "$LF")" = "$_rpre" ] \
     && printf '%s' "$LOUT" | grep -qF "refs/notes/kit-sync-$_wpid"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync B1(a) (−): a symref planted at refs/notes/kit-sync-<pid> -> sync refuses naming it; the ledger and origin are intact" "anc=$_anc rc=$LRC lrev=$(lrev "$LF/B") want=$_lpre out=$LOUT"
  lfix b1b
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  _lpre="$(lrev "$LF/B")"
  lplant "$LF/B" "refs/kit/notes-remote-" log --unpushed
  if [ "$_anc" = 0 ] && [ "$LRC" = 2 ] && [ "$(lrev "$LF/B")" = "$_lpre" ] \
     && printf '%s' "$LOUT" | grep -qF "refs/kit/notes-remote-$_wpid"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync B1(b) (−): a symref planted at the scratch ref -> log --unpushed refuses naming it; the local ledger is intact" "anc=$_anc rc=$LRC lrev=$(lrev "$LF/B") want=$_lpre out=$LOUT"
  lfix b1c
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  _lpre="$(lrev "$LF/B")"
  lplant "$LF/B" "refs/kit/notes-remote-" record --approved-sha "$ASHA" --approved-by "solo maintainer" --gate design --rung integration --class control-plane --scope branch/b1c --token "GO: b1c" --basis docs/architecture/x-design.md
  if [ "$_anc" = 0 ] && [ "$LRC" = 2 ] && [ "$(lrev "$LF/B")" = "$_lpre" ] \
     && printf '%s' "$LOUT" | grep -qF "refs/kit/notes-remote-$_wpid"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync B1(c) (−): the same symref at the scratch ref -> record's sync-in refuses naming it; the local ledger is intact" "anc=$_anc rc=$LRC lrev=$(lrev "$LF/B") want=$_lpre out=$LOUT"

  # B3: a non-40-hex path in the LOCAL ledger tree REFUSES (it used to be skipped silently, with no backup).
  lfix b3
  git -C "$LF/B" notes --ref="$LR" show "$BSHA" > "$LF/x.txt"; lput "$LF/B" not-a-sha "$LF/x.txt"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsnap; lsync "$LF/B"
  if [ "$_anc" = 0 ] && [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -qF 'not-a-sha' && ! printf '%s' "$LOUT" | grep -q 'published' && lunmoved \
     && printf '%s' "$LOUT" | grep -qF "git ls-tree -r refs/notes/$LR" && printf '%s' "$LOUT" | grep -qF 'operator-only'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync B3 (−): a non-40-hex entry in the local ledger tree -> rc 2 naming the path AND the remedy (ls-tree inspect, operator-only repair), ledger unchanged (never silently dropped)" "anc=$_anc rc=$LRC out=$LOUT"

  # B4: the voided arm's horizon is the local object store — a SHALLOW repository is refused.
  mkledger b4
  lrec "$LF/A" "$ASHA" "branch/b4a"
  git clone -q --depth 1 -b main "file://$LF/remote.git" "$LF/S" 2>/dev/null
  git -C "$LF/S" config user.email t@example.com; git -C "$LF/S" config user.name t; git -C "$LF/S" config commit.gpgsign false
  git -C "$LF/S" fetch -q origin "refs/notes/$LR:refs/notes/$LR"
  printf 's-side change\n' >> "$LF/S/docs/architecture/x-design.md"; git -C "$LF/S" add docs/architecture/x-design.md
  git -C "$LF/S" commit -q -m s-side; _ssha="$(git -C "$LF/S" rev-parse HEAD)"
  lrec "$LF/S" "$_ssha" "branch/b4s" --no-push
  la2 "$LF/A"; _fa2="$(git -C "$LF/A" rev-parse HEAD)"
  lrec "$LF/A" "$_fa2" "branch/b4b"
  _shal="$(git -C "$LF/S" rev-parse --is-shallow-repository)"
  if git -C "$LF/S" merge-base --is-ancestor "$(lrev "$LF/S")" "$(rrev "$LF")" 2>/dev/null; then _anc=1; else _anc=0; fi
  _lpre="$(lrev "$LF/S")"
  lsync "$LF/S"
  if [ "$_shal" = true ] && [ "$_anc" = 0 ] && [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q "published $_ssha" && rnote "$LF" "$_ssha"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync B4(a) (+): a shallow BRANCH clone whose notes chain was fetched in full syncs normally -> rc 0, published" "shallow=$_shal anc=$_anc rc=$LRC out=$LOUT"
  # B4(b): a notes chain TRUNCATED by --depth (its tip is a graft) is refused, naming 'shallow', ledger unchanged.
  mkledger b4b
  lrec "$LF/A" "$ASHA" "branch/b4ba"
  la2 "$LF/A"; _fa2="$(git -C "$LF/A" rev-parse HEAD)"
  lrec "$LF/A" "$_fa2" "branch/b4bb"
  git clone -q "file://$LF/remote.git" "$LF/S2" 2>/dev/null
  git -C "$LF/S2" config user.email t@example.com; git -C "$LF/S2" config user.name t; git -C "$LF/S2" config commit.gpgsign false
  git -C "$LF/S2" fetch -q --depth 1 origin "refs/notes/$LR:refs/notes/$LR"
  printf 's2-side change\n' >> "$LF/S2/docs/architecture/x-design.md"; git -C "$LF/S2" add docs/architecture/x-design.md
  git -C "$LF/S2" commit -q -m s2-side; _s2sha="$(git -C "$LF/S2" rev-parse HEAD)"
  lrec "$LF/S2" "$_s2sha" "branch/b4bs" --no-push
  _lpre="$(lrev "$LF/S2")"
  lsync "$LF/S2"
  if [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -qi 'shallow' && [ "$(lrev "$LF/S2")" = "$_lpre" ] && ! printf '%s' "$LOUT" | grep -q 'published'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync B4(b) (−): a notes chain truncated by a shallow fetch -> rc 2 naming 'shallow', ledger unchanged" "rc=$LRC lrev=$(lrev "$LF/S2") want=$_lpre out=$LOUT"

  # B7: the postcondition must tell a benign race (another record landed on top of OUR push) from a failed publish.
  lfix b7
  printf '#!/bin/sh\nt="$(git rev-parse "refs/notes/%s^{tree}")"\nc="$(GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e git commit-tree "$t" -p "refs/notes/%s" -m race)"\ngit update-ref "refs/notes/%s" "$c"\nexit 0\n' "$LR" "$LR" "$LR" > "$LF/remote.git/hooks/post-receive"
  chmod +x "$LF/remote.git/hooks/post-receive"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsync "$LF/B"
  git -C "$LF/B" fetch -q origin "refs/notes/$LR:refs/kit/anchor-remote" 2>/dev/null
  _ob="$(git -C "$LF/B" merge-base --is-ancestor "$(lrev "$LF/B")" "$(rrev "$LF")" && echo yes || echo no)"
  git -C "$LF/B" update-ref -d refs/kit/anchor-remote
  if [ "$_anc" = 0 ] && [ "$LRC" = 0 ] && [ "$_ob" = yes ] && [ "$(lrev "$LF/B")" != "$(rrev "$LF")" ] \
     && printf '%s' "$LOUT" | grep -q 'origin has since moved on' && ! printf '%s' "$LOUT" | grep -q 'POSTCONDITION FAILED'; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync B7 (+): a record landing on top of our push is a benign race -> rc 0 'published (origin has since moved on)', not POSTCONDITION FAILED" "anc=$_anc ob=$_ob rc=$LRC out=$LOUT"

  # C1: with `remote.origin.fetch = +refs/notes/*:refs/notes/*` a fetch into the scratch ref would ALSO force-update
  # the local ledger through git's opportunistic remote-tracking update. `--refmap=` disables it: --dry-run must not
  # write the ledger, `log --unpushed` must still list the unpublished record, and a live sync must still publish.
  lfix c1
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  git -C "$LF/B" config remote.origin.fetch '+refs/notes/*:refs/notes/*'
  lsnap; lsync "$LF/B" --dry-run; _c1="$LRC"; _o1="$LOUT"; _k1=1; lunmoved && _k1=0
  llog "$LF/B" --unpushed; _c2="$LRC"; _o2="$LOUT"; _k2=1; [ "$(lrev "$LF/B")" = "$_s_l" ] && _k2=0
  lsync "$LF/B"; _c3="$LRC"; _o3="$LOUT"
  if [ "$_anc" = 0 ] && [ "$_c1" = 0 ] && [ "$_k1" = 0 ] && printf '%s' "$_o1" | grep -q "candidate $BSHA" \
     && [ "$_c2" = 0 ] && [ "$_k2" = 0 ] && printf '%s' "$_o2" | grep -q "## $BSHA (unpublished)" \
     && [ "$_c3" = 0 ] && printf '%s' "$_o3" | grep -q "published $BSHA" && rnote "$LF" "$BSHA"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync C1 (−/+): an opportunistic notes refmap in the clone must not let a fetch write the ledger — dry-run leaves it unmoved, log --unpushed still lists the record, a live sync still publishes" "anc=$_anc c=$_c1/$_c2/$_c3 kept=$_k1/$_k2 o1=$_o1 o2=$_o2 o3=$_o3"

  # C2: land's confirm fetch must not write through (nor delete through) a symref planted at its pid-named ref.
  mkorigin c2; LF="$LO"; rm -f "$LAND_MARK"; _wnr="$LR2"
  # (the earlier land section's cleanup removed $LAND_STUB with the land-* fixtures: recreate a stub)
  LAND_STUB="$LROOT/c2-stub"; printf '#!/bin/sh\ntouch %s\n' "'$LAND_MARK'" > "$LAND_STUB"; chmod +x "$LAND_STUB"
  _c2_path="$PATH"; PATH="$(lgh "$LOSHA" "solo maintainer"):$PATH"
  lplant "$LOA" "refs/notes/kit-land-confirm-" land --ref 77 --merge-cmd "$LAND_STUB" --approved-sha "$LOSHA" --approved-by "solo maintainer" --go-by "the owner" --gate release-candidate --rung rc --class control-plane --scope "PR #77" --token "GO: land c2"
  PATH="$_c2_path"; _wnr=""
  if [ "$LRC" != 0 ] && printf '%s' "$LOUT" | grep -qF "refs/notes/kit-land-confirm-$_wpid" && [ ! -f "$LAND_MARK" ] \
     && git -C "$LOA" rev-parse -q --verify "refs/notes/$LR2" >/dev/null && onote "$LOSHA"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "land C2 (−): a symref planted at refs/notes/kit-land-confirm-<pid> -> land refuses naming it, no merge, the ledger (local and origin) intact" "rc=$LRC merged=$( [ -f "$LAND_MARK" ] && echo yes || echo no ) ledger=$(git -C "$LOA" rev-parse -q --verify "refs/notes/$LR2" || echo none) out=$LOUT"

  # C6: a prefix shared by a LOCAL-only and an ORIGIN-only note path is ambiguous.
  lfix a1q
  git -C "$LF/B" notes --ref="$LR" show "$BSHA" > "$LF/x.txt"; lput "$LF/B" 1234567890123456789012345678901234567890 "$LF/x.txt"
  lput "$LF/remote.git" 1234567855555555555555555555555555555555 "$LF/x.txt"
  lsync "$LF/B" --dry-run --discard-local 12345678
  if [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q "ambiguous"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync A1(a'') (−): a prefix shared by a local-only and an origin-only note path -> refused as ambiguous" "rc=$LRC out=$LOUT"

  # =====================================================================================
  # SWAS-323 slice A: a GO note is a LIST of records, keyed (scope, gate); a second GO on the same commit no longer erases the first.
  # Each cell is a function over a fixture NAME that returns 0 when the property holds. _j323 runs it against the real gate (must hold)
  # and, for a mutant, against a sed-edited COPY of the gate (must NOT hold: the cell has teeth). R1 R2 R3 L1 S1 T1 D1.
  # =====================================================================================
  _j323() {   # <label> <cell fn> <sed|-> <desc>
    _jv0="$VERIFY"
    if [ "$3" != - ] && [ "${J323_COPY:-0}" = 1 ]; then
      # a LAND cell: the copy must carry the layout of the gate under test (the evidence leg reads it), so it is built by tr_copy, then sed-edited
      _jx="$(fx_facts "$FX_OWN")"
      tr_copy "$LROOT/m323-$1" "${_jx%% *}" "${_jx##* }" "$(printf '%s' "$_jx" | cut -d' ' -f2)"
      cp "$LROOT/m323-$1/scripts/promotion-verify.sh" "$LROOT/m323-$1/orig.sh"
      sed "$3" "$LROOT/m323-$1/orig.sh" > "$LROOT/m323-$1/scripts/promotion-verify.sh"
      if cmp -s "$LROOT/m323-$1/orig.sh" "$LROOT/m323-$1/scripts/promotion-verify.sh"; then echo "FAIL: $1: the mutant changed nothing"; st=1; VERIFY="$_jv0"; return 0; fi
      VERIFY="$LROOT/m323-$1/scripts/promotion-verify.sh"
    elif [ "$3" != - ]; then
      mkdir -p "$LROOT/m323-$1"; sed "$3" "$VERIFY" > "$LROOT/m323-$1/promotion-verify.sh"
      if cmp -s "$VERIFY" "$LROOT/m323-$1/promotion-verify.sh"; then echo "FAIL: $1: the mutant changed nothing"; st=1; VERIFY="$_jv0"; return 0; fi
      VERIFY="$LROOT/m323-$1/promotion-verify.sh"
    fi
    _op323=1
    if "$2" "m323$1"; then _jr=0; else _jr=1; fi
    VERIFY="$_jv0"
    if [ "$3" = - ]; then lpass "$_jr" "$1: $4" "cell failed rc=$LRC out=$LOUT"
    elif [ "$_op323" != 0 ]; then echo "FAIL: $1: $4 -- the mutant copy's OPERATION failed outright (so its red proves nothing): rc=$LRC out=$LOUT"; st=1
    elif [ "$_jr" = 1 ]; then echo "PASS: $1: $4 (the mutant is killed)"
    else echo "FAIL: $1: $4 -- the mutant SURVIVED"; st=1; fi
  }
  # _opok: the operation under test RAN to its own verdict (no crash, no missing file): the cell sets _op323=0 only then, so under a mutant
  # only the property may differ.
  _opok() { case "$LOUT" in *'syntax error'*|*'not found'*|*'No such file'*) return 1 ;; esac; return 0; }
  _n323() { git -C "$LF/A" notes --ref="$LR" show "$ASHA" 2>/dev/null; }
  _f_r1() {   # two scopes on one sha: both kept, in order, and both on origin
    mkledger "$1"; lrec "$LF/A" "$ASHA" "branch/r1a"; _x1="$LRC"; lrec "$LF/A" "$ASHA" "branch/r1b"; _x2="$LRC"
    _nn="$(_n323)"; _ro="$(git --git-dir="$LF/remote.git" notes --ref="$LR" show "$ASHA" 2>/dev/null)"
    if [ "$_x1" = 0 ] && [ "$_x2" = 0 ]; then _op323=0; fi   # both records WERE written: only the property may differ under a mutant
    [ "$_x1" = 0 ] && [ "$_x2" = 0 ] && [ "$(printf '%s\n' "$_nn" | grep -c '^record: promotion')" = 2 ] \
      && [ "$(printf '%s\n' "$_nn" | sed -n 's/^scope: //p' | tr '\n' ' ')" = 'branch/r1a branch/r1b ' ] && [ "$_ro" = "$_nn" ]
  }
  _f_r2() {   # a re-record of the same (scope, gate) supersedes only that key
    mkledger "$1"; lrec "$LF/A" "$ASHA" "branch/r2a"; lrec "$LF/A" "$ASHA" "branch/r2b"
    lrec "$LF/A" "$ASHA" "branch/r2a" --basis docs/architecture/y-design.md
    _nn="$(_n323)"
    if [ "$LRC" = 0 ]; then _op323=0; fi
    [ "$LRC" = 0 ] && [ "$(printf '%s\n' "$_nn" | grep -c '^scope: branch/r2a$')" = 1 ] && [ "$(printf '%s\n' "$_nn" | grep -c '^record: promotion')" = 2 ] \
      && printf '%s\n' "$_nn" | grep -q '^basis: docs/architecture/y-design.md$' && printf '%s\n' "$_nn" | grep -q '^scope: branch/r2b$'
  }
  _f_r5() {   # a --go-by that reads 'promotion x' is only a field value: the note stays two records (one blank separator), not three pieces
    mkledger "$1"; lrec "$LF/A" "$ASHA" "branch/r5a" --go-by 'promotion x'; _x1="$LRC"; lrec "$LF/A" "$ASHA" "branch/r5b"; _x2="$LRC"
    _nn="$(_n323)"
    if [ "$_x1" = 0 ] && [ "$_x2" = 0 ]; then _op323=0; fi
    [ "$_x1" = 0 ] && [ "$_x2" = 0 ] && [ "$(printf '%s\n' "$_nn" | grep -c '^$')" = 1 ] \
      && [ "$(printf '%s\n' "$_nn" | grep -c '^record: promotion')" = 2 ] && printf '%s\n' "$_nn" | grep -q '^go-by: promotion x \[self-asserted\]$'
  }
  _f_r11() {   # 64 records already on the sha: the 65th record refuses at the cap and the note still holds all 64
    mkledger "$1"; _i11=0
    while [ "$_i11" -lt 64 ]; do _i11=$((_i11 + 1)); lrec "$LF/A" "$ASHA" "branch/cap$_i11" --no-push; done
    lrec "$LF/A" "$ASHA" "branch/cap65" --no-push
    _nn="$(_n323)"
    if { [ "$LRC" = 0 ] || [ "$LRC" = 2 ]; } && _opok; then _op323=0; fi
    [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'capped at 64 records' && [ "$(printf '%s\n' "$_nn" | grep -c '^record: promotion')" = 64 ]
  }
  _f_r12() {   # a free-text value that ends in whitespace is refused, naming the field, and nothing is written
    mkledger "$1"; lrec "$LF/A" "$ASHA" "branch/r12" --token "GO "
    if { [ "$LRC" = 0 ] || [ "$LRC" = 2 ]; } && _opok; then _op323=0; fi
    [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q -e '--token ends in whitespace' && [ -z "$(_n323)" ]
  }
  _lracer323() {   # clone B records branch/r3racer on ASHA the moment A's ledger ref moves, once: the window between A's sync-in and A's push
    mkdir -p "$LF/hooks"
    { printf '#!/bin/sh\n[ "$1" = committed ] || exit 0\ngrep -q "refs/notes/%s" || exit 0\n' "$LR"
      printf '[ -e "%s/.raced" ] && exit 0\n: > "%s/.raced"\n' "$LF" "$LF"
      printf 'unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX\n'
      printf '( cd "%s/B" && PROMOTION_NOTES_REF=%s sh "%s" record --approved-sha %s \\\n' "$LF" "$LR" "$VERIFY" "$ASHA"
      printf '  --approved-by racer --gate design --rung integration --class control-plane \\\n'
      printf '  --scope branch/r3racer --token "GO: racer" --basis docs/architecture/x-design.md ) >/dev/null 2>&1\nexit 0\n'
    } > "$LF/hooks/reference-transaction"
    chmod +x "$LF/hooks/reference-transaction"; git -C "$LF/A" config core.hooksPath "$LF/hooks"
  }
  _f_r3() {   # a record that loses the push race re-reads the note after its next sync-in: origin ends with all three records
    mkledger "$1"; lrec "$LF/A" "$ASHA" "branch/r3seed"; _lracer323; lrec "$LF/A" "$ASHA" "branch/r3a"
    _ro="$(git --git-dir="$LF/remote.git" notes --ref="$LR" show "$ASHA" 2>/dev/null)"
    if [ "$LRC" = 0 ]; then _op323=0; fi
    [ "$LRC" = 0 ] && [ "$(printf '%s\n' "$_ro" | sed -n 's/^scope: //p' | LC_ALL=C sort | tr '\n' ' ')" = 'branch/r3a branch/r3racer branch/r3seed ' ]
  }
  _f_l1() {   # a merge GO recorded on a design commit leaves that commit's design record in place
    mkledger "$1"; lrec "$LF/A" "$ASHA" "branch/l1"; lrec "$LF/A" "$ASHA" "PR #5" --gate release-candidate --rung rc
    _nn="$(_n323)"
    if [ "$LRC" = 0 ]; then _op323=0; fi
    [ "$LRC" = 0 ] && printf '%s\n' "$_nn" | grep -q '^gate: design$' && printf '%s\n' "$_nn" | grep -q '^scope: branch/l1$' \
      && printf '%s\n' "$_nn" | grep -q '^gate: release-candidate$'
  }
  _f_s1a() {   # sync refuses a local-only note that holds two records
    mkledger "$1"; lrec "$LF/A" "$ASHA" "branch/s1o"; lrec "$LF/B" "$BSHA" "branch/s1x" --no-push; lrec "$LF/B" "$BSHA" "branch/s1y" --no-push
    lsync "$LF/B"; _lpre="$(lrev "$LF/B")"
    if { [ "$LRC" = 0 ] || [ "$LRC" = 2 ]; } && _opok; then _op323=0; fi   # sync ran to its own verdict (refused, or published under a mutant)
    [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q "REFUSED $BSHA" && printf '%s' "$LOUT" | grep -q "sync --discard-local $BSHA" \
      && printf '%s' "$LOUT" | grep -q 'holds more than one record' && ! printf '%s' "$LOUT" | grep -q "published $BSHA"
  }
  _f_s1b() {   # sync refuses a twin one side of which holds two records
    mkledger "$1"; lrec "$LF/A" "$ASHA" "branch/s1t1"; lrec "$LF/A" "$ASHA" "branch/s1t2"; lrec "$LF/B" "$ASHA" "branch/s1t1" --no-push --token "different token"   # different bytes: the same note in the same second would be the SAME ledger commit, a fast-forward
    lsync "$LF/B"
    if { [ "$LRC" = 0 ] || [ "$LRC" = 2 ]; } && _opok; then _op323=0; fi
    [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q "REFUSED $ASHA" && printf '%s' "$LOUT" | grep -q "sync --discard-local $ASHA" \
      && printf '%s' "$LOUT" | grep -q 'holds more than one record'
  }
  # T1 / D1 repo: base B0 (tree t0), X1 (tree t1, the approved commit), Y (reverts to t0), Z (reapplies t1).
  _t323repo() {
    T3="$LROOT/$1"; mkdir -p "$T3"
    ( set -e; cd "$T3"; git init -q; git config user.email t@example.com; git config user.name t; git config commit.gpgsign false
      printf 'a\n' > f.txt; git add f.txt; git commit -qm b0; git rev-parse HEAD > .B0
      printf 'b\n' >> f.txt; git add f.txt; git commit -qm x1; git rev-parse HEAD > .X1
      git revert --no-edit HEAD >/dev/null 2>&1; git rev-parse HEAD > .Y
      git cherry-pick "$(cat .X1)" >/dev/null 2>&1; git rev-parse HEAD > .Z )
    T3X="$(cat "$T3/.X1")"; T3Z="$(cat "$T3/.Z")"
    T3TREE="$(git -C "$T3" rev-parse "$T3X^{tree}")"
  }
  _t323rec() {   # <gate> <scope> -> a record with an approved-tree
    printf '%s\n' "record: promotion GO (approve->execute->log)" "approved-sha: $T3X" "approved-tree: $T3TREE" "approved-by: o [self-asserted]" \
      "gate: $1" "rung: integration" "change-class: ordinary" "kit-row: (none)" "scope: $2" "approval-token: \"GO\"" "basis: b" "recorded-at: t"
  }
  _f_t1() {   # two records on one commit: a revert-and-reapply in the window cannot claim the commit a second time
    _t323repo "$1"; { _t323rec design branch/t1; printf '\n'; _t323rec release-candidate 'PR #1'; } > "$T3/.note"
    git -C "$T3" notes --ref=promotions add -f -F "$T3/.note" "$T3X"
    LOUT="$( cd "$T3" && $VSH "$VERIFY" trace --recent 4 --from "$T3Z" 2>&1 )" && LRC=0 || LRC=$?
    if { [ "$LRC" = 0 ] || [ "$LRC" = 1 ]; } && _opok; then _op323=0; fi   # trace walked the window to its own verdict
    [ "$LRC" != 0 ] && printf '%s' "$LOUT" | grep -q 'shared-tree with'
  }
  _f_d1() {   # a note whose first line is not a header binds nothing in trace
    _t323repo "$1"; { printf '%s\n' 'stray: not a header'; _t323rec release-candidate 'PR #1'; } > "$T3/.note"
    git -C "$T3" notes --ref=promotions add -f -F "$T3/.note" "$T3X"
    LOUT="$( cd "$T3" && $VSH "$VERIFY" trace --ref "$T3X" 2>&1 )" && LRC=0 || LRC=$?
    if { [ "$LRC" = 0 ] || [ "$LRC" = 1 ]; } && _opok; then _op323=0; fi
    [ "$LRC" = 1 ] && printf '%s' "$LOUT" | grep -q 'RECORDLESS MERGE'
  }
  _j323 R1 _f_r1 - "record scope A then scope B on one sha: both records kept, in order, and published"
  _j323 R1m _f_r1 's/^_pv_note_with() {$/_pv_note_with() { printf "%s\\n" "$nbody"; return 0/' "restoring the replace loses the first record"
  _j323 R2 _f_r2 - "a re-record of the same (scope, gate) supersedes that key once and leaves the other untouched"
  _j323 R2m _f_r2 's/\[ "\$(_pv_rec_field "\$_nw_rec" scope)" = "\$scope" \]/false/' "never dropping the same key leaves two copies"
  _j323 R3 _f_r3 - "a record that loses the push race keeps the racer's record (origin ends with all three)"
  _j323 R3m _f_r3 's/^    if git notes \(.*\) list "\$asha"\(.*\)$/    if [ "\$attempt" = 1 ] \&\& git notes \1 list "\$asha"\2/' "reading the note on the first attempt only erases the racer's record"
  _j323 R11 _f_r11 - "the 65th record on a sha refuses at the 64-record cap and the note keeps all 64"
  _j323 R11m _f_r11 's/if \[ \$((_nw_kept + 1)) -gt 64 \]; then/if false; then/' "dropping the refusal writes a 65th record (a defective note)"
  _j323 R12 _f_r12 - "a --token ending in whitespace is refused naming the field, and nothing is written"
  _j323 R12m _f_r12 's/^  for _p in "token=\$token" "basis=\$basis".*"gate=\$gate"; do$/  for _p in; do/' "dropping the refusal records a value the ledger will strip"
  _j323 R5 _f_r5 - "a --go-by of 'promotion x' stays a field value: two records, one separator"
  _j323 R5m _f_r5 '/function hdr/ s/(record|land)/[A-Za-z0-9_-]+/' "the generic header rule splits the record at the go-by line"
  _j323 L1 _f_l1 - "a merge GO on a design commit leaves its design record in place"
  _j323 L1m _f_l1 's/^_pv_note_with() {$/_pv_note_with() { printf "%s\\n" "$nbody"; return 0/' "restoring the replace erases the design record"
  _j323 S1a _f_s1a - "sync refuses a local-only note that holds two records, naming --discard-local"
  _j323 S1am _f_s1a 's/if _pv_sync_multi "\$_lo_body"; then _pv_sync_refuse_multi "\$1" "the local-only note"; return 0; fi/:/' "dropping the refusal publishes it"
  _j323 S1b _f_s1b - "sync refuses a twin one side of which holds two records"
  _j323 S1bm _f_s1b 's/if _pv_sync_multi "\$2" || _pv_sync_multi "\$3"; then/if false; then/' "dropping the refusal lets the first records decide"
  _j323 T1 _f_t1 - "a revert-and-reapply cannot claim an already-claimed commit a second time"
  _j323 T1m _f_t1 's/awk -v t="\$_tt" .\$1 == t {print \$2 " " \$3; exit}./awk -v t="$_tt" -v c=" $_tr_claimed " '"'"'$1 == t \&\& index(c, " " $2 "#" $3 " ") == 0 {print $2 " " $3; exit}'"'"'/;s/^    _tr_claimed="\$_tr_claimed \$_ta"$/    _tr_claimed="$_tr_claimed $_ta#$_tk"/' "a claim per (object, record) lets a revert-and-reapply take the second record"
  _j323 D1 _f_d1 - "a note with no header binds nothing in trace"
  _j323 D1m _f_d1 '/NR == 1/ s/bad = 1/bad = 0/; /if (hdr(/ s/bad = 1/bad = 0/' "without the first-line rule the stray-first note is traced"

  # =====================================================================================
  # SWAS-323 slice B: `land` writes a LAND record beside the GO record (one transaction, one push) and `trace` binds it. L2 L3 L5a L5b, the serial
  # precondition (SP) and the cap with the land record counted (CAP). The land cells' mutants are built over a layout-carrying COPY of the gate
  # (J323_COPY=1); the only mutant NOT built in-cell is the design's "write the land record in a second push" (it needs a structural change).
  # =====================================================================================
  J323_COPY=1
  _l323_land() {   # <name> -> one serial land on a fresh origin; _l_sq is a trunk squash commit carrying the approved tree
    mkorigin "$1"; rm -f "$LAND_MARK"
    lland "$LAND_STUB" "$LOSHA" control-plane "branch/$1"
    _l_sq="$(git -C "$LOA" commit-tree "${LOSHA}^{tree}" -p "$LOSHA" -m squash 2>/dev/null)" || _l_sq=""
  }
  _l323_trace() {   # <commit> -> LRC, LOUT of `trace --ref`
    if LOUT="$( cd "$LOA" && PROMOTION_NOTES_REF="$LR2" $VSH "$VERIFY" trace --ref "$1" 2>&1 )"; then LRC=0; else LRC=$?; fi
  }
  _l323_extra() {   # a trunk commit whose tree matches neither the approved tree nor any land record: the extra hunk
    ( cd "$LOA" && printf 'x\n' >> f.txt && git commit -qam extra ) >/dev/null 2>&1
    _l_x="$(git -C "$LOA" rev-parse HEAD)"
  }
  _f_l2() {   # the land record rides in the GO's own push, and trace binds the trunk squash through it
    _l323_land "$1"; _l323_trace "$_l_sq"
    if [ "$_ldc" = 0 ] && [ -f "$LAND_MARK" ] && [ "$LRC" = 0 ]; then _op323=0; fi
    _on="$(git --git-dir="$LO/remote.git" notes --ref="$LR2" show "$LOSHA" 2>/dev/null)"
    [ "$_ldc" = 0 ] && [ -f "$LAND_MARK" ] && [ "$(printf '%s\n' "$_on" | grep -c '^land: promotion LAND')" = 1 ] \
      && [ "$(printf '%s\n' "$_on" | grep -c '^record: promotion')" = 1 ] \
      && [ "$(git --git-dir="$LO/remote.git" rev-list --count "refs/notes/$LR2")" = 1 ] \
      && [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q 'land: serial-.* (bound)'
  }
  _f_l3() {   # an extra hunk (a tree equal to neither landed-tree nor approved-tree) reds as recordless; the squash still binds
    _l323_land "$1"; _l323_extra
    _l323_trace "$_l_sq"; _l3a="$LRC"
    _l323_trace "$_l_x"; _l3b="$LRC"
    if [ "$_ldc" = 0 ] && [ -f "$LAND_MARK" ] && { [ "$_l3b" = 0 ] || [ "$_l3b" = 1 ]; }; then _op323=0; fi
    [ "$_l3a" = 0 ] && [ "$_l3b" = 1 ] && printf '%s' "$LOUT" | grep -q 'RECORDLESS MERGE'
  }
  _f_l5a() {   # a re-record of the GO leaves the land record's go-record-sha256 dangling: the land record binds nothing
    _l323_land "$1"; _l323_trace "$_l_sq"; _l5pre="$LOUT"; _l5r0="$LRC"
    ( cd "$LOA" && PATH="$(lgh "$LOSHA" "solo maintainer"):$PATH" PROMOTION_NOTES_REF="$LR2" $VSH "$VERIFY" record --no-push \
        --approved-sha "$LOSHA" --approved-by "solo maintainer" --gate release-candidate --rung rc --class control-plane \
        --scope "PR #77" --go-by "the owner" --token "a different token" ) >/dev/null 2>&1 && _l5rc=0 || _l5rc=$?
    _l323_trace "$_l_sq"
    if [ "$_ldc" = 0 ] && [ "$_l5rc" = 0 ] && [ "$LRC" = 0 ]; then _op323=0; fi
    [ "$_l5r0" = 0 ] && printf '%s' "$_l5pre" | grep -q '(bound)' && ! printf '%s' "$LOUT" | grep -q '(bound)'
  }
  _f_l5b() {   # a land record whose landed-tree differs from its GO's approved-tree binds nothing: that tree reds as recordless
    _l323_land "$1"; _l323_extra
    _l5t="$(git -C "$LOA" rev-parse "${_l_x}^{tree}")"
    git -C "$LOA" notes --ref="$LR2" show "$LOSHA" | sed "s/^landed-tree: .*/landed-tree: $_l5t/" > "$LO/l5b.note"
    git -C "$LOA" notes --ref="$LR2" add -f -F "$LO/l5b.note" "$LOSHA" >/dev/null 2>&1
    _l323_trace "$_l_x"
    if [ "$_ldc" = 0 ] && [ -f "$LAND_MARK" ] && { [ "$LRC" = 0 ] || [ "$LRC" = 1 ]; }; then _op323=0; fi
    [ "$LRC" = 1 ] && printf '%s' "$LOUT" | grep -q 'RECORDLESS MERGE'
  }
  _f_sp() {   # the serial precondition: origin's main is not an ancestor of the approved head, so nothing is recorded or merged
    mkorigin "$1"; rm -f "$LAND_MARK"
    ( cd "$LOA" && git checkout -q -b feat && printf 'f\n' > feat.txt && git add feat.txt && git commit -qm feat-head \
        && git checkout -q "$LOTRUNK" && printf 'n\n' > newer.txt && git add newer.txt && git commit -qm newer \
        && git push -q origin HEAD:refs/heads/main ) >/dev/null 2>&1
    _spx="$(git -C "$LOA" rev-parse feat)"
    lland "$LAND_STUB" "$_spx" control-plane "branch/$1"
    case "$_ld_out" in *'syntax error'*|*'not found'*) ;; *) if [ "$_ldc" = 0 ] || [ "$_ldc" = 1 ]; then _op323=0; fi ;; esac
    LOUT="$_ld_out"; LRC="$_ldc"
    [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && ! onote "$_spx" \
      && printf '%s' "$_ld_out" | grep -q 'serial land needs an up-to-date head; the train computes prefixes'
  }
  _f_cap() {   # 63 records already on the sha: GO + land would make 65, so land refuses at the cap and merges nothing
    mkorigin "$1"; rm -f "$LAND_MARK"; _i63=0
    while [ "$_i63" -lt 63 ]; do
      _i63=$((_i63 + 1))
      ( cd "$LOA" && PATH="$(lgh "$LOSHA" "solo maintainer"):$PATH" PROMOTION_NOTES_REF="$LR2" $VSH "$VERIFY" record --no-push \
          --approved-sha "$LOSHA" --approved-by "solo maintainer" --gate release-candidate --rung rc --class control-plane \
          --scope "branch/cap$_i63" --token "GO" ) >/dev/null 2>&1 || true
    done
    lland "$LAND_STUB" "$LOSHA" control-plane "branch/$1"
    LOUT="$_ld_out"; LRC="$_ldc"
    case "$_ld_out" in *'syntax error'*|*'not found'*) ;; *) if [ "$_ldc" = 0 ] || [ "$_ldc" = 1 ] || [ "$_ldc" = 2 ]; then _op323=0; fi ;; esac
    [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q 'capped at 64 records'
  }
  _j323 L2 _f_l2 - "land writes the land record in the GO's own push (one ledger commit) and trace binds the squash through it"
  _j323 L2m _f_l2 's/"landed-tree: \$atree" \\/"landed-tree: 0000000000000000000000000000000000000000" \\/' "a land record with a landed-tree that is not the approved tree is not bound by trace (the head is the base tip here, so base's tree is not a wrong tree)"
  _j323 L3 _f_l3 - "an extra hunk reds as recordless in trace while the real squash binds"
  _j323 L3m _f_l3 "s/'\$1 == t {print/'{print/" "matching a trunk commit without its tree binds the extra hunk"
  # L3m2, the design's ancestry mutant: a trunk commit is bound to any note whose approved commit is its ancestor. The extra commit in L3 is made on
  # the clone's branch, whose head is the approved commit, so it DOES descend from it and the mutant binds it (the tree test is what stops it).
  _j323 L3m2 _f_l3 's#^    _tak=.*$#    _tak=""; for _ao in $(printf %s "$_tr_map" | cut -d" " -f2); do if git merge-base --is-ancestor "$_ao" "$_tc" >/dev/null 2>\&1; then _tak="$_ao 1"; break; fi; done#' "binding a trunk commit by ancestry of the approved commit binds the extra hunk"
  _j323 L5a _f_l5a - "a re-recorded GO leaves the land record's hash dangling: it stops binding"
  _j323 L5am _f_l5a 's/if \[ "\$_lg_s" = "\$_lg_h" \] &&/if true \&\&/' "accepting a land record without the hash check binds a dangling one"
  _j323 L5b _f_l5b - "a land record whose landed-tree differs from its GO's approved-tree binds nothing"
  _j323 L5bm _f_l5b 's/ && \[ "\$(_pv_rec_field "\$_lg_r" approved-tree)" = "\$_lg_t" \]; then printf/; then printf/' "dropping the tree equality binds the lane-asserted tree"
  _j323 SP _f_sp - "land refuses a head that origin's main is not an ancestor of, before anything is recorded"
  _j323 SPm _f_sp 's/if \[ -z "\$_land_base" \] || \[ "\$_land_brc" -ne 0 \]; then/if false; then/' "dropping the refusal lands a stale head"
  _j323 CAP _f_cap - "the land record counts toward the 64-record cap: 63 records + GO + land refuses"
  _j323 CAPm _f_cap 's/^  if \[ -n "\${lbody:-}" \]; then _nw_kept=\$((_nw_kept + 1)); fi$/  :/' "not counting the land record writes a 65th record"
  J323_COPY=0

  # =====================================================================================
  # SWAS-943: the trunk trace reads the Inception baseline as the baseline, not a recordless merge. In the --recent walk a commit is the
  # baseline only when it is the trunk's ONLY root (a property of the whole history, not of the window), the repository is not shallow, and no
  # note binds it. Cells TB1-TB9; mutants TB1m TB2m TB3m TB3m2 TB4m TB8m, run by _j323 over a sed-edited COPY of the gate. Every fixture is a
  # fresh repository on trunk `main`, root commit unrecorded; a recorded commit carries a hand-written note whose approved-tree is its own tree.
  # =====================================================================================
  _tb_init() {   # <name> -> TBR (a fresh repository, trunk `main`) and TBROOT (its root commit, no note)
    TBR="$LROOT/$1"; rm -rf "$TBR"; mkdir -p "$TBR"
    ( set -e; cd "$TBR"; git init -q; git symbolic-ref HEAD refs/heads/main
      git config user.email t@example.com; git config user.name t; git config commit.gpgsign false
      printf 'a\n' > f.txt; git add f.txt; git commit -qm base ) >/dev/null 2>&1
    TBROOT="$(git -C "$TBR" rev-parse HEAD)"
  }
  _tb_commit() {   # <repo> <file> <content> <message> -> TBC, one parented commit on the trunk
    ( cd "$1" && printf '%s\n' "$3" > "$2" && git add "$2" && git commit -qm "$4" ) >/dev/null 2>&1
    TBC="$(git -C "$1" rev-parse HEAD)"
  }
  _tb_rec() {   # <repo> <commit> <row> -> a GO note on <commit> whose approved-tree is that commit's own tree
    _tbt="$(git -C "$1" rev-parse "$2^{tree}")"
    printf '%s\n' "record: promotion GO (approve->execute->log)" "approved-sha: $2" "approved-tree: $_tbt" \
      "approved-by: o [self-asserted]" "gate: release-candidate" "rung: r" "change-class: ordinary" "kit-row: $3" \
      "scope: PR #1" "approval-token: \"GO\"" "basis: b" "recorded-at: t" > "$1.note"
    git -C "$1" notes --ref=promotions add -f -F "$1.note" "$2" >/dev/null 2>&1
  }
  _tb_ledger() {   # <repo> -> a ledger that binds nothing on the trunk: one note on a side commit (off the trunk, on the empty tree no trunk commit has)
    _tbside="$(git -C "$1" commit-tree "$(git -C "$1" hash-object -t tree /dev/null)" -m side)"
    _tb_rec "$1" "$_tbside" TB-SIDE
  }
  _tb_splice() {   # <repo> -> TBO (an unrelated single-commit orphan) merged onto the trunk, TBC (the merge commit): a SECOND root
    ( cd "$1" && git checkout -q --orphan tborphan && git rm -rfq . && printf 'z\n' > z.txt && git add z.txt && git commit -qm orphan \
        && git checkout -q main && git merge -q --allow-unrelated-histories --no-edit tborphan ) >/dev/null 2>&1
    TBO="$(git -C "$1" rev-parse tborphan)"; TBC="$(git -C "$1" rev-parse HEAD)"
  }
  _tb_run() {   # <repo> <trace args...> -> LRC and LOUT (stdout and stderr together); the operation ran when it reached its own verdict
    _tbd="$1"; shift
    if LOUT="$( cd "$_tbd" && $VSH "$VERIFY" trace "$@" 2>&1 )"; then LRC=0; else LRC=$?; fi
    # The operation RAN only when the trace reached its own verdict: the no-ledger early exit (rc 1, "nothing to trace against") is no verdict,
    # so a mutant that reds through it is never counted as killed (_j323 reads _op323).
    case "$LOUT" in *'nothing to trace against'*) return 0 ;; esac
    if { [ "$LRC" = 0 ] || [ "$LRC" = 1 ]; } && _opok; then _op323=0; fi
  }
  _tb_has() { printf '%s\n' "$LOUT" | grep -qF -- "$1"; }
  _tb_cnt() { printf '%s\n' "$LOUT" | grep -cF -- "$1" || true; }
  _tb_s12() { printf '%s' "$1" | cut -c1-12; }
  _f_tb1() {   # root (no note), then one recorded commit: green, the baseline line, exact counts, no RECORDLESS text
    _tb_init "$1"; _tb_commit "$TBR" a.txt a1 'recorded a'; _tb_rec "$TBR" "$TBC" TB-ROW-1
    _tb_run "$TBR" --recent 2 --from main
    [ "$LRC" = 0 ] && _tb_has "$(_tb_s12 "$TBROOT")  baseline: the trunk's only root commit, unrecorded by design (Inception precedes the GO ledger)" \
      && _tb_has '1/1 bound of the last 2 commit(s)' && _tb_has '1 is the Inception baseline' && ! _tb_has 'RECORDLESS MERGE'
  }
  _f_tb2() {   # root (no note), then one unrecorded commit: the commit reds as RECORDLESS, the root reads as the baseline and only that
    _tb_init "$1"; _tb_commit "$TBR" a.txt a1 'unrecorded a'; _tb_one="$TBC"; _tb_ledger "$TBR"
    _tb_run "$TBR" --recent 2 --from main
    [ "$LRC" = 1 ] && _tb_has "trace: $_tb_one has no promotion note" && ! _tb_has "trace: $TBROOT has no promotion note" \
      && _tb_has "$(_tb_s12 "$TBROOT")  baseline: " && [ "$(_tb_cnt 'RECORDLESS MERGE')" = 1 ]
  }
  _f_tb3() {   # a second root spliced in (its merge commit recorded): nothing is exempt, so the root and the orphan both red
    _tb_init "$1"; _tb_commit "$TBR" a.txt a1 'recorded a'; _tb_one="$TBC"; _tb_rec "$TBR" "$_tb_one" TB-ROW-3
    _tb_splice "$TBR"; _tb_rec "$TBR" "$TBC" TB-ROW-3m
    _tb_run "$TBR" --recent 4 --from main
    [ "$LRC" = 1 ] && ! _tb_has 'unrecorded by design' && _tb_has "trace: $TBO has no promotion note" \
      && _tb_has "trace: $TBROOT has no promotion note" && ! _tb_has "trace: $_tb_one has no promotion note" \
      && ! _tb_has "trace: $TBC has no promotion note" && [ "$(_tb_cnt 'RECORDLESS MERGE')" = 2 ]
  }
  _f_tb4() {   # a window holding only the baseline asserts nothing: it reds
    _tb_init "$1"; _tb_ledger "$TBR"
    _tb_run "$TBR" --recent 1 --from main
    [ "$LRC" = 1 ] && _tb_has 'only the Inception baseline' && _tb_has "$(_tb_s12 "$TBROOT")  baseline: " && ! _tb_has 'OK: trace'
  }
  _f_tb5() {   # --ref is unchanged: asked about the root by name, the trace still answers RECORDLESS
    _tb_init "$1"; _tb_ledger "$TBR"
    _tb_run "$TBR" --ref "$TBROOT"
    [ "$LRC" = 1 ] && _tb_has 'RECORDLESS MERGE' && ! _tb_has 'unrecorded by design'
  }
  _f_tb6() {   # the true root is OUTSIDE the window, a single-commit orphan is spliced in: two roots on the trunk, so the orphan is no baseline
    _tb_init "$1"; _tb_i=0
    while [ "$_tb_i" -lt 5 ]; do
      _tb_i=$((_tb_i + 1)); _tb_commit "$TBR" "t$_tb_i.txt" "v$_tb_i" "trunk $_tb_i"; _tb_rec "$TBR" "$TBC" "TB-ROW-6-$_tb_i"
    done
    _tb_splice "$TBR"; _tb_rec "$TBR" "$TBC" TB-ROW-6m
    _tb_run "$TBR" --recent 3 --from main
    [ "$LRC" = 1 ] && ! _tb_has 'unrecorded by design' && _tb_has "trace: $TBO has no promotion note" && [ "$(_tb_cnt 'RECORDLESS MERGE')" = 1 ]
  }
  _tb7_build() {   # <name> -> TBS, a depth-1 clone of a trunk whose tip carries no note; rc 1 when the clone cannot be made shallow here
    _tb_init "$1"; _tb_commit "$TBR" a.txt a1 'recorded a'; _tb_rec "$TBR" "$TBC" TB-ROW-7
    _tb_commit "$TBR" b.txt b1 'unrecorded tip'; TBTIP="$TBC"
    TBS="$TBR-shallow"; rm -rf "$TBS"
    git clone -q --depth 1 "file://$TBR" "$TBS" >/dev/null 2>&1 || return 1
    git -C "$TBS" fetch -q origin "refs/notes/promotions:refs/notes/promotions" >/dev/null 2>&1 || return 1
    [ "$(git -C "$TBS" rev-parse --is-shallow-repository 2>/dev/null)" = true ]
  }
  _f_tb7() {   # a shallow clone: its boundary commit looks like a root, so no exemption; one line says why; the tip reds
    _tb7_build "$1" || return 1
    _tb_run "$TBS" --recent 2 --from main
    [ "$LRC" = 1 ] && _tb_has 'baseline: not checked (shallow clone; fetch the full history to exempt the Inception baseline)' \
      && ! _tb_has 'unrecorded by design' && _tb_has "trace: $TBTIP has no promotion note"
  }
  _f_tb8() {   # a replace-graft makes an unrecorded commit look parentless: the probe ignores it, so that commit is no baseline and reds
    _tb_init "$1"; _tb_commit "$TBR" a.txt a1 'unrecorded one'; _tb_one="$TBC"
    _tb_commit "$TBR" b.txt b1 'recorded two'; _tb_rec "$TBR" "$TBC" TB-ROW-8
    git -C "$TBR" replace --graft "$_tb_one" >/dev/null 2>&1 || return 1
    _tb_run "$TBR" --recent 2 --from main
    [ "$LRC" = 1 ] && ! _tb_has 'unrecorded by design' && _tb_has "trace: $_tb_one has no promotion note" && [ "$(_tb_cnt 'RECORDLESS MERGE')" = 1 ]
  }
  _f_tb10g() {   # a .git/info/grafts file cuts the real root off: the gate exempts nothing, says why, and the parentless-looking commit reds
    _tb_init "$1"; _tb_commit "$TBR" a.txt a1 'unrecorded one'; _tb_one="$TBC"
    _tb_commit "$TBR" b.txt b1 'recorded two'; _tb_rec "$TBR" "$TBC" TB-ROW-10
    mkdir -p "$TBR/.git/info"; printf '%s\n' "$_tb_one" > "$TBR/.git/info/grafts"
    _tb_run "$TBR" --recent 2 --from main
    [ "$LRC" = 1 ] && _tb_has 'baseline: not checked (a .git/info/grafts file is present; grafts can make any commit look like a root)' \
      && ! _tb_has 'unrecorded by design' && _tb_has "trace: $_tb_one has no promotion note" && [ "$(_tb_cnt 'RECORDLESS MERGE')" = 1 ]
  }
  _f_tb11() {   # the root carries its OWN note (plus one recorded commit): it binds like any commit, no baseline line, 2/2 bound
    _tb_init "$1"; _tb_rec "$TBR" "$TBROOT" TB-ROW-11r; _tb_commit "$TBR" a.txt a1 'recorded a'; _tb_rec "$TBR" "$TBC" TB-ROW-11
    _tb_run "$TBR" --recent 2 --from main
    [ "$LRC" = 0 ] && ! _tb_has 'baseline:' && _tb_has '2/2 of the last 2 commit(s) on main are bound to a promotion note' && ! _tb_has 'Inception baseline'
  }
  _f_tb9() {   # two unrecorded PARENTED commits (the root is outside the window): neither is a baseline; both red
    _tb_init "$1"; _tb_commit "$TBR" a.txt a1 'unrecorded one'; _tb_one="$TBC"; _tb_commit "$TBR" b.txt b1 'unrecorded two'; _tb_two="$TBC"; _tb_ledger "$TBR"
    _tb_run "$TBR" --recent 2 --from main
    [ "$LRC" = 1 ] && ! _tb_has 'unrecorded by design' && _tb_has "trace: $_tb_one has no promotion note" \
      && _tb_has "trace: $_tb_two has no promotion note"
  }
  _j323 TB1 _f_tb1 - "the trunk's only root, unrecorded, reads as the Inception baseline: green, one baseline line, 1/1 bound, no RECORDLESS text"
  _j323 TB2 _f_tb2 - "an unrecorded commit after the baseline reds as RECORDLESS while the root reads as the baseline and only that"
  _j323 TB3 _f_tb3 - "a second root spliced in turns the exemption off: the root and the orphan both red"
  _j323 TB4 _f_tb4 - "a window holding only the baseline reds: no bound commit, so a green would assert nothing"
  _j323 TB5 _f_tb5 - "trace --ref on the root keeps its strict answer (RECORDLESS MERGE)"
  _j323 TB6 _f_tb6 - "a spliced orphan inside a window whose true root is outside it is no baseline (two roots on the trunk)"
  if _tb7_build tb7probe; then
    _j323 TB7 _f_tb7 - "a shallow clone exempts nothing and says so (the boundary commit looks like a root)"
  else
    echo "selftest TB7: not built, because the depth-1 clone could not be made shallow here (git clone --depth over file://, the notes fetch, or --is-shallow-repository was not available); TB7 and TB4m were NOT run"
  fi
  _j323 TB8 _f_tb8 - "a replace-graft cannot fake a root: the probe ignores replace refs, so the grafted commit reds"
  _j323 TB9 _f_tb9 - "an unrecorded PARENTED commit is never the baseline (the root test bites)"
  _j323 TB10g _f_tb10g - "a .git/info/grafts file turns the exemption off, says so, and the commit it makes look parentless reds"
  _j323 TB11 _f_tb11 - "a root that carries its own note binds like any commit: no baseline line, 2/2 bound, no baseline clause"
  _j323 TB10gm _f_tb10g 's/^    _tr_shallow=grafted$/    :/' "dropping the grafts test lets the grafted commit read as the only root, and exempts it"
  _j323 TB1m _f_tb9 's/\[ "\$_tr_roots" = "\$_tr_c" \]/true/' "treating any unbindable commit as the baseline exempts a parented one"
  _j323 TB2m _f_tb6 's#\[ "\$_tr_roots" = "\$_tr_c" \]#[ "$(git rev-list --parents -n 1 "$_tr_c" | wc -w | tr -d " ")" = 1 ]#' "testing 'a root in the window' instead of 'the trunk's only root' exempts a spliced orphan"
  _j323 TB3m _f_tb1 's/_tr_n - _tr_miss - _tr_base/_tr_n - _tr_miss/' "counting the baseline as bound changes the exact numbers"
  _j323 TB3m2 _f_tb4 's/_tr_n - _tr_miss - _tr_base/_tr_n - _tr_miss/' "counting the baseline as bound lets a baseline-only window go green"
  if _tb7_build tb7probe; then
    _j323 TB4m _f_tb7 's/\[ "\$_tr_shallow" = false \] && //' "skipping the shallow test exempts a shallow boundary commit"
  fi
  # TB8m: the gate exports GIT_NO_REPLACE_OBJECTS=1 for the whole script (line 120), so the probe's own --no-replace-objects is redundant and
  # dropping it alone changes nothing: that flag-only mutant is equivalent and is NOT built. This mutant drops BOTH, so the graft is honoured, the
  # grafted commit is the trunk's only reachable root, and it reads as the baseline (rc 0 plus the baseline line); the real gate reds it (rc 1).
  # A caller environment that itself exports GIT_NO_REPLACE_OBJECTS makes this mutant read SURVIVED, which fails closed (the cell then flags it).
  _j323 TB8m _f_tb8 's/^export GIT_NO_REPLACE_OBJECTS=1/:/;s/git -c core.commitGraph=false --no-replace-objects rev-list --max-parents=0/git -c core.commitGraph=false rev-list --max-parents=0/' "a gate that honours replace refs lets a graft make the grafted commit the only root, and exempts it"

  # =====================================================================================
  # SWAS-901 slice A: `go-bound`, the read-only verb the solo-go-bound workflow runs from the BASE branch. It prints exactly one line,
  # `go-bound: na|ok|missing|error [reason]`, and writes nothing. Each cell is run by _j323 against the real gate (must hold) and, for the
  # mutants, against a sed-edited COPY (must NOT hold). GB-T1..GB-T12 read the relationship from the DEFAULT branch's tip (refs/kit/solo-go-default, set to the base B by the fixture) and the PR head by sha; GB-T9c
  # is a LAND cell (a layout-carrying copy). The fixture is a plain repository: HEAD is the base B, the PR head sits on another branch, and
  # the GO notes are written by the real `record --no-push` (so a note has the shape the verb really reads).
  # =====================================================================================
  G901_REAL="$VERIFY"
  _g901_repo() {   # <name> <dial|NONE> <claude-md line|NONE> -> G_R (the repository, HEAD = the base tip) and G_B (that tip)
    G_R="$LROOT/g901-$1"; rm -rf "$G_R"; mkdir -p "$G_R"
    ( set -e; cd "$G_R"; git init -q; git config user.email t@example.com; git config user.name t; git config commit.gpgsign false
      printf 'a\n' > f.txt; git add f.txt
      if [ "$2" != NONE ]; then mkdir -p .kit; printf '%s\n' "$2" > .kit/dials.conf; git add .kit/dials.conf; fi
      if [ "$3" != NONE ]; then printf '%s\n' "$3" > CLAUDE.md; git add CLAUDE.md; fi
      git commit -qm base; git update-ref refs/kit/solo-go-default HEAD ) >/dev/null 2>&1
    G_B="$(git -C "$G_R" rev-parse HEAD)"
  }
  _g901_head() {   # <repo> <parent> <change|design|empty> [<dial line>] -> G_H, a commit on <parent>; HEAD goes back to the base tip. `design` is `change` plus a docs/architecture/x-design.md the head adds (a design GO's basis must be touched by its approved commit, SWAS-944)
    ( set -e; cd "$1"; git checkout -q "$2"
      if [ "$3" = change ] || [ "$3" = design ]; then
        printf '%s\n' "$2" >> f.txt; git add f.txt
        if [ "$3" = design ]; then
          mkdir -p docs/architecture
          printf '# Fixture design\n\nA design the PR head adds so its design GO names a tracked, touched file.\nIt carries several real lines so it is more than a stub.\nThe approved commit is the one that last touched it.\n' > docs/architecture/x-design.md
          git add docs/architecture/x-design.md
        fi
        if [ -n "${4:-}" ]; then mkdir -p .kit; printf '%s\n' "$4" > .kit/dials.conf; git add .kit/dials.conf; fi
        git commit -qm pr
      else git commit -q --allow-empty -m empty; fi
      git rev-parse HEAD > "$1.sha"; git checkout -q "$G_B" ) >/dev/null 2>&1
    G_H="$(cat "$1.sha" 2>/dev/null || true)"
  }
  _g901_rec() {   # <repo> <sha> <scope> <gate> [<class>] -> one GO record on <sha>, written offline by the real verb
    if [ "$4" = design ]; then
      ( cd "$1" && $VSH "$G901_REAL" record --no-push --approved-sha "$2" --approved-by "solo maintainer" --go-by "the owner" --gate design \
          --rung integration --class "${5:-control-plane}" --scope "$3" --token "GO: design $2" --basis docs/architecture/x-design.md ) >/dev/null 2>&1
    else
      ( cd "$1" && $VSH "$G901_REAL" record --no-push --approved-sha "$2" --approved-by "solo maintainer" --go-by "the owner" --gate "$4" \
          --rung rc --class "${5:-ordinary}" --scope "$3" --token "GO: $4 $2" ) >/dev/null 2>&1
    fi
  }
  _g901_gb() {   # <repo> <sha> <pr> [<base-ref> = main] [<default-branch> = main] -> LOUT (stdout), LRC
    if LOUT="$( cd "$1" && $VSH "$VERIFY" go-bound --approved-sha "$2" --pr "$3" --base-ref "${4:-main}" --default-branch "${5:-main}" 2>/dev/null )"; then LRC=0; else LRC=$?; fi
  }
  _g901_ran() { case "$LOUT" in 'go-bound: '*) _op323=0 ;; esac; }   # the verb ran to its own verdict, so only the property may differ under a mutant
  _g901_is() {   # <word> -> 0 when LOUT is exactly one line, `go-bound: <word>` with an optional reason
    [ "$(printf '%s\n' "$LOUT" | wc -l | tr -d ' ')" = 1 ] || return 1
    case "$LOUT" in "go-bound: $1"|"go-bound: $1 "*) return 0 ;; esac
    return 1
  }
  _g901_snap() { ( cd "$1" && git for-each-ref && git notes --ref=promotions list ) 2>&1; }
  _g901_solo() {   # <name> [<head mode> = change] -> a solo base, a PR head G_H on it and a valid merge-gate record for PR #7 on that head
    _g901_repo "$1" MERGE_RELATIONSHIP=solo NONE; _g901_head "$G_R" "$G_B" "${2:-change}"
    _g901_rec "$G_R" "$G_H" "PR #7" release-candidate
  }
  _f_gb1() {   # a base that reads team or has no dial is na, though the PR head declares solo and carries a valid note
    _g901_repo "${1}a" NONE NONE; _gr1="$G_R"; _g901_head "$_gr1" "$G_B" change MERGE_RELATIONSHIP=solo; _gh1="$G_H"
    _g901_rec "$_gr1" "$_gh1" "PR #7" release-candidate || return 1
    _g901_repo "${1}b" MERGE_RELATIONSHIP=team NONE; _gr2="$G_R"; _g901_head "$_gr2" "$G_B" change MERGE_RELATIONSHIP=solo; _gh2="$G_H"
    _g901_rec "$_gr2" "$_gh2" "PR #7" release-candidate || return 1
    _g901_gb "$_gr1" "$_gh1" 7; _gt1="$LOUT"; _gc1="$LRC"
    _g901_gb "$_gr2" "$_gh2" 7; _g901_ran
    [ "$_gt1" = "go-bound: na" ] && [ "$_gc1" = 0 ] && [ "$LOUT" = "go-bound: na" ] && [ "$LRC" = 0 ]
  }
  _f_gb2() {   # solo base + one valid merge-gate record for this PR, bound to the head -> ok
    _g901_solo "$1" || return 1
    _g901_gb "$G_R" "$G_H" 7; _g901_ran
    _g901_is ok && [ "$LRC" = 0 ]
  }
  _f_gb3a() {   # a record that names the head but sits on ANOTHER sha (the base) is no GO on the head
    _g901_solo "$1" || return 1
    ( cd "$G_R" && git notes --ref=promotions copy "$G_H" "$G_B" && git notes --ref=promotions remove "$G_H" ) >/dev/null 2>&1 || return 1
    _g901_gb "$G_R" "$G_H" 7; _g901_ran
    _g901_is missing
  }
  _f_gb3b() {   # a note on the head that names an OLDER sha with the SAME tree (an empty commit pushed after the GO) binds nothing
    _g901_repo "$1" MERGE_RELATIONSHIP=solo NONE; _g901_head "$G_R" "$G_B" change; _gold="$G_H"
    _g901_head "$G_R" "$_gold" empty
    _g901_rec "$G_R" "$_gold" "PR #7" release-candidate || return 1
    ( cd "$G_R" && git notes --ref=promotions copy "$_gold" "$G_H" ) >/dev/null 2>&1 || return 1
    _g901_gb "$G_R" "$G_H" 7; _g901_ran
    _g901_is missing
  }
  _f_gb3c() {   # an approved-sha line that is only the 12-character prefix of the head binds nothing
    _g901_solo "$1" || return 1
    ( cd "$G_R" && git notes --ref=promotions show "$G_H" | sed "s/^approved-sha: .*/approved-sha: $(printf '%s' "$G_H" | cut -c1-12)/" > "$G_R.note" \
        && git notes --ref=promotions add -f -F "$G_R.note" "$G_H" ) >/dev/null 2>&1 || return 1
    _g901_gb "$G_R" "$G_H" 7; _g901_ran
    _g901_is missing
  }
  _f_gb4a() {   # a design-gate record and a merge-gate record for the same PR: the merge-gate one is judged -> ok
    _g901_solo "$1" design || return 1
    _g901_rec "$G_R" "$G_H" "PR #7" design || return 1
    _g901_gb "$G_R" "$G_H" 7; _g901_ran
    _g901_is ok
  }
  _f_gb4b() {   # a design GO alone is not a merge GO -> missing
    _g901_repo "$1" MERGE_RELATIONSHIP=solo NONE; _g901_head "$G_R" "$G_B" design
    _g901_rec "$G_R" "$G_H" "PR #7" design || return 1
    _g901_gb "$G_R" "$G_H" 7; _g901_ran
    _g901_is missing
  }
  _f_gb5() {   # the only record is scoped to ANOTHER PR: no one-record shortcut -> missing
    _g901_repo "$1" MERGE_RELATIONSHIP=solo NONE; _g901_head "$G_R" "$G_B" change
    _g901_rec "$G_R" "$G_H" "PR #8" release-candidate || return 1
    _g901_gb "$G_R" "$G_H" 7; _g901_ran
    _g901_is missing
  }
  _f_gb6() {   # two merge-gate records for this PR (two gates) are ambiguous, never guessed -> missing
    _g901_solo "$1" || return 1
    _g901_rec "$G_R" "$G_H" "PR #7" merge || return 1
    _g901_gb "$G_R" "$G_H" 7; _g901_ran
    _g901_is missing
  }
  _f_gb7() {   # a PR that targets a branch other than the default -> error, rc 2
    _g901_solo "$1" || return 1
    _g901_gb "$G_R" "$G_H" 7 feature main; _g901_ran
    _g901_is error && [ "$LRC" = 2 ]
  }
  _f_gb7b() {   # a base that reads team (or has no dial) is na even for a PR into a non-default branch: team reads na, never error
    _g901_repo "${1}a" MERGE_RELATIONSHIP=team NONE; _gr1="$G_R"; _g901_head "$_gr1" "$G_B" change; _g901_rec "$_gr1" "$G_H" "PR #7" release-candidate || return 1
    _g901_gb "$_gr1" "$G_H" 7 feature main; _gt1="$LOUT"; _gc1="$LRC"
    _g901_repo "${1}b" NONE NONE; _g901_head "$G_R" "$G_B" change; _g901_rec "$G_R" "$G_H" "PR #7" release-candidate || return 1
    _g901_gb "$G_R" "$G_H" 7 feature main; _g901_ran
    [ "$_gt1" = "go-bound: na" ] && [ "$_gc1" = 0 ] && [ "$LOUT" = "go-bound: na" ] && [ "$LRC" = 0 ]
  }
  _f_gb7c() {   # S-1: the default branch reads solo and the PR's own base (the checkout, HEAD) reads team: still error, never na
    _g901_repo "$1" MERGE_RELATIONSHIP=solo NONE
    ( set -e; cd "$G_R"; git checkout -q "$G_B"; printf 'MERGE_RELATIONSHIP=team\n' > .kit/dials.conf; git commit -qam x; git rev-parse HEAD > "$G_R.x" ) >/dev/null 2>&1 || return 1
    _gx="$(cat "$G_R.x")"; _g901_head "$G_R" "$_gx" change; _g901_rec "$G_R" "$G_H" "PR #7" release-candidate || return 1
    ( cd "$G_R" && git checkout -q "$_gx" ) >/dev/null 2>&1 || return 1
    _g901_gb "$G_R" "$G_H" 7 x main; _g901_ran
    _g901_is error && [ "$LRC" = 2 ]
  }
  _f_gb10() {   # the head commit is not in the object store -> error, rc 2
    _g901_repo "$1" MERGE_RELATIONSHIP=solo NONE
    _g901_gb "$G_R" 0123456789012345678901234567890123456789 7; _g901_ran
    _g901_is error && [ "$LRC" = 2 ]
  }
  _f_gb11() {   # a note whose first line is no record header is malformed and binds nothing -> missing
    _g901_solo "$1" || return 1
    ( cd "$G_R" && { printf 'stray: x\n'; git notes --ref=promotions show "$G_H"; } > "$G_R.bad" && git notes --ref=promotions add -f -F "$G_R.bad" "$G_H" ) >/dev/null 2>&1 || return 1
    _g901_gb "$G_R" "$G_H" 7; _g901_ran
    _g901_is missing
  }
  _f_gb12() {   # no GO ledger at all (S-2): a team default reads na, a solo default reads missing
    _g901_repo "${1}a" MERGE_RELATIONSHIP=team NONE; _g901_head "$G_R" "$G_B" change
    _g901_gb "$G_R" "$G_H" 7; _gt1="$LOUT"; _gc1="$LRC"
    _g901_repo "${1}b" MERGE_RELATIONSHIP=solo NONE; _g901_head "$G_R" "$G_B" change
    _g901_gb "$G_R" "$G_H" 7; _g901_ran
    [ "$_gt1" = "go-bound: na" ] && [ "$_gc1" = 0 ] && _g901_is missing && [ "$LRC" = 0 ]
  }
  _f_gb8() {   # a Governance team line on the base tightens a solo dial -> na
    _g901_repo "$1" MERGE_RELATIONSHIP=solo '- **Governance** (§ solo/team): team — non-author approval'; _g901_head "$G_R" "$G_B" change
    _g901_rec "$G_R" "$G_H" "PR #7" release-candidate || return 1
    _g901_gb "$G_R" "$G_H" 7; _g901_ran
    _g901_is na
  }
  _f_gb9() {   # go-bound writes no ref and no note: the ref list and the ledger are equal before and after
    _g901_solo "$1" || return 1
    _g901_snap "$G_R" > "$G_R.s0"
    _g901_gb "$G_R" "$G_H" 7; _g901_ran
    _g901_snap "$G_R" > "$G_R.s1"
    _g901_is ok && [ -s "$G_R.s0" ] && cmp -s "$G_R.s0" "$G_R.s1"
  }
  _f_gb9b() {   # stdout is exactly one `go-bound:` line, and a bad flag is an error with rc 2
    _g901_solo "$1" || return 1
    _g901_gb "$G_R" "$G_H" 7; _g901_ran; _gok=1
    if [ "$(printf '%s\n' "$LOUT" | wc -l | tr -d ' ')" = 1 ] && printf '%s\n' "$LOUT" | grep -Eq '^go-bound: (na|ok|missing|error)( .*)?$'; then _gok=0; fi
    _g901_gb "$G_R" nothex 7
    [ "$_gok" = 0 ] && [ "$LRC" = 2 ] && _g901_is error
  }
  _f_gb9c() {   # the relationship and merge GO lines of a solo land are unchanged by the factoring (a LAND cell)
    mkorigin "$1"; lsolo_base MERGE_RELATIONSHIP=solo; rm -f "$LAND_MARK"
    lland "$LAND_STUB" "$LOSHA" control-plane "branch/$1"
    LOUT="$_ld_out"; LRC="$_ldc"
    if [ "$_ldc" = 0 ] && [ -f "$LAND_MARK" ]; then _op323=0; fi
    [ "$_ldc" = 0 ] && [ -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -qF -e 'merge relationship: solo (origin/main'
  }
  # SWAS-948. record now refuses `--gate promotion`, so a legacy record is PLANTED here by rewriting the gate line of a real one.
  _g948_regate() {   # <repo> <sha> <sed script> -> rewrites the note on <sha> in place
    ( cd "$1" && git notes --ref=promotions show "$2" | sed "$3" > "$1.note" && git notes --ref=promotions add -f -F "$1.note" "$2" ) >/dev/null 2>&1
  }
  _f_coex() {   # THE DISCLOSED TRANSITIONAL STATE: a legacy `promotion` record beside a new `merge` record for one PR is two merge-gate records, so go-bound fails closed
    _g901_repo "$1" MERGE_RELATIONSHIP=solo NONE; _g901_head "$G_R" "$G_B" change
    _g901_rec "$G_R" "$G_H" "PR #7" merge || return 1
    _g901_rec "$G_R" "$G_H" "PR #7" release-candidate || return 1
    _g948_regate "$G_R" "$G_H" 's/^gate: release-candidate$/gate: promotion/' || return 1
    _g948_n="$( cd "$G_R" && git notes --ref=promotions show "$G_H" 2>/dev/null )"
    printf '%s\n' "$_g948_n" | grep -qx 'gate: promotion' && printf '%s\n' "$_g948_n" | grep -qx 'gate: merge' || return 1   # both records exist on the same sha and scope
    _g901_gb "$G_R" "$G_H" 7; _g901_ran
    _g901_is missing
  }
  _f_gbt() {   # pv_go_gate_typed's letter boundary, on a planted note: the pick keeps `planned-release` as a merge-gate record, so go-bound
    # reaches the solo bar, whose design*/plan* prefix then refuses it as a pre-build gate (fail closed). Without the boundary the pick drops
    # the record first and go-bound says missing for another reason, so the solo-bar reason is what pins the boundary.
    _g901_repo "$1" MERGE_RELATIONSHIP=solo NONE; _g901_head "$G_R" "$G_B" change
    _g901_rec "$G_R" "$G_H" "PR #7" merge || return 1
    _g948_regate "$G_R" "$G_H" 's/^gate: merge$/gate: planned-release/' || return 1
    ( cd "$G_R" && git notes --ref=promotions show "$G_H" 2>/dev/null | grep -qx 'gate: planned-release' ) || return 1
    _g901_gb "$G_R" "$G_H" 7; _g901_ran
    _g901_is missing && printf '%s' "$LOUT" | grep -qF -e "gate 'planned-release' is a pre-build gate"
  }
  J323_COPY=0
  _j323 GB-T1 _f_gb1 - "go-bound: a base that reads team or has no dial is na, though the PR head declares solo"
  _j323 GB-T1m _f_gb1 's@^  _gb_tip=.*$@  _gb_tip="$_gb_sha"@' "reading the dial from the PR head instead of the base tip opens a solo reading"
  _j323 GB-T2 _f_gb2 - "go-bound: a solo base and one valid merge-gate record scoped to the PR, bound to the head, is ok"
  _j323 GB-T2m _f_gb2 's@echo "go-bound: ok"@echo "go-bound: missing"@' "a verb that never says ok is not live"
  _j323 GB-T3a _f_gb3a - "go-bound: a record that names the head but sits on another sha is no GO on the head"
  _j323 GB-T3am _f_gb3a 's@notes --ref="\$NOTES_REF" show "\$_gb_sha"@notes --ref="$NOTES_REF" show HEAD@' "looking the note up on the base tip finds a GO that is not the head's"
  _j323 GB-T3b _f_gb3b - "go-bound: a note on the head that names an older sha with the same tree binds nothing"
  _j323 GB-T3bm _f_gb3b 's@if \[ "\$_sgb" != "\$_sga" .; then@if false; then@' "without leg 1 (the sha) only the tree is read, and a same-tree sha passes"
  _j323 GB-T3c _f_gb3c - "go-bound: a 12-character prefix in approved-sha binds nothing"
  _j323 GB-T3cm _f_gb3c 's@if \[ "\$_sgb" != "\$_sga" .; then@if [ -z "$_sgb" ] || [ "${_sga#"$_sgb"}" = "$_sga" ]; then@' "comparing the sha by prefix accepts a 12-character name"
  _j323 GB-T4a _f_gb4a - "go-bound: a design record beside a merge record for the PR leaves the merge record judged"
  _j323 GB-T4am _f_gb4a 's@^    if pv_go_gate_typed "\$(_pv_rec_field "\$_gp_r" gate)"; then continue; fi$@    :@' "without the gate filter two records are kept and the pick refuses"
  _j323 GB-T4b _f_gb4b - "go-bound: a design GO alone is not a merge GO"
  _j323 GB-T4bm _f_gb4b 's@^    if pv_go_gate_typed "\$(_pv_rec_field "\$_gp_r" gate)"; then continue; fi$@    :@;s@^    design\*|plan\*)$@    zz-never)@' "a typed gate treated as a merge gate in the pick and in leg 4 is judged ok"
  _j323 GB-T5 _f_gb5 - "go-bound: the only record is for another PR, so there is no one-record shortcut"
  _j323 GB-T5m _f_gb5 's@^    \[ "\$(pv_ev_pr_number .*|| continue$@    :@' "accepting a single record whatever its scope merges under another PR's GO"
  _j323 GB-T6 _f_gb6 - "go-bound: two merge-gate records for this PR are ambiguous, never guessed"
  _j323 GB-T6m _f_gb6 's@^  \[ "\$_gp_kept" = 1 . || return 1$@  [ "$_gp_kept" -ge 1 ] || return 1@' "picking the first of two records judges one by position"
  _j323 GB-T7 _f_gb7 - "go-bound: a PR into a branch that is not the default is an error, rc 2"
  _j323 GB-T7m _f_gb7 's@^  if \[ "\$_gb_base" != "\$_gb_def" .; then$@  if false; then@' "skipping the base-ref check judges a PR into a feature branch"
  _j323 GB-T7b _f_gb7b - "go-bound: a team or undeclared base is na even for a PR into a non-default branch"
  _j323 GB-T7bm _f_gb7b 's@^  if \[ "\$PV_REL" != solo \]; then _gb_say na; return 0; fi$@  if [ "$PV_REL" != solo ] \&\& [ "$_gb_base" = "$_gb_def" ]; then _gb_say na; return 0; fi@' "running the base-ref check ahead of the relationship read reds a team repository's PR into a feature branch"
  _j323 GB-T7c _f_gb7c - "go-bound: a default branch that reads solo is error for a PR whose own base reads team (a retargeted PR)"
  _j323 GB-T7cm _f_gb7c 's@^  _gb_tip=.*$@  _gb_tip="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)"@' "reading the relationship from the checkout instead of the default branch tip lets a retargeted PR read team"
  _j323 GB-T10 _f_gb10 - "go-bound: a head commit that is not in the object store is an error, rc 2"
  _j323 GB-T10m _f_gb10 's@^  if ! git -C "\$ROOT" cat-file -e .*; then$@  if false; then@' "without the presence check a missing head reads as a missing note"
  _j323 GB-T11 _f_gb11 - "go-bound: a malformed note (its first line is no record header) binds nothing"
  _j323 GB-T11m _f_gb11 '/NR == 1/ s/bad = 1/bad = 0/; /if (hdr(/ s/bad = 1/bad = 0/' "without the first-line rule the stray-first note binds"
  _j323 GB-T12 _f_gb12 - "go-bound: with no GO ledger a team default is na and a solo default is missing"
  _j323 GB-T12m _f_gb12 's@_gb_say missing "no GO note on@_gb_say error "no GO note on@' "a missing ledger turned into an error reds the solo case as error"
  _j323 GB-T8 _f_gb8 - "go-bound: a Governance team line on the base overrides a solo dial"
  _j323 GB-T8m _f_gb8 's@^  if \[ "\$_mrgov" = team .; then$@  if false; then@' "letting the dial win over Governance team reads solo"
  _j323 GB-T9 _f_gb9 - "go-bound: writes no ref and no note"
  _j323 GB-T9m _f_gb9 's@echo "go-bound: ok"@git notes --ref=promotions add -f -m x "$_gb_sha" >/dev/null 2>\&1; echo "go-bound: ok"@' "a notes add inside go-bound moves the ledger"
  _j323 GB-948COEX _f_coex - "948-COEX: a legacy promotion record beside a new merge record on one PR reads missing in go-bound (fail closed)"
  _j323 GB-948T _f_gbt - "948-T: a planted planned-release note is kept by go-bound's pick (pv_go_gate_typed's letter boundary) and refused by the solo bar"
  _j323 GB-948Tm _f_gbt 's@design|plan|design\[!a-z\]\*|plan\[!a-z\]\*) return 0 ;;@design|plan|design*|plan*) return 0 ;;@' "a typed-gate test with no letter boundary treats planned-release as a plan gate, so the pick drops it before the solo bar"
  _j323 GB-T9b _f_gb9b - "go-bound: stdout is exactly one line, and a bad flag is an error, rc 2"
  _j323 GB-T9bm _f_gb9b 's@echo "go-bound: ok"@echo "go-bound: ok"; echo "go-bound: ok"@' "a second output line breaks the one-line grammar"
  # SWAS-901 E6 S-1: once the default branch's REQUIRED-CHECKS.md declares solo-go-bound, a default branch that no longer READS solo (a team dial, a
  # deleted or symlinked dial, a symlinked CLAUDE.md: the verbs' own reader) makes go-bound an `error`, never a green `na`, because protection would
  # otherwise hold a required check that passes for everyone. A team adopter that never declared it still reads `na`.
  _g901_s1() {  # <name> <dial: solo|team|link|none> <CLAUDE.md: none|link> <declared 1|0> -> G_R, G_B (the default tip; no PR head is needed: the relationship is read first)
    G_R="$LROOT/g901-$1"; rm -rf "$G_R"; mkdir -p "$G_R/.kit"
    ( set -e; cd "$G_R"; git init -q; git config user.email t@example.com; git config user.name t; git config commit.gpgsign false
      printf 'a\n' > f.txt
      if [ "$2" = solo ]; then printf 'MERGE_RELATIONSHIP=solo\n' > .kit/dials.conf
      elif [ "$2" = team ]; then printf 'MERGE_RELATIONSHIP=team\n' > .kit/dials.conf
      elif [ "$2" = link ]; then ln -s elsewhere .kit/dials.conf; fi
      if [ "$3" = link ]; then ln -s elsewhere CLAUDE.md; fi
      if [ "$4" = 1 ]; then printf '```\nci\nsolo-go-bound\n```\n' > REQUIRED-CHECKS.md
      elif [ "$4" = second ]; then printf '```\nci\n```\n\n```\nsolo-go-bound\n```\n' > REQUIRED-CHECKS.md
      elif [ "$4" = link ]; then ln -s elsewhere REQUIRED-CHECKS.md; fi
      git add -A; git commit -qm base; git update-ref refs/kit/solo-go-default HEAD ) >/dev/null 2>&1
    G_B="$(git -C "$G_R" rev-parse HEAD)"
  }
  _f_s1a() { _g901_s1 "$1" team none 0; _g901_gb "$G_R" "$G_B" 7; _g901_ran; [ "$LOUT" = "go-bound: na" ] && [ "$LRC" = 0 ]; }
  _f_s1b() { _g901_s1 "$1" link none 1; _g901_gb "$G_R" "$G_B" 7; _g901_ran; _g901_is error && [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -qF 'declares solo-go-bound'; }
  _f_s1c() { _g901_s1 "$1" none none 1; _g901_gb "$G_R" "$G_B" 7; _g901_ran; _g901_is error && [ "$LRC" = 2 ]; }
  _f_s1d() { _g901_s1 "$1" solo link 1; _g901_gb "$G_R" "$G_B" 7; _g901_ran; _g901_is error && [ "$LRC" = 2 ]; }
  _f_s1e() { _g901_s1 "$1" team none link; _g901_gb "$G_R" "$G_B" 7; _g901_ran; _g901_is error && [ "$LRC" = 2 ]; }   # R2-3: an unreadable declaration (a symlink) reads error, never "not declared"
  _f_s1f() { _g901_s1 "$1" team none second; _g901_gb "$G_R" "$G_B" 7; _g901_ran; [ "$LOUT" = "go-bound: na" ] && [ "$LRC" = 0 ]; }   # only the FIRST fenced block is the declaration
  _S1M='s@^  if \[ "\$_gb_dr" != 1 \]; then@  if false; then@'
  _j323 GB-E6a _f_s1a - "go-bound: a team default branch that never declared solo-go-bound still reads na"
  _j323 GB-E6b _f_s1b - "go-bound: solo-go-bound declared and the dial a symlink is an error, never na"
  _j323 GB-E6bm _f_s1b "$_S1M" "without the arm a declared check beside a symlinked dial reads a green na"
  _j323 GB-E6c _f_s1c - "go-bound: solo-go-bound declared and the dial deleted is an error"
  _j323 GB-E6cm _f_s1c "$_S1M" "without the arm a declared check beside a deleted dial reads a green na"
  _j323 GB-E6e _f_s1e - "go-bound: a REQUIRED-CHECKS.md that is a symlink reads error, never not-declared"
  _j323 GB-E6em _f_s1e 's@\[ "\$_gb_dr" != 1 \]@[ "$_gb_dr" = 0 ]@' "treating only rc 0 as a declaration reads an unreadable one as a green na"
  _j323 GB-E6f _f_s1f - "go-bound: solo-go-bound listed only in a SECOND fenced block is not the declaration: na"
  _j323 GB-E6fm _f_s1f 's@if (done) next; @@' "reading every fenced block lets a usage example declare the check"
  _j323 GB-E6d _f_s1d - "go-bound: solo-go-bound declared, a solo dial and a symlinked CLAUDE.md (the verbs read team) is an error"
  _j323 GB-E6dm _f_s1d "$_S1M" "without the arm a declared check beside a symlinked CLAUDE.md reads a green na"
  J323_COPY=1; LGH_NOREV=1
  _j323 GB-T9c _f_gb9c - "a solo land still prints its merge relationship line after the factoring"
  _j323 GB-T9cm _f_gb9c 's/merge relationship: solo (origin/merge relationship: SOLO (origin/' "editing one string in the factored reader changes land's line"
  J323_COPY=0; LGH_NOREV=""

  # =====================================================================================
  # SWAS-901 slice B (B1): in a solo-declared repository the merge verbs (`land` here, `actuate` in promotion-actuate-wired.sh) read the
  # head's `solo-go-bound` runs, refuse a foreign one, re-run a red one and wait for it. `gh` is a PATH stub that serves fixture JSON through
  # the verb's own --jq filter (real jq), logs every call, and sends everything else to lgh's shim. It never reaches a forge. Each cell
  # has one mutant on a layout-carrying COPY of the gate (_j323, J323_COPY=1; the copy must differ from the gate, cmp proves it).
  # =====================================================================================
  _SGW=.github/workflows/solo-go.yml
  _sg_cr() { printf '{"id":%s,"app":{"slug":"%s"},"check_suite":{"id":%s},"status":"%s","conclusion":%s}' "$1" "$2" "$3" "$4" "$5"; }   # <id> <slug> <suite> <status> <conclusion JSON>
  _sg_wr() {   # <id> <path> <event> <suite> <attempt> <status> <conclusion JSON> <base ref|none>
    if [ "$8" = none ]; then _sgw_pr='[]'; else _sgw_pr="[{\"number\":77,\"base\":{\"ref\":\"$8\"}}]"; fi
    printf '{"id":%s,"path":"%s","event":"%s","check_suite_id":%s,"run_attempt":%s,"status":"%s","conclusion":%s,"pull_requests":%s}' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$_sgw_pr"
  }
  _sg_list() {   # <key> <item>... -> {"<key>":[item,item,...]}
    _sgl_k="$1"; shift; _sgl_o=""
    for _sgl_i in "$@"; do _sgl_o="${_sgl_o:+$_sgl_o,}$_sgl_i"; done
    printf '{"%s":[%s]}\n' "$_sgl_k" "$_sgl_o"
  }
  _sg_gok() { _sg_wr "$1" "$_SGW" pull_request_target "$2" "${3:-1}" completed '"success"' "${4:-main}"; }   # <id> <suite> [<attempt>] [<base>]: a qualifying, green run
  _sg_stub() {   # <name> -> SG_D, the gh stub dir; the caller writes cr.json, wr.json and optionally cr-after.json (served once a re-run was posted)
    SG_D="$LROOT/sg-$1"; rm -rf "$SG_D"; mkdir -p "$SG_D"
    printf '%s\n' '#!/bin/sh' \
      'd=$(dirname "$0"); a="$*"; jqf=.; prev=' \
      'for x in "$@"; do if [ "$prev" = --jq ]; then jqf=$x; fi; prev=$x; done' \
      'case "$a" in' \
      '  *rerun-failed-jobs*) printf "POST %s\n" "$a" >> "$d/log"; if [ -f "$d/rerun-fail" ]; then exit 1; fi; : > "$d/rerun"; exit 0 ;;' \
      '  *check-runs*) printf "CR %s\n" "$a" >> "$d/log"; src=$d/cr.json; if [ -f "$d/rerun" ] && [ -f "$d/cr-after.json" ]; then src=$d/cr-after.json; fi; jq -r "$jqf" < "$src"; exit $? ;;' \
      '  *"actions/runs?head_sha"*) printf "WR %s\n" "$a" >> "$d/log"; jq -r "$jqf" < "$d/wr.json"; exit $? ;;' \
      '  *) exec "$SG_NEXT" "$@" ;;' \
      'esac' > "$SG_D/gh"
    chmod +x "$SG_D/gh"; : > "$SG_D/log"
  }
  _sg_fx() {   # <name> <dial line> <workflow 1|0> -> an origin whose main carries the dial (and the installed workflow); LOSHA is that tip
    mkorigin "$1"
    ( set -e; cd "$LOA"; mkdir -p .kit; printf '%s\n' "$2" > .kit/dials.conf; git add .kit/dials.conf
      if [ "$3" = 1 ]; then mkdir -p .github/workflows; printf '# COPY & ADAPT\nname: solo-go\n' > "$_SGW"; git add "$_SGW"; fi
      git commit -qm "declare"; git push -q origin HEAD:refs/heads/main ) >/dev/null 2>&1
    LOSHA="$(git -C "$LOA" rev-parse HEAD)"; rm -f "$LAND_MARK"
    _sg_stub "$1"
  }
  _sg_land() {   # <stub dir> -> _ld_out, _ldc: one `land` with the stub ahead of lgh's forge shim
    _sgl_d="$1"; _sgl_gh="$(lgh "$LOSHA" "solo maintainer")"
    if _ld_out="$( cd "$LOA" && SG_NEXT="$_sgl_gh/gh" PROMOTION_VERIFY_SG_POLL="${SG_POLL:-2}" PATH="$_sgl_d:$_sgl_gh:$PATH" PROMOTION_NOTES_REF="$LR2" $VSH "$VERIFY" land \
          --ref 77 --merge-cmd "$LAND_STUB" --approved-sha "$LOSHA" --approved-by "solo maintainer" --go-by "the owner" \
          --gate release-candidate --rung rc --class control-plane --scope "PR #77" --token "GO: land at $LOSHA" 2>&1 )"; then _ldc=0; else _ldc=$?; fi
    case "$_ld_out" in *'merge relationship: '*) _op323=0 ;; esac
  }
  _sg_merged() { [ "$_ldc" = 0 ] && [ -f "$LAND_MARK" ]; }
  _sg_refused() { [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -qF -e "$1"; }   # <needle>: refused, nothing merged, and it says why
  _sg_posts() { grep -c '^POST ' "$SG_D/log" || true; }
  _f_t16a() {   # red on the head, a late GO: the verb re-runs, re-reads, sees green and merges
    _sg_fx "$1" MERGE_RELATIONSHIP=solo 1
    _sg_list check_runs "$(_sg_cr 1 github-actions 101 completed '"failure"')" > "$SG_D/cr.json"
    _sg_list check_runs "$(_sg_cr 1 github-actions 101 completed '"success"')" > "$SG_D/cr-after.json"
    _sg_list workflow_runs "$(_sg_wr 11 "$_SGW" pull_request_target 101 1 completed '"failure"' main)" > "$SG_D/wr.json"
    _sg_land "$SG_D"
    _sg_merged && [ "$(_sg_posts)" = 1 ] && [ "$(sed -n '$p' "$SG_D/log" | cut -c1-5)" != 'POST ' ]
  }
  _f_t16b() {   # red forever: one re-run, then refused at the bound, naming the run; nothing merged
    _sg_fx "$1" MERGE_RELATIONSHIP=solo 1
    _sg_list check_runs "$(_sg_cr 1 github-actions 101 completed '"failure"')" > "$SG_D/cr.json"
    _sg_list workflow_runs "$(_sg_wr 11 "$_SGW" pull_request_target 101 1 completed '"failure"' main)" > "$SG_D/wr.json"
    SG_POLL=1; _sg_land "$SG_D"; SG_POLL=2
    _sg_refused 'run 11' && [ "$(_sg_posts)" = 1 ] && printf '%s' "$_ld_out" | grep -qF 'Nothing was merged'
  }
  _f_t17a() {   # three qualifying runs (opened, ready_for_review, a second attempt), all green: merges
    _sg_fx "$1" MERGE_RELATIONSHIP=solo 1
    _sg_list check_runs "$(_sg_cr 1 github-actions 101 completed '"success"')" "$(_sg_cr 2 github-actions 102 completed '"success"')" "$(_sg_cr 3 github-actions 103 completed '"success"')" > "$SG_D/cr.json"
    _sg_list workflow_runs "$(_sg_gok 11 101)" "$(_sg_gok 12 102)" "$(_sg_gok 13 103 2)" > "$SG_D/wr.json"
    _sg_land "$SG_D"
    _sg_merged && [ "$(_sg_posts)" = 0 ]
  }
  _f_t17b() {   # plus a green job of the same name from another workflow on `pull_request`: refused naming it, no re-run
    _sg_fx "$1" MERGE_RELATIONSHIP=solo 1
    _sg_list check_runs "$(_sg_cr 1 github-actions 101 completed '"success"')" "$(_sg_cr 2 github-actions 104 completed '"success"')" > "$SG_D/cr.json"
    _sg_list workflow_runs "$(_sg_gok 11 101)" "$(_sg_wr 14 .github/workflows/x.yml pull_request 104 1 completed '"success"' main)" > "$SG_D/wr.json"
    _sg_land "$SG_D"
    _sg_refused 'x.yml' && [ "$(_sg_posts)" = 0 ]
  }
  _f_t17c() {   # one check suite that joins two workflow runs is ambiguous: refused
    _sg_fx "$1" MERGE_RELATIONSHIP=solo 1
    _sg_list check_runs "$(_sg_cr 1 github-actions 101 completed '"success"')" > "$SG_D/cr.json"
    _sg_list workflow_runs "$(_sg_gok 11 101)" "$(_sg_gok 12 101)" > "$SG_D/wr.json"
    _sg_land "$SG_D"
    _sg_refused 'check suite 101'
  }
  _f_t17d() {   # a green run whose PR base is not the default branch (S-1 residual): refused naming the base
    _sg_fx "$1" MERGE_RELATIONSHIP=solo 1
    _sg_list check_runs "$(_sg_cr 1 github-actions 101 completed '"success"')" > "$SG_D/cr.json"
    _sg_list workflow_runs "$(_sg_gok 11 101 1 feature)" > "$SG_D/wr.json"
    _sg_land "$SG_D"
    _sg_refused 'base feature'
  }
  _f_t17e() {   # a check run from another app: refused
    _sg_fx "$1" MERGE_RELATIONSHIP=solo 1
    _sg_list check_runs "$(_sg_cr 1 my-bot 101 completed '"success"')" > "$SG_D/cr.json"
    _sg_list workflow_runs "$(_sg_gok 11 101)" > "$SG_D/wr.json"
    _sg_land "$SG_D"
    _sg_refused 'my-bot'
  }
  _f_t17f() {   # an older green and a newer red on one head, the re-run stays red: refused, only the red run re-run
    _sg_fx "$1" MERGE_RELATIONSHIP=solo 1
    _sg_list check_runs "$(_sg_cr 1 github-actions 101 completed '"success"')" "$(_sg_cr 2 github-actions 102 completed '"failure"')" > "$SG_D/cr.json"
    _sg_list workflow_runs "$(_sg_gok 11 101)" "$(_sg_wr 12 "$_SGW" pull_request_target 102 1 completed '"failure"' main)" > "$SG_D/wr.json"
    SG_POLL=1; _sg_land "$SG_D"; SG_POLL=2
    _sg_refused 'run 12' && [ "$(_sg_posts)" = 1 ] && grep -q '^POST .*runs/12/' "$SG_D/log"
  }
  _f_t18() {   # a TEAM base, the same red stubs: the verb never asks about solo-go-bound
    _sg_fx "$1" MERGE_RELATIONSHIP=team 1
    _sg_list check_runs "$(_sg_cr 1 github-actions 101 completed '"failure"')" > "$SG_D/cr.json"
    _sg_list workflow_runs "$(_sg_wr 11 "$_SGW" pull_request_target 101 1 completed '"failure"' main)" > "$SG_D/wr.json"
    LGH_NOREV=""; SG_POLL=1; _sg_land "$SG_D"; SG_POLL=2; LGH_NOREV=1
    _sg_merged && [ ! -s "$SG_D/log" ]
  }
  _f_t18b() {   # solo but no installed workflow on the tip: one N/A line, nothing read, today's path
    _sg_fx "$1" MERGE_RELATIONSHIP=solo 0
    _sg_list check_runs "$(_sg_cr 1 github-actions 101 completed '"failure"')" > "$SG_D/cr.json"
    _sg_list workflow_runs "$(_sg_wr 11 "$_SGW" pull_request_target 101 1 completed '"failure"' main)" > "$SG_D/wr.json"
    SG_POLL=1; _sg_land "$SG_D"; SG_POLL=2
    _sg_merged && [ ! -s "$SG_D/log" ] && printf '%s' "$_ld_out" | grep -qF 'solo-go-bound: not installed'
  }
  J323_COPY=1; LGH_NOREV=1
  _j323 T16a _f_t16a - "solo, a red solo-go-bound on the head: the verb re-runs it, re-reads, and merges once it is green"
  _j323 T16am _f_t16a 's@^    sleep "\$_sgstep"; _sgt=.*$@    return 0@' "returning after the re-run without reading again merges before the forge answered"
  _j323 T16b _f_t16b - "solo, red forever: one re-run, then refused at the bound naming the run, nothing merged"
  _j323 T16bm _f_t16b 's@^    if \[ "\$_sgt" -ge "\$_sgb" \]; then@    if [ "$_sgt" -ge "$_sgb" ]; then return 0@' "treating the bound as success merges on a red check"
  _j323 T16bs _f_t16b 's@^  pv_sg_gate land .*$@  :@' "land without the call site never reads solo-go-bound"
  _f_t16g() {   # no solo-go-bound run on the head at all (the verdict `none`): the refusal says so, in its own words
    _sg_fx "$1" MERGE_RELATIONSHIP=solo 1
    _sg_list check_runs > "$SG_D/cr.json"; _sg_list workflow_runs > "$SG_D/wr.json"
    SG_POLL=1; _sg_land "$SG_D"; SG_POLL=2
    _sg_refused 'no solo-go-bound run exists on this head' && [ "$(_sg_posts)" = 0 ]
  }
  _j323 T16g _f_t16g - "solo, no solo-go-bound run on the head: refused at the bound saying no run exists, not that the GO is missing"
  _j323 T16gm _f_t16g '/MUT-SG-NONE$/d' "without the verdict-specific wording a missing run reads like a missing GO"
  _j323 T17a _f_t17a - "three qualifying runs on one head, all green, are not refused for being several"
  _j323 T17am _f_t17a 's@^      total++$@      if (++total > 1) { print "foreign more than one run"; fin = 1; exit }@' "refusing on more than one run blocks the re-run and the ready_for_review runs"
  _j323 T17b _f_t17b - "a green same-named job from another workflow on pull_request is refused naming it, and nothing is re-run"
  _j323 T17bm _f_t17b '/^      if (pth\[\$3\] != /d' "without the path and event rule a spoofing workflow's green merges"
  _j323 T17c _f_t17c - "one check suite joining two workflow runs is refused"
  _j323 T17cm _f_t17c '/^      if (cnt\[\$3\] != 1)/d' "without the join rule an ambiguous suite is judged by whichever run came last"
  _j323 T17d _f_t17d - "a green run whose PR base is a feature branch is refused naming the base"
  _j323 T17dm _f_t17d '/^      if (bas\[\$3\] != def)/d' "without the base rule a run for another base counts"
  _j323 T17e _f_t17e - "a check run from an app other than github-actions is refused"
  _j323 T17em _f_t17e '/^      if (\$2 != "github-actions")/d' "without the app rule a bot's check counts"
  _j323 T17f _f_t17f - "an older green beside a newer red is red: only the red run is re-run, and it is refused at the bound"
  _j323 T17fm _f_t17f 's@^      if (\$4 != "completed") pend = 1$@      if ($5 == "success") ok1 = 1; if ($4 != "completed") pend = 1@;s@^      else if (red) print "red " ids$@      else if (red \&\& !ok1) print "red " ids@' "accepting any green run beside a red one merges on the older head state"
  _j323 T18 _f_t18 - "a team base: the verb never reads solo-go-bound, runs nothing, and merges as before"
  _j323 T18m _f_t18 '/^  \[ "\$PV_REL" = solo \] || return 0$/d' "without the solo gate a team repository is asked about solo-go-bound"
  _j323 T18b _f_t18b - "solo with no installed workflow on the tip: one N/A line and today's path, nothing read"
  _j323 T18bm _f_t18b 's@^  if ! pv_sg_installed; then$@  if false; then@' "without the installed test a solo repository without the workflow is refused for want of a run"
  # SWAS-901 slice B, HO4: a solo `land` prints the handover line twice (after the relationship line, before the success text) and its success text no
  # longer says "authenticated non-author forge approval" (nothing authenticated a solo GO); HO4m1-m3 each undo one of the three on a COPY of the gate.
  _HO4='land: From here the agent merges on your recorded GO; the owner'"'"'s per-PR act is the GO only.'
  _f_ho4() {
    _sg_fx "$1" MERGE_RELATIONSHIP=solo 0
    _sg_land "$SG_D"
    _sg_merged && [ "$(printf '%s\n' "$_ld_out" | grep -cxF -e "$_HO4")" = 2 ] && printf '%s' "$_ld_out" | grep -qF 'merged on your recorded GO' \
      && ! printf '%s' "$_ld_out" | grep -qF 'authenticated non-author'
  }
  _j323 HO4 _f_ho4 - "a solo land prints the handover line twice and a success text that does not claim a forge approval"
  _j323 HO4m1 _f_ho4 's@^  pv_handover land .*MUT-HO-REL$@  :@' "without the print after the relationship line the count is one"
  _j323 HO4m2 _f_ho4 's@^  pv_handover land .*MUT-HO-OK$@  :@' "without the print before the success text the count is one"
  _j323 HO4m3 _f_ho4 's@merged on your recorded GO, bound to the head sha@merged on an authenticated non-author forge approval@' "reverting the solo success text claims a forge approval that no forge gave"
  J323_COPY=0; LGH_NOREV=""

  # =====================================================================================
  # SWAS-944: `record --gate design` checks its basis BEFORE it writes (design 2026-11-18-record-input-at-write-944 §2e rev 3, errata E2 + E3).
  # Every negative asserts rc 2, ITS OWN leg's message, no new note, and a ledger that is unmoved or fast-forwarded to origin's tip. Each cell is
  # run by _j323 against the real gate (must hold) and its mutants against a sed-edited COPY (must NOT hold). RI1-RI21 with RI8i and RI17d, E2's
  # RI22a-e, E3's RI17e-h and RI15b. E1's RI17e-g are replaced by E3's (E3 says so). Not built: none.
  # =====================================================================================
  J323_COPY=0
  _ri_head() { git -C "$1" rev-parse HEAD; }
  _ri_pre() { _rip_l="$(lrev "$1")"; _rip_o="$(rrev "$LF")"; }   # <clone>: the ledger's state before the operation under test
  _ri_ran() { if { [ "$LRC" = 0 ] || [ "$LRC" = 2 ]; } && _opok; then _op323=0; fi; }
  _ri_ran_any() { if _opok; then _op323=0; fi; }
  _ri_said() { printf '%s' "$LOUT" | grep -qF -e "$1"; }
  _ri_neg0() {   # <clone> <needle>... -> rc 2, every needle printed, origin's ledger unmoved, the clone's unmoved or fast-forwarded to origin's tip
    _rn_c="$1"; shift
    [ "$LRC" = 2 ] || return 1
    for _rn_n in "$@"; do _ri_said "$_rn_n" || return 1; done
    [ "$(rrev "$LF")" = "$_rip_o" ] || return 1
    [ "$(lrev "$_rn_c")" = "$_rip_l" ] || [ "$(lrev "$_rn_c")" = "$(rrev "$LF")" ] || return 1
    return 0
  }
  _ri_neg() { _ri_neg0 "$@" && _ri_said 'Nothing was written'; }
  _ri_nonote() { ! lnote "$1" "$2" && ! rnote "$LF" "$2"; }   # <clone> <sha>: no note on that sha, locally or on origin
  _ri_fetch_line() { printf '%s\n' "$LOUT" | grep -qxF "        git fetch origin refs/notes/$LR:refs/notes/$LR"; }
  _ri_sync_line() { printf '%s\n' "$LOUT" | grep -qxF "        sh scripts/promotion-verify.sh sync"; }
  _ri_nostar() {   # every printed remedy line carries neither a glob nor a leading plus, and at least one is printed
    _rns="$(printf '%s\n' "$LOUT" | grep -E '^        (git fetch origin |sh scripts/promotion-verify.sh sync)')"
    [ -n "$_rns" ] || return 1
    ! printf '%s\n' "$_rns" | grep -qE '[*]|[+]refs'
  }
  _rir() {   # <clone> <sha> <scope> <basis> [extra record args...] -> LRC, LOUT: a design GO (a later --gate overrides, last wins). _RI_GLOB, when set, is CB_DESIGN_GLOB
    _ric="$1"; _ris="$2"; _rix="$3"; _rib="$4"; shift 4
    if LOUT="$( cd "$_ric" && { if [ -n "${_RI_GLOB+x}" ]; then CB_DESIGN_GLOB="$_RI_GLOB"; export CB_DESIGN_GLOB; fi; } \
        && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e PROMOTION_NOTES_REF="$LR" $VSH "$VERIFY" record \
          --approved-sha "$_ris" --approved-by "solo maintainer" --gate design --rung integration \
          --class control-plane --scope "$_rix" --token "GO: $_rix" \
          --basis "$_rib" "$@" 2>&1 )"; then LRC=0; else LRC=$?; fi
  }
  _ri_links() {   # <name> -> mkledger plus _riLNK (docs/architecture/link-design.md as a symlink) and _riA3 (the same path replaced by a regular file)
    mkledger "$1"
    ( set -e; cd "$LF/A"
      ln -s x-design.md docs/architecture/link-design.md; git add docs/architecture/link-design.md; git commit -qm lnk; git rev-parse HEAD > "$LF/.lnk"
      git rm -q docs/architecture/link-design.md
      printf '# Link design\n\nNow a regular file.\nIt carries several real lines so it is more than a stub.\nThe approved commit replaces the symlink with it.\n' > docs/architecture/link-design.md
      git add docs/architecture/link-design.md; git commit -qm a3; git rev-parse HEAD > "$LF/.a3" ) >/dev/null 2>&1
    _riLNK="$(cat "$LF/.lnk")"; _riA3="$(cat "$LF/.a3")"
  }
  _ri_errata() {   # <name> -> mkledger plus _riE1, a commit adding five errata-shaped files (x-errata, x-errata-2, z-design, z-errata, q-errata)
    mkledger "$1"
    ( set -e; cd "$LF/A"
      for _rif in x-errata x-errata-2 z-design z-errata q-errata; do
        printf '# %s\n\nA fixture file for the errata cells.\nIt carries several real lines so it is more than a stub.\nThe approved commit adds it.\n' "$_rif" > "docs/architecture/$_rif.md"
      done
      git add docs/architecture; git commit -qm errata; git rev-parse HEAD > "$LF/.e1" ) >/dev/null 2>&1
    _riE1="$(cat "$LF/.e1")"
  }
  _riX=docs/architecture/x-design.md
  _riY=docs/architecture/y-design.md

  _f_ri1() {   # a bare basis the approved commit touches, a full 40-hex sha: recorded and published
    mkledger "$1"
    _rir "$LF/A" "$ASHA" branch/ri1 "$_riX"; _ri_ran
    [ "$LRC" = 0 ] && _ri_said published && rnote "$LF" "$ASHA"
  }
  _f_ri2() {   # the same with a 7-hex --approved-sha: recorded, and the note says it exactly as typed
    mkledger "$1"; _ri2s="$(printf '%s' "$ASHA" | cut -c1-7)"
    _rir "$LF/A" "$_ri2s" branch/ri2 "$_riX"; _ri_ran
    [ "$LRC" = 0 ] && rnote "$LF" "$ASHA" && git -C "$LF/A" notes --ref="$LR" show "$ASHA" | grep -qx "approved-sha: $_ri2s"
  }
  _f_ri3() {   # run B: --basis <asha>:<path> with nothing at P is refused with the "use --basis <path>" remedy
    mkledger "$1"; _ri_pre "$LF/A"
    _rir "$LF/A" "$ASHA" branch/ri3 "$ASHA:$_riX"; _ri_ran
    _ri_neg "$LF/A" "use --basis $_riX, or approve a later commit on this branch" && _ri_nonote "$LF/A" "$ASHA"
  }
  _f_ri4() {   # P = asha through a short P against a full asha, and a full P against a short asha: refused by leg 5, not by rc alone
    mkledger "$1"; _ri_pre "$LF/A"; _ri4s="$(printf '%s' "$ASHA" | cut -c1-7)"
    _rir "$LF/A" "$ASHA" branch/ri4a "$_ri4s:$_riX"; _ri_ran
    _ri_neg "$LF/A" "use --basis $_riX" || return 1
    _rir "$LF/A" "$_ri4s" branch/ri4b "$ASHA:$_riX"; _ri_ran
    _ri_neg "$LF/A" "use --basis $_riX" && _ri_nonote "$LF/A" "$ASHA"
  }
  _f_ri5() {   # a stacked child: P = asha, P carries a bare design record naming the path under another scope -> accepted (the gate accepts it)
    mkledger "$1"
    _rir "$LF/A" "$ASHA" branch/ri5p "$_riX"; [ "$LRC" = 0 ] || return 1
    _rir "$LF/A" "$ASHA" branch/ri5c "$ASHA:$_riX"; _ri_ran
    [ "$LRC" = 0 ] && [ "$(git -C "$LF/A" notes --ref="$LR" show "$ASHA" | grep -c '^record: promotion')" = 2 ]
  }
  _f_ri6() {   # the same with the parent's own scope: it would replace the very GO it quotes
    mkledger "$1"
    _rir "$LF/A" "$ASHA" branch/ri6 "$_riX"; [ "$LRC" = 0 ] || return 1
    _ri_pre "$LF/A"
    _rir "$LF/A" "$ASHA" branch/ri6 "$ASHA:$_riX"; _ri_ran
    _ri_neg "$LF/A" "would replace the design GO it quotes" && [ "$(git -C "$LF/A" notes --ref="$LR" show "$ASHA" | grep -c '^record: promotion')" = 1 ]
  }
  _f_ri7() {   # a bare basis the approved commit does not touch: refused, naming the commit that last touched it
    mkledger "$1"; la2 "$LF/A"; _ri7a="$(_ri_head "$LF/A")"; _ri_pre "$LF/A"
    _rir "$LF/A" "$_ri7a" branch/ri7 "$_riY"; _ri_ran
    _ri_neg "$LF/A" "does not touch '$_riY' (last touched by $ASHA)" && _ri_nonote "$LF/A" "$_ri7a"
  }
  _f_ri8() {   # path safety (two cases), a path absent at asha, and a symlink at asha: each refused by its own leg
    _ri_links "$1"; _ri_pre "$LF/A"
    _rir "$LF/A" "$ASHA" branch/ri8a ../x-design.md; _ri_ran
    _ri_neg "$LF/A" "absolute or contains '..'" || return 1
    _rir "$LF/A" "$ASHA" branch/ri8b /abs/x-design.md; _ri_ran
    _ri_neg "$LF/A" "absolute or contains '..'" || return 1
    _rir "$LF/A" "$ASHA" branch/ri8c docs/architecture/nope-design.md; _ri_ran
    _ri_neg "$LF/A" "is not a regular file at the approved commit" || return 1
    _rir "$LF/A" "$_riLNK" branch/ri8d docs/architecture/link-design.md; _ri_ran
    _ri_neg "$LF/A" "is not a regular file at the approved commit" && _ri_nonote "$LF/A" "$_riLNK"
  }
  _f_ri8i() {   # the inherited form: the path is a symlink at P (and a regular file at asha): refused at P by leg 3i
    _ri_links "$1"; _ri_pre "$LF/A"
    _rir "$LF/A" "$_riA3" branch/ri8i "$_riLNK:docs/architecture/link-design.md"; _ri_ran
    _ri_neg "$LF/A" "is not a regular file at $_riLNK" && _ri_nonote "$LF/A" "$_riA3"
  }
  _f_ri9() {   # README.md on a commit that touches it: only the glob refuses it
    mkledger "$1"
    ( cd "$LF/A" && printf '# readme\n' > README.md && git add README.md && git commit -qm readme ) >/dev/null 2>&1; _ri9a="$(_ri_head "$LF/A")"
    _ri_pre "$LF/A"
    _rir "$LF/A" "$_ri9a" branch/ri9 README.md; _ri_ran
    _ri_neg "$LF/A" "is not a design artifact" && _ri_nonote "$LF/A" "$_ri9a"
  }
  _f_ri10() {   # inherited, a ledger on origin but no design GO record at P
    mkledger "$1"; la2 "$LF/A"; _ri10a="$(_ri_head "$LF/A")"
    _rir "$LF/A" "$_ri10a" branch/ri10x "$_riX"; [ "$LRC" = 0 ] || return 1
    la2 "$LF/A"; _ri10b="$(_ri_head "$LF/A")"; _ri_pre "$LF/A"
    _rir "$LF/A" "$_ri10b" branch/ri10 "$ASHA:$_riX"; _ri_ran
    _ri_neg "$LF/A" "no design GO record at $ASHA" && _ri_nonote "$LF/A" "$_ri10b"
  }
  _f_ri11() {   # inherited, P's only design record is itself inherited: one hop only
    mkledger "$1"
    _rir "$LF/A" "$ASHA" branch/ri11g "$_riX"; [ "$LRC" = 0 ] || return 1
    la2 "$LF/A"; _ri11a="$(_ri_head "$LF/A")"
    _rir "$LF/A" "$_ri11a" branch/ri11c "$ASHA:$_riX"; [ "$LRC" = 0 ] || return 1
    la2 "$LF/A"; _ri11b="$(_ri_head "$LF/A")"; _ri_pre "$LF/A"
    _rir "$LF/A" "$_ri11b" branch/ri11d "$_ri11a:$_riX"; _ri_ran
    _ri_neg "$LF/A" "one hop only" && _ri_nonote "$LF/A" "$_ri11b"
  }
  _f_ri12() {   # inherited, P's design record names another path: refused, naming both paths
    mkledger "$1"
    _rir "$LF/A" "$ASHA" branch/ri12p "$_riY"; [ "$LRC" = 0 ] || return 1
    la2 "$LF/A"; _ri12a="$(_ri_head "$LF/A")"; _ri_pre "$LF/A"
    _rir "$LF/A" "$_ri12a" branch/ri12 "$ASHA:$_riX"; _ri_ran
    _ri_neg "$LF/A" "name '$_riY', not '$_riX'" && _ri_nonote "$LF/A" "$_ri12a"
  }
  _f_ri13() {   # inherited, a valid bare parent at an earlier P: accepted
    mkledger "$1"
    _rir "$LF/A" "$ASHA" branch/ri13p "$_riX"; [ "$LRC" = 0 ] || return 1
    la2 "$LF/A"; _ri13a="$(_ri_head "$LF/A")"
    _rir "$LF/A" "$_ri13a" branch/ri13 "$ASHA:$_riX"; _ri_ran
    [ "$LRC" = 0 ] && rnote "$LF" "$_ri13a"
  }
  _f_ri14() {   # inherited, a basis-less (legacy-shaped) design parent: accepted; CI judges the list and the position
    mkledger "$1"
    _rir "$LF/A" "$ASHA" branch/ri14p "$_riX"; [ "$LRC" = 0 ] || return 1
    git -C "$LF/A" notes --ref="$LR" show "$ASHA" | sed 's/^basis: .*/basis: (none recorded)/' > "$LF/ri14.note" || return 1
    git -C "$LF/A" notes --ref="$LR" add -f -F "$LF/ri14.note" "$ASHA" >/dev/null 2>&1 || return 1
    la2 "$LF/A"; _ri14a="$(_ri_head "$LF/A")"
    _rir "$LF/A" "$_ri14a" branch/ri14c "$ASHA:$_riX" --no-push; _ri_ran
    [ "$LRC" = 0 ] && lnote "$LF/A" "$_ri14a"
  }
  _f_ri15() {   # --approved-sha HEAD, a branch name and 6 hex characters, each resolving to a commit that passes legs 1-4: leg 0 alone refuses
    mkledger "$1"; la2 "$LF/A"; _ri15a="$(_ri_head "$LF/A")"; git -C "$LF/A" branch ri15br "$_ri15a"; _ri_pre "$LF/A"
    _rir "$LF/A" HEAD branch/ri15a "$_riX"; _ri_ran
    _ri_neg "$LF/A" "must be a hex object name of 7-40 characters" || return 1
    _rir "$LF/A" ri15br branch/ri15b "$_riX"; _ri_ran
    _ri_neg "$LF/A" "must be a hex object name of 7-40 characters" || return 1
    _rir "$LF/A" "$(printf '%s' "$_ri15a" | cut -c1-6)" branch/ri15c "$_riX"; _ri_ran
    _ri_neg "$LF/A" "must be a hex object name of 7-40 characters" && _ri_nonote "$LF/A" "$_ri15a"
  }
  _f_ri15b() {   # E3: --approved-sha deadbee, a branch named like hex that points at a valid design commit: the written hex is no prefix of it
    mkledger "$1"; la2 "$LF/A"; _ri15d="$(_ri_head "$LF/A")"; git -C "$LF/A" branch deadbee "$_ri15d"; _ri_pre "$LF/A"
    _rir "$LF/A" deadbee branch/ri15d "$_riX"; _ri_ran
    _ri_neg "$LF/A" "is not a hex object name of a commit" && _ri_nonote "$LF/A" "$_ri15d"
  }
  _f_ri16() {   # glob parity: (a) the same default line in record and in the gate, (b) '*' refused by both, (c) an override is honoured
    mkledger "$1"; _ri16ok=0
    _ri16g="$KITROOT/conformance/ceremony-binding.sh"; _ri16l='CB_DESIGN_GLOB="${CB_DESIGN_GLOB:-docs/architecture/*-design.md}"'
    grep -qF -e "$_ri16l" "$G901_REAL" && grep -qF -e "$_ri16l" "$_ri16g" || _ri16ok=1
    _ri_pre "$LF/A"
    _RI_GLOB='*'; _rir "$LF/A" "$ASHA" branch/ri16b "$_riX"; unset _RI_GLOB; _ri_ran
    _ri_neg "$LF/A" "CB_DESIGN_GLOB must not match every path" || _ri16ok=1
    if _ri16o="$( cd "$KITROOT" && CB_DESIGN_GLOB='*' $VSH conformance/ceremony-binding.sh 2>&1 )"; then _ri16c=0; else _ri16c=$?; fi
    [ "$_ri16c" = 2 ] && printf '%s' "$_ri16o" | grep -qF 'CB_DESIGN_GLOB must not match every path' || _ri16ok=1
    ( cd "$LF/A" && mkdir -p docs/designs && printf '# A\n\nA design under an overridden glob.\nIt carries several real lines so it is more than a stub.\nThe approved commit adds it.\n' > docs/designs/a.md \
        && git add docs/designs/a.md && git commit -qm dd ) >/dev/null 2>&1; _ri16d="$(_ri_head "$LF/A")"
    _RI_GLOB='docs/designs/*.md'; _rir "$LF/A" "$_ri16d" branch/ri16c docs/designs/a.md; _ri16r="$LRC"; _ri_ran
    [ "$_ri16r" = 0 ] || _ri16ok=1
    _ri_pre "$LF/A"
    _rir "$LF/A" "$_ri16d" branch/ri16d "$_riX"; unset _RI_GLOB; _ri_ran
    _ri_neg "$LF/A" "is not a design artifact" || _ri16ok=1
    return "$_ri16ok"
  }
  # RI17: two clones. The parent design GO is published from A; B starts behind origin (it has no ledger yet).
  _f_ri17a() {   # (a) publishing: the pre-leg fetch finds the parent -> rc 0, published, B's ledger equals origin's
    mkledger "$1"
    _rir "$LF/A" "$ASHA" branch/ri17ap "$_riX"; [ "$LRC" = 0 ] || return 1
    _rir "$LF/B" "$BSHA" branch/ri17a "$ASHA:$_riX"; _ri_ran
    [ "$LRC" = 0 ] && rnote "$LF" "$BSHA" && [ "$(lrev "$LF/B")" = "$(rrev "$LF")" ]
  }
  _f_ri17b() {   # (b) --no-push: B reads its local ledger only; "not fetched", the fetch line (B has no ledger), B's ledger unchanged
    mkledger "$1"
    _rir "$LF/A" "$ASHA" branch/ri17bp "$_riX"; [ "$LRC" = 0 ] || return 1
    _ri_pre "$LF/B"
    _rir "$LF/B" "$BSHA" branch/ri17b "$ASHA:$_riX" --no-push; _ri_ran
    _ri_neg "$LF/B" "in the local ledger, NOT FETCHED" && _ri_fetch_line && _ri_nostar && _ri_nonote "$LF/B" "$BSHA" && [ "$(lrev "$LF/B")" = none ]
  }
  _f_ri17c() {   # (c) origin unreachable: the existing "cannot reach" refusal, not a basis message; B's ledger unchanged
    mkledger "$1"
    _rir "$LF/A" "$ASHA" branch/ri17cp "$_riX"; [ "$LRC" = 0 ] || return 1
    git -C "$LF/B" remote set-url origin "$LF/nowhere.git"
    _ri_pre "$LF/B"
    _rir "$LF/B" "$BSHA" branch/ri17c "$ASHA:$_riX"; _ri_ran
    _ri_neg0 "$LF/B" "cannot reach the ledger remote" && ! _ri_said "no design GO record" && [ "$(lrev "$LF/B")" = none ]
  }
  _f_ri17d() {   # as (a), but the child names a path no record at P names: leg 6 refuses; B's ledger equals origin's tip (the allowed fast-forward)
    mkledger "$1"
    _rir "$LF/A" "$ASHA" branch/ri17dp "$_riX"; [ "$LRC" = 0 ] || return 1
    _ri_pre "$LF/B"
    _rir "$LF/B" "$BSHA" branch/ri17d "$ASHA:$_riY"; _ri_ran
    _ri_neg "$LF/B" "name '$_riX', not '$_riY'" && [ "$(lrev "$LF/B")" = "$(rrev "$LF")" ] && [ "$(lrev "$LF/B")" != "$_rip_l" ] && _ri_nonote "$LF/B" "$BSHA"
  }
  _f_ri17e() {   # E3: B's ledger equals origin's -> the single-ref fetch line, byte for byte, with no glob and no +refs
    mkledger "$1"; la2 "$LF/A"; _ri17ea="$(_ri_head "$LF/A")"
    _rir "$LF/A" "$_ri17ea" branch/ri17ep "$_riX"; [ "$LRC" = 0 ] || return 1
    lfetch "$LF/B"; _ri_pre "$LF/B"
    _rir "$LF/B" "$BSHA" branch/ri17e "$ASHA:$_riX" --no-push; _ri_ran
    _ri_neg "$LF/B" "in the local ledger, NOT FETCHED" && _ri_fetch_line && _ri_nostar && ! _ri_sync_line
  }
  _f_ri17f() {   # E3: B's ledger is ahead of origin's (a --no-push record first; origin's tip is local) -> sync, and the fetch line is absent
    mkledger "$1"; la2 "$LF/A"; _ri17fa="$(_ri_head "$LF/A")"
    _rir "$LF/A" "$_ri17fa" branch/ri17fp "$_riX"; [ "$LRC" = 0 ] || return 1
    lfetch "$LF/B"
    _rir "$LF/B" "$BSHA" branch/ri17fx "$_riX" --no-push; [ "$LRC" = 0 ] || return 1
    _ri_pre "$LF/B"
    _rir "$LF/B" "$BSHA" branch/ri17f "$ASHA:$_riX" --no-push; _ri_ran
    _ri_neg "$LF/B" "in the local ledger, NOT FETCHED" && _ri_sync_line && _ri_nostar && ! _ri_said "git fetch origin refs/notes/"
  }
  _f_ri17g() {   # E3: origin moved on after B's fetch, so its tip is not local (behind) -> sync, and the fetch line is absent
    mkledger "$1"; la2 "$LF/A"; _ri17ga="$(_ri_head "$LF/A")"
    _rir "$LF/A" "$_ri17ga" branch/ri17gp "$_riX"; [ "$LRC" = 0 ] || return 1
    lfetch "$LF/B"
    la2 "$LF/A"; _ri17gb="$(_ri_head "$LF/A")"
    _rir "$LF/A" "$_ri17gb" branch/ri17gq "$_riX"; [ "$LRC" = 0 ] || return 1
    _ri_pre "$LF/B"
    _rir "$LF/B" "$BSHA" branch/ri17g "$ASHA:$_riX" --no-push; _ri_ran
    _ri_neg "$LF/B" "in the local ledger, NOT FETCHED" && _ri_sync_line && _ri_nostar && ! _ri_said "git fetch origin refs/notes/"
  }
  _f_ri17h() {   # E3: origin has no ledger -> "record the parent design GO first" and no fetch line (--no-push); without --no-push the leg 5/6 refusal says so
    mkledger "$1"; _ri_pre "$LF/B"
    _rir "$LF/B" "$BSHA" branch/ri17h "$ASHA:$_riX" --no-push; _ri_ran
    _ri_neg "$LF/B" "origin has no ledger yet: record the parent design GO first." || return 1
    ! _ri_said "git fetch origin refs/notes/" || return 1
    _rir "$LF/B" "$BSHA" branch/ri17i "$ASHA:$_riX"; _ri_ran
    _ri_neg "$LF/B" "origin has no ledger yet, so no parent design GO at $ASHA is published" && _ri_nonote "$LF/B" "$BSHA"
  }
  _f_ri18() {   # land --gate design with a basis the approved commit does not touch: leg 4 refuses, no merge, no note (local or on origin)
    mkorigin "$1"; rm -f "$LAND_MARK"
    ( set -e; cd "$LOA"; mkdir -p docs/architecture
      printf '# X design\n\nThe x fixture design.\nIt carries several real lines so it is more than a stub.\nThe head below does not touch it.\n' > docs/architecture/x-design.md
      git add docs/architecture/x-design.md; git commit -qm design
      printf 'f2\n' >> f.txt; git add f.txt; git commit -qm head
      git push -q origin HEAD:refs/heads/main ) >/dev/null 2>&1
    _ri18="$(git -C "$LOA" rev-parse HEAD)"; _ri18g="$(lgh "$_ri18" "solo maintainer")"
    if _ri18o="$( cd "$LOA" && PATH="$_ri18g:$PATH" PROMOTION_NOTES_REF="$LR2" $VSH "$VERIFY" land \
          --ref 77 --merge-cmd "$LAND_STUB" --approved-sha "$_ri18" --approved-by "solo maintainer" \
          --go-by "the owner" --gate design --rung integration --class control-plane \
          --scope "PR #77" --token "GO: land design at $_ri18" --basis "$_riX" 2>&1 )"; then _ri18c=0; else _ri18c=$?; fi
    case "$_ri18o" in *'syntax error'*|*'not found'*) ;; *) if [ "$_ri18c" = 0 ] || [ "$_ri18c" = 2 ]; then _op323=0; fi ;; esac
    [ "$_ri18c" = 2 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ri18o" | grep -qF "does not touch '$_riX'" \
      && ! onote "$_ri18" && ! git -C "$LOA" notes --ref="$LR2" show "$_ri18" >/dev/null 2>&1
  }
  _f_ri19() {   # other gates are unchanged (rc 0 on three inputs the design gate refuses), and the same inputs under --gate design are refused by legs 2, 5 and 0
    mkledger "$1"; _ri19ok=0
    ( cd "$LF/A" && printf '# readme\n' > README.md && git add README.md && git commit -qm readme ) >/dev/null 2>&1
    la2 "$LF/A"; _ri19a="$(_ri_head "$LF/A")"
    _rir "$LF/A" "$_ri19a" "PR #51" README.md --gate release-candidate --rung rc; _ri_ran
    [ "$LRC" = 0 ] || _ri19ok=1
    _rir "$LF/A" "$_ri19a" "PR #52" "$_ri19a:$_riX" --gate release-candidate --rung rc; _ri_ran
    [ "$LRC" = 0 ] || _ri19ok=1
    _rir "$LF/A" HEAD "PR #53" "$_riX" --gate release-candidate --rung rc; _ri_ran
    [ "$LRC" = 0 ] || _ri19ok=1
    _ri_pre "$LF/A"
    _rir "$LF/A" "$_ri19a" branch/ri19a README.md; _ri_ran
    _ri_neg "$LF/A" "is not a design artifact" || _ri19ok=1
    _rir "$LF/A" "$_ri19a" branch/ri19b "$_ri19a:$_riX"; _ri_ran
    _ri_neg "$LF/A" "use --basis $_riX" || _ri19ok=1
    _rir "$LF/A" HEAD branch/ri19c "$_riX"; _ri_ran
    _ri_neg "$LF/A" "must be a hex object name of 7-40 characters" || _ri19ok=1
    return "$_ri19ok"
  }
  _f_ri20() {   # a symref'd ledger and an inherited basis, without --no-push: refused as symbolic BEFORE the fetch, so the decoy ref never moves
    mkledger "$1"
    _rir "$LF/A" "$ASHA" branch/ri20p "$_riX"; [ "$LRC" = 0 ] || return 1
    git -C "$LF/B" symbolic-ref "refs/notes/$LR" refs/notes/decoy
    _ri_pre "$LF/B"
    _rir "$LF/B" "$BSHA" branch/ri20 "$ASHA:$_riX"; _ri_ran_any
    _ri_neg0 "$LF/B" "is symbolic" && [ -z "$(git -C "$LF/B" rev-parse -q --verify refs/notes/decoy 2>/dev/null)" ] && _ri_nonote "$LF/B" "$BSHA"
  }
  _f_ri21() {   # a branch named like hex (deadbee, no object starts with it) holds a valid bare parent GO: the written hex is no prefix of what it resolves to
    mkledger "$1"
    _rir "$LF/A" "$ASHA" branch/ri21p "$_riX"; [ "$LRC" = 0 ] || return 1
    git -C "$LF/A" branch deadbee "$ASHA"; la2 "$LF/A"; _ri21a="$(_ri_head "$LF/A")"; _ri_pre "$LF/A"
    _rir "$LF/A" "$_ri21a" branch/ri21 "deadbee:$_riX"; _ri_ran
    _ri_neg "$LF/A" "is not a prefix of the commit it resolves to" && _ri_nonote "$LF/A" "$_ri21a"
  }
  # E2: an errata GO is accepted beside its design GO (same scope and kit-row), refused alone, and refused on another design's GO.
  _f_ri22a() {   # a design GO with a *-design.md basis, then the errata GO for the same scope with that design's -errata.md
    _ri_errata "$1"
    _rir "$LF/A" "$ASHA" branch/ri22a "$_riX"; [ "$LRC" = 0 ] || return 1
    _rir "$LF/A" "$_riE1" branch/ri22a docs/architecture/x-errata.md; _ri_ran
    [ "$LRC" = 0 ] && _ri_said published && rnote "$LF" "$_riE1"
  }
  _f_ri22b() {   # the same errata GO with no prior design GO for the scope
    _ri_errata "$1"; _ri_pre "$LF/A"
    _rir "$LF/A" "$_riE1" branch/ri22b docs/architecture/x-errata.md; _ri_ran
    _ri_neg "$LF/A" "an errata GO needs its design GO first (scope branch/ri22b)" && _ri_nonote "$LF/A" "$_riE1"
  }
  _f_ri22c() {   # a prior design GO for the scope, but the errata file's own design is not a tracked file: refused by condition 1
    _ri_errata "$1"
    _rir "$LF/A" "$ASHA" branch/ri22c "$_riX"; [ "$LRC" = 0 ] || return 1
    _ri_pre "$LF/A"
    _rir "$LF/A" "$_riE1" branch/ri22c docs/architecture/q-errata.md; _ri_ran
    _ri_neg "$LF/A" "its design 'docs/architecture/q-design.md' is not a tracked file" && _ri_nonote "$LF/A" "$_riE1"
  }
  _f_ri22c2() {   # a prior design GO for the scope that names ANOTHER design: the errata of z-design cannot ride on x-design's GO (condition 2)
    _ri_errata "$1"
    _rir "$LF/A" "$ASHA" branch/ri22k "$_riX"; [ "$LRC" = 0 ] || return 1
    _ri_pre "$LF/A"
    _rir "$LF/A" "$_riE1" branch/ri22k docs/architecture/z-errata.md; _ri_ran
    _ri_neg "$LF/A" "an errata GO needs its design GO first (scope branch/ri22k)" "naming 'docs/architecture/z-design.md'" && _ri_nonote "$LF/A" "$_riE1"
  }
  _f_ri22d() {   # an -errata-2.md basis beside its design GO: the numbered form is accepted
    _ri_errata "$1"
    _rir "$LF/A" "$ASHA" branch/ri22d "$_riX"; [ "$LRC" = 0 ] || return 1
    _rir "$LF/A" "$_riE1" branch/ri22d docs/architecture/x-errata-2.md; _ri_ran
    [ "$LRC" = 0 ] && _ri_said published && rnote "$LF" "$_riE1"
  }
  _f_ri22e() {   # an inherited <P>:<errata path> basis is never accepted
    _ri_errata "$1"; _ri_pre "$LF/A"
    _rir "$LF/A" "$_riE1" branch/ri22e "$ASHA:docs/architecture/x-errata.md"; _ri_ran
    _ri_neg "$LF/A" "an errata GO names its errata file as a bare path" && _ri_nonote "$LF/A" "$_riE1"
  }
  _f_ri23() {   # S1: the same valid design GO as RI1, run from a subdirectory with a repo-root-relative basis: recorded and published
    mkledger "$1"
    _rir "$LF/A/docs" "$ASHA" branch/ri23 "$_riX"; _ri_ran
    [ "$LRC" = 0 ] && _ri_said published && rnote "$LF" "$ASHA"
  }
  _j323 RI23 _f_ri23 - "a valid design GO run from a subdirectory of the repository is recorded and published"
  _j323 RI23m _f_ri23 's/git -C "\$ROOT" rev-list -1/git rev-list -1/' "dropping -C ROOT from leg 4 reads the basis relative to the subdirectory and refuses"
  _j323 RI1 _f_ri1 - "a design GO whose bare basis the approved commit touches (full sha) is recorded and published"
  _j323 RI2 _f_ri2 - "the same with a 7-hex --approved-sha is recorded, and the note says approved-sha exactly as typed"
  _j323 RI2m _f_ri2 's/^    if \[ "\$_dl_last" != "\$_dl_a40" \]; then$/    if [ "$_dl_last" != "$asha" ]; then/' "comparing leg 4 against the typed sha refuses a short sha"
  _j323 RI3 _f_ri3 - "run B: --basis <asha>:<path> with nothing at P is refused with the 'use --basis <path>' remedy, nothing written"
  _j323 RI3m _f_ri3 's/^  if \[ "\$_dl_p40" = "\$_dl_a40" \]; then$/  if false; then/' "dropping the P = approved commit refusal changes leg 5's message"
  _j323 RI4 _f_ri4 - "a short P against a full asha, and a full P against a short asha, are both refused by leg 5"
  _j323 RI4m _f_ri4 's/^  if \[ "\$_dl_p40" = "\$_dl_a40" \]; then$/  if [ "$_dl_ip" = "$asha" ]; then/' "comparing P and asha as typed lets a short P through leg 5"
  _j323 RI5 _f_ri5 - "a stacked child (P = asha, a parent GO under another scope) is accepted, as the gate accepts it"
  _j323 RI6 _f_ri6 - "the same under the parent's own scope is refused: it would replace the design GO it quotes"
  _j323 RI6m _f_ri6 's/^    if \[ "\$_ds_same" -gt 0 \]; then$/    if false; then/' "dropping the same-scope arm changes the message to the run-B remedy"
  _j323 RI7 _f_ri7 - "a bare basis the approved commit does not touch is refused, naming the commit that last touched it"
  _j323 RI7m _f_ri7 's/^    if \[ "\$_dl_last" != "\$_dl_a40" \]; then$/    if false; then/' "dropping leg 4 records an untouched design"
  _j323 RI8 _f_ri8 - "../ and /abs bases (path safety), a path absent at asha and a symlink at asha are each refused by their own leg"
  _j323 RI8m1 _f_ri8 's#^    /\*|\*\.\.\*)$#    zz-never)#' "dropping path safety lets ../ reach the glob leg instead"
  _j323 RI8m2 _f_ri8 's/^  if \[ "\$_dl_inh" = 0 \] && ! _pv_dl_blob "\$_dl_a40" "\$_dl_path"; then$/  if false; then/' "dropping the regular-file check lets an absent path and a symlink reach leg 4 or pass"
  _j323 RI8i _f_ri8i - "inherited: a symlink at P (a regular file at asha) is refused at P by leg 3i"
  _j323 RI8im _f_ri8i 's/^  if ! _pv_dl_blob "\$_dl_p40" "\$_dl_path"; then$/  if ! _pv_dl_blob "$_dl_a40" "$_dl_path"; then/' "running leg 3 at asha for the inherited form misses the symlink at P"
  _j323 RI9 _f_ri9 - "README.md on a commit that touches it is refused by the glob alone"
  _j323 RI9m _f_ri9 's/^    \$CB_DESIGN_GLOB) : ;;$/    *) : ;;/' "dropping the glob leg records any tracked touched file"
  _j323 RI10 _f_ri10 - "inherited, a ledger on origin and no design GO record at P: refused"
  _j323 RI11 _f_ri11 - "inherited, P's only design record is itself inherited: refused as one hop only"
  _j323 RI11m _f_ri11 's/^  if \[ "\$_ds_hop" -gt 0 \]; then$/  if false; then/' "dropping the one-hop arm changes the message to a generic one"
  _j323 RI12 _f_ri12 - "inherited, P's design record names another path: refused naming both paths"
  _j323 RI12m _f_ri12 's/^    if \[ "\$_ds_b" = "\$2" \] || /    if true || /' "dropping leg 6's path comparison accepts any design record at P"
  _j323 RI13 _f_ri13 - "inherited, a valid bare parent at an earlier P is accepted"
  _j323 RI14 _f_ri14 - "inherited, a basis-less (legacy-shaped) design parent is accepted; CI judges the list and the position"
  _j323 RI14m _f_ri14 's/ || \[ "\$_ds_b" = "(none recorded)" \]; then$/; then/' "dropping the legacy arm refuses a parent the gate accepts"
  _j323 RI15 _f_ri15 - "--approved-sha HEAD, a branch name and 6 hex characters are each refused by leg 0 (each resolves to a commit that passes legs 1-4)"
  _j323 RI15m _f_ri15 's/^  if \[ "\$_dl_bad" = 1 \] || .*; then$/  if false; then/' "dropping leg 0 changes the message, or records the 6-hex sha"
  _j323 RI15b _f_ri15b - "E3: --approved-sha deadbee (a branch named like hex) is refused: the written hex is no prefix of the commit"
  _j323 RI15bm _f_ri15b 's/ || ! _pv_dl_hexprefix "\$asha" "\$_dl_a40"; then$/; then/' "dropping leg 0's prefix check records the branch's commit"
  _j323 RI16 _f_ri16 - "glob parity: the same default line, '*' refused by record and by the gate, an override honoured"
  _j323 RI16m _f_ri16 's/^  case "\$CB_DESIGN_GLOB" in$/  case zz in/' "dropping the match-everything refusal lets CB_DESIGN_GLOB='*' record"
  _j323 RI17a _f_ri17a - "two clones, B behind: the pre-leg fetch finds the parent, rc 0, published, B equals origin"
  _j323 RI17am _f_ri17a 's/^  if \[ "\$nopush" = 0 \]; then _pv_sync_in quiet || return 2; fi$/  :/' "dropping the pre-leg fetch refuses a child whose parent B has not fetched"
  _j323 RI17b _f_ri17b - "--no-push: 'local ledger, NOT FETCHED', the single-ref fetch line, B's ledger unchanged"
  _j323 RI17c _f_ri17c - "origin unreachable: the existing 'cannot reach' refusal, not a basis message, B's ledger unchanged"
  _j323 RI17d _f_ri17d - "leg 6 refuses after the fetch; B's ledger equals origin's tip, no note on the approved sha"
  _j323 RI17e _f_ri17e - "E3: B's ledger equals origin's -> the fetch line byte for byte, with no glob and no +refs"
  _j323 RI17f _f_ri17f - "E3: B's ledger ahead of origin's -> the sync line, no fetch line"
  _j323 RI17fm _f_ri17f 's/^  case "\$_rm_state" in$/  case fetch in/' "always printing the fetch line is refused by an ahead ledger"
  _j323 RI17g _f_ri17g - "E3: origin's tip is not local (behind) -> the sync line, no fetch line"
  _j323 RI17gm _f_ri17g 's/^  case "\$_rm_state" in$/  case fetch in/' "always printing the fetch line is refused by an origin tip not held locally"
  _j323 RI17h _f_ri17h - "E3: origin has no ledger -> 'record the parent design GO first', and no fetch line"
  _j323 RI18 _f_ri18 - "land --gate design with an untouched basis: leg 4 refuses, no merge, no note local or on origin"
  _j323 RI19 _f_ri19 - "other gates unchanged (rc 0 on inputs the design gate refuses by legs 2, 5 and 0)"
  _j323 RI20 _f_ri20 - "a symref'd ledger is refused as symbolic before the fetch; the decoy ref never moves"
  _j323 RI20m _f_ri20 's#^  if git symbolic-ref -q "refs/notes/\$NOTES_REF" >/dev/null 2>[&]1; then$#  if [ "$gate" != design ] \&\& git symbolic-ref -q "refs/notes/$NOTES_REF" >/dev/null 2>\&1; then#;s#^  if \[ "\$gate" = design \]; then _pv_design_legs || return 2; fi$#  if [ "$gate" = design ]; then _pv_design_legs || return 2; if git symbolic-ref -q "refs/notes/$NOTES_REF" >/dev/null 2>\&1; then echo "record: ledger ref refs/notes/$NOTES_REF is symbolic, moved below the fetch." >\&2; return 2; fi; fi#' "moving the symref check below the pre-leg fetch still refuses as symbolic, but the fetch has written through the symref (only the decoy assertion kills it)"
  _j323 RI21 _f_ri21 - "a branch named like hex holding a valid parent GO is refused: the written hex is no prefix of the commit"
  _j323 RI21m _f_ri21 's/^  if ! _pv_dl_hexprefix "\$_dl_ip" "\$_dl_p40"; then$/  if false; then/' "dropping leg 5's prefix check lets the branch stand in for P"
  _j323 RI22a _f_ri22a - "E2: an errata GO beside its design GO (same scope and kit-row) is recorded and published"
  _j323 RI22b _f_ri22b - "E2: the errata GO with no prior design GO is refused"
  _j323 RI22bm _f_ri22b 's/^_pv_dl_errata_go() {$/_pv_dl_errata_go() { return 0/' "dropping condition 2 records an errata GO alone"
  _j323 RI22c _f_ri22c - "E2: an errata file whose design is not a tracked file is refused by condition 1"
  _j323 RI22cm _f_ri22c 's/^      if ! _pv_dl_blob "\$_dl_a40" "\$_dl_sib"; then$/      if false; then/' "dropping the sibling-path test changes the refusal to the generic one"
  _j323 RI22c2 _f_ri22c2 - "E2: the errata of another tracked design cannot ride on this design's GO"
  _j323 RI22c2m _f_ri22c2 's/^      if \[ "\$_eg_b" = "\$1" \]; then return 0; fi$/      if true; then return 0; fi/' "dropping the basis comparison accepts any design GO of the scope"
  _j323 RI22d _f_ri22d - "E2: an -errata-2.md basis beside its design GO is recorded (the numbered form)"
  _j323 RI22e _f_ri22e - "E2: an inherited <P>:<errata path> basis is refused"

  # FXS: the skip count is load-bearing. A skip call raises it by exactly one, and the note carries the number (0 prints as "0 SKIPPED").
  _fxs0="$FX_SKIPS"; fx_skip "FXS-probe" >/dev/null; _fxs1="$FX_SKIPS"; FX_SKIPS="$_fxs0"
  if [ "$_fxs1" = "$((_fxs0 + 1))" ] && [ "$(fx_skip_note 3)" = "(3 SKIPPED: not a kit tree, counted per skip line above)" ] \
     && fx_skip_note 0 | grep -qF "0 SKIPPED"; then echo "PASS: FXS: a skip is counted once and the summary note carries the count"
  else echo "FAIL: FXS: skip count $_fxs0 -> $_fxs1, note '$(fx_skip_note 3)'"; st=1; fi
  # FXS-kit: a kit tree never skips. The judge kills the mutant (a skip forced on a kit tree) and spares an adopter tree.
  fx_skip_ok() { [ "$1" != "1 1" ] || [ "$2" = 0 ]; }
  if fx_skip_ok "1 1" 0 && ! fx_skip_ok "1 1" 2 && fx_skip_ok "0 0" 2; then echo "PASS: FXS-kit: the judge kills a skip forced on a kit tree and allows an adopter tree's"
  else echo "FAIL: FXS-kit: the judge does not separate a kit tree's skips from an adopter tree's"; st=1; fi
  if fx_skip_ok "$(fx_facts "$FX_OWN")" "$FX_SKIPS"; then echo "PASS: FXS-kit: this tree skipped $FX_SKIPS cell group(s) and reads $FX_KIND"
  else echo "FAIL: FXS-kit: a KIT tree skipped $FX_SKIPS cell group(s)"; st=1; fi

  if [ "$st" = 0 ]; then
    echo "OK: promotion-verify-wired selftest [producer shell: $VSH] $(fx_skip_note "$FX_SKIPS") (fixture left in $D)"
  else
    echo "FAIL: promotion-verify-wired selftest [producer shell: $VSH] $(fx_skip_note "$FX_SKIPS") (fixture left in $D)"
  fi
  return $st
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "") [ -f "$VERIFY" ] || { echo "FAIL: missing producer $VERIFY"; exit 1; }
      echo "OK: promotion-verify producer present ($VERIFY)"; exit 0 ;;
  *) echo "usage: promotion-verify-wired.sh [--selftest]" >&2; exit 2 ;;
esac
