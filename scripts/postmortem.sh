#!/bin/sh
# postmortem.sh — postmortem stub generator + action-item backlog parser.
#
# Two modes:
#   new        — scaffold a postmortem stub from incident metadata
#   to-backlog — parse the action-items table and emit backlog-row stubs to stdout
#
# Usage:
#   sh scripts/postmortem.sh new --id <ID> --severity <P0|P1|P2|P3> --title <title> \
#       [--commander <name>] [--date <YYYY-MM-DD>] [--out <dir>]
#   sh scripts/postmortem.sh to-backlog <postmortem.md>
#   sh scripts/postmortem.sh --selftest
#
# Notes:
#   new:        reads templates/POSTMORTEM-TEMPLATE.md, substitutes header placeholders,
#               writes to <out>/<ID>.md (default out: postmortems/). No-clobber.
#   to-backlog: parses "## 7. Action items" table; skips header, separator, blank, and
#               placeholder rows ([action] etc.). Emits Ready-row stubs to stdout.
# POSIX sh; dash-clean.
set -eu
cd "$(dirname "$0")/.."

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
usage() {
  cat >&2 <<'EOF'
usage:
  sh scripts/postmortem.sh new --id <ID> --severity <P0|P1|P2|P3> --title <title> \
      [--commander <name>] [--date <YYYY-MM-DD>] [--out <dir>]
  sh scripts/postmortem.sh to-backlog <postmortem.md>
  sh scripts/postmortem.sh --selftest
EOF
  exit 2
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# mode: new
# ---------------------------------------------------------------------------
cmd_new() {
  # parse args
  _id=""
  _severity=""
  _title=""
  _commander="[name / role]"
  _date="$(date -u +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)"
  _out="postmortems"

  while [ $# -gt 0 ]; do
    case "$1" in
      --id|--severity|--title|--commander|--date|--out)
        # Guard: a value-taking flag must be followed by a value
        if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
          printf 'error: %s requires a value\n' "$1" >&2; usage
        fi
        case "$1" in
          --id)        _id="$2"        ;;
          --severity)  _severity="$2"  ;;
          --title)     _title="$2"     ;;
          --commander) _commander="$2" ;;
          --date)      _date="$2"      ;;
          --out)       _out="$2"       ;;
        esac
        shift 2
        ;;
      *) printf 'error: unknown option: %s\n' "$1" >&2; usage ;;
    esac
  done

  # validate required
  if [ -z "$_id" ] || [ -z "$_title" ]; then
    printf 'error: --id and --title are required\n' >&2; usage
  fi
  case "$_severity" in
    P0|P1|P2|P3) ;;
    *) printf 'error: --severity must be one of P0 P1 P2 P3 (got: %s)\n' "$_severity" >&2; usage ;;
  esac

  _template="templates/POSTMORTEM-TEMPLATE.md"
  [ -f "$_template" ] || die "template not found: $_template"

  _dest="${_out}/${_id}.md"
  [ -f "$_dest" ] && die "target already exists (no-clobber): $_dest"

  mkdir -p "$_out"

  # FIX 2: values are passed via ENVIRON[] (export then read ENVIRON["key"] in awk BEGIN)
  # rather than via awk -v flags. awk -v interpreted C-style escape sequences before the
  # program ran: a literal backslash in --title was dropped, and \t/\n became tab/newline,
  # which could split the single-line header row. ENVIRON[] values are plain data —
  # no escape interpretation at any stage.
  #
  # Substitution uses replace_all() (index + substr concatenation) instead of gsub().
  # gsub() treats & and \ specially in the replacement string; replace_all() treats the
  # replacement as opaque data and concatenates it directly, so & / \ / / all pass
  # through to the output unchanged without any per-character escaping.
  export pm_title="$_title"
  export pm_id="$_id"
  export pm_severity="$_severity"
  export pm_commander="$_commander"
  export pm_dateval="$_date"

  awk \
    'BEGIN {
       title     = ENVIRON["pm_title"]
       id        = ENVIRON["pm_id"]
       severity  = ENVIRON["pm_severity"]
       commander = ENVIRON["pm_commander"]
       dateval   = ENVIRON["pm_dateval"]
     }
     function replace_all(str, pat, rep,    result, pos, patlen) {
       result = ""
       patlen = length(pat)
       while ((pos = index(str, pat)) > 0) {
         result = result substr(str, 1, pos - 1) rep
         str = substr(str, pos + patlen)
       }
       return result str
     }
     {
       $0 = replace_all($0, "[Incident Title]", title)
       $0 = replace_all($0, "[id]", id)
       $0 = replace_all($0, "[P0 / P1 / P2 / P3]", severity)
       $0 = replace_all($0, "[name / role]", commander)
       $0 = replace_all($0, "[date]", dateval)
       $0 = replace_all($0, "[open / closed]", "open")
       print
     }' \
    "$_template" > "$_dest"

  printf 'created: %s\n' "$_dest"
}

