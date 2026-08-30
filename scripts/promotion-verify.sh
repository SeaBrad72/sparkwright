#!/bin/sh
# promotion-verify.sh — the approve->execute->log actuation integrity tool for NON-control-plane
# promotions (KW1 . D2; docs/governance/promotion-contract.md "Approve->execute->log").
#
# Three modes:
#   record  --approved-sha <sha> --approved-by <id> --gate <g> --rung <r> --class <c> \
#           --scope <pr> --token "<explicit approval string>" [--basis <text>]
#       -> BIND a structured GO record to the approved commit as a git NOTE under
#          refs/notes/promotions (tree-invariant: the commit's tree/SHA is unchanged, so `check`
#          can NEVER false-fail because of the record). The `approved-by` line is written with a
#          DERIVED assurance label ([signed: gpg] -> [committer] -> [self-asserted]) — the label
#          is derived from the commit's own evidence, never accepted from input, and never claims
#          more than the evidence proves.
#          `--scope` carries EITHER a PR id (`PR-<n>` — what CI's ceremony-binding matches) OR
#          `branch/<name>` (owner ruling D11: the key the pre-push predicate derives, so a design
#          GO can bind BEFORE a PR exists). The `branch/` shape is charset-validated below against
#          the same charset the gates match on; other scopes keep their existing hygiene.
#
#          `record` also PROJECTS the approved commit's `Kit-Row` trailer into the note as
#          `kit-row:` (derived through git's own trailer parser, never a flag; `(none)` when the
#          commit carries none, never invented). That projection is what makes `trace` possible.
#
#   log
#       -> render refs/notes/promotions as a human-readable trail (a PROJECTION of the notes,
#          not a second synced surface — replaces the retired docs/governance/promotion-log.md).
#
#   trace   --ref <sha> | --recent <n> [--from <trunk-ref>]
#       -> RECOVER the board row for a commit that ALREADY LANDED. Under a squash merge the trunk
#          commit is composed by the forge and carries no Kit-* trailer (MEASURED on this repo:
#          0/60), so `git log` on the default branch is the wrong place to audit adherence. This
#          matches a trunk commit to its GO note BY TREE — the same fingerprint `check` uses, and
#          the one thing a squash preserves where ancestry does not — and prints the recorded row.
#          `--recent <n>` walks the trunk (origin/main, else main) and REDS if any commit in the
#          window has no recoverable row: that is the recordless-merge alarm. Read-only.
#          MEASURED 2026-08-30 on this repo: 28/30 recoverable; both misses were board chores
#          merged with no GO record at all, which is exactly what the red is for.
#
#   check   --ref <merged-ref|tag> [--approved-sha <sha>]
#       -> assert the SHIPPED content EQUALS the APPROVED content (shipped == approved),
#          by TREE equality — the shipped ref's tree must equal the approved commit's tree.
#          Tree equality = exact content equality: it neither false-FAILS a squash merge
#          (the approved feature-tip is not in the squashed trunk history) nor false-PASSES
#          a revert-after-merge or extra unapproved content riding on top of the approved SHA.
#          approved-sha resolves from --approved-sha, else the latest note (by record order).
#          merge ref: git rev-parse "<ref>^{tree}"  ==  git rev-parse "<approved-sha>^{tree}".
#          tag:       the same tree equality between the tag and the approved-sha, PLUS
#                     `git show <tag>:VERSION` == `git show <approved-sha>:VERSION` (belt+braces).
#          Ref is treated as a tag when refs/tags/<ref> resolves, else as a merged ref.
#
# Exit: 0 = ok . 1 = MISMATCH (loud: "SHIPPED != APPROVED") . 2 = usage/args.
#
# HONEST CEILING (do not overclaim):
#   * `shipped == approved` is the GATEABLE guarantee — the record's existence, its SHA-binding,
#     and the post-actuation content match are all checkable. This is UNCHANGED by S5a.
#   * The record now BINDS via a git note (tree-invariant) — placement is solved: the record can
#     never perturb the approved tree, so the entire "log-append false-fails check" class is gone.
#     But a git note is a MUTABLE ref: notes BIND, they do NOT AUTHENTICATE. Tamper-evidence of the
#     APPROVAL rides on the `approved-by` SOURCE's assurance (below), not on the note storage.
#   * Assurance is LABELED, not proven-strong: [committer] is honest-but-weak (user.name is
#     self-set), [self-asserted] is weaker still. The label states HOW identity was established and
#     never overclaims — an unsigned commit can never be [signed: gpg]. Authenticated team approval
#     (forge PR/MR review -> [authenticated: <forge>-review]) is a SEAM in docs/adoption/vc-hosts.md,
#     wired when a team consumer exists — NOT wired here (no solo consumer).
#   * `trace` green means A NOTE EXISTS whose approved tree equals the trunk commit's tree and
#     which names a row. It does NOT mean the row was the RIGHT row, nor that the Entry Declaration
#     it came from was true. It inherits the GO record's assurance exactly and no more — the same
#     bind-not-authenticate ceiling as everything else here (D-240805-3). Say "the row is
#     RECOVERABLE", never "the row is verified".
#   * ⚠️ A LEGACY NOTE'S RECOVERY DEPENDS ON OBJECT REACHABILITY; FROM 2026-08-30 THE TREE RIDES IN
#     THE NOTE. `trace` matches by tree. Until 2026-08-30 it obtained the approved tree by resolving
#     `approved-sha^{tree}` at trace time, which silently assumed the approved COMMIT OBJECT was
#     still fetchable. In a developer clone it is; in a CI checkout it is NOT — `fetch-depth: 0`
#     fetches heads and tags, and every approved-sha on this repo is a PR-branch head deleted after
#     its squash. MEASURED on the first live run (CI, PR #601): 10/10 trunk commits reported
#     unrecoverable, while the identical command scored 10/10 on the developer machine.
#     `record` now writes `approved-tree:` into the note, so a note written from 2026-08-30 is
#     self-contained. A note written BEFORE that still needs its approved commit object, and where
#     that object is unreachable the commit is reported `unresolvable (approved commit object not
#     reachable from this checkout)` and counted as NOT recoverable — deliberately distinct from
#     "recordless merge", because the remedy is a fetch, not a governance repair.
#   * ⚠️ THE TREE->NOTE PAIRING IS MANY-TO-ONE, AND ONLY PART OF THAT IS CLOSED. Trees are not
#     unique to commits: an EMPTY commit, or a revert-and-reapply pair, reproduces an earlier
#     commit's tree and would borrow its note — being credited with a GO nobody gave it.
#     WHAT IS CLOSED: within a `--recent` window each annotated sha may be claimed ONCE, oldest
#     commit first, so a later commit reproducing an earlier tree REDS as `[shared-tree with <sha>]`
#     instead of passing (security H-1).
#     WHAT IS NOT CLOSED, AND IS DISCLOSED RATHER THAN PAPERED OVER: a stale pairing whose partner
#     lies OUTSIDE the window. A revert that restores a tree approved twenty commits ago still
#     matches that older note and is credited to it, because the dedup only sees the commits it
#     walked. Widening the window narrows the hole; it does not remove it. Do not describe this leg
#     as "every trunk commit has its own GO" — describe it as "no commit in this window borrowed
#     another's, and each is bound to some recorded GO".
#   * `never-infer` — that the agent WAITED for an explicit recorded per-gate human GO — is FLOOR
#     discipline, NOT enforced by this tool. A green `check` proves what shipped carries the approved
#     SHA; it does NOT prove the agent's judgment or that it refused to infer.
# Control-plane stays human-actuated (bootstrap); this tool wires NON-control-plane promotions only.
#
# POSIX sh; dash-clean (no `local`, no bashisms). Operates on the current working tree's git repo.
# The notes ref name is overridable with PROMOTION_NOTES_REF (default: promotions) for testing.
# What it changes: `record` binds a GO record as a git NOTE under refs/notes/promotions (tree-invariant — the commit's tree/SHA is unchanged); `actuate` performs a real control-plane PR merge (default `gh pr merge --squash`, swappable via --merge-cmd) bound to the approved SHA; `log`, `check` and `trace` are read-only.
# Guardrails: `check` asserts shipped==approved by TREE equality (exit 1 on MISMATCH); the approved-by assurance label is DERIVED from the commit's own evidence (never from input) — a note BINDS, it does not AUTHENTICATE. `actuate` fails CLOSED unless a SHA-bound [authenticated: <forge>-review] GO exists and approver != author, rejects `$ref` metacharacters, NEVER emits `--admin`, and re-verifies shipped==approved after the merge. `record` derives `kit-row:` from the approved commit's own trailer (never a flag), records `(none)` rather than inventing one, and sanitises it with every other free-text field; `trace` matches a trunk commit to its note by TREE (never ancestry, which a squash breaks), reds on any recordless commit in a `--recent` window, and fails closed on an empty window.
set -eu

