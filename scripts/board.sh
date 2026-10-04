#!/bin/sh
# board.sh — the MCP-neutral write port (TBG-BOARD-VERBS, design
# docs/architecture/2026-09-20-tbg-board-verbs-design.md; design of record §4.4). Lets an agent
# move a card on ANY backend with no MCP harness: on `md` an agent hand-edits BACKLOG.md; a
# hosted tracker has no hand-edit, so without these verbs only an MCP harness could move a card.
#
#   sh scripts/board.sh claim   <ROW-ID> [--branch <name>]
#   sh scripts/board.sh release <ROW-ID> [--stale]
#   sh scripts/board.sh move    <ROW-ID> <state>
#   sh scripts/board.sh create  --title <text> [--size <s>] [--risk <r>] [--type <issuetype>]
#                               [--parent <KEY>] [--description <text>] [--field <token>=<value>]...
#   sh scripts/board.sh --selftest
#
# `create` also fills the fields the PROJECT requires of that type (adapter `required-fields`): a value comes from
#   `--field <id>=<value>` or the conf's `create.<id>=<value>`; `create.<id>=prompt` means "ask per card" (refused
#   without --field). Anything unfilled is refused BEFORE any POST, every miss in one run, naming the exact conf line
#   to add. The grammar is tracker-conf.sh's; which keys are writable is the adapter's `writable-create-keys`.
#   A transition the tracker refuses (adapter rc 5) shows the adapter's sentence verbatim; the kit diagnoses, it never
#   fills a transition screen.
# `create` makes the issue type `--type`, else `create.issuetype` in .kit/tracker.conf, else Task. Size and
#   Risk go through the SAME `field.size`/`field.risk` mapping the readers use (customfield_N select/string,
#   or label:<prefix>), checked against that type's create-meta BEFORE any POST. Acceptance criteria ride
#   `--description`: `create` writes no separate `field.acceptance` custom field (fill that by hand).
#
# EXIT: 0 the verb succeeded AND its effect was PROVEN by a post-read · 1 the tracker-side write
#   (or its proof) failed — for claim/release this is reported by board-claim.sh's claim-ref/
#   release-ref, whose own compensation already ran (S-5) · 2 usage / undeclared or unsupported
#   backend / missing .kit/tracker.conf keys · 3 claim: ALREADY CLAIMED (forwarded unchanged).
#
# What it changes: on `md`, claim/release DELEGATE WHOLESALE to board-claim.sh's own claim/
#   release (which already sequence the git-ref lock with the BACKLOG.md row move) — this file
#   adds no second md write path. On a tracker backend (today: jira), claim/release compose
#   board-claim.sh's `claim-ref`/`release-ref` (the git ref IS the lock, on every backend, S-5)
#   with a tracker-side write via tracker-jira.sh's assign-self/transition, run as claim-ref's/
#   release-ref's `--then` step so a tracker-side failure is COMPENSATED (the ref is undone) —
#   this file never pushes a claim ref itself. `move` and `create` write ONLY to a tracker
#   backend (no md equivalent exists — an md board is hand-edited, by design). Every verb's
#   effect is PROVEN by a post-read (get-issue) before it reports success; a verb that cannot
#   prove its own effect exits non-zero.
# Guardrails: writes use the credential tracker-jira.sh's jira_curl_authed already resolves —
#   the developer's own KIT_TRACKER_USER/TOKEN, never a CI-scoped token (A5; this file sets no
#   credential of its own, so it inherits that boundary rather than re-deciding it). `move`
#   accepts only a state name that is DECLARED in `.kit/tracker.conf`'s `state.*` map (never a
#   raw tracker string typed at the CLI) and tracker-jira.sh resolves the actual transition by
#   its `to.id` (S-8), never by re-matching a name a second time. `create`'s body is built via
#   `jq -n --arg` (S-8: the fields fragment here, the envelope in tracker-jira.sh) — this file never
#   string-interpolates a title into a request. `claim`/`release`'s ref-vs-tracker ORDER and COMPENSATION (S-5) live in
#   board-claim.sh's `claim-ref`/`release-ref`, called here, never reimplemented. `BD_CLAIM_SH` /
#   `BD_JIRA_SH` / `BD_CONF_SH` / `BD_LIB_SH` are plain script variables (the loop-state.sh /
#   start.sh precedent) — only `--selftest` ever repoints them, at fixtures/stubs it creates
#   itself; nothing outside this file can redirect a production run to a substitute. The row id
#   is validated against `[A-Z0-9][A-Z0-9-]*` at THIS file's own front door (`bd_require_row`),
#   before it is used to build any `--then` string or pre-read — never left to a downstream
#   validator to catch first. Every value interpolated into a `--then` shell string is
#   single-quote-escaped (`bd_sq`) so a conf-admitted apostrophe in a state name cannot break the
#   string it is embedded in. Every post-read proof is an EXACT field match (`bd_field`), never a
#   substring test, so a status named "Done Deal" cannot be mistaken for "Done".
#
# STATED CEILINGS (read before assuming more than this does):
#   * claim's pre-read (the "is a human already holding this?" check) is deliberately FAIL-OPEN —
#     an unreadable tracker never blocks the attempt; it is an optimization, not the safety
#     boundary. The git ref (claim-ref) is the actual lock; the post-read is what proves success.
#   * a successful `assign-self` followed by a FAILED `transition` (claim's `--then` step runs
#     both) leaves the tracker's ASSIGNEE changed even though the failure compensates (deletes)
#     the git claim ref — partial tracker state is not rolled back, only the ref is.
set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
BD_CLAIM_SH="$here/board-claim.sh"
BD_JIRA_SH="$here/tracker-jira.sh"
BD_CONF_SH="$here/tracker-conf.sh"
BD_LIB_SH="$(dirname "$here")/conformance/backlog-lib.sh"

bd_usage() {
  echo "usage:" >&2
  echo "  board.sh claim   <ROW-ID> [--branch <name>]" >&2
  echo "  board.sh release <ROW-ID> [--stale]" >&2
  echo "  board.sh move    <ROW-ID> <state>" >&2
  echo "  board.sh create  --title <text> [--size <s>] [--risk <r>] [--type <issuetype>] [--parent <KEY>] [--description <text>]" >&2
  echo "                   [--field <token>=<value>]...   (repeatable: the value of a field the project REQUIRES; the token is" >&2
  echo "                    tracker-conf.sh's create.<token> grammar; \`sh conformance/tracker-contract.sh --fields\` lists them)" >&2
  echo "                   (acceptance criteria ride --description; no separate field.acceptance is written;" >&2
  echo "                    a select --size/--risk must be one of the type's allowed values, matched case-insensitively," >&2
  echo "                    printable ASCII only; a free value is [A-Za-z0-9 _.-]{1,64}; a label value [A-Za-z0-9_-]{1,32})" >&2
  echo "  board.sh --selftest" >&2
}

bd_root() { git rev-parse --show-toplevel 2>/dev/null || pwd; }

# bd_row_ok / bd_require_row — the row grammar, checked at THIS file's OWN front door (BLOCKER-1c),
# not left to board-claim.sh/tracker-jira.sh downstream. A row id becomes part of a git ref name
# (board-claim.sh) AND, on a tracker backend, a `--then` shell string this file itself builds
# (see do_claim/do_release below) — so it is validated HERE, before the pre-read, before any
# `_then` string is built, and before do_move passes it onward, exactly like
# board-claim.sh's own bc_row_ok/bc_require_row (a deliberate second copy, for the same reason:
# this file must not trust a downstream validator to run before ITS OWN first use of the value).
bd_row_ok() {
  case "$1" in
    '')           return 1 ;;
    [!A-Z0-9]*)   return 1 ;;
    *[!A-Z0-9-]*) return 1 ;;
  esac
  return 0
}
bd_require_row() {
  bd_row_ok "$1" && return 0
  echo "board: invalid row id '$(printf '%s' "$1" | tr -d '[:cntrl:]')' — a row id must match [A-Z0-9][A-Z0-9-]*." >&2
  return 2
}

# bd_sq <value> -> the value, single-quote-escaped for embedding inside a single-quoted sh string
# (MEDIUM-2): `.kit/tracker.conf` deliberately ADMITS an apostrophe in a state name (L-7, e.g.
# "Won't Do"), so building `_then` with a bare `'$_target'` breaks under `sh -c` the moment a
# conf-admitted apostrophe appears. Every value interpolated into a `_then` string goes through
# this first — never a raw `'$value'`.
bd_sq() {
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
}

# bd_field <text> <field-name> -> the EXACT value of a `<name><TAB><value>` line, or empty
# (MEDIUM-1). Replaces every `case "$x" in *"name<TAB>$want"*)` substring match this file used to
# make: a status named "Done Deal" wrongly matched a target of "Done" under a substring test — the
# post-read is the security oracle for every verb, so it is now an EXACT field extraction + `=`.
bd_field() {
  printf '%s\n' "$1" | awk -F'\t' -v f="$2" '$1==f{print $2; exit}'
}

# bd_backend -> md|jira|... or empty (undeclared/unverified). Routes through the FROZEN §4.2
# seam (`seam_backend`, TBG-SEAM-CONSUMERS-DERIVED) rather than calling `resolve_backend` itself —
# a direct call is a derived-consumer seam bypass (`board-parser-drift.sh` flags it; caught by
# green-on-clone at this fix round). `SEAM_ROOT` is set fresh on every call, mirroring every other
# seam caller in the tree.
bd_backend() {
  _r=$(bd_root)
  [ -f "$BD_LIB_SH" ] || { printf ''; return 0; }
  # shellcheck disable=SC1090
  . "$BD_LIB_SH"
  # shellcheck disable=SC2034  # read by seam_backend() inside the sourced BD_LIB_SH, not in this file
  SEAM_ROOT="$_r"
  seam_backend 2>/dev/null || printf ''
}

bd_conf_path() { printf '%s/.kit/tracker.conf\n' "$(bd_root)"; }

bd_tc_get() { # <key> -> value or empty (never fatal — callers check emptiness)
  sh "$BD_CONF_SH" get "$1" "$(bd_conf_path)" 2>/dev/null || true
}

# bd_tracker_ctx -> sets _btbase/_btflavour/_btproject; rc 1 (naming the missing key) when the
# pin is incomplete. Read ONCE per verb invocation.
bd_tracker_ctx() {
  _btbase=$(bd_tc_get base_url)
  _btproject=$(bd_tc_get project)
  _btflavour=$(bd_tc_get flavour)
  [ -n "$_btflavour" ] || _btflavour=cloud
  if [ -z "$_btbase" ] || [ -z "$_btproject" ]; then
    echo "board.sh: .kit/tracker.conf is missing base_url and/or project — cannot write to the tracker." >&2
    return 1
  fi
  return 0
}

# ── claim ──────────────────────────────────────────────────────────────────────────────────────
do_claim() {
  _row=""; _branch=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --branch) [ $# -ge 2 ] || { echo "board claim: --branch needs a value" >&2; return 2; }; _branch=$2; shift 2 ;;
      -*)       echo "board claim: unknown option '$1'" >&2; bd_usage; return 2 ;;
      *)        [ -z "$_row" ] || { echo "board claim: one row id, not two" >&2; return 2; }; _row=$1; shift ;;
    esac
  done
  [ -n "$_row" ] || { echo "board claim: a row id is required" >&2; bd_usage; return 2; }
  bd_require_row "$_row" || return 2

  _be=$(bd_backend)
  case "$_be" in
    md|'')
      if [ -n "$_branch" ]; then sh "$BD_CLAIM_SH" claim "$_row" --branch "$_branch"
      else                       sh "$BD_CLAIM_SH" claim "$_row"
      fi
      return $? ;;
    jira)
      bd_tracker_ctx || return 1
      _target=$(bd_tc_get state.in-progress)
      [ -n "$_target" ] || { echo "board claim: .kit/tracker.conf has no state.in-progress mapping." >&2; return 2; }
      # pre-read: refuse if the tracker already shows this row in the target state (a cheap proxy
      # for "a human already holds it" — the ref lock below is the real, race-safe guard). LOW-3,
      # STATED CEILING: this pre-read is deliberately FAIL-OPEN (`|| _pre=""` — an unreadable
      # tracker never blocks a claim attempt); it is an optimization, not the safety boundary. The
      # git ref (claim-ref, below) is what makes the claim race-safe; the post-read is what proves
      # success. A pre-read that cannot run simply skips this optimization and proceeds to the ref.
      _pre=$(sh "$BD_JIRA_SH" get-issue "$_btbase" "$_btflavour" "$_btproject" "$_row" 2>&1) || _pre=""
      if [ "$(bd_field "$_pre" status-name)" = "$_target" ]; then
        echo "board claim: REFUSED — \`$_row\` already shows status '$_target' in the tracker." >&2
        return 3
      fi
      # MEDIUM-2: every interpolated value is single-quote-escaped (bd_sq) before it is embedded
      # in this single-quoted `sh -c` string — a conf-admitted apostrophe in a state name (L-7,
      # e.g. "Won't Do") must not break the shape `sh -c` parses.
      _then="sh '$(bd_sq "$BD_JIRA_SH")' assign-self '$(bd_sq "$_btbase")' '$(bd_sq "$_btflavour")' '$(bd_sq "$_btproject")' '$(bd_sq "$_row")' && sh '$(bd_sq "$BD_JIRA_SH")' transition '$(bd_sq "$_btbase")' '$(bd_sq "$_btflavour")' '$(bd_sq "$_btproject")' '$(bd_sq "$_row")' '$(bd_sq "$_target")'"
      # LOW-B: `cmd || return $?` — never a bare `cmd; _rc=$?`. Under `set -e`, a failing `sh …
      # claim-ref` as the LAST statement of an if/else body already aborts the FUNCTION right
      # there (the shell's own -e semantics), so a `_rc=$?` line placed after it never actually
      # runs on the failure path — it was dead code, and the selftest leg that exercises this rc
      # passed for the WRONG reason (set -e's abort, not this forwarding). `cmd || return $?`
      # short-circuits: `$?` inside is cmd's OWN exit status (nothing runs between), and being
      # part of a `||` list this is exempt from -e, so the rc genuinely flows through THIS line.
      if [ -n "$_branch" ]; then sh "$BD_CLAIM_SH" claim-ref "$_row" --branch "$_branch" --then "$_then" || return $?
      else                       sh "$BD_CLAIM_SH" claim-ref "$_row" --then "$_then" || return $?
      fi
      _post=$(sh "$BD_JIRA_SH" get-issue "$_btbase" "$_btflavour" "$_btproject" "$_row" 2>&1) || {
        echo "board claim: the ref+tracker write succeeded but the post-read could not run — cannot prove the claim." >&2
        return 1
      }
      if [ "$(bd_field "$_post" status-name)" = "$_target" ]; then
        echo "board claim: OK — \`$_row\` claimed (ref + tracker transition to '$_target'), proven by post-read."
        return 0
      fi
      echo "board claim: the write ran but the post-read did NOT prove status '$_target' — treating as unproven." >&2
      return 1 ;;
    *) echo "board claim: undeclared or unsupported backend '$_be' — no write adapter for it." >&2; return 2 ;;
  esac
}

