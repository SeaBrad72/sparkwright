#!/bin/sh
# poster-parity.sh — THE POSTERS ARE GONE, AND THEY MUST STAY GONE.
#
# WHAT THIS FILE USED TO BE (B5, 2026-08-07): the kit shipped SEVEN check-run POSTERS — workflow steps
# that computed a verdict and then POSTed it to GitHub's check-runs API under the required context's
# name — and this lock asserted one seven-property safe shape across all of them (server-side
# `?check_name=` lookup · PATCH-or-POST · conclusion-omission for the WAITING render · loud same-repo
# post failure · posted name never a job key in the same file · rc routed through the shared mapping ·
# `external_id` own-run identity). It closed a real class: a fix landing in one poster and never
# reaching the others, three times measured.
#
# WHY IT IS NOW THE INVERSE (REQUIRED-CHECK-POSTED-VIA-API-NOT-MATCHED, owner ruling 2026-08-27).
# The posters existed for ONE reason: a WAITING state ("a human has not approved yet") is not a build
# failure, and only a posted check-run can render yellow — a workflow job reports success / failure /
# skipped / cancelled and nothing else. Then the mechanism itself failed: GitHub branch protection
# stopped MATCHING the posted runs. Three PRs in nine days sat at "Expected — waiting for status to be
# reported" with every gate green, and each was cleared only by an admin merge. A merge gate that
# intermittently cannot be satisfied teaches people to bypass it, which is a worse outcome than a
# coarse colour. So every poster was deleted and each required context became a REAL JOB whose key is
# the context name and whose own conclusion is the verdict. WAITING now reds, and the check's own
# title says, in words, that it is not a build failure and what to do (locked by
# conformance/proportional-gate-wired.sh's legibility anchors).
#
# THE PROPERTY THIS FILE ASSERTS NOW: no shipped workflow contains a check-run poster or the
# `checks: write` scope one needs. Repo-wide and fail-closed, over .github/workflows/*.yml and
# profiles/*.yml — the same discovery scope the seven-poster registry covered, so a poster cannot come
# back in a file the old registry named, nor in a new one. Two independent tokens, because they fail
# differently: the `check-runs` API path a poster cannot avoid, and the scope it cannot work without.
#
# ⚠️ WHY THE SCOPE MATTERS AS MUCH AS THE POST. `checks: write` lets a job post a check-run of ANY name
# on ANY sha — including `control-plane-ratification`. The retired two-job splits existed to keep that
# token away from jobs that execute the PR's own scripts. With the token absent from every workflow,
# that containment is structural rather than arranged, and this lock is what keeps it so.
#
# COMMENT-STRIPPED, ALWAYS. These workflows must stay free to EXPLAIN the retired design at length —
# they all do, and they should. A lock that reds on its own documentation makes the comments
# load-bearing for the test, which is backwards (proportional-gate-wired.sh records the same rule after
# paying for it twice).
#
# HONEST CEILING: this proves ABSENCE in shipped source, not runtime conduct. It cannot see a poster
# added by a workflow this repo does not ship, an action pulled in by `uses:`, or a token minted from
# an App installation. It is the regression lock for a deletion, not a proof that nothing anywhere can
# post a check-run.
#
#   usage: sh conformance/poster-parity.sh [--selftest]   (run from repo root)
#   exit:  0 = no poster and no checks:write in any shipped workflow (or N/A on an adopter tree)
#          1 = a poster or the scope is back · 2 = usage
set -eu
cd "$(dirname "$0")/.."

# is_adopter_tree: 0 (true) iff NOT the kit's own tree. Same TWO export-ignored kit-dev markers
# ratification-parity.sh / adopter-gates-parity.sh use. This lock audits the KIT's OWN shipped
# workflows; wired into verify.sh it must N/A on any adopter tree (exit 0, NEVER 2).
is_adopter_tree() {
  [ ! -f docs/ROADMAP-KIT.md ] && [ ! -f .github/workflows/golden-path.yml ]
}

