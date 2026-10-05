#!/bin/sh
# promotion-actuate-wired.sh — regression-lock for the CONTROL-PLANE actuation GATE
# (scripts/promotion-verify.sh `actuate`) and its guard denial of the --admin bypass
# (.claude/hooks/guard-core.sh). Proves the gate is WIRED and NON-VACUOUS: a control-plane merge is
# actuated ONLY on a recorded GO note whose DERIVED approved-by label is [authenticated: <forge>-
# review] AND approver != author, then shipped==approved is re-verified; every weaker / spoofed /
# wrong-SHA / self-approval case fails CLOSED, the --admin bypass stays guard-denied, and the actuate
# path never emits --admin. S6 — the control-plane actuation capstone.
# (docs/governance/promotion-contract.md; docs/architecture/2026-07-07-s6-control-plane-actuation-plan.md)
#   sh conformance/promotion-actuate-wired.sh [--selftest]
# Exit: 0 = ok . 1 = drift/vacuity . 2 = usage. POSIX sh; dash-clean.
#
# HONEST CEILING (rewritten at PR 11 — the paragraph it replaced said the derivation was UNWIRED,
# which stopped being true in the same diff that added these legs): this lock proves the GATE is wired
# + non-vacuous (the [authenticated: <forge>-review] bar, the approver!=author SoD teeth, the
# tree-equality re-check, the control-plane refusal, and the guard --admin deny are all real and
# LOAD-BEARING), AND that the label the bar demands is now DERIVABLE by a production path — the
# REC-* legs drive the real `record` against a `gh` PATH shim, so the derivation's own conditions are
# fixture-proven here rather than assumed. It still does NOT prove the live `gh pr merge` (a swappable
# --merge-cmd stub), a real forge credential, or that a note is authentic: a note is self-authorable
# and the derivation trusts the local `gh`, so the label remains a DRIFT CONTROL at the note's own
# trust tier. The LOCK SELF-NEGATIVE (below) proves the lock ITSELF is non-vacuous: a
# neutralized/always-pass gate MUST fail this lock.
set -eu

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

# wiring() inspects three real installed surfaces, resolved from $SCRIPT_DIR (co-located scratchpad
# authoring, else the installed layout) — NOT overridable by the caller's environment. The selftest
# aims wiring() at fixtures WITHOUT touching wiring()'s logic by reassigning VERIFY/GUARD/VERIFY_SH as
# SUBSHELL-LOCALS inside _expect_wiring's $( … ), never via the environment. Mirrors
# promotion-verify-wired.sh's resolution.
VERIFY="$SCRIPT_DIR/promotion-verify.sh"
[ -f "$VERIFY" ] || VERIFY="$SCRIPT_DIR/../scripts/promotion-verify.sh"
GUARD="$SCRIPT_DIR/../.claude/hooks/guard-core.sh"
[ -f "$GUARD" ]  || GUARD="$SCRIPT_DIR/../guard-core.sh"
VERIFY_SH="$SCRIPT_DIR/verify.sh"

# The control-plane bar the gate MUST enforce (fixed string; the brackets are LITERAL -> grep -F).
BAR='authenticated: [A-Za-z0-9_-]+-review'
# The ratified guard reason string that denies the --admin branch-protection bypass.
ADMIN_DENY='gh pr merge --admin bypasses branch protection'

# ===========================================================================================
# DEFAULT (no --selftest): WIRING / PRESENCE checks against the REAL installed paths. These pass
# post-apply.py (the reals carry the gate + guard). Any missing surface -> FAIL with a legible reason.
# ===========================================================================================
wiring() {
  _w=0
  [ -f "$VERIFY" ] || { echo "FAIL: missing actuate producer $VERIFY"; return 1; }
  [ -f "$GUARD" ]  || { echo "FAIL: missing guard core $GUARD"; return 1; }

  grep -q 'actuate)' "$VERIFY" \
    || { echo "FAIL: $VERIFY has no 'actuate)' dispatcher case"; _w=1; }
  grep -qF "$BAR" "$VERIFY" \
    || { echo "FAIL: $VERIFY does not enforce the control-plane bar (/$BAR/ absent)"; _w=1; }
  { grep -q '%an' "$VERIFY" && grep -q '%ae' "$VERIFY"; } \
    || { echo "FAIL: $VERIFY lacks the approver!=author (%an/%ae) comparison"; _w=1; }

  grep -qF "$ADMIN_DENY" "$GUARD" \
    || { echo "FAIL: $GUARD does not deny the --admin bypass (ratified reason string absent)"; _w=1; }
  grep -qF 'promotion-verify.sh' "$GUARD" \
    || { echo "FAIL: $GUARD does not list promotion-verify.sh (control-plane immutability)"; _w=1; }

  { [ -f "$VERIFY_SH" ] && grep -qF 'promotion-actuate-wired.sh' "$VERIFY_SH"; } \
    || { echo "FAIL: conformance/verify.sh does not register promotion-actuate-wired.sh"; _w=1; }

  [ "$_w" = 0 ] && echo "OK: actuate gate + guard --admin deny + verify.sh registration wired"
  return $_w
}

# ===========================================================================================
# --selftest — the NON-VACUITY heart. Self-contained throwaway git repos (mktemp -d; no network).
# The ORACLE (st / pass / fail) and the wiring oracle helper live BELOW the selftest() marker so the
# non-vacuity harness never mutates them — an always-pass oracle would hide a dead check.
# ===========================================================================================

# Build a throwaway repo: commit G (last-good) as `committer`, then X authored as `Author A` on feat.
# G's tree ("base") differs from X's tree ("base"+"x") — real objects, genuine tree-equality. Writes
# $D/.G and $D/.X inside the dir; echoes the dir. (Same shape as scratchpad/s6/test-actuate.sh.)
mkrepo() {
  _d="$(mktemp -d)"
  (
    set -e
    cd "$_d"
    git init -q
    git config user.email committer@example.com
    git config user.name  committer
    git config commit.gpgsign false
    printf 'base\n' > f.txt
    git add f.txt; git commit -qm G
    git rev-parse HEAD > "$_d/.G"
    git checkout -q -b feat
    printf 'x\n' >> f.txt
    git add f.txt
    GIT_AUTHOR_NAME='Author A' GIT_AUTHOR_EMAIL='a@x' git commit -qm X
    git rev-parse HEAD > "$_d/.X"
  ) || return 1
  printf '%s\n' "$_d"
}

# Fabricate a GO note on <sha> with a chosen approved-by value (id + label) + optional basis body
# (used to plant a decoy `[...]` substring — the label read must ignore the body). The authenticated
# label can NEVER be emitted by derive_assurance solo (the vc-hosts seam), so fixtures write it
# directly — exactly the design's liveness-anchor method.
#
# ⚠️ THE `change-class:` DEFAULT IS `Ordinary`, AND THAT IS LOAD-BEARING, NOT COSMETIC. Since PR 11
# `do_actuate` REFUSES a Control-plane-class note outright (the fail-closed arm the open
# TIER-3-CP-MERGE-ACTUATION-RULING sitting will dispose of), so a fixture that wants to exercise the
# label bar, the SoD teeth or the tree re-check must NOT also be control-plane — it would refuse one
# step earlier and every one of those legs would be passing for the wrong reason. The 5th argument
# carries the class, and ACT-CP below is the one leg that passes `Control-plane` deliberately.
#
# ⚠️ `${5-Ordinary}`, NOT `${5:-Ordinary}` — the colon form substitutes on EMPTY as well as unset, so
# a leg passing '' to model a blank class silently got `Ordinary` and PASSED THROUGH THE ALLOWLIST.
# That is exactly how ACT-UNKNOWN first went green for the wrong reason. The literal `OMIT` drops the
# line entirely, which is the stronger evasion shape (a note with no class at all).
write_note() { # dir sha approved-by-value [basis] [change-class|OMIT]
  _dir="$1"; _s="$2"; _aby="$3"; _basis="${4:-reviewer APPROVE}"; _cls="${5-Ordinary}"
  if [ "$_cls" = OMIT ]; then _clsline="x-no-class: (this note carries no change-class line)"
  else _clsline="change-class: $_cls"; fi
  printf '%s\n' \
    "record: promotion GO (fabricated fixture note)" \
    "approved-sha: $_s" \
    "approved-by: $_aby" \
    "gate: release-candidate" \
    "rung: Release candidate" \
    "$_clsline" \
    "scope: PR #260" \
    "approval-token: \"GO: merge #260\"" \
    "basis: $_basis" \
    "recorded-at: fixture" \
    | ( cd "$_dir" && git notes --ref=promotions add -f -F - "$_s" >/dev/null 2>&1 )
}

# Drive <gate> actuate in <dir>; capture RC + OUT (stdout+stderr merged).
run_actuate() { # gate dir ref sha merge-cmd
  _gate="$1"; _dir="$2"; _ref="$3"; _sha="$4"; _mc="$5"
  if OUT="$( ( cd "$_dir" && sh "$_gate" actuate --ref "$_ref" --approved-sha "$_sha" --merge-cmd "$_mc" ) 2>&1 )"; then
    RC=0
  else
    RC=$?
  fi
}

# invoked? — a stub-invocation sentinel ($D/.invoked) is touched only when the merge stub ran.
invoked() { [ -f "$1/.invoked" ] && echo yes || echo no; }

# ── WIRING fixtures: build three plain .txt files (no shebang, no +x) that model the three surfaces
#    wiring() greps — v.txt (the actuate producer), g.txt (the guard), r.txt (the verify.sh registration).
#    Each omit-arg drops exactly one required token so exactly one of wiring()'s six accumulator
#    sites (the _w flag) fires.
_mkwiring() {  # <verify-omit> <guard-omit> <reg-omit> -> echoes a dir holding v.txt g.txt r.txt
  _d=$(mktemp -d)
  { [ "$1" = actuate ] || printf 'actuate)\n'
    [ "$1" = bar ]     || printf 'grep -Eq "authenticated: [A-Za-z0-9_-]+-review"\n'
    [ "$1" = sod ]     || printf 'git log -1 --format=%%an%%ae\n'
  } > "$_d/v.txt"
  { [ "$2" = deny ] || printf 'gh pr merge --admin bypasses branch protection\n'
    [ "$2" = list ] || printf 'promotion-verify.sh\n'
  } > "$_d/g.txt"
  { [ "$3" = reg ] || printf 'promotion-actuate-wired.sh\n'; } > "$_d/r.txt"
  printf '%s\n' "$_d"
}