# ---------------------------------------------------------------------------
# mode: to-backlog
# ---------------------------------------------------------------------------
cmd_to_backlog() {
  _pmfile="${1:-}"
  [ -z "$_pmfile" ] && { printf 'error: to-backlog requires a postmortem file path\n' >&2; usage; }
  [ -f "$_pmfile" ] || die "file not found: $_pmfile"

  # Derive incident ID from the basename (strip .md extension)
  _id="$(basename "$_pmfile" .md)"

  # FIX 1: _id and _pmfile are passed into awk via ENVIRON[] (export then read
  # ENVIRON["pm_id"] / ENVIRON["pm_file"] in awk BEGIN). Previously they were
  # interpolated into a sed command that used | as its delimiter:
  #   sed -e "s|INCIDENT_ID|${_id}|g" -e "s|PMFILE|${_pmfile}|g"
  # A | in _pmfile produced "sed: bad flag in substitute command" (hard crash);
  # an & in _pmfile was expanded by sed as "matched text" (silent corruption).
  # ENVIRON[] values are plain data — no escape interpretation, no delimiter clash.
  # The awk emits the row by string concatenation, so no special character in
  # _id or _pmfile can affect program text.
  export pm_id="$_id"
  export pm_file="$_pmfile"

  # Use awk to:
  #   1. Detect "## 7. Action items" → start collecting
  #   2. Stop at the next "## " heading
  #   3. Skip header row (contains "Action" and "Owner"), separator (|---), blank lines,
  #      and placeholder rows (first cell trimmed matches ^\[.*\]$)
  #   4. Emit one backlog Ready row per real action
  _rows="$(awk '
    BEGIN {
      in_section  = 0
      incident_id = ENVIRON["pm_id"]
      pmfile      = ENVIRON["pm_file"]
    }

    # Enter the action-items section
    /^## 7[.] Action items/ { in_section = 1; next }

    # Leave the section when we hit the next ## heading
    in_section && /^## / { in_section = 0; next }

    !in_section { next }

    # Skip blank lines
    /^[[:space:]]*$/ { next }

    # Only process lines starting with |
    !/^\|/ { next }

    {
      # Split on |; field [2] = Action, [3] = Owner, [6] = Type
      # (fields: "" | Action | Owner | Due | Backlog link | Type | "")
      # KNOWN LIMITATION: a literal | inside an action cell will be treated as a
      # column separator and truncate the action text. This is accepted; workaround
      # is to avoid | in action cell text (use "or", "and", or a similar alternative).
      n = split($0, f, "|")

      action = f[2]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", action)
      owner  = f[3]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", owner)
      type   = f[6]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", type)
      if (n < 6) { type = "prevent" }

      # Skip header row
      if (action == "Action" && owner == "Owner") { next }

      # Skip separator row (contains ---)
      if (action ~ /^-/) { next }

      # Skip placeholder row: action cell is a bracketed placeholder [...]
      if (action ~ /^\[.*\]$/) { next }

      # Skip blank action cells
      if (action == "") { next }

      # Emit backlog Ready row — incident_id and pmfile come from ENVIRON[] and
      # are concatenated by awk as plain string data, never interpreted as sed/awk
      # program text. No special character in either value can crash or corrupt.
      print "| " action " | incident " incident_id " follow-up — " type " | " action " completed | S | [set] | tech-debt | " owner " | " pmfile " |"
    }
  ' "$_pmfile")"

  if [ -z "$_rows" ]; then
    printf 'no action items found in %s\n' "$_pmfile"
    return 0
  fi

  # Emit stubs with header comment
  echo "# Backlog stubs (review before pasting into BACKLOG.md or creating in your tracker)"
  echo "| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links |"
  echo "|------|--------------|---------------------|------|------|------|-------|-------|"
  printf '%s\n' "$_rows"
}