# ── release ────────────────────────────────────────────────────────────────────────────────────
do_release() {
  _row=""; _stale=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --stale) _stale=1; shift ;;
      -*)      echo "board release: unknown option '$1'" >&2; bd_usage; return 2 ;;
      *)       [ -z "$_row" ] || { echo "board release: one row id, not two" >&2; return 2; }; _row=$1; shift ;;
    esac
  done
  [ -n "$_row" ] || { echo "board release: a row id is required" >&2; bd_usage; return 2; }
  bd_require_row "$_row" || return 2

  _be=$(bd_backend)
  case "$_be" in
    md|'')
      if [ "$_stale" = 1 ]; then sh "$BD_CLAIM_SH" release "$_row" --stale
      else                       sh "$BD_CLAIM_SH" release "$_row"
      fi
      return $? ;;
    jira)
      bd_tracker_ctx || return 1
      _target=$(bd_tc_get state.ready)
      [ -n "$_target" ] || { echo "board release: .kit/tracker.conf has no state.ready mapping." >&2; return 2; }
      # MEDIUM-2: see the identical note in do_claim above.
      _then="sh '$(bd_sq "$BD_JIRA_SH")' transition '$(bd_sq "$_btbase")' '$(bd_sq "$_btflavour")' '$(bd_sq "$_btproject")' '$(bd_sq "$_row")' '$(bd_sq "$_target")'"
      # LOW-B: see the identical note in do_claim above — `cmd || return $?`, never a bare
      # `cmd; _rc=$?` that `set -e` would have already made unreachable on the failure path.
      if [ "$_stale" = 1 ]; then sh "$BD_CLAIM_SH" release-ref "$_row" --stale --then "$_then" || return $?
      else                       sh "$BD_CLAIM_SH" release-ref "$_row" --then "$_then" || return $?
      fi
      _post=$(sh "$BD_JIRA_SH" get-issue "$_btbase" "$_btflavour" "$_btproject" "$_row" 2>&1) || {
        echo "board release: the ref+tracker write succeeded but the post-read could not run — cannot prove the release." >&2
        return 1
      }
      if [ "$(bd_field "$_post" status-name)" = "$_target" ]; then
        echo "board release: OK — \`$_row\` released (tracker transition to '$_target' + ref deleted), proven by post-read."
        return 0
      fi
      echo "board release: the write ran but the post-read did NOT prove status '$_target' — treating as unproven." >&2
      return 1 ;;
    *) echo "board release: undeclared or unsupported backend '$_be' — no write adapter for it." >&2; return 2 ;;
  esac
}

# ── move ───────────────────────────────────────────────────────────────────────────────────────
# §4.1 tokens only — the eight kit states. A raw tracker status string never reaches this verb;
# the token is resolved to the conf's own state.<token> NAME, and tracker-jira.sh resolves that
# name to the ONE matching transition's to.id (S-8). Backward moves (e.g. done -> backlog) are
# ordinary tokens here, first-class — nothing in this verb distinguishes direction.
BD_STATES='backlog ready in-progress in-review blocked released done cancelled'
bd_state_ok() {
  for _s in $BD_STATES; do [ "$1" = "$_s" ] && return 0; done
  return 1
}

# bd_transition <row> <target>: the adapter's transition with its stderr passed through unchanged; the adapter's
# rc lands in $_tr_rc (5 = a diagnosed refusal: ONE fixed sentence naming the transition screen's required fields).
# claim/release need no twin: their transition runs under board-claim.sh's `--then`, whose stderr is not captured.
bd_transition() {
  _tr_errf=$(mktemp) || { echo "board: could not create a scratch file." >&2; _tr_rc=1; return 1; }
  _tr_rc=0
  sh "$BD_JIRA_SH" transition "$_btbase" "$_btflavour" "$_btproject" "$1" "$2" 2>"$_tr_errf" || _tr_rc=$?
  cat "$_tr_errf" >&2; rm -f "$_tr_errf"
  [ "$_tr_rc" -eq 0 ]
}

do_move() {
  [ $# -eq 2 ] || { echo "board move: usage: board.sh move <ROW-ID> <state>" >&2; return 2; }
  _row=$1; _state=$2
  bd_require_row "$_row" || return 2
  bd_state_ok "$_state" || {
    echo "board move: '$_state' is not one of the §4.1 states ($BD_STATES)." >&2
    return 2
  }
  _be=$(bd_backend)
  case "$_be" in
    jira)
      bd_tracker_ctx || return 1
      _target=$(bd_tc_get "state.$_state")
      [ -n "$_target" ] || { echo "board move: .kit/tracker.conf has no state.$_state mapping." >&2; return 2; }
      if ! bd_transition "$_row" "$_target"; then
        # rc 5 = the adapter DIAGNOSED the refusal (its fixed sentence, already shown above, names the
        # screen fields); any other failure keeps the generic line.
        [ "$_tr_rc" -eq 5 ] || echo "board move: the tracker transition to '$_target' failed or was refused." >&2
        return 1
      fi
      _post=$(sh "$BD_JIRA_SH" get-issue "$_btbase" "$_btflavour" "$_btproject" "$_row" 2>&1) || {
        echo "board move: the transition ran but the post-read could not run — cannot prove the move." >&2
        return 1
      }
      if [ "$(bd_field "$_post" status-name)" = "$_target" ]; then
        echo "board move: OK — \`$_row\` -> '$_target' ($_state), proven by post-read."
        return 0
      fi
      echo "board move: the transition ran but the post-read did NOT prove status '$_target'." >&2
      return 1 ;;
    md|'') echo "board move: no write adapter for backend '$_be' — hand-edit BACKLOG.md." >&2; return 2 ;;
    *)     echo "board move: undeclared or unsupported backend '$_be'." >&2; return 2 ;;
  esac
}

# ── create ─────────────────────────────────────────────────────────────────────────────────────
# `create` resolves Size/Risk through the SAME `field.*` mapping the readers use (tracker-read.sh's
# tr_field_kind: customfield_N | label:<prefix> | none | description), checks it against the create-meta
# of the issue type it is about to make, and refuses BEFORE any POST when a mapped field is not on that
# type's screen, a select value is outside its allowed set, or a mapping cannot carry the value. The
# body is a fields FRAGMENT built here with `jq -n --arg` (S-8); tracker-jira.sh merges it. Success is
# PROVEN by a get-fields post-read of the type, parent, Size and Risk (design 2026-10-01 §3c).
BD_TAB=$(printf '\t')

# bd_val_ok <value> <tr-set> <max>: non-empty, every byte inside <tr-set>, at most <max> bytes. Counted
# in bytes after a C-locale `tr -d` (a stray newline survives the delete, where `$(...)` would hide it).
bd_val_ok() {
  [ -n "$1" ] && [ "${#1}" -le "$3" ] || return 1
  [ "$(printf '%s' "$1" | LC_ALL=C tr -d "$2" | wc -c | tr -d ' ')" = 0 ]
}

# bd_type_ok <name>: tracker-conf.sh's own create.issuetype grammar, ^[A-Za-z][A-Za-z0-9 _-]{0,39}$.
bd_type_ok() {
  bd_val_ok "$1" 'A-Za-z0-9 _-' 40 || return 1
  [ -z "$(printf '%s' "$1" | cut -c1 | LC_ALL=C tr -d 'A-Za-z')" ]
}

# bd_cr_has <field-id>: 0 when the create-meta ($_cm) carries that field id on this type's screen.
bd_cr_has() {
  [ -n "$(printf '%s\n' "$_cm" | awk -F'\t' -v f="$1" '$2 == f { print "y"; exit }')" ]
}

# bd_cr_note <field-id> <expected>: remember what the post-read must show; the id is read back once.
bd_cr_note() {
  _cr_expect="$_cr_expect
$1	$2"
  case " $_cr_ids " in
    *" $1 "*) : ;;
    *) _cr_ids="$_cr_ids $1" ;;
  esac
}

# bd_cr_wrong_screen <name> <field-id>: the named refusal when a mapped customfield is not on this type's screen.
bd_cr_wrong_screen() {
  _ws_own=$(printf '%s\n' "$_cm" | awk -F'\t' -v n="$1" 'tolower($4) == n { print $2; exit }')
  if [ -n "$_ws_own" ]; then
    echo "board create: field.$1=$2 is not on the create screen of issue type '$_type'; that type's own $1 field is $_ws_own - repoint field.$1=$_ws_own, or create the conf's own type (--type). A per-type map is TRACKER-FIELD-MAP-PER-ISSUE-TYPE." >&2
  else
    echo "board create: field.$1=$2 is not on the create screen of issue type '$_type', and that type has no field named '$1' - run \`sh conformance/tracker-contract.sh --fields\` to see each type's ids." >&2
  fi
}

# bd_cr_custom <name> <customfield_N> <value>: a select (option) is written {"value": <canonical allowed
# value>} (case-insensitive match, so `low` becomes `Low`); a string as-is; any other schema type refused.
bd_cr_custom() {
  _cu_line=$(printf '%s\n' "$_cm" | awk -F'\t' -v f="$2" '$2 == f { print; exit }')
  [ -n "$_cu_line" ] || { bd_cr_wrong_screen "$1" "$2"; return 2; }
  bd_val_ok "$3" 'A-Za-z0-9 _.-' 64 || { echo "board create: --$1 must match [A-Za-z0-9 _.-]{1,64}." >&2; return 2; }
  _cu_schema=$(printf '%s' "$_cu_line" | cut -f3)
  case "$_cu_schema" in
    option)
      _cu_allowed=$(printf '%s' "$_cu_line" | cut -f5)
      _cu_val=$(printf '%s\n' "$_cu_allowed" | awk -F'|' -v v="$3" 'BEGIN { lv = tolower(v) } { for (i = 1; i <= NF; i++) if (tolower($i) == lv) { print $i; exit } }')
      [ -n "$_cu_val" ] || { echo "board create: --$1 '$3' is not an allowed value of $2; allowed: $(printf '%s' "$_cu_allowed" | sed 's/|/, /g') (printable ASCII only)." >&2; return 2; }
      _frag=$(printf '%s' "$_frag" | jq -c --arg id "$2" --arg v "$_cu_val" '. + {($id): {value: $v}}') ;;
    string)
      _cu_val=$3
      _frag=$(printf '%s' "$_frag" | jq -c --arg id "$2" --arg v "$_cu_val" '. + {($id): $v}') ;;
    *) echo "board create: field.$1=$2 has schema type '$_cu_schema'; board create writes only a select (option) or string field." >&2; return 2 ;;
  esac
  bd_cr_note "$2" "$_cu_val"
}

# bd_cr_label <name> <prefix> <value>: the label `<prefix>:<value>`, the value in the reader's own grammar.
bd_cr_label() {
  bd_val_ok "$3" 'A-Za-z0-9_-' 32 || { echo "board create: --$1 must match [A-Za-z0-9_-]{1,32} to be written as the label '$2:<value>' the readers count." >&2; return 2; }
  bd_cr_has labels || { echo "board create: issue type '$_type' has no labels field on its create screen, so field.$1=label:$2 cannot be written." >&2; return 2; }
  _frag=$(printf '%s' "$_frag" | jq -c --arg l "$2:$3" '.labels = ((.labels // []) + [$l])')
  _cr_labels="$_cr_labels $2:$3"
  bd_cr_note labels ""
}

# bd_cr_field <name> <value>: one of Size/Risk. An empty value is not asked for. A mapping that is none,
# description or absent refuses the value (never a silent drop).
bd_cr_field() {
  [ -n "$2" ] || return 0
  _fm=$(bd_tc_get "field.$1")
  case "$_fm" in
    customfield_*) bd_cr_custom "$1" "$_fm" "$2" ;;
    label:*)       bd_cr_label "$1" "${_fm#label:}" "$2" ;;
    *) echo "board create: field.$1 is not mapped to a writable field (conf has '${_fm:-unset}') - map it to customfield_N or label:<prefix> in .kit/tracker.conf, or drop --$1." >&2; return 2 ;;
  esac
}

# bd_cr_parent / bd_cr_desc: --parent and --description, each only when the type's screen carries the field.
bd_cr_parent() {
  [ -n "$_parent" ] || return 0
  bd_cr_has parent || { echo "board create: issue type '$_type' has no parent field on its create screen (Data Center links an epic via Epic Link, which board create does not write) - drop --parent and link the card by hand." >&2; return 2; }
  _frag=$(printf '%s' "$_frag" | jq -c --arg k "$_parent" '. + {parent: {key: $k}}')
  bd_cr_note parent "$_parent"
}
bd_cr_desc() {
  [ -n "$_desc" ] || return 0
  bd_cr_has description || { echo "board create: issue type '$_type' has no description field on its create screen." >&2; return 2; }
  bd_cr_text "$_desc" || return 1
  _frag=$(printf '%s' "$_frag" | jq -c --argjson d "$_jv" '. + {description: $d}')
}

# bd_cr_text <text>: the Jira text shape, into $_jv — ADF paragraphs on Cloud, a plain string on Data Center.
# The ONE shaper: --description and a required `text` (textarea) field both go through it.
bd_cr_text() {
  if [ "$_btflavour" = datacenter ]; then
    _jv=$(jq -nc --arg v "$1" '$v')
  else
    _jv=$(jq -nc --arg v "$1" '{type: "doc", version: 1, content: ($v | split("\n") | map({type: "paragraph", content: (if . == "" then [] else [{type: "text", text: .}] end)}))}')
  fi
}

# bd_cr_prove <key>: the post-read — every value we wrote must read back EXACTLY. A mismatch names the key
# (the card exists; this verb does not delete on a failed proof, it could delete the wrong thing).
bd_cr_prove() {
  # shellcheck disable=SC2086  # _cr_ids is a space-separated list of closed-grammar field ids
  _pv_post=$(sh "$BD_JIRA_SH" get-fields "$_btbase" "$_btflavour" "$_btproject" "$1" $_cr_ids 2>&1) || {
    echo "board create: created '$1' but the post-read could not run - cannot prove its type, parent, Size and Risk (the card exists)." >&2
    return 1
  }
  while IFS="$BD_TAB" read -r _pv_id _pv_want; do
    [ -n "$_pv_id" ] && [ "$_pv_id" != labels ] || continue
    _pv_got=$(bd_field "$_pv_post" "$_pv_id")
    [ "$_pv_got" = "$_pv_want" ] || { echo "board create: created '$1' but the post-read did NOT prove $_pv_id = '$_pv_want' (read '$(printf '%s' "$_pv_got" | tr -cd '\40-\176' | cut -c1-64)') - the card exists, fix or delete it by hand." >&2; return 1; }
  done <<EOF_PV
$_cr_expect
EOF_PV
  for _pv_pres in $_cr_present; do
    [ -n "$(bd_field "$_pv_post" "$_pv_pres")" ] \
      || { echo "board create: created '$1' but the post-read did NOT prove $_pv_pres is present (it read back empty) - the card exists, fix or delete it by hand." >&2; return 1; }
  done
  for _pv_lab in $_cr_labels; do
    case " $(bd_field "$_pv_post" labels) " in
      *" $_pv_lab "*) : ;;
      *) echo "board create: created '$1' but the post-read did NOT prove the label '$_pv_lab' - the card exists, fix or delete it by hand." >&2; return 1 ;;
    esac
  done
}

