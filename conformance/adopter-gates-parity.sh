#!/bin/sh
# adopter-gates-parity.sh — the board/loop merge-time gates (backlog-presence, ceremony-binding,
# loop-state) ship for EVERY stack (Phase-B slice B6).
#
# Clones conformance/ratification-parity.sh's shape (design D3): a single, stack-neutral source —
# profiles/adopter-gates.yml — installed by scripts/incept.sh UNCONDITIONALLY for every stack.
# Proves that single source is present, marked, wired, stack-neutral, the SOLE copy, that incept
# installs it universally, and (Δ1) that the loop-state observe/enforce dial ships in the ACTIVE
# form the 2026-08-06 probe (PR #499) confirmed — `neutral` in observe mode, never a permanent red.
#
# HONEST CEILING (read before trusting a green):
#   - The REAL run proves the single source's PRESENCE + SHAPE + SOLE-COPY, and that incept.sh's
#     install line references it unconditionally. It does NOT run incept — that behavioural witness
#     is --selftest.
#   - The --selftest drives REAL incept for a NON-ts, EXEMPT stack (terraform) and asserts the
#     workflow LANDS byte-identical to the source. It does NOT re-prove the gate's RUNTIME behaviour
#     (the check-run POSTs, the PATCH-or-POST discriminator, the base-tree adjudication) — that needs
#     a live GitHub PR (the B5a/B6 probes did this once; this lock proves REACH, not runtime).
#
#   usage: sh conformance/adopter-gates-parity.sh [--selftest]   (run from repo root)
#   exit:  0 = single source present/marked/wired/neutral/sole + incept installs it universally (or
#          N/A on an adopter tree, or a structural GitLab N/A) · 1 = a parity gap · 2 = usage
set -eu
cd "$(dirname "$0")/.."

SRC="profiles/adopter-gates.yml"     # the single, stack-neutral source (top-level, like ratification.yml)
INCEPT="scripts/incept.sh"
WF=".github/workflows/adopter-gates.yml"
CI_WF=".github/workflows/ci.yml"

# is_adopter_tree: 0 (true) iff NOT the kit's own tree. Same two export-ignored kit-dev markers
# ratification-parity.sh uses: docs/ROADMAP-KIT.md AND .github/workflows/golden-path.yml (both
# stripped by git archive/adopter-export). Fail-closed on the kit (both present -> the audit RUNS);
# an adopter has neither -> N/A.
is_adopter_tree() {
  [ ! -f docs/ROADMAP-KIT.md ] && [ ! -f .github/workflows/golden-path.yml ]
}

# _ag_gitlab_only_adopter [root] -> 1 iff this tree is a GitLab-CI adopter for which the board/loop
# gates are legitimately absent (mirrors proportional-gate-wired.sh::_gitlab_only_adopter's SHAPE,
# re-parameterized on THIS gate's own workflow file — that function is hardcoded to the ratification
# workflow, so it cannot be reused verbatim here). Keyed ENTIRELY on tree STRUCTURE, never on prose in
# a mutable doc (DEVELOPMENT-PROCESS.md declares these GitHub-conditional; conformance/conditional-
# gates.sh locks that declaration). The structural triple, ALL THREE required:
#   .gitlab-ci.yml present          — this tree's authoritative pipeline is GitLab
#   .github/workflows/ci.yml absent — it is NOT a GitHub adopter
#   .github/workflows/adopter-gates.yml absent — the gates are genuinely not installed here
_ag_gitlab_only_adopter() {
  _gr=${1:-.}
  { [ -f "$_gr/.gitlab-ci.yml" ] && [ ! -f "$_gr/$CI_WF" ] && [ ! -f "$_gr/$WF" ]; } \
    && echo 1 || echo 0
}

# ---- static assertions (each takes its target by ARGUMENT so --selftest can drive it against a
#      fixture, never an env var — this is a control-plane oracle) --------------------------------

# marker: cp_kit_replace (incept.sh) refuses to overwrite a destination lacking this marker.
assert_marker() { grep -qE 'COPY & ADAPT|Sparkwright' "$1"; }

# wired: the source must invoke the exact tokens its runtime shape depends on. Read COMMENT-STRIPPED
# code (a commented-out invocation is a hollow gate, not a wired one).
assert_wired() {  # <src-file>
  _w=0
  _wcode=$(grep -v '^[[:space:]]*#' "$1")
  printf '%s\n' "$_wcode" | grep -qF 'previous_filename' || { echo "FAIL: $1 derives its changed-file listing without projecting 'previous_filename' — a rename's SOURCE path is dropped, so a renamed control-plane/board path would be invisible to backlog-presence"; _w=1; }
  printf '%s\n' "$_wcode" | grep -qF 'test("\n")' || { echo "FAIL: $1 derives its changed-file listing with no newline guard — a crafted filename could split one API entry into two lines that each classify separately"; _w=1; }
  printf '%s\n' "$_wcode" | grep -qF 'agent-boundary.sh --conclusion' || { echo "FAIL: $1 does not invoke 'agent-boundary.sh --conclusion' — the gates would carry no WAITING prose, and since the poster deletion (2026-08-27) that prose is the ONLY thing distinguishing 'a human has not approved yet' from 'the build is broken': both render as a red required check"; _w=1; }
  printf '%s\n' "$_wcode" | grep -qF 'agent-boundary.sh --check-complete' || { echo "FAIL: $1 does not invoke 'agent-boundary.sh --check-complete' — the backlog-presence gate would not notice a changed-file listing TRUNCATED at the forge's API cap"; _w=1; }
  # CODE-based anchor, not a comment (comment-stripped code cannot see prose). REPLACED ON 2026-08-27
  # (REQUIRED-CHECK-POSTED-VIA-API-NOT-MATCHED): this used to require an `if [ -n "$concl" ]` guard
  # around the POST, because an unconditional post sends conclusion="" for the WAITING state and that
  # COMPLETES the check-run, rendering it red. There is no post any more — branch protection stopped
  # matching API-posted runs, so every gate became a real job whose OWN CONCLUSION is the verdict.
  # What must not silently vanish now is the LAST LINE: a job that computes an rc and then exits 0
  # regardless satisfies a required context while enforcing nothing — a green gate, which is a
  # strictly worse failure than the red-while-waiting this design accepts.
  printf '%s\n' "$_wcode" | grep -qF '[ "$rc" = 0 ] || exit 1' || { echo "FAIL: $1 has no job that ENDS ON THE GATE'S rc (no \`[ \"\$rc\" = 0 ] || exit 1\`) — the required contexts are job conclusions now, so a gate that computes a verdict and exits 0 anyway is green and enforces nothing"; _w=1; }
  printf '%s\n' "$_wcode" | grep -qE 'checks:[[:space:]]+write' && { echo "FAIL: $1 grants 'checks: write' — nothing posts a check-run since 2026-08-27, and that scope lets a job post a run of ANY name on ANY sha (including control-plane-ratification) from a job that executes the PR's own scripts"; _w=1; }
  # B2 Δ4(ii) / reviewer I4 — THE JUDGMENT-SURFACE RENDER IS PART OF THE GATE. ceremony-binding's
  # disposition has two halves: the gate REFUSES an unrecorded design GO, and the matched record is
  # RENDERED at the judgment surface so a minted one walks into the reviewer's field of view before
  # the click (D-240805-4). A source carrying only the first half ships adopters the enforcement
  # without the visibility — the mirror-divergence class B6 paid a Critical for. Two anchors,
  # because the SHAPE is load-bearing too: the body must go inside a GROWN FENCE, never per-field
  # markdown (a forged field closed a code span and emitted `<br>`, rendering a second
  # authoritative-looking approved-by line — measured, B2 sec H2). Negatives: cases 2h/2i.
  printf '%s\n' "$_wcode" | grep -qF 'GITHUB_STEP_SUMMARY' || { echo "FAIL: $1 never writes \$GITHUB_STEP_SUMMARY — the matched GO record would not reach the judgment surface, so an adopter's reviewer gets the gate without the visibility half of the disposition (B2 Δ4(ii))"; _w=1; }
  assert_render_single_sourced "$1" || _w=1
  # Δ1 (BRANCH-SCOPE-END-TO-END): the gate leg must pass the head branch, or an adopter ships the
  # PR key alone — every design GO recorded before its PR exists then WAITS, and the [S4]#7
  # re-record this slice retires comes back as an undocumented obligation for adopters only.
  printf '%s\n' "$_wcode" | grep -qF -- '--head-branch' || { echo "FAIL: $1 never passes --head-branch to ceremony-binding.sh — the second scope key (\`scope: branch/<head-branch>\`, D11) would be dead for adopters, so a design GO recorded before the PR exists could never satisfy their gate"; _w=1; }
  return "$_w"
}

# assert_render_single_sourced <src-file> — Δ3 (BRANCH-SCOPE-END-TO-END, 2026-08-11). REPLACES the
# grown-fence grep this lock used to carry. The fence, the all-match loop and the 8 KB total bound
# no longer live in the workflow at all: they live ONCE in conformance/ceremony-binding.sh --render,
# because Δ1 adds a SECOND scope key and a workflow-local copy left matching the PR key alone would
# render NOTHING on exactly the PRs the branch key enables — the gate green, the reviewer clicking
# with no record in view (a D-240805-4 visibility lie manufactured by the fix).
# So this asserts BOTH directions, and both are load-bearing (cases 2h/2i):
#   (i)  the render leg INVOKES the script — dropping the invocation removes the visibility half;
#   (ii) the source carries NO inline copy of the match/fence — a regrown copy is the drift this
#        single-sourcing exists to make impossible, and it would pass (i) while silently diverging.
# Read from COMMENT-STRIPPED code, so prose describing the old shape cannot satisfy or trip it.
assert_render_single_sourced() {  # <src-file>
  _r=0
  _rcode=$(grep -v '^[[:space:]]*#' "$1")
  printf '%s\n' "$_rcode" | grep -qF 'ceremony-binding.sh --render' || { echo "FAIL: $1 does not invoke \`ceremony-binding.sh --render\` — the judgment-surface render (D-240805-4) is not wired, so an adopter gets the gate without the visibility half of its disposition"; _r=1; }
  if printf '%s\n' "$_rcode" | grep -qF 'fence="$fence"'; then
    echo "FAIL: $1 has REGROWN an inline copy of the GO-record render (\`fence=\"\$fence\"\`) — the render is single-sourced in conformance/ceremony-binding.sh --render, and a workflow-local copy drifts from the gate's scope keys (that drift renders NOTHING on branch-keyed PRs while the gate passes)"
    _r=1
  fi
  if printf '%s\n' "$_rcode" | grep -qF 'grep -qF -x "scope: '; then
    echo "FAIL: $1 has REGROWN an inline copy of the record MATCH (\`grep -qF -x \"scope: …\"\`) — the matcher is single-sourced in conformance/ceremony-binding.sh; a second copy is exactly the three-way drift B7 §1.8 measured"
    _r=1
  fi
  return "$_r"
}

# stack-neutral: no per-stack toolchain step, read from COMMENT-STRIPPED code.
assert_stack_neutral() {  # <src-file>
  if grep -v '^[[:space:]]*#' "$1" \
     | grep -Eiq 'actions/setup-[a-z]|(^|[^-a-z])(npm|pnpm|yarn|pip|pipenv|poetry|cargo|rustup|dotnet|nuget|gradlew|gradle|mvnw|mvn|maven|bundler)([^a-z]|$)'; then
    echo "FAIL: $1 is not stack-neutral — it carries a per-stack toolchain step; the single-source install would no longer be universal"
    return 1
  fi
  return 0
}