# ---------------------------------------------------------------------------
# selftest
# ---------------------------------------------------------------------------
selftest() {
  _fail=0
  _tmpdir="$(mktemp -d)"
  trap 'rm -rf "$_tmpdir"' EXIT

  # --- fixture: postmortem with 2 real rows + 1 placeholder + 1 empty-action ---
  _pm_fixture="${_tmpdir}/INC-001.md"
  cat > "$_pm_fixture" <<'PMEOF'
# Test Incident — Postmortem

**Incident ID:** INC-001 · **Severity:** P1 · **Date:** 2026-01-01 · **Incident commander:** alice · **Status:** open

## 7. Action items

| Action | Owner | Due | Backlog link | Type |
|--------|-------|-----|--------------|------|
| [action] | [owner] | [date] | [#id] | [prevent / detect-faster / mitigate-faster] |
| Add rate-limit to login endpoint | alice | 2026-01-15 | #42 | prevent |
| Set up alert for error-rate spike | bob | 2026-01-20 | #43 | detect-faster |

## 8. Blameless statement

This postmortem examines systems and processes, not people.
PMEOF

  # --- fixture: postmortem with no real action rows ---
  _pm_empty="${_tmpdir}/INC-002.md"
  cat > "$_pm_empty" <<'PMEOF2'
# Empty — Postmortem

## 7. Action items

| Action | Owner | Due | Backlog link | Type |
|--------|-------|-----|--------------|------|
| [action] | [owner] | [date] | [#id] | [prevent / detect-faster / mitigate-faster] |
PMEOF2

  # ---- T1: to-backlog with 2 real rows ----------------------------------------
  _out="$(sh "$0" to-backlog "$_pm_fixture" 2>&1)"

  printf '%s\n' "$_out" | grep -q "Add rate-limit to login endpoint" || {
    echo "postmortem --selftest: FAIL (T1: real action row 1 missing)" >&2; _fail=1
  }
  printf '%s\n' "$_out" | grep -q "Set up alert for error-rate spike" || {
    echo "postmortem --selftest: FAIL (T1: real action row 2 missing)" >&2; _fail=1
  }
  printf '%s\n' "$_out" | grep -q "INC-001" || {
    echo "postmortem --selftest: FAIL (T1: incident ID not in output)" >&2; _fail=1
  }
  printf '%s\n' "$_out" | grep -q '\[action\]' && {
    echo "postmortem --selftest: FAIL (T1: placeholder row was emitted)" >&2; _fail=1
  }
  # Exactly 2 data rows (lines starting with | that contain "completed")
  _row_count="$(printf '%s\n' "$_out" | grep -c '| tech-debt |' || true)"
  [ "$_row_count" = "2" ] || {
    echo "postmortem --selftest: FAIL (T1: expected 2 backlog rows, got $_row_count)" >&2; _fail=1
  }

  # ---- T2: new mode — stub is created with correct tokens ---------------------
  _outdir="${_tmpdir}/postmortems"
  sh "$0" new --id INC-001 --severity P1 --title "Test Incident" \
      --commander alice --date 2026-01-01 --out "$_outdir" >/dev/null 2>&1 || {
    echo "postmortem --selftest: FAIL (T2: new command exited non-zero)" >&2; _fail=1
  }
  _stub="${_outdir}/INC-001.md"
  [ -f "$_stub" ] || {
    echo "postmortem --selftest: FAIL (T2: stub file not created)" >&2; _fail=1
  }
  grep -q "INC-001" "$_stub" || {
    echo "postmortem --selftest: FAIL (T2: ID not in stub)" >&2; _fail=1
  }
  grep -q "Test Incident" "$_stub" || {
    echo "postmortem --selftest: FAIL (T2: title not in stub)" >&2; _fail=1
  }

  # ---- T3: no-clobber — second new to same target must fail -------------------
  _clobber_rc=0
  sh "$0" new --id INC-001 --severity P1 --title "Test Incident" \
      --out "$_outdir" >/dev/null 2>&1 || _clobber_rc=$?
  [ "$_clobber_rc" != "0" ] || {
    echo "postmortem --selftest: FAIL (T3: no-clobber did not reject duplicate)" >&2; _fail=1
  }

  # ---- T4: empty action table → "no action items found" notice ----------------
  _empty_out="$(sh "$0" to-backlog "$_pm_empty" 2>&1)"
  printf '%s\n' "$_empty_out" | grep -q "no action items found" || {
    echo "postmortem --selftest: FAIL (T4: expected 'no action items found' notice)" >&2; _fail=1
  }

  # ---- T5: missing file → exit 1 (error, not usage exit 2) -------------------
  _missing_rc=0
  sh "$0" to-backlog /nonexistent/path.md >/dev/null 2>&1 || _missing_rc=$?
  [ "$_missing_rc" != "0" ] || {
    echo "postmortem --selftest: FAIL (T5: missing file did not exit non-zero)" >&2; _fail=1
  }

  # ---- T6: & in title is preserved literally in the stub (existing pin) -------
  _outdir_amp="${_tmpdir}/postmortems-amp"
  sh "$0" new --id INC-AMP --severity P1 --title "A & B" \
      --commander "alice / SRE" --date 2026-01-01 --out "$_outdir_amp" >/dev/null 2>&1 || {
    echo "postmortem --selftest: FAIL (T6: new with & in title exited non-zero)" >&2; _fail=1
  }
  _stub_amp="${_outdir_amp}/INC-AMP.md"
  grep -q 'A & B' "$_stub_amp" 2>/dev/null || {
    echo "postmortem --selftest: FAIL (T6: literal 'A & B' not found in stub)" >&2; _fail=1
  }
  grep -q '\[Incident Title\]' "$_stub_amp" 2>/dev/null && {
    echo "postmortem --selftest: FAIL (T6: placeholder [Incident Title] still present in stub)" >&2; _fail=1
  }
  # / in commander should also survive intact
  grep -q 'alice / SRE' "$_stub_amp" 2>/dev/null || {
    echo "postmortem --selftest: FAIL (T6: 'alice / SRE' not found in stub)" >&2; _fail=1
  }

  # ---- T7 (NEW — Fix 1 pin): to-backlog with | and & in the FILE PATH --------
  # Verify that a postmortem file whose path contains | and & does not crash sed
  # and that the Links column in the emitted row contains the path intact.
  _special_dir="${_tmpdir}/inc|dir&test"
  mkdir -p "$_special_dir"
  _pm_special="${_special_dir}/INC-SPECIAL.md"
  cat > "$_pm_special" <<'PMEOF3'
# Special — Postmortem

## 7. Action items

| Action | Owner | Due | Backlog link | Type |
|--------|-------|-----|--------------|------|
| Fix the pipe issue | carol | 2026-02-01 | #99 | prevent |
PMEOF3

  _special_rc=0
  _special_out="$(sh "$0" to-backlog "$_pm_special" 2>&1)" || _special_rc=$?
  [ "$_special_rc" = "0" ] || {
    echo "postmortem --selftest: FAIL (T7: to-backlog crashed on | and & in path, rc=$_special_rc)" >&2
    _fail=1
  }
  # The Links column must contain the path intact (including | and &)
  printf '%s\n' "$_special_out" | grep -qF "$_pm_special" || {
    echo "postmortem --selftest: FAIL (T7: Links column does not contain intact path with | and &)" >&2
    _fail=1
  }

  # ---- T8 (NEW — Fix 2 pin): new with backslash + & in --title ---------------
  # A literal backslash and & in the title must survive in the stub on a single
  # header line (no missing backslash, no line split from \n interpretation).
  _outdir_bs="${_tmpdir}/postmortems-bs"
  sh "$0" new --id INC-BS --severity P2 --title 'A & B \ C' \
      --date 2026-01-01 --out "$_outdir_bs" >/dev/null 2>&1 || {
    echo "postmortem --selftest: FAIL (T8: new with backslash in title exited non-zero)" >&2; _fail=1
  }
  _stub_bs="${_outdir_bs}/INC-BS.md"
  # The header line in the template is: # [Incident Title] — Postmortem
  # After substitution it should be:   # A & B \ C — Postmortem  (all on one line)
  grep -qF 'A & B \ C' "$_stub_bs" 2>/dev/null || {
    echo "postmortem --selftest: FAIL (T8: 'A & B \\ C' not found literally in stub)" >&2; _fail=1
  }
  # Must be on a SINGLE line (the header), not split by a newline from \n interpretation
  _header_line="$(grep -F 'A & B \ C' "$_stub_bs" 2>/dev/null | head -1)"
  # The header line should end with "— Postmortem" (confirming it was not split)
  printf '%s\n' "$_header_line" | grep -q 'Postmortem' || {
    echo "postmortem --selftest: FAIL (T8: header line was split or truncated — backslash-n became newline)" >&2; _fail=1
  }

  [ "$_fail" -eq 0 ] && { echo "postmortem --selftest: OK"; exit 0; } || exit 1
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------
case "${1:-}" in
  --selftest)  selftest ;;
  new)         shift; cmd_new "$@" ;;
  to-backlog)  shift; cmd_to_backlog "${1:-}" ;;
  *)           usage ;;
esac
