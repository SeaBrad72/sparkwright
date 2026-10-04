#!/bin/sh
# backlog-lib.sh — shared board-parser primitives for the KW6 backlog gates.
# Extracted VERBATIM from backlog-current.sh (KW6-A2 T1.1) so backlog-current.sh and
# backlog-presence.sh consume ONE definition of "the board" — two parsers would drift, and
# drift between them is invisible to both of their tests. Pure functions only: no dispatch,
# no `exit`, no `set -eu`, no top-level side effects — this file is sourced, never run.
#   . "$(dirname "$0")/backlog-lib.sh"
# What it changes: nothing — a sourced-only library of read-only parser helpers; mutates no state.
# Guardrails: read-only; no network, no writes, no dispatch/exit; sourced by its callers, never
#   executed standalone (so it carries no --selftest and needs no ci.yml wiring).
#
# --- THE SEAM (TBG-SEAM-MD-ARM, `md` arm) -------------------------------------------------------
# `seam_backend` / `seam_row_count` / `seam_row_state` / `seam_row_flag` / `seam_rows_in_state` are
# the frozen five-function read surface (design §4.2): the ONLY functions a gate may call to reach
# "the board", on every backend. This file carries the `md` arm (delegates to the parser primitives
# above, never re-implements them) AND, as of TBG-RECORD-GATES-BIND, the TRACKER ARM of
# `seam_row_count`/`seam_row_state` (§2 scope A/B — the two fields the landed reader, #694, actually
# emits). `seam_row_flag`/`seam_rows_in_state` on a tracker are UNVERIFIED-by-construction (rc2)
# until `TBG-READER-FLAGS-LIST` lands their live arm end-to-end against the reader's real emission.
# CONFIGURATION: the seam is configured ONCE per call site with the project root, via the single
# sourced variable `SEAM_ROOT` — mirroring `loop-state.sh`'s own `LS_BOARDROOT`. The caller sets
# `SEAM_ROOT` to the project directory (never a board PATH — the functions take `<id>`/`<state>`
# only, per §4.2's signatures) before calling any seam function. A caller that changes root between
# calls (e.g. a selftest fixture) re-sets `SEAM_ROOT` each time, exactly as `LS_BOARDROOT` is
# re-pointed at fixture trees today.
# rc contract (§4.2, unchanged): 0 bound (stdout is the answer) · 1 refused (malformed id/state,
# unmapped, no board) · 2 UNVERIFIED (md arm: `SEAM_ROOT` unset/empty only — the fail-closed guard;
# tracker arm: record unavailable/stale/unreadable) · 3 NOT ENFORCED (a declared non-md backend —
# `seam_backend` never returns this itself; a CALLER
# maps its returned token through `not_enforced_notice`, exactly as today). Never a silent empty:
# rc 0 with empty stdout is legal ONLY for `seam_rows_in_state`.

# resolve_backend <project-dir> -> echoes a normalized backend token
# (md|github|jira|ado|linear|gitlab), or empty when undeclared. Reads only <dir>/CLAUDE.md.
resolve_backend() {
  _d="$1"; _c="$_d/CLAUDE.md"
  [ -f "$_c" ] || return 0                                   # no CLAUDE.md -> undeclared
  # Field-leading line, tolerating list/bold markers and a `(§6)`-style annotation
  # before the colon (mirrors surface-lib.sh's is_agentic field resolution).
  # rc captured off the grep itself (a temp var, not the pipe's tail `head`) so an EXEC failure
  # (rc>=2: unreadable file, bad regex) is never confused with a legitimate no-match (rc1) — both
  # used to collapse silently to empty stdout / "undeclared" (SEAM-BACKEND-DECL-GREP-FOLD).
  # Guarded (if/then/else), never a bare assignment: callers run under `set -e`, and grep's own
  # non-zero rc would otherwise trip -e on the assignment statement itself, aborting before the rc
  # is ever read (killing the exec-fault path this fix exists to add).
  if _rb_full=$(grep -Ei '^[-*[:space:]]*\**backlog backend\**[^:]*:' "$_c" 2>/dev/null); then _rb_grc=0; else _rb_grc=$?; fi
  # FIXED TOKEN (security fix-round 2, L-2): never interpolate the path/value into the token — it
  # is repo text on its way to a gate's prose. `unrecognized:evalerror` alone is still diagnosable
  # (a consumer prints "evalerror" as the reason name) AND fail-closed via the unrecognized:* arm.
  [ "$_rb_grc" -ge 2 ] && { printf 'unrecognized:evalerror\n'; return 0; }  # exec fault -> fail-closed, never undeclared
  _line=$(printf '%s\n' "$_rb_full" | head -1)
  [ -n "$_line" ] || return 0                               # field absent (rc1, no match) -> undeclared
  _val=${_line#*:}                                          # value after the first colon
  # Cut the annotation: everything after the first em-dash, or the first space-then-paren,
  # is annotation (`— [link]`, ` (mapping: …)`, ` (repo-native)`), never the value. The
  # space-paren form is deliberate — it strips ` (mapping…)` while preserving a markdown
  # link's `](url)`. This also stops a GitHub URL in the `— [link]` annotation from
  # resolving a Jira project to `github`. Then trim surrounding whitespace.
  _val=$(printf '%s' "$_val" | sed 's/—.*$//; s/ (.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')
  [ -n "$_val" ] || return 0                                # empty value after the colon -> undeclared
  # Unfilled placeholder = a bracketed *choice-list*: brackets AND a `/` separator inside
  # them. Mirrors surface-lib.sh's is_agentic, which skips only on the choice-list shape, never on
  # any bracket — so a bare `[link]` annotation (already cut above) never trips this.
  if printf '%s' "$_val" | grep -Eq '\[[^]]*/[^]]*\]'; then
    return 0                                                # unfilled choice-list -> undeclared
  fi
  # Lowercase, then resolve to one canonical token (the incept.sh vocabulary).
  _lv=$(printf '%s' "$_val" | tr '[:upper:]' '[:lower:]')
  case "$_lv" in
    *'azure devops'*) printf 'ado\n'; return 0 ;;           # human alias -> ado
  esac
  case "$_lv" in
    md|markdown)  printf 'md\n'; return 0 ;;                # bare token (what T8 stamps)
    *backlog.md*) printf 'md\n'; return 0 ;;                # BACKLOG.md / a link to it -> md
  esac
  # Same rc-fold as :40 — capture the grep's own rc, not head's, so an exec fault (rc>=2, e.g. an
  # allocation failure) is never confused with the legitimate no-match (rc1) that falls through to
  # the "unrecognized" verdict below.
  if _rb_full2=$(printf '%s' "$_lv" | grep -Eo 'github|jira|ado|linear|gitlab'); then _rb_grc2=0; else _rb_grc2=$?; fi
  # FIXED TOKEN (security fix-round 2, L-2): see the header note at the other emit site above.
  [ "$_rb_grc2" -ge 2 ] && { printf 'unrecognized:evalerror\n'; return 0; }  # exec fault -> fail-closed via the unrecognized:* arm
  _res=$(printf '%s\n' "$_rb_full2" | head -1)
  if [ -n "$_res" ]; then
    printf '%s\n' "$_res"
    return 0
  fi
  # Non-empty, non-choice-list value that matches NO known token = a MISTYPED/unknown backend
  # (`markdow`, `TBD`, …). It must NOT fail open to undeclared -> N/A: that silently loses the
  # gate for an md-board owner who fat-fingers the field — the exact dark-gate class this slice
  # closed. Signal it distinctly (an absent field and an unfilled choice-list already returned
  # empty above and stay N/A). Echo the trimmed value, case preserved, for the diagnostic.
  printf 'unrecognized:%s\n' "$_val"
  return 0
}

# is_pure_template <BACKLOG.md path> -> rc0 iff the board is still the pristine template:
# it contains the example row `| [title] |` AND has no other real data row.
is_pure_template() {
  _f="$1"
  [ -f "$_f" ] || return 1
  grep -Fq '| [title] |' "$_f" || return 1                 # example row gone -> not pristine
  # A "real data row" = a table body row with content that is NOT a separator, NOT a
  # header (the row directly above a separator), NOT the `[title]` example, and NOT an
  # empty `| | | |` row. awk exits 1 the moment one is found (-> not pure).
  if awk '
    /^[ \t]*```/ { L[NR]=$0; FEN[NR]=1; infence=!infence; next }  # ``` fence toggle: the fence
    { L[NR]=$0; if (infence) FEN[NR]=1 }                          #   line + its body are not live
    END {
      for (i=1;i<=NR;i++) {
        if (FEN[i]) continue                               # inside a ``` fence -> an example, not live
        s=L[i]
        if (s !~ /^[ \t]*\|/) continue                     # not a table row
        if (s ~ /^[ \t]*\|[ \t|:*-]*$/) continue           # separator / empty-cells / spacer row
        nx=(i<NR)?L[i+1]:""
        # A row is a HEADER only when its NEXT line is a GENUINE separator — one that contains a
        # dash. A blank spacer row `| | | |` is pipes+spaces only and must NOT count: treating
        # "next line is empty-cells" as "next line is a separator" is the defect that let a real,
        # unlinked row sitting directly above the shipped spacer be misread as a header and skipped
        # (the same wrong idea is_sep_row was already fixed to reject). Mirror its dash rule.
        if (nx ~ /^[ \t]*\|[ \t|:-]*-[ \t|:-]*\|[ \t]*$/) continue  # header (row above a real separator)
        if (s ~ /\|[ \t]*\[title\][ \t]*\|/) continue      # the example placeholder row
        exit 1                                             # a real data row -> not pure
      }
      exit 0
    }
  ' "$_f"; then
    return 0
  else
    return 1
  fi
}

