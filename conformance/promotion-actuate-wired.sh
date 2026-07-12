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
# HONEST CEILING: this lock proves the GATE is wired + non-vacuous (the [authenticated: <forge>-
# review] bar, the approver!=author SoD teeth, the tree-equality re-check, and the guard --admin deny
# are all real and LOAD-BEARING). It does NOT prove the live `gh pr merge`, the forge-review ->
# [authenticated: <forge>-review] derivation (the vc-hosts seam), or a real team credential — those
# are documented seams, fixture-proven here with a swappable --merge-cmd stub + a fabricated
# authenticated note. The LOCK SELF-NEGATIVE (below) proves the lock ITSELF is non-vacuous: a
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
write_note() { # dir sha approved-by-value [basis]
  _dir="$1"; _s="$2"; _aby="$3"; _basis="${4:-reviewer APPROVE}"
  printf '%s\n' \
    "record: promotion GO (fabricated fixture note)" \
    "approved-sha: $_s" \
    "approved-by: $_aby" \
    "gate: release-candidate" \
    "rung: Release candidate" \
    "change-class: Control-plane" \
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

  if [ "$st" = 0 ]; then
    echo "OK: promotion-actuate-wired selftest — actuate gate wired + non-vacuous (wiring: 1 liveness + 6 negatives; actuate: 1 liveness + 9 negatives + guard fixtures + lock self-negative)"
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
