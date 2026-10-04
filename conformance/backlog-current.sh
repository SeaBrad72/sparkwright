#!/bin/sh
# backlog-current.sh — KW6-A conformance lock (T1 routing + T2 board checks).
# Resolves a project's declared backlog backend (from its own CLAUDE.md), N/As the
# not-applicable routes, and — for a repo-native BACKLOG.md that is in use — asserts the
# state-table item-traceability the loop depends on: Ready -> Success metric / hypothesis,
# In Progress -> Links, In Review -> PR,
# (only if the OPTIONAL section is present) Blocked -> Blocked on + Since, and (Done-edge, HITL-3)
# a Done row FLAGGED [taste-surface] -> a UAT-SIGNOFF reference. It also asserts column ARITY
# (BOARD-ROW-ARITY): every non-spacer body row carries exactly as many columns as its own section
# header declares, so an unescaped '|' inside a cell cannot silently shift a row's metadata.
#
#   sh conformance/backlog-current.sh [project-dir]   (default: .)
#   sh conformance/backlog-current.sh --selftest
# What it changes: read-only — inspects a project's CLAUDE.md / BACKLOG.md; mutates nothing.
# Guardrails: read-only; no network, no writes; N/A-by-default routing so a not-applicable
#   project is never a false FAIL (protects the incept first-run-green invariant).
# HONEST CEILING: a green run proves the backend was RESOLVED, correctly ROUTED, and (for an
#   in-use BACKLOG.md) that its Ready / In Progress / In Review / Blocked rows carry the required
#   traceability — NOT that those links resolve, that the board is current, that PRs actually
#   merged, or that a blocked item's age is acceptable. Necessary, not sufficient. The Ready gate
#   in particular proves a Success metric is POPULATED, never that it is TRUE or measurable —
#   that judgment is the review seat's, and a prose scanner for "measurable" is not attempted.
#   Gated columns
#   are resolved BY NAME (Ready→'Success metric / hypothesis', In Progress→Links, In Review→PR,
#   Blocked→'Blocked on'+'Since'). A gated
#   section whose gated column is ABSENT (renamed) is a SCHEMA VIOLATION and FAILs — the template
#   schema is the contract, and a renamed column must never silently disable the gate. The success
#   line reports the column(s) it RESOLVED and the number of rows it EVALUATED per section, so
#   "0 rows" and "column missing" cannot look alike. An EMPTY gated section may be expressed
#   two ways — a zero-row schema table (the canonical form) OR a bare `None.`/blank body (0
#   items, nothing to trace); both ACCEPT. Any OTHER content without the schema table FAILs
#   (anti-bypass: an item must never exist without its traceability column). Failures across
#   all gated sections are reported in ONE pass, not one-at-a-time.
#   BLOCKED is deliberately shaped: it is gated ONLY IF the section is present (Ready/In Progress/
#   In Review are required headings; Blocked is not — a board may omit it, and a blocked item then
#   cannot exist). It is NOT gated on a work-link — demanding "where is the work?" of an item that
#   by definition cannot proceed is a category error that would invite fake links. 'Event-retro
#   link' is NOT gated (conditional on an event-retro having occurred). 'Since' is checked ONLY
#   for non-emptiness so rot is VISIBLE: there is NO date/age arithmetic anywhere — staleness is
#   surfaced, never adjudicated (failing on "blocked > N days" is time-dependent, non-deterministic
#   in CI, and a Go/No-Go policy call).
#   ARITY's ceiling: it proves a row has the RIGHT NUMBER of columns, never that the right CONTENT
#   is in them — and it counts GFM delimiters (an escaped `\|` renders as a literal and is excluded),
#   so it does NOT detect that the shared cell() still splits on raw pipes. That parser gap is
#   BOARD-PIPE-ESCAPE, boarded separately; retro_cell() is HITL-6's local workaround for it.
set -eu
# Shared board-parser primitives (resolve_backend, is_pure_template, section_rows, cell,
# col_index, is_sep_row) live in backlog-lib.sh so this check and backlog-presence.sh consume
# ONE definition of "the board" — two parsers would drift, invisibly to both of their tests
# (KW6-A2 T1.1). Sourced $0-relative so it resolves regardless of the caller's cwd.
. "$(dirname "$0")/backlog-lib.sh"

# header_cols <header-row> : the non-empty column names, comma-joined, for a diagnostic that
# names what WAS found when a required column is absent (never a bare "not found").
# BOARD-PIPE-ESCAPE T2 — routed through the shared GFM-exact parser (gfm_nf + cell), NOT an
# independent `awk -F'|'` split: an escaped pipe in a header cell used to shift every later
# column name (L-7). gfm_nf's column count is already GFM-exact-index-aligned with cell(), so
# walking 1..N and reading each column by index is the same rule cell()/col_index() use.
header_cols() {
  _hc_n=$(gfm_nf "$1")
  _hc_out=""
  _hc_i=1
  while [ "$_hc_i" -le "$_hc_n" ]; do
    _hc_v=$(cell "$1" "$_hc_i")
    [ -n "$_hc_v" ] && _hc_out="${_hc_out:+$_hc_out, }$_hc_v"
    _hc_i=$((_hc_i + 1))
  done
  printf '%s' "$_hc_out"
}
# is_bare_na / is_na_reason — TBG-SEAM-MD-ARM WAVE 3: MOVED to backlog-lib.sh, byte-unchanged
# apart from that file's header, for the SAME reason retro_cell/row_count/backtick_id moved there
# (KW6-A2 T1.1 / BOARD-ROW-IDENTIFIER): seam_row_flag's `dor-metric` arm now grades the Ready
# Success-metric cell with the SAME predicate this file's other gated cells use — a second copy of
# that LOGIC (as opposed to a constant like READY_METRIC_COL) is exactly the drift backlog-lib.sh
# exists to prevent. Both names are called below exactly as before; they now resolve from the
# sourced library at :51.

# _cell_diag <cell> : a board-author-controlled cell rendered safe to print in a diagnostic —
# control bytes stripped and length-bounded. Board cells are untrusted bytes that reach a
# terminal (and a CI log), so an ANSI/CSI sequence pasted into a cell could otherwise rewrite the
# verdict a human reads. The security-waiver CONDITION for this slice (design §"Obligations"):
# every new FAIL message that echoes cell content goes through here. `LC_ALL=C` on the `tr` is
# load-bearing — bytewise deletion of 0x00-0x1F/0x7F leaves UTF-8 continuation bytes (0x80-0xBF)
# untouched, so an em-dash or an emoji in a row title survives intact; the `cut` is left in the
# ambient locale so it bounds CHARACTERS and cannot split a multibyte sequence.
# Precedent: promotion-readiness.sh:344-345, branch-protection.sh:170.
# THE BOUND ANNOUNCES ITSELF (CHECK-SECTION-RAW-ECHOES). A silent 80-character cut is a second
# falsification surface on top of the one this function closes: a crafted 500-character cell whose
# first 80 characters read as a DIFFERENT, entirely plausible row id renders indistinguishable from
# a complete value, and the operator acts on the wrong row. So the cut appends a marker. The marker
# describes the CUT ONLY — stripping control bytes never sets it (a stripped cell is still the whole
# cell), which is why the comparison is made AFTER the strip and not against the raw input.
_cell_diag() {
  _cd_s=$(printf '%s' "$1" | LC_ALL=C tr -d '[:cntrl:]')
  _cd_c=$(printf '%s' "$_cd_s" | cut -c1-80)
  # ⚠️ BRACES ARE LOAD-BEARING: `$_cd_c…` makes the shell read the multibyte `…` as part of the
  # NAME and dies with "unbound variable" under `set -u` (measured here, not theorised).
  [ "$_cd_c" = "$_cd_s" ] || _cd_c="${_cd_c}…[truncated]"
  printf '%s' "$_cd_c"
}

# _header_cols_diag <header-row> : header_cols, but with the sanitizer's bound applied PER COLUMN
# NAME rather than to the JOINED list. Bounding the join is the wrong bound and was a real defect:
# a board with many SHORT columns had its diagnostic cut after the third or fourth name, so the
# operator was told "columns present: A, B, C…[truncated]" and never learned which column they had
# actually misspelled — while the hostile input the bound exists for (ONE enormous cell) is exactly
# what it should still be cutting. The hostile unit is the CELL, so the bound belongs on the cell.
# BUT THE LIST NEEDS A BOUND OF ITS OWN, ON COUNT RATHER THAN LENGTH. Moving the character bound onto
# the cell removed every limit on the NUMBER of names, and a 300-column probe row produced a single
# 4,939-byte FAIL line — unreadable, and a log-flooding surface a board author controls. So the list
# is capped at the first 20 names and then SAYS how many it withheld: an operator scanning for their
# misspelled column still sees the realistic cases (no honest board has 20 columns), and the count
# tells them the diagnostic is partial instead of letting them assume it is complete — the same
# announce-the-cut rule `_cell_diag` follows one level down.
# ⚠️ HONEST CEILING — THIS CAP AND ITS ANNOUNCEMENT ARE UNCOVERED BY THE SELFTEST. Measured, both
# faces: deleting the `...(+N more)` announcement AND deleting the cap test itself each leave the
# whole battery GREEN (rc 0, zero FAILs). So the two lines below are asserted by nothing — exactly
# the drifted-green shape the rest of this file exists to prevent, and it is disclosed rather than
# left for the next reader to discover. WHY: the cap landed in a review fix round with the fixture
# budget at 4 free lines, and an honest leg (a wide-header fixture plus positive/negative faces)
# costs ~6-8 fixture lines — i.e. a fresh owner ack, which a residual of this size does not justify
# spending mid-review. Follow-up row `HEADER-CAP-ANNOUNCE-LEG` is boarded. Until it lands, treat
# this block as unproven: if you change it, re-measure the 300-column probe by hand.
# BOARD-PIPE-ESCAPE T2 — routed through the shared GFM-exact parser (gfm_nf + cell), same rule
# as header_cols above, but sanitizing PER COLUMN NAME (_cell_diag) and capping the COUNT
# (_HEADER_COLS_MAX) rather than the joined string — see the header comment on the cap's honest
# ceiling. Variable names are `_hcd_`-prefixed (distinct from header_cols' `_hc_`) — this file is
# POSIX sh with no `local`, and the two functions must never be able to clobber each other's state.
_HEADER_COLS_MAX=20
_header_cols_diag() {
  _hcd_n=$(gfm_nf "$1")
  _hcd_out=""; _hcd_seen=0; _hcd_extra=0
  _hcd_i=1
  while [ "$_hcd_i" -le "$_hcd_n" ]; do
    _hcd_v=$(cell "$1" "$_hcd_i")
    if [ -n "$_hcd_v" ]; then
      _hcd_seen=$((_hcd_seen + 1))
      if [ "$_hcd_seen" -gt "$_HEADER_COLS_MAX" ]; then
        _hcd_extra=$((_hcd_extra + 1))
      else
        _hcd_out="${_hcd_out:+$_hcd_out, }$(_cell_diag "$_hcd_v")"
      fi
    fi
    _hcd_i=$((_hcd_i + 1))
  done
  if [ "$_hcd_extra" -gt 0 ]; then _hcd_out="${_hcd_out} ...(+${_hcd_extra} more)"; fi
  printf '%s' "$_hcd_out"
}

# is_empty_marker <trimmed-line> : rc0 iff the line is a bare `None.` empty-section idiom,
# WHOLE-LINE anchored (R3): a `case` exact-match, so an item literally named "None of the
# above" is NOT a marker — the anchoring is what keeps empty-acceptance from opening a hole.
is_empty_marker() {
  case "$1" in None.|None|none.|none|_None._|_None_|_none._|_none_) return 0 ;; *) return 1 ;; esac
}
# section_is_empty <file> <section> : rc0 iff the section body (between `## <section>` and the
# next `## ` heading) carries NO Markdown table AND every non-blank line is an empty-marker.
# Used ONLY when the section has no gated column resolved AND no table rows at all, so a bare
# `None.`/blank section is accepted (0 items -> nothing to trace) while any other content
# (item-like lines, prose) still demands the schema table (anti-bypass, spec §2 row 3). A
# here-doc feeds the loop (NOT a `| while` pipeline — that runs in a subshell and would lose
# _er, the trap backlog-presence.sh:95 warns of).
section_is_empty() {
  # EXACT heading match — no dynamic awk regex built from the arg (hardens against a future
  # caller passing a section name with regex metacharacters); trailing whitespace on the
  # heading is tolerated, mirroring check_dir's `^## H[[:space:]]*$`.
  _shead="## $2"
  _body=$(awk -v s="$_shead" '
    { line=$0; sub(/[ \t]+$/, "", line) }
    line==s {f=1; next}
    f && /^## / {f=0}
    f {print}
  ' "$1")
  _er=0
  while IFS= read -r _l; do
    _t=${_l#"${_l%%[! ]*}"}; _t=${_t%"${_t##*[! ]}"}  # trim leading/trailing spaces
    [ -z "$_t" ] && continue                          # blank line -> ignore
    # A table row (`| … |`), prose, or any item-like line is a non-marker -> content, NOT empty
    # (anti-bypass, spec §2 row 3). The marker-loop alone rejects every non-empty-marker line,
    # so no separate table/pipe pre-check is needed (a `*'|'*` guard here was fully shadowed).
    is_empty_marker "$_t" || { _er=1; break; }
  done <<EOF
$_body
EOF
  return $_er
}

# check_section <file> <section> <gated-column-name> <mode: progress|review>
# Evaluates the section's gated cell for every non-spacer body row. Increments the globals
# SPACER_SKIPS (Item-empty rows) and NA_ESCAPES (In Progress `N/A — reason`), and appends the
# resolved column + rows-evaluated to BOARD_TRACE. rc0 = pass.
# SCHEMA VIOLATION -> FAIL: a GATED section (this function is only called for gated ones)
# whose gated column is ABSENT is a schema violation, NOT a skip. A renamed column must never
# silently disable the gate (the reproduced defect). No fallback-column guessing.
check_section() {
  _f="$1"; _sec="$2"; _col="$3"; _mode="$4"; _col2="${5:-}"
  _rows=$(section_rows "$_f" "$_sec")
  _hdr=$(printf '%s\n' "$_rows" | head -1)
  _ci=""
  [ -n "$_rows" ] && _ci=$(col_index "$_hdr" "$_col")
  if [ -z "$_ci" ]; then
    # No gated column resolved. Two very different cases, distinguished by whether a table
    # exists at all (spec §2): a section with NO table may be a legitimately EMPTY gated
    # section (`None.`/blank -> 0 items, nothing to trace -> ACCEPT); a section WITH a table
    # whose gated column is absent is a schema violation (a renamed column must never silently
    # disable the gate). Content-without-table is the anti-bypass FAIL: an item must never
    # exist without its traceability column.
    if [ -z "$_rows" ]; then                       # no table at all
      if section_is_empty "$_f" "$_sec"; then
        _coltrace="$_col"; [ "$_mode" = "blocked" ] && _coltrace="${_col}+${_col2}"
        BOARD_TRACE="${BOARD_TRACE:+$BOARD_TRACE, }${_sec}→${_coltrace} (0 rows, empty)"
        return 0
      fi
      echo "FAIL: $_sec — expected a schema table with the '$_col' column (zero rows is fine, or write 'None.' if the section is empty); found content but no table"
      return 1
    fi
    _found=$(_header_cols_diag "$_hdr")                  # a table exists but the gated column is renamed/absent
    echo "FAIL: $_sec — required column '$_col' not found (columns present: ${_found:-none}); a renamed/absent gated column is a schema violation, not a skip"
    return 1
  fi
  # 'blocked' gates a SECOND column ('Since'). Absent -> the same schema violation (a renamed
  # 'Blocked on'/'Since' must never silently disable the gate), never a fallback-column guess.
  _ci2=""
  if [ "$_mode" = "blocked" ]; then
    [ -n "$_rows" ] && _ci2=$(col_index "$_hdr" "$_col2")
    if [ -z "$_ci2" ]; then
      _found=$(_header_cols_diag "$_hdr")
      echo "FAIL: $_sec — required column '$_col2' not found (columns present: ${_found:-none}); a renamed/absent gated column is a schema violation, not a skip"
      return 1
    fi
  fi
  _ln=0; _eval=0
  while IFS= read -r _row; do
    _ln=$((_ln + 1))
    if [ "$_ln" -eq 1 ]; then continue; fi        # header row
    if is_sep_row "$_row"; then continue; fi       # separator row (has a dash)
    _item=$(cell "$_row" 1)
    if [ -z "$_item" ]; then
      SPACER_SKIPS=$((SPACER_SKIPS + 1))           # template 'no items' spacer row
      continue
    fi
    _eval=$((_eval + 1))                           # a gated row actually evaluated
    if [ "$_mode" = "review" ]; then
      # In Review -> PR: a real value ONLY. A blank AND an `N/A — reason` both FAIL
      # (you cannot be in review without a PR).
      _g=$(cell "$_row" "$_ci")
      if is_bare_na "$_g" || is_na_reason "$_g"; then
        echo "FAIL: $_sec item '$(_cell_diag "$_item")' — $_col must be a real PR link (got '$(_cell_diag "$_g")'); a blank or 'N/A — reason' is not review-ready"
        return 1
      fi
    elif [ "$_mode" = "blocked" ]; then
      # Blocked -> 'Blocked on' AND 'Since': each answers "what blocks it, and since when?".
      # Same accept-rule as In Progress (a real value OR an `N/A — reason`; bare/empty FAILs) —
      # a work-link is deliberately NOT demanded here (work cannot proceed; that would invite
      # fake links). 'Since' is gated ONLY for non-emptiness so rot is VISIBLE — NO date/age
      # arithmetic: staleness is surfaced, never adjudicated (a Go/No-Go policy call).
      _g=$(cell "$_row" "$_ci")                    # 'Blocked on'
      if is_bare_na "$_g"; then
        echo "FAIL: $_sec item '$(_cell_diag "$_item")' — $_col is empty/bare ('$(_cell_diag "$_g")'); name the blocker or use the 'N/A — <reason>' idiom"
        return 1
      fi
      if is_na_reason "$_g"; then BLOCKED_NA_ESCAPES=$((BLOCKED_NA_ESCAPES + 1)); fi
      _s=$(cell "$_row" "$_ci2")                   # 'Since'
      if is_bare_na "$_s"; then
        echo "FAIL: $_sec item '$(_cell_diag "$_item")' — $_col2 is empty/bare ('$(_cell_diag "$_s")'); record when it blocked so staleness is visible, or use the 'N/A — <reason>' idiom"
        return 1
      fi
      if is_na_reason "$_s"; then BLOCKED_NA_ESCAPES=$((BLOCKED_NA_ESCAPES + 1)); fi
    else
      # In Progress -> Links: a real value OR an `N/A — reason`. Bare/empty FAILs.
      _g=$(cell "$_row" "$_ci")
      if is_bare_na "$_g"; then
        echo "FAIL: $_sec item '$(_cell_diag "$_item")' — $_col is empty/bare ('$(_cell_diag "$_g")'); use a real link or the 'N/A — <reason>' idiom"
        return 1
      fi
      if is_na_reason "$_g"; then
        NA_ESCAPES=$((NA_ESCAPES + 1))
      fi
    fi
  done <<EOF
$_rows
EOF
  # Report what we RESOLVED and the count we EVALUATED — never a hardcoded expected schema.
  # '0 rows' (an empty board) is legitimate but must be visible, distinct from column-missing.
  _rw=rows; [ "$_eval" -eq 1 ] && _rw=row
  # Name every gated column resolved (both, for blocked). BRACED before the multibyte `→`:
  # an unbraced `$_sec→` can absorb `→`'s first byte on a byte-oriented sh under `set -u`.
  _coltrace="$_col"; [ "$_mode" = "blocked" ] && _coltrace="${_col}+${_col2}"
  BOARD_TRACE="${BOARD_TRACE:+$BOARD_TRACE, }${_sec}→${_coltrace} (${_eval} ${_rw})"
  return 0
}

# READY_METRIC_COL — the Definition-of-Ready Success-metric column, declared HERE, OUTSIDE the
# board it grades and NOT derived from it. Same oracle rule as the HITL-6 constants: a set built
# out of its own subject can always be satisfied by renaming the subject.
READY_METRIC_COL="Success metric / hypothesis"

# check_ready_metric <file> : Ready-edge Definition-of-Ready enforcement (BOARD-DOR-FIELDS,
# ruling D-240811-2.2). Every content-bearing Ready row must carry a NON-EMPTY
# 'Success metric / hypothesis' cell — the DoR's own mandatory field, which was previously
# graded for PRESENCE-of-the-heading only (dor-defined.sh:8, unchanged and disclosed).
#
# THE ACCEPT RULE IS THE IN-REVIEW ASYMMETRY, NOT THE IN-PROGRESS ONE: a real value ONLY. Both a
# bare/empty cell (is_bare_na) AND the `N/A — <reason>` idiom (is_na_reason) FAIL. Under the
# owner's demote-don't-fill ruling (2026-08-13) a row that cannot state how we will know it
# worked is BY DEFINITION not Ready — it demotes to Backlog (unrefined) with a dated note. An
# escape hatch here would rebuild the exact filler this gate exists to stop.
#
# COLUMN ABSENT -> FAIL when the table carries item rows, PASS when it carries none. The FAIL
# side follows this file's own recorded gated-column contract ("a renamed/absent gated column is
# a schema violation, not a skip"): a skip-when-absent arm would let any board disable the gate
# by deleting one header cell. The PASS side is the false-FAIL control — a board with nothing in
# Ready has nothing to measure, which keeps a brand-new adopter's first run green (and a pristine
# template N/As earlier still, at is_pure_template).
#
# THE SPACER SKIP IS THE TRUE-SPACER TEST (every cell empty), NOT the Item-empty test the older
# gates use. BOARD-ROW-ARITY already reproduced the Item-empty evasion once — a row that simply
# leaves Item blank was skipped and not even counted — so this gate does not re-import it: a row
# carrying content anywhere is graded and named by its first non-empty cell (_ra_label, which is
# deliberately variable-free and safe to call from any namespace).
#
# HONEST CEILING — THIS GATES *POPULATED*, NOT *TRUE*. A determined author can type "it will be
# better" and pass. Measurability is human judgment at review; a prose scanner for "is this
# measurable" is the kit's standing veto and is not attempted here. The control is the column
# plus the review seat, labelled as such (the Δ-B drift-control precedent). The exit side of the
# metric loop (`## Released` -> did it move?) stays UNGATED and is explicitly out of scope.
# Increments SPACER_SKIPS for true spacers; appends Ready to BOARD_TRACE. rc0 = pass.
# FIRST-FAIL IDIOM, and the counter is honest about it: this returns on the FIRST bad row, so any
# true spacer BELOW that row goes uncounted and `spacer-rows-skipped` under-reports on a failing
# board. That is consistent with check_section (same shape) and harmless — the counter is a
# non-vacuity witness for a PASSING run, not a census. Accumulate-all (K11) is honoured at the
# SECTION level by check_dir, which still runs every other gate in the same pass.
check_ready_metric() {
  _rm_f="$1"
  _rm_rows=$(section_rows "$_rm_f" "Ready")
  [ -n "$_rm_rows" ] || return 0                  # no Ready table at all -> nothing to grade
  _rm_hdr=$(printf '%s\n' "$_rm_rows" | head -1)
  _rm_ci=$(col_index "$_rm_hdr" "$READY_METRIC_COL")
  # TBG-SEAM-MD-ARM WAVE 2: SEAM_ROOT tracks this board's project dir (the same dirname convention
  # every other routed call site in this repo uses) so seam_row_flag below resolves the SAME board.
  SEAM_ROOT=$(dirname "$_rm_f")
  _rm_ln=0; _rm_eval=0
  while IFS= read -r _rm_row; do
    _rm_ln=$((_rm_ln + 1))
    if [ "$_rm_ln" -eq 1 ]; then continue; fi     # header row
    if is_sep_row "$_rm_row"; then continue; fi   # separator row (has a dash)
    _rm_item=$(_ra_label "$_rm_row")
    if [ -z "$_rm_item" ]; then
      SPACER_SKIPS=$((SPACER_SKIPS + 1))          # TRUE spacer: every cell empty
      continue
    fi
    _rm_eval=$((_rm_eval + 1))
    if [ -z "$_rm_ci" ]; then continue; fi        # column absent: count now, report ONCE below
    _rm_g=$(cell "$_rm_row" "$_rm_ci")
    # THE GATING DECISION routes through seam_row_flag's dor-metric arm (§4.2) — the ONE flag this
    # gate reads on md, and the seam's md arm reads the SAME column by name via the SAME
    # is_bare_na/is_na_reason predicate (WAVE 3: moved into backlog-lib.sh — ONE definition, called
    # from both here and the seam, not a duplicate).
    #
    # THE DUAL PATH, AND WHY IT EXISTS: this works ONLY for a row that resolves to exactly one
    # backticked id (§4.2's row identity). On THIS repo's real board, and under the shipped
    # convention (CLAUDE.md §1 act 3, "lead your row's Item cell with the backticked id"), that is
    # EVERY Ready row — so the seam is the PRODUCTION path today. A row that does NOT resolve — no
    # backtick in its Item cell, or the id collides with another row on the SAME board — falls back
    # to the DIRECT check below, UNCHANGED: a fail-safe for a malformed/legacy `md` row, never a
    # bypass, and it is exactly today's coverage for that row (the seam cannot identify a row the
    # board itself does not uniquely identify). NO SUCH FALLBACK EXISTS, OR IS NEEDED, ON A
    # TRACKER ARM: every tracker row has a key BY CONSTRUCTION (it is how the tracker addresses the
    # row at all), so the "no resolvable id" case this fallback covers is an `md`-only possibility,
    # born of the format having a schema-optional identifier rather than a mandatory one.
    _rm_id=$(backtick_id "$(cell "$_rm_row" 1)")
    _rm_bad=0
    # WAVE 4 (perf): no separate row_count pre-check here — seam_row_flag's own single-pass scan
    # ALREADY establishes uniqueness (its rc is 1 for absent-or-ambiguous, exactly what a
    # standalone `row_count == 1` guard would have gated on), so calling it twice per row was pure
    # waste, not a correctness need. Only the cheap, non-scanning `-n "$_rm_id"` check stays as a
    # front-door skip (never call the seam with an empty id).
    if [ -n "$_rm_id" ]; then
      _rm_flag=$(seam_row_flag "$_rm_id" dor-metric 2>/dev/null) && _rm_sfrc=0 || _rm_sfrc=$?
    else
      _rm_sfrc=1
    fi
    if [ "$_rm_sfrc" = 0 ] && { [ "$_rm_flag" = "yes" ] || [ "$_rm_flag" = "no" ]; }; then
      [ "$_rm_flag" = "no" ] && _rm_bad=1
    else
      # fail-safe: no resolvable id, or the seam refused/could not answer -> the direct read,
      # byte-identical to this gate's behaviour before the seam existed.
      { is_bare_na "$_rm_g" || is_na_reason "$_rm_g"; } && _rm_bad=1
    fi
    if [ "$_rm_bad" = 1 ]; then
      echo "FAIL: Ready item '$(_cell_diag "$_rm_item")' — $READY_METRIC_COL is empty/placeholder (got '$(_cell_diag "$_rm_g")'); a Ready item must state how we will know it worked. A blank, a bare marker and 'N/A — reason' all mean the same thing: not Ready — demote it to Backlog (unrefined) rather than filling this cell"
      return 1
    fi
  done <<EOF
$_rm_rows
EOF
  if [ -z "$_rm_ci" ]; then
    if [ "$_rm_eval" -gt 0 ]; then
      # HEADER CELLS ARE BOARD-AUTHOR BYTES TOO. `header_cols` returns the table's own column
      # names verbatim, so this diagnostic echoes untrusted content exactly like the per-row FAIL
      # below does — and it was MEASURED reaching stdout with two raw ESC bytes before this call
      # was added (an erase-line + cursor-up pasted into a header cell, which rewrites the line
      # above the verdict). Sanitize on the SAME helper: one definition of "safe to print".
      _rm_found=$(_header_cols_diag "$_rm_hdr")   # bound PER COLUMN, not on the join (see the helper)
      _rm_rw=rows; [ "$_rm_eval" -eq 1 ] && _rm_rw=row
      echo "FAIL: Ready — required column '$READY_METRIC_COL' not found (columns present: ${_rm_found:-none}) on a table carrying ${_rm_eval} item ${_rm_rw}; a renamed/absent gated column is a schema violation, not a skip. MIGRATION: add the '$READY_METRIC_COL' column to your Ready table — rows without an honest metric demote to your backlog rather than being filled in"
      return 1
    fi
    return 0                                      # nothing in Ready -> nothing to measure
  fi
  _rm_rw=rows; [ "$_rm_eval" -eq 1 ] && _rm_rw=row
  BOARD_TRACE="${BOARD_TRACE:+$BOARD_TRACE, }Ready→${READY_METRIC_COL} (${_rm_eval} ${_rm_rw})"
  return 0
}

# check_done_uat <file> : Done-edge UAT sign-off enforcement (HITL-3). A Done row FLAGGED as a
# taste-surface — carrying the inline `[taste-surface]` token anywhere in the row — MUST record a
# UAT sign-off: a resolvable `UAT-SIGNOFF` reference (a link or path token) somewhere in the row.
# This mirrors the In-Review PR idiom: it asserts the RECORD EXISTS (presence of a reference), NOT
# that the link resolves — demanding a resolved URL would only invite a fake link. An UNFLAGGED
# Done row is N/A: no UAT is required (not every Done item touches a taste-surface). Done is
# OPTIONAL and structurally UNGATED here (no column-schema enforcement) — the ONLY rule is
# flagged-row -> UAT reference. Increments DONE_UAT_FLAGGED (rows that carried the flag). rc0 = pass.
# HONEST CEILING: this enforces the RECORD on rows the builder FLAGGED; correct flagging is builder
# discipline, and HITL-2 (the PR-context gate) is the hard diff-level backstop that flags the surface.
check_done_uat() {
  _f="$1"
  _rows=$(section_rows "$_f" "Done")
  [ -n "$_rows" ] || return 0                     # no Done table at all -> nothing to enforce
  _ln=0
  while IFS= read -r _row; do
    _ln=$((_ln + 1))
    if [ "$_ln" -eq 1 ]; then continue; fi        # header row
    if is_sep_row "$_row"; then continue; fi       # separator row (has a dash)
    _item=$(cell "$_row" 1)
    if [ -z "$_item" ]; then continue; fi          # template 'no items' spacer row
    # The taste-surface flag: an inline `[taste-surface]` token anywhere in the row (quoted in the
    # case pattern so the brackets are LITERAL, not a character class). An unflagged Done row is
    # N/A -> skip; only a flagged row must carry the UAT record.
    case "$_row" in
      *'[taste-surface]'*) ;;
      *) continue ;;
    esac
    DONE_UAT_FLAGGED=$((DONE_UAT_FLAGGED + 1))
    # A flagged row MUST carry a UAT-SIGNOFF reference — presence of the reference token, NOT a
    # resolved URL (mirrors the In-Review PR idiom; presence-not-resolution is the fake-link guard).
    case "$_row" in
      *UAT-SIGNOFF*) ;;
      *)
        echo "FAIL: Done item '$(_cell_diag "$_item")' — flagged [taste-surface] but carries no UAT-SIGNOFF reference; a taste-surface reaching Done must record a UAT sign-off (a link or path to a UAT-SIGNOFF)"
        return 1
        ;;
    esac
  done <<EOF