# bd_cr_meta: read the create type's create-meta into $_cm and its numeric id into $_type_id. The adapter's rc
# is a contract: 3 = the type is not in the project, 4 = the name is ambiguous, anything else non-zero =
# unverified (its own fixed sentence is shown — a credential or transport refusal is NOT "type absent").
bd_cr_meta() {
  _cm_errf=$(mktemp) || { echo "board create: could not create a scratch file." >&2; return 1; }
  _cm_rc=0
  _cm=$(sh "$BD_JIRA_SH" create-meta "$_btbase" "$_btflavour" "$_btproject" "$_type" 2>"$_cm_errf") || _cm_rc=$?
  _cm_err=$(tr -cd '\40-\176' < "$_cm_errf" | cut -c1-200); rm -f "$_cm_errf"
  case "$_cm_rc" in
    0) : ;;
    3) echo "board create: issue type '$_type' is not in project $_btproject (or the token lacks Create permission in this project) - set create.issuetype in .kit/tracker.conf (or pass --type) to one of its types; \`sh conformance/tracker-contract.sh --fields\` lists them." >&2; return 2 ;;
    4) echo "board create: issue type name '$_type' is ambiguous in project $_btproject (more than one type carries it) - rename one in Jira; nothing was created." >&2; return 2 ;;
    *) echo "board create: could not read the create-meta of '$_type' - ${_cm_err:-unverified}; nothing was created." >&2; return 1 ;;
  esac
  _type_id=$(printf '%s\n' "$_cm" | awk -F'\t' '$1 == "#type-id" { print $2; exit }')
  case "$_type_id" in
    ''|*[!0-9]*) echo "board create: the create-meta carried no numeric type id (unverified); nothing was created." >&2; return 1 ;;
  esac
}

# ── required fields (TRACKER-REQUIRED-FIELDS-DISCOVERY) ─────────────────────────────────────────
# The adapter's `required-fields` lists what the project demands of this type beyond what the kit already
# sends. Each is covered (a value is ALREADY in the fragment), filled from `--field <id>=<value>` or the
# conf's `create.<id>=<value>`, or REFUSED — every miss reported in one run, then ZERO POSTs. The key/value
# grammar is tracker-conf.sh's (`check-create`/`get-prefix`), never a second copy here.

bd_disp() { printf '%s' "$1" | tr -cd '\40-\176' | cut -c1-64; }

# bd_cr_miss <what> [<tail>]: one refusal line; the verb exits 1 once every required field was looked at.
bd_cr_miss() {
  echo "board create: $1; nothing was created.${2:+ $2}" >&2
  _cr_missed=1
}

# bd_wck_has <id>: 0 when the adapter's writable-create-keys ($_wck) admits that fragment key.
bd_wck_has() {
  case "$1" in
    customfield_*)
      _wk=${1#customfield_}
      case "$_wk" in ''|*[!0-9]*) return 1 ;; esac
      [ "${#_wk}" -le 10 ] || return 1
      printf '%s\n' "$_wck" | grep -qxF 'customfield_N' ;;
    *) printf '%s\n' "$_wck" | grep -qxF -e "$1" ;;
  esac
}

# bd_cr_flag_for <id>: the CLI flag that fills this id (parent/description/Size/Risk), or nothing.
bd_cr_flag_for() {
  case "$1" in
    description) echo '--description <text>'; return 0 ;;
    parent)      echo '--parent <KEY>'; return 0 ;;
  esac
  [ "$1" != "$(bd_tc_get field.size)" ] || { echo '--size <s>'; return 0; }
  [ "$1" != "$(bd_tc_get field.risk)" ] || { echo '--risk <r>'; return 0; }
  return 0
}

# bd_date_ok <value>: YYYY-MM-DD with a real month and a 01-31 day.
bd_date_ok() {
  case "$1" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;; *) return 1 ;; esac
  _dm=${1#*-}; _dd=${_dm#*-}; _dm=${_dm%%-*}
  case "$_dm" in 0[1-9]|1[0-2]) : ;; *) return 1 ;; esac
  case "$_dd" in 0[1-9]|[12][0-9]|3[01]) return 0 ;; esac
  return 1
}

# bd_cr_json <kind> <value>: the value shaped for its kind into $_jv (compact JSON, built with jq --arg only);
# rc 1 with $_jwhy when the value cannot be that kind. `id:<N>` selects the id form where a kind has one.
bd_cr_json() {
  _jid=""
  case "$2" in id:*) _jid=${2#id:} ;; esac
  case "$1" in
    option|option-array|priority|component-array|version-array) : ;;
    *) [ -z "$_jid" ] || { _jwhy="id:<N> applies only to option, priority, component and version fields"; return 1; } ;;
  esac
  case "$1" in
    string|team) _jp='$v' ;;
    text) bd_cr_text "$2"; return 0 ;;
    number)
      case "$2" in ''|*[!0-9.-]*) _jwhy="'$(bd_disp "$2")' is not a number"; return 1 ;; esac
      jq -nc --arg v "$2" '$v | tonumber' >/dev/null 2>&1 || { _jwhy="'$(bd_disp "$2")' is not a number"; return 1; }
      _jp='$v | tonumber' ;;
    date) bd_date_ok "$2" || { _jwhy="'$(bd_disp "$2")' is not a date (YYYY-MM-DD)"; return 1; }; _jp='$v' ;;
    option)          _jp='if $id != "" then {id: $id} else {value: $v} end' ;;
    option-array)    _jp='[if $id != "" then {id: $id} else {value: $v} end]' ;;
    string-array)
      case "$2" in *' '*) _jwhy="a label cannot contain a space"; return 1 ;; esac
      _jp='[$v]' ;;
    priority)        _jp='if $id != "" then {id: $id} else {name: $v} end' ;;
    component-array|version-array) _jp='[if $id != "" then {id: $id} else {name: $v} end]' ;;
    user) if [ "$_btflavour" = datacenter ]; then _jp='{name: $v}'; else _jp='{accountId: $v}'; fi ;;
    *) _jwhy="its kind '$(bd_disp "$1")' is not one the kit can write"; return 1 ;;
  esac
  _jv=$(jq -nc --arg v "$2" --arg id "$_jid" "$_jp") || { _jwhy="the value could not be shaped"; return 1; }
}

# bd_cr_member: a literal value of an option/priority/component/version field must be one Jira listed.
# An incomplete (truncated) or empty list cannot prove a miss: NOTE and let Jira decide. id:<N> is unchecked.
bd_cr_member() {
  case "$_rq_kind" in option|option-array|priority|component-array|version-array) : ;; *) return 0 ;; esac
  case "$_rq_val" in id:*) return 0 ;; esac
  if [ "$_rq_comp" != complete ] || [ -z "$_rq_allowed" ]; then
    echo "board create: NOTE - the allowed values of $_rq_disp are incomplete, so '$(bd_disp "$_rq_val")' is not checked against them (Jira decides)." >&2
    return 0
  fi
  printf '%s\n' "$_rq_allowed" | tr '|' '\n' | grep -qxF -e "$_rq_val" && return 0
  bd_cr_miss "$_rq_disp has no allowed value '$(bd_disp "$_rq_val")' (from $_rq_src)" "Pick one (allowed: $(printf '%s' "$_rq_allowed" | sed 's/|/, /g' | cut -c1-80))."
  return 1
}

# bd_cr_apply: check the value against the allowed set, shape it by kind, merge it into the fragment.
bd_cr_apply() {
  bd_cr_member || return 0
  bd_cr_json "$_rq_kind" "$_rq_val" || { bd_cr_miss "$_rq_disp: $_jwhy (from $_rq_src)"; return 0; }
  _frag=$(printf '%s' "$_frag" | jq -c --arg k "$_rq_id" --argjson v "$_jv" '. + {($k): $v}') \
    || { bd_cr_miss "$_rq_disp could not be added to the request"; return 0; }
  bd_cr_expect
}

# bd_cr_present <field-id>: remember that the post-read must show SOMETHING for this field (not a particular value).
bd_cr_present() {
  case " $_cr_ids " in
    *" $1 "*) : ;;
    *) _cr_ids="$_cr_ids $1" ;;
  esac
  _cr_present="$_cr_present $1"
}

# bd_cr_expect: register the value just filled so bd_cr_prove reads it back. Exact for string, number, date,
# team, user, priority, component/version names, option values and string arrays (what the adapter's get-fields
# renders). PRESENCE only for a text field (the adapter renders its content as the word `present`) and for any
# id:<N> value (get-fields renders an option's value or a priority's name, not the id it was written by).
bd_cr_expect() {
  case "$_rq_kind:$_rq_val" in
    text:*|*:id:*) bd_cr_present "$_rq_id"; return 0 ;;
    number:*) bd_cr_note "$_rq_id" "$(jq -nc --arg v "$_rq_val" '$v | tonumber | tostring' | tr -d '"')"; return 0 ;;
    string-array:*)
      if [ "$_rq_id" = labels ]; then _cr_labels="$_cr_labels $_rq_val"; bd_cr_note labels ""; return 0; fi ;;
  esac
  bd_cr_note "$_rq_id" "$_rq_val"
}

# bd_cr_one: resolve ONE required line (the _rq_* vars) — covered, flag, unsupported, not writable, --field,
# conf default, prompt, or unmapped. Never exits the verb: a miss is recorded and the next field is still read.
bd_cr_one() {
  _rq_disp="'$(bd_disp "$_rq_name")' ($(bd_disp "$_rq_id"))"
  _rq_fv=$(bd_field "$_cr_fields" "$_rq_id")
  if printf '%s' "$_frag" | jq -e --arg k "$_rq_id" 'has($k)' >/dev/null 2>&1; then
    [ -z "$_rq_fv" ] || bd_cr_miss "--field $_rq_id sets a value a flag already sets (--size/--risk/--parent/--description) - drop one"
    return 0
  fi
  _rq_flag=$(bd_cr_flag_for "$_rq_id")
  if [ -n "$_rq_flag" ]; then bd_cr_miss "the project requires $_rq_disp - pass $_rq_flag"; return 0; fi
  if [ "$_rq_kind" = unsupported ]; then
    bd_cr_miss "the project requires $_rq_disp, a field the kit cannot write (its schema type is not one board create supports)" "Give it a default in Jira, or make it optional there."; return 0
  fi
  if ! bd_wck_has "$_rq_id"; then
    bd_cr_miss "the project requires $_rq_disp, which this adapter cannot write (writable: $(printf '%s' "$_wck" | tr '\n' ' ' | sed 's/ $//'))" "Give it a default in Jira, or make it optional there."; return 0
  fi
  _rq_src=--field; _rq_val=$_rq_fv
  if [ -z "$_rq_val" ]; then
    _rq_src=".kit/tracker.conf"; _rq_val=$(bd_field "$_cr_defaults" "create.$_rq_id")
    case "$_rq_val" in
      '') _rq_allow=""; [ -z "$_rq_allowed" ] || _rq_allow=" (allowed: $(printf '%s' "$_rq_allowed" | sed 's/|/, /g' | cut -c1-80))"
          bd_cr_miss "the project requires $_rq_disp and .kit/tracker.conf does not map it" "Add the line 'create.$_rq_id=<value>'$_rq_allow to .kit/tracker.conf, or 'create.$_rq_id=prompt' - the value is your team's: read the project CLAUDE.md, and if it is silent ask the owner; use prompt for a per-card value"
          return 0 ;;
      prompt) bd_cr_miss "$_rq_disp needs a value for this card - pass --field $_rq_id=<value> (.kit/tracker.conf says prompt; the value is your team's: read the project CLAUDE.md, and if it is silent ask the owner)"; return 0 ;;
    esac
  fi
  bd_cr_apply
}

# bd_cr_fields_ok: every --field pair must name a writable key that is a REQUIRED field of this type.
bd_cr_fields_ok() {
  while IFS="$BD_TAB" read -r _ff_id _ff_val; do
    [ -n "$_ff_id" ] || continue
    if ! bd_wck_has "$_ff_id"; then
      bd_cr_miss "--field $_ff_id is not a writable create key (writable: $(printf '%s' "$_wck" | tr '\n' ' ' | sed 's/ $//'))"; continue
    fi
    [ -n "$(printf '%s\n' "$_rf" | awk -F'\t' -v f="$_ff_id" '$1 == f { print "y"; exit }')" ] \
      || bd_cr_miss "--field $_ff_id is not a required field of issue type '$_type' (the kit fills only required fields; Size/Risk/parent/description have their own flags)"
  done <<EOF_FF
$_cr_fields
EOF_FF
}

# bd_cr_dropped: the adapter's `#dropped<TAB><n>` sentinel = n required fields it could not name (a bad fieldId):
# the create cannot be proven complete, so it is refused (fail closed), never guessed.
bd_cr_dropped() {
  _dr_n=$(printf '%s\n' "$_rf" | awk -F'\t' '$1 == "#dropped" { print $2; exit }')
  case "$_dr_n" in ''|0|*[!0-9]*) return 0 ;; esac
  bd_cr_miss "unverified: the tracker reported $_dr_n required field(s) the kit cannot name"
}

# bd_cr_notes: a conf create.<token> that board create will not write is NOTEd, never silently dropped —
# description/parent are filled only by their flags; any other token must be a REQUIRED field of this type.
bd_cr_notes() {
  while IFS="$BD_TAB" read -r _nt_key _nt_rest; do
    [ -n "$_nt_key" ] || continue
    _nt_tok=${_nt_key#create.}
    case "$_nt_tok" in
      description) echo "board create: NOTE: create.description is ignored - description is filled only by --description <text>." >&2 ;;
      parent) echo "board create: NOTE: create.parent is ignored - parent is filled only by --parent <KEY>." >&2 ;;
      *) [ -n "$(printf '%s\n' "$_rf" | awk -F'\t' -v f="$_nt_tok" '$1 == f { print "y"; exit }')" ] \
           || echo "board create: NOTE: create.$(bd_disp "$_nt_tok") is not required by '$(bd_disp "$_type")'; not written." >&2 ;;
    esac
  done <<EOF_NT
$_cr_defaults
EOF_NT
}

