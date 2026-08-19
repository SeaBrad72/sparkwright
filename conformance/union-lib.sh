#!/bin/sh
# union-lib.sh — THE ADAPTER-UNION AUTHORITY, extracted so the two merge-time gates that consult it
# share ONE derivation and ONE matcher (GUARD-PATH-ENUMERATION-INCOMPLETE S2, design
# docs/architecture/2026-08-17-guard-class-parity-s2-design.md §3 M1).
#
# What it changes at runtime: NOTHING. A sourced library of two primitives, no side effects on
# source, no top-level `set`, no `cd`. Consumers: conformance/agent-boundary.sh (the required
# ratification gate) and conformance/promotion-readiness.sh (the `--class` seam every merge gate —
# loop-state, ceremony-binding, ci.yml, phase-gate — derives through).
#
# ★★★ WHY BOTH LAYERS ARE SHARED, NOT JUST THE PARSER (design vet M-A). The union has TWO halves:
# WHICH ENTRIES EXIST (kit_union_derive) and WHAT AN ENTRY MATCHES (kit_path_in_union — glob-
# implementing, case-folding, trailing-slash directory prefix). Sharing only the parser would re-fork
# the semantics one layer down: `.Cursor/rules/x` would gate at ratification and derive `ordinary` at
# `--class`, which is byte-for-byte the divergence this extraction exists to close. Both are here.
#
# ⚠️ NOT the guard-core control-plane set. This is the ADAPTER-DECLARED half — what each harness's
# own manifest says must be ratified. The guard-core half lives in .claude/hooks/guard-core.sh and is
# consulted separately by both callers; the union of the two is the merge-time control-plane set.
# The GUARD (runtime deny) deliberately does NOT consult this file — see the design's §4.
#
# POSIX sh; dash-clean. No `set -eu` here: a sourced library must not change its caller's shell flags.

# kit_union_derive <adapters-dir> [strict] — print the union of `controlPlanePaths` across
# <adapters-dir>/*/adapter.json, one entry per line, sorted-unique.
#
# THREE STATES, and conflating the last two is the defect this contract exists to prevent:
#   rc 0 — OK.        Manifests exist and every one of them parsed.
#   rc 3 — OK-EMPTY.  NO manifest file exists at all. A LEGITIMATE tree (an adopter who ships no
#                     adapter manifests, or a hand-rolled minimal repo), NOT a failure: the caller
#                     must fall back to the guard-core floor and MUST NOT fail-safe. A tree that
#                     classified every PR control-plane because it declared no adapters would be a
#                     ceremony DoS, and "no adapters" is a state we expect adopters to be in.
#   rc 1 — UNAVAILABLE. Manifests EXIST and the mechanism is broken: jq is unavailable, or at least
#                     one manifest failed to parse. The union is therefore NARROWER THAN DECLARED
#                     and nothing on stdout can say so — which is precisely how a corrupt manifest
#                     silently shrinks a control-plane set. A caller deciding an authorization
#                     question must fail-safe here.
#
# STDOUT IS ALWAYS WHAT WAS ACTUALLY PARSED, in every state — including rc 1. That is deliberate and
# it is what lets `agent-boundary.sh` keep its existing posture byte-for-byte (it ignores the rc and
# consumes the partial union, exactly as its inline copy did) while `promotion-readiness.sh` reads
# the rc and fail-safes. Changing a REQUIRED gate's fail posture is its own ruling, not this
# extraction's to make.
#
# `strict` — the SECOND ARGUMENT, deliberately not an environment variable ("arguments, not env",
# OBLIGATION-TESTMODE-ENV-FLAG): an ambient knob that turns a disclosure off is an unlogged
# off-switch on a diagnosis. When passed, every derivation failure is DISCLOSED ON STDERR with the
# remedy named. The pre-extraction copy wrote `jq … 2>/dev/null` with `// empty`, so a corrupt
# manifest produced silence and a narrower union — the exact defect class.
#
# ⚠️ NEVER PRINT A DIAGNOSIS ON STDOUT. Both callers capture this function's stdout as DATA (one of
# them with `tail -1` two levels up), so a line of prose there is read as a union entry, or as a
# change-class.
kit_union_derive() {
  _kud_dir=${1:-}
  _kud_strict=${2:-}
  _kud_seen=0
  _kud_bad=0

  [ -n "$_kud_dir" ] || return 3
  [ -d "$_kud_dir" ] || return 3

  # PASS 1 — does ANY manifest exist? This decides OK-EMPTY vs UNAVAILABLE and must be answered
  # WITHOUT jq, because "jq is missing" is one of the states it discriminates.
  for _kud_m in "$_kud_dir"/*/adapter.json; do
    [ -f "$_kud_m" ] || continue
    _kud_seen=1
  done
  [ "$_kud_seen" = 1 ] || return 3

  # jq is the parser. Absent, with manifests present, the declared surface is UNREADABLE — not empty.
  if ! command -v jq >/dev/null 2>&1; then
    if [ "$_kud_strict" = strict ]; then
      echo "kit_union_derive: jq is NOT INSTALLED and adapter manifests exist under '$_kud_dir'." >&2
      echo "  The adapter-declared control-plane surface cannot be read, so the union is NARROWER" >&2
      echo "  than what the manifests declare. REMEDY: install jq (the manifests are JSON)." >&2
    fi
    return 1
  fi

  # PASS 2 — parse. Each manifest is read on its own so ONE corrupt file cannot discard the others,
  # and its rc is CAPTURED rather than swallowed. `.controlPlanePaths[]? // empty` tolerates a
  # manifest that legitimately declares none; it does NOT tolerate a file that is not JSON.
  #
  # ⚠️ ACCUMULATED INTO A VARIABLE, NOT PIPED INTO `sort -u`. A `for … done | sort -u` runs the loop
  # in a SUBSHELL, so `_kud_bad` set inside it is discarded and every corrupt manifest reads as
  # rc 0 — the extraction would have re-introduced the silent-narrowing defect it exists to remove.
  # (Caught by this function's own broken-manifest leg on first write.)
  _kud_acc=""
  for _kud_m in "$_kud_dir"/*/adapter.json; do
    [ -f "$_kud_m" ] || continue
    if _kud_one=$(jq -r '.controlPlanePaths[]? // empty' "$_kud_m" 2>/dev/null); then
      [ -z "$_kud_one" ] || _kud_acc="$_kud_acc$_kud_one
"
    else
      _kud_bad=1
      if [ "$_kud_strict" = strict ]; then
        echo "kit_union_derive: adapter manifest '$_kud_m' FAILED TO PARSE." >&2
        echo "  Every control-plane path it declares is missing from the union, so the merge-time" >&2
        echo "  control-plane set is narrower than declared. REMEDY: fix the JSON in that file" >&2
        echo "  (validate with: jq . '$_kud_m'), or remove the manifest deliberately." >&2
      fi
    fi
  done
  [ -z "$_kud_acc" ] || printf '%s' "$_kud_acc" | sort -u

  [ "$_kud_bad" = 0 ] || return 1
  return 0
}

