#!/bin/sh
# proportional-gate-wired.sh — regression-lock for Proportional Promotion Contract slice 3
# (docs/governance/promotion-contract.md): the control-plane-ratification gate is (a) class-aware
# and (b) emits the honest team/solo SoD state label, surfaced in LEGIBLE plain language for the
# human who must act. Tokens are machine-stable; the gloss is human-required and locked here.
#   sh conformance/proportional-gate-wired.sh [--selftest]
# Exit: 0 = ok · 1 = drift · 2 = usage. POSIX sh; dash-clean.
set -eu
cd "$(dirname "$0")/.." 2>/dev/null || true
AB="conformance/agent-boundary.sh"
# CP-9: the gate moved OUT of ci.yml into its own workflow — it is the one check that must re-run on
# `pull_request_review`, and a review must re-run THAT and nothing else. This path is also the KIT↔PROFILE
# PARITY LOCK: verify.sh runs this script both in the kit AND (via CI's artifact-gate) inside a freshly
# incepted adopter project, where .github/workflows/ratification.yml is the copy of
# profiles/typescript-node/ratification.yml. Fix the kit alone and this goes RED in the adopter — which
# is exactly what stops the cry-wolf bug from shipping to customers while the kit quietly enjoys the fix.
WF=".github/workflows/ratification.yml"
CI_WF=".github/workflows/ci.yml"
PR="conformance/promotion-readiness.sh"

label() { sh "$AB" --changed "$1" --ratified "$2" --state 2>/dev/null; }  # -> SoD state label

# code_only <file>: the file with whole-line comments stripped.
#
# Every NEGATIVE anchor below ("this workflow must NOT contain X") must read CODE, not file text. These
# workflows DISCUSS `github.base_ref`, `action_required`, and `ref: …head.sha` at length — they have to,
# since explaining why those are wrong is the point of the comments. A bare grep over the file therefore
# fires on the explanation and reds a correct workflow. (It did, three times, during this slice. The
# first two versions of these anchors were "fixed" by contorting the prose — hyphenating `action-required`
# so the grep would miss it — which makes the COMMENTS load-bearing for the TEST. That is backwards: the
# lock must not constrain what the documentation is allowed to say.)
code_only() { grep -v '^[[:space:]]*#' "$1"; }