# bd_cr_required: ask the adapter what $_type requires and what it can write, then resolve every line.
# rc 0 = nothing missing (the fragment now carries every filled value); rc 1 = refused, nothing POSTed.
bd_cr_required() {
  _wck=$(sh "$BD_JIRA_SH" writable-create-keys 2>/dev/null) || _wck=""
  [ -n "$_wck" ] || { echo "board create: the adapter reported no writable create keys (unverified); nothing was created." >&2; return 1; }
  _rf_errf=$(mktemp) || { echo "board create: could not create a scratch file." >&2; return 1; }
  _rf_rc=0
  _rf=$(sh "$BD_JIRA_SH" required-fields "$_btbase" "$_btflavour" "$_btproject" "$_type" 2>"$_rf_errf") || _rf_rc=$?
  _rf_err=$(tr -cd '\40-\176' < "$_rf_errf" | cut -c1-200); rm -f "$_rf_errf"
  [ "$_rf_rc" -eq 0 ] || { echo "board create: could not read the required fields of '$_type' - ${_rf_err:-unverified}; nothing was created." >&2; return 1; }
  _cr_defaults=$(sh "$BD_CONF_SH" get-prefix create. "$(bd_conf_path)" 2>/dev/null) || _cr_defaults=""
  _cr_missed=0
  bd_cr_dropped
  bd_cr_notes
  bd_cr_fields_ok
  while IFS= read -r _rq_line; do
    case "$_rq_line" in ''|'#'*) continue ;; esac
    _rq_id=$(printf '%s' "$_rq_line" | cut -f1); _rq_kind=$(printf '%s' "$_rq_line" | cut -f2)
    _rq_name=$(printf '%s' "$_rq_line" | cut -f3); _rq_allowed=$(printf '%s' "$_rq_line" | cut -f4)
    _rq_comp=$(printf '%s' "$_rq_line" | cut -f5)
    bd_cr_one
  done <<EOF_RF
$_rf
EOF_RF
  [ "$_cr_missed" -eq 0 ]
}

# bd_create_jira: the jira arm — type, create-meta, resolve every field, POST once, prove.
bd_create_jira() {
  bd_tracker_ctx || return 1
  command -v jq >/dev/null 2>&1 || { echo "board create: jq is required for create (install jq)." >&2; return 2; }
  [ -n "$_type" ] || _type=$(bd_tc_get create.issuetype)
  [ -n "$_type" ] || _type=Task
  bd_type_ok "$_type" || { echo "board create: the issue type must match ^[A-Za-z][A-Za-z0-9 _-]{0,39}\$." >&2; return 2; }
  bd_cr_meta || return $?
  _frag='{}'; _cr_expect=""; _cr_ids=""; _cr_labels=""; _cr_present=""
  bd_cr_note issuetype "$_type"
  bd_cr_field size "$_size" || return $?
  bd_cr_field risk "$_risk" || return $?
  bd_cr_parent || return $?
  bd_cr_desc || return $?
  bd_cr_required || return 1
  # created BY the numeric id create-meta resolved (never an ambiguous name); the fragment rides STDIN, not argv
  _key=$(printf '%s' "$_frag" | sh "$BD_JIRA_SH" create "$_btbase" "$_btflavour" "$_btproject" "$_title" "$_type_id" -) || {
    echo "board create: the tracker create request failed or was refused (a workflow validator may require a field create-meta does not report; see tracker-contract.sh --fields)." >&2
    return 1
  }
  bd_row_ok "$_key" || { echo "board create: the tracker returned a key outside the id grammar." >&2; return 1; }
  bd_cr_prove "$_key" || return 1
  echo "board create: OK — created \`$_key\`, proven by post-read."
  printf '%s\n' "$_key"
}

# bd_field_arg <token=value>: one --field, validated by tracker-conf.sh's own create.<token>=<value> grammar
# (`check-create` — the one grammar, not a copy here) and appended to $_cr_fields as `token<TAB>value`.
bd_field_arg() {
  case "$1" in
    *=*) : ;;
    *) echo "board create: --field needs <token>=<value> (got '$(bd_disp "$1")')" >&2; return 2 ;;
  esac
  _fa_k=${1%%=*}; _fa_v=${1#*=}
  [ "$_fa_v" != prompt ] || { echo "board create: --field $(bd_disp "$_fa_k")=prompt is not a value - pass the real one (read the project CLAUDE.md, or ask the owner)" >&2; return 2; }
  _fa_err=$(sh "$BD_CONF_SH" check-create "$_fa_k" "$_fa_v" 2>&1 >/dev/null) || { echo "board create: --field: ${_fa_err#refused: }" >&2; return 2; }
  [ -z "$(bd_field "$_cr_fields" "$_fa_k")" ] || { echo "board create: --field $_fa_k is given twice - one value per field" >&2; return 2; }
  _cr_fields="$_cr_fields$_fa_k$BD_TAB$_fa_v
"
}

do_create() {
  _title=""; _size=""; _risk=""; _type=""; _parent=""; _desc=""; _cr_fields=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --title|--size|--risk|--type|--parent|--description|--field)
        [ $# -ge 2 ] || { echo "board create: $1 needs a value" >&2; return 2; }
        case "$1" in
          --title) _title=$2 ;;
          --size) _size=$2 ;;
          --risk) _risk=$2 ;;
          --type) _type=$2 ;;
          --parent) _parent=$2 ;;
          --description) _desc=$2 ;;
          --field) bd_field_arg "$2" || return 2 ;;
        esac
        shift 2 ;;
      -*)      echo "board create: unknown option '$1'" >&2; bd_usage; return 2 ;;
      *)       echo "board create: unexpected argument '$1' (use --title/--size/--risk/--type/--parent/--description/--field)" >&2; return 2 ;;
    esac
  done
  [ -n "$_title" ] || { echo "board create: --title is required" >&2; bd_usage; return 2; }
  [ -z "$_type" ] || bd_type_ok "$_type" || { echo "board create: --type must match ^[A-Za-z][A-Za-z0-9 _-]{0,39}\$." >&2; return 2; }
  [ -z "$_parent" ] || bd_row_ok "$_parent" || { echo "board create: --parent must be an issue key matching [A-Z0-9][A-Z0-9-]*." >&2; return 2; }
  [ "$(printf '%s' "$_desc" | wc -c | tr -d ' ')" -le 32000 ] || { echo "board create: --description is over the 32000-byte bound." >&2; return 2; }
  [ "$(printf '%s' "$_desc" | wc -l | tr -d ' ')" -le 2000 ] || { echo "board create: --description is over the 2000-line bound." >&2; return 2; }
  _be=$(bd_backend)
  case "$_be" in
    jira) bd_create_jira; return $? ;;
    md|'') echo "board create: no write adapter for backend '$_be' — add the row to BACKLOG.md by hand." >&2; return 2 ;;
    *)     echo "board create: undeclared or unsupported backend '$_be'." >&2; return 2 ;;
  esac
}

# ── ORACLE MARKER: selftest() and everything below is the non-vacuity oracle region. ─────────────
selftest() {
  bd_fail=0
  bd_base=$(mktemp -d)
  HOME="$bd_base/home"; mkdir -p "$HOME"; export HOME
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null; export GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
  unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL 2>/dev/null || true

  bd_pass() { echo "selftest PASS: $1"; }
  bd_fail_() { echo "selftest FAIL: $1"; bd_fail=1; }

  # ── md-backend leg: claim/release DELEGATE to board-claim.sh's own claim/release ────────────
  bd_remote="$bd_base/github.com/fixture-owner/fixture-repo.git"
  mkdir -p "$(dirname -- "$bd_remote")"
  git init -q --bare "$bd_remote"
  git clone -q "$bd_remote" "$bd_base/md-clone" 2>/dev/null
  (
    cd "$bd_base/md-clone"
    git config user.name "Fixture Dev"; git config user.email "dev@example.com"; git config commit.gpgsign false
    printf '# CLAUDE.md\n\nBacklog backend: BACKLOG.md (repo-native)\n' > CLAUDE.md
    cat > BACKLOG.md <<'BOARD_EOF'
# Fixture — Backlog

## Ready

| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links | Success metric / hypothesis |
|------|--------------|---------------------|------|------|------|-------|-------|-----------------------------|
| `ROW-1` — a claimable row | because | it is claimed | S | low | feature | agent | — | a claim serializes |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|
BOARD_EOF
  )
  BOARD_CLAIM_REMOTE="$bd_remote"
  export BOARD_CLAIM_REMOTE
  bd_out=$(cd "$bd_base/md-clone" && sh "$BD_SELF" claim ROW-1 --branch feat/x 2>&1); bd_rc=$?
  if [ "$bd_rc" -eq 0 ]; then bd_pass "leg md/claim: an md-backend claim delegates to board-claim.sh and succeeds"
  else bd_fail_ "leg md/claim: rc=$bd_rc out=[$bd_out]"; fi
  if git ls-remote "$bd_remote" refs/claims/ROW-1 2>/dev/null | grep -q refs/claims/ROW-1; then
    bd_pass "leg md/ref: refs/claims/ROW-1 exists on the fixture remote (a real push, not a stub)"
  else
    bd_fail_ "leg md/ref: refs/claims/ROW-1 absent from the fixture remote after rc 0"
  fi
  bd_out2=$(cd "$bd_base/md-clone" && sh "$BD_SELF" release ROW-1 2>&1); bd_rc2=$?
  if [ "$bd_rc2" -eq 0 ]; then bd_pass "leg md/release: an md-backend release delegates to board-claim.sh and succeeds"
  else bd_fail_ "leg md/release: rc=$bd_rc2 out=[$bd_out2]"; fi

  # ── jira-backend legs: BD_JIRA_SH repointed at a STUB adapter (mirrors start.sh's ST_CLASSIFIER
  # stub pattern) so this file's OWN orchestration (order, proof, refusal) is proven without a real
  # HTTP fixture — tracker-jira.sh's own selftest already proves the adapter's request/response
  # shapes and security controls; duplicating those here would test the wrong layer. ────────────
  bd_jclone="$bd_base/jira-clone"
  git clone -q "$bd_remote" "$bd_jclone" 2>/dev/null
  (
    cd "$bd_jclone"
    git config user.name "Fixture Dev"; git config user.email "dev@example.com"; git config commit.gpgsign false
    mkdir -p .kit
    printf 'Backlog backend: jira\n' > CLAUDE.md
    cat > .kit/tracker.conf <<'CONF_EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
state.ready=Selected for Development
state.in-progress=In Progress
state.in-review=In Review
state.blocked=Blocked
state.backlog=Backlog
state.released=Released
state.done=Done
state.cancelled=Won't Do
field.size=label:size
field.risk=label:risk
field.acceptance=description
field.metric=customfield_10077
list_cap=200
CONF_EOF
    git add -A
    git commit -q -m "fixture: jira backend"
  )
  git -C "$bd_jclone" push -q origin HEAD:refs/heads/main
  bd_stub="$bd_base/stub"; mkdir -p "$bd_stub"
  # a configurable stub: reads its behaviour off env vars so each leg can reconfigure it.
  cat > "$bd_stub/tracker-jira.sh" <<'STUB_EOF'
#!/bin/sh
set -eu
log="${STUB_LOG:-/dev/null}"
echo "$*" >> "$log"
case "$1" in
  get-issue)
    _cur="${STUB_STATE:-In Progress}"
    if [ -n "${STUB_STATE_FILE:-}" ] && [ -f "$STUB_STATE_FILE" ]; then _cur=$(cat "$STUB_STATE_FILE"); fi
    if [ "$_cur" = "denied" ]; then exit 2; fi
    printf 'key\t%s\n' "$5"
    printf 'status-id\t3\n'
    printf 'status-name\t%s\n' "$_cur"
    exit 0 ;;
  assign-self)
    [ "${STUB_ASSIGN_FAIL:-0}" = 1 ] && exit 1
    exit 0 ;;
  transition)
    [ "${STUB_TRANSITION_FAIL:-0}" = 1 ] && exit 1
    # rc 5 = the adapter's diagnosed refusal: ONE fixed sentence on stderr (TRACKER-REQUIRED-FIELDS-DISCOVERY)
    if [ "${STUB_TRANSITION_RC:-0}" = 5 ]; then printf '%s\n' "${STUB_TRANSITION_ERR:-refused: stub transition}" >&2; exit 5; fi
    STUB_STATE=$6
    if [ -n "${STUB_STATE_FILE:-}" ]; then printf '%s' "$STUB_STATE" > "$STUB_STATE_FILE"; fi
    exit 0 ;;
  create)
    [ "${STUB_CREATE_FAIL:-0}" = 1 ] && exit 1
    # the fields fragment board.sh pipes in on STDIN (arg 7 is `-`) — a leg compares it byte-for-byte
    if [ -n "${STUB_BODY_FILE:-}" ]; then cat > "$STUB_BODY_FILE"; else cat > /dev/null; fi
    printf '%s\n' "${STUB_CREATED_KEY:-AB-99}"
    exit 0 ;;
  create-meta)
    # one recorded meta file per issue type: $STUB_CM_DIR/<type>.txt. rc 3 = the type is not in the project,
    # rc 4 = ambiguous (via STUB_CM_RC), any other non-zero = unverified with the adapter's own sentence on stderr
    if [ "${STUB_CM_RC:-0}" != 0 ]; then echo "unverified: stub create-meta failure" >&2; exit "$STUB_CM_RC"; fi
    [ -f "$STUB_CM_DIR/$5.txt" ] || { echo "refused: the issue type is not in this project's create-meta" >&2; exit 3; }
    case "$5" in
      Task) _tid=10003 ;;
      Story) _tid=10004 ;;
      *) _tid=10009 ;;
    esac
    printf '#type-id\t%s\n' "$_tid"
    cat "$STUB_CM_DIR/$5.txt"
    exit 0 ;;
  required-fields)
    # `required-fields <base> <flavour> <project> <type>`: the type-id line, then the leg's recorded required
    # lines from $STUB_RF_DIR/<type>.txt (none = nothing required); STUB_RF_RC non-zero = unverified
    if [ "${STUB_RF_RC:-0}" != 0 ]; then echo "unverified: stub required-fields failure" >&2; exit "$STUB_RF_RC"; fi
    printf '#type-id\t10003\n'
    if [ -n "${STUB_RF_DIR:-}" ] && [ -f "$STUB_RF_DIR/$5.txt" ]; then cat "$STUB_RF_DIR/$5.txt"; fi
    exit 0 ;;
  writable-create-keys)
    # the adapter's closed set; STUB_WCK names a file to narrow/replace it
    if [ -n "${STUB_WCK:-}" ] && [ -f "$STUB_WCK" ]; then cat "$STUB_WCK"; exit 0; fi
    printf 'customfield_N\npriority\ncomponents\nfixVersions\nduedate\nlabels\nparent\ndescription\n'
    exit 0 ;;
  get-fields)
    # the post-read: prints what the leg says the tracker holds (rc 2 when the leg sets none)
    [ -n "${STUB_GF:-}" ] && [ -f "$STUB_GF" ] || exit 2
    cat "$STUB_GF"
    exit 0 ;;
  *) exit 2 ;;
