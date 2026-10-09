#!/bin/sh
# board-migrate.sh — `board migrate`: move a markdown board's open rows into the declared tracker (KIT-TREE-BOARD-MIGRATION;
# design docs/architecture/2026-10-08-kit-tree-board-migration-design.md).
#
#   sh scripts/board.sh migrate --from <board.md> --plan <plan.tsv> [--ledger <path>] [--screen <file>] [--date <YYYY-MM-DD>] [--dry-run]
#   sh scripts/board.sh migrate --from <board.md> --plan <plan.tsv> [--ledger <path>] --freeze --date <YYYY-MM-DD>
#   sh scripts/board-migrate.sh --selftest
#
# The PLAN (TAB-separated; `#` comments; the row order is the rank order) is the one input that says what happens to each row:
#   epic<TAB>NAME                                    an epic, created first, in file order
#   row<TAB>ID<TAB>keep<TAB>EPIC                     becomes a card under EPIC (the epic named `Parked` also gets the label `parked` + Backlog)
#   row<TAB>ID<TAB>drop<TAB>-<TAB>REASON             no card; --freeze writes a Done entry "dropped at migration triage - REASON"
#   row<TAB>ID<TAB>merge:OTHER<TAB>-<TAB>REASON      no card; OTHER (a keep row) gains an "Absorbs" line; --freeze writes a Done pointer
#   row<TAB>ID<TAB>stay<TAB>-[<TAB>REASON]           no card; the row stays, unedited, in the frozen file
#   new<TAB>ID<TAB>EPIC<TAB>SIZE<TAB>RISK<TAB>INTENT a card that is on no board today (SIZE/RISK `-` = S / med)
# Every row the verb would move must be in the plan exactly once; a row missing from the plan, a plan row naming no board row,
# an undeclared epic, a merge into a non-keep row, a missing reason, a control byte, a bad `new` line, or more than `list_cap`
# epics plus cards refuses the run - every reason at once, zero tracker calls (a dry run included).
#
# What it changes: a tracker, ONLY through `board.sh create` (which keeps its required-field refusal and its read-back proof) and
#   `tracker-jira.sh transition`; and, with --freeze, the board file itself plus the ledger it reads. --dry-run and every refusal
#   make no tracker call of any kind. The ledger (`ROW-ID<TAB>KEY<TAB>created|done`, append-only, last line wins) makes a stopped run
#   resumable: a re-run skips `done` rows, only transitions a `created` row, and creates the rest. The census reads the project
#   through `list-in-states` and exits 1 on a count that differs from the ledger.
# Guardrails: credentials are the environment's KIT_TRACKER_USER/KIT_TRACKER_TOKEN and are never taken as an argument, printed or
#   stored. `BM_BOARD_SH` / `BM_JIRA_SH` / `BM_CONF_SH` / `BM_LIB_SH` are plain script variables (the board.sh precedent): only
#   `--selftest` repoints them, at stubs it generates; nothing outside this file can redirect the writer. `--screen` refuses a card that
#   names an entry of an identifier list (the publish gate's grammar) and prints only the row ID and a hit count.
# STATED CEILINGS: rank is the creation order, which a Jira Software board turns into rank - the fixtures prove the order, not the
#   site; a crash between a card's POST and its ledger line, then a re-run, creates that card twice (the census shows it, one
#   delete by the owner cures it); the adapter's `permissions` probe says only "holds a write permission", not which one.
set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
BM_BOARD_SH="$here/board.sh"
BM_JIRA_SH="$here/tracker-jira.sh"
BM_CONF_SH="$here/tracker-conf.sh"
BM_LIB_SH="$(dirname "$here")/conformance/backlog-lib.sh"
BM_FIXTURES="$(dirname "$here")/conformance/fixtures/board-migrate"

BM_TAB=$(printf '\t')
# The unit separator (\037), not the control-A byte: bash 3.2 does not split `read` on it (its internal CTLESC byte).
BM_US=$(printf '\037')
BM_SIZES='XS S M L XL'
BM_PARKED='Parked'

bm_usage() {
  echo "usage:" >&2
  echo "  board.sh migrate --from <board.md> --plan <plan.tsv> [--ledger <path>] [--screen <file>] [--date <YYYY-MM-DD>] [--dry-run]" >&2
  echo "  board.sh migrate --from <board.md> --plan <plan.tsv> [--ledger <path>] --freeze --date <YYYY-MM-DD>" >&2
  echo "  board-migrate.sh --selftest" >&2
}

# ── small helpers ──────────────────────────────────────────────────────────────────────────────────
# bm_disp <text>: a printable-ASCII, length-bounded copy for a sentence (plan text is untrusted).
bm_disp() { printf '%s' "$1" | LC_ALL=C tr -cd '\40-\176' | cut -c1-60; }
# bm_reason <sentence>: one refusal reason; nothing is printed until bm_flush prints them all at once.
bm_reason() { printf '%s\n' "$1" >> "$bm_work/reasons"; }
bm_flush() {
  [ -s "$bm_work/reasons" ] || return 0
  _bf_n=$(wc -l < "$bm_work/reasons" | tr -d ' ')
  echo "board migrate: REFUSED - $_bf_n reason(s); nothing was written:" >&2
  sed 's/^/  - /' "$bm_work/reasons" >&2
  return 2
}
# bm_rf <ROW-ID> <file>: one stored field of a parsed row, empty when absent.
bm_rf() { cat "$bm_work/rows/$1/$2" 2>/dev/null || true; }
bm_in() { grep -qxF -e "$2" "$1"; }   # bm_in <file> <line>
bm_join() { if [ -z "$1" ]; then printf '%s' "$2"; elif [ -z "$2" ]; then printf '%s' "$1"; else printf '%s\n%s' "$1" "$2"; fi; }
# bm_val <cell>: trimmed; a bare dash means "no value".
bm_val() {
  _bv=$(printf '%s' "$1" | sed 's/^[ ]*//; s/[ ]*$//')
  case "$_bv" in '-'|'—') _bv="" ;; esac
  printf '%s' "$_bv"
}
bm_unesc() { awk '{ gsub(/\\\|/, "|"); gsub(/<br ?\/?>/, "\n"); print }'; }   # a cell's text: \| -> |, <br> -> newline
bm_cellv() { cell "$1" "$2" | bm_unesc; }
# bm_item_text <item cell>: the text after the backticked ID, leading decoration removed.
bm_item_text() {
  _it=${1#*\`}; _it=${_it#*\`}
  printf '%s' "$_it" | sed -E 's/^( |\*|★|✅|⏸|—|-|:)+//'
}
bm_date_ok() {
  case "$1" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;; *) return 1 ;; esac
  _dm=${1#*-}; _dd=${_dm#*-}; _dm=${_dm%%-*}
  case "$_dm" in 0[1-9]|1[0-2]) : ;; *) return 1 ;; esac
  case "$_dd" in 0[1-9]|[12][0-9]|3[01]) return 0 ;; esac
  return 1
}
bm_cget() { # <conf key> -> its value, or empty
  [ -f "$bm_conf_file" ] || return 0
  sh "$BM_CONF_SH" get "$1" "$bm_conf_file" 2>/dev/null || true
}
# bm_ledger_get <id> -> "KEY<TAB>step" (the last line for that id wins), or empty.
bm_ledger_get() {
  [ -f "$bm_ledger_path" ] || return 0
  _lg_k=""; _lg_s=""
  while IFS="$BM_TAB" read -r _lg_a _lg_b _lg_c; do
    if [ "$_lg_a" = "$1" ]; then _lg_k=$_lg_b; _lg_s=$_lg_c; fi
  done < "$bm_ledger_path"
  [ -z "$_lg_k" ] || printf '%s\t%s\n' "$_lg_k" "$_lg_s"
}
bm_ledger_add() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$bm_ledger_path"; }

# ── arguments ──────────────────────────────────────────────────────────────────────────────────────
bm_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) bm_dry=1; shift ;;
      --freeze) bm_freeze=1; shift ;;
      --from|--plan|--ledger|--screen|--date)
        [ $# -ge 2 ] || { echo "board migrate: $1 needs a value" >&2; return 2; }
        case "$1" in
          --from) bm_from=$2 ;;
          --plan) bm_plan=$2 ;;
          --ledger) bm_ledger_arg=$2 ;;
          --screen) bm_screen=$2 ;;
          --date) bm_date=$2 ;;
        esac
        shift 2 ;;
      *) echo "board migrate: unknown argument '$(bm_disp "$1")'" >&2; bm_usage; return 2 ;;
    esac
  done
  if [ -z "$bm_from" ] || [ -z "$bm_plan" ]; then echo "board migrate: --from and --plan are required" >&2; bm_usage; return 2; fi
  if [ "$bm_freeze" = 1 ]; then
    [ -n "$bm_date" ] || { echo "board migrate: --freeze needs --date <YYYY-MM-DD>" >&2; return 2; }
    if [ "$bm_dry" = 1 ] || [ -n "$bm_screen" ]; then echo "board migrate: --freeze takes no --dry-run and no --screen" >&2; return 2; fi
  fi
  [ -n "$bm_date" ] || bm_date=$(date +%Y-%m-%d)
  bm_date_ok "$bm_date" || { echo "board migrate: --date must be YYYY-MM-DD" >&2; return 2; }
  return 0
}

# bm_backend_gate: the verb moves rows INTO a tracker. The conf's own backend key governs when a conf exists
# (the verb gates on the conf's backend, not on the CLAUDE.md declaration; the live run happens AFTER the declaration is
# flipped, because `board create` reads it); otherwise the frozen seam answers.
bm_backend_gate() {
  bm_be=""
  if [ -f "$bm_conf_file" ]; then bm_be=$(sh "$BM_CONF_SH" get backend "$bm_conf_file" 2>/dev/null) || bm_be=""; fi
  if [ -z "$bm_be" ]; then
    # shellcheck disable=SC2034  # read by seam_backend() inside the sourced BM_LIB_SH
    SEAM_ROOT="$bm_root"
    bm_be=$(seam_backend 2>/dev/null) || bm_be=""
  fi
  case "$bm_be" in
    jira) return 0 ;;
    md|'') echo "board migrate: migrate moves rows INTO a tracker; declare the tracker first (.kit/tracker.conf)." >&2; return 2 ;;
    *) echo "board migrate: no write adapter for backend '$(bm_disp "$bm_be")'." >&2; return 2 ;;
  esac
}

# ── the board ──────────────────────────────────────────────────────────────────────────────────────
# bm_ids_of <Section>: the backticked IDs of a section's Item column, one per line.
bm_ids_of() {
  # shellcheck disable=SC2016  # the sed program holds literal backticks
  cells_in_section "$bm_from" "$1" 1 | sed -n 's/^[^`]*`\([^`]*\)`.*$/\1/p' | grep -E '^[A-Z0-9][A-Z0-9-]*$' || true
}

