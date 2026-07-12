#!/bin/sh
# incept-first-run-green.sh — the STACK-AGNOSTIC "first-run green" detector (KW3).
#
# Proves a generalizable property, not a hardcoded five-item patch:
#
#   For an archetype's reference scaffold, every mechanism the archetype is expected to ship is
#   activated to a GREEN-or-LEGIBLY-SKIPPED state — no mechanism is present-but-misconfigured-red.
#
# The check body carries ZERO stack-specific knowledge: all archetype specifics (which mechanisms,
# their config-shape assertions, preconditions, skip-reasons) live in a per-archetype MANIFEST
# (manifest-<stack>.txt). KW4/KW8 add one manifest per stack — same engine, zero check rework.
#
#   sh incept-first-run-green.sh --selftest              # the GATED proof (good fixture + 5 negatives + lock self-negative)
#   sh incept-first-run-green.sh [--manifest M] [TARGET] # evaluate an archetype dir (default profiles/typescript-node)
# Exit: 0 = every mechanism GREEN-or-SKIPPED/N-A . 1 = a MISCONFIGURED-RED mechanism . 2 = usage/setup.
# POSIX sh; dash-clean. Fail-closed: a missing/unreadable manifest or ci.yml, or an unknown predicate
# verb, resolves to MISCONFIGURED / error — never a silent pass.
#
# Config-shape assertions are the ALWAYS-RUN, tool-free, deterministic core — and, as of CP-5, ALL
# this script claims to be. The old "opportunistic LIVE-GATE" layer was DELETED (see the note at its
# former site below): it skipped when the tool was absent — and kit CI never installed semgrep, so it
# ALWAYS skipped — scanned the wrong scope when it did run, and was advisory-only. It could not fail.
# The REAL live proof is the `artifact-gate` CI job: export -> incept -> the adopter's own
# `verify.sh --require` + the exact emitted SAST command, ON THE ARTIFACT, blocking.
#
# HONEST CEILING: proves the shipped archetype's gates are green-or-legibly-skipped on first run;
# cannot prove a mechanism no scaffold exercises (an adopter who later adds payments hits wiring this
# lock never saw). Live external attestation (real SLSA, a live cloud DB) is the adopter's CI, not here.
set -euf

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

# --- Resolve the repo root across authoring (scratchpad/kw3) + installed (conformance/) layouts. ---
if [ -d "$SCRIPT_DIR/../profiles" ]; then
  REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
elif [ -d "$SCRIPT_DIR/../../profiles" ]; then
  REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
else
  REPO_ROOT="$SCRIPT_DIR"
fi

# --- Fixtures + manifest default resolution (env-overridable so a neutered COPY run out of a tmp dir
#     still finds the originals; mirrors the sibling locks' co-located-then-installed resolution). ---
FIXTURES="${KW3_FIXTURES:-$SCRIPT_DIR/fixtures}"
MANIFEST_DEFAULT="${KW3_MANIFEST:-}"
resolve_manifest_default() {  # echoes a manifest path for TARGET basename, or empty
  _base="$1"
  if [ -n "$MANIFEST_DEFAULT" ]; then printf '%s\n' "$MANIFEST_DEFAULT"; return 0; fi
  for _cand in \
    "$SCRIPT_DIR/manifest-$_base.txt" \
    "$SCRIPT_DIR/incept-manifests/$_base.txt" \
    "$REPO_ROOT/conformance/incept-manifests/$_base.txt"; do
    [ -f "$_cand" ] && { printf '%s\n' "$_cand"; return 0; }
  done
  return 1
}

# ===========================================================================================
# PREDICATE ENGINE — the stack-agnostic vocabulary. NO archetype token appears here; the manifest
# supplies every regex/path. Returns 0 = holds, 1 = does not hold, 2 = unknown verb (fail-closed).
# (The function-def line below is the neutralization target for the lock self-negative — do not rename.)
# ===========================================================================================
predicate_holds() {
  _pd="$1"; _verb="$2"; _arg="$3"
  # present/absent evaluate the LIVE config (comment-stripped CI_CODE) so a token that appears only
  # in a comment neither satisfies `present` nor trips `absent` (the R1/agentops-sensor lesson). The
  # `comment` verb matches the RAW ci.yml — for intentional in-repo explanations (e.g. the provenance
  # legible skip-reason, which is by-design a comment).
  case "$_verb" in
    always)  return 0 ;;
    present) grep -Eq -- "$_arg" "$CI_CODE" 2>/dev/null ;;
    absent)  if grep -Eq -- "$_arg" "$CI_CODE" 2>/dev/null; then return 1; else return 0; fi ;;
    comment) grep -Eq -- "$_arg" "$CI" 2>/dev/null ;;
    scaffold)
      [ -d "$_pd/scaffold" ] || return 1
      grep -rEq -- "$_arg" "$_pd/scaffold" 2>/dev/null ;;
    scaffoldfile)
      # arg = "<relpath> <ERE>" — grep <ERE> within scaffold/<relpath> ONLY (precise, file-scoped:
      # binds the assertion to a NAMED scaffold file, e.g. the .gitignore build-output exclusion,
      # rather than any file under scaffold/). Missing file -> does not hold.
      _sf=${_arg%% *}; case "$_arg" in *' '*) _sre=${_arg#* } ;; *) _sre='' ;; esac
      [ -f "$_pd/scaffold/$_sf" ] || return 1
      grep -Eq -- "$_sre" "$_pd/scaffold/$_sf" 2>/dev/null ;;
    file)    [ -f "$_pd/$_arg" ] ;;
    *)       echo "MISCONFIGURED: unknown predicate verb '$_verb' (fail-closed)" >&2; return 2 ;;
  esac
}

