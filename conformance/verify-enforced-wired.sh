#!/bin/sh
# verify-enforced-wired.sh — assert the tree's CI pipeline(s) ENFORCE the conformance aggregate (run
# `verify.sh --require`), not merely the renderer (--selftest). Closes the per-PR control-enforcement
# gap durably: an edit reverting a KIT-EMITTED pipeline to --selftest-only fails this lock (T4-B1).
#   usage: sh conformance/verify-enforced-wired.sh [--wf=<path>]
#          sh conformance/verify-enforced-wired.sh --selftest
#          sh conformance/verify-enforced-wired.sh --fleet --expect-github=<n> --expect-gitlab=<m>
# Exit: 0 = enforced, or a disclosed N/A · 1 = drift / missing / bad argv · POSIX sh; dash-clean.
#
# ── THE DISPOSITION MATRIX (CP7R5-GATE-AUTHORITY dispositions §3, owner-approved 2026-07-22) ───────
# This check was promoted into the PORTABLE battery without a disposition for every tree the battery
# must pass on, and took two review BLOCKs and four failed repairs for it — each repair green on its
# own test, each one a disposition invented for a single cell of an input space nobody enumerated.
# The enumeration is now explicit. Three axes; every signal is STRUCTURAL, derived from the tree,
# never asserted by prose in a mutable doc (one line of ordinary CLAUDE.md prose once turned a
# governance FAIL into rc=0):
#
#   provenance | enforcing step | disposition
#   -----------+----------------+-------------------------------------------------------------------
#   kit-emitted|      yes       | PASS
#   kit-emitted|      NO        | FAIL — real drift: the kit shipped the step and someone removed it
#   kit-source |      yes       | PASS — the kit's OWN unmarked ci.yml, step intact
#   kit-source |      NO        | FAIL — the kit must self-enforce its own battery (review F1). Its own
#              |                |   top-level ci.yml is SOURCE (incept never installs it, so it is
#              |                |   unmarked) — but N/A here would be a self-governance hole.
#   adopter    |      yes       | PASS — they merged it, as docs/adoption/brownfield.md instructs
#   adopter    |      NO        | N/A-with-remedy — an unmet DOCUMENTED merge obligation, not a
#              |                |   failure. The exact YAML to paste is printed.
#   no pipeline at all, incepted | FAIL (fail-closed)
#   no pipeline, raw pre-incept  | N/A
#
# THE DRIFT LEG (KIT-UPDATE-PROFILE-CI-DRIFT) runs AFTER a PASS verdict above, never instead of one, and
# compares the workflow against the in-tree profiles/*/ pipelines by a SEMANTIC key (a capability registry,
# `_cap_registry`), never by bytes:
#
#   tree / state                                   | drift disposition
#   -----------------------------------------------+------------------------------------------------
#   kit source (_kit_source)                       | N/A — the kit's profiles are locked by --fleet
#   no in-tree profile pipeline for the platform   | N/A — nothing to compare against
#   the in-tree profiles lack the capability       | silent — current against what the adopter took
#   the workflow has it                            | silent (one OK clause: "CI capabilities current")
#   lacks it, carries `# kit-ci-decline: <id>`     | N/A — declined (declinable ids only; drift leg only)
#   lacks it, origin emitted                       | FAIL + the CI-DRIFT notice
#   lacks it, origin adopter (brownfield)          | the notice, rc 0 — a disclosed obligation, never red
#   a predicate error                              | FAIL (fail-closed)
#   (`--drift --wf= --profile=` is the same comparison for ONE pair, for kit-update: rc 0/1/2)
#
# PROVENANCE is the origin marker `# kit-pipeline-origin: emitted` that scripts/incept.sh stamps into
# the pipeline it INSTALLS (design §4, ratified P2; locked by conformance/pipeline-origin.sh, which
# also asserts the marker literal below has not drifted from incept's). Present -> kit-emitted;
# absent -> adopter-owned. A brownfield pipeline incept PRESERVED is never stamped.
# The THIRD value, kit-source, resolves an ambiguity in the binary above: an UNMARKED pipeline is the
# kit's OWN source when the tree is the kit repo — derived STRUCTURALLY (not by prose) via _kit_source:
# .github/workflows/golden-path.yml OR docs/ROADMAP-KIT.md, both control-plane and export-ignored, so
# no adopter export or incepted tree carries either. That downgrade (adopter -> kitsource) is a
# FAIL-ADDER only; the kit's own repo with the step present still PASSes.
# PLATFORM is file presence, and EVERY pipeline present is judged (see the dispatch at the foot).
#
# ★ HONEST CEILING — read this before trusting a green.
#   * The matrix covers the ENUMERATED rows. It does NOT prove the input space is exhausted; an
#     unenumerated combination is the exact failure mode this design exists to address. Every such
#     combination therefore FAILS CLOSED (asserted in --selftest), and no verdict here claims more.
#   * Removing the origin marker downgrades enforcement to a DISCLOSED N/A. §4 accepts that as a
#     self-assertion of ownership — it is the one non-derived signal in this design.
#   * Suppression detection is STEP/JOB-SCOPED and an ENUMERATION, not a decision procedure (§5, see
#     the matchers below): KNOWN suppression forms are rejected on the OWNING step OR job, in BLOCK and
#     FLOW-LIST (`[ … ]`) form; the class is NOT closed. A sufficiently creative pipeline can still
#     present the step and prevent it failing the build. Only the ENUMERATED `if: false` (normalised) is
#     caught at job level — an arbitrary `if:` expression (a branch guard) stays honest-ceiling. An
#     UNRELATED suppressor elsewhere in the file (another step, another job) is (correctly) irrelevant.
set -eu

# The contract string, stated LITERALLY because this check runs on adopter trees, which have no
# scripts/incept.sh to derive it from. That duplication is a drift risk with a fail-OPEN failure mode
# (a diverged marker classifies every emitted pipeline adopter-owned and silently downgrades the whole
# gate to N/A), so conformance/pipeline-origin.sh — which IS kit-only and DOES derive from incept.sh —
# asserts the two strings are identical, with a mutation proving a divergence goes RED.
PIPELINE_ORIGIN_MARKER='# kit-pipeline-origin: emitted'
GH_WF='.github/workflows/ci.yml'
GL_WF='.gitlab-ci.yml'

# ── PLATFORM SELECTION (CP7R5-GATE-AUTHORITY C1, then the dispositions rebuild) ────────────────────
# `scripts/incept.sh --ci gitlab` installs .gitlab-ci.yml at the root and NO .github/workflows/ci.yml.
# A GitHub-only single-tree check therefore FAILs on EVERY GitLab adopter — and because this check is
# registered in the portable battery, and the battery is a blocking step in the pipeline this slice
# adds, their first run would be red with no in-tree remedy.
# MEASURED, not inherited (re-measured 2026-07-22 against a real export -> incept --ci gitlab):
# `git archive HEAD` ships `.github/workflows/` as an EMPTY DIRECTORY (workflows are export-ignored),
# and after a `--ci gitlab` incept it is STILL empty. So the DIRECTORY is a useless signal — it always
# exists — and the FILE is the signal. Keying on the directory is what broke repair attempt #1.
# Selection is DERIVED FROM THE TREE (file presence), never an env override of a control-plane path:
# the old `VERIFY_ENFORCED_WF` env read is deleted, and the seam is the `--wf=<path>` ARGUMENT.

# _pipeline_origin <file> -> emitted | adopter | none. The provenance axis, by fixed string.
_pipeline_origin() {
  if [ ! -f "$1" ]; then echo none; return; fi
  if grep -qF "$PIPELINE_ORIGIN_MARKER" "$1"; then echo emitted; else echo adopter; fi
}

# ── PLATFORM-AWARE MATCHING (CP7R5-GATE-AUTHORITY) ────────────────────────────────────────────────
# The kit emits pipelines for TWO platforms, and they express a command differently:
#   GitHub Actions   run: sh conformance/verify.sh --require
#   GitLab CI        script:  →  - sh conformance/verify.sh --require        (block-list form)
#                    script: [sh conformance/verify.sh --require]            (flow-list form)
# A `run:`-only matcher is GitHub-blind-spotted: pointed at a .gitlab-ci.yml it can only ever say
# FAIL — fail-safe, but unable to confirm a CORRECT GitLab pipeline. Since `incept --ci gitlab`
# installs profiles/<stack>/ci.gitlab-ci.yml as a real adopter's .gitlab-ci.yml, a GitHub-only
# contract would itself be the stack-neutrality defect this kit exists to prevent.
#
# The platform is an explicit ARGUMENT, never sniffed from file content. In --fleet it is derived
# from the filename glob this script itself controls (ci.yml → github, ci.gitlab-ci.yml → gitlab),
# so the classification is deterministic rather than a heuristic that can be fooled.

# ── STEP/JOB-SCOPED SUPPRESSION (design §5 — security review OVERTURNED the old file-level posture) ──
# A disqualifier — the `|| true` class wearing YAML clothes: continue-on-error/if:false (GitHub),
# allow_failure/when:manual|never (GitLab) — leaves the step PRESENT but unable to fail the build. It is
# now SCOPED to the step/job that OWNS the `verify.sh --require` invocation, never the file: "can THIS
# step fail the build" is not a file-level question, and it is not regex-decidable in general (§5). The
# old file-level grep hard-FAILed ordinary pipelines — an unrelated Codecov step with
# `continue-on-error: true`, a `when: manual` deploy job — whose enforcing step was fully intact. That
# is a false positive that breaks real adopters; §5 removes the class. An unrelated suppression key
# ELSEWHERE in the file is now irrelevant; only a suppressor on the OWNING step/job disqualifies.
# Matching is NORMALISED first (§5.2): trailing comment stripped, lowercased, quotes stripped, a leading
# `- ` allowed, booleans treated as (true|yes|on) — so `True`, `yes`, `when: "manual"`, a trailing
# comment, and a leading `- ` are all caught on the owning step. CEILING: this is an ENUMERATION of
# known forms, NOT a decision procedure — a sufficiently creative pipeline can still present the step
# and prevent it failing the build. Stated in the header and the selftest banner; no verdict claims the
# class is closed.

# _suppressed / _enf are expressed once, inside each awk program below. The suppression set is the
# `|| true` family generalised: `|| :` is ONE CHARACTER from the fixture the selftest already asserted
# and passed the old lock, which is why this is a set rather than a literal.

