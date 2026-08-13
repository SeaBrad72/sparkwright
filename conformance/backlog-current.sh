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
header_cols() {
  printf '%s' "$1" | awk -F'|' '
    {s=""; for(i=2;i<=NF;i++){v=$i; gsub(/^[ \t]+|[ \t]+$/,"",v);
      if(v!=""){s=s (s==""?"":", ") v}} print s}'
}
# is_bare_na <cell> : rc0 iff the cell is empty or a bare marker (a blank in a costume).
# ONE definition of "a blank in a costume", shared by every gated cell in this file — never two
# (BOARD-DOR-FIELDS design-gate MEDIUM-3). `?` joined the set with the Ready Success-metric gate:
# a lone question mark is the most natural "I don't know yet" a board author types, and it is a
# blank wearing punctuation. Widening here widens EVERY caller (Links, PR, Blocked on, Since,
# Success metric) — deliberate: a bare `?` was never an acceptable value in any of them.
is_bare_na() {
  _v=$(printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  [ -z "$_v" ] && return 0
  printf '%s' "$_v" | grep -Eiq '^(-|—|n/?a|tbd|none|[?])$'
}
# is_na_reason <cell> : rc0 iff the cell is the kit idiom `N/A — <reason>` (reason present).
is_na_reason() { printf '%s' "$1" | grep -Eiq '^[[:space:]]*n/?a[[:space:]]*(—|-)[[:space:]]*[^[:space:]]'; }

# _cell_diag <cell> : a board-author-controlled cell rendered safe to print in a diagnostic —
# control bytes stripped and length-bounded. Board cells are untrusted bytes that reach a
# terminal (and a CI log), so an ANSI/CSI sequence pasted into a cell could otherwise rewrite the
# verdict a human reads. The security-waiver CONDITION for this slice (design §"Obligations"):
# every new FAIL message that echoes cell content goes through here. `LC_ALL=C` on the `tr` is
# load-bearing — bytewise deletion of 0x00-0x1F/0x7F leaves UTF-8 continuation bytes (0x80-0xBF)
# untouched, so an em-dash or an emoji in a row title survives intact; the `cut` is left in the
# ambient locale so it bounds CHARACTERS and cannot split a multibyte sequence.
# Precedent: promotion-readiness.sh:344-345, branch-protection.sh:170.
_cell_diag() { printf '%s' "$1" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-80; }

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
    _found=$(header_cols "$_hdr")                  # a table exists but the gated column is renamed/absent
    echo "FAIL: $_sec — required column '$_col' not found (columns present: ${_found:-none}); a renamed/absent gated column is a schema violation, not a skip"
    return 1
  fi
  # 'blocked' gates a SECOND column ('Since'). Absent -> the same schema violation (a renamed
  # 'Blocked on'/'Since' must never silently disable the gate), never a fallback-column guess.
  _ci2=""
  if [ "$_mode" = "blocked" ]; then
    [ -n "$_rows" ] && _ci2=$(col_index "$_hdr" "$_col2")
    if [ -z "$_ci2" ]; then
      _found=$(header_cols "$_hdr")
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
        echo "FAIL: $_sec item '$_item' — $_col must be a real PR link (got '${_g}'); a blank or 'N/A — reason' is not review-ready"
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
        echo "FAIL: $_sec item '$_item' — $_col is empty/bare ('${_g}'); name the blocker or use the 'N/A — <reason>' idiom"
        return 1
      fi
      if is_na_reason "$_g"; then BLOCKED_NA_ESCAPES=$((BLOCKED_NA_ESCAPES + 1)); fi
      _s=$(cell "$_row" "$_ci2")                   # 'Since'
      if is_bare_na "$_s"; then
        echo "FAIL: $_sec item '$_item' — $_col2 is empty/bare ('${_s}'); record when it blocked so staleness is visible, or use the 'N/A — <reason>' idiom"
        return 1
      fi
      if is_na_reason "$_s"; then BLOCKED_NA_ESCAPES=$((BLOCKED_NA_ESCAPES + 1)); fi
    else
      # In Progress -> Links: a real value OR an `N/A — reason`. Bare/empty FAILs.
      _g=$(cell "$_row" "$_ci")
      if is_bare_na "$_g"; then
        echo "FAIL: $_sec item '$_item' — $_col is empty/bare ('${_g}'); use a real link or the 'N/A — <reason>' idiom"
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
    if is_bare_na "$_rm_g" || is_na_reason "$_rm_g"; then
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
      _rm_found=$(_cell_diag "$(header_cols "$_rm_hdr")")
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
        echo "FAIL: Done item '$_item' — flagged [taste-surface] but carries no UAT-SIGNOFF reference; a taste-surface reaching Done must record a UAT sign-off (a link or path to a UAT-SIGNOFF)"
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

# retro_cell <row> <header-row> <col-index> : the Retro/outcome cell, ROBUST to escaped pipes.
# WHY THIS EXISTS: GFM treats `\|` as a literal pipe inside a table cell, but backlog-lib's cell()
# splits on every raw '|' via awk -F'|', so a row using the CORRECT markdown escape has its trailing
# columns shifted. MEASURED on BACKLOG.md:133 (HITL-1's Done row): it carries
# `triggered\|none\|uncertain`, giving NF=7 where every other Done row has NF=5, which parks the
# 'L1 retro' marker in field 6 instead of field 4. Plain cell() would read a TRUNCATED retro and
# could both trip the substance floor and lose the marker on a perfectly valid row.
# Retro/outcome is the LAST column of the shipped Done schema, so every extra split belongs to it:
# rejoin fields (i+1)..NF, dropping the trailing empty the closing pipe produces. GUARD: if any
# NAMED column follows Retro/outcome, joining would over-capture (a fail-OPEN), so fall back to
# cell() in that case. The shared-parser gap itself is boarded, not fixed here — fixing cell() means
# re-proving check_section, check_done_uat and backlog-presence, which is its own slice.
retro_cell() {
  _rc_after=$(printf '%s' "$2" | awk -F'|' -v i="$3" \
    '{for(j=i+2;j<=NF;j++){v=$j; gsub(/^[ \t]+|[ \t]+$/,"",v); if(v!=""){print "y"; exit}}}')
  if [ -n "$_rc_after" ]; then cell "$1" "$3"; return 0; fi
  printf '%s' "$1" | awk -F'|' -v i="$3" '{
    s=""; for(j=i+1;j<=NF;j++){ if(j==NF && $j ~ /^[[:space:]]*$/) continue
      s = s (s==""?"":"|") $j }
    gsub(/^[ \t]+|[ \t]+$/,"",s); print s}'
}