# --- T2.1 table-parser primitives -------------------------------------------------------
# section_rows <file> <section> : emit every `|`-leading row inside `## <section>` (header,
# separator, and body rows), up to the next `## ` heading. Blockquotes/prose are excluded.
section_rows() {
  awk -v sec="$2" '
    /^[[:space:]]*```/ {infence = !infence; next}   # a fenced example board is documentation, not
    infence {next}                                  #   a live table — skip everything inside ``` … ```
    $0 ~ "^## " sec "[[:space:]]*$" {inseg=1; next}
    inseg && /^## / {inseg=0}
    inseg && /^[[:space:]]*\|/ {print}
  ' "$1"
}
# section_present <file> <section> : rc 0 iff `## <section>` (exact heading, optional trailing
# whitespace) is present in <file>; rc 1 otherwise (including an unreadable file). Owns the ONE
# heading regex section_rows itself matches on, so a caller that only needs a yes/no presence
# check (TBG-ROADMAP-CURRENT-SEAM / M-1) is not tempted to hand-roll a second copy of it — the
# duplication measured in roadmap-current.sh before this helper existed. NOT fence-aware: a `##
# <section>` heading that happens to sit inside a ``` code fence still returns rc 0 here, unlike
# section_rows (which yields 0 rows for it) — this matches the behaviour of the grep it replaced
# in roadmap-current.sh, so it is a like-for-like swap, not a widening. `$2` is interpolated
# directly into an ERE; only code-controlled callers (never raw external/user input) may pass it.
section_present() {
  [ -r "$1" ] || return 1
  grep -Eq "^## $2\$" "$1" 2>/dev/null || grep -Eq "^## $2[[:space:]]*\$" "$1" 2>/dev/null
}
# cells_in_section <file> <section> <1-based-column-index> : column <index> of EVERY row inside
# `## <section>`, one per output line — the batched form of calling `cell` once per row returned by
# `section_rows` (TBG-ROADMAP-CURRENT-SEAM / L-2: the per-row loop cost one awk spawn per Done row —
# measured ~40x slower on a 287-row board). ONE awk pass does the section-bounding (identical rule to
# section_rows) AND the GFM-exact pipe split (identical rule to cell) together, so its output is
# byte-identical, row for row, to `section_rows "$1" "$2" | while read -r row; do cell "$row" "$3"; done`.
cells_in_section() {
  awk -v sec="$2" -v want="$3" -F'|' '
    /^[[:space:]]*```/ {infence = !infence; next}
    infence {next}
    $0 ~ "^## " sec "[[:space:]]*$" {inseg=1; next}
    inseg && /^## / {inseg=0}
    inseg && /^[[:space:]]*\|/ {
      n=0; s=""
      for (j=2; j<=NF; j++) {
        s = (s=="") ? $j : s "|" $j
        t=s; run=0
        while ((L=length(t)) > 0 && substr(t,L,1)=="\\") { run++; t=substr(t,1,L-1) }
        if (run % 2 == 1) continue         # odd backslash run -> the pipe was escaped, keep joining
        if (j==NF && s ~ /^[ \t]*$/) break # the trailing artifact after a closing "|" is not a column
        n++
        if (n==want) { v=s; gsub(/^[ \t]+|[ \t]+$/,"",v); print v; break }
        s=""
      }
    }
  ' "$1"
}
# cell <row> <1-based-index> : the trimmed content of the Nth GFM column (BOARD-PIPE-ESCAPE T1 —
# the canonical, GFM-exact parser: a `|` is a column delimiter iff preceded by an EVEN-length run
# of `\` (0, 2, 4, …); an odd-length run means the final `\` escapes that pipe, so the split keeps
# joining across it. Same leading-empty-field convention as before ($(j+1)/j=2 start: the field
# before the row's leading `|` is not a column). RAW convention (L-8): `\|` is PRESERVED in the
# returned content, never unescaped — a second transformation is a separate surface.
cell() {
  printf '%s' "$1" | awk -F'|' -v i="$2" '
    {
      n=0; s=""
      for (j=2; j<=NF; j++) {
        s = (s=="") ? $j : s "|" $j
        t=s; run=0
        while ((L=length(t)) > 0 && substr(t,L,1)=="\\") { run++; t=substr(t,1,L-1) }
        if (run % 2 == 1) continue                        # odd backslash run -> the pipe was escaped, keep joining
        if (j==NF && s ~ /^[ \t]*$/) break                 # the trailing artifact after a closing "|" is not a column
        n++
        if (n==i) { v=s; gsub(/^[ \t]+|[ \t]+$/,"",v); print v; exit }
        s=""
      }
    }'
}
# col_index <header-row> <column-name> : the 1-based index of the column named <column-name>,
# resolved BY NAME (never by a hardcoded position) under the same GFM backslash-run rule as
# cell(). Empty if the column is absent.
col_index() {
  printf '%s' "$1" | awk -F'|' -v want="$2" '
    {
      n=0; s=""
      for (j=2; j<=NF; j++) {
        s = (s=="") ? $j : s "|" $j
        t=s; run=0
        while ((L=length(t)) > 0 && substr(t,L,1)=="\\") { run++; t=substr(t,1,L-1) }
        if (run % 2 == 1) continue
        if (j==NF && s ~ /^[ \t]*$/) break
        n++
        v=s; gsub(/^[ \t]+|[ \t]+$/,"",v)
        if (v==want) { print n; exit }
        s=""
      }
    }'
}
# gfm_nf <row> : the GFM column count of <row> under the same backslash-run rule as cell() — an
# escaped pipe (`\|`, odd run) does not delimit; an even run (incl. `\\|`) does. Exported for
# callers that used to count columns with a raw awk NF or the `sed 's/\\|//g' | awk NF` idiom
# (both wrong on `\\|` — see `_arity_nf`, converted in T2).
gfm_nf() {
  printf '%s' "$1" | awk -F'|' '
    {
      n=0; s=""
      for (j=2; j<=NF; j++) {
        s = (s=="") ? $j : s "|" $j
        t=s; run=0
        while ((L=length(t)) > 0 && substr(t,L,1)=="\\") { run++; t=substr(t,1,L-1) }
        if (run % 2 == 1) continue
        if (j==NF && s ~ /^[ \t]*$/) break
        n++
        s=""
      }
      print n
    }'
}
# is_sep_row <row> : rc0 iff the row is a markdown separator. CRITICAL: it must contain at
# least one dash, so a blank spacer row `| | | |` (pipes+spaces only) is NOT matched — that
# row belongs to the Item-empty skip, not the separator branch (the known vacuity trap).
is_sep_row() { printf '%s' "$1" | grep -Eq '^[[:space:]]*\|[[:space:]|:]*-[[:space:]|:-]*\|[[:space:]]*$'; }

# --- SLICE-CLOSES-IN-ONE-PR primitives (shared by BOTH board gates) ----------------------
# ⚠️ MUTATION COVERAGE OF EVERYTHING BELOW — STATED, NOT ASSUMED (review m3). This file is listed in
# conformance/aggregate-exclusions.txt — it is sourced, never run, and has no selftest surface — so
# `non-vacuity.sh` NEVER mutates a line of it. Two consequences a reader must not have to derive:
#   (1) moving retro_cell here took it OUT of backlog-current.sh's mutation region — the sweep used
#       to be able to neuter it there and can no longer reach it anywhere;
#   (2) cell, col_index, gfm_nf, gfm_cell and retro_cell (BOARD-PIPE-ESCAPE T1 — the one GFM-exact
#       parser and its alias/fold) plus closed_pre_epoch are proven only BEHAVIOURALLY, via callers'
#       own selftests: the parser harness at backlog-current.sh's `selftest()` (parser/escaped-pipe,
#       parser/escaped-backslash-pipe, parser/trailing-backslash, parser/gfm_cell-alias,
#       parser/retro_cell-shared) plus the pre-existing gate selftests (dispo/escaped-item-pipe,
#       dispo/escaped-pipe, dispo/pre-epoch, dispo/bad-date, t1c/done-pre-epoch, t1c/done-bad-date,
#       t1c/done-escaped-pipe), each watched red against a hand-applied mutant (M-EVEN: every
#       backslash run escapes; M-ODD: no run escapes; M-TRIM; M-GFM, M-DA1) — never by the
#       automated sweep.
# The cure for (1)/(2) is the sweep learning to mutate sourced libraries through their callers; that
# is its own slice, and until it exists this paragraph is the honest record.
# HITL6_DISPO_EPOCH — the ONE constant both gates read for "a Done row closed under the
# one-PR rule". backlog-current.sh grades such a row's Disposition line; backlog-presence.sh
# scopes its Done arm to the same population. It lives HERE, in the sourced library, so the two
# gates cannot drift over WHICH rows the rule reaches — the same reason every board-parser
# primitive was extracted here (KW6-A2 T1.1).
# It is still DECLARED EXTERNALLY AND NEVER DERIVED FROM THE BOARD — the HITL-4 rule that an
# oracle built out of the thing under test goes blind. This library is not the board; it is a
# constant a human edits in a reviewed diff, exactly as HITL6_RETRO_EPOCH is.
# WHY THIS DATE: 2026-09-03 is the day the rule was built, not ship-date+1, so this slice's OWN
# Done rows are graded by the leg they introduce (HITL-6's precedent). Measured before build:
# none of the 228 existing Done rows is Closed on/after it — zero backfill, zero manufactured
# attestation.
# shellcheck disable=SC2034  # consumed by the two gates that SOURCE this library
# (backlog-current.sh leg 3, backlog-presence.sh's Done arm), never inside the library itself —
# which is the entire point of putting it here.
HITL6_DISPO_EPOCH="2026-09-03"

# closed_pre_epoch <closed-cell> <epoch YYYY-MM-DD> : rc0 iff the cell is a parseable ISO date
# STRICTLY BEFORE the epoch (i.e. the row is out of the rule's scope). FAIL-CLOSED: anything this
# cannot parse — an empty cell, `someday`, a column-shifted row — returns rc1, i.e. IN scope. A
# date test that skipped what it could not read would make the epoch a bypass.
closed_pre_epoch() {
  case "$1" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) return 1 ;;
  esac
  # PREPUSH-CORE-DEFAULT: hyphen-strip by parameter expansion, not two `tr` forks per call (this runs
  # ~3x per Done row, ~1000 calls on the live board). $1 is already proven dddd-dd-dd above, so the
  # result is byte-identical to `tr -d '-'`; $2 (an epoch constant) takes the same route when it is
  # that shape and falls back to the original `tr` otherwise.
  _cpe_c="${1%%-*}"; _cpe_t="${1#*-}"; _cpe_c="$_cpe_c${_cpe_t%%-*}${_cpe_t#*-}"
  case "$2" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
      _cpe_e="${2%%-*}"; _cpe_t="${2#*-}"; _cpe_e="$_cpe_e${_cpe_t%%-*}${_cpe_t#*-}" ;;
    *) _cpe_e=$(printf '%s' "$2" | tr -d '-') ;;
  esac
  [ "$_cpe_c" -lt "$_cpe_e" ]
}

# gfm_cell <row> <1-based-index> : BOARD-PIPE-ESCAPE T1 folded this to a thin alias of cell() —
# cell() is now itself GFM-exact (backslash-run counting, not "ends in one backslash"), so the
# two parsers this comment used to distinguish are one. Kept as a name, not a second
# implementation, because backlog-current.sh and backlog-presence.sh already call it at several
# sites (Item/Closed reads) and repointing every call site is not this slice's shape.
gfm_cell() { cell "$1" "$2"; }

# --- NOT ENFORCED — THE NON-MD VERDICT (NON-MD-BACKEND-NEVER-SILENT) --------------------
# not_enforced_notice <backend> <project-dir> <waivers-valid.sh path>
#   prints ONE verdict line on stdout · rc 3 = NOT ENFORCED (red) · rc 0 = waived, with the
#   notice still printed.
# WHY IT LIVES HERE and not four times in four gates: `backlog-presence.sh`, `backlog-current.sh`,
# `loop-state.sh`, and `board-drift.sh` must say the SAME sentence about the SAME condition. The
# design asked for "text identical in all callers"; four copies of a sentence is exactly the drift
# this library exists to prevent, so there is one copy and four callers.
# WHAT rc 3 IS: a PARTITION, not a bypass — distinct from 1 (a WAIT on the author's own
# precondition) and 2 (a broken gate). The ONLY consumer that maps it to "allow" is the pre-push
# speed bump, whose ceiling is already "not a boundary"; the required CI context reds on it.
# WHY IT IS RED AT ALL: with a hosted tracker declared, all three gates used to print an `N/A` and
# return 0 — three green lights and no governance (ruling D-240903-1 §3, "governance may never
# switch off silently"). Nobody can CLEAR this red by editing code; the ladder is the waiver
# register below, or `TRACKER-BACKED-GOVERNANCE`. That visible cost is the ruling's intent.
# THE WAIVER READ IS FAIL-CLOSED: an absent or unreadable waivers-valid.sh, an absent register, a
# placeholder row and an expired row all read as NO WAIVER. A green here requires a human-signed,
# dated row and nothing less.
#   <cure-sentence> (4th, OPTIONAL): overrides the default "TRACKER-BACKED-GOVERNANCE, or ratify a
#   board-governance waiver" clause in the final (non-waived) message. Both `backlog-presence.sh`
#   and `loop-state.sh` supply the real cure (`tracker_delegated_cure()`, above) once the trusted
#   job exists (LOOP-STATE-TRACKER-STEP-ASIDE amendment A2 — one cure, both gates, so an agent
#   reading either gate's refusal gets the same instruction); `backlog-current.sh` still omits it
#   and keeps today's sentence byte-identical (not this task's file to touch or message to change).
not_enforced_notice() {
  # The backend token is repo text on its way to a CI log. It is one of five fixed tokens on this
  # path today, but strip C0/DEL anyway — the same reason loop-state's ls_safe exists.
  _ne_b=$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177')
  _ne_d="$2"; _ne_s="$3"; _ne_w=""
  _ne_cure="${4:-TRACKER-BACKED-GOVERNANCE, or ratify a board-governance waiver}"
  if [ -f "$_ne_s" ]; then
    _ne_w=$(sh "$_ne_s" --active board-governance "$_ne_d/WAIVER-REGISTER.md" 2>/dev/null) || _ne_w=""
  else
    echo "NOTE: $_ne_s is not present — the board-governance waiver could not be read; treating it as ABSENT (fail-closed)." >&2
  fi
  if [ -n "$_ne_w" ]; then
    # TAB-SEPARATED, `<owner><TAB><expires>` (reviewer r4). This used to split on a middle dot,
    # which can itself occur inside an owner cell — an ambiguous separator parsing the one input
    # that could contain it. A TAB cannot survive `trim` inside a markdown cell, so it cannot be
    # smuggled in. waivers-valid.sh also strips C0/DEL from both fields before emitting them
    # (security S-L1), so nothing here re-sanitises what arrives already clean.
    _ne_own=${_ne_w%%	*}
    _ne_exp=${_ne_w#*	}
    echo "NOT ENFORCED: backend '$_ne_b' — waived until $_ne_exp by $_ne_own (WAIVER-REGISTER.md); board-bound governance is not verified on this tree"
    return 0
  fi
  echo "NOT ENFORCED: backend '$_ne_b' — board-bound governance is not verified on this tree (the kit reads BACKLOG.md only; see docs/work-tracking/adapters.md §Which gates bind). Cure: $_ne_cure (templates/WAIVER-REGISTER.md)."
  return 3
}

# --- THE STEP-ASIDE PREDICATE (TRACKER-TRUSTED-JOB-REQUIRED-CONTEXT T1, design §2b + amendment A1
# §9 RD-1 arm (a) LIVE / RD-2 / RD-3) -----------------------------------------------------------
# bp_tracker_delegated <base-dir> <live-contexts-file> : rc 0 iff board governance is delegated to
# the required context `tracker-board-gates`, verified from the BASE alone — NEVER from the head
# (`--dir`, the caller's attacker-writable board dir on `pull_request`). ALL THREE must hold, every
# one read from <base-dir>:
#   (i)   <base-dir>'s OWN backend declaration (resolve_backend, the same resolver `seam_backend`
#         already uses — never re-derived, and never read from a `--dir` other than <base-dir>) is
#         a hosted tracker (non-empty, non-`md`, a RECOGNIZED token — `unrecognized:*` fails closed);
#   (ii)  <base-dir>/.kit/tracker.conf EXISTS and `sh <base-dir>/scripts/tracker-conf.sh` (that base
#         checkout's OWN copy of the validator, never this repo's) ACCEPTS it (rc 0);
#   (iii) <live-contexts-file> is a non-empty REGULAR file carrying a line EXACTLY `tracker-board-
#         gates` (RD-1 arm (a), MEASURED live: the caller fetches this from the base branch's LIVE
#         `required_status_checks.contexts` via the forge API — this predicate does not care how the
#         file was produced, only that the line is there; `REQUIRED-CHECKS.md` is a declaration, not
#         this file, and is NOT read here — RD-1's whole point is "declared" is not "required").
# ANY missing/empty/malformed input -> rc 1 (fail-closed, RD-3): no `--base-dir`, no `--live-
# contexts`, a base declaring `md`/undeclared/unrecognized, an absent/unreadable conf, a conf the
# base's own tracker-conf.sh refuses, an absent/empty live-contexts file, or a live-contexts file
# that lists something else (a substring, a commented mention, a different context name) but not
# the exact line. NO ENV READS — every input arrives BY ARGUMENT (S-L5's rule, carried here).
# CALLER DISCIPLINE (RD-2, no self-delegation): the ONLY caller (backlog-presence.sh::check_pr) MUST
# call this AFTER `seam_tracker_record_set` has already been checked false — the trusted job (which
# sets SEAM_RECORD) is never itself excused by its own required-context wiring. This function has no
# way to enforce that from inside itself (it takes no SEAM_RECORD-shaped input at all); the ordering
# is the caller's contract, proven by a hoist mutant in the caller's selftest, not by this function.
bp_tracker_delegated() {
  _btd_base="${1:-}"; _btd_live="${2:-}"
  [ -n "$_btd_base" ] && [ -d "$_btd_base" ] || return 1
  _btd_tok=$(resolve_backend "$_btd_base")
  case "$_btd_tok" in
    ''|md|unrecognized:*) return 1 ;;
  esac
  _btd_conf="$_btd_base/.kit/tracker.conf"
  [ -f "$_btd_conf" ] || return 1
  [ -f "$_btd_base/scripts/tracker-conf.sh" ] || return 1
  sh "$_btd_base/scripts/tracker-conf.sh" "$_btd_conf" >/dev/null 2>&1 || return 1
  [ -n "$_btd_live" ] && [ -f "$_btd_live" ] && [ -s "$_btd_live" ] || return 1
  grep -Fxq 'tracker-board-gates' "$_btd_live" 2>/dev/null || return 1
  return 0
}

# --- THE SHARED DELEGATION SENTENCE (LOOP-STATE-TRACKER-STEP-ASIDE T1, design §2 "one helper") ---
# tracker_delegated_notice : prints the exact N/A sentence `backlog-presence.sh` has printed since
# TRACKER-TRUSTED-JOB-REQUIRED-CONTEXT T1 (`:543`), byte-identical, so both gates say the same
# thing about the same condition — the same reason `not_enforced_notice` lives here and not in
# every caller. Lifted verbatim; `backlog-presence.sh` now calls this instead of its own literal,
# so its output stays byte-identical by construction.
tracker_delegated_notice() {
  printf '%s\n' "N/A: board governance is delegated to the required context 'tracker-board-gates' (live on the base branch)"
}

# tracker_delegated_cure : prints the exact cure sentence `backlog-presence.sh` has passed as
# `not_enforced_notice`'s 4th argument since TRACKER-TRUSTED-JOB-REQUIRED-CONTEXT T1 (`:552`),
# byte-identical — amendment A2: `loop-state.sh` passes this on every hosted-tracker refusal too,
# so an agent reading either gate's red gets the SAME cure, not the generic waiver-only clause.
tracker_delegated_cure() {
  printf '%s\n' "bind the trusted job as a required context: add tracker-board-gates to REQUIRED-CHECKS.md, then run sh scripts/branch-protection-apply.sh --apply — or move the board to BACKLOG.md, or ratify a board-governance waiver"
}

# --- THE ROW-ID SEAM (BOARD-ROW-IDENTIFIER) ---------------------------------------------
# backtick_id and row_exists MOVED HERE from backlog-current.sh:434-460, byte-unchanged apart
# from this header, because a FOURTH mechanism — conformance/loop-state.sh's `Kit-Row` check —
# now resolves a row through them. Three mechanisms already agreed on one identity
# (backlog-current's Disposition clause, backlog-presence's inprogress_hints, board-claim's ref
# name); loop-state did not, and a whole-file `grep -Fq` is what that disagreement cost.
# THE GRAMMAR, STATED ONCE for prose and code: the row id is the FIRST backticked token in the
# row's Item cell, matching [A-Z0-9][A-Z0-9-]*. Decoration BEFORE it (`✅`, `⏸`, `**`, `▶️`) is
# allowed — which is why 162 pre-convention Done rows already resolve. This is deliberately not
# a "must start the cell" rule: the board does not obey one.
# NOTHING HERE INTERPOLATES A BOARD-SUPPLIED ID INTO A REGEX. A row id is attacker-influenceable
# text (anyone can open a PR), so every match below is string EQUALITY or a CONSTANT `case`
# pattern applied TO the id — never a pattern built FROM it.

# row_id_ok <token> : rc0 iff the token matches [A-Z0-9][A-Z0-9-]*. THE ONE DEFINITION of the
# grammar for the checks that source this library. scripts/board-claim.sh carries a byte-equal
# `bc_row_ok` and CANNOT call this one — its selftest drives it inside throwaway clones that
# carry a BACKLOG.md and nothing else, so sourcing a conformance/ library would make the verb
# untestable in the only fixture that proves it (that file's own disclosure at :210-224 states
# the same boundary for the board parser).
# ⚠️ THE COST USED TO BE "nothing greps the two implementations against each other". IT IS GATED
# NOW (reviewer R3): `backlog-current.sh --selftest`'s `rid/twin` leg extracts the `case` BODY of
# this function and of `bc_row_ok` and compares them byte for byte, so changing either arm reds —
# measured against a mutant that widened board-claim's first arm to `[!A-Za-z0-9]*`. What that leg
# does NOT prove, and the difference matters: it compares TEXT, not behaviour, so two identical
# bodies in files whose surrounding shell options differ would still pass.
row_id_ok() {
  case "$1" in
    '')            return 1 ;;
    [!A-Z0-9]*)    return 1 ;;
    *[!A-Z0-9-]*)  return 1 ;;
  esac
  return 0
}