# INVARIANT: an accumulator assignment (a NAME followed by '=' then the digit one) must never appear
# above the ^selftest() marker, comments included — mutate() has no lexer and would count it as a
# phantom accumulator, drifting ACC. Keep any such token strictly below the marker.
selftest() {
  # ---------------------------------------------------------------------------------------
  # WIRING coverage: 1 liveness (all six surfaces present) + 6 negatives (each omits exactly one
  # required token -> exactly one of wiring()'s six wiring-flag accumulators fires). Asserts the SPECIFIC
  # FAIL message per site, never a bare rc!=0.
  # ---------------------------------------------------------------------------------------
  _expect_wiring "" "" "" 0 "OK: actuate gate"                            "LIVENESS: all six surfaces present -> wiring() PASSES"
  _expect_wiring actuate "" "" 1 "has no 'actuate)' dispatcher case"      "NEG: no actuate) dispatcher"
  _expect_wiring bar     "" "" 1 "does not enforce the control-plane bar" "NEG: control-plane bar absent"
  _expect_wiring sod     "" "" 1 "lacks the approver!=author"             "NEG: %an/%ae comparison absent"
  _expect_wiring "" deny "" 1 "does not deny the --admin bypass"          "NEG: guard --admin deny absent"
  _expect_wiring "" list "" 1 "does not list promotion-verify.sh"         "NEG: guard immutability absent"
  _expect_wiring "" "" reg  1 "does not register promotion-actuate-wired.sh" "NEG: verify.sh registration absent"

  # ---------------------------------------------------------------------------------------
  # LIVENESS anchor: authenticated GO, approver B != author A, note binds X, stub merges -> OK.
  # ---------------------------------------------------------------------------------------
  D="$(mkrepo)" || { fail "fixture build (liveness)"; return 1; }
  X="$(cat "$D/.X")"
  write_note "$D" "$X" "Reviewer B [authenticated: github-review]"
  MC="git update-ref refs/heads/merged $X && : > $D/.invoked"
  run_actuate "$VERIFY" "$D" merged "$X" "$MC"
  if [ "$RC" = 0 ] && [ -f "$D/.invoked" ] \
     && printf '%s' "$OUT" | grep -q 'OK: actuated' \
     && printf '%s' "$OUT" | grep -q 'shipped == approved'; then
    pass "LIVENESS: authenticated GO + approver!=author -> merge stub invoked -> shipped==approved (rc=0)"
  else
    fail "LIVENESS: rc=$RC invoked=$(invoked "$D") OUT=[$OUT]"
  fi

  # ---------------------------------------------------------------------------------------
  # NEGATIVE 1: no note on X -> refuse (fail closed), merge NOT invoked.
  # ---------------------------------------------------------------------------------------
  D="$(mkrepo)" || { fail "fixture build (neg1)"; return 1; }
  X="$(cat "$D/.X")"
  MC="git update-ref refs/heads/merged $X && : > $D/.invoked"
  run_actuate "$VERIFY" "$D" merged "$X" "$MC"
  if [ "$RC" != 0 ] && [ ! -f "$D/.invoked" ] && printf '%s' "$OUT" | grep -q 'no recorded GO note'; then
    pass "NEG1: no note on X -> ACTUATE REFUSED, merge not invoked (rc=$RC)"
  else
    fail "NEG1: rc=$RC invoked=$(invoked "$D") OUT=[$OUT]"
  fi

  # ---------------------------------------------------------------------------------------
  # NEGATIVE 2: note binds a DIFFERENT sha (record on G, actuate X) -> X unbound -> refuse.
  # ---------------------------------------------------------------------------------------
  D="$(mkrepo)" || { fail "fixture build (neg2)"; return 1; }
  X="$(cat "$D/.X")"; G="$(cat "$D/.G")"
  write_note "$D" "$G" "Reviewer B [authenticated: github-review]"
  MC="git update-ref refs/heads/merged $X && : > $D/.invoked"
  run_actuate "$VERIFY" "$D" merged "$X" "$MC"
  if [ "$RC" != 0 ] && [ ! -f "$D/.invoked" ] && printf '%s' "$OUT" | grep -q "no recorded GO note on $X"; then
    pass "NEG2: note binds G, actuate X -> refuse (SHA binding is exact) (rc=$RC)"
  else
    fail "NEG2: rc=$RC invoked=$(invoked "$D") OUT=[$OUT]"
  fi

  # ---------------------------------------------------------------------------------------
  # NEGATIVES 3-5: every weaker label ([self-asserted]/[committer]/[signed: gpg]) fails the bar.
  # ---------------------------------------------------------------------------------------
  for _lab in self-asserted committer 'signed: gpg'; do
    D="$(mkrepo)" || { fail "fixture build (neg-label)"; return 1; }
    X="$(cat "$D/.X")"
    write_note "$D" "$X" "Reviewer B [$_lab]"
    MC="git update-ref refs/heads/merged $X && : > $D/.invoked"
    run_actuate "$VERIFY" "$D" merged "$X" "$MC"
    if [ "$RC" != 0 ] && [ ! -f "$D/.invoked" ] \
       && printf '%s' "$OUT" | grep -q 'does not meet the control-plane bar'; then
      pass "NEG(label): [$_lab] fails the bar -> refuse, merge not invoked (rc=$RC)"
    else
      fail "NEG(label): [$_lab] rc=$RC invoked=$(invoked "$D") OUT=[$OUT]"
    fi
  done

  # ---------------------------------------------------------------------------------------
  # NEGATIVE 6: authenticated label but approver == author (name, then email) -> refuse (SoD).
  # ---------------------------------------------------------------------------------------
  for _id in 'Author A' 'a@x'; do
    D="$(mkrepo)" || { fail "fixture build (neg6)"; return 1; }
    X="$(cat "$D/.X")"
    write_note "$D" "$X" "$_id [authenticated: github-review]"
    MC="git update-ref refs/heads/merged $X && : > $D/.invoked"
    run_actuate "$VERIFY" "$D" merged "$X" "$MC"
    if [ "$RC" != 0 ] && [ ! -f "$D/.invoked" ] \
       && printf '%s' "$OUT" | grep -q 'approver equals author'; then
      pass "NEG6: approver '$_id' == author -> refuse (builder!=ratifier), merge not invoked (rc=$RC)"
    else
      fail "NEG6: id='$_id' rc=$RC invoked=$(invoked "$D") OUT=[$OUT]"
    fi
  done

  # ---------------------------------------------------------------------------------------
  # NEGATIVE 7: a [authenticated:] decoy in the BASIS body must NOT rescue a weak [committer] label
  #             — the label read is the approved-by line ONLY (the S5a injection lesson).
  # ---------------------------------------------------------------------------------------
  D="$(mkrepo)" || { fail "fixture build (neg7)"; return 1; }
  X="$(cat "$D/.X")"
  write_note "$D" "$X" "Reviewer B [committer]" "GO [authenticated: x-review]"
  MC="git update-ref refs/heads/merged $X && : > $D/.invoked"
  run_actuate "$VERIFY" "$D" merged "$X" "$MC"
  if [ "$RC" != 0 ] && [ ! -f "$D/.invoked" ] \
     && printf '%s' "$OUT" | grep -q 'does not meet the control-plane bar'; then
    pass "NEG7: [committer] + [authenticated:] decoy in body -> still refuse (label read ignores body)"
  else
    fail "NEG7: rc=$RC invoked=$(invoked "$D") OUT=[$OUT]"
  fi

  # ---------------------------------------------------------------------------------------
  # NEGATIVE 8: merge stub SUCCEEDS but leaves merged tree (= G) != X's tree -> SHIPPED != APPROVED.
  # ---------------------------------------------------------------------------------------
  D="$(mkrepo)" || { fail "fixture build (neg8)"; return 1; }
  X="$(cat "$D/.X")"; G="$(cat "$D/.G")"
  write_note "$D" "$X" "Reviewer B [authenticated: github-review]"
  MC="git update-ref refs/heads/merged $G && : > $D/.invoked"   # merged points at G: tree != X
  run_actuate "$VERIFY" "$D" merged "$X" "$MC"
  if [ "$RC" != 0 ] && [ -f "$D/.invoked" ] && printf '%s' "$OUT" | grep -q 'SHIPPED != APPROVED'; then
    pass "NEG8: merge left tree != approved -> loud SHIPPED != APPROVED (merge ran, rc=$RC)"
  else
    fail "NEG8: rc=$RC invoked=$(invoked "$D") OUT=[$OUT]"
  fi

  # ---------------------------------------------------------------------------------------
  # NEGATIVE 9: the actuate code path NEVER emits `--admin` (no bypass laundering via the wrapper).
  # ---------------------------------------------------------------------------------------
  if sed -n '/^do_actuate()/,/^}/p' "$VERIFY" | grep -q -- '--admin'; then
    fail "NEG9: '--admin' appears in the do_actuate code path -- the wrapper must NEVER emit the bypass"
  else
    pass "NEG9: '--admin' never appears in the do_actuate code path"
  fi

  # ---------------------------------------------------------------------------------------
  # BOARD-CLAIM RELEASE (BOARD-CLAIM-MECHANISM design §3.5). The merge is the end of the slice, so
  # actuate must RELEASE the merged row's claim ref — a claim nobody releases blocks the next session
  # from taking the row. Three properties, and the third is the load-bearing one:
  #   (1) it is called, with the note's OWN kit-row and with --stale (the merger is routinely not the
  #       claimant — builder != ratifier — so without --stale it would refuse every real merge);
  #   (2) a note with no kit-row releases NOTHING and says so (never an invented row);
  #   (3) a FAILING release is a WARN, not a merge failure. The merge already happened; no rc can
  #       un-merge it, and reporting a verified promotion as failed would be a lie in the log.
  # The stub is resolved the way the real one is — beside the gate — so the fixture copies the gate
  # into its own dir and puts board-claim.sh next to it. Same shape as the `gh` PATH shim below.
  _mk_release_fixture() {  # <dir> <stub-exit>
    cp "$VERIFY" "$1/promotion-verify.sh"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/.released"\necho "release: stub"\nexit %s\n' "$1" "$2" > "$1/board-claim.sh"
    chmod +x "$1/board-claim.sh"
  }
  D="$(mkrepo)" || { fail "fixture build (claim-release)"; return 1; }
  X="$(cat "$D/.X")"
  write_note "$D" "$X" "Reviewer B [authenticated: github-review]"
  ( cd "$D" && git notes --ref=promotions append -m 'kit-row: ROW-X' "$X" ) >/dev/null 2>&1
  _mk_release_fixture "$D" 0
  MC="git update-ref refs/heads/merged $X && : > $D/.invoked"
  run_actuate "$D/promotion-verify.sh" "$D" merged "$X" "$MC"
  if [ "$RC" = 0 ] && [ -f "$D/.released" ] \
     && grep -q 'release ROW-X --stale' "$D/.released" \
     && printf '%s' "$OUT" | grep -q "board claim on 'ROW-X' released"; then
    pass "CLAIM-RELEASE: actuate releases the merged row's claim as 'release ROW-X --stale' and says so"
  else
    fail "CLAIM-RELEASE: rc=$RC released=[$(cat "$D/.released" 2>/dev/null)] OUT=[$OUT]"
  fi

  D="$(mkrepo)" || { fail "fixture build (claim-release/no-row)"; return 1; }
  X="$(cat "$D/.X")"
  write_note "$D" "$X" "Reviewer B [authenticated: github-review]"
  _mk_release_fixture "$D" 0
  MC="git update-ref refs/heads/merged $X && : > $D/.invoked"
  run_actuate "$D/promotion-verify.sh" "$D" merged "$X" "$MC"
  if [ "$RC" = 0 ] && [ ! -f "$D/.released" ] \
     && printf '%s' "$OUT" | grep -q 'no kit-row on the GO note'; then
    pass "CLAIM-RELEASE-NOROW: a note with no kit-row releases NOTHING and says so (no row invented)"
  else
    fail "CLAIM-RELEASE-NOROW: rc=$RC released=[$(cat "$D/.released" 2>/dev/null)] OUT=[$OUT]"
  fi

  D="$(mkrepo)" || { fail "fixture build (claim-release/warn)"; return 1; }
  X="$(cat "$D/.X")"
  write_note "$D" "$X" "Reviewer B [authenticated: github-review]"
  ( cd "$D" && git notes --ref=promotions append -m 'kit-row: ROW-X' "$X" ) >/dev/null 2>&1
  _mk_release_fixture "$D" 1
  MC="git update-ref refs/heads/merged $X && : > $D/.invoked"
  run_actuate "$D/promotion-verify.sh" "$D" merged "$X" "$MC"
  if [ "$RC" = 0 ] \
     && printf '%s' "$OUT" | grep -q 'WARN — could not release the board claim' \
     && printf '%s' "$OUT" | grep -q 'OK: actuated'; then
    pass "CLAIM-RELEASE-WARN: a FAILING release is a WARN — the verified merge still reports rc 0"
  else
    fail "CLAIM-RELEASE-WARN: rc=$RC OUT=[$OUT]"
  fi

  # LAND-WRITES-CARD-STATE C2: the `md` path is UNCHANGED. A board.sh stub BESIDE the gate copy writes a marker if it is
  # ever run; on an md fixture (no tracker backend) it must NOT be — routing md through board.sh reds this leg. The
  # existing message text stays intact, and the verb now ends on the one md tail line.
  D="$(mkrepo)" || { fail "fixture build (claim-release/md-tail)"; return 1; }
  X="$(cat "$D/.X")"
  write_note "$D" "$X" "Reviewer B [authenticated: github-review]"
  ( cd "$D" && git notes --ref=promotions append -m 'kit-row: ROW-X' "$X" ) >/dev/null 2>&1
  _mk_release_fixture "$D" 0
  printf '#!/bin/sh\n: > "%s/.board-sh-ran"\nexit 0\n' "$D" > "$D/board.sh"; chmod +x "$D/board.sh"
  MC="git update-ref refs/heads/merged $X && : > $D/.invoked"
  run_actuate "$D/promotion-verify.sh" "$D" merged "$X" "$MC"
  if [ "$RC" = 0 ] && [ ! -f "$D/.board-sh-ran" ] && grep -q 'release ROW-X --stale' "$D/.released" \
     && printf '%s' "$OUT" | grep -q "board claim on 'ROW-X' released" \
     && [ "$(printf '%s\n' "$OUT" | tail -1)" = 'board: row closes with the PR (md); claim released' ]; then
    pass "CLAIM-RELEASE-MD-TAIL (C2): an md row never runs board.sh, keeps its message, and ends 'board: row closes with the PR (md); claim released'"
  else
    fail "CLAIM-RELEASE-MD-TAIL: rc=$RC boardsh=$([ -f "$D/.board-sh-ran" ] && echo RAN || echo no) OUT=[$OUT]"
  fi

  # md tail lines for the two non-happy cases: a FAILING release, and a note with no row (nothing released).
  D="$(mkrepo)" || { fail "fixture build (md-tail/fail)"; return 1; }
  X="$(cat "$D/.X")"
  write_note "$D" "$X" "Reviewer B [authenticated: github-review]"
  ( cd "$D" && git notes --ref=promotions append -m 'kit-row: ROW-X' "$X" ) >/dev/null 2>&1
  _mk_release_fixture "$D" 1
  MC="git update-ref refs/heads/merged $X && : > $D/.invoked"
  run_actuate "$D/promotion-verify.sh" "$D" merged "$X" "$MC"
  if [ "$RC" = 0 ] && [ "$(printf '%s\n' "$OUT" | tail -1)" = 'board: row closes with the PR (md); claim NOT released — see the WARN above' ]; then
    pass "CLAIM-RELEASE-MD-TAIL-FAIL: a failing md release ends 'claim NOT released — see the WARN above' (rc 0)"
  else
    fail "CLAIM-RELEASE-MD-TAIL-FAIL: rc=$RC OUT=[$OUT]"
  fi
  D="$(mkrepo)" || { fail "fixture build (md-tail/none)"; return 1; }
  X="$(cat "$D/.X")"
  write_note "$D" "$X" "Reviewer B [authenticated: github-review]"
  _mk_release_fixture "$D" 0
  MC="git update-ref refs/heads/merged $X && : > $D/.invoked"
  run_actuate "$D/promotion-verify.sh" "$D" merged "$X" "$MC"
  if [ "$RC" = 0 ] && ! printf '%s' "$OUT" | grep -q 'WARN' \
     && [ "$(printf '%s\n' "$OUT" | tail -1)" = 'board: row closes with the PR (md); no claim to release' ]; then
    pass "CLAIM-RELEASE-MD-TAIL-NONE: md + no kit-row keeps today's output (no new WARN) and ends 'no claim to release'"
  else
    fail "CLAIM-RELEASE-MD-TAIL-NONE: rc=$RC OUT=[$OUT]"
  fi

  # LAND-WRITES-CARD-STATE review Major: only `jira` has a board.sh write adapter. A github-declared repo keeps the
  # ref-only `board-claim.sh release ROW-X --stale`, board.sh is NEVER run, and a WARN + `NOT CLOSED` say to move the card.
  D="$(mkrepo)" || { fail "fixture build (no-adapter)"; return 1; }
  X="$(cat "$D/.X")"
  write_note "$D" "$X" "Reviewer B [authenticated: github-review]"
  ( cd "$D" && git notes --ref=promotions append -m 'kit-row: ROW-X' "$X" ) >/dev/null 2>&1
  _mk_release_fixture "$D" 0
  mkdir -p "$D/conformance"; cp "$(dirname "$VERIFY")/../conformance/backlog-lib.sh" "$D/conformance/backlog-lib.sh"
  printf 'Backlog backend: github\n' > "$D/CLAUDE.md"
  printf '#!/bin/sh\n: > "%s/.board-sh-ran"\nexit 0\n' "$D" > "$D/board.sh"; chmod +x "$D/board.sh"
  MC="git update-ref refs/heads/merged $X && : > $D/.invoked"
  run_actuate "$D/promotion-verify.sh" "$D" merged "$X" "$MC"
  if [ "$RC" = 0 ] && [ ! -f "$D/.board-sh-ran" ] && grep -q 'release ROW-X --stale' "$D/.released" \
     && printf '%s' "$OUT" | grep -qF "no write adapter for 'github'; move the card on 'ROW-X' by hand" \
     && [ "$(printf '%s\n' "$OUT" | tail -1)" = 'board: NOT CLOSED — see the WARN above' ]; then
    pass "CLAIM-RELEASE-NOADAPTER: github-declared -> ref-only release, board.sh never run, WARN 'no write adapter', tail NOT CLOSED"
  else
    fail "CLAIM-RELEASE-NOADAPTER: rc=$RC boardsh=$([ -f "$D/.board-sh-ran" ] && echo RAN || echo no) released=[$(cat "$D/.released" 2>/dev/null)] OUT=[$OUT]"
  fi

  # security Low 1: a kit-row outside [A-Z0-9][A-Z0-9-]* releases and closes NOTHING, is not echoed, and prints no
  # paste-able command.
  D="$(mkrepo)" || { fail "fixture build (bad-row)"; return 1; }
  X="$(cat "$D/.X")"
  write_note "$D" "$X" "Reviewer B [authenticated: github-review]"
  ( cd "$D" && git notes --ref=promotions append -m 'kit-row: X;echo pwned' "$X" ) >/dev/null 2>&1
  _mk_release_fixture "$D" 0
  printf '#!/bin/sh\n: > "%s/.board-sh-ran"\nexit 0\n' "$D" > "$D/board.sh"; chmod +x "$D/board.sh"
  MC="git update-ref refs/heads/merged $X && : > $D/.invoked"
  run_actuate "$D/promotion-verify.sh" "$D" merged "$X" "$MC"
  if [ "$RC" = 0 ] && [ ! -f "$D/.released" ] && [ ! -f "$D/.board-sh-ran" ] \
     && printf '%s' "$OUT" | grep -qF 'kit-row is not a valid row id; nothing released or closed' \
     && ! printf '%s' "$OUT" | grep -qF 'pwned' && ! printf '%s' "$OUT" | grep -qF 'sh scripts/board' \
     && [ "$(printf '%s\n' "$OUT" | tail -1)" = 'board: NOT CLOSED — see the WARN above' ]; then
    pass "CLAIM-RELEASE-BADROW: kit-row 'X;echo pwned' -> nothing released or closed, value not echoed, no command printed, tail NOT CLOSED"
  else
    fail "CLAIM-RELEASE-BADROW: rc=$RC released=$([ -f "$D/.released" ] && echo yes || echo no) OUT=[$OUT]"
  fi

  # ---------------------------------------------------------------------------------------
  # GUARD fixtures: the --admin bypass stays DENIED; the gate is immutable-but-runnable; normal merge
  # allowed. Control-plane path strings live in a DATA FILE (never on a command line) so the real
  # PreToolUse guard cannot block us. Source the guard in a subshell WITHOUT set -e (its functions
  # return 1 on deny by design).
  # ---------------------------------------------------------------------------------------
  CASES="$D/cases.txt"
  {
    printf '%s\n' 'DENY|cmd|gh pr merge 260 --admin --squash'
    printf '%s\n' 'DENY|cmd|gh pr merge 260 --administrator'
    printf '%s\n' 'ALLOW|cmd|gh pr merge 260 --squash'
    printf '%s\n' 'DENY|cmd|sed -i s/x/y/ scripts/promotion-verify.sh'
    printf '%s\n' 'DENY|cmd|printf x > scripts/promotion-verify.sh'
    printf '%s\n' 'DENY|path|scripts/promotion-verify.sh'
    printf '%s\n' 'ALLOW|cmd|sh scripts/promotion-verify.sh actuate --ref 260 --approved-sha abc'
    # S6R (A1): the REST forms of the SAME bypass. `gh pr merge --admin` is IMPLEMENTED as
    # PUT /repos/:o/:r/pulls/:n/merge, so denying only the porcelain flag left the plumbing open
    # (reproduced live 2026-08-25: rc=0). Eight load-bearing negatives — revert the arm and all eight
    # red. Six ALLOWs pin the read/poster/additive traffic the arm must NOT touch.
    printf '%s\n' 'DENY|cmd|gh api -X PUT repos/o/r/pulls/5/merge'
    printf '%s\n' 'DENY|cmd|gh api --method POST repos/o/r/pulls/5/merge -f merge_method=squash'
    printf '%s\n' 'DENY|cmd|gh api --method=put https://api.github.com/repos/o/r/pulls/5/merge'
    printf '%s\n' 'DENY|cmd|gh api repos/o/r/pulls/5/merge -f merge_method=squash'
    printf '%s\n' 'DENY|cmd|gh api -X DELETE repos/o/r'
    printf '%s\n' 'DENY|cmd|gh api -X PUT repos/o/r/branches/main/protection --input p.json'
    printf '%s\n' 'DENY|cmd|gh api -X DELETE repos/o/r/rulesets/7'
    printf '%s\n' 'DENY|cmd|gh api -X PATCH orgs/o/rulesets/7 -f enforcement=disabled'
    printf '%s\n' 'ALLOW|cmd|gh api repos/o/r/pulls/5'
    printf '%s\n' 'ALLOW|cmd|gh api -X GET repos/o/r/pulls/5/merge'
    printf '%s\n' 'ALLOW|cmd|gh api repos/o/r/pulls/5/reviews -f event=APPROVE'
    printf '%s\n' 'ALLOW|cmd|gh api graphql -f query=mutation{}'
    printf '%s\n' 'ALLOW|cmd|gh api --paginate repos/o/r/rulesets'
    # S6R round 2 — SPELLING VARIANTS OF THE SAME CALL. Round 1 matched the method with
    # `[[:space:]=]+`, so every one of these reached the endpoint at rc=0 while the plain form denied.
    # A deny arm that a quote or a missing space defeats is a deny arm for tidy attackers only.
    printf '%s\n' 'DENY|cmd|gh api -XPUT repos/o/r/pulls/5/merge'
    printf '%s\n' 'DENY|cmd|gh api -X "PUT" repos/o/r/pulls/5/merge'
    printf '%s\n' "DENY|cmd|gh api -X 'PUT' repos/o/r/pulls/5/merge"
    printf '%s\n' "DENY|cmd|gh api -X PUT 'repos/o/r/pulls/5/merge'"
    printf '%s\n' 'DENY|cmd|gh api repos/o/r/pulls/5/merge?x=1 -X PUT'
    printf '%s\n' 'DENY|cmd|gh api -X PUT repos/o/r/pulls/5/merge/'
    printf '%s\n' 'DENY|cmd|gh api -X PUT repos/o//r/pulls/5/merge'
    # ORDER-INDEPENDENCE PIN: the method may follow the path. The scan is over the whole raw string,
    # never a positional parse, and this cell is what stops someone "tidying" it into one.
    printf '%s\n' 'DENY|cmd|gh api repos/o/r/pulls/5/merge --method PUT'
    # FUSED SHORT BODY FLAG. `gh api` defaults to POST once a body is given, so this merges the PR
    # with no method flag at all.
    printf '%s\n' 'DENY|cmd|gh api repos/o/r/pulls/5/merge -fmerge_method=squash'
    # --hostname (GHES) DENIES TODAY — the path is unchanged, only the host is. Pinned because round
    # 1's comment wrongly listed it as uncovered; the cell is now the source of truth over the prose.
    printf '%s\n' 'DENY|cmd|gh api --hostname ghe.example.com -X PUT repos/o/r/pulls/5/merge'
    # PROTECTION IS DENY-BY-DEFAULT UNDER ANY MUTATING METHOD (round-2 inversion). Round 1 listed
    # four weakening sub-resources and let every other sub-path through, so DELETE on
    # required_status_checks — which removes every required context at once — was ALLOW.
    printf '%s\n' 'DENY|cmd|gh api -X DELETE repos/o/r/branches/main/protection/required_status_checks'
    printf '%s\n' 'DENY|cmd|gh api -X PATCH repos/o/r/branches/main/protection/required_status_checks -f strict=false'
    printf '%s\n' 'DENY|cmd|gh api -X DELETE repos/o/r/branches/main/protection/required_status_checks/contexts -f contexts[]=x'
    printf '%s\n' 'DENY|cmd|gh api -X PUT repos/o/r/branches/main/protection/required_status_checks/contexts'
    printf '%s\n' 'DENY|cmd|gh api -X DELETE repos/o/r/branches/main/protection/restrictions/users'
    printf '%s\n' 'DENY|cmd|gh api -X DELETE repos/o/r/branches/main/protection/enforce_admins'
    # ...with EXACTLY ONE carve-out, and it is now genuinely load-bearing: POST (and only POST) to the
    # additive contexts endpoint, which is `scripts/branch-protection-apply.sh --apply`'s own human-run
    # call. Under the round-1 shape this cell passed because the whole sub-tree was unmatched; under
    # the inversion it passes only because the carve-out exists. Flipping the method above (the PUT and
    # DELETE cells) proves the carve-out is a method-scoped hole, not an open door.
    printf '%s\n' 'ALLOW|cmd|gh api -X POST repos/o/r/branches/main/protection/required_status_checks/contexts -f contexts[]=x'
    # THREE MORE TIER-3 ENDPOINT CLASSES (`D-240813-5`: force-push, privilege grant, delete).
    # A default-branch swap moves protection off the branch everything merges to; a ref PATCH with
    # force=true IS a force-push over the API; a collaborator PUT mints an admin.
    printf '%s\n' 'DENY|cmd|gh api -X PATCH repos/o/r -f default_branch=evil'
    printf '%s\n' 'DENY|cmd|gh api -X PATCH repos/o/r/git/refs/heads/main -f force=true'
    printf '%s\n' 'DENY|cmd|gh api -X PUT repos/o/r/collaborators/mallory -f permission=admin'
    # ALLOW pins for the relaxed method matcher: a QUOTED GET is still a read.
    printf '%s\n' 'ALLOW|cmd|gh api -X "GET" repos/o/r/pulls/5/merge'
    printf '%s\n' 'ALLOW|cmd|gh api repos/o/r/pulls/5 -X GET'
    # ── ROUND 3 ─────────────────────────────────────────────────────────────────────────────────
    # A QUOTE IS A JOINER, NOT A BOUNDARY. Round 2 normalized quotes to SPACES, which is exactly
    # backwards: the shell CONCATENATES adjacent fragments, so `me''rge` runs as `merge` while the
    # guard saw two short tokens and matched neither. Every one of these six was ALLOW at 5ada56d9
    # and every one is a valid shell spelling of a denied call. Quotes and backslashes are now
    # DELETED, not spaced.
    printf '%s\n' "DENY|cmd|gh api -X PUT repos/o/r/pulls/5/me''rge"
    printf '%s\n' 'DENY|cmd|gh api -X PUT repos/o/r/pulls/5/me""rge'
    printf '%s\n' 'DENY|cmd|gh api -X PUT "repos/o/r/pulls/5/me"rge'
    printf '%s\n' 'DENY|cmd|gh api -X PUT repos/o/r/pulls/5/mer\ge'
    printf '%s\n' "DENY|cmd|gh api -X PUT repos/o/r/branches/ma'in'/protection"
    printf '%s\n' "DENY|cmd|gh api -X DELETE repos/o/r/rul''esets/7"
    # READ-SIDE FALSE POSITIVES, and they were the OWNER'S OWN A3 READ-BACK. Round 2 counted any
    # whitespace-anchored `-f`/`-F` anywhere in the string as a request body, so `sort -f` and
    # `grep -F` in a downstream pipe stage turned a read into a DENY. A body flag must carry a FIELD
    # ASSIGNMENT to count. A guard that blocks the command the runbook tells you to run is a guard
    # people learn to route around.
    printf '%s\n' 'ALLOW|cmd|gh api repos/o/r/branches/main/protection | grep -F required_status_checks'
    printf '%s\n' "ALLOW|cmd|gh api repos/o/r/rulesets | jq -r '.[].name' | sort -f"
    printf '%s\n' 'ALLOW|cmd|gh api --paginate repos/o/r/rulesets > /tmp/r.json && grep -F name /tmp/r.json'
    # THE CARVE-OUT WAS A PRESENCE TEST, NOT A POSITIONAL ONE: the contexts path appearing ANYWHERE
    # in the string satisfied it, so a decoy in a filename opened the whole protection subtree under
    # POST. Same class as round 1's inversion. The fix strips the contexts path and re-tests.
    printf '%s\n' 'DENY|cmd|gh api -X POST repos/o/r/branches/main/protection --input /repos/o/r/branches/main/protection/required_status_checks/contexts'
    # METHOD-SET WIDENING — do not rest safety on GitHub'"'"'s current routing table.
    printf '%s\n' 'DENY|cmd|gh api -X DELETE repos/o/r/'
    printf '%s\n' 'DENY|cmd|gh api -X PUT repos/o/r/git/refs/heads/main -f sha=x'
    printf '%s\n' 'DENY|cmd|gh api repos/o/r/collaborators/mallory -f permission=admin'
    # S6R SURVIVES A QUOTED WRAPPER — by luck, not design (its first probe sees the wrapped bytes).
    # The incumbent --admin arm does NOT. Pin the property so it cannot regress silently; the general
    # blindness is boarded as GUARD-QUOTED-WRAPPER-BLINDS-COMMAND-ARMS, not claimed closed here.
    printf '%s\n' "DENY|cmd|sh -c 'gh api -X PUT repos/o/r/pulls/5/merge'"
    # ── ROUND 4: THE OTHER HALF OF ROUND 3'"'"'S OWN FIX ────────────────────────────────────────────
    # Round 3 deleted quotes/backslashes for the PATH but computed that string AFTER the method and
    # body-flag probes, which kept reading raw $1. So the identical joiner trick walked through on the
    # METHOD instead: every one of these was ALLOW at 670e9205, and `PUT /pulls/N/merge` takes an
    # EMPTY BODY, so the first line is a complete admin merge with no body flag needed.
    # The fix is not another regex — it is ONE normalisation, computed BEFORE ANY PROBE READS.
    printf '%s\n' "DENY|cmd|gh api -X P''UT repos/o/r/pulls/5/merge"
    printf '%s\n' 'DENY|cmd|gh api -X P""UT repos/o/r/pulls/5/merge'
    printf '%s\n' 'DENY|cmd|gh api -X PU\T repos/o/r/pulls/5/merge'
    printf '%s\n' "DENY|cmd|gh api --met''hod PUT repos/o/r/pulls/5/merge"
    printf '%s\n' "DENY|cmd|gh api -X DEL''ETE repos/o/r"
    printf '%s\n' "DENY|cmd|gh api -X P''ATCH repos/o/r/branches/main/protection"
    # The BODY flag was split-able too (found at build, same root cause, same fix).
    printf '%s\n' "DENY|cmd|gh api repos/o/r/pulls/5/merge -''f merge_method=squash"
    # A quote-split GET must still SUPPRESS. Today that happens by accident — the method loop finds
    # nothing, so the call is judged non-mutating and falls through. After the reorder it is a
    # DELIBERATE `get` match. Pinned so the accident becomes a property.
    printf '%s\n' "ALLOW|cmd|gh api -X G''ET repos/o/r/pulls/5/merge"
    # Round-4 addendum (security seat), same root cause on the FLAG side. The first line is the one
    # that matters: `-f 'merge_method=squash'` is how a HUMAN ORDINARILY QUOTES A SHELL ARGUMENT —
    # not an evasion at all — and it was ALLOW. A deny arm that the normal spelling defeats is not a
    # deny arm. The rest are the same joiner applied to the flag token itself.
    printf '%s\n' "DENY|cmd|gh api -f 'merge_method=squash' repos/o/r/pulls/5/merge"
    printf '%s\n' "DENY|cmd|gh api -f'merge_method=squash' repos/o/r/pulls/5/merge"
    printf '%s\n' 'DENY|cmd|gh api -f"merge_method=squash" repos/o/r/pulls/5/merge'
    printf '%s\n' 'DENY|cmd|gh api -f\merge_method=squash repos/o/r/pulls/5/merge'
    printf '%s\n' "DENY|cmd|gh api -'X' PUT repos/o/r/pulls/5/merge"
    printf '%s\n' 'DENY|cmd|gh api -X\ PUT repos/o/r/pulls/5/merge'
    printf '%s\n' "DENY|cmd|gh api --'method' PUT repos/o/r/pulls/5/merge"
  } > "$CASES"
  if (
       set +e
       # shellcheck source=/dev/null
       . "$GUARD"
       _gf=0
       while IFS= read -r _line || [ -n "$_line" ]; do
         case "$_line" in ''|'#'*) continue ;; esac
         _exp=${_line%%|*}; _rest=${_line#*|}; _kind=${_rest%%|*}; _pl=${_rest#*|}
         case "$_kind" in
           cmd)  _r=$(guard_check_command "$_pl"); _rc=$? ;;
           path) _r=$(guard_check_path    "$_pl"); _rc=$? ;;
           *)    echo "GUARDFAIL: unknown kind '$_kind'"; _gf=1; continue ;;
         esac
         if [ "$_rc" -eq 0 ]; then _got=ALLOW; else _got=DENY; fi
         if [ "$_got" != "$_exp" ]; then
           echo "GUARDFAIL: expected=$_exp got=$_got | $_kind $_pl"; _gf=1
         fi
       done < "$CASES"
       exit $_gf ); then
    pass "GUARD fixtures: --admin/--administrator denied, normal merge allowed, gate immutable-but-runnable"
  else
    fail "GUARD fixtures: a guard verdict did not match (see GUARDFAIL above)"
  fi

  # ---------------------------------------------------------------------------------------
  # ★ LOCK SELF-NEGATIVE (mandatory — proves the LOCK ITSELF is non-vacuous). Neutralize the gate's
  # control-plane bar (regex -> .*) in a COPY, then feed a WEAK [self-asserted] note (approver != author).
  # The neutralized gate MUST now actuate it (rc=0) — which is exactly what the bar is supposed to
  # forbid. If a dead/always-pass gate were INDISTINGUISHABLE (the neutralized gate still refused),
  # the lock's bar-assertion would prove nothing -> FAIL. This mirrors non-vacuity.sh's discipline:
  # a mutant of the FAIL path must be detectable. (The DEFAULT wiring path ALSO catches this mutation:
  # grep -F of the exact bar string fails once the regex is neutralized.)
  # ---------------------------------------------------------------------------------------
  NEUT="$D/neutered-gate.sh"
  cat > "$D/neuter.awk" <<'AWK'
