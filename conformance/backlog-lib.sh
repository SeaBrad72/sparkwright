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

# resolve_backend <project-dir> -> echoes a normalized backend token
# (md|github|jira|ado|linear|gitlab), or empty when undeclared. Reads only <dir>/CLAUDE.md.
resolve_backend() {
  _d="$1"; _c="$_d/CLAUDE.md"
  [ -f "$_c" ] || return 0                                   # no CLAUDE.md -> undeclared
  # Field-leading line, tolerating list/bold markers and a `(§6)`-style annotation
  # before the colon (mirrors agentops-ready.sh's field resolution).
  _line=$(grep -Ei '^[-*[:space:]]*\**backlog backend\**[^:]*:' "$_c" 2>/dev/null | head -1) || true
  [ -n "$_line" ] || return 0                               # field absent -> undeclared
  _val=${_line#*:}                                          # value after the first colon
  # Cut the annotation: everything after the first em-dash, or the first space-then-paren,
  # is annotation (`— [link]`, ` (mapping: …)`, ` (repo-native)`), never the value. The
  # space-paren form is deliberate — it strips ` (mapping…)` while preserving a markdown
  # link's `](url)`. This also stops a GitHub URL in the `— [link]` annotation from
  # resolving a Jira project to `github`. Then trim surrounding whitespace.
  _val=$(printf '%s' "$_val" | sed 's/—.*$//; s/ (.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')
  [ -n "$_val" ] || return 0                                # empty value after the colon -> undeclared
  # Unfilled placeholder = a bracketed *choice-list*: brackets AND a `/` separator inside
  # them. Mirrors agentops-ready.sh:28, which skips only on the choice-list shape, never on
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
  _res=$(printf '%s' "$_lv" | grep -Eo 'github|jira|ado|linear|gitlab' | head -1) || true
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
# cell <row> <1-based-index> : the trimmed content of the Nth pipe-delimited cell.
cell() { printf '%s' "$1" | awk -F'|' -v i="$2" '{v=$(i+1); gsub(/^[ \t]+|[ \t]+$/,"",v); print v}'; }
# col_index <header-row> <column-name> : the 1-based index of the column named <column-name>,
# resolved BY NAME (never by a hardcoded position). Empty if the column is absent.
col_index() {
  printf '%s' "$1" | awk -F'|' -v want="$2" '
    {for(i=2;i<=NF;i++){v=$i; gsub(/^[ \t]+|[ \t]+$/,"",v); if(v==want){print i-1; exit}}}'
}
# is_sep_row <row> : rc0 iff the row is a markdown separator. CRITICAL: it must contain at
# least one dash, so a blank spacer row `| | | |` (pipes+spaces only) is NOT matched — that
# row belongs to the Item-empty skip, not the separator branch (the known vacuity trap).
is_sep_row() { printf '%s' "$1" | grep -Eq '^[[:space:]]*\|[[:space:]|:]*-[[:space:]|:-]*\|[[:space:]]*$'; }
