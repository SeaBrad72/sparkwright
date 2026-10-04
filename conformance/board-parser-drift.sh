#!/bin/sh
# board-parser-drift.sh — conformance gate (BOARD-PIPE-ESCAPE T6). Proves the two GFM-exact board
# cell parsers this kit carries — conformance/backlog-lib.sh's cell()/col_index() (the LIB parser,
# sourced by the board gates) and scripts/board-claim.sh's bc_cell/bc_col_index (a DELIBERATE second
# copy, standalone-runnable — see board-claim.sh's own block comment above bc_cell) — agree, BY
# BEHAVIOUR, on a committed corpus of escaped-pipe board rows. It is the mechanism named in the
# design (§6.5): "the one new mechanism is the bc_cell<->cell() behavioural drift gate — no current
# check compares the two parser copies."
#
# HOW IT COMPARES: feeds each corpus row through BOTH parsers, at every column index from 1 up to
# one past the row's own field count, and diffs the two outputs cell-by-cell. This is BEHAVIOURAL,
# not textual — it never diffs the two scripts' source; a semantic drift (one parser's backslash-run
# rule diverging from the other's while the surrounding code differs) is exactly what it is built to
# catch (design §8: "a source-text oracle greens on later drift ... the precedent NOT to follow").
#
# EXTRACTION, NOT SOURCING. board-claim.sh carries `set -eu` and top-level dispatch logic (its own
# block comment: "this script must run BEFORE and INDEPENDENTLY of the conformance tree"), so this
# gate never sources it whole. It extracts ONLY the bc_cell/bc_col_index function bodies (sed range
# between their `bc_cell() {` / `bc_col_index() {` headers and each matching top-level `}`) into a
# throwaway shim it sources instead — the functions themselves are pure (no `exit`, no dispatch), so
# lifting them verbatim reproduces board-claim's real behaviour without its script-level guardrails.
#
#   sh conformance/board-parser-drift.sh            # real corpus run (the tree's own files)
#   sh conformance/board-parser-drift.sh --selftest # mutation-proof: M-EVEN/M-ODD/M-TRIM each red;
#                                                    # the unmutated pair greens (liveness leg)
# Exit: 0 = the two parsers agree on every corpus row/column · 1 = a divergence (or a selftest
# expectation failed) · 2 = usage / extraction failure.
# What it changes: read-only — parses corpus fixtures and extracts function bodies into a scratch
#   temp file; touches no tracked file.
# Guardrails: read-only against the tree; no network, no writes to any tracked path; all scratch
#   work happens under `mktemp -d`, cleaned up on exit.
set -eu

HERE=$(CDPATH='' cd "$(dirname "$0")" && pwd)
LIB="$HERE/backlog-lib.sh"
BOARD_CLAIM="$HERE/../scripts/board-claim.sh"
META_CONTROL="$HERE/meta-control-fresh.sh"
BACKLOG_CURRENT="$HERE/backlog-current.sh"
SCRIPTS_DIR="$HERE/../scripts"
HOOKS_DIR="$HERE/../hooks"
CORPUS="$HERE/fixtures/board-parser-corpus/rows.tsv"

# bpd_extract_bc <board-claim.sh path> <out-shim path> — pulls bc_cell + bc_col_index (verbatim,
# unmodified) out of board-claim.sh into a small sourced shim, so this gate never sources the whole
# (set -eu, dispatching) script. Fails loudly (rc 2) if either function is not found — a silent empty
# shim would make every comparison vacuously agree.
# NOTE: this extraction (and bpd_func_range below) is coupled to board-claim.sh's function-header/
# closing-brace layout (`^${fn}() {` ... first following `^}`) -- a cosmetic reformat there (e.g. a
# brace moved to its own line) reds this gate. That is a deliberate fail SAFE/loud tradeoff, not a
# bug: an extraction that silently emptied would make every comparison below vacuously agree.
bpd_extract_bc() {
  _src="$1"; _out="$2"
  : > "$_out"
  for _fn in bc_cell bc_col_index; do
    sed -n "/^${_fn}() {/,/^}/p" "$_src" >> "$_out"
    echo >> "$_out"
  done
  grep -Fq 'bc_cell()' "$_out" || { echo "board-parser-drift: FAIL -- could not extract bc_cell from $_src" >&2; return 2; }
  grep -Fq 'bc_col_index()' "$_out" || { echo "board-parser-drift: FAIL -- could not extract bc_col_index from $_src" >&2; return 2; }
  return 0
}

# bpd_max_cols <row> : how many column indices to try (the row's own gfm_nf, plus one past it, so a
# past-the-end index is compared too -- both parsers must agree it is empty).
bpd_max_cols() {
  _n=$(gfm_nf "$1")
  echo $((_n + 1))
}

# bpd_diff_row <row> <label> : compare cell()/bc_cell and col_index()/bc_col_index across every
# column index for <row>. Echoes each divergence found; returns 1 if any were found.
bpd_diff_row() {
  _row="$1"; _label="$2"; _bad=0
  _max=$(bpd_max_cols "$_row")
  _i=1
  while [ "$_i" -le "$_max" ]; do
    _lib_v=$(cell "$_row" "$_i")
    _bc_v=$(bc_cell "$_row" "$_i")
    if [ "$_lib_v" != "$_bc_v" ]; then
      echo "board-parser-drift: DIVERGE -- class $_label col $_i: cell()=[$_lib_v] bc_cell()=[$_bc_v]"
      _bad=1
    fi
    _i=$((_i + 1))
  done
  # header-name resolution too, using the row itself as a stand-in header (col_index/bc_col_index
  # both resolve BY NAME, so any of the row's own resolved cell values is a legitimate probe name).
  _probe=$(cell "$_row" 1)
  if [ -n "$_probe" ]; then
    _lib_i=$(col_index "$_row" "$_probe")
    _bc_i=$(bc_col_index "$_row" "$_probe")
    if [ "$_lib_i" != "$_bc_i" ]; then
      echo "board-parser-drift: DIVERGE -- class $_label col_index(\"$_probe\"): col_index()=[$_lib_i] bc_col_index()=[$_bc_i]"
      _bad=1
    fi
  fi
  return "$_bad"
}

# bpd_run_corpus <corpus-file> : run every corpus row through bpd_diff_row. Returns 1 on ANY divergence.
bpd_run_corpus() {
  _corpus="$1"; _overall=0
  while IFS= read -r _line || [ -n "$_line" ]; do
    case "$_line" in
      ''|'#'*) continue ;;
    esac
    _label=${_line%%	*}
    _row=${_line#*	}
    bpd_diff_row "$_row" "$_label" || _overall=1
  done < "$_corpus"
  return "$_overall"
}

# bpd_check <lib> <board-claim> <corpus> : source both parser sets and run the corpus. Used by both
# the real run and the selftest (which points it at mutated copies).
bpd_check() {
  _lib="$1"; _bc_src="$2"; _corpus="$3"
  _tmpd=$(mktemp -d) || return 2
  _shim="$_tmpd/bc-shim.sh"
  if ! bpd_extract_bc "$_bc_src" "$_shim"; then
    rm -rf "$_tmpd"
    return 2
  fi
  # shellcheck disable=SC1090
  . "$_lib"
  # shellcheck disable=SC1090
  . "$_shim"
  bpd_run_corpus "$_corpus"
  _rc=$?
  rm -rf "$_tmpd"
  return "$_rc"
}

usage() { echo "usage: board-parser-drift.sh [--selftest]" >&2; }

# --- enumeration -> detection sibling (design 6.6) --------------------------------------
# The consumer set (T2-T5) was ENUMERATED, not derived -- an enumeration misses consumers (the
# standing TRACKER-BACKED-GOVERNANCE lesson). This assertion catches a FUTURE naive consumer added
# to the already-converted set: it FAILs if any of the four converted files carries a raw
# `awk -F'|'` splitter OUTSIDE the allowlisted parser/write functions below.
#
# DISCLOSED LIMITS (design 8): idiom-only -- catches `awk -F'|'`/`-F"|"` and NOTHING else (a new
# naive `sed`/`cut -d'|'`/`IFS='|'`/`${v%%|*}` splitter escapes it entirely); scope-only -- a new
# naive helper added INSIDE an allowlisted function's body also escapes (this proves absence of the
# idiom at the file/function granularity, not semantic correctness of each consumer -- design 8).
#
# ALLOWLIST (the parser/write functions legitimately holding a raw `awk -F'|'`, verified by reading
# each occurrence at plan time -- BOARD-PIPE-ESCAPE T7):
#   backlog-lib.sh:      cell, col_index, gfm_nf              (the canonical GFM-exact parser)
#   scripts/board-claim.sh: bc_row_line, bc_section_bounds, bc_cell, bc_col_index (the proven-
#                         equivalent standalone copy, T3/T4), bc_new_row (the write path, T5 --
#                         builds a row from ENVIRON-supplied cells, never reads board content),
#                         bc_v_ncols (selftest-only column counter, proves the write path preserves
#                         arity -- T5 leg 5; never reads a real board)
#   meta-control-fresh.sh: log_field, trailing_deferred, header_row (STRUCTURAL scans only -- they
#                         awk-split to find the header/separator rows by position, never to extract
#                         cell content; log_field/trailing_deferred hand the row itself to
#                         backlog-lib.sh's cell()/gfm_nf() to read a value -- M-1, BOARD-PIPE-ESCAPE
#                         fix round -- see each function's own block comment)
#   backlog-current.sh:  none -- its former raw `awk -F'|' NF` idiom was fully replaced in T2; the
#                         file's remaining `awk -F'|'` text is inside comments describing the OLD
#                         idiom it replaced, not a live splitter (verified: no allowlist needed)

# bpd_func_range <file> <fn> -> "<start> <end>" line numbers for a top-level `<fn>() { ... }` body
# (matches the SAME simple, non-nested convention bpd_extract_bc already relies on for board-claim.sh
# -- see the coupling note above bpd_extract_bc). Prints nothing (rc 1) if <fn> is not found.
bpd_func_range() {
  _file="$1"; _fn="$2"
  _start=$(grep -n "^${_fn}() {" "$_file" 2>/dev/null | head -n 1 | cut -d: -f1)
  [ -n "$_start" ] || return 1
  _end=$(awk -v s="$_start" 'NR>s && /^}/ {print NR; exit}' "$_file")
  [ -n "$_end" ] || return 1
  echo "$_start $_end"
}

# bpd_enum_ranges <file> [fn...] -> newline-separated "<start> <end>" ranges for each fn found.
bpd_enum_ranges() {
  _file="$1"; shift
  for _fn in "$@"; do
    bpd_func_range "$_file" "$_fn" 2>/dev/null || true
  done
}

