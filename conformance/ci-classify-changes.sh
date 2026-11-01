#!/bin/sh
# ci-classify-changes.sh — decide whether a change-set is DOCS-ONLY, i.e. whether it can possibly affect
# the expensive conformance proofs. CI uses the verdict to skip the heavy shards on a docs-only PR.
#
# What it changes: nothing. Reads a newline-delimited changed-file listing; prints `docs_only=true|false`.
# Guardrails: fail-safe by construction (see below). Never writes, never network.
#
# THE PREDICATE IS DELIBERATELY NARROW: *every* changed path must end in `.md`. Anything else — a `.sh`,
# `.yml`, `.tsv`, an extensionless file, a rename, a deletion of a non-.md file — makes the whole change
# set NOT docs-only.
#
# ⚠️ THE "A RENAME" CLAUSE ABOVE DEPENDS ENTIRELY ON THE CALLER, and it was FALSE until 2026-07-25.
# This predicate is only as good as the listing it is handed. `ci.yml` built that listing with
# `gh api .../pulls/N/files -q '.[].filename'`, and the Files API reports a rename as ONE entry whose
# `filename` is the DESTINATION — the source lives only in `previous_filename`. So a rename FROM a
# non-`.md` path TO a `.md` path arrived here as an all-`.md` listing and this check correctly answered
# `docs_only=true` on the data it was given. Measured consequence: `git mv conformance/<check>.sh
# docs/<x>.md` skipped cf-verify-enforced, --selftest, claims, non-vacuity and green-on-clone while the
# required `conformance` job still reported OK (its allowed set includes `skipped`). Fail-closed by
# design, defeated upstream by its caller. The caller now also projects `previous_filename`, so the
# non-`.md` source reappears and disqualifies the set — which is what this header always claimed.
# ⚠️ NOTHING LOCKS THIS INVARIANT. A class-wide check was built and withdrawn (it was defeated three
# times over three review rounds); it is boarded as `CHANGESET-DERIVATION-LOCK`. So the caller's
# projection is correct TODAY by inspection only — if you change how `/tmp/changed.txt` is built, this
# predicate's "a rename" clause is your responsibility to re-verify.
#
# WHY AN ALLOWLIST AND NOT A DENYLIST. The question is not "does this look risky?" but "can this change
# POSSIBLY affect the expensive proofs?", and the answer must default to YES. A denylist of risky paths
# fails OPEN on every path nobody thought of — and the paths nobody thinks of are exactly where the
# defects live. An allowlist of `.md` fails CLOSED on everything new. In a governance kit a
# mis-classification must cost us CI TIME, never COVERAGE.
#
# FAIL-SAFE, in every ambiguous case -> docs_only=false (run everything):
#   - an EMPTY listing        -> false. "No files" is not "no code"; it is "we could not read the change
#                                set", which is unknown, and unknown means run the full suite.
#   - an UNREADABLE listing   -> false (same reason).
#   - a MIXED listing         -> false (one .sh among fifty .md still needs the full proof).
#   - a path with NO extension-> false.
#   - literally anything else -> false. `true` is emitted from exactly ONE code path, and only when every
#                                line was affirmatively matched as markdown.
#
# The one direction that must NEVER happen is a code change classified as docs-only: that silently skips
# the gates. So the default is `false`, and `true` must be EARNED.
#
# Usage:
#   sh scripts/ci-classify-changes.sh <listing-file>   # prints docs_only=true|false ; exit 0
#   sh scripts/ci-classify-changes.sh --selftest
set -eu

# ── classify <listing-file> : print `docs_only=true` iff the file is non-empty AND every line is a .md
#    path. Every other outcome prints `docs_only=false`. Exit is always 0 — the VERDICT is the output,
#    not the exit code, so a caller can never mistake "classified as code" for "the classifier crashed".
classify() {
  _f=${1:-}

  # Unreadable / absent / empty -> unknown -> full suite.
  if [ -z "$_f" ] || [ ! -r "$_f" ] || [ ! -s "$_f" ]; then
    echo "docs_only=false"
    return 0
  fi

  # Any line that is NOT a .md path disqualifies the whole set. `grep -qv` is the whole predicate:
  # "does there exist a line that fails to match `\.md$`?" If yes -> not docs-only.
  # Note the anchor: `\.md$` matches `docs/x.md` but NOT `x.md.sh`, `mdfile`, or a bare `md`.
  if grep -qvE '\.md$' "$_f"; then
    echo "docs_only=false"
    return 0
  fi

  # THE ONLY PATH THAT EMITS true. Reached only when the listing was readable, non-empty, and every
  # single line ended in `.md`.
  echo "docs_only=true"
  return 0
}

# ══════════════════════════════════════════════════════════════════════════════════════════════
# push_graded — the SECOND predicate (CI-LANE-BY-CHANGE-CLASS, D-240903-3). Same doctrine as
# classify() above, aimed at a different lane: a push to `main` re-runs only what the merged PR did
# not already grade. `true` must be EARNED and is emitted from exactly TWO code paths; every other
# outcome is `false`, which means THE FULL SUITE RUNS. A mis-classification must cost CI TIME,
# never COVERAGE.
#
# THIS IS NOT A DIFF. It never asks "what changed"; it asks "is the tree being pushed BYTE-IDENTICAL
# to a tree a completed, successful CI run already graded, and was that run the one for the PR the
# forge says produced this commit?" Tree identity is computed LOCALLY by the caller (git rev-parse)
# and compared here — the forge is trusted only for the commit→PR association and the run record.
#
# Inputs are FILES and STRINGS, passed by argument (the --check-complete precedent): nothing is
# interpolated into a shell, nothing is fetched here, and the whole thing is --selftest-able.
#   $1 pulls.json  — repos/<repo>/commits/<sha>/pulls (an array, or {} on failure)
#   $2 run.json    — actions/runs?head_sha=… ({"workflow_runs":[…]} or an array); the caller may
#                    pre-filter, and this predicate re-selects the CI run with the highest
#                    run_number/run_attempt anyway, so a two-run head cannot be graded by the older one
#   $3 jobs.json   — actions/runs/<id>/jobs ({"jobs":[…]} or an array)
#   $4 push_tree   — `git rev-parse "$GITHUB_SHA^{tree}"`
#   $5 head_tree   — `git rev-parse "<pr-head>^{tree}"`
#   $6 github_sha  — the pushed commit
#   $7 repo        — owner/name; base AND head repo must both equal it (no fork head)
#
# THE TWO AUTHORISED PATHS (design §4.1a, owner ruling R2-with-R1):
#   all-shards          — every job in PG_NEEDED plus every `non-vacuity*` leg concluded success.
#                         This is the CODE-merge path.
#   docs-only-induction — every heavy shard was `skipped` (i.e. the PR ran docs-only) AND
#                         `conformance-docs` (the always-run doc-sensitive job), `docs-links` and the
#                         required `conformance` aggregator all succeeded. The induction: a docs-only
#                         tree differs from the last fully-graded main only in `.md` files; every check
#                         that can READ a `.md` ran on the PR in conformance-docs; the checks that
#                         cannot already answered on the last fully-graded main. Its base case is that
#                         a push with no merged PR, and every code merge, run the full suite.
# PG_NEEDED is a CONSTANT, deliberately: it mirrors the `conformance` aggregator's `needs:` list, and
# a drift between the two is caught by the boarded AGGREGATOR-NEEDS-LOCK, not by a parse of ci.yml
# from a script that must stay pure. `conformance-docs` is NOT in it — the aggregator IS, and the
# aggregator needs conformance-docs, so R1 subsumes it without breaking on pre-slice runs.
PG_NEEDED='changes conformance-core conformance-selftests cf-doctor cf-export cf-export-claims cf-verify-enforced cf-claims cf-green-on-clone guard-battery guard-delta boundary-redteam conformance'
PG_HEAVY='conformance-core conformance-selftests cf-doctor cf-export cf-export-claims cf-verify-enforced cf-claims cf-green-on-clone'

