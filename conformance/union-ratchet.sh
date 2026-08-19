#!/bin/sh
# union-ratchet.sh — THE UNION RECLASSIFICATION RATCHET (GUARD-PATH-ENUMERATION-INCOMPLETE S3).
#
# THE PROPERTY (design docs/architecture/2026-08-18-union-ratchet-s3-design.md §2, narrow on
# purpose): base-union ⊆ head-union ∪ acknowledged. For a run where a base revision is resolvable
# (PR/CI context), this derives the adapter-declared control-plane union (kit_union_derive over
# adapters/*/adapter.json — conformance/union-lib.sh, the S2 union authority) at BASE and at HEAD.
# Any entry present at base and absent at head is a DECLASSIFICATION — a `controlPlanePaths` line
# removed, or a whole adapter manifest deleted — and reds this check UNLESS the removal is
# acknowledged in conformance/union-declass.txt (the acknowledgment ledger, see its own header).
#
# WHY THIS EXISTS: S2 shipped the union authority and its own census PROVES the union is consulted
# at `--class` — but nothing stopped the union from silently SHRINKING. A CP-ratified edit removing
# a `controlPlanePaths` entry (or deleting a manifest outright) sails through the census green by
# construction (the census derives the union FRESH each run) while narrowing what every future PR
# must ratify. This converts "ratified but silent" into "ratified and DECLARED".
#
# DELIBERATELY OUT OF SCOPE (design §2): guard-side declassification (a guard-core pattern
# narrowing) is NOT covered here — guard-core edits are themselves CP-ratified AND carry the
# mandatory security vet, a stronger control than a declaration line. A green here says nothing
# about that surface.
#
# BASE LADDER (design §3 M2, vet L1) — TWO STATED, never a silent third:
#   CI    — $GITHUB_BASE_REF set: merge-base HEAD refs/remotes/origin/$GITHUB_BASE_REF (the
#           hermetic-lane pattern this repo's own ci.yml already uses for the same reason).
#   local — the promotion-readiness.sh ladder: merge-base HEAD origin/main, else merge-base HEAD
#           main.
#   Unresolvable either way -> `NA <reason>`, never a fail-open silent pass and never a false red.
#
# BASE DERIVATION (design §3 H2) — ls-tree materialization, NEVER a worktree glob: a worktree glob
# against `git show <base>:adapters/*/adapter.json` expands against the WORKTREE and silently
# OMITS base-only manifests — exactly the wholesale-deletion case this check exists to catch. Base
# manifests are enumerated with `git ls-tree` (the SAME one-level `adapters/*/adapter.json` shape
# kit_union_derive's own glob walks — never a second enumeration shape), materialized into a temp
# directory via `git show <base>:<path>`, then fed to kit_union_derive itself (never a second
# parser). ANY git failure mid-materialization is UNAVAILABLE — never a partial base union, which
# would be a silently-narrower base and a missed declassification.
#
# rc IS READ ON BOTH SIDES (design §3 M4): either side UNAVAILABLE (rc 1) -> `NA <reason>`, never
# ignored and never fail-open. The agent-boundary ignore-the-rc posture is FORBIDDEN here — this is
# precisely the silent-narrowing defect class that posture would reintroduce. Base rc 3 (OK-EMPTY,
# e.g. a base predating adapters/) -> `BASE-EMPTY`, a vacuous pass WITH a statement, not silence.
#
# `KIT_ADAPTERS_DIR` set -> `NA <reason>` (design §3 L3): an env-redirected HEAD union compared
# against a git-derived BASE union compares two universes and would manufacture phantom
# declassifications; refuse honestly instead of guessing.
#
# THE ACKNOWLEDGMENT LEDGER + THE THREE-WAY RULE — see conformance/union-declass.txt's own header
# for the full grammar. In short: an ack line is graded PRE-EMPTIVE (red, entry still in the HEAD
# union — base-independent), LIVE (green, entry left base and is absent from head), or INERT
# (neither union — never printed). Matching is byte-exact string equality throughout — union
# entries may themselves carry a literal `*`, so a glob match would be a standing blanket amnesty.
#
# LINE-KIND VOCABULARY (closed, design §3 M3) — the only meaningful lines this check ever prints:
#   DECLASS <entry>   (red)   — a base-only entry with no acknowledgment covering it.
#   ACK <entry>       (green) — a base-only, head-absent entry WITH a live acknowledgment.
#   PREEMPT <entry>   (red)   — an acknowledged entry that is STILL in the head union.
#   BASE-EMPTY        (info)  — the base declares no adapters at all; nothing to compare.
#   NA <reason>       (info)  — the run could not be graded; not a pass claiming more than it knows.
#   ALIVE             (sentinel, always the FINAL line — empty output is the caller's FAIL)
#
#   sh conformance/union-ratchet.sh [--selftest]
# Exit: 0 = no DECLASS/PREEMPT line was printed · 1 = at least one was · 2 = bad usage.
# POSIX sh; dash-clean. Registered as a WORKFLOW check (a PR-context step in .github/workflows/ci.yml's
# conformance-core job) — NOT a conformance/verify.sh offline row: this check is base-relative and
# fails closed with no PR base to compare against, so it cannot live in the portable offline battery
# without false-reddening every base-less caller (the same reasoning threat-obligation.sh and
# uat-obligation.sh state for their own diff-relative gates).
set -eu
CDPATH=''
DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$DIR"

LEDGER="conformance/union-declass.txt"
UNION_LIB="conformance/union-lib.sh"

# shellcheck source=/dev/null  # a fixed kit path resolved at runtime, not statically followable
[ -f "$UNION_LIB" ] && . "$UNION_LIB"