# single-source family-lock: the source is the TOP-LEVEL profiles/adopter-gates.yml, so NO
# profiles/<stack>/adopter-gates.yml may exist.
assert_single_source() {  # <profiles-root>
  _s=0
  for _f in "$1"/*/adopter-gates.yml; do
    [ -f "$_f" ] || continue
    echo "FAIL family-lock: $_f is a per-profile adopter-gates copy — the single source is the top-level <root>/adopter-gates.yml; remove it"
    _s=1
  done
  return "$_s"
}

# incept installs it UNCONDITIONALLY: the install line references the shared source AND is not
# re-gated on a per-stack file.
assert_incept_universal() {  # <incept-file>
  _i=0
  grep -qF 'profiles/adopter-gates.yml' "$1" || { echo "FAIL: $1 does not install the board/loop gates from profiles/adopter-gates.yml"; _i=1; }
  if grep -qF 'profiles/${STACK}/adopter-gates.yml' "$1"; then
    echo "FAIL: $1 still gates the adopter-gates install on a per-stack file (profiles/\${STACK}/adopter-gates.yml) — every non-default stack would silently get no gates"
    _i=1
  fi
  return "$_i"
}

# Δ1 — the loop-state observe/enforce dial. This lock asserts the ACTIVE form (never the
# commented-out fallback) AND the shipped default of the dial.
#
# ⚠️ THE ASSERTED DEFAULT FLIPPED ON 2026-08-30 (LOOP-STATE-ADOPTER-ENFORCE) AND THE FLIP IS
# RULED, NOT DRIFT. Until then this function asserted `observe`, per `D-240811-2.1` clause 1 and
# the 2026-08-06 probe (dev-repo PR #499). `D-240811-2.1` also held that no dial is left in bare
# observe: each carries its named TRIGGER. loop-state's trigger was that its required trailer set
# was agent self-attested — Kit-Stage and Kit-Skill are checked only for resolvability. That
# trigger FIRED in the same PR that flips this: ENTRY-CONTRACT-CLASS-PROPORTIONAL cut the required
# set to Kit-Row (board-matched) and Kit-Class (classifier-matched) for ordinary work. The clause-1
# amendment is transcribed in docs/governance/DECISIONS.md under 2026-08-30. Do not "restore"
# `observe` here without amending that record — the two must agree or one of them is a lie.
# The observe BRANCH is untouched and still asserted below: opting out remains a one-line edit.
assert_loop_state_active() {  # <src-file>
  _l=0
  # I2 (surviving mutant, reviewer): read the dial from COMMENT-STRIPPED code, same idiom as the
  # loop-state.sh --head anchor below — a raw grep over the whole file is satisfied by a prose
  # duplicate sitting in a COMMENT (e.g. stale header text) even when the live code default has
  # drifted. Comment-stripping first closes that: only a literal, live-code default counts. And it
  # matters MORE under the enforce default, because this file's own header now says the word
  # `enforce` in prose several times over.
  _wcode=$(grep -v '^[[:space:]]*#' "$1")
  printf '%s\n' "$_wcode" | grep -qF 'LOOP_STATE_MODE: enforce' || { echo "FAIL: $1 does not default LOOP_STATE_MODE to enforce — the adopter default (D-240811-2.1 as amended 2026-08-30) is missing or mis-defaulted"; _l=1; }
  # THE OBSERVE BRANCH MUST BE UNCONDITIONALLY NON-BLOCKING. It used to be expressed as a posted
  # `conclusion: neutral` (the 2026-08-06 probe's measured colour); with the poster gone the same
  # promise is an exit code — the job runs the gate, prints its verdict, and ALWAYS exits 0. Anchored
  # on the escape line itself, because that is the one character-for-character difference between a
  # nudge and a day-one permanent red on every adopter PR.
  printf '%s\n' "$_wcode" | grep -qF '[ "$mode" = enforce ] || exit 0' || { echo "FAIL: $1 has no unconditional observe-mode pass (no \`[ \"\$mode\" = enforce ] || exit 0\`) — in observe mode loop-state must ALWAYS exit 0, or an adopter's first PR reds on a gate that is not supposed to be enforcing yet"; _l=1; }
  # The gate itself (loop-state.sh --head) must still be INVOKED (never fully commented out) — Δ1
  # ships ACTIVE, not the commented-block fallback.
  printf '%s\n' "$_wcode" | grep -qF 'loop-state.sh --head' || { echo "FAIL: $1 does not invoke loop-state.sh --head — the gate is not ACTIVE (looks like the commented-out fallback form, which is not what the 2026-08-06 probe ruled for)"; _l=1; }
  return "$_l"
}

# assert_t2_live_contexts <src-file> — TRACKER-TRUSTED-JOB-REQUIRED-CONTEXT T2 (design §2b + A1 §9
# RD-1 arm (a) LIVE): the backlog-presence job must feed conformance/backlog-presence.sh the base
# checkout AND the base branch's LIVE required contexts, so bp_tracker_delegated's step-aside can be
# verified from the BASE alone (never the head). Read from COMMENT-STRIPPED code — same idiom as
# assert_loop_state_active above. Four static legs, ≤6 total with the two mutants in selftest():
#   (i)   the gate step passes --base-dir <checkout>
#   (ii)  the gate step passes --live-contexts <file>
#   (iii) the contexts-fetch step reads the base ref ONLY via an env: binding (never inlined into
#         the run: line as a `${{ }}` expression, and NEVER github.event.pull_request.head.ref —
#         the PR-controlled branch RD-1 must not trust)
#   (iv)  the contexts-fetch step cannot fail the JOB — an `||` fallback covers the `gh api` call, so
#         a forge hiccup leaves the live-contexts file ABSENT (fail-closed at the gate) rather than
#         reddening a job that has nothing to do with board presence
#
# LS-D1 (LOOP-STATE-TRACKER-STEP-ASIDE, 2026-09-28): job-scoped, not whole-file. `loop-state` now
# carries a byte-identical live-contexts step, so a whole-file grep here would be satisfied by
# EITHER job's copy and could mask a stripped `--live-contexts`, `BASE_REF` or fallback in one job
# while the other job's copy is intact. Reads ONLY the `backlog-presence:` job's own block (via
# `_extract_job_block`, the same discipline `assert_t2_base_checkout` already applies) — the
# loop-state twin is `assert_t2_live_contexts_loop_state` below.
assert_t2_live_contexts() {  # <src-file>
  _t2=0
  _t2tmp=$(mktemp)
  _extract_job_block "$1" "backlog-presence" "$_t2tmp"
  _t2code=$(grep -v '^[[:space:]]*#' "$_t2tmp")
  printf '%s\n' "$_t2code" | grep -qF -- '--base-dir "$GITHUB_WORKSPACE"' \
    || { echo "FAIL: $1's backlog-presence job does not pass --base-dir \"\$GITHUB_WORKSPACE\" to backlog-presence.sh — the base checkout is never handed to bp_tracker_delegated (T2 leg i, job-scoped)"; _t2=1; }
  printf '%s\n' "$_t2code" | grep -qF -- '--live-contexts /tmp/live-contexts' \
    || { echo "FAIL: $1's backlog-presence job does not pass --live-contexts /tmp/live-contexts — the base branch's live required contexts never reach the gate, so the tracker step-aside can never fire (T2 leg ii, job-scoped)"; _t2=1; }
  printf '%s\n' "$_t2code" | grep -qF 'BASE_REF: ${{ github.event.pull_request.base.ref }}' \
    || { echo "FAIL: $1's backlog-presence job does not env-bind BASE_REF from github.event.pull_request.base.ref — the live-contexts fetch has no base branch to query, or reads the ref unsafely inline (T2 leg iii, job-scoped)"; _t2=1; }
  printf '%s\n' "$_t2code" | grep -qF 'github.event.pull_request.head.ref' \
    && { echo "FAIL: $1's backlog-presence job's live-contexts fetch reads github.event.pull_request.head.ref somewhere — RD-1 requires the BASE branch's protection, never the PR-controlled head (T2 leg iii, negative, job-scoped)"; _t2=1; }
  # T2 fix round 2 sweep: anchored on the trailing `;` — a substring pin on `rm -f /tmp/live-contexts`
  # (no anchor) is satisfied by `rm -f /tmp/live-contexts-old` (still contains the pinned text as a
  # prefix), which would remove the WRONG file and leave the real live-contexts file behind.
  printf '%s\n' "$_t2code" | grep -qF -- '|| { rm -f /tmp/live-contexts;' \
    || { echo "FAIL: $1's backlog-presence job's live-contexts fetch has no \`|| { rm -f /tmp/live-contexts; ...\` fallback around the gh api call — a forge API failure would fail the JOB instead of leaving the file absent for the gate to fail closed on (T2 leg iv, job-scoped)"; _t2=1; }
  rm -f "$_t2tmp"
  return "$_t2"
}

# assert_t2_live_contexts_loop_state <src-file> — LOOP-STATE-TRACKER-STEP-ASIDE T2 / LS-D1, A3: the
# `loop-state` job's own twin of assert_t2_live_contexts above, job-scoped to `loop-state:` (never
# satisfied by backlog-presence's copy). Pins the loop-state job's OWN base-dir/live-contexts flags
# — `--base-dir "$GITHUB_WORKSPACE/.kit-base"` (the SECOND checkout's path, LS-D2) — plus the same
# BASE_REF/no-head-ref/fallback shape, PLUS A3's cost-avoidance `if:` guard so an `md` adopter pays
# no token/API call for this step.
assert_t2_live_contexts_loop_state() {  # <src-file>
  _t2l=0
  _t2ltmp=$(mktemp)
  _extract_job_block "$1" "loop-state" "$_t2ltmp"
  _t2lcode=$(grep -v '^[[:space:]]*#' "$_t2ltmp")
  # T2 fix round 2 sweep (gate-flags pin): both flags must sit on the FLAGGED CALL LINE ITSELF, not
  # merely somewhere in the step/job — a flag present on some OTHER line (e.g. planted on the bare
  # else-arm call, or on an unrelated comment) would satisfy a job-wide grep while --base-dir/
  # --live-contexts never actually reach loop-state.sh. Extract the one line that is BOTH the
  # loop-state.sh --head invocation AND carries --base-dir (the then-arm's flagged call), and require
  # it to be the exact trimmed line — this also pins the VALUE (a wrong path, e.g. --base-dir
  # "$GITHUB_WORKSPACE" with no /.kit-base, fails to match the whole line).
  # Position-anchored, not just content-matched: the flagged line must be the line IMMEDIATELY
  # AFTER the `if grep -q -- '--base-dir' conformance/loop-state.sh; then` probe — a mutant that
  # keeps the exact flagged-call TEXT byte-for-byte but relocates it into the else arm (swapping
  # places with the bare call) would satisfy a plain grep for that text; anchoring on "the line right
  # after the if" catches that relocation.
  # The probe may carry a harmless `2>/dev/null` redirect (the real source does); tolerated here too.
  _t2l_flagline=$(printf '%s\n' "$_t2lcode" | awk '
    /^[[:space:]]*if grep -q -- .--base-dir. conformance\/loop-state\.sh( 2>\/dev\/null)?; then[[:space:]]*$/ { want=1; next }
    want { print; exit }
  ' | sed 's/^[[:space:]]*//')
  if [ -z "$_t2l_flagline" ]; then
    echo "FAIL: $1's loop-state job has no line immediately after the version-skew \`if\` probe — the flagged call is missing or the guard's then-arm is empty (T2 leg i, loop-state)"; _t2l=1
  elif [ "$_t2l_flagline" != 'sh conformance/loop-state.sh --head "$HEAD_SHA" --base-dir "$GITHUB_WORKSPACE/.kit-base" --live-contexts /tmp/live-contexts' ]; then
    echo "FAIL: $1's loop-state job's flagged call line is not exactly \`sh conformance/loop-state.sh --head \"\$HEAD_SHA\" --base-dir \"\$GITHUB_WORKSPACE/.kit-base\" --live-contexts /tmp/live-contexts\` (found: $_t2l_flagline) — a flag on the wrong line, or a wrong value, would leave loop-state.sh never actually seeing the right base tree or live contexts (T2 leg i/ii, loop-state, gate-flags pin)"; _t2l=1
  fi
  printf '%s\n' "$_t2lcode" | grep -qF 'BASE_REF: ${{ github.event.pull_request.base.ref }}' \
    || { echo "FAIL: $1's loop-state job does not env-bind BASE_REF from github.event.pull_request.base.ref (T2 leg iii, loop-state)"; _t2l=1; }
  printf '%s\n' "$_t2lcode" | grep -qF 'github.event.pull_request.head.ref' \
    && { echo "FAIL: $1's loop-state job's live-contexts fetch reads github.event.pull_request.head.ref somewhere — RD-1 requires the BASE branch's protection, never the PR-controlled head (T2 leg iii negative, loop-state)"; _t2l=1; }
  # T2 fix round 2 sweep: anchored on the trailing `;` (see assert_t2_live_contexts's twin note).
  printf '%s\n' "$_t2lcode" | grep -qF -- '|| { rm -f /tmp/live-contexts;' \
    || { echo "FAIL: $1's loop-state job's live-contexts fetch has no \`|| { rm -f /tmp/live-contexts; ...\` fallback around the gh api call (T2 leg iv, loop-state)"; _t2l=1; }
  # A3 — no token/API call on md: the contexts-fetch step must carry the hashFiles cost guard.
  printf '%s\n' "$_t2lcode" | grep -qF "if: hashFiles('.kit-base/.kit/tracker.conf') != ''" \
    || { echo "FAIL: $1's loop-state job's live-contexts fetch step has no \`if: hashFiles('.kit-base/.kit/tracker.conf') != ''\` guard — an md adopter would pay for a token-bearing gh api call on every PR for nothing (A3)"; _t2l=1; }
  rm -f "$_t2ltmp"
  return "$_t2l"
}

# _extract_checkout_step <job-block> <n> <out> — LS-T2-Q1: lift the Nth
# `      - uses: actions/checkout` step's OWN block (that line through the line before the next
# step at the same "      - " indent, or a dedent to the job-block's own top-level key), so a field
# planted in the WRONG checkout's block (e.g. `path: .kit-base` moved onto the head checkout) can be
# told apart from the same field sitting in the right one — a job-wide grep cannot make that
# distinction, which is exactly what let M1 (path: .kit-base on the head checkout) pass silently.
_extract_checkout_step() {  # <job-block> <n> <out>
  awk -v want="$2" '
    /^      - uses: actions\/checkout/ { n++; instep = (n == want); if (instep) { print; next } else { next } }
    instep && /^      - / { exit }
    instep && /^  [A-Za-z]/ { exit }
    instep { print }
  ' "$1" > "$3"
}

# assert_t2_base_checkout_loop_state <src-file> — LS-D1/LS-D2 (LS-T2-Q1): the loop-state job must
# carry EXACTLY two actions/checkout steps; the SECOND one's OWN block (not the job as a whole) must
# be pinned to base.sha, land at path: .kit-base, be shallow and credential-free; and the FIRST
# one's OWN block must carry neither a path: nor a base.sha ref: — so a field moved from the second
# checkout onto the first (M1) reds on both the missing-from-second and present-on-first legs, and a
# third checkout sneaking base.sha in reds on the exactly-two count regardless of field placement.
# Replaces the persist-credentials COUNT hack and the line-number order test (both job-wide, both
# foolable by a checkout added/moved elsewhere in the job).
assert_t2_base_checkout_loop_state() {  # <src-file>
  _bcl=0
  _bcltmp=$(mktemp)
  _extract_job_block "$1" "loop-state" "$_bcltmp"
  _bclcode_file=$(mktemp)
  grep -v '^[[:space:]]*#' "$_bcltmp" > "$_bclcode_file"

  _n_checkouts=$(grep -cF 'uses: actions/checkout' "$_bclcode_file")
  if [ "$_n_checkouts" -ne 2 ]; then
    echo "FAIL: $1's loop-state job does not have EXACTLY two actions/checkout steps (found $_n_checkouts) — LS-D2 needs one head checkout and one base checkout, no more"; _bcl=1
  fi

  _first_tmp=$(mktemp); _second_tmp=$(mktemp)
  _extract_checkout_step "$_bclcode_file" 1 "$_first_tmp"
  _extract_checkout_step "$_bclcode_file" 2 "$_second_tmp"

  if [ -s "$_second_tmp" ]; then
    grep -qF 'ref: ${{ github.event.pull_request.base.sha }}' "$_second_tmp" \
      || { echo "FAIL: $1's loop-state job's SECOND checkout step (its own block) is not pinned to \`ref: \${{ github.event.pull_request.base.sha }}\` — the base tree is never fetched for --base-dir (loop-state base checkout, scoped)"; _bcl=1; }
    # T2 fix round 2 sweep: EXACT whole trimmed-line match (grep -qx), not grep -qF substring — a
    # substring pin on `path: .kit-base` is satisfied by `path: .kit-base-x` (it CONTAINS the pinned
    # text as a prefix), and a substring pin on `fetch-depth: 1` is satisfied by `fetch-depth: 10`
    # (same prefix problem) — both presence-preserving mutants that change the actual value while
    # leaving the pinned substring intact.
    sed 's/^[[:space:]]*//' "$_second_tmp" | grep -qxF 'path: .kit-base' \
      || { echo "FAIL: $1's loop-state job's SECOND checkout step (its own block) does not land at path: .kit-base — --base-dir \"\$GITHUB_WORKSPACE/.kit-base\" would point nowhere (scoped)"; _bcl=1; }
    sed 's/^[[:space:]]*//' "$_second_tmp" | grep -qxF 'fetch-depth: 1' \
      || { echo "FAIL: $1's loop-state job's SECOND checkout step (its own block) is not fetch-depth: 1 — the base checkout should be shallow (A3 cost, scoped)"; _bcl=1; }
    grep -qF 'persist-credentials: false' "$_second_tmp" \
      || { echo "FAIL: $1's loop-state job's SECOND checkout step (its own block) does not set persist-credentials: false (scoped)"; _bcl=1; }
  else
    echo "FAIL: $1's loop-state job has no SECOND actions/checkout step — the base checkout is missing"; _bcl=1
  fi

  if [ -s "$_first_tmp" ]; then
    grep -qF 'path:' "$_first_tmp" \
      && { echo "FAIL: $1's loop-state job's FIRST checkout step carries a path: of its own — that field belongs on the SECOND (base) checkout only; a field moved onto the head checkout would leave --base-dir pointed nowhere while looking wired"; _bcl=1; }
    grep -qF 'ref: ${{ github.event.pull_request.base.sha }}' "$_first_tmp" \
      && { echo "FAIL: $1's loop-state job's FIRST checkout step is pinned to base.sha — the base pin belongs on the SECOND checkout only (order pin, LS-D2)"; _bcl=1; }
  fi

  rm -f "$_bcltmp" "$_bclcode_file" "$_first_tmp" "$_second_tmp"
  return "$_bcl"
}

# assert_t2_loop_state_token_scoped <src-file> — LS-D1/LS-D5: a credential MUST appear ONLY in the
# loop-state job's contexts-fetch step, never in any other step of that job (the token is
# "hygiene, not isolation", adopter-tracker-gates.yml:49-52 — it must not spread to a step that
# later runs head code).
#
# LS-T2-Q3: counted by literal `GH_TOKEN` alone, a token planted under a DIFFERENT name — e.g.
# `GITHUB_TOKEN: ${{ github.token }}` (M3) — was invisible to this pin: `_job_n` and `_step_n` both
# stayed at their clean values (1/1) with the plant sitting on the gate step. Widened to any
# credential-shaped binding: `GH_TOKEN`, `GITHUB_TOKEN`, a bare `github.token` reference, or any
# `secrets.*` reference — matched with extended regex, comment-stripped.
assert_t2_loop_state_token_scoped() {  # <src-file>
  _tok=0
  _jobtmp=$(mktemp); _steptmp=$(mktemp)
  _extract_job_block "$1" "loop-state" "$_jobtmp"
  _extract_contexts_step "$_jobtmp" "$_steptmp"
  # T2 fix round 2 sweep: also counts the bracket-indexed forms (github['\''token'\''],
  # secrets['\''FOO'\'']) — a credential-shaped binding does not have to spell the dotted form.
  _job_n=$(grep -v '^[[:space:]]*#' "$_jobtmp" | grep -ciE "GH_TOKEN|GITHUB_TOKEN|github\.token|secrets\.|github\[|secrets\[")
  _step_n=$(grep -v '^[[:space:]]*#' "$_steptmp" | grep -ciE "GH_TOKEN|GITHUB_TOKEN|github\.token|secrets\.|github\[|secrets\[")
  if [ "$_job_n" != "$_step_n" ] || [ "$_step_n" -eq 0 ]; then
    echo "FAIL: $1's loop-state job carries a credential-shaped binding (GH_TOKEN/GITHUB_TOKEN/github.token/secrets.*) outside the live-contexts fetch step ($_job_n total in the job vs $_step_n in that step) — the token must be confined to the one step that runs no head code"; _tok=1
  fi
  rm -f "$_jobtmp" "$_steptmp"
  return "$_tok"
}

