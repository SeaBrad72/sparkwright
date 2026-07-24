#!/bin/sh
# obligation-lib.sh — the HITL obligation-trigger engine (sourced by per-obligation checks).
# What it changes: nothing at runtime — a sourced library of detector + record-check primitives.
# Detection: an obligation's own sensitive-surface globs over the change-set — NOT the control-plane
# path set. An obligation MAY additionally source guard-core's is_control_plane_path only when ITS
# surface IS the control-plane set; the threat obligation's surface is the secret/auth/payments/
# migrations set, a DIFFERENT set, so it does not (and must not) source guard-core.
# Fail-safe: a derive-FAILURE (no resolvable base / git error) or an uncertain surface -> require the record.
set -eu

# obl_changeset [--changed FILE]: newline-delimited changed paths. Modelled on promotion-readiness.sh's
# derivation but now DELIBERATELY DIVERGENT from it in two ways — do not "re-sync" them without reading
# both notes. (a) It DISTINGUISHES a derive-FAILURE from a genuinely-empty diff (the security-critical
# split, below); (b) it derives UNQUOTED paths (see PATH QUOTING). promotion-readiness.sh still uses the
# bare quoted form and mis-classifies a non-ASCII control-plane path as Ordinary — boarded as
# PROMOTION-PATH-QUOTING; that check is NOT fixed by this slice.
# The derive-FAILURE split:
#  - a valid base RESOLVES (merge-base HEAD origin/main, else HEAD main) and the diff is empty
#    -> empty change-set, OBL_DERIVE_FAIL stays 0 -> 'none'/N-A (correct: nothing changed);
#  - NO base resolves, OR any git step errors -> OBL_DERIVE_FAIL=1 so the caller fails CLOSED
#    (routes to 'uncertain' -> requires the record). We never collapse failure into empty via
#    `|| echo HEAD` / `|| true` (the old fail-open). This is promotion-readiness.sh's CHANGED_READ_FAIL
#    + its line-87 fail-safe-to-highest-class, applied to the diff-derivation path.
# shellcheck disable=SC2120 # obl_changeset exposes an optional --changed API that current callers don't
# use (they invoke it bare); the parameter is part of the engine's public surface. This also silences the
# paired SC2119 info at the no-arg call site (obl_changeset > "$cs").
obl_changeset() {
  OBL_DERIVE_FAIL=0
  if [ "${1:-}" = "--changed" ]; then cat "$2"; return 0; fi
  base="$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || true)"
  if [ -z "$base" ]; then OBL_DERIVE_FAIL=1; return 0; fi
  # PATH QUOTING (HITL-4 F1 — a silent fail-open on every obligation). Under git's default
  # core.quotePath=true a path with any non-ASCII byte is emitted WRAPPED IN DOUBLE QUOTES with octal
  # escapes ("web/Caf\303\251.tsx"). The trailing '"' defeats every EXTENSION surface glob (*.tsx,
  # *.html …) while directory globs still match (they are '*'-wrapped both sides), so `Café.tsx` derived
  # N/A where `Cafe.tsx` correctly FAILed — one accented character bypassed the gate. This is MONOTONE:
  # unquoting can only ever ADD matches, so no previously-triggering change-set can stop triggering.
  # WHICH PART IS PROVEN (measured, and an earlier version of this note had it BACKWARDS — see below):
  #   drop `core.quotePath=false` alone -> selftest SURVIVES
  #   drop `-z` alone                   -> selftest SURVIVES  (until the quote leg below; now KILLED)
  #   drop both                         -> KILLED by the non-ASCII leg
  # `-z` is the STRICTLY STRONGER control: NUL output is never quoted at all, whereas
  # `core.quotePath=false` only stops the non-ASCII octal escaping — it still quotes a path containing
  # `"`, `\`, a newline or a control byte. obl_selftest therefore carries TWO assertions: a non-ASCII
  # path (kills the both-dropped mutant) AND a quote-in-name path (kills the `-z`-dropped mutant, which
  # nothing else covers). Keep both, and do not "simplify" `-z` away: it is the half that matters.
  # A temp file, not a pipe: `git … | tr` would make the pipeline's status `tr`'s, silently discarding the
  # derive-FAILURE signal this whole function exists to preserve. POSIX sh has no PIPESTATUS.
  _z="$(mktemp 2>/dev/null)" || { OBL_DERIVE_FAIL=1; return 0; }
  if git -c core.quotePath=false diff --name-only -z "$base"...HEAD > "$_z" 2>/dev/null; then
    # tr's status is CAPTURED, not discarded: a bare `tr … < "$_z"` under `set -e` aborts the whole
    # check with no NOTE, no FAIL text and a LEAKED temp file (measured). Fail closed, loudly, and clean up.
    tr '\0' '\n' < "$_z" || OBL_DERIVE_FAIL=1
  else
    OBL_DERIVE_FAIL=1
  fi
  rm -f "$_z"
  return 0
}