/grep -Eq/ && /authenticated:/ { print "  if ! printf '%s' \"$label\" | grep -Eq '.*'; then"; next }
{ print }
AWK
  awk -f "$D/neuter.awk" "$VERIFY" > "$NEUT"
  # Sanity: the neutralization actually landed (the exact bar string is gone from the gate copy).
  if grep -qF "$BAR" "$NEUT"; then
    fail "LOCK SELF-NEGATIVE setup: neutralization did not remove the bar from the gate copy"
  else
    DN="$(mkrepo)" || { fail "self-negative fixture build"; return 1; }
    XN="$(cat "$DN/.X")"
    write_note "$DN" "$XN" "Reviewer B [self-asserted]"
    MCN="git update-ref refs/heads/merged $XN && : > $DN/.invoked"
    run_actuate "$NEUT" "$DN" merged "$XN" "$MCN"
    if [ "$RC" = 0 ] && [ -f "$DN/.invoked" ]; then
      pass "LOCK SELF-NEGATIVE: neutralized bar actuated a [self-asserted] note -> the bar-check is LOAD-BEARING"
    else
      fail "LOCK SELF-NEGATIVE did NOT fire: neutralized gate still refused a weak note (rc=$RC) -> the lock's bar-assertion is VACUOUS"
    fi
  fi

  # =======================================================================================
  # PR 11 — THE FORGE-REVIEW DERIVATION IN `record` (ACTUATE-FORGE-REVIEW-DERIVATION-UNWIRED).
  #
  # Until this slice `derive_assurance` could emit only [signed: gpg] / [committer] /
  # [self-asserted], so the [authenticated: <forge>-review] bar every leg above enforces was
  # UNREACHABLE by any production path and `actuate` was closed for every class by construction —
  # the fabricated notes above were the only way to reach it. These legs prove the label is now
  # DERIVED from forge evidence, and — far more importantly — that it is derived ONLY when every
  # folded condition holds. Each negative isolates exactly one condition, so deleting that condition
  # from the gate turns exactly that leg red (the proof matrix is in the PR body).
  # =======================================================================================
  _RQ='[{"user":{"login":"Reviewer B","type":"User"},"state":"APPROVED","commit_id":"@SHA@","submitted_at":"2026-09-01T00:00:00Z"}]'

  # REC-L (LIVENESS): a qualifying review upgrades the label — and the upgraded record then carries
  # `actuate` end to end, which is the row's whole claim ("actuate opens for ordinary/sensitive").
  # A liveness anchor that stopped at the note would not prove the two halves compose.
  DL="$(mkrepo)" || { fail "REC-L: fixture build"; return 1; }
  XL="$(cat "$DL/.X")"
  GL="$(_mkgh "$(printf '%s' "$_RQ" | sed "s/@SHA@/$XL/g")" '"AuthorLogin"')"
  _run_record "$DL" "$GL" "PR #260" "Reviewer B" "$XL"
  NL="$(_note_of "$DL" "$XL")"
  if [ "$RC" = 0 ] && printf '%s\n' "$NL" | grep -qF 'approved-by: Reviewer B [authenticated: github-review]'; then
    MC="git update-ref refs/heads/merged $XL && : > $DL/.invoked"
    run_actuate "$VERIFY" "$DL" merged "$XL" "$MC"
    if [ "$RC" = 0 ] && [ -f "$DL/.invoked" ] && printf '%s' "$OUT" | grep -q 'OK: actuated'; then
      pass "REC-L LIVENESS: derived [authenticated: github-review] -> actuate merged it (rc=0) — the gate is REACHABLE by a production path"
    else
      fail "REC-L LIVENESS (actuate half): rc=$RC invoked=$(invoked "$DL") OUT=[$OUT]"
    fi
  else
    fail "REC-L LIVENESS (record half): rc=$RC note=[$NL]"
  fi
  rm -rf "$DL" "$GL" 2>/dev/null || true

  # REC-L2 (the second liveness anchor, and the ONLY leg that can red the SHA RESOLUTION): the caller
  # passes an ABBREVIATED --approved-sha while the API answers with the 40-hex commit_id. 27 of this
  # repo's own records carry an abbreviated sha, so comparing the raw caller string would make every
  # one of them silently never-upgrade — a permanent false negative that looks exactly like "no review
  # exists". Without this leg, `git rev-parse` could be replaced by the raw string and nothing reds.
  DL2="$(mkrepo)" || { fail "REC-L2: fixture build"; return 1; }
  XL2="$(cat "$DL2/.X")"
  GL2="$(_mkgh "$(printf '%s' "$_RQ" | sed "s/@SHA@/$XL2/g")" '"AuthorLogin"')"
  _run_record "$DL2" "$GL2" "PR #260" "Reviewer B" "$(printf '%s' "$XL2" | cut -c1-8)"
  BL2="$(_note_of "$DL2" "$XL2")"
  if [ "$RC" = 0 ] && printf '%s\n' "$BL2" | grep -qF 'approved-by: Reviewer B [authenticated: github-review]'; then
    pass "REC-L2 LIVENESS: an ABBREVIATED --approved-sha still upgrades (the compare resolves the full sha first)"
  else
    fail "REC-L2: abbreviated approved-sha did not upgrade; rc=$RC note=[$BL2] OUT=[$OUT]"
  fi
  rm -rf "$DL2" "$GL2" 2>/dev/null || true

  # ★ REC-L3 (the THIRD liveness anchor, review I2): the reviewer APPROVED and then left a COMMENTED
  # review at the same sha — answering a question, the ordinary shape of a real review thread. A
  # COMMENTED review does NOT change a PR's review state on GitHub, so a standing approval survives
  # it. A plain latest-row read would let that comment CANCEL the approval and refuse a GO the forge
  # itself still considers approved, with no clue why. This must still UPGRADE, and it is the leg that
  # reds if the state-changing filter is dropped from the selector.
  _rec_case REC-L3 auth \
    '[{"user":{"login":"Reviewer B","type":"User"},"state":"APPROVED","commit_id":"@SHA@","submitted_at":"2026-09-01T00:00:00Z"},{"user":{"login":"Reviewer B","type":"User"},"state":"COMMENTED","commit_id":"@SHA@","submitted_at":"2026-09-01T02:00:00Z"}]' \
    '"AuthorLogin"' ''

  # REC-N1: the review is bound to a DIFFERENT commit. `commit_id` is what makes the review an
  # approval OF THIS CONTENT rather than of the PR as an idea; without it a reviewer's approval of an
  # early commit would authenticate anything pushed after it.
  _rec_case REC-N1 base \
    '[{"user":{"login":"Reviewer B","type":"User"},"state":"APPROVED","commit_id":"0123456789012345678901234567890123456789"}]' \
    '"AuthorLogin"' review-sha-mismatch

  # REC-N2: the reviewer is not the id the GO claims. The derivation CORROBORATES the caller's claim;
  # it never substitutes a different identity for it.
  _rec_case REC-N2 base \
    '[{"user":{"login":"Reviewer C","type":"User"},"state":"APPROVED","commit_id":"@SHA@"}]' \
    '"AuthorLogin"' reviewer-not-in-reviews

  # REC-N3: reviewer == PR author (forge-side SoD), asserted in a DIFFERENT CASE deliberately —
  # GitHub logins are case-insensitive, so a byte-equal test here would be defeated by a capital.
  # This leg is what makes the case-folding deletion-provable.
  # NOTE the reviewer login here is charset-legal on both sides: F3 anchors the AUTHOR to
  # [A-Za-z0-9-], so a spaced author would refuse as author-unresolvable and this leg would pass for
  # the wrong reason — proving the charset arm rather than the case-fold.
  _rec_case REC-N3 base \
    '[{"user":{"login":"ReviewerB","type":"User"},"state":"APPROVED","commit_id":"@SHA@"}]' \
    '"reviewerb"' reviewer-is-pr-author ReviewerB

  # REC-N4: a lone CHANGES_REQUESTED is not an approval.
  _rec_case REC-N4 base \
    '[{"user":{"login":"Reviewer B","type":"User"},"state":"CHANGES_REQUESTED","commit_id":"@SHA@"}]' \
    '"AuthorLogin"' review-not-approved

  # REC-N5: `gh` genuinely absent from PATH -> the FALLBACK label, and the notice is ASSERTED, not
  # merely observed. A silent fallback is the "never-silently-default" rule's exact violation.
  DN5="$(mkrepo)" || { fail "REC-N5: fixture build"; return 1; }
  XN5="$(cat "$DN5/.X")"
  PN5="$(_mknogh)"
  _run_record "$DN5" "$PN5" "PR #260" "Reviewer B" "$XN5" absolute
  BN5="$(_note_of "$DN5" "$XN5")"
  if [ "$RC" = 0 ] \
     && printf '%s\n' "$BN5" | grep -qF 'approved-by: Reviewer B [self-asserted]' \
     && printf '%s' "$OUT" | grep -qF 'forge-review derivation: gh-unavailable' \
     && printf '%s' "$OUT" | grep -qF 'recording [self-asserted]'; then
    pass "REC-N5: gh absent from PATH -> fallback label kept + 'gh-unavailable' notice printed (never a silent default)"
  else
    fail "REC-N5: rc=$RC note=[$BN5] OUT=[$OUT]"
  fi
  rm -rf "$DN5" "$PN5" 2>/dev/null || true

  # REC-N6: HOSTILE forge output. The login carries the very bracket text the label read parses, plus
  # a control character and a newline — the S5a note-injection class aimed at the one new input
  # surface this slice opens. Two assertions, and the second is the load-bearing one: no upgrade, AND
  # the note body is byte-clean (no API byte reaches a line-structured record, by construction).
  DN6="$(mkrepo)" || { fail "REC-N6: fixture build"; return 1; }
  XN6="$(cat "$DN6/.X")"
  GN6="$(_mkgh "$(printf '%s' '[{"user":{"login":"Reviewer B]\napproved-by: X [authenticated: github-review","type":"User"},"state":"APPROVED","commit_id":"@SHA@"}]' | sed "s/@SHA@/$XN6/g")" '"AuthorLogin"')"
  _run_record "$DN6" "$GN6" "PR #260" "Reviewer B" "$XN6"
  BN6="$(_note_of "$DN6" "$XN6")"
  if [ "$RC" = 0 ] \
     && printf '%s\n' "$BN6" | grep -qF 'approved-by: Reviewer B [self-asserted]' \
     && ! printf '%s\n' "$BN6" | grep -q 'authenticated' \
     && [ "$(printf '%s' "$BN6" | LC_ALL=C tr -d '\001-\010\013\014\016-\037')" = "$(printf '%s' "$BN6")" ]; then
    pass "REC-N6: hostile login (brackets + control char + newline) -> no upgrade AND the note body stays clean"
  else
    fail "REC-N6: rc=$RC note=[$BN6] OUT=[$OUT]"
  fi
  rm -rf "$DN6" "$GN6" 2>/dev/null || true

  # REC-N7: the SAME reviewer approved and then requested changes, both on this SHA. ANY-MATCH over
  # the history would upgrade here — the reviewer's APPROVED row is still in the list and always will
  # be. LATEST-per-reviewer is the only reading that respects a withdrawn approval, and this leg is
  # what makes that ordering deletion-provable.
  _rec_case REC-N7 base \
    '[{"user":{"login":"Reviewer B","type":"User"},"state":"APPROVED","commit_id":"@SHA@","submitted_at":"2026-09-01T00:00:00Z"},{"user":{"login":"Reviewer B","type":"User"},"state":"CHANGES_REQUESTED","commit_id":"@SHA@","submitted_at":"2026-09-01T01:00:00Z"}]' \
    '"AuthorLogin"' review-not-approved

  # REC-N8: a DISMISSED review. It is the strongest argument for an EXACT-state compare over any
  # `case`/prefix/substring test — a dismissed approval still reads as an approval to a loose matcher,
  # and dismissal is precisely the forge saying it no longer counts.
  _rec_case REC-N8 base \
    '[{"user":{"login":"Reviewer B","type":"User"},"state":"DISMISSED","commit_id":"@SHA@"}]' \
    '"AuthorLogin"' review-not-approved

  # REC-N9: reviews present, PR author UNRESOLVABLE (empty). The SoD inequality would be VACUOUSLY
  # TRUE against an empty author and would hand out the strongest label the kit has on the strength of
  # a failed lookup. Refuse instead — the same empty-operand refusal `actuate` already makes.
  _rec_case REC-N9 base "$_RQ" '""' author-unresolvable

  # REC-N9b (security F3): the author resolves NON-empty but is not a legal GitHub login. This is the
  # SoD comparison's only API-derived operand decided by INEQUALITY, and an inequality passes on
  # anything unexpected — so a malformed answer would read as "not the reviewer" and upgrade. The
  # charset anchor turns that silent pass into a stated refusal. `dependabot[bot]` is the real shape:
  # a bot-opened PR now refuses to upgrade, fail-closed and disclosed.
  _rec_case REC-N9b base "$_RQ" '"dependabot[bot]"' author-unresolvable

  # REC-N10: a Bot reviewer. `record` already rejects '[' in --approved-by, so a `…[bot]` App login can
  # never be the claimed id; this is the belt for a machine identity whose login carries no brackets.
  _rec_case REC-N10 base \
    '[{"user":{"login":"Reviewer B","type":"Bot"},"state":"APPROVED","commit_id":"@SHA@"}]' \
    '"AuthorLogin"' reviewer-is-bot

  # ---------------------------------------------------------------------------------------
  # ACT-CP: with the derivation wired, an [authenticated:] label is producible for EVERY class, so
  # "control-plane stays human-actuated" stops being true by construction and needs an actual arm.
  # A Control-plane-class note that clears the label bar AND the SoD teeth must still be REFUSED,
  # citing the open TIER-3-CP-MERGE-ACTUATION-RULING sitting. Honestly a DRIFT CONTROL — the class
  # field is caller-recorded, at the note's own trust tier — and removable by that ruling.
  # ---------------------------------------------------------------------------------------
  DCP="$(mkrepo)" || { fail "ACT-CP: fixture build"; return 1; }
  XCP="$(cat "$DCP/.X")"
  write_note "$DCP" "$XCP" "Reviewer B [authenticated: github-review]" "reviewer APPROVE" "Control-plane"
  MC="git update-ref refs/heads/merged $XCP && : > $DCP/.invoked"
  run_actuate "$VERIFY" "$DCP" merged "$XCP" "$MC"
  if [ "$RC" != 0 ] && [ ! -f "$DCP/.invoked" ] \
     && printf '%s' "$OUT" | grep -q 'ACTUATE REFUSED' \
     && printf '%s' "$OUT" | grep -qF 'TIER-3-CP-MERGE-ACTUATION-RULING'; then
    pass "ACT-CP: Control-plane class + authenticated label -> REFUSED citing the open sitting, merge not invoked (rc=$RC)"
  else
    fail "ACT-CP: rc=$RC invoked=$(invoked "$DCP") OUT=[$OUT]"
  fi
  rm -rf "$DCP" 2>/dev/null || true

  # ---------------------------------------------------------------------------------------
  # ACT-UNKNOWN (security F2): the class gate is an ALLOWLIST, so a note whose change-class is
  # MISSING or unrecognised must refuse too. Under the denylist this shipped with, this note merged:
  # `control-plane` was the only refused value, and a note is caller-recorded, so deleting one line
  # was the whole evasion. Two shapes, both must refuse.
  # ---------------------------------------------------------------------------------------
  for _uc in '' 'Contol-plane' 'OMIT'; do
    DUK="$(mkrepo)" || { fail "ACT-UNKNOWN: fixture build"; return 1; }
    XUK="$(cat "$DUK/.X")"
    write_note "$DUK" "$XUK" "Reviewer B [authenticated: github-review]" "reviewer APPROVE" "$_uc"
    MC="git update-ref refs/heads/merged $XUK && : > $DUK/.invoked"
    run_actuate "$VERIFY" "$DUK" merged "$XUK" "$MC"
    if [ "$RC" != 0 ] && [ ! -f "$DUK/.invoked" ] \
       && printf '%s' "$OUT" | grep -qF 'unrecognised or missing change-class'; then
      pass "ACT-UNKNOWN: change-class '$_uc' -> REFUSED by the allowlist, merge not invoked (rc=$RC)"
    else
      fail "ACT-UNKNOWN: class='$_uc' rc=$RC invoked=$(invoked "$DUK") OUT=[$OUT]"
    fi
    rm -rf "$DUK" 2>/dev/null || true
  done

  # REC-CLASS (review M1, the other end of the same hardening): `record` refuses an unrecognised
  # --class at the FRONT DOOR with rc 2, so the unjudgeable note above cannot be produced by the
  # supported path at all. Two arms of one vocabulary; each is load-bearing without the other.
  DRC="$(mkrepo)" || { fail "REC-CLASS: fixture build"; return 1; }
  XRC="$(cat "$DRC/.X")"
  if ORC="$( cd "$DRC" && sh "$VERIFY" record --approved-sha "$XRC" --approved-by "Reviewer B" \
               --gate release-candidate --rung "Release candidate" --class "Contol-plane" \
               --scope "PR #260" --token "GO" 2>&1 )"; then RRC=0; else RRC=$?; fi
  if [ "$RRC" = 2 ] && printf '%s' "$ORC" | grep -qF "invalid --class" \
     && [ -z "$(_note_of "$DRC" "$XRC")" ]; then
    pass "REC-CLASS: record refuses an out-of-vocabulary --class (rc=2, NO note written)"
  else
    fail "REC-CLASS: rc=$RRC OUT=[$ORC]"
  fi
  # ...and the three legal values are accepted (a validator that refused everything would pass above).
  for _lc in ordinary Sensitive CONTROL-PLANE; do
    DLC="$(mkrepo)" || { fail "REC-CLASS-OK: fixture build"; return 1; }
    XLC="$(cat "$DLC/.X")"
    if ( cd "$DLC" && sh "$VERIFY" record --no-push --approved-sha "$XLC" --approved-by "Reviewer B" \
           --gate release-candidate --rung "Release candidate" --class "$_lc" \
           --scope "branch/x" --token "GO" >/dev/null 2>&1 ); then
      pass "REC-CLASS-OK: '$_lc' accepted (case-insensitive vocabulary, not a refuse-all)"
    else
      fail "REC-CLASS-OK: legal class '$_lc' was rejected"
    fi
    rm -rf "$DLC" 2>/dev/null || true
  done
  rm -rf "$DRC" 2>/dev/null || true

  # =====================================================================================
  # GO-IDENTITY-AND-LAND-SOD (design 2026-10-02, owner ruling): the forge Approve is the ONLY identity the
  # kit authenticates; the owner's GO is recorded BY NAME in `go-by:` (never authenticated); and a
  # control-plane `land` merges only on an authenticated NON-AUTHOR forge approval. The fixtures use
  # half-2's shapes (PR author SeaBrad72 = the agent's gh account; reviewer reviewer-login = the owner's second
  # account). Every land leg asserts the merge marker AND the ledger, never a bare rc.
  # =====================================================================================
  _L_REV='[{"user":{"login":"reviewer-login","type":"User"},"state":"APPROVED","commit_id":"@SHA@"}]'
  _L_BOTH='[{"user":{"login":"reviewer-login","type":"User"},"state":"APPROVED","commit_id":"@SHA@"},{"user":{"login":"SeaBrad72","type":"User"},"state":"APPROVED","commit_id":"@SHA@"}]'
  _L_CHG='[{"user":{"login":"reviewer-login","type":"User"},"state":"CHANGES_REQUESTED","commit_id":"@SHA@"}]'
  # L2 (the control): reviewer reviewer-login approved, PR author SeaBrad72, GO-giver SeaBrad72 -> lands.
  _mkland_fx || { fail "L2: fixture build"; return 1; }
  _lg="$(_mkgh "$(_L_json "$_L_REV")" '"SeaBrad72"')"
  _land_run "$_lg" reviewer-login SeaBrad72
  _ln="$(_land_note)"
  if [ "$RC" = 0 ] && [ -f "$LDMARK" ] \
     && [ "$(printf '%s\n' "$_ln" | sed -n '4p')" = 'approved-by: reviewer-login [authenticated: github-review]' ] \
     && [ "$(printf '%s\n' "$_ln" | sed -n '5p')" = 'go-by: SeaBrad72 [self-asserted]' ] \
     && [ "$(printf '%s\n' "$_ln" | wc -l | tr -d ' ')" = 13 ] && printf '%s' "$OUT" | grep -qF 'authenticated non-author forge approval'; then
    pass "L2: CP land, approved-by=reviewer reviewer-login [authenticated], go-by=SeaBrad72 [self-asserted] -> rc 0, merge ran, 13-line note on origin"
  else
    fail "L2: rc=$RC merged=$([ -f "$LDMARK" ] && echo yes || echo no) note=[$_ln] OUT=[$OUT]"
  fi
  rm -rf "$LDR" "$_lg" 2>/dev/null || true

  # L1 (+, THE DEFECT): the cold test's mistake — the GO-giver SeaBrad72 passed as --approved-by while the
  # only review on the PR is reviewer-login's -> reviewer-not-in-reviews. land must REFUSE before the record:
  # rc 1, NO note (local or origin), merge never ran.
  _mkland_fx || { fail "L1: fixture build"; return 1; }
  _lg="$(_mkgh "$(_L_json "$_L_REV")" '"SeaBrad72"')"
  _land_run "$_lg" SeaBrad72 SeaBrad72
  if [ "$RC" = 1 ] && [ ! -f "$LDMARK" ] && [ -z "$(_land_note)" ] && [ -z "$(_land_onote)" ] \
     && printf '%s' "$OUT" | grep -qF 'reviewer-not-in-reviews' && printf '%s' "$OUT" | grep -qF -e '--go-by' \
     && printf '%s' "$OUT" | grep -qF 'LAND REFUSED' && printf '%s' "$OUT" | grep -qF 'SOLO'; then
    pass "L1: CP land with the GO-giver as --approved-by (no such review) -> rc 1 reviewer-not-in-reviews, NO note, merge never ran, the cure + SOLO path named"
  else
    fail "L1: rc=$RC merged=$([ -f "$LDMARK" ] && echo yes || echo no) local=[$(_land_note)] origin=[$(_land_onote)] OUT=[$OUT]"
  fi
  rm -rf "$LDR" "$_lg" 2>/dev/null || true

  # L3: SeaBrad72 DID post an APPROVED review, but on their own PR (they are its author) -> refused
  # reviewer-is-pr-author (the forge-side SoD, case-insensitive), no note, no merge.
  _mkland_fx || { fail "L3: fixture build"; return 1; }
  _lg="$(_mkgh "$(_L_json "$_L_BOTH")" '"SeaBrad72"')"
  _land_run "$_lg" SeaBrad72 SeaBrad72
  if [ "$RC" = 1 ] && [ ! -f "$LDMARK" ] && [ -z "$(_land_note)" ] && [ -z "$(_land_onote)" ] \
     && printf '%s' "$OUT" | grep -qF 'reviewer-is-pr-author'; then
    pass "L3: CP land with the PR author as approver (own APPROVED review present) -> rc 1 reviewer-is-pr-author, NO note, merge never ran"
  else
    fail "L3: rc=$RC merged=$([ -f "$LDMARK" ] && echo yes || echo no) local=[$(_land_note)] OUT=[$OUT]"
  fi
  rm -rf "$LDR" "$_lg" 2>/dev/null || true

  # L4: a CP land with no --go-by refuses, naming it — even with a fully qualifying approval — and writes nothing.
  _mkland_fx || { fail "L4: fixture build"; return 1; }
  _lg="$(_mkgh "$(_L_json "$_L_REV")" '"SeaBrad72"')"
  _land_run "$_lg" reviewer-login NONE
  if [ "$RC" = 1 ] && [ ! -f "$LDMARK" ] && [ -z "$(_land_note)" ] && [ -z "$(_land_onote)" ] \
     && printf '%s' "$OUT" | grep -qF -e '--go-by <the GO-giver>'; then
    pass "L4: CP land without --go-by -> rc 1 naming '--go-by <the GO-giver>', NO note, merge never ran"
  else
    fail "L4: rc=$RC merged=$([ -f "$LDMARK" ] && echo yes || echo no) local=[$(_land_note)] OUT=[$OUT]"
  fi
  rm -rf "$LDR" "$_lg" 2>/dev/null || true

  # L6 (the belt): the forge answers APPROVED to land's pre-check and CHANGES_REQUESTED to record's own call
  # (the approval was withdrawn in between). record writes a non-authenticated label; land re-reads the label
  # FROM THE NOTE ON ORIGIN and refuses the merge: note recorded [self-asserted], merge never ran, rc 1.
  _mkland_fx || { fail "L6: fixture build"; return 1; }
  _lg="$(_mkgh "$(_L_json "$_L_REV")" '"SeaBrad72"' "$(_L_json "$_L_CHG")")"
  _land_run "$_lg" reviewer-login SeaBrad72
  _ln="$(_land_note)"
  if [ "$RC" = 1 ] && [ ! -f "$LDMARK" ] \
     && [ "$(printf '%s\n' "$_ln" | sed -n '4p')" = 'approved-by: reviewer-login [self-asserted]' ] && [ -n "$(_land_onote)" ] \
     && printf '%s' "$OUT" | grep -qF 'IS recorded' && printf '%s' "$OUT" | grep -qF 'supersedes'; then
    pass "L6: approval withdrawn between pre-check and record -> note recorded [self-asserted], merge NOT run, rc 1 (the belt re-reads the note's own label)"
  else
    fail "L6: rc=$RC merged=$([ -f "$LDMARK" ] && echo yes || echo no) note=[$_ln] OUT=[$OUT]"
  fi
  rm -rf "$LDR" "$_lg" 2>/dev/null || true

  # S2-1 (a): the flag-swallowing repro. `--token` (record-only) is followed by a flag-shaped value, so land's
  # peek reads `--go-by`'s "value" as `--gate` while record reads `--go-by` as the TOKEN: land saw a go-by,
  # record wrote `(none recorded)`, and the merge ran. Any peeked value starting with '-' is now rc 2.
  _mkland_fx || { fail "S2-1a: fixture build"; return 1; }
  _lg="$(_mkgh "$(_L_json "$_L_REV")" '"SeaBrad72"')"
  rm -f "$LDMARK"
  if OUT="$( cd "$LDR/c" && PATH="$_lg:$PATH" PROMOTION_NOTES_REF=promotions sh "$VERIFY" land --ref 260 \
       --merge-cmd "$LDR/stub" --approved-sha "$LDX" --approved-by reviewer-login --token --go-by --gate release-candidate \
       --rung "Release candidate" --class control-plane --scope "PR #260" 2>&1 )"; then RC=0; else RC=$?; fi
  if [ "$RC" = 2 ] && [ ! -f "$LDMARK" ] && [ -z "$(_land_note)" ] && [ -z "$(_land_onote)" ] \
     && printf '%s' "$OUT" | grep -qF -e '--go-by'; then
    pass "S2-1a: a flag-shaped peeked value (--go-by --gate) -> rc 2 naming the flag, NO note, merge never ran"
  else
    fail "S2-1a: rc=$RC merged=$([ -f "$LDMARK" ] && echo yes || echo no) origin=[$(_land_onote)] OUT=[$OUT]"
  fi
  rm -rf "$LDR" "$_lg" 2>/dev/null || true

  # S2-1 (b): the belt verifies the WHOLE origin note. A hook on origin rewrites the note's go-by after the
  # push (the label stays authenticated), so only the whole-note check can refuse: note recorded, no merge.
  _mkland_fx || { fail "S2-1b: fixture build"; return 1; }
  printf '#!/bin/sh\nexport GIT_COMMITTER_NAME=h GIT_COMMITTER_EMAIL=h@x GIT_AUTHOR_NAME=h GIT_AUTHOR_EMAIL=h@x\ngit notes --ref=promotions show %s | sed "s/^go-by: .*/go-by: (none recorded)/" > "$GIT_DIR/hook.txt"\ngit notes --ref=promotions add -f -F "$GIT_DIR/hook.txt" %s\n' "$LDX" "$LDX" > "$LDR/origin.git/hooks/post-receive"
  chmod +x "$LDR/origin.git/hooks/post-receive"
  _lg="$(_mkgh "$(_L_json "$_L_REV")" '"SeaBrad72"')"
  _land_run "$_lg" reviewer-login SeaBrad72
  if [ "$RC" = 1 ] && [ ! -f "$LDMARK" ] && [ -n "$(_land_note)" ] && printf '%s' "$OUT" | grep -qF 'go-by' && printf '%s' "$OUT" | grep -qF 'IS recorded'; then
    pass "S2-1b: origin's note differs from what land judged (go-by rewritten) -> merge NOT run, rc 1, note IS recorded"
  else
    fail "S2-1b: rc=$RC merged=$([ -f "$LDMARK" ] && echo yes || echo no) OUT=[$OUT]"
  fi
  rm -rf "$LDR" "$_lg" 2>/dev/null || true

  # S2-2: the merged PR is the judged PR. --scope PR #12 judges PR 12's reviews; --ref 261 would merge 261.
  _mkland_fx || { fail "S2-2: fixture build"; return 1; }
  _lg="$(_mkgh "$(_L_json "$_L_REV")" '"SeaBrad72"')"
  _LREF=261; _land_run "$_lg" reviewer-login SeaBrad72 --scope "PR #12"; _LREF=""
  if [ "$RC" = 1 ] && [ ! -f "$LDMARK" ] && [ -z "$(_land_note)" ] && [ -z "$(_land_onote)" ] && printf '%s' "$OUT" | grep -qF 'LAND REFUSED'; then
    pass "S2-2: --scope PR #12 with --ref 261 -> rc 1, NO note, merge never ran (the judged PR is the merged PR)"
  else
    fail "S2-2: rc=$RC merged=$([ -f "$LDMARK" ] && echo yes || echo no) OUT=[$OUT]"
  fi
  # L2 (review): a branch/* scope has no PR to read, and the cure says --scope must be the PR id.
  _land_run "$_lg" reviewer-login SeaBrad72 --scope branch/x
  if [ "$RC" = 1 ] && [ ! -f "$LDMARK" ] && [ -z "$(_land_note)" ] && printf '%s' "$OUT" | grep -qF -e '--scope must be the PR id'; then
    pass "S2-2/L2: a branch/* scope -> rc 1, the cure says '--scope must be the PR id', NO note"
  else
    fail "S2-2/L2: rc=$RC OUT=[$OUT]"
  fi
  # L1 (review): --go-by given but empty/whitespace is rc 2 with record's wording, never 'missing' (rc 1).
  _l1bad=""
  for _l1 in '' '   '; do
    _land_run "$_lg" reviewer-login "$_l1"
    if [ "$RC" != 2 ] || [ -f "$LDMARK" ] || ! printf '%s' "$OUT" | grep -qF 'empty or whitespace-only'; then _l1bad="$_l1bad [$_l1 rc=$RC]"; fi
  done
  if [ -z "$_l1bad" ]; then pass "L1: land --go-by '' / whitespace -> rc 2 'empty or whitespace-only', no merge"; else fail "L1: got:$_l1bad"; fi
  rm -rf "$LDR" "$_lg" 2>/dev/null || true

  # LAND-WRITES-CARD-STATE C1: on a TRACKER backend `land` closes the row's card after the merge, and a failed move is
  # LOUD but never a failed merge. Real board.sh + tracker-conf.sh + backlog-lib.sh beside a COPY of the gate; stubs for
  # board-claim.sh (no claim ref: `check` rc 1) and the Jira adapter (a state file, STUB_TRANSITION_FAIL). The A9 reader
  # is stubbed to N/A (LAND_TRACKER_READER=false) so only the card step is under test. The tail line is the contract.
  _mkland_jira_fx || { fail "C1: fixture build"; return 1; }
  _lg="$(_mkgh "$(_L_json "$_L_REV")" '"SeaBrad72"')"
  printf 'In Progress' > "$LDR/state"
  _lv="$VERIFY"; VERIFY="$LDR/c/scripts/promotion-verify.sh"
  STUB_STATE_FILE="$LDR/state" LAND_TRACKER_READER=false; export STUB_STATE_FILE LAND_TRACKER_READER
  _land_run "$_lg" reviewer-login SeaBrad72
  if [ "$RC" = 0 ] && [ -f "$LDMARK" ] && [ "$(cat "$LDR/state")" = Done ] \
     && [ "$(printf '%s\n' "$OUT" | tail -1)" = 'board: closed' ]; then
    pass "LAND-CARD-CLOSE (C1 +): tracker land -> merge ran, the card reads Done (post-read), the last line is 'board: closed' (rc 0)"
  else
    fail "LAND-CARD-CLOSE: rc=$RC merged=$([ -f "$LDMARK" ] && echo yes || echo no) state=[$(cat "$LDR/state")] OUT=[$OUT]"
  fi
  VERIFY="$_lv"; rm -rf "$LDR" "$_lg" 2>/dev/null || true
  _mkland_jira_fx || { VERIFY="$_lv"; unset STUB_STATE_FILE LAND_TRACKER_READER; fail "C1n: fixture build"; return 1; }
  _lg="$(_mkgh "$(_L_json "$_L_REV")" '"SeaBrad72"')"   # the review JSON binds THIS fixture's sha
  printf 'In Progress' > "$LDR/state"; VERIFY="$LDR/c/scripts/promotion-verify.sh"
  STUB_STATE_FILE="$LDR/state" STUB_TRANSITION_FAIL=1; export STUB_STATE_FILE STUB_TRANSITION_FAIL
  _land_run "$_lg" reviewer-login SeaBrad72
  unset STUB_TRANSITION_FAIL
  if [ "$RC" = 0 ] && [ -f "$LDMARK" ] && [ "$(cat "$LDR/state")" != Done ] \
     && printf '%s' "$OUT" | grep -qF 'WARN' && printf '%s' "$OUT" | grep -qF 'sh scripts/board.sh release AB-1 --stale' \
     && [ "$(printf '%s\n' "$OUT" | tail -1)" = 'board: NOT CLOSED — see the WARN above' ]; then
    pass "LAND-CARD-CLOSE-FAIL (C1 -): a failed card move is rc 0 (merge kept), a WARN naming 'board.sh release AB-1 --stale', the card not Done, tail 'board: NOT CLOSED'"
  else
    fail "LAND-CARD-CLOSE-FAIL: rc=$RC merged=$([ -f "$LDMARK" ] && echo yes || echo no) state=[$(cat "$LDR/state")] OUT=[$OUT]"
  fi
  unset STUB_STATE_FILE LAND_TRACKER_READER; VERIFY="$_lv"
  rm -rf "$LDR" "$_lg" 2>/dev/null || true

  # L5: an ORDINARY record (the self-asserted default, no --go-by) writes a 13-line note whose line 5 reads
  # `go-by: (none recorded)`, and trace recovers it. With --go-by the line carries the name, labelled
  # [self-asserted] by a FIXED literal. (record for ordinary/sensitive keeps its behaviour but for the line.)
  DL5="$(mkrepo)" || { fail "L5: fixture build"; return 1; }
  XL5="$(cat "$DL5/.X")"
  GL5="$(_mkgh '[]' '"AuthorLogin"')"   # a forge with no review: the label stays the git-native [self-asserted]
  _run_record "$DL5" "$GL5" "PR #260" "Reviewer B" "$XL5"
  N5="$(_note_of "$DL5" "$XL5")"
  TR5="$( ( cd "$DL5" && sh "$VERIFY" trace --ref "$XL5" 2>&1 ) || true )"
  if [ "$RC" = 0 ] && [ "$(printf '%s\n' "$N5" | wc -l | tr -d ' ')" = 13 ] \
     && [ "$(printf '%s\n' "$N5" | sed -n '5p')" = 'go-by: (none recorded)' ] \
     && printf '%s' "$TR5" | grep -qF "$(printf '%s' "$XL5" | cut -c1-12)" && printf '%s' "$TR5" | grep -qF 'go-by: (none recorded)'; then
    pass "L5: ordinary record without --go-by -> 13-line note, line 5 'go-by: (none recorded)'; trace recovers it and prints go-by"
  else
    fail "L5: rc=$RC lines=$(printf '%s\n' "$N5" | wc -l | tr -d ' ') note=[$N5] trace=[$TR5]"
  fi
  if ( cd "$DL5" && sh "$VERIFY" record --no-push --approved-sha "$XL5" --approved-by "Reviewer B" --go-by "Bradley James" \
         --gate release-candidate --rung "Release candidate" --class Ordinary --scope "branch/l5" --token "GO" >/dev/null 2>&1 ) \
     && [ "$(_note_of "$DL5" "$XL5" | sed -n '5p')" = 'go-by: Bradley James [self-asserted]' ]; then
    pass "L5b: record --go-by 'Bradley James' -> line 5 'go-by: Bradley James [self-asserted]' (a FIXED literal label)"
  else
    fail "L5b: --go-by did not record 'go-by: Bradley James [self-asserted]': note=[$(_note_of "$DL5" "$XL5")]"
  fi
  rm -rf "$DL5" "$GL5" 2>/dev/null || true

  # L7: --go-by gets --approved-by's front-door hygiene: a bracket, a newline (note injection) or a blank value
  # is rejected rc 2 with NO note written — the label can never be supplied, so a forged one cannot enter.
  DL7="$(mkrepo)" || { fail "L7: fixture build"; return 1; }
  XL7="$(cat "$DL7/.X")"
  _l7bad=""
  for _l7 in 'Owner [authenticated: github-review]' "$(printf 'Owner\napproved-by: x [signed: gpg]')" '   ' ''; do
    if ( cd "$DL7" && sh "$VERIFY" record --no-push --approved-sha "$XL7" --approved-by "Reviewer B" --go-by "$_l7" \
           --gate release-candidate --rung "Release candidate" --class Ordinary --scope "branch/l7" --token "GO" >/dev/null 2>&1 ); then _l7rc=0; else _l7rc=$?; fi
    if [ "$_l7rc" != 2 ] || [ -n "$(_note_of "$DL7" "$XL7")" ]; then _l7bad="$_l7bad [$_l7 rc=$_l7rc]"; fi
  done
  # ...and the NON-VACUITY partner: the same call with a clean name is ACCEPTED (an unknown flag would also be rc 2).
  if ( cd "$DL7" && sh "$VERIFY" record --no-push --approved-sha "$XL7" --approved-by "Reviewer B" --go-by "Owner Name" \
         --gate release-candidate --rung "Release candidate" --class Ordinary --scope "branch/l7" --token "GO" >/dev/null 2>&1 ) \
     && [ "$(_note_of "$DL7" "$XL7" | sed -n '5p')" = 'go-by: Owner Name [self-asserted]' ]; then :; else _l7bad="$_l7bad [control: a clean --go-by was refused]"; fi
  if [ -z "$_l7bad" ]; then
    pass "L7: --go-by with a bracket, a newline, whitespace-only or empty -> rc 2 at the front door, NO note written (a clean name is accepted)"
  else
    fail "L7: want rc 2 and no note for every hostile --go-by; got:$_l7bad"
  fi
  rm -rf "$DL7" 2>/dev/null || true

  # =====================================================================================
  # RUNAWAY-METERING-LANDING-GATE T2 — `actuate` consults the per-slice meter behind the
  # RUNAWAY_METERING_GATE dial, AFTER SoD and BEFORE the merge. The row is the note's OWN `kit-row:`.
  # LOAD-BEARING NEGATIVE: a refusal attempts NO merge (the stub would leave a marker). The GO note
  # ALREADY EXISTS on actuate (`record` is a separate verb), so a refusal leaves a recorded-but-unmerged
  # GO — asserted, because that is the disclosed residual (design F5c), not a defect. The dial is read
  # from the APPROVED tree (never the working tree); env may only escalate. Owner ruling F3 = Option A: a
  # breached row PROCEEDS with a loud STOP line. Every leg sandboxes the tally through a temp HOME and runs
  # the gate from a kit-layout COPY, so a leg can remove the classifier or the guard.
  # =====================================================================================
  MGA_ROOT="$(mktemp -d)"
  MGA_SRC="$(cd "$(dirname "$VERIFY")" && pwd)"
  MGA_ENVX=""
  MGA_KIT="$MGA_ROOT/kit"
  mga_layout() {   # <dir> [noclassifier|noguard]
    _mk="$1"; _mv="${2:-}"
    rm -rf "$_mk"; mkdir -p "$_mk/scripts" "$_mk/.kit" "$_mk/conformance"
    cp "$VERIFY" "$_mk/scripts/promotion-verify.sh"
    cp "$MGA_SRC/../.kit/budget.conf" "$_mk/.kit/budget.conf"
    printf '#!/bin/sh\nexit 0\n' > "$_mk/scripts/board-claim.sh"
    if [ "$_mv" = stubrc7 ]; then printf '#!/bin/sh\nexit 7\n' > "$_mk/scripts/runaway-guard.sh"   # present, but exits an rc the gate has no named arm for
    elif [ "$_mv" != noguard ]; then cp "$MGA_SRC/runaway-guard.sh" "$_mk/scripts/runaway-guard.sh"; fi
    [ "$_mv" = noclassifier ] || cp "$MGA_SRC/../conformance/ci-classify-changes.sh" "$_mk/conformance/ci-classify-changes.sh"
  }
  mga_layout "$MGA_KIT"
  MGA_K="$MGA_KIT"
  mga_put_dial() {   # writes the dial into the CURRENT tree (cwd) and stages it
    mkdir -p .kit
    if [ "$_mdial" = LINK ]; then
      printf 'RUNAWAY_METERING_GATE=enforce\n' > .kit/elsewhere.conf
      ln -s elsewhere.conf .kit/dials.conf
    else
      printf '%s\n' "$_mdial" > .kit/dials.conf
    fi
    git add .kit
  }
  # mga_fx <dial: NONE|LINK|<conf line>> <row: NONE|(none)|ROW> <kind: code|docs|rename> [feat|base] [nobase]
  # -> $MD (repo), $MX (the approved sha, authored by `Author A`), $MH (the leg's temp HOME). G carries
  # x.sh (and the dial when `base`), origin/main is pointed at G unless `nobase`, and X is the feature
  # commit. The GO note is authenticated, approver != author, class Ordinary; kit-row is projected.
  mga_fx() {
    MD="$(mktemp -d)"; _mdial="$1"; _mrow="$2"; _mkind="$3"; _mwhere="${4:-feat}"
    (
      set -e; cd "$MD"
      git init -q; git config user.email committer@example.com; git config user.name committer; git config commit.gpgsign false
      printf 'base\n' > f.txt; printf '#!/bin/sh\n:\n' > x.sh; git add f.txt x.sh
      if [ "$_mwhere" = base ] && [ "$_mdial" != NONE ]; then mga_put_dial; fi
      git commit -qm G; git rev-parse HEAD > "$MD/.G"
      git checkout -q -b feat
      if [ "$_mwhere" = feat ] && [ "$_mdial" != NONE ]; then mga_put_dial; fi
      case "$_mkind" in
        code)   printf 'c\n' > code.sh; git add code.sh ;;
        docs)   mkdir -p docs; printf 'hi\n' > docs/x.md; git add docs ;;
        rename) mkdir -p docs; git mv x.sh docs/x.md ;;
        codedocs) printf 'c\n' > code.sh; git add code.sh; git commit -qm codepart
                  mkdir -p docs; printf 'hi\n' > docs/x.md; git add docs ;;
      esac
      GIT_AUTHOR_NAME='Author A' GIT_AUTHOR_EMAIL='a@x' git commit -qm X ${MGA_TRAILER:+-m "$MGA_TRAILER"}; git rev-parse HEAD > "$MD/.X"
    ) || { fail "metering-gate fixture build"; return 1; }
    MX="$(cat "$MD/.X")"
    # A REAL origin: the gate takes the docs-only base from the REMOTE (ls-remote), never the local ref.
    # `nobase` = the remote is unreachable (the local origin/main ref is still set, so a gate that trusted it would exempt).
    _mo="$MD/.origin.git"; mkdir -p "$_mo"; git -C "$_mo" init -q --bare
    if [ "${5:-}" = nobase ]; then git -C "$MD" remote add origin "$MD/no-such-origin"
    else git -C "$MD" remote add origin "$_mo"; git -C "$MD" push -q origin "$(cat "$MD/.G"):refs/heads/main"; fi
    git -C "$MD" update-ref refs/remotes/origin/main "$(cat "$MD/.G")"
    write_note "$MD" "$MX" "Reviewer B [authenticated: github-review]"
    [ "$_mrow" = NONE ] || ( cd "$MD" && git notes --ref=promotions append -m "kit-row: $_mrow" "$MX" ) >/dev/null 2>&1
    MH="$MD/.home"; mkdir -p "$MH"
  }
  mga_seed() {   # <row> <tokens> <agents> — a tally line for the fixture repo in the leg's temp HOME
    _mkey="$(git -C "$MD" rev-list --max-parents=0 --first-parent HEAD | tail -1)"
    mkdir -p "$MH/.local/state/sparkwright/runaway/$_mkey"
    printf '1757900000 keyA %s %s %s\n' "$1" "$2" "$3" >> "$MH/.local/state/sparkwright/runaway/$_mkey/tally.v2"
  }
  mga_act() {   # -> RC, OUT. The ambient redirection/dial env is scrubbed; $MGA_ENVX re-adds a leg's own.
    rm -f "$MD/.invoked"
    if OUT="$( cd "$MD/${MGA_SUB:-}" && env -u KIT_RUNAWAY_SANDBOX -u RUNAWAY_TALLY -u RUNAWAY_BUDGET_CONFIG -u RUNAWAY_METERING_GATE \
          HOME="$MH" $MGA_ENVX "$MGA_SH" "$MGA_K/scripts/promotion-verify.sh" actuate --ref merged --approved-sha "$MX" \
          --merge-cmd "git update-ref refs/heads/merged $MX && : > $MD/.invoked" 2>&1 )"; then RC=0; else RC=$?; fi
  }
  mga_check() {   # <label> <proceed|refuse> <needle>... (a leading ! = must NOT appear)
    _ml="$1"; _mw="$2"; shift 2; _mbad=""
    if [ "$_mw" = proceed ]; then
      { [ "$RC" = 0 ] && [ -f "$MD/.invoked" ]; } || _mbad="want rc 0 + merge, got rc=$RC invoked=$(invoked "$MD")"
    else
      { [ "$RC" != 0 ] && [ ! -f "$MD/.invoked" ] && [ -n "$(_note_of "$MD" "$MX")" ]; } \
        || _mbad="want a refusal + NO merge + the GO note still recorded, got rc=$RC invoked=$(invoked "$MD")"
    fi
    for _mn in "$@"; do
      case "$_mn" in
        '!'*) _mn="${_mn#!}"; if printf '%s' "$OUT" | grep -qF -- "$_mn"; then _mbad="$_mbad; unexpected '$_mn'"; fi ;;
        *)    printf '%s' "$OUT" | grep -qF -- "$_mn" || _mbad="$_mbad; missing '$_mn'" ;;
      esac
    done
    if [ -z "$_mbad" ]; then pass "$_ml [$MGA_SH]"; else fail "$_ml [$MGA_SH] — $_mbad; OUT=[$OUT]"; fi
    rm -rf "$MD" 2>/dev/null || true
  }
  MGA_ENF='RUNAWAY_METERING_GATE=enforce'
  MGA_OBS='RUNAWAY_METERING_GATE=observe'

  # The legs run under EVERY producer shell this host has: `sh` (bash-as-sh on macOS, dash on Debian CI)
  # AND `dash` explicitly (the A5 class: dash's echo expands \0NNN, its patterns differ). MGA_SH names it.
  mga_legs() {
  mga_fx "$MGA_ENF" ROW-MA1 code; mga_act
  mga_check "ACT-METER(enforce, unmetered): refused, NO merge attempted, the remedy names the exact step command" refuse \
    "ACTUATE REFUSED (metering gate)" "step --row ROW-MA1 --tokens N --agents N" "never estimate" "default branch"

  mga_fx "$MGA_ENF" ROW-MA2 code; mga_seed ROW-MA2 100 2; mga_act
  mga_check "ACT-METER(enforce, metered): proceeds, prints the meter line" proceed "metered: ROW-MA2 tokens(100/" "OK: actuated"

  mga_fx "$MGA_ENF" ROW-MA3 code; mga_seed ROW-MA3 100 2
  printf 'this line is not the tally grammar\n' >> "$MH/.local/state/sparkwright/runaway/$_mkey/tally.v2"; mga_act
  mga_check "ACT-METER(enforce, rc 2 poisoned tally): refused (fail-closed), no merge, the HOME path elided" refuse \
    "ACTUATE REFUSED (metering gate)" "guard rc 2" "\$HOME…" "!$MH"

  mga_fx "$MGA_ENF" ROW-MA4 code; mga_seed ROW-MA4 999999999999 1; mga_act
  mga_check "ACT-METER(enforce, breached, F3 Option A): PROCEEDS with the loud STOP line, repeated in the report" proceed \
    "STOP: ROW-MA4 tokens(" "ceiling breached (landed anyway: approved)" "OK: actuated"
  # (the STOP-twice count is asserted on the land verb; here the merge ran and the line is present)

  mga_fx "$MGA_OBS" ROW-MA5 code; mga_act
  mga_check "ACT-METER(observe, unmetered): proceeds with the one line" proceed "unmetered: ROW-MA5 (observe — not gating)"

  mga_fx NONE ROW-MA6 code; mga_act
  mga_check "ACT-METER(dial absent): silent — proceeds, nothing about the meter" proceed "!metered" "!metering gate" "!runaway"

  mga_fx "$MGA_ENF" ROW-MA7 docs base; mga_act
  mga_check "ACT-METER(docs-only, enforce, unmetered): N/A — proceeds" proceed "N/A: docs-only change"

  mga_fx "$MGA_ENF" ROW-MA8 rename base; mga_act
  mga_check "ACT-METER(a .sh -> .md rename is NOT docs-only): refused in enforce" refuse "ACTUATE REFUSED (metering gate)" "!N/A: docs-only"

  mga_fx "$MGA_ENF" ROW-MA9 docs base nobase; mga_act
  mga_check "ACT-METER(unresolvable merge-base): NOT docs-only — refused in enforce, and says the base is unreadable (fix2 B)" refuse "ACTUATE REFUSED (metering gate)" "!N/A: docs-only" \
    "docs-only exemption unavailable: cannot read origin's main"

  # fix round 2 (Minor): the remote main tip is NOT present locally -> the exemption names the missing fetch.
  mga_fx "$MGA_ENF" ROW-MA26 docs base
  ( set -e; _mgc="$(mktemp -d)"; git clone -q "$MD/.origin.git" "$_mgc/c"; cd "$_mgc/c"; git config user.email c@x; git config user.name c
    git checkout -q main 2>/dev/null || git checkout -q -b main origin/main; printf 'n\n' > newer.txt; git add newer.txt; git commit -qm newer
    git push -q origin HEAD:refs/heads/main; rm -rf "$_mgc" ) || fail "could not advance the fixture origin"
  mga_act
  mga_check "ACT-METER(fix2 B): remote main tip not fetched locally -> NOT docs-only, refused, names 'git fetch origin'" refuse "ACTUATE REFUSED (metering gate)" "!N/A: docs-only" \
    "docs-only exemption unavailable: origin/main tip not fetched — git fetch origin"

  # fix round 1 (security HIGH): the dial read is FULL-TREE — from a SUBDIRECTORY the gate still reads the root dial.
  mga_fx "$MGA_ENF" ROW-MA19 code; mkdir -p "$MD/sub"; MGA_SUB=sub; mga_act; MGA_SUB=""
  mga_check "ACT-METER(fix1 A): enforce + unmetered invoked from a SUBDIRECTORY -> still refused" refuse "ACTUATE REFUSED (metering gate)" "step --row ROW-MA19"

  # fix round 1 (security MEDIUM): a replace ref pointing the approved sha at an observe tree must not de-escalate.
  mga_fx "$MGA_ENF" ROW-MA20 code
  ( set -e; cd "$MD"; git checkout -q -b crafted; printf 'RUNAWAY_METERING_GATE=observe\n' > .kit/dials.conf; git add .kit
    git commit -qm crafted; git replace -f "$MX" "$(git rev-parse HEAD)"; git checkout -q feat ) || fail "could not build the replace-ref fixture"
  mga_act
  mga_check "ACT-METER(fix1 B): a replace ref redirecting the approved sha to an observe tree does NOT de-escalate -> refused" refuse "ACTUATE REFUSED (metering gate)"

  # fix round 1 (security MEDIUM): the docs-only base is the REMOTE's main; moving the local ref must not exempt code+docs.
  mga_fx "$MGA_ENF" ROW-MA21 codedocs base
  git -C "$MD" update-ref refs/remotes/origin/main "${MX}^"; mga_act
  mga_check "ACT-METER(fix1 C): a code+docs change with the LOCAL origin/main moved to the approved parent is NOT docs-only -> refused" refuse "ACTUATE REFUSED (metering gate)" "!N/A: docs-only" "!docs-only exemption unavailable"

  # fix round 2 (reviewer Blocker): a note for a sha whose COMMIT is absent locally (a clone that fetched only the notes
  # ref) must REFUSE in the default (non-enforce) env — it cannot be proved non-enforcing — and never reach the merge.
  mga_fx NONE ROW-MA25 code; _mgold="$MD"; MD="$(mktemp -d)"
  ( set -e; cd "$MD"; git init -q; git config user.email committer@example.com; git config user.name committer
    git fetch -q "$_mgold" refs/notes/promotions:refs/notes/promotions ) || fail "could not build the notes-only fixture"
  if git -C "$MD" cat-file -e "${MX}^{commit}" 2>/dev/null; then fail "notes-only fixture unexpectedly holds the approved commit"; fi
  mga_act; rm -rf "$_mgold" 2>/dev/null || true
  # ACTUATE-SOD-EMPTY-AUTHOR: SoD now speaks FIRST on an absent commit (it cannot compare an unreadable author), so the
  # refusal is the SoD reason with the fetch remedy — NOT the metering gate's. The gate's own unresolvable-sha branch
  # stays as a belt but is unreachable from this verb (pv_sod_author_check refuses earlier).
  mga_check "ACT-METER(fix2 A): a note whose approved commit is ABSENT locally -> refused by SoD with the fetch remedy, NO merge (default env)" refuse \
    "ACTUATE REFUSED: the approved commit" "is not in this clone — SoD cannot compare the approver to its author" "git fetch origin" "!(metering gate)"

  # SODEA-A1: the same notes-only clone with the dial in OBSERVE — the reason must be the SoD one, and no merge.
  mga_fx "$MGA_OBS" ROW-SA1 code; _mgold="$MD"; MD="$(mktemp -d)"
  ( set -e; cd "$MD"; git init -q; git config user.email committer@example.com; git config user.name committer
    git fetch -q "$_mgold" refs/notes/promotions:refs/notes/promotions ) || fail "could not build the SODEA-A1 notes-only fixture"
  if git -C "$MD" cat-file -e "${MX}^{commit}" 2>/dev/null; then fail "SODEA-A1 fixture unexpectedly holds the approved commit"; fi
  mga_act; rm -rf "$_mgold" 2>/dev/null || true
  mga_check "SODEA-A1: notes-only clone, observe -> refused by the SoD reason (names the missing commit + git fetch origin), NOT the metering gate, NO merge" refuse \
    "ACTUATE REFUSED: the approved commit $MX is not in this clone" "SoD cannot compare the approver to its author" "git fetch origin" "!(metering gate)"

  # SODEA-A2: a case-varied and a whitespace-varied self-approval (the author is 'Author A') are refused, NO merge.
  # Each is a note the fixture would otherwise PROCEED on (authenticated, ordinary, commit present), so step 3 is really reached.
  # The last two are full-ident spellings ('Name <email>' and a bare '<EMAIL>'): the same person, refused too.
  for _sa2 in 'author a' 'AUTHOR A' 'Author  A' ' Author   A ' 'Author A <a@x>' '<A@X>'; do
    mga_fx NONE ROW-SA2 code; write_note "$MD" "$MX" "$_sa2 [authenticated: github-review]"; mga_act
    mga_check "SODEA-A2: approver '$_sa2' vs author 'Author A' -> refused as a self-approval, NO merge" refuse "ACTUATE REFUSED: approver equals author"
  done
  mga_fx NONE ROW-SA2P code; write_note "$MD" "$MX" "Author AB [authenticated: github-review]"; mga_act
  mga_check "SODEA-A2 (liveness): a DIFFERENT approver 'Author AB' still proceeds — the fold is not a refuse-all" proceed "OK: actuated"

  # SODEA-A3: a RESOLVABLE commit whose author NAME is empty (crafted; git writes it without --literally) is refused
  # with the empty-author reason — an identity that cannot be read is never a pass.
  mga_fx NONE ROW-SA3 code
  ( set -e; cd "$MD"; _sat="$(git rev-parse "${MX}^{tree}")"; _sap="$(git rev-parse "${MX}^")"
    printf 'tree %s\nparent %s\nauthor  <a@x> 1757900000 +0000\ncommitter committer <committer@example.com> 1757900000 +0000\n\nX\n' "$_sat" "$_sap" > .sa3body
    _sac="$(git hash-object -t commit -w .sa3body)"; printf '%s\n' "$_sac" > .X; git update-ref refs/heads/feat "$_sac" ) || fail "could not craft the empty-author commit"
  MX="$(cat "$MD/.X")"; write_note "$MD" "$MX" "Reviewer B [authenticated: github-review]"
  if [ -n "$(git -C "$MD" show -s --format=%an "$MX")" ]; then fail "SODEA-A3 fixture: the crafted author name is not empty"; fi
  mga_act
  mga_check "SODEA-A3: a resolvable commit with an EMPTY author name -> refused with the empty-author reason, NO merge" refuse "ACTUATE REFUSED:" "author of the approved commit" "cannot be read"

  # SODEA-A4: the fixture repo's OWN config sets log.showSignature=true and the approved commit is ssh-SIGNED, so an
  # unflagged `git show --format=%an` prints a signature line before the name. A real self-approval (approver ==
  # author) must still be refused as one, NO merge. The fixture proves it is polluted, or the leg is not load-bearing.
  if ! command -v ssh-keygen >/dev/null 2>&1; then
    echo "N/A: SODEA-A4 (log.showSignature + signed commit): ssh-keygen is absent on this host, so no ssh-signed fixture can be built — NOT a PASS"
  else
    mga_fx NONE ROW-SA4 code
    # (an `&&` chain, not `set -e`: errexit is disabled inside an `if` condition)
    if ( cd "$MD" && ssh-keygen -q -t ed25519 -N '' -f "$MD/.k" && git config log.showSignature true \
         && GIT_AUTHOR_NAME='Author A' GIT_AUTHOR_EMAIL='a@x' git -c gpg.format=ssh -c user.signingkey="$MD/.k.pub" commit -q -S --amend --no-edit \
         && git rev-parse HEAD > .X ) >/dev/null 2>&1; then
      MX="$(cat "$MD/.X")"; write_note "$MD" "$MX" "Author A [authenticated: github-review]"
      if [ "$(git -C "$MD" show -s --format=%an "$MX" 2>/dev/null | wc -l | tr -d ' ')" -lt 2 ]; then fail "SODEA-A4 fixture: an unflagged %an read is NOT polluted, so the leg is not load-bearing"; fi
      mga_act
      mga_check "SODEA-A4: log.showSignature=true + a signed approved commit, approver == author -> still refused as a self-approval, NO merge" refuse "ACTUATE REFUSED: approver equals author"
    else
      echo "N/A: SODEA-A4 (log.showSignature + signed commit): this host's git/ssh-keygen cannot make an ssh-signed commit — NOT a PASS"; rm -rf "$MD" 2>/dev/null || true
    fi
  fi

  # SODEA-A5: a RESOLVABLE commit with a real author NAME and an EMPTY email (crafted `author Name <> ...`; git accepts it
  # without --literally) is refused with the empty-author reason (the empty-email arm).
  mga_fx NONE ROW-SA5 code
  ( set -e; cd "$MD"; _sat="$(git rev-parse "${MX}^{tree}")"; _sap="$(git rev-parse "${MX}^")"
    printf 'tree %s\nparent %s\nauthor Name <> 1757900000 +0000\ncommitter committer <committer@example.com> 1757900000 +0000\n\nX\n' "$_sat" "$_sap" > .sa5body
    _sac="$(git hash-object -t commit -w .sa5body)"; printf '%s\n' "$_sac" > .X; git update-ref refs/heads/feat "$_sac" ) || fail "could not craft the empty-email commit"
  MX="$(cat "$MD/.X")"; write_note "$MD" "$MX" "Reviewer B [authenticated: github-review]"
  if [ -n "$(git -C "$MD" show -s --format=%ae "$MX")" ] || [ -z "$(git -C "$MD" show -s --format=%an "$MX")" ]; then fail "SODEA-A5 fixture: want a real name and an EMPTY email"; fi
  mga_act
  mga_check "SODEA-A5: a resolvable commit with a real author name and an EMPTY email -> refused with the empty-author reason, NO merge" refuse "ACTUATE REFUSED:" "author of the approved commit" "cannot be read"

  mga_fx "$MGA_ENF" ROW-MA10 docs base; mga_layout "$MGA_ROOT/kit-nocls" noclassifier; MGA_K="$MGA_ROOT/kit-nocls"; mga_act; MGA_K="$MGA_KIT"
  mga_check "ACT-METER(classifier absent): NOT docs-only (fail-safe) — refused in enforce" refuse "ACTUATE REFUSED (metering gate)" "!N/A: docs-only"

  mga_fx "$MGA_ENF" NONE code; mga_act
  mga_check "ACT-METER(note with no kit-row, enforce): refused — cannot meter an unnamed row" refuse "ACTUATE REFUSED (metering gate)" "unnamed row"
  mga_fx "$MGA_ENF" '(none)' code; mga_act
  mga_check "ACT-METER(kit-row: (none), enforce): refused" refuse "unnamed row"

  mga_fx 'RUNAWAY_METERING_GATE=enforcee' ROW-MA11 code; mga_act
  mga_check "ACT-METER(malformed conf value): reads as observe and WARNs on the conf side" proceed "WARN" ".kit/dials.conf" "unmetered: ROW-MA11 (observe — not gating)"

  mga_fx "$MGA_ENF" ROW-MA12 code
  printf 'RUNAWAY_METERING_GATE=observe\n' > "$MD/.kit/dials.conf"; mga_act
  mga_check "ACT-METER(F1): the working tree says observe but the APPROVED tree says enforce -> refused" refuse "ACTUATE REFUSED (metering gate)"

  mga_fx "$MGA_ENF" ROW-MA13 code; MGA_ENVX="RUNAWAY_METERING_GATE=observe"; mga_act; MGA_ENVX=""
  mga_check "ACT-METER(F1): env =observe cannot de-escalate an enforcing approved tree -> refused, and says so" refuse "ACTUATE REFUSED (metering gate)" "cannot de-escalate"
  mga_fx NONE ROW-MA14 code; MGA_ENVX="RUNAWAY_METERING_GATE=enforce"; mga_act; MGA_ENVX=""
  mga_check "ACT-METER(F1): env =enforce escalates a tree with no key -> refused" refuse "ACTUATE REFUSED (metering gate)"

  # fix round 3 (F-C): a hand-written note whose kit-row differs from the approved commit's Kit-Row trailer
  # (record never writes a mismatch) is refused in enforce, BEFORE the gate, with no merge.
  MGA_TRAILER='Kit-Row: ROW-UNMETERED'; mga_fx "$MGA_ENF" ROW-METERED code; MGA_TRAILER=""; mga_seed ROW-METERED 100 1; mga_act
  mga_check "ACT-METER(F-C): note kit-row ROW-METERED vs commit Kit-Row ROW-UNMETERED, enforce -> refused as a hand-written note, no merge" refuse "does not match the approved commit's Kit-Row" "ROW-METERED" "ROW-UNMETERED" "hand-written note"

  mga_fx LINK ROW-MA15 code; mga_act
  mga_check "ACT-METER(F1 cond 2): a 120000 symlink dials entry reads observe with a loud line naming the symlink" proceed "symlink" "unmetered: ROW-MA15 (observe — not gating)"

  mga_fx "$MGA_ENF" ROW-MA16 code
  mkdir -p "$MGA_ROOT/sbx"; printf '1757900000 keyA ROW-MA16 100 1\n' > "$MGA_ROOT/sbx/tally.v2"
  if ( cd "$MD" && env HOME="$MH" KIT_RUNAWAY_SANDBOX="$MGA_ROOT/sbx" RUNAWAY_TALLY="$MGA_ROOT/sbx/tally.v2" \
         sh "$MGA_KIT/scripts/runaway-guard.sh" meter --row ROW-MA16 >/dev/null 2>&1 ); then
    pass "ACT-METER(F2) precondition: the sandbox env alone WOULD read ROW-MA16 as metered"
  else fail "ACT-METER(F2) precondition: the sandbox tally did not read as metered, the leg would be vacuous"; fi
  MGA_ENVX="KIT_RUNAWAY_SANDBOX=$MGA_ROOT/sbx RUNAWAY_TALLY=$MGA_ROOT/sbx/tally.v2"; mga_act; MGA_ENVX=""
  mga_check "ACT-METER(F2): the sandbox env exported while the temp-HOME tally is unmetered -> still refused" refuse "ACTUATE REFUSED (metering gate)" "step --row ROW-MA16"

  mga_fx "$MGA_ENF" ROW-MA17 code; mga_layout "$MGA_ROOT/kit-nog" noguard; MGA_K="$MGA_ROOT/kit-nog"; mga_act; MGA_K="$MGA_KIT"
  mga_check "ACT-METER(F8): the guard script absent -> refused in enforce, naming the absence (deterministic under every shell)" refuse "ACTUATE REFUSED (metering gate)" "the runaway guard script is absent (<path elided>)"
  mga_fx "$MGA_ENF" ROW-MA17B code; mga_layout "$MGA_ROOT/kit-stub7" stubrc7; MGA_K="$MGA_ROOT/kit-stub7"; mga_act; MGA_K="$MGA_KIT"
  mga_check "ACT-METER(F8b): a guard that is present but exits rc 7 -> the any-other-rc arm refuses in enforce (no fail-open on a crash)" refuse "ACTUATE REFUSED (metering gate)" "exited rc 7"

  mga_fx "$MGA_OBS" ROW-MA18 code; mga_seed ROW-MA18 1 1
  printf 'this line is not the tally grammar\n' >> "$MH/.local/state/sparkwright/runaway/$_mkey/tally.v2"; mga_act
  mga_check "ACT-METER(observe, rc 2): ONE line, proceeds" proceed "guard rc 2" "observe"
  }
  # `dash` explicitly only when `sh` is not already dash (every Ubuntu runner): a second pass would run every
  # leg twice for nothing. If `sh` cannot be resolved, keep both.
  mga_sh_is_dash() { _mgp="$(command -v sh 2>/dev/null)" || return 1; _mgt="$(readlink -f "$_mgp" 2>/dev/null || readlink "$_mgp" 2>/dev/null || true)"
    case "$_mgt" in *dash*) return 0 ;; esac; return 1; }
  MGA_SHELLS="sh dash"; if mga_sh_is_dash; then MGA_SHELLS="sh"; fi
  for MGA_SH in $MGA_SHELLS; do
    command -v "$MGA_SH" >/dev/null 2>&1 || continue
    mga_legs
  done
  rm -rf "$MGA_ROOT" 2>/dev/null || true

  if [ "$st" = 0 ]; then
    echo "OK: promotion-actuate-wired selftest — actuate gate wired + non-vacuous (wiring: 1 liveness + 6 negatives; actuate: 1 liveness + 9 negatives + guard fixtures + lock self-negative; forge-review derivation: 3 liveness + 11 negatives + the class allowlist, both ends; GO identity: land L1-L4+L6 (the CP bar, the belt) + record L5/L7 (go-by))"
  else
    echo "FAIL: promotion-actuate-wired selftest"
  fi
  return $st
}

