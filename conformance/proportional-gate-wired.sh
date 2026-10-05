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

# ── S-1 pairing leg + N-3 SEAM_RECORD= setter scan (TBG-TRUSTED-JOB, design
# docs/architecture/2026-09-22-tbg-trusted-job-design.md §4/§8, ruling D-240919-2(3)). ─────────────
#
# A job that references a tracker credential (secrets.KIT_TRACKER_*/JIRA_*) must NEVER also check
# out or run PR-head-controlled code — that pairing is the exact `pull_request_target`
# credential-theft shape (design §8 threat A) the trusted job (profiles/adopter-tracker-gates.yml)
# exists to avoid. And SEAM_RECORD may be assigned ONLY by the sanctioned setters enumerated below
# (N-3, count kept out of this sentence on purpose — it was "two" here through the third and fourth
# additions below and went stale each time): the trusted job itself, and conformance/loop-state.sh's
# local/hygiene KIT_TRACKER_RECORD map — a stray setter outside the enumerated list is a
# planted-record attack surface (threat D/F).
TJ_FLEET_GLOBS=".github/workflows/*.yml profiles/*.yml profiles/*/ci.yml"
# .github/workflows/tracker-live.yml joins the allowlist as a THIRD, narrowly-scoped setter (added
# in the fix-round, M-2): it is KIT-ONLY, export-ignored (never ships to an adopter), triggered only
# by `workflow_dispatch`/`schedule` (never `pull_request_target` — it processes no PR-controlled
# content), and its SEAM_RECORD assignment is entirely SELF-CONTAINED — set and consumed within the
# same nested-shell process that proves the seam's own bind/refuse logic against a tracked fixture,
# never persisted for a later job or a real board gate to pick up. N-3's threat (a planted record a
# REAL gate later trusts) does not apply to a self-contained proof harness.
# `.github/workflows/adopter-tracker-gates.yml` joins as a FOURTH setter (fix-round, artifact-gate
# CI): incept.sh installs the kit-path source `profiles/adopter-tracker-gates.yml` TO this path on
# every incepted/adopter tree (cp_kit_replace) — it is the SAME trusted job, at its INSTALLED
# location, not a second one. The kit-path entry stays too: the kit's own tree carries the source
# under `profiles/`, never installed at `.github/workflows/` on the kit repo itself.
# `conformance/backlog-current.sh` joins as a FIFTH setter (TBG-READER-FLAGS-LIST T10-n3, CI red on
# the push otherwise): its ONE production-path assignment, `check_dir`'s
# `SEAM_RECORD="${KIT_TRACKER_RECORD:-}"`, is the READING side of the trusted job's fixed path —
# identical in shape to loop-state.sh's already-allowlisted `run_gate` map, and gated the same way
# (only reached for a non-md backend; an unset KIT_TRACKER_RECORD leaves today's non-tracker
# behaviour byte-identical). Every OTHER setter in this file lives inside its own `selftest()`
# function: env-var prefixes on the file's own re-invocations of itself against constructed git
# fixtures, set and consumed by that same in-process harness, never persisted for a later job or a
# real board gate to read. N-3's threat (a planted record a REAL gate later trusts) applies to
# neither shape.
# `conformance/backlog-presence.sh` joins as a SIXTH setter (same slice, same CI red): its ONE
# production-path assignment, `check_pr`'s `SEAM_RECORD="${KIT_TRACKER_RECORD:-}"`, is the same
# reading-side mapping, gated the same way (only reached past the ordinary/gated split, for a non-md
# backend). Every other setter is a selftest fixture: the bulk sit lexically inside `selftest()`,
# and the `t8h_run` helper (defined below `selftest()`'s closing brace but called only from within
# it) sets `KIT_TRACKER_RECORD=` as an env prefix when re-invoking this file's own CLI as a
# subprocess against a fixture directory — still self-contained, same file, same in-process proof
# harness, never a real gate.
# `scripts/tracker-read.sh` joins as a SEVENTH setter (same slice, same CI red): this file carries
# NO production-path assignment at all — the reader consumes `SEAM_RECORD`/`SEAM_ROOT`/`SEAM_HEAD`
# as inputs its caller sets, it never sets them for a real run. Every setter found here lives inside
# `_tr_selftest()`, the file's `--selftest` entry point: env-var prefixes on constructed git
# fixtures and on the file's own re-invocations of itself, proving the seam's bind/refuse logic
# in-process. Classification (b) throughout; N-3's threat does not apply.
# conformance/proportional-gate-wired.sh (security M-1, close fix round 1): its selftest sets the
# record for a throwaway fixture tree only — the same classification as the gates' own selftest
# setters above; its production code is held to zero setters by B6.
# conformance/board-drift.sh (security review, TBG-WIRE-LOCAL fix round): carries NO production-path
# assignment; §4.5 tracker-arm reads SEAM_RECORD only via backlog-lib's
# seam_tracker_record_set/seam_rows_in_state from caller env; every setter is a selftest() fixture
# (subshells, legs J/K/L/M/O/P); B6 pins production at 0.
# hooks/pre-push (security review, TBG-WIRE-LOCAL fix round): the LOCAL face; decl_check_ref binds
# SEAM_RECORD/SEAM_HEAD/KIT_TRACKER_RECORD COMMAND-SCOPED on the single loop-state invocation (M-2)
# and blanks them on the unbound path (I2); record path is fixed per repo (S-10), written by
# tracker-read.sh from the origin-pinned conf; never runs in CI; consumer is the A2/B1 local
# speed-bump. N-3's threat (a record a real CI gate trusts) does not apply.
# scripts/promotion-verify.sh (security review, TBG-WIRE-LOCAL fix round): do_land's A9 hygiene
# re-read binds the same fixed local path for one in-process seam_row_state call, cleared before and
# after (twin of pre-push M-2/I2); hygiene, not a control; never runs in CI; B6 pins production at 1.
TJ_SEAM_RECORD_ALLOWED_SETTERS="conformance/loop-state.sh profiles/adopter-tracker-gates.yml .github/workflows/adopter-tracker-gates.yml .github/workflows/tracker-live.yml conformance/backlog-current.sh conformance/backlog-presence.sh scripts/tracker-read.sh conformance/proportional-gate-wired.sh conformance/board-drift.sh hooks/pre-push scripts/promotion-verify.sh"
TJ_SEAM_RECORD_SCAN_DIRS="conformance scripts hooks profiles .github"

# _tj_fleet -> every workflow file the fleet globs resolve to that actually exists, one per line.
_tj_fleet() {
  for _g in $TJ_FLEET_GLOBS; do
    for _f in $_g; do [ -f "$_f" ] && printf '%s\n' "$_f"; done
  done
}

# ── REWRITTEN after the fix-round security seat's B-1 (12/13 evasion fixtures passed GREEN on the
# first draft): job enumeration and both detectors are now SCOPED to the `jobs:` section (never a
# literal "  <name>:" match anywhere in the file, which is how the first draft's `_job_names` mis-
# read `on:`'s own `pull_request:` trigger key as a job), TOLERANT OF ANY CONSISTENT INDENT (not
# hardcoded 2-space), TRAILING-COMMENT-TOLERANT on the job key line, CASE-INSENSITIVE on the head-
# checkout side, and the secret side now also reads a WORKFLOW-LEVEL `env:` (visible to every job)
# and a `toJSON(secrets)` capture, not only `secrets.KIT_TRACKER_*`/`JIRA_*` by name — a renamed
# `secrets.<anything>` still trips it because the leg reads the job's own ENV-KEY NAME, which the
# job cannot rename without also renaming what it reads at runtime.

# _tj_jobs_section <file> -> the CODE (comments stripped) lines strictly inside the top-level
# `jobs:` key — never a same-named key elsewhere in the file (e.g. `on:`'s `pull_request:`).
_tj_jobs_section() {
  code_only "$1" 2>/dev/null | awk '
    /^jobs:[[:space:]]*$/ { f=1; next }
    f && /^[^[:space:]]/ { f=0 }
    f { print }
  '
}

# _tj_job_indent <jobs-section-text> -> the indent width of job keys — the indent of the section's
# first non-blank line, so a 2-space OR a 4-space (or any other consistent) job indent both work.
_tj_job_indent() {
  printf '%s\n' "$1" | awk '
    /^[[:space:]]*$/ { next }
    { s=$0; n=0; while (substr(s,n+1,1)==" ") n++; print n; exit }
  '
}

# _tj_job_names <file> -> every job key declared directly under `jobs:`, at whatever indent this
# file's jobs use, tolerant of a trailing comment on the key line (e.g. `bad-job:   # note`).
_tj_job_names() {
  _sec=$(_tj_jobs_section "$1")
  [ -n "$_sec" ] || return 0
  _ind=$(_tj_job_indent "$_sec")
  [ -n "$_ind" ] || return 0
  printf '%s\n' "$_sec" | awk -v ind="$_ind" '
    {
      s=$0; n=0; while (substr(s,n+1,1)==" ") n++
      if (n!=ind) next
      line=s; sub(/^[ ]+/,"",line); sub(/[[:space:]]*#.*$/,"",line)
      if (line ~ /^[A-Za-z0-9_-]+:[[:space:]]*$/) { sub(/:.*$/,"",line); print line }
    }
  '
}

# _tj_job_block <file> <job-key> -> the lines strictly inside that job (deeper than the job
# indent), scoped to the `jobs:` section only — a same-named key under `on:` can never match.
_tj_job_block() {
  _sec=$(_tj_jobs_section "$1")
  [ -n "$_sec" ] || return 0
  _ind=$(_tj_job_indent "$_sec")
  printf '%s\n' "$_sec" | awk -v ind="$_ind" -v key="$2" '
    {
      s=$0; n=0; while (substr(s,n+1,1)==" ") n++
      if (n==ind) {
        line=s; sub(/^[ ]+/,"",line); sub(/[[:space:]]*#.*$/,"",line); sub(/:.*$/,"",line)
        f = (line==key) ? 1 : 0
        next
      }
      if (f) print
    }
  '
}

# _tj_workflow_env_section <file> -> the CODE lines inside a TOP-LEVEL (0-indent) `env:` key that
# appears BEFORE `jobs:` — visible to every job in the file (a workflow-level secret pairing is
# just as real as a step-scoped one).
_tj_workflow_env_section() {
  code_only "$1" 2>/dev/null | awk '
    /^jobs:[[:space:]]*$/ { exit }
    /^env:[[:space:]]*$/ { f=1; next }
    f && /^[^[:space:]]/ { f=0 }
    f { print }
  '
}

# _tj_has_tracker_secret_text <text> -> 0 iff the text references a tracker credential: any
# `secrets.<name>` reference, `toJSON(secrets)`, or a recognised tracker ENV-KEY NAME (catches a
# renamed `secrets.<X>` value, since what matters is what the job's own env key is called — that
# name is what any later step actually reads to authenticate).
_tj_has_tracker_secret_text() {
  # `secrets.GITHUB_TOKEN` is the forge's own default, automatic token — every real job in this
  # fleet legitimately reads it, and it is not a "tracker credential" S-1 cares about; matching it
  # here paired with the also-broad head-checkout detector false-positived on ci.yml's own `changes`
  # job (which fetches a MERGED PR's head as objects via `refs/pull/…` — the sanctioned pattern —
  # using only `secrets.GITHUB_TOKEN`). Excluded by NAME, never by scope, so a job that renames the
  # default token via `env: X: ${{ secrets.GITHUB_TOKEN }}` still reads as GITHUB_TOKEN here (the
  # match is on the RHS token, not the LHS env-key name).
  printf '%s\n' "$1" | grep -oE 'secrets\.[A-Za-z0-9_]+' | grep -qvE '^secrets\.GITHUB_TOKEN$' && return 0
  printf '%s\n' "$1" | grep -qE 'toJSON\([[:space:]]*secrets[[:space:]]*\)' && return 0
  printf '%s\n' "$1" | grep -qE '(KIT_TRACKER_(USER|TOKEN)|JIRA_(TOKEN|EMAIL))[[:space:]]*:' && return 0
  # H-C(c), second fix round: a DYNAMIC secret index (`secrets[format(...)]`, `secrets[matrix.x]`,
  # etc) — the literal name is opaque to a text scan, so treated conservatively as "carries a
  # secret" whenever it appears at all (an over-approximation; the safe direction for a security leg).
  printf '%s\n' "$1" | grep -qE 'secrets\[' && return 0
  # H-C (q6, cross-job indirection): a job consuming ANOTHER job's `needs.*.outputs.*` may be
  # consuming a value that job derived FROM a secret (the seat's demonstrated shape: job A
  # base64-encodes its tracker token into an output, job B reads it via `needs.a.outputs.t` with no
  # `secrets.` text of its own at all). Over-approximated the same way (c) is: flagged whenever the
  # pattern appears, not only when the source job is proven to hold a secret — a grep scan cannot
  # follow the cross-job data flow precisely, and the safe direction is to over-flag.
  # Scoped to an ENV-KEY ASSIGNMENT specifically (`KEY: ${{ needs.job.outputs.name }}`), never a
  # bare `if:`/`needs:` condition — a job-level `if: needs.x.outputs.has_build == 'true'` is an
  # ordinary boolean gate, not a value flowing anywhere, and an unscoped match false-positived on
  # exactly that shape (profiles/*/ci.yml's `provenance` jobs), measured while building this rule.
  printf '%s\n' "$1" | grep -qE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*"?\$\{\{[[:space:]]*needs\.[A-Za-z0-9_-]+\.outputs\.' && return 0
  return 1
}

# _tj_block_has_tracker_secret <file> <block-text> -> 0 iff the JOB carries a tracker secret,
# either in its own body or via a workflow-level `env:` ahead of `jobs:` (evasion p5).
_tj_block_has_tracker_secret() {
  _tj_has_tracker_secret_text "$2" && return 0
  _we=$(_tj_workflow_env_section "$1")
  [ -n "$_we" ] && _tj_has_tracker_secret_text "$_we" && return 0
  return 1
}

# _tj_block_has_head_checkout <block-text> -> 0 iff the block makes PR-head-controlled code THE
# WORKING TREE, or otherwise reaches it: a checkout `ref:` (quoted or not) naming head_ref/
# pull_request.head.(sha|ref)/merge_commit_sha/pull_request.number/event.number; a `refs/pull` or
# `pull/<n>` ref; `git checkout|switch|reset|worktree|archive|show|cat-file` naming FETCH_HEAD/
# HEAD_SHA/head; `gh pr checkout`; or `download-artifact` (a build artifact from the head run).
# Case-insensitive throughout. Narrowly scoped to actually REACHING the head tree — the trusted job
# legitimately READS the head sha as metadata (git fetch of objects, git log for Kit-Row, exporting
# SEAM_HEAD) without ever checking it out; a leg that flagged every head.sha mention would red the
# trusted job itself for doing its job.
# HONEST RESIDUAL (security seat, stated in THREAT-MODEL T9, not claimed closed here): head code
# EXECUTED WITHOUT any checkout verb this leg recognises — e.g. `git show $HEAD_SHA:path | sh` piped
# straight into an interpreter with no `git checkout`/`switch` in between — is not fully grep-
# detectable; `show`/`cat-file` are included precisely to narrow that gap, not to close it.
_tj_block_has_head_checkout() {
  _b="$1"
  printf '%s\n' "$_b" | grep -qiE 'ref:[[:space:]]*"?\$\{\{[^}]*(head_ref|pull_request\.head\.(sha|ref)|merge_commit_sha|pull_request\.number|event\.number)' && return 0
  printf '%s\n' "$_b" | grep -qiE 'refs/pull|pull/[0-9]' && return 0
  printf '%s\n' "$_b" | grep -qiE 'git[[:space:]]+(checkout|switch|reset|worktree|archive|show|cat-file)([^\n]*)(fetch_head|head_sha|head)' && return 0
  printf '%s\n' "$_b" | grep -qiE 'gh[[:space:]]+pr[[:space:]]+checkout' && return 0
  printf '%s\n' "$_b" | grep -qiE 'download-artifact' && return 0
  _tj_block_tainted "$_b" && return 0
  return 1
}

# _tj_block_tainted <block-text> -> H-C (second fix round security seat): "taint-lite" rules —
# still grep, but scanning line-by-line with a small ALLOWLIST rather than a single denylist regex,
# to catch INDIRECTION the first-round detector missed (10 of 12 seat-demonstrated shapes passed
# GREEN): the head sha routed through env/matrix/step-output/needs-outputs before reaching a
# checkout `ref:`, a dynamic git-command target, a raw-content fetch, unsafe PR-text interpolation
# in `run:`, and an opaque local composite action. HONEST CEILING (stated here and in THREAT-MODEL
# T9, not claimed complete): a grep scan cannot follow arbitrary indirection (a computed `export
# "$v=…"`, a fully opaque LOCAL OR THIRD-PARTY action doing the checkout internally with no `uses:
# ./` marker this rule can see). This is defense-in-depth / regression-catching; the ACTUAL S-1
# control is the base-defined workflow + control-plane ratification, not this detector.
_tj_block_tainted() {
  printf '%s\n' "$1" | while IFS= read -r _tjt_l; do
    # (a) actions/checkout `ref:`/`repository:` set to ANY `${{ }}` expression except an ALLOWLISTED
    # one (github.sha / *base.sha — the only two safe subjects a trusted job ever checks out), or a
    # literal `refs/heads/...` (a moving branch pointer, never a pin).
    case "$_tjt_l" in
      *ref:*'${{'*|*repository:*'${{'*)
        case "$_tjt_l" in
          *github.sha*|*base.sha*) : ;;
          *) echo TAINT; continue ;;
        esac ;;
    esac
    case "$_tjt_l" in
      *ref:*refs/heads/*) echo TAINT; continue ;;
    esac
    # (r4, second fix round's second re-review) a `ref:` whose value is a FOLDED/LITERAL BLOCK
    # SCALAR (`>-`/`>`/`|-`/`|`) — rule (a) above only sees an inline `${{ }}` on the SAME line, and
    # a block scalar puts the head expression on a CONTINUATION line this per-line scanner does not
    # look ahead to. Flagged as suspect outright (never inspected for content) — an over-
    # approximation, the same safe direction as (c)/(g): a benign folded `ref: base.sha` would also
    # be flagged, which is an acceptable false-positive rate for a security leg.
    printf '%s\n' "$_tjt_l" | grep -qE '^[[:space:]]*ref:[[:space:]]*[>|][+-]?[[:space:]]*$' && { echo TAINT; continue; }
    # (b) a `git` invocation (optionally carrying `-c`/`-C`/`--git-dir=`) of checkout/switch/reset/
    # worktree/archive/show/cat-file/merge/pull/cherry-pick/restore/apply/read-tree/stash whose
    # ARGUMENTS carry a `$`-expansion — catches `git checkout "$SHA"`, `git -c … checkout $HEAD_SHA`,
    # `git merge --no-edit "$SHA"`, `git restore --source="$SHA" -- .`, not just the literal
    # `head`/`HEAD_SHA`/`FETCH_HEAD` tokens the base rule above already covers.
    case "$_tjt_l" in
      *git*checkout*'$'*|*git*switch*'$'*|*git*reset*'$'*|*git*worktree*'$'*|*git*archive*'$'*|*git*show*'$'*|*git*cat-file*'$'*)
        echo TAINT; continue ;;
      *git*merge*'$'*|*git*pull*'$'*|*git*cherry-pick*'$'*|*git*restore*'$'*|*git*apply*'$'*|*git*read-tree*'$'*|*git*stash*'$'*)
        echo TAINT; continue ;;
    esac
    # `git apply` with NO `$`-expansion on the same line (piped from `gh pr diff`, r2's shape —
    # the diff TEXT carries the head content, not a shell variable this line-scanner can see) — and
    # `gh pr diff` itself, which pulls head-tree content in a secret job regardless of what consumes it.
    case "$_tjt_l" in
      *'git apply'*|*'gh pr diff'*) echo TAINT; continue ;;
    esac
    # (d) fetching raw head-tree CONTENT over HTTP and (elsewhere) executing it — the class p8/q11
    # generalise: no `git checkout` verb at all, just a blob/content read.
    case "$_tjt_l" in
      *curl*raw.githubusercontent*|*curl*/git/blobs/*|*curl*/contents/*|*wget*raw.githubusercontent*|*wget*/git/blobs/*|*wget*/contents/*)
        echo TAINT; continue ;;
    esac
    # (e) untrusted PR text (body/title, issue/comment body, head_ref) interpolated directly into a
    # `run:` script — a DIFFERENT S-1-adjacent hazard (script injection into the shell that also
    # holds the secret in env), flagged here per the security seat's grouping.
    case "$_tjt_l" in
      *'${{ github.event.pull_request.body'*|*'${{ github.event.pull_request.title'*) echo TAINT; continue ;;
      *'${{ github.event.issue.body'*|*'${{ github.event.issue.title'*) echo TAINT; continue ;;
      *'${{ github.event.comment.body'*|*'${{ github.head_ref'*) echo TAINT; continue ;;
    esac
    # (f) a LOCAL composite action — opaque to this text scan; its own steps could do anything,
    # including the exact checkout/exec this leg exists to catch, invisibly to a scan of THIS file.
    case "$_tjt_l" in
      *'uses: ./'*) echo TAINT; continue ;;
    esac
  done | grep -q TAINT
}

# tj_pairing_leg -> 0 iff no job in the whole fleet pairs a tracker secret with a head checkout.
tj_pairing_leg() {
  _tjp_bad=0
  for _tjp_f in $(_tj_fleet); do
    for _tjp_j in $(_tj_job_names "$_tjp_f"); do
      _tjp_blk=$(_tj_job_block "$_tjp_f" "$_tjp_j" || true)
      if _tj_block_has_tracker_secret "$_tjp_f" "$_tjp_blk" && _tj_block_has_head_checkout "$_tjp_blk"; then
        echo "FAIL: $_tjp_f job '$_tjp_j' pairs a tracker secret (secrets.*/env-key KIT_TRACKER_*/JIRA_*/toJSON(secrets)) with a PR-head checkout/ref — exactly the pull_request_target credential-theft shape (S-1, D-240919-2(3)). The job must check out BASE only and fetch the head as objects, never checkout/ref/switch/show it"
        _tjp_bad=1
      fi
    done
  done
  return $_tjp_bad
}

# ── FIX-ROUND M-1: the scan was on the WRONG variable + missed spellings. On the CI path the
# EFFECTIVE setter is `KIT_TRACKER_RECORD` — `loop-state.sh`'s `run_gate` overwrites `SEAM_RECORD`
# from it on every call (`SEAM_RECORD="${KIT_TRACKER_RECORD:-}"`), so a stray `KIT_TRACKER_RECORD=`
# assignment is exactly as dangerous as a stray `SEAM_RECORD=` and the first draft never looked for
# it. Both names are scanned now, over more spellings than a bare `X=`/`X:` — `X+=`, `read X`,
# `eval …X…`, and an `X…>> "$GITHUB_ENV"` append — and `hooks/` files (extensionless) are no longer
# skipped by an extension filter.
TJ_SEAM_RECORD_NAMES="SEAM_RECORD KIT_TRACKER_RECORD"

# _tj_text_sets_seam_record <text> -> 0 iff the text assigns either sanctioned-setter-scoped name
# under any of the recognised spellings.
_tj_text_sets_seam_record() {
  for _tjn in $TJ_SEAM_RECORD_NAMES; do
    # Shell assignment: NAME= or NAME+= (bare `=`). NOTE the CORRECTION (M-A, second fix round):
    # `${NAME:-…}`/`${NAME:+…}` are pure READS and must NOT trip this (measured:
    # `${SEAM_RECORD:-}` false-positived the first cut) — but `${NAME:=…}` is NOT a read, it IS an
    # assignment (it SETS NAME to the default when unset), and the first cut's comment wrongly
    # grouped all three together. Matched explicitly below, never lumped in with the `:-`/`:+` carve-out.
    printf '%s\n' "$1" | grep -qE "(^|[^A-Za-z0-9_])${_tjn}\+?=" && return 0
    printf '%s\n' "$1" | grep -qE "\\\$\\{${_tjn}:=" && return 0
    # YAML key: NAME: <value-or-EOL> — colon then whitespace/EOL, never `NAME:-`/`NAME:+`/`NAME:=`
    # (those are the same parameter-expansion operators, colon directly followed by the modifier).
    printf '%s\n' "$1" | grep -qE "(^|[^A-Za-z0-9_])${_tjn}:([[:space:]]|\$)" && return 0
    # `read NAME` — an OPTIONAL flag/option prefix ending in whitespace (`read -r NAME`), or NONE at
    # all (`read NAME`, single space). M-A, second fix round: the original `[^#]*(^|[^A-Za-z0-9_])`
    # form required a non-word delimiter to precede NAME, which single-space `read NAME` never has
    # (nothing sits between the mandatory `read `'s trailing space — already consumed — and NAME
    # itself) — measured, false-negative. `([^#]*[[:space:]])?` makes that prefix optional.
    printf '%s\n' "$1" | grep -qE "read[[:space:]]+([^#]*[[:space:]])?${_tjn}([^A-Za-z0-9_]|\$)" && return 0
    printf '%s\n' "$1" | grep -qE "eval[[:space:]].*${_tjn}" && return 0
    printf '%s\n' "$1" | grep -qE "${_tjn}.*GITHUB_ENV" && return 0
  done
  return 1
}

# _tj_seam_record_setter_files -> every file under the scanned dirs whose CODE (comments stripped)
# assigns SEAM_RECORD or KIT_TRACKER_RECORD, one per line. No extension filter — `hooks/` scripts
# are typically extensionless, and the first draft's `*.sh`/`*.yml`/`*.yaml` filter silently skipped
# the whole directory's non-matching files. `.nv-*` is excluded: the non-vacuity harness's own
# established transient-artifact prefix (conformance/harness-adapter.sh's `.nv-` fixture discipline;
# .gitignore-matched) for the mutant/ctl COPIES it drops beside a check under test — since this file
# now carries a literal, DECLARED `KIT_TRACKER_RECORD=` (security M-1, close fix round 1), a byte-
# copy of it sitting in conformance/ under a `.nv-` name during its OWN mutation run is not a stray
# production setter, it is this scan seeing its own test scaffolding. security M-2 (close fix round
# 2): skip a `.nv-*` file ONLY when it is UNTRACKED — a committed `.nv-*` file is a real setter.
_tj_seam_record_setter_files() {
  for _tjs_d in $TJ_SEAM_RECORD_SCAN_DIRS; do
    [ -d "$_tjs_d" ] || continue
    find "$_tjs_d" -type f 2>/dev/null
  done | while IFS= read -r _tjs_f; do
    case "$(basename "$_tjs_f")" in
      .nv-*) git -C "$(dirname "$_tjs_f")" ls-files --error-unmatch -- "$(basename "$_tjs_f")" >/dev/null 2>&1 || continue ;;
    esac
    _tjs_txt=$(code_only "$_tjs_f" 2>/dev/null || true)
    _tj_text_sets_seam_record "$_tjs_txt" && printf '%s\n' "$_tjs_f"
  done
}

# tj_seam_record_scan -> 0 iff every SEAM_RECORD/KIT_TRACKER_RECORD setter in the tree is one of
# the sanctioned ones. HONEST CEILING (security seat, stated here and in THREAT-MODEL T9): this
# is DETECTION of these spellings — a text scan over shell/YAML source — never a proof that no
# OTHER spelling exists (a computed variable name, an indirect `eval "$var=$val"` with `$var`
# resolving to the name at runtime, or a spelling outside the scanned directories entirely).
tj_seam_record_scan() {
  _tjs_bad=0
  for _tjs_f in $(_tj_seam_record_setter_files); do
    case " $TJ_SEAM_RECORD_ALLOWED_SETTERS " in
      *" $_tjs_f "*) : ;;
      *) echo "FAIL: $_tjs_f assigns SEAM_RECORD or KIT_TRACKER_RECORD outside the sanctioned setters ($TJ_SEAM_RECORD_ALLOWED_SETTERS) — N-3 requires the trusted job be the ONLY setter, so a stray assignment is a planted-record attack surface"; _tjs_bad=1 ;;
    esac
  done
  return $_tjs_bad
}

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

