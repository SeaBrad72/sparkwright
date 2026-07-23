#!/bin/sh
# harness-ceiling-disclosed.sh — verifies incept discloses the enforcement CEILING
# (no inline PreToolUse-equivalent interception) for every selected harness whose
# adapter declares command-guard != native, and does NOT falsely claim it for a
# native harness. Closes K4 / AC1.
#
# The signal is data-driven + single-source: adapters/<h>/adapter.json ->
#   .dimensions["command-guard"].level. "native" (claude-code) has inline interception
#   => NO ceiling; anything else (floor/n-a: codex, cursor, gemini, generic) => the
#   ceiling is disclosed. This gate drives a REAL incept for a floor harness (codex,
#   the live representative) and asserts the ceiling notice is PRESENT and names the
#   harness, and drives one for a native harness (claude-code) and asserts it is ABSENT
#   (the load-bearing anti-overclaim leg). The rest of the fleet is covered by a
#   registry-coverage assertion over the SAME jq classifier the emission uses (logged,
#   never a silent cap) — a full incept per adapter is redundant given the emission is
#   purely data-driven from that one classifier.
#
# What it changes: nothing (read-only verification; drives incept in a temp dir).
# Guardrails: three-state (0 ok · 1 violation · 2 UNVERIFIED); harness set from adapters/ registry + literal fixtures, never env.
#
# HONEST CEILING: proves the disclosure fires with a discriminating token for a floor
# harness and stays silent for a native one, driven by the adapter's declared level. It
# does NOT re-prove a harness's runtime lacks a hook — that is harness-adapter.sh's
# lying-native guard.
#   sh conformance/harness-ceiling-disclosed.sh            # real run (drives incept)
#   sh conformance/harness-ceiling-disclosed.sh --selftest # mutation proof it has teeth
# Exit: 0 = ok · 1 = violation · 2 = UNVERIFIED (jq/git absent, setup failed). POSIX sh.
set -eu

DISCRIMINATOR='PreToolUse'          # the token a truthful ceiling notice MUST contain
NATIVE_HARNESS='claude-code'        # command-guard: native (the negative/anti-overclaim anchor)
FLOOR_HARNESS='codex'               # command-guard: floor (the positive liveness anchor)

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
if [ -d "$SCRIPT_DIR/../profiles" ]; then
  REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
elif [ -d "$SCRIPT_DIR/../../profiles" ]; then
  REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
else
  REPO_ROOT="$SCRIPT_DIR"
fi

# Kit-self N/A guard — HOISTED above the jq/git preconditions (CP7R5-KITSELF-NA-ORDERING; mirrors
# pipeline-origin.sh, which already orders it this way). This check DRIVES incept via `git archive HEAD`
# + a real incept, meaningless on an already-incepted adopter tree. It MUST N/A (rc 0) there BEFORE the
# jq/git preconditions can return UNVERIFIED (rc 2) — otherwise an adopter without git scores a check that
# does not apply to them as a FAILURE (verify.sh --require treats UNVERIFIED as a failure). N/A when BOTH
# kit markers are absent (the export strips both; golden-path.yml is control-plane + export-ignored, so the
# marker set is un-spoofable). Placed before the mode dispatch so it covers BOTH `run` and `--selftest`.
if [ ! -f "$REPO_ROOT/docs/ROADMAP-KIT.md" ] && [ ! -f "$REPO_ROOT/.github/workflows/golden-path.yml" ]; then
  echo "harness-ceiling-disclosed: N/A — kit-self check (not applicable outside the kit repo)"
  exit 0
fi

