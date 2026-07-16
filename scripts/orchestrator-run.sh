#!/bin/sh
# orchestrator-run.sh — E3a real mechanical orchestration loop (harness-neutral).
# ⚠ Q2 relabel (KW8 follow-on): this file is the harness-neutral REFERENCE implementation +
#   fixture selftest of the loop — NOT the live driver. The live conductor is the session-as-
#   conductor pattern: an agent dispatching Engineer subagents via its harness's Agent/Task tool
#   (as in the KW8 and KW8-followon runs). This script proves the loop's SHAPE deterministically
#   (fixture ROLE_RUNNER) and runs as a CI selftest; it did not itself drive a real fan-out.
# Fans a work-list of disjoint slices to ROLE_RUNNER (the Engineer seam), each in an
# isolated git worktree, meters each step through runaway-guard.sh, integrates the diffs,
# and emits the OTel span tree scripts/otel-to-scorecard.sh reads. Replaces the E5-thin
# stand-in (orchestrator-trace-demo.sh). Live: ROLE_RUNNER dispatches an LLM subagent.
# CI/selftest: scripts/fixtures/engineer-fixture.sh. kit.denied is set ONLY from the
# guard's exit code here (trusted) — never from agent data. sh + jq + git. Not a gate.
#
# Modes:
#   orchestrator-run.sh SLICE...   drive the loop in the CURRENT git repo (live)
#   orchestrator-run.sh            self-isolating representative demo -> prints trace path
#   orchestrator-run.sh --selftest self-isolating assertions
# What it changes: Live mode drives disjoint slices in the CURRENT git repo — creates ephemeral git worktrees and integrates each slice's diffs; writes an OTel trace file; resets/steps the runaway tally.
# Guardrails: Rejects non-slug slice names; meters every step through runaway-guard.sh and halts on breach; kit.denied is set ONLY from the guard's exit code (trusted), never from agent data; not a gate.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
ROLE_RUNNER="${ROLE_RUNNER:-$here/fixtures/engineer-fixture.sh}"

now() { _n=$(date +%s%N 2>/dev/null); case "$_n" in *N|"") printf '%s000000000' "$(date +%s)";; *) printf '%s' "$_n";; esac; }
span() { sh "$here/otel-trace.sh" span "$@"; }

