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
# incepted adopter project, where .github/workflows/ratification.yml is the copy of the single
# stack-neutral source profiles/ratification.yml (RATIFY-PARITY: installed for EVERY stack, not just
# ts-node). Fix the kit alone and this goes RED in the adopter — which is exactly what stops the
# cry-wolf bug from shipping to customers while the kit quietly enjoys the fix.
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

# _wf_disposition <wf_exists:0|1> <must_have:0|1> -> RUN | NA | FAIL
# Decides what to do when the ratification workflow is (P0-FU) export-ignored. By ARGUMENTS, never env:
# an env-redirectable path on a control-plane check is exactly the vacuity this project forbids. Fail-CLOSED
# — the only silent path (NA) requires BOTH "no workflow" AND "this tree is NOT one that must have it".
# `must_have` = incepted adopter OR the kit repo itself (see the OR-of-markers at the call site): both are
# expected to carry the workflow, so a missing one there is a real regression, never N/A. Only a raw
# pre-incept export (neither) legitimately has no workflow yet — incept installs it.
_wf_disposition() {
  [ "$1" = 1 ] && { echo RUN; return; }    # the gate exists -> verify its wiring (kit repo + incepted adopter)
  [ "$2" = 1 ] && { echo FAIL; return; }   # must-have context, yet the gate is gone -> a real regression
  echo NA                                  # no gate AND a raw export -> incept installs it; nothing to wire yet
}

# _must_have_workflow [root] -> 1 iff this tree is expected to carry the kit workflows: an incepted adopter
# (incept creates ENGINEERING-PRINCIPLES.md) OR the kit repo itself (kit-only markers, one control-plane +
# export-ignored so it is un-spoofable). A raw pre-incept export has NONE of these -> 0. Fail-closed:
# any ONE marker present makes a missing workflow a FAIL, so a raw export is the only path to N/A.
# Parameterized on <root> (default cwd) SO THE SELFTEST CAN LOCK BOTH BRANCHES against fixtures — a marker
# rename that made this return 0 on an incepted tree would silently fail-OPEN the gate, and that must fail a test.
# _gitlab_only_adopter [root] -> 1 iff this tree is a GitLab-CI adopter for which the §13
# control-plane-ratification gate is legitimately absent. Keyed ENTIRELY on STRUCTURE derived from the
# tree — NEVER on prose in a mutable doc. §13 is declared GitHub-conditional in DEVELOPMENT-PROCESS.md
# (built on GitHub check-runs + `pull_request_review`, which GitLab does not provide; locked by
# conformance/conditional-gates.sh), so its absence on a GitLab tree is an already-ratified platform gap,
# not drift. The structural triple, ALL THREE required:
#   .gitlab-ci.yml present          — this tree's authoritative pipeline is GitLab
#   .github/workflows/ci.yml absent — it is NOT a GitHub adopter (`incept --ci github` installs this;
#                                     `--ci gitlab` never touches .github/workflows/, and both are
#                                     export-ignored so a raw export ships only an EMPTY workflows dir)
#   ratification.yml absent         — the §13 gate is genuinely not installed here
# Load-bearing narrowness: a GitHub tree (ci.yml present) can NEVER reach the N/A; a GitLab tree that
# somehow HAS the ratification workflow is checked normally, not waved through; and a tree with NO
# .gitlab-ci.yml FAILs — including the prose-only exploit (a self-typed `**CI platform** (§14): gitlab`
# line in CLAUDE.md) that the RETIRED grep-based escape accepted. The escape has no structural signal to
# key on there, so the prose is not read at all: that self-exemptible bypass is closed.
# Parameterized on <root> so BOTH branches are lockable against fixtures: this script cd's to its own
# repo root (line 9), so a test that cd'd into a fixture would evaluate the KIT and pass for the wrong
# reason — which is exactly what the first version of this selftest did.
_gitlab_only_adopter() {
  _gr=${1:-.}
  { [ -f "$_gr/.gitlab-ci.yml" ] && [ ! -f "$_gr/$CI_WF" ] && [ ! -f "$_gr/$WF" ]; } \
    && echo 1 || echo 0
}