# backtick_id <cell> : the FIRST backticked token of a cell, extracted exactly as
# inprogress_hints does in backlog-presence.sh, so "the row's identifier" means one thing across
# every gate. Empty when the cell carries no backticks.
backtick_id() {
  case "$1" in
    *'`'*) _bi=${1#*\`}; printf '%s' "${_bi%%\`*}" ;;
    *) printf '' ;;
  esac
}

# row_count <board-file> <id> : how many Item cells across the seven sections resolve to exactly
# this backticked id, printed on stdout. This is what makes `Kit-Row` a LOOKUP rather than a
# substring test: 0 = names no row, 1 = resolved, >=2 = AMBIGUOUS. Uniqueness is BOARD-LOCAL —
# two boards, or a tracker, are outside it (design §5).
row_count() {
  _rc_bl="$1"; _rc_want="$2"; _rc_hits=0
  for _rc_sec in "Ready" "In Progress" "In Review" "Blocked" "Released" "Done" "Backlog (unrefined)"; do
    _rc_rows=$(section_rows "$_rc_bl" "$_rc_sec")
    [ -n "$_rc_rows" ] || continue
    _rc_n=0
    while IFS= read -r _rc_row; do
      _rc_n=$((_rc_n + 1))
      [ "$_rc_n" -eq 1 ] && continue            # header row
      is_sep_row "$_rc_row" && continue
      if [ "$(backtick_id "$(cell "$_rc_row" 1)")" = "$_rc_want" ]; then
        _rc_hits=$((_rc_hits + 1))
      fi
    done <<EOF
$_rc_rows
EOF
  done
  printf '%s\n' "$_rc_hits"
}

# row_exists <board-file> <id> : rc0 iff SOME section's Item cell carries exactly this backticked
# id. THIS IS THE SEAM. Today it has one implementation, over BACKLOG.md, through the shared
# parser. `TRACKER-BACKED-GOVERNANCE` (Tier 4) implements the same seam for a Jira/Linear key;
# `NON-MD-BACKEND-NEVER-SILENT` (Tier 2) makes a non-md backend say NOT ENFORCED, loudly, until
# then. A row boarded and closed in the SAME PR resolves — resolution proves EXISTENCE, never
# independence, and §5 of the design says so rather than pretending otherwise.
# It is EXISTENCE ONLY and stays that way: backlog-current.sh's Disposition clause asks "is this
# a real row", not "is it unique". loop-state asks the stronger question and calls row_count.
row_exists() {
  [ "$(row_count "$1" "$2")" -gt 0 ]
}

# row_id_index <board-file> : every Item-cell backticked id across the seven sections, one per
# line, printed on stdout. PREPUSH-CORE-DEFAULT: row_exists re-parses all seven sections per call
# (~2.6 s on the 350-row board), and backlog-current.sh's Disposition leg calls it once per `row`
# clause (~135x) — O(n^2), ~5 min. This is the SAME walk row_count does (same section list, same
# header skip, same is_sep_row, same cell/backtick_id), run ONCE; the caller asks many ids of the
# one result via row_in_index. A row whose Item cell has no backticks prints an empty line, as
# row_count's backtick_id yields "" for it — row_in_index never matches an empty <id> meaningfully
# (callers validate the id's grammar first). EXISTENCE ONLY, like row_exists: uniqueness stays
# row_count's. The parity leg in backlog-current.sh --selftest (`rid/index-parity`) is what proves
# row_in_index(row_id_index B) == row_exists B for every id on the fixture corpus — edit the walk
# here and row_count TOGETHER, or that leg goes red.
row_id_index() {
  _ri_bl="$1"
  for _ri_sec in "Ready" "In Progress" "In Review" "Blocked" "Released" "Done" "Backlog (unrefined)"; do
    _ri_rows=$(section_rows "$_ri_bl" "$_ri_sec")
    [ -n "$_ri_rows" ] || continue
    _ri_n=0
    while IFS= read -r _ri_row; do
      _ri_n=$((_ri_n + 1))
      [ "$_ri_n" -eq 1 ] && continue            # header row
      is_sep_row "$_ri_row" && continue
      printf '%s\n' "$(backtick_id "$(cell "$_ri_row" 1)")"
    done <<EOF
$_ri_rows
EOF
  done
}

# row_in_index <index-text> <id> : rc0 iff <id> is exactly one whole line of <index-text> (the
# stdout of row_id_index, held in a variable by the caller). Fixed-string, whole-line: the id is
# never turned into a pattern, so a prefix/suffix/substring of a real id, or an id carrying regex
# metacharacters, cannot match. An empty <id> returns 1 (grep -x with "" would match any blank line).
row_in_index() {
  [ -n "$2" ] || return 1
  printf '%s\n' "$1" | grep -qxF -- "$2"
}