# --- CP-2: the opportunistic "live-gate" was DELETED here. It could not fail. ---
#
# It claimed to be a bonus live proof that a fresh incept lands green. It was three ways vacuous:
#   * it SKIPPED when the tool was absent — and kit CI never installed semgrep, so it always skipped;
#   * if it HAD run, it scanned `$DIR/scaffold/src` — NOT `.` — the exact single-subdir narrowing the
#     emitted CI's own comment forbids, so it would have scanned a clean subtree and missed the 22
#     blocking findings that were sitting in the kit's retained conformance/ + scripts/ + docs YAML;
#   * a non-zero result was ADVISORY ONLY and never touched the return code.
# So the one check that promised "first run is green" was structurally UNFALSIFIABLE, and CP-1 shipped
# under it for 119 versions. A check that cannot fail is worse than no check: it manufactures
# confidence. It is deleted rather than repaired.
#
# The REAL proof now lives in the `artifact-gate` CI job: export -> incept -> run the adopter's own
# `verify.sh --require` AND the exact emitted SAST command, ON THE ARTIFACT, blocking.
# The deterministic config-SHAPE assertions in the manifests below are unaffected — those work, and
# they are what this script is actually for.

# ===========================================================================================
# resolve_mechanism — evaluate the current block (shared vars: id/precond/whenabsent/asserts/
# skipreason/fixhint) against DIR/CI. Updates counters + RC. Prints the per-mechanism verdict.
# ===========================================================================================
resolve_mechanism() {
  [ -n "$id" ] || return 0
  _pv=${precond%% *}; case "$precond" in *' '*) _pa=${precond#* } ;; *) _pa='' ;; esac

  if predicate_holds "$DIR" "$_pv" "$_pa"; then
    # precondition holds -> the mechanism is expected live; evaluate config-shape asserts (ALL hold).
    _mis=0; _failed=''
    _oifs=$IFS; IFS='
'
    for _a in $asserts; do
      IFS=$_oifs
      [ -n "$_a" ] || { IFS='
'; continue; }
      _av=${_a%% *}; case "$_a" in *' '*) _aa=${_a#* } ;; *) _aa='' ;; esac
      if predicate_holds "$DIR" "$_av" "$_aa"; then :; else _mis=1; _failed=$_a; break; fi
      IFS='
'
    done
    IFS=$_oifs
    if [ "$_mis" = 0 ]; then
      echo "  [GREEN] $id — config-shape correct"
      GREENS=$((GREENS + 1))
    else
      echo "  [RED]   $id — MISCONFIGURED: assertion not satisfied: '$_failed'"
      echo "          fix: $fixhint"
      REDS=$((REDS + 1)); RC=1
    fi
  else
    if [ "$whenabsent" = na ]; then
      echo "  [N/A]   $id — $skipreason"
      NAS=$((NAS + 1))
    else
      echo "  [SKIP]  $id — $skipreason"
      SKIPS=$((SKIPS + 1))
    fi
  fi
}

reset_block() { id=''; precond=''; whenabsent='skip'; asserts=''; skipreason=''; fixhint=''; }

# ===========================================================================================
# run_check TARGET MANIFEST — parse the manifest block-by-block, resolve each mechanism, print a
# verdict + the honest ceiling. Sets RC (0 clean / 1 misconfigured-red / 2 setup error).
# ===========================================================================================
run_check() {
  DIR="$1"; MANIFEST="$2"; CI="$DIR/ci.yml"
  RC=0; GREENS=0; SKIPS=0; NAS=0; REDS=0
  [ -f "$MANIFEST" ] || { echo "MISCONFIGURED: manifest not found: $MANIFEST (fail-closed)" >&2; RC=2; return 2; }
  [ -f "$CI" ]       || { echo "MISCONFIGURED: ci.yml not found: $CI (fail-closed)" >&2; RC=2; return 2; }

  # LIVE-config view: strip `#` comments so present/absent assert the live YAML, not documentation.
  CI_CODE="${TMPDIR:-/tmp}/kw3-cicode-$$.yml"
  # Clean up the temp file on ANY exit path (incl. the fail-closed sed return below) — no $$-temp leak.
  trap 'rm -f "$CI_CODE"' EXIT
  sed 's/#.*//' "$CI" > "$CI_CODE" 2>/dev/null || { echo "MISCONFIGURED: cannot read ci.yml: $CI (fail-closed)" >&2; RC=2; return 2; }

  echo "first-run-green: archetype $DIR"
  echo "  manifest: $MANIFEST"

  reset_block
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    _key=${line%%:*}
    case "$line" in *': '*) _val=${line#*: } ;; *) _val='' ;; esac
    case "$_key" in
      id)           [ -n "$id" ] && resolve_mechanism; reset_block; id=$_val ;;
      precondition) precond=$_val ;;
      when-absent)  whenabsent=$_val ;;
      assert)       asserts="${asserts}${_val}