esac
STUB_EOF
  chmod +x "$bd_stub/tracker-jira.sh"
  _saved_jira=$BD_JIRA_SH
  BD_JIRA_SH="$bd_stub/tracker-jira.sh"

  # These legs call do_claim/do_move/do_create DIRECTLY, IN-PROCESS (never a spawned board.sh),
  # for the same reason start.sh's classifier stub legs call st_classify in-process: BD_JIRA_SH is
  # a plain shell variable (never read from the environment by a fresh process — see the header),
  # so only an in-process call sees this selftest's re-pointed value.
  # leg (j-claim): a good claim composes claim-ref + assign + transition, proven by post-read.
  # STUB_STATE_FILE makes the stub STATEFUL: pre-read sees the initial state (not yet claimed),
  # the transition call overwrites it, and the post-read then sees the NEW state — proving
  # board.sh's own order (pre-read -> ref -> tracker write -> post-read), not a static fixture.
  bd_sf1="$bd_base/.sf1"; printf 'Selected for Development' > "$bd_sf1"
  bd_out=$(cd "$bd_jclone" && STUB_STATE_FILE="$bd_sf1" do_claim ROW-JIRA-1 2>&1); bd_rc=$?
  if [ "$bd_rc" -eq 0 ]; then bd_pass "leg jira/claim: claim-ref + tracker write + proven post-read succeeds"
  else bd_fail_ "leg jira/claim: rc=$bd_rc out=[$bd_out]"; fi
  if git ls-remote "$bd_remote" refs/claims/ROW-JIRA-1 2>/dev/null | grep -q refs/claims/ROW-JIRA-1; then
    bd_pass "leg jira/claim-ref: the git ref was taken FIRST (S-5 order) — present on the fixture remote"
  else
    bd_fail_ "leg jira/claim-ref: refs/claims/ROW-JIRA-1 absent after a successful jira claim"
  fi

  # leg (j-claim-compensate): the tracker write fails -> claim-ref is compensated (S-5), rc non-zero.
  bd_out=$(cd "$bd_jclone" && STUB_STATE='Selected for Development' STUB_TRANSITION_FAIL=1 do_claim ROW-JIRA-2 2>&1); bd_rc=$?
  if [ "$bd_rc" -ne 0 ]; then bd_pass "leg jira/claim-fail: a failed tracker write yields non-zero"
  else bd_fail_ "leg jira/claim-fail: a failed tracker write wrongly returned 0"; fi
  if git ls-remote "$bd_remote" refs/claims/ROW-JIRA-2 2>/dev/null | grep -q refs/claims/ROW-JIRA-2; then
    bd_fail_ "leg jira/claim-fail-compensated: refs/claims/ROW-JIRA-2 was LEFT BEHIND after a failed tracker write (S-5 compensation broke)"
  else
    bd_pass "leg jira/claim-fail-compensated: the claim ref was compensated (deleted) after the tracker write failed (S-5)"
  fi

  # leg (j-claim-preread-refuse): the pre-read already shows the target state -> refused before
  # any ref is pushed (a cheap proxy for "a human already holds it").
  bd_out=$(cd "$bd_jclone" && STUB_STATE='In Progress' do_claim ROW-JIRA-3 2>&1); bd_rc=$?
  if [ "$bd_rc" -eq 3 ]; then bd_pass "leg jira/preread-refuse: a row already In Progress in the tracker is refused before any ref push (rc 3)"
  else bd_fail_ "leg jira/preread-refuse: expected rc 3, got rc=$bd_rc out=[$bd_out]"; fi
  if git ls-remote "$bd_remote" refs/claims/ROW-JIRA-3 2>/dev/null | grep -q refs/claims/ROW-JIRA-3; then
    bd_fail_ "leg jira/preread-refuse-noref: a pre-read refusal wrongly pushed a claim ref"
  else
    bd_pass "leg jira/preread-refuse-noref: a pre-read refusal pushed NO ref"
  fi

  # leg (j-move): a §4.1 token resolves to the conf's state name and is proven by post-read.
  bd_out=$(cd "$bd_jclone" && STUB_STATE=Done do_move ROW-JIRA-4 'done' 2>&1); bd_rc=$?
  if [ "$bd_rc" -eq 0 ]; then bd_pass "leg jira/move: a §4.1 token resolves + transitions + proves via post-read"
  else bd_fail_ "leg jira/move: rc=$bd_rc out=[$bd_out]"; fi

  # leg (j-move-backward): a backward move (done -> backlog) is first-class, not special-cased.
  bd_out=$(cd "$bd_jclone" && STUB_STATE=Backlog do_move ROW-JIRA-5 backlog 2>&1); bd_rc=$?
  if [ "$bd_rc" -eq 0 ]; then bd_pass "leg jira/move-backward: a backward move (-> backlog) is first-class, not refused"
  else bd_fail_ "leg jira/move-backward: rc=$bd_rc out=[$bd_out]"; fi

  # leg (j-move-badtoken): a non-§4.1 token is refused offline, before any tracker call.
  bd_out=$(cd "$bd_jclone" && STUB_LOG="$bd_base/.movelog" do_move ROW-JIRA-6 "not a real state" 2>&1); bd_rc=$?
  if [ "$bd_rc" -eq 2 ] && [ ! -s "$bd_base/.movelog" ]; then
    bd_pass "leg jira/move-badtoken: a non-§4.1 state token is refused before any tracker call"
  else
    bd_fail_ "leg jira/move-badtoken: rc=$bd_rc, dispatched=$([ -s "$bd_base/.movelog" ] && echo yes || echo no)"
  fi

  # leg (j-move-postread-mismatch): the transition call succeeds but the post-read proves a
  # DIFFERENT state -> treated as unproven, non-zero.
  bd_out=$(cd "$bd_jclone" && STUB_STATE='Selected for Development' do_move ROW-JIRA-7 'done' 2>&1); bd_rc=$?
  if [ "$bd_rc" -ne 0 ]; then bd_pass "leg jira/move-postread-mismatch: a post-read that does not confirm the new state is non-zero"
  else bd_fail_ "leg jira/move-postread-mismatch: wrongly returned 0 despite a mismatched post-read"; fi

  # ── create legs (BOARD-CREATE-HONOURS-FIELD-MAP): per-type recorded meta files + a scriptable
  # post-read; every "refused" leg asserts ZERO `create` calls reached the stub (the POST). ─────────
  bd_cc="$bd_base/jira-clone-create"
  git clone -q "$bd_remote" "$bd_cc" 2>/dev/null
  (
    cd "$bd_cc"
    git config user.name "Fixture Dev"; git config user.email "dev@example.com"; git config commit.gpgsign false
    mkdir -p .kit
    printf 'Backlog backend: jira\n' > CLAUDE.md
    : > .kit/tracker.conf
    git add -A
    git commit -q -m "fixture: jira backend, create legs"
  )
  bd_cmdir="$bd_base/cm"; mkdir -p "$bd_cmdir/dc" "$bd_cmdir/nolabels" "$bd_cmdir/nodesc" "$bd_cmdir/num" "$bd_cmdir/str"
  bd_cm_cur="$bd_cmdir"; bd_cm_rc_cur=0
  bd_cm_lines() { # <type> <size-id> <risk-id>
    printf '%s\tcustomfield_%s\toption\tSize\tXS|S|M|L|XL\n%s\tcustomfield_%s\toption\tRisk\tLow|Medium|High\n%s\tdescription\tstring\tDescription\t\n%s\tlabels\tarray\tLabels\t\n%s\tparent\tissuelink\tParent\t\n' "$1" "$2" "$1" "$3" "$1" "$1" "$1"
  }
  bd_cm_lines Task 10046 10047 > "$bd_cmdir/Task.txt"
  bd_cm_lines Story 10043 10044 > "$bd_cmdir/Story.txt"
  printf 'Task\tcustomfield_10200\toption\tSize\tS|M\nTask\tdescription\tstring\tDescription\t\nTask\tlabels\tarray\tLabels\t\nTask\tcustomfield_10100\tany\tEpic Link\t\n' > "$bd_cmdir/dc/Task.txt"
  bd_cr_gf="$bd_base/.gf"; bd_cr_body="$bd_base/.crbody"; bd_cr_log="$bd_base/.crlog"
  # required-fields fixtures (TRACKER-REQUIRED-FIELDS-DISCOVERY): $bd_rfdir/<type>.txt, one required line per field;
  # bd_cx = extra conf lines (create.<token>=...) appended by bd_conf; bd_rf_rc_cur / bd_wck_cur script the stub
  bd_rfdir="$bd_base/rf"; mkdir -p "$bd_rfdir"; bd_cx=""; bd_rf_rc_cur=0; bd_wck_cur=""
  # bd_conf <size-map|-> <risk-map|-> <flavour> [create.issuetype]: rewrite the clone's conf for one leg
  bd_conf() {
    { printf 'version=1\nbackend=jira\nbase_url=https://ex.atlassian.net\nflavour=%s\nauth=basic\nproject=AB\nstate.ready=Selected for Development\nstate.in-progress=In Progress\nstate.done=Done\n' "$3"
      [ "$1" = - ] || printf 'field.size=%s\n' "$1"
      [ "$2" = - ] || printf 'field.risk=%s\n' "$2"
      [ -z "${4:-}" ] || printf 'create.issuetype=%s\n' "$4"
      [ -z "$bd_cx" ] || printf '%s\n' "$bd_cx"
    } > "$bd_cc/.kit/tracker.conf"
  }
  # bd_posts: how many `create` (the POST) calls the stub saw this leg; create-meta is a different verb
  bd_posts() { grep -c '^create ' "$bd_cr_log" 2>/dev/null || true; }
  # bd_cr <args…>: one create, in-process, stderr folded in; the stub log/body/gf are reset first
  bd_cr() {
    : > "$bd_cr_log"; rm -f "$bd_cr_body"
    bd_out=$(cd "$bd_cc" && STUB_LOG="$bd_cr_log" STUB_BODY_FILE="$bd_cr_body" STUB_CM_DIR="$bd_cm_cur" STUB_CM_RC="$bd_cm_rc_cur" STUB_GF="$bd_cr_gf" STUB_RF_DIR="$bd_rfdir" STUB_RF_RC="$bd_rf_rc_cur" STUB_WCK="$bd_wck_cur" do_create "$@" 2>&1); bd_rc=$?
  }
  printf 'issuetype\tTask\nparent\tAB-5\ncustomfield_10046\tS\ncustomfield_10047\tLow\n' > "$bd_cr_gf"

  # leg (create-select): size/risk select fields, parent and a multi-line description -> the exact
  # fragment (a case-insensitive `s` becomes the allowed value `S`), ONE POST, proven by the post-read.
  bd_conf customfield_10046 customfield_10047 cloud
  bd_cr --title "a new row" --size s --risk low --parent AB-5 --description "line one