# bm_parse_table <Section> <ready|blocked>: one directory per row under $bm_work/rows/<ID>/. Columns are found by
# header name, never by position. A row whose cell count differs from its header is marked `malformed`.
bm_parse_table() {
  _pt_sec=$1; _pt_kind=$2
  _pt_rows=$(section_rows "$bm_from" "$_pt_sec")
  [ -n "$_pt_rows" ] || return 0
  _pt_hdr=$(printf '%s\n' "$_pt_rows" | sed -n 1p)
  _pt_hn=$(gfm_nf "$_pt_hdr")
  if [ "$_pt_kind" = ready ]; then
    _c_intent=$(col_index "$_pt_hdr" "Intent (why)"); _c_acc=$(col_index "$_pt_hdr" "Acceptance criteria")
    _c_size=$(col_index "$_pt_hdr" "Size"); _c_risk=$(col_index "$_pt_hdr" "Risk"); _c_type=$(col_index "$_pt_hdr" "Type")
    _c_links=$(col_index "$_pt_hdr" "Links"); _c_metric=$(col_index "$_pt_hdr" "Success metric / hypothesis")
  else
    _c_blk=$(col_index "$_pt_hdr" "Blocked on"); _c_since=$(col_index "$_pt_hdr" "Since"); _c_links=$(col_index "$_pt_hdr" "Event-retro link")
  fi
  _pt_i=0
  while IFS= read -r _pt_row; do
    _pt_i=$((_pt_i + 1))
    [ "$_pt_i" -gt 1 ] || continue
    if is_sep_row "$_pt_row"; then continue; fi
    _pt_item=$(cell "$_pt_row" 1)
    [ -n "$_pt_item" ] || continue
    _pt_id=$(backtick_id "$_pt_item")
    if ! row_id_ok "$_pt_id"; then continue; fi
    printf '%s\n' "$_pt_id" >> "$bm_work/ids.movable"
    _pt_dir=$bm_work/rows/$_pt_id
    [ ! -d "$_pt_dir" ] || continue
    mkdir -p "$_pt_dir"
    printf '%s' "$_pt_kind" > "$_pt_dir/section"
    _pt_nf=$(gfm_nf "$_pt_row")
    [ "$_pt_nf" = "$_pt_hn" ] || printf '%s %s %s\n' "$_pt_nf" "$_pt_hn" "$_pt_sec" > "$_pt_dir/malformed"
    _pt_text=$(printf '%s' "$_pt_item" | bm_unesc | tr '\n\t' '  ' | sed 's/ *$//')
    printf '%s' "$(bm_item_text "$_pt_text")" > "$_pt_dir/sumtext"
    if [ "$_pt_kind" = ready ]; then
      printf '%s' "$(bm_cellv "$_pt_row" "$_c_intent")" > "$_pt_dir/intent"
      printf '%s' "$(bm_cellv "$_pt_row" "$_c_acc")" > "$_pt_dir/accept"
      printf '%s' "$(bm_cellv "$_pt_row" "$_c_size")" > "$_pt_dir/size"
      printf '%s' "$(bm_cellv "$_pt_row" "$_c_risk")" > "$_pt_dir/risk"
      printf '%s' "$(bm_cellv "$_pt_row" "$_c_type")" > "$_pt_dir/type"
      printf '%s' "$(bm_cellv "$_pt_row" "$_c_links")" > "$_pt_dir/links"
      printf '%s' "$(bm_cellv "$_pt_row" "$_c_metric")" > "$_pt_dir/metric"
    else
      _pt_since=$(bm_cellv "$_pt_row" "$_c_since")
      _pt_intent="Blocked on: $(bm_cellv "$_pt_row" "$_c_blk")"
      [ -z "$_pt_since" ] || _pt_intent=$(bm_join "$_pt_intent" "Since: $_pt_since")
      printf '%s' "$_pt_intent" > "$_pt_dir/intent"
      printf '%s' "$(bm_cellv "$_pt_row" "$_c_links")" > "$_pt_dir/links"
    fi
  done <<EOF_PT
$_pt_rows
EOF_PT
}

