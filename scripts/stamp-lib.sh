#!/bin/sh
# stamp-lib.sh — the kit's stamping functions, shared. SOURCED, never run.
#
# Who sources it: scripts/incept.sh (at the very top, from incept's own resolved directory, never the
# cwd) and, from SWAS-1009 PR 2, scripts/adopt.sh (the kit's own copy, never a file from the target).
# Why it exists: incept runs top to bottom in the cwd and defines its functions between top-level
# statements, so it cannot be sourced. These functions moved here, with no change in behaviour, so
# adopt reuses incept's stamping code instead of keeping a copy that nothing locks.
#
# DEFINITIONS ONLY: this file defines functions, plus the one constant PIPELINE_ORIGIN_MARKER, and runs
# nothing when sourced. POSIX sh, dash-clean, safe under `set -eu`. No global IFS change and no
# one-line case/esac. The functions use relative paths, so the caller sets the cwd.
# What it changes: nothing by itself; it defines functions that callers use to write the files they name.
# Guardrails: definitions only; POSIX sh; the callers keep every write condition. Caller name: the optional variable STAMP_CALLER (default incept) names the caller in the mktemp-failure message.

# STAMP_CALLER: the name the mktemp-failure message uses for the caller. Unset means incept, whose text is
# the original, byte for byte; scripts/adopt.sh sets it to adopt before it calls any function here.
_stamp_tmp_fail() {  # <dir> — a failed mktemp STOPS the caller (exit 1); there is no fallback name (SWAS-754)
  _stf_c=${STAMP_CALLER:-incept}
  if [ "$_stf_c" = incept ]; then
    printf '%s\n' "incept: could not create a temporary file in $1 (mktemp failed), so incept stopped part-way and this directory is half-incepted; check the disk has free space and the directory is writable, then re-export the kit into a fresh directory and run 'sh scripts/incept.sh' there (in an existing repository, restore it from git instead and rerun)" >&2
  else
    printf '%s\n' "$_stf_c: could not create a temporary file in $1 (mktemp failed), so $_stf_c stopped part-way; check the disk has free space and the directory is writable, then rerun" >&2
  fi
  exit 1
}
# escape a string for safe use as a sed REPLACEMENT. Escapes & / \ AND the `#` delimiter every `sedi`
# stamp below uses: without `#`, a `#`-bearing value terminates the `s#..#..#` program and the trailing
# text is read as sed COMMANDS (e.g. `w <path>` = arbitrary file write). Escaping `#` closes EVERY
# `#`-delimited stamp sink at once, not just one call site (T9 — defense in depth with --stack validation).
esc() { printf '%s' "$1" | sed 's/[&/#\\]/\\&/g'; }
# portable in-place sed: last positional arg is the FILE (POSIX; no bash ${@: -1})
sedi() {
  last=
  for last in "$@"; do :; done
  sed -i.bak "$@" && rm -f "${last}.bak"
}

# --- DB-archetype curation (KW3): the `kit:db-backed` CI region strip ---
strip_db_region() {  # FILE — delete the `# >>> kit:db-backed` … `# <<< kit:db-backed` region in-place; no-op if absent
  [ -f "$1" ] || return 0
  # GUARD (Security-Medium): a `sed '/start/,/end/d'` range with NO closing match deletes to EOF — which
  # would silently wipe EVERY gate below the region (sast/secret/agent-trace/provenance), leaving a
  # gateless-but-green CI. Only strip when BOTH markers are present; otherwise no-op, loudly.
  grep -q '# >>> kit:db-backed' "$1" || return 0   # no opening marker — nothing to strip
  grep -q '# <<< kit:db-backed' "$1" || { echo "warn: kit:db-backed closing marker missing in $1 — leaving CI untouched (refusing an open-ended range that would wipe gates to EOF)" >&2; return 0; }
  sed '/# >>> kit:db-backed/,/# <<< kit:db-backed/d' "$1" > "$1.kwtmp" && mv "$1.kwtmp" "$1"
}