# _ep_github <file>: an UNCOMMENTED, UNSUPPRESSED `run:` step invoking verify.sh --require, in a STEP
# BLOCK carrying no disqualifying key, whose OWNING JOB carries no job-level `if: false`. The `- `-
# delimited step block that owns the run: is buffered and judged ALONE — a disqualifier in ANOTHER step
# block is ignored (§5). Job structure (`jobs:` → job-name indent → keys) is tracked so a job-level
# `if: false` (the enumerated token, normalised) disqualifies only the OWNING job — an UNRELATED job's
# `if: false` is reset at the next job boundary (job-scope, NOT file-scope); an arbitrary `if:` branch
# guard is honest-ceiling, never evaluated. A file with no `jobs:` structure keeps the bare step-block
# behaviour unchanged. Accepts the inline `- run: …` list form (a documented false negative the previous
# lock rejected). Assumes a single-line `run:`; a block-scalar refactor fails SAFE/over-strict, never a
# false pass.
_ep_github() {
  awk '
    function strip(s) { sub(/#.*/, "", s); return s }
    function suppressed(s) {                   # F2: flow-list terminators (] , " '\'') are boundaries too
      gsub(/[],"]/, " ", s); gsub(/'\''/, " ", s)
      return (s ~ /\|\|[[:space:]]*true([[:space:]]|$)/) || (s ~ /\|\|[[:space:]]*:([[:space:]]|$)/) ||
             (s ~ /\|\|[[:space:]]*exit[[:space:]]+0/)   || (s ~ /;[[:space:]]*true[[:space:]]*$/) ||
             (s ~ /&&[[:space:]]*true[[:space:]]*$/)
    }
    function disq(s,   n) {                    # §5.2 normalise, then match a STEP-level suppressor
      n = tolower(s); gsub(/"/, "", n); gsub(/'\''/, "", n); sub(/^[[:space:]]*-[[:space:]]*/, "", n)
      return (n ~ /^[[:space:]]*continue-on-error:[[:space:]]*(true|yes|on)[[:space:]]*$/) ||
             (n ~ /^[[:space:]]*if:[[:space:]]*false[[:space:]]*$/)
    }
    function jobif(s,   n) {                    # F1: §5.2 normalise, then a JOB-level ENUMERATED if:false
      n = tolower(s); gsub(/"/, "", n); gsub(/'\''/, "", n)   # arbitrary if: expressions stay honest-ceiling
      return (n ~ /^[[:space:]]*if:[[:space:]]*false[[:space:]]*$/)
    }
    function flushb() { if (b_enf && !b_disq) j_enf = 1; b_enf = 0; b_disq = 0 }
    function flushj() { flushb(); if (j_enf && !j_disq) f = 1; j_enf = 0; j_disq = 0 }
    /^[[:space:]]*#/ { next }
    {
      s = strip($0)
      i = match(s, /[^ ]/) ? RSTART - 1 : length(s)     # indentation depth
      blank = (s ~ /^[[:space:]]*$/)
      dash = (s ~ /^[[:space:]]*-[[:space:]]/)
      # F1: attribute a job-level if:false to the OWNING job. `jobs:` opens the block; the first child
      # indent is the job-name level; a non-dash key at that level is a new job (flush the prior job).
      # Fires ONLY when a real `jobs:` structure is present, so bare step-block snippets are unchanged,
      # and an UNRELATED job if:false is reset at the next job boundary — job-scope, never file-scope.
      if (s ~ /^[[:space:]]*jobs:[[:space:]]*$/) { flushj(); injobs = 1; jni = -1; inb = 0; next }
      if (injobs && !blank) {
        if (jni < 0) jni = i
        else if (i < jni) injobs = 0                    # dedented out of the jobs: block
        if (injobs && i == jni && !dash) { flushj(); inb = 0; next }   # a new job header
      }
      if (dash && (!inb || i <= bi)) { flushb(); inb = 1; bi = i }   # a new step block at this indent
      else if (!dash && inb && i <= bi) { flushb(); inb = 0 }        # dedented out of the steps list
      if (inb) {
        if (s ~ /^[[:space:]]*-?[[:space:]]*run:[[:space:]]/ && s ~ /conformance\/verify\.sh/ &&
            s ~ /--require/ && !suppressed(s)) b_enf = 1
        if (disq(s)) b_disq = 1
      } else if (injobs && jobif(s)) {
        j_disq = 1                              # job-level if:false, attributed to THIS (owning) job
      }
    }
    END { flushj(); exit(f ? 0 : 1) }
  ' "$1"
}

# _ep_gitlab <file>: the invocation must sit in an EXECUTABLE position — inside a script/before_script/
# after_script block of a NON-hidden job — and that OWNING JOB must carry no disqualifier. The previous
# regex allowed `-[[:space:]]` anchored to nothing, so ANY YAML list item satisfied it: security review
# confirmed a `- sh conformance/verify.sh --require` under `cache: paths:` passed the lock while never
# being a command at all. Job context is tracked, so a `.hidden-job:` template (never executed by
# GitLab) cannot satisfy it; allow_failure/when:manual|never are attributed to their OWNING job (job
# level OR inside a rules: entry), and only the job that owns the enforcing invocation is judged (§5) —
# an unrelated `deploy-prod: {when: manual}` job no longer disqualifies the whole file.
_ep_gitlab() {
  awk '
    function strip(s) { sub(/#.*/, "", s); return s }
    function suppressed(s) {                   # F2: the shipped GitLab shape is `script: [ … ]`, so a
      gsub(/[],"]/, " ", s); gsub(/'\''/, " ", s)   # suppressor is terminated by ] , or a quote — not only
      return (s ~ /\|\|[[:space:]]*true([[:space:]]|$)/) || (s ~ /\|\|[[:space:]]*:([[:space:]]|$)/) ||
             (s ~ /\|\|[[:space:]]*exit[[:space:]]+0/)   || (s ~ /;[[:space:]]*true[[:space:]]*$/) ||
             (s ~ /&&[[:space:]]*true[[:space:]]*$/)   # whitespace/EOL. Normalise those to a boundary first.
    }
    function enf(s) { return (s ~ /conformance\/verify\.sh/) && (s ~ /--require/) && !suppressed(s) }
    function disq(s,   n) {                    # §5.2 normalise, then match a JOB-level suppressor
      n = tolower(s); gsub(/"/, "", n); gsub(/'\''/, "", n); sub(/^[[:space:]]*-[[:space:]]*/, "", n)
      return (n ~ /^[[:space:]]*allow_failure:[[:space:]]*(true|yes|on)[[:space:]]*$/) ||
             (n ~ /^[[:space:]]*when:[[:space:]]*(manual|never)[[:space:]]*$/)
    }
    function flush() { if (j_enf && !hidden && !j_disq) f = 1; j_enf = 0; j_disq = 0 }
    /^[[:space:]]*#/ { next }
    {
      l = strip($0)
      if (l ~ /^[^[:space:]].*:/) {                      # a top-level key = a job (or stages/variables)
        flush()
        k = l; sub(/:.*/, "", k)
        hidden = (substr(k, 1, 1) == ".")                # GitLab treats a leading "." as a template
        ins = 0
        next
      }
      if (disq(l)) j_disq = 1                            # per-job disqualifier (job level OR in rules:)
      if (l ~ /^[[:space:]]*(before_script|script|after_script):/) {
        ins = 1
        if (enf(l)) j_enf = 1                            # flow-list form: script: [ … ]
        next
      }
      if (l ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_-]*:/) { ins = 0; next }   # any other key ends the block
      if (ins && l ~ /^[[:space:]]*-[[:space:]]/ && enf(l)) j_enf = 1
    }
    END { flush(); exit(f ? 0 : 1) }
  ' "$1"
}

# enforcing_present <file> [platform]: platform defaults to github (every pre-existing caller).
# An UNRECOGNISED platform returns FAIL — fail-safe, matching the block-scalar posture above.
enforcing_present() {
  case "${2:-github}" in
    github) _ep_github "$1" ;;
    gitlab) _ep_gitlab "$1" ;;
    *)      return 1 ;;
  esac
}

# _wf_disposition <wf_exists:0|1> <must_have:0|1> <origin:emitted|adopter|none> <step_present:0|1>
#   -> PASS | NA | NA-REMEDY | FAIL
# THE §3 MATRIX, as a PURE FUNCTION over arguments — no file reads, no globals, so every row is
# testable without a fixture tree and none of it can be redirected by the environment (an
# env-redirectable control-plane path is the vacuity this repo forbids).
# The pipeline files are export-ignored: incept installs profiles/<stack>/ci.yml, so a PRE-INCEPT
# export has no pipeline to enforce yet (NA). A tree that MUST have one (incepted adopter OR the kit
# repo) with none at all is a real regression (FAIL).
# The THIRD axis — provenance — is what separates DRIFT from an UNMET DOCUMENTED MERGE OBLIGATION:
# the kit's own brownfield documentation instructs adopters to merge the gate ids by hand, so failing
# them for not having done it yet is failing them for a state the kit's documentation created.
# FAIL-CLOSED IS THE DEFAULT, not a fallback: any argument value outside the enumerated domain lands
# on FAIL. The design's own honest ceiling is that this input space is not proven exhausted, so an
# unenumerated combination must never fall through to a silent pass.
_wf_disposition() {
  case "${1:-}" in 0|1) ;; *) echo FAIL; return ;; esac
  case "${2:-}" in 0|1) ;; *) echo FAIL; return ;; esac
  case "${4:-}" in 0|1) ;; *) echo FAIL; return ;; esac
  if [ "$1" = 0 ]; then
    if [ "$2" = 1 ]; then echo FAIL; else echo NA; fi
    return
  fi
  if [ "$4" = 1 ]; then echo PASS; return; fi
  case "${3:-}" in
    emitted)   echo FAIL ;;
    kitsource) echo FAIL ;;   # the kit's OWN repo dropped its OWN battery step — self-enforcement drift (§3)
    adopter)   echo NA-REMEDY ;;
    *)         echo FAIL ;;
  esac
}
# _must_have_workflow [root] -> 1 iff incepted adopter (ENGINEERING-PRINCIPLES.md) OR the kit repo (kit-only
# markers; golden-path.yml is control-plane + export-ignored, un-spoofable). A raw export has none -> 0.
# Parameterized on <root> (default cwd) so the selftest can lock both branches against fixtures (a marker
# rename returning 0 on an incepted tree would fail-OPEN the gate to a silent NA — that must fail a test).
_must_have_workflow() {
  _mhr=${1:-.}
  { [ -f "$_mhr/ENGINEERING-PRINCIPLES.md" ] || [ -f "$_mhr/docs/ROADMAP-KIT.md" ] || [ -f "$_mhr/.github/workflows/golden-path.yml" ]; } \
    && echo 1 || echo 0
}
# _kit_source [root] -> 1 iff this tree is the KIT'S OWN repo (design §3, review F1). A DELIBERATELY
# NARROWER predicate than _must_have_workflow: only .github/workflows/golden-path.yml OR docs/ROADMAP-KIT.md
# — both control-plane and export-ignored, so no adopter export or incepted tree carries either.
# It MUST NOT include ENGINEERING-PRINCIPLES.md: an incepted brownfield adopter has that file (incept
# renames CLAUDE.md) but neither kit marker, and folding it in would misclassify that adopter as
# kit-source and wrongly FAIL them — the exact false-FAIL class §3 exists to remove. The two marker sets
# are cleanly disjoint precisely BECAUSE this predicate does not reuse _must_have_workflow's.
_kit_source() {
  _ksr=${1:-.}
  { [ -f "$_ksr/.github/workflows/golden-path.yml" ] || [ -f "$_ksr/docs/ROADMAP-KIT.md" ]; } \
    && echo 1 || echo 0
}

# _remedy_yaml <github|gitlab> — the EXACT step to paste, taken from the shipped profile pipelines
# (profiles/typescript-node/ci.yml and .../ci.gitlab-ci.yml). The YAML DIFFERS per platform, which is
# why it is not one string: telling a GitLab adopter to add a `run:` step is telling them nothing.
# A blocking gate whose constraint is undocumented and undiagnosable is, in this check's own words,
# "the classic path to the gate being deleted" — so the remedy ships with the verdict, not in a doc.
_remedy_yaml() {
  if [ "$1" = gitlab ]; then
    echo "      conformance-aggregate:"
    echo "        stage: verify"
    echo "        needs: []"
    echo "        script: [sh conformance/verify.sh --require]"
  else
    echo "      - name: Conformance aggregate (required — DEVELOPMENT-STANDARDS.md §14)"
    echo "        run: sh conformance/verify.sh --require"
  fi
}

# _judge <file> <platform> -> 0 (PASS or a disclosed N/A) · 1 (FAIL); prints the verdict, the CAUSE
# and, where there is one, the remedy. Every message names $CI_WF and $_PLATFORM — never a hardcoded
# literal. The old message hardcoded `ci.yml` and asserted "renderer-only (--selftest)" even when the
# step was simply ABSENT: a brownfield tree was told something false and a GitLab tree was told about
# a GitHub path it does not have.
_judge() {
  CI_WF=$1; _PLATFORM=$2; _J_PASS=0; _J_ORIGIN=''
  _j_step=$(enforcing_present "$CI_WF" "$_PLATFORM" && echo 1 || echo 0)
  _j_origin=$(_pipeline_origin "$CI_WF")
  # THE KIT-SOURCE DOWNGRADE (design §3, review F1) lives in the IMPURE layer — "am I the kit repo" is a
  # TREE fact, alongside the other tree reads here, never threaded into the pure _wf_disposition. An
  # UNMARKED pipeline in the kit's OWN repo is source, not an adopter's: it must self-enforce (FAIL on
  # drift), not fall to N/A. Direction is fail-closed — this only rewrites 'adopter' to 'kitsource', both
  # of which PASS when the step is present, so it can never open a bypass.
  if [ "$_j_origin" = adopter ] && [ "$(_kit_source)" = 1 ]; then _j_origin=kitsource; fi
  case "$(_wf_disposition 1 1 "$_j_origin" "$_j_step")" in
    PASS)
      _J_PASS=1; _J_ORIGIN=$_j_origin   # the drift leg runs only on a PASS, and needs the provenance
      echo "OK: $CI_WF enforces the conformance aggregate ($_PLATFORM: a real 'verify.sh --require' step; origin: $_j_origin)"
      return 0 ;;
    FAIL)
      if [ "$_j_origin" = kitsource ]; then
        echo "FAIL: $CI_WF ($_PLATFORM) is the KIT'S OWN pipeline — this is the sparkwright repo"
        echo "  (.github/workflows/golden-path.yml or docs/ROADMAP-KIT.md is present) — yet it no longer runs an"
        echo "  unsuppressed, uncommented 'sh conformance/verify.sh --require'. The kit MUST self-enforce its own"
        echo "  conformance battery (core principle 4: if it isn't automated, it isn't enforced). This is not an"
        echo "  adopter merge obligation — the kit dropped its OWN step. Restore it in $CI_WF:"
        _remedy_yaml "$_PLATFORM"
        return 1
      fi
      echo "FAIL: $CI_WF ($_PLATFORM) carries the kit's origin marker '$PIPELINE_ORIGIN_MARKER' — the kit"
      echo "  INSTALLED this pipeline — but it no longer runs an unsuppressed, uncommented"
      echo "  'sh conformance/verify.sh --require'. That is DRIFT: the enforcing step was removed from a"
      echo "  pipeline its remover did not author. Restore it in $CI_WF:"
      _remedy_yaml "$_PLATFORM"
      return 1 ;;
    NA-REMEDY)
      echo "N/A: $CI_WF ($_PLATFORM) carries no kit origin marker — it is ADOPTER-OWNED. incept PRESERVES an"
      echo "  existing pipeline (docs/adoption/brownfield.md) and instructs you to merge the kit's gate ids"
      echo "  by hand. The conformance aggregate is NOT enforced here: this is a disclosed, unmet merge"
      echo "  obligation, not a failure. To enforce it, add to $CI_WF:"
      _remedy_yaml "$_PLATFORM"
      return 0 ;;
  esac
  # Unreachable via _wf_disposition's enumerated returns — and therefore exactly the shape that has
  # gone wrong four times in this slice. Fail CLOSED rather than fall off the end with rc 0.
  echo "FAIL: $CI_WF ($_PLATFORM) — no enumerated disposition (origin='$_j_origin', step=$_j_step). Fail-closed by design: see the matrix in this file's header."
  return 1
}

# ── K5 (ADOPTER-KIT-SELFTESTS-ON-CHANGE) — the emitted pipelines pass `--changed` ONLY on a pull request ──
# Design §4.3/§7. A pipeline may let verify.sh skip the kit's own selftests only when (1) the listing comes
# from a step gated to pull_request, whose base sha is ENV-BOUND (never interpolated into a `run:` line) and
# which refuses a newline-bearing path set; (2) the ONE verify.sh line passes `--changed` only through
# `${KIT_CHANGED:+…}`, so push / schedule / a failed or refused diff run plain `verify.sh --require`
# (the full battery); and (3) GitHub also passes `--summary-file "$GITHUB_STEP_SUMMARY"`, plus a WEEKLY
# `schedule:` cron. The verify.sh line stays ONE line on purpose: _ep_github/_ep_gitlab above read a
# single-line `run:`/script item. Comment lines are ignored. Each helper prints one reason per violation.
_KST_GH_LINE='run: sh conformance/verify.sh --require ${KIT_CHANGED:+--changed "$KIT_CHANGED" --summary-file "$GITHUB_STEP_SUMMARY"}'
_KST_GL_LINE='- sh conformance/verify.sh --require ${KIT_CHANGED:+--changed "$KIT_CHANGED"}'
_kst_wiring_github() {  # <file> -> 0 conforming; else 1 with reasons
  _kw_t=$(grep -v '^[[:space:]]*#' "$1") || _kw_t=""; _kw_rc=0
  printf '%s\n' "$_kw_t" | grep -Eq '^  schedule:' || { echo "K5: $1 has no 'schedule:' trigger"; _kw_rc=1; }
  printf '%s\n' "$_kw_t" | grep -Eq "^[[:space:]]*-[[:space:]]*cron:[[:space:]]*['\"][0-9*/,-]+ [0-9*/,-]+ \* \* [0-6]['\"]" || { echo "K5: $1 has no WEEKLY cron (want 'm h * * <0-6>')"; _kw_rc=1; }
  _kw_n=$(printf '%s\n' "$_kw_t" | grep -c 'github\.event\.pull_request\.base\.sha') || true
  _kw_ok=$(printf '%s\n' "$_kw_t" | grep -Ec '^[[:space:]]+BASE_SHA: \$\{\{ github\.event\.pull_request\.base\.sha \}\}[[:space:]]*$') || true
  { [ "$_kw_n" -ge 1 ] && [ "$_kw_n" = "$_kw_ok" ]; } || { echo "K5: $1 must use the PR base sha ONLY as an env: 'BASE_SHA: \${{ github.event.pull_request.base.sha }}' (found $_kw_n use(s), $_kw_ok env-bound)"; _kw_rc=1; }
  printf '%s\n' "$_kw_t" | awk '
    function flush() { if (d) { if (g && nl) good = 1; else bad = 1 } d = 0; g = 0; nl = 0 }
    /^[[:space:]]*-[[:space:]]+name:/ { flush() }
    /git diff/ { d = 1; if ($0 !~ /--no-renames/ || $0 !~ / -z /) bad = 1 }
    /if:[[:space:]]*github\.event_name == .pull_request./ && /github\.base_ref == github\.event\.repository\.default_branch/ { g = 1 }
    /tr -cd .\\n./ { nl = 1 }
    END { flush(); exit(good && !bad ? 0 : 1) }' || { echo "K5: $1 has no 'git diff -z --no-renames' listing step gated by if: github.event_name == 'pull_request' && github.base_ref == github.event.repository.default_branch (S2) that refuses a newline-bearing path set (tr -cd '\\n', R6)"; _kw_rc=1; }
  printf '%s\n' "$_kw_t" | grep -q 'GITHUB_ENV' || { echo "K5: $1's listing step never exports KIT_CHANGED via GITHUB_ENV"; _kw_rc=1; }
  printf '%s\n' "$_kw_t" | grep -qF -- "$_KST_GH_LINE" || { echo "K5: $1 lacks the single verify line: $_KST_GH_LINE"; _kw_rc=1; }
  _kw_n=$(printf '%s\n' "$_kw_t" | grep -c -e '--changed') || true
  [ "$_kw_n" = 1 ] || { echo "K5: $1 mentions --changed on $_kw_n non-comment line(s), want exactly the one verify line"; _kw_rc=1; }
  return "$_kw_rc"
}
_kst_wiring_gitlab() {  # <file> -> 0 conforming; else 1 with reasons
  _kw_t=$(grep -v '^[[:space:]]*#' "$1") || _kw_t=""; _kw_rc=0
  for _kw_k in merge_request_event CI_MERGE_REQUEST_DIFF_BASE_SHA CI_MERGE_REQUEST_TARGET_BRANCH_NAME CI_DEFAULT_BRANCH '--no-renames' 'git diff -z' 'mktemp' "tr -cd '\\n'"; do
    printf '%s\n' "$_kw_t" | grep -qF -e "$_kw_k" || { echo "K5: $1 lacks '$_kw_k' in the listing step (merge-request + default-branch gate, mktemp files, newline refusal)"; _kw_rc=1; }
  done
  ! printf '%s\n' "$_kw_t" | grep -qF '/tmp/kit-changed' || { echo "K5: $1 uses a fixed /tmp/kit-changed.* listing path (use mktemp)"; _kw_rc=1; }
  printf '%s\n' "$_kw_t" | grep -qF -- "$_KST_GL_LINE" || { echo "K5: $1 lacks the single verify line: $_KST_GL_LINE"; _kw_rc=1; }
  ! printf '%s\n' "$_kw_t" | grep -q 'GITHUB_STEP_SUMMARY' || { echo "K5: $1 passes GITHUB_STEP_SUMMARY on GitLab"; _kw_rc=1; }
  _kw_n=$(printf '%s\n' "$_kw_t" | grep -c -e '--changed') || true
  [ "$_kw_n" = 1 ] || { echo "K5: $1 mentions --changed on $_kw_n non-comment line(s), want exactly the one verify line"; _kw_rc=1; }
  return "$_kw_rc"
}

