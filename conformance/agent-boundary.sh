#!/bin/sh
# agent-boundary.sh — CI-side, harness-independent enforcement of the DEVELOPMENT-PROCESS.md §13
# agent boundary: a PR diff that touches a CONTROL-PLANE path must carry an explicit HUMAN
# ratification signal (a CODEOWNER (non-author) approval on those paths). This is the
# enforcement floor that holds on EVERY harness — incl. a harness with no inline guard — because CI
# catches an unratified control-plane edit post-hoc, before merge.
#
# Pure decision via boundary_decide(): the CI job computes the inputs (changed-file listing +
# ratified flag) from the PR event and passes them in, so this stays deterministic + --selftest-able.
# Reuses guard-core.sh::is_control_plane_path — the SINGLE SOURCE OF TRUTH for the control-plane set
# (no forked path list; this is another honored consumer of the core).
#
# THREE-STATE: 0 = boundary holds · 1 = violated (unratified control-plane change) · 2 = UNVERIFIED
#   (changed-file listing unavailable). 2 escalates to 1 under CI (CI env) or --require — a gate must
#   be runnable. See conformance/branch-protection.sh for the same contract.
#
#   usage: sh conformance/agent-boundary.sh --changed <listing-file> --ratified <0|1> [--require]
#          sh conformance/agent-boundary.sh --selftest
set -eu

REQUIRE="${REQUIRE:-0}"
[ -n "${CI:-}" ] && REQUIRE=1
CHANGED=""
RATIFIED="0"
MODE="run"
while [ $# -gt 0 ]; do
  case "$1" in
    --changed) CHANGED="${2:-}"; shift 2 ;;
    --ratified) RATIFIED="${2:-0}"; shift 2 ;;
    --require) REQUIRE=1; shift ;;
    --selftest) MODE="selftest"; shift ;;
    --state) MODE="state"; shift ;;
    *) echo "usage: agent-boundary.sh --changed <file> --ratified <0|1> [--require] | --selftest" >&2; exit 2 ;;
  esac
done

# Resolve + source the deny-matrix core (the control-plane path set lives there).
CORE="${KIT_GUARD_CORE:-$(dirname "$0")/../.claude/hooks/guard-core.sh}"
# adapters/ registry — beyond the kit-standard guard-core set, the gate also protects each harness's
# OWN declared control-plane surface: the union of controlPlanePaths across adapters/*/adapter.json
# (P1 / N5 — turns the manifest's declarative inventory into real enforcement).
ADAPTERS_DIR="${KIT_ADAPTERS_DIR:-$(dirname "$0")/../adapters}"

# adapter_union: echo the union of controlPlanePaths across adapters/*/adapter.json (sorted-unique).
# jq-absent or no adapters/ -> empty union (the hardcoded guard-core floor still applies regardless).
adapter_union() {
  command -v jq >/dev/null 2>&1 || return 0
  [ -d "$ADAPTERS_DIR" ] || return 0
  for _m in "$ADAPTERS_DIR"/*/adapter.json; do
    [ -f "$_m" ] || continue
    jq -r '.controlPlanePaths[]? // empty' "$_m" 2>/dev/null
  done | sort -u
}

# path_in_union <path> <union-list>: 0 if <path> matches a union entry — exact, or a directory-prefix
# entry ending in '/'. Union entries never contain spaces, so word-splitting the list is safe.
path_in_union() {
  _pp=$1; _u=$2
  for _e in $_u; do
    [ "$_pp" = "$_e" ] && return 0
    case "$_e" in */) case "$_pp" in "$_e"*) return 0 ;; esac ;; esac
  done
  return 1
}

unverifiable() {  # <reason>
  if [ "$REQUIRE" = "1" ]; then
    echo "FAIL: agent-boundary could not verify ($1) and verification is required (CI/--require)."
    exit 1
  fi
  echo "UNVERIFIED: $1 — provide --changed <listing> in a PR context. (NOT a pass.)"
  exit 2
}

# boundary_decide <newline-separated-paths> <ratified 0|1>: print verdict; return 0 ok / 1 violation.
# Kept pure so the selftest can exercise it in-process (an env var must never force a pass).
boundary_decide() {
  _list=$1; _rat=$2; _union=${3:-}; _hits=""
  # Read the listing line-by-line in the CURRENT shell (heredoc, not a pipe) so _hits persists.
  # A path is control-plane if guard-core's hardcoded set knows it OR an adapter declared it (union).
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    if is_control_plane_path "$_p" || path_in_union "$_p" "$_union"; then _hits="$_hits $_p"; fi
  done <<EOF
$_list
EOF
  if [ -n "$_hits" ]; then
    if [ "$_rat" = "1" ]; then
      echo "OK: control-plane change present and ratified —$_hits"; return 0
    fi
    echo "FAIL: unratified control-plane change —$_hits"; return 1
  fi
  echo "OK: no control-plane paths in the diff"; return 0
}

