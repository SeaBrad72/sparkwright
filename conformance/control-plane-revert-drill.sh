#!/bin/sh
# control-plane-revert-drill.sh — the DRILLED control-plane recovery proof (S5b, the S6 precondition).
#
# A control-plane revert needs NO new command: `git revert <bad control-plane merge>` restores the
# prior tree, and scripts/promotion-verify.sh `check` ALREADY verifies tree-equality — so
# `check --ref <reverted-HEAD> --approved-sha <last-good-sha>` IS the "did the revert restore the
# approved-good state" proof. This drill REUSES that exact mechanism (no parallel verifier) and
# proves it works on a fixture: apply a control-plane change C over a known-good state G, `git revert`
# it, and assert (a) the reverted tree EQUALS G's tree (via promotion-verify.sh check) AND (b) a
# fixture-local conformance-shaped marker is green on the reverted state.
#
#   sh control-plane-revert-drill.sh --selftest              # the GATED proof (fixture + negative)
#   sh control-plane-revert-drill.sh [repo] --last-good <sha> # advisory restoration attest on a live repo
#   sh control-plane-revert-drill.sh                          # presence attest (producer wired?)
# Exit: 0 = ok . 1 = non-restoration / drift . 2 = usage. POSIX sh; dash-clean.
#
# LOAD-BEARING NEGATIVE (non-vacuity): a NON-RESTORING revert — one that leaves the marker green but
# does NOT restore G's tree (extra unapproved content rides on top) — MUST FAIL the drill. The
# tree-equality assertion (not the marker alone) is what catches it: a stub that skips the
# tree-equality assertion PASSES the broken case, so the --selftest negative would no longer hold —
# that is the proof the assertion is load-bearing.
#
# HONEST CEILING: this drill proves RESTORATION now — that `git revert` + tree-equality restores the
# last-good control-plane tree, CI-gateable with no deploy. It does NOT prove a deploy rollback in
# anger (that needs a real staging environment — deferred to KW23), and it is not a bad-action
# detector (the break-glass HALT is resource-based + manual; see docs/operations/break-glass.md).
set -eu

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

# Resolve the producer we REUSE (scripts/promotion-verify.sh `check`) across installed + authoring
# layouts. Installed: conformance/../scripts. Scratchpad authoring: scratchpad/s5b/../../scripts.
resolve_verify() {
  if [ -n "${PROMOTION_VERIFY:-}" ] && [ -f "${PROMOTION_VERIFY}" ]; then
    echo "$PROMOTION_VERIFY"; return 0
  fi
  for _cand in \
    "$SCRIPT_DIR/../scripts/promotion-verify.sh" \
    "$SCRIPT_DIR/promotion-verify.sh" \
    "$SCRIPT_DIR/../../scripts/promotion-verify.sh"; do
    [ -f "$_cand" ] && { echo "$_cand"; return 0; }
  done
  return 1
}

# fixture-local conformance-shaped marker: the control-plane file is "green" when it carries the
# passing token. This stands in for "conformance is green on the reverted state" WITHOUT a heavy /
# circular full verify.sh re-run inside the selftest (owner ruling: restoration + a representative
# green). The marker is DELIBERATELY still green in the negative fixture, so tree-equality — not the
# marker — must be what fails the broken revert.
MARKER_FILE="guardrail.conf"
MARKER_GREEN="status=green"
conformance_green() {  # conformance_green <worktree-dir>
  grep -q "$MARKER_GREEN" "$1/$MARKER_FILE" 2>/dev/null
}

# The drill verdict for a candidate reverted state: restored (tree == last-good, via the REUSED
# `check`) AND conformance-marker green. Returns 0 = restored+green, 1 = not restored / not green.
#   drill_verdict <repo-worktree> <candidate-ref> <last-good-sha>
# The tree-equality half is the load-bearing anchor (a stub that drops it passes a non-restoring
# revert whose marker is green — see the header + the load-bearing proof in --selftest).
drill_verdict() {
  _repo="$1"; _ref="$2"; _good="$3"
  # (a) TREE-EQUALITY — REUSED from promotion-verify.sh check (no parallel verifier). This is the
  #     same fingerprint `check` uses to prove shipped == approved; here it proves reverted == good.
  if ! ( cd "$_repo" && sh "$VERIFY" check --ref "$_ref" --approved-sha "$_good" >/dev/null 2>&1 ); then
    return 1
  fi
  # (b) conformance-shaped marker green on the reverted worktree (representative green).
  conformance_green "$_repo" || return 1
  return 0
}