# TRACKER-GATES-TRUSTED-WIRING (T1) — three shape legs on profiles/adopter-tracker-gates.yml's
# reader-states arg, its rc-aggregation across the three board gates, and the gates step's PR env.
# Text-presence, same honesty note as the fix-round-reviewer-3 legs above: this proves the shape is
# SPELLED into the file, not that the gates were exercised (T2's job is the latter).
# _t2_step_block <marker> <file> -> the block from the FIRST line containing <marker> up to (but
# excluding) the next step at the same indent (`^      - `, named or not — an unnamed `- uses:`/
# `- run:` step is a step boundary too), or to end-of-file if none follows. Today the gates step
# is the last one, so bounding at end-of-file and bounding at the next step agree; if a step is
# ever added after it, only the bounded form still stops at the right place — a plain `,$p` (or a
# caller's own `tail -1`) would silently start reading into that later step.
_t2_step_block() {
  _tsb_marker="$1"; _tsb_file="$2"
  _tsb_code=$(code_only "$_tsb_file")
  _tsb_start=$(printf '%s\n' "$_tsb_code" | grep -nF "$_tsb_marker" | head -1 | cut -d: -f1)
  [ -n "$_tsb_start" ] || return 1
  _tsb_after=$(printf '%s\n' "$_tsb_code" | tail -n "+$((_tsb_start + 1))")
  _tsb_rel_end=$(printf '%s\n' "$_tsb_after" | grep -n '^      - ' | head -1 | cut -d: -f1)
  if [ -n "$_tsb_rel_end" ]; then
    _tsb_end=$((_tsb_start + _tsb_rel_end - 1))
    printf '%s\n' "$_tsb_code" | sed -n "${_tsb_start},${_tsb_end}p"
  else
    printf '%s\n' "$_tsb_code" | tail -n "+$_tsb_start"
  fi
}

# _t2_run_body <marker> <file> -> the DEDENTED shell body of the step named by <marker>'s `run: |`
# block only (comments/env/id/if stripped) — the lines from the first `        run: |` line inside
# that step's block to the first line that is no longer indented >= 10 spaces. Used by the
# TRACKER-DRIFT-SCHEDULED-WIRING executed leg to run the shipped profile's own step bodies rather
# than a hand-typed copy.
_t2_run_body() {
  _trb_blk=$(_t2_step_block "$1" "$2") || return 1
  printf '%s\n' "$_trb_blk" | awk '
    /^        run: \|/ { inrun=1; next }
    inrun {
      if ($0 ~ /^          /) { print substr($0, 11) }
      else { exit }
    }
  '
}

_tj_wiring_legs() {
  _twl_f="$1"; _twl_st=0
  _twl_gates=$(_t2_step_block 'Run the tracker-bound board gates from base' "$_twl_f")
  # security whole-branch Low 1: scoped to the READER step's own invocation line — a whole-file grep
  # would pass if the full state list appeared ANYWHERE in the file, not necessarily on the
  # `sh scripts/tracker-read.sh` call itself.
  _twl_reader=$(_t2_step_block 'Run the trusted reader from base' "$_twl_f")

  if ! printf '%s\n' "$_twl_reader" | grep -qF 'sh scripts/tracker-read.sh' \
    || ! printf '%s\n' "$_twl_reader" | grep -F 'sh scripts/tracker-read.sh' | grep -qF '"$HEAD_SHA" in-progress in-review ready'; then
    echo "FAIL: $_twl_f's reader step's own tracker-read.sh invocation does not carry the full in-progress in-review ready state list"; _twl_st=1
  fi

  if ! { printf '%s\n' "$_twl_gates" | grep -qF '|| rc_bp=$?' \
      && printf '%s\n' "$_twl_gates" | grep -qF '|| rc_ls=$?' \
      && printf '%s\n' "$_twl_gates" | grep -qF '|| rc_bc=$?' \
      && printf '%s\n' "$_twl_gates" | grep -qF '[ "$rc_ls" = 0 ] && [ "$rc_bp" = 0 ] && [ "$rc_bc" = 0 ]'; }; then
    echo "FAIL: $_twl_f's gates step does not capture rc_bp, rc_ls, and rc_bc and fail the step on any of the three gates' rc"; _twl_st=1
  fi

  if ! printf '%s\n' "$_twl_gates" | grep -qF 'PR: ${{ github.event.pull_request.number }}'; then
    echo "FAIL: $_twl_f's gates step env does not set PR from the pull_request number"; _twl_st=1
  fi

  return $_twl_st
}

# TRACKER-GATES-TRUSTED-WIRING (T2) — the EXECUTED leg: run the two gate CLI lines EXTRACTED from
# the shipped profiles/adopter-tracker-gates.yml gates step against a throwaway fixture tree, and
# show they bind on a good tracker record and red on bad ones. T1's legs prove the shape is SPELLED
# into the file; this proves the shape RUNS. Never a hand-typed copy of the CLI: both lines are read
# out of the shipped YAML at run time so a future edit to either line reflows here automatically.

# _t2_digest <file> -> sha256 hex digest, the SAME tool order backlog-lib.sh's own pin check uses
# (sha256sum, falling back to shasum -a 256) — never a re-implementation, both sides must agree.
_t2_digest() {
  { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } < "$1" 2>/dev/null | awk '{print $1}'
}

# _t2_extract_gate_line <marker> <file> <listing-path> -> the ONE line of <file>'s gates step
# containing <marker>, comment-stripped, with the `rc_xx=0; ` setup prefix and the trailing
# `|| rc_xx=$?` capture stripped, and the literal `/tmp/tbg-changed.txt` replaced by <listing-path>
# (never a fixed /tmp path — the brief's own rule). Empty/missing output is a caller-visible FAIL,
# never a silent pass (leg 1's liveness check).
_t2_extract_gate_line() {
  _tgel_marker="$1"; _tgel_file="$2"; _tgel_listing="$3"
  _tgel_step=$(_t2_step_block 'Run the tracker-bound board gates from base' "$_tgel_file")
  _tgel_raw=$(printf '%s\n' "$_tgel_step" | grep -E '^[[:space:]]*rc_[a-z]*=0;' | grep -F "$_tgel_marker" | tail -1) || return 1
  [ -n "$_tgel_raw" ] || return 1
  _tgel_line=$(printf '%s\n' "$_tgel_raw" \
    | sed -e 's/^[[:space:]]*//' -e 's/^rc_[a-z]*=0;[[:space:]]*//' -e 's/[[:space:]]*|| rc_[a-z]*=\$?[[:space:]]*$//')
  printf '%s\n' "$_tgel_line" | sed "s#/tmp/tbg-changed.txt#$_tgel_listing#g"
}

# _t2_build_tree <root> -> populate a throwaway adopter tree at <root> with the fixture's CLAUDE.md
# + .kit/tracker.conf (conformance/fixtures/tbg-record-gates-bind/tracker-jira/, never modified) plus
# copies of every kit file the two gates dereference at runtime: backlog-presence.sh/
# backlog-current.sh/backlog-lib.sh (the shared parser), agent-boundary.sh + promotion-readiness.sh +
# union-lib.sh (gate_class's two classifier seams) + .claude/hooks/guard-core.sh + adapters/ (what
# those seams read to derive a change class), and scripts/tracker-conf.sh (backlog-lib.sh's own pin/
# backend cross-check). git-inits it (never this clone's own history) with a commit whose message
# ends in a Kit-Row trailer, and prints the resulting head sha.
_t2_build_tree() {
  _tbt_root="$1"
  mkdir -p "$_tbt_root/conformance" "$_tbt_root/.claude/hooks" "$_tbt_root/scripts" "$_tbt_root/.kit"
  cp "conformance/fixtures/tbg-record-gates-bind/tracker-jira/CLAUDE.md" "$_tbt_root/CLAUDE.md"
  cp "conformance/fixtures/tbg-record-gates-bind/tracker-jira/.kit/tracker.conf" "$_tbt_root/.kit/tracker.conf"
  for _tbt_f in backlog-presence.sh backlog-current.sh backlog-lib.sh agent-boundary.sh promotion-readiness.sh union-lib.sh; do
    cp "conformance/$_tbt_f" "$_tbt_root/conformance/$_tbt_f"
  done
  cp ".claude/hooks/guard-core.sh" "$_tbt_root/.claude/hooks/guard-core.sh"
  cp -R "adapters" "$_tbt_root/adapters"
  cp "scripts/tracker-conf.sh" "$_tbt_root/scripts/tracker-conf.sh"
  git -C "$_tbt_root" init -q
  git -C "$_tbt_root" -c user.email=t2@example.invalid -c user.name=t2 add -A >/dev/null
  git -C "$_tbt_root" -c user.email=t2@example.invalid -c user.name=t2 commit -q -m "$(printf 'T2 fixture seed\n\nKit-Row: AB-1\n')"
  git -C "$_tbt_root" rev-parse HEAD
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
  # ── TBG-TRUSTED-JOB: the S-1 pairing leg + N-3 SEAM_RECORD= setter scan ──────────────────────
  # Positive: the real fleet (this tree, as it stands) must pass — no job today pairs a tracker
  # secret with a head checkout, and no stray SEAM_RECORD= setter exists outside the sanctioned
  # ones (B6: the count is deliberately not stated here — it went stale each time the allowlist
  # grew). Load-bearing negative: the fixture at conformance/fixtures/trusted-job-pairing/bad.yml
  # pairs secrets.KIT_TRACKER_TOKEN with a PR-head checkout in the SAME job and must RED — proven by
  # TEMPORARILY pointing the fleet glob at it (never by asserting on the fixture path directly,
  # which would prove nothing about the scanner that walks the real fleet).
  # NOTE: `var=$(cmd)` where cmd fails ABORTS under `set -e` (a bare assignment IS a simple command,
  # unlike `$(cmd)` used inside an `if` condition) — so the capture is inside the `if`, not outside it.
  if _tj_pairing_out=$(tj_pairing_leg 2>&1); then
    echo "PASS: tj_pairing_leg — the real workflow fleet pairs no tracker secret with a head checkout"
  else
    echo "FAIL: tj_pairing_leg reds on the REAL fleet (should be clean):"; printf '%s\n' "$_tj_pairing_out"; st=1
  fi
  # the negative: run the SAME scanner logic over a fleet containing ONLY the bad fixture. Achieved
  # by overriding TJ_FLEET_GLOBS to the fixture path for this one call — the scanner code itself is
  # unmodified, so this proves the assertion inside it, not merely that the fixture exists.
  _tj_bad_fixture="conformance/fixtures/trusted-job-pairing/bad.yml"
  [ -f "$_tj_bad_fixture" ] || { echo "FAIL: $_tj_bad_fixture is missing — the pairing leg's load-bearing negative fixture"; st=1; }
  # CALL tj_pairing_leg ITSELF, with the fleet glob temporarily pointed at ONLY the bad fixture — not
  # a re-implementation of its internals. A re-implementation would prove the HELPERS work without
  # proving tj_pairing_leg actually calls them the way it must; this proves the real entry point reds.
  TJ_FLEET_GLOBS="$_tj_bad_fixture"
  if tj_pairing_leg >/dev/null 2>&1; then
    echo "FAIL: tj_pairing_leg's detector does not RED on its own negative fixture — a mutant that guts the assertion would pass unnoticed"; st=1
  else
    echo "PASS: tj_pairing_leg detects the negative fixture (secret+head-checkout paired)"
  fi
  TJ_FLEET_GLOBS=".github/workflows/*.yml profiles/*.yml profiles/*/ci.yml"
  # mutant: a job with the secret ALONE (no head checkout) must NOT trip the leg.
  _tj_secretonly=$(mktemp -d)/secretonly.yml
  printf 'jobs:\n  x:\n    steps:\n      - env:\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: echo ok\n' > "$_tj_secretonly"
  _tj_blk=$(_tj_job_block "$_tj_secretonly" x || true)
  _tj_block_has_tracker_secret "$_tj_secretonly" "$_tj_blk" || { echo "FAIL: mutant — a job carrying the tracker secret token must be DETECTED as such"; st=1; }
  _tj_block_has_head_checkout "$_tj_blk" && { echo "FAIL: mutant — a job with NO head-checkout reference must not be flagged as one"; st=1; }
  # mutant: a head checkout ALONE (no secret) must NOT trip the leg either — the leg is a PAIRING,
  # not a ban on either half alone (adopter-gates.yml legitimately checks out base only; a fork-safe
  # job may still reference head.sha for read-only metadata elsewhere in the fleet).
  _tj_headonly=$(dirname "$_tj_secretonly")/headonly.yml
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@x\n        with:\n          ref: ${{ github.event.pull_request.head.sha }}\n' > "$_tj_headonly"
  _tj_blk=$(_tj_job_block "$_tj_headonly" x || true)
  _tj_block_has_head_checkout "$_tj_blk" || { echo "FAIL: mutant — a job checking out head.sha must be DETECTED as a head checkout"; st=1; }
  _tj_block_has_tracker_secret "$_tj_headonly" "$_tj_blk" && { echo "FAIL: mutant — a job with no secret token must not be flagged as carrying one"; st=1; }
  rm -rf "$(dirname "$_tj_secretonly")" 2>/dev/null || true

  # ── FIX-ROUND B-1 EVASION CORPUS (2026-09-22 security seat, NO-GO) — every one of these MUST red
  # tj_pairing_leg through the REAL entry point (TJ_FLEET_GLOBS pointed at ONE fixture at a time),
  # not a re-implementation. p0 is the plain control (same shape the original negative fixture
  # used); p1-p12 are the seat's demonstrated evasions. A single row failing here is exactly the
  # non-vacuity gap the seat found: 12 of 13 passed GREEN on the first draft.
  _tj_evd=$(mktemp -d)
  printf 'jobs:\n  bad-job:\n    steps:\n      - uses: actions/checkout@x\n        with:\n          ref: ${{ github.event.pull_request.head.sha }}\n      - env:\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: ./build\n' > "$_tj_evd/p0-control.yml"
  printf 'jobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n        with:\n          ref: ${{ github.event.pull_request.head.sha }}\n      - env:\n          KIT_TRACKER_TOKEN: ${{ secrets.ATLASSIAN_API }}\n        run: ./build\n' > "$_tj_evd/p1-secret-renamed.yml"
  printf 'jobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n        with:\n          ref: ${{ github.head_ref }}\n          repository: ${{ github.event.pull_request.head.repo.full_name }}\n      - env:\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: ./build\n' > "$_tj_evd/p2-head-ref.yml"
  printf 'jobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n      - env:\n          HEAD_SHA: ${{ github.event.pull_request.head.sha }}\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: |\n          git fetch origin "$HEAD_SHA" && git checkout FETCH_HEAD\n          ./build\n' > "$_tj_evd/p3-fetch-head.yml"
  printf 'jobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n      - env:\n          HEAD_SHA: ${{ github.event.pull_request.head.sha }}\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: |\n          git fetch origin "$HEAD_SHA"\n          git checkout "$HEAD_SHA"\n          ./build\n' > "$_tj_evd/p4-checkout-var.yml"
  printf 'on:\n  pull_request_target:\nenv:\n  KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\njobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n        with:\n          ref: ${{ github.event.pull_request.head.sha }}\n      - run: ./build\n' > "$_tj_evd/p5-workflow-env.yml"
  printf 'jobs:\n  bad-job:   # trailing comment on the job key\n    steps:\n      - uses: actions/checkout@x\n        with:\n          ref: ${{ github.event.pull_request.head.sha }}\n      - env:\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: ./build\n' > "$_tj_evd/p6-job-comment.yml"
  printf 'jobs:\n    bad-job:\n        steps:\n            - uses: actions/checkout@x\n              with:\n                  ref: ${{ github.event.pull_request.head.sha }}\n            - env:\n                  KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n              run: ./build\n' > "$_tj_evd/p6b-indent4.yml"
  printf 'jobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n      - env:\n          GH_TOKEN: ${{ github.token }}\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: |\n          gh pr checkout ${{ github.event.pull_request.number }}\n          ./build\n' > "$_tj_evd/p7-gh-pr-checkout.yml"
  printf 'jobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n      - env:\n          HEAD_SHA: ${{ github.event.pull_request.head.sha }}\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: |\n          git fetch origin "$HEAD_SHA"\n          git show "$HEAD_SHA:build" > /tmp/b && chmod +x /tmp/b && /tmp/b\n' > "$_tj_evd/p8-git-show-exec.yml"
  printf 'jobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n        with:\n          ref: ${{ github.event.pull_request.merge_commit_sha }}\n      - env:\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: ./build\n' > "$_tj_evd/p9-merge-sha.yml"
  printf 'jobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n        with:\n          ref: ${{ github.event.pull_request.head.sha }}\n      - env:\n          ALL: ${{ toJSON(secrets) }}\n        run: ./build\n' > "$_tj_evd/p10-tojson.yml"
  printf 'jobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n        with:\n          ref: "${{ github.event.pull_request.head.sha }}"\n      - env:\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: ./build\n' > "$_tj_evd/p11-quoted-ref.yml"
  printf 'jobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n        with:\n          ref: ${{ github.event.pull_request.head.sha }}\n      - env:\n          JIRA_TOKEN: ${{ secrets.JIRA_TOKEN }}\n        run: ./build\n' > "$_tj_evd/p12-secret-alias-jira.yml"
  for _tj_ev in "$_tj_evd"/p*.yml; do
    TJ_FLEET_GLOBS="$_tj_ev"
    if tj_pairing_leg >/dev/null 2>&1; then
      echo "FAIL: tj_pairing_leg does NOT catch evasion fixture $(basename "$_tj_ev") — B-1 non-vacuity gap"; st=1
    else
      echo "PASS: tj_pairing_leg catches evasion fixture $(basename "$_tj_ev")"
    fi
  done
  TJ_FLEET_GLOBS=".github/workflows/*.yml profiles/*.yml profiles/*/ci.yml"
  rm -rf "$_tj_evd" 2>/dev/null || true

  # ── FIX-ROUND 2 H-C EVASION CORPUS (2026-09-23 security seat re-review) — 10 of 12 of these
  # passed GREEN before the taint-lite rules above existed. Same discipline as the p-corpus: call
  # tj_pairing_leg ITSELF through TJ_FLEET_GLOBS, one fixture at a time.
  _tj_evd2=$(mktemp -d)
  printf 'jobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n      - env:\n          SHA: ${{ github.event.pull_request.head.sha }}\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: |\n          git fetch origin "$SHA"\n          git checkout "$SHA"\n          ./build\n' > "$_tj_evd2/q1-env-indirect-sha.yml"
  printf 'env:\n  PR_SHA: ${{ github.event.pull_request.head.sha }}\njobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n        with:\n          ref: ${{ env.PR_SHA }}\n      - env:\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: ./build\n' > "$_tj_evd2/q2-ref-from-env.yml"
  printf 'jobs:\n  j:\n    strategy:\n      matrix:\n        target:\n          - ${{ github.event.pull_request.head.sha }}\n    steps:\n      - uses: actions/checkout@x\n        with:\n          ref: ${{ matrix.target }}\n      - env:\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: ./build\n' > "$_tj_evd2/q3-ref-from-matrix.yml"
  printf 'jobs:\n  j:\n    steps:\n      - id: pick\n        run: echo "r=${{ github.event.pull_request.head.sha }}" >> "$GITHUB_OUTPUT"\n      - uses: actions/checkout@x\n        with:\n          ref: ${{ steps.pick.outputs.r }}\n      - env:\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: ./build\n' > "$_tj_evd2/q4-ref-from-step-output.yml"
  printf "jobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n        with:\n          ref: \${{ github.event.pull_request.head.sha }}\n      - env:\n          T: \${{ secrets[format('KIT_{0}', 'TRACKER_TOKEN')] }}\n        run: ./build\n" > "$_tj_evd2/q5-secret-index-form.yml"
  printf 'jobs:\n  a:\n    outputs:\n      t: ${{ steps.s.outputs.t }}\n    steps:\n      - id: s\n        env:\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: echo "t=$(printf %%s "$KIT_TRACKER_TOKEN" | base64)" >> "$GITHUB_OUTPUT"\n  b:\n    needs: a\n    steps:\n      - uses: actions/checkout@x\n        with:\n          ref: ${{ github.event.pull_request.head.sha }}\n      - env:\n          T: ${{ needs.a.outputs.t }}\n        run: ./build\n' > "$_tj_evd2/q6-needs-outputs.yml"
  printf 'jobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n      - uses: ./.github/actions/prepare-pr-tree\n      - env:\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: ./build\n' > "$_tj_evd2/q7-local-composite-action.yml"
  printf 'jobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n        with:\n          repository: ${{ github.event.pull_request.head.repo.full_name }}\n      - env:\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: ./build\n' > "$_tj_evd2/q8-fork-repo-default-branch.yml"
  printf 'jobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n      - env:\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: |\n          echo "PR says: ${{ github.event.pull_request.body }}"\n          ./build\n' > "$_tj_evd2/q9-pr-body-in-run.yml"
  printf 'jobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n      - env:\n          HEAD_SHA: ${{ github.event.pull_request.head.sha }}\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: |\n          git fetch origin "$HEAD_SHA"\n          git -c advice.detachedHead=false checkout "$HEAD_SHA"\n          ./build\n' > "$_tj_evd2/q10-git-C-checkout.yml"
  printf 'jobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n      - env:\n          HEAD_SHA: ${{ github.event.pull_request.head.sha }}\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: |\n          curl -fsSL "https://raw.githubusercontent.com/${{ github.repository }}/$HEAD_SHA/build" -o /tmp/b\n          chmod +x /tmp/b && /tmp/b\n' > "$_tj_evd2/q11-curl-raw-exec.yml"
  for _tj_ev2 in "$_tj_evd2"/q*.yml; do
    TJ_FLEET_GLOBS="$_tj_ev2"
    if tj_pairing_leg >/dev/null 2>&1; then
      echo "FAIL: tj_pairing_leg does NOT catch evasion fixture $(basename "$_tj_ev2") — H-C non-vacuity gap"; st=1
    else
      echo "PASS: tj_pairing_leg catches evasion fixture $(basename "$_tj_ev2")"
    fi
  done
  TJ_FLEET_GLOBS=".github/workflows/*.yml profiles/*.yml profiles/*/ci.yml"
  rm -rf "$_tj_evd2" 2>/dev/null || true

  # ── FIX-ROUND 3 C-3 EVASION CORPUS (2026-09-23, third security-seat re-review). r5 is a POSITIVE
  # control mirroring OUR OWN trusted job's legitimate shape (base checkout, an authenticated
  # `git fetch` — never a checkout — of the head, secret in a LATER step) and MUST stay green: a
  # rule broad enough to catch r1-r4 must not also catch the pattern the trusted job itself uses.
  _tj_evd3=$(mktemp -d)
  printf 'jobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n      - env:\n          SHA: ${{ github.event.pull_request.head.sha }}\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: |\n          git fetch origin "$SHA"\n          git merge --no-edit "$SHA"\n          ./build\n' > "$_tj_evd3/r1-git-merge-head.yml"
  printf 'jobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n      - env:\n          GH_TOKEN: ${{ github.token }}\n          N: ${{ github.event.pull_request.number }}\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: |\n          gh pr diff "$N" | git apply\n          ./build\n' > "$_tj_evd3/r2-pr-diff-apply.yml"
  printf 'jobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n      - env:\n          SHA: ${{ github.event.pull_request.head.sha }}\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: |\n          git fetch origin "$SHA"\n          git restore --source="$SHA" -- .\n          ./build\n' > "$_tj_evd3/r3-git-restore-source.yml"
  printf 'jobs:\n  j:\n    steps:\n      - uses: actions/checkout@x\n        with:\n          ref: >-\n            ${{ github.event.pull_request.head.sha }}\n      - env:\n          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}\n        run: ./build\n' > "$_tj_evd3/r4-folded-ref.yml"
  # QUOTED heredoc (never printf): the fixture's own inner `printf %s x-access-token:%s` reads as a
  # bare, argument-less `%s` to an OUTER printf's format string (SC2183) — a quoted `<<'YAML'` is
  # literal (no `$`/`%` interpretation), so the fixture content is exact and shellcheck sees no
  # format string at all.
  cat > "$_tj_evd3/r5-trusted-job-shape-control.yml" <<'YAML'
jobs:
  j:
    steps:
      - uses: actions/checkout@x
        with:
          ref: ${{ github.event.pull_request.base.sha }}
      - env:
          GH_TOKEN: ${{ github.token }}
          HEAD_SHA: ${{ github.event.pull_request.head.sha }}
        run: |
          AUTH=$(printf %s x-access-token:%s | base64)
          git -c http.extraheader="AUTHORIZATION: basic $AUTH" fetch --no-tags --no-recurse-submodules origin "$HEAD_SHA"
      - env:
          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}
        run: ./reader
