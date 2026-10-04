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
#   KIT_RUN_ROW=<ROW> orchestrator-run.sh SLICE...   drive the loop in the CURRENT git repo (live); KIT_RUN_ROW required
#   orchestrator-run.sh            self-isolating representative demo -> prints trace path
#   orchestrator-run.sh --selftest self-isolating assertions
# What it changes: Live mode drives disjoint slices in the CURRENT git repo — creates ephemeral git worktrees and integrates each slice's diffs; writes an OTel trace file; steps the runaway tally for the row named by KIT_RUN_ROW (it never resets or wipes it; a raise-ceiling ruling only counts if a `RAISE <ROW>` line is in effect).
# Guardrails: Requires KIT_RUN_ROW (rc 2 if unset/invalid); rejects non-slug slice names; meters every step through runaway-guard.sh and halts on breach; kit.denied is set ONLY from the guard's exit code (trusted), never from agent data; not a gate; refuses the whole integration (rc 1, no merge) if any built slice touches a control-plane path (ASCII case-folded, raw names via `git diff -z`; a name with a control or non-ASCII byte is refused too), and runs its own git actuation with hooks disabled. That closes the DIFF/MERGE channel only: the engineer role runner is NOT sandboxed (same uid, a worktree sharing the main .git), so it can write the main checkout's files directly or plant config; the platform usage cap stays the hard ceiling.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
ROLE_RUNNER="${ROLE_RUNNER:-$here/fixtures/engineer-fixture.sh}"

now() { _n=$(date +%s%N 2>/dev/null); case "$_n" in *N|"") printf '%s000000000' "$(date +%s)";; *) printf '%s' "$_n";; esac; }
span() { sh "$here/otel-trace.sh" span "$@"; }