# ── KIT-UPDATE-PROFILE-CI-DRIFT — kit-owned CI CAPABILITIES (design 2026-10-05) ─────────────────────
# A kit-owned CI block is a CAPABILITY: a named fact about the pipeline the kit needs and the adopter can
# satisfy any way they like. The registry below is the one source of `since` (checked against CHANGELOG
# headings by --fleet, lock 3). Profiles carry only `# >>> kit:owned <id>` / `# <<< kit:owned <id>` markers,
# which exist to PRINT the block in the notice — detection never reads them (an adopter's adapted workflow
# has none), it uses a SEMANTIC key (_drift_has), never a byte comparison.
# _VEW_DRIFT is the greppable switch the selftest flips in a copy to prove the leg is the only red.
_VEW_DRIFT=on
_cap_registry() {  # id|since|declinable|purpose — no forge, stack or organisation named in a purpose
  echo "changed-listing|3.232.0|yes|an app-only pull request skips the kit's own selftests"
}
_cap_ids() { _cap_registry | awk -F'|' '{ print $1 }'; }
_cap_field() {  # <id> <2=since|3=declinable|4=purpose>
  _cap_registry | awk -F'|' -v id="$1" -v n="$2" '$1 == id { print $n }'
}
# _drift_has <id> <file> -> 0 the pipeline HAS the capability · 1 it lacks it · 2 error (unknown id / no file).
# changed-listing: (a) an uncommented line runs conformance/verify.sh with --require AND --changed <arg>;
# (b) if <arg> is a shell variable reference NAME, NAME must be defined somewhere. Defined means ANY of: some
# OTHER uncommented line assigns `NAME=`; the SAME verify line assigns it before `--changed`
# (`L=$(mktemp); sh conformance/verify.sh --require --changed "$L"`); a YAML mapping key `NAME:` (a GitHub
# `env:` / GitLab `variables:` entry); or <arg> starts with a runner-provided variable used as a PATH PREFIX —
# exactly `$X/…` or `${X}/…` (optionally quoted) with X one of RUNNER_TEMP, GITHUB_WORKSPACE, CI_PROJECT_DIR,
# CI_BUILDS_DIR (the runner defines them; a bare `$RUNNER_TEMP` is a directory, not a listing, and `$HOME` is not
# on the list). The widening is deliberate: silence is the safe direction (the cost of a false silence is the slow
# path). Line-based: a wrapper script or a `\`-continued invocation still reads as lacking (a false notice); a
# variable defined but never to a real listing reads as having. Design §2 D3.
_drift_has() {
  case "$1" in changed-listing) ;; *) return 2 ;; esac
  [ -f "$2" ] || return 2
  awk '
    /^[[:space:]]*#/ { next }
    {
      s = $0; sub(/[[:space:]]#.*/, "", s)
      if (s ~ /conformance\/verify\.sh/ && s ~ /--require/ && s ~ /--changed/) {
        nv++; a = s; sub(/.*--changed[ =]*/, "", a); sub(/[[:space:]].*/, "", a)
        vname[nv] = ""; vsafe[nv] = 0; vpre[nv] = substr(s, 1, index(s, "--changed") - 1)
        if (match(a, /\$\{?[A-Za-z_][A-Za-z0-9_]*/)) { n = substr(a, RSTART + 1, RLENGTH - 1); sub(/^\{/, "", n); vname[nv] = n }
        if (a ~ /^"?\$\{?(RUNNER_TEMP|GITHUB_WORKSPACE|CI_PROJECT_DIR|CI_BUILDS_DIR)\}?\//) vsafe[nv] = 1
        next
      }
      other[++no] = s
    }
    END {
      for (i = 1; i <= nv; i++) {
        if (vname[i] == "" || vsafe[i]) exit 0
        pat = "(^|[^A-Za-z0-9_])" vname[i] "="
        if (vpre[i] ~ pat) exit 0
        key = "^[[:space:]]*" vname[i] ":[[:space:]]"
        for (j = 1; j <= no; j++) if (other[j] ~ pat || other[j] ~ key) exit 0
      }
      exit 1
    }' "$2"
}
# _cap_id_ok <id> -> 0 iff the id is ^[a-z0-9-]+$ (it is used inside an ERE by _drift_declined and in awk -v).
_cap_id_ok() { printf '%s\n' "$1" | grep -Eq '^[a-z0-9-]+$'; }
# _drift_declined <id> <file> -> 0 iff the id is declinable AND the file carries `# kit-ci-decline: <id>`.
# The decline silences ONLY the drift leg (never _judge, never the aggregate leg).
_drift_declined() {
  [ "$(_cap_field "$1" 3)" = yes ] || return 1
  grep -Eq "^[[:space:]]*#[[:space:]]*kit-ci-decline:[[:space:]]*$1([[:space:]]|\$)" "$2"
}
# _drift_block <id> <file> -> the marked block verbatim (markers excluded); rc 1 unless EXACTLY one balanced pair.
_drift_block() {
  awk -v id="$1" '
    $0 ~ "^[[:space:]]*# >>> kit:owned " id "[[:space:]]*$" { if (state != 0) bad = 1; state = 1; no++; next }
    $0 ~ "^[[:space:]]*# <<< kit:owned " id "[[:space:]]*$" { if (state != 1) bad = 1; state = 2; nc++; next }
    state == 1 { buf[++n] = $0 }
    END { if (bad || no != 1 || nc != 1 || state != 2) exit 1; for (i = 1; i <= n; i++) print buf[i] }
  ' "$2"
}
# _drift_notice <wf> <platform> <profile> <id>... — the ONE notice text (CI and kit-update print the same).
_drift_notice() {
  _dn_wf=$1; _dn_pl=$2; _dn_pr=$3; shift 3
  echo "CI-DRIFT: $_dn_wf ($_dn_pl) lacks a kit-owned CI capability its stack profile carries:"
  for _dn_id in "$@"; do
    echo "  $_dn_id (since kit v$(_cap_field "$_dn_id" 2)): $(_cap_field "$_dn_id" 4)."
    if _dn_blk=$(_drift_block "$_dn_id" "$_dn_pr"); then
      echo "  Adopt these lines from $_dn_pr (between '# >>> kit:owned $_dn_id' and '# <<< kit:owned $_dn_id'):"
      # the block is profile text (from a --from release in kit-update): strip control bytes, keep tab/newline
      printf '%s\n' "$_dn_blk" | tr -d '\000-\010\013-\037\177' | sed 's/^/    /'
    else
      echo "  Adopt the lines the profile carries for it: see $_dn_pr."
    fi
    if [ "$(_cap_field "$_dn_id" 3)" = yes ]; then
      echo "  Or decline it: add the line '# kit-ci-decline: $_dn_id' to $_dn_wf (the full battery then runs on every PR)."
    fi
  done
}
# _drift_profiles <github|gitlab> -> the in-tree profile pipelines of that platform (cwd-relative), one per line.
_drift_profiles() {
  if [ "$1" = gitlab ]; then _dp_g='profiles/*/ci.gitlab-ci.yml'; else _dp_g='profiles/*/ci.yml'; fi
  for _dp_f in $_dp_g; do [ -f "$_dp_f" ] && echo "$_dp_f"; done
  return 0
}
# _drift_leg <wf> <platform> <origin> -> 0 · 1 (FAIL). Runs AFTER a PASS verdict from _judge only; fail-closed
# on a predicate error. Dispositions: design §2 D4.
_drift_leg() {
  [ "$_VEW_DRIFT" = on ] || return 0
  _dl_wf=$1; _dl_pl=$2; _dl_origin=$3
  if [ "$(_kit_source)" = 1 ]; then
    echo "N/A: CI drift — $_dl_wf is the kit's own source pipeline; its profiles are locked by --fleet"; return 0
  fi
  _dl_profs=$(_drift_profiles "$_dl_pl")
  if [ -z "$_dl_profs" ]; then
    echo "N/A: CI drift — no profile pipeline ($_dl_pl) in this tree to compare $_dl_wf against"; return 0
  fi
  _dl_first=$(printf '%s\n' "$_dl_profs" | sed -n 1p)
  _dl_stale=""; _dl_cur=""
  for _dl_id in $(_cap_ids); do
    _dl_all=1
    # line by line (a profile path may hold a space); a here-doc, not a pipe, so _dl_all survives the loop
    while IFS= read -r _dl_p; do
      [ -n "$_dl_p" ] || continue
      _dl_r=0; _drift_has "$_dl_id" "$_dl_p" || _dl_r=$?
      case "$_dl_r" in 0) ;; 1) _dl_all=0 ;; *) echo "FAIL: CI drift — cannot evaluate capability '$_dl_id' on $_dl_p"; return 1 ;; esac
    done <<EOF
$_dl_profs
EOF
    [ "$_dl_all" = 1 ] || continue   # the in-tree profiles predate it: the adopter is current against what they took
    _dl_r=0; _drift_has "$_dl_id" "$_dl_wf" || _dl_r=$?
    case "$_dl_r" in
      0) _dl_cur="$_dl_cur $_dl_id" ;;
      1) if _drift_declined "$_dl_id" "$_dl_wf"; then
           echo "N/A: CI drift — declined: $_dl_id; the full battery runs on every PR"
         else _dl_stale="$_dl_stale $_dl_id"; fi ;;
      *) echo "FAIL: CI drift — cannot evaluate capability '$_dl_id' on $_dl_wf"; return 1 ;;
    esac
  done
  [ -z "$_dl_cur" ] || echo "OK: CI capabilities current:$_dl_cur"
  [ -n "$_dl_stale" ] || return 0
  # shellcheck disable=SC2086
  _drift_notice "$_dl_wf" "$_dl_pl" "$_dl_first" $_dl_stale
  case "$_dl_origin" in
    emitted) return 1 ;;   # the kit installed it: a stale pipeline is drift
    adopter) return 0 ;;   # adopter-owned (brownfield): a disclosed obligation, never a red
    *)       return 1 ;;   # unenumerated provenance fails closed
  esac
}
# _drift_cli <wf> <profile> -> the `--drift` form kit-update runs: 0 nothing stale · 1 stale (notice printed) · 2 error.
_drift_cli() {
  [ -f "$1" ] || { echo "FAIL: --wf='$1' names no file (fail-closed)"; return 2; }
  [ -f "$2" ] || { echo "FAIL: --profile='$2' names no file (fail-closed)"; return 2; }
  case "$1" in *gitlab*) _dc_pl=gitlab ;; *) _dc_pl=github ;; esac
  _dc_stale=""
  for _dc_id in $(_cap_ids); do
    _dc_r=0; _drift_has "$_dc_id" "$2" || _dc_r=$?
    case "$_dc_r" in 0) ;; 1) continue ;; *) echo "FAIL: cannot evaluate capability '$_dc_id' on $2"; return 2 ;; esac
    _dc_r=0; _drift_has "$_dc_id" "$1" || _dc_r=$?
    case "$_dc_r" in
      0) ;;
      1) _drift_declined "$_dc_id" "$1" || _dc_stale="$_dc_stale $_dc_id" ;;
      *) echo "FAIL: cannot evaluate capability '$_dc_id' on $1"; return 2 ;;
    esac
  done
  [ -n "$_dc_stale" ] || return 0
  # shellcheck disable=SC2086
  _drift_notice "$1" "$_dc_pl" "$2" $_dc_stale
  return 1
}
# _since_ok <since> <root> -> 0 iff <since> is above <root>/VERSION (a pending release) or <root>/CHANGELOG.md
# has a `## [<since>]` heading. A mis-guessed version reds as soon as the release ships without it.
_since_ok() {
  printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || return 1
  _so_v=$(tr -d ' \t\r\n' < "$2/VERSION" 2>/dev/null) || _so_v=""
  [ -n "$_so_v" ] || return 1
  if awk -v a="$1" -v b="$_so_v" 'BEGIN { split(a, x, "."); split(b, y, "."); for (i = 1; i <= 3; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 } exit 1 }'; then return 0; fi
  _so_re=$(printf '%s' "$1" | sed 's/\./\\./g')   # the value is [0-9.]+ (checked above): only the dots need escaping
  grep -Eq "^## \\[$_so_re\\]" "$2/CHANGELOG.md" 2>/dev/null
}
# _fleet_caps <profile> -> 0 · 1 with FAIL lines. Locks 1 and 2 (design D6): balanced markers for every
# registry id, no marker id outside the registry, and the profile satisfies its OWN predicate.
_fleet_caps() {
  _fc_rc=0
  for _fc_id in $(_cap_ids); do
    _drift_block "$_fc_id" "$1" >/dev/null || { echo "FAIL: $1 lacks exactly one balanced '# >>> kit:owned $_fc_id' / '# <<< kit:owned $_fc_id' marker pair (open before close)"; _fc_rc=1; }
    _fc_r=0; _drift_has "$_fc_id" "$1" || _fc_r=$?
    [ "$_fc_r" = 0 ] || { echo "FAIL: $1 lacks capability '$_fc_id' by the drift key (a profile must satisfy its own predicate)"; _fc_rc=1; }
  done
  _fc_all=$(grep -E '^[[:space:]]*# (>>>|<<<) kit:owned ' "$1" | sed 's/.*kit:owned //; s/[[:space:]]*$//' | sort -u) || _fc_all=""
  for _fc_m in $_fc_all; do
    _cap_ids | grep -qxF "$_fc_m" || { echo "FAIL: $1 marks kit:owned id '$_fc_m', which is not in the capability registry (a block with no row is invisible to the drift leg)"; _fc_rc=1; }
  done
  return "$_fc_rc"
}

