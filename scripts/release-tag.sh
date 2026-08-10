#!/bin/sh
# release-tag.sh — forge-neutral auto-tag-on-merge (the FLOOR). Reads VERSION, asserts release
# coherence INLINE, and creates+pushes v<VERSION> on HEAD if that tag doesn't already exist.
# Idempotent: no-op when the tag exists (VERSION unchanged / already released). Pure git — works
# on any forge; the CI trigger + push auth are the per-forge NATIVE binding (GitHub workflow /
# GitLab job / generic). Coherent BY CONSTRUCTION: it tags v<VERSION> on the commit whose VERSION
# file says that value, so a premature/incoherent tag is structurally impossible.
# Exit: 0 = tagged or no-op · 1 = coherence/precondition fail · 2 = bad usage/env.
#   release-tag.sh             # decide + tag + push (run in CI on main)
#   release-tag.sh --dry-run   # decide + print the action; never tags/pushes
#   release-tag.sh --selftest
# What it changes: Creates and pushes the git tag v<VERSION> on HEAD; --dry-run decides and prints only (never tags/pushes).
# Guardrails: Idempotent no-op when the tag already exists; refuses a non-semver VERSION and a failed coherence check (won't tag a stale/dup); refuses while the meta-control cadence is ESCALATED or its record is broken (cadence_gate — fail-closed, D-240807-1); RELEASE_TAG_CI_PROBE is eval'd via `sh -c` — set it only from trusted CI config, never repo/PR input.
# SECURITY (F2, hygiene security seat 2026-08-07): RELEASE_TAG_CADENCE / META_CONTROL_TAGS|N|ROOT
# are TRUSTED-INVOCATION-ONLY (selftest fixtures, trusted CI config) — never set them from repo/PR
# input. Any of them re-points or re-scopes the cadence detector, so ONLY the unmodified-env
# invocation carries the enforce-at-birth guarantee (D-240807-1, as ceiling-corrected); an
# overridden run banners itself out loud (cadence_gate) instead of silently waiving the gate.
set -eu
here=$(CDPATH='' cd "$(dirname "$0")" && pwd)
REMOTE="${RELEASE_TAG_REMOTE:-origin}"
COHERENCE="${RELEASE_TAG_COHERENCE:-$here/../conformance/version-tag-coherent.sh}"
CADENCE="${RELEASE_TAG_CADENCE:-$here/../conformance/meta-control-fresh.sh}"

# ── CP-10: RELEASE_SHA — the commit being released, resolved ONCE at invocation.
# WHY. `git tag <v>` tags HEAD *implicitly, at the moment it runs* — and ci_gate below polls for up to
# 10 minutes first. If HEAD moves during that poll (a checkout, a commit on another branch), the tag
# lands on whatever HEAD became. This is not hypothetical: on 2026-07-13 it put v3.129.0 on an UNMERGED
# feature branch, because the script was backgrounded for its CI poll while other git work continued.
# A HEAD-reading command that takes minutes to complete is a RACE. So: pin the SHA up front, thread it
# through every downstream step, and NEVER re-read HEAD after this point.
RELEASE_SHA=""

# decide -> prints "TAG v<x>" or "NOOP <reason>" on stdout; rc 0 ok, 1 precondition fail, 2 usage.
decide() {
  [ -f VERSION ] || { echo "release-tag: no VERSION file in $(pwd)" >&2; return 2; }
  v=$(tr -d '[:space:]' < VERSION)
  printf '%s' "$v" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "release-tag: VERSION '$v' not semver" >&2; return 2; }
  # coherence backstop INLINE: VERSION must not be behind a reachable tag (don't tag a stale/dup).
  sh "$COHERENCE" . --require >/dev/null 2>&1 || { echo "release-tag: coherence check failed for VERSION $v" >&2; return 1; }
  # idempotency: already tagged? remote first (authoritative), then local.
  if git ls-remote --tags "$REMOTE" "v$v" 2>/dev/null | grep -Fq "refs/tags/v$v" \
     || git tag -l "v$v" 2>/dev/null | grep -qx "v$v"; then
    echo "NOOP v$v already tagged"; return 0
  fi
  echo "TAG v$v"; return 0
}

# on_remote V -> 0 if vV exists on the remote (authoritative), 1 otherwise
on_remote() { git ls-remote --tags "$REMOTE" "$1" 2>/dev/null | grep -Fq "refs/tags/$1"; }

# ── CP-10: the on-branch gate. A release tag must point at a RELEASED commit.
#
# The existing ci_gate answers "is this commit GREEN?". It never asks "is this commit SHIPPED?" — and
# those are different questions. version-tag-coherent.sh does not close the gap either: it asserts
# VERSION matches a REACHABLE tag, which stayed GREEN the entire time v3.129.0 sat on an unmerged
# branch. The tag genuinely DID match VERSION. It was simply unreachable from main.
#
# default_branch -> the remote's default branch name (e.g. "main"); empty if unresolvable.
default_branch() {
  _db=$(git symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null || true)
  if [ -n "$_db" ]; then printf '%s' "${_db#"$REMOTE"/}"; return 0; fi
  # Fallback: ask the remote directly (costs a round-trip; only on a clone with no origin/HEAD ref).
  git remote show "$REMOTE" 2>/dev/null | sed -n 's/.*HEAD branch: *//p' | head -1
}

# on_default_branch <sha> -> 0 = sha IS an ancestor of the default branch (released)
#                            1 = sha is NOT (an unmerged commit — refuse to tag it)
#                            2 = the default branch cannot be resolved (caller degrades OPEN)
on_default_branch() {
  _s=$1
  _db=$(default_branch)
  [ -n "$_db" ] || return 2
  _ref="$REMOTE/$_db"
  git rev-parse --verify --quiet "$_ref" >/dev/null 2>&1 || return 2
  git merge-base --is-ancestor "$_s" "$_ref" 2>/dev/null && return 0
  return 1
}

# branch_gate <sha> -> 0 = proceed, 1 = REFUSE. Mirrors ci_gate's posture exactly.
#
# DEGRADE-OPEN on an unresolvable default branch (rc 2), deliberately and out loud: this guard exists to
# catch an HONEST SLIP — the one that actually happened — not to defeat an adversary, who can always
# `git tag` by hand. A forge-neutral kit must not become untaggable on a host it cannot introspect (no
# remote, a detached CI checkout, a fork). The honest ceiling is STATED, never silent: it always says
# which branch it checked, or that it could not check.
branch_gate() {
  _s=$1
  set +e; on_default_branch "$_s"; _rc=$?; set -e
  case "$_rc" in
    0) echo "release-tag: $(git rev-parse --short "$_s") is on $REMOTE/$(default_branch) — released, safe to tag"; return 0 ;;
    1) echo "release-tag: REFUSING to tag $(git rev-parse --short "$_s") — it is NOT an ancestor of $REMOTE/$(default_branch)." >&2
       echo "release-tag: a release tag must point at a RELEASED commit; this one is unmerged. Merge it first." >&2
       return 1 ;;
    *) echo "release-tag: cannot resolve $REMOTE's default branch — SKIPPING the on-branch check (degrade-open)" >&2
       return 0 ;;
  esac
}