# run SLICE...  — drive the loop in $PWD's git repo; emit trace to $OTEL_TRACE_FILE (or mktemp);
# print the trace-file path. Requires a runaway budget config present (else guard fail-closes).
run() {
  # The guard grades per ROW and requires --row (no env fallback there); this loop takes the row from
  # KIT_RUN_ROW and checks it against the guard's grammar BEFORE any worktree or trace exists.
  # Explicit byte classes (no ranges), so no locale can widen them.
  case "${KIT_RUN_ROW:-}" in
    ""|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-]*|-*) _row_bad=1 ;;
    *) _row_bad=0; [ "${#KIT_RUN_ROW}" -le 64 ] || _row_bad=1 ;;
  esac
  [ "$_row_bad" = 0 ] || { echo "orchestrator-run: KIT_RUN_ROW must be set to the slice's row id ([A-Z0-9][A-Z0-9-]*, at most 64 characters)" >&2; exit 2; }
  OUT="${OTEL_TRACE_FILE:-$(mktemp)}"; printf '' > "$OUT"; export OTEL_TRACE_FILE="$OUT"
  wtbase=$(mktemp -d)
  # F4: the orchestrator's OWN git actuation runs with hooks disabled. The role runner shares the main .git, so
  # it can plant core.hooksPath in the SHARED config; `git -c core.hooksPath=<empty dir>` outranks it.
  nohooks=$(mktemp -d); trap 'rm -rf "$nohooks"' EXIT
  # ⚠️ STDOUT IS DISCARDED, STDERR IS NOT (B4-CROSS-SESSION-BUDGET). All three guard call sites used
  # to swallow stderr, which would have hidden the guard's SANDBOX-override banner — and a banner an
  # operator never sees is not a control. WARN/STOP lines surface here for the same reason.
  tid="${OTEL_TRACE_ID:-$(sh "$here/otel-trace.sh" new-trace)}"
  r_start=$(now)
  root=$(span --trace "$tid" --name orchestrator-run --status OK --start "$r_start" --end "$r_start" --attr "agent.id=orchestrator")
  halted=0; built=""; base=$(git rev-parse HEAD)
  for slice in "$@"; do
    [ "$halted" = 0 ] || break
    # slice names flow into paths/branches/merge refs — reject anything but a safe slug (defense-in-depth)
    case "$slice" in *[!A-Za-z0-9._-]*|"") echo "orchestrator-run: invalid slice name: $slice" >&2; exit 2 ;; esac
    wt="$wtbase/$slice"
    # (the F4 hardening is set inline for this call only, never exported: the role runner below is untrusted)
    GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$nohooks" \
      GIT_CONFIG_KEY_1=core.fsmonitor GIT_CONFIG_VALUE_1='' GIT_CONFIG_KEY_2=diff.external GIT_CONFIG_VALUE_2='' \
      git worktree add -q -b "e3a/$slice" "$wt" HEAD
    e_start=$(now)
    # Scrub the role-runner's env (anti-spoof): a live engineer must NOT be able to append/forge spans
    # (OTEL_TRACE_FILE) NOR learn the deterministic escalation id / record dir (OTEL_TRACE_ID,
    # KIT_ESCALATION_DIR, KIT_RUN_DIR) — else it could pre-write its OWN verdict and self-ratify a breach.
    # The metering dials too (RUNAWAY_TALLY, RUNAWAY_BUDGET_CONFIG, KIT_RUNAWAY_SANDBOX, KIT_RUN_ROW): an
    # engineer that sees them could re-point its own meter or learn which row it is charged to.
    env -u OTEL_TRACE_FILE -u OTEL_TRACE_ID -u KIT_ESCALATION_DIR -u KIT_RUN_DIR -u GIT_CONFIG_COUNT \
        -u RUNAWAY_TALLY -u RUNAWAY_BUDGET_CONFIG -u KIT_RUNAWAY_SANDBOX -u KIT_RUN_ROW \
        "$ROLE_RUNNER" "$slice" "$wt" >/dev/null
    e_end=$(now)
    rc=0; sh "$here/runaway-guard.sh" step --row "$KIT_RUN_ROW" --tokens "${STEP_TOKENS:-1000}" --agents 1 >/dev/null || rc=$?
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
             raise-ceiling) # governed break-glass: NEVER a tally wipe — the ruling only counts if a `RAISE <ROW>`
               # line for this row is now in effect: re-grade the row (check writes nothing, same rc as step).
               crc=0; sh "$here/runaway-guard.sh" check --row "$KIT_RUN_ROW" >/dev/null || crc=$?
               if [ "$crc" = 0 ]; then
                 span --trace "$tid" --parent "$root" --name "gate:guard" --status OK \
                      --start "$e_start" --end "$(now)" --attr "agent.id=engineer" --attr "slice=$slice" \
                      --attr "kit.escalated=true" --attr "kit.verdict=raise-ceiling" --attr "kit.ratifier=$rat" >/dev/null
                 built="$built $slice"
               else
                 span --trace "$tid" --parent "$root" --name "gate:guard" --status ERROR \
                      --start "$e_start" --end "$(now)" --attr "agent.id=engineer" --attr "slice=$slice" \
                      --attr "kit.denied=true" --attr "kit.escalated=true" --attr "kit.verdict=raise-ceiling" --attr "kit.ratifier=$rat" >/dev/null
                 echo "orchestrator-run: raise-ceiling ruled but no sufficient RAISE for $KIT_RUN_ROW is in effect (check rc=$crc) — add 'RAISE $KIT_RUN_ROW MAX_TOKENS=<n>' and/or 'MAX_AGENTS=<n>' / 'MAX_STEPS=<n>' for the breached dimension to the budget config" >&2
                 halted=1
               fi ;;
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
  # F4: from here every git call is the orchestrator's OWN (all role runners have finished): run them with hooks,
  # fsmonitor and an external diff driver disabled via git's env config (git >= 2.31), which outranks the shared
  # config a role runner could have planted. filter.* smudge/process drivers (shared config or attributes) are NOT
  # covered here; they stay under the documented same-uid disclosure.
  GIT_CONFIG_COUNT=3
  GIT_CONFIG_KEY_0=core.hooksPath; GIT_CONFIG_VALUE_0="$nohooks"
  GIT_CONFIG_KEY_1=core.fsmonitor; GIT_CONFIG_VALUE_1=
  GIT_CONFIG_KEY_2=diff.external; GIT_CONFIG_VALUE_2=
  export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_CONFIG_KEY_1 GIT_CONFIG_VALUE_1 GIT_CONFIG_KEY_2 GIT_CONFIG_VALUE_2
  claims=$(mktemp); rawf=$(mktemp); unsafe_slice=""
  for slice in $built; do
    # F2: `-z` gives the RAW, unquoted names (plain --name-only C-quotes a byte >= 0x80, a `"`, a backslash or a
    # control character, and the quoted form starts with `"`, missing every prefix check). A name carrying a
    # control byte (newline and tab included) is not a legitimate slice file: refused outright.
    git diff --name-only --no-renames -z "$base..e3a/$slice" > "$rawf" \
      || { rm -f "$claims" "$rawf"; echo "orchestrator-run: cannot diff e3a/$slice — fail-closed" >&2; exit 2; }
    # F1-RESIDUAL: a case-insensitive filesystem (APFS) folds far more than ASCII A-Z (Kelvin U+212A -> k, long-s
    # U+017F -> s, NFD == NFC), so we do NOT try to mimic its fold: ANY byte >= 0x80 refuses the slice, exactly like a
    # control byte. This over-denies (`docs/` + an accented name too); legitimate kit slices never need non-ASCII names.
    # F2-RESIDUAL: every tr runs under LC_ALL=C (under a UTF-8 locale tr aborts on invalid UTF-8 and truncates).
    # (counted with wc, not captured: a $(...) capture would strip a lone newline)
    if [ "$(LC_ALL=C tr -d '\000' < "$rawf" | LC_ALL=C tr -cd '\001-\037\177\200-\377' | wc -c | tr -d ' ')" != 0 ]; then
      unsafe_slice=$slice; break
    fi
    LC_ALL=C tr '\000' '\n' < "$rawf" | while IFS= read -r f; do
      [ -n "$f" ] && printf '%s\t%s\n' "$f" "$slice" || true
    done >> "$claims"
  done
  rm -f "$rawf"
  # SEC-1: a slice must never land a change to the control plane (a `RAISE <ROW>` line in .kit/budget.conf,
  # a replaced guard, a workflow, a hook): the next run would honour it. Refuse the WHOLE integration, before
  # any merge, from the same trusted diffs. The literal list below is a subset of the guard's control-plane set,
  # covering the runaway actuation surface; `.claude/hooks/guard-core.sh::is_control_plane_path` is the authority
  # for the harness guard. F1: matched on tolower() under LC_ALL=C in EVERY arm (a case-insensitive filesystem
  # resolves `.KIT/budget.conf` to the real file); this only ever over-denies.
  cp_hit=$(LC_ALL=C awk -F'\t' '
    { p = tolower($1) }
    p == "claude.md" || p == "agents.md" || p == ".kit" || p == ".gitattributes" || p == ".gitmodules" || p == "codeowners" \
      || p == ".gitleaks.toml" || p == ".gitleaksignore" || p == ".semgrepignore" || p == ".trivyignore" \
      || p ~ /^development-[^\/]*\.md$/ || index(p, ".checkov") == 1 \
      || index(p, ".kit/") == 1 || index(p, "scripts/") == 1 || index(p, "conformance/") == 1 || index(p, "hooks/") == 1 \
      || index(p, ".github/") == 1 || index(p, ".claude/") == 1 || index(p, "skills/") == 1 || index(p, "agents/") == 1 \
      || index(p, "adapters/") == 1 || index(p, "docs/governance/") == 1 || index(p, "profiles/") == 1 \
      { print $2 "\t" $1; exit }' "$claims")
  [ -z "$unsafe_slice" ] || cp_hit="$unsafe_slice	(a non-ASCII or control-byte path)"
  if [ -n "$cp_hit" ]; then
    cp_slice=${cp_hit%%	*}; cp_file=${cp_hit#*	}
    span --trace "$tid" --parent "$root" --name "gate:integrate" --status ERROR \
         --start "$(now)" --end "$(now)" --attr "agent.id=orchestrator" \
         --attr "kit.denied=true" --attr "kit.controlplane=true" --attr "controlplane.file=$cp_file" --attr "controlplane.slice=$cp_slice" >/dev/null
    rm -f "$claims"
    for slice in $built; do git worktree remove -f "$wtbase/$slice" 2>/dev/null || true; done
    echo "orchestrator-run: slice '$cp_slice' touches a control-plane path ($cp_file) — integration refused" >&2
    printf '%s\n' "$OUT"
    exit 1
  fi
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
  # ⚠️ THE SANDBOX DIAL IS DECLARED HERE (B4-CROSS-SESSION-BUDGET). The guard REFUSES a redirected
  # config/tally unless KIT_RUNAWAY_SANDBOX vouches for it — a second tally is a second ceiling — so
  # a fixture that wants its own throwaway budget must say so out loud, and every such run banners.
  # conf + tally therefore live INSIDE the sandbox root, not at loose mktemp paths.
  budget=""; while [ "$1" != "--" ]; do budget="$budget$1\n"; shift; done; shift
  sand=$(mktemp -d); tmp="$sand/repo"; mkdir -p "$tmp"
  ext=$(mktemp); conf="$sand/budget.conf"; tally="$sand/tally"
  printf '%b' "$budget" > "$conf"; printf '' > "$tally"
  (
    cd "$tmp"
    git init -q; git config user.email e@x; git config user.name e
    echo seed > seed.txt; git add seed.txt; git commit -q -m seed
    HOME="$sand" KIT_RUNAWAY_SANDBOX="$sand" \
      OTEL_TRACE_FILE="$ext" RUNAWAY_BUDGET_CONFIG="$conf" RUNAWAY_TALLY="$tally" \
      "$here/orchestrator-run.sh" "$@" >/dev/null
  )
  rm -rf "$sand"
  printf '%s\n' "$ext"
}

# The demo meters its OWN row in its own seeded temp repo under its own $HOME (see _isolated) — never the
# ambient checkout, which is SHALLOW in CI and which the guard refuses (no stable repo key).
# MAX_AGENTS=2 (per row) reproduces the old MAX_STEPS=2 shape: engineer#1 OK, engineer#2 denied, halt.
demo() { KIT_RUN_ROW=DEMO-RUN; export KIT_RUN_ROW; _isolated "MAX_TOKENS=0" "MAX_STEPS=0" "MAX_AGENTS=2" -- demoA demoB demoC; }

selftest() {
  fail=0
  # every sandboxed run meters against ONE row (the guard grades per row and requires --row); the legs
  # that test the row requirement itself override or unset it explicitly.
  export KIT_RUN_ROW=SELFTEST-ROW
  # ⚠️ THE SANDBOX BANNER IS SILENCED AT THE ASSERTING CALL SITES ONLY, NEVER INSIDE `_isolated`
  # (R1/M2). Every fixture declares the dial, so each run legitimately banners three times; muffling
  # it inside the helper would also muffle the guard's REFUSALS and WARNs — i.e. the thing this slice
  # exists to surface — for the demo path and any future caller. `_iso_q` is the selftest's own noise
  # gate: stdout (the trace path each assertion reads) is untouched.
  _iso_q() { _isolated "$@" 2>/dev/null; }
  # clean run: 2 disjoint slices, no ceiling -> root + 2 engineer children, both artifacts integrated
  clean=$(_iso_q "MAX_TOKENS=0" "MAX_STEPS=0" "MAX_AGENTS=0" -- alpha beta)
  n=$(wc -l < "$clean" | tr -d ' ')
  [ "$n" -ge 3 ] || { echo "FAIL: clean run expected >=3 spans, got $n"; fail=1; }
  [ "$(jq -s '[.[]|select(.parent_span_id==null)]|length' "$clean")" = "1" ] || { echo "FAIL: not exactly 1 root"; fail=1; }
  [ "$(jq -s '[.[]|select(.attributes["agent.id"]=="engineer")]|length' "$clean")" = "2" ] || { echo "FAIL: expected 2 engineer children"; fail=1; }
  [ "$(jq -s '[.[]|select(.attributes["kit.denied"]=="true")]|length' "$clean")" = "0" ] || { echo "FAIL: clean run has a denied span"; fail=1; }
  rm -f "$clean"
  # breach run: 3 slices, MAX_AGENTS=2 (each step reports 1 agent; the ceiling is per ROW) -> engineer#1 OK,
  # engineer#2 DENIED + halt (engineer#3 never runs)
  br=$(_iso_q "MAX_TOKENS=0" "MAX_STEPS=0" "MAX_AGENTS=2" -- one two three)
  [ "$(jq -s '[.[]|select(.attributes["kit.denied"]=="true")]|length' "$br")" = "1" ] || { echo "FAIL: breach run not exactly 1 denied span"; fail=1; }
  [ "$(jq -s '[.[]|select(.attributes["agent.id"]=="engineer")]|length' "$br")" = "2" ] || { echo "FAIL: breach run expected 2 child spans (1 ok engineer + 1 denied), halt not honored"; fail=1; }
  # the denied span feeds the scorecard adapter to a denied step
  [ "$(sh "$here/otel-to-scorecard.sh" "$br" | jq '[.[]|select(.steps[].outcome=="denied")]|length')" -ge 1 ] || { echo "FAIL: denied not mapped to scorecard"; fail=1; }
  rm -f "$br"
  # E3-escalation (fail-closed pause): breach with NO verdict written -> loop stops here,
  # gate span carries kit.escalated=pending + kit.denied; engineer#3 does NOT run. The resume
  # positive is the next case; this is the load-bearing NEGATIVE (a dead loop -> 0 spans, an
  # always-proceed loop -> 3 engineer spans; both fail). No verdict is pre-placed.
  br2=$(_iso_q "MAX_TOKENS=0" "MAX_STEPS=0" "MAX_AGENTS=2" -- one two three)
  [ "$(jq -s '[.[]|select(.attributes["kit.escalated"]=="pending")]|length' "$br2")" = "1" ] \
    || { echo "FAIL: breach without a verdict did not record kit.escalated=pending (fail-closed pause)"; fail=1; }
  [ "$(jq -s '[.[]|select(.attributes["agent.id"]=="engineer")]|length' "$br2")" = "2" ] \
    || { echo "FAIL: paused run advanced past the breach (no-progress fail-closed violated)"; fail=1; }
  rm -f "$br2"
  # E3-escalation (raise-ceiling resume): breach + a PRE-PLACED raise-ceiling verdict -> the loop
  # continues past the breach; the gate span carries kit.escalated=true + kit.verdict + kit.ratifier
  # (sourced from the verdict FILE), all 3 engineers run, NO denial. The OTEL_TRACE_ID opt-in makes
  # the breaching slice's escalation id deterministic so the verdict can be pre-placed.
  # Two runs (per-row model, no tally wipe): run 1 breaches and PAUSES; the FIXTURE HARNESS (never the
  # engineer role runner) then appends `RAISE <ROW> MAX_AGENTS=100` to the sandbox conf and writes the
  # raise-ceiling verdict; run 2 (NEW slice names — run 1's e3a/<slice> branches exist) re-checks the row,
  # continues past the breach and integrates. The OTEL_TRACE_ID opt-in makes the escalation id
  # deterministic so the verdict can be pre-placed. Variant B is run 2 WITHOUT the RAISE (the negative).
  rtid="esc-resume-$$"
  for rvar in raised noraise; do
    rdir=$(mktemp -d); rsand=$(mktemp -d); rtmp="$rsand/repo"; mkdir -p "$rtmp"
    rconf="$rsand/budget.conf"; rtally="$rsand/tally"; rout1=$(mktemp); rout2=$(mktemp); rerr=$(mktemp)
    printf 'MAX_TOKENS=0\nMAX_STEPS=0\nMAX_AGENTS=2\n' > "$rconf"
    ( cd "$rtmp"; git init -q; git config user.email e@x; git config user.name e
      echo seed > seed.txt; git add seed.txt; git commit -q -m seed )
    ( cd "$rtmp"
      HOME="$rsand" KIT_RUNAWAY_SANDBOX="$rsand" OTEL_TRACE_ID="$rtid" KIT_ESCALATION_DIR="$rdir" \
        OTEL_TRACE_FILE="$rout1" RUNAWAY_BUDGET_CONFIG="$rconf" RUNAWAY_TALLY="$rtally" \
        "$here/orchestrator-run.sh" one two three >/dev/null 2>&1 ) || true
    [ "$(jq -s '[.[]|select(.attributes["kit.escalated"]=="pending")]|length' "$rout1")" = "1" ] \
      || { echo "FAIL: resume ($rvar) run 1 did not breach and pause (kit.escalated=pending)"; fail=1; }
    # the harness plays the human and rules raise-ceiling on run 2's breach (run 1's tally still sits at the
    # ceiling, so run 2's FIRST step re-breaches). The RAISE line cannot be appended BEFORE run 2: a row
    # already lifted never breaches, so no verdict would ever be consumed and the re-check would go
    # unexercised. So the raised variant runs a COPY of the scripts whose escalate.sh is a harness shim:
    # when the loop raises the record, the shim (the human) appends the RAISE line — after the step graded
    # STOP, before the loop re-checks. The engineer role runner never touches the conf.
    printf '{"option":"raise-ceiling","note":"selftest","ratifier_id":"selftest@kit"}' \
      > "$rdir/$(printf '%s' "$rtid.uno" | tr -c 'A-Za-z0-9._-' '_').verdict"
    rrun="$here/orchestrator-run.sh"
    if [ "$rvar" = raised ]; then
      cp -R "$here" "$rsand/scripts"; mv "$rsand/scripts/escalate.sh" "$rsand/scripts/escalate-real.sh"
      cat > "$rsand/scripts/escalate.sh" <<'SHIM'
#!/bin/sh
sh "$(dirname "$0")/escalate-real.sh" "$@" || exit $?
[ "$1" != raise ] || printf 'RAISE SELFTEST-ROW MAX_AGENTS=100\n' >> "$HARNESS_CONF"
SHIM
      rrun="$rsand/scripts/orchestrator-run.sh"
    fi
    ( cd "$rtmp"
      HOME="$rsand" KIT_RUNAWAY_SANDBOX="$rsand" OTEL_TRACE_ID="$rtid" KIT_ESCALATION_DIR="$rdir" \
        OTEL_TRACE_FILE="$rout2" RUNAWAY_BUDGET_CONFIG="$rconf" RUNAWAY_TALLY="$rtally" HARNESS_CONF="$rconf" \
        "$rrun" uno dos tres >/dev/null 2>"$rerr" ) || true
    if [ "$rvar" = raised ]; then
      [ "$(jq -s '[.[]|select(.attributes["kit.escalated"]=="true")]|length' "$rout2")" = "1" ] \
        || { echo "FAIL: raise-ceiling verdict did not resume the loop (no kit.escalated=true span)"; fail=1; }
      [ "$(jq -s '[.[]|select(.attributes["kit.verdict"]=="raise-ceiling")]|length' "$rout2")" = "1" ] \
        || { echo "FAIL: resumed span missing kit.verdict=raise-ceiling"; fail=1; }
      [ "$(jq -s '[.[]|select(.attributes["agent.id"]=="engineer")]|length' "$rout2")" = "3" ] \
        || { echo "FAIL: raise-ceiling did not continue past the breach (expected 3 engineer spans)"; fail=1; }
      [ "$(jq -s '[.[]|select(.attributes["kit.denied"]=="true")]|length' "$rout2")" = "0" ] \
        || { echo "FAIL: raise-ceiling resume wrongly recorded a denial"; fail=1; }
      [ -f "$rtmp/built-by-uno.txt" ] && [ -f "$rtmp/built-by-tres.txt" ] \
        || { echo "FAIL: raise-ceiling resume did not integrate run 2's slices"; fail=1; }
    else
      [ "$(jq -s '[.[]|select(.attributes["kit.verdict"]=="raise-ceiling" and .attributes["kit.denied"]=="true" and .attributes["kit.escalated"]=="true" and .status.code=="ERROR")]|length' "$rout2")" = "1" ] \
        || { echo "FAIL: raise-ceiling with NO RAISE in effect did not record an ERROR denial span"; fail=1; }
      [ "$(jq -s '[.[]|select(.name=="agent:engineer")]|length' "$rout2")" = "0" ] \
        || { echo "FAIL: raise-ceiling with NO RAISE in effect continued past the breach"; fail=1; }
      [ "$(jq -s '[.[]|select(.attributes.slice=="dos")]|length' "$rout2")" = "0" ] \
        || { echo "FAIL: raise-ceiling with NO RAISE in effect still carried a span for the breached slice dos (continued past the breach)"; fail=1; }
      [ "$(jq -s '[.[]|select(.name=="gate:guard")]|length' "$rout2")" = "1" ] \
        || { echo "FAIL: raise-ceiling with NO RAISE in effect did not leave exactly one gate:guard span"; fail=1; }
      grep -q "no sufficient RAISE for SELFTEST-ROW is in effect (check rc=" "$rerr" \
        || { echo "FAIL: no-RAISE halt did not print the 'no sufficient RAISE for <ROW> is in effect (check rc=<rc>)' sentence on stderr"; fail=1; }
      grep -q "add 'RAISE SELFTEST-ROW MAX_TOKENS=<n>' and/or 'MAX_AGENTS=<n>' / 'MAX_STEPS=<n>' for the breached dimension" "$rerr" \
        || { echo "FAIL: no-RAISE halt hint does not name all three dimensions (MAX_TOKENS / MAX_AGENTS / MAX_STEPS)"; fail=1; }
    fi
    rm -rf "$rdir" "$rsand"; rm -f "$rout1" "$rout2" "$rerr"
  done
  # E3-escalation (anti-spoof): the engineer role-runner MUST NOT inherit OTEL_TRACE_ID /
  # KIT_ESCALATION_DIR / KIT_RUN_DIR -- else it could compute the deterministic escalation id and
  # pre-write its OWN verdict file to self-ratify a breach. Probe the role-runner's actual env.
  eprobe=$(mktemp); erun=$(mktemp); export E3_ENVPROBE="$eprobe"
  cat > "$erun" <<'PROBE'
#!/bin/sh
{ echo "OTEL_TRACE_ID=[${OTEL_TRACE_ID:-UNSET}]"
  echo "KIT_ESCALATION_DIR=[${KIT_ESCALATION_DIR:-UNSET}]"
  echo "KIT_RUN_DIR=[${KIT_RUN_DIR:-UNSET}]"
  echo "RUNAWAY_TALLY=[${RUNAWAY_TALLY:-UNSET}]"
  echo "RUNAWAY_BUDGET_CONFIG=[${RUNAWAY_BUDGET_CONFIG:-UNSET}]"
  echo "KIT_RUNAWAY_SANDBOX=[${KIT_RUNAWAY_SANDBOX:-UNSET}]"
  echo "KIT_RUN_ROW=[${KIT_RUN_ROW:-UNSET}]"; } >> "$E3_ENVPROBE"
PROBE
  chmod +x "$erun"
  esand=$(mktemp -d); etmp="$esand/repo"; mkdir -p "$etmp"
  eout=$(mktemp); econf="$esand/budget.conf"; etally="$esand/tally"
  printf 'MAX_TOKENS=0\nMAX_STEPS=0\nMAX_AGENTS=0\n' > "$econf"
  ( cd "$etmp"; git init -q; git config user.email e@x; git config user.name e
    echo seed > seed.txt; git add seed.txt; git commit -q -m seed
    HOME="$esand" KIT_RUNAWAY_SANDBOX="$esand" \
      OTEL_TRACE_ID="leak-probe" KIT_ESCALATION_DIR="/tmp/leak-esc" KIT_RUN_DIR="/tmp/leak-run" \
      OTEL_TRACE_FILE="$eout" RUNAWAY_BUDGET_CONFIG="$econf" RUNAWAY_TALLY="$etally" \
      ROLE_RUNNER="$erun" "$here/orchestrator-run.sh" alpha >/dev/null 2>&1 )
  unset E3_ENVPROBE
  grep -q 'OTEL_TRACE_ID=\[UNSET\]' "$eprobe"      || { echo "FAIL: role-runner LEAKED OTEL_TRACE_ID (anti-spoof: engineer can forge a verdict)"; fail=1; }
  grep -q 'KIT_ESCALATION_DIR=\[UNSET\]' "$eprobe" || { echo "FAIL: role-runner LEAKED KIT_ESCALATION_DIR (anti-spoof: engineer can locate the verdict channel)"; fail=1; }
  grep -q 'KIT_RUN_DIR=\[UNSET\]' "$eprobe"        || { echo "FAIL: role-runner LEAKED KIT_RUN_DIR"; fail=1; }
  # the metering dials: a live engineer that could see/redirect the tally, the config, the sandbox dial or
  # its own row could re-point its meter or charge another row — none may reach it.
  for _sv in RUNAWAY_TALLY RUNAWAY_BUDGET_CONFIG KIT_RUNAWAY_SANDBOX KIT_RUN_ROW; do
    grep -q "^$_sv=\[UNSET\]" "$eprobe" || { echo "FAIL: role-runner LEAKED $_sv (metering dial visible to the engineer)"; fail=1; }
  done
  grep -q 'KIT_RUN_DIR=' "$eprobe" || { echo "FAIL: env probe never ran (scrub legs vacuous)"; fail=1; }
  rm -rf "$esand"; rm -f "$eprobe" "$erun" "$eout"
  # E3b conflict-safe: two slices write the SAME file (conflicting fixture) -> overlap DETECTED, the run
  # REFUSES integration (exits nonzero), emits a kit.conflict span, does NOT merge (no silent corruption).
  csand=$(mktemp -d); ctmp="$csand/repo"; mkdir -p "$ctmp"
  cout=$(mktemp); cconf="$csand/budget.conf"; ctally="$csand/tally"
  printf 'MAX_TOKENS=0\nMAX_STEPS=0\nMAX_AGENTS=0\n' > "$cconf"
  crc=0
  ( cd "$ctmp"; git init -q; git config user.email e@x; git config user.name e
    echo seed > seed.txt; git add seed.txt; git commit -q -m seed
    HOME="$csand" KIT_RUNAWAY_SANDBOX="$csand" \
      FIXTURE_CONFLICT_FILE=shared.txt OTEL_TRACE_FILE="$cout" \
      RUNAWAY_BUDGET_CONFIG="$cconf" RUNAWAY_TALLY="$ctally" \
      "$here/orchestrator-run.sh" ca cb >/dev/null 2>&1 ) || crc=$?
  [ "$crc" -ne 0 ] || { echo "FAIL: overlapping slices did not refuse integration (expected nonzero exit)"; fail=1; }
  [ "$(jq -s '[.[]|select(.attributes["kit.conflict"]=="true")]|length' "$cout")" = "1" ] \
    || { echo "FAIL: no kit.conflict span emitted on overlap (detect-by-inspection missing)"; fail=1; }
  [ ! -f "$ctmp/shared.txt" ] || { echo "FAIL: overlap silently integrated shared.txt (corruption not prevented)"; fail=1; }
  rm -rf "$csand"; rm -f "$cout"
  # POSITIVE complement: disjoint slices still integrate cleanly (the existing clean-run assertion already
  # covers this, but re-confirm no kit.conflict on a disjoint run):
  dj=$(_iso_q "MAX_TOKENS=0" "MAX_STEPS=0" "MAX_AGENTS=0" -- da db)
  [ "$(jq -s '[.[]|select(.attributes["kit.conflict"]=="true")]|length' "$dj")" = "0" ] \
    || { echo "FAIL: disjoint run wrongly flagged a conflict"; fail=1; }
  rm -f "$dj"
  # E3b conflict-safe (DUELING RENAME — the rename-divergence evasion): two slices rename the SAME
  # source file to DIFFERENT targets. --no-renames surfaces the deleted source in both diffs, so the
  # overlap on the source is detected (a plain --name-only with rename detection would see disjoint
  # {A} vs {B} and MISS it). Asserts kit.conflict fires (evasion closed) + the run refuses.
  rsand=$(mktemp -d); rtmp="$rsand/repo"; mkdir -p "$rtmp"
  rout=$(mktemp); rconf="$rsand/budget.conf"; rtally="$rsand/tally"
  printf 'MAX_TOKENS=0\nMAX_STEPS=0\nMAX_AGENTS=0\n' > "$rconf"
  rrc=0
  ( cd "$rtmp"; git init -q; git config user.email e@x; git config user.name e
    echo seed > seed.txt; git add seed.txt; git commit -q -m seed
    echo orig > F.txt; git add F.txt; git commit -q -m "add F"
    HOME="$rsand" KIT_RUNAWAY_SANDBOX="$rsand" \
      FIXTURE_RENAME_SRC=F.txt OTEL_TRACE_FILE="$rout" \
      RUNAWAY_BUDGET_CONFIG="$rconf" RUNAWAY_TALLY="$rtally" \
      "$here/orchestrator-run.sh" rra rrb >/dev/null 2>&1 ) || rrc=$?
  [ "$rrc" -ne 0 ] || { echo "FAIL: dueling-rename did not refuse integration"; fail=1; }
  [ "$(jq -s '[.[]|select(.attributes["kit.conflict"]=="true")]|length' "$rout")" -ge 1 ] \
    || { echo "FAIL: dueling-rename EVADED detection (no kit.conflict span) — rename-divergence not closed"; fail=1; }
  [ ! -f "$rtmp/renamed-by-rra.txt" ] || { echo "FAIL: dueling-rename silently integrated a side (tree not clean)"; fail=1; }
  rm -rf "$rsand"; rm -f "$rout"
  # E3-merge-atomicity (load-bearing NEGATIVE): two slices with DISJOINT changed-file sets that still
  # collide at the merge FLOOR. clashF creates path 'clash' as a FILE; clashD creates 'clash/child' (a
  # file under dir 'clash'). Name-only sets {clash} vs {clash/child} are disjoint so DETECTION passes; the
  # merge floor then merges clashF (lands 'clash') and merging clashD FAILS (cannot create a dir over a
  # file) -> floor trips. WITHOUT the atomic reset, clashF stays committed (partial-integration residual);
  # WITH it, HEAD resets to the cut-point base. Asserts refuse + kit.conflict(merge:clashD) + HEAD==base
  # + no residual 'clash'. This is the case the unfixed code FAILS (HEAD advanced) and the fix makes pass.
  msand=$(mktemp -d); mtmp="$msand/repo"; mkdir -p "$mtmp"
  mout=$(mktemp); mconf="$msand/budget.conf"; mtally="$msand/tally"; mrun=$(mktemp)
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
    HOME="$msand" KIT_RUNAWAY_SANDBOX="$msand" \
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
  rm -rf "$msand"; rm -f "$mout" "$mrun"
  # E3-merge-atomicity (POSITIVE liveness anchor): a disjoint clean run still INTEGRATES — HEAD advances
  # past base and both artifacts are present. Guards against a regression where the atomic reset fires
  # spuriously on the success path (an always-reset bug integrates nothing and fails here).
  psand=$(mktemp -d); ptmp="$psand/repo"; mkdir -p "$ptmp"
  pout=$(mktemp); pconf="$psand/budget.conf"; ptally="$psand/tally"
  printf 'MAX_TOKENS=0\nMAX_STEPS=0\nMAX_AGENTS=0\n' > "$pconf"
  ( cd "$ptmp"; git init -q; git config user.email e@x; git config user.name e
    echo seed > seed.txt; git add seed.txt; git commit -q -m seed )
  pbase=$(git -C "$ptmp" rev-parse HEAD); prc=0
  ( cd "$ptmp"
    HOME="$psand" KIT_RUNAWAY_SANDBOX="$psand" \
      OTEL_TRACE_FILE="$pout" RUNAWAY_BUDGET_CONFIG="$pconf" RUNAWAY_TALLY="$ptally" \
      "$here/orchestrator-run.sh" pa pb >/dev/null 2>&1 ) || prc=$?
  [ "$prc" -eq 0 ] || { echo "FAIL: disjoint clean run did not exit 0 (prc=$prc)"; fail=1; }
  [ "$(git -C "$ptmp" rev-parse HEAD)" != "$pbase" ] \
    || { echo "FAIL: disjoint clean run did not integrate (HEAD == base) — reset fired spuriously on success"; fail=1; }
  { [ -f "$ptmp/built-by-pa.txt" ] && [ -f "$ptmp/built-by-pb.txt" ]; } \
    || { echo "FAIL: disjoint clean run missing integrated artifacts"; fail=1; }
  [ "$(jq -s '[.[]|select(.attributes["kit.conflict"]=="true")]|length' "$pout")" = "0" ] \
    || { echo "FAIL: disjoint clean run wrongly flagged a conflict"; fail=1; }
  rm -rf "$psand"; rm -f "$pout"
  # KIT_RUN_ROW is REQUIRED and grammar-checked (the guard grades per row): unset, empty and invalid all
  # exit rc 2 naming KIT_RUN_ROW, before any worktree is made; a valid row is the liveness anchor.
  for rcase in unset invalid-lower invalid-space invalid-dash-first invalid-long valid; do
    ksand=$(mktemp -d); ktmp="$ksand/repo"; mkdir -p "$ktmp"
    kconf="$ksand/budget.conf"; kerr=$(mktemp); kout=$(mktemp); krc=0
    printf 'MAX_TOKENS=0\nMAX_STEPS=0\nMAX_AGENTS=0\n' > "$kconf"
    ( cd "$ktmp"; git init -q; git config user.email e@x; git config user.name e
      echo seed > seed.txt; git add seed.txt; git commit -q -m seed )
    case "$rcase" in
      unset)            krow="" ;;
      invalid-lower)    krow="row-1" ;;
      invalid-space)    krow="ROW 1" ;;
      invalid-dash-first) krow="-ROW" ;;
      invalid-long)     krow="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" ;;
      valid)            krow="SELFTEST-ROW" ;;
    esac
    ( cd "$ktmp"
      if [ "$rcase" = unset ]; then unset KIT_RUN_ROW; else KIT_RUN_ROW="$krow"; fi
      HOME="$ksand" KIT_RUNAWAY_SANDBOX="$ksand" OTEL_TRACE_FILE="$kout" \
        RUNAWAY_BUDGET_CONFIG="$kconf" RUNAWAY_TALLY="$ksand/tally" \
        "$here/orchestrator-run.sh" ka >/dev/null 2>"$kerr" ) || krc=$?
    if [ "$rcase" = valid ]; then
      [ "$krc" -eq 0 ] || { echo "FAIL: a valid KIT_RUN_ROW did not run (rc=$krc)"; fail=1; }
    else
      [ "$krc" -eq 2 ] || { echo "FAIL: KIT_RUN_ROW $rcase expected rc 2, got $krc"; fail=1; }
      grep -q "KIT_RUN_ROW" "$kerr" || { echo "FAIL: KIT_RUN_ROW $rcase rc 2 message does not name KIT_RUN_ROW"; fail=1; }
      [ -z "$(git -C "$ktmp" branch --list 'e3a/*')" ] || { echo "FAIL: KIT_RUN_ROW $rcase still created a slice branch"; fail=1; }
    fi
    rm -rf "$ksand"; rm -f "$kerr" "$kout"
  done
  # SEC-1: a built slice that touches a CONTROL-PLANE path is refused BEFORE any merge (a slice must never be
  # able to land a `RAISE <ROW>` line in .kit/budget.conf or replace the guard). Whole-integration refusal:
  # rc 1, a trusted kit.controlplane span, the stderr sentence, HEAD == base, nothing merged, the conf untouched.
  # The clean fan-out legs above (slices write only built-by-*.txt) are the negative: they must NOT be refused.
  for cpath in .kit/budget.conf scripts/runaway-guard.sh; do
    xsand=$(mktemp -d); xtmp="$xsand/repo"; mkdir -p "$xtmp"
    xout=$(mktemp); xerr=$(mktemp); xconf="$xsand/budget.conf"; xrun=$(mktemp)
    printf 'MAX_TOKENS=0\nMAX_STEPS=0\nMAX_AGENTS=0\n' > "$xconf"; cp "$xconf" "$xsand/conf.orig"
    cat > "$xrun" <<'CPRUN'