_must_have_workflow() {
  _mhr=${1:-.}
  { [ -f "$_mhr/ENGINEERING-PRINCIPLES.md" ] || [ -f "$_mhr/docs/ROADMAP-KIT.md" ] || [ -f "$_mhr/.github/workflows/golden-path.yml" ]; } \
    && echo 1 || echo 0
}

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

  # P0-FU: the ratification gate is export-ignored (incept installs profiles/<stack>/ratification.yml),
  # so a PRE-INCEPT adopter export ships no workflow and this content-lock has nothing to wire yet. But an
  # INCEPTED tree missing its gate is a real regression. `_wf_disposition` makes that call fail-CLOSED, by
  # ARGUMENTS (never env — an env-redirectable control-plane check is the vacuity we forbid). Load-bearing:
  # an always-RUN mutation reddens the raw-export case; an always-NA mutation greens the incepted case.
  [ "$(_wf_disposition 1 0)" = RUN ]  || { echo "FAIL: disposition — workflow present must RUN the content assertions"; st=1; }
  [ "$(_wf_disposition 1 1)" = RUN ]  || { echo "FAIL: disposition — workflow present (incepted) must RUN"; st=1; }
  [ "$(_wf_disposition 0 0)" = NA ]   || { echo "FAIL: disposition — raw pre-incept export (no gate, not incepted) must be N/A"; st=1; }
  [ "$(_wf_disposition 0 1)" = FAIL ] || { echo "FAIL: disposition — incepted tree missing its gate must FAIL (fail-closed)"; st=1; }
  # C1b legs — by ARGUMENT against fixture roots, NOT by cd-ing into a fixture and running this script.
  # This script cd's to its own repo root (line 9), so a fixture-cwd test would silently evaluate the
  # KIT instead of the fixture: the positive leg would pass for the wrong reason and prove nothing.
  # (That is exactly what the first version of this leg did — caught only because the negative leg,
  # which expected a FAIL, also evaluated the kit and got OK.)
  _pgd=$(mktemp -d)
  # STRUCTURAL fixtures — the disposition keys on tree STRUCTURE, never on CLAUDE.md prose. Positive/
  # legitimate legs FIRST: a matcher broken SHUT would satisfy every negative assertion (governing lesson).
  # (1) recorded GitLab adopter, §13 gate genuinely absent -> N/A (the escape's one legitimate case)
  mkdir -p "$_pgd/gl"; : > "$_pgd/gl/.gitlab-ci.yml"
  [ "$(_gitlab_only_adopter "$_pgd/gl")" = 1 ] || { echo "FAIL: selftest — a GitLab adopter (.gitlab-ci.yml, no §13 gate) must take the platform-conditional N/A"; st=1; }
  # (2) GitLab tree that HAS the §13 gate -> checked normally, not waved through
  mkdir -p "$_pgd/gl2/.github/workflows"; : > "$_pgd/gl2/.gitlab-ci.yml"; : > "$_pgd/gl2/$WF"
  [ "$(_gitlab_only_adopter "$_pgd/gl2")" = 0 ] || { echo "FAIL: selftest — a GitLab tree that HAS the §13 ratification workflow must be checked, not waved through"; st=1; }
  # (3) GitHub adopter (ci.yml present) -> can NEVER reach the escape; its missing §13 gate is real drift
  mkdir -p "$_pgd/gh/.github/workflows"; : > "$_pgd/gh/$CI_WF"
  [ "$(_gitlab_only_adopter "$_pgd/gh")" = 0 ] || { echo "FAIL: selftest — a GitHub adopter must NOT take the GitLab escape (its missing §13 gate is real drift, not a platform gap)"; st=1; }
  # (4) neither pipeline -> fail-closed (no structural signal for the escape)
  mkdir -p "$_pgd/bare"
  [ "$(_gitlab_only_adopter "$_pgd/bare")" = 0 ] || { echo "FAIL: selftest — a tree with NEITHER pipeline must NOT take the GitLab escape (fail-closed)"; st=1; }
  # (6) BOTH pipelines present (GitHub authoritative) -> NOT the gitlab-only escape; checked normally.
  #     Load-bearing for the `.github/workflows/ci.yml absent` conjunct: without it this tree would
  #     wrongly N/A despite carrying a GitHub pipeline that MUST run the §13 gate.
  mkdir -p "$_pgd/both/.github/workflows"; : > "$_pgd/both/.gitlab-ci.yml"; : > "$_pgd/both/$CI_WF"
  [ "$(_gitlab_only_adopter "$_pgd/both")" = 0 ] || { echo "FAIL: selftest — a tree with BOTH pipelines (GitHub authoritative) must NOT take the GitLab escape"; st=1; }
  # (5) THE EXPLOIT LEG (mandatory — the single most important assertion in this check). The RETIRED
  #     escape keyed on a CLAUDE.md prose stamp: a tree carrying `**CI platform** (§14): gitlab` with no
  #     ratification workflow returned N/A — self-exemptible by anyone who can type that one line. With NO
  #     structural `.gitlab-ci.yml` the tree now FAILs: the prose is not read at all. This locks out the
  #     exact bypass security demonstrated.
  mkdir -p "$_pgd/exploit"; printf '**CI platform** (§14): gitlab\n' > "$_pgd/exploit/CLAUDE.md"
  [ "$(_gitlab_only_adopter "$_pgd/exploit")" = 0 ] || { echo "FAIL: selftest — a CLAUDE.md prose stamp with NO .gitlab-ci.yml must NOT take the GitLab escape (the self-exemptible bypass this task removes)"; st=1; }
  rm -rf "$_pgd" 2>/dev/null || true
  # And the OTHER half of the fail-closed decision: _must_have_workflow's MARKER DETECTION. The truth table
  # above is inert if this returns 0 on a real incepted/kit tree (a marker rename would do exactly that ->
  # silent NA = fail-open). Lock every marker against fixtures so that regression fails HERE, not in an adopter.
  _mh=$(mktemp -d)
  [ "$(_must_have_workflow "$_mh")" = 0 ] || { echo "FAIL: _must_have_workflow — a markerless tree (raw export) must be 0"; st=1; }
  for _mk in ENGINEERING-PRINCIPLES.md docs/ROADMAP-KIT.md .github/workflows/golden-path.yml; do
    mkdir -p "$_mh/$(dirname "$_mk")"; : > "$_mh/$_mk"
    [ "$(_must_have_workflow "$_mh")" = 1 ] || { echo "FAIL: _must_have_workflow — marker '$_mk' present must be 1 (fail-closed: a missing workflow here is a FAIL, never N/A)"; st=1; }
    rm -f "$_mh/$_mk"
  done
  rm -rf "$_mh" 2>/dev/null || true

  # The GitLab escape must be honoured HERE TOO. verify.sh registers this check as `--selftest`
  # (verify.sh's `check control proportional-gate … --selftest`), so the selftest — not the bare
  # dispatch — is the path the required battery actually runs. Fixing only the dispatch left the
  # battery red on a real --ci gitlab incept: the end-to-end run caught it, a unit selftest could not.
  if [ "$(_gitlab_only_adopter)" = 1 ]; then
    echo "N/A: proportional-gate — GitLab adopter; §13 control-plane ratification is declared a"
    echo "     GitHub-conditional gate in DEVELOPMENT-PROCESS.md (GitHub check-runs + pull_request_review,"
    echo "     which GitLab does not provide). Already-ratified platform gap; manual separation-of-duties"
    echo "     guidance in docs/operations/gitlab-adoption.md. State-label derivation above verified."
    return $st
  fi
  case "$(_wf_disposition "$([ -f "$WF" ] && echo 1 || echo 0)" "$(_must_have_workflow)")" in
    RUN)  : ;;   # fall through to the workflow-content assertions below
    NA)   echo "N/A: proportional-gate — pre-incept export (incept installs $WF; nothing to wire yet; state-label derivation above verified)"; return $st ;;
    FAIL) echo "FAIL: $WF is missing in a kit/incepted tree — the ratification gate has no workflow to run in"; st=1; return $st ;;
  esac
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
  "") # CP7R5-GATE-AUTHORITY. `incept --ci gitlab` installs NO §13 ratification gate — §13 is declared a
      # GitHub-conditional gate in DEVELOPMENT-PROCESS.md (GitHub check-runs + `pull_request_review`,
      # which GitLab does not provide; locked by conformance/conditional-gates.sh), an already-ratified
      # platform gap with manual separation-of-duties guidance. That was tolerable while nothing forced
      # adopters to run this battery. It stopped being tolerable the moment the emitted pipeline began
      # running `verify.sh --require` as a BLOCKING step: this check would redden every GitLab adopter's
      # first run over a gap they cannot close in their own tree, and a required gate that can never go
      # green is the classic path to the gate being deleted. Report the disclosed gap AS a disclosed gap.
      # STRUCTURAL, not prose (the retired grep-based escape keyed on a self-typed CLAUDE.md line and was
      # self-exemptible): the N/A requires the structural triple in `_gitlab_only_adopter` above —
      # .gitlab-ci.yml present AND .github/workflows/ci.yml absent AND the ratification workflow absent —
      # so a GitHub adopter (or the kit) that has genuinely LOST its ratification workflow still FAILs.
      if [ "$(_gitlab_only_adopter)" = 1 ]; then
        echo "N/A: proportional-gate — GitLab adopter; §13 control-plane ratification is declared a"
        echo "     GitHub-conditional gate in DEVELOPMENT-PROCESS.md (GitHub check-runs + pull_request_review,"
        echo "     which GitLab does not provide). Already-ratified platform gap; manual separation-of-duties"
        echo "     guidance in docs/operations/gitlab-adoption.md."
        exit 0
      fi
      case "$(_wf_disposition "$([ -f "$WF" ] && echo 1 || echo 0)" "$(_must_have_workflow)")" in
        NA) echo "N/A: proportional-gate — pre-incept export (incept installs $WF)"; exit 0 ;;
      esac
      for f in "$AB" "$WF" "$PR"; do [ -f "$f" ] || { echo "FAIL: missing $f"; exit 1; }; done
      echo "OK: proportional-gate wiring present"; exit 0 ;;
  *) echo "usage: proportional-gate-wired.sh [--selftest]" >&2; exit 2 ;;
esac