# check_done_retro <file> : Done-edge L1-retro enforcement (HITL-6). "The loop closes" is a stated
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
  _rows=$(section_rows "$_f" "Done")
  [ -n "$_rows" ] || return 0                     # no Done table at all -> nothing to enforce
  _hdr=$(printf '%s\n' "$_rows" | head -1)
  _ci_c=$(col_index "$_hdr" "Closed")
  _ci_r=$(col_index "$_hdr" "Retro/outcome")
  if [ -z "$_ci_c" ] || [ -z "$_ci_r" ]; then
    echo "FAIL: Done table lacks a 'Closed' and/or 'Retro/outcome' column (found: $(header_cols "$_hdr")); HITL-6 cannot grade an L1 retro without both"
    return 1
  fi
  _epoch_n=$(printf '%s' "$HITL6_RETRO_EPOCH" | tr -d '-')
  _ln=0
  while IFS= read -r _row; do
    _ln=$((_ln + 1))
    if [ "$_ln" -eq 1 ]; then continue; fi        # header row
    if is_sep_row "$_row"; then continue; fi      # separator row (has a dash)
    _item=$(cell "$_row" 1)
    if [ -z "$_item" ]; then continue; fi         # template 'no items' spacer row
    _closed=$(cell "$_row" "$_ci_c")
    _retro=$(retro_cell "$_row" "$_hdr" "$_ci_r")
    DONE_RETRO_GRADED=$((DONE_RETRO_GRADED + 1))
    # leg 1 — substance floor, EVERY row regardless of date.
    _len=${#_retro}
    if [ "$_len" -lt "$HITL6_MIN_RETRO_CHARS" ]; then
      echo "FAIL: Done item '$_item' — Retro/outcome cell is too thin ($_len chars, floor $HITL6_MIN_RETRO_CHARS); a Done row must record what shipped and what was learned"
      return 1
    fi
    # leg 2 — explicit marker for rows Closed on/after the epoch. A date this cannot parse falls
    # THROUGH to the marker requirement (fail closed); it is never skipped.
    case "$_closed" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
        _cn=$(printf '%s' "$_closed" | tr -d '-')
        if [ "$_cn" -lt "$_epoch_n" ]; then continue; fi ;;   # pre-epoch -> N/A for the marker
    esac
    case "$_retro" in
      *"L1 retro"*) ;;
      *)
        echo "FAIL: Done item '$_item' — closed '$_closed' (on/after $HITL6_RETRO_EPOCH, or undated) but carries no 'L1 retro' marker; a Done item must record an L1 retro"
        return 1
        ;;
    esac
  done <<EOF