# obl_detect GLOBS CHANGED_FILE [--force-uncertain] -> prints triggered|none|uncertain
# The uncertain band + fail-safe: --force-uncertain (a real derive-failure, or a simulated ambiguous
# surface) routes straight to 'uncertain', which the gate treats as "require the record".
obl_detect() {
  _globs="$1"; _changed="$2"; _force="${3:-}"
  [ "$_force" = "--force-uncertain" ] && { echo uncertain; return; }
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    # $_globs is a '|'-separated alternation list. A '|' inside an EXPANDED variable is a LITERAL in a
    # case pattern (POSIX recognises alternation only from source tokens at parse time), so we split on
    # '|' and test each glob. set -f during the split so each glob word (e.g. *auth*) is NOT
    # pathname-expanded against the cwd; case matching still honours * / ? / [ ] regardless of -f.
    _oldifs=$IFS; IFS='|'; set -f
    for _g in $_globs; do
      # shellcheck disable=SC2254 # the unquoted $_g glob IS the matching mechanism — each surface glob
      # (e.g. *auth*) must expand as a case-pattern, not match literally.
      case "$p" in $_g) IFS=$_oldifs; set +f; echo triggered; return ;; esac
    done
    IFS=$_oldifs; set +f
  done < "$_changed"
  echo none
}

# obligation_gate --name N --surface-globs G --record R --template-marker T [--changed F|--root D|--force-uncertain]
# The bracketed fixture flags (--changed/--root/--force-uncertain) are honored ONLY under KIT_OBL_TEST=1
# (set by --selftest). The production entrypoint (verify.sh: no args) parses-but-ignores them, so a caller
# cannot redirect the gate at /dev/null or a dummy record dir (M1).
obligation_gate() {
  name=""; globs=""; record=""; tmpl=""; changed=""; root="."; force=""
  _testmode=0; [ "${KIT_OBL_TEST:-}" = 1 ] && _testmode=1
  while [ $# -gt 0 ]; do case "$1" in
    --name) name="$2"; shift 2;; --surface-globs) globs="$2"; shift 2;;
    --record) record="$2"; shift 2;; --template-marker) tmpl="$2"; shift 2;;
    --changed) if [ "$_testmode" = 1 ]; then changed="$2"; fi; shift 2;;
    --root) if [ "$_testmode" = 1 ]; then root="$2"; fi; shift 2;;
    --force-uncertain) if [ "$_testmode" = 1 ]; then force="--force-uncertain"; fi; shift;;
    *) shift;; esac; done

  # Derive the change-set into a temp file and detect the surface INSIDE a subshell whose EXIT trap removes
  # the mktemp'd file even on a set -e abort (L3) WITHOUT clobbering a caller's trap (e.g. the selftest's).
  # The subshell emits "<derive_fail> <state>"; a derive-FAILURE forces the uncertain band (fail CLOSED).
  _out="$(
    cs="$(mktemp)"; trap 'rm -f "$cs"' EXIT
    OBL_DERIVE_FAIL=0
    if [ -n "$changed" ]; then cat "$changed" > "$cs"; else obl_changeset > "$cs"; fi
    _f="$force"; [ "${OBL_DERIVE_FAIL:-0}" = 1 ] && _f="--force-uncertain"
    printf '%s %s\n' "${OBL_DERIVE_FAIL:-0}" "$(obl_detect "$globs" "$cs" "$_f")"
  )"
  derive_fail="${_out%% *}"; s="${_out#* }"
  case "$s" in
    none)      echo "N/A: no $name surface touched by this change-set — no record required"; return 0 ;;
    uncertain)
      if [ "$derive_fail" = 1 ]; then
        echo "NOTE: could not derive the $name change-set (no resolvable base / git error) — fail-safe requires the record"
      else
        echo "NOTE: ambiguous $name surface — fail-safe requires the record"
      fi ;;  # fall through -> record required
  esac
  rec="$root/$record"
  if [ ! -f "$rec" ]; then
    echo "FAIL: change touches a $name surface but $rec is absent — record it ($tmpl)"; return 1
  fi
  # present + filled: reject the unfilled template placeholder (privacy-ready.sh:21-35 idiom)
  if obl_is_placeholder "$rec"; then
    echo "FAIL: $rec is still the unfilled template — fill it ($tmpl)"; return 1
  fi
  echo "PASS: $name surface touched and a filled $record is present"; return 0
}