# retro_cell <row> <header-row> <col-index> : the Retro/outcome cell.
# MOVED HERE from backlog-current.sh (SLICE-CLOSES-IN-ONE-PR §4.2), because backlog-presence.sh's
# Done arm must read the SAME cell the retro gate grades — two extractions of one cell would drift
# invisibly to both gates' tests, which is this library's whole reason.
# BOARD-PIPE-ESCAPE T1 re-expressed this on the shared parser: it used to hand-roll its own raw
# `awk -F'|'` join (rejoining fields past col-index, with an `_rc_after` guard to detect a NAMED
# column following Retro/outcome and fall back to cell() rather than over-capture) because cell()
# split on every raw '|' and mis-parsed a correctly-escaped `\|` inside the cell. cell() is now
# itself GFM-exact — it resolves an escaped pipe anywhere in the row, including inside this
# column's own content — so that workaround (and its raw-split `_rc_after` guard) is redundant
# and is dropped. <header-row> is kept in the signature for caller compatibility (unused).
retro_cell() {
  cell "$1" "$3"
}

# is_bare_na / is_na_reason — MOVED HERE from backlog-current.sh (TBG-SEAM-MD-ARM WAVE 3),
# byte-unchanged apart from this header, for the SAME reason retro_cell/row_count/backtick_id
# moved here (KW6-A2 T1.1 / BOARD-ROW-IDENTIFIER): a second copy of this LOGIC — as opposed to a
# constant, which is a different, accepted trade-off (see READY_METRIC_COL's own header in
# backlog-current.sh) — is exactly the drift this library exists to prevent, once a SECOND
# consumer needed it: seam_row_flag's `dor-metric` arm below grades the Ready Success-metric cell
# with this SAME predicate. Proven only BEHAVIOURALLY, via callers' own selftests (this file is
# listed in conformance/aggregate-exclusions.txt and carries no --selftest of its own — the same
# disclosure backlog-lib.sh's other moved primitives already carry, :175-190).
#
# is_bare_na <cell> : rc0 iff the cell is empty or a bare marker (a blank in a costume).
# ONE definition of "a blank in a costume", shared by every gated cell in backlog-current.sh —
# never two (BOARD-DOR-FIELDS design-gate MEDIUM-3). `?` joined the set with the Ready
# Success-metric gate: a lone question mark is the most natural "I don't know yet" a board author
# types, and it is a blank wearing punctuation. Widening here widens EVERY caller (Links, PR,
# Blocked on, Since, Success metric) — deliberate: a bare `?` was never an acceptable value in any
# of them.
is_bare_na() {
  _v=$(printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  [ -z "$_v" ] && return 0
  printf '%s' "$_v" | grep -Eiq '^(-|—|n/?a|tbd|none|[?])$'
}
# is_na_reason <cell> : rc0 iff the cell is the kit idiom `N/A — <reason>` (reason present).
is_na_reason() { printf '%s' "$1" | grep -Eiq '^[[:space:]]*n/?a[[:space:]]*(—|-)[[:space:]]*[^[:space:]]'; }

# --- THE SEAM, `md` ARM (continued) -------------------------------------------------------------
# See the header comment for SEAM_ROOT's contract. All five functions below are the ONLY board
# access a routed gate performs; every one delegates to a primitive already defined above.

# _seam_root_ok -> rc0 iff SEAM_ROOT is set and non-empty; else prints a one-line refusal to
# stderr and rc's 2 (UNVERIFIED, §4.2). WAVE 3 FAIL-CLOSED: every seam_* function below calls this
# FIRST. An unset SEAM_ROOT is a caller bug (every routed gate sets it before calling — see
# check_row/check_pr/check_dir/check_ready_metric), never a legitimate "board at the current
# directory" default: silently resolving an empty root would read `/BACKLOG.md` (or, worse, cwd's
# BACKLOG.md if a relative empty-string join happened to land there) — an answer about the WRONG
# board is worse than a loud refusal. `${SEAM_ROOT:-}` is load-bearing: every caller of this
# library runs under `set -u`, so a bare `$SEAM_ROOT` reference on an unset variable would abort
# the whole gate process rather than let this function refuse cleanly.
_seam_root_ok() {
  if [ -z "${SEAM_ROOT:-}" ]; then
    echo "seam: SEAM_ROOT is unset — refusing" >&2
    return 2
  fi
  return 0
}

# --- SINGLE-PASS RESOLUTION (TBG-SEAM-MD-ARM WAVE 4, perf) ---------------------------------------
# MEASURED: backlog-current's Ready gate calls seam_row_flag once per Ready row (~28 rows on this
# repo's board); the pre-wave-4 arm re-derived uniqueness with row_count (7 fresh section_rows()
# awk passes over the WHOLE board) and THEN ran a SECOND, separate 7-pass scan to locate the row —
# 14 section_rows spawns per call. check_ready_metric's OWN pre-check (below, in
# backlog-current.sh) called the raw row_count primitive AGAIN before ever reaching the seam — a
# THIRD 7-pass scan per row. ~28 rows x ~21 board rescans is what took `backlog-current.sh .` from
# a 153s baseline to 259s.
#
# FIRST ATTEMPT (measured, reverted): a process-wide memo of the seven sections' section_rows()
# output, keyed by SEAM_ROOT. It made things WORSE (a synthetic 28-row board went from ~0.9s to
# ~10-20s) because EVERY seam_* call site — every production caller and every selftest leg —
# invokes these functions via `$(...)` command substitution, which forks a SUBSHELL. Assignments a
# subshell makes (the cache-population lines) are discarded the instant the subshell exits, so the
# "cache" rebuilt from scratch on every single call — strictly MORE work than before (a wasted
# rebuild in addition to the original scans), not less. Left as a documented dead end so this is
# not re-attempted; a working cross-call cache would need to survive a subshell (e.g. a file store
# keyed by `$$`, which — unlike a shell variable — a subshell cannot un-write), and that extra
# lifecycle/cleanup machinery was judged not worth it once the single-pass fix below closed most
# of the gap on its own.
#
# THE FIX: _seam_scan does uniqueness AND location in ONE walk per section (7 section_rows spawns
# total per call, not 14), and check_ready_metric (backlog-current.sh) no longer makes its OWN
# redundant row_count pre-check — it calls seam_row_flag directly and reads ITS rc, since
# seam_row_flag's single pass already establishes uniqueness as a side effect. Net: ~21 board
# rescans/row down to ~7 — no cross-call state, so it is correct regardless of how a caller invokes
# it (subshell or not). Scoped ENTIRELY to the seam functions: section_rows/row_count/cell/
# col_index themselves are UNCHANGED, so every carve-out validator (column-arity, GFM-shape, Done
# retro/UAT — ruling B) that calls them directly keeps its own, always-fresh read.

# _seam_scan <id> -> ONE pass over the whole board's seven sections, establishing uniqueness,
# section, row text and header text in the SAME walk — replacing row_count() [7 section_rows
# scans] plus a SEPARATE locate loop [7 more] with ONE section_rows call per section (7 total).
# Sets globals: _seam_scan_hits (the row_count-equivalent), and — iff hits==1 — _seam_scan_sec
# (the §4.1 section NAME, e.g. "In Progress"), _seam_scan_row (the row text), _seam_scan_hdr (that
# section's header row text).
_seam_scan() {
  _ss_id="$1"
  _ss_board="$SEAM_ROOT/BACKLOG.md"
  _seam_scan_hits=0; _seam_scan_sec=""; _seam_scan_row=""; _seam_scan_hdr=""
  [ -f "$_ss_board" ] || return 0
  for _ss_sec in "Ready" "In Progress" "In Review" "Blocked" "Released" "Done" "Backlog (unrefined)"; do
    _ss_rows=$(section_rows "$_ss_board" "$_ss_sec")
    [ -n "$_ss_rows" ] || continue
    _ss_n=0; _ss_hdr=""
    while IFS= read -r _ss_r; do
      _ss_n=$((_ss_n + 1))
      if [ "$_ss_n" -eq 1 ]; then _ss_hdr="$_ss_r"; continue; fi   # header row
      is_sep_row "$_ss_r" && continue
      if [ "$(backtick_id "$(cell "$_ss_r" 1)")" = "$_ss_id" ]; then
        _seam_scan_hits=$((_seam_scan_hits + 1))
        _seam_scan_sec="$_ss_sec"; _seam_scan_row="$_ss_r"; _seam_scan_hdr="$_ss_hdr"
      fi
    done <<EOF
$_ss_rows
EOF
  done
}

# seam_backend -> the backend token (§4.2). `md` arm: a thin wrapper over resolve_backend, which
# is already "the ONE parser" (its own header, F5) — never re-derived here. Same string, same rc
# (always 0) as calling resolve_backend directly: this is a pure rename of the call site, not a
# behaviour change, so every existing caller-side `case` over its output (empty / a token /
# `unrecognized:<x>`) keeps working unmodified. Reads no cache — resolve_backend reads CLAUDE.md,
# not the board.
seam_backend() {
  _seam_root_ok || return 2
  resolve_backend "$SEAM_ROOT"
}

# --- THE SEAM, TRACKER ARM (TBG-RECORD-GATES-BIND, design §2 scope A/B) -------------------------
# seam_tracker_record_set -> rc0 iff SEAM_RECORD is set and non-empty. THE H-4 SWITCH: callers use
# this to choose between the tracker arm below (SEAM_RECORD set -> rc0 bound / rc2 UNVERIFIED,
# NEVER waivable) and today's not_enforced_notice path (SEAM_RECORD unset -> rc3 NOT ENFORCED,
# byte-identical to before this slice, waiver ladder preserved). ONE copy; the three routed gates
# (loop-state.sh now, backlog-presence.sh/backlog-current.sh in TBG-READER-FLAGS-LIST) call it so
# the rc-2-vs-rc-3 decision cannot drift between them (design §8a, "Twins").
seam_tracker_record_set() {
  [ -n "${SEAM_RECORD:-}" ]
}

# §4.1 the closed state vocabulary — SAME set tracker-read.sh's TR_STATES carries (kept as a
# separate literal here: this file is sourced by callers that never source tracker-read.sh, and a
# cross-file call would need it turned into a library too — a wider change than this slice's scope).
SEAM_STATE_TOKENS="backlog ready in-progress in-review released done blocked cancelled"

# fix1 H1 — reset the memo + every _SRV_* answer global at FILE SCOPE (source time), so an
# exported env var (GITHUB_ENV, a poisoned shell profile) cannot pre-arm the memo before this
# process ever calls _seam_record_load itself. Also zeroes the test-only load counter to a safe
# literal (never `${VAR:=0}`, which would keep a pre-seeded value) — an arithmetic expansion of an
# attacker string there could itself run a command substitution.
_SRV_MEMO_OK=0
_SRV_MEMO_RECORD=""; _SRV_MEMO_ROOT=""; _SRV_MEMO_HEAD=""; _SRV_MEMO_SHA=""
_SRV_BACKEND=""; _SRV_HEAD=""; _SRV_REQUESTED=""; _SRV_READDAY=""; _SRV_CRED=""; _SRV_VERDICT=""
_SRV_ROWID=""; _SRV_ROWSTATE=""; _SRV_ROWS=""; _SRV_LISTS=""; _SRV_SUBJ_STATE=""
SEAM_TEST_LOAD_COUNT=0

# _seam_rows_state_of <id> -> rc0 with $_SRV_SUBJ_STATE set to that captured row's `state=`
# value, rc1 if no line of $_SRV_ROWS (T6a: id + its flags, one `row` line per line) carries that
# id. Extracted OUT of _seam_record_load (T6a) — that function already exceeds the 50-line
# guideline, so new logic grows a helper rather than the body; also keeps the requested<->row
# match order-independent (a scan over the fully-captured rows, done once the parse loop is over).
_seam_rows_state_of() {
  _srs_id="$1"; _SRV_SUBJ_STATE=""
  [ -n "$_SRV_ROWS" ] || return 1
  while IFS= read -r _srs_l; do
    [ -n "$_srs_l" ] || continue
    _srs_lid=${_srs_l%% *}
    [ "$_srs_lid" = "$_srs_id" ] || continue
    _srs_rest=${_srs_l#* }
    for _srs_tok in $_srs_rest; do
      case "$_srs_tok" in
        state=*) _SRV_SUBJ_STATE=${_srs_tok#state=} ;;
      esac
    done
    return 0
  done <<EOF
$_SRV_ROWS
EOF
  return 1
}

# _seam_row_token_lookup <id> <token-key> -> the TBG-READER-FLAGS-LIST T7 twin of
# _seam_rows_state_of above (same scan-$_SRV_ROWS-once idiom), generalised from a fixed `state=`
# key to any token key a `row` line may carry. Sets $_SRT_FOUND_ID (1 iff SOME row line carries
# <id>, else 0 — distinguishes "no such row" from "row exists, flag absent") and $_SRT_VALUE (the
# raw value after `=`, empty when the row carries no token of that key). rc is always 0 — callers
# read the two globals, never the return code, to tell the three outcomes apart (M-5: an absent
# flag is UNVERIFIED, never folded into "no such id"). Manual key compare (`${tok%%=*}`), never a
# `case` pattern built from the caller-supplied key, though today every caller passes a fixed
# literal from the closed §4.2 set.
_seam_row_token_lookup() {
  _srtl_id="$1"; _srtl_key="$2"
  _SRT_FOUND_ID=0; _SRT_VALUE=""
  [ -n "$_SRV_ROWS" ] || return 0
  while IFS= read -r _srtl_l; do
    [ -n "$_srtl_l" ] || continue
    _srtl_lid=${_srtl_l%% *}
    [ "$_srtl_lid" = "$_srtl_id" ] || continue
    _SRT_FOUND_ID=1
    _srtl_rest=${_srtl_l#* }
    [ "$_srtl_rest" = "$_srtl_l" ] && _srtl_rest=""
    for _srtl_tok in $_srtl_rest; do
      _srtl_tokkey=${_srtl_tok%%=*}
      [ "$_srtl_tokkey" = "$_srtl_key" ] && _SRT_VALUE=${_srtl_tok#*=}
    done
    return 0
  done <<EOF
$_SRV_ROWS
EOF
  return 0
}

# _seam_record_row_token <line-no> <token> -> rc0 iff <token> is a legal row flag (state=/claimed=/
# outcome-recorded=/blocked-by-open=/dor-*), setting the CALLER's _srl_have_state=1 when it is the
# state= token. Split OUT of _seam_record_row_line (below) so each of the two stays under the
# 50-line guideline — the per-token grammar is its own self-contained decision.
_seam_record_row_token() {
  _srt_n=$1; _srt_tok=$2
  case "$_srt_tok" in
    state=*)
      _srl_have_state=1
      _srt_st=${_srt_tok#state=}
      case " $SEAM_STATE_TOKENS " in
        *" $_srt_st "*) ;;
        *) echo "record line $_srt_n: key row refused (state token not in the §4.1 set)" >&2; return 2 ;;
      esac ;;
    claimed=yes|claimed=no) ;;
    # T6a leg7/leg8/§3f/F-9: forward-compat tokens, booleans ONLY, never `n/a`/`maybe`.
    outcome-recorded=yes|outcome-recorded=no) ;;
    blocked-by-open=yes|blocked-by-open=no) ;;
    dor-*)
      # L-c: split on the FIRST `=` only (never a glob `*=yes`/`*=no` tail match).
      _srt_dorname=${_srt_tok%%=*}
      _srt_dorval=${_srt_tok#*=}
      # T6a leg6/P-2: the dor- name set is CLOSED to exactly these four.
      case "$_srt_dorname" in
        dor-acceptance|dor-metric|dor-size|dor-risk) ;;
        *) echo "record line $_srt_n: key row refused (unknown dor- token name)" >&2; return 2 ;;
      esac
      case "$_srt_dorval" in
        yes|no|n/a) ;;
        *) echo "record line $_srt_n: key row refused (malformed dor- token value)" >&2; return 2 ;;
      esac ;;
    *) echo "record line $_srt_n: key row refused (unknown token)" >&2; return 2 ;;
  esac
  return 0
}