_pg_no()  { echo "push_graded=false reason=$1"; }
_pg_hex() { case "${1:-}" in ''|*[!0-9a-f]*) return 1 ;; esac; [ "${#1}" -eq 40 ]; }
_pg_jq()  { printf '%s' "$1" | jq -r "$2" 2>/dev/null; }
# _pg_conc <name>: the conclusion of the job AND its matrix legs `<name> (...)`; empty if none exist,
# the shared conclusion if every instance agrees, `mixed` if not (success/skipped then need EVERY leg).
_pg_conc() { printf '%s\n' "$_pgmap" | awk -F'\t' -v n="$1" '$1 == n || index($1, n " (") == 1 { c[$2] = 1; k++; v = $2 } END { if (k) print (length(c) == 1 ? v : "mixed") }'; }

# head_evidence — the EXACT-HEAD predicate (SWAS-537), extracted from push_graded's steps 3-4 so the push lane
# and the merge verbs (promotion-verify.sh land/actuate/trace) cannot drift. The question: did a COMPLETED,
# successful run of the CI workflow on EXACTLY <head-sha> grade the light-or-full set? A cheap run (the
# `changes` job skipped, e.g. a draft PR) never satisfies it. Inputs are FILES and STRINGS, nothing fetched:
#   $1 runs.json   {"workflow_runs":[…]} or an array; $2 jobs.json {"jobs":[…]} or an array
#   $3 head-sha    the 40-hex commit; $4 head-branch (never empty); $5 repo owner/name (head repo must equal it)
#   $6 workflow    the workflow FILE path (default .github/workflows/ci.yml)
# Prints `evidence=ok reason=all-shards|docs-only-induction run=<id>` or `evidence=no reason=<token>` (the
# token carries ` run=<id>` once a run was selected). Always rc 0: the VERDICT is the output.
_he_no() { echo "evidence=no reason=$1${2:+ run=$2}"; }
head_evidence() {
  _hru=${1:-}; _hjo=${2:-}; _hhs=${3:-}; _hhb=${4:-}; _hrepo=${5:-}; _hwf=${6:-.github/workflows/ci.yml}
  command -v jq >/dev/null 2>&1 || { _he_no no-jq; return 0; }
  for _hf in "$_hru" "$_hjo"; do
    { [ -n "$_hf" ] && [ -r "$_hf" ] && [ -s "$_hf" ]; } || { _he_no unreadable-input; return 0; }
  done
  _pg_hex "$_hhs" || { _he_no bad-head-sha; return 0; }

  # 3. WHICH RUN, AND DID IT COMPLETE GREEN. Latest run_number/run_attempt among the runs of THIS
  #    workflow file, triggered by pull_request, from THIS PR's own branch and repository. The run's
  #    `pull_requests` list is EMPTY once the PR merged (measured live), so it cannot be the bind; the
  #    PR's own head ref and repo are. Another branch's run, or a fork's, is never graded.
  _hr=$(jq -c --arg p "$_hwf" --arg b "$_hhb" --arg r "$_hrepo" 'if type == "array" then . else (.workflow_runs // []) end
              | [.[] | select(.path == $p and .event == "pull_request" and $b != ""
                              and .head_branch == $b and .head_repository.full_name == $r)] | sort_by(.run_number, .run_attempt) | last' "$_hru" 2>/dev/null) \
    || { _he_no unreadable-input; return 0; }
  { [ -n "$_hr" ] && [ "$_hr" != null ]; } || { _he_no no-graded-run; return 0; }
  _hid=$(_pg_jq "$_hr" '.id')
  [ "$(_pg_jq "$_hr" '.head_sha')" = "$_hhs" ]     || { _he_no run-head-mismatch "$_hid"; return 0; }
  [ "$(_pg_jq "$_hr" '.status')" = completed ]     || { _he_no run-not-completed "$_hid"; return 0; }
  [ "$(_pg_jq "$_hr" '.conclusion')" = success ]   || { _he_no run-not-success "$_hid"; return 0; }

  # 4. WHAT THAT RUN ACTUALLY GRADED. A run-level `success` is NOT enough: a run whose heavy shards
  #    all skipped is `success` too — that is precisely the docs-only case, and it earns the weaker
  #    (induction) authorisation, never the strong one.
  _pgmap=$(jq -r 'if type == "array" then . else (.jobs // []) end
                  | .[] | [.name, (.conclusion // "")] | @tsv' "$_hjo" 2>/dev/null) \
    || { _he_no unreadable-input "$_hid"; return 0; }
  [ -n "$_pgmap" ] || { _he_no no-jobs "$_hid"; return 0; }
  _nv=$(printf '%s\n' "$_pgmap" | awk -F'\t' '$1 ~ /^non-vacuity/ { print $2 }')

  _r1=1; [ -n "$_nv" ] || _r1=0
  for _j in $PG_NEEDED; do [ "$(_pg_conc "$_j")" = success ] || _r1=0; done
  for _c in $_nv;        do [ "$_c" = success ] || _r1=0; done
  if [ "$_r1" = 1 ]; then
    echo "evidence=ok reason=all-shards run=$_hid"
    return 0
  fi

  _sk=1; [ -n "$_nv" ] || _sk=0
  for _j in $PG_HEAVY; do [ "$(_pg_conc "$_j")" = skipped ] || _sk=0; done
  for _c in $_nv;       do [ "$_c" = skipped ] || _sk=0; done
  if [ "$_sk" = 1 ] && [ "$(_pg_conc changes)" = success ]; then
    _d=$(_pg_conc conformance-docs)
    [ -n "$_d" ]         || { _he_no docs-induction-no-docs-job "$_hid"; return 0; }
    [ "$_d" = success ]  || { _he_no docs-induction-docs-job-not-success "$_hid"; return 0; }
    { [ "$(_pg_conc docs-links)" = success ] && [ "$(_pg_conc conformance)" = success ]; } \
      || { _he_no docs-induction-support-not-success "$_hid"; return 0; }
    echo "evidence=ok reason=docs-only-induction run=$_hid"
    return 0
  fi
  for _j in $PG_NEEDED; do   # name the FIRST failing entry, in the constant's order
    _c=$(_pg_conc "$_j")
    [ -n "$_c" ] || { _he_no "needed-job-missing:$_j" "$_hid"; return 0; }
    [ "$_c" = success ] || { _he_no "needed-job-not-success:$_j" "$_hid"; return 0; }
  done
  [ -n "$_nv" ] || { _he_no needed-job-missing:non-vacuity "$_hid"; return 0; }
  _he_no needed-job-not-success:non-vacuity "$_hid"
  return 0
}

push_graded() {
  _pu=${1:-}; _ru=${2:-}; _jo=${3:-}; _pt=${4:-}; _ht=${5:-}; _sha=${6:-}; _repo=${7:-}
  _wf=${8:-.github/workflows/ci.yml}   # the workflow FILE the graded run must come from (D3)

  # jq is the union tool (ci.yml probes it in two jobs); absent, we do not guess — we run everything.
  command -v jq >/dev/null 2>&1 || { _pg_no no-jq; return 0; }
  for _f in "$_pu" "$_ru" "$_jo"; do
    { [ -n "$_f" ] && [ -r "$_f" ] && [ -s "$_f" ]; } || { _pg_no unreadable-input; return 0; }
  done

  # 0. THE IDS ARE GRAMMAR-CHECKED BEFORE THEY REACH jq. `$_sha` is bound with `--arg` below, never
  #    interpolated into a jq program — but it is also required to BE a 40-hex object id, because a
  #    value that is not one cannot be the commit being pushed and must never select anything.
  _pg_hex "$_sha" || { _pg_no bad-github-sha; return 0; }

  # 1. THE TREE. Checked FIRST and locally: no forge answer can talk us past a tree nobody graded.
  { _pg_hex "$_pt" && _pg_hex "$_ht"; } || { _pg_no bad-tree-id; return 0; }
  [ "$_pt" = "$_ht" ] || { _pg_no tree-mismatch; return 0; }

  # 2. WHICH PR. `commits/<sha>/pulls` also lists OPEN PRs containing the commit (with a TEST-MERGE
  #    merge_commit_sha that can coincide) — `merged_at != null` is what excludes them.
  _merged=$(jq -c '[.[]? | select(.merged_at != null)]' "$_pu" 2>/dev/null) || { _pg_no unreadable-input; return 0; }
  [ -n "$_merged" ] || { _pg_no unreadable-input; return 0; }
  # ⚠️ BOUND WITH --arg, NEVER INTERPOLATED. An earlier draft built these two programs by string
  #    substitution of `$_sha`, which makes a caller-supplied value part of the jq PROGRAM.
  _hit=$(printf '%s' "$_merged" | jq -r --arg s "$_sha" '[.[] | select(.merge_commit_sha == $s)] | length' 2>/dev/null)
  if [ "$_hit" != 1 ]; then
    if [ "$_hit" -gt 1 ] 2>/dev/null; then _pg_no multiple-merged-prs
    elif [ "$(_pg_jq "$_merged" 'length')" = 0 ]; then _pg_no no-merged-pr
    else _pg_no merge-sha-mismatch; fi
    return 0
  fi
  _e=$(printf '%s' "$_merged" | jq -c --arg s "$_sha" 'map(select(.merge_commit_sha == $s))[0]' 2>/dev/null)
  [ "$(_pg_jq "$_e" '.base.ref')" = main ] || { _pg_no base-not-main; return 0; }
  { [ "$(_pg_jq "$_e" '.base.repo.full_name')" = "$_repo" ] \
    && [ "$(_pg_jq "$_e" '.head.repo.full_name')" = "$_repo" ]; } || { _pg_no fork-head; return 0; }
  _hs=$(_pg_jq "$_e" '.head.sha'); _pg_hex "$_hs" || { _pg_no bad-head-sha; return 0; }
  _pr=$(_pg_jq "$_e" '.number')
  case "$_pr" in ''|*[!0-9]*) _pg_no bad-pr-number; return 0 ;; esac

  # 3-4. WHICH RUN, AND WHAT IT GRADED: the shared exact-head predicate (head_evidence, above), so the push
  #    lane and the merge verbs (SWAS-537) read ONE grammar. Its verdict is translated back into this
  #    predicate's own key=value shape, byte-for-byte.
  _hb=$(_pg_jq "$_e" '.head.ref')
  _ev=$(head_evidence "$_ru" "$_jo" "$_hs" "$_hb" "$_repo" "$_wf")
  case "$_ev" in
    "evidence=ok reason="*" run="*)
      _evr=${_ev#evidence=ok reason=}
      echo "push_graded=true graded_pr=$_pr graded_head=$_hs graded_run=${_evr##* run=} reason=${_evr%% run=*}" ;;
    "evidence=no reason="*)
      _evr=${_ev#evidence=no reason=}; _pg_no "${_evr%% run=*}" ;;
    *) _pg_no unreadable-input ;;
  esac
  return 0
}

# ══════════════════════════════════════════════════════════════════════════════════════════════
# export_ignored_only — the THIRD predicate (CI-ARTIFACT-GATE-PATHFILTER). `git archive
# --worktree-attributes HEAD` (scripts/adopter-export.sh) is what produces the adopter artifact the
# artifact-gate* jobs incept and grade. A path that is export-ignored is DEFINITIONALLY absent from
# that archive, so it can never influence what artifact-gate grades. When every changed path is
# export-ignored, the three artifact-gate* jobs are skippable — a time saving, never a coverage loss
# (D-240815-3): nothing export-ignored is ever added back to the exported tree.
#
# THE ORACLE IS `git check-attr` WITH AN ANCESTOR-DIRECTORY WALK, NOT A FILE-PATH QUERY ALONE.
# Measured 2026-09-14: `git check-attr export-ignore -- docs/architecture/x.md` -> `unspecified`,
# but `git check-attr export-ignore -- docs/architecture/` (trailing slash) -> `set`, and
# `git archive` DOES prune that subtree. A file-path query does not inherit a directory pattern; a
# trailing-slash directory query does. So a path is treated as export-ignored iff the path itself,
# OR any ancestor directory (queried with a trailing slash), resolves `set`.
#
# This is a PATTERN oracle, not a tree-presence oracle — correct for deletions and renames. A
# deleted EXPORTED file still pattern-matches as NOT ignored (the artifact loses that file — a real
# change; the gate must run). A deleted MAINTAINER file still pattern-matches as ignored via its
# ancestor (no artifact effect; skippable). A tree-presence check ("is this path in `git archive
# HEAD`") would get the deletion case backwards — a coverage loss this predicate must never make.
#
# Same fail-safe doctrine as classify(): unreadable/absent/empty listing, no git, or not a work
# tree -> false (unknown => run). `true` is earned only when every single line resolves ignored.
_eio_ignored() { # _eio_ignored <path> : true (rc 0) iff PATH or an ancestor dir is export-ignore=set
  _ep=$1

  _ev=$(git check-attr export-ignore -- "$_ep" 2>/dev/null) || _ev=''
  _ev=${_ev##*: }
  [ "$_ev" = set ] && return 0

  _ed=$_ep
  while :; do
    case "$_ed" in
      */*) _ed=${_ed%/*} ;;
      *)   return 1 ;;
    esac
    _ev=$(git check-attr export-ignore -- "$_ed/" 2>/dev/null) || _ev=''
    _ev=${_ev##*: }
    [ "$_ev" = set ] && return 0
  done
}

export_ignored_only() {
  _ef=${1:-}

  # Unreadable / absent / empty -> unknown -> run (same contract as classify()).
  if [ -z "$_ef" ] || [ ! -r "$_ef" ] || [ ! -s "$_ef" ]; then
    echo "export_ignored_only=false"
    return 0
  fi

  # No git, or not inside a work tree -> fail-safe -> run.
  command -v git >/dev/null 2>&1 || { echo "export_ignored_only=false"; return 0; }
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "export_ignored_only=false"; return 0; }

  while IFS= read -r _ep || [ -n "$_ep" ]; do
    [ -n "$_ep" ] || continue
    if ! _eio_ignored "$_ep"; then
      echo "export_ignored_only=false"
      return 0
    fi
  done < "$_ef"

  # THE ONLY PATH THAT EMITS true. Reached only when every single line resolved export-ignored.
  echo "export_ignored_only=true"
  return 0
}

# ── selftest : the classifier's teeth. Every fixture below is a real mis-classification we must not make.
#    The `false` cases matter far more than the `true` case: a wrong `false` costs CI minutes; a wrong
#    `true` SKIPS THE GATES.
selftest() {
  st=0; d=$(mktemp -d)
  _want() { # _want <name> <expected> <lines...>
    _n=$1; _exp=$2; shift 2
    printf '%s\n' "$@" > "$d/$_n"
    _got=$(classify "$d/$_n")
    if [ "$_got" = "docs_only=$_exp" ]; then
      printf 'PASS: %-34s -> %s\n' "$_n" "$_got"
    else
      printf 'FAIL: %-34s -> %s (want docs_only=%s)\n' "$_n" "$_got" "$_exp"; st=1
    fi
  }

  # --- the ONE case that may be true ---
  _want all-markdown          true  'BACKLOG.md' 'docs/architecture/x.md' 'README.md'

  # --- everything else must be false ---
  _want one-shell-among-md    false 'BACKLOG.md' 'conformance/verify.sh' 'README.md'
  # CI-LANE-BY-CHANGE-CLASS §4.3 — the row's exact wording: a conformance file added to an otherwise
  # docs-only diff must flip the lane ON. Same class as one-shell-among-md, asserted under the name
  # the row used, because THIS is the diff shape the new push/docs lanes are judged against.
  _want conformance-file-among-md false 'BACKLOG.md' 'conformance/ci-classify-changes.sh' 'docs/x.md'
  _want a-workflow            false '.github/workflows/ci.yml'
  _want a-tsv                 false 'conformance/claims.tsv'
  _want no-extension          false 'CODEOWNERS'
  _want a-profile-yml         false 'profiles/typescript-node/ci.yml'
  _want dotfile               false '.gitignore'
  _want md-lookalike-suffix   false 'evil.md.sh'
  _want md-substring-not-ext  false 'docs/mdnotes'
  _want bare-md-word          false 'md'
  _want uppercase-MD          false 'README.MD'

  # --- fail-safe: the unknown cases ---
  : > "$d/empty"
  _got=$(classify "$d/empty")
  if [ "$_got" = "docs_only=false" ]; then echo "PASS: EMPTY listing                    -> docs_only=false (unknown => run everything)"
  else echo "FAIL: an EMPTY listing classified as $_got — 'no files' is not 'no code'"; st=1; fi

  _got=$(classify "$d/does-not-exist")
  if [ "$_got" = "docs_only=false" ]; then echo "PASS: UNREADABLE listing               -> docs_only=false (unknown => run everything)"
  else echo "FAIL: an UNREADABLE listing classified as $_got"; st=1; fi

  _got=$(classify "")
  if [ "$_got" = "docs_only=false" ]; then echo "PASS: NO argument                      -> docs_only=false (unknown => run everything)"
  else echo "FAIL: a missing argument classified as $_got"; st=1; fi

  # --- THE LOAD-BEARING NEGATIVE: `true` must be EARNED, never the default. If a mutation neuters the
  #     disqualifying grep, EVERY fixture above collapses to true and the suite goes red. Assert directly
  #     that the code fixture cannot reach `true` — this is the assertion the non-vacuity sweep will
  #     mutate, and it must not survive.
  printf '%s\n' 'conformance/verify.sh' > "$d/code"
  if [ "$(classify "$d/code")" = "docs_only=true" ]; then
    echo "FAIL: a CODE change was classified docs-only — this silently skips the conformance gates"; st=1
  else
    echo "PASS: a CODE change can never be classified docs-only (the one direction that must never happen)"
  fi

  rm -rf "$d"
  selftest_pg || st=1
  selftest_he || st=1
  selftest_eio || st=1
  [ "$st" = 0 ] && echo "ci-classify-changes --selftest: OK" || { echo "ci-classify-changes --selftest: FAIL" >&2; return 1; }
  return "$st"
}

# ── selftest_pg : the --push-graded predicate's teeth (CI-LANE-BY-CHANGE-CLASS design §6).
#    A wrong `false` costs the push lane's CI minutes; a wrong `true` MERGES A TREE NOTHING GRADED.
#    So every negative asserts its EXACT reason token: a fixture that fails for the wrong reason is a
#    fixture that is no longer testing what its name says.
selftest_pg() {
  pst=0; p=$(mktemp -d)
  T=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa                       # the (equal) push/head tree ids
  S=1111111111111111111111111111111111111111                       # $GITHUB_SHA (the merge commit)
  H=2222222222222222222222222222222222222222                       # the PR head sha
  R=acme/kit
  PRS='"head_branch":"feat/x","head_repository":{"full_name":"acme/kit"},"event":"pull_request","pull_requests":[]'   # the live shape of a merged PR's run

  _mkpulls() { # _mkpulls <file> <merged_at> <merge_sha> <base_ref> <base_repo> <head_repo> <head_sha>
    printf '[{"number":7,"merged_at":%s,"merge_commit_sha":"%s","base":{"ref":"%s","repo":{"full_name":"%s"}},"head":{"ref":"feat/x","sha":"%s","repo":{"full_name":"%s"}}}]\n' \
      "$2" "$3" "$4" "$5" "$7" "$6" > "$1"
  }
  _mkrun() { # _mkrun <file> <status> <conclusion> <head_sha> [more-json-entries]
    printf '{"workflow_runs":[{"id":900,"name":"CI","path":".github/workflows/ci.yml","run_number":1,"run_attempt":1,"status":"%s","conclusion":"%s","head_sha":"%s",%s}%s]}\n' \
      "$2" "$3" "$4" "$PRS" "${5:-}" > "$1"
  }
  _mkjobs() { # _mkjobs <file> <name=conclusion ...>   (`~` in a name stands for a space)
    _o=''; _dst=$1; shift
    for _pair in "$@"; do
      _nm=$(printf '%s' "${_pair%%=*}" | tr '~' ' ')
      _o="$_o${_o:+,}{\"name\":\"$_nm\",\"conclusion\":\"${_pair#*=}\"}"
    done
    printf '{"jobs":[%s]}\n' "$_o" > "$_dst"
  }
  # the three canonical job listings
  J_ALL='changes=success conformance-core=success conformance-selftests=success cf-doctor=success
    cf-export=success cf-export-claims=success cf-verify-enforced=success
    cf-claims=success cf-green-on-clone=success guard-battery=success guard-delta=success boundary-redteam=success conformance-docs=success docs-links=success
    conformance=success non-vacuity~(1)=success non-vacuity~(2)=success'
  J_DOCS='changes=success conformance-core=skipped conformance-selftests=skipped cf-doctor=skipped
    cf-export=skipped cf-export-claims=skipped cf-verify-enforced=skipped
    cf-claims=skipped cf-green-on-clone=skipped guard-battery=skipped guard-delta=skipped boundary-redteam=skipped conformance-docs=success docs-links=success
    conformance=success non-vacuity~(1)=skipped non-vacuity~(2)=skipped'

  # shellcheck disable=SC2086   # the J_* listings are deliberately word-split into name=conclusion args
  _reset() {
    _mkpulls "$p/pulls" '"2026-09-03T00:00:00Z"' "$S" main "$R" "$R" "$H"
    _mkrun "$p/run" completed success "$H"
    _mkjobs "$p/jobs" $J_ALL
  }
  _pg() { push_graded "$p/pulls" "$p/run" "$p/jobs" "$T" "${1:-$T}" "$S" "$R"; }
  _case() { # _case <name> <expected-line>
    _got=$(_pg "${3:-$T}")
    if [ "$_got" = "$2" ]; then printf 'PASS: %-38s -> %s\n' "$1" "$_got"
    else printf 'FAIL: %-38s -> %s\n           (want %s)\n' "$1" "$_got" "$2"; pst=1; fi
  }
  OK_ALL="push_graded=true graded_pr=7 graded_head=$H graded_run=900 reason=all-shards"
  OK_IND="push_graded=true graded_pr=7 graded_head=$H graded_run=900 reason=docs-only-induction"

  # --- (+) the two authorised paths ---
  _reset;                                   _case r1-all-shards-success "$OK_ALL"
  # shellcheck disable=SC2046,SC2086   # word-splitting the name=conclusion listing IS the fixture builder
  _reset; _mkjobs "$p/jobs" $J_DOCS;        _case r2-docs-only-induction "$OK_IND"

  # --- (−) the PR association ---
  _reset; echo '[]' > "$p/pulls";           _case zero-pulls          "push_graded=false reason=no-merged-pr"
  _reset; _mkpulls "$p/pulls" null "$S" main "$R" "$R" "$H"
  _case open-pr-test-merge-sha              "push_graded=false reason=no-merged-pr"
  _reset; _e1=$(sed 's/^\[//; s/\]$//' "$p/pulls"); printf '[%s,%s]\n' "$_e1" "$(printf '%s' "$_e1" | sed 's/"number":7/"number":8/')" > "$p/pulls"
  _case two-merged-prs                      "push_graded=false reason=multiple-merged-prs"
  _reset; _mkpulls "$p/pulls" '"x"' 3333333333333333333333333333333333333333 main "$R" "$R" "$H"
  _case merge-sha-mismatch                  "push_graded=false reason=merge-sha-mismatch"
  _reset; _mkpulls "$p/pulls" '"x"' "$S" release "$R" "$R" "$H"
  _case base-not-main                       "push_graded=false reason=base-not-main"
  _reset; _mkpulls "$p/pulls" '"x"' "$S" main "$R" forker/kit "$H"
  _case fork-head                           "push_graded=false reason=fork-head"
  _reset; _mkpulls "$p/pulls" '"x"' "$S" main "$R" "$R" cafe
  _case non-40-hex-head-sha                 "push_graded=false reason=bad-head-sha"

  # --- (−) the run record ---
  _reset; _mkrun "$p/run" completed success 4444444444444444444444444444444444444444
  _case run-on-an-older-head                "push_graded=false reason=run-head-mismatch"
  _reset; _mkrun "$p/run" in_progress '' "$H"
  _case run-in-progress                     "push_graded=false reason=run-not-completed"
  _reset; _mkrun "$p/run" completed success "$H" ',{"id":901,"name":"CI","path":".github/workflows/ci.yml","run_number":2,"run_attempt":1,"status":"completed","conclusion":"failure","head_sha":"'"$H"'",'"$PRS"'}'
  _case two-runs-latest-failed              "push_graded=false reason=run-not-success"
  _reset; printf '{"workflow_runs":[{"id":9,"name":"Ratification","path":".github/workflows/ratification.yml","run_number":1,"run_attempt":1,"status":"completed","conclusion":"success","head_sha":"%s"}]}\n' "$H" > "$p/run"
  _case no-CI-run-on-that-head              "push_graded=false reason=no-graded-run"

  # --- (−) grading ---
  # shellcheck disable=SC2046,SC2086   # word-splitting the name=conclusion listing IS the fixture builder
  _reset; _j=$(printf '%s' "$J_ALL" | sed 's/conformance-core=success/conformance-core=skipped/'); _mkjobs "$p/jobs" $_j
  _case needed-job-skipped-on-a-code-run    "push_graded=false reason=needed-job-not-success:conformance-core"
  # shellcheck disable=SC2046,SC2086   # word-splitting the name=conclusion listing IS the fixture builder
  _reset; _j=$(printf '%s' "$J_DOCS" | sed 's/conformance-docs=success/conformance-docs=failure/'); _mkjobs "$p/jobs" $_j
  _case docs-run-doc-job-red                "push_graded=false reason=docs-induction-docs-job-not-success"
  # shellcheck disable=SC2046,SC2086   # word-splitting the name=conclusion listing IS the fixture builder
  _reset; _j=$(printf '%s' "$J_DOCS" | sed 's/conformance-docs=success //'); _mkjobs "$p/jobs" $_j
  _case docs-run-without-a-doc-job          "push_graded=false reason=docs-induction-no-docs-job"

  # A PRE-SLICE docs-only run (conformance-core/-selftests still had no `if:`, so they RAN while the
  # cf-* shards skipped, and there was no conformance-docs job at all) is NOT induction-shaped: the
  # induction branch demands that EVERY heavy shard skipped, so a mixed run falls through to the full
  # suite. Measured live against run 33754855186 (PR #638) — the honest, fail-safe answer.
  # shellcheck disable=SC2046,SC2086   # word-splitting the name=conclusion listing IS the fixture builder
  _reset; _j=$(printf '%s' "$J_DOCS" | sed 's/conformance-core=skipped/conformance-core=success/; s/conformance-selftests=skipped/conformance-selftests=success/; s/conformance-docs=success //'); _mkjobs "$p/jobs" $_j
  _case legacy-mixed-docs-run               "push_graded=false reason=needed-job-not-success:cf-doctor"

  # --- (+/-) 233a: matrix legs, named reasons, and the run selected by workflow FILE (D3) ---
  # shellcheck disable=SC2046,SC2086   # word-splitting the name=conclusion listing IS the fixture builder
  _reset; _j=$(printf '%s' "$J_ALL" | sed 's/guard-battery=success/guard-battery~(1)=success guard-battery~(2)=success/'); _mkjobs "$p/jobs" $_j
  _case matrix-two-green-legs-earn-true     "$OK_ALL"
  # shellcheck disable=SC2046,SC2086   # word-splitting the name=conclusion listing IS the fixture builder
  _reset; _j=$(printf '%s' "$J_ALL" | sed 's/guard-battery=success/guard-battery~(1)=failure guard-battery~(2)=success/'); _mkjobs "$p/jobs" $_j
  _case matrix-one-red-leg-refuses          "push_graded=false reason=needed-job-not-success:guard-battery"
  # shellcheck disable=SC2046,SC2086   # word-splitting the name=conclusion listing IS the fixture builder
  _reset; _j=$(printf '%s' "$J_ALL" | sed 's/guard-battery=success //'); _mkjobs "$p/jobs" $_j
  _case matrix-no-leg-at-all-is-missing     "push_graded=false reason=needed-job-missing:guard-battery"
  _reset; _mkrun "$p/run" completed failure "$H" ',{"id":950,"name":"CI","path":".github/workflows/other.yml","run_number":9,"run_attempt":1,"status":"completed","conclusion":"success","head_sha":"'"$H"'",'"$PRS"'}'
  _case decoy-workflow-is-never-selected    "push_graded=false reason=run-not-success"
  # shellcheck disable=SC2046,SC2086   # word-splitting the name=conclusion listing IS the fixture builder
  _reset; _j=$(printf '%s' "$J_ALL" | sed 's/guard-battery=success/guard-battery~(1)=success guard-battery~(2)=failure/'); _mkjobs "$p/jobs" $_j
  _case matrix-last-leg-red-refuses         "push_graded=false reason=needed-job-not-success:guard-battery"
  # shellcheck disable=SC2046,SC2086   # word-splitting the name=conclusion listing IS the fixture builder
  _reset; _j=$(printf '%s' "$J_ALL" | sed 's/guard-battery=success/guard-battery-extra=success/'); _mkjobs "$p/jobs" $_j
  _case prefix-collision-is-not-a-leg       "push_graded=false reason=needed-job-missing:guard-battery"

  # --- 233a security N1/N2: the selected run is BOUND to the merged PR, and is a pull_request run ---
  # The LIVE shape (a completed run of a MERGED PR, measured read-only on #841-#843 and run 38667437837):
  # `pull_requests` is EMPTY once the PR merged, so the run is bound by head_branch and head_repository.
  _later() { # _later <id> <head_branch> <head_repo> <event> : a NEWER green run, same sha and workflow file
    printf ',{"id":%s,"name":"CI","path":".github/workflows/ci.yml","run_number":9,"run_attempt":1,"status":"completed","conclusion":"success","head_sha":"%s","head_branch":"%s","head_repository":{"full_name":"%s"},"event":"%s","pull_requests":[]}' "$1" "$H" "$2" "$3" "$4"
  }
  _reset; _case live-shape-empty-pull-requests-earns-the-skip "$OK_ALL"
  _reset; _mkrun "$p/run" completed failure "$H" "$(_later 960 feat/other "$R" pull_request)"
  _case later-green-run-of-another-branch   "push_graded=false reason=run-not-success"
  _reset; _mkrun "$p/run" completed failure "$H" "$(_later 961 feat/x forker/kit pull_request)"
  _case later-green-run-of-a-fork           "push_graded=false reason=run-not-success"
  _reset; _mkrun "$p/run" completed failure "$H" "$(_later 962 feat/x "$R" push)"
  _case later-green-run-of-another-event    "push_graded=false reason=run-not-success"
  _reset; sed 's/"number":7/"number":"x"/' "$p/pulls" > "$p/pulls.x"; mv "$p/pulls.x" "$p/pulls"
  _case non-numeric-pr-number-fails-closed  "push_graded=false reason=bad-pr-number"
  _reset; sed 's/"ref":"feat\/x"/"ref":""/' "$p/pulls" > "$p/pulls.x"; mv "$p/pulls.x" "$p/pulls"
  _mkrun "$p/run" completed success "$H" "$(_later 970 '' "$R" pull_request)"; sed 's/"head_branch":"feat\/x"/"head_branch":""/' "$p/run" > "$p/run.x"; mv "$p/run.x" "$p/run"
  _case empty-head-ref-never-matches        "push_graded=false reason=no-graded-run"

  # --- (−) the tree identity and the unknowns ---
  _reset; _case trees-differ                "push_graded=false reason=tree-mismatch" bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  _reset; _case non-40-hex-tree             "push_graded=false reason=bad-tree-id" deadbeef
  # The pushed sha is grammar-checked before it reaches jq (it is BOUND with --arg there, never
  # interpolated — this leg pins the grammar half of that pair).
  _reset
  _got=$(push_graded "$p/pulls" "$p/run" "$p/jobs" "$T" "$T" 'main"); ("x' "$R")
  if [ "$_got" = "push_graded=false reason=bad-github-sha" ]; then
    printf 'PASS: %-38s -> %s\n' non-40-hex-github-sha "$_got"
  else
    printf 'FAIL: %-38s -> %s (want push_graded=false reason=bad-github-sha)\n' non-40-hex-github-sha "$_got"; pst=1
  fi
  _reset; : > "$p/pulls";  _case empty-pulls-json  "push_graded=false reason=unreadable-input"
  _reset; echo 'not json' > "$p/run"; _case unparseable-run-json "push_graded=false reason=unreadable-input"
  _reset; rm -f "$p/jobs"; _case missing-jobs-json "push_graded=false reason=unreadable-input"

  # --- THE LOAD-BEARING NEGATIVE: `true` must be EARNED. If a mutation neuters any leg above, this
  #     fixture — a push whose tree is NOT the graded head's — must still refuse. A `true` here means
  #     a tree NOTHING graded was merged into main with the whole heavy suite skipped.
  _reset
  if [ "$(_pg bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb)" = "$OK_ALL" ]; then
    echo "FAIL: an UNGRADED tree was authorised for the push skip — this merges code nothing ran"; pst=1
  else
    echo "PASS: an ungraded tree can never earn push_graded=true (the one direction that must never happen)"
  fi

  rm -rf "$p"
  [ "$pst" = 0 ] && echo "ci-classify-changes --push-graded selftest: OK" || echo "ci-classify-changes --push-graded selftest: FAIL" >&2
  return "$pst"
}

# ── selftest_he : the --head-evidence predicate's teeth (SWAS-537, cells HE1-HE10). The question a merge
#    asks: did a COMPLETED run of the CI workflow on EXACTLY this head grade at least the light set? A wrong
#    `ok` merges a head nothing graded (the S3-SEC-2 window), so every negative asserts its EXACT line.
selftest_he() {
  hst=0; h=$(mktemp -d)
  H=2222222222222222222222222222222222222222; R=acme/kit
  PRS='"head_branch":"feat/x","head_repository":{"full_name":"acme/kit"},"event":"pull_request","pull_requests":[]'
  _hrun() { # _hrun <id> <run_number> <status> <conclusion> <head_sha> [path] [extra-fields]
    printf '{"id":%s,"path":"%s","run_number":%s,"run_attempt":1,"status":"%s","conclusion":"%s","head_sha":"%s",%s}' \
      "$1" "${6:-.github/workflows/ci.yml}" "$2" "$3" "$4" "$5" "${7:-$PRS}"
  }
  _hjobs() { # _hjobs <file> <name=conclusion ...>   (`~` in a name stands for a space)
    _ho=''; _hd=$1; shift
    for _hp in "$@"; do _ho="$_ho${_ho:+,}{\"name\":\"$(printf '%s' "${_hp%%=*}" | tr '~' ' ')\",\"conclusion\":\"${_hp#*=}\"}"; done
    printf '{"jobs":[%s]}\n' "$_ho" > "$_hd"
  }
  HJ_LIGHT='changes=success conformance-core=success conformance-selftests=success cf-doctor=success cf-export=success cf-export-claims=success cf-verify-enforced=success cf-claims=success cf-green-on-clone=success guard-battery=success guard-delta=success boundary-redteam=success conformance-docs=success docs-links=success conformance=success non-vacuity~(1)=success'
  HJ_DOCS='changes=success conformance-core=skipped conformance-selftests=skipped cf-doctor=skipped cf-export=skipped cf-export-claims=skipped cf-verify-enforced=skipped cf-claims=skipped cf-green-on-clone=skipped guard-battery=skipped guard-delta=skipped boundary-redteam=skipped conformance-docs=success docs-links=success conformance=success non-vacuity~(1)=skipped'
  HJ_CHEAP='changes=skipped conformance-core=skipped conformance-selftests=skipped cf-doctor=skipped cf-export=skipped cf-export-claims=skipped cf-verify-enforced=skipped cf-claims=skipped cf-green-on-clone=skipped guard-battery=skipped guard-delta=skipped boundary-redteam=skipped conformance-docs=skipped docs-links=skipped conformance=success non-vacuity~(1)=skipped'
  _hcase() { # _hcase <name> <runs-json-body> <jobs-listing> <expected-line> [head] [branch] [repo]
    printf '{"workflow_runs":[%s]}\n' "$2" > "$h/runs"
    # shellcheck disable=SC2086   # the HJ_* listings are deliberately word-split into name=conclusion args
    _hjobs "$h/jobs" $3
    _hg=$(head_evidence "$h/runs" "$h/jobs" "${5:-$H}" "${6:-feat/x}" "${7:-$R}")
    if [ "$_hg" = "$4" ]; then printf 'PASS: %-38s -> %s\n' "$1" "$_hg"
    else printf 'FAIL: %-38s -> %s\n           (want %s)\n' "$1" "$_hg" "$4"; hst=1; fi
  }
  OKR="$(_hrun 900 1 completed success "$H")"
  _hcase HE1-light-run-all-shards-ok        "$OKR" "$HJ_LIGHT" "evidence=ok reason=all-shards run=900"
  _hcase HE2-cheap-run-never-satisfies      "$OKR" "$HJ_CHEAP" "evidence=no reason=needed-job-not-success:changes run=900"
  _hcase HE3-queued-run-over-cheap-run      "$OKR,$(_hrun 901 2 queued '' "$H")" "$HJ_CHEAP" "evidence=no reason=run-not-completed run=901"
  _hcase HE4a-run-on-another-sha            "$(_hrun 900 1 completed success 4444444444444444444444444444444444444444)" "$HJ_LIGHT" "evidence=no reason=run-head-mismatch run=900"
  _hcase HE4b-run-on-another-branch         "$(_hrun 900 1 completed success "$H" '.github/workflows/ci.yml' '"head_branch":"feat/other","head_repository":{"full_name":"acme/kit"},"event":"pull_request","pull_requests":[]')" "$HJ_LIGHT" "evidence=no reason=no-graded-run"
  _hcase HE5-decoy-workflow-path            "$(_hrun 950 9 completed success "$H" .github/workflows/other.yml)" "$HJ_LIGHT" "evidence=no reason=no-graded-run"
  _hcase HE6-docs-only-induction-ok         "$OKR" "$HJ_DOCS" "evidence=ok reason=docs-only-induction run=900"
  _hcase HE7-needed-shard-skipped           "$OKR" "$(printf '%s' "$HJ_LIGHT" | sed 's/cf-doctor=success/cf-doctor=skipped/')" "evidence=no reason=needed-job-not-success:cf-doctor run=900"
  _hcase HE8-fork-head                      "$(_hrun 900 1 completed success "$H" '.github/workflows/ci.yml' '"head_branch":"feat/x","head_repository":{"full_name":"forker/kit"},"event":"pull_request","pull_requests":[]')" "$HJ_LIGHT" "evidence=no reason=no-graded-run"
  _hcase HE10a-matrix-leg-name-accepted     "$OKR" "$(printf '%s' "$HJ_LIGHT" | sed 's/conformance=success/conformance~(light)=success/')" "evidence=ok reason=all-shards run=900"
  _hcase HE10b-cheap-matrix-leg-refused     "$OKR" "$(printf '%s' "$HJ_CHEAP" | sed 's/conformance=success/conformance~(cheap)=success/')" "evidence=no reason=needed-job-not-success:changes run=900"
  # HE9: push_graded and head_evidence cannot diverge. The same run/jobs graded through both predicates must
  # carry the same reason (the existing push-graded fixtures above stay byte-identical on their own).
  T=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; S=1111111111111111111111111111111111111111
  printf '[{"number":7,"merged_at":"2026-09-03T00:00:00Z","merge_commit_sha":"%s","base":{"ref":"main","repo":{"full_name":"%s"}},"head":{"ref":"feat/x","sha":"%s","repo":{"full_name":"%s"}}}]\n' "$S" "$R" "$H" "$R" > "$h/pulls"
  for _hv in "$HJ_LIGHT" "$HJ_DOCS" "$HJ_CHEAP"; do
    printf '{"workflow_runs":[%s]}\n' "$OKR" > "$h/runs"
    # shellcheck disable=SC2086   # word-splitting the name=conclusion listing IS the fixture builder
    _hjobs "$h/jobs" $_hv
    _hpg=$(push_graded "$h/pulls" "$h/runs" "$h/jobs" "$T" "$T" "$S" "$R" | sed 's/^push_graded=true graded_pr=7 graded_head=[0-9a-f]* graded_run=900 //; s/^push_graded=false //')
    _hhe=$(head_evidence "$h/runs" "$h/jobs" "$H" feat/x "$R" | sed 's/^evidence=[a-z]* //; s/ run=900$//')
    if [ -n "$_hpg" ] && [ "$_hpg" = "$_hhe" ]; then printf 'PASS: %-38s -> %s\n' HE9-no-divergence "$_hpg"
    else printf 'FAIL: %-38s -> push_graded [%s] vs head_evidence [%s]\n' HE9-no-divergence "$_hpg" "$_hhe"; hst=1; fi
  done
  rm -rf "$h"
  [ "$hst" = 0 ] && echo "ci-classify-changes --head-evidence selftest: OK" || echo "ci-classify-changes --head-evidence selftest: FAIL" >&2
  return "$hst"
}

# ── selftest_eio : export_ignored_only()'s teeth. A wrong `false` costs artifact-gate minutes;
#    a wrong `true` SKIPS THE GATE on a change that CAN reach the artifact. Hermetic: this builds
#    its own temp git repo with a representative .gitattributes so it is independent of the
#    surrounding tree — it must pass under green-on-clone on the adopter export, whose
#    .gitattributes is neutered.
selftest_eio() {
  est=0; e=$(mktemp -d)
  ( cd "$e" && git init -q ) >/dev/null 2>&1
  cat > "$e/.gitattributes" <<'EOF'
BACKLOG.md export-ignore
docs/architecture/ export-ignore
docs/plans/ export-ignore
EOF

  _ewant() { # _ewant <name> <expected> <lines...>
    _en=$1; _eexp=$2; shift 2
    printf '%s\n' "$@" > "$e/$_en.listing"
    _egot=$(cd "$e" && export_ignored_only "$e/$_en.listing")
    if [ "$_egot" = "export_ignored_only=$_eexp" ]; then
      printf 'PASS: %-34s -> %s\n' "$_en" "$_egot"
    else
      printf 'FAIL: %-34s -> %s (want export_ignored_only=%s)\n' "$_en" "$_egot" "$_eexp"; est=1
    fi
  }

  # --- the ONE case that may be true ---
  _ewant all-export-ignored          true  'BACKLOG.md' 'docs/architecture/x.md'

  # --- THE load-bearing negative: one survivor among ignored files disqualifies the set ---
  _ewant one-exported-among-ignored  false 'BACKLOG.md' 'profiles/typescript-node/scaffold/a.ts'

  _ewant exported-only               false 'README.md'
  _ewant nested-under-ignored-dir    true  'docs/plans/deep/a.md'
  # Proves the PATTERN oracle, not tree presence: this path does not exist in the temp repo at all.
  _ewant deletion-of-exported        false 'profiles/typescript-node/scaffold/gone.ts'

  : > "$e/empty.listing"
  _egot=$(cd "$e" && export_ignored_only "$e/empty.listing")
  if [ "$_egot" = "export_ignored_only=false" ]; then echo "PASS: EMPTY listing                    -> export_ignored_only=false"
  else echo "FAIL: an EMPTY listing classified as $_egot"; est=1; fi

  _egot=$(cd "$e" && export_ignored_only "$e/does-not-exist.listing")
  if [ "$_egot" = "export_ignored_only=false" ]; then echo "PASS: UNREADABLE listing               -> export_ignored_only=false"
  else echo "FAIL: an UNREADABLE listing classified as $_egot"; est=1; fi

  # --- fail-safe: not a work tree at all ---
  _enwd=$(mktemp -d)
  printf '%s\n' 'BACKLOG.md' > "$_enwd/l.listing"
  _egot=$(cd "$_enwd" && export_ignored_only "$_enwd/l.listing")
  if [ "$_egot" = "export_ignored_only=false" ]; then echo "PASS: not-a-work-tree                  -> export_ignored_only=false"
  else echo "FAIL: not-a-work-tree classified as $_egot"; est=1; fi
  rm -rf "$_enwd"

  # --- THE LOAD-BEARING NEGATIVE: an exported (non-ignored) code path must NEVER be classified
  #     export_ignored_only=true. This is the assertion the non-vacuity sweep will mutate.
  printf '%s\n' 'profiles/typescript-node/scaffold/a.ts' > "$e/code.listing"
  _egot=$(cd "$e" && export_ignored_only "$e/code.listing")
  if [ "$_egot" = "export_ignored_only=true" ]; then
    echo "FAIL: an EXPORTED code path was classified export-ignored-only — this silently skips artifact-gate"; est=1
  else
    echo "PASS: an exported code path can never be classified export-ignored-only (the one direction that must never happen)"
  fi

  rm -rf "$e"
  [ "$est" = 0 ] && echo "ci-classify-changes --export-ignored-only selftest: OK" || { echo "ci-classify-changes --export-ignored-only selftest: FAIL" >&2; return 1; }
  return "$est"
}

# DISPATCH. The BARE `<listing-file>` invocation prints EXACTLY `docs_only=true|false` — a
# single-line contract consumers depend on (conformance/review-lane.sh:211 reads it via `tail -1`).
# The third predicate is reached ONLY through its own flag, never bolted onto the bare output, so
# adding it cannot change what an existing caller reads. ci.yml's `changes` job calls the classifier
# once bare (docs_only) and once with --export-ignored-only, appending both key=value lines.
case "${1:-}" in
  --selftest)            selftest; exit $? ;;
  --push-graded)         shift; push_graded "${1:-}" "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" "${7:-}" "${8:-}"; exit 0 ;;
  --export-ignored-only) shift; export_ignored_only "${1:-}"; exit 0 ;;
  --head-evidence)       shift; head_evidence "${1:-}" "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}"; exit 0 ;;
  "")                    echo "usage: ci-classify-changes.sh <listing-file> | --export-ignored-only <listing-file> | --head-evidence <runs.json> <jobs.json> <head-sha> <head-branch> <repo> [workflow-path] | --push-graded <pulls.json> <run.json> <jobs.json> <push_tree> <head_tree> <github_sha> <repo> [workflow-path] | --selftest" >&2; exit 2 ;;
  *)                     classify "$1"; exit 0 ;;
esac
