#!/bin/sh
# harness-adapter.sh — composing conformance meta-check (harness-neutrality N2).
# Proves the adapter at adapters/<harness>/ satisfies the boundary contract
# (docs/operations/harness-adapters.md):
#   1. manifest valid (JSON; .harness non-empty; controlPlanePaths non-empty; declared
#      bindingFiles exist; all 7 dimensions declared with a valid level)
#   1b. contextFile is DECLARED and boundary-valid — the document this harness AUTO-LOADS. REQUIRED;
#      an absent field is a FAIL and there is no default (a default would silently rebind every future
#      adapter to a file its harness may never read). Chain, in order: bare relative path (no absolute,
#      no '..'); no EMPTY, '.' or '.git' path component (all three UNCONDITIONAL); not a symlink and not
#      reached through one; a regular file (so a directory or a glob is refused); and, wherever the repo
#      has a populated index, tracked and not index-mode 120000. Only that LAST pair is conditional, and
#      only on the index being populated — git being absent or the tree not being a repo is UNVERIFIED,
#      never a pass.
#   2. the dimension set is CLOSED — a key outside the seven is a FAIL, because the Kit enforces no
#      floor for it and therefore cannot verify it (keys are compared whole, never word-split)
#   3. the Kit-enforced FLOOR holds for every dimension (the equal-enforcement guarantee)
#   4. every `native` claim carries a proof that actually passes (the lying-native guard)
#   5. --selftest exercises conformant / malformed / lying-native / closed-set / no-glob / contextFile
#      fixtures
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

# ctx_path_has_symlink <relative-path>: 0 (TRUE) if the path itself, or ANY ancestor component of it,
# is a symlink. This is the git-INDEPENDENT half of the contextFile confinement chain, and it is why
# that chain still holds where the index cannot answer.
# MEASURED 2026-07-27, and the reason this function exists at all: the tree the `artifact-gate` job
# validates is `adopter-export.sh` (a `git archive` — the archive carries NO .git) followed by
# `incept.sh`, whose `git init` (scripts/incept.sh:976) commits only to the ORPHAN `kit-base` branch and
# leaves the checked-out branch UNBORN. The index there is EMPTY — measured: a valid repo reporting 0
# tracked files — so `git ls-files` answers "untracked" for EVERY file and every index-side assertion is
# inert. lstat is not. Without this walk, the adopter path — the one an adopter actually runs — would
# carry no symlink defense whatsoever, which is precisely the MED-5 hole this chain is supposed to close.
ctx_path_has_symlink() {
  _cph_rest=$1; _cph_seen=""
  while [ -n "$_cph_rest" ]; do
    _cph_seg=${_cph_rest%%/*}
    if [ "$_cph_seg" = "$_cph_rest" ]; then _cph_rest=""; else _cph_rest=${_cph_rest#*/}; fi
    [ -n "$_cph_seg" ] || continue
    _cph_seen="${_cph_seen:+$_cph_seen/}$_cph_seg"
    if [ -L "$_cph_seen" ]; then return 0; fi
  done
  return 1
}