$_rows
EOF
  return 0
}

# _arity_nf <row> : the row's FIELD count under GFM delimiter rules — `awk -F'|' NF` AFTER removing
# every ESCAPED pipe (`\|`), which GFM renders as a literal and which therefore does NOT delimit a
# column. NOTE the units: on a pipe-BOUNDED row (the canonical GFM form the template ships) NF
# counts the two EMPTY boundary fields as well, so a 3-column row returns 5. The comparison below
# is NF-to-NF so the units cancel; the FAIL MESSAGE subtracts them, because a board author counts
# columns, not awk fields.
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
# This is NOT a fix for BOARD-PIPE-ESCAPE (the shared cell() splitting on raw pipes, boarded
# separately): it only makes THIS check count what a GFM renderer counts.
_arity_nf() { printf '%s' "$1" | sed 's/\\|//g' | awk -F'|' '{print NF}'; }

# _ra_label <row> : the row's FIRST non-empty cell — the name a diagnostic calls the row by. Empty
# output means EVERY cell is empty, which is also the TRUE-spacer test (see _arity_one_section).
# Deliberately variable-free (a pure pipeline) so it cannot collide with any caller's namespace.
_ra_label() {
  printf '%s' "$1" | awk -F'|' '{for(i=2;i<=NF;i++){v=$i; gsub(/^[ \t]+|[ \t]+$/,"",v);
    if(v!=""){print v; exit}}}'
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
      # Report COLUMNS, not awk fields: NF counts the two empty boundary fields of a pipe-bounded
      # row, so the raw numbers read one table wider than the one the author is looking at (the
      # live board printed "19 against 10" for an 8-column table). A message a board author cannot
      # count against is a message that sends them to the wrong cell.
      echo "FAIL: '$_ra_sec' row '$_ra_item' carries $((_ra_got - 2)) columns but the section header declares $((_ra_want - 2)) — an unescaped '|' inside a cell shifts every later column and silently corrupts this row's metadata (escape it as '\\|')"
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

