#!/bin/sh
# start.sh — the ONE-COMMAND loop entry: classify (act 1), claim (act 3), print the Entry Declaration
# trailer block + the ceremony-budget line (acts 4-5). A THIN SEQUENCER over two tools that already
# exist and are already governed — `conformance/promotion-readiness.sh --class` and
# `scripts/board.sh claim` — so it invents NO new policy, NO write path, and NO env dial of its
# own (SPARKWRIGHT-START-VERB, design 2026-09-16 D1/D2).
#
# TBG-BOARD-VERBS S-L5: the claim step is REROUTED through `board.sh claim` (never `board-claim.sh
# claim` directly) — the git-ref-lock-first, backend-dispatching neutral verb, which itself calls
# `board-claim.sh claim` unchanged for an md board, and composes `claim-ref` + a tracker write for a
# declared tracker backend. On md the observable behaviour is BYTE-IDENTICAL (board.sh delegates
# wholesale); on a tracker backend `start` gains real coverage it never had.
#
#   sh scripts/start.sh <ROW-ID> [--branch <name>] [--changed <listing>]
#   sh scripts/start.sh --selftest
#
# What it changes:
#   NOTHING of its own. The only writes are board.sh's (which, for md, are board-claim.sh's own
#   unchanged) — the `refs/claims/<ROW>` ref on the remote and the board-row edit / tracker
#   transition — and start.sh CALLs board.sh (never `exec`s, so acts 4-5 can still print) and
#   prints nothing until the claim has returned 0.
# Guardrails: (the C8 disclosure)
#   * writes nothing itself; every write is board.sh's/board-claim.sh's, behind their own guard/grammars;
#   * inherits board-claim's BOARD_CLAIM_REMOTE / BOARD_CLAIM_BOARD reach UNCHANGED;
#   * sets no env dial of its own, and NEVER exports KIT_CLAIM_FRONT_DOOR (that front-door sentinel
#     belongs to board-claim's own pushes — exporting it here would be the interpreter-wrapper
#     residual the guard arm names);
#   * the class it prints is PROVISIONAL. loop-state.sh RE-DERIVES the authoritative class at
#     promotion from its own scrubbed classifier spawn over merge-base..HEAD (D2, verified), and
#     nothing downstream trusts a declared class — so a printed class is a convenience, never a
#     source of truth. A stale `--changed` degrades to "the printed class was provisional", never
#     "the gate was misled".
#
# Exit: board-claim's rc, propagated UNCHANGED — 0 (claimed) · 2 (usage / bad row / not Ready) ·
#   3 (already claimed). No trailer block is printed on ANY non-zero path. start's own precondition
#   failures (bad option, unreadable --changed listing) are rc 2. POSIX sh; dash-clean. Run the
#   classifier from the kit root — this resolves it by $0's directory, never $PWD.
set -eu

here=$(dirname "$0")

# THE CLASSIFIER IS A PLAIN SCRIPT VARIABLE, NOT AN ENV ROUTE (the loop-state.sh:168-171 precedent).
# selftest() re-points it at an in-process stub so the unrecognised-token arm can be fixtured; nothing
# OUTSIDE this file can reach it, so `start` gains no env dial by having a testable seam. Resolved by
# $0's directory (a sibling-of-parent), so a call from any $PWD reaches the real classifier.
ST_CLASSIFIER="$here/../conformance/promotion-readiness.sh"

st_usage() {
  echo "usage: sparkwright start <ROW-ID> [--branch <name>] [--changed <listing>] [--lease-token <sha>]" >&2
  echo "       sparkwright start --selftest" >&2
  echo "       (a project with no remote yet claims locally; after the first push run: sh scripts/board.sh publish)" >&2
}

# st_besteffort <cmd...> — run a step that MUST NOT change the exit code. THE B2 EXIT-TRAP LESSON:
# under `kit-guard install-shims` a shimmed `rm -rf` is guard-BLOCKED ("recursive rm is irreversible
# - human-gated"), and in dash a command that FAILS inside an EXIT trap OVERRIDES the script's own
# `exit 0`. Every destructive cleanup step goes through here so a blocked step can never report a
# successful selftest as failed.
st_besteffort() { "$@" 2>/dev/null || true; }

# st_cleanup — the EXIT-trap body. A no-op unless selftest() set $st_base (the same guard board-claim
# uses to keep its trap inert for the verbs). Best-effort by construction (see st_besteffort).
st_cleanup() {
  { [ -n "${st_base:-}" ] && st_besteffort rm -rf "$st_base"; } || true
  { [ -n "${st_stub:-}" ] && st_besteffort rm -rf "$st_stub"; } || true
  return 0
}
trap 'st_cleanup' EXIT INT TERM

# st_classify <ABSOLUTE-listing> -> echoes ordinary|sensitive|control-plane, or EMPTY for unknown.
# Mirrors loop-state.sh derive_class's EXACT shape (C3): the child's environment is SCRUBBED of
# KIT_ADAPTERS_DIR / KIT_UNION_LIB (an ambient value there would move a governing path out of the
# control-plane set), `--class` ONLY (it prints one token, never paths), stderr discarded, `tail -1`.
# Any token that is not one of the three -> unknown (empty). start NEVER echoes the listing's
# contents, and the caller has already absolutized + validated the path (C4).
st_classify() {
  _c=$(env -u KIT_ADAPTERS_DIR -u KIT_UNION_LIB sh "$ST_CLASSIFIER" --changed "$1" --class 2>/dev/null | tail -1) || _c=""
  case "$_c" in
    ordinary|sensitive|control-plane) printf '%s\n' "$_c" ;;
    *)                                printf '' ;;
  esac
}

