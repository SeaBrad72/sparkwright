#!/bin/sh
# proportional-gate-wired.sh — regression-lock for Proportional Promotion Contract slice 3
# (docs/governance/promotion-contract.md): the control-plane-ratification gate is (a) class-aware
# and (b) emits the honest team/solo SoD state label, surfaced in LEGIBLE plain language for the
# human who must act. Tokens are machine-stable; the gloss is human-required and locked here.
#
# ⚠️ ANCHORS (2)-(7) WERE INVERTED ON 2026-08-27 — REQUIRED-CHECK-POSTED-VIA-API-NOT-MATCHED.
# They used to lock the POSTER design: a job key that must DIFFER from the check-run name, a
# `?check_name=` lookup, a PATCH-or-POST pair, an omitted `conclusion` for the yellow waiting render,
# `checks: write` confined to a base-tree-only job. All of that existed to render WAITING as YELLOW,
# which a workflow job cannot do. The owner deleted it: GitHub branch protection stopped MATCHING
# API-posted check-runs (three PRs in nine days stranded at "Expected — waiting for status to be
# reported", each cleared only by an admin merge), and a merge gate that intermittently cannot be
# satisfied is worse than a coarse colour. So the anchors now lock the INVERSE, at the same scope:
#   (a) each of the three required contexts is a JOB KEY of exactly that name;
#   (b) NO job in either workflow posts a check-run or holds `checks: write` (code-only);
#   (c) the ratification job still adjudicates from the BASE tree, never head.sha — UNCHANGED, and
#       now stronger: the exit code, not a token, is the thing PR code could forge;
#   (d) the profiles/ mirrors satisfy (a) and (b) too.
# The legibility anchors on the --conclusion prose are KEPT (they are what replaced the colour). The
# two anchors asserting `status=in_progress` and an empty `conclusion=` are DELETED: those fields are
# INERT now — nothing posts a check-run, so nothing consumes them — and an anchor on a field no
# consumer reads is a lock that can only ever mislead.
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

# THE THREE REQUIRED CONTEXTS THAT ARE NOW JOB KEYS (REQUIRED-CHECK-POSTED-VIA-API-NOT-MATCHED).
# Kept as data, not spelled into each anchor, so adding a fourth is one edit and cannot half-land.
REAL_JOB_CONTEXTS="backlog-presence ceremony-binding control-plane-ratification"

# _has_job_key <file> <name> -> 0 iff <file> declares a job keyed EXACTLY <name>.
# Line-anchored at the two-space job indent: a bare token grep would match the name in a comment, in
# a `-f name=` argument, or as a prefix of `backlog-presence-selftest`. The key IS the required
# context now, so this is an identity test, not a presence test.
_has_job_key() { grep -qE "^  $2:\$" "$1" 2>/dev/null; }

# _posts_nothing <file> -> 0 iff <file>, COMMENT-STRIPPED, contains no check-run posting call and no
# `checks: write`. Comment-stripped because these workflows must stay free to EXPLAIN the retired
# design at length — the whole reason code_only exists (see its note above). Two tokens, because they
# fail differently: `check-runs` is the API path a poster cannot avoid, and `checks: write` is the
# scope it cannot work without; either one reappearing means the indirection is back.
# _job_block <file> <job-key> -> that job's lines only, COMMENT-STRIPPED, key line excluded.
# ⚠️ THE ADDRESSING UNIT. ci.yml is a 2,000-line multi-job workflow: a bare `grep -qF` over the file
# passes if ANY job carries the line, so a whole-file anchor cannot tell a correct job from a broken one
# sitting next to a correct one. Every per-job property below reads THIS. (Review round 1, finding 2 —
# the exit-on-rc anchor was whole-file and would have passed with the line present in one job only.)
_job_block() {
  awk -v k="  $2:" '$0==k{f=1;next} f&&/^  [A-Za-z0-9_-]+:[[:space:]]*$/{f=0} f' "$1" 2>/dev/null \
    | grep -v '^[[:space:]]*#'
}

# _job_exits_on_rc <file> <job-key> -> 0 iff that job ENDS ON THE GATE'S rc.
# Its own conclusion is the required context, so a job that computes a verdict and then exits 0 anyway
# is a green gate enforcing nothing — the one fail-open the poster's deletion could have opened.
_job_exits_on_rc() { _job_block "$1" "$2" | grep -qF '[ "$rc" = 0 ] || exit 1'; }

# ── THE RATIFICATION JOB'S RENDERING (RATIFICATION-WAITING-IS-GREEN, owner ruling 2026-08-28) ────────
# The three helpers below REPLACE _job_exits_on_rc FOR THE RATIFICATION JOB ONLY. The other required
# contexts (backlog-presence / ceremony-binding / loop-state) still end on the gate's rc unchanged.
#
# WHY THE SWAP. That job no longer exits on the rc: rc 1 with NO approval present is the healthy
# WAITING state and now exits 0 with a ::notice, because branch protection's review requirement is
# what blocks that merge — a red there added no enforcement and taught the team to ignore reds. What
# still MUST red is rc 1 with an approval PRESENT that does not ratify (a human acted and the gate did
# not clear: self-approval, unreadable review list, fail-safed class) and rc 2. So the lock moves from
# "ends on the rc" to "ends on the RENDERING'S DECISION, and the rendering has these three arms".
#
# ⚠️ WITHOUT THESE, DELETING THE WAITING ARM IS INVISIBLE. `_job_exits_on_render` alone would pass a
# job that exits 1 on every non-zero rc (the pre-ruling behaviour) — the exit literal is identical.
# The arms have to be asserted individually or the lock only proves the last line still exists.

# ⚠️⚠️ THESE ANCHORS ARE ABOUT *WHERE THE DECISION LIVES*, NOT ITS TEXT (round 1, finding 3). The
# first version grepped the workflows' inline chain for its literals; the reviewer inverted the
# rendering TWICE without touching one (`_exit=1` inside the waiting arm; the condition widened with
# `|| [ 1 = 1 ]`). A policy in YAML is not unit-testable, so a text lock cannot see a semantic
# inversion. THE CURE: the decision lives in agent-boundary.sh's `render_exit`, selftest-driven over
# the whole state table; what is left here is structural, about a CALL — both workflows INVOKE the
# mode, pass it all four inputs, and neither decides an exit of its own. A re-planted inline decision
# reds HERE; a changed policy reds in agent-boundary.sh's selftest. No spelling satisfies both.

# _job_calls_render_exit <file> <job-key> -> 0 iff that job invokes the single-sourced decision.
# CODE-ONLY (_job_block strips comments): the files must stay free to EXPLAIN the mode by name.
_job_calls_render_exit() { _job_block "$1" "$2" | grep -qF 'agent-boundary.sh --render-exit'; }

# _job_exits_on_render <file> <job-key> -> 0 iff that job ENDS ON THE VALUE THE MODE RETURNED and
# nowhere decides an exit for itself: `exit "$_exit"` present; no `_exit=0`/`_exit=1` LITERAL
# assignment (the reviewer's mutant shape — `_exit=""` and `_exit=${_f1#exit=}` are the PARSE and are
# allowed, since they carry the mode's answer rather than replacing it); no bare `exit 0`/`exit 1`.
# It also requires the VERSION-SKEW PROBE (round 2): the job runs the BASE tree's agent-boundary.sh,
# which lacks `--render-exit` on the PR introducing it and during an adopter upgrade; the absent
# branch fails closed with `false` under `set -e` — never `exit 1`, which this anchor forbids.
# ⚠️ HONEST CEILING — A SPELLING LOCK SEES ONLY THE SPELLINGS IT ENUMERATES. A COMPUTED assignment
# (`_exit=$(printf 0)`, `_exit=$((1-1))`, `_exit=${x:-0}`) decides the conclusion just as completely
# and PASSES HERE. What bounds that is not this anchor but the SPLIT — the decision's home is
# render_exit, selftest-driven over every state, so a computed override reads as a visible
# re-implementation in review. A green here means "it does not decide in any KNOWN form", no more.
_job_exits_on_render() {
  _rb=$(_job_block "$1" "$2")
  printf '%s\n' "$_rb" | grep -qF 'exit "$_exit"' || return 1
  printf '%s\n' "$_rb" | grep -qF "grep -q -- '--render-exit' conformance/agent-boundary.sh" || return 1
  printf '%s\n' "$_rb" | grep -qE '_exit=[01]([^0-9]|$)' && return 1
  printf '%s\n' "$_rb" | grep -qE '(^|[^"$_a-zA-Z])exit[[:space:]]+[01]([^0-9]|$)' && return 1
  return 0
}