# ── H1 (PHASE-B-HYGIENE / MC-CADENCE-1): the cadence gate. A release tag must not ship over a DEAD
# meta-control cadence. Measured third-instance failure: OVERDUE fired 2026-08-03 and six releases
# shipped over it in four days — the only consumer was a weekly advisory job nothing reads ("the
# signal fired and nothing consumed it", panel #38). This leg is the responder: it refuses exactly
# the act that accumulates exposure (tagging a release) while leaving per-PR CI non-blocking intact.
#
# ENFORCES AT BIRTH — no observe dial — as a RATIFIED EXCEPTION to the observe-first rollout ruling
# (docs/governance/DECISIONS.md §2.6 `D-240807-1` Δ1(ii)): an observe-mode responder to an ignored
# observe-mode signal is a second bell nobody hears; the doctrine's purpose (don't break flows on
# unproven mechanisms) is served instead by the fixture battery below and the narrow blast radius —
# this one script, remedy printed, the ruled DEFERRED escape intact.
#
# cadence_gate -> 0 = proceed (FRESH · N/A off-kit · OVERDUE-not-escalated, the advisory grace band),
#                 1 = REFUSE (ESCALATED, or rc!=0 with NO ^OVERDUE:/^ESCALATED: token = invalid state).
# FAIL-CLOSED on invalid state, deliberately and stated: a cadence gate that degrades OPEN on a
# broken cadence RECORD (marker desync, unparseable marker) is satisfiable by breaking the record —
# the opposite posture from branch_gate/ci_gate's degrade-open, because THEIR unknowns are host
# introspection limits while THIS unknown is the guarded artifact itself.
cadence_gate() {
  # F2 (hygiene security seat, 2026-08-07): the OVERRIDE BANNER. RELEASE_TAG_CADENCE and the
  # META_CONTROL_* hooks re-point or re-scope the detector — legitimate for selftest fixtures and
  # trusted CI config, but a caller-set var quietly de-escalates the ratified enforce-at-birth
  # gate to a fixture verdict. Posture per D3′ (drift control, NOT an arms race): the override
  # stays possible — env-hardening is unwinnable against a caller who owns the environment — but
  # it is never SILENT: an overridden run says so, unmissably, on every invocation.
  if [ -n "${RELEASE_TAG_CADENCE+x}${META_CONTROL_TAGS+x}${META_CONTROL_N+x}${META_CONTROL_ROOT+x}" ]; then
    echo "release-tag: ⚠⚠ OVERRIDDEN ENVIRONMENT — RELEASE_TAG_CADENCE/META_CONTROL_* is set by the caller: the cadence gate is consulting a caller-chosen detector/root/tag-list, and the enforce-at-birth guarantee (D-240807-1) does NOT apply to this run. Trusted-invocation-only; see this script's SECURITY header." >&2
  fi
  if [ ! -f "$CADENCE" ]; then
    echo "release-tag: cadence detector not found ($CADENCE) — REFUSING to tag (fail-closed: a missing detector must not silently waive the cadence gate; restore conformance/meta-control-fresh.sh or set RELEASE_TAG_CADENCE)" >&2
    return 1
  fi
  set +e; _cout=$(sh "$CADENCE" 2>&1); _crc=$?; set -e
  # M2 (hygiene reviewer, 2026-08-07): the TOKEN is the contract — an ^ESCALATED: verdict line
  # refuses REGARDLESS of rc, checked BEFORE the rc-0 fast path. A detector that prints ESCALATED
  # yet exits 0 (adversarial substitution, or an honest bug) must not be a green light (measured).
  if printf '%s\n' "$_cout" | grep -q '^ESCALATED:'; then
    printf '%s\n' "$_cout" >&2
    echo "release-tag: REFUSING to tag — the meta-control cadence is ESCALATED (>2N release tags past the last addressed panel)." >&2
    echo "release-tag: remedy — run the light 5-lens panel (docs/operations/meta-control.md) OR record a dated, human-ratified DEFERRED row; either appends a log row and advances the marker, which un-escalates by construction." >&2
    return 1
  fi
  [ "$_crc" = "0" ] && return 0   # FRESH, or N/A (cadence not adopted — the detector's applicability arm)
  if printf '%s\n' "$_cout" | grep -q '^OVERDUE:'; then
    # Fix-round 1 (reviewer 6): the CAP-FIRED face gets its own accurate warning. When the
    # serial-deferral cap fired, the remedy is a REAL panel run (more DEFERRED rows do not clear
    # it) and the tag count may be 0 — so the count-band text "past 2N tags this ESCALATES" would
    # be wrong on this face. Behavior identical on both faces (advisory: the tag proceeds).
    if printf '%s\n' "$_cout" | grep -q 'consecutive DEFERRED'; then
      echo "release-tag: WARNING — the meta-control cadence is OVERDUE via the serial-deferral cap (advisory: the tag proceeds; remedy is a REAL panel run — deferral is exhausted, and another DEFERRED row will not clear this)" >&2
    else
      echo "release-tag: WARNING — the meta-control cadence is OVERDUE (advisory grace band: the tag proceeds; past 2N tags this ESCALATES and refuses)" >&2
    fi
    return 0
  fi
  printf '%s\n' "$_cout" >&2
  echo "release-tag: REFUSING to tag — the cadence detector failed WITHOUT an OVERDUE/ESCALATED verdict (invalid cadence state: missing/unparseable marker or marker-log desync). Fail-closed on purpose — see this gate's header. Repair docs/governance/.meta-control-last + docs/governance/meta-control-log.md per docs/operations/meta-control.md." >&2
  return 1
}

# ci_probe -> prints "<status>\t<conclusion>" for HEAD's main CI run; empty if unknown.
# Default: GitHub via gh. Overridable via RELEASE_TAG_CI_PROBE (a command) for tests / non-GitHub forges.
# SECURITY: RELEASE_TAG_CI_PROBE is eval'd via 'sh -c' - set it only from trusted CI config, never repo/PR input.
ci_probe() {
  if [ -n "${RELEASE_TAG_CI_PROBE:-}" ]; then
    sh -c "$RELEASE_TAG_CI_PROBE" 2>/dev/null || true
    return 0
  fi
  command -v gh >/dev/null 2>&1 || return 0
  # CP-10: probe the PINNED release sha, not a fresh HEAD read. Re-reading HEAD here would ask CI about
  # a commit we are not tagging — the same race, one level down. Fall back to HEAD only when unpinned
  # (a direct ci_probe call from a test).
  _sha=${RELEASE_SHA:-$(git rev-parse HEAD 2>/dev/null)} || return 0
  [ -n "$_sha" ] || return 0
  gh run list --commit "$_sha" --workflow CI --json status,conclusion \
    --jq '.[0] | .status + "\t" + (.conclusion // "")' 2>/dev/null || true
}

# ci_gate -> 0 = proceed (success OR degrade-open), 1 = refuse (definitive CI failure).
# Bounded poll: the tag fires while CI may still be in-progress, so wait (bounded) for a conclusion;
# refuse only on a definitive failure; degrade OPEN (warn + proceed) on no-signal / timeout (forge-neutral).
ci_gate() {
  _timeout=${RELEASE_TAG_CI_TIMEOUT:-600}
  _interval=${RELEASE_TAG_CI_INTERVAL:-15}
  if [ "$_interval" -lt 1 ]; then _interval=1; fi   # floor: never busy-loop on a 0 interval
  _elapsed=0
  while :; do
    _out=$(ci_probe)
    _status=$(printf '%s' "$_out" | cut -f1)
    _concl=$(printf '%s' "$_out" | cut -f2)
    if [ -z "$_out" ] || [ -z "$_status" ]; then
      echo "release-tag: CI status unavailable for HEAD (no gh / not GitHub / no run) - proceeding (degrade-open)" >&2
      return 0
    fi
    if [ "$_status" = "completed" ]; then
      case "$_concl" in
        success) return 0 ;;
        failure|cancelled|timed_out|startup_failure)
          echo "release-tag: main CI concluded '$_concl' for HEAD - refusing to tag a red commit" >&2
          return 1 ;;
        *) echo "release-tag: CI conclusion '$_concl' is not a clear pass - proceeding (degrade-open)" >&2
           return 0 ;;
      esac
    fi
    if [ "$_elapsed" -ge "$_timeout" ]; then
      echo "release-tag: main CI still '$_status' after ${_timeout}s - proceeding (degrade-open); re-run after CI concludes for the gate to bite" >&2
      return 0
    fi
    sleep "$_interval"
    _elapsed=$((_elapsed + _interval))
  done
}

# ── B8 (GATE-PROVENANCE-SELF-DISABLES-AND-NEVER-GATES-THE-MERGE, PHASE-B-SPINE) — the provenance
# gate. ci_gate above reads only the WORKFLOW-level conclusion, which is blind to a per-job SKIP:
# measured live on a private user-owned adopter (codex-pulse-6, run 29929763014) — job `provenance`
# and `image-provenance` -> skipped, workflow -> success, and ci_gate proceeded silently. This gate
# reads per-JOB conclusions for the pinned RELEASE_SHA and distinguishes a legitimate skip (a
# validated na disposition, or image-provenance absent for a Dockerfile-less tree) from the disease
# (a declared/undecided gate that never ran). See
# docs/architecture/2026-08-08-b8-provenance-honesty-design.md §4.1.
CI_GATES="${RELEASE_TAG_CI_GATES:-$here/../conformance/ci-gates.sh}"
GATE_DISP_FILE="conformance/gate-dispositions.txt"

# prov_probe -> prints "<job-name>\t<conclusion>" lines for the pinned RELEASE_SHA's main CI run.
# Mirrors ci_probe's architecture (resolve the run for RELEASE_SHA, then read it) one level deeper
# (JOBS, not the workflow conclusion). Default: GitHub via gh. Overridable via
# RELEASE_TAG_PROV_PROBE (a command) for tests / non-GitHub forges.
# SECURITY (ci_probe's exact note, copied — this seam carries the identical trust boundary):
# RELEASE_TAG_PROV_PROBE is eval'd via `sh -c` — set it only from trusted CI config, never repo/PR input.
prov_probe() {
  if [ -n "${RELEASE_TAG_PROV_PROBE:-}" ]; then
    sh -c "$RELEASE_TAG_PROV_PROBE" 2>/dev/null || true
    return 0
  fi
  command -v gh >/dev/null 2>&1 || return 0
  # CP-10: probe the PINNED release sha, not a fresh HEAD read (same rule as ci_probe).
  _sha=${RELEASE_SHA:-$(git rev-parse HEAD 2>/dev/null)} || return 0
  [ -n "$_sha" ] || return 0
  _run=$(gh run list --commit "$_sha" --workflow CI --json databaseId --jq '.[0].databaseId // empty' 2>/dev/null) || return 0
  [ -n "$_run" ] || return 0
  gh run view "$_run" --json jobs --jq '.jobs[] | .name + "\t" + .conclusion' 2>/dev/null || true
}