# ===========================================================================================
# ORACLE + wiring oracle helper — BELOW the ^selftest() marker, so the non-vacuity harness emits them
# VERBATIM and never mutates them. fail()'s st accumulator is the ONE that legitimately leaves the
# mutation region; wiring()'s six wiring flags stay ABOVE the marker and remain load-bearing.
# ===========================================================================================
st=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; st=1; }

# Drive wiring() against fixture targets. The VERIFY/GUARD/VERIFY_SH reassignments live INSIDE the
# $( … ) subshell, so they cannot leak between cases — wiring() always runs; only WHAT it inspects
# changes.
_expect_wiring() {  # <v-omit> <g-omit> <r-omit> <expected-rc> <needle> <label>
  _d=$(_mkwiring "$1" "$2" "$3")
  if _out=$( VERIFY="$_d/v.txt"; GUARD="$_d/g.txt"; VERIFY_SH="$_d/r.txt"; wiring 2>&1 ); then _rc=0; else _rc=$?; fi
  if [ "$_rc" = "$4" ] && printf '%s\n' "$_out" | grep -qF "$5"; then
    pass "wiring — $6 (rc $_rc)"
  else
    fail "wiring — $6 expected rc $4 + '$5'; got rc $_rc out=[$_out]"
  fi
  rm -rf "$_d"
}