# CP7R5-GATE-AUTHORITY §4 — the RATIFIED provenance mechanism (option P2): stamp an ORIGIN MARKER into
# the CI pipeline incept INSTALLS. It lets conformance/verify-enforced-wired.sh tell DRIFT (the kit
# installed this pipeline and someone stripped a required step) apart from an UNMET DOCUMENTED MERGE
# OBLIGATION (a brownfield adopter owns their pipeline and merges the gate-ids by hand, exactly as
# docs/adoption/brownfield.md instructs). Nothing in an adopter tree recorded which of the two it was:
# .kit-manifest lists the EXPORT's files (workflows are export-ignored), never an installed path.
# Provenance written by the ACT of installation travels IN the
# artifact it describes, so it cannot go stale relative to that artifact and survives a rename.
#
# TWO PROPERTIES ARE LOAD-BEARING — both locked by conformance/pipeline-origin.sh:
#  1. NON-COLLISION. The marker must match NEITHER kit-own ERE incept passes to install_pipeline
#     ('Kit-own CI|Sparkwright', 'Sparkwright'). If it did, installing it would silently flip a LATER
#     cp_kit_replace from PRESERVE to OVERWRITE and clobber an adopter's edited CI.
#  2. ONLY STAMP A FILE WE WROTE. cp_kit_replace returns 0 whether it copied or preserved, so a blind
#     post-call prepend would stamp a brownfield-PRESERVED adopter pipeline as kit-emitted — precisely
#     the false-FAIL class this design exists to remove. The caller (incept's install_pipeline) mirrors
#     the write condition up front and calls pipeline_origin_stamp only on a file it wrote.
# The marker goes at the TOP of the file, not inside it: curate_db_backed -> strip_db_region runs AFTER
# the §5 wiring block and deletes the bounded `# >>> kit:db-backed` … `# <<< kit:db-backed` region, so a
# marker placed inside that region would vanish on a --no-db incept.
# HONEST CEILING: an adopter can delete this line. Under §4 that is an accepted self-assertion of
# ownership — it downgrades enforcement to a DISCLOSED N/A, never to a silent pass.
PIPELINE_ORIGIN_MARKER='# kit-pipeline-origin: emitted'
pipeline_origin_stamp() {  # <file> — prepend the origin marker as line 1; idempotent, never double-stamps
  if ! grep -qF "$PIPELINE_ORIGIN_MARKER" "$1" 2>/dev/null; then   # idempotent: never double-stamp
    # Unpredictable temp name beside the target (same idiom as codeowners_inert) — avoids following
    # a pre-placed symlink at a predictable path. A failed mktemp STOPS the write: there is no
    # fallback name, because a guessable name brings that symlink back (SWAS-754).
    _ip_tmp=$(mktemp "$(dirname "$1")/.kitorigin.XXXXXX" 2>/dev/null) || { _stamp_tmp_fail "$(dirname "$1")"; }
    { printf '%s\n' "$PIPELINE_ORIGIN_MARKER"; cat "$1"; } > "$_ip_tmp" && mv "$_ip_tmp" "$1"
  fi
}

warn_codeowners_active_placeholder() {  # <dst> — G11: warn ONLY on an ACTIVE (uncommented) @your-org rule
  if [ -f "$1" ] && grep -Eq '^[[:space:]]*[^#].*@your-org' "$1" 2>/dev/null; then
    echo "warning: $1 has an ACTIVE @your-org/* placeholder — replace it with REAL teams/users" >&2
    echo "         BEFORE enabling branch protection (require_code_owner_reviews), or that merge gate" >&2
    echo "         will block (the placeholder owners don't exist). See docs/operations/review-lane.md." >&2
  fi
}

# K3 (CP-7 recert Slice 2): incept must ship an INERT CODEOWNERS so require_code_owner_reviews cannot
# silently block every merge. OWNER is free text ("who owns the why"); a blind substitution is INVALID
# CODEOWNERS syntax, so seed the `*` rule ONLY when OWNER is an explicit @handle (@user or @org/team).
# A bare name / free text stays fully inert — seeding a wrong/non-existent owner would re-introduce the
# very block K3 fixes. Honest ceiling: incept cannot confirm the handle exists (no guaranteed network).
codeowners_seed_handle() {  # <owner> — echoes the normalized @handle iff handle-shaped, else nothing
  case "$1" in
    '@'*) : ;;
    *) return 0 ;;
  esac
  _csh_h=${1#@}
  printf '%s' "$_csh_h" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9-]{0,38}(/[A-Za-z0-9._-]+)?$' || return 0
  printf '@%s' "$_csh_h"
}
codeowners_inert() {  # <file> <owner> — inert transform: comment every rule, prepend the warning header and an optional @handle seed
  _ic_seed=$(codeowners_seed_handle "$2")
  # Comment every active ownership rule: ANY line whose first non-blank char is not '#' (a CODEOWNERS rule,
  # whatever its leading glyph — `*`, `/`, or a bare-word path a future profile might use). Header comments
  # and blank lines are untouched. (dual-review Minor: don't couple to the current `*`/`/` rule shapes.)
  sedi 's/^\([[:space:]]*[^#[:space:]]\)/# \1/' "$1"
  # Unpredictable temp name (mktemp, O_EXCL) beside the target — avoids following a pre-placed symlink
  # at a predictable path (dual-review Low). A failed mktemp STOPS the write: there is no pid-name
  # fallback, because a guessable name brings that symlink back (SWAS-754).
  _ic_tmp=$(mktemp "$(dirname "$1")/.codeowners.XXXXXX" 2>/dev/null) || { _stamp_tmp_fail "$(dirname "$1")"; }
  {
    echo "# EDIT before enabling require_code_owner_reviews: replace the commented @your-org/*"
    echo "# placeholder teams below with REAL teams/users, then uncomment. An active @your-org"
    echo "# owner does not exist and would block EVERY merge (K3 / DEVELOPMENT-PROCESS.md §12)."
    if [ -n "$_ic_seed" ]; then
      _ic_flag=--intent-owner; [ "${STAMP_CALLER:-incept}" = incept ] || _ic_flag=--owner   # the caller's own flag name; incept's text is unchanged
      echo "# Seeded from $_ic_flag; confirm it is a real VCS user/team and add co-reviewers."
      echo "*            ${_ic_seed}"
    fi
    echo ""
    cat "$1"
  } > "$_ic_tmp" && mv "$_ic_tmp" "$1"
}

