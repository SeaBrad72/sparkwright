#!/bin/sh
# harness-adapter.sh — composing conformance meta-check (harness-neutrality N2).
# Proves the adapter at adapters/<harness>/ satisfies the boundary contract
# (docs/operations/harness-adapters.md):
#   1. manifest valid (JSON; .harness non-empty; controlPlanePaths non-empty; declared
#      bindingFiles exist; all 7 dimensions declared with a valid level)
#   2. the dimension set is CLOSED — a key outside the seven is a FAIL, because the Kit enforces no
#      floor for it and therefore cannot verify it (keys are compared whole, never word-split)
#   3. the Kit-enforced FLOOR holds for every dimension (the equal-enforcement guarantee)
#   4. every `native` claim carries a proof that actually passes (the lying-native guard)
#   5. --selftest exercises conformant / malformed / lying-native / closed-set / no-glob fixtures
# COMPOSES existing checks (agents-brief, guard-core-sourced, guard-wired, mcp-policy) — never
# reimplements them. THREE-STATE: 0 ok · 1 violation · 2 UNVERIFIED (jq absent / adapter missing);
# 2 escalates to 1 under CI/--require. POSIX sh; dash-clean. Run from the repo root.
set -eu

REQUIRE="${REQUIRE:-0}"
[ -n "${CI:-}" ] && REQUIRE=1
ADAPTER=""
MODE="run"
while [ $# -gt 0 ]; do
  case "$1" in
    --require) REQUIRE=1; shift ;;
    --selftest) MODE="selftest"; shift ;;
    -*) echo "usage: harness-adapter.sh [adapters/<harness>] [--require] | --selftest" >&2; exit 2 ;;
    *) ADAPTER="$1"; shift ;;
  esac
done
[ -n "$ADAPTER" ] || ADAPTER="adapters/claude-code"

DIMS="context-binding command-guard history-protection review-roles mcp-gate orchestration model-tiering"

unverifiable() {
  if [ "$REQUIRE" = "1" ]; then echo "FAIL: harness-adapter could not verify ($1) — required (CI/--require)."; exit 1; fi
  echo "UNVERIFIED: $1 — (NOT a pass)."; exit 2
}

# _san: strip control bytes from adopter-supplied text on its way to stdout. A manifest key,
# bindingFile, level or harness name is UNRATIFIED input that reaches the CI log verbatim, so an ANSI
# escape in it can erase the line and impersonate this check's own "OK:" line. Dropping \n as well
# means a value can never inject a whole extra result line. Reads stdin so it composes with the jq
# that produced the value.
# THE PREDICATE MUST BE THE ONE THE SELFTEST ASSERTS. `tr -d '\000-\037'` left DEL (0x7f) standing,
# while the selftest's `LC_ALL=C grep -q '[[:cntrl:]]'` counts DEL as control — the sanitizer and its
# own assertion disagreed on exactly one byte, and no fixture carried that byte, so nothing was red.
# `[:cntrl:]` under LC_ALL=C is now literally the same class on both sides; a DEL-bearing fixture
# (below) keeps them from drifting apart again.
_san() { LC_ALL=C tr -d '[:cntrl:]'; }

# floor_holds <dim>: 0 if the Kit-enforced floor for <dim> is present in this repo (reuses checks).
floor_holds() {
  case "$1" in
    context-binding)    sh conformance/agents-brief.sh >/dev/null 2>&1 ;;
    command-guard)      [ -f hooks/pre-push ] && [ -f scripts/kit-guard ] && [ -f conformance/agent-boundary.sh ] && sh conformance/guard-core-sourced.sh >/dev/null 2>&1 ;;
    history-protection) [ -f hooks/pre-push ] ;;
    review-roles)       [ -f conformance/agent-boundary.sh ] && [ -f conformance/branch-protection.sh ] ;;
    mcp-gate)           [ -f scripts/kit-guard ] ;;
    orchestration)      [ -f agents/orchestrator.agent.md ] && [ -f agents/engineer.agent.md ] && [ -f agents/reviewer.agent.md ] && [ -f agents/security.agent.md ] ;;
    model-tiering)      [ -f conformance/model-tiering.sh ] && sh conformance/model-tiering.sh >/dev/null 2>&1 ;;
    *)                  return 1 ;;   # no Kit-enforced floor for this dimension -> fail CLOSED
  esac
}