# ---------------------------------------------------------------------------
# Fixture: a throwaway control-plane repo exercising RESTORATION.
#   G       — known-good state: a tracked control-plane file (guardrail.conf = status=green) + VERSION
#   C       — a BAD control-plane change on top (guardrail.conf -> status=red): breaks the guardrail
#   REVERT  — `git revert --no-edit C`: restores G's tree exactly (the positive)
#   NONREST — a NON-restoring revert: revert C (marker back to green) BUT an extra unapproved file
#             rides on top, so the tree DIFFERS from G though the marker is green (the load-bearing
#             negative — only tree-equality catches it)
# Sentinels ($D/.*) live OUTSIDE the work-tree so `git add`/checkout never sweep or delete them.
# ---------------------------------------------------------------------------
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
    printf 'status=green\n' > guardrail.conf          # the control-plane guardrail, GREEN
    git add VERSION guardrail.conf; git commit -qm 'G: known-good control-plane state'
    git rev-parse HEAD > "$D/.G"
    git rev-parse --abbrev-ref HEAD > "$D/.TRUNK"

    printf 'status=red\n' > guardrail.conf            # C: a BAD control-plane change (guardrail off)
    git add guardrail.conf; git commit -qm 'C: bad control-plane change (guardrail -> red)'
    git rev-parse HEAD > "$D/.C"

    # positive lane: a clean revert of C restores G's tree exactly
    git checkout -q -b clean-revert "$(cat "$D/.C")"
    git revert --no-edit HEAD >/dev/null 2>&1         # REVERT: tree back to G's tree
    git rev-parse HEAD > "$D/.REVERT"

    # negative lane: a NON-restoring revert — marker restored green, but extra content rides on top
    git checkout -q -b nonrest "$(cat "$D/.C")"
    git revert --no-edit HEAD >/dev/null 2>&1         # marker back to green (status=green)...
    printf 'sneaked-in\n' > extra-unapproved.txt      # ...but an unapproved file rides on top
    git add extra-unapproved.txt; git commit -qm 'non-restoring: extra unapproved content'
    git rev-parse HEAD > "$D/.NONREST"

    git checkout -q "$(cat "$D/.TRUNK")"
  )
}

selftest() {
  st=0
  D="$(mktemp -d)"; R="$D/repo"
  build_fixture "$D" || true
  for _s in .G .C .REVERT .NONREST .TRUNK; do
    [ -f "$D/$_s" ] || { echo "FAIL: could not build git fixture (missing $_s)"; return 1; }
  done
  G="$(cat "$D/.G")"; REVERT="$(cat "$D/.REVERT")"; NONREST="$(cat "$D/.NONREST")"

  # --- POSITIVE: a clean `git revert` of C restores G's tree (same tree-equality `check` uses) AND
  #     the conformance-shaped marker is green -> the drill PASSES (rc 0). ---
  ( cd "$R" && git checkout -q "$REVERT" )
  if drill_verdict "$R" "$REVERT" "$G"; then
    echo "PASS: restoration positive: git revert restored G's tree (tree-equality) + marker green"
  else
    echo "FAIL: restoration positive: clean revert was not accepted as a restoration"; st=1
  fi

  # --- LOAD-BEARING NEGATIVE: a NON-restoring revert leaves the marker GREEN but does NOT restore
  #     G's tree (extra unapproved content) -> the drill MUST FAIL (rc 1). Tree-equality — not the
  #     marker — is what catches it (the marker is green here on purpose). ---
  ( cd "$R" && git checkout -q "$NONREST" )
  if conformance_green "$R"; then
    :  # confirm the trap: the marker IS green on the broken state, so only tree-equality can catch it
  else
    echo "FAIL: fixture invalid — non-restoring lane should keep the marker green"; st=1
  fi
  if drill_verdict "$R" "$NONREST" "$G"; then
    echo "FAIL: non-restoring-revert negative: drill PASSED a revert that did NOT restore G's tree (VACUOUS)"; st=1
  else
    echo "PASS: non-restoring-revert negative: drill FAILED the non-restoring revert (tree != G) as required"
  fi

  ( cd "$R" && git checkout -q "$(cat "$D/.TRUNK")" )

  if [ "$st" = 0 ]; then
    echo "OK: control-plane-revert-drill selftest — restoration proven + non-restoring revert rejected (fixture in $D)"
  else
    echo "FAIL: control-plane-revert-drill selftest (fixture in $D)"
  fi
  return $st
}

# Advisory restoration attest for a LIVE repo (not the gated proof): assert the current HEAD's tree
# equals a real prior-good sha's tree, via the same REUSED `check`. Use after a real `git revert`.
advise() {
  _repo="${1:-.}"; _good="${2:-}"
  [ -d "$_repo/.git" ] || { echo "advise: '$_repo' is not a git repo" >&2; return 2; }
  if [ -z "$_good" ]; then
    echo "advise: --last-good <sha> required for a live restoration attest" >&2; return 2
  fi
  if ( cd "$_repo" && sh "$VERIFY" check --ref HEAD --approved-sha "$_good" >/dev/null 2>&1 ); then
    echo "OK: HEAD tree == last-good $_good (advisory) — control-plane revert restored the good tree"
    return 0
  fi
  echo "NOT RESTORED: HEAD tree != last-good $_good — the revert did NOT restore the good tree" >&2
  return 1
}

VERIFY="$(resolve_verify || true)"

case "${1:-}" in
  --selftest)
    [ -n "$VERIFY" ] || { echo "FAIL: cannot resolve scripts/promotion-verify.sh (the reused producer)"; exit 1; }
    selftest; exit $? ;;
  "")
    if [ -n "$VERIFY" ]; then
      echo "OK: control-plane revert drill present; reuses producer $VERIFY (run --selftest for the gated proof)"; exit 0
    fi
    echo "FAIL: missing producer scripts/promotion-verify.sh"; exit 1 ;;
  --last-good)
    [ -n "$VERIFY" ] || { echo "FAIL: cannot resolve scripts/promotion-verify.sh"; exit 1; }
    advise "." "${2:-}"; exit $? ;;
  -*)
    echo "usage: control-plane-revert-drill.sh [--selftest] | [repo] --last-good <sha>" >&2; exit 2 ;;
  *)
    [ -n "$VERIFY" ] || { echo "FAIL: cannot resolve scripts/promotion-verify.sh"; exit 1; }
    _repo="$1"; shift
    if [ "${1:-}" = "--last-good" ]; then advise "$_repo" "${2:-}"; exit $?; fi
    echo "usage: control-plane-revert-drill.sh [--selftest] | [repo] --last-good <sha>" >&2; exit 2 ;;
esac