# _render_args_bound <file> <job-key> -> 0 iff all FOUR inputs reach the mode as the job's own
# variables. ⚠️ ROUND 2's FINDING, WHICH RE-OPENED THE ROUND-1 BLOCKER: every other anchor passes a
# job calling the mode with `--reviews-readable 1` HARDCODED — call present, exit obeyed, arms
# rendered — while an unreadable review list silently becomes "readable" and the waiting arm greens
# exactly where round 1 proved it must not. An anchor on the CALL is not one on what it is TOLD.
_render_args_bound() {
  _gb=$(_job_block "$1" "$2")
  for _ra in '--rc "$rc"' '--approvals-seen "$APPROVALS_SEEN"' \
             '--reviews-readable "$REVIEWS_READABLE"' '--failsafe "$_fs"'; do
    printf '%s\n' "$_gb" | grep -qF -- "$_ra" || return 1
  done
  return 0
}

# _renders_each_arm <file> -> 0 iff the job turns each arm into the surface a human reads. TEXT
# anchors, honestly so: they lock the ANNOTATION (prose), not the verdict (render_exit's); gutting one
# cannot flip a colour, only leave it unexplained — the PR #584 failure mode.
_renders_each_arm() {
  _ab=$(_job_block "$1" control-plane-ratification)
  printf '%s\n' "$_ab" | grep -qF '::notice title=%s::' || return 1
  printf '%s\n' "$_ab" | grep -qF 'control-plane-ratification: awaiting' || return 1
  printf '%s\n' "$_ab" | grep -qF '::error title=control-plane-ratification: not ratified' || return 1
  printf '%s\n' "$_ab" | grep -qF '::error title=control-plane-ratification: GATE ERROR' || return 1
  # AND THE UNRECOGNISED-ARM FALLBACK: "no arm" must not read as green (a fail-open at this seam).
  printf '%s\n' "$_ab" | grep -qF 'ratified|waiting|defective|error'
}

# _reads_no_seat_body <file> -> 0 iff the file's CODE never grades a seat approval's BODY. The seat
# SENTENCE RULE was retired on 2026-08-28: a seat is detected BY LOGIN, which the forge supplies and
# no body text can make truer, and the workflow prints the disclosure itself. Re-planting a body grep
# would reintroduce a state where a human's typing parks a governance gate.
_reads_no_seat_body() { ! code_only "$1" | grep -qiE 'seat-bodies|seat sentence'; }

# _job_if <file> <job-key> -> the job-level `if:` line(s), or empty if there is none.
# ⚠️ A SKIPPED JOB IS A MISSING REQUIRED VERDICT (review round 1, finding 1 — a BLOCKER, and the
# sharpest consequence of the key becoming the context). When a job-level `if:` evaluates false GitHub
# reports `skipped` under the required name: fail-open, or a permanent "Expected — waiting". The
# ratification gate carried `if: … head.repo.full_name == github.repository`, which a fork author could
# falsify with a COMMENTED self-review — harmless while the verdict lived in a posted run, a skip of
# the verdict itself once the job key became the context.
# `if[[:space:]]*:` — YAML permits whitespace before the colon (`if :` is a valid mapping key), so the
# tight `^    if:` form was defeatable by one space. Cheap to widen, and an anchor a space can dodge is
# not an anchor (review round 2, nit 2).
_job_if() { _job_block "$1" "$2" | grep -E '^    if[[:space:]]*:'; }

# _job_if_canon <file> <job-key> -> that job's `if:` in CANONICAL form: a TRAILING COMMENT stripped,
# then all whitespace removed. Every conditioned job in ci.yml carries a trailing `# why` comment, so
# a correctly copied clause arrives with one; comparing raw text would red on the comment and teach
# the next author to delete it — the inversion this file's `code_only` note already warns about. The
# comment is stripped, never read: it cannot make a wrong clause compare equal.
_job_if_canon() { _job_if "$1" "$2" | sed 's/[[:space:]]*#.*$//' | tr -d '[:space:]'; }

# THE ALLOWED JOB-LEVEL `if:` PER REQUIRED CONTEXT — the table anchor (5) below reads.
# ⚠️ SOURCE OF TRUTH IS REQUIRED-CHECKS.md; this table says what each of those contexts is ALLOWED to
# condition itself on, which that file does not record. Both drift directions are asserted below, so
# the table cannot silently disagree with the declaration: every name here must be declared there, and
# every declared context that is a job key in ci.yml must appear here.
#   PR_GUARDED  — `if: github.event_name == 'pull_request'` and NOTHING else. These gates adjudicate a
#                 PR head; on a push to main there is no PR to adjudicate, so the guard is legitimate.
#                 Any OTHER condition can skip the job on a PR event, and a skipped job reports
#                 `skipped` under the required name (fail-open, or a permanent "Expected").
#   ALWAYS      — `conformance` is the shard AGGREGATOR and MUST be `if: always()`; a plain `needs:`
#                 job is SKIPPED when a dependency fails, which would turn every genuine RED into a
#                 hung PR. That invariant is stated at the top of ci.yml and is load-bearing.
#   NO_IF       — nothing to condition on; these run on every event the workflow triggers on.
CI_IF_PR_GUARDED="backlog-presence threat-obligation uat-obligation a11y-obligation ceremony-binding loop-state review-lane"
CI_IF_ALWAYS="conformance"
CI_IF_NONE="bootstrap secret-scan docs-links"
CI_IF_CANONICAL="if:github.event_name=='pull_request'"
#   PUSH_GRADED_ONLY — `conformance-docs`, the ALWAYS-RUN doc job (CONFORMANCE-DOCS-SKIPS-ON-PUSH-
#                 GRADED, D-240903-3). It is NOT a required status context, so it is absent from
#                 REQUIRED-CHECKS.md and from both drift loops below on purpose; what it needs is the
#                 opposite lock — the ONE clause it may carry, and no other. It may skip on a push
#                 whose tree the merged PR already graded (that PR's run ran this very job, which the
#                 push-graded predicate requires), and it may NOT carry the docs-only clause: on a
#                 docs-only PR it is the only job grading the change.
CI_IF_PUSH_GRADED_ONLY="conformance-docs"
CI_IF_PUSH_GRADED_CANONICAL="if:needs.changes.outputs.push_graded!='true'"