$_rows
EOF
  return 0
}

# HITL-6 constants — declared HERE, OUTSIDE the board they grade, and deliberately NOT derived from
# BACKLOG.md. HITL-4 spent four review rounds establishing that an oracle built out of the thing
# under test goes blind to a whole class of defect (an unlisted glob, a renamed token, a mistyped
# glob each survived in turn); the only construct that held was a constant declared externally,
# which caught a wrong value on its first run. Do not replace these with anything computed.
HITL6_RETRO_EPOCH="2026-07-24"    # rows Closed on/after this date owe an explicit 'L1 retro' marker
HITL6_MIN_RETRO_CHARS=120         # substance floor. Measured 2026-07-24 across this kit's own 77
                                  # Done rows: min 200, median 1462 — a FLOOR, not a fit to the corpus.
HITL6_DISPO_MIN_REASON=20         # leg 3's `none — <reason>` floor, in NON-WHITESPACE characters —
                                  # counting raw length would let twenty spaces clear it (vet M2).
                                  # HITL6_DISPO_EPOCH itself lives in backlog-lib.sh: backlog-presence.sh
                                  # scopes its Done arm to the SAME population, and one constant read by
                                  # two gates cannot drift. Still declared externally, never derived
                                  # from the board (the HITL-4 rule).

# retro_cell (the escaped-pipe-robust Retro/outcome extractor) MOVED to backlog-lib.sh at
# SLICE-CLOSES-IN-ONE-PR, byte-unchanged, because backlog-presence.sh's Done arm now reads the
# SAME cell this gate grades. Its full rationale travelled with it; the library is sourced above.

# ── LEG 3 RESOLVERS (SLICE-CLOSES-IN-ONE-PR §4.3) ─────────────────────────────────────────────
# Both are STRING-EQUALITY / PREFIX matchers. NOTHING here interpolates a board-supplied id into a
# regex: a row id and a `D-` id are attacker-influenceable text (anyone can open a PR), and a
# `.*` id in an ERE would resolve against every object at once (threat T4). The only regexes are
# CONSTANT well-formedness patterns applied TO an id, never built FROM one.

# backtick_id and row_exists MOVED to backlog-lib.sh at BOARD-ROW-IDENTIFIER, together with the
# new `row_id_ok` (the grammar) and `row_count` (the counting form loop-state's `check_row` needs
# to tell "resolved" from "AMBIGUOUS"). They moved because a FOURTH mechanism now resolves a row
# through them, and a second copy under conformance/ would drift invisibly to both gates' tests —
# the same reason the rest of the board parser lives there. The library is sourced above; their
# full rationale travelled with them.

# ruling_recorded <DECISIONS.md path> <D-id> : rc0 iff a line STARTS with the entry-header form
# **`D-YYMMDD-N`. A CROSS-REFERENCE DOES NOT RESOLVE (vet H2) — measured on this repo's file:
# 44 entry headers against 108 backticked mentions, so "the id appears somewhere" would resolve
# against a sentence that merely cites a ruling. The needle is a shell PREFIX pattern in `case`,
# which is anchored at the line start and involves no regex at all.
# ⚠️ ORDERING IS LOAD-BEARING (review m4): the id is interpolated into a `case` GLOB, and a glob is
# not inert — an id of `*` would match EVERY line and resolve against any file. That is safe ONLY
# because the caller validates the id against `^D-[0-9]{6}-[0-9]+$` BEFORE calling, so no glob
# metacharacter can reach here. Moving this call above that validation re-opens the hole silently.
# Any future caller owes the same validation first.
ruling_recorded() {
  _rr_needle="**\`$2\`"
  while IFS= read -r _rr_line || [ -n "$_rr_line" ]; do
    case "$_rr_line" in "$_rr_needle"*) return 0 ;; esac
  done < "$1"
  return 1
}

# bc_warn <check-id> <text> : an ADVISORY finding — `WARN: <check-id>: <text>` on stderr (the kit's
# ci-gates.sh shape), never a failure: the caller returns 0 / does not touch the failure accumulator.
# Under GitHub Actions the same line is ALSO a `::warning::` annotation (stdout) so it shows on the PR
# where the approver looks — a stderr line in a green job is one nobody reads. <text> carries the
# pre-demotion wording and ends `— fix: <one line>`, so a grep for the old phrase still finds it.
# printf '%s\n', NEVER echo: CI's sh is dash, whose echo expands backslash escapes, so board text
# carrying a literal `\n::error::…` would become a REAL workflow command (security L-1). The
# annotation payload is also encoded per the workflow-command rules (% -> %25, CR -> %0D, LF -> %0A).
bc_warn() {
  printf '%s\n' "WARN: $1: $2" >&2
  [ "${GITHUB_ACTIONS-}" = true ] || return 0
  _bw_enc=$(printf '%s\n' "$2" | awk '{ gsub(/%/, "%25"); gsub(/\r/, "%0D"); s = s (NR > 1 ? "%0A" : "") $0 } END { print s }')
  printf '%s\n' "::warning::WARN: $1: $_bw_enc"
}

# _dispo_row_exists <board-file> <id> : row_exists's answer, from a one-pass id index (PREPUSH-CORE-DEFAULT).
# row_exists re-parses the whole board per call; the Done pass asks it once per Disposition `row`
# clause (~135x on the live board, ~5 min). The index (backlog-lib.sh::row_id_index) is built ONCE
# per board and held in a shell variable — no temp file, nothing written anywhere, nothing to clean.
# STALENESS: the cache key is the board PATH plus its `cksum` (content), so a different board, or the
# same path rewritten between calls (selftest fixtures do this), rebuilds; an unreadable board
# (empty cksum) is never cached, so it rebuilds each time exactly as row_exists would re-read it.
# Inside a $(...) the cache dies with the subshell — slower, never wrong.
_dispo_row_exists() {
  _dx_sig=$(cksum < "$1" 2>/dev/null) || _dx_sig=""
  if [ -z "$_dx_sig" ] || [ "${_dx_key-}" != "$1|$_dx_sig" ]; then
    _dx_idx=$(row_id_index "$1")
    _dx_key="$1|$_dx_sig"
  fi
  row_in_index "$_dx_idx" "$2"
}