# code_join <file>: comment-stripped source with backslash-continued lines JOINED, so a multi-line
# `gh api` call greps as ONE logical line. Kept from the seven-poster era: a poster splices its URL
# across continuations, and a line-at-a-time scan would miss the one that matters.
code_join() {
  grep -v '^[[:space:]]*#' "$1" | awk '
    /\\$/ { sub(/\\$/, ""); buf = buf $0 " "; next }
    { print buf $0; buf = "" }
    END { if (buf != "") print buf }'
}

# scan_file <file> -> rc0 iff the file posts no check-run and grants no checks:write.
# Targets by ARGUMENT so the selftest drives it against fixtures (control-plane oracle: never
# env-redirectable).
scan_file() {
  _f="$1"; _rc=0
  [ -f "$_f" ] || return 0
  _src=$(code_join "$_f")
  if printf '%s\n' "$_src" | grep -q 'check-runs'; then
    printf '%s\n' "$_src" | grep -n 'check-runs' | while IFS= read -r _l; do
      echo "FAIL [P-no-poster] $_f: $_l"
    done
    echo "FAIL [P-no-poster] $_f posts (or reads) a check-run through the API. The required contexts are JOB CONCLUSIONS since 2026-08-27 — an API-posted run is exactly what branch protection stopped matching, which stranded three PRs at 'Expected — waiting for status to be reported'."
    _rc=1
  fi
  # `[[:space:]]+`, NOT `*`: a YAML permissions entry is always `checks: write`, and the zero-space
  # form matched this repo's own PROSE (a step named "no poster, no checks:write…" tripped it). An
  # anchor that fires on a description of itself is the false-positive class code_join exists to avoid.
  if printf '%s\n' "$_src" | grep -qE 'checks:[[:space:]]+write'; then
    echo "FAIL [P-no-scope] $_f grants 'checks: write'. Nothing posts any more, so nothing needs it — and that scope lets a job post a check-run of ANY name on ANY sha, including control-plane-ratification. Its absence is what makes the old two-job containment structural."
    _rc=1
  fi
  return "$_rc"
}

