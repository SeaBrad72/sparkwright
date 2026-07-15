#!/bin/sh
# mode-enforcement-blind.sh — lock that the S1 process-weight mode (incept --mode) is SURFACING-ONLY,
# never an ENFORCEMENT input. Asserts that NO gate across the enforcement surface — conformance checks,
# the gating scripts (preflight/doctor/tier-advice/…), CI workflows, and the pre-push hook — reads the
# stamped `Process mode` field / `INCEPT_PROCESS_MODE` env, EXCEPT the small allowlist declared below
# (the producer incept.sh, the replay tool kit-update.sh, and this lock), excluded by exact relative
# path — and a replay reader may only pass the mode through, never branch on it. This is the durable
# guard for the P2 resolution:
# enforcement keys on detected triggers (Dockerfile, evals/, data surface, classification), never on
# the declared mode — so a mode can NEVER weaken an applicable control. The moment someone makes a gate
# key on the mode, CI fails here. (Floor-invariance across modes is NOT checked here: it is a structural
# property of incept's design — the floor stamping runs unconditionally and curate_for_mode is purely
# additive — and running incept inside a conformance check would need the full kit tree in CWD; the
# enforcement-surface grep below is the load-bearing invariant.)
# Also asserts (additively, in run()) that the PRODUCER (incept.sh) offers only the honest
# lean|enterprise canonical modes + carries the prototype|team->lean deprecation alias, so the
# dial cannot silently regress to dead/false names. See the (2) HONEST MODE NAMES block below.
#   sh conformance/mode-enforcement-blind.sh [--selftest]
# Exit: 0 = mode-blind · 1 = a gate reads the mode (regression) · 2 = setup. POSIX sh; dash-clean.
set -eu
cd "$(dirname "$0")/.."
ROOT="${MODE_BLIND_ROOT:-.}"

# ── THE ALLOWLIST (the single source of truth for BOTH assertions below) ───────────────────────────
# Only these files may name the stamped mode. Each entry states WHY it is not an enforcement read:
#   scripts/incept.sh  — the PRODUCER. It stamps the mode; producing it necessarily means naming it.
#   conformance/mode-enforcement-blind.sh — this lock (it names the mode in its own asserts).
#   scripts/kit-update.sh — a REPLAY TOOL, NOT A GATE. It reads the recorded mode SOLELY to hand it
#     back to `incept --mode` when it reconstructs the adopter's base tree — structurally the same
#     reason the producer is allowlisted (both sides of the same round-trip). It makes no enforcement
#     decision on the value, and MODE_BRANCH_RE below LOCKS that: a replay reader that BRANCHES on the
#     mode's value fails this check. That is what keeps the allowlist from becoming a blanket hole —
#     an entry added to REPLAY_READERS buys the right to READ the mode, never to ACT on it.
PRODUCER='scripts/incept.sh'
SELF='conformance/mode-enforcement-blind.sh'
REPLAY_READERS='scripts/kit-update.sh'   # non-producer readers: pass-through only, branch-scanned in (3)

# The exclusion ERE is DERIVED from the allowlist above (never hand-maintained beside it), so a file can
# not be excluded from the (1) scan without also being enrolled in the (3) branch-scan.
EXCL=''
for _a in "$PRODUCER" "$SELF" $REPLAY_READERS; do
  EXCL="${EXCL:+$EXCL|}(^|/)$(printf '%s' "$_a" | sed 's/\./\\./g')\$"
done

# A read of the mode that BRANCHES on its VALUE — the forbidden weakening dial — in any of these forms:
#   case "$MODE" in …            (dispatch on the value)
#   [ "$MODE" = lean ] / != / =~ (compare the value, either operand order)
#   X=$MODE                      (copy it into another variable, then branch on THAT — the derivation hole)
# A PRESENCE check (`filled "$MODE"`, `[ -n "$MODE" ]`) is deliberately NOT forbidden: it branches on the
# stamp being ABSENT, not on lean-vs-enterprise, and its only outcome is a REFUSAL — it can harden the
# tool, never weaken a gate. Note `mode=$MODE` inside an echo does NOT match (a `=` operand needs the
# surrounding whitespace POSIX `test` requires), so surfacing the value stays legal.
# HONEST CEILING: this is a grep, not a shell parser. It catches the DIRECT forms above (that is what
# makes the allowlist non-vacuous — see the --selftest negatives), but it cannot see a value branch that
# is deliberately laundered out of `$MODE` first: e.g. a SECOND read into another name
# (`X=$(stamp_list 'Process mode')`), or an inline derivation (`[ "$(printf %s "$MODE" | cut -c1)" = l ]`).
# It is a strong floor against the realistic regression (someone adds an `if` on the mode), NOT a proof
# of impossibility — the durable defense is that REPLAY_READERS stays TINY and every entry is reviewed.
_MV='\$\{?MODE\}?'
MODE_BRANCH_RE="case[[:space:]]+\"?${_MV}\"?[[:space:]]+in|${_MV}\"?[[:space:]]*(=|==|!=|=~)[[:space:]]|(=|==|!=|=~)[[:space:]]+\"?${_MV}|^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[^=]*${_MV}"