# _prov_conclusion <job-name> <probe-output> -> prints the conclusion; rc 1 if the job is absent;
# rc 2 if the job name appears MORE THAN ONCE in the probe output. [fix round 1 item 1] An
# ambiguous/duplicate probe must never silently pick a match: "first detect, then verdict" — a
# multi-line value assigned straight into a `case` would fall through the `*` arm unnoticed
# (case pattern-matches the WHOLE string; "success\nsuccess" matches neither `success` nor
# `skipped`), so the duplicate is detected HERE, before any verdict is formed.
_prov_conclusion() {
  printf '%s\n' "$2" | awk -F'\t' -v j="$1" '
    $1==j { n++; last=$2 }
    END { if (n==0) exit 1; if (n>1) exit 2; print last }'
}

# _prov_disp_file -> prints a PATH to the gate-dispositions.txt content AS OF the pinned
# RELEASE_SHA (a trap-cleaned temp file, created once by provenance_gate itself — see the note
# there), falling back to the WORKING-TREE path only when RELEASE_SHA is unset (a direct-call
# selftest case — the same fallback ci_probe/prov_probe already apply to the SHA they query gh
# about, §4.1). [reviewer Important-2, CP-10, fix round 1]: every gate INPUT must read the commit
# being released, not whatever the working tree holds right now.
_PG_DISP_DIR=""
_prov_disp_file() {
  if [ -z "${RELEASE_SHA:-}" ]; then
    printf '%s\n' "$GATE_DISP_FILE"   # unpinned (direct-call selftest case) — read the working tree
    return 0
  fi
  if git cat-file -e "${RELEASE_SHA}:${GATE_DISP_FILE}" 2>/dev/null; then
    git show "${RELEASE_SHA}:${GATE_DISP_FILE}" > "$_PG_DISP_DIR/gate-dispositions.txt" 2>/dev/null
    printf '%s\n' "$_PG_DISP_DIR/gate-dispositions.txt"
  else
    printf '%s\n' "$_PG_DISP_DIR/absent-at-release-sha.txt"   # never written -> ci-gates.sh reports absent
  fi
}

# _prov_dockerfile_present -> 0 if the pinned RELEASE_SHA (or the working tree when RELEASE_SHA is
# unset — direct-call selftest case) has a Dockerfile. [reviewer Important-2, CP-10, fix round 1]:
# same pinning rule as the disposition read above — the ASSERTION SET must not read a moving
# working tree (measured defect: a Dockerfile added to the tree AFTER the sha was pinned must stay
# invisible to this gate).
_prov_dockerfile_present() {
  if [ -n "${RELEASE_SHA:-}" ]; then
    git cat-file -e "${RELEASE_SHA}:Dockerfile" 2>/dev/null
  else
    [ -f Dockerfile ]
  fi
}

# _prov_disposition <gate-id> -> apply|na|absent (single-sourced via ci-gates.sh --disposition,
# against the PINNED disposition content; an unreadable ci-gates.sh itself fails safe to apply,
# matching that mode's own fail-safe direction). [security LOW-4, fix round 1]: no `2>/dev/null`
# here — an invalid-file WARN from ci-gates.sh must reach release-tag's own stderr, never be
# silently swallowed (command substitution only ever captures stdout, so this is safe to drop).
_prov_disposition() {
  _pd_file=$(_prov_disp_file)
  if [ -f "$CI_GATES" ]; then
    sh "$CI_GATES" --disposition "$1" "$_pd_file" || echo apply
  else
    echo apply
  fi
}

# _prov_reason <gate-id> -> the disposition reason for <gate-id> in the PINNED disposition content
# (empty if none / file absent / no matching line). Same pinning as _prov_disposition.
_prov_reason() {
  _pd_file=$(_prov_disp_file)
  awk -F'\t' -v id="$1" '!/^[[:space:]]*#/ && $1==id && NF>=3 {print $3}' "$_pd_file" 2>/dev/null | head -1
}

# _strip_ctrl <string> -> the string with control characters removed. [security LOW-3, fix round 1]:
# a disposition REASON is free text from a file this script does not own the review of; echoing it
# verbatim can carry terminal escape sequences (cursor moves, title-bar spoofing) into an operator's
# terminal. Applied wherever a reason crosses into an echoed message (here; inception-done.sh's own
# repo-class leg applies the same filter inline for its own echoed reason).
_strip_ctrl() {
  printf '%s' "$1" | tr -d '[:cntrl:]'
}

# provenance_gate -> 0 = proceed (pass / observe-mode LOUD / degrade-open / na-excused) · 1 = refuse
# (enforce LOUD). Dial: RELEASE_TAG_PROVENANCE=observe|enforce, default observe (§3 Δ2 — the
# D-240807-1 enforce-at-birth bar is not met; this is a one-time wild measurement, not a
# 3x-recurring kit-process failure).
#
# VERDICT PRECEDENCE [owner-adjudicated, fix round 1]: success -> quiet pass · skipped + validated
# na -> exactly one N/A-with-reason line, tag proceeds in BOTH modes (na excuses only NOT-RUNNING
# states, never a job that ran and did not conclude success) · skipped + apply/no-disposition ->
# LOUD · ANY OTHER CONCLUSION (failure, empty, an ambiguous/duplicate match) -> LOUD REGARDLESS OF
# DISPOSITION [security MED-2 + the owner's sharpening].
provenance_gate() {
  # _PG_DISP_DIR is created HERE, once, in provenance_gate's OWN execution frame — never inside
  # _prov_disp_file itself. [root cause, fix round 1 debugging] _prov_disp_file is reached only via
  # nested command substitutions (`_pg_disp=$(_prov_disposition ...)` -> `_pd_file=$(_prov_disp_file)`),
  # each of which forks its OWN subshell; a `trap ... EXIT` registered inside one of those inner
  # subshells fires the instant THAT subshell finishes computing its value — i.e. before the outer
  # caller ever reads the path — deleting the temp file out from under itself (measured: git show
  # wrote the file, `ls` inside the same call proved it existed, and it was gone one line later in
  # the caller). Creating it here means the ONLY subshell boundary the trap's lifetime depends on is
  # provenance_gate's own — which does not exit until every disposition/reason read below is done.
  _PG_DISP_DIR=""
  if [ -n "${RELEASE_SHA:-}" ]; then
    _PG_DISP_DIR=$(mktemp -d)
    # Cleanup on EXIT; the signal arms stay TERMINAL (exit so the EXIT trap fires) — a handler
    # that only cleans up would swallow an operator abort and let the tag proceed (seat-caught).
    trap 'rm -rf "$_PG_DISP_DIR"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
  fi
  _pg_mode="${RELEASE_TAG_PROVENANCE:-observe}"
  _pg_mode_default=1
  if [ -n "${RELEASE_TAG_PROVENANCE+x}" ]; then
    _pg_mode_default=0
    case "$_pg_mode" in
      observe|enforce) : ;;
      *)
        # [security LOW-1, fix round 1] an unrecognized value must never silently pick a posture —
        # name it, name the accepted set, and stay OBSERVE (the safer of the two postures).
        echo "release-tag: WARNING — RELEASE_TAG_PROVENANCE='$_pg_mode' is not a recognized value (accepted: observe|enforce) — behavior stays OBSERVE." >&2
        _pg_mode=observe ;;
    esac
  fi
  _pg_probe=$(prov_probe)
  if [ -z "$_pg_probe" ]; then
    echo "release-tag: provenance probe returned no data (no gh / not GitHub / no run / no seam set) — proceeding (degrade-open, unverified; see this gate's SECURITY note)" >&2
    return 0
  fi
  _pg_loud=0
  _pg_assert="provenance"
  _prov_dockerfile_present && _pg_assert="$_pg_assert image-provenance"

  for _pg_job in $_pg_assert; do
    case "$_pg_job" in
      provenance) _pg_gid=gate-provenance ;;
      image-provenance) _pg_gid=gate-sbom ;;
    esac
    set +e; _pg_concl=$(_prov_conclusion "$_pg_job" "$_pg_probe"); _pg_crc=$?; set -e
    case "$_pg_crc" in
      0)
        case "$_pg_concl" in
          success) : ;;   # quiet pass
          skipped)
            _pg_disp=$(_prov_disposition "$_pg_gid")
            if [ "$_pg_disp" = na ]; then
              _pg_reason=$(_strip_ctrl "$(_prov_reason "$_pg_gid")")
              echo "release-tag: N/A ($_pg_gid) — CI job '$_pg_job' concluded skipped for ${RELEASE_SHA:-HEAD} and $_pg_gid is validated na (${_pg_reason:-reason on file}). Revisit if the repo becomes public/org-owned." >&2
            else
              echo "release-tag: LOUD — CI job '$_pg_job' concluded skipped for ${RELEASE_SHA:-HEAD} (disposition $_pg_gid: $_pg_disp). A provenance/image-provenance gate that never ran must not pass silently. Cure: make the repo public / move it to a GitHub org, OR record a dated na disposition in $GATE_DISP_FILE, OR set RELEASE_TAG_PROV_PROBE for your forge." >&2
              _pg_loud=1
            fi ;;
          *)
            # [owner adjudication + security MED-2, fix round 1] any OTHER conclusion (failure,
            # empty, or an ambiguous value that slipped past rc 2 below) is LOUD regardless of
            # disposition — na excuses only a job that did NOT run, never one that ran and did not
            # conclude success.
            echo "release-tag: LOUD — CI job '$_pg_job' concluded '${_pg_concl:-<empty>}' for ${RELEASE_SHA:-HEAD} — not success, not skipped. A gate whose job RAN and did not conclude success is never excused by a disposition. Cure: fix the pipeline / re-run CI for this SHA." >&2
            _pg_loud=1 ;;
        esac ;;
      2)
        echo "release-tag: LOUD — CI job '$_pg_job' appears MORE THAN ONCE in the provenance probe for ${RELEASE_SHA:-HEAD} (ambiguous conclusion) — LOUD regardless of disposition. Cure: fix the probe/seam to report each job exactly once." >&2
        _pg_loud=1 ;;
      *)
        # job absent from the run entirely
        _pg_disp=$(_prov_disposition "$_pg_gid")
        case "$_pg_disp" in
          na) echo "release-tag: N/A ($_pg_gid) — '$_pg_job' is not in this run and $_pg_gid is validated na in $GATE_DISP_FILE." >&2 ;;
          *)
            echo "release-tag: LOUD — CI job '$_pg_job' is ABSENT from the run for ${RELEASE_SHA:-HEAD} and $_pg_gid has no na disposition (got: $_pg_disp). Cure: restore the job, OR record a dated na disposition in $GATE_DISP_FILE." >&2
            _pg_loud=1 ;;
        esac ;;
    esac
  done

  if [ "$_pg_loud" = 1 ]; then
    if [ "$_pg_mode" = enforce ]; then
      echo "release-tag: REFUSING to tag — provenance gate LOUD under RELEASE_TAG_PROVENANCE=enforce." >&2
      return 1
    fi
    _pg_suffix=""
    [ "$_pg_mode_default" = 1 ] && _pg_suffix=" (default)"
    echo "release-tag: provenance gate is OBSERVE mode$_pg_suffix — the tag proceeds despite the LOUD verdict above; flip RELEASE_TAG_PROVENANCE=enforce to refuse (tracked: PHASE-B-DIAL-FLIP)." >&2
  fi
  return 0
}