# st_board_path — the board the md claim edits: the same six-line rule as board-claim.sh bc_board_path (SWAS-905), which
# cannot be sourced (it runs on load). <toplevel>/BACKLOG.md, or $(pwd)/BACKLOG.md outside a repository; a relative
# BOARD_CLAIM_BOARD resolves against the toplevel and an absolute one is used as given. A selftest cell compares the two.
st_board_path() {
  _sbtop=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  case "${BOARD_CLAIM_BOARD:-}" in
    '')  printf '%s/BACKLOG.md\n' "$_sbtop" ;;
    /*)  printf '%s\n' "$BOARD_CLAIM_BOARD" ;;
    *)   printf '%s/%s\n' "$_sbtop" "$BOARD_CLAIM_BOARD" ;;
  esac
}

# st_size_pick <row-id> <size-column> — reads the Ready section's rows (header first) on stdin. Prints the row's Size
# cell, and only when it is exactly one of XS S M L XL and exactly one Ready row carries the id; else prints nothing.
# The raw cell is never echoed. The id is compared as a string, never turned into a pattern.
st_size_pick() {
  _spn=0; _sphits=0; _spsize=""
  while IFS= read -r _sprow; do
    _spn=$((_spn + 1))
    [ "$_spn" -gt 1 ] || continue
    is_sep_row "$_sprow" && continue
    [ "$(backtick_id "$(gfm_cell "$_sprow" 1)")" = "$1" ] || continue
    _sphits=$((_sphits + 1))
    _spsize=$(gfm_cell "$_sprow" "$2")
  done
  [ "$_sphits" -eq 1 ] || return 0
  case "$_spsize" in
    XS|S|M|L|XL) printf '%s' "$_spsize" ;;
  esac
  return 0
}

# st_size <row-id> — the row's Size cell on the md board, or nothing when it cannot be read. ALWAYS RUN IN A SUBSHELL,
# `_size=$( st_size "$_row" ) || _size=""`: the board library sets unprefixed globals (_d, _c, _line, _val) that would
# clobber this script's own, and `exit 0` leaves only the subshell. Any failure reads as unknown (empty): no library, no
# board, a tracker backend (the kit reads BACKLOG.md only), no Size column, no row or two rows. Read-only; no network.
st_size() {
  _sslib="$here/../conformance/backlog-lib.sh"
  [ -r "$_sslib" ] || exit 0
  _ssroot=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  _ssboard=$(st_board_path)
  [ -r "$_ssboard" ] || exit 0
  # shellcheck source=/dev/null
  . "$_sslib"
  # shellcheck disable=SC2034  # read by the sourced seam_backend (backlog-lib.sh)
  SEAM_ROOT=$_ssroot
  _ssbe=$(seam_backend 2>/dev/null) || exit 0
  case "$_ssbe" in
    ''|md) ;;
    *) exit 0 ;;
  esac
  _ssrows=$(section_rows "$_ssboard" "Ready")
  [ -n "$_ssrows" ] || exit 0
  _ssix=$(col_index "$(printf '%s\n' "$_ssrows" | head -1)" Size)
  [ -n "$_ssix" ] || exit 0
  printf '%s\n' "$_ssrows" | st_size_pick "$1" "$_ssix"
}

# THE BUDGET TABLE IS THE REVIEW SKILL'S, READ AT RUN TIME (SWAS-947). A plain script variable, not an env route (the
# ST_CLASSIFIER precedent): resolved from $0's directory, re-pointed only by selftest() in-process.
ST_BUDGET_SKILL="$here/../skills/review/SKILL.md"

# st_table_cell <skill-file> <class> <band> — the third cell of the one table row for that class and size band, between
# the skill's ceremony-budget markers. rc 1 and no output on ANY malformed shape: not exactly one begin before exactly
# one end, a wrong header or separator, a row that is not three cells, an empty third cell, any byte outside printable
# ASCII (a control byte, or a UTF-8 C1 control or bidi mark), or no single matching row: exactly one `any` row for the
# class wins; else exactly one band row; two `any` rows, or two band rows and no `any` row, is malformed. Pure read; the
# cell is printed as it stands.
st_table_cell() {
  [ -r "$1" ] || return 1
  LC_ALL=C awk -v cls="$2" -v band="$3" '
    BEGIN { nb = 0; ne = 0; inb = 0; ln = 0; anyn = 0; bandn = 0; bad = 0; anycell = ""; bandcell = "" }
    /^<!-- ceremony-budget:begin/ { nb++; if (nb > 1 || ne > 0) bad = 1; inb = 1; next }
    /^<!-- ceremony-budget:end/   { ne++; if (nb != 1 || ne > 1) bad = 1; inb = 0; next }
    inb != 1 { next }
    $0 ~ /^[ ]*$/ { next }
    $0 ~ /[^ -~]/ { bad = 1; next }
    { ln++ }
    ln == 1 { if ($0 != "| Class | Size | Ceremony budget |") bad = 1; next }
    ln == 2 { if ($0 != "|---|---|---|") bad = 1; next }
    {
      n = split($0, f, "|")
      if (n != 5 || f[1] != "" || f[5] != "") { bad = 1; next }
      for (i = 2; i <= 4; i++) gsub(/^ +| +$/, "", f[i])
      if (f[4] == "") { bad = 1; next }
      if (f[2] == cls && f[3] == "any") { anyn++; anycell = f[4] }
      else if (f[2] == cls && f[3] == band) { bandn++; bandcell = f[4] }
    }
    END {
      if (bad || nb != 1 || ne != 1 || ln < 3) exit 1
      if (anyn == 1) { print anycell; exit 0 }
      if (anyn == 0 && bandn == 1) { print bandcell; exit 0 }
      exit 1
    }
  ' "$1"
}

# st_budget <class> [<size>] — act 5, one line: the review skill's table row for the class and the size band, led by
# the class and the size read (XS S M L XL, else `unknown (read as M)`). XS and S take the XS/S row; every other size
# input takes M+. A class that is not one of the three is "not derived" and takes the control-plane row. Table
# missing or malformed: a fixed strictest line, a note on stderr, never a made-up budget; always rc 0.
st_budget() {
  _bcls=$1; _bsz=${2:-}
  case "$_bsz" in
    XS|S|M|L|XL) _bsize=$_bsz ;;
    *)           _bsize='unknown (read as M)' ;;
  esac
  case "$_bsz" in
    XS|S) _bband='XS/S' ;;
    *)    _bband='M+' ;;   # MUT-BAND
  esac
  case "$_bcls" in
    ordinary|sensitive|control-plane)
      _brow=$_bcls
      _blab="$_bcls, size $_bsize — " ;;
    *)
      _brow=control-plane
      _blab="class not derived — assume control-plane until the gate re-derives (run the derive command above); size $_bsize — " ;;
  esac
  if _bcell=$(st_table_cell "$ST_BUDGET_SKILL" "$_brow" "$_bband"); then
    printf '%s%s%s\n' 'Ceremony budget (act 5): ' "$_blab" "$_bcell"   # MUT-OUT
    return 0
  fi
  _bsk=$ST_BUDGET_SKILL
  case "$_bsk" in *[[:cntrl:]]*) _bsk='<unprintable path>' ;; esac
  echo "start: no ceremony-budget table in $_bsk" >&2
  echo "Ceremony budget (act 5): the budget table in skills/review/SKILL.md could not be read — assume the strictest budget (control-plane) and read the review skill."   # MUT-FALLBACK
  return 0
}

# st_emit <row> <class> [<size>] — acts 2, 4 and 5 on stdout, printed ONLY after a claim returned 0.
#   * class = ordinary|sensitive|control-plane -> the TWO-key block (Kit-Row + Kit-Class) carrying
#                                    the REAL derived class: every class owes the same two (SWAS-614).
#   * class = "" (unknown, or --changed omitted) -> the same two keys, with the class rendered as
#                                    the paste-FAILING placeholder `<derived class>` [C5]: the angle
#                                    brackets are outside loop-state's Kit-Class charset, so a
#                                    verbatim paste fails LOUDLY at the charset leg rather than
#                                    smuggling an unverified class through. The derive command
#                                    prints on its own line above it.
st_emit() {
  _r=$1; _cls=$2
  echo "act 2 — read the governing skill for this surface before you code: skills/<name>/SKILL.md"
  echo ""
  echo "The Entry Declaration — paste it as the LAST paragraph of the commit message, and contiguous"
  echo "(a blank line inside it truncates it; git keeps only the paragraph after the blank)."
  echo "Never self-assert the class — loop-state.sh re-derives it at promotion; the class here is provisional."
  echo ""
  case "$_cls" in
    ordinary|sensitive|control-plane)
      printf 'Kit-Row: %s\n' "$_r"
      printf 'Kit-Class: %s\n' "$_cls"
      ;;
    *)
      echo   "# derive the class, then replace the placeholder below (do not self-assert it):"
      echo   "#   sh conformance/promotion-readiness.sh --class --changed <listing>"
      printf 'Kit-Row: %s\n' "$_r"
      echo   "Kit-Class: <derived class>"
      ;;
  esac
  echo ""
  st_budget "$_cls" "${3:-}"
}

# do_start <args...> — parse strictly, classify, claim, then (and only then) print acts 4-5.
do_start() {
  _row=""; _branch=""; _changed=""; _have_branch=0; _have_changed=0; _ltok=""
  # STRICT PARSER, REJECT BY DEFAULT [C2]: exactly one positional (the row); accept ONLY
  # --branch / --changed; ANY other option -> rc 2, so board-claim's --links / --dry-run /
  # --board-already-moved are UNREACHABLE through `start`. A positional beginning with `-` is an
  # option-injection shape and is refused by the `-*` arm (rc 2), the same refusal board-claim gives
  # `-ROW`. start adds NO third copy of the row/branch grammar — board-claim owns and validates it.
  while [ $# -gt 0 ]; do
    case "$1" in
      --branch)  [ $# -ge 2 ] || { echo "start: --branch needs a value" >&2; return 2; }; _branch=$2;  _have_branch=1;  shift 2 ;;
      --changed) [ $# -ge 2 ] || { echo "start: --changed needs a value" >&2; return 2; }; _changed=$2; _have_changed=1; shift 2 ;;
      --lease-token) [ $# -ge 2 ] || { echo "start: --lease-token needs a value" >&2; return 2; }; _ltok=$2; shift 2 ;;   # SWAS-192: forwarded to the claim, which checks it
      -*)        echo "start: unknown option '$(printf '%s' "$1" | tr -d '[:cntrl:]')' (only --branch, --changed and --lease-token are accepted)" >&2; st_usage; return 2 ;;
      *)         [ -z "$_row" ] || { echo "start: one row id, not two" >&2; return 2; }; _row=$1; shift ;;
    esac
  done
  [ -n "$_row" ] || { echo "start: a row id is required" >&2; st_usage; return 2; }

  # SWAS-784: the first line names the tree start works in. It is resolved from $0's directory, never from $PWD, and derived from nothing in argv; it refuses nothing.
  _tree=$(CDPATH='' cd -- "$here/.." && pwd -P) || _tree='<unknown>'
  case "$_tree" in *[[:cntrl:]]*) _tree='<unprintable path>' ;; esac
  # (stderr: stdout is the Kit-* trailer block a caller pastes, and must carry only that)
  printf 'start: tree %s\n' "$_tree" >&2   # MUT-STARTTREE

  # ── act 1: classify. Only when a listing is given; otherwise the class is unknown (the block carries a placeholder class).
  _class=""
  if [ "$_have_changed" = 1 ]; then
    # ABSOLUTIZE [C4]: promotion-readiness.sh `cd`s to the kit root before its `-f "$CHANGED"` test, so
    # a $PWD-relative name would resolve against the WRONG directory. Resolve against $PWD here.
    case "$_changed" in
      /*) _abs=$_changed ;;
      *)  _abs="$(pwd)/$_changed" ;;
    esac
    # Refuse a listing that is not a readable REGULAR file, with a plain message. Strip control bytes
    # from the echoed path (C4) and NEVER echo its contents.
    if [ ! -f "$_abs" ] || [ ! -r "$_abs" ]; then
      echo "start: --changed listing '$(printf '%s' "$_changed" | tr -d '[:cntrl:]')' is not a readable regular file." >&2
      return 2
    fi
    _class=$(st_classify "$_abs")
  fi

  # ── act 3: claim. CALL, never `exec` [C1] — `exec` would end the process before acts 4-5 print.
  # Sibling resolved via $(dirname "$0"), never $PWD [C1] — resolves `board.sh`, the neutral write
  # port (TBG-BOARD-VERBS S-L5); board.sh in turn resolves `board-claim.sh` by ITS OWN `$0`. Omit
  # --branch iff not supplied, so board-claim's own `(detached)` refusal stays in ONE place.
  # board-claim's grammars/guard/hygiene all apply UNCHANGED (board.sh calls it verbatim for md, and
  # composes claim-ref for a tracker backend), and start prints nothing derived from argv (row,
  # branch, listing) until this has returned 0 — so those values have already passed validation.
  # SWAS-947: the row's size is read BEFORE the claim — the claim rebuilds the row in In Progress without its Size cell.
  # In a subshell (see st_size); any failure reads as unknown.
  _size=$( st_size "$_row" ) || _size=""   # MUT-SIZE
  _rc=0
  set -- claim "$_row"
  [ "$_have_branch" != 1 ] || set -- "$@" --branch "$_branch"
  [ -z "$_ltok" ] || set -- "$@" --lease-token "$_ltok"
  sh "$here/board.sh" "$@" || _rc=$?   # MUT-CLAIM

  # ── PROPAGATE rc UNCHANGED [C1]. On non-zero: board-claim's stderr has already reached the caller
  # as-is; propagate its exact rc (never collapse 3 "already claimed" into 2) and print NO trailer.
  if [ "$_rc" -ne 0 ]; then
    return "$_rc"
  fi

  # ── acts 4-5, only now.
  st_emit "$_row" "$_class" "$_size"
  return 0
}

# ── ORACLE MARKER: selftest() and everything below is the non-vacuity oracle region. ─────────────
# The mutation sweep mutates only lines BEFORE this marker; the legs below are the oracle that must
# fail when it does (conformance writing-conventions).
selftest() {
  st_fail_n=0
  # the in-process size cells `cd` into fixture directories, so $here must not depend on the cwd the run began in
  here=$(dirname -- "$ST_SELF")
  ST_BUDGET_SKILL="$here/../skills/review/SKILL.md"
  st_real_skill=$ST_BUDGET_SKILL
  st_base=$(mktemp -d)
  st_stub=$(mktemp -d)
  # HERMETIC BY CONSTRUCTION (conformance/selftest-hermetic.sh face (a)): HOME inside the workdir, no
  # global/system git config, every identity set locally per clone. Real pushes to a REAL bare remote
  # at a github-shaped path (the same fixture shape as board-claim.sh:1388-1416), so the ref
  # assertions read the FIXTURE remote, not a simulation. The classify legs are hermetic to the
  # FIXTURE, not the tree: st_classify spawns promotion-readiness.sh, which reads the kit tree
  # READ-ONLY — stated, not hidden (design D3).
  HOME="$st_base/home"; mkdir -p "$HOME"; export HOME
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null; export GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
  unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL 2>/dev/null || true

  st_remote="$st_base/github.com/fixture-owner/fixture-repo.git"
  mkdir -p "$(dirname -- "$st_remote")"
  git init -q --bare "$st_remote"
  st_mkclone A "Session A" a@example.com
  st_mkclone B "Session B" b@example.com
  st_mkclone C "Session C" c@example.com

  # A listing whose ONLY path classifies `ordinary`, so leg (a) proves act-1 wiring end to end:
  # a real classifier spawn returning `ordinary` -> the reduced two-key block.
  printf 'docs/example.md\n' > "$st_base/listing-ordinary"

  # ---- leg (a): siblings via $(dirname "$0"); a real claim; the ref on the FIXTURE remote; act 1 ---
  # A DECOY board.sh sits in the cwd (TBG-BOARD-VERBS S-L5: start's claim step now resolves board.sh,
  # not board-claim.sh, as its sibling). If `start` resolved its sibling by $PWD it would run the
  # decoy (which prints DECOY-MARKER and never pushes); resolving by $0's directory it runs the REAL
  # board.sh (which itself calls the real board-claim.sh), the claim ref appears on the bare remote,
  # and the marker is ABSENT. Non-vacuous: a cwd-relative resolver flips BOTH the marker check and
  # the ref check.
  printf '#!/bin/sh\necho DECOY-MARKER\nexit 0\n' > "$st_base/A/board.sh"
  chmod +x "$st_base/A/board.sh"
  st_run "$st_base/A" ROW-1 --branch feat/a --changed "$st_base/listing-ordinary"
  st_expect_rc 0 "leg a/claim: A claims a Ready row via start -> rc 0"
  if git ls-remote "$st_remote" refs/claims/ROW-1 2>/dev/null | grep -q refs/claims/ROW-1; then
    st_pass "leg a/ref: refs/claims/ROW-1 EXISTS on the FIXTURE bare remote (ls-remote — a real push)"
  else
    st_fail "leg a/ref: refs/claims/ROW-1 absent from the fixture remote after a claimed rc 0"
  fi
  st_hasnt "leg a/siblings: the cwd decoy board.sh was NOT run (sibling resolved by \$0, not \$PWD)" "DECOY-MARKER"
  st_has   "leg a/act1: the block carries the DERIVED ordinary class (act 1 wired the real classifier)" "Kit-Class: ordinary"
  st_hasnt "leg a/act1-twokey: an ordinary class prints the REDUCED two-key block (no Kit-Stage)" "Kit-Stage:"
  st_has   "leg a/trailer: the block leads with Kit-Row" "Kit-Row: ROW-1"
  st_has   "leg a/print: the budget line names the class and the size read from the Ready row (ROW-1 is S)" "ordinary, size S — "

  # ---- leg (b): a SECOND claim of the same row -> rc 3 propagated UNCHANGED, and NO trailer -------
  st_run "$st_base/B" ROW-1 --branch feat/b
  st_expect_rc 3 "leg b/second-claim: B claims a held row via start -> rc 3 (never collapsed to 2)"
  st_has   "leg b/forwarded: board-claim's refusal reaches the caller, naming the holder" "Session A <a@example.com>"
  st_hasnt "leg b/no-trailer: NO trailer block is printed on the rc-3 path" "Kit-Row:"

  # ---- leg (c): a bad row -> board-claim rc 2 propagated, and NO trailer -------------------------
  st_run "$st_base/A" 'row 1'
  st_expect_rc 2 "leg c/bad-row: an invalid row grammar -> rc 2 (board-claim owns the grammar)"
  st_has   "leg c/forwarded: the board-claim grammar refusal reaches the caller" "must match [A-Z0-9][A-Z0-9-]*"
  st_hasnt "leg c/no-trailer: NO trailer block is printed on the rc-2 path" "Kit-Row:"

  # ---- leg (d): reject-by-default parser [C2]; a control-byte row prints NO raw ESC -------------
  st_run "$st_base/A" ROW-2 --bogus
  st_expect_rc 2 "leg d/unknown-opt: an unrecognised option -> rc 2 (reject by default)"
  st_has   "leg d/unknown-opt: start names the refused option" "unknown option '--bogus'"
  st_run "$st_base/A" ROW-2 --links x
  st_expect_rc 2 "leg d/links-unreachable: board-claim's --links is UNREACHABLE through start -> rc 2"
  # NON-VACUOUS: assert the refusal is START'S OWN parser message, not a board-claim refusal that
  # happens to be rc 2 (WIP/branch/etc). If start ACCEPTED --links, this message would be absent even
  # when board-claim then refused ROW-2 for its own reason. The claim is never reached.
  st_has   "leg d/links-unreachable: --links is refused by start's parser (never forwarded to board-claim)" "unknown option '--links'"
  if git ls-remote "$st_remote" refs/claims/ROW-2 2>/dev/null | grep -q refs/claims/ROW-2; then
    st_fail "leg d/no-push: a parser-refused start pushed a ref for ROW-2 anyway"
  else
    st_pass "leg d/no-push: a parser-refused start pushed NOTHING (rejected before the claim)"
  fi
  st_run "$st_base/A" "$(printf 'ROW\033[2K')"
  st_expect_rc 2 "leg d/control-byte: a control-byte row id -> rc 2 (offline refusal)"
  case "$st_out" in
    *"$(printf '\033')"*) st_fail "leg d/no-raw-esc: a raw ESC byte reached the output" ;;
    *)                    st_pass "leg d/no-raw-esc: the control-byte row prints NO raw ESC (stripped at the refusal)" ;;
  esac

  # ---- leg (e): the best-effort EXIT-trap wrapper SWALLOWS a failing step (the B2 lesson) ---------
  if st_besteffort sh -c 'exit 1'; then
    st_pass "leg e/trap: a failing cleanup step is swallowed by st_besteffort (exit 0 preserved)"
  else
    st_fail "leg e/trap: st_besteffort let a failing step change the exit code"
  fi

  # ---- leg (f): an unrecognised classifier token -> unknown -> the FULL four-key block [C3] ------
  # A stub classifier prints a token that is NOT one of the three; st_classify must map it to unknown
  # (empty). A second stub proves a VALID token passes through — the check is not vacuously empty.
  printf '#!/bin/sh\necho banana\n'    > "$st_stub/prcls-bad";  chmod +x "$st_stub/prcls-bad"
  printf '#!/bin/sh\necho sensitive\n' > "$st_stub/prcls-sens"; chmod +x "$st_stub/prcls-sens"
  _saved_classifier=$ST_CLASSIFIER
  ST_CLASSIFIER="$st_stub/prcls-bad"
  if [ -z "$(st_classify "$st_base/listing-ordinary")" ]; then
    st_pass "leg f/unrecognised: a token that is not ordinary|sensitive|control-plane -> unknown (empty)"
  else
    st_fail "leg f/unrecognised: an unrecognised classifier token was NOT mapped to unknown"
  fi
  ST_CLASSIFIER="$st_stub/prcls-sens"
  if [ "$(st_classify "$st_base/listing-ordinary")" = sensitive ]; then
    st_pass "leg f/valid-token: a valid classifier token passes through unchanged"
  else
    st_fail "leg f/valid-token: a valid classifier token did not pass through"
  fi
  ST_CLASSIFIER=$_saved_classifier

  # the block shapes: every class (and the unknown one) is two keys; unknown keeps the paste-failing
  # placeholder and the derive command; ordinary and control-plane carry their REAL class.
  _e_unknown=$(st_emit ROW-X "")
  st_emit_hasnt "$_e_unknown" "leg f/unknown-twokey: unknown class emits two keys (no Kit-Stage, no Kit-Skill)" "Kit-Stage:"
  st_emit_hasnt "$_e_unknown" "leg f/unknown-twokey: unknown class emits two keys (no Kit-Skill)" "Kit-Skill:"
  st_emit_has "$_e_unknown" "leg f/placeholder: unknown class emits the paste-FAILING <derived class> placeholder" "Kit-Class: <derived class>"
  st_emit_has "$_e_unknown" "leg f/derive-cmd: the derive command is printed above the placeholder" "promotion-readiness.sh --class --changed"
  _e_ord=$(st_emit ROW-Y ordinary)
  st_emit_has   "$_e_ord" "leg f/ordinary-class: ordinary emits its real class" "Kit-Class: ordinary"
  st_emit_hasnt "$_e_ord" "leg f/ordinary-twokey: ordinary is a two-key block (no Kit-Stage)" "Kit-Stage:"
  _e_cp=$(st_emit ROW-Z control-plane)
  st_emit_has "$_e_cp" "leg f/cp-class: control-plane emits its real class" "Kit-Class: control-plane"
  st_emit_hasnt "$_e_cp" "leg f/cp-twokey: control-plane is a two-key block (no Kit-Stage)" "Kit-Stage:"
  st_emit_hasnt "$_e_cp" "leg f/cp-twokey: control-plane is a two-key block (no Kit-Skill)" "Kit-Skill:"

  # ---- leg (g): the tree line (SWAS-784). start resolves its tree from $0, so its first line names the tree that holds this script, whatever the cwd; it refuses nothing
  # (a held row still returns rc 3). A mutant copy that drops the line must lose it; the unmutated copy beside it proves the cell is live.
  _g_want="start: tree $(CDPATH='' cd -- "$(dirname -- "$ST_SELF")/.." && pwd -P)"
  st_run "$st_base/B" ROW-1 --branch feat/g
  st_expect_rc 3 "leg g/no-refusal: the tree line changes no exit code (a held row is still rc 3)"
  if [ "$(printf '%s\n' "$st_out" | sed -n 1p)" = "$_g_want" ]; then
    st_pass "leg g/tree: the first line names the tree that holds the script, not the cwd"
  else st_fail "leg g/tree: the first line is not '$_g_want'; out=[$st_out]"; fi
  _g_tm="$st_stub/tree-mut"; mkdir -p "$_g_tm/scripts"
  cp "$ST_SELF" "$_g_tm/scripts/start-orig.sh"; sed '/MUT-STARTTREE$/d' "$ST_SELF" > "$_g_tm/scripts/start-mut.sh"
  if cmp -s "$ST_SELF" "$_g_tm/scripts/start-mut.sh"; then st_fail "leg g/mutant: tree-line-dropped did not apply (the sed matched nothing)"
  else
    _g_tw="start: tree $(CDPATH='' cd -- "$_g_tm" && pwd -P)"
    _g_o1=$( cd "$st_base/B" && sh "$_g_tm/scripts/start-orig.sh" ROW-1 2>&1 ) || true
    _g_o2=$( cd "$st_base/B" && sh "$_g_tm/scripts/start-mut.sh" ROW-1 2>&1 ) || true
    case "$_g_o1" in "$_g_tw"*) : ;; *) st_fail "leg g/mutant: the unmutated copy does not print its tree line (the cell is vacuous); out=[$_g_o1]" ;; esac
    # the tree line is on STDERR: stdout alone never carries it (the trailer block is what a caller pastes), stderr alone does; a mutant that sends it to stdout must lose this
    _g_so=$( cd "$st_base/B" && sh "$_g_tm/scripts/start-orig.sh" ROW-1 2>/dev/null ) || true
    _g_se=$( cd "$st_base/B" && sh "$_g_tm/scripts/start-orig.sh" ROW-1 2>&1 >/dev/null ) || true
    case "$_g_so" in *"start: tree"*) st_fail "leg g/stderr: the tree line reached STDOUT; out=[$_g_so]" ;; *) st_pass "leg g/stderr: the tree line is not on stdout" ;; esac
    case "$_g_se" in *"start: tree"*) st_pass "leg g/stderr: the tree line is on stderr" ;; *) st_fail "leg g/stderr: the tree line is not on stderr (the cell is vacuous); err=[$_g_se]" ;; esac
    sed '/MUT-STARTTREE$/s/ >&2//' "$ST_SELF" > "$_g_tm/scripts/start-out.sh"
    if cmp -s "$ST_SELF" "$_g_tm/scripts/start-out.sh"; then st_fail "leg g/mutant: tree-line-to-stdout did not apply (the sed matched nothing)"
    else
      _g_o3=$( cd "$st_base/B" && sh "$_g_tm/scripts/start-out.sh" ROW-1 2>/dev/null ) || true
      case "$_g_o3" in *"start: tree"*) st_pass "leg g/mutant: tree-line-to-stdout is killed (the mutant puts the line on stdout, so the stderr cell reds)" ;; *) st_fail "leg g/mutant: tree-line-to-stdout survived; out=[$_g_o3]" ;; esac
    fi
    case "$_g_o2" in
      *"start: tree"*) st_fail "leg g/mutant: tree-line-dropped survived; out=[$_g_o2]" ;;
      *board.sh*)      st_pass "leg g/mutant: tree-line-dropped is killed (the mutant ran past the line and printed none)" ;;
      *)               st_fail "leg g/mutant: the mutant never ran past the tree line (vacuous); out=[$_g_o2]" ;;
    esac
  fi

  # ---- leg ST-L (SWAS-783): in a repository with NO remote, start claims locally and prints the trailer ----
  # The first card of a new project is claimed before its remote exists. The claim is a local ref (never a
  # refs/claims/* ref), the Kit-* block prints as it does with a remote, and the usage names this route.
  st_mklocal N "Session N" n@example.com
  st_run "$st_base/N" ROW-1 --branch feat/n --changed "$st_base/listing-ordinary"
  st_expect_rc 0 "leg ST-L/claim: start in a repository with no remote -> rc 0"
  st_has   "leg ST-L/trailer: the block leads with Kit-Row" "Kit-Row: ROW-1"
  st_has   "leg ST-L/class: the block carries the derived class" "Kit-Class: ordinary"
  st_has   "leg ST-L/sentence: the claim says it is recorded in this repository" "recorded in this repository"
  st_hasnt "leg ST-L/not-unreachable: it is not the unreachable sentence" "cannot reach"
  if git -C "$st_base/N" rev-parse --verify -q refs/local-claims/ROW-1 >/dev/null; then
    st_pass "leg ST-L/ref: the local claim ref exists"
  else
    st_fail "leg ST-L/ref: no local claim ref after a claimed rc 0"
  fi
  st_run "$st_base/N"
  st_expect_rc 2 "leg ST-L/usage: start with no row -> rc 2"
  st_has   "leg ST-L/help: the usage names the no-remote route" "no remote yet claims locally"

  # ---- leg a/size (SWAS-947): the size is read from the Ready row, on the board the claim edits ----
  # Read directly (in-process, in a subshell) so these cells grade the READ itself; the claim-path cells that grade what
  # is PRINTED sit in leg a/print below.
  st_size_is "leg a/size: ROW-1 (Size S) reads S" "$st_base/C" ROW-1 S
  st_size_is "leg a/size: ROW-3 (Size M) reads M" "$st_base/C" ROW-3 M
  st_size_is "leg a/size: a Size cell of ? reads as unknown (empty)" "$st_base/C" ROW-4 ""
  st_size_is "leg a/size: a row that is not in Ready reads as unknown (empty)" "$st_base/C" ROW-DONE ""
  st_size_is "leg a/size: an id with no row reads as unknown (empty)" "$st_base/C" ROW-NONE ""
  mkdir -p "$st_base/NR"
  st_board "$st_base/NR/BACKLOG.md"
  printf '%s\n' '' '## Later' '' '| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links | Success metric / hypothesis |' \
    '|------|------|------|------|------|------|------|------|------|' \
    '| `ROW-MLATER` — an M row outside Ready | because | later | M | low | feature | agent | — | none |' >> "$st_base/NR/BACKLOG.md"
  st_size_is "leg a/size: an M-sized row in a non-Ready section reads as unknown (empty)" "$st_base/NR" ROW-MLATER ""
  mkdir -p "$st_base/T"
  st_board "$st_base/T/BACKLOG.md"
  st_size_is "leg a/size: an undeclared backend reads the board (control for the tracker cell)" "$st_base/T" ROW-1 S
  printf '%s\n' '- **Backlog backend**: jira' > "$st_base/T/CLAUDE.md"
  st_size_is "leg a/size: a tracker-declared project reads as unknown (empty), never the local board" "$st_base/T" ROW-1 ""
  mkdir -p "$st_base/D2"
  st_board "$st_base/D2/BACKLOG.md"
  sed '/^| `ROW-1`/p' "$st_base/D2/BACKLOG.md" > "$st_base/D2/dup.md"
  cp "$st_base/D2/dup.md" "$st_base/D2/BACKLOG.md"
  st_size_is "leg a/size: two Ready rows with one id read as unknown (empty)" "$st_base/D2" ROW-1 ""

  # ---- leg a/board-twin (SWAS-947): the path start resolves IS the path the claim edits and prints (`board: <path>`) ----
  # One local repository per spelling of BOARD_CLAIM_BOARD, so no claim shares a session ceiling with another.
  st_mklocal BT1 "Session BT1" bt1@example.com
  st_run "$st_base/BT1" ROW-1 --branch feat/bt1 --changed "$st_base/listing-ordinary"
  st_expect_rc 0 "leg a/board-twin: a claim with BOARD_CLAIM_BOARD unset -> rc 0"
  st_twin_line "leg a/board-twin: unset" "$st_base/BT1"
  st_mklocal BT2 "Session BT2" bt2@example.com
  mkdir -p "$st_base/BT2/sub"
  st_board "$st_base/BT2/alt.md"
  BOARD_CLAIM_BOARD=alt.md; export BOARD_CLAIM_BOARD
  st_run "$st_base/BT2/sub" ROW-1 --branch feat/bt2 --changed "$st_base/listing-ordinary"
  st_expect_rc 0 "leg a/board-twin: a relative BOARD_CLAIM_BOARD, run from a subdirectory -> rc 0"
  st_twin_line "leg a/board-twin: relative" "$st_base/BT2/sub"
  st_mklocal BT3 "Session BT3" bt3@example.com
  BOARD_CLAIM_BOARD="$st_base/BT3/BACKLOG.md"; export BOARD_CLAIM_BOARD
  st_run "$st_base/BT3" ROW-1 --branch feat/bt3 --changed "$st_base/listing-ordinary"
  st_expect_rc 0 "leg a/board-twin: an absolute BOARD_CLAIM_BOARD -> rc 0"
  st_twin_line "leg a/board-twin: absolute" "$st_base/BT3"
  unset BOARD_CLAIM_BOARD

  # ---- leg a/lib-absent (SWAS-947): a tree without the board library still claims and prints the trailer ----
  st_nolib=1
  st_mktree nolib
  st_nolib=0
  st_tree_claim "$st_tree" NL1
  st_expect_rc 0 "leg a/lib-absent: a tree with no conformance/backlog-lib.sh claims -> rc 0"
  st_has "leg a/lib-absent: the trailer block still prints" "Kit-Row: ROW-3"
  st_has "leg a/lib-absent: the size reads as unknown" "ordinary, size unknown (read as M) — "

  # ---- leg a/print (continued): a row sized M, claimed from a FRESH clone C (so no session holds two rows, and the ceiling is untouched) ----
  # Last among the remote claims: A holds ROW-1, and a second foreign claim would put legs b and g at the WIP ceiling.
  st_run "$st_base/C" ROW-3 --branch feat/c --changed "$st_base/listing-ordinary"
  st_expect_rc 0 "leg a/print: C claims ROW-3 (Size M) -> rc 0"
  st_has "leg a/print: the budget line carries size M and the M+ row" "ordinary, size M — design doc with the twelve-lens table"

  # ---- leg h (SWAS-947): the printed budget IS the review skill's table row for the class and size ----
  # The expected cell comes from a reader that is NOT start's parser (grep -F + sed over the table row), so a parser
  # that agrees with itself cannot pass. 4 classes x 7 size inputs = 28 exact comparisons.
  _h_blk=$(sed -n '/^<!-- ceremony-budget:begin/,/^<!-- ceremony-budget:end/p' "$st_real_skill")
  _h_n=$(printf '%s\n' "$_h_blk" | grep -c '^|' || true)
  if [ "$_h_n" -eq 6 ]; then st_pass "leg h/table: the live table is a header, a separator and four rows"
  else st_fail "leg h/table: the live table has $_h_n table lines, wanted 6"; fi
  for _h_pair in "ordinary | XS/S" "ordinary | M+" "sensitive | any" "control-plane | any"; do
    _h_c=$(printf '%s\n' "$_h_blk" | grep -cF "| $_h_pair |" || true)
    if [ "$_h_c" -eq 1 ]; then st_pass "leg h/table: exactly one row for $_h_pair"
    else st_fail "leg h/table: $_h_c rows for $_h_pair, wanted 1"; fi
  done
  for _h_cls in ordinary sensitive control-plane ""; do
    for _h_sz in XS S M L XL unknown '?'; do
      _h_want=$(st_ref_line "$st_real_skill" "$_h_cls" "$_h_sz")
      _h_got=$(st_budget "$_h_cls" "$_h_sz" 2>/dev/null) || _h_got="<rc>"
      if [ "$_h_got" = "$_h_want" ]; then st_pass "leg h/cells: class [${_h_cls:-not derived}] size [$_h_sz] prints the table row"
      else st_fail "leg h/cells: class [${_h_cls:-not derived}] size [$_h_sz]; got [$_h_got]; wanted [$_h_want]"; fi
    done
  done

  # h/rb6 — the anti-regression anchor: what each row MEANS, so a table edit that reverts to "self-review" fails here
  for _h_row in "ordinary XS/S" "ordinary M+" "sensitive any" "control-plane any"; do
    _h_cell=$(st_ref_cell "$st_real_skill" ${_h_row})
    st_emit_has   "$_h_cell" "leg h/rb6: [$_h_row] names a reviewer" "reviewer"
    st_emit_has   "$_h_cell" "leg h/rb6: [$_h_row] names a security pass" "security"
    st_emit_hasnt "$_h_cell" "leg h/rb6: [$_h_row] never reads self-review" "self-review"
    st_emit_hasnt "$_h_cell" "leg h/rb6: [$_h_row] never reads lightweight" "lightweight"
    if [ "$_h_row" = "ordinary XS/S" ]; then
      st_emit_has "$_h_cell" "leg h/rb6: [$_h_row] owes one reviewer" "one reviewer"
      st_emit_has "$_h_cell" "leg h/rb6: [$_h_row] owes security once on the built diff" "security once"
    else
      st_emit_has "$_h_cell" "leg h/rb6: [$_h_row] owes a plan file" "plan file"
      st_emit_has "$_h_cell" "leg h/rb6: [$_h_row] owes a review record" "review record"
      st_emit_has "$_h_cell" "leg h/rb6: [$_h_row] owes a separate security seat" "separate security seat"
    fi
  done

  # h/fallback — one cell per malformed shape: the fixed strictest line on stdout, a note on stderr, rc 0
  printf '%s\n' "$_h_blk" > "$st_stub/blk.good"
  printf '# a skill with no table\n' > "$st_stub/blk.none"
  sed '$d' "$st_stub/blk.good" > "$st_stub/blk.noend"
  cat "$st_stub/blk.good" "$st_stub/blk.good" > "$st_stub/blk.twob"
  sed '/^| ordinary | M+ |/p' "$st_stub/blk.good" > "$st_stub/blk.dup"
  sed 's#^\(| sensitive | any |\) .*#\1  |#' "$st_stub/blk.good" > "$st_stub/blk.empty3"
  sed 's#^\(| sensitive | any | design doc\)#\1 a|b#' "$st_stub/blk.good" > "$st_stub/blk.pipe"
  sed "s#^\(| sensitive | any | design doc\)#\1$(printf '\001')#" "$st_stub/blk.good" > "$st_stub/blk.ctrl"
  st_fb_cell "leg h/fallback: no table block" "$st_stub/blk.none"
  st_fb_cell "leg h/fallback: a begin marker with no end marker" "$st_stub/blk.noend"
  st_fb_cell "leg h/fallback: two begin markers" "$st_stub/blk.twob"
  st_fb_cell "leg h/fallback: a duplicated row" "$st_stub/blk.dup"
  st_fb_cell "leg h/fallback: an empty third cell" "$st_stub/blk.empty3"
  st_fb_cell "leg h/fallback: a stray pipe in a cell" "$st_stub/blk.pipe"
  st_fb_cell "leg h/fallback: a control byte in a cell" "$st_stub/blk.ctrl"
  st_fb_cell "leg h/fallback: a skill file that does not exist" "$st_stub/blk.absent"
  sed "s#^\(| sensitive | any | design doc\)#\1$(printf '\302\233')#" "$st_stub/blk.good" > "$st_stub/blk.c1"
  sed "s#^\(| sensitive | any | design doc\)#\1$(printf '\342\200\256')#" "$st_stub/blk.good" > "$st_stub/blk.bidi"
  st_fb_cell "leg h/fallback: a UTF-8 C1 control (C2 9B) in a cell" "$st_stub/blk.c1"
  st_fb_cell "leg h/fallback: a bidi override (U+202E) in a cell" "$st_stub/blk.bidi"
  _h_top='<!-- ceremony-budget:begin -->'
  _h_end='<!-- ceremony-budget:end -->'
  printf '%s\n' "$_h_top" '| Class | Size | Ceremony budget |' '|---|---|---|' \
    '| ordinary | any | ANY-CELL |' '| ordinary | M+ | BAND-CELL |' "$_h_end" > "$st_stub/blk.anyband"
  printf '%s\n' "$_h_top" '| Class | Size | Ceremony budget |' '|---|---|---|' \
    '| ordinary | any | ANY-ONE |' '| ordinary | any | ANY-TWO |' "$_h_end" > "$st_stub/blk.twoany"
  ST_BUDGET_SKILL="$st_stub/blk.anyband"
  _h_ab=$(st_budget ordinary M 2>/dev/null) || _h_ab="<rc>"
  ST_BUDGET_SKILL=$st_real_skill
  case "$_h_ab" in
    *"size M — ANY-CELL") st_pass "leg h/lookup: a class with an any row and a band row prints the any row's cell" ;;
    *) st_fail "leg h/lookup: any row plus band row; got [$_h_ab]" ;;
  esac
  st_fb_cell "leg h/fallback: two any rows for one class" "$st_stub/blk.twoany"

  # h/mutant-cell (M1) — a table whose ordinary M+ cell is edited: start prints the edit, so it reads the table at run time
  sed 's#^\(| ordinary | M+ | \).*#\1MUTANT-CELL |#' "$st_stub/blk.good" > "$st_stub/blk.m1"
  ST_BUDGET_SKILL="$st_stub/blk.m1"
  _h_m1=$(st_budget ordinary M 2>/dev/null) || _h_m1="<rc>"
  _h_m1xs=$(st_budget ordinary XS 2>/dev/null) || _h_m1xs="<rc>"
  ST_BUDGET_SKILL=$st_real_skill
  case "$_h_m1" in
    *"size M — MUTANT-CELL") st_pass "leg h/mutant-cell: an edited M+ cell is what start prints (the line is read from the table)" ;;
    *) st_fail "leg h/mutant-cell: the edited cell did not reach the line; got [$_h_m1]" ;;
  esac
  case "$_h_m1xs" in
    *MUTANT-CELL*) st_fail "leg h/mutant-cell: the XS/S row printed the edited M+ cell; got [$_h_m1xs]" ;;
    *) st_pass "leg h/mutant-cell: the edit is confined to its own row" ;;
  esac

  # ---- leg h/mutants (SWAS-947): M2-M5 run through a fixture tree's COPY of start, each beside an unmutated twin ----
  # The twins prove the tree claims and prints what the cells grade, so a "killed" is never a tree that cannot run.
  st_mktree twin
  st_tree_claim "$st_tree" TWIN
  st_expect_rc 0 "leg h/twin: the unmutated fixture tree claims ROW-3 -> rc 0"
  st_has   "leg h/twin: it prints the M+ row for the Size M read from the Ready row" "ordinary, size M — design doc with the twelve-lens table"
  st_hasnt "leg h/twin: it never reads self-review" "self-review"
  st_mktree twin-notable "$st_stub/blk.none"
  st_tree_claim "$st_tree" TWINNT
  st_expect_rc 0 "leg h/twin: a fixture tree whose skill has no table still claims -> rc 0 (the fallback never changes the exit code)"
  st_has "leg h/twin: ... and prints the trailer block" "Kit-Row: ROW-3"
  st_has "leg h/twin: ... and the fixed strictest line" "assume the strictest budget (control-plane)"
  st_has "leg h/twin: ... and the table note on stderr" "start: no ceremony-budget table in "
  st_mutant m2 lacks "ordinary, size M — design doc with the twelve-lens table" "$st_real_skill" \
    -e "/# MUT-BAND\$/s#'M+'#'XS/S'#"
  st_mutant m3 lacks "assume the strictest budget (control-plane)" "$st_stub/blk.none" \
    -e '/# MUT-FALLBACK$/s#assume the strictest budget (control-plane)#ordinary, size M#'
  st_mutant m4 has "self-review" "$st_real_skill" \
    -e '/# MUT-OUT$/s#.*#    echo "Ceremony budget (act 5): ordinary - automated gates + self-review; the lightweight GO."#'
  st_mutant m5 lacks "ordinary, size M — " "$st_real_skill" \
    -e '/# MUT-SIZE$/d' \
    -e '/# MUT-CLAIM$/s#|| _rc=\$?#|| _rc=$?; _size=$( st_size "$_row" ) || _size=""#'

  if [ "$st_fail_n" -ne 0 ]; then
    echo "start --selftest: FAIL" >&2
    return 1
  fi
  echo "start --selftest: OK (fixtures under $st_base, removed by the best-effort EXIT trap)"
  return 0
}

# --- selftest-only helpers, BELOW the marker so the mutation harness cannot neuter the oracle ----
st_pass() { echo "selftest PASS: $1"; }
st_fail() { echo "selftest FAIL: $1"; st_fail_n=1; }

# st_mkclone <name> <user.name> <user.email> — a clone of the bare remote with a fixture board that
# carries ROW-1 and ROW-2 in Ready (so a claim has a real Ready row to enter) and a Done row.
st_mkclone() {
  git clone -q "$st_remote" "$st_base/$1" 2>/dev/null
  (
    cd "$st_base/$1"
    git config user.name "$2"
    git config user.email "$3"
    git config commit.gpgsign false
  )
  st_board "$st_base/$1/BACKLOG.md"
}

# st_mklocal <name> <user.name> <user.email> — a repository with NO remote at all: `git init`, one commit
# holding the fixture board (an unborn HEAD is refused by the claim, which needs a branch name).
st_mklocal() {
  mkdir -p "$st_base/$1"
  (
    cd "$st_base/$1"
    git init -q .
    git config user.name "$2"
    git config user.email "$3"
    git config commit.gpgsign false
    st_board "$st_base/$1/BACKLOG.md"
    git add BACKLOG.md
    git commit -q -m 'fixture board'
  ) >/dev/null 2>&1
}

# st_board <path> — the fixture board: ROW-1 and ROW-2 in Ready, and a Done row.
st_board() {
  cat > "$1" <<'BOARD_EOF'
# Fixture — Backlog

## Ready

| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links | Success metric / hypothesis |
|------|--------------|---------------------|------|------|------|-------|-------|-----------------------------|
| `ROW-1` — the claimable row | because | it is claimed | S | low | feature | agent | — | a claim serializes |
| `ROW-2` — a second claimable row | because | it is claimed | S | low | feature | agent | — | a claim serializes |
| `ROW-3` — a medium claimable row | because | it is claimed | M | low | feature | agent | — | a claim serializes |
| `ROW-4` — a row whose size is unreadable | because | it is claimed | ? | low | feature | agent | — | a claim serializes |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|
| `ROW-DONE` — already shipped | 2026-09-03 | fixture. |
BOARD_EOF
}

# st_run <clone-dir> <args...> — run THIS script inside the clone, capturing rc + merged output.
st_run() {
  _sd=$1; shift
  if st_out=$( cd "$_sd" && sh "$ST_SELF" "$@" 2>&1 ); then st_rc=0; else st_rc=$?; fi
}
st_expect_rc() { # <want> <label>
  if [ "$st_rc" -eq "$1" ]; then st_pass "$2"
  else st_fail "$2 (rc=$st_rc, wanted $1); out=[$st_out]"; fi
}
st_has() { # <label> <needle> — graded on the last st_run's output
  case "$st_out" in *"$2"*) st_pass "$1" ;; *) st_fail "$1 (output lacks '$2'); out=[$st_out]" ;; esac
}
st_hasnt() { # <label> <needle>
  case "$st_out" in *"$2"*) st_fail "$1 (output wrongly carries '$2'); out=[$st_out]" ;; *) st_pass "$1" ;; esac
}
st_emit_has() { # <captured> <label> <needle> — graded on a captured st_emit string
  case "$1" in *"$3"*) st_pass "$2" ;; *) st_fail "$2 (emit lacks '$3'); emit=[$1]" ;; esac
}
st_emit_hasnt() { # <captured> <label> <needle>
  case "$1" in *"$3"*) st_fail "$2 (emit wrongly carries '$3'); emit=[$1]" ;; *) st_pass "$2" ;; esac
}

# st_size_is <label> <dir> <row> <want> — st_size, run in <dir>, reads <want> (empty = unknown).
st_size_is() {
  _szg=$( cd "$2" && st_size "$3" ) || _szg="<rc>"
  if [ "$_szg" = "$4" ]; then st_pass "$1"
  else st_fail "$1 (size read [$_szg], wanted [$4])"; fi
}

# st_twin_line <label> <dir> — the last st_run's `board: <path>` line is the path start resolves from <dir>.
st_twin_line() {
  _tw=$( cd "$2" && st_board_path ) || _tw="<unresolved>"
  if printf '%s\n' "$st_out" | grep -qxF "board: $_tw"; then
    st_pass "$1: the claim's board line is the path start resolves"
  else st_fail "$1: no 'board: $_tw' line in the claim output; out=[$st_out]"; fi
}

# st_ref_cell <skill-file> <class> <band> — the table row's third cell, read by grep -F + sed. It is NOT start's parser
# (st_table_cell): the cells grade one reader against the other.
st_ref_cell() {
  grep -F "| $2 | $3 |" "$1" | sed 's#^| [^|]* | [^|]* | \(.*\) |$#\1#'
}

# st_ref_line <skill-file> <class> <size-input> — the line the design says start prints for that class and size input,
# built here from the reference reader: the prefix, the class label, the size, then the row's cell.
st_ref_line() {
  case "$3" in
    XS|S|M|L|XL) _rls=$3 ;;
    *)           _rls='unknown (read as M)' ;;
  esac
  case "$3" in
    XS|S) _rlb='XS/S' ;;
    *)    _rlb='M+' ;;
  esac
  case "$2" in
    ordinary)       _rlcell=$(st_ref_cell "$1" ordinary "$_rlb"); _rll="ordinary, size $_rls — " ;;
    sensitive)      _rlcell=$(st_ref_cell "$1" sensitive any);    _rll="sensitive, size $_rls — " ;;
    control-plane)  _rlcell=$(st_ref_cell "$1" control-plane any); _rll="control-plane, size $_rls — " ;;
    *)              _rlcell=$(st_ref_cell "$1" control-plane any); _rll="class not derived — assume control-plane until the gate re-derives (run the derive command above); size $_rls — " ;;
  esac
  printf '%s%s%s\n' 'Ceremony budget (act 5): ' "$_rll" "$_rlcell"
}

# st_fb_cell <label> <skill-file> — one malformed-table cell: st_budget points at <skill-file> and must print the fixed
# strictest line on stdout, name the table on stderr, and return 0.
st_fb_cell() {
  ST_BUDGET_SKILL=$2
  if _fbo=$(st_budget ordinary M 2>"$st_stub/fb.err"); then _fbrc=0; else _fbrc=$?; fi
  ST_BUDGET_SKILL=$st_real_skill
  _fbwant='Ceremony budget (act 5): the budget table in skills/review/SKILL.md could not be read — assume the strictest budget (control-plane) and read the review skill.'
  _fberr=$(cat "$st_stub/fb.err")
  if [ "$_fbrc" -eq 0 ] && [ "$_fbo" = "$_fbwant" ]; then st_pass "$1: the fixed strictest line, rc 0"
  else st_fail "$1: rc=$_fbrc; stdout [$_fbo]"; fi
  case "$_fberr" in
    *"start: no ceremony-budget table in "*) st_pass "$1: stderr names the missing table" ;;
    *) st_fail "$1: stderr lacks the table note; stderr [$_fberr]" ;;
  esac
}

# st_mutant <name> <has|lacks> <needle> <skill-file> <sed-arg>... — build a fixture tree whose copy of start is run
# through the sed arguments, claim ROW-3 through it, and grade the output as a MUTANT: it is KILLED when its output
# contains <needle> (has: the bad text) or lacks it (lacks: the good text). A mutant whose sed matched nothing, or that
# never ran to the trailer, FAILS as vacuous rather than counting as a kill.
st_mutant() {
  _mname=$1; _mmode=$2; _mneedle=$3; _mskill=$4; shift 4
  if ! st_mktree "mut-$_mname" "$_mskill" "$@"; then
    st_fail "leg h/mutant $_mname: did not apply (the sed matched nothing)"
    return 0
  fi
  st_tree_claim "$st_tree" "MR$_mname"
  case "$st_out" in
    *"Kit-Row: ROW-3"*) : ;;
    *) st_fail "leg h/mutant $_mname: the mutant never ran to the trailer (vacuous); rc=$st_rc out=[$st_out]"; return 0 ;;
  esac
  case "$st_out" in
    *"$_mneedle"*) _mfound=1 ;;
    *)             _mfound=0 ;;
  esac
  if [ "$_mmode" = has ]; then _mkill=$_mfound; else _mkill=$((1 - _mfound)); fi
  if [ "$_mkill" -eq 1 ]; then st_pass "leg h/mutant $_mname: killed (output $_mmode [$_mneedle])"
  else st_fail "leg h/mutant $_mname: SURVIVED (output $_mmode [$_mneedle] was not the kill signal); out=[$st_out]"; fi
}

# st_mktree <name> [<skill-file>] [<sed-arg>...] — a FIXTURE KIT TREE under $st_stub holding the claim chain: a copy of
# this script (run through the sed arguments when given), the real board.sh + board-claim.sh, the board library
# (omitted when st_nolib=1), the review skill (<skill-file>, default this tree's) and a STUB classifier that prints
# `ordinary`. It sets st_tree. rc 1 when sed arguments were given and the copy came out equal to the original, so
# a mutant that matched nothing is never mistaken for a kill. Never run with --selftest, so it cannot recurse.
st_mktree() {
  _mtn=$1; shift
  _mtskill=""
  if [ "$#" -gt 0 ]; then _mtskill=$1; shift; fi
  st_tree="$st_stub/tree-$_mtn"
  _mtroot=$(CDPATH='' cd -- "$(dirname -- "$ST_SELF")/.." && pwd)
  [ -n "$_mtskill" ] || _mtskill="$_mtroot/skills/review/SKILL.md"
  mkdir -p "$st_tree/scripts" "$st_tree/conformance" "$st_tree/skills/review"
  cp "$_mtroot/scripts/board.sh" "$_mtroot/scripts/board-claim.sh" "$st_tree/scripts/"
  if [ "${st_nolib:-0}" != 1 ]; then cp "$_mtroot/conformance/backlog-lib.sh" "$st_tree/conformance/"; fi
  cp "$_mtskill" "$st_tree/skills/review/SKILL.md"
  printf '#!/bin/sh\necho ordinary\n' > "$st_tree/conformance/promotion-readiness.sh"
  if [ "$#" -eq 0 ]; then
    cp "$ST_SELF" "$st_tree/scripts/start.sh"
    return 0
  fi
  sed "$@" "$ST_SELF" > "$st_tree/scripts/start.sh"
  if cmp -s "$ST_SELF" "$st_tree/scripts/start.sh"; then return 1; fi
  return 0
}

# st_tree_claim <tree> <repo-name> — claim ROW-3 (Size M) through <tree>'s copy of start, in a fresh local repository.
# Sets st_out and st_rc. ST_SELF is never used, so a mutant copy is what runs.
st_tree_claim() {
  st_mklocal "$2" "Session $2" "$2@example.com"
  if st_out=$( cd "$st_base/$2" && sh "$1/scripts/start.sh" ROW-3 --branch feat/t --changed "$st_base/listing-ordinary" 2>&1 ); then st_rc=0; else st_rc=$?; fi
}

ST_SELF=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")

case "${1:-}" in
  --selftest) shift; if selftest; then st_rc_main=0; else st_rc_main=$?; fi ;;
  -h|--help)  st_usage; st_rc_main=2 ;;
  "")         st_usage; st_rc_main=2 ;;
  *)          if do_start "$@"; then st_rc_main=0; else st_rc_main=$?; fi ;;
esac
exit "$st_rc_main"