#!/bin/sh
slice="$1"; wt="$2"; cd "$wt" || exit 1
case "$slice" in
  evil*) mkdir -p "$(dirname "$CP_PATH")"; printf 'RAISE SELFTEST-ROW MAX_AGENTS=999\n' > "$CP_PATH"; git add -A; git commit -q -m "cp($slice)" ;;
  *)     printf 'ok\n' > "built-by-$slice.txt"; git add -A; git commit -q -m "ok($slice)" ;;
esac
CPRUN
    chmod +x "$xrun"
    ( cd "$xtmp"; git init -q; git config user.email e@x; git config user.name e
      echo seed > seed.txt; git add seed.txt; git commit -q -m seed )
    xbase=$(git -C "$xtmp" rev-parse HEAD); xrc=0
    ( cd "$xtmp"
      HOME="$xsand" KIT_RUNAWAY_SANDBOX="$xsand" CP_PATH="$cpath" \
        ROLE_RUNNER="$xrun" OTEL_TRACE_FILE="$xout" \
        RUNAWAY_BUDGET_CONFIG="$xconf" RUNAWAY_TALLY="$xsand/tally" \
        "$here/orchestrator-run.sh" goodx evilx >/dev/null 2>"$xerr" ) || xrc=$?
    [ "$xrc" -eq 1 ] || { echo "FAIL: control-plane slice ($cpath) expected rc 1, got $xrc"; fail=1; }
    [ "$(jq -s '[.[]|select(.attributes["kit.controlplane"]=="true" and .attributes["kit.denied"]=="true" and .status.code=="ERROR")]|length' "$xout")" = "1" ] \
      || { echo "FAIL: control-plane slice ($cpath) did not emit exactly one kit.controlplane+kit.denied ERROR span"; fail=1; }
    grep -q "slice 'evilx' touches a control-plane path ($cpath) — integration refused" "$xerr" \
      || { echo "FAIL: control-plane slice ($cpath) refusal sentence missing on stderr"; fail=1; }
    [ "$(git -C "$xtmp" rev-parse HEAD)" = "$xbase" ] \
      || { echo "FAIL: control-plane slice ($cpath) left a merge on HEAD (the clean sibling slice was integrated too)"; fail=1; }
    { [ ! -e "$xtmp/built-by-goodx.txt" ] && [ ! -e "$xtmp/$cpath" ]; } \
      || { echo "FAIL: control-plane slice ($cpath) left an integrated artifact in the tree"; fail=1; }
    cmp -s "$xconf" "$xsand/conf.orig" || { echo "FAIL: control-plane slice ($cpath) changed the budget config"; fail=1; }
    rm -rf "$xsand"; rm -f "$xout" "$xerr" "$xrun"
  done
  # SEC-1 bypasses (fix round 2). The role runner commits through git PLUMBING (`update-index --cacheinfo`), because
  # `git add` / a `printf` into the path would fold to the REAL entry on a case-insensitive filesystem and prove
  # nothing. F1: case variants. F2: a name git C-quotes (byte >= 0x80, `"`), a newline in a name. F5: the wider list.
  eacute=$(printf '\303\251'); nlpath=$(printf 'docs/a\nb.txt')
  # F1-RESIDUAL: APFS folds far more than ASCII (Kelvin U+212A -> k, long-s U+017F -> s, NFD == NFC), so ANY byte
  # >= 0x80 is refused outright (over-denies by design: an accented name under docs/ too). Bytes as octal escapes, no raw non-ASCII here.
  longs=$(printf '\305\277cripts/x.sh'); kelvin=$(printf '.\342\204\252it/x.conf'); rawbad=$(printf 'a\377\001z')
  # F2-RESIDUAL: run one leg under a UTF-8 locale (tr aborts on invalid UTF-8 outside the C locale).
  utf8loc=C.UTF-8; for _l in en_US.UTF-8 en_US.utf8; do locale -a 2>/dev/null | grep -qx "$_l" && { utf8loc=$_l; break; } || true; done
  for pcase in "F1-case-dir:.KIT/budget.conf" "F1-case-scripts:Scripts/runaway-guard.sh" \
               "F2-nonascii:.github/workflows/${eacute}.yml" 'F2-dquote:.github/workflows/a"b.yml' \
               "F2-newline:$nlpath" "F5-gitattributes:.gitattributes" "F5-profiles:profiles/x.md" \
               "F1R-longs:$longs" "F1R-kelvin:$kelvin" "F1R-outside-cp:docs/${eacute}.md" "F2R-locale:$rawbad"; do
    plabel=${pcase%%:*}; ppath=${pcase#*:}
    ploc=""; [ "$plabel" != F2R-locale ] || ploc=$utf8loc
    psand=$(mktemp -d); ptmp="$psand/repo"; mkdir -p "$ptmp"
    pout=$(mktemp); perr=$(mktemp); pconf="$psand/budget.conf"; prun=$(mktemp)
    printf 'MAX_TOKENS=0\nMAX_STEPS=0\nMAX_AGENTS=0\n' > "$pconf"
    cat > "$prun" <<'PLRUN'
#!/bin/sh
slice="$1"; wt="$2"; cd "$wt" || exit 1
case "$slice" in
  evil*) blob=$(printf 'RAISE SELFTEST-ROW MAX_AGENTS=999\n' | git hash-object -w --stdin)
         git update-index --add --cacheinfo 100644,"$blob","$PL_PATH"; git commit -q -m "pl($slice)" ;;
  *)     printf 'ok\n' > "built-by-$slice.txt"; git add -A; git commit -q -m "ok($slice)" ;;