# ratification_state <newline-paths> <ratified 0|1> [<union>]: the honest SoD state label for the
# human GO. PURE (no env can force it; the selftest drives it directly). A PRE-MERGE PROJECTION —
# it names the SoD reality the merge will have, it does not observe the future keystroke.
#   control-plane present + ratified=1 -> RATIFIED-BY-SECOND-REVIEWER (team; SoD genuinely exercised)
#   control-plane present + ratified=0 -> SOLO-ADMIN-OVERRIDE-LOGGED  (solo; logged admin-override)
#   no control-plane path              -> NONE (N/A — nothing to ratify)
ratification_state() {
  _list=$1; _rat=$2; _union=${3:-}; _cp=0
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    if is_control_plane_path "$_p" || path_in_union "$_p" "$_union"; then _cp=1; break; fi
  done <<EOF
$_list
EOF
  [ "$_cp" = 1 ] || { echo NONE; return 0; }
  if [ "$_rat" = 1 ]; then echo RATIFIED-BY-SECOND-REVIEWER; else echo SOLO-ADMIN-OVERRIDE-LOGGED; fi
}

run() {
  [ -f "$CORE" ] || unverifiable "deny-matrix core not found at $CORE (set KIT_GUARD_CORE)"
  # shellcheck disable=SC1090  # core path is resolved at runtime, intentionally dynamic
  . "$CORE"
  [ -n "$CHANGED" ] || unverifiable "no --changed listing supplied"
  [ -f "$CHANGED" ] || unverifiable "--changed listing not found: $CHANGED"
  _paths=$(cat "$CHANGED")
  _union=$(adapter_union)
  if boundary_decide "$_paths" "$RATIFIED" "$_union"; then exit 0; else exit 1; fi
}