NOTES_REF="${PROMOTION_NOTES_REF:-promotions}"

usage() {
  echo "usage:" >&2
  echo "  promotion-verify.sh record --approved-sha <sha> --approved-by <id> --gate <g> \\" >&2
  echo "                             --rung <r> --class <c> --scope <pr> --token <str> [--basis <t>]" >&2
  echo "        --scope takes a PR id (CI's key) or branch/<name> (the pre-push key, ruling D11)" >&2
  echo "  promotion-verify.sh log" >&2
  echo "  promotion-verify.sh trace --ref <sha> | --recent <n> [--from <trunk-ref>]" >&2
  echo "        recover the board row for a commit that already landed (squash loses the trailer)" >&2
  echo "  promotion-verify.sh check  --ref <merged-ref|tag> [--approved-sha <sha>]" >&2
  echo "  promotion-verify.sh actuate --ref <pr|tag|merged-ref> --approved-sha <sha> [--merge-cmd \"<cmd>\"]" >&2
}

# Derive the assurance label for `approved-by`, HONESTLY, from the commit's own evidence.
# Rules (never overclaims — the non-vacuity anchor):
#   [signed: gpg]   the approved-sha carries a good signature (git verify-commit succeeds, or
#                   %G? in {G,U}). Cryptographic identity — forge-agnostic.
#   [committer]     no signature, but the approver id EQUALS the commit's committer identity
#                   (%cn or %ce) — git attests THIS identity made the commit (weak: user.name is
#                   self-set, but it is a git-attested field, not a free-typed claim).
#   [self-asserted] no signature and the approver is a free-typed string git cannot corroborate
#                   against the commit (the solo default; also the honest label for a reviewer who
#                   is not the committer).
# Prints the bare label text (without brackets). Never trusts a caller-supplied label.
derive_assurance() {
  _sha="$1"; _id="${2:-}"
  if git verify-commit "$_sha" >/dev/null 2>&1; then
    echo "signed: gpg"; return 0
  fi
  _g="$(git show -s --format='%G?' "$_sha" 2>/dev/null || echo N)"
  case "$_g" in
    G|U) echo "signed: gpg"; return 0 ;;
  esac
  _cn="$(git show -s --format='%cn' "$_sha" 2>/dev/null || echo '')"
  _ce="$(git show -s --format='%ce' "$_sha" 2>/dev/null || echo '')"
  if [ -n "$_id" ] && { [ "$_id" = "$_cn" ] || [ "$_id" = "$_ce" ]; }; then
    echo "committer"; return 0
  fi
  echo "self-asserted"
}

# Latest approved-sha bound by a note, in RECORD ORDER (newest first). Walks the notes-ref commit
# history: each `git notes add` is a new commit on refs/notes/promotions, so rev-list order IS the
# record order. The note path added/modified in the newest commit (fanout slashes stripped) is the
# annotated commit's sha. Deterministic (no timestamp ties, unlike a wall-clock sort).
resolve_latest_sha() {
  git rev-parse -q --verify "refs/notes/$NOTES_REF" >/dev/null 2>&1 || return 1
  for _nc in $(git rev-list "refs/notes/$NOTES_REF" 2>/dev/null); do
    _obj="$(git diff-tree --root --no-commit-id --name-only -r "$_nc" 2>/dev/null | head -1 | tr -d '/')"
    if [ -n "$_obj" ]; then printf '%s\n' "$_obj"; return 0; fi
  done
  return 1
}