# obl_is_placeholder FILE: true (returns 0) if the record is still the blank template (unfilled), or is
# present-but-unreadable (L2 — fail CLOSED, never pass on a read error). What marks "unfilled":
#  1. the template's self-identifying "> **Template.**" guidance banner, or a generic unfilled bracket
#     token (fill/todo/replace/your/describe) — mirrors privacy-ready.sh's placeholder-skip idiom; or
#  2. (L1) a threshold (>=3) of residual TEMPLATE STUBS still present — anchored on THREAT-MODEL-TEMPLATE.md's
#     OWN bracket vocabulary ([summary]/[threat]/[why]/[boundary N …]/[planned/done]/[data, credentials …]/
#     [users, agents …]/[auth, MFA …]/[risk accepted …]/[tracked items …]), a stable subset that will NOT
#     appear in ordinary prose. This catches a record with the banner deleted but every section left as the
#     template stub, WITHOUT false-positiving on a filled record's markdown links / citations ([STRIDE],
#     [design doc](…), [1], [OWASP A01]) — the pre-fix arbitrary-`[...]` count wrongly FAILed those. Coarse
#     by design (honest ceiling stays "present + filled").
# Absent all signals on a readable file -> treat as filled (a real record passes).
obl_is_placeholder() {
  _rec="$1"
  # L2: an existing-but-unreadable record must NOT pass — treat as unfilled (fail-closed).
  [ -r "$_rec" ] || return 0
  # Signal 1: the "> **Template.**" banner, or a generic unfilled bracket token.
  if grep -Eiq '(\*\*template\.\*\*|\[(fill|todo|replace|your |describe ))' "$_rec" 2>/dev/null; then
    return 0
  fi
  # Signal 2 (L1): residual template stubs. Anchor on the template's stub words — NOT arbitrary `[...]` —
  # so bracketed prose (markdown links, citations) is not mistaken for an unfilled stub. A bare `[STRIDE]`
  # citation defeats a pure link-strip, so the stub-vocabulary anchor (not a link-strip) is load-bearing.
  _n=$(grep -oE '\[(summary|threat|why|boundary [0-9]|planned/done|data, credentials|users, agents|auth, MFA|risk accepted|tracked items)' "$_rec" 2>/dev/null | wc -l | tr -d ' ')
  [ "${_n:-0}" -ge 3 ] && return 0
  return 1
}

# ---- selftest() marker: the non-vacuity sweep mutates ONLY lines ABOVE here; everything below (the
# engine's own oracle) is emitted verbatim. Named selftest() per non-vacuity.sh's first_marker
# convention so the sweep recognizes this oracle region and mutates the engine FAIL paths above;
# obl_selftest (just below) is the substantive test it delegates to.
selftest() { obl_selftest; }