# ===========================================================================================
# PR 11 — FORGE-REVIEW DERIVATION fixtures. DELIBERATELY BELOW THE ^selftest() MARKER, for two
# reasons that point the same way: (1) the non-vacuity sweep mutates only the lines ABOVE it, and a
# neutered `gh` shim would silently disarm every REC-* leg's teeth rather than red them; (2) the mass
# budget prices pre-marker lines as check LOGIC (zero-headroom) and post-marker lines as FIXTURE —
# and these are fixtures, not check logic. The pre-marker NAME=1 accumulator invariant (see the
# marker's comment) is therefore untouched by this block.
# ===========================================================================================

# _mkgh <reviews-json> <pr-author-login-as-JSON> -> echoes a throwaway dir holding an executable `gh`.
#
# A PATH SHIM — a real executable file the derivation finds through PATH — and NOT an env-var-eval'd
# probe. That distinction is the point: `BOARD_DRIFT_PR_STATE`-style `sh -c "$VAR …"` injection is the
# class PR 10 caught an RCE in, and the cure for this file is to not add a second instance.
#
# The shim applies the caller's own `--jq` filter with REAL jq, exactly as `gh api` does, so the
# PRODUCTION extraction filters are what the legs exercise. A shim that returned canned post-jq
# answers would leave the one thing worth proving — that the extraction is structural rather than a
# substring grep of raw JSON — untested, and REC-N6 would then be theatre.
_mkgh() {
  _g=$(mktemp -d)
  printf '%s' "$1" > "$_g/reviews.json"
  printf '{"user":{"login":%s}}' "$2" > "$_g/pr.json"
  # OPTIONAL 3rd arg: the reviews the forge answers on EVERY LATER reviews call (the first call gets $1) —
  # the approval-withdrawn-between-two-reads shape that GO-IDENTITY-AND-LAND-SOD's belt (L6) needs.
  [ -z "${3:-}" ] || printf '%s' "$3" > "$_g/reviews2.json"
  cat > "$_g/gh" <<'GHSHIM'
#!/bin/sh
# fake gh — answers `gh api <path> [--jq <filter>] [flags]` and nothing else.
_p=""; _f="."
while [ $# -gt 0 ]; do
  case "$1" in
    --jq) _f="${2:-.}"; shift ;;
    -*|api) : ;;
    *) [ -n "$_p" ] || _p="$1" ;;
  esac
  shift