# bpd_enum_offenders <file> <ranges> -> prints "<file>:<line>" for every raw `awk -F'|'`/`-F"|"`
# occurrence in <file> whose line number falls OUTSIDE every range in <ranges>.
bpd_enum_offenders() {
  _file="$1"; _ranges="$2"
  [ -f "$_file" ] || return 0
  # Exclude whole-line comments (`^[ \t]*#`) -- several converted files document the OLD raw idiom
  # they replaced in a block comment quoting `` `awk -F'|'` `` verbatim; that prose is not a splitter.
  # The exclusion is ANCHORED to the `grep -n` line-number prefix (`^[0-9]+:[ \t]*#`) so it only
  # matches a WHOLE-LINE comment -- an unanchored `#` match would also exclude a LIVE splitter line
  # carrying a trailing comment (e.g. `x=$(awk -F'|' ...) # note: # tail`), letting a real naive
  # consumer slip past uncaught (BOARD-PIPE-ESCAPE fix round, L-2).
  # TBG-ROADMAP-CURRENT-SEAM / HIGH-B.1 (second security round): the idiom used to require the
  # CONTIGUOUS literal `awk -F'|'`/`awk -F"|"`, so a splitter with args BEFORE `-F` (the real shape
  # backlog-lib.sh's own `cells_in_section` uses, `awk -v sec="$2" -v want="$3" -F'|'`) was invisible
  # to a raw splitter added elsewhere in the same style. Match `-F'|'`/`-F"|"` preceded by `awk`
  # ANYWHERE earlier on the line, regardless of what args sit between them.
  # TBG-ROADMAP-CURRENT-SEAM / L-3 (pre-existing, disclosed, not chased): this idiom detects the
  # contiguous-flag form `awk ... -F'|'`/`awk ... -F"|"` only. A SPACED flag (`awk -F '|'`), a
  # variable-assigned FS (`awk -v FS='|'`), an in-program `BEGIN{FS="|"}`, or an explicit `split(s, a,
  # "|")` are outside this idiom's detection shape and are not caught here.
  _bpd_sq=\'
  _bpd_awkf_pat="awk.*-F[${_bpd_sq}\"]\\|[${_bpd_sq}\"]"
  _lines=$(grep -n -E "$_bpd_awkf_pat" "$_file" 2>/dev/null | grep -v -E '^[0-9]+:[ 	]*#' | cut -d: -f1) || true
  for _ln in $_lines; do
    _covered=0
    while IFS= read -r _r; do
      [ -z "$_r" ] && continue
      _s=${_r%% *}; _e=${_r#* }
      if [ "$_ln" -ge "$_s" ] 2>/dev/null && [ "$_ln" -le "$_e" ] 2>/dev/null; then
        _covered=1; break
      fi
    done <<EOF
$_ranges
EOF
    [ "$_covered" -eq 0 ] && echo "$_file:$_ln"
  done
}

# bpd_enum_check <lib> <board-claim> <meta-control> <backlog-current> : the enumeration->detection
# assertion. Returns 1 (and prints every offending file:line) if a raw `awk -F'|'` splitter is found
# outside the allowlist above in any of the four covered files.
bpd_enum_check() {
  _lib="$1"; _bc="$2"; _mc="$3"; _blc="$4"
  _offenders=""
  _offenders="$_offenders
$(bpd_enum_offenders "$_lib" "$(bpd_enum_ranges "$_lib" cell col_index gfm_nf cells_in_section)")"
  _offenders="$_offenders
$(bpd_enum_offenders "$_bc" "$(bpd_enum_ranges "$_bc" bc_row_line bc_section_bounds bc_cell bc_col_index bc_new_row bc_v_ncols)")"
  _offenders="$_offenders
$(bpd_enum_offenders "$_mc" "$(bpd_enum_ranges "$_mc" log_field trailing_deferred header_row)")"
  _offenders="$_offenders
$(bpd_enum_offenders "$_blc" "$(bpd_enum_ranges "$_blc")")"
  _offenders=$(printf '%s\n' "$_offenders" | grep -v '^$' || true)
  if [ -n "$_offenders" ]; then
    echo "board-parser-drift: ENUM-OFFENDER -- raw awk -F'|' splitter(s) outside the allowlisted parser/write functions (a new naive consumer?):"
    printf '%s\n' "$_offenders"
    return 1
  fi
  return 0
}

# --- the derived-consumer assertion (TBG-SEAM-CONSUMERS-DERIVED T1, ruling A'/D-240919-4) ----------
# §4.2 (the frozen seam contract): "a conformance leg fails when any file under conformance/, hooks/
# or scripts/ OTHER THAN THE SEAM opens the board file, calls resolve_backend/section_rows/cell
# directly, or names curl." Read literally this reds the honest tree (measured: many files legitimately
# name `curl` -- guard tests, tracker-contract.sh, supply-chain-verify.sh -- with no board involvement
# at all). RULING A' (owner, 2026-09-19, D-240919-4): allowlist-scoped detection, with `curl` POSITIVELY
# SCOPED rather than file-allowlisted, so the `curl` clause cannot erode into a rubber stamp (L1 of the
# design's ten-lens review). Three clauses:
#
#   (a) BOARD-CONTENT READ -- a file opens BACKLOG.md directly (a real cat/redirect/git-show read
#       idiom -- NOT a bare existence test or a string literal, which are legitimate everywhere and
#       would make a literal-text scan hopelessly noisy: this repo's own selftests build dozens of
#       throwaway BACKLOG.md FIXTURES via `cat >`/heredoc, which is a WRITE, never a read) OR calls
#       `section_rows`/`cell` (the shared parser) BY INVOCATION SHAPE (a real call, not the word
#       appearing in a comment or a sibling identifier like gfm_cell/bc_cell/retro_cell). EXCLUDED,
#       by a named + justified allowlist (D-240919-3 + the seam):
#         backlog-lib.sh        -- the seam itself (§4.2); defines section_rows/cell and uses them
#                                   internally (seam_row_count/seam_row_state/seam_rows_in_state).
#         backlog-current.sh    -- D-240919-3 (a)+(c): md-format/column-arity/GFM-shape validators,
#                                   plus check_done_retro/check_done_uat (repo-side Done retro/UAT
#                                   grading, §4.5 -- git-shaped, stays repo-side on every backend).
#                                   FILE-scoped, not function-range: this is the file backlog-lib.sh's
#                                   primitives were extracted FROM VERBATIM (backlog-lib.sh's own
#                                   header), i.e. it IS the md-board shape/DoR/DoD validator, and its
#                                   own selftest() exercises the shared parser directly (proving it,
#                                   not bypassing it).
#         backlog-presence.sh   -- D-240919-3 (b): the md PR->row INVERSE presence search
#                                   (row_bears_pr/base_row_in_done/gov_row_id) -- on a tracker this is
#                                   answered from the `Kit-Row` trailer, never a board search (§4.2's
#                                   own `pr-bound` note). inprogress_hints already ROUTES through
#                                   `seam_rows_in_state` (TBG-SEAM-MD-ARM) and carries no section_rows/
#                                   cell call of its own -- only the inverse search keeps the direct
#                                   read. File-scoped for the same selftest reason as above.
#         scripts/board-claim.sh -- the verified-EQUIVALENT bc_* parser copy (bc_row_line/
#                                   bc_section_bounds/bc_cell/bc_col_index/bc_new_row/bc_v_ncols);
#                                   this very file's bpd_check proves it agrees with cell()/
#                                   section_rows() BY BEHAVIOUR on the corpus above.
#         board-drift.sh         -- TBG-SEAM-CONSUMERS-DERIVED T2: routed through seam_backend first
#                                   (rc 3 NOT ENFORCED on a declared non-md backend); its In-Review
#                                   PR-cell read is reached ONLY once the seam has confirmed the
#                                   backend supports it, and extracts a PR NUMBER -- a GitHub concept
#                                   with no seam analogue, the same non-portability D-240919-3 (b)
#                                   already names for the presence search.
#         review-lane.sh         -- RECORD-GRAMMAR-ESSENTIALS (D-240930-1): the XS/S ceiling reads one
#                                   row's Size cell from the board AS IT STOOD AT THE MERGE-BASE
#                                   (`git show <base>:BACKLOG.md` into a temp file) -- the seam reads
#                                   the working tree and exposes no size value (only dor-size). Reached
#                                   ONLY after seam_backend confirms md; on any tracker backend the
#                                   ceiling is owed, never read. Retired by REVIEW-LANE-SIZE-VIA-SEAM.
#         meta-control-fresh.sh  -- calls the shared `cell()` primitive, but on rows sourced from
#                                   docs/governance/.meta-control-verdict-log.md -- a DIFFERENT,
#                                   always-repo-side governance file, never BACKLOG.md and never
#                                   `section_rows` (verified: this file carries zero section_rows/
#                                   BACKLOG.md hits of its own -- only cell(), on an already-selected
#                                   row string). No tracker analogue; not a board read.
#
#   (b) resolve_backend, BY INVOCATION SHAPE, OUTSIDE the seam. EXCLUDED: backlog-lib.sh (defines +
#       uses it internally, incl. via seam_backend's thin wrapper) and the named NON-board-governance
#       users who read the backend FIELD for export/incept identity, never a board-governance read:
#       scripts/incept.sh, scripts/adopter-export.sh, conformance/adopter-export-wired.sh,
#       conformance/inception-done.sh.
#
#   (c) curl -- POSITIVELY SCOPED (D-240919-4), never file-allowlisted: flagged ONLY inside a file
#       that is ALSO a board-content reader -- RAW idiom (a real section_rows/cell call or a real
#       BACKLOG.md-open) OR A SEAM CALLER (a real seam_* invocation) -- regardless of whether (a)
#       then exempts the raw idiom, excluding the seam itself. A file that names `curl` but never
#       reads the board (tracker-contract.sh, supply-chain-verify.sh, the guard tests,
#       actionlint-valid.sh, inception-done.sh's own hostile-hook FIXTURE STRING, ...) is never
#       flagged and needs no allowlist entry -- the erosion the file-allowlist form (recommendation A)
#       would have invited. ⚠️ THE SEAM-CALLER ARM IS LOAD-BEARING (security fix round, H-1): a file
#       routed cleanly through `seam_*` and nothing else (no raw idiom at all -- the CANONICAL shape a
#       future gate is most likely to take) is precisely the file most likely to grow a tracker call
#       next, and it is the file this control exists to bind. Gating curl on the raw-idiom set alone
#       let it escape entirely. The teeth: a board-governance consumer -- raw OR seam-routed -- must
#       never reach a tracker outside the seam's own reader.
#
# COMMENT-ANCHORED EXCLUSION, as bpd_enum_offenders already uses (`^[0-9]+:[ \t]*#` -- a whole-line
# comment, never a trailing one on live code, per that function's own L-2 disclosure).
#
# HONEST CEILING (design §4, stated not glossed): idiom + scope detection, not semantic proof. It
# proves the absence of these idioms at the file/invocation-shape granularity in an unallowlisted
# file -- not that every consumer is semantically correct, and a wrapper/alias/indirect-variable
# bypass (e.g. `x="sec"; x"tion_rows" ...`, or piping through a helper that itself calls curl) escapes
# a grep entirely. Detection-shaped: a gate added tomorrow that copies one of these idioms verbatim
# is exactly what this catches. Also stated (TRACKER-GATES-TRUSTED-WIRING T3): clause (c)'s
# seam-caller arm matches public `seam_*` calls only -- a leading `_` is a word character, so a file
# calling a private seam function (e.g. `_seam_record_load`) beside `curl` escapes it; the reader's
# producer contract test is the one known legitimate caller; building it is
# `BOARD-PARSER-DRIFT-PRIVATE-SEAM-CALLS`.

bpd_dc_is_comment_excluded() { grep -v -E '^[0-9]+:[ 	]*#'; }

# bpd_dc_open_offenders <file> -> "<line>:<text>" for a REAL read of a literal BACKLOG.md (cat/
# redirect-in/git-show/an OPERAND-shaped text-tool invocation) -- never a bare existence test
# (`[ -f BACKLOG.md ]`) or a string literal (usage text, a fixture path assembled from a variable),
# which are legitimate everywhere and would otherwise make a literal-text scan hopelessly noisy
# (measured: dozens of `cat > .../BACKLOG.md` FIXTURE WRITES across this tree's own selftests --
# `[^>]` after `cat ` excludes exactly that shape). ⚠️ THE OPERAND IDIOM IS LOAD-BEARING (security fix
# round, M-1): `roadmap-current.sh:258`'s `rc_awk ROADMAP.md BACKLOG.md "$_armed"` reads BACKLOG.md by
# passing it as a DIRECT OPERAND to a wrapper function (never `cat`/a redirect/`git show`), calls no
# seam function, and was on no allowlist -- a real, live bypass the original three idioms missed
# entirely. Two operand arms, both measured against every false positive a broader single pattern
# produced (English prose containing "cut"/"released" [sic, contains "sed"], a `grep`/`sed` invocation
# whose OWN argument is a QUOTED STRING that merely MENTIONS "BACKLOG.md" rather than reading the
# file):
#   (i) `awk` — deliberately UNANCHORED on the command name (a substring match, only requiring a
#       non-letter before it and a REQUIRED SPACE right after it): that is exactly what catches
#       `rc_awk` (a wrapper whose own name CONTAINS `awk`) while still rejecting prose like
#       "awkward" (no space follows "awk" there).
#   (ii) `grep`/`sed`/`head`/`tail`/`wc`/`cut`/`sort` — held to a REAL invocation shape instead (start
#       of line, or preceded by `;`/`&`/`|`/`$(`, then the bare command name, then a required space)
#       so "released" (contains "sed") and "(cut from" (prose, preceded by a bare `(`) never match.
# Either arm's candidate is then POST-FILTERED to drop a match where "BACKLOG.md" is immediately
# followed by a quote character or by a space-then-lowercase-word — the shape of "...mentions
# BACKLOG.md mid-sentence inside a quoted string" (`'ALLOWLISTED: BACKLOG.md'`, `"...BACKLOG.md only"`,
# `(cut from BACKLOG.md pre-repair)`) rather than "BACKLOG.md is a trailing bare OPERAND" (the real
# bypass's own shape: followed by a space-then-quote, a semicolon, or end of line).
bpd_dc_open_offenders() {
  _f="$1"
  [ -f "$_f" ] || return 0
  # The original three idioms (cat/redirect-in/git-show) carry NO post-filter -- their own
  # bracket-exclusion (`[^>]`/`[^<]`/`[^|]`) already keeps fixture WRITES out, and applying the
  # operand arms' prose post-filter here too would wrongly drop a genuine `cat "$dir/BACKLOG.md"`
  # whose very next byte is the closing quote (measured: it did, in this function's own selftest).
  _dc_oo1=$(grep -n -E -e 'cat [^>]*BACKLOG\.md' -e '<[^<]*BACKLOG\.md' -e 'git show[^|]*:BACKLOG\.md' \
              "$_f" 2>/dev/null | bpd_dc_is_comment_excluded) || true
  # The two OPERAND arms (M-1) are noisier against prose (see the block comment above) and are the
  # only ones the post-filter applies to.
  # TBG-ROADMAP-CURRENT-SEAM / M-1b (security seat MED-1): the post-filter's KEEP-condition is now
  # SLASH-PRECEDED, not "slash- or quote-preceded" -- the real bypass shape is a slashed-path operand
  # (`awk … "$1/BACKLOG.md"`, `"$dir/BACKLOG.md"`); a bare `"BACKLOG.md"`/`'BACKLOG.md'` immediately
  # after a quote or a space+lowercase-word is a STRING MENTION (a search argument: `grep -q
  # "BACKLOG.md" f`, `sed 's/BACKLOG.md/x/'`), not a read. The naive `[^/\"']BACKLOG\.md['\"]` form
  # over-reports on exactly those two shapes; this predicate drops everything that is NOT `/`-preceded
  # (so a real path operand survives) OR is followed by a space+lowercase-word (the `sort BACKLOG.md
  # foo` prose shape). RESIDUAL, disclosed: `sed 's/BACKLOG.md/x/'` carries a `/` immediately before
  # `BACKLOG.md` (the sed delimiter, not a path separator) and this predicate cannot distinguish the
  # two syntactically -- it is KEPT (a false positive), which is the safe direction (toward RED), not
  # a silent hole.
  # TBG-ROADMAP-CURRENT-SEAM / M-2 (security seat MED-2): the prose post-filter is a QUOTE-drop --
  # legitimate for grep/sed (whose own trailing argument CAN be a bare-quoted search string, e.g.
  # `grep -q "BACKLOG.md" f`) but WRONG for awk/head/tail/wc/cut/sort, whose trailing operand IS the
  # file being read even when it happens to be quoted (`awk '{print}' "BACKLOG.md"`,
  # `head -n 5 "BACKLOG.md"`) -- applying the same drop to both arms let those real reads slip through
  # GREEN. Split into two arms; the drop applies ONLY to the grep/sed arm.
  # TBG-ROADMAP-CURRENT-SEAM / MED-A + MED-B (second security round): `[^>|]*` -> `[^>]*` in every
  # operand arm (a pipe byte on the line, e.g. `cut -d'|' -f2 BACKLOG.md`, no longer breaks the
  # match -- crossing a pipeline is still a read). MED-B: the head/tail/wc/cut/sort prefix
  # alternation widened to also admit a `then`/`do`/`if`/`!`/`{`/`(` keyword prefix and a leading
  # env-assignment (`LC_ALL=C sort BACKLOG.md`), disclosed-then-closed rather than left silent.
  _dc_oo2a=$(grep -n -E \
               -e '(^|[^A-Za-z])awk[ 	][^>]*BACKLOG\.md' \
               -e '(^|[;&|]|\$\(|[A-Za-z_][A-Za-z0-9_]*=[^ 	]*)[ 	]*(head|tail|wc|cut|sort)[ 	]+[^>]*BACKLOG\.md' \
               -e '(^|[;&|])[ 	]*(then|do|if|!|\{|\()[ 	]*(head|tail|wc|cut|sort)[ 	]+[^>]*BACKLOG\.md' \
               "$_f" 2>/dev/null | bpd_dc_is_comment_excluded) || true
  # MED-A residual: the quote-drop split into TWO shapes, either of which drops the line (a genuine
  # `grep -c . "BACKLOG.md"`/`sed -n 1p "BACKLOG.md"` trailing operand matches NEITHER and stays
  # flagged -- closing the residual measured on THIS ROUND'S OWN FIRST DRAFT, which used the task's
  # single "followed by another argument" shape alone and regressed a real file to FAIL:
  # `grep -q 'ALLOWLISTED: BACKLOG.md' || { ... }` in owner-step-markers.sh, a MID-STRING MENTION with
  # no following shell argument):
  #   (i)  a MID-STRING MENTION -- the quote does NOT immediately precede BACKLOG.md (other text sits
  #        between the opening quote and the token, e.g. "ALLOWLISTED: BACKLOG.md"): never a bare
  #        file operand.
  #   (ii) "quoted BACKLOG.md followed by ANOTHER argument" -- the search-string shape
  #        (`grep -q "BACKLOG.md" f`).
  # A BARE quoted operand with NOTHING else inside the quotes and NOTHING else following (the real
  # bypass's own shape) matches neither and stays flagged.
  # TBG-ROADMAP-CURRENT-SEAM / N-2 (security seat, third round): shape (i) required only ONE-OR-MORE
  # non-quote bytes between the opening quote and the token, with no constraint on WHICH byte sits
  # immediately before it -- so a SLASHED quoted path (`grep -c . "$dir/BACKLOG.md"`, `sed -n 1p
  # "$W/BACKLOG.md"`, a genuine read) matched the mid-string-mention shape and was wrongly dropped.
  # Fixed: the byte immediately before the token must be NON-SLASH (a real path operand's `/` no
  # longer qualifies as "other text before the mention"); `"$dir/BACKLOG.md"` now fails shape (i) and
  # stays flagged, while a genuine mention (`'ALLOWLISTED: BACKLOG.md'`, space-preceded) still drops.
  # TBG-ROADMAP-CURRENT-SEAM / L-4 (pre-existing residual): shape (ii) treated ANY following
  # non-whitespace/semicolon/pipe/paren byte as "another argument" and dropped the line -- including a
  # REDIRECT (`grep -c '^|' "BACKLOG.md" 2>/dev/null`, `sed -n 1p "BACKLOG.md" >out`), which is not
  # another argument at all and is a real read. Excluded a digit/`<`/`>`-led follower (the redirect
  # shapes) from the drop.
  _dc_oo2b=$(grep -n -E -e '(^|[;&|]|\$\()[ 	]*(grep|sed)[ 	]+[^>]*BACKLOG\.md' \
               "$_f" 2>/dev/null | bpd_dc_is_comment_excluded \
               | grep -v -E "['\"][^'\"]*[^'\"/]BACKLOG\.md|BACKLOG\.md['\"][ 	]+[^ 	;&|)0-9<>]") || true
  printf '%s\n%s\n%s\n' "$_dc_oo1" "$_dc_oo2a" "$_dc_oo2b" | grep -v '^$' || true
}

# bpd_dc_section_rows_offenders <file> -> a real `section_rows`/`cells_in_section`/`section_present`
# CALL (invocation shape: followed by a space+quote or an open paren) -- never the bare word in a
# comment/doc line (already comment-excluded) or a sibling identifier (there is none sharing any of
# these exact names). TBG-ROADMAP-CURRENT-SEAM / HIGH-B.3 (second security round): the detector used
# to match `section_rows[ (]` ONLY, so a file reading the board exclusively via `cells_in_section`/
# `section_present` (the batched TBG-ROADMAP-CURRENT-SEAM primitives) was NOT recognised as a
# board-governance consumer -- it escaped clause (a) entirely, AND never entered clause (c)'s curl
# scoping (`_dc_sr` feeds both). Widened to all three primitives.
bpd_dc_section_rows_offenders() {
  _f="$1"
  [ -f "$_f" ] || return 0
  grep -n -E '(^|[^A-Za-z0-9_])(section_rows|cells_in_section|section_present)[ (]' "$_f" 2>/dev/null \
    | bpd_dc_is_comment_excluded || true
}

# bpd_dc_cell_offenders <file> -> a real `cell` CALL (invocation shape `cell "..."`), preceded by a
# non-identifier char or start-of-line -- so `gfm_cell`/`bc_cell`/`retro_cell`/`is_bare_na` (which all
# END in or contain unrelated identifier text) never match; only the bare primitive's own call site.
bpd_dc_cell_offenders() {
  _f="$1"
  [ -f "$_f" ] || return 0
  grep -n -E '(^|[^A-Za-z0-9_])cell "' "$_f" 2>/dev/null | bpd_dc_is_comment_excluded || true
}

# bpd_dc_resolve_backend_offenders <file> -> a real `resolve_backend` CALL (invocation shape: a call
# with an argument, an assignment, or a subshell), never the bare word in a comment/doc/echo-string
# line (e.g. an error message ABOUT resolve_backend, which several files carry and none of which is a
# call).
bpd_dc_resolve_backend_offenders() {
  _f="$1"
  [ -f "$_f" ] || return 0
  grep -n -e 'resolve_backend "' -e 'resolve_backend \$' -e '=resolve_backend' -e '(resolve_backend' "$_f" 2>/dev/null \
    | bpd_dc_is_comment_excluded || true
}

# bpd_dc_seam_offenders <file> -> a real `seam_*` invocation (bare call shape: the identifier
# followed by a space, a closing paren of a command-substitution `$(seam_x)`, or end of line --
# NEVER the `seam_x() {` DEFINITION shape, whose next character is an opening paren; that excludes
# backlog-lib.sh's own definitions even before the separate seam-file exemption below runs).
# Security fix round H-1: clause (c)'s curl gate used to key off RAW board-content hits only, so a
# file routed cleanly through the seam (no raw idiom left at all) escaped it -- exactly the shape a
# future gate is most likely to take. This is the second (and now load-bearing) half of "is this file
# a board-content reader" for clause (c) only; clause (a) does not use it (a seam call is never itself
# a bypass -- it is the sanctioned path).
bpd_dc_seam_offenders() {
  _f="$1"
  [ -f "$_f" ] || return 0
  # TBG-ROADMAP-CURRENT-SEAM / B: widened the tail from `( |\)|$)` to `( |\)|;|$)` so a `;`-terminated
  # seam call (`x=$(seam_foo); …`) is detected too -- purely additive, no new hole.
  grep -n -E '(^|[^A-Za-z0-9_])seam_[a-z_]+( |\)|;|$)' "$_f" 2>/dev/null | bpd_dc_is_comment_excluded || true
}

# bpd_dc_curl_offenders <file> -> every LIVE, whole-word `curl` occurrence (the clause (c) candidate
# set BEFORE the positive board-reader scoping is applied by the caller).
bpd_dc_curl_offenders() {
  _f="$1"
  [ -f "$_f" ] || return 0
  grep -n -w 'curl' "$_f" 2>/dev/null | bpd_dc_is_comment_excluded || true
}

# bpd_dc_bc_exempt <file> -> rc0 iff <file> is the seam or a named D-240919-3/T2 carve-out, exempt
# from clause (a) (board-content read). See the allowlist comment above for each entry's justification.
bpd_dc_bc_exempt() {
  case "$1" in
    */backlog-lib.sh|*/backlog-current.sh|*/backlog-presence.sh|*/board-claim.sh|*/board-drift.sh|*/meta-control-fresh.sh|*/review-lane.sh)
      return 0 ;;
    */prepush-lane.sh|*/hooks/pre-push)
      # PLUMBING, not parsing: both materialize a `git show <base>:BACKLOG.md` SNAPSHOT FILE for
      # another gate's own seam-routed `--base-board` consumption (backlog-presence.sh) -- they never
      # call section_rows/cell/resolve_backend themselves (verified: zero live hits in either file),
      # and never interpret a single cell of the board's content.
      return 0 ;;
    */roadmap-current.sh)
      # PRINCIPLED CARVE-OUT (d), D-240919-5, not a TODO: `rc_awk` does a TOKEN-BOUNDED SUBSTRING
      # search of each pending roadmap item's id within the Done section's raw cell-1 TEXT -- it is
      # NOT an id-equality join `seam_rows_in_state Done` could answer: a Done row's cell 1 can carry
      # prose beyond its own backtick id (this file's own header discloses a real one, "satisfied-by-
      # P1.4"), and the join's whole correctness story depends on searching that prose, not just the
      # row's canonical id. This is non-tracker-portable (a Jira/Linear issue has no cell-1 prose
      # carrying that substring), touches no curl/credential, and (post TBG-ROADMAP-CURRENT-SEAM) the
      # board read itself is EXCLUSIVELY the shared GFM-exact parser (section_rows/cell,
      # backlog-lib.sh) -- the three D-240919-3 point-4 criteria for admitting a 4th carve-out.
      # FILE-GRANULAR CEILING (security seat MED-2): this entry exempts the WHOLE file from clause
      # (a); it does not itself verify the board read is exclusively section_rows/cell -- that is
      # enforced by the STANDING ABSENCE LEG below (bpd_dc_open_offenders' own selftest greps
      # roadmap-current.sh for a raw board-operand read and asserts absence), so criterion (iii) is
      # given teeth by the absence leg, not by this exemption.
      return 0 ;;
  esac
  return 1
}