line two"
  bd_want='{"customfield_10046":{"value":"S"},"customfield_10047":{"value":"Low"},"parent":{"key":"AB-5"},"description":{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"line one"}]},{"type":"paragraph","content":[{"type":"text","text":"line two"}]}]}}'
  if [ "$bd_rc" -eq 0 ] && [ "$(cat "$bd_cr_body")" = "$bd_want" ] && [ "$(bd_posts)" = 1 ] && printf '%s' "$bd_out" | grep -q 'AB-99'; then
    bd_pass "leg jira/create-select: select Size/Risk (case-insensitive -> canonical), parent and an ADF description build the exact fragment, one POST, proven by post-read"
  else bd_fail_ "leg jira/create-select: rc=$bd_rc posts=$(bd_posts) body=[$(cat "$bd_cr_body" 2>/dev/null)] out=[$bd_out]"; fi

  # leg (create-label): label mappings write `<prefix>:<value>` labels (the reader's own grammar)
  bd_conf label:size label:risk cloud
  printf 'issuetype\tTask\nlabels\trisk:low size:S\n' > "$bd_cr_gf"
  bd_cr --title "x" --size S --risk low
  if [ "$bd_rc" -eq 0 ] && [ "$(cat "$bd_cr_body")" = '{"labels":["size:S","risk:low"]}' ] && [ "$(bd_posts)" = 1 ]; then
    bd_pass "leg jira/create-label: label:size / label:risk write the labels size:S and risk:low, proven by the post-read"
  else bd_fail_ "leg jira/create-label: rc=$bd_rc body=[$(cat "$bd_cr_body" 2>/dev/null)] out=[$bd_out]"; fi
  bd_cr --title "x" --size 'a b'
  if [ "$bd_rc" -eq 2 ] && [ "$(bd_posts)" = 0 ]; then
    bd_pass "leg jira/create-label-grammar: a label value outside [A-Za-z0-9_-]{1,32} is refused before any POST"
  else bd_fail_ "leg jira/create-label-grammar: rc=$bd_rc posts=$(bd_posts) out=[$bd_out]"; fi

  # leg (create-wrong-type): the conf maps Task's field ids; --type Story's screen has other ids ->
  # refused BEFORE any POST, naming Story's own id. The create-meta call proves the check really ran.
  bd_conf customfield_10046 customfield_10047 cloud
  bd_cr --title "x" --type Story --size S
  if [ "$bd_rc" -eq 2 ] && [ "$(bd_posts)" = 0 ] && grep -q '^create-meta .* Story$' "$bd_cr_log" \
     && printf '%s' "$bd_out" | grep -q 'customfield_10043'; then
    bd_pass "leg jira/create-wrong-type: a Task-mapped conf with --type Story is refused with ZERO POSTs, naming Story's own customfield_10043"
  else bd_fail_ "leg jira/create-wrong-type: rc=$bd_rc posts=$(bd_posts) out=[$bd_out]"; fi

  # leg (create-bad-value): a value outside the select's allowed set -> refused, the set listed, zero POSTs
  bd_cr --title "x" --size XXL
  if [ "$bd_rc" -eq 2 ] && [ "$(bd_posts)" = 0 ] && printf '%s' "$bd_out" | grep -qF 'XS, S, M, L, XL'; then
    bd_pass "leg jira/create-bad-value: a select value outside the allowed set is refused, the allowed set listed, zero POSTs"
  else bd_fail_ "leg jira/create-bad-value: rc=$bd_rc posts=$(bd_posts) out=[$bd_out]"; fi

  # leg (create-unmapped): field.size=none, or unmapped, with --size -> refused, never silently dropped
  bd_conf none - cloud
  bd_cr --title "x" --size S
  bd_rc1=$bd_rc; bd_p1=$(bd_posts); bd_o1=$bd_out
  bd_cr --title "x" --risk low
  if [ "$bd_rc1" -eq 2 ] && [ "$bd_p1" = 0 ] && [ "$bd_rc" -eq 2 ] && [ "$(bd_posts)" = 0 ] \
     && printf '%s' "$bd_o1" | grep -qF 'field.size is not mapped to a writable field' \
     && printf '%s' "$bd_out" | grep -qF 'field.risk is not mapped to a writable field'; then
    bd_pass "leg jira/create-unmapped: --size under field.size=none and --risk with no field.risk are refused (never dropped), zero POSTs"
  else bd_fail_ "leg jira/create-unmapped: rc1=$bd_rc1 rc=$bd_rc posts=$bd_p1/$(bd_posts) o1=[$bd_o1] out=[$bd_out]"; fi

  # leg (create-postread-mismatch): the tracker reads back a DIFFERENT Size -> rc 1, the created key named
  bd_conf customfield_10046 customfield_10047 cloud
  printf 'issuetype\tTask\ncustomfield_10046\tM\ncustomfield_10047\tLow\n' > "$bd_cr_gf"
  bd_cr --title "x" --size S --risk low
  if [ "$bd_rc" -eq 1 ] && [ "$(bd_posts)" = 1 ] && printf '%s' "$bd_out" | grep -q 'AB-99' && printf '%s' "$bd_out" | grep -qi 'did NOT prove'; then
    bd_pass "leg jira/create-postread-mismatch: a post-read that disagrees on Size exits 1 and names the created key AB-99"
  else bd_fail_ "leg jira/create-postread-mismatch: rc=$bd_rc posts=$(bd_posts) out=[$bd_out]"; fi
  printf 'issuetype\tBug\ncustomfield_10046\tS\ncustomfield_10047\tLow\n' > "$bd_cr_gf"
  bd_cr --title "x" --size S --risk low
  if [ "$bd_rc" -eq 1 ] && printf '%s' "$bd_out" | grep -q 'AB-99'; then
    bd_pass "leg jira/create-postread-type: a post-read that disagrees on the issue type exits 1 and names the key"
  else bd_fail_ "leg jira/create-postread-type: rc=$bd_rc out=[$bd_out]"; fi

  # leg (create-type): the type is --type, else create.issuetype; a type the project lacks is refused
  # (zero POSTs); an unreadable create-meta is unverified (rc 1, zero POSTs)
  bd_conf customfield_10043 customfield_10044 cloud Story
  printf 'issuetype\tStory\ncustomfield_10043\tXS\n' > "$bd_cr_gf"
  bd_cr --title "x" --size xs
  # the type is created BY ID (create-meta resolved Story -> 10004) and the fragment goes in on stdin (`-`)
  if [ "$bd_rc" -eq 0 ] && grep -q '^create-meta .* Story$' "$bd_cr_log" && grep -q '^create .* 10004 -$' "$bd_cr_log"; then
    bd_pass "leg jira/create-type-conf: create.issuetype=Story drives the create-meta lookup; the card is created by the resolved id 10004, fragment on stdin"
  else bd_fail_ "leg jira/create-type-conf: rc=$bd_rc out=[$bd_out]"; fi
  bd_cr --title "x" --type Epic
  bd_rc1=$bd_rc; bd_p1=$(bd_posts); bd_o1=$bd_out
  bd_cm_rc_cur=2; bd_cr --title "x"; bd_cm_rc_cur=0
  bd_rc2=$bd_rc; bd_p2=$(bd_posts); bd_o2=$bd_out
  bd_cm_rc_cur=1; bd_cr --title "x"; bd_cm_rc_cur=0
  bd_rc3=$bd_rc; bd_o3=$bd_out
  bd_cm_rc_cur=4; bd_cr --title "x"; bd_cm_rc_cur=0
  if [ "$bd_rc1" -eq 2 ] && [ "$bd_p1" = 0 ] && printf '%s' "$bd_o1" | grep -qF 'lacks Create permission' \
     && [ "$bd_rc2" -eq 1 ] && [ "$bd_p2" = 0 ] && printf '%s' "$bd_o2" | grep -qF 'unverified: stub create-meta failure' \
     && [ "$bd_rc3" -eq 1 ] && printf '%s' "$bd_o3" | grep -qF 'unverified' \
     && [ "$bd_rc" -eq 2 ] && [ "$(bd_posts)" = 0 ] && printf '%s' "$bd_out" | grep -qF 'ambiguous'; then
    bd_pass "leg jira/create-type-absent: adapter rc 3 -> type-absent cure (rc 2, names the Create-permission cause); rc 1/2 -> unverified with the adapter's sentence (rc 1); rc 4 -> ambiguous (rc 2); zero POSTs each"
  else bd_fail_ "leg jira/create-type-absent: rc=$bd_rc1/$bd_rc2/$bd_rc3/$bd_rc posts=$bd_p1/$bd_p2/$(bd_posts) o1=[$bd_o1] o2=[$bd_o2] o=[$bd_out]"; fi

  # leg (create-dc): Data Center has no `parent` (Epic Link) -> --parent refused with a named cure; a plain-string description
  bd_conf customfield_10200 - datacenter
  bd_cm_cur="$bd_cmdir/dc"; bd_cr --title "x" --parent AB-5
  bd_rc1=$bd_rc; bd_p1=$(bd_posts); bd_o1=$bd_out
  printf 'issuetype\tTask\ncustomfield_10200\tS\n' > "$bd_cr_gf"
  bd_cr --title "x" --size s --description "plain text"; bd_cm_cur="$bd_cmdir"
  if [ "$bd_rc1" -eq 2 ] && [ "$bd_p1" = 0 ] && printf '%s' "$bd_o1" | grep -qF 'Epic Link' \
     && [ "$bd_rc" -eq 0 ] && [ "$(cat "$bd_cr_body")" = '{"customfield_10200":{"value":"S"},"description":"plain text"}' ]; then
    bd_pass "leg jira/create-dc: Data Center --parent is refused naming Epic Link (zero POSTs); its description is a plain string, not ADF"
  else bd_fail_ "leg jira/create-dc: rc1=$bd_rc1 p1=$bd_p1 o1=[$bd_o1] rc=$bd_rc body=[$(cat "$bd_cr_body" 2>/dev/null)] out=[$bd_out]"; fi

  # leg (create-offline): a bad --type, a bad --parent and an oversized --description refuse (rc 2) before
  # ANY tracker call (the stub log stays empty)
  bd_conf label:size label:risk cloud
  bd_big=$(awk 'BEGIN{for(i=0;i<32001;i++) printf "a"}')
  bd_cr --title "x" --type 'Ta"sk'; bd_rc1=$bd_rc; bd_s1=$(wc -c < "$bd_cr_log" | tr -d ' ')
  bd_cr --title "x" --parent 'not a key'; bd_rc2=$bd_rc; bd_s2=$(wc -c < "$bd_cr_log" | tr -d ' ')
  bd_cr --title "x" --description "$bd_big"; bd_rc3=$bd_rc; bd_s3=$(wc -c < "$bd_cr_log" | tr -d ' ')
  if [ "$bd_rc1" -eq 2 ] && [ "$bd_rc2" -eq 2 ] && [ "$bd_rc3" -eq 2 ] && [ "$bd_s1" = 0 ] && [ "$bd_s2" = 0 ] && [ "$bd_s3" = 0 ]; then
    bd_pass "leg jira/create-offline: a quote in --type, a bad --parent and a 32001-byte --description each refuse rc 2 with no tracker call"
  else bd_fail_ "leg jira/create-offline: rc=$bd_rc1/$bd_rc2/$bd_rc3 stubbytes=$bd_s1/$bd_s2/$bd_s3"; fi

  # legs (create-gaps): each refusal is rc 2 with ZERO POSTs unless stated
  printf 'Task\tcustomfield_10046\toption\tSize\tXS|S|M|L|XL\nTask\tdescription\tstring\tDescription\t\n' > "$bd_cmdir/nolabels/Task.txt"
  printf 'Task\tcustomfield_10046\toption\tSize\tXS|S|M|L|XL\nTask\tlabels\tarray\tLabels\t\n' > "$bd_cmdir/nodesc/Task.txt"
  printf 'Task\tcustomfield_10016\tnumber\tStory point estimate\t\nTask\tcustomfield_10046\toption\tSize\tXS|S|M|L|XL\tx\nTask\tcustomfield_10050\toption\tRisk\tLow|Medium\n' > "$bd_cmdir/num/Task.txt"
  printf 'Task\tcustomfield_10300\tstring\tSize\t\nTask\tcustomfield_10046\toption\t?\tXS|M\n' > "$bd_cmdir/str/Task.txt"
  bd_conf label:size - cloud
  bd_cm_cur="$bd_cmdir/nolabels"; bd_cr --title "x" --size S; bd_cm_cur="$bd_cmdir"
  bd_rc1=$bd_rc; bd_p1=$(bd_posts); bd_o1=$bd_out
  bd_conf - - cloud
  bd_cm_cur="$bd_cmdir/nodesc"; bd_cr --title "x" --description "d"; bd_cm_cur="$bd_cmdir"
  if [ "$bd_rc1" -eq 2 ] && [ "$bd_p1" = 0 ] && printf '%s' "$bd_o1" | grep -qF 'no labels field' \
     && [ "$bd_rc" -eq 2 ] && [ "$(bd_posts)" = 0 ] && printf '%s' "$bd_out" | grep -qF 'no description field'; then
    bd_pass "leg jira/create-no-screen: label mapping with no labels on the screen, and --description with no description on it, are refused (rc 2, zero POSTs)"
  else bd_fail_ "leg jira/create-no-screen: rc=$bd_rc1/$bd_rc posts=$bd_p1/$(bd_posts) o1=[$bd_o1] out=[$bd_out]"; fi
  bd_conf customfield_10016 - cloud
  bd_cm_cur="$bd_cmdir/num"; bd_cr --title "x" --size 3; bd_cm_cur="$bd_cmdir"
  if [ "$bd_rc" -eq 2 ] && [ "$(bd_posts)" = 0 ] && printf '%s' "$bd_out" | grep -qF "schema type 'number'"; then
    bd_pass "leg jira/create-schema-number: a mapped customfield of schema type number is refused naming the type (rc 2, zero POSTs)"
  else bd_fail_ "leg jira/create-schema-number: rc=$bd_rc posts=$(bd_posts) out=[$bd_out]"; fi
  bd_conf customfield_10046 - cloud
  bd_cr --title "x" --size 'S;x'
  if [ "$bd_rc" -eq 2 ] && [ "$(bd_posts)" = 0 ] && printf '%s' "$bd_out" | grep -qF 'must match [A-Za-z0-9 _.-]{1,64}'; then
    bd_pass "leg jira/create-value-grammar: a customfield value outside [A-Za-z0-9 _.-]{1,64} is refused (rc 2, zero POSTs)"
  else bd_fail_ "leg jira/create-value-grammar: rc=$bd_rc posts=$(bd_posts) out=[$bd_out]"; fi
  # the string write path SUCCEEDS: written as-is, body pinned, proven by the post-read; the select with a
  # `?`-named sibling field and a dropped option still lists only what the screen carried
  bd_conf customfield_10300 - cloud
  printf 'issuetype\tTask\ncustomfield_10300\tBig one\n' > "$bd_cr_gf"
  bd_cm_cur="$bd_cmdir/str"; bd_cr --title "x" --size "Big one"; bd_cm_cur="$bd_cmdir"
  if [ "$bd_rc" -eq 0 ] && [ "$(cat "$bd_cr_body")" = '{"customfield_10300":"Big one"}' ] && [ "$(bd_posts)" = 1 ]; then
    bd_pass "leg jira/create-string: a string customfield is written as-is ({\"customfield_10300\":\"Big one\"}), one POST, proven by the post-read; an unmapped odd-named field does not block it"
  else bd_fail_ "leg jira/create-string: rc=$bd_rc posts=$(bd_posts) body=[$(cat "$bd_cr_body" 2>/dev/null)] out=[$bd_out]"; fi
  bd_conf customfield_10046 - cloud
  bd_cm_cur="$bd_cmdir/str"; bd_cr --title "x" --size L; bd_cm_cur="$bd_cmdir"
  if [ "$bd_rc" -eq 2 ] && [ "$(bd_posts)" = 0 ] && printf '%s' "$bd_out" | grep -qF 'allowed: XS, M (printable ASCII only)'; then
    bd_pass "leg jira/create-bad-value-ascii: the refusal lists the allowed ASCII values and says so (a dropped non-ASCII option is not shown)"
  else bd_fail_ "leg jira/create-bad-value-ascii: rc=$bd_rc posts=$(bd_posts) out=[$bd_out]"; fi
  # a label the post-read does not show -> rc 1, the key named
  bd_conf label:size label:risk cloud
  printf 'issuetype\tTask\nlabels\tsize:S\n' > "$bd_cr_gf"
  bd_cr --title "x" --size S --risk low
  if [ "$bd_rc" -eq 1 ] && [ "$(bd_posts)" = 1 ] && printf '%s' "$bd_out" | grep -q 'AB-99' && printf '%s' "$bd_out" | grep -qF "label 'risk:low'"; then
    bd_pass "leg jira/create-postread-label: a label missing from the post-read exits 1 and names the key AB-99"
  else bd_fail_ "leg jira/create-postread-label: rc=$bd_rc posts=$(bd_posts) out=[$bd_out]"; fi
  # --description of 2002 lines (2001 newlines, over the 2000 bound) is refused offline (the byte bound is 32000)
  bd_lines=$(awk 'BEGIN{for(i=0;i<2002;i++) print "l"}')
  bd_cr --title "x" --description "$bd_lines"
  if [ "$bd_rc" -eq 2 ] && [ ! -s "$bd_cr_log" ] && printf '%s' "$bd_out" | grep -qF '2000-line'; then
    bd_pass "leg jira/create-lines: a 2001-line --description is refused offline (rc 2, no tracker call)"
  else bd_fail_ "leg jira/create-lines: rc=$bd_rc out=[$bd_out]"; fi
  # a bad-value refusal keeps its allowed-set listing (and now says printable ASCII)

  # leg (j-create-fail): the tracker create call fails -> non-zero, no post-read claimed.
  bd_conf label:size label:risk cloud
  bd_out=$(cd "$bd_cc" && STUB_CM_DIR="$bd_cmdir" STUB_CREATE_FAIL=1 do_create --title "x" 2>&1); bd_rc=$?
  if [ "$bd_rc" -ne 0 ]; then bd_pass "leg jira/create-fail: a failed tracker create yields non-zero"
  else bd_fail_ "leg jira/create-fail: wrongly returned 0"; fi

  # ── required-field legs (TRACKER-REQUIRED-FIELDS-DISCOVERY): the adapter's `required-fields` + conf
  # `create.<id>` defaults + --field, resolved BEFORE the POST; every refused leg asserts ZERO POSTs. ───
  printf 'issuetype\tTask\n' > "$bd_cr_gf"
  bd_rf() { printf '%b\n' "$1" > "$bd_rfdir/Task.txt"; }   # the Task required lines for the next bd_cr
  bd_body_leg() { # <label> <want-body>: created (rc 0), ONE POST, the exact fragment
    if [ "$bd_rc" -eq 0 ] && [ "$(cat "$bd_cr_body" 2>/dev/null)" = "$2" ] && [ "$(bd_posts)" = 1 ]; then bd_pass "leg jira/create-required-$1"
    else bd_fail_ "leg jira/create-required-$1: rc=$bd_rc posts=$(bd_posts) body=[$(cat "$bd_cr_body" 2>/dev/null)] want=[$2] out=[$bd_out]"; fi
  }
  bd_refuse_leg() { # <label> <needle>...: rc 1, ZERO POSTs, every needle in the output
    _rl_label=$1; shift; _rl_ok=1
    if [ "$bd_rc" -ne 1 ] || [ "$(bd_posts)" != 0 ]; then _rl_ok=0; fi
    for _rl_n in "$@"; do printf '%s' "$bd_out" | grep -qF -e "$_rl_n" || _rl_ok=0; done
    if [ "$_rl_ok" = 1 ]; then bd_pass "leg jira/create-required-$_rl_label"
    else bd_fail_ "leg jira/create-required-$_rl_label: rc=$bd_rc posts=$(bd_posts) out=[$bd_out]"; fi
  }
  bd_kind_leg() { # <label> <id> <kind> <allowed> <conf-value> <want-json> <flavour> <read-back>: one kind's value shape + its proof
    printf '%s\t%s\tField F\t%s\tcomplete\n' "$2" "$3" "$4" > "$bd_rfdir/Task.txt"
    printf 'issuetype\tTask\n%s\t%s\n' "$2" "$8" > "$bd_cr_gf"
    bd_cx="create.$2=$5"; bd_conf - - "$7"; bd_cr --title x; bd_cx=""
    bd_body_leg "$1" "{\"$2\":$6}"
  }
  # unmapped: refused with the field named, the exact conf line to paste, the allowed values, and the agentic pointer
  bd_conf - - cloud
  bd_rf 'customfield_10100\tstring\tTeam name\t\tcomplete'
  bd_cr --title x
  bd_refuse_leg unmapped "'Team name' (customfield_10100)" "create.customfield_10100=<value>" "create.customfield_10100=prompt" \
    "the value is your team's: read the project CLAUDE.md, and if it is silent ask the owner; use prompt for a per-card value" "nothing was created"
  # two unmapped fields: BOTH named in the ONE run (never one per try); the allowed set shows when Jira listed one
  bd_rf 'customfield_10100\tstring\tTeam name\t\tcomplete\ncustomfield_10101\toption\tPhase\tAlpha|Beta\tcomplete'
  bd_cr --title x
  bd_refuse_leg two-unmapped "'Team name' (customfield_10100)" "'Phase' (customfield_10101)" "(allowed: Alpha, Beta)"
  # a mapped default is written, correctly shaped, ONE POST
  bd_rf 'customfield_10100\tstring\tTeam name\t\tcomplete'
  printf 'issuetype\tTask\ncustomfield_10100\tAcme\n' > "$bd_cr_gf"
  bd_cx='create.customfield_10100=Acme'; bd_conf - - cloud; bd_cr --title x; bd_cx=""
  bd_body_leg mapped-default '{"customfield_10100":"Acme"}'
  # no required field at all: the create is exactly what it was before this feature
  rm -f "$bd_rfdir/Task.txt"; bd_conf - - cloud; bd_cr --title x
  bd_body_leg none-required '{}'
  # one leg per kind's JSON shape
  # (the last two args: the flavour, and what the post-read shows — an id:<N> value is proven by presence only)
  bd_kind_leg kind-option customfield_10100 option 'Alpha|Beta' Beta '{"value":"Beta"}' cloud Beta
  bd_kind_leg kind-option-id customfield_10100 option 'Alpha|Beta' id:10028 '{"id":"10028"}' cloud Whatever
  bd_kind_leg kind-option-array customfield_10100 option-array 'Alpha|Beta' Beta '[{"value":"Beta"}]' cloud Beta
  bd_kind_leg kind-priority priority priority 'High|Low' High '{"name":"High"}' cloud High
  bd_kind_leg kind-priority-id priority priority 'High|Low' id:3 '{"id":"3"}' cloud Medium
  bd_kind_leg kind-component components component-array 'Web|Api' Web '[{"name":"Web"}]' cloud Web
  bd_kind_leg kind-version fixVersions version-array 'v1|v2' v2 '[{"name":"v2"}]' cloud v2
  bd_kind_leg kind-string-array labels string-array '' ops '["ops"]' cloud ops
  bd_kind_leg kind-user-cloud customfield_10200 user '' abc123 '{"accountId":"abc123"}' cloud abc123
  bd_kind_leg kind-user-dc customfield_10200 user '' jdoe '{"name":"jdoe"}' datacenter jdoe
  bd_kind_leg kind-team customfield_10001 team '' team-uuid-1 '"team-uuid-1"' cloud team-uuid-1
  bd_kind_leg kind-number customfield_10300 number '' 2.5 '2.5' cloud 2.5
  bd_kind_leg kind-date duedate date '' 2026-10-03 '"2026-10-03"' cloud 2026-10-03
  bd_kind_leg kind-text-cloud customfield_10400 text '' 'Needs review' '{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"Needs review"}]}]}' cloud present
  bd_kind_leg kind-text-dc customfield_10400 text '' 'Needs review' '"Needs review"' datacenter present
  # the post-read PROVES every filled value: a different value read back is the prove mismatch (the card exists, one POST,
  # rc 1); text and id:<N> values are proven by presence only, so an EMPTY read-back is the failure there
  bd_prove_leg() { # <label> <id> <kind> <conf-value> <read-back> <needle>: created, then the post-read disagrees
    printf '%s\t%s\tField F\t\tcomplete\n' "$2" "$3" > "$bd_rfdir/Task.txt"
    printf 'issuetype\tTask\n%s\t%s\n' "$2" "$5" > "$bd_cr_gf"
    bd_cx="create.$2=$4"; bd_conf - - cloud; bd_cr --title x; bd_cx=""
    if [ "$bd_rc" -eq 1 ] && [ "$(bd_posts)" = 1 ] && printf '%s' "$bd_out" | grep -qF -e "$6" && printf '%s' "$bd_out" | grep -qF 'the card exists'; then
      bd_pass "leg jira/create-prove-$1"
    else bd_fail_ "leg jira/create-prove-$1: rc=$bd_rc posts=$(bd_posts) out=[$bd_out]"; fi
  }
  bd_prove_leg mismatch customfield_10100 string Acme Other "did NOT prove customfield_10100 = 'Acme'"
  bd_prove_leg mismatch-priority priority priority High Low "did NOT prove priority = 'High'"
  bd_prove_leg text-absent customfield_10400 text 'Needs review' '' "did NOT prove customfield_10400 is present"
  bd_prove_leg id-absent customfield_10100 option id:10028 '' "did NOT prove customfield_10100 is present"
  # a bad number and a bad date are refused naming the field, zero POSTs
  printf 'customfield_10300\tnumber\tPoints\t\tcomplete\n' > "$bd_rfdir/Task.txt"
  bd_cx='create.customfield_10300=five'; bd_conf - - cloud; bd_cr --title x; bd_cx=""
  bd_refuse_leg bad-number "'Points' (customfield_10300)" "not a number"
  printf 'duedate\tdate\tDue\t\tcomplete\n' > "$bd_rfdir/Task.txt"
  bd_cx='create.duedate=2026-13-40'; bd_conf - - cloud; bd_cr --title x; bd_cx=""
  bd_refuse_leg bad-date "'Due' (duedate)" "YYYY-MM-DD"
  # prompt: refused naming --field and CLAUDE.md; with --field it is created; --field also beats a conf default
  printf 'customfield_10100\tstring\tTeam name\t\tcomplete\n' > "$bd_rfdir/Task.txt"
  bd_cx='create.customfield_10100=prompt'; bd_conf - - cloud
  bd_cr --title x
  bd_refuse_leg prompt "--field customfield_10100=<value>" "CLAUDE.md" "'Team name' (customfield_10100)"
  printf 'issuetype\tTask\ncustomfield_10100\tAcme\n' > "$bd_cr_gf"
  bd_cr --title x --field customfield_10100=Acme
  bd_body_leg prompt-with-field '{"customfield_10100":"Acme"}'
  bd_cx='create.customfield_10100=Old'; bd_conf - - cloud
  printf 'issuetype\tTask\ncustomfield_10100\tNew\n' > "$bd_cr_gf"
  bd_cr --title x --field customfield_10100=New
  bd_body_leg field-beats-default '{"customfield_10100":"New"}'
  bd_cx=""
  # --field: its pair is validated offline (rc 2, no tracker call), and only a REQUIRED writable key is accepted
  bd_conf - - cloud
  bd_cr --title x --field 'bad-token=x'; bd_rc1=$bd_rc; bd_s1=$(wc -c < "$bd_cr_log" | tr -d ' ')
  bd_cr --title x --field customfield_10100=a --field customfield_10100=b; bd_rc2=$bd_rc
  bd_cr --title x --field customfield_10100=prompt; bd_rc3=$bd_rc
  bd_cr --title x --field customfield_10100; bd_rc4=$bd_rc
  if [ "$bd_rc1" -eq 2 ] && [ "$bd_s1" = 0 ] && [ "$bd_rc2" -eq 2 ] && [ "$bd_rc3" -eq 2 ] && [ "$bd_rc4" -eq 2 ]; then
    bd_pass "leg jira/create-field-grammar: --field with a bad token, a repeat, the literal prompt, or no '=' is refused rc 2 before any tracker call"
  else bd_fail_ "leg jira/create-field-grammar: rc=$bd_rc1/$bd_rc2/$bd_rc3/$bd_rc4 stubbytes=$bd_s1"; fi
  bd_cr --title x --field customfield_10999=x
  bd_refuse_leg field-not-required "--field customfield_10999" "not a required field"
  # a value outside Jira's allowed set is refused naming the allowed set; truncated -> NOTE + created; id:N unchecked
  printf 'customfield_10100\toption\tPhase\tAlpha|Beta\tcomplete\n' > "$bd_rfdir/Task.txt"
  bd_cx='create.customfield_10100=Gamma'; bd_conf - - cloud; bd_cr --title x; bd_cx=""
  bd_refuse_leg not-allowed "'Phase' (customfield_10100)" "Gamma" "allowed: Alpha, Beta"
  printf 'customfield_10100\toption\tPhase\tAlpha|Beta\ttruncated\n' > "$bd_rfdir/Task.txt"
  printf 'issuetype\tTask\ncustomfield_10100\tGamma\n' > "$bd_cr_gf"
  bd_cx='create.customfield_10100=Gamma'; bd_conf - - cloud; bd_cr --title x; bd_cx=""
  if [ "$bd_rc" -eq 0 ] && [ "$(cat "$bd_cr_body")" = '{"customfield_10100":{"value":"Gamma"}}' ] && printf '%s' "$bd_out" | grep -qF 'NOTE'; then
    bd_pass "leg jira/create-required-truncated: an incomplete allowed list skips the membership check with a NOTE (never a refusal) and creates"
  else bd_fail_ "leg jira/create-required-truncated: rc=$bd_rc body=[$(cat "$bd_cr_body" 2>/dev/null)] out=[$bd_out]"; fi
  # unsupported kind: the Jira-side cure; a key outside the adapter's writable set: refused naming the set
  printf 'customfield_10500\tunsupported\tCascade\t\tcomplete\n' > "$bd_rfdir/Task.txt"
  bd_conf - - cloud; bd_cr --title x
  bd_refuse_leg unsupported "'Cascade' (customfield_10500)" "cannot write" "a default in Jira, or make it optional"
  printf 'security\tstring\tSecurity level\t\tcomplete\n' > "$bd_rfdir/Task.txt"
  bd_cx='create.security=x'; bd_conf - - cloud; bd_cr --title x; bd_cx=""
  bd_refuse_leg not-writable "'Security level' (security)" "writable: customfield_N priority components fixVersions duedate labels parent description"
  printf 'customfield_10100\tstring\tTeam name\t\tcomplete\n' > "$bd_rfdir/Task.txt"
  printf 'priority\nlabels\n' > "$bd_base/.wck"; bd_wck_cur="$bd_base/.wck"
  bd_conf - - cloud; bd_cr --title x --field customfield_10100=a; bd_wck_cur=""
  bd_refuse_leg field-not-writable "--field customfield_10100" "writable: priority labels"
  # a flag-covered field: required Size without --size names the FLAG (not a conf key); with --size it is covered
  printf 'customfield_10046\toption\tSize\tXS|S|M|L|XL\tcomplete\n' > "$bd_rfdir/Task.txt"
  bd_conf customfield_10046 - cloud; bd_cr --title x
  bd_refuse_leg size-flag "'Size' (customfield_10046)" "--size <s>"
  printf 'issuetype\tTask\ncustomfield_10046\tS\n' > "$bd_cr_gf"
  bd_cr --title x --size S
  bd_body_leg size-covered '{"customfield_10046":{"value":"S"}}'
  printf 'issuetype\tTask\n' > "$bd_cr_gf"
  printf 'description\ttext\tDescription\t\tcomplete\nparent\tissuelink\tParent\t\tcomplete\n' > "$bd_rfdir/Task.txt"
  bd_conf - - cloud; bd_cr --title x
  bd_refuse_leg desc-parent-flags "'Description' (description)" "--description <text>" "'Parent' (parent)" "--parent <KEY>"
  # a --field for a value a flag already sets is refused, not silently shadowed
  printf 'customfield_10046\toption\tSize\tXS|S\tcomplete\n' > "$bd_rfdir/Task.txt"
  bd_conf customfield_10046 - cloud; bd_cr --title x --size S --field customfield_10046=XS
  bd_refuse_leg field-vs-flag "customfield_10046" "already"
  # an unreadable required-fields (adapter rc non-zero) is unverified: refused, never created on a guess
  printf 'customfield_10100\tstring\tTeam name\t\tcomplete\n' > "$bd_rfdir/Task.txt"
  bd_cx='create.customfield_10100=Acme'; bd_conf - - cloud; bd_rf_rc_cur=2; bd_cr --title x; bd_rf_rc_cur=0; bd_cx=""
  bd_refuse_leg unverified "unverified: stub required-fields failure" "nothing was created"
  # R3: the adapter's #dropped sentinel (n required fields it could not name) refuses the create, zero POSTs
  bd_rf '#dropped\t2\ncustomfield_10100\tstring\tTeam name\t\ttruncated'
  bd_cx='create.customfield_10100=Acme'; bd_conf - - cloud; bd_cr --title x; bd_cx=""
  bd_refuse_leg dropped "unverified: the tracker reported 2 required field(s) the kit cannot name; nothing was created."
  # R1: a conf create.description / create.parent is not honoured (flag-only) - a NOTE says so; the create is unchanged
  rm -f "$bd_rfdir/Task.txt"; printf 'issuetype\tTask\n' > "$bd_cr_gf"
  bd_cx='create.description=hello
