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
  D="$(mktemp -d)"; R="$D/repo"
  build_fixture "$D" || true
  for _s in .BASE .APPROVED .SQUASH .EXTRA .RC .REVERT .SIDE .TRUNK; do
    [ -f "$D/$_s" ] || { echo "FAIL: could not build git fixture (missing $_s)"; return 1; }
  done
  # .BASE and .RC are consumed inside build_fixture (BASE anchors branches; RC carries the v2.0.0
  # tag); the selftest asserts via the refs below. Only bind what the assertions reference.
  APP="$(cat "$D/.APPROVED")"; SQ="$(cat "$D/.SQUASH")"
  EXTRA="$(cat "$D/.EXTRA")"; REV="$(cat "$D/.REVERT")"
  SIDE="$(cat "$D/.SIDE")"; TRUNK="$(cat "$D/.TRUNK")"

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
        --gate release-candidate --rung "Release candidate" --class Ordinary \
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
      --gate release-candidate --rung "Release candidate" --class Ordinary \
      --scope "PR #1000" --token "GO: merge #1000 at $SIDE" >/dev/null 2>&1 ) \
    || { echo "FAIL: second record (SIDE) failed"; st=1; }
  assert 1 "note round-trip NEGATIVE: latest note (SIDE) tree != squash tip -> FAIL" --ref "$SQ"

  # --- LABEL-CAN'T-LIE (the non-vacuity anchor): the emitted label is DERIVED from the commit's
  #     evidence, never from input. On an UNSIGNED commit with a free-typed approver that is NOT the
  #     committer, the label MUST be [self-asserted] — never [signed: gpg]. (A smuggled bracket claim
  #     is now rejected outright at input — see the injection negatives below — so here we feed a
  #     CLEAN id and assert the derivation itself cannot overclaim.) ---
  ( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$APP" --approved-by "attacker" \
      --gate release-candidate --rung "Release candidate" --class Ordinary \
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
  if ( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$APP" --approved-by "solo maintainer" \
        --gate design --rung "Design" --class control-plane \
        --scope "branch/feat-b2-go" --token "GO: design at $APP" \
        --basis "docs/architecture/x-design.md" >/dev/null 2>&1 ); then _brc=0; else _brc=$?; fi
  _bscope="$( ( cd "$R" && git notes --ref=promotions show "$APP" 2>/dev/null \
                 | grep -c '^scope: branch/feat-b2-go$' ) || true )"
  if [ "$_brc" = 0 ] && [ "$_bscope" = 1 ]; then
    echo "PASS: branch scoping: --scope branch/<name> accepted and round-trips verbatim into the note"
  else
    echo "FAIL: branch scoping: record rc=$_brc, exact 'scope: branch/feat-b2-go' lines in note=$_bscope"; st=1
  fi
  if ( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$APP" --approved-by "solo maintainer" \
        --gate design --rung "Design" --class control-plane --scope "branch/" \
        --token "GO" >/dev/null 2>&1 ); then _b2rc=0; else _b2rc=$?; fi
  if [ "$_b2rc" = 2 ]; then
    echo "PASS: branch scoping NEGATIVE: a bare 'branch/' names no branch -> rc 2"
  else
    echo "FAIL: branch scoping NEGATIVE: 'branch/' should be rc 2, got rc=$_b2rc"; st=1
  fi
  if ( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$APP" --approved-by "solo maintainer" \
        --gate design --rung "Design" --class control-plane --scope "branch/feat+plus" \
        --token "GO" >/dev/null 2>&1 ); then _b3rc=0; else _b3rc=$?; fi
  if [ "$_b3rc" = 2 ]; then
    echo "PASS: branch scoping NEGATIVE: a name outside the gate's scope charset -> rc 2 (not recorded dead)"
  else
    echo "FAIL: branch scoping NEGATIVE: 'branch/feat+plus' should be rc 2, got rc=$_b3rc"; st=1
  fi
  # REGRESSION: the NEW rule applies to the `branch/` shape ONLY. Existing scopes keep their existing
  # hygiene — this repo's own ledger holds scopes with a space ("PR #999"), and retrofitting the
  # charset onto every scope would refuse records the gates already accept.
  if ( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$APP" --approved-by "solo maintainer" \
        --gate design --rung "Design" --class Ordinary --scope "PR #1005" \
        --token "GO" >/dev/null 2>&1 ); then _b4rc=0; else _b4rc=$?; fi
  if [ "$_b4rc" = 0 ]; then
    echo "PASS: branch scoping: a non-branch scope with a space is still accepted (no retrofit)"
  else
    echo "FAIL: branch scoping: 'PR #1005' must still record, got rc=$_b4rc"; st=1
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
      --gate promotion --rung "Ordinary" --class Ordinary --scope "PR #1010" \
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
      --gate promotion --rung "Ordinary" --class Ordinary --scope "PR #1011" \
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
    *"gate: promotion  scope: PR #1010  approved-by: solo maintainer [self-asserted]  go-by: (none recorded)") echo "PASS: trace L9: the per-commit line ends with the approver and 'go-by: (none recorded)' (prefix unchanged)" ;;
    *) echo "FAIL: trace L9: expected the line to end '...scope: PR #1010  approved-by: solo maintainer [self-asserted]  go-by: (none recorded)'; got: $_tr_l9"; st=1 ;;
  esac
  ( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$ROWC" --approved-by "solo maintainer" --go-by "Bradley James" \
      --gate promotion --rung "Ordinary" --class Ordinary --scope "PR #1010" \
      --token "GO: merge #1010 at $ROWC" >/dev/null 2>&1 ) || true
  _tr_l9="$( ( cd "$R" && $VSH "$VERIFY" trace --ref "$SQROW" 2>/dev/null ) || true )"
  case "$_tr_l9" in
    *"approved-by: solo maintainer [self-asserted]  go-by: Bradley James [self-asserted]") echo "PASS: trace L9: a recorded --go-by is printed beside the approver, labelled [self-asserted]" ;;
    *) echo "FAIL: trace L9: expected 'go-by: Bradley James [self-asserted]' at the end of the line; got: $_tr_l9"; st=1 ;;
  esac
  # trace prints note-derived text: a control byte (an ESC in a hand-written go-by) must not reach the terminal.
  ( cd "$R" && git notes --ref=promotions show "$ROWC" | sed "s/^go-by: .*/go-by: Bad$(printf '\033')Name [self-asserted]/" \
      | git notes --ref=promotions add -f -F - "$ROWC" ) >/dev/null 2>&1
  _tr_l9="$( ( cd "$R" && $VSH "$VERIFY" trace --ref "$SQROW" 2>/dev/null ) || true )"
  case "$_tr_l9" in
    *"go-by: BadName"*) if printf '%s' "$_tr_l9" | grep -q "$(printf '\033')"; then echo "FAIL: trace: an ESC byte reached the output"; st=1; else echo "PASS: trace: control bytes in a note's go-by are stripped from the printed line"; fi ;;
    *) echo "FAIL: trace: expected 'go-by: BadName' (control byte stripped, not the line dropped); got: $_tr_l9"; st=1 ;;
  esac
  ( cd "$R" && $VSH "$VERIFY" record --no-push --approved-sha "$ROWC" --approved-by "solo maintainer" --go-by "Bradley James" \
      --gate promotion --rung "Ordinary" --class Ordinary --scope "PR #1010" \
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

  # --recent: the RECORDLESS-MERGE leg the kit's own CI runs. Over a window that includes the
  # unrecorded BASE and 'squash-merge feat' commits it must RED and name at least one of them.
  _tr_out="$( ( cd "$R" && $VSH "$VERIFY" trace --recent 3 --from "$TRUNK" 2>&1 ) || true )"
  if ( cd "$R" && $VSH "$VERIFY" trace --recent 3 --from "$TRUNK" >/dev/null 2>&1 ); then
    echo "FAIL: trace --recent over a window containing recordless merges must RED"; st=1
  else
    echo "PASS: trace --recent NEGATIVE: a recordless trunk commit reds the window"
  fi
  case "$_tr_out" in
    *"$SQROW"*|*"no promotion note"*) echo "PASS: trace --recent names what it could not recover" ;;
    *) echo "FAIL: trace --recent red did not name the unrecoverable commit(s): $_tr_out"; st=1 ;;
  esac

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
        --gate promotion --rung Ordinary --class Ordinary --scope "PR #1012" \
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
    --approved-sha "$APP" --approved-by "solo maintainer" --gate g --rung r --class Ordinary \
    --scope "PR #1002" --token "$NL_TOK"

  NL_BASIS="$(printf 'reviewer APPROVE\napproved-by: forged [authenticated: github-review]')"
  reject_inj "injection NEGATIVE: newline+forged [authenticated: in --basis rejected" \
    --approved-sha "$APP" --approved-by "solo maintainer" --gate g --rung r --class Ordinary \
    --scope "PR #1003" --token "GO clean" --basis "$NL_BASIS"

  reject_inj "injection NEGATIVE: mid-string [signed: gpg] in --approved-by rejected" \
    --approved-sha "$APP" --approved-by "attacker [signed: gpg] and more" --gate g --rung r \
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
    {
      printf '#!/bin/sh\ncase "$*" in\n'
      printf '  */reviews*) printf "APPROVED\\t%%s\\t%%s\\tUser\\n" "%s" "%s" ;;\n' "$1" "$2"
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
          --go-by "the owner" --gate release-candidate --rung "Release candidate" --class "$_lcls" \
          --scope "$_lscope" --token "GO: land at $_lasha" "$@" 2>&1 )"; then _ldc=0; else _ldc=$?; fi
  }

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
        --approved-by "solo maintainer" --go-by "the owner" --gate release-candidate --rung "Release candidate" \
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
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && ! onote "$LOSHA" && printf '%s' "$_ld_out" | grep -q 'actuate'; then
    echo "PASS: land NEGATIVE(ord): --class ordinary is refused (-> actuate), no record, no merge"
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
  # mg_land -> runs land from the fixture clone; the ambient redirection/dial env is scrubbed, $MG_ENVX re-adds a leg's own.
  mg_land() {
    rm -f "$LAND_MARK"
    _mgh="$(lgh "$MG_ASHA" "${MG_ABY:-solo maintainer}")"   # the authenticated non-author approval the CP bar needs
    if _ld_out="$( cd "$LOA/${MG_SUB:-}" && env -u KIT_RUNAWAY_SANDBOX -u RUNAWAY_TALLY -u RUNAWAY_BUDGET_CONFIG -u RUNAWAY_METERING_GATE \
          HOME="$MG_H" $MG_ENVX PATH="$_mgh:$PATH" PROMOTION_NOTES_REF="$LR2" $VSH "$MG_K/scripts/promotion-verify.sh" land \
          --ref 77 --merge-cmd "$LAND_STUB" --approved-sha "$MG_ASHA" --approved-by "${MG_ABY:-solo maintainer}" \
          --go-by "the owner" --gate release-candidate --rung "Release candidate" --class control-plane \
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
  mg_fx enfun "$MG_DIAL_ENF" ROW-MG1 code; mg_land
  mg_check "land METER(enforce, unmetered): refused, NO note on origin, NO merge, the remedy names the exact step command" refuse \
    "LAND REFUSED (metering gate)" "step --row ROW-MG1 --tokens N --agents N" "never estimate" "default branch"

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

  mg_fx rename "$MG_DIAL_ENF" ROW-MG8 rename base; mg_land
  mg_check "land METER(a .sh -> .md rename is NOT docs-only): refused in enforce" refuse "LAND REFUSED (metering gate)" "!N/A: docs-only"

  mg_fx nobase "$MG_DIAL_ENF" ROW-MG9 docs base
  git -C "$LOA" remote set-url origin "$MG_ROOT/no-such-origin"; mg_land
  mg_check "land METER(remote unreachable -> no docs-only base): NOT docs-only — refused in enforce, says the base is unreadable (fix2 B)" refuse "LAND REFUSED (metering gate)" "!N/A: docs-only" \
    "docs-only exemption unavailable: cannot read origin's main"

  # fix round 1 (security HIGH): the dial read is FULL-TREE — from a SUBDIRECTORY the gate still reads the root .kit/dials.conf.
  mg_fx subdir "$MG_DIAL_ENF" ROW-MG21 code; mkdir -p "$LOA/sub"; MG_SUB=sub; mg_land; MG_SUB=""
  mg_check "land METER(fix1 A): enforce + unmetered invoked from a SUBDIRECTORY -> still refused" refuse "LAND REFUSED (metering gate)" "step --row ROW-MG21"

  # fix round 1 (security MEDIUM): a refs/replace ref pointing the approved sha at a commit whose dial says observe must not de-escalate.
  mg_fx replace "$MG_DIAL_ENF" ROW-MG22 code
  ( set -e; cd "$LOA"; git checkout -q -b crafted; printf 'RUNAWAY_METERING_GATE=observe\n' > .kit/dials.conf; git add .kit
    printf 'crafted\n\nKit-Row: ROW-MG22\nKit-Class: control-plane\n' | git commit -q -F -
    git replace -f "$MG_ASHA" "$(git rev-parse HEAD)"; git checkout -q mgfeat ) || { echo "FAIL: could not build the replace-ref fixture"; st=1; }
  mg_land
  mg_check "land METER(fix1 B): a replace ref redirecting the approved sha to an observe tree does NOT de-escalate -> refused" refuse "LAND REFUSED (metering gate)"

  # fix round 1 (security MEDIUM): the docs-only base is the REMOTE's main, not the local origin/main ref an agent can move.
  mg_fx movedbase "$MG_DIAL_ENF" ROW-MG23 codedocs base
  git -C "$LOA" update-ref refs/remotes/origin/main "${MG_ASHA}^"; mg_land
  mg_check "land METER(fix1 C): a code+docs change with the LOCAL origin/main moved to the approved parent is NOT docs-only -> refused" refuse "LAND REFUSED (metering gate)" "!N/A: docs-only" "!docs-only exemption unavailable"

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

  mg_fx nocls "$MG_DIAL_ENF" ROW-MG10 docs base; mg_layout "$MG_ROOT/kit-nocls" noclassifier; MG_K="$MG_ROOT/kit-nocls"; mg_land; MG_K="$MG_KIT"
  mg_check "land METER(classifier absent): NOT docs-only (fail-safe) — refused in enforce" refuse "LAND REFUSED (metering gate)" "!N/A: docs-only"

  mg_fx norow "$MG_DIAL_ENF" NONE code; mg_land
  mg_check "land METER(no Kit-Row trailer, enforce): refused — cannot meter an unnamed row" refuse "LAND REFUSED (metering gate)" "unnamed row"
  mg_fx nonerow "$MG_DIAL_ENF" '(none)' code; mg_land
  mg_check "land METER(Kit-Row: (none), enforce): refused" refuse "unnamed row"
  mg_fx norowobs "$MG_DIAL_OBS" NONE code; mg_land
  mg_check "land METER(no row, observe): proceeds with one line" proceed "unnamed row" "observe"

  mg_fx bad 'RUNAWAY_METERING_GATE=enforcee' ROW-MG11 code; mg_land
  mg_check "land METER(malformed conf value): reads as observe and WARNs on the conf side" proceed "WARN" ".kit/dials.conf" "unmetered: ROW-MG11 (observe — not gating)"

  mg_fx wtobs "$MG_DIAL_ENF" ROW-MG12 code
  printf 'RUNAWAY_METERING_GATE=observe\n' > "$LOA/.kit/dials.conf"; mg_land
  mg_check "land METER(F1): the working tree says observe but the APPROVED tree says enforce -> refused" refuse "LAND REFUSED (metering gate)"
  mg_fx wtenf NONE ROW-MG13 code
  mkdir -p "$LOA/.kit"; printf 'RUNAWAY_METERING_GATE=enforce\n' > "$LOA/.kit/dials.conf"; mg_land
  mg_check "land METER(F1 converse): the working tree says enforce but the approved tree carries no key -> silent, proceeds" proceed "!metering gate" "!unmetered"

  mg_fx envobs "$MG_DIAL_ENF" ROW-MG14 code; MG_ENVX="RUNAWAY_METERING_GATE=observe"; mg_land; MG_ENVX=""
  mg_check "land METER(F1): env =observe cannot de-escalate an enforcing approved tree -> refused, and says so" refuse "LAND REFUSED (metering gate)" "cannot de-escalate"
  mg_fx envenf NONE ROW-MG15 code; MG_ENVX="RUNAWAY_METERING_GATE=enforce"; mg_land; MG_ENVX=""
  mg_check "land METER(F1): env =enforce escalates a tree with no key -> refused" refuse "LAND REFUSED (metering gate)"
  mg_fx envbad "$MG_DIAL_ENF" ROW-MG16 code; MG_ENVX="RUNAWAY_METERING_GATE=bogus"; mg_land; MG_ENVX=""
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
  mg_check "land METER(F2): the sandbox env exported while the temp-HOME tally is unmetered -> still refused" refuse "LAND REFUSED (metering gate)" "step --row ROW-MG18"

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
      printf 'a\n' > f.txt; git add f.txt; git commit -qm base
      git push -q origin HEAD:refs/heads/main
      cd "$LF"
      git clone -q remote.git B 2>/dev/null
      cd B
      git config user.email t@example.com; git config user.name t; git config commit.gpgsign false
      git commit -q --allow-empty -m b-side )
    ASHA="$(git -C "$LF/A" rev-parse HEAD)"
    BSHA="$(git -C "$LF/B" rev-parse HEAD)"
  }
  # lrec <clone-dir> <approved-sha> <scope> [extra record args...] -> sets LRC and LOUT.
  lrec() {
    _cd="$1"; _cs="$2"; _cp="$3"; shift 3
    if LOUT="$( cd "$_cd" && PROMOTION_NOTES_REF="$LR" $VSH "$VERIFY" record \
          --approved-sha "$_cs" --approved-by "solo maintainer" --gate design --rung Design \
          --class control-plane --scope "$_cp" --token "GO: $_cp" "$@" 2>&1 )"; then
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
      printf '  --approved-by racer --gate design --rung Design --class control-plane \\\n'
      printf '  --scope branch/racer-$$ --token "GO: racer" ) >/dev/null 2>&1\nexit 0\n'
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
  git -C "$LF/A" commit -q --allow-empty -m a2
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
  git -C "$LF/A" commit -q --allow-empty -m a2
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
    git -C "$LF/A" commit -q --allow-empty -m a2
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
  git -C "$LF/A" commit -q --allow-empty -m a2
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
  git -C "$LF/A" commit -q --allow-empty -m a2
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
  git -C "$LF/A" commit -q --allow-empty -m a2
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
  git -C "$LF/A" commit -q --allow-empty -m a2
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
        --approved-by x --gate design --rung Design --class control-plane --scope branch/x \
        --token GO 2>&1 )"; then LRC=0; else LRC=$?; fi
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
    if LOUT="$( cd "$_cd" && PATH="${LSHIM_DIR:+$LSHIM_DIR:}$PATH" FAIL_GIT_SUB="${LSHIM_SUB:-}" PROMOTION_NOTES_REF="$LR" $VSH "$VERIFY" sync "$@" 2>&1 )"; then
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
  git -C "$LF/A" commit -q --allow-empty -m a2; _a2="$(git -C "$LF/A" rev-parse HEAD)"
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
  lrec "$LF/B" "$ASHA" "branch/s4" --no-push --token "different token" --basis "different basis"
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
  git -C "$LF/A" commit -q --allow-empty -m a2; _a2="$(git -C "$LF/A" rev-parse HEAD)"
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
  git -C "$LF/A" commit -q --allow-empty -m a2; _a2="$(git -C "$LF/A" rev-parse HEAD)"
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
    git -C "$LF/A" commit -q --allow-empty -m a2; _fa2="$(git -C "$LF/A" rev-parse HEAD)"
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
  git -C "$LF/A" commit -q --allow-empty -m a2; _fa2="$(git -C "$LF/A" rev-parse HEAD)"
  lrec "$LF/A" "$_fa2" "branch/s2rowb"
  git -C "$LF/B" commit -q --allow-empty -m b-row -m "Kit-Row: A"; BSHA="$(git -C "$LF/B" rev-parse HEAD)"
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
  lrec "$LF/B" "$BSHA" "branch/s8nb" --no-push --go-by "SeaBrad72"
  _l8n="$(git -C "$LF/B" notes --ref="$LR" show "$BSHA" | wc -l | tr -d ' ')"
  _l8g="$(git -C "$LF/B" notes --ref="$LR" show "$BSHA" | sed -n '5p')"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsync "$LF/B"
  if [ "$_anc" = 0 ] && [ "$_l8n" = 13 ] && [ "$_l8g" = 'go-by: SeaBrad72 [self-asserted]' ] && [ "$LRC" = 0 ] \
     && printf '%s' "$LOUT" | grep -q "published $BSHA" && [ "$(git --git-dir="$LF/remote.git" notes --ref="$LR" show "$BSHA" | sed -n '5p')" = "$_l8g" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync L8(b) (+): a 13-line note with 'go-by: SeaBrad72 [self-asserted]' at line 5 is accepted and published byte-identical" "anc=$_anc lines=$_l8n l5=$_l8g rc=$LRC out=$LOUT"
  for _l8lab in 'authenticated: github-review' 'committer' 'signed: gpg'; do
    _l8k=$((${_l8k:-0} + 1))
    lfix "s8forge$_l8k"; lrec "$LF/B" "$BSHA" "branch/s8fb" --no-push --go-by "SeaBrad72"
    lmut "$LF/B" "$BSHA" "s/^go-by: .*/go-by: SeaBrad72 [$_l8lab]/"
    lvcase "sync L8(c) (−): a go-by carrying [$_l8lab] is refused naming go-by (the GO-giver is never authenticated), nothing moved" 'go-by'
  done
  lfix s8blank; lrec "$LF/B" "$BSHA" "branch/s8bb" --no-push --go-by "SeaBrad72"
  lmut "$LF/B" "$BSHA" 's/^go-by: .*/go-by: SeaBrad72/'
  lvcase "sync L8(c) (−): a go-by with no [self-asserted] label is refused naming go-by" 'go-by'
  mkledger s8twin
  lrec "$LF/A" "$ASHA" "branch/s8t" --go-by "SeaBrad72"
  lrec "$LF/B" "$ASHA" "branch/s8t" --no-push --token "local token" --go-by "SomeoneElse"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  _lpre="$(lrev "$LF/B")"
  lsync "$LF/B"
  if [ "$_anc" = 0 ] && [ "$LRC" = 2 ] && printf '%s' "$LOUT" | grep -q 'DIFFERENT identity' && printf '%s' "$LOUT" | grep -q "REFUSED $ASHA" \
     && printf '%s' "$LOUT" | grep -q 'go-by: SomeoneElse \[self-asserted\]' && [ "$(lrev "$LF/B")" = "$_lpre" ]; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync L8(d) (−): a same-sha twin differing ONLY in go-by is a different GO -> rc 2 DIFFERENT identity, both notes printed, ledger untouched" "anc=$_anc rc=$LRC out=$LOUT"
  mkledger s8twin2
  lrec "$LF/A" "$ASHA" "branch/s8t2" --go-by "SeaBrad72"
  lrec "$LF/B" "$ASHA" "branch/s8t2" --no-push --token "local token" --go-by "SeaBrad72"
  if ldiverged "$LF/B"; then _anc=0; else _anc=1; fi
  lsync "$LF/B"
  if [ "$_anc" = 0 ] && [ "$LRC" = 0 ] && printf '%s' "$LOUT" | grep -q "twin-origin-wins $ASHA"; then _lc=0; else _lc=1; fi
  lpass "$_lc" "sync L8(d) (+): the same twin with the SAME go-by is a free-text twin -> twin-origin-wins (the identity field is not a refuse-all)" "anc=$_anc rc=$LRC out=$LOUT"

  # (−) T2-8: a non-fast-forward RACE. A holds a free-text twin of ASHA (so the run DROPS content and
  # makes a backup) plus a new record on a2; the racer (clone B, via A's reference-transaction hook)
  # records and PUBLISHES the instant A's CAS moves the ledger, so A's first push is rejected. A must
  # unwind, delete the backup THIS run made, retry once, and publish. Both records end on origin, and
  # exactly ONE backup ref survives (the retry's), never two.
  mkledger s2race
  lrec "$LF/A" "$ASHA" "branch/s2r1"
  lrec "$LF/B" "$BSHA" "branch/s2r2"
  lrec "$LF/A" "$ASHA" "branch/s2r1" --no-push --token "local twin"
  git -C "$LF/A" commit -q --allow-empty -m a2; _fa2="$(git -C "$LF/A" rev-parse HEAD)"
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
  lsig "$LF/B" push record --approved-sha "$BSHA" --approved-by "solo maintainer" --gate design --rung Design --class control-plane --scope branch/f1a --token "GO: f1a"
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
  lsig "$LF/B" push record --approved-sha "$BSHA" --approved-by "solo maintainer" --gate design --rung Design --class control-plane --scope branch/f1b --token "GO: f1b"
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
  git -C "$LF/A" commit -q --allow-empty -m a2; _fa2="$(git -C "$LF/A" rev-parse HEAD)"
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
  lplant "$LF/B" "refs/kit/notes-remote-" record --approved-sha "$ASHA" --approved-by "solo maintainer" --gate design --rung Design --class control-plane --scope branch/b1c --token "GO: b1c"
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
  git -C "$LF/S" commit -q --allow-empty -m s-side; _ssha="$(git -C "$LF/S" rev-parse HEAD)"
  lrec "$LF/S" "$_ssha" "branch/b4s" --no-push
  git -C "$LF/A" commit -q --allow-empty -m a2; _fa2="$(git -C "$LF/A" rev-parse HEAD)"
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
  git -C "$LF/A" commit -q --allow-empty -m a2; _fa2="$(git -C "$LF/A" rev-parse HEAD)"
  lrec "$LF/A" "$_fa2" "branch/b4bb"
  git clone -q "file://$LF/remote.git" "$LF/S2" 2>/dev/null
  git -C "$LF/S2" config user.email t@example.com; git -C "$LF/S2" config user.name t; git -C "$LF/S2" config commit.gpgsign false
  git -C "$LF/S2" fetch -q --depth 1 origin "refs/notes/$LR:refs/notes/$LR"
  git -C "$LF/S2" commit -q --allow-empty -m s2-side; _s2sha="$(git -C "$LF/S2" rev-parse HEAD)"
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
  lplant "$LOA" "refs/notes/kit-land-confirm-" land --ref 77 --merge-cmd "$LAND_STUB" --approved-sha "$LOSHA" --approved-by "solo maintainer" --go-by "the owner" --gate release-candidate --rung "Release candidate" --class control-plane --scope "PR #77" --token "GO: land c2"
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

  if [ "$st" = 0 ]; then
    echo "OK: promotion-verify-wired selftest [producer shell: $VSH] (fixture left in $D)"
  else
    echo "FAIL: promotion-verify-wired selftest [producer shell: $VSH] (fixture left in $D)"
  fi
  return $st
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "") [ -f "$VERIFY" ] || { echo "FAIL: missing producer $VERIFY"; exit 1; }
      echo "OK: promotion-verify producer present ($VERIFY)"; exit 0 ;;
  *) echo "usage: promotion-verify-wired.sh [--selftest]" >&2; exit 2 ;;
esac