# _fleet_run <root> <expect_github> <expect_gitlab> -> 0 all pipelines enforce & counts match, else 1
# WHY COUNTS ARE STATED, NOT DERIVED: deriving the expected count from the very glob being checked
# makes the assertion circular — a glob that silently matched nothing would then "pass". WHY
# PER-PLATFORM rather than one total: a single total lets a missing GitLab pipeline hide behind the
# ten GitHub ones, which is the aggregation blindness this whole slice exists to correct one level up.
# Exact equality both ways — an UNDER-count catches a pipeline that lost the step, an OVER-count
# forces a deliberate update when a new pipeline appears instead of absorbing it silently.
_fleet_run() {
  _fr_root=$1; _fr_exp_gh=$2; _fr_exp_gl=$3
  _fr_rc=0; _fr_n_gh=0; _fr_n_gl=0
  for _fr_f in "$_fr_root"/profiles/*/ci.yml; do
    [ -f "$_fr_f" ] || continue
    _fr_n_gh=$((_fr_n_gh + 1))
    enforcing_present "$_fr_f" github || { echo "FAIL: $_fr_f does not run a real 'verify.sh --require'"; _fr_rc=1; }
    _fr_k5=$(_kst_wiring_github "$_fr_f") || { echo "FAIL: $_fr_k5"; _fr_rc=1; }
    _fr_dc=$(_fleet_caps "$_fr_f") || { printf '%s\n' "$_fr_dc"; _fr_rc=1; }
  done
  for _fr_f in "$_fr_root"/profiles/*/ci.gitlab-ci.yml; do
    [ -f "$_fr_f" ] || continue
    _fr_n_gl=$((_fr_n_gl + 1))
    enforcing_present "$_fr_f" gitlab || { echo "FAIL: $_fr_f does not run a real 'verify.sh --require'"; _fr_rc=1; }
    _fr_k5=$(_kst_wiring_gitlab "$_fr_f") || { echo "FAIL: $_fr_k5"; _fr_rc=1; }
    _fr_dc=$(_fleet_caps "$_fr_f") || { printf '%s\n' "$_fr_dc"; _fr_rc=1; }
  done
  for _fr_id in $(_cap_ids); do
    _since_ok "$(_cap_field "$_fr_id" 2)" "$_fr_root" || { echo "FAIL: capability '$_fr_id' since $(_cap_field "$_fr_id" 2): that version is neither above $_fr_root/VERSION (pending) nor a '## [<since>]' heading in $_fr_root/CHANGELOG.md — a mis-guessed since"; _fr_rc=1; }
    _cap_id_ok "$_fr_id" || { echo "FAIL: registry id '$_fr_id' is not ^[a-z0-9-]+\$ (ids are matched inside an ERE)"; _fr_rc=1; }
    _fr_ref=''; _fr_refn=''   # the marked block must be byte-identical across every GitHub profile (one notice)
    for _fr_f in "$_fr_root"/profiles/*/ci.yml; do
      [ -f "$_fr_f" ] || continue
      _fr_b=$(_drift_block "$_fr_id" "$_fr_f" 2>/dev/null) || continue   # missing markers are lock 1's finding
      if [ -z "$_fr_refn" ]; then _fr_ref=$_fr_b; _fr_refn=$_fr_f
      elif [ "$_fr_b" != "$_fr_ref" ]; then echo "FAIL: the kit:owned '$_fr_id' block in $_fr_f is not byte-identical to the one in $_fr_refn (the notice must read the same whichever profile is shown)"; _fr_rc=1; fi
    done
  done
  # A zero enumeration is ALWAYS a failure, never a silent pass: a check that cannot find its
  # subjects must not report success (the presence-check-cannot-see-substitution class).
  [ "$_fr_n_gh" != 0 ] || { echo "FAIL: enumerated ZERO github pipelines under '$_fr_root/profiles/*/ci.yml' — refusing to pass vacuously"; _fr_rc=1; }
  [ "$_fr_n_gl" != 0 ] || { echo "FAIL: enumerated ZERO gitlab pipelines under '$_fr_root/profiles/*/ci.gitlab-ci.yml' — refusing to pass vacuously"; _fr_rc=1; }
  [ "$_fr_n_gh" = "$_fr_exp_gh" ] || { echo "FAIL: github pipelines: found $_fr_n_gh, expected $_fr_exp_gh (update --expect-github deliberately)"; _fr_rc=1; }
  [ "$_fr_n_gl" = "$_fr_exp_gl" ] || { echo "FAIL: gitlab pipelines: found $_fr_n_gl, expected $_fr_exp_gl (update --expect-gitlab deliberately)"; _fr_rc=1; }
  [ "$_fr_rc" = 0 ] && echo "OK: all $_fr_n_gh github + $_fr_n_gl gitlab emitted pipelines run 'verify.sh --require'"
  return "$_fr_rc"
}

if [ "${1:-}" = "--fleet" ]; then
  shift
  _root="."; _exp_gh=""; _exp_gl=""
  for _a in "$@"; do
    case "$_a" in
      --root=*)          _root=${_a#--root=} ;;
      --expect-github=*) _exp_gh=${_a#--expect-github=} ;;
      --expect-gitlab=*) _exp_gl=${_a#--expect-gitlab=} ;;
      *) echo "FAIL: --fleet: unknown argument '$_a'"; exit 1 ;;
    esac
  done
  if [ -z "$_exp_gh" ] || [ -z "$_exp_gl" ]; then
    echo "FAIL: --fleet requires --expect-github=<n> AND --expect-gitlab=<m>."
    echo "  Both are STATED, never derived from the glob being checked — a derived count is circular,"
    echo "  and a glob matching nothing would then pass."
    exit 1
  fi
  _fleet_run "$_root" "$_exp_gh" "$_exp_gl"
  exit $?
fi