selftest() {
  st=0; d=$(mktemp -d)
  printf '.github/workflows/ci.yml\n' > "$d/cp.txt"
  printf 'src/util/format.ts\n'       > "$d/ord.txt"
  lk() { _g=$(label "$2" "$3"); if [ "$_g" = "$1" ]; then echo "PASS: $4 -> $_g"; else echo "FAIL: $4 want $1 got $_g"; st=1; fi; }
  lk RATIFIED-BY-SECOND-REVIEWER "$d/cp.txt"  1 "control-plane + ratified -> team label"
  lk SOLO-ADMIN-OVERRIDE-LOGGED  "$d/cp.txt"  0 "control-plane + unratified -> solo label"
  lk NONE                        "$d/ord.txt" 0 "ordinary -> no label (N/A)"
  # load-bearing negative: solo and team labels must differ (always-team mutation -> this FAILs)
  if [ "$(label "$d/cp.txt" 0)" = "$(label "$d/cp.txt" 1)" ]; then
    echo "FAIL: solo and team labels identical (state derivation vacuous)"; st=1; fi
  [ -f "$WF" ] || { echo "FAIL: $WF is missing — the ratification gate has no workflow to run in"; st=1; return $st; }
  # workflow wiring: class-aware (the actual promotion-readiness --class call, not the bare flag token —
  # a prose mention of '--class' must not satisfy this) + both state tokens surfaced. The state tokens
  # now reach the human via agent-boundary's --conclusion mapping, so they are anchored THERE; what the
  # workflow must still prove is that it CALLS that mapping rather than re-deciding inline.
  for tok in 'promotion-readiness.sh --class' 'agent-boundary.sh --conclusion'; do
    grep -qF -- "$tok" "$WF" || { echo "FAIL: $WF missing '$tok' in the ratification gate"; st=1; }
  done
  for tok in 'RATIFIED-BY-SECOND-REVIEWER' 'SOLO-ADMIN-OVERRIDE-LOGGED'; do
    grep -qF -- "$tok" "$AB" || { echo "FAIL: $AB missing the '$tok' state token"; st=1; }
  done
  # the class/gate reconciliation guard: displayed class must not contradict the gate verdict (the
  # gate is union-aware; guard-core-only --class can under-detect adapter-declared paths, e.g. AGENTS.md)
  grep -qF -- 'state" != NONE' "$WF" || { echo "FAIL: $WF missing the class/gate reconciliation guard"; st=1; }

  # --- CP-9 anchors. Each one pins a property whose loss is SILENT: the gate keeps posting green. ---

  # (1) The re-trigger. Without it an approval lands and the check stays stale at its pre-approval
  # verdict — the human ratifies and the gate never notices.
  # Matched as a TRIGGER KEY (line-anchored), never as a bare token: both of these files DISCUSS
  # `pull_request_review` at length in their comments, so a substring grep passes happily on a workflow
  # whose trigger has been deleted. It did, in mutation testing — the anchor proved nothing.
  grep -qE '^[[:space:]]+pull_request_review:[[:space:]]*$' "$WF" || {
    echo "FAIL: $WF has no pull_request_review TRIGGER — an approval would never re-run the gate, and the check would sit stale at its pre-approval verdict"; st=1; }

  # (2) CONTAINMENT: the review event must re-run the ratification gate and NOTHING ELSE. This is the
  # whole reason the gate lives in its own file, and it is invisible until someone's CI bill arrives.
  if [ -f "$CI_WF" ] && grep -qE '^[[:space:]]+pull_request_review:[[:space:]]*$' "$CI_WF"; then
    echo "FAIL: $CI_WF triggers on pull_request_review — a review would re-run the whole suite (tests, conformance, artifact-gate), not just the gate"; st=1
  fi

  # (3) THE TRUST BOUNDARY, and the most important anchor in this file.
  #
  # The gate holds `checks: write` and runs its own adjudicating code (agent-boundary.sh,
  # promotion-readiness.sh, guard-core.sh). It must NEVER check out or execute code from the PR it is
  # judging: a PR that rewrites the mapping to say `success` — or that neuters `is_control_plane_path` —
  # would have the gate post its own green. No fork needed; the author can fire the review event with a
  # COMMENTED self-review. So the gate is adjudicated from the BASE tree, and the changed-file listing
  # comes from the PR files API, never from a git diff of a checked-out working tree.
  #
  # NOTE this anchor is INVERTED from its first draft, which asserted `ref: …head.sha` must be PRESENT —
  # i.e. it pinned the vulnerability as a required property and mutation-tested it into place. A lock can
  # enforce a defect as confidently as a fix; what makes it a lock is which one you point it at.
  grep -qF -- 'ref: ${{ github.event.pull_request.base.sha }}' "$WF" || {
    echo "FAIL: $WF does not check out the BASE commit — the gate would adjudicate using code from the PR under test, which can rewrite the gate to pass itself"; st=1; }
  # Only the CHECKOUT of the head is forbidden. The check-run is still POSTED against head.sha (it must
  # be — that is the commit whose mergeability the check governs), so this must not be a bare token grep.
  if code_only "$WF" | grep -qF -- 'ref: ${{ github.event.pull_request.head.sha }}'; then
    echo "FAIL: $WF checks out the PR HEAD — it executes conformance/*.sh from that tree while holding checks:write, so the PR under test can rewrite the gate that judges it and forge its own ratification"; st=1
  fi
  grep -qF -- 'pulls/${PR}/files' "$WF" || {
    echo "FAIL: $WF does not take the changed-file listing from the PR files API — a git diff of a checked-out tree is head-dependent, and the wrong ref yields an EMPTY listing, which reads as 'no control-plane paths' (rc=0) and posts GREEN on an unratified PR"; st=1; }
  grep -qF -- '[ ! -s /tmp/changed.txt ]' "$WF" || {
    echo "FAIL: $WF has no empty-changed-file tripwire — a PR always changes >=1 file, so an empty listing means the listing could not be computed, NOT that there is nothing to ratify. Without this, a failed lookup reads as rc=0 (fail-open)"; st=1; }

  # (3b) The privileged-untrusted-code seam. This job checks out the PR HEAD and EXECUTES code from it
  # (conformance/*.sh). On `pull_request` a fork's token is read-only, so that is inert. But
  # `pull_request_review` can run in the BASE-repo context — and if its token is writable on a fork PR,
  # "run the fork's code" + `checks: write` lets an attacker post `control-plane-ratification: success`
  # on any SHA: the gate handing out its own green. The review re-trigger is therefore restricted to
  # SAME-REPO PRs. Losing this line silently re-opens a pwn-request against the governance gate itself.
  grep -qF -- 'github.event.pull_request.head.repo.full_name == github.repository' "$WF" || {
    echo "FAIL: $WF does not restrict the pull_request_review re-trigger to same-repo PRs — a fork PR would reach a privileged path that checks out and EXECUTES its own code with checks:write (pwn-request against the ratification gate)"; st=1; }

  # (4) `github.base_ref` is UNDEFINED on pull_request_review (populated only for
  # pull_request/pull_request_target), so a workflow that computes a diff base from it silently gets an
  # empty ref on review events. The base-tree design above removes the diff entirely — there is no base
  # ref to get wrong — so this is anchored as an ABSENCE: reintroducing github.base_ref would mean
  # someone has reintroduced a working-tree diff, and with it the whole fail-open class.
  if code_only "$WF" | grep -qF -- 'github.base_ref'; then
    echo "FAIL: $WF references github.base_ref — it is EMPTY on pull_request_review, and its presence means a head-relative diff has been reintroduced (see the trust-boundary note above)"; st=1
  fi

  # (4b) THE CONSUMER of the mapping. conclusion_map is thoroughly tested — but the workflow that POSTS
  # its output was not, and that is where the slice actually lives. A single-call `gh api … -f
  # conclusion="$concl"` sends conclusion="" for the waiting state; GitHub takes the empty string AS a
  # conclusion, COMPLETES the check, and the red is back — with every selftest still green. (Proven: a
  # reviewer collapsed the if/else and the whole slice reverted with no lock noticing.) The omission is
  # the mechanism, so the omission gets an anchor.
  grep -qF -- 'if [ -n "$concl" ]; then' "$WF" || {
    echo "FAIL: $WF does not CONDITIONALLY omit the conclusion — posting -f conclusion=\"\" completes the check-run, which renders RED again and reverts the slice"; st=1; }
  grep -qF -- '-f status="$status"' "$WF" || {
    echo "FAIL: $WF does not pass the mapping's status through — a hardcoded status ignores the yellow waiting state entirely"; st=1; }
  # ...and the waiting branch's API call must carry NO conclusion field at all.
  if code_only "$WF" | sed -n '/else$/,/^          fi$/p' | grep -q 'conclusion'; then
    echo "FAIL: the waiting (else) gh api call in $WF carries a conclusion field — any conclusion completes the check and turns waiting red"; st=1
  fi

  # (5) The colour contract: waiting is YELLOW. `action_required` renders with the same red X as a
  # failure, which is what made a correctly-functioning gate read as a broken build.
  code_only "$WF" | grep -qF -- 'action_required' && {
    echo "FAIL: $WF still posts action_required — that renders RED, and a WAITING gate must not read as a BROKEN one (CP-9)"; st=1; }

  # legibility anchors: the waiting check-run must stay plain-language and tell the human what to do.
  # DRIVEN, not grepped. The text now lives in agent-boundary.sh — but so does that script's own
  # selftest, whose expectation list contains these very literals, so grepping the FILE finds them even
  # when the real title has been gutted. (It did, in mutation testing.) Ask the mapping what it would
  # actually post, and read THAT. Behaviour, not source text.
  _waiting=$(sh "$AB" --conclusion 1 --for-state SOLO-ADMIN-OVERRIDE-LOGGED --for-class control-plane)
  for a in 'Awaiting ratification' 'NOT a build failure' 'To proceed:' 'gh pr merge' 'review-lane.md'; do
    case "$_waiting" in
      *"$a"*) ;;
      *) echo "FAIL: the waiting check-run's text is missing legibility anchor '$a'"; st=1 ;;
    esac
  done
  # ...and the waiting state must actually BE the yellow, still-blocking one.
  printf '%s\n' "$_waiting" | grep -qx 'status=in_progress' || {
    echo "FAIL: the waiting check-run does not post status=in_progress (a completed non-success check renders RED — the exact cry-wolf CP-9 removes)"; st=1; }
  printf '%s\n' "$_waiting" | grep -qx 'conclusion=' || {
    echo "FAIL: the waiting check-run carries a conclusion — any conclusion COMPLETES the check, which turns it red again. It must be empty and OMITTED from the API call"; st=1; }
  [ "$st" = 0 ] && echo "OK: proportional-gate-wired selftest" || echo "FAIL: proportional-gate-wired selftest"
  return $st
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "") for f in "$AB" "$WF" "$PR"; do [ -f "$f" ] || { echo "FAIL: missing $f"; exit 1; }; done
      echo "OK: proportional-gate wiring present"; exit 0 ;;
  *) echo "usage: proportional-gate-wired.sh [--selftest]" >&2; exit 2 ;;
esac