# bpd_dc_rb_exempt <file> -> rc0 iff <file> is the seam or a named non-board-governance
# resolve_backend user, exempt from clause (b).
bpd_dc_rb_exempt() {
  case "$1" in
    */backlog-lib.sh|*/scripts/incept.sh|*/scripts/adopter-export.sh|*/adopter-export-wired.sh|*/inception-done.sh)
      return 0 ;;
  esac
  return 1
}

# bpd_dc_files -> every .sh file under conformance/, scripts/, hooks/, plus hooks/pre-push (the one
# hook this kit ships, extension-less). Printed newline-separated. BPD_DC_FILES_OVERRIDE, if set (a
# newline-separated file list), REPLACES the real scan entirely -- selftest-only, so the end-to-end
# gate (bpd_derived_consumer_check) can be proven against a synthetic tree without touching the real
# one. BPD_DC_SCAN_HERE/BPD_DC_SCAN_SCRIPTS_DIR/BPD_DC_SCAN_HOOKS_DIR, if set, instead point the REAL
# `find` (L-4's own widening) at a substitute tree -- selftest-only (security seat HIGH-1: no existing
# leg drives the actual `find`; every end-to-end leg short-circuits via BPD_DC_FILES_OVERRIDE before
# it runs).
bpd_dc_files() {
  if [ -n "${BPD_DC_FILES_OVERRIDE:-}" ]; then
    printf '%s\n' "$BPD_DC_FILES_OVERRIDE"
    return 0
  fi
  _dc_f_here="${BPD_DC_SCAN_HERE:-$HERE}"
  _dc_f_scripts="${BPD_DC_SCAN_SCRIPTS_DIR:-$SCRIPTS_DIR}"
  _dc_f_hooks="${BPD_DC_SCAN_HOOKS_DIR:-$HOOKS_DIR}"
  # SELF-EXCLUDED: this file's own source carries the detection patterns themselves (as literal
  # strings in its grep -e arguments) and this selftest's own fixture-generating heredocs (which
  # embed "section_rows"/"cell \""/"resolve_backend"/"curl" as DATA, not live calls) -- scanning
  # itself would be exactly the false-positive-on-fixture-text problem the comment-anchor exclusion
  # already can't fully solve for heredoc bodies. The precedent is bpd_enum_check above, which never
  # scans this file either. Idiom-only detection cannot distinguish "this text IS a call" from "this
  # text NAMES a call", so self-scanning is out of scope by design, not oversight.
  # TBG-ROADMAP-CURRENT-SEAM / L-4: dropped `-maxdepth 1` so a NESTED, non-fixture consumer
  # (conformance/**/*.sh, scripts/**/*.sh, hooks/**/*.sh) is scanned too, and added
  # `! -path '*/fixtures/*'` to exclude fixture trees (a selftest's own throwaway fixtures embed the
  # detection idioms as DATA, not live calls -- see the self-exclusion note above). DISCLOSED CEILING
  # (security seat LOW-1): the exclusion is NAME-based -- a live board-reader under any directory
  # literally named `fixtures/` (not a throwaway test fixture) would be unscanned.
  find "$_dc_f_here" -name '*.sh' -type f ! -name 'board-parser-drift.sh' ! -path '*/fixtures/*' 2>/dev/null
  [ -d "$_dc_f_scripts" ] && find "$_dc_f_scripts" -name '*.sh' -type f ! -path '*/fixtures/*' 2>/dev/null
  [ -d "$_dc_f_hooks" ] && find "$_dc_f_hooks" -name '*.sh' -type f ! -path '*/fixtures/*' 2>/dev/null
  [ -f "$_dc_f_hooks/pre-push" ] && printf '%s\n' "$_dc_f_hooks/pre-push"
  return 0
}