# ctx_component_bad <raw-path> <sanitized-path>: 0 (TRUE) — and prints the refusal — when ANY component
# of the path is structurally inadmissible. LEXICAL and UNCONDITIONAL: it needs neither the filesystem
# nor the index, which is the whole point, because the index is exactly what the adopter tree cannot
# answer with.
#   - EMPTY / '.' components ('conformance//verify.sh', './AGENTS.md') — MEASURED rc=0 before this walk.
#     They are not a traversal risk; they are an ALIASING risk. Two adapters spelling one document
#     differently ('AGENTS.md' vs './AGENTS.md') read as two distinct bindings to any consumer that
#     compares the declared strings, so the per-adapter '§1 must be byte-identical in every declared
#     contextFile' invariant would be asserted twice over one file and satisfied by neither spelling
#     being canonical. Refused, not normalized: normalizing here would be a sanitize-on-read, the exact
#     shape this file already refuses for $level and proof.check.
#   - '.git' components — MEASURED rc=0 for '.git/config', '.git/HEAD' and '.git/hooks/pre-commit.sample'
#     on the adopter tree. Nothing but the TRACKED rule was refusing them, and the tracked rule is
#     precisely what an empty index skips, so the refusal was absent exactly where the adopter runs.
#     A harness "auto-loading" a file inside .git is either a mistake or an attempt to bind governance
#     to content that lives in no diff and no review.
#     The comparison is CASE-FOLDED because a case-insensitive filesystem (APFS, NTFS) resolves
#     '.GIT/config' to the same bytes git itself resolves — MEASURED rc=0 for '.GIT/config' and
#     '.Git/HEAD'. Folding can only ever match MORE inputs, never fewer, so it cannot be the
#     sanitize-on-read bypass this file warns about; it is a widening of a refusal, not a narrowing.
#     '.gitignore' / '.gitattributes' stay legal — the comparison is against the WHOLE component, never
#     a substring, and a naive '*git*' match is what that distinction exists to avoid.
ctx_component_bad() {
  _ccb_rest=$1; _ccb_s=$2
  while [ -n "$_ccb_rest" ]; do
    _ccb_seg=${_ccb_rest%%/*}
    if [ "$_ccb_seg" = "$_ccb_rest" ]; then _ccb_rest=""; else _ccb_rest=${_ccb_rest#*/}; fi
    case "$_ccb_seg" in
      "") echo "FAIL: contextFile '$_ccb_s' has an EMPTY path component — declare the document under ONE canonical spelling"
          return 0 ;;
      .)  echo "FAIL: contextFile '$_ccb_s' has a '.' path component — declare the document under ONE canonical spelling"
          return 0 ;;
    esac
    if [ "$(printf '%s' "$_ccb_seg" | LC_ALL=C tr '[:upper:]' '[:lower:]')" = ".git" ]; then
      echo "FAIL: contextFile '$_ccb_s' reaches into the .git DIRECTORY — that content is in no diff and no review, so it cannot be a binding"
      return 0
    fi
  done
  return 1
}