_posts_nothing() {
  # `[[:space:]]+`, NOT `*`: a YAML permissions entry is always `checks: write`, and the zero-space
  # form matches prose describing the anchor itself (measured: a CI step named "…no checks:write…").
  ! code_only "$1" | grep -qE 'check-runs|checks:[[:space:]]+write'
}

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
  # ⚠️ THIS ANCHOR WAS RE-DERIVED ON 2026-08-17 (GUARD-PATH-ENUMERATION-INCOMPLETE S2 M2), AND THE
  # REASON IS A CURE, NOT AN ACCOMMODATION. It used to require `state" != NONE` — the class/gate
  # RECONCILIATION arm, which existed because `--class` was guard-core-only and under-detected
  # adapter-declared paths this gate treats as control-plane. S2 made the classifier union-aware, so
  # the two sides derive the SAME set and the arm was deleted as redundant (its sibling arm, a
  # `control-plane -> sensitive` downgrade reachable only from fail-safe states, was deleted as a
  # fabrication). Keeping the old anchor would have required the workflow to carry a dead arm purely
  # to satisfy a lock. What the workflow must still prove is the property the arms were reaching for
  # — THE DISPLAYED CLASS MUST NOT MISLEAD THE HUMAN AT THE CLICK — so the anchor now pins the
  # replacement, in both halves:
  #   (1) the class is VALIDATED against the closed token set before it is passed to --for-class. An
  #       invalid token makes the poster refuse, the required check goes ABSENT, and every PR in that
  #       state bricks; this is the guard that stops a disclosure string ever reaching that flag.
  #   (2) a FAIL-SAFED class is DISCLOSED as such on the judgment surface, so "control-plane, derived"
  #       and "control-plane, because we could not tell" do not render as the same sentence.
  grep -qF -- 'ordinary|sensitive|control-plane)' "$WF" || {
    echo "FAIL: $WF does not validate the derived class against the closed token set before passing it to --conclusion --for-class — an unvalidated token makes the poster refuse, the required check stays ABSENT and every PR in that state is bricked"; st=1; }
  # ⚠️ ANCHORED ON THE **RENDERED LITERAL**, NOT ON THE BARE TOKEN (review REV-I2, reproduced before
  # fixing). `grep -qF 'FAIL-SAFED'` was satisfied by the workflow's own PROSE — the comment block
  # explaining why the deleted arms died mentions the token twice — so deleting the entire disclosure
  # mechanism (the stderr read AND the step-summary line) left this check GREEN. Measured. A
  # presence check that a COMMENT can satisfy is not a check on behaviour. The string below is the
  # exact text printed onto $GITHUB_STEP_SUMMARY and appears nowhere else in the file.
  grep -qF -- 'change-class FAIL-SAFED, not derived' "$WF" || {
    echo "FAIL: $WF never RENDERS the 'change-class FAIL-SAFED, not derived' line onto the judgment surface — a class that was fail-safed (empty/unreadable change-set, degraded classifier) would show there as if it had been derived. NOTE: mentioning FAIL-SAFED in a comment does not satisfy this; the rendered literal is what is anchored"; st=1; }

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
  # (2b, A4) ci.yml builds its OWN files-API listing and feeds the docs-only classifier, so a truncated
  # listing there can drop non-.md paths, read docs_only=true and SKIP the conformance shards — a
  # COVERAGE loss. That third wiring site was locked by NOTHING: ratification-parity anchors
  # profiles/ratification.yml and the block below anchors this file's ratification workflow, so deleting
  # the ci.yml call left the whole battery green. Comment-stripped, so commenting the call out is also
  # caught (the sibling anchor's hollow-source case, applied here).
  # Trigger on the LISTING FILE, not on one spelling of the API URL: `pulls/${PR}/files` vs
  # `pulls/$PR/files` are functionally identical, so keying on the braced form let a plausible refactor
  # silently disable this whole anchor — the hollow-defeat class, reintroduced inside the fix for it.
  if [ -f "$CI_WF" ] && grep -qF -- '/tmp/changed.txt' "$CI_WF"; then
    code_only "$CI_WF" | grep -qF -- 'agent-boundary.sh --check-complete' || {
      echo "FAIL: $CI_WF derives a changed-file listing but never checks it for TRUNCATION — a listing capped by the forge's files API looks healthy (non-empty, exit 0) while paths are missing, so docs_only can read true and the conformance shards SKIP"; st=1; }
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
  # Only the CHECKOUT of the head is forbidden — the head sha may still be READ (it is the commit whose
  # mergeability this gate governs), so this must not be a bare token grep.
  if code_only "$WF" | grep -qF -- 'ref: ${{ github.event.pull_request.head.sha }}'; then
    echo "FAIL: $WF checks out the PR HEAD — it executes conformance/*.sh from that tree TO COMPUTE ITS OWN EXIT CODE, and that exit code IS the required status context, so the PR under test could rewrite the gate that judges it and forge its own ratification. (The older wording said 'while holding checks:write'; that token is gone, and the exposure is not — it moved from the posted verdict to the job's conclusion.)"; st=1
  fi
  grep -qF -- 'pulls/${PR}/files' "$WF" || {
    echo "FAIL: $WF does not take the changed-file listing from the PR files API — a git diff of a checked-out tree is head-dependent, and the wrong ref yields an EMPTY listing, which reads as 'no control-plane paths' (rc=0) and posts GREEN on an unratified PR"; st=1; }
  grep -qF -- '[ ! -s /tmp/changed.txt ]' "$WF" || {
    echo "FAIL: $WF has no empty-changed-file tripwire — a PR always changes >=1 file, so an empty listing means the listing could not be computed, NOT that there is nothing to ratify. Without this, a failed lookup reads as rc=0 (fail-open)"; st=1; }
  # (A4) The empty tripwire above catches a listing that could not be BUILT. This catches one the forge
  # TRUNCATED: the List-PR-files API stops at a cap and reports SUCCESS, so the listing is non-empty,
  # `set -e` never fires, and the gate classifies on paths it cannot enumerate — posting GREEN "nothing
  # to ratify" on a change-set nobody can see. Anchored on the CALL, because the decision deliberately
  # lives in agent-boundary.sh where it is --selftest-able and reachable by the non-vacuity sweep.
  # COMMENT-STRIPPED (I6): the raw-file grep was hollow-defeatable — commenting the call out left this
  # selftest green, while the sibling anchor in ratification-parity.sh strips comments and catches it.
  # Asymmetric hardening on two halves of the same anchor is how one half rots unnoticed.
  code_only "$WF" | grep -qF -- 'agent-boundary.sh --check-complete' || {
    echo "FAIL: $WF has no truncation tripwire — a changed-file listing capped by the forge's files API looks healthy (non-empty, exit 0) while paths are missing, so the gate would derive a change-class from an incomplete listing and post GREEN on a change-set it cannot fully enumerate"; st=1; }

  # (3b) A SKIPPED JOB IS A MISSING REQUIRED VERDICT — the anchor that replaced the same-repo
  # restriction, and an INVERSION of it (review round 1, BLOCKER).
  #
  # What stood here: `head.repo.full_name == github.repository` must be PRESENT, restricting the
  # `pull_request_review` re-trigger to same-repo PRs. It guarded a real thing — a fork PR's token can
  # be WRITABLE on a base-context review event, and "run the fork's code" + `checks: write` let an
  # attacker post `control-plane-ratification: success` on any sha. That premise died with the poster:
  # nothing is posted and the job is read-only.
  #
  # Why the restriction then became the DEFECT. The job key is now the required context, so a job that
  # does not RUN does not merely go stale — GitHub reports `skipped` under that name. A fork author
  # fires `pull_request_review` on their own PR with a COMMENTED self-review (self-APPROVAL is
  # forbidden, a self-comment-review is not), the `if:` is false, the job is SKIPPED, and the required
  # context resolves to a skip (fail-open) or hangs at "Expected" forever. So the invariant is now the
  # opposite: THE REQUIRED JOB MUST HAVE NO JOB-LEVEL `if:` AT ALL. Any fork distinction belongs at
  # step level, where it cannot change the job's conclusion.
  if [ -n "$(_job_if "$WF" control-plane-ratification)" ]; then
    echo "FAIL: $WF's control-plane-ratification job carries a job-level \`if:\` — its key IS the required status context, so any event on which that condition is false SKIPS the job and GitHub reports 'skipped' under the required name (fail-open, or a permanent 'Expected — waiting'). A fork author can reach exactly that state with a COMMENTED self-review. Put the condition at STEP level, where it cannot change the job's conclusion"; st=1
  fi

  # (4) `github.base_ref` is UNDEFINED on pull_request_review (populated only for
  # pull_request/pull_request_target), so a workflow that computes a diff base from it silently gets an
  # empty ref on review events. The base-tree design above removes the diff entirely — there is no base
  # ref to get wrong — so this is anchored as an ABSENCE: reintroducing github.base_ref would mean
  # someone has reintroduced a working-tree diff, and with it the whole fail-open class.
  if code_only "$WF" | grep -qF -- 'github.base_ref'; then
    echo "FAIL: $WF references github.base_ref — it is EMPTY on pull_request_review, and its presence means a head-relative diff has been reintroduced (see the trust-boundary note above)"; st=1
  fi

  # (4b) THE VERDICT IS THE JOB'S EXIT — there is no consumer of a posted mapping any more.
  # This anchor replaces the omitted-conclusion lock that stood here (a reviewer once collapsed that
  # if/else and reverted a whole slice with every selftest green — the lesson survives; its subject
  # does not). What must not silently vanish now is the LAST LINE: a verdict step that computes an rc
  # and then exits 0 regardless would satisfy a required context while enforcing nothing.
  #
  # ⚠️ PER JOB BLOCK, NOT PER FILE (review round 1, finding 2). The first version grepped the whole
  # file, so ONE job carrying the line satisfied it for every other job in the same workflow — in
  # ci.yml, a 2,000-line file with two required-context jobs, that is a lock that cannot see the
  # regression it exists for. Asserted for every required-context job in every file that ships one.
  # ⚠️ THE RATIFICATION JOB IS THE EXCEPTION (RATIFICATION-WAITING-IS-GREEN, 2026-08-28): it ends on
  # the RENDERING'S decision, not on the raw rc, because rc 1 with no approval yet is now GREEN. The
  # other required contexts below are unchanged — they still end on the gate's rc.
  _job_calls_render_exit "$WF" control-plane-ratification || {
    echo "FAIL: $WF's control-plane-ratification job does not invoke \`conformance/agent-boundary.sh --render-exit\` — the rc/approvals/readable/failsafe -> (exit, arm) decision is SINGLE-SOURCED there because it is selftest-driven, and a decision re-written inline in YAML can only be locked by its spelling (two measured mutants inverted the inline form while keeping every anchored literal)"; st=1; }
  _render_args_bound "$WF" control-plane-ratification || {
    echo "FAIL: $WF's control-plane-ratification job does not pass all four inputs to --render-exit as its own variables (\`--rc \"\$rc\"\`, \`--approvals-seen \"\$APPROVALS_SEEN\"\`, \`--reviews-readable \"\$REVIEWS_READABLE\"\`, \`--failsafe \"\$_fs\"\`). A HARDCODED argument keeps every other anchor green while silently answering the question for the gate — \`--reviews-readable 1\` alone re-opens the round-1 blocker, turning an unreadable review list back into a GREEN waiting check"; st=1; }
  _job_exits_on_render "$WF" control-plane-ratification || {
    echo "FAIL: $WF's control-plane-ratification job does not obey the render mode's answer: it must carry the version-skew probe (\`grep -q -- '--render-exit' conformance/agent-boundary.sh\`), end on \`exit \"\$_exit\"\`, and contain NO literal \`_exit=0\`/\`_exit=1\` assignment and no bare \`exit 0\`/\`exit 1\`. A literal exit assignment IS a policy decision, and it is exactly the shape both round-1 mutants took"; st=1; }
  _renders_each_arm "$WF" || {
    echo "FAIL: $WF's control-plane-ratification job no longer renders every arm to the human surface — the waiting ::notice ('awaiting a non-author approval'), the 'approval present but not ratifying' ::error, the GATE ERROR ::error, and the fail-closed fallback for an UNRECOGNISED arm. A colour with no annotation is the failure mode measured on PR #584; an unrecognised arm that falls through would be a green with no verdict at all"; st=1; }
  _reads_no_seat_body "$WF" || {
    echo "FAIL: $WF's CODE still grades a ratification seat's approval BODY ('seat-bodies' / 'seat sentence'). The sentence rule was RETIRED 2026-08-28 — a seat is detected BY LOGIN and the workflow prints the disclosure itself, so no human's typing can park this gate"; st=1; }
  if [ -f "docs/ROADMAP-KIT.md" ] && [ -f "$CI_WF" ]; then
    for _ctx in backlog-presence ceremony-binding; do
      _job_exits_on_rc "$CI_WF" "$_ctx" || {
        echo "FAIL: $CI_WF's $_ctx job never ENDS ON THE GATE'S rc — its conclusion is the required context, so it would report green while enforcing nothing"; st=1; }
    done

    # (5) THE JOB-LEVEL `if:` TABLE — EVERY required context in ci.yml, not just the two this slice
    # touched (review round 2). A skipped job reports `skipped` under the required name, so the
    # condition a required job carries is part of its enforcement surface, and every one of them
    # deserves the same scrutiny the two gates got. Three allowed shapes, declared above.
    for _ctx in $CI_IF_PR_GUARDED; do
      _cif=$(_job_if "$CI_WF" "$_ctx" | tr -d '[:space:]')
      [ "$_cif" = "$CI_IF_CANONICAL" ] || {
        echo "FAIL: $CI_WF's $_ctx job-level \`if:\` is '$_cif', not exactly \`if: github.event_name == 'pull_request'\`. Its key IS a required status context: any OTHER condition can skip the job on a PR event, and GitHub reports 'skipped' under the required name (fail-open, or a permanent 'Expected'). The pull_request guard is allowed only because a push-to-main run has no PR head to adjudicate"; st=1; }
    done
    for _ctx in $CI_IF_ALWAYS; do
      [ "$(_job_if "$CI_WF" "$_ctx" | tr -d '[:space:]')" = "if:always()" ] || {
        echo "FAIL: $CI_WF's $_ctx job is not \`if: always()\` — it is the shard AGGREGATOR, and a plain needs:-gated job is SKIPPED when a dependency fails, which turns every genuine RED into a required check stuck at 'Expected' (a hung PR). See the invariant at the top of $CI_WF"; st=1; }
    done
    for _ctx in $CI_IF_NONE; do
      [ -z "$(_job_if "$CI_WF" "$_ctx")" ] || {
        echo "FAIL: $CI_WF's $_ctx job has GROWN a job-level \`if:\` — it is a required status context with nothing to condition on, and any condition that can be false is an event on which the required check reports 'skipped'"; st=1; }
    done
    # (5b) THE ALWAYS-RUN DOC JOB'S ONE PERMITTED CLAUSE (CONFORMANCE-DOCS-SKIPS-ON-PUSH-GRADED).
    # Kit-tree only, and deliberately OUTSIDE both drift loops below: `conformance-docs` is not a
    # required status context (it is adjudicated through the `conformance` aggregator's `needs:`),
    # so REQUIRED-CHECKS.md neither declares it nor should. The lock pins the exact SHAPE, so
    # REMOVING the clause reds too — not only adding a forbidden one.
    for _ctx in $CI_IF_PUSH_GRADED_ONLY; do
      _has_job_key "$CI_WF" "$_ctx" || {
        echo "FAIL: $CI_WF has no job keyed exactly '$_ctx' — the always-run doc job is where every doc-sensitive check now lives, and a renamed key leaves this lock pointed at nothing while the docs-only and push-graded skips keep standing on it"; st=1; continue; }
      _cif=$(_job_if_canon "$CI_WF" "$_ctx")
      [ "$_cif" = "$CI_IF_PUSH_GRADED_CANONICAL" ] || {
        echo "FAIL: $CI_WF's $_ctx job-level \`if:\` is '$_cif', not exactly \`if: needs.changes.outputs.push_graded != 'true'\`. That is the ONE clause it may carry: the push-graded skip is sound because the graded PR's own run ran this very job. THE DOCS-ONLY CLAUSE IS FORBIDDEN HERE — on a docs-only PR this job is the only one grading the change (every check that can read a .md was moved into it), so skipping it there would leave that lane graded by nothing and would falsify the push-graded induction's premise. Removing the \`if:\` entirely reds too: the job would re-run on every push over a tree the PR already graded"; st=1; }
    done
    # BOTH DRIFT DIRECTIONS between the table and REQUIRED-CHECKS.md — the reason this is a table and
    # not six hardcoded greps. Without these, a context added to the declaration would be silently
    # unconditioned, and a name that stopped being required would keep a lock pointed at nothing.
    for _ctx in $CI_IF_PR_GUARDED $CI_IF_ALWAYS $CI_IF_NONE; do
      grep -qx -- "$_ctx" REQUIRED-CHECKS.md || {
        echo "FAIL: proportional-gate-wired's job-level-if table names '$_ctx', which REQUIRED-CHECKS.md does not declare as a required context — the table has drifted from its source of truth"; st=1; }
    done
    for _ctx in $(grep -xE '[a-z][a-z0-9-]*' REQUIRED-CHECKS.md); do
      _has_job_key "$CI_WF" "$_ctx" || continue          # declared, but supplied by another workflow
      case " $CI_IF_PR_GUARDED $CI_IF_ALWAYS $CI_IF_NONE " in
        *" $_ctx "*) ;;
        *) echo "FAIL: REQUIRED-CHECKS.md declares '$_ctx' and $CI_WF has a job of that key, but proportional-gate-wired's job-level-if table does not cover it — its skip condition is unlocked"; st=1 ;;
      esac
    done
    # `branch-protection-live` (REQUIRED-CONTEXT-SET-LOCK, 2026-08-28) is a required context supplied by its
    # OWN workflow file, so the $CI_WF legs above skip it ("supplied by another workflow"); same NO_IF
    # invariant, locked here by presence + no job-level `if:`. A rename does NOT red anything — the
    # context simply never reports and the PR hangs at 'Expected' — so the key itself is pinned too.
    _bpl=".github/workflows/branch-protection-live.yml"
    _has_job_key "$_bpl" branch-protection-live || { echo "FAIL: $_bpl has no job keyed 'branch-protection-live' — REQUIRED-CHECKS.md declares that context, and a renamed or missing key never reports (a hung PR, not a red)"; st=1; }
    [ -z "$(_job_if "$_bpl" branch-protection-live)" ] || { echo "FAIL: $_bpl's branch-protection-live job has GROWN a job-level \`if:\` — a required context with nothing to condition on; any false condition reports 'skipped'"; st=1; }
  fi
  if [ -f "docs/ROADMAP-KIT.md" ]; then
    # THE MIRROR GETS THE SAME FOUR ANCHORS, not the rc one: adopters must inherit the same rendering,
    # and a mirror that diverges here is the class this repo has paid a Critical for.
    _job_calls_render_exit profiles/ratification.yml control-plane-ratification || {
      echo "FAIL: profiles/ratification.yml's control-plane-ratification job does not invoke \`agent-boundary.sh --render-exit\` — adopters would inherit an inline, un-unit-testable copy of the decision, which is the divergence class this repo has paid a Critical for"; st=1; }
    _render_args_bound profiles/ratification.yml control-plane-ratification || {
      echo "FAIL: profiles/ratification.yml does not pass all four inputs to --render-exit as its own variables — a hardcoded \`--reviews-readable 1\` (or any of the other three) would ship adopters a gate that answers its own question while every other anchor stays green"; st=1; }
    _job_exits_on_render profiles/ratification.yml control-plane-ratification || {
      echo "FAIL: profiles/ratification.yml's control-plane-ratification job does not obey the render mode's answer (the version-skew probe, \`exit \"\$_exit\"\`, no literal _exit=0/1, no bare exit 0/1) — the adopter reference would ship a gate that decides for itself, or one that greens when its conformance/ predates the mode"; st=1; }
    _renders_each_arm profiles/ratification.yml || {
      echo "FAIL: profiles/ratification.yml does not render every arm to the human surface (waiting ::notice, both ::errors, and the fail-closed fallback for an unrecognised arm) — adopters would get colours with no explanation, or a green with no verdict"; st=1; }
    _reads_no_seat_body profiles/ratification.yml || {
      echo "FAIL: profiles/ratification.yml's CODE grades a seat approval's BODY — the retired sentence rule must not ship to adopters"; st=1; }
    # (d) THE BASE-TREE ADJUDICATION, MIRRORED. The kit's copy is anchored above; without this the
    # adopter reference could start executing PR-head code to compute its own required verdict.
    grep -qF -- 'ref: ${{ github.event.pull_request.base.sha }}' profiles/ratification.yml || {
      echo "FAIL: profiles/ratification.yml does not check out the BASE commit — the adopter's gate would adjudicate using code from the PR under test"; st=1; }
    if code_only profiles/ratification.yml | grep -qF -- 'ref: ${{ github.event.pull_request.head.sha }}'; then
      echo "FAIL: profiles/ratification.yml checks out the PR HEAD — the PR under test could rewrite the gate that judges it and forge its own ratification"; st=1
    fi
    [ -n "$(_job_if profiles/ratification.yml control-plane-ratification)" ] && {
      echo "FAIL: profiles/ratification.yml's control-plane-ratification job carries a job-level \`if:\` — a skipped job is a missing required verdict (see anchor 3b); adopters would inherit the fork-skippable gate"; st=1; }
    for _ctx in backlog-presence ceremony-binding loop-state; do
      _job_exits_on_rc profiles/adopter-gates.yml "$_ctx" || {
        echo "FAIL: profiles/adopter-gates.yml's $_ctx job never ends on the gate's rc — the adopter reference would ship a gate that reports green while enforcing nothing (loop-state reaches this line only in ENFORCE mode; the observe escape is asserted by adopter-gates-parity.sh)"; st=1; }
      # The MIRROR gets the same `if:` scrutiny as the kit's own gates. adopter-gates.yml triggers on
      # `pull_request` only, so the guard is redundant there rather than load-bearing — but it is the
      # shape an adopter copies, and a fork-skippable condition landing in the REFERENCE ships the
      # defect to every adopter at once (the mirror-divergence class this repo has paid a Critical for).
      _mif=$(_job_if profiles/adopter-gates.yml "$_ctx" | tr -d '[:space:]')
      [ "$_mif" = "$CI_IF_CANONICAL" ] || [ -z "$_mif" ] || {
        echo "FAIL: profiles/adopter-gates.yml's $_ctx job-level \`if:\` is '$_mif' — allowed values are exactly \`if: github.event_name == 'pull_request'\` or none at all. Its key IS the adopter's required status context, and any other condition can skip the job on a PR event, reporting 'skipped' under the required name"; st=1; }
    done
  fi

  # (6) THE JOB KEY *IS* THE REQUIRED CONTEXT — the inverse of the anchor that stood here.
  #
  # This block used to require the OPPOSITE: that a job key never equal the check-run name posted in
  # the same file (two same-named runs on one sha, the job's own completing last — measured on PR
  # #446). That rule was correct WHILE a poster existed. With the posters deleted there is no second
  # run to collide with, and the key must BE the name or branch protection has nothing to read.
  #
  # ⚠️ GATED ON A KIT-TREE MARKER, and that gating is load-bearing for the same reason it always was:
  # this check is registered in verify.sh WITHOUT --kitself and runs inside a freshly incepted adopter
  # project, whose emitted ci.yml carries none of these jobs. An unconditional anchor would FAIL every
  # adopter over a gate they do not have — "the classic path to the gate being deleted".
  # docs/ROADMAP-KIT.md is export-ignored, so it distinguishes the kit tree WITHOUT letting a rename
  # switch the anchors off. Note the anchors are NOT gated on their own subject: a presence check on
  # its own job key would be disarmed by the very rename it exists to catch (review defeated exactly
  # that in the retired version).
  if [ -f "docs/ROADMAP-KIT.md" ] && [ -f "$CI_WF" ]; then
    for _ctx in $REAL_JOB_CONTEXTS; do
      _has_job_key "$CI_WF" "$_ctx" || _has_job_key "$WF" "$_ctx" || {
        echo "FAIL: neither $CI_WF nor $WF declares a job keyed exactly '$_ctx' — that name is a REQUIRED status context and, since the posters were deleted, it can only be supplied by a job of that name. A renamed key unbinds the check silently"; st=1; }
    done
    # (6b) ...AND NOTHING MAY POST. A reintroduced poster does not merely duplicate the verdict — it
    # reintroduces the failure this slice fixed (protection not matching an API-posted run) and, with
    # `checks: write`, re-opens the escalation the two-job splits existed to contain: a token that can
    # post a check-run of ANY name on ANY sha, held by a job that executes the PR's own scripts.
    for _f in "$CI_WF" "$WF"; do
      [ -f "$_f" ] || continue
      _posts_nothing "$_f" || {
        echo "FAIL: $_f posts a check-run or holds 'checks: write' (code, not comment) — the required contexts are JOB CONCLUSIONS now; an API-posted run is what branch protection stopped matching, and the scope re-opens the forge-your-own-verdict escalation"; st=1; }
    done
  fi

  # (7) THE MIRRORS. profiles/ratification.yml and profiles/adopter-gates.yml are what an adopter
  # actually runs, and the mirror-divergence class has already cost this repo a Critical: fixing the
  # kit alone while the reference copies keep the retired design ships the broken gate to customers
  # and enjoys the fix privately. Same two properties, same scope, kit-tree only (the mirrors exist
  # only in the kit — an adopter has the INSTALLED copies, checked as $WF/$CI_WF above).
  if [ -f "docs/ROADMAP-KIT.md" ]; then
    for _m in profiles/ratification.yml profiles/adopter-gates.yml; do
      [ -f "$_m" ] || { echo "FAIL: $_m is missing — the adopter reference copy of a required gate"; st=1; continue; }
      _posts_nothing "$_m" || {
        echo "FAIL: $_m posts a check-run or holds 'checks: write' — the adopter reference must carry the same real-job design as the kit's own, or adopters get the retired poster"; st=1; }
    done
    for _ctx in backlog-presence ceremony-binding loop-state; do
      _has_job_key profiles/adopter-gates.yml "$_ctx" || {
        echo "FAIL: profiles/adopter-gates.yml has no job keyed exactly '$_ctx' — the adopter's required context would have nothing to report it"; st=1; }
    done
    _has_job_key profiles/ratification.yml control-plane-ratification || {
      echo "FAIL: profiles/ratification.yml has no job keyed exactly 'control-plane-ratification' — the adopter's §13 required context would have nothing to report it"; st=1; }
  fi

  # (7b) MUTANT LEGS for (6)/(7). Fixtures, never the live tree: an anchor that has only ever been run
  # against a PASSING file has not been shown to fail. Each mutant is the realistic regression — the
  # retired design walking back in — not a syntactic scribble.
  _mx=$(mktemp -d)
  printf '  ceremony-binding:\n    runs-on: ubuntu-latest\n' > "$_mx/ok.yml"
  _has_job_key "$_mx/ok.yml" ceremony-binding || { echo "FAIL: mutant — _has_job_key must find an exactly-keyed job"; st=1; }
  # mutant 1: the job key renamed back to the gate-*/post-* convention -> the context is unbound
  printf '  gate-ceremony-binding:\n    runs-on: ubuntu-latest\n' > "$_mx/renamed.yml"
  _has_job_key "$_mx/renamed.yml" ceremony-binding && { echo "FAIL: mutant — a renamed job key must NOT satisfy the context anchor"; st=1; }
  # mutant 2: a poster re-planted -> the check-runs API call must red
  printf '  ceremony-binding:\n    steps:\n      - run: gh api "repos/x/commits/$SHA/check-runs?check_name=ceremony-binding"\n' > "$_mx/poster.yml"
  _posts_nothing "$_mx/poster.yml" && { echo "FAIL: mutant — a re-planted check-run poster must NOT pass the posts-nothing anchor"; st=1; }
  # mutant 3: `checks: write` re-planted -> must red even with no posting call in sight
  printf '  ceremony-binding:\n    permissions:\n      checks: write\n' > "$_mx/scope.yml"
  _posts_nothing "$_mx/scope.yml" && { echo "FAIL: mutant — a re-planted 'checks: write' scope must NOT pass the posts-nothing anchor"; st=1; }
  # mutant 4: the same two tokens IN COMMENTS -> must PASS. The workflows have to stay free to explain
  # the retired design; a lock that forbids the documentation is the defect class this file fixed twice.
  printf '  ceremony-binding:\n    # was: gh api .../check-runs, and the poster held checks: write\n    runs-on: ubuntu-latest\n' > "$_mx/prose.yml"
  _posts_nothing "$_mx/prose.yml" || { echo "FAIL: mutant — the posts-nothing anchor fired on a COMMENT; it must read code only"; st=1; }

  # ── mutants for the PER-JOB anchors (review round 1, findings 1 and 2) ──────────────────────────
  # A two-job fixture, both jobs correct, is the positive control: the per-job reader must find each.
  printf 'jobs:\n  backlog-presence:\n    if: github.event_name == %spull_request%s\n    steps:\n      - run: [ "$rc" = 0 ] || exit 1\n  ceremony-binding:\n    if: github.event_name == %spull_request%s\n    steps:\n      - run: [ "$rc" = 0 ] || exit 1\n' "'" "'" "'" "'" > "$_mx/two.yml"
  for _j in backlog-presence ceremony-binding; do
    _job_exits_on_rc "$_mx/two.yml" "$_j" || { echo "FAIL: mutant — _job_exits_on_rc must find the exit line in job '$_j'"; st=1; }
  done
  # mutant 5: THE FINDING-2 REGRESSION ITSELF — strip the exit line from ONE job block only. A
  # whole-file grep passes this fixture (the other job still carries the line); the per-job reader must
  # not. This is the exact shape the retired whole-file anchor could not see.
  printf 'jobs:\n  backlog-presence:\n    steps:\n      - run: echo verdict-computed-but-never-enforced\n  ceremony-binding:\n    steps:\n      - run: [ "$rc" = 0 ] || exit 1\n' > "$_mx/onejob.yml"
  code_only "$_mx/onejob.yml" | grep -qF '[ "$rc" = 0 ] || exit 1' \
    || { echo "FAIL: mutant — the one-job fixture must still satisfy a WHOLE-FILE grep, or it does not demonstrate the finding"; st=1; }
  _job_exits_on_rc "$_mx/onejob.yml" backlog-presence && { echo "FAIL: mutant — a job block missing the exit line must RED even when a SIBLING job in the same file carries it (the whole-file-grep defect)"; st=1; }
  _job_exits_on_rc "$_mx/onejob.yml" ceremony-binding || { echo "FAIL: mutant — the sibling job that DOES carry the exit line must still pass"; st=1; }
  # mutant 6: a job-level `if:` re-planted on the required ratification job -> must be SEEN.
  printf 'jobs:\n  control-plane-ratification:\n    if: github.event.pull_request.head.repo.full_name == github.repository\n    steps:\n      - run: [ "$rc" = 0 ] || exit 1\n' > "$_mx/reif.yml"
  [ -n "$(_job_if "$_mx/reif.yml" control-plane-ratification)" ] || { echo "FAIL: mutant — a re-planted job-level if: must be detected (a skipped job is a missing required verdict)"; st=1; }
  printf 'jobs:\n  control-plane-ratification:\n    runs-on: ubuntu-latest\n    steps:\n      - run: [ "$rc" = 0 ] || exit 1\n' > "$_mx/noif.yml"
  [ -z "$(_job_if "$_mx/noif.yml" control-plane-ratification)" ] || { echo "FAIL: mutant — a job with NO job-level if: must read as none"; st=1; }
  # mutant 7: an `if:` that is NOT the bare pull_request guard -> the exact-text anchor must reject it.
  # This is how the fork-skippable condition comes back wearing a legitimate shape. Planted on
  # a11y-obligation — one of the jobs round 2 brought under the table, not one of the two this slice
  # edited, so the mutant proves the WIDENED coverage rather than re-proving the original pair.
  printf 'jobs:\n  a11y-obligation:\n    if: github.event_name == %spull_request%s && github.actor != %sdependabot[bot]%s\n    steps:\n      - run: [ "$rc" = 0 ] || exit 1\n' "'" "'" "'" "'" > "$_mx/extraif.yml"
  [ "$(_job_if "$_mx/extraif.yml" a11y-obligation | tr -d '[:space:]')" = "$CI_IF_CANONICAL" ] && { echo "FAIL: mutant — an if: carrying an EXTRA condition must not read as the bare pull_request guard"; st=1; }
  # mutant 7b: WHITESPACE BEFORE THE COLON (`if :`) — YAML-legal, and it dodged the old `^    if:`
  # regex entirely, which would have read the job as carrying NO condition at all (round 2, nit 2).
  printf 'jobs:\n  a11y-obligation:\n    if : github.event.pull_request.head.repo.full_name == github.repository\n    steps:\n      - run: echo x\n' > "$_mx/spacecolon.yml"
  [ -n "$(_job_if "$_mx/spacecolon.yml" a11y-obligation)" ] || { echo "FAIL: mutant — \`if :\` (space before the colon) is valid YAML and must still be SEEN as a job-level if"; st=1; }
  # mutant 7c: the aggregator's `if: always()` must be recognised as itself, and must NOT be
  # interchangeable with the PR guard in either direction.
  printf 'jobs:\n  conformance:\n    if: always()\n    steps:\n      - run: echo x\n' > "$_mx/agg.yml"
  [ "$(_job_if "$_mx/agg.yml" conformance | tr -d '[:space:]')" = "if:always()" ] || { echo "FAIL: mutant — the aggregator's if: always() must read back exactly"; st=1; }
  [ "$(_job_if "$_mx/agg.yml" conformance | tr -d '[:space:]')" = "$CI_IF_CANONICAL" ] && { echo "FAIL: mutant — if: always() must not satisfy the PR-guard anchor"; st=1; }
  # mutant 7d: a no-`if:` required job that GROWS one -> the NO_IF arm must see it.
  printf 'jobs:\n  bootstrap:\n    if: github.ref == %srefs/heads/main%s\n    steps:\n      - run: echo x\n' "'" "'" > "$_mx/grewif.yml"
  [ -n "$(_job_if "$_mx/grewif.yml" bootstrap)" ] || { echo "FAIL: mutant — a required job that grew a job-level if must be detected"; st=1; }

  # ── mutants for the PUSH-GRADED-ONLY arm (CONFORMANCE-DOCS-SKIPS-ON-PUSH-GRADED, D-240903-3) ────
  # The positive control is the LIVE ci.yml, asserted inside the kit-tree guard above; these are the
  # negatives, as printf'd fragments (this file's idiom — an anchor only ever run against a passing
  # file has not been shown to fail).
  printf 'jobs:\n  conformance-docs:\n    needs: changes\n    if: needs.changes.outputs.push_graded != %strue%s\n    steps:\n      - run: echo x\n' "'" "'" > "$_mx/pg-ok.yml"
  [ "$(_job_if_canon "$_mx/pg-ok.yml" conformance-docs)" = "$CI_IF_PUSH_GRADED_CANONICAL" ] \
    || { echo "FAIL: mutant — the canonical push-graded-only \`if:\` must read back as the canonical form"; st=1; }
  # the TRAILING-COMMENT shape: every other `if:` in ci.yml carries one, so a copy-paste will too.
  # It must still compare equal — a lock that reds on a comment teaches people to delete comments.
  printf 'jobs:\n  conformance-docs:\n    if: needs.changes.outputs.push_graded != %strue%s   # skip on a push whose tree the merged PR graded\n    steps:\n      - run: echo x\n' "'" "'" > "$_mx/pg-comment.yml"
  [ "$(_job_if_canon "$_mx/pg-comment.yml" conformance-docs)" = "$CI_IF_PUSH_GRADED_CANONICAL" ] \
    || { echo "FAIL: mutant — a TRAILING COMMENT on the push-graded \`if:\` must still compare equal to the canonical form"; st=1; }
  # mutant PG-1 (load-bearing): the docs-only clause added -> the doc-sensitive checks would stop
  # running on the one lane where nothing else grades a `.md`.
  printf 'jobs:\n  conformance-docs:\n    if: needs.changes.outputs.docs_only != %strue%s && needs.changes.outputs.push_graded != %strue%s\n    steps:\n      - run: echo x\n' "'" "'" "'" "'" > "$_mx/pg-docsonly.yml"
  [ "$(_job_if_canon "$_mx/pg-docsonly.yml" conformance-docs)" = "$CI_IF_PUSH_GRADED_CANONICAL" ] \
    && { echo "FAIL: mutant PG-1 — the docs-only clause added to conformance-docs must NOT read as the canonical push-graded-only if:"; st=1; }
  # mutant PG-2: the `if:` removed -> the job runs on every push again (the cost this slice removed);
  # the lock pins the exact SHAPE, not merely "no forbidden clause".
  printf 'jobs:\n  conformance-docs:\n    needs: changes\n    steps:\n      - run: echo x\n' > "$_mx/pg-noif.yml"
  [ "$(_job_if_canon "$_mx/pg-noif.yml" conformance-docs)" = "$CI_IF_PUSH_GRADED_CANONICAL" ] \
    && { echo "FAIL: mutant PG-2 — a conformance-docs job with NO job-level if: must NOT satisfy the push-graded-only anchor"; st=1; }
  # mutant PG-3: the job key renamed -> the anchor addresses nothing and must say so.
  printf 'jobs:\n  conformance-docs-v2:\n    if: needs.changes.outputs.push_graded != %strue%s\n    steps:\n      - run: echo x\n' "'" "'" > "$_mx/pg-renamed.yml"
  _has_job_key "$_mx/pg-renamed.yml" conformance-docs \
    && { echo "FAIL: mutant PG-3 — a renamed conformance-docs job key must NOT satisfy the anchor"; st=1; }
  # mutant PG-4: the clause planted at STEP level (8 spaces) — it conditions one step, not the job,
  # so the job still runs; a reader skimming for the string would call it locked.
  printf 'jobs:\n  conformance-docs:\n    steps:\n      - run: echo x\n        if: needs.changes.outputs.push_graded != %strue%s\n' "'" "'" > "$_mx/pg-steplevel.yml"
  [ "$(_job_if_canon "$_mx/pg-steplevel.yml" conformance-docs)" = "$CI_IF_PUSH_GRADED_CANONICAL" ] \
    && { echo "FAIL: mutant PG-4 — a STEP-level if: must NOT read as the job-level push-graded guard"; st=1; }

  # ── mutants for the RENDERING anchors (RATIFICATION-WAITING-IS-GREEN, 2026-08-28; rebuilt after
  # review round 1, finding 3 — see the note above the helpers). The CLEAN fixture is the obedient
  # shape: it calls the mode, parses it, renders each arm, and exits on the returned value.
  _mk_rat() {  # <path> — the clean rendering fixture
    {
      printf 'jobs:\n  control-plane-ratification:\n    runs-on: ubuntu-latest\n    steps:\n      - run: |\n'
      printf '          if grep -q -- %s--render-exit%s conformance/agent-boundary.sh 2>/dev/null; then\n' "'" "'"
      printf '          sh conformance/agent-boundary.sh --render-exit --rc "$rc" --approvals-seen "$APPROVALS_SEEN" --reviews-readable "$REVIEWS_READABLE" --failsafe "$_fs" > /tmp/render.txt\n'
      printf '          else\n'
      printf "            printf '::error title=control-plane-ratification: gate predates --render-exit::fail-closed\\\\n'\n"
      printf '            false\n'
      printf '          fi\n'
      printf '          _exit=""; _arm=""\n'
      printf '          while read -r _f1 _f2; do _exit=${_f1#exit=}; _arm=${_f2#arm=}; done < /tmp/render.txt\n'
      printf '          case "$_arm" in\n'
      printf '            ratified|waiting|defective|error) ;;\n'
      printf '            *) sh conformance/agent-boundary.sh --render-exit > /tmp/render.txt\n'
      printf '               while read -r _f1 _f2; do _exit=${_f1#exit=}; _arm=${_f2#arm=}; done < /tmp/render.txt ;;\n'
      printf '          esac\n'
      printf '          case "$_arm" in\n'
      printf "            waiting) _wtitle='control-plane-ratification: awaiting a non-author approval'\n"
      printf "                     printf '::notice title=%%s::%%s\\\\n' \"\$_wtitle\" \"\$_wmsg\" ;;\n"
      printf "            defective) printf '::error title=control-plane-ratification: not ratified — a human acted; the review list was unreadable; or the class fail-safed::%%s\\\\n' \"\$_dmsg\" ;;\n"
      printf "            error) printf '::error title=control-plane-ratification: GATE ERROR — could not evaluate the control-plane diff::%%s\\\\n' \"\$_msg\" ;;\n"
      printf '          esac\n'
      printf '          exit "$_exit"\n'
    } > "$1"
  }
  _mk_rat "$_mx/rat-ok.yml"
  _job_calls_render_exit "$_mx/rat-ok.yml" control-plane-ratification || { echo "FAIL: mutant — the clean rendering fixture must satisfy _job_calls_render_exit"; st=1; }
  _job_exits_on_render   "$_mx/rat-ok.yml" control-plane-ratification || { echo "FAIL: mutant — the clean rendering fixture must satisfy _job_exits_on_render"; st=1; }
  _renders_each_arm      "$_mx/rat-ok.yml" || { echo "FAIL: mutant — the clean rendering fixture must satisfy _renders_each_arm"; st=1; }
  _render_args_bound     "$_mx/rat-ok.yml" control-plane-ratification || { echo "FAIL: mutant — the clean rendering fixture must satisfy _render_args_bound"; st=1; }
  grep -v -- '--render-exit --rc' "$_mx/rat-ok.yml" > "$_mx/rat-noargs.yml"
  _render_args_bound "$_mx/rat-noargs.yml" control-plane-ratification && { echo "FAIL: mutant — a job whose argument line is gone must NOT pass _render_args_bound"; st=1; }
  # ★ ONE MUTANT PER ARGUMENT (round 2): each HARDCODES one input, leaving every other anchor green.
  # `--reviews-readable 1` is the live one (an unreadable list becomes "readable" and the waiting arm
  # re-greens); all four are the same defect — the gate stops being told and starts being answered.
  for _rm in '--rc "$rc"|--rc 1' '--approvals-seen "$APPROVALS_SEEN"|--approvals-seen 0' \
             '--reviews-readable "$REVIEWS_READABLE"|--reviews-readable 1' '--failsafe "$_fs"|--failsafe 0'; do
    _rm_from=${_rm%%|*}; _rm_to=${_rm#*|}
    sed "s|$_rm_from|$_rm_to|" "$_mx/rat-ok.yml" > "$_mx/rat-arg.yml"
    _render_args_bound "$_mx/rat-arg.yml" control-plane-ratification \
      && { echo "FAIL: mutant — a HARDCODED '$_rm_to' must NOT pass _render_args_bound (the gate would answer its own question while every other anchor stays green)"; st=1; }
  done
  # ★ MUTANT A — the reviewer's own: `_exit=1` inside the waiting arm. Every anchored literal intact.
  sed 's/_wtitle=/_exit=1; _wtitle=/' "$_mx/rat-ok.yml" > "$_mx/rat-mutA.yml"
  _job_exits_on_render "$_mx/rat-mutA.yml" control-plane-ratification && { echo "FAIL: mutant A — an \`_exit=1\` planted inside the waiting arm must NOT pass _job_exits_on_render (red-while-waiting re-planted with every anchored literal intact)"; st=1; }
  # ★ MUTANT B — the same inversion in its other spelling: a bare `exit 1` in the job.
  sed 's/^          esac$/          exit 1/' "$_mx/rat-ok.yml" > "$_mx/rat-mutB.yml"
  _job_exits_on_render "$_mx/rat-mutB.yml" control-plane-ratification && { echo "FAIL: mutant B — a bare \`exit 1\` in the job must NOT pass _job_exits_on_render; it decides the conclusion regardless of the mode's answer"; st=1; }
  # mutant B2: `exit 0` is the fail-OPEN twin of B — a job that greens whatever the mode returned.
  cp "$_mx/rat-ok.yml" "$_mx/rat-mut0.yml"
  printf '          exit 0\n' >> "$_mx/rat-mut0.yml"
  _job_exits_on_render "$_mx/rat-mut0.yml" control-plane-ratification && { echo "FAIL: mutant B2 — a bare \`exit 0\` must NOT pass: it is the fail-OPEN spelling of the same self-made decision"; st=1; }
  # mutant C: THE CALL REMOVED — the decision comes home to the YAML, where it cannot be unit-tested.
  grep -v -- '--render-exit' "$_mx/rat-ok.yml" > "$_mx/rat-nocall.yml"
  _job_calls_render_exit "$_mx/rat-nocall.yml" control-plane-ratification && { echo "FAIL: mutant C — a job that no longer invokes --render-exit must NOT pass _job_calls_render_exit"; st=1; }
  # mutant C2: the call present only as a COMMENT — hollow, and the code-only read must catch it. On
  # EVERY line carrying it (the fallback arm has a second call; hiding one is not this mutant).
  sed 's|^\([[:space:]]*\).*--render-exit.*$|\1# &|' "$_mx/rat-ok.yml" > "$_mx/rat-commentcall.yml"
  _job_calls_render_exit "$_mx/rat-commentcall.yml" control-plane-ratification && { echo "FAIL: mutant C2 — a COMMENTED-OUT --render-exit call must NOT satisfy the anchor"; st=1; }
  # mutant 9: the ::notice deleted -> the waiting state greens with NO explanation, which is worse
  # than the red it replaced (a green on an unratified control-plane PR with nothing said).
  grep -v '::notice' "$_mx/rat-ok.yml" > "$_mx/rat-nonotice.yml"
  _renders_each_arm "$_mx/rat-nonotice.yml" && { echo "FAIL: mutant — a waiting arm with no ::notice must NOT pass _renders_each_arm: a green with no explanation is a silent green"; st=1; }
  # mutant 10: the DEFECTIVE annotation deleted -> the red arrives with no reason on the Checks list.
  grep -v 'control-plane-ratification: not ratified' "$_mx/rat-ok.yml" > "$_mx/rat-nodefect.yml"
  _renders_each_arm "$_mx/rat-nodefect.yml" && { echo "FAIL: mutant — a file with no 'not ratified' ::error must NOT pass _renders_each_arm"; st=1; }
  # mutant 11: THE FALLBACK DELETED. An unrecognised arm (a checkout predating the mode) falls through
  # with _exit empty, and `exit ""` is exit 0 in POSIX sh: a GREEN with no verdict at all.
  grep -v 'ratified|waiting|defective|error' "$_mx/rat-ok.yml" > "$_mx/rat-nofallback.yml"
  _renders_each_arm "$_mx/rat-nofallback.yml" && { echo "FAIL: mutant — a job with no fail-closed fallback for an UNRECOGNISED arm must NOT pass; an empty _exit exits 0"; st=1; }
  # mutant 12: a body-sentence grep RE-PLANTED as CODE -> the retired seat sentence rule is back.
  printf 'jobs:\n  x:\n    steps:\n      - run: sh scripts/sod-check.sh --seat-bodies\n' > "$_mx/seatbody.yml"
  _reads_no_seat_body "$_mx/seatbody.yml" && { echo "FAIL: mutant — a re-planted --seat-bodies CALL must NOT pass _reads_no_seat_body"; st=1; }
  printf 'jobs:\n  x:\n    steps:\n      - run: echo "carries no seat sentence" >&2\n' > "$_mx/seatsentence.yml"
  _reads_no_seat_body "$_mx/seatsentence.yml" && { echo "FAIL: mutant — a re-planted seat SENTENCE check must NOT pass _reads_no_seat_body"; st=1; }
  # mutant 12b: the same tokens IN A COMMENT must PASS — these workflows have to stay free to explain
  # what was retired and why (the same rule mutant 4 pins for the poster anchor).
  printf 'jobs:\n  x:\n    # the retired --seat-bodies mode required a seat sentence in the body\n    steps:\n      - run: echo ok\n' > "$_mx/seatprose.yml"
  _reads_no_seat_body "$_mx/seatprose.yml" || { echo "FAIL: mutant — the no-seat-body anchor fired on a COMMENT; it must read code only"; st=1; }
  rm -rf "$_mx" 2>/dev/null || true

  # LEGIBILITY ANCHORS — AND THEY CARRY THE WHOLE COMPENSATION NOW. With the yellow retired, this
  # prose is the ONLY thing separating "a human has not approved yet" from "the build is broken":
  # both render as a red required check. Gutting the title used to cost a little legibility; it now
  # costs the distinction entirely.
  # DRIVEN, not grepped. The text lives in agent-boundary.sh — but so does that script's own
  # selftest, whose expectation list contains these very literals, so grepping the FILE finds them even
  # when the real title has been gutted. (It did, in mutation testing.) Ask the mapping what it would
  # actually say, and read THAT. Behaviour, not source text.
  _waiting=$(sh "$AB" --conclusion 1 --for-state SOLO-ADMIN-OVERRIDE-LOGGED --for-class control-plane)
  for a in 'Awaiting ratification' 'NOT a build failure' 'To proceed:' 'gh pr merge' 'review-lane.md'; do
    case "$_waiting" in
      *"$a"*) ;;
      *) echo "FAIL: the waiting check-run's text is missing legibility anchor '$a'"; st=1 ;;
    esac
  done
  # ⚠️ THE TWO ANCHORS THAT SAT HERE ARE DELETED, RECORDED NOT DROPPED. They asserted that the waiting
  # mapping emits `status=in_progress` and an EMPTY `conclusion=` — the yellow, still-blocking
  # check-run. Both fields are INERT since REQUIRED-CHECK-POSTED-VIA-API-NOT-MATCHED: nothing posts a
  # check-run, so no consumer reads them (the workflows now read only title=/summary=). A green on a
  # field nobody consumes attests to nothing, and would have kept a retired mechanism looking alive.
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