selftest() {
  st=0
  # source the core so is_control_plane_path is available to boundary_decide in-process
  [ -f "$CORE" ] || { echo "selftest FAIL: core not found at $CORE"; return 1; }
  # shellcheck disable=SC1090
  . "$CORE"
  dc() {  # expect_rc paths ratified label [union]
    e=$1; p=$2; r=$3; lbl=$4; u=${5:-}
    ( boundary_decide "$p" "$r" "$u" ) >/dev/null && g=0 || g=$?
    if [ "$g" = "$e" ]; then echo "selftest PASS: $lbl -> rc $g"; else echo "selftest FAIL: $lbl want $e got $g"; st=1; fi
  }
  dc 0 "src/app.ts
README.md" 0 "ordinary diff, unratified -> PASS"
  dc 1 "src/app.ts
.github/workflows/ci.yml" 0 "workflow change, unratified -> FAIL"
  dc 0 "src/app.ts
.github/workflows/ci.yml" 1 "workflow change, ratified -> PASS"
  dc 1 "CODEOWNERS" 0 "CODEOWNERS change, unratified -> FAIL"
  dc 0 "" 0 "empty diff -> PASS"
  dc 1 "conformance/agent-boundary.sh" 0 "conformance change, unratified -> FAIL"
  dc 0 "conformance/agent-boundary.sh" 1 "conformance change, ratified -> PASS"
  dc 1 "DEVELOPMENT-STANDARDS.md" 0 "standards doc change, unratified -> FAIL"
  dc 1 "CLAUDE.md" 0 "CLAUDE.md change, unratified -> FAIL"
  dc 1 "adapters/generic/adapter.json" 0 "adapter manifest change, unratified -> FAIL"
  dc 0 "scripts/deploy.sh" 0 "adopter own script (not kit) -> PASS"

  # N5 union: a path declared ONLY in an adapter manifest's controlPlanePaths (NOT in guard-core's
  # hardcoded set) is now caught — proving the gate enforces what adapters declare, per harness.
  dc 1 ".cursor/rules" 0 "adapter-union path, unratified -> FAIL" ".cursor/rules .github/workflows/"
  dc 0 ".cursor/rules" 1 "adapter-union path, ratified -> PASS" ".cursor/rules .github/workflows/"
  dc 0 "src/app.ts" 0 "non-union ordinary path -> PASS" ".cursor/rules"
  dc 1 ".cursor/rules/foo.md" 0 "dir-prefix union entry -> FAIL" ".cursor/rules/"

  # slice 3: the honest SoD state label (pure ratification_state, driven in-process)
  rs() {  # expect label paths ratified [union]
    e=$1; p=$2; r=$3; u=${4:-}; g=$(ratification_state "$p" "$r" "$u")
    if [ "$g" = "$e" ]; then echo "selftest PASS: state $e"; else echo "selftest FAIL: state want $e got $g"; st=1; fi
  }
  rs RATIFIED-BY-SECOND-REVIEWER ".github/workflows/ci.yml" 1 ""
  rs SOLO-ADMIN-OVERRIDE-LOGGED  ".github/workflows/ci.yml" 0 ""
  rs NONE                        "src/app.ts" 0 ""
  # load-bearing negative: an always-team mutation flips the solo case above; assert distinction too
  if [ "$(ratification_state '.github/workflows/ci.yml' 0)" = "$(ratification_state '.github/workflows/ci.yml' 1)" ]; then
    echo "selftest FAIL: solo/team labels identical (vacuous)"; st=1; fi

  # three-state CLI: no --changed is UNVERIFIED (exit 2) locally, FAIL (exit 1) under CI/--require.
  miss=$(mktemp -d)  # fixtures left in place (no rm; 7e guard)
  printf '.github/workflows/ci.yml\n' > "$miss/cp.txt"
  printf 'src/app.ts\n' > "$miss/clean.txt"
  # shellcheck disable=SC1007  # CI= intentionally clears the var for the subprocess
  CI= REQUIRE=0 sh "$0" --ratified 0 >/dev/null && r=0 || r=$?
  if [ "$r" = "2" ]; then echo "selftest PASS: no --changed local -> exit 2 (UNVERIFIED)"; else echo "selftest FAIL: no --changed local want 2 got $r"; st=1; fi
  CI=true sh "$0" --ratified 0 >/dev/null && r=0 || r=$?
  if [ "$r" = "1" ]; then echo "selftest PASS: no --changed + CI -> exit 1 (escalation)"; else echo "selftest FAIL: no --changed + CI want 1 got $r"; st=1; fi
  # end-to-end CLI over a real listing file
  sh "$0" --changed "$miss/cp.txt" --ratified 0 >/dev/null && r=0 || r=$?
  if [ "$r" = "1" ]; then echo "selftest PASS: cli unratified control-plane -> exit 1"; else echo "selftest FAIL: cli cp unratified want 1 got $r"; st=1; fi
  sh "$0" --changed "$miss/cp.txt" --ratified 1 >/dev/null && r=0 || r=$?
  if [ "$r" = "0" ]; then echo "selftest PASS: cli ratified control-plane -> exit 0"; else echo "selftest FAIL: cli cp ratified want 0 got $r"; st=1; fi
  sh "$0" --changed "$miss/clean.txt" --ratified 0 >/dev/null && r=0 || r=$?
  if [ "$r" = "0" ]; then echo "selftest PASS: cli clean diff -> exit 0"; else echo "selftest FAIL: cli clean want 0 got $r"; st=1; fi

  # N5 integration: drive the FULL run() path (real adapter_union from this repo's adapters/) over a
  # path that ONLY the union protects (AGENTS.md, declared by the generic adapter, not in guard-core).
  printf 'AGENTS.md\n' > "$miss/agents.txt"
  if command -v jq >/dev/null 2>&1 && [ -d "$ADAPTERS_DIR" ]; then
    sh "$0" --changed "$miss/agents.txt" --ratified 0 >/dev/null && r=0 || r=$?
    if [ "$r" = "1" ]; then echo "selftest PASS: cli AGENTS.md via real adapter union, unratified -> exit 1"; else echo "selftest FAIL: cli AGENTS.md union want 1 got $r"; st=1; fi
    sh "$0" --changed "$miss/agents.txt" --ratified 1 >/dev/null && r=0 || r=$?
    if [ "$r" = "0" ]; then echo "selftest PASS: cli AGENTS.md via real adapter union, ratified -> exit 0"; else echo "selftest FAIL: cli AGENTS.md union ratified want 0 got $r"; st=1; fi
  else
    echo "selftest SKIP: real adapter-union integration (jq or adapters/ absent)"
  fi

  [ "$st" = "0" ] && echo "agent-boundary --selftest: OK"
  return "$st"
}

state() {  # advisory label for the CI human-surface; CI-independent, always exit 0
  [ -f "$CORE" ] || { echo NONE; exit 0; }
  # shellcheck disable=SC1090
  . "$CORE"
  { [ -n "$CHANGED" ] && [ -f "$CHANGED" ]; } || { echo NONE; exit 0; }
  ratification_state "$(cat "$CHANGED")" "$RATIFIED" "$(adapter_union)"
  exit 0
}

case "$MODE" in
  selftest) selftest; exit $? ;;
  state) state ;;
  *) run ;;
esac