command -v jq  >/dev/null 2>&1 || { echo "UNVERIFIED: jq not installed (the adapter manifest is JSON)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "UNVERIFIED: git not installed (needed to build the pristine export)"; exit 2; }

# One temp root for the whole run; trap-cleaned on ANY exit (no disk leak).
TMPROOT=$(mktemp -d) || { echo "UNVERIFIED: mktemp failed"; exit 2; }
# shellcheck disable=SC2064 # expand TMPROOT now — it is fixed for the life of the process
trap "rm -rf '$TMPROOT'" EXIT

PRISTINE="$TMPROOT/pristine"
INCEPT_OUT=''

# make_pristine_export — build ONCE the tree an adopter actually incepts. Mirrors
# conformance/incept-first-run-green.sh:make_pristine_export: `git archive HEAD` (export
# semantics), then OVERLAY the worktree content of every modified tracked file so the run
# exercises the incept.sh UNDER CHANGE, not the committed one (a no-op in CI where HEAD is
# the tree under test; load-bearing during development — it is what makes RED->GREEN real).
make_pristine_export() {
  mkdir -p "$PRISTINE"
  ( cd "$REPO_ROOT" && git archive HEAD ) | ( cd "$PRISTINE" && tar -xf - ) || return 1
  _mods=$( cd "$REPO_ROOT" && git diff --name-only HEAD ) || return 1
  for _mf in $_mods; do
    [ -f "$PRISTINE/$_mf" ] || continue          # export-ignored or deleted -> not in the adopter tree
    cp "$REPO_ROOT/$_mf" "$PRISTINE/$_mf" || return 1
  done
  # Setup anchors — fail LOUDLY rather than green the assertions below against a broken fixture.
  [ -f "$PRISTINE/scripts/incept.sh" ]              || return 1
  [ -f "$PRISTINE/adapters/$FLOOR_HARNESS/adapter.json" ]  || return 1
  [ -f "$PRISTINE/adapters/$NATIVE_HARNESS/adapter.json" ] || return 1
  return 0
}

fresh_tree() {  # echo a fresh, un-incepted copy of the pristine export
  # mktemp (not a persisted counter): fresh_tree is called via `_t=$(fresh_tree)`, i.e. in a
  # SUBSHELL, so a counter increment would not survive to the parent — every call would return
  # the SAME path, and the second incept would hit an already-incepted tree (error, no notice)
  # and VACUOUSLY pass the negative leg. mktemp is unique per call regardless of subshell.
  _ft=$(mktemp -d "$TMPROOT/t.XXXXXX") || return 1
  cp -R "$PRISTINE/." "$_ft/" || return 1
  printf '%s\n' "$_ft"
}

run_incept() {  # <tree> <harness> -> rc; combined output in $INCEPT_OUT
  _it="$1"; _h="$2"
  if INCEPT_OUT=$( cd "$_it" && sh scripts/incept.sh --name CeilingProbe --intent-owner probe \
       --stack typescript-node --backlog md --ci github --harness "$_h" --noninteractive 2>&1 ); then
    return 0
  else
    return $?
  fi
}

# Positive (liveness): the ceiling notice must be PRESENT for a floor harness AND name it
# (token + harness on the SAME line). On miss: the discriminating FAIL message + return 1.
assert_ceiling_present() {  # <tree> <harness>
  run_incept "$1" "$2" || true   # incept's rc is not the assertion — the emitted notice is
  if printf '%s\n' "$INCEPT_OUT" | grep -F "$DISCRIMINATOR" | grep -qF "$2"; then
    return 0
  fi
  echo "FAIL: $2 disclosure omits the $DISCRIMINATOR ceiling"
  return 1
}

# Negative (load-bearing, AC1 anti-overclaim): the ceiling notice must be ABSENT for a
# native harness. On violation: the discriminating FAIL message + return 1.
assert_ceiling_absent() {  # <tree> <harness>
  run_incept "$1" "$2" || true
  # Symmetric with assert_ceiling_present (Security L1): a violation is the ceiling token AND
  # the harness name on the SAME line — the emitted notice's shape. Scoping to that line (vs a
  # whole-output token grep) avoids a spurious FAIL should PreToolUse ever appear elsewhere in
  # incept's output; the fail direction was already safe, this makes it precise.
  if printf '%s\n' "$INCEPT_OUT" | grep -F "$DISCRIMINATOR" | grep -qF "$2"; then
    echo "FAIL: $2 (native) falsely claims the no-inline ceiling"
    return 1
  fi
  return 0
}

run() {
  make_pristine_export || { echo "UNVERIFIED: could not build the pristine export tree (fail-closed)"; exit 2; }

  # (1) POSITIVE liveness: codex (floor) -> ceiling PRESENT and names the harness.
  _t=$(fresh_tree) || { echo "UNVERIFIED: could not stage a fresh tree"; exit 2; }
  assert_ceiling_present "$_t" "$FLOOR_HARNESS" || exit 1
  echo "OK: $FLOOR_HARNESS (floor) discloses the $DISCRIMINATOR ceiling (live incept)."

  # (2) NEGATIVE anti-overclaim: claude-code (native) -> ceiling ABSENT.
  _t=$(fresh_tree) || { echo "UNVERIFIED: could not stage a fresh tree"; exit 2; }
  assert_ceiling_absent "$_t" "$NATIVE_HARNESS" || exit 1
  echo "OK: $NATIVE_HARNESS (native) does NOT claim the ceiling (live incept)."

  # (3) FLEET-GENERAL registry coverage: every adapter whose declared command-guard level
  #     is != native is covered by-construction — the emission's classifier is this exact jq
  #     read, so a non-native declaration guarantees the notice fires. Logged, never capped.
  _covered=0; _native=0
  for _adj in "$REPO_ROOT"/adapters/*/adapter.json; do
    [ -f "$_adj" ] || continue
    _h=$(basename "$(dirname "$_adj")")
    _lvl=$(jq -r '.dimensions["command-guard"].level // "floor"' "$_adj" 2>/dev/null || echo floor)
    if [ "$_lvl" = "native" ]; then
      echo "  [registry] $_h -> native (has inline interception; no ceiling — correctly excluded)"
      _native=$((_native + 1))
    else
      echo "  [registry] $_h -> $_lvl (ceiling applies; covered by-construction — same jq classifier the emission uses)"
      _covered=$((_covered + 1))
    fi
  done
  [ "$_covered" -gt 0 ] || { echo "FAIL: no non-native adapters found in the registry (fail-closed)"; exit 1; }

  echo "OK: harness-ceiling-disclosed — ceiling PRESENT for a floor harness (live), ABSENT for native (live); $_covered non-native adapter(s) covered by the registry classifier, $_native native excluded."
  exit 0
}

# --selftest — the NON-VACUITY heart: two mutants of incept.sh, each of which MUST flip a
# leg RED with its discriminating message (assert the MESSAGE, not just exit 1 — Slice-3
# lesson: an exit-code-only assertion can be faked by a usage/other non-zero exit).
selftest() {
  st=0
  make_pristine_export || { echo "selftest FAIL: could not build the pristine export tree (fail-closed)"; return 1; }

  # --- Mutant A: the ceiling `echo` is DELETED. The positive leg MUST go RED with the
  #     "omits the ... ceiling" message. (If it still passed, the assertion is vacuous.) ---
  _t=$(fresh_tree) || { echo "selftest FAIL: mutant A — no tree"; return 1; }
  _mut="$_t/scripts/incept.sh"
  grep -vF 'Control-plane enforcement is limited to the local pre-push hook' "$_mut" > "$_mut.mut" && mv "$_mut.mut" "$_mut"
  if grep -qF 'Control-plane enforcement is limited to the local pre-push hook' "$_mut"; then
    echo "selftest FAIL: mutant A setup — the ceiling echo was not removed from the copy"; st=1
  elif out=$(assert_ceiling_present "$_t" "$FLOOR_HARNESS" 2>&1); then
    echo "selftest FAIL: mutant A (emission deleted) — the positive leg still PASSED (VACUOUS): $out"; st=1
  elif printf '%s\n' "$out" | grep -qF "omits the $DISCRIMINATOR ceiling"; then
    echo "selftest PASS: mutant A (emission deleted) caught -> $out"
  else
    echo "selftest FAIL: mutant A went RED but WITHOUT the 'omits the ... ceiling' message: $out"; st=1
  fi

  # --- Mutant B: the condition `= native` is INVERTED to `!= native`, so the notice would
  #     print for claude-code (native) and not for codex. The NEGATIVE leg MUST go RED with
  #     "falsely claims". ---
  _t=$(fresh_tree) || { echo "selftest FAIL: mutant B — no tree"; return 1; }
  _mut="$_t/scripts/incept.sh"
  # shellcheck disable=SC2016 # single-quote literal is INTENTIONAL: match/replace the source text, no expansion
  sed 's/\[ "$_lvl" = "native" \]/[ "$_lvl" != "native" ]/' "$_mut" > "$_mut.mut" && mv "$_mut.mut" "$_mut"
  # shellcheck disable=SC2016 # single-quote literal is INTENTIONAL: assert the source line changed, no expansion
  if ! grep -qF '[ "$_lvl" != "native" ]' "$_mut"; then
    echo "selftest FAIL: mutant B setup — the condition was not inverted in the copy"; st=1
  elif out=$(assert_ceiling_absent "$_t" "$NATIVE_HARNESS" 2>&1); then
    echo "selftest FAIL: mutant B (condition inverted) — the negative leg still PASSED (VACUOUS): $out"; st=1
  elif printf '%s\n' "$out" | grep -qF "falsely claims"; then
    echo "selftest PASS: mutant B (condition inverted) caught -> $out"
  else
    echo "selftest FAIL: mutant B went RED but WITHOUT the 'falsely claims' message: $out"; st=1
  fi

  if [ "$st" = 0 ]; then
    echo "OK: harness-ceiling-disclosed selftest — BOTH mutants (emission-deleted, condition-inverted) caught"
  else
    echo "FAIL: harness-ceiling-disclosed selftest"
  fi
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "")         run ;;
  *)          echo "usage: harness-ceiling-disclosed.sh [--selftest]" >&2; exit 2 ;;
esac