# bpd_derived_consumer_check -> prints every offender ("<clause>: <file>:<line>: <text>") and returns
# 1 if any is found outside its clause's allowlist; 0 on a clean/honest tree.
bpd_derived_consumer_check() {
  _dc_bad=0
  # TBG-ROADMAP-CURRENT-SEAM / H-2b (security seat HIGH-2): fail CLOSED on an empty scanned-file
  # list -- zero files is a dead parser (`find` misfiring, a moved directory, a bad override), not a
  # clean tree, and printing OK over it would be the exact "green over a shrunken domain" class this
  # gate exists to close. `_dc_last_scanned_count` is left as a plain (non-subshelled) global so the
  # dispatch's own OK line can report it too (H-2c).
  _dc_all_files=$(bpd_dc_files)
  _dc_last_scanned_count=$(printf '%s\n' "$_dc_all_files" | grep -c '.' 2>/dev/null || true)
  if [ "${_dc_last_scanned_count:-0}" -eq 0 ]; then
    echo "board-parser-drift: DERIVED-CONSUMER(EMPTY-SCAN) -- the file scan returned ZERO files; a zero-file scan is a dead parser, never a clean tree, and is never reported OK"
    return 1
  fi
  for _dc_f in $_dc_all_files; do
    _dc_is_seam=0
    case "$_dc_f" in */backlog-lib.sh) _dc_is_seam=1 ;; esac

    # clause (a): board-content read, unless allowlisted.
    _dc_open=$(bpd_dc_open_offenders "$_dc_f")
    _dc_sr=$(bpd_dc_section_rows_offenders "$_dc_f")
    _dc_cell=$(bpd_dc_cell_offenders "$_dc_f")
    _dc_seam=$(bpd_dc_seam_offenders "$_dc_f")
    if ! bpd_dc_bc_exempt "$_dc_f"; then
      for _dc_hit in "OPEN:$_dc_open" "SECTION-ROWS:$_dc_sr" "CELL:$_dc_cell"; do
        _dc_tag=${_dc_hit%%:*}; _dc_lines=${_dc_hit#*:}
        [ -n "$_dc_lines" ] || continue
        printf '%s\n' "$_dc_lines" | while IFS= read -r _dc_l; do
          [ -n "$_dc_l" ] || continue
          echo "board-parser-drift: DERIVED-CONSUMER($_dc_tag) -- $_dc_f:$_dc_l bypasses the seam (board-content read outside the allowlist)"
        done
        _dc_bad=1
      done
    fi

    # clause (b): resolve_backend outside the seam, unless named as a non-governance user.
    if ! bpd_dc_rb_exempt "$_dc_f"; then
      _dc_rb=$(bpd_dc_resolve_backend_offenders "$_dc_f")
      if [ -n "$_dc_rb" ]; then
        printf '%s\n' "$_dc_rb" | while IFS= read -r _dc_l; do
          [ -n "$_dc_l" ] || continue
          echo "board-parser-drift: DERIVED-CONSUMER(RESOLVE-BACKEND) -- $_dc_f:$_dc_l calls resolve_backend outside the seam"
        done
        _dc_bad=1
      fi
    fi

    # clause (c): curl, POSITIVELY scoped -- only inside a file that is ALSO a board-content reader,
    # raw (a's detection, regardless of whether (a) then allowlists it) OR seam-routed (H-1), never
    # both required -- excluding the seam itself.
    if [ "$_dc_is_seam" = 0 ] && { [ -n "$_dc_open" ] || [ -n "$_dc_sr" ] || [ -n "$_dc_cell" ] || [ -n "$_dc_seam" ]; }; then
      _dc_curl=$(bpd_dc_curl_offenders "$_dc_f")
      if [ -n "$_dc_curl" ]; then
        printf '%s\n' "$_dc_curl" | while IFS= read -r _dc_l; do
          [ -n "$_dc_l" ] || continue
          echo "board-parser-drift: DERIVED-CONSUMER(CURL) -- $_dc_f:$_dc_l names curl in a board-content-reading file (a board-governance consumer must not reach a tracker outside the seam)"
        done
        _dc_bad=1
      fi
    fi
  done
  [ "$_dc_bad" = 0 ]
}

# bpd_neutrality_check -> rc0 iff none of the seam's own function names (every `seam_*() {` defined
# in backlog-lib.sh) names a tracker (D-240919-3 L4's executable neutrality leg: the seam's NEUTRAL
# surface -- its function names -- must carry no `jira`/`linear` token; only arm BODIES, e.g.
# resolve_backend's backend-token vocabulary, are backend-shaped). ⚠️ WIDENED (security fix round,
# L-3): the enumerator used to require the bare `^seam_[a-z_]+()` shape, byte-for-byte -- it missed
# `function seam_jira() {`/`seam_Jira ()`/any mixed-case function name. Now tolerant of an optional
# leading `function` keyword, leading whitespace, mixed-case identifiers, and whitespace before the
# parens; the token test is CASE-FOLDED (`tr` to lowercase) instead of enumerating case variants by
# hand, so it cannot again miss a case the enumeration forgot to spell out.
bpd_neutrality_check() {
  _nt_target="${1:-$LIB}"
  _nt_bad=0
  for _nt_fn in $(grep -oE '^[ 	]*(function[ 	]+)?seam_[A-Za-z_]+[ 	]*\(\)' "$_nt_target" 2>/dev/null \
                    | sed 's/^[ 	]*//; s/^function[ 	]*//; s/[ 	]*()$//'); do
    _nt_lc=$(printf '%s' "$_nt_fn" | tr '[:upper:]' '[:lower:]')
    case "$_nt_lc" in
      *jira*|*linear*)
        echo "board-parser-drift: NEUTRALITY -- seam function '$_nt_fn' names a tracker (the seam's read surface must stay backend-neutral)"
        _nt_bad=1 ;;
    esac
  done
  [ "$_nt_bad" = 0 ]
}