# _seam_record_row_line <line-no> <rest-after-"row "> -> rc0 on success (captures the row into
# _SRV_ROWS plus the row-id/token bookkeeping the post-loop checks rely on), rc2 on any refusal —
# echoes the SAME sentences the inline row) arm always did. Extracted OUT of
# _seam_record_load_parse's row) case arm (T6b Step 0, T6a review finding 5): the line loop stays a
# short dispatch table instead of an ever-growing case body, and the bijection pass below (T6b) gets
# a clean seam to call once the whole scan is done, rather than more inline growth here.
_seam_record_row_line() {
  _srl_n=$1; _srl_rest=$2
  _srv_row_count=$((_srv_row_count + 1))
  _srl_rid=${_srl_rest%% *}
  _srl_toks=${_srl_rest#* }
  [ "$_srl_toks" = "$_srl_rest" ] && _srl_toks=""
  row_id_ok "$_srl_rid" || { echo "record line $_srl_n: key row refused (bad id grammar)" >&2; return 2; }
  # T6a leg3: refuse a duplicate `row` id (a SEPARATE tracked set from `list`'s own — a row's own
  # id legitimately reappearing inside a `list` line is NOT a duplicate at this scope).
  case " $_srv_seen_rowids " in
    *" $_srl_rid "*) echo "record line $_srl_n: key row refused (duplicate id)" >&2; return 2 ;;
  esac
  _srv_seen_rowids="$_srv_seen_rowids $_srl_rid"
  _srl_have_state=0
  _srl_seen_toks=""
  for _srl_tok in $_srl_toks; do
    _srl_tokkey=${_srl_tok%%=*}
    # N-1: a duplicate token KEY inside one row line (e.g. two `state=` tokens) must refuse.
    case " $_srl_seen_toks " in
      *" $_srl_tokkey "*) echo "record line $_srl_n: key row refused (duplicate token)" >&2; return 2 ;;
    esac
    _srl_seen_toks="$_srl_seen_toks $_srl_tokkey"
    _seam_record_row_token "$_srl_n" "$_srl_tok" || return 2
  done
  [ "$_srl_have_state" -eq 1 ] || { echo "record line $_srl_n: key row refused (no state= token)" >&2; return 2; }
  # T6a: capture the WHOLE row (id + its flags) into _SRV_ROWS, one line per `row` — the subject
  # row (id == requested) is picked out AFTER the loop, by _seam_rows_state_of, since
  # `requested` may occur before OR after `row` in the file (unchanged M-6 invariant).
  _SRV_ROWS="${_SRV_ROWS}${_srl_rid} ${_srl_toks}
"
  return 0
}

# _seam_record_list_line <line-no> <rest-after-"list "> -> rc0 on success (captures the list into
# _SRV_LISTS plus the state/id bookkeeping the post-loop checks rely on), rc2 on any refusal.
# Extracted OUT of _seam_record_load_parse's list) case arm (T6b Step 0, mirrors
# _seam_record_row_line above).
_seam_record_list_line() {
  _sll_n=$1; _sll_rest=$2
  _sll_lst=${_sll_rest%% *}
  _sll_ids=${_sll_rest#* }
  [ "$_sll_ids" = "$_sll_rest" ] && _sll_ids=""
  case " $SEAM_STATE_TOKENS " in
    *" $_sll_lst "*) ;;
    *) echo "record line $_sll_n: key list refused (state token not in the §4.1 set)" >&2; return 2 ;;
  esac
  # T6a leg4: refuse a SECOND `list` line for the same state (one list line per state).
  case " $_srv_seen_list_states " in
    *" $_sll_lst "*) echo "record line $_sll_n: key list refused (duplicate state)" >&2; return 2 ;;
  esac
  _srv_seen_list_states="$_srv_seen_list_states $_sll_lst"
  # T6a leg5: refuse a duplicate id WITHIN this one `list` line. Reset PER LINE (never accumulated
  # across lines) — the SAME id appearing in two DIFFERENT lists is T6b's bijection question,
  # deliberately not checked here.
  _sll_seen_thislist=""
  for _sll_lid in $_sll_ids; do
    row_id_ok "$_sll_lid" || { echo "record line $_sll_n: key list refused (bad id grammar)" >&2; return 2; }
    case " $_sll_seen_thislist " in
      *" $_sll_lid "*) echo "record line $_sll_n: key list refused (duplicate id)" >&2; return 2 ;;
    esac
    _sll_seen_thislist="$_sll_seen_thislist $_sll_lid"
  done
  # T6a leg2: capture the WHOLE list (state + its ids) into _SRV_LISTS, one line per `list`.
  _SRV_LISTS="${_SRV_LISTS}${_sll_lst} ${_sll_ids}
"
  return 0
}

# _seam_record_load -> the record parser/validator (design §4.3, the CLOSED grammar, validated as
# a WHOLE-RECORD gate BEFORE any answer). Reads $SEAM_RECORD (NEVER $KIT_TRACKER_RECORD directly —
# M-2: the gate maps the env var to SEAM_RECORD only on the local/hygiene path, mirroring how
# SEAM_ROOT mirrors LS_BOARDROOT). Reads $SEAM_ROOT/.kit/tracker.conf as the BASE conf for the pin
# check (M-1) and $SEAM_HEAD as the sha being graded (H-2). rc0 on a fully bound-or-unverified but
# STRUCTURALLY/CONSISTENCY-SOUND record (globals set below); rc2 on ANY refusal — never a partial
# answer, nothing ever eval'd or interpolated into a shell/format string (every compare is a quoted
# case or `[ ]`). L-1: every refusal names the line + key + reason, NEVER the value — `echo` below
# never interpolates $_srv_l/$_srv_rest/a token; the one exception (the sha compare messages) still
# never echoes attacker bytes, only a fixed sentence.
# Globals set on rc0: _SRV_BACKEND, _SRV_HEAD, _SRV_REQUESTED, _SRV_READDAY, _SRV_CRED, _SRV_VERDICT,
# _SRV_ROWID/_SRV_ROWSTATE (set only when a `row` line's id equals `requested` — the subject).
# _SRV_ROWS/_SRV_LISTS (T6a: every captured `row`/`list` line, newline-joined) are VALID ONLY ON
# RC0 — F-2: cleared by the wrapper below on ANY refusal, never a stale partially-parsed capture
# left over from a record that failed midway through parsing.
_seam_record_load() {
  # T89s item4 (parse memo, T7 seat M-1): skip the re-PARSE when SEAM_RECORD/SEAM_ROOT/SEAM_HEAD
  # and the record file's own sha256 all still match the last rc-0 load — a failed load is NEVER
  # cached (the memo is only ever armed on the rc0 path below), so a refusal always re-tries.
  # fix1 H3: a symlinked path never feeds the pre-hash (matches the parser's own [ -L ] refusal) —
  # a stale memo could otherwise hit on a path swapped to a symlink over byte-identical content,
  # skipping the parser's check entirely (that check never runs on a memo hit).
  _srv_memo_sha=""
  if [ -n "${SEAM_RECORD:-}" ] && [ ! -L "${SEAM_RECORD:-}" ] && [ -f "${SEAM_RECORD:-}" ] && [ -r "${SEAM_RECORD:-}" ]; then
    _srv_memo_sha=$( { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } < "$SEAM_RECORD" 2>/dev/null | awk '{print $1}')
  fi
  if [ "${_SRV_MEMO_OK:-0}" -eq 1 ] \
    && [ "${_SRV_MEMO_RECORD:-}" = "${SEAM_RECORD:-}" ] \
    && [ "${_SRV_MEMO_ROOT:-}" = "${SEAM_ROOT:-}" ] \
    && [ "${_SRV_MEMO_HEAD:-}" = "${SEAM_HEAD:-}" ] \
    && [ -n "$_srv_memo_sha" ] && [ "$_srv_memo_sha" = "${_SRV_MEMO_SHA:-}" ]; then
    return 0
  fi
  _seam_record_load_parse; _srv_load_rc=$?
  # Test-only call counter (item4 leg d) — never printed, so it carries no production output.
  : "${SEAM_TEST_LOAD_COUNT:=0}"; SEAM_TEST_LOAD_COUNT=$((SEAM_TEST_LOAD_COUNT + 1))
  # F-2: one exit point for the clear, rather than scattering it across every one of this
  # function's ~50 `return 2` refusal sites — every refusal, wherever it fires, routes back through
  # here before the caller ever sees the return code. T6b-fix1 Minor 3: EVERY _SRV_* global (all 11)
  # is cleared on refusal, not just the four a LATE refusal (e.g. a wrong SEAM_HEAD, which runs after
  # the subject-match step has already set several of these) would otherwise leave stale.
  [ "$_srv_load_rc" -eq 0 ] || {
    _SRV_BACKEND=""; _SRV_HEAD=""; _SRV_REQUESTED=""; _SRV_READDAY=""; _SRV_CRED=""; _SRV_VERDICT=""
    _SRV_ROWID=""; _SRV_ROWSTATE=""; _SRV_ROWS=""; _SRV_LISTS=""; _SRV_SUBJ_STATE=""
    _SRV_MEMO_OK=0
    return "$_srv_load_rc"
  }
  # fix1 H3: re-hash AFTER the parse; arm the memo only when the pre- and post-parse digests
  # agree — a record swapped mid-call must never be cached as the file that was actually read. The
  # call itself still answers rc0 (the parse it just ran was internally consistent); only the CACHE
  # is withheld, so the next call always re-verifies.
  _srv_memo_sha2=""
  if [ -n "${SEAM_RECORD:-}" ] && [ ! -L "${SEAM_RECORD:-}" ] && [ -f "${SEAM_RECORD:-}" ] && [ -r "${SEAM_RECORD:-}" ]; then
    _srv_memo_sha2=$( { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } < "$SEAM_RECORD" 2>/dev/null | awk '{print $1}')
  fi
  if [ -z "$_srv_memo_sha" ] || [ "$_srv_memo_sha" != "$_srv_memo_sha2" ]; then
    _SRV_MEMO_OK=0
    return 0
  fi
  _SRV_MEMO_OK=1
  _SRV_MEMO_RECORD="${SEAM_RECORD:-}"; _SRV_MEMO_ROOT="${SEAM_ROOT:-}"; _SRV_MEMO_HEAD="${SEAM_HEAD:-}"
  _SRV_MEMO_SHA="$_srv_memo_sha"
  return 0
}