# bm_parse_bullets: the `> - [ ] **`ID`**` bullets of `## Backlog (unrefined)`. The heading is matched literally. A
# bullet runs until the next top-level checkbox line, a line not starting with `>`, or the next heading. Every other
# top-level checkbox line is not a row; it is counted, and stays where it is.
bm_parse_bullets() {
  : > "$bm_work/bul.order"; echo 0 > "$bm_work/left"
  mkdir -p "$bm_work/bul"
  awk -v dir="$bm_work/bul" -v order="$bm_work/bul.order" -v leftf="$bm_work/left" '
    BEGIN { insec = 0; infence = 0; inbul = 0; left = 0; cur = "" }
    /^[ \t]*```/ { infence = !infence; inbul = 0; next }
    infence { next }
    /^#/ { insec = ($0 ~ /^## Backlog \(unrefined\)[ \t]*$/); inbul = 0; next }
    insec && /^> - \[ \] \*\*`[A-Z0-9][A-Z0-9-]*`\*\*/ {
      id = $0; sub(/^> - \[ \] \*\*`/, "", id); sub(/`.*$/, "", id)
      txt = $0; sub(/^> - \[ \] \*\*`[A-Z0-9][A-Z0-9-]*`\*\* ?/, "", txt)
      if (cur != "") close(cur)
      print id >> order
      if (id in seen) { cur = dir "/" id ".dup" } else { cur = dir "/" id }
      seen[id] = 1
      print txt > cur
      inbul = 1; next
    }
    /^(> )?- \[[ xX]\]/ { left++; inbul = 0; next }
    inbul && /^>/ { txt = $0; sub(/^> ?/, "", txt); print txt > cur; next }
    { inbul = 0 }
    END { if (cur != "") close(cur); print left > leftf }
  ' "$bm_from"
  while IFS= read -r _bp_id; do
    [ -n "$_bp_id" ] || continue
    bm_one_bullet "$_bp_id"
  done < "$bm_work/bul.order"
}

bm_one_bullet() { # <ID>
  printf '%s\n' "$1" >> "$bm_work/ids.movable"
  _ob_dir=$bm_work/rows/$1
  [ ! -d "$_ob_dir" ] || return 0
  mkdir -p "$_ob_dir"
  printf 'bullet' > "$_ob_dir/section"
  _ob_all=$(cat "$bm_work/bul/$1")
  _ob_first=$(printf '%s\n' "$_ob_all" | sed -n 1p)
  _ob_more=$(printf '%s\n' "$_ob_all" | sed -n '2,$p')
  _ob_paren=""; _ob_text=$_ob_first
  case "$_ob_first" in
    '('*)
      case "$_ob_first" in
        *' — '*) _ob_paren=${_ob_first%% — *}; _ob_text=${_ob_first#* — } ;;
        *) _ob_paren=$_ob_first; _ob_text="" ;;
      esac ;;
    '— '*) _ob_text=${_ob_first#— } ;;
  esac
  _ob_size=""
  if [ -n "$_ob_paren" ]; then
    _ob_tok=${_ob_paren#\(}; _ob_tok=${_ob_tok%%,*}; _ob_tok=${_ob_tok%%\)*}
    _ob_tok=$(printf '%s' "$_ob_tok" | tr -d ' ')
    case " $BM_SIZES " in *" $_ob_tok "*) [ -z "$_ob_tok" ] || _ob_size=$_ob_tok ;; esac
  fi
  _ob_intent=$(bm_join "$_ob_paren" "$_ob_text")
  _ob_intent=$(bm_join "$_ob_intent" "$_ob_more")
  _ob_sum=$_ob_text
  [ -n "$_ob_sum" ] || _ob_sum=$_ob_paren
  printf '%s' "$(printf '%s' "$_ob_sum" | tr '\t' ' ')" > "$_ob_dir/sumtext"
  printf '%s' "$_ob_intent" > "$_ob_dir/intent"
  printf '%s' "$_ob_size" > "$_ob_dir/size"
}

bm_parse_board() {
  : > "$bm_work/ids.movable"; : > "$bm_work/ids.flight"; : > "$bm_work/ids.other"
  mkdir -p "$bm_work/rows"
  bm_parse_table Ready ready
  bm_parse_table Blocked blocked
  bm_parse_bullets
  for _pb_sec in "In Progress" "In Review"; do bm_ids_of "$_pb_sec" >> "$bm_work/ids.flight"; done
  for _pb_sec in Released Done; do bm_ids_of "$_pb_sec" >> "$bm_work/ids.other"; done
  cat "$bm_work/ids.movable" "$bm_work/ids.flight" "$bm_work/ids.other" > "$bm_work/ids.all"
  cat "$bm_work/ids.movable" "$bm_work/ids.flight" | sort | uniq -d | while IFS= read -r _pb_d; do
    bm_reason "board row '$_pb_d' appears more than once in Ready, Blocked, the unrefined bullets, In Progress or In Review"
  done
}

# ── the plan ───────────────────────────────────────────────────────────────────────────────────────
# bm_parse_plan: shape checks per line; cross-checks against the board follow in bm_check_plan. Fields are split on
# TAB through US (\037), so an empty field stays an empty field (a TAB IFS would collapse it).
bm_parse_plan() {
  : > "$bm_work/plan.epics"; : > "$bm_work/plan.rows"; : > "$bm_work/plan.new"; : > "$bm_work/plan.ids"
  _pl_ctl=$(tr -d '\t' < "$bm_plan" | LC_ALL=C grep -n '[[:cntrl:]]' | cut -d: -f1 | tr '\n' ' ')
  [ -z "$_pl_ctl" ] || bm_reason "plan: a control byte on line(s) $_pl_ctl"
  _pl_n=0
  while IFS= read -r _pl_line || [ -n "$_pl_line" ]; do
    _pl_n=$((_pl_n + 1))
    case "$_pl_line" in *[![:space:]]*) : ;; *) continue ;; esac
    case "$_pl_line" in '#'*) continue ;; esac
    _pl_rec=$(printf '%s' "$_pl_line" | tr '\t' '\037')
    IFS=$BM_US read -r _pf1 _pf2 _pf3 _pf4 _pf5 _pf6 _pf7 <<EOF_PL
$_pl_rec
EOF_PL
    case "$_pf1" in
      epic) bm_plan_epic ;;
      row) bm_plan_row ;;
      new) bm_plan_new ;;
      *) bm_reason "plan line $_pl_n: unknown line kind '$(bm_disp "$_pf1")' (use epic, row or new)" ;;
    esac
  done < "$bm_plan"
}

bm_plan_epic() {
  if [ -z "$_pf2" ] || [ "${#_pf2}" -gt 60 ]; then bm_reason "plan line $_pl_n: an epic name is 1-60 characters"; return 0; fi
  [ -z "$_pf3" ] || bm_reason "plan line $_pl_n: an epic line holds only the name"
  if bm_in "$bm_work/plan.epics" "$_pf2"; then bm_reason "plan line $_pl_n: epic '$(bm_disp "$_pf2")' is declared more than once"; return 0; fi
  printf '%s\n' "$_pf2" >> "$bm_work/plan.epics"
}

bm_plan_row() {
  _pr_id=$_pf2; _pr_fate=$_pf3; _pr_epic=$_pf4; _pr_reason=$_pf5
  if ! row_id_ok "$_pr_id"; then bm_reason "plan line $_pl_n: '$(bm_disp "$_pr_id")' is not a row ID ([A-Z0-9][A-Z0-9-]*)"; return 0; fi
  [ -z "$_pf6" ] || bm_reason "plan line $_pl_n ($_pr_id): too many fields"
  case "$_pr_fate" in
    keep|drop|stay) : ;;
    merge:*) row_id_ok "${_pr_fate#merge:}" || bm_reason "plan line $_pl_n ($_pr_id): the merge target '$(bm_disp "${_pr_fate#merge:}")' is not a row ID" ;;
    *) bm_reason "plan line $_pl_n ($_pr_id): fate '$(bm_disp "$_pr_fate")' is not keep, drop, stay or merge:<ID>"; return 0 ;;
  esac
  if [ "$_pr_fate" = keep ]; then
    if [ -z "$_pr_epic" ] || [ "$_pr_epic" = - ]; then bm_reason "plan line $_pl_n ($_pr_id): a keep row names its epic"; fi
  else
    [ "$_pr_epic" = - ] || bm_reason "plan line $_pl_n ($_pr_id): the epic column is - unless the fate is keep"
  fi
  case "$_pr_fate" in
    drop|merge:*)
      if [ -z "$_pr_reason" ] || [ "${#_pr_reason}" -gt 200 ]; then bm_reason "plan line $_pl_n ($_pr_id): a drop or merge row needs a reason of 1-200 characters"; fi ;;
  esac
  if bm_in "$bm_work/plan.ids" "$_pr_id"; then bm_reason "plan line $_pl_n: '$_pr_id' appears more than once in the plan"; return 0; fi
  printf '%s\n' "$_pr_id" >> "$bm_work/plan.ids"
  printf '%s\n' "$_pr_id$BM_US$_pr_fate$BM_US$_pr_epic$BM_US$_pr_reason$BM_US$_pl_n" >> "$bm_work/plan.rows"
}

bm_plan_new() {
  _pn_id=$_pf2; _pn_epic=$_pf3; _pn_size=$_pf4; _pn_risk=$_pf5; _pn_intent=$_pf6
  [ -z "$_pf7" ] || bm_reason "plan line $_pl_n: a new line has six fields"
  if ! row_id_ok "$_pn_id"; then bm_reason "plan line $_pl_n: new ID '$(bm_disp "$_pn_id")' does not match [A-Z0-9][A-Z0-9-]*"; return 0; fi
  if bm_in "$bm_work/ids.all" "$_pn_id"; then bm_reason "plan line $_pl_n: new ID '$_pn_id' collides with a row on the board"; return 0; fi
  if bm_in "$bm_work/plan.ids" "$_pn_id"; then bm_reason "plan line $_pl_n: new ID '$_pn_id' collides with another plan line (an ID appears once)"; return 0; fi
  printf '%s\n' "$_pn_id" >> "$bm_work/plan.ids"
  case " - $BM_SIZES " in *" $_pn_size "*) : ;; *) bm_reason "plan line $_pl_n ($_pn_id): Size '$(bm_disp "$_pn_size")' is not one of XS S M L XL (or -)" ;; esac
  _pn_risks=' - low med high '
  case "$_pn_risks" in *" $_pn_risk "*) : ;; *) bm_reason "plan line $_pl_n ($_pn_id): Risk '$(bm_disp "$_pn_risk")' is not one of low med high (or -)" ;; esac
  if [ -z "$_pn_intent" ]; then bm_reason "plan line $_pl_n ($_pn_id): the new card's intent is empty"
  elif [ "$(printf '%s' "$_pn_intent" | wc -c | tr -d ' ')" -gt 2000 ]; then bm_reason "plan line $_pl_n ($_pn_id): the new card's intent is over 2000 bytes"; fi
  printf '%s\n' "$_pn_id$BM_US$_pn_epic$BM_US$_pn_size$BM_US$_pn_risk$BM_US$_pn_intent$BM_US$_pl_n" >> "$bm_work/plan.new"
}

# bm_check_plan: the plan against the board. Every reason is recorded; nothing stops at the first.
bm_check_plan() {
  : > "$bm_work/plan.keep"
  while IFS=$BM_US read -r _cp_id _cp_fate _cp_epic _cp_why _cp_ln; do
    [ "$_cp_fate" != keep ] || printf '%s\n' "$_cp_id" >> "$bm_work/plan.keep"
  done < "$bm_work/plan.rows"
  while IFS=$BM_US read -r _cp_id _cp_fate _cp_epic _cp_why _cp_ln; do
    [ -n "$_cp_id" ] || continue
    bm_check_row
  done < "$bm_work/plan.rows"
  while IFS= read -r _cp_b; do
    [ -n "$_cp_b" ] || continue
    bm_in "$bm_work/plan.ids" "$_cp_b" || bm_reason "board row '$_cp_b' ($(bm_rf "$_cp_b" section)) is not in the plan"
  done < "$bm_work/ids.movable"
  while IFS= read -r _cp_b; do
    [ -n "$_cp_b" ] || continue
    bm_in "$bm_work/plan.ids" "$_cp_b" || bm_reason "'$_cp_b' is In Progress or In Review and not in the plan: work in flight is not migrated; mark it stay"
  done < "$bm_work/ids.flight"
  while IFS=$BM_US read -r _cp_id _cp_epic _cp_sz _cp_rk _cp_in _cp_ln; do
    [ -n "$_cp_id" ] || continue
    bm_in "$bm_work/plan.epics" "$_cp_epic" || bm_reason "new card '$_cp_id' names the undeclared epic '$(bm_disp "$_cp_epic")'"
  done < "$bm_work/plan.new"
  _cp_total=$(( $(wc -l < "$bm_work/plan.epics") + $(wc -l < "$bm_work/plan.keep") + $(wc -l < "$bm_work/plan.new") ))
  case "$bm_cap" in
    ''|*[!0-9]*) bm_reason "list_cap is not set in .kit/tracker.conf (the census needs it)" ;;
    *) [ "$_cp_total" -le "$bm_cap" ] || bm_reason "the plan creates $_cp_total epics and cards but list_cap is $bm_cap (the census must be able to list them all)" ;;
  esac
}

bm_check_row() {
  if bm_in "$bm_work/ids.movable" "$_cp_id"; then _cr_where=movable
  elif bm_in "$bm_work/ids.flight" "$_cp_id"; then _cr_where=flight
  elif bm_in "$bm_work/ids.other" "$_cp_id"; then _cr_where=other
  else bm_reason "plan row '$_cp_id' is not on the board"; return 0; fi
  case "$_cr_where:$_cp_fate" in
    *:stay) : ;;
    flight:*) bm_reason "'$_cp_id' is In Progress or In Review: work in flight is not migrated; mark it stay" ;;
    other:*) bm_reason "'$_cp_id' is in Released or Done, not an open row; mark it stay" ;;
  esac
  [ "$_cr_where" = movable ] || return 0
  case "$_cp_fate" in
    keep)
      bm_in "$bm_work/plan.epics" "$_cp_epic" || bm_reason "'$_cp_id' names the undeclared epic '$(bm_disp "$_cp_epic")'"
      if [ -f "$bm_work/rows/$_cp_id/malformed" ]; then
        read -r _cr_nf _cr_hn _cr_sec < "$bm_work/rows/$_cp_id/malformed"
        bm_reason "'$_cp_id' has $_cr_nf cells but the $_cr_sec header has $_cr_hn: a kept row cannot become a card; fix the row or change its fate"
      fi ;;
    merge:*)
      _cr_t=${_cp_fate#merge:}
      if [ "$_cr_t" = "$_cp_id" ]; then bm_reason "'$_cp_id' cannot merge into itself"
      elif ! bm_in "$bm_work/plan.keep" "$_cr_t"; then bm_reason "merge target '$(bm_disp "$_cr_t")' of '$_cp_id' is not a keep row"; fi ;;
  esac
}

# ── the cards ──────────────────────────────────────────────────────────────────────────────────────
# bm_make_summary <ID> <text>: the summary; past 240 characters it is cut at the last space and the full text opens the Intent.
bm_make_summary() {
  _ms_dir=$bm_work/rows/$1
  if [ -n "$2" ]; then _ms_full="$1 — $2"; else _ms_full=$1; fi
  _ms_full=$(printf '%s' "$_ms_full" | tr '\t\n' '  ')
  rm -f "$_ms_dir/cut"
  if [ "${#_ms_full}" -le 240 ]; then printf '%s' "$_ms_full" > "$_ms_dir/summary"; return 0; fi
  _ms_head=$(printf '%s' "$_ms_full" | cut -c1-240)
  _ms_head=${_ms_head% *}
  printf '%s…' "$_ms_head" > "$_ms_dir/summary"
  printf '%s' "$_ms_full" > "$_ms_dir/cut"
}

# bm_or_dash <ROW-ID> <field>: the stored field, or a dash when empty.
bm_or_dash() {
  _od=$(bm_rf "$1" "$2")
  if [ -n "$_od" ]; then printf '%s' "$_od"; else printf '—'; fi
}

bm_make_desc() { # <ROW-ID>
  _md_dir=$bm_work/rows/$1
  {
    printf 'Intent\n'
    if [ -f "$_md_dir/cut" ]; then printf '%s\n' "$(cat "$_md_dir/cut")"; fi
    printf '%s\n\n' "$(bm_or_dash "$1" intent)"
    printf 'Acceptance criteria\n%s\n\n' "$(bm_or_dash "$1" accept)"
    printf 'Links\n%s\n\n' "$(bm_or_dash "$1" links)"
    printf 'Success metric\n%s\n\n' "$(bm_or_dash "$1" metric)"
    if [ -f "$bm_work/absorb/$1" ]; then cat "$bm_work/absorb/$1"; fi
    # shellcheck disable=SC2016  # literal backticks around the row ID
    printf 'Migrated from %s row `%s` on %s.\n' "$(basename "$bm_from")" "$1" "$bm_date"
  } > "$_md_dir/desc"
}

# bm_build_cards: $bm_work/cards, one line per card in creation order (keep rows in plan order, then new):
#   kind US ID US epic US state US labels US type US size US risk
bm_build_cards() {
  : > "$bm_work/cards"; mkdir -p "$bm_work/absorb"
  while IFS=$BM_US read -r _bc_id _bc_fate _bc_epic _bc_why _bc_ln; do
    [ "${_bc_fate%%:*}" = merge ] || continue
    # shellcheck disable=SC2016  # literal backticks around the row ID
    printf 'Absorbs `%s`: %s\n' "$_bc_id" "$(bm_rf "$_bc_id" sumtext)" >> "$bm_work/absorb/${_bc_fate#merge:}"
  done < "$bm_work/plan.rows"
  while IFS=$BM_US read -r _bc_id _bc_fate _bc_epic _bc_why _bc_ln; do
    [ "$_bc_fate" = keep ] || continue
    bm_card_keep
  done < "$bm_work/plan.rows"
  while IFS=$BM_US read -r _bc_id _bc_epic _bc_size _bc_risk _bc_intent _bc_ln; do
    [ -n "$_bc_id" ] || continue
    bm_card_new
  done < "$bm_work/plan.new"
}

bm_card_keep() {
  bm_make_summary "$_bc_id" "$(bm_rf "$_bc_id" sumtext)"
  bm_make_desc "$_bc_id"
  _bc_labels=""; _bc_state=backlog
  if [ "$_bc_epic" = "$BM_PARKED" ]; then _bc_labels=parked
  else
    case "$(bm_rf "$_bc_id" section)" in ready) _bc_state=ready ;; blocked) _bc_state=blocked ;; esac
  fi
  _bc_type=Task
  case "$(bm_rf "$_bc_id" type | tr '[:upper:]' '[:lower:]')" in defect|bug) _bc_type=Bug ;; esac
  _bc_sz=$(bm_val "$(bm_rf "$_bc_id" size)"); _bc_rk=$(bm_val "$(bm_rf "$_bc_id" risk)")
  printf 'card%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' "$BM_US" "$_bc_id" "$BM_US" "$_bc_epic" "$BM_US" "$_bc_state" "$BM_US" "$_bc_labels" "$BM_US" "$_bc_type" "$BM_US" "$_bc_sz" "$BM_US" "$_bc_rk" >> "$bm_work/cards"
}

bm_card_new() {
  mkdir -p "$bm_work/rows/$_bc_id"
  printf '%s' "$_bc_id" > "$bm_work/rows/$_bc_id/summary"
  printf '%s\n' "$_bc_intent" > "$bm_work/rows/$_bc_id/desc"
  [ "$_bc_size" != - ] || _bc_size=S
  [ "$_bc_risk" != - ] || _bc_risk=med
  _bc_labels=""
  [ "$_bc_epic" != "$BM_PARKED" ] || _bc_labels=parked
  printf 'new%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' "$BM_US" "$_bc_id" "$BM_US" "$_bc_epic" "$BM_US" backlog "$BM_US" "$_bc_labels" "$BM_US" Task "$BM_US" "$_bc_size" "$BM_US" "$_bc_risk" >> "$bm_work/cards"
}

# bm_check_cards: description bounds (board create's own) and, with --screen, the identifier list. A hit prints the row ID and a
# count, never the entry or the matched text.
bm_check_cards() {
  while IFS=$BM_US read -r _cc_kind _cc_id _cc_rest; do
    [ -n "$_cc_id" ] || continue
    _cc_f=$bm_work/rows/$_cc_id/desc
    _cc_b=$(wc -c < "$_cc_f" | tr -d ' '); _cc_l=$(wc -l < "$_cc_f" | tr -d ' ')
    if [ "$_cc_b" -gt 32000 ] || [ "$_cc_l" -gt 2000 ]; then bm_reason "'$_cc_id': the description is $_cc_b bytes and $_cc_l lines (board create takes at most 32000 and 2000)"; fi
  done < "$bm_work/cards"
  [ -z "$bm_screen" ] || bm_screen_run
}

bm_screen_load() {
  : > "$bm_work/screen.ids"
  # fail CLOSED: a list that cannot be read, or that yields no entry, must never mean "nothing to screen".
  if [ ! -f "$bm_screen" ]; then bm_reason "screen: the identifier list file was not found"; return 0; fi
  if [ ! -r "$bm_screen" ] || ! cat "$bm_screen" >/dev/null 2>&1; then bm_reason "screen: the identifier list file cannot be read"; return 0; fi
  _sl_cr=$(printf '\r'); _sl_n=0; _sl_rc=0
  while IFS= read -r _sl_e || [ -n "$_sl_e" ]; do
    _sl_n=$((_sl_n + 1)); _sl_e=${_sl_e%"$_sl_cr"}
    case $_sl_e in *"$_sl_cr"*) bm_reason "screen list line $_sl_n: a carriage return inside an entry (a CR-only list?)"; continue ;; esac
    case $_sl_e in *[![:space:]]*) : ;; *) continue ;; esac
    _sl_lead=${_sl_e%%[![:space:]]*}
    case ${_sl_e#"$_sl_lead"} in \#*) continue ;; esac
    case $_sl_e in [[:space:]]*|*[[:space:]]) bm_reason "screen list line $_sl_n: an entry has leading or trailing whitespace"; continue ;; esac
    case $_sl_e in
      word:*)
        _sl_v=${_sl_e#word:}
        if [ -z "$_sl_v" ] || printf '%s\n' "$_sl_v" | LC_ALL=C grep -q '[^ -~]'; then bm_reason "screen list line $_sl_n: a word: entry must be a non-empty printable-ASCII value"; continue; fi
        case $_sl_v in [[:space:]]*) bm_reason "screen list line $_sl_n: a word: entry has whitespace after the colon"; continue ;; esac
        printf 'word\t%s\n' "$_sl_v" >> "$bm_work/screen.ids" ;;
      [Ww][Oo][Rr][Dd]:*|[Ww][Oo][Rr][Dd][[:space:]]*:*) bm_reason "screen list line $_sl_n: only exactly lowercase word: starts a whole-word entry" ;;
      *) printf 'plain\t%s\n' "$_sl_e" >> "$bm_work/screen.ids" ;;
    esac
  done < "$bm_screen" || _sl_rc=1
  [ "$_sl_rc" = 0 ] || bm_reason "screen: reading the identifier list failed"
  [ -s "$bm_work/screen.ids" ] || bm_reason "screen: the identifier list holds no entries (a screen of nothing is refused, not skipped)"
}

# bm_screen_hits <file>: the number of matching lines, summed over the list's entries (plain: case-insensitive fixed
# substring; word: whole word under LC_ALL=C - the publish gate's grammar).
bm_screen_hits() {
  _sh_total=0
  while IFS="$BM_TAB" read -r _sh_form _sh_val; do
    [ -n "$_sh_form" ] || continue
    if [ "$_sh_form" = word ]; then _sh_c=$(LC_ALL=C grep -c -i -w -F -e "$_sh_val" "$1" || true)
    else _sh_c=$(grep -c -i -F -e "$_sh_val" "$1" || true); fi
    _sh_total=$((_sh_total + ${_sh_c:-0}))
  done < "$bm_work/screen.ids"
  printf '%s' "$_sh_total"
}

bm_screen_run() {
  bm_screen_load
  [ -s "$bm_work/screen.ids" ] || return 0
  while IFS=$BM_US read -r _sr_kind _sr_id _sr_rest; do
    [ -n "$_sr_id" ] || continue
    cat "$bm_work/rows/$_sr_id/summary" "$bm_work/rows/$_sr_id/desc" > "$bm_work/screen.txt"
    _sr_h=$(bm_screen_hits "$bm_work/screen.txt")
    [ "$_sr_h" -eq 0 ] || bm_reason "screen: $_sr_id: $_sr_h hit(s)"
  done < "$bm_work/cards"
  _sr_k=0
  while IFS= read -r _sr_name; do
    _sr_k=$((_sr_k + 1))
    printf '%s\n' "$_sr_name" > "$bm_work/screen.txt"
    _sr_h=$(bm_screen_hits "$bm_work/screen.txt")
    [ "$_sr_h" -eq 0 ] || bm_reason "screen: epic #$_sr_k: $_sr_h hit(s)"
  done < "$bm_work/plan.epics"
}

# ── the dry run ────────────────────────────────────────────────────────────────────────────────────
bm_print_plan() {
  while IFS=$BM_US read -r _pp_id _pp_fate _pp_epic _pp_why _pp_ln; do
    [ -f "$bm_work/rows/$_pp_id/malformed" ] || continue
    [ "$_pp_fate" != keep ] || continue
    read -r _pp_nf _pp_hn _pp_sec < "$bm_work/rows/$_pp_id/malformed"
    case "$_pp_fate" in merge:*) _pp_w="merged away" ;; drop) _pp_w=dropped ;; *) _pp_w="stays in the file" ;; esac
    echo "note: $_pp_id has $_pp_nf cells but the $_pp_sec header has $_pp_hn ($_pp_w, not migrated)"
  done < "$bm_work/plan.rows"
  while IFS= read -r _pp_e; do printf 'epic\t%s\n' "$_pp_e"; done < "$bm_work/plan.epics"
  _pp_r=0; _pp_b=0; _pp_k=0; _pp_p=0; _pp_m=0
  while IFS=$BM_US read -r _pp_kind _pp_id _pp_epic _pp_state _pp_lab _pp_type _pp_sz _pp_rk; do
    [ -n "$_pp_id" ] || continue
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$_pp_kind" "$(cat "$bm_work/rows/$_pp_id/summary")" "$_pp_type" "$_pp_epic" "$_pp_state" "${_pp_lab:--}" "${_pp_sz:--}" "${_pp_rk:--}"
    _pp_m=$((_pp_m + 1))
    if [ -n "$_pp_lab" ]; then _pp_p=$((_pp_p + 1))
    else case "$_pp_state" in ready) _pp_r=$((_pp_r + 1)) ;; blocked) _pp_b=$((_pp_b + 1)) ;; *) _pp_k=$((_pp_k + 1)) ;; esac; fi
  done < "$bm_work/cards"
  echo "left in place: $(cat "$bm_work/left") checkbox lines"
  _pp_d=$(awk -F"$BM_US" '$2 == "drop"' "$bm_work/plan.rows" | wc -l | tr -d ' ')
  _pp_g=$(awk -F"$BM_US" '$2 ~ /^merge:/' "$bm_work/plan.rows" | wc -l | tr -d ' ')
  _pp_s=$(awk -F"$BM_US" '$2 == "stay"' "$bm_work/plan.rows" | wc -l | tr -d ' ')
  echo "$(wc -l < "$bm_work/plan.epics" | tr -d ' ') epics, $_pp_m cards ($_pp_r ready, $_pp_b blocked, $_pp_k backlog, $_pp_p parked), $_pp_d dropped, $_pp_g merged, $_pp_s stayed"
}

# ── the preflight: reads only ──────────────────────────────────────────────────────────────────────
bm_cm_has() { awk -F'\t' -v f="$2" '$2 == f { y = 1 } END { exit !y }' "$bm_work/cm.$1"; }   # <type> <field-id>

bm_pf_meta() { # <type>
  _pm_rc=0
  sh "$BM_JIRA_SH" create-meta "$bm_base" "$bm_flavour" "$bm_project" "$1" > "$bm_work/cm.$1" 2> "$bm_work/pm.err" || _pm_rc=$?
  case "$_pm_rc" in
    0) return 0 ;;
    3) bm_reason "issue type '$1' is not in project $bm_project (or the token lacks Create permission there)" ;;
    4) bm_reason "issue type name '$1' is ambiguous in project $bm_project" ;;
    *) bm_reason "could not read the create-meta of '$1' (unverified): $(tr -cd '\40-\176' < "$bm_work/pm.err" | cut -c1-120)" ;;
  esac
  return 1
}

# bm_pf_value <type> <Size|Risk> <mapping> <value>: one distinct value against the field it will be written to.
bm_pf_value() {
  case "$3" in
    customfield_*)
      _pv_line=$(awk -F'\t' -v f="$3" '$2 == f { print; exit }' "$bm_work/cm.$1")
      if [ -z "$_pv_line" ]; then bm_reason "$2: $3 is not on the create screen of '$1'"; return 0; fi
      case "$(printf '%s' "$_pv_line" | cut -f3)" in
        option)
          _pv_allowed=$(printf '%s' "$_pv_line" | cut -f5)
          _pv_hit=$(printf '%s\n' "$_pv_allowed" | tr '|' '\n' | awk -v v="$4" 'BEGIN { lv = tolower(v) } tolower($0) == lv { print "y"; exit }')
          [ -n "$_pv_hit" ] || bm_reason "$2 '$(bm_disp "$4")' is not an allowed value of $3 on '$1' (allowed: $(printf '%s' "$_pv_allowed" | sed 's/|/, /g' | cut -c1-80))" ;;
        string) : ;;
        *) bm_reason "$2: $3 on '$1' is neither a select nor a string field; board create cannot write it" ;;
      esac ;;
    label:*)
      if ! printf '%s' "$4" | LC_ALL=C grep -Eq '^[A-Za-z0-9_-]{1,32}$'; then bm_reason "$2 '$(bm_disp "$4")' cannot be written as the label $3 (use [A-Za-z0-9_-]{1,32})"; fi
      bm_cm_has "$1" labels || bm_reason "$2: '$1' has no labels field on its create screen, so $3 cannot be written" ;;
    *) bm_reason "$2 '$(bm_disp "$4")': the conf maps no writable field for it (field.$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')=${3:-unset})" ;;
  esac
}

bm_pf_type_checks() { # <type> (Task or Bug)
  bm_cm_has "$1" parent || bm_reason "issue type '$1' has no parent field on its create screen, so cards cannot be attached to their epic"
  bm_cm_has "$1" description || bm_reason "issue type '$1' has no description field on its create screen"
  if awk -F"$BM_US" -v t="$1" '$6 == t && $5 != "" { y = 1 } END { exit !y }' "$bm_work/cards"; then
    bm_cm_has "$1" labels || bm_reason "issue type '$1' has no labels field on its create screen, so the parked label cannot be written"
  fi
  awk -F"$BM_US" -v t="$1" '$6 == t && $7 != "" { print $7 }' "$bm_work/cards" | sort -u > "$bm_work/vals.size"
  awk -F"$BM_US" -v t="$1" '$6 == t && $8 != "" { print $8 }' "$bm_work/cards" | sort -u > "$bm_work/vals.risk"
  _tc_sm=$(bm_cget field.size); _tc_rm=$(bm_cget field.risk)
  while IFS= read -r _tc_v; do bm_pf_value "$1" Size "$_tc_sm" "$_tc_v"; done < "$bm_work/vals.size"
  while IFS= read -r _tc_v; do bm_pf_value "$1" Risk "$_tc_rm" "$_tc_v"; done < "$bm_work/vals.risk"
}

# bm_pf_required <type>: a required field board create would not fill is a refusal now, not a stop at card 40.
bm_pf_required() {
  _rq_rc=0
  _rq_out=$(sh "$BM_JIRA_SH" required-fields "$bm_base" "$bm_flavour" "$bm_project" "$1" 2>/dev/null) || _rq_rc=$?
  if [ "$_rq_rc" -ne 0 ]; then bm_reason "could not read the required fields of '$1' (unverified)"; return 0; fi
  _rq_sm=$(bm_cget field.size); _rq_rm=$(bm_cget field.risk)
  while IFS="$BM_TAB" read -r _rq_id _rq_kind _rq_name _rq_rest; do
    case "$_rq_id" in
      '') continue ;;
      '#dropped') case "$_rq_kind" in ''|0|*[!0-9]*) : ;; *) bm_reason "the tracker reported $_rq_kind required field(s) of '$1' the kit cannot name (unverified)" ;; esac; continue ;;
      '#'*) continue ;;
    esac
    if [ "$1" != Epic ]; then
      case "$_rq_id" in parent|description) continue ;; esac
      if [ "$_rq_id" = "$_rq_sm" ] || [ "$_rq_id" = "$_rq_rm" ]; then continue; fi
    fi
    _rq_def=$(printf '%s\n' "$bm_cdefs" | awk -F'\t' -v k="create.$_rq_id" '$1 == k { print $2; exit }')
    if [ -n "$_rq_def" ] && [ "$_rq_def" != prompt ]; then continue; fi
    bm_reason "issue type '$1' requires '$(bm_disp "$_rq_name")' ($(bm_disp "$_rq_id")), which board create would not fill: add the line create.$(bm_disp "$_rq_id")=<value> to .kit/tracker.conf"
  done <<EOF_RQ
$_rq_out
EOF_RQ
}

bm_pf_states() {
  _ps_rc=0
  sh "$BM_JIRA_SH" status-ids "$bm_base" "$bm_flavour" "$bm_project" > "$bm_work/statuses" 2>/dev/null || _ps_rc=$?
  if [ "$_ps_rc" -ne 0 ]; then bm_reason "could not read the project's statuses (unverified)"; return 0; fi
  for _ps_tok in ready blocked backlog; do
    awk -F"$BM_US" -v s="$_ps_tok" '$4 == s { y = 1 } END { exit !y }' "$bm_work/cards" || continue
    _ps_name=$(bm_cget "state.$_ps_tok")
    if [ -z "$_ps_name" ]; then bm_reason "state.$_ps_tok is not mapped in .kit/tracker.conf, but the plan puts cards there"; continue; fi
  done
  : > "$bm_work/census.ids"
  sh "$BM_CONF_SH" get-prefix state. "$bm_conf_file" 2>/dev/null > "$bm_work/state.map" || true
  while IFS="$BM_TAB" read -r _ps_key _ps_val; do
    [ -n "$_ps_key" ] || continue
    _ps_id=$(awk -F'\t' -v n="$_ps_val" '$2 == n { print $1; exit }' "$bm_work/statuses")
    if [ -z "$_ps_id" ]; then bm_reason "$_ps_key='$(bm_disp "$_ps_val")' is not a status of project $bm_project (the census reads every mapped state)"; continue; fi
    bm_in "$bm_work/census.ids" "$_ps_id" || printf '%s\n' "$_ps_id" >> "$bm_work/census.ids"
  done < "$bm_work/state.map"
}

bm_pf_ledger() {
  [ -f "$bm_ledger_path" ] || return 0
  while IFS="$BM_TAB" read -r _pg_id _pg_key _pg_step; do
    [ -n "$_pg_id" ] || continue
    case "$_pg_id" in
      epic:*) bm_in "$bm_work/plan.epics" "${_pg_id#epic:}" || bm_reason "ledger: '$(bm_disp "$_pg_id")' is not an epic the plan declares" ;;
      *) if ! bm_in "$bm_work/plan.keep" "$_pg_id" && ! awk -F"$BM_US" -v id="$_pg_id" '$1 == id { y = 1 } END { exit !y }' "$bm_work/plan.new"; then
           bm_reason "ledger: '$(bm_disp "$_pg_id")' is not a row the plan creates"
         fi ;;
    esac
    printf '%s' "$_pg_key" | grep -Eq "^$bm_project-[0-9]+\$" || bm_reason "ledger: key '$(bm_disp "$_pg_key")' of '$(bm_disp "$_pg_id")' does not belong to project $bm_project"
    case "$_pg_step" in created|done) : ;; *) bm_reason "ledger: step '$(bm_disp "$_pg_step")' of '$(bm_disp "$_pg_id")' is not created or done" ;; esac
  done < "$bm_ledger_path"
}

bm_preflight() {
  if [ -z "${KIT_TRACKER_USER:-}" ] || [ -z "${KIT_TRACKER_TOKEN:-}" ]; then
    bm_reason "credentials: KIT_TRACKER_USER and KIT_TRACKER_TOKEN must be set in the environment (the adapter reads only the environment)"
    return 0
  fi
  if [ -z "$bm_base" ] || [ -z "$bm_project" ]; then bm_reason "base_url and project must be set in .kit/tracker.conf"; return 0; fi
  # the adapter's permissions probe answers over-privileged when the account holds ANY write permission on the project,
  # ok when it holds none; it cannot name which. A migration needs a writer.
  _pf_perm=$(sh "$BM_JIRA_SH" permissions "$bm_base" "$bm_flavour" "$bm_project" 2>/dev/null) || _pf_perm=unverified
  case "$_pf_perm" in
    over-privileged) : ;;
    ok) bm_reason "permission: this account holds no write permission (CREATE_ISSUES, TRANSITION_ISSUES) on project $bm_project" ;;
    *) bm_reason "permission: this account's permissions on project $bm_project could not be read (unverified)" ;;
  esac
  bm_cdefs=$(sh "$BM_CONF_SH" get-prefix create. "$bm_conf_file" 2>/dev/null) || bm_cdefs=""
  _pf_types=""
  [ ! -s "$bm_work/plan.epics" ] || _pf_types="Epic"
  for _pf_t in Task Bug; do
    awk -F"$BM_US" -v t="$_pf_t" '$6 == t { y = 1 } END { exit !y }' "$bm_work/cards" && _pf_types="$_pf_types $_pf_t"
  done
  for _pf_t in $_pf_types; do
    if bm_pf_meta "$_pf_t"; then
      [ "$_pf_t" = Epic ] || bm_pf_type_checks "$_pf_t"
      bm_pf_required "$_pf_t"
    fi
  done
  bm_pf_states
  bm_pf_ledger
  return 0
}

# ── the write loop ─────────────────────────────────────────────────────────────────────────────────
bm_epic_key() { # <epic name> -> its key
  while IFS="$BM_TAB" read -r _ek_n _ek_k; do
    if [ "$_ek_n" = "$1" ]; then printf '%s' "$_ek_k"; return 0; fi
  done < "$bm_work/epickeys"
}

# bm_create_card <ledger-id> <args to board create…>: create unless the ledger says it exists; sets bm_key and bm_step.
bm_create_card() {
  _cr_id=$1; shift
  _cr_cur=$(bm_ledger_get "$_cr_id")
  bm_key=""; bm_step=""
  if [ -n "$_cr_cur" ]; then bm_key=${_cr_cur%%"$BM_TAB"*}; bm_step=${_cr_cur#*"$BM_TAB"}; fi
  [ -z "$bm_step" ] || return 0
  # stdin is closed for the child: the loop that called us reads the cards file on its stdin, and a child must not eat it
  _cr_out=$(sh "$BM_BOARD_SH" create "$@" </dev/null) || {
    echo "board migrate: STOPPED at $(bm_disp "$_cr_id"): board create refused it (above). Nothing is retried; fix the cause and re-run to resume." >&2
    return 1
  }
  bm_key=$(printf '%s\n' "$_cr_out" | tail -n 1)
  if ! row_id_ok "$bm_key"; then echo "board migrate: STOPPED at $(bm_disp "$_cr_id"): board create printed no card key." >&2; return 1; fi
  bm_ledger_add "$_cr_id" "$bm_key" created
  bm_step=created
}

bm_write_epics() {
  while IFS= read -r _we_name; do
    [ -n "$_we_name" ] || continue
    bm_create_card "epic:$_we_name" --type Epic --title "$_we_name" || return 1
    [ "$bm_step" = "done" ] || { bm_ledger_add "epic:$_we_name" "$bm_key" "done"; echo "migrated epic '$_we_name' -> $bm_key"; }
    printf '%s\t%s\n' "$_we_name" "$bm_key" >> "$bm_work/epickeys"
  done < "$bm_work/plan.epics"
  return 0
}

bm_write_card() {
  bm_epic_k=$(bm_epic_key "$_wc_epic")
  set -- --type "$_wc_type" --title "$(cat "$bm_work/rows/$_wc_id/summary")" --parent "$bm_epic_k"
  [ -z "$_wc_sz" ] || set -- "$@" --size "$_wc_sz"
  [ -z "$_wc_rk" ] || set -- "$@" --risk "$_wc_rk"
  [ -z "$_wc_lab" ] || set -- "$@" --label "$_wc_lab"
  set -- "$@" --description "$(cat "$bm_work/rows/$_wc_id/desc")"
  bm_create_card "$_wc_id" "$@" || return 1
  [ "$bm_step" != "done" ] || return 0
  case "$_wc_state" in
    ready) _wc_name=$bm_st_ready ;;
    blocked) _wc_name=$bm_st_blocked ;;
    *) _wc_name="" ;;
  esac
  if [ -n "$_wc_name" ]; then
    if ! sh "$BM_JIRA_SH" transition "$bm_base" "$bm_flavour" "$bm_project" "$bm_key" "$_wc_name" </dev/null; then
      echo "board migrate: STOPPED at $_wc_id: the card exists as $bm_key but the transition to '$(bm_disp "$_wc_name")' was refused (above). Re-run to retry only the transition." >&2
      return 1
    fi
  fi
  bm_ledger_add "$_wc_id" "$bm_key" "done"
  echo "migrated $_wc_id -> $bm_key"
}

bm_write_all() {
  mkdir -p "$(dirname "$bm_ledger_path")" || return 1
  : > "$bm_work/epickeys"
  bm_st_ready=$(bm_cget state.ready); bm_st_blocked=$(bm_cget state.blocked)
  bm_write_epics || return 1
  while IFS=$BM_US read -r _wc_kind _wc_id _wc_epic _wc_state _wc_lab _wc_type _wc_sz _wc_rk; do
    [ -n "$_wc_id" ] || continue
    bm_write_card || return 1
  done < "$bm_work/cards"
  return 0
}

# bm_census: the project's cards across every mapped state must equal the ledger's finished epics and cards.
bm_census() {
  _ce_ids=$(tr '\n' ' ' < "$bm_work/census.ids")
  # shellcheck disable=SC2086  # the status ids are a space-separated list of numeric ids
  _ce_out=$(sh "$BM_JIRA_SH" list-in-states "$bm_base" "$bm_flavour" "$bm_project" "$bm_cap" $_ce_ids) || {
    echo "board migrate: the census could not read the project (above); the cards were written, check the project by hand." >&2
    return 1
  }
  _ce_n=$(printf '%s\n' "$_ce_out" | grep -c . || true)
  _ce_l=$(awk -F'\t' '$3 == "done" { d[$1] = 1 } END { n = 0; for (k in d) n++; print n }' "$bm_ledger_path")
  if [ "$_ce_n" != "$_ce_l" ]; then
    echo "board migrate: census MISMATCH - the project lists $_ce_n cards, the ledger holds $_ce_l. A duplicate card is how a crash between a create and its ledger line shows." >&2
    return 1
  fi
  echo "census OK ($_ce_n cards)"
}

# ── the freeze ─────────────────────────────────────────────────────────────────────────────────────
bm_pipe_esc() { printf '%s' "$1" | sed 's/|/\\|/g'; }

bm_freeze_check() {
  if [ ! -f "$bm_ledger_path" ]; then bm_reason "freeze: the ledger ($bm_ledger_disp) does not exist; run the migration first"; return 0; fi
  # every ledger key is written into the board file (the merge pointers), so each one must be a key of THIS project
  if [ -z "$bm_project" ]; then bm_reason "freeze: project must be set in .kit/tracker.conf"; return 0; fi
  while IFS="$BM_TAB" read -r _fc_lid _fc_lkey _fc_lstep; do
    [ -n "$_fc_lid" ] || continue
    printf '%s' "$_fc_lkey" | grep -Eq "^$bm_project-[0-9]+\$" || bm_reason "freeze: ledger key '$(bm_disp "$_fc_lkey")' of '$(bm_disp "$_fc_lid")' does not belong to project $bm_project"
  done < "$bm_ledger_path"
  while IFS= read -r _fc_name; do
    [ -n "$_fc_name" ] || continue
    _fc_cur=$(bm_ledger_get "epic:$_fc_name")
    [ "${_fc_cur#*"$BM_TAB"}" = "done" ] || bm_reason "freeze: epic '$(bm_disp "$_fc_name")' has no finished ledger line"
  done < "$bm_work/plan.epics"
  cat "$bm_work/plan.keep" > "$bm_work/freeze.ids"
  awk -F"$BM_US" '{ print $1 }' "$bm_work/plan.new" >> "$bm_work/freeze.ids"
  while IFS= read -r _fc_id; do
    [ -n "$_fc_id" ] || continue
    _fc_cur=$(bm_ledger_get "$_fc_id")
    [ "${_fc_cur#*"$BM_TAB"}" = "done" ] || bm_reason "freeze: '$_fc_id' has no finished ledger line"
  done < "$bm_work/freeze.ids"
  grep -q '^# ' "$bm_from" || bm_reason "freeze: the board has no H1 heading to put the banner under"
}

bm_freeze_run() {
  bm_freeze_check
  bm_flush || return 2
  case "$bm_be" in jira) _fr_name=Jira ;; linear) _fr_name=Linear ;; github) _fr_name=GitHub ;; gitlab) _fr_name=GitLab ;; ado) _fr_name="Azure DevOps" ;; *) _fr_name=$bm_be ;; esac
  : > "$bm_work/moved.ids"; : > "$bm_work/done.rows"
  while IFS=$BM_US read -r _fr_id _fr_fate _fr_epic _fr_why _fr_ln; do
    case "$_fr_fate" in
      keep) printf '%s\n' "$_fr_id" >> "$bm_work/moved.ids" ;;
      drop)
        printf '%s\n' "$_fr_id" >> "$bm_work/moved.ids"
        # shellcheck disable=SC2016  # literal backticks around the row ID
        printf '| `%s` — dropped at migration triage — %s | %s | — |\n' "$_fr_id" "$(bm_pipe_esc "$_fr_why")" "$bm_date" >> "$bm_work/done.rows" ;;
      merge:*)
        printf '%s\n' "$_fr_id" >> "$bm_work/moved.ids"
        _fr_t=${_fr_fate#merge:}; _fr_cur=$(bm_ledger_get "$_fr_t")
        # shellcheck disable=SC2016  # literal backticks around the row IDs
        printf '| `%s` — merged into `%s` (%s) | %s | — |\n' "$_fr_id" "$_fr_t" "${_fr_cur%%"$BM_TAB"*}" "$bm_date" >> "$bm_work/done.rows" ;;
    esac
  done < "$bm_work/plan.rows"
  {
    # shellcheck disable=SC2016  # literal backticks around the ledger path
    printf '> **This board is history.** The board is %s (project %s) since %s; archived rows below were not migrated and may be re-created as cards when needed. The row → card map is `%s`.\n' "$_fr_name" "$bm_project" "$bm_date" "$bm_ledger_disp"
    printf 'Moved to %s on %s; see the banner.\n' "$bm_project" "$bm_date"
  } > "$bm_work/freeze.lines"
  awk -v movedf="$bm_work/moved.ids" -v donef="$bm_work/done.rows" -v linesf="$bm_work/freeze.lines" '
    BEGIN {
      while ((getline l < movedf) > 0) mv[l] = 1
      nd = 0
      while ((getline l < donef) > 0) dn[++nd] = l
      getline banner < linesf
      getline moved < linesf
      sec = ""; pend = 0; inskip = 0; infence = 0; h1 = 0; doneins = 0
    }
    {
      if (pend) { pend = 0; if ($0 != "") print "" }
      line = $0
      if (line ~ /^[ \t]*```/) { infence = !infence; inskip = 0; print line; next }
      if (infence) { print line; next }
      if (!h1 && line ~ /^# /) { h1 = 1; print line; print ""; print banner; pend = 1; next }
      if (line ~ /^#/) {
        inskip = 0; sec = ""
        if (line ~ /^## Ready[ \t]*$/) sec = "Ready"
        else if (line ~ /^## Blocked[ \t]*$/) sec = "Blocked"
        else if (line ~ /^## Backlog \(unrefined\)[ \t]*$/) sec = "Backlog"
        else if (line ~ /^## Done[ \t]*$/) sec = "Done"
        print line
        if (sec == "Ready" || sec == "Blocked" || sec == "Backlog") { print ""; print moved; pend = 1 }
        next
      }
      if ((sec == "Ready" || sec == "Blocked") && line ~ /^[ \t]*\|/) {
        if (match(line, /^[ \t]*\|[^|`]*`[A-Z0-9][A-Z0-9-]*`/)) {
          id = substr(line, RSTART, RLENGTH); sub(/`$/, "", id); sub(/^.*`/, "", id)
          if (id in mv) next
        }
        print line; next
      }
      if (sec == "Done" && !doneins && line ~ /^[ \t]*\|[ \t:|-]*-[ \t:|-]*\|[ \t]*$/) {
        print line
        for (i = 1; i <= nd; i++) print dn[i]
        doneins = 1; next
      }
      if (sec == "Backlog") {
        if (line ~ /^> - \[ \] \*\*`[A-Z0-9][A-Z0-9-]*`\*\*/) {
          id = line; sub(/^> - \[ \] \*\*`/, "", id); sub(/`.*$/, "", id)
          if (id in mv) { inskip = 1; next }
          inskip = 0; print line; next
        }
        if (inskip && line ~ /^>/ && line !~ /^> - \[[ xX]\]/) next
        inskip = 0
      }
      print line
    }
  ' "$bm_from" > "$bm_work/frozen.md" || { echo "board migrate: the freeze could not rewrite the board." >&2; return 1; }
  cat "$bm_work/frozen.md" > "$bm_from" || { echo "board migrate: the frozen board could not be written back." >&2; return 1; }
  echo "frozen: $bm_from ($(wc -l < "$bm_work/moved.ids" | tr -d ' ') rows moved out, banner added)"
}

# ── the verb ───────────────────────────────────────────────────────────────────────────────────────
# Every step below checks its own result and returns it: a surprise abort halfway through a run would skip the ledger
# line of a card that exists, so errexit is off inside the verb.
bm_migrate() {
  set +e
  bm_work=$(mktemp -d "${TMPDIR:-/tmp}/bmig.XXXXXX") || { echo "board migrate: could not create a scratch directory." >&2; return 1; }
  bm_rc_inner=0
  bm_migrate_run "$@" || bm_rc_inner=$?
  rm -rf "$bm_work"
  return "$bm_rc_inner"
}

bm_migrate_run() {
  bm_from=""; bm_plan=""; bm_ledger_arg=""; bm_screen=""; bm_dry=0; bm_freeze=0; bm_date=""
  bm_cdefs=""; bm_be=""
  bm_args "$@" || return $?
  [ -f "$BM_LIB_SH" ] || { echo "board migrate: conformance/backlog-lib.sh is missing." >&2; return 1; }
  # shellcheck disable=SC1090
  . "$BM_LIB_SH"
  bm_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  bm_conf_file="$bm_root/.kit/tracker.conf"
  if [ -n "$bm_ledger_arg" ]; then bm_ledger_path=$bm_ledger_arg; bm_ledger_disp=$bm_ledger_arg
  else bm_ledger_path="$bm_root/.kit/board-migration.tsv"; bm_ledger_disp=".kit/board-migration.tsv"; fi
  bm_backend_gate || return $?
  [ -f "$bm_from" ] || { echo "board migrate: --from '$(bm_disp "$bm_from")' is not a file." >&2; return 2; }
  [ -f "$bm_plan" ] || { echo "board migrate: --plan '$(bm_disp "$bm_plan")' is not a file." >&2; return 2; }
  if [ "$bm_freeze" = 1 ] && grep -q '^> \*\*This board is history\.\*\*' "$bm_from"; then
    echo "board migrate: $bm_from is already frozen; nothing to do."
    return 0
  fi
  bm_base=$(bm_cget base_url); bm_flavour=$(bm_cget flavour); [ -n "$bm_flavour" ] || bm_flavour=cloud
  bm_project=$(bm_cget project); bm_cap=$(bm_cget list_cap)
  : > "$bm_work/reasons"
  bm_parse_board
  bm_parse_plan
  bm_check_plan
  bm_flush || return 2
  if [ "$bm_freeze" = 1 ]; then bm_freeze_run; return $?; fi
  bm_build_cards
  bm_check_cards
  bm_flush || return 2
  if [ "$bm_dry" = 1 ]; then bm_print_plan; return 0; fi
  bm_preflight
  bm_flush || return 2
  bm_write_all || return 1
  bm_census
}

# ── ORACLE MARKER: selftest() and everything below is the non-vacuity oracle region. ─────────────
selftest() {
  bm_fail=0
  bm_t=$(mktemp -d) || { echo "selftest FAIL: no scratch dir"; return 1; }
  HOME="$bm_t/home"; mkdir -p "$HOME"; export HOME
  fx=$BM_FIXTURES
  [ -d "$fx" ] || { echo "selftest FAIL: the fixtures are missing ($fx)"; rm -rf "$bm_t"; return 1; }
  bm_pass() { echo "selftest PASS: $1"; }
  bm_fail_() { echo "selftest FAIL: $1"; bm_fail=1; }

  bm_repo="$bm_t/repo"; bm_stub="$bm_t/stub"
  mkdir -p "$bm_repo/.kit" "$bm_stub"
  git init -q "$bm_repo" >/dev/null 2>&1 || true

  # ── the two stubs: board.sh (create) and tracker-jira.sh (reads + transition). They append to $D/log and answer from
  # files under $D; the path is baked in at generation, so nothing in the environment can steer them. ─────────────
  cat > "$bm_stub/board.sh.tmpl" <<'STUB_EOF'
#!/bin/sh
D=@@D@@
[ "$1" = create ] || exit 2
shift
n=$(cat "$D/counter" 2>/dev/null || echo 0)
n=$((n + 1))
line="board create"; desc=""
while [ $# -gt 0 ]; do
  case "$1" in
    --description) desc=$2; line="$line --description …" ;;
    *) line="$line $1 $2" ;;
  esac
  shift 2
done
printf '%s\n' "$line" >> "$D/log"
fail=$(cat "$D/fail-create-at" 2>/dev/null || true)
if [ -n "$fail" ] && [ "$n" = "$fail" ]; then echo "board create: stub refusal" >&2; exit 1; fi
echo "$n" > "$D/counter"
printf '%s' "$desc" > "$D/desc.$n"
printf 'board create: OK — created `ZB-%s`, proven by post-read.\nZB-%s\n' "$n" "$n"
STUB_EOF
  cat > "$bm_stub/tracker-jira.sh.tmpl" <<'STUB_EOF'
#!/bin/sh
D=@@D@@
printf 'tracker %s\n' "$*" >> "$D/log"
case "$1" in
  permissions) cat "$D/perm" ;;
  create-meta)
    [ -f "$D/cm/$5.txt" ] || { echo "refused: the issue type is not in this project's create-meta" >&2; exit 3; }
    printf '#type-id\t10003\n'; cat "$D/cm/$5.txt" ;;
  required-fields)
    printf '#type-id\t10003\n'
    if [ -f "$D/rf/$5.txt" ]; then cat "$D/rf/$5.txt"; fi ;;
  status-ids) cat "$D/status-ids.txt" ;;
  list-in-states)
    n=$(cat "$D/counter" 2>/dev/null || echo 0); x=$(cat "$D/census-extra" 2>/dev/null || echo 0)
    t=$((n + x)); i=1
    while [ "$i" -le "$t" ]; do echo "ZB-$i"; i=$((i + 1)); done ;;
  transition)
    if [ -f "$D/fail-transition" ]; then echo "refused: stub transition" >&2; exit 1; fi ;;
  *) exit 2 ;;
esac
exit 0
STUB_EOF
  sed "s|@@D@@|$bm_stub|g" "$bm_stub/board.sh.tmpl" > "$bm_stub/board.sh"
  sed "s|@@D@@|$bm_stub|g" "$bm_stub/tracker-jira.sh.tmpl" > "$bm_stub/tracker-jira.sh"
  BM_BOARD_SH="$bm_stub/board.sh"
  BM_JIRA_SH="$bm_stub/tracker-jira.sh"

  bm_conf() { # <list_cap>
    cat > "$bm_repo/.kit/tracker.conf" <<CONF_EOF
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=ZB
state.backlog=Backlog
state.ready=Ready
state.in-progress=In Progress
state.blocked=Blocked
state.done=Done
field.size=customfield_10046
field.risk=customfield_10047
list_cap=$1
CONF_EOF
  }
  bm_cm() { # <type> <size-allowed>
    printf '%s\tcustomfield_10046\toption\tSize\t%s\n%s\tcustomfield_10047\toption\tRisk\tLow|Med|High\n%s\tdescription\tstring\tDescription\t\n%s\tlabels\tarray\tLabels\t\n%s\tparent\tissuelink\tParent\t\n' "$1" "$2" "$1" "$1" "$1" "$1" > "$bm_stub/cm/$1.txt"
  }
  bm_reset() {
    rm -rf "$bm_stub/cm" "$bm_stub/rf" "$bm_stub"/desc.* "$bm_stub/fail-create-at" "$bm_stub/fail-transition" "$bm_stub/census-extra"
    mkdir -p "$bm_stub/cm" "$bm_stub/rf"
    : > "$bm_stub/log"; echo 0 > "$bm_stub/counter"
    bm_cm Task 'XS|S|M|L|XL'; bm_cm Bug 'XS|S|M|L|XL'
    printf 'Epic\tdescription\tstring\tDescription\t\nEpic\tlabels\tarray\tLabels\t\n' > "$bm_stub/cm/Epic.txt"
    echo over-privileged > "$bm_stub/perm"
    printf '10001\tBacklog\n10002\tReady\n10003\tIn Progress\n10004\tBlocked\n10005\tDone\n' > "$bm_stub/status-ids.txt"
    rm -f "$bm_repo/.kit/board-migration.tsv" "$bm_repo"/*.md "$bm_repo"/*.tsv "$bm_repo"/*.list
    cp "$fx"/*.md "$fx"/*.tsv "$fx"/*.list "$bm_repo/"
    printf 'Backlog backend: jira\n' > "$bm_repo/CLAUDE.md"
    bm_conf 200
    KIT_TRACKER_USER=fixture-user; KIT_TRACKER_TOKEN=fixture-token
  }
  bm_run() { # args…: the verb, in-process, in the fixture repo
    bm_out=$(cd "$bm_repo" && bm_migrate "$@" 2>"$bm_t/err"); bm_rc=$?
    bm_err=$(cat "$bm_t/err"); bm_all="$bm_out
$bm_err"
  }
  bm_writes() { grep -e '^board create' -e '^tracker transition' "$bm_stub/log" 2>/dev/null || true; }
  bm_nwrites() { bm_writes | wc -l | tr -d ' '; }
  bm_logbytes() { wc -c < "$bm_stub/log" | tr -d ' '; }
  bm_has() { printf '%s\n' "$bm_all" | grep -qF -e "$1"; }
  D=--date; DT=2026-10-08

  # ── leg 1: dry run — exact output, zero tracker calls of any kind, no credentials needed ──────────────────────────
  bm_reset; KIT_TRACKER_USER=; KIT_TRACKER_TOKEN=
  bm_run --from board.md --plan plan.tsv --dry-run $D $DT
  if [ "$bm_rc" -eq 0 ] && [ "$(printf '%s\n' "$bm_out")" = "$(cat "$fx/expected-dry-run.txt")" ] && [ "$(bm_logbytes)" = 0 ]; then
    bm_pass "leg 1 dry-run: the fixture prints exactly expected-dry-run.txt, makes zero tracker calls, needs no credentials"
  else bm_fail_ "leg 1 dry-run: rc=$bm_rc logbytes=$(bm_logbytes) out=[$bm_all]"; fi

  # ── leg 2: live run — the write calls equal expected-calls.txt (epics first, plan order, Bug/Task, parents, label, transitions only for ready/blocked, no assignee) ─
  bm_reset
  bm_run --from board.md --plan plan.tsv $D $DT
  if [ "$bm_rc" -eq 0 ] && [ "$(bm_writes)" = "$(cat "$fx/expected-calls.txt")" ] && ! grep -qi 'assign' "$bm_stub/log" && bm_has 'census OK'; then
    bm_pass "leg 2 live: the write calls equal expected-calls.txt (epics first, plan order, Bug for defect, parents, parked label, transitions for ready/blocked only, no assignee) and the census holds"
  else bm_fail_ "leg 2 live: rc=$bm_rc writes=$(bm_nwrites) out=[$bm_all]"; fi
  bm_first_write=$(grep -n -m1 -e '^board create' "$bm_stub/log" | cut -d: -f1)
  bm_last_read=$(grep -n -e '^tracker permissions' -e '^tracker create-meta' -e '^tracker status-ids' "$bm_stub/log" | tail -1 | cut -d: -f1)
  if [ -n "$bm_first_write" ] && [ -n "$bm_last_read" ] && [ "$bm_last_read" -lt "$bm_first_write" ] && grep -q '^tracker list-in-states' "$bm_stub/log"; then
    bm_pass "leg 2 order: the preflight reads (permissions, create-meta, status-ids) all precede the first write, and the census read follows"
  else bm_fail_ "leg 2 order: first-write=$bm_first_write last-preflight-read=$bm_last_read"; fi

  # ── leg 3: description — the four labelled sections, the unescaped pipe, the Absorbs line, blocked and bullet shapes ─
  bm_d_ok=1
  for bm_pair in 5:alpha 6:delta 8:foxtrot 9:hotel; do
    if [ "$(cat "$bm_stub/desc.${bm_pair%%:*}" 2>/dev/null)" != "$(cat "$fx/expected-desc-${bm_pair#*:}.txt")" ]; then bm_d_ok=0; bm_fail_ "leg 3 description: card ${bm_pair%%:*} differs from expected-desc-${bm_pair#*:}.txt: [$(cat "$bm_stub/desc.${bm_pair%%:*}" 2>/dev/null)]"; fi
  done
  [ "$bm_d_ok" = 1 ] && bm_pass "leg 3 description: ready, absorbing, blocked and bullet descriptions equal their expected four-section text"

  # ── leg 7: freeze — exact frozen board, no tracker call, a second freeze changes nothing ─────────────────────────
  bm_lines_before=$(wc -l < "$bm_stub/log" | tr -d ' ')
  bm_run --from board.md --plan plan.tsv --ledger .kit/board-migration.tsv --freeze $D $DT
  if [ "$bm_rc" -eq 0 ] && cmp -s "$bm_repo/board.md" "$fx/expected-frozen.md" && [ "$(wc -l < "$bm_stub/log" | tr -d ' ')" = "$bm_lines_before" ]; then
    bm_pass "leg 7 freeze: the fixture board, plan and finished ledger produce exactly expected-frozen.md, with no tracker call"
  else bm_fail_ "leg 7 freeze: rc=$bm_rc out=[$bm_all]"; fi
  bm_sum1=$(cksum < "$bm_repo/board.md")
  bm_run --from board.md --plan plan.tsv --ledger .kit/board-migration.tsv --freeze $D $DT
  if [ "$bm_rc" -eq 0 ] && [ "$(cksum < "$bm_repo/board.md")" = "$bm_sum1" ]; then
    bm_pass "leg 7 freeze-idempotent: a second --freeze changes nothing (the banner is detected)"
  else bm_fail_ "leg 7 freeze-idempotent: rc=$bm_rc out=[$bm_all]"; fi

  # ── leg 4: resume — done skipped, created gets only its transition, the rest is created ──────────────────────────
  bm_reset; echo 6 > "$bm_stub/counter"
  printf 'epic:Milestone Q\tZB-1\tcreated\nepic:Milestone Q\tZB-1\tdone\nepic:Parked\tZB-2\tdone\nepic:Later Work\tZB-3\tdone\nepic:Empty Epic\tZB-4\tdone\nQLN-ALPHA\tZB-5\tcreated\nQLN-ALPHA\tZB-5\tdone\nQLN-DELTA\tZB-6\tcreated\n' > "$bm_repo/.kit/board-migration.tsv"
  bm_run --from board.md --plan plan.tsv $D $DT
  if [ "$bm_rc" -eq 0 ] && [ "$(bm_writes)" = "$(cat "$fx/expected-resume-calls.txt")" ] && ! grep -q -e 'title QLN-ALPHA' -e 'title QLN-DELTA' -e 'title Milestone' "$bm_stub/log"; then
    bm_pass "leg 4 resume: a done row and a created row are not created again, the created row is only transitioned, the rest is created"
  else bm_fail_ "leg 4 resume: rc=$bm_rc out=[$bm_all] writes=[$(bm_writes)]"; fi
  # a create that fails stops the run at that row; the re-run finishes with no duplicate
  bm_reset; echo 9 > "$bm_stub/fail-create-at"
  bm_run --from board.md --plan plan.tsv $D $DT
  bm_rc1=$bm_rc; bm_o1=$bm_all
  rm -f "$bm_stub/fail-create-at"
  bm_run --from board.md --plan plan.tsv $D $DT
  if [ "$bm_rc1" -eq 1 ] && printf '%s' "$bm_o1" | grep -qF 'QLN-HOTEL' && [ "$bm_rc" -eq 0 ] && bm_has 'census OK' \
     && [ "$(grep -c 'title QLN-ALPHA' "$bm_stub/log")" = 1 ] && [ "$(grep -c 'title QLN-HOTEL' "$bm_stub/log")" = 2 ]; then
    bm_pass "leg 4 stop+resume: a refused create stops the run naming the row; the re-run finishes without a duplicate and the census holds"
  else bm_fail_ "leg 4 stop+resume: rc1=$bm_rc1 rc=$bm_rc o1=[$bm_o1] out=[$bm_all]"; fi
  # a transition that fails leaves the row created; the re-run only transitions it
  bm_reset; : > "$bm_stub/fail-transition"
  bm_run --from board.md --plan plan.tsv $D $DT
  bm_rc1=$bm_rc; bm_o1=$bm_all
  rm -f "$bm_stub/fail-transition"
  bm_run --from board.md --plan plan.tsv $D $DT
  if [ "$bm_rc1" -eq 1 ] && printf '%s' "$bm_o1" | grep -qF 'QLN-ALPHA' && [ "$bm_rc" -eq 0 ] && [ "$(grep -c 'title QLN-ALPHA' "$bm_stub/log")" = 1 ] \
     && [ "$(grep -c 'transition .* ZB-5 Ready' "$bm_stub/log")" = 2 ]; then
    bm_pass "leg 4 stop+transition: a refused transition stops the run naming the row; the re-run only retries the transition"
  else bm_fail_ "leg 4 stop+transition: rc1=$bm_rc1 rc=$bm_rc o1=[$bm_o1] out=[$bm_all]"; fi

  # ── leg 5: refusals — every reason at once, zero writes ──────────────────────────────────────────────────────────
  bm_reset
  bm_run --from board.md --plan bad-missing.tsv $D $DT
  if [ "$bm_rc" -eq 2 ] && bm_has 'QLN-GOLF' && [ "$(bm_logbytes)" = 0 ] && [ "$(bm_nwrites)" = 0 ]; then bm_pass "leg 5 missing: a moved row absent from the plan refuses (rc 2), naming it, with zero tracker calls"
  else bm_fail_ "leg 5 missing: rc=$bm_rc log=$(bm_logbytes) out=[$bm_all]"; fi
  bm_run --from board.md --plan bad-dup.tsv $D $DT
  if [ "$bm_rc" -eq 2 ] && bm_has 'QLN-ALPHA' && bm_has 'more than once' && [ "$(bm_logbytes)" = 0 ] && [ "$(bm_nwrites)" = 0 ]; then bm_pass "leg 5 duplicate: a duplicate plan ID refuses, with zero tracker calls"
  else bm_fail_ "leg 5 duplicate: rc=$bm_rc out=[$bm_all]"; fi
  bm_run --from board.md --plan bad-epic.tsv $D $DT
  if [ "$bm_rc" -eq 2 ] && bm_has 'Nowhere' && [ "$(bm_logbytes)" = 0 ]; then bm_pass "leg 5 epic: an undeclared epic refuses before any call"
  else bm_fail_ "leg 5 epic: rc=$bm_rc out=[$bm_all]"; fi
  bm_run --from board.md --plan bad-merge-drop.tsv $D $DT
  if [ "$bm_rc" -eq 2 ] && bm_has 'merge target' && [ "$(bm_logbytes)" = 0 ]; then bm_pass "leg 5 merge: a merge into a drop row refuses before any call"
  else bm_fail_ "leg 5 merge: rc=$bm_rc out=[$bm_all]"; fi
  bm_run --from board-inprogress.md --plan plan-inprogress.tsv $D $DT
  if [ "$bm_rc" -eq 2 ] && bm_has 'QLN-MIKE' && bm_has 'QLN-NOVEMBER' && [ "$(bm_logbytes)" = 0 ]; then bm_pass "leg 5 in-flight: In Progress and In Review rows not marked stay refuse, both named"
  else bm_fail_ "leg 5 in-flight: rc=$bm_rc out=[$bm_all]"; fi
  echo ok > "$bm_stub/perm"
  bm_run --from board.md --plan plan.tsv $D $DT
  if [ "$bm_rc" -eq 2 ] && [ "$(bm_nwrites)" = 0 ] && bm_has 'permission'; then bm_pass "leg 5 permission: a token without write permission refuses in the preflight with zero writes"
  else bm_fail_ "leg 5 permission: rc=$bm_rc writes=$(bm_nwrites) out=[$bm_all]"; fi
  echo over-privileged > "$bm_stub/perm"; : > "$bm_stub/log"
  bm_cm Task 'XS|S|M'
  bm_run --from board.md --plan plan.tsv $D $DT
  if [ "$bm_rc" -eq 2 ] && [ "$(bm_nwrites)" = 0 ] && bm_has "Size 'L'"; then bm_pass "leg 5 size: a Size value outside the field's allowed set refuses in the preflight with zero writes"
  else bm_fail_ "leg 5 size: rc=$bm_rc writes=$(bm_nwrites) out=[$bm_all]"; fi
  bm_cm Task 'XS|S|M|L|XL'; : > "$bm_stub/log"; bm_conf 3
  bm_run --from board.md --plan plan.tsv $D $DT
  if [ "$bm_rc" -eq 2 ] && [ "$(bm_logbytes)" = 0 ] && bm_has 'list_cap'; then bm_pass "leg 5 list_cap: more cards than list_cap refuses before any call"
  else bm_fail_ "leg 5 list_cap: rc=$bm_rc out=[$bm_all]"; fi
  bm_conf 200; KIT_TRACKER_USER=; KIT_TRACKER_TOKEN=
  bm_run --from board.md --plan plan.tsv $D $DT
  if [ "$bm_rc" -eq 2 ] && [ "$(bm_logbytes)" = 0 ] && bm_has 'KIT_TRACKER_USER'; then bm_pass "leg 5 credentials: a live run without credentials refuses before any tracker call"
  else bm_fail_ "leg 5 credentials: rc=$bm_rc out=[$bm_all]"; fi
  KIT_TRACKER_USER=fixture-user; KIT_TRACKER_TOKEN=fixture-token
  bm_run --from board.md --plan bad-multi.tsv --dry-run $D $DT
  if [ "$bm_rc" -eq 2 ] && [ "$(bm_logbytes)" = 0 ] && bm_has 'QLN-GOLF' && bm_has 'Nowhere' && bm_has 'QLN-GHOST' && bm_has 'more than once' && bm_has 'needs a reason' && bm_has 'unknown line kind'; then
    bm_pass "leg 5 all-at-once: a plan with six faults reports every reason in one run"
  else bm_fail_ "leg 5 all-at-once: rc=$bm_rc out=[$bm_all]"; fi
  bm_run --from board.md --plan bad-new.tsv --dry-run $D $DT
  if [ "$bm_rc" -eq 2 ] && bm_has 'QLN-ALPHA' && bm_has 'QLN-NEWTWO' && bm_has 'HUGE' && bm_has 'extreme' && bm_has 'bad id' && bm_has 'QLN-NEWFOUR'; then
    bm_pass "leg 5 new: a colliding or duplicate new ID, a bad Size or Risk, a bad ID and an empty intent each refuse"
  else bm_fail_ "leg 5 new: rc=$bm_rc out=[$bm_all]"; fi

  # ── leg 6: census — a project listing one card more than the ledger exits 1 with both numbers ────────────────────
  bm_reset; echo 1 > "$bm_stub/census-extra"
  bm_run --from board.md --plan plan.tsv $D $DT
  if [ "$bm_rc" -eq 1 ] && bm_has 'lists 15 cards, the ledger holds 14' && bm_has 'MISMATCH'; then bm_pass "leg 6 census: a project listing 15 cards against a ledger of 14 exits 1 naming both"
  else bm_fail_ "leg 6 census: rc=$bm_rc out=[$bm_all]"; fi

  # ── leg 6b: new cards and --screen ───────────────────────────────────────────────────────────────────────────────
  bm_reset
  bm_run --from screen-board.md --plan screen-plan.tsv --screen screen.list $D $DT
  if [ "$bm_rc" -eq 2 ] && bm_has 'QLN-PAPA' && bm_has 'QLN-ROMEO' && [ "$(bm_logbytes)" = 0 ] \
     && ! printf '%s' "$bm_all" | grep -qi -e 'acmely' -e 'zbx'; then
    bm_pass "leg 6b screen: a keep row naming an entry and a new intent holding a word: entry refuse, naming only the row IDs, zero calls, neither entry printed"
  else bm_fail_ "leg 6b screen: rc=$bm_rc log=$(bm_logbytes) out=[$bm_all]"; fi
  bm_run --from screen-board.md --plan screen-plan.tsv --screen screen.list --dry-run $D $DT
  if [ "$bm_rc" -eq 2 ] && bm_has 'QLN-PAPA' && [ "$(bm_logbytes)" = 0 ]; then bm_pass "leg 6b screen-dry: the screen also refuses a dry run"
  else bm_fail_ "leg 6b screen-dry: rc=$bm_rc out=[$bm_all]"; fi
  bm_run --from screen-board.md --plan screen-plan-ok.tsv --screen screen.list --dry-run $D $DT
  if [ "$bm_rc" -eq 0 ] && bm_has 'QLN-ROMEO'; then bm_pass "leg 6b screen-word: ZBXQ is not the whole word ZBX, and a dropped row is never a card, so the screen passes"
  else bm_fail_ "leg 6b screen-word: rc=$bm_rc out=[$bm_all]"; fi

  # ── leg 6c: --screen fails closed, and speaks the publish gate's grammar ──────────────────────────────────────────
  bm_reset
  printf '# only a comment\n\n   \n' > "$bm_repo/screen-empty.list"
  bm_run --from screen-board.md --plan screen-plan-ok.tsv --screen screen-empty.list $D $DT
  if [ "$bm_rc" -eq 2 ] && bm_has 'holds no entries' && [ "$(bm_logbytes)" = 0 ] && [ "$(bm_nwrites)" = 0 ]; then
    bm_pass "leg 6c screen-empty: a comments-only identifier list refuses (rc 2) instead of skipping the screen, with zero tracker calls"
  else bm_fail_ "leg 6c screen-empty: rc=$bm_rc log=$(bm_logbytes) out=[$bm_all]"; fi
  cp "$bm_repo/screen.list" "$bm_repo/screen-unreadable.list"; chmod 000 "$bm_repo/screen-unreadable.list"
  if [ "$(id -u)" = 0 ] || [ -r "$bm_repo/screen-unreadable.list" ]; then
    echo "selftest SKIP: leg 6c screen-unreadable (running as root, or the file is readable despite mode 000)"
  else
    bm_run --from screen-board.md --plan screen-plan-ok.tsv --screen screen-unreadable.list $D $DT
    if [ "$bm_rc" -eq 2 ] && bm_has 'cannot be read' && [ "$(bm_logbytes)" = 0 ] && [ "$(bm_nwrites)" = 0 ]; then
      bm_pass "leg 6c screen-unreadable: an unreadable identifier list refuses (rc 2) instead of skipping the screen, with zero tracker calls"
    else bm_fail_ "leg 6c screen-unreadable: rc=$bm_rc log=$(bm_logbytes) out=[$bm_all]"; fi
  fi
  chmod 600 "$bm_repo/screen-unreadable.list"
  printf 'ACME\rLY\n' > "$bm_repo/screen-cr.list"
  bm_run --from screen-board.md --plan screen-plan-ok.tsv --screen screen-cr.list --dry-run $D $DT
  if [ "$bm_rc" -eq 2 ] && bm_has 'carriage return' && [ "$(bm_logbytes)" = 0 ]; then
    bm_pass "leg 6c screen-cr: a carriage return inside an entry refuses (the publish gate's rule)"
  else bm_fail_ "leg 6c screen-cr: rc=$bm_rc out=[$bm_all]"; fi
  printf 'word: ZBX\n' > "$bm_repo/screen-wordsp.list"
  bm_run --from screen-board.md --plan screen-plan-ok.tsv --screen screen-wordsp.list --dry-run $D $DT
  if [ "$bm_rc" -eq 2 ] && bm_has 'whitespace after the colon' && [ "$(bm_logbytes)" = 0 ]; then
    bm_pass "leg 6c screen-word-space: whitespace after word: refuses (the publish gate's rule)"
  else bm_fail_ "leg 6c screen-word-space: rc=$bm_rc out=[$bm_all]"; fi

  # ── leg 6d: --freeze refuses a ledger key that is not a key of this project; the board is untouched ────────────────
  bm_reset
  bm_run --from board.md --plan plan.tsv $D $DT
  printf 'QLN-ALPHA\tX | evil |\tdone\n' >> "$bm_repo/.kit/board-migration.tsv"
  bm_sum1=$(cksum < "$bm_repo/board.md")
  bm_run --from board.md --plan plan.tsv --ledger .kit/board-migration.tsv --freeze $D $DT
  if [ "$bm_rc" -eq 2 ] && bm_has 'does not belong to project ZB' && [ "$(cksum < "$bm_repo/board.md")" = "$bm_sum1" ]; then
    bm_pass "leg 6d freeze-key: a crafted ledger key refuses the freeze (rc 2) and the board file is unchanged"
  else bm_fail_ "leg 6d freeze-key: rc=$bm_rc out=[$bm_all]"; fi

  # ── leg 6.1: a long Item is cut at the last space before 240 characters; the full text opens the Intent ─────────
  bm_reset
  bm_long=$(awk 'BEGIN { for (i = 1; i <= 60; i++) printf "word%02d ", i }' | sed 's/ $//')
  # shellcheck disable=SC2016  # literal backticks around the row ID
  printf '# Long\n\n## Ready\n\n| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links | Success metric / hypothesis |\n|------|---|---|---|---|---|---|---|---|\n| `QLN-LONG` — %s | long intent | ac | S | low | feature | — | — | — |\n' "$bm_long" > "$bm_repo/long-board.md"
  printf 'epic\tMilestone Q\nrow\tQLN-LONG\tkeep\tMilestone Q\n' > "$bm_repo/long-plan.tsv"
  bm_run --from long-board.md --plan long-plan.tsv --dry-run $D $DT
  bm_sum=$(printf '%s\n' "$bm_out" | awk -F'\t' '$1 == "card" { print $2 }')
  bm_run --from long-board.md --plan long-plan.tsv $D $DT
  if [ "${#bm_sum}" -le 255 ] && [ "${#bm_sum}" -gt 100 ] && [ "${bm_sum#*…}" = "" ] && [ "$(sed -n 2p "$bm_stub/desc.2")" = "QLN-LONG — $bm_long" ]; then
    bm_pass "leg 6.1 long-summary: a summary past 240 characters is cut at a space with an ellipsis (within Jira's 255), and the full Item opens the Intent"
  else bm_fail_ "leg 6.1 long-summary: len=${#bm_sum} sum=[$bm_sum] intent-line=[$(sed -n 2p "$bm_stub/desc.2" 2>/dev/null)] out=[$bm_all]"; fi

  # ── leg 8: backend — on md the verb refuses before it reads the plan ─────────────────────────────────────────────
  bm_reset; rm -f "$bm_repo/.kit/tracker.conf"; printf 'Backlog backend: BACKLOG.md (repo-native)\n' > "$bm_repo/CLAUDE.md"
  bm_run --from absent-board.md --plan absent-plan.tsv $D $DT
  if [ "$bm_rc" -eq 2 ] && bm_has 'declare the tracker first' && ! bm_has 'absent-plan' && [ "$(bm_logbytes)" = 0 ]; then
    bm_pass "leg 8 backend: on an md backend the verb refuses before reading the plan, with zero calls"
  else bm_fail_ "leg 8 backend: rc=$bm_rc out=[$bm_all]"; fi

  # ── usage ────────────────────────────────────────────────────────────────────────────────────────────────────────
  bm_reset
  bm_run
  bm_rc1=$bm_rc
  bm_run --from board.md --plan plan.tsv --bogus
  bm_rc2=$bm_rc
  bm_run --from board.md --plan plan.tsv --freeze
  if [ "$bm_rc1" -eq 2 ] && [ "$bm_rc2" -eq 2 ] && [ "$bm_rc" -eq 2 ] && bm_has '--date'; then bm_pass "leg usage: no arguments, an unknown option, and --freeze without --date each refuse (rc 2)"
  else bm_fail_ "leg usage: rc=$bm_rc1/$bm_rc2/$bm_rc out=[$bm_all]"; fi

  # ── the writer paths are plain variables: no default-from-environment expansion anywhere in this file ─────────────
  if grep -n -E '\$\{BM_(BOARD|JIRA|CONF|LIB)_SH[:=-]' "$here/board-migrate.sh" | grep -q .; then
    bm_fail_ "leg env-seam: a BM_*_SH variable is expanded with a default or read from the environment"
  else bm_pass "leg env-seam: no BM_*_SH variable is ever read from the environment (plain assignments only)"; fi

  rm -rf "$bm_t" 2>/dev/null || true
  if [ "$bm_fail" -ne 0 ]; then echo "board-migrate --selftest: FAIL" >&2; return 1; fi
  echo "board-migrate --selftest: OK"
  return 0
}

case "${1:-}" in
  --selftest) if selftest; then bm_rc_main=0; else bm_rc_main=$?; fi ;;
  -h|--help) bm_usage; bm_rc_main=2 ;;
  *) bm_work=""   # never inherited from the environment: the trap below removes this directory
     trap '[ -z "${bm_work:-}" ] || rm -rf "$bm_work"; exit 130' INT TERM
     if bm_migrate "$@"; then bm_rc_main=0; else bm_rc_main=$?; fi ;;
esac
exit "$bm_rc_main"