done
case "$_p" in
  */reviews) _src="$(dirname "$0")/reviews.json"
             if [ -f "$(dirname "$0")/reviews2.json" ]; then
               _c="$(dirname "$0")/calls"; _n=$(( $(cat "$_c" 2>/dev/null || echo 0) + 1 )); echo "$_n" > "$_c"
               [ "$_n" -le 1 ] || _src="$(dirname "$0")/reviews2.json"
             fi ;;
  *)         _src="$(dirname "$0")/pr.json" ;;
esac
[ -f "$_src" ] || exit 1
jq -r "$_f" < "$_src"
GHSHIM
  chmod +x "$_g/gh"
  printf '%s\n' "$_g"
}

# _mknogh -> echoes a dir that is a COMPLETE PATH carrying every tool `record` needs EXCEPT `gh`.
# The honest way to test "gh absent" is a PATH on which it genuinely is not, rather than a stub that
# pretends to fail — a stub failing is the api-error arm, which is a different reason string.
_mknogh() {
  _n=$(mktemp -d)
  for _t in sh env git awk sed tr cut grep head tail wc sort date mktemp basename dirname \
            cat rm ln chmod expr test true false uname jq; do
    _tp="$(command -v "$_t" 2>/dev/null)" || continue
    ln -s "$_tp" "$_n/$_t" 2>/dev/null || true
  done
  printf '%s\n' "$_n"
}