# kit_path_in_union <path> <union-list>: 0 if <path> matches a union entry — exact, a glob, or a
# directory-prefix entry ending in '/'. Union entries never contain spaces, so word-splitting the
# list is safe.
#
# THE MATCHING AUTHORITY. Both merge-time gates call THIS; neither re-implements it.
#
# A2 (case). The adapter-declared surface is the OTHER half of the merge-time control-plane set, and
# it was byte-literal while is_control_plane_path folded — so `.Cursor/rules` stayed ordinary and the
# union half remained evadable by one capital letter. Fold BOTH the subject and each declared entry;
# adapter manifests are author-written, so an entry may itself carry uppercase.
#
# ⚠️ THE ENTRY FOLD IS HOISTED OUT OF THE LOOP, AND THAT IS A MEASURED FIX, NOT A TIDY-UP. Folding
# each entry INSIDE the loop spawned `printf | tr` once per uppercase entry per call — three of this
# repository's fourteen declared entries carry uppercase (`CODEOWNERS`, `AGENTS.md`, `GEMINI.md`), so
# a 1141-path sweep spawned ~3400 processes and the full-tree render went 4s -> 11s the moment
# `--class` started consulting the union. Folding the whole LIST once is byte-identical (`tr` is
# per-character and union entries carry no whitespace) and costs at most one process per call — and
# none at all when the caller hands over an already-folded list, which promotion-readiness.sh does.
kit_path_in_union() {
  _pp=$1; _u=$2
  case "$_pp" in *[A-Z]*) _pp=$(printf '%s' "$_pp" | LC_ALL=C tr 'A-Z' 'a-z') ;; esac
  case "$_u" in *[A-Z]*) _u=$(printf '%s' "$_u" | LC_ALL=C tr 'A-Z' 'a-z') ;; esac
  # `for _e in $_u` needs WORD splitting but must NOT get PATHNAME expansion: a manifest entry such as
  # `conformance/*` would otherwise expand to the existing files, so a NEW file under that directory
  # would not match the union at all. Adapter manifests are author-controlled input to an
  # authorization predicate, so disable globbing for the loop and restore it after.
  # Save the caller's noglob state and restore it, rather than an unconditional `set +f` — the
  # established pattern in guard-core.sh. An unconditional restore silently clears a caller's `set -f`.
  _piu_g=0; case "$-" in *f*) _piu_g=1 ;; esac
  set -f
  for _e in $_u; do
    # (the fold happened once, on the whole list, above — see the note on this function)
    # IMPLEMENT the glob rather than degrading to match-all. An earlier draft treated any entry
    # containing * ? or [ as an unsupported shape and returned MATCH, reasoning that fail-closed beats a
    # silent no-match. Measured, that made ONE glob entry in ANY adapter manifest classify EVERY path
    # control-plane — `README.md`, `package.json`, `totally/unrelated.txt` — turning the required gate
    # into an always-red check with no diagnostic naming the offending entry. Over-classification is the
    # safe direction but a blanket merge block is not a usable one.
    # `case` patterns are NOT subject to pathname expansion, so the glob works directly and `set -f`
    # (kept, for the unquoted word-split above) does not affect it. `docs/*` now matches
    # `docs/CAPABILITIES.md` and NOT `src/App.tsx` — the behaviour the fail-closed branch was standing in
    # for. Unquoted `$_e` on the pattern side is deliberate: that is what makes it a pattern.
    # shellcheck disable=SC2254  # intentional: the union entry IS the pattern
    case "$_pp" in $_e) [ "$_piu_g" = 1 ] || set +f; return 0 ;; esac
    [ "$_pp" = "$_e" ] && { [ "$_piu_g" = 1 ] || set +f; return 0; }
    case "$_e" in */) case "$_pp" in "$_e"*) [ "$_piu_g" = 1 ] || set +f; return 0 ;; esac ;; esac
  done
  [ "$_piu_g" = 1 ] || set +f
  return 1
}