# run SLICE...  — drive the loop in $PWD's git repo; emit trace to $OTEL_TRACE_FILE (or mktemp);
# print the trace-file path. Requires a runaway budget config present (else guard fail-closes).
run() {
  OUT="${OTEL_TRACE_FILE:-$(mktemp)}"; printf '' > "$OUT"; export OTEL_TRACE_FILE="$OUT"
  wtbase=$(mktemp -d)
  sh "$here/runaway-guard.sh" reset >/dev/null 2>&1 || true
  tid="${OTEL_TRACE_ID:-$(sh "$here/otel-trace.sh" new-trace)}"
  r_start=$(now)
  root=$(span --trace "$tid" --name orchestrator-run --status OK --start "$r_start" --end "$r_start" --attr "agent.id=orchestrator")
  halted=0; built=""; base=$(git rev-parse HEAD)
  for slice in "$@"; do
    [ "$halted" = 0 ] || break
    # slice names flow into paths/branches/merge refs — reject anything but a safe slug (defense-in-depth)
    case "$slice" in *[!A-Za-z0-9._-]*|"") echo "orchestrator-run: invalid slice name: $slice" >&2; exit 2 ;; esac
    wt="$wtbase/$slice"
    git worktree add -q -b "e3a/$slice" "$wt" HEAD
    e_start=$(now)
    # Scrub the role-runner's env (anti-spoof): a live engineer must NOT be able to append/forge spans
    # (OTEL_TRACE_FILE) NOR learn the deterministic escalation id / record dir (OTEL_TRACE_ID,
    # KIT_ESCALATION_DIR, KIT_RUN_DIR) — else it could pre-write its OWN verdict and self-ratify a breach.
    env -u OTEL_TRACE_FILE -u OTEL_TRACE_ID -u KIT_ESCALATION_DIR -u KIT_RUN_DIR "$ROLE_RUNNER" "$slice" "$wt" >/dev/null
    e_end=$(now)
    rc=0; sh "$here/runaway-guard.sh" step --tokens "${STEP_TOKENS:-1000}" --agents 1 >/dev/null 2>&1 || rc=$?
    # Legibility (Slice 3): resolve this builder's MODEL tier fail-safe (any error -> deep, the safe
    # high floor) and stamp it on the span so otel-to-scorecard.sh -> the scorecard can render it.
    # tokens seeds the value-analysis cost axis in the demo; a real Workflow run overwrites with actuals.
    mt=$(sh "$here/model-tier.sh" resolve --role engineer --change-class ordinary 2>/dev/null || echo deep)
    case "$rc" in
      0) span --trace "$tid" --parent "$root" --name "agent:engineer" --status OK \
              --start "$e_start" --end "$e_end" --attr "agent.id=engineer" --attr "slice=$slice" \
              --attr "model.tier=$mt" --attr "tokens=${STEP_TOKENS:-1000}" >/dev/null
         built="$built $slice" ;;
      1) # guard STOP -> governed breach: ESCALATE to a human (E3-escalation), don't bare-halt.
         eid="$tid.$slice"
         sh "$here/escalate.sh" raise "$eid" runaway-breach security-owner \
            "Runaway ceiling hit while building slice '$slice'. Raise the ceiling, abort, or amend scope?" >/dev/null
         vf="${KIT_ESCALATION_DIR:-${KIT_RUN_DIR:-.kit-run}/escalations}/$(printf '%s' "$eid" | tr -c 'A-Za-z0-9._-' '_').verdict"
         if sh "$here/escalate.sh" await "$eid" >/dev/null 2>&1; then
           # read the ratifier BEFORE resolve (resolve consumes the verdict file to prevent replay);
           # strip CR/LF so an unauthenticated ratifier_id cannot inject into the NDJSON trace line.
           rat=$(jq -r '.ratifier_id // ""' "$vf" 2>/dev/null | tr -d '\r\n' || echo "")
           verdict=$(sh "$here/escalate.sh" resolve "$eid") || verdict=""
           case "$verdict" in
             raise-ceiling) # governed break-glass: clear the tally, accept this slice, continue fan-out
               span --trace "$tid" --parent "$root" --name "gate:guard" --status OK \
                    --start "$e_start" --end "$(now)" --attr "agent.id=engineer" --attr "slice=$slice" \
                    --attr "kit.escalated=true" --attr "kit.verdict=raise-ceiling" --attr "kit.ratifier=$rat" >/dev/null
               sh "$here/runaway-guard.sh" reset >/dev/null 2>&1 || true
               built="$built $slice" ;;
             abort|amend) # human declined: halt, denial recorded WITH the human verdict
               span --trace "$tid" --parent "$root" --name "gate:guard" --status ERROR \
                    --start "$e_start" --end "$(now)" --attr "agent.id=engineer" --attr "slice=$slice" \
                    --attr "kit.denied=true" --attr "kit.escalated=true" --attr "kit.verdict=$verdict" --attr "kit.ratifier=$rat" >/dev/null
               halted=1 ;;
             *) # invalid verdict -> fail-closed
               span --trace "$tid" --parent "$root" --name "gate:guard" --status ERROR \
                    --start "$e_start" --end "$(now)" --attr "agent.id=engineer" --attr "slice=$slice" --attr "kit.denied=true" >/dev/null
               halted=1 ;;
           esac
         else
           # PAUSED: no verdict yet -> record written, loop stops here (resume on re-run after a verdict is written)
           span --trace "$tid" --parent "$root" --name "gate:guard" --status ERROR \
                --start "$e_start" --end "$(now)" --attr "agent.id=engineer" --attr "slice=$slice" \
                --attr "kit.denied=true" --attr "kit.escalated=pending" >/dev/null
           halted=1
         fi ;;
      *) echo "orchestrator-run: runaway-guard UNVERIFIED (rc=$rc) — fail-closed" >&2; exit 2 ;;
    esac
  done
  # E3b conflict-safe integration: detect overlapping changed-file sets BEFORE merging (detect by
  # inspection, not by a corrupting merge). Uses --no-renames so a rename surfaces BOTH the deleted
  # source AND the added target — two slices renaming the same source to different targets thus still
  # collide on the source (closes the rename-divergence evasion). A path claimed by >=2 built slices ->
  # refuse fail-closed with a TRUSTED kit.conflict span (set here from the computed diffs, never
  # agent-supplied); do NOT attempt any merge (the tree stays clean). Changed-file granularity (honest
  # ceiling: not semantic conflicts across DIFFERENT files); the merge loop below is the fail-closed
  # floor for the residual. git-diff failure -> fail-closed; a claims-write failure -> fail-closed.
  claims=$(mktemp)
  for slice in $built; do
    cf_one=$(git diff --name-only --no-renames "$base..e3a/$slice") \
      || { rm -f "$claims"; echo "orchestrator-run: cannot diff e3a/$slice — fail-closed" >&2; exit 2; }
    printf '%s\n' "$cf_one" | while IFS= read -r f; do
      [ -n "$f" ] && printf '%s\t%s\n' "$f" "$slice" || true
    done >> "$claims"
  done
  dup=$(cut -f1 "$claims" | sort | uniq -d | head -n1)
  if [ -n "$dup" ]; then
    cslices=$(awk -F'\t' -v want="$dup" '$1==want{printf "%s ", $2}' "$claims")
    span --trace "$tid" --parent "$root" --name "gate:integration" --status ERROR \
         --start "$(now)" --end "$(now)" --attr "agent.id=orchestrator" \
         --attr "kit.conflict=true" --attr "conflict.file=$dup" --attr "conflict.slices=$cslices" >/dev/null
    rm -f "$claims"
    for slice in $built; do git worktree remove -f "$wtbase/$slice" 2>/dev/null || true; done
    echo "orchestrator-run: conflict — slices [$cslices] all modified '$dup' — refusing integration (no silent corruption)" >&2
    printf '%s\n' "$OUT"
    exit 1
  fi
  rm -f "$claims"
  # integrate disjoint worktree branches. Detection above catches any same-path overlap; this merge is
  # the fail-closed FLOOR for anything the changed-file granularity can miss. On failure: abort the
  # half-merge (keep the tree clean), clean up worktrees, emit a TRUSTED kit.conflict span (observable),
  # and refuse — never leave a dirty tree or a dangling worktree.
  for slice in $built; do
    if ! git merge -q --no-edit "e3a/$slice"; then
      git merge --abort 2>/dev/null || true
      # ATOMICITY: a floor trip is all-or-nothing -- reset to the run cut-point base so any
      # slices already merged this run are undone (no partial-integration residual). base is
      # orchestrator-owned (captured at run start), never agent-supplied. Per the loop's
      # clean-committed-base contract there are no uncommitted tracked changes to lose;
      # reset is best-effort and WARNS (not silent) on the pathological failure so the rare
      # non-atomic outcome is observable, while the kit.conflict span + refusal still fire.
      git reset --hard -q "$base" 2>/dev/null || echo "orchestrator-run: WARNING reset to base failed - manual cleanup may be needed" >&2
      span --trace "$tid" --parent "$root" --name "gate:integration" --status ERROR \
           --start "$(now)" --end "$(now)" --attr "agent.id=orchestrator" \
           --attr "kit.conflict=true" --attr "conflict.file=merge:$slice" --attr "conflict.slices=$slice" >/dev/null
      for s in $built; do git worktree remove -f "$wtbase/$s" 2>/dev/null || true; done
      echo "orchestrator-run: integration merge failed for $slice (detection floor) — refusing, tree clean" >&2
      printf '%s\n' "$OUT"
      exit 1
    fi
  done
  # cleanup worktrees (branches retain the integrated commits on the current branch)
  for slice in $built; do git worktree remove -f "$wtbase/$slice" 2>/dev/null || true; done
  printf '%s\n' "$OUT"
}