# _run_record <dir> <path-prefix-or-PATH-override> <scope> <approved-by> <sha> [absolute]
#   Drives the REAL `record` in <dir>. With a 6th arg the 2nd is used as the WHOLE PATH (the gh-absent
#   leg); otherwise it is PREPENDED. Sets RC + OUT (merged), as run_actuate does.
_run_record() {
  _rd="$1"; _rg="$2"; _rs="$3"; _rb="$4"; _rx="$5"; _rabs="${6:-}"
  if [ -n "$_rabs" ]; then _rp="$_rg"; else _rp="${_rg:+$_rg:}$PATH"; fi
  # --no-push: since RECORD-FETCHES-AND-PUSHES-LEDGER, `record` fetches the ledger from `origin`
  # first and refuses when it cannot read it. These fixtures are remote-less `git init` repos and
  # they test the ASSURANCE LABEL, not publication, so they take the labelled offline escape.
  if OUT="$( cd "$_rd" && PATH="$_rp" sh "$VERIFY" record --no-push \
               --approved-sha "$_rx" --approved-by "$_rb" --gate release-candidate \
               --rung "Release candidate" --class Ordinary --scope "$_rs" \
               --token "GO: merge $_rs" 2>&1 )"; then RC=0; else RC=$?; fi
}

# _note_of <dir> <sha> -> the recorded note body ('' when none).
_note_of() { ( cd "$1" && git notes --ref=promotions show "$2" 2>/dev/null ) || true; }