# native_proof_ok <manifest> <dim>: 0 if the dim's declared native proof passes. A native dim MUST
# carry a proof (a check and/or files); none => not ok (cannot claim native unverified).
native_proof_ok() {
  m=$1; d=$2
  chk=$(jq -r --arg d "$d" '.dimensions[$d].proof.check // empty' "$m")
  # shellcheck disable=SC2086 # intentional word-split: files is a newline-separated list of paths
  files=$(jq -r --arg d "$d" '.dimensions[$d].proof.files[]? // empty' "$m")
  [ -n "$chk" ] || [ -n "$files" ] || return 1
  if [ -n "$chk" ]; then
    # D2 allowlist: execute a proof.check ONLY if it is a bare conformance/*.sh path
    # (no metacharacters, no args, no traversal) that exists. Anything else => not ok, NOT run.
    case "$chk" in
      conformance/*.sh) : ;;
      *) return 1 ;;
    esac
    if printf '%s' "$chk" | grep -Eq '[^A-Za-z0-9._/-]' || printf '%s' "$chk" | grep -q '\.\.'; then
      return 1
    fi
    [ -f "$chk" ] || return 1
    if [ -L "$chk" ]; then return 1; fi   # -f follows symlinks; reject a symlinked check
    sh "$chk" >/dev/null 2>&1 || return 1
  fi
  # proof.files is adopter-supplied: word-split it, never PATHNAME-expand it. `["*"]` otherwise
  # expands to the existing repo-root entries, every one of which satisfies `-e`, so a `native` claim
  # carrying no real proof PASSED (measured at HEAD: rc=0 OK). Save and restore the caller's noglob
  # state rather than an unconditional `set +f` — the house idiom (conformance/agent-boundary.sh,
  # .claude/hooks/guard-core.sh); an unconditional restore silently clears a caller's `set -f`.
  _npo_g=0; case "$-" in *f*) _npo_g=1 ;; esac
  set -f
  # shellcheck disable=SC2086 # intentional word-split; pathname expansion disabled just above
  for f in $files; do
    [ -e "$f" ] || { [ "$_npo_g" = 1 ] || set +f; return 1; }
  done
  [ "$_npo_g" = 1 ] || set +f
  return 0
}

run() {
  command -v jq >/dev/null 2>&1 || unverifiable "jq not installed (the manifest is JSON)"
  [ -d "$ADAPTER" ] || unverifiable "adapter dir not found: $ADAPTER"
  m="$ADAPTER/adapter.json"
  [ -f "$m" ] || unverifiable "manifest not found: $m"
  jq -e . "$m" >/dev/null 2>&1 || { echo "FAIL: $m is not valid JSON"; exit 1; }

  fail=0
  # Sanitized at the READ site, not at the echo site, so every present and future use of $harness is
  # covered — the OK line below was missed exactly because it was the one use nobody sanitized. A
  # harness name that is nothing but control bytes therefore sanitizes to empty and trips the
  # emptiness check: fail-CLOSED, which is the right answer for a name that cannot be printed.
  harness=$(jq -r '.harness // empty' "$m" | _san); [ -n "$harness" ] || { echo "FAIL: .harness is empty"; fail=1; }
  cp=$(jq '(.controlPlanePaths // []) | length' "$m"); [ "$cp" -gt 0 ] || { echo "FAIL: controlPlanePaths is empty"; fail=1; }
  # bindingFiles are adopter-supplied: word-split them, never PATHNAME-expand them. Globbing has to
  # be off BEFORE this list is expanded — with it on, `"bindingFiles":["*"]` expanded to the
  # repo-root entries, all of which exist, so a manifest declaring no real binding file passed
  # (measured: rc=0 OK). Save/restore the caller's noglob state rather than an unconditional
  # `set +f`, the house idiom — an unconditional restore silently clears a caller's `set -f`.
  _hb_g=0; case "$-" in *f*) _hb_g=1 ;; esac
  set -f
  # shellcheck disable=SC2086 # intentional word-split; pathname expansion disabled just above
  for bf in $(jq -r '.bindingFiles[]? // empty' "$m"); do
    [ -e "$bf" ] || { echo "FAIL: bindingFile missing: $(printf '%s' "$bf" | _san)"; fail=1; }
  done
  [ "$_hb_g" = 1 ] || set +f

  # The dimension set is CLOSED: a key outside $DIMS carries no Kit-enforced floor, so it can never
  # be verified and is a FAIL. Count the offenders IN JQ — a key must never reach the shell. The
  # earlier form materialised the key set as a string and word-split it, which SILENTLY DROPPED any
  # key that split into nothing ("" / "   ") or into names already in $DIMS ("mcp-gate model-tiering",
  # "command-guard "). All four were measured passing rc=0 OK while declared `native` with a
  # nonexistent proof.check — so the lying-native guard never ran on them either.
  # The key MUST be bound to $d before the membership test: inside `$k|index(...)` the `.` has been
  # rebound to $k, so `select($k|index(.)|not)` asks whether $k contains ITSELF — always index 0,
  # always truthy, so the count came out 0 for every manifest and the whole rule was vacuous.
  n_extra=$(jq -r --arg dims "$DIMS" \
    '($dims|split(" ")) as $k
     | [(.dimensions|objects|keys_unsorted[]) as $d | select($k|index($d)|not) | $d] | length' "$m")
  case "${n_extra:-}" in ''|*[!0-9]*) n_extra=1 ;; esac   # unreadable count -> fail CLOSED
  if [ "$n_extra" -eq 0 ]; then : ; else
    echo "FAIL: manifest declares $n_extra dimension(s) outside the boundary contract (the contract is exactly: $DIMS) — the Kit enforces no floor for them, so they cannot be verified"
    echo "FAIL:   offending key(s): $(jq -r --arg dims "$DIMS" \
      '($dims|split(" ")) as $k
       | [(.dimensions|objects|keys_unsorted[]) as $d | select($k|index($d)|not) | "<" + $d + ">"]
       | join(" ")' "$m" | _san)"
    fail=1
  fi

  for d in $DIMS; do
    # $level is sanitized at its ECHO site, NOT at the read site — the opposite of $harness above, and
    # deliberately so: $level is COMPARED, not just printed. Sanitizing on read would turn a level of
    # "flo<ESC>[2Kor" into the literal "floor" and the `case` below would ACCEPT it, converting a
    # display fix into a validation bypass. Read raw, compare raw, print sanitized.
    level=$(jq -r --arg d "$d" '.dimensions[$d].level // "missing"' "$m")
    case "$level" in
      missing) echo "FAIL: dimension '$d' not declared"; fail=1; continue ;;
      n-a)     [ "$d" = "mcp-gate" ] || { echo "FAIL: '$d' may not be n-a (only mcp-gate may)"; fail=1; }; continue ;;
      floor|native) : ;;
      *)       echo "FAIL: '$d' has invalid level '$(printf '%s' "$level" | _san)'"; fail=1; continue ;;
    esac
    if floor_holds "$d"; then : ; else echo "FAIL: '$d' Kit-enforced floor not satisfied"; fail=1; fi
    if [ "$level" = "native" ]; then
      if native_proof_ok "$m" "$d"; then : ; else echo "FAIL: '$d' declared native but its proof is absent or failing (lying-native)"; fail=1; fi
    fi
  done

  if [ "$fail" = "0" ]; then echo "OK: adapter '$harness' satisfies the boundary contract (floor for every dimension; native proofs verified)"; exit 0; fi
  echo "harness-adapter: FAIL ($ADAPTER)"; exit 1
}

selftest() {
  st=0
  base=$(mktemp -d)   # fixtures left in place (no rm; 7e control-plane guard)
  mkconf() { mkdir -p "$1"; printf '%s\n' "$2" > "$1/adapter.json"; }
  expect() {  # <expected-rc> <adapter-dir> <label>
    e=$1; a=$2; lbl=$3
    ( sh "$0" "$a" ) >/dev/null 2>&1 && g=0 || g=$?
    if [ "$g" = "$e" ]; then echo "selftest PASS: $lbl -> rc $g"; else echo "selftest FAIL: $lbl want $e got $g"; st=1; fi
  }

  mkconf "$base/ok" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  expect 0 "$base/ok" "conformant (all floor, mcp n-a)"

  mkconf "$base/missing" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  expect 1 "$base/missing" "missing review-roles dimension"

  mkconf "$base/missorch" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"model-tiering":{"level":"floor"}}}'
  expect 1 "$base/missorch" "missing orchestration dimension"

  mkconf "$base/nocp" '{"harness":"fixture","controlPlanePaths":[],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  expect 1 "$base/nocp" "empty controlPlanePaths"

  mkconf "$base/lie" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"native","proof":{"files":["does-not-exist-xyz.txt"]}},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  expect 1 "$base/lie" "lying-native (native proof file missing)"

  mkconf "$base/badcheck" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"native","proof":{"check":"false"}},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  expect 1 "$base/badcheck" "lying-native (proof.check exits non-zero)"

  mkconf "$base/noproof" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"native"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  expect 1 "$base/noproof" "native with no proof declared"

  mkconf "$base/badbind" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["nope-not-here.txt"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  expect 1 "$base/badbind" "missing bindingFile"

  # D2: proof.check allowlist — a check with shell metacharacters or outside conformance/
  # must be REJECTED BEFORE EXECUTION (no side effect), not run.
  canary="$base/canary"
  mkconf "$base/metachar" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"native","proof":{"check":"conformance/agents-brief.sh; touch __CANARY__"}},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  sed "s#__CANARY__#$canary#" "$base/metachar/adapter.json" > "$base/metachar/adapter.tmp" && mv "$base/metachar/adapter.tmp" "$base/metachar/adapter.json"
  expect 1 "$base/metachar" "proof.check with metacharacters (lying-native)"
  if [ -e "$canary" ]; then echo "selftest FAIL: metachar proof.check EXECUTED (canary created)"; st=1; else echo "selftest PASS: metachar proof.check not executed"; fi
  mkconf "$base/escape" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"native","proof":{"check":"../evil.sh"}},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  expect 1 "$base/escape" "proof.check outside conformance/ (lying-native)"

  # model-tiering: native declared with a broken proof -> lying-native -> FAIL
  mkconf "$base/mtlie" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"native","proof":{"check":"conformance/does-not-exist-mt.sh"}}}}'
  expect 1 "$base/mtlie" "model-tiering native + broken proof (lying-native)"
  # model-tiering omitted entirely -> required-dim -> FAIL
  mkconf "$base/mtmiss" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"}}}'
  expect 1 "$base/mtmiss" "model-tiering dimension omitted"

  # an UNDECLARED dimension: all 7 real dims valid, plus a dimension the Kit enforces no floor
  # for. There is no Kit-enforced floor to hold, so it may not be accepted -> FAIL (fail-CLOSED).
  mkconf "$base/unknowndim" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"},"not-a-real-dimension":{"level":"floor"}}}'
  expect 1 "$base/unknowndim" "unknown dimension -> FAIL (closes the floor_holds fail-open)"

  # The closed-set rule must not be defeatable by the SHAPE of the key. A key materialised into a
  # shell string and word-split DISAPPEARS when it is empty or whitespace-only, or splits into names
  # already in $DIMS — measured bypasses, all rc=0 OK. Each is declared `native` with a proof.check
  # naming a file that does NOT exist, so a regression that drops the key also skips the lying-native
  # guard, and one fixture catches both holes.
  lyingnative='{"level":"native","proof":{"check":"conformance/does-not-exist-xyz.sh"}}'
  seven='"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}'
  hdr='"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"]'
  mkconf "$base/emptykey"  "{$hdr,\"dimensions\":{$seven,\"\":$lyingnative}}"
  expect 1 "$base/emptykey" "extra key is the empty string (word-splits to nothing)"
  mkconf "$base/wskey"     "{$hdr,\"dimensions\":{$seven,\"   \":$lyingnative}}"
  expect 1 "$base/wskey" "extra key is whitespace only (word-splits to nothing)"
  mkconf "$base/splitkey"  "{$hdr,\"dimensions\":{$seven,\"mcp-gate model-tiering\":$lyingnative}}"
  expect 1 "$base/splitkey" "extra key word-splits into two KNOWN dimension names"
  mkconf "$base/trailkey"  "{$hdr,\"dimensions\":{$seven,\"command-guard \":$lyingnative}}"
  expect 1 "$base/trailkey" "extra key is a known name plus a trailing space"

  # bindingFiles are adopter-supplied and were read through an unquoted `$(...)` BEFORE globbing was
  # disabled, so `["*"]` PATHNAME-expanded to the repo-root entries — every one of which exists.
  # Measured: rc=0 OK while the manifest declared no real binding file at all.
  mkconf "$base/globbind" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["*"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  expect 1 "$base/globbind" "bindingFiles ['*'] must not glob-expand"

  # SAME defect class, SECOND site: proof.files is adopter-supplied and word-split too. Measured at
  # HEAD, `"proof":{"files":["*"]}` expanded to the repo-root entries and every one existed, so a
  # `native` claim passed carrying no proof at all (rc=0 OK). It is closed only INCIDENTALLY while a
  # `set -f` wraps the whole dimension loop; scoping that `set -f` to bindingFiles re-opens it unless
  # native_proof_ok disables globbing itself. This fixture pins it to native_proof_ok.
  mkconf "$base/globproof" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"native","proof":{"files":["*"]}},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  expect 1 "$base/globproof" "proof.files ['*'] must not glob-expand (lying-native)"

  # A manifest key / bindingFile is unratified adopter input that reaches the CI log VERBATIM, so an
  # ANSI escape can erase the line and impersonate an "OK:" line. The fixture needs a REAL ESC byte
  # without putting one in THIS file (a raw control byte in a source file is itself a review hazard,
  # and is illegal inside a JSON string): build the six-character JSON escape at runtime instead.
  # jq -r then decodes it to ESC on output. Asserted on the BYTES of a real run — newlines stripped
  # first, since those are control bytes too — so dropping a sanitize call makes this fail.
  # shellcheck disable=SC1003 # a LITERAL backslash is exactly what is wanted here, not an escape
  esc="$(printf '\\')u001b"
  # DEL (0x7f) is a control byte to `[[:cntrl:]]` — the predicate the assertion below uses — but NOT to
  # `\000-\037`, the range the sanitizer used to strip. The sanitizer and its own assertion therefore
  # disagreed on exactly one byte, and no fixture carried that byte, so the gap was invisible. The key
  # here carries a DEL so the two predicates can never drift apart again.
  # shellcheck disable=SC1003 # a LITERAL backslash is exactly what is wanted here, not an escape
  del="$(printf '\\')u007f"
  # The FAIL path prints THREE of the four adopter-controlled sinks; this fixture spans all three:
  # the extra dimension key, the bindingFile, and — measured raw at the pre-fix tree —
  # `FAIL: 'model-tiering' has invalid level 'flo<raw ESC>[2Kor'`.
  # It CANNOT span the fourth. `.harness` is printed only on the OK line, and this fixture exits down
  # the FAIL path where `.harness` is never printed at all (measured: zero occurrences). A fixture
  # that merely carried an ANSI `.harness` HERE would be vacuous — a green attesting a sink it never
  # exercised. That is the same substitution-blindness the rest of this slice closes, so the success
  # sink gets its own rc=0 fixture (`ansiok`) below rather than a passenger field in this one.
  sevenansilvl="\"context-binding\":{\"level\":\"floor\"},\"command-guard\":{\"level\":\"floor\"},\"history-protection\":{\"level\":\"floor\"},\"review-roles\":{\"level\":\"floor\"},\"mcp-gate\":{\"level\":\"n-a\"},\"orchestration\":{\"level\":\"floor\"},\"model-tiering\":{\"level\":\"flo${esc}[2Kor\"}"
  mkconf "$base/ansikey" "{\"harness\":\"fixture\",\"controlPlanePaths\":[\".claude/settings.json\"],\"bindingFiles\":[\"${esc}[2Kfake.txt\"],\"dimensions\":{$sevenansilvl,\"${esc}[2K${del}evil\":{\"level\":\"floor\"}}}"
  expect 1 "$base/ansikey" "ANSI/DEL extra key + ANSI bindingFile + ANSI level still FAIL"
  if ( sh "$0" "$base/ansikey" ) 2>&1 | tr -d '\n' | LC_ALL=C grep -q '[[:cntrl:]]'; then
    echo "selftest FAIL: manifest control bytes reached the output (unsanitized)"; st=1
  else
    echo "selftest PASS: manifest control bytes stripped from the output"
  fi

  # THE SUCCESS LINE IS THE MOST VALUABLE LINE IN THIS FILE TO FORGE, and it was the one line whose
  # adopter-supplied value went out raw — measured at the pre-fix tree:
  #   OK: adapter 'fix<raw ESC>[2Kture' satisfies the boundary contract ...
  # rc=0, escape verbatim in the CI log, on a GREEN run. Every FAIL-path value was sanitized; this one
  # was missed precisely because it is on the path nobody thinks of as hostile. The manifest below is
  # otherwise conformant, so it MUST still pass (rc 0) — sanitizing must not be bought by failing.
  mkconf "$base/ansiok" "{\"harness\":\"fix${esc}[2K${del}ture\",\"controlPlanePaths\":[\".claude/settings.json\"],\"bindingFiles\":[\"AGENTS.md\"],\"dimensions\":{$seven}}"
  expect 0 "$base/ansiok" "ANSI/DEL harness still PASSES (sanitizing is not bought by failing)"
  if ( sh "$0" "$base/ansiok" ) 2>&1 | tr -d '\n' | LC_ALL=C grep -q '[[:cntrl:]]'; then
    echo "selftest FAIL: control bytes reached the SUCCESS line (unsanitized .harness)"; st=1
  else
    echo "selftest PASS: control bytes stripped from the SUCCESS line"
  fi

  # adapter dir not found -> UNVERIFIED(2) local, FAIL(1) under CI/--require
  # shellcheck disable=SC1007 # CI= is intentional: clears CI in the subshell to test non-CI path
  ( CI= REQUIRE=0 sh "$0" "$base/does-not-exist" ) >/dev/null 2>&1 && g=0 || g=$?
  if [ "$g" = "2" ]; then echo "selftest PASS: missing adapter -> exit 2 (UNVERIFIED)"; else echo "selftest FAIL: missing adapter want 2 got $g"; st=1; fi
  ( CI=true sh "$0" "$base/does-not-exist" ) >/dev/null 2>&1 && g=0 || g=$?
  if [ "$g" = "1" ]; then echo "selftest PASS: missing adapter + CI -> exit 1"; else echo "selftest FAIL: missing adapter + CI want 1 got $g"; st=1; fi

  [ "$st" = "0" ] && echo "harness-adapter --selftest: OK"
  return "$st"
}

case "$MODE" in
  selftest) selftest; exit $? ;;
  *) run ;;
esac
