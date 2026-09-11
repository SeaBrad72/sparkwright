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
  if ( cd "$R" && sh "$VERIFY" record --no-push --approved-sha "$APP" --approved-by "solo maintainer" \
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
  ( cd "$R" && sh "$VERIFY" record --no-push --approved-sha "$SIDE" --approved-by "solo maintainer" \
      --gate release-candidate --rung "Release candidate" --class Ordinary \
      --scope "PR #1000" --token "GO: merge #1000 at $SIDE" >/dev/null 2>&1 ) \
    || { echo "FAIL: second record (SIDE) failed"; st=1; }
  assert 1 "note round-trip NEGATIVE: latest note (SIDE) tree != squash tip -> FAIL" --ref "$SQ"

  # --- LABEL-CAN'T-LIE (the non-vacuity anchor): the emitted label is DERIVED from the commit's
  #     evidence, never from input. On an UNSIGNED commit with a free-typed approver that is NOT the
  #     committer, the label MUST be [self-asserted] — never [signed: gpg]. (A smuggled bracket claim
  #     is now rejected outright at input — see the injection negatives below — so here we feed a
  #     CLEAN id and assert the derivation itself cannot overclaim.) ---
  ( cd "$R" && sh "$VERIFY" record --no-push --approved-sha "$APP" --approved-by "attacker" \
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
  if ( cd "$R" && sh "$VERIFY" record --no-push --approved-sha "$APP" --approved-by "solo maintainer" \
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
  if ( cd "$R" && sh "$VERIFY" record --no-push --approved-sha "$APP" --approved-by "solo maintainer" \
        --gate design --rung "Design" --class control-plane --scope "branch/" \
        --token "GO" >/dev/null 2>&1 ); then _b2rc=0; else _b2rc=$?; fi
  if [ "$_b2rc" = 2 ]; then
    echo "PASS: branch scoping NEGATIVE: a bare 'branch/' names no branch -> rc 2"
  else
    echo "FAIL: branch scoping NEGATIVE: 'branch/' should be rc 2, got rc=$_b2rc"; st=1
  fi
  if ( cd "$R" && sh "$VERIFY" record --no-push --approved-sha "$APP" --approved-by "solo maintainer" \
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
  if ( cd "$R" && sh "$VERIFY" record --no-push --approved-sha "$APP" --approved-by "solo maintainer" \
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

  ( cd "$R" && sh "$VERIFY" record --no-push --approved-sha "$ROWC" --approved-by "solo maintainer" \
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
  ( cd "$R" && sh "$VERIFY" record --no-push --approved-sha "$SIDE" --approved-by "solo maintainer" \
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
  if ( cd "$R" && sh "$VERIFY" record --no-push --approved-sha "$CTRLC" --approved-by "solo maintainer" \
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
    git init -q --bare "$LO/remote.git"
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
  # lland <merge-cmd> <approved-sha> <class> <scope> [extra land args...] -> sets _ldc and _ld_out.
  # Runs in $LOA with PROMOTION_NOTES_REF=$LR2 so nothing here can touch the real ledger.
  lland() {
    _lmc="$1"; _lasha="$2"; _lcls="$3"; _lscope="$4"; shift 4
    if _ld_out="$( cd "$LOA" && PROMOTION_NOTES_REF="$LR2" sh "$VERIFY" land \
          --ref v1.0.0 --merge-cmd "$_lmc" --approved-sha "$_lasha" --approved-by "solo maintainer" \
          --gate release-candidate --rung "Release candidate" --class "$_lcls" \
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

  # (−i) RECORD FAILS -> NO merge. An UNRESOLVABLE --approved-sha reds `record` (rc 2) BEFORE any note
  #      is written, so the stub merge must NOT run and the reason is verb-scoped. The class is
  #      control-plane so land's OWN class gate (F3-2) passes and the failure is genuinely record's,
  #      not land's class refusal. (Discriminant partner of the liveness leg above; the bad-class case
  #      is now caught by land's class gate — see NEGATIVE(unknown-class) below.)
  mkorigin badsha
  rm -f "$LAND_MARK"
  lland "$LAND_STUB" deadbeefdeadbeefdeadbeefdeadbeefdeadbeef control-plane "branch/land-badsha"
  if [ "$_ldc" != 0 ] && [ ! -f "$LAND_MARK" ] && printf '%s' "$_ld_out" | grep -q 'will not merge'; then
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
     && ( cd "$LOA" && PROMOTION_NOTES_REF="$LR2" sh "$VERIFY" trace --recent 1 --from "$LANDTIP" >/dev/null 2>&1 ); then
    echo "PASS: land + trace: a merge landed by land is recoverable — trace --recent binds the trunk head"
  else
    echo "FAIL: land + trace: rc=$_ldc, trace --recent 1 did not bind the trunk head $LANDTIP; out=$_ld_out"; st=1
  fi
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
    git init -q --bare "$LF/remote.git"
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
    if LOUT="$( cd "$_cd" && PROMOTION_NOTES_REF="$LR" sh "$VERIFY" record \
          --approved-sha "$_cs" --approved-by "solo maintainer" --gate design --rung Design \
          --class control-plane --scope "$_cp" --token "GO: $_cp" "$@" 2>&1 )"; then
      LRC=0; else LRC=$?; fi
  }
  # llog <clone-dir> [args...] -> sets LRC and LOUT
  llog() {
    _cd="$1"; shift
    if LOUT="$( cd "$_cd" && PROMOTION_NOTES_REF="$LR" sh "$VERIFY" log "$@" 2>&1 )"; then
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
  if LOUT="$( cd "$LF/A" && PROMOTION_NOTES_REF='*' sh "$VERIFY" record --approved-sha "$ASHA" \
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