# ctx_ok <contextFile>: 0 if the declared context document satisfies the boundary chain; prints its own
# FAIL line otherwise. The value is UNRATIFIED manifest input reaching the CI log, so it is COMPARED RAW
# and PRINTED SANITIZED — the same discipline as $level below, and for the same reason: sanitizing on
# read would let "..<ESC>[2K/x" collapse into a value the `case` accepts, turning a display fix into a
# validation bypass.
ctx_ok() {
  _c=$1; _cs=$(printf '%s' "$_c" | _san)
  # (1) bare RELATIVE path — refuse absolute and any '..'. Deliberately whole-string, matching the
  # ratified ceremony-binding:281-285 shape rather than reinventing a component-wise variant.
  case "$_c" in
    /*|*..*)
      echo "FAIL: contextFile '$_cs' must be a bare relative path inside the repo (absolute or '..' refused)"
      return 1 ;;
  esac
  # (2) no EMPTY, '.' or '.git' component — LEXICAL and UNCONDITIONAL (see ctx_component_bad). This sits
  # ABOVE the symlink and regular-file rules deliberately: '.git/config' IS a regular file and IS not a
  # symlink, so every rule below would have waved it through, and only the index-side rule — the one an
  # adopter tree skips — was refusing it.
  if ctx_component_bad "$_c" "$_cs"; then
    return 1
  fi
  # (3) no component may be a symlink — enforced ALWAYS (see ctx_path_has_symlink).
  if ctx_path_has_symlink "$_c"; then
    echo "FAIL: contextFile '$_cs' is, or is reached through, a SYMLINK — its content is not in this tree"
    return 1
  fi
  # (4) a regular file, not a directory and not a glob. QUOTED, so `*` is a literal name that does not
  # exist — the shell-side half of the glob defense the globctx fixture pins.
  if [ ! -f "$_c" ]; then
    echo "FAIL: contextFile '$_cs' is not a regular file in this repo"
    return 1
  fi
  # (5) INDEX-SIDE: tracked, and not a symlink in the index. Asserted only where an index can answer —
  # in a tree with ZERO tracked files the answer "untracked" is a property of the TREE, not of this
  # manifest, and asserting it there fails every conformant adopter without catching a single bad one
  # (measured: it turns artifact-gate red, a CI-only failure). Rules 1-4 above hold unconditionally and
  # already confine the path to this tree, so the conditional narrows the claim, not the confinement.
  #
  # THE PREDICATE MUST NOT CONFLATE "empty index" WITH "no git". `[ -n "$(git ls-files ...)" ]` alone is
  # empty in THREE states: an empty index (justified — the adopter tree), git ABSENT from PATH, and "not
  # a git repo". MEASURED: with git removed from PATH an UNTRACKED contextFile returned rc=0 OK, silently
  # — a fail-OPEN, and the one direction this file may never fail in. Only the first state is a narrowing
  # of the claim; the other two are an INABILITY TO VERIFY, which this script already has a state for.
  # Mirrors the jq-absent arm at the top of run(): UNVERIFIED (rc 2), escalating to FAIL under CI/--require.
  # MEASURED on a real `adopter-export.sh | incept.sh` tree: incept's `git init` (scripts/incept.sh:976)
  # always leaves a `.git`, so `--git-dir` resolves there and this arm cannot red the artifact-gate. (It
  # commits only to the ORPHAN `kit-base` branch, leaving the checked-out `main` unborn — hence 0 tracked
  # files with a perfectly valid repo, which is exactly the state the conditional below is written for.)
  if ! command -v git >/dev/null 2>&1 || ! git rev-parse --git-dir >/dev/null 2>&1; then
    unverifiable "git is unavailable or this tree is not a git repository, so contextFile '$_cs' cannot be index-verified"
  fi
  # `-- ':/'` makes the index probe REPO-WIDE. A bare `git ls-files` is CWD-scoped, so running this check
  # from a tracked-but-empty subdirectory would read as "empty index" and silently skip the index rules in
  # a fully populated repo. `:/` is a MAGIC pathspec, so --literal-pathspecs must NOT be added to this
  # line (it would make git look for a literal file named ':/'). Kept in lockstep with the selftest's own
  # guard on the untracked fixture — the two must agree or the fixture asserts a rule that did not run.
  if [ -n "$(git ls-files -- ':/' 2>/dev/null | head -1)" ]; then
    # --literal-pathspecs: a git pathspec is a GLOB by default, so `-- '*'` MATCHES and a bare
    # tracked-check would accept a manifest naming no document (measured on this repo).
    if ! git --literal-pathspecs ls-files --error-unmatch -- "$_c" >/dev/null 2>&1; then
      echo "FAIL: contextFile '$_cs' is not a tracked file — a context document that appears in no diff is not a binding"
      return 1
    fi
    if [ "$(git --literal-pathspecs ls-files -s -- "$_c" 2>/dev/null | awk 'NR==1{print $1}')" = "120000" ]; then
      echo "FAIL: contextFile '$_cs' is a SYMLINK in the index (git mode 120000)"
      return 1
    fi
  fi
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

  # contextFile — the document THIS harness AUTO-LOADS at session start. REQUIRED; an absent field is a
  # FAIL and there is NO default. `agents-brief.sh` asserts only that AGENTS.md exists, routes to the
  # canonical docs, and stays within a line bound — it never asks WHICH file the harness actually loads.
  # That is exactly how adapters/claude-code passed while binding to `.claude/settings.json` and naming
  # no context document at all. Defaulting to AGENTS.md would make that same defect the SILENT
  # behaviour of every adapter added from here on, so unset is fatal.
  ctx=$(jq -r '.contextFile // empty' "$m")
  if [ -z "$ctx" ]; then
    echo "FAIL: contextFile is absent — declare the document this harness auto-loads (REQUIRED; there is no default)"
    fail=1
  elif ctx_ok "$ctx"; then : ; else fail=1; fi

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
  # expect_why: `expect` PLUS the REASON. Use it for any rule that a rule ABOVE it in the chain could
  # mask, because an rc alone cannot tell the two apart and a green then attests nothing.
  # THIS IS NOT A STYLE PREFERENCE — it is the fix for a MEASURED vacuity. The symlink fixture below
  # used a DANGLING link, so the regular-file rule refused it before the symlink walk was ever reached;
  # with `ctx_path_has_symlink` stubbed to `return 1` the mutant SURVIVED on BOTH the populated-index and
  # the empty-index tree, and `non-vacuity.sh --only harness-adapter.sh` still reported KILLED because 32
  # other kills masked it. The rule the entire empty-index security argument rests on had ZERO coverage
  # while its fixture printed PASS. An rc-only assertion cannot see a substitution; this one can.
  expect_why() {  # <expected-rc> <adapter-dir> <label> <fixed substring the output MUST contain>
    ewe=$1; ewa=$2; ewl=$3; eww=$4
    ewo=$( ( sh "$0" "$ewa" ) 2>&1 ) && ewg=0 || ewg=$?
    if [ "$ewg" != "$ewe" ]; then
      echo "selftest FAIL: $ewl want $ewe got $ewg"; st=1; return 0
    fi
    if printf '%s\n' "$ewo" | LC_ALL=C grep -qF "$eww"; then
      echo "selftest PASS: $ewl -> rc $ewg (reason pinned)"
    else
      echo "selftest FAIL: $ewl exited $ewg but for the WRONG RULE — no '$eww' in its output"; st=1
    fi
  }

  mkconf "$base/ok" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"contextFile":"AGENTS.md","dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  expect 0 "$base/ok" "conformant (all floor, mcp n-a)"

  mkconf "$base/missing" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"contextFile":"AGENTS.md","dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  expect 1 "$base/missing" "missing review-roles dimension"

  mkconf "$base/missorch" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"contextFile":"AGENTS.md","dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"model-tiering":{"level":"floor"}}}'
  expect 1 "$base/missorch" "missing orchestration dimension"

  mkconf "$base/nocp" '{"harness":"fixture","controlPlanePaths":[],"bindingFiles":["AGENTS.md"],"contextFile":"AGENTS.md","dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  expect 1 "$base/nocp" "empty controlPlanePaths"

  mkconf "$base/lie" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"contextFile":"AGENTS.md","dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"native","proof":{"files":["does-not-exist-xyz.txt"]}},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  expect 1 "$base/lie" "lying-native (native proof file missing)"

  mkconf "$base/badcheck" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"contextFile":"AGENTS.md","dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"native","proof":{"check":"false"}},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  expect 1 "$base/badcheck" "lying-native (proof.check exits non-zero)"

  mkconf "$base/noproof" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"contextFile":"AGENTS.md","dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"native"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  expect 1 "$base/noproof" "native with no proof declared"

  mkconf "$base/badbind" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["nope-not-here.txt"],"contextFile":"AGENTS.md","dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  expect 1 "$base/badbind" "missing bindingFile"

  # D2: proof.check allowlist — a check with shell metacharacters or outside conformance/
  # must be REJECTED BEFORE EXECUTION (no side effect), not run.
  canary="$base/canary"
  mkconf "$base/metachar" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"contextFile":"AGENTS.md","dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"native","proof":{"check":"conformance/agents-brief.sh; touch __CANARY__"}},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  sed "s#__CANARY__#$canary#" "$base/metachar/adapter.json" > "$base/metachar/adapter.tmp" && mv "$base/metachar/adapter.tmp" "$base/metachar/adapter.json"
  expect 1 "$base/metachar" "proof.check with metacharacters (lying-native)"
  if [ -e "$canary" ]; then echo "selftest FAIL: metachar proof.check EXECUTED (canary created)"; st=1; else echo "selftest PASS: metachar proof.check not executed"; fi
  mkconf "$base/escape" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"contextFile":"AGENTS.md","dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"native","proof":{"check":"../evil.sh"}},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  expect 1 "$base/escape" "proof.check outside conformance/ (lying-native)"

  # model-tiering: native declared with a broken proof -> lying-native -> FAIL
  mkconf "$base/mtlie" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"contextFile":"AGENTS.md","dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"native","proof":{"check":"conformance/does-not-exist-mt.sh"}}}}'
  expect 1 "$base/mtlie" "model-tiering native + broken proof (lying-native)"
  # model-tiering omitted entirely -> required-dim -> FAIL
  mkconf "$base/mtmiss" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"contextFile":"AGENTS.md","dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"}}}'
  expect 1 "$base/mtmiss" "model-tiering dimension omitted"

  # an UNDECLARED dimension: all 7 real dims valid, plus a dimension the Kit enforces no floor
  # for. There is no Kit-enforced floor to hold, so it may not be accepted -> FAIL (fail-CLOSED).
  mkconf "$base/unknowndim" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"contextFile":"AGENTS.md","dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"},"not-a-real-dimension":{"level":"floor"}}}'
  expect 1 "$base/unknowndim" "unknown dimension -> FAIL (closes the floor_holds fail-open)"

  # The closed-set rule must not be defeatable by the SHAPE of the key. A key materialised into a
  # shell string and word-split DISAPPEARS when it is empty or whitespace-only, or splits into names
  # already in $DIMS — measured bypasses, all rc=0 OK. Each is declared `native` with a proof.check
  # naming a file that does NOT exist, so a regression that drops the key also skips the lying-native
  # guard, and one fixture catches both holes.
  lyingnative='{"level":"native","proof":{"check":"conformance/does-not-exist-xyz.sh"}}'
  seven='"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}'
  # $hdr deliberately carries NO contextFile and $hdrctx is the valid-contextFile variant. Folding the
  # field into $hdr itself would have been shorter and WRONG: the contextFile negatives below append
  # their own value, and a duplicate JSON key resolves to the LAST one — so `nocontext`, the fixture
  # whose entire job is to prove an ABSENT field is fatal, would have silently inherited a valid one and
  # attested nothing. Two variables, no reliance on duplicate-key semantics.
  hdr='"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"]'
  hdrctx="$hdr,\"contextFile\":\"AGENTS.md\""
  mkconf "$base/emptykey"  "{$hdrctx,\"dimensions\":{$seven,\"\":$lyingnative}}"
  expect 1 "$base/emptykey" "extra key is the empty string (word-splits to nothing)"
  mkconf "$base/wskey"     "{$hdrctx,\"dimensions\":{$seven,\"   \":$lyingnative}}"
  expect 1 "$base/wskey" "extra key is whitespace only (word-splits to nothing)"
  mkconf "$base/splitkey"  "{$hdrctx,\"dimensions\":{$seven,\"mcp-gate model-tiering\":$lyingnative}}"
  expect 1 "$base/splitkey" "extra key word-splits into two KNOWN dimension names"
  mkconf "$base/trailkey"  "{$hdrctx,\"dimensions\":{$seven,\"command-guard \":$lyingnative}}"
  expect 1 "$base/trailkey" "extra key is a known name plus a trailing space"

  # bindingFiles are adopter-supplied and were read through an unquoted `$(...)` BEFORE globbing was
  # disabled, so `["*"]` PATHNAME-expanded to the repo-root entries — every one of which exists.
  # Measured: rc=0 OK while the manifest declared no real binding file at all.
  mkconf "$base/globbind" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["*"],"contextFile":"AGENTS.md","dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  expect 1 "$base/globbind" "bindingFiles ['*'] must not glob-expand"

  # SAME defect class, SECOND site: proof.files is adopter-supplied and word-split too. Measured at
  # HEAD, `"proof":{"files":["*"]}` expanded to the repo-root entries and every one existed, so a
  # `native` claim passed carrying no proof at all (rc=0 OK). It is closed only INCIDENTALLY while a
  # `set -f` wraps the whole dimension loop; scoping that `set -f` to bindingFiles re-opens it unless
  # native_proof_ok disables globbing itself. This fixture pins it to native_proof_ok.
  mkconf "$base/globproof" '{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"contextFile":"AGENTS.md","dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"native","proof":{"files":["*"]}},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"},"model-tiering":{"level":"floor"}}}'
  expect 1 "$base/globproof" "proof.files ['*'] must not glob-expand (lying-native)"

  # ---- contextFile: the REQUIRED field naming the document the harness AUTO-LOADS.
  # The whole point of the field is that an ABSENT one is fatal. A default (to AGENTS.md, the obvious
  # candidate) would silently reinstate the exact defect the field exists to close, for every adapter
  # added from here on — so `nocontext` is the load-bearing fixture of this whole group.
  mkconf "$base/nocontext" "{$hdr,\"dimensions\":{$seven}}"
  expect 1 "$base/nocontext" "contextFile absent -> FAIL (never a default)"

  # The value is unratified manifest input, so it is boundary-validated exactly like proof.check —
  # `adapters/` being control-plane did not exempt proof.check and does not exempt this either.
  mkconf "$base/absctx"    "{$hdr,\"contextFile\":\"/etc/hostname\",\"dimensions\":{$seven}}"
  expect 1 "$base/absctx" "contextFile is an ABSOLUTE path -> FAIL"
  mkconf "$base/dotdotctx" "{$hdr,\"contextFile\":\"../outside-this-tree.md\",\"dimensions\":{$seven}}"
  expect 1 "$base/dotdotctx" "contextFile traverses with '..' -> FAIL"

  # THE SAME GLOB CLASS AS globbind/globproof, THIRD SITE — and this one bites on the GIT side, not the
  # shell side: a git pathspec is a glob by default, so `git ls-files --error-unmatch -- '*'` MATCHES
  # (measured: exit 0 on this repo) and a bare tracked-check would accept a manifest that names no
  # document at all. Closed twice over — the worktree test is on a QUOTED value so `*` is a literal
  # filename that does not exist, and the index test passes --literal-pathspecs.
  mkconf "$base/globctx"   "{$hdr,\"contextFile\":\"*\",\"dimensions\":{$seven}}"
  expect 1 "$base/globctx" "contextFile ['*'] must not pathspec-expand"
  # A DIRECTORY is a tracked pathspec too (`git ls-files --error-unmatch -- conformance` exits 0,
  # measured), and its first index mode is 100644, so a dir would clear both index-side tests. It is
  # not a document; the regular-file test is what refuses it.
  mkconf "$base/dirctx"    "{$hdr,\"contextFile\":\"conformance\",\"dimensions\":{$seven}}"
  expect 1 "$base/dirctx" "contextFile names a DIRECTORY -> FAIL"
  mkconf "$base/missingctx" "{$hdr,\"contextFile\":\"no-such-context-file-xyz.md\",\"dimensions\":{$seven}}"
  expect 1 "$base/missingctx" "contextFile does not exist -> FAIL"

  # RULE 3 (symlink) and RULE 5 (tracked) need REAL on-disk witnesses. A nonexistent path would be
  # refused by the regular-file rule first, and the fixture would then attest nothing about the rule it
  # is named after — the vacuity this file has already been bitten by twice. Both witnesses live under
  # the repo-root `.nv-` prefix that .gitignore already carries (so a leaked artifact can never be
  # committed) and are removed immediately after use.
  ctxsym=".nv-hactx-symlink.md"; ctxuntracked=".nv-hactx-untracked.md"
  # THE LINK TARGET MUST RESOLVE. It used to be `../outside-this-tree.md` — a DANGLING link, which the
  # regular-file rule (`[ -f ]` follows the link and finds nothing) refused BEFORE the symlink walk was
  # ever credited. Pointing it at a real tracked file leaves the symlink walk as the ONLY rule that can
  # refuse it: `[ -f ]` now succeeds, and so does the tracked check on the link's target name. That is
  # what makes the mutant on ctx_path_has_symlink die instead of survive. Paired with expect_why below —
  # the target change makes the rule REACHABLE, the reason assertion proves it is what actually fired.
  ln -sf AGENTS.md "$ctxsym"
  printf '# untracked context document\n' > "$ctxuntracked"
  # ceremony-binding MED-5, third recurrence in this surface area: a symlink whose content is not in the
  # tree would let A1.3's position-assert read a document that appears in NO diff.
  mkconf "$base/symctx"    "{$hdr,\"contextFile\":\"$ctxsym\",\"dimensions\":{$seven}}"
  expect_why 1 "$base/symctx" "contextFile is a SYMLINK -> FAIL" "is, or is reached through, a SYMLINK"
  # The tracked rule is asserted only where an index can answer it (see ctx_ok) — so is its fixture.
  # Guarding the ASSERTION with the same predicate as the RULE is what keeps this honest in both
  # environments instead of green in one and red in the other. `-- ':/'` here is in LOCKSTEP with ctx_ok's
  # own probe; if the two ever disagree this fixture runs against a rule that did not.
  if [ -n "$(git ls-files -- ':/' 2>/dev/null | head -1)" ]; then
    mkconf "$base/untrackedctx" "{$hdr,\"contextFile\":\"$ctxuntracked\",\"dimensions\":{$seven}}"
    expect_why 1 "$base/untrackedctx" "contextFile exists but is UNTRACKED -> FAIL" "is not a tracked file"
  else
    echo "selftest n/a: untracked-contextFile fixture (no populated git index in this tree)"
  fi
  rm -f "$ctxsym" "$ctxuntracked"

  # ---- .git components: MEASURED rc=0 on the adopter tree for all three of these. The tracked rule was
  # the ONLY thing refusing them, and an empty index skips exactly that rule — so the refusal was missing
  # precisely where the adopter runs. These carry expect_why because on a POPULATED index the tracked rule
  # would refuse them too: an rc-only fixture would go green here and still be blind to the regression
  # that matters (the unconditional rule being removed), which is the same masking that made symctx
  # vacuous. Pinning the reason is what makes these fixtures mean the same thing on both trees.
  mkconf "$base/gitctx"     "{$hdr,\"contextFile\":\".git/config\",\"dimensions\":{$seven}}"
  expect_why 1 "$base/gitctx" "contextFile '.git/config' -> FAIL" "reaches into the .git DIRECTORY"
  mkconf "$base/githeadctx" "{$hdr,\"contextFile\":\".git/HEAD\",\"dimensions\":{$seven}}"
  expect_why 1 "$base/githeadctx" "contextFile '.git/HEAD' -> FAIL" "reaches into the .git DIRECTORY"
  mkconf "$base/githookctx" "{$hdr,\"contextFile\":\".git/hooks/pre-commit.sample\",\"dimensions\":{$seven}}"
  expect_why 1 "$base/githookctx" "contextFile '.git/hooks/*' -> FAIL" "reaches into the .git DIRECTORY"
  # Case-folded: a case-insensitive filesystem resolves these to the same bytes git itself resolves.
  mkconf "$base/gitupperctx" "{$hdr,\"contextFile\":\".GIT/config\",\"dimensions\":{$seven}}"
  expect_why 1 "$base/gitupperctx" "contextFile '.GIT/config' (case-folded) -> FAIL" "reaches into the .git DIRECTORY"
  mkconf "$base/gitmixedctx" "{$hdr,\"contextFile\":\".Git/HEAD\",\"dimensions\":{$seven}}"
  expect_why 1 "$base/gitmixedctx" "contextFile '.Git/HEAD' (case-folded) -> FAIL" "reaches into the .git DIRECTORY"
  # THE FALSE-POSITIVE PROBE, and the strongest one available: `.gitignore` is a tracked regular file
  # whose NAME begins with the refused string. A naive `*git*` or prefix match would wrongly refuse it.
  # Whole-COMPONENT comparison is what keeps this rc 0, and this fixture is what proves the refusal was
  # not bought by breaking a legitimate document.
  mkconf "$base/gitignorectx" "{$hdr,\"contextFile\":\".gitignore\",\"dimensions\":{$seven}}"
  expect 0 "$base/gitignorectx" "contextFile '.gitignore' stays LEGAL (whole-component, not substring)"

  # ---- '.' and EMPTY components: an ALIASING defect, not a traversal one. MEASURED rc=0 for all three.
  # Two adapters spelling one document differently read as two distinct bindings, and the per-adapter
  # byte-identity invariant would then be asserted twice over one file with neither spelling canonical.
  mkconf "$base/dotctx"    "{$hdr,\"contextFile\":\"./AGENTS.md\",\"dimensions\":{$seven}}"
  expect_why 1 "$base/dotctx" "contextFile './AGENTS.md' -> FAIL" "has a '.' path component"
  mkconf "$base/dotdotslashctx" "{$hdr,\"contextFile\":\"././AGENTS.md\",\"dimensions\":{$seven}}"
  expect_why 1 "$base/dotdotslashctx" "contextFile '././AGENTS.md' -> FAIL" "has a '.' path component"
  mkconf "$base/emptycompctx" "{$hdr,\"contextFile\":\"conformance//verify.sh\",\"dimensions\":{$seven}}"
  expect_why 1 "$base/emptycompctx" "contextFile 'conformance//verify.sh' -> FAIL" "has an EMPTY path component"

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
  # The FAIL path prints FOUR of the five adopter-controlled sinks; this fixture spans all four:
  # the extra dimension key, the bindingFile, the contextFile, and — measured raw at the pre-fix tree —
  # `FAIL: 'model-tiering' has invalid level 'flo<raw ESC>[2Kor'`.
  # contextFile is the sink this slice ADDS, so it is carried HERE rather than in a fixture of its own:
  # the value below reaches its FAIL line on this very run (measured — the "not a regular file" arm),
  # and the byte assertion below scans the whole output, so dropping its `_san` reddens this fixture.
  # It CANNOT span the fifth. `.harness` is printed only on the OK line, and this fixture exits down
  # the FAIL path where `.harness` is never printed at all (measured: zero occurrences). A fixture
  # that merely carried an ANSI `.harness` HERE would be vacuous — a green attesting a sink it never
  # exercised. That is the same substitution-blindness the rest of this slice closes, so the success
  # sink gets its own rc=0 fixture (`ansiok`) below rather than a passenger field in this one.
  sevenansilvl="\"context-binding\":{\"level\":\"floor\"},\"command-guard\":{\"level\":\"floor\"},\"history-protection\":{\"level\":\"floor\"},\"review-roles\":{\"level\":\"floor\"},\"mcp-gate\":{\"level\":\"n-a\"},\"orchestration\":{\"level\":\"floor\"},\"model-tiering\":{\"level\":\"flo${esc}[2Kor\"}"
  mkconf "$base/ansikey" "{\"harness\":\"fixture\",\"controlPlanePaths\":[\".claude/settings.json\"],\"bindingFiles\":[\"${esc}[2Kfake.txt\"],\"contextFile\":\"${esc}[2K${del}fake-context.md\",\"dimensions\":{$sevenansilvl,\"${esc}[2K${del}evil\":{\"level\":\"floor\"}}}"
  expect 1 "$base/ansikey" "ANSI/DEL extra key + ANSI bindingFile + ANSI contextFile + ANSI level still FAIL"
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
  mkconf "$base/ansiok" "{\"harness\":\"fix${esc}[2K${del}ture\",\"controlPlanePaths\":[\".claude/settings.json\"],\"bindingFiles\":[\"AGENTS.md\"],\"contextFile\":\"AGENTS.md\",\"dimensions\":{$seven}}"
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