# _ur_na <reason> — print the NA line + PREEMPT lines already accumulated + ALIVE, then exit with
# the correct rc (1 if any red line — PREEMPT — was already printed, else 0). NA is a refusal to
# grade base-relative membership, NOT a licence to un-print an already-detected PREEMPT violation.
_ur_na() {
  printf 'NA %s\n' "$1"
  printf 'ALIVE\n'
  [ "$_UR_RED" = 0 ] && exit 0 || exit 1
}

run_union_ratchet() {
  _UR_RED=0

  # THE UNION AUTHORITY MUST BE AVAILABLE AT ALL — before anything else. Without it there is no
  # reliable notion of "the union" on either side, so refuse rather than guess.
  if ! command -v kit_union_derive >/dev/null 2>&1; then
    _ur_na "the union authority ($UNION_LIB) could not be sourced — the adapter-declared control-plane surface cannot be read on either side"
  fi

  # L3 — KIT_ADAPTERS_DIR set: an env-redirected HEAD union compared against a git-derived BASE
  # union compares two universes. Checked BEFORE deriving anything (design §3 L3).
  if [ -n "${KIT_ADAPTERS_DIR:-}" ]; then
    _ur_na "KIT_ADAPTERS_DIR is set to '$KIT_ADAPTERS_DIR' — comparing a git-derived base union against an env-redirected head union compares two universes; refusing rather than manufacturing a phantom declassification"
  fi
  ADAPTERS_DIR=adapters

  # ── PARSE THE ACKNOWLEDGMENT LEDGER (before either union derivation: the PREEMPT arm below is
  # base-independent and needs the ack set regardless of whether a base ever resolves).
  # A line with any field count other than 3 (2 tabs) is MALFORMED and is NEVER treated as an
  # acknowledgment — the entry it names, if any, still reds as an unacknowledged DECLASS. This is
  # the fail-closed posture design §3 asks for a malformed line, expressed through the EXISTING
  # DECLASS token rather than a new line-kind (the vocabulary above is closed).
  _UR_ACKS=""
  if [ -f "$LEDGER" ]; then
    _ur_ln=0
    # NO `|| [ -n "$_ur_line" ]` FINAL-LINE FALLBACK, DELIBERATELY: this file is always written with
    # a trailing newline (the header + every printf-built line in production and in every selftest
    # fixture), and `read`'s undefined-on-EOF variable retention across shells makes that fallback a
    # latent infinite-loop hazard on a file that happens to lack one — safer to require the newline.
    while IFS= read -r _ur_line; do
      _ur_ln=$((_ur_ln + 1))
      case "$_ur_line" in
        ''|'#'*) continue ;;
      esac
      _ur_tabs=$(printf '%s' "$_ur_line" | LC_ALL=C tr -cd '\t' | wc -c | tr -d ' ')
      if [ "$_ur_tabs" != 2 ]; then
        echo "union-ratchet: malformed ledger line $_ur_ln in $LEDGER (expected 3 tab-separated fields: date, entry, reason) — NOT treated as an acknowledgment" >&2
        continue
      fi
      _ur_entry=$(printf '%s\n' "$_ur_line" | awk -F'\t' '{print $2}')
      if [ -z "$_ur_entry" ]; then
        echo "union-ratchet: malformed ledger line $_ur_ln in $LEDGER (empty entry field) — NOT treated as an acknowledgment" >&2
        continue
      fi
      _UR_ACKS="$_UR_ACKS$_ur_entry
"
    done < "$LEDGER"
  fi

  # ── HEAD UNION.
  HEAD_LIST=$(kit_union_derive "$ADAPTERS_DIR" strict) && _ur_head_rc=0 || _ur_head_rc=$?
  case "$_ur_head_rc" in
    0) ;;                                             # OK
    3) HEAD_LIST="" ;;                                # OK-EMPTY — no manifests at head at all
    *) _ur_na "the head adapter-declared surface under '$ADAPTERS_DIR' is UNAVAILABLE (see stderr) — a partial head union could hide a still-declared entry as a false declassification" ;;
  esac

  # ── THE PREEMPT ARM — BASE-INDEPENDENT (design §3 M1, vet-amended). Any acknowledged entry that
  # is STILL declared at head is a pre-emptive acknowledgment, forbidden regardless of base state.
  if [ -n "$_UR_ACKS" ]; then
    while IFS= read -r _ur_a; do
      [ -n "$_ur_a" ] || continue
      if [ -n "$HEAD_LIST" ] && printf '%s\n' "$HEAD_LIST" | grep -qxF -- "$_ur_a"; then
        printf 'PREEMPT %s\n' "$_ur_a"
        _UR_RED=1
      fi
    done <<EOF