if [ "${1:-}" = "--selftest" ]; then
  d=$(mktemp -d) || { echo "verify-enforced-wired --selftest: FAIL (no tmpdir)"; exit 1; }; st=0
  # ── §3 disposition matrix, as a PURE FUNCTION over arguments ────────────────────────────────────
  # Every row of the spec's table, both provenance values. POSITIVE (PASS) rows first, deliberately:
  # a function broken SHUT — one that answers FAIL to everything — satisfies every negative row here
  # perfectly, and only a positive row can catch it.
  [ "$(_wf_disposition 1 1 emitted 1)" = PASS ] || { echo "FAIL: disposition — kit-installed + step must PASS"; st=1; }
  [ "$(_wf_disposition 1 0 emitted 1)" = PASS ] || { echo "FAIL: disposition — kit-installed + step must PASS (non-must-have tree)"; st=1; }
  [ "$(_wf_disposition 1 1 adopter 1)" = PASS ] || { echo "FAIL: disposition — adopter-owned + step must PASS (they merged it)"; st=1; }
  [ "$(_wf_disposition 1 1 kitsource 1)" = PASS ] || { echo "FAIL: disposition — kit-source repo + step must still PASS (kit-source is a FAIL-adder only)"; st=1; }
  [ "$(_wf_disposition 0 0 none 0)"    = NA ]   || { echo "FAIL: disposition — raw pre-incept export must be N/A"; st=1; }
  [ "$(_wf_disposition 1 1 adopter 0)" = NA-REMEDY ] || { echo "FAIL: disposition — adopter-owned + NO step is an unmet DOCUMENTED merge obligation (N/A-with-remedy), not a failure"; st=1; }
  [ "$(_wf_disposition 1 1 emitted 0)" = FAIL ] || { echo "FAIL: disposition — kit-installed + step REMOVED is real drift and must FAIL"; st=1; }
  [ "$(_wf_disposition 1 1 kitsource 0)" = FAIL ] || { echo "FAIL: disposition — kit-source repo + NO step is the kit failing to self-enforce its own battery and must FAIL (drift)"; st=1; }
  [ "$(_wf_disposition 0 1 none 0)"    = FAIL ] || { echo "FAIL: disposition — kit/incepted tree missing every pipeline must FAIL (fail-closed)"; st=1; }
  # FAIL-CLOSED on anything the matrix does not enumerate. The whole point of this design is that the
  # input space is NOT proven exhausted (see the ceiling in the header); an unenumerated combination
  # must land on the safe side rather than fall through to a silent pass.
  [ "$(_wf_disposition 1 1 bogus 0)" = FAIL ]   || { echo "FAIL: disposition — an UNENUMERATED provenance must fail-closed"; st=1; }
  [ "$(_wf_disposition 9 0 emitted 1)" = FAIL ] || { echo "FAIL: disposition — an UNENUMERATED wf_exists value must fail-closed"; st=1; }
  # 'adopter 9', NOT 'emitted 9', is the load-bearing probe for the step-domain guard: without the guard
  # an invalid step falls through to the case on provenance, where 'emitted' still yields FAIL (an
  # equivalent mutant) but 'adopter' would yield NA-REMEDY — so only 'adopter <invalid>' proves the guard.
  [ "$(_wf_disposition 1 1 adopter 9)" = FAIL ] || { echo "FAIL: disposition — an UNENUMERATED step value must fail-closed"; st=1; }
  # Lock the marker-detection half too (a rename returning 0 on an incepted tree would fail-OPEN to NA):
  _mh=$(mktemp -d) || { echo "verify-enforced-wired --selftest: FAIL (no tmpdir for the marker legs)"; exit 1; }
  [ "$(_must_have_workflow "$_mh")" = 0 ] || { echo "FAIL: _must_have_workflow — markerless tree (raw export) must be 0"; st=1; }
  for _mk in ENGINEERING-PRINCIPLES.md docs/ROADMAP-KIT.md .github/workflows/golden-path.yml; do
    mkdir -p "$_mh/$(dirname "$_mk")"; : > "$_mh/$_mk"
    [ "$(_must_have_workflow "$_mh")" = 1 ] || { echo "FAIL: _must_have_workflow — marker '$_mk' present must be 1 (fail-closed)"; st=1; }
    rm -f "$_mh/$_mk"
  done
  rm -rf "$_mh" 2>/dev/null || true
  # Lock the KIT-SOURCE predicate directly (design §3, review F1): golden-path.yml OR docs/ROADMAP-KIT.md
  # => 1 (the kit's own repo); a raw tree => 0. CRUCIALLY, ENGINEERING-PRINCIPLES.md alone must stay 0:
  # an incepted brownfield adopter carries it (incept renames CLAUDE.md) but carries NEITHER kit marker,
  # so folding it into this predicate would misclassify that adopter as kit-source and wrongly FAIL them —
  # the exact trap §3 exists to avoid. This leg goes RED if the predicate is widened to include it.
  _ks=$(mktemp -d) || { echo "verify-enforced-wired --selftest: FAIL (no tmpdir for the kit-source legs)"; exit 1; }
  [ "$(_kit_source "$_ks")" = 0 ] || { echo "FAIL: _kit_source — markerless tree (raw export/adopter) must be 0"; st=1; }
  : > "$_ks/ENGINEERING-PRINCIPLES.md"
  [ "$(_kit_source "$_ks")" = 0 ] || { echo "FAIL: _kit_source — ENGINEERING-PRINCIPLES.md is an INCEPTED-ADOPTER marker, NOT kit-source; must stay 0 (disjointness)"; st=1; }
  rm -f "$_ks/ENGINEERING-PRINCIPLES.md"
  for _km in .github/workflows/golden-path.yml docs/ROADMAP-KIT.md; do
    mkdir -p "$_ks/$(dirname "$_km")"; : > "$_ks/$_km"
    [ "$(_kit_source "$_ks")" = 1 ] || { echo "FAIL: _kit_source — kit marker '$_km' present must be 1"; st=1; }
    rm -f "$_ks/$_km"
  done
  rm -rf "$_ks" 2>/dev/null || true
  printf '      - name: enforce\n        run: sh conformance/verify.sh --require\n      - name: render\n        run: sh conformance/verify.sh --selftest\n' > "$d/ok.yml"
  printf '      - name: render only\n        run: sh conformance/verify.sh --selftest\n' > "$d/bad.yml"
  printf '# historical: we used to run sh conformance/verify.sh --require here\n        run: sh conformance/verify.sh --selftest\n' > "$d/comment.yml"
  printf '      - name: suppressed\n        run: sh conformance/verify.sh --require || true\n' > "$d/suppressed.yml"
  printf '      - name: trailing\n        run: sh conformance/verify.sh --selftest  # not --require\n' > "$d/trailing.yml"
  enforcing_present "$d/ok.yml"         || { echo "FAIL: selftest — real enforcing step missed"; st=1; }
  enforcing_present "$d/bad.yml"        && { echo "FAIL: selftest — selftest-only wrongly passed"; st=1; }
  enforcing_present "$d/comment.yml"    && { echo "FAIL: selftest — commented --require wrongly passed"; st=1; }
  enforcing_present "$d/suppressed.yml" && { echo "FAIL: selftest — '|| true'-suppressed --require wrongly passed"; st=1; }
  enforcing_present "$d/trailing.yml"   && { echo "FAIL: selftest — trailing-comment --require wrongly passed"; st=1; }

  # ── GitLab arm (CP7R5-GATE-AUTHORITY) ───────────────────────────────────────────────────────────
  # Both shapes found in the SHIPPED profiles/typescript-node/ci.gitlab-ci.yml are covered: the
  # block-list form (:47) and the flow-list form (:58). Every bypass the GitHub arm rejects must be
  # rejected here too — otherwise the second platform ships with a weaker contract than the first.
  printf 'gate-x:\n  script:\n    - sh conformance/verify.sh --require\n'          > "$d/gl-block-ok.yml"
  printf 'gate-x:\n  script: [sh conformance/verify.sh --require]\n'               > "$d/gl-flow-ok.yml"
  printf 'gate-x:\n  script: [sh conformance/verify.sh --selftest]\n'              > "$d/gl-flow-bad.yml"
  printf 'gate-x:\n  script:\n    - sh conformance/verify.sh --require || true\n'  > "$d/gl-suppressed.yml"
  printf '# - sh conformance/verify.sh --require\ngate-x:\n  script: [true]\n'     > "$d/gl-comment.yml"
  printf 'gate-x:\n  script:\n    - sh conformance/verify.sh --selftest  # not --require\n' > "$d/gl-trailing.yml"
  enforcing_present "$d/gl-block-ok.yml"   gitlab || { echo "FAIL: selftest — GitLab block-list enforcing step missed"; st=1; }
  enforcing_present "$d/gl-flow-ok.yml"    gitlab || { echo "FAIL: selftest — GitLab flow-list enforcing step missed"; st=1; }
  enforcing_present "$d/gl-flow-bad.yml"   gitlab && { echo "FAIL: selftest — GitLab renderer-only wrongly passed"; st=1; }
  enforcing_present "$d/gl-suppressed.yml" gitlab && { echo "FAIL: selftest — GitLab '|| true'-suppressed wrongly passed"; st=1; }
  enforcing_present "$d/gl-comment.yml"    gitlab && { echo "FAIL: selftest — GitLab commented --require wrongly passed"; st=1; }
  enforcing_present "$d/gl-trailing.yml"   gitlab && { echo "FAIL: selftest — GitLab trailing-comment --require wrongly passed"; st=1; }
  # Cross-platform isolation, load-bearing BOTH ways: a GitHub file judged as GitLab (and vice versa)
  # must NOT pass. Without this, a single over-broad matcher could green a pipeline whose syntax its
  # platform would never execute.
  enforcing_present "$d/ok.yml"            gitlab && { echo "FAIL: selftest — GitHub 'run:' wrongly satisfied the GitLab matcher"; st=1; }
  enforcing_present "$d/gl-block-ok.yml"   github && { echo "FAIL: selftest — GitLab 'script:' wrongly satisfied the GitHub matcher"; st=1; }
  # Unrecognised platform must FAIL (fail-safe), never fall through to a default that passes.
  enforcing_present "$d/ok.yml"            bitbucket && { echo "FAIL: selftest — unknown platform wrongly passed (must fail-safe)"; st=1; }
  # ── --fleet legs (CP7R5-GATE-AUTHORITY) ─────────────────────────────────────────────────────────
  # These drive the REAL _fleet_run, not a replica — testing a copy of the logic is the classic way a
  # green proves nothing about the shipped path (the K3 lesson).
  # K5 conforming fixtures (the shape the shipped profiles carry) — every fleet fixture that must PASS uses these.
  _kst_fx_gh() {  # <file>
    { printf 'on:\n  pull_request:\n  push:\n    branches: [main]\n  schedule:\n    - cron: %s\n' "'23 5 * * 1'"
      printf 'jobs:\n  ci:\n    steps:\n      # >>> kit:owned changed-listing\n      - name: Changed-path listing\n        if: github.event_name == %s && github.base_ref == github.event.repository.default_branch\n' "'pull_request'"
      printf '        env:\n          BASE_SHA: ${{ github.event.pull_request.base.sha }}\n        run: |\n'
      printf '          git diff -z --name-only --no-renames "$BASE_SHA...HEAD" > "$RUNNER_TEMP/z"\n'
      printf '          [ "$(%s < "$RUNNER_TEMP/z" | wc -c)" -eq 0 ]\n' "tr -cd '\\n'"
      printf '          echo "KIT_CHANGED=$RUNNER_TEMP/list" >> "$GITHUB_ENV"\n      - name: Conformance aggregate\n        %s\n      # <<< kit:owned changed-listing\n' "$_KST_GH_LINE"
    } > "$1"
  }
  _kst_fx_gl() {  # <file>
    { printf '# >>> kit:owned changed-listing\nconformance-aggregate:\n  stage: verify\n  before_script:\n    - |\n'
      printf '      if [ "$CI_PIPELINE_SOURCE" = "merge_request_event" ] && [ "$CI_MERGE_REQUEST_TARGET_BRANCH_NAME" = "$CI_DEFAULT_BRANCH" ] && kz=$(mktemp) && kl=$(mktemp) && git diff -z --name-only --no-renames "$CI_MERGE_REQUEST_DIFF_BASE_SHA...HEAD" > "$kz" && [ "$(%s < "$kz" | wc -c)" -eq 0 ]; then export KIT_CHANGED="$kl"; fi\n' "tr -cd '\\n'"
      printf '  script:\n    %s\n# <<< kit:owned changed-listing\n' "$_KST_GL_LINE"
    } > "$1"
  }
  _fx_meta() {  # <root> — the VERSION + CHANGELOG heading the fleet's since-lock reads
    printf '3.232.0\n' > "$1/VERSION"; printf '## [3.232.0] - fixture\n' > "$1/CHANGELOG.md"
  }
  _fd=$(mktemp -d) || { echo "verify-enforced-wired --selftest: FAIL (no tmpdir for the fleet legs)"; exit 1; }
  mkdir -p "$_fd/good/profiles/a" "$_fd/good/profiles/b"; _fx_meta "$_fd/good"
  _kst_fx_gh "$_fd/good/profiles/a/ci.yml"
  _kst_fx_gl "$_fd/good/profiles/b/ci.gitlab-ci.yml"
  # ── K5 legs: the conforming fixtures PASS first (a check broken shut satisfies every mutant), then one mutant
  # per property must FAIL, each against the SAME base fixture so a green mutant means that property is unchecked.
  _kst_wiring_github "$_fd/good/profiles/a/ci.yml" >/dev/null || { echo "FAIL: K5 — the conforming GitHub fixture was REJECTED (checker broken shut)"; st=1; }
  _kst_wiring_gitlab "$_fd/good/profiles/b/ci.gitlab-ci.yml" >/dev/null || { echo "FAIL: K5 — the conforming GitLab fixture was REJECTED (checker broken shut)"; st=1; }
  _kst_mut() {  # <label> <sed-script> — mutate the GitHub fixture; the checker must now FAIL
    sed "$2" "$_fd/good/profiles/a/ci.yml" > "$_fd/mut.yml"
    if cmp -s "$_fd/mut.yml" "$_fd/good/profiles/a/ci.yml"; then echo "FAIL: K5 mutant '$1' changed nothing (vacuous)"; st=1; return 0; fi
    ! _kst_wiring_github "$_fd/mut.yml" >/dev/null || { echo "FAIL: K5 — mutant '$1' was ACCEPTED (that property is not checked)"; st=1; }
  }
  _kst_mut no-schedule      '/^  schedule:/d;/cron:/d'
  _kst_mut daily-cron       's/\* \* 1/* * */'
  _kst_mut no-pr-gate       '/if: github.event_name/d'
  _kst_mut base-sha-in-run  's/"\$BASE_SHA\.\.\.HEAD"/"${{ github.event.pull_request.base.sha }}...HEAD"/'
  _kst_mut renames-on       's/ --no-renames//'
  _kst_mut no-nul-list      's/git diff -z/git diff/'
  _kst_mut no-summary-file  's/ --summary-file "\$GITHUB_STEP_SUMMARY"//'
  _kst_mut unconditional    's/\${KIT_CHANGED:+--changed "\$KIT_CHANGED" --summary-file "\$GITHUB_STEP_SUMMARY"}/--changed list.txt/'
  _kst_mut no-default-branch 's/ && github.base_ref == github.event.repository.default_branch//'
  _kst_mut no-newline-refusal '/tr -cd/d'
  _kst_mutgl() {
    sed "$2" "$_fd/good/profiles/b/ci.gitlab-ci.yml" > "$_fd/mutgl.yml"
    if cmp -s "$_fd/mutgl.yml" "$_fd/good/profiles/b/ci.gitlab-ci.yml"; then echo "FAIL: K5 GitLab mutant '$1' changed nothing (vacuous)"; st=1; return 0; fi
    ! _kst_wiring_gitlab "$_fd/mutgl.yml" >/dev/null || { echo "FAIL: K5 — GitLab mutant '$1' was ACCEPTED"; st=1; }
  }
  _kst_mutgl no-mr-gate   's/merge_request_event/push/'
  _kst_mutgl no-target-branch-gate 's/CI_MERGE_REQUEST_TARGET_BRANCH_NAME/CI_X/'
  _kst_mutgl fixed-tmp    's/\$(mktemp)/\/tmp\/kit-changed.z/g'
  _kst_mutgl no-newline-refusal 's/ && \[ "\$(tr -cd [^|]*| wc -c)" -eq 0 \]//'
  _kst_mutgl unconditional 's/\${KIT_CHANGED:+--changed "\$KIT_CHANGED"}/--changed list.txt/'
  rm -f "$_fd/mut.yml" "$_fd/mutgl.yml"
  _fleet_run "$_fd/good" 1 1 >/dev/null || { echo "FAIL: fleet — a fully-enforcing fixture must PASS"; st=1; }

  mkdir -p "$_fd/bad/profiles/a" "$_fd/bad/profiles/b"; _fx_meta "$_fd/bad"
  printf '      - name: x\n        run: sh conformance/verify.sh --selftest\n' > "$_fd/bad/profiles/a/ci.yml"
  printf 'gate-x:\n  script: [sh conformance/verify.sh --require]\n'           > "$_fd/bad/profiles/b/ci.gitlab-ci.yml"
  _fleet_run "$_fd/bad" 1 1 >/dev/null && { echo "FAIL: fleet — ONE pipeline missing the step must FAIL the fleet"; st=1; }

  # THE VACUITY LEG, and the reason the zero-guard is not redundant with the equality check: here
  # found==expected==0, so equality alone would report success over an empty tree. Only the explicit
  # zero-guard turns that into a failure.
  mkdir -p "$_fd/empty/profiles"; _fx_meta "$_fd/empty"
  _fleet_run "$_fd/empty" 0 0 >/dev/null && { echo "FAIL: fleet — ZERO enumerated pipelines must FAIL, never pass vacuously"; st=1; }

  _fleet_run "$_fd/good" 2 1 >/dev/null && { echo "FAIL: fleet — found FEWER than asserted must FAIL"; st=1; }
  _fleet_run "$_fd/good" 1 0 >/dev/null && { echo "FAIL: fleet — found MORE than asserted must FAIL (a new pipeline must force a deliberate update)"; st=1; }

  # ── THE PER-PLATFORM ZERO GUARDS, ONE AT A TIME (review M2) ─────────────────────────────────────
  # The empty-tree leg above has BOTH counts at 0, so it is killed by EITHER guard: removing one alone
  # SURVIVES it. The previous round proved the PAIR load-bearing and claimed the INDIVIDUALS were —
  # which is precisely the vacuous-proof shape this slice keeps reproducing. A SINGLE-PLATFORM tree
  # separates them: here the counts MATCH what is asserted, so the equality checks are satisfied and
  # only the OTHER platform's zero guard can register the failure.
  mkdir -p "$_fd/gh-only/profiles/a"; _fx_meta "$_fd/gh-only"
  _kst_fx_gh "$_fd/gh-only/profiles/a/ci.yml"
  _fleet_run "$_fd/gh-only" 1 0 >/dev/null && { echo "FAIL: fleet — a tree with ZERO gitlab pipelines must FAIL on the GITLAB zero guard alone"; st=1; }
  mkdir -p "$_fd/gl-only/profiles/a"; _fx_meta "$_fd/gl-only"
  _kst_fx_gl "$_fd/gl-only/profiles/a/ci.gitlab-ci.yml"
  _fleet_run "$_fd/gl-only" 0 1 >/dev/null && { echo "FAIL: fleet — a tree with ZERO github pipelines must FAIL on the GITHUB zero guard alone"; st=1; }

  # ── KIT-UPDATE-PROFILE-CI-DRIFT fleet locks (design D6), each killed by ITS property alone ──────────
  # The shipped fixture tree must PASS first (a lock broken shut satisfies every negative below).
  _fleet_run "$_fd/good" 1 1 >/dev/null || { echo "FAIL: drift fleet — the marker-carrying fixture tree must PASS the locks (positive first)"; st=1; }
  for _fl in nomarker-close nomarker-open unknown-id no-capability no-changelog; do
    mkdir -p "$_fd/$_fl/profiles/a" "$_fd/$_fl/profiles/b"; _fx_meta "$_fd/$_fl"
    _kst_fx_gh "$_fd/$_fl/profiles/a/ci.yml"; _kst_fx_gl "$_fd/$_fl/profiles/b/ci.gitlab-ci.yml"
  done
  sed '/<<< kit:owned/d' "$_fd/good/profiles/a/ci.yml" > "$_fd/nomarker-close/profiles/a/ci.yml"
  _fleet_run "$_fd/nomarker-close" 1 1 >/dev/null && { echo "FAIL: drift fleet — a profile with its '<<<' marker deleted must FAIL (lock 1, close)"; st=1; }
  sed '/>>> kit:owned/d' "$_fd/good/profiles/b/ci.gitlab-ci.yml" > "$_fd/nomarker-open/profiles/b/ci.gitlab-ci.yml"
  _fleet_run "$_fd/nomarker-open" 1 1 >/dev/null && { echo "FAIL: drift fleet — a profile with its '>>>' marker deleted must FAIL (lock 1, open)"; st=1; }
  { cat "$_fd/good/profiles/a/ci.yml"; printf '# >>> kit:owned zzz-unknown\n# <<< kit:owned zzz-unknown\n'; } > "$_fd/unknown-id/profiles/a/ci.yml"
  _fleet_run "$_fd/unknown-id" 1 1 >/dev/null && { echo "FAIL: drift fleet — a kit:owned id missing from the registry must FAIL (lock 1, enumeration)"; st=1; }
  sed 's/--changed "\$KIT_CHANGED"//' "$_fd/good/profiles/a/ci.yml" > "$_fd/no-capability/profiles/a/ci.yml"
  _fleet_run "$_fd/no-capability" 1 1 2>&1 | grep -qF 'by the drift key' || { echo "FAIL: drift fleet — a profile that lacks the capability by the D3 key must FAIL naming it (lock 2)"; st=1; }
  rm -f "$_fd/no-changelog/CHANGELOG.md"
  _fleet_run "$_fd/no-changelog" 1 1 >/dev/null && { echo "FAIL: drift fleet — a since with no CHANGELOG heading (and not above VERSION) must FAIL (lock 3)"; st=1; }
  _sx=$(mktemp -d) || { echo "verify-enforced-wired --selftest: FAIL (no tmpdir for the since legs)"; exit 1; }
  _fx_meta "$_sx"
  _since_ok 3.232.0 "$_sx" || { echo "FAIL: drift fleet — a since at VERSION with its heading must be accepted"; st=1; }
  _since_ok 3.233.0 "$_sx" || { echo "FAIL: drift fleet — a since above VERSION (pending release) must be accepted"; st=1; }
  _since_ok 3.231.5 "$_sx" && { echo "FAIL: drift fleet — a since of 3.231.5 (<= VERSION, no heading) must FAIL (lock 3)"; st=1; }
  # the heading match is anchored to a line start with the dots literal: a `###` heading, prose that quotes
  # the heading mid-line, and a dot-wildcard near miss must NOT satisfy it
  printf '## [3.232.0] - fixture\n### [3.231.5] - a sub-heading\nsee ## [3.231.5] in the notes\n## [3x231.4] - near miss\n' > "$_sx/CHANGELOG.md"
  _since_ok 3.231.5 "$_sx" && { echo "FAIL: drift fleet — a '###' heading or mid-line prose must not satisfy the since lock (anchor ^## [x.y.z])"; st=1; }
  _since_ok 3.231.4 "$_sx" && { echo "FAIL: drift fleet — '3x231' must not satisfy a since of 3.231.4 (dots are literal)"; st=1; }
  printf '## [3.232.0] - fixture\n## [3.231.5] - real\n' > "$_sx/CHANGELOG.md"
  _since_ok 3.231.5 "$_sx" || { echo "FAIL: drift fleet — a real '## [3.231.5]' heading must satisfy the since lock"; st=1; }
  # registry ids are used inside an ERE (the decline match): only [a-z0-9-]+ is accepted
  _cap_id_ok changed-listing || { echo "FAIL: drift fleet — the shipped id must pass the id-shape lock"; st=1; }
  for _bi in 'a.b' 'A' 'a|b' 'a b' ''; do
    _cap_id_ok "$_bi" && { echo "FAIL: drift fleet — id '$_bi' must fail the id-shape lock (^[a-z0-9-]+\$)"; st=1; }
  done
  # the marked block is byte-identical across every GitHub profile (one notice, whichever profile is shown)
  for _fl in dup-same dup-diff; do
    mkdir -p "$_fd/$_fl/profiles/a" "$_fd/$_fl/profiles/b" "$_fd/$_fl/profiles/c"; _fx_meta "$_fd/$_fl"
    _kst_fx_gh "$_fd/$_fl/profiles/a/ci.yml"; _kst_fx_gh "$_fd/$_fl/profiles/b/ci.yml"; _kst_fx_gl "$_fd/$_fl/profiles/c/ci.gitlab-ci.yml"
  done
  _fleet_run "$_fd/dup-same" 2 1 >/dev/null || { echo "FAIL: drift fleet — two identical marked blocks must PASS (positive first)"; st=1; }
  sed 's#RUNNER_TEMP/list#RUNNER_TEMP/list2#' "$_fd/dup-same/profiles/b/ci.yml" > "$_fd/dup-diff/profiles/b/ci.yml"
  _fleet_run "$_fd/dup-diff" 2 1 2>&1 | grep -qF 'not byte-identical' || { echo "FAIL: drift fleet — a marked block that differs between two GitHub profiles must FAIL (lock: identical blocks)"; st=1; }
  rm -rf "$_sx" 2>/dev/null || true
  rm -rf "$_fd" 2>/dev/null || true

  # ── §5 STEP/JOB-SCOPED SUPPRESSION — FALSE-POSITIVE (PASS) LEGS FIRST (the governing lesson) ───────
  # A check broken SHUT satisfies every negative suppression leg below perfectly; that has already
  # happened in this slice. These POSITIVE legs — an INTACT enforcing step with an UNRELATED suppressor
  # ELSEWHERE in the file — are what catch that, so they are asserted BEFORE the negatives. Each is a
  # real shipped shape plus an injected unrelated suppressed step/job; the old FILE-LEVEL disqualifier
  # hard-FAILed all three (a real adopter false positive), and step/job scoping (§5) makes the unrelated
  # key irrelevant. If any of these REDDENS, the matcher has been broken shut — read it before the negatives.
  printf '      - name: aggregate\n        run: sh conformance/verify.sh --require\n      - name: codecov\n        continue-on-error: true\n        run: echo upload\n' > "$d/gh-fp-unrelated.yml"
  enforcing_present "$d/gh-fp-unrelated.yml" github || { echo "FAIL: selftest — §5 GitHub: an UNRELATED step's continue-on-error must NOT disqualify an intact enforcing step"; st=1; }
  printf 'conformance-aggregate:\n  script: [sh conformance/verify.sh --require]\ndeploy-prod:\n  when: manual\n  script: [echo deploy]\n' > "$d/gl-fp-manual.yml"
  enforcing_present "$d/gl-fp-manual.yml" gitlab || { echo "FAIL: selftest — §5 GitLab: an UNRELATED when:manual deploy job must NOT disqualify the enforcing job"; st=1; }
  printf 'conformance-aggregate:\n  script: [sh conformance/verify.sh --require]\nrelease:\n  rules:\n    - if: "$CI_COMMIT_TAG"\n      when: never\n  script: [echo release]\n' > "$d/gl-fp-rules.yml"
  enforcing_present "$d/gl-fp-rules.yml" gitlab || { echo "FAIL: selftest — §5 GitLab: a legitimate rules/when:never on a DIFFERENT job must NOT disqualify the enforcing job"; st=1; }
  # ── F1 (fix-loop): GitHub JOB-level if:false is scoped to the OWNING job — PASS legs FIRST ─────────
  # The governing lesson: a matcher broken shut satisfies every negative leg, so the legitimate shapes
  # are asserted before the negative. (1) a clean job-structured pipeline must PASS — job-scope must not
  # over-fire on ordinary `jobs:` YAML; (2) an UNRELATED job's `if: false` beside a conforming job must
  # STILL PASS — the fix is job-SCOPED, NOT a return to file-scope (the parent's over-strict posture).
  printf 'jobs:\n  conformance:\n    steps:\n      - name: aggregate\n        run: sh conformance/verify.sh --require\n' > "$d/gh-job-ok.yml"
  enforcing_present "$d/gh-job-ok.yml" github || { echo "FAIL: selftest — F1 GitHub: a clean job-structured pipeline must PASS (job-scope must not over-fire)"; st=1; }
  printf 'jobs:\n  deploy:\n    if: false\n    steps:\n      - name: d\n        run: echo deploy\n  conformance:\n    steps:\n      - name: aggregate\n        run: sh conformance/verify.sh --require\n' > "$d/gh-job-unrelated-iffalse.yml"
  enforcing_present "$d/gh-job-unrelated-iffalse.yml" github || { echo "FAIL: selftest — F1 GitHub: an UNRELATED job's if:false must NOT disqualify the conforming job (job-scope, not file-scope)"; st=1; }
  # A non-enumerated branch-guard `if:` expression on the OWNING job stays HONEST-CEILING — it must NOT
  # be evaluated as a suppressor, else the shipped pipelines' `if: github.ref == …` provenance jobs FAIL.
  printf 'jobs:\n  conformance:\n    if: github.ref == \x27refs/heads/main\x27\n    steps:\n      - name: aggregate\n        run: sh conformance/verify.sh --require\n' > "$d/gh-job-branchguard.yml"
  enforcing_present "$d/gh-job-branchguard.yml" github || { echo "FAIL: selftest — F1 GitHub: a non-enumerated branch-guard if: on the owning job must stay HONEST-CEILING (PASS), not be evaluated"; st=1; }

  # ── H2: shapes that leave the step PRESENT but unable to fail the build (ON THE OWNING STEP/JOB) ───
  # Every one of these PASSED the pre-fix lock (security review drove 19 shapes through the real
  # --fleet). `|| :` is one character from the `|| true` fixture that already existed, which is why
  # suppression is now a SET rather than a literal. Under §5 these are asserted with the suppressor ON
  # THE OWNING step/job — the ONLY position that now disqualifies (the false-positive legs above prove
  # an unrelated one does not).
  printf '      - name: x\n        run: sh conformance/verify.sh --require || :\n'        > "$d/gh-colon.yml"
  printf '      - name: x\n        run: sh conformance/verify.sh --require || exit 0\n'   > "$d/gh-exit0.yml"
  printf '      - name: x\n        run: sh conformance/verify.sh --require ; true\n'      > "$d/gh-semitrue.yml"
  printf '      - name: x\n        continue-on-error: true\n        run: sh conformance/verify.sh --require\n' > "$d/gh-coe.yml"
  printf '      - name: x\n        if: false\n        run: sh conformance/verify.sh --require\n'               > "$d/gh-iffalse.yml"
  for _bx in gh-colon gh-exit0 gh-semitrue gh-coe gh-iffalse; do
    enforcing_present "$d/$_bx.yml" github && { echo "FAIL: selftest — GitHub suppression '$_bx' wrongly passed"; st=1; }
  done
  # F1 (fix-loop): a JOB-level `if: false` on the job OWNING the enforcing step disables the whole job —
  # CI stays green — so it must FAIL. Step-scoping alone (the b4ed401 posture) never inspected job keys.
  printf 'jobs:\n  conformance:\n    if: false\n    runs-on: ubuntu-latest\n    steps:\n      - name: aggregate\n        run: sh conformance/verify.sh --require\n' > "$d/gh-job-iffalse.yml"
  enforcing_present "$d/gh-job-iffalse.yml" github && { echo "FAIL: selftest — F1 GitHub: a job-level if:false on the OWNING job wrongly passed (the whole job never runs)"; st=1; }
  printf '.hidden:\n  script: [sh conformance/verify.sh --require]\n'                        > "$d/gl-hidden.yml"
  printf 'j:\n  allow_failure: true\n  script: [sh conformance/verify.sh --require]\n'       > "$d/gl-allowfail.yml"
  printf 'j:\n  when: manual\n  script: [sh conformance/verify.sh --require]\n'              > "$d/gl-manual.yml"
  printf 'j:\n  rules:\n    - when: never\n  script: [sh conformance/verify.sh --require]\n' > "$d/gl-never.yml"
  printf 'default:\n  cache:\n    paths:\n      - sh conformance/verify.sh --require\n'      > "$d/gl-cache.yml"
  for _bx in gl-hidden gl-allowfail gl-manual gl-never gl-cache; do
    enforcing_present "$d/$_bx.yml" gitlab && { echo "FAIL: selftest — GitLab suppression '$_bx' wrongly passed"; st=1; }
  done
  # ── F2 (fix-loop): every suppressor in FLOW-LIST form must FAIL ────────────────────────────────────
  # The SHIPPED profiles/typescript-node/ci.gitlab-ci.yml uses `script: [ … ]`, so a suppressor is
  # followed IMMEDIATELY by `]` (no whitespace/EOL). The pre-fix suppressed() anchored on whitespace/EOL
  # and missed 4 of 5 (`|| true`, `|| :`, `; true`, `&& true`; only `|| exit 0` was caught). The
  # conforming flow-list `gl-flow-ok` above (a real shipped shape) must still PASS — asserted first.
  printf 'gate-x:\n  script: [sh conformance/verify.sh --require || true]\n'   > "$d/gl-flow-ortrue.yml"
  printf 'gate-x:\n  script: [sh conformance/verify.sh --require || :]\n'      > "$d/gl-flow-orcolon.yml"
  printf 'gate-x:\n  script: [sh conformance/verify.sh --require || exit 0]\n' > "$d/gl-flow-orexit0.yml"
  printf 'gate-x:\n  script: [sh conformance/verify.sh --require ; true]\n'    > "$d/gl-flow-semitrue.yml"
  printf 'gate-x:\n  script: [sh conformance/verify.sh --require && true]\n'   > "$d/gl-flow-andtrue.yml"
  for _bx in gl-flow-ortrue gl-flow-orcolon gl-flow-orexit0 gl-flow-semitrue gl-flow-andtrue; do
    enforcing_present "$d/$_bx.yml" gitlab && { echo "FAIL: selftest — F2 GitLab flow-list suppression '$_bx' wrongly passed (']' boundary missed)"; st=1; }
  done
  # The inline GitHub list form is LEGITIMATE and must still pass (it was a documented false negative).
  printf '      - run: sh conformance/verify.sh --require\n' > "$d/gh-inline.yml"
  enforcing_present "$d/gh-inline.yml" github || { echo "FAIL: selftest — legitimate inline '- run:' form wrongly rejected"; st=1; }

  # ── §5.2 NORMALISATION — each variant, ON THE OWNING STEP/JOB, must STILL disqualify ──────────────
  # Review found ~12 one-token bypasses of the file-level matcher. Normalisation before matching —
  # lowercase, strip quotes, strip a trailing comment, allow a leading `- `, booleans (true|yes|on) —
  # closes the enumerated ones. Each fixture carries the suppressor on the OWNING step/job, so a
  # regression to a false PASS here means normalisation was dropped, not that scoping over-fired.
  printf '      - name: x\n        continue-on-error: True\n        run: sh conformance/verify.sh --require\n'      > "$d/gh-n-mixed.yml"
  printf '      - name: x\n        continue-on-error: TRUE\n        run: sh conformance/verify.sh --require\n'      > "$d/gh-n-upper.yml"
  printf '      - name: x\n        continue-on-error: yes\n        run: sh conformance/verify.sh --require\n'       > "$d/gh-n-yes.yml"
  printf '      - name: x\n        continue-on-error: on\n        run: sh conformance/verify.sh --require\n'        > "$d/gh-n-on.yml"
  printf '      - name: x\n        continue-on-error: true # tmp\n        run: sh conformance/verify.sh --require\n' > "$d/gh-n-comment.yml"
  printf '      - continue-on-error: true\n        run: sh conformance/verify.sh --require\n'                      > "$d/gh-n-dash.yml"
  for _bx in gh-n-mixed gh-n-upper gh-n-yes gh-n-on gh-n-comment gh-n-dash; do
    enforcing_present "$d/$_bx.yml" github && { echo "FAIL: selftest — §5.2 GitHub normalisation '$_bx' wrongly passed (owning-step suppressor not caught)"; st=1; }
  done
  printf 'j:\n  when: "manual"\n  script: [sh conformance/verify.sh --require]\n'     > "$d/gl-n-quoted.yml"
  printf 'j:\n  allow_failure: YES\n  script: [sh conformance/verify.sh --require]\n' > "$d/gl-n-yes.yml"
  for _bx in gl-n-quoted gl-n-yes; do
    enforcing_present "$d/$_bx.yml" gitlab && { echo "FAIL: selftest — §5.2 GitLab normalisation '$_bx' wrongly passed"; st=1; }
  done

  # ── §3 DISPOSITION MATRIX, ON THE REAL SINGLE-TREE DISPATCH ─────────────────────────────────────
  # Drives the REAL dispatch by executing this script inside a fixture tree — the dispatch lives in the
  # main body, so a function-level test would prove nothing about the path an adopter actually runs.
  # (This file never `cd`s to a repo root, so a fixture-cwd run evaluates the FIXTURE. That is not true
  # of every check in this directory; it is true here, and that is why the technique is used here.)
  #
  # ★ POSITIVE ROWS FIRST, DELIBERATELY. A check broken SHUT satisfies every negative row perfectly.
  # That has already happened twice in this file — six negative legs passed against a matcher a
  # tab-parsing bug had broken shut, and only a positive leg caught it. The ORDER is load-bearing.
  #
  # The fixtures state the origin marker LITERALLY rather than reusing $PIPELINE_ORIGIN_MARKER: a
  # fixture that reuses the implementation's own constant cannot see that constant change.
  _self=$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")
  _MXMARK='# kit-pipeline-origin: emitted'
  _mx=$(mktemp -d) || { echo "verify-enforced-wired --selftest: FAIL (no tmpdir for the matrix legs)"; exit 1; }

  _mx_tree() {   # <name> [raw] -> echo a fresh fixture tree; "incepted" (must-have) unless "raw"
    _mt="$_mx/$1"
    mkdir -p "$_mt"
    if [ "${2:-}" != raw ]; then : > "$_mt/ENGINEERING-PRINCIPLES.md"; fi
    printf '%s\n' "$_mt"
  }

  _mx_pipe() {   # <tree> <github|gitlab> <emitted|adopter> <step|nostep|silent>
    if [ "$2" = github ]; then _mp_f="$1/.github/workflows/ci.yml"; else _mp_f="$1/.gitlab-ci.yml"; fi
    mkdir -p "$(dirname "$_mp_f")"
    : > "$_mp_f"
    if [ "$3" = emitted ]; then printf '%s\n' "$_MXMARK" >> "$_mp_f"; fi
    if [ "$2" = github ]; then
      case "$4" in
        step)   printf 'jobs:\n  gate:\n    steps:\n      - name: aggregate\n        run: sh conformance/verify.sh --require\n' >> "$_mp_f" ;;
        nostep) printf 'jobs:\n  gate:\n    steps:\n      - name: render\n        run: sh conformance/verify.sh --selftest\n'   >> "$_mp_f" ;;
        *)      printf 'jobs:\n  gate:\n    steps:\n      - name: build\n        run: make all\n'                               >> "$_mp_f" ;;
      esac
    else
      case "$4" in
        step)   printf 'conformance-aggregate:\n  stage: verify\n  script: [sh conformance/verify.sh --require]\n'  >> "$_mp_f" ;;
        nostep) printf 'conformance-aggregate:\n  stage: verify\n  script: [sh conformance/verify.sh --selftest]\n' >> "$_mp_f" ;;
        *)      printf 'build:\n  stage: build\n  script: [make all]\n'                                             >> "$_mp_f" ;;
      esac
    fi
  }

  _mx_kitmark() { # <tree> — make the fixture look like the kit's OWN repo: a control-plane, export-
                  # ignored marker present (golden-path.yml). NOT ENGINEERING-PRINCIPLES.md — that is an
                  # incepted-adopter marker, and folding it in is the trap the disjointness leg guards.
    mkdir -p "$1/.github/workflows"; : > "$1/.github/workflows/golden-path.yml"
  }

  _MX_OUT=''; _MX_RC=0
  _mx_run() {    # <tree> [extra-arg] — run the REAL dispatch in <tree>; capture output AND rc
    if [ -n "${2:-}" ]; then
      _MX_OUT=$( cd "$1" && sh "$_self" "$2" 2>&1 ) && _MX_RC=0 || _MX_RC=$?
    else
      _MX_OUT=$( cd "$1" && sh "$_self" 2>&1 ) && _MX_RC=0 || _MX_RC=$?
    fi
  }
  # The message is asserted, never just the exit code: an rc-only assertion is satisfied by ANY
  # incidental failure, which is how a check broken shut reads as six passing negative legs.
  _mx_assert() { # <tree> <expect-rc> <must-contain|-> <label> [extra-arg]
    _mx_run "$1" "${5:-}"
    if [ "$_MX_RC" != "$2" ]; then
      echo "FAIL: matrix [$4] — expected rc=$2, got rc=$_MX_RC :: $_MX_OUT"; st=1; return 0
    fi
    if [ "$3" != - ] && ! printf '%s\n' "$_MX_OUT" | grep -qF "$3"; then
      echo "FAIL: matrix [$4] — rc=$2 as expected, but the message never says '$3' :: $_MX_OUT"; st=1
    fi
    return 0
  }
  _mx_refute() { # <must-NOT-contain> <label> — asserted on the LAST _mx_assert's output
    if printf '%s\n' "$_MX_OUT" | grep -qF "$1"; then
      echo "FAIL: matrix [$2] — the message must not mention '$1' :: $_MX_OUT"; st=1
    fi
    return 0
  }

  # ---- PASS rows: legitimate trees that must stay GREEN (asserted before any FAIL row) ----
  _mt1=$(_mx_tree gh-emitted-step);  _mx_pipe "$_mt1" github emitted step
  _mx_assert "$_mt1" 0 '.github/workflows/ci.yml' 'kit-installed github + step -> PASS'
  _mt2=$(_mx_tree gl-emitted-step);  _mx_pipe "$_mt2" gitlab emitted step
  _mx_assert "$_mt2" 0 '.gitlab-ci.yml' 'kit-installed gitlab + step -> PASS'
  _mx_refute '.github/workflows/ci.yml' 'kit-installed gitlab + step -> PASS'
  _mt3=$(_mx_tree gh-adopter-step);  _mx_pipe "$_mt3" github adopter step
  _mx_assert "$_mt3" 0 '.github/workflows/ci.yml' 'adopter-owned github + step -> PASS (they merged it)'
  _mt4=$(_mx_tree gl-adopter-step);  _mx_pipe "$_mt4" gitlab adopter step
  _mx_assert "$_mt4" 0 '.gitlab-ci.yml' 'adopter-owned gitlab + step -> PASS (they merged it)'
  _mx_refute '.github/workflows/ci.yml' 'adopter-owned gitlab + step -> PASS'
  _mt5=$(_mx_tree both-ok); _mx_pipe "$_mt5" github emitted step; _mx_pipe "$_mt5" gitlab emitted step
  _mx_assert "$_mt5" 0 '.gitlab-ci.yml' 'D-1: BOTH pipelines conforming -> PASS, and BOTH are judged'
  _mt6=$(_mx_tree raw-export raw)
  _mx_assert "$_mt6" 0 'N/A' 'raw pre-incept export, no pipeline -> N/A'

  # ---- N/A-with-remedy rows: an unmet DOCUMENTED merge obligation is NOT a failure ----
  # docs/adoption/brownfield.md tells the adopter incept PRESERVES their pipeline and that they merge
  # the kit's gate ids by hand. Failing them for the state the kit's own documentation created is the
  # false-FAIL class this whole design removes — so these rows exit 0, and they print the YAML.
  _mt7=$(_mx_tree gh-adopter-nostep); _mx_pipe "$_mt7" github adopter nostep
  _mx_assert "$_mt7" 0 'run: sh conformance/verify.sh --require' 'adopter-owned github, no step -> N/A + the exact YAML to paste'
  _mt8=$(_mx_tree gl-adopter-nostep); _mx_pipe "$_mt8" gitlab adopter nostep
  _mx_assert "$_mt8" 0 'script: [sh conformance/verify.sh --require]' 'adopter-owned gitlab, no step -> N/A + the exact (GitLab) YAML to paste'
  _mx_refute '.github/workflows/ci.yml' 'adopter-owned gitlab, no step -> N/A'

  # ---- FAIL rows ----
  _mt9=$(_mx_tree gh-emitted-nostep); _mx_pipe "$_mt9" github emitted nostep
  _mx_assert "$_mt9" 1 'kit-pipeline-origin' 'kit-installed github, step REMOVED -> FAIL (real drift, named as such)'
  _mta=$(_mx_tree gl-emitted-nostep); _mx_pipe "$_mta" gitlab emitted nostep
  _mx_assert "$_mta" 1 '.gitlab-ci.yml' 'kit-installed gitlab, step REMOVED -> FAIL (real drift)'
  _mx_refute '.github/workflows/ci.yml' 'kit-installed gitlab, step REMOVED -> FAIL'
  # A pipeline that never mentions verify.sh AT ALL must not be told it is "renderer-only (--selftest)".
  # Diagnosing a cause that is not the cause is how a blocking gate earns its deletion.
  _mtb=$(_mx_tree gh-emitted-silent); _mx_pipe "$_mtb" github emitted silent
  _mx_assert "$_mtb" 1 - 'kit-installed github, NO verify.sh line at all -> FAIL'
  _mx_refute 'renderer-only' 'a pipeline that never mentions verify.sh must not be diagnosed as renderer-only'
  _mtc=$(_mx_tree none-incepted)
  _mx_assert "$_mtc" 1 - 'incepted tree with NEITHER pipeline -> FAIL (fail-closed, never N/A)'
  # D-1: a tree carrying BOTH pipelines is judged on EVERY pipeline present. A github-if-present-else-
  # gitlab selection would never look at the .gitlab-ci.yml and would pass this tree.
  _mtd=$(_mx_tree both-gl-bad); _mx_pipe "$_mtd" github emitted step; _mx_pipe "$_mtd" gitlab emitted nostep
  _mx_assert "$_mtd" 1 '.gitlab-ci.yml' 'D-1: both present, GITLAB stripped -> FAIL (a github-first selection would pass it)'
  _mte=$(_mx_tree both-gh-bad); _mx_pipe "$_mte" github emitted nostep; _mx_pipe "$_mte" gitlab emitted step
  _mx_assert "$_mte" 1 '.github/workflows/ci.yml' 'D-1: both present, GITHUB stripped -> FAIL'

  # ── §3 KIT-SOURCE CELL, ON THE REAL DISPATCH (review F1) ────────────────────────────────────────
  # The kit repo's own top-level ci.yml is SOURCE — incept never installs it, so it carries no origin
  # marker and _pipeline_origin calls it 'adopter'. Task 2 therefore returned N/A when the kit's own
  # battery step was stripped: a self-governance hole (core principle 4). Kit-source is derived
  # STRUCTURALLY — golden-path.yml OR docs/ROADMAP-KIT.md, both control-plane and export-ignored, so no
  # adopter export or incepted tree carries either. This downgrade is a FAIL-ADDER only: a kit-repo tree
  # WITH the step still PASSes; it can never open a bypass.
  #
  # ★ POSITIVE/LEGIT ROWS FIRST (both exit 0), the FAIL row last. The disjointness row is the mandatory
  # one: a brownfield incepted adopter (ENGINEERING-PRINCIPLES.md present, NEITHER kit marker) must stay
  # N/A-remedy — proving ENGINEERING-PRINCIPLES.md was NOT folded into the kit-source predicate.
  _mtk1=$(_mx_tree kitsrc-step raw); _mx_kitmark "$_mtk1"; _mx_pipe "$_mtk1" github adopter step
  _mx_assert "$_mtk1" 0 '.github/workflows/ci.yml' 'F1: kit-source repo (unmarked ci.yml) WITH step -> PASS (still passes)'
  # DISJOINTNESS (mandatory): incepted adopter, no kit marker, no step -> N/A-remedy, NOT FAIL.
  _mtk2=$(_mx_tree kitsrc-disjoint); _mx_pipe "$_mtk2" github adopter nostep
  _mx_assert "$_mtk2" 0 'run: sh conformance/verify.sh --require' 'F1 disjointness: incepted brownfield adopter (ENGINEERING-PRINCIPLES.md, NO kit marker), no step -> N/A-remedy, NOT FAIL'
  _mx_refute 'self-enforce' 'F1 disjointness: a brownfield adopter must NEVER see the kit-self-enforcement verdict'
  # THE F1 FIX — the single most important leg: kit's own repo, step STRIPPED -> FAIL, diagnosed as kit
  # self-enforcement, and NOT reusing the adopter N/A-remedy text (which would tell the kit to "merge" a
  # step it itself dropped).
  _mtk3=$(_mx_tree kitsrc-nostep raw); _mx_kitmark "$_mtk3"; _mx_pipe "$_mtk3" github adopter nostep
  _mx_assert "$_mtk3" 1 'self-enforce' 'F1: kit-source repo, step STRIPPED -> FAIL (kit self-enforcement, named as such)'
  _mx_refute 'ADOPTER-OWNED' 'F1: the kit-source FAIL must NOT reuse the adopter N/A-remedy text'

  # ---- argv discipline: the VERIFY_ENFORCED_WF env read is GONE ─────────────────────────────────
  # An env-redirectable control-plane path is the vacuity this repo forbids. But a STALE invocation
  # (`VERIFY_ENFORCED_WF=x sh …`) must not quietly check the cwd instead and answer about the wrong
  # tree — so unknown argv FAILs loudly, and the seam is an ARGUMENT.
  _mtf=$(_mx_tree argv-gh); _mx_pipe "$_mtf" github emitted step
  _mx_assert "$_mtf" 1 'unknown argument' 'an unknown argument must FAIL LOUDLY, never silently judge the cwd' '--bogus'
  _mx_assert "$_mtf" 0 '.github/workflows/ci.yml' '--wf=<path> judges the NAMED pipeline' "--wf=$_mtf/.github/workflows/ci.yml"
  _mtg=$(_mx_tree argv-gl); _mx_pipe "$_mtg" gitlab emitted nostep
  _mx_assert "$_mtf" 1 '.gitlab-ci.yml' '--wf= a gitlab file is judged with the GITLAB matcher, from a github cwd' "--wf=$_mtg/.gitlab-ci.yml"
  _mx_assert "$_mtf" 1 'names no file' '--wf= a nonexistent path must FAIL (fail-closed), never pass vacuously' "--wf=$_mx/nope.yml"

  # ── KIT-UPDATE-PROFILE-CI-DRIFT (design §3): the drift leg on the REAL dispatch ────────────────────
  # One load-bearing negative per control. The fixture PROFILE is the K5-conforming fixture above (it
  # carries the kit:owned markers), read from the fixture tree's own profiles/ — never the kit's.
  _dr_assert() {  # <tree> <expect-rc> <must-contain|-> <label> [argv...] — run the dispatch (or a copy: _DR_SELF)
    _da_t=$1; _da_rc=$2; _da_c=$3; _da_l=$4; shift 4
    _MX_OUT=$( cd "$_da_t" && sh "${_DR_SELF:-$_self}" "$@" 2>&1 ) && _MX_RC=0 || _MX_RC=$?
    if [ "$_MX_RC" != "$_da_rc" ]; then echo "FAIL: drift [$_da_l] — expected rc=$_da_rc, got rc=$_MX_RC :: $_MX_OUT"; st=1; return 0; fi
    if [ "$_da_c" != - ] && ! printf '%s\n' "$_MX_OUT" | grep -qF -e "$_da_c"; then
      echo "FAIL: drift [$_da_l] — rc=$_da_rc as expected, but the output never says '$_da_c' :: $_MX_OUT"; st=1
    fi
    return 0
  }
  _dr_prof() {  # <tree> <github|gitlab> — the in-tree profile pipeline the leg compares against
    mkdir -p "$1/profiles/p"
    if [ "$2" = github ]; then _kst_fx_gh "$1/profiles/p/ci.yml"; else _kst_fx_gl "$1/profiles/p/ci.gitlab-ci.yml"; fi
  }
  _dr_stale_wf() {  # <tree> <emitted|adopter> — the plain-step workflow (no --changed) of a pre-3.232.0 adopter
    _mx_pipe "$1" github "$2" step
  }
  # (1) drift -> notice; positive FIRST (a leg that never fires satisfies every silent leg below)
  _dt=$(_mx_tree dr-stale); _dr_prof "$_dt" github; _dr_stale_wf "$_dt" emitted
  _dr_assert "$_dt" 1 'CI-DRIFT:' 'drift: emitted GitHub workflow without the listing -> FAIL with the notice'
  for _dn in 'changed-listing' '3.232.0' 'git diff -z --name-only' 'kit-ci-decline: changed-listing' '>>> kit:owned changed-listing'; do
    printf '%s\n' "$_MX_OUT" | grep -qF -e "$_dn" || { echo "FAIL: drift [notice] — the notice never says '$_dn' :: $_MX_OUT"; st=1; }
  done
  # load-bearing negative: the greppable switch flipped OFF in a copy -> the leg goes green (it is live)
  sed 's/^_VEW_DRIFT=on$/_VEW_DRIFT=off/' "$_self" > "$_mx/vew-off.sh"
  if cmp -s "$_mx/vew-off.sh" "$_self"; then echo "FAIL: drift [switch] — no '_VEW_DRIFT=on' line to flip (vacuous negative)"; st=1; fi
  _DR_SELF="$_mx/vew-off.sh"
  _dr_assert "$_dt" 0 - 'drift: switch OFF -> the same fixture is green (the leg was the only red)'
  _DR_SELF=''   # explicit reset: a prefix assignment on a function call persists under dash and bash-as-sh
  printf '%s\n' "$_MX_OUT" | grep -qF 'CI-DRIFT' && { echo "FAIL: drift [switch] — OFF still printed a notice"; st=1; }
  # (2) current -> silent
  _dt=$(_mx_tree dr-current); _dr_prof "$_dt" github
  { printf '%s\n' "$_MXMARK"; cat "$_dt/profiles/p/ci.yml"; } > "$_dt/.github-wf.tmp"; mkdir -p "$_dt/.github/workflows"; mv "$_dt/.github-wf.tmp" "$_dt/.github/workflows/ci.yml"
  _dr_assert "$_dt" 0 'CI capabilities current: changed-listing' 'drift: workflow == profile -> silent and says it checked'
  printf '%s\n' "$_MX_OUT" | grep -qF 'CI-DRIFT' && { echo "FAIL: drift [current] — a current workflow got a notice"; st=1; }
  # (3) equivalent adapted -> silent; the (b) half is live
  _dt=$(_mx_tree dr-adapted); _dr_prof "$_dt" github; mkdir -p "$_dt/.github/workflows"
  { printf '%s\n' "$_MXMARK"; printf 'jobs:\n  mine:\n    steps:\n      - name: my own diff\n        run: echo "MY_LIST=$RUNNER_TEMP/l" >> "$GITHUB_ENV"\n      - name: Gate\n        run: sh conformance/verify.sh --require ${MY_LIST:+--changed "$MY_LIST"}\n'; } > "$_dt/.github/workflows/ci.yml"
  _dr_assert "$_dt" 0 'CI capabilities current' 'drift: renamed variable, no --summary-file, other step name -> silent'
  printf '%s\n' "$_MX_OUT" | grep -qF 'CI-DRIFT' && { echo "FAIL: drift [adapted] — an equivalent adaptation got a notice"; st=1; }
  { printf '%s\n' "$_MXMARK"; printf 'jobs:\n  mine:\n    steps:\n      - name: Gate\n        run: sh conformance/verify.sh --require ${NOPE:+--changed "$NOPE"}\n'; } > "$_dt/.github/workflows/ci.yml"
  _dr_assert "$_dt" 1 'CI-DRIFT:' 'drift: --changed "$NOPE" with no NOPE= anywhere -> notice (the variable half is live)'
  # (4) brownfield never red; the origin marker is what makes it red
  _dt=$(_mx_tree dr-brown); _dr_prof "$_dt" github; _dr_stale_wf "$_dt" adopter
  _dr_assert "$_dt" 0 'CI-DRIFT:' 'drift: unmarked (adopter-owned) stale workflow -> notice, rc 0'
  _dt=$(_mx_tree dr-brown-marked); _dr_prof "$_dt" github; _dr_stale_wf "$_dt" emitted
  _dr_assert "$_dt" 1 'CI-DRIFT:' 'drift: the SAME file with the origin marker -> rc 1 (provenance is the discriminator)'
  # (5) decline is scoped to the drift leg
  _dt=$(_mx_tree dr-decl); _dr_prof "$_dt" github; _dr_stale_wf "$_dt" emitted
  printf '# kit-ci-decline: changed-listing\n' >> "$_dt/.github/workflows/ci.yml"
  _dr_assert "$_dt" 0 'declined: changed-listing' 'drift: decline line -> rc 0 with the declined line'
  printf '%s\n' "$_MX_OUT" | grep -qF 'CI-DRIFT:' && { echo "FAIL: drift [decline] — a declined capability still printed the notice"; st=1; }
  _dt=$(_mx_tree dr-decl-nostep); _dr_prof "$_dt" github; _mx_pipe "$_dt" github emitted nostep
  printf '# kit-ci-decline: changed-listing\n' >> "$_dt/.github/workflows/ci.yml"
  _dr_assert "$_dt" 1 'kit-pipeline-origin' 'drift: the decline never silences the aggregate FAIL (decline is scoped)'
  _dt=$(_mx_tree dr-decl-unknown); _dr_prof "$_dt" github; _dr_stale_wf "$_dt" emitted
  printf '# kit-ci-decline: no-such-capability\n' >> "$_dt/.github/workflows/ci.yml"
  _dr_assert "$_dt" 1 'CI-DRIFT:' 'drift: a decline for a different id does not silence changed-listing'
  # (6) compared against the IN-TREE profile: an older profile without the capability -> silent
  _dt=$(_mx_tree dr-oldprof); mkdir -p "$_dt/profiles/p"
  printf 'jobs:\n  ci:\n    steps:\n      - name: Gate\n        run: sh conformance/verify.sh --require\n' > "$_dt/profiles/p/ci.yml"
  _dr_stale_wf "$_dt" emitted
  _dr_assert "$_dt" 0 - 'drift: the in-tree profile lacks the capability (older release) -> silent'
  printf '%s\n' "$_MX_OUT" | grep -qF 'CI-DRIFT' && { echo "FAIL: drift [in-tree] — judged against something other than the in-tree profile"; st=1; }
  # (7) N/A faces
  _dt=$(_mx_tree dr-src raw); _mx_kitmark "$_dt"; _dr_prof "$_dt" github; _dr_stale_wf "$_dt" adopter
  _dr_assert "$_dt" 0 'locked by --fleet' 'drift: kit-source tree -> N/A naming source'
  printf '%s\n' "$_MX_OUT" | grep -qF 'CI-DRIFT:' && { echo "FAIL: drift [source] — the kit's own pipeline got a notice"; st=1; }
  _dt=$(_mx_tree dr-noprof); _dr_stale_wf "$_dt" emitted
  _dr_assert "$_dt" 0 'no profile pipeline' 'drift: no in-tree profile -> N/A naming it'
  # (8) GitLab: the notice is the GitLab block, no GitHub word; the profile as the workflow is silent
  _dt=$(_mx_tree dr-gl); _dr_prof "$_dt" gitlab; _mx_pipe "$_dt" gitlab emitted step
  _dr_assert "$_dt" 1 'CI-DRIFT:' 'drift: emitted GitLab pipeline without the listing -> FAIL with the notice'
  printf '%s\n' "$_MX_OUT" | grep -qF 'conformance-aggregate:' || { echo "FAIL: drift [gitlab] — the notice does not print the GitLab block :: $_MX_OUT"; st=1; }
  printf '%s\n' "$_MX_OUT" | grep -qF 'GITHUB_' && { echo "FAIL: drift [gitlab] — a GitHub string leaked into a GitLab notice :: $_MX_OUT"; st=1; }
  { printf '%s\n' "$_MXMARK"; cat "$_dt/profiles/p/ci.gitlab-ci.yml"; } > "$_dt/.gitlab-ci.yml"
  _dr_assert "$_dt" 0 'CI capabilities current' 'drift: the GitLab profile copied as the workflow -> silent'
  # (9) the --drift form (what kit-update runs): same text, rc 1 stale / 0 current, errors fail closed
  _dt=$(_mx_tree dr-form); _dr_prof "$_dt" github; _dr_stale_wf "$_dt" emitted
  _dr_assert "$_dt" 1 'CI-DRIFT: .github/workflows/ci.yml (github)' 'drift: --drift form prints the notice with the given paths' --drift --wf=.github/workflows/ci.yml --profile=profiles/p/ci.yml
  _dr_assert "$_dt" 0 - 'drift: --drift form on a current workflow is silent' --drift --wf=profiles/p/ci.yml --profile=profiles/p/ci.yml
  _dr_assert "$_dt" 2 'names no file' 'drift: --drift form with a missing workflow fails closed' --drift --wf=nope.yml --profile=profiles/p/ci.yml
  _dr_assert "$_dt" 2 'requires' 'drift: --drift form without --profile fails closed' --drift --wf=.github/workflows/ci.yml
  # _drift_has on a block-scalar `run: |` (verify line on its own line) is equivalent too
  printf 'jobs:\n  a:\n    steps:\n      - run: |\n          echo "L=x" >> "$GITHUB_ENV"\n          sh conformance/verify.sh --require ${L:+--changed "$L"}\n' > "$_mx/bs.yml"
  _drift_has changed-listing "$_mx/bs.yml" || { echo "FAIL: drift [key] — a block-scalar run: with the verify line on its own line must have the capability"; st=1; }
  # ── review round: equivalent wirings the first (b) rule read as lacking (silence is the safe direction) ──
  _hk() {  # <label> <file-content-printf-format> — an equivalent wiring must HAVE the capability
    printf "$2" > "$_mx/hk.yml"
    _drift_has changed-listing "$_mx/hk.yml" || { echo "FAIL: drift [key] — $1 must have the capability"; st=1; }
  }
  _hk 'a NAME= assignment earlier on the SAME verify line' 'jobs:\n  a:\n    steps:\n      - run: L=$(mktemp); sh conformance/verify.sh --require --changed "$L"\n'
  _hk 'a GitHub env: mapping key' 'jobs:\n  a:\n    env:\n      MY_LIST: /tmp/x\n    steps:\n      - run: sh conformance/verify.sh --require --changed "$MY_LIST"\n'
  _hk 'a GitLab variables: mapping key' 'job:\n  variables:\n    MY_LIST: /tmp/x\n  script:\n    - sh conformance/verify.sh --require --changed "$MY_LIST"\n'
  _hk 'a RUNNER_TEMP path prefix' 'jobs:\n  a:\n    steps:\n      - run: sh conformance/verify.sh --require --changed "$RUNNER_TEMP/list"\n'
  _hk 'a ${CI_PROJECT_DIR} path prefix' 'job:\n  script:\n    - sh conformance/verify.sh --require --changed "${CI_PROJECT_DIR}/list"\n'
  # load-bearing negatives: the widened rule is NOT "anything goes"
  printf 'jobs:\n  a:\n    steps:\n      - run: sh conformance/verify.sh --require --changed "$HOME/list"\n' > "$_mx/hk.yml"
  _drift_has changed-listing "$_mx/hk.yml" && { echo "FAIL: drift [key] — \$HOME is not a runner-provided listing prefix; it must lack the capability"; st=1; }
  printf 'jobs:\n  a:\n    steps:\n      - run: sh conformance/verify.sh --require --changed "$RUNNER_TEMP"\n' > "$_mx/hk.yml"
  _drift_has changed-listing "$_mx/hk.yml" && { echo "FAIL: drift [key] — a bare \$RUNNER_TEMP (a directory, no path suffix) must lack the capability"; st=1; }
  printf 'jobs:\n  a:\n    steps:\n      - run: sh conformance/verify.sh --require --changed "$NOPE"\n      - name: other\n        run: echo NOPE_X=1\n' > "$_mx/hk.yml"
  _drift_has changed-listing "$_mx/hk.yml" && { echo "FAIL: drift [key] — NOPE_X= must not satisfy NOPE (whole-name match)"; st=1; }
  # a profile directory name with a space must not word-split into a false "cannot evaluate"
  _dt=$(_mx_tree dr-space); mkdir -p "$_dt/profiles/my stack"; _kst_fx_gh "$_dt/profiles/my stack/ci.yml"; _dr_stale_wf "$_dt" emitted
  _dr_assert "$_dt" 1 'CI-DRIFT:' 'drift: a profile dir name with a space is still compared (no word-splitting)'
  printf '%s\n' "$_MX_OUT" | grep -qF 'cannot evaluate' && { echo "FAIL: drift [space] — word-splitting produced a false 'cannot evaluate' :: $_MX_OUT"; st=1; }
  # control bytes in the profile block never reach the notice (the same strip kit-update applies)
  _dt=$(_mx_tree dr-ctl); _dr_prof "$_dt" github; _dr_stale_wf "$_dt" emitted
  _esc=$(printf '\033')
  awk -v e="$_esc" '/<<< kit:owned changed-listing/ { print "      # note " e "[31mred" } { print }' "$_dt/profiles/p/ci.yml" > "$_dt/profiles/p/ci.new" && mv "$_dt/profiles/p/ci.new" "$_dt/profiles/p/ci.yml"
  grep -qF "$_esc" "$_dt/profiles/p/ci.yml" || { echo "FAIL: drift [ctl] — the fixture never carried the control byte (vacuous)"; st=1; }
  _dr_assert "$_dt" 1 'CI-DRIFT:' 'drift: a control byte in the profile block still yields the notice'
  printf '%s\n' "$_MX_OUT" | grep -qF "$_esc" && { echo "FAIL: drift [ctl] — an ESC byte from the profile block reached the notice"; st=1; }
  rm -rf "$_mx" 2>/dev/null || true

  if [ "$st" = 0 ]; then
    _banner=$(cat <<'BANNER'
OK: verify-enforced-wired selftest — the §3 disposition matrix on the REAL dispatch (kit-emitted
                       +/- step, kit-SOURCE +/- step (F1, disjoint from a brownfield adopter),
                       adopter-owned +/- step, both-pipelines, no-pipeline, raw export),
                       both platforms, PASS rows asserted BEFORE FAIL rows; matrix also locked as
                       a pure function incl. fail-closed on unenumerated input; argv rejected;
                       suppression is STEP/JOB-SCOPED (§5) — an UNRELATED continue-on-error / when:manual
                       elsewhere in the file no longer disqualifies an intact enforcing step (proven by
                       false-positive PASS legs asserted BEFORE the negatives); ON the OWNING step OR job,
                       in BLOCK and FLOW-LIST ([ … ]) form, the SET is rejected on both arms —
                       '|| true/:/exit 0/; true/&& true', continue-on-error, if:false (step AND job level),
                       allow_failure, when:manual/never (normalised: True/TRUE/yes/on, quoted, trailing
                       comment, leading '- '), hidden .job, non-script list items; an arbitrary job-level
                       if: branch guard stays honest-ceiling (NOT evaluated); cross-platform isolation;
                       fleet counts stated-not-derived; each per-platform zero guard killed ALONE;
                       the CI-DRIFT leg (notice on a stale emitted pipeline, silent on a current or
                       equivalently adapted one, rc 0 for brownfield, decline scoped, in-tree profile,
                       GitLab, --drift form) and its three --fleet locks (markers, own predicate, since).
    CEILING — what this green does NOT say. The matrix covers the rows ENUMERATED in the header;
    the input space is NOT proven exhausted, and a disposition invented for an unenumerated cell
    is exactly what took this file two review BLOCKs. Unenumerated combinations fail CLOSED, which
    is a safety property, not coverage. Suppression detection is an ENUMERATION of known forms, NOT a
    decision procedure — a sufficiently creative pipeline can still present the step and prevent it
    failing the build, so the class is open. Provenance is removable by the adopter (design §4 accepts
    that as a disclosed self-assertion of ownership), so a stripped marker downgrades enforcement to N/A.
BANNER
)
    # ── BANNER HONESTY (§5.3): the banner must STATE the ceiling and must NOT overclaim closure ──────
    # A verdict string that asserts coverage it lacks is what a future reviewer reads INSTEAD of the
    # regex — worse than silence. Load-bearing BOTH ways: re-introduce an overclaim (or delete the
    # honest ceiling) and one of these REDs. "fail CLOSED" is a safety property, NOT a closure claim, so
    # the forbidden set is phrased to admit it while rejecting "the class is closed" / "exhaustive".
    if printf '%s\n' "$_banner" | grep -qiE 'class is closed|suppression is closed|forms? (are )?exhaustive|fully closed|closes the class'; then
      echo "FAIL: selftest banner OVERCLAIMS suppression closure — §5 is an ENUMERATION, the class is OPEN"; exit 1
    fi
    printf '%s\n' "$_banner" | grep -qF 'the class is open' || { echo "FAIL: selftest banner must STATE the honest ceiling ('the class is open')"; exit 1; }
    printf '%s\n' "$_banner"
    exit 0
  fi
  exit 1