_seam_record_load_parse() {
  _srv_file="${SEAM_RECORD:-}"
  _SRV_BACKEND=""; _SRV_HEAD=""; _SRV_REQUESTED=""; _SRV_READDAY=""; _SRV_CRED=""; _SRV_VERDICT=""
  _SRV_ROWID=""; _SRV_ROWSTATE=""
  _SRV_ROWS=""; _SRV_LISTS=""
  [ -n "$_srv_file" ] || { echo "seam: SEAM_RECORD is unset — refusing" >&2; return 2; }
  # M-2: a non-regular-file record (symlink, FIFO, directory) is refused BEFORE any read.
  if [ -L "$_srv_file" ]; then
    echo "seam: record path is a symlink — refused" >&2; return 2
  fi
  if [ ! -f "$_srv_file" ] || [ ! -r "$_srv_file" ]; then
    echo "seam: record path is not a readable regular file — refused" >&2; return 2
  fi
  # M-2: size cap (<=64 KiB / <=512 lines) BEFORE parsing.
  _srv_bytes=$(wc -c < "$_srv_file" 2>/dev/null | tr -d '[:space:]') || _srv_bytes=""
  case "$_srv_bytes" in ''|*[!0-9]*) _srv_bytes=99999999 ;; esac
  if [ "$_srv_bytes" -gt 65536 ]; then
    echo "seam: record exceeds the 64 KiB size cap — refused" >&2; return 2
  fi
  _srv_lines=$(wc -l < "$_srv_file" 2>/dev/null | tr -d '[:space:]') || _srv_lines=""
  case "$_srv_lines" in ''|*[!0-9]*) _srv_lines=0 ;; esac
  if [ "$_srv_lines" -gt 512 ]; then
    echo "seam: record exceeds the 512-line cap — refused" >&2; return 2
  fi
  # N-2: a NUL byte is invisible to the per-line charset gate below (`read -r` silently drops it,
  # so a smuggled NUL could straddle/hide a byte the charset gate would otherwise refuse). Detect it
  # over the WHOLE file, before any line is parsed — `tr -d` stripped of NULs must equal the file
  # byte-for-byte, or one was present.
  if ! LC_ALL=C tr -d '\000' < "$_srv_file" | cmp -s - "$_srv_file"; then
    echo "seam: record contains a NUL byte — refused" >&2; return 2
  fi

  _srv_n=0
  _srv_seen_backend=0; _srv_seen_pin=0; _srv_seen_head=0; _srv_seen_requested=0
  _srv_seen_readday=0; _srv_seen_credential=0; _srv_seen_verdict=0
  _srv_row_count=0
  _srv_seen_rowids=""; _srv_seen_list_states=""
  _srv_pinhex=""

  while IFS= read -r _srv_l || [ -n "$_srv_l" ]; do
    _srv_n=$((_srv_n + 1))

    if [ "$_srv_n" -eq 1 ]; then
      if [ "$_srv_l" != "kit-tracker-read 1" ]; then
        echo "record line 1: key header refused (must be exactly 'kit-tracker-read 1')" >&2
        return 2
      fi
      continue
    fi

    # M-6 WHOLE-LINE CHARSET GATE, before any field parse — closes CR/tab/NBSP/ESC/BOM/backtick/
    # $/%/;/|/</> and a blank line in ONE check. A blank line is refused here too (no trailing/
    # interstitial blank lines; `#` is refused by the same gate — the charset carries no `#`).
    case "$_srv_l" in
      '') echo "record line $_srv_n: key ? refused (blank line not permitted)" >&2; return 2 ;;
      # fix1 L2: spelled out (item2's own fix, generalised) — a bracket RANGE collates a Unicode
      # letter as "inside" A-Za-z under LC_ALL=en_US.UTF-8 on macOS sh/bash; a literal set does not.
      *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\ =:./-]*) echo "record line $_srv_n: key ? refused (byte outside the closed charset)" >&2; return 2 ;;
      # T6b Leg 0 (T6a review, M-6): exactly ONE ASCII space between tokens — a second consecutive
      # space anywhere, or a single trailing space, is refused. `list done` and `list done  ` must
      # not capture differently (H-3: a reader that treats "present list, zero ids" as a real
      # answer would read the trailing-space form as non-empty).
      *'  '*|*' ') echo "record line $_srv_n: key ? refused (more than one space between tokens, or a trailing space — M-6)" >&2; return 2 ;;
    esac

    _srv_key=${_srv_l%% *}
    _srv_rest=${_srv_l#* }
    [ "$_srv_rest" = "$_srv_l" ] && _srv_rest=""

    case "$_srv_key" in
      backend)
        [ "$_srv_seen_backend" -eq 0 ] || { echo "record line $_srv_n: key backend refused (duplicate)" >&2; return 2; }
        _srv_seen_backend=1
        case "$_srv_rest" in
          # fix1 L2: spelled out — the range also collates uppercase as "inside" a-z under
          # LC_ALL=en_US.UTF-8 (same class item2 already closed for pin/head).
          ''|*[!abcdefghijklmnopqrstuvwxyz0123456789_-]*) echo "record line $_srv_n: key backend refused (malformed token)" >&2; return 2 ;;
        esac
        _SRV_BACKEND=$_srv_rest ;;
      pin)
        [ "$_srv_seen_pin" -eq 0 ] || { echo "record line $_srv_n: key pin refused (duplicate)" >&2; return 2; }
        _srv_seen_pin=1
        case "$_srv_rest" in
          sha256:*) _srv_pinhex=${_srv_rest#sha256:} ;;
          *) echo "record line $_srv_n: key pin refused (must be sha256:<64 hex>)" >&2; return 2 ;;
        esac
        # T89s item2 (T4 seat M-1): a spelled-out class, not `[0-9a-f]` — under LC_ALL=en_US.UTF-8
        # on sh/bash the bracket range also collates uppercase, wrongly accepting it as hex.
        case "$_srv_pinhex" in
          *[!0123456789abcdef]*) echo "record line $_srv_n: key pin refused (non-hex digest)" >&2; return 2 ;;
        esac
        if [ "${#_srv_pinhex}" -ne 64 ]; then
          echo "record line $_srv_n: key pin refused (digest is not 64 hex characters)" >&2; return 2
        fi ;;
      head)
        [ "$_srv_seen_head" -eq 0 ] || { echo "record line $_srv_n: key head refused (duplicate)" >&2; return 2; }
        _srv_seen_head=1
        case "${#_srv_rest}" in
          40|64) ;;
          *) echo "record line $_srv_n: key head refused (must be a 40 or 64 hex character sha)" >&2; return 2 ;;
        esac
        # T89s item2 (T4 seat M-1): spelled-out class, same locale reason as the pin check above.
        case "$_srv_rest" in
          *[!0123456789abcdef]*) echo "record line $_srv_n: key head refused (non-hex sha)" >&2; return 2 ;;
        esac
        _SRV_HEAD=$_srv_rest ;;
      requested)
        [ "$_srv_seen_requested" -eq 0 ] || { echo "record line $_srv_n: key requested refused (duplicate)" >&2; return 2; }
        _srv_seen_requested=1
        row_id_ok "$_srv_rest" || { echo "record line $_srv_n: key requested refused (bad id grammar)" >&2; return 2; }
        _SRV_REQUESTED=$_srv_rest ;;
      read-day)
        [ "$_srv_seen_readday" -eq 0 ] || { echo "record line $_srv_n: key read-day refused (duplicate)" >&2; return 2; }
        _srv_seen_readday=1
        case "$_srv_rest" in
          [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
          *) echo "record line $_srv_n: key read-day refused (must be YYYY-MM-DD)" >&2; return 2 ;;
        esac
        _SRV_READDAY=$_srv_rest ;;
      credential)
        [ "$_srv_seen_credential" -eq 0 ] || { echo "record line $_srv_n: key credential refused (duplicate)" >&2; return 2; }
        _srv_seen_credential=1
        case "$_srv_rest" in
          ok|over-privileged|unverified) ;;
          *) echo "record line $_srv_n: key credential refused (unknown token)" >&2; return 2 ;;
        esac
        _SRV_CRED=$_srv_rest ;;
      verdict)
        [ "$_srv_seen_verdict" -eq 0 ] || { echo "record line $_srv_n: key verdict refused (duplicate)" >&2; return 2; }
        _srv_seen_verdict=1
        case "$_srv_rest" in
          bound|unverified) ;;
          *) echo "record line $_srv_n: key verdict refused (unknown token)" >&2; return 2 ;;
        esac
        _SRV_VERDICT=$_srv_rest ;;
      row)
        _seam_record_row_line "$_srv_n" "$_srv_rest" || return 2
        ;;
      list)
        _seam_record_list_line "$_srv_n" "$_srv_rest" || return 2
        ;;
      *)
        # L-a: cap the echoed key at 32 bytes — an unbounded key (e.g. a multi-KB line with no
        # space) would otherwise dump arbitrary attacker-controlled length onto stderr.
        _srv_key32=$_srv_key
        if [ "${#_srv_key32}" -gt 32 ]; then
          _srv_key32=$(printf '%s' "$_srv_key32" | cut -c1-32)
        fi
        echo "record line $_srv_n: key $_srv_key32 refused (unknown key)" >&2
        return 2 ;;
    esac
  done < "$_srv_file"

  [ "$_srv_seen_backend" -eq 1 ]   || { echo "seam: record missing key backend — refused" >&2; return 2; }
  [ "$_srv_seen_pin" -eq 1 ]       || { echo "seam: record missing key pin — refused" >&2; return 2; }
  [ "$_srv_seen_head" -eq 1 ]      || { echo "seam: record missing key head — refused" >&2; return 2; }
  [ "$_srv_seen_requested" -eq 1 ] || { echo "seam: record missing key requested — refused" >&2; return 2; }
  [ "$_srv_seen_readday" -eq 1 ]   || { echo "seam: record missing key read-day — refused" >&2; return 2; }
  [ "$_srv_seen_credential" -eq 1 ] || { echo "seam: record missing key credential — refused" >&2; return 2; }
  [ "$_srv_seen_verdict" -eq 1 ]   || { echo "seam: record missing key verdict — refused" >&2; return 2; }

  # M-6/T6a: `verdict bound` with no `row` line at all is refused; when one or more `row` lines
  # are present, exactly one of them must be the subject (id == requested) — with multiple rows
  # now legal (§3b), "the only row" becomes "some row", found by scanning the captured _SRV_ROWS
  # (order-independent: `requested` may occur before OR after `row` in the file).
  if [ "$_SRV_VERDICT" = "bound" ] && [ "$_srv_row_count" -eq 0 ]; then
    echo "seam: record verdict is bound but carries no row line — refused" >&2; return 2
  fi
  if [ "$_srv_row_count" -gt 0 ]; then
    if _seam_rows_state_of "$_SRV_REQUESTED"; then
      _SRV_ROWID=$_SRV_REQUESTED; _SRV_ROWSTATE=$_SRV_SUBJ_STATE
    else
      echo "seam: record row id does not equal requested — refused" >&2; return 2
    fi
  fi
  # M-3: an unverified credential must never coexist with a bound verdict; an over-privileged one
  # binds, with a stderr notice (S-11) — never a refusal.
  if [ "$_SRV_CRED" = "unverified" ] && [ "$_SRV_VERDICT" = "bound" ]; then
    echo "seam: record credential is unverified but verdict is bound — refused" >&2; return 2
  fi
  if [ "$_SRV_CRED" = "over-privileged" ]; then
    echo "seam: NOTICE — record credential is over-privileged for this read (binding anyway, S-11)" >&2
  fi

  # M-1: the pin proves CONSISTENCY (the record was made against the conf in force), never
  # authenticity — the trust boundary is the trusted job (S-1). Digest the SAME base conf bytes a
  # writer would (tracker-read.sh's own tr_pin_digest: sha256sum, falling back to shasum -a 256 —
  # L-4, same tool, same bytes, both sides).
  _srv_baseconf="$SEAM_ROOT/.kit/tracker.conf"
  if [ ! -f "$_srv_baseconf" ] || [ ! -r "$_srv_baseconf" ]; then
    echo "seam: base .kit/tracker.conf is absent or unreadable — cannot verify the record's pin — refused" >&2
    return 2
  fi
  _srv_basedigest=$( { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } < "$_srv_baseconf" 2>/dev/null | awk '{print $1}') || _srv_basedigest=""
  if [ -z "$_srv_basedigest" ] || [ "$_srv_basedigest" != "$_srv_pinhex" ]; then
    echo "seam: record pin does not match sha256 of the base .kit/tracker.conf — stale pin, refused" >&2
    return 2
  fi
  # M-4/N-4: backend declared in three places must agree — the record, the base conf, and
  # CLAUDE.md. The base-conf side reads through the ONE conf parser (scripts/tracker-conf.sh get),
  # never a second ad hoc parser — a raw `grep '^backend=' | head -1` bound on the FIRST of two
  # `backend=` lines while tracker-conf.sh's own grammar gate refuses a duplicate singleton key
  # outright (fail-closed, not last/first-wins). $0 is the CALLING script's own path (this file is
  # sourced, never exec'd), and every caller lives directly under conformance/, so
  # dirname("$0")/.. resolves to this kit checkout's root, mirroring loop-state.sh's own DIR calc.
  # shellcheck disable=SC1007 # `CDPATH= cd` clears CDPATH so a user's CDPATH cannot redirect the cd.
  _srv_kitroot=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || _srv_kitroot=""
  _srv_confsh="$_srv_kitroot/scripts/tracker-conf.sh"
  if [ -z "$_srv_kitroot" ] || [ ! -f "$_srv_confsh" ]; then
    echo "seam: tracker-conf.sh could not be located to verify the base conf's backend — refused" >&2
    return 2
  fi
  _srv_baseback=$(sh "$_srv_confsh" get backend "$_srv_baseconf" 2>/dev/null) || _srv_baseback=""
  if [ "$_srv_baseback" != "$_SRV_BACKEND" ]; then
    echo "seam: record backend does not equal .kit/tracker.conf's backend — refused" >&2
    return 2
  fi
  _srv_claudeback=$(resolve_backend "$SEAM_ROOT")
  if [ "$_srv_claudeback" != "$_SRV_BACKEND" ]; then
    echo "seam: record backend does not equal the declared CLAUDE.md backend — refused" >&2
    return 2
  fi

  # H-2: the record must be for the SAME subject sha the gate is grading — a sourced SEAM_HEAD
  # (mirrors SEAM_ROOT), never taken from the record's own claim alone (replay defence).
  if [ -z "${SEAM_HEAD:-}" ]; then
    echo "seam: SEAM_HEAD is unset — refusing" >&2
    return 2
  fi
  if [ "$_SRV_HEAD" != "$SEAM_HEAD" ]; then
    echo "seam: record head does not match the subject sha being graded — refused" >&2
    return 2
  fi

  # L-2: read-day window — bind UTC today or yesterday only (belt-and-braces with H-2).
  _srv_today=$(date -u +%Y-%m-%d 2>/dev/null) || _srv_today=""
  _srv_yday=$(date -u -d 'yesterday' +%Y-%m-%d 2>/dev/null) || _srv_yday=""
  [ -n "$_srv_yday" ] || _srv_yday=$(date -u -v-1d +%Y-%m-%d 2>/dev/null) || _srv_yday=""
  case "$_SRV_READDAY" in
    "$_srv_today") ;;
    "$_srv_yday") [ -n "$_srv_yday" ] || { echo "seam: read-day window could not be computed — refused" >&2; return 2; } ;;
    *) echo "seam: record read-day is outside the today/yesterday window — refused" >&2; return 2 ;;
  esac

  _seam_record_bijection || return 2

  return 0
}