# check_dispo <retro> <own-id> <board-file> <project-dir> <item-label> : leg 3 for ONE row. Emits
# the FAIL text (naming the row, the clause, and the remedy) and returns 1, or returns 0.
# GRAMMAR:  Disposition: row `ID` [, row `ID` …] | ruling `D-YYMMDD-N` [, …] | none — <reason>
# At least one clause is required and EVERY clause present must RESOLVE — "at least one" is a floor
# on COUNT, never a disjunction on TRUTH (vet H3), or an unresolved citation could ride along with
# a valid one. The LAST `Disposition:` occurring AFTER the 'L1 retro' marker is the one parsed: the
# word already appears in retro prose on the live board (1 hit), so an unanchored parse would grade
# the wrong text. A cell is one line under GFM, so the clause list runs to the end of the cell.
# ⚠️ DISCLOSED LIMIT — `none —` IS TERMINAL (review m2). Its reason runs to the end of the cell, so
# (a) any clause written AFTER a `none —` is not scanned and therefore not resolved, and (b) retro
# PROSE that happens to contain the literal "none — " after a valid clause is read as the reason and
# graded against the length floor, which can FALSE-RED an otherwise-good retro. (b) is the
# fail-CLOSED direction and its remedy — put the `Disposition:` line last, which the grammar wants
# anyway — is what the failure text says. Neither case lets an unresolved clause pass.
check_dispo() {
  _dp_retro="$1"; _dp_own="$2"; _dp_bl="$3"; _dp_dir="$4"; _dp_lab="$5"
  # $6 = "quiet": suppress the FORM warnings (the caller already WARNed about the missing marker)
  # while every SUBSTANCE failure below still FAILs — a dangling pointer is never excused by form.
  _dp_q="${6-}"
  _dp_rem="remedy: board the row, record the ruling, or write \`none — <reason>\`"
  case "$_dp_retro" in *"L1 retro"*) _dp_after=${_dp_retro#*L1 retro} ;; *) _dp_after="" ;; esac
  case "$_dp_after" in
    *"Disposition:"*) _dp_txt=${_dp_after##*Disposition:} ;;
    *)
      # FORM, not substance (RECORD-GRAMMAR-ESSENTIALS, owner GO): a missing clause is advisory.
      [ -n "$_dp_q" ] || bc_warn HITL-6-DISPO "Done item '$_dp_lab' — closed on/after $HITL6_DISPO_EPOCH but its retro carries no 'Disposition:' clause after the 'L1 retro' marker; a retro should say where its lessons went — fix: $_dp_rem"
      return 0 ;;
  esac
  _dp_n=0
  # The `none — <reason>` clause is TERMINAL (its reason runs to the end of the cell), so it is
  # split off FIRST and only the text before it is scanned for backticked clauses — otherwise a
  # backtick inside the reason would be read as a clause id.
  _dp_scan=$_dp_txt
  case "$_dp_txt" in
    *"none — "*)
      _dp_scan=${_dp_txt%%none — *}
      _dp_nw=$(printf '%s' "${_dp_txt##*none — }" | tr -d '[:space:]')
      if [ "${#_dp_nw}" -lt "$HITL6_DISPO_MIN_REASON" ]; then
        [ -n "$_dp_q" ] || bc_warn HITL-6-DISPO "Done item '$_dp_lab' — its Disposition's 'none —' reason is too thin (${#_dp_nw} non-whitespace chars, floor $HITL6_DISPO_MIN_REASON) — fix: say why this retro boards nothing and changes no rule"
        # No return: a thin reason is form, but any clause BEFORE the `none —` must still resolve —
        # returning here would let a dangling pointer ride past the scan below.
      fi
      _dp_n=$((_dp_n + 1)) ;;
  esac
  _dp_rest=$_dp_scan
  while :; do
    case "$_dp_rest" in *'`'*) ;; *) break ;; esac
    _dp_before=${_dp_rest%%\`*}; _dp_rest=${_dp_rest#*\`}
    case "$_dp_rest" in *'`'*) ;; *) break ;; esac      # an unterminated backtick ends the scan
    _dp_id=${_dp_rest%%\`*}; _dp_rest=${_dp_rest#*\`}
    # trailing-whitespace strip by parameter expansion (was a `printf | sed` fork per backtick pair —
    # the retros carry many); byte-identical for a one-line cell.
    _dp_kw=${_dp_before%"${_dp_before##*[![:space:]]}"}
    case "$_dp_kw" in
      row|*[!A-Za-z]row) _dp_kind=row ;;
      ruling|*[!A-Za-z]ruling) _dp_kind=ruling ;;
      *) continue ;;                                    # a backticked token that is not a clause
    esac
    _dp_n=$((_dp_n + 1))
    if [ "$_dp_kind" = row ]; then
      if ! printf '%s' "$_dp_id" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$'; then
        echo "FAIL: Done item '$_dp_lab' — its Disposition clause row \`$(_cell_diag "$_dp_id")\` is not a well-formed row id (want a backticked board identifier); $_dp_rem"
        return 1
      fi
      if [ -n "$_dp_own" ] && [ "$_dp_id" = "$_dp_own" ]; then
        echo "FAIL: Done item '$_dp_lab' — its Disposition names its OWN row \`$(_cell_diag "$_dp_id")\`; a lesson has to go somewhere other than the row it closes ($_dp_rem)"
        return 1
      fi
      if ! _dispo_row_exists "$_dp_bl" "$_dp_id"; then
        echo "FAIL: Done item '$_dp_lab' — its Disposition names row \`$(_cell_diag "$_dp_id")\`, which is on no section of the board; $_dp_rem"
        return 1
      fi
    else
      if ! printf '%s' "$_dp_id" | grep -Eq '^D-[0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9]*$'; then
        echo "FAIL: Done item '$_dp_lab' — its Disposition clause ruling \`$(_cell_diag "$_dp_id")\` is not a well-formed ruling id (want D-YYMMDD-N); $_dp_rem"
        return 1
      fi
      _dp_dec="$_dp_dir/docs/governance/DECISIONS.md"
      if [ ! -f "$_dp_dec" ]; then
        echo "FAIL: Done item '$_dp_lab' — its Disposition cites ruling \`$(_cell_diag "$_dp_id")\` but $_dp_dec does not exist; stamp one from templates/DECISIONS-TEMPLATE.md and record the ruling"
        return 1
      fi
      if ! ruling_recorded "$_dp_dec" "$_dp_id"; then
        echo "FAIL: Done item '$_dp_lab' — its Disposition cites ruling \`$(_cell_diag "$_dp_id")\`, which is not recorded as an entry header in $_dp_dec (a cross-reference is a mention, not a ruling); $_dp_rem"
        return 1
      fi
    fi
  done
  if [ "$_dp_n" -eq 0 ]; then
    [ -n "$_dp_q" ] || bc_warn HITL-6-DISPO "Done item '$_dp_lab' — its 'Disposition:' carries no recognisable clause — fix: $_dp_rem"
    return 0
  fi
  return 0
}

# check_done_retro <file> [<project-dir>] : Done-edge L1-retro enforcement (HITL-6). "The loop closes" is a stated
# principle and the Done section's own header already declares "L1 retro written" — this makes that
# declaration ENFORCED rather than discipline. TWO legs with DIFFERENT scopes:
#   leg 1 — every Done row's Retro/outcome cell must clear HITL6_MIN_RETRO_CHARS. Without it a stub
#           (`| x | date | done |`) reads as a filled retro — the cheapest available bypass.
#   leg 2 — a row Closed on/after HITL6_RETRO_EPOCH must ALSO carry an 'L1 retro' marker.
# WHY THE EPOCH: this kit's board carries 77 Done rows predating the marker convention (5 carry it).
# Enforcing the marker retroactively would demand 72 retrospectives manufactured after the fact —
# precisely the attestation theatre this gate exists to prevent. Leg 1 still applies to all 77 and
# all 77 clear it, so the epoch buys backward compatibility without buying a hole.
# WHY THIS DATE: 2026-07-24 is the day HITL-6 was built, NOT the day after. It is set one day
# earlier than the obvious "ship date + 1" so that this slice's OWN Done rows — and the four HITL
# rows closed the same day — are graded by the gate they introduce. Measured: the real board is
# green at this epoch with zero backfill, and mutating the marker token reds it (so leg 2 is
# demonstrably live on real rows here, not merely configured).
# Columns are resolved BY NAME (col_index), never by position — the backlog-lib contract.
# FAIL-CLOSED: an unparseable or absent Closed date is treated as POST-epoch (marker required); an
# absent Closed/Retro column FAILs naming the columns that WERE found. A column-shifted row (see
# BOARD-ROW-ARITY) therefore fails loudly instead of silently evading leg 2.
# HONEST CEILING: leg 1 proves the cell is not a stub, NEVER that a retro was written; leg 2 proves
# a marker is present, not that the prose beneath it is a real retro. Backdating the Closed cell
# evades leg 2 — that edit is diff-visible and review-covered, and is not defended against here.
# Increments DONE_RETRO_GRADED (rows that reached leg 1). rc0 = pass.
check_done_retro() {
  _f="$1"
  # The project dir is what leg 3's ruling resolver reads DECISIONS.md relative to — BY ARGUMENT,
  # the same by-argument dir check_dir already takes, never an env var (threat T3). It defaults to
  # the board's own directory so the function stays callable with one argument.
  _dr_dir="${2:-$(dirname "$_f")}"
  _rows=$(section_rows "$_f" "Done")
  [ -n "$_rows" ] || return 0                     # no Done table at all -> nothing to enforce
  _hdr=$(printf '%s\n' "$_rows" | head -1)
  _ci_c=$(col_index "$_hdr" "Closed")
  _ci_r=$(col_index "$_hdr" "Retro/outcome")
  if [ -z "$_ci_c" ] || [ -z "$_ci_r" ]; then
    # One of FOUR FURTHER SITES beyond the six the row named (the others are the three Done-item
    # echoes below), found by sweeping the whole file rather than the diff. Re-derived at review:
    # the baseline b43d05a9 carried TEN raw sites, not the nine first claimed here — the Ready
    # column-missing echo was miscounted as raw when it was in fact already sanitized (its defect
    # was the joined-vs-per-cell bound, not rawness). Census: 10 -> 0.
    echo "FAIL: Done table lacks a 'Closed' and/or 'Retro/outcome' column (found: $(_header_cols_diag "$_hdr")); HITL-6 cannot grade an L1 retro without both"
    return 1
  fi
  _ln=0
  while IFS= read -r _row; do
    _ln=$((_ln + 1))
    if [ "$_ln" -eq 1 ]; then continue; fi        # header row
    if is_sep_row "$_row"; then continue; fi      # separator row (has a dash)
    # gfm_cell, NOT cell (review m6): the Item cell feeds both the diagnostic AND backtick_id, which
    # supplies leg 3's own-id test. A raw split truncates an item at its first escaped pipe, so the
    # id read is only accidentally right (the backticks happen to sit left of the escape on today's
    # board). Reading every graded cell of this row by ONE rule removes the accident.
    _item=$(gfm_cell "$_row" 1)
    if [ -z "$_item" ]; then continue; fi         # template 'no items' spacer row
    # gfm_cell, NOT cell: an escaped pipe anywhere left of this column shifts a raw split, and both
    # date legs below fail CLOSED on an unparseable value — so a GFM-correct row would go red for a
    # parser bug (measured live on the `B8` row). The diagnostic Item cell keeps cell(); it is
    # truncated there, not misread, and _cell_diag already bounds it.
    _closed=$(gfm_cell "$_row" "$_ci_c")
    _retro=$(retro_cell "$_row" "$_hdr" "$_ci_r")
    DONE_RETRO_GRADED=$((DONE_RETRO_GRADED + 1))
    # leg 1 — substance floor, EVERY row regardless of date.
    _len=${#_retro}
    if [ "$_len" -lt "$HITL6_MIN_RETRO_CHARS" ]; then
      echo "FAIL: Done item '$(_cell_diag "$_item")' — Retro/outcome cell is too thin ($_len chars, floor $HITL6_MIN_RETRO_CHARS); a Done row must record what shipped and what was learned"
      return 1
    fi
    # leg 2 — explicit marker for rows Closed on/after the epoch. A date this cannot parse falls
    # THROUGH to the marker requirement (fail closed); it is never skipped. The date test is
    # closed_pre_epoch (backlog-lib.sh), the same helper leg 3 and backlog-presence.sh's Done arm
    # use — one parse of "is this row in scope", not three.
    if closed_pre_epoch "$_closed" "$HITL6_RETRO_EPOCH"; then continue; fi   # pre-epoch -> N/A
    case "$_retro" in
      *"L1 retro"*) ;;
      *)
        # Demoted FAIL -> WARN (RECORD-GRAMMAR-ESSENTIALS): the marker is form. But a `Disposition:`
        # clause that names a row/ruling which does not exist is SUBSTANCE (D-240930-1 Q2) and must
        # still FAIL without the marker, so such a row is resolved by check_dispo under a synthetic
        # marker prefix, in quiet mode (form WARNs suppressed; this WARN already covers the marker).
        # A row with no `Disposition:` at all only repeats as a "no Disposition" WARN, so it is skipped.
        bc_warn HITL-6-RETRO "Done item '$(_cell_diag "$_item")' — closed '$(_cell_diag "$_closed")' (on/after $HITL6_RETRO_EPOCH, or undated) but carries no 'L1 retro' marker; a Done item should record an L1 retro — fix: add an 'L1 retro' marker to the Retro/outcome cell"
        case "$_retro" in
          *"Disposition:"*)
            if ! closed_pre_epoch "$_closed" "$HITL6_DISPO_EPOCH"; then
              check_dispo "L1 retro $_retro" "$(backtick_id "$_item")" "$_f" "$_dr_dir" "$(_cell_diag "$_item")" quiet || return 1
            fi ;;
        esac
        continue
        ;;
    esac
    # leg 3 — a DISPOSITION that resolves, for rows Closed on/after HITL6_DISPO_EPOCH. It runs
    # AFTER leg 2 deliberately: a retro with no marker is a leg-2 failure and should be reported
    # as one. Leg 2's pre-epoch `continue` above cannot hide a leg-3 obligation, because its epoch
    # (2026-07-24) is EARLIER than leg 3's (2026-09-03) — a row it skips is out of leg 3's scope
    # by construction. If those two dates ever cross, this ordering stops being safe.
    if ! closed_pre_epoch "$_closed" "$HITL6_DISPO_EPOCH"; then
      check_dispo "$_retro" "$(backtick_id "$_item")" "$_f" "$_dr_dir" "$(_cell_diag "$_item")" || return 1
    fi
  done <<EOF
$_rows
EOF
  return 0
}

# _arity_nf <row> : the row's COLUMN count under GFM delimiter rules, via gfm_nf (backlog-lib.sh) —
# an escaped pipe (`\|`, an odd backslash run) is a literal and does NOT delimit; `\\|` (even run)
# DOES. It returns a BARE column count (a 3-column row returns 3): no +2 boundary-field offset, so
# neither the NF-to-NF comparison nor the FAIL MESSAGE below subtracts anything — a board author
# counts columns, and gfm_nf already reports columns. (Pre-BOARD-PIPE-ESCAPE this was a raw
# `awk -F'|' NF` that also counted the two empty pipe-boundary fields and the FAIL message
# subtracted 2; that idiom is gone — do NOT reintroduce the offset. See the T2 note below.)
# Counting raw pipes instead of GFM delimiters would false-FAIL every correctly-escaped row.
# MEASURED on this kit's own board as this commit leaves it (2026-07-24), by comparing each row's
# raw NF against its escape-aware NF: EIGHT rows carry `\|` legitimately — the BOARD-ROW-ARITY and
# CP7R5-KITOWN-MARKER **Ready** rows, and the HITL-1 / CP7R5-NINE-PROFILES / CP7R5-GATE-AUTHORITY /
# CP-7-recert-run-5 / CP-8a / P0-FU(a) **Done** rows — and every one of the eight raw-splits WIDER
# than its own header, so a raw count would red all eight. One of them (HITL-1's Done row) is the
# exact shape the shipped `good-done-escaped-pipe` fixture asserts must PASS, so a raw count would
# also contradict an already-shipped contract. Rows are named, NOT cited by line number: a line
# citation goes stale on the next board edit, and an earlier draft of this comment cited a line
# that was in fact the Done table's SEPARATOR row.
# BOARD-PIPE-ESCAPE T2 (H-2/C2) — the `sed 's/\\|//g'` idiom above is DELETED. It CONTRADICTS the
# even-run rule this file otherwise honours: the pattern is a literal two-byte `\|`, so it strips
# the trailing `\|` out of a genuine `\\|` (an even backslash run — a REAL delimiter under GFM) as
# if it were an escaped `\|` (odd run — NOT a delimiter). A row carrying `\\|` therefore had its
# real extra column silently deleted before counting, so its NF matched the header's and the arity
# gate passed a row that was actually malformed — re-creating the exact H3 vacuity this file
# otherwise closes (the metric gate then reads the WRONG cell of that malformed row). `gfm_nf`
# (backlog-lib.sh) counts columns by the same backslash-run parse `cell()`/`col_index()` use, so
# this file now has ONE column-counting rule instead of two, and they cannot drift apart again.
# Units are unchanged: this is a bare column count (no +2 boundary-field offset — gfm_nf does not
# count the two empty artifacts the raw `awk -F'|' NF` idiom used to), so the arithmetic below
# updates from _ra_got/_ra_want to a bare NF-to-NF comparison; see _arity_one_section.
_arity_nf() { gfm_nf "$1"; }

# _ra_label <row> : the row's FIRST non-empty cell — the name a diagnostic calls the row by. Empty
# output means EVERY cell is empty, which is also the TRUE-spacer test (see _arity_one_section).
# Uses `_ral_`-prefixed locals; every call site is a command substitution, so the disjoint prefix
# cannot collide with any caller's namespace.
# BOARD-PIPE-ESCAPE T2 — routed through the shared GFM-exact parser (gfm_nf + cell): an
# independent raw split used to mislabel a row whose Item cell carries an escaped pipe left of
# real content (e.g. `Refine\| me` raw-split into `Refine\` — non-empty, so the true-spacer test
# still worked, but every diagnostic that named the row by this label named it WRONG). Called by
# check_ready_metric's spacer test AND its FAIL-message row name (design row 8).
_ra_label() {
  _ral_n=$(gfm_nf "$1")
  _ral_i=1
  while [ "$_ral_i" -le "$_ral_n" ]; do
    _ral_v=$(cell "$1" "$_ral_i")
    if [ -n "$_ral_v" ]; then printf '%s' "$_ral_v"; return 0; fi
    _ral_i=$((_ral_i + 1))
  done
}

# _ra_body_rows <file> : a crude, whole-file count of CONTENT-BEARING table body rows — a row that
# follows a delimiter row inside the same table and has at least one non-empty cell. This is the
# vacuous-green floor's independent oracle, NOT a second grader: it is deliberately a DIFFERENT
# parser (delimiter-anchored and section-agnostic, no section_rows/cell) so it cannot go blind the
# same way the graded path can. Per the shipped schema (locked by the arity-section-set selftest
# leg) a board's ONLY tables are its six state sections, so a positive count here with zero rows
# graded means either the grader went blind or the board grew a table-bearing section outside the
# six — and both are the same silent-coverage-loss defect.
_ra_body_rows() {
  awk '
    /^[[:space:]]*$/                        { inb=0; next }
    /^[[:space:]]*\|[-:| ]+\|[[:space:]]*$/ { inb=1; next }
    /^[[:space:]]*\|/                       { if (inb) { s=$0; gsub(/[[:space:]|]/,"",s)
                                                         if (s != "") n++ }
                                              next }
                                            { inb=0 }
    END { print n+0 }
  ' "$1"
}

# _arity_one_section <file> <section> : every non-spacer body row's column count must equal its
# section HEADER's. An unescaped '|' inside a cell shifts every later column, so the row's metadata
# is silently wrong and any positional reader (col_index + cell, the contract the gates above are
# built on) mis-reads it — a shifted row can evade a gate while looking well-formed. The header is
# the oracle because it is the section's own declared schema. Increments BOARD_ARITY_CHECKED per
# row actually compared. rc0 = pass. Accumulates within the section (reports EVERY bad row, not the
# first) so one run surfaces the whole picture, matching check_dir's K11 contract — proven by the
# bad-arity-two leg, which asserts BOTH offending rows are named in ONE run.
# THE SPACER SKIP IS NARROW ON PURPOSE. It used to be `[ -z "$(cell "$_row" 1)" ]` — skip any row
# whose ITEM cell is empty — which swallowed a mis-shaped row that simply left Item blank: it
# shipped green and was not even COUNTED (reproduced; now the bad-arity-empty-item leg). A TRUE
# spacer is a row where EVERY cell is empty, and such a row carries no metadata for a column shift
# to corrupt, so skipping exactly that is safe. Verified before narrowing: every empty-Item row on
# this kit's live board (3) and in templates/BACKLOG-TEMPLATE.md (3) is an all-cells-empty spacer.
# VARIABLE NAMING IS LOAD-BEARING HERE: this file is POSIX sh with NO `local`, so every helper
# shares ONE namespace and a bare `_f`/`_row`/`_item` in a leaf function is a live footgun — this
# exact class already bit inside this subsystem (see check_row_arity's `_agg` note below). Hence
# the `_ra_` prefix on everything the arity subsystem owns; `_ra_sf` is deliberately NOT `_ra_f`,
# which belongs to check_row_arity, our caller.
_arity_one_section() {
  _ra_sf="$1"; _ra_sec="$2"; _ra_bad=0
  _ra_rows=$(section_rows "$_ra_sf" "$_ra_sec")
  [ -n "$_ra_rows" ] || return 0                  # section absent or table-less -> nothing to compare
  _ra_hdr=$(printf '%s\n' "$_ra_rows" | head -1)
  _ra_want=$(_arity_nf "$_ra_hdr")
  _ra_ln=0
  while IFS= read -r _ra_row; do
    _ra_ln=$((_ra_ln + 1))
    if [ "$_ra_ln" -eq 1 ]; then continue; fi     # header row (the oracle itself)
    if is_sep_row "$_ra_row"; then continue; fi   # separator row (has a dash)
    _ra_item=$(_ra_label "$_ra_row")
    if [ -z "$_ra_item" ]; then continue; fi      # TRUE spacer: EVERY cell empty (see above)
    _ra_got=$(_arity_nf "$_ra_row")
    BOARD_ARITY_CHECKED=$((BOARD_ARITY_CHECKED + 1))
    if [ "$_ra_got" != "$_ra_want" ]; then
      # BOARD-PIPE-ESCAPE T2: _arity_nf is now gfm_nf, which already counts COLUMNS (no pipe-bounded
      # boundary-field offset to subtract — unlike the old raw `awk -F'|' NF` idiom this replaced),
      # so the FAIL message reports $_ra_got/$_ra_want directly.
      echo "FAIL: '$_ra_sec' row '$_ra_item' carries $_ra_got columns but the section header declares $_ra_want — an unescaped '|' inside a cell shifts every later column and silently corrupts this row's metadata (escape it as '\\|')"
      _ra_bad=1
    fi
  done <<EOF
$_ra_rows
EOF
  return $_ra_bad
}

# check_row_arity <file> : run the arity rule over every board section that carries items.
# The section list is ENUMERATED here, deliberately NOT derived from the board under test: a set
# derived from its own subject can always be satisfied by deleting a section (the same oracle
# lesson HITL-6's externally-declared constants record). They are separate calls rather than an
# `IFS='|'` split loop on purpose — the save/restore IFS form is exactly what this slice REMOVES
# from obl_detect (semgrep bash.lang.security.ifs-tampering); adding a new instance here would be
# incoherent. rc0 = pass.
# VARIABLE NAMING IS LOAD-BEARING HERE: this file is POSIX sh with NO `local`, so every helper
# shares one namespace. Naming this accumulator `_agg` CLOBBERED check_dir's own `_agg` and reset
# every failure accumulated before it — a green verdict on a board with a real Done-retro failure.
# Caught by the pre-existing bad-done-* legs going RED. Hence the `_ra_` prefix, which now covers
# _arity_one_section's locals too (it was still using bare names, safe only by leaf-call accident).
# The enumerated set is LOCKED to the shipped schema by the arity-section-set selftest leg: adding
# a seventh table-bearing state section to templates/BACKLOG-TEMPLATE.md without adding it here
# reds the selftest, so a new section can never ship arity-unchecked in silence.
# VACUOUS-GREEN FLOOR: a gate that inspected NOTHING must never report OK. `board-arity-checked=0`
# is legitimate on a genuinely empty board (a brand-new adopter's — protecting incept first-run-
# green), but NOT on a board that plainly carries rows, so the floor is conditioned on an
# independent row count (_ra_body_rows) rather than being unconditional.
check_row_arity() {
  _ra_f="$1"; _ra_agg=0
  _arity_one_section "$_ra_f" "Ready"       || _ra_agg=1
  _arity_one_section "$_ra_f" "In Progress" || _ra_agg=1
  _arity_one_section "$_ra_f" "In Review"   || _ra_agg=1
  _arity_one_section "$_ra_f" "Released"    || _ra_agg=1
  _arity_one_section "$_ra_f" "Done"        || _ra_agg=1
  _arity_one_section "$_ra_f" "Blocked"     || _ra_agg=1
  if [ "$BOARD_ARITY_CHECKED" -eq 0 ]; then
    _ra_seen=$(_ra_body_rows "$_ra_f")
    if [ "$_ra_seen" -gt 0 ]; then
      echo "FAIL: the column-arity gate inspected 0 rows on a board that carries $_ra_seen content-bearing table row(s) — either it went blind (a renamed or reshaped state section) or the board tracks items in a table outside the six sections it grades (Ready / In Progress / In Review / Released / Done / Blocked); a gate that inspects nothing must never report OK"
      _ra_agg=1
    fi
  fi
  return $_ra_agg
}

# _bctr_sig <signame> -> fix2 (security BLOCKER + MEDIUM). Called ONLY from the ONE top-level trap
# installed near the dispatch `case` below — never inside bc_tracker_ready itself, so there is no
# caller's trap here to clobber (that was the MEDIUM bug: a trap saved/restored INSIDE the library
# function broke under bash, whose `trap` listing spells `SIGINT`/`SIGTERM`, not `INT`/`TERM`).
# Removes bc_tracker_ready's temp files (if any exist yet) then RE-RAISES so the process actually
# TERMINATES (128+signal) — the BLOCKER this closes: a handler that only removed files and returned
# let `done < list` silently read nothing and print "OK ... graded=0" at rc0 after a real TERM.
_bctr_sig() {
  rm -f "${_bctr_lf:-}" "${_bctr_vf:-}" 2>/dev/null
  trap - INT TERM
  kill -"$1" "$$"
}

# _bctr_cleanup -> removes bc_tracker_ready's two mktemp files on the way out (the normal-return
# path; the signal path is _bctr_sig above).
_bctr_cleanup() {
  rm -f "$_bctr_lf" "$_bctr_vf"
}

# bc_tracker_ready <head> -> the TRACKER ARM of the Ready-edge DoR gate (design §3e/§3f, P-4).
# Reads seam_rows_in_state ready then the four dor-* flags per id WITHOUT $( ) (T9 carry, T7 seat
# M-1: a $( ) call forks, so the seam's parse memo never survives across it) — SEAM_ROOT is already
# set by check_dir's caller. rc0 OK (every flag 'yes'), rc1 FAIL (a bound 'no'/'n/a' dor-* value),
# rc2 UNVERIFIED (the Ready list or a flag is absent) — worst rc across every row wins (2 over 1).
# This gate's own vocabulary (OK/FAIL), never 'WAITING' (P-4 correction to the inherited design).
# fix1 R3 (F-9): grades ONLY the four Ready-edge dor-* flags — `outcome-recorded` is a Done-edge
# flag and is never graded here.
# fix2 (security BLOCKER, independent of the top-level trap near the dispatch `case`): fail CLOSED
# if the Ready list ever vanishes or shrinks between the write below and the read — never let a
# missing/short list read as a clean 0. `[ -r ]`, never a bare `exec <`: a bare exec's redirection
# failure is shell-FATAL on some shells (dash) even guarded by `||` — a compound command's own
# `< file` (the while loop below) fails as an ordinary, recoverable nonzero status, portably.
bc_tracker_ready() {
  SEAM_HEAD="$1"
  _bctr_lf=$(mktemp); _bctr_vf=$(mktemp)
  _bctr_lrc=0; seam_rows_in_state ready > "$_bctr_lf" 2>"$_bctr_vf" || _bctr_lrc=$?
  if [ "$_bctr_lrc" -ne 0 ]; then
    # fix1 R2 (L-1): relay the seam's own fixed-text refusal above the generic line — never the record's own bytes.
    [ -s "$_bctr_vf" ] && cat "$_bctr_vf" >&2
    echo "UNVERIFIED: backlog-current (tracker) — the Ready list is absent or truncated on the tracker record — cannot grade Definition-of-Ready" >&2
    _bctr_cleanup; return 2
  fi
  _bctr_want=$(wc -l < "$_bctr_lf" 2>/dev/null) || _bctr_want=-1
  if [ ! -r "$_bctr_lf" ]; then echo "UNVERIFIED: backlog-current (tracker) — the Ready list vanished before it could be read — cannot grade Definition-of-Ready" >&2; _bctr_cleanup; return 2; fi
  _bctr_worst=0; _bctr_n=0
  while IFS= read -r _bctr_id; do
    [ -n "$_bctr_id" ] || continue
    _bctr_n=$((_bctr_n + 1))
    for _bctr_flag in dor-acceptance dor-metric dor-size dor-risk; do
      _bctr_frc=0
      seam_row_flag "$_bctr_id" "$_bctr_flag" > "$_bctr_vf" 2>/dev/null || _bctr_frc=$?
      if [ "$_bctr_frc" -ne 0 ]; then
        echo "UNVERIFIED: backlog-current (tracker) — row '$_bctr_id' — $_bctr_flag is not carried on the tracker record (conf key field.${_bctr_flag#dor-}) — cannot grade Definition-of-Ready" >&2
        [ "$_bctr_worst" -lt 2 ] && _bctr_worst=2
        continue
      fi
      IFS= read -r _bctr_v < "$_bctr_vf" || _bctr_v=""
      if [ "$_bctr_v" != "yes" ]; then
        echo "FAIL: backlog-current (tracker) — row '$_bctr_id' — $_bctr_flag is '$_bctr_v', not 'yes' — not Ready" >&2
        [ "$_bctr_worst" -lt 1 ] && _bctr_worst=1
      fi
    done
  done < "$_bctr_lf"
  if [ "$_bctr_n" -ne "$_bctr_want" ]; then echo "UNVERIFIED: backlog-current (tracker) — graded $_bctr_n of $_bctr_want Ready rows — the list was cut short — cannot grade Definition-of-Ready" >&2; _bctr_worst=2; fi
  _bctr_cleanup
  [ "$_bctr_worst" -eq 0 ] && echo "OK: backlog-current (tracker) — Ready rows graded=$_bctr_n; every dor-* flag is 'yes'"
  return "$_bctr_worst"
}

# check_dir <project-dir> -> routes the three N/A cases; for an in-use BACKLOG.md, parses the
# state tables. N/A is always a pass (never a false FAIL). OK/FAIL reflect the board.
check_dir() {
  _dir="$1"
  # shellcheck disable=SC2034  # SEAM_ROOT is read by the sourced seam_* functions (backlog-lib.sh) — shellcheck cannot trace a global consumed across a sourced-function boundary.
  SEAM_ROOT="$_dir"
  _tok=$(seam_backend)
  if [ -z "$_tok" ]; then
    echo "N/A: $_dir — no backlog backend declared (CLAUDE.md has no filled 'Backlog backend' field) — skipping"
    return 0
  fi
  case "$_tok" in
    unrecognized:*)
      # A filled but unknown backend token. FAIL (never fail open to N/A) so a mistyped backend
      # cannot silently disable the gate for an md-board owner.
      _bad=${_tok#unrecognized:}
      echo "FAIL: $_dir — unrecognized backlog backend '$_bad' (known: md github jira ado linear gitlab)"
      return 1
      ;;
  esac
  # A NON-MD BACKEND IS NOT AN N/A (NON-MD-BACKEND-NEVER-SILENT, D-240903-1 §3). It printed
  # `N/A … repo-native board checks skip` and returned 0 — a green light over governance nobody
  # verified. rc 3 is the NOT ENFORCED partition; `verify.sh`'s `-run` companion reads non-zero as
  # fail, which is correct. See backlog-lib.sh::not_enforced_notice for the sentence and the ladder.
  # (`conformance/backlog-adapters.sh` still owns backend-NAME agreement; that is a different claim
  # from board-bound governance and it was never what this route attested.)
  if [ "$_tok" != "md" ]; then
    # TBG-READER-FLAGS-LIST T9 (design §3e/§3f, P-4, the H-4 switch): a SET SEAM_RECORD (mapped
    # from $KIT_TRACKER_RECORD below) routes through the tracker arm — bound (rc0/rc1 on this
    # gate's own OK/FAIL vocabulary) or UNVERIFIED (rc2), NEVER waivable, NEVER falling through to
    # not_enforced_notice. UNSET SEAM_RECORD keeps today's behaviour byte-identical (rc3 NOT
    # ENFORCED, waiver ladder preserved) — mirrors loop-state.sh::check_row's own H-4 branch.
    SEAM_RECORD="${KIT_TRACKER_RECORD:-}"
    if seam_tracker_record_set; then
      _bc_trc=0
      bc_tracker_ready "${_BC_HEAD:-}" || _bc_trc=$?
      return "$_bc_trc"
    fi
    _bc_ne=0
    not_enforced_notice "$_tok" "$_dir" "$(dirname "$0")/waivers-valid.sh" || _bc_ne=$?
    return "$_bc_ne"
  fi
  _bl="$_dir/BACKLOG.md"
  if [ ! -f "$_bl" ]; then
    echo "FAIL: $_dir declares a BACKLOG.md backend but has no BACKLOG.md file"
    return 1
  fi
  if is_pure_template "$_bl"; then
    echo "N/A: $_dir — BACKLOG.md board not yet in use (still the pristine template) — skipping (protects incept first-run-green)"
    return 0
  fi
  # Required state headings must all be present.
  for _h in "Ready" "In Progress" "In Review"; do
    if ! grep -Eq "^## ${_h}[[:space:]]*$" "$_bl"; then
      echo "FAIL: $_bl is missing required '## $_h' section"
      return 1
    fi
  done
  # Parse the gated state tables. Ready is gated on ONE cell only — its Success metric
  # (BOARD-DOR-FIELDS); the rest of its schema, acceptance criteria included, stays ungated.
  # Released is ungated. Done is structurally ungated but carries two edge gates (HITL-3 UAT,
  # HITL-6 L1 retro) below.
  SPACER_SKIPS=0; NA_ESCAPES=0; BLOCKED_NA_ESCAPES=0; DONE_UAT_FLAGGED=0; DONE_RETRO_GRADED=0; BOARD_ARITY_CHECKED=0; BOARD_TRACE=""; _agg=0
  # Accumulate-all (K11): run EVERY gated section unconditionally and collect every failure,
  # so ONE run surfaces the whole picture — never exit-on-first (fix In Review, re-run, only
  # THEN discover Blocked also failed). return non-zero iff any section failed.
  # Ready-edge DoR enforcement (BOARD-DOR-FIELDS): every content-bearing Ready row carries a
  # non-empty Success metric, and a Ready table with content but no metric column is a schema
  # violation naming the migration.
  check_ready_metric "$_bl" || _agg=1
  check_section "$_bl" "In Progress" "Links" progress || _agg=1
  check_section "$_bl" "In Review" "PR" review || _agg=1
  # Blocked is OPTIONAL (Ready/In Progress/In Review are required headings; Blocked is not) —
  # gate it ONLY IF the section is present. A blocked *item* cannot exist without the section,
  # so nothing escapes the gate by the board omitting it.
  if grep -Eq "^## Blocked[[:space:]]*$" "$_bl"; then
    check_section "$_bl" "Blocked" "Blocked on" blocked "Since" || _agg=1
  fi
  # Done-edge UAT enforcement (HITL-3): a Done row flagged [taste-surface] must carry a UAT-SIGNOFF
  # reference; an unflagged Done row is N/A. Self-guards on an absent/empty Done table (Done is
  # optional). Accumulate-all (K11): collect its failure alongside the section gates in ONE pass.
  check_done_uat "$_bl" || _agg=1
  # Done-edge L1-retro enforcement (HITL-6): every Done row clears a substance floor, and a row
  # closed on/after HITL6_RETRO_EPOCH also carries an 'L1 retro' marker. Same accumulate-all (K11)
  # contract as the gate above — collect its failure in the SAME pass rather than short-circuiting.
  check_done_retro "$_bl" "$_dir" || _agg=1
  # Column-arity (BOARD-ROW-ARITY): every non-spacer body row's column count matches its section
  # header's. Same accumulate-all (K11) contract — a shifted row is reported in the SAME pass.
  check_row_arity "$_bl" || _agg=1
  [ "$_agg" -ne 0 ] && return 1
  echo "OK: backlog-current — backend is BACKLOG.md and the in-use board traces: $BOARD_TRACE; spacer-rows-skipped=$SPACER_SKIPS; in-progress N/A-escapes=$NA_ESCAPES; blocked N/A-escapes=$BLOCKED_NA_ESCAPES; done-uat-flagged=$DONE_UAT_FLAGGED; done-retro-graded=$DONE_RETRO_GRADED; board-arity-checked=$BOARD_ARITY_CHECKED"
  return 0
}

# --- selftest (written FIRST) -----------------------------------------------------------
selftest() {
  st_fail=0
  base=$(mktemp -d)
  # Trap-clean on every exit path — matches the sibling promotion-readiness-wired selftest fixed
  # earlier this slice, and honours this project's documented history of leaked conformance mktemp
  # trees filling the dev machine. `[ -n ]` guards the empty-var case so this can never widen.
  trap '[ -n "${base:-}" ] && rm -rf "$base"; :' EXIT INT TERM

  # ===== BOARD-PIPE-ESCAPE T1 — backlog-lib.sh's shared parser, proven BEHAVIOURALLY here ====
  # backlog-lib.sh is sourced-only and sits in conformance/aggregate-exclusions.txt (never
  # mutation-swept) — see its own header comment. This is its one behavioural harness: cell(),
  # gfm_cell() (now a thin alias) and gfm_nf() proven against the GFM backslash-run rule (a `|`
  # is a delimiter iff preceded by an EVEN-length run of `\`), RAW (not unescaped) per L-8.
  _pp_row1='| a\|b | c |'                      # one backslash before the pipe -> escaped (odd run)
  assert_eq_str "$(cell "$_pp_row1" 1)" 'a\|b' "parser/escaped-pipe: cell(row,1) rejoins across a single \\ before |"
  assert_eq_str "$(cell "$_pp_row1" 2)" 'c' "parser/escaped-pipe: cell(row,2) reads the column AFTER the escaped pipe"
  assert_eq_str "$(gfm_nf "$_pp_row1")" 2 "parser/escaped-pipe: gfm_nf counts 2 GFM columns (the escaped pipe is not a delimiter)"

  _pp_row2='| a\\|b | c |'                     # two backslashes before the pipe -> NOT escaped (even run)
  assert_eq_str "$(cell "$_pp_row2" 1)" 'a\\' "parser/escaped-backslash-pipe: cell(row,1) stops at the real delimiter after an even run of \\"
  assert_eq_str "$(cell "$_pp_row2" 2)" 'b' "parser/escaped-backslash-pipe: cell(row,2) reads the column the real delimiter opened"
  assert_eq_str "$(gfm_nf "$_pp_row2")" 3 "parser/escaped-backslash-pipe: gfm_nf counts 3 GFM columns (\\\\| IS a delimiter)"

  _pp_row3='| foo\ | bar |'                    # a trailing backslash in CONTENT, then a real (space-padded) delimiter
  assert_eq_str "$(cell "$_pp_row3" 1)" 'foo\' "parser/trailing-backslash: cell(row,1) keeps a content-ending backslash and still closes at the next real pipe"
  assert_eq_str "$(cell "$_pp_row3" 2)" 'bar' "parser/trailing-backslash: cell(row,2) reads the column after it"

  # gfm_cell is now a thin alias of cell() (T1 fold) — same three assertions must hold through it.
  assert_eq_str "$(gfm_cell "$_pp_row1" 1)" 'a\|b' "parser/gfm_cell-alias: gfm_cell(row,1) matches cell() on the escaped-pipe row"
  assert_eq_str "$(gfm_cell "$_pp_row2" 1)" 'a\\' "parser/gfm_cell-alias: gfm_cell(row,1) matches cell() on the escaped-backslash-pipe row"

  # retro_cell re-expressed on the shared parser (T1 fold) — same escaped-pipe row, last column.
  _pp_hdr='| Item | Retro |'
  assert_eq_str "$(retro_cell "$_pp_row1" "$_pp_hdr" 1)" 'a\|b' "parser/retro_cell-shared: retro_cell(row,hdr,1) matches cell() on the escaped-pipe row"

  # ===== T2.0 — backend resolution / routing (annotated template forms) ================

  # no CLAUDE.md at all -> undeclared.
  d="$base/t0_nofile"; mkdir -p "$d"; printf '# just a readme\n' > "$d/README.md"
  assert_msg "$d" "no backlog backend declared" "t0/nofile: no CLAUDE.md -> N/A (undeclared)"

  # CLAUDE.md exists but has no Backlog-backend field -> undeclared.
  d="$base/t0_absentfield"; mkdir -p "$d"; printf '# CLAUDE\n\nnothing here\n' > "$d/CLAUDE.md"
  assert_msg "$d" "no backlog backend declared" "t0/absent-field: field absent -> N/A (undeclared)"

  # the true unfilled bracketed choice-list -> undeclared.
  d="$base/t0_placeholder"; mkdir -p "$d"
  _claude_md '[`BACKLOG.md` / GitHub / Jira / Azure DevOps / Linear / GitLab] — [link] (mapping: `docs/work-tracking/adapters.md`)' "$d/CLAUDE.md"
  assert_msg "$d" "no backlog backend declared" "t0/placeholder: unfilled choice-list -> N/A (undeclared)"

  # filled BACKLOG.md (annotated), board still pristine -> N/A (board not yet in use).
  # Pin to the REAL shipped template (verbatim), not a synthetic board.
  d="$base/t0_pristine"; mkdir -p "$d"
  _claude_md 'BACKLOG.md — [link] (mapping: `docs/work-tracking/adapters.md`)' "$d/CLAUDE.md"
  _tpl=$(_find_template) || { echo "selftest FAIL: cannot locate templates/BACKLOG-TEMPLATE.md"; st_fail=1; _tpl=/dev/null; }
  cp "$_tpl" "$d/BACKLOG.md"
  assert_msg "$d" "board not yet in use" "t0/pristine: filled BACKLOG.md + verbatim template -> N/A (pristine)"

  # filled BACKLOG.md (annotated) + a real board -> GATED (resolves md, must NOT be N/A).
  d="$base/t0_filled_md"; mkdir -p "$d"
  _claude_md 'BACKLOG.md — [link] (mapping: `docs/work-tracking/adapters.md`)' "$d/CLAUDE.md"
  _good_board "$d/BACKLOG.md"
  assert_ok "$d" "t0/filled-md: 'BACKLOG.md — [link] (mapping:…)' -> GATED (resolves md, not N/A)"

  # the bare token `md` (what T8's stamp writes) + a real board -> GATED.
  d="$base/t0_bare_md"; mkdir -p "$d"
  _claude_md 'md — [link] (mapping: `docs/work-tracking/adapters.md`)' "$d/CLAUDE.md"
  _good_board "$d/BACKLOG.md"
  assert_ok "$d" "t0/bare-md: bare token 'md — [link] (mapping:…)' -> GATED (resolves md)"

  # a markdown-link value -> GATED (resolves md via the URL).
  d="$base/t0_mdlink"; mkdir -p "$d"
  _claude_md '[the board](./BACKLOG.md)' "$d/CLAUDE.md"
  _good_board "$d/BACKLOG.md"
  assert_ok "$d" "t0/md-link: '[the board](./BACKLOG.md)' -> GATED (resolves md)"

  # ===== NON-MD-BACKEND-NEVER-SILENT — a hosted tracker is NOT ENFORCED (rc 3), never an N/A ====
  # Every one of the five tokens, because the route is shared and a single-token leg cannot see a
  # token that stops resolving. These four legs used to assert `N/A ... rc 0`, below.
  for _st_tok in github jira ado linear gitlab; do
    d="$base/t_nonmd_$_st_tok"; mkdir -p "$d"
    _claude_md "$_st_tok" "$d/CLAUDE.md"
    assert_msg_rc "$d" "NOT ENFORCED: backend '$_st_tok' — board-bound governance is not verified on this tree" 3 \
      "nonmd/$_st_tok: -> NOT ENFORCED, rc 3 (red), never a silent N/A"
  done
  d="$base/t_nonmd_jira"
  assert_msg_rc "$d" "Cure: TRACKER-BACKED-GOVERNANCE, or ratify a board-governance waiver" 3 \
    "nonmd/cure: the verdict names both ladders"
  # A ratified, filled, unexpired waiver -> rc 0, notice still printed.
  # TODAY-RELATIVE dates (security S-M1): a future `Opened` is now refused — it makes the 90-day
  # maximum nominal — so the 2099 dates this fixture used to carry would assert the opposite of the
  # rule. GNU then BSD, matching waivers-valid.sh's own dialect pair.
  _bc_d0=$(date -u -d "+0 days" +%Y-%m-%d 2>/dev/null || date -u -v+0d +%Y-%m-%d)
  _bc_d60=$(date -u -d "+60 days" +%Y-%m-%d 2>/dev/null || date -u -v+60d +%Y-%m-%d)
  d="$base/t_nonmd_waived"; mkdir -p "$d"; _claude_md 'jira' "$d/CLAUDE.md"
  printf '## Active waivers\n\n| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |\n|--|--|--|--|--|--|--|\n| board-governance | the kit reads BACKLOG.md only | @jdoe | %s | %s | adopt TRACKER-BACKED-GOVERNANCE | @sec |\n' "$_bc_d0" "$_bc_d60" \
    > "$d/WAIVER-REGISTER.md"
  assert_msg_rc "$d" "NOT ENFORCED: backend 'jira' — waived until $_bc_d60 by @jdoe" 0 \
    "nonmd/waived: a ratified board-governance waiver -> rc 0 WITH the notice"
  # The UNFILLED incept stamp buys nothing (the bridge's load-bearing negative).
  d="$base/t_nonmd_stamp"; mkdir -p "$d"; _claude_md 'jira' "$d/CLAUDE.md"
  printf '## Active waivers\n\n| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |\n|--|--|--|--|--|--|--|\n| board-governance | x | [owner] | %s | %s | y | [security-owner] |\n' "$_bc_d0" "$_bc_d60" \
    > "$d/WAIVER-REGISTER.md"
  assert_msg_rc "$d" "NOT ENFORCED: backend 'jira' — board-bound governance is not verified on this tree" 3 \
    "nonmd/stamp: the UNFILLED incept stamp -> still rc 3"

  # The ANNOTATED forms still RESOLVE to the right token — the property these legs were always
  # about — and now land on the NOT ENFORCED verdict rather than an N/A.
  d="$base/t0_jira"; mkdir -p "$d"
  _claude_md 'Jira — [link] (mapping: `docs/work-tracking/adapters.md`)' "$d/CLAUDE.md"
  assert_msg_rc "$d" "NOT ENFORCED: backend 'jira'" 3 "t0/jira: Jira -> NOT ENFORCED (names 'jira', not 'undeclared')"

  # Azure DevOps -> naming 'ado' (alias), NOT 'undeclared'.
  d="$base/t0_ado"; mkdir -p "$d"
  _claude_md 'Azure DevOps — [link]' "$d/CLAUDE.md"
  assert_msg_rc "$d" "NOT ENFORCED: backend 'ado'" 3 "t0/ado: 'Azure DevOps' -> NOT ENFORCED (aliases to 'ado')"

  # one fixture per remaining backend.
  d="$base/t0_github"; mkdir -p "$d"
  _claude_md 'GitHub — [link] (mapping: `docs/work-tracking/adapters.md`)' "$d/CLAUDE.md"
  assert_msg_rc "$d" "NOT ENFORCED: backend 'github'" 3 "t0/github: GitHub -> NOT ENFORCED (names 'github')"

  d="$base/t0_linear"; mkdir -p "$d"
  _claude_md 'Linear — [link] (mapping: `docs/work-tracking/adapters.md`)' "$d/CLAUDE.md"
  assert_msg_rc "$d" "NOT ENFORCED: backend 'linear'" 3 "t0/linear: Linear -> NOT ENFORCED (names 'linear')"

  d="$base/t0_gitlab"; mkdir -p "$d"
  _claude_md 'GitLab — [link] (mapping: `docs/work-tracking/adapters.md`)' "$d/CLAUDE.md"
  assert_msg_rc "$d" "NOT ENFORCED: backend 'gitlab'" 3 "t0/gitlab: GitLab -> NOT ENFORCED (names 'gitlab')"

  # ===== T2.1 — in-use board: In Progress -> Links, In Review -> PR =====================
  _MD='BACKLOG.md — [link] (mapping: `docs/work-tracking/adapters.md`)'

  # good/ — a fully valid board -> OK.
  d="$base/good"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"; _good_board "$d/BACKLOG.md"
  assert_ok "$d" "good: valid board -> OK"
  # ...and its well-formed Blocked row is gated: BOARD_TRACE names Blocked (Blocked on + Since).
  assert_msg "$d" "Blocked→Blocked on+Since" "good: BOARD_TRACE names the Blocked gate (Blocked on+Since)"

  # bad-unlinked-inprogress/ — an In Progress row with an empty Links cell -> FAIL.
  d="$base/bad-unlinked-inprogress"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 |  |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |
EOF
  assert_fail "$d" "In Progress item 'Add login'" "bad-unlinked-inprogress: empty Links -> FAIL"

  # bad-unlinked-inreview/ — an In Review row with an empty PR cell -> FAIL.
  d="$base/bad-unlinked-inreview"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat |  |
EOF
  assert_fail "$d" "In Review item 'Add login'" "bad-unlinked-inreview: empty PR -> FAIL"

  # bad-bare-na/ — a bare `N/A` (a blank in a costume) in In Progress Links -> FAIL.
  d="$base/bad-bare-na"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | N/A |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |
EOF
  assert_fail "$d" "In Progress item 'Add login'" "bad-bare-na: bare 'N/A' Links -> FAIL"

  # good-na-with-reason/ — In Progress Links `N/A — <reason>` -> PASS, counted as an escape.
  d="$base/good-na-with-reason"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | N/A — spike, no artifact yet |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |
EOF
  assert_msg "$d" "in-progress N/A-escapes=1" "good-na-with-reason: 'N/A — reason' Links -> PASS (escape counted)"

  # bad-na-in-inreview/ — In Review PR `N/A — reason` -> FAIL (asymmetry: no PR, no review).
  d="$base/bad-na-in-inreview"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | N/A — not opened yet |
EOF
  assert_fail "$d" "In Review item 'Add login'" "bad-na-in-inreview: 'N/A — reason' PR -> FAIL (asymmetry)"

  # good-spacer-rows/ — template 'no items' spacer rows are skipped BY the Item-empty rule
  # (not consumed as separators). 2 spacers in In Progress + 1 in In Review = 3 skipped.
  d="$base/good-spacer-rows"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |
| | | | |
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |
| | | |
EOF
  assert_msg "$d" "spacer-rows-skipped=3" "good-spacer-rows: 3 spacer rows skipped by the Item-empty rule (not as separators)"

  # ===== BOARD-DOR-FIELDS — Ready -> 'Success metric / hypothesis' (the DoR entry gate) =======
  # THE SANCTIONED REVERSAL. The fixture that stood here (`good-ready-unrefined`) asserted that a
  # Ready row with blank acceptance criteria PASSes because "Ready is ungated; we do NOT over-gate
  # into the Definition of Ready". Ruling `D-240811-2.2` reverses exactly that for ONE field: the
  # DoR's mandatory Success metric. The property is SPLIT, not abandoned — acceptance-criteria
  # content stays ungated (only the metric field is funded), and `good-ready-metric` below is the
  # surviving half (blank AC + a populated metric -> PASS).

  # good-ready-metric/ — the SURVIVING half of the deleted property: blank acceptance criteria
  # still PASSes, because only the metric cell is gated. Also the positive liveness anchor for the
  # new trace field (Ready is named in BOARD_TRACE with the rows it evaluated).
  d="$base/good-ready-metric"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Intent | Acceptance | Size | Risk | Type | Owner | Links | Success metric / hypothesis |
|------|--------|-----------|------|------|------|-------|-------|-----------------------------|
| Refine me | some intent |  | M | low | feature | agent | #99 | first-week drop-off 38% -> under 15% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |
EOF
  assert_ok "$d" "good-ready-metric: blank Ready acceptance + a populated metric -> PASS (only the metric is gated)"
  assert_msg "$d" "Ready→Success metric / hypothesis (1 row)" \
    "good-ready-metric: the trace names the RESOLVED metric column and the rows EVALUATED"

  # bad-ready-no-metric/ — an EMPTY metric cell on a Ready row -> FAIL, naming the row. THE
  # enforced edge: an item cannot be Ready without a measurable statement of what "worked" means.
  d="$base/bad-ready-no-metric"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| Refine me | agent | #99 |  |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |
EOF
  assert_fail "$d" "Ready item 'Refine me'" "bad-ready-no-metric: empty metric cell -> FAIL (row named)"

  # bad-ready-placeholder-metric/ — a bare `TBD` (a blank in a costume) -> FAIL. Reuses the file's
  # OWN placeholder helper (is_bare_na), so there is ONE definition of "a blank in a costume".
  d="$base/bad-ready-placeholder-metric"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| Refine me | agent | #99 | TBD |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |
EOF
  assert_fail "$d" "Ready item 'Refine me'" "bad-ready-placeholder-metric: bare 'TBD' metric -> FAIL"

  # bad-ready-qmark-metric/ — a bare `?`. This is the leg that makes the is_bare_na EXTENSION
  # non-vacuous: `?` was NOT in the marker set before this slice, so reverting the extension
  # flips this fixture green while every other placeholder leg stays red.
  d="$base/bad-ready-qmark-metric"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| Refine me | agent | #99 | ? |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |
EOF
  assert_fail "$d" "Ready item 'Refine me'" "bad-ready-qmark-metric: bare '?' metric -> FAIL (is_bare_na extension is live)"

  # bad-ready-na-reason-metric/ — `N/A — <reason>` is REJECTED for this cell (the In-Review PR
  # asymmetry, applied to the DoR). Under the demote-don't-fill ruling a row whose metric is
  # "N/A because…" is BY DEFINITION not Ready — it demotes to Backlog (unrefined). Without this
  # leg, adding `|| is_na_reason` to the accept path would silently reopen the escape hatch and
  # no fixture would notice.
  d="$base/bad-ready-na-reason-metric"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| Refine me | agent | #99 | N/A — hard to measure right now |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |
EOF
  assert_fail "$d" "Ready item 'Refine me'" "bad-ready-na-reason-metric: 'N/A — reason' metric -> FAIL (demote, do not fill)"

  # bad-ready-escaped-item-pipe-metric/ — BOARD-PIPE-ESCAPE leg 1 (design §6.1 leg 1 / H3). A Ready
  # row whose ITEM cell carries an escaped pipe LEFT of the metric column, with an EMPTY metric cell.
  # This fixture exercises BOTH halves of the defect, against the PRE-SLICE (main) raw parser:
  #   (H3 metric-misread) the old raw `cell()` splits `Refine\| me` into `Refine\` + ` me`, shifting
  #   every later column one right, so `cell(row, metric-col)` reads `#99` (non-empty) and the row
  #   PASSES the Ready-metric gate VACUOUSLY — the exact H3 vacuity (measured on main: metric reads
  #   `#99`, not empty). T1's GFM-exact `cell()`/`col_index()` fix this: the metric column now reads
  #   the true (empty) cell and the row FAILs.
  #   (_ra_label mislabel, design row 8) T2's conversion of `_ra_label` additionally fixes the row's
  #   NAME in every diagnostic: the pre-T2 independent raw split labelled it `Refine\` (truncated but
  #   non-empty, so the true-spacer test still passed and the row was still evaluated) instead of the
  #   real GFM cell `Refine\| me`.
  # The assertion below (`assert_fail ... "Ready item 'Refine\| me'"`) is non-vacuous against the
  # unconverted code on BOTH counts: vs main the row would not FAIL at all (vacuous metric pass, no
  # message); vs T1-without-T2 it FAILs but the message names it `Refine\'` (no "me"). Post-conversion
  # it FAILs AND names the true GFM item cell verbatim (RAW convention — `\|` preserved, not unescaped).
  d="$base/bad-ready-escaped-item-pipe-metric"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| Refine\| me | agent | #99 |  |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |
EOF
  assert_fail "$d" "Ready item 'Refine\| me'" \
    "bad-ready-escaped-item-pipe-metric: empty metric on a row with an escaped pipe left of it -> FAIL, naming the TRUE (GFM) item label"

  # good-ready-metric-seam-routed/ & bad-ready-metric-seam-routed/ (TBG-SEAM-MD-ARM WAVE 2,
  # non-vacuity) — every fixture ABOVE uses a bare 'Refine me' Item cell (no backticked id), so
  # check_ready_metric's dor-metric gating decision falls back to its pre-seam direct read for
  # every leg above: byte-identical, but none of them actually EXERCISE seam_row_flag's dor-metric
  # arm. These two legs use a properly backticked Item id (the shipped board convention, CLAUDE.md
  # §1 act 3) so the seam path — not the fallback — is what runs, giving the new arm a real,
  # production-routed positive AND a load-bearing negative.
  d="$base/good-ready-metric-seam-routed"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| `SEAM-RM-1` | agent | #99 | first-week drop-off 38% -> under 15% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |
EOF
  assert_ok "$d" "good-ready-metric-seam-routed: a backticked-id row with a populated metric -> PASS, through the seam"

  d="$base/bad-ready-metric-seam-routed"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| `SEAM-RM-2` | agent | #99 |  |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |
EOF
  assert_fail "$d" "Ready item '\`SEAM-RM-2\`'" \
    "bad-ready-metric-seam-routed: a backticked-id row with an empty metric -> FAIL, through the seam (load-bearing negative)"

  # bad-ready-missing-metric-column/ — the COLUMN-ABSENT semantics (design-gate HIGH-1): a Ready
  # table carrying content rows but NO metric column FAILs, naming the migration. The
  # skip-when-absent arm would silently reverse this file's own recorded gated-column contract
  # ("a renamed column must never silently disable the gate"). This is the shape an EXISTING
  # adopter board takes on kit-update, so the FAIL text carries the one-line cure.
  d="$base/bad-ready-missing-metric-column"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Intent | Acceptance | Size | Risk | Type | Owner | Links |
|------|--------|-----------|------|------|------|-------|-------|
| Refine me | some intent | it works | M | low | feature | agent | #99 |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |
EOF
  assert_fail "$d" "required column 'Success metric / hypothesis' not found" \
    "bad-ready-missing-metric-column: content rows, no metric column -> schema-violation FAIL"
  assert_fail "$d" "rows without an honest metric demote" \
    "bad-ready-missing-metric-column: the FAIL names the MIGRATION (the adopter's one-line cure)"

  # good-ready-empty-no-column/ — the column-absent rule's FALSE-FAIL CONTROL and the
  # first-run-green guard: a Ready table with ZERO content rows and NO metric column must still
  # PASS. Nothing is Ready, so nothing needs a metric. Without this leg the absent-column FAIL
  # could be tightened into an unconditional red that breaks every brand-new adopter board.
  d="$base/good-ready-empty-no-column"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Intent | Acceptance | Size | Risk | Type | Owner | Links |
|------|--------|-----------|------|------|------|-------|-------|

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |
EOF
  assert_ok "$d" "good-ready-empty-no-column: zero Ready rows + no metric column -> PASS (first-run-green)"

  # bad-ready-ctrl-header/ — THE SANITIZER, PROVEN ON THE PATH THAT ECHOES HEADER CELLS. The
  # column-missing FAIL interpolates the header's own column names, which are board-author bytes
  # reaching a terminal and a CI log. MEASURED before this leg existed: a `\033[2K\033[1A`
  # (erase-line + cursor-up) pasted into a Ready header cell reached stdout VERBATIM — two ESC
  # bytes — so a board could rewrite the line above its own verdict. The board is written with
  # printf, not a quoted here-doc, because a here-doc cannot carry a raw ESC.
  d="$base/bad-ready-ctrl-header"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  printf '# B\n## Ready\n\n| Item | Owner\033[2K\033[1A | Links |\n|------|-------|-------|\n| x | a | #1 |\n\n## In Progress\n\n| Item | Owner | Started | Links |\n|------|-------|---------|-------|\n| | | | |\n\n## In Review\n\n| Item | Reviewer | PR |\n|------|----------|----|\n| | | |\n' > "$d/BACKLOG.md"
  assert_fail "$d" "required column 'Success metric / hypothesis' not found" \
    "bad-ready-ctrl-header: control bytes in a Ready header -> still FAILs on the missing column"
  assert_no_ctrl "$d" \
    "bad-ready-ctrl-header: the column-missing FAIL echoes header cells with control bytes STRIPPED"

  # bad-ready-ctrl-cell/ — the sibling path: the per-row FAIL echoes the ITEM cell and the METRIC
  # cell. Same untrusted bytes, same sanitizer, a different call site — so neither can regress
  # while the other stays covered.
  d="$base/bad-ready-ctrl-cell"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  printf '# B\n## Ready\n\n| Item | Owner | Links | Success metric / hypothesis |\n|------|-------|-------|-----------------------------|\n| x\033[2K\033[1A | a | #1 | TBD |\n\n## In Progress\n\n| Item | Owner | Started | Links |\n|------|-------|---------|-------|\n| | | | |\n\n## In Review\n\n| Item | Reviewer | PR |\n|------|----------|----|\n| | | |\n' > "$d/BACKLOG.md"
  assert_fail "$d" "is empty/placeholder" \
    "bad-ready-ctrl-cell: control bytes in a Ready ITEM cell -> still FAILs on the placeholder metric"
  assert_no_ctrl "$d" \
    "bad-ready-ctrl-cell: the per-row FAIL echoes the item cell with control bytes STRIPPED"

  # ===== CHECK-SECTION-RAW-ECHOES — the sanitizer's OTHER SIX call sites ====================
  # The two legs above cover the READY gate. `check_section` — which grades In Progress, In Review
  # and Blocked — echoed board cells RAW at six sites, in direct violation of the security-waiver
  # CONDITION recorded at this file's `_cell_diag` header ("every new FAIL message that echoes cell
  # content goes through here"). Those are untrusted bytes reaching a terminal and a CI log, and the
  # ANSI verdict-rewrite `_cell_diag` exists to prevent was reachable through every gated section
  # except the one that had legs. One fixture face PER SECTION and PER SITE, so no site can regress
  # while another stays covered — and `assert_no_ctrl` is whole-output, so it also catches a site
  # nobody remembered to write a leg for.

  # (i) _cell_diag's own truncation MARKER. A bound that silently drops bytes is a second
  # falsification surface: a crafted 500-char cell whose first 80 characters read as a DIFFERENT,
  # plausible row id would render indistinguishable from a complete value, and the operator would
  # act on the wrong row. Driven directly — four faces, so neither the bound nor the marker can be
  # neutered without a leg noticing.
  _cdlong=$(printf 'x%.0s' $(seq 1 200))
  _cdout=$(_cell_diag "$_cdlong")
  case "$_cdout" in
    *'[truncated]') echo "selftest PASS: _cell_diag marks a truncated cell as truncated" ;;
    *) echo "selftest FAIL: _cell_diag truncated a 200-char cell SILENTLY (out=<$_cdout>) — a crafted prefix would read as a complete, different row id"; st_fail=1 ;;
  esac
  _cdout=$(_cell_diag "short cell")
  if [ "$_cdout" = "short cell" ]; then
    echo "selftest PASS: _cell_diag leaves an unbounded cell byte-exact (no spurious marker)"
  else
    echo "selftest FAIL: _cell_diag altered a short cell (out=<$_cdout>)"; st_fail=1
  fi
  _cdout=$(_cell_diag "$(printf 'a\033[2Kb')")
  case "$_cdout" in
    *'[truncated]') echo "selftest FAIL: _cell_diag marked a SHORT cell as truncated after stripping control bytes — the marker must describe the cut, not the strip"; st_fail=1 ;;
    *) echo "selftest PASS: _cell_diag's marker describes the CUT, not the control-byte strip" ;;
  esac
  _cdout=$(_cell_diag "$_cdlong")
  if printf '%s' "$_cdout" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    echo "selftest FAIL: _cell_diag's truncation marker introduced a control byte"; st_fail=1
  else
    echo "selftest PASS: _cell_diag's marker carries no control byte of its own"
  fi

  # (ii) the JOINED-HEADER BOUND, applied per CELL and not to the join. `header_cols` returns a
  # comma-joined list, and bounding the JOIN at 80 characters is the wrong bound: a board with many
  # SHORT columns has its diagnostic cut after the third or fourth name, so the operator is told
  # "columns present: A, B, C…[truncated]" and never learns which column they actually misspelled —
  # while the hostile input the bound exists for (ONE enormous cell) is what it should be cutting.
  # The bound belongs on the cell. Assert the LAST column name survives a long-but-many-short header.
  _hdrmany='| Item | Owner | Started | Assignee | Reviewer | Milestone | Estimate | Priority | Zebra |'
  _hcout=$(_header_cols_diag "$_hdrmany")
  case "$_hcout" in
    *Zebra*) echo "selftest PASS: the header diagnostic bounds each COLUMN, so a many-column board still names its last column" ;;
    *) echo "selftest FAIL: the header diagnostic bounded the JOINED list — the last column was cut away (out=<$_hcout>)"; st_fail=1 ;;
  esac
  _hcout=$(_header_cols_diag "| Item | $(printf 'y%.0s' $(seq 1 200)) |")
  case "$_hcout" in
    *'[truncated]') echo "selftest PASS: the header diagnostic still bounds a single ENORMOUS column name" ;;
    *) echo "selftest FAIL: an enormous column name was printed unbounded (len=$(printf '%s' "$_hcout" | wc -c))"; st_fail=1 ;;
  esac

  # (iii) bad-progress-ctrl-cell/ — site: the In Progress 'Links' per-row FAIL (echoes item + cell).
  d="$base/bad-progress-ctrl-cell"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  printf '# B\n## Ready\n\n| Item | Owner | Links | Success metric / hypothesis |\n|------|-------|-------|-----------------------------|\n| x | a | #1 | m |\n\n## In Progress\n\n| Item | Owner | Started | Links |\n|------|-------|---------|-------|\n| p\033[2K\033[1A | a | 2026-07-01 |  |\n\n## In Review\n\n| Item | Reviewer | PR |\n|------|----------|----|\n| | | |\n' > "$d/BACKLOG.md"
  assert_fail "$d" "is empty/bare" \
    "bad-progress-ctrl-cell: control bytes in an In Progress ITEM cell -> still FAILs on the empty Links"
  assert_no_ctrl "$d" \
    "bad-progress-ctrl-cell: the In Progress per-row FAIL echoes the cells with control bytes STRIPPED"

  # (iv) bad-review-ctrl-cell/ — site: the In Review 'PR' per-row FAIL.
  d="$base/bad-review-ctrl-cell"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  printf '# B\n## Ready\n\n| Item | Owner | Links | Success metric / hypothesis |\n|------|-------|-------|-----------------------------|\n| x | a | #1 | m |\n\n## In Progress\n\n| Item | Owner | Started | Links |\n|------|-------|---------|-------|\n| | | | |\n\n## In Review\n\n| Item | Reviewer | PR |\n|------|----------|----|\n| r\033[2K\033[1A | a |  |\n' > "$d/BACKLOG.md"
  assert_fail "$d" "must be a real PR link" \
    "bad-review-ctrl-cell: control bytes in an In Review ITEM cell -> still FAILs on the missing PR"
  assert_no_ctrl "$d" \
    "bad-review-ctrl-cell: the In Review per-row FAIL echoes the cells with control bytes STRIPPED"

  # (v) bad-blocked-ctrl-cell/ — site: the Blocked 'Blocked on' per-row FAIL.
  d="$base/bad-blocked-ctrl-cell"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  printf '# B\n## Ready\n\n| Item | Owner | Links | Success metric / hypothesis |\n|------|-------|-------|-----------------------------|\n| x | a | #1 | m |\n\n## In Progress\n\n| Item | Owner | Started | Links |\n|------|-------|---------|-------|\n| | | | |\n\n## In Review\n\n| Item | Reviewer | PR |\n|------|----------|----|\n| | | |\n\n## Blocked\n\n| Item | Blocked on | Since | Event-retro link |\n|------|-----------|-------|------------------|\n| b\033[2K\033[1A |  | 2026-07-02 | |\n' > "$d/BACKLOG.md"
  assert_fail "$d" "Blocked on is empty/bare" \
    "bad-blocked-ctrl-cell: control bytes in a Blocked ITEM cell -> still FAILs on the empty blocker"
  assert_no_ctrl "$d" \
    "bad-blocked-ctrl-cell: the Blocked 'Blocked on' FAIL echoes the cells with control bytes STRIPPED"

  # (vi) bad-since-ctrl-cell/ — site: the Blocked 'Since' per-row FAIL (a DIFFERENT echo from (v)).
  d="$base/bad-since-ctrl-cell"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  printf '# B\n## Ready\n\n| Item | Owner | Links | Success metric / hypothesis |\n|------|-------|-------|-----------------------------|\n| x | a | #1 | m |\n\n## In Progress\n\n| Item | Owner | Started | Links |\n|------|-------|---------|-------|\n| | | | |\n\n## In Review\n\n| Item | Reviewer | PR |\n|------|----------|----|\n| | | |\n\n## Blocked\n\n| Item | Blocked on | Since | Event-retro link |\n|------|-----------|-------|------------------|\n| s\033[2K\033[1A | waiting on legal |  | |\n' > "$d/BACKLOG.md"
  assert_fail "$d" "Since is empty/bare" \
    "bad-since-ctrl-cell: control bytes in a Blocked ITEM cell -> still FAILs on the empty Since"
  assert_no_ctrl "$d" \
    "bad-since-ctrl-cell: the Blocked 'Since' FAIL echoes the cells with control bytes STRIPPED"

  # (vii) bad-progress-ctrl-hdr/ — site: the 'required column not found' FAIL, which echoes the
  # HEADER cells (`columns present: …`). A different echo from every per-row site above.
  d="$base/bad-progress-ctrl-hdr"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  printf '# B\n## Ready\n\n| Item | Owner | Links | Success metric / hypothesis |\n|------|-------|-------|-----------------------------|\n| x | a | #1 | m |\n\n## In Progress\n\n| Item | Owner\033[2K\033[1A | Started | Hyperlinks |\n|------|-------|---------|-------|\n| p | a | 2026-07-01 | #1 |\n\n## In Review\n\n| Item | Reviewer | PR |\n|------|----------|----|\n| | | |\n' > "$d/BACKLOG.md"
  assert_fail "$d" "required column 'Links' not found" \
    "bad-progress-ctrl-hdr: control bytes in an In Progress HEADER -> still FAILs on the renamed column"
  assert_no_ctrl "$d" \
    "bad-progress-ctrl-hdr: the column-missing FAIL echoes header cells with control bytes STRIPPED"

  # (viii) bad-since-ctrl-hdr/ — site: the SECOND 'required column not found' FAIL, the one guarding
  # the Blocked gate's second column. It is a separate echo of `_found` and had no coverage at all.
  d="$base/bad-since-ctrl-hdr"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  printf '# B\n## Ready\n\n| Item | Owner | Links | Success metric / hypothesis |\n|------|-------|-------|-----------------------------|\n| x | a | #1 | m |\n\n## In Progress\n\n| Item | Owner | Started | Links |\n|------|-------|---------|-------|\n| | | | |\n\n## In Review\n\n| Item | Reviewer | PR |\n|------|----------|----|\n| | | |\n\n## Blocked\n\n| Item | Blocked on | When\033[2K\033[1A | Event-retro link |\n|------|-----------|-------|------------------|\n| b | waiting | 2026-07-02 | |\n' > "$d/BACKLOG.md"
  assert_fail "$d" "required column 'Since' not found" \
    "bad-since-ctrl-hdr: control bytes in a Blocked HEADER -> still FAILs on the renamed 'Since'"
  assert_no_ctrl "$d" \
    "bad-since-ctrl-hdr: the second column-missing FAIL echoes header cells with control bytes STRIPPED"

  # bad-inprogress-qmark/ — THE WIDENING, FIXTURED ON A SECOND CALLER. Extending is_bare_na with
  # `?` widens EVERY gated cell, not just the Ready metric, and until this leg the three older
  # callers (Links, PR, Blocked on/Since) had no coverage of it at all. HONEST: this leg is green
  # the moment the extension lands, so it detects no present defect — it exists so the widening's
  # blast radius is asserted somewhere rather than merely described in a comment. Measured live:
  # reverting the `?` flips this leg AND bad-ready-qmark-metric, which is the point.
  d="$base/bad-inprogress-qmark"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | ? |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |
EOF
  assert_fail "$d" "In Progress item 'Add login'" \
    "bad-inprogress-qmark: a bare '?' in Links -> FAIL (the is_bare_na widening reaches the older callers)"

  # bad-missing-section/ — a missing required `## In Review` heading -> FAIL.
  d="$base/bad-missing-section"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |
EOF
  assert_fail "$d" "missing required '## In Review' section" "bad-missing-section: no In Review heading -> FAIL"

  # bad-renamed-inprogress-col/ — In Progress renames 'Links' to 'Evidence' + an unlinked
  # active row. The gated column is ABSENT in a GATED section -> schema violation, FAIL
  # (never a silent pass). This is the reproduced defect.
  d="$base/bad-renamed-inprogress-col"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Evidence |
|------|-------|---------|----------|
| Add login | agent | 2026-07-01 |  |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |
EOF
  assert_fail "$d" "In Progress — required column 'Links' not found" "bad-renamed-inprogress-col: 'Links' renamed -> schema-violation FAIL (not silent pass)"

  # bad-renamed-inreview-col/ — In Review renames 'PR' to 'Merge'. Gated column absent -> FAIL.
  d="$base/bad-renamed-inreview-col"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | Merge |
|------|----------|-------|
| Add login | Octocat | #34 |
EOF
  assert_fail "$d" "In Review — required column 'PR' not found" "bad-renamed-inreview-col: 'PR' renamed -> schema-violation FAIL"

  # good-empty-gated-sections/ — every gated section present, ZERO data rows. Legitimately
  # PASSes (an empty board), and the message must show '(0 rows)' so an empty board and a
  # column-missing board never look alike. (Ready carries a real row so the board is in use,
  # not pure-template.)
  d="$base/good-empty-gated-sections"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|