# check_dir <project-dir> -> routes the three N/A cases; for an in-use BACKLOG.md, parses the
# state tables. N/A is always a pass (never a false FAIL). OK/FAIL reflect the board.
check_dir() {
  _dir="$1"
  _tok=$(resolve_backend "$_dir")
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
  if [ "$_tok" != "md" ]; then
    echo "N/A: $_dir — backend '$_tok' is not BACKLOG.md (repo-native board checks skip; conformance/backlog-adapters.sh owns backend-name agreement) — skipping"
    return 0
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
  check_done_retro "$_bl" || _agg=1
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

  # filled Jira (annotated) -> N/A via the not-BACKLOG.md route, naming 'jira'.
  d="$base/t0_jira"; mkdir -p "$d"
  _claude_md 'Jira — [link] (mapping: `docs/work-tracking/adapters.md`)' "$d/CLAUDE.md"
  assert_msg "$d" "backend 'jira' is not BACKLOG.md" "t0/jira: Jira -> N/A (names 'jira', not 'undeclared')"

  # Azure DevOps -> N/A naming 'ado' (alias), NOT 'undeclared'.
  d="$base/t0_ado"; mkdir -p "$d"
  _claude_md 'Azure DevOps — [link]' "$d/CLAUDE.md"
  assert_msg "$d" "backend 'ado' is not BACKLOG.md" "t0/ado: 'Azure DevOps' -> N/A (aliases to 'ado')"

  # one fixture per remaining backend -> N/A (not-BACKLOG.md route).
  d="$base/t0_github"; mkdir -p "$d"
  _claude_md 'GitHub — [link] (mapping: `docs/work-tracking/adapters.md`)' "$d/CLAUDE.md"
  assert_msg "$d" "backend 'github' is not BACKLOG.md" "t0/github: GitHub -> N/A (names 'github')"

  d="$base/t0_linear"; mkdir -p "$d"
  _claude_md 'Linear — [link] (mapping: `docs/work-tracking/adapters.md`)' "$d/CLAUDE.md"
  assert_msg "$d" "backend 'linear' is not BACKLOG.md" "t0/linear: Linear -> N/A (names 'linear')"

  d="$base/t0_gitlab"; mkdir -p "$d"
  _claude_md 'GitLab — [link] (mapping: `docs/work-tracking/adapters.md`)' "$d/CLAUDE.md"
  assert_msg "$d" "backend 'gitlab' is not BACKLOG.md" "t0/gitlab: GitLab -> N/A (names 'gitlab')"

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
| Add login | ISBrad72 | #34 |
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
| Add login | ISBrad72 |  |
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
| Add login | ISBrad72 | #34 |
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
| Add login | ISBrad72 | #34 |
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
| Add login | ISBrad72 | N/A — not opened yet |
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
| Add login | ISBrad72 | #34 |
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
| Add login | ISBrad72 | #34 |
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
| Add login | ISBrad72 | #34 |
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
| Add login | ISBrad72 | #34 |

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
| Add login | ISBrad72 | #34 |

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
| Add login | ISBrad72 | #34 |

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
| Add login | ISBrad72 | #34 |

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
| Add login | ISBrad72 | #34 |

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
| Add login | ISBrad72 | #34 |

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
| Add login | ISBrad72 | #34 |
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
| Add login | ISBrad72 |  |
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
| Add login | ISBrad72 | #34 |

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
| Add login | ISBrad72 | #34 |
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
| Add login | ISBrad72 |  |
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
| Add login | ISBrad72 | #34 |

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
| Add login | ISBrad72 | #34 |

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
| Add login | ISBrad72 | #34 |

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
| Add login | ISBrad72 | #34 |

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
| Add login | ISBrad72 | #34 |

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|
| Add login | 2026-07-25 | shipped to production on the Friday and ramped without incident; the session store moved to Redis and p95 login latency dropped from 410ms to 120ms. |
EOF
  assert_fail "$d" "carries no 'L1 retro' marker" "bad-done-postepoch-no-marker: post-epoch, no marker -> FAIL"

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
| Add login | ISBrad72 | #34 |

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
| Add login | ISBrad72 | #34 |

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|
| Add login | 2026-07-24 | shipped to production on the Friday and ramped without incident; the session store moved to Redis and p95 login latency dropped from 410ms to 120ms. |
EOF
  assert_fail "$d" "carries no 'L1 retro' marker" "bad-done-onepoch-no-marker: ON the epoch, no marker -> FAIL (locks >= inclusivity)"

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
| Add login | ISBrad72 | #34 |

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|
| Add login | someday | shipped to production on the Friday and ramped without incident; the session store moved to Redis and p95 login latency dropped from 410ms to 120ms. |
EOF
  assert_fail "$d" "carries no 'L1 retro' marker" "bad-done-malformed-date: unparseable Closed -> FAIL CLOSED"

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
| Add login | ISBrad72 | #34 |

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
| Add login | ISBrad72 | #34 |

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|
| Add login | 2026-07-25 | shipped the `triggered\|none\|uncertain` detector with fail-closed derivation; the escaped pipes here are GFM-correct and must not shift the parse. L1 retro in #99. |
EOF
  # NB: no backticks in this label — inside a double-quoted shell string they are COMMAND
  # SUBSTITUTION, which silently ate the label text on the first version of this line.
  assert_ok "$d" 'good-done-escaped-pipe: GFM escaped pipe in retro cell -> parsed whole (PASS)'

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
| Add login | ISBrad72 | #34 |
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

# --- fixture writers --------------------------------------------------------------------
# _claude_md <backend-value> <dest-CLAUDE.md> : write a CLAUDE.md declaring the backend.
_claude_md() { printf '# CLAUDE\n\n- **Backlog backend** (§6): %s\n' "$1" > "$2"; }

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
| Add login | ISBrad72 | #34 |

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

case "${1:-}" in
  --selftest) selftest ;;
  *)          check_dir "${1:-.}" ;;
esac
exit $?
