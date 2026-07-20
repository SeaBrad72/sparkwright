#!/bin/sh
# backlog-current.sh — KW6-A conformance lock (T1 routing + T2 board checks).
# Resolves a project's declared backlog backend (from its own CLAUDE.md), N/As the
# not-applicable routes, and — for a repo-native BACKLOG.md that is in use — asserts the
# state-table item-traceability the loop depends on: In Progress -> Links, In Review -> PR,
# and (only if the OPTIONAL section is present) Blocked -> Blocked on + Since.
#
#   sh conformance/backlog-current.sh [project-dir]   (default: .)
#   sh conformance/backlog-current.sh --selftest
# What it changes: read-only — inspects a project's CLAUDE.md / BACKLOG.md; mutates nothing.
# Guardrails: read-only; no network, no writes; N/A-by-default routing so a not-applicable
#   project is never a false FAIL (protects the incept first-run-green invariant).
# HONEST CEILING: a green run proves the backend was RESOLVED, correctly ROUTED, and (for an
#   in-use BACKLOG.md) that its In Progress / In Review / Blocked rows carry the required
#   traceability — NOT that those links resolve, that the board is current, that PRs actually
#   merged, or that a blocked item's age is acceptable. Necessary, not sufficient. Gated columns
#   are resolved BY NAME (In Progress→Links, In Review→PR, Blocked→'Blocked on'+'Since'). A gated
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
is_bare_na() {
  _v=$(printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  [ -z "$_v" ] && return 0
  printf '%s' "$_v" | grep -Eiq '^(-|—|n/?a|tbd|none)$'
}
# is_na_reason <cell> : rc0 iff the cell is the kit idiom `N/A — <reason>` (reason present).
is_na_reason() { printf '%s' "$1" | grep -Eiq '^[[:space:]]*n/?a[[:space:]]*(—|-)[[:space:]]*[^[:space:]]'; }

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
  # Parse the gated state tables (Ready/Released/Done are ungated — untouched).
  SPACER_SKIPS=0; NA_ESCAPES=0; BLOCKED_NA_ESCAPES=0; BOARD_TRACE=""; _agg=0
  # Accumulate-all (K11): run EVERY gated section unconditionally and collect every failure,
  # so ONE run surfaces the whole picture — never exit-on-first (fix In Review, re-run, only
  # THEN discover Blocked also failed). return non-zero iff any section failed.
  check_section "$_bl" "In Progress" "Links" progress || _agg=1
  check_section "$_bl" "In Review" "PR" review || _agg=1
  # Blocked is OPTIONAL (Ready/In Progress/In Review are required headings; Blocked is not) —
  # gate it ONLY IF the section is present. A blocked *item* cannot exist without the section,
  # so nothing escapes the gate by the board omitting it.
  if grep -Eq "^## Blocked[[:space:]]*$" "$_bl"; then
    check_section "$_bl" "Blocked" "Blocked on" blocked "Since" || _agg=1
  fi
  [ "$_agg" -ne 0 ] && return 1
  echo "OK: backlog-current — backend is BACKLOG.md and the in-use board traces: $BOARD_TRACE; spacer-rows-skipped=$SPACER_SKIPS; in-progress N/A-escapes=$NA_ESCAPES; blocked N/A-escapes=$BLOCKED_NA_ESCAPES"
  return 0
}

# --- selftest (written FIRST) -----------------------------------------------------------
selftest() {
  st_fail=0
  base=$(mktemp -d)

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

  # good-ready-unrefined/ — a Ready row with blank acceptance criteria must PASS (Ready is
  # ungated; we do NOT over-gate into the Definition of Ready). In Progress/In Review empty.
  d="$base/good-ready-unrefined"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Intent | Acceptance | Size | Risk | Type | Owner | Links |
|------|--------|-----------|------|------|------|-------|-------|
| Refine me | some intent |  | M | low | feature | agent | #99 |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| | | |
EOF
  assert_ok "$d" "good-ready-unrefined: blank Ready acceptance -> PASS (Ready ungated)"

  # bad-missing-section/ — a missing required `## In Review` heading -> FAIL.
  d="$base/bad-missing-section"; mkdir -p "$d"; _claude_md "$_MD" "$d/CLAUDE.md"
  cat > "$d/BACKLOG.md" <<'EOF'
# B
## Ready

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links |
|------|--------------|---------------------|------|------|------|-------|-------|
| [title] | [why] | [testable criteria] | S | low | feature | [who] | [spec] |

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

| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links |
|------|--------------|---------------------|------|------|------|-------|-------|
| [title] | [why] | [testable criteria] | S | low | feature | [who] | [spec] |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links |
|------|--------------|---------------------|------|------|------|-------|-------|
| [title] | [why] | [testable criteria] | S | low | feature | [who] | [spec] |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

| Item | Owner | Links |
|------|-------|-------|
| x | a | #1 |

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

  if [ "$st_fail" -ne 0 ]; then
    echo "backlog-current --selftest: FAIL" >&2
    return 1
  fi
  echo "backlog-current --selftest: OK (fixtures left in $base)"
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

| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links |
|------|--------------|---------------------|------|------|------|-------|-------|
| Add login | ship auth | user can log in | S | med | feature | agent | #12 |

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