# _seam_id_matches_project <id> -> rc0 iff <id> matches ^$_srb_project-[1-9][0-9]*$ (F-5; a
# leading zero, e.g. AB-07, is refused — real Jira keys never carry one). Reads the caller's
# _srb_project (set once by _seam_record_bijection, below).
_seam_id_matches_project() {
  case "$1" in
    "$_srb_project"-[1-9]*) _saimp_suf=${1#"$_srb_project"-} ;;
    *) return 1 ;;
  esac
  case "$_saimp_suf" in *[!0-9]*) return 1 ;; esac
  return 0
}

# _seam_bijection_scan -> the T89s item5 single-pass core, split OUT of _seam_record_bijection
# (below) to keep both under the 50-line guideline (same reason the old _seam_bijection_subject_iff
# split existed). ONE awk pass: a row-state hash map (built once, O(rows)) replaces the old nested
# "for every listed id, rescan every row" (O(listed*rows)) — same accept/refuse set, folding in the
# F-5 listed-id grammar, the row/list state-agreement rule, the must-be-listed rule, and the "iff"
# direction (T6b-fix1 Important 1: the subject's OWN state, if listed at all, must list the subject).
# fix1 M6: prints "ok" or one of five FIXED reason tokens (never record bytes) — grammar/norow/
# statemismatch/iff/unlisted — so the caller can name WHICH rule refused, not one generic sentence.
# Reads the caller's _srb_project (set by _seam_record_bijection).
# _SRV_ROWS/_SRV_LISTS are passed via ENVIRON, never `awk -v` (measured: macOS's bundled awk
# errors "newline in string" on a `-v`-assigned value carrying a real embedded/trailing newline —
# both fields always do, one per captured line — while ENVIRON has no such limit).
_seam_bijection_scan() {
  _SRB_ENV_ROWS="$_SRV_ROWS" _SRB_ENV_LISTS="$_SRV_LISTS" \
  awk -v subj="$_SRV_REQUESTED" -v subjrow="$_SRV_ROWID" \
    -v subjstate="$_SRV_ROWSTATE" -v project="$_srb_project" '
    function idok(id,    rest) {
      if (substr(id, 1, length(project) + 1) != project "-") return 0
      rest = substr(id, length(project) + 2)
      return (rest ~ /^[1-9][0-9]*$/)
    }
    BEGIN {
      rows = ENVIRON["_SRB_ENV_ROWS"]; lists = ENVIRON["_SRB_ENV_LISTS"]
      nr = split(rows, RL, "\n")
      for (i = 1; i <= nr; i++) {
        line = RL[i]; if (line == "") continue
        sp = index(line, " ")
        rid = (sp == 0) ? line : substr(line, 1, sp - 1)
        rest = (sp == 0) ? "" : substr(line, sp + 1)
        st = ""
        nt = split(rest, TOK, " ")
        for (j = 1; j <= nt; j++) if (substr(TOK[j], 1, 6) == "state=") st = substr(TOK[j], 7)
        ROWSEEN[rid] = 1; ROWSTATE[rid] = st
      }
      ownstatelisted = 0
      nl = split(lists, LL, "\n")
      for (i = 1; i <= nl; i++) {
        line = LL[i]; if (line == "") continue
        sp = index(line, " ")
        lst = (sp == 0) ? line : substr(line, 1, sp - 1)
        ids = (sp == 0) ? "" : substr(line, sp + 1)
        if (lst == subjstate) ownstatelisted = 1
        ni = split(ids, IDS, " ")
        for (j = 1; j <= ni; j++) {
          id = IDS[j]; if (id == "") continue
          if (!idok(id)) { print "grammar"; exit }
          if (!(id in ROWSEEN)) { print "norow"; exit }
          if (ROWSTATE[id] != lst) { print "statemismatch"; exit }
          LISTED[id] = 1
        }
      }
      if (subjrow != "" && ownstatelisted && !(subj in LISTED)) { print "iff"; exit }
      for (rid in ROWSEEN) {
        if (rid == subj) continue
        if (!(rid in LISTED)) { print "unlisted"; exit }
      }
      print "ok"
    }
  '
}

# _seam_record_bijection -> rc0 iff the §3b bijection holds over the already-captured _SRV_ROWS/
# _SRV_LISTS (T6b, called ONCE after the line loop — never grows _seam_record_load_parse itself).
# Leg 9 (F-5): `requested` matches the conf's project id grammar (every OTHER id's grammar is
# checked inside _seam_bijection_scan, above). See that function's docstring for the full rule set.
_seam_record_bijection() {
  _srb_project=$(sh "$_srv_confsh" get project "$_srv_baseconf" 2>/dev/null) || _srb_project=""
  [ -n "$_srb_project" ] || { echo "seam: could not resolve the project from the base conf for the F-5 grammar check — refused" >&2; return 2; }
  _seam_id_matches_project "$_SRV_REQUESTED" \
    || { echo "seam: the requested id fails the project id grammar — refused (F-5)" >&2; return 2; }
  _srb_verdict=$(_seam_bijection_scan)
  # fix1 M6: name WHICH rule refused (fixed text, no record bytes) — restores the per-rule
  # sentences the single-pass rewrite had collapsed to one generic line.
  case "$_srb_verdict" in
    ok) return 0 ;;
    grammar) echo "seam: a listed id fails the project id grammar — refused (F-5)" >&2; return 2 ;;
    norow) echo "seam: a listed id names no row line — refused (bijection)" >&2; return 2 ;;
    statemismatch) echo "seam: a row's state disagrees with the list it is listed under — refused (bijection)" >&2; return 2 ;;
    iff) echo "seam: the subject's own state was listed but the subject id is absent from it — refused (bijection)" >&2; return 2 ;;
    unlisted) echo "seam: a non-subject row appears in no list — refused (bijection)" >&2; return 2 ;;
    *) echo "seam: the record fails the §3b bijection — refused" >&2; return 2 ;;
  esac
}

# _seam_tracker_row_flag <id> <flag> -> the TRACKER ARM of seam_row_flag (design §3d,
# TBG-READER-FLAGS-LIST T7). Looks up ANY id across the multi-row structure the parser already
# validated — NEVER the `requested == caller-id` check `_seam_tracker_answer` carries (that check
# is for the subject-keyed arms only, `seam_row_count`/`seam_row_state`; §3d states plainly this
# arm does not need, and does not get, it). rc0 with the value on stdout, rc2 UNVERIFIED (load
# failed, verdict not bound, or the row carries no such flag — M-5, never `n/a`).
_seam_tracker_row_flag() {
  _strf_id="$1"; _strf_flag="$2"
  # The closed §4.2 flag set — checked BEFORE ever loading the record (mirrors the `md` arm's own
  # unconditional-of-the-board rc1 for an unimplemented flag): an unrecognised flag name is always
  # refused, whatever the record says.
  case "$_strf_flag" in
    claimed|dor-acceptance|dor-metric|dor-size|dor-risk|outcome-recorded|blocked-by-open|pr-bound|mine) ;;
    *) return 1 ;;
  esac
  # T89s item3: leg11 is pinned by THIS load-rc check (or the wrapper's clear of the _SRV_*
  # globals on failure) — not the verdict gate on the next line.
  _seam_record_load || return 2
  [ "$_SRV_VERDICT" = "bound" ] || return 2
  # fix1 R1: the id lookup and its absent -> rc2 check run BEFORE any flag special-case (pr-bound
  # included, per the ruling's "applies to EVERY flag"). A tracker record is a partial read (the
  # subject + the listed ids), so an id it never mentions means "not read" (rc2 UNVERIFIED) — rc1
  # stays reserved for grammar/mapping refusals (the unknown-flag-name case above).
  _seam_row_token_lookup "$_strf_id" "$_strf_flag"
  [ "$_SRT_FOUND_ID" -eq 1 ] || return 2
  # §4.2/§3f: on a tracker, `pr-bound` is always answered from the PR's own `Kit-Row` trailer, not
  # a record lookup — `backlog-presence` uses state+claimed instead (F-1). Gated on load+bound+
  # found-id exactly like every other flag (never answered on an unverified OR absent-id read).
  if [ "$_strf_flag" = "pr-bound" ]; then
    printf 'n/a\n'
    return 0
  fi
  # fix1 R2: `mine` is explicit here, never a fall-through to the generic value lookup below —
  # §4.2 "local only — CI never knows who 'me' is", so it always refuses (rc2) fail-closed,
  # whatever the record's own tokens might otherwise suggest (a gate reading `n/a` on an
  # ownership check could pass open).
  if [ "$_strf_flag" = "mine" ]; then
    echo "seam: 'mine' is local only — CI never knows who 'me' is — refusing (rc2)" >&2
    return 2
  fi
  [ -n "$_SRT_VALUE" ] || return 2
  printf '%s\n' "$_SRT_VALUE"
  return 0
}