# assert_t2_loop_state_skew_guard <src-file> — the gate step must mirror :280's version-skew guard:
# if the tree's loop-state.sh lacks --base-dir, call it the old way rather than passing flags the
# checked-out script does not understand (A3/design §2, "behind a version-skew guard that mirrors
# :280"). Job-scoped to loop-state:.
#
# LS-T2-Q2: the `if grep -q -- '--base-dir' ...; then <flagged call>` half is not enough on its own —
# without a bare `else` fallback, an OLD checked-out loop-state.sh (predating --base-dir) makes the
# `if` false and NEITHER branch runs, so `rc` is never set by this step at all. In enforce mode the
# job's later `[ "$rc" = 0 ] || exit 1` then reads a leftover/empty `$rc` from a PRIOR step's shell
# state (or an unset var under `set -u`-less sh, which is simply empty and not `= 0`... but under
# THIS file's `set +e; ...; rc=$?` idiom sitting entirely inside the same `if`, a taken-neither-branch
# run leaves `rc=$?` never executed, so the step's own exit code is 0 from the `if` itself — the gate
# silently passes). So both the flagged call AND the bare fallback call must be present.
assert_t2_loop_state_skew_guard() {  # <src-file>
  _sk=0
  _sktmp=$(mktemp)
  _extract_job_block "$1" "loop-state" "$_sktmp"
  _skcode=$(grep -v '^[[:space:]]*#' "$_sktmp")
  printf '%s\n' "$_skcode" | grep -qF -- '--base-dir' \
    || { echo "FAIL: $1's loop-state job never mentions --base-dir at all — no skew guard is possible"; _sk=1; }
  # The guard must actually PROBE the checked-out script (mirrors :280's `grep -q -- '--check-complete' conformance/agent-boundary.sh`), not just call the flag unconditionally.
  printf '%s\n' "$_skcode" | grep -qF -- "grep -q -- '--base-dir' conformance/loop-state.sh" \
    || { echo "FAIL: $1's loop-state job does not probe conformance/loop-state.sh for --base-dir before using the flag — the gate step has no version-skew guard, so a checkout predating the flag would break rather than falling back to the old call shape"; _sk=1; }
  # LS-T2-Q2: the bare `else` fallback call must also be present — dropping it leaves an old
  # loop-state.sh's `if` branch untaken, so the step exits 0 with `rc` never computed, and enforce
  # mode passes silently on a checkout that predates --base-dir. Anchored to the END of the line
  # (grep -x on the trimmed line) so the FLAGGED call — which also contains this substring as its
  # prefix, before ` --base-dir ...` — cannot satisfy it; only a line that is EXACTLY the bare call
  # counts as the else arm.
  printf '%s\n' "$_skcode" | sed 's/^[[:space:]]*//' | grep -qxF 'sh conformance/loop-state.sh --head "$HEAD_SHA"' \
    || { echo "FAIL: $1's loop-state job has no bare \`sh conformance/loop-state.sh --head \"\$HEAD_SHA\"\` fallback call (the else arm) — on a checkout predating --base-dir the version-skew if's else branch would never run, leaving \$rc uncomputed and the gate silently passing"; _sk=1; }
  # T2 fix round 2 BLOCKER: the presence pins above are each satisfied independently of ORDER —
  # deleting only the `else` line moves the bare call into the `then` arm (both calls still present,
  # so every pin above still passes), and on an old loop-state.sh (no --base-dir) NO arm runs, `rc`
  # is never computed, and the job passes silently in enforce mode. Swapping the two calls (the
  # flagged call in the else arm, the bare call in the then arm) is the same failure the other way:
  # a checkout that DOES understand --base-dir would take the bare, unflagged call. So this is a
  # STRUCTURAL, ordered check: the whole trimmed if/then/else/fi skeleton, line-for-line, each line
  # matched EXACTLY (never a substring) — swap, dedent, or drop any one line and this reds even
  # though every individual pin above it still finds its string somewhere in the job.
  # l1 is a REGEX (not a literal) because the real source appends `2>/dev/null` to the probe
  # (:280's own --check-complete guard carries no such redirect); an optional, harmless redirect on
  # the probe itself is not the drift this check exists to catch, so it is tolerated here while l2-l5
  # stay literal, whole-line matches.
  _sk_l1re='^if grep -q -- .--base-dir. conformance/loop-state\.sh( 2>/dev/null)?; then$'
  _sk_l2='sh conformance/loop-state.sh --head "$HEAD_SHA" --base-dir "$GITHUB_WORKSPACE/.kit-base" --live-contexts /tmp/live-contexts'
  _sk_l3="else"
  _sk_l4='sh conformance/loop-state.sh --head "$HEAD_SHA"'
  _sk_l5="fi"
  if ! printf '%s\n' "$_skcode" | awk -v l1re="$_sk_l1re" -v l2="$_sk_l2" -v l3="$_sk_l3" -v l4="$_sk_l4" -v l5="$_sk_l5" '
      { line=$0; sub(/^[ \t]*/, "", line) }
      state==0 && line ~ l1re { state=1; next }
      state==1 && line==l2 { state=2; next }
      state==2 && line==l3 { state=3; next }
      state==3 && line==l4 { state=4; next }
      state==4 && line==l5 { state=5; next }
      END { exit (state==5) ? 0 : 1 }
    '; then
    echo "FAIL: $1's loop-state job's version-skew guard is not the exact if/then(flagged-call)/else/bare-call/fi SEQUENCE, in that order, each line matched whole and trimmed — a re-ordered, dedented, or swapped skew guard can leave every individual pin satisfied while the guard itself no longer covers an old checkout"; _sk=1
  fi
  rm -f "$_sktmp"
  return "$_sk"
}

# _extract_job_block <yml> <job> <out> — S-1 (RT2-Q4): lift a TOP-LEVEL job's own block (its
# `  <job>:` line through the line before the next top-level `  <name>:` key), the same discipline
# _extract_contexts_step already applies to a single step — so a checkout pinned correctly in some
# OTHER job cannot mask a wrong pin in THIS one, and a mutant scoped to one job cannot hide behind an
# unrelated job's correct pin either.
_extract_job_block() {  # <yml> <job> <out>
  awk -v job="$2" '
    $0 ~ "^  " job ":" { injob=1; print; next }
    injob && /^  [A-Za-z]/ { exit }
    injob { print }
  ' "$1" > "$3"
}

# assert_t2_base_checkout <src-file> — RT2-Q4: the backlog-presence job's OWN checkout must be
# pinned to the base sha (github.event.pull_request.base.sha), never the head sha — this is what
# makes `--base-dir "$GITHUB_WORKSPACE"` (T2 leg i above) actually hand backlog-presence.sh the BASE
# tree rather than the PR-controlled head. conformance/proportional-gate-wired.sh's generic taint
# scanner (~:283-304, `_tj_block_tainted`) allows EITHER github.sha or base.sha as a safe checkout
# subject — it is scoped to profiles/ratification.yml + .github/workflows/ci.yml (its own WF/CI_WF)
# and does not pin backlog-presence's checkout specifically, and it would not RED a head.sha swap
# here since head.sha is not on its denylist either (it only denies non-allowlisted `${{ }}`
# expressions and literal `refs/heads/...`). So this is a separate, dedicated leg, not a duplicate.
#
# S-1 (class sweep, RT2-Q4 STRUCTURAL): read ONLY the `backlog-presence:` job's OWN block (via
# _extract_job_block, the same discipline _extract_contexts_step already applies to a single step) —
# never the whole file. A whole-file grep is satisfied by a base.sha checkout living in ANY job; the
# orchestrator's ruling is that a workflow pin must be scoped to the right job/step block, so a
# mutant that flips ONLY backlog-presence's own checkout while another job's base.sha checkout is
# left untouched must still RED (selftest case2f4c proves this: a second job in the clean fixture
# also checks out base.sha, and the mutant flips only the FIRST occurrence).
assert_t2_base_checkout() {  # <src-file>
  _bc=0
  _bctmp=$(mktemp)
  _extract_job_block "$1" "backlog-presence" "$_bctmp"
  _bccode=$(grep -v '^[[:space:]]*#' "$_bctmp")
  printf '%s\n' "$_bccode" | grep -qF 'ref: ${{ github.event.pull_request.base.sha }}' \
    || { echo "FAIL: $1's backlog-presence job checkout is not pinned to \`ref: \${{ github.event.pull_request.base.sha }}\` — --base-dir would hand backlog-presence.sh a tree that is not provably the BASE (RT2-Q4)"; _bc=1; }
  rm -f "$_bctmp"
  return "$_bc"
}

# _extract_contexts_step <yml> <out> — RT2-Q1: lift the contexts-fetch step's OWN block (its
# `- name: Fetch the base branch's LIVE required contexts` line through the line before the next
# `- name:`), so a defect elsewhere in the file (or a fix elsewhere) cannot mask/satisfy a check
# that must be true of THIS step specifically.
#
# LOOP-STATE-TRACKER-STEP-ASIDE T2 (token-scoping non-vacuity): also exits on the next UNNAMED
# step start (`      - run:` / `      - uses:` at the step-list indent) — not just the next `- name:`
# — so a step planted right after the contexts step with no `name:` of its own (e.g. a stray
# `GH_TOKEN` leak) is never silently folded INTO the extracted contexts-step block. This only
# NARROWS what counts as "this step" (stops earlier, never later), so it cannot loosen any existing
# pin that already reads from this extraction.
_extract_contexts_step() {  # <yml> <out>
  awk '
    /- name: Fetch the base branch.s LIVE required contexts/ { instep=1; print; next }
    instep && /^[[:space:]]*- name:/ { exit }
    instep && /^[[:space:]]*- (run|uses):/ { exit }
    instep && /^  [A-Za-z]/ { exit }
    instep { print }
  ' "$1" > "$2"
}

# assert_t2_contexts_step_checks_what_it_claims <src-file> — RT2-Q1 [SEC]: the leg must check what
# it claims. Reads ONLY the contexts-fetch step's own block (comment-stripped):
#   - it targets branches/${BASE_REF} (not some other branch, hardcoded or otherwise);
#   - after its run: line there is NO `${{` — the base ref is read ONLY via the env: binding, never
#     interpolated into the shell line;
#   - it contains no head_ref and no head.ref anywhere in its own block;
#   - RT2-Q7 [SEC]: after its run: line there is no GITHUB_HEAD_REF (the env var GitHub Actions
#     exposes for the PR's head branch) and no shell assignment of BASE_REF= (a run: line that
#     reassigns BASE_REF from GITHUB_HEAD_REF before the gh api call would read the PR-controlled
#     head even though the step's env: binding still says base.ref);
#   - S-2 [SEC]: the step's own jq filter carries `select(.name == env.BASE_REF)` — dropping that
#     selector would let the filter read ANY branch's protection entry in the API response, not
#     necessarily the one named by BASE_REF.
#
# LS-T2-SWEEP (drift hazard, class sweep): job-scoped, PARAMETERIZED on <job> — extracts THAT job's
# block FIRST (via _extract_job_block), then lifts the contexts-fetch step from within it, so a
# sibling job's byte-identical step (same name) cannot mask a break in this one. Was two near-copies
# (one hardcoded to backlog-presence, one to loop-state, differing only in the job name and FAIL
# prose) — a drift hazard the sweep retires: call this once per job instead.
assert_t2_contexts_step_checks_what_it_claims() {  # <src-file> <job>
  _cs=0
  _csjob="$2"
  _cjobtmp=$(mktemp)
  _cstmp=$(mktemp)
  _extract_job_block "$1" "$_csjob" "$_cjobtmp"
  _extract_contexts_step "$_cjobtmp" "$_cstmp"
  _cscode=$(grep -v '^[[:space:]]*#' "$_cstmp")
  printf '%s\n' "$_cscode" | grep -qF 'branches/${BASE_REF}' \
    || { echo "FAIL: $1's $_csjob job's contexts-fetch step does not target branches/\${BASE_REF} — the leg cannot verify it reads the BASE branch's protection (RT2-Q1)"; _cs=1; }
  # After the run: line there must be NO `${{` — the base ref is env-bound, never inlined.
  if printf '%s\n' "$_cscode" | awk '/^[[:space:]]*run:/ { seen=1; next } seen && /\$\{\{/ { found=1 } END { exit !found }'; then
    echo "FAIL: $1's $_csjob job's contexts-fetch step interpolates a \${{ }} expression into its run: line — the base ref must be read ONLY via the env: binding (RT2-Q1)"; _cs=1
  fi
  printf '%s\n' "$_cscode" | grep -qF 'head_ref' && { echo "FAIL: $1's $_csjob job's contexts-fetch step reads head_ref — RD-1 requires the BASE branch's protection, never a PR-controlled head (RT2-Q1)"; _cs=1; }
  printf '%s\n' "$_cscode" | grep -qF 'head.ref' && { echo "FAIL: $1's $_csjob job's contexts-fetch step reads head.ref — RD-1 requires the BASE branch's protection, never a PR-controlled head (RT2-Q1)"; _cs=1; }
  # RT2-Q7 [SEC]: from the run: line onward (INCLUSIVE — the reassignment could sit on the run: line
  # itself, before the gh api call), deny GITHUB_HEAD_REF and any shell reassignment of BASE_REF=.
  if printf '%s\n' "$_cscode" | awk '/^[[:space:]]*run:/ { seen=1 } seen && /GITHUB_HEAD_REF/ { found=1 } END { exit !found }'; then
    echo "FAIL: $1's $_csjob job's contexts-fetch step's run: line reads GITHUB_HEAD_REF — RD-1 requires the BASE branch's protection; the PR-controlled head ref must never reach this step's shell (RT2-Q7)"; _cs=1
  fi
  if printf '%s\n' "$_cscode" | awk '/^[[:space:]]*run:/ { seen=1 } seen && /BASE_REF=/ { found=1 } END { exit !found }'; then
    echo "FAIL: $1's $_csjob job's contexts-fetch step's run: line shell-reassigns BASE_REF= — the step's env: binding would be silently overridden before the gh api call (RT2-Q7)"; _cs=1
  fi
  # S-2 [SEC]: the jq filter must select the record named by BASE_REF, never any entry in the response.
  printf '%s\n' "$_cscode" | grep -qF 'select(.name == env.BASE_REF)' \
    || { echo "FAIL: $1's $_csjob job's contexts-fetch step's jq filter does not carry \`select(.name == env.BASE_REF)\` — the filter could read ANY branch's protection entry in the API response, not necessarily BASE_REF's own (S-2)"; _cs=1; }
  rm -f "$_cjobtmp" "$_cstmp"
  return "$_cs"
}

# _extract_fetch_body <yml> <out> — lift the `run: |` body of the "Fetch the board + backend
# declaration from the PR HEAD" step, with the 10-space YAML indent stripped (so it is a runnable
# script). Stops at the next `      - ` step start.
_extract_fetch_body() {  # <yml> <out>
  awk '
    /- name: Fetch the board \+ backend declaration from the PR HEAD/ { instep=1; next }
    instep && /^      - / { exit }
    instep && /^        run: \|/ { inrun=1; next }
    inrun { if ($0 ~ /^[[:space:]]*$/) { print ""; next } sub(/^          /, ""); print }
  ' "$1" > "$2"
}

# assert_fetch_survives_404 <src-yml> — ADOPTER-GATES-JIRA-BLOCKERS C1/C2. GitHub runs `run:` under
# `bash -eo pipefail`; a bare `err=$(gh api ...)` that returns non-zero (a 404 — a Jira adopter has
# no BACKLOG.md) aborts the step BEFORE the 404 ladder can read it. So RUN the real step body, with
# `/tmp/` rewritten to a throwaway root and a stub `gh` first on PATH:
#   mode 404: BACKLOG.md + WAIVER-REGISTER.md -> HTTP 404 (CLAUDE.md fetched) -> rc 0, two "absent
#             (404)" lines, "fetched CLAUDE.md", and an EMPTY board.err;
#   mode 500: additionally CLAUDE.md -> HTTP 500 -> rc 0 and board.err names CLAUDE.md (a non-404
#             stays a gate error, never silently "absent").
assert_fetch_survives_404() {  # <src-yml>
  _fs=0
  _fsbash=$(command -v bash 2>/dev/null) || _fsbash=""
  if [ -z "$_fsbash" ]; then
    echo "SKIP: assert_fetch_survives_404 — no bash on PATH (not a pass)"
    return 0
  fi
  _fsroot=$(mktemp -d)
  _fsraw="$_fsroot/body.raw"
  _fsbody="$_fsroot/body.sh"
  _extract_fetch_body "$1" "$_fsraw"
  if [ ! -s "$_fsraw" ]; then
    echo "FAIL: $1 has no 'Fetch the board + backend declaration from the PR HEAD' run: body to execute (C1)"
    rm -rf "$_fsroot"
    return 1
  fi
  sed "s#/tmp/#$_fsroot/#g" "$_fsraw" > "$_fsbody"
  mkdir -p "$_fsroot/bin"
  cat > "$_fsroot/bin/gh" <<'STUB'
#!/bin/sh
case "$*" in
  *contents/BACKLOG.md*|*contents/WAIVER-REGISTER.md*)
    echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
  *contents/CLAUDE.md*)
    if [ "${AG_GH_MODE:-}" = 500 ]; then echo "gh: Server Error (HTTP 500)" >&2; exit 1; fi ;;