YAML
  for _tj_ev3 in "$_tj_evd3"/r1*.yml "$_tj_evd3"/r2*.yml "$_tj_evd3"/r3*.yml "$_tj_evd3"/r4*.yml; do
    TJ_FLEET_GLOBS="$_tj_ev3"
    if tj_pairing_leg >/dev/null 2>&1; then
      echo "FAIL: tj_pairing_leg does NOT catch evasion fixture $(basename "$_tj_ev3") — C-3 non-vacuity gap"; st=1
    else
      echo "PASS: tj_pairing_leg catches evasion fixture $(basename "$_tj_ev3")"
    fi
  done
  TJ_FLEET_GLOBS="$_tj_evd3/r5-trusted-job-shape-control.yml"
  if tj_pairing_leg >/dev/null 2>&1; then
    echo "PASS: tj_pairing_leg does NOT false-positive on the trusted job's own legitimate shape (r5 control)"
  else
    echo "FAIL: tj_pairing_leg false-positives on the trusted job's own legitimate fetch-then-secret shape (r5 control) — the extended taint rules are over-broad"; st=1
  fi
  TJ_FLEET_GLOBS=".github/workflows/*.yml profiles/*.yml profiles/*/ci.yml"
  rm -rf "$_tj_evd3" 2>/dev/null || true

  if _tj_seam_out=$(tj_seam_record_scan 2>&1); then
    echo "PASS: tj_seam_record_scan — no stray SEAM_RECORD setter outside the sanctioned ones"
  else
    echo "FAIL: tj_seam_record_scan reds on the REAL tree (should be clean):"; printf '%s\n' "$_tj_seam_out"; st=1
  fi
  # negative: a THIRD setter planted in a scanned dir must be caught. Exercised against the detector
  # function directly (same logic tj_seam_record_scan calls), scoped to a temp fixture so it never
  # touches the real tree.
  # CALL tj_seam_record_scan ITSELF against a scan-dir temporarily pointed at a fixture directory
  # carrying a planted stray setter — not a re-implementation of its internals. Built via %s
  # substitution, NOT a literal 'SEAM_RECORD=' in THIS file's own source (this file is itself inside
  # the N-3 scan's scope, and a literal occurrence here would trip the very scan it is testing).
  _tj_strayd=$(mktemp -d)
  printf '#!/bin/sh\n%s="/tmp/planted.json"\n' SEAM_RECORD > "$_tj_strayd/stray.sh"
  TJ_SEAM_RECORD_SCAN_DIRS="$_tj_strayd"
  if tj_seam_record_scan >/dev/null 2>&1; then
    echo "FAIL: tj_seam_record_scan does not RED on a planted stray SEAM_RECORD setter — a mutant that guts the allowlist check would pass unnoticed"; st=1
  else
    echo "PASS: tj_seam_record_scan detects a planted stray setter outside the allowlist"
  fi
  TJ_SEAM_RECORD_SCAN_DIRS="conformance scripts hooks profiles .github"
  rm -rf "$_tj_strayd" 2>/dev/null || true

  # ── security M-2 (close fix round 2): the `.nv-*` exclusion must skip only UNTRACKED copies — a
  # TRACKED `.nv-*` file (committed via `git add -f`) is a real production setter wearing the
  # fixture-prefix disguise, and must still be flagged. Exercised in a throwaway git repo (never
  # this clone's own history) so "tracked" has a real git index to test against.
  _tj_nvd=$(mktemp -d)
  (
    cd "$_tj_nvd" \
      && git init -q \
      && git config user.email test@example.com \
      && git config user.name test \
      && printf '#!/bin/sh\n%s="/tmp/planted.json"\n' SEAM_RECORD > .nv-evil.sh \
      && git add -f .nv-evil.sh \
      && git commit -q -m tracked \
      && printf '#!/bin/sh\n%s="/tmp/planted.json"\n' SEAM_RECORD > .nv-untracked.sh
  ) >/dev/null 2>&1
  TJ_SEAM_RECORD_SCAN_DIRS="$_tj_nvd"
  if tj_seam_record_scan >/dev/null 2>&1; then
    echo "FAIL: tj_seam_record_scan does not RED on a TRACKED .nv-* setter — the fixture-prefix exclusion hides a committed file (M-2)"; st=1
  else
    echo "PASS: tj_seam_record_scan detects a TRACKED .nv-* setter (M-2)"
  fi
  (cd "$_tj_nvd" && rm -f .nv-evil.sh && git rm -q --cached .nv-evil.sh) >/dev/null 2>&1
  if tj_seam_record_scan >/dev/null 2>&1; then
    echo "PASS: tj_seam_record_scan does not flag an UNTRACKED .nv-* setter (M-2)"
  else
    echo "FAIL: tj_seam_record_scan flags an UNTRACKED .nv-* setter — the non-vacuity harness's own mutant/ctl copies would false-positive (M-2)"; st=1
  fi
  TJ_SEAM_RECORD_SCAN_DIRS="conformance scripts hooks profiles .github"
  rm -rf "$_tj_nvd" 2>/dev/null || true

  # ── FIX ROUND 2 M-A: two more setter spellings the scan missed, and the non-regression check on
  # the `${VAR:-}` read carve-out (must stay unflagged — it very nearly regressed while fixing this).
  # BUILT VIA %s SUBSTITUTION, not a literal 'KIT_TRACKER_RECORD:=' / 'read KIT_TRACKER_RECORD' in
  # THIS file's own source — this file is itself inside the N-3 scan's scope, and a literal
  # occurrence here would trip the very scan it is testing (measured: it did, first cut of this fix).
  _tj_ma_default=$(printf ': "${%s:=/tmp/planted.json}"' KIT_TRACKER_RECORD)
  if _tj_text_sets_seam_record "$_tj_ma_default"; then
    echo "PASS: tj_seam_record_scan detects a \${NAME:=...} default-assign (M-A)"
  else
    echo "FAIL: tj_seam_record_scan misses a \${NAME:=...} default-assign — that operator ASSIGNS, unlike :-/:+  which only read (M-A)"; st=1
  fi
  _tj_ma_rverb=$(printf '%s' r)ead
  _tj_ma_name=KIT_TRACKER_RECORD
  _tj_ma_readss="$_tj_ma_rverb $_tj_ma_name < /tmp/p"
  if _tj_text_sets_seam_record "$_tj_ma_readss"; then
    echo "PASS: tj_seam_record_scan detects a single-space 'read NAME' (M-A)"
  else
    echo "FAIL: tj_seam_record_scan misses a single-space 'read NAME' — no non-word delimiter separates 'read ' from NAME, and the original regex required one (M-A)"; st=1
  fi
  if _tj_text_sets_seam_record 'x="${SEAM_RECORD:-}"; y="${KIT_TRACKER_RECORD:-none}"; [ -f "$SEAM_RECORD" ] && echo yes'; then
    echo "FAIL: tj_seam_record_scan REGRESSED on the \${VAR:-}/\${VAR:-default} READ carve-out — this must stay unflagged (non-regression check)"; st=1
  else
    echo "PASS: tj_seam_record_scan still does not false-positive on \${VAR:-}/\${VAR:-default} reads (non-regression)"
  fi

  # positive: the two sanctioned setters themselves must NOT be flagged (allowlist exact-match, not
  # substring — a path like conformance/loop-state.sh.bak must not sneak through).
  case " $TJ_SEAM_RECORD_ALLOWED_SETTERS " in
    *" conformance/loop-state.sh "*) : ;;
    *) echo "FAIL: mutant — conformance/loop-state.sh must be in the sanctioned-setter allowlist"; st=1 ;;
  esac
  case " $TJ_SEAM_RECORD_ALLOWED_SETTERS " in
    *" conformance/loop-state.sh.bak "*) echo "FAIL: mutant — the allowlist match must be EXACT, not a substring/prefix"; st=1 ;;
    *) : ;;
  esac
  # ── artifact-gate CI fix: incept installs profiles/adopter-tracker-gates.yml TO
  # .github/workflows/adopter-tracker-gates.yml (cp_kit_replace) — the SAME trusted job at its
  # INSTALLED location on every incepted/adopter tree. Proven end-to-end (not just an allowlist
  # membership check): a fixture file AT that installed path, carrying the real SEAM_RECORD
  # assignment line, must NOT be flagged by tj_seam_record_scan.
  case " $TJ_SEAM_RECORD_ALLOWED_SETTERS " in
    *" .github/workflows/adopter-tracker-gates.yml "*) : ;;
    *) echo "FAIL: mutant — .github/workflows/adopter-tracker-gates.yml (the INSTALLED path) must be in the sanctioned-setter allowlist, or every incepted/adopter tree reds artifact-gate"; st=1 ;;
  esac
  # The scanner walks DIRS by NAME relative to cwd, so exercising the REAL installed path means
  # building it under a temp root, cd-ing there, and scanning — the allowlist compares the exact
  # relative path ".github/workflows/adopter-tracker-gates.yml", not a basename.
  _tj_instroot=$(mktemp -d)
  mkdir -p "$_tj_instroot/.github/workflows"
  cp profiles/adopter-tracker-gates.yml "$_tj_instroot/.github/workflows/adopter-tracker-gates.yml"
  if (cd "$_tj_instroot" && TJ_SEAM_RECORD_SCAN_DIRS=".github" tj_seam_record_scan) >/dev/null 2>&1; then
    echo "PASS: tj_seam_record_scan does NOT flag .github/workflows/adopter-tracker-gates.yml at its installed path (artifact-gate CI fix)"
  else
    echo "FAIL: tj_seam_record_scan still flags .github/workflows/adopter-tracker-gates.yml at its installed path — every incepted/adopter tree would red artifact-gate"; st=1
  fi
  rm -rf "$_tj_instroot" 2>/dev/null || true
  TJ_SEAM_RECORD_SCAN_DIRS="conformance scripts hooks profiles .github"

  # ── B6 (security F-3, quality F7): the ALLOWLIST admits whole FILES — it says nothing about how
  # many setter LINES sit inside one. A second setter smuggled into an already-allowlisted file is
  # invisible to tj_seam_record_scan (file-membership only), so this pins the per-file SHAPE
  # directly: exactly one sanctioned SEAM_RECORD=/KIT_TRACKER_RECORD= setter line in the file's
  # PRODUCTION code in each of the two gates, and NONE in the reader (N-3's rule is "the trusted job
  # is the ONLY setter"). WB-FIX-2 item 2: all three files carry production dispatch AFTER their
  # selftest function (backlog-current.sh's --head arm, backlog-presence.sh's tail,
  # scripts/tracker-read.sh's tail) — a scan that stops at the marker was blind to that tail.
  # ⚠️ MEASURED (WB-FIX-2, not the brief's own simpler first draft): "the marker function's own body"
  # is not a safe boundary on its own — all three files also carry a CHAIN of "selftest-only helpers
  # (defined AFTER the selftest() marker on purpose)" (each file's own ORACLE-region comment) between
  # the marker and the real dispatch tail, and one of them (backlog-presence.sh's `t8h_run()`) carries
  # a real `KIT_TRACKER_RECORD="$t8_rec1"` env-prefix to exercise the CLI under test — a legitimate
  # TEST fixture, not a production setter. A "walk the chain of functions after the marker" attempt
  # was ALSO measured fragile: the chain in backlog-current.sh breaks on a same-line function (`{
  # printf …; }`, `_claude_md`) and a commented opener (`br_expect_rc() { # <want-rc> <label>`) that
  # a naive "next line must open another function" walk cannot see past, silently landing on the
  # WRONG boundary (still gets 1/1/0 today only because no setter happens to live in the falsely
  # "production" span it leaves in) — not something to ship as the general fix.
  # The rule: a line counts as PRODUCTION only if it is NOT inside a function whose OWN definition
  # starts at or after the marker line — B6/post-marker-reach below CHECKS that exclusion instead of
  # assuming it, by confirming no post-marker function name is itself reachable from production.
  # Every real, top-level dispatch line (the CLI's
  # bare `case` tail in all three files is never itself wrapped in a function) is counted regardless
  # of its position; every function — single-line or multi-line, comment-tailed opener or not — that
  # is DEFINED at/after the marker is excluded wholesale, chain or no chain, gap or no gap. This is a
  # single linear pass tracking function open/close by column-0 brace, exactly the same brace
  # discipline this file elsewhere assumes of these three files (checked, not assumed: the marker's
  # own closing `}` was independently confirmed to be a real, well-formed function close in all
  # three — see the WB-FIX-2 note in the fix log).
  # _tj_setter_count_before_marker reuses _tj_text_sets_seam_record (same detector
  # tj_seam_record_scan calls) per line, over the file's CODE-ONLY, NON-POST-MARKER-FUNCTION text.
  _tj_setter_count_before_marker() {
    _tjcbm_tmp=$(mktemp) || _tjcbm_tmp=""
    if [ -z "$_tjcbm_tmp" ]; then
      printf '%s' -1
      return
    fi
    _tjcbm_start=$(grep -n "^${2}() {" "$1" | head -1 | cut -d: -f1)
    [ -n "$_tjcbm_start" ] || _tjcbm_start=999999999
    # Prefilter: the detector can only fire on a line containing one of these two names literally.
    awk -v mstart="$_tjcbm_start" '
      function is_opener(line) { return (line ~ /^[A-Za-z_][A-Za-z0-9_]*\(\) \{/) }
      function is_oneliner(line) { return (line ~ /^[A-Za-z_][A-Za-z0-9_]*\(\) \{.*\}/) }
      {
        if (infunc) {
          if (!(fstart >= mstart)) print
          if ($0 ~ /^}/) infunc = 0
          next
        }
        if (is_opener($0)) {
          if (is_oneliner($0)) { if (!(NR >= mstart)) print; next }
          infunc = 1; fstart = NR
          if (!(fstart >= mstart)) print
          next
        }
        print
      }
    ' "$1" | grep -v '^[[:space:]]*#' | grep -e 'SEAM_RECORD' -e 'KIT_TRACKER_RECORD' > "$_tjcbm_tmp" || true
    _tjcbm_n=0
    while IFS= read -r _tjcbm_line; do
      _tj_text_sets_seam_record "$_tjcbm_line" && _tjcbm_n=$((_tjcbm_n + 1))
    done < "$_tjcbm_tmp"
    rm -f "$_tjcbm_tmp"
    printf '%s' "$_tjcbm_n"
  }
  # B6/post-marker-reach (M1): names of functions (this file's own opener shape, `name() {`, plus the
  # `name () {` spelling) whose OWN definition starts STRICTLY AFTER the marker line — the marker
  # function itself is not a "post-marker helper", it is the honest, expected top-level dispatch call.
  _tj_post_marker_names() {
    _tjpm_mstart=$(grep -n "^${2}() {" "$1" | head -1 | cut -d: -f1)
    [ -n "$_tjpm_mstart" ] || _tjpm_mstart=999999999
    awk -v mstart="$_tjpm_mstart" '
      function is_opener(line) { return (line ~ /^[A-Za-z_][A-Za-z0-9_]*\(\) \{/ || line ~ /^[A-Za-z_][A-Za-z0-9_]* \(\) \{/) }
      is_opener($0) && NR > mstart { name = $0; sub(/[ (].*/, "", name); print name }
    ' "$1"
  }
  # B6/post-marker-reach (M1): the exact "pre-marker lines + kept top-level tail" region
  # _tj_setter_count_before_marker scans, comment lines stripped, WITHOUT its final SEAM_RECORD/
  # KIT_TRACKER_RECORD filter — the honest-tree assumption's proof surface: nothing counted as
  # production may name, as a whole word, a function the tree just declared post-marker/test-only.
  _tj_counted_region() {
    _tjcr_mstart=$(grep -n "^${2}() {" "$1" | head -1 | cut -d: -f1)
    [ -n "$_tjcr_mstart" ] || _tjcr_mstart=999999999
    awk -v mstart="$_tjcr_mstart" '
      function is_opener(line) { return (line ~ /^[A-Za-z_][A-Za-z0-9_]*\(\) \{/) }
      function is_oneliner(line) { return (line ~ /^[A-Za-z_][A-Za-z0-9_]*\(\) \{.*\}/) }
      {
        if (infunc) {
          if (!(fstart >= mstart)) print
          if ($0 ~ /^}/) infunc = 0
          next
        }
        if (is_opener($0)) {
          if (is_oneliner($0)) { if (!(NR >= mstart)) print; next }
          infunc = 1; fstart = NR
          if (!(fstart >= mstart)) print
          next
        }
        print
      }
    ' "$1" | grep -v '^[[:space:]]*#'
  }
  # B6/post-marker-reach (M1): FAIL if any post-marker function name is itself reachable (as a whole
  # word) from the counted production region — the honest-tree assumption, CHECKED rather than assumed.
  _tj_post_marker_reach() {
    _tjpr_hit=""
    for _tjpr_name in $(_tj_post_marker_names "$1" "$2"); do
      if printf '%s\n' "$3" | grep -qw "$_tjpr_name"; then _tjpr_hit=$_tjpr_name; break; fi
    done
    printf '%s' "$_tjpr_hit"
  }
  # scripts/promotion-verify.sh has no selftest FUNCTION (its selftest lives in
  # conformance/promotion-verify-wired.sh), so marker `none` names no function -> the whole file is
  # counted for setters and post-marker-reach is vacuously clean; the pin is the COUNT (1). Note:
  # hooks/pre-push is NOT added here — its selftest is a top-level `if` block, not a function, so B6
  # cannot delimit it; a known residual, not attempted.
  for _tj_shf in "conformance/backlog-presence.sh selftest 1" "conformance/backlog-current.sh selftest 1" "scripts/tracker-read.sh _tr_selftest 0" "conformance/proportional-gate-wired.sh selftest 0" "conformance/board-drift.sh selftest 0" "scripts/promotion-verify.sh none 1"; do
    # shellcheck disable=SC2086 # deliberate word-split: "<file> <marker> <want>" into three fields
    set -- $_tj_shf
    _tj_shfile=$1; _tj_shmarker=$2; _tj_shwant=$3
    _tj_shgot=$(_tj_setter_count_before_marker "$_tj_shfile" "$_tj_shmarker")
    if [ "$_tj_shgot" -eq "$_tj_shwant" ]; then
      echo "PASS: B6/per-file-shape: $_tj_shfile carries exactly $_tj_shwant sanctioned setter line(s) above $_tj_shmarker()"
    else
      echo "FAIL: B6/per-file-shape: $_tj_shfile wanted $_tj_shwant setter line(s) above $_tj_shmarker(), got $_tj_shgot"; st=1
    fi
    _tj_shregion=$(_tj_counted_region "$_tj_shfile" "$_tj_shmarker")
    _tj_shhit=$(_tj_post_marker_reach "$_tj_shfile" "$_tj_shmarker" "$_tj_shregion")
    if [ -z "$_tj_shhit" ]; then
      echo "PASS: B6/post-marker-reach: $_tj_shfile production code names no post-marker function"
    else
      echo "FAIL: B6/post-marker-reach: $_tj_shfile production code references post-marker function $_tj_shhit"; st=1
    fi
  done
  # RED anchor (B6/post-marker-reach, M1): the setter-count scan above excludes a post-marker
  # helper's OWN body wholesale, so a helper that IS called from real production (the --head arm)
  # smuggles a setter invisible to every leg above it — its body carries no literal SEAM_RECORD text
  # at the CALL site, so a grep for the assignment text alone would never see it either. Plant such a
  # helper (named `_smug`) in a scratch copy of backlog-current.sh, called from the real --head arm,
  # and require post-marker-reach to name it. Built via %s substitution, NOT a literal setter
  # assignment in THIS file's own source (same N-3-scope reason as the anchor below).
  _tj_reach_def=$(printf '_smug() { %s="${4:-}"; }' SEAM_RECORD)
  _tj_reach_call='_smug "$@"'
  _tj_reach_anchor='_BC_HEAD="$2"'
  _tj_reach_copy=$(mktemp)
  _tj_reach_line=$(grep -Fn "$_tj_reach_anchor" conformance/backlog-current.sh | head -1 | cut -d: -f1)
  awk -v n="$_tj_reach_line" -v def="$_tj_reach_def" -v call="$_tj_reach_call" \
    'NR==n{print; print def; print call; next} {print}' conformance/backlog-current.sh > "$_tj_reach_copy"
  if cmp -s "$_tj_reach_copy" conformance/backlog-current.sh; then
    echo "FAIL: B6/post-marker-reach-red setup — the planted copy did not differ from its source"; st=1
  fi
  _tj_reach_region=$(_tj_counted_region "$_tj_reach_copy" selftest)
  _tj_reach_hit=$(_tj_post_marker_reach "$_tj_reach_copy" selftest "$_tj_reach_region")
  if [ "$_tj_reach_hit" = "_smug" ]; then
    echo "PASS: B6/post-marker-reach-red: a post-marker helper called from the real --head arm (_smug) is named by the reach pin (the anchor a mutant that guts it must red)"
  else
    echo "FAIL: B6/post-marker-reach-red: wanted _smug named as a reachable post-marker function, got '$_tj_reach_hit'"; st=1
  fi
  rm -f "$_tj_reach_copy"
  # RED anchor: a scratch copy with a SECOND production setter planted above the marker must count
  # 2, not 1 — the shape a mutant that guts this leg (or a stray second setter) must red. Built via
  # %s substitution, NOT a literal setter assignment in THIS file's own source (this file is itself
  # inside the N-3 scan's scope — see the note above _tj_seam_record_scan).
  _tj_b6_pat=$(printf '%s="${%s:-}"' SEAM_RECORD KIT_TRACKER_RECORD)
  _tj_b6_copy=$(mktemp)
  _tj_b6_line=$(grep -Fn "$_tj_b6_pat" conformance/backlog-presence.sh | head -1 | cut -d: -f1)
  awk -v n="$_tj_b6_line" -v extra="$_tj_b6_pat" 'NR==n{print; print extra; next} {print}' conformance/backlog-presence.sh > "$_tj_b6_copy"
  if cmp -s "$_tj_b6_copy" conformance/backlog-presence.sh; then
    echo "FAIL: B6/per-file-shape-red setup — the planted copy did not differ from its source"; st=1
  fi
  _tj_b6_got=$(_tj_setter_count_before_marker "$_tj_b6_copy" selftest)
  if [ "$_tj_b6_got" -eq 2 ]; then
    echo "PASS: B6/per-file-shape-red: a scratch copy with a SECOND production setter counts 2, not 1 (the anchor a mutant must red)"
  else
    echo "FAIL: B6/per-file-shape-red: wanted 2 after planting a second setter, got $_tj_b6_got"; st=1
  fi
  rm -f "$_tj_b6_copy"

  # RED anchor (security M-1, close fix round 1): the N-3 setter in THIS file must be DECLARED, not
  # merely exempted wholesale — plant a literal `KIT_TRACKER_RECORD=x` line ABOVE this file's own
  # `selftest() {` marker (real, top-level production text) in a scratch copy; B6 must count it as 1,
  # not 0, proving this file's shipped production code is genuinely held to zero setters above the
  # marker rather than the allowlist entry silently covering everything in the file.
  _tj_m1_copy=$(mktemp)
  { printf 'KIT_TRACKER_RECORD=x\n'; cat conformance/proportional-gate-wired.sh; } > "$_tj_m1_copy"
  if cmp -s "$_tj_m1_copy" conformance/proportional-gate-wired.sh; then
    echo "FAIL: security-M1-red setup — the planted copy did not differ from its source"; st=1
  fi
  _tj_m1_got=$(_tj_setter_count_before_marker "$_tj_m1_copy" selftest)
  if [ "$_tj_m1_got" -eq 1 ]; then
    echo "PASS: security-M1-red: a setter planted ABOVE proportional-gate-wired.sh's own selftest() marker counts 1, not 0 (red)"
  else
    echo "FAIL: security-M1-red: wanted 1 after planting a setter above the marker, got $_tj_m1_got"; st=1
  fi
  rm -f "$_tj_m1_copy"

  # RED anchor 2 (WB-FIX-2 item 2, mutant M7b): the OLD before-marker-only scan was blind to
  # anything after the selftest's closing brace, so a setter smuggled into the POST-selftest
  # dispatch tail (the real `--head` arm every reader/gate carries) was invisible. Plant one there
  # in a scratch copy of backlog-current.sh and require the count to reach 2. Built via %s
  # substitution, not a literal setter assignment in THIS file's own source (same N-3-scope reason
  # as the anchor above).
  _tj_m7b_pat=$(printf '%s="${%s:-}"' SEAM_RECORD 4)
  _tj_m7b_anchor='_BC_HEAD="$2"'
  _tj_m7b_copy=$(mktemp)
  _tj_m7b_line=$(grep -Fn "$_tj_m7b_anchor" conformance/backlog-current.sh | head -1 | cut -d: -f1)
  awk -v n="$_tj_m7b_line" -v extra="$_tj_m7b_pat" 'NR==n{print; print extra; next} {print}' conformance/backlog-current.sh > "$_tj_m7b_copy"
  if cmp -s "$_tj_m7b_copy" conformance/backlog-current.sh; then
    echo "FAIL: B6/post-marker-red setup — the planted copy did not differ from its source"; st=1
  fi
  _tj_m7b_got=$(_tj_setter_count_before_marker "$_tj_m7b_copy" selftest)
  if [ "$_tj_m7b_got" -eq 2 ]; then
    echo "PASS: B6/post-marker-red (M7b): a setter planted in the POST-selftest dispatch tail (the real --head arm) counts 2, not 1 (the anchor a before-marker-only scan could never see)"
  else
    echo "FAIL: B6/post-marker-red (M7b): wanted 2 after planting a setter in the post-selftest dispatch tail, got $_tj_m7b_got"; st=1
  fi
  rm -f "$_tj_m7b_copy"

  # RED anchor twins (M2): M7b above only exercised backlog-current.sh's own dispatch tail — the
  # SAME "before-marker-only would be blind" gap exists, unproven, in the other two files' tails.
  # Twin 1: backlog-presence.sh's real --head arm (after its _hd=$2 positional read).
  _tj_m7bp_pat=$(printf '%s="${%s:-}"' SEAM_RECORD 4)
  _tj_m7bp_anchor='_hd=$2'
  _tj_m7bp_copy=$(mktemp)
  _tj_m7bp_line=$(grep -Fn "$_tj_m7bp_anchor" conformance/backlog-presence.sh | head -1 | cut -d: -f1)
  awk -v n="$_tj_m7bp_line" -v extra="$_tj_m7bp_pat" 'NR==n{print; print extra; next} {print}' conformance/backlog-presence.sh > "$_tj_m7bp_copy"
  if cmp -s "$_tj_m7bp_copy" conformance/backlog-presence.sh; then
    echo "FAIL: B6/post-marker-red-twin1 setup — the planted copy did not differ from its source"; st=1
  fi
  _tj_m7bp_got=$(_tj_setter_count_before_marker "$_tj_m7bp_copy" selftest)
  if [ "$_tj_m7bp_got" -eq 2 ]; then
    echo "PASS: B6/post-marker-red-twin1 (backlog-presence.sh): a setter planted in the POST-selftest dispatch tail (the real --head arm) counts 2, not 1"
  else
    echo "FAIL: B6/post-marker-red-twin1 (backlog-presence.sh): wanted 2 after planting a setter in the post-selftest dispatch tail, got $_tj_m7bp_got"; st=1
  fi
  rm -f "$_tj_m7bp_copy"
  # Twin 2: scripts/tracker-read.sh's top-level `*)` arm (its only dispatch to tr_read).
  _tj_m7bt_pat=$(printf '%s="${%s:-}"' SEAM_RECORD 5)
  _tj_m7bt_anchor='tr_read "$@"'
  _tj_m7bt_copy=$(mktemp)
  _tj_m7bt_line=$(grep -Fn "$_tj_m7bt_anchor" scripts/tracker-read.sh | head -1 | cut -d: -f1)
  awk -v n="$_tj_m7bt_line" -v extra="$_tj_m7bt_pat" 'NR==n{print extra; print; next} {print}' scripts/tracker-read.sh > "$_tj_m7bt_copy"
  if cmp -s "$_tj_m7bt_copy" scripts/tracker-read.sh; then
    echo "FAIL: B6/post-marker-red-twin2 setup — the planted copy did not differ from its source"; st=1
  fi
  _tj_m7bt_got=$(_tj_setter_count_before_marker "$_tj_m7bt_copy" _tr_selftest)
  if [ "$_tj_m7bt_got" -eq 1 ]; then
    echo "PASS: B6/post-marker-red-twin2 (scripts/tracker-read.sh): a setter planted in the top-level dispatch arm counts 1, not 0"
  else
    echo "FAIL: B6/post-marker-red-twin2 (scripts/tracker-read.sh): wanted 1 after planting a setter in the top-level dispatch arm, got $_tj_m7bt_got"; st=1
  fi
  rm -f "$_tj_m7bt_copy"

  # ── fix-round reviewer-3: three SHAPE legs on the trusted-job workflow text itself. Text-presence
  # locks, honestly so — they pin that the documented behaviour is SPELLED into the file, not a
  # mutation-tested proof of runtime behaviour (that proof is the R1b dispatch job itself, exercised
  # separately, not by this script). A gutted spelling reds here even though nothing on GitHub ran.
  _tj_atg="profiles/adopter-tracker-gates.yml"
  if [ -f "$_tj_atg" ]; then
    # R1a: the skip-on-md step names both the absent-conf and backend=md exits.
    if code_only "$_tj_atg" | grep -qF 'skip=true' && code_only "$_tj_atg" | grep -qF 'backend" = "md"'; then
      echo "PASS: $_tj_atg names the skip-on-md shape (R1a)"
    else
      echo "FAIL: $_tj_atg does not spell out the skip-on-md shape (R1a) — a gutted resolve step would silently run the reader on every backend"; st=1
    fi
    # M-5: a malformed (present but invalid) conf must ERROR, never silently join the skip path.
    if code_only "$_tj_atg" | grep -qF '::error title=tracker-board-gates: malformed .kit/tracker.conf'; then
      echo "PASS: $_tj_atg errors on a malformed (present, invalid) conf rather than skipping (M-5)"
    else
      echo "FAIL: $_tj_atg has no distinct error path for a malformed conf — M-5 requires a present-but-invalid conf to ERROR, never silently skip"; st=1
    fi
    # H-2(i): the reader head-arg capability is PROBED live, never assumed from a hardcoded string,
    # and its absence is a hard failure (no silent degrade to the reader's 4-positional form).
    if code_only "$_tj_atg" | grep -qF -- '--help' && code_only "$_tj_atg" | grep -qF 'reader lacks the head-sha argument'; then
      echo "PASS: $_tj_atg probes the reader's --help output and fails closed when the head-arg is absent (H-2(i))"
    else
      echo "FAIL: $_tj_atg does not probe+fail-closed on the reader's head-arg capability (H-2(i))"; st=1
    fi
    # security L-1 (close fix round 1): the Kit-Row step must parse the TRAILER BLOCK (via
    # `git interpret-trailers --parse`), never the first `^Kit-Row: ` line anywhere in the message —
    # the gates' own source of truth. Scoped to the row step's own block, not a whole-file grep.
    _twl_row=$(_t2_step_block "Read the PR head's Kit-Row trailer" "$_tj_atg")
    if printf '%s\n' "$_twl_row" | grep -qF 'git interpret-trailers --parse'; then
      echo "PASS: $_tj_atg's Kit-Row step parses the trailer block via git interpret-trailers --parse, not a first-match body grep (L-1)"
    else
      echo "FAIL: $_tj_atg's Kit-Row step does not parse the trailer block — it may read the first Kit-Row-looking line anywhere in the PR-authored message body (L-1)"; st=1
    fi
    # mutant: revert to the retired first-match grep shape -> must be caught.
    _twl_de=$(mktemp -d)
    sed "s#trailers=\$(git interpret-trailers --parse < /tmp/tbg-head-msg.txt)#trailers=\$(cat /tmp/tbg-head-msg.txt)#" "$_tj_atg" > "$_twl_de/e.yml"
    if cmp -s "$_twl_de/e.yml" "$_tj_atg"; then
      echo "FAIL: L-1/mutant setup — the planted copy did not differ from its source"; st=1
    fi
    _twl_de_row=$(_t2_step_block "Read the PR head's Kit-Row trailer" "$_twl_de/e.yml")
    if printf '%s\n' "$_twl_de_row" | grep -qF 'git interpret-trailers --parse'; then
      echo "FAIL: L-1/mutant (dropped interpret-trailers) was not caught"; st=1
    else
      echo "PASS: L-1/mutant (dropped interpret-trailers) is caught"
    fi
    rm -rf "$_twl_de" 2>/dev/null || true
    # H-2(ii): the base..head changed-listing reaches loop-state.sh as ARGV.
    if code_only "$_tj_atg" | grep -qF -- 'loop-state.sh --head "$SEAM_HEAD" --changed'; then
      echo "PASS: $_tj_atg hands loop-state.sh a real changed-listing via --changed (H-2(ii))"
    else
      echo "FAIL: $_tj_atg does not pass --changed to loop-state.sh — a base-only checkout's empty diff would fail OPEN to ordinary (H-2(ii))"; st=1
    fi
    # H-A (second fix round): an AUTHENTICATED, OBJECTS-ONLY fetch of the head sha must be PRESENT.
    # Removing it in favour of API-only reads (M-4) was a REGRESSION: loop-state.sh itself does
    # `git cat-file -e`/`git log -1` on the head sha, which needs the object locally even though
    # this job never checks it out. A silently re-dropped fetch step would red EVERY PR (rc 2).
    if code_only "$_tj_atg" | grep -qE 'git[[:space:]].*fetch[[:space:]].*--no-tags.*origin[[:space:]]+"\$HEAD_SHA"'; then
      echo "PASS: $_tj_atg fetches the PR head as an object (H-A)"
    else
      echo "FAIL: $_tj_atg has no objects-only head fetch — loop-state.sh's own git cat-file-e/git log -1 on the head sha would fail on a base-only checkout, redding EVERY PR (H-A regression)"; st=1
    fi
    # H-B: the changed-listing must come from the PR files API (3000 cap, matches changed_files),
    # never the compare API (300-file, alphabetical, un-paginatable cap — measured).
    if code_only "$_tj_atg" | grep -qF 'pulls/${PR}/files' && ! code_only "$_tj_atg" | grep -qF '/compare/'; then
      echo "PASS: $_tj_atg builds the changed-listing from the PR files API, not the truncating compare API (H-B)"
    else
      echo "FAIL: $_tj_atg does not build its changed-listing from the PR files API (or still uses the truncating /compare/ endpoint) — H-B's under-derivation gap"; st=1
    fi
    if code_only "$_tj_atg" | grep -qF 'changed_files'; then
      echo "PASS: $_tj_atg cross-checks the listing against the PR's changed_files count (H-B)"
    else
      echo "FAIL: $_tj_atg does not cross-check the listing length against changed_files — a silently truncated listing would classify on a partial view (H-B)"; st=1
    fi
    # ── fix-round C-1: the count cross-check was computed from the SAME projection handed to the
    # classifier (filename + previous_filename), so a renamed file counted TWICE against a
    # changed_files total the forge computes ONCE per file — failing closed on every PR containing a
    # rename. Verified here by EXTRACTING the actual jq filter strings from the shipped file (never a
    # hand-copied replica) and running them for real, via the jq binary, against synthetic PR-files
    # JSON representing one rename.
    _tj_jqcount=$(sed -n "s/.*pulls\/\${PR}\/files\" --paginate -q '\(\[\.\[\] | \.filename\] | [^']*\)'.*/\1/p" "$_tj_atg" | head -1)
    _tj_jqfull=$(sed -n "s/.*pulls\/\${PR}\/files\" --paginate -q '\(\[\.\[\] | \.filename, [^']*\)'.*/\1/p" "$_tj_atg" | head -1)
    if [ -n "$_tj_jqcount" ] && [ -n "$_tj_jqfull" ] && command -v jq >/dev/null 2>&1; then
      _tj_pr_rename='[{"filename":"b.txt","previous_filename":"a.txt"}]'
      _tj_countlines=$(printf '%s' "$_tj_pr_rename" | jq -r "$_tj_jqcount" | grep -c .)
      _tj_fulllines=$(printf '%s' "$_tj_pr_rename" | jq -r "$_tj_jqfull" | grep -c .)
      # PASS scenario: the forge's changed_files for a one-file rename is 1 — the filenames-only
      # count must equal it, even though the classifier's own (fuller) listing has 2 lines.
      if [ "$_tj_countlines" = 1 ] && [ "$_tj_fulllines" = 2 ]; then
        echo "PASS: $_tj_atg's count-check basis (filenames only) is 1 for a one-file rename while the classifier listing (with previous_filename) stays 2 — C-1 fixed"
      else
        echo "FAIL: $_tj_atg's extracted jq filters do not reproduce the C-1 fix (count=$_tj_countlines expected 1, full=$_tj_fulllines expected 2)"; st=1
      fi
      # RED scenario: the same arithmetic ([ "$_tbg_lines" != "$_tbg_changed_files" ]) must still
      # refuse a genuinely inconsistent listing (a count that does NOT match changed_files).
      if [ "$_tj_countlines" != 2 ]; then
        echo "PASS: $_tj_atg's count-check would still REFUSE a genuinely inconsistent listing (1 != 2)"
      else
        echo "FAIL: $_tj_atg's count-check no longer distinguishes a genuine mismatch"; st=1
      fi
    else
      echo "FAIL: could not extract both jq filters from $_tj_atg (or jq is unavailable) — cannot verify C-1"; st=1
    fi
    # C-1 WIRING check: the jq-filter proof above verifies the FILTER exists; this catches the
    # sibling mutant — a correct filter written to /tmp/tbg-filenames.txt but _tbg_lines counting
    # the WRONG file (measured while proving this: reverting only the `_tbg_lines=` source back to
    # /tmp/tbg-changed.txt left every other C-1 check green).
    if code_only "$_tj_atg" | grep -qF '_tbg_lines=$(wc -l < /tmp/tbg-filenames.txt'; then
      echo "PASS: $_tj_atg's line-count is wired to the filenames-only listing, not the classifier's fuller one (C-1)"
    else
      echo "FAIL: $_tj_atg's line-count is not wired to /tmp/tbg-filenames.txt — the filenames-only jq filter could exist unused while the count still double-counts a rename (C-1)"; st=1
    fi
    # TRACKER-GATES-TRUSTED-WIRING T1: the shipped file must pass all three wiring legs.
    if _tj_wiring_legs "$_tj_atg"; then
      echo "PASS: $_tj_atg passes the reader-states/rc-aggregation/PR-env wiring legs (T1)"
    else
      echo "FAIL: $_tj_atg does not pass all three T1 wiring legs (see above)"; st=1
    fi
    # ── TRACKER-TRUSTED-JOB-REQUIRED-CONTEXT (T4): the named, value-free credential pre-check that
    # runs immediately before the trusted reader. Mirrors the reader's own resolution (token ALWAYS,
    # user ONLY under auth=basic, read from the BASE conf) — RD-5 / D-240919-2(3): never a value.
    # _t4_leaks_cred <run-block-text> -> 0 (admitted/safe) iff every line dereferencing
    # KIT_TRACKER_(TOKEN|USER) is exactly a presence test of that shape, AND the block never
    # names printenv, a bare `env` command, `set -x`, or GITHUB_OUTPUT/ENV/STEP_SUMMARY (RT4-Q1 +
    # S-7 + S-9). Admit-only, never a ban-list of spellings: everything not admitted is refused.
    # This is the ONE place the regex lives (leg 3 and mutantA both call through here, no inline
    # copy — orchestrator ruling).
    _t4_leaks_cred() {
      # Scoped to the run: BODY only — a step block also carries an `env:` key section (the literal
      # word "env:" there is a YAML key, never the shell builtin the deny-list means to catch).
      # RB-3: fail closed if the step's `run: |` block cannot even be found — an absent block is
      # never "nothing to admit, so safe" (that would silently pass a step this function could not
      # actually inspect).
      printf '%s\n' "$1" | grep -qF 'run: |' || return 1
      _t4lc_run=$(printf '%s\n' "$1" | sed -n '/run: |/,$p' | tail -n +2)
      # Strip every EXACT admitted presence-test occurrence, then refuse if any DEREFERENCE of
      # $KIT_TRACKER_(TOKEN|USER) remains anywhere in what's left — brace-optional, hash-optional
      # (`#` covers the length-expansion shape `${#KIT_TRACKER_TOKEN}`) — never a line-level
      # grep -v, which would wrongly admit a whole line just because an admitted test appears
      # somewhere on it (e.g. `[ -z "$KIT_TRACKER_TOKEN" ] && echo "${KIT_TRACKER_TOKEN:0:4}"`).
      # A BARE literal mention of the name (no leading `$`) is never itself the leak this admits —
      # the reader's own `_missing="${_missing:+$_missing and }KIT_TRACKER_USER"` naming convention
      # is exactly that shape and is not a value leak; indirect expansion (`${!n}`) is refused
      # separately below regardless of what name the indirection variable was assigned.
      _t4lc_stripped=$(printf '%s\n' "$_t4lc_run" | sed -E 's/\[ -[zn] "\$KIT_TRACKER_(TOKEN|USER)" \]//g')
      printf '%s\n' "$_t4lc_stripped" | grep -qE '\$\{?#?KIT_TRACKER_(TOKEN|USER)' && return 1
      printf '%s\n' "$_t4lc_run" | grep -qF '${!' && return 1
      printf '%s\n' "$_t4lc_run" | grep -qE '(^|[^A-Za-z0-9_])(printenv|env)([^A-Za-z0-9_]|$)' && return 1
      printf '%s\n' "$_t4lc_run" | grep -qE 'set[[:space:]]+-x' && return 1
      printf '%s\n' "$_t4lc_run" | grep -qE 'GITHUB_(OUTPUT|ENV|STEP_SUMMARY)' && return 1
      return 0
    }

    # _t4_permissions_block <file> -> the `permissions:` block (the key line + every indented line
    # under it), the same start/end-by-indent technique _t2_step_block uses for a step (S-10 +
    # RT4-Q3).
    _t4_permissions_block() {
      _t4pb_code=$(code_only "$1")
      _t4pb_start=$(printf '%s\n' "$_t4pb_code" | grep -nE '^permissions:' | head -1 | cut -d: -f1)
      [ -n "$_t4pb_start" ] || return 1
      _t4pb_after=$(printf '%s\n' "$_t4pb_code" | tail -n "+$((_t4pb_start + 1))")
      _t4pb_rel_end=$(printf '%s\n' "$_t4pb_after" | grep -nE '^[^[:space:]]' | head -1 | cut -d: -f1)
      if [ -n "$_t4pb_rel_end" ]; then
        _t4pb_end=$((_t4pb_start + _t4pb_rel_end - 1))
        printf '%s\n' "$_t4pb_code" | sed -n "${_t4pb_start},${_t4pb_end}p"
      else
        printf '%s\n' "$_t4pb_code" | tail -n "+$_t4pb_start"
      fi
    }

    # _t4_job_perm_leak <file> -> 0 (safe) iff the `tracker-board-gates:` JOB's OWN block (from its
    # key line to the next top-level (2-space-indented) job key, or EOF) carries NO `permissions:`
    # key of its own — a job-level permissions: block OVERRIDES the pinned top-level one for that
    # job (RB-2 [SEC]), so its mere presence inside THIS job's block is itself the leak, regardless
    # of what it grants. Scoped strictly to this one job's block: a SIBLING job's OWN
    # `permissions:` block (e.g. a later `tracker-board-drift:` job) starts AFTER this job's block
    # ends and is never inside it — never flagged. Fails closed (1) if the job itself cannot be
    # found at all.
    _t4_job_perm_leak() {
      _t4jp_code=$(code_only "$1")
      _t4jp_start=$(printf '%s\n' "$_t4jp_code" | grep -nE '^  tracker-board-gates:[[:space:]]*$' | head -1 | cut -d: -f1)
      [ -n "$_t4jp_start" ] || return 1
      _t4jp_after=$(printf '%s\n' "$_t4jp_code" | tail -n "+$((_t4jp_start + 1))")
      _t4jp_rel_end=$(printf '%s\n' "$_t4jp_after" | grep -nE '^  [A-Za-z0-9_-]+:[[:space:]]*$' | head -1 | cut -d: -f1)
      if [ -n "$_t4jp_rel_end" ]; then
        _t4jp_block=$(printf '%s\n' "$_t4jp_after" | sed -n "1,$((_t4jp_rel_end - 1))p")
      else
        _t4jp_block="$_t4jp_after"
      fi
      printf '%s\n' "$_t4jp_block" | grep -qE '^[[:space:]]+permissions:' && return 1
      return 0
    }

    # _t4_extract_precheck_script <file> -> the pre-check step's `run:` body, dedented, ready to
    # execute under `sh` (RT4-Q2/S-8 — the behavioural leg; never a hand-typed copy of the script).
    _t4_extract_precheck_script() {
      _t4eps_block=$(_t2_step_block 'Verify tracker credentials are configured' "$1")
      printf '%s\n' "$_t4eps_block" | sed -n '/run: |/,$p' | tail -n +2 | sed 's/^          //'
    }

    # _t4_run_matrix <script-text> -> 0 iff, over auth ∈ {basic,bearer,absent} x token ∈
    # {set,empty} x user ∈ {set,empty}, <script-text> exits 1 exactly when a refusal is due (token
    # empty; or effective auth=basic (absent falls back to basic, same as the reader) and user
    # empty), names exactly the missing variable(s) in its ::error, exits 0 otherwise, and never
    # emits either fixture secret's VALUE or its character LENGTH (RT4-Q2/S-8, the headline).
    _t4_run_matrix() {
      _t4rm_script="$1"; _t4rm_bad=0
      _t4rm_root=$(mktemp -d)
      mkdir -p "$_t4rm_root/scripts" "$_t4rm_root/.kit"
      cp scripts/tracker-conf.sh "$_t4rm_root/scripts/tracker-conf.sh"
      _t4rm_tokval='tok-fixture-9f3ac72e01-value'
      _t4rm_uservval='user-fixture-4b7e91-value'
      _t4rm_toklen=${#_t4rm_tokval}
      _t4rm_userlen=${#_t4rm_uservval}
      for _t4rm_auth in basic bearer absent; do
        {
          echo 'version=1'; echo 'backend=jira'; echo 'base_url=https://example.atlassian.net'
          echo 'flavour=cloud'
          [ "$_t4rm_auth" = absent ] || echo "auth=$_t4rm_auth"
          echo 'project=AB'; echo 'state.in-progress=In Progress'
        } > "$_t4rm_root/.kit/tracker.conf"
        for _t4rm_tokst in set empty; do
          for _t4rm_userst in set empty; do
            _t4rm_tok=""; [ "$_t4rm_tokst" = set ] && _t4rm_tok="$_t4rm_tokval"
            _t4rm_user=""; [ "$_t4rm_userst" = set ] && _t4rm_user="$_t4rm_uservval"
            _t4rm_eff_auth="$_t4rm_auth"; [ "$_t4rm_auth" = absent ] && _t4rm_eff_auth=basic
            _t4rm_want_missing=""
            [ -z "$_t4rm_tok" ] && _t4rm_want_missing="KIT_TRACKER_TOKEN"
            if [ "$_t4rm_eff_auth" = basic ] && [ -z "$_t4rm_user" ]; then
              _t4rm_want_missing="${_t4rm_want_missing:+$_t4rm_want_missing and }KIT_TRACKER_USER"
            fi
            _t4rm_out=$(cd "$_t4rm_root" && KIT_TRACKER_TOKEN="$_t4rm_tok" KIT_TRACKER_USER="$_t4rm_user" sh -c "$_t4rm_script" 2>&1)
            _t4rm_rc=$?
            if [ -n "$_t4rm_want_missing" ]; then
              if [ "$_t4rm_rc" != 1 ]; then
                echo "FAIL: T4-behavioural: auth=$_t4rm_auth token=$_t4rm_tokst user=$_t4rm_userst want rc1, got rc$_t4rm_rc"; _t4rm_bad=1
              fi
              if ! printf '%s\n' "$_t4rm_out" | grep -qF "add the repository Actions secret $_t4rm_want_missing"; then
                echo "FAIL: T4-behavioural: auth=$_t4rm_auth token=$_t4rm_tokst user=$_t4rm_userst -- ::error did not name exactly '$_t4rm_want_missing'"; _t4rm_bad=1
              fi
            else
              if [ "$_t4rm_rc" != 0 ]; then
                echo "FAIL: T4-behavioural: auth=$_t4rm_auth token=$_t4rm_tokst user=$_t4rm_userst want rc0, got rc$_t4rm_rc"; _t4rm_bad=1
              fi
            fi
            if printf '%s\n' "$_t4rm_out" | grep -qF "$_t4rm_tokval" || printf '%s\n' "$_t4rm_out" | grep -qF "$_t4rm_uservval"; then
              echo "FAIL: T4-behavioural: auth=$_t4rm_auth token=$_t4rm_tokst user=$_t4rm_userst -- the run leaked a fixture secret VALUE"; _t4rm_bad=1
            fi
            if printf '%s\n' "$_t4rm_out" | grep -qx "$_t4rm_toklen" || printf '%s\n' "$_t4rm_out" | grep -qx "$_t4rm_userlen"; then
              echo "FAIL: T4-behavioural: auth=$_t4rm_auth token=$_t4rm_tokst user=$_t4rm_userst -- the run leaked a fixture secret LENGTH"; _t4rm_bad=1
            fi
          done
        done
      done
      rm -rf "$_t4rm_root" 2>/dev/null || true
      return $_t4rm_bad
    }

    _t4_precheck=$(_t2_step_block 'Verify tracker credentials are configured' "$_tj_atg")
    _t4_precheck_line=$(code_only "$_tj_atg" | grep -nF 'Verify tracker credentials are configured' | head -1 | cut -d: -f1)
    _t4_reader_line=$(code_only "$_tj_atg" | grep -nF 'Run the trusted reader from base' | head -1 | cut -d: -f1)
    if [ -n "$_t4_precheck" ] && printf '%s\n' "$_t4_precheck" | grep -qF "if: steps.resolve.outputs.skip != 'true'" \
       && [ -n "$_t4_precheck_line" ] && [ -n "$_t4_reader_line" ] && [ "$_t4_precheck_line" -lt "$_t4_reader_line" ]; then
      echo "PASS: $_tj_atg's credential pre-check step exists before the reader step and shares its if: guard (T4)"
    else
      echo "FAIL: $_tj_atg's credential pre-check step is missing, out of order, or does not share the reader's if: guard (T4)"; st=1
    fi
    # S-11: the FULL auth-resolution line, fallback included — a substring match on
    # 'scripts/tracker-conf.sh get auth' alone would still pass if the `2>/dev/null || echo basic`
    # fallback (the reader's own default) were quietly dropped.
    if printf '%s\n' "$_t4_precheck" | grep -qF '_auth=$(sh scripts/tracker-conf.sh get auth .kit/tracker.conf 2>/dev/null || echo basic)'; then
      echo "PASS: $_tj_atg's credential pre-check matches the full auth-resolution line, fallback included (S-11)"
    else
      echo "FAIL: $_tj_atg's credential pre-check does not match the full auth-resolution line (S-11)"; st=1
    fi
    if _t4_leaks_cred "$_t4_precheck"; then
      echo "PASS: $_tj_atg's credential pre-check never echoes/printfs a credential variable — presence tests only (T4/RT4-Q1/S-7/S-9)"
    else
      echo "FAIL: $_tj_atg's credential pre-check leaks a credential (RD-5 forbids surfacing the value) (T4/RT4-Q1/S-7/S-9)"; st=1
    fi
    if code_only "$_tj_atg" | grep -qF 'contents: read' && tj_pairing_leg >/dev/null 2>&1; then
      echo "PASS: $_tj_atg still declares permissions: contents: read and the S-1 pairing leg still passes (T4)"
    else
      echo "FAIL: $_tj_atg's permissions block or the S-1 pairing leg regressed (T4)"; st=1
    fi
    # Mutant T4a: echo the token inside the pre-check step -> must RED.
    _t4_d1=$(mktemp -d)
    sed 's/^\(          _auth=\$(sh scripts\/tracker-conf.sh get auth .kit\/tracker.conf 2>\/dev\/null || echo basic)\)$/\1\
          echo "token=$KIT_TRACKER_TOKEN"/' "$_tj_atg" > "$_t4_d1/t4a.yml"
    if cmp -s "$_t4_d1/t4a.yml" "$_tj_atg"; then
      echo "FAIL: T4/mutantA setup — the planted copy did not differ from its source"; st=1
    fi
    _t4a_block=$(_t2_step_block 'Verify tracker credentials are configured' "$_t4_d1/t4a.yml")
    if _t4_leaks_cred "$_t4a_block"; then
      echo "FAIL: T4/mutantA (echoed token in the pre-check) was not caught"; st=1
    else
      echo "PASS: T4/mutantA (echoed token in the pre-check) is caught"
    fi
    rm -rf "$_t4_d1" 2>/dev/null || true
    # Mutant T4b: drop the `"$_auth" = "basic" &&` guard so KIT_TRACKER_USER is required even under
    # auth=bearer — breaks "mirror the reader" (the reader never requires a user under bearer).
    _t4_d2=$(mktemp -d)
    sed 's/^          if \[ "\$_auth" = "basic" \] \&\& \[ -z "\$KIT_TRACKER_USER" \]; then$/          if [ -z "$KIT_TRACKER_USER" ]; then/' "$_tj_atg" > "$_t4_d2/t4b.yml"
    if cmp -s "$_t4_d2/t4b.yml" "$_tj_atg"; then
      echo "FAIL: T4/mutantB setup — the planted copy did not differ from its source"; st=1
    fi
    _t4b_block=$(_t2_step_block 'Verify tracker credentials are configured' "$_t4_d2/t4b.yml")
    if printf '%s\n' "$_t4b_block" | grep -qF '"$_auth" = "basic" ] && [ -z "$KIT_TRACKER_USER"'; then
      echo "FAIL: T4/mutantB (user required regardless of auth) was not caught"; st=1
    else
      echo "PASS: T4/mutantB (user required regardless of auth) is caught"
    fi
    rm -rf "$_t4_d2" 2>/dev/null || true

    # Mutant RT4-Q1-printenv: plant a `printenv` line inside the pre-check block -> _t4_leaks_cred
    # must catch it (the deny-list half of the admit-only lock, distinct from the dereference half
    # mutantA already covers).
    _t4_printenv_block=$(printf '%s\nprintenv\n' "$_t4_precheck")
    if _t4_leaks_cred "$_t4_printenv_block"; then
      echo "FAIL: T4/RT4-Q1-printenv mutant (planted printenv) was not caught"; st=1
    else
      echo "PASS: T4/RT4-Q1-printenv mutant (planted printenv) is caught"
    fi

    # RB-1 [SEC] new mutants — the admit-only lock must be a REAL strip-then-refuse, not a
    # line-level grep -v (which would wrongly admit a whole line just because an admitted test
    # appears somewhere on it, and would miss a leak shape that never matches the dereference
    # regex at all).
    # Mutant RB-1-sameline: an admitted presence test PLUS a value leak on the SAME line.
    _t4_sameline_block=$(printf '%s\n[ -z "$KIT_TRACKER_TOKEN" ] && echo "${KIT_TRACKER_TOKEN:0:4}"\n' "$_t4_precheck")
    if _t4_leaks_cred "$_t4_sameline_block"; then
      echo "FAIL: T4/RB-1-sameline mutant (admitted test + leak, same line) was not caught"; st=1
    else
      echo "PASS: T4/RB-1-sameline mutant (admitted test + leak, same line) is caught"
    fi
    # Mutant RB-1-length: a length expansion never matches the dereference regex at all.
    _t4_length_block=$(printf '%s\necho "len=${#KIT_TRACKER_TOKEN}"\n' "$_t4_precheck")
    if _t4_leaks_cred "$_t4_length_block"; then
      echo "FAIL: T4/RB-1-length mutant (echoed token length) was not caught"; st=1
    else
      echo "PASS: T4/RB-1-length mutant (echoed token length) is caught"
    fi
    # Mutant RB-1-indirect: indirect expansion (${!n}) — also caught up-front by the bare
    # 'KIT_TRACKER_' text on the assignment line, plus the dedicated ${! deny.
    _t4_indirect_block=$(printf '%s\nn=KIT_TRACKER_TOKEN; echo "${!n}"\n' "$_t4_precheck")
    if _t4_leaks_cred "$_t4_indirect_block"; then
      echo "FAIL: T4/RB-1-indirect mutant (indirect expansion via \${!n}) was not caught"; st=1
    else
      echo "PASS: T4/RB-1-indirect mutant (indirect expansion via \${!n}) is caught"
    fi

    # RB-3: _t4_leaks_cred must FAIL (fail closed) when it cannot find the step's run: | block at
    # all — never a silent "nothing to admit, so safe".
    if _t4_leaks_cred "no run block here at all"; then
      echo "FAIL: T4/RB-3 (no run: | block found) was not caught — must fail closed"; st=1
    else
      echo "PASS: T4/RB-3 (no run: | block found) fails closed"
    fi

    # Mutant S-11: drop the `2>/dev/null || echo basic` fallback from the auth-resolution line.
    _t4_d3=$(mktemp -d)
    sed 's#_auth=\$(sh scripts/tracker-conf.sh get auth .kit/tracker.conf 2>/dev/null || echo basic)#_auth=$(sh scripts/tracker-conf.sh get auth .kit/tracker.conf)#' "$_tj_atg" > "$_t4_d3/t4s11.yml"
    if cmp -s "$_t4_d3/t4s11.yml" "$_tj_atg"; then
      echo "FAIL: T4/S-11 mutant setup — the planted copy did not differ from its source"; st=1
    fi
    _t4s11_block=$(_t2_step_block 'Verify tracker credentials are configured' "$_t4_d3/t4s11.yml")
    if printf '%s\n' "$_t4s11_block" | grep -qF '_auth=$(sh scripts/tracker-conf.sh get auth .kit/tracker.conf 2>/dev/null || echo basic)'; then
      echo "FAIL: T4/S-11 mutant (dropped the || echo basic fallback) was not caught"; st=1
    else
      echo "PASS: T4/S-11 mutant (dropped the || echo basic fallback) is caught"
    fi
    rm -rf "$_t4_d3" 2>/dev/null || true

    # S-10 / RT4-Q3 (re-pinned by ADOPTER-GATES-JIRA-BLOCKERS C3): the tracker job's TOP-LEVEL
    # permissions: block declares EXACTLY two entries, `contents: read` and `pull-requests: read`
    # (any order), nothing else. `pull-requests: read` is the one owner-ruled widening (a private
    # repo's pulls endpoint 404s on contents: read alone); a write, a third scope, or a dropped
    # entry all RED. _t4_permissions_block reads the TOP-LEVEL block only — a job-level block
    # (e.g. tracker-board-drift's own) is never counted here.
    _t4_perm_exact2() {  # <file> -> 0 iff the top-level block is exactly those two entries
      _t4pe_blk=$(_t4_permissions_block "$1") || return 1
      printf '%s\n' "$_t4pe_blk" | head -1 | grep -qxF 'permissions:' || return 1
      _t4pe_body=$(printf '%s\n' "$_t4pe_blk" | tail -n +2 | grep . || true)
      [ "$(printf '%s\n' "$_t4pe_body" | grep -c .)" = 2 ] || return 1
      printf '%s\n' "$_t4pe_body" | grep -qxF '  contents: read' || return 1
      printf '%s\n' "$_t4pe_body" | grep -qxF '  pull-requests: read' || return 1
      return 0
    }
    if _t4_perm_exact2 "$_tj_atg"; then
      echo "PASS: $_tj_atg's top-level permissions: block declares exactly contents: read + pull-requests: read (S-10/RT4-Q3/C3)"
    else
      echo "FAIL: $_tj_atg's top-level permissions: block is not exactly 'contents: read' + 'pull-requests: read' (S-10/RT4-Q3/C3)"; st=1
    fi
    # Mutant base: a copy that DEFINITELY carries `pull-requests: read` (idempotent — an already-fixed
    # profile is used as is), so the three mutants below hold before and after the real fix.
    _t4_permd=$(mktemp -d)
    if grep -qxF '  pull-requests: read' "$_tj_atg"; then
      cp "$_tj_atg" "$_t4_permd/perm-base.yml"
    else
      sed '/^  contents: read$/a\
  pull-requests: read' "$_tj_atg" > "$_t4_permd/perm-base.yml"
    fi
    if _t4_perm_exact2 "$_t4_permd/perm-base.yml"; then
      echo "PASS: T4/C3 mutant base (contents: read + pull-requests: read) is accepted"
    else
      echo "FAIL: T4/C3 mutant base (contents: read + pull-requests: read) was rejected — the mutants below would be vacuous"; st=1
    fi
    # (i) drop pull-requests: read -> must RED.
    sed '/^  pull-requests: read$/d' "$_t4_permd/perm-base.yml" > "$_t4_permd/perm-drop.yml"
    if cmp -s "$_t4_permd/perm-drop.yml" "$_t4_permd/perm-base.yml"; then
      echo "FAIL: T4/C3 (i) mutant setup — the planted copy did not differ from its source"; st=1
    fi
    if _t4_perm_exact2 "$_t4_permd/perm-drop.yml"; then
      echo "FAIL: T4/C3 (i) mutant (dropped pull-requests: read) was not caught"; st=1
    else
      echo "PASS: T4/C3 (i) mutant (dropped pull-requests: read) is caught"
    fi
    # (ii) add pull-requests: write as a THIRD entry (the original S-10 mutant) -> must RED.
    sed '/^  pull-requests: read$/a\
  pull-requests: write' "$_t4_permd/perm-base.yml" > "$_t4_permd/perm-third.yml"
    if cmp -s "$_t4_permd/perm-third.yml" "$_t4_permd/perm-base.yml"; then
      echo "FAIL: T4/C3 (ii)/S-10 mutant setup — the planted copy did not differ from its source"; st=1
    fi
    if _t4_perm_exact2 "$_t4_permd/perm-third.yml"; then
      echo "FAIL: T4/C3 (ii)/S-10 mutant (added a third entry, pull-requests: write) was not caught"; st=1
    else
      echo "PASS: T4/C3 (ii)/S-10 mutant (added a third entry, pull-requests: write) is caught"
    fi
    # (iii) widen pull-requests: read to write -> must RED.
    sed 's/^  pull-requests: read$/  pull-requests: write/' "$_t4_permd/perm-base.yml" > "$_t4_permd/perm-widen.yml"
    if cmp -s "$_t4_permd/perm-widen.yml" "$_t4_permd/perm-base.yml"; then
      echo "FAIL: T4/C3 (iii) mutant setup — the planted copy did not differ from its source"; st=1
    fi
    if _t4_perm_exact2 "$_t4_permd/perm-widen.yml"; then
      echo "FAIL: T4/C3 (iii) mutant (pull-requests: read -> write) was not caught"; st=1
    else
      echo "PASS: T4/C3 (iii) mutant (pull-requests: read -> write) is caught"
    fi
    # (iv) rewrite the header to `permissions: write-all`, both entries kept -> must RED (S2).
    sed 's/^permissions:$/permissions: write-all/' "$_t4_permd/perm-base.yml" > "$_t4_permd/perm-hdr.yml"
    if cmp -s "$_t4_permd/perm-hdr.yml" "$_t4_permd/perm-base.yml"; then
      echo "FAIL: T4/C3 (iv) mutant setup — the planted copy did not differ from its source"; st=1
    fi
    if _t4_perm_exact2 "$_t4_permd/perm-hdr.yml"; then
      echo "FAIL: T4/C3 (iv) mutant (header rewritten to permissions: write-all) was not caught"; st=1
    else
      echo "PASS: T4/C3 (iv) mutant (header rewritten to permissions: write-all) is caught"
    fi
    rm -rf "$_t4_permd" 2>/dev/null || true

    # RB-2 [SEC]: the tracker-board-gates JOB's OWN block carries no permissions: key of its own —
    # a job-level block would override the pinned top-level one for this job.
    if _t4_job_perm_leak "$_tj_atg"; then
      echo "PASS: $_tj_atg's tracker-board-gates job carries no job-level permissions: override (RB-2)"
    else
      echo "FAIL: $_tj_atg's tracker-board-gates job carries a job-level permissions: key, overriding the pinned top-level one (RB-2)"; st=1
    fi
    # Mutant RB-2: add a job-level permissions: block right after the job's own key line (before
    # its `steps:`) -> must RED.
    _t4_jpd=$(mktemp -d)
    sed '/^  tracker-board-gates:$/a\
    permissions:\
      pull-requests: write' "$_tj_atg" > "$_t4_jpd/jobperm-mut.yml"
    if cmp -s "$_t4_jpd/jobperm-mut.yml" "$_tj_atg"; then
      echo "FAIL: T4/RB-2 mutant setup — the planted copy did not differ from its source"; st=1
    fi
    if _t4_job_perm_leak "$_t4_jpd/jobperm-mut.yml"; then
      echo "FAIL: T4/RB-2 mutant (added a job-level permissions: block) was not caught"; st=1
    else
      echo "PASS: T4/RB-2 mutant (added a job-level permissions: block) is caught"
    fi
    # RB-2 tolerance: a SIBLING job carrying its OWN job-level permissions: block (e.g. a later
    # `tracker-board-drift:` job, per main's PR #706) must NOT trip this check — it is scoped
    # strictly to the tracker-board-gates job's own block, which ends before the sibling begins.
    cp "$_tj_atg" "$_t4_jpd/sibling-ok.yml"
    printf '\n  tracker-board-drift:\n    permissions:\n      contents: read\n    runs-on: ubuntu-latest\n    steps: []\n' >> "$_t4_jpd/sibling-ok.yml"
    if _t4_job_perm_leak "$_t4_jpd/sibling-ok.yml"; then
      echo "PASS: T4/RB-2 tolerance: a sibling job's OWN job-level permissions: block is not flagged (scoped to tracker-board-gates alone)"
    else
      echo "FAIL: T4/RB-2 tolerance: a sibling job's OWN job-level permissions: block was wrongly flagged — the scope leaked past tracker-board-gates's own block"; st=1
    fi
    rm -rf "$_t4_jpd" 2>/dev/null || true

    # RT4-Q2 + S-8 [SEC] — the behavioural leg (the headline; orchestrator ruling: prefer this over
    # a textual pin wherever the thing can be run).
    _t4_real_script=$(_t4_extract_precheck_script "$_tj_atg")
    if [ -n "$_t4_real_script" ] && _t4_run_matrix "$_t4_real_script"; then
      echo "PASS: $_tj_atg's real credential pre-check script satisfies the full auth x token x user matrix, no secret leak (RT4-Q2/S-8)"
    else
      echo "FAIL: $_tj_atg's real credential pre-check script failed the behavioural matrix (RT4-Q2/S-8; see above)"; st=1
    fi

    # Mutant behavioural-A: delete the token check -> a token-empty cell wrongly rc0.
    _t4_mutA=$(printf '%s\n' "$_t4_real_script" | sed '/^if \[ -z "\$KIT_TRACKER_TOKEN" \]; then$/,/^fi$/d')
    if [ "$_t4_mutA" = "$_t4_real_script" ]; then
      echo "FAIL: T4-behavioural mutantA setup — the planted script did not differ from its source"; st=1
    fi
    if _t4_run_matrix "$_t4_mutA" >/dev/null 2>&1; then
      echo "FAIL: T4-behavioural mutantA (token check deleted) was not caught"; st=1
    else
      echo "PASS: T4-behavioural mutantA (token check deleted) is caught"
    fi

    # Mutant behavioural-B: require the user under bearer too (drop the auth=basic guard).
    _t4_mutB=$(printf '%s\n' "$_t4_real_script" | sed 's/^if \[ "\$_auth" = "basic" \] && \[ -z "\$KIT_TRACKER_USER" \]; then$/if [ -z "$KIT_TRACKER_USER" ]; then/')
    if [ "$_t4_mutB" = "$_t4_real_script" ]; then
      echo "FAIL: T4-behavioural mutantB setup — the planted script did not differ from its source"; st=1
    fi
    if _t4_run_matrix "$_t4_mutB" >/dev/null 2>&1; then
      echo "FAIL: T4-behavioural mutantB (user required under bearer) was not caught"; st=1
    else
      echo "PASS: T4-behavioural mutantB (user required under bearer) is caught"
    fi

    # Mutant behavioural-C: echo the token's LENGTH (the brief's own `echo ${#KIT_TRACKER_TOKEN}`
    # mutant) -> the leak check must catch it even though no value ever appears.
    _t4_mutC=$(printf '%s\necho "${#KIT_TRACKER_TOKEN}"\n' "$_t4_real_script")
    if _t4_run_matrix "$_t4_mutC" >/dev/null 2>&1; then
      echo "FAIL: T4-behavioural mutantC (echoed token length) was not caught"; st=1
    else
      echo "PASS: T4-behavioural mutantC (echoed token length) is caught"
    fi

    # Mutant 1: drop ' ready' from the reader invocation's trailing state list.
    _twl_d1=$(mktemp -d)
    sed 's/"\$HEAD_SHA" in-progress in-review ready/"$HEAD_SHA" in-progress in-review/' "$_tj_atg" > "$_twl_d1/m1.yml"
    if cmp -s "$_twl_d1/m1.yml" "$_tj_atg"; then
      echo "FAIL: T1/mutant1 setup — the planted copy did not differ from its source"; st=1
    fi
    if _tj_wiring_legs "$_twl_d1/m1.yml" >/dev/null; then
      echo "FAIL: T1/mutant1 (reader dropped ' ready') was not caught"; st=1
    else
      echo "PASS: T1/mutant1 (reader dropped ' ready') is caught"
    fi
    rm -rf "$_twl_d1" 2>/dev/null || true
    # Mutant 2a: strip the rc_bp capture from the presence-gate invocation.
    _twl_d2a=$(mktemp -d)
    sed 's/sh conformance\/backlog-presence.sh --dir "\$SEAM_ROOT" --pr "\$PR" --changed \/tmp\/tbg-changed.txt --head "\$SEAM_HEAD" || rc_bp=\$?/sh conformance\/backlog-presence.sh --dir "$SEAM_ROOT" --pr "$PR" --changed \/tmp\/tbg-changed.txt --head "$SEAM_HEAD"/' "$_tj_atg" > "$_twl_d2a/m2a.yml"
    if cmp -s "$_twl_d2a/m2a.yml" "$_tj_atg"; then
      echo "FAIL: T1/mutant2a setup — the planted copy did not differ from its source"; st=1
    fi
    if _tj_wiring_legs "$_twl_d2a/m2a.yml" >/dev/null; then
      echo "FAIL: T1/mutant2a (stripped || rc_bp=\$?) was not caught"; st=1
    else
      echo "PASS: T1/mutant2a (stripped || rc_bp=\$?) is caught"
    fi
    rm -rf "$_twl_d2a" 2>/dev/null || true
    # Mutant 2b: delete the final combined rc test line.
    _twl_d2b=$(mktemp -d)
    sed '/\[ "\$rc_ls" = 0 \] && \[ "\$rc_bp" = 0 \] && \[ "\$rc_bc" = 0 \]/d' "$_tj_atg" > "$_twl_d2b/m2b.yml"
    if cmp -s "$_twl_d2b/m2b.yml" "$_tj_atg"; then
      echo "FAIL: T1/mutant2b setup — the planted copy did not differ from its source"; st=1
    fi
    if _tj_wiring_legs "$_twl_d2b/m2b.yml" >/dev/null; then
      echo "FAIL: T1/mutant2b (deleted the final combined rc test line) was not caught"; st=1
    else
      echo "PASS: T1/mutant2b (deleted the final combined rc test line) is caught"
    fi
    rm -rf "$_twl_d2b" 2>/dev/null || true
    # Mutant 2c (L1, review Low): strip the rc_ls capture from the loop-state gate invocation.
    # `|| rc_bp=$?` alone let a stripped rc_ls capture pass unnoticed; rc_ls/rc_bc are now
    # both required (see the gates-check above), so this mutant must be caught too.
    _twl_d2c=$(mktemp -d)
    sed 's/|| rc_ls=\$?//' "$_tj_atg" > "$_twl_d2c/m2c.yml"
    if cmp -s "$_twl_d2c/m2c.yml" "$_tj_atg"; then
      echo "FAIL: T1/mutant2c setup — the planted copy did not differ from its source"; st=1
    fi
    if _tj_wiring_legs "$_twl_d2c/m2c.yml" >/dev/null; then
      echo "FAIL: T1/mutant2c (stripped || rc_ls=\$?) was not caught"; st=1
    else
      echo "PASS: T1/mutant2c (stripped || rc_ls=\$?) is caught"
    fi
    rm -rf "$_twl_d2c" 2>/dev/null || true
    # Mutant 2d (L2, whole-branch review Low 2): strip the rc_bc capture from the backlog-current
    # gate invocation — the sibling of mutant 2c for the third gate.
    _twl_d2d=$(mktemp -d)
    sed 's/|| rc_bc=\$?//' "$_tj_atg" > "$_twl_d2d/m2d.yml"
    if cmp -s "$_twl_d2d/m2d.yml" "$_tj_atg"; then
      echo "FAIL: T1/mutant2d setup — the planted copy did not differ from its source"; st=1
    fi
    if _tj_wiring_legs "$_twl_d2d/m2d.yml" >/dev/null; then
      echo "FAIL: T1/mutant2d (stripped || rc_bc=\$?) was not caught"; st=1
    else
      echo "PASS: T1/mutant2d (stripped || rc_bc=\$?) is caught"
    fi
    rm -rf "$_twl_d2d" 2>/dev/null || true
    # Mutant 3: delete the gates step's PR env line — ONLY the LAST matching line (the gates
    # step's own `PR:`), never the reader step's identical line earlier in the file. A whole-file
    # `/…/d` deletes BOTH occurrences, so a mutant scoped to the reader step alone (which
    # _tj_wiring_legs does not even inspect) would still register as "caught" for the wrong reason.
    _twl_d3=$(mktemp -d)
    _twl_pr_line=$(grep -n '^          PR: \${{ github.event.pull_request.number }}$' "$_tj_atg" | tail -1 | cut -d: -f1)
    if [ -z "$_twl_pr_line" ]; then
      echo "FAIL: T1/mutant3 setup — could not find the gates step's PR: line to delete"; st=1
    else
      sed "${_twl_pr_line}d" "$_tj_atg" > "$_twl_d3/m3.yml"
    fi
    if cmp -s "$_twl_d3/m3.yml" "$_tj_atg"; then
      echo "FAIL: T1/mutant3 setup — the planted copy did not differ from its source"; st=1
    fi
    if _tj_wiring_legs "$_twl_d3/m3.yml" >/dev/null; then
      echo "FAIL: T1/mutant3 (deleted the gates step's PR env line) was not caught"; st=1
    else
      echo "PASS: T1/mutant3 (deleted the gates step's PR env line) is caught"
    fi
    rm -rf "$_twl_d3" 2>/dev/null || true

    # Mutant/class fix (A): a copy of the YAML with an UNNAMED step (`- uses:`, no `- name:`) planted
    # AFTER the gates step, whose own run line carries a decoy `rc_bc=0; sh conformance/backlog-current.sh
    # --head WRONG x || rc_bc=$?`. `_t2_step_block`'s OLD end condition (`^      - name:` only) would
    # have run past this unnamed step straight to end-of-file, letting the decoy line leak into the
    # gates step's own block; the fixed end condition (any `^      - ` step start) must still stop the
    # block at the real boundary, so extraction returns ONLY the gates step's own backlog-current line.
    _twl_d4=$(mktemp -d)
    cp "$_tj_atg" "$_twl_d4/m4.yml"
    printf '      - uses: actions/checkout@decoy\n        run: |\n          rc_bc=0; sh conformance/backlog-current.sh --head WRONG x || rc_bc=$?\n' >> "$_twl_d4/m4.yml"
    if cmp -s "$_twl_d4/m4.yml" "$_tj_atg"; then
      echo "FAIL: T1/mutant-A setup — the planted copy did not differ from its source"; st=1
    fi
    _twl_d4_block=$(_t2_step_block 'Run the tracker-bound board gates from base' "$_twl_d4/m4.yml")
    if printf '%s\n' "$_twl_d4_block" | grep -qF 'WRONG'; then
      echo "FAIL: T1/mutant-A: _t2_step_block's gates-step extraction leaked into a later UNNAMED step (the class gap this fix closes)"; st=1
    else
      echo "PASS: T1/mutant-A: _t2_step_block stops at a later unnamed step; the gates step's own line only is returned"
    fi
    rm -rf "$_twl_d4" 2>/dev/null || true

    # ── TRACKER-GATES-TRUSTED-WIRING T2 — execute the two gate lines extracted from $_tj_atg ──────
    _t2base=$(mktemp -d)
    _t2listing="$_t2base/changed.txt"
    printf 'conformance/verify.sh\n' > "$_t2listing"
    _t2_bp_line=$(_t2_extract_gate_line 'sh conformance/backlog-presence.sh' "$_tj_atg" "$_t2listing")
    _t2_bc_line=$(_t2_extract_gate_line 'sh conformance/backlog-current.sh' "$_tj_atg" "$_t2listing")

    # leg 1: liveness — a vacuous extraction is a FAIL, checked before anything else runs.
    if [ -n "$_t2_bp_line" ] && [ -n "$_t2_bc_line" ] \
      && printf '%s\n' "$_t2_bp_line" | grep -qF -- '--head "$SEAM_HEAD"' \
      && printf '%s\n' "$_t2_bc_line" | grep -qF -- '--head "$SEAM_HEAD"'; then
      echo "PASS: T2/leg1: both gate lines extracted from $_tj_atg are non-empty and carry --head \"\$SEAM_HEAD\""
    else
      echo "FAIL: T2/leg1: extraction from $_tj_atg is vacuous — bp='$_t2_bp_line' bc='$_t2_bc_line'"; st=1
    fi

    if command -v jq >/dev/null 2>&1; then
      _t2tree="$_t2base/tree"
      _t2head=$(_t2_build_tree "$_t2tree")
      _t2pin=$(_t2_digest "$_t2tree/.kit/tracker.conf")
      _t2day=$(date -u +%Y-%m-%d)

      # security M-1 (close fix round 1): the setter is spelled LITERALLY here, not held in a
      # plain variable — hiding the name behind `$_t2_recvar` obscured the ONE genuine test-fixture
      # setter this file needs from the N-3 scan itself, rather than declaring it as sanctioned.
      # This file's own selftest() body is entirely excluded from the B6 setter count (it lives
      # after the `selftest() {` marker), and `conformance/proportional-gate-wired.sh` is listed in
      # TJ_SEAM_RECORD_ALLOWED_SETTERS above with the reason: this line sets the record for a
      # throwaway fixture tree only — production code in this file is held to zero setters by B6.

      # _t2_run_line <record-path> <cli-line> -> runs <cli-line> from the tree root against
      # <record-path>, returning its rc. The ONE place the env/cd shape lives — both _t2_run and
      # leg 6's mutant check call through here.
      _t2_run_line() {
        ( cd "$_t2tree" && KIT_TRACKER_RECORD="$1" SEAM_ROOT="$_t2tree" SEAM_HEAD="$_t2head" PR=1 sh -c "$2" )
      }

      # _t2_run <record-path> -> runs both extracted lines from the tree root against <record-path>,
      # setting _T2_BP_RC / _T2_BC_RC. Never a fixed /tmp path — SEAM_ROOT/head are this run's own.
      _t2_run() {
        _T2_BP_RC=0; _T2_BC_RC=0
        _t2_run_line "$1" "$_t2_bp_line" >/dev/null 2>&1 || _T2_BP_RC=$?
        _t2_run_line "$1" "$_t2_bc_line" >/dev/null 2>&1 || _T2_BC_RC=$?
      }

      # leg 2: good record — AB-1 in-progress claimed=yes (presence's subject); AB-2 ready with all
      # four dor-* = yes, listed under `list ready` (current's Ready list).
      _t2_rec="$_t2base/record.txt"
      {
        echo "kit-tracker-read 1"; echo "backend jira"; echo "pin sha256:$_t2pin"
        echo "head $_t2head"; echo "requested AB-1"; echo "read-day $_t2day"
        echo "credential ok"; echo "verdict bound"
        echo "row AB-1 state=in-progress claimed=yes"
        echo "row AB-2 state=ready dor-acceptance=yes dor-metric=yes dor-size=yes dor-risk=yes"
        echo "list ready AB-2"
      } > "$_t2_rec"
      _t2_run "$_t2_rec"
      if [ "$_T2_BP_RC" -eq 0 ] && [ "$_T2_BC_RC" -eq 0 ]; then
        echo "PASS: T2/leg2: a good tracker record -> presence rc0 AND current rc0"
      else
        echo "FAIL: T2/leg2: want presence rc0 current rc0, got bp=$_T2_BP_RC bc=$_T2_BC_RC"; st=1
      fi

      # leg 3: subject claimed=no -> presence rc1.
      _t2_rec3="$_t2base/record3.txt"
      sed 's/row AB-1 state=in-progress claimed=yes/row AB-1 state=in-progress claimed=no/' "$_t2_rec" > "$_t2_rec3"
      _t2_run "$_t2_rec3"
      if [ "$_T2_BP_RC" -eq 1 ]; then
        echo "PASS: T2/leg3: subject claimed=no -> presence rc1"
      else
        echo "FAIL: T2/leg3: want presence rc1, got bp=$_T2_BP_RC"; st=1
      fi

      # leg 4: AB-2 dor-size=no -> current rc1.
      _t2_rec4="$_t2base/record4.txt"
      sed 's/row AB-2 state=ready dor-acceptance=yes dor-metric=yes dor-size=yes dor-risk=yes/row AB-2 state=ready dor-acceptance=yes dor-metric=yes dor-size=no dor-risk=yes/' "$_t2_rec" > "$_t2_rec4"
      _t2_run "$_t2_rec4"
      if [ "$_T2_BC_RC" -eq 1 ]; then
        echo "PASS: T2/leg4: AB-2 dor-size=no -> current rc1"
      else
        echo "FAIL: T2/leg4: want current rc1, got bc=$_T2_BC_RC"; st=1
      fi

      # leg 5: no record (KIT_TRACKER_RECORD points at a missing file) -> both gates non-zero.
      _t2_run "$_t2base/does-not-exist.txt"
      if [ "$_T2_BP_RC" -ne 0 ] && [ "$_T2_BC_RC" -ne 0 ]; then
        echo "PASS: T2/leg5: a missing record -> both gates non-zero"
      else
        echo "FAIL: T2/leg5: want both non-zero, got bp=$_T2_BP_RC bc=$_T2_BC_RC"; st=1
      fi

      # leg 6: mutant — a copy of the YAML whose backlog-current line lost --head "$SEAM_HEAD" ->
      # the good-record run of the RE-EXTRACTED (mutant) line must now be non-zero (the leg reds on
      # a wrong CLI, never a hand-typed one).
      _t2_mutyml="$_t2base/mutant.yml"
      sed '/backlog-current\.sh/s/--head "\$SEAM_HEAD" //' "$_tj_atg" > "$_t2_mutyml"
      if cmp -s "$_t2_mutyml" "$_tj_atg"; then
        echo "FAIL: T2/leg6 setup — the planted copy did not differ from its source"; st=1
      fi
      _t2_bc_mut=$(_t2_extract_gate_line 'sh conformance/backlog-current.sh' "$_t2_mutyml" "$_t2listing")
      _t2_bc_mut_rc=0
      _t2_run_line "$_t2_rec" "$_t2_bc_mut" >/dev/null 2>&1 || _t2_bc_mut_rc=$?
      if [ "$_t2_bc_mut_rc" -ne 0 ]; then
        echo "PASS: T2/leg6: a mutant backlog-current line missing --head \"\$SEAM_HEAD\" reds on the good record"
      else
        echo "FAIL: T2/leg6: the mutant line did not red (rc=$_t2_bc_mut_rc) — the extraction cannot tell a wrong CLI from a right one"; st=1
      fi
    else
      echo "N/A: T2/legs 2-6 — jq is absent (gate_class fail-safes without it; see backlog-presence.sh's own header)"
    fi
    rm -rf "$_t2base" 2>/dev/null || true

    # ── TRACKER-DRIFT-SCHEDULED-WIRING — six shape legs on the folded tracker-board-drift job.
    # Same honesty note as above: text-presence, proving the shape is SPELLED into the file, not
    # that the job was exercised (the tracker-live dispatch-proof leg + board-drift.sh's own
    # --selftest legs are the executed proof). Each leg mutates a scratch COPY of the shipped
    # profile, asserts the mutant DIFFERS from the original, and asserts the leg's predicate REDS
    # on the mutant while it GREENS on the original.
    _tds_gates_blk=$(_tj_job_block "$_tj_atg" tracker-board-gates)
    _tds_drift_blk=$(_tj_job_block "$_tj_atg" tracker-board-drift)

    # leg 1: on: carries schedule: and workflow_dispatch:.
    if code_only "$_tj_atg" | grep -qE '^  schedule:[[:space:]]*$' \
        && code_only "$_tj_atg" | grep -qE '^  workflow_dispatch:[[:space:]]*$'; then
      echo "PASS: $_tj_atg's on: carries schedule: and workflow_dispatch: (drift job triggers)"
    else
      echo "FAIL: $_tj_atg's on: is missing schedule: or workflow_dispatch: — the drift job would never run"; st=1
    fi
    _tds_d1=$(mktemp -d)
    sed '/^  schedule:$/,/^    - cron:/d' "$_tj_atg" > "$_tds_d1/m1.yml"
    if cmp -s "$_tds_d1/m1.yml" "$_tj_atg"; then
      echo "FAIL: TDS/leg1 setup — the planted copy did not differ from its source"; st=1
    elif code_only "$_tds_d1/m1.yml" | grep -qE '^  schedule:[[:space:]]*$'; then
      echo "FAIL: TDS/leg1 mutant (deleted schedule:) was not caught"; st=1
    else
      echo "PASS: TDS/leg1 mutant (deleted schedule:) is caught"
    fi
    rm -rf "$_tds_d1" 2>/dev/null || true

    # item 5(b)/m3: leg1 gains a second mutant, deleting workflow_dispatch: -> reds.
    _tds_d1b=$(mktemp -d)
    sed '/^  workflow_dispatch:$/d' "$_tj_atg" > "$_tds_d1b/m1b.yml"
    if cmp -s "$_tds_d1b/m1b.yml" "$_tj_atg"; then
      echo "FAIL: TDS/leg1 m3 setup — the planted copy did not differ from its source"; st=1
    elif code_only "$_tds_d1b/m1b.yml" | grep -qE '^  workflow_dispatch:[[:space:]]*$'; then
      echo "FAIL: TDS/leg1 m3 mutant (deleted workflow_dispatch:) was not caught"; st=1
    else
      echo "PASS: TDS/leg1 m3 mutant (deleted workflow_dispatch:) is caught"
    fi
    rm -rf "$_tds_d1b" 2>/dev/null || true

    # item 4 (security L-2 RULE): the top-level on: block carries EXACTLY {pull_request_target,
    # schedule, workflow_dispatch} — never a fourth trigger (e.g. push:) the drift job's positive
    # `if:` guard (leg 3 below) does not enumerate. Scoped to the TOP-LEVEL on: block only (stops at
    # the next top-level key, never reaching into a job's own on-shaped step data).
    _tds_on_sec() {
      code_only "$1" | awk '
        /^on:[[:space:]]*$/ { f=1; next }
        f && /^[^[:space:]]/ { f=0 }
        f { print }
      '
    }
    _tds_on_keys() {
      _tds_on_sec "$1" | grep -E '^  [A-Za-z_-]+:' | sed -E 's/^  ([A-Za-z_-]+):.*/\1/' | sort -u
    }
    _tds_on_expected=$(printf 'pull_request_target\nschedule\nworkflow_dispatch\n' | sort -u)
    if [ "$(_tds_on_keys "$_tj_atg")" = "$_tds_on_expected" ]; then
      echo "PASS: $_tj_atg's top-level on: carries EXACTLY {pull_request_target, schedule, workflow_dispatch}"
    else
      echo "FAIL: $_tj_atg's top-level on: does not carry exactly {pull_request_target, schedule, workflow_dispatch} (got: $(_tds_on_keys "$_tj_atg" | tr '\n' ' '))"; st=1
    fi
    _tds_d1c=$(mktemp -d)
    awk '{print} /^on:[[:space:]]*$/ && !_d1c_done { print "  push:"; _d1c_done=1 }' "$_tj_atg" > "$_tds_d1c/m1c.yml"
    if cmp -s "$_tds_d1c/m1c.yml" "$_tj_atg"; then
      echo "FAIL: TDS on:-shape mutant setup — the planted copy did not differ from its source"; st=1
    elif [ "$(_tds_on_keys "$_tds_d1c/m1c.yml")" = "$_tds_on_expected" ]; then
      echo "FAIL: TDS on:-shape mutant (added push: under on:) was not caught"; st=1
    else
      echo "PASS: TDS on:-shape mutant (added push: under on:) is caught"
    fi
    rm -rf "$_tds_d1c" 2>/dev/null || true

    # item 4 follow-up (Low-B, security-seat RULE, fail-closed): a 2-space-indented line under the
    # top-level on: block that does NOT match a plain `key:` shape (e.g. a QUOTED key) is invisible
    # to _tds_on_keys' grep -E — it would be silently dropped rather than counted, so a stray
    # `"push":` line could add a fourth trigger without ever changing the {3 keys} comparison above.
    # Fail closed: any such line makes the shape check FAIL, named by content.
    _tds_on_malformed() {
      _tds_on_sec "$1" | grep -E '^  [^[:space:]]' | grep -vE '^  [A-Za-z_-]+:'
    }
    if [ -z "$(_tds_on_malformed "$_tj_atg")" ]; then
      echo "PASS: $_tj_atg's top-level on: block has no malformed (non-\`key:\`) 2-space-indented lines"
    else
      echo "FAIL: $_tj_atg's top-level on: block carries a malformed line: $(_tds_on_malformed "$_tj_atg")"; st=1
    fi
    _tds_d1d=$(mktemp -d)
    awk '{print} /^on:[[:space:]]*$/ && !_d1d_done { print "  \"push\":"; _d1d_done=1 }' "$_tj_atg" > "$_tds_d1d/m1d.yml"
    if cmp -s "$_tds_d1d/m1d.yml" "$_tj_atg"; then
      echo "FAIL: TDS on:-shape malformed-line mutant setup — the planted copy did not differ from its source"; st=1
    elif [ -z "$(_tds_on_malformed "$_tds_d1d/m1d.yml")" ]; then
      echo "FAIL: TDS on:-shape malformed-line mutant (added a quoted \"push\": line) was not caught"; st=1
    else
      echo "PASS: TDS on:-shape malformed-line mutant (added a quoted \"push\": line) is caught"
    fi
    rm -rf "$_tds_d1d" 2>/dev/null || true
    unset -f _tds_on_sec _tds_on_keys _tds_on_malformed

    # leg 2: tracker-board-gates carries if: github.event_name == 'pull_request_target'.
    if printf '%s\n' "$_tds_gates_blk" | grep -qF "if: github.event_name == 'pull_request_target'"; then
      echo "PASS: $_tj_atg's tracker-board-gates job carries if: github.event_name == 'pull_request_target'"
    else
      echo "FAIL: $_tj_atg's tracker-board-gates job has no pull_request_target guard — it could run PR-less on a schedule"; st=1
    fi
    _tds_d2=$(mktemp -d)
    sed "/if: github.event_name == 'pull_request_target'/d" "$_tj_atg" > "$_tds_d2/m2.yml"
    if cmp -s "$_tds_d2/m2.yml" "$_tj_atg"; then
      echo "FAIL: TDS/leg2 setup — the planted copy did not differ from its source"; st=1
    else
      _tds_d2_blk=$(_tj_job_block "$_tds_d2/m2.yml" tracker-board-gates)
      if printf '%s\n' "$_tds_d2_blk" | grep -qF "if: github.event_name == 'pull_request_target'"; then
        echo "FAIL: TDS/leg2 mutant (dropped the gates job's if:) was not caught"; st=1
      else
        echo "PASS: TDS/leg2 mutant (dropped the gates job's if:) is caught"
      fi
    fi
    rm -rf "$_tds_d2" 2>/dev/null || true

    # leg 3 (security L-2 RULE): tracker-board-drift carries a POSITIVE trigger guard —
    # `if: github.event_name == 'schedule' || github.event_name == 'workflow_dispatch'` (never the
    # earlier `!= 'pull_request_target'`, which admits ANY future trigger the on: block might grow to
    # include) — job-level pull-requests: read, and its checkout has NO ref: (S-1: a scheduled/
    # dispatch run must never check out a head).
    if printf '%s\n' "$_tds_drift_blk" | grep -qE "^    if: github\.event_name == 'schedule' \|\| github\.event_name == 'workflow_dispatch'\$" \
        && printf '%s\n' "$_tds_drift_blk" | grep -qE '^      pull-requests: read\s*$' \
        && ! printf '%s\n' "$_tds_drift_blk" | grep -qE '^\s*ref:'; then
      echo "PASS: $_tj_atg's tracker-board-drift job guards its trigger, declares pull-requests: read, and checks out no ref (S-1)"
    else
      echo "FAIL: $_tj_atg's tracker-board-drift job is missing its trigger guard, pull-requests: read, or checks out a ref"; st=1
    fi
    _tds_d3=$(mktemp -d)
    awk '
      { print }
      /actions\/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10  # v6\.0\.3$/ { seen=1 }
      seen && /persist-credentials: false/ {
        print "          ref: ${{ github.event.pull_request.head.sha }}"
        seen=0
      }
    ' "$_tj_atg" > "$_tds_d3/m3.yml"
    if cmp -s "$_tds_d3/m3.yml" "$_tj_atg"; then
      echo "FAIL: TDS/leg3 setup — the planted copy did not differ from its source"; st=1
    else
      _tds_d3_drift_blk=$(_tj_job_block "$_tds_d3/m3.yml" tracker-board-drift)
      _tds_d3_bad=0
      if printf '%s\n' "$_tds_d3_drift_blk" | grep -qE '^\s*ref:'; then :; else _tds_d3_bad=1; fi
      _tds_d3_pair_bad=0
      TJ_FLEET_GLOBS="$_tds_d3/m3.yml" tj_pairing_leg >/dev/null 2>&1 || _tds_d3_pair_bad=1
      if [ "$_tds_d3_bad" = 1 ]; then
        echo "FAIL: TDS/leg3 mutant (added ref: to the drift job's checkout) was not caught by the shape leg"; st=1
      elif [ "$_tds_d3_pair_bad" = 0 ]; then
        echo "FAIL: TDS/leg3 mutant (added ref: to the drift job's checkout) was not caught by tj_pairing_leg (free S-1 proof)"; st=1
      else
        echo "PASS: TDS/leg3 mutant (added ref: to the drift job's checkout) is caught by the shape leg AND tj_pairing_leg"
      fi
    fi
    rm -rf "$_tds_d3" 2>/dev/null || true

    # leg 4: ONLY the read step and the preflight step (TRACKER-PREFLIGHT-TIER-CARD; two steps, by
    # name) within the drift job carry secrets.KIT_TRACKER_. A third step still reds.
    _tds_read_blk=$(_t2_step_block "Read the tracker's in-flight lists" "$_tj_atg")
    _tds_pf_blk=$(_t2_step_block "Preflight from this runner" "$_tj_atg" || true)
    _tds_drift_secret_total=$(printf '%s\n' "$_tds_drift_blk" | grep -cF 'secrets.KIT_TRACKER_')
    _tds_read_secret_total=$(( $(printf '%s\n' "$_tds_read_blk" | grep -cF 'secrets.KIT_TRACKER_') + $(printf '%s\n' "$_tds_pf_blk" | grep -cF 'secrets.KIT_TRACKER_' || true) ))
    if [ "$_tds_drift_secret_total" -gt 0 ] && [ "$_tds_drift_secret_total" = "$_tds_read_secret_total" ]; then
      echo "PASS: $_tj_atg's tracker-board-drift job holds secrets.KIT_TRACKER_ only in its read step and its preflight step (hygiene, S-1)"
    else
      echo "FAIL: $_tj_atg's tracker-board-drift job carries a tracker secret outside its read and preflight steps (drift=$_tds_drift_secret_total read+preflight=$_tds_read_secret_total)"; st=1
    fi
    _tds_d4=$(mktemp -d)
    awk '
      { print }
      /SEAM_HEAD: \$\{\{ github\.sha \}\}$/ {
        print "          KIT_TRACKER_USER: ${{ secrets.KIT_TRACKER_USER }}"
        print "          KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}"
      }
    ' "$_tj_atg" > "$_tds_d4/m4.yml"
    if cmp -s "$_tds_d4/m4.yml" "$_tj_atg"; then
      echo "FAIL: TDS/leg4 setup — the planted copy did not differ from its source"; st=1
    else
      _tds_d4_drift_blk=$(_tj_job_block "$_tds_d4/m4.yml" tracker-board-drift)
      _tds_d4_read_blk=$(_t2_step_block "Read the tracker's in-flight lists" "$_tds_d4/m4.yml")
      _tds_d4_drift_total=$(printf '%s\n' "$_tds_d4_drift_blk" | grep -cF 'secrets.KIT_TRACKER_')
      _tds_d4_read_total=$(printf '%s\n' "$_tds_d4_read_blk" | grep -cF 'secrets.KIT_TRACKER_')
      if [ "$_tds_d4_drift_total" = "$_tds_d4_read_total" ]; then
        echo "FAIL: TDS/leg4 mutant (copied secret env into the drift step) was not caught"; st=1
      else
        echo "PASS: TDS/leg4 mutant (copied secret env into the drift step) is caught"
      fi
    fi
    rm -rf "$_tds_d4" 2>/dev/null || true

    # leg 5: the read step's reader call passes "$GITHUB_SHA" in-progress in-review, and
    # RECORD_PATH="$RUNNER_TEMP/ is assigned inside that step (S-10 — never from env).
    if printf '%s\n' "$_tds_read_blk" | grep -qF '"$GITHUB_SHA" in-progress in-review' \
        && printf '%s\n' "$_tds_read_blk" | grep -qF 'RECORD_PATH="$RUNNER_TEMP/'; then
      echo "PASS: $_tj_atg's drift read step passes the full in-progress/in-review state list and fixes RECORD_PATH in-step (S-10)"
    else
      echo "FAIL: $_tj_atg's drift read step is missing the in-progress/in-review state list or a fixed in-step RECORD_PATH"; st=1
    fi
    _tds_d5=$(mktemp -d)
    sed 's/"\$GITHUB_SHA" in-progress in-review/"$GITHUB_SHA" in-progress/' "$_tj_atg" > "$_tds_d5/m5.yml"
    if cmp -s "$_tds_d5/m5.yml" "$_tj_atg"; then
      echo "FAIL: TDS/leg5 setup — the planted copy did not differ from its source"; st=1
    else
      _tds_d5_read_blk=$(_t2_step_block "Read the tracker's in-flight lists" "$_tds_d5/m5.yml")
      if printf '%s\n' "$_tds_d5_read_blk" | grep -qF '"$GITHUB_SHA" in-progress in-review'; then
        echo "FAIL: TDS/leg5 mutant (dropped in-review) was not caught"; st=1
      else
        echo "PASS: TDS/leg5 mutant (dropped in-review) is caught"
      fi
    fi
    rm -rf "$_tds_d5" 2>/dev/null || true

    # leg 6: _tj_job_names on the shipped profile lists BOTH jobs (liveness: the pairing leg
    # actually walks the new job, not just the old one).
    _tds_names=$(_tj_job_names "$_tj_atg")
    if printf '%s\n' "$_tds_names" | grep -qF 'tracker-board-gates' \
        && printf '%s\n' "$_tds_names" | grep -qF 'tracker-board-drift'; then
      echo "PASS: _tj_job_names($_tj_atg) lists both tracker-board-gates and tracker-board-drift"
    else
      echo "FAIL: _tj_job_names($_tj_atg) does not list both jobs — the pairing leg would not walk tracker-board-drift at all: got '$_tds_names'"; st=1
    fi

    # ── TRACKER-DRIFT-SCHEDULED-WIRING — THE EXECUTED LEG: run the drift job's three run: blocks,
    # extracted BY STEP NAME from the shipped profile (sed/awk, never a hand copy), against a
    # harness that emulates the runner: COPIES of board-drift.sh/backlog-lib.sh/tracker-read.sh/
    # tracker-conf.sh over a throwaway root seeded from conformance/fixtures/tbg-record-gates-bind/
    # tracker-jira/ (CLAUDE.md + .kit/tracker.conf, project=AB), a fake scripts/tracker-jira.sh (T8
    # pattern, backlog-presence.sh ~1258-1340) that `cat`s the SAME tracked
    # conformance/fixtures/tracker-jira/ops/*.out files T8 proved, RUNNER_TEMP/GITHUB_OUTPUT temp
    # files, GITHUB_SHA the head of a throwaway git repo, and step outputs read back into the next
    # step's env exactly as the YAML maps them. The shape legs above prove the profile is SPELLED
    # right; this proves it RUNS.
    _tde_repo=$(pwd)
    _tde_enum_body=$(_t2_run_body "Enumerate PRs merged in the drift window (no secret)" "$_tj_atg")
    _tde_read_body=$(_t2_run_body "Read the tracker's in-flight lists" "$_tj_atg")
    _tde_arm_body=$(_t2_run_body "Run board-drift's tracker arm from base" "$_tj_atg")

    # leg 7 (liveness): all three blocks extracted non-empty — a step name change fails loudly.
    if [ -n "$_tde_enum_body" ] && [ -n "$_tde_read_body" ] && [ -n "$_tde_arm_body" ]; then
      echo "PASS: TDE/leg7: all three drift job run: blocks extracted non-empty from $_tj_atg (extraction liveness)"
    else
      echo "FAIL: TDE/leg7: extraction from $_tj_atg is vacuous (a step name likely changed) — enum='$_tde_enum_body' read='$_tde_read_body' arm='$_tde_arm_body'"; st=1
    fi

    # item 5(c) notes:
    #  - a step whose env: block references a TYPO'D `steps.<id>.outputs.<k>` is covered by leg 1's
    #    own bound scenario: the typo'd key resolves to "" (an unset output, never a harness error),
    #    which leg 1's own assertion on the DRIFT sentence's exact text catches as a red — the same
    #    way a real runner's silently-empty `${{ }}` interpolation would.
    #  - this throwaway root never carries `conformance/waivers-valid.sh`. Legs 1–3 (SEAM_RECORD
    #    set) never reach the waiver ladder (not_enforced_notice) at all, so its absence is inert
    #    there. Legs 6 and 8 (SEAM_RECORD absent/empty) DO reach it — they print the waiver-ABSENT
    #    note and return rc 3.
    #
    # _tde_mkroot -> a throwaway root: the TBG-RECORD-GATES-BIND fixture's CLAUDE.md + tracker.conf
    # (project=AB, jira/cloud) plus one extra state.* mapping each for in-review/done (a PRIVATE
    # copy — fix1 Q1's own rule — never a line appended to the tracked fixture) and copies of the
    # kit files the three run: blocks dereference.
    _tde_mkroot() {
      _tdmr=$(mktemp -d)
      mkdir -p "$_tdmr/conformance" "$_tdmr/scripts" "$_tdmr/.kit"
      cp "$_tde_repo/conformance/fixtures/tbg-record-gates-bind/tracker-jira/CLAUDE.md" "$_tdmr/CLAUDE.md"
      cp "$_tde_repo/conformance/fixtures/tbg-record-gates-bind/tracker-jira/.kit/tracker.conf" "$_tdmr/.kit/tracker.conf"
      printf 'state.in-review=In Review\n' >> "$_tdmr/.kit/tracker.conf"
      printf 'state.done=Done\n' >> "$_tdmr/.kit/tracker.conf"
      printf 'list_cap=200\n' >> "$_tdmr/.kit/tracker.conf"
      cp "$_tde_repo/conformance/board-drift.sh" "$_tdmr/conformance/board-drift.sh"
      cp "$_tde_repo/conformance/backlog-lib.sh" "$_tdmr/conformance/backlog-lib.sh"
      cp "$_tde_repo/scripts/tracker-read.sh" "$_tdmr/scripts/tracker-read.sh"
      cp "$_tde_repo/scripts/tracker-conf.sh" "$_tdmr/scripts/tracker-conf.sh"
      printf '%s' "$_tdmr"
    }

    # _tde_adapter <root> <key> <status-id> <status-name> <inprogress-ops-file-or-""> <inreview-ops-file-or-"">
    # -- (re)writes the fake scripts/tracker-jira.sh the copied reader dispatches to (T8 pattern:
    # get-issue's key/status are BAKED, one anchor per call); list-in-states branches on the
    # resolved status id (3=In Progress, 10003=In Review) and `cat`s the named TRACKED ops/*.out
    # file, or answers empty when none is given.
    _tde_adapter() {
      _tda_root="$1"; _tda_key="$2"; _tda_sid="$3"; _tda_sname="$4"; _tda_ip="$5"; _tda_ir="$6"
      _tda_ops="$_tde_repo/conformance/fixtures/tracker-jira/ops"
      if [ -n "$_tda_ip" ]; then _tda_ip_cmd="cat \"$_tda_ops/$_tda_ip\""; else _tda_ip_cmd="printf ''"; fi
      if [ -n "$_tda_ir" ]; then _tda_ir_cmd="cat \"$_tda_ops/$_tda_ir\""; else _tda_ir_cmd="printf ''"; fi
      cat > "$_tda_root/scripts/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_tda_ops/status-ids-cloud.out"; exit 0 ;;
  get-issue) printf 'key\t$_tda_key\nstatus-id\t$_tda_sid\nstatus-name\t$_tda_sname\n'; exit 0 ;;
  list-in-states)
    case "\$6" in
      3) $_tda_ip_cmd ;;
      10003) $_tda_ir_cmd ;;
      *) printf '' ;;
    esac
    exit 0 ;;
esac
EOF
      chmod +x "$_tda_root/scripts/tracker-jira.sh"
    }

    # _tde_head -> the head sha of a throwaway one-commit git repo (never this clone's own history).
    _tde_head() {
      _tdh=$(mktemp -d)
      git -C "$_tdh" init -q
      git -C "$_tdh" -c user.email=tde@example.invalid -c user.name=tde commit -q --allow-empty -m "tde fixture"
      git -C "$_tdh" rev-parse HEAD
      rm -rf "$_tdh"
    }

    # _tde_priv -> ONE private scratch dir for this section's own GITHUB_OUTPUT files and
    # RUNNER_TEMP dirs (I-2 — every prior run leaked ~14 of these into the ambient tmp). An
    # explicit mktemp TEMPLATE under $d (this selftest's own temp dir, line ~764) — a no-arg
    # mktemp ignores TMPDIR on macOS. Removed at the end of this section below (I-2); $d's own
    # cleanup (or lack of one) is the selftest's, untouched here.
    _tde_priv=$(mktemp -d "$d/tde.XXXXXX")

    # _tde_step_block_env <marker> <file> -> tab-separated NAME<TAB>VALUE pairs, one per env: line
    # of the step named by <marker> in <file> (I-1: read from THAT file's own block, shipped or a
    # mutant, never hardcoded). Mapping:
    #   ${{ steps.<id>.outputs.<k> }} -> the value <k>= that step's own recorded GITHUB_OUTPUT
    #     carried (from $_tde_priv/out.<id>, written by _tde_run_step below); a step this harness
    #     never simulates (e.g. resolve) has no such file -> resolves to "" (an unset output).
    #   ${{ github.sha }}                  -> $_TDE_SHA, the ambient sha _tde_run_step was given.
    #   ${{ github.token }} / ${{ secrets.*}} -> a dummy value (no live credential exists here; the
    #     test doubles under _tde_adapter never inspect it).
    # Anything else -> FAILS LOUDLY to stderr (never silently skipped) and sets _TDE_ENV_BAD=1.
    _tde_step_block_env() {
      _tsbe_marker="$1"; _tsbe_file="$2"
      _tsbe_blk=$(_t2_step_block "$_tsbe_marker" "$_tsbe_file") || {
        echo "FAIL: TDE env — step '$_tsbe_marker' not found in $_tsbe_file" >&2
        _TDE_ENV_BAD=1
        return 1
      }
      _TDE_ENV_BAD=0
      _tsbe_inenv=0
      _tsbe_blkfile=$(mktemp "$_tde_priv/tsbe.XXXXXX")
      printf '%s\n' "$_tsbe_blk" > "$_tsbe_blkfile"
      while IFS= read -r _tsbe_line || [ -n "$_tsbe_line" ]; do
        case "$_tsbe_line" in
          '        env:') _tsbe_inenv=1; continue ;;
          '        run: '*) _tsbe_inenv=0 ;;
        esac
        [ "$_tsbe_inenv" = 1 ] || continue
        case "$_tsbe_line" in
          '          '*': '*) : ;;
          *) continue ;;
        esac
        _tsbe_rest=${_tsbe_line#'          '}
        _tsbe_key=${_tsbe_rest%%:*}
        _tsbe_val=${_tsbe_rest#*: }
        case "$_tsbe_val" in
          '${{ github.sha }}')
            _tsbe_v="$_TDE_SHA" ;;
          '${{ github.token }}')
            _tsbe_v="dummy-token" ;;
          '${{ secrets.'*'}}')
            _tsbe_v="dummy-secret" ;;
          '${{ steps.'*'.outputs.'*' }}')
            _tsbe_ref=${_tsbe_val#'${{ steps.'}
            _tsbe_ref=${_tsbe_ref%' }}'}
            _tsbe_id=${_tsbe_ref%%.outputs.*}
            _tsbe_k=${_tsbe_ref#*.outputs.}
            _tsbe_v=$(grep "^${_tsbe_k}=" "$_tde_priv/out.$_tsbe_id" 2>/dev/null | tail -1 | cut -d= -f2-)
            ;;
          *)
            echo "FAIL: TDE env — unrecognised value for $_tsbe_key in '$_tsbe_marker': $_tsbe_val" >&2
            _TDE_ENV_BAD=1
            _tsbe_v=""
            ;;
        esac
        printf '%s\t%s\n' "$_tsbe_key" "$_tsbe_v"
      done < "$_tsbe_blkfile"
      rm -f "$_tsbe_blkfile"
    }

    # _tde_if_run <marker> <file> -> sets _TDE_IF_RESULT: 1 (run), 0 (skip), or 2 on an if: form
    # outside the shipped grammar (steps.<id>.outputs.<k> != 'true', joined by ` && `), which FAILS
    # LOUDLY to stderr rather than silently running or silently skipping.
    _tde_if_run() {
      _tir_marker="$1"; _tir_file="$2"
      _TDE_IF_RESULT=1
      _tir_blk=$(_t2_step_block "$_tir_marker" "$_tir_file") || {
        echo "FAIL: TDE if — step '$_tir_marker' not found in $_tir_file" >&2
        _TDE_IF_RESULT=2
        return 2
      }
      _tir_line=$(printf '%s\n' "$_tir_blk" | grep '^        if: ' | head -1)
      [ -n "$_tir_line" ] || return 0
      _tir_expr=${_tir_line#'        if: '}
      _tir_clausefile=$(mktemp "$_tde_priv/if.XXXXXX")
      printf '%s\n' "$_tir_expr" | awk -F' [&][&] ' '{for(i=1;i<=NF;i++) print $i}' > "$_tir_clausefile"
      while read -r _tir_clause; do
        _tir_clause=$(printf '%s' "$_tir_clause" | sed -e 's/^ *//' -e 's/ *$//')
        [ -n "$_tir_clause" ] || continue
        case "$_tir_clause" in
          steps.*.outputs.*) ;;
          *)
            echo "FAIL: TDE if — unsupported clause in '$_tir_marker': $_tir_clause" >&2
            _TDE_IF_RESULT=2
            return 2 ;;
        esac
        case "$_tir_clause" in
          *" != 'true'") ;;
          *)
            echo "FAIL: TDE if — unsupported clause in '$_tir_marker': $_tir_clause" >&2
            _TDE_IF_RESULT=2
            return 2 ;;
        esac
        _tir_ref=${_tir_clause% != *}
        _tir_id=${_tir_ref#steps.}
        _tir_id=${_tir_id%%.outputs.*}
        _tir_k=${_tir_ref#*.outputs.}
        _tir_v=$(grep "^${_tir_k}=" "$_tde_priv/out.$_tir_id" 2>/dev/null | tail -1 | cut -d= -f2-)
        if [ "$_tir_v" = "true" ]; then _TDE_IF_RESULT=0; rm -f "$_tir_clausefile"; return 0; fi
      done < "$_tir_clausefile"
      rm -f "$_tir_clausefile"
      return 0
    }

    # _tde_run_step <marker> <id> <file> <root> <ambient-tsv> <sha> <body> -> the generic engine
    # (I-1): evaluates <marker>'s own if: FROM <file> (skip vs run, never hardcoded); when it runs,
    # builds the env from THAT SAME file's own env: block (I-1) plus <ambient-tsv> (this harness's
    # OWN testing seams — RUNNER_TEMP, BOARD_DRIFT_MERGED_ROWS — never declared in the YAML's env:
    # block; a real runner supplies RUNNER_TEMP ambiently on every step the same way), then runs the
    # (unchanged-by-mutants) run: BODY with `sh -ec` (M-3, matching the runner's `bash -e`), and
    # records the step's own GITHUB_OUTPUT under $_tde_priv/out.<id> for downstream steps' env/if
    # lookups. Sets _TDE_STEP_RC (0 on a genuine skip) and _TDE_STEP_OUT.
    # item 2: a real runner IMPLICITLY prepends `&& success()` to any custom `if:` that names no
    # status-check function (success/failure/cancelled/always) — none of this profile's ifs ever do
    # — so once an earlier step in the SAME job fails, every later step is skipped regardless of what
    # its own if: text says. _TDE_PRIOR_FAILED models that (reset per scenario by the caller); the
    # skip literal is distinct from "(skipped: if: false)" so a failure it hides from is still legible.
    _tde_run_step() {
      _trs_marker="$1"; _trs_id="$2"; _trs_file="$3"; _trs_root="$4"; _trs_ambient="$5"; _TDE_SHA="$6"; _trs_body="$7"
      _trs_go="$_tde_priv/out.$_trs_id"
      : > "$_trs_go"
      if [ "${_TDE_PRIOR_FAILED:-0}" = 1 ]; then
        _TDE_STEP_RC=0; _TDE_STEP_OUT="(skipped: a prior step in this job failed — implicit success())"; return 0
      fi
      _tde_if_run "$_trs_marker" "$_trs_file"
      _trs_run=$_TDE_IF_RESULT
      if [ "$_trs_run" = 2 ]; then _TDE_STEP_RC=2; _TDE_STEP_OUT="(if: evaluation failed)"; return 2; fi
      if [ "$_trs_run" = 0 ]; then _TDE_STEP_RC=0; _TDE_STEP_OUT="(skipped: if: false)"; return 0; fi
      _trs_envfile=$(mktemp "$_tde_priv/env.XXXXXX")
      {
        printf '%s\n' "$_trs_ambient"
        _tde_step_block_env "$_trs_marker" "$_trs_file"
      } > "$_trs_envfile"
      if [ "$_TDE_ENV_BAD" = 1 ]; then
        _TDE_STEP_RC=2; _TDE_STEP_OUT="(env: extraction failed)"; rm -f "$_trs_envfile"; return 2
      fi
      _TDE_STEP_RC=0
      _TDE_STEP_OUT=$(
        cd "$_trs_root" || exit 99
        while IFS='	' read -r _rk _rv || [ -n "$_rk" ]; do
          [ -n "$_rk" ] || continue
          export "$_rk=$_rv"
        done < "$_trs_envfile"
        export GITHUB_OUTPUT="$_trs_go"
        sh -ec "$_trs_body" 2>&1
      ) || _TDE_STEP_RC=$?
      rm -f "$_trs_envfile"
      [ "$_TDE_STEP_RC" = 0 ] || _TDE_PRIOR_FAILED=1
      return "$_TDE_STEP_RC"
    }

    # _tde_pipeline <root> <file> <sha> <merged-stub> -> runs the enum/read/arm steps, in order,
    # against <file>'s OWN if:/env: wiring (I-1). RUNNER_TEMP and BOARD_DRIFT_MERGED_ROWS are this
    # harness's own testing seams (§ _tde_run_step above); check() calls merged_rows() a SECOND
    # time on its own, so the arm step must see the SAME stub the enumerate step ran with. Sets
    # _TDE_ENUM_RC/_TDE_READ_RC/_TDE_READ_SKIP/_TDE_RECORD/_TDE_ARM_RC/_TDE_ARM_RAN/_TDE_ARM_OUT/
    # _TDE_RUNNER_TEMP.
    _tde_pipeline() {
      _tp_root="$1"; _tp_file="$2"; _tp_sha="$3"; _tp_stub="$4"
      _TDE_PRIOR_FAILED=0
      _tde_rt=$(mktemp -d "$_tde_priv/rt.XXXXXX")
      _TDE_RUNNER_TEMP="$_tde_rt"

      _tp_amb=$(printf 'RUNNER_TEMP\t%s\nBOARD_DRIFT_MERGED_ROWS\t%s\n' "$_tde_rt" "$_tp_stub")
      _tde_run_step "Enumerate PRs merged in the drift window (no secret)" enum "$_tp_file" "$_tp_root" "$_tp_amb" "$_tp_sha" "$_tde_enum_body" || :
      _TDE_ENUM_RC=$_TDE_STEP_RC

      _tp_amb=$(printf 'RUNNER_TEMP\t%s\nGITHUB_SHA\t%s\n' "$_tde_rt" "$_tp_sha")
      _tde_run_step "Read the tracker's in-flight lists" read "$_tp_file" "$_tp_root" "$_tp_amb" "$_tp_sha" "$_tde_read_body" || :
      _TDE_READ_RC=$_TDE_STEP_RC
      _TDE_READ_SKIP=$(grep '^skip=' "$_tde_priv/out.read" 2>/dev/null | tail -1 | cut -d= -f2-)
      _TDE_RECORD=$(grep '^record_path=' "$_tde_priv/out.read" 2>/dev/null | tail -1 | cut -d= -f2-)

      _tp_amb=$(printf 'RUNNER_TEMP\t%s\nBOARD_DRIFT_MERGED_ROWS\t%s\n' "$_tde_rt" "$_tp_stub")
      _tde_run_step "Run board-drift's tracker arm from base" arm "$_tp_file" "$_tp_root" "$_tp_amb" "$_tp_sha" "$_tde_arm_body" || :
      _TDE_ARM_RC=$_TDE_STEP_RC
      _TDE_ARM_OUT=$_TDE_STEP_OUT
      case "$_TDE_STEP_OUT" in
        '(skipped: if: false)') _TDE_ARM_RAN=0 ;;
        *) _TDE_ARM_RAN=1 ;;
      esac
    }

    # leg 1: Drifted — merged 7 AB-1; the anchor IS the drifted row.
    _tde_r1=$(_tde_mkroot)
    _tde_adapter "$_tde_r1" AB-1 3 "In Progress" list-cloud-inprogress.out ""
    _tde_h1=$(_tde_head)
    _tde_pipeline "$_tde_r1" "$_tj_atg" "$_tde_h1" "printf '7 AB-1\n'"
    if [ "$_TDE_ENUM_RC" = 0 ] && [ "$_TDE_READ_RC" = 0 ] && [ "$_TDE_READ_SKIP" = "false" ] \
        && [ "$_TDE_ARM_RC" = 1 ] && printf '%s\n' "$_TDE_ARM_OUT" | grep -qF 'AB-1 merged (PR #7)'; then
      echo "PASS: TDE/leg1: a merged anchor still in-flight on the tracker -> DRIFT (rc1, naming AB-1 merged (PR #7))"
    else
      echo "FAIL: TDE/leg1: enum=$_TDE_ENUM_RC read=$_TDE_READ_RC skip=$_TDE_READ_SKIP arm=$_TDE_ARM_RC out='$_TDE_ARM_OUT' rec='$(cat "$_TDE_RECORD" 2>&1 | tr '\n' ';')'"; st=1
    fi

    # leg 2: Clean — AB-1 resolved Done, both in-flight lists empty -> every step rc0.
    _tde_r2=$(_tde_mkroot)
    _tde_adapter "$_tde_r2" AB-1 10004 "Done" "" ""
    _tde_h2=$(_tde_head)
    _tde_pipeline "$_tde_r2" "$_tj_atg" "$_tde_h2" "printf '7 AB-1\n'"
    if [ "$_TDE_ENUM_RC" = 0 ] && [ "$_TDE_READ_RC" = 0 ] && [ "$_TDE_READ_SKIP" = "false" ] \
        && [ "$_TDE_ARM_RC" = 0 ] && printf '%s\n' "$_TDE_ARM_OUT" | grep -qF 'no merged PR is still in-flight'; then
      echo "PASS: TDE/leg2: AB-1 Done, empty in-flight lists -> every step rc0 (no drift)"
    else
      echo "FAIL: TDE/leg2: enum=$_TDE_ENUM_RC read=$_TDE_READ_RC skip=$_TDE_READ_SKIP arm=$_TDE_ARM_RC out='$_TDE_ARM_OUT'"; st=1
    fi

    # leg 3: Non-anchor drift — merged 7 AB-2 (Done, status 10004) then 8 AB-1; AB-2 is the anchor
    # tried FIRST (candidate order follows the merge order in $MERGED) and binds Done; AB-1 (merged,
    # the SECOND, non-anchor candidate) shows drifted on the SAME in-progress list -> red naming
    # AB-1, and NOT AB-2, proving the multi-row detection catches a merged key beyond the one
    # candidate the reader actually bound. list-cloud-inprogress.out is the only TRACKED two-id
    # list-in-states fixture (AB-1, AB-4); AB-2 is used as the anchor here (a fresh key never itself
    # a member of that list) rather than AB-4, because AB-4 as the bound anchor would itself have to
    # appear on list-cloud-inprogress.out to satisfy its own R6 race check — a Done anchor carries no
    # such requirement (Done is not one of the two requested states, in-progress/in-review), so a
    # Done AB-2 binds cleanly while AB-1 alone drifts on the in-progress list.
    _tde_r3=$(_tde_mkroot)
    _tde_adapter "$_tde_r3" AB-2 10004 "Done" list-cloud-inprogress.out ""
    _tde_h3=$(_tde_head)
    _tde_pipeline "$_tde_r3" "$_tj_atg" "$_tde_h3" "printf '7 AB-2\n8 AB-1\n'"
    if [ "$_TDE_ENUM_RC" = 0 ] && [ "$_TDE_READ_RC" = 0 ] && [ "$_TDE_READ_SKIP" = "false" ] \
        && [ "$_TDE_ARM_RC" = 1 ] && printf '%s\n' "$_TDE_ARM_OUT" | grep -qF 'AB-1 merged (PR #8)' \
        && ! printf '%s\n' "$_TDE_ARM_OUT" | grep -qF 'AB-2 merged' \
        && grep -qxF 'requested AB-2' "$_TDE_RECORD" 2>/dev/null; then
      echo "PASS: TDE/leg3: the anchor (AB-2, tried first, Done) binds, and a NON-anchor merged row (AB-1, tried second) drifts on the SAME in-progress list -> rc1 naming AB-1, not AB-2"
    else
      echo "FAIL: TDE/leg3: enum=$_TDE_ENUM_RC read=$_TDE_READ_RC skip=$_TDE_READ_SKIP arm=$_TDE_ARM_RC out='$_TDE_ARM_OUT' rec='$(cat "$_TDE_RECORD" 2>&1 | tr '\n' ';')'"; st=1
    fi

    # leg 4: no in-project key — merged 7 ZZ-1 (ZZ is not this tracker's project) -> the read step's
    # own candidate-filter finds nothing to check; no adapter call, no record, and the drift step's
    # OWN if: (steps.read.outputs.skip != 'true') now genuinely evaluates false and skips it (I-1;
    # leg 8 below proves that evaluation is read from the file, not assumed).
    _tde_r4=$(_tde_mkroot)
    _tde_h4=$(_tde_head)
    _tde_pipeline "$_tde_r4" "$_tj_atg" "$_tde_h4" "printf '7 ZZ-1\n'"
    if [ "$_TDE_ENUM_RC" = 0 ] && [ "$_TDE_READ_RC" = 0 ] && [ "$_TDE_READ_SKIP" = "true" ] && [ -z "$_TDE_RECORD" ] \
        && [ "$_TDE_ARM_RAN" = 0 ] && [ ! -e "$_TDE_RUNNER_TEMP/tbd-record.txt" ]; then
      echo "PASS: TDE/leg4: no merged PR carries this project's key -> read step rc0, skip=true, no record written, the drift step's own if: skips it"
    else
      echo "FAIL: TDE/leg4: read=$_TDE_READ_RC skip=$_TDE_READ_SKIP record='$_TDE_RECORD' arm_ran=$_TDE_ARM_RAN"; st=1
    fi

    # leg 5: cannot enumerate — the stub exits 2 -> the enumerate step itself exits non-zero.
    _TDE_PRIOR_FAILED=0
    _tde_r5=$(_tde_mkroot)
    _tde_h5=$(_tde_head)
    _tp_amb=$(printf 'RUNNER_TEMP\t%s\nBOARD_DRIFT_MERGED_ROWS\texit 2\n' "$(mktemp -d "$_tde_priv/rt.XXXXXX")")
    _tde_run_step "Enumerate PRs merged in the drift window (no secret)" enum "$_tj_atg" "$_tde_r5" "$_tp_amb" "$_tde_h5" "$_tde_enum_body" || :
    if [ "$_TDE_STEP_RC" != 0 ] && printf '%s\n' "$_TDE_STEP_OUT" | grep -qF 'cannot enumerate merged PRs'; then
      echo "PASS: TDE/leg5: merged_rows cannot enumerate (stub exit 2) -> the enumerate step exits non-zero, naming 'cannot enumerate merged PRs' (M-b)"
    else
      echo "FAIL: TDE/leg5: enum rc=$_TDE_STEP_RC out='$_TDE_STEP_OUT' (wanted non-zero rc + 'cannot enumerate merged PRs')"; st=1
    fi

    # leg 6: mutant — a copy of the profile without the drift step's SEAM_RECORD: env line. The
    # run: BODY TEXT is unchanged by this mutant (env: wiring, not the shell body, carries
    # SEAM_RECORD) — so re-running leg 1's bound scenario against THIS file (I-1: the engine reads
    # env: from the file it is given, so SEAM_RECORD is never exported here, exactly as an env-less
    # step would behave) must lose the "AB-1 merged (PR #7)" sentence entirely, and board-drift's
    # own reported rc must differ from leg 1's DRIFT (1).
    _tde_mut6=$(mktemp -d)
    sed '/^          SEAM_RECORD: /d' "$_tj_atg" > "$_tde_mut6/m.yml"
    if cmp -s "$_tde_mut6/m.yml" "$_tj_atg"; then
      echo "FAIL: TDE/leg6 setup — the planted copy did not differ from its source"; st=1
    fi
    _tde_mut6_blk=$(_t2_step_block "Run board-drift's tracker arm from base" "$_tde_mut6/m.yml")
    if printf '%s\n' "$_tde_mut6_blk" | grep -qF 'SEAM_RECORD:'; then
      echo "FAIL: TDE/leg6 setup — the mutant still carries SEAM_RECORD:"; st=1
    fi
    _tde_pipeline "$_tde_r1" "$_tde_mut6/m.yml" "$_tde_h1" "printf '7 AB-1\n'"
    if printf '%s\n' "$_TDE_ARM_OUT" | grep -qF 'board-drift rc=3' \
        && ! printf '%s\n' "$_TDE_ARM_OUT" | grep -qF 'AB-1 merged (PR #7)'; then
      echo "PASS: TDE/leg6: dropping the drift step's SEAM_RECORD env removes the DRIFT sentence entirely (board-drift rc=3, not 1)"
    else
      echo "FAIL: TDE/leg6: the DRIFT sentence or rc=1 survived without SEAM_RECORD (out='$_TDE_ARM_OUT')"; st=1
    fi
    rm -rf "$_tde_mut6" 2>/dev/null || true

    # leg 8: mutant — a copy of the profile whose drift step's if: drops the
    # "&& steps.read.outputs.skip != 'true'" clause, leaving only the resolve check. Under leg 4's
    # OWN inputs (no in-project key -> read skip=true), this mutant's drift step now RUNS (I-1's
    # if: evaluation is read from the FILE, never assumed) — with no record, it reds — proving leg
    # 4's skip above is actually driven by the if: text, not by this harness's own say-so.
    _tde_mut8=$(mktemp -d)
    sed "s/^        if: steps.resolve.outputs.skip != 'true' \&\& steps.read.outputs.skip != 'true'\$/        if: steps.resolve.outputs.skip != 'true'/" "$_tj_atg" > "$_tde_mut8/m.yml"
    if cmp -s "$_tde_mut8/m.yml" "$_tj_atg"; then
      echo "FAIL: TDE/leg8 setup — the planted copy did not differ from its source"; st=1
    fi
    _tde_mut8_blk=$(_t2_step_block "Run board-drift's tracker arm from base" "$_tde_mut8/m.yml")
    if printf '%s\n' "$_tde_mut8_blk" | grep -qF "steps.read.outputs.skip"; then
      echo "FAIL: TDE/leg8 setup — the mutant still carries the read.skip clause"; st=1
    fi
    _tde_r8=$(_tde_mkroot)
    _tde_h8=$(_tde_head)
    _tde_pipeline "$_tde_r8" "$_tde_mut8/m.yml" "$_tde_h8" "printf '7 ZZ-1\n'"
    if [ "$_TDE_READ_SKIP" = "true" ] && [ "$_TDE_ARM_RAN" = 1 ] && [ "$_TDE_ARM_RC" != 0 ] \
        && printf '%s\n' "$_TDE_ARM_OUT" | grep -qF 'board-drift rc='; then
      echo "PASS: TDE/leg8: dropping the drift step's read.skip if: clause makes it run even though the read step skipped (no record) -> it reds, naming 'board-drift rc=' (M-b: a harness rc 2 cannot pass this leg)"
    else
      echo "FAIL: TDE/leg8: read_skip=$_TDE_READ_SKIP arm_ran=$_TDE_ARM_RAN arm_rc=$_TDE_ARM_RC out='$_TDE_ARM_OUT'"; st=1
    fi
    rm -rf "$_tde_mut8" "$_tde_r8" 2>/dev/null || true

    # item 2 (I-2 follow-up): the RESOLVE step itself, never simulated at all before this round.
    _tde_resolve_marker="Resolve backend from the .kit/tracker.conf (drift; skip-on-md, error on malformed)"
    _tde_resolve_body=$(_t2_run_body "$_tde_resolve_marker" "$_tj_atg")

    # R1: no .kit/tracker.conf at all -> resolve rc0 skip=true; the enumerate/read steps' OWN if:
    # (read from the file, same generic engine as legs 1-8) must not run them.
    _TDE_PRIOR_FAILED=0
    _tde_rR1=$(_tde_mkroot)
    rm -f "$_tde_rR1/.kit/tracker.conf"
    _tde_hR1=$(_tde_head)
    _tp_amb=$(printf 'RUNNER_TEMP\t%s\n' "$(mktemp -d "$_tde_priv/rt.XXXXXX")")
    _tde_run_step "$_tde_resolve_marker" resolve "$_tj_atg" "$_tde_rR1" "$_tp_amb" "$_tde_hR1" "$_tde_resolve_body" || :
    _TDE_R1_RC=$_TDE_STEP_RC
    _TDE_R1_SKIP=$(grep '^skip=' "$_tde_priv/out.resolve" 2>/dev/null | tail -1 | cut -d= -f2-)
    _tde_run_step "Enumerate PRs merged in the drift window (no secret)" enum "$_tj_atg" "$_tde_rR1" "$_tp_amb" "$_tde_hR1" "$_tde_enum_body" || :
    _TDE_R1_ENUM_OUT=$_TDE_STEP_OUT
    _tde_run_step "Read the tracker's in-flight lists" read "$_tj_atg" "$_tde_rR1" "$_tp_amb" "$_tde_hR1" "$_tde_read_body" || :
    _TDE_R1_READ_OUT=$_TDE_STEP_OUT
    if [ "$_TDE_R1_RC" = 0 ] && [ "$_TDE_R1_SKIP" = "true" ] \
        && [ "$_TDE_R1_ENUM_OUT" = "(skipped: if: false)" ] && [ "$_TDE_R1_READ_OUT" = "(skipped: if: false)" ]; then
      echo "PASS: TDE/R1: no .kit/tracker.conf -> resolve rc0 skip=true, enumerate/read steps do not run"
    else
      echo "FAIL: TDE/R1: rc=$_TDE_R1_RC skip=$_TDE_R1_SKIP enum='$_TDE_R1_ENUM_OUT' read='$_TDE_R1_READ_OUT'"; st=1
    fi

    # R2: backend=md -> same shape as R1.
    _TDE_PRIOR_FAILED=0
    _tde_rR2=$(_tde_mkroot)
    {
      printf 'version=1\n'
      printf 'backend=md\n'
      printf 'base_url=https://example.atlassian.net\n'
      printf 'project=AB\n'
    } > "$_tde_rR2/.kit/tracker.conf"
    _tde_hR2=$(_tde_head)
    _tp_amb=$(printf 'RUNNER_TEMP\t%s\n' "$(mktemp -d "$_tde_priv/rt.XXXXXX")")
    _tde_run_step "$_tde_resolve_marker" resolve "$_tj_atg" "$_tde_rR2" "$_tp_amb" "$_tde_hR2" "$_tde_resolve_body" || :
    _TDE_R2_RC=$_TDE_STEP_RC
    _TDE_R2_SKIP=$(grep '^skip=' "$_tde_priv/out.resolve" 2>/dev/null | tail -1 | cut -d= -f2-)
    _tde_run_step "Enumerate PRs merged in the drift window (no secret)" enum "$_tj_atg" "$_tde_rR2" "$_tp_amb" "$_tde_hR2" "$_tde_enum_body" || :
    _TDE_R2_ENUM_OUT=$_TDE_STEP_OUT
    _tde_run_step "Read the tracker's in-flight lists" read "$_tj_atg" "$_tde_rR2" "$_tp_amb" "$_tde_hR2" "$_tde_read_body" || :
    _TDE_R2_READ_OUT=$_TDE_STEP_OUT
    if [ "$_TDE_R2_RC" = 0 ] && [ "$_TDE_R2_SKIP" = "true" ] \
        && [ "$_TDE_R2_ENUM_OUT" = "(skipped: if: false)" ] && [ "$_TDE_R2_READ_OUT" = "(skipped: if: false)" ]; then
      echo "PASS: TDE/R2: backend=md -> resolve rc0 skip=true, enumerate/read steps do not run"
    else
      echo "FAIL: TDE/R2: rc=$_TDE_R2_RC skip=$_TDE_R2_SKIP enum='$_TDE_R2_ENUM_OUT' read='$_TDE_R2_READ_OUT'"; st=1
    fi

    # R3: a present-but-malformed conf -> resolve rc!=0, naming 'tracker-board-drift: malformed';
    # downstream steps do not run.
    _TDE_PRIOR_FAILED=0
    _tde_rR3=$(_tde_mkroot)
    printf 'this-has-no-equals\n' > "$_tde_rR3/.kit/tracker.conf"
    _tde_hR3=$(_tde_head)
    _tp_amb=$(printf 'RUNNER_TEMP\t%s\n' "$(mktemp -d "$_tde_priv/rt.XXXXXX")")
    _tde_run_step "$_tde_resolve_marker" resolve "$_tj_atg" "$_tde_rR3" "$_tp_amb" "$_tde_hR3" "$_tde_resolve_body" || :
    _TDE_R3_RC=$_TDE_STEP_RC
    _TDE_R3_OUT=$_TDE_STEP_OUT
    _tde_run_step "Enumerate PRs merged in the drift window (no secret)" enum "$_tj_atg" "$_tde_rR3" "$_tp_amb" "$_tde_hR3" "$_tde_enum_body" || :
    _TDE_R3_ENUM_OUT=$_TDE_STEP_OUT
    _tde_run_step "Read the tracker's in-flight lists" read "$_tj_atg" "$_tde_rR3" "$_tp_amb" "$_tde_hR3" "$_tde_read_body" || :
    _TDE_R3_READ_OUT=$_TDE_STEP_OUT
    if [ "$_TDE_R3_RC" != 0 ] && printf '%s\n' "$_TDE_R3_OUT" | grep -qF 'tracker-board-drift: malformed' \
        && [ "$_TDE_R3_ENUM_OUT" = "(skipped: a prior step in this job failed — implicit success())" ] \
        && [ "$_TDE_R3_READ_OUT" = "(skipped: a prior step in this job failed — implicit success())" ]; then
      echo "PASS: TDE/R3: a present-but-malformed .kit/tracker.conf -> resolve rc!=0 naming 'tracker-board-drift: malformed', enumerate/read steps do not run"
    else
      echo "FAIL: TDE/R3: rc=$_TDE_R3_RC out='$_TDE_R3_OUT' enum='$_TDE_R3_ENUM_OUT' read='$_TDE_R3_READ_OUT'"; st=1
    fi

    # R3 mutant: the drift job's malformed branch rewritten to silently skip — proves R3 has teeth.
    # Located dynamically off the drift job's OWN (distinct) error title text, never the PR job's
    # near-identical block ('tracker-board-gates: malformed' — a different string).
    _tde_dmL=$(grep -n 'tracker-board-drift: malformed' "$_tj_atg" | head -1 | cut -d: -f1)
    if [ -n "$_tde_dmL" ]; then
      _tde_dmStart=$((_tde_dmL - 1))
      _tde_dmEnd=$((_tde_dmL + 2))
      _tde_mutR3=$(mktemp -d)
      awk -v s="$_tde_dmStart" -v e="$_tde_dmEnd" '
        NR==s { print "          echo \"skip=true\" >> \"$GITHUB_OUTPUT\"; exit 0  # MUTANT (was: error+exit1)"; next }
        NR>s && NR<=e { next }
        { print }
      ' "$_tj_atg" > "$_tde_mutR3/m.yml"
      if cmp -s "$_tde_mutR3/m.yml" "$_tj_atg"; then
        echo "FAIL: TDE/R3-mutant setup — the planted copy did not differ from its source"; st=1
      fi
      if ! grep -qF 'A .kit/tracker.conf exists but did not validate' "$_tde_mutR3/m.yml" \
          && grep -qF 'A .kit/tracker.conf exists on base but did not validate' "$_tde_mutR3/m.yml"; then
        echo "PASS: TDE/R3-mutant setup — only the drift job's malformed branch was rewritten; the PR job's resolve step is untouched"
      else
        echo "FAIL: TDE/R3-mutant setup — mutation touched the wrong block, or missed it"; st=1
      fi
      _TDE_PRIOR_FAILED=0
      _tde_rR3m=$(_tde_mkroot)
      printf 'this-has-no-equals\n' > "$_tde_rR3m/.kit/tracker.conf"
      _tde_hR3m=$(_tde_head)
      _tp_amb=$(printf 'RUNNER_TEMP\t%s\n' "$(mktemp -d "$_tde_priv/rt.XXXXXX")")
      _tde_resolve_body_mut=$(_t2_run_body "$_tde_resolve_marker" "$_tde_mutR3/m.yml")
      _tde_run_step "$_tde_resolve_marker" resolve "$_tde_mutR3/m.yml" "$_tde_rR3m" "$_tp_amb" "$_tde_hR3m" "$_tde_resolve_body_mut" || :
      _TDE_R3M_RC=$_TDE_STEP_RC
      _TDE_R3M_SKIP=$(grep '^skip=' "$_tde_priv/out.resolve" 2>/dev/null | tail -1 | cut -d= -f2-)
      if [ "$_TDE_R3M_RC" = 0 ] && [ "$_TDE_R3M_SKIP" = "true" ]; then
        echo "PASS: TDE/R3-mutant: rewriting the malformed branch to skip=true;exit0 flips it to rc0/skip=true — R3's own assertion (rc!=0 + the malformed sentence) would FAIL against this file, proving R3 has teeth"
      else
        echo "FAIL: TDE/R3-mutant: expected the mutant to silently skip (rc0 skip=true), got rc=$_TDE_R3M_RC skip=$_TDE_R3M_SKIP"; st=1
      fi
      rm -rf "$_tde_mutR3" "$_tde_rR3m" 2>/dev/null || true
    else
      echo "FAIL: TDE/R3-mutant setup — could not locate the drift job's malformed branch by its error title"; st=1
    fi

    rm -rf "$_tde_r1" "$_tde_r2" "$_tde_r3" "$_tde_r4" "$_tde_r5" "$_tde_rR1" "$_tde_rR2" "$_tde_rR3" "$_tde_priv" 2>/dev/null || true
    if [ ! -e "$_tde_priv" ]; then
      echo "PASS: TDE/I-2: the private GITHUB_OUTPUT/RUNNER_TEMP scratch dir is gone after cleanup"
    else
      echo "FAIL: TDE/I-2: $_tde_priv still exists after cleanup — temp files leaked"; st=1
    fi
    unset -f _tde_mkroot _tde_adapter _tde_head _tde_step_block_env _tde_if_run _tde_run_step _tde_pipeline

    # ── TRACKER-PREFLIGHT-TIER-CARD (lane 3) — the runner knob and the from-runner preflight step.
    # (1) both jobs take their runner from the KIT_TRACKER_RUNNER repository variable (design §7);
    # (2) the drift job's `Preflight from this runner` step sits AFTER resolve and BEFORE enum
    # (enum's rc 1 can never skip it), runs only under workflow_dispatch, holds the two tracker
    # secrets (hygiene: the read step and this step are the ONLY two), and is EXECUTED here against
    # a stub contract that prints a canned card: a FAIL card still ends rc 0, notices appear only
    # for lines that are not PASS, a line off the card grammar is never echoed (S-6), and a
    # reach-here FAIL adds the runner cure and the click path. Text-presence proves the shape; the
    # run proves the step behaves.
    _pf_runs_on="    runs-on: \${{ vars.KIT_TRACKER_RUNNER || 'ubuntu-latest' }}"
    for _pf_job in tracker-board-gates tracker-board-drift; do
      if _tj_job_block "$_tj_atg" "$_pf_job" | grep -qxF "$_pf_runs_on"; then
        echo "PASS: TPF/runs-on: $_pf_job takes its runner from vars.KIT_TRACKER_RUNNER (default ubuntu-latest)"
      else
        echo "FAIL: TPF/runs-on: $_pf_job does not use runs-on: \${{ vars.KIT_TRACKER_RUNNER || 'ubuntu-latest' }} — an adopter behind an IP allowlist has no runner knob"; st=1
      fi
    done
    _pf_priv=$(mktemp -d "$d/pf.XXXXXX")
    sed "s/vars.KIT_TRACKER_RUNNER || 'ubuntu-latest'/'ubuntu-latest'/" "$_tj_atg" > "$_pf_priv/m-runs-on.yml"
    if cmp -s "$_pf_priv/m-runs-on.yml" "$_tj_atg"; then
      echo "FAIL: TPF/runs-on mutant setup — the planted copy did not differ from its source"; st=1
    elif _tj_job_block "$_pf_priv/m-runs-on.yml" tracker-board-drift | grep -qxF "$_pf_runs_on"; then
      echo "FAIL: TPF/runs-on mutant (hard-coded ubuntu-latest) was not caught"; st=1
    else
      echo "PASS: TPF/runs-on mutant (hard-coded ubuntu-latest) is caught"
    fi

    _pf_marker='Preflight from this runner'
    _pf_blk=$(_t2_step_block "$_pf_marker" "$_tj_atg" || true)
    _pf_body=$(_t2_run_body "$_pf_marker" "$_tj_atg" || true)
    if [ -n "$_pf_blk" ] && [ -n "$_pf_body" ]; then
      echo "PASS: TPF/liveness: the drift job's preflight step and its run: body extract non-empty"
    else
      echo "FAIL: TPF/liveness: the drift job has no 'Preflight from this runner' step (or an empty run: body)"; st=1
    fi

    # order: resolve < preflight < enum, inside the drift job.
    _pf_drift=$(_tj_job_block "$_tj_atg" tracker-board-drift | grep -v '^[[:space:]]*#')
    _pf_n_res=$(printf '%s\n' "$_pf_drift" | grep -nF 'id: resolve' | head -1 | cut -d: -f1)
    _pf_n_pf=$(printf '%s\n' "$_pf_drift" | grep -nF -- "- name: $_pf_marker" | head -1 | cut -d: -f1)
    _pf_n_enum=$(printf '%s\n' "$_pf_drift" | grep -nF 'id: enum' | head -1 | cut -d: -f1)
    if [ -n "$_pf_n_res" ] && [ -n "$_pf_n_pf" ] && [ -n "$_pf_n_enum" ] \
        && [ "$_pf_n_res" -lt "$_pf_n_pf" ] && [ "$_pf_n_pf" -lt "$_pf_n_enum" ]; then
      echo "PASS: TPF/order: the preflight step sits after resolve and before enum (enum's rc 1 cannot skip it)"
    else
      echo "FAIL: TPF/order: the preflight step must sit after 'id: resolve' and before 'id: enum' (resolve=$_pf_n_res preflight=$_pf_n_pf enum=$_pf_n_enum)"; st=1
    fi

    # condition: workflow_dispatch only, never under schedule; pinned verbatim and then evaluated.
    _pf_if=$(printf '%s\n' "$_pf_blk" | grep '^        if: ' | head -1)
    _pf_if_want="        if: github.event_name == 'workflow_dispatch' && steps.resolve.outputs.skip != 'true' && steps.resolve.outputs.backend == 'jira'"
    if [ "$_pf_if" = "$_pf_if_want" ]; then
      echo "PASS: TPF/if: the preflight step's if: is workflow_dispatch && resolve not skipped && backend jira (verbatim)"
    else
      echo "FAIL: TPF/if: the preflight step's if: is not the pinned form; got '$_pf_if'"; st=1
    fi
    for _pf_ev in schedule workflow_dispatch; do
      case "$_pf_if" in
        *"github.event_name == '$_pf_ev'"*) _pf_ran=1 ;;
        *) _pf_ran=0 ;;
      esac
      if [ "$_pf_ev" = schedule ] && [ "$_pf_ran" = 0 ]; then
        echo "PASS: TPF/if: the preflight step is absent under schedule (no daily noise)"
      elif [ "$_pf_ev" = workflow_dispatch ] && [ "$_pf_ran" = 1 ]; then
        echo "PASS: TPF/if: the preflight step is present under workflow_dispatch"
      else
        echo "FAIL: TPF/if: under $_pf_ev the preflight step's run decision is wrong (ran=$_pf_ran)"; st=1
      fi
    done
    # decision by backend: the step runs for jira only (the card is Jira-specific); linear and any other backend skip it.
    for _pf_be in jira linear github; do
      case "$_pf_if" in
        *"steps.resolve.outputs.backend == '$_pf_be'"*) _pf_ran=1 ;;
        *) _pf_ran=0 ;;
      esac
      if [ "$_pf_be" = jira ] && [ "$_pf_ran" = 1 ]; then
        echo "PASS: TPF/if: backend jira runs the preflight step"
      elif [ "$_pf_be" != jira ] && [ "$_pf_ran" = 0 ]; then
        echo "PASS: TPF/if: backend $_pf_be skips the preflight step"
      else
        echo "FAIL: TPF/if: under backend $_pf_be the preflight step's run decision is wrong (ran=$_pf_ran)"; st=1
      fi
    done

    # secrets: both credentials on this step, exactly as the read step has them; and the drift job
    # holds a tracker secret ONLY in those two steps.
    if printf '%s\n' "$_pf_blk" | grep -qF 'KIT_TRACKER_USER: ${{ secrets.KIT_TRACKER_USER }}' \
        && printf '%s\n' "$_pf_blk" | grep -qF 'KIT_TRACKER_TOKEN: ${{ secrets.KIT_TRACKER_TOKEN }}'; then
      echo "PASS: TPF/env: the preflight step carries KIT_TRACKER_USER and KIT_TRACKER_TOKEN from secrets"
    else
      echo "FAIL: TPF/env: the preflight step does not carry both tracker secrets in its env"; st=1
    fi
    _pf_sec_total=$(printf '%s\n' "$_tds_drift_blk" | grep -cF 'secrets.KIT_TRACKER_' || true)
    _pf_sec_two=$(( $(printf '%s\n' "$_tds_read_blk" | grep -cF 'secrets.KIT_TRACKER_' || true) + $(printf '%s\n' "$_pf_blk" | grep -cF 'secrets.KIT_TRACKER_' || true) ))
    if [ "$_pf_sec_total" -gt 0 ] && [ "$_pf_sec_total" = "$_pf_sec_two" ]; then
      echo "PASS: TPF/secrets: the drift job holds a tracker secret only in its read step and its preflight step (hygiene, S-1)"
    else
      echo "FAIL: TPF/secrets: the drift job carries a tracker secret outside the read and preflight steps (job=$_pf_sec_total two-steps=$_pf_sec_two)"; st=1
    fi

    # the executed leg. _pf_exec <body> <stub-script-file> -> runs <body> with `sh -ec` in a root
    # whose conformance/tracker-contract.sh is the stub; sets _PF_RC and _PF_OUT.
    _pf_exec() {
      _pfe_root=$(mktemp -d "$_pf_priv/root.XXXXXX")
      mkdir -p "$_pfe_root/conformance" "$_pfe_root/rt"
      cp "$2" "$_pfe_root/conformance/tracker-contract.sh"
      _PF_RC=0
      _PF_OUT=$(
        cd "$_pfe_root" || exit 99
        RUNNER_TEMP="$_pfe_root/rt" GITHUB_OUTPUT="$_pfe_root/out" KIT_TRACKER_USER=u KIT_TRACKER_TOKEN=t sh -ec "$1" 2>&1
      ) || _PF_RC=$?
    }
    {
      printf '#!/bin/sh\n'
      printf 'printf "card\\tINFO\\thost.example - project AB - as ci - read-only\\n"\n'
      printf 'printf "deployment\\tPASS\\tCloud\\n"\n'
      printf 'printf "reach-here\\tFAIL\\tthe site did not answer from this machine\\n"\n'
      printf 'printf "reach-ci\\tINFO\\tCI reachability is measured on the runner\\n"\n'
      printf 'printf "claim-tier\\tTIER\\tconvention\\n"\n'
      printf 'printf "free text that is off the card grammar SECRETLEAK\\n"\n'
      printf 'printf "bogus\\tMAYBE\\toff-enum verdict SECRETLEAK\\n"\n'
      printf 'printf "permissions\\tPASS\\tbrowse only\\n"\n'
      printf 'printf "CARD\\tFAIL\\t1 FAIL - 0 UNVERIFIED\\n"\n'
      printf 'exit 1\n'
    } > "$_pf_priv/stub-fail.sh"
    {
      printf '#!/bin/sh\n'
      printf 'printf "card\\tINFO\\thost.example - project AB - as ci - read-only\\n"\n'
      printf 'printf "deployment\\tPASS\\tCloud\\n"\n'
      printf 'printf "reach-here\\tPASS\\tthe site answered\\n"\n'
      printf 'printf "CARD\\tPASS\\t0 FAIL - 0 UNVERIFIED\\n"\n'
      printf 'exit 0\n'
    } > "$_pf_priv/stub-pass.sh"
    printf '#!/bin/sh\nexit 2\n' > "$_pf_priv/stub-none.sh"

    if [ -n "$_pf_body" ]; then
      _pf_exec "$_pf_body" "$_pf_priv/stub-fail.sh"
      _pf_notices=$(printf '%s\n' "$_PF_OUT" | grep -c '^::notice title=tracker preflight: ' || true)
      if [ "$_PF_RC" = 0 ]; then
        echo "PASS: TPF/exec: a FAIL card still ends the step rc 0 (it never fails the job)"
      else
        echo "FAIL: TPF/exec: a FAIL card ended the step rc $_PF_RC — the preflight must never fail the job"; st=1
      fi
      # card, reach-here, reach-ci, claim-tier, CARD = 5 non-PASS lines, plus the runner-cure notice.
      if [ "$_pf_notices" = 6 ] \
          && printf '%s\n' "$_PF_OUT" | grep -qF '::notice title=tracker preflight: reach-here::FAIL ' \
          && printf '%s\n' "$_PF_OUT" | grep -qF '::notice title=tracker preflight: claim-tier::TIER ' \
          && printf '%s\n' "$_PF_OUT" | grep -qF '::notice title=tracker preflight: CARD::FAIL '; then
        echo "PASS: TPF/exec: a notice for every non-PASS card line (5) plus the runner cure (1), titled by the line's name"
      else
        echo "FAIL: TPF/exec: expected 6 preflight notices (5 non-PASS lines + the runner cure), got $_pf_notices: $_PF_OUT"; st=1
      fi
      if printf '%s\n' "$_PF_OUT" | grep -qF 'tracker preflight: deployment' \
          || printf '%s\n' "$_PF_OUT" | grep -qF 'tracker preflight: permissions'; then
        echo "FAIL: TPF/exec: a PASS line produced a notice — only non-PASS lines may"; st=1
      else
        echo "PASS: TPF/exec: PASS lines (deployment, permissions) produce no notice"
      fi
      if printf '%s\n' "$_PF_OUT" | grep -qF 'SECRETLEAK'; then
        echo "FAIL: TPF/exec: a line off the card grammar was echoed into the log (S-6)"; st=1
      else
        echo "PASS: TPF/exec: lines off the card grammar (no tabs, off-enum verdict) are never echoed (S-6)"
      fi
      if printf '%s\n' "$_PF_OUT" | grep -qF 'KIT_TRACKER_RUNNER' \
          && printf '%s\n' "$_PF_OUT" | grep -qF 'Actions → Adopter Tracker Gates → Run workflow'; then
        echo "PASS: TPF/exec: a reach-here FAIL names KIT_TRACKER_RUNNER and the Actions → Adopter Tracker Gates → Run workflow click path"
      else
        echo "FAIL: TPF/exec: a reach-here FAIL notice must name KIT_TRACKER_RUNNER and the click path: $_PF_OUT"; st=1
      fi
      _pf_exec "$_pf_body" "$_pf_priv/stub-pass.sh"
      _pf_notices=$(printf '%s\n' "$_PF_OUT" | grep -c '^::notice title=tracker preflight: ' || true)
      # card is INFO (1 notice); deployment/reach-here/CARD are PASS (none); no runner cure.
      if [ "$_PF_RC" = 0 ] && [ "$_pf_notices" = 1 ] && ! printf '%s\n' "$_PF_OUT" | grep -qF 'KIT_TRACKER_RUNNER'; then
        echo "PASS: TPF/exec: an all-PASS card gives rc 0, no PASS notice and no runner cure"
      else
        echo "FAIL: TPF/exec: an all-PASS card gave rc=$_PF_RC notices=$_pf_notices (want 0 / 1 for the INFO card line): $_PF_OUT"; st=1
      fi
      _pf_exec "$_pf_body" "$_pf_priv/stub-none.sh"
      if [ "$_PF_RC" = 0 ] && printf '%s\n' "$_PF_OUT" | grep -qF '::notice title=tracker preflight: no card::'; then
        echo "PASS: TPF/exec: a contract that prints no card still ends rc 0 and says so in a notice"
      else
        echo "FAIL: TPF/exec: a card-less contract run must end rc 0 with a 'no card' notice (rc=$_PF_RC): $_PF_OUT"; st=1
      fi
      # non-vacuity: a step that propagates the contract's rc, or notices PASS lines, must RED.
      _pf_mut=$(printf '%s\n' "$_pf_body" | sed 's/^exit 0$/exit "$rc"/')
      if [ "$_pf_mut" = "$_pf_body" ]; then
        echo "FAIL: TPF/mutant setup — the body has no bare 'exit 0' line to mutate"; st=1
      else
        _pf_exec "$_pf_mut" "$_pf_priv/stub-fail.sh"
        if [ "$_PF_RC" = 0 ]; then
          echo "FAIL: TPF/mutant (step propagates the contract's rc) was not caught by the rc-0 leg"; st=1
        else
          echo "PASS: TPF/mutant (step propagates the contract's rc) is caught by the rc-0 leg"
        fi
      fi
    fi
    # ── TRACKER-RUNNER-PUBLIC-SELFHOSTED-WARN — the gates job's first step warns (never fails) when a
    # PUBLIC repo runs it on a SELF-HOSTED runner. C1 first step; C2 the fact-based if: (verbatim +
    # truth table); C3 never fails the job (continue-on-error + executed body); C4 inert (no env,
    # with, uses, id, secrets, no ${{ in the body). The if: cannot be evaluated off GitHub: these legs
    # prove the condition is SPELLED as designed and the body behaves, not that GitHub evaluates it.
    _pf_wm='Warn when a public repo runs this job on a self-hosted runner'
    _pf_wtitle='::warning title=tracker-board-gates: public repo on a self-hosted runner::'
    _pf_wif_want="        if: runner.environment == 'self-hosted' && github.event.repository.private == false"
    _pf_w_first() { _tj_job_block "$1" tracker-board-gates | grep -v '^[[:space:]]*#' | grep '^      - ' | head -1; }
    _pf_w_inert() {
      _pwi_blk=$(_t2_step_block "$_pf_wm" "$1" || true)
      _pwi_body=$(_t2_run_body "$_pf_wm" "$1" || true)
      [ -n "$_pwi_blk" ] && [ -n "$_pwi_body" ] || return 1
      # ALLOWLIST: the step's keys are exactly name (first line), the pinned if:, continue-on-error:
      # true and run: | — each once; any other key (env, with, uses, id, shell, working-directory,
      # timeout-minutes, a quoted key) reds. Body lines are indented 10+.
      printf '%s\n' "$_pwi_blk" | awk -v want_if="$_pf_wif_want" '
        NR == 1 { if (index($0, "      - name: ") != 1) bad = 1; next }
        /^[[:space:]]*$/ { next }
        inrun && /^          / { next }
        $0 == want_if { nif++; next }
        $0 == "        continue-on-error: true" { ncoe++; next }
        $0 == "        run: |" { nrun++; inrun = 1; next }
        { bad = 1 }
        END { exit (bad || nif != 1 || ncoe != 1 || nrun != 1) ? 1 : 0 }
      ' || return 1
      # No expression or secret anywhere in the step except the pinned if: line (which has neither).
      if printf '%s\n' "$_pwi_blk" | grep -vxF "$_pf_wif_want" | grep -qF '${{'; then return 1; fi
      if printf '%s\n' "$_pwi_blk" | grep -vxF "$_pf_wif_want" | grep -qF 'secrets'; then return 1; fi
      # The body is a constant: no `$` at all (no variable, no ${{ }}, nothing to expand).
      if printf '%s\n' "$_pwi_body" | grep -qF '$'; then return 1; fi
      return 0
    }
    _pf_w_blk=$(_t2_step_block "$_pf_wm" "$_tj_atg" || true)
    _pf_w_body=$(_t2_run_body "$_pf_wm" "$_tj_atg" || true)

    # C1 — runs first.
    case "$(_pf_w_first "$_tj_atg")" in
      "      - name: $_pf_wm"*) echo "PASS: TPW/first: the public-self-hosted warning is the first step of tracker-board-gates (no later skip or failure can suppress it)" ;;
      *) echo "FAIL: TPW/first: the first step of tracker-board-gates is not the public-self-hosted warning"; st=1 ;;
    esac
    awk -v m="$_pf_wm" '
      index($0, "      - name: " m) == 1 { grab = 1 }
      grab { held = held $0 "\n"; if ($0 ~ /^[[:space:]]*$/) grab = 0; next }
      /^      - name: Resolve backend from the base / { printf "%s", held }
      { print }
    ' "$_tj_atg" > "$_pf_priv/m-first.yml"
    if cmp -s "$_pf_priv/m-first.yml" "$_tj_atg"; then
      echo "FAIL: TPW/first mutant setup — the planted copy did not differ from its source"; st=1
    else
      case "$(_pf_w_first "$_pf_priv/m-first.yml")" in
        "      - name: $_pf_wm"*) echo "FAIL: TPW/first mutant (warning moved after the checkout) was not caught"; st=1 ;;
        *) echo "PASS: TPW/first mutant (warning moved after the checkout) is caught" ;;
      esac
    fi

    # C2 — fires on the runtime fact, public only.
    _pf_w_if=$(printf '%s\n' "$_pf_w_blk" | grep '^        if: ' | head -1)
    if [ "$_pf_w_if" = "$_pf_wif_want" ]; then
      echo "PASS: TPW/if: the warning's if: is runner.environment == 'self-hosted' && private == false (verbatim)"
    else
      echo "FAIL: TPW/if: the warning's if: is not the pinned form; got '$_pf_w_if'"; st=1
    fi
    for _pf_we in self-hosted github-hosted; do
      for _pf_wp in public private; do
        _pf_wlit=true; [ "$_pf_wp" = public ] && _pf_wlit=false
        _pf_wran=0
        case "$_pf_w_if" in
          *"runner.environment == '$_pf_we'"*"github.event.repository.private == $_pf_wlit"*) _pf_wran=1 ;;
        esac
        if [ "$_pf_we" = self-hosted ] && [ "$_pf_wp" = public ]; then _pf_wwant=1; else _pf_wwant=0; fi
        if [ "$_pf_wran" = "$_pf_wwant" ]; then
          echo "PASS: TPW/if: $_pf_we + $_pf_wp repo decides warn=$_pf_wwant (warns only for self-hosted + public)"
        else
          echo "FAIL: TPW/if: $_pf_we + $_pf_wp repo decides warn=$_pf_wran, want $_pf_wwant"; st=1
        fi
      done
    done
    sed "s/^        if: runner.environment == 'self-hosted' && github.event.repository.private == false\$/        if: vars.KIT_TRACKER_RUNNER != ''/" "$_tj_atg" > "$_pf_priv/m-if.yml"
    if cmp -s "$_pf_priv/m-if.yml" "$_tj_atg"; then
      echo "FAIL: TPW/if mutant setup — the planted copy did not differ from its source"; st=1
    else
      _pf_wmif=$(_t2_step_block "$_pf_wm" "$_pf_priv/m-if.yml" | grep '^        if: ' | head -1)
      if [ "$_pf_wmif" = "$_pf_wif_want" ]; then
        echo "FAIL: TPW/if mutant (the label, not the fact) was not caught"; st=1
      else
        echo "PASS: TPW/if mutant (the label, not the fact) is caught"
      fi
    fi

    # C3 — never fails the job.
    if printf '%s\n' "$_pf_w_blk" | grep -qxF '        continue-on-error: true'; then
      echo "PASS: TPW/never-fails: the warning step carries continue-on-error: true"
    else
      echo "FAIL: TPW/never-fails: the warning step has no continue-on-error: true"; st=1
    fi
    if [ -n "$_pf_w_body" ]; then
      _PF_RC=0
      _PF_OUT=$(sh -ec "$_pf_w_body" 2>&1) || _PF_RC=$?
      _pf_wn=$(printf '%s\n' "$_PF_OUT" | grep -cF "$_pf_wtitle" || true)
      if [ "$_PF_RC" = 0 ] && [ "$_pf_wn" = 1 ] \
          && printf '%s\n' "$_PF_OUT" | grep -qF 'KIT_TRACKER_RUNNER' \
          && printf '%s\n' "$_PF_OUT" | grep -qF 'private' \
          && printf '%s\n' "$_PF_OUT" | grep -qF 'ephemeral' \
          && printf '%s\n' "$_PF_OUT" | grep -qF 'https://docs.github.com/'; then
        echo "PASS: TPW/never-fails: the executed body ends rc 0 and prints exactly one warning naming KIT_TRACKER_RUNNER, private, ephemeral and the GitHub guidance"
      else
        echo "FAIL: TPW/never-fails: the executed body gave rc=$_PF_RC warnings=$_pf_wn: $_PF_OUT"; st=1
      fi
    else
      echo "FAIL: TPW/never-fails: the warning step has no run: body"; st=1
    fi
    grep -vxF '        continue-on-error: true' "$_tj_atg" > "$_pf_priv/m-coe.yml" || true
    if cmp -s "$_pf_priv/m-coe.yml" "$_tj_atg"; then
      echo "FAIL: TPW/never-fails mutant setup — the planted copy did not differ from its source"; st=1
    elif _t2_step_block "$_pf_wm" "$_pf_priv/m-coe.yml" | grep -qxF '        continue-on-error: true'; then
      echo "FAIL: TPW/never-fails mutant (no continue-on-error) was not caught"; st=1
    else
      echo "PASS: TPW/never-fails mutant (no continue-on-error) is caught"
    fi

    # C4 — inert: no env/with/uses/id/secrets in the step, no ${{ in the body; one negative per input class.
    if _pf_w_inert "$_tj_atg"; then
      echo "PASS: TPW/inert: the warning step's keys are exactly name, the pinned if:, continue-on-error and run, with no \${{ expression or secret outside the if:"
    else
      echo "FAIL: TPW/inert: the warning step is not inert (a key beyond name/if/continue-on-error/run, or a \${{ expression or secret outside the pinned if:)"; st=1
    fi
    awk -v m="$_pf_wm" '
      index($0, "      - name: " m) == 1 { inw = 1 }
      { print }
      inw && $0 == "        continue-on-error: true" { print "        env:"; print "          T: ${{ secrets.KIT_TRACKER_TOKEN }}"; inw = 0 }
    ' "$_tj_atg" > "$_pf_priv/m-secret.yml"
    awk -v m="$_pf_wm" '
      index($0, "      - name: " m) == 1 { inw = 1 }
      { print }
      inw && $0 == "        run: |" { print "          echo \"${{ github.event.pull_request.title }}\""; inw = 0 }
    ' "$_tj_atg" > "$_pf_priv/m-event.yml"
    awk -v m="$_pf_wm" '
      index($0, "      - name: " m) == 1 { inw = 1 }
      { print }
      inw && $0 == "        continue-on-error: true" { print "        working-directory: /tmp"; inw = 0 }
    ' "$_tj_atg" > "$_pf_priv/m-key.yml"
    awk -v m="$_pf_wm" '
      index($0, "      - name: " m) == 1 { inw = 1 }
      { print }
      inw && index($0, "        if: runner.environment == ") == 1 { print "          || true"; inw = 0 }
    ' "$_tj_atg" > "$_pf_priv/m-continuation.yml"
    for _pf_wmut in secret event key continuation; do
      if cmp -s "$_pf_priv/m-$_pf_wmut.yml" "$_tj_atg"; then
        echo "FAIL: TPW/inert mutant setup ($_pf_wmut) — the planted copy did not differ from its source"; st=1
      elif _pf_w_inert "$_pf_priv/m-$_pf_wmut.yml"; then
        echo "FAIL: TPW/inert mutant ($_pf_wmut class) was not caught"; st=1
      else
        echo "PASS: TPW/inert mutant ($_pf_wmut class) is caught"
      fi
    done
    unset -f _pf_w_first _pf_w_inert

    rm -rf "$_pf_priv" 2>/dev/null || true
    unset -f _pf_exec
  else
    echo "FAIL: $_tj_atg is missing — cannot check its shape legs"; st=1
  fi
  _tj_tlive=".github/workflows/tracker-live.yml"
  if [ -f "$_tj_tlive" ]; then
    # H-1: the live secret is Environment-scoped, not a bare `if:` ref check.
    if grep -qE '^[[:space:]]+environment:[[:space:]]*tracker-live[[:space:]]*$' "$_tj_tlive"; then
      echo "PASS: $_tj_tlive's live-jira-roundtrip job is scoped to the tracker-live Environment (H-1)"
    else
      echo "FAIL: $_tj_tlive's live-jira-roundtrip job has no 'environment: tracker-live' — the secret is not server-side ref-bound (H-1)"; st=1
    fi
    # §8.3/R1c: the live leg still skips-with-notice, never fails closed, on an absent secret.
    if code_only "$_tj_tlive" | grep -qF 'tracker-live: skipped'; then
      echo "PASS: $_tj_tlive still skips with a notice on an absent secret (§8.3/R1c)"
    else
      echo "FAIL: $_tj_tlive lost its skip-with-notice guard — §8.3/R1c requires this leg never fail closed on an unconfigured secret"; st=1
    fi
    # M-2 / design §6b R1b, revised in the aggregate-coverage fix round: R1b is "the gates' own
    # selftests" — dispatch-proof must run loop-state.sh --selftest BY PATH (which carries the T6b
    # good-binds/gutted-refuses legs internally), never call conformance/backlog-lib.sh directly
    # (a workflow naming a LIBRARY as a run target — the exact contradiction aggregate-coverage.sh
    # exists to catch — and, proven, `loop-state --head` cannot be pointed at a fixture tree from
    # outside: check_row hardcodes SEAM_ROOT=$LS_BOARDROOT=$DIR).
    if code_only "$_tj_tlive" | grep -qF 'sh conformance/loop-state.sh --selftest'; then
      echo "PASS: $_tj_tlive's dispatch-proof runs loop-state.sh --selftest by path (design §6b R1b — the T6b good-binds/gutted-refuses legs)"
    else
      echo "FAIL: $_tj_tlive's dispatch-proof does not run loop-state.sh --selftest — R1b's good/gutted proof would not be exercised (M-2)"; st=1
    fi
    if code_only "$_tj_tlive" | grep -qF 'conformance/backlog-lib.sh'; then
      echo "FAIL: $_tj_tlive still names conformance/backlog-lib.sh directly — a workflow invoking a LIBRARY is exactly what aggregate-coverage.sh's library-vs-check contradiction catches"; st=1
    else
      echo "PASS: $_tj_tlive no longer names conformance/backlog-lib.sh directly (aggregate-coverage fix)"
    fi
    # T3: dispatch-proof must ALSO run the two board gates' own selftests — backlog-presence.sh and
    # backlog-current.sh (their T8/T9 tracker-arm legs: a good record binds, gutted ones refuse) —
    # plus board-drift.sh --selftest (TRACKER-DRIFT-SCHEDULED-WIRING) — scoped to the dispatch-proof
    # job's own block, never the whole file.
    _t3_dp_blk=$(_job_block "$_tj_tlive" dispatch-proof)
    if printf '%s\n' "$_t3_dp_blk" | grep -qF 'sh conformance/backlog-presence.sh --selftest' \
        && printf '%s\n' "$_t3_dp_blk" | grep -qF 'sh conformance/backlog-current.sh --selftest' \
        && printf '%s\n' "$_t3_dp_blk" | grep -qF 'sh conformance/board-drift.sh --selftest'; then
      echo "PASS: $_tj_tlive's dispatch-proof job runs backlog-presence.sh, backlog-current.sh and board-drift.sh --selftest"
    else
      echo "FAIL: $_tj_tlive's dispatch-proof job does not run all three of backlog-presence.sh, backlog-current.sh and board-drift.sh --selftest"; st=1
    fi
    # Mutant: strip the backlog-current.sh --selftest line from dispatch-proof and confirm the leg reds.
    _t3_mut=$(mktemp -d)
    sed '/sh conformance\/backlog-current\.sh --selftest/d' "$_tj_tlive" > "$_t3_mut/mut.yml"
    if cmp -s "$_t3_mut/mut.yml" "$_tj_tlive"; then
      echo "FAIL: T3/mutant setup — the planted copy did not differ from its source"; st=1
    else
      _t3_mut_blk=$(_job_block "$_t3_mut/mut.yml" dispatch-proof)
      if printf '%s\n' "$_t3_mut_blk" | grep -qF 'sh conformance/backlog-presence.sh --selftest' \
          && printf '%s\n' "$_t3_mut_blk" | grep -qF 'sh conformance/backlog-current.sh --selftest' \
          && printf '%s\n' "$_t3_mut_blk" | grep -qF 'sh conformance/board-drift.sh --selftest'; then
        echo "FAIL: T3/mutant (dropped backlog-current.sh --selftest) was not caught"; st=1
      else
        echo "PASS: T3/mutant (dropped backlog-current.sh --selftest) is caught"
      fi
    fi
    rm -rf "$_t3_mut" 2>/dev/null || true
    # Mutant (TDS): strip the board-drift.sh --selftest line from dispatch-proof and confirm the leg reds.
    _tds_t3_mut=$(mktemp -d)
    sed '/sh conformance\/board-drift\.sh --selftest/d' "$_tj_tlive" > "$_tds_t3_mut/mut.yml"
    if cmp -s "$_tds_t3_mut/mut.yml" "$_tj_tlive"; then
      echo "FAIL: TDS/T3-mutant setup — the planted copy did not differ from its source"; st=1
    else
      _tds_t3_mut_blk=$(_job_block "$_tds_t3_mut/mut.yml" dispatch-proof)
      if printf '%s\n' "$_tds_t3_mut_blk" | grep -qF 'sh conformance/board-drift.sh --selftest'; then
        echo "FAIL: TDS/T3-mutant (dropped board-drift.sh --selftest) was not caught"; st=1
      else
        echo "PASS: TDS/T3-mutant (dropped board-drift.sh --selftest) is caught"
      fi
    fi
    rm -rf "$_tds_t3_mut" 2>/dev/null || true
  elif [ -f "docs/ROADMAP-KIT.md" ]; then
    # kit-tree marker present (docs/ROADMAP-KIT.md, export-ignored) yet tracker-live.yml is
    # missing — that IS a real regression on the kit's own tree, never N/A there.
    echo "FAIL: $_tj_tlive is missing — cannot check its shape legs"; st=1
  else
    # artifact-gate CI fix: tracker-live.yml is KIT-ONLY, export-ignored (.gitattributes) — it is
    # legitimately ABSENT on every incepted/adopter/exported tree (no kit-tree marker here means
    # this is one of those trees). Its shape legs above only apply where the file exists to have a
    # shape; an absent kit-only file is N/A, not a FAIL — the same disposition ladder every other
    # kit-tree-gated leg in this file already uses (docs/ROADMAP-KIT.md-gated blocks elsewhere).
    echo "N/A: $_tj_tlive shape legs — kit-only, export-ignored file, legitimately absent on this tree (not the kit's own)"
  fi

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