# _isolated BUDGET_KV... -- SLICE...  : run the loop in a throwaway git repo so demo/selftest
# never touch the host repo. Trace OUT is a mktemp OUTSIDE the temp repo (persists after cleanup).
_isolated() {
  budget=""; while [ "$1" != "--" ]; do budget="$budget$1\n"; shift; done; shift
  tmp=$(mktemp -d); ext=$(mktemp); conf=$(mktemp); tally=$(mktemp)
  printf '%b' "$budget" > "$conf"; printf '' > "$tally"
  (
    cd "$tmp"
    git init -q; git config user.email e@x; git config user.name e
    echo seed > seed.txt; git add seed.txt; git commit -q -m seed
    OTEL_TRACE_FILE="$ext" RUNAWAY_BUDGET_CONFIG="$conf" RUNAWAY_TALLY="$tally" \
      "$here/orchestrator-run.sh" "$@" >/dev/null
  )
  rm -rf "$tmp" "$conf" "$tally"
  printf '%s\n' "$ext"
}

demo() { _isolated "MAX_TOKENS=0" "MAX_STEPS=2" "MAX_AGENTS=0" -- demoA demoB demoC; }

selftest() {
  fail=0
  # clean run: 2 disjoint slices, no ceiling -> root + 2 engineer children, both artifacts integrated
  clean=$(_isolated "MAX_TOKENS=0" "MAX_STEPS=0" "MAX_AGENTS=0" -- alpha beta)
  n=$(wc -l < "$clean" | tr -d ' ')
  [ "$n" -ge 3 ] || { echo "FAIL: clean run expected >=3 spans, got $n"; fail=1; }
  [ "$(jq -s '[.[]|select(.parent_span_id==null)]|length' "$clean")" = "1" ] || { echo "FAIL: not exactly 1 root"; fail=1; }
  [ "$(jq -s '[.[]|select(.attributes["agent.id"]=="engineer")]|length' "$clean")" = "2" ] || { echo "FAIL: expected 2 engineer children"; fail=1; }
  [ "$(jq -s '[.[]|select(.attributes["kit.denied"]=="true")]|length' "$clean")" = "0" ] || { echo "FAIL: clean run has a denied span"; fail=1; }
  rm -f "$clean"
  # breach run: 3 slices, MAX_STEPS=2 -> engineer#1 OK, engineer#2 DENIED + halt (engineer#3 never runs)
  br=$(_isolated "MAX_TOKENS=0" "MAX_STEPS=2" "MAX_AGENTS=0" -- one two three)
  [ "$(jq -s '[.[]|select(.attributes["kit.denied"]=="true")]|length' "$br")" = "1" ] || { echo "FAIL: breach run not exactly 1 denied span"; fail=1; }
  [ "$(jq -s '[.[]|select(.attributes["agent.id"]=="engineer")]|length' "$br")" = "2" ] || { echo "FAIL: breach run expected 2 child spans (1 ok engineer + 1 denied), halt not honored"; fail=1; }
  # the denied span feeds the scorecard adapter to a denied step
  [ "$(sh "$here/otel-to-scorecard.sh" "$br" | jq '[.[]|select(.steps[].outcome=="denied")]|length')" -ge 1 ] || { echo "FAIL: denied not mapped to scorecard"; fail=1; }
  rm -f "$br"
  # E3-escalation (fail-closed pause): breach with NO verdict written -> loop stops here,
  # gate span carries kit.escalated=pending + kit.denied; engineer#3 does NOT run. The resume
  # positive is the next case; this is the load-bearing NEGATIVE (a dead loop -> 0 spans, an
  # always-proceed loop -> 3 engineer spans; both fail). No verdict is pre-placed.
  br2=$(_isolated "MAX_TOKENS=0" "MAX_STEPS=2" "MAX_AGENTS=0" -- one two three)
  [ "$(jq -s '[.[]|select(.attributes["kit.escalated"]=="pending")]|length' "$br2")" = "1" ] \
    || { echo "FAIL: breach without a verdict did not record kit.escalated=pending (fail-closed pause)"; fail=1; }
  [ "$(jq -s '[.[]|select(.attributes["agent.id"]=="engineer")]|length' "$br2")" = "2" ] \
    || { echo "FAIL: paused run advanced past the breach (no-progress fail-closed violated)"; fail=1; }
  rm -f "$br2"
  # E3-escalation (raise-ceiling resume): breach + a PRE-PLACED raise-ceiling verdict -> the loop
  # continues past the breach; the gate span carries kit.escalated=true + kit.verdict + kit.ratifier
  # (sourced from the verdict FILE), all 3 engineers run, NO denial. The OTEL_TRACE_ID opt-in makes
  # the breaching slice's escalation id deterministic so the verdict can be pre-placed.
  rdir=$(mktemp -d); rtid="esc-resume-$$"
  printf '{"option":"raise-ceiling","note":"selftest","ratifier_id":"selftest@kit"}' \
    > "$rdir/$(printf '%s' "$rtid.two" | tr -c 'A-Za-z0-9._-' '_').verdict"
  rtmp=$(mktemp -d); rout=$(mktemp); rconf=$(mktemp); rtally=$(mktemp)
  printf 'MAX_TOKENS=0\nMAX_STEPS=2\nMAX_AGENTS=0\n' > "$rconf"
  ( cd "$rtmp"; git init -q; git config user.email e@x; git config user.name e
    echo seed > seed.txt; git add seed.txt; git commit -q -m seed
    OTEL_TRACE_ID="$rtid" KIT_ESCALATION_DIR="$rdir" OTEL_TRACE_FILE="$rout" \
      RUNAWAY_BUDGET_CONFIG="$rconf" RUNAWAY_TALLY="$rtally" \
      "$here/orchestrator-run.sh" one two three >/dev/null 2>&1 )
  [ "$(jq -s '[.[]|select(.attributes["kit.escalated"]=="true")]|length' "$rout")" = "1" ] \
    || { echo "FAIL: raise-ceiling verdict did not resume the loop (no kit.escalated=true span)"; fail=1; }
  [ "$(jq -s '[.[]|select(.attributes["kit.verdict"]=="raise-ceiling")]|length' "$rout")" = "1" ] \
    || { echo "FAIL: resumed span missing kit.verdict=raise-ceiling"; fail=1; }
  [ "$(jq -s '[.[]|select(.attributes["agent.id"]=="engineer")]|length' "$rout")" = "3" ] \
    || { echo "FAIL: raise-ceiling did not continue past the breach (expected 3 engineer spans)"; fail=1; }
  [ "$(jq -s '[.[]|select(.attributes["kit.denied"]=="true")]|length' "$rout")" = "0" ] \
    || { echo "FAIL: raise-ceiling resume wrongly recorded a denial"; fail=1; }
  rm -rf "$rdir" "$rtmp"; rm -f "$rout" "$rconf" "$rtally"
  # E3-escalation (anti-spoof): the engineer role-runner MUST NOT inherit OTEL_TRACE_ID /
  # KIT_ESCALATION_DIR / KIT_RUN_DIR -- else it could compute the deterministic escalation id and
  # pre-write its OWN verdict file to self-ratify a breach. Probe the role-runner's actual env.
  eprobe=$(mktemp); erun=$(mktemp); export E3_ENVPROBE="$eprobe"
  cat > "$erun" <<'PROBE'
#!/bin/sh
{ echo "OTEL_TRACE_ID=[${OTEL_TRACE_ID:-UNSET}]"
  echo "KIT_ESCALATION_DIR=[${KIT_ESCALATION_DIR:-UNSET}]"
  echo "KIT_RUN_DIR=[${KIT_RUN_DIR:-UNSET}]"; } >> "$E3_ENVPROBE"
PROBE
  chmod +x "$erun"
  etmp=$(mktemp -d); eout=$(mktemp); econf=$(mktemp); etally=$(mktemp)
  printf 'MAX_TOKENS=0\nMAX_STEPS=0\nMAX_AGENTS=0\n' > "$econf"
  ( cd "$etmp"; git init -q; git config user.email e@x; git config user.name e
    echo seed > seed.txt; git add seed.txt; git commit -q -m seed
    OTEL_TRACE_ID="leak-probe" KIT_ESCALATION_DIR="/tmp/leak-esc" KIT_RUN_DIR="/tmp/leak-run" \
      OTEL_TRACE_FILE="$eout" RUNAWAY_BUDGET_CONFIG="$econf" RUNAWAY_TALLY="$etally" \
      ROLE_RUNNER="$erun" "$here/orchestrator-run.sh" alpha >/dev/null 2>&1 )
  unset E3_ENVPROBE
  grep -q 'OTEL_TRACE_ID=\[UNSET\]' "$eprobe"      || { echo "FAIL: role-runner LEAKED OTEL_TRACE_ID (anti-spoof: engineer can forge a verdict)"; fail=1; }
  grep -q 'KIT_ESCALATION_DIR=\[UNSET\]' "$eprobe" || { echo "FAIL: role-runner LEAKED KIT_ESCALATION_DIR (anti-spoof: engineer can locate the verdict channel)"; fail=1; }
  grep -q 'KIT_RUN_DIR=\[UNSET\]' "$eprobe"        || { echo "FAIL: role-runner LEAKED KIT_RUN_DIR"; fail=1; }
  rm -rf "$etmp"; rm -f "$eprobe" "$erun" "$eout" "$econf" "$etally"
  # E3b conflict-safe: two slices write the SAME file (conflicting fixture) -> overlap DETECTED, the run
  # REFUSES integration (exits nonzero), emits a kit.conflict span, does NOT merge (no silent corruption).
  ctmp=$(mktemp -d); cout=$(mktemp); cconf=$(mktemp); ctally=$(mktemp)
  printf 'MAX_TOKENS=0\nMAX_STEPS=0\nMAX_AGENTS=0\n' > "$cconf"
  crc=0
  ( cd "$ctmp"; git init -q; git config user.email e@x; git config user.name e
    echo seed > seed.txt; git add seed.txt; git commit -q -m seed
    FIXTURE_CONFLICT_FILE=shared.txt OTEL_TRACE_FILE="$cout" \
      RUNAWAY_BUDGET_CONFIG="$cconf" RUNAWAY_TALLY="$ctally" \
      "$here/orchestrator-run.sh" ca cb >/dev/null 2>&1 ) || crc=$?
  [ "$crc" -ne 0 ] || { echo "FAIL: overlapping slices did not refuse integration (expected nonzero exit)"; fail=1; }
  [ "$(jq -s '[.[]|select(.attributes["kit.conflict"]=="true")]|length' "$cout")" = "1" ] \
    || { echo "FAIL: no kit.conflict span emitted on overlap (detect-by-inspection missing)"; fail=1; }
  [ ! -f "$ctmp/shared.txt" ] || { echo "FAIL: overlap silently integrated shared.txt (corruption not prevented)"; fail=1; }
  rm -rf "$ctmp"; rm -f "$cout" "$cconf" "$ctally"
  # POSITIVE complement: disjoint slices still integrate cleanly (the existing clean-run assertion already
  # covers this, but re-confirm no kit.conflict on a disjoint run):
  dj=$(_isolated "MAX_TOKENS=0" "MAX_STEPS=0" "MAX_AGENTS=0" -- da db)
  [ "$(jq -s '[.[]|select(.attributes["kit.conflict"]=="true")]|length' "$dj")" = "0" ] \
    || { echo "FAIL: disjoint run wrongly flagged a conflict"; fail=1; }
  rm -f "$dj"
  # E3b conflict-safe (DUELING RENAME — the rename-divergence evasion): two slices rename the SAME
  # source file to DIFFERENT targets. --no-renames surfaces the deleted source in both diffs, so the
  # overlap on the source is detected (a plain --name-only with rename detection would see disjoint
  # {A} vs {B} and MISS it). Asserts kit.conflict fires (evasion closed) + the run refuses.
  rtmp=$(mktemp -d); rout=$(mktemp); rconf=$(mktemp); rtally=$(mktemp)
  printf 'MAX_TOKENS=0\nMAX_STEPS=0\nMAX_AGENTS=0\n' > "$rconf"
  rrc=0
  ( cd "$rtmp"; git init -q; git config user.email e@x; git config user.name e
    echo seed > seed.txt; git add seed.txt; git commit -q -m seed
    echo orig > F.txt; git add F.txt; git commit -q -m "add F"
    FIXTURE_RENAME_SRC=F.txt OTEL_TRACE_FILE="$rout" \
      RUNAWAY_BUDGET_CONFIG="$rconf" RUNAWAY_TALLY="$rtally" \
      "$here/orchestrator-run.sh" rra rrb >/dev/null 2>&1 ) || rrc=$?
  [ "$rrc" -ne 0 ] || { echo "FAIL: dueling-rename did not refuse integration"; fail=1; }
  [ "$(jq -s '[.[]|select(.attributes["kit.conflict"]=="true")]|length' "$rout")" -ge 1 ] \
    || { echo "FAIL: dueling-rename EVADED detection (no kit.conflict span) — rename-divergence not closed"; fail=1; }
  [ ! -f "$rtmp/renamed-by-rra.txt" ] || { echo "FAIL: dueling-rename silently integrated a side (tree not clean)"; fail=1; }
  rm -rf "$rtmp"; rm -f "$rout" "$rconf" "$rtally"
  # E3-merge-atomicity (load-bearing NEGATIVE): two slices with DISJOINT changed-file sets that still
  # collide at the merge FLOOR. clashF creates path 'clash' as a FILE; clashD creates 'clash/child' (a
  # file under dir 'clash'). Name-only sets {clash} vs {clash/child} are disjoint so DETECTION passes; the
  # merge floor then merges clashF (lands 'clash') and merging clashD FAILS (cannot create a dir over a
  # file) -> floor trips. WITHOUT the atomic reset, clashF stays committed (partial-integration residual);
  # WITH it, HEAD resets to the cut-point base. Asserts refuse + kit.conflict(merge:clashD) + HEAD==base
  # + no residual 'clash'. This is the case the unfixed code FAILS (HEAD advanced) and the fix makes pass.
  mtmp=$(mktemp -d); mout=$(mktemp); mconf=$(mktemp); mtally=$(mktemp); mrun=$(mktemp)
  printf 'MAX_TOKENS=0\nMAX_STEPS=0\nMAX_AGENTS=0\n' > "$mconf"
  cat > "$mrun" <<'DIRFILE'
#!/bin/sh
slice="$1"; wt="$2"; cd "$wt" || exit 1
case "$slice" in
  *F) printf 'x\n' > clash; git add clash; git commit -q -m "f($slice)" ;;
  *D) mkdir clash; printf 'y\n' > clash/child; git add clash/child; git commit -q -m "d($slice)" ;;