## In Review

| Item | Reviewer | PR |
|------|----------|----|
EOF
  assert_msg "$d" "In Progress→Links (0 rows)" "good-empty-gated-sections: zero data rows -> PASS, message shows (0 rows)"

  # ===== T3 — in-use board: Blocked -> Blocked on + Since (gated only IF present) =========

  # bad-blocked-no-blocker/ — a Blocked row with an EMPTY 'Blocked on' cell -> FAIL. This is
  # the invisible-rot case: an item parked with no named blocker. (Pins the 'Blocked on' gate.)
  d="$base/bad-blocked-no-blocker"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |

## Blocked

| Item | Blocked on | Since | Event-retro link |
|------|-----------|-------|------------------|
| Add SSO |  | 2026-07-02 | |
EOF
  assert_fail "$d" "Blocked on is empty/bare" "bad-blocked-no-blocker: empty 'Blocked on' -> FAIL (invisible rot)"

  # bad-blocked-bare-na/ — a bare 'n/a' (a blank in a costume) in 'Blocked on' -> FAIL.
  d="$base/bad-blocked-bare-na"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |

## Blocked

| Item | Blocked on | Since | Event-retro link |
|------|-----------|-------|------------------|
| Add SSO | n/a | 2026-07-02 | |
EOF
  assert_fail "$d" "Blocked on is empty/bare" "bad-blocked-bare-na: bare 'n/a' Blocked on -> FAIL"

  # bad-blocked-no-since/ — a Blocked row with a named blocker but an EMPTY 'Since' cell ->
  # FAIL. Since must be non-empty so staleness is VISIBLE. (Pins the 'Since' gate.)
  d="$base/bad-blocked-no-since"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |

## Blocked

| Item | Blocked on | Since | Event-retro link |
|------|-----------|-------|------------------|
| Add SSO | vendor SAML metadata |  | |
EOF
  assert_fail "$d" "Since is empty/bare" "bad-blocked-no-since: empty 'Since' -> FAIL (rot must be visible)"

  # bad-renamed-blocked-col/ — Blocked renames 'Blocked on' to 'Depends on'. The gated column
  # is ABSENT in a present gated section -> schema violation, FAIL (never a silent skip-to-pass).
  d="$base/bad-renamed-blocked-col"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |

## Blocked

| Item | Depends on | Since | Event-retro link |
|------|-----------|-------|------------------|
| Add SSO | vendor SAML metadata | 2026-07-02 | |
EOF
  assert_fail "$d" "required column 'Blocked on' not found" "bad-renamed-blocked-col: 'Blocked on' renamed -> schema-violation FAIL"

  # bad-renamed-since-col/ — Blocked renames 'Since' to 'When'. The SECOND gated column is
  # absent -> schema violation, FAIL. (Makes the 'Since' schema-resolution branch non-vacuous;
  # without this, that branch could be deleted and no fixture would notice.)
  d="$base/bad-renamed-since-col"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |

## Blocked

| Item | Blocked on | When | Event-retro link |
|------|-----------|------|------------------|
| Add SSO | vendor SAML metadata | 2026-07-02 | |
EOF
  assert_fail "$d" "required column 'Since' not found" "bad-renamed-since-col: 'Since' renamed -> schema-violation FAIL (second gated column)"

  # good-blocked-na-reason/ — 'Blocked on' = 'N/A — <reason>' (a genuine linkless case:
  # upstream vendor, no tracker) -> PASS, counted as a blocked N/A escape. Since is a real date.
  d="$base/good-blocked-na-reason"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |

## Blocked

| Item | Blocked on | Since | Event-retro link |
|------|-----------|-------|------------------|
| Add SSO | N/A — upstream vendor, no tracker | 2026-07-02 | |
EOF
  assert_msg "$d" "blocked N/A-escapes=1" "good-blocked-na-reason: 'N/A — reason' Blocked on -> PASS (escape counted)"

  # good-no-blocked-section/ — a board that omits '## Blocked' ENTIRELY. Blocked is optional
  # (a blocked item cannot exist without the section), so this must PASS, not FAIL.
  d="$base/good-no-blocked-section"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |
EOF
  assert_ok "$d" "good-no-blocked-section: board omits '## Blocked' -> PASS (Blocked is optional)"

  # ===== T7 — dead-gate defects: is_pure_template header-vs-spacer + fences + backend ====

  # bad-real-row-above-spacer/ — the most natural first adopter edit: keep the shipped Ready
  # `| [title] | … |` example AND drop a real unlinked item into In Progress DIRECTLY ABOVE the
  # shipped `| | | |` spacer. is_pure_template misreads the real row as "a header (row above a
  # separator)" because the spacer matches its empty-cells pattern -> board judged pristine ->
  # N/A having evaluated nothing. A real, active, unlinked row MUST FAIL.
  d="$base/bad-real-row-above-spacer"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links | Success metric / hypothesis |