# REQUIRED-CHECKS.md — replace ONLY the pristine `<your-check-name>` placeholder line with the declared
# contexts (a brownfield file with real entries is never touched). Args: FILE, the `ci` line, the
# tracker-board-gates line ('' for none), the solo-go-bound line ('' for none; incept passes '').
required_checks_fill() {  # <file> <ci> <tbg> <solo>
  awk -v ci="$2" -v tbg="$3" -v solo="${4:-}" '$0=="<your-check-name>"{print ci; print "control-plane-ratification"; print "backlog-presence"; print "ceremony-binding"; print "loop-state"; if (tbg != "") print tbg; if (solo != "") print solo; next}1' "$1" > "$1.tmp" && mv "$1.tmp" "$1" \
    || { rm -f "$1.tmp"; echo "${STAMP_CALLER:-incept}: could not fill $1 — declare ci, control-plane-ratification, backlog-presence, ceremony-binding, loop-state${3:+, $3} by hand (inception-done will name them)" >&2; }
}

# TBG-TRACKER-CONF: write .kit/tracker.conf for the jira backend, per design §5. `--existing` (F1's jira
# arm) writes an EMPTY state map plus a --discover instruction instead of the greenfield identity map —
# the adopter's Jira statuses are unknown until they run the live discovery leg. The conf is validated
# against the SAME grammar tracker-contract.sh reads (F4 — never a second parser), so both arms are
# written to satisfy scripts/tracker-conf.sh exactly. The caller owns the exists check, the mkdir and
# the notes. Optional URL and PROJECT replace the two placeholder lines (incept passes none).
tracker_conf_write() {  # <dest> <existing 0|1> [<url> <project>]
  if [ "$2" -eq 1 ]; then
    _tcw_body_existing > "$1"
  else
    _tcw_body_new > "$1"
  fi
  [ -z "${3:-}" ] || sedi "s#^base_url=.*#base_url=$(esc "$3")#" "$1"
  [ -z "${4:-}" ] || sedi "s#^project=.*#project=$(esc "$4")#" "$1"
}
# The two bodies, one printf each, one single-quoted argument per line (no expansion; an apostrophe is '\'').
_tcw_body_existing() {  # prints the --existing body (an EMPTY state map plus the discovery note)
    printf '%s\n' \
      '# .kit/tracker.conf — stamped by `incept --backlog jira --existing`. Fail-closed key=value grammar;' \
      '# see docs/architecture/2026-09-19-tracker-backed-governance-design.md §5, or `sh scripts/' \
      '# tracker-conf.sh <this-file>` to validate. Credentials are ENV ONLY: KIT_TRACKER_USER /' \
      '# KIT_TRACKER_TOKEN (JIRA_EMAIL/JIRA_TOKEN honoured as aliases) — never stamp a token here.' \
      'version=1' \
      'backend=jira' \
      'base_url=https://your-site.example.invalid' \
      'flavour=cloud' \
      'auth=basic' \
      'project=PROJ' \
      'list_cap=200' \
      '# --existing: the state map below is intentionally EMPTY. Set KIT_TRACKER_USER/KIT_TRACKER_TOKEN,' \
      '# then run `sh conformance/tracker-contract.sh --discover` to print this instance'\''s id<->name state' \
      '# map, and add one `state.<kit-state>=<tracker-status>` line per §4.1 kit state (the FIRST line for' \
      '# a given kit state is the `move` target). field.<name>=customfield_NNNNN|label:<prefix>|none lines' \
      '# follow the same discovery step.' \
      '# create.issuetype is the issue type `board create` makes. Field ids are PER ISSUE TYPE on' \
      '# team-managed projects: map field.size/field.risk to THIS type'\''s ids, printed by' \
      '# `sh conformance/tracker-contract.sh --fields`.' \
      '# A field your Jira REQUIRES on create (it will be listed under REQUIRED by --fields) needs a line here:' \
      '# create.<fieldId>=<value> (a team default) or create.<fieldId>=prompt (the agent supplies it per card).' \
      'create.issuetype=Task'
}
_tcw_body_new() {  # prints the greenfield body (the identity state map)
    printf '%s\n' \
      '# .kit/tracker.conf — stamped by `incept --backlog jira`. Fail-closed key=value grammar; see' \
      '# docs/architecture/2026-09-19-tracker-backed-governance-design.md §5, or `sh scripts/' \
      '# tracker-conf.sh <this-file>` to validate. Credentials are ENV ONLY: KIT_TRACKER_USER /' \
      '# KIT_TRACKER_TOKEN (JIRA_EMAIL/JIRA_TOKEN honoured as aliases) — never stamp a token here.' \
      '# Edit base_url/project for your instance, then verify with `sh conformance/tracker-contract.sh`.' \
      'version=1' \
      'backend=jira' \
      'base_url=https://your-site.example.invalid' \
      'flavour=cloud' \
      'auth=basic' \
      'project=PROJ' \
      'state.backlog=Backlog' \
      'state.ready=Ready' \
      'state.in-progress=In Progress' \
      'state.in-review=In Review' \
      'state.released=Released' \
      'state.done=Done' \
      'state.blocked=Blocked' \
      'field.size=label:size' \
      'field.risk=label:risk' \
      'list_cap=200' \
      '# create.issuetype is the issue type `board create` makes. Field ids are PER ISSUE TYPE on' \
      '# team-managed projects: map field.size/field.risk to THIS type'\''s ids, printed by' \
      '# `sh conformance/tracker-contract.sh --fields`.' \
      '# A field your Jira REQUIRES on create (it will be listed under REQUIRED by --fields) needs a line here:' \
      '# create.<fieldId>=<value> (a team default) or create.<fieldId>=prompt (the agent supplies it per card).' \
      'create.issuetype=Task'
}