" ;;
      skip-reason)  skipreason=$_val ;;
      fix-hint)     fixhint=$_val ;;
      *)            : ;;
    esac
  done < "$MANIFEST"
  [ -n "$id" ] && resolve_mechanism

  echo "  ---"
  echo "  summary: $GREENS GREEN, $SKIPS SKIPPED-WITH-REASON, $NAS N/A, $REDS MISCONFIGURED-RED"
  echo "  honest ceiling: proves the shipped archetype's gates are green-or-legibly-skipped on first"
  echo "  run; cannot prove a mechanism no scaffold exercises. This is a CONFIG-SHAPE proof: it shows"
  echo "  the gates are WIRED, never that they PASS on a real tree. The artifact-gate CI job proves"
  echo "  that (export -> incept -> the adopter's verify.sh --require + the exact SAST command)."
  if [ "$REDS" -gt 0 ]; then
    echo "FAIL: $REDS misconfigured-red mechanism(s) — first run would NOT be green"
  else
    echo "OK: every expected mechanism is GREEN-or-legibly-SKIPPED on first run"
  fi
  rm -f "$CI_CODE"
  return "$RC"
}

# ===========================================================================================
# --selftest — the NON-VACUITY heart. Good fixture (liveness) + 5 mutated-config negatives + a
# mandatory LOCK SELF-NEGATIVE. Self-contained: fixtures under $FIXTURES, uses the delivered manifest.
# ===========================================================================================
selftest() {
  st=0
  MAN="$(resolve_manifest_default typescript-node)" \
    || { echo "selftest FAIL: cannot resolve the TS/Node manifest"; return 1; }

  # --- LIVENESS ANCHOR: the good fixture -> every mechanism GREEN-or-SKIPPED, exit 0. ---
  if out=$(KW3_NOLIVE=1 sh "$0" --manifest "$MAN" "$FIXTURES/good" 2>&1); then
    if printf '%s\n' "$out" | grep -q '\[RED\]'; then
      echo "selftest FAIL: good fixture emitted a [RED] verdict"; printf '%s\n' "$out" | sed 's/^/    /'; st=1
    else
      echo "selftest PASS: good fixture -> all GREEN-or-SKIPPED (exit 0)"
    fi
  else
    echo "selftest FAIL: good fixture exited non-zero"; printf '%s\n' "$out" | sed 's/^/    /'; st=1
  fi

  # --- N/A path: a non-DB good fixture -> db-postgres omitted as N/A (not a skip), rest GREEN, exit 0. ---
  if out=$(KW3_NOLIVE=1 sh "$0" --manifest "$MAN" "$FIXTURES/good-nodb" 2>&1); then
    if printf '%s\n' "$out" | grep -q '\[N/A\][[:space:]]*db-postgres'; then
      echo "selftest PASS: non-DB fixture -> db-postgres omitted as N/A (omit != skip)"
    else
      echo "selftest FAIL: non-DB fixture did not mark db-postgres N/A"; printf '%s\n' "$out" | sed 's/^/    /'; st=1
    fi
  else
    echo "selftest FAIL: non-DB fixture exited non-zero"; printf '%s\n' "$out" | sed 's/^/    /'; st=1
  fi

  # --- 5 LOAD-BEARING NEGATIVES: each mutated fixture -> FAIL naming that mechanism. ---
  check_negative() {  # fixture-dir mechanism-id
    _fx="$1"; _mech="$2"
    # Capture rc via `if` — a bare `_o=$(...)` under set -e would abort on the (expected) non-zero exit.
    if _o=$(KW3_NOLIVE=1 sh "$0" --manifest "$MAN" "$FIXTURES/$_fx" 2>&1); then _rc=0; else _rc=$?; fi
    if [ "$_rc" -ne 0 ] && printf '%s\n' "$_o" | grep -q "\[RED\][[:space:]]*$_mech"; then
      echo "selftest PASS: $_fx -> MISCONFIGURED-RED naming '$_mech' (rc=$_rc)"
    else
      echo "selftest FAIL: $_fx (rc=$_rc) did not RED-name '$_mech'"; printf '%s\n' "$_o" | sed 's/^/    /'; st=1
    fi
  }
  check_negative bad-db-postgres        db-postgres
  check_negative bad-sast-narrowed      sast-scoped
  check_negative bad-secret-gitignore   secret-gate
  check_negative bad-provenance-ungated provenance-gated
  check_negative bad-agent-trace        agent-trace-emit

  # --- ★ LOCK SELF-NEGATIVE (mandatory): neutralize the detector (predicate_holds -> always-true) and
  #     assert its --selftest FAILS. A dead/always-green detector must NOT pass — else the whole proof
  #     is theater. Skipped inside the inner (neutered) run via KW3_INNER to avoid recursion. ---
  if [ -z "${KW3_INNER:-}" ]; then
    NEUT="${TMPDIR:-/tmp}/kw3-neutered-$$-detector.sh"
    awk '/^predicate_holds\(\) \{$/ { print; print "  return 0  # NEUTERED (lock self-negative)"; next } { print }' "$0" > "$NEUT"
    if grep -q 'NEUTERED' "$NEUT"; then
      if KW3_INNER=1 KW3_NOLIVE=1 KW3_FIXTURES="$FIXTURES" KW3_MANIFEST="$MAN" sh "$NEUT" --selftest >/dev/null 2>&1; then
        echo "selftest FAIL: LOCK SELF-NEGATIVE did NOT fire — a neutered always-green detector still PASSED (VACUOUS)"; st=1
      else
        echo "selftest PASS: LOCK SELF-NEGATIVE fired — the neutered always-green detector FAILS its own selftest (asserts are LOAD-BEARING)"
      fi
    else
      echo "selftest FAIL: LOCK SELF-NEGATIVE setup — neutralization did not land in the copy"; st=1
    fi
    rm -f "$NEUT"
  fi

  if [ "$st" = 0 ]; then
    echo "OK: incept-first-run-green selftest — anchor + N/A + 5 load-bearing negatives + lock self-negative"
  else
    echo "FAIL: incept-first-run-green selftest"
  fi
  return "$st"
}