fi

# ── SINGLE-TREE DISPATCH ──────────────────────────────────────────────────────────────────────────
# UNKNOWN ARGV FAILS LOUDLY. The `VERIFY_ENFORCED_WF=<path> sh conformance/verify-enforced-wired.sh`
# env seam is deleted (an env-redirectable control-plane path is the vacuity this repo forbids, and
# it had zero code consumers). A stale invocation carrying it would otherwise silently judge the CWD
# tree instead of the named file — a wrong answer, quietly. The replacement seam is `--wf=<path>`.
_wf_arg=''; _drift_mode=0; _profile_arg=''
for _a in "$@"; do
  case "$_a" in
    --wf=*) _wf_arg=${_a#--wf=} ;;
    --drift) _drift_mode=1 ;;
    --profile=*) _profile_arg=${_a#--profile=} ;;
    *) echo "FAIL: unknown argument '$_a' (usage: [--wf=<path>] | --drift --wf=<path> --profile=<path> | --selftest | --fleet --expect-github=<n> --expect-gitlab=<m>)"; exit 1 ;;
  esac
done

# `--drift` (what kit-update runs on the new release): compare ONE workflow against ONE profile pipeline.
# 0 = nothing to say · 1 = stale, the notice is printed · 2 = bad argv / unreadable input (fail-closed).
if [ "$_drift_mode" = 1 ]; then
  if [ -z "$_wf_arg" ] || [ -z "$_profile_arg" ]; then
    echo "FAIL: --drift requires --wf=<path> AND --profile=<path>"; exit 2
  fi
  _drift_cli "$_wf_arg" "$_profile_arg"; exit $?