# The discovery scope: every shipped workflow, kit-own and adopter-reference alike. Fail-closed on the
# reference copies too — the mirror-divergence class has already cost this repo a Critical (fix the kit,
# ship the broken design to adopters, every parity lock green).
scan_all() {
  _st=0; _n=0
  for _f in .github/workflows/*.yml profiles/*.yml; do
    [ -e "$_f" ] || continue
    _n=$((_n + 1))
    scan_file "$_f" || _st=1
  done
  # ⚠️ NON-VACUITY (review round 1, finding 9). An ABSENCE check over a glob is green when the glob
  # matches NOTHING, and that is the single most likely way this lock rots: a directory rename, a
  # `cd` that did not happen, an export that ships no workflows. "We found no posters" and "we looked
  # at no files" are the same exit code without this line. It reports COUNT, and the count is the
  # evidence — a green that has scanned zero files is a FAILURE here, not a pass.
  if [ "$_n" -eq 0 ]; then
    echo "FAIL [P-vacuous] scanned 0 workflow files under .github/workflows/*.yml and profiles/*.yml. This check asserts an ABSENCE, so an empty scan is indistinguishable from a clean one — refusing to report OK. Run from the repo root; if the paths moved, this lock must move with them."
    return 1
  fi
  echo "poster-parity: scanned $_n shipped workflow file(s)"
  return "$_st"
}

selftest() {
  st=0
  # ⚠️ POSITIVE LEG FIRST. A matcher broken SHUT satisfies every negative assertion — the governing
  # lesson this repo relearned more than once. Prove the scanner passes a clean file before trusting
  # it to fail a dirty one.
  d=$(mktemp -d)
  printf 'jobs:\n  ceremony-binding:\n    permissions:\n      contents: read\n    steps:\n      - run: sh conformance/ceremony-binding.sh\n' > "$d/clean.yml"
  scan_file "$d/clean.yml" >/dev/null 2>&1 || { echo "FAIL: selftest — a clean real-job workflow must PASS"; st=1; }
  # MUTANT 1: a poster re-planted, in the exact shape the deleted ones had (continuation-split URL).
  printf 'jobs:\n  x:\n    steps:\n      - run: |\n          run_id=$(gh api "repos/o/r/commits/$SHA/check-runs?check_name=ceremony-binding" \\\n                     -q .id)\n' > "$d/poster.yml"
  scan_file "$d/poster.yml" >/dev/null 2>&1 && { echo "FAIL: selftest — a re-planted check-run poster must RED"; st=1; }
  # MUTANT 2: the scope re-planted with no posting call in sight. Locked separately because a token
  # granted "for later" is the step that precedes the poster's return.
  printf 'jobs:\n  x:\n    permissions:\n      contents: read\n      checks: write\n' > "$d/scope.yml"
  scan_file "$d/scope.yml" >/dev/null 2>&1 && { echo "FAIL: selftest — a re-planted 'checks: write' scope must RED"; st=1; }
  # MUTANT 3: BOTH tokens, but in COMMENTS. Must PASS — the workflows explain the retired design at
  # length, and a lock that forbids the documentation is the defect class this file exists downstream of.
  printf 'jobs:\n  x:\n    # the poster used to hit .../check-runs?check_name=x and hold checks: write\n    runs-on: ubuntu-latest\n' > "$d/prose.yml"
  scan_file "$d/prose.yml" >/dev/null 2>&1 || { echo "FAIL: selftest — the scanner fired on a COMMENT; it must read code only"; st=1; }
  # MUTANT 4 (finding 9): AN EMPTY SCAN MUST RED. Driven by cd-ing into a tree with no workflows at
  # all — the honest reproduction of a rename or a wrong cwd. A subshell so the real cwd is untouched.
  if ( cd "$d" && scan_all >/dev/null 2>&1 ); then
    echo "FAIL: selftest — scan_all reported OK having scanned ZERO files; an absence check that looked at nothing must never pass"; st=1
  else
    echo "OK: zero files scanned -> RED (the absence check cannot pass vacuously)"
  fi
  rm -rf "$d" 2>/dev/null || true
  # ...and the live tree, which is the assertion that actually ships.
  # ⚠️ THE SUMMARY MUST NAME WHAT WAS ACTUALLY ASSERTED (review round 2, nit 3). On an adopter tree the
  # live scan does not run, so a closing line claiming "no poster in any shipped workflow" would report
  # a conclusion this run never reached — the honest-headline defect this kit gates other people's
  # claims for. Two summaries, and the branch decides which is true.
  _scanned=1
  if is_adopter_tree; then
    _scanned=0
    echo "poster-parity: N/A — kit-self check (audits the kit's own shipped workflows; not present on an adopter tree)"
  else
    scan_all || st=1
  fi
  if [ "$st" != 0 ]; then
    echo "poster-parity --selftest: FAIL"
  elif [ "$_scanned" = 1 ]; then
    echo "poster-parity --selftest: OK (scanner proven on fixtures; no poster and no checks:write in any shipped workflow)"
  else
    echo "poster-parity --selftest: OK (scanner proven on FIXTURES ONLY — adopter tree, so the kit's shipped workflows were not scanned and nothing is claimed about them)"
  fi
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "")
      if is_adopter_tree; then
        echo "poster-parity: N/A — kit-self check (audits the kit's own shipped workflows; not present on an adopter tree)"
        exit 0
      fi
      if scan_all; then
        echo "OK: poster-parity — no check-run poster and no 'checks: write' in any shipped workflow; every required context is a job conclusion"
        exit 0
      fi
      echo "FAIL: poster-parity — the check-run poster design is back (see the tagged lines above). It was deleted on 2026-08-27 because branch protection stopped matching API-posted runs."
      exit 1 ;;
  *)          echo "usage: poster-parity.sh [--selftest]" >&2; exit 2 ;;
esac