# --- selftest ---------------------------------------------------------------------------
# selftest marker (mass-budget's logic/fixture boundary): everything above prices as `logic`.
selftest() {
  sd=0
  W=$(mktemp -d)
  trap 'rm -rf "$W"' EXIT

  # Honest pair -- the real lib + the real board-claim.sh -- must AGREE (liveness leg).
  if bpd_check "$LIB" "$BOARD_CLAIM" "$CORPUS"; then
    echo "PASS: selftest -- honest lib/board-claim pair agrees on the whole corpus"
  else
    echo "FAIL: selftest -- honest pair diverges (the gate itself, or the parsers, regressed)"; sd=1
  fi

  # M-EVEN: mutate a COPY of bc_cell so EVERY backslash run (even ones too) is treated as escaping
  # the pipe -- i.e. drop the odd/even distinction entirely and never split on a preceded-by-`\` `|`.
  mk_mutant() { # <mutant-name> <sed-program> -> writes $W/board-claim-<name>.sh
    sed "$2" "$BOARD_CLAIM" > "$W/board-claim-$1.sh"
    # Assert the mutation actually took (BOARD-PIPE-ESCAPE CI fix round): a sed program that is a
    # no-op on this platform (dialect mismatch -- e.g. a BRE quantifier extension one sed accepts and
    # another doesn't) would leave the "mutant" identical to the original, so bpd_check trivially
    # agrees and the leg below wrongly reads as PASS. Fail LOUDLY instead.
    if cmp -s "$BOARD_CLAIM" "$W/board-claim-$1.sh"; then
      echo "FAIL: selftest -- mutant $1 did not change board-claim.sh (sed no-op on this platform)"
      sd=1
    fi
  }

  # M-EVEN: replace the odd-check `if (run % 2 == 1) continue` with `if (run >= 1) continue` inside
  # bc_cell/bc_col_index -- ANY backslash run (odd or even) keeps joining, so `\\|` (even -> should
  # delimit) wrongly fails to split.
  mk_mutant M-EVEN 's/if (run % 2 == 1) continue/if (run >= 1) continue/'
  if bpd_check "$LIB" "$W/board-claim-M-EVEN.sh" "$CORPUS" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  # rc==1 specifically (a real behavioural divergence), not "any nonzero" -- a future extraction
  # crash (rc 2, e.g. the layout-coupling above) must not be mistaken for this mutant's own signal.
  if [ "$rc" -eq 1 ]; then
    echo "PASS: selftest -- M-EVEN mutant reds the gate"
  else
    echo "FAIL: selftest -- M-EVEN mutant did NOT red the gate with rc=1 (expected a divergence on the \\\\| class; got rc=$rc)"; sd=1
  fi

  # M-ODD: replace the odd-check with `if (0) continue` -- NO run ever escapes, every raw `|` always
  # delimits, so `\|` (odd -> should NOT delimit) wrongly splits.
  mk_mutant M-ODD 's/if (run % 2 == 1) continue/if (0) continue/'
  if bpd_check "$LIB" "$W/board-claim-M-ODD.sh" "$CORPUS" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ]; then
    echo "PASS: selftest -- M-ODD mutant reds the gate"
  else
    echo "FAIL: selftest -- M-ODD mutant did NOT red the gate with rc=1 (expected a divergence on the \\| class; got rc=$rc)"; sd=1
  fi

  # M-TRIM: drop the trim (gsub of leading/trailing whitespace) inside bc_cell only, so a cell that
  # carries incidental padding around its content compares unequal to the lib's trimmed value.
  # (dialect-portable: no `\+`/ERE quantifier extension -- BSD sed doesn't honor it the way GNU
  # sed does, so an earlier version of this mutant was a silent no-op on GNU/Linux; `+` and `$`
  # are literal here anyway under plain BRE since neither sits at an anchor position, so this
  # matches byte-for-byte on both dialects. A different delimiter (`#`) avoids escaping the `/`.)
  mk_mutant M-TRIM 's#gsub(/^\[ \\t\]+|\[ \\t\]+$/,"",v);##'
  if bpd_check "$LIB" "$W/board-claim-M-TRIM.sh" "$CORPUS" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ]; then
    echo "PASS: selftest -- M-TRIM mutant reds the gate"
  else
    echo "FAIL: selftest -- M-TRIM mutant did NOT red the gate with rc=1 (expected untrimmed vs trimmed divergence; got rc=$rc)"; sd=1
  fi

  # --- enumeration -> detection leg (design 6.6, T7) -------------------------------------
  # Liveness: the honest four files must agree the allowlist covers every raw awk -F'|' occurrence.
  if bpd_enum_check "$LIB" "$BOARD_CLAIM" "$META_CONTROL" "$BACKLOG_CURRENT" >/dev/null 2>&1; then
    echo "PASS: selftest -- enum-check greens on the honest converted set"
  else
    echo "FAIL: selftest -- enum-check reds on the honest converted set (allowlist drifted from the real code)"; sd=1
  fi

  # Non-vacuity: inject a NEW naive `awk -F'|'` splitter into a COPY of backlog-current.sh (which
  # carries NO allowlisted function -- T2 fully replaced its raw idiom), outside any function this
  # gate would allowlist, and confirm the enum-check REDS on it (a stand-in for a future 6th
  # consumer the enumeration never named).
  cat > "$W/backlog-current-mutant.sh" <<'MUTEOF'
naive_new_consumer() {
  awk -F'|' '{ print $2 }' "$1"
}
MUTEOF
  cat "$BACKLOG_CURRENT" >> "$W/backlog-current-mutant.sh"
  if bpd_enum_check "$LIB" "$BOARD_CLAIM" "$META_CONTROL" "$W/backlog-current-mutant.sh" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ]; then
    echo "PASS: selftest -- enum-check reds on an injected naive awk -F'|' consumer (non-vacuity)"
  else
    echo "FAIL: selftest -- enum-check did NOT red on an injected naive consumer with rc=1 (got rc=$rc)"; sd=1
  fi

  # TBG-ROADMAP-CURRENT-SEAM / HIGH-B.1 (second security round): a raw splitter with ARGS BEFORE
  # `-F` (`awk -v sec="$2" -v want="$3" -F'|' ...`, the exact shape a copy of cells_in_section's own
  # idiom would take) injected OUTSIDE the allowlist must still be caught.
  cat > "$W/backlog-current-mutant3.sh" <<'MUTEOF'
naive_args_before_f_consumer() {
  awk -v sec="$2" -F'|' '{ print $2 }' "$1"
}
MUTEOF
  cat "$BACKLOG_CURRENT" >> "$W/backlog-current-mutant3.sh"
  if bpd_enum_check "$LIB" "$BOARD_CLAIM" "$META_CONTROL" "$W/backlog-current-mutant3.sh" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ]; then
    echo "PASS: selftest -- enum-check reds on a raw awk -F'|' splitter whose args precede -F (HIGH-B.1, non-vacuity)"
  else
    echo "FAIL: selftest -- enum-check did NOT red on an args-before-F splitter with rc=1 (got rc=$rc)"; sd=1
  fi

  # TBG-ROADMAP-CURRENT-SEAM / HIGH-B.1.2 (second security round): cells_in_section is a THIRD copy
  # of the GFM escaped-pipe split (backlog-lib.sh:140-160), asserted byte-identical to
  # section_rows+cell only in a comment. Standing corpus leg: for every corpus row, wrap it as the
  # sole row of a `## Done` section and assert cells_in_section() agrees, PER COLUMN, with the oracle
  # `section_rows | while read; do cell; done` -- the same oracle the security seat ran by hand.
  # `cell`/`section_rows`/`cells_in_section` are already sourced (bpd_check ran above).
  _cis_bad=0
  while IFS= read -r _cis_line || [ -n "$_cis_line" ]; do
    case "$_cis_line" in ''|'#'*) continue ;; esac
    _cis_label=${_cis_line%%	*}
    _cis_row=${_cis_line#*	}
    _cis_board="$W/cis-corpus-board.md"
    printf '## Ready\n| PLACEHOLDER | m |\n\n## Done\n%s\n\n## Blocked\n| none |\n' "$_cis_row" > "$_cis_board"
    _cis_max=$(bpd_max_cols "$_cis_row")
    _cis_i=1
    while [ "$_cis_i" -le "$_cis_max" ]; do
      _cis_batched=$(cells_in_section "$_cis_board" Done "$_cis_i")
      _cis_oracle=$(section_rows "$_cis_board" Done | while IFS= read -r _cis_r; do cell "$_cis_r" "$_cis_i"; done)
      if [ "$_cis_batched" != "$_cis_oracle" ]; then
        echo "FAIL: selftest -- cells_in_section diverges from section_rows+cell on corpus class $_cis_label col $_cis_i: batched=[$_cis_batched] oracle=[$_cis_oracle]"
        _cis_bad=1
      fi
      _cis_i=$((_cis_i + 1))
    done
  done < "$CORPUS"
  if [ "$_cis_bad" -eq 0 ]; then
    echo "PASS: selftest -- cells_in_section agrees with section_rows+cell on every corpus row/column (HIGH-B.1.2)"
  else
    sd=1
  fi

  # L-2 (BOARD-PIPE-ESCAPE fix round): a LIVE naive splitter carrying a trailing `#`-comment on the
  # same line must still be REPORTED -- the whole-line-comment exclusion is anchored to the grep -n
  # line-number prefix, so a trailing comment after real code no longer false-excludes it.
  cat > "$W/backlog-current-mutant2.sh" <<'MUTEOF'
naive_trailing_comment_consumer() {
  x=$(awk -F'|' '{ print $2 }' "$1") # note: # tail
}
MUTEOF
  cat "$BACKLOG_CURRENT" >> "$W/backlog-current-mutant2.sh"
  if bpd_enum_check "$LIB" "$BOARD_CLAIM" "$META_CONTROL" "$W/backlog-current-mutant2.sh" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ]; then
    echo "PASS: selftest -- enum-check reds on a naive splitter with a trailing line comment (L-2)"
  else
    echo "FAIL: selftest -- enum-check did NOT red on a trailing-comment splitter with rc=1 (got rc=$rc)"; sd=1
  fi

  # --- derived-consumer assertion legs (TBG-SEAM-CONSUMERS-DERIVED T1) -------------------
  # Liveness: the honest tree must agree the allowlist covers every real board-content/resolve_backend/
  # curl idiom -- a red here means the allowlist has drifted from the real code (or a genuine bypass
  # was just introduced and this selftest is doing its job).
  if bpd_derived_consumer_check >/dev/null 2>&1; then
    echo "PASS: selftest -- derived-consumer check greens on the honest tree"
  else
    echo "FAIL: selftest -- derived-consumer check reds on the honest tree (allowlist drift, or a real bypass)"; sd=1
  fi

  # Non-vacuity (a): a NAIVE new board-opener, injected into a COPY that carries NO allowlisted
  # function, must RED clause (a).
  mkdir -p "$W/scripts"
  cat > "$W/scripts/naive-board-opener.sh" <<'DCEOF'
#!/bin/sh
naive_board_reader() {
  cat "$1/BACKLOG.md" | awk -F'|' '{ print $1 }'
}
DCEOF
  _dc_open=$(bpd_dc_open_offenders "$W/scripts/naive-board-opener.sh")
  if [ -n "$_dc_open" ]; then
    echo "PASS: selftest -- an unallowlisted literal BACKLOG.md read reds clause (a) (non-vacuity)"
  else
    echo "FAIL: selftest -- an unallowlisted literal BACKLOG.md read did NOT red clause (a)"; sd=1
  fi

  cat > "$W/scripts/naive-section-rows.sh" <<'DCEOF'
#!/bin/sh
naive_section_rows_caller() {
  section_rows "$1" "Ready"
}
DCEOF
  _dc_sr=$(bpd_dc_section_rows_offenders "$W/scripts/naive-section-rows.sh")
  if [ -n "$_dc_sr" ]; then
    echo "PASS: selftest -- an unallowlisted section_rows call reds clause (a) (non-vacuity)"
  else
    echo "FAIL: selftest -- an unallowlisted section_rows call did NOT red clause (a)"; sd=1
  fi

  # Non-vacuity (a), M-1 twin: a naive OPERAND-shaped read (a wrapper handing BACKLOG.md to a
  # text-reading command as a bare argument, never `cat`/a redirect/`git show`, exactly
  # `roadmap-current.sh:258`'s own shape) must RED clause (a); and END TO END, paired with curl in
  # the SAME file, clause (c) must also fire (a new operand-read consumer is a board-content reader
  # for curl-scoping purposes too).
  cat > "$W/scripts/naive-operand-read.sh" <<'DCEOF'
#!/bin/sh
rc_naive() {
  awk -v roadmap="$1" -v backlog="$2" 'BEGIN{}' ROADMAP.md BACKLOG.md
}
run() {
  rc_naive ROADMAP.md BACKLOG.md "$1"
  curl -s "https://example.invalid/$1"
}
DCEOF
  _dc_op=$(bpd_dc_open_offenders "$W/scripts/naive-operand-read.sh")
  if [ -n "$_dc_op" ]; then
    echo "PASS: selftest -- an unallowlisted operand-shaped BACKLOG.md read reds clause (a) (non-vacuity, M-1)"
  else
    echo "FAIL: selftest -- an unallowlisted operand-shaped BACKLOG.md read did NOT red clause (a) (M-1)"; sd=1
  fi
  _dc_op_list="$W/scripts/naive-operand-read.sh"
  _dc_op_ee=0
  _dc_op_out=$(BPD_DC_FILES_OVERRIDE="$_dc_op_list" bpd_derived_consumer_check 2>&1) || _dc_op_ee=$?
  if printf '%s\n' "$_dc_op_out" | grep -q '(CURL).*naive-operand-read\.sh'; then
    echo "PASS: selftest -- curl IS flagged, end to end, in the same operand-reading file (M-1)"
  else
    echo "FAIL: selftest -- curl was NOT flagged in the operand-reading file, end to end (M-1)"; sd=1
  fi
  [ "$_dc_op_ee" -eq 1 ] \
    && echo "PASS: selftest -- the end-to-end gate reds (rc 1) on the operand-read + curl fixture (M-1)" \
    || { echo "FAIL: selftest -- the end-to-end gate did not red on the operand-read + curl fixture (rc=$_dc_op_ee)"; sd=1; }

  # Non-vacuity (b): a naive `resolve_backend` call, outside the seam and outside the named
  # non-governance users, must RED clause (b).
  cat > "$W/scripts/naive-resolve-backend.sh" <<'DCEOF'