esac
echo "file body"
exit 0
STUB
  chmod +x "$_fsroot/bin/gh"

  # mode 404
  _fsrc=0
  _fsout=$(PATH="$_fsroot/bin:$PATH" AG_GH_MODE=404 REPO=o/r SHA=abc \
    "$_fsbash" --noprofile --norc -eo pipefail "$_fsbody" 2>&1) || _fsrc=$?
  [ "$_fsrc" -eq 0 ] \
    || { echo "FAIL: $1's Fetch step exits rc=$_fsrc under bash -eo pipefail when BACKLOG.md / WAIVER-REGISTER.md are 404 — a Jira adopter's backlog-presence job dies before the 404 ladder (C1)"; _fs=1; }
  printf '%s\n' "$_fsout" | grep -qF 'backlog-presence: BACKLOG.md absent at the PR head (404)' \
    || { echo "FAIL: $1's Fetch step (mode 404) did not report 'BACKLOG.md absent at the PR head (404)' (C1)"; _fs=1; }
  printf '%s\n' "$_fsout" | grep -qF 'backlog-presence: WAIVER-REGISTER.md absent at the PR head (404)' \
    || { echo "FAIL: $1's Fetch step (mode 404) did not report 'WAIVER-REGISTER.md absent at the PR head (404)' (C1)"; _fs=1; }
  printf '%s\n' "$_fsout" | grep -qF 'backlog-presence: fetched CLAUDE.md from the PR head' \
    || { echo "FAIL: $1's Fetch step (mode 404) did not reach 'fetched CLAUDE.md' — the loop stopped at the first 404 (C1)"; _fs=1; }
  # the files the gate reads: the 404'd ones removed, the present one written (path built through a
  # variable so no literal board filename operand appears — board-parser-drift's scan shape)
  _fsbl="$_fsroot/board/BACKLOG"
  [ ! -e "$_fsbl.md" ] \
    || { echo "FAIL: $1's Fetch step (mode 404) left a stale board file for the absent head file, which the gate would read as a board (C1)"; _fs=1; }
  [ ! -e "$_fsroot/board/WAIVER-REGISTER.md" ] \
    || { echo "FAIL: $1's Fetch step (mode 404) left a stale WAIVER-REGISTER.md for the absent head file (C1)"; _fs=1; }
  [ -s "$_fsroot/board/CLAUDE.md" ] \
    || { echo "FAIL: $1's Fetch step (mode 404) did not write the fetched CLAUDE.md into the board dir (C1)"; _fs=1; }
  if [ ! -f "$_fsroot/board.err" ]; then
    echo "FAIL: $1's Fetch step (mode 404) left no board.err file (C1)"; _fs=1
  elif [ -s "$_fsroot/board.err" ]; then
    echo "FAIL: $1's Fetch step (mode 404) wrote to board.err — a plain 404 must NOT be a gate error (C1)"; _fs=1
  fi

  # mode 500
  _fsrc=0
  _fsout=$(PATH="$_fsroot/bin:$PATH" AG_GH_MODE=500 REPO=o/r SHA=abc \
    "$_fsbash" --noprofile --norc -eo pipefail "$_fsbody" 2>&1) || _fsrc=$?
  [ "$_fsrc" -eq 0 ] \
    || { echo "FAIL: $1's Fetch step exits rc=$_fsrc under bash -eo pipefail on a non-404 (500) — it must record the error for the next step, not abort (C2)"; _fs=1; }
  if [ ! -f "$_fsroot/board.err" ] || ! grep -qF '=== CLAUDE.md ===' "$_fsroot/board.err"; then
    echo "FAIL: $1's Fetch step (mode 500) did not record '=== CLAUDE.md ===' in board.err — a non-404 fetch failure was swallowed as absence (C2)"; _fs=1
  fi
  rm -rf "$_fsroot"
  return "$_fs"
}

# ---- the run --------------------------------------------------------------------------------------
run() {
  if is_adopter_tree; then
    echo "adopter-gates-parity: N/A — kit-self check (audits the kit's own reference source; not present on an adopter tree)"
    return 0
  fi
  if [ "$(_ag_gitlab_only_adopter)" = 1 ]; then
    echo "N/A: adopter-gates-parity — GitLab adopter; backlog-presence/ceremony-binding/loop-state are"
    echo "     declared GitHub-conditional gates in DEVELOPMENT-PROCESS.md (GitHub check-runs, which"
    echo "     GitLab does not provide). Already-ratified platform gap; manual equivalents documented in"
    echo "     docs/operations/gitlab-adoption.md."
    return 0
  fi
  fail=0
  if [ -f "$SRC" ]; then
    assert_marker "$SRC" || { echo "FAIL: $SRC lacks the kit marker (COPY & ADAPT|Sparkwright) — cp_kit_replace would refuse to install it"; fail=1; }
    assert_wired "$SRC"         || fail=1
    assert_stack_neutral "$SRC" || fail=1
    assert_loop_state_active "$SRC" || fail=1
    assert_t2_live_contexts "$SRC" || fail=1
    assert_t2_base_checkout "$SRC" || fail=1
    _t2csout=$(assert_t2_contexts_step_checks_what_it_claims "$SRC" backlog-presence 2>&1) || { printf '%s\n' "$_t2csout"; fail=1; }
    assert_t2_live_contexts_loop_state "$SRC" || fail=1
    assert_t2_base_checkout_loop_state "$SRC" || fail=1
    _t2lcsout=$(assert_t2_contexts_step_checks_what_it_claims "$SRC" loop-state 2>&1) || { printf '%s\n' "$_t2lcsout"; fail=1; }
    assert_t2_loop_state_token_scoped "$SRC" || fail=1
    assert_t2_loop_state_skew_guard "$SRC" || fail=1
    assert_fetch_survives_404 "$SRC" || fail=1
  else
    echo "FAIL: the single source $SRC is MISSING — no stack would get the board/loop gates"
    fail=1
  fi
  assert_single_source profiles      || fail=1
  assert_incept_universal "$INCEPT"  || fail=1

  if [ "$fail" -ne 0 ]; then
    echo "FAIL: adopter-gates-parity — the board/loop gates do not ship uniformly for every stack"
    return 1
  fi
  echo "OK: adopter-gates-parity — single source present, marked, wired, stack-neutral, sole copy; incept installs it universally; loop-state ships ACTIVE and defaults to enforce (observe is a one-line opt-out)"
  return 0
}