run() {
  # PIN THE RELEASE COMMIT, ONCE, BEFORE ANYTHING SLOW RUNS. Every downstream step uses $RELEASE_SHA;
  # none re-reads HEAD. This is what makes the ceremony safe to run in the background: HEAD may move,
  # the release cannot.
  RELEASE_SHA=$(git rev-parse HEAD 2>/dev/null) || { echo "release-tag: cannot resolve HEAD" >&2; return 2; }

  out=$(decide) || return $?
  v=${out#TAG }
  case "$out" in
    NOOP*) echo "release-tag: $out"; return 0 ;;
    TAG*) : ;;
    *) echo "release-tag: unexpected decision: $out" >&2; return 2 ;;
  esac
  if [ "${1:-}" = "--dry-run" ]; then
    echo "release-tag: would create + push $v on $(git rev-parse --short "$RELEASE_SHA")"; return 0
  fi
  # H1: is the CADENCE alive? (cadence_gate)  ...CP-10: is it SHIPPED? (branch_gate)  ...is it GREEN? (ci_gate)
  # Ordered cheap-first on purpose: cadence + branch are local reads, so we do not spend a 10-minute
  # CI poll only to reject the commit afterwards.
  cadence_gate || return 1
  branch_gate "$RELEASE_SHA" || return 1
  ci_gate || return 1
  provenance_gate || return 1
  # Tag the PINNED sha explicitly — never a bare `git tag "$v"`, which re-reads HEAD at this instant.
  git tag "$v" "$RELEASE_SHA"
  if git push "$REMOTE" "$v"; then
    echo "release-tag: created + pushed $v"; return 0
  fi
  # push failed: a concurrent run may have pushed it (race) — that's fine; otherwise the local
  # tag is a poison pill (a future run would NOOP green with no remote tag), so roll it back + fail.
  git tag -d "$v" >/dev/null 2>&1 || true
  if on_remote "$v"; then
    echo "release-tag: $v already on remote (concurrent run) — ok"; return 0
  fi
  echo "release-tag: push of $v failed and it is NOT on the remote — rolled back local tag" >&2
  return 1
}