esac
PLRUN
    chmod +x "$prun"
    ( cd "$ptmp"; git init -q; git config user.email e@x; git config user.name e
      echo seed > seed.txt; git add seed.txt; git commit -q -m seed )
    pbase=$(git -C "$ptmp" rev-parse HEAD); prc=0
    ( cd "$ptmp"
      [ -z "$ploc" ] || export LC_ALL="$ploc"
      HOME="$psand" KIT_RUNAWAY_SANDBOX="$psand" PL_PATH="$ppath" \
        ROLE_RUNNER="$prun" OTEL_TRACE_FILE="$pout" \
        RUNAWAY_BUDGET_CONFIG="$pconf" RUNAWAY_TALLY="$psand/tally" \
        "$here/orchestrator-run.sh" goodp evilp >/dev/null 2>"$perr" ) || prc=$?
    [ "$prc" -eq 1 ] || { echo "FAIL: control-plane bypass ($plabel) expected rc 1, got $prc"; fail=1; }
    [ "$(jq -s '[.[]|select(.attributes["kit.controlplane"]=="true" and .attributes["kit.denied"]=="true" and .status.code=="ERROR")]|length' "$pout")" = "1" ] \
      || { echo "FAIL: control-plane bypass ($plabel) did not emit exactly one kit.controlplane+kit.denied ERROR span"; fail=1; }
    [ "$(git -C "$ptmp" rev-parse HEAD)" = "$pbase" ] \
      || { echo "FAIL: control-plane bypass ($plabel) left a merge on HEAD"; fail=1; }
    rm -rf "$psand"; rm -f "$pout" "$perr" "$prun"
  done
  # F4: the orchestrator's own git actuation runs with hooks DISABLED. A role runner shares the main .git, so it can
  # point core.hooksPath (shared config) at a post-merge hook; after a CLEAN integration the marker must NOT exist
  # (and the integration itself must have happened, so the leg is not vacuous).
  hsand=$(mktemp -d); htmp="$hsand/repo"; mkdir -p "$htmp" "$hsand/hk"
  hout=$(mktemp); hconf="$hsand/budget.conf"; hrun=$(mktemp)
  printf 'MAX_TOKENS=0\nMAX_STEPS=0\nMAX_AGENTS=0\n' > "$hconf"
  printf '#!/bin/sh\n: > "%s/marker"\n' "$hsand" > "$hsand/hk/post-merge"; chmod +x "$hsand/hk/post-merge"
  cat > "$hrun" <<'HKRUN'