$_UR_ACKS
EOF
  fi

  # ── RESOLVE THE BASE — CI ladder first, else the local ladder (design §3 L1).
  BASE=""
  if [ -n "${GITHUB_BASE_REF:-}" ]; then
    BASE=$(git merge-base HEAD "refs/remotes/origin/$GITHUB_BASE_REF" 2>/dev/null) || BASE=""
    [ -n "$BASE" ] || _ur_na "no resolvable CI base — merge-base HEAD refs/remotes/origin/$GITHUB_BASE_REF failed (is the base ref fetched?)"
  else
    BASE=$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || true)
    [ -n "$BASE" ] || _ur_na "no resolvable local base — neither origin/main nor main exists as an ancestor context; run this in a PR/CI context, or pass GITHUB_BASE_REF"
  fi

  # ── MATERIALIZE THE BASE UNION — ls-tree enumeration, never a worktree glob (design §3 H2).
  _ur_tmp=$(mktemp -d) || _ur_na "could not create a temp directory to materialize the base union"
  trap 'rm -rf "$_ur_tmp"' EXIT INT TERM
  _ur_top=$(git ls-tree --name-only "$BASE" -- adapters/ 2>/dev/null) || {
    _ur_na "the base revision's adapters/ directory could not be enumerated (git ls-tree failed)"
  }
  # `set -f` around the enumeration loop — the union-lib precedent (kit_path_in_union): unquoted word
  # splitting is needed (one path per line), but pathname expansion must NOT ride along with it — a
  # base-only manifest directory whose name happens to carry a glob metacharacter must not be silently
  # substituted for whatever happens to match it in the CURRENT working tree. Save/restore the
  # caller's noglob state rather than an unconditional `set +f`, same reason guard-core.sh does.
  _ur_g=0; case "$-" in *f*) _ur_g=1 ;; esac
  set -f
  for _ur_d in $_ur_top; do
    _ur_probe=$(git ls-tree --name-only "$BASE" -- "$_ur_d/adapter.json" 2>/dev/null) || {
      _ur_na "the base revision could not be probed for '$_ur_d/adapter.json' (git ls-tree failed) — refusing a partial base union"
    }
    [ -n "$_ur_probe" ] || continue
    _ur_name=$(basename "$_ur_d")
    mkdir -p "$_ur_tmp/$_ur_name" || _ur_na "could not create a materialization directory for '$_ur_d'"
    if ! git show "$BASE:$_ur_d/adapter.json" > "$_ur_tmp/$_ur_name/adapter.json" 2>/dev/null; then
      _ur_na "'git show $BASE:$_ur_d/adapter.json' failed mid-materialization — refusing a partial base union (a partial base is a silently narrower base, i.e. a missed declassification)"
    fi
  done
  [ "$_ur_g" = 1 ] || set +f

  BASE_LIST=$(kit_union_derive "$_ur_tmp" strict) && _ur_base_rc=0 || _ur_base_rc=$?
  case "$_ur_base_rc" in
    0) ;;                                              # OK
    3)                                                 # BASE-EMPTY — the base declares no adapters at all
      printf 'BASE-EMPTY\n'
      printf 'ALIVE\n'
      [ "$_UR_RED" = 0 ] && exit 0 || exit 1 ;;
    *) _ur_na "the materialized base union is UNAVAILABLE (see stderr) — a partial base union could hide a real declassification" ;;
  esac

  # ── THE COMPARISON. Byte-exact string equality throughout (design §3 M2, vet M2) — never a case
  # fold, never kit_path_in_union's glob matching: union entries may themselves contain a literal
  # `*`, so glob-matching an ack line against an entry would be a standing blanket amnesty.
  if [ -n "$BASE_LIST" ]; then
    while IFS= read -r _ur_b; do
      [ -n "$_ur_b" ] || continue
      if [ -n "$HEAD_LIST" ] && printf '%s\n' "$HEAD_LIST" | grep -qxF -- "$_ur_b"; then
        continue   # still present at head — no declassification
      fi
      # base-only entry: was it acknowledged? (already proven absent from head, above)
      if [ -n "$_UR_ACKS" ] && printf '%s\n' "$_UR_ACKS" | grep -qxF -- "$_ur_b"; then
        printf 'ACK %s\n' "$_ur_b"
      else
        printf 'DECLASS %s\n' "$_ur_b"
        _UR_RED=1
      fi
    done <<EOF
$BASE_LIST
EOF
  fi

  printf 'ALIVE\n'
  [ "$_UR_RED" = 0 ] && exit 0 || exit 1
}

