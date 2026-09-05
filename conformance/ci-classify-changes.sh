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
PG_NEEDED='changes conformance-core conformance-selftests cf-doctor cf-export cf-export-claims cf-verify-enforced cf-verify-selftest cf-claims cf-green-on-clone conformance'
PG_HEAVY='conformance-core conformance-selftests cf-doctor cf-export cf-export-claims cf-verify-enforced cf-verify-selftest cf-claims cf-green-on-clone'

_pg_no()  { echo "push_graded=false reason=$1"; }
_pg_hex() { case "${1:-}" in ''|*[!0-9a-f]*) return 1 ;; esac; [ "${#1}" -eq 40 ]; }
_pg_jq()  { printf '%s' "$1" | jq -r "$2" 2>/dev/null; }
_pg_conc() { printf '%s\n' "$_pgmap" | awk -F'\t' -v n="$1" '$1 == n { print $2; exit }'; }

push_graded() {
  _pu=${1:-}; _ru=${2:-}; _jo=${3:-}; _pt=${4:-}; _ht=${5:-}; _sha=${6:-}; _repo=${7:-}

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

  # 3. WHICH RUN, AND DID IT COMPLETE GREEN. Latest run_number/run_attempt among the CI runs.
  _r=$(jq -c 'if type == "array" then . else (.workflow_runs // []) end
              | [.[] | select(.name == "CI")] | sort_by(.run_number, .run_attempt) | last' "$_ru" 2>/dev/null) \
    || { _pg_no unreadable-input; return 0; }
  { [ -n "$_r" ] && [ "$_r" != null ]; } || { _pg_no no-graded-run; return 0; }
  [ "$(_pg_jq "$_r" '.head_sha')" = "$_hs" ]     || { _pg_no run-head-mismatch; return 0; }
  [ "$(_pg_jq "$_r" '.status')" = completed ]    || { _pg_no run-not-completed; return 0; }
  [ "$(_pg_jq "$_r" '.conclusion')" = success ]  || { _pg_no run-not-success; return 0; }
  _rid=$(_pg_jq "$_r" '.id')

  # 4. WHAT THAT RUN ACTUALLY GRADED. A run-level `success` is NOT enough: a run whose heavy shards
  #    all skipped is `success` too — that is precisely the docs-only case, and it earns the weaker
  #    (induction) authorisation, never the strong one.
  _pgmap=$(jq -r 'if type == "array" then . else (.jobs // []) end
                  | .[] | [.name, (.conclusion // "")] | @tsv' "$_jo" 2>/dev/null) \
    || { _pg_no unreadable-input; return 0; }
  [ -n "$_pgmap" ] || { _pg_no no-jobs; return 0; }
  _nv=$(printf '%s\n' "$_pgmap" | awk -F'\t' '$1 ~ /^non-vacuity/ { print $2 }')

  _r1=1; [ -n "$_nv" ] || _r1=0
  for _j in $PG_NEEDED; do [ "$(_pg_conc "$_j")" = success ] || _r1=0; done
  for _c in $_nv;        do [ "$_c" = success ] || _r1=0; done
  if [ "$_r1" = 1 ]; then
    echo "push_graded=true graded_pr=$_pr graded_head=$_hs graded_run=$_rid reason=all-shards"
    return 0
  fi

  _sk=1; [ -n "$_nv" ] || _sk=0
  for _j in $PG_HEAVY; do [ "$(_pg_conc "$_j")" = skipped ] || _sk=0; done
  for _c in $_nv;       do [ "$_c" = skipped ] || _sk=0; done
  if [ "$_sk" = 1 ] && [ "$(_pg_conc changes)" = success ]; then
    _d=$(_pg_conc conformance-docs)
    [ -n "$_d" ]         || { _pg_no docs-induction-no-docs-job; return 0; }
    [ "$_d" = success ]  || { _pg_no docs-induction-docs-job-not-success; return 0; }
    { [ "$(_pg_conc docs-links)" = success ] && [ "$(_pg_conc conformance)" = success ]; } \
      || { _pg_no docs-induction-support-not-success; return 0; }
    echo "push_graded=true graded_pr=$_pr graded_head=$_hs graded_run=$_rid reason=docs-only-induction"
    return 0
  fi
  _pg_no needed-job-not-success
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

  _mkpulls() { # _mkpulls <file> <merged_at> <merge_sha> <base_ref> <base_repo> <head_repo> <head_sha>
    printf '[{"number":7,"merged_at":%s,"merge_commit_sha":"%s","base":{"ref":"%s","repo":{"full_name":"%s"}},"head":{"sha":"%s","repo":{"full_name":"%s"}}}]\n' \
      "$2" "$3" "$4" "$5" "$7" "$6" > "$1"
  }
  _mkrun() { # _mkrun <file> <status> <conclusion> <head_sha> [more-json-entries]
    printf '{"workflow_runs":[{"id":900,"name":"CI","run_number":1,"run_attempt":1,"status":"%s","conclusion":"%s","head_sha":"%s"}%s]}\n' \
      "$2" "$3" "$4" "${5:-}" > "$1"
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
    cf-export=success cf-export-claims=success cf-verify-enforced=success cf-verify-selftest=success
    cf-claims=success cf-green-on-clone=success conformance-docs=success docs-links=success
    conformance=success non-vacuity~(1)=success non-vacuity~(2)=success'
  J_DOCS='changes=success conformance-core=skipped conformance-selftests=skipped cf-doctor=skipped
    cf-export=skipped cf-export-claims=skipped cf-verify-enforced=skipped cf-verify-selftest=skipped
    cf-claims=skipped cf-green-on-clone=skipped conformance-docs=success docs-links=success
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
  _reset; _mkrun "$p/run" completed success "$H" ',{"id":901,"name":"CI","run_number":2,"run_attempt":1,"status":"completed","conclusion":"failure","head_sha":"'"$H"'"}'
  _case two-runs-latest-failed              "push_graded=false reason=run-not-success"
  _reset; printf '{"workflow_runs":[{"id":9,"name":"Ratification","run_number":1,"run_attempt":1,"status":"completed","conclusion":"success","head_sha":"%s"}]}\n' "$H" > "$p/run"
  _case no-CI-run-on-that-head              "push_graded=false reason=no-graded-run"

  # --- (−) grading ---
  # shellcheck disable=SC2046,SC2086   # word-splitting the name=conclusion listing IS the fixture builder
  _reset; _j=$(printf '%s' "$J_ALL" | sed 's/conformance-core=success/conformance-core=skipped/'); _mkjobs "$p/jobs" $_j
  _case needed-job-skipped-on-a-code-run    "push_graded=false reason=needed-job-not-success"
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
  _case legacy-mixed-docs-run               "push_graded=false reason=needed-job-not-success"

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

case "${1:-}" in
  --selftest)    selftest; exit $? ;;
  --push-graded) shift; push_graded "${1:-}" "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" "${7:-}"; exit 0 ;;
  "")            echo "usage: ci-classify-changes.sh <listing-file> | --push-graded <pulls.json> <run.json> <jobs.json> <push_tree> <head_tree> <github_sha> <repo> | --selftest" >&2; exit 2 ;;
  *)             classify "$1"; exit 0 ;;
esac