# _seam_tracker_rows_in_state <state> -> the TRACKER ARM of seam_rows_in_state (design §3d/H-3,
# TBG-READER-FLAGS-LIST T7). rc1 for a state outside the closed §4.1 vocabulary, checked BEFORE
# ever loading the record (mirrors the `md` arm's own unconditional-of-the-board rc1). rc2
# UNVERIFIED for an absent `list <state>` line (H-3: indistinguishable from "present, zero ids" is
# the exact fail-open the design forbids) or an unbound/unsound record. rc0 with empty stdout is
# legal ONLY for a PRESENT list line carrying zero ids — the one §4.2 carve-out.
_seam_tracker_rows_in_state() {
  _stris_state="$1"
  # T89s item1 (T7 seat L-2): an EXACT per-token case, not a substring test — the old
  # `*" $state "*` membership let a caller-supplied compound arg (`ready in-progress`, one quoted
  # arg) read as a literal substring of the space-joined vocabulary and bypass this gate.
  case "$_stris_state" in
    backlog|ready|in-progress|in-review|released|done|blocked|cancelled) ;;
    *) return 1 ;;
  esac
  # T89s item3: leg11 is pinned by THIS load-rc check (or the wrapper's clear of the _SRV_*
  # globals on failure) — not the verdict gate on the next line.
  _seam_record_load || return 2
  [ "$_SRV_VERDICT" = "bound" ] || return 2
  _stris_found=0
  while IFS= read -r _stris_l; do
    [ -n "$_stris_l" ] || continue
    _stris_lst=${_stris_l%% *}
    [ "$_stris_lst" = "$_stris_state" ] || continue
    _stris_found=1
    _stris_ids=${_stris_l#* }
    [ "$_stris_ids" = "$_stris_l" ] && _stris_ids=""
    for _stris_id in $_stris_ids; do
      printf '%s\n' "$_stris_id"
    done
  done <<EOF
$_SRV_LISTS
EOF
  [ "$_stris_found" -eq 1 ] || return 2
  return 0
}

# seam_row_count_tracker / seam_row_state_tracker — the ARMS seam_row_count/seam_row_state dispatch
# to below. Both REQUIRE $_SRV_REQUESTED to equal the caller's own id argument (the seam re-checks
# this independently of the record's own internal requested==row agreement — hostile-input rule A4:
# never trust a record's self-consistency alone as proof it answers THIS caller's question).
_seam_tracker_answer() {   # $1 = id -> rc0 with globals set, rc2 refused
  _sta_id="$1"
  _seam_record_load || return 2
  if [ "$_SRV_REQUESTED" != "$_sta_id" ]; then
    echo "seam: record's requested id does not match the caller's argument — refusing" >&2
    return 2
  fi
  return 0
}

# seam_row_count <id> -> 0 / 1 / n (§4.2). `md` arm: the single-pass scan's hit count —
# behaviourally identical to row_count over $SEAM_ROOT/BACKLOG.md (same sections, same order, same
# header/separator skip, same string-equal match). A missing board answers 0 (no board -> no rows
# can resolve) rather than refusing — callers that need to distinguish "no board" from "board
# exists, id absent" already guard the file's existence themselves before reaching for a row
# (loop-state's check_row does exactly this).
seam_row_count() {
  _seam_root_ok || return 2
  case "$(resolve_backend "$SEAM_ROOT")" in
    md|''|unrecognized:*)
      _seam_scan "$1"
      printf '%s\n' "$_seam_scan_hits"
      return 0 ;;
  esac
  # TRACKER ARM (TBG-RECORD-GATES-BIND, design §2 scope B). A record that fails ANY consistency
  # check answers rc2 UNVERIFIED — never a "0" (a real "no such row" answer would be
  # indistinguishable from a broken/stale/hostile read, which is exactly the silent-answer defect
  # the design's honest ceiling forbids). `verdict unverified` on an otherwise-sound record is the
  # SAME rc2 for the same reason.
  _seam_tracker_answer "$1" || return 2
  if [ "$_SRV_VERDICT" != "bound" ]; then
    echo "seam: record verdict is unverified — refusing (no silent 0/absent answer on an unbound read)" >&2
    return 2
  fi
  printf '1\n'
  return 0
}

# seam_row_state <id> -> one §4.1 token (§4.1 closed set), rc 0; rc 1 when the id resolves to no
# row (absent board, unmapped id, or the id sits on more than one row — state is undefined for an
# ambiguous id). `md` arm: the section heading the row's Item cell resolves in, mapped to its §4.1
# token verbatim (§1 of the confirming design): Ready->ready, In Progress->in-progress, In
# Review->in-review, Blocked->blocked, Released->released, Done->done, "Backlog (unrefined)"->backlog.
# `cancelled` is in the vocabulary (§4.1) but this arm NEVER returns it — `md` expresses cancellation
# by striking a row, which carries no section of its own.
seam_row_state() {
  _seam_root_ok || return 2
  case "$(resolve_backend "$SEAM_ROOT")" in
    md|''|unrecognized:*)
      _seam_scan "$1"
      [ "$_seam_scan_hits" = 1 ] || return 1   # absent or ambiguous -> refused
      case "$_seam_scan_sec" in
        Ready)                    printf 'ready\n' ;;
        "In Progress")            printf 'in-progress\n' ;;
        "In Review")               printf 'in-review\n' ;;
        Blocked)                   printf 'blocked\n' ;;
        Released)                  printf 'released\n' ;;
        Done)                      printf 'done\n' ;;
        "Backlog (unrefined)")     printf 'backlog\n' ;;
      esac
      return 0 ;;
  esac
  # TRACKER ARM — see seam_row_count's header for the rc2-not-0 rationale (unverified is unverified,
  # never silently folded into "absent").
  _seam_tracker_answer "$1" || return 2
  [ "$_SRV_VERDICT" = "bound" ] || return 2
  printf '%s\n' "$_SRV_ROWSTATE"
  return 0
}

# seam_rows_in_state <state> -> ids, one per line (§4.2); rc 0 with EMPTY stdout is legal HERE
# ONLY (§4.2's one carve-out to "never a silent empty" — a state with no rows is not an error).
# rc 1 for a state outside the §4.1 closed set. `md` arm: `cancelled` has no section (§4.1) so it
# always answers empty, rc 0 — a real answer ("no row is cancelled on this board"), not a refusal.
seam_rows_in_state() {
  _seam_root_ok || return 2
  case "$(resolve_backend "$SEAM_ROOT")" in
    md|''|unrecognized:*) ;;
    *)
      _seam_tracker_rows_in_state "$1"
      return $? ;;
  esac
  _sris_state="$1"
  _sris_board="$SEAM_ROOT/BACKLOG.md"
  [ -f "$_sris_board" ] || return 1
  case "$_sris_state" in
    ready)        _sris_sec="Ready" ;;
    in-progress)  _sris_sec="In Progress" ;;
    in-review)    _sris_sec="In Review" ;;
    blocked)      _sris_sec="Blocked" ;;
    released)     _sris_sec="Released" ;;
    done)         _sris_sec="Done" ;;
    backlog)      _sris_sec="Backlog (unrefined)" ;;
    cancelled)    printf ''; return 0 ;;
    *)            return 1 ;;
  esac
  _sris_rows=$(section_rows "$_sris_board" "$_sris_sec")
  [ -n "$_sris_rows" ] || { printf ''; return 0; }
  _sris_n=0
  while IFS= read -r _sris_r; do
    _sris_n=$((_sris_n + 1))
    [ "$_sris_n" -eq 1 ] && continue
    is_sep_row "$_sris_r" && continue
    _sris_id=$(backtick_id "$(cell "$_sris_r" 1)")
    [ -n "$_sris_id" ] && printf '%s\n' "$_sris_id"
  done <<EOF
$_sris_rows
EOF
  return 0
}

# seam_row_flag <id> <flag> -> yes / no / n/a (§4.2); rc 0 bound, rc 1 refused (no board, id
# resolves to no row / is ambiguous, or <flag> is not implemented on the `md` arm yet — F1: "ship
# only the flags the three gates ask for"). `md` arm: the cell the routed gate reads today. `pr-bound`
# is the one flag a routed gate (backlog-presence) can ask for this wave — is the row's named `PR`
# column non-empty. Answers `n/a` when the row's section carries no `PR` column at all (e.g. Done).
#
# `dor-metric` (TBG-SEAM-MD-ARM WAVE 2): backlog-current's Ready-edge DoR gate (BOARD-DOR-FIELDS)
# on ONE cell — the Success-metric column. `no` iff the cell is empty/placeholder (a blank, a bare
# `-`/`—`/`n/a`/`tbd`/`none`/`?` marker, or the `N/A — <reason>` idiom), else `yes`; `n/a` when the
# row's section carries no `Success metric / hypothesis` column at all. The column NAME and the
# emptiness regexes below are a DELIBERATE, literal DUPLICATE of backlog-current.sh's
# `READY_METRIC_COL` / `is_bare_na` / `is_na_reason` — never a call INTO backlog-current.sh, and
# never a caller-set variable read here, the same reason `pr-bound` hardcodes `"PR"` rather than
# taking a column-name argument: this file is sourced by callers (`backlog-presence.sh`) that do
# not define backlog-current.sh's helpers or constants, so a flag's `md`-arm semantics must be
# entirely self-contained. Keeping the two definitions in sync is a discipline, not a cross-file
# call — the same trade-off backlog-current.sh's own header (line ~299) already accepts for
# READY_METRIC_COL vs the board it grades ("declared HERE, OUTSIDE the board it grades, and NOT
# derived from it").
seam_row_flag() {
  _seam_root_ok || return 2
  _srf_id="$1"; _srf_flag="$2"
  case "$(resolve_backend "$SEAM_ROOT")" in
    md|''|unrecognized:*) ;;
    *)
      _seam_tracker_row_flag "$_srf_id" "$_srf_flag"
      return $? ;;
  esac
  _seam_scan "$_srf_id"
  [ "$_seam_scan_hits" = 1 ] || return 1
  _srf_row="$_seam_scan_row"; _srf_hdr="$_seam_scan_hdr"
  case "$_srf_flag" in
    pr-bound)
      _srf_idx=$(col_index "$_srf_hdr" "PR")
      if [ -z "$_srf_idx" ]; then printf 'n/a\n'; return 0; fi
      _srf_v=$(cell "$_srf_row" "$_srf_idx")
      if [ -n "$_srf_v" ]; then printf 'yes\n'; else printf 'no\n'; fi
      return 0 ;;
    dor-metric)
      _srf_idx=$(col_index "$_srf_hdr" "Success metric / hypothesis")
      if [ -z "$_srf_idx" ]; then printf 'n/a\n'; return 0; fi
      _srf_v=$(cell "$_srf_row" "$_srf_idx")
      # WAVE 3: calls the ONE definition (moved here from backlog-current.sh, above) rather than
      # a second, inline copy of the same predicate — the exact drift this library exists to stop.
      if is_bare_na "$_srf_v" || is_na_reason "$_srf_v"; then
        printf 'no\n'
      else
        printf 'yes\n'
      fi
      return 0 ;;
    *)
      return 1 ;;
  esac
}