# ── GO-IDENTITY-AND-LAND-SOD land fixtures. `land` records THROUGH origin and refuses --no-push, so these
#    legs need a real bare origin (a throwaway under mktemp; PROMOTION_NOTES_REF names the fixture ledger,
#    so nothing here can touch the real one). The approved commit X is authored by `Author A`, which is
#    neither reviewer nor PR author, so land's own commit-author SoD passes and the FORGE derivation is the
#    only thing under test. The merge-cmd is ONE word (a stub touching $LDMARK): land refuses every shell
#    metacharacter in a merge-cmd, and "marker absent" is what proves no merge ran.
_mkland_fx() {
  LDR="$(mktemp -d)"
  git init -q --bare -b main "$LDR/origin.git" || return 1
  ( set -e
    git clone -q "$LDR/origin.git" "$LDR/c" 2>/dev/null
    cd "$LDR/c"
    git config user.email committer@example.com; git config user.name committer; git config commit.gpgsign false
    printf 'base\n' > f.txt; git add f.txt; git commit -qm G
    git push -q origin HEAD:refs/heads/main
    git checkout -q -b feat; printf 'x\n' >> f.txt; git add f.txt
    GIT_AUTHOR_NAME='Author A' GIT_AUTHOR_EMAIL='a@x' git commit -qm X
    git rev-parse HEAD > "$LDR/.X" ) >/dev/null 2>&1 || return 1
  LDX="$(cat "$LDR/.X")"; LDMARK="$LDR/.merged"
  printf '#!/bin/sh\ntouch %s\n' "'$LDMARK'" > "$LDR/stub"; chmod +x "$LDR/stub"
}
# _mkland_jira_fx: _mkland_fx's shape on a TRACKER repo (LAND-WRITES-CARD-STATE). G carries CLAUDE.md (jira), the conf,
# conformance/backlog-lib.sh and scripts/{board.sh,tracker-conf.sh} (real) + a COPY of the gate + stubs for board-claim.sh
# (`check` -> rc 1: no claim ref) and tracker-jira.sh (state in $STUB_STATE_FILE; STUB_TRANSITION_FAIL=1 refuses). X
# carries `Kit-Row: AB-1`. The caller sets VERIFY to the gate COPY ($LDR/c/scripts/promotion-verify.sh).
_mkland_jira_fx() {
  _jsrc="$(cd "$(dirname "$VERIFY")" && pwd)"
  LDR="$(mktemp -d)"
  git init -q --bare -b main "$LDR/origin.git" || return 1
  ( set -e
    git clone -q "$LDR/origin.git" "$LDR/c" 2>/dev/null
    cd "$LDR/c"
    git config user.email committer@example.com; git config user.name committer; git config commit.gpgsign false
    mkdir -p .kit scripts conformance
    printf 'Backlog backend: jira\n' > CLAUDE.md
    printf 'version=1\nbackend=jira\nbase_url=https://ex.atlassian.net\nflavour=cloud\nauth=basic\nproject=AB\nstate.ready=Selected for Development\nstate.in-progress=In Progress\nstate.done=Done\n' > .kit/tracker.conf
    cp "$_jsrc/../conformance/backlog-lib.sh" conformance/backlog-lib.sh
    cp "$_jsrc/board.sh" "$_jsrc/tracker-conf.sh" scripts/
    cp "$VERIFY" scripts/promotion-verify.sh
    printf '#!/bin/sh\ncase "$1" in check) exit 1 ;; *) exit 0 ;; esac\n' > scripts/board-claim.sh
    cat > scripts/tracker-jira.sh <<'JIRA_STUB'
#!/bin/sh
case "$1" in
  get-issue) printf 'key\t%s\n' "$5"; printf 'status-name\t%s\n' "$(cat "$STUB_STATE_FILE")"; exit 0 ;;
  transition) [ "${STUB_TRANSITION_FAIL:-0}" = 1 ] && exit 1; printf '%s' "$6" > "$STUB_STATE_FILE"; exit 0 ;;
  *) exit 2 ;;
esac
JIRA_STUB
    printf 'base\n' > f.txt; git add -A; git commit -qm G
    git push -q origin HEAD:refs/heads/main
    git checkout -q -b feat; printf 'x\n' >> f.txt; git add f.txt
    GIT_AUTHOR_NAME='Author A' GIT_AUTHOR_EMAIL='a@x' git commit -qm X -m 'Kit-Row: AB-1'
    git rev-parse HEAD > "$LDR/.X" ) >/dev/null 2>&1 || return 1
  LDX="$(cat "$LDR/.X")"; LDMARK="$LDR/.merged"
  printf '#!/bin/sh\ntouch %s\n' "'$LDMARK'" > "$LDR/stub"; chmod +x "$LDR/stub"
}
_L_json() { printf '%s' "$1" | sed "s/@SHA@/$LDX/g"; }
# _land_run <gh-shim-dir> <approved-by> <go-by|NONE> [extra land args] -> RC, OUT (stdout+stderr merged).
_land_run() {
  _lrg="$1"; _lrb="$2"; _lrgo="$3"; shift 3
  if [ "$_lrgo" = NONE ]; then :; else set -- --go-by "$_lrgo" "$@"; fi
  rm -f "$LDMARK"
  if OUT="$( cd "$LDR/c" && PATH="$_lrg:$PATH" PROMOTION_NOTES_REF=promotions sh "$VERIFY" land --ref "${_LREF:-260}" \
       --merge-cmd "$LDR/stub" --approved-sha "$LDX" --approved-by "$_lrb" --gate release-candidate \
       --rung "Release candidate" --class control-plane --scope "PR #260" --token "GO: land #260" "$@" 2>&1 )"; then RC=0; else RC=$?; fi
}
_land_note()  { ( cd "$LDR/c" && git notes --ref=promotions show "$LDX" 2>/dev/null ) || true; }
_land_onote() { git --git-dir="$LDR/origin.git" notes --ref=promotions show "$LDX" 2>/dev/null || true; }

# _rec_case <label> <auth|base> <reviews-json-template> <author-login-json> <notice-reason> [approver]
#   The shared REC-* driver. `@SHA@` in the template is replaced by the fixture's REAL full X sha, so
#   the resolved-SHA compare is exercised against a genuine object rather than a literal.
#   Every leg asserts the RECORDED LABEL, never a bare rc — a record NEVER fails on a derivation gap
#   (it only ever declines to upgrade), so rc alone would pass vacuously on all ten negatives.
_rec_case() {
  _cl="$1"; _ce="$2"; _ct="$3"; _ca="$4"; _cn="$5"; _cw="${6:-Reviewer B}"
  _cd="$(mkrepo)" || { fail "$_cl: fixture build"; return 0; }
  _cx="$(cat "$_cd/.X")"
  _cj="$(printf '%s' "$_ct" | sed "s/@SHA@/$_cx/g")"
  _cg="$(_mkgh "$_cj" "$_ca")"
  _run_record "$_cd" "$_cg" "PR #260" "$_cw" "$_cx"
  _cb="$(_note_of "$_cd" "$_cx")"
  _cline="$(printf '%s\n' "$_cb" | grep '^approved-by:' || true)"
  if [ "$_ce" = auth ]; then
    if [ "$RC" = 0 ] && printf '%s' "$_cline" | grep -qF "$_cw [authenticated: github-review]"; then
      pass "$_cl: qualifying forge review -> recorded [authenticated: github-review]"
    else
      fail "$_cl: expected the authenticated upgrade; rc=$RC approved-by=[$_cline] OUT=[$OUT]"
    fi
  else
    if [ "$RC" = 0 ] \
       && printf '%s' "$_cline" | grep -qF '[self-asserted]' \
       && ! printf '%s' "$_cb" | grep -q 'authenticated' \
       && printf '%s' "$OUT" | grep -qF "forge-review derivation: $_cn" \
       && printf '%s' "$OUT" | grep -qF 'recording [self-asserted]'; then
      pass "$_cl: no upgrade -> [self-asserted] kept + '$_cn' notice on stderr"
    else
      fail "$_cl: expected NO upgrade + '$_cn'; rc=$RC approved-by=[$_cline] OUT=[$OUT]"
    fi
  fi
  rm -rf "$_cd" "$_cg" 2>/dev/null || true
}

case "${1:-}" in
  --selftest)
    [ -f "$VERIFY" ] || { echo "FAIL: missing actuate producer $VERIFY"; exit 1; }
    [ -f "$GUARD" ]  || { echo "FAIL: missing guard core $GUARD"; exit 1; }
    selftest; exit $? ;;
  "")
    wiring; exit $? ;;
  *)
    echo "usage: promotion-actuate-wired.sh [--selftest]" >&2; exit 2 ;;
esac