do_record() {
  asha=""; aby=""; gate=""; rung=""; cls=""; scope=""; token=""; basis=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --approved-sha) asha="${2:-}"; shift 2 ;;
      --approved-by)  aby="${2:-}";  shift 2 ;;
      --gate)         gate="${2:-}"; shift 2 ;;
      --rung)         rung="${2:-}"; shift 2 ;;
      --class)        cls="${2:-}";  shift 2 ;;
      --scope)        scope="${2:-}"; shift 2 ;;
      --token)        token="${2:-}"; shift 2 ;;
      --basis)        basis="${2:-}"; shift 2 ;;
      *) echo "record: unknown arg '$1'" >&2; usage; return 2 ;;
    esac
  done
  for pair in "approved-sha=$asha" "approved-by=$aby" "gate=$gate" "rung=$rung" \
              "change-class=$cls" "scope=$scope" "approval-token=$token"; do
    _v="${pair#*=}"
    if [ -z "$_v" ]; then echo "record: missing --${pair%%=*}" >&2; usage; return 2; fi
  done
  # Reject option-like values: a --approved-sha beginning with '-' must never reach git as a flag.
  case "$asha" in -*) echo "record: invalid --approved-sha '$asha' (must not start with '-')" >&2; return 2 ;; esac
  # SANITIZE (S5a review, CRITICAL): the note body is line-structured text. A NEWLINE (or any control
  # char) in a free-text field would inject arbitrary lines — e.g. a forged `approved-by: x [signed:
  # gpg]` / `[authenticated: ...]` line that bypasses derive_assurance entirely. Reject any control
  # char in ANY free-text field and fail CLOSED (return 2) — never silently strip: a GO with a mangled
  # token must be re-issued cleanly. (POSIX/dash-clean: strip control chars via `tr` and compare.)
  for _p in "token=$token" "basis=$basis" "approved-by=$aby" "scope=$scope" \
            "gate=$gate" "rung=$rung" "class=$cls"; do
    _fn="${_p%%=*}"; _fv="${_p#*=}"
    if [ "$(printf '%s' "$_fv" | LC_ALL=C tr -d '[:cntrl:]')" != "$_fv" ]; then
      echo "record: --$_fn contains a control character (newline/CR/tab/etc.) — rejected (fail closed)" >&2
      return 2
    fi
  done
  # BRANCH SCOPING (owner ruling D11, 2026-07-28; B2 Δ1′). `--scope branch/<name>` is the key
  # conformance/ceremony-binding.sh --pre-push DERIVES from the checked-out branch, which is what
  # lets a design GO bind BEFORE a PR exists (the [S4]#7 back-fill this repo kept re-deriving).
  # VALIDATE THE SHAPE HERE, at the front door, with the SAME charset the gates match on
  # (ceremony-binding.sh's `_scope_charset_bad`, and its --scope boundary validator): the gate
  # compares the key with `grep -F -x`, so a `branch/` scope it can never produce would be recorded
  # DEAD — a record that satisfies nothing and reports no error. Reject it instead.
  # SCOPED TO THE NEW SHAPE ONLY, deliberately: non-`branch/` scopes keep the hygiene they already
  # had (control-chars rejected above, everything else allowed). This repo's own ledger holds legal
  # scopes with a space ("PR #999"), so retrofitting the charset onto every scope would refuse
  # records the gates already accept — a new charset hole is not opened, and no old one is closed
  # by surprise.
  case "$scope" in
    branch/)
      echo "record: --scope 'branch/' names no branch (expected branch/<name>) — rejected" >&2
      return 2 ;;
    branch/*)
      case "${scope#branch/}" in
        *[!A-Za-z0-9_.:/-]*)
          echo "record: --scope branch/<name> may contain only [A-Za-z0-9_.:/-] after 'branch/' —" >&2
          echo "        the design gate matches this key LITERALLY, so a name it cannot express" >&2
          echo "        would record a GO that satisfies nothing. Rejected (fail closed)." >&2
          return 2 ;;
      esac ;;
  esac
  # Reject '[' or ']' ANYWHERE in --approved-by (S5a review): the assurance label is DERIVED below,
  # never supplied. A trailing-only strip left a mid-string "[signed: gpg]" decoy in the body that
  # could fool a substring grep — reject brackets outright instead.
  case "$aby" in
    *'['* | *']'*)
      echo "record: --approved-by must not contain '[' or ']' (assurance label is derived, not supplied) — rejected" >&2
      return 2 ;;
  esac
  [ -n "$basis" ] || basis="(none recorded)"
  # KIT-ROW PROJECTION (ENTRY-DECLARATION-SEVERED-ON-MAIN, 2026-08-30). The board row is DERIVED
  # from the approved commit through git's own trailer parser — never a --flag, because a
  # caller-supplied row would be a second self-assertion and this record is the one place the row
  # can be recovered from later. MEASURED: 0/60 of this repo's main commits carry a parseable
  # Kit-Row (the forge composes the squash message), while 28/30 were recoverable through these
  # notes. `head -1` because a commit with two Kit-Row lines is already refused by loop-state; here
  # we record ONE value rather than injecting a second line into a line-structured body.
  #
  # ⚠️ NEVER INVENTED. A commit with no Kit-Row records the literal `(none)`, which is not the same
  # as omitting the field: an omitted field is indistinguishable from a note written before this
  # projection existed, and `trace` would have to guess which. `(none)` is a positive statement
  # that the approved commit carried no row.
  #
  # SANITISED BY ITS OWN CONTROL-CHAR ARM BELOW, *NOT* by the shared loop above — because kit-row is
  # DERIVED after that loop has already run. (This comment previously claimed "kit-row is in it",
  # which was false and would have sent a reader looking for coverage that was not there.) The check
  # is the same rule for the same reason: a trailer value is PR-controlled text and the note body is
  # line-structured, so an embedded newline here would forge a note line exactly as one in --token
  # would. Fail CLOSED (rc 2, no note written) rather than stripping — a GO whose row is mangled
  # must be re-recorded cleanly.
  kitrow="$(git log -1 --format='%(trailers:key=Kit-Row,valueonly)' "$asha" 2>/dev/null | head -1)"
  [ -n "$kitrow" ] || kitrow="(none)"
  if [ "$(printf '%s' "$kitrow" | LC_ALL=C tr -d '[:cntrl:]')" != "$kitrow" ]; then
    echo "record: the approved commit's Kit-Row trailer contains a control character — rejected (fail closed)" >&2
    return 2
  fi
  # the approved-sha must resolve to a real commit before we bind a note to it.
  if ! git rev-parse -q --verify "${asha}^{commit}" >/dev/null 2>&1; then
    echo "record: approved-sha '$asha' is not a resolvable commit in this repo" >&2; return 2
  fi
  # THE NOTE CARRIES THE TREE, NOT ONLY A POINTER TO IT (first live run of the recordless-merge leg,
  # CI PR #601 — see the ceiling note in the header).
  #
  # WHY. `trace` matches a trunk commit to its GO by TREE equality, and it used to obtain the
  # approved tree by resolving `approved-sha^{tree}` at trace time. That silently assumed the
  # approved COMMIT OBJECT is still reachable — true in a developer clone that fetched the PR
  # branch, FALSE in a CI checkout: `fetch-depth: 0` fetches heads and tags, and every approved-sha
  # here is a PR-branch head deleted after its squash merge. Measured: 10/10 trunk commits
  # "unrecoverable" in CI while the identical command scored 10/10 locally. A pointer to an object
  # nobody can fetch is not a record.
  #
  # Derived HERE, at record time, where the object is guaranteed present (the check above just
  # resolved it). A 40-hex tree id needs no control-char sanitising — it cannot contain one — but it
  # IS validated as 40 hex, because writing a malformed value into a line-structured body is the
  # same class of defect whether or not the source is attacker-controlled.
  atree="$(git rev-parse -q --verify "${asha}^{tree}" 2>/dev/null || true)"
  case "$atree" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) echo "record: could not derive a 40-hex approved-tree from '$asha' (got '$atree') — refusing to write a record that cannot be traced" >&2
       return 2 ;;
  esac
  # The assurance label is DERIVED (below), never accepted from input. Brackets in --approved-by were
  # rejected above, so the id is the caller string verbatim — input can't manufacture assurance.
  aby_id="$aby"
  assurance="$(derive_assurance "$asha" "$aby_id")"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
  # Bind the structured record to the approved commit as a note (tree-invariant). `-f` overwrites a
  # prior note on the same commit (re-record supersedes) — honest: notes are mutable (see ceiling).
  # KIT_PROMOTION_FRONT_DOOR=1 is the FRONT-DOOR SENTINEL, scoped to this ONE command [B2 sec H1].
  # guard-core.sh's Δ4(i)′ arm denies raw `git notes` writes to the ledger; under `kit-guard
  # install-shims` every git invocation is routed through that arm, so without this the arm blocked
  # the exact door its own deny message points the operator at and the ledger became unwritable by
  # any route (measured). IT IS AGENT-FORGEABLE — an agent can prefix the same variable to a raw
  # command — and the arm's ceiling says so: the arm is a drift control (owner ruling D3′), not a
  # boundary; the control that binds is the record rendered at the CI judgment surface.
  if ! printf '%s\n' \
      "record: promotion GO (approve->execute->log)" \
      "approved-sha: $asha" \
      "approved-tree: $atree" \
      "approved-by: $aby_id [$assurance]" \
      "gate: $gate" \
      "rung: $rung" \
      "change-class: $cls" \
      "kit-row: $kitrow" \
      "scope: $scope" \
      "approval-token: \"$token\"" \
      "basis: $basis" \
      "recorded-at: $ts" \
      | KIT_PROMOTION_FRONT_DOOR=1 git notes --ref="$NOTES_REF" add -f -F - "$asha" >/dev/null 2>&1; then
    echo "record: failed to write note refs/notes/$NOTES_REF on $asha" >&2; return 2
  fi
  echo "OK: recorded approval for $scope (approved-sha $asha) -> note refs/notes/$NOTES_REF [$assurance]"
  echo "     share it: git push origin refs/notes/$NOTES_REF"
  return 0
}

# do_trace — RECOVER the board row (and the GO) for a commit that already landed on the trunk.
#
# THE PROBLEM. `loop-state.sh` refuses a PR head that carries no Entry Declaration, but the commit
# that LANDS is composed by the forge under a squash merge and carries no Kit-* trailer at all
# (measured on this repo: 0/60). So the trunk history is the wrong place to audit adherence, and a
# check that read it would be vacuously green. The record path is where the row survives:
# `record` projects Kit-Row into the note, and this mode reads it back.
#
# HOW A TRUNK COMMIT IS MATCHED TO ITS NOTE: BY TREE, never by ancestry and never by message.
# Ancestry is exactly what a squash breaks — the approved feature tip is not an ancestor of the
# squashed trunk commit. The TREE is invariant across the squash, which is the same fingerprint
# `check` already uses for shipped==approved. So the pairing is: note on X pairs with trunk commit
# C iff X^{tree} == C^{tree}.
#
# HONEST CEILING: green means A NOTE EXISTS whose approved tree equals this commit's tree and which
# names a row. It does NOT mean the row was the RIGHT row, or that the declaration was true — this
# inherits the GO record's assurance exactly and no more (notes BIND, they do not AUTHENTICATE;
# D-240805-3). A forged note is as forgeable here as anywhere else in this file.
#
# READ-ONLY: writes nothing, moves no ref.
do_trace() {
  ref=""; recent=""; from=""
  # ⚠️ `[ $# -ge 2 ]` BEFORE EVERY `shift 2` (review L-3). Without it, a trailing `--ref` with no
  # value takes the `${2:-}` empty default and then `shift 2` on a one-element list — which in dash
  # is an error the `set -eu` script exits on, and in other shells silently empties the list. Either
  # way the flag is swallowed instead of refused. rc 2 is the usage answer.
  while [ $# -gt 0 ]; do
    case "$1" in
      --ref)    [ $# -ge 2 ] || { echo "trace: --ref needs a value" >&2; return 2; }
                ref="$2";    shift 2 ;;
      --recent) [ $# -ge 2 ] || { echo "trace: --recent needs a value" >&2; return 2; }
                recent="$2"; shift 2 ;;
      --from)   [ $# -ge 2 ] || { echo "trace: --from needs a value" >&2; return 2; }
                from="$2";   shift 2 ;;
      *) echo "trace: unknown arg '$1'" >&2; usage; return 2 ;;
    esac
  done
  if [ -z "$ref" ] && [ -z "$recent" ]; then
    echo "trace: need --ref <sha> or --recent <n>" >&2; usage; return 2
  fi
  # PER-ARGUMENT, NOT CONCATENATED (review L-4). `case "$ref$recent$from"` only ever saw the FIRST
  # character of the joined string, so `--ref abc --from -x` passed: the leading `-` was in the
  # middle of the concatenation and matched nothing. Each value is checked on its own.
  for _tr_arg in "$ref" "$recent" "$from"; do
    case "$_tr_arg" in -*)
      echo "trace: arguments must not start with '-' (got '$_tr_arg')" >&2; return 2 ;;
    esac
  done
  case "$recent" in ''|*[!0-9]*) [ -z "$recent" ] || { echo "trace: --recent takes a positive integer" >&2; return 2; } ;; esac
  if ! git rev-parse -q --verify "refs/notes/$NOTES_REF" >/dev/null 2>&1; then
    echo "trace: no refs/notes/$NOTES_REF in this repository — nothing to trace against." >&2
    echo "       fetch it first: git fetch origin refs/notes/$NOTES_REF:refs/notes/$NOTES_REF" >&2
    return 1
  fi

  # Build the tree -> annotated-commit index ONCE. `git notes list` prints "<note-obj> <annotated>".
  # An annotated sha that is no longer in the object store is SKIPPED, not fatal: the note points at
  # the row-bearing commit, it does not carry it, and a pruned feature branch is ordinary (measured:
  # 4 / 233 on this repo). Those simply cannot be recovered, and the caller is told so by name.
  # TWO SOURCES FOR THE APPROVED TREE, IN THIS ORDER, AND THE ORDER IS THE FIX:
  #   1. the note's own `approved-tree:` line — self-contained, needs no object beyond the note;
  #   2. `approved-sha^{tree}` — the LEGACY path, which works only while that commit object is
  #      reachable from this checkout.
  # Every note written before 2026-08-30 has only (2), and in a CI checkout (2) resolves for none of
  # them: the approved-shas are PR-branch heads deleted after squash. Such a note is recorded in the
  # index as UNRESOLVABLE rather than silently dropped, so the commit it belongs to reds by name
  # instead of being reported as a recordless merge — a different fault with a different remedy.
  _tr_idx="$(git notes --ref="$NOTES_REF" list 2>/dev/null)" || _tr_idx=""
  _tr_map=""
  _tr_unres=""
  for _tr_a in $(printf '%s\n' "$_tr_idx" | awk '{print $2}'); do
    _tr_body="$(git notes --ref="$NOTES_REF" show "$_tr_a" 2>/dev/null)" || _tr_body=""
    _tr_t="$(printf '%s\n' "$_tr_body" | sed -n 's/^approved-tree: //p' | head -1)"
    if [ -z "$_tr_t" ]; then
      # LEGACY FALLBACK. ⚠️ Resolve the tree of the sha the NOTE RECORDS, not of the object the note
      # is ATTACHED to. In practice `record` attaches the note to the approved-sha, so the two
      # coincide and the distinction never shows — which is exactly why it was wrong here and went
      # unnoticed until a fixture attached a legacy note to a different object. Reading the
      # annotated object's tree would have made every legacy note "resolvable" by pointing at
      # whatever it happened to hang on, silently matching the wrong commit.
      _tr_asha="$(printf '%s\n' "$_tr_body" | sed -n 's/^approved-sha: //p' | head -1)"
      [ -n "$_tr_asha" ] || _tr_asha="$_tr_a"
      _tr_t="$(git rev-parse -q --verify "$_tr_asha^{tree}" 2>/dev/null)" || _tr_t=""
      if [ -z "$_tr_t" ]; then
        _tr_unres="$_tr_unres $_tr_a"
        continue
      fi
    fi
    _tr_map="$_tr_map$_tr_t $_tr_a
"
  done

  # CLAIMED-NOTE LEDGER (security H-1 / review L2). THE TREE->NOTE PAIRING IS MANY-TO-ONE, and that
  # is not a corner case: an EMPTY commit, or a revert-and-reapply pair, produces a trunk commit
  # whose tree equals an already-recorded commit's tree. It would silently BORROW that commit's note
  # and be credited with a GO nobody gave it — which is precisely the recordless merge this leg
  # exists to catch, wearing the costume of the merge before it. Within a `--recent` window we can
  # refuse it: each annotated sha may be claimed ONCE, and a second claimant reds by name.
  _tr_claimed=""
  # trace_one <commit> — print the recovered record, or rc 1 with a reason naming the commit.
  trace_one() {
    _tc="$(git rev-parse -q --verify "$1^{commit}" 2>/dev/null)" || {
      echo "trace: '$1' is not a commit in this repository" >&2; return 2; }
    _tt="$(git rev-parse "$_tc^{tree}")"
    _ta="$(printf '%s' "$_tr_map" | awk -v t="$_tt" '$1 == t {print $2; exit}')"
    if [ -z "$_ta" ]; then
      # TWO DIFFERENT FAULTS, AND CONFLATING THEM SENDS THE READER TO THE WRONG REMEDY. A genuine
      # recordless merge means nobody recorded a GO. An unresolvable legacy note means a GO WAS
      # recorded but its approved commit object is not reachable from this checkout, so its tree
      # cannot be computed here — a fetch problem, not a governance one.
      if [ -n "$_tr_unres" ]; then
        echo "trace: $_tc unresolvable (approved commit object not reachable from this checkout — fetch refs/pull/*/head)." >&2
        echo "       $(printf '%s' "$_tr_unres" | wc -w | tr -d ' ') note(s) in the ledger carry no 'approved-tree:' line AND their approved-sha is absent here," >&2
        echo "       so this commit cannot be matched. Notes written from 2026-08-30 carry the tree and do not need the object." >&2
      else
        echo "trace: $_tc has no promotion note — no recorded GO whose approved tree equals this commit's tree." >&2
        echo "       This is a RECORDLESS MERGE: the board row that authorised it is not recoverable." >&2
      fi
      return 1
    fi
    # THE DEDUP. Only meaningful across a window, so it is scoped to the `--recent` walk by
    # `_tr_claimed` being empty on a single `--ref` call — a lone commit has nothing to collide with.
    case " $_tr_claimed " in
      *" $_ta "*)
        echo "trace: $_tc [shared-tree with $_ta] — recordless (an empty commit / revert-and-reapply borrows another commit's note)." >&2
        echo "       Its tree equals an EARLIER commit's in this window, so the only note that matches is one already claimed." >&2
        return 1 ;;
    esac
    _tr_claimed="$_tr_claimed $_ta"
    _tn="$(git notes --ref="$NOTES_REF" show "$_ta" 2>/dev/null)" || _tn=""
    _trow="$(printf '%s\n' "$_tn" | sed -n 's/^kit-row: //p' | head -1)"
    # A note written BEFORE the projection existed carries no kit-row line. Say that, rather than
    # printing an empty value that reads as "no row was declared".
    # ⚠️ AND COUNT IT SEPARATELY. Every note on this repo's main today predates the projection, so
    # a verdict that said "10/10 carry a recoverable board row" over ten `(not recorded)` lines
    # would be the overstatement this repo bans on sight. What such a commit has is a recoverable
    # GO; the ROW is not recoverable for it, and the summary says both numbers.
    if [ -z "$_trow" ]; then
      _trow="(not recorded — note predates the kit-row projection)"
      _tr_pre=$((${_tr_pre:-0} + 1))
    fi
    _tgate="$(printf '%s\n' "$_tn" | sed -n 's/^gate: //p' | head -1)"
    _tscope="$(printf '%s\n' "$_tn" | sed -n 's/^scope: //p' | head -1)"
    printf '%s  kit-row: %s  approved-sha: %s  gate: %s  scope: %s\n' \
      "$(printf '%s' "$_tc" | cut -c1-12)" "$_trow" "$(printf '%s' "$_ta" | cut -c1-12)" \
      "${_tgate:-(none)}" "${_tscope:-(none)}"
    return 0
  }

  if [ -n "$ref" ]; then
    trace_one "$ref"; return $?
  fi

  # --recent N: the RECORDLESS-MERGE leg. Walks the trunk and REDS if ANY commit in the window has
  # no recoverable row. `--from` exists for the fixture; production resolves origin/main, then main.
  if [ -z "$from" ]; then
    if git rev-parse -q --verify origin/main >/dev/null 2>&1; then from=origin/main
    elif git rev-parse -q --verify main >/dev/null 2>&1; then from=main
    else echo "trace: neither origin/main nor main resolves — pass --from <ref>" >&2; return 2; fi
  fi
  git rev-parse -q --verify "$from^{commit}" >/dev/null 2>&1 || {
    echo "trace: --from '$from' is not a commit in this repository" >&2; return 2; }
  _tr_rc=0; _tr_n=0; _tr_miss=0; _tr_pre=0
  # OLDEST-FIRST, AND THE ORDER IS LOAD-BEARING FOR THE DEDUP ABOVE. `git rev-list` yields
  # newest-first; walking that way would let the EMPTY commit (the newer one) claim the note and red
  # the genuine commit that produced the tree — naming the victim instead of the borrower. Reversed,
  # the first commit to produce a tree claims its note and any later commit that merely reproduces
  # that tree is the one that reds. (`tac`/`tail -r` are not portable; awk is.)
  for _tr_c in $(git rev-list -n "$recent" "$from" | awk '{a[NR]=$0} END{for(i=NR;i>0;i--) print a[i]}'); do
    _tr_n=$((_tr_n + 1))
    trace_one "$_tr_c" || { _tr_rc=1; _tr_miss=$((_tr_miss + 1)); }
  done
  # NON-VACUITY: an empty window is a FAIL, never a quiet pass. A green over zero commits would be
  # the exact shape this leg exists to prevent someone shipping.
  if [ "$_tr_n" -eq 0 ]; then
    echo "trace: walked ZERO commits from '$from' — a green over an empty window asserts nothing." >&2
    return 1
  fi
  if [ "$_tr_rc" = 0 ]; then
    echo "OK: trace — $_tr_n/$_tr_n of the last $recent commit(s) on $from are bound to a promotion note."
    echo "    of those, $((_tr_n - _tr_pre)) carry a projected board row; $_tr_pre predate the kit-row projection"
    echo "    (bound and recoverable, NOT verified-correct: this inherits the GO record's assurance exactly.)"
  else
    echo "FAIL: trace — $_tr_miss of $_tr_n commit(s) on $from have no recoverable board row (see above)." >&2
  fi
  return "$_tr_rc"
}