# obl_selftest: the engine's OWN mutation-tested oracle. The per-obligation wrappers (threat-obligation.sh)
# are thin — run_threat_obligation carries no mutable FAIL idiom of its own, so mutating that file yields
# UNCOVERED(no-idiom) and cannot prove the engine's teeth. So the engine tests ITSELF here: non-vacuity.sh
# mutates obl_changeset/obl_detect/obligation_gate's FAIL legs ABOVE the marker and this oracle KILLS them.
# Covers: obl_detect none/triggered/uncertain; obligation_gate absent-record FAIL, placeholder FAIL, real
# derive-failure -> uncertain -> require FAIL, filled -> PASS, non-triggering -> N/A PASS.
obl_selftest() {
  _t="$(mktemp -d "${TMPDIR:-/tmp}/obl-st.XXXXXX")"; trap 'rm -rf "$_t"' EXIT INT TERM
  export KIT_OBL_TEST=1   # honor the fixture flags (--changed/--root/--force-uncertain) only in-test (M1)
  rc=0

  # obl_detect — the three bands.
  printf 'docs/README.md\n' > "$_t/none"
  [ "$(obl_detect '*secret*|*auth*' "$_t/none")" = none ] \
    || { echo "OBL SELFTEST FAIL: non-matching change-set should detect 'none'"; rc=1; }
  printf 'src/auth/login.js\n' > "$_t/hit"
  [ "$(obl_detect '*secret*|*auth*' "$_t/hit")" = triggered ] \
    || { echo "OBL SELFTEST FAIL: matching change-set should detect 'triggered'"; rc=1; }
  [ "$(obl_detect '*secret*|*auth*' "$_t/hit" --force-uncertain)" = uncertain ] \
    || { echo "OBL SELFTEST FAIL: --force-uncertain should detect 'uncertain'"; rc=1; }

  # obligation_gate — absent record on a triggered surface -> FAIL. Kills obligation_gate's absent-record
  # `return 1` (neutered to `return 0`, this leg would see a wrong PASS).
  printf 'src/auth/login.js\n' > "$_t/changed"
  if obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
       --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: triggered surface with no record did not FAIL"; rc=1
  fi
  # placeholder (unfilled template) record -> FAIL. Kills the placeholder-branch `return 1`.
  printf '> **Template.**\n' > "$_t/R.md"
  if obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
       --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: unfilled template record did not FAIL"; rc=1
  fi
  # filled record -> PASS.
  printf '# Threat Model\n\nReal, filled analysis with no residual stubs.\n' > "$_t/R.md"
  if ! obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
       --changed "$_t/changed" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: triggered surface with a filled record did not PASS"; rc=1
  fi
  # non-triggering change -> N/A PASS.
  if ! obligation_gate --name t --surface-globs '*auth*' --record R.md --template-marker T \
       --changed "$_t/none" --root "$_t" >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: non-triggering change did not PASS (N/A)"; rc=1
  fi
  # REAL derive-failure (no resolvable base) -> uncertain -> require the record -> FAIL. Kills
  # obl_changeset's `OBL_DERIVE_FAIL=1` (neutered to =0, failure collapses into an empty change-set ->
  # 'none' -> a wrong N/A PASS). Throwaway repo with neither origin/main nor a 'main' branch.
  _dr="$_t/derive"; mkdir -p "$_dr"
  git -C "$_dr" init -q >/dev/null 2>&1
  git -C "$_dr" config user.email obl@test.local
  git -C "$_dr" config user.name obl-test
  : > "$_dr/f.txt"; git -C "$_dr" add f.txt; git -C "$_dr" commit -qm init >/dev/null 2>&1
  git -C "$_dr" branch -m obl-st-nobase >/dev/null 2>&1
  if ( cd "$_dr" && obligation_gate --name t --surface-globs '*auth*' \
         --record R.md --template-marker T --root "$_dr" ) >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: underivable change-set did not FAIL (derive fail-open)"; rc=1
  fi
  # LIVENESS ONLY — this leg kills NO quoting mutant, and saying otherwise was a round-3 defect.
  # Its change-set is {web/Cafe.tsx, web/Café.tsx}; the ASCII twin matches *.tsx however the accented one
  # is rendered, so the gate fires under every derivation and this assertion is permanently green. It is
  # kept because it does kill a "detection totally broken" mutant, and because the twin makes the NEXT
  # leg's setup explicit — but it is NOT one of the two path-quoting assertions. Those are the
  # accented-ALONE leg and the quote-in-name leg below, each of which is the sole triggering path in its
  # own change-set. A fail-open assertion sharing a change-set with any other triggering path proves nothing.
  _qr="$_t/quote"; mkdir -p "$_qr"
  git -C "$_qr" init -q >/dev/null 2>&1
  git -C "$_qr" config user.email obl@test.local
  git -C "$_qr" config user.name obl-test
  : > "$_qr/seed.txt"; git -C "$_qr" add seed.txt; git -C "$_qr" commit -qm seed >/dev/null 2>&1
  git -C "$_qr" branch -M main >/dev/null 2>&1        # a resolvable base for merge-base HEAD main
  git -C "$_qr" checkout -q -b feat >/dev/null 2>&1
  mkdir -p "$_qr/web"
  _acc="$(printf 'web/Caf\303\251.tsx')"              # UTF-8 'Café.tsx', written by byte so the
  : > "$_qr/$_acc"                                    # selftest does not depend on this file's encoding
  : > "$_qr/web/Cafe.tsx"
  git -C "$_qr" add -A >/dev/null 2>&1; git -C "$_qr" commit -qm ui >/dev/null 2>&1
  if ( cd "$_qr" && obligation_gate --name t --surface-globs '*.tsx' \
         --record R.md --template-marker T --root "$_qr" ) >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a change-set containing plain ASCII UI files was wrongly N/A — detection is broken outright"; rc=1
  fi
  # …and the accented file ALONE must still trigger. This is the assertion that actually bites: with the
  # ASCII twin present, the twin triggers and masks the bug, so the leg above cannot prove equivalence on
  # its own (verified — under the both-dropped mutant only THIS assertion fires).
  git -C "$_qr" rm -q --cached web/Cafe.tsx >/dev/null 2>&1
  rm -f "$_qr/web/Cafe.tsx"
  git -C "$_qr" commit -qm ascii-gone >/dev/null 2>&1
  if ( cd "$_qr" && obligation_gate --name t --surface-globs '*.tsx' \
         --record R.md --template-marker T --root "$_qr" ) >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a change-set whose ONLY UI file has a non-ASCII name was wrongly N/A"; rc=1
  fi
  # QUOTE-IN-NAME (kills the `-z`-dropped mutant, which the non-ASCII legs above CANNOT — git quotes a
  # path containing `"` regardless of core.quotePath, so only `-z` unquotes it). Without this leg the
  # engine's strongest half ships untested and a maintainer can "simplify" it away on a false attestation.
  # The accented file is REMOVED first: with core.quotePath=false it emits raw, triggers, and MASKS this
  # assertion (measured — the mutant survived until this line existed). Every fail-open leg here must be
  # the ONLY triggering path in its change-set, or it proves nothing.
  git -C "$_qr" rm -q --cached "$_acc" >/dev/null 2>&1
  rm -f "$_qr/$_acc"
  _qn="$(printf 'web/qu\42ote.tsx')"        # web/qu"ote.tsx, written by byte
  : > "$_qr/$_qn"
  git -C "$_qr" add -A >/dev/null 2>&1; git -C "$_qr" commit -qm quoted >/dev/null 2>&1
  if ( cd "$_qr" && obligation_gate --name t --surface-globs '*.tsx' \
         --record R.md --template-marker T --root "$_qr" ) >/dev/null 2>&1; then
    echo "OBL SELFTEST FAIL: a UI path containing a double-quote was wrongly N/A — git quotes it whatever core.quotePath says, so the derivation must use -z"; rc=1
  fi

  [ "$rc" = 0 ] && echo "OK (obligation-lib engine: detect none/triggered/uncertain; gate absent/placeholder/filled/none/derive-fail)"
  return $rc
}

# Dispatch the engine selftest ONLY when this lib is executed directly, NEVER when sourced. A consumer
# (threat-obligation.sh) sets OBL_LIB_SOURCED before sourcing us, so this stays inert there; a directly-
# run copy — INCLUDING the non-vacuity harness's renamed .nv-mut-/.nv-ctl- copies, which a $0-basename
# guard could NOT recognize — has it unset, so the selftest runs and the sweep can mutate + kill the
# engine's FAIL paths. Flag-based (not $0-based) precisely because the sweep renames the copy it runs.
if [ -z "${OBL_LIB_SOURCED:-}" ] && [ "${1:-}" = "--selftest" ]; then selftest; exit $?; fi
