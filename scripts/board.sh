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
#                               [--parent <KEY>] [--description <text>] [--metric <text>] [--label <name>]... [--field <token>=<value>]...
#   sh scripts/board.sh comment <KEY> --from-record docs/reviews/<name>.md [--dry-run]
#   sh scripts/board.sh rank    KEY (--top | --before KEY | --after KEY) [--dry-run]
#   sh scripts/board.sh list    [--limit N]
#   sh scripts/board.sh show    <KEY> [--comments <n>]
#   sh scripts/board.sh edit    <KEY> [--title <t> | --title-file <path>] [--description-file <path>] [--metric-file <path>] [--size <s>] [--risk <r>]
#                               [--label-add <l>]... [--label-remove <l>]... [--parent <KEY>] [--dry-run]
#   sh scripts/board.sh migrate --from <board.md> --plan <plan.tsv> [--dry-run | --freeze --date <D>] ...  (scripts/board-migrate.sh)
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
#   The Success metric rides `--metric <text>`: it is written to the conf's `field.metric` (a customfield_N paragraph
#   field: ADF on Cloud, a plain string on Data Center) and proven present by the post-read. `--metric` with
#   `field.metric` unmapped is refused before any POST, naming the conf line to add.
# `comment <KEY> --from-record docs/reviews/<name>.md` posts one comment on a card through the adapter (the text rides
#   stdin, never argv) and reads it back by id. The verb builds the body (the agent supplies no free text): the record's
#   FIRST line (1..300 bytes, printable, a non-blank byte), then `Record: <path>`. The record must be a tracked regular
#   file with no symlink in its path. On `md` it refuses (the retro rides the PR). `--dry-run` validates and prints what
#   it would post, with no adapter call and no credentials.
# `rank KEY (--top | --before KEY | --after KEY)` moves a card in the tracker's Rank order (adapter `rank`, Jira Software's
#   agile endpoint; the account needs the Schedule Issues permission). KEY and any anchor must be OPEN cards (pre-read via
#   `list-ranked`); success is reported only when a post-read shows the new order, else UNPROVEN (rc 2). `--top` on a card
#   already first writes nothing. `--dry-run` runs every check and the pre-read, then prints the PUT it would make.
#   `list [--limit N]` prints the open cards, KEY and status, in rank order. Both refuse on md (its order is the Order line).
# `show <KEY>` reads one whole card (read-only, one request); its text is untrusted, so the adapter sanitises every printed
#   byte, frames the description and comments as data and caps the output. `edit <KEY>` changes only the fields named (summary,
#   description, Size, Risk, labels as add/remove deltas, parent) through the adapter's allowlisted `edit` (the adapter allows
#   exactly the Size, Risk and Metric ids it is GIVEN on argv; THIS file supplies the conf's field.size, field.risk and field.metric), and PROVES each by a
#   get-fields post-read; it never touches state, assignee or rank. `--description-file <path>` (create and edit) is the form for
#   text the guard's scan cannot judge: contained to the repo root and $TMPDIR, no dot-leading component, no symlink, valid
#   UTF-8, no key or token shape (bd_tf_load). Design: docs/architecture/2026-10-09-board-edit-show-verb-design.md.
#   BOARD-TEXT-FILE-FORMS (design 2026-10-10): the same loader serves `--title-file` (create and edit; exactly one line of the
#   inline --title grammar) and `--metric-file` (create and edit). `create` refuses --title with --title-file and --metric
#   with --metric-file. `edit --metric-file` is the only edit form for the Success metric: it writes the conf's field.metric
#   (the adapter allows that id because THIS file hands it over on argv) and the post-read proves it `present <bytes>`.
#
# `release --stale` on a TRACKER backend (today: jira) is the merged-PR close: with a claim ref held its proof is a merged
#   PR (release-ref's P2), so the card ends at `state.done` (not `state.ready`), and the ref is deleted after the transition
#   (S-5 order). EXCEPTION: with NO claim ref there is no proof to check — the card is moved on the caller's word, and a
#   stderr line says UNPROVEN (a forge-UI hand-close must work). A card already at `state.done` gets no transition call.
#   The holder's plain `release` (an abandoned claim) still ends at `state.ready`. `md` is unchanged: the Done row
#   rides the PR. `land`/`actuate` call `release <ROW> --stale` after the merge; run it by hand after a forge-UI merge.
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
  echo "  board.sh release <ROW-ID> [--stale]   (on a tracker, --stale = close after the merge: card ends Done; plain release ends Ready; no claim ref = UNPROVEN)" >&2
  echo "  board.sh move    <ROW-ID> <state>" >&2
  echo "  board.sh create  --title <text> [--size <s>] [--risk <r>] [--type <issuetype>] [--parent <KEY>] [--description <text>] [--metric <text>]" >&2
  echo "                   (--title-file <path> / --metric-file <path> replace --title / --metric: one line of the title grammar; the metric as a description file)" >&2
  echo "                   [--label <name>]...   (repeatable, at most 10; each [A-Za-z0-9_.:-]{1,64}; appended to the card's labels)" >&2
  echo "                   [--field <token>=<value>]...   (repeatable: the value of a field the project REQUIRES; the token is" >&2
  echo "                    tracker-conf.sh's create.<token> grammar; \`sh conformance/tracker-contract.sh --fields\` lists them)" >&2
  echo "                   (acceptance criteria ride --description; no separate field.acceptance is written;" >&2
  echo "                    a select --size/--risk must be one of the type's allowed values, matched case-insensitively," >&2
  echo "                    printable ASCII only; a free value is [A-Za-z0-9 _.-]{1,64}; a label value [A-Za-z0-9_-]{1,32})" >&2
  echo "  board.sh comment <KEY> --from-record docs/reviews/<name>.md [--dry-run]   (one comment on a card: the record's first line + its path; on md it refuses)" >&2
  echo "  board.sh rank    KEY (--top | --before KEY | --after KEY) [--dry-run]   (move a card in the tracker's rank order; proven by a post-read; on md it refuses)" >&2
  echo "  board.sh list    [--limit N]   (the open cards in rank order, KEY and status; on md it refuses)" >&2
  echo "  board.sh show    <KEY> [--comments <n>]   (one whole card, read-only: header lines, the description and the last n comments (default 3, max 10), the text sanitised and framed as data)" >&2
  echo "  board.sh edit    <KEY> [--title <t> | --title-file <path>] [--description-file <path>] [--metric-file <path>] [--size <s>] [--risk <r>] [--label-add <l>]... [--label-remove <l>]... [--parent <KEY>] [--dry-run]" >&2
  echo "                   (changes only those fields, proven by a post-read; --description-file / --metric-file REPLACE the whole text (no inline edit --metric); --title is 1..255 printable ASCII;" >&2
  echo "                    --size/--risk are matched against the card's editmeta; labels are add/remove deltas; --parent must be in this project; --dry-run makes no request)" >&2
  echo "  board.sh create ... also takes --description-file <path> in place of --description (a regular non-symlink file of 1..32000 bytes under the repo root or \$TMPDIR," >&2
  echo "                    no dot-leading path component, valid UTF-8, no key or token shape; the sanctioned form for text with < | ; \$ ' or a control-plane file name)" >&2
  echo "  board.sh migrate --from <board.md> --plan <plan.tsv> [--ledger <path>] [--screen <file>] [--date <YYYY-MM-DD>] [--dry-run]" >&2
  echo "                   (moves a markdown board's open rows INTO the declared tracker through \`create\`; add --freeze --date <D> to freeze the file;" >&2
  echo "                    see scripts/board-migrate.sh and docs/work-tracking/adapters.md 'Moving an existing board')" >&2
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
  # SWAS-101 (H1): the auth kind comes from the conf (default basic) unless the caller already set it, so a Data
  # Center bearer user needs no export. The adapter reads KIT_TRACKER_AUTH; the credential itself is resolved there.
  if [ -z "${KIT_TRACKER_AUTH:-}" ]; then
    KIT_TRACKER_AUTH=$(bd_tc_get auth)
    [ -n "$KIT_TRACKER_AUTH" ] || KIT_TRACKER_AUTH=basic
    export KIT_TRACKER_AUTH
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
      # `--stale` on a tracker backend is the MERGED-PR close: with a claim ref its proof (release-ref's P2) is a merged PR (no ref = UNPROVEN, below),
      # so the card ends at state.done. The holder's plain release (an abandoned claim) still ends at state.ready.
      if [ "$_stale" = 1 ]; then _tkey=state.done; else _tkey=state.ready; fi
      _target=$(bd_tc_get "$_tkey")
      [ -n "$_target" ] || { echo "board release: .kit/tracker.conf has no $_tkey mapping." >&2; return 2; }
      if [ "$_stale" = 1 ]; then bd_release_jira_stale; return $?; fi
      # MEDIUM-2: see the identical note in do_claim above.
      _then="sh '$(bd_sq "$BD_JIRA_SH")' transition '$(bd_sq "$_btbase")' '$(bd_sq "$_btflavour")' '$(bd_sq "$_btproject")' '$(bd_sq "$_row")' '$(bd_sq "$_target")'"
      # LOW-B: see the identical note in do_claim above — `cmd || return $?`, never a bare
      # `cmd; _rc=$?` that `set -e` would have already made unreachable on the failure path.
      sh "$BD_CLAIM_SH" release-ref "$_row" --then "$_then" || return $?
      bd_release_proof "released (tracker transition to '$_target' + ref deleted)"
      return $? ;;
    *) echo "board release: undeclared or unsupported backend '$_be' — no write adapter for it." >&2; return 2 ;;
  esac
}

# bd_release_proof <what>: the post-read every tracker release ends with. rc 0 only on an EXACT match of $_target.
bd_release_proof() {
  _post=$(sh "$BD_JIRA_SH" get-issue "$_btbase" "$_btflavour" "$_btproject" "$_row" 2>&1) || {
    echo "board release: the ref+tracker write succeeded but the post-read could not run — cannot prove the release." >&2
    return 1
  }
  if [ "$(bd_field "$_post" status-name)" = "$_target" ]; then
    echo "board release: OK — \`$_row\` $1, proven by post-read."
    return 0
  fi
  echo "board release: the write ran but the post-read did NOT prove status '$_target' — treating as unproven." >&2
  return 1
}

# bd_release_jira_stale: `release <ROW> --stale` on a tracker backend; reads $_row/$_target/$_bt* from do_release.
# A pre-read comes first (Jira has no transition from a state to itself, so an already-Done card gets NO transition
# call), then `board-claim.sh check`: a held ref is released through release-ref's S-5 order (the transition runs
# FIRST, the ref is deleted only after it succeeds, and the merged-PR proof gates the whole thing); no ref = there is
# nothing to release, so the card is moved on its own. Every path ends with the exact-match post-read.
bd_release_jira_stale() {
  _pre=$(sh "$BD_JIRA_SH" get-issue "$_btbase" "$_btflavour" "$_btproject" "$_row" 2>&1) || _pre=""
  _already=0
  [ "$(bd_field "$_pre" status-name)" = "$_target" ] && _already=1
  _crc=0
  sh "$BD_CLAIM_SH" check "$_row" >/dev/null || _crc=$?
  case "$_crc" in
    0)
      _then="sh '$(bd_sq "$BD_JIRA_SH")' transition '$(bd_sq "$_btbase")' '$(bd_sq "$_btflavour")' '$(bd_sq "$_btproject")' '$(bd_sq "$_row")' '$(bd_sq "$_target")'"
      if [ "$_already" = 1 ]; then
        sh "$BD_CLAIM_SH" release-ref "$_row" --stale || return $?
      else
        sh "$BD_CLAIM_SH" release-ref "$_row" --stale --then "$_then" || return $?
      fi
      bd_release_proof "closed (tracker transition to '$_target' + ref deleted)"
      return $? ;;
    1)
      echo "board release: no claim to release on \`$_row\`."
      echo "board release: UNPROVEN — no claim ref on '$_row', so no merged-PR proof was checked; moving to '$_target' on the caller's word." >&2
      if [ "$_already" != 1 ]; then
        if ! bd_transition "$_row" "$_target"; then
          case "$_tr_rc" in
            5) : ;;
            6) if [ "$_tr_anon" -eq 1 ]; then echo "board release: the tracker rejected the credential but served the transition anonymously - the card may have moved; check with board show $_row" >&2; else bd_rejected release; fi ;;
            *) echo "board release: the tracker transition to '$_target' failed or was refused." >&2 ;;
          esac
          return 1
        fi
      fi
      bd_release_proof "closed (tracker already at, or moved to, '$_target'; no claim ref; merge proof not checked)"
      return $? ;;
    *) echo "board release: could not read the claim ref (remote unreachable) — nothing was changed." >&2; return 2 ;;
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
  _tr_rc=0; _tr_anon=0
  sh "$BD_JIRA_SH" transition "$_btbase" "$_btflavour" "$_btproject" "$1" "$2" 2>"$_tr_errf" || _tr_rc=$?
  if bd_anon_wrote "$_tr_errf"; then _tr_anon=1; fi
  cat "$_tr_errf" >&2; rm -f "$_tr_errf"
  [ "$_tr_rc" -eq 0 ]
}

# bd_anon_wrote <errfile>: 0 when the adapter's rc-6 sentence in <errfile> carries its suffix "(the write may have applied
# anonymously)": Jira answered a WRITE with a 2xx but served it to an unauthenticated user, so on a project that allows anonymous
# writes the change may exist (SWAS-113 S-L1). Only that suffix decides it; nothing else of the file is read.
bd_anon_wrote() {
  grep -qF '(the write may have applied anonymously)' "$1" 2>/dev/null
}

# bd_rejected <verb> [<detail>]: the adapter answered rc 6 - Jira did not accept the credential (the response was served
# anonymously, or the login was refused; SWAS-113). The request was refused before it could change anything, so this is never
# "may have applied" UNLESS the adapter's sentence carries the anonymous-write suffix (a 2xx served to a write): the callers
# test bd_anon_wrote first and use their own may-have-applied wording. The sentence names the cure. <detail> is the adapter's sentence when it was captured, else it is above.
bd_rejected() {
  _rj_where=" (the adapter's sentence is above)"
  [ -z "${2:-}" ] || _rj_where=" - $2"
  echo "board $1: the tracker rejected the credential${_rj_where}; nothing was changed." >&2
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
        case "$_tr_rc" in
          5) : ;;
          6) if [ "$_tr_anon" -eq 1 ]; then echo "board move: the tracker rejected the credential but served the transition anonymously - the card may have moved; check with board show $_row" >&2; else bd_rejected move; fi ;;
          *) echo "board move: the tracker transition to '$_target' failed or was refused." >&2 ;;
        esac
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
  bd_cu_value create "$1" "$2" "$3" || return $?
  case "$_cu_schema" in
    option) _frag=$(printf '%s' "$_frag" | jq -c --arg id "$2" --arg v "$_cu_val" '. + {($id): {value: $v}}') ;;
    *)      _frag=$(printf '%s' "$_frag" | jq -c --arg id "$2" --arg v "$_cu_val" '. + {($id): $v}') ;;
  esac
  bd_cr_note "$2" "$_cu_val"
}

# bd_cu_value <verb> <name> <customfield_N> <value>: the ONE select/string resolver, shared by `create` (against the
# type's create-meta) and `edit` (against the card's editmeta) - both hand it the meta lines in $_cm (column 2 the field
# id, 3 the schema type, 5 the `|`-joined allowed values). Sets $_cu_schema (option|string) and $_cu_val (the canonical
# allowed value for a select, matched case-insensitively). rc 2 with a sentence naming <verb> on any refusal.
bd_cu_value() {
  _cu_line=$(printf '%s\n' "$_cm" | awk -F'\t' -v f="$3" '$2 == f { print; exit }')
  if [ -z "$_cu_line" ]; then
    if [ "$1" = create ]; then bd_cr_wrong_screen "$2" "$3"; else echo "board $1: field.$2=$3 is not editable on this card (it is absent from the card's editmeta) - nothing was changed." >&2; fi
    return 2
  fi
  bd_val_ok "$4" 'A-Za-z0-9 _.-' 64 || { echo "board $1: --$2 must match [A-Za-z0-9 _.-]{1,64}." >&2; return 2; }
  _cu_schema=$(printf '%s' "$_cu_line" | cut -f3)
  case "$_cu_schema" in
    option)
      _cu_allowed=$(printf '%s' "$_cu_line" | cut -f5)
      _cu_val=$(printf '%s\n' "$_cu_allowed" | awk -F'|' -v v="$4" 'BEGIN { lv = tolower(v) } { for (i = 1; i <= NF; i++) if (tolower($i) == lv) { print $i; exit } }')
      [ -n "$_cu_val" ] || { echo "board $1: --$2 '$4' is not an allowed value of $3; allowed: $(printf '%s' "$_cu_allowed" | sed 's/|/, /g') (printable ASCII only)." >&2; return 2; }
      ;;
    string) _cu_val=$4 ;;
    *) echo "board $1: field.$2=$3 has schema type '$_cu_schema'; board $1 writes only a select (option) or string field." >&2; return 2 ;;
  esac
  return 0
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

# bd_cr_metric: --metric, written to the conf's field.metric through the text shaper (ADF on Cloud, a plain string on
# Data Center), only when that field is mapped to a customfield_N and is on the type's screen. Unmapped is refused
# (never a silent drop), naming the conf line. The post-read proves the field is present (the text kind's proof).
bd_cr_metric() {
  [ -n "$_metric" ] || return 0
  _mt_id=$(bd_tc_get field.metric)
  case "$_mt_id" in
    customfield_*) : ;;
    *) echo "board create: --metric / --metric-file needs field.metric=customfield_N in .kit/tracker.conf (conf has '${_mt_id:-unset}') - add that line, or drop the metric; nothing was created." >&2; return 2 ;;
  esac
  bd_cr_has "$_mt_id" || { bd_cr_wrong_screen metric "$_mt_id"; return 2; }
  bd_cr_text "$_metric" || return 1
  _frag=$(printf '%s' "$_frag" | jq -c --arg id "$_mt_id" --argjson d "$_jv" '. + {($id): $d}')
  bd_cr_present "$_mt_id"
}

# bd_cr_user_labels: the --label values, appended to .labels (any size:/risk: label is already there).
bd_cr_user_labels() {
  [ -n "$_labels" ] || return 0
  bd_cr_has labels || { echo "board create: issue type '$_type' has no labels field on its create screen, so --label cannot be written." >&2; return 2; }
  while IFS= read -r _ul; do
    [ -n "$_ul" ] || continue
    _frag=$(printf '%s' "$_frag" | jq -c --arg l "$_ul" '.labels = ((.labels // []) + [$l])')
    _cr_labels="$_cr_labels $_ul"
  done <<EOF_UL
$_labels
EOF_UL
  bd_cr_note labels ""
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
  _cm_err=$(tr '\n' ' ' < "$_cm_errf" | tr -cd '\40-\176' | cut -c1-200); rm -f "$_cm_errf"
  case "$_cm_rc" in
    0) : ;;
    3) echo "board create: issue type '$_type' is not in project $_btproject (or the token lacks Create permission in this project) - set create.issuetype in .kit/tracker.conf (or pass --type) to one of its types; \`sh conformance/tracker-contract.sh --fields\` lists them." >&2; return 2 ;;
    4) echo "board create: issue type name '$_type' is ambiguous in project $_btproject (more than one type carries it) - rename one in Jira; nothing was created." >&2; return 2 ;;
    6) bd_rejected create "${_cm_err:-the adapter reported the rejection}"; return 1 ;;
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
  [ "$1" != "$(bd_tc_get field.metric)" ] || { echo '--metric <text>'; return 0; }
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
  _rf_err=$(tr '\n' ' ' < "$_rf_errf" | tr -cd '\40-\176' | cut -c1-200); rm -f "$_rf_errf"
  if [ "$_rf_rc" -eq 6 ]; then bd_rejected create "${_rf_err:-the adapter reported the rejection}"; return 1; fi
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
  bd_cr_metric || return $?
  bd_cr_user_labels || return $?
  bd_cr_required || return 1
  # created BY the numeric id create-meta resolved (never an ambiguous name); the fragment rides STDIN, not argv
  _cr_crc=0
  _cr_errf=$(mktemp) || { echo "board create: could not create a scratch file." >&2; return 1; }
  _key=$(printf '%s' "$_frag" | sh "$BD_JIRA_SH" create "$_btbase" "$_btflavour" "$_btproject" "$_title" "$_type_id" - 2>"$_cr_errf") || _cr_crc=$?
  cat "$_cr_errf" >&2; _cr_anon=0
  if bd_anon_wrote "$_cr_errf"; then _cr_anon=1; fi
  rm -f "$_cr_errf"
  if [ "$_cr_crc" -eq 6 ]; then
    if [ "$_cr_anon" -eq 1 ]; then echo "board create: the tracker rejected the credential but served the create anonymously - a card may have been created; check the board before re-running." >&2
    else bd_rejected create; fi
    return 1
  fi
  if [ "$_cr_crc" -ne 0 ]; then
    echo "board create: the tracker create request failed or was refused (a workflow validator may require a field create-meta does not report; see tracker-contract.sh --fields)." >&2
    return 1
  fi
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