do_log() {
  if ! git rev-parse -q --verify "refs/notes/$NOTES_REF" >/dev/null 2>&1; then
    echo "# Promotion records (refs/notes/$NOTES_REF)"
    echo "(no promotion records yet — record one with: promotion-verify.sh record ...)"
    return 0
  fi
  echo "# Promotion records (refs/notes/$NOTES_REF) — projection of the notes trail"
  git notes --ref="$NOTES_REF" list 2>/dev/null | while read -r _n _obj; do
    [ -n "$_obj" ] || continue
    echo ""
    echo "## $_obj"
    git notes --ref="$NOTES_REF" show "$_obj" 2>/dev/null || true
  done
  return 0
}

do_check() {
  ref=""; asha=""
  while [ $# -gt 0 ]; do
    case "$1" in
      # SAME BUG SHAPE AS trace's (review L-3), fixed in the same breath rather than left as the
      # one surviving instance of a class this PR closed next door.
      --ref)          [ $# -ge 2 ] || { echo "check: --ref needs a value" >&2; return 2; }
                      ref="$2";  shift 2 ;;
      --approved-sha) [ $# -ge 2 ] || { echo "check: --approved-sha needs a value" >&2; return 2; }
                      asha="$2"; shift 2 ;;
      *) echo "check: unknown arg '$1'" >&2; usage; return 2 ;;
    esac
  done
  if [ -z "$ref" ]; then echo "check: --ref required" >&2; usage; return 2; fi
  if [ -z "$asha" ]; then
    asha="$(resolve_latest_sha || true)"
    if [ -z "$asha" ]; then
      echo "check: no --approved-sha given and no note to resolve from (refs/notes/$NOTES_REF)" >&2; return 2
    fi
  fi
  # Reject option-like values (Low finding): a --ref/--approved-sha beginning with '-' must never
  # be handed to git where it could be misparsed as a flag. Real refs/SHAs never start with '-'.
  case "$ref"  in -*) echo "check: invalid --ref '$ref' (must not start with '-')" >&2; return 2 ;; esac
  case "$asha" in -*) echo "check: invalid --approved-sha '$asha' (must not start with '-')" >&2; return 2 ;; esac

  # the approved-sha must resolve to a real object; capture its TREE (the content fingerprint).
  atree="$(git rev-parse -q --verify "${asha}^{tree}" 2>/dev/null || true)"
  if [ -z "$atree" ]; then
    echo "SHIPPED != APPROVED: approved-sha $asha is not a resolvable commit/tree in this repo" >&2; return 1
  fi
  if git rev-parse -q --verify "refs/tags/$ref" >/dev/null 2>&1; then
    # --- tag mode: the tag's TREE must EQUAL the approved TREE (exact content equality),
    #     plus a belt-and-suspenders VERSION match ---------------------------------------
    ttree="$(git rev-parse -q --verify "refs/tags/$ref^{tree}" 2>/dev/null || true)"
    if [ -z "$ttree" ] || [ "$ttree" != "$atree" ]; then
      echo "SHIPPED != APPROVED: tag '$ref' tree ($ttree) != approved-sha $asha tree ($atree)" >&2
      return 1
    fi
    tag_ver="$(git show "refs/tags/$ref:VERSION" 2>/dev/null || true)"
    app_ver="$(git show "${asha}:VERSION" 2>/dev/null || true)"
    if [ -z "$tag_ver" ] || [ "$tag_ver" != "$app_ver" ]; then
      echo "SHIPPED != APPROVED: tag '$ref' VERSION '$tag_ver' != approved VERSION '$app_ver'" >&2
      return 1
    fi
    echo "OK: shipped == approved — tag '$ref' tree equals approved $asha (VERSION $tag_ver)"
    return 0
  else
    # --- merged-ref mode: the shipped ref's TREE must EQUAL the approved TREE ------------
    rtree="$(git rev-parse -q --verify "${ref}^{tree}" 2>/dev/null || true)"
    if [ -z "$rtree" ]; then
      echo "check: ref '$ref' not found" >&2; return 2
    fi
    if [ "$rtree" != "$atree" ]; then
      echo "SHIPPED != APPROVED: merged ref '$ref' tree ($rtree) != approved-sha $asha tree ($atree)" >&2
      return 1
    fi
    echo "OK: shipped == approved — ref '$ref' tree equals approved $asha"
    return 0
  fi
}