|------|--------------|---------------------|------|------|------|-------|-------|-----------------------------|
| [title] | [why] | [testable criteria] | S | low | feature | [who] | [spec] | [how we'll know it worked] |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 |  |
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |
EOF
  assert_fail "$d" "In Progress item 'Add login'" "bad-real-row-above-spacer: real unlinked In Progress row above the shipped spacer -> FAIL (board is NOT pristine)"

  # bad-real-inreview-above-spacer/ — the twin: the same shape reproduces in In Review. Ready
  # keeps the shipped `[title]` example; In Review carries a real unlinked row above the spacer.
  d="$base/bad-real-inreview-above-spacer"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links | Success metric / hypothesis |
|------|--------------|---------------------|------|------|------|-------|-------|-----------------------------|
| [title] | [why] | [testable criteria] | S | low | feature | [who] | [spec] | [how we'll know it worked] |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat |  |
| | | |
EOF
  assert_fail "$d" "In Review item 'Add login'" "bad-real-inreview-above-spacer: real unlinked In Review row above the shipped spacer -> FAIL"

  # good-fenced-example/ — a REAL, correctly-linked board that documents an EXAMPLE board inside
  # a ``` fence. The fenced block contains `## In Progress` and an unlinked row. The scanners must
  # skip fenced lines, or that example is parsed as live and the good board spuriously FAILs.
  d="$base/good-fenced-example"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |

## Notes
> An example board for contributors (illustrative, not live):

```
## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Example item | someone | 2026-01-01 |  |
```
EOF
  assert_ok "$d" "good-fenced-example: a fenced example board (unlinked row inside a code fence) is not parsed as live -> PASS"

  # na-fenced-pristine/ — a still-pristine board (Ready `[title]` + empty spacers) that also shows
  # a filled example row INSIDE a ``` fence. is_pure_template must skip fenced lines, else it counts
  # the fenced pseudo-row as real, judges the board "in use", and greens a vacuous OK on a virgin
  # board. Must resolve N/A (board not yet in use) — first-run-green.
  d="$base/na-fenced-pristine"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links | Success metric / hypothesis |
|------|--------------|---------------------|------|------|------|-------|-------|-----------------------------|
| [title] | [why] | [testable criteria] | S | low | feature | [who] | [spec] | [how we'll know it worked] |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |

## Notes
> Example of a filled row (illustrative):

```
| Example item | agent | 2026-01-01 | #99 |
```
EOF
  assert_msg "$d" "board not yet in use" "na-fenced-pristine: a fenced filled-row example does not defeat pristine detection -> N/A"

  # bad-unrecognized-backend/ — an md-board owner MISTYPES the backend (`markdow`). Today it fails
  # open to N/A (dark gate: the gate is silently lost for anyone who mistypes). A non-empty,
  # non-choice-list value that matches NO known token must FAIL, not skip.
  d="$base/bad-unrecognized-backend"; mkdir -p "$d"; _claude_md 'markdow' "$d/CLAUDE.md"
  assert_fail "$d" "unrecognized backlog backend 'markdow'" "bad-unrecognized-backend: a mistyped/unknown backend -> FAIL (never a silent N/A)"

  # ===== S7 — board zero-row schema: empty-state (K10) + one-pass reporting (K11) =========

  # P1 (None.) — an In Review whose body is the bare `None.` idiom (no table) is an EMPTY
  # gated section: nothing to trace -> PASS, trace records '(0 rows, empty)'.
  d="$base/s7-p1-none"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

None.
EOF
  assert_msg "$d" "In Review→PR (0 rows, empty)" "s7/p1-none: 'None.' In Review body -> PASS (0 rows, empty)"

  # P2 (empty) — an In Review heading with a blank body (no table) is likewise EMPTY -> PASS.
  d="$base/s7-p2-empty"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

EOF
  assert_msg "$d" "In Review→PR (0 rows, empty)" "s7/p2-empty: blank In Review body -> PASS (0 rows, empty)"

  # P3 (zero-row table, regression) — the canonical empty form (header+separator, no data
  # rows) still PASSes with the pre-existing '(0 rows)' trace (NOT '(0 rows, empty)').
  d="$base/s7-p3-zerorow"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
EOF
  assert_msg "$d" "In Review→PR (0 rows)" "s7/p3-zerorow: zero-row In Review table -> PASS (0 rows)"

  # N1 (anti-bypass — THE new teeth) — an In Review body that is a bare item line with NO
  # table must STILL FAIL: accepting `None.`/empty weakens nothing, because any non-marker
  # content still demands the schema table. A mutant that accepts it must go RED.
  d="$base/s7-n1-bypass"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

- sneaky item
EOF
  assert_fail "$d" "expected a schema table" "s7/n1-bypass: bare item (no table) in In Review -> FAIL (anti-bypass, schema required)"
  assert_fail "$d" "In Review" "s7/n1-bypass: the anti-bypass FAIL names the offending section (In Review)"

  # N2 (renamed column, existing anti-silent-disable) — a table whose 'PR' is renamed 'Pull'
  # is a schema violation (the gated column is ABSENT), NOT an empty section -> FAIL with the
  # 'required column not found' message (empty-acceptance must NOT swallow this path).
  d="$base/s7-n2-renamed"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | Pull |
|------|----------|------|
| Add login | Octocat | #34 |
EOF
  assert_fail "$d" "required column 'PR' not found" "s7/n2-renamed: 'PR' renamed 'Pull' (table present) -> schema-violation FAIL (not 'empty')"

  # N3 (missing value) — a real In Review row with an empty 'PR' cell -> FAIL (a blank PR is
  # not review-ready). Regression guard: empty-acceptance must not leak into a real row.
  d="$base/s7-n3-missing"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat |  |
EOF
  assert_fail "$d" "must be a real PR link" "s7/n3-missing: empty PR cell on a real row -> FAIL"

  # N4 (one-pass proof — K11) — In Review AND Blocked are BOTH broken (bare item, no table).
  # ONE run's output must contain BOTH section names (accumulate-all, not exit-on-first).
  d="$base/s7-n4-onepass"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

- x

## Blocked

- y
EOF
  assert_fail "$d" "In Review" "s7/n4-onepass: broken In Review is named in the one-pass output"
  assert_fail "$d" "Blocked" "s7/n4-onepass: broken Blocked is named in the SAME one-pass output (accumulate-all)"

  # ===== HITL-3 — Done-edge: a flagged taste-surface must carry a UAT-SIGNOFF reference =========

  # bad-done-flagged-no-uat/ — a Done row flagged [taste-surface] with NO UAT-SIGNOFF reference ->
  # FAIL. THE enforced edge: a taste-surface reaching Done without a recorded sign-off. (Kills the
  # new FAIL-path idiom: neutering its `return` flips this RED->green, failing the selftest.)
  d="$base/bad-done-flagged-no-uat"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|
| Redesign onboarding [taste-surface] | 2026-07-10 | shipped in v1.4; the three-step wizard replaced the single long form and first-week drop-off fell from 38% to 11%. L1 retro in #40. |
EOF
  assert_fail "$d" "carries no UAT-SIGNOFF reference" "bad-done-flagged-no-uat: flagged taste-surface, no UAT ref -> FAIL"

  # good-done-unflagged/ — a Done row with NO taste-surface flag -> N/A for UAT (PASS). Not every
  # Done item touches a taste-surface; an unflagged row must never demand a sign-off (over-gating).
  d="$base/good-done-unflagged"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|
| Fix a typo | 2026-07-10 | corrected a misspelling in the billing footer that shipped in v1.2; reported by a customer, no code path or data affected. L1 retro in #41. |
EOF
  assert_ok "$d" "good-done-unflagged: unflagged Done row -> N/A for UAT (PASS)"

  # good-done-flagged-with-uat/ — a Done row flagged [taste-surface] that DOES carry a UAT-SIGNOFF
  # reference -> PASS, and the flagged row is counted (done-uat-flagged=1), proving the flag was
  # DETECTED and the reference SATISFIED (a green here is not vacuous — the flagged path ran).
  d="$base/good-done-flagged-with-uat"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|
| Redesign onboarding [taste-surface] | 2026-07-10 | shipped behind a flag then ramped to 100% over four days with no rollback; UAT sign-off recorded at docs/uat/UAT-SIGNOFF-onboarding.md. L1 retro in #42. |
EOF
  assert_msg "$d" "done-uat-flagged=1" "good-done-flagged-with-uat: flagged + UAT-SIGNOFF ref -> PASS (flagged row counted)"

  # ===== HITL-6 — a Done item must carry an L1 retro ============================================
  # Two legs with DIFFERENT scopes, both anchored on constants declared outside this board:
  #   leg 1 (substance floor) applies to EVERY Done row;
  #   leg 2 (explicit marker) applies only to rows Closed on/after HITL6_RETRO_EPOCH.
  # The split exists because the 77 rows on this kit's own board predate the marker convention:
  # enforcing it retroactively would demand 72 retrospectives manufactured after the fact, which is
  # the attestation theatre this gate exists to prevent. Measured 2026-07-24: 77 rows, 5 markers,
  # col-3 min 200 chars — so the floor is met by every historical row without any backfill.

  # bad-done-stub-retro/ — a Done row whose Retro/outcome cell is a stub -> FAIL. THE enforced
  # floor, and the cheaper bypass: `| x | date | done |` would otherwise read as a filled retro.
  d="$base/bad-done-stub-retro"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|
| Add login | 2026-01-01 | done |
EOF
  assert_fail "$d" "Retro/outcome cell is too thin" "bad-done-stub-retro: stub retro cell -> FAIL"

  # bad-done-postepoch-no-marker/ — a row Closed ON/AFTER the epoch, with substantial prose but NO
  # 'L1 retro' marker -> FAIL. This is the leg that makes leg 1 more than a length check: the prose
  # here CLEARS the floor, so only the marker rule can red it.
  d="$base/bad-done-postepoch-no-marker"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|
| Add login | 2026-07-25 | shipped to production on the Friday and ramped without incident; the session store moved to Redis and p95 login latency dropped from 410ms to 120ms. |
EOF
  assert_warn "$d" "HITL-6-RETRO" "carries no 'L1 retro' marker" "bad-done-postepoch-no-marker: post-epoch, no marker -> WARN, rc 0 (form, demoted)"
  # The annotation leg (design §2): under GITHUB_ACTIONS=true the same WARN is ALSO a ::warning::.
  assert_warn_annot "$d" "HITL-6-RETRO" on "warn-annot/on: GITHUB_ACTIONS=true -> the WARN is also emitted as ::warning::"
  assert_warn_annot "$d" "HITL-6-RETRO" off "warn-annot/off: GITHUB_ACTIONS unset -> stderr WARN only, no ::warning::"

  # good-done-preepoch-no-marker/ — the SAME row, Closed one day BEFORE the epoch -> PASS. Guards
  # against over-gating the historical rows. HONEST: this leg is green before AND after the gate
  # ships (nothing enforced it previously), so it detects no existing defect — it locks the epoch
  # boundary against a future change that drops the date test and reds 72 historical rows.
  d="$base/good-done-preepoch-no-marker"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|
| Add login | 2026-07-23 | shipped to production on the Friday and ramped without incident; the session store moved to Redis and p95 login latency dropped from 410ms to 120ms. |
EOF
  assert_ok "$d" "good-done-preepoch-no-marker: pre-epoch, no marker -> N/A (PASS)"

  # bad-done-onepoch-no-marker/ — a row Closed EXACTLY ON the epoch (2026-07-24), substantial prose,
  # NO marker -> FAIL. This is the leg that LOCKS the boundary as INCLUSIVE ("on/after"), which is the
  # entire point of the epoch tightening (commit 36bf637 — "so this slice grades itself"). Without it
  # the pre/post fixtures straddle 2026-07-24 but never land on it, so mutating the comparison from
  # `-lt` to `-le` (which would wrongly EXEMPT an on-epoch row) passes the selftest unchanged — an
  # unfalsifiable claim. Verified: this fixture is RED under `-le` and green under the shipped `-lt`.
  d="$base/bad-done-onepoch-no-marker"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|
| Add login | 2026-07-24 | shipped to production on the Friday and ramped without incident; the session store moved to Redis and p95 login latency dropped from 410ms to 120ms. |
EOF
  assert_warn "$d" "HITL-6-RETRO" "carries no 'L1 retro' marker" "bad-done-onepoch-no-marker: ON the epoch, no marker -> WARN (locks >= inclusivity)"

  # bad-done-malformed-date/ — an unparseable Closed cell must FAIL CLOSED (treated as post-epoch),
  # never skipped. Also the BOARD-ROW-ARITY mitigation: a stray '|' shifting columns lands here.
  d="$base/bad-done-malformed-date"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|
| Add login | someday | shipped to production on the Friday and ramped without incident; the session store moved to Redis and p95 login latency dropped from 410ms to 120ms. |
EOF
  assert_warn "$d" "HITL-6-RETRO" "carries no 'L1 retro' marker" "bad-done-malformed-date: unparseable Closed -> still IN scope, WARN (never skipped)"

  # bad-done-missing-column/ — a Done table whose header renames 'Closed' to 'Shipped' -> FAIL. Locks
  # the defensive branch that fails when either graded column is absent (HITL-6 cannot grade a retro
  # without both), which was otherwise an unproven FAIL path.
  d="$base/bad-done-missing-column"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |

## Done

| Item | Shipped | Retro/outcome |
|------|---------|---------------|
| Add login | 2026-07-23 | shipped and ramped without incident; session store moved to Redis and p95 login latency fell from 410ms to 120ms. L1 retro in #77. |
EOF
  assert_fail "$d" "lacks a 'Closed'" "bad-done-missing-column: Done header renames Closed -> FAIL (both graded columns required)"

  # good-done-escaped-pipe/ — a POST-epoch row whose retro cell contains the GFM-correct escaped
  # pipe `\|` -> PASS. Without retro_cell this row parses as NF=7, the marker lands in a shifted
  # field, and a perfectly valid retro is falsely RED. Derived from a REAL row (BACKLOG.md:133,
  # HITL-1), not invented — the plain-cell() parse was measured before this fixture was written.
  d="$base/good-done-escaped-pipe"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| x | a | #1 | login success rate 92% -> 98% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|
| Add login | 2026-07-25 | shipped the `triggered\|none\|uncertain` detector with fail-closed derivation; the escaped pipes here are GFM-correct and must not shift the parse. L1 retro in #99. |
EOF
  # NB: no backticks in this label — inside a double-quoted shell string they are COMMAND
  # SUBSTITUTION, which silently ate the label text on the first version of this line.
  assert_ok "$d" 'good-done-escaped-pipe: GFM escaped pipe in retro cell -> parsed whole (PASS)'

  # ===== HITL-6 leg 3 — EVERY POST-EPOCH RETRO CARRIES A DISPOSITION THAT RESOLVES ============
  # (SLICE-CLOSES-IN-ONE-PR §4.3.) Legs 1-2 prove a retro cell is not a stub and carries a marker —
  # never that a finding went anywhere. Measured 2026-09-03 across this board's 228 Done rows: 62
  # cite a `D-` ruling, 42 say "boarded", ZERO say "no follow-up". A retro that names a lesson and
  # boards nothing was green. Leg 3 requires a `Disposition:` line whose every clause RESOLVES to a
  # real object: a board row, a recorded ruling, or an explicit `none — <reason>`.
  # Scope: rows Closed on/after HITL6_DISPO_EPOCH (backlog-lib.sh), fail-closed on an unparseable date.
  _DR='L1 retro. Shipped on a green first run; the escaped-pipe parse and the epoch boundary were both re-measured against the live board before the push, and nothing needed backfill. '

  # D+ row-clause resolving to a DIFFERENT row that is really on the board -> PASS.
  d="$base/dispo-row-ok"; _dispo_proj "$d" 2026-09-03 "${_DR}Disposition: row \`OTHER-ROW\`"
  assert_ok "$d" "dispo/row-resolves: a row clause naming a real board row -> PASS"

  # D− the clause names a row that is on NO section of the board -> FAIL. The whole point: a
  # disposition is only worth anything if the object it cites exists.
  d="$base/dispo-row-absent"; _dispo_proj "$d" 2026-09-03 "${_DR}Disposition: row \`NO-SUCH-ROW\`"
  assert_fail "$d" "is on no section of the board" "dispo/row-absent: an unboarded row id -> FAIL"

  # D− the clause names the GRADING ROW'S OWN id (security vet H3) -> FAIL. Self-citation is the
  # cheapest way to satisfy a resolver while sending the lesson nowhere.
  d="$base/dispo-row-self"; _dispo_proj "$d" 2026-09-03 "${_DR}Disposition: row \`THE-ROW\`"
  assert_fail "$d" "names its OWN row" "dispo/row-self: a row clause citing its own id -> FAIL"

  # D− an EMPTY backticked id -> FAIL (never treated as "no clause", which would silently pass).
  d="$base/dispo-row-empty"; _dispo_proj "$d" 2026-09-03 "${_DR}Disposition: row \`\`"
  assert_fail "$d" "is not a well-formed row id" "dispo/row-empty: an empty backticked id -> FAIL"

  # D+ a ruling clause whose id appears as an ENTRY HEADER in the project's own DECISIONS.md -> PASS.
  # The path is <project-dir>-relative — BY ARGUMENT, never an env var (threat T3).
  d="$base/dispo-ruling-ok"
  _dispo_proj "$d" 2026-09-03 "${_DR}Disposition: ruling \`D-240903-9\`" \
    '**`D-240903-9` · ruling (owner, 2026-09-03) · THE RULE.**'
  assert_ok "$d" "dispo/ruling-resolves: an entry header in DECISIONS.md -> PASS"

  # D− the same id present ONLY as a cross-reference (measured on the live file: 44 entry headers
  # against 108 backticked mentions) -> FAIL. Mentioning a ruling is not recording one.
  d="$base/dispo-ruling-xref"
  _dispo_proj "$d" 2026-09-03 "${_DR}Disposition: ruling \`D-240903-9\`" \
    'Basis: this supersedes `D-240903-9`, which said otherwise.'
  assert_fail "$d" "is not recorded as an entry header" "dispo/ruling-xref: a cross-reference must not resolve -> FAIL"

  # D− DECISIONS.md absent + a ruling clause -> FAIL NAMING THE PATH (vet H2), never a skip.
  # Adopters stamp their own from templates/DECISIONS-TEMPLATE.md; a missing file is a broken
  # citation, not a not-applicable.
  d="$base/dispo-ruling-nofile"; _dispo_proj "$d" 2026-09-03 "${_DR}Disposition: ruling \`D-240903-9\`"
  assert_fail "$d" "docs/governance/DECISIONS.md" "dispo/ruling-no-file: absent DECISIONS.md -> FAIL naming the path"

  # D+ `none — <reason>` with a reason clearing the non-whitespace floor -> PASS. A stub-detector,
  # not a judgment: whether the reason is honest is the reviewer's, and §5 says so.
  d="$base/dispo-none-ok"; _dispo_proj "$d" 2026-09-03 "${_DR}Disposition: none — a one-line typo fix in a comment; nothing to board and no rule to change."
  assert_ok "$d" "dispo/none-reasoned: 'none —' with a substantive reason -> PASS"

  # D− a reason that is only PADDING -> FAIL. The floor counts NON-WHITESPACE characters precisely
  # so twenty spaces cannot clear it (vet M2).
  d="$base/dispo-none-pad"; _dispo_proj "$d" 2026-09-03 "${_DR}Disposition: none —          x"
  assert_warn "$d" "HITL-6-DISPO" "reason is too thin" "dispo/none-padded: a whitespace-padded reason -> WARN, rc 0 (form, demoted)"

  # D− TWO clauses, one resolving and one not -> FAIL (vet H3). "At least one clause" is a floor on
  # COUNT, never a disjunction on TRUTH: a green here would let any unresolved citation ride along
  # with a valid one.
  d="$base/dispo-mixed"; _dispo_proj "$d" 2026-09-03 "${_DR}Disposition: row \`OTHER-ROW\`, row \`NO-SUCH-ROW\`"
  assert_fail "$d" "is on no section of the board" "dispo/mixed: one resolved + one unresolved -> FAIL"

  # D− a post-epoch row with NO Disposition at all -> FAIL. This is the leg that makes leg 3 more
  # than a syntax check on rows that already carry one.
  d="$base/dispo-absent"; _dispo_proj "$d" 2026-09-03 "$_DR"
  assert_warn "$d" "HITL-6-DISPO" "carries no 'Disposition:'" "dispo/absent: post-epoch row with no Disposition -> WARN, rc 0 (form, demoted)"
  assert_warn_annot "$d" "HITL-6-DISPO" on "warn-annot/dispo-on: GITHUB_ACTIONS=true -> the Disposition WARN is also a ::warning::"

  # D0 a `Disposition:` whose text holds NO recognisable clause -> WARN (form), rc 0.
  d="$base/dispo-noclause"; _dispo_proj "$d" 2026-09-03 "${_DR}Disposition: see the review record"
  assert_warn "$d" "HITL-6-DISPO" "carries no recognisable clause" "dispo/no-clause: a Disposition with no row/ruling/none clause -> WARN, rc 0 (form, demoted)"

  # D− a `Disposition:` that appears only BEFORE the 'L1 retro' marker -> FAIL. The word already
  # occurs in retro prose on the live board, so the parse is anchored after the marker; without
  # this leg an anchorless parse would pass and the anchor would be unfalsifiable.
  d="$base/dispo-before-marker"
  _dispo_proj "$d" 2026-09-03 "Disposition: row \`OTHER-ROW\` was the plan before review. $_DR"
  assert_warn "$d" "HITL-6-DISPO" "carries no 'Disposition:'" "dispo/before-marker: a Disposition before the marker does not count -> WARN (anchor still live)"

  # D+ TWO `Disposition:` occurrences after the marker, the EARLIER one unresolvable and the LATER
  # one valid -> PASS. The header says the LAST occurrence is parsed; without this leg that sentence
  # is unfalsifiable, because `${_dp_after##*Disposition:}` (last) and `${_dp_after#*Disposition:}`
  # (first) agree on every other fixture. Under the `#` mutant this board grades `NO-SUCH-ROW` and
  # reds. Not a licence to leave a bad clause on a row — a superseded draft is diff-visible.
  d="$base/dispo-last-wins"
  _dispo_proj "$d" 2026-09-03 "${_DR}Disposition: row \`NO-SUCH-ROW\` was the draft before review. Disposition: row \`OTHER-ROW\`"
  assert_ok "$d" "dispo/last-wins: the LAST Disposition after the marker is the one graded -> PASS"

  # D− an UNPARSEABLE Closed cell + no Disposition -> FAIL CLOSED (in scope, never skipped), the
  # same posture leg 2 takes.
  d="$base/dispo-baddate"; _dispo_proj "$d" someday "$_DR"
  assert_warn "$d" "HITL-6-DISPO" "carries no 'Disposition:'" "dispo/bad-date: an unparseable Closed date is IN scope -> WARN"

  # D− NO 'L1 retro' marker but a `Disposition:` naming a row on NO section -> FAIL (substance is never
  # excused by the missing marker: D-240930-1 Q2). The marker WARN may fire; the rc must still be 1.
  _NM='Shipped on a green first run; the escaped-pipe parse and the epoch boundary were both re-measured against the live board before the push, and nothing needed backfill. '
  d="$base/dispo-nomarker-dangling"; _dispo_proj "$d" 2026-09-03 "${_NM}Disposition: row \`NOPE\`"
  assert_fail "$d" "is on no section of the board" "dispo/nomarker-dangling: no marker + a dangling row pointer -> still FAIL"

  # D− a THIN `none —` AFTER a dangling row clause -> FAIL: the thin reason is form, but the scan must
  # keep going and resolve the clause before it (an early return would let the pointer ride past).
  d="$base/dispo-thin-none-dangling"; _dispo_proj "$d" 2026-09-03 "${_DR}Disposition: row \`NOPE\`, none — x"
  assert_fail "$d" "is on no section of the board" "dispo/thin-none-dangling: a thin none must not end the scan -> FAIL"

  # WARN-injection hardening (security L-1). A board cell carrying a LITERAL backslash-n then a workflow
  # command must never yield a line that STARTS with `::error::` (dash's echo would expand the `\n`).
  d="$base/warn-inject"; _DISPO_ITEM=' x\n::error::boom'; _dispo_proj "$d" 2026-09-03 "$_DR"; _DISPO_ITEM=''
  assert_warn_no_cmd "$d" "warn-inject: a literal \\n::error:: in a board cell never becomes a workflow command line"
  # The annotation payload is encoded per the workflow-command rules: a `%` in the text is `%25`.
  d="$base/warn-percent"; _DISPO_ITEM=' 100% done'; _dispo_proj "$d" 2026-09-03 "$_DR"; _DISPO_ITEM=''
  assert_warn_annot_has "$d" "100%25 done" "warn-encode: a % in the WARN text appears as %25 in the ::warning:: line"

  # D+ a GFM-correct escaped pipe before the Disposition -> PASS. Without retro_cell the clause
  # lands in a shifted field and a valid row reds.
  d="$base/dispo-escaped"
  _dispo_proj "$d" 2026-09-03 "${_DR}Shipped the \`triggered\\|none\\|uncertain\` detector. Disposition: row \`OTHER-ROW\`"
  assert_ok "$d" "dispo/escaped-pipe: a Disposition after an escaped pipe is still parsed -> PASS"

  # D0 an ESCAPED PIPE IN THE **ITEM** CELL of a PRE-epoch row -> PASS. FOUND ON THE LIVE BOARD
  # (the `B8` row, whose item carries `RELEASE_TAG_PROVENANCE=observe\|enforce`): plain cell() splits
  # on raw pipes, so the Closed column read `enforce\` dial registered…`, the date was unparseable,
  # the fail-closed posture pulled a 2026-08-09 row into leg 3's scope, and a GFM-CORRECT row went
  # red. retro_cell already exists in this family for exactly this class; the Closed read needed the
  # same treatment (gfm_cell). Fail-closed is right — but only for rows that are genuinely unreadable.
  d="$base/dispo-escaped-item"
  _DISPO_ITEM=' registered the `X=observe\|enforce` dial'
  _dispo_proj "$d" 2026-09-02 "$_DR"
  _DISPO_ITEM=''
  assert_ok "$d" "dispo/escaped-item-pipe: an escaped pipe BEFORE the Closed column must not shift the date -> PASS"

  # D0 a PRE-epoch row with no Disposition -> PASS. The epoch boundary, live: without it the 228
  # historical rows would demand 228 dispositions manufactured after the fact — the attestation
  # theatre this gate family exists to prevent.
  d="$base/dispo-preepoch"; _dispo_proj "$d" 2026-09-02 "$_DR"
  assert_ok "$d" "dispo/pre-epoch: a pre-epoch row owes no Disposition -> PASS"

  # ===== BOARD-ROW-ARITY — a body row's column count must match its section header's ======
  # Fixtures live under $base so the ONE trap installed at the top of selftest() cleans them
  # (a second mktemp -d + trap here would REPLACE that trap and leak the whole $base tree —
  # this project has filled its dev machine that way twice).

  # bad-arity-extra/ — a Ready row carrying one column MORE than its header. This is what an
  # unescaped '|' inside a cell does: every later column shifts, so the row's metadata is
  # silently wrong and any positional reader mis-reads it. Measured live on this kit's own board:
  # the Ready row fusing MODEL-TIER-FAILSPAN and CP7R5-BOT-BOARD-BINDING carried 17 columns against
  # its header's 8 (named, not cited by line — a line citation goes stale on the next board edit).
  d="$base/bad-arity-extra"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Intent | Size | Success metric / hypothesis |
|------|--------|------|-----------------------------|
| A | why | S | ships | EXTRA |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |
EOF
  assert_fail "$d" "carries 5 columns but the section header declares 4" \
    "bad-arity-extra: a Ready row with an EXTRA column -> FAIL"

  # bad-arity-missing/ — the other direction: a row SHORT of its header. Locks the comparison
  # as an equality, not a "no more than" (a `>` would let this one through silently).
  # NOTE THE COLUMN ORDER: the Success-metric column is deliberately NOT last here. A short row
  # necessarily loses its TRAILING cells, so with the metric last this board would carry TWO
  # independent defects (a shifted row AND a missing metric) and stop being a single-property
  # fixture. Columns resolve BY NAME, so moving it left costs nothing — and it incidentally
  # proves the metric gate is not position-dependent.
  d="$base/bad-arity-missing"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Success metric / hypothesis | Intent | Size |
|------|-----------------------------|--------|------|
| A | ships | why |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |
EOF
  assert_fail "$d" "carries 3 columns but the section header declares 4" \
    "bad-arity-missing: a Ready row with a MISSING column -> FAIL"

  # bad-arity-double-backslash-pipe/ — BOARD-PIPE-ESCAPE T2, leg 3 (design §6.1 leg 3 / H-2/C2).
  # A Ready row carrying `\\|` (an EVEN backslash run — a REAL GFM delimiter, not an escape) in its
  # Item cell, against a 4-column header. The row is genuinely malformed: `\\|` really does split
  # the cell, so it carries 5 GFM columns against the header's 4 — exactly the metadata-shift arity
  # exists to catch. The pre-T2 `_arity_nf` (`sed 's/\\|//g' | awk NF`) CONTRADICTS the even-run
  # rule: its sed pattern deletes the trailing two bytes of `\\|` as if they were an escaped `\|`,
  # silently removing the real delimiter before counting — so old and new field counts both land on
  # the header's count and the row passes arity vacuously (H3 re-created: the metric gate then reads
  # the WRONG cell of this malformed row — its real column 4 is `#99`, not the metric text). Measured
  # pre-fix: `check_dir` returns rc0/OK on this exact board. This assertion REDS against the
  # unconverted sed idiom (rc0, no FAIL text) and GREENs once `_arity_nf` is `gfm_nf`.
  d="$base/bad-arity-double-backslash-pipe"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links | Success metric / hypothesis |
|------|-------|-------|-----------------------------|
| foo\\|bar | agent | #99 | m |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |
EOF
  assert_fail "$d" "carries 5 columns but the section header declares 4" \
    "bad-arity-double-backslash-pipe: a real \\\\| delimiter inside a cell -> FAIL, not a vacuous PASS"

  # good-arity-exact/ — the positive liveness anchor, COUNTED: three well-formed body rows across
  # three sections, plus a spacer row that must NOT be counted. `board-arity-checked=3` is the
  # anti-vacuity assertion — a check that inspected nothing would report 0 and still exit 0.
  d="$base/good-arity-exact"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Intent | Size | Success metric / hypothesis |
|------|--------|------|-----------------------------|
| A | why | S | signups +10% |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |
EOF
  assert_msg "$d" "board-arity-checked=3" \
    "good-arity-exact: 3 well-formed rows counted, spacer not counted -> PASS"

  # good-arity-escaped-pipe/ — a GFM-ESCAPED pipe inside a cell renders as a literal and does NOT
  # delimit a column, so the row's arity is unchanged and it must PASS. Load-bearing: this row
  # raw-splits to 6 fields against a 5-field header, so dropping the escape-awareness reddens it.
  # MEASURED on this kit's own board as this commit leaves it (2026-07-24), by comparing each row's
  # raw `awk -F'|' NF` against its escape-aware NF: EIGHT rows carry `\|` legitimately — the
  # BOARD-ROW-ARITY and CP7R5-KITOWN-MARKER **Ready** rows, and the HITL-1 / CP7R5-NINE-PROFILES /
  # CP7R5-GATE-AUTHORITY / CP-7-recert-run-5 / CP-8a / P0-FU(a) **Done** rows. Every one of the
  # eight raw-splits WIDER than its section header (14/11 against 10; 7/6/9/7/8/9 against 5), so a
  # raw-pipe count would false-FAIL all eight. Rows are named, never cited by line number — a line
  # citation goes stale on the next board edit (an earlier draft of this comment cited a line that
  # was the Done table's SEPARATOR row).
  d="$base/good-arity-escaped-pipe"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Intent | Size | Success metric / hypothesis |
|------|--------|------|-----------------------------|
| A | guard teardown with \|\| true | S | zero orphaned temp trees |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |
EOF
  assert_ok "$d" 'good-arity-escaped-pipe: GFM escaped pipes do not delimit -> arity unchanged (PASS)'

  # bad-arity-empty-item/ — THE EVASION. The spacer skip was `[ -z "$(cell "$_row" 1)" ]`, which
  # swallowed ANY row with an empty Item cell — so a mis-shaped row that simply leaves Item blank
  # reported `board-arity-checked=0` and exited 0: shipped green, and not even COUNTED. The skip is
  # now a TRUE-spacer test (EVERY cell empty), so a row carrying content anywhere is graded and
  # named by its first non-empty cell. VERIFIED before tightening: every empty-Item row on this
  # kit's live board (3) and in templates/BACKLOG-TEMPLATE.md (3) is an all-cells-empty spacer, so
  # the narrowing false-FAILs neither.
  d="$base/bad-arity-empty-item"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Intent | Size | Success metric / hypothesis |
|------|--------|------|-----------------------------|
| | why | S | ships | EXTRA |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |
EOF
  assert_fail "$d" "row 'why' carries 5 columns but the section header declares 4" \
    "bad-arity-empty-item: an empty Item cell no longer buys a skip -> FAIL (named by first non-empty cell)"

  # bad-arity-two/ — the ACCUMULATE-ALL contract the header claims, PROVEN: two mis-shaped rows in
  # ONE section must BOTH be named in ONE run (never exit-on-first — fix ALPHA, re-run, only THEN
  # discover BETA). Same shape as s7/n4-onepass, one level down (rows within a section, not
  # sections within a board).
  d="$base/bad-arity-two"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Success metric / hypothesis | Intent | Size |
|------|-----------------------------|--------|------|
| ALPHA | ships | why | S | EXTRA |
| BETA | ships | why |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |
EOF
  assert_fail "$d" "row 'ALPHA' carries 5 columns" \
    "bad-arity-two: the FIRST mis-shaped row is named"
  assert_fail "$d" "row 'BETA' carries 3 columns" \
    "bad-arity-two: the SECOND mis-shaped row is named in the SAME run (accumulate-all)"

  # bad-arity-blind/ — the VACUOUS-GREEN FLOOR. A gate that inspects NOTHING must never report OK.
  # Here the six graded sections are all empty while the board tracks its items in a SEVENTH
  # table-bearing section (`## Shipped`) — the silent-coverage-loss shape: `board-arity-checked=0`
  # on a board that plainly carries rows. Without the floor this exits 0 and the `=3` count
  # assertion above lives only inside a fixture, never on a real board.
  d="$base/bad-arity-blind"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Intent | Size |
|------|--------|------|

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |

## Shipped

| Item | Closed | Notes |
|------|--------|-------|
| A | 2026-07-01 | shipped |
EOF
  assert_fail "$d" "inspected 0 rows on a board that carries 1 content-bearing table row" \
    "bad-arity-blind: 0 rows inspected on a board that HAS rows -> FAIL (vacuous-green floor)"

  # good-arity-empty-board/ — the floor's other side, and its false-FAIL control: a genuinely EMPTY
  # board (zero-row schema tables + all-cells-empty spacers, nothing else) legitimately inspects 0
  # rows and must still PASS. Without this leg the floor could be tightened into an unconditional
  # `checked==0 -> FAIL`, which would red every brand-new adopter board on its first run and break
  # the incept first-run-green invariant this check is built to protect.
  d="$base/good-arity-empty-board"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Intent | Size |
|------|--------|------|

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |
EOF
  assert_msg "$d" "board-arity-checked=0" \
    "good-arity-empty-board: a truly empty board inspects 0 rows and still PASSES (floor does not false-FAIL)"

  # arity-section-set/ — the ENUMERATION LOCK. check_row_arity hardcodes its six sections (on
  # purpose: a set derived from the board under test can be satisfied by DELETING a section). But
  # nothing tied that constant to the shipped schema, so adding a seventh state section to
  # templates/BACKLOG-TEMPLATE.md would ship it arity-UNCHECKED with no signal — silent coverage
  # loss. This leg compares two INDEPENDENT artifacts: the actual call sites in this script's own
  # source ($0 — the mutant copy under the non-vacuity harness, so mutating a call site kills it)
  # against the template's table-bearing `^## ` headings. `Backlog (unrefined)` is a list and
  # `How to use` is prose — neither bears a table, so both are correctly absent from the set.
  _ra_tpl=$(_find_template) || { echo "selftest FAIL: arity-section-set cannot locate templates/BACKLOG-TEMPLATE.md"; st_fail=1; _ra_tpl=/dev/null; }
  _ra_have=$(sed -n 's/^[[:space:]]*_arity_one_section "[^"]*" "\([^"]*\)".*/\1/p' "$0" | sort)
  _ra_want_set=$(awk '
    /^##[[:space:]]/ { if (sec != "" && has) print sec
                       sec=$0; sub(/^##[[:space:]]+/,"",sec); sub(/[[:space:]]+$/,"",sec); has=0; next }
    /^[[:space:]]*\|/ { has=1 }
    END { if (sec != "" && has) print sec }
  ' "$_ra_tpl" | sort)
  if [ -n "$_ra_have" ] && [ "$_ra_have" = "$_ra_want_set" ]; then
    echo "selftest PASS: arity-section-set: the enumerated sections equal the template's table-bearing state sections"
  else
    echo "selftest FAIL: arity-section-set: enumerated=<$(printf '%s' "$_ra_have" | tr '\n' ',')> template=<$(printf '%s' "$_ra_want_set" | tr '\n' ',')>"
    st_fail=1
  fi

  # ===== T-RID — the ROW-ID GRAMMAR and the COUNTING seam (BOARD-ROW-IDENTIFIER) ==========
  # row_id_ok and row_count live in backlog-lib.sh (sourced, never run, and therefore never
  # mutated by non-vacuity.sh — see that file's own MUTATION COVERAGE disclosure). They are
  # graded HERE, behaviourally, by the gate that used to own backtick_id/row_exists, because
  # this is the selftest surface that already sources the library. Watched red against the
  # mutants named in the design §6 before the code existed.
  assert_rid_ok  "KW6-A2"           "rid/accept-alnum-dash: KW6-A2 is a well-formed row id"
  assert_rid_ok  "X"                "rid/accept-single-upper: a one-character id is well-formed"
  assert_rid_bad "kw6"              "rid/refuse-lowercase: kw6 is refused (the grammar is upper-case)"
  assert_rid_bad "A/B"              "rid/refuse-slash: A/B is refused (it would escape a ref name)"
  assert_rid_bad "-A"               "rid/refuse-leading-dash: -A is refused (option injection)"
  assert_rid_bad ""                 "rid/refuse-empty: the empty token is refused"

  # THE TWIN IS GATED (reviewer R3). `scripts/board-claim.sh::bc_row_ok` is a deliberate SECOND
  # implementation of this grammar — that script cannot source a conformance/ library, because its
  # own selftest drives it inside throwaway clones that carry a BACKLOG.md and nothing else — and
  # the round-1 review's question was exactly right: a disclosure comment saying "nothing greps
  # these two against each other" is a confession, not a control. This leg is the control. It
  # extracts the `case` BODY of each function and compares them byte for byte, so a change to
  # either arm reds here, in the gate that owns the grammar, on the same run that proves it.
  # It compares BODIES, not whole functions: the names differ by design (one is namespaced to the
  # script that must stay standalone), and pinning the names would make the leg fail for a
  # difference that carries no meaning.
  _rid_body() {  # <file> <function-name> -> the case arms, whitespace-normalised
    awk -v fn="$2" '
      $0 ~ "^" fn "\\(\\) \\{" { inf=1; next }
      inf && /^\}/ { exit }
      inf { gsub(/^[ \t]+|[ \t]+$/,""); if ($0 != "") print }
    ' "$1"
  }
  _rid_lib=$(_rid_body "$(dirname "$0")/backlog-lib.sh" "row_id_ok")
  _rid_bc=$(_rid_body "$(dirname "$0")/../scripts/board-claim.sh" "bc_row_ok")
  if [ -z "$_rid_lib" ] || [ -z "$_rid_bc" ]; then
    echo "selftest FAIL: rid/twin: could not extract one of the two row-id grammars (lib=$(printf '%s' "$_rid_lib" | wc -l) bc=$(printf '%s' "$_rid_bc" | wc -l)) — the leg cannot pass vacuously"; st_fail=1
  elif [ "$_rid_lib" = "$_rid_bc" ]; then
    echo "selftest PASS: rid/twin: backlog-lib.sh::row_id_ok and scripts/board-claim.sh::bc_row_ok are byte-identical"
  else
    echo "selftest FAIL: rid/twin: the two row-id grammars have DRIFTED — an id one accepts the other may refuse, and a claim that cannot be made for a row that resolves is the worst of both"; st_fail=1
    echo "  backlog-lib.sh::row_id_ok:  <$(printf '%s' "$_rid_lib" | tr '\n' ';')>"
    echo "  board-claim.sh::bc_row_ok:  <$(printf '%s' "$_rid_bc" | tr '\n' ';')>"
  fi

  # row_count over three fixture boards: absent (0), unique (1), duplicated (2).
  d="$base/t_rid_boards"; mkdir -p "$d"
  _good_board "$d/one.md"
  sed 's/| Add login | ship auth |/| `ONE-ROW` — Add login | ship auth |/' "$d/one.md" > "$d/uniq.md"
  sed 's/| Add login | agent | 2026-07-01 |/| `ONE-ROW` — Add login | agent | 2026-07-01 |/' "$d/uniq.md" > "$d/dup.md"
  assert_rowcount "$d/uniq.md" "ONE-ROW" 1 "rid/count-one: an id in exactly one Item cell counts 1"
  assert_rowcount "$d/dup.md"  "ONE-ROW" 2 "rid/count-two: the same id on two rows counts 2 (the AMBIGUOUS subject)"
  assert_rowcount "$d/uniq.md" "NO-SUCH-ROW" 0 "rid/count-zero: an id on no row counts 0"
  # THE LOAD-BEARING NEGATIVE for the whole slice's premise: a token that occurs in the board's
  # TEXT but is not a row's Item-cell id counts 0. `a` is a substring of `Add login`.
  assert_rowcount "$d/uniq.md" "a" 0 "rid/count-substring: a bare substring of the board counts 0 rows"

  # ===== PREPUSH-CORE-DEFAULT — the one-pass id index must answer exactly as row_exists =========
  # row_in_index(row_id_index B) is a faster route to row_exists's answer and MUST NOT diverge from
  # it. Every id is graded against BOTH and against a hand-stated <want>, so a pair of equally wrong
  # answers (both always-true, both always-false) cannot pass. RED shapes: an index that is always
  # true fails every absent/near-miss leg; always false (or an empty index) fails every present leg;
  # a substring/regex match fails the near-miss and the `.`-metacharacter legs.
  d="$base/t_rid_index"; mkdir -p "$d"
  # NB: the last heading is `## Backlog unrefined` ON PURPOSE: row_count passes "Backlog (unrefined)" to
  # section_rows, whose awk treats the parens as an ERE GROUP, so the live heading "(unrefined)" never
  # matches and that section is invisible to row_exists today. The index mirrors that quirk; the fixture
  # uses the spelling the pattern really matches so all seven walked sections are exercised.
  cat > "$d/multi.md" <<'EOF'
# Proj — Backlog

## Ready

| Item | Owner |
|------|-------|
| `ALPHA-1` — first | agent |

## In Progress

| Item | Owner |
|------|-------|
| `BETA-2` — second | agent |
| | |

## In Review

| Item | Reviewer |
|------|----------|
| `GAMMA-3` — third | me |

## Blocked

| Item | Blocked on |
|------|------------|
| `DELTA-4` — fourth | dep |

## Released

| Item | Released |
|------|----------|
| `EPS-5` — fifth | 2026-07-01 |

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|
| `ZETA.6` — sixth | 2026-07-01 | done |

## Backlog unrefined

| Item | Notes |
|------|-------|
| `ETA-7` — seventh | idea |
EOF
  # a second board: ALPHA-1 gone, OMEGA-9 new, the rest identical
  sed -e '/ALPHA-1/d' -e 's/| `ETA-7` — seventh | idea |/| `ETA-7` — seventh | idea |\
| `OMEGA-9` — new | idea |/' "$d/multi.md" > "$d/other.md"
  assert_idx() {   # <board> <id> <want 0|1> <label>
    if row_exists "$1" "$2"; then _ix_re=1; else _ix_re=0; fi
    _ix_idx=$(row_id_index "$1")
    if row_in_index "$_ix_idx" "$2"; then _ix_ri=1; else _ix_ri=0; fi
    if [ "$_ix_re" = "$3" ] && [ "$_ix_ri" = "$3" ]; then echo "selftest PASS: $4"
    else echo "selftest FAIL: $4 (row_exists=$_ix_re row_in_index=$_ix_ri want=$3)"; st_fail=1; fi
  }
  for _ix_id in ALPHA-1 BETA-2 GAMMA-3 DELTA-4 EPS-5 ZETA.6 ETA-7; do
    assert_idx "$d/multi.md" "$_ix_id" 1 "rid/index-parity: $_ix_id (one section each, all seven) resolves through the index as through row_exists"
  done
  for _ix_id in NO-SUCH-ROW OMEGA-9 ALPH ALPHA-1X LPHA-1 ZETAX6 A; do
    assert_idx "$d/multi.md" "$_ix_id" 0 "rid/index-parity-absent: '$_ix_id' (absent, prefix/suffix/near-miss or regex-lookalike) is absent through the index as through row_exists"
  done
  assert_idx "$base/t_rid_boards/uniq.md" "ONE-ROW" 1 "rid/index-parity: the uniq fixture's id resolves through the index"
  assert_idx "$base/t_rid_boards/dup.md"  "ONE-ROW" 1 "rid/index-parity: a duplicated id still EXISTS through the index (existence, never uniqueness)"
  assert_idx "$base/t_rid_boards/one.md"  "ONE-ROW" 0 "rid/index-parity: a board with no backticked ids resolves nothing"
  # Stale-index guard: _dispo_row_exists (the cached lookup check_dispo uses) called on DIFFERENT
  # boards in sequence in THIS shell must answer for the board it is given. RED: a cache keyed on
  # nothing (or on a constant) answers the second board from the first board's index.
  assert_cached() {   # <board> <id> <want 0|1> <label>
    if _dispo_row_exists "$1" "$2"; then _ix_c=1; else _ix_c=0; fi
    if [ "$_ix_c" = "$3" ]; then echo "selftest PASS: $4"
    else echo "selftest FAIL: $4 (cached lookup=$_ix_c want=$3)"; st_fail=1; fi
  }
  assert_cached "$d/multi.md" ALPHA-1 1 "rid/index-stale-1: first board answers its own row"
  assert_cached "$d/other.md" ALPHA-1 0 "rid/index-stale-2: the SECOND board does not inherit the first board's index"
  assert_cached "$d/other.md" OMEGA-9 1 "rid/index-stale-3: the second board's own new row resolves"
  assert_cached "$d/multi.md" OMEGA-9 0 "rid/index-stale-4: switching back drops the second board's row"
  # Same PATH, new CONTENT (a fixture rewritten in place): the key carries a content checksum.
  cp "$d/other.md" "$d/rewrite.md"
  assert_cached "$d/rewrite.md" ALPHA-1 0 "rid/index-stale-5: a board path read before the rewrite"
  cp "$d/multi.md" "$d/rewrite.md"
  assert_cached "$d/rewrite.md" ALPHA-1 1 "rid/index-stale-6: the SAME path rewritten with new content is re-indexed"

  # ===== TBG-READER-FLAGS-LIST T9 — the `backlog-current` tracker arm (design §3e/§3f, P-4) =====
  # H-1: every record below is produced by the REAL, unmodified tracker-read.sh/tracker-conf.sh
  # (never a hand-authored fixture) through a throwaway root this leg builds at test time — mirrors
  # loop-state.sh's own H-1 round-trip idiom (~:2523). The fake tracker-jira.sh is ONE script whose
  # per-case behaviour is driven entirely by env vars (never a different inline printf shape per
  # case). Every conf below sets its OWN list_cap — the T9 orchestrator note: the SHARED
  # conformance/fixtures/tracker-jira/ conf carries none and would omit every list; never reused.
  # T10-harden-B D2: the reader (T5d) now maps field.risk for real (customfield_N/description ->
  # field-empty; label:<p> -> label-counts, the same closed dispatch every other dor-* flag uses) —
  # every leg below gets dor-risk from a REAL round trip (field.risk=customfield_10088 on the fake
  # adapter's field-empty answer), never a backfilled copy. The former HONEST GAP no longer applies.
  _t9dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
  _t9head="24ceb345e6d66bb5c4702c947a9de7a862e65a74"   # this task's own throwaway git commit (T9)
  _t9_ops="$_t9dir/conformance/fixtures/tracker-jira/ops"   # B4 drift lock

  # B4 drift lock: status-ids and the present-empty list case now `cat` the SAME adapter-proven
  # ops/*.out files T2/T3/T5/T8 prove against the real adapter (never an inline printf for a shape
  # a tracked file already covers). get-issue also carries assignee-present now (the real adapter's
  # shape). The other per-leg shapes below (a single subject id's list/field-empty/label-counts)
  # have NO tracked .out fixture — every tracked fixture here is a multi-id shape (field-empty.out:
  # AB-2+AB-3; label-counts.out: AB-1..AB-4; list-cloud*.out: 2-5 ids) — so they stay inline printfs,
  # named per branch below (the exception the brief allows; boarded for the owner).
  cat > "$base/t9-adapter.sh" <<'EOF9ADAPTER'
#!/bin/sh
case "$1" in
  get-issue) printf 'key\t%s\n' "$T9_KEY"; printf 'status-id\t%s\n' "$T9_STATUSID"; printf 'status-name\t%s\n' "$T9_STATUSNAME"; printf 'assignee-present\ttrue\n' ;;
  permissions) echo ok ;;
  status-ids) cat "$T9_OPS/status-ids-cloud.out" ;;
  list-in-states)
    if [ -n "${T9_LISTRC:-}" ]; then exit "$T9_LISTRC"; fi
    if [ -z "${T9_LIST:-}" ]; then cat "$T9_OPS/list-cloud-empty.out"; exit 0; fi
    # B4 exception: every non-empty case here is a single-subject id — no tracked .out fixture
    # is a single-id list (list-cloud-ready.out is AB-2+AB-3) — stays an inline printf.
    printf '%s\n' "$T9_LIST"
    ;;
  field-empty)
    # B4 exception: no tracked field-empty .out fixture matches this task's single-subject
    # empty/non-empty shapes (field-empty.out is the two-id AB-2/AB-3 shape) — stays inline.
    case "$5" in
      description) if [ -n "${T9_ACC:-}" ]; then printf '%s\n' "$T9_ACC"; fi ;;
      customfield_10077) if [ -n "${T9_MET:-}" ]; then printf '%s\n' "$T9_MET"; fi ;;
      customfield_10088) if [ -n "${T9_RISK:-}" ]; then printf '%s\n' "$T9_RISK"; fi ;;
    esac
    ;;
  # B4 exception: no tracked label-counts .out fixture matches this task's single-subject shape
  # (label-counts.out lists four ids AB-1..AB-4) — stays inline.
  label-counts) if [ -n "${T9_SIZE:-}" ]; then printf '%s\n' "$T9_SIZE"; fi ;;
