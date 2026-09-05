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
  # before the colon (mirrors surface-lib.sh's is_agentic field resolution).
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

# --- SLICE-CLOSES-IN-ONE-PR primitives (shared by BOTH board gates) ----------------------
# ⚠️ MUTATION COVERAGE OF EVERYTHING BELOW — STATED, NOT ASSUMED (review m3). This file is listed in
# conformance/aggregate-exclusions.txt — it is sourced, never run, and has no selftest surface — so
# `non-vacuity.sh` NEVER mutates a line of it. Two consequences a reader must not have to derive:
#   (1) moving retro_cell here took it OUT of backlog-current.sh's mutation region — the sweep used
#       to be able to neuter it there and can no longer reach it anywhere;
#   (2) gfm_cell, closed_pre_epoch and retro_cell are proven only BEHAVIOURALLY, by the two gates'
#       own selftests (dispo/escaped-item-pipe, dispo/escaped-pipe, dispo/pre-epoch, dispo/bad-date,
#       t1c/done-pre-epoch, t1c/done-bad-date, t1c/done-escaped-pipe), each watched red against a
#       hand-applied mutant (M-GFM, M-DA1) — never by the automated sweep.
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
  _cpe_c=$(printf '%s' "$1" | tr -d '-')
  _cpe_e=$(printf '%s' "$2" | tr -d '-')
  [ "$_cpe_c" -lt "$_cpe_e" ]
}

# gfm_cell <row> <1-based-index> : cell() under GFM DELIMITER RULES — an escaped pipe (`\|`)
# renders as a literal and does NOT delimit a column, so the split re-joins across it. cell() splits
# on every raw '|', which shifts every column to the RIGHT of an escaped pipe.
# WHY IT EXISTS AND WHERE IT CAME FROM: measured on this repo's own board while building
# SLICE-CLOSES-IN-ONE-PR. The `B8` Done row carries `RELEASE_TAG_PROVENANCE=observe\|enforce` in its
# ITEM cell, so cell(row,"Closed") returned "enforce\` dial registered…" instead of `2026-08-09`.
# Any gate that reads a date THROUGH cell() therefore sees an unparseable value on a row that is
# perfectly correct GFM, and a fail-closed date test turns that into a false RED. retro_cell already
# solves this class for the LAST column; this solves it for any column, by the same GFM rule
# `_arity_nf` already counts by. It is deliberately NOT a replacement for cell(): swapping cell()
# wholesale means re-proving check_section, check_done_uat and row_bears_pr, which is BOARD-PIPE-
# ESCAPE's own slice. Callers that read a DATE or an ID use this one.
# ⚠️ DISCLOSED LIMIT (review m5): the join rule is "the accumulated text ends in a backslash", so a
# cell whose CONTENT legitimately ends in `\` (a trailing line-continuation, a lone escape) is joined
# with the cell after it and the column read is wrong. In every caller here that lands on a DATE, and
# an unparseable date is treated as IN SCOPE — fail-CLOSED, a false RED, never a bypass. A GFM-exact
# parse needs backslash-run counting (`\\|` is an escaped backslash then a DELIMITER); that belongs
# to BOARD-PIPE-ESCAPE with the cell() fix, not to a helper two gates read a date through.
gfm_cell() {
  printf '%s' "$1" | awk -F'|' -v i="$2" '{
    n=0; s=""
    for (j=2; j<=NF; j++) {
      s = (s=="") ? $j : s "|" $j
      if (s ~ /\\$/) continue            # a trailing backslash: THAT pipe was escaped, keep joining
      n++
      if (n==i) { gsub(/^[ \t]+|[ \t]+$/,"",s); print s; exit }
      s=""
    }
  }'
}

# --- NOT ENFORCED — THE NON-MD VERDICT (NON-MD-BACKEND-NEVER-SILENT) --------------------
# not_enforced_notice <backend> <project-dir> <waivers-valid.sh path>
#   prints ONE verdict line on stdout · rc 3 = NOT ENFORCED (red) · rc 0 = waived, with the
#   notice still printed.
# WHY IT LIVES HERE and not three times in three gates: `backlog-presence.sh`, `backlog-current.sh`
# and `loop-state.sh` must say the SAME sentence about the SAME condition. The design asked for
# "text identical in all three scripts"; three copies of a sentence is exactly the drift this
# library exists to prevent, so there is one copy and three callers.
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
not_enforced_notice() {
  # The backend token is repo text on its way to a CI log. It is one of five fixed tokens on this
  # path today, but strip C0/DEL anyway — the same reason loop-state's ls_safe exists.
  _ne_b=$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177')
  _ne_d="$2"; _ne_s="$3"; _ne_w=""
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
  echo "NOT ENFORCED: backend '$_ne_b' — board-bound governance is not verified on this tree (the kit reads BACKLOG.md only; see docs/work-tracking/adapters.md §Which gates bind). Cure: TRACKER-BACKED-GOVERNANCE, or ratify a board-governance waiver (templates/WAIVER-REGISTER.md)."
  return 3
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

# retro_cell <row> <header-row> <col-index> : the Retro/outcome cell, ROBUST to escaped pipes.
# MOVED HERE from backlog-current.sh (SLICE-CLOSES-IN-ONE-PR §4.2) unchanged, because
# backlog-presence.sh's Done arm must read the SAME cell the retro gate grades — two extractions
# of one cell would drift invisibly to both gates' tests, which is this library's whole reason.
# WHY IT EXISTS: GFM treats `\|` as a literal pipe inside a table cell, but cell() splits on every
# raw '|' via awk -F'|', so a row using the CORRECT markdown escape has its trailing columns
# shifted. MEASURED on BACKLOG.md (HITL-1's Done row): it carries `triggered\|none\|uncertain`,
# giving NF=7 where every other Done row has NF=5, which parks the 'L1 retro' marker in field 6
# instead of field 4. Plain cell() would read a TRUNCATED retro and could both trip the substance
# floor and lose the marker on a perfectly valid row.
# Retro/outcome is the LAST column of the shipped Done schema, so every extra split belongs to it:
# rejoin fields (i+1)..NF, dropping the trailing empty the closing pipe produces. GUARD: if any
# NAMED column follows Retro/outcome, joining would over-capture (a fail-OPEN), so fall back to
# cell() in that case. The shared-parser gap itself is boarded (BOARD-PIPE-ESCAPE), not fixed here:
# fixing cell() means re-proving check_section, check_done_uat and backlog-presence.
retro_cell() {
  _rc_after=$(printf '%s' "$2" | awk -F'|' -v i="$3" \
    '{for(j=i+2;j<=NF;j++){v=$j; gsub(/^[ \t]+|[ \t]+$/,"",v); if(v!=""){print "y"; exit}}}')
  if [ -n "$_rc_after" ]; then cell "$1" "$3"; return 0; fi
  printf '%s' "$1" | awk -F'|' -v i="$3" '{
    s=""; for(j=i+1;j<=NF;j++){ if(j==NF && $j ~ /^[[:space:]]*$/) continue
      s = s (s==""?"":"|") $j }
    gsub(/^[ \t]+|[ \t]+$/,"",s); print s}'
}