# bd_label_arg <name>: one --label (repeatable, at most 10), each ^[A-Za-z0-9_.:-]{1,64}$, collected in $_labels one per
# line. A label rides the `labels` field the adapter already allowlists; it is appended to whatever size:/risk: labels the
# field map writes, and is read back by bd_cr_prove.
bd_label_arg() {
  bd_val_ok "$1" 'A-Za-z0-9_.:-' 64 || { echo "board create: --label must match [A-Za-z0-9_.:-]{1,64} (no space)." >&2; return 2; }
  [ "$_label_n" -lt 10 ] || { echo "board create: at most 10 --label values." >&2; return 2; }
  _label_n=$((_label_n + 1))
  _labels="$_labels$1
"
}

# ── --description-file (BOARD-EDIT-SHOW-VERB, design 2026-10-09 §2.3) ─────────────────────────────────────────
# The sanctioned form for text the guard's scan cannot judge (`<`, `|`, `;`, `$`, apostrophes, control-plane names): the
# bytes never ride the command line. Inline `--description "$(cat x)"` is declined by the guard, so a file option is a NEW way
# to send a local file's bytes to the tracker - hence the containment below. It is a speed bump, stated as one: the credential
# is already in the session's environment and the egress control is a network allowlist.

# bd_df_under <physical-path> <root>: 0 when the path is under the root and NO component below the root starts with a dot
# (.ssh, .aws, .env, .kit, .git). A root of `/` is never a root.
bd_df_under() {
  [ "$2" != / ] || return 1
  case "$1" in
    "$2"/*) : ;;
    *) return 1 ;;
  esac
  case "/${1#"$2"/}" in
    */.*) return 1 ;;
  esac
  return 0
}

# bd_df_contained <physical-path>: under the repo root, or under $TMPDIR (/tmp when unset) - both resolved physically.
bd_df_contained() {
  _dc_root=$(CDPATH='' cd -- "$(bd_root)" 2>/dev/null && pwd -P) || _dc_root=""
  _dc_tmp=$(CDPATH='' cd -- "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P) || _dc_tmp=""
  if [ -n "$_dc_root" ] && bd_df_under "$1" "$_dc_root"; then return 0; fi
  if [ -n "$_dc_tmp" ] && bd_df_under "$1" "$_dc_tmp"; then return 0; fi
  return 1
}

# bd_df_secret <physical-path>: 0 when the file holds a private-key header or a well-known token shape (the secret scan's
# own families). The content is never echoed; the caller prints one fixed sentence.
bd_df_secret() {
  head -c 32001 "$1" | LC_ALL=C grep -Eq \
    -e '-----BEGIN [A-Z ]*PRIVATE KEY' \
    -e 'gh[pousr]_[A-Za-z0-9]{30,}' \
    -e 'github_pat_[A-Za-z0-9_]{20,}' \
    -e 'AKIA[0-9A-Z]{16}' \
    -e 'xox[abprs]-[A-Za-z0-9-]{10,}' \
    -e 'ATATT[A-Za-z0-9_=-]{20,}' \
    -e 'sk-ant-[A-Za-z0-9_-]{20,}' \
    -e 'AIza[0-9A-Za-z_-]{35}' \
    -e 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.'
}

# bd_tf_load <verb> <kind> <path>: reads the file into $_tf_val (trailing newlines trimmed - an editor's final newline is not
# content). kind is description, title or metric (BOARD-TEXT-FILE-FORMS, design 2026-10-10 §2.1) and names the flag:
# --description-file / --title-file / --metric-file. Regular file, not a symlink, readable, physical path inside the
# containment, 1..32000 bytes, no NUL, valid UTF-8, no secret shape; a title is also exactly one line of the inline --title
# grammar. Read bounded (head -c). rc 2 with ONE fixed sentence on any refusal; no byte of the file or its path is echoed.
bd_tf_load() {
  _df_v=$1; _tf_kind=$2; _df_p=$3
  _df_pre="board $_df_v: --$_tf_kind-file"
  _tf_val=""
  # every byte of the path must be printable ASCII (a newline included): counted with wc -c, never a residue test
  [ -n "$_df_p" ] && [ "$(printf '%s' "$_df_p" | LC_ALL=C tr -cd '\040-\176' | wc -c | tr -d ' ')" = "$(printf '%s' "$_df_p" | wc -c | tr -d ' ')" ] \
    || { echo "$_df_pre needs a path of printable ASCII characters (no newline or control byte)." >&2; return 2; }
  _df_dir=$(CDPATH='' cd -- "$(dirname -- "$_df_p")" 2>/dev/null && pwd -P) || { echo "$_df_pre must be a readable regular file." >&2; return 2; }
  _df_phys="$_df_dir/$(basename -- "$_df_p")"
  # -L and -f on the EXACT path that is read below
  if [ -L "$_df_phys" ]; then echo "$_df_pre must not be a symlink." >&2; return 2; fi
  { [ -f "$_df_phys" ] && [ -r "$_df_phys" ]; } || { echo "$_df_pre must be a readable regular file." >&2; return 2; }
  bd_df_contained "$_df_phys" \
    || { echo "$_df_pre must sit under the repo root or \$TMPDIR, and no path component below that may start with a dot." >&2; return 2; }
  # the file is read ONCE, bounded, into a private mode-600 copy; every check and the content come from that copy
  _df_tmp=$( umask 077; mktemp ) || { echo "$_df_pre could not create a scratch file." >&2; return 2; }
  trap 'rm -f "$_df_tmp"' EXIT
  trap 'rm -f "$_df_tmp"; exit 130' INT
  trap 'rm -f "$_df_tmp"; exit 143' TERM
  _df_rc=0
  head -c 32001 "$_df_phys" > "$_df_tmp" 2>/dev/null || _df_rc=2
  if [ "$_df_rc" -eq 0 ]; then bd_tf_check "$_df_tmp" || _df_rc=$?; fi
  rm -f "$_df_tmp"
  trap - EXIT INT TERM
  return "$_df_rc"
}

# bd_tf_check <copy>: the content checks, all on the private copy. Sets $_tf_val. rc 2 + one fixed sentence on any refusal.
bd_tf_check() {
  _df_n=$(wc -c < "$1" | tr -d ' ')
  { [ "$_df_n" -ge 1 ] && [ "$_df_n" -le 32000 ]; } || { echo "$_df_pre must be 1..32000 bytes." >&2; return 2; }
  [ "$(LC_ALL=C tr -d '\000' < "$1" | wc -c | tr -d ' ')" = "$_df_n" ] \
    || { echo "$_df_pre must not hold a NUL byte." >&2; return 2; }
  command -v iconv >/dev/null 2>&1 || { echo "$_df_pre needs iconv to verify UTF-8; install it." >&2; return 2; }
  iconv -f UTF-8 -t UTF-8 < "$1" >/dev/null 2>&1 \
    || { echo "$_df_pre must be valid UTF-8." >&2; return 2; }
  if bd_df_secret "$1"; then
    echo "$_df_pre holds a private-key header or a token shape; remove it and retry." >&2; return 2
  fi
  _tf_val=$(cat "$1")
  [ -n "$_tf_val" ] || { echo "$_df_pre holds no content." >&2; return 2; }
  [ "$_tf_kind" != title ] || { bd_tf_title || return 2; return 0; }
  [ "$(bd_text_lines "$_tf_val")" -le 2000 ] || { echo "$_df_pre is over the 2000-line bound." >&2; return 2; }
  return 0
}

# bd_tf_title: a title file is exactly one line, then the SAME grammar as inline --title (1..255 printable ASCII, no leading
# or trailing space). On a refusal $_tf_val is cleared so no byte of the file survives the call.
# (The single-line check gives the clearer refusal sentence; the printable-ASCII grammar would refuse a newline anyway.)
bd_tf_title() {
  case "$_tf_val" in
    *"
"*) _tf_val=""; echo "$_df_pre must hold exactly one line." >&2; return 1 ;;
  esac
  bd_val_ok "$_tf_val" '\40-\176' 255 || { _tf_val=""; echo "$_df_pre must be 1..255 printable ASCII characters." >&2; return 1; }
  case "$_tf_val" in
    ' '*|*' ') _tf_val=""; echo "$_df_pre must not start or end with a space." >&2; return 1 ;;
  esac
  return 0
}

# bd_text_lines <text>: the line count BOTH create and edit use for the 2000-line bound (a last line without a newline counts).
bd_text_lines() {
  printf '%s\n' "$1" | awk 'END { print NR }'
}

do_create() {
  _title=""; _titleset=0; _titlef=""; _size=""; _risk=""; _type=""; _parent=""; _desc=""; _descset=0; _descf=""; _metric=""; _metricset=0; _metricf=""; _cr_fields=""; _labels=""; _label_n=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --title|--title-file|--size|--risk|--type|--parent|--description|--description-file|--metric|--metric-file|--field|--label)
        [ $# -ge 2 ] || { echo "board create: $1 needs a value" >&2; return 2; }
        case "$1" in
          --title) _title=$2; _titleset=1 ;;
          --title-file) _titlef=$2 ;;
          --size) _size=$2 ;;
          --risk) _risk=$2 ;;
          --type) _type=$2 ;;
          --parent) _parent=$2 ;;
          --description) _desc=$2; _descset=1 ;;
          --description-file) _descf=$2 ;;
          --metric) _metric=$2; _metricset=1 ;;
          --metric-file) _metricf=$2 ;;
          --field) bd_field_arg "$2" || return 2 ;;
          --label) bd_label_arg "$2" || return 2 ;;
        esac
        shift 2 ;;
      -*)      echo "board create: unknown option '$1'" >&2; bd_usage; return 2 ;;
      *)       echo "board create: unexpected argument '$1' (use --title/--title-file/--size/--risk/--type/--parent/--description/--description-file/--metric/--metric-file/--field/--label)" >&2; return 2 ;;
    esac
  done
  [ -n "$_title" ] || [ -n "$_titlef" ] || { echo "board create: --title is required" >&2; bd_usage; return 2; }
  if [ -n "$_titlef" ]; then
    [ "$_titleset" -eq 0 ] || { echo "board create: --title and --title-file are mutually exclusive." >&2; return 2; }
    bd_tf_load create title "$_titlef" || return 2
    _title=$_tf_val
  fi
  if [ -n "$_descf" ]; then
    [ "$_descset" -eq 0 ] || { echo "board create: --description and --description-file are mutually exclusive." >&2; return 2; }
    bd_tf_load create description "$_descf" || return 2
    _desc=$_tf_val
  fi
  if [ -n "$_metricf" ]; then
    [ "$_metricset" -eq 0 ] || { echo "board create: --metric and --metric-file are mutually exclusive." >&2; return 2; }
    bd_tf_load create metric "$_metricf" || return 2
    _metric=$_tf_val
  fi
  [ -z "$_type" ] || bd_type_ok "$_type" || { echo "board create: --type must match ^[A-Za-z][A-Za-z0-9 _-]{0,39}\$." >&2; return 2; }
  [ -z "$_parent" ] || bd_row_ok "$_parent" || { echo "board create: --parent must be an issue key matching [A-Z0-9][A-Z0-9-]*." >&2; return 2; }
  [ "$(printf '%s' "$_desc" | wc -c | tr -d ' ')" -le 32000 ] || { echo "board create: --description is over the 32000-byte bound." >&2; return 2; }
  [ "$(bd_text_lines "$_desc")" -le 2000 ] || { echo "board create: --description is over the 2000-line bound." >&2; return 2; }
  [ "$(printf '%s' "$_metric" | wc -c | tr -d ' ')" -le 32000 ] || { echo "board create: --metric is over the 32000-byte bound." >&2; return 2; }
  [ "$(bd_text_lines "$_metric")" -le 2000 ] || { echo "board create: --metric is over the 2000-line bound." >&2; return 2; }
  _be=$(bd_backend)
  case "$_be" in
    jira) bd_create_jira; return $? ;;
    md|'') echo "board create: no write adapter for backend '$_be' — add the row to BACKLOG.md by hand." >&2; return 2 ;;
    *)     echo "board create: undeclared or unsupported backend '$_be'." >&2; return 2 ;;
  esac
}

# ── comment (KIT-TREE-BOARD-SWITCH, design 2026-10-09 §6) ─────────────────────────────────────────
# `comment <KEY> --from-record docs/reviews/<name>.md [--dry-run]` posts one comment on a card. The request itself lives
# in the adapter (tracker-jira.sh `comment`): this front door resolves the backend through the seam, validates the key
# and the record path, composes the body itself, and hands it over on STDIN — never argv, so neither `ps` nor a command
# log sees it. Refusals are fixed sentences; no record byte is echoed. The adapter re-validates everything (both layers, before any request).

# bd_cmt_key_ok <KEY>: the adapter's own key grammar — this project, a dash, digits with no leading zero, <= 32 bytes.
bd_cmt_key_ok() {
  [ "${#1}" -le 32 ] || return 1
  case "$1" in
    "$_btproject"-[0-9]*) : ;;
    *) return 1 ;;
  esac
  _ck_rest=${1#"$_btproject"-}
  case "$_ck_rest" in
    ''|*[!0-9]*|0*) return 1 ;;
  esac
  return 0
}