selftest() {
  st=0; t=$(mktemp -d)
  # _repo creates a single-commit repo with the given VERSION. Does NOT tag it.
  _repo() { mkdir -p "$1"; printf '%s\n' "$2" > "$1/VERSION"
    ( cd "$1" && git init -q && git -c user.email=c@k -c user.name=c add -A \
      && git -c user.email=c@k -c user.name=c commit -q -m s ) >/dev/null 2>&1; }
  _dry() { ( cd "$1" && sh "$here/release-tag.sh" --dry-run ) 2>/dev/null; }
  # _rc captures the exit code safely under set -eu (nonzero subshell would otherwise
  # trigger set -e exit before "echo $?" runs).
  _rc()  { _x=0; ( cd "$1" && sh "$here/release-tag.sh" --dry-run ) >/dev/null 2>&1 || _x=$?; echo $_x; }
  # A. VERSION ahead of reachable tag, v<VERSION> absent -> TAG
  # Two commits: v1.0.0 tagged on first commit, HEAD is second commit with VERSION=1.1.0.
  # (Single-commit setup fails: tagging v1.0.0 on HEAD with VERSION=1.1.0 violates coherence.)
  d="$t/a"
  ( mkdir -p "$d" && cd "$d" \
    && git init -q \
    && printf '1.0.0\n' > VERSION \
    && git -c user.email=c@k -c user.name=c add -A \
    && git -c user.email=c@k -c user.name=c commit -q -m s1 \
    && git tag v1.0.0 \
    && printf '1.1.0\n' > VERSION \
    && git -c user.email=c@k -c user.name=c add -A \
    && git -c user.email=c@k -c user.name=c commit -q -m s2 ) >/dev/null 2>&1
  case "$(_dry "$d")" in *"would create + push v1.1.0"*) echo "PASS: new version -> TAG";; *) echo "FAIL: A"; st=1;; esac
  # B. v<VERSION> already exists -> NOOP
  d="$t/b"; _repo "$d" "1.0.0"; ( cd "$d" && git tag v1.0.0 ) >/dev/null 2>&1
  case "$(_dry "$d")" in *"NOOP v1.0.0 already tagged"*) echo "PASS: existing tag -> NOOP";; *) echo "FAIL: B"; st=1;; esac
  # C. VERSION BEHIND a reachable tag -> coherence fail (rc 1), no tag
  d="$t/c"; _repo "$d" "1.0.0"; ( cd "$d" && git tag v2.0.0 ) >/dev/null 2>&1
  [ "$(_rc "$d")" = "1" ] && echo "PASS: VERSION behind tag -> rc 1" || { echo "FAIL: C"; st=1; }
  # D. non-semver VERSION -> rc 2
  d="$t/d"; _repo "$d" "not-a-version"
  [ "$(_rc "$d")" = "2" ] && echo "PASS: non-semver -> rc 2" || { echo "FAIL: D"; st=1; }
  # --- tag-time CI gate (injected probe, no network) ---
  _gate_rc() { _x=0; ( RELEASE_TAG_CI_PROBE="$1" RELEASE_TAG_CI_TIMEOUT="${2:-0}" RELEASE_TAG_CI_INTERVAL=1; ci_gate ) >/dev/null 2>&1 || _x=$?; echo $_x; }
  # E (teeth): definitive failure -> refuse (rc 1)
  [ "$(_gate_rc 'printf "completed\tfailure\n"')" = "1" ] && echo "PASS: CI failure -> refuse tag" || { echo "FAIL: E (CI-gate failure not refused)"; st=1; }
  # F: success -> proceed (rc 0)
  [ "$(_gate_rc 'printf "completed\tsuccess\n"')" = "0" ] && echo "PASS: CI success -> proceed" || { echo "FAIL: F"; st=1; }
  # G: in-progress + timeout 0 -> degrade-open proceed (rc 0)
  [ "$(_gate_rc 'printf "in_progress\t\n"' 0)" = "0" ] && echo "PASS: CI in-progress timeout -> proceed (degrade-open)" || { echo "FAIL: G"; st=1; }
  # H: no CI signal (empty probe) -> degrade-open proceed (rc 0)
  [ "$(_gate_rc 'true')" = "0" ] && echo "PASS: no CI signal -> proceed (degrade-open)" || { echo "FAIL: H"; st=1; }

  # ===== CP-10 — the on-branch gate (a release tag must point at a RELEASED commit) ==========
  # ci_gate asks "is it GREEN?". branch_gate asks "is it SHIPPED?". Those are different questions, and
  # nothing asked the second one until v3.129.0 landed on an unmerged branch.
  #
  # _wt <dir>: a work repo with a real bare remote, main checked out, origin/HEAD set.
  _wt() {
    ( git init -q --bare "$1/origin.git"
      git clone -q "$1/origin.git" "$1/w"
      cd "$1/w"
      printf '1.0.0\n' > VERSION
      git -c user.email=c@k -c user.name=c add -A
      git -c user.email=c@k -c user.name=c commit -q -m s1
      git tag v1.0.0
      printf '1.1.0\n' > VERSION
      git -c user.email=c@k -c user.name=c add -A
      git -c user.email=c@k -c user.name=c commit -q -m s2
      git push -q origin HEAD:main
      git push -q origin v1.0.0
      git remote set-head origin main ) >/dev/null 2>&1
  }
  _bg_rc() { _x=0; ( cd "$1" && RELEASE_SHA=$(git rev-parse "$2"); branch_gate "$RELEASE_SHA" ) >/dev/null 2>&1 || _x=$?; echo $_x; }

  # ===== H1 (PHASE-B-HYGIENE) — cadence fixtures: every end-to-end leg pins a HERMETIC cadence =====
  # The cadence gate shells the real detector, and the detector's default ROOT is the surrounding
  # repo — so an end-to-end leg WITHOUT a pinned META_CONTROL_ROOT would silently assert the KIT'S
  # OWN live freshness verdict, which is exactly the property meta-control-fresh.sh's selftest
  # refuses to assert (a legitimately-ESCALATED kit would red these unrelated legs). Fixtures are
  # hermetic by construction: each leg names its own ROOT + META_CONTROL_TAGS.
  _cadfix() { # <dir> — a kit-marked meta-control ROOT (marker 1.0.0 GO, log synced); verdict forced via META_CONTROL_TAGS
    mkdir -p "$1/docs/governance"
    : > "$1/docs/ROADMAP-KIT.md"
    printf '99.99.99\n' > "$1/VERSION"
    printf '1.0.0 GO\n' > "$1/docs/governance/.meta-control-last"
    { printf '| Date | Version | Trigger | Profile | Verdict | Artifact | Ledger |\n'
      printf '|---|---|---|---|---|---|---|\n'
      printf '| 2026-01-01 | 1.0.0 | t | light | GO | a | s |\n'
    } > "$1/docs/governance/meta-control-log.md"
  }
  _cadfix "$t/cad"   # with META_CONTROL_TAGS=1.0.0: 0 newer tags => FRESH
  # invalid-state fixture: cadence adopted (log present) but the marker file is MISSING => detector
  # rc 1 with NO ^OVERDUE:/^ESCALATED: token — the marker-desync/broken-record face.
  _cadfix "$t/cadbad"; rm -f "$t/cadbad/docs/governance/.meta-control-last"
  _capfix() { # <dir> — serial-defer-capped ROOT: marker 1.0.0 DEFERRED + two trailing DEFERRED rows
    mkdir -p "$1/docs/governance"
    : > "$1/docs/ROADMAP-KIT.md"
    printf '99.99.99\n' > "$1/VERSION"
    printf '1.0.0 DEFERRED\n' > "$1/docs/governance/.meta-control-last"
    { printf '| Date | Version | Trigger | Profile | Verdict | Artifact | Ledger |\n'
      printf '|---|---|---|---|---|---|---|\n'
      printf '| 2026-01-01 | 0.9.0 | t | l | DEFERRED | a | s |\n'
      printf '| 2026-01-02 | 1.0.0 | t | l | DEFERRED | a | s |\n'
    } > "$1/docs/governance/meta-control-log.md"
  }

  # I (TEETH — the whole point): a commit NOT on the default branch must be REFUSED, and NO TAG WRITTEN.
  #
  # ★ THIS TEST DRIVES THE REAL SCRIPT END-TO-END, NOT branch_gate DIRECTLY — and that distinction is
  # load-bearing. An earlier draft called branch_gate() directly. It proved the FUNCTION worked but not
  # that run() CALLED it: deleting the `branch_gate "$RELEASE_SHA"` line from run() left the selftest
  # GREEN. A vacuous test — it verified the artifact I wrote, not the property I wanted. Caught by
  # mutation. Assert on the OBSERVABLE OUTCOME (rc != 0 AND no tag exists), which no wiring bug survives.
  d="$t/i"; mkdir -p "$d"; _wt "$d"
  ( cd "$d/w" && git checkout -q -b feature/unmerged \
    && printf 'x\n' > f.txt \
    && git -c user.email=c@k -c user.name=c add -A \
    && git -c user.email=c@k -c user.name=c commit -q -m unmerged \
    && printf '1.2.0\n' > VERSION \
    && git -c user.email=c@k -c user.name=c add -A \
    && git -c user.email=c@k -c user.name=c commit -q -m bump ) >/dev/null 2>&1
  _irc=0
  ( cd "$d/w" && META_CONTROL_ROOT="$t/cad" META_CONTROL_TAGS=1.0.0 RELEASE_TAG_CI_PROBE='printf "completed\tsuccess\n"' sh "$here/release-tag.sh" ) >/dev/null 2>&1 || _irc=$?
  _itag=$( cd "$d/w" && git tag -l v1.2.0 )
  if [ "$_irc" != "0" ] && [ -z "$_itag" ]; then
    echo "PASS: an UNMERGED commit -> REFUSED, no tag written (the v3.129.0 defect)"
  else
    echo "FAIL: I — an unmerged commit was tagged (rc=$_irc tag='$_itag')"; st=1
  fi

  # J (LIVENESS — the anchor): a commit ON the default branch must be ACCEPTED, and the tag WRITTEN.
  # Without this, a gate that refuses EVERYTHING would pass test I and be worse than useless.
  # Also end-to-end, for the same reason. DOUBLES as the cadence gate's pass-on-FRESH anchor (H1):
  # the pinned fixture verdict is FRESH, so a cadence gate that refuses FRESH would red this leg.
  d="$t/j"; mkdir -p "$d"; _wt "$d"
  _jrc=0
  ( cd "$d/w" && META_CONTROL_ROOT="$t/cad" META_CONTROL_TAGS=1.0.0 RELEASE_TAG_CI_PROBE='printf "completed\tsuccess\n"' sh "$here/release-tag.sh" ) >/dev/null 2>&1 || _jrc=$?
  _jtag=$( cd "$d/w" && git tag -l v1.1.0 )
  if [ "$_jrc" = "0" ] && [ -n "$_jtag" ]; then
    echo "PASS: a RELEASED commit (on origin/main) + FRESH cadence -> tagged (pass-on-FRESH anchor)"
  else
    echo "FAIL: J — a released commit was refused (rc=$_jrc tag='$_jtag') — the gate refuses everything"; st=1
  fi

  # K: no resolvable default branch -> DEGRADE OPEN (rc 0), loudly. A forge-neutral kit must not become
  # untaggable on a host it cannot introspect. The ceiling is stated, not silent.
  d="$t/k"; _repo "$d" "1.1.0"     # a plain repo: no remote at all
  [ "$(_bg_rc "$d" HEAD)" = "0" ] \
    && echo "PASS: unresolvable default branch -> degrade-open (forge-neutral)" \
    || { echo "FAIL: K — degraded CLOSED; the kit is untaggable without a resolvable remote"; st=1; }

  # ===== CP-10 — the HEAD race (the mechanism that caused the defect) =======================
  # L (TEETH): HEAD moving DURING the CI poll must not change which commit gets tagged.
  # We reproduce the real bug: the CI probe (which runs inside ci_gate, mid-poll) commits a new commit,
  # moving HEAD — precisely what an unrelated `checkout -b` + `commit` did on 2026-07-13. The tag MUST
  # still land on the sha pinned at invocation. Before the fix, `git tag "$v"` tagged the NEW HEAD.
  d="$t/l"; mkdir -p "$d"; _wt "$d"
  _orig=$( cd "$d/w" && git rev-parse HEAD )
  _probe='printf "completed\tsuccess\n"; git -c user.email=c@k -c user.name=c commit -q --allow-empty -m "HEAD MOVED mid-poll" >/dev/null 2>&1'
  ( cd "$d/w" && META_CONTROL_ROOT="$t/cad" META_CONTROL_TAGS=1.0.0 RELEASE_TAG_CI_PROBE="$_probe" sh "$here/release-tag.sh" ) >/dev/null 2>&1 || true
  _tagged=$( cd "$d/w" && git rev-list -n1 v1.1.0 2>/dev/null || true )
  _now=$( cd "$d/w" && git rev-parse HEAD )
  if [ "$_tagged" = "$_orig" ] && [ "$_orig" != "$_now" ]; then
    echo "PASS: HEAD moved mid-poll; the tag stayed on the PINNED sha (race closed)"
  else
    echo "FAIL: L — the tag followed a moving HEAD (tagged=$_tagged orig=$_orig head=$_now)"; st=1
  fi

  # ===== H1 (PHASE-B-HYGIENE) — the cadence gate (refuse-on-ESCALATED / refuse-on-invalid-state) ==
  # End-to-end THROUGH run(), never cadence_gate directly — the same load-bearing distinction test I
  # records: a direct function call proves the FUNCTION, not that run() CALLS it (deleting the call
  # would leave a direct-call leg GREEN — the exact mutant the hand-built kill evidence exercises).
  # M (TEETH): an ESCALATED cadence (>2N tags past the marker) -> REFUSED, and NO TAG WRITTEN.
  d="$t/mm"; mkdir -p "$d"; _wt "$d"
  _mrc=0
  _mout=$( cd "$d/w" && META_CONTROL_ROOT="$t/cad" \
      META_CONTROL_TAGS='1.0.0 1.0.1 1.0.2 1.0.3 1.0.4 1.0.5 1.0.6 1.0.7 1.0.8 1.0.9 1.0.10 1.0.11' \
      RELEASE_TAG_CI_PROBE='printf "completed\tsuccess\n"' sh "$here/release-tag.sh" 2>&1 ) || _mrc=$?
  _mtag=$( cd "$d/w" && git tag -l v1.1.0 )
  if [ "$_mrc" != "0" ] && [ -z "$_mtag" ]; then
    echo "PASS: ESCALATED cadence -> REFUSED, no tag written (the release-over-dead-cadence defect)"
  else
    echo "FAIL: M — an ESCALATED cadence was tagged over (rc=$_mrc tag='$_mtag')"; st=1
  fi
  # M-banner (F2): this leg runs under META_CONTROL_* overrides, so the override banner MUST have
  # printed — a silent overridden run is the de-escalation the security seat measured.
  if printf '%s\n' "$_mout" | grep -q 'OVERRIDDEN ENVIRONMENT'; then
    echo "PASS: env-override run printed the OVERRIDDEN ENVIRONMENT banner (F2 loud-not-silent)"
  else
    echo "FAIL: M-banner — an env-overridden run stayed SILENT about the override"; st=1
  fi
  # O (FAIL-CLOSED): detector rc 1 with NO OVERDUE/ESCALATED token (marker missing => invalid state)
  # -> REFUSED. A cadence gate that degrades open on a broken cadence RECORD is satisfiable by
  # breaking the record; this leg pins the fail-closed face.
  d="$t/o"; mkdir -p "$d"; _wt "$d"
  _orc=0
  ( cd "$d/w" && META_CONTROL_ROOT="$t/cadbad" META_CONTROL_TAGS=1.0.0 \
      RELEASE_TAG_CI_PROBE='printf "completed\tsuccess\n"' sh "$here/release-tag.sh" ) >/dev/null 2>&1 || _orc=$?
  _otag=$( cd "$d/w" && git tag -l v1.1.0 )
  if [ "$_orc" != "0" ] && [ -z "$_otag" ]; then
    echo "PASS: invalid cadence state (broken record) -> REFUSED, fail-closed"
  else
    echo "FAIL: O — a broken cadence record degraded OPEN (rc=$_orc tag='$_otag')"; st=1
  fi
  # P (M2 TOKEN-CONTRACT): an adversarial/broken detector that prints ^ESCALATED: but exits 0 must
  # still be REFUSED — the token is the contract, not the rc (the reviewer's measured attack: before
  # this check, rc 0 short-circuited past the token and the tag proceeded).
  d="$t/p"; mkdir -p "$d"; _wt "$d"
  printf '#!/bin/sh\necho "ESCALATED: 99 release tags since the last addressed meta-control panel (fixture)."\nexit 0\n' > "$t/esc-rc0.sh"
  _prc=0
  ( cd "$d/w" && RELEASE_TAG_CADENCE="$t/esc-rc0.sh" \
      RELEASE_TAG_CI_PROBE='printf "completed\tsuccess\n"' sh "$here/release-tag.sh" ) >/dev/null 2>&1 || _prc=$?
  _ptag=$( cd "$d/w" && git tag -l v1.1.0 )
  if [ "$_prc" != "0" ] && [ -z "$_ptag" ]; then
    echo "PASS: detector prints ESCALATED but exits 0 -> still REFUSED (token contract, M2)"
  else
    echo "FAIL: P — an ESCALATED-printing rc-0 detector was tagged over (rc=$_prc tag='$_ptag')"; st=1
  fi
  # Q (reviewer 6): the CAP-FIRED OVERDUE face — the tag PROCEEDS (advisory, unchanged) but the
  # warning must name the cap's remedy (a REAL run) and must NOT print the count-band "past 2N"
  # text, which is wrong when the count may be 0.
  _capfix "$t/cap"
  d="$t/qq"; mkdir -p "$d"; _wt "$d"
  _qrc=0
  _qout=$( cd "$d/w" && META_CONTROL_ROOT="$t/cap" META_CONTROL_TAGS=1.0.0 \
      RELEASE_TAG_CI_PROBE='printf "completed\tsuccess\n"' sh "$here/release-tag.sh" 2>&1 ) || _qrc=$?
  _qtag=$( cd "$d/w" && git tag -l v1.1.0 )
  if [ "$_qrc" = "0" ] && [ -n "$_qtag" ] \
     && printf '%s\n' "$_qout" | grep -q 'serial-deferral cap' \
     && ! printf '%s\n' "$_qout" | grep -q 'past 2N tags this ESCALATES'; then
    echo "PASS: cap-fired OVERDUE -> proceeds with the cap-face warning (real-run remedy, no count-band text)"
  else
    echo "FAIL: Q — the cap-fired OVERDUE face is wrong (rc=$_qrc tag='$_qtag')"; st=1
  fi

  # ===== B8 (GATE-PROVENANCE-SELF-DISABLES-AND-NEVER-GATES-THE-MERGE, PHASE-B-SPINE) ============
  # provenance_gate: ci_gate reads only the WORKFLOW-level conclusion, which is blind to a per-job
  # SKIP — measured live on a private user-owned adopter (codex-pulse-6, run 29929763014): job
  # `provenance` and `image-provenance` -> skipped, workflow -> success, and ci_gate proceeded
  # silently. This gate reads per-JOB conclusions for the pinned RELEASE_SHA and distinguishes a
  # legitimate skip (a validated na disposition, or image-provenance absent for a Dockerfile-less
  # tree) from the disease (a declared/undecided gate that never ran).
  #
  # VERDICT PRECEDENCE (fix round 1, owner-adjudicated): success -> quiet pass · skipped + validated
  # na -> exactly one N/A line, proceeds in BOTH modes (na excuses only "did not run", never "ran and
  # did not pass") · skipped + apply/no-disposition -> LOUD · ANY OTHER CONCLUSION (failure, empty,
  # an ambiguous/duplicate match) -> LOUD REGARDLESS OF DISPOSITION [security MED-2].
  #
  # _pg_mk <dir> <dockerfile:0|1> <gp-kind> <gp-reason> <gs-kind> <gs-reason> — a REAL one-commit git
  # repo (Dockerfile optional, a full valid 8-id gate-dispositions.txt always present), COMMITTED, so
  # RELEASE_SHA can be pinned to a real git object [fix round 1, reviewer Important-2 / CP-10: gate
  # INPUTS — the Dockerfile probe, the disposition-file read — must read the commit being released,
  # not a bare directory + an unresolvable fake sha string]. `return 0` is load-bearing under
  # `set -eu`: without it, dockerfile=0 (the trailing `[ ... ] && :` evaluating false) makes the
  # function's own exit status nonzero, and a bare (unguarded) statement call then aborts the whole
  # selftest silently at that line.
  _pg_mk() {
    mkdir -p "$1/conformance"
    [ "${2:-0}" = 1 ] && : > "$1/Dockerfile"
    { printf 'gate-lint\tapply\tx\n'; printf 'gate-type-check\tapply\tx\n'; printf 'gate-test\tapply\tx\n'
      printf 'gate-build\tapply\tx\n'; printf 'gate-secret-scan\tapply\tx\n'; printf 'gate-dep-scan\tapply\tx\n'
      printf 'gate-provenance\t%s\t%s\n' "${3:-apply}" "${4:-n/a}"
      printf 'gate-sbom\t%s\t%s\n' "${5:-apply}" "${6:-n/a}"
    } > "$1/conformance/gate-dispositions.txt"
    ( cd "$1" && git init -q && git -c user.email=c@k -c user.name=c add -A \
      && git -c user.email=c@k -c user.name=c commit -q -m s ) >/dev/null 2>&1
    return 0
  }

  # PG1 (LIVENESS): both jobs conclude success, Dockerfile present (asserts both gates) -> quiet pass.
  d="$t/pg1"; _pg_mk "$d" 1 apply n/a apply n/a
  _pgrc=0
  _pgout=$( cd "$d"; RELEASE_SHA=$(git rev-parse HEAD); RELEASE_TAG_PROV_PROBE='printf "provenance\tsuccess\nimage-provenance\tsuccess\n"'; RELEASE_TAG_PROVENANCE=observe; provenance_gate 2>&1 ) || _pgrc=$?
  if [ "$_pgrc" = 0 ] && [ -z "$_pgout" ]; then
    echo "PASS: provenance_gate — both jobs conclude success -> quiet pass"
  else
    echo "FAIL: PG1 (rc=$_pgrc out='$_pgout')"; st=1
  fi

  # PG2 (TEETH, the whole point): a SKIPPED job + apply/undecided disposition — observe proceeds
  # with a LOUD banner, enforce refuses. Also anchors the default-vs-explicit-mode banner text
  # [security LOW-1]: the UNSET (default) run must say "(default)"; an EXPLICITLY-set run must not.
  d="$t/pg2"; _pg_mk "$d" 0 apply n/a apply n/a
  _pgrc=0
  _pgout=$( cd "$d"; RELEASE_SHA=$(git rev-parse HEAD); RELEASE_TAG_PROV_PROBE='printf "provenance\tskipped\n"'; RELEASE_TAG_PROVENANCE=observe; provenance_gate 2>&1 ) || _pgrc=$?
  if [ "$_pgrc" = 0 ] && printf '%s' "$_pgout" | grep -q LOUD; then
    echo "PASS: provenance_gate — skipped job in OBSERVE -> proceeds with a LOUD banner"
  else
    echo "FAIL: PG2-observe (rc=$_pgrc out='$_pgout')"; st=1
  fi
  _pgrc=0
  _pgout=$( cd "$d"; RELEASE_SHA=$(git rev-parse HEAD); RELEASE_TAG_PROV_PROBE='printf "provenance\tskipped\n"'; provenance_gate 2>&1 ) || _pgrc=$?
  if [ "$_pgrc" = 0 ] && printf '%s' "$_pgout" | grep -q "OBSERVE mode (default)"; then
    echo "PASS: provenance_gate — the UNSET (default) dial banners '(default)' [security LOW-1]"
  else
    echo "FAIL: PG2-default-banner (rc=$_pgrc out='$_pgout')"; st=1
  fi
  _pgrc=0
  _pgout=$( cd "$d"; RELEASE_SHA=$(git rev-parse HEAD); RELEASE_TAG_PROV_PROBE='printf "provenance\tskipped\n"'; RELEASE_TAG_PROVENANCE=observe; provenance_gate 2>&1 ) || _pgrc=$?
  if [ "$_pgrc" = 0 ] && printf '%s' "$_pgout" | grep -q LOUD && ! printf '%s' "$_pgout" | grep -q "(default)"; then
    echo "PASS: provenance_gate — RELEASE_TAG_PROVENANCE=observe set EXPLICITLY drops the '(default)' suffix [security LOW-1]"
  else
    echo "FAIL: PG2-explicit-banner (rc=$_pgrc out='$_pgout')"; st=1
  fi
  _pgrc=0
  _pgout=$( cd "$d"; RELEASE_SHA=$(git rev-parse HEAD); RELEASE_TAG_PROV_PROBE='printf "provenance\tskipped\n"'; RELEASE_TAG_PROVENANCE=enforce; provenance_gate 2>&1 ) || _pgrc=$?
  if [ "$_pgrc" = 1 ] && printf '%s' "$_pgout" | grep -q REFUSING; then
    echo "PASS: provenance_gate — skipped job in ENFORCE -> refuses (rc 1)"
  else
    echo "FAIL: PG2-enforce (rc=$_pgrc out='$_pgout')"; st=1
  fi

  # PG-SKIP-NA (owner-adjudicated, fix round 1 — the design contradiction's resolution): a SKIPPED
  # job whose gate is a VALIDATED na disposition -> exactly one N/A-with-reason line, and the tag
  # PROCEEDS IN BOTH MODES (na excuses only a job that did not run, not a job that ran and failed).
  d="$t/pgskipna"; _pg_mk "$d" 0 na "no attestable image on a private repo" apply n/a
  _pgrc=0
  _pgout=$( cd "$d"; RELEASE_SHA=$(git rev-parse HEAD); RELEASE_TAG_PROV_PROBE='printf "provenance\tskipped\n"'; RELEASE_TAG_PROVENANCE=enforce; provenance_gate 2>&1 ) || _pgrc=$?
  _pglines=$(printf '%s\n' "$_pgout" | grep -c "N/A" || true)
  if [ "$_pgrc" = 0 ] && [ "$_pglines" = 1 ] && ! printf '%s' "$_pgout" | grep -q LOUD; then
    echo "PASS: provenance_gate — skipped + validated na -> exactly one N/A line, tag proceeds even under ENFORCE (owner adjudication)"
  else
    echo "FAIL: PG-SKIP-NA (rc=$_pgrc lines=$_pglines out='$_pgout')"; st=1
  fi

  # PG-FAILURE-NA (security MED-2, closed): a FAILURE conclusion is LOUD/refused EVEN WITH a
  # validated na disposition on file — na excuses "did not run", never "ran and did not pass".
  d="$t/pgfailna"; _pg_mk "$d" 0 na "reason on file" apply n/a
  _pgrc=0
  _pgout=$( cd "$d"; RELEASE_SHA=$(git rev-parse HEAD); RELEASE_TAG_PROV_PROBE='printf "provenance\tfailure\n"'; RELEASE_TAG_PROVENANCE=enforce; provenance_gate 2>&1 ) || _pgrc=$?
  if [ "$_pgrc" = 1 ] && printf '%s' "$_pgout" | grep -q LOUD && ! printf '%s' "$_pgout" | grep -q "N/A"; then
    echo "PASS: provenance_gate — a FAILURE conclusion is LOUD/refused despite a validated na disposition (the failure-band is never excused)"
  else
    echo "FAIL: PG-FAILURE-NA (rc=$_pgrc out='$_pgout')"; st=1
  fi

  # PG-DUP (reviewer Important-1's 'first detect, then verdict'): a job name appearing MORE THAN
  # ONCE in the probe is ambiguous and must be LOUD, never a multi-line value silently falling
  # through the `*` catch-all.
  d="$t/pgdup"; _pg_mk "$d" 0 apply n/a apply n/a
  _pgrc=0
  _pgout=$( cd "$d"; RELEASE_SHA=$(git rev-parse HEAD); RELEASE_TAG_PROV_PROBE='printf "provenance\tsuccess\nprovenance\tsuccess\n"'; RELEASE_TAG_PROVENANCE=enforce; provenance_gate 2>&1 ) || _pgrc=$?
  if [ "$_pgrc" = 1 ] && printf '%s' "$_pgout" | grep -q "MORE THAN ONCE"; then
    echo "PASS: provenance_gate — a duplicate 'provenance' line in the probe -> LOUD/refused (ambiguous conclusion never silently picked)"
  else
    echo "FAIL: PG-DUP (rc=$_pgrc out='$_pgout')"; st=1
  fi

  # PG-EMPTY: an empty conclusion (job present, no verdict yet) is LOUD, not a silent proceed.
  d="$t/pgempty"; _pg_mk "$d" 0 apply n/a apply n/a
  _pgrc=0
  _pgout=$( cd "$d"; RELEASE_SHA=$(git rev-parse HEAD); RELEASE_TAG_PROV_PROBE='printf "provenance\t\n"'; RELEASE_TAG_PROVENANCE=enforce; provenance_gate 2>&1 ) || _pgrc=$?
  if [ "$_pgrc" = 1 ] && printf '%s' "$_pgout" | grep -q LOUD; then
    echo "PASS: provenance_gate — an EMPTY conclusion -> LOUD/refused"
  else
    echo "FAIL: PG-EMPTY (rc=$_pgrc out='$_pgout')"; st=1
  fi

  # PG3: job ABSENT from the run + apply/undecided disposition -> LOUD.
  d="$t/pg3"; _pg_mk "$d" 0 apply n/a apply n/a
  _pgrc=0
  _pgout=$( cd "$d"; RELEASE_SHA=$(git rev-parse HEAD); RELEASE_TAG_PROV_PROBE='printf "ci\tsuccess\n"'; RELEASE_TAG_PROVENANCE=observe; provenance_gate 2>&1 ) || _pgrc=$?
  if [ "$_pgrc" = 0 ] && printf '%s' "$_pgout" | grep -q LOUD && printf '%s' "$_pgout" | grep -q ABSENT; then
    echo "PASS: provenance_gate — job absent + apply disposition -> LOUD"
  else
    echo "FAIL: PG3 (rc=$_pgrc out='$_pgout')"; st=1
  fi

  # PG4: job ABSENT + a VALIDATED na disposition -> exactly one N/A-with-reason line, never LOUD.
  d="$t/pg4"; _pg_mk "$d" 0 na "nothing to attest" apply n/a
  _pgrc=0
  _pgout=$( cd "$d"; RELEASE_SHA=$(git rev-parse HEAD); RELEASE_TAG_PROV_PROBE='printf "ci\tsuccess\n"'; RELEASE_TAG_PROVENANCE=observe; provenance_gate 2>&1 ) || _pgrc=$?
  # [reviewer Minor-4, fix round 1]: grep -c returns rc 1 on zero matches, which would otherwise
  # abort this whole selftest under `set -eu` — guard with `|| true` so the printed count (0) survives.
  _pglines=$(printf '%s\n' "$_pgout" | grep -c "N/A" || true)
  if [ "$_pgrc" = 0 ] && [ "$_pglines" = 1 ] && ! printf '%s' "$_pgout" | grep -q LOUD; then
    echo "PASS: provenance_gate — job absent + na disposition -> exactly one N/A-with-reason line, never LOUD"
  else
    echo "FAIL: PG4 (rc=$_pgrc lines=$_pglines out='$_pgout')"; st=1
  fi

  # PG5: empty probe (no gh / no seam data) -> degrade-open, NAMED (never a silent proceed).
  d="$t/pg5"; _pg_mk "$d" 0 apply n/a apply n/a
  _pgrc=0
  _pgout=$( cd "$d"; RELEASE_SHA=$(git rev-parse HEAD); RELEASE_TAG_PROV_PROBE=true; RELEASE_TAG_PROVENANCE=observe; provenance_gate 2>&1 ) || _pgrc=$?
  if [ "$_pgrc" = 0 ] && printf '%s' "$_pgout" | grep -q degrade-open; then
    echo "PASS: provenance_gate — empty probe -> degrade-open, named"
  else
    echo "FAIL: PG5 (rc=$_pgrc out='$_pgout')"; st=1
  fi

  # PG6 (design §9.2 defect #1, killed): Dockerfile-LESS tree must NOT assert image-provenance — a
  # job absent from the probe that was never in the assertion set must never false-LOUD.
  d="$t/pg6"; _pg_mk "$d" 0 apply n/a apply n/a
  _pgrc=0
  _pgout=$( cd "$d"; RELEASE_SHA=$(git rev-parse HEAD); RELEASE_TAG_PROV_PROBE='printf "provenance\tsuccess\n"'; RELEASE_TAG_PROVENANCE=observe; provenance_gate 2>&1 ) || _pgrc=$?
  if [ "$_pgrc" = 0 ] && [ -z "$_pgout" ]; then
    echo "PASS: provenance_gate — Dockerfile-less tree does not assert image-provenance (no false LOUD)"
  else
    echo "FAIL: PG6 (rc=$_pgrc out='$_pgout') — image-provenance falsely asserted on a Dockerfile-less tree"; st=1
  fi

  # PG7: Dockerfile PRESENT + image-provenance itself skipped -> LOUD naming it (the positive face
  # of PG6's gating — proves the Dockerfile check adds the job rather than only ever excluding it).
  d="$t/pg7"; _pg_mk "$d" 1 apply n/a apply n/a
  _pgrc=0
  _pgout=$( cd "$d"; RELEASE_SHA=$(git rev-parse HEAD); RELEASE_TAG_PROV_PROBE='printf "provenance\tsuccess\nimage-provenance\tskipped\n"'; RELEASE_TAG_PROVENANCE=observe; provenance_gate 2>&1 ) || _pgrc=$?
  if [ "$_pgrc" = 0 ] && printf '%s' "$_pgout" | grep -q "image-provenance" && printf '%s' "$_pgout" | grep -q LOUD; then
    echo "PASS: provenance_gate — Dockerfile present + image-provenance skipped -> LOUD naming it"
  else
    echo "FAIL: PG7 (rc=$_pgrc out='$_pgout')"; st=1
  fi

  # PG-SHA (reviewer Important-2, CP-10 — the SHA-pinning proof): the RELEASE_SHA is pinned BEFORE
  # a Dockerfile is added to the WORKING TREE (uncommitted) — the assertion set must be decided from
  # the pinned commit, not whatever the working tree happens to hold right now.
  d="$t/pgsha"; _pg_mk "$d" 0 apply n/a apply n/a
  _pgsha=$( cd "$d" && git rev-parse HEAD )
  : > "$d/Dockerfile"   # uncommitted — the release SHA above does not have this
  _pgrc=0
  _pgout=$( cd "$d"; RELEASE_SHA="$_pgsha"; RELEASE_TAG_PROV_PROBE='printf "provenance\tsuccess\n"'; RELEASE_TAG_PROVENANCE=observe; provenance_gate 2>&1 ) || _pgrc=$?
  if [ "$_pgrc" = 0 ] && [ -z "$_pgout" ]; then
    echo "PASS: provenance_gate — a Dockerfile added to the WORKING TREE after the pin is invisible; image-provenance stays unasserted (CP-10 SHA-pinning proof)"
  else
    echo "FAIL: PG-SHA (rc=$_pgrc out='$_pgout') — the Dockerfile probe read the working tree instead of the pinned RELEASE_SHA"; st=1
  fi

  # PG-MODE-BAD (security LOW-1): an unrecognized RELEASE_TAG_PROVENANCE value warns by name and
  # stays OBSERVE (never silently enforces, never silently observes without saying so).
  d="$t/pgbad"; _pg_mk "$d" 0 apply n/a apply n/a
  _pgrc=0
  _pgout=$( cd "$d"; RELEASE_SHA=$(git rev-parse HEAD); RELEASE_TAG_PROV_PROBE='printf "provenance\tskipped\n"'; RELEASE_TAG_PROVENANCE=bogus; provenance_gate 2>&1 ) || _pgrc=$?
  if [ "$_pgrc" = 0 ] && printf '%s' "$_pgout" | grep -q "not a recognized value" && printf '%s' "$_pgout" | grep -q "bogus"; then
    echo "PASS: provenance_gate — an unrecognized RELEASE_TAG_PROVENANCE value warns by name and stays OBSERVE [security LOW-1]"
  else
    echo "FAIL: PG-MODE-BAD (rc=$_pgrc out='$_pgout')"; st=1
  fi

  # PG-CTRL (security LOW-3): a disposition REASON carrying a raw control character (a terminal
  # escape) must never reach an echoed message intact.
  d="$t/pgctrl"; _pg_mk "$d" 0 na "$(printf 'bad\001mark')" apply n/a
  _pgrc=0
  _pgout=$( cd "$d"; RELEASE_SHA=$(git rev-parse HEAD); RELEASE_TAG_PROV_PROBE='printf "provenance\tskipped\n"'; RELEASE_TAG_PROVENANCE=observe; provenance_gate 2>&1 ) || _pgrc=$?
  # Locale-stable: count surviving CONTROL bytes directly ([:cntrl:] is byte-stable in every
  # locale) — deleting [:print:] instead miscounts multibyte UTF-8 text under LC_ALL=C (seat-measured).
  _pgctrl=$(printf '%s' "$_pgout" | tr -cd '[:cntrl:]' | tr -d '\n\t' | wc -c | tr -d ' ')
  if [ "$_pgrc" = 0 ] && [ "$_pgctrl" = 0 ] && printf '%s' "$_pgout" | grep -q "badmark"; then
    echo "PASS: provenance_gate — a control character in a disposition reason is stripped before echoing [security LOW-3]"
  else
    echo "FAIL: PG-CTRL (rc=$_pgrc ctrl-bytes-remaining=$_pgctrl out='$_pgout')"; st=1
  fi

  # PGWIRE (TEETH — the same end-to-end-through-run() discipline as tests I/J/M above): a skipped
  # provenance job in ENFORCE mode must refuse THROUGH run(), and no tag is written. A direct-call
  # test proves the FUNCTION; only driving the real script proves run() actually CALLS it.
  d="$t/pgwire"; mkdir -p "$d"; _wt "$d"
  _pgwrc=0
  ( cd "$d/w" && META_CONTROL_ROOT="$t/cad" META_CONTROL_TAGS=1.0.0 \
      RELEASE_TAG_CI_PROBE='printf "completed\tsuccess\n"' \
      RELEASE_TAG_PROV_PROBE='printf "provenance\tskipped\n"' \
      RELEASE_TAG_PROVENANCE=enforce \
      sh "$here/release-tag.sh" ) >/dev/null 2>&1 || _pgwrc=$?
  _pgwtag=$( cd "$d/w" && git tag -l v1.1.0 )
  if [ "$_pgwrc" != "0" ] && [ -z "$_pgwtag" ]; then
    echo "PASS: provenance_gate wired into run() — enforce+skipped -> refused end-to-end, no tag written"
  else
    echo "FAIL: PGWIRE — provenance gate not enforced through run() (rc=$_pgwrc tag='$_pgwtag')"; st=1
  fi

  # PGWIRE-OBS (LIVENESS anchor, same reason test J anchors test I): the DEFAULT dial (unset ->
  # observe) must still let a skipped-job release proceed end-to-end — a refuse-everything mutant
  # would pass PGWIRE and be worse than useless without this.
  d="$t/pgwireobs"; mkdir -p "$d"; _wt "$d"
  _pgwrc=0
  ( cd "$d/w" && META_CONTROL_ROOT="$t/cad" META_CONTROL_TAGS=1.0.0 \
      RELEASE_TAG_CI_PROBE='printf "completed\tsuccess\n"' \
      RELEASE_TAG_PROV_PROBE='printf "provenance\tskipped\n"' \
      sh "$here/release-tag.sh" ) >/dev/null 2>&1 || _pgwrc=$?
  _pgwtag=$( cd "$d/w" && git tag -l v1.1.0 )
  if [ "$_pgwrc" = "0" ] && [ -n "$_pgwtag" ]; then
    echo "PASS: provenance_gate default OBSERVE — skipped job proceeds end-to-end (dial default doesn't refuse)"
  else
    echo "FAIL: PGWIRE-OBS — default observe mode blocked the tag (rc=$_pgwrc tag='$_pgwtag')"; st=1
  fi

  rm -rf "$t"
  [ "$st" = 0 ] && { echo "release-tag --selftest: OK"; return 0; } || { echo "release-tag --selftest: FAIL"; return 1; }
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  --dry-run)  run --dry-run; exit $? ;;
  "")         run; exit $? ;;
  *)          echo "usage: release-tag.sh [--dry-run|--selftest]" >&2; exit 2 ;;
esac