# ===========================================================================================
# Dispatch
# ===========================================================================================
MODE=check
TARGET=''
MANIFEST_ARG=''
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) MODE=selftest; shift ;;
    --manifest) MANIFEST_ARG="${2:-}"; shift 2 ;;
    --) shift; break ;;
    -*) echo "usage: incept-first-run-green.sh [--selftest] [--manifest M] [TARGET]" >&2; exit 2 ;;
    *)  TARGET="$1"; shift ;;
  esac
done

# Kit-self N/A guard (mirrors adopter-export-wired.sh + its "kit-self pattern" guidance): this
# detector validates the KIT's OWN shipped profiles ship first-run-green — it has no meaning on an
# adopter's exported tree (already incepted). N/A-
# skip when BOTH kit markers are absent (the export strips both; golden-path.yml is control-plane +
# export-ignored, so the marker set is un-spoofable). In the kit repo both are present -> full run.
# Gated on KW3_INNER being unset: the lock self-negative's neutered copy runs from $TMPDIR (no markers)
# with KW3_INNER=1 — it MUST bypass this guard and actually run, else the self-negative can't fire.
if [ -z "${KW3_INNER:-}" ] && [ ! -f "$REPO_ROOT/docs/ROADMAP-KIT.md" ] && [ ! -f "$REPO_ROOT/.github/workflows/golden-path.yml" ]; then
  echo "incept-first-run-green: N/A — kit-self check (not applicable outside the kit repo)"
  exit 0
fi

if [ "$MODE" = selftest ]; then
  selftest; exit $?
fi

[ -n "$TARGET" ] || TARGET="$REPO_ROOT/profiles/typescript-node"
_base="$(basename "$TARGET")"
if [ -n "$MANIFEST_ARG" ]; then
  MAN="$MANIFEST_ARG"
else
  MAN="$(resolve_manifest_default "$_base")" \
    || { echo "MISCONFIGURED: no manifest for archetype '$_base' (looked for manifest-$_base.txt / incept-manifests/$_base.txt) — fail-closed" >&2; exit 2; }
fi
run_check "$TARGET" "$MAN"; exit $?