create.parent=AB-1'; bd_conf - - cloud; bd_cr --title x; bd_cx=""
  if [ "$bd_rc" -eq 0 ] && [ "$(cat "$bd_cr_body" 2>/dev/null)" = '{}' ] && [ "$(bd_posts)" = 1 ] \
     && printf '%s' "$bd_out" | grep -qF 'NOTE: create.description is ignored' && printf '%s' "$bd_out" | grep -qF 'NOTE: create.parent is ignored' \
     && printf '%s' "$bd_out" | grep -qF -e '--description' -e '--parent'; then
    bd_pass "leg jira/create-flag-only-conf: a conf create.description / create.parent is NOT written; a stderr NOTE says it is flag-only (R1)"
  else bd_fail_ "leg jira/create-flag-only-conf: rc=$bd_rc posts=$(bd_posts) body=[$(cat "$bd_cr_body" 2>/dev/null)] out=[$bd_out]"; fi
  # R5: a conf create.<token> the type does not require is NOTEd, never written
  bd_cx='create.customfield_10100=Acme'; bd_conf - - cloud; bd_cr --title x; bd_cx=""
  if [ "$bd_rc" -eq 0 ] && [ "$(cat "$bd_cr_body" 2>/dev/null)" = '{}' ] \
     && printf '%s' "$bd_out" | grep -qF "NOTE: create.customfield_10100 is not required by 'Task'; not written."; then
    bd_pass "leg jira/create-unrequired-conf: a conf create.<token> the type does not require is NOTEd and not written (R5)"
  else bd_fail_ "leg jira/create-unrequired-conf: rc=$bd_rc body=[$(cat "$bd_cr_body" 2>/dev/null)] out=[$bd_out]"; fi
  # R8: a string-array (labels) value with a space is refused (Jira would split or reject it), zero POSTs
  printf 'labels\tstring-array\tLabels\t\tcomplete\n' > "$bd_rfdir/Task.txt"
  bd_cx='create.labels=two words'; bd_conf - - cloud; bd_cr --title x; bd_cx=""
  bd_refuse_leg label-space "'Labels' (labels)" "cannot contain a space"
  rm -f "$bd_rfdir/Task.txt"; bd_conf - - cloud
  # the bare create-POST failure now points at the validator hint
  bd_out=$(cd "$bd_cc" && STUB_CM_DIR="$bd_cmdir" STUB_CREATE_FAIL=1 do_create --title "x" 2>&1)
  if printf '%s' "$bd_out" | grep -qF 'a workflow validator may require a field create-meta does not report'; then
    bd_pass "leg jira/create-fail-hint: a refused create names the workflow-validator possibility and --fields"
  else bd_fail_ "leg jira/create-fail-hint: out=[$bd_out]"; fi

  # ── transition rc 5 (the adapter's diagnosed refusal): its ONE sentence is shown verbatim by move, and
  # survives claim's compensation (the ref is still undone); rc stays non-zero. ───────────────────────
  bd_s5="refused: jira refused the transition to 'Done'; its screen requires: customfield_10900 (Reviewer); a workflow validator may also require a field the screen does not report - the kit does not fill transition screens: set it in Jira, or give it a default in the workflow"
  bd_out=$(cd "$bd_jclone" && STUB_STATE='Selected for Development' STUB_TRANSITION_RC=5 STUB_TRANSITION_ERR="$bd_s5" do_move ROW-JIRA-13 'done' 2>&1); bd_rc=$?
  if [ "$bd_rc" -ne 0 ] && printf '%s\n' "$bd_out" | grep -qxF "$bd_s5"; then
    bd_pass "leg jira/move-rc5: an adapter rc 5 shows its sentence verbatim and board move exits non-zero"
  else bd_fail_ "leg jira/move-rc5: rc=$bd_rc out=[$bd_out]"; fi
  bd_out=$(cd "$bd_jclone" && STUB_STATE='Selected for Development' STUB_TRANSITION_RC=5 STUB_TRANSITION_ERR="$bd_s5" do_claim ROW-JIRA-14 2>&1); bd_rc=$?
  if [ "$bd_rc" -ne 0 ] && printf '%s\n' "$bd_out" | grep -qxF "$bd_s5" \
     && ! git ls-remote "$bd_remote" refs/claims/ROW-JIRA-14 2>/dev/null | grep -q refs/claims/ROW-JIRA-14; then
    bd_pass "leg jira/claim-rc5: an adapter rc 5 under claim keeps its sentence intact through the compensation (ref undone), rc non-zero"
  else bd_fail_ "leg jira/claim-rc5: rc=$bd_rc out=[$bd_out]"; fi

  # --- FIX ROUND (security NO-GO on the FIRST head) — legs below ------------------------------

  # leg (row-grammar, BLOCKER-1c): board.sh's OWN front-door row-grammar refusal, before any
  # pre-read, ref push, or --then string is built.
  bd_out=$(cd "$bd_jclone" && STUB_LOG="$bd_base/.badrowlog" do_claim 'ROW 1' 2>&1); bd_rc=$?
  if [ "$bd_rc" -eq 2 ] && [ ! -s "$bd_base/.badrowlog" ]; then
    bd_pass "leg row-grammar/claim: an invalid row id is refused at board.sh's own front door, before any tracker call (BLOCKER-1c)"
  else
    bd_fail_ "leg row-grammar/claim: rc=$bd_rc, dispatched=$([ -s "$bd_base/.badrowlog" ] && echo yes || echo no)"
  fi
  # (no separate ref-push check here: 'ROW 1' carries a space, which is not a legal git ref
  # component at all — the meaningful assertion is the empty dispatch log above, which proves
  # bd_require_row runs BEFORE do_claim ever reaches claim-ref or any tracker call.)
  bd_out=$(cd "$bd_jclone" && STUB_LOG="$bd_base/.badrowlog2" do_move "$(printf 'ROW\tBAD')" 'done' 2>&1); bd_rc=$?
  if [ "$bd_rc" -eq 2 ] && [ ! -s "$bd_base/.badrowlog2" ]; then
    bd_pass "leg row-grammar/move: an invalid row id on move is refused pre-request (BLOCKER-1c)"
  else
    bd_fail_ "leg row-grammar/move: rc=$bd_rc, dispatched=$([ -s "$bd_base/.badrowlog2" ] && echo yes || echo no)"
  fi

  # leg (exact-match, MEDIUM-1): a status "Done Deal" must NOT satisfy a target of "Done" via a
  # SUBSTRING match — the pre-fix shape (`*"status-name\t$_target"*`) would have wrongly matched,
  # since "Done Deal" starts with "Done".
  bd_out=$(cd "$bd_jclone" && STUB_STATE='Done Deal' do_move ROW-JIRA-9 'done' 2>&1); bd_rc=$?
  if [ "$bd_rc" -ne 0 ]; then
    bd_pass "leg exact-match/move: 'Done Deal' does not satisfy a target of 'Done' — exact match, not substring (MEDIUM-1)"
  else
    bd_fail_ "leg exact-match/move: 'Done Deal' wrongly satisfied a target of 'Done' (substring-match regression)"
  fi

  # leg (exact-match, MEDIUM-1 pre-read twin): a pre-read of "In Progress++" must NOT falsely
  # trigger claim's already-claimed refusal against a target of "In Progress" (same substring
  # class, on the pre-read this time) — the transition then writes the EXACT target so the
  # post-read still succeeds normally, isolating the pre-read comparison alone.
  bd_sf10="$bd_base/.sf10"; printf 'In Progress++' > "$bd_sf10"
  bd_out=$(cd "$bd_jclone" && STUB_STATE_FILE="$bd_sf10" do_claim ROW-JIRA-10 2>&1); bd_rc=$?
  if [ "$bd_rc" -eq 0 ]; then
    bd_pass "leg exact-match/preread: a pre-read of 'In Progress++' does not falsely trigger the already-claimed refusal (MEDIUM-1)"
  else
    bd_fail_ "leg exact-match/preread: wrongly refused/failed (rc=$bd_rc) against a non-exact pre-read match, out=[$bd_out]"
  fi

  # leg (claim-second-refusal, LOW-2): a claim ref ALREADY on the remote (pushed for real, through
  # claim-ref itself) exercises do_claim's `sh … claim-ref … || return $?` forwarding line with a
  # REAL non-zero rc from claim-ref (rc 3, already claimed) — the one scenario among the legs here
  # where that exact code path runs. FIX ROUND (LOW-B): this used to be `cmd; _rc=$?; [ "$_rc" -eq
  # 0 ] || return "$_rc"`, and under `set -e` the bare `cmd` failing as the LAST statement of the
  # if/else body already aborted the FUNCTION before `_rc=$?` ever ran — so this leg passed for the
  # WRONG reason (set -e's own abort, not the forwarding line). Mutants M6a (`_rc=0`) and M6b
  # (delete both lines) left it green. The line is now `cmd || return $?`, genuinely load-bearing;
  # confirmed non-vacuous by RC at fix round (M6a/M6b-shaped mutation reds this leg).
  ( cd "$bd_jclone" && sh "$BD_CLAIM_SH" claim-ref ROW-JIRA-11 >/dev/null 2>&1 )
  bd_out=$(cd "$bd_jclone" && STUB_LOG="$bd_base/.claimlog11" STUB_STATE='Selected for Development' do_claim ROW-JIRA-11 2>&1); bd_rc=$?
  if [ "$bd_rc" -eq 3 ]; then
    bd_pass "leg jira/claim-second-refusal: a pre-existing claim ref forces do_claim's rc-3 forwarding through the real 'cmd || return \$?' line (LOW-2/LOW-B)"
  else
    bd_fail_ "leg jira/claim-second-refusal: expected rc 3 (already claimed), got rc=$bd_rc out=[$bd_out]"
  fi
  if [ -f "$bd_base/.claimlog11" ] && grep -qE 'assign-self|transition' "$bd_base/.claimlog11"; then
    bd_fail_ "leg jira/claim-second-refusal-notracker: a tracker WRITE call was reached despite the pre-existing ref"
  else
    bd_pass "leg jira/claim-second-refusal-notracker: no tracker WRITE call was dispatched (claim-ref refused before --then ran)"
  fi

  # leg (apostrophe-state, MEDIUM-2): `.kit/tracker.conf` deliberately ADMITS an apostrophe in a
  # state name (L-7, "Won't Do"); a SEPARATE clone pins `state.in-progress=Dev's Turn` and proves
  # claim still succeeds — the pre-fix `_then` shape broke under `sh -c` on this exact byte.
  bd_jclone2="$bd_base/jira-clone-apos"
  git clone -q "$bd_remote" "$bd_jclone2" 2>/dev/null
  (
    cd "$bd_jclone2"
    git config user.name "Fixture Dev"; git config user.email "dev@example.com"; git config commit.gpgsign false
    mkdir -p .kit
    printf 'Backlog backend: jira\n' > CLAUDE.md
    printf 'version=1\nbackend=jira\nbase_url=https://ex.atlassian.net\nflavour=cloud\nauth=basic\nproject=AB\nstate.ready=Selected for Development\nstate.in-progress=Dev'"'"'s Turn\nstate.in-review=In Review\nstate.blocked=Blocked\nstate.backlog=Backlog\nstate.released=Released\nstate.done=Done\nstate.cancelled=Won'"'"'t Do\n' > .kit/tracker.conf
    git add -A
    git commit -q -m "fixture: jira backend, apostrophe state name"
  )
  git -C "$bd_jclone2" push -q origin HEAD:refs/heads/apos-fixture
  bd_sf_apos="$bd_base/.sf-apos"; printf 'Selected for Development' > "$bd_sf_apos"
  bd_out=$(cd "$bd_jclone2" && STUB_STATE_FILE="$bd_sf_apos" do_claim ROW-JIRA-12 2>&1); bd_rc=$?
  if [ "$bd_rc" -eq 0 ]; then
    bd_pass "leg apostrophe-state: a conf-admitted apostrophe in the target state name (\"Dev's Turn\") does not break the --then shell string (MEDIUM-2)"
  else
    bd_fail_ "leg apostrophe-state: an apostrophe in the target state name broke the claim (rc=$bd_rc) out=[$bd_out]"
  fi

  # leg (usage): missing --title, unknown option, two row ids — real subprocess spawns (the
  # production BD_JIRA_SH is fine here; none of these reach the tracker at all).
  BD_JIRA_SH=$_saved_jira
  bd_out=$(sh "$BD_SELF" create 2>&1); bd_rc=$?
  [ "$bd_rc" -eq 2 ] && bd_pass "leg usage/create-no-title: create without --title is rc 2" \
    || bd_fail_ "leg usage/create-no-title: rc=$bd_rc"
  bd_out=$(sh "$BD_SELF" claim ROW-1 ROW-2 2>&1); bd_rc=$?
  [ "$bd_rc" -eq 2 ] && bd_pass "leg usage/claim-two-rows: two row ids is rc 2" \
    || bd_fail_ "leg usage/claim-two-rows: rc=$bd_rc"
  bd_out=$(sh "$BD_SELF" claim --bogus ROW-1 2>&1); bd_rc=$?
  [ "$bd_rc" -eq 2 ] && bd_pass "leg usage/claim-unknown-opt: an unknown option is rc 2" \
    || bd_fail_ "leg usage/claim-unknown-opt: rc=$bd_rc"

  BD_JIRA_SH=$_saved_jira
  rm -rf "$bd_base" 2>/dev/null || true

  if [ "$bd_fail" -ne 0 ]; then echo "board --selftest: FAIL" >&2; return 1; fi
  echo "board --selftest: OK"
  return 0
}

BD_SELF=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")

case "${1:-}" in
  --selftest) shift; if selftest; then bd_rc_main=0; else bd_rc_main=$?; fi ;;
  claim)      shift; if do_claim "$@"; then bd_rc_main=0; else bd_rc_main=$?; fi ;;
  release)    shift; if do_release "$@"; then bd_rc_main=0; else bd_rc_main=$?; fi ;;
  move)       shift; if do_move "$@"; then bd_rc_main=0; else bd_rc_main=$?; fi ;;
  create)     shift; if do_create "$@"; then bd_rc_main=0; else bd_rc_main=$?; fi ;;
  -h|--help)  bd_usage; bd_rc_main=2 ;;
  "")         bd_usage; bd_rc_main=2 ;;
  *)          echo "board.sh: unknown verb '$1'" >&2; bd_usage; bd_rc_main=2 ;;
esac
exit "$bd_rc_main"