#!/bin/sh
naive_backend_decider() {
  _b=$(resolve_backend "$1")
  printf '%s\n' "$_b"
}
DCEOF
  _dc_rb=$(bpd_dc_resolve_backend_offenders "$W/scripts/naive-resolve-backend.sh")
  if [ -n "$_dc_rb" ]; then
    echo "PASS: selftest -- an unallowlisted resolve_backend call reds clause (b) (non-vacuity)"
  else
    echo "FAIL: selftest -- an unallowlisted resolve_backend call did NOT red clause (b)"; sd=1
  fi

  # Non-vacuity (c): the RULING A' teeth -- curl is flagged ONLY when the SAME file is also a
  # board-content reader. A curl-namer with NO board read must NEVER be flagged (this is the whole
  # point of positive scoping, not a file allowlist); a curl-namer that ALSO reads the board must be.
  cat > "$W/scripts/curl-only-no-board.sh" <<'DCEOF'
#!/bin/sh
fetch_something() {
  curl -s "$1"
}
DCEOF
  cat > "$W/scripts/curl-plus-board.sh" <<'DCEOF'
#!/bin/sh
naive_board_and_tracker() {
  section_rows "$1" "Ready"
  curl -s "https://example.invalid/$2"
}
DCEOF
  # End to end, via BPD_DC_FILES_OVERRIDE: point the REAL gate (bpd_derived_consumer_check) at a
  # synthetic two-file tree and prove the ruling A' behaviour directly, not a re-derivation of it.
  _dc_fixture_list="$W/scripts/curl-only-no-board.sh
$W/scripts/curl-plus-board.sh"
  _dc_ee=0
  _dc_out=$(BPD_DC_FILES_OVERRIDE="$_dc_fixture_list" bpd_derived_consumer_check 2>&1) || _dc_ee=$?
  if printf '%s\n' "$_dc_out" | grep -q '(CURL).*curl-only-no-board\.sh'; then
    echo "FAIL: selftest -- curl-only-no-board.sh (no board read) was flagged for curl; A' positive scoping is not holding"; sd=1
  else
    echo "PASS: selftest -- a curl-namer with NO board read is never flagged, end to end (A' positive scoping)"
  fi
  if printf '%s\n' "$_dc_out" | grep -q '(CURL).*curl-plus-board\.sh'; then
    echo "PASS: selftest -- curl IS flagged, end to end, when the SAME file also reads the board (the clause's real teeth)"
  else
    echo "FAIL: selftest -- curl was NOT flagged, end to end, in a file that also reads the board directly"; sd=1
  fi
  [ "$_dc_ee" -eq 1 ] \
    && echo "PASS: selftest -- the end-to-end gate reds (rc 1) on the curl-plus-board fixture" \
    || { echo "FAIL: selftest -- the end-to-end gate did not red on the curl-plus-board fixture (rc=$_dc_ee)"; sd=1; }

  # Non-vacuity (c), H-1 twin: a SEAM-ROUTED file (no raw idiom at all -- the canonical shape a
  # future gate is most likely to take) that also names curl must red END TO END. Before the fix
  # this escaped entirely: clause (c) keyed off the raw board-content hits only.
  cat > "$W/scripts/seam-plus-curl.sh" <<'DCEOF'
#!/bin/sh
seam_routed_and_tracker() {
  SEAM_ROOT="$1"
  seam_rows_in_state in-review
  curl -s "https://example.invalid/$2"
}
DCEOF
  _dc_seam_list="$W/scripts/curl-only-no-board.sh
$W/scripts/seam-plus-curl.sh"
  _dc_seam_ee=0
  _dc_seam_out=$(BPD_DC_FILES_OVERRIDE="$_dc_seam_list" bpd_derived_consumer_check 2>&1) || _dc_seam_ee=$?
  if printf '%s\n' "$_dc_seam_out" | grep -q '(CURL).*seam-plus-curl\.sh'; then
    echo "PASS: selftest -- curl IS flagged, end to end, in a SEAM-ROUTED file with no raw idiom (H-1)"
  else
    echo "FAIL: selftest -- curl was NOT flagged in a seam-routed (no-raw-idiom) file — H-1 escape reproduced"; sd=1
  fi
  [ "$_dc_seam_ee" -eq 1 ] \
    && echo "PASS: selftest -- the end-to-end gate reds (rc 1) on the seam-plus-curl fixture (H-1)" \
    || { echo "FAIL: selftest -- the end-to-end gate did not red on the seam-plus-curl fixture (rc=$_dc_seam_ee)"; sd=1; }
  if printf '%s\n' "$_dc_seam_out" | grep -q '(CURL).*curl-only-no-board\.sh'; then
    echo "FAIL: selftest -- curl-only-no-board.sh was wrongly flagged in the H-1 twin run"; sd=1
  else
    echo "PASS: selftest -- a curl-namer with no board read stays unflagged in the H-1 twin run too"
  fi

  # Non-vacuity: the honest seam callers name no live curl, so the H-1 arm must NOT red the honest
  # tree (liveness for the seam-caller side specifically, isolating it from the raw-idiom liveness
  # leg above).
  if bpd_derived_consumer_check >/dev/null 2>&1; then
    echo "PASS: selftest -- the honest tree's real seam callers name no curl (H-1 does not false-fire)"
  else
    echo "FAIL: selftest -- the honest tree reds after the H-1 change (a real seam caller names curl, or a false positive)"; sd=1
  fi

  # Neutrality leg (D-240919-3 L4): a synthetic seam function named after a tracker must red; the
  # real seam's own function names (honest tree) must green (already proven by the liveness call
  # above going through bpd_neutrality_check on $LIB directly here too).
  if bpd_neutrality_check >/dev/null 2>&1; then
    echo "PASS: selftest -- the real seam's function names carry no tracker token"
  else
    echo "FAIL: selftest -- the real seam's function names failed the neutrality leg"; sd=1
  fi
  cat > "$W/jira-lib.sh" <<'DCEOF'
seam_jira_backend() { :; }
DCEOF
  if bpd_neutrality_check "$W/jira-lib.sh" >/dev/null 2>&1; then
    echo "FAIL: selftest -- a tracker-named seam function escaped the neutrality predicate (real function, not a re-derivation)"; sd=1
  else
    echo "PASS: selftest -- a tracker-named seam function is DETECTABLE by the REAL predicate (non-vacuity)"
  fi

  # L-3 (security fix round): the widened shapes the narrow enumerator used to miss -- `function`
  # keyword, mixed case, and whitespace before the parens. Each must ALSO be caught by the real
  # bpd_neutrality_check, not a hand re-derivation of its old (narrower) logic.
  cat > "$W/jira-lib-function-kw.sh" <<'DCEOF'
function seam_Jira() { :; }
DCEOF
  if bpd_neutrality_check "$W/jira-lib-function-kw.sh" >/dev/null 2>&1; then
    echo "FAIL: selftest -- 'function seam_Jira() {' escaped the widened neutrality predicate (L-3)"; sd=1
  else
    echo "PASS: selftest -- 'function seam_Jira() {' is caught by the widened predicate (L-3)"
  fi
  cat > "$W/jira-lib-spaced-mixedcase.sh" <<'DCEOF'
seam_LINEAR ()
{
  :
}
DCEOF
  if bpd_neutrality_check "$W/jira-lib-spaced-mixedcase.sh" >/dev/null 2>&1; then
    echo "FAIL: selftest -- 'seam_LINEAR ()' (spaced parens, upper case) escaped the widened neutrality predicate (L-3)"; sd=1
  else
    echo "PASS: selftest -- 'seam_LINEAR ()' is caught by the widened, case-folded predicate (L-3)"
  fi

  # --- TBG-ROADMAP-CURRENT-SEAM / M-1b: the slashed-path operand fix, proven both ways ----
  # POSITIVE: a real slashed-path operand (`awk … "$dir/BACKLOG.md"`) MUST still be flagged
  # post-fix (this is the shape M-1b exists to keep catching, not to newly relax).
  cat > "$W/scripts/slashed-path-operand.sh" <<'DCEOF'
#!/bin/sh
naive_slashed_read() {
  awk '{print $2}' "$1/BACKLOG.md"
}
DCEOF
  _dc_slash=$(bpd_dc_open_offenders "$W/scripts/slashed-path-operand.sh")
  if [ -n "$_dc_slash" ]; then
    echo "PASS: selftest -- a slashed-path operand (\"\$dir/BACKLOG.md\") is flagged post-fix (M-1b positive)"
  else
    echo "FAIL: selftest -- a slashed-path operand was NOT flagged post-fix (M-1b positive)"; sd=1
  fi
  # NEGATIVE TWIN: quote/slash-adjacent STRING MENTIONS (a search argument, not a read) must NOT be
  # treated as a board-content read (security seat MED-1).
  cat > "$W/scripts/string-mention-grep.sh" <<'DCEOF'
#!/bin/sh
naive_grep_mention() {
  grep -q "BACKLOG.md" f
}
DCEOF
  _dc_ment1=$(bpd_dc_open_offenders "$W/scripts/string-mention-grep.sh")
  if [ -z "$_dc_ment1" ]; then
    echo "PASS: selftest -- a quoted string MENTION (grep -q \"BACKLOG.md\" f) is NOT flagged (M-1b negative twin)"
  else
    echo "FAIL: selftest -- a quoted string MENTION was wrongly flagged as a board-content read (M-1b negative twin)"; sd=1
  fi
  cat > "$W/scripts/string-mention-sed.sh" <<'DCEOF'
#!/bin/sh
naive_sed_mention() {
  sed 's/BACKLOG.md/x/'
}
DCEOF
  _dc_ment2=$(bpd_dc_open_offenders "$W/scripts/string-mention-sed.sh")
  if [ -n "$_dc_ment2" ]; then
    echo "DISCLOSED: selftest -- sed 's/BACKLOG.md/x/' is still flagged (the sed-delimiter '/' is syntactically indistinguishable from a path separator; documented residual over-report, toward RED, in bpd_dc_open_offenders)"
  else
    echo "PASS: selftest -- sed 's/BACKLOG.md/x/' is not flagged (M-1b negative twin)"
  fi

  # NON-VACUITY TWIN (N-2): a SLASHED quoted path on the grep/sed arm is a real read, not a mention --
  # shape (i)'s pre-fix form wrongly dropped it (the escape the security seat named third round).
  cat > "$W/scripts/slashed-path-grepsed.sh" <<'DCEOF'
#!/bin/sh
naive_slashed_grep() {
  grep -c . "$dir/BACKLOG.md"
}
DCEOF
  _dc_n2=$(bpd_dc_open_offenders "$W/scripts/slashed-path-grepsed.sh")
  if [ -n "$_dc_n2" ]; then
    echo "PASS: selftest -- grep -c . \"\$dir/BACKLOG.md\" is flagged (N-2, slashed quoted path on the grep/sed arm)"
  else
    echo "FAIL: selftest -- grep -c . \"\$dir/BACKLOG.md\" was NOT flagged (N-2 escape reproduced)"; sd=1
  fi

  # NON-VACUITY TWIN (L-4): a redirect immediately after the quoted operand is not "another argument"
  # -- shape (ii) wrongly read it as one and dropped a real read.
  cat > "$W/scripts/redirect-followed-operand.sh" <<'DCEOF'
#!/bin/sh
naive_redirect_read() {
  grep -c '^|' "BACKLOG.md" 2>/dev/null
}
DCEOF
  _dc_l4=$(bpd_dc_open_offenders "$W/scripts/redirect-followed-operand.sh")
  if [ -n "$_dc_l4" ]; then
    echo "PASS: selftest -- grep -c '^|' \"BACKLOG.md\" 2>/dev/null is flagged (L-4, redirect-followed operand)"
  else
    echo "FAIL: selftest -- grep -c '^|' \"BACKLOG.md\" 2>/dev/null was NOT flagged (L-4 escape reproduced)"; sd=1
  fi

  # --- TBG-ROADMAP-CURRENT-SEAM / M-2: awk/head/tail/wc/cut/sort operand reads with a BARE-QUOTED
  # trailing operand are REAL reads and must still be flagged, even though the same shape on
  # grep/sed's trailing argument is a legitimate search string (kept dropped, below).
  cat > "$W/scripts/quoted-awk-operand.sh" <<'DCEOF'