esac
exit 0
EOF9ADAPTER

  # _t9_round <name> <statusid> <statusname> <list> <listrc> <acc> <met> <size> <field.metric-val>
  #   <risk> -> builds a throwaway root, runs the REAL reader (its own public CLI), sets
  #   $_t9_root/$_t9_rec. <risk> is the field-empty "empty" id list for field.risk=customfield_10088
  #   (D2: a real dor-risk round trip, never a backfill) — "" means dor-risk=yes for AB-2.
  _t9_round() {
    _t9n=$1; _t9sid=$2; _t9sname=$3; _t9list=$4; _t9lrc=$5; _t9acc=$6; _t9met=$7; _t9size=$8; _t9metconf=$9
    shift 9; _t9risk=$1
    _t9_root="$base/t9_$_t9n"; mkdir -p "$_t9_root/scripts" "$_t9_root/.kit"
    cp "$_t9dir/scripts/tracker-read.sh" "$_t9_root/scripts/tracker-read.sh"
    cp "$_t9dir/scripts/tracker-conf.sh" "$_t9_root/scripts/tracker-conf.sh"
    cp "$base/t9-adapter.sh" "$_t9_root/scripts/tracker-jira.sh"
    printf -- '- **Backlog backend**: Jira\n' > "$_t9_root/CLAUDE.md"
    cat > "$_t9_root/.kit/tracker.conf" <<EOF9CONF
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.ready=Selected
state.in-progress=In Progress
field.acceptance=description
field.metric=$_t9metconf
field.size=label:size
field.risk=customfield_10088
EOF9CONF
    _t9_rec="$_t9_root/record.txt"
    _t9_rc=0
    T9_KEY=AB-2 T9_STATUSID="$_t9sid" T9_STATUSNAME="$_t9sname" T9_LIST="$_t9list" T9_LISTRC="$_t9lrc" \
      T9_ACC="$_t9acc" T9_MET="$_t9met" T9_SIZE="$_t9size" T9_RISK="$_t9risk" T9_OPS="$_t9_ops" \
      KIT_TRACKER_USER="user@example.com" KIT_TRACKER_TOKEN="s3cr3t" \
      sh "$_t9_root/scripts/tracker-read.sh" "$_t9_root/.kit/tracker.conf" - "$_t9_rec" AB-2 "$_t9head" ready \
      >"$_t9_rec.out" 2>"$_t9_rec.err" || _t9_rc=$?
  }

  # --- L1 (F-7): field.metric=none -> the reader omits dor-metric entirely (never n/a); the
  # tracker arm reads UNVERIFIED, naming the conf key field.metric.
  _t9_round metricnone 10001 Selected AB-2 "" "" "" "$(printf 'AB-2\t1')" none ""
  if [ "$_t9_rc" -ne 0 ] || ! grep -q '^verdict bound$' "$_t9_rec"; then
    echo "selftest FAIL: T9 L1 setup — the real round trip did not bind (rc=$_t9_rc, err=$(cat "$_t9_rec.err" 2>/dev/null))"; st_fail=1
  fi
  if grep -q 'dor-metric=' "$_t9_rec"; then
    echo "selftest FAIL: T9 L1 setup — field.metric=none must omit dor-metric entirely, got: $(cat "$_t9_rec" 2>/dev/null)"; st_fail=1
  fi
  KIT_TRACKER_RECORD="$_t9_rec"; _BC_HEAD="$_t9head"
  _t9grc=0
  check_dir "$_t9_root" >"$_t9_root/gate.out" 2>"$_t9_root/gate.err" || _t9grc=$?
  if [ "$_t9grc" -eq 2 ] && grep -q 'field.metric' "$_t9_root/gate.err"; then
    echo "selftest PASS: T9/L1: field.metric=none -> rc2 UNVERIFIED naming the conf key field.metric (F-7)"
  else
    echo "selftest FAIL: T9/L1: field.metric=none -> want rc2 naming field.metric, got rc=$_t9grc err=$(cat "$_t9_root/gate.err" 2>/dev/null)"; st_fail=1
  fi

  # --- L2 (H-3): the Ready list query fails -> the reader omits the `list ready` line entirely
  # (never present-empty); the subject's own dor-* flags still bind (they are independent queries)
  # but the tracker arm still reads UNVERIFIED — an absent list can never be read as empty.
  _t9_round listfail 10001 Selected "" 1 "" "" "$(printf 'AB-2\t1')" customfield_10077 ""
  if [ "$_t9_rc" -ne 0 ] || ! grep -q '^verdict bound$' "$_t9_rec"; then
    echo "selftest FAIL: T9 L2 setup — the real round trip did not bind (rc=$_t9_rc, err=$(cat "$_t9_rec.err" 2>/dev/null))"; st_fail=1
  fi
  if grep -q '^list ready' "$_t9_rec"; then
    echo "selftest FAIL: T9 L2 setup — expected NO 'list ready' line (the adapter was made to fail): $(cat "$_t9_rec" 2>/dev/null)"; st_fail=1
  fi
  if ! grep -q '^row AB-2 state=ready claimed=yes dor-acceptance=yes dor-metric=yes dor-size=yes dor-risk=yes$' "$_t9_rec"; then
    echo "selftest FAIL: T9 L2 setup — expected the subject's own dor-* flags still bound despite the list failure: $(cat "$_t9_rec" 2>/dev/null)"; st_fail=1
  fi
  KIT_TRACKER_RECORD="$_t9_rec"; _BC_HEAD="$_t9head"
  _t9grc=0
  check_dir "$_t9_root" >"$_t9_root/gate.out" 2>"$_t9_root/gate.err" || _t9grc=$?
  if [ "$_t9grc" -eq 2 ] && grep -q 'Ready list' "$_t9_root/gate.err"; then
    echo "selftest PASS: T9/L2: an absent (query-failed) Ready list -> rc2 UNVERIFIED, even though every row flag on the subject is bound (H-3)"
  else
    echo "selftest FAIL: T9/L2: want rc2 naming the Ready list, got rc=$_t9grc err=$(cat "$_t9_root/gate.err" 2>/dev/null)"; st_fail=1
  fi

  # --- L3: no Ready rows at all (a present-empty `list ready` line, the subject itself not ready)
  # -> rc0 OK, the graded count stated as zero (never vacuously silent).
  _t9_round empty 3 "In Progress" "" "" "" "" "" customfield_10077 ""
  if [ "$_t9_rc" -ne 0 ] || ! grep -q '^verdict bound$' "$_t9_rec"; then
    echo "selftest FAIL: T9 L3 setup — the real round trip did not bind (rc=$_t9_rc, err=$(cat "$_t9_rec.err" 2>/dev/null))"; st_fail=1
  fi
  if ! grep -q '^list ready$' "$_t9_rec"; then
    echo "selftest FAIL: T9 L3 setup — expected a PRESENT empty 'list ready' line: $(cat "$_t9_rec" 2>/dev/null)"; st_fail=1
  fi
  KIT_TRACKER_RECORD="$_t9_rec"; _BC_HEAD="$_t9head"
  _t9grc=0
  check_dir "$_t9_root" >"$_t9_root/gate.out" 2>"$_t9_root/gate.err" || _t9grc=$?
  if [ "$_t9grc" -eq 0 ] && grep -q 'graded=0' "$_t9_root/gate.out"; then
    echo "selftest PASS: T9/L3: no Ready rows (present-empty) -> rc0 OK, the graded count stated as zero"
  else
    echo "selftest FAIL: T9/L3: want rc0 graded=0, got rc=$_t9grc out=$(cat "$_t9_root/gate.out" 2>/dev/null)"; st_fail=1
  fi

  # --- D2: the base round trip for L5 — a real record where all four dor-* flags round-trip
  # 'yes', dor-risk included (field.risk=customfield_10088, T5d) — no backfill, no copy-and-sed.
  _t9_round happy 10001 Selected AB-2 "" "" "" "$(printf 'AB-2\t1')" customfield_10077 ""
  if [ "$_t9_rc" -ne 0 ] || ! grep -q '^verdict bound$' "$_t9_rec"; then
    echo "selftest FAIL: T9 L5 setup — the real round trip did not bind (rc=$_t9_rc, err=$(cat "$_t9_rec.err" 2>/dev/null))"; st_fail=1
  fi
  if ! grep -q '^row AB-2 state=ready claimed=yes dor-acceptance=yes dor-metric=yes dor-size=yes dor-risk=yes$' "$_t9_rec"; then
    echo "selftest FAIL: T9 L5 setup — expected all four dor-* flags 'yes' (a real field.risk round trip): $(cat "$_t9_rec" 2>/dev/null)"; st_fail=1
  fi
  _t9_okroot="$_t9_root"; _t9_ok="$_t9_rec"

  # --- L5: every Ready row's dor-*=yes, dor-risk from a real round trip -> rc0 OK.
  KIT_TRACKER_RECORD="$_t9_ok"; _BC_HEAD="$_t9head"
  _t9grc=0
  check_dir "$_t9_okroot" >"$_t9_okroot/gate-ok.out" 2>"$_t9_okroot/gate-ok.err" || _t9grc=$?
  if [ "$_t9grc" -eq 0 ] && grep -q 'graded=1' "$_t9_okroot/gate-ok.out"; then
    echo "selftest PASS: T9/L5: every Ready row's dor-*=yes (dor-risk via a real field.risk round trip, D2) -> rc0 OK"
  else
    echo "selftest FAIL: T9/L5: want rc0 graded=1, got rc=$_t9grc out=$(cat "$_t9_okroot/gate-ok.out" 2>/dev/null) err=$(cat "$_t9_okroot/gate-ok.err" 2>/dev/null)"; st_fail=1
  fi

  # --- L4: a real round trip mapping AB-2 into field.metric's 'empty' set -> dor-metric=no, every
  # other flag 'yes' -> rc1 FAIL naming the row id and the flag.
  _t9_round fail 10001 Selected AB-2 "" "" AB-2 "$(printf 'AB-2\t1')" customfield_10077 ""
  if [ "$_t9_rc" -ne 0 ] || ! grep -q '^verdict bound$' "$_t9_rec"; then
    echo "selftest FAIL: T9 L4 setup — the real round trip did not bind (rc=$_t9_rc, err=$(cat "$_t9_rec.err" 2>/dev/null))"; st_fail=1
  fi
  if ! grep -q '^row AB-2 state=ready claimed=yes dor-acceptance=yes dor-metric=no dor-size=yes dor-risk=yes$' "$_t9_rec"; then
    echo "selftest FAIL: T9 L4 setup — expected only dor-metric='no': $(cat "$_t9_rec" 2>/dev/null)"; st_fail=1
  fi
  KIT_TRACKER_RECORD="$_t9_rec"; _BC_HEAD="$_t9head"
  _t9grc=0
  check_dir "$_t9_root" >"$_t9_root/gate-fail.out" 2>"$_t9_root/gate-fail.err" || _t9grc=$?
  if [ "$_t9grc" -eq 1 ] && grep -q 'AB-2' "$_t9_root/gate-fail.err" && grep -q 'dor-metric' "$_t9_root/gate-fail.err"; then
    echo "selftest PASS: T9/L4: a Ready row's dor-metric=no (a real round trip) -> rc1 FAIL naming the row id and dor-metric"
  else
    echo "selftest FAIL: T9/L4: want rc1 naming AB-2/dor-metric, got rc=$_t9grc err=$(cat "$_t9_root/gate-fail.err" 2>/dev/null)"; st_fail=1
  fi

  # --- L4b (mutant anchor, "skip dor-size"): a real round trip where field.size's label count is 0
  # -> dor-size=no, every other flag 'yes' -> rc1 FAIL naming dor-size. The ONLY leg that isolates
  # dor-size as the sole bad flag — required so the "skip dor-size" mutant (below) actually reds
  # something (L4/L5 alone do not depend on dor-size being checked at all).
  _t9_round failsize 10001 Selected AB-2 "" "" "" "$(printf 'AB-2\t0')" customfield_10077 ""
  if [ "$_t9_rc" -ne 0 ] || ! grep -q '^verdict bound$' "$_t9_rec"; then
    echo "selftest FAIL: T9 L4b setup — the real round trip did not bind (rc=$_t9_rc, err=$(cat "$_t9_rec.err" 2>/dev/null))"; st_fail=1
  fi
  if ! grep -q '^row AB-2 state=ready claimed=yes dor-acceptance=yes dor-metric=yes dor-size=no dor-risk=yes$' "$_t9_rec"; then
    echo "selftest FAIL: T9 L4b setup — expected only dor-size='no': $(cat "$_t9_rec" 2>/dev/null)"; st_fail=1
  fi
  KIT_TRACKER_RECORD="$_t9_rec"; _BC_HEAD="$_t9head"
  _t9grc=0
  check_dir "$_t9_root" >"$_t9_root/gate-failsize.out" 2>"$_t9_root/gate-failsize.err" || _t9grc=$?
  if [ "$_t9grc" -eq 1 ] && grep -q 'dor-size' "$_t9_root/gate-failsize.err"; then
    echo "selftest PASS: T9/L4b: a Ready row's dor-size=no (a real round trip, every other flag 'yes') -> rc1 FAIL naming dor-size"
  else
    echo "selftest FAIL: T9/L4b: want rc1 naming dor-size, got rc=$_t9grc err=$(cat "$_t9_root/gate-failsize.err" 2>/dev/null)"; st_fail=1
  fi

  # --- L6 (F-7, D2 replaces the n/a backfill with a real field.risk mapping): AB-2 in the risk
  # field's 'empty' set -> dor-risk=no, every other flag 'yes' -> rc1 FAIL naming dor-risk — a
  # bound 'no' answer is a real FAIL, never UNVERIFIED, never a fictional n/a.
  _t9_round riskno 10001 Selected AB-2 "" "" "" "$(printf 'AB-2\t1')" customfield_10077 AB-2
  if [ "$_t9_rc" -ne 0 ] || ! grep -q '^verdict bound$' "$_t9_rec"; then
    echo "selftest FAIL: T9 L6 setup — the real round trip did not bind (rc=$_t9_rc, err=$(cat "$_t9_rec.err" 2>/dev/null))"; st_fail=1
  fi
  if ! grep -q '^row AB-2 state=ready claimed=yes dor-acceptance=yes dor-metric=yes dor-size=yes dor-risk=no$' "$_t9_rec"; then
    echo "selftest FAIL: T9 L6 setup — expected only dor-risk='no': $(cat "$_t9_rec" 2>/dev/null)"; st_fail=1
  fi
  KIT_TRACKER_RECORD="$_t9_rec"; _BC_HEAD="$_t9head"
  _t9grc=0
  check_dir "$_t9_root" >"$_t9_root/gate-na.out" 2>"$_t9_root/gate-na.err" || _t9grc=$?
  if [ "$_t9grc" -eq 1 ] && grep -q 'dor-risk' "$_t9_root/gate-na.err"; then
    echo "selftest PASS: T9/L6 (D2): a real field.risk round trip answering 'no' -> rc1 FAIL naming dor-risk (never n/a, F-7)"
  else
    echo "selftest FAIL: T9/L6: want rc1 naming dor-risk, got rc=$_t9grc out=$(cat "$_t9_root/gate-na.out" 2>/dev/null) err=$(cat "$_t9_root/gate-na.err" 2>/dev/null)"; st_fail=1
  fi

  # --- L6c (F-7 control, re-pin the literal 'n/a'): the real reader never emits dor-risk=n/a
  # (D2's real round trip only produces yes/no) — but a sed-mutated COPY of the L5 record with a
  # literal dor-risk=n/a must still FAIL, never silently pass, so a stray n/a on a record (any
  # source) can't sneak a Ready row past the gate. Assert the copy differs from its source first.
  _t9_narec="$_t9_okroot/record-na.txt"
  sed 's/dor-risk=yes/dor-risk=n\/a/' "$_t9_ok" > "$_t9_narec"
  if cmp -s "$_t9_ok" "$_t9_narec"; then
    echo "selftest FAIL: T9 L6c setup — the sed-mutated dor-risk=n/a copy did not differ from its source record"; st_fail=1
  fi
  KIT_TRACKER_RECORD="$_t9_narec"; _BC_HEAD="$_t9head"
  _t9grc=0
  check_dir "$_t9_okroot" >"$_t9_okroot/gate-narec.out" 2>"$_t9_okroot/gate-narec.err" || _t9grc=$?
  if [ "$_t9grc" -eq 1 ] && grep -q 'dor-risk' "$_t9_okroot/gate-narec.err"; then
    echo "selftest PASS: T9/L6c: a literal dor-risk=n/a on the record -> rc1 FAIL naming dor-risk (F-7 control, re-pinned)"
  else
    echo "selftest FAIL: T9/L6c: want rc1 naming dor-risk, got rc=$_t9grc out=$(cat "$_t9_okroot/gate-narec.out" 2>/dev/null) err=$(cat "$_t9_okroot/gate-narec.err" 2>/dev/null)"; st_fail=1
  fi

  # --- H1 (fix1, BOTH seats — the head is env-steerable): an exported _BC_HEAD with NO --head
  # flag must never reach bc_tracker_ready. Spawns the script FRESH (never in-process) since the
  # bug is in the file-scope reset that only runs once, at process start.
  _t9_h1out=$(cd "$_t9_root" && _BC_HEAD="$_t9head" KIT_TRACKER_RECORD="$_t9_ok" sh "$_t9dir/conformance/backlog-current.sh" . 2>&1) && _t9_h1rc=0 || _t9_h1rc=$?
  if [ "$_t9_h1rc" -eq 2 ]; then
    echo "selftest PASS: T9/H1 (fix1): an exported _BC_HEAD with no --head flag never reaches bc_tracker_ready (file-scope reset) -> rc2, never rc0"
  else
    echo "selftest FAIL: T9/H1: want rc2 (head ignored, refused), got rc=$_t9_h1rc out=$_t9_h1out"; st_fail=1
  fi

  # --- R2 (fix1, both seats' Low — the diagnosis): a head mismatch must surface the seam's own
  # fixed-text refusal (L-1: line+key+reason, never the value) ABOVE the generic 'Ready list is
  # absent' line, not be silently discarded — else a head mismatch misreports as a missing list.
  KIT_TRACKER_RECORD="$_t9_ok"; _BC_HEAD="0000000000000000000000000000000000000000"
  _t9grc=0
  check_dir "$_t9_root" >"$_t9_root/gate-headmismatch.out" 2>"$_t9_root/gate-headmismatch.err" || _t9grc=$?
  _t9_r2_seamline=$(grep -n 'record head does not match' "$_t9_root/gate-headmismatch.err" | head -1 | cut -d: -f1)
  _t9_r2_genline=$(grep -n 'the Ready list is absent' "$_t9_root/gate-headmismatch.err" | head -1 | cut -d: -f1)
  if [ "$_t9grc" -eq 2 ] && [ -n "$_t9_r2_seamline" ] && [ -n "$_t9_r2_genline" ] && [ "$_t9_r2_seamline" -lt "$_t9_r2_genline" ]; then
    echo "selftest PASS: T9/R2 (fix1): a head mismatch relays the seam's own fixed-text refusal ABOVE the generic 'Ready list is absent' line"
  else
    echo "selftest FAIL: T9/R2: want the seam's own refusal line BEFORE the generic UNVERIFIED line, got rc=$_t9grc err=$(cat "$_t9_root/gate-headmismatch.err" 2>/dev/null)"; st_fail=1
  fi

  # --- L0 (step 0, T7 seat M-1 carry): bc_tracker_ready calls seam_rows_in_state/seam_row_flag
  # WITHOUT $( ) so the seam's parse memo survives — over N>=5 Ready ids, exactly ONE record load.
  # A hand-built record (never the reader — this leg pins the GATE's own call pattern, not the
  # reader) with a real pin (this run's own tracker.conf digest) and today's read-day.
  _t9_l0root="$base/t9_l0"; mkdir -p "$_t9_l0root/.kit"
  printf -- '- **Backlog backend**: Jira\n' > "$_t9_l0root/CLAUDE.md"
  cat > "$_t9_l0root/.kit/tracker.conf" <<'EOF9L0'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.ready=Selected
