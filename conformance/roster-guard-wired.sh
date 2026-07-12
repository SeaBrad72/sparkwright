#!/bin/sh
# roster-guard-wired.sh — behavioural conformance for the roster-authority guard dial (Slice B).
#
# Claim `roster-guard`: the opt-in Skill dial in guard-core.sh (guard_check_skill) behaves per
# mode, is FAIL-SAFE toward off, honours the KIT_ROSTER_GUARD=off session override, and is actually
# WIRED (settings.json matcher admits `Skill`; guard.sh has a `Skill)` case). Behaviour is driven
# against a real guard-core by pointing guard_check_skill at a temp config (KIT_ROSTER_CONF) — no
# reliance on the shipped dial being ON (it ships OFF; correctness is proven by fixtures).
#
# Overridable (defaults = the real kit files; overridden by --selftest / this task's scratch proof):
#   GUARD_CORE   (default .claude/hooks/guard-core.sh)  — sourced for guard_check_skill
#   SETTINGS_DOC (default .claude/settings.json)        — structural: matcher admits Skill
#   GUARD_SH_DOC (default .claude/hooks/guard.sh)       — structural: has a Skill) case
#
#   sh conformance/roster-guard-wired.sh            (main: behavioural + structural)
#   sh conformance/roster-guard-wired.sh --selftest (anchor + non-vacuity: a dead core FAILS)
# Exit: 0 = OK · 1 = FAIL · 2 = UNVERIFIED (jq absent for the structural matcher test). POSIX sh; dash-clean.
set -eu

GUARD_CORE="${GUARD_CORE:-.claude/hooks/guard-core.sh}"
SETTINGS_DOC="${SETTINGS_DOC:-.claude/settings.json}"
GUARD_SH_DOC="${GUARD_SH_DOC:-.claude/hooks/guard.sh}"