run() {
  rc=0
  # Scan the whole ENFORCEMENT SURFACE — conformance checks, the gating scripts (preflight/doctor/
  # tier-advice/…), every CI workflow, and the pre-push hook — for any READ of the stamped process
  # mode (`Process mode` in a project CLAUDE.md, or the `INCEPT_PROCESS_MODE` env). A gate that keys
  # on the mode is the forbidden weakening dial. Exclude ONLY the allowlist declared at the top (the
  # producer, this lock, and the branch-scanned replay readers) — nothing else.
  # The `--mode` FLAG is intentionally NOT forbidden — incept and any CI step that runs incept use it
  # legitimately; the forbidden thing is a gate CONSUMING the stamped value.
  # Exclude, by EXACT RELATIVE PATH, only the allowlist declared above ($EXCL is derived from it).
  # Full-path anchoring (not basename) means an `incept.sh` planted in ANY OTHER dir — e.g.
  # conformance/incept.sh reading the mode — is still caught. `|| true` keeps set -e happy when the
  # inner grep finds nothing or everything is excluded.
  _hits=$(grep -REl "Process mode|INCEPT_PROCESS_MODE" \
            "$ROOT/conformance" "$ROOT/scripts" "$ROOT/.github/workflows" "$ROOT/hooks" 2>/dev/null \
          | grep -vE "$EXCL" || true)
  if [ -n "$_hits" ]; then
    echo "FAIL: a gate reads the process mode (enforcement must be mode-blind):"
    printf '%s\n' "$_hits" | sed 's/^/  /'
    rc=1
  fi
  # (3) THE ALLOWLIST HAS TEETH: an allowlisted NON-PRODUCER (a replay tool) may READ the mode only to
  # PASS IT THROUGH — it must never BRANCH ENFORCEMENT on the value. This is the invariant the (1) scan
  # only approximates: the rule was never "no script reads the mode", it is "no script ACTS on it". So
  # the moment kit-update (or any future replay reader) grows an `if`/`case`/`[ … ]` on the mode — or
  # launders it into another variable to branch on that — this fails, exactly as if it were never
  # allowlisted. An allowlisted file that has VANISHED is not a pass: a replay reader is a named member
  # of the enforcement surface, and a missing member is a FAIL (a deletion must not silently retire the
  # assertion — presence cannot see a substitution).
  for _r in $REPLAY_READERS; do
    if [ ! -f "$ROOT/$_r" ]; then
      echo "FAIL: allowlisted replay reader '$_r' is missing — remove it from REPLAY_READERS (and from the"
      echo "      allowlist) deliberately, or restore it. A vanished member must not silently retire its lock."
      rc=1
      continue
    fi
    _branch=$(grep -nE "$MODE_BRANCH_RE" "$ROOT/$_r" || true)
    if [ -n "$_branch" ]; then
      echo "FAIL: allowlisted replay reader '$_r' BRANCHES on the process mode — the mode is surfacing-only,"
      echo "      never an enforcement input. It is allowlisted to READ the mode (to pass it back to"
      echo "      \`incept --mode\`), NOT to act on it. Offending line(s):"
      printf '%s\n' "$_branch" | sed 's/^/  /'
      rc=1
    fi
  done
  # (2) HONEST MODE NAMES: the producer (incept.sh) offers only lean|enterprise as canonical modes,
  # and deprecates the former prototype|team to lean (so the dial can't silently regress to dead names
  # and old --mode values keep working). incept is NAMED here (this is a read of the producer, distinct
  # from the blind-scan exclusion above — that forbids a GATE reading the stamped mode, not this lock
  # asserting the producer's mode set).
  _ip="$ROOT/scripts/incept.sh"
  if [ -f "$_ip" ]; then
    grep -q 'PROCESS_MODES="lean enterprise"' "$_ip" || { echo "FAIL: incept PROCESS_MODES is not the honest 'lean enterprise'"; rc=1; }
    grep -Eq 'PROCESS_MODES="[^"]*(prototype|team)' "$_ip" && { echo "FAIL: incept still offers a dead canonical mode (prototype/team) in PROCESS_MODES"; rc=1; }
    grep -Eq 'prototype\|team\).*MODE="lean"' "$_ip" || { echo "FAIL: incept lacks the prototype|team -> lean deprecation alias (old --mode values would break or dead names could return)"; rc=1; }
  fi
  [ "$rc" -eq 0 ] && echo "PASS: process mode is enforcement-blind (no gate / script / workflow / hook reads it)"
  return $rc
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  run >/dev/null 2>&1 || { echo "mode-enforcement-blind --selftest: FAIL (real tree not green)"; sfail=1; }
  # negative: a conformance dir containing a mode-reading check must FAIL the lock.
  _n=$(mktemp -d); mkdir -p "$_n/conformance" "$_n/.github/workflows"
  printf '#!/bin/sh\ncase "$mode" in lean) exit 0;; esac\n# Process mode\n' > "$_n/conformance/bad.sh"
  : > "$_n/.github/workflows/ci.yml"
  # Direct rebind of $ROOT (NOT `MODE_BLIND_ROOT=$_n run` — an env-prefix does not rebind the
  # already-captured $ROOT; the S2/S3 lesson). Save/restore so the positive run above is unaffected.
  _saved_root="$ROOT"; ROOT="$_n"
  if run >/dev/null 2>&1; then echo "mode-enforcement-blind --selftest: FAIL (mode-reading check passed)"; sfail=1; fi
  ROOT="$_saved_root"
  rm -rf "$_n"
  # negative (honest-names): an incept.sh that still offers prototype/team as a canonical mode must FAIL.
  _h=$(mktemp -d); mkdir -p "$_h/scripts" "$_h/conformance" "$_h/.github/workflows"
  printf '#!/bin/sh\nPROCESS_MODES="prototype team enterprise"\n' > "$_h/scripts/incept.sh"
  : > "$_h/.github/workflows/ci.yml"
  _saved_root2="$ROOT"; ROOT="$_h"
  if run >/dev/null 2>&1; then echo "mode-enforcement-blind --selftest: FAIL (dead canonical mode name passed honest-names)"; sfail=1; fi
  ROOT="$_saved_root2"
  rm -rf "$_h"
  # negative (allowlist teeth): an ALLOWLISTED replay reader that BRANCHES on the mode must FAIL — the
  # allowlist buys the right to read the mode, never to act on it. One tree per forbidden form: the
  # value test, the case dispatch, and the laundering copy (`X=$MODE`, then branch on X). Each carries
  # the honest read+pass-through too, so what is being caught is the BRANCH, not the read.
  for _form in '[ "$MODE" = "lean" ] && SKIP_A_GATE=1' 'case "$MODE" in lean) SKIP_A_GATE=1 ;; esac' 'LAUNDERED=$MODE'; do
    _b=$(mktemp -d); mkdir -p "$_b/scripts" "$_b/conformance" "$_b/.github/workflows"
    cp "$ROOT/scripts/incept.sh" "$_b/scripts/incept.sh" 2>/dev/null || :
    : > "$_b/.github/workflows/ci.yml"
    printf '#!/bin/sh\nMODE=$(stamp_list "Process mode")\n%s\nset -- --mode "$MODE"\n' "$_form" > "$_b/scripts/kit-update.sh"
    _saved_root3="$ROOT"; ROOT="$_b"
    if run >/dev/null 2>&1; then
      echo "mode-enforcement-blind --selftest: FAIL (a replay reader branching on the mode passed: $_form)"; sfail=1
    fi
    # positive control for the SAME tree: strip the branch and the very same reader must PASS, proving the
    # branch-scan catches the BRANCH and does not merely flag any mention of the mode (no false positive
    # on the honest read + `--mode "$MODE"` pass-through that kit-update actually does).
    printf '#!/bin/sh\nMODE=$(stamp_list "Process mode")\nset -- --mode "$MODE"\necho "mode=$MODE"\n' > "$_b/scripts/kit-update.sh"
    run >/dev/null 2>&1 || { echo "mode-enforcement-blind --selftest: FAIL (honest pass-through replay reader flagged — false positive)"; sfail=1; }
    ROOT="$_saved_root3"
    rm -rf "$_b"
  done
  # negative (completeness): an allowlisted replay reader that has VANISHED must FAIL, not silently pass.
  _m=$(mktemp -d); mkdir -p "$_m/scripts" "$_m/conformance" "$_m/.github/workflows"
  cp "$ROOT/scripts/incept.sh" "$_m/scripts/incept.sh" 2>/dev/null || :
  : > "$_m/.github/workflows/ci.yml"
  _saved_root4="$ROOT"; ROOT="$_m"
  if run >/dev/null 2>&1; then echo "mode-enforcement-blind --selftest: FAIL (missing replay reader silently passed)"; sfail=1; fi
  ROOT="$_saved_root4"
  rm -rf "$_m"
  [ "$sfail" -eq 0 ] && { echo "mode-enforcement-blind --selftest: OK"; exit 0; } || exit 1
fi

run