# The board-governance waiver row, printed as ONE line (no trailing newline is needed: a command
# substitution strips it). A stamp is not a ratification: the two bracketed cells are placeholders on
# purpose, so `waivers-valid.sh --active board-governance` refuses them until a person fills both.
# Returns 1 and prints nothing for a backend token holding `|` (the row IS a markdown table row, so a
# pipe would forge extra columns, security S-L4); the caller refuses with its own message first.
board_governance_row() {  # <backend> <date>
  case "$1" in
    *'|'*) return 1 ;;
  esac
  # +90 days: GNU then BSD. If NEITHER parses (a date(1) with neither dialect), stamp the opening
  # date — a same-day expiry is still refused for its placeholders, so the fallback cannot
  # accidentally widen anything; it only makes the row shorter-lived.
  _bgr_exp=$(date -u -d "$2 +90 days" +%Y-%m-%d 2>/dev/null \
    || date -u -j -v+90d -f %Y-%m-%d "$2" +%Y-%m-%d 2>/dev/null) || _bgr_exp="$2"
  [ -n "$_bgr_exp" ] || _bgr_exp="$2"
  # SWAS-203: the Remediation cell names a cure that exists today. Jira has a kit adapter (the bind);
  # every other backend has none, so its way out is its own adapter or BACKLOG.md. No pipe, no
  # "when released": the validator reads this cell as a plan, and a plan must not wait on a release.
  case "$1" in
    jira) _bgr_fix="Bind tracker-board-gates once branch protection is available, or move the board to BACKLOG.md" ;;
    *) _bgr_fix="Adopt a kit adapter for '$1', or move the board to BACKLOG.md" ;;
  esac
  # printf, NOT `awk -v` (security S-L4): awk -v runs ESCAPE PROCESSING over the assigned value.
  printf '| board-governance | The kit reads BACKLOG.md only; board-bound gates cannot read '"'"'%s'"'"' | [owner] | %s | %s | %s | [security-owner] |\n' "$1" "$2" "$_bgr_exp" "$_bgr_fix"
}

strip_template_banner() {  # <file> — drop the whole `> **Template.**` blockquote run + one blank after
  [ -f "$1" ] || return 0
  grep -q '^> \*\*Template\.\*\*' "$1" || return 0
  awk '
    /^> \*\*Template\.\*\*/ { skip = 1; next }
    skip == 1 && /^>/       { next }
    skip == 1 && $0 == ""   { skip = 0; next }
    { skip = 0; print }
  ' "$1" > "$1.b3tmp" && mv "$1.b3tmp" "$1"
}
