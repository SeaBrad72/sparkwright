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
    if ( cd "$DLC" && sh "$VERIFY" record --approved-sha "$XLC" --approved-by "Reviewer B" \
           --gate release-candidate --rung "Release candidate" --class "$_lc" \
           --scope "branch/x" --token "GO" >/dev/null 2>&1 ); then
      pass "REC-CLASS-OK: '$_lc' accepted (case-insensitive vocabulary, not a refuse-all)"
    else
      fail "REC-CLASS-OK: legal class '$_lc' was rejected"
    fi
    rm -rf "$DLC" 2>/dev/null || true
  done
  rm -rf "$DRC" 2>/dev/null || true

  if [ "$st" = 0 ]; then
    echo "OK: promotion-actuate-wired selftest — actuate gate wired + non-vacuous (wiring: 1 liveness + 6 negatives; actuate: 1 liveness + 9 negatives + guard fixtures + lock self-negative; forge-review derivation: 3 liveness + 11 negatives + the class allowlist, both ends)"
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
  */reviews) _src="$(dirname "$0")/reviews.json" ;;
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
  if OUT="$( cd "$_rd" && PATH="$_rp" sh "$VERIFY" record \
               --approved-sha "$_rx" --approved-by "$_rb" --gate release-candidate \
               --rung "Release candidate" --class Ordinary --scope "$_rs" \
               --token "GO: merge $_rs" 2>&1 )"; then RC=0; else RC=$?; fi
}

# _note_of <dir> <sha> -> the recorded note body ('' when none).
_note_of() { ( cd "$1" && git notes --ref=promotions show "$2" 2>/dev/null ) || true; }

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