# bd_cmt_record <path>: the record the comment points at (design B1). The verb builds the whole body itself — the agent
# supplies no free text: line 1 is the record's FIRST line, line 2 is `Record: <path>`. The path must be relative and
# exactly docs/reviews/<name>.md (<name> of [A-Za-z0-9._-]), with no '..', no symlink in docs, docs/reviews or the
# leaf, a regular readable file, and tracked in git. Sets _ck_body, _ck_bytes and _ck_lines. rc 2 with one fixed
# sentence on any refusal; no record byte is echoed.
bd_cmt_record() {
  _cr_p=$1
  _cr_shape="board comment: --from-record must be docs/reviews/<name>.md (relative, no '..', <name> of letters, digits, dot, dash, underscore)."
  case "$_cr_p" in
    *..*|/*) echo "$_cr_shape" >&2; return 2 ;;
    docs/reviews/*.md) : ;;
    *) echo "$_cr_shape" >&2; return 2 ;;
  esac
  _cr_name=${_cr_p#docs/reviews/}
  case "$_cr_name" in
    *[!A-Za-z0-9._-]*) echo "$_cr_shape" >&2; return 2 ;;
  esac
  [ -n "${_cr_name%.md}" ] || { echo "$_cr_shape" >&2; return 2; }
  if [ -L docs ] || [ -L docs/reviews ] || [ -L "$_cr_p" ]; then
    echo "board comment: the record path has a symlink in it (docs, docs/reviews or the file)." >&2; return 2
  fi
  { [ -f "$_cr_p" ] && [ -r "$_cr_p" ]; } || { echo "board comment: the record must be a readable regular file." >&2; return 2; }
  git ls-files --error-unmatch -- "$_cr_p" >/dev/null 2>&1 \
    || { echo "board comment: the record must be tracked in git (git add it first)." >&2; return 2; }
  _cr_line=$(head -c 4096 "$_cr_p" | head -n 1)
  _cr_bad=$(head -c 4096 "$_cr_p" | head -n 1 | LC_ALL=C tr -d '\012\040-\176\200-\377' | wc -c | tr -d ' ')
  _cr_len=$(head -c 4096 "$_cr_p" | head -n 1 | tr -d '\012' | wc -c | tr -d ' ')
  _cr_ink=$(head -c 4096 "$_cr_p" | head -n 1 | LC_ALL=C tr -d '\012\040' | wc -c | tr -d ' ')
  if [ "$_cr_bad" != 0 ] || [ "$_cr_ink" -lt 1 ] || [ "$_cr_len" -gt 300 ]; then
    echo "board comment: the record's first line must be 1..300 bytes with a non-blank byte and no control byte, CR or TAB." >&2; return 2
  fi
  _ck_body=$(printf '%s\nRecord: %s\n' "$_cr_line" "$_cr_p")
  _ck_bytes=$(printf '%s\nRecord: %s\n' "$_cr_line" "$_cr_p" | wc -c | tr -d ' ')
  _ck_lines=2
  return 0
}

# bd_cmt_args <args…>: sets _ck_key/_ck_file (the record path)/_ck_dry. rc 2 on a usage fault.
bd_cmt_args() {
  _ck_key=""; _ck_file=""; _ck_dry=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --from-record) [ $# -ge 2 ] || { echo "board comment: --from-record needs a value" >&2; return 2; }; _ck_file=$2; shift 2 ;;
      --dry-run)   _ck_dry=1; shift ;;
      -*)          echo "board comment: unknown option '$(printf '%s' "$1" | tr -d '[:cntrl:]')'" >&2; bd_usage; return 2 ;;
      *)           [ -z "$_ck_key" ] || { echo "board comment: one card key, not two" >&2; return 2; }; _ck_key=$1; shift ;;
    esac
  done
  [ -n "$_ck_key" ] && [ -n "$_ck_file" ] || { echo "board comment: a card key and --from-record docs/reviews/<name>.md are required" >&2; bd_usage; return 2; }
  bd_require_row "$_ck_key"
}

do_comment() {
  bd_cmt_args "$@" || return 2
  _be=$(bd_backend)
  case "$_be" in
    jira) : ;;
    md|'') echo "board comment: comment writes to a tracker; on md the retro rides the PR." >&2; return 2 ;;
    *)     echo "board comment: undeclared or unsupported backend '$_be'." >&2; return 2 ;;
  esac
  bd_tracker_ctx || return 2
  bd_cmt_key_ok "$_ck_key" || { echo "board comment: '$(printf '%s' "$_ck_key" | tr -cd '\40-\176' | cut -c1-40)' is not a card key of project $_btproject (the project, a dash, digits with no leading zero)." >&2; return 2; }
  bd_cmt_record "$_ck_file" || return 2
  if [ "$_ck_dry" -eq 1 ]; then
    echo "board comment: would POST a $_ck_bytes-byte, $_ck_lines-line comment to $_ck_key (dry run; no tracker call)"
    return 0
  fi
  _ck_rc=0
  _ck_errf=$(mktemp) || { echo "board comment: could not create a scratch file." >&2; return 1; }
  _ck_id=$(printf '%s\n' "$_ck_body" | sh "$BD_JIRA_SH" comment "$_btbase" "$_btflavour" "$_btproject" "$_ck_key" - 2>"$_ck_errf") || _ck_rc=$?
  cat "$_ck_errf" >&2; _ck_anon=0
  if bd_anon_wrote "$_ck_errf"; then _ck_anon=1; fi
  rm -f "$_ck_errf"
  # the adapter's rc 1 is a grammar/body refusal this front door should have caught (usage-class, rc 2); any other
  # failure is the write or its proof (rc 1)
  case "$_ck_rc" in
    0) : ;;
    1) return 2 ;;
    6)
      if [ "$_ck_anon" -eq 1 ]; then echo "board comment: the tracker rejected the credential but served the post anonymously - a comment may have been posted on $_ck_key; check the card before re-running." >&2
      else bd_rejected comment; fi
      return 1 ;;
    *) echo "board comment: the comment was not posted and proved on $_ck_key (the adapter's sentence is above)." >&2; return 1 ;;
  esac
  case "$_ck_id" in
    ''|*[!0-9]*) echo "board comment: the adapter returned no comment id; cannot prove the post." >&2; return 1 ;;
  esac
  echo "board comment: $_ck_key comment $_ck_id posted and read back"
}

# ── show / edit (BOARD-EDIT-SHOW-VERB, design 2026-10-09) ──────────────────────────────────────────
# `show <KEY> [--comments <n>]` prints one whole card (read-only, ONE request). `edit <KEY> ...` changes a closed list of a
# card's fields - summary, description, Size, Risk, labels (add/remove deltas), parent - through the adapter's `edit` (which
# carries its own allowlist) and PROVES every written value by a get-fields post-read. State, assignee, claim and rank are NOT
# here (move / claim / release / rank). Both refuse on md (the board is a file an adopter edits by hand).

# bd_se_ready <verb> <KEY>: the jira backend, the tracker context, and a key that belongs to this project. rc 2 backend or
# context fault, 1 the key is outside the project (a refusal).
bd_se_ready() {
  _be=$(bd_backend)
  case "$_be" in
    jira) : ;;
    md|'') echo "board $1: $1 needs a tracker backend; on md the board is BACKLOG.md - read or edit the file by hand." >&2; return 2 ;;
    *)     echo "board $1: undeclared or unsupported backend '$_be'." >&2; return 2 ;;
  esac
  bd_tracker_ctx || return 2
  bd_cmt_key_ok "$2" || { echo "board $1: '$(printf '%s' "$2" | tr -cd '\40-\176' | cut -c1-40)' is not a card key of project $_btproject (the project, a dash, digits with no leading zero)." >&2; return 1; }
  return 0
}

# bd_se_map <size|risk>: the conf's field.<name> when it is a customfield_N or a label:<prefix>, else `-` (what the adapter's show reads).
bd_se_map() {
  _sm_v=$(bd_tc_get "field.$1")
  case "$_sm_v" in
    customfield_*|label:*) printf '%s' "$_sm_v" ;;
    *)                     printf '%s' - ;;
  esac
}

do_show() {
  _sh_key=""; _sh_n=3
  while [ $# -gt 0 ]; do
    case "$1" in
      --comments) [ $# -ge 2 ] || { echo "board show: --comments needs a value" >&2; return 2; }; _sh_n=$2; shift 2 ;;
      -*)         echo "board show: unknown option '$(printf '%s' "$1" | tr -d '[:cntrl:]')'" >&2; bd_usage; return 2 ;;
      *)          [ -z "$_sh_key" ] || { echo "board show: one card key, not two" >&2; return 2; }; _sh_key=$1; shift ;;
    esac
  done
  [ -n "$_sh_key" ] || { echo "board show: a card key is required" >&2; bd_usage; return 2; }
  bd_require_row "$_sh_key" || return 1   # a key that fails the grammar is a refusal (design §2.1), not a usage fault
  case "$_sh_n" in
    [0-9]|10) : ;;
    *) echo "board show: --comments must be 0..10." >&2; return 2 ;;
  esac
  bd_se_ready show "$_sh_key" || return $?
  _sh_rc=0
  sh "$BD_JIRA_SH" show "$_btbase" "$_btflavour" "$_btproject" "$_sh_key" "$(bd_se_map size)" "$(bd_se_map risk)" "$_sh_n" || _sh_rc=$?
  case "$_sh_rc" in
    0) return 0 ;;
    1) return 1 ;;
    6) bd_rejected show; return 1 ;;
    *) echo "board show: the card could not be read and verified (the adapter's sentence is above)." >&2; return 3 ;;
  esac
}

# bd_ed_label <add|remove> <label>: one --label-add / --label-remove (each at most 10), the grammar create's --label has.
bd_ed_label() {
  bd_val_ok "$2" 'A-Za-z0-9_.:-' 64 || { echo "board edit: --label-$1 must match [A-Za-z0-9_.:-]{1,64} (no space)." >&2; return 2; }
  if [ "$1" = add ]; then
    [ "$_ed_na" -lt 10 ] || { echo "board edit: at most 10 --label-add values." >&2; return 2; }
    _ed_na=$((_ed_na + 1)); _ed_ladd="$_ed_ladd$2
"
  else
    [ "$_ed_nr" -lt 10 ] || { echo "board edit: at most 10 --label-remove values." >&2; return 2; }
    _ed_nr=$((_ed_nr + 1)); _ed_lrem="$_ed_lrem$2
"
  fi
}

# bd_ed_args <args...>: sets _ed_key, _ed_title, _ed_titlef, _ed_descf, _ed_metricf, _ed_size, _ed_risk, _ed_parent, _ed_ladd, _ed_lrem, _ed_dry. rc 2 on a usage fault.
bd_ed_args() {
  _ed_key=""; _ed_title=""; _ed_titlef=""; _ed_metricf=""; _ed_metric=""; _ed_mid=""; _ed_descf=""; _ed_size=""; _ed_risk=""; _ed_parent=""; _ed_dry=0; _ed_ladd=""; _ed_lrem=""; _ed_na=0; _ed_nr=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) _ed_dry=1; shift ;;
      --title|--title-file|--description-file|--metric-file|--size|--risk|--parent|--label-add|--label-remove)
        [ $# -ge 2 ] && [ -n "$2" ] || { echo "board edit: $1 needs a non-empty value" >&2; return 2; }
        case "$1" in
          --title) _ed_title=$2 ;;
          --title-file) _ed_titlef=$2 ;;
          --metric-file) _ed_metricf=$2 ;;
          --description-file) _ed_descf=$2 ;;
          --size) _ed_size=$2 ;;
          --risk) _ed_risk=$2 ;;
          --parent) _ed_parent=$2 ;;
          --label-add) bd_ed_label add "$2" || return 2 ;;
          --label-remove) bd_ed_label remove "$2" || return 2 ;;
        esac
        shift 2 ;;
      -*) echo "board edit: unknown option '$(printf '%s' "$1" | tr -d '[:cntrl:]')'" >&2; bd_usage; return 2 ;;
      *)  [ -z "$_ed_key" ] || { echo "board edit: one card key, not two" >&2; return 2; }; _ed_key=$1; shift ;;
    esac
  done
  [ -n "$_ed_key" ] || { echo "board edit: a card key is required" >&2; bd_usage; return 2; }
  bd_require_row "$_ed_key" || return 2
  [ -z "$_ed_title" ] || [ -z "$_ed_titlef" ] || { echo "board edit: --title and --title-file are mutually exclusive." >&2; return 2; }
  [ -n "$_ed_title$_ed_titlef$_ed_descf$_ed_metricf$_ed_size$_ed_risk$_ed_parent$_ed_ladd$_ed_lrem" ] \
    || { echo "board edit: nothing to change - pass at least one of --title, --title-file, --description-file, --metric-file, --size, --risk, --label-add, --label-remove, --parent" >&2; bd_usage; return 2; }
  return 0
}

# bd_ed_values: every value through the SAME grammar create uses (bd_val_ok / bd_row_ok / the text bounds), locally, before any request.
bd_ed_values() {
  [ -z "$_ed_titlef" ] || { bd_tf_load edit title "$_ed_titlef" || return 2; _ed_title=$_tf_val; }
  if [ -n "$_ed_title" ]; then
    bd_val_ok "$_ed_title" '\40-\176' 255 || { echo "board edit: --title must be 1..255 printable ASCII characters." >&2; return 2; }
    case "$_ed_title" in
      ' '*|*' ') echo "board edit: --title must not start or end with a space." >&2; return 2 ;;
    esac
  fi
  [ -z "$_ed_size" ] || bd_val_ok "$_ed_size" 'A-Za-z0-9 _.-' 64 || { echo "board edit: --size must match [A-Za-z0-9 _.-]{1,64}." >&2; return 2; }
  [ -z "$_ed_risk" ] || bd_val_ok "$_ed_risk" 'A-Za-z0-9 _.-' 64 || { echo "board edit: --risk must match [A-Za-z0-9 _.-]{1,64}." >&2; return 2; }
  [ -z "$_ed_parent" ] || bd_row_ok "$_ed_parent" || { echo "board edit: --parent must be an issue key matching [A-Z0-9][A-Z0-9-]*." >&2; return 2; }
  while IFS= read -r _ev_l; do
    [ -n "$_ev_l" ] || continue
    if printf '%s' "$_ed_lrem" | grep -qxF -e "$_ev_l"; then
      echo "board edit: the label '$_ev_l' is in both --label-add and --label-remove." >&2; return 2
    fi
  done <<EOF_EV
$_ed_ladd
EOF_EV
  _desc=""
  [ -z "$_ed_descf" ] || { bd_tf_load edit description "$_ed_descf" || return 2; _desc=$_tf_val; }
  [ -z "$_ed_metricf" ] || { bd_tf_load edit metric "$_ed_metricf" || return 2; _ed_metric=$_tf_val; }
  [ "$(printf '%s' "$_desc" | wc -c | tr -d ' ')" -le 32000 ] || { echo "board edit: the description is over the 32000-byte bound." >&2; return 2; }
  [ "$(bd_text_lines "$_desc")" -le 2000 ] || { echo "board edit: the description is over the 2000-line bound." >&2; return 2; }
  [ "$(printf '%s' "$_ed_metric" | wc -c | tr -d ' ')" -le 32000 ] || { echo "board edit: the metric is over the 32000-byte bound." >&2; return 2; }
  [ "$(bd_text_lines "$_ed_metric")" -le 2000 ] || { echo "board edit: the metric is over the 2000-line bound." >&2; return 2; }
  return 0
}

# bd_ed_cf <name>: sets _ed_cfid to the conf's field.<name> when it is a customfield_N (digits only), else refuses (rc 2).
bd_ed_cf() {
  _ed_cfid=$(bd_tc_get "field.$1")
  case "$_ed_cfid" in
    customfield_[0-9]*)
      case "${_ed_cfid#customfield_}" in
        *[!0-9]*) : ;;
        *) [ "${#_ed_cfid}" -gt 22 ] || return 0 ;;  # the adapter's 22-character bound on a customfield id
      esac ;;
  esac
  if [ "$1" = metric ]; then
    echo "board edit: --metric-file needs field.metric=customfield_N in .kit/tracker.conf (conf has '$(bd_disp "${_ed_cfid:-unset}")') - add that line, or drop --metric-file. Nothing was changed." >&2
    return 2
  fi
  echo "board edit: --$1 needs field.$1=customfield_N in .kit/tracker.conf (conf has '$(bd_disp "${_ed_cfid:-unset}")'); a label-mapped $1 is changed with --label-add / --label-remove. Nothing was changed." >&2
  return 2
}

# bd_ed_dry: print the planned change set (plain words, no request, no credential).
bd_ed_dry() {
  echo "board edit: DRY RUN - would change $_ed_key on project $_btproject; no tracker call was made (the select check against the card's editmeta runs only on the live edit):"
  [ -z "$_ed_title" ] || echo "  summary: \"$_ed_title\""
  [ -z "$_ed_descf" ] || echo "  description: replaced whole, $(printf '%s' "$_desc" | wc -c | tr -d ' ') bytes, $(bd_text_lines "$_desc") lines"
  [ -z "$_ed_metricf" ] || echo "  metric: replaced whole, $(printf '%s' "$_ed_metric" | wc -c | tr -d ' ') bytes, $(bd_text_lines "$_ed_metric") lines"
  [ -z "$_ed_size" ] || echo "  size: $_ed_size"
  [ -z "$_ed_risk" ] || echo "  risk: $_ed_risk"
  [ -z "$_ed_parent" ] || echo "  parent: $_ed_parent"
  [ -z "$_ed_ladd" ] || echo "  labels added: $(printf '%s' "$_ed_ladd" | tr '\n' ' ' | sed 's/ $//')"
  [ -z "$_ed_lrem" ] || echo "  labels removed: $(printf '%s' "$_ed_lrem" | tr '\n' ' ' | sed 's/ $//')"
  return 0
}

# bd_ed_meta: the card's own editmeta into $_cm (rc 1 = unverified, nothing changed).
bd_ed_meta() {
  _em_errf=$(mktemp) || { echo "board edit: could not create a scratch file." >&2; return 1; }
  _em_rc=0
  _cm=$(sh "$BD_JIRA_SH" edit-meta "$_btbase" "$_btflavour" "$_btproject" "$_ed_key" 2>"$_em_errf") || _em_rc=$?
  _em_err=$(tr '\n' ' ' < "$_em_errf" | tr -cd '\40-\176' | cut -c1-200); rm -f "$_em_errf"
  if [ "$_em_rc" -eq 6 ]; then bd_rejected edit "${_em_err:-the adapter reported the rejection}"; return 1; fi
  [ "$_em_rc" -eq 0 ] || { echo "board edit: could not read the editmeta of $_ed_key - ${_em_err:-unverified}; nothing was changed." >&2; return 1; }
  return 0
}

# bd_ed_need <field-id> <what>: the field must be in the card's editmeta ($_cm), else a named refusal before the PUT.
bd_ed_need() {
  bd_cr_has "$1" && return 0
  echo "board edit: $2 ($1) is not editable on $_ed_key - the card's editmeta does not list it; nothing was changed." >&2
  return 2
}

# bd_ed_expect <field-id> <expected>: what the post-read must show for this id (read back once).
bd_ed_expect() {
  _ed_exp="$_ed_exp$1$BD_TAB$2
"
  _ed_ids="$_ed_ids $1"
}

# bd_ed_select <size|risk> <value>: one select/string customfield into the fields object, matched against the card's editmeta.
bd_ed_select() {
  bd_ed_cf "$1" || return 2
  bd_ed_need "$_ed_cfid" "$1" || return 2
  bd_cu_value edit "$1" "$_ed_cfid" "$2" || return 2
  case "$_cu_schema" in
    option) _ed_ff=$(printf '%s' "$_ed_ff" | jq -c --arg id "$_ed_cfid" --arg v "$_cu_val" '. + {($id): {value: $v}}') ;;
    *)      _ed_ff=$(printf '%s' "$_ed_ff" | jq -c --arg id "$_ed_cfid" --arg v "$_cu_val" '. + {($id): $v}') ;;
  esac
  bd_ed_expect "$_ed_cfid" "$_cu_val"
  _ed_sel="$_ed_sel $_ed_cfid"
  [ "$1" = size ] && _ed_sid=$_ed_cfid
  [ "$1" = risk ] && _ed_rid=$_ed_cfid
  return 0
}

# bd_ed_build: the edit fragment {"fields": {...}, "update": {"labels": [add/remove ops]}} in $_ed_frag, and what the post-read must show.
bd_ed_build() {
  _ed_ff='{}'; _ed_ul='[]'; _ed_exp=""; _ed_ids=""; _ed_sel=""; _ed_sid="-"; _ed_rid="-"; _ed_mida="-"
  if [ -n "$_ed_title" ]; then
    bd_ed_need summary "--title" || return 2
    _ed_ff=$(printf '%s' "$_ed_ff" | jq -c --arg v "$_ed_title" '. + {summary: $v}')
    bd_ed_expect summary "$_ed_title"
  fi
  if [ -n "$_ed_descf" ]; then
    bd_ed_need description "--description-file" || return 2
    bd_cr_text "$_desc" || return 1
    _ed_ff=$(printf '%s' "$_ed_ff" | jq -c --argjson d "$_jv" '. + {description: $d}')
    bd_ed_expect description "present $(printf '%s' "$_desc" | wc -c | tr -d ' ')"
  fi
  if [ -n "$_ed_metricf" ]; then
    bd_ed_need "$_ed_mid" "--metric-file" || return 2
    bd_cr_text "$_ed_metric" || return 1
    _ed_ff=$(printf '%s' "$_ed_ff" | jq -c --arg id "$_ed_mid" --argjson d "$_jv" '. + {($id): $d}')
    # the `:text` token asks get-fields for the description's own proof (`present <bytes>`) on this customfield
    bd_ed_expect "$_ed_mid:text" "present $(printf '%s' "$_ed_metric" | wc -c | tr -d ' ')"
    _ed_mida=$_ed_mid
  fi
  if [ -n "$_ed_parent" ]; then
    bd_ed_need parent "--parent" || return 2
    _ed_ff=$(printf '%s' "$_ed_ff" | jq -c --arg k "$_ed_parent" '. + {parent: {key: $k}}')
    bd_ed_expect parent "$_ed_parent"
  fi
  [ -z "$_ed_size" ] || bd_ed_select size "$_ed_size" || return 2
  [ -z "$_ed_risk" ] || bd_ed_select risk "$_ed_risk" || return 2
  if [ -n "$_ed_ladd$_ed_lrem" ]; then
    bd_ed_need labels "--label-add/--label-remove" || return 2
    while IFS= read -r _eb_l; do
      [ -z "$_eb_l" ] || _ed_ul=$(printf '%s' "$_ed_ul" | jq -c --arg l "$_eb_l" '. + [{add: $l}]')
    done <<EOF_EBA
$_ed_ladd
EOF_EBA
    while IFS= read -r _eb_l; do
      [ -z "$_eb_l" ] || _ed_ul=$(printf '%s' "$_ed_ul" | jq -c --arg l "$_eb_l" '. + [{remove: $l}]')
    done <<EOF_EBR
$_ed_lrem
EOF_EBR
    _ed_ids="$_ed_ids labels"
  fi
  _ed_frag=$(jq -nc --argjson f "$_ed_ff" --argjson u "$_ed_ul" '(if ($f | length) > 0 then {fields: $f} else {} end) + (if ($u | length) > 0 then {update: {labels: $u}} else {} end)')
}

# bd_ed_prove: the post-read - every value written must read back EXACTLY (a select, the summary, the parent), a label delta by
# membership / absence, the description by `present <bytes>`. A mismatch is rc 1 naming the field; never "ok".
bd_ed_prove() {
  # shellcheck disable=SC2086  # _ed_ids is a space-separated list of closed-grammar field ids
  _pe_post=$(sh "$BD_JIRA_SH" get-fields "$_btbase" "$_btflavour" "$_btproject" "$_ed_key" $_ed_ids 2>&1) || {
    echo "board edit: edited '$_ed_key' but the post-read could not run - cannot prove the change (the card may have changed)." >&2
    return 1
  }
  while IFS="$BD_TAB" read -r _pe_id _pe_want; do
    [ -n "$_pe_id" ] || continue
    _pe_got=$(bd_field "$_pe_post" "$_pe_id")
    [ "$_pe_got" = "$_pe_want" ] || { echo "board edit: edited '$_ed_key' but the post-read did NOT prove $_pe_id (wanted '$(bd_disp "$_pe_want")', read '$(bd_disp "$_pe_got")') - the card may be half-changed; check it with \`board show $_ed_key\`." >&2; return 1; }
  done <<EOF_PE
$_ed_exp
EOF_PE
  _pe_labels=" $(bd_field "$_pe_post" labels) "
  while IFS= read -r _pe_l; do
    [ -n "$_pe_l" ] || continue
    case "$_pe_labels" in
      *" $_pe_l "*) : ;;
      *) echo "board edit: edited '$_ed_key' but the post-read did NOT prove the label '$_pe_l' was added." >&2; return 1 ;;
    esac
  done <<EOF_PA
$_ed_ladd
EOF_PA
  while IFS= read -r _pe_l; do
    [ -n "$_pe_l" ] || continue
    case "$_pe_labels" in
      *" $_pe_l "*) echo "board edit: edited '$_ed_key' but the post-read did NOT prove the label '$_pe_l' was removed." >&2; return 1 ;;
    esac
  done <<EOF_PR
$_ed_lrem
EOF_PR
  return 0
}

# bd_ed_summary: the fields that changed, for the OK line.
bd_ed_summary() {
  _es=""
  [ -z "$_ed_title" ] || _es="$_es summary"
  [ -z "$_ed_descf" ] || _es="$_es description"
  [ -z "$_ed_metricf" ] || _es="$_es metric"
  [ -z "$_ed_size" ] || _es="$_es size"
  [ -z "$_ed_risk" ] || _es="$_es risk"
  [ -z "$_ed_parent" ] || _es="$_es parent"
  [ -z "$_ed_ladd$_ed_lrem" ] || _es="$_es labels"
  printf '%s' "${_es# }" | sed 's/ /, /g'
}

do_edit() {
  bd_ed_args "$@" || return 2
  bd_ed_values || return 2
  bd_se_ready edit "$_ed_key" || return $?
  # --parent: the key's project is checked here (no request); the adapter then reads the parent's REAL key and project before
  # the PUT (a moved epic keeps its old key), so a re-parent can only land under a card that is in this project today.
  [ -z "$_ed_parent" ] || bd_cmt_key_ok "$_ed_parent" \
    || { echo "board edit: --parent '$(bd_disp "$_ed_parent")' is not a card key of project $_btproject - a card is never re-parented under another project; nothing was changed." >&2; return 1; }
  command -v jq >/dev/null 2>&1 || { echo "board edit: jq is required for edit (install jq)." >&2; return 2; }
  [ -z "$_ed_size" ] || bd_ed_cf size || return 2
  [ -z "$_ed_risk" ] || bd_ed_cf risk || return 2
  [ -z "$_ed_metricf" ] || { bd_ed_cf metric || return 2; _ed_mid=$_ed_cfid; }
  if [ "$_ed_dry" -eq 1 ]; then bd_ed_dry; return 0; fi
  bd_ed_meta || return 1
  bd_ed_build || return $?
  _ed_rc=0
  _ed_errf=$(mktemp) || { echo "board edit: could not create a scratch file." >&2; return 1; }
  printf '%s' "$_ed_frag" | sh "$BD_JIRA_SH" edit "$_btbase" "$_btflavour" "$_btproject" "$_ed_key" "$_ed_sid" "$_ed_rid" "$_ed_mida" - >/dev/null 2>"$_ed_errf" || _ed_rc=$?
  cat "$_ed_errf" >&2; _ed_anon=0
  if bd_anon_wrote "$_ed_errf"; then _ed_anon=1; fi
  rm -f "$_ed_errf"
  # the adapter's rc 1 is a refusal before/at the PUT (a 400, the allowlist, a key/project mismatch): stays rc 1. Any other failure
  # (a timeout, a 5xx, an unreadable answer) cannot say whether the edit applied: rc 3.
  case "$_ed_rc" in
    0) : ;;
    1) echo "board edit: the tracker refused the edit of $_ed_key (the adapter's sentence is above); no field is known to have changed." >&2; return 1 ;;
    6)
      # a 2xx served anonymously may have applied (S-L1): keep "may have applied" and the unverified rc 3
      if [ "$_ed_anon" -eq 1 ]; then echo "board edit: unverified - the tracker rejected the credential but served the edit anonymously, so it may have applied; check with board show $_ed_key" >&2; return 3; fi
      bd_rejected edit; return 1 ;;
    *) echo "board edit: unverified - the edit may have applied; check with board show $_ed_key" >&2; return 3 ;;
  esac
  bd_ed_prove || return 1
  echo "board edit: OK — $_ed_key $(bd_ed_summary), proven by post-read."
}

# ── rank / list (BOARD-RANK-VERB, design 2026-10-09 D3) ──────────────────────────────────────────
# `rank KEY (--top | --before KEY | --after KEY) [--dry-run]` moves a card in the tracker's Rank order (priority only:
# state, assignee and labels are untouched); `list [--limit N]` prints the open cards in that order. Both go through the
# adapter (tracker-jira.sh `rank` / `list-ranked`). `rank` reads the order BEFORE (KEY and any anchor must be open cards)
# and AFTER the write, and reports OK only when the read-back order proves the move (UNPROVEN, rc 2, otherwise).

# bd_rank_args <args…>: sets _rk_key/_rk_form (top|before|after)/_rk_anchor/_rk_dry. rc 2 on a usage fault.
bd_rank_args() {
  _rk_key=""; _rk_form=""; _rk_anchor=""; _rk_dry=0; _rk_forms=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --top)           _rk_forms=$((_rk_forms + 1)); _rk_form=top; shift ;;
      --before|--after)
        [ $# -ge 2 ] || { echo "board rank: $1 needs a card key" >&2; return 2; }
        _rk_forms=$((_rk_forms + 1)); _rk_form=${1#--}; _rk_anchor=$2; shift 2 ;;
      --dry-run)       _rk_dry=1; shift ;;
      -*)              echo "board rank: unknown option '$(printf '%s' "$1" | tr -d '[:cntrl:]')'" >&2; bd_usage; return 2 ;;
      *)               [ -z "$_rk_key" ] || { echo "board rank: one card key, not two" >&2; return 2; }; _rk_key=$1; shift ;;
    esac
  done
  [ -n "$_rk_key" ] || { echo "board rank: a card key is required" >&2; bd_usage; return 2; }
  [ "$_rk_forms" -eq 1 ] || { echo "board rank: give exactly one of --top, --before KEY, --after KEY" >&2; bd_usage; return 2; }
  bd_require_row "$_rk_key" || return 2
  [ -z "$_rk_anchor" ] || bd_require_row "$_rk_anchor"
}

# bd_rank_read: sets _rr_list (KEY<TAB>STATUS lines in rank order). The limit is the adapter's maximum, so a long
# board is not mistaken for a truncation. rc 1 on any adapter failure (its sentence is already on stderr).
bd_rank_read() {
  _rr_rc=0
  _rr_list=$(sh "$BD_JIRA_SH" list-ranked "$_btbase" "$_btflavour" "$_btproject" 1000) || _rr_rc=$?
  if [ "$_rr_rc" -eq 6 ]; then bd_rejected rank; return 1; fi
  [ "$_rr_rc" -eq 0 ] || { echo "board rank: could not read the open cards of $_btproject in rank order (the adapter's sentence is above)." >&2; return 1; }
  return 0
}

# bd_rank_pos <list> <KEY> -> the 1-based line of KEY, or nothing; bd_rank_at <list> <N> -> the key on line N, or nothing.
bd_rank_pos() { printf '%s\n' "$1" | awk -F '\t' -v k="$2" '$1 == k { print NR; exit }'; }
bd_rank_at()  { printf '%s\n' "$1" | awk -F '\t' -v n="$2" 'NR == n { print $1; exit }'; }

# bd_rank_verify <list> <form> <KEY> <ANCHOR>: 0 when the order read back proves the move.
bd_rank_verify() {
  _rv_pos=$(bd_rank_pos "$1" "$3")
  [ -n "$_rv_pos" ] || return 1
  case "$2" in
    top)    [ "$_rv_pos" -eq 1 ] ;;
    before) [ "$(bd_rank_at "$1" $((_rv_pos + 1)))" = "$4" ] ;;
    after)  [ "$(bd_rank_at "$1" $((_rv_pos - 1)))" = "$4" ] ;;
    *)      return 1 ;;
  esac
}

# bd_rank_plan: from the pre-read list, resolves _rk_dir/_rk_anchor. rc 2 when KEY or the anchor is not an open card;
# rc 3 when --top and KEY already leads (nothing to write).
bd_rank_plan() {
  [ -n "$(bd_rank_pos "$_rr_list" "$_rk_key")" ] || { echo "board rank: $_rk_key is not an open card on $_btproject." >&2; return 2; }
  # where the card sits now, so a bad move can be undone: first, or right after this neighbour
  _rk_p=$(bd_rank_pos "$_rr_list" "$_rk_key")
  if [ "$_rk_p" -eq 1 ]; then _rk_was="was first"; else _rk_was="was after $(bd_rank_at "$_rr_list" $((_rk_p - 1)))"; fi
  if [ "$_rk_form" = top ]; then
    _rk_anchor=$(bd_rank_at "$_rr_list" 1)
    [ "$_rk_anchor" != "$_rk_key" ] || return 3
    _rk_dir=before
    return 0
  fi
  _rk_dir=$_rk_form
  [ -n "$(bd_rank_pos "$_rr_list" "$_rk_anchor")" ] || { echo "board rank: $_rk_anchor is not an open card on $_btproject." >&2; return 2; }
  return 0
}

do_rank() {
  bd_rank_args "$@" || return 2
  _be=$(bd_backend)
  case "$_be" in
    jira) : ;;
    md|'') echo "board rank: the markdown board's order is its Order line; edit BACKLOG.md" >&2; return 2 ;;
    *)     echo "board rank: undeclared or unsupported backend '$_be'." >&2; return 2 ;;
  esac
  bd_tracker_ctx || return 2
  bd_cmt_key_ok "$_rk_key" || { echo "board rank: '$_rk_key' is not a card key of project $_btproject." >&2; return 2; }
  if [ -n "$_rk_anchor" ]; then
    bd_cmt_key_ok "$_rk_anchor" || { echo "board rank: '$_rk_anchor' is not a card key of project $_btproject." >&2; return 2; }
    [ "$_rk_anchor" != "$_rk_key" ] || { echo "board rank: a card cannot be ranked against itself." >&2; return 2; }
  fi
  bd_rank_read || return 1
  _rk_prc=0; bd_rank_plan || _rk_prc=$?
  if [ "$_rk_prc" -eq 3 ]; then echo "board rank: $_rk_key is already first"; return 0; fi
  [ "$_rk_prc" -eq 0 ] || return "$_rk_prc"
  if [ "$_rk_dry" -eq 1 ]; then
    echo "board rank: would PUT /rest/agile/1.0/issue/rank: $_rk_key $_rk_dir $_rk_anchor"
    return 0
  fi
  _rk_wrc=0
  _rk_errf=$(mktemp) || { echo "board rank: could not create a scratch file." >&2; return 1; }
  sh "$BD_JIRA_SH" rank "$_btbase" "$_btflavour" "$_btproject" "$_rk_key" "$_rk_dir" "$_rk_anchor" >/dev/null 2>"$_rk_errf" || _rk_wrc=$?
  cat "$_rk_errf" >&2; _rk_anon=0
  if bd_anon_wrote "$_rk_errf"; then _rk_anon=1; fi
  rm -f "$_rk_errf"
  # the adapter's rc 1 is a grammar refusal this front door should have caught (usage-class, rc 2); any other failure
  # is the write or its proof (rc 1)
  case "$_rk_wrc" in
    0) : ;;
    1) return 2 ;;
    6)
      if [ "$_rk_anon" -eq 1 ]; then echo "board rank: the tracker rejected the credential but served the rank anonymously - the order may have changed; read it back with board list ($_rk_key $_rk_was)." >&2
      else bd_rejected rank; fi
      return 1 ;;
    *) echo "board rank: $_rk_key was not ranked (the adapter's sentence is above)." >&2; return 1 ;;
  esac
  if ! bd_rank_read; then
    echo "board rank: UNPROVEN - the write was accepted but the post-read failed; read the order back with board list ($_rk_key $_rk_was)" >&2
    return 2
  fi
  if bd_rank_verify "$_rr_list" "$_rk_form" "$_rk_key" "$_rk_anchor"; then
    _rk_n=$(printf '%s\n' "$_rr_list" | awk 'END { print NR }')
    echo "board rank: OK - $_rk_key now $_rk_dir $_rk_anchor (position $(bd_rank_pos "$_rr_list" "$_rk_key") of $_rk_n open cards), proven by post-read. ($_rk_key $_rk_was)"
    return 0
  fi
  echo "board rank: UNPROVEN - the tracker took the write but the order read back differs (a concurrent re-rank?) ($_rk_key $_rk_was)" >&2
  return 2
}

do_list() {
  _ls_limit=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --limit)
        [ $# -ge 2 ] || { echo "board list: --limit needs a value" >&2; return 2; }
        _ls_limit=$2; shift 2
        case "$_ls_limit" in
          ''|*[!0-9]*) echo "board list: --limit must be digits" >&2; return 2 ;;
        esac ;;
      -*) echo "board list: unknown option '$(printf '%s' "$1" | tr -d '[:cntrl:]')'" >&2; bd_usage; return 2 ;;
      *)  echo "board list: takes no argument" >&2; bd_usage; return 2 ;;
    esac
  done
  _be=$(bd_backend)
  case "$_be" in
    jira) : ;;
    md|'') echo "board list: the markdown board's order is its Order line; read BACKLOG.md" >&2; return 2 ;;
    *)     echo "board list: undeclared or unsupported backend '$_be'." >&2; return 2 ;;
  esac
  bd_tracker_ctx || return 2
  _ls_rc=0
  if [ -n "$_ls_limit" ]; then
    _ls_out=$(sh "$BD_JIRA_SH" list-ranked "$_btbase" "$_btflavour" "$_btproject" "$_ls_limit") || _ls_rc=$?
  else
    _ls_out=$(sh "$BD_JIRA_SH" list-ranked "$_btbase" "$_btflavour" "$_btproject") || _ls_rc=$?
  fi
  case "$_ls_rc" in
    0) : ;;
    1) return 2 ;;
    6) bd_rejected list; return 1 ;;
    *) echo "board list: could not read the open cards in rank order (the adapter's sentence is above)." >&2; return 1 ;;
  esac
  printf 'open cards on %s, in rank order:\n' "$_btproject"
  [ -z "$_ls_out" ] || printf '%s\n' "$_ls_out"
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
# SWAS-113: the anonymous-write suffix the adapter's rc-6 sentence carries when a leg asks for it
sfx=""
if [ -n "${STUB_ANON_SUFFIX:-}" ]; then sfx=" (the write may have applied anonymously)"; fi
echo "$*" >> "$log"
if [ -n "${STUB_AUTH_LOG:-}" ]; then echo "${KIT_TRACKER_AUTH:-unset}" >> "$STUB_AUTH_LOG"; fi
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
    # rc 6 = the adapter's "Jira did not accept the credential" (SWAS-113)
    if [ "${STUB_TRANSITION_RC:-0}" = 6 ]; then echo "unverified: stub credential rejected$sfx" >&2; exit 6; fi
    STUB_STATE=$6
    if [ -n "${STUB_STATE_FILE:-}" ]; then printf '%s' "$STUB_STATE" > "$STUB_STATE_FILE"; fi
    exit 0 ;;
  create)
    [ "${STUB_CREATE_FAIL:-0}" = 1 ] && exit 1
    # STUB_CREATE_RC: the adapter's own rc (6 = the credential was rejected, SWAS-113)
    if [ -n "${STUB_CREATE_RC:-}" ]; then echo "unverified: stub create failure$sfx" >&2; exit "$STUB_CREATE_RC"; fi
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
  comment)
    # `comment <base> <flavour> <project> <KEY> -`: the body arrives on STDIN (never argv); a leg compares it byte-for-byte.
    # STUB_COMMENT_RC non-zero = the adapter's refusal/failure with that rc and one fixed sentence
    if [ -n "${STUB_BODY_FILE:-}" ]; then cat > "$STUB_BODY_FILE"; else cat > /dev/null; fi
    if [ "${STUB_COMMENT_RC:-0}" != 0 ]; then echo "unverified: stub comment failure$sfx" >&2; exit "$STUB_COMMENT_RC"; fi
    printf '%s\n' "${STUB_COMMENT_ID:-10042}"
    exit 0 ;;
  show)
    # `show <base> <flavour> <project> <KEY> <size-map> <risk-map> <n>`: prints the leg's recorded card text; STUB_SHOW_RC non-zero = the adapter's rc
    if [ "${STUB_SHOW_RC:-0}" != 0 ]; then echo "unverified: stub show failure" >&2; exit "$STUB_SHOW_RC"; fi
    [ -n "${STUB_SHOW:-}" ] && [ -f "$STUB_SHOW" ] || exit 2
    cat "$STUB_SHOW"
    exit 0 ;;
  edit-meta)
    # the card's editmeta lines from $STUB_EM (rc 2 when the leg sets none)
    if [ "${STUB_EM_RC:-0}" != 0 ]; then echo "unverified: stub editmeta failure" >&2; exit "$STUB_EM_RC"; fi
    [ -n "${STUB_EM:-}" ] && [ -f "$STUB_EM" ] || exit 2
    cat "$STUB_EM"
    exit 0 ;;
  edit)
    # `edit <base> <flavour> <project> <KEY> <size-id|-> <risk-id|-> <metric-id|-> -`: the fragment arrives on STDIN; a leg compares it byte-for-byte
    if [ -n "${STUB_BODY_FILE:-}" ]; then cat > "$STUB_BODY_FILE"; else cat > /dev/null; fi
    if [ "${STUB_EDIT_RC:-0}" != 0 ]; then echo "refused: stub edit failure$sfx" >&2; exit "$STUB_EDIT_RC"; fi
    printf 'ok\n'
    exit 0 ;;
  rank)
    # `rank <base> <flavour> <project> KEY dir ANCHOR`: STUB_RANK_RC non-zero = that failure; else the write is marked done
    # (the file STUB_RANK_DONE), which switches `list-ranked` from STUB_RANKED_PRE to STUB_RANKED_POST
    if [ "${STUB_RANK_RC:-0}" != 0 ]; then echo "unverified: stub rank failure$sfx" >&2; exit "$STUB_RANK_RC"; fi
    if [ -n "${STUB_RANK_DONE:-}" ]; then : > "$STUB_RANK_DONE"; fi
    printf 'ranked %s %s %s\n' "$5" "$6" "$7"
    exit 0 ;;
  list-ranked)
    # KEY<TAB>STATUS lines from STUB_RANKED_PRE, or from STUB_RANKED_POST once a rank has been written
    if [ "${STUB_LIST_RC:-0}" != 0 ]; then echo "unverified: stub list failure" >&2; exit "$STUB_LIST_RC"; fi
    # STUB_LIST_RC_AFTER: fail only once the write is done (the post-read)
    if [ "${STUB_LIST_RC_AFTER:-0}" != 0 ] && [ -n "${STUB_RANK_DONE:-}" ] && [ -f "$STUB_RANK_DONE" ]; then
      echo "unverified: stub post-read failure" >&2; exit "$STUB_LIST_RC_AFTER"
    fi
    _lf="${STUB_RANKED_PRE:-}"
    if [ -n "${STUB_RANK_DONE:-}" ] && [ -f "$STUB_RANK_DONE" ] && [ -n "${STUB_RANKED_POST:-}" ]; then _lf=$STUB_RANKED_POST; fi
    [ -n "$_lf" ] && [ -f "$_lf" ] || exit 2
    cat "$_lf"
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

  # ── release legs (LAND-WRITES-CARD-STATE): on a tracker, `--stale` (proof: a merged PR) ends at state.done and a
  # plain release ends at state.ready. A gh stub on PATH answers release-ref's P2 query from $bd_gh/prlist. ────────
  bd_gh="$bd_base/gh"; mkdir -p "$bd_gh"; printf 'MERGED false\n' > "$bd_gh/prlist"
  cat > "$bd_gh/gh" <<'GH_EOF'
#!/bin/sh
case "$1" in pr) cat "$(dirname "$0")/prlist" ;; *) exit 1 ;; esac
GH_EOF
  chmod +x "$bd_gh/gh"
  bd_rl_log="$bd_base/.rllog"; bd_rl_sf="$bd_base/.rlsf"
  bd_refpresent() { git ls-remote "$bd_remote" "refs/claims/$1" 2>/dev/null | grep -q "refs/claims/$1"; }
  # bd_rl_claim <ROW>: take a real claim (the stub card ends In Progress), log reset
  bd_rl_claim() {
    printf 'Selected for Development' > "$bd_rl_sf"
    (cd "$bd_jclone" && STUB_STATE_FILE="$bd_rl_sf" do_claim "$1" --branch "feat/$1") >/dev/null 2>&1 || true
    : > "$bd_rl_log"
  }
  # bd_rl <ROW> [args]: one release, in-process, gh stubbed, the stub card state in $bd_rl_sf, STUB_* passed through
  bd_rl() {
    _rl_row=$1; shift
    bd_out=$(cd "$bd_jclone" && PATH="$bd_gh:$PATH" STUB_LOG="$bd_rl_log" STUB_STATE_FILE="$bd_rl_sf" do_release "$_rl_row" "$@" 2>&1); bd_rc=$?
  }

  # C3 (positive): a held claim + a merged PR -> `--stale` ends at Done, the ref is gone, proven by the post-read
  bd_rl_claim AB-10
  bd_rl AB-10 --stale
  if [ "$bd_rc" -eq 0 ] && [ "$(cat "$bd_rl_sf")" = Done ] && ! bd_refpresent AB-10 && grep -q '^transition .* AB-10 Done$' "$bd_rl_log"; then
    bd_pass "leg jira/release-stale-done: release --stale on a held claim + merged PR ends the card at Done and deletes the ref, proven by post-read"
  else bd_fail_ "leg jira/release-stale-done: rc=$bd_rc state=[$(cat "$bd_rl_sf")] out=[$bd_out]"; fi

  # C3 (negative): the holder's plain release is NOT the merged close — it still ends at Ready, never Done
  bd_rl_claim AB-11
  bd_rl AB-11
  if [ "$bd_rc" -eq 0 ] && [ "$(cat "$bd_rl_sf")" = 'Selected for Development' ] && ! bd_refpresent AB-11; then
    bd_pass "leg jira/release-plain-ready: a plain release (abandoned claim) still ends at Ready, not Done"
  else bd_fail_ "leg jira/release-plain-ready: rc=$bd_rc state=[$(cat "$bd_rl_sf")] out=[$bd_out]"; fi

  # C4 (negative): the transition fails -> rc 1, the card is not Done, and the claim ref is STILL HELD (S-5 order)
  bd_rl_claim AB-12
  bd_out=$(cd "$bd_jclone" && PATH="$bd_gh:$PATH" STUB_LOG="$bd_rl_log" STUB_STATE_FILE="$bd_rl_sf" STUB_TRANSITION_FAIL=1 do_release AB-12 --stale 2>&1); bd_rc=$?
  if [ "$bd_rc" -eq 1 ] && [ "$(cat "$bd_rl_sf")" = 'In Progress' ] && bd_refpresent AB-12; then
    bd_pass "leg jira/release-stale-order: a failed transition leaves rc 1, the card unmoved and refs/claims/AB-12 still held (S-5)"
  else bd_fail_ "leg jira/release-stale-order: rc=$bd_rc state=[$(cat "$bd_rl_sf")] ref=$(bd_refpresent AB-12 && echo held || echo gone) out=[$bd_out]"; fi

  # C5 (negative): the card is already Done and no ref is held -> rc 0 and NO transition call reached the adapter
  printf 'Done' > "$bd_rl_sf"; : > "$bd_rl_log"
  bd_rl AB-13 --stale
  if [ "$bd_rc" -eq 0 ] && ! grep -q '^transition ' "$bd_rl_log" && printf '%s' "$bd_out" | grep -q 'no claim to release'; then
    bd_pass "leg jira/release-stale-idempotent: an already-Done card with no claim is rc 0 and makes no transition call"
  else bd_fail_ "leg jira/release-stale-idempotent: rc=$bd_rc log=[$(cat "$bd_rl_log")] out=[$bd_out]"; fi
  # ...and with the claim still held on a Done card: ref-only (no transition), the ref is deleted
  bd_rl_claim AB-14
  printf 'Done' > "$bd_rl_sf"
  bd_rl AB-14 --stale
  if [ "$bd_rc" -eq 0 ] && ! grep -q '^transition ' "$bd_rl_log" && ! bd_refpresent AB-14; then
    bd_pass "leg jira/release-stale-done-held: an already-Done card with a held ref is released ref-only (no transition call)"
  else bd_fail_ "leg jira/release-stale-done-held: rc=$bd_rc log=[$(cat "$bd_rl_log")] ref=$(bd_refpresent AB-14 && echo held || echo gone) out=[$bd_out]"; fi

  # no claim ref, card not Done: the card is still moved (a manual forge-UI merge), and the output says there was no claim
  printf 'In Progress' > "$bd_rl_sf"; : > "$bd_rl_log"
  bd_rl AB-15 --stale
  if [ "$bd_rc" -eq 0 ] && [ "$(cat "$bd_rl_sf")" = Done ] && printf '%s' "$bd_out" | grep -q 'no claim to release' \
     && printf '%s' "$bd_out" | grep -qF "UNPROVEN — no claim ref on 'AB-15', so no merged-PR proof was checked; moving to 'Done' on the caller's word." \
     && printf '%s' "$bd_out" | grep -qF 'merge proof not checked'; then
    bd_pass "leg jira/release-stale-noclaim: no claim ref + card not Done -> the card is moved to Done, the output says no claim and UNPROVEN"
  else bd_fail_ "leg jira/release-stale-noclaim: rc=$bd_rc state=[$(cat "$bd_rl_sf")] out=[$bd_out]"; fi

  # the merged-PR proof still gates a HELD claim: an unmerged PR refuses before any transition
  bd_rl_claim AB-16
  printf 'CLOSED false\n' > "$bd_gh/prlist"
  bd_rl AB-16 --stale
  printf 'MERGED false\n' > "$bd_gh/prlist"
  if [ "$bd_rc" -eq 1 ] && [ "$(cat "$bd_rl_sf")" = 'In Progress' ] && bd_refpresent AB-16 && ! grep -q '^transition ' "$bd_rl_log"; then
    bd_pass "leg jira/release-stale-unproven: a held claim without a merged PR is refused before any transition (the card is not closed on no proof)"
  else bd_fail_ "leg jira/release-stale-unproven: rc=$bd_rc state=[$(cat "$bd_rl_sf")] out=[$bd_out]"; fi

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

  # legs (create-label-flag, KIT-TREE-BOARD-MIGRATION): --label is repeatable, grammar-bound and capped at 10; a label
  # reaches .labels in the create body (beside any size:/risk: label) and is proven by the post-read; every refusal is
  # rc 2 with ZERO POSTs.
  cp "$bd_cr_gf" "$bd_base/.gf.save"
  bd_conf customfield_10046 customfield_10047 cloud
  printf 'issuetype\tTask\nlabels\tparked ab:cd_1.2\n' > "$bd_cr_gf"
  bd_cr --title "x" --label parked --label ab:cd_1.2
  if [ "$bd_rc" -eq 0 ] && [ "$(cat "$bd_cr_body")" = '{"labels":["parked","ab:cd_1.2"]}' ] && [ "$(bd_posts)" = 1 ]; then
    bd_pass "leg jira/create-label-flag: two --label values reach .labels in the create body, one POST, proven by the post-read"
  else bd_fail_ "leg jira/create-label-flag: rc=$bd_rc posts=$(bd_posts) body=[$(cat "$bd_cr_body" 2>/dev/null)] out=[$bd_out]"; fi
  bd_conf label:size label:risk cloud
  printf 'issuetype\tTask\nlabels\tsize:S parked\n' > "$bd_cr_gf"
  bd_cr --title "x" --size S --label parked
  if [ "$bd_rc" -eq 0 ] && [ "$(cat "$bd_cr_body")" = '{"labels":["size:S","parked"]}' ]; then
    bd_pass "leg jira/create-label-flag-merge: --label is appended to the labels a label:size mapping already writes"
  else bd_fail_ "leg jira/create-label-flag-merge: rc=$bd_rc body=[$(cat "$bd_cr_body" 2>/dev/null)] out=[$bd_out]"; fi
  bd_cr --title "x" --label 'a b'
  bd_rc1=$bd_rc; bd_p1=$(bd_posts)
  bd_cr --title "x" --label l1 --label l2 --label l3 --label l4 --label l5 --label l6 --label l7 --label l8 --label l9 --label l10 --label l11
  bd_rc2=$bd_rc; bd_p2=$(bd_posts)
  bd_cr --title "x" --label 'a"b'
  bd_rc3=$bd_rc; bd_p3=$(bd_posts)
  if [ "$bd_rc1" -eq 2 ] && [ "$bd_p1" = 0 ] && [ "$bd_rc2" -eq 2 ] && [ "$bd_p2" = 0 ] && [ "$bd_rc3" -eq 2 ] && [ "$bd_p3" = 0 ]; then
    bd_pass "leg jira/create-label-flag-grammar: a label with a space or a quote, and an eleventh label, each refuse rc 2 with zero POSTs"
  else bd_fail_ "leg jira/create-label-flag-grammar: rc=$bd_rc1/$bd_rc2/$bd_rc3 posts=$bd_p1/$bd_p2/$bd_p3"; fi
  printf 'Task\tcustomfield_10046\toption\tSize\tXS|S|M|L|XL\nTask\tdescription\tstring\tDescription\t\n' > "$bd_cmdir/nolabels/Task.txt"
  bd_cm_cur="$bd_cmdir/nolabels"; bd_cr --title "x" --label parked; bd_cm_cur="$bd_cmdir"
  if [ "$bd_rc" -eq 2 ] && [ "$(bd_posts)" = 0 ] && printf '%s' "$bd_out" | grep -qF 'no labels field'; then
    bd_pass "leg jira/create-label-flag-screen: a type whose create screen has no labels field refuses --label with zero POSTs"
  else bd_fail_ "leg jira/create-label-flag-screen: rc=$bd_rc posts=$(bd_posts) out=[$bd_out]"; fi
  cp "$bd_base/.gf.save" "$bd_cr_gf"

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

  # ── --metric legs (KIT-TREE-BOARD-SWITCH, D8): the text shaper writes it to the conf's field.metric; unmapped or
  # off-screen refuses with ZERO POSTs, naming the conf line ─────────────────────────────────────────────────────
  mkdir -p "$bd_cmdir/metric" "$bd_cmdir/metricdc"
  { bd_cm_lines Task 10046 10047; printf 'Task\tcustomfield_10077\tstring\tSuccess metric\t\n'; } > "$bd_cmdir/metric/Task.txt"
  printf 'Task\tcustomfield_10077\tstring\tSuccess metric\t\nTask\tdescription\tstring\tDescription\t\n' > "$bd_cmdir/metricdc/Task.txt"
  bd_cx='field.metric=customfield_10077'; bd_conf - - cloud
  printf 'issuetype\tTask\ncustomfield_10077\tpresent\n' > "$bd_cr_gf"
  bd_cm_cur="$bd_cmdir/metric"; bd_cr --title "x" --metric "Adoption rises
second line"; bd_cm_cur="$bd_cmdir"
  bd_want='{"customfield_10077":{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"Adoption rises"}]},{"type":"paragraph","content":[{"type":"text","text":"second line"}]}]}}'
  if [ "$bd_rc" -eq 0 ] && [ "$(cat "$bd_cr_body" 2>/dev/null)" = "$bd_want" ] && [ "$(bd_posts)" = 1 ]; then
    bd_pass "leg jira/create-metric: --metric reaches field.metric as an ADF document on Cloud, one POST, proven present by the post-read"
  else bd_fail_ "leg jira/create-metric: rc=$bd_rc posts=$(bd_posts) body=[$(cat "$bd_cr_body" 2>/dev/null)] out=[$bd_out]"; fi
  bd_conf - - datacenter
  printf 'issuetype\tTask\ncustomfield_10077\tplain metric\n' > "$bd_cr_gf"
  bd_cm_cur="$bd_cmdir/metricdc"; bd_cr --title "x" --metric "plain metric"; bd_cm_cur="$bd_cmdir"
  if [ "$bd_rc" -eq 0 ] && [ "$(cat "$bd_cr_body" 2>/dev/null)" = '{"customfield_10077":"plain metric"}' ] && [ "$(bd_posts)" = 1 ]; then
    bd_pass "leg jira/create-metric-dc: --metric on Data Center is a plain string, one POST, proven by the post-read"
  else bd_fail_ "leg jira/create-metric-dc: rc=$bd_rc posts=$(bd_posts) body=[$(cat "$bd_cr_body" 2>/dev/null)] out=[$bd_out]"; fi
  bd_cx=""; bd_conf - - cloud
  bd_cm_cur="$bd_cmdir/metric"; bd_cr --title "x" --metric "m"; bd_cm_cur="$bd_cmdir"
  bd_rc1=$bd_rc; bd_p1=$(bd_posts); bd_o1=$bd_out
  bd_cx='field.metric=none'; bd_conf - - cloud
  bd_cm_cur="$bd_cmdir/metric"; bd_cr --title "x" --metric "m"; bd_cm_cur="$bd_cmdir"; bd_cx=""
  if [ "$bd_rc1" -eq 2 ] && [ "$bd_p1" = 0 ] && printf '%s' "$bd_o1" | grep -qF 'field.metric=customfield_N' \
     && [ "$bd_rc" -eq 2 ] && [ "$(bd_posts)" = 0 ] && printf '%s' "$bd_out" | grep -qF "conf has 'none'"; then
    bd_pass "leg jira/create-metric-unmapped: --metric with field.metric unset, or none, is refused (rc 2) with zero POSTs, naming the conf line to add"
  else bd_fail_ "leg jira/create-metric-unmapped: rc=$bd_rc1/$bd_rc posts=$bd_p1/$(bd_posts) o1=[$bd_o1] out=[$bd_out]"; fi
  bd_cx='field.metric=customfield_10077'; bd_conf - - cloud
  bd_cr --title "x" --metric "m"; bd_cx=""
  if [ "$bd_rc" -eq 2 ] && [ "$(bd_posts)" = 0 ] && printf '%s' "$bd_out" | grep -qF 'create screen'; then
    bd_pass "leg jira/create-metric-screen: a mapped field.metric that is not on the type's create screen is refused (rc 2, zero POSTs)"
  else bd_fail_ "leg jira/create-metric-screen: rc=$bd_rc posts=$(bd_posts) out=[$bd_out]"; fi

  # ── comment legs (KIT-TREE-BOARD-SWITCH §6.5 legs 10-13, B1 --from-record): the adapter is the stub; the record carries
  # TOPSECRET so an argv/log/echo leak is visible, and its SECOND line must never reach the stub at all ───────────────
  bd_cb="$bd_base/.cwant"; bd_cl="$bd_base/.cmtlog"; bd_cbo="$bd_base/.cmtcaptured"
  bd_cclone="$bd_base/cmt-clone"; bd_sclone="$bd_base/cmt-symclone"
  cp -R "$bd_jclone" "$bd_cclone"; cp -R "$bd_jclone" "$bd_sclone"
  (
    cd "$bd_cclone"
    mkdir -p docs/reviews
    printf 'TOPSECRET first line\nTOPSECRETBODY2 second line\n' > docs/reviews/x.md
    printf 'TOPSECRET notes\n' > docs/reviews/n.txt
    printf 'TOPSECRET\033x\n' > docs/reviews/c.md
    printf 'TOPSECRET\tx\n' > docs/reviews/t.md
    printf '   \nTOPSECRET second line\n' > docs/reviews/b.md
    : > docs/reviews/e.md
    awk 'BEGIN{printf "TOPSECRET"; for(i=0;i<300;i++) printf "T"; print ""}' > docs/reviews/big.md
    ln -s x.md docs/reviews/l.md
    git add docs/reviews/x.md docs/reviews/n.txt docs/reviews/c.md docs/reviews/t.md docs/reviews/b.md docs/reviews/e.md docs/reviews/big.md docs/reviews/l.md
    printf 'TOPSECRET untracked\n' > docs/reviews/u.md
  )
  (
    cd "$bd_sclone"
    mkdir -p real docs
    printf 'TOPSECRET first line\n' > real/x.md
    ln -s ../real docs/reviews
  )
  printf 'TOPSECRET first line\nRecord: docs/reviews/x.md\n' > "$bd_cb"
  bd_cmt() { # <dir> <args…>: one comment, in-process; the stub log is reset and its captured stdin lands in $bd_cbo
    _cd_dir=$1; shift
    : > "$bd_cl"; rm -f "$bd_cbo"
    bd_out=$(cd "$_cd_dir" && STUB_LOG="$bd_cl" STUB_BODY_FILE="$bd_cbo" do_comment "$@" 2>&1); bd_rc=$?
  }
  # leg 10: --dry-run makes no adapter call and needs no credentials
  bd_nbytes=$(wc -c < "$bd_cb" | tr -d ' ')
  bd_out=$( (unset KIT_TRACKER_USER KIT_TRACKER_TOKEN KIT_TRACKER_AUTH JIRA_EMAIL JIRA_TOKEN; : > "$bd_cl"; cd "$bd_cclone" && STUB_LOG="$bd_cl" do_comment AB-7 --from-record docs/reviews/x.md --dry-run 2>&1) ); bd_rc=$?
  if [ "$bd_rc" -eq 0 ] && [ ! -s "$bd_cl" ] \
     && [ "$bd_out" = "board comment: would POST a $bd_nbytes-byte, 2-line comment to AB-7 (dry run; no tracker call)" ]; then
    bd_pass "leg comment/dry-run: --dry-run with no credentials prints the byte and line count and makes no adapter call"
  else bd_fail_ "leg comment/dry-run: rc=$bd_rc adapter-calls=$([ -s "$bd_cl" ] && echo yes || echo no) out=[$bd_out]"; fi
  # leg 11: on md the verb refuses rc 2 BEFORE it reads the record (the record path does not even exist)
  bd_cmt "$bd_base/md-clone" AB-7 --from-record docs/reviews/no-such.md
  if [ "$bd_rc" -eq 2 ] && [ ! -s "$bd_cl" ] && printf '%s' "$bd_out" | grep -qF 'on md the retro rides the PR' \
     && ! printf '%s' "$bd_out" | grep -qF 'regular file'; then
    bd_pass "leg comment/md: on an md backend comment refuses rc 2 (the retro rides the PR) before it reads the body"
  else bd_fail_ "leg comment/md: rc=$bd_rc out=[$bd_out]"; fi
  # leg 12: every record-path and first-line refusal is rc 2 with ZERO adapter calls, no record byte echoed, and the
  # sentence that names the check that fired (so a deleted check turns its own row red, not a neighbour's)
  bd_bad=0
  bd_cmt_refuse() { # <dir> <sentence fragment> <args…>
    _cr_dir=$1; _cr_frag=$2; shift 2
    bd_cmt "$_cr_dir" AB-7 "$@"
    [ "$bd_rc" -eq 2 ] && [ ! -s "$bd_cl" ] || bd_bad=1
    ! printf '%s' "$bd_out" | grep -qF 'TOPSECRET' || bd_bad=1
    printf '%s' "$bd_out" | grep -qF "$_cr_frag" || bd_bad=1
  }
  bd_cmt_refuse "$bd_cclone" 'must be docs/reviews/<name>.md' --from-record .env
  bd_cmt_refuse "$bd_cclone" 'must be docs/reviews/<name>.md' --from-record 'docs/reviews/../../x.md'
  bd_cmt_refuse "$bd_cclone" 'must be docs/reviews/<name>.md' --from-record "$bd_cclone/docs/reviews/x.md"
  bd_cmt_refuse "$bd_cclone" 'must be docs/reviews/<name>.md' --from-record docs/reviews/n.txt
  bd_cmt_refuse "$bd_cclone" 'must be docs/reviews/<name>.md' --from-record 'docs/reviews/a b.md'
  bd_cmt_refuse "$bd_cclone" 'symlink' --from-record docs/reviews/l.md
  bd_cmt_refuse "$bd_sclone" 'symlink' --from-record docs/reviews/x.md
  bd_cmt_refuse "$bd_cclone" 'readable regular file' --from-record docs/reviews/none.md
  bd_cmt_refuse "$bd_cclone" 'tracked in git' --from-record docs/reviews/u.md
  bd_cmt_refuse "$bd_cclone" 'first line must be' --from-record docs/reviews/c.md
  bd_cmt_refuse "$bd_cclone" 'first line must be' --from-record docs/reviews/t.md
  bd_cmt_refuse "$bd_cclone" 'first line must be' --from-record docs/reviews/b.md
  bd_cmt_refuse "$bd_cclone" 'first line must be' --from-record docs/reviews/e.md
  bd_cmt_refuse "$bd_cclone" 'first line must be' --from-record docs/reviews/big.md
  for bd_k in XY-1 AB-07 'AB-1;x'; do
    bd_cmt "$bd_cclone" "$bd_k" --from-record docs/reviews/x.md
    [ "$bd_rc" -eq 2 ] && [ ! -s "$bd_cl" ] || bd_bad=1
  done
  if [ "$bd_bad" -eq 0 ]; then
    bd_pass "leg comment/refusals: a dotenv-named path, '..', an absolute path, a non-.md file, a symlinked leaf, a symlinked docs/reviews, a missing record, an untracked record, a control-byte / TAB / blank / empty / over-300-byte first line, another project's key and a leading-zero key each refuse rc 2 with zero adapter calls and no record byte echoed"
  else bd_fail_ "leg comment/refusals: bad=$bd_bad (last rc=$bd_rc out=[$bd_out])"; fi
  # leg 13: the composed body (first line + the Record line, NOT the second line) reaches the stub on stdin byte-for-byte
  # and is absent from the stub's argv log
  bd_cmt "$bd_cclone" AB-7 --from-record docs/reviews/x.md
  if [ "$bd_rc" -eq 0 ] && cmp -s "$bd_cb" "$bd_cbo" && ! grep -qF 'TOPSECRET' "$bd_cl" \
     && ! grep -qF 'TOPSECRETBODY2' "$bd_cbo" \
     && grep -qxF 'comment https://ex.atlassian.net cloud AB AB-7 -' "$bd_cl" \
     && [ "$bd_out" = 'board comment: AB-7 comment 10042 posted and read back' ]; then
    bd_pass "leg comment/stdin: the composed body reaches the adapter on stdin byte-for-byte, carries only the record's first line, is absent from its argv, and success names the comment id"
  else bd_fail_ "leg comment/stdin: rc=$bd_rc log=[$(cat "$bd_cl")] out=[$bd_out]"; fi
  # the adapter's failure is rc 1 (the write or its proof); its own refusal (rc 1) reaches the caller as rc 2; no id is not a success
  bd_cmt_rc() { # <stub rc>
    : > "$bd_cl"
    bd_out=$(cd "$bd_cclone" && STUB_LOG="$bd_cl" STUB_COMMENT_RC="$1" do_comment AB-7 --from-record docs/reviews/x.md 2>&1); bd_rc=$?
  }
  bd_cmt_rc 2; bd_rc1=$bd_rc; bd_o1=$bd_out
  bd_cmt_rc 1; bd_rc2=$bd_rc
  bd_out=$(cd "$bd_cclone" && STUB_COMMENT_ID=x1 do_comment AB-7 --from-record docs/reviews/x.md 2>&1); bd_rc3=$?
  if [ "$bd_rc1" -eq 1 ] && printf '%s' "$bd_o1" | grep -qF 'was not posted and proved' && ! printf '%s' "$bd_o1" | grep -qF 'TOPSECRET' \
     && [ "$bd_rc2" -eq 2 ] && [ "$bd_rc3" -eq 1 ]; then
    bd_pass "leg comment/rc: an adapter failure is rc 1, an adapter refusal is rc 2, and a non-numeric id is rc 1 (never a success)"
  else bd_fail_ "leg comment/rc: rc=$bd_rc1/$bd_rc2/$bd_rc3 o1=[$bd_o1]"; fi

  # ── show / edit legs (BOARD-EDIT-SHOW-VERB, design 2026-10-09 §4): the stub adapter records every call; each edit form alone
  # asserts the exact fragment, ONE PUT, and the post-read; every refusal asserts ZERO PUTs (and, before any request, an EMPTY log). ──
  bd_em="$bd_base/.em"; bd_em_cur="$bd_em"; bd_em_rc_cur=0; bd_ed_rc_cur=0; bd_show="$bd_base/.show"; bd_show_rc=0
  printf 'edit\tsummary\tstring\tSummary\t\nedit\tdescription\tstring\tDescription\t\nedit\tlabels\tarray\tLabels\t\nedit\tparent\tissuelink\tParent\t\nedit\tcustomfield_10046\toption\tSize\tXS|S|M|L|XL\nedit\tcustomfield_10047\toption\tRisk\tLow|Medium|High\n' > "$bd_em"
  printf 'edit\tsummary\tstring\tSummary\t\nedit\tdescription\tstring\tDescription\t\nedit\tlabels\tarray\tLabels\t\nedit\tparent\tissuelink\tParent\t\n' > "$bd_em.nosize"
  bd_conf customfield_10046 customfield_10047 cloud
  bd_x_run() { # <args…>: one edit, in-process, stderr folded in; the stub log and fragment capture are reset first
    : > "$bd_cr_log"; rm -f "$bd_cr_body"
    bd_out=$(cd "$bd_cc" && STUB_LOG="$bd_cr_log" STUB_BODY_FILE="$bd_cr_body" STUB_EM="$bd_em_cur" STUB_EM_RC="$bd_em_rc_cur" STUB_EDIT_RC="$bd_ed_rc_cur" STUB_GF="$bd_cr_gf" do_edit "$@" 2>&1); bd_rc=$?
  }
  bd_x_n() { grep -c "^$1 " "$bd_cr_log" 2>/dev/null || true; }
  bd_x_one() { # <label> <want-fragment> <gf> <expected size/risk ids> <args…>: succeeds with exactly the fragment, ONE PUT, the post-read
    _x_label=$1; _x_want=$2; _x_gf=$3; _x_ids=$4; shift 4
    printf '%b' "$_x_gf" > "$bd_cr_gf"
    bd_x_run "$@"
    if [ "$bd_rc" -eq 0 ] && [ "$(cat "$bd_cr_body" 2>/dev/null)" = "$_x_want" ] && [ "$(bd_x_n edit)" = 1 ] && [ "$(bd_x_n edit-meta)" = 1 ] && [ "$(bd_x_n get-fields)" = 1 ] \
       && grep -qxF "edit https://ex.atlassian.net cloud AB AB-7 $_x_ids -" "$bd_cr_log" && printf '%s' "$bd_out" | grep -qF 'proven by post-read'; then
      bd_pass "leg jira/edit-$_x_label: the exact fragment, one PUT, proven by the post-read"
    else bd_fail_ "leg jira/edit-$_x_label: rc=$bd_rc puts=$(bd_x_n edit) body=[$(cat "$bd_cr_body" 2>/dev/null)] want=[$_x_want] out=[$bd_out]"; fi
  }
  bd_x_mis() { # <label> <gf> <needle> <args…>: the PUT happened, the post-read disagrees -> rc 1 naming the field, never ok
    _x_label=$1; _x_gf=$2; _x_needle=$3; shift 3
    printf '%b' "$_x_gf" > "$bd_cr_gf"
    bd_x_run "$@"
    if [ "$bd_rc" -eq 1 ] && [ "$(bd_x_n edit)" = 1 ] && printf '%s' "$bd_out" | grep -qF 'did NOT prove' && printf '%s' "$bd_out" | grep -qF -e "$_x_needle" && ! printf '%s' "$bd_out" | grep -qF 'OK'; then
      bd_pass "leg jira/edit-mismatch-$_x_label: a post-read that disagrees is rc 1 naming the field"
    else bd_fail_ "leg jira/edit-mismatch-$_x_label: rc=$bd_rc out=[$bd_out]"; fi
  }
  bd_x_off() { # <label> <rc> <needle> <args…>: refused BEFORE any request - the stub log is EMPTY, no content echoed
    _x_label=$1; _x_rc=$2; _x_needle=$3; shift 3
    bd_x_run "$@"
    if [ "$bd_rc" -eq "$_x_rc" ] && [ ! -s "$bd_cr_log" ] && printf '%s' "$bd_out" | grep -qF -e "$_x_needle" && ! printf '%s' "$bd_out" | grep -qF TOPSECRET; then
      bd_pass "leg jira/edit-refuse-$_x_label: refused rc $_x_rc with zero requests and no content echoed"
    else bd_fail_ "leg jira/edit-refuse-$_x_label: rc=$bd_rc log=[$(cat "$bd_cr_log")] out=[$bd_out]"; fi
  }
  bd_l1='a < b | c; d $HOME '"'"'q'"'"' scripts/board.sh'
  bd_df="$bd_base/d.txt"; printf '%s\nsecond\n' "$bd_l1" > "$bd_df"
  bd_adf='{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"'"$bd_l1"'"}]},{"type":"paragraph","content":[{"type":"text","text":"second"}]}]}'
  bd_dn=$(printf '%s\nsecond' "$bd_l1" | wc -c | tr -d ' ')

  # each form alone
  bd_x_one title '{"fields":{"summary":"New title"}}' 'summary\tNew title\n' '- - -' AB-7 --title "New title"
  bd_x_one description "{\"fields\":{\"description\":$bd_adf}}" "description\\tpresent $bd_dn\\n" '- - -' AB-7 --description-file "$bd_df"
  bd_x_one size '{"fields":{"customfield_10046":{"value":"S"}}}' 'customfield_10046\tS\n' 'customfield_10046 - -' AB-7 --size s
  bd_x_one risk '{"fields":{"customfield_10047":{"value":"Medium"}}}' 'customfield_10047\tMedium\n' '- customfield_10047 -' AB-7 --risk medium
  bd_x_one label-add '{"update":{"labels":[{"add":"parked"}]}}' 'labels\tkeep parked\n' '- - -' AB-7 --label-add parked
  bd_x_one label-remove '{"update":{"labels":[{"remove":"old"}]}}' 'labels\tkeep\n' '- - -' AB-7 --label-remove old
  bd_x_one parent '{"fields":{"parent":{"key":"AB-5"}}}' 'parent\tAB-5\n' '- - -' AB-7 --parent AB-5
  bd_x_one combined '{"fields":{"summary":"T","customfield_10046":{"value":"L"}},"update":{"labels":[{"add":"a"},{"remove":"b"}]}}' 'summary\tT\ncustomfield_10046\tL\nlabels\ta keep\n' 'customfield_10046 - -' AB-7 --title T --size l --label-add a --label-remove b

  # a mismatch leg per proof kind
  bd_x_mis summary 'summary\tOther\n' 'summary' AB-7 --title X
  bd_x_mis select 'customfield_10046\tM\n' 'customfield_10046' AB-7 --size S
  bd_x_mis parent 'parent\tAB-6\n' 'parent' AB-7 --parent AB-5
  bd_x_mis label-added 'labels\tkeep\n' "the label 'parked' was added" AB-7 --label-add parked
  bd_x_mis label-removed 'labels\told\n' "the label 'old' was removed" AB-7 --label-remove old
  bd_x_mis description 'description\tpresent 3\n' 'description' AB-7 --description-file "$bd_df"

  # refused before any request
  bd_x_off key-other-project 1 'not a card key' XY-7 --title x
  bd_x_off key-leading-zero 1 'not a card key' AB-07 --title x
  bd_x_off key-bad-grammar 2 'invalid row id' 'AB-7;x' --title x
  bd_x_off label-both 2 "in both --label-add and --label-remove" AB-7 --label-add a --label-remove a
  bd_x_off parent-other-project 1 'never re-parented under another project' AB-7 --parent XY-5
  bd_x_off nothing 2 'nothing to change' AB-7
  bd_x_off label-grammar 2 'must match' AB-7 --label-add 'a b'
  bd_x_off size-grammar 2 'must match' AB-7 --size 'S;x'
  bd_x_off title-grammar 2 'printable ASCII' AB-7 --title 'caf'"$(printf '\303\251')"
  bd_x_off title-space 2 'start or end with a space' AB-7 --title ' x'
  bd_x_off no-inline-description 2 'unknown option' AB-7 --description x
  # a select value outside the card's allowed set: refused after the editmeta read, before the PUT
  printf 'issuetype\tTask\n' > "$bd_cr_gf"
  bd_x_run AB-7 --size XXL
  if [ "$bd_rc" -eq 2 ] && [ "$(bd_x_n edit)" = 0 ] && [ "$(bd_x_n edit-meta)" = 1 ] && printf '%s' "$bd_out" | grep -qF 'XS, S, M, L, XL'; then
    bd_pass "leg jira/edit-refuse-bad-value: a Size outside the editmeta's allowed set is refused with the set listed and zero PUTs"
  else bd_fail_ "leg jira/edit-refuse-bad-value: rc=$bd_rc out=[$bd_out]"; fi
  # editmeta lacking the field -> refused before the PUT, the field named; an unreadable editmeta -> unverified (rc 1), zero PUTs
  bd_em_cur="$bd_em.nosize"; bd_x_run AB-7 --size S; bd_em_cur="$bd_em"
  bd_rc1=$bd_rc; bd_e1=$(bd_x_n edit); bd_o1=$bd_out
  bd_em_rc_cur=2; bd_x_run AB-7 --title x; bd_em_rc_cur=0
  if [ "$bd_rc1" -eq 2 ] && [ "$bd_e1" = 0 ] && printf '%s' "$bd_o1" | grep -qF 'customfield_10046' && printf '%s' "$bd_o1" | grep -qF 'is not editable' \
     && [ "$bd_rc" -eq 1 ] && [ "$(bd_x_n edit)" = 0 ] && printf '%s' "$bd_out" | grep -qF 'unverified: stub editmeta failure'; then
    bd_pass "leg jira/edit-refuse-editmeta: a field absent from the card's editmeta is refused naming it, and an unreadable editmeta is unverified - zero PUTs each"
  else bd_fail_ "leg jira/edit-refuse-editmeta: rc=$bd_rc1/$bd_rc o1=[$bd_o1] out=[$bd_out]"; fi
  # the PUT fails with anything but a refusal (adapter rc 2: a timeout, a 5xx) -> rc 3 "may have applied", never a post-read, never ok
  bd_ed_rc_cur=2; bd_x_run AB-7 --title x; bd_ed_rc_cur=0
  if [ "$bd_rc" -eq 3 ] && [ "$(bd_x_n get-fields)" = 0 ] && printf '%s' "$bd_out" | grep -qF 'unverified - the edit may have applied; check with board show AB-7' && ! printf '%s' "$bd_out" | grep -qF 'OK'; then
    bd_pass "leg jira/edit-unverified-put: an adapter failure other than a refusal is rc 3 saying the edit may have applied"
  else bd_fail_ "leg jira/edit-unverified-put: rc=$bd_rc out=[$bd_out]"; fi
  # the tracker refuses the PUT -> rc 1, no OK, no post-read
  bd_ed_rc_cur=1; bd_x_run AB-7 --title x; bd_ed_rc_cur=0
  if [ "$bd_rc" -eq 1 ] && [ "$(bd_x_n get-fields)" = 0 ] && ! printf '%s' "$bd_out" | grep -qF 'OK'; then
    bd_pass "leg jira/edit-refuse-put: a PUT the adapter refuses is rc 1 and is never read back as ok"
  else bd_fail_ "leg jira/edit-refuse-put: rc=$bd_rc out=[$bd_out]"; fi
  # md backend: rc 2 before any request
  : > "$bd_cr_log"
  bd_out=$(cd "$bd_base/md-clone" && STUB_LOG="$bd_cr_log" do_edit AB-7 --title x 2>&1); bd_rc=$?
  bd_out2=$(cd "$bd_base/md-clone" && STUB_LOG="$bd_cr_log" do_show AB-7 2>&1); bd_rc2=$?
  if [ "$bd_rc" -eq 2 ] && [ "$bd_rc2" -eq 2 ] && [ ! -s "$bd_cr_log" ] && printf '%s' "$bd_out" | grep -qF 'needs a tracker backend'; then
    bd_pass "leg jira/edit-md: on an md backend edit and show refuse rc 2 with zero requests"
  else bd_fail_ "leg jira/edit-md: rc=$bd_rc/$bd_rc2 out=[$bd_out] out2=[$bd_out2]"; fi

  # dry run: every flag validated, the plan printed, ZERO requests, and no credential needed
  bd_out=$( (unset KIT_TRACKER_USER KIT_TRACKER_TOKEN KIT_TRACKER_AUTH JIRA_EMAIL JIRA_TOKEN; : > "$bd_cr_log"; cd "$bd_cc" && STUB_LOG="$bd_cr_log" do_edit AB-7 --title T --size S --description-file "$bd_df" --label-add x --label-remove y --parent AB-5 --dry-run 2>&1) ); bd_rc=$?
  if [ "$bd_rc" -eq 0 ] && [ ! -s "$bd_cr_log" ] && printf '%s' "$bd_out" | grep -qF 'DRY RUN' && printf '%s' "$bd_out" | grep -qF "summary: \"T\"" \
     && printf '%s' "$bd_out" | grep -qF "$bd_dn bytes, 2 lines" && printf '%s' "$bd_out" | grep -qF 'labels added: x' && printf '%s' "$bd_out" | grep -qF 'labels removed: y'; then
    bd_pass "leg jira/edit-dry-run: --dry-run with no credentials prints the change set (text as bytes and lines) and makes no request"
  else bd_fail_ "leg jira/edit-dry-run: rc=$bd_rc log=[$(cat "$bd_cr_log")] out=[$bd_out]"; fi
  bd_out=$( (unset KIT_TRACKER_USER KIT_TRACKER_TOKEN; : > "$bd_cr_log"; cd "$bd_cc" && STUB_LOG="$bd_cr_log" do_edit AB-7 --title T --label-add x --label-remove x --dry-run 2>&1) ); bd_rc=$?
  if [ "$bd_rc" -eq 2 ] && [ ! -s "$bd_cr_log" ]; then bd_pass "leg jira/edit-dry-run-validates: a dry run still refuses an invalid flag set (rc 2, zero requests)"
  else bd_fail_ "leg jira/edit-dry-run-validates: rc=$bd_rc out=[$bd_out]"; fi

  # --description-file refusals: each rc 2, ZERO requests, and no byte of the file echoed (every file carries TOPSECRET)
  mkdir -p "$bd_cc/.hid" "$bd_base/nul"
  printf 'TOPSECRET\n' > "$bd_cc/.hid/d.txt"
  ln -s "$bd_df" "$bd_base/lnk.txt"
  printf 'TOPSECRET\000x\n' > "$bd_base/nul.txt"
  { printf 'TOPSECRET'; awk 'BEGIN { for (i = 0; i < 31992; i++) printf "a" }'; } > "$bd_base/big32001.txt"
  { printf 'TOPSECRET\n-----BEGIN RSA PRIVATE'; printf ' KEY-----\n'; } > "$bd_base/pem.txt"
  { printf 'TOPSECRET gh'; printf 'p_'; awk 'BEGIN { for (i = 0; i < 36; i++) printf "a" }'; printf '\n'; } > "$bd_base/tok.txt"
  printf 'TOPSECRET \377\376\n' > "$bd_base/utf8.txt"
  printf '\n\n' > "$bd_base/blank.txt"
  bd_x_off file-symlink 2 'symlink' AB-7 --description-file "$bd_base/lnk.txt"
  bd_x_off file-dot-path 2 'must sit under' AB-7 --description-file "$bd_cc/.hid/d.txt"
  bd_x_off file-outside 2 'must sit under' AB-7 --description-file /etc/hosts
  bd_x_off file-nul 2 'NUL' AB-7 --description-file "$bd_base/nul.txt"
  bd_x_off file-over-32000 2 '1..32000 bytes' AB-7 --description-file "$bd_base/big32001.txt"
  bd_x_off file-private-key 2 'private-key header' AB-7 --description-file "$bd_base/pem.txt"
  bd_x_off file-token 2 'token shape' AB-7 --description-file "$bd_base/tok.txt"
  bd_x_off file-utf8 2 'valid UTF-8' AB-7 --description-file "$bd_base/utf8.txt"
  bd_x_off file-blank 2 'no content' AB-7 --description-file "$bd_base/blank.txt"
  bd_x_off file-missing 2 'regular file' AB-7 --description-file "$bd_base/none.txt"
  # a file named `foo<LF>` beside a symlink `foo`: the newline path is refused as a path, the symlink as a symlink - zero requests each
  mkdir -p "$bd_base/nl"
  bd_nlname=$(printf 'foo\nX'); bd_nlname=${bd_nlname%X}
  printf 'TOPSECRET real\n' > "$bd_base/nl/$bd_nlname"
  ln -s "$bd_df" "$bd_base/nl/foo"
  bd_x_off file-newline-path 2 'printable ASCII' AB-7 --description-file "$bd_base/nl/$bd_nlname"
  bd_x_off file-newline-beside-symlink 2 'symlink' AB-7 --description-file "$bd_base/nl/foo"

  # create --description-file: the same file round-trips byte-exact (< | ; $ ' and a control-plane name) into the create fragment;
  # --description with --description-file is refused; a refused file means zero POSTs
  bd_conf - - cloud
  printf 'issuetype\tTask\n' > "$bd_cr_gf"
  bd_cr --title x --description-file "$bd_df"
  if [ "$bd_rc" -eq 0 ] && [ "$(cat "$bd_cr_body")" = "{\"description\":$bd_adf}" ] && [ "$(bd_posts)" = 1 ]; then
    bd_pass "leg jira/create-description-file: a file holding < | ; \$ ' and a control-plane file name reaches the create fragment byte-exact, one POST"
  else bd_fail_ "leg jira/create-description-file: rc=$bd_rc posts=$(bd_posts) body=[$(cat "$bd_cr_body" 2>/dev/null)] out=[$bd_out]"; fi
  bd_cr --title x --description inline --description-file "$bd_df"
  bd_rc1=$bd_rc; bd_p1=$(bd_posts)
  bd_cr --title x --description-file "$bd_base/pem.txt"
  bd_rc2=$bd_rc; bd_p2=$(bd_posts)
  if [ "$bd_rc1" -eq 2 ] && [ "$bd_p1" = 0 ] && [ "$bd_rc2" -eq 2 ] && [ "$bd_p2" = 0 ] && ! printf '%s' "$bd_out" | grep -qF TOPSECRET; then
    bd_pass "leg jira/create-description-file-refuse: --description with --description-file, and a file holding a private-key header, each refuse rc 2 with zero POSTs"
  else bd_fail_ "leg jira/create-description-file-refuse: rc=$bd_rc1/$bd_rc2 posts=$bd_p1/$bd_p2 out=[$bd_out]"; fi

  # one line count for both verbs: 2001 lines is over the bound for an edit file and for a create --description, 2000 is not
  awk 'BEGIN { for (i = 0; i < 2001; i++) print "a" }' > "$bd_base/l2001.txt"
  awk 'BEGIN { for (i = 0; i < 2000; i++) print "a" }' > "$bd_base/l2000.txt"
  bd_lines_2001=$(cat "$bd_base/l2001.txt")
  bd_x_off file-2001-lines 2 '2000-line' AB-7 --description-file "$bd_base/l2001.txt"
  bd_cr --title x --description "$bd_lines_2001"
  bd_rc1=$bd_rc; bd_p1=$(bd_posts); bd_o1=$bd_out
  bd_cr --title x --description-file "$bd_base/l2000.txt"
  if [ "$bd_rc1" -eq 2 ] && [ "$bd_p1" = 0 ] && printf '%s' "$bd_o1" | grep -qF '2000-line' && [ "$bd_rc" -eq 0 ] && [ "$(bd_posts)" = 1 ]; then
    bd_pass "leg jira/lines-shared: 2001 lines is refused by create --description and by an edit file alike; 2000 lines is accepted"
  else bd_fail_ "leg jira/lines-shared: rc=$bd_rc1/$bd_rc posts=$bd_p1/$(bd_posts) o1=[$bd_o1]"; fi

  # ── title / metric file forms (BOARD-TEXT-FILE-FORMS, design 2026-10-10 §4): one loader, three kinds. Fixtures are ASCII; every
  # hostile byte is an octal escape. Each refusal asserts ZERO requests and no file content echoed (TOPSECRET rides each file). ──
  bd_tl="a < b | c; d \$HOME 'q' scripts/board.sh"
  printf '%s\n' "$bd_tl" > "$bd_base/t1.txt"
  printf 'line one\nTOPSECRET line two\n' > "$bd_base/t2.txt"
  printf 'TOPSECRET caf\303\251\n' > "$bd_base/tna.txt"
  printf ' TOPSECRET lead\n' > "$bd_base/tsp.txt"
  printf 'TOPSECRET %0300d\n' 0 > "$bd_base/t256.txt"
  printf 'TOPSECRET\r\n' > "$bd_base/tcr.txt"
  bd_mdf="$bd_base/m.txt"; printf '%s\nsecond metric line\n' "$bd_l1" > "$bd_mdf"
  bd_madf='{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"'"$bd_l1"'"}]},{"type":"paragraph","content":[{"type":"text","text":"second metric line"}]}]}'
  bd_mn=$(printf '%s\nsecond metric line' "$bd_l1" | wc -c | tr -d ' ')
  printf 'edit\tsummary\tstring\tSummary\t\nedit\tcustomfield_10077\tstring\tSuccess metric\t\n' > "$bd_em.metric"

  # create --title-file / --metric-file: byte-exact into the fragment, ONE POST
  bd_cx='field.metric=customfield_10077'; bd_conf - - cloud
  printf 'issuetype\tTask\ncustomfield_10077\tpresent\n' > "$bd_cr_gf"
  bd_cm_cur="$bd_cmdir/metric"; bd_cr --title-file "$bd_base/t1.txt"; bd_cm_cur="$bd_cmdir"
  bd_t1=$(cat "$bd_cr_log" 2>/dev/null)
  if [ "$bd_rc" -eq 0 ] && [ "$(bd_posts)" = 1 ] && grep -qF "create https://ex.atlassian.net cloud AB $bd_tl " "$bd_cr_log"; then
    bd_pass "leg jira/create-title-file: a title file holding < | ; \$ ' and a control-plane file name reaches the create call byte-exact, one POST"
  else bd_fail_ "leg jira/create-title-file: rc=$bd_rc posts=$(bd_posts) log=[$bd_t1] out=[$bd_out]"; fi
  bd_cm_cur="$bd_cmdir/metric"; bd_cr --title x --metric-file "$bd_mdf"; bd_cm_cur="$bd_cmdir"
  if [ "$bd_rc" -eq 0 ] && [ "$(bd_posts)" = 1 ] && [ "$(cat "$bd_cr_body" 2>/dev/null)" = "{\"customfield_10077\":$bd_madf}" ]; then
    bd_pass "leg jira/create-metric-file: a metric file holding < | ; \$ ' and a control-plane file name reaches field.metric byte-exact (ADF on Cloud), one POST, proven present"
  else bd_fail_ "leg jira/create-metric-file: rc=$bd_rc posts=$(bd_posts) body=[$(cat "$bd_cr_body" 2>/dev/null)] out=[$bd_out]"; fi
  # exclusivity and the loader's refusals on create: zero POSTs, no file content echoed
  bd_cb2=0
  bd_cm_cur="$bd_cmdir/metric"
  bd_cr --title x --title-file "$bd_base/t1.txt";            { [ "$bd_rc" -eq 2 ] && [ "$(bd_posts)" = 0 ] && printf '%s' "$bd_out" | grep -qF 'mutually exclusive'; } || bd_cb2=1
  bd_cr --title x --metric m --metric-file "$bd_mdf";        { [ "$bd_rc" -eq 2 ] && [ "$(bd_posts)" = 0 ] && printf '%s' "$bd_out" | grep -qF 'mutually exclusive'; } || bd_cb2=1
  bd_cr --title-file "$bd_base/t2.txt";                      { [ "$bd_rc" -eq 2 ] && [ "$(bd_posts)" = 0 ] && printf '%s' "$bd_out" | grep -qF 'exactly one line'; } || bd_cb2=1
  bd_cr --title-file "$bd_base/tna.txt";                     { [ "$bd_rc" -eq 2 ] && [ "$(bd_posts)" = 0 ] && printf '%s' "$bd_out" | grep -qF 'printable ASCII'; } || bd_cb2=1
  bd_cr --title-file "$bd_base/blank.txt";                   { [ "$bd_rc" -eq 2 ] && [ "$(bd_posts)" = 0 ] && printf '%s' "$bd_out" | grep -qF 'no content'; } || bd_cb2=1
  bd_cr --title x --metric-file "$bd_base/pem.txt";          { [ "$bd_rc" -eq 2 ] && [ "$(bd_posts)" = 0 ] && printf '%s' "$bd_out" | grep -qF 'private-key header'; } || bd_cb2=1
  bd_cr --title x --metric-file "$bd_base/lnk.txt";          { [ "$bd_rc" -eq 2 ] && [ "$(bd_posts)" = 0 ] && printf '%s' "$bd_out" | grep -qF 'symlink'; } || bd_cb2=1
  bd_cr --title-file "$bd_cc/.hid/d.txt";                    { [ "$bd_rc" -eq 2 ] && [ "$(bd_posts)" = 0 ] && printf '%s' "$bd_out" | grep -qF 'must sit under'; } || bd_cb2=1
  bd_cr --title x --metric-file /etc/hosts;                  { [ "$bd_rc" -eq 2 ] && [ "$(bd_posts)" = 0 ] && printf '%s' "$bd_out" | grep -qF 'must sit under'; } || bd_cb2=1
  bd_cm_cur="$bd_cmdir"
  if [ "$bd_cb2" -eq 0 ] && ! printf '%s' "$bd_out" | grep -qF TOPSECRET; then
    bd_pass "leg jira/create-text-file-refuse: --title with --title-file, --metric with --metric-file, a two-line / non-ASCII / blank title file, a key-bearing, symlinked, dot-path or outside-the-roots file each refuse rc 2 with zero POSTs"
  else bd_fail_ "leg jira/create-text-file-refuse: bad=$bd_cb2 out=[$bd_out]"; fi
  bd_cx=""

  # edit --title-file: the exact fragment, one PUT, proven; a mismatch leg; the title grammar and the single-line rule
  bd_conf customfield_10046 customfield_10047 cloud
  bd_x_one title-file '{"fields":{"summary":"'"$bd_tl"'"}}' "summary\\t$bd_tl\\n" '- - -' AB-7 --title-file "$bd_base/t1.txt"
  bd_x_mis title-file "summary\\tOther\\n" 'summary' AB-7 --title-file "$bd_base/t1.txt"
  bd_x_off title-file-two-lines 2 'exactly one line' AB-7 --title-file "$bd_base/t2.txt"
  bd_x_off title-file-grammar 2 'printable ASCII' AB-7 --title-file "$bd_base/tna.txt"
  bd_x_off title-file-cr 2 'printable ASCII' AB-7 --title-file "$bd_base/tcr.txt"
  bd_x_off title-file-space 2 'start or end with a space' AB-7 --title-file "$bd_base/tsp.txt"
  bd_x_off title-file-256 2 '1..255' AB-7 --title-file "$bd_base/t256.txt"
  bd_x_off title-file-blank 2 'no content' AB-7 --title-file "$bd_base/blank.txt"
  bd_x_off title-and-file 2 'mutually exclusive' AB-7 --title x --title-file "$bd_base/t1.txt"
  bd_x_off title-file-symlink 2 'symlink' AB-7 --title-file "$bd_base/lnk.txt"
  bd_x_off title-file-dot-path 2 'must sit under' AB-7 --title-file "$bd_cc/.hid/d.txt"
  bd_x_off title-file-outside 2 'must sit under' AB-7 --title-file /etc/hosts

  # edit --metric-file: the exact fragment on the metric id, one PUT, the metric id on the adapter's argv slot, proven `present <bytes>`
  bd_cx='field.metric=customfield_10077'; bd_conf customfield_10046 customfield_10047 cloud; bd_em_cur="$bd_em.metric"
  bd_x_one metric-file "{\"fields\":{\"customfield_10077\":$bd_madf}}" "customfield_10077:text\\tpresent $bd_mn\\n" '- - customfield_10077' AB-7 --metric-file "$bd_mdf"
  bd_x_mis metric-file 'customfield_10077:text\tpresent 3\n' 'customfield_10077:text' AB-7 --metric-file "$bd_mdf"
  bd_x_mis metric-file-empty 'customfield_10077:text\tempty\n' 'customfield_10077:text' AB-7 --metric-file "$bd_mdf"
  bd_x_off metric-file-symlink 2 'symlink' AB-7 --metric-file "$bd_base/lnk.txt"
  bd_x_off metric-file-dot-path 2 'must sit under' AB-7 --metric-file "$bd_cc/.hid/d.txt"
  bd_x_off metric-file-outside 2 'must sit under' AB-7 --metric-file /etc/hosts
  bd_x_off metric-file-blank 2 'no content' AB-7 --metric-file "$bd_base/blank.txt"
  bd_x_off metric-file-secret 2 'private-key header' AB-7 --metric-file "$bd_base/pem.txt"
  bd_x_off metric-file-2001-lines 2 '2000-line' AB-7 --metric-file "$bd_base/l2001.txt"
  bd_x_off no-inline-metric 2 'unknown option' AB-7 --metric x
  # a metric that is unmapped (none, or absent) is refused before any request, naming the conf line
  bd_cx='field.metric=none'; bd_conf customfield_10046 customfield_10047 cloud
  bd_x_off metric-file-unmapped-none 2 'field.metric=customfield_N' AB-7 --metric-file "$bd_mdf"
  bd_cx=""; bd_conf customfield_10046 customfield_10047 cloud
  bd_x_off metric-file-unmapped-absent 2 'field.metric=customfield_N' AB-7 --metric-file "$bd_mdf"
  # the metric field absent from the card's editmeta: refused after the editmeta read, before the PUT, the field named
  bd_cx='field.metric=customfield_10077'; bd_conf customfield_10046 customfield_10047 cloud
  bd_em_cur="$bd_em"; bd_x_run AB-7 --metric-file "$bd_mdf"
  if [ "$bd_rc" -eq 2 ] && [ "$(bd_x_n edit)" = 0 ] && [ "$(bd_x_n edit-meta)" = 1 ] && printf '%s' "$bd_out" | grep -qF 'customfield_10077' && printf '%s' "$bd_out" | grep -qF 'is not editable'; then
    bd_pass "leg jira/edit-refuse-metric-editmeta: a metric field absent from the card's editmeta is refused naming it, zero PUTs"
  else bd_fail_ "leg jira/edit-refuse-metric-editmeta: rc=$bd_rc out=[$bd_out]"; fi
  # a dry run of --metric-file (and --title-file) sends nothing and needs no credential; it lists the metric as bytes and lines
  bd_em_cur="$bd_em.metric"
  bd_out=$( (unset KIT_TRACKER_USER KIT_TRACKER_TOKEN KIT_TRACKER_AUTH JIRA_EMAIL JIRA_TOKEN; : > "$bd_cr_log"; cd "$bd_cc" && STUB_LOG="$bd_cr_log" do_edit AB-7 --metric-file "$bd_mdf" --title-file "$bd_base/t1.txt" --dry-run 2>&1) ); bd_rc=$?
  if [ "$bd_rc" -eq 0 ] && [ ! -s "$bd_cr_log" ] && printf '%s' "$bd_out" | grep -qF 'DRY RUN' && printf '%s' "$bd_out" | grep -qF "metric: replaced whole, $bd_mn bytes, 2 lines" \
     && printf '%s' "$bd_out" | grep -qF "summary: \"$bd_tl\""; then
    bd_pass "leg jira/edit-metric-dry-run: --dry-run of --metric-file sends nothing, needs no credential and lists the metric as bytes and lines"
  else bd_fail_ "leg jira/edit-metric-dry-run: rc=$bd_rc log=[$(cat "$bd_cr_log")] out=[$bd_out]"; fi
  # an over-long metric id (over the adapter's 22-character bound) is refused at board level, dry run included, zero requests
  bd_cx='field.metric=customfield_12345678901'; bd_conf customfield_10046 customfield_10047 cloud
  bd_x_off metric-file-id-too-long 2 'field.metric=customfield_N' AB-7 --metric-file "$bd_mdf"
  bd_x_off metric-file-id-too-long-dry 2 'field.metric=customfield_N' AB-7 --metric-file "$bd_mdf" --dry-run
  bd_cx=""; bd_em_cur="$bd_em"; bd_conf customfield_10046 customfield_10047 cloud

  # show: ONE adapter call (read-only), the card text passed through, the field mappings and the comment count handed on
  bd_conf customfield_10046 customfield_10047 cloud
  printf 'key: AB-7\nsummary: s\n' > "$bd_show"
  bd_x_show() { # <args…>: one show, in-process
    : > "$bd_cr_log"
    bd_out=$(cd "$bd_cc" && STUB_LOG="$bd_cr_log" STUB_SHOW="$bd_show" STUB_SHOW_RC="$bd_show_rc" do_show "$@" 2>&1); bd_rc=$?
  }
  bd_x_show AB-7
  if [ "$bd_rc" -eq 0 ] && [ "$bd_out" = "$(cat "$bd_show")" ] && [ "$(wc -l < "$bd_cr_log" | tr -d ' ')" = 1 ] \
     && grep -qxF 'show https://ex.atlassian.net cloud AB AB-7 customfield_10046 customfield_10047 3' "$bd_cr_log"; then
    bd_pass "leg jira/show: one read-only adapter call with the conf's Size/Risk fields and the default 3 comments; the card text is passed through"
  else bd_fail_ "leg jira/show: rc=$bd_rc log=[$(cat "$bd_cr_log")] out=[$bd_out]"; fi
  bd_conf label:size label:risk cloud
  bd_x_show AB-7 --comments 5
  if [ "$bd_rc" -eq 0 ] && grep -qxF 'show https://ex.atlassian.net cloud AB AB-7 label:size label:risk 5' "$bd_cr_log"; then
    bd_pass "leg jira/show-args: --comments 5 and label-mapped Size/Risk reach the adapter"
  else bd_fail_ "leg jira/show-args: rc=$bd_rc log=[$(cat "$bd_cr_log")]"; fi
  bd_conf customfield_10046 customfield_10047 cloud
  bd_show_bad=0
  bd_x_show AB-7 --comments 11; { [ "$bd_rc" -eq 2 ] && [ ! -s "$bd_cr_log" ]; } || bd_show_bad=1
  bd_x_show XY-7; { [ "$bd_rc" -eq 1 ] && [ ! -s "$bd_cr_log" ]; } || bd_show_bad=1
  bd_x_show 'AB-7;x'; { [ "$bd_rc" -eq 1 ] && [ ! -s "$bd_cr_log" ]; } || bd_show_bad=1
  bd_x_show; { [ "$bd_rc" -eq 2 ] && [ ! -s "$bd_cr_log" ]; } || bd_show_bad=1
  bd_show_rc=2; bd_x_show AB-7; { [ "$bd_rc" -eq 3 ] || bd_show_bad=1; }
  # the adapter's rc 1 (a card that MOVED to another project, a foreign key) stays a refusal, rc 1
  bd_show_rc=1; bd_x_show AB-7; { [ "$bd_rc" -eq 1 ] || bd_show_bad=1; }
  bd_show_rc=0
  if [ "$bd_show_bad" -eq 0 ]; then
    bd_pass "leg jira/show-refuse: --comments 11 and no key are rc 2, a key of another project or off the grammar is rc 1, all before any request; an adapter refusal (a moved card) is rc 1; an adapter failure is rc 3"
  else bd_fail_ "leg jira/show-refuse: bad=$bd_show_bad"; fi

  # ── rank / list legs (BOARD-RANK-VERB): the stub serves STUB_RANKED_PRE until a rank is written, then STUB_RANKED_POST ──
  bd_rkl="$bd_base/.rklog"; bd_rkd="$bd_base/.rkdone"; bd_rktab=$(printf '\t')
  bd_rk_list() { # <file> <key>...: one open card per line, status To Do
    _rl_f=$1; shift; : > "$_rl_f"
    for _rl_k in "$@"; do printf '%s\tTo Do\n' "$_rl_k" >> "$_rl_f"; done
  }
  bd_rk_list "$bd_base/.rk-pre" AB-9 AB-2 AB-5 AB-7
  bd_rk_list "$bd_base/.rk-post-top" AB-7 AB-9 AB-2 AB-5
  bd_rk_list "$bd_base/.rk-post-before" AB-9 AB-7 AB-2 AB-5
  bd_rk_list "$bd_base/.rk-post-after" AB-9 AB-2 AB-7 AB-5
  bd_rk() { # <dir> <post-file> <args…>: one rank, in-process, adapter log reset, no stale write marker
    _rk_cd=$1; _rk_postf=$2; shift 2
    : > "$bd_rkl"; rm -f "$bd_rkd"
    bd_out=$(cd "$_rk_cd" && STUB_LOG="$bd_rkl" STUB_RANK_DONE="$bd_rkd" STUB_RANKED_PRE="$bd_base/.rk-pre" STUB_RANKED_POST="$_rk_postf" do_rank "$@" 2>&1); bd_rc=$?
  }
  bd_rk_wrote() { grep -q '^rank ' "$bd_rkl"; }   # did the verb reach the adapter's write?
  # leg rank/top|before|after: each writes once with the right adapter argv and reports OK with the proven position
  bd_rk "$bd_jclone" "$bd_base/.rk-post-top" AB-7 --top
  if [ "$bd_rc" -eq 0 ] && grep -qxF 'rank https://ex.atlassian.net cloud AB AB-7 before AB-9' "$bd_rkl" \
     && [ "$bd_out" = 'board rank: OK - AB-7 now before AB-9 (position 1 of 4 open cards), proven by post-read. (AB-7 was after AB-5)' ]; then
    bd_pass "leg rank/top: --top resolves to before the first open card, one adapter write, OK with the proven position"
  else bd_fail_ "leg rank/top: rc=$bd_rc log=[$(cat "$bd_rkl")] out=[$bd_out]"; fi
  bd_rk "$bd_jclone" "$bd_base/.rk-post-before" AB-7 --before AB-2
  if [ "$bd_rc" -eq 0 ] && grep -qxF 'rank https://ex.atlassian.net cloud AB AB-7 before AB-2' "$bd_rkl" \
     && [ "$bd_out" = 'board rank: OK - AB-7 now before AB-2 (position 2 of 4 open cards), proven by post-read. (AB-7 was after AB-5)' ]; then
    bd_pass "leg rank/before: --before writes once and the post-read proves KEY sits immediately before the anchor"
  else bd_fail_ "leg rank/before: rc=$bd_rc log=[$(cat "$bd_rkl")] out=[$bd_out]"; fi
  bd_rk "$bd_jclone" "$bd_base/.rk-post-after" AB-7 --after AB-2
  if [ "$bd_rc" -eq 0 ] && grep -qxF 'rank https://ex.atlassian.net cloud AB AB-7 after AB-2' "$bd_rkl" \
     && [ "$bd_out" = 'board rank: OK - AB-7 now after AB-2 (position 3 of 4 open cards), proven by post-read. (AB-7 was after AB-5)' ]; then
    bd_pass "leg rank/after: --after writes once and the post-read proves KEY sits immediately after the anchor"
  else bd_fail_ "leg rank/after: rc=$bd_rc log=[$(cat "$bd_rkl")] out=[$bd_out]"; fi
  # leg rank/already-first and rank/dry-run: no write reaches the adapter
  bd_rk "$bd_jclone" "$bd_base/.rk-post-top" AB-9 --top
  if [ "$bd_rc" -eq 0 ] && ! bd_rk_wrote && [ "$bd_out" = 'board rank: AB-9 is already first' ]; then
    bd_pass "leg rank/already-first: --top on the first card prints 'already first', rc 0, and makes no write"
  else bd_fail_ "leg rank/already-first: rc=$bd_rc log=[$(cat "$bd_rkl")] out=[$bd_out]"; fi
  bd_rk "$bd_jclone" "$bd_base/.rk-post-before" AB-7 --before AB-2 --dry-run
  if [ "$bd_rc" -eq 0 ] && ! bd_rk_wrote && grep -q '^list-ranked ' "$bd_rkl" \
     && [ "$bd_out" = 'board rank: would PUT /rest/agile/1.0/issue/rank: AB-7 before AB-2' ]; then
    bd_pass "leg rank/dry-run: --dry-run does the pre-read, prints the PUT it would make, and makes no write"
  else bd_fail_ "leg rank/dry-run: rc=$bd_rc log=[$(cat "$bd_rkl")] out=[$bd_out]"; fi
  # leg rank/usage: two forms, no form, a missing anchor value, an unknown option: rc 2, no adapter call at all
  bd_bad=0
  bd_rk "$bd_jclone" "$bd_base/.rk-post-top" AB-7 --top --before AB-2; [ "$bd_rc" -eq 2 ] && [ ! -s "$bd_rkl" ] || bd_bad=1
  bd_rk "$bd_jclone" "$bd_base/.rk-post-top" AB-7; [ "$bd_rc" -eq 2 ] && [ ! -s "$bd_rkl" ] || bd_bad=1
  bd_rk "$bd_jclone" "$bd_base/.rk-post-top" AB-7 --before; [ "$bd_rc" -eq 2 ] && [ ! -s "$bd_rkl" ] || bd_bad=1
  bd_rk "$bd_jclone" "$bd_base/.rk-post-top" AB-7 --bogus; [ "$bd_rc" -eq 2 ] && [ ! -s "$bd_rkl" ] || bd_bad=1
  bd_rk "$bd_jclone" "$bd_base/.rk-post-top" --top; [ "$bd_rc" -eq 2 ] && [ ! -s "$bd_rkl" ] || bd_bad=1
  # leg rank/keys: another project's key, a leading-zero key, a metacharacter, and ranking a card against itself: rc 2, no adapter call
  bd_rk "$bd_jclone" "$bd_base/.rk-post-top" XY-1 --top; [ "$bd_rc" -eq 2 ] && [ ! -s "$bd_rkl" ] || bd_bad=1
  bd_rk "$bd_jclone" "$bd_base/.rk-post-top" AB-7 --after XY-2; [ "$bd_rc" -eq 2 ] && [ ! -s "$bd_rkl" ] || bd_bad=1
  bd_rk "$bd_jclone" "$bd_base/.rk-post-top" AB-07 --top; [ "$bd_rc" -eq 2 ] && [ ! -s "$bd_rkl" ] || bd_bad=1
  bd_rk "$bd_jclone" "$bd_base/.rk-post-top" AB-7 --before 'AB-1;x'; [ "$bd_rc" -eq 2 ] && [ ! -s "$bd_rkl" ] || bd_bad=1
  bd_rk "$bd_jclone" "$bd_base/.rk-post-top" AB-7 --before AB-7; [ "$bd_rc" -eq 2 ] && [ ! -s "$bd_rkl" ] || bd_bad=1
  if [ "$bd_bad" -eq 0 ]; then
    bd_pass "leg rank/refusals: two forms, no form, a missing anchor, an unknown option, no key, another project's key (as key or anchor), AB-07, a metacharacter and a self-rank each refuse rc 2 with no adapter call"
  else bd_fail_ "leg rank/refusals: bad=$bd_bad (last rc=$bd_rc out=[$bd_out])"; fi
  # leg rank/not-open: a well-formed key (or anchor) that is not an open card is refused after the pre-read, with no write
  bd_bad=0
  bd_rk "$bd_jclone" "$bd_base/.rk-post-top" AB-7 --before AB-3
  { [ "$bd_rc" -eq 2 ] && ! bd_rk_wrote && printf '%s' "$bd_out" | grep -qF 'AB-3 is not an open card on AB'; } || bd_bad=1
  bd_rk "$bd_jclone" "$bd_base/.rk-post-top" AB-4 --top
  { [ "$bd_rc" -eq 2 ] && ! bd_rk_wrote && printf '%s' "$bd_out" | grep -qF 'AB-4 is not an open card on AB'; } || bd_bad=1
  if [ "$bd_bad" -eq 0 ]; then
    bd_pass "leg rank/not-open: a key or an anchor that is not among the open cards is refused rc 2 naming it, with no write"
  else bd_fail_ "leg rank/not-open: bad=$bd_bad (last rc=$bd_rc out=[$bd_out])"; fi
  # leg rank/unproven (LOAD-BEARING NEGATIVE): the write succeeded but the order read back is unchanged. It must be UNPROVEN
  # rc 2 and never OK. This kills the mutant that skips (or ignores) the post-read and reports success on the adapter's rc.
  bd_bad=0
  bd_rk "$bd_jclone" "$bd_base/.rk-pre" AB-7 --before AB-2
  { [ "$bd_rc" -eq 2 ] && bd_rk_wrote && printf '%s' "$bd_out" | grep -qF 'UNPROVEN' && ! printf '%s' "$bd_out" | grep -qF 'OK'; } || bd_bad=1
  bd_rk "$bd_jclone" "$bd_base/.rk-pre" AB-7 --top
  { [ "$bd_rc" -eq 2 ] && bd_rk_wrote && printf '%s' "$bd_out" | grep -qF 'UNPROVEN'; } || bd_bad=1
  bd_rk "$bd_jclone" "$bd_base/.rk-post-before" AB-7 --after AB-2
  { [ "$bd_rc" -eq 2 ] && bd_rk_wrote && printf '%s' "$bd_out" | grep -qF 'UNPROVEN'; } || bd_bad=1
  if [ "$bd_bad" -eq 0 ]; then
    bd_pass "leg rank/unproven: when the order read back does not show the move (before, top and after alike), the verb says UNPROVEN, rc 2, never OK"
  else bd_fail_ "leg rank/unproven: bad=$bd_bad (last rc=$bd_rc out=[$bd_out])"; fi
  # the UNPROVEN line names where the card was, so a bad move can be undone: after its old neighbour, or first
  bd_rk "$bd_jclone" "$bd_base/.rk-pre" AB-7 --before AB-2
  bd_o1=$bd_out
  bd_rk "$bd_jclone" "$bd_base/.rk-pre" AB-9 --after AB-2
  if printf '%s' "$bd_o1" | grep -qF '(AB-7 was after AB-5)' && printf '%s' "$bd_out" | grep -qF 'UNPROVEN' \
     && printf '%s' "$bd_out" | grep -qF '(AB-9 was first)'; then
    bd_pass "leg rank/was: the OK and UNPROVEN lines name the card's old neighbour (was after KEY) or 'was first'"
  else bd_fail_ "leg rank/was: o1=[$bd_o1] out=[$bd_out]"; fi
  # leg rank/post-read-failure: the write was accepted but the post-read fails: UNPROVEN rc 2 (never OK, never a silent rc 1)
  : > "$bd_rkl"; rm -f "$bd_rkd"
  bd_out=$(cd "$bd_jclone" && STUB_LOG="$bd_rkl" STUB_RANK_DONE="$bd_rkd" STUB_RANKED_PRE="$bd_base/.rk-pre" STUB_RANKED_POST="$bd_base/.rk-post-before" STUB_LIST_RC_AFTER=2 do_rank AB-7 --before AB-2 2>&1); bd_rc=$?
  if [ "$bd_rc" -eq 2 ] && bd_rk_wrote \
     && printf '%s' "$bd_out" | grep -qF 'board rank: UNPROVEN - the write was accepted but the post-read failed; read the order back with board list' \
     && ! printf '%s' "$bd_out" | grep -qF 'OK -'; then
    bd_pass "leg rank/post-read-failure: a failed post-read after an accepted write is UNPROVEN rc 2, never OK"
  else bd_fail_ "leg rank/post-read-failure: rc=$bd_rc out=[$bd_out]"; fi
  # leg rank/adapter-failure: a failed write is rc 1 (no OK), the adapter's own refusal (rc 1) is rc 2, a failed pre-read is rc 1 with no write
  : > "$bd_rkl"; rm -f "$bd_rkd"
  bd_out=$(cd "$bd_jclone" && STUB_LOG="$bd_rkl" STUB_RANK_DONE="$bd_rkd" STUB_RANKED_PRE="$bd_base/.rk-pre" STUB_RANKED_POST="$bd_base/.rk-post-before" STUB_RANK_RC=2 do_rank AB-7 --before AB-2 2>&1); bd_rc=$?
  bd_rc1=$bd_rc; bd_o1=$bd_out
  bd_out=$(cd "$bd_jclone" && STUB_LOG="$bd_rkl" STUB_RANK_DONE="$bd_rkd" STUB_RANKED_PRE="$bd_base/.rk-pre" STUB_RANK_RC=1 do_rank AB-7 --before AB-2 2>&1); bd_rc2=$?
  : > "$bd_rkl"
  bd_out=$(cd "$bd_jclone" && STUB_LOG="$bd_rkl" STUB_LIST_RC=2 do_rank AB-7 --before AB-2 2>&1); bd_rc3=$?
  if [ "$bd_rc1" -eq 1 ] && printf '%s' "$bd_o1" | grep -qF 'was not ranked' && ! printf '%s' "$bd_o1" | grep -qF 'OK' \
     && [ "$bd_rc2" -eq 2 ] && [ "$bd_rc3" -eq 1 ] && ! bd_rk_wrote; then
    bd_pass "leg rank/adapter-failure: a failed write is rc 1 and never OK, an adapter refusal is rc 2, an unreadable board is rc 1 with no write"
  else bd_fail_ "leg rank/adapter-failure: rc=$bd_rc1/$bd_rc2/$bd_rc3 o1=[$bd_o1]"; fi
  # leg rank/md and list/md: on md both verbs refuse rc 2 before any adapter call
  : > "$bd_rkl"
  bd_out=$(cd "$bd_base/md-clone" && STUB_LOG="$bd_rkl" do_rank AB-7 --top 2>&1); bd_rc1=$?; bd_o1=$bd_out
  bd_out=$(cd "$bd_base/md-clone" && STUB_LOG="$bd_rkl" do_list 2>&1); bd_rc2=$?
  if [ "$bd_rc1" -eq 2 ] && [ "$bd_rc2" -eq 2 ] && [ ! -s "$bd_rkl" ] && printf '%s' "$bd_o1" | grep -qF 'edit BACKLOG.md' \
     && printf '%s' "$bd_out" | grep -qF 'read BACKLOG.md'; then
    bd_pass "leg rank/md: on an md backend rank and list each refuse rc 2 (the order is the Order line) with no adapter call"
  else bd_fail_ "leg rank/md: rc=$bd_rc1/$bd_rc2 log=[$(cat "$bd_rkl")] o1=[$bd_o1] o2=[$bd_out]"; fi
  # leg list: the header, then the adapter's lines in the stub's order (no re-sort); --limit reaches the adapter; a bad limit is rc 2
  : > "$bd_rkl"
  bd_out=$(cd "$bd_jclone" && STUB_LOG="$bd_rkl" STUB_RANKED_PRE="$bd_base/.rk-pre" do_list 2>&1); bd_rc=$?
  bd_want="open cards on AB, in rank order:
AB-9${bd_rktab}To Do
AB-2${bd_rktab}To Do
AB-5${bd_rktab}To Do
AB-7${bd_rktab}To Do"
  bd_rc1=$bd_rc; bd_o1=$bd_out
  : > "$bd_rkl"
  bd_out=$(cd "$bd_jclone" && STUB_LOG="$bd_rkl" STUB_RANKED_PRE="$bd_base/.rk-pre" do_list --limit 5 2>&1); bd_rc2=$?
  grep -qxF 'list-ranked https://ex.atlassian.net cloud AB 5' "$bd_rkl" && bd_lim=1 || bd_lim=0
  : > "$bd_rkl"
  bd_out=$(cd "$bd_jclone" && STUB_LOG="$bd_rkl" do_list --limit x 2>&1); bd_rc3=$?
  bd_bad_empty=0; [ -s "$bd_rkl" ] && bd_bad_empty=1
  bd_out=$(cd "$bd_jclone" && STUB_LOG="$bd_rkl" STUB_LIST_RC=2 do_list 2>&1); bd_rc4=$?
  if [ "$bd_rc1" -eq 0 ] && [ "$bd_o1" = "$bd_want" ] && [ "$bd_rc2" -eq 0 ] && [ "$bd_lim" -eq 1 ] \
     && [ "$bd_rc3" -eq 2 ] && [ "$bd_bad_empty" -eq 0 ] && [ "$bd_rc4" -eq 1 ]; then
    bd_pass "leg list: prints the header then the adapter's lines in order; --limit reaches the adapter; a non-digit limit is rc 2 with no call; an adapter failure is rc 1"
  else bd_fail_ "leg list: rc=$bd_rc1/$bd_rc2/$bd_rc3/$bd_rc4 lim=$bd_lim o1=[$bd_o1]"; fi

  # leg list-auth (SWAS-101 H1): with KIT_TRACKER_AUTH unset, the adapter sees the conf's auth kind (bearer here); an
  # exported KIT_TRACKER_AUTH is left alone; a conf without an auth line gives basic.
  cp "$bd_jclone/.kit/tracker.conf" "$bd_base/.conf.authsave"
  sed 's/^auth=basic$/auth=bearer/' "$bd_base/.conf.authsave" > "$bd_jclone/.kit/tracker.conf"
  bd_al="$bd_base/.authlog"; : > "$bd_al"
  bd_out=$(cd "$bd_jclone" && unset KIT_TRACKER_AUTH && STUB_AUTH_LOG="$bd_al" STUB_LOG="$bd_rkl" STUB_RANKED_PRE="$bd_base/.rk-pre" do_list 2>&1); bd_rc=$?
  bd_a1=$(sed -n 1p "$bd_al")
  : > "$bd_al"
  bd_out=$(cd "$bd_jclone" && KIT_TRACKER_AUTH=basic && export KIT_TRACKER_AUTH && STUB_AUTH_LOG="$bd_al" STUB_LOG="$bd_rkl" STUB_RANKED_PRE="$bd_base/.rk-pre" do_list 2>&1); bd_rc2=$?
  bd_a2=$(sed -n 1p "$bd_al")
  grep -v '^auth=' "$bd_base/.conf.authsave" > "$bd_jclone/.kit/tracker.conf"
  : > "$bd_al"
  bd_out=$(cd "$bd_jclone" && unset KIT_TRACKER_AUTH && STUB_AUTH_LOG="$bd_al" STUB_LOG="$bd_rkl" STUB_RANKED_PRE="$bd_base/.rk-pre" do_list 2>&1); bd_rc3=$?
  bd_a3=$(sed -n 1p "$bd_al")
  cp "$bd_base/.conf.authsave" "$bd_jclone/.kit/tracker.conf"
  if [ "$bd_rc" -eq 0 ] && [ "$bd_a1" = bearer ] && [ "$bd_a2" = basic ] && [ "$bd_rc3" -eq 0 ] && [ "$bd_a3" = basic ]; then
    bd_pass "leg list-auth: the adapter sees auth=bearer from a bearer conf with KIT_TRACKER_AUTH unset, an exported value is kept, and no auth line gives basic"
  else bd_fail_ "leg list-auth: rc=$bd_rc/$bd_rc2/$bd_rc3 auth=[$bd_a1]/[$bd_a2]/[$bd_a3]"; fi

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

  # ── adapter rc 6 (SWAS-113, TRACKER-ANON-200-REJECT): Jira did not accept the credential. Every verb that talks to the tracker
  # maps it to "the tracker rejected the credential" (rc 1) and NEVER to its own failure wording ("may have applied", "failed or was
  # refused", the validator hint, "was not ranked"): the request was refused before it could change anything. ───────────────────
  bd_rj_chk() { # <label> <needle-that-must-NOT-appear or -> : rc 1, the rejection sentence, no wording of the caller's own
    _rj_label=$1; _rj_not=$2
    if [ "$bd_rc" -eq 1 ] && printf '%s' "$bd_out" | grep -qF 'the tracker rejected the credential' \
       && { [ "$_rj_not" = - ] || ! printf '%s' "$bd_out" | grep -qF -e "$_rj_not"; }; then
      bd_pass "leg rc6/$_rj_label: adapter rc 6 is rc 1 with 'the tracker rejected the credential' and none of the verb's own failure wording"
    else bd_fail_ "leg rc6/$_rj_label: rc=$bd_rc out=[$bd_out]"; fi
  }
  : > "$bd_cl"
  bd_cmt_rc 6
  bd_rj_chk comment 'was not posted'
  bd_show_rc=6; bd_x_show AB-7; bd_show_rc=0
  bd_rj_chk show -
  bd_ed_rc_cur=6; bd_x_run AB-7 --title X; bd_ed_rc_cur=0
  bd_rj_chk edit 'may have applied'
  bd_em_rc_cur=6; bd_x_run AB-7 --title X; bd_em_rc_cur=0
  bd_rj_chk edit-meta 'could not read the editmeta'
  : > "$bd_rkl"; rm -f "$bd_rkd"
  bd_out=$(cd "$bd_jclone" && STUB_LOG="$bd_rkl" STUB_RANK_DONE="$bd_rkd" STUB_RANKED_PRE="$bd_base/.rk-pre" STUB_RANKED_POST="$bd_base/.rk-post-before" STUB_RANK_RC=6 do_rank AB-7 --before AB-2 2>&1); bd_rc=$?
  bd_rj_chk rank-write 'was not ranked'
  : > "$bd_rkl"
  bd_out=$(cd "$bd_jclone" && STUB_LOG="$bd_rkl" STUB_LIST_RC=6 do_rank AB-7 --before AB-2 2>&1); bd_rc=$?
  bd_rj_chk rank-read 'could not read the open cards'
  bd_out=$(cd "$bd_jclone" && STUB_LOG="$bd_rkl" STUB_LIST_RC=6 do_list 2>&1); bd_rc=$?
  bd_rj_chk list 'could not read the open cards'
  bd_out=$(cd "$bd_jclone" && STUB_STATE='Selected for Development' STUB_TRANSITION_RC=6 do_move ROW-JIRA-13 'done' 2>&1); bd_rc=$?
  bd_rj_chk move 'failed or was refused'
  bd_out=$(cd "$bd_cc" && STUB_CM_DIR="$bd_cmdir" STUB_CREATE_RC=6 do_create --title "x" 2>&1); bd_rc=$?
  bd_rj_chk create 'workflow validator'
  bd_out=$(cd "$bd_cc" && STUB_CM_DIR="$bd_cmdir" STUB_CM_RC=6 do_create --title "x" 2>&1); bd_rc=$?
  bd_rj_chk create-meta 'could not read the create-meta'
  bd_out=$(cd "$bd_cc" && STUB_CM_DIR="$bd_cmdir" STUB_RF_RC=6 do_create --title "x" 2>&1); bd_rc=$?
  bd_rj_chk create-required 'could not read the required fields'

  # S-L1: a 2xx served anonymously to a WRITE may have applied; the adapter's sentence ends "(the write may have applied
  # anonymously)" and the verb must NOT say "nothing was changed" (edit keeps "may have applied", rc 3).
  STUB_ANON_SUFFIX=1; export STUB_ANON_SUFFIX
  bd_aw_chk() { # <label> <want-rc> <needle>
    if [ "$bd_rc" -eq "$2" ] && printf '%s' "$bd_out" | grep -qF -e "$3" && ! printf '%s' "$bd_out" | grep -qF 'nothing was changed'; then
      bd_pass "leg rc6-anon-write/$1: an anonymously served write is rc $2 saying '$3', never 'nothing was changed'"
    else bd_fail_ "leg rc6-anon-write/$1: rc=$bd_rc out=[$bd_out]"; fi
  }
  bd_out=$(cd "$bd_cclone" && STUB_LOG="$bd_cl" STUB_COMMENT_RC=6 do_comment AB-7 --from-record docs/reviews/x.md 2>&1); bd_rc=$?
  bd_aw_chk comment 1 'may have been posted'
  bd_ed_rc_cur=6; bd_x_run AB-7 --title X; bd_ed_rc_cur=0
  bd_aw_chk edit 3 'may have applied'
  : > "$bd_rkl"; rm -f "$bd_rkd"
  bd_out=$(cd "$bd_jclone" && STUB_LOG="$bd_rkl" STUB_RANK_DONE="$bd_rkd" STUB_RANKED_PRE="$bd_base/.rk-pre" STUB_RANKED_POST="$bd_base/.rk-post-before" STUB_RANK_RC=6 do_rank AB-7 --before AB-2 2>&1); bd_rc=$?
  bd_aw_chk rank 1 'order may have changed'
  bd_out=$(cd "$bd_jclone" && STUB_STATE='Selected for Development' STUB_TRANSITION_RC=6 do_move ROW-JIRA-13 'done' 2>&1); bd_rc=$?
  bd_aw_chk move 1 'may have moved'
  bd_out=$(cd "$bd_cc" && STUB_CM_DIR="$bd_cmdir" STUB_CREATE_RC=6 do_create --title "x" 2>&1); bd_rc=$?
  bd_aw_chk create 1 'may have been created'
  unset STUB_ANON_SUFFIX

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
  # the migrate verb hands off to board-migrate.sh: no arguments is its usage refusal (rc 2), reached through this dispatch
  bd_out=$(sh "$BD_SELF" migrate 2>&1); bd_rc=$?
  if [ "$bd_rc" -eq 2 ] && printf '%s' "$bd_out" | grep -qF -e '--from'; then bd_pass "leg usage/migrate: the migrate verb dispatches to board-migrate.sh (no arguments is rc 2 with its usage)"
  else bd_fail_ "leg usage/migrate: rc=$bd_rc out=[$bd_out]"; fi

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
  comment)    shift; if do_comment "$@"; then bd_rc_main=0; else bd_rc_main=$?; fi ;;
  rank)       shift; if do_rank "$@"; then bd_rc_main=0; else bd_rc_main=$?; fi ;;
  list)       shift; if do_list "$@"; then bd_rc_main=0; else bd_rc_main=$?; fi ;;
  show)       shift; if do_show "$@"; then bd_rc_main=0; else bd_rc_main=$?; fi ;;
  edit)       shift; if do_edit "$@"; then bd_rc_main=0; else bd_rc_main=$?; fi ;;
  migrate)    shift; exec sh "$here/board-migrate.sh" "$@" ;;
  -h|--help)  bd_usage; bd_rc_main=2 ;;
  "")         bd_usage; bd_rc_main=2 ;;
  *)          echo "board.sh: unknown verb '$1'" >&2; bd_usage; bd_rc_main=2 ;;
esac
exit "$bd_rc_main"