#!/bin/sh
quoted_awk_reader() {
  awk '{print}' "BACKLOG.md"
}
DCEOF
  _dc_m2a=$(bpd_dc_open_offenders "$W/scripts/quoted-awk-operand.sh")
  if [ -n "$_dc_m2a" ]; then
    echo "PASS: selftest -- awk '{print}' \"BACKLOG.md\" is flagged (M-2 positive, awk arm)"
  else
    echo "FAIL: selftest -- awk '{print}' \"BACKLOG.md\" was NOT flagged (M-2 positive, awk arm)"; sd=1
  fi
  cat > "$W/scripts/quoted-head-operand.sh" <<'DCEOF'
#!/bin/sh
quoted_head_reader() {
  head -n 5 "BACKLOG.md"
}
DCEOF
  _dc_m2b=$(bpd_dc_open_offenders "$W/scripts/quoted-head-operand.sh")
  if [ -n "$_dc_m2b" ]; then
    echo "PASS: selftest -- head -n 5 \"BACKLOG.md\" is flagged (M-2 positive, head arm)"
  else
    echo "FAIL: selftest -- head -n 5 \"BACKLOG.md\" was NOT flagged (M-2 positive, head arm)"; sd=1
  fi
  # NEGATIVE TWIN: grep's own bare-quoted trailing argument stays a dropped mention, unaffected by
  # the M-2 split.
  _dc_m2c=$(bpd_dc_open_offenders "$W/scripts/string-mention-grep.sh")
  if [ -z "$_dc_m2c" ]; then
    echo "PASS: selftest -- grep -q \"BACKLOG.md\" f is still dropped after the M-2 split (negative twin)"
  else
    echo "FAIL: selftest -- grep -q \"BACKLOG.md\" f was wrongly flagged after the M-2 split"; sd=1
  fi

  # --- TBG-ROADMAP-CURRENT-SEAM / MED-B (completion round): the widened head/tail/wc/cut/sort
  # prefix alternation (keyword prefix `then`/`do`/`if`/`!`/`{`/`(`, and a leading env-assignment)
  # was disclosed by hand trace only, with no RC-backed leg -- proving it here, positive shapes
  # first, then a prose negative twin sharing the same "if ... head" words but NOT the operand
  # shape (something sits between the keyword and the command name, so it can never be a real
  # invocation).
  cat > "$W/scripts/medb-if-head.sh" <<'DCEOF'
#!/bin/sh
medb_if_head() {
  if head -n1 BACKLOG.md >/dev/null; then :; fi
}
DCEOF
  _dc_medb1=$(bpd_dc_open_offenders "$W/scripts/medb-if-head.sh")
  if [ -n "$_dc_medb1" ]; then
    echo "PASS: selftest -- 'if head -n1 BACKLOG.md' is flagged (MED-B positive, if-prefix)"
  else
    echo "FAIL: selftest -- 'if head -n1 BACKLOG.md' was NOT flagged (MED-B positive, if-prefix)"; sd=1
  fi
  cat > "$W/scripts/medb-then-sort.sh" <<'DCEOF'
#!/bin/sh
medb_then_sort() {
  [ -f BACKLOG.md ] && then sort BACKLOG.md
}
DCEOF
  _dc_medb2=$(bpd_dc_open_offenders "$W/scripts/medb-then-sort.sh")
  if [ -n "$_dc_medb2" ]; then
    echo "PASS: selftest -- 'then sort BACKLOG.md' is flagged (MED-B positive, then-prefix)"
  else
    echo "FAIL: selftest -- 'then sort BACKLOG.md' was NOT flagged (MED-B positive, then-prefix)"; sd=1
  fi
  cat > "$W/scripts/medb-env-sort.sh" <<'DCEOF'
#!/bin/sh
medb_env_sort() {
  LC_ALL=C sort BACKLOG.md
}
DCEOF
  _dc_medb3=$(bpd_dc_open_offenders "$W/scripts/medb-env-sort.sh")
  if [ -n "$_dc_medb3" ]; then
    echo "PASS: selftest -- 'LC_ALL=C sort BACKLOG.md' is flagged (MED-B positive, env-assignment prefix)"
  else
    echo "FAIL: selftest -- 'LC_ALL=C sort BACKLOG.md' was NOT flagged (MED-B positive, env-assignment prefix)"; sd=1
  fi
  # NEGATIVE TWIN: genuine prose sharing the same "if"/"head" words, but with other text between
  # the keyword and the command name -- never a real invocation shape. TBG-ROADMAP-CURRENT-SEAM / L-2
  # (security seat): the prior fixture put this prose in a COMMENT, which the comment-exclude filter
  # drops BEFORE the MED-B shape is even tested -- the leg was vacuous (it would pass even if the
  # keyword-prefix predicate had no prose exclusion at all). Moved to a LIVE line (an echo'd string),
  # so the negative twin actually exercises the shape's own "other text between keyword and command
  # name" exclusion.
  cat > "$W/scripts/medb-prose-negative.sh" <<'DCEOF'
#!/bin/sh
medb_prose_negative() {
  echo "if the head of BACKLOG.md changes, rerun this script"
}
DCEOF
  _dc_medb4=$(bpd_dc_open_offenders "$W/scripts/medb-prose-negative.sh")
  if [ -z "$_dc_medb4" ]; then
    echo "PASS: selftest -- 'if the head of BACKLOG.md changes' prose is NOT flagged (MED-B negative twin)"
  else
    echo "FAIL: selftest -- 'if the head of BACKLOG.md changes' prose was wrongly flagged (MED-B negative twin)"; sd=1
  fi

  # --- TBG-ROADMAP-CURRENT-SEAM / B: the widened `;`-terminated seam-call tail ------------
  cat > "$W/scripts/seam-call-semicolon.sh" <<'DCEOF'
#!/bin/sh
seam_semicolon_caller() {
  x=$(seam_rows_in_state in-review); printf '%s\n' "$x"
}
DCEOF
  _dc_semi=$(bpd_dc_seam_offenders "$W/scripts/seam-call-semicolon.sh")
  if [ -n "$_dc_semi" ]; then
    echo "PASS: selftest -- a \`;\`-terminated seam call is detected by bpd_dc_seam_offenders"
  else
    echo "FAIL: selftest -- a \`;\`-terminated seam call was NOT detected"; sd=1
  fi

  # --- TBG-ROADMAP-CURRENT-SEAM / L-4: the REAL find, no BPD_DC_FILES_OVERRIDE (security seat
  # HIGH-1) -- every OTHER leg in this file short-circuits via BPD_DC_FILES_OVERRIDE before the
  # `find` in bpd_dc_files ever runs, so L-4's widening was unobserved by any existing leg. Point
  # the real find at a synthetic tree via BPD_DC_SCAN_HERE/SCRIPTS_DIR/HOOKS_DIR and prove BOTH
  # directions: a nested NON-fixture reader MUST appear, a fixtures/-path decoy MUST NOT.
  mkdir -p "$W/l4tree/conformance/nested/deep"
  mkdir -p "$W/l4tree/conformance/fixtures/nested"
  mkdir -p "$W/l4tree/scripts-empty"
  mkdir -p "$W/l4tree/hooks-empty"
  # NOTE (L-4, review): this fixture is a no-op function -- it proves the FILE LIST bpd_dc_files
  # returns (does `find` reach it?), not the list->gate step (does bpd_derived_consumer_check then
  # FLAG it?); that second step is proven elsewhere, by the BPD_DC_FILES_OVERRIDE legs above.
  cat > "$W/l4tree/conformance/nested/deep/real-consumer.sh" <<'DCEOF'
#!/bin/sh
real_nested_consumer() { :; }
DCEOF
  cat > "$W/l4tree/conformance/fixtures/nested/decoy-fixture.sh" <<'DCEOF'
#!/bin/sh
decoy_fixture_consumer() { :; }
DCEOF
  _dc_l4_out=$(BPD_DC_SCAN_HERE="$W/l4tree/conformance" \
               BPD_DC_SCAN_SCRIPTS_DIR="$W/l4tree/scripts-empty" \
               BPD_DC_SCAN_HOOKS_DIR="$W/l4tree/hooks-empty" \
               bpd_dc_files)
  if printf '%s\n' "$_dc_l4_out" | grep -qF "$W/l4tree/conformance/nested/deep/real-consumer.sh"; then
    echo "PASS: selftest -- the REAL find (no override) recurses into a nested non-fixture consumer (L-4, HIGH-1)"
  else
    echo "FAIL: selftest -- the REAL find did NOT find the nested non-fixture consumer (L-4, HIGH-1)"; sd=1
  fi
  if printf '%s\n' "$_dc_l4_out" | grep -qF "$W/l4tree/conformance/fixtures/nested/decoy-fixture.sh"; then
    echo "FAIL: selftest -- the REAL find wrongly included a fixtures/-path decoy (L-4, HIGH-1)"; sd=1
  else
    echo "PASS: selftest -- the REAL find excludes a fixtures/-path decoy (L-4, HIGH-1)"
  fi

  # --- TBG-ROADMAP-CURRENT-SEAM / H-2 (security seat HIGH-2): the env-bypass class, closed.
  _bpd_self="$HERE/board-parser-drift.sh"
  # (a) PRODUCTION refusal: the real script (no --selftest), with an override env var set, must
  # REFUSE (non-zero rc) and must NOT print the derived-consumer OK line.
  _dc_h2_rc=0
  _dc_h2_out=$(env BPD_DC_FILES_OVERRIDE=/dev/null sh "$_bpd_self" 2>&1) || _dc_h2_rc=$?
  if [ "$_dc_h2_rc" -ne 0 ] && ! printf '%s\n' "$_dc_h2_out" | grep -qF "OK -- no board-governance consumer"; then
    echo "PASS: selftest -- BPD_DC_FILES_OVERRIDE=/dev/null in PRODUCTION refuses (rc $_dc_h2_rc), never prints the OK line (H-2a)"
  else
    echo "FAIL: selftest -- BPD_DC_FILES_OVERRIDE=/dev/null in production did NOT refuse cleanly (rc=$_dc_h2_rc)"
    printf '%s\n' "$_dc_h2_out" | sed 's/^/    /'; sd=1
  fi
  _dc_h2_rc2=0
  _dc_h2_out2=$(env BPD_DC_SCAN_HERE=/dev/null sh "$_bpd_self" 2>&1) || _dc_h2_rc2=$?
  if [ "$_dc_h2_rc2" -ne 0 ] && ! printf '%s\n' "$_dc_h2_out2" | grep -qF "OK -- no board-governance consumer"; then
    echo "PASS: selftest -- BPD_DC_SCAN_HERE set in PRODUCTION refuses too (rc $_dc_h2_rc2) (H-2a)"
  else
    echo "FAIL: selftest -- BPD_DC_SCAN_HERE set in production did NOT refuse cleanly (rc=$_dc_h2_rc2)"
    printf '%s\n' "$_dc_h2_out2" | sed 's/^/    /'; sd=1
  fi
  # (b) fail CLOSED on an empty scanned-file list, called directly (still honored -- this is the
  # SELFTEST process, calling the function in-process, not the production dispatch path (a) guards).
  _dc_nl='