# ═══════════════════════════════════════════════════════════════════════════ selftest() marker ══
# The kit's non-vacuity sweep mutates only lines ABOVE this marker; every fixture below stays live.
selftest() {
  _self=$(CDPATH='' cd "$(dirname "$0")" && pwd)/$(basename "$0")
  _lib="$(dirname "$_self")/union-lib.sh"
  W=$(mktemp -d)
  trap 'rm -rf "$W"' EXIT INT TERM
  sfail=0

  # ── ONE SHARED GRADER (design §3 M3 — the _census_grade shape): positively matches ^DECLASS ,
  # never "something was left over", so a fourth future line-kind cannot silently read as a
  # divergence, and the ALIVE sentinel proves the run completed rather than died mid-script.
  _ur_grade() {  # <raw output> -> sets _g_state (NORUN|CLEAN|DIRTY), _g_declass, _g_ack, _g_preempt
    # Reset on EVERY call — a NORUN result must not retain a PRIOR call's DECLASS/ACK/PREEMPT values
    # (measured hazard: a caller reading $_g_declass after a NORUN would see the previous fixture's).
    _g_declass=""; _g_ack=""; _g_preempt=""
    if [ "$(printf '%s\n' "$1" | tail -1)" != ALIVE ]; then
      _g_state=NORUN
    else
      _g_declass=$(printf '%s\n' "$1" | grep '^DECLASS ' || true)
      _g_ack=$(printf '%s\n' "$1" | grep '^ACK ' || true)
      _g_preempt=$(printf '%s\n' "$1" | grep '^PREEMPT ' || true)
      if [ -n "$_g_declass" ] || [ -n "$_g_preempt" ]; then _g_state=DIRTY; else _g_state=CLEAN; fi
    fi
  }

  # ── FIXTURE PLUMBING. "Arming" per the S2 census's own fixture pattern (promotion-readiness-
  # wired.sh's mkrepo()/_cen_mroot): each throwaway repo is armed with a COPY of this script and of
  # union-lib.sh, so kit_union_derive genuinely runs inside the fixture rather than being borrowed
  # from the surrounding tree.
  ur_init() {  # <dir>
    rm -rf "$1"; mkdir -p "$1/conformance"
    cp "$_self" "$1/conformance/union-ratchet.sh"
    cp "$_lib" "$1/conformance/union-lib.sh"
    printf '# fixture ledger\n' > "$1/conformance/union-declass.txt"
    ( cd "$1" && git init -q && git config user.email t@t && git config user.name t )
  }
  ur_manifest() {  # <dir> <name> <cp-json-array-body>  e.g. ur_manifest d claude-code '".claude/","CODEOWNERS"'
    mkdir -p "$1/adapters/$2"
    printf '{"harness":"%s","controlPlanePaths":[%s]}\n' "$2" "$3" > "$1/adapters/$2/adapter.json"
  }
  ur_commit() { ( cd "$1" && git add -A >/dev/null 2>&1 && git commit -q -m "$2" >/dev/null 2>&1 ); }
  ur_branch_main_then_feat() {  # <dir> — base state on 'main', a 'feat' branch checked out to diverge from
    ( cd "$1" && git branch -M main && git checkout -q -b feat )
  }
  # ur_run <dir> -> the run's stdout. `|| true` is LOAD-BEARING under `set -eu`: the ratchet's own
  # rc is 1 whenever it reports a real violation, and `_out=$(ur_run "$1")` is an ASSIGNMENT whose
  # exit status is the captured command's — without this, every fixture designed to red would abort
  # the whole selftest silently the instant it exercised the very behavior being proven (measured on
  # first write: zero output, rc 1, no diagnostic — the exact silent-death shape this note now names).
  # HERMETICITY AGAINST AMBIENT CI ENV (CI-round fix; the selftest-hermetic stripped-env face /
  # backlog-presence's env scrubs are the precedent). On a REAL CI runner `GITHUB_BASE_REF` is set
  # GLOBALLY for the whole job — not just the one step that means to use it — so a fixture invocation
  # that does not explicitly scrub it inherits the AMBIENT ref, takes the CI ladder INSIDE the
  # fixture (where no matching `refs/remotes/origin/<ref>` exists), and answers `NA` instead of
  # exercising the fixture's own local ladder. Measured on PR #559's first CI run: legs (c)/(e)/(f)/
  # (g) each silently NA'd (`NA no resolvable CI base`, state=CLEAN) while reading 28/28 locally,
  # where the var happens to be unset — an environment-dependent green, not a hermetic one. Every env
  # var the check itself reads (`GITHUB_BASE_REF`, `KIT_ADAPTERS_DIR` — swept by grepping the
  # production logic for `${VAR:-}`) is scrubbed by default; `GITHUB_EVENT_NAME` is scrubbed too for
  # hygiene even though the script itself never reads it (only the ci.yml step wrapper does) — a
  # fixture harness should not depend on that staying true. The ONE exception is the leg that
  # DELIBERATELY exercises the CI ladder (ur_run_ci): it SETS `GITHUB_BASE_REF`/`GITHUB_EVENT_NAME`
  # explicitly to fixture-controlled values rather than inheriting whatever the runner happens to
  # have — the class fix, not a special-case patch for the four measured legs alone.
  ur_run() {  # <dir> -> stdout only
    ( cd "$1" && env -u GITHUB_BASE_REF -u GITHUB_EVENT_NAME -u KIT_ADAPTERS_DIR sh conformance/union-ratchet.sh ) 2>/dev/null || true
  }
  ur_rc() {  # <dir> -> rc of a real run
    _rc=0; ( cd "$1" && env -u GITHUB_BASE_REF -u GITHUB_EVENT_NAME -u KIT_ADAPTERS_DIR sh conformance/union-ratchet.sh ) >/dev/null 2>&1 || _rc=$?
    echo "$_rc"
  }
  # ur_run_ci <dir> <base-ref-name> -> stdout, EXPLICITLY exercising the CI ladder with
  # fixture-controlled values (never inherited from the ambient runner): GITHUB_BASE_REF is set to
  # the caller's ref, GITHUB_EVENT_NAME to a real value, KIT_ADAPTERS_DIR scrubbed (irrelevant to
  # this leg and must not leak in either).
  ur_run_ci() {
    ( cd "$1" && env -u KIT_ADAPTERS_DIR GITHUB_BASE_REF="$2" GITHUB_EVENT_NAME=pull_request sh conformance/union-ratchet.sh ) 2>/dev/null || true
  }

  # ── (a) entry removed, unacknowledged -> DECLASS red, rc 1.
  ur_init "$W/a"
  ur_manifest "$W/a" claude-code '".claude/hooks/","CODEOWNERS"'
  ur_commit "$W/a" base
  ur_branch_main_then_feat "$W/a"
  ur_manifest "$W/a" claude-code '".claude/hooks/"'   # drops CODEOWNERS
  ur_commit "$W/a" "drop CODEOWNERS from the union"
  _out=$(ur_run "$W/a")
  _ur_grade "$_out"
  if [ "$_g_state" = DIRTY ] && printf '%s\n' "$_g_declass" | grep -qxF 'DECLASS CODEOWNERS'; then
    echo "PASS: (a) unacknowledged removal -> DECLASS CODEOWNERS"
  else echo "FAIL: (a) unacknowledged removal — got state=$_g_state out=[$_out]"; sfail=1; fi
  if [ "$(ur_rc "$W/a")" = 1 ]; then echo "PASS: (a) rc 1 on an unacknowledged declassification"
  else echo "FAIL: (a) rc was not 1"; sfail=1; fi

  # ── (b) same removal + a correct ack line -> ACK green, rc 0.
  ur_init "$W/b"
  ur_manifest "$W/b" claude-code '".claude/hooks/","CODEOWNERS"'
  ur_commit "$W/b" base
  ur_branch_main_then_feat "$W/b"
  ur_manifest "$W/b" claude-code '".claude/hooks/"'
  printf '2026-08-18\tCODEOWNERS\tD-240818-1 no longer harness-declared, guard-core still covers it\n' >> "$W/b/conformance/union-declass.txt"
  ur_commit "$W/b" "drop CODEOWNERS, acknowledged"
  _out=$(ur_run "$W/b")
  _ur_grade "$_out"
  if [ "$_g_state" = CLEAN ] && printf '%s\n' "$_out" | grep -qxF 'ACK CODEOWNERS'; then
    echo "PASS: (b) acknowledged removal -> ACK CODEOWNERS, clean"
  else echo "FAIL: (b) acknowledged removal — got state=$_g_state out=[$_out]"; sfail=1; fi
  if [ "$(ur_rc "$W/b")" = 0 ]; then echo "PASS: (b) rc 0 on a fully acknowledged declassification"
  else echo "FAIL: (b) rc was not 0"; sfail=1; fi

  # ── (c) wholesale manifest deletion -> EVERY ONE of its entries DECLASS (plural, proven: the
  # deleted manifest carries TWO entries, not one, so a fixture with only one could not distinguish
  # "the whole manifest's entries DECLASS" from "one entry happened to DECLASS").
  ur_init "$W/c"
  ur_manifest "$W/c" claude-code '".claude/hooks/","CODEOWNERS"'
  ur_manifest "$W/c" cursor '".cursor/rules/","cursor.config.json"'
  ur_commit "$W/c" base
  ur_branch_main_then_feat "$W/c"
  rm -rf "$W/c/adapters/cursor"
  ur_commit "$W/c" "delete the cursor adapter manifest wholesale"
  _out=$(ur_run "$W/c")
  _ur_grade "$_out"
  if [ "$_g_state" = DIRTY ] \
     && printf '%s\n' "$_g_declass" | grep -qxF 'DECLASS .cursor/rules/' \
     && printf '%s\n' "$_g_declass" | grep -qxF 'DECLASS cursor.config.json'; then
    echo "PASS: (c) wholesale manifest deletion -> BOTH of its entries DECLASS (no special case, no partial credit)"
  else echo "FAIL: (c) wholesale manifest deletion — got state=$_g_state out=[$_out]"; sfail=1; fi
  # …and the SURVIVING manifest's entries must NOT be caught in the crossfire.
  if printf '%s\n' "$_out" | grep -qxF 'DECLASS CODEOWNERS'; then
    echo "FAIL: (c) an untouched manifest's entry was wrongly declassified"; sfail=1
  else echo "PASS: (c) the untouched manifest's entries are unaffected"; fi

  # ── (d) ack line for a STILL-DECLARED entry -> PREEMPT red, base-independent semantics proven by
  # running it with NO change at all between base and head (the entry never left).
  ur_init "$W/d"
  ur_manifest "$W/d" claude-code '".claude/hooks/","CODEOWNERS"'
  printf '2026-08-18\tCODEOWNERS\tpre-emptive, still declared\n' >> "$W/d/conformance/union-declass.txt"
  ur_commit "$W/d" base
  ur_branch_main_then_feat "$W/d"
  # An empty commit so 'feat' diverges from 'main' at all — the entry itself never changes.
  ( cd "$W/d" && git commit -q --allow-empty -m noop >/dev/null 2>&1 )
  _out=$(ur_run "$W/d")
  _ur_grade "$_out"
  if [ "$_g_state" = DIRTY ] && printf '%s\n' "$_g_preempt" | grep -qxF 'PREEMPT CODEOWNERS'; then
    echo "PASS: (d) an ack for a still-declared entry -> PREEMPT CODEOWNERS"
  else echo "FAIL: (d) pre-emptive ack — got state=$_g_state out=[$_out]"; sfail=1; fi
  if [ "$(ur_rc "$W/d")" = 1 ]; then echo "PASS: (d) rc 1 on a pre-emptive acknowledgment"
  else echo "FAIL: (d) rc was not 1"; sfail=1; fi

  # ── (d2) PREEMPT fires even when NO base resolves at all (base-independent, design §3 M1).
  ur_init "$W/d2"
  ur_manifest "$W/d2" claude-code '".claude/hooks/","CODEOWNERS"'
  printf '2026-08-18\tCODEOWNERS\tpre-emptive, no base at all\n' >> "$W/d2/conformance/union-declass.txt"
  ( cd "$W/d2" && git add -A >/dev/null 2>&1 && git commit -q -m base >/dev/null 2>&1 && git branch -M nomain-nomaster >/dev/null 2>&1 )
  _out=$(ur_run "$W/d2")
  if printf '%s\n' "$_out" | grep -qxF 'PREEMPT CODEOWNERS' && printf '%s\n' "$_out" | grep -q '^NA '; then
    echo "PASS: (d2) PREEMPT fires even when no base is resolvable at all"
  else echo "FAIL: (d2) base-independent PREEMPT — got out=[$_out]"; sfail=1; fi
  if [ "$(ur_rc "$W/d2")" = 1 ]; then echo "PASS: (d2) rc 1 even though the base itself is unresolvable"
  else echo "FAIL: (d2) rc was not 1"; sfail=1; fi

  # ── (e) malformed ledger line (wrong field count) -> red, fail-closed (the entry it was meant to
  # acknowledge stays an unacknowledged DECLASS — the closed vocabulary has no separate token).
  ur_init "$W/e"
  ur_manifest "$W/e" claude-code '".claude/hooks/","CODEOWNERS"'
  ur_commit "$W/e" base
  ur_branch_main_then_feat "$W/e"
  ur_manifest "$W/e" claude-code '".claude/hooks/"'
  printf '2026-08-18\tCODEOWNERS\n' >> "$W/e/conformance/union-declass.txt"   # only 2 fields
  ur_commit "$W/e" "drop CODEOWNERS with a malformed ack line"
  _out=$(ur_run "$W/e")
  _ur_grade "$_out"
  if [ "$_g_state" = DIRTY ] && printf '%s\n' "$_g_declass" | grep -qxF 'DECLASS CODEOWNERS'; then
    echo "PASS: (e) a malformed (2-field) ledger line is never treated as an acknowledgment -> DECLASS"
  else echo "FAIL: (e) malformed ledger line — got state=$_g_state out=[$_out]"; sfail=1; fi
  _err=$( ( cd "$W/e" && env -u GITHUB_BASE_REF -u GITHUB_EVENT_NAME -u KIT_ADAPTERS_DIR sh conformance/union-ratchet.sh ) 2>&1 >/dev/null ) || true
  case "$_err" in
    *"malformed ledger line"*) echo "PASS: (e) the malformed line is diagnosed on stderr" ;;
    *) echo "FAIL: (e) no diagnostic for the malformed ledger line: $_err"; sfail=1 ;;
  esac

  # ── (f) byte-exactness negative: an ack line of `*` must NOT acknowledge the literal entry
  # `conformance/*` — glob-matching an ack would be a standing blanket amnesty (design §3 vet M2).
  ur_init "$W/f"
  ur_manifest "$W/f" claude-code '"conformance/*"'
  ur_commit "$W/f" base
  ur_branch_main_then_feat "$W/f"
  ur_manifest "$W/f" claude-code '".claude/hooks/"'
  printf '2026-08-18\t*\tan attempted blanket ack, must not match\n' >> "$W/f/conformance/union-declass.txt"
  ur_commit "$W/f" "drop conformance/*, try to blanket-ack with a bare *"
  _out=$(ur_run "$W/f")
  _ur_grade "$_out"
  if [ "$_g_state" = DIRTY ] && printf '%s\n' "$_g_declass" | grep -qxF 'DECLASS conformance/*'; then
    echo "PASS: (f) a bare '*' ack line does NOT byte-match 'conformance/*' -> still DECLASS"
  else echo "FAIL: (f) byte-exactness negative — got state=$_g_state out=[$_out]"; sfail=1; fi

  # ── (g) base declares NO adapters at all -> BASE-EMPTY, a vacuous pass WITH a statement.
  ur_init "$W/g"
  : > "$W/g/nothing.txt"
  ur_commit "$W/g" base
  ur_branch_main_then_feat "$W/g"
  ur_manifest "$W/g" claude-code '".claude/hooks/"'
  ur_commit "$W/g" "introduce the first-ever adapter manifest"
  _out=$(ur_run "$W/g")
  if printf '%s\n' "$_out" | grep -qxF 'BASE-EMPTY' && [ "$(printf '%s\n' "$_out" | tail -1)" = ALIVE ]; then
    echo "PASS: (g) a base predating adapters/ -> BASE-EMPTY, ALIVE"
  else echo "FAIL: (g) BASE-EMPTY — got out=[$_out]"; sfail=1; fi
  if [ "$(ur_rc "$W/g")" = 0 ]; then echo "PASS: (g) rc 0 on BASE-EMPTY"
  else echo "FAIL: (g) rc was not 0 on BASE-EMPTY"; sfail=1; fi

  # ── (h) no base resolvable at all -> NA, rc 0 (no violations to report).
  ur_init "$W/h"
  ur_manifest "$W/h" claude-code '".claude/hooks/"'
  ( cd "$W/h" && git add -A >/dev/null 2>&1 && git commit -q -m base >/dev/null 2>&1 && git branch -M nomain-nomaster >/dev/null 2>&1 )
  # premise: neither origin/main nor main resolves in this fixture
  if ( cd "$W/h" && git rev-parse --verify main >/dev/null 2>&1 ); then
    echo "FAIL: (h) premise — fixture unexpectedly has a 'main' branch, the NA leg proves nothing"; sfail=1
  else
    echo "PASS: (h) premise — no 'main' and no 'origin/main' in this fixture"
  fi
  _out=$(ur_run "$W/h")
  if printf '%s\n' "$_out" | grep -q '^NA ' && [ "$(printf '%s\n' "$_out" | tail -1)" = ALIVE ]; then
    echo "PASS: (h) no resolvable base -> NA, ALIVE"
  else echo "FAIL: (h) no-base NA — got out=[$_out]"; sfail=1; fi
  if [ "$(ur_rc "$W/h")" = 0 ]; then echo "PASS: (h) rc 0 on an honest NA with nothing else to report"
  else echo "FAIL: (h) rc was not 0 on a bare NA"; sfail=1; fi

  # ── KIT_ADAPTERS_DIR set -> NA (design §3 L3), independent of everything else.
  ur_init "$W/envset"
  ur_manifest "$W/envset" claude-code '".claude/hooks/"'
  ur_commit "$W/envset" base
  _out=$( ( cd "$W/envset" && env -u GITHUB_BASE_REF -u GITHUB_EVENT_NAME KIT_ADAPTERS_DIR=/tmp/nope sh conformance/union-ratchet.sh ) 2>/dev/null )
  case "$_out" in
    *"KIT_ADAPTERS_DIR"*) echo "PASS: KIT_ADAPTERS_DIR set -> NA naming the variable" ;;
    *) echo "FAIL: KIT_ADAPTERS_DIR set did not NA naming the variable: $_out"; sfail=1 ;;
  esac

  # ── BOTH-SIDES RC HANDLING: a HEAD manifest that fails to parse -> UNAVAILABLE -> NA (never a
  # false-red naming an unrelated entry, never a silent pass).
  ur_init "$W/headbad"
  ur_manifest "$W/headbad" claude-code '".claude/hooks/"'
  ur_commit "$W/headbad" base
  ur_branch_main_then_feat "$W/headbad"
  printf 'not valid json {{{\n' > "$W/headbad/adapters/claude-code/adapter.json"
  ur_commit "$W/headbad" "corrupt the head manifest"
  _out=$(ur_run "$W/headbad")
  if printf '%s\n' "$_out" | grep -q '^NA '; then
    echo "PASS: a corrupt HEAD manifest (UNAVAILABLE) -> NA, never a false verdict"
  else echo "FAIL: corrupt head manifest — got out=[$_out]"; sfail=1; fi
  if printf '%s\n' "$_out" | grep -q '^DECLASS '; then
    echo "FAIL: a corrupt head manifest produced a DECLASS line — a partial head union false-reported a declassification"; sfail=1
  fi

  # ── BOTH-SIDES RC HANDLING, THE OTHER SIDE (vet M4's fail-open half): a BASE manifest that fails
  # to parse -> the MATERIALIZED base union is UNAVAILABLE -> NA, never a false pass and never a
  # false DECLASS. Distinct from headbad above: the base commit itself carries invalid JSON (the
  # ls-tree probe and git-show materialization both succeed — they move bytes, they do not validate
  # them — so this exercises kit_union_derive's own parse failure on the MATERIALIZED tmp dir, not a
  # materialization failure). The entry a naive implementation might have reported removed
  # (CODEOWNERS, present at head but unreadable at base) must NOT appear as a DECLASS.
  ur_init "$W/basebad"
  mkdir -p "$W/basebad/adapters/claude-code"
  printf 'not valid json {{{\n' > "$W/basebad/adapters/claude-code/adapter.json"
  ur_commit "$W/basebad" "base with a corrupt manifest"
  ur_branch_main_then_feat "$W/basebad"
  ur_manifest "$W/basebad" claude-code '".claude/hooks/","CODEOWNERS"'   # head: a valid, DIFFERENT manifest
  ur_commit "$W/basebad" "head repairs the manifest (base stays corrupt)"
  _out=$(ur_run "$W/basebad")
  if printf '%s\n' "$_out" | grep -q '^NA '; then
    echo "PASS: a corrupt BASE manifest (UNAVAILABLE) -> NA, never a false verdict"
  else echo "FAIL: corrupt base manifest — got out=[$_out]"; sfail=1; fi
  if printf '%s\n' "$_out" | grep -q '^DECLASS '; then
    echo "FAIL: a corrupt base manifest produced a DECLASS line — the fail-open half of M4 is broken (an unreadable base must never be read as 'nothing was there', which would either miss or fabricate a declassification)"; sfail=1
  else echo "PASS: a corrupt base manifest produces ZERO DECLASS lines (fail-open, not fail-fabricate)"; fi

  # ── LIVENESS ANCHOR: an unrelated, untouched ordinary change between base and head must be
  # completely clean (no DECLASS/ACK/PREEMPT at all) — proves the comparison is not vacuously red.
  ur_init "$W/clean"
  ur_manifest "$W/clean" claude-code '".claude/hooks/","CODEOWNERS"'
  ur_commit "$W/clean" base
  ur_branch_main_then_feat "$W/clean"
  printf 'x\n' > "$W/clean/README.md"
  ur_commit "$W/clean" "an ordinary, unrelated change"
  _out=$(ur_run "$W/clean")
  _ur_grade "$_out"
  if [ "$_g_state" = CLEAN ] && [ -z "$_g_ack" ]; then
    echo "PASS: an unrelated ordinary change is completely clean (no DECLASS/ACK/PREEMPT)"
  else echo "FAIL: liveness anchor — an untouched union produced output beyond ALIVE: [$_out]"; sfail=1; fi

  # ── THE CI LADDER (design §3 L1): $GITHUB_BASE_REF set -> merge-base HEAD
  # refs/remotes/origin/$GITHUB_BASE_REF, the SAME shape ci.yml's own hermetic lane already uses.
  # `git update-ref` stands in for the CI step's own `git fetch` — the ratchet's derivation cannot
  # tell the difference, and this keeps the fixture offline/hermetic.
  ur_init "$W/ci"
  ur_manifest "$W/ci" claude-code '".claude/hooks/","CODEOWNERS"'
  ur_commit "$W/ci" base
  ( cd "$W/ci" && git branch -M release-line )
  _ci_base_sha=$( cd "$W/ci" && git rev-parse HEAD )
  ( cd "$W/ci" && git update-ref refs/remotes/origin/release-line "$_ci_base_sha" )
  ( cd "$W/ci" && git checkout -q -b feat )
  ur_manifest "$W/ci" claude-code '".claude/hooks/"'   # drops CODEOWNERS
  ur_commit "$W/ci" "drop CODEOWNERS from the union (CI ladder)"
  _out=$(ur_run_ci "$W/ci" release-line)
  _ur_grade "$_out"
  if [ "$_g_state" = DIRTY ] && printf '%s\n' "$_g_declass" | grep -qxF 'DECLASS CODEOWNERS'; then
    echo "PASS: CI ladder (GITHUB_BASE_REF=release-line) resolves the base via refs/remotes/origin/release-line and DECLASSes"
  else echo "FAIL: CI ladder — got state=$_g_state out=[$_out]"; sfail=1; fi
  # …and the CI ladder is TRIED FIRST when GITHUB_BASE_REF is set, proven by planting a LOCAL 'main'
  # branch that resolves to a DIFFERENT base — one that would report CLEAN (main == HEAD, no diff)
  # where the true CI base reports DECLASS. If the check fell through to the local ladder despite
  # GITHUB_BASE_REF being set, this leg would see CLEAN instead of DECLASS.
  ( cd "$W/ci" && git branch main )   # 'main' at the CURRENT HEAD (feat) — merge-base(HEAD,main) == HEAD, no diff
  _out2=$(ur_run_ci "$W/ci" release-line)
  _ur_grade "$_out2"
  if [ "$_g_state" = DIRTY ] && printf '%s\n' "$_g_declass" | grep -qxF 'DECLASS CODEOWNERS'; then
    echo "PASS: CI ladder wins over a coincidentally-present local 'main' when GITHUB_BASE_REF is set"
  else echo "FAIL: CI ladder was not tried first — a local 'main' at HEAD would report CLEAN; got state=$_g_state out=[$_out2]"; sfail=1; fi

  # ── THE CI LADDER, UNRESOLVABLE: GITHUB_BASE_REF set but no matching refs/remotes/origin/<ref> —
  # must NA naming the CI-specific reason, never silently fall through to the local ladder (a silent
  # fallback would compare against the WRONG base without saying so).
  ur_init "$W/cina"
  ur_manifest "$W/cina" claude-code '".claude/hooks/"'
  ur_commit "$W/cina" base
  _out=$(ur_run_ci "$W/cina" no-such-remote-branch)
  case "$_out" in
    *"NA"*"GITHUB_BASE_REF"*|*"NA"*"refs/remotes/origin/no-such-remote-branch"*)
      echo "PASS: CI ladder unresolvable (no fetched base ref) -> NA naming the CI base" ;;
    *) echo "FAIL: CI ladder unresolvable did not NA correctly: [$_out]"; sfail=1 ;;
  esac
  if [ "$(printf '%s\n' "$_out" | tail -1)" = ALIVE ]; then echo "PASS: CI-unresolvable NA still ends ALIVE"
  else echo "FAIL: CI-unresolvable NA did not end ALIVE: [$_out]"; sfail=1; fi

  # ── (i) THE MUTANT — anchored sed on the base-union derivation call site, `_cen_mut` discipline
  # (cmp -s proves it landed, sh -n proves it parses). Forces the base derivation to behave as if it
  # always found nothing (rc 3, as if BASE-EMPTY), run against fixture (a)'s REMOVAL. A mutant that
  # merely renders BASE-EMPTY is distinguishable by the positive `^DECLASS ` grader and still killed
  # — never "output was non-empty" (design §3 M3).
  #
  # ⚠️ PREMISE ASSERTION (CI-round fix): the leg below is MEANINGLESS unless fixture (a)'s REAL,
  # UNMUTATED run ACTUALLY produces `DECLASS CODEOWNERS` right now — measured directly, under the
  # env-leak class this round's fix closes: with `GITHUB_BASE_REF` leaked in, fixture (a)'s own
  # earlier assertion had already FAILed (state=CLEAN, `NA no resolvable CI base…`), and this mutant
  # leg still PRINTED "PASS … its DECLASS line disappeared" — a vacuous kill, since there was never
  # a DECLASS line to make disappear. `ur_run` alone (hermetic since the fix above) is not sufficient
  # proof by itself; the premise must be asserted AT THIS POINT IN THE RUN, not inferred from leg
  # (a)'s earlier PASS, because a later fixture mutation (or a leak this harness has not yet been
  # taught to scrub) could silently invalidate it between here and there. FAIL, never skip.
  _areal=$(ur_run "$W/a")
  _ur_grade "$_areal"
  if [ "$_g_state" != DIRTY ] || ! printf '%s\n' "$_g_declass" | grep -qxF 'DECLASS CODEOWNERS'; then
    echo "FAIL: (i) premise — fixture (a)'s REAL run does not produce DECLASS CODEOWNERS right now (state=$_g_state, out=[$_areal]) — the mutant leg below would prove NOTHING (this is the exact vacuous-kill shape an unscrubbed ambient env produces)"; sfail=1
  else
    echo "PASS: (i) premise — fixture (a)'s real, unmutated run produces DECLASS CODEOWNERS, so the mutant's disappearance below is a genuine kill, not a vacuous one"
    _mroot="$W/mutant-root"; mkdir -p "$_mroot"
    _mut_src="$_mroot/union-ratchet.sh"
    sed 's%^  BASE_LIST=\$(kit_union_derive "\$_ur_tmp" strict) && _ur_base_rc=0 || _ur_base_rc=\$\?%  BASE_LIST=""; _ur_base_rc=3%' \
      "$_self" > "$_mut_src"
    if cmp -s "$_self" "$_mut_src"; then
      echo "FAIL: (i) the mutant was NOT BUILT — the anchor did not match, so the leg it kills is unproven"; sfail=1
    elif ! sh -n "$_mut_src" 2>/dev/null; then
      echo "FAIL: (i) the mutant does not parse — it would report nothing rather than killing anything"; sfail=1
    else
      cp "$_mut_src" "$W/a/conformance/union-ratchet.sh"
      _mout=$(ur_run "$W/a")
      cp "$_self" "$W/a/conformance/union-ratchet.sh"   # restore for any later reuse
      _ur_grade "$_mout"
      # `[ "$_g_state" = CLEAN ]` ALONE — strictly stronger than an `|| [ -z "$(grep ^DECLASS)" ]`
      # disjunct, which was a SECOND grader copy that could launder a NORUN mutant (no ALIVE sentinel
      # at all, e.g. a syntax error the anchor's own sh -n check somehow missed) into a false kill: a
      # NORUN's raw output also contains no `DECLASS ` line, so the disjunct would read it as killed
      # even though _ur_grade correctly says NORUN. One grader, positively matched, per design §3 M3.
      # Combined with the premise above: CLEAN here is only a kill BECAUSE the premise just proved
      # DIRTY was the mutant-free baseline — the same discipline `assert_collapses()` gives the
      # rename leg in promotion-readiness-wired.sh (a premise proven, not assumed).
      if [ "$_g_state" = CLEAN ]; then
        echo "PASS: (i) the mutant kills fixture (a) — its DECLASS line disappeared (state=$_g_state), and the premise above proves it was really there to disappear"
      else
        echo "FAIL: (i) the mutant did NOT kill fixture (a) — state=$_g_state, out=[$_mout]"; sfail=1
      fi
    fi
  fi

  if [ "$sfail" = 0 ]; then
    echo "OK: union-ratchet selftest (unacknowledged/acknowledged/wholesale/pre-emptive/malformed/byte-exactness/BASE-EMPTY/NA/both-sides-rc/liveness/both base ladders — plus the base-union derivation mutant)"
    exit 0
  fi
  echo "FAIL: union-ratchet selftest"
  exit 1
}

case "${1:-}" in
  --selftest) selftest ;;
  "") run_union_ratchet ;;
  *) echo "usage: union-ratchet.sh [--selftest]" >&2; exit 2 ;;
esac