esac
DIRFILE
  chmod +x "$mrun"
  ( cd "$mtmp"; git init -q; git config user.email e@x; git config user.name e
    echo seed > seed.txt; git add seed.txt; git commit -q -m seed )
  mbase=$(git -C "$mtmp" rev-parse HEAD); mrc=0
  ( cd "$mtmp"
    ROLE_RUNNER="$mrun" OTEL_TRACE_FILE="$mout" \
      RUNAWAY_BUDGET_CONFIG="$mconf" RUNAWAY_TALLY="$mtally" \
      "$here/orchestrator-run.sh" clashF clashD >/dev/null 2>&1 ) || mrc=$?
  [ "$mrc" -ne 0 ] || { echo "FAIL: merge-floor clash did not refuse integration (expected nonzero exit)"; fail=1; }
  [ "$(jq -s '[.[]|select(.attributes["kit.conflict"]=="true" and .attributes["conflict.file"]=="merge:clashD")]|length' "$mout")" = "1" ] \
    || { echo "FAIL: merge-floor trip did not emit kit.conflict span for merge:clashD"; fail=1; }
  [ "$(git -C "$mtmp" rev-parse HEAD)" = "$mbase" ] \
    || { echo "FAIL: merge-floor trip left a partial-integration residual (HEAD != base) — integration not atomic"; fail=1; }
  [ ! -e "$mtmp/clash" ] \
    || { echo "FAIL: merge-floor trip left residual artifact 'clash' (integration not atomic)"; fail=1; }
  rm -rf "$mtmp"; rm -f "$mout" "$mconf" "$mtally" "$mrun"
  # E3-merge-atomicity (POSITIVE liveness anchor): a disjoint clean run still INTEGRATES — HEAD advances
  # past base and both artifacts are present. Guards against a regression where the atomic reset fires
  # spuriously on the success path (an always-reset bug integrates nothing and fails here).
  ptmp=$(mktemp -d); pout=$(mktemp); pconf=$(mktemp); ptally=$(mktemp)
  printf 'MAX_TOKENS=0\nMAX_STEPS=0\nMAX_AGENTS=0\n' > "$pconf"
  ( cd "$ptmp"; git init -q; git config user.email e@x; git config user.name e
    echo seed > seed.txt; git add seed.txt; git commit -q -m seed )
  pbase=$(git -C "$ptmp" rev-parse HEAD); prc=0
  ( cd "$ptmp"
    OTEL_TRACE_FILE="$pout" RUNAWAY_BUDGET_CONFIG="$pconf" RUNAWAY_TALLY="$ptally" \
      "$here/orchestrator-run.sh" pa pb >/dev/null 2>&1 ) || prc=$?
  [ "$prc" -eq 0 ] || { echo "FAIL: disjoint clean run did not exit 0 (prc=$prc)"; fail=1; }
  [ "$(git -C "$ptmp" rev-parse HEAD)" != "$pbase" ] \
    || { echo "FAIL: disjoint clean run did not integrate (HEAD == base) — reset fired spuriously on success"; fail=1; }
  { [ -f "$ptmp/built-by-pa.txt" ] && [ -f "$ptmp/built-by-pb.txt" ]; } \
    || { echo "FAIL: disjoint clean run missing integrated artifacts"; fail=1; }
  [ "$(jq -s '[.[]|select(.attributes["kit.conflict"]=="true")]|length' "$pout")" = "0" ] \
    || { echo "FAIL: disjoint clean run wrongly flagged a conflict"; fail=1; }
  rm -rf "$ptmp"; rm -f "$pout" "$pconf" "$ptally"
  [ "$fail" -eq 0 ] || { echo "orchestrator-run --selftest: FAIL" >&2; return 1; }
  echo "orchestrator-run --selftest: OK (clean fan-out+integrate, breach halt+denied, scorecard maps denied, escalation pause+resume, role-runner env scrubbed, conflict-safe detect+refuse incl. dueling-rename, integration atomic on floor-trip)"; return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "")         demo ;;
  *)          run "$@" ;;
esac