# --- main check: behavioural (6 direct modes) + structural (2 wiring) + e2e (4 adapter cases) --
run_checks() {
  [ -r "$GUARD_CORE" ] || { echo "FAIL: cannot read guard-core ($GUARD_CORE)"; return 1; }
  # shellcheck source=/dev/null
  . "$GUARD_CORE"
  command -v guard_check_skill >/dev/null 2>&1 || { echo "FAIL: guard_check_skill not defined in $GUARD_CORE"; return 1; }

  fail=0
  unverified=0
  cfg=$(mktemp)   # left in place (no rm; 7e guard) — one reusable temp config
  missing=$(mktemp); rm -f "$missing"  # a path guaranteed NOT to exist (fail-safe case)

  mkconf() { printf 'MODE=%s\nBLOCKLIST=%s\n' "$1" "$2" > "$cfg"; }

  # verdict <label> <skill> <expected-token>   (reads current KIT_ROSTER_CONF / KIT_ROSTER_GUARD)
  verdict() {
    _got=$(guard_check_skill "$2" | head -n1 || printf '?')
    if [ "$_got" = "$3" ]; then echo "PASS: $1 -> $3"; else echo "FAIL: $1 (expected $3, got '$_got')"; fail=1; fi
  }

  # 1. MODE=off -> a blocklisted skill is still ALLOWED (ships off; anchor negative-of-teeth).
  mkconf off superpowers
  KIT_ROSTER_GUARD='' KIT_ROSTER_CONF="$cfg" verdict "MODE=off superpowers:brainstorming" superpowers:brainstorming allow
  # 2. MODE=deny -> blocklisted namespace DENIED (the teeth; a live positive).
  mkconf deny superpowers
  KIT_ROSTER_GUARD='' KIT_ROSTER_CONF="$cfg" verdict "MODE=deny superpowers:brainstorming" superpowers:brainstorming deny
  # 3. MODE=deny -> a utility namespace not on the blocklist stays ALLOWED (no over-block).
  KIT_ROSTER_GUARD='' KIT_ROSTER_CONF="$cfg" verdict "MODE=deny figma:make (utility)" figma:make allow
  # 4. MODE=ask -> blocklisted namespace routes to ASK.
  mkconf ask superpowers
  KIT_ROSTER_GUARD='' KIT_ROSTER_CONF="$cfg" verdict "MODE=ask superpowers:tdd" superpowers:tdd ask
  # 5. config missing/unreadable -> ALLOW (fail-safe; must never wedge).
  KIT_ROSTER_GUARD='' KIT_ROSTER_CONF="$missing" verdict "config missing -> fail-safe" superpowers:brainstorming allow
  # 6. KIT_ROSTER_GUARD=off overrides a deny config -> ALLOW (preference, not prohibition).
  mkconf deny superpowers
  KIT_ROSTER_GUARD=off KIT_ROSTER_CONF="$cfg" verdict "KIT_ROSTER_GUARD=off overrides deny" superpowers:brainstorming allow

  # 7a. structural: guard.sh has a Skill) case.
  if [ -r "$GUARD_SH_DOC" ] && grep -Eq '^[[:space:]]*Skill\)' "$GUARD_SH_DOC"; then
    echo "PASS: guard.sh has a Skill) case ($GUARD_SH_DOC)"
  else
    echo "FAIL: $GUARD_SH_DOC has no Skill) case — the dial would be unwired"; fail=1
  fi
  # 7b. structural: settings.json PreToolUse matcher (for the guard.sh hook) ADMITS the Skill tool.
  if [ ! -r "$SETTINGS_DOC" ]; then
    echo "FAIL: cannot read $SETTINGS_DOC"; fail=1
  elif command -v jq >/dev/null 2>&1; then
    _m=$(jq -r '.hooks.PreToolUse[]? | select(any(.hooks[]?; (.command // "") | test("guard\\.sh"))) | .matcher // empty' "$SETTINGS_DOC" 2>/dev/null | head -n1)
    if [ -z "$_m" ]; then
      echo "FAIL: could not resolve the guard.sh PreToolUse matcher in $SETTINGS_DOC"; fail=1
    elif printf 'Skill\n' | grep -Eq "^($_m)$" 2>/dev/null; then
      echo "PASS: settings.json matcher '$_m' admits the Skill tool"
    else
      echo "FAIL: settings.json matcher '$_m' does NOT admit Skill — the dial would be DARK"; fail=1
    fi
  else
    echo "UNVERIFIED: jq absent — cannot structurally confirm the Skill matcher; install jq"; unverified=1
  fi

  # 8. e2e ADAPTER path: pipe REAL Skill tool JSON through guard.sh ($GUARD_SH_DOC) and assert the
  #    emitted permissionDecision. The direct cases (1-6) exercise guard_check_skill in isolation;
  #    these exercise the WHOLE adapter — JSON field extraction of `.tool_input.skill` + the
  #    token->permissionDecision mapping (ask/deny/allow) — pinning the `.tool_input.skill` field
  #    name. Mirrors conformance/agent-autonomy.sh's e2e style (JSON in -> decision asserted).
  #    jq is required for guard.sh; jq-absent => UNVERIFIED (three-state, like 7b above).
  skill_json='{"tool_name":"Skill","tool_input":{"skill":"superpowers:brainstorming"}}'
  util_json='{"tool_name":"Skill","tool_input":{"skill":"figma:make"}}'
  if [ ! -r "$GUARD_SH_DOC" ]; then
    echo "FAIL: cannot read the guard.sh adapter ($GUARD_SH_DOC) for the e2e path"; fail=1
  elif ! command -v jq >/dev/null 2>&1; then
    echo "UNVERIFIED: jq absent — cannot pipe Skill JSON through the guard.sh adapter; install jq"; unverified=1
  else
    # e2e <label> <json> <expected: deny|ask|allow>  (reads the current $cfg via KIT_ROSTER_CONF)
    e2e() {
      _out=$(printf '%s' "$2" | KIT_ROSTER_GUARD='' KIT_ROSTER_CONF="$cfg" sh "$GUARD_SH_DOC" 2>/dev/null || true)
      if [ "$3" = allow ]; then
        if [ -z "$_out" ]; then echo "PASS(e2e): $1 -> allow (no JSON emitted)"; else echo "FAIL(e2e): $1 (expected allow/no-JSON, got '$_out')"; fail=1; fi
      elif printf '%s' "$_out" | grep -q "\"permissionDecision\":\"$3\""; then
        echo "PASS(e2e): $1 -> permissionDecision $3"
      else
        echo "FAIL(e2e): $1 (expected permissionDecision $3, got '$_out')"; fail=1
      fi
    }
    mkconf deny superpowers; e2e "MODE=deny superpowers:brainstorming (adapter)" "$skill_json" deny
    mkconf ask  superpowers; e2e "MODE=ask superpowers:brainstorming (adapter)"  "$skill_json" ask
    mkconf off  superpowers; e2e "MODE=off superpowers:brainstorming (adapter)"  "$skill_json" allow
    mkconf deny superpowers; e2e "MODE=deny figma:make utility (adapter)"        "$util_json"  allow
  fi

  [ "$fail" -eq 0 ] || { echo "roster-guard: FAIL (see reasons above)" >&2; return 1; }
  [ "$unverified" -eq 0 ] || { echo "roster-guard: UNVERIFIED (behaviour OK; matcher/adapter not fully confirmed)" >&2; return 2; }
  echo "roster-guard: OK (6 direct mode cases + 4 e2e adapter cases; Skill) case + matcher wired)"
  return 0
}

# --- selftest: anchor (real/scratch core passes) + non-vacuity (a dead core FAILS) ------------
selftest() {
  st=0
  # Anchor: the configured core (env-inherited scratch in this task, real files in CI) passes.
  if run_checks >/dev/null 2>&1; then rc=0; else rc=$?; fi
  case "$rc" in
    0) echo "selftest PASS: configured guard-core -> OK (all mode + wiring cases pass)" ;;
    2) echo "selftest PASS: configured guard-core -> UNVERIFIED (jq absent; behaviour still ran)" ;;
    *) echo "selftest FAIL: configured guard-core should pass (got $rc)"; st=1 ;;
  esac

  # Non-vacuity: a DEAD core (guard_check_skill always prints allow) must FAIL >=1 case
  # (the MODE=deny and MODE=ask assertions), proving the check has real teeth.
  dead=$(mktemp)
  printf '%s\n' '#!/bin/sh' 'guard_check_skill() { printf "allow\n"; return 0; }' > "$dead"
  if GUARD_CORE="$dead" run_checks >/dev/null 2>&1; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ]; then
    echo "selftest PASS: dead always-allow core -> FAIL (non-vacuous)"
  else
    echo "selftest FAIL: dead core should FAIL the deny/ask cases (got $rc)"; st=1
  fi

  [ "$st" -eq 0 ] || { echo "roster-guard-wired --selftest: FAIL" >&2; return 1; }
  echo "roster-guard-wired --selftest: OK (anchor passes; dead always-allow core fails -> non-vacuous)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "")         run_checks; exit $? ;;
  *)          echo "usage: roster-guard-wired.sh [--selftest]" >&2; exit 2 ;;
esac