fi
if [ -n "$_profile_arg" ]; then echo "FAIL: --profile= is only valid with --drift"; exit 1; fi

if [ -n "$_wf_arg" ]; then
  if [ ! -f "$_wf_arg" ]; then
    echo "FAIL: --wf='$_wf_arg' names no file (fail-closed: a check that cannot find its subject must not report success)"
    exit 1
  fi
  # The platform derives from the NAMED file, not from the cwd — the whole point of naming it.
  case "$_wf_arg" in *gitlab*) _wfa_p=gitlab ;; *) _wfa_p=github ;; esac
  _wfa_rc=0; _judge "$_wf_arg" "$_wfa_p" || _wfa_rc=1
  if [ "$_wfa_rc" = 0 ] && [ "$_J_PASS" = 1 ]; then _drift_leg "$_wf_arg" "$_wfa_p" "$_J_ORIGIN" || _wfa_rc=1; fi
  exit "$_wfa_rc"
fi

# EVERY PIPELINE PRESENT IS JUDGED, and the tree passes only if every one of them passes (design D-1).
# A `github-if-present-else-gitlab` selection would judge a tree carrying BOTH on the github file alone
# and never look at its .gitlab-ci.yml — a pipeline the adopter really runs, silently unchecked.
# Judging all of them is strictly stronger and cannot create a bypass. (Measured: the kit's own repo
# has .github/workflows/ci.yml and no .gitlab-ci.yml, so its own result is unchanged.)
_n_seen=0; _tree_rc=0
_judge_and_drift() {  # <wf> <platform> — the verdict first; the drift leg only on a PASS (a louder verdict wins)
  if _judge "$1" "$2"; then
    if [ "$_J_PASS" = 1 ]; then _drift_leg "$1" "$2" "$_J_ORIGIN" || _tree_rc=1; fi
  else _tree_rc=1; fi
}
if [ -f "$GH_WF" ]; then _n_seen=$((_n_seen + 1)); _judge_and_drift "$GH_WF" github; fi
if [ -f "$GL_WF" ]; then _n_seen=$((_n_seen + 1)); _judge_and_drift "$GL_WF" gitlab; fi

if [ "$_n_seen" = 0 ]; then
  case "$(_wf_disposition 0 "$(_must_have_workflow)" none 0)" in
    NA) echo "N/A: verify-enforced — raw pre-incept export: no $GH_WF and no $GL_WF, and no incepted/kit marker (incept installs a pipeline; there is nothing to enforce yet)"; exit 0 ;;
    *)  echo "FAIL: a kit/incepted tree carries NO CI pipeline at all — looked for $GH_WF and $GL_WF. Fail-closed: run scripts/incept.sh --ci <github|gitlab>, or add one of them by hand."; exit 1 ;;
  esac
fi
exit "$_tree_rc"