#!/bin/sh
slice="$1"; wt="$2"; cd "$wt" || exit 1
printf 'ok\n' > "built-by-$slice.txt"; git add -A; git commit -q -m "ok($slice)"
git config core.hooksPath "$HK_DIR"
HKRUN
  chmod +x "$hrun"
  ( cd "$htmp"; git init -q; git config user.email e@x; git config user.name e
    echo seed > seed.txt; git add seed.txt; git commit -q -m seed )
  hrc=0
  ( cd "$htmp"
    HOME="$hsand" KIT_RUNAWAY_SANDBOX="$hsand" HK_DIR="$hsand/hk" \
      ROLE_RUNNER="$hrun" OTEL_TRACE_FILE="$hout" \
      RUNAWAY_BUDGET_CONFIG="$hconf" RUNAWAY_TALLY="$hsand/tally" \
      "$here/orchestrator-run.sh" hooka >/dev/null 2>&1 ) || hrc=$?
  [ "$hrc" -eq 0 ] && [ -f "$htmp/built-by-hooka.txt" ] \
    || { echo "FAIL: hook leg did not integrate cleanly (rc=$hrc) — the leg is vacuous"; fail=1; }
  [ ! -e "$hsand/marker" ] || { echo "FAIL: a slice-installed post-merge hook RAN inside the orchestrator's merge (core.hooksPath not disabled)"; fail=1; }
  rm -rf "$hsand"; rm -f "$hout" "$hrun"
  [ "$fail" -eq 0 ] || { echo "orchestrator-run --selftest: FAIL" >&2; return 1; }
  echo "orchestrator-run --selftest: OK (clean fan-out+integrate, breach halt+denied, scorecard maps denied, escalation pause+resume(two runs)+no-RAISE halt, KIT_RUN_ROW required, role-runner env scrubbed, conflict-safe detect+refuse incl. dueling-rename, integration atomic on floor-trip, control-plane slice refused before any merge)"; return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "")         demo ;;
  *)          run "$@" ;;
esac