# actuate --ref <pr|tag|merged-ref> --approved-sha <sha> [--merge-cmd "<cmd>"]
#   The CONTROL-PLANE actuation GATE. Fails CLOSED unless a recorded, authenticated, SHA-bound GO
#   exists AND the approver is a distinct party from the author, then performs a NORMAL (non-`--admin`)
#   merge via a swappable --merge-cmd and re-verifies shipped == approved. Never emits `--admin`:
#   approval authorizes PROMOTION, never a branch-protection BYPASS (the bypass is the human's solo
#   kill-switch, denied to the agent by guard-core.sh — see docs/governance/promotion-contract.md).
#
#   Fail-safe direction: ANY parse/lookup gap in steps 1-3 -> refuse before touching anything; a gap
#   in step 5 (post-merge) -> loud SHIPPED != APPROVED (an incident, not a warning).
#
#   HONEST CEILING (T1): the merge is a swappable stub in tests; the real `gh pr merge` (default) and
#   the forge-review -> [authenticated: <forge>-review] derivation (the vc-hosts seam) are UNWIRED
#   solo — a solo maintainer can never produce an [authenticated] label, so the gate stays closed and
#   `--admin` remains the human's only path, by construction. Steps 1-3 + 5 are fully fixture-proven.
do_actuate() {
  ref=""; asha=""; merge_cmd=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --ref)          ref="${2:-}";       shift 2 ;;
      --approved-sha) asha="${2:-}";      shift 2 ;;
      --merge-cmd)    merge_cmd="${2:-}"; shift 2 ;;
      *) echo "actuate: unknown arg '$1'" >&2; usage; return 2 ;;
    esac
  done
  if [ -z "$ref" ];  then echo "actuate: --ref required" >&2; usage; return 2; fi
  if [ -z "$asha" ]; then echo "actuate: --approved-sha required" >&2; usage; return 2; fi
  # Reject option-like values (as `check`/`record` do): a --ref/--approved-sha beginning with '-'
  # must never reach git where it could be misparsed as a flag. Real refs/SHAs never start with '-'.
  case "$ref"  in -*) echo "actuate: invalid --ref '$ref' (must not start with '-')" >&2; return 2 ;; esac
  case "$asha" in -*) echo "actuate: invalid --approved-sha '$asha' (must not start with '-')" >&2; return 2 ;; esac
  # Charset-validate (defense-in-depth): a real ref/tag/PR-number/SHA contains only [A-Za-z0-9._/-].
  # $ref is interpolated into the default merge_cmd eval below, so reject any metacharacter outright —
  # the gate must never be a shell-injection primitive even though the caller is already the agent.
  case "$ref"  in *[!A-Za-z0-9._/-]*) echo "actuate: invalid --ref '$ref' (allowed chars: A-Za-z0-9._/-)" >&2; return 2 ;; esac
  case "$asha" in *[!A-Za-z0-9._/-]*) echo "actuate: invalid --approved-sha '$asha' (allowed chars: A-Za-z0-9._/-)" >&2; return 2 ;; esac
  # Default merge = the sanctioned NORMAL squash merge (no branch-protection bypass flag is ever
  # emitted here; see the header comment). Swapped for a stub in tests.
  [ -n "$merge_cmd" ] || merge_cmd="gh pr merge \"$ref\" --squash"

  # 1. A GO note must bind EXACTLY this sha (git notes show fails closed on a bogus/unbound sha).
  note="$(git notes --ref="$NOTES_REF" show "$asha" 2>/dev/null || true)"
  if [ -z "$note" ]; then
    echo "ACTUATE REFUSED: no recorded GO note on $asha" >&2; return 1
  fi

  # 2. Read the DERIVED label from the `approved-by:` line ONLY — extract the trailing [...] on that
  #    single line. NEVER substring-scan the note body: a --token/--basis/--scope value may legitimately
  #    contain bracket text (the S5a injection lesson). Require the authenticated-forge-review bar.
  aby_line="$(printf '%s\n' "$note" | grep '^approved-by:' | head -1 || true)"
  aby_rest="${aby_line#approved-by:}"
  aby_rest="$(printf '%s' "$aby_rest" | sed 's/^[[:space:]]*//')"
  label=""
  case "$aby_rest" in
    *'['*']') label="${aby_rest##*\[}"; label="${label%]}" ;;
  esac
  if ! printf '%s' "$label" | grep -Eq '^authenticated: [A-Za-z0-9_-]+-review$'; then
    echo "ACTUATE REFUSED: assurance '$label' does not meet the control-plane bar ([authenticated: <forge>-review] required)" >&2
    return 1
  fi

  # 3. approver != author (builder != ratifier — real SoD teeth). The approver id is the text BEFORE
  #    the trailing ' [label]'. Strip from the SAME last '[' the label read used (not a
  #    space-prefixed '[') so a hand-crafted 'Name[label]' (no space) can't leave the bracket
  #    suffix in aby_id and slip the SoD check. Compare to the approved commit's author name AND email.
  #    ESCAPE THE BRACKET. An unescaped `[` starts a bracket expression in POSIX pattern syntax:
  #    bash tolerates the unterminated form as a literal, but dash — which IS /bin/sh on ubuntu-latest
  #    — does not match at all and returns the WHOLE string, corrupting both this SoD read and the
  #    label read at :308. Same one-character fix as conformance/ceremony-binding.sh:216.
  aby_id="${aby_rest%\[*}"
  aby_id="$(printf '%s' "$aby_id" | sed 's/[[:space:]]*$//')"
  # An empty / whitespace-only approver id can never satisfy SoD (a fabricated or malformed note) —
  # refuse rather than pass the `!= author` comparison vacuously.
  if [ -z "$aby_id" ]; then
    echo "ACTUATE REFUSED: empty approver id (cannot satisfy builder != ratifier)" >&2; return 1
  fi
  a_name="$(git show -s --format='%an' "$asha" 2>/dev/null || true)"
  a_email="$(git show -s --format='%ae' "$asha" 2>/dev/null || true)"
  if [ "$aby_id" = "$a_name" ] || [ "$aby_id" = "$a_email" ]; then
    echo "ACTUATE REFUSED: approver equals author (builder != ratifier)" >&2; return 1
  fi

  # 4. Execute the (swappable) NORMAL merge. Non-zero -> loud failure, propagate the code.
  if eval "$merge_cmd"; then mrc=0; else mrc=$?; fi
  if [ "$mrc" -ne 0 ]; then
    echo "ACTUATE FAILED: merge command exited $mrc" >&2; return "$mrc"
  fi

  # 5. Verify shipped == approved post-merge (a mismatch is the loud SHIPPED != APPROVED, exit 1).
  #    HONEST CEILING (seam): step 5 resolves $ref as a git ref/tag (do_check does git rev-parse
  #    "$ref^{tree}"). The default --merge-cmd merges a PR by number; a bare PR number does NOT
  #    resolve to a tree here. So the caller MUST pass a resolvable merged ref/tag as --ref for the
  #    verification to hold; wiring the PR-number -> merge-commit-sha resolution is part of the
  #    forge-adapter seam (docs/adoption/vc-hosts.md), unexercised solo. The fixtures pass a real
  #    merged ref precisely because this is the contract the live team path must honour.
  if do_check --ref "$ref" --approved-sha "$asha"; then crc=0; else crc=$?; fi
  if [ "$crc" -ne 0 ]; then return "$crc"; fi

  # Honest success line: the note is RECORDED, not necessarily AUTHENTICATED — a git note is
  # self-authorable (the label bar is audit + defense-in-depth over it; the real solo control is
  # server-side branch protection + the human-only admin bypass). Do not imply the label authenticates.
  echo "OK: actuated $ref on recorded GO (approved-sha $asha) — shipped == approved"
  return 0
}

cmd="${1:-}"
[ $# -gt 0 ] && shift || true
case "$cmd" in
  record)  if do_record  "$@"; then rc=0; else rc=$?; fi ;;
  log)     if do_log     "$@"; then rc=0; else rc=$?; fi ;;
  trace)   if do_trace   "$@"; then rc=0; else rc=$?; fi ;;
  check)   if do_check   "$@"; then rc=0; else rc=$?; fi ;;
  actuate) if do_actuate "$@"; then rc=0; else rc=$?; fi ;;
  -h|--help) usage; rc=2 ;;
  *) usage; rc=2 ;;
esac
exit "$rc"
