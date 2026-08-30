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

selftest() {
  st=0
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
    if ( cd "$R" && sh "$VERIFY" check "$@" >/dev/null 2>&1 ); then _got=0; else _got=$?; fi
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
  if ( cd "$R" && sh "$VERIFY" record --approved-sha "$APP" --approved-by "solo maintainer" \
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
  if ( cd "$R" && sh "$VERIFY" log 2>/dev/null | grep -q "$APP" ); then
    echo "PASS: note round-trip: log projects the recorded approved-sha"
  else
    echo "FAIL: note round-trip: log did not list $APP"; st=1
  fi
  assert 0 "note round-trip: check resolves latest approved-sha (APP) from the note" --ref "$SQ"
  # a LATER record binding the divergent SIDE -> resolve must now pick SIDE and FAIL.
  ( cd "$R" && sh "$VERIFY" record --approved-sha "$SIDE" --approved-by "solo maintainer" \
      --gate release-candidate --rung "Release candidate" --class Ordinary \
      --scope "PR #1000" --token "GO: merge #1000 at $SIDE" >/dev/null 2>&1 ) \
    || { echo "FAIL: second record (SIDE) failed"; st=1; }
  assert 1 "note round-trip NEGATIVE: latest note (SIDE) tree != squash tip -> FAIL" --ref "$SQ"

  # --- LABEL-CAN'T-LIE (the non-vacuity anchor): the emitted label is DERIVED from the commit's
  #     evidence, never from input. On an UNSIGNED commit with a free-typed approver that is NOT the
  #     committer, the label MUST be [self-asserted] — never [signed: gpg]. (A smuggled bracket claim
  #     is now rejected outright at input — see the injection negatives below — so here we feed a
  #     CLEAN id and assert the derivation itself cannot overclaim.) ---
  ( cd "$R" && sh "$VERIFY" record --approved-sha "$APP" --approved-by "attacker" \
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
  if ( cd "$R" && sh "$VERIFY" record --approved-sha "$APP" --approved-by "solo maintainer" \
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
  if ( cd "$R" && sh "$VERIFY" record --approved-sha "$APP" --approved-by "solo maintainer" \
        --gate design --rung "Design" --class control-plane --scope "branch/" \
        --token "GO" >/dev/null 2>&1 ); then _b2rc=0; else _b2rc=$?; fi
  if [ "$_b2rc" = 2 ]; then
    echo "PASS: branch scoping NEGATIVE: a bare 'branch/' names no branch -> rc 2"
  else
    echo "FAIL: branch scoping NEGATIVE: 'branch/' should be rc 2, got rc=$_b2rc"; st=1
  fi
  if ( cd "$R" && sh "$VERIFY" record --approved-sha "$APP" --approved-by "solo maintainer" \
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
  if ( cd "$R" && sh "$VERIFY" record --approved-sha "$APP" --approved-by "solo maintainer" \
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

  ( cd "$R" && sh "$VERIFY" record --approved-sha "$ROWC" --approved-by "solo maintainer" \
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
  ( cd "$R" && sh "$VERIFY" record --approved-sha "$SIDE" --approved-by "solo maintainer" \
      --gate promotion --rung "Ordinary" --class Ordinary --scope "PR #1011" \
      --token "GO clean" >/dev/null 2>&1 ) || { echo "FAIL: record on the trailerless commit failed"; st=1; }
  if ( cd "$R" && git notes --ref=promotions show "$SIDE" 2>/dev/null | grep -qxF 'kit-row: (none)' ); then
    echo "PASS: kit-row projection: a commit with no Kit-Row records '(none)', never an invented row"
  else
    echo "FAIL: kit-row projection: the note on $SIDE does not carry 'kit-row: (none)'"; st=1
  fi

  # THE RECOVERY ITSELF: trace on the SQUASHED trunk commit finds the row the trunk message lost.
  if ( cd "$R" && sh "$VERIFY" trace --ref "$SQROW" 2>/dev/null | grep -qF 'DEMO-ROW-42' ); then
    echo "PASS: trace: the row is recoverable for a squashed trunk commit that carries no trailer"
  else
    echo "FAIL: trace --ref $SQROW did not recover kit-row DEMO-ROW-42"; st=1
  fi

  # NEGATIVE: a trunk commit with NO matching note must exit 1 and NAME the commit. EXTRA's tree
  # equals nothing that was ever recorded. Without this leg an always-0 trace passes everything.
  if ( cd "$R" && sh "$VERIFY" trace --ref "$EXTRA" >/dev/null 2>&1 ); then
    echo "FAIL: trace on a commit with no matching promotion note must exit 1, but it passed"; st=1
  else
    echo "PASS: trace NEGATIVE: a commit with no matching note exits 1 (recordless merge is loud)"
  fi

  # --recent: the RECORDLESS-MERGE leg the kit's own CI runs. Over a window that includes the
  # unrecorded BASE and 'squash-merge feat' commits it must RED and name at least one of them.
  _tr_out="$( ( cd "$R" && sh "$VERIFY" trace --recent 3 --from "$TRUNK" 2>&1 ) || true )"
  if ( cd "$R" && sh "$VERIFY" trace --recent 3 --from "$TRUNK" >/dev/null 2>&1 ); then
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
  if ( cd "$R" && sh "$VERIFY" trace --recent 1 --from "$SQROW" >/dev/null 2>&1 ); then
    echo "PASS: trace --recent POSITIVE: a fully recorded window is green"
  else
    echo "FAIL: trace --recent over the single recorded commit $SQROW must be green"; st=1
  fi

  # THE SUMMARY MUST NOT OVERSTATE. Every note on this repo's main today predates the kit-row
  # projection, so a `--recent` verdict reading "N/N carry a recoverable board row" over N
  # `(not recorded)` lines would be the exact overstatement this repo bans. A green window whose
  # single commit DOES carry a projected row must report 1 projected and 0 pre-projection; the
  # counts must be reported separately from the note-binding count.
  _tr_sum="$( ( cd "$R" && sh "$VERIFY" trace --recent 1 --from "$SQROW" 2>&1 ) || true )"
  case "$_tr_sum" in
    *"bound to a promotion note"*"1 carry a projected board row; 0 predate"*)
      echo "PASS: trace --recent reports note-binding and ROW projection as separate counts" ;;
    *) echo "FAIL: trace --recent summary conflates 'bound to a note' with 'carries a row': $_tr_sum"; st=1 ;;
  esac

  # …and the pre-projection case is COUNTED, not silently credited. APP's note was written before
  # kit-row existed in this fixture's first records; re-record it WITHOUT a row-bearing commit and
  # the window must say so. (SIDE recorded `(none)` above — a positive statement, distinct from a
  # note that has no kit-row line at all.)
  case "$( ( cd "$R" && sh "$VERIFY" trace --ref "$SIDE" 2>&1 ) || true )" in
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
  _tr_dup="$( ( cd "$R" && sh "$VERIFY" trace --recent 2 --from "$EMPTYC" 2>&1 ) || true )"
  if ( cd "$R" && sh "$VERIFY" trace --recent 2 --from "$EMPTYC" >/dev/null 2>&1 ); then
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
  _tr_orph="$( ( cd "$R" && sh "$VERIFY" trace --ref "$ORPHANC" 2>&1 ) || true )"
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
  _tr_leg="$( ( cd "$R" && sh "$VERIFY" trace --ref "$LEGACYC" 2>&1 ) || true )"
  if ( cd "$R" && sh "$VERIFY" trace --ref "$LEGACYC" >/dev/null 2>&1 ); then
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
  _tr_zero="$( ( cd "$R" && sh "$VERIFY" trace --recent 0 --from "$TRUNK" 2>&1 ) || true )"
  if ( cd "$R" && sh "$VERIFY" trace --recent 0 --from "$TRUNK" >/dev/null 2>&1 ); then
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
  if ( cd "$R" && sh "$VERIFY" record --approved-sha "$CTRLC" --approved-by "solo maintainer" \
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
  ( cd "$R" && sh "$VERIFY" trace --ref "$SQROW" >/dev/null 2>&1 ) || true
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
    if ( cd "$R" && sh "$VERIFY" record "$@" >/dev/null 2>&1 ); then _irc=0; else _irc=$?; fi
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

  if [ "$st" = 0 ]; then
    echo "OK: promotion-verify-wired selftest (fixture left in $D)"
  else
    echo "FAIL: promotion-verify-wired selftest (fixture left in $D)"
  fi
  return $st
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "") [ -f "$VERIFY" ] || { echo "FAIL: missing producer $VERIFY"; exit 1; }
      echo "OK: promotion-verify producer present ($VERIFY)"; exit 0 ;;
  *) echo "usage: promotion-verify-wired.sh [--selftest]" >&2; exit 2 ;;
esac