'
  _dc_h2_empty_rc=0
  _dc_h2_empty_out=$(BPD_DC_FILES_OVERRIDE="$_dc_nl" bpd_derived_consumer_check 2>&1) || _dc_h2_empty_rc=$?
  if [ "$_dc_h2_empty_rc" -ne 0 ] && printf '%s\n' "$_dc_h2_empty_out" | grep -qF "EMPTY-SCAN"; then
    echo "PASS: selftest -- an empty scanned-file list fails closed (rc $_dc_h2_empty_rc, EMPTY-SCAN named) (H-2b)"
  else
    echo "FAIL: selftest -- an empty scanned-file list did NOT fail closed (rc=$_dc_h2_empty_rc)"
    printf '%s\n' "$_dc_h2_empty_out" | sed 's/^/    /'; sd=1
  fi

  # --- TBG-ROADMAP-CURRENT-SEAM / H-1 (security seat, second round), N-1 (security seat, THIRD
  # round -- still not discharged): the second round's allowlist was an UNANCHORED substring match
  # (`grep -v -E "$_rc_allow"`), so any COMPOUND line, a TRAILING COMMENT, or an allowlisted phrase
  # appearing anywhere on an otherwise-live line laundered a real read past the scan: `[ -r "$_rc_bl"
  # ] && cat "$_rc_bl"`, `sort -r "$_rc_bl"`, `cat "$_rc_bl"  # see backlog-lib.sh`, an `if
  # section_present ...; then cat "$_rc_bl"; fi` compound, and (on the narrow `$2` scan) the
  # command-name allowlist itself let `git show "HEAD:$2"`, `_x="$2"; cat "$_x"`, a `< "$2"` redirect,
  # or an operand on the awk-program's own closing-quote line all escape. Rebuilt WHOLE-LINE
  # ANCHORED: every permitted form below is matched against the ENTIRE line (`^[0-9]+:<exact text>$`,
  # never a substring), so a compound statement, a trailing comment, or an allowlisted phrase buried
  # inside a longer live line no longer launders anything -- the line must equal a permitted form
  # exactly, or it is an offender. (The prior round's claim that this shape carries "no command-name
  # allowlist to escape around at all" was true only of the WIDE scan; the NARROW scan below still
  # carried one, which is exactly what N-1 exploited -- fixed by removing it, see below.)
  bpd_rc_seam_offenders() {  # <file> -> offending "<line>:<text>" lines, or empty
    _rc_allow='^[0-9]+:  _rc_bl="\$2"$'
    _rc_allow="$_rc_allow"'|^[0-9]+:  if \[ ! -r "\$_rc_bl" \]; then$'
    _rc_allow="$_rc_allow"'|^[0-9]+:    if section_present "\$_rc_bl" Done; then$'
    _rc_allow="$_rc_allow"'|^[0-9]+:      cells_in_section "\$_rc_bl" Done 1 > "\$_rc_donefile"$'
    _rc_allow="$_rc_allow"'|^[0-9]+:  LC_ALL=C awk -v roadmap="\$1" -v backlog="\$2" -v armed="\$3" \\$'
    _rc_allow="$_rc_allow"'|^[0-9]+:rc_awk\(\) \{  # <roadmap-path> <backlog-path> <armed 0\|1>$'                # L130
    _rc_allow="$_rc_allow"'|^[0-9]+:\. "\$\(dirname "\$0"\)/backlog-lib\.sh"$'                                  # the source line (L113)
    _rc_allow="$_rc_allow"'|^[0-9]+:                  backlog " ## Done carries: " squeeze\(done1\[j\]\)$'      # PASS-1 print (L236)
    _rc_allow="$_rc_allow"'|^[0-9]+:      else if \(bstat < 0\)   why = "the board \(" backlog "\) could not be read"$'
    _rc_allow="$_rc_allow"'|^[0-9]+:      else if \(!seen_done\)  why = "the board \(" backlog "\) has no `## Done` section"$'
    _rc_allow="$_rc_allow"'|^[0-9]+:      else if \(ndone == 0\)  why = "the `## Done` section of the board \(" backlog "\) contains no rows"$'
    _rc_allow="$_rc_allow"'|^[0-9]+:  rc_awk ROADMAP\.md BACKLOG\.md "\$_armed" \|\| _rc=\$\?$'
    _rc_allow="$_rc_allow"'|^[0-9]+:.*rc_put "[^"]*" "BACKLOG\.md" ".*"$'                                        # selftest fixture writer (rc_board + inline rc_put)
    _rc_allow="$_rc_allow"'|^[0-9]+:  rc_says  "and NAMES the board side too" "BACKLOG\.md ## Done carries:" "\$W/stale"$'
    # Whole-file: any live line naming `_rc_bl` / `backlog` / `BACKLOG.md`, UNLESS the ENTIRE line
    # equals one of the permitted forms above. `.*` between the token and the read (never `[^|]*`) so
    # a `|` byte cannot break the DETECTION; the allowlist is anchored (`^...$`) so a `|` byte, a
    # trailing comment, or a compound statement on the same line cannot break the EXEMPTION either.
    _rc_wide=$(grep -n -E '_rc_bl|(^|[^A-Za-z0-9_])backlog([^A-Za-z0-9_]|$)|BACKLOG\.md' "$1" 2>/dev/null \
      | grep -v -E '^[0-9]+:[[:space:]]*#' \
      | grep -v -E "$_rc_allow") || true
    # SCOPE-RESTRICTED to rc_awk()'s own body: a bare `$2` is rc_awk's positional parameter (the
    # board path, before `_rc_bl="$2"` names it) -- but `$2`/`$1` are reused generically as ordinary
    # positional params all over this file's OTHER functions (selftest helpers, rc_says/rc_denies),
    # so a file-wide `$2` match is a false-positive class of its own; restricted to rc_awk's body,
    # where `$2` unambiguously means "the board path", it is not. N-1: NO command-name allowlist here
    # any more -- ANY live line in the body that mentions `$2` at all (quoted or bare) is an offender
    # unless the WHOLE line is one of the permitted forms above; a command-name list is exactly what
    # let `git show "HEAD:$2"`, `_x="$2"; cat "$_x"`, a bare `< "$2"` redirect, and an operand on the
    # awk-program's closing-quote line all escape the old scan.
    _rc_fnbody=$(sed -n '/^rc_awk() {/,/^}/p' "$1" 2>/dev/null)
    _rc_narrow=$(printf '%s\n' "$_rc_fnbody" \
      | grep -n -E '\$2' \
      | grep -v -E '^[0-9]+:[[:space:]]*#' \
      | grep -v -E "$_rc_allow") || true
    printf '%s\n%s\n' "$_rc_wide" "$_rc_narrow" | grep -v '^$' || true
  }
  _rc_seam_file="$HERE/roadmap-current.sh"
  if [ -f "$_rc_seam_file" ]; then
    _dc_rc_raw=$(bpd_rc_seam_offenders "$_rc_seam_file") || true
    if [ -z "$_dc_rc_raw" ]; then
      echo "PASS: selftest -- roadmap-current.sh carries NO raw board-operand read outside the allowlist (H-1 absence leg)"
    else
      echo "FAIL: selftest -- roadmap-current.sh carries a raw board-operand read outside section_present/cells_in_section (H-1 absence leg tripped):"
      printf '%s\n' "$_dc_rc_raw" | sed 's/^/    /'
      sd=1
    fi
    # NON-VACUITY TWIN (H-1): splice the pre-refactor PASS 1 read (`r = (getline ln < backlog)`, the
    # 19e6516-era shape the old MED-2 leg was supposed to catch and did not) into a SCRATCH COPY and
    # assert the leg REDS on it -- proving this leg is not vacuous in the positive direction either.
    _rc_scratch="$W/roadmap-current-preref.sh"
    awk '{ print; if ($0 ~ /^rc_awk\(\) \{/) print "  r = (getline ln < backlog)" }' "$_rc_seam_file" > "$_rc_scratch"
    _dc_rc_twin=$(bpd_rc_seam_offenders "$_rc_scratch") || true
    if [ -n "$_dc_rc_twin" ]; then
      echo "PASS: selftest -- the pre-refactor board getline, spliced into a scratch copy, REDS the H-1 leg (non-vacuity twin, positive)"
    else
      echo "FAIL: selftest -- the pre-refactor board getline did NOT red the H-1 leg on a scratch copy (non-vacuity twin FAILED -- the leg is vacuous)"; sd=1
    fi

    # MORE NON-VACUITY TWINS (H-1, second security round): each is the EXACT shape the security
    # seat named as escaping the first rebuild -- spliced into rc_awk()'s own body of a scratch
    # copy, one splice per twin, each must RED on its own.
    _rc_twin_i=0
    for _rc_twin_line in \
      'awk -F"|" "{print $1}" "$_rc_bl"' \
      'cut -d"|" -f1 "$_rc_bl"' \
      'while IFS= read -r l; do :; done < "$_rc_bl"' \
      'awk "{print}" $_rc_bl' \
      'git show HEAD:BACKLOG.md' \
      '[ -r "$_rc_bl" ] && cat "$_rc_bl"' \
      'cat "$_rc_bl"  # see backlog-lib.sh' \
      'git show "HEAD:$2"' \
      '_x="$2"; cat "$_x"'
    do
      _rc_twin_i=$((_rc_twin_i + 1))
      _rc_twinN="$W/roadmap-current-twin$_rc_twin_i.sh"
      awk -v ins="  $_rc_twin_line" '{ print; if ($0 ~ /^rc_awk\(\) \{/) print ins }' "$_rc_seam_file" > "$_rc_twinN"
      _dc_rc_twinN=$(bpd_rc_seam_offenders "$_rc_twinN") || true
      if [ -n "$_dc_rc_twinN" ]; then
        echo "PASS: selftest -- twin $_rc_twin_i ($_rc_twin_line) REDS the H-1 leg (non-vacuity, second round)"
      else
        echo "FAIL: selftest -- twin $_rc_twin_i ($_rc_twin_line) did NOT red the H-1 leg (non-vacuity twin FAILED -- the leg is vacuous on this shape)"; sd=1
      fi
    done
  else
    echo "FAIL: selftest -- roadmap-current.sh not found at $_rc_seam_file (H-1 absence leg cannot run)"; sd=1
  fi

  rm -rf "$W"; trap - EXIT
  [ "$sd" -eq 0 ] && { echo "OK: board-parser-drift selftest"; exit 0; } || { echo "FAIL: board-parser-drift selftest"; exit 1; }
}

case "${1:-}" in
  --selftest) selftest ;;
  "")
    # TBG-ROADMAP-CURRENT-SEAM / H-2a (security seat HIGH-2): BPD_DC_FILES_OVERRIDE/BPD_DC_SCAN_* are
    # selftest-only substitutes for the real scan (see bpd_dc_files' header comment). Honoring them in
    # PRODUCTION let a caller substitute a synthetic -- possibly EMPTY -- scan for the real tree and
    # still get the derived-consumer OK line (measured: `env BPD_DC_FILES_OVERRIDE=/dev/null sh
    # conformance/board-parser-drift.sh` printed OK over a zero-file scan). Refuse outright, never
    # silently ignore-and-continue (that would still let the override change behaviour unexamined).
    for _bpd_env_v in BPD_DC_FILES_OVERRIDE BPD_DC_SCAN_HERE BPD_DC_SCAN_SCRIPTS_DIR BPD_DC_SCAN_HOOKS_DIR; do
      eval "_bpd_env_vv=\${$_bpd_env_v:-}"
      if [ -n "$_bpd_env_vv" ]; then
        echo "board-parser-drift: REFUSED -- $_bpd_env_v is set outside --selftest; this override is selftest-only (it substitutes a synthetic scan for the real tree) and is refused in production, never silently honored" >&2
        exit 1
      fi
    done
    if bpd_check "$LIB" "$BOARD_CLAIM" "$CORPUS"; then rc=0; else rc=$?; fi
    if [ "$rc" -eq 0 ]; then
      echo "board-parser-drift: OK -- cell()/col_index() and bc_cell/bc_col_index agree on the corpus"
    else
      echo "board-parser-drift: FAIL -- divergence(s) above between the lib parser and board-claim's copy"
    fi
    if bpd_enum_check "$LIB" "$BOARD_CLAIM" "$META_CONTROL" "$BACKLOG_CURRENT"; then enum_rc=0; else enum_rc=$?; fi
    if [ "$enum_rc" -eq 0 ]; then
      echo "board-parser-drift: OK -- no raw awk -F'|' splitter found outside the allowlisted parser/write functions"
    else
      echo "board-parser-drift: FAIL -- enumeration offender(s) above (a new naive consumer?)"
    fi
    if bpd_derived_consumer_check; then dc_rc=0; else dc_rc=$?; fi
    if [ "$dc_rc" -eq 0 ]; then
      echo "board-parser-drift: OK -- no board-governance consumer bypasses the seam (derived-consumer assertion; ${_dc_last_scanned_count:-?} file(s) scanned)"
    else
      echo "board-parser-drift: FAIL -- derived-consumer offender(s) above (a seam bypass?)"
    fi
    if bpd_neutrality_check; then nt_rc=0; else nt_rc=$?; fi
    if [ "$nt_rc" -eq 0 ]; then
      echo "board-parser-drift: OK -- the seam's read surface names no tracker (neutrality)"
    else
      echo "board-parser-drift: FAIL -- neutrality offender(s) above"
    fi
    [ "$rc" -eq 0 ] && [ "$enum_rc" -eq 0 ] && [ "$dc_rc" -eq 0 ] && [ "$nt_rc" -eq 0 ] && exit 0
    exit 1
    ;;
  *) usage; exit 2 ;;
esac