EOF9L0
  _t9_l0pin=$( { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } < "$_t9_l0root/.kit/tracker.conf" | awk '{print $1}')
  _t9_l0day=$(date -u +%Y-%m-%d)
  _t9_l0rec="$_t9_l0root/record.txt"
  {
    echo "kit-tracker-read 1"
    echo "backend jira"
    echo "pin sha256:$_t9_l0pin"
    echo "head $_t9head"
    echo "requested AB-10"
    echo "read-day $_t9_l0day"
    echo "credential ok"
    echo "verdict bound"
    for _t9i in 10 11 12 13 14; do
      echo "row AB-$_t9i state=ready dor-acceptance=yes dor-metric=yes dor-size=yes dor-risk=yes"
    done
    echo "list ready AB-10 AB-11 AB-12 AB-13 AB-14"
  } > "$_t9_l0rec"
  # fix1 R1 (quality 6 + the carry): route through check_dir — the gate's REAL entry (never
  # bc_tracker_ready called directly) — and assert the graded COUNT, not just rc0, while still
  # pinning the load count at 1 (the carry this leg exists for).
  KIT_TRACKER_RECORD="$_t9_l0rec"; _BC_HEAD="$_t9head"
  SEAM_TEST_LOAD_COUNT=0
  _t9_l0rc=0
  check_dir "$_t9_l0root" >"$_t9_l0root/gate.out" 2>"$_t9_l0root/gate.err" || _t9_l0rc=$?
  if [ "$_t9_l0rc" -eq 0 ] && [ "$SEAM_TEST_LOAD_COUNT" = "1" ] && grep -q 'graded=5' "$_t9_l0root/gate.out"; then
    echo "selftest PASS: T9/L0 (step 0, T7 seat M-1 carry; fix1 R1): through check_dir's real entry, over 5 Ready ids, bc_tracker_ready's plain (non-\$( )) seam calls cost exactly ONE record load, graded=5"
  else
    echo "selftest FAIL: T9/L0: want rc0, SEAM_TEST_LOAD_COUNT=1, graded=5, got rc=$_t9_l0rc count=${SEAM_TEST_LOAD_COUNT:-unset} out=$(cat "$_t9_l0root/gate.out" 2>/dev/null)"; st_fail=1
  fi

  # --- W1 (fix1, quality blocking 2 — worst rc wins / accumulate-all unpinned): one Ready row
  # missing a flag entirely (dor-risk absent -> UNVERIFIED) AND another with dor-metric=no
  # (-> FAIL) in ONE record -> rc2 (worst wins over rc1), naming BOTH rows.
  _t9_w1rec="$_t9_l0root/record-w1.txt"
  {
    echo "kit-tracker-read 1"
    echo "backend jira"
    echo "pin sha256:$_t9_l0pin"
    echo "head $_t9head"
    echo "requested AB-10"
    echo "read-day $_t9_l0day"
    echo "credential ok"
    echo "verdict bound"
    echo "row AB-10 state=ready dor-acceptance=yes dor-metric=no dor-size=yes dor-risk=yes"
    echo "row AB-11 state=ready dor-acceptance=yes dor-metric=yes dor-size=yes"
    # fix2 W2 (the quality seat's "-lt 1 -> unconditional" mutant was vacuous with FAIL-then-
    # UNVERIFIED order — UNVERIFIED, processed LAST, always ratchets to 2 regardless of the FAIL
    # line's own guard). UNVERIFIED row FIRST so a broken guard can OVERWRITE 2 back down to 1.
    echo "list ready AB-11 AB-10"
  } > "$_t9_w1rec"
  KIT_TRACKER_RECORD="$_t9_w1rec"; _BC_HEAD="$_t9head"
  _t9grc=0
  check_dir "$_t9_l0root" >"$_t9_l0root/gate-w1.out" 2>"$_t9_l0root/gate-w1.err" || _t9grc=$?
  if [ "$_t9grc" -eq 2 ] && grep -q 'AB-10' "$_t9_l0root/gate-w1.err" && grep -q 'AB-11' "$_t9_l0root/gate-w1.err"; then
    echo "selftest PASS: T9/W1 (fix1): a FAIL row (AB-10 dor-metric=no) AND an UNVERIFIED row (AB-11 missing dor-risk) in one record -> rc2 (worst wins), both rows named"
  else
    echo "selftest FAIL: T9/W1: want rc2 naming AB-10 and AB-11, got rc=$_t9grc err=$(cat "$_t9_l0root/gate-w1.err" 2>/dev/null)"; st_fail=1
  fi

  # --- fix2 G1/HIGH (security — the env-read test hook was itself a defect): the removed
  # _BCTR_TEST_SELFTERM hook has NO effect at all on the production CLI any more — an exported
  # value writes nothing and never changes the verdict (the quality seat's own probe: the variable
  # exported on the production CLI, no --head-armed hook needed to demonstrate its old truncation).
  _t9_g1victim="$base/t9-g1-victim.txt"; rm -f "$_t9_g1victim"
  _t9_g1out=$(_BCTR_TEST_SELFTERM="$_t9_g1victim" KIT_TRACKER_RECORD="$_t9_l0rec" sh "$_t9dir/conformance/backlog-current.sh" --head "$_t9head" "$_t9_l0root" 2>&1) && _t9_g1rc=0 || _t9_g1rc=$?
  if [ ! -e "$_t9_g1victim" ] && [ "$_t9_g1rc" -eq 0 ] && printf '%s' "$_t9_g1out" | grep -q 'graded=5'; then
    echo "selftest PASS: T9/G1 (fix2): an exported _BCTR_TEST_SELFTERM on the production CLI writes nothing and never changes the verdict — the hook is gone"
  else
    echo "selftest FAIL: T9/G1: want no victim file and rc0 graded=5, got rc=$_t9_g1rc victim=$([ -e "$_t9_g1victim" ] && echo PRESENT || echo absent) out=$_t9_g1out"; st_fail=1
  fi

  # --- fix2 BLOCKER 1a (security) + G2, hardened by T10-harden-B D1 (a CI flake): an EXTERNAL TERM
  # mid-run (never a hook) must terminate the process (rc143) and must NEVER print a silent
  # "graded=0" on a non-empty Ready list; both mktemp files must be gone. D1: a 5-row record can
  # finish before the delay on a fast runner, so the kill misses and a fast pass misreports as a
  # FAIL — sized up to 480 Ready rows so the run reliably outlives the delay, and `kill`'s own exit
  # status is asserted as a PRECONDITION: if the process already exited before the signal could be
  # delivered, the leg reports "not exercised — SKIP", never a FAIL and never a silent PASS. TMPDIR
  # isolated under $base so the leftover count is unambiguous.
  _t9_termtmp="$base/t9-term-tmp"; mkdir -p "$_t9_termtmp"
  _t9_termout="$base/t9-term.out"
  _t9_termrec="$_t9_l0root/record-term.txt"
  {
    echo "kit-tracker-read 1"
    echo "backend jira"
    echo "pin sha256:$_t9_l0pin"
    echo "head $_t9head"
    echo "requested AB-9000"
    echo "read-day $_t9_l0day"
    echo "credential ok"
    echo "verdict bound"
    _t9_termi=9000
    while [ "$_t9_termi" -lt 9480 ]; do
      echo "row AB-$_t9_termi state=ready dor-acceptance=yes dor-metric=yes dor-size=yes dor-risk=yes"
      _t9_termi=$((_t9_termi + 1))
    done
    _t9_termlist="list ready"
    _t9_termi=9000
    while [ "$_t9_termi" -lt 9480 ]; do
      _t9_termlist="$_t9_termlist AB-$_t9_termi"
      _t9_termi=$((_t9_termi + 1))
    done
    printf '%s\n' "$_t9_termlist"
  } > "$_t9_termrec"
  TMPDIR="$_t9_termtmp" KIT_TRACKER_RECORD="$_t9_termrec" sh "$_t9dir/conformance/backlog-current.sh" --head "$_t9head" "$_t9_l0root" >"$_t9_termout" 2>&1 &
  _t9_termpid=$!
  sleep 0.08
  # WB-FIX-2 item 1 (both seats): snapshot the output file IMMEDIATELY BEFORE sending TERM — a
  # handler that swallows TERM (mutant M6c) also finishes the run and prints the same OK/graded
  # line, so the OLD post-hoc grep could not tell an ignored TERM from a genuine finished-first
  # race. The presnap fixes the ambiguity: OK already present before the kill -> a real race
  # (SKIP); OK appears only AFTER the kill -> TERM was delivered but ignored (FAIL).
  _t9_term_presnap=0
  grep -q 'OK: backlog-current (tracker) — Ready rows graded=' "$_t9_termout" 2>/dev/null && _t9_term_presnap=1
  _t9_termkillrc=0
  kill -TERM "$_t9_termpid" 2>/dev/null || _t9_termkillrc=$?
  _t9_termrc=0
  wait "$_t9_termpid" || _t9_termrc=$?
  _t9_termleftover=$(find "$_t9_termtmp" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$_t9_termkillrc" -ne 0 ]; then
    echo "selftest SKIP: T9/BLOCKER-term: not exercised — the process already exited before the TERM could be delivered"
  elif [ "$_t9_term_presnap" -eq 1 ]; then
    # B5 (security L-3, signal leg): the run finishing normally BEFORE the TERM landed is the same
    # race as an already-exited pid — an honest SKIP, never a silent PASS or a misleading FAIL.
    echo "selftest SKIP: T9/BLOCKER-term: not exercised — the run completed (an OK/graded line) before the TERM could take effect"
  elif grep -q 'OK: backlog-current (tracker) — Ready rows graded=' "$_t9_termout"; then
    echo "selftest FAIL: T9/BLOCKER-term: TERM delivered but ignored — the run produced an OK/graded line only AFTER the kill (a handler that swallows the signal instead of terminating)"; st_fail=1
  elif [ "$_t9_termrc" -eq 143 ] && ! grep -q 'graded=0' "$_t9_termout" && [ "$_t9_termleftover" -eq 0 ]; then
    echo "selftest PASS: T9/BLOCKER-term (D1): a real external TERM, delivered mid-run (kill itself succeeded) over a 480-row fixture, kills the process (rc143), never prints a silent graded=0, and leaves no temp files behind"
  else
    echo "selftest FAIL: T9/BLOCKER-term: want rc143, no graded=0, 0 leftover temps; got rc=$_t9_termrc leftover=$_t9_termleftover out=$(cat "$_t9_termout" 2>/dev/null)"; st_fail=1
  fi

  # --- fix2 BLOCKER 1b (security, independent of the trap above): the Ready list vanishing AFTER
  # the write but BEFORE the read -> rc2, never a silent graded=0. Test-side only: shadow
  # seam_rows_in_state for ONE direct bc_tracker_ready call (a fixture — unlinking an already-open
  # fd's target is inert on the write already in flight, but the shell's later
  # `< "$_bctr_lf"` (the while loop's own redirection) then cannot reopen it), then restore the
  # real definition by re-sourcing backlog-lib.sh.
  seam_rows_in_state() { _seam_tracker_rows_in_state "$1"; _t9v_rc=$?; rm -f "$_bctr_lf"; return "$_t9v_rc"; }
  # shellcheck disable=SC2034  # SEAM_ROOT is read by the sourced seam_* functions (backlog-lib.sh)
  SEAM_ROOT="$_t9_l0root"
  # shellcheck disable=SC2034
  SEAM_RECORD="$_t9_l0rec"
  # shellcheck disable=SC2034
  SEAM_HEAD="$_t9head"
  _t9_vanish_out="$base/t9-vanish.out"
  _t9_vgrc=0
  bc_tracker_ready "$_t9head" >"$_t9_vanish_out" 2>&1 || _t9_vgrc=$?
  . "$_t9dir/conformance/backlog-lib.sh"
  if [ "$_t9_vgrc" -eq 2 ] && grep -q 'vanished before it could be read' "$_t9_vanish_out"; then
    echo "selftest PASS: T9/BLOCKER-vanish (fix2): the Ready list vanishing between the write and the read -> rc2, never a silent graded=0"
  else
    echo "selftest FAIL: T9/BLOCKER-vanish: want rc2 naming 'vanished before it could be read', got rc=$_t9_vgrc out=$(cat "$_t9_vanish_out" 2>/dev/null)"; st_fail=1
  fi

  # --- fix2 BLOCKER 1b's sibling defence: the independent row-count assertion. A PATH-shimmed `wc`
  # inflates the counted want-total by 1 for THIS one subprocess only (a fixture, never a hook) ->
  # the loop's real 5-row count no longer matches -> rc2, never a silent rc0. Passthrough for every
  # OTHER `wc` call so nothing else in the run is affected.
  mkdir -p "$base/t9-wcshim"
  cat > "$base/t9-wcshim/wc" <<'EOF9WC'
#!/bin/sh
case "$1" in
  -l) r=$(command -p wc -l); printf '%s\n' "$((r + 1))" ;;
  *) command -p wc "$@" ;;
esac
EOF9WC
  chmod +x "$base/t9-wcshim/wc"
  _t9_wcout=$(PATH="$base/t9-wcshim:$PATH" KIT_TRACKER_RECORD="$_t9_l0rec" sh "$_t9dir/conformance/backlog-current.sh" --head "$_t9head" "$_t9_l0root" 2>&1) && _t9_wcrc=0 || _t9_wcrc=$?
  if [ "$_t9_wcrc" -eq 2 ] && printf '%s' "$_t9_wcout" | grep -q 'graded 5 of 6'; then
    echo "selftest PASS: T9/BLOCKER-count (fix2): a wc-shimmed inflated want-count vs the real 5 graded rows -> rc2, never a silent rc0 (the independent fail-closed count check)"
  else
    echo "selftest FAIL: T9/BLOCKER-count: want rc2 naming 'graded 5 of 6', got rc=$_t9_wcrc out=$_t9_wcout"; st_fail=1
  fi

  # --- L7 (H-4, fix1 R5 — quality 8): KIT_TRACKER_RECORD unset -> today's rc3 NOT ENFORCED path,
  # BYTES compared (cmp) against a direct not_enforced_notice call — a substring cannot see stray
  # extra bytes on either side.
  unset KIT_TRACKER_RECORD
  _BC_HEAD=""
  _t9grc=0
  check_dir "$_t9_l0root" >"$_t9_l0root/gate-unset.out" 2>"$_t9_l0root/gate-unset.err" || _t9grc=$?
  _t9_l7drc=0
  not_enforced_notice jira "$_t9_l0root" "$(dirname "$0")/waivers-valid.sh" >"$_t9_l0root/gate-unset-direct.out" 2>&1 || _t9_l7drc=$?
  if [ "$_t9grc" -eq 3 ] && [ "$_t9_l7drc" -eq 3 ] && cmp -s "$_t9_l0root/gate-unset.out" "$_t9_l0root/gate-unset-direct.out"; then
    echo "selftest PASS: T9/L7 (H-4, fix1 R5): KIT_TRACKER_RECORD unset -> today's rc3 NOT ENFORCED sentence, byte-identical (cmp) to a direct not_enforced_notice call"
  else
    echo "selftest FAIL: T9/L7: want rc3 byte-identical to the direct call, got rc=$_t9grc direct_rc=$_t9_l7drc out=$(cat "$_t9_l0root/gate-unset.out" 2>/dev/null) direct=$(cat "$_t9_l0root/gate-unset-direct.out" 2>/dev/null)"; st_fail=1
  fi

  if [ "$st_fail" -ne 0 ]; then
    echo "backlog-current --selftest: FAIL" >&2
    return 1
  fi
  echo "backlog-current --selftest: OK (fixtures cleaned on exit)"
  return 0
}

# --- selftest-only helpers (defined AFTER the selftest() marker on purpose) -------------
# These live in the ORACLE region so the non-vacuity mutation harness (which mutates only
# lines BEFORE the first ^selftest() marker) cannot neuter the oracle's own failure
# accumulator (st_fail=1). The CHECK logic above the marker stays mutable, as it must.
# assert_msg_rc <dir> <needle> <want-rc> <label> : check_dir must emit <needle> AND return exactly
# <want-rc>. assert_msg above hardcodes rc 0, which cannot express the rc-3 NOT ENFORCED partition
# — and asserting the sentence without the rc would pass on a gate that printed the red and
# returned green.
assert_msg_rc() {
  _o=$(check_dir "$1" 2>&1) && _r=0 || _r=$?
  if [ "${_r:-0}" = "$3" ] && printf '%s\n' "$_o" | grep -Fq "$2"; then
    echo "selftest PASS: $4"
  else
    echo "selftest FAIL: $4 (rc=${_r:-?} want=$3, out=<$_o>)"; st_fail=1
  fi
}
# assert_rid_ok <token> <label> : row_id_ok must accept the token.
assert_rid_ok() {
  if row_id_ok "$1"; then echo "selftest PASS: $2"
  else echo "selftest FAIL: $2 (row_id_ok refused '$1')"; st_fail=1; fi
}
# assert_rid_bad <token> <label> : row_id_ok must refuse the token.
assert_rid_bad() {
  if row_id_ok "$1"; then echo "selftest FAIL: $2 (row_id_ok accepted '$1')"; st_fail=1
  else echo "selftest PASS: $2"; fi
}
# assert_eq_str <got> <want> <label> : the two already-computed strings must be byte-equal.
# BOARD-PIPE-ESCAPE T1 — the parser harness compares cell()/gfm_cell()/gfm_nf()/retro_cell()
# output directly (no check_dir round-trip), so it needs a bare string-equality assertion.
assert_eq_str() {
  if [ "$1" = "$2" ]; then echo "selftest PASS: $3"
  else echo "selftest FAIL: $3 (got=<$1> want=<$2>)"; st_fail=1; fi
}
# assert_rowcount <board> <id> <want> <label> : row_count must print exactly <want>.
assert_rowcount() {
  _arc=$(row_count "$1" "$2")
  if [ "$_arc" = "$3" ]; then echo "selftest PASS: $4"
  else echo "selftest FAIL: $4 (row_count='$_arc' want='$3')"; st_fail=1; fi
}
# assert_msg <dir> <needle> <label> : check_dir must rc0 AND emit <needle>.
assert_msg() {
  _o=$(check_dir "$1" 2>&1) && _r=0 || _r=$?
  if [ "${_r:-0}" -eq 0 ] && printf '%s\n' "$_o" | grep -Fq "$2"; then
    echo "selftest PASS: $3"
  else
    echo "selftest FAIL: $3 (rc=${_r:-?}, out=<$_o>)"; st_fail=1
  fi
}
# assert_ok <dir> <label> : rc0, emits OK, and does NOT emit an N/A line (non-vacuity).
assert_ok() {
  _o=$(check_dir "$1" 2>&1) && _r=0 || _r=$?
  if [ "${_r:-0}" -eq 0 ] && printf '%s\n' "$_o" | grep -Fq "OK" \
     && ! printf '%s\n' "$_o" | grep -Fq "N/A:"; then
    echo "selftest PASS: $2"
  else
    echo "selftest FAIL: $2 (rc=${_r:-?}, out=<$_o>)"; st_fail=1
  fi
}
# assert_no_ctrl <dir> <label> : check_dir's ENTIRE output must carry no control byte (newlines
# excepted). Board cells are untrusted bytes that reach a terminal and a CI log, so a CSI sequence
# pasted into a cell could rewrite the verdict a human reads. `LC_ALL=C` makes `[[:cntrl:]]` the
# same byte class the `_cell_diag` sanitizer deletes — and leaves UTF-8 continuation bytes alone,
# so an em-dash in a row title is not mistaken for a control byte (the harness-adapter:661
# precedent, whose comment records that exact locale trap).
# DELIBERATELY WHOLE-OUTPUT, not one message: a future FAIL path that echoes a cell without
# _cell_diag is caught here without anyone remembering to write a leg for it.
assert_no_ctrl() {
  _o=$(check_dir "$1" 2>&1) || :
  if printf '%s' "$_o" | LC_ALL=C tr -d '\n\t' | LC_ALL=C grep -q '[[:cntrl:]]'; then
    echo "selftest FAIL: $2 (a control byte survived into the diagnostic; sanitized out=<$(printf '%s' "$_o" | LC_ALL=C tr -d '[:cntrl:]')>)"
    st_fail=1
  else
    echo "selftest PASS: $2"
  fi
}
# assert_fail <dir> <needle> <label> : check_dir must rc!=0 AND emit <needle>.
assert_fail() {
  _o=$(check_dir "$1" 2>&1) && _r=0 || _r=$?
  if [ "${_r:-0}" -ne 0 ] && printf '%s\n' "$_o" | grep -Fq "$2"; then
    echo "selftest PASS: $3"
  else
    echo "selftest FAIL: $3 (rc=${_r:-?}, out=<$_o>)"; st_fail=1
  fi
}
# assert_warn <dir> <check-id> <phrase> <label> : a DEMOTED (form) check — check_dir must rc0 AND emit
# a `WARN: <check-id>:` line that still carries the pre-demotion <phrase> (so a grep for the old
# wording still finds it). GITHUB_ACTIONS is unset in the subshell so the stderr-only shape is what
# is graded. The vacuity guard is the rc: every leg using this returned rc 1 before the demotion.
assert_warn() {
  _o=$( unset GITHUB_ACTIONS; check_dir "$1" 2>&1 ) && _r=0 || _r=$?
  if [ "${_r:-0}" -eq 0 ] && printf '%s\n' "$_o" | grep -F "WARN: $2:" | grep -Fq "$3"; then
    echo "selftest PASS: $4"
  else
    echo "selftest FAIL: $4 (rc=${_r:-?}, out=<$_o>)"; st_fail=1
  fi
}
# assert_warn_annot <dir> <check-id> <on|off> <label> : under GITHUB_ACTIONS=true the same WARN is also
# emitted as a `::warning::` annotation (on); with it unset there is NO annotation (off). rc0 both ways.
assert_warn_annot() {
  if [ "$3" = on ]; then
    _o=$( GITHUB_ACTIONS=true; export GITHUB_ACTIONS; check_dir "$1" 2>&1 ) && _r=0 || _r=$?
    _want=0; printf '%s\n' "$_o" | grep -Fq "::warning::WARN: $2:" && _want=1
  else
    _o=$( unset GITHUB_ACTIONS; check_dir "$1" 2>&1 ) && _r=0 || _r=$?
    _want=1; printf '%s\n' "$_o" | grep -Fq "::warning::" && _want=0
  fi
  if [ "${_r:-0}" = "0" ] && [ "$_want" -eq 1 ] && printf '%s\n' "$_o" | grep -Fq "WARN: $2:"; then
    echo "selftest PASS: $4"
  else
    echo "selftest FAIL: $4 (rc=${_r:-?}, out=<$_o>)"; st_fail=1
  fi
}
# assert_warn_no_cmd <dir> <label> : under GITHUB_ACTIONS=true, NO output line may START with `::error::`
# (a workflow command smuggled through board text), and the row's WARN must still have fired (non-vacuity).
assert_warn_no_cmd() {
  _o=$( GITHUB_ACTIONS=true; export GITHUB_ACTIONS; check_dir "$1" 2>&1 ) && _r=0 || _r=$?
  if [ "${_r:-0}" -eq 0 ] && printf '%s\n' "$_o" | grep -Fq "WARN: HITL-6-DISPO:" \
     && ! printf '%s\n' "$_o" | grep -q '^::error::'; then
    echo "selftest PASS: $2"
  else
    echo "selftest FAIL: $2 (rc=${_r:-?}, out=<$_o>)"; st_fail=1
  fi
}
# assert_warn_annot_has <dir> <needle> <label> : under GITHUB_ACTIONS=true a `::warning::` line carries <needle>.
assert_warn_annot_has() {
  _o=$( GITHUB_ACTIONS=true; export GITHUB_ACTIONS; check_dir "$1" 2>&1 ) && _r=0 || _r=$?
  if [ "${_r:-0}" -eq 0 ] && printf '%s\n' "$_o" | grep -F '::warning::' | grep -Fq "$2"; then
    echo "selftest PASS: $3"
  else
    echo "selftest FAIL: $3 (rc=${_r:-?}, out=<$_o>)"; st_fail=1
  fi
}

# --- fixture writers --------------------------------------------------------------------
# _claude_md <backend-value> <dest-CLAUDE.md> : write a CLAUDE.md declaring the backend.
_claude_md() { printf '# CLAUDE\n\n- **Backlog backend** (§6): %s\n' "$1" > "$2"; }

# _dispo_proj <dir> <closed> <retro> [<decisions-body>] : a project dir declaring an md backend
# with a valid in-use board whose ONLY Done row is `| `THE-ROW` | <closed> | <retro> |`, and whose
# Ready section carries `OTHER-ROW` so a Disposition can resolve to a real but DIFFERENT row. A
# fourth argument writes <dir>/docs/governance/DECISIONS.md with that body; omitted, the file does
# not exist (which is itself one of the graded routes). One writer for fifteen legs — the fixture
# surface is budgeted, and fifteen inline boards would cost ~350 lines of it.
_dispo_proj() {
  mkdir -p "$1"; _claude_md "$_MD" "$1/CLAUDE.md"
  {
    echo '# B'
    echo '## Ready'
    echo
    echo '| Item | Owner | Links | Success metric / hypothesis |'
    echo '|------|-------|-------|-----------------------------|'
    echo '| `OTHER-ROW` | a | #1 | login success rate 92% -> 98% |'
    echo
    echo '## In Progress'
    echo
    echo '| Item | Owner | Started | Links |'
    echo '|------|-------|---------|-------|'
    echo '| | | | |'
    echo
    echo '## In Review'
    echo
    echo '| Item | Reviewer | PR |'
    echo '|------|----------|----|'
    echo '| | | |'
    echo
    echo '## Done'
    echo
    echo '| Item | Closed | Retro/outcome |'
    echo '|------|--------|---------------|'
    # _DISPO_ITEM (optional, caller-set) appends text to the Done row's ITEM cell — how the live
    # `B8` shape (an escaped pipe LEFT of the Closed column) is reproduced. Passed through printf,
    # never sed: a sed REPLACEMENT eats the backslash in `\|`, which silently destroys the very
    # byte the fixture is about (watched happen while writing this leg).
    printf '| `THE-ROW`%s | %s | %s |\n' "${_DISPO_ITEM:-}" "$2" "$3"
  } > "$1/BACKLOG.md"
  if [ $# -ge 4 ]; then
    mkdir -p "$1/docs/governance"
    printf '%s\n' "$4" > "$1/docs/governance/DECISIONS.md"
  fi
}

# _good_board <dest-BACKLOG.md> : a valid, in-use board (real In Progress+In Review rows,
# one In Progress spacer row). Passes every T2.1 check.
_good_board() {
  cat > "$1" <<'EOF'
# Proj — Backlog

## Ready
> Safe to start.

| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links | Success metric / hypothesis |
|------|--------------|---------------------|------|------|------|-------|-------|-----------------------------|
| Add login | ship auth | user can log in | S | med | feature | agent | #12 | login success rate 92% -> 98% |

## In Progress
> WIP-limited.

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| Add login | agent | 2026-07-01 | #12 |
| | | | |

## In Review
> Awaiting merge gate.

| Item | Reviewer | PR |
|------|----------|----|
| Add login | Octocat | #34 |

## Released

| Item | Released | Success metric / hypothesis |
|------|----------|------------------------------|
| | | |

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|

## Blocked
> Waiting on an external dependency; Since keeps rot visible.

| Item | Blocked on | Since | Event-retro link |
|------|-----------|-------|------------------|
| Add SSO | vendor SAML metadata | 2026-07-02 | |
EOF
}

# _find_template -> path to the shipped BACKLOG-TEMPLATE.md (repo-root or relative to $0).
_find_template() {
  for _p in templates/BACKLOG-TEMPLATE.md \
            "$(dirname "$0")/../templates/BACKLOG-TEMPLATE.md" \
            "$(dirname "$0")/templates/BACKLOG-TEMPLATE.md"; do
    [ -f "$_p" ] && { printf '%s' "$_p"; return 0; }
  done
  return 1
}

# fix1 H1 (both seats — the head is env-steerable): reset at FILE SCOPE, before the dispatch
# below, so an already-exported _BC_HEAD (a poisoned shell profile, a decoy env var) can never
# reach bc_tracker_ready without the explicit --head flag. Only the --head branch below may set it.
_BC_HEAD=""

# fix2 (security BLOCKER + MEDIUM): the ONE trap for bc_tracker_ready's temp files, installed here
# at the top of the CLI's own execution — no caller sits above this script's own top level, so
# there is nothing here to clobber (see _bctr_sig's own header comment).
trap '_bctr_sig TERM' TERM
trap '_bctr_sig INT' INT

case "${1:-}" in
  --selftest) selftest ;;
  # TBG-READER-FLAGS-LIST T9 (P-3): --head is the tracker arm's ONLY new input, BY ARGUMENT (never
  # an env var — the same rule loop-state.sh/backlog-presence.sh's own --head carries) so a decoy
  # cannot redirect a control-plane check. Ignored entirely on the md path (bc_tracker_ready is
  # never reached there).
  --head)
    [ $# -ge 2 ] || { echo "usage: backlog-current.sh --head <sha> [project-dir]" >&2; exit 2; }
    # shellcheck disable=SC2034  # read by bc_tracker_ready via check_dir's non-md branch
    _BC_HEAD="$2"
    check_dir "${3:-.}"
    ;;
  *)          check_dir "${1:-.}" ;;
esac
exit $?