# ---- selftest (non-vacuity: every assertion is WITNESSED against a fixture and must be RED-able) --
selftest() {
  st=0
  base=$(mktemp -d)
  trap 'rm -rf "$base"' EXIT

  # A minimal CLEAN source fixture: carries the marker, all wiring tokens, the Δ1 observe dial, and
  # no toolchain step.
  mk_clean_src() {  # <path>
    mkdir -p "$(dirname "$1")"
    {
      printf '# COPY & ADAPT — reference adopter-gates workflow (Sparkwright)\n'
      printf 'env:\n  LOOP_STATE_MODE: enforce\n'
      printf 'jobs:\n  backlog-presence:\n    steps:\n'
      printf '      - uses: actions/checkout@df4cb1c\n        with:\n          ref: ${{ github.event.pull_request.base.sha }}\n'
      printf '      - run: gh api "repos/x/pulls/1/files" -q %s[.[] | .filename, (.previous_filename // empty)] | if any(test("\\n")) then error("nl") else .[] end%s > /tmp/changed.txt\n' "'" "'"
      printf '      - run: sh conformance/agent-boundary.sh --check-complete --changed /tmp/changed.txt\n'
      # TRACKER-TRUSTED-JOB-REQUIRED-CONTEXT T2: the live-contexts fetch (BASE_REF env-bound, never
      # head.ref, an || fallback so a forge hiccup cannot fail this JOB) and the gate call carrying
      # both --base-dir and --live-contexts.
      printf '      - name: Fetch the base branch%ss LIVE required contexts (TRACKER-TRUSTED-JOB-REQUIRED-CONTEXT T2)\n        env:\n          BASE_REF: ${{ github.event.pull_request.base.ref }}\n        run: gh api "repos/${REPO}/branches/${BASE_REF}" --jq %sselect(.name == env.BASE_REF) | .protection.required_status_checks.contexts[]?%s > /tmp/live-contexts 2>/tmp/live-contexts.err || { rm -f /tmp/live-contexts; echo no; }\n' "'" "'" "'"
      printf '      - run: sh conformance/backlog-presence.sh --dir /tmp/board --pr "$PR" --base-dir "$GITHUB_WORKSPACE" --live-contexts /tmp/live-contexts\n'
      printf '      - run: sh conformance/agent-boundary.sh --conclusion "$rc"\n'
      printf '      - run: [ "$rc" = 0 ] || exit 1\n'
      # S-1 (RT2-Q4 STRUCTURAL): a SECOND job that ALSO checks out base.sha — present so the
      # head.sha mutant (case2f4c) can prove the checkout pin is scoped to backlog-presence's OWN
      # job block, never satisfied by a base.sha checkout living in some OTHER job.
      printf '  other-checkout:\n    steps:\n'
      printf '      - uses: actions/checkout@df4cb1c\n        with:\n          ref: ${{ github.event.pull_request.base.sha }}\n'
      # LOOP-STATE-TRACKER-STEP-ASIDE T2 (LS-D1): the loop-state job's own second (base) checkout,
      # its own byte-identical live-contexts step (guarded, job-scoped GH_TOKEN) and its own
      # base-dir/live-contexts gate flags, behind the version-skew probe.
      printf '  loop-state:\n    steps:\n'
      printf '      - uses: actions/checkout@df4cb1c\n        with:\n          fetch-depth: 0\n          persist-credentials: false\n'
      printf '      - uses: actions/checkout@df4cb1c\n        with:\n          ref: ${{ github.event.pull_request.base.sha }}\n          path: .kit-base\n          fetch-depth: 1\n          persist-credentials: false\n'
      printf "      - name: Fetch the base branch's LIVE required contexts (TRACKER-TRUSTED-JOB-REQUIRED-CONTEXT T2)\n        if: hashFiles('.kit-base/.kit/tracker.conf') != ''\n        env:\n          GH_TOKEN: \${{ github.token }}\n          BASE_REF: \${{ github.event.pull_request.base.ref }}\n        run: gh api \"repos/\${REPO}/branches/\${BASE_REF}\" --jq %sselect(.name == env.BASE_REF) | .protection.required_status_checks.contexts[]?%s > /tmp/live-contexts 2>/tmp/live-contexts.err || { rm -f /tmp/live-contexts; echo no; }\n" "'" "'"
      printf '      - run: |\n          if grep -q -- %s--base-dir%s conformance/loop-state.sh; then\n            sh conformance/loop-state.sh --head "$HEAD_SHA" --base-dir "$GITHUB_WORKSPACE/.kit-base" --live-contexts /tmp/live-contexts\n          else\n            sh conformance/loop-state.sh --head "$HEAD_SHA"\n          fi\n' "'" "'"
      printf '      - run: [ "$mode" = enforce ] || exit 0\n'
      # B2 Δ4(ii) + Δ3: the judgment-surface render is part of the wired contract, so the CLEAN
      # fixture must carry it — otherwise this fixture asserts a gap the real shipped source does
      # not have. Post-Δ3 the wired shape is an INVOCATION of the single-sourced render (plus the
      # two-key gate call), never an inline fence/match copy.
      printf '  ceremony-binding:\n    steps:\n'
      printf '      - run: sh conformance/ceremony-binding.sh --scope "PR-$PR_NUMBER" --head-branch "$HEAD_REF"\n'
      printf '      - run: sh conformance/ceremony-binding.sh --render --scope "PR-$PR_NUMBER" --head-branch "$HEAD_REF" >> "$GITHUB_STEP_SUMMARY"\n'
    } > "$1"
  }

  # 1. CLEAN source -> every static assertion PASSES.
  mk_clean_src "$base/src.yml"
  _ok=1
  assert_marker            "$base/src.yml" || _ok=0
  assert_wired              "$base/src.yml" >/dev/null 2>&1 || _ok=0
  assert_stack_neutral       "$base/src.yml" >/dev/null 2>&1 || _ok=0
  assert_loop_state_active   "$base/src.yml" >/dev/null 2>&1 || _ok=0
  assert_t2_live_contexts    "$base/src.yml" >/dev/null 2>&1 || _ok=0
  assert_t2_base_checkout    "$base/src.yml" >/dev/null 2>&1 || _ok=0
  assert_t2_live_contexts_loop_state "$base/src.yml" >/dev/null 2>&1 || _ok=0
  assert_t2_base_checkout_loop_state "$base/src.yml" >/dev/null 2>&1 || _ok=0
  assert_t2_contexts_step_checks_what_it_claims "$base/src.yml" loop-state >/dev/null 2>&1 || _ok=0
  assert_t2_loop_state_token_scoped "$base/src.yml" >/dev/null 2>&1 || _ok=0
  assert_t2_loop_state_skew_guard "$base/src.yml" >/dev/null 2>&1 || _ok=0
  if [ "$_ok" = 1 ]; then echo "OK: clean source -> marker + wired + stack-neutral + loop-state-active + t2-live-contexts + t2-base-checkout + loop-state T2 twins all PASS"; else echo "FAIL: selftest case1 — a clean source fixture reported a gap"; st=1; fi

  # 2. UNWIRED source (drop a conformance call) -> assert_wired RED.
  mk_clean_src "$base/nowire.yml"
  grep -v 'agent-boundary.sh --conclusion' "$base/nowire.yml" > "$base/nowire.yml.tmp" && mv "$base/nowire.yml.tmp" "$base/nowire.yml"
  if assert_wired "$base/nowire.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2 — a source missing a conformance call passed assert_wired"; st=1; else echo "OK: unwired source -> RED (assert_wired)"; fi

  # 2b. HOLLOW: the wiring is COMMENTED OUT, not deleted -> assert_wired RED (comment-strip is
  #     load-bearing).
  {
    printf '# COPY & ADAPT (Sparkwright)\n'
    printf 'jobs:\n  x:\n    steps:\n'
    printf '      - run: gh api "repos/x/pulls/1/files" -q %s[.[] | .filename, (.previous_filename // empty)] | if any(test("\\n")) then error("nl") else .[] end%s > /tmp/changed.txt\n' "'" "'"
    printf '      - run: sh conformance/agent-boundary.sh --check-complete --changed /tmp/changed.txt\n'
    printf '      # - run: sh conformance/agent-boundary.sh --conclusion "$rc"\n'
    printf '      # - run: [ "$rc" = 0 ] || exit 1\n'
  } > "$base/hollow.yml"
  if assert_wired "$base/hollow.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2b — a source with COMMENTED-OUT wiring passed assert_wired (hollow gate)"; st=1; else echo "OK: commented-out wiring -> RED (assert_wired comment-strip)"; fi

  # 2c. LOAD-BEARING NEGATIVE for the previous_filename anchor: a listing derived WITHOUT it must FAIL.
  {
    printf '# COPY & ADAPT (Sparkwright)\n'
    printf 'jobs:\n  x:\n    steps:\n'
    printf '      - run: gh api "repos/x/pulls/1/files" -q %s.[].filename%s > /tmp/changed.txt\n' "'" "'"
    printf '      - run: sh conformance/agent-boundary.sh --check-complete --changed /tmp/changed.txt\n'
    printf '      - run: sh conformance/agent-boundary.sh --conclusion "$rc"\n'
    printf '      - run: [ "$rc" = 0 ] || exit 1\n'
    printf '      - run: [ "$mode" = enforce ] || exit 0\n'
  } > "$base/collapsing.yml"
  if assert_wired "$base/collapsing.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2c — a source deriving its listing WITHOUT previous_filename passed assert_wired"; st=1; else echo "OK: listing without previous_filename -> RED (T2 anchor is load-bearing)"; fi

  # 2d. LOAD-BEARING NEGATIVE for the newline-guard anchor.
  {
    printf '# COPY & ADAPT (Sparkwright)\n'
    printf 'jobs:\n  x:\n    steps:\n'
    printf '      - run: gh api "repos/x/pulls/1/files" -q %s.[] | .filename, (.previous_filename // empty)%s > /tmp/changed.txt\n' "'" "'"
    printf '      - run: sh conformance/agent-boundary.sh --check-complete --changed /tmp/changed.txt\n'
    printf '      - run: sh conformance/agent-boundary.sh --conclusion "$rc"\n'
    printf '      - run: [ "$rc" = 0 ] || exit 1\n'
    printf '      - run: [ "$mode" = enforce ] || exit 0\n'
  } > "$base/noguard.yml"
  if assert_wired "$base/noguard.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2d — a source projecting previous_filename but with NO newline guard passed assert_wired"; st=1; else echo "OK: listing without a newline guard -> RED (guard anchor is load-bearing)"; fi

  # 2e. LOAD-BEARING NEGATIVE for the --check-complete anchor.
  mk_clean_src "$base/nocap.yml"
  grep -v 'check-complete' "$base/nocap.yml" > "$base/nocap.yml.tmp" && mv "$base/nocap.yml.tmp" "$base/nocap.yml"
  if assert_wired "$base/nocap.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2e — a source with no --check-complete call passed assert_wired"; st=1; else echo "OK: listing with no truncation check -> RED (A4 anchor is load-bearing)"; fi

  # 2f. LOAD-BEARING NEGATIVE for the verdict-is-the-exit anchor (2026-08-27, replacing the retired
  #     conclusion-omission guard): a source that computes a verdict and never exits on it is a gate
  #     that is green while enforcing nothing — the fail-open the poster's deletion could have opened.
  mk_clean_src "$base/noexit.yml"
  grep -v 'rc" = 0 \] || exit 1' "$base/noexit.yml" > "$base/noexit.yml.tmp" && mv "$base/noexit.yml.tmp" "$base/noexit.yml"
  if assert_wired "$base/noexit.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f — a source whose gates never exit on the rc passed assert_wired"; st=1; else echo "OK: no exit-on-rc -> RED (the verdict-is-the-exit anchor is load-bearing)"; fi

  # 2f2. LOAD-BEARING NEGATIVE for the no-checks:write anchor — a re-planted scope must RED even
  #      though nothing in the fixture posts anything. A token granted "for later" is the step that
  #      precedes the poster's return.
  mk_clean_src "$base/scope.yml"
  printf '    permissions:\n      checks: write\n' >> "$base/scope.yml"
  if assert_wired "$base/scope.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f2 — a source granting checks: write passed assert_wired"; st=1; else echo "OK: re-planted checks:write -> RED"; fi

  # 2f3. TRACKER-TRUSTED-JOB-REQUIRED-CONTEXT T2 mutant — the live-contexts fetch pointed at
  # github.event.pull_request.head.ref instead of base.ref -> assert_t2_live_contexts RED (RD-1
  # requires the BASE branch's protection; a head-ref fetch lets a PR author name their OWN branch's
  # required contexts, self-delegating the board gate). (Renumbered from 2g on T2 fix round 1 —
  # RT2-Q5 — which collided with the pre-existing case2g/2h below; T2's mutants now live at 2f3/2f4.)
  mk_clean_src "$base/t2_headref.yml"
  sed 's/github\.event\.pull_request\.base\.ref/github.event.pull_request.head.ref/' "$base/t2_headref.yml" > "$base/t2_headref.yml.tmp" && mv "$base/t2_headref.yml.tmp" "$base/t2_headref.yml"
  if cmp -s "$base/t2_headref.yml" "$base/src.yml"; then echo "FAIL: selftest case2f3 setup — the planted mutant did not differ from the clean fixture"; st=1; fi
  if assert_t2_live_contexts "$base/t2_headref.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f3 — a live-contexts fetch pointed at head.ref passed assert_t2_live_contexts"; st=1; else echo "OK: live-contexts fetch on head.ref -> RED (T2 leg iii negative)"; fi

  # 2f4. TRACKER-TRUSTED-JOB-REQUIRED-CONTEXT T2 mutant — --live-contexts dropped from the gate step
  # -> assert_t2_live_contexts RED (the gate would run with no live-contexts file at all, and the
  # tracker step-aside could never fire even on a legitimately delegated base). (Renumbered from 2h
  # on T2 fix round 1 — RT2-Q5.)
  mk_clean_src "$base/t2_nolc.yml"
  sed 's/ --live-contexts \/tmp\/live-contexts//' "$base/t2_nolc.yml" > "$base/t2_nolc.yml.tmp" && mv "$base/t2_nolc.yml.tmp" "$base/t2_nolc.yml"
  if cmp -s "$base/t2_nolc.yml" "$base/src.yml"; then echo "FAIL: selftest case2f4 setup — the planted mutant did not differ from the clean fixture"; st=1; fi
  if assert_t2_live_contexts "$base/t2_nolc.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f4 — a gate step missing --live-contexts passed assert_t2_live_contexts"; st=1; else echo "OK: gate step missing --live-contexts -> RED (T2 leg ii)"; fi

  # 2f4b. RT2-Q4 mutant — the backlog-presence job's checkout ref swapped to head.sha ->
  # assert_t2_base_checkout RED (a head-pinned checkout would hand backlog-presence.sh a tree that
  # is not provably the BASE, defeating --base-dir's whole purpose).
  mk_clean_src "$base/t2_headsha.yml"
  sed 's/base\.sha/head.sha/' "$base/t2_headsha.yml" > "$base/t2_headsha.yml.tmp" && mv "$base/t2_headsha.yml.tmp" "$base/t2_headsha.yml"
  if cmp -s "$base/t2_headsha.yml" "$base/src.yml"; then echo "FAIL: selftest case2f4b setup — the planted mutant did not differ from the clean fixture"; st=1; fi
  if assert_t2_base_checkout "$base/t2_headsha.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f4b — a backlog-presence checkout ref swapped to head.sha passed assert_t2_base_checkout"; st=1; else echo "OK: backlog-presence checkout ref on head.sha -> RED (RT2-Q4)"; fi

  # 2f4c. S-1 (RT2-Q4 STRUCTURAL) — the SCOPING proof: flip ONLY backlog-presence's OWN checkout to
  # head.sha (the FIRST base.sha occurrence in the file), leaving the second job's (other-checkout)
  # base.sha checkout untouched. A whole-file grep for the pinned ref would still find it (in the
  # OTHER job) and wrongly PASS; the job-scoped check must still RED, because it reads only the
  # backlog-presence block.
  mk_clean_src "$base/t2_headsha_scoped.yml"
  awk '!done && sub(/base\.sha/, "head.sha") { done=1 } { print }' "$base/t2_headsha_scoped.yml" > "$base/t2_headsha_scoped.yml.tmp" && mv "$base/t2_headsha_scoped.yml.tmp" "$base/t2_headsha_scoped.yml"
  if cmp -s "$base/t2_headsha_scoped.yml" "$base/src.yml"; then echo "FAIL: selftest case2f4c setup — the planted mutant did not differ from the clean fixture"; st=1; fi
  if ! grep -qF 'ref: ${{ github.event.pull_request.base.sha }}' "$base/t2_headsha_scoped.yml"; then
    echo "FAIL: selftest case2f4c setup — the OTHER job's base.sha checkout was not left intact; the scoping proof needs it untouched"; st=1
  fi
  if assert_t2_base_checkout "$base/t2_headsha_scoped.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f4c — backlog-presence's OWN checkout flipped to head.sha (with an unrelated job still on base.sha) passed assert_t2_base_checkout; the pin is not scoped to the right job block"; st=1; else echo "OK: backlog-presence checkout on head.sha, unrelated job still on base.sha -> RED (RT2-Q4 scoping proof, S-1)"; fi

  # 2f5. RT2-Q1 [SEC] — the contexts-fetch STEP itself checks what it claims (assert_t2_contexts_
  # step_checks_what_it_claims, defined above with the other static assertions so run() can drive it
  # against the real $SRC too, not just this selftest).
  mk_clean_src "$base/t2_clean_step.yml"
  if assert_t2_contexts_step_checks_what_it_claims "$base/t2_clean_step.yml" backlog-presence >/dev/null 2>&1; then
    echo "OK: clean contexts-fetch step -> branches/\${BASE_REF}, no \${{ after run:, no head_ref/head.ref (RT2-Q1)"
  else
    echo "FAIL: selftest case2f5 — the clean fixture's contexts-fetch step failed its own claim-check"; st=1
  fi
  # mutant (a): the run: line inlines github.head_ref instead of the env-bound BASE_REF.
  mk_clean_src "$base/t2_mutant_a.yml"
  sed 's#repos/\${REPO}/branches/\${BASE_REF}#repos/${REPO}/branches/${{ github.head_ref }}#' "$base/t2_mutant_a.yml" > "$base/t2_mutant_a.yml.tmp" && mv "$base/t2_mutant_a.yml.tmp" "$base/t2_mutant_a.yml"
  if cmp -s "$base/t2_mutant_a.yml" "$base/src.yml"; then echo "FAIL: selftest case2f5a setup — the planted mutant did not differ from the clean fixture"; st=1; fi
  if assert_t2_contexts_step_checks_what_it_claims "$base/t2_mutant_a.yml" backlog-presence >/dev/null 2>&1; then
    echo "FAIL: selftest case2f5a — a run: line inlining \${{ github.head_ref }} passed the contexts-fetch claim-check (RT2-Q1 mutant a)"; st=1
  else
    echo "OK: run: line inlining \${{ github.head_ref }} -> RED (RT2-Q1 mutant a)"
  fi
  # mutant (b): the branch is hardcoded to main instead of ${BASE_REF}.
  mk_clean_src "$base/t2_mutant_b.yml"
  sed 's#repos/\${REPO}/branches/\${BASE_REF}#repos/${REPO}/branches/main#' "$base/t2_mutant_b.yml" > "$base/t2_mutant_b.yml.tmp" && mv "$base/t2_mutant_b.yml.tmp" "$base/t2_mutant_b.yml"
  if cmp -s "$base/t2_mutant_b.yml" "$base/src.yml"; then echo "FAIL: selftest case2f5b setup — the planted mutant did not differ from the clean fixture"; st=1; fi
  if assert_t2_contexts_step_checks_what_it_claims "$base/t2_mutant_b.yml" backlog-presence >/dev/null 2>&1; then
    echo "FAIL: selftest case2f5b — a hardcoded branches/main passed the contexts-fetch claim-check (RT2-Q1 mutant b)"; st=1
  else
    echo "OK: hardcoded branches/main -> RED (RT2-Q1 mutant b)"
  fi
  # mutant (c): RT2-Q7 — the run: line shell-reassigns BASE_REF from GITHUB_HEAD_REF before the gh
  # api call, so the step's env: binding (base.ref) is silently overridden by the PR-controlled head.
  mk_clean_src "$base/t2_mutant_c.yml"
  sed 's#run: gh api#run: BASE_REF=$GITHUB_HEAD_REF; gh api#' "$base/t2_mutant_c.yml" > "$base/t2_mutant_c.yml.tmp" && mv "$base/t2_mutant_c.yml.tmp" "$base/t2_mutant_c.yml"
  if cmp -s "$base/t2_mutant_c.yml" "$base/src.yml"; then echo "FAIL: selftest case2f5c setup — the planted mutant did not differ from the clean fixture"; st=1; fi
  if assert_t2_contexts_step_checks_what_it_claims "$base/t2_mutant_c.yml" backlog-presence >/dev/null 2>&1; then
    echo "FAIL: selftest case2f5c — a run: line shell-reassigning BASE_REF=\$GITHUB_HEAD_REF passed the contexts-fetch claim-check (RT2-Q7 mutant)"; st=1
  else
    echo "OK: run: line reassigning BASE_REF=\$GITHUB_HEAD_REF -> RED (RT2-Q7 mutant)"
  fi
  # mutant (d): S-2 — the jq filter's `select(.name == env.BASE_REF)` clause is deleted, so the
  # filter would read ANY branch entry the API happens to return, not necessarily BASE_REF's own.
  mk_clean_src "$base/t2_mutant_d.yml"
  sed "s#select(.name == env.BASE_REF) | ##" "$base/t2_mutant_d.yml" > "$base/t2_mutant_d.yml.tmp" && mv "$base/t2_mutant_d.yml.tmp" "$base/t2_mutant_d.yml"
  if cmp -s "$base/t2_mutant_d.yml" "$base/src.yml"; then echo "FAIL: selftest case2f5d setup — the planted mutant did not differ from the clean fixture"; st=1; fi
  if assert_t2_contexts_step_checks_what_it_claims "$base/t2_mutant_d.yml" backlog-presence >/dev/null 2>&1; then
    echo "FAIL: selftest case2f5d — a jq filter with select(.name == env.BASE_REF) deleted passed the contexts-fetch claim-check (S-2 mutant)"; st=1
  else
    echo "OK: jq filter with select(.name == env.BASE_REF) deleted -> RED (S-2 mutant)"
  fi

  # _mutate_job_only <src> <job> <out> <sed-expr> — apply a sed substitution ONLY inside <job>'s own
  # block (via _extract_job_block), leaving every other job's copy of the same text untouched. This
  # is the scoping proof for LS-D1's job-scoped twins: a mutant confined to one job must red ONLY
  # that job's leg, never the other job's (which still reads clean).
  # NOTE: $3 (<out>) may be THE SAME PATH as $1 (<src>) — every call site below reuses the fixture
  # path for both. The awk redirection `> "$3"` truncates that file BEFORE awk reads $1 if $3==$1,
  # so this writes to a distinct scratch file first and mv's it into place at the end.
  _mutate_job_only() {  # <src> <job> <out> <sed-expr>
    _mjtmp=$(mktemp)
    _mjout=$(mktemp)
    _extract_job_block "$1" "$2" "$_mjtmp"
    sed "$4" "$_mjtmp" > "$_mjtmp.new"
    awk -v job="$2" -v repl="$_mjtmp.new" '
      $0 ~ "^  " job ":" { while ((getline line < repl) > 0) print line; close(repl); skip=1; next }
      skip && /^  [A-Za-z]/ { skip=0 }
      skip { next }
      { print }
    ' "$1" > "$_mjout"
    mv "$_mjout" "$3"
    rm -f "$_mjtmp" "$_mjtmp.new"
  }

  # _mutate_job_only_awk <src> <job> <out> <awk-program> — LS-T2-Q5: the same extract/mutate/splice-
  # back shape as _mutate_job_only above, but for a mutation an ordinary sed expression cannot
  # express (address the LAST match, swap two blocks, insert after a marker line). Replaces three
  # inline copies of this same splice-back awk that used to live at the persist/order/token mutant
  # sites below — a mutation this file could not express as sed was growing its OWN copy of the
  # splice every time, which is exactly the duplication _mutate_job_only already exists to avoid.
  _mutate_job_only_awk() {  # <src> <job> <out> <awk-program>
    _mjatmp=$(mktemp)
    _mjaout=$(mktemp)
    _extract_job_block "$1" "$2" "$_mjatmp"
    awk "$4" "$_mjatmp" > "$_mjatmp.new"
    awk -v job="$2" -v repl="$_mjatmp.new" '
      $0 ~ "^  " job ":" { while ((getline line < repl) > 0) print line; close(repl); skip=1; next }
      skip && /^  [A-Za-z]/ { skip=0 }
      skip { next }
      { print }
    ' "$1" > "$_mjaout"
    mv "$_mjaout" "$3"
    rm -f "$_mjatmp" "$_mjatmp.new"
  }

  # 2f6 — LS-D1 SCOPING PROOF (T2): each pin removed from the loop-state job ONLY must red its
  # loop-state twin while the backlog-presence legs stay green (the twins are independent, never
  # satisfied by the other job's copy) — and vice versa for --live-contexts.
  mk_clean_src "$base/ls_base_dir.yml"
  _mutate_job_only "$base/ls_base_dir.yml" loop-state "$base/ls_base_dir.yml" 's/--base-dir "\$GITHUB_WORKSPACE\/.kit-base"//'
  if assert_t2_live_contexts_loop_state "$base/ls_base_dir.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6a — loop-state job missing --base-dir passed its own twin"; st=1; else echo "OK: loop-state --base-dir removed (loop-state job only) -> RED (twin), untouched elsewhere"; fi
  if ! assert_t2_live_contexts "$base/ls_base_dir.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6a-cross — mutating loop-state's --base-dir also broke backlog-presence's own leg (not job-scoped)"; st=1; fi

  # T2 fix round 2 sweep mutant (gate-flags pin, "not elsewhere in the step"): --base-dir/--live-
  # contexts moved OFF the flagged (then-arm) call line onto the bare (else-arm) call — both flags
  # are still PRESENT somewhere in the job, so a job-wide substring grep would wrongly pass, but
  # loop-state.sh's actual invocation (the then-arm, taken when --base-dir IS understood) now runs
  # unflagged.
  mk_clean_src "$base/ls_flags_wrong_line.yml"
  _mutate_job_only_awk "$base/ls_flags_wrong_line.yml" loop-state "$base/ls_flags_wrong_line.yml" '
    /^            sh conformance\/loop-state\.sh --head "\$HEAD_SHA" --base-dir "\$GITHUB_WORKSPACE\/\.kit-base" --live-contexts \/tmp\/live-contexts$/ { print "            sh conformance/loop-state.sh --head \"$HEAD_SHA\""; next }
    /^            sh conformance\/loop-state\.sh --head "\$HEAD_SHA"$/ { print "            sh conformance/loop-state.sh --head \"$HEAD_SHA\" --base-dir \"$GITHUB_WORKSPACE/.kit-base\" --live-contexts /tmp/live-contexts"; next }
    { print }
  '
  if cmp -s "$base/ls_flags_wrong_line.yml" "$base/src.yml"; then echo "FAIL: selftest case2f6t setup — the planted mutant did not differ from the clean fixture"; st=1; fi
  if ! grep -qF -- '--base-dir "$GITHUB_WORKSPACE/.kit-base"' "$base/ls_flags_wrong_line.yml"; then
    echo "FAIL: selftest case2f6t setup — the flags did not survive the move (job-wide presence check would then trivially red for the wrong reason)"; st=1
  fi
  if assert_t2_live_contexts_loop_state "$base/ls_flags_wrong_line.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6t — --base-dir/--live-contexts moved off the flagged call onto the bare else-arm call passed the twin (gate-flags pin: flags present in the job but on the WRONG line)"; st=1; else echo "OK: --base-dir/--live-contexts moved onto the wrong (bare) call line -> RED (gate-flags pin, flagged-call-line scoping)"; fi

  mk_clean_src "$base/ls_live_contexts.yml"
  _mutate_job_only "$base/ls_live_contexts.yml" loop-state "$base/ls_live_contexts.yml" 's/--live-contexts \/tmp\/live-contexts//'
  if assert_t2_live_contexts_loop_state "$base/ls_live_contexts.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6b — loop-state job missing --live-contexts passed its own twin"; st=1; else echo "OK: loop-state --live-contexts removed (loop-state job only) -> RED (twin)"; fi
  if ! assert_t2_live_contexts "$base/ls_live_contexts.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6b-cross — mutating loop-state's --live-contexts also broke backlog-presence's own leg (not job-scoped)"; st=1; fi

  mk_clean_src "$base/bp_live_contexts.yml"
  _mutate_job_only "$base/bp_live_contexts.yml" backlog-presence "$base/bp_live_contexts.yml" 's/--live-contexts \/tmp\/live-contexts//'
  if assert_t2_live_contexts "$base/bp_live_contexts.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6c — backlog-presence job missing --live-contexts passed its own (re-scoped) leg"; st=1; else echo "OK: backlog-presence --live-contexts removed (backlog-presence job only) -> RED (re-scoped leg)"; fi
  if ! assert_t2_live_contexts_loop_state "$base/bp_live_contexts.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6c-cross — mutating backlog-presence's --live-contexts also broke loop-state's own twin (not job-scoped)"; st=1; fi

  mk_clean_src "$base/ls_path.yml"
  _mutate_job_only "$base/ls_path.yml" loop-state "$base/ls_path.yml" '/path: .kit-base/d'
  if assert_t2_base_checkout_loop_state "$base/ls_path.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6d — loop-state base checkout with no path: .kit-base passed its own twin"; st=1; else echo "OK: loop-state base checkout missing path: .kit-base -> RED (twin)"; fi

  mk_clean_src "$base/ls_fetchdepth.yml"
  _mutate_job_only "$base/ls_fetchdepth.yml" loop-state "$base/ls_fetchdepth.yml" '/fetch-depth: 1/d'
  if assert_t2_base_checkout_loop_state "$base/ls_fetchdepth.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6e — loop-state base checkout with no fetch-depth: 1 passed its own twin"; st=1; else echo "OK: loop-state base checkout missing fetch-depth: 1 -> RED (twin)"; fi

  # T2 fix round 2 sweep mutant: PRESENCE-PRESERVING value change — `path: .kit-base` -> `path:
  # .kit-base-x` still CONTAINS the pinned substring, so a grep -qF pin would wrongly pass while the
  # checkout lands at the wrong path (--base-dir "$GITHUB_WORKSPACE/.kit-base" would point nowhere).
  mk_clean_src "$base/ls_path_wrongval.yml"
  _mutate_job_only "$base/ls_path_wrongval.yml" loop-state "$base/ls_path_wrongval.yml" 's/path: \.kit-base$/path: .kit-base-x/'
  if cmp -s "$base/ls_path_wrongval.yml" "$base/src.yml"; then echo "FAIL: selftest case2f6r setup — the planted mutant did not differ from the clean fixture"; st=1; fi
  if assert_t2_base_checkout_loop_state "$base/ls_path_wrongval.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6r — loop-state base checkout with path: .kit-base-x (substring-preserving) passed its own twin"; st=1; else echo "OK: loop-state base checkout path value widened to .kit-base-x -> RED (exact-value pin)"; fi

  # T2 fix round 2 sweep mutant: PRESENCE-PRESERVING value change — `fetch-depth: 1` -> `fetch-depth:
  # 10` still CONTAINS the pinned substring; the base checkout would no longer be shallow (A3 cost).
  mk_clean_src "$base/ls_fetchdepth_wrongval.yml"
  _mutate_job_only "$base/ls_fetchdepth_wrongval.yml" loop-state "$base/ls_fetchdepth_wrongval.yml" 's/fetch-depth: 1$/fetch-depth: 10/'
  if cmp -s "$base/ls_fetchdepth_wrongval.yml" "$base/src.yml"; then echo "FAIL: selftest case2f6s setup — the planted mutant did not differ from the clean fixture"; st=1; fi
  if assert_t2_base_checkout_loop_state "$base/ls_fetchdepth_wrongval.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6s — loop-state base checkout with fetch-depth: 10 (substring-preserving) passed its own twin"; st=1; else echo "OK: loop-state base checkout fetch-depth widened to 10 -> RED (exact-value pin)"; fi

  # LS-T2-Q1 mutant (M1): `path: .kit-base` moved from the SECOND (base) checkout's own block onto
  # the FIRST (head) checkout — job-wide checks (the pre-fix shape) were satisfied because the field
  # was still present SOMEWHERE in the job; the per-block scoping must red both the missing-on-second
  # and present-on-first legs.
  mk_clean_src "$base/ls_path_on_head.yml"
  _mutate_job_only_awk "$base/ls_path_on_head.yml" loop-state "$base/ls_path_on_head.yml" '
    /path: \.kit-base/ { next }
    /fetch-depth: 0/ { print; print "          path: .kit-base"; next }
    { print }
  '
  if cmp -s "$base/ls_path_on_head.yml" "$base/src.yml"; then echo "FAIL: selftest case2f6n setup — the planted mutant did not differ from the clean fixture"; st=1; fi
  if assert_t2_base_checkout_loop_state "$base/ls_path_on_head.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6n — path: .kit-base moved onto the FIRST (head) checkout passed the per-block base-checkout pin (LS-T2-Q1 / M1)"; st=1; else echo "OK: path: .kit-base moved onto the head checkout -> RED (LS-T2-Q1 per-block scoping)"; fi

  # LS-T2-Q1 mutant — the third-checkout trick: a THIRD actions/checkout step added to the job (base
  # content on the second, an innocuous third) must red the exactly-two-checkouts count even though
  # every field on the first two checkouts stays correct.
  mk_clean_src "$base/ls_third_checkout.yml"
  _mutate_job_only_awk "$base/ls_third_checkout.yml" loop-state "$base/ls_third_checkout.yml" \
    '{ print } /persist-credentials: false/ && !done { print "      - uses: actions/checkout@df4cb1c"; print "        with:"; print "          path: extra"; done=1 }'
  if cmp -s "$base/ls_third_checkout.yml" "$base/src.yml"; then echo "FAIL: selftest case2f6o setup — the planted mutant did not differ from the clean fixture"; st=1; fi
  if assert_t2_base_checkout_loop_state "$base/ls_third_checkout.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6o — a THIRD actions/checkout step in the loop-state job passed the exactly-two-checkouts count (LS-T2-Q1 third-checkout trick)"; st=1; else echo "OK: a third actions/checkout step planted in the loop-state job -> RED (LS-T2-Q1 exactly-two count)"; fi

  # T2 fix round 2 sweep confirmation: the exactly-two-checkouts count is NOT satisfiable/broken by a
  # COMMENTED-OUT third checkout — a `# uses: actions/checkout...` line is not live code and must
  # NOT trip the count (comment-stripping is applied before the count, same as everywhere else).
  mk_clean_src "$base/ls_third_checkout_commented.yml"
  _mutate_job_only_awk "$base/ls_third_checkout_commented.yml" loop-state "$base/ls_third_checkout_commented.yml" \
    '{ print } /persist-credentials: false/ && !done { print "      # - uses: actions/checkout@df4cb1c"; print "      #   with:"; print "      #     path: extra"; done=1 }'
  if cmp -s "$base/ls_third_checkout_commented.yml" "$base/src.yml"; then echo "FAIL: selftest case2f6u setup — the planted fixture did not differ from the clean fixture"; st=1; fi
  if assert_t2_base_checkout_loop_state "$base/ls_third_checkout_commented.yml" >/dev/null 2>&1; then echo "OK: a COMMENTED-OUT third actions/checkout step -> the exactly-two count stays clean (comment-stripped, not counted)"; else echo "FAIL: selftest case2f6u — a commented-out third checkout wrongly tripped the exactly-two-checkouts count"; st=1; fi

  # T2 fix round 2 sweep confirmation: the first-block-clean negative pin is NOT satisfiable/broken
  # by a COMMENTED-OUT `path: .kit-base` planted on the head (first) checkout — since it is not live
  # code, it must NOT trip the "the first checkout must carry no path:" negative.
  mk_clean_src "$base/ls_first_block_commented.yml"
  _mutate_job_only_awk "$base/ls_first_block_commented.yml" loop-state "$base/ls_first_block_commented.yml" \
    '/fetch-depth: 0/ { print; print "          # path: .kit-base"; next } { print }'
  if cmp -s "$base/ls_first_block_commented.yml" "$base/src.yml"; then echo "FAIL: selftest case2f6v setup — the planted fixture did not differ from the clean fixture"; st=1; fi
  if assert_t2_base_checkout_loop_state "$base/ls_first_block_commented.yml" >/dev/null 2>&1; then echo "OK: a COMMENTED-OUT path: .kit-base on the head checkout -> the first-block-clean pin stays clean (comment-stripped, not counted)"; else echo "FAIL: selftest case2f6v — a commented-out path: .kit-base on the head checkout wrongly tripped the first-block-clean negative"; st=1; fi

  mk_clean_src "$base/ls_persist.yml"
  # Deletes only the SECOND (loop-state's OWN) persist-credentials: false line — the first belongs
  # to the head checkout above it. sed can't easily address "the last match"; awk does it directly.
  _mutate_job_only_awk "$base/ls_persist.yml" loop-state "$base/ls_persist.yml" '
    /persist-credentials: false/ { n++; lines[n]=NR }
    { buf[NR]=$0 }
    END {
      last=lines[n]
      for (i=1;i<=NR;i++) if (i!=last) print buf[i]
    }
  '
  if assert_t2_base_checkout_loop_state "$base/ls_persist.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6f — loop-state base checkout with no persist-credentials: false passed its own twin"; st=1; else echo "OK: loop-state base checkout missing persist-credentials: false -> RED (twin)"; fi

  mk_clean_src "$base/ls_order.yml"
  # Swap the two checkout sub-blocks (portable awk, no multi-line sed regex): the base checkout
  # moves ahead of the head checkout — the order pin (LS-D2) must red on this hoist.
  _mutate_job_only_awk "$base/ls_order.yml" loop-state "$base/ls_order.yml" '
    BEGIN { n=0 }
    /uses: actions\/checkout/ { n++ }
    n==1 { headbuf[++hc]=$0; next }
    n==2 { basebuf[++bc]=$0; next }
    { restbuf[++rc]=$0 }
    END {
      for (i=1;i<=bc;i++) print basebuf[i]
      for (i=1;i<=hc;i++) print headbuf[i]
      for (i=1;i<=rc;i++) print restbuf[i]
    }
  '
  if assert_t2_base_checkout_loop_state "$base/ls_order.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6g — loop-state base checkout swapped to FIRST position passed its own order pin"; st=1; else echo "OK: loop-state base checkout hoisted to first -> RED (order pin, LS-D2)"; fi

  mk_clean_src "$base/ls_if.yml"
  _mutate_job_only "$base/ls_if.yml" loop-state "$base/ls_if.yml" "/if: hashFiles/d"
  if assert_t2_live_contexts_loop_state "$base/ls_if.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6h — loop-state contexts step with no if: hashFiles guard passed its own twin"; st=1; else echo "OK: loop-state contexts step missing the hashFiles if: guard -> RED (A3 twin)"; fi

  mk_clean_src "$base/ls_select.yml"
  _mutate_job_only "$base/ls_select.yml" loop-state "$base/ls_select.yml" "s/select(.name == env.BASE_REF) | //"
  if assert_t2_contexts_step_checks_what_it_claims "$base/ls_select.yml" loop-state >/dev/null 2>&1; then echo "FAIL: selftest case2f6i — loop-state contexts step with select(...) dropped passed its own claim-check twin"; st=1; else echo "OK: loop-state contexts step select(.name == env.BASE_REF) dropped -> RED (S-2 twin)"; fi

  mk_clean_src "$base/ls_fallback.yml"
  _mutate_job_only "$base/ls_fallback.yml" loop-state "$base/ls_fallback.yml" 's/|| { rm -f \/tmp\/live-contexts; echo no; }//'
  if assert_t2_live_contexts_loop_state "$base/ls_fallback.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6j — loop-state contexts step with no || fallback passed its own twin"; st=1; else echo "OK: loop-state contexts step missing the || fallback -> RED (twin leg iv)"; fi

  mk_clean_src "$base/ls_token.yml"
  _mutate_job_only_awk "$base/ls_token.yml" loop-state "$base/ls_token.yml" \
    '{ print } /    steps:/ && !done { print "      - run: echo \"$GH_TOKEN\""; print "        env:"; print "          GH_TOKEN: ${{ github.token }}"; done=1 }'
  if assert_t2_loop_state_token_scoped "$base/ls_token.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6k — a GH_TOKEN added to an unrelated loop-state step passed the token-scoping pin"; st=1; else echo "OK: GH_TOKEN added to a second loop-state step -> RED (token-scoping pin)"; fi

  # LS-T2-Q3 mutant (M3): GITHUB_TOKEN: ${{ github.token }} added to the gate step (not GH_TOKEN) —
  # a token-shaped binding outside the fetch step must still red even under a different var name.
  mk_clean_src "$base/ls_token_ghtoken.yml"
  _mutate_job_only_awk "$base/ls_token_ghtoken.yml" loop-state "$base/ls_token_ghtoken.yml" \
    '/mode" = enforce \] \|\| exit 0/ && !done { print "        env:"; print "          GITHUB_TOKEN: ${{ github.token }}"; done=1 } { print }'
  if cmp -s "$base/ls_token_ghtoken.yml" "$base/src.yml"; then echo "FAIL: selftest case2f6m setup — the planted mutant did not differ from the clean fixture"; st=1; fi
  if assert_t2_loop_state_token_scoped "$base/ls_token_ghtoken.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6m — GITHUB_TOKEN: \${{ github.token }} planted on the gate step passed the token-scoping pin (LS-T2-Q3)"; st=1; else echo "OK: GITHUB_TOKEN planted on the gate step -> RED (LS-T2-Q3 token-shaped-binding pin)"; fi

  # T2 fix round 2 sweep mutant: the BRACKET-indexed form (github[...]) added to the gate step — a
  # credential-shaped binding does not have to spell the dotted `github.token` form.
  mk_clean_src "$base/ls_token_bracket.yml"
  _mutate_job_only_awk "$base/ls_token_bracket.yml" loop-state "$base/ls_token_bracket.yml" \
    '{ print } /mode" = enforce \] \|\| exit 0/ && !done { print "        env:"; print "          GH: ${{ github[Qtoken]}"; done=1 }'
  if cmp -s "$base/ls_token_bracket.yml" "$base/src.yml"; then echo "FAIL: selftest case2f6n2 setup — the planted mutant did not differ from the clean fixture"; st=1; fi
  if assert_t2_loop_state_token_scoped "$base/ls_token_bracket.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6n2 — github[ bracket-form token planted on the gate step passed the token-scoping pin"; st=1; else echo "OK: github[ bracket-form token planted on the gate step -> RED (bracket-form widening)"; fi

  mk_clean_src "$base/ls_skew.yml"
  _mutate_job_only "$base/ls_skew.yml" loop-state "$base/ls_skew.yml" "s/grep -q -- '--base-dir' conformance\/loop-state.sh/true/"
  if assert_t2_loop_state_skew_guard "$base/ls_skew.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6l — a loop-state gate step with no real skew probe passed the skew-guard pin"; st=1; else echo "OK: loop-state skew probe replaced with an unconditional true -> RED (skew-guard pin)"; fi

  # LS-T2-Q2 mutant (M2): the skew guard's `else` fallback deleted — on an old checked-out
  # loop-state.sh (no --base-dir), the `if` is false and NEITHER branch runs, so `rc` is never
  # computed and enforce mode would pass silently. Must red.
  mk_clean_src "$base/ls_no_else.yml"
  _mutate_job_only_awk "$base/ls_no_else.yml" loop-state "$base/ls_no_else.yml" '
    /^          else$/ { skip=1; next }
    skip && /^          fi$/ { skip=0; next }
    skip { next }
    { print }
  '
  if cmp -s "$base/ls_no_else.yml" "$base/src.yml"; then echo "FAIL: selftest case2f6p setup — the planted mutant did not differ from the clean fixture"; st=1; fi
  if assert_t2_loop_state_skew_guard "$base/ls_no_else.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6p — a loop-state gate step with the else fallback dropped passed the skew-guard pin (LS-T2-Q2 / M2)"; st=1; else echo "OK: loop-state skew guard's else fallback dropped -> RED (LS-T2-Q2)"; fi

  # T2 fix round 2 BLOCKER mutant: SWAP the flagged and bare calls between the then/else arms — the
  # `then` arm now runs the BARE call (no --base-dir/--live-contexts) and the `else` arm runs the
  # FLAGGED call, so both strings are still present SOMEWHERE in the job (every presence pin above
  # still passes) but the guard now does the OPPOSITE of what it claims: a checkout that DOES
  # understand --base-dir takes the bare call, and an old checkout that does NOT understand the flag
  # takes the flagged call and breaks. Must red on the order check.
  mk_clean_src "$base/ls_swap_calls.yml"
  _mutate_job_only_awk "$base/ls_swap_calls.yml" loop-state "$base/ls_swap_calls.yml" '
    { lines[NR] = $0 }
    /^            sh conformance\/loop-state\.sh --head "\$HEAD_SHA" --base-dir/ { flagged_i = NR }
    /^            sh conformance\/loop-state\.sh --head "\$HEAD_SHA"$/ { bare_i = NR }
    END {
      tmp = lines[flagged_i]; lines[flagged_i] = lines[bare_i]; lines[bare_i] = tmp
      for (i = 1; i <= NR; i++) print lines[i]
    }
  '
  if cmp -s "$base/ls_swap_calls.yml" "$base/src.yml"; then echo "FAIL: selftest case2f6q setup — the planted mutant did not differ from the clean fixture"; st=1; fi
  if ! grep -qF -- '--base-dir "$GITHUB_WORKSPACE/.kit-base"' "$base/ls_swap_calls.yml" || ! grep -qxF '            sh conformance/loop-state.sh --head "$HEAD_SHA"' "$base/ls_swap_calls.yml"; then
    echo "FAIL: selftest case2f6q setup — the swap did not leave both calls present (both presence pins would then trivially red for the wrong reason)"; st=1
  fi
  if assert_t2_loop_state_skew_guard "$base/ls_swap_calls.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2f6q — a loop-state skew guard with the flagged/bare calls SWAPPED between then/else passed the skew-guard pin (BLOCKER mutant: both calls present, presence-only pins fooled)"; st=1; else echo "OK: loop-state skew guard's flagged/bare calls swapped -> RED (order check, BLOCKER)"; fi

  # 2g. LOAD-BEARING NEGATIVE for the Δ1 observe-mode dial (was: the posted `neutral` conclusion; now
  #     the unconditional exit 0 that carries the same non-blocking promise without an API call).
  mk_clean_src "$base/noneutral.yml"
  grep -v 'mode" = enforce \] || exit 0' "$base/noneutral.yml" > "$base/noneutral.yml.tmp" && mv "$base/noneutral.yml.tmp" "$base/noneutral.yml"
  if assert_loop_state_active "$base/noneutral.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2g — a source with no unconditional observe-mode pass passed assert_loop_state_active"; st=1; else echo "OK: no observe-mode exit 0 -> RED (the Δ1 dial anchor is load-bearing)"; fi

  # 2h/2i/2j/2k (B2 Δ4(ii) / reviewer I4 / Δ1 / Δ3, LOAD-BEARING NEGATIVES) — a source that gates
  # ceremony-binding but never RENDERS the matched record to the judgment surface must be RED (2h);
  # so must one that drops the render INVOCATION (2i) or REGROWS an inline copy of it (2j); and so
  # must one that never passes the second scope key (2k). Without these cases each anchor could be
  # deleted with the suite still green, which is exactly how an emitted profile comes to carry
  # enforcement without visibility — or visibility that has silently drifted from what the gate matched.
  mk_clean_src "$base/norender.yml"
  grep -v 'GITHUB_STEP_SUMMARY' "$base/norender.yml" > "$base/norender.tmp" && mv "$base/norender.tmp" "$base/norender.yml"
  if assert_wired "$base/norender.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2h — a source that never writes \$GITHUB_STEP_SUMMARY passed assert_wired; adopters would get the gate without the judgment-surface render"; st=1; else echo "OK: source with no judgment-surface render -> RED (B2 Δ4(ii) anchor is load-bearing)"; fi
  mk_clean_src "$base/noinvoke.yml"
  grep -v 'ceremony-binding.sh --render' "$base/noinvoke.yml" > "$base/noinvoke.tmp" && mv "$base/noinvoke.tmp" "$base/noinvoke.yml"
  if assert_render_single_sourced "$base/noinvoke.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2i — a source that never invokes ceremony-binding.sh --render passed assert_render_single_sourced; the visibility half of the disposition would be missing"; st=1; else echo "OK: render invocation dropped -> RED (Δ3 invocation anchor is load-bearing)"; fi
  mk_clean_src "$base/recopy.yml"
  printf '      - run: while printf %%s "$body" | grep -qF -- "$fence"; do fence="$fence"%s`%s; done\n' "'" "'" >> "$base/recopy.yml"
  printf '      - run: printf %s%%s\\n%s "$b" | grep -qF -x "scope: PR-$PR_NUMBER"\n' "'" "'" >> "$base/recopy.yml"
  if assert_render_single_sourced "$base/recopy.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2j — a source that REGREW an inline fence/match copy passed assert_render_single_sourced; a workflow-local copy drifts from the gate's scope keys and renders nothing on branch-keyed PRs"; st=1; else echo "OK: regrown inline render copy -> RED (Δ3 anti-copy anchor is load-bearing)"; fi
  mk_clean_src "$base/nohead.yml"
  grep -v -- '--head-branch' "$base/nohead.yml" > "$base/nohead.tmp" && mv "$base/nohead.tmp" "$base/nohead.yml"
  if assert_wired "$base/nohead.yml" >/dev/null 2>&1; then echo "FAIL: selftest case2k — a source that never passes --head-branch passed assert_wired; the branch scope key would be dead for adopters and every pre-PR design GO would WAIT"; st=1; else echo "OK: gate leg without --head-branch -> RED (Δ1 second-key anchor is load-bearing)"; fi

  # 3. STACK-SPECIALIZED source (plant actions/setup-node) -> assert_stack_neutral RED.
  mk_clean_src "$base/stacky.yml"
  printf '      - uses: actions/setup-node@v4\n' >> "$base/stacky.yml"
  if assert_stack_neutral "$base/stacky.yml" >/dev/null 2>&1; then echo "FAIL: selftest case3 — a source carrying actions/setup-node passed assert_stack_neutral"; st=1; else echo "OK: stack-specialized source -> RED (assert_stack_neutral)"; fi

  # 4. FAMILY LOCK: a per-profile SUBDIR copy -> assert_single_source RED.
  mkdir -p "$base/prof/go"
  : > "$base/prof/go/adopter-gates.yml"
  if assert_single_source "$base/prof" >/dev/null 2>&1; then echo "FAIL: selftest case4 — a per-profile adopter-gates copy passed the family lock"; st=1; else echo "OK: per-profile subdir copy -> RED (family lock)"; fi
  mkdir -p "$base/prof2"; : > "$base/prof2/adopter-gates.yml"
  if assert_single_source "$base/prof2" >/dev/null 2>&1; then echo "OK: top-level source only, no subdir copy -> PASS"; else echo "FAIL: selftest case4b — a clean single-source root was flagged by the family lock"; st=1; fi

  # 5. INCEPT INSTALL LINE: re-gated per-stack, or not referencing the shared source -> RED.
  printf '%s\n' 'cp_kit_replace "profiles/adopter-gates.yml" .github/workflows/adopter-gates.yml' > "$base/incept-good.sh"
  if assert_incept_universal "$base/incept-good.sh" >/dev/null 2>&1; then echo "OK: unconditional shared-source install -> PASS"; else echo "FAIL: selftest case5a — a correct incept install line was flagged"; st=1; fi
  printf '%s\n' '[ -f "profiles/${STACK}/adopter-gates.yml" ] && cp_kit_replace "profiles/${STACK}/adopter-gates.yml" .github/workflows/adopter-gates.yml' > "$base/incept-bad.sh"
  if assert_incept_universal "$base/incept-bad.sh" >/dev/null 2>&1; then echo "FAIL: selftest case5b — a per-stack-gated install line passed assert_incept_universal"; st=1; else echo "OK: per-stack-gated install -> RED (assert_incept_universal)"; fi

  # 5c. Δ1 LOAD-BEARING NEGATIVE, INVERTED 2026-08-30 (LOOP-STATE-ADOPTER-ENFORCE). This case used
  #     to assert that an `enforce` default must RED. `D-240811-2.1` clause 1 has been AMENDED (see
  #     docs/governance/DECISIONS.md, 2026-08-30): the emitted adopter default is now `enforce`,
  #     because the trigger that kept it in observe — a required trailer set nothing could verify —
  #     was cured in the same PR by ENTRY-CONTRACT-CLASS-PROPORTIONAL. So the polarity flips: a
  #     source that ships `observe` is now the defect.
  mk_clean_src "$base/observedefault.yml"
  sed 's/LOOP_STATE_MODE: enforce/LOOP_STATE_MODE: observe/' "$base/observedefault.yml" > "$base/observedefault.yml.tmp" && mv "$base/observedefault.yml.tmp" "$base/observedefault.yml"
  if assert_loop_state_active "$base/observedefault.yml" >/dev/null 2>&1; then echo "FAIL: selftest case5c — a source defaulting LOOP_STATE_MODE to observe (not enforce) passed assert_loop_state_active"; st=1; else echo "OK: observe-by-default source -> RED (the adopter default is enforce since 2026-08-30)"; fi

  # 5e. I2 SURVIVING MUTANT (reviewer; polarity flipped 2026-08-30 with the default). The live CODE
  #     default has drifted to the WRONG value, but a COMMENT elsewhere in the file duplicates the
  #     literal string the lock wants — a raw (non-comment-stripped) grep would be satisfied by that
  #     comment even though the real default is wrong. Must RED. Now that the wanted default is
  #     `enforce`, the drifted code value is `observe` and the stale comment says `enforce`.
  {
    printf '# COPY & ADAPT (Sparkwright)\n'
    printf '# stale header prose (never updated):    LOOP_STATE_MODE: enforce   (the shipped default)\n'
    printf 'env:\n  LOOP_STATE_MODE: observe\n'
    printf 'jobs:\n  loop-state:\n    steps:\n'
    printf '      - run: sh conformance/loop-state.sh --head "$SHA"\n'
    # SINGLE-CAUSE (review round 1, finding 7): this fixture must fail for its OWN reason — the live
    # code default is `enforce` while only a COMMENT says `observe` — and for nothing else. Omitting
    # the observe escape below would ALSO trip the dial anchor, so the case would pass while proving
    # the wrong thing (the over-determined-fixture class this file already paid for once).
    printf '      - run: [ "$mode" = enforce ] || exit 0\n'
  } > "$base/commentdup.yml"
  if assert_loop_state_active "$base/commentdup.yml" >/dev/null 2>&1; then echo "FAIL: selftest case5e — a source defaulting to observe in CODE, with only a COMMENT duplicating 'LOOP_STATE_MODE: enforce', passed assert_loop_state_active (I2 surviving mutant)"; st=1; else echo "OK: comment-only enforce duplicate with observe live in code -> RED (I2 mutant killed)"; fi

  # 5d. Δ1 LOAD-BEARING NEGATIVE: the FALLBACK shape (loop-state.sh --head fully commented out, no
  #     invocation at all) must NOT read as ACTIVE.
  {
    printf '# COPY & ADAPT (Sparkwright)\n'
    printf 'env:\n  LOOP_STATE_MODE: enforce\n'
    printf 'jobs:\n  loop-state:\n    steps:\n'
    printf '      # - run: sh conformance/loop-state.sh --head "$SHA"\n'
    # SINGLE-CAUSE (finding 7), same rule as 5e: the intended defect is the COMMENTED-OUT gate
    # invocation, so the observe escape must be present or the case would also red on the dial anchor.
    printf '      - run: [ "$mode" = enforce ] || exit 0\n'
  } > "$base/commentedblock.yml"
  if assert_loop_state_active "$base/commentedblock.yml" >/dev/null 2>&1; then echo "FAIL: selftest case5d — a source with loop-state.sh --head fully COMMENTED OUT (the fallback shape) passed assert_loop_state_active"; st=1; else echo "OK: commented-out-block fallback shape -> RED (Δ1 ships ACTIVE, not the fallback)"; fi

  # 6. BEHAVIOURAL WITNESS: drive REAL incept for terraform (a NON-ts, EXEMPT stack) against this
  #    tree's working state and assert .github/workflows/adopter-gates.yml LANDS byte-identical to
  #    the source. Mirrors ratification-parity.sh's own case 6.
  if command -v git >/dev/null 2>&1 && [ -f "$INCEPT" ]; then
    _ref=$(git stash create 2>/dev/null || true); [ -n "$_ref" ] || _ref=$(git rev-parse HEAD 2>/dev/null || echo HEAD)
    _t="$base/incept"; mkdir -p "$_t"
    if git archive "$_ref" 2>/dev/null | tar -x -C "$_t" 2>/dev/null; then
      if ( cd "$_t" && sh scripts/incept.sh --noninteractive --name AdopterGatesParity --intent-owner CI \
             --stack terraform --backlog md --ci github --harness claude-code ) >/dev/null 2>&1; then
        if [ -f "$_t/.github/workflows/adopter-gates.yml" ] \
           && diff "$_t/.github/workflows/adopter-gates.yml" "$_t/profiles/adopter-gates.yml" >/dev/null 2>&1; then
          echo "OK: incept --stack terraform -> .github/workflows/adopter-gates.yml lands == profiles/adopter-gates.yml (non-ts, exempt stack witnessed)"
        else
          echo "FAIL: selftest case6 — incepting a non-ts (terraform) stack did NOT install the board/loop gates from the shared source"; st=1
        fi
      else
        echo "FAIL: selftest case6 — incept --stack terraform did not complete (cannot witness the install)"; st=1
      fi
    else
      echo "FAIL: selftest case6 — could not archive the working tree to drive incept"; st=1
    fi
  else
    echo "FAIL: selftest case6 — git or $INCEPT unavailable; cannot witness the behavioural install"; st=1
  fi

  # 7. KIT-SELF N/A: an adopter-shaped tree (NEITHER kit-dev marker) -> run() N/A, exit 0, never a FAIL.
  _a="$base/adopter"; mkdir -p "$_a"
  if _c7=$( cd "$_a" && SRC="profiles/adopter-gates.yml" INCEPT="scripts/incept.sh"; run 2>&1 ); then _c7rc=0; else _c7rc=$?; fi
  if [ "$_c7rc" = 0 ] && printf '%s\n' "$_c7" | grep -q 'N/A — kit-self check'; then
    echo "OK: adopter-shaped tree (no kit-dev markers) -> N/A, exit 0 (kit-self carve-out)"
  else
    echo "FAIL: selftest case7 — adopter tree did not N/A green (rc=$_c7rc): $_c7"; st=1
  fi

  # 8. GITLAB STRUCTURAL N/A (Δ6): a GitLab-only adopter (.gitlab-ci.yml, no GitHub CI, no adopter-
  #    gates workflow) -> the platform-conditional escape; a GitHub tree with the SAME markers must
  #    NOT take it (checked normally instead).
  _gl="$base/gl"; mkdir -p "$_gl"; : > "$_gl/.gitlab-ci.yml"
  [ "$(_ag_gitlab_only_adopter "$_gl")" = 1 ] || { echo "FAIL: selftest case8a — a GitLab adopter (.gitlab-ci.yml, no adopter-gates workflow) must take the platform-conditional N/A"; st=1; }
  _gh="$base/gh"; mkdir -p "$_gh/.github/workflows"; : > "$_gh/$CI_WF"
  [ "$(_ag_gitlab_only_adopter "$_gh")" = 0 ] || { echo "FAIL: selftest case8b — a GitHub adopter must NOT take the GitLab escape (its missing gates are real drift)"; st=1; }

  # 9. B2 round-2, security M-new-1 — THE RENDER IS EXECUTED, not merely grepped. GitHub caps
  #    $GITHUB_STEP_SUMMARY at 1 MiB and DROPS THE WHOLE SUMMARY past it, so an unbounded render is
  #    a "hide the GO record" path by VOLUME: one forged field measured 1,601,670 bytes emitted
  #    before the bound, which would have posted ceremony-binding PASS with NOTHING rendered — the
  #    exact outcome Δ4(ii) exists to prevent, and the sentence the guard's ceiling rests on
  #    ("the honest control is Δ4(ii)'s VISIBILITY"). Cases 2h/2i only assert the render's SHAPE by
  #    grep; this one RUNS it against a FIXTURE ledger ref — never refs/notes/promotions
  #    (D-240805-3) — for BOTH real sources, which also witnesses the ci.yml/profile mirror
  #    behaviourally. Asserts: (a) a huge record renders TRUNCATED, not dropped, (b) the truncation
  #    is ANNOUNCED (silent truncation hides the record just as effectively), (c) the record's own
  #    head survives, (d) a normal record is NOT truncated and renders whole, (e) a backtick-run
  #    body still gets a fence longer than the run (the one-pass fence must not regress the escape).
  # Δ3 RESHAPE (BRANCH-SCOPE-END-TO-END): the render's BEHAVIOUR is no longer in the workflows, so
  # this case no longer EXECUTES an extracted workflow step — it (i) proves each source's render
  # STEP is an INVOCATION of the single source (extracted from the step itself, so an invocation
  # sitting somewhere else in the file cannot satisfy it) and (ii) executes
  # `conformance/ceremony-binding.sh --render` ONCE for the behavioural assertions. Witnessing
  # behaviour once is CORRECT now and was not before: there is one implementation, and a second
  # execution of the same code would witness nothing the first did not.
  _extract_render() {  # <yml> <out-script> — lift the render step's shell out of the workflow
    awk '
      /- name: Render the matched GO record into the step summary/ { instep=1; next }
      instep && /^[[:space:]]*run: \|/ { inbody=1; next }
      inbody {
        if ($0 ~ /^[[:space:]]*$/) { print ""; next }
        if ($0 !~ /^          /) { exit }
        sub(/^          /, ""); print
      }
    ' "$1" > "$2"
    [ -s "$2" ]
  }
  _fixture_ledger() {  # <dir> <body-file> — a throwaway repo whose FIXTURE notes ref holds the record
    mkdir -p "$1"
    ( cd "$1" && git init -q . \
      && git config user.email tester@example.com && git config user.name tester \
      && git commit -q --allow-empty -m base \
      && git notes --ref=fixture-go add -F "$2" HEAD ) >/dev/null 2>&1
  }
  _fixture_ledger2() {  # <dir> <body1> <body2> — TWO commits, one scope-matching record EACH
    # (B7 rider: the render must show EVERY matching record, so its witness needs a ledger that
    # actually holds two; iteration order is annotated-SHA order, deliberately not controlled here
    # — the assertions below are order-independent).
    mkdir -p "$1"
    ( cd "$1" && git init -q . \
      && git config user.email tester@example.com && git config user.name tester \
      && git commit -q --allow-empty -m base1 \
      && git notes --ref=fixture-go add -F "$2" HEAD \
      && git commit -q --allow-empty -m base2 \
      && git notes --ref=fixture-go add -F "$3" HEAD ) >/dev/null 2>&1
  }
  # Run THE SINGLE SOURCE as CI now does: absolute path (so its $0-relative sourcing resolves to
  # the kit root) with the fixture repo as cwd (so git reads the fixture's FIXTURE ledger ref, never
  # refs/notes/promotions — D-240805-3). stdout is the summary block; stderr is the step log.
  _kitroot=$(pwd)
  _render_into() {  # <unused> <repo> <summary-out> [head-branch] — run the render as CI would
    : > "$3"
    ( cd "$2" && PROMOTION_NOTES_REF=fixture-go \
        sh "$_kitroot/conformance/ceremony-binding.sh" --render --scope PR-909 \
           --head-branch "${4:-a-branch-with-no-record}" ) > "$3" 2>/dev/null
  }
  _rbig="$base/render-big.txt"
  { printf 'gate: design\nscope: PR-909\napproved-by: someone [assurance: declared]\n'
    awk 'BEGIN { s = ""; for (i = 0; i < 1000; i++) s = s "A"; for (j = 0; j < 1600; j++) print s }'
  } > "$_rbig"
  _rtick="$base/render-tick.txt"
  { printf 'gate: design\nscope: PR-909\n'
    awk 'BEGIN { s = ""; for (i = 0; i < 2000; i++) s = s "`"; print s }'
  } > "$_rtick"
  _rsmall="$base/render-small.txt"
  printf 'gate: design\nscope: PR-909\napproved-by: owner [assurance: declared]\nbasis: docs/architecture/x-design.md\n' > "$_rsmall"
  # 9-i — EACH real source's render STEP must be an INVOCATION of the single source. Extracted from
  # the step itself, so an invocation elsewhere in the file cannot satisfy it, and a step that
  # regrew an inline copy cannot hide behind one. This is the parity half; the behaviour is
  # witnessed once, below, because there is now exactly one implementation of it.
  _rn=0
  for _rsrc in "$SRC" "$CI_WF"; do
    _rn=$((_rn + 1))
    if [ ! -f "$_rsrc" ]; then echo "FAIL: selftest case9 — $_rsrc is missing; the judgment-surface render cannot be witnessed"; st=1; continue; fi
    _rscript="$base/render$_rn.sh"
    if ! _extract_render "$_rsrc" "$_rscript"; then
      echo "FAIL: selftest case9 — could not extract the render step's shell from $_rsrc (the step name or its \`run: |\` indentation changed; this case would silently stop witnessing the render)"; st=1; continue
    fi
    if grep -qF 'ceremony-binding.sh --render' "$_rscript" \
       && grep -qF -- '--head-branch' "$_rscript" \
       && grep -qF 'GITHUB_STEP_SUMMARY' "$_rscript"; then
      echo "OK: $_rsrc's render step INVOKES the single source with both scope keys, into the step summary"
    else
      echo "FAIL: selftest case9i — $_rsrc's render STEP does not invoke \`ceremony-binding.sh --render\` with --head-branch into \$GITHUB_STEP_SUMMARY; the two sources would render from different logic (or different keys) than the gate matched on"; st=1
    fi
  done

  # 9-ii — THE BEHAVIOUR, executed against the single source (never grepped). Run in a throwaway
  # repo against a FIXTURE ledger ref, never refs/notes/promotions (D-240805-3).
  _rsrc="conformance/ceremony-binding.sh --render"
  # (a)(b)(c) — the 1.6 MB forged record
  _rrepo="$base/rrepo"; _fixture_ledger "$_rrepo" "$_rbig"
  _rout="$base/summary-big.md"
  _render_into "" "$_rrepo" "$_rout"
  _rbytes=$(wc -c < "$_rout" | tr -d ' ')
  if [ "$_rbytes" -le 65536 ]; then
    echo "OK: $_rsrc renders a $(wc -c < "$_rbig" | tr -d ' ')-byte record in $_rbytes bytes (under GitHub's 1 MiB summary cap, so the record is not DROPPED)"
  else
    echo "FAIL: selftest case9a — $_rsrc emitted $_rbytes bytes for one oversized record; GitHub drops a >1 MiB step summary WHOLE, so ceremony-binding would post PASS with no record rendered"; st=1
  fi
  if grep -qF 'truncated at 8 KB' "$_rout"; then
    echo "OK: $_rsrc ANNOUNCES the truncation (silent truncation hides the record just as well)"
  else
    echo "FAIL: selftest case9b — $_rsrc truncated (or dropped) the record with no notice; the reader cannot tell a short record from a cut one"; st=1
  fi
  grep -qF 'gate: design' "$_rout" \
    && echo "OK: $_rsrc keeps the record's own head inside the truncated render" \
    || { echo "FAIL: selftest case9c — $_rsrc rendered nothing of the record itself"; st=1; }
  # (d) — a NORMAL record must be untouched (the bound must not truncate ordinary records)
  _rrepo2="$base/rsmall"; _fixture_ledger "$_rrepo2" "$_rsmall"
  _rout2="$base/summary-small.md"
  _render_into "" "$_rrepo2" "$_rout2"
  if grep -qF 'basis: docs/architecture/x-design.md' "$_rout2" && ! grep -qF 'truncated at 8 KB' "$_rout2"; then
    echo "OK: $_rsrc renders a normal record WHOLE, with no truncation notice"
  else
    echo "FAIL: selftest case9d — $_rsrc did not render a normal record whole/untruncated"; st=1
  fi
  # (f)/(g) — B7 RIDER: the render shows EVERY scope-matching record (rendering only the first
  # would show a defective record while the gate passed on a valid sibling — a D-240805-4
  # visibility lie), and the 8 KB bound is TOTAL ACROSS RECORDS, not per-record (self-review
  # finding 4: B2's measured volume attack applies with interest when N records render).
  # (f) two SMALL records -> BOTH bodies rendered, no truncation notice.
  _rtwoA="$base/render-twoA.txt"; _rtwoB="$base/render-twoB.txt"
  printf 'gate: design\nscope: PR-909\nmarker: RECORD-A-MARKER\n' > "$_rtwoA"
  printf 'gate: design\nscope: PR-909\nmarker: RECORD-B-MARKER\n' > "$_rtwoB"
  _rrepo4="$base/rtwo"; _fixture_ledger2 "$_rrepo4" "$_rtwoA" "$_rtwoB"
  _rout4="$base/summary-two.md"
  _render_into "" "$_rrepo4" "$_rout4"
  if grep -qF 'RECORD-A-MARKER' "$_rout4" && grep -qF 'RECORD-B-MARKER' "$_rout4" \
     && ! grep -qF 'truncated at 8 KB' "$_rout4"; then
    echo "OK: $_rsrc renders BOTH scope-matching records, untruncated (render-all witnessed)"
  else
    echo "FAIL: selftest case9f — $_rsrc did not render EVERY scope-matching record (a defective record could hide behind the one rendered while the gate passed on another)"; st=1
  fi
  # (g) two records whose COMBINED size exceeds the bound -> bounded output + ANNOUNCED cut
  # (order-independent: whichever record iterates first, the TOTAL bound + notice must hold).
  _rrepo5="$base/rtwobig"; _fixture_ledger2 "$_rrepo5" "$_rtwoA" "$_rbig"
  _rout5="$base/summary-twobig.md"
  _render_into "" "$_rrepo5" "$_rout5"
  _rbytes5=$(wc -c < "$_rout5" | tr -d ' ')
  if [ "$_rbytes5" -le 65536 ] && grep -qF 'truncated at 8 KB' "$_rout5" \
     && grep -qF 'gate: design' "$_rout5"; then
    echo "OK: $_rsrc bounds TWO records TOTAL ($_rbytes5 bytes) and announces the cut (finding 4)"
  else
    echo "FAIL: selftest case9g — $_rsrc with two records emitted $_rbytes5 bytes (want <=65536 + announced truncation + a record head) — the bound must be TOTAL across records, or N records reopen B2's volume attack"; st=1
  fi
  # (e) — the escape must survive the one-pass fence computation
  _rrepo3="$base/rtick"; _fixture_ledger "$_rrepo3" "$_rtick"
  _rout3="$base/summary-tick.md"
  _render_into "" "$_rrepo3" "$_rout3"
  _rfence=$(awk '/^`+$/ { if (length($0) > m) m = length($0) } END { print m + 0 }' "$_rout3")
  if [ "$_rfence" -gt 2000 ]; then
    echo "OK: $_rsrc fences a 2,000-backtick body with a $_rfence-backtick fence (no content can close it)"
  else
    echo "FAIL: selftest case9e — $_rsrc emitted a $_rfence-backtick fence for a 2,000-backtick body; ledger content could close the fence and render as markdown"; st=1
  fi
  # (h) Δ1 — THE SECOND KEY REACHES THE RENDER. A branch-keyed record must render when the head
  # branch is supplied, and NOT when it is not: the render's key set is the gate's, or the two
  # drift and the owner clicks GO on a PR whose record was never shown.
  _rbr="$base/render-branch.txt"
  printf 'gate: design\nscope: branch/feat-x\nmarker: BRANCH-KEY-MARKER\n' > "$_rbr"
  _rrepo6="$base/rbranch"; _fixture_ledger "$_rrepo6" "$_rbr"
  _rout6="$base/summary-branch.md"; _rout7="$base/summary-branch-off.md"
  _render_into "" "$_rrepo6" "$_rout6" feat-x
  _render_into "" "$_rrepo6" "$_rout7" some-other-branch
  if grep -qF 'BRANCH-KEY-MARKER' "$_rout6" && ! grep -qF 'BRANCH-KEY-MARKER' "$_rout7"; then
    echo "OK: $_rsrc renders a BRANCH-keyed record for its own branch and not for another (Δ1 keys reach the render)"
  else
    echo "FAIL: selftest case9h — the render's scope keys do not match the gate's: a branch-keyed record rendered for the wrong branch, or not at all for its own"; st=1
  fi

  # 10. ADOPTER-GATES-JIRA-BLOCKERS C1/C2 — the Fetch step must survive a 404 under -eo pipefail and
  #     keep a non-404 a gate error. The clean fixture above has no Fetch step, so the positive and
  #     both mutants are built from a copy of the REAL profile, normalised to the FIXED shape
  #     (idempotent: already-fixed -> used as is) so the positive PASSES before and after the fix.
  if [ -f "$SRC" ] && command -v bash >/dev/null 2>&1; then
    _fxfix="$base/fetch-fixed.yml"
    if grep -qE '2>&1 >"/tmp/board/\$f"\) \|\| fetch_rc=\$\?$' "$SRC"; then
      cp "$SRC" "$_fxfix"
    else
      awk '
        /^[[:space:]]*fetch_rc=\$\?[[:space:]]*$/ { next }
        /^[[:space:]]*err=\$\(gh api/ { match($0, /^[[:space:]]*/); print substr($0, 1, RLENGTH) "fetch_rc=0" }
        /2>&1 >"\/tmp\/board\/\$f"\)$/ { $0 = $0 " || fetch_rc=$?" }
        { print }
      ' "$SRC" > "$_fxfix"
    fi
    # the fixed copy must carry the fix (guards the awk normalisation itself)
    if grep -qE '2>&1 >"/tmp/board/\$f"\) \|\| fetch_rc=\$\?$' "$_fxfix" && grep -qE '^[[:space:]]*fetch_rc=0[[:space:]]*$' "$_fxfix"; then
      if assert_fetch_survives_404 "$_fxfix" >/dev/null 2>&1; then
        echo "OK: fixed Fetch step survives a 404 and records a non-404 -> PASS (assert_fetch_survives_404)"
      else
        echo "FAIL: selftest case10 — the fixed Fetch step was rejected by assert_fetch_survives_404"; st=1
      fi
    else
      echo "FAIL: selftest case10 — could not build the fixed Fetch-step fixture (normalisation did not apply)"; st=1
    fi
    # 10a. PRE-FIX body: `err=$(...)` then `fetch_rc=$?` on the next line -> RED (C1).
    _fxpre="$base/fetch-prefix.yml"
    awk '
      /^[[:space:]]*fetch_rc=0[[:space:]]*$/ { next }
      / \|\| fetch_rc=\$\?$/ { sub(/ \|\| fetch_rc=\$\?$/, ""); print; print "            fetch_rc=$?"; next }
      { print }
    ' "$_fxfix" > "$_fxpre"
    if cmp -s "$_fxfix" "$_fxpre"; then
      echo "FAIL: selftest case10a — the pre-fix mutant did not differ from the fixed copy (vacuous)"; st=1
    elif assert_fetch_survives_404 "$_fxpre" >/dev/null 2>&1; then
      echo "FAIL: selftest case10a — the pre-fix Fetch body (bare err=\$(...) under -e) passed assert_fetch_survives_404"; st=1
    else
      echo "OK: pre-fix Fetch body (aborts on the first 404) -> RED (C1 is load-bearing)"
    fi
    # 10b. non-404 branch loses its board.err write -> RED (C2).
    _fxnoerr="$base/fetch-noerr.yml"
    grep -vF "printf '=== %s ===" "$_fxfix" > "$_fxnoerr" || true
    if cmp -s "$_fxfix" "$_fxnoerr"; then
      echo "FAIL: selftest case10b — the non-404-swallowed mutant did not differ from the fixed copy (vacuous)"; st=1
    elif assert_fetch_survives_404 "$_fxnoerr" >/dev/null 2>&1; then
      echo "FAIL: selftest case10b — a Fetch step that swallows a non-404 (no board.err write) passed assert_fetch_survives_404"; st=1
    else
      echo "OK: non-404 swallowed as absence -> RED (C2 is load-bearing)"
    fi
  else
    echo "SKIP: selftest case10 — $SRC or bash missing (not a pass)"
  fi

  if [ "$st" = 0 ]; then echo "adopter-gates-parity --selftest: OK (all cases witnessed)"; else echo "adopter-gates-parity --selftest: FAIL"; fi
  return "$st"
}

case "${1:-}" in
  --selftest) selftest ;;
  '')         run ;;
  *)          echo "usage: adopter-gates-parity.sh [--selftest]" >&2; exit 2 ;;
esac
