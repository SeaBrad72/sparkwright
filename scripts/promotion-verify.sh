#!/bin/sh
# promotion-verify.sh — the approve->execute->log actuation integrity tool for NON-control-plane
# promotions (KW1 . D2; docs/governance/promotion-contract.md "Approve->execute->log").
#
# Three modes:
#   record  --approved-sha <sha> --approved-by <id> --gate <g> --rung <r> --class <c> \
#           --scope <pr> (--token "<explicit approval string>" | --token-file <path>) [--basis <text> (required with --gate design)]
#          The token is the owner's words VERBATIM, never re-spelled. `--token-file` (SWAS-724) reads them from
#          a file so they stay off the command line; it records the same note bytes as `--token`.
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
# Exit: 0 = ok . 1 = MISMATCH (loud: "SHIPPED != APPROVED") . 2 = usage/args . 5 = the checkout lease refused (`record`, `land` and `actuate`,
# only in a checkout that opted in with `kit.checkoutLease`: they need `--lease-token <sha>`; the check runs before the verb's own argument checks).
# 6 = `land --update-behind` asked the forge to update a behind head: update REQUESTED (202), NOT merged (nothing recorded; wait for CI on the new head, land again).
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
#     (forge PR/MR review -> [authenticated: <forge>-review]) IS WIRED, for GitHub, since PR 11:
#     `record` reads the PR's reviews and upgrades the label when a non-author, non-Bot APPROVED
#     review by the claimed approver is bound to the approved sha. Other forges remain the seam in
#     docs/adoption/vc-hosts.md; github is now that seam's reference adapter. THE UPGRADE DOES NOT
#     CHANGE THE CEILING ABOVE: the note is still self-authorable and the label is a DRIFT CONTROL at
#     the note's own trust tier — it records that the forge answered YES when asked, over the local
#     `gh` credential. What BINDS is still server-side branch protection + required review.
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
# `actuate` wires ORDINARY and SENSITIVE promotions: on a SHA-bound recorded GO it performs the merge.
# TEAM (the default): the GO must carry an authenticated non-author forge approval. SOLO (an explicit
# MERGE_RELATIONSHIP=solo declared on origin's default branch): the owner's named GO, bound to the sha, the
# tree and origin, is the control (pv_solo_go_ok). CONTROL-PLANE is not merged by `actuate` in either: it is
# REFUSED with a pointer at the exact `land` command (D-241014-1 item 6 closed the Tier-3 sitting).
# That refusal is a DRIFT CONTROL, not a boundary: the class is caller-recorded.
#
# POSIX sh; dash-clean (no `local`, no bashisms). Operates on the current working tree's git repo.
# The notes ref name is overridable with PROMOTION_NOTES_REF (default: promotions) for testing.
# SOLO-GO-BOUND (SWAS-901): in a solo-declared repository whose origin tip carries the installed .github/workflows/solo-go.yml, `actuate` and `land` first read
# the head's `solo-go-bound` check runs (gh api GETs), refuse a run that is not the base's own workflow, and re-run a red one (the one POST: actions/runs/<id>/rerun-failed-jobs) and wait for it.
# What it changes: `record` binds a GO record as a git NOTE under refs/notes/promotions (tree-invariant — the commit's tree/SHA is unchanged); `actuate` performs a real ordinary/sensitive PR merge (default `gh pr merge --squash --match-head-commit <sha>`, swappable via a vetted, pinned --merge-cmd) bound to the approved SHA, and points a control-plane note at `land`; `sync` reconciles a diverged local ledger with origin's by tree content and publishes it (fast-forward only, never rewriting a published note; it moves refs/notes/promotions and leaves a local refs/kit/promotions-presync-<UTC> backup when it drops local content); `log`, `check`, `trace`, `evidence` and `go-bound` are read-only.
# Guardrails: `check` asserts shipped==approved by TREE equality (exit 1 on MISMATCH); the approved-by assurance label is DERIVED from the commit's own evidence (never from input) — a note BINDS, it does not AUTHENTICATE. `actuate` fails CLOSED unless a SHA-bound GO exists on origin and the declared merge relationship's bar holds (team, the default: [authenticated: <forge>-review] and approver != author; solo, declared in .kit/dials.conf on origin's default branch: the named, sha- and tree-bound owner GO), rejects `$ref` metacharacters, NEVER emits `--admin`, and re-verifies shipped==approved after the merge. `record` derives `kit-row:` from the approved commit's own trailer (never a flag), records `(none)` rather than inventing one, and sanitises it with every other free-text field; `trace` matches a trunk commit to its note by TREE (never ancestry, which a squash breaks), reds on any recordless commit in a `--recent` window, and fails closed on an empty window. `sync` publishes only local-only notes that re-validate as exactly what `record` would write NOW (never a label it could not derive), never rewrites, forces or merges, refuses a note origin once held and removed (voids visible in origin's history). Operator-only by policy (the script does not detect CI or a subagent): never CI, never a subagent, except the read-only `trace` and `go-bound` (the solo-go-bound workflow runs `go-bound` from the base branch).
set -eu
# A `refs/replace/*` ref can make every object read (tree, blob, trailer, author) of an approved sha return a
# crafted commit; the metering gate reads the approved commit, so it must read the REAL object.
export GIT_NO_REPLACE_OBJECTS=1

# ROOT — same idiom as hooks/pre-push (`ROOT=$(git rev-parse --show-toplevel) || ROOT=.`), used by
# `land`'s A9 hygiene re-read (design §8) to locate conformance/backlog-lib.sh, .kit/tracker.conf,
# and scripts/tracker-read.sh regardless of the caller's cwd within the working tree, and (SWAS-944) by
# the design-basis legs 3 and 4, which read a repo-root-relative basis path from any subdirectory.
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=.

# SWAS-903: the gh-reaching verbs set their own trust store inside the macOS agent sandbox (scripts/gh-tls.sh; the probe runs once, at dispatch,
# below). A missing library means no probe: today's behaviour.
_pv_ghtls=$(dirname -- "$0")/gh-tls.sh
# shellcheck source=scripts/gh-tls.sh
if [ -f "$_pv_ghtls" ]; then . "$_pv_ghtls"; fi

NOTES_REF="${PROMOTION_NOTES_REF:-promotions}"
# VALIDATE THE REF NAME AT THE FRONT DOOR (security review SEC-M2). `PROMOTION_NOTES_REF` is a
# fixture affordance, but since RECORD-FETCHES-AND-PUSHES-LEDGER it also selects what gets FETCHED
# from and PUSHED to `origin` — so an unvalidated value now reaches a refspec, not just a local
# `git notes --ref`. A `/` would let it escape `refs/notes/`, a leading `.` is not a legal ref
# component, and glob/whitespace bytes have no business in a ref name at all. Fail closed, before
# any mode runs: nothing here is worth a partially-composed refspec.
case "$NOTES_REF" in
  ''|*[!A-Za-z0-9._-]*|.*)
    echo "promotion-verify: invalid PROMOTION_NOTES_REF '$NOTES_REF' (charset A-Za-z0-9._- ; no '/', no leading '.')" >&2
    exit 2 ;;
esac

# The SCRATCH ref the remote ledger is fetched into when we need to compare the two chains
# (divergence count, `log --unpushed`). It is a throwaway under refs/kit/, never the ledger itself,
# so fetching it FORCED is correct and cannot discard anything: the guard's force rule matches
# `push`, and nothing reads this ref between invocations.
#
# PID-SCOPED (security review SEC-M1): a fixed name is a shared mutable ref. Two concurrent
# invocations — the exact concurrency this slice exists to handle — would fetch into and delete each
# other's scratch, and the trap would delete a ref this process never created. `$$` makes the ref
# this process's own, and the trap deletes only that one.
NOTES_SCRATCH="refs/kit/notes-remote-$$"
# --no-deref (whole-branch fix round 1, B1): a SYMBOLIC ref planted at this name would otherwise be deleted
# THROUGH — `update-ref -d` follows a symref and removes its TARGET (the ledger itself; MEASURED, git 2.48.1).
_pv_drop_scratch() { git update-ref --no-deref -d "$NOTES_SCRATCH" >/dev/null 2>&1 || true; }
# _pv_ref_exists <full-ref> — 0 when ANY kind of ref (a dangling symbolic ref included) already has that name.
_pv_ref_exists() {
  git symbolic-ref -q "$1" >/dev/null 2>&1 && return 0
  git rev-parse -q --verify "$1" >/dev/null 2>&1 && return 0
  [ -n "$(git for-each-ref "$1" 2>/dev/null)" ]
}
# THE RECORD SPLITTER (SWAS-323): a note is a LIST of records. A record starts at a header line `record: promotion ` or
# `land: promotion ` (a `land:` record is of another type that no GO reader takes), and the blank lines
# between records are dropped, so each record's bytes are exactly what `record` composed. The note is DEFECTIVE, and holds NO
# record at all (a reader then binds nothing, fail closed), when its first line is not a header (D1), a non-blank line is not
# `key: value` (D2), or a key repeats inside one record (D3: other readers take `head -1`, a matcher greps every line, so a
# repeat would let them judge different values). Out = `bad` (1 when defective), `n` (record count, 0 when defective), `type`
# or `body` of record <k>. KEEP THE TWO IN STEP: conformance/ceremony-binding.sh carries this block byte for byte (cell P1).
# BEGIN kit_note_records
kit_note_records() {
  awk -v out="$1" -v k="${2:-0}" '
    function hdr(s) { return s ~ /^(record|land): promotion / }
    NF == 0 { next }
    { if (NR == 1 && !hdr($0)) bad = 1
      if (hdr($0)) { n++; typ[n] = $0; sub(/: .*/, "", typ[n]) } else if (n == 0) bad = 1
      if ($0 !~ /^[A-Za-z0-9_-]+:( |$)/) bad = 1
      else { key = $0; sub(/:.*/, "", key); if ((n, key) in seen) bad = 1; seen[n, key] = 1 }
      if (n > 0) bod[n] = bod[n] $0 "\n" }
    END { if (n > 64) bad = 1
          if (bad) n = 0
          if (out == "bad") print bad + 0; else if (out == "n") print n + 0
          else if (out == "type") print typ[k]; else if (out == "body") printf "%s", bod[k] }'
}
# END kit_note_records
# _pv_rec_field <record> <key> -> the first `<key>: ` value of a record (a record holds each key once).
_pv_rec_field() { printf '%s\n' "$1" | sed -n "s/^$2: //p" | head -1; }
# _pv_note_with <note> -> the note with the GO record keyed (scope, gate) = ($scope, $gate) replaced by $nbody, which goes last
# (a different key is kept beside it: SWAS-323). Every record of another type is kept. A note with no whole record (a defective
# one, which binds nothing) is replaced outright, as a re-record always did, and says so.
_pv_note_with() {
  _nw_out=""; _nw_kept=0; _nw_nl='
'
  _nw_n="$(printf '%s\n' "$1" | kit_note_records n)"; _nw_i=0
  if [ "$_nw_n" = 0 ] && [ -n "$(printf '%s' "$1" | tr -d '[:space:]')" ]; then
    echo "record: the note on $asha is not a well-formed list of records (it binds nothing); it is replaced by this record." >&2
  fi
  while [ "$_nw_i" -lt "$_nw_n" ]; do
    _nw_i=$((_nw_i + 1))
    _nw_rec="$(printf '%s\n' "$1" | kit_note_records body "$_nw_i")"
    _nw_t="$(printf '%s\n' "$1" | kit_note_records type "$_nw_i")"
    if [ "$_nw_t" = record ] \
       && [ "$(_pv_rec_field "$_nw_rec" scope)" = "$scope" ] && [ "$(_pv_rec_field "$_nw_rec" gate)" = "$gate" ]; then
      continue
    fi
    # SWAS-323b: a land record is keyed (scope, land), so a land record of the same scope is superseded by the one written with this GO.
    _nw_sc="$(_pv_rec_field "$_nw_rec" scope)"
    if [ "$_nw_t" = land ] && [ -n "${lbody:-}" ] && [ "$_nw_sc" = "$scope" ]; then
      continue
    fi
    _nw_out="$_nw_out$_nw_rec$_nw_nl$_nw_nl"; _nw_kept=$((_nw_kept + 1))
  done
  # the land record, when this GO carries one, counts toward the cap beside the GO record (SWAS-323b)
  if [ -n "${lbody:-}" ]; then _nw_kept=$((_nw_kept + 1)); fi
  # The splitter calls a note of more than 64 records DEFECTIVE, so writing a 65th would make the note bind nothing and the next record
  # would replace it outright. Refuse before the write, on the freshly synced note (R11).
  if [ $((_nw_kept + 1)) -gt 64 ]; then
    echo "record: the note on $asha already holds $_nw_kept other records and a note is capped at 64 records — refusing to record." >&2
    return 2
  fi
  if [ -n "${lbody:-}" ]; then printf '%s%s%s%s\n' "$_nw_out" "$nbody" "$_nw_nl$_nw_nl" "$lbody"; return 0; fi
  printf '%s%s\n' "$_nw_out" "$nbody"
}
# _pv_note_pick <note> <scope> <gate> -> prints the GO record keyed (scope, gate); rc 1 when the note holds none.
_pv_note_pick() {
  _np_n="$(printf '%s\n' "$1" | kit_note_records n)"; _np_i=0
  while [ "$_np_i" -lt "$_np_n" ]; do
    _np_i=$((_np_i + 1))
    [ "$(printf '%s\n' "$1" | kit_note_records type "$_np_i")" = record ] || continue
    _np_r="$(printf '%s\n' "$1" | kit_note_records body "$_np_i")"
    if [ "$(_pv_rec_field "$_np_r" scope)" = "$2" ] && [ "$(_pv_rec_field "$_np_r" gate)" = "$3" ]; then
      printf '%s\n' "$_np_r"; return 0
    fi
  done
  return 1
}
# _pv_land_go <note> <land record> -> prints the GO record a land record BINDS; rc 1 when it binds none (SWAS-323b). Bound means BOTH: the
# land record's go-record-sha256 is the sha256 of the bytes of a GO record live in this note (so a re-record of that GO leaves it dangling),
# and its landed-tree equals that GO record's approved-tree (serial land: landed-tree = approved-tree). `trace` indexes a land record only
# when this holds, because trace --recent is CI's recordless-merge backstop and landed-tree feeds it.
_pv_land_go() {
  _lg_h="$(_pv_rec_field "$2" go-record-sha256)"; _lg_t="$(_pv_rec_field "$2" landed-tree)"
  if [ -z "$_lg_h" ] || [ -z "$_lg_t" ]; then return 1; fi
  _lg_n="$(printf '%s\n' "$1" | kit_note_records n)"; _lg_i=0
  while [ "$_lg_i" -lt "$_lg_n" ]; do
    _lg_i=$((_lg_i + 1))
    [ "$(printf '%s\n' "$1" | kit_note_records type "$_lg_i")" = record ] || continue
    _lg_r="$(printf '%s\n' "$1" | kit_note_records body "$_lg_i")"
    _lg_s="$(printf '%s\n' "$_lg_r" | pv_sha256)" || return 1
    if [ "${#_lg_s}" != 64 ]; then return 1; fi   # no sha256 tool: nothing binds (fail closed)
    if [ "$_lg_s" = "$_lg_h" ] && [ "$(_pv_rec_field "$_lg_r" approved-tree)" = "$_lg_t" ]; then printf '%s\n' "$_lg_r"; return 0; fi
  done
  return 1
}
# _pv_note_pick_land <note> <scope> -> prints the land record of that scope; rc 1 when the note holds none.
_pv_note_pick_land() {
  _pl2_n="$(printf '%s\n' "$1" | kit_note_records n)"; _pl2_i=0
  while [ "$_pl2_i" -lt "$_pl2_n" ]; do
    _pl2_i=$((_pl2_i + 1))
    [ "$(printf '%s\n' "$1" | kit_note_records type "$_pl2_i")" = land ] || continue
    _pl2_r="$(printf '%s\n' "$1" | kit_note_records body "$_pl2_i")"
    if [ "$(_pv_rec_field "$_pl2_r" scope)" = "$2" ]; then printf '%s\n' "$_pl2_r"; return 0; fi
  done
  return 1
}
# _pv_scratch_free <mode> — the scratch ref must NOT pre-exist before anything is fetched into it: `fetch -f`
# writes THROUGH a symbolic ref (B1), so a pre-planted `refs/kit/notes-remote-<pid>` -> the ledger would be
# overwritten by the fetch. Refuse (rc 2) naming it; a stale leftover from a killed run that reused this pid
# refuses the same way (delete it, re-run). The EXIT/INT/TERM traps that drop the scratch ref are installed in
# the sync section below (the old scratch-only trap that stood here was superseded there, so it is gone).
_pv_scratch_free() {
  if _pv_ref_exists "$NOTES_SCRATCH"; then
    printf '%s\n' "$1: the scratch ref $NOTES_SCRATCH already exists (a stale leftover or a planted ref) — REFUSED before any fetch into it; nothing changed." >&2
    printf '%s\n' "        Inspect it (git for-each-ref $NOTES_SCRATCH), delete it if it is stale, then re-run." >&2
    return 2
  fi
  return 0
}

# _pv_sync_in — STEP 1 of the record transaction: make the local ledger CURRENT, or refuse.
#
# WHY A PROBE AND NOT THE FETCH'S rc (security vet H2, MEASURED): `git fetch` exits 128 BOTH when
# the remote has no such ref (the first record this repo ever makes) AND when the remote is
# unreachable (offline, bad URL, no origin) — same rc, same "fatal: couldn't find remote ref". The
# rc alone therefore cannot split "proceed, publish will create it" from "refuse, you are blind".
# `git ls-remote --exit-code` CAN: 0 = present, 2 = the remote answered and does not have it,
# anything else = the remote did not answer. Recording blind is exactly the race this transaction
# exists to end, so the unreachable case REFUSES rather than recording locally.
# Returns 0 = proceed, 2 = refuse (message already printed).
_pv_sync_none=0
_pv_sync_in() {
  _pv_sync_none=0
  if git ls-remote --exit-code origin "refs/notes/$NOTES_REF" >/dev/null 2>&1; then
    _si_probe=0
  else
    _si_probe=$?
  fi
  case "$_si_probe" in
    0) ;;
    2) _pv_sync_none=1
       # SWAS-944: the pre-leg call (argument `quiet`) runs before a design GO's legs 5 and 6 may still refuse, so it must not say "recording".
       [ "${1:-}" = quiet ] || echo "record: origin has no refs/notes/$NOTES_REF yet — recording the first entry; publish will create it." >&2
       return 0 ;;
    *) echo "record: cannot reach the ledger remote — 'git ls-remote origin refs/notes/$NOTES_REF' exited $_si_probe." >&2
       echo "        A record written against a ledger this process cannot read is the race this" >&2
       echo "        transaction exists to end, so recording offline is REFUSED. Fix the remote and" >&2
       echo "        re-run, or use --no-push for explicitly offline maintenance (it says UNPUBLISHED)." >&2
       return 2 ;;
  esac
  # NO leading '+': a forced refspec would silently DISCARD a local unpublished record, which is the
  # dangling-note failure this row forbids, merely moved earlier.
  # C1: EVERY fetch here carries `--refmap=` — a configured `remote.origin.fetch = +refs/notes/*:refs/notes/*` would
  # otherwise ALSO force-update the local ledger (git's opportunistic remote-tracking update) behind our back.
  if git fetch --refmap= --no-tags origin "refs/notes/$NOTES_REF:refs/notes/$NOTES_REF" >/dev/null 2>&1; then
    return 0
  fi
  # The fetch refused. Split "diverged" (the case with a real remedy) from everything else by
  # MEASURING the two chains against each other, locally — never by trusting the remote's answer.
  _pv_scratch_free record || return 2
  if ! git fetch --refmap= --no-tags -f origin "refs/notes/$NOTES_REF:$NOTES_SCRATCH" >/dev/null 2>&1; then
    echo "record: fetching refs/notes/$NOTES_REF from origin failed and the reason could not be" >&2
    echo "        determined (the ref is present but unfetchable). Refusing to record." >&2
    return 2
  fi
  _si_n="$(git rev-list "refs/notes/$NOTES_REF" ^"$NOTES_SCRATCH" --count 2>/dev/null || echo 0)"
  _pv_drop_scratch
  if [ "${_si_n:-0}" -gt 0 ] 2>/dev/null; then
    echo "record: ledger diverged: the local refs/notes/$NOTES_REF carries $_si_n record(s) the remote" >&2
    echo "        does not; reconcile with promotion-verify.sh sync (preview it with sync --dry-run);" >&2
    echo "        inspect them with promotion-verify.sh log --unpushed. Refusing to record." >&2
    return 2
  fi
  echo "record: refs/notes/$NOTES_REF could not be fast-forwarded from origin. Refusing to record." >&2
  return 2
}

# _pv_unwind <pre> <post> — STEP 4: put the ledger ref back exactly where this invocation found it.
# COMPARE-AND-SWAP (security vet H1): the OLD-VALUE operand is what makes this safe. If anything
# moved the ref since our write, git refuses (rc 128, "cannot lock ref") and the ref is left ALONE —
# so an unwind can only ever remove the exact commit this invocation created, never someone else's.
# That is what makes "a published record is never rewritten" a postcondition rather than a promise.
_pv_unwind() {
  if [ -n "$1" ]; then
    git update-ref "refs/notes/$NOTES_REF" "$1" "$2" >/dev/null 2>&1
  else
    git update-ref -d "refs/notes/$NOTES_REF" "$2" >/dev/null 2>&1
  fi
}

# ---- SWAS-944: `record --gate design` checks its basis BEFORE it writes (design 2026-11-18-record-input-at-write-944, rev 3 + errata E1/E2/E3).
# Mirrors the legs of conformance/ceremony-binding.sh that a record's own text decides (path safety, the design glob, a regular file, the
# touch check, and for the inherited form `<P>:<path>` the parent's design GO at P). CI stays the control: the parent pick (go-by, token
# quote, ambiguity), the legacy list, the parent's identity and blob identity with the graded head are left to the gate. Every refusal is
# rc 2 and writes no note. printf, never echo: a basis is operator text (dash's echo expands a backslash).
_pv_dl_say() { printf '%s\n' "$*" >&2; }
# _pv_dl_blob <commit> <path> -> 0 when the entry at that commit is a regular file (blob, 100644 or 100755); a missing path and a symlink are not.
_pv_dl_blob() {
  # from the repository's top level, as CI reads the basis (the path is relative to the root, not to the caller's directory)
  _db_e="$(git -C "$ROOT" ls-tree --full-tree "$1" -- "$2" 2>/dev/null | head -1)" || _db_e=""
  [ -n "$_db_e" ] || return 1
  _db_m="${_db_e%% *}"; _db_t="${_db_e#* }"; _db_t="${_db_t%% *}"
  [ "$_db_t" = blob ] || return 1
  case "$_db_m" in
    100644|100755) return 0 ;;
  esac
  return 1
}
# _pv_dl_hexprefix <written hex> <resolved 40-hex> — the gate's _hex_is_prefix: a branch or tag spelled like hex cannot stand in for a commit.
_pv_dl_hexprefix() {
  _hp_w="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$2" in
    "$_hp_w"*) return 0 ;;
  esac
  return 1
}
# _pv_dl_remedy — E1: print the ONE remedy that works for the ledger's state, when a design GO's parent is not in the local ledger under --no-push.
# E3: reads only (an ls-remote, then local object and ancestry tests; no fetch, no write). Local ledger absent, equal to origin's, or an ancestor of
# origin's tip that is present locally -> the single-ref fetch; origin's tip not local, or local ahead -> sync; unreadable -> both, labelled.
# Neither line carries a glob or a leading plus.
_pv_dl_remedy() {
  _rm_fetch="git fetch origin refs/notes/$NOTES_REF:refs/notes/$NOTES_REF"
  _rm_sync="sh scripts/promotion-verify.sh sync"
  _rm_loc="$(git rev-parse -q --verify "refs/notes/$NOTES_REF^{commit}" 2>/dev/null)" || _rm_loc=""
  _rm_state=unreadable
  # E3: no fetch, no write. An ls-remote of origin's tip, then local tests only.
  _rm_rc=0; _rm_out="$(GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code origin "refs/notes/$NOTES_REF" 2>/dev/null)" || _rm_rc=$?
  if [ "$_rm_rc" = 2 ]; then
    _rm_state=noorigin
  elif [ "$_rm_rc" = 0 ]; then
    _rm_tip="$(printf '%s\n' "$_rm_out" | awk -F'\t' -v r="refs/notes/$NOTES_REF" '$2 == r { print $1; exit }')"
    if [ -z "$_rm_tip" ]; then
      _rm_state=unreadable
    elif [ -z "$_rm_loc" ] || [ "$_rm_tip" = "$_rm_loc" ]; then
      _rm_state=fetch
    elif git cat-file -e "${_rm_tip}^{commit}" >/dev/null 2>&1; then
      # origin's tip is local: behind (fast-forward provable here) -> fetch; ahead or diverged -> sync
      if git merge-base --is-ancestor "$_rm_loc" "$_rm_tip" >/dev/null 2>&1; then _rm_state=fetch; else _rm_state=sync; fi
    else
      _rm_state=sync   # origin's tip is not local: behind or diverged, which a fetch-free read cannot tell apart
    fi
  fi
  case "$_rm_state" in
    fetch)
      _pv_dl_say "        fetch the ledger first:"
      _pv_dl_say "        $_rm_fetch" ;;
    sync)
      _pv_dl_say "        origin's ledger is not a plain fast-forward of yours here (it holds notes you lack, or yours holds notes it lacks), so a plain fetch could be refused; sync fetches, reconciles and publishes:"
      _pv_dl_say "        $_rm_sync" ;;
    noorigin)
      _pv_dl_say "        origin has no ledger yet: record the parent design GO first." ;;
    *)
      _pv_dl_say "        the ledger's state against origin could not be read; one of these applies:"
      _pv_dl_say "        if your local ledger is absent, behind or equal to origin's, fetch it:"
      _pv_dl_say "        $_rm_fetch"
      _pv_dl_say "        if your local ledger holds notes origin does not have, reconcile it:"
      _pv_dl_say "        $_rm_sync" ;;
  esac
}
# _pv_dl_nofetch <what> — the refusal for a parent GO that is not in the ledger this run can see.
_pv_dl_nofetch() {
  if [ "$nopush" = 1 ]; then
    _pv_dl_say "record: $1 in the local ledger, NOT FETCHED (--no-push fetches and writes nothing; one ls-remote reads origin's tip to choose the remedy). Fetch the ledger, or run without --no-push. Nothing was written."
    _pv_dl_remedy
  elif [ "$_pv_sync_none" = 1 ]; then
    _pv_dl_say "record: origin has no ledger yet, so no parent design GO at $_dl_ip is published ($1). Nothing was written."
  else
    _pv_dl_say "record: $1. Nothing was written."
  fi
}
# _pv_dl_scan <note> <path> — sorts a note's design records: sets _ds_same / _ds_other (accepted, under this scope / another: the bare basis equals
# the path, or the basis is the legacy `(none recorded)`), _ds_hop (inherited-form basis), _ds_names (any other basis).
_pv_dl_scan() {
  _ds_same=0; _ds_other=0; _ds_hop=0; _ds_names=""
  _ds_n="$(printf '%s\n' "$1" | kit_note_records n)"; _ds_i=0
  while [ "$_ds_i" -lt "$_ds_n" ]; do
    _ds_i=$((_ds_i + 1))
    [ "$(printf '%s\n' "$1" | kit_note_records type "$_ds_i")" = record ] || continue
    _ds_r="$(printf '%s\n' "$1" | kit_note_records body "$_ds_i")"
    [ "$(_pv_rec_field "$_ds_r" gate)" = design ] || continue
    _ds_b="$(_pv_rec_field "$_ds_r" basis)"
    if printf '%s\n' "$_ds_b" | grep -Eq '^[0-9a-fA-F]{7,40}:'; then _ds_hop=$((_ds_hop + 1)); continue; fi
    if [ "$_ds_b" = "$2" ] || [ "$_ds_b" = "(none recorded)" ]; then
      if [ "$(_pv_rec_field "$_ds_r" scope)" = "$scope" ]; then _ds_same=$((_ds_same + 1)); else _ds_other=$((_ds_other + 1)); fi
    else
      _ds_names="${_ds_names:+$_ds_names, }'$_ds_b'"
    fi
  done
}
# _pv_dl_inherited — legs 3i, 5 and 6 for `<P>:<path>` (globals: _dl_ip, _dl_path, _dl_a40). rc 2 = refused.
_pv_dl_inherited() {
  _dl_p40="$(git rev-parse -q --verify "${_dl_ip}^{commit}" 2>/dev/null)" || _dl_p40=""
  if [ -z "$_dl_p40" ]; then
    _pv_dl_say "record: the GO'd commit $_dl_ip is not in this clone: the branch that carries it must stay on origin (D-240819-4); restore it, or write a confirming design (skills/design). Nothing was written."
    return 2
  fi
  if ! _pv_dl_hexprefix "$_dl_ip" "$_dl_p40"; then
    _pv_dl_say "record: the written hex $_dl_ip is not a prefix of the commit it resolves to ($_dl_p40): a branch or tag spelled like hex cannot stand in for a commit id. Nothing was written."
    return 2
  fi
  # leg 3i: the design is the GO'd blob AT P (the gate's _ip_blob_identity), not at the approved commit.
  if ! _pv_dl_blob "$_dl_p40" "$_dl_path"; then
    _pv_dl_say "record: the basis '$_dl_path' is not a regular file at $_dl_ip (missing, a symlink or a directory): the inherited form quotes the design as it stood at P. Nothing was written."
    return 2
  fi
  _dl_pn="$(git notes --ref="$NOTES_REF" show "$_dl_p40" 2>/dev/null)" || _dl_pn=""
  _pv_dl_scan "$_dl_pn" "$_dl_path"
  if [ "$_dl_p40" = "$_dl_a40" ]; then
    # leg 5, P = the approved commit: only a stacked child (a parent GO under another scope) is the gate's accepted shape.
    if [ "$_ds_other" -gt 0 ]; then return 0; fi
    if [ "$_ds_same" -gt 0 ]; then
      _pv_dl_say "record: the parent design GO at $_dl_ip is under this same scope, so recording this GO would replace the design GO it quotes. Nothing was written."
      return 2
    fi
    if [ -z "$_dl_pn" ] && [ "$nopush" = 1 ]; then
      _pv_dl_nofetch "no design GO record at $_dl_ip (it names '$_dl_path')"; return 2
    fi
    _pv_dl_say "record: the inherited form quotes an earlier design GO at $_dl_ip; for the design you are approving now, use --basis $_dl_path, or approve a later commit on this branch. Nothing was written."
    return 2
  fi
  # leg 6: a design GO at P names the path.
  if [ "$((_ds_same + _ds_other))" -gt 0 ]; then return 0; fi
  if [ -z "$_dl_pn" ]; then
    _pv_dl_nofetch "no design GO record at $_dl_ip (it names '$_dl_path')"; return 2
  fi
  if [ "$_ds_hop" -gt 0 ]; then
    _pv_dl_say "record: the only design record(s) at $_dl_ip are themselves in the inherited form: one hop only, a child cannot name another child as its parent. Nothing was written."
    return 2
  fi
  if [ -n "$_ds_names" ]; then
    _pv_dl_say "record: the design record(s) at $_dl_ip name $_ds_names, not '$_dl_path'. Nothing was written."
    return 2
  fi
  _pv_dl_nofetch "no design GO record at $_dl_ip names '$_dl_path'"
  return 2
}
# _pv_dl_errata_go <design-sibling> — E2 condition 2: the ledger already holds a `gate: design` record with this scope and kit-row whose basis is
# the sibling design path, bare or inherited. Scans every note (the design GO sits on an earlier commit). rc 2 = refused.
_pv_dl_errata_go() {
  for _eg_a in $(git notes --ref="$NOTES_REF" list 2>/dev/null | awk '{print $2}'); do
    _eg_note="$(git notes --ref="$NOTES_REF" show "$_eg_a" 2>/dev/null)" || continue
    # skip a note that cannot hold a record of this scope before splitting it (the splitter is awk per record)
    printf '%s\n' "$_eg_note" | grep -qxF "scope: $scope" || continue
    _eg_n="$(printf '%s\n' "$_eg_note" | kit_note_records n)"; _eg_i=0
    while [ "$_eg_i" -lt "$_eg_n" ]; do
      _eg_i=$((_eg_i + 1))
      [ "$(printf '%s\n' "$_eg_note" | kit_note_records type "$_eg_i")" = record ] || continue
      _eg_r="$(printf '%s\n' "$_eg_note" | kit_note_records body "$_eg_i")"
      [ "$(_pv_rec_field "$_eg_r" gate)" = design ] || continue
      [ "$(_pv_rec_field "$_eg_r" scope)" = "$scope" ] || continue
      [ "$(_pv_rec_field "$_eg_r" kit-row)" = "$kitrow" ] || continue
      _eg_b="$(_pv_rec_field "$_eg_r" basis)"
      if printf '%s\n' "$_eg_b" | grep -Eq '^[0-9a-fA-F]{7,40}:'; then _eg_b="${_eg_b#*:}"; fi
      if [ "$_eg_b" = "$1" ]; then return 0; fi
    done
  done
  if [ "$nopush" = 1 ]; then
    _pv_dl_say "record: an errata GO needs its design GO first (scope $scope): none naming '$1' is in the local ledger, NOT FETCHED (--no-push fetches and writes nothing; one ls-remote reads origin's tip to choose the remedy). Nothing was written."
    _pv_dl_remedy
  else
    _pv_dl_say "record: an errata GO needs its design GO first (scope $scope): the ledger holds no design GO with this scope and kit-row naming '$1'. Nothing was written."
  fi
  return 2
}
# _pv_design_legs — the legs of design §2b for `--gate design`, in the order of §2a. Reads do_record's asha, basis, scope, kitrow, nopush.
_pv_design_legs() {
  # leg 0: --approved-sha is a hex object name (the gate's own test), and the hex is a prefix of what it resolves to.
  case "$asha" in
    ''|*[!0123456789abcdefABCDEF]*) _dl_bad=1 ;;
    *) _dl_bad=0 ;;
  esac
  if [ "$_dl_bad" = 1 ] || [ "${#asha}" -lt 7 ] || [ "${#asha}" -gt 40 ]; then
    _pv_dl_say "record: a design GO's --approved-sha must be a hex object name of 7-40 characters (not HEAD, a branch name or another revision expression): ceremony-binding refuses anything else. Got: $asha. Nothing was written."
    return 2
  fi
  _dl_a40="$(git rev-parse -q --verify "${asha}^{commit}" 2>/dev/null)" || _dl_a40=""
  if [ -z "$_dl_a40" ] || ! _pv_dl_hexprefix "$asha" "$_dl_a40"; then
    _pv_dl_say "record: --approved-sha $asha is not a hex object name of a commit (a branch or tag spelled like hex does not count). Nothing was written."
    return 2
  fi
  _dl_inh=0; _dl_ip=""; _dl_path="$basis"
  if printf '%s\n' "$basis" | grep -Eq '^[0-9a-fA-F]{7,40}:'; then _dl_inh=1; _dl_ip="${basis%%:*}"; _dl_path="${basis#*:}"; fi
  # leg 1: path safety, before git reads the path (the gate's pattern).
  case "$_dl_path" in
    /*|*..*)
      _pv_dl_say "record: refusing a basis path that is absolute or contains '..': $_dl_path. Nothing was written."
      return 2 ;;
  esac
  # leg 2: the design glob, read and guarded exactly as the gate does.
  CB_DESIGN_GLOB="${CB_DESIGN_GLOB:-docs/architecture/*-design.md}"
  case "$CB_DESIGN_GLOB" in
    ''|'*'|'**'|'*'*'*'|'?*')
      _pv_dl_say "record: CB_DESIGN_GLOB must not match every path — that disables the design-artifact constraint entirely. Narrow it to your design-document convention. Nothing was written."
      return 2 ;;
  esac
  _dl_errata=0; _dl_sib=""
  # shellcheck disable=SC2254 # UNQUOTED ON PURPOSE: CB_DESIGN_GLOB is a glob pattern (the gate matches it the same way).
  case "$_dl_path" in
    $CB_DESIGN_GLOB) : ;;
    *)
      # E2: an errata file of a design is accepted beside that design's GO (bare form only; conditions 1-3 below).
      case "$_dl_path" in
        docs/architecture/*-errata.md) _dl_sib="${_dl_path%-errata.md}-design.md" ;;
        docs/architecture/*-errata-*.md)
          _dl_en="${_dl_path%.md}"; _dl_en="${_dl_en##*-errata-}"
          case "$_dl_en" in
            ''|*[!0-9]*) _dl_sib="" ;;
            *) _dl_sib="${_dl_path%-errata-"$_dl_en".md}-design.md" ;;
          esac ;;
      esac
      if [ -z "$_dl_sib" ]; then
        _pv_dl_say "record: the basis '$_dl_path' is not a design artifact: expected $CB_DESIGN_GLOB (e.g. docs/architecture/2026-07-26-my-slice-design.md). A GO naming an arbitrary tracked file is not a recorded DESIGN decision. Nothing was written."
        return 2
      fi
      if [ "$_dl_inh" = 1 ]; then
        _pv_dl_say "record: an errata GO names its errata file as a bare path (--basis $_dl_path); the inherited form <P>:<path> is never accepted for an errata basis. Nothing was written."
        return 2
      fi
      if ! _pv_dl_blob "$_dl_a40" "$_dl_sib"; then
        _pv_dl_say "record: '$_dl_path' looks like an errata file, but its design '$_dl_sib' is not a tracked file at the approved commit, so the errata cannot be tied to its own design. Nothing was written."
        return 2
      fi
      _dl_errata=1 ;;
  esac
  # leg 3 (bare): a regular file at the approved commit. The inherited form checks it at P (leg 3i, in _pv_dl_inherited).
  if [ "$_dl_inh" = 0 ] && ! _pv_dl_blob "$_dl_a40" "$_dl_path"; then
    _pv_dl_say "record: the basis '$_dl_path' is not a regular file at the approved commit $_dl_a40 (missing, a symlink or a directory). Nothing was written."
    return 2
  fi
  # leg 4 (bare): the approved commit touches the path, compared as full ids.
  if [ "$_dl_inh" = 0 ]; then
    _dl_last="$(GIT_LITERAL_PATHSPECS=1 git -C "$ROOT" rev-list -1 "$_dl_a40" -- "$_dl_path" 2>/dev/null)" || _dl_last=""
    if [ "$_dl_last" != "$_dl_a40" ]; then
      _pv_dl_say "record: the approved commit $_dl_a40 does not touch '$_dl_path' (last touched by ${_dl_last:-no commit in its history}); approve that commit, or use the inherited form <P>:$_dl_path to quote an earlier design GO. Nothing was written."
      return 2
    fi
  fi
  [ "$_dl_inh" = 1 ] || [ "$_dl_errata" = 1 ] || return 0
  # the pre-leg fetch: before leg 5 (and E2's condition 2), after the symbolic-ledger refusal; `quiet` drops the "recording the first entry" line.
  if [ "$nopush" = 0 ]; then _pv_sync_in quiet || return 2; fi
  if [ "$_dl_inh" = 1 ]; then _pv_dl_inherited || return 2; return 0; fi
  _pv_dl_errata_go "$_dl_sib" || return 2
  return 0
}

usage() {
  echo "usage:" >&2
  echo "  promotion-verify.sh record --approved-sha <sha> --approved-by <id> --gate <g> \\" >&2
  echo "                             --rung <r> --class <c> --scope <pr> (--token <str> | --token-file <path>) [--basis <t> (required with --gate design)]" >&2
  echo "                             [--go-by <name>] [--no-push]" >&2
  echo "        a design GO is checked before it is written (a hex --approved-sha; the basis a design file the approved commit touches):" >&2
  echo "          --gate design --basis docs/architecture/<date>-<slice>-design.md                 (the design you are approving now)" >&2
  echo "          --gate design --basis <P>:docs/architecture/<date>-<slice>-design.md             (inherited: quotes the design GO already recorded at an earlier commit P)" >&2
  echo "        record is a TRANSACTION: it fetches refs/notes/<ref> from origin first, refuses if" >&2
  echo "        the local ledger has diverged, writes the note, PUBLISHES it, and unwinds its own" >&2
  echo "        unpublished note if the push is rejected (retrying once on a non-fast-forward)." >&2
  echo "        --no-push skips BOTH the fetch and the publish (fixtures / explicitly offline" >&2
  echo "                  maintenance); its OK line ends UNPUBLISHED." >&2
  echo "        --scope takes a PR id (CI's key) or branch/<name> (the pre-push key, ruling D11)" >&2
  echo "        WHICH IDENTITY GOES WHERE (each field wants a DIFFERENT person's name):" >&2
  echo "        --approved-by  the forge LOGIN of the PR reviewer, verbatim (e.g. 'octocat', not a display" >&2
  echo "                      name): the [authenticated: <forge>-review] upgrade requires a BYTE-EQUAL match" >&2
  echo "                      to the review's user.login, from a NON-author whose APPROVED review is on the" >&2
  echo "                      approved sha; anything else records a weaker label and says why on stderr." >&2
  echo "                      For a DESIGN GO (--gate design, no PR yet) it is the design commit's COMMITTER" >&2
  echo "                      name or email: a design GO binds to the committer ([committer] is only as strong" >&2
  echo "                      as user.name, and hollow when the agent commits under the owner's identity)." >&2
  echo "        --go-by       the person who GAVE the GO, by name (usually the owner, who is NOT the forge" >&2
  echo "                      reviewer). Recorded '[self-asserted]' BY DESIGN: the kit authenticates only the" >&2
  echo "                      forge review. Omitted -> 'go-by: (none recorded)'. REQUIRED by land (control-plane)." >&2
  echo "        --token       their words, verbatim (the owner's own GO sentence), never re-spelled." >&2
  echo "        --token-file  the same words read from a file instead (instead of --token, never with it): one line," >&2
  echo "                      1..4096 raw bytes (the trailing newline counts), a regular file (no symlink) under the repo root or \$TMPDIR (default /tmp) with no dot" >&2
  echo "                      component, no secret shape. Use it when the words must stay off the command line." >&2
  echo "        --class must be one of: ordinary | sensitive | control-plane (case-insensitive)" >&2
  echo "        --gate must be one of: design | plan | governance | merge | release-candidate (case-insensitive; stored lowercase)" >&2
  echo "        --rung must be one of: spike | integration | rc | staging | production (case-insensitive; stored lowercase)" >&2
  echo "          --gate design --rung integration   (a design GO; --basis names the design)" >&2
  echo "          --gate plan --rung integration     (a plan-presentation record)" >&2
  echo "          --gate governance --rung integration   (a meta-control panel's GO)" >&2
  echo "          --gate merge --rung integration    (a PR's merge GO)" >&2
  echo "          --gate release-candidate --rung rc (a release-candidate go/no-go)" >&2
  echo "  promotion-verify.sh log [--unpushed]" >&2
  echo "        --unpushed lists only the records the remote ledger does not have; it fails CLOSED" >&2
  echo "                   (UNKNOWN, rc 2) when the remote cannot be read — never a silent '0'." >&2
  echo "  promotion-verify.sh sync [--dry-run] [--discard-local <sha>]..." >&2
  echo "        reconcile a DIVERGED local ledger with origin's by tree content: origin-only notes are" >&2
  echo "        kept, same-commit twins whose identity agrees take origin's bytes, and a note origin" >&2
  echo "        once held and removed is refused (voided). --dry-run prints WOULD lines, writes nothing." >&2
  echo "        sync is a TRANSACTION: it fetches origin's ledger, classifies by tree content, re-validates" >&2
  echo "        every local-only note as exactly what record would write NOW (gate and rung as shape only, SWAS-948; the label is re-derived," >&2
  echo "        never trusted), builds the result on origin's tip, backs up the old local tip (only when" >&2
  echo "        it drops local content) at refs/kit/promotions-presync-<UTC>, swaps, PUBLISHES, and" >&2
  echo "        unwinds if the push is rejected (retrying once on a non-fast-forward)." >&2
  echo "        It NEVER rewrites a published note, forces, merges, publishes a label record could not" >&2
  echo "        derive now, or deletes the ledger. --discard-local <sha> (repeatable; lowercase 40-hex, or a unique" >&2
  echo "        prefix of a note in the ledger) drops ONLY that local note in favour of origin's; the backup ref keeps it." >&2
  echo "        Exit 0 = reconciled (or nothing to do); 2 = refused or unreachable, nothing dangling, except two rare" >&2
  echo "        paths reported loudly: the push was rejected and the ledger moved under the run (not unwound; backup" >&2
  echo "        kept), or POSTCONDITION FAILED after a push (state unknown; inspect with log --unpushed). A signal" >&2
  echo "        exits 130/143." >&2
  echo "        Operator-only by policy (the script does not detect CI or a subagent): never CI, never a subagent (D-240805-3)." >&2
  echo "  promotion-verify.sh trace --ref <sha> | --recent <n> [--from <trunk-ref>]" >&2
  echo "        recover the board row for a commit that already landed (squash loses the trailer)" >&2
  echo "        --recent also runs a DETECTIVE evidence leg (SWAS-537): with a forge credential, a trunk commit merged without a completed light-or-full CI run on its approved head prints a FLAG line and is counted (the exit code is unchanged); the FIRST failed forge read turns it off with ONE 'evidence leg: UNVERIFIED' line, a later failed read is that commit's own UNVERIFIED line (summary PARTIAL); outside the kit pipeline it prints one N/A line." >&2
  echo "  promotion-verify.sh evidence --pr <n> --approved-sha <sha>" >&2
  echo "        READ-ONLY: would land find exact-head CI evidence for that head now? Exit 0 yes, 1 refused (the token and the wait are printed), 2 usage." >&2
  echo "  promotion-verify.sh go-bound --approved-sha <40-hex> --pr <n> --base-ref <name> --default-branch <name>" >&2
  echo "        READ-ONLY (SWAS-901; the solo-go-bound workflow runs it from the checked-out BASE branch): prints exactly ONE line, go-bound: na|ok|missing|error [reason]." >&2
  echo "        na = the base reads team; ok = one merge-gate GO record scoped to this PR binds exactly this head; missing = none does; error = it could not be judged." >&2
  echo "        Exit 0 for na, ok and missing; 2 for error. It reads the note from the LOCAL notes ref (it never fetches) and writes no ref, no note and no file." >&2
  echo "  promotion-verify.sh check  --ref <merged-ref|tag> [--approved-sha <sha>]" >&2
  echo "  promotion-verify.sh actuate --ref <head-branch> --approved-sha <sha> [--merge-cmd \"<cmd>\"]" >&2
  echo "        --ref is the PR's head branch, fetched, and must equal <sha> (refused before any merge otherwise); a" >&2
  echo "        caller --merge-cmd is vetted like land's and must pin --match-head-commit <sha>; the GO note is read from" >&2
  echo "        origin. The real shipped == approved check on the trunk is promotion-verify.sh trace --recent (the kit's CI runs it on every pull request; on GitHub the trunk-trace job in adopter-trunk-trace.yml runs it on every push to your default branch, reporting only until you set TRUNK_TRACE_MODE: enforce; on another host, run it on your trunk yourself)." >&2
  echo "  promotion-verify.sh land --ref <pr|tag|merged-ref> --merge-cmd \"<cmd>\" \\" >&2
  echo "                           --approved-sha <sha> --approved-by <id> --gate <g> --rung <r> \\" >&2
  echo "                           --class <c> --scope <s> --token <str> --go-by <the GO-giver> [--basis <t>]" >&2
  echo "        --gate: design | plan | governance | merge | release-candidate; --rung: spike | integration | rc | staging | production" >&2
  echo "        (case-insensitive, folded to lowercase before anything is read; a land GO is usually --gate merge --rung integration)." >&2
  echo "        land (control-plane) merges ONLY on an AUTHENTICATED NON-AUTHOR forge approval: --approved-by is" >&2
  echo "        the forge login of a non-author reviewer whose APPROVED review is on <sha> (checked BEFORE the" >&2
  echo "        record, so a refusal writes no note, and again from the note on origin BEFORE the merge); the" >&2
  echo "        owner who gave the GO goes in --go-by, recorded [self-asserted]. --scope must be the PR id (a" >&2
  echo "        branch/<name> scope has no reviews to read, so land refuses it). SOLO-DECLARED (MERGE_RELATIONSHIP=solo" >&2
  echo "        in .kit/dials.conf on the default branch): no second approver is needed — land judges the solo bar" >&2
  echo "        (a named --go-by, the tree, a non-design/plan gate) on the note read back from origin. An UNDECLARED" >&2
  echo "        one-account repo reads team: land refuses; record the GO with 'record' and the HUMAN merges (admin" >&2
  echo "        merge is the human's act, never the agent's). docs/adoption/vc-hosts.md explains declaring solo." >&2
  echo "        GO_ACT (.kit/dials.conf on origin's default branch; team mode only; design and plan GOs stay typed): absent = the two acts" >&2
  echo "        above, exactly. separate = the same plus --go-by must differ from --approved-by (land and actuate). review = an APPROVED" >&2
  echo "        forge review on the exact head by a GO_GIVERS login IS the GO: land takes NO --token and NO --go-by, records go-act: review," >&2
  echo "        go-by = approved-by, token forge-review:<id>, and takes any class; actuate refuses and points here. An approval that carries" >&2
  echo "        a comment is HELD (rc 2, the words printed): release it with --token and --go-by together (recorded go-act: separate)." >&2
  echo "        land is ONE transactional verb for the direct/control-plane path: it RECORDS the GO" >&2
  echo "        (record's own args + transaction), CONFIRMS the note reached origin, then MERGES then" >&2
  echo "        leaves the branch INTACT. If the record does not complete or the note is not on" >&2
  echo "        origin, land does NOT merge. --no-push is REFUSED (a landing merge must publish the" >&2
  echo "        GO so it reaches origin — landing on a local-only note would reopen #658). Default" >&2
  echo "        merge: gh pr merge <ref> --squash --match-head-commit <sha> — NEVER --admin, NEVER --delete-branch." >&2
  echo "        land also writes a LAND record beside the GO (one transaction) and refuses a head that origin's default branch is not an" >&2
  echo "        ancestor of (serial land; it assumes the PR targets that branch). Exit 3 = the merge HAPPENED but origin's new tip carries a" >&2
  echo "        tree that is not the landed tree (SHIPPED != APPROVED): never read 3 as 'refused, nothing merged'." >&2
  echo "        --update-behind (land only, never passed to record): on a head that origin's default branch is not an ancestor of, ask the forge to" >&2
  echo "        update the PR branch (pinned to the head land was given: the approved head where a forge approval is read; under a solo relationship, the --approved-sha given), then exit 6 = update REQUESTED (202), NOT merged and nothing recorded: wait for CI on the new head and land again." >&2
  echo "        A merge head must be a plain update from main (two parents, the second on origin's default branch, merge-tree's tree) or land refuses it (rc 1)." >&2
  echo "        Verb-scoped: land refuses a recordless merge on its OWN path; the universal net for a" >&2
  echo "        recordless merge is the recordless-merge backstop (promotion-verify.sh trace --recent: the kit's CI runs it; on GitHub an adopter's trunk-trace job in adopter-trunk-trace.yml runs it on each push to the default branch, observe by default; on another host, run it on your trunk yourself)." >&2
  echo "  BOARD TAIL (land AND actuate): after the merge both verbs release the row's claim and, on a JIRA" >&2
  echo "        backend, close its card (\`board.sh release <ROW> --stale\`: card -> Done). On every run that MERGED" >&2
  echo "        the LAST line of stdout is exactly one of (a stable contract; read this line, not the exit code):" >&2
  echo "          board: row closes with the PR (md); claim released" >&2
  echo "          board: row closes with the PR (md); claim NOT released — see the WARN above" >&2
  echo "          board: row closes with the PR (md); no claim to release   (md, the note has no kit-row)" >&2
  echo "          board: closed                                        (jira: card Done; proven by post-read when a" >&2
  echo "                                                                claim ref was held, else the output says so)" >&2
  echo "          board: NOT CLOSED — see the WARN above               (merge done; the WARN names the one command;" >&2
  echo "                                                                also any other tracker: no write adapter)" >&2
  echo "        rc stays 0 on all of them: the merge succeeded and no rc can undo it. A forge-UI merge moves no card:" >&2
  echo "        run \`sh scripts/board.sh release <ROW> --stale\` by hand." >&2
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
  _g="$(git show -s --no-show-signature --format='%G?' "$_sha" 2>/dev/null || echo N)"
  case "$_g" in
    G|U) echo "signed: gpg"; return 0 ;;
  esac
  _cn="$(git show -s --no-show-signature --format='%cn' "$_sha" 2>/dev/null || echo '')"
  _ce="$(git show -s --no-show-signature --format='%ce' "$_sha" 2>/dev/null || echo '')"
  if [ -n "$_id" ] && { [ "$_id" = "$_cn" ] || [ "$_id" = "$_ce" ]; }; then
    echo "committer"; return 0
  fi
  echo "self-asserted"
}

# ── THE FORGE-REVIEW DERIVATION (ACTUATE-FORGE-REVIEW-DERIVATION-UNWIRED, PR 11) ──────────────────
#
# WHY IT EXISTS. Until this slice derive_assurance could emit only [signed: gpg] / [committer] /
# [self-asserted], and `actuate` hard-requires [authenticated: <forge>-review]. Nothing anywhere
# produced that label, so `actuate` was closed for EVERY class by construction and the kit's Tier-2
# promise — the agent merges ordinary/sensitive PRs on a recorded GO — did not hold through this tool.
# MEASURED TWICE on this repo: #582 (the boarding) and #605, where a real APPROVED review sat on the
# exact head and `record` never looked, recording [committer].
#
# WHAT IT DOES, AND WHAT IT DELIBERATELY DOES NOT. It CORROBORATES the caller's claim against forge
# evidence — the same philosophy as [committer], where the id EQUALS a git-attested field and so earns
# a stronger label. It NEVER substitutes an identity: the recorded id stays the already-sanitised
# caller string, and the label is a FIXED LITERAL. NO BYTE OF API OUTPUT IS EVER WRITTEN INTO THE
# NOTE, so this opens no new injection surface into a line-structured body (the S5a class stays closed
# by construction, not by escaping). ONE EXCEPTION, ADDED BY SWAS-727 AND ONLY IN REVIEW MODE: the review id, accepted only as
# 1-20 digits, and the review body, which is made safe (control characters out, quotes escaped, capped) before it is kept.
#
# FAIL DIRECTION. It can only ever UPGRADE. Any gap — no PR scope, no gh, an API error, no qualifying
# review, an unresolvable author — keeps the git-native label and prints a notice naming the reason
# from a FIXED ENUMERATION (no API byte in the notice either). It never blocks and never fails a
# record: a governance record must not become unwritable because a network call did.
#
# HONEST CEILING. This authenticates against the forge's ANSWER AT RECORD TIME, over the local `gh`
# binary and its ambient credential — an agent that controls PATH can feed it fabricated reviews. That
# is no NEW capability (the note was already self-authorable), and the label's tier is stated plainly:
# a DRIFT CONTROL at the note's own trust tier. The control that BINDS remains server-side branch
# protection + required review. It also proves only that a qualifying review existed WHEN ASKED —
# a later dismissal is not re-checked here (the forge re-judges at merge time; layered, not doubled).
#
# REVIEW MODE (SWAS-727, GO_ACT=review): a fifth argument, the GO_GIVERS list, widens the read for `land` only. The same
# fixed-literal label comes back, and the call ALSO has to find the reviewer on that list, a digits-only review id, and the
# review's body (read through `gh --jq` into a variable and kept as DATA: it never reaches a label, a token or a shell). Those
# three come back in globals (a caller that wants them calls this function WITHOUT a command substitution, redirecting stdout to
# a file, because a substitution would drop them): PV_FR_WHY (the last fallback reason, empty on success), PV_FR_ID, PV_FR_BODY
# and PV_FR_HELD (1 when the body holds anything but whitespace: the approval carries a comment, so it is not a one-act GO).
# SWAS-747: a review of any posted state (not a PENDING draft) by a GO_GIVERS login, other than the chosen approval, that is not provably BEFORE the chosen approval holds it too (words or line comments;
# a read that fails, or an id that is not digits, holds). PV_FR_OWN is 1 when the approval itself holds, PV_FR_LATER the digits-only ids of
# the later rows that held on their words or line comments, PV_FR_LATERERR the ones held because a read failed (an id, `bad` for an id that is not digits, `scan` for a failed scan); PV_FR_BODY is then the approval's body and each
# holding later body, joined by one line feed.
PV_FR_WHY=""; PV_FR_ID=""; PV_FR_BODY=""; PV_FR_HELD=0; PV_FR_OWN=0; PV_FR_LATER=""; PV_FR_LATERERR=""

# _fr_fallback <reason> <label> — print the fixed-enumeration notice, echo the unchanged label.
_fr_fallback() {
  PV_FR_WHY="$1"
  echo "forge-review derivation: $1 — recording [$2]" >&2
  printf '%s\n' "$2"
}

# _fr_body_read <pr number> <review id> — one review's body, raw, into _fb_body: the sentinel x keeps trailing newlines, gh's own
# final newline is removed once. rc 1 = the read failed, or came back without gh's final newline.
_fr_body_read() {
  if ! _fb_body="$(gh api "repos/{owner}/{repo}/pulls/$1/reviews/$2" --jq '.body // ""' 2>/dev/null && printf x)"; then return 1; fi
  _fb_body="${_fb_body%x}"
  _fb_nl='
'
  # gh always ends the answer with ONE newline, even for an empty body; an answer with none is no answer, and an unread body must
  # never read as an empty one (that would turn a held approval into a one-act GO).
  case "$_fb_body" in
    *"$_fb_nl") _fb_body="${_fb_body%"$_fb_nl"}" ;;
    *) return 1 ;;
  esac
}

# _fr_later_ids <rows> <approval id> <givers> — one token per row, of any posted state (not a PENDING draft) and other than the chosen
# approval itself, by a GO_GIVERS login (folded) that is NOT provably before the approval: `D<digits>` for a row whose id is digits, else `X`; plus one `DUP` when the approval's id is on two rows. Provably before = earlier in the list AND both rows carry a well-formed
# submitted_at with the row's strictly earlier (the fixed shape makes string order the time order); any other case counts as later.
# The id and the givers go in through the ENVIRONMENT, never `awk -v`. These rows never choose or cancel an approval (that is
# the awk in forge_review_upgrade); this only decides whether the chosen one is held. A second giver's APPROVED, CHANGES_REQUESTED or
# DISMISSED row holds on its words like a COMMENTED one (SWAS-756); an empty one holds nothing.
_fr_later_ids() {
  printf '%s\n' "$1" | FR_ID="$2" FR_GIV="$3" LC_ALL=C awk -F'\t' '
    function stamp(t) { return t ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/ }
    { n++; st[n] = $1; lg[n] = tolower($3); id[n] = $5; tm[n] = $6; if (("" $5) == ("" ENVIRON["FR_ID"])) { ap = n; at = $6; hits++ } }
    END {
      if (hits > 1) print "DUP"
      k = split(tolower(ENVIRON["FR_GIV"]), gv, " "); for (j = 1; j <= k; j++) on[gv[j]] = 1
      for (i = 1; i <= n; i++) {
        if (st[i] == "PENDING" || i == ap) continue
        if (!on[lg[i]]) continue
        if (i < ap && stamp(tm[i]) && stamp(at) && ("" tm[i]) < ("" at)) continue
        print (id[i] ~ /^[0-9]+$/ ? "D" id[i] : "X")
      }
    }'
}

# _fr_later_holds <pr number> <review id> — does one later comment row hold the approval? rc 0 = it holds on its words (the body in
# _lh_body) or its line comments; rc 1 = it does not (an empty review); rc 2 = it holds because a read failed.
_fr_later_holds() {
  _lh_body=""
  if ! _fr_body_read "$1" "$2"; then return 2; fi
  if [ -n "$(printf '%s' "$_fb_body" | LC_ALL=C tr -d '[:space:]')" ]; then _lh_body="$_fb_body"; return 0; fi
  # A lone line comment is filed as a COMMENTED review with an empty body and one comment (a review's own line comments likewise): any count but 0 holds.
  if ! _lh_c="$(gh api "repos/{owner}/{repo}/pulls/$1/reviews/$2/comments" --jq 'length' 2>/dev/null)"; then return 2; fi
  [ "$_lh_c" = 0 ] || return 0
  return 1
}

# _fr_later_scan <pr number> <approval id> <givers> <rows> — read every later comment row; each one that holds sets PV_FR_HELD and is
# recorded in PV_FR_LATER (+ PV_FR_LATERERR when unread) and its words joined to PV_FR_BODY. An id that is not 1-20 digits holds.
_fr_later_scan() {
  _ls_nl='
'
  # A failed scan is a hold, never a one-act GO: the rows could not be read for later comments.
  if ! _ls_late="$(_fr_later_ids "$4" "$2" "$3")"; then PV_FR_HELD=1; PV_FR_LATERERR="${PV_FR_LATERERR:+$PV_FR_LATERERR }scan"; return 0; fi
  for _ls_t in $_ls_late; do
    _ls_id="${_ls_t#D}"; _lh_body=""; _ls_kind=bad
    case "$_ls_t" in
      D[0-9]*) if [ "${#_ls_id}" -gt 20 ]; then _ls_id="?"; fi ;;
      DUP) _ls_id="?"; _ls_kind=dup ;;
      *) _ls_id="?" ;;
    esac
    _ls_rc=2
    if [ "$_ls_id" != "?" ]; then _ls_rc=0; _fr_later_holds "$1" "$_ls_id" || _ls_rc=$?; fi
    if [ "$_ls_rc" = 1 ]; then continue; fi
    PV_FR_HELD=1
    if [ "$_ls_rc" = 2 ]; then PV_FR_LATERERR="${PV_FR_LATERERR:+$PV_FR_LATERERR }$(if [ "$_ls_id" = "?" ]; then echo "$_ls_kind"; else echo "$_ls_id"; fi)"
    else PV_FR_LATER="${PV_FR_LATER:+$PV_FR_LATER }$_ls_id"; fi
    if [ -z "$_lh_body" ]; then continue; fi
    # non-empty parts only: an approval body of whitespace is cleared before the words are joined to it
    if [ -z "$(printf '%s' "$PV_FR_BODY" | LC_ALL=C tr -d '[:space:]')" ]; then PV_FR_BODY=""; fi
    PV_FR_BODY="${PV_FR_BODY:+$PV_FR_BODY$_ls_nl}$_lh_body"
  done
}

# _fr_review_go <row> <folded login> <pr number> <givers> <fallback label> <rows> — review mode's extra conditions, after every
# check above has passed. rc 0 = all hold (PV_FR_* set); rc 1 = a fallback was printed (label already on stdout).
_fr_review_go() {
  _rg_row="$1"; _rg_login="$2"; _rg_n="$3"; _rg_giv="$4"; _rg_lab="$5"; _rg_rows="$6"; _rg_ok=1
  for _rg_g in $_rg_giv; do
    if [ "$(printf '%s' "$_rg_g" | LC_ALL=C tr 'A-Z' 'a-z')" = "$_rg_login" ]; then _rg_ok=0; fi
  done
  if [ "$_rg_ok" != 0 ]; then _fr_fallback giver-not-listed "$_rg_lab"; return 1; fi
  # The review id is the only new value taken from the API: accepted only as 1-20 digits, else it is not an id.
  _rg_id="$(printf '%s' "$_rg_row" | cut -f5)"
  case "$_rg_id" in
    ''|*[!0-9]*) _fr_fallback review-id-invalid "$_rg_lab"; return 1 ;;
  esac
  if [ "${#_rg_id}" -gt 20 ]; then _fr_fallback review-id-invalid "$_rg_lab"; return 1; fi
  # The body, raw. A failed read is a fallback.
  if ! _fr_body_read "$_rg_n" "$_rg_id"; then _fr_fallback api-error "$_rg_lab"; return 1; fi
  _rg_b="$_fb_body"
  PV_FR_ID="$_rg_id"; PV_FR_BODY="$_rg_b"
  if [ -n "$(printf '%s' "$_rg_b" | LC_ALL=C tr -d '[:space:]')" ]; then PV_FR_HELD=1; fi
  # LINE COMMENTS hold the approval too: they are the review's comments on the diff, and may hold a condition as a body does. The
  # count is read as DATA (digits only); a failed or unparsable read is a HOLD, never a one-act GO (an unread comment is not "none").
  if _rg_c="$(gh api "repos/{owner}/{repo}/pulls/$_rg_n/reviews/$_rg_id/comments" --jq 'length' 2>/dev/null)"; then
    if [ "$_rg_c" != 0 ]; then PV_FR_HELD=1; fi
  else
    PV_FR_HELD=1
  fi
  PV_FR_OWN="$PV_FR_HELD"
  _fr_later_scan "$_rg_n" "$_rg_id" "$_rg_giv" "$_rg_rows"
  return 0
}

# forge_review_upgrade <scope> <approved-sha> <approved-by> <fallback-label> [<go-givers>] -> the label to record.
forge_review_upgrade() {
  _fr_scope="$1"; _fr_sha="$2"; _fr_by="$3"; _fr_lab="$4"; _fr_givers="${5:-}"; _fr_n=""
  PV_FR_WHY=""; PV_FR_ID=""; PV_FR_BODY=""; PV_FR_HELD=0; PV_FR_OWN=0; PV_FR_LATER=""; PV_FR_LATERERR=""
  # 1. TRIGGER — a PR number, DIGITS-ANCHORED. The number is interpolated into an API path, so the
  #    remainder after a recognised prefix must be ALL digits or the scope is simply not a PR scope.
  #    `branch/<name>` skips outright: the design-GO path binds BEFORE a PR exists and must not be
  #    perturbed. Anything that is not exactly one of these four shapes is `no-pr-scope`, never a
  #    best-effort digit scrape — scraping `release-v3.220.0` down to `3` would probe a REAL, unrelated
  #    PR 3 and judge this record against someone else's reviews.
  case "$_fr_scope" in
    branch/*) _fr_n="" ;;
    'PR #'*)  _fr_n="${_fr_scope#PR #}" ;;
    'PR-'*)   _fr_n="${_fr_scope#PR-}" ;;
    '#'*)     _fr_n="${_fr_scope#\#}" ;;
    *)        _fr_n="$_fr_scope" ;;
  esac
  case "$_fr_n" in
    ''|*[!0-9]*) _fr_n="" ;;
  esac
  [ -n "$_fr_n" ] || { _fr_fallback no-pr-scope "$_fr_lab"; return 0; }
  command -v gh >/dev/null 2>&1 || { _fr_fallback gh-unavailable "$_fr_lab"; return 0; }
  # 2. RESOLVE THE APPROVED SHA IN FULL before comparing. 27 of this repo's own records carry an
  #    ABBREVIATED sha; comparing the raw caller string against the API's 40-hex commit_id would make
  #    every one of them silently never-upgrade — a permanent false negative wearing a green.
  _fr_full="$(git rev-parse -q --verify "${_fr_sha}^{commit}" 2>/dev/null || true)"
  [ -n "$_fr_full" ] || { _fr_fallback sha-unresolvable "$_fr_lab"; return 0; }
  # 3. PROBE. `gh api` (REST) is the transport, MEASURED at build time against both candidates: it is
  #    the only one that exposes `user.type` (the Bot belt below), and it exposes `commit_id`, `state`
  #    and `user.login` in submission order. `gh pr view --json reviews` DOES also carry the commit
  #    binding (as `commit.oid` — the design's assumption that it did not was re-measured and is
  #    false), but it carries no account type, so it cannot serve the belt.
  #    EXTRACTION IS STRUCTURAL (`--jq`), never a substring grep of raw JSON: a grep for APPROVED
  #    matches inside a review BODY, which is attacker-supplied prose. `@tsv` also escapes any tab or
  #    newline a hostile login carries, so one review is always one line here.
  #    Under `set -eu` the substitution is guarded so a probe failure FALLS BACK rather than aborting.
  #    ⚠️ NO TIMEOUT IS SET, AND THAT IS A REAL LIMIT, NOT AN OVERSIGHT (security review F4). A gh call
  #    that FAILS falls back within milliseconds; a gh call that HANGS stalls `record` for as long as
  #    the network does, and the operator sees a wedged command rather than a notice. There is no
  #    portable POSIX timeout (`timeout(1)` is GNU/coreutils, absent on stock macOS), so wrapping this
  #    would trade a rare hang for a new portability failure on the commonest developer platform. The
  #    fail-SAFE direction is preserved either way — a hang never produces a wrong label, only no label.
  if _fr_rows="$(gh api "repos/{owner}/{repo}/pulls/$_fr_n/reviews" --paginate \
        --jq '.[]|[(.state//""),(.commit_id//""),(.user.login//""),(.user.type//""),((.id//"")|tostring),(.submitted_at//"")]|@tsv' 2>/dev/null)"; then
    :
  else
    _fr_fallback api-error "$_fr_lab"; return 0
  fi
  # 4. LATEST REVIEW PER REVIEWER, not any match over the history. An APPROVED that the same reviewer
  #    later replaced with CHANGES_REQUESTED is still in the list and always will be; an any-match read
  #    would authenticate on a WITHDRAWN approval. Take the LAST row for this login (REST returns
  #    submission order) and judge only that one. The login is passed through the ENVIRONMENT, never
  #    `awk -v` (which would interpret backslash escapes in the value) and never interpolated.
  #    ⚠️ ONLY STATE-CHANGING REVIEWS ARE CONSIDERED (review I2, and this is GitHub's OWN semantics,
  #    not a convenience). A review row may be APPROVED, CHANGES_REQUESTED, DISMISSED, COMMENTED or
  #    PENDING. Only the first three change a PR's review STATE; a COMMENTED review is a note, and it
  #    is what a reviewer leaves when they answer a question AFTER approving. Taking the plain latest
  #    row would let that comment silently cancel a standing approval — the derivation would refuse a
  #    GO the forge itself still considers approved, and the operator would have no idea why. So
  #    COMMENTED and PENDING rows are filtered out BEFORE the latest-per-reviewer selection, and the
  #    withdrawal semantics REC-N7 pins (APPROVED then CHANGES_REQUESTED) are untouched: those are
  #    state-changing and still win by recency.
  _fr_row="$(printf '%s\n' "$_fr_rows" \
      | FR_WHO="$_fr_by" LC_ALL=C awk -F'\t' \
          '$3 == ENVIRON["FR_WHO"] && ($1 == "APPROVED" || $1 == "CHANGES_REQUESTED" || $1 == "DISMISSED") { last = $0 } END { if (last != "") print last }')"
  [ -n "$_fr_row" ] || { _fr_fallback reviewer-not-in-reviews "$_fr_lab"; return 0; }
  _fr_state="$(printf '%s' "$_fr_row" | cut -f1)"
  _fr_cid="$(printf '%s' "$_fr_row" | cut -f2)"
  _fr_login="$(printf '%s' "$_fr_row" | cut -f3)"
  _fr_type="$(printf '%s' "$_fr_row" | cut -f4)"
  # 5. EXACT state. Not a prefix, not a `case` glob, not a substring: DISMISSED is the forge saying an
  #    approval no longer counts, and a loose matcher reads it as an approval.
  [ "$_fr_state" = "APPROVED" ] || { _fr_fallback review-not-approved "$_fr_lab"; return 0; }
  # 6. Bound to THIS content (resolved, full). A review of an earlier commit is not a review of this one.
  [ "$_fr_cid" = "$_fr_full" ] || { _fr_fallback review-sha-mismatch "$_fr_lab"; return 0; }
  # 7. The reviewer IS the id this GO claims — byte-equal, narrow and fail-closed. (Redundant with the
  #    awk select above, kept because a corroboration gate should not depend on one selector's shape.)
  [ "$_fr_login" = "$_fr_by" ] || { _fr_fallback reviewer-not-in-reviews "$_fr_lab"; return 0; }
  # 8. Bot belt. A `…[bot]` App login is already unusable as --approved-by (brackets are rejected at
  #    :222-226 — that rejection does double duty, do not "fix" it later); this covers a machine
  #    identity whose login carries none. A machine USER account with a plain login stays
  #    indistinguishable from a human: an honest ceiling, not a mechanism.
  [ "$_fr_type" != "Bot" ] || { _fr_fallback reviewer-is-bot "$_fr_lab"; return 0; }
  # 9. FORGE-SIDE SoD: the reviewer is not the PR's author. CASE-INSENSITIVE rejection, because forge
  #    logins are case-insensitive and a capital letter must not buy a self-approval; BROAD and
  #    fail-closed, the opposite direction from the byte-equal acceptance above.
  #    AND THE AUTHOR MUST RESOLVE. An empty author would make the inequality VACUOUSLY TRUE and hand
  #    out the strongest label the kit has on the strength of a FAILED LOOKUP — the same empty-operand
  #    refusal both verbs now make for the commit author in pv_sod_author_check.
  if _fr_author="$(gh api "repos/{owner}/{repo}/pulls/$_fr_n" --jq '.user.login // ""' 2>/dev/null)"; then
    :
  else
    _fr_fallback api-error "$_fr_lab"; return 0
  fi
  [ -n "$_fr_author" ] || { _fr_fallback author-unresolvable "$_fr_lab"; return 0; }
  # CHARSET-ANCHOR THE AUTHOR BEFORE COMPARING (security review F3). A GitHub login is
  # [A-Za-z0-9-] and nothing else. This value is the ONLY API-derived string that decides an upgrade
  # by INEQUALITY, and an inequality is satisfied by anything unexpected — so a malformed, truncated
  # or surprising answer would read as "different from the reviewer" and PASS the SoD test. Requiring
  # the shape first converts that whole class from a silent pass into a stated refusal.
  # ⚠️ DISCLOSED CONSEQUENCE, deliberately accepted: an App-opened PR has an author login of the form
  # `dependabot[bot]`, whose brackets are outside this charset — so a review on a bot-opened PR will
  # never upgrade and will say `author-unresolvable`. That is the fail-CLOSED direction (no label is
  # weaker than a wrong label), and it is stated here rather than discovered.
  case "$_fr_author" in
    *[!A-Za-z0-9-]*) _fr_fallback author-unresolvable "$_fr_lab"; return 0 ;;
  esac
  _fr_l1="$(printf '%s' "$_fr_login"  | LC_ALL=C tr 'A-Z' 'a-z')"
  _fr_l2="$(printf '%s' "$_fr_author" | LC_ALL=C tr 'A-Z' 'a-z')"
  [ "$_fr_l1" != "$_fr_l2" ] || { _fr_fallback reviewer-is-pr-author "$_fr_lab"; return 0; }
  # 10. REVIEW MODE only (SWAS-727): the reviewer is on GO_GIVERS, the review id is digits, the body is read. Every check above
  #     is the one a team-mode read already makes; these are what a one-act GO adds (SWAS-747: and a later GO-giver comment holds). A fallback ends the call here.
  if [ -n "$_fr_givers" ]; then _fr_review_go "$_fr_row" "$_fr_l1" "$_fr_n" "$_fr_givers" "$_fr_lab" "$_fr_rows" || return 0; fi
  # THE LABEL IS A FIXED LITERAL — assembled from nothing the API said.
  printf '%s\n' "authenticated: github-review"
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

# Shared front-door predicates: `record` composes with them and `sync` RE-VALIDATES with them (V5, V6),
# so what one accepts the other accepts by construction (design I6).
# _pv_class_ok <class> — record's change-class vocabulary (case-insensitive).
_pv_class_ok() {
  case "$(printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z')" in
    ordinary|sensitive|control-plane) return 0 ;;
  esac
  return 1
}
# SWAS-948: record's and land's gate and rung vocabularies (NOT shared with sync, which keeps reading legacy
# notes). Case-insensitive, no trimming; on success print the LOWERCASE list spelling and return 0.
# _pv_gate_ok <gate> — design | plan | governance | merge | release-candidate.
_pv_gate_ok() {
  case "$1" in
    ''|*[!A-Za-z-]*) return 1 ;;
  esac
  _pv_vf="$(printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z')"
  case "$_pv_vf" in
    design|plan|governance|merge|release-candidate)
      printf '%s\n' "$_pv_vf"
      return 0 ;;
  esac
  return 1
}
# _pv_rung_ok <rung> — spike | integration | rc | staging | production.
_pv_rung_ok() {
  case "$1" in
    ''|*[!A-Za-z-]*) return 1 ;;
  esac
  _pv_vf="$(printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z')"
  case "$_pv_vf" in
    spike|integration|rc|staging|production)
      printf '%s\n' "$_pv_vf"
      return 0 ;;
  esac
  return 1
}
# _pv_vocab_refuse <cmd> <flag> <value> — the refusal text for an unlisted --gate/--rung, on stderr.
_pv_vocab_refuse() {
  _pv_shown="$(printf '%s' "$3" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-40)"
  if [ "$2" = gate ]; then
    echo "$1: invalid --gate '$_pv_shown' — must be one of: design · plan · governance · merge · release-candidate (case-insensitive)" >&2
  else
    echo "$1: invalid --rung '$_pv_shown' — must be one of: spike · integration · rc · staging · production (case-insensitive)" >&2
  fi
  echo "        --gate design --rung integration   (a design GO; --basis names the design)" >&2
  echo "        --gate plan --rung integration     (a plan-presentation record)" >&2
  echo "        --gate governance --rung integration   (a meta-control panel's GO)" >&2
  echo "        --gate merge --rung integration    (a PR's merge GO)" >&2
  echo "        --gate release-candidate --rung rc (a release-candidate go/no-go)" >&2
}
# _pv_scope_shape <scope> — 0 ok · 1 `branch/` names no branch · 2 a charset the gate cannot express.
# Non-`branch/` scopes keep the hygiene they already had (see do_record's D11 note).
_pv_scope_shape() {
  case "$1" in
    branch/) return 1 ;;
    branch/*)
      case "${1#branch/}" in
        *[!A-Za-z0-9_.:/-]*) return 2 ;;
      esac ;;
  esac
  return 0
}
# _pv_placeholder_span <value> — SWAS-902. rc 0 and the last matched span on stdout (cut to 40 bytes) when the value holds template text
# in angle brackets: `<`, one character that is not a space, digit, `=`, `<`, `>` or `-`, a run without `<`, `>` or `@`, then `>`.
# rc 1 when it does not. An ERE under LC_ALL=C, NOT a case glob (a glob cannot exclude `@` in a run, so it would refuse
# `Name <email>`). The span is pulled out with sed, not `grep -o` (which differs across GNU, BSD and ugrep). Shared by `record`
# and `sync`, so what one refuses the other refuses.
_pv_placeholder_span() {
  printf '%s' "$1" | LC_ALL=C grep -Eq '<[^[:space:]0-9=<>-][^<>@]*>' || return 1
  printf '%s' "$1" | LC_ALL=C sed -n 's/^.*\(<[^[:space:]0-9=<>-][^<>@]*>\).*$/\1/p' | LC_ALL=C cut -c1-40
  return 0
}
# _pv_placeholder_msg <verb> <field> <span> [file] — SWAS-902. The refusal text, to stderr; the caller returns rc 2. A token sends the owner's
# words back to the owner (the kit never re-spells a token); every other field says to write the value without the brackets. With a 4th
# argument `file` (a token read from --token-file) no span is echoed: a refusal never prints a byte of the file.
_pv_placeholder_msg() {
  # printf, never echo: the span is operator text (dash's echo expands a backslash)
  if [ "$2" = token ]; then
    if [ "${4:-}" = file ]; then
      echo "$1: --token-file holds text in angle brackets, which reads as an unfilled template." >&2
    else
      printf '%s\n' "$1: --token (or --token-file) holds text in angle brackets ('$3'), which reads as an unfilled template." >&2
    fi
    echo "        Copied a template? Put the real value in its place." >&2
    echo "        The owner's own words? Ask the owner to give the GO again without '<' and '>';" >&2
    echo "        never edit their words yourself. Nothing was written." >&2
    return 0
  fi
  printf '%s\n' "$1: --$2 holds text in angle brackets ('$3'), which reads as an unfilled template." >&2
  echo "        Copied a template? Put the real value in its place." >&2
  echo "        Write the value without '<' and '>'. Nothing was written." >&2
}

# pv_token_file_load <path> — SWAS-724. Reads the owner's GO words from a file into $token, or refuses (rc 2,
# ONE fixed sentence, no byte of the file or its path echoed). The rules are board.sh's file-form rules,
# rewritten here without its trap (board.sh is not a library, and its loader's `trap - EXIT INT TERM` would
# wipe this script's own traps). A speed bump, as board's is: the re-check after the read narrows the
# check-then-read window, it does not close it. The window covers EVERY path component, not only the file (a
# directory swapped for a symlink after the check is not seen), and a swap of the file to a FIFO between the
# check and the read can hang `head`. Containment and the dot rule are checks on the path as it was, not a lock.
_pv_tf_under() {   # <physical-path> <root>: under the root, no dot component below it; `/` is never a root
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
_pv_tf_contained() {   # <physical-path>: under the repo root or under ${TMPDIR:-/tmp}, both resolved physically
  _tc_root=$(CDPATH='' cd -- "$ROOT" 2>/dev/null && pwd -P) || _tc_root=""
  case "${TMPDIR:-}" in
    /*) _tc_t=$TMPDIR ;;
    *) _tc_t=/tmp ;;
  esac
  _tc_tmp=$(CDPATH='' cd -- "$_tc_t" 2>/dev/null && pwd -P) || _tc_tmp=""
  if [ -n "$_tc_root" ] && _pv_tf_under "$1" "$_tc_root"; then return 0; fi
  if [ -n "$_tc_tmp" ] && _pv_tf_under "$1" "$_tc_tmp"; then return 0; fi
  return 1
}
_pv_tf_secret() {   # <text>: 0 when it holds a private-key header or a well-known token shape (board.sh's list)
  printf '%s\n' "$1" | LC_ALL=C grep -Eq \
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
pv_token_file_load() {
  _tf_pre="record: --token-file"
  _tf_p=$1
  [ -n "$_tf_p" ] && [ "$(printf '%s' "$_tf_p" | LC_ALL=C tr -cd '\040-\176' | wc -c | tr -d ' ')" = "$(printf '%s' "$_tf_p" | wc -c | tr -d ' ')" ] \
    || { echo "$_tf_pre needs a path of printable ASCII characters (no newline or control byte)." >&2; return 2; }
  _tf_dir=$(CDPATH='' cd -- "$(dirname -- "$_tf_p")" 2>/dev/null && pwd -P) \
    || { echo "$_tf_pre must be a readable regular file." >&2; return 2; }
  _tf_phys="$_tf_dir/$(basename -- "$_tf_p")"
  if [ -L "$_tf_phys" ]; then echo "$_tf_pre must not be a symlink." >&2; return 2; fi
  { [ -f "$_tf_phys" ] && [ -r "$_tf_phys" ]; } || { echo "$_tf_pre must be a readable regular file." >&2; return 2; }
  _pv_tf_contained "$_tf_phys" \
    || { echo "$_tf_pre must sit under the repo root or \$TMPDIR, and no path component below that may start with a dot." >&2; return 2; }
  # ONE read, verbatim: the sentinel x keeps every trailing newline (the trim below removes exactly one), and the
  # tr maps a NUL to \001 because command substitution drops NUL silently (the control check refuses \001).
  _tf_v=$(head -c 4097 -- "$_tf_phys" 2>/dev/null | LC_ALL=C tr '\000' '\001'; printf x)
  _tf_v=${_tf_v%x}
  if [ -L "$_tf_phys" ] || [ ! -f "$_tf_phys" ]; then echo "$_tf_pre must be a readable regular file." >&2; return 2; fi
  _tf_n=$(printf '%s' "$_tf_v" | wc -c | tr -d ' ')
  { [ "$_tf_n" -ge 1 ] && [ "$_tf_n" -le 4096 ]; } || { echo "$_tf_pre must be 1..4096 bytes." >&2; return 2; }
  _tf_nl=$(printf '\nx'); _tf_nl=${_tf_nl%x}
  _tf_v=${_tf_v%"$_tf_nl"}
  case "$_tf_v" in
    *"$_tf_nl"*) echo "$_tf_pre must hold exactly one line." >&2; return 2 ;;
  esac
  if [ "$(printf '%s' "$_tf_v" | LC_ALL=C tr -d '[:cntrl:]')" != "$_tf_v" ]; then
    echo "$_tf_pre holds a control character." >&2; return 2
  fi
  if _pv_tf_secret "$_tf_v"; then
    echo "$_tf_pre holds a private-key header or a token shape; remove it and retry." >&2; return 2
  fi
  [ -n "$_tf_v" ] || { echo "$_tf_pre holds no content." >&2; return 2; }
  token=$_tf_v
  return 0
}

# THE GO'S ACT, RECORDED (SWAS-727). `land` alone sets these before it calls do_record, and they are plain assignments here at
# the top of the script so that no environment variable of the same name can pre-set them (the public `record` verb leaves them
# empty and writes the note it always wrote). PV_REC_GOACT is `review` for a one-act GO (a GO_GIVERS login's empty-body approval
# was the GO) or `separate` for a held approval released by a typed GO; PV_REC_GOWORDS / PV_REC_GOSHA are the held review's words,
# made safe, and the sha256 of the raw body.
PV_REC_GOACT=""; PV_REC_GOWORDS=""; PV_REC_GOSHA=""
# THE LAND RECORD (SWAS-323b). `land` alone sets PV_REC_LAND=1 (and PV_LAND_BASE, origin's default-branch tip) before it calls do_record, which
# then writes the land record beside the GO record in the SAME transaction (one read-modify-write, one push). Plain assignments here at the
# top of the script, so no environment variable of these names reaches a verb; the public `record` verb leaves both empty.
PV_REC_LAND=""; PV_LAND_BASE=""
# pv_compose_land — sets `lbody`, the land record of a serial land (a batch of one), from do_record's locals (asha, atree, scope, kitrow,
# nbody, ts) and PV_LAND_BASE. It binds the exact GO by the sha256 of the GO record's bytes as the splitter returns them (the lines of
# $nbody, each ending in a newline). It is the AUDIT projection of what land landed (no control decision reads it, design 4): `trace`
# binds it only after checking the hash and the tree. landed-tree = tested-tree = approved-tree holds because land refused an
# approved head that is not up to date with base (serial land); the queue and verdict fields read `(none: serial)`.
pv_compose_land() {
  _pl_full="$(git rev-parse -q --verify "${asha}^{commit}" 2>/dev/null)" || _pl_full=""
  _pl_hash="$(printf '%s\n' "$nbody" | pv_sha256)" || _pl_hash=""   # pv_sha256 (sha256sum, shasum, openssl) prints nothing without a tool: fail closed
  _pl_btree="$(git rev-parse -q --verify "${PV_LAND_BASE}^{tree}" 2>/dev/null)" || _pl_btree=""
  if [ -z "$_pl_full" ] || [ "${#_pl_hash}" != 64 ] || [ -z "$_pl_btree" ]; then
    echo "record: could not compose the land record (the approved commit, a sha256 tool or origin's base tree is unreadable) — nothing was written." >&2
    return 2
  fi
  _pl_n="$(pv_ev_pr_number "$scope" 2>/dev/null)" || _pl_n=""
  _pl_id="PR-$_pl_n"; if [ -z "$_pl_n" ]; then _pl_id="$scope"; fi
  _pl_utc="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo unknown)"
  lbody="$(printf '%s\n' \
      "land: promotion LAND (approve->execute->log)" \
      "approved-sha: $asha" \
      "approved-tree: $atree" \
      "scope: $scope" \
      "kit-row: $kitrow" \
      "go-record-sha256: $_pl_hash" \
      "batch: serial-$_pl_utc-${_pl_n:-none}" \
      "member: 1/1" \
      "members: $_pl_id@$(printf '%s' "$_pl_full" | cut -c1-12)" \
      "base-sha: $PV_LAND_BASE" \
      "prefix-prev-tree: $_pl_btree" \
      "landed-tree: $atree" \
      "tested-tree: $atree" \
      "queue-sha: (none: serial)" \
      "queue-run: (none: serial)" \
      "verdict-run: (none: serial)" \
      "recorded-at: $ts")"
  # the same belt as the GO record's: no line but the header may read as a record header
  if printf '%s\n' "$lbody" | sed 1d | grep -Eq '^(record|land): promotion '; then
    echo "record: a land-record line reads as a record header ('record: promotion ' or 'land: promotion ') — refusing to record." >&2
    lbody=""; return 2
  fi
  return 0
}

# pv_record_goact — add the go-act lines to the note being composed (do_record's locals: assurance, goby, goby_line, _rec_extra).
# A one-act note is written only if the forge STILL shows the authenticated approval at record time, and its go-by then carries the
# same fixed label as approved-by: one authenticated identity in two fields.
pv_record_goact() {
  case "$PV_REC_GOACT" in
    review)
      if [ "$assurance" != "authenticated: github-review" ]; then
        echo "record: the forge no longer shows the authenticated approval (it derives [$assurance]) — a one-act GO is not recorded on anything less. Nothing was written." >&2
        return 2
      fi
      goby_line="$goby [authenticated: github-review]"
      _rec_extra="go-act: review" ;;
    separate)
      # The words come from land's made-safe copy, but this arm is the last door before a line-structured body: any control
      # character (a newline would forge a note line) refuses rc 2, before anything is written.
      if [ "$(printf '%s' "$PV_REC_GOWORDS" | LC_ALL=C tr -d '[:cntrl:]')" != "$PV_REC_GOWORDS" ]; then
        echo "record: go-words holds a control character — rejected (fail closed). Nothing was written." >&2
        return 2
      fi
      _rec_extra="go-act: separate
go-words: \"$PV_REC_GOWORDS\"
go-words-sha256: $PV_REC_GOSHA" ;;
    *)
      echo "record: unrecognised go-act — nothing was written." >&2
      return 2 ;;
  esac
  return 0
}

do_record() {
  asha=""; aby=""; gate=""; rung=""; cls=""; scope=""; token=""; basis=""; nopush=0
  goby=""; goby_given=0; tok_arg=0; tok_file=0; tokpath=""; lbody=""
  while [ $# -gt 0 ]; do
    case "$1" in
      # ARGUMENT ONLY, never an env var (security vet T3): the offline escape must be visible in the
      # command the operator ran and in the shell history, not settable by ambient state.
      --no-push)      nopush=1; shift ;;
      --approved-sha) asha="${2:-}"; shift 2 ;;
      --approved-by)  aby="${2:-}";  shift 2 ;;
      # THE GO-GIVER, BY NAME (GO-IDENTITY-AND-LAND-SOD, owner ruling 2026-10-02). `--approved-by` is the
      # forge reviewer the kit can AUTHENTICATE; this is the human whose judgment the GO is, which it can
      # not. Recorded `[self-asserted]` as a FIXED literal. `goby_given` makes an explicitly BLANK value a
      # refusal (below) rather than a silent "none recorded".
      --go-by)        goby="${2:-}"; goby_given=1; shift 2 ;;
      --gate)         gate="${2:-}"; shift 2 ;;
      --rung)         rung="${2:-}"; shift 2 ;;
      --class)        cls="${2:-}";  shift 2 ;;
      --scope)        scope="${2:-}"; shift 2 ;;
      --token)        tok_arg=1; token="${2:-}"; shift 2 ;;
      # THE TOKEN FROM A FILE (SWAS-724). The owner's words go in verbatim and are never re-spelled; a
      # file keeps them off the command line, where the agent guard reads every word. Loaded after this
      # loop (pv_token_file_load), so argument order does not matter.
      --token-file)
        if [ "$tok_file" = 1 ]; then echo "record: --token-file was given twice; give it once." >&2; return 2; fi
        if [ $# -lt 2 ]; then echo "record: --token-file needs a path." >&2; return 2; fi
        case "$2" in
          -*) echo "record: --token-file needs a path that does not start with '-'." >&2; return 2 ;;
        esac
        tok_file=1; tokpath="$2"; shift 2 ;;
      --basis)        basis="${2:-}"; shift 2 ;;
      *) echo "record: unknown arg '$1'" >&2; usage; return 2 ;;
    esac
  done
  if [ "$tok_arg" = 1 ] && [ "$tok_file" = 1 ]; then
    echo "record: give the token one way: --token or --token-file, not both." >&2; return 2
  fi
  if [ "$tok_file" = 1 ]; then pv_token_file_load "$tokpath" || return 2; fi
  for pair in "approved-sha=$asha" "approved-by=$aby" "gate=$gate" "rung=$rung" \
              "change-class=$cls" "scope=$scope" "approval-token=$token"; do
    _v="${pair#*=}"
    if [ -z "$_v" ]; then echo "record: missing --${pair%%=*}" >&2; usage; return 2; fi
    # F4(a): `git notes add -F -` strips trailing whitespace, so a whitespace-only value would be stored
    # EMPTY (a note `sync`'s V1 then refuses). Reject it here, where it is cheap.
    if [ -z "$(printf '%s' "$_v" | tr -d ' \t')" ]; then
      echo "record: --${pair%%=*} is whitespace-only — rejected" >&2; return 2
    fi
  done
  if [ -n "$basis" ] && [ -z "$(printf '%s' "$basis" | tr -d ' \t')" ]; then
    echo "record: --basis is whitespace-only — rejected" >&2; return 2
  fi
  # --go-by, when GIVEN, must name someone: an empty or whitespace-only value is a refusal, never a silent
  # "(none recorded)" (a GO whose giver was meant to be named and was not is a defect to fix, not default).
  if [ "$goby_given" = 1 ] && [ -z "$(printf '%s' "$goby" | tr -d ' \t')" ]; then
    echo "record: --go-by is empty or whitespace-only — rejected (omit the flag to record '(none recorded)')" >&2; return 2
  fi
  # Reject option-like values: a --approved-sha beginning with '-' must never reach git as a flag.
  case "$asha" in
    -*) echo "record: invalid --approved-sha '$asha' (must not start with '-')" >&2; return 2 ;;
  esac
  # SANITIZE (S5a review, CRITICAL): the note body is line-structured text. A NEWLINE (or any control
  # char) in a free-text field would inject arbitrary lines — e.g. a forged `approved-by: x [signed:
  # gpg]` / `[authenticated: ...]` line that bypasses derive_assurance entirely. Reject any control
  # char in ANY free-text field and fail CLOSED (return 2) — never silently strip: a GO with a mangled
  # token must be re-issued cleanly. (POSIX/dash-clean: strip control chars via `tr` and compare.)
  for _p in "token=$token" "basis=$basis" "approved-by=$aby" "go-by=$goby" "scope=$scope" \
            "gate=$gate" "rung=$rung" "class=$cls"; do
    _fn="${_p%%=*}"; _fv="${_p#*=}"
    if [ "$(printf '%s' "$_fv" | LC_ALL=C tr -d '[:cntrl:]')" != "$_fv" ]; then
      echo "record: --$_fn contains a control character (newline/CR/tab/etc.) — rejected (fail closed)" >&2
      return 2
    fi
    # SWAS-902: template text in angle brackets is a paste, not a value; refuse before anything is written.
    if _pv_placeholder_span "$_fv" >/dev/null; then   # PV-PLACEHOLDER-RECORD
      # a token read from --token-file never has a byte of the file echoed (pv_token_file_load's contract): no span, source "file"
      if [ "$_fn" = token ] && [ "$tok_file" = 1 ]; then _pv_placeholder_msg record token "" file
      else _pv_placeholder_msg record "$_fn" "$(_pv_placeholder_span "$_fv")"; fi
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
  # The predicate is SHARED with `sync`'s re-validation (V6), so the two cannot drift.
  _scs=0; _pv_scope_shape "$scope" || _scs=$?
  case "$_scs" in
    1)
      echo "record: --scope 'branch/' names no branch (expected branch/<name>) — rejected" >&2
      return 2 ;;
    2)
      echo "record: --scope branch/<name> may contain only [A-Za-z0-9_.:/-] after 'branch/' —" >&2
      echo "        the design gate matches this key LITERALLY, so a name it cannot express" >&2
      echo "        would record a GO that satisfies nothing. Rejected (fail closed)." >&2
      return 2 ;;
  esac
  # Reject '[' or ']' ANYWHERE in --approved-by (S5a review): the assurance label is DERIVED below,
  # never supplied. A trailing-only strip left a mid-string "[signed: gpg]" decoy in the body that
  # could fool a substring grep — reject brackets outright instead.
  case "$aby" in
    *'['* | *']'*)
      echo "record: --approved-by must not contain '[' or ']' (assurance label is derived, not supplied) — rejected" >&2
      return 2 ;;
  esac
  # The same for --go-by: its label is the FIXED literal [self-asserted], never supplied, so a bracket is
  # the only way to smuggle a label into the line (sync's V1 refuses any other label too).
  case "$goby" in
    *'['* | *']'*)
      echo "record: --go-by must not contain '[' or ']' (the GO-giver is always recorded [self-asserted]) — rejected" >&2
      return 2 ;;
  esac
  # CHANGE-CLASS VOCABULARY (review M1 / security F2 — the two ends of one hardening; the other end is
  # do_actuate's allowlist). `change-class:` is now a DECIDING field: actuate proceeds only for
  # ordinary/sensitive and refuses control-plane. A free-text class was therefore a way to record a
  # note that no consumer can classify — a typo (`contol-plane`, `Control Plane`) would sail past
  # record and then be refused at actuate with a confusing message, or worse, be read as neither.
  # Validate at the FRONT DOOR, fail closed at rc 2, so the defect is caught where it is cheap.
  # Placed here deliberately: AFTER the control-char and bracket rejections (nothing may precede
  # those), and before the note is composed.
  if ! _pv_class_ok "$cls"; then   # shared with `sync`'s V5
    echo "record: invalid --class '$cls' — must be one of: ordinary | sensitive | control-plane" >&2
    echo "        (case-insensitive). The class DECIDES whether \`actuate\` may merge, so an" >&2
    echo "        unrecognised value would record a GO no consumer can classify. Rejected (fail closed)." >&2
    return 2
  fi
  # SWAS-948: --gate and --rung are listed values too, folded to the lowercase list spelling so a `Design`
  # gets the design-basis check below and the design legs, and the note says what ceremony-binding reads.
  # BEFORE the basis check; `sync` does not call these (legacy notes keep reading as they are).
  _gf=""; _rf=""
  _gf="$(_pv_gate_ok "$gate")" || { _pv_vocab_refuse record gate "$gate"; return 2; }
  _rf="$(_pv_rung_ok "$rung")" || { _pv_vocab_refuse record rung "$rung"; return 2; }
  gate="$_gf"; rung="$_rf"
  # A DESIGN GO MUST NAME ITS ARTIFACT (SWAS-392, design 2.3a). The gate that reads a design GO
  # (conformance/ceremony-binding.sh) refuses one whose basis is empty or `(none recorded)` as "names no
  # artifact", and an inherited-design child binds only to a parent whose basis is a path (or a LEGACY
  # basis-less parent on a committed list). So the front door stops minting basis-less design GOs: the
  # tool makes no new one, and the committed list names the only ones the gate accepts. EXACTLY the gate value `design` (the one value the exact-line
  # classifier accepts, G5); every other gate keeps the optional basis. PLACEMENT (H2): after every
  # argument validation above (control characters, scope shape, brackets, class), BEFORE
  # derive_assurance, the forge-review upgrade and the record transaction, so a refusal writes no note
  # and makes no forge or network call. `sync` is deliberately unchanged: it re-validates a note's
  # shape and must not refuse the legacy notes already in the ledger.
  # THE DEFAULT, TYPED (F-2/M3): the literal `(none recorded)` is what an omitted basis becomes, so for a
  # design GO it is refused as an explicit --basis too (trimmed, case-insensitive), or the refusal would
  # be bypassed by typing the default.
  _basis_lit="$(printf '%s' "$basis" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
  if [ "$gate" = design ] && { [ -z "$basis" ] || [ "$_basis_lit" = "(none recorded)" ]; }; then
    echo "record: --gate design requires --basis <path-to-the-design-artifact> — a design GO that names no" >&2
    echo "        artifact (omitted, or the literal '(none recorded)') binds nothing (ceremony-binding.sh refuses it" >&2
    echo "        as 'names no artifact'). Rejected." >&2
    return 2
  fi
  [ -n "$basis" ] || basis="(none recorded)"
  # SWAS-323, AFTER every older per-field refusal (each keeps its own message): `git notes add -F` strips trailing whitespace, so a
  # free-text value that ends in whitespace would be stored differently from the record `land` composed and read back as a misleading
  # "mismatched". Refuse it here, naming the field.
  for _p in "token=$token" "basis=$basis" "approved-by=$aby" "go-by=$goby" "scope=$scope" "rung=$rung" "gate=$gate"; do
    _fn="${_p%%=*}"; _fv="${_p#*=}"
    case "$_fv" in
      *[[:space:]])
        echo "record: --$_fn ends in whitespace — rejected (the ledger strips trailing whitespace, so the note would not say what was approved; remove it)" >&2
        return 2 ;;
    esac
  done
  # THE GO-GIVER LINE: the name with a FIXED `[self-asserted]` literal (the kit never claims to authenticate
  # the person whose judgment the GO is — the forge review in approved-by is the one authenticated control),
  # or `(none recorded)` mirroring basis:. No byte of any derivation reaches this line.
  if [ -n "$goby" ]; then goby_line="$goby [self-asserted]"; else goby_line="(none recorded)"; fi
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
  kitrow="$(git log -1 --no-show-signature --format='%(trailers:key=Kit-Row,valueonly)' "$asha" 2>/dev/null | head -1)"
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
  # STEP 0 (security vet M1; MOVED UP by SWAS-944, for every gate). A SYMBOLIC ledger ref is a repointing — measured: a fetch and a plain
  # `update-ref` both write THROUGH a symref, while `--no-deref` clobbers the symref itself. Either way the operator's ledger is not
  # where they think it is, so the guard's bypass #8 becomes a loud FRONT-DOOR refusal here rather than a silent mis-write. It must
  # run before the design legs' pre-leg fetch (which writes through a symref), and before derive_assurance and the forge call.
  if git symbolic-ref -q "refs/notes/$NOTES_REF" >/dev/null 2>&1; then
    echo "record: ledger ref refs/notes/$NOTES_REF is symbolic — repointed; refusing to record." >&2
    echo "        Restore it (git symbolic-ref --delete refs/notes/$NOTES_REF) before recording." >&2
    return 2
  fi
  # SWAS-944: a design GO's basis is checked before anything is derived or written (legs 0-6; every refusal is rc 2, no note, no forge call).
  if [ "$gate" = design ]; then _pv_design_legs || return 2; fi
  # The assurance label is DERIVED (below), never accepted from input. Brackets in --approved-by were
  # rejected above, so the id is the caller string verbatim — input can't manufacture assurance.
  aby_id="$aby"
  assurance="$(derive_assurance "$asha" "$aby_id")"
  # FORGE-REVIEW UPGRADE — STRICTLY AFTER every rc-2 sanitizer arm above, and that ordering is
  # load-bearing, not incidental: it runs on an ALREADY-VALIDATED $aby_id (no brackets, no control
  # characters, a resolvable approved-sha), so nothing it compares can itself be an injection. Moving
  # it above any of those arms would hand unvalidated bytes to the comparison. It can only upgrade the
  # label; it never changes aby_id, never blocks, never fails the record.
  assurance="$(forge_review_upgrade "$scope" "$asha" "$aby_id" "$assurance")"
  # SWAS-727: `land` alone sets PV_REC_GOACT (review | separate) for a one-act or a held-then-typed note; here it adds the go-act
  # line (and go-words, go-words-sha256) after recorded-at. Empty for every other note, which stays byte-identical to before.
  _rec_extra=""
  if [ -n "$PV_REC_GOACT" ]; then pv_record_goact || return 2; fi
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
  # Bind the structured record to the approved commit as a note (tree-invariant). `-f` writes the whole note back (SWAS-323: the
  # note is a list of records and only the same (scope, gate) key is superseded) — honest: notes are mutable (see ceiling).
  # KIT_PROMOTION_FRONT_DOOR=1 is the FRONT-DOOR SENTINEL, scoped to this ONE command [B2 sec H1].
  # guard-core.sh's Δ4(i)′ arm denies raw `git notes` writes to the ledger; under `kit-guard
  # install-shims` every git invocation is routed through that arm, so without this the arm blocked
  # the exact door its own deny message points the operator at and the ledger became unwritable by
  # any route (measured). IT IS AGENT-FORGEABLE — an agent can prefix the same variable to a raw
  # command — and the arm's ceiling says so: the arm is a drift control (owner ruling D3′), not a
  # boundary; the control that binds is the record rendered at the CI judgment surface.
  # (STEP 0, security vet M1: the symbolic-ledger refusal now sits above, ahead of the design legs' pre-leg fetch.)
  # STEP 0 (security vet M3): COMPOSE THE BODY ONCE, before the transaction. The assurance label can
  # involve a network call (the forge-review upgrade), so recomposing it on the retry below could
  # write DIFFERENT bytes for the same GO. The same bytes are written on both attempts.
  nbody="$(printf '%s\n' \
      "record: promotion GO (approve->execute->log)" \
      "approved-sha: $asha" \
      "approved-tree: $atree" \
      "approved-by: $aby_id [$assurance]" \
      "go-by: $goby_line" \
      "gate: $gate" \
      "rung: $rung" \
      "change-class: $cls" \
      "kit-row: $kitrow" \
      "scope: $scope" \
      "approval-token: \"$token\"" \
      "basis: $basis" \
      "recorded-at: $ts")"
  if [ -n "$_rec_extra" ]; then nbody="$nbody
$_rec_extra"; fi
  # SWAS-323: no composed line but the first may read as a record header, or a note would split inside this record.
  if printf '%s\n' "$nbody" | sed 1d | grep -Eq '^(record|land): promotion '; then
    echo "record: a field line reads as a record header ('record: promotion ' or 'land: promotion ') — refusing to record." >&2
    return 2
  fi
  # SWAS-323b: `land` alone asks for the land record, composed ONCE here beside the GO record (vet M3: the bytes of both are fixed before
  # the transaction, and only the note that holds them is recomputed on a retry).
  if [ "$PV_REC_LAND" = 1 ]; then pv_compose_land || return 2; fi

  _pv_rec_rc=0; _pv_record_txn || _pv_rec_rc=$?
  _pv_crit_leave    # a signal deferred inside the transaction stops the run HERE, published or unwound
  return "$_pv_rec_rc"
}
# _pv_record_txn — the transaction body (split out only so the critical section has one exit).
_pv_record_txn() {
  # THE TRANSACTION: sync-in -> write -> publish -> unwind. At most two attempts; the second only
  # ever happens on a NON-FAST-FORWARD rejection, which is the one failure a fresh sync-in can fix.
  attempt=1
  while : ; do
    if [ "$nopush" = 0 ]; then
      _pv_sync_in || return 2
    fi
    # CRITICAL SECTION (deferred signals): from just before the note write to the moment the push/unwind
    # outcome is fully resolved (published, unwound, or refused).
    _pv_crit_enter
    # _pre is captured AFTER every sync-in (security vet T1): unwinding to a value captured before
    # the fetch would move the ref BACKWARDS past records the fetch legitimately brought in.
    _pre="$(git rev-parse -q --verify "refs/notes/$NOTES_REF" 2>/dev/null || true)"
    # SWAS-323: READ-MODIFY-WRITE on the freshly synced tip. The note holds a list of records; the one with this (scope, gate) key
    # is replaced, every other record stays, and the whole note is written with the same `add -f`. Read AFTER the sync-in, so a
    # record another lane published a moment ago is kept, not erased. A one-record note is byte-identical to before.
    # FAIL CLOSED (SWAS-323): a note that exists but cannot be read is never treated as an empty note, or its records would be erased.
    if git notes --ref="$NOTES_REF" list "$asha" >/dev/null 2>&1; then
      _pv_old="$(git notes --ref="$NOTES_REF" show "$asha" 2>/dev/null)" || {
        echo "record: a note exists on $asha but could not be read — refusing to write over it." >&2; return 2; }
    else
      _pv_old=""
    fi
    _pv_new="$(_pv_note_with "$_pv_old")" || return 2
    if ! printf '%s\n' "$_pv_new" \
        | KIT_PROMOTION_FRONT_DOOR=1 git notes --ref="$NOTES_REF" add -f -F - "$asha" >/dev/null 2>&1; then
      echo "record: failed to write note refs/notes/$NOTES_REF on $asha" >&2; return 2
    fi
    _post="$(git rev-parse "refs/notes/$NOTES_REF" 2>/dev/null || true)"
    # BELT (security review SEC-L2): every unwind below uses $_post as the compare-and-swap's NEW
    # value. An empty one would turn the CAS into an unconditional write — the single most dangerous
    # thing in this file — so refuse here rather than carry an unusable old-value operand forward.
    [ -n "$_post" ] || { echo "record: could not read the ledger ref after the write" >&2; return 2; }
    if [ "$nopush" = 1 ]; then
      echo "OK: recorded approval for $scope (approved-sha $asha) -> note refs/notes/$NOTES_REF [$assurance] — UNPUBLISHED (--no-push)"
      return 0
    fi
    if pout="$(git push origin "refs/notes/$NOTES_REF" 2>&1)"; then
      echo "OK: recorded approval for $scope (approved-sha $asha) -> note refs/notes/$NOTES_REF [$assurance] — published"
      return 0
    fi
    # WHICH REJECTIONS ROUTE HERE (security vet M2, CORRECTED BY MEASUREMENT at build time). The vet
    # expected the kit's own pre-push hook to refuse a non-ff ledger push first. MEASURED: it does
    # not — git's client-side fast-forward check rejects a NON-FORCED non-ff push before any hook
    # runs, so what `record` actually sees is always git's own "(non-fast-forward)" / "(fetch
    # first)". The hook's "13: non-fast-forward (force) push..." text is matched by the same arm
    # anyway (it contains the same token), which keeps the classification right for any wrapper hook
    # that does reach it, and costs nothing. Pinned in promotion-verify-wired.sh's hookrace leg. A
    # `[remote rejected] ... (pre-receive hook declined)` is NOT one of them — it is the auth/
    # protected-ref shape, which no amount of re-syncing fixes, so it must never be retried.
    case "$pout" in
      *non-fast-forward*|*'fetch first'*) nonff=1 ;;
      *) nonff=0 ;;
    esac
    # RELAYED VERBATIM, MINUS THE CONTROL BYTES (security review SEC-L1). git's stderr here contains
    # remote-controlled text (a receive hook's message), and this file's own rule is that what lands
    # in a line-structured surface — an operator's terminal included — may not carry escapes that
    # forge lines or repaint the screen. Newline is kept: it is the message's own structure.
    pout="$(printf '%s' "$pout" | LC_ALL=C tr -d '\000-\011\013-\037\177')"
    if ! _pv_unwind "$_pre" "$_post"; then
      echo "record: the push was rejected AND the ledger moved under this record — refs/notes/$NOTES_REF" >&2
      echo "        is NOT unwound (the compare-and-swap refused rather than clobber someone else's" >&2
      echo "        commit). Inspect with promotion-verify.sh log --unpushed before recording again." >&2
      printf '%s\n' "$pout" >&2
      return 2
    fi
    if [ "$nonff" = 1 ] && [ "$attempt" = 1 ]; then
      attempt=2
      _pv_crit_leave    # unwound: a pending signal stops here, before the re-sync
      continue
    fi
    if [ "$nonff" = 1 ]; then
      echo "record: NOT published and NOT retained locally: the remote ledger moved twice during this" >&2
      echo "        record. Nothing was left dangling — re-run the same command." >&2
      return 2
    fi
    echo "record: publishing refs/notes/$NOTES_REF to origin failed for a reason a re-sync cannot fix;" >&2
    echo "        the unpublished note was unwound (nothing dangling). git said:" >&2
    printf '%s\n' "$pout" >&2
    return 2
  done
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
    case "$_tr_arg" in
      -*)
        echo "trace: arguments must not start with '-' (got '$_tr_arg')" >&2; return 2 ;;
    esac
  done
  case "$recent" in
    ''|*[!0-9]*) [ -z "$recent" ] || { echo "trace: --recent takes a positive integer" >&2; return 2; } ;;
  esac
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
    _tr_note="$(git notes --ref="$NOTES_REF" show "$_tr_a" 2>/dev/null)" || _tr_note=""
    # SWAS-323: a note is a list of records. Every GO record is indexed by its own approved tree; a record of another type (a
    # land record) is skipped, and a defective note holds no record, so it indexes nothing and its commit reds as recordless.
    _tr_rn="$(printf '%s\n' "$_tr_note" | kit_note_records n)"; _tr_ri=0
    # SWAS-323b: a land record is indexed FIRST, and only when it is BOUND (its go-record-sha256 is the sha256 of a GO record live on this
    # object AND its landed-tree is that record's approved-tree); an unbound land record binds nothing. The entry carries the land record's
    # index, so the claim stays per object while the record printed is the one that matched.
    _tr_li=0
    while [ "$_tr_li" -lt "$_tr_rn" ]; do
      _tr_li=$((_tr_li + 1))
      [ "$(printf '%s\n' "$_tr_note" | kit_note_records type "$_tr_li")" = land ] || continue
      _tr_lb="$(printf '%s\n' "$_tr_note" | kit_note_records body "$_tr_li")"
      _pv_land_go "$_tr_note" "$_tr_lb" >/dev/null || continue
      _tr_map="$_tr_map$(_pv_rec_field "$_tr_lb" landed-tree) $_tr_a $_tr_li
"
    done
    while [ "$_tr_ri" -lt "$_tr_rn" ]; do
    _tr_ri=$((_tr_ri + 1))
    [ "$(printf '%s\n' "$_tr_note" | kit_note_records type "$_tr_ri")" = record ] || continue
    _tr_body="$(printf '%s\n' "$_tr_note" | kit_note_records body "$_tr_ri")"
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
        case " $_tr_unres " in
          *" $_tr_a "*) ;;
          *) _tr_unres="$_tr_unres $_tr_a" ;;
        esac
        continue
      fi
    fi
    _tr_map="$_tr_map$_tr_t $_tr_a $_tr_ri
"
    done
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
    # The map entry is `<tree> <annotated object> <record index>`: the object is what is claimed, the index is the record whose tree matched.
    _tak="$(printf '%s' "$_tr_map" | awk -v t="$_tt" '$1 == t {print $2 " " $3; exit}')"
    _ta="${_tak%% *}"; _tk="${_tak##* }"
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
    # The claim above stays per OBJECT (one trunk commit claims an annotated sha once, whichever record matched: a per-record claim would
    # let a revert-and-reapply take a second record on the same sha). What is PRINTED is the record whose approved tree matched (SWAS-323).
    _tnw="$(git notes --ref="$NOTES_REF" show "$_ta" 2>/dev/null)" || _tnw=""
    _tn="$(printf '%s\n' "$_tnw" | kit_note_records body "$_tk")"
    # A commit bound through a land record prints the GO record that land record binds, and names the land (SWAS-323b).
    _tland=""
    if [ "$(printf '%s\n' "$_tnw" | kit_note_records type "$_tk")" = land ]; then
      _tland="$_tn"; _tn="$(_pv_land_go "$_tnw" "$_tland")" || _tn=""
    fi
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
    # THE TWO IDENTITIES, APPENDED AT THE END (GO-IDENTITY-AND-LAND-SOD): the forge approver the kit
    # authenticated (`[<label>]` as recorded) and the GO-giver recorded by name. APPENDED, so the prefix
    # above stays byte-stable for any reader that parses it. A legacy note (12 lines) carries no go-by
    # line and reads `(none recorded)`, exactly what a new note without --go-by says.
    _taby="$(printf '%s\n' "$_tn" | sed -n 's/^approved-by: //p' | head -1)"
    _tgo="$(printf '%s\n' "$_tn" | sed -n 's/^go-by: //p' | head -1)"
    # Note-derived text is printed to a terminal: control bytes are stripped (not the line dropped).
    _trow="$(printf '%s' "$_trow" | LC_ALL=C tr -d '[:cntrl:]')"; _tgate="$(printf '%s' "$_tgate" | LC_ALL=C tr -d '[:cntrl:]')"
    _tscope="$(printf '%s' "$_tscope" | LC_ALL=C tr -d '[:cntrl:]')"; _taby="$(printf '%s' "$_taby" | LC_ALL=C tr -d '[:cntrl:]')"
    _tgo="$(printf '%s' "$_tgo" | LC_ALL=C tr -d '[:cntrl:]')"
    # A ONE-ACT NOTE (SWAS-727, `go-act: review`) names the act that was the GO: the review id (the token is `forge-review:<id>`,
    # digits only, else nothing is printed) and the login (approved-by's id). Appended at the END, so the prefix stays byte-stable.
    _tgx=""
    if [ "$(printf '%s\n' "$_tn" | sed -n 's/^go-act: //p' | head -1)" = review ]; then
      _tgid="$(printf '%s\n' "$_tn" | sed -n 's/^approval-token: "forge-review:\([0-9]*\)"$/\1/p' | head -1)"
      _tglogin="$(printf '%s' "${_taby%% \[*}" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-80)"
      if [ -n "$_tgid" ] && [ "${#_tgid}" -le 20 ]; then _tgx="  GO = forge review $_tgid by $_tglogin"; fi
    fi
    if [ -n "$_tland" ]; then
      _tlb="$(printf '%s' "$(_pv_rec_field "$_tland" batch)" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-80)"
      _tgx="$_tgx  land: $_tlb (bound)"
    fi
    printf '%s  kit-row: %s  approved-sha: %s  gate: %s  scope: %s  approved-by: %s  go-by: %s%s\n' \
      "$(printf '%s' "$_tc" | cut -c1-12)" "$_trow" "$(printf '%s' "$_ta" | cut -c1-12)" \
      "${_tgate:-"(none)"}" "${_tscope:-"(none)"}" "${_taby:-"(none)"}" "${_tgo:-"(none recorded)"}" "$_tgx"
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
  _tr_rc=0; _tr_n=0; _tr_miss=0; _tr_pre=0; _tr_base=0
  # THE INCEPTION BASELINE (SWAS-943). Inception commits the incepted baseline as the trunk's FIRST commit, before any GO can exist
  # (the Inception exception, CLAUDE.md section 1), so no adopter can have recorded it. In THIS walk only, a commit reads as the baseline
  # when ALL hold: the trunk has exactly ONE root and it is this commit (a property of the whole trunk history, never of the window, so a
  # root spliced in later makes two roots and nothing is exempt); the repository is not shallow (a shallow boundary commit looks parentless,
  # so the exemption is off and one line says why); and no note binds it (a recorded root binds as before). The probe ignores replace refs,
  # so a graft cannot fake a root. `--ref` is untouched: asked about one commit by name, the trace gives the plain answer.
  # Anything the probe cannot read exempts nothing (shallow is anything but a clear `false`; no roots is an empty string).
  _tr_shallow="$(git rev-parse --is-shallow-repository 2>/dev/null)" || _tr_shallow=unknown
  _tr_roots="$(git -c core.commitGraph=false --no-replace-objects rev-list --max-parents=0 "$from" 2>/dev/null)" || _tr_roots=""
  if [ "$_tr_shallow" = true ]; then
    echo "baseline: not checked (shallow clone; fetch the full history to exempt the Inception baseline)"
  fi
  # A .git/info/grafts file can make any commit look parentless, and replace-ref protection does not cover it: with one present, exempt nothing.
  _tr_graft="$(git rev-parse --git-path info/grafts 2>/dev/null)" || _tr_graft=""
  if [ -n "$_tr_graft" ] && [ -e "$_tr_graft" ]; then
    echo "baseline: not checked (a .git/info/grafts file is present; grafts can make any commit look like a root)"
    _tr_shallow=grafted
  fi
  # THE DETECTIVE EVIDENCE LEG (SWAS-537, ruling Q1: it prints and counts, and NEVER changes the rc). For each commit bound to a note,
  # read the exact-head evidence of the PR the note names (the very reads `land` makes). A commit with none is FLAGGED: it reached
  # the trunk without a completed light-or-full run on the head that was approved (an admin or UI merge in the SEC-2 window, or a
  # merge outside `land`). The leg turns OFF only on proof of no credential: when the FIRST forge read in the window fails, trace
  # probes `gh api rate_limit` (a credential-only GET); only if that probe ALSO fails (no credential, as in CI's loop-state, which
  # drops it) is there ONE UNVERIFIED line, never a green and never a flag. With a working credential a failing per-PR read (a 404,
  # an answer failure), first or later, is that commit's own UNVERIFIED line and the walk goes on; the summary counts FLAG, ok and
  # UNVERIFIED commits and says PARTIAL when some were read first. A run from before the `gate` job existed is accepted as
  # pre-gate. A layout that is not kit at both locations (see pv_ev_layout) prints its N/A line once (both adopter), or UNVERIFIED
  # naming the token (layout-mismatch, kit-pipeline-half-present, forge-unreadable).
  _tr_ev_on=1; _tr_ev_unver=0; _tr_ev_n=0; _tr_ev_flags=0; _tr_ev_pre=0; _tr_ev_unv_n=0
  pv_ev_layout
  case "$_pv_ev_layout" in
    adopter) _tr_ev_on=0; pv_ev_na_line ;;
    refuse)  _tr_ev_on=0; echo "evidence leg: UNVERIFIED ($_pv_ev_lay_reason: $_pv_ev_lay_note) - no commit was checked." ;;
  esac
  _tr_ev_one() { # <trunk commit> : reads the note trace_one just parsed in $_tn
    [ "$_tr_ev_on" = 1 ] || return 0
    _te_c="$(printf '%s' "$1" | cut -c1-12)"
    _te_asha="$(printf '%s\n' "$_tn" | sed -n 's/^approved-sha: //p' | head -1)"; [ -n "$_te_asha" ] || _te_asha="$_ta"
    _te_pr="$(pv_ev_pr_number "$(printf '%s\n' "$_tn" | sed -n 's/^scope: //p' | head -1)")" || {
      _tr_ev_unv_n=$((_tr_ev_unv_n + 1))
      echo "evidence leg: $_te_c UNVERIFIED (the note's scope is not a PR id, so no pull request can be read)"; return 0; }
    pv_ev_read "$_te_pr" "$_te_asha"
    case "$_pv_ev_verdict" in
      unreadable) if [ "$_tr_ev_n" -eq 0 ] && ! gh api rate_limit >/dev/null 2>&1; then _tr_ev_on=0; _tr_ev_unver=1; return 0; fi
                  _tr_ev_unv_n=$((_tr_ev_unv_n + 1)); echo "evidence leg: $_te_c UNVERIFIED (forge read failed)"; return 0 ;;
      ok) _tr_ev_n=$((_tr_ev_n + 1))
          case "$_pv_ev_gate" in
            success) ;;
            absent)  _tr_ev_pre=$((_tr_ev_pre + 1)); echo "evidence leg: $_te_c ok (pre-gate: run $_pv_ev_run predates the gate job)"; return 0 ;;
            *)       _pv_ev_reason='no-gate-job'; _pv_ev_verdict=refused ;;
          esac ;;
      *) _tr_ev_n=$((_tr_ev_n + 1)) ;;
    esac
    [ "$_pv_ev_verdict" = refused ] || return 0
    _tr_ev_flags=$((_tr_ev_flags + 1))
    printf '%s\n' "FLAG admin-merge: $_te_c head $(printf '%s' "$_te_asha" | cut -c1-12) merged without exact-head light evidence ($(printf '%s' "$_pv_ev_reason" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-80))"
  }
  # OLDEST-FIRST, AND THE ORDER IS LOAD-BEARING FOR THE DEDUP ABOVE. `git rev-list` yields
  # newest-first; walking that way would let the EMPTY commit (the newer one) claim the note and red
  # the genuine commit that produced the tree — naming the victim instead of the borrower. Reversed,
  # the first commit to produce a tree claims its note and any later commit that merely reproduces
  # that tree is the one that reds. (`tac`/`tail -r` are not portable; awk is.)
  for _tr_c in $(git rev-list -n "$recent" "$from" | awk '{a[NR]=$0} END{for(i=NR;i>0;i--) print a[i]}'); do
    _tr_n=$((_tr_n + 1))
    _tr_isbase=0
    if [ "$_tr_shallow" = false ] && [ "$_tr_roots" = "$_tr_c" ]; then _tr_isbase=1; fi
    if [ "$_tr_isbase" = 1 ]; then
      # The baseline candidate is tried FIRST, silently: it may carry a note, and then it binds like any commit. trace_one mutates
      # _tr_claimed/_ta/_tn in THIS shell, so it is never run inside $(...); its stderr (the old RECORDLESS text) goes to a temp file.
      _tr_errf="$(mktemp "${TMPDIR:-/tmp}/trace-base.XXXXXX" 2>/dev/null)" || _tr_errf=/dev/null
      if trace_one "$_tr_c" 2>"$_tr_errf"; then
        _tr_ev_one "$_tr_c"
      else
        _tr_base=$((_tr_base + 1))
        printf '%s  baseline: the trunk'"'"'s only root commit, unrecorded by design (Inception precedes the GO ledger)\n' "$(printf '%s' "$_tr_c" | cut -c1-12)"
      fi
      [ "$_tr_errf" = /dev/null ] || rm -f "$_tr_errf"
    elif trace_one "$_tr_c"; then _tr_ev_one "$_tr_c"; else _tr_rc=1; _tr_miss=$((_tr_miss + 1)); fi
  done
  _tr_bound=$((_tr_n - _tr_miss - _tr_base))
  _tr_ev_ok=$((_tr_ev_n - _tr_ev_flags - _tr_ev_pre))
  if [ "$_tr_ev_unver" = 1 ]; then
    echo "evidence leg: UNVERIFIED (the first forge read failed; the cause is not known: a missing credential, as in CI's loop-state, or no answer from the forge) - no commit was checked for exact-head CI evidence; this says nothing about them either way."
  elif [ "$_tr_ev_n" -gt 0 ] && [ "$_tr_ev_unv_n" -gt 0 ]; then
    echo "evidence leg: PARTIAL — $_tr_ev_flags FLAG(s), $_tr_ev_ok ok, $_tr_ev_pre pre-gate, $_tr_ev_unv_n UNVERIFIED over $_tr_ev_n commit(s) read; the UNVERIFIED commits were not checked either way; detective only, the exit code is unchanged."
  elif [ "$_tr_ev_n" -gt 0 ]; then
    echo "evidence leg: $_tr_ev_flags FLAG(s) over $_tr_ev_n commit(s) read ($_tr_ev_ok ok, $_tr_ev_pre pre-gate, 0 UNVERIFIED); detective only, the exit code is unchanged."
  elif [ "$_tr_ev_unv_n" -gt 0 ]; then
    echo "evidence leg: UNVERIFIED — no commit was read ($_tr_ev_unv_n UNVERIFIED: no pull request named, or the forge read failed); this says nothing about them either way."
  fi
  # NON-VACUITY: an empty window is a FAIL, never a quiet pass. A green over zero commits would be
  # the exact shape this leg exists to prevent someone shipping.
  if [ "$_tr_n" -eq 0 ]; then
    echo "trace: walked ZERO commits from '$from' — a green over an empty window asserts nothing." >&2
    return 1
  fi
  # A window holding only the baseline binds nothing: a green here would assert nothing (the empty-window rule, extended).
  if [ "$_tr_rc" = 0 ] && [ "$_tr_bound" -eq 0 ] && [ "$_tr_base" -gt 0 ]; then
    echo "trace: no bound commit in the window — only the Inception baseline; a green here would assert nothing." >&2
    return 1
  fi
  if [ "$_tr_rc" = 0 ]; then
    if [ "$_tr_base" -gt 0 ]; then
      echo "OK: trace — $_tr_bound/$_tr_bound bound of the last $recent commit(s) on $from; $_tr_base is the Inception baseline (the trunk's only root, unrecorded by design)."
    else
      echo "OK: trace — $_tr_bound/$_tr_bound of the last $recent commit(s) on $from are bound to a promotion note."
    fi
    echo "    of those, $((_tr_bound - _tr_pre)) carry a projected board row; $_tr_pre predate the kit-row projection"
    echo "    (bound and recoverable, NOT verified-correct: this inherits the GO record's assurance exactly.)"
  else
    echo "FAIL: trace — $_tr_miss of $_tr_n commit(s) on $from have no recoverable board row (see above)." >&2
  fi
  return "$_tr_rc"
}

do_log() {
  _unpushed=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --unpushed) _unpushed=1; shift ;;
      *) echo "log: unknown arg '$1'" >&2; usage; return 2 ;;
    esac
  done
  # --unpushed — the target of `record`'s divergence remedy: which records does the remote NOT have?
  # FAIL CLOSED (security vet M4): if the remote cannot be read we print UNKNOWN and exit 2. The
  # tempting "0 unpushed" would be read as "everything is published" — the most dangerous possible
  # answer here, and the one an operator would act on by force-pushing or deleting the local ref.
  if [ "$_unpushed" = 1 ]; then
    echo "# Unpublished promotion records (refs/notes/$NOTES_REF not on origin)"
    if ! git rev-parse -q --verify "refs/notes/$NOTES_REF" >/dev/null 2>&1; then
      echo "(no local refs/notes/$NOTES_REF — nothing can be unpublished)"
      return 0
    fi
    # Split the three remote states with the same probe `record` uses, so "the remote has no ledger
    # at all" reports the truth (everything local is unpublished) instead of the alarming UNKNOWN.
    if git ls-remote --exit-code origin "refs/notes/$NOTES_REF" >/dev/null 2>&1; then
      _up_probe=0
    else
      _up_probe=$?
    fi
    case "$_up_probe" in
      0) _pv_scratch_free log || return 2
         if ! git fetch --refmap= --no-tags -f origin "+refs/notes/$NOTES_REF:$NOTES_SCRATCH" >/dev/null 2>&1; then
           echo "UNKNOWN (remote unreachable): cannot read origin's refs/notes/$NOTES_REF, so which local" >&2
           echo "        records are unpublished cannot be determined. This is NOT '0 unpushed'." >&2
           return 2
         fi
         # CAPTURE BEFORE ITERATING (security review SEC-M1). A `for x in $(git rev-list …)` swallows
         # the exit status: if the scratch ref were deleted or repointed between the fetch and this
         # walk, rev-list would fail and the loop would simply not execute — rendering as a clean,
         # confident "nothing unpublished". That is the one answer this mode must never give by
         # accident, so the status is checked before a single line is printed.
         _ul="$(git rev-list "refs/notes/$NOTES_REF" "^$NOTES_SCRATCH" 2>/dev/null)" || {
           echo "UNKNOWN (rev-list failed): the local ledger could not be compared with the fetched" >&2
           echo "        remote chain. This is NOT '0 unpushed'." >&2
           return 2
         } ;;
      2) # The remote answered and has no ledger ref at all: every local record is unpublished.
         echo "(origin has no refs/notes/$NOTES_REF — every local record below is unpublished)"
         _ul="$(git rev-list "refs/notes/$NOTES_REF" 2>/dev/null)" || {
           echo "UNKNOWN (rev-list failed): the local ledger could not be walked. NOT '0 unpushed'." >&2
           return 2
         } ;;
      *) echo "UNKNOWN (remote unreachable): cannot read origin's refs/notes/$NOTES_REF, so which local" >&2
         echo "        records are unpublished cannot be determined. This is NOT '0 unpushed'." >&2
         return 2 ;;
    esac
    _uf=0
    for _uc in $_ul; do
      for _up in $(git diff-tree -r --root --no-commit-id --name-only "$_uc" 2>/dev/null); do
        _uo="$(printf '%s' "$_up" | tr -d '/')"
        # A notes tree path is the annotated object id, fanned out; anything else is not ours to
        # print or to hand to `git notes show` (security review SEC-L3). `--` ends option parsing.
        case "$_uo" in
          [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
          *) continue ;;
        esac
        echo ""
        echo "## $_uo (unpublished)"
        git notes --ref="$NOTES_REF" show -- "$_uo" 2>/dev/null || true
        _uf=1
      done
    done
    _pv_drop_scratch
    if [ "$_uf" = 1 ]; then echo "# reconcile: promotion-verify.sh sync  (preview: sync --dry-run)"; fi
    return 0
  fi
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
  case "$ref" in
    -*) echo "check: invalid --ref '$ref' (must not start with '-')" >&2; return 2 ;;
  esac
  case "$asha" in
    -*) echo "check: invalid --approved-sha '$asha' (must not start with '-')" >&2; return 2 ;;
  esac

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

# actuate --ref <head-branch> --approved-sha <sha> [--merge-cmd "<cmd>"]
#   --ref is the PR's head branch at the approved sha (step 0 refuses anything else before a merge); a caller
#   --merge-cmd is vetted like land's and must pin --match-head-commit <sha>; the GO note is read from ORIGIN;
#   the post-check repeats step 0 and the real shipped == approved check is CI's `trace --recent` (SWAS-207a; the kit's ci.yml, and an adopter's `trunk-trace` job).
#   The ORDINARY/SENSITIVE actuation GATE (control-plane is a pointer at `land`, step 1b). Fails CLOSED unless a
#   recorded, SHA-bound GO exists on origin and the bar for the declared MERGE RELATIONSHIP holds — TEAM (the
#   default, and every undeclared or unreadable case): the label is [authenticated: <forge>-review] AND the
#   approver is a distinct party from the author; SOLO: the solo bar (the named go-by, the tree, a non-pre-build
#   gate) replaces both. Then performs a NORMAL (non-`--admin`) merge via a swappable --merge-cmd and
#   re-verifies shipped == approved. Never emits `--admin`: approval authorizes PROMOTION, never a
#   branch-protection BYPASS (the guard denies `--admin` to the agent — docs/governance/promotion-contract.md).
#
#   Fail-safe direction: ANY parse/lookup gap in steps 1-3 -> refuse before touching anything; a gap
#   in step 5 (post-merge) -> loud SHIPPED != APPROVED (an incident, not a warning).
#
#   HONEST CEILING (rewritten at PR 11, when the sentence it replaced stopped being true): the
#   forge-review -> [authenticated: github-review] derivation IS NOW WIRED in `record`, so this gate
#   is reachable by a production path and `actuate` opens for ORDINARY and SENSITIVE changes on an
#   authenticated recorded GO. CONTROL-PLANE is refused here (step 1b, before any label judgment) with a pointer at
#   the exact `land` command, in BOTH relationships (D-241014-1 item 6 closed the Tier-3 sitting).
#   WHAT IS STILL NOT PROVEN HERE: the live `gh pr merge` remains a swappable stub in tests, and the
#   PR-number -> merge-commit-sha resolution for step 5 is still the forge-adapter seam. AND THE LABEL
#   BAR IS NOT AUTHENTICATION: a note is self-authorable and the derivation trusts the local `gh`
#   binary and its ambient credential, so both the bar and the class refusal are DRIFT CONTROLS at the
#   note's own trust tier. The control that binds a human with push rights is server-side branch
#   protection + required review; `--admin` stays denied to the agent regardless (:676-678).
# pv_release_claim <note-text> <verb-label> — RELEASE THE ROW'S OWN BOARD CLAIM AFTER A VERIFIED
# MERGE (BOARD-CLAIM-MECHANISM §3.5, extended to `land` by B2-SESSION-IDENTITY-LEDGER decision 6).
# The merge is the end of the slice, so the row's claim ref has done its job and must not linger: a
# stale claim blocks the next session from taking the row, shows up in `status` as work nobody is
# doing, and — since B4 — consumes a slot in the machine's WIP ceiling. THE EIGHT STALE REFS OF
# 2026-09-15 ARE EXACTLY THIS GAP: `actuate` had this block, `do_land` did not, and every slice that
# landed left its claim behind.
#
# The row comes from the note's OWN `kit-row:` projection — derived by `record` from the approved
# commit's trailer, never a flag here.
# `--stale` IS REQUIRED AND IS NOT A SHORTCUT: the merger is routinely not the claimant (builder !=
# ratifier is the point), so the holder check would refuse every real merge. Since B2 that flag also
# means the release must PROVE staleness — and a `land`/`actuate` release is P3-provable by
# construction, because the merge just moved the row into `## Done` on the default branch. A forged
# `kit-row:` naming a LIVE row fails that proof and releases nothing, which makes this call strictly
# safer than the unconditional `--stale` it replaces.
# ⚠️ THAT SENTENCE IS TRUE ONLY UNDER THE PROOFS THAT REMAIN, and it was NOT true as first written
# (re-graded at fix round 1, H2). While "branch absent from origin" counted as a proof, a forged
# `kit-row:` naming a live, NOT-YET-PUSHED slice satisfied it — and under one-push-per-PR that is
# every slice before its final push. P1 is withdrawn; the proofs are P2 (a merged same-repo PR from
# that row's branch) and P3 (that row Done on the default-branch board), neither of which a forged
# row id can conjure. The safety argument for calling `--stale` from an automated verb rests
# entirely on this, which is why it is spelled out rather than assumed.
#
# ⚠️ FAILURE HERE IS A **WARN**, NEVER A MERGE FAILURE. The merge ALREADY HAPPENED — returning
# non-zero now would report a successful, verified promotion as failed, and no rc can un-merge it.
# What is printed is the exact command to run by hand.
#
# LAND-WRITES-CARD-STATE: on a TRACKER backend the merge is also the close of the row's CARD, which no
# PR can write (the Done row rides the PR only on `md`, D-240903-2 (1)). So the helper routes by backend
# (the same `seam_backend` land's A9 leg uses): `md`, empty, unrecognised or a seam rc 2 keep the call
# above exactly; `jira` (the one backend with a board.sh write adapter) runs
# `sh <beside>/board.sh release <row> --stale`, which ends the card at Done and deletes the claim ref after
# the transition; any other recognised tracker keeps the ref-only call plus a WARN to move the card by hand.
# ⚠️ THE TRACKER EXCEPTION TO THE PROOF ARGUMENT ABOVE: with a claim ref held, board.sh's release-ref still
# demands P2 (a merged PR). With NO claim ref there is no proof to check at all (board.sh prints UNPROVEN and
# moves the card on the caller's word — a forge-UI hand-close must work). For land/actuate the standing
# argument is therefore different: the proof is the VERIFIED MERGE of the approved commit whose `Kit-Row`
# trailer names the row. A wrong trailer that reviewers approved closes the wrong card; that is a review
# failure, not something this helper can see.
# A failure is the same WARN-never-failure, naming that command. EVERY run that merged sets $PV_BOARD_TAIL, the
# ONE line `land`/`actuate` print LAST (a stated contract in usage; every line is listed there). rc stays 0:
# the merge is done and verified.
pv_tracker_backend() {  # -> the tracker backend name on stdout, or nothing (md / empty / unrecognised / seam rc 2)
  _pvlib="$ROOT/conformance/backlog-lib.sh"
  [ -f "$_pvlib" ] && [ -r "$_pvlib" ] || return 0
  # sourced in a subshell: this helper must not leak the seam's globals into the verb that called it
  # shellcheck disable=SC1090  # dynamic source path (the kit's own backlog-lib.sh); existence/readability checked above
  if _pvb=$( . "$_pvlib"; SEAM_ROOT=$ROOT; seam_backend 2>/dev/null ); then :; else return 0; fi
  case "$_pvb" in
    github | jira | ado | linear | gitlab) printf '%s' "$_pvb" ;;
  esac
  return 0
}

pv_release_claim() {
  _pvnote="$1"; _pvverb="$2"
  PV_BOARD_TAIL='board: NOT CLOSED — see the WARN above'
  _pvkr_line="$(printf '%s\n' "$_pvnote" | grep '^kit-row:' | head -1 || true)"
  _pvkr="${_pvkr_line#kit-row:}"
  # ⚠️ CONTROL BYTES OUT FIRST (security S-L6). It comes from a GIT NOTE — self-authorable text —
  # and it is printed straight into an operator's terminal by the WARN lines below. An ANSI escape in
  # a `kit-row:` projection could repaint or forge those lines, which are the audit record of a
  # merge. Stripped once, here, so every consumer downstream (the prints AND the argument handed to
  # board-claim.sh) sees the sanitised value; board-claim's own row grammar is the second gate.
  _pvkr="$(printf '%s' "$_pvkr" | tr -d '[:cntrl:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  _pvbc="$(dirname -- "$0")/board-claim.sh"
  _pvbd="$(dirname -- "$0")/board.sh"
  _pvtb="$(pv_tracker_backend)"
  if [ -z "$_pvkr" ] || [ "$_pvkr" = '(none)' ]; then
    echo "$_pvverb: no kit-row on the GO note — no board claim to release (nothing invented)."
    if [ -n "$_pvtb" ]; then
      echo "$_pvverb: WARN — no row, so no card was closed; close it by hand if one exists." >&2
    else
      PV_BOARD_TAIL='board: row closes with the PR (md); no claim to release'
    fi
    return 0
  fi
  # ROW GRAMMAR, whole string (security Low 1): the value comes from a self-authorable note, and the commands
  # printed below are meant to be pasted. A value outside [A-Z0-9][A-Z0-9-]* releases nothing, closes nothing,
  # and is NEITHER echoed NOR turned into a paste-able command.
  case "$_pvkr" in
    [!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789]* | *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-]*)
      echo "$_pvverb: kit-row is not a valid row id; nothing released or closed."
      echo "$_pvverb: WARN — the GO note's kit-row is not a valid row id; no claim was released and no card was closed." >&2
      return 0 ;;
  esac
  if [ "$_pvtb" = jira ]; then
    pv_close_card_jira
  elif [ -n "$_pvtb" ]; then
    # a recognised tracker with NO board.sh write adapter: the claim ref is still released, the card is moved by hand
    pv_release_claim_ref || :
    echo "$_pvverb: WARN — no write adapter for '$_pvtb'; move the card on '$_pvkr' by hand." >&2
  elif pv_release_claim_ref; then
    PV_BOARD_TAIL='board: row closes with the PR (md); claim released'
  else
    PV_BOARD_TAIL='board: row closes with the PR (md); claim NOT released — see the WARN above'
  fi
  return 0
}

# pv_release_claim_ref: the ref-only release (the md call, text unchanged). rc 0 released, 1 not (a WARN printed).
pv_release_claim_ref() {
  if [ ! -f "$_pvbc" ]; then
    echo "$_pvverb: WARN — board-claim.sh not found beside this script; claim on '$_pvkr' NOT released." >&2
    return 1
  fi
  # SWAS-192: in a checkout that opted in, the release needs the holder's lease token (stripped at dispatch, kept in _pv_ltok)
  set -- release "$_pvkr" --stale
  [ -z "${_pv_ltok:-}" ] || set -- "$@" --lease-token "$_pv_ltok"
  if sh "$_pvbc" "$@"; then
    echo "$_pvverb: board claim on '$_pvkr' released (refs/claims/$_pvkr deleted on origin)."
    return 0
  fi
  echo "$_pvverb: WARN — could not release the board claim on '$_pvkr' (refs/claims/$_pvkr may still exist)." >&2
  echo "        The merge SUCCEEDED and is verified; release by hand:" >&2
  echo "        sh scripts/board-claim.sh release $_pvkr --stale" >&2
  return 1
}

# pv_close_card_jira: `board.sh release <row> --stale` (card -> Done). Sets PV_BOARD_TAIL on success; a failure is a WARN.
pv_close_card_jira() {
  if [ ! -f "$_pvbd" ]; then
    echo "$_pvverb: WARN — board.sh not found beside this script; the card on '$_pvkr' was NOT closed." >&2
    echo "        The merge SUCCEEDED and is verified; close it by hand:" >&2
    echo "        sh scripts/board.sh release $_pvkr --stale" >&2
    return 0
  fi
  set -- release "$_pvkr" --stale
  [ -z "${_pv_ltok:-}" ] || set -- "$@" --lease-token "$_pv_ltok"
  if _pvout=$(sh "$_pvbd" "$@"); then
    [ -z "$_pvout" ] || printf '%s\n' "$_pvout"
    case "$_pvout" in
      *'no claim to release'*) echo "$_pvverb: board card on '$_pvkr' Done (no claim ref; merge proof not checked)." ;;
      *) echo "$_pvverb: board card on '$_pvkr' closed (Done, proven by post-read; claim released)." ;;
    esac
    PV_BOARD_TAIL='board: closed'
    return 0
  fi
  [ -z "$_pvout" ] || printf '%s\n' "$_pvout"
  echo "$_pvverb: WARN — could not close the card on '$_pvkr' (refs/claims/$_pvkr may still exist)." >&2
  echo "        The merge SUCCEEDED and is verified; close it by hand:" >&2
  echo "        sh scripts/board.sh release $_pvkr --stale" >&2
  return 0
}

# ---------------------------------------------------------------------------------------------
# RUNAWAY-METERING-LANDING-GATE (design 2026-09-29, §2.2 with the §5a/§5b/§5c amendments binding).
# `land` and `actuate` consult the PER-SLICE METER (`runaway-guard.sh meter`) behind the
# RUNAWAY_METERING_GATE dial. SWAS-302 (owner answer Q2 A2) dropped ONE refusal: a row that was never metered
# on this machine is now only NOTED, in enforce and in observe. In enforce `land`/`actuate` still REFUSE (before
# any note is written / any merge is attempted) an approved commit with no Kit-Row, an absent guard, and a
# guard that cannot read the tally (rc 2) or exits any other rc. The dial is ABSENT on an adopter
# export, and absent is SILENT — an adopter sees nothing.
#
# ⚠️ HONEST CEILING (design §5 + F5): the gate proves a row was metered "EVER", not metered "HONESTLY" —
# `step --row R --tokens 1 --agents 1` passes it. It does not own row identity (a trailer naming any
# metered row passes; the row-to-branch binding belongs to loop-state / backlog-presence). The tally is
# PER MACHINE, so a row metered elsewhere reads as unmetered here. On `actuate` the GO note already exists
# (`record` is a separate verb), so a refusal there leaves a recorded-but-unmerged GO. Verb-scoped, like
# the rest of this file: a raw `gh pr merge` never consults it.
PV_STOP_LINE=""

# pv_dial_mode <sha> -> prints `enforce` | `observe` | `absent` on stdout (warnings on stderr).
# PARSE, never source. The conf side is read from the APPROVED TREE — `git show <sha>:.kit/dials.conf`, by
# blob — and NEVER from the working tree (an agent could edit that) or a remote-tracking ref. A
# de-escalation therefore has to be a committed control-plane diff inside the approved PR, visible to the
# owner at GO. Only a regular blob (mode 100644/100755) is read: a symlink (120000) or any other entry
# reads OBSERVE with a loud line. Env RUNAWAY_METERING_GATE=enforce ESCALATES; env can NEVER de-escalate.
# Conf-side and env-side garbage are WARNed separately and read as observe / ignored respectively.
pv_dial_mode() {
  _pdsha="$1"; _pdconf=absent; _pdtab="$(printf '\t')"
  if git -C "$ROOT" rev-parse -q --verify "${_pdsha}^{tree}" >/dev/null 2>&1; then
    _pdent="$(git -C "$ROOT" ls-tree --full-tree "$_pdsha" -- .kit/dials.conf 2>/dev/null | head -1 || true)"
    if [ -n "$_pdent" ]; then
      _pdmode="${_pdent%% *}"
      _pdobj="${_pdent#* }"; _pdobj="${_pdobj#* }"; _pdobj="${_pdobj%%"$_pdtab"*}"
      case "$_pdmode" in
        100644|100755)
          _pdline="$(git -C "$ROOT" cat-file blob "$_pdobj" 2>/dev/null | grep -E '^[[:space:]]*RUNAWAY_METERING_GATE[[:space:]]*=' | tail -n1 || true)"
          if [ -n "$_pdline" ]; then
            _pdval="$(printf '%s' "$_pdline" | sed -E "s/^[[:space:]]*RUNAWAY_METERING_GATE[[:space:]]*=[[:space:]]*//; s/#.*$//; s/[\"']//g; s/[[:space:]].*$//")"
            case "$_pdval" in
              enforce|observe) _pdconf="$_pdval" ;;
              *) _pdconf=observe
                 _pdsafe="$(printf '%s' "$_pdval" | tr -d '[:cntrl:]' | cut -c1-40)"
                 printf '%s\n' "WARN: RUNAWAY_METERING_GATE='$_pdsafe' in .kit/dials.conf (the approved tree) is not a recognized value (accepted: enforce|observe) — read as OBSERVE." >&2 ;;
            esac
          fi ;;
        *)
          _pdconf=observe
          echo "WARN: .kit/dials.conf in the approved tree is a $_pdmode entry (a symlink or other non-regular file), not a regular file — NOT read; the metering gate reads as OBSERVE. A dial file must be a regular tracked file." >&2 ;;
      esac
    else
      # fix round 3 (security F-A): `.kit` ITSELF a symlink (120000) or gitlink (160000) makes the path-through
      # lookup above return NOTHING — indistinguishable from an adopter tree. Ask for the `.kit` entry itself;
      # anything but a tree (040000) is a committed disarm and reads OBSERVE, loudly.
      _pdkent="$(git -C "$ROOT" ls-tree --full-tree "$_pdsha" -- .kit 2>/dev/null | head -1 || true)"
      _pdkmode="${_pdkent%% *}"
      if [ -n "$_pdkent" ] && [ "$_pdkmode" != 040000 ]; then
        _pdconf=observe
        echo "WARN: .kit in the approved tree is a $_pdkmode entry (a symlink or gitlink), not a directory — .kit/dials.conf is NOT read; the metering gate reads as OBSERVE. A dial file must be a regular tracked file." >&2
      fi
    fi
  fi
  _pdenv="${RUNAWAY_METERING_GATE:-}"
  case "$_pdenv" in
    ''|enforce|observe) : ;;
    *) _pdsafe="$(printf '%s' "$_pdenv" | tr -d '[:cntrl:]' | cut -c1-40)"
       printf '%s\n' "WARN: RUNAWAY_METERING_GATE='$_pdsafe' in the environment is not a recognized value (accepted: enforce|observe) — IGNORED." >&2
       _pdenv="" ;;
  esac
  if [ "$_pdenv" = enforce ]; then printf 'enforce\n'; return 0; fi
  if [ "$_pdenv" = observe ] && [ "$_pdconf" = enforce ]; then
    echo "WARN: RUNAWAY_METERING_GATE=observe in the environment cannot de-escalate the enforce carried by the approved tree's .kit/dials.conf — the tree WINS (env may only escalate)." >&2
  fi
  printf '%s\n' "$_pdconf"
  return 0
}

# pv_remote_ref_sha <full-ref> -> stdout the sha of EXACTLY <full-ref> on origin; rc 0 found, 1 otherwise.
# ls-remote patterns tail-match and refs sort, so a pushed `a/<full-ref>` also answers and sorts first
# (SWAS-245); only a line whose ref field IS <full-ref> counts, and exactly one must exist.
pv_remote_ref_sha() {
  _rrout="$(GIT_TERMINAL_PROMPT=0 git -C "$ROOT" ls-remote origin "$1" 2>/dev/null)" || return 1
  printf '%s\n' "$_rrout" | awk -v r="$1" '$2 == r { s = $1; n++ } END { if (n == 1) { print s; exit 0 } exit 1 }'
}

# pv_docs_only <sha> -> 0 only when the change-set base..<sha> is DOCS-ONLY by the SAME predicate the CI
# lane uses (conformance/ci-classify-changes.sh; reused, not re-implemented). FAIL-SAFE: an unresolvable
# base, an empty listing, or a classifier that is absent or fails all mean NOT docs-only. The listing comes
# from git over the approved commit (--no-renames, so a .sh -> .md rename lists BOTH paths), never from
# caller text.
pv_docs_only() {
  _ddsha="$1"; _ddcls="$(dirname -- "$0")/../conformance/ci-classify-changes.sh"
  [ -f "$_ddcls" ] || return 1
  # The base comes from the REMOTE (ls-remote), never the local origin/main ref (an agent can move it with
  # update-ref). Any failure — no network, ref absent, object absent locally — means NOT docs-only.
  # A failure for a BASE reason says so (one line, both modes) so the caller knows the fix is a fetch, not a rewrite.
  _ddrsha="$(pv_remote_ref_sha refs/heads/main)" || _ddrsha=""
  if [ -z "$_ddrsha" ]; then echo "docs-only exemption unavailable: cannot read origin's main"; return 1; fi
  if ! git -C "$ROOT" cat-file -e "${_ddrsha}^{commit}" 2>/dev/null; then
    echo "docs-only exemption unavailable: origin/main tip not fetched — git fetch origin"; return 1
  fi
  _ddbase="$(git -C "$ROOT" merge-base "$_ddrsha" "$_ddsha" 2>/dev/null)" || return 1
  [ -n "$_ddbase" ] || return 1
  _ddlist="$(mktemp 2>/dev/null)" || return 1
  _ddrc=1
  if git -C "$ROOT" diff --name-only --no-renames "$_ddbase" "$_ddsha" >"$_ddlist" 2>/dev/null && [ -s "$_ddlist" ]; then
    _ddv="$(sh "$_ddcls" "$_ddlist" 2>/dev/null || true)"
    [ "$_ddv" = "docs_only=true" ] && _ddrc=0
  fi
  rm -f "$_ddlist"
  return "$_ddrc"
}

# pv_sod_author_check <verb> <approved-sha> <approver-normalized> -> 0 SoD holds | 1 REFUSED (already printed).
# builder != ratifier for BOTH `actuate` (step 3) and `land` (step 0b). FAIL-CLOSED: an author that cannot be
# read is never a pass (an empty operand makes `approver != author` vacuously true — the same refusal the
# forge-side SoD makes). Every git call is `git -C "$ROOT"`, like pv_meter_gate, so SoD and the meter gate
# resolve against the same repo. The author is read from the RESOLVED commit id, not the caller's string.
# ⚠️ `%an`/`%ae`, NEVER `%aN`/`%aE`: `.mailmap` is tree-controlled, so honouring it would let the change under
# review choose the identity it is compared against. Do not "fix" this. The fold is ASCII-only (LC_ALL=C): a
# non-ASCII name is still compared case-sensitively (honest ceiling). A DRIFT CONTROL at the note's own tier.
pv_sod_author_check() {
  _sav="$1"; _sasha="$2"; _saaby="$3"
  _saVERB="$(printf '%s' "$_sav" | LC_ALL=C tr 'a-z' 'A-Z')"
  _said="$(git -C "$ROOT" rev-parse -q --verify "${_sasha}^{commit}" 2>/dev/null || true)"
  if [ -z "$_said" ]; then
    echo "$_saVERB REFUSED: the approved commit $_sasha is not in this clone — SoD cannot compare the approver to its author." >&2
    echo "        Fetch it and re-run (do not change the approver): git fetch origin $_sasha  (or fetch the PR head)." >&2
    return 1
  fi
  _sa_norm() { printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//'; }
  # `--no-show-signature`: a user's `log.showSignature=true` prints a verification line BEFORE the name of a signed
  # commit, so the string never equals the approver and a real self-approval would pass. Belt: a read that still
  # spans more than one line is refused, so no other config that injects a line can slip through.
  _saanr="$(git -C "$ROOT" show -s --no-show-signature --format='%an' "$_said" 2>/dev/null || true)"
  _saaer="$(git -C "$ROOT" show -s --no-show-signature --format='%ae' "$_said" 2>/dev/null || true)"
  case "$_saanr$_saaer" in
    *'
'*) echo "$_saVERB REFUSED: the author of the approved commit $_sasha could not be read as a single line — SoD cannot compare the approver to it." >&2
        return 1 ;;
  esac
  _saan="$(printf '%s' "$_saanr" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  _saae="$(printf '%s' "$_saaer" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  if [ -z "$_saan" ] || [ -z "$_saae" ]; then
    echo "$_saVERB REFUSED: the author of the approved commit $_sasha cannot be read (empty name or email) — SoD cannot compare the approver to it." >&2
    return 1
  fi
  _saby="$(_sa_norm "$_saaby")"
  # A full-ident approver ('Name <email>', or just '<email>') is the author too: compare the whole ident and its <...> part.
  _saident="$(_sa_norm "$_saan <$_saae>")"
  _sainner="$(_sa_norm "$(printf '%s' "$_saaby" | sed -n 's/.*<\([^>]*\)>.*/\1/p')")"
  if [ "$_saby" = "$(_sa_norm "$_saan")" ] || [ "$_saby" = "$(_sa_norm "$_saae")" ] \
     || [ "$_saby" = "$_saident" ] || [ "$_sainner" = "$(_sa_norm "$_saae")" ]; then
    if [ "$_sav" = land ]; then
      echo "LAND REFUSED: approver ('$_saaby') equals the author of the approved commit (builder != ratifier, SoD)." >&2
      echo "              This is a drift control at the GO note's own tier (branch protection is the real" >&2
      echo "              boundary), not authentication; a different person must approve than authored the change." >&2
    else
      echo "$_saVERB REFUSED: approver equals author (builder != ratifier)" >&2
    fi
    return 1
  fi
  return 0
}

# pv_meter_gate <row> <verb> <approved-sha> -> 0 proceed | 1 REFUSED (the refusal is already printed).
# The guard is called with the redirection env SCRUBBED (F2): KIT_RUNAWAY_SANDBOX / RUNAWAY_TALLY /
# RUNAWAY_BUDGET_CONFIG could otherwise point the meter at a tally the caller wrote. The guard is the
# sibling of THIS script ($0), the way pv_release_claim finds board-claim.sh.
pv_meter_gate() {
  _mgrow="$(printf '%s' "$1" | tr -d '[:cntrl:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  _mgverb="$2"; _mgsha="$3"
  _mgVERB="$(printf '%s' "$_mgverb" | LC_ALL=C tr 'a-z' 'A-Z')"
  # An approved sha that does not resolve cannot have its dial read, so the gate cannot prove the tree is not
  # enforcing and REFUSES. This is a BELT: both verbs call pv_sod_author_check first, with the same `^{commit}`
  # predicate against the same $ROOT, and it refuses an unresolvable sha before this gate runs — so this branch is
  # unreachable today from either verb, and kept in case the call order changes. (The land-outside-enforce
  # `return 0` arm below is likewise unreachable today; `record` would refuse such a sha anyway.)
  if ! git -C "$ROOT" rev-parse -q --verify "${_mgsha}^{commit}" >/dev/null 2>&1; then
    if [ "$_mgverb" = land ] && [ "${RUNAWAY_METERING_GATE:-}" != enforce ]; then return 0; fi
    printf '%s\n' "$_mgVERB REFUSED (metering gate): the approved sha does not resolve — cannot read the metering dial" >&2
    return 1
  fi
  _mgmode="$(pv_dial_mode "$_mgsha")"
  [ "$_mgmode" != absent ] || return 0                       # an adopter sees nothing
  if pv_docs_only "$_mgsha"; then
    echo "$_mgverb: metering gate: N/A: docs-only change"; return 0
  fi
  if [ -z "$_mgrow" ] || [ "$_mgrow" = '(none)' ]; then
    if [ "$_mgmode" = enforce ]; then
      echo "$_mgVERB REFUSED (metering gate): cannot meter an unnamed row — the approved commit carries no Kit-Row trailer (or '(none)')." >&2
      return 1
    fi
    echo "$_mgverb: metering gate (observe — not gating): no Kit-Row on the approved commit — cannot meter an unnamed row."
    return 0
  fi
  # An absent guard is decided HERE, not by the shell's exit code for a missing script (bash 127, dash 2).
  if [ ! -f "$(dirname -- "$0")/runaway-guard.sh" ]; then
    if [ "$_mgmode" = enforce ]; then
      printf '%s\n' "$_mgVERB REFUSED (metering gate): the runaway guard script is absent (<path elided>) — cannot meter $_mgrow." >&2
      return 1
    fi
    printf '%s\n' "$_mgverb: metering gate (observe — not gating): the runaway guard script is absent (<path elided>) — cannot meter $_mgrow."; return 0
  fi
  if _mgout="$(env -u KIT_RUNAWAY_SANDBOX -u RUNAWAY_TALLY -u RUNAWAY_BUDGET_CONFIG \
        sh "$(dirname -- "$0")/runaway-guard.sh" meter --row "$_mgrow" 2>&1)"; then _mgrc=0; else _mgrc=$?; fi
  _mgline="$(printf '%s\n' "$_mgout" | grep -E '^(un)?metered: ' | head -1 | tr -d '[:cntrl:]' || true)"
  # printf, never echo, for every line that carries the row or guard text: dash's echo EXPANDS \0NNN, and
  # the row comes from a commit trailer / git note (the echo-sweep lesson of the sync verb).
  case "$_mgrc" in
    0) printf '%s\n' "$_mgverb: $_mgline"; return 0 ;;
    1) _mgfig="${_mgline#metered: "$_mgrow" }"
       PV_STOP_LINE="STOP: $_mgrow $_mgfig — ceiling breached (landed anyway: approved)"
       printf '%s\n' "$PV_STOP_LINE" >&2   # loud NOW (stderr); repeated in the landing report on stdout at the end
       return 0 ;;
    3) # SWAS-302 (owner answer Q2 A2): a row with NO meter line no longer refuses, in enforce or observe.
       # The kit does not meter a conductor's dispatches, so a zero-filled `step` line proved only "metered EVER".
       # The refusals that stay in enforce are the unnamed row, an absent guard, rc 2 and any other rc.
       # This gate no longer catches a forged Kit-Row: row identity is owned by loop-state and backlog-presence.
       if [ "$_mgmode" = enforce ]; then
         printf '%s\n' "$_mgverb: unmetered: $_mgrow (enforce — an unmetered row is not a landing condition)"; return 0
       fi
       printf '%s\n' "$_mgverb: unmetered: $_mgrow (observe — not gating)"; return 0 ;;
    2) _mgreason="$(printf '%s\n' "$_mgout" | grep -v -e '^runaway-guard: budget config ' -e '^runaway-guard: SANDBOX' -e '^WARN' | head -1 | tr -d '[:cntrl:]' | cut -c1-220)"
       if [ -n "${HOME:-}" ]; then
         _mghe="$(printf '%s' "$HOME" | sed 's/[][\\.*^$|]/\\&/g')"
         _mgreason="$(printf '%s' "$_mgreason" | sed "s|${_mghe}[^ ']*|\$HOME…|g")"
       fi
       if [ "$_mgmode" = enforce ]; then
         printf '%s\n' "$_mgVERB REFUSED (metering gate): the meter for $_mgrow could not be read (guard rc 2, fail-closed): $_mgreason" >&2
         return 1
       fi
       printf '%s\n' "$_mgverb: metering gate (observe — not gating): meter unreadable for $_mgrow (guard rc 2): $_mgreason"; return 0 ;;
    *) if [ "$_mgmode" = enforce ]; then
         printf '%s\n' "$_mgVERB REFUSED (metering gate): the meter for $_mgrow exited rc $_mgrc (the guard is missing or crashed — fail-closed)." >&2
         return 1
       fi
       printf '%s\n' "$_mgverb: metering gate (observe — not gating): the meter for $_mgrow exited rc $_mgrc."; return 0 ;;
  esac
}

# pv_merge_cmd_vet <verb> <merge-cmd> -> 0 = the command passes | 1 = REFUSED (already printed, "<VERB> REFUSED: ...").
# THE ONE VET BOTH MERGE VERBS APPLY (SWAS-207a): `land` ran it inline as steps 3b and 4, and `actuate` now runs the
# SAME text, so a caller's --merge-cmd faces the same refusals on either path. Extracted from `land` UNCHANGED (verb
# word aside), so land's refusals are byte-identical. It refuses, in order: (1) any shell metacharacter; (2) any
# branch-deletion flag or short cluster; (3) any --admin form.
#
# (1) REFUSE any --merge-cmd carrying a shell metacharacter ANYWHERE. The eval'd shell can rebuild a --admin or
#     --delete-branch flag from characters the token scan below cannot see: it sees only the PRE-eval bytes and strips
#     only quotes/backslash, but the shell expands/word-splits.
#     The DECLINED SET IS PARITY with the guard's own word-shape vet for a plain command operand —
#     `_cp8b_seg_word_shape_ok` (.claude/hooks/guard-core.sh) refuses `{ } , * ? [`, and its sibling
#     `_cp8b_seg_path_ok` refuses `$ ` backtick ` < > ; & |` — plus `\` (which the guard handles via its own
#     backslash treatment). The verb and the guard therefore agree BY CONSTRUCTION: a merge-cmd character refused
#     here is a character the guard refuses in an operand. Every one is a rebuild vector at eval:
#       $ / backtick  — command/parameter substitution   (--$(echo admin), --`echo admin`)
#       \             — quoting that the token scan strips only its own copy of (\--admin, --del\ete-…)
#       ; & |         — command separators/operators glued to a flag   (--admin; , --admin|x, --admin&&:)
#       < >           — redirections glued to a flag   (--admin>x)
#       { } ,         — brace expansion   (--{admin,} , --ad{m,}in) — THE gap that evaded both land AND
#                       the guard tier: the token scan's `--*` arm swallowed it as an inert flag
#       * ? [         — globbing   (--admi[n]); refused ANYWHERE here (the guard gates the glob only
#                       when LEADING a token because it splits per-token, but the merge-cmd is ONE
#                       eval'd string, so a non-leading glob token is still a rebuild vector).
#     No guard word-shape character is omitted. The default merge-cmd
#     (gh pr merge "<ref>" --squash --match-head-commit "<sha>") carries NONE of these — only letters,
#     digits, spaces, quotes, `/`, `.`, `-`, `:`; $ref and $asha are interpolated and charset-validated
#     ([A-Za-z0-9._/-]) by the caller — so no legitimate merge is refused. Refused as a CLASS here,
#     BEFORE the delete/--admin token scan; that scan then handles the quoted/=value/tab spellings that carry NO
#     metacharacter.
#
# (2)+(3) REFUSE a branch deletion or an --admin bypass. TOKENIZE the merge-cmd on IFS (space/tab/newline) and
#    inspect each token. TRUE SCOPE, no overclaim: the merge-cmd is the AGENT'S OWN string, so this is an ergonomic
#    foot-gun guard at that string's trust tier, not an adversarial parser; it is tokenized (not shell-lexed) and
#    defeatable by an uncooperative caller (the friction-test net stays the CI backstop). It refuses: any
#    --delete-branch/--delete* long flag; any SHORT cluster (single '-', not '--', containing 'd', so
#    -d/-sd/-ds/-dq); and ANY --admin form — bare --admin OR --admin=<value> (F3-1: a merge never needs --admin in
#    ANY form, so the whole --admin=* class is refused — over-refusing the cosmetic --admin=false is the correct,
#    disclosed trade).
#    QUOTE-STRIP each token first (F3-1): the merge-cmd is one string, so a caller who QUOTES a flag
#    ('--delete-branch', "--admin") or SPLITS it across adjacent quotes (--del''ete-branch) leaves the quote bytes
#    on the token here — this is a tokenize, not a shell re-lex. Deleting every ', " and \ normalizes the quoted/split
#    spelling to its bare form before the case. SCOPE OF "no evade" (N1/N3, corrected): this token scan defeats the
#    QUOTED / =value / TAB-separated spellings that carry NO shell metacharacter; every metacharacter spelling —
#    backslash, substitution, brace, glob and glued operator/redirect — is refused UPSTREAM by arm (1) (parity with
#    the guard's word-shape vet), before this loop. The two arms together are what make "none evade" true.
#    The verb NEVER deletes a branch (D-240819-4 — the branch object holds the commit the GO note binds) and NEVER
#    emits a bypass.
#    ⚠️ SCOPE — the GUARD does NOT cover branch deletion via `git push`: `git push origin --delete <b>` and
#    `git push origin :<b>` are guard-ALLOW (uncovered, disclosed; D-240819-6 is about Claude's SETTINGS
#    allow-rules — a prompt — not the guard tier). This matcher scans the merge-cmd precisely because that push form
#    is not covered elsewhere. A `git push origin :<b>` colon-refspec deletion INSIDE a --merge-cmd is out of THIS
#    token scan's scope (a bare `:branch` token carries no shell metacharacter): the friction-test net for it stays
#    the CI backstop + branch protection.
pv_merge_cmd_vet() {
  _mv="$1"; _mvcmd="$2"
  _mvVERB="$(printf '%s' "$_mv" | LC_ALL=C tr 'a-z' 'A-Z')"
  case "$_mvcmd" in
    *'$'* | *'`'* | *'\'* | *'<'* | *'>'* | *';'* | *'&'* | *'|'* | *'{'* | *'}'* | *','* | *'*'* | *'?'* | *'['*)
      echo "$_mvVERB REFUSED: --merge-cmd carries a shell metacharacter — the merge command is eval'd and the" >&2
      echo "              default needs none. The refused set is parity with the guard's word-shape vet:" >&2
      echo "              \$ backtick \\ < > ; & | { } , * ? [. Such a spelling (e.g. \\--admin," >&2
      echo "              --\$(echo admin), --{admin,}, --admi[n], --admin;) can smuggle a --admin or a" >&2
      echo "              --delete-branch past the token scan, which strips only quotes, because the" >&2
      echo "              eval'd shell rebuilds the flag. Re-run with a merge command free of those." >&2
      return 1 ;;
  esac
  _mvdeny=""
  _mvoifs=${IFS-__unset__}
  _mvtab="$(printf '\t')"
  _mvnl='
'
  # Reviewed (SWAS-277): the deliberate tokenizer of the merge vet. IFS is blank/tab/newline only, under `set -f`, restored below on every path; the loop only matches tokens and executes nothing.
  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
  IFS=" $_mvtab$_mvnl"
  set -f
  for _mvtok in $_mvcmd; do
    # Strip every ', " and \ from the token before matching (F3-1 + N1 belt). tr's set is the two
    # quote bytes plus backslash (a token bearing \ was already refused upstream).
    _mvnorm="$(printf '%s' "$_mvtok" | tr -d "\"'\\\\")"
    case "$_mvnorm" in
      --delete-branch|--delete*) _mvdeny='delete' ;;
      --admin|--admin=*)         _mvdeny='admin' ;;
      --*)                       : ;;
      -*d*)                      _mvdeny='delete' ;;
    esac
    if [ -n "$_mvdeny" ]; then break; fi
  done
  set +f
  # Reviewed (SWAS-277): restores the IFS saved above (or unsets it), on every path out of the tokenizer loop.
  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
  if [ "$_mvoifs" = __unset__ ]; then unset IFS; else IFS=$_mvoifs; fi
  if [ "$_mvdeny" = delete ]; then
    echo "$_mvVERB REFUSED: --merge-cmd carries a branch-deletion flag (--delete-branch/--delete or a" >&2
    echo "              short cluster like -d/-sd/-ds) — $_mv NEVER deletes a branch. Deletion is a" >&2
    echo "              separate human act (D-240819-4); the branch object holds the commit the GO" >&2
    echo "              note binds. Re-run without the deletion flag." >&2
    return 1
  fi
  if [ "$_mvdeny" = admin ]; then
    echo "$_mvVERB REFUSED: --merge-cmd carries an --admin token — $_mv NEVER emits a branch-protection" >&2
    echo "              bypass. Approval authorizes promotion, never a bypass (the bypass is the" >&2
    echo "              human's solo kill-switch, denied to the agent by the guard). Re-run without" >&2
    echo "              --admin." >&2
    return 1
  fi
  return 0
}

# pv_actuate_cmd_shape <merge-cmd> -> 0 | 1 REFUSED (already printed). `actuate`'s CALLER-supplied --merge-cmd only
# (SWAS-207a fix round); `land` and pv_merge_cmd_vet are untouched. The vet and the pin check read the command as
# tokens, but the eval'd shell reads it as a program, so these shapes let a command pass both textually while the merge
# runs unpinned: a `#` (the pin sits in a comment), a newline or CR (a second command, or the pin on a dead line), a quote
# character (a quoted value the tokenizer and the shell read differently), and more than one pin token (the first
# decides, the other is inert — or the reverse). Refuse each, naming itself, before any merge.
pv_actuate_cmd_shape() {
  _sh_cmd="$1"; _sh_nl='
'; _sh_cr="$(printf '\r')"
  case "$_sh_cmd" in
    *'#'*) echo "ACTUATE REFUSED: --merge-cmd carries a '#' — a comment could hide the --match-head-commit pin from the shell. Nothing was merged." >&2; return 1 ;;
    *"$_sh_nl"*) echo "ACTUATE REFUSED: --merge-cmd carries a newline — a second command line is not one pinned merge. Nothing was merged." >&2; return 1 ;;
    *"$_sh_cr"*) echo "ACTUATE REFUSED: --merge-cmd carries a carriage return — a line break the tokenizer and the shell read differently. Nothing was merged." >&2; return 1 ;;
    *"'"* | *'"'*) echo "ACTUATE REFUSED: --merge-cmd carries a quote character — a quoted value is read differently by the pin check and the shell. Write the command without quotes. Nothing was merged." >&2; return 1 ;;
  esac
  _sh_n=0
  _sh_oifs=${IFS-__unset__}
  # Reviewed (SWAS-277): the newline was refused above, so IFS is blank/tab only, under `set -f`, restored below; the loop only counts pin tokens and executes nothing.
  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
  IFS=" $(printf '\t')"
  set -f
  for _sh_tok in $_sh_cmd; do
    case "$_sh_tok" in
      --match-head-commit | --match-head-commit=*) _sh_n=$((_sh_n+1)) ;;
    esac
  done
  set +f
  # Reviewed (SWAS-277): restores the IFS saved above (or unsets it).
  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
  if [ "$_sh_oifs" = __unset__ ]; then unset IFS; else IFS=$_sh_oifs; fi
  if [ "$_sh_n" -gt 1 ]; then
    echo "ACTUATE REFUSED: --merge-cmd carries more than one --match-head-commit token ($_sh_n) — exactly one pin, on the approved sha. Nothing was merged." >&2
    return 1
  fi
  return 0
}

# pv_merge_cmd_pins <merge-cmd> <sha> -> 0 only when the command carries a `--match-head-commit` token whose value
# (after the same quote-strip the vet applies) equals <sha>, as `--match-head-commit <sha>` or
# `--match-head-commit=<sha>`. Tokenized, not shell-lexed: the same ergonomic tier as the vet.
pv_merge_cmd_pins() {
  _mpcmd="$1"; _mpsha="$2"; _mppin=1; _mpprev=""
  _mpoifs=${IFS-__unset__}
  _mptab="$(printf '\t')"
  _mpnl='
'
  # Reviewed (SWAS-277): IFS is blank/tab/newline only, under `set -f`, restored below; the loop only compares tokens to the sha and executes nothing.
  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
  IFS=" $_mptab$_mpnl"
  set -f
  for _mptok in $_mpcmd; do
    _mpnorm="$(printf '%s' "$_mptok" | tr -d "\"'\\\\")"
    if [ "$_mpprev" = --match-head-commit ] && [ "$_mpnorm" = "$_mpsha" ]; then _mppin=0; fi
    if [ "$_mpnorm" = "--match-head-commit=$_mpsha" ]; then _mppin=0; fi
    _mpprev="$_mpnorm"
  done
  set +f
  # Reviewed (SWAS-277): restores the IFS saved above (or unsets it).
  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
  if [ "$_mpoifs" = __unset__ ]; then unset IFS; else IFS=$_mpoifs; fi
  return "$_mppin"
}

# pv_origin_note <verb> <sha> -> prints the GO note bound to <sha> as ORIGIN holds it; rc 0 = printed | 1 = REFUSED
# (already printed). The read-back `land` makes (its step 2) and `actuate` now makes too (SWAS-207a A3): a note that
# lives only in this clone is not what CI's recordless-merge backstop reads, so a local `git notes show` would PASS
# on the exact state the #658 hole is made of. Fetch origin's ledger into a PID-scoped throwaway notes ref, read the
# bind on THAT copy, delete it with --no-deref. C2 (the B1 twin): `fetch -f` writes THROUGH a symbolic ref, and a
# plain `update-ref -d` deletes through one, so refuse if ANYTHING is at the name. C1: --refmap= so the fetch cannot
# ALSO update the local ledger.
pv_origin_note() {
  _on="$1"; _onsha="$2"
  _onVERB="$(printf '%s' "$_on" | LC_ALL=C tr 'a-z' 'A-Z')"
  _onref="kit-$_on-origin-$$"
  if _pv_ref_exists "refs/notes/$_onref"; then
    echo "$_onVERB REFUSED: the origin-read ref refs/notes/$_onref already exists (a stale leftover or a planted ref) —" >&2
    echo "              refused before any fetch into it. Inspect it (git for-each-ref refs/notes/$_onref), delete it if stale, then re-run." >&2
    return 1
  fi
  if git fetch --refmap= --no-tags -f origin "refs/notes/$NOTES_REF:refs/notes/$_onref" >/dev/null 2>&1; then
    _onnote="$(git notes --ref="$_onref" show "$_onsha" 2>/dev/null || true)"
  else
    _onnote=""
  fi
  git update-ref --no-deref -d "refs/notes/$_onref" >/dev/null 2>&1 || true
  if [ -z "$_onnote" ]; then
    echo "$_onVERB REFUSED: no GO note bound to $_onsha on origin — nothing was merged. $_on reads the note from ORIGIN" >&2
    echo "              (a local-only note is not what CI's recordless-merge backstop sees). Record and publish it" >&2
    echo "              first: promotion-verify.sh record ... (without --no-push); an unreachable origin refuses too." >&2
    return 1
  fi
  printf '%s\n' "$_onnote"
  return 0
}

# pv_actuate_pick <note> <head-branch> <approved-sha> -> prints the ONE GO record `actuate` judges; rc 1 = REFUSED (printed). SWAS-323:
# a note is a list of records. A note holding exactly ONE GO record is judged as it always was, whatever its gate. Otherwise the
# candidates are the merge-gate GO records (not a typed design or plan gate, not a record of another type): exactly one is judged;
# none is the "no GO note" refusal; several are narrowed to the one whose scope, as PR digits, is the PR whose head is --ref
# (`gh pr view`), and with no single such PR the pick REFUSES, naming every scope, rather than guess.
pv_actuate_pick() {
  _ap_n="$(printf '%s\n' "$1" | kit_note_records n)"; _ap_i=0; _ap_all=0; _ap_nc=0; _ap_cl=""; _ap_ci=0
  while [ "$_ap_i" -lt "$_ap_n" ]; do
    _ap_i=$((_ap_i + 1))
    [ "$(printf '%s\n' "$1" | kit_note_records type "$_ap_i")" = record ] || continue
    _ap_all=$((_ap_all + 1)); _ap_last="$_ap_i"
    _ap_r="$(printf '%s\n' "$1" | kit_note_records body "$_ap_i")"
    if ! pv_go_gate_typed "$(_pv_rec_field "$_ap_r" gate)"; then _ap_nc=$((_ap_nc + 1)); _ap_ci="$_ap_i"; _ap_cl="$_ap_cl $_ap_i"; fi
  done
  if [ "$_ap_all" = 1 ]; then printf '%s\n' "$1" | kit_note_records body "$_ap_last"; return 0; fi
  if [ "$_ap_nc" = 1 ]; then printf '%s\n' "$1" | kit_note_records body "$_ap_ci"; return 0; fi
  if [ "$_ap_nc" = 0 ]; then
    echo "ACTUATE REFUSED: no GO note bound to $3 on origin that holds a merge-gate GO record (the note holds none: only design, plan or other records) — nothing was merged." >&2
    return 1
  fi
  _ap_pr=""
  if command -v gh >/dev/null 2>&1; then _ap_pr="$(gh pr view "$2" --json number --jq .number 2>/dev/null)" || _ap_pr=""; fi
  case "$_ap_pr" in
    ''|*[!0-9]*) _ap_pr="" ;;
  esac
  _ap_hit=0; _ap_hi=0; _ap_names=""
  for _ap_i in $_ap_cl; do
    _ap_sc="$(_pv_rec_field "$(printf '%s\n' "$1" | kit_note_records body "$_ap_i")" scope)"
    _ap_names="$_ap_names '$(printf '%s' "$_ap_sc" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-60)'"
    if [ -n "$_ap_pr" ] && [ "$(pv_ev_pr_number "$_ap_sc" 2>/dev/null || true)" = "$_ap_pr" ]; then _ap_hit=$((_ap_hit + 1)); _ap_hi="$_ap_i"; fi
  done
  if [ "$_ap_hit" = 1 ]; then printf '%s\n' "$1" | kit_note_records body "$_ap_hi"; return 0; fi
  echo "ACTUATE REFUSED: the GO note on $3 holds $_ap_nc merge-gate GO records (scopes:$_ap_names) and none is the single record of the PR whose head is '$2' — nothing was merged." >&2
  echo "                 Judging one of them by position could merge under another PR's GO. Record the GO for one scope per commit, or re-record the one that is current." >&2
  return 1
}

# ---------------------------------------------------------------------------------------------------------------------
# THE MERGE RELATIONSHIP (SWAS-207b; D-241014-1). `solo` or `team`, DECLARED by the repo and read from ORIGIN'S DEFAULT BRANCH.
#   team (the default, and what every unreadable or undeclared case reads): an authenticated non-author forge approval plus
#        the owner's recorded GO — the bar both verbs always had.
#   solo (an explicit `MERGE_RELATIONSHIP=solo` in .kit/dials.conf): one forge account, so the owner's recorded GO, bound to
#        the head sha (pv_solo_go_ok), is the merge control for every class.
# INVERTED KEY: every failure to read reads the STRICTER value. There is no environment variable. The declaration is NOT read
# from the approved tree (a PR that flips team to solo would be judged by the bar it introduces); a flip takes effect only
# after it has merged under the current relationship's bar.
# A DRIFT CONTROL, NOT A BOUNDARY: it reads whatever `origin` resolves to in the agent's own clone, and `git remote set-url` or a
# GIT_CONFIG_* pair can redirect that. What binds is server-side protection where the plan has it, and after-the-fact review of
# the trail (`trace --recent`, the PR's diff of dials.conf).
# ---------------------------------------------------------------------------------------------------------------------
# pv_rel_blob <tip-sha> <path> -> prints the blob of <path> at <tip-sha> (regular files only, like pv_dial_mode); rc 0 = printed |
# 1 = absent | 2 = present but NOT a regular file (a symlink, a gitlink, or a `.kit` that is not a directory).
pv_rel_blob() {
  _rbtip="$1"; _rbpath="$2"; _rbtab="$(printf '\t')"
  _rbent="$(git -C "$ROOT" ls-tree --full-tree "$_rbtip" -- "$_rbpath" 2>/dev/null | head -1 || true)"
  if [ -z "$_rbent" ]; then
    # A symlinked `.kit` makes the path-through lookup return NOTHING, which is indistinguishable from absent: ask for the
    # directory entry itself (the same F-A cure pv_dial_mode carries).
    case "$_rbpath" in
      */*)
        _rbdent="$(git -C "$ROOT" ls-tree --full-tree "$_rbtip" -- "${_rbpath%%/*}" 2>/dev/null | head -1 || true)"
        if [ -n "$_rbdent" ] && [ "${_rbdent%% *}" != 040000 ]; then return 2; fi ;;
    esac
    return 1
  fi
  case "${_rbent%% *}" in
    100644|100755) ;;
    *) return 2 ;;
  esac
  _rbobj="${_rbent#* }"; _rbobj="${_rbobj#* }"; _rbobj="${_rbobj%%"$_rbtab"*}"
  git -C "$ROOT" cat-file blob "$_rbobj" 2>/dev/null
}

# pv_rel_governance <CLAUDE.md text> -> prints `team` | `solo` | `undeclared`. The grammar of conformance/branch-protection.sh
# read_governance (GOV_FIELD, :154-175), RE-STATED here because that script cannot be sourced: ONLY an anchored
# `**Governance** (§ solo/team): <mode>` field line counts; the FIRST word must be exactly `team` or `solo`; more than one field
# line is ambiguous (`team` if ANY says team, else undeclared). KEEP THE TWO IN STEP.
pv_rel_governance() {
  _rgn="$(printf '%s\n' "$1" | grep -c -e '^[-*+[:space:]]*\*\*Governance\*\* (§ solo/team):' || true)"
  if [ "${_rgn:-0}" -lt 1 ]; then echo undeclared; return 0; fi
  _rgvals="$(printf '%s\n' "$1" | sed -n 's#^[-*+[:space:]]*\*\*Governance\*\* (§ solo/team): \([^[:space:]]*\).*$#\1#p')"
  if printf '%s\n' "$_rgvals" | grep -qx 'team'; then echo team; return 0; fi
  if [ "$_rgn" = 1 ] && [ "$_rgvals" = solo ]; then echo solo; else echo undeclared; fi
}

# pv_rel_team <verb> <why> — prints the ONE relationship line for a `team` reading. Never prints note or origin text beyond
# what the caller passes (control bytes are stripped).
pv_rel_team() {
  printf '%s: merge relationship: team (%s)\n' "$1" "$(printf '%s' "$2" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-200)"
}

# pv_merge_relationship <verb> -> sets PV_REL (`solo` | `team`) and prints ONE line saying which, and why when it is team.
# It also keeps what it read for pv_go_dials (SWAS-727), which reads the GO dials from the SAME origin tip: PV_REL_TIP (empty when
# the tip was not read), PV_REL_DIALRC (pv_rel_blob's rc for .kit/dials.conf) and PV_REL_DIALTXT (its text). Plain assignments at
# the top of the script, so no environment variable of these names reaches a verb.
PV_REL=team
PV_REL_TIP=""; PV_REL_DIALRC=1; PV_REL_DIALTXT=""
PV_GO_ACT=absent; PV_GO_GIVERS=""
# SWAS-901: the handover line. The declaring merge is a person's act; from it on the agent merges on the owner's recorded GO. Printed by `actuate` and `land`
# after the relationship line and before the success line, in a SOLO reading only (never team or undeclared); `doctor` prints the same words (a cell locks the two).
PV_HANDOVER_LINE="From here the agent merges on your recorded GO; the owner's per-PR act is the GO only."
pv_handover() {  # <verb>
  [ "$PV_REL" = solo ] || return 0
  printf '%s: %s\n' "$1" "$PV_HANDOVER_LINE"
}
pv_merge_relationship() {
  _mrv="$1"; PV_REL=team; PV_REL_TIP=""; PV_REL_DIALRC=1; PV_REL_DIALTXT=""
  _mrhd="$(GIT_TERMINAL_PROMPT=0 git -C "$ROOT" ls-remote --symref origin HEAD 2>/dev/null | awk '$1 == "ref:" && $3 == "HEAD" { print $2; exit }' || true)"
  case "$_mrhd" in
    refs/heads/?*) ;;
    *) _mrhd=refs/heads/main ;;
  esac
  case "$_mrhd" in
    *[!A-Za-z0-9._/-]*) _mrhd=refs/heads/main ;;
  esac
  _mrbr="${_mrhd#refs/heads/}"
  _mrtip="$(pv_remote_ref_sha "$_mrhd" || true)"
  if [ -z "$_mrtip" ]; then
    pv_rel_team "$_mrv" "cannot read origin's $_mrbr, so the declaration is unreadable and reads team"; return 0
  fi
  if ! git -C "$ROOT" cat-file -e "${_mrtip}^{commit}" 2>/dev/null; then
    pv_rel_team "$_mrv" "origin/$_mrbr tip not fetched, so the declaration is unreadable and reads team until: git fetch origin"; return 0
  fi
  pv_rel_from_tip "$_mrv" "$_mrtip" "$_mrbr"
  return 0
}

# pv_rel_from_tip <verb> <tip-sha> <branch-name> -> the merge relationship read from the commit <tip-sha> (the dial and CLAUDE.md
# AT that commit), set and said exactly as pv_merge_relationship does (SWAS-901: factored out so `go-bound` reads the default branch's tip
# (refs/kit/solo-go-default) with the SAME grammar and no ls-remote). Sets PV_REL, PV_REL_TIP, PV_REL_DIALRC and PV_REL_DIALTXT; prints ONE line.
pv_rel_from_tip() {
  _mrv="$1"; _mrtip="$2"; _mrbr="$3"; PV_REL=team; PV_REL_TIP=""; PV_REL_DIALRC=1; PV_REL_DIALTXT=""
  _mrrc=0; _mrdial="$(pv_rel_blob "$_mrtip" .kit/dials.conf)" || _mrrc=$?
  PV_REL_TIP="$_mrtip"; PV_REL_DIALRC="$_mrrc"; PV_REL_DIALTXT="$_mrdial"
  if [ "$_mrrc" = 2 ]; then
    pv_rel_team "$_mrv" ".kit/dials.conf on origin/$_mrbr is not a regular file (a symlink or other entry), so it is not read"; return 0
  fi
  _mrval=""
  if [ "$_mrrc" = 0 ]; then
    _mrline="$(printf '%s\n' "$_mrdial" | grep -E '^[[:space:]]*MERGE_RELATIONSHIP[[:space:]]*=' | tail -n1 || true)"
    if [ -n "$_mrline" ]; then
      _mrval="$(printf '%s' "$_mrline" | sed -E "s/^[[:space:]]*MERGE_RELATIONSHIP[[:space:]]*=[[:space:]]*//; s/#.*$//; s/[\"']//g; s/[[:space:]].*$//")"
    fi
  fi
  case "$_mrval" in
    solo|team) ;;
    '') _mrval=undeclared ;;
    *) pv_rel_team "$_mrv" "MERGE_RELATIONSHIP='$_mrval' in .kit/dials.conf on origin/$_mrbr is not a recognised value (solo|team), so it reads team"; return 0 ;;
  esac
  _mrgrc=0; _mrgtxt="$(pv_rel_blob "$_mrtip" CLAUDE.md)" || _mrgrc=$?
  _mrgov=undeclared
  if [ "$_mrgrc" = 0 ]; then _mrgov="$(pv_rel_governance "$_mrgtxt")"; fi
  # FAIL-CLOSED: a CLAUDE.md that exists but cannot be read as a regular file (rc 2), or any read failure other than a plain
  # absence (rc 1), reads Governance `team`, so a solo dial can never grant on a Governance line it failed to read.
  if [ "$_mrgrc" != 0 ] && [ "$_mrgrc" != 1 ]; then _mrgov=team; fi
  if [ "$_mrval" = team ]; then pv_rel_team "$_mrv" "MERGE_RELATIONSHIP=team on origin/$_mrbr"; return 0; fi
  if [ "$_mrval" = undeclared ]; then
    if [ "$_mrgov" = solo ]; then
      pv_rel_team "$_mrv" "undeclared: no MERGE_RELATIONSHIP on origin/$_mrbr; CLAUDE.md Governance: solo alone grants nothing"
    else
      pv_rel_team "$_mrv" "undeclared: no MERGE_RELATIONSHIP on origin/$_mrbr"
    fi
    return 0
  fi
  if [ "$_mrgov" = team ]; then
    pv_rel_team "$_mrv" "CLAUDE.md Governance: team overrides MERGE_RELATIONSHIP=solo"; return 0
  fi
  PV_REL=solo
  printf '%s: merge relationship: solo (origin/%s %s) — the recorded GO is the control\n' "$_mrv" "$_mrbr" "$(printf '%s' "$_mrtip" | cut -c1-8)"
  return 0
}

# ---------------------------------------------------------------------------------------------------------------------
# THE MERGE GO'S ACT (SWAS-727; design 2026-11-06-one-act-approval-727-design.md). TEAM MODE ONLY: under `solo` neither dial is
# read. Two dials in .kit/dials.conf, read from the SAME origin default-branch tip as MERGE_RELATIONSHIP (never the approved tree,
# never an environment variable), with the same ceiling (origin can be redirected in the agent's own clone):
#   GO_ACT     absent | unrecognised | unreadable  -> TODAY'S TWO ACTS, exactly (a REVERSED default: the weaker-change value, so
#                                                    nothing breaks for an adopter or a note in flight)
#              separate -> two acts, plus G1 (go-by != approved-by, folded) and G2 (an `actuate` note needs a go-by)
#              review   -> an APPROVED forge review on the exact head by a GO_GIVERS login is the GO (`land` only)
#   GO_GIVERS  space-separated forge logins; EMPTY or unreadable: `review` refuses every merge (it fails closed).
# A CLAUDE.md `**Merge GO**: separate` line can only TIGHTEN to `separate`; no line turns `review` on. Design and plan GOs (the
# gates design* and plan*) stay typed in every mode (pv_go_gate_typed). A DRIFT CONTROL at the note's own tier, not a boundary.
# ---------------------------------------------------------------------------------------------------------------------
# pv_dial_rest <dial text> <KEY> -> the text after `KEY =` on the LAST such line (comment and quotes removed, trimmed).
pv_dial_rest() {
  printf '%s\n' "$1" | grep -E "^[[:space:]]*$2[[:space:]]*=" | tail -n1 \
    | sed -E "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*//; s/#.*$//; s/[\"']//g; s/[[:space:]]*$//" || true
}
# pv_go_gov_separate <CLAUDE.md text> -> 0 when an anchored `**Merge GO**: separate` field line is present (the first word counts).
pv_go_gov_separate() {
  printf '%s\n' "$1" | grep -qE '^[-*+[:space:]]*\*\*Merge GO\*\*: separate([[:space:]]|$)'
}
# pv_go_gate_typed <gate text> -> 0 when the gate is a design or plan gate (folded, trimmed): exactly `design` or `plan`, or
# `design` / `plan` followed by a character that is not a lowercase letter (`design-x`, `design review`, `plan.v2`; so
# `planned-release` is a merge gate); the typed GO stays, in every mode. land and actuate both ask this one function.
pv_go_gate_typed() {
  case "$(printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')" in
    design|plan|design[!a-z]*|plan[!a-z]*) return 0 ;;
  esac
  return 1
}
# pv_go_dials <verb> -> sets PV_GO_ACT (absent | separate | review) and PV_GO_GIVERS, and says so in ONE line unless absent.
# Call it right after pv_merge_relationship. Reads nothing else from the network: it uses what that call kept.
pv_go_dials() {
  _gdv="$1"; PV_GO_ACT=absent; PV_GO_GIVERS=""
  [ "$PV_REL" = team ] || return 0
  [ -n "$PV_REL_TIP" ] || return 0
  _gdact=""; _gdgiv=""
  if [ "$PV_REL_DIALRC" = 0 ]; then
    _gdact="$(pv_dial_rest "$PV_REL_DIALTXT" GO_ACT | sed 's/[[:space:]].*$//')"
    _gdgiv="$(pv_dial_rest "$PV_REL_DIALTXT" GO_GIVERS)"
  fi
  case "$_gdact" in
    review|separate) PV_GO_ACT="$_gdact" ;;
    '') ;;
    *) printf "%s: merge GO: GO_ACT='%s' in .kit/dials.conf on origin is not a recognised value (review|separate), so it reads absent (today's two acts)\n" \
         "$_gdv" "$(printf '%s' "$_gdact" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-40)" ;;
  esac
  # A GO_GIVERS entry outside A-Za-z0-9- is not a forge login: the whole list reads empty (review then refuses), never a partial list.
  _gdgiv="$(printf '%s' "$_gdgiv" | LC_ALL=C tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')"
  case "$_gdgiv" in
    *[!A-Za-z0-9' '-]*) _gdgiv="" ;;
  esac
  _gdgrc=0; _gdgtxt="$(pv_rel_blob "$PV_REL_TIP" CLAUDE.md)" || _gdgrc=$?
  _gdforced=""
  if [ "$_gdgrc" = 0 ]; then
    if pv_go_gov_separate "$_gdgtxt"; then _gdforced=" (CLAUDE.md says Merge GO: separate)"; PV_GO_ACT=separate; fi
  elif [ "$_gdgrc" != 1 ] && [ "$PV_GO_ACT" = review ]; then
    _gdforced=" (CLAUDE.md could not be read as a regular file, so review reads separate)"; PV_GO_ACT=separate
  fi
  PV_GO_GIVERS="$_gdgiv"
  case "$PV_GO_ACT" in
    review)   printf '%s: merge GO: review (an APPROVED forge review on the exact head by one of %s GO_GIVERS login(s) is the GO; land only)\n' "$_gdv" "$(printf '%s\n' "$PV_GO_GIVERS" | wc -w | tr -d ' ')" ;;
    separate) printf '%s: merge GO: separate (two acts; the GO-giver must differ from the reviewer)%s\n' "$_gdv" "$_gdforced" ;;
  esac
  return 0
}
# _pv_fold <text> -> lowercase, whitespace runs collapsed to one space, trimmed (pv_sod_author_check's fold, ASCII only).
_pv_fold() { printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//'; }
# pv_note_goby_name <note> -> the GO-giver's name on the note's go-by line (the label dropped); empty for `(none recorded)` or none.
pv_note_goby_name() {
  _ngn="$(printf '%s\n' "$1" | sed -n 's/^go-by: //p' | head -1)"
  case "$_ngn" in
    '(none recorded)') _ngn="" ;;
    *' ['*) _ngn="${_ngn% \[*}" ;;
  esac
  printf '%s' "$_ngn"
}
# pv_separate_ok <verb> <go-by name> <approved-by id> -> 0 | 1 REFUSED (printed). GO_ACT=separate's two closed gaps: G2 (the GO
# records a giver at all) and G1 (the giver is not the reviewer, folded like pv_sod_author_check). WHAT THIS PROVES, plainly: that a
# different NAME was typed. go-by stays self-asserted, so this guards a mistake; it is not proof a second person decided.
pv_separate_ok() {
  _soV="$(printf '%s' "$1" | LC_ALL=C tr 'a-z' 'A-Z')"
  _sof="$(_pv_fold "$2")"
  if [ -z "$_sof" ]; then
    echo "$_soV REFUSED (GO_ACT=separate): the GO records no GO-giver (go-by is empty or '(none recorded)'). In separate mode the person whose judgment this GO is must be named, and be someone other than the reviewer. Nothing was merged." >&2
    return 1
  fi
  if [ "$_sof" = "$(_pv_fold "$3")" ]; then
    printf '%s\n' "$_soV REFUSED (GO_ACT=separate): the GO-giver ('$(printf '%s' "$2" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-60)') is the reviewer in approved-by (compared folded). In separate mode they must be different people; go-by is self-asserted, so this guards a mistake, it does not prove a second person decided. Nothing was merged." >&2
    return 1
  fi
  return 0
}

# pv_solo_go_ok <verb> <note> <approved-sha> -> 0 = the SOLO BAR holds | 1 = REFUSED (already printed). Runs on the note as
# ORIGIN holds it, replaces the forge-review label bar and the author SoD in a solo-declared repo, and reads every key LINE-ANCHORED
# (never a body scan — a --token/--basis value may legitimately contain any text). Five legs:
#   1. the note binds EXACTLY <approved-sha>;  2. `approved-tree:` is the sha's own tree;  3. `go-by:` names a giver;
#   4. `gate:` is not a pre-build gate (design, plan: a design GO is not a merge GO);  5. `change-class:` is a recorded class.
# WHAT AUTHENTICATES THE SOLO GO: NOTHING. The record says so and no new label is invented: `go-by` is [self-asserted] by design and
# `approval-token:` holds the owner's words. The BINDING is what this checks — sha, tree, origin, and the forge's --match-head-commit
# pin on the merge. A fabricated note that passes these legs merges; only after-the-fact review of the trail catches it.
pv_solo_go_ok() {
  _sgV="$(printf '%s' "$1" | LC_ALL=C tr 'a-z' 'A-Z')"; _sgn="$2"; _sga="$3"
  _sgf() { printf '%s\n' "$_sgn" | sed -n "s/^$1: //p" | head -1; }
  _sgclean() { printf '%s' "$1" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-60; }
  _sgb="$(_sgf approved-sha)"
  if [ "$_sgb" != "$_sga" ]; then
    echo "$_sgV REFUSED (solo bar): the GO note on origin does not bind $_sga exactly (its approved-sha line is '$(_sgclean "$_sgb")') — nothing was merged." >&2
    return 1
  fi
  _sgt="$(_sgf approved-tree)"; _sgw="$(git -C "$ROOT" rev-parse -q --verify "${_sga}^{tree}" 2>/dev/null || true)"
  if [ -z "$_sgw" ] || [ "$_sgt" != "$_sgw" ]; then
    echo "$_sgV REFUSED (solo bar): the note's approved-tree ($(_sgclean "$_sgt")) is not the tree of $_sga — nothing was merged." >&2
    return 1
  fi
  _sgg="$(_sgf go-by)"; _sgname=""
  case "$_sgg" in
    *' [self-asserted]') _sgname="${_sgg%" [self-asserted]"}" ;;
  esac
  if [ -z "$(printf '%s' "$_sgname" | tr -d '[:space:]')" ]; then
    echo "$_sgV REFUSED (solo bar): the note records no named GO-giver (go-by is '$(_sgclean "$_sgg")'; the shape is '<name> [self-asserted]'). In a solo repo the" >&2
    echo "              owner's named GO is the control: record it with --go-by <the GO-giver>. Nothing was merged." >&2
    return 1
  fi
  _sgate="$(_sgf gate | LC_ALL=C tr 'A-Z' 'a-z' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  if [ -z "$_sgate" ]; then
    echo "$_sgV REFUSED (solo bar): the note records no gate (a missing or empty gate: line cannot be shown not to be a pre-build gate) — nothing was merged." >&2
    return 1
  fi
  case "$_sgate" in
    design*|plan*)
      echo "$_sgV REFUSED (solo bar): gate '$(_sgclean "$_sgate")' is a pre-build gate (design or plan) — a design or plan GO is not a merge GO. Record the" >&2
      echo "              merge GO at its own gate (for example release-candidate). Nothing was merged." >&2
      return 1 ;;
  esac
  if ! _pv_class_ok "$(_sgf change-class)"; then
    echo "$_sgV REFUSED (solo bar): the note's change-class is not a recorded class (ordinary | sensitive | control-plane) — nothing was merged." >&2
    return 1
  fi
  return 0
}

# ── EXACT-HEAD CI EVIDENCE (SWAS-537, slice S4 of SWAS-382; design 2026-10-16 §18.5 as revised by §19; closes S3-SEC-2) ──
# A draft PR runs a CHEAP CI (the `changes` job skipped), and marking it ready starts a new run: in the seconds between, the
# forge shows the old run's context state. So `land` and `actuate` merge only when a COMPLETED run of the CI workflow on the EXACT
# approved head graded at least the light set. The predicate is conformance/ci-classify-changes.sh --head-evidence (the very one
# main's push lane uses), run from the same checkout as the verb (main's, for `land`), not from the PR head. The reads are `gh api` GETs over the operator's own
# credential, promoted only on rc 0 and a parseable page. It reads no environment variable and parses no flag.
# SCOPE (H1): the leg belongs to the KIT pipeline. Three facts are read, each at TWO locations (this script's own checkout, and the
# top level of the repository the verb operates on): the decider conformance/ci-gate-state.sh exists, the kit-only marker
# conformance/adopter-census.sh exists, and .github/workflows/ci.yml carries a `gate:` job. BOTH locations kit (all three): the leg
# runs. BOTH adopter (no decider, no marker): ONE N/A line and the verb proceeds. A DISAGREEMENT:
# REFUSED `layout-mismatch`. ANY OTHER combination at either: REFUSED `kit-pipeline-half-present`, so deleting one fact never
# silently disables the leg. CEILING: in the kit repo, a merged reviewed control-plane PR that deletes both the decider and the marker turns later lands to N/A.
# HONEST CEILING: verb-scoped. A raw `gh pr merge`, or the forge's merge button, is outside it; `trace --recent` flags those after
# the fact, and a CI context rename is the server-side layer (out of this slice). The workflow and the `gate` job live in the head.
# TWO LOCATIONS (fix round 2, closes a fail-open): the three facts are read from BOTH the checkout that holds this script AND the
# repository the verb operates on (the top level of the current working repository). A relocated copy or a symlink of the gate, or
# `sh -s`, run from inside a kit-layout repository would otherwise read "adopter" from its own directory and merge a draft. Both
# "kit": the leg runs. Both "adopter": ONE N/A line. ANY disagreement: REFUSED `layout-mismatch`. EITHER "half":
# `kit-pipeline-half-present`. No git repository: `forge-unreadable`, never N/A. Every refusal names both layouts.
# pv_ev_lay_of <root> -> stdout kit | adopter | half (the three facts above, read under that root).
pv_ev_lay_of() {
  # Three facts: the decider, the kit-only marker (conformance/adopter-census.sh, export-ignored and control-plane, so no adopter tree
  # carries it) and the gate job. kit = all three; adopter = neither decider nor marker (an adopter's own `gate:` job cannot change
  # the answer); half = every other combination.
  _pl_dec=0; _pl_mark=0; _pl_gate=0
  if [ -f "$1/conformance/ci-gate-state.sh" ]; then _pl_dec=1; fi
  if [ -f "$1/conformance/adopter-census.sh" ]; then _pl_mark=1; fi
  if grep -q '^  gate:[[:space:]]*$' "$1/.github/workflows/ci.yml" 2>/dev/null; then _pl_gate=1; fi
  case "$_pl_dec$_pl_mark$_pl_gate" in
    111)     printf 'kit\n' ;;
    000|001) printf 'adopter\n' ;;
    *)       printf 'half\n' ;;
  esac
}
# pv_ev_layout -> _pv_ev_layout = kit | adopter | refuse; on refuse _pv_ev_lay_reason names the token. _pv_ev_lay_note names both layouts.
pv_ev_layout() {
  _pl_own="$(pv_ev_lay_of "$(dirname -- "$0")/..")"; _pl_repo=none
  _pl_top="$(git rev-parse --show-toplevel 2>/dev/null)" || _pl_top=""
  if [ -n "$_pl_top" ]; then _pl_repo="$(pv_ev_lay_of "$_pl_top")"; fi
  _pv_ev_lay_note="this script's checkout reads $_pl_own and the repository it operates on reads $_pl_repo"
  _pv_ev_lay_reason=""
  case "$_pl_own/$_pl_repo" in
    kit/kit)         _pv_ev_layout=kit ;;
    adopter/adopter) _pv_ev_layout=adopter ;;
    */none)          _pv_ev_layout=refuse; _pv_ev_lay_reason='forge-unreadable' ;;
    half/*|*/half)   _pv_ev_layout=refuse; _pv_ev_lay_reason='kit-pipeline-half-present' ;;
    *)               _pv_ev_layout=refuse; _pv_ev_lay_reason=layout-mismatch ;;
  esac
}
pv_ev_na_line() { echo "exact-head CI evidence: N/A (not the kit's own CI pipeline)"; }
# pv_ev_pr_number <scope> -> stdout the PR digits (PR #N, PR-N, #N or N); rc 1 when the scope is not a PR id.
pv_ev_pr_number() {
  case "$1" in
    'PR #'*) _pen="${1#PR #}" ;;
    'PR-'*)  _pen="${1#PR-}" ;;
    '#'*)    _pen="${1#\#}" ;;
    *)       _pen="$1" ;;
  esac
  case "$_pen" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "$_pen"
}

# pv_ev_read_in <dir> <pr> <approved-sha> <classifier> : the reads. Sets _pv_ev_verdict (ok | refused | unreadable),
# _pv_ev_reason, _pv_ev_run and _pv_ev_gate (success | absent | other). Any read that fails, pages partially or is not JSON is
# `unreadable`: nothing proves the head was graded.
pv_ev_read_in() {
  _pe_d="$1"; _pe_n="$2"; _pe_a="$3"; _pe_c="$4"
  _pe_meta="$(gh api "repos/{owner}/{repo}/pulls/$_pe_n" \
      --jq '[(.draft | tostring), (.head.sha // ""), (.head.ref // ""), (.base.repo.full_name // ""), (.head.repo.full_name // "")] | @tsv' 2>/dev/null)" || return 0
  _pe_draft="$(printf '%s' "$_pe_meta" | cut -f1)"; _pe_live="$(printf '%s' "$_pe_meta" | cut -f2)"
  _pe_br="$(printf '%s' "$_pe_meta" | cut -f3)"; _pe_repo="$(printf '%s' "$_pe_meta" | cut -f4)"; _pe_hrepo="$(printf '%s' "$_pe_meta" | cut -f5)"
  case "$_pe_draft" in
    true)  _pv_ev_verdict=refused; _pv_ev_reason=draft; return 0 ;;
    false) ;;
    *)     return 0 ;;
  esac
  case "$_pe_live" in
    ''|*[!0-9a-f]*) return 0 ;;
  esac
  { [ "${#_pe_live}" -eq 40 ] && [ -n "$_pe_br" ] && [ -n "$_pe_repo" ]; } || return 0
  # A head in a FORK (or a deleted fork, whose repo reads empty) is not this repository's head: its CI is not the base's evidence.
  if [ "$_pe_hrepo" != "$_pe_repo" ]; then _pv_ev_verdict=refused; _pv_ev_reason='fork-head'; return 0; fi
  # actuate only: --ref must BE the PR's head branch (the shipped merge names it), else the PR read says nothing about the ref merged.
  if [ -n "$_pv_ev_xref" ] && [ "$_pe_br" != "$_pv_ev_xref" ]; then
    _pv_ev_verdict=refused; _pv_ev_reason='ref-mismatch'; return 0
  fi
  # The live head must BE the approved head: a prefix match, and only for a hex sha of 7 or more characters.
  case "$_pe_a" in
    ''|*[!0-9a-f]*) _pv_ev_verdict=refused; _pv_ev_reason='stale-head'; return 0 ;;
  esac
  if [ "${#_pe_a}" -lt 7 ]; then _pv_ev_verdict=refused; _pv_ev_reason='stale-head'; return 0; fi
  case "$_pe_live" in
    "$_pe_a"*) ;;
    *) _pv_ev_verdict=refused; _pv_ev_reason='stale-head'; return 0 ;;
  esac
  gh api "repos/{owner}/{repo}/actions/workflows/ci.yml/runs?head_sha=$_pe_live&event=pull_request&per_page=30" \
      --paginate --jq '.workflow_runs[]' >"$_pe_d/runs.nd" 2>/dev/null || return 0
  jq -s '.' "$_pe_d/runs.nd" >"$_pe_d/runs.json" 2>/dev/null || return 0
  # First pass with an EMPTY jobs listing: it settles every run-level answer, and reaches `no-jobs` only for a completed,
  # successful run on this head, which is the one run whose jobs are worth reading.
  printf '{"jobs":[]}\n' >"$_pe_d/nojobs.json"
  _pe_v="$(sh "$_pe_c" --head-evidence "$_pe_d/runs.json" "$_pe_d/nojobs.json" "$_pe_live" "$_pe_br" "$_pe_repo")" || return 0
  case "$_pe_v" in
    "evidence=no reason=no-jobs run="*) ;;
    "evidence=no reason="*) _pe_r="${_pe_v#evidence=no reason=}"; _pv_ev_verdict=refused; _pv_ev_reason="${_pe_r%% run=*}"
                            case "$_pe_r" in
                              *" run="*) _pv_ev_run="${_pe_r##* run=}" ;;
                            esac
                            return 0 ;;
    *) return 0 ;;
  esac
  _pe_rid="${_pe_v##* run=}"
  case "$_pe_rid" in
    ''|*[!0-9]*) return 0 ;;
  esac
  gh api "repos/{owner}/{repo}/actions/runs/$_pe_rid/jobs?filter=latest&per_page=30" \
      --paginate --jq '.jobs[]' >"$_pe_d/jobs.nd" 2>/dev/null || return 0
  jq -s '.' "$_pe_d/jobs.nd" >"$_pe_d/jobs.json" 2>/dev/null || return 0
  _pe_v="$(sh "$_pe_c" --head-evidence "$_pe_d/runs.json" "$_pe_d/jobs.json" "$_pe_live" "$_pe_br" "$_pe_repo")" || return 0
  _pv_ev_gate="$(jq -r '[.[] | select(.name == "gate") | (.conclusion // "")] | if length == 0 then "absent" elif all(. == "success") then "success" else "other" end' "$_pe_d/jobs.json" 2>/dev/null)" || return 0
  _pv_ev_run="$_pe_rid"
  case "$_pe_v" in
    "evidence=ok reason="*) _pv_ev_verdict=ok; _pv_ev_reason="${_pe_v#evidence=ok reason=}"; _pv_ev_reason="${_pv_ev_reason%% run=*}" ;;
    "evidence=no reason="*) _pe_r="${_pe_v#evidence=no reason=}"; _pv_ev_verdict=refused; _pv_ev_reason="${_pe_r%% run=*}" ;;
  esac
}

# pv_ev_read <pr> <approved-sha> [<head-branch>] : the verdict in _pv_ev_* (defaults: unreadable / forge-unreadable). Never exits the
# caller. A head branch (actuate's --ref) must equal the PR's live head.ref.
pv_ev_read() {
  _pv_ev_verdict=unreadable; _pv_ev_reason='forge-unreadable'; _pv_ev_run=""; _pv_ev_gate=""; _pv_ev_xref="${3:-}"
  _pr_c="$(dirname -- "$0")/../conformance/ci-classify-changes.sh"
  { command -v gh >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && [ -f "$_pr_c" ]; } || return 0
  _pr_d="$(mktemp -d 2>/dev/null)" || return 0
  pv_ev_read_in "$_pr_d" "$1" "$2" "$_pr_c"
  rm -rf "$_pr_d"
  return 0
}

# pv_ci_evidence <land|actuate|evidence> <pr> <approved-sha> <gate-required 0|1> [<head-branch>] : 0 when the head is evidenced (or
# the checkout is not the kit pipeline: ONE N/A line, _pv_ev_na=1); else prints the refusal (the token, the run and what to wait
# for) and returns 1. land also requires the `gate` job at success (a run from before the gate existed is not evidence for a
# control-plane merge); actuate does not. actuate passes its --ref as the head branch, which must be the PR's live head.ref.
pv_ci_evidence() {
  _pc_verb="$(printf '%s' "$1" | LC_ALL=C tr 'a-z' 'A-Z')"; _pc_n="$2"; _pv_ev_na=0
  pv_ev_layout
  if [ "$_pv_ev_layout" = adopter ]; then _pv_ev_na=1; pv_ev_na_line; return 0; fi
  if [ "$_pv_ev_layout" = refuse ]; then _pv_ev_verdict=refused; _pv_ev_reason="$_pv_ev_lay_reason"; _pv_ev_run=""
  elif [ -z "$_pc_n" ]; then _pv_ev_verdict=refused; _pv_ev_reason='no-pr-scope'; _pv_ev_run=""
  else
    pv_ev_read "$_pc_n" "$3" "${5:-}"
    if [ "$_pv_ev_verdict" = ok ] && [ "$4" = 1 ] && [ "$_pv_ev_gate" != success ]; then
      _pv_ev_verdict=refused; _pv_ev_reason='no-gate-job'
    fi
  fi
  [ "$_pv_ev_verdict" != ok ] || return 0
  _pc_tok="$(printf '%s' "$_pv_ev_reason" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-80)"
  _pc_run="${_pv_ev_run:-none selected}"
  _pc_lay_tail=""
  if [ -n "${_pv_ev_lay_reason:-}" ]; then _pc_lay_tail="; $_pv_ev_lay_note"; fi
  case "$_pv_ev_reason" in
    draft)            _pc_wait="PR #$_pc_n is a draft, and a draft runs only the cheap CI: mark it ready, wait for the run on that head to complete, then re-run" ;;
    fork-head)        _pc_wait="PR #$_pc_n has its head in a fork, and a fork's CI run is not this repository's evidence: push the branch to this repository, open the PR from it, then re-run" ;;
    ref-mismatch)     _pc_wait="--ref is not the head branch of PR #$_pc_n: pass the PR's own head branch (gh pr view $_pc_n --json headRefName), at the approved sha" ;;
    kit-pipeline-half-present) _pc_wait="$_pv_ev_lay_note; a kit layout carries all three of conformance/ci-gate-state.sh, conformance/adopter-census.sh and a gate: job in .github/workflows/ci.yml, and an adopter tree has neither the decider nor the marker; this one has some but not all: restore the missing kit fact (conformance/ci-gate-state.sh, conformance/adopter-census.sh, or the gate: job in .github/workflows/ci.yml); removing kit facts is a reviewed control-plane change" ;;
    layout-mismatch)  _pc_wait="$_pv_ev_lay_note, and the leg trusts neither alone: run the gate that lives in the repository you are merging in (its own scripts/promotion-verify.sh), not a copy, a symlink or a piped script" ;;
    stale-head)       _pc_wait="the PR head is no longer the approved sha $3: re-review the new head and re-record the GO" ;;
    no-graded-run)    _pc_wait="no pull_request run of ci.yml exists on this head yet: wait for it to start, then re-run" ;;
    run-not-completed) _pc_wait="run $_pc_run has not completed: wait for it to finish, then re-run" ;;
    run-not-success)  _pc_wait="run $_pc_run did not succeed: fix it or re-run its failed jobs, then re-run" ;;
    needed-job-not-success:*) _pc_wait="run $_pc_run did not grade the light set (a draft or cheap run skips it): mark the PR ready and wait for the full run on this head" ;;
    no-gate-job)      _pc_wait="run $_pc_run carries no gate job at success: re-run CI on this head so it records one" ;;
    no-pr-scope)      _pc_wait="the GO note's scope is not a PR id, so no pull request can be read: record the GO with --scope PR #<n>" ;;
    forge-unreadable) _pc_wait="the forge could not be read here (no git repository, no gh credential, a failed or partial page, or a non-JSON answer): nothing proves this head was graded$_pc_lay_tail" ;;
    *)                _pc_wait="run $_pc_run did not satisfy the exact-head predicate" ;;
  esac
  printf '%s\n' "$_pc_verb REFUSED (exact-head CI evidence): $_pc_tok on head $3 (run: $_pc_run). Wait: $_pc_wait." >&2
  if [ "$1" = land ]; then echo "              No GO note was written and nothing was merged. A draft or cheap run never counts; this closes the mark-ready window." >&2
  else echo "              Nothing was merged. A draft or cheap run never counts; this closes the mark-ready window." >&2; fi
  return 1
}

# ---------------------------------------------------------------------------------------------------------------------
# THE SOLO-GO-BOUND STEP (SWAS-901 slice B). In a solo-declared repository whose origin tip carries the installed workflow
# (.github/workflows/solo-go.yml, COPY & ADAPT), `actuate` and `land` read the HEAD's `solo-go-bound` check runs before they merge:
# every run must be the base's own workflow (path solo-go.yml, event pull_request_target, one run per check suite, run for the default
# branch as the PR's base, app github-actions) or the verb REFUSES at once and re-runs nothing; a red run is re-run once (a late GO
# turns it green: the job reads the live ledger) and waited for, 15 s at a time, up to 600 s. The reads are `gh api` GETs and the one
# POST is the re-run of a failed run; no `--admin`, no write to a ref, a note or a file. In team and undeclared repositories it is a no-op.
# pv_sg_installed -> 0 when the workflow is on the origin tip the relationship was read from (PV_REL_TIP) and carries the kit marker.
pv_sg_installed() {
  [ -n "$PV_REL_TIP" ] || return 1
  _sgi_rc=0; _sgi_txt="$(pv_rel_blob "$PV_REL_TIP" .github/workflows/solo-go.yml)" || _sgi_rc=$?
  [ "$_sgi_rc" = 0 ] || return 1
  printf '%s\n' "$_sgi_txt" | grep -qF 'COPY & ADAPT'
}

# pv_sg_refuse <verb> <why> -> prints the one refusal line (control bytes stripped) and returns 1.
pv_sg_refuse() {
  printf '%s REFUSED (solo-go-bound): %s. Nothing was merged.\n' "$(printf '%s' "$1" | LC_ALL=C tr 'a-z' 'A-Z')" "$(printf '%s' "$2" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-300)" >&2
  return 1
}

# pv_sg_read <pr> <sha> <default-branch> <dir> -> sets _sg_verdict (ok | red | pending | none | foreign | unreadable), _sg_why (foreign) and
# _sg_failed (the failed workflow-run ids). Two GETs, then one awk join of each check run to its workflow run by check-suite id.
pv_sg_read() {
  _sgr_pr="$1"; _sgr_sha="$2"; _sgr_def="$3"; _sgr_d="$4"
  _sg_verdict=unreadable; _sg_why=""; _sg_failed=""
  gh api "repos/{owner}/{repo}/commits/$_sgr_sha/check-runs?check_name=solo-go-bound&per_page=100" --paginate \
    --jq '.check_runs[] | [.id, (.app.slug // ""), (.check_suite.id | tostring), .status, (.conclusion // "")] | @tsv' >"$_sgr_d/cr.tsv" 2>/dev/null || return 0
  gh api "repos/{owner}/{repo}/actions/runs?head_sha=$_sgr_sha&per_page=100" --paginate \
    --jq '.workflow_runs[] | [.id, .path, .event, (.check_suite_id | tostring), (.run_attempt | tostring), .status, (.conclusion // ""), ([.pull_requests[]? | select(.number == '"$_sgr_pr"') | .base.ref] | join(","))] | @tsv' >"$_sgr_d/wr.tsv" 2>/dev/null || return 0
  _sgr_v="$(awk -F '\t' -v def="$_sgr_def" '
    FILENAME == ARGV[1] { cnt[$4]++; rid[$4] = $1; pth[$4] = $2; evt[$4] = $3; bas[$4] = $8; next }
    {
      total++
      if ($2 != "github-actions") { print "foreign app " $2; fin = 1; exit }
      if (cnt[$3] != 1) { print "foreign check suite " $3 " joins " cnt[$3] " workflow runs, not one"; fin = 1; exit }
      if (pth[$3] != ".github/workflows/solo-go.yml" || evt[$3] != "pull_request_target") { print "foreign run " rid[$3] " " pth[$3] " " evt[$3]; fin = 1; exit }
      if (bas[$3] != def) { print "foreign base " bas[$3] " (run " rid[$3] ")"; fin = 1; exit }
      if ($4 != "completed") pend = 1
      else if ($5 != "success") { red = 1; ids = ids ((ids == "") ? "" : " ") rid[$3] }
    }
    END {
      if (fin) exit
      if (total == 0) print "none"
      else if (red) print "red " ids
      else if (pend) print "pending"
      else print "ok"
    }' "$_sgr_d/wr.tsv" "$_sgr_d/cr.tsv")" || return 0
  case "$_sgr_v" in
    none|pending|ok) _sg_verdict="$_sgr_v" ;;
    "red "*)     _sg_verdict=red; _sg_failed="${_sgr_v#red }" ;;
    "foreign "*) _sg_verdict=foreign; _sg_why="${_sgr_v#foreign }" ;;
  esac
}

# pv_sg_gate <verb> <pr> <sha> <default-branch> -> 0 = proceed (not solo, not installed, or the check is green), 1 = refused (printed).
# PROMOTION_VERIFY_SG_POLL (digits) can only SHORTEN the 600 s wait, and a shorter wait can only end in a refusal, never a merge.
pv_sg_gate() {
  _sgv="$1"; _sgp="$2"; _sgs="$3"; _sgdef="$4"
  [ "$PV_REL" = solo ] || return 0
  if ! pv_sg_installed; then
    printf '%s: solo-go-bound: not installed on origin/%s; this step does not apply (the forge'"'"'s protection is what binds)\n' "$_sgv" "$_sgdef"
    return 0
  fi
  if ! command -v gh >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    pv_sg_refuse "$_sgv" "solo-go-bound is installed here and gh and jq are needed to read it, and one is missing"; return 1
  fi
  case "$_sgp" in
    ''|*[!0-9]*) pv_sg_refuse "$_sgv" "the GO note's scope names no pull request, so its solo-go-bound runs cannot be read"; return 1 ;;
  esac
  _sgs="$(git -C "$ROOT" rev-parse -q --verify "${_sgs}^{commit}" 2>/dev/null || true)"
  if [ -z "$_sgs" ]; then pv_sg_refuse "$_sgv" "the approved head is not a commit in this clone"; return 1; fi
  # E6 S-5: `actuate` passes its --ref; the PR the note's scope names must be the pull request whose head IS that ref at the approved sha (`land` binds scope == ref itself).
  if [ -n "${5:-}" ] && [ "$5" != "$_sgp" ] && [ "$(gh api "repos/{owner}/{repo}/pulls/$_sgp" --jq '[.head.ref, .head.sha] | @tsv' 2>/dev/null || true)" != "$(printf '%s\t%s' "$5" "$_sgs")" ]; then pv_sg_refuse "$_sgv" "the GO note's PR #$_sgp is not the pull request whose head is '$5' at the approved sha"; return 1; fi   # MUT-SG-BIND
  _sgb=600
  case "${PROMOTION_VERIFY_SG_POLL:-}" in
    ''|*[!0-9]*) ;;
    *) if [ "${#PROMOTION_VERIFY_SG_POLL}" -le 3 ] && [ "$PROMOTION_VERIFY_SG_POLL" -lt 600 ]; then _sgb="$PROMOTION_VERIFY_SG_POLL"; fi ;;
  esac
  _sgstep=15; if [ "$_sgb" -lt "$_sgstep" ]; then _sgstep="$_sgb"; fi
  _sgd="$(mktemp -d 2>/dev/null)" || { pv_sg_refuse "$_sgv" "no temporary directory for the forge reads"; return 1; }
  _sgt=0; _sgrr=""
  while :; do
    pv_sg_read "$_sgp" "$_sgs" "$_sgdef" "$_sgd"
    case "$_sg_verdict" in
      ok)
        rm -rf "$_sgd"
        printf '%s: solo-go-bound: green on the head, from the base'"'"'s own workflow\n' "$_sgv"
        return 0 ;;
      foreign)
        rm -rf "$_sgd"
        pv_sg_refuse "$_sgv" "a solo-go-bound check on this head is not the base's own workflow ($_sg_why), so nothing was re-run and the check is not trusted"; return 1 ;;
      unreadable)
        rm -rf "$_sgd"
        pv_sg_refuse "$_sgv" "the forge could not be read for the head's solo-go-bound runs (a failed, partial or non-TSV answer), so nothing proves the GO binds it"; return 1 ;;
      red)
        for _sgi in $_sg_failed; do
          case "$_sgi" in
            ''|*[!0-9]*) continue ;;
          esac
          case " $_sgrr " in
            *" $_sgi "*) continue ;;
          esac
          if ! gh api -X POST "repos/{owner}/{repo}/actions/runs/$_sgi/rerun-failed-jobs" >/dev/null 2>&1; then
            rm -rf "$_sgd"
            pv_sg_refuse "$_sgv" "solo-go-bound run $_sgi is red and the forge refused its re-run, so the check cannot turn green by itself"; return 1
          fi
          _sgrr="$_sgrr $_sgi"
        done ;;
    esac
    if [ "$_sgt" -ge "$_sgb" ]; then
      rm -rf "$_sgd"
      if [ "$_sg_verdict" = none ]; then pv_sg_refuse "$_sgv" "no solo-go-bound run exists on this head after ${_sgt}s: trigger one (push, or close and reopen the PR), then re-run this command"; return 1; fi   # MUT-SG-NONE
      pv_sg_refuse "$_sgv" "the recorded GO on origin does not bind this head (solo-go-bound is ${_sg_verdict}${_sg_failed:+, run $_sg_failed} after ${_sgt}s): read the run's log, record the GO on this head, then re-run this command"; return 1
    fi
    sleep "$_sgstep"; _sgt=$((_sgt + _sgstep))
  done
}

# do_evidence — the READ-ONLY verb behind the leg (SWAS-537, D4): `evidence --pr <n> --approved-sha <sha>` prints whether `land` would find
# exact-head CI evidence for that head right now, so an agent checks BEFORE a GO ask. Exit 0 = evidenced, 1 = refused (the token and
# the wait are printed), 2 = usage. It writes nothing, records nothing and merges nothing. It asks `land`'s question, the gate job included.
do_evidence() {
  _ev_pr=""; _ev_sha=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --pr)           [ $# -ge 2 ] || { echo "evidence: --pr needs a value" >&2; return 2; }
                      _ev_pr="$2"; shift 2 ;;
      --approved-sha) [ $# -ge 2 ] || { echo "evidence: --approved-sha needs a value" >&2; return 2; }
                      _ev_sha="$2"; shift 2 ;;
      *) echo "evidence: unknown arg '$1'" >&2; usage; return 2 ;;
    esac
  done
  if [ -z "$_ev_pr" ] || [ -z "$_ev_sha" ]; then echo "evidence: --pr and --approved-sha are required" >&2; usage; return 2; fi
  case "$_ev_pr" in
    ''|*[!0-9]*) echo "evidence: --pr takes a PR number (digits only)" >&2; return 2 ;;
  esac
  case "$_ev_sha" in
    ''|*[!0-9a-f]*) echo "evidence: --approved-sha takes a lowercase hex commit id" >&2; return 2 ;;
  esac
  _ev_full="$(git -C "$ROOT" rev-parse -q --verify "${_ev_sha}^{commit}" 2>/dev/null || true)"
  pv_ci_evidence evidence "$_ev_pr" "${_ev_full:-$_ev_sha}" 1 || return 1
  if [ "$_pv_ev_na" = 1 ]; then return 0; fi
  echo "OK: exact-head CI evidence on ${_ev_full:-$_ev_sha} (PR #$_ev_pr): reason=$_pv_ev_reason run=$_pv_ev_run gate=$_pv_ev_gate - read-only, nothing was recorded or merged."
}

# pv_go_bound_pick <note> <pr-digits> -> prints the ONE merge-gate GO record scoped to that PR; rc 1 when there is not exactly one (SWAS-901).
# `go-bound` keeps only records of type `record` that are not a typed design or plan gate (pv_go_gate_typed) and whose `scope:` reads, as PR
# digits (pv_ev_pr_number), to <pr>. Zero or several are rc 1, never a guess. It is NOT pv_actuate_pick: no `gh` call and no one-record
# shortcut, so a lone record scoped to another PR is not judged here.
pv_go_bound_pick() {
  _gp_n="$(printf '%s\n' "$1" | kit_note_records n)"; _gp_i=0; _gp_kept=0; _gp_rec=""
  while [ "$_gp_i" -lt "$_gp_n" ]; do
    _gp_i=$((_gp_i + 1))
    [ "$(printf '%s\n' "$1" | kit_note_records type "$_gp_i")" = record ] || continue
    _gp_r="$(printf '%s\n' "$1" | kit_note_records body "$_gp_i")"
    if pv_go_gate_typed "$(_pv_rec_field "$_gp_r" gate)"; then continue; fi
    [ "$(pv_ev_pr_number "$(_pv_rec_field "$_gp_r" scope)" 2>/dev/null || true)" = "$2" ] || continue
    _gp_kept=$((_gp_kept + 1))
    if [ "$_gp_kept" = 1 ]; then _gp_rec="$_gp_r"; fi
  done
  [ "$_gp_kept" = 1 ] || return 1
  printf '%s\n' "$_gp_rec"
}

# _gb_say <word> [<reason>] -> THE one `go-bound:` line (control bytes stripped from the reason, 160 characters at most).
_gb_say() {
  if [ -n "${2:-}" ]; then printf 'go-bound: %s %s\n' "$1" "$(printf '%s' "$2" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-160)"
  else printf 'go-bound: %s\n' "$1"; fi
}

# pv_gb_declared <tip> -> 0 when REQUIRED-CHECKS.md at <tip> declares solo-go-bound on a line of its own (E6 S-1): protection then holds that check, so a default
# branch that stopped reading solo must not read a green `na`. Absent or unreadable reads "not declared" (a team adopter that never declared it stays `na`).
pv_gb_declared() {   # rc 0 = declared | 1 = not declared (absent included) | 2 = present but not a regular file, or unreadable (reads as declared by the caller: fail closed)
  _gd_rc=0; _gd_t="$(pv_rel_blob "$1" REQUIRED-CHECKS.md)" || _gd_rc=$?
  if [ "$_gd_rc" = 1 ]; then return 1; fi
  if [ "$_gd_rc" != 0 ]; then return 2; fi
  # the declaration is the FIRST fenced block only, as every declaration reader reads it (a later block is a usage example), one name per line, comments ignored
  printf '%s\n' "$_gd_t" | awk '/^```/ { if (done) next; if (inb) { done = 1; inb = 0 } else inb = 1; next } inb { l = $0; sub(/^[ \t]+/, "", l); sub(/[ \t]+$/, "", l); if (l == "solo-go-bound") f = 1 } END { exit f ? 0 : 1 }'
}

# FOR CI: the solo-go-bound workflow fetches refs/kit/solo-go-default itself. Run locally, the verb reads whatever that ref holds in YOUR clone.
# do_go_bound — SWAS-901: the READ-ONLY check behind the solo-go-bound workflow (profiles/solo-go.yml), run from the checked-out BASE branch.
# `go-bound --approved-sha <40-hex> --pr <digits> --base-ref <name> --default-branch <name>` prints exactly ONE line on stdout,
# `go-bound: na|ok|missing|error [reason]`, rc 0 for na, ok and missing and rc 2 for error. It reads the merge relationship from the DEFAULT branch's tip, which the
# workflow fetched as objects into refs/kit/solo-go-default (never the PR head, never the PR's own base, which a PR can retarget), and the GO note from the LOCAL notes ref (the workflow fetched it; this verb never fetches, so it needs no
# credential), judges it with pv_solo_go_ok, and writes no ref, no note and no file. na = the base reads team; ok = one merge-gate GO record
# scoped to this PR binds exactly this head; missing = it does not; error = it could not be judged (red).
do_go_bound() {
  _gb_sha=""; _gb_pr=""; _gb_base=""; _gb_def=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --approved-sha|--pr|--base-ref|--default-branch)
        [ $# -ge 2 ] || { _gb_say error "usage: $1 needs a value"; return 2; }
        case "$1" in
          --approved-sha)   _gb_sha="$2" ;;
          --pr)             _gb_pr="$2" ;;
          --base-ref)       _gb_base="$2" ;;
          --default-branch) _gb_def="$2" ;;
        esac
        shift 2 ;;
      *) _gb_say error "usage: unknown arg '$1'"; return 2 ;;
    esac
  done
  case "$_gb_sha" in
    ''|*[!0-9a-f]*) _gb_say error "usage: --approved-sha takes a lowercase hex commit id (40 characters)"; return 2 ;;
  esac
  if [ "${#_gb_sha}" != 40 ]; then _gb_say error "usage: --approved-sha takes a lowercase hex commit id (40 characters)"; return 2; fi
  case "$_gb_pr" in
    ''|*[!0-9]*) _gb_say error "usage: --pr takes a PR number (digits only)"; return 2 ;;
  esac
  for _gb_n in "$_gb_base" "$_gb_def"; do
    case "$_gb_n" in
      ''|-*|*[!A-Za-z0-9._/-]*) _gb_say error "usage: --base-ref and --default-branch take a branch name (allowed chars: A-Za-z0-9._/-)"; return 2 ;;
    esac
  done
  _gb_tip="$(git -C "$ROOT" rev-parse -q --verify "refs/kit/solo-go-default^{commit}" 2>/dev/null || true)"
  if [ -z "$_gb_tip" ]; then _gb_say error "the default branch tip is not fetched (refs/kit/solo-go-default)"; return 2; fi
  pv_rel_from_tip go-bound "$_gb_tip" "$_gb_def" >/dev/null
  _gb_dr=1; if [ "$PV_REL" != solo ]; then _gb_dr=0; pv_gb_declared "$_gb_tip" || _gb_dr=$?; fi
  if [ "$_gb_dr" != 1 ]; then _gb_say error "the default branch declares solo-go-bound (or its declaration is unreadable) but no longer reads solo; leaving solo needs --replace --team in the same step"; return 2; fi   # E6 S-1
  if [ "$PV_REL" != solo ]; then _gb_say na; return 0; fi
  if [ "$_gb_base" != "$_gb_def" ]; then
    _gb_say error "solo merges target the default branch ($_gb_def), and this PR targets $_gb_base"; return 2
  fi
  if ! git -C "$ROOT" cat-file -e "${_gb_sha}^{commit}" 2>/dev/null; then
    _gb_say error "head commit not fetched ($(printf '%s' "$_gb_sha" | cut -c1-8))"; return 2
  fi
  _gb_note="$(git -C "$ROOT" notes --ref="$NOTES_REF" show "$_gb_sha" 2>/dev/null || true)"
  if [ -z "$_gb_note" ]; then _gb_say missing "no GO note on $(printf '%s' "$_gb_sha" | cut -c1-8)"; return 0; fi
  if ! _gb_rec="$(pv_go_bound_pick "$_gb_note" "$_gb_pr")"; then
    _gb_say missing "no single merge-gate GO record scoped to PR #$_gb_pr in the note on $(printf '%s' "$_gb_sha" | cut -c1-8)"; return 0
  fi
  if _gb_err="$(pv_solo_go_ok go-bound "$_gb_rec" "$_gb_sha" 2>&1 >/dev/null)"; then
    echo "go-bound: ok"; return 0
  fi
  _gb_say missing "$(printf '%s\n' "$_gb_err" | head -n 1)"
  return 0
}

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
  case "$ref" in
    -*) echo "actuate: invalid --ref '$ref' (must not start with '-')" >&2; return 2 ;;
  esac
  case "$asha" in
    -*) echo "actuate: invalid --approved-sha '$asha' (must not start with '-')" >&2; return 2 ;;
  esac
  # Charset-validate (defense-in-depth): a real ref/tag/PR-number/SHA contains only [A-Za-z0-9._/-].
  # $ref is interpolated into the default merge_cmd eval below, so reject any metacharacter outright —
  # the gate must never be a shell-injection primitive even though the caller is already the agent.
  case "$ref" in
    *[!A-Za-z0-9._/-]*) echo "actuate: invalid --ref '$ref' (allowed chars: A-Za-z0-9._/-)" >&2; return 2 ;;
  esac
  case "$asha" in
    *[!A-Za-z0-9._/-]*) echo "actuate: invalid --approved-sha '$asha' (allowed chars: A-Za-z0-9._/-)" >&2; return 2 ;;
  esac
  # Default merge = the sanctioned NORMAL squash merge (no branch-protection bypass flag is ever
  # emitted here; see the header comment). Swapped for a stub in tests.
  # A CALLER-supplied command faces the extra shape refusals below; the default does not need them.
  _act_caller=0; [ -z "$merge_cmd" ] || _act_caller=1

  # 0. --ref MUST BE THE PR'S HEAD BRANCH, AT THE APPROVED SHA — checked BEFORE anything is read or merged (A2).
  #    `--ref` resolves AND its commit equals the approved sha's commit, else nothing runs. A bare PR number with no
  #    local ref, a branch that has moved past the GO, and a ref that does not exist all refuse here. (The tag form is
  #    dropped: `gh pr merge <tag>` merges nothing. The merged-ref form is retired: it exists only AFTER the merge.)
  _act_rc="$(git -C "$ROOT" rev-parse -q --verify "$ref^{commit}" 2>/dev/null || true)"
  _act_full="$(git -C "$ROOT" rev-parse -q --verify "$asha^{commit}" 2>/dev/null || true)"
  if [ -z "$_act_rc" ] || [ -z "$_act_full" ] || [ "$_act_rc" != "$_act_full" ]; then
    echo "ACTUATE REFUSED: --ref '$ref' resolves to ${_act_rc:-nothing}, not the approved sha ${_act_full:-$asha} — nothing was merged." >&2
    echo "                 --ref is the PR's head branch, fetched at the approved sha: git fetch origin <branch>:<branch>" >&2
    return 2
  fi
  # From here the approved sha is the FULL sha step 0 resolved (N3): the pin, the origin read and every later read use
  # one spelling, whatever abbreviation the caller typed.
  asha="$_act_full"

  # Default merge = the sanctioned NORMAL squash merge (no branch-protection bypass flag is ever emitted here; see the
  # header comment). PINNED to the approved head (--match-head-commit), exactly as `land`'s: a head pushed after the GO
  # is rejected server-side instead of merged under a note bound to the older sha (SWAS-207a A1). Swapped for a stub in tests.
  [ -n "$merge_cmd" ] || merge_cmd="gh pr merge \"$ref\" --squash --match-head-commit \"$asha\""

  # 0b. THE MERGE COMMAND IS VETTED AND PINNED (A1). A caller's --merge-cmd passes through the SAME vet `land` applies
  #     (metacharacters, branch deletion, every admin-bypass spelling), faces the caller-only shape refusals
  #     (pv_actuate_cmd_shape), and must carry exactly one `--match-head-commit <approved-sha>`.
  #     HONEST CEILING: the command is the agent's own string — an ergonomic guard at that string's trust tier,
  #     not a parser an uncooperative caller cannot evade. What REMAINS after these refusals: a caller that runs a
  #     different binary carrying the pin token (a no-op, say) passes the textual check, because a tokenized string
  #     cannot prove what the eval'd shell will execute. The pin binds the forge's merge only when the command really
  #     is the forge's merge; the server-side `--match-head-commit` and CI's `trace --recent` are what bind.
  if [ "$_act_caller" = 1 ]; then pv_actuate_cmd_shape "$merge_cmd" || return 1; fi
  pv_merge_cmd_vet actuate "$merge_cmd" || return 1
  if ! pv_merge_cmd_pins "$merge_cmd" "$asha"; then
    echo "ACTUATE REFUSED: --merge-cmd must pin --match-head-commit <approved-sha> ($asha) — nothing was merged." >&2
    echo "                 Without the pin a head pushed after the GO would merge under a note bound to the older sha." >&2
    return 1
  fi

  # 1. A GO note must bind EXACTLY this sha, as ORIGIN holds it (A3): a local-only or hand-written note is not what
  #    CI's recordless-merge backstop reads. Same read-back `land` makes; a fetch that fails refuses too.
  if ! note="$(pv_origin_note actuate "$asha")"; then return 1; fi
  #    SWAS-323: the note is a LIST of records; every step below judges ONE merge-gate GO record, selected here.
  if ! note="$(pv_actuate_pick "$note" "$ref" "$asha")"; then return 1; fi

  # 1b. CONTROL-PLANE IS NOT MERGED HERE — IT GOES THROUGH `land`, IN BOTH RELATIONSHIPS (D-241014-1 item 6: the owner CLOSED the
  #     Tier-3 sitting). This arm is a POINTER, and it runs BEFORE any label or relationship judgment: a control-plane note with ANY
  #     label (authenticated, or [committer] in a team repo) gets the exact `land` command, never the "does not meet the
  #     control-plane bar" refusal below, and the unknown-class refusal also precedes any label judgment. Nothing gets weaker: the
  #     same notes are refused, only the first message changes. `land` already holds the stronger transaction (record, confirm on
  #     origin, vet, pin); routing control-plane there gives `actuate` no new power over it.
  #     HONEST TIER: `change-class:` is CALLER-RECORDED, so this is a DRIFT CONTROL at the note's own trust tier, never a
  #     boundary. Read LINE-ANCHORED from the `change-class:` line only (never a body scan — the S5a decoy lesson) and matched
  #     EXACTLY after case-folding (a substring test would refuse a legitimate class merely containing the word).
  cls_line="$(printf '%s\n' "$note" | grep '^change-class:' | head -1 || true)"
  cls_val="${cls_line#change-class:}"
  cls_val="$(printf '%s' "$cls_val" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  cls_lc="$(printf '%s' "$cls_val" | LC_ALL=C tr 'A-Z' 'a-z')"
  cls_val="$(printf '%s' "$cls_val" | LC_ALL=C tr -d '[:cntrl:]')"   # N4: judged raw above, echoed clean below
  # AN ALLOWLIST, NOT A DENYLIST (security review F2). A denylist on "control-plane" fails OPEN on everything it does not
  # recognise: a note with NO `change-class:` line at all, or a typo'd value, or a class this vocabulary gains later, would all
  # sail through the refusal and be merged. Since the note is caller-recorded, that is a one-character evasion. Proceed ONLY for
  # the two classes this subcommand is wired for; everything else — missing, empty, unrecognised — refuses with its own reason.
  # `record` validates the same vocabulary at the front door, so a note reaching here with an unrecognised class was written by
  # something other than `record`, which is worth saying out loud.
  case "$cls_lc" in
    ordinary|sensitive) ;;
    control-plane)
      echo "ACTUATE REFUSED: change-class '$cls_val' — control-plane merges go through land, in both relationships (D-241014-1 item 6). Nothing was merged. Run:" >&2
      echo "  sh scripts/promotion-verify.sh land --ref <PR number> --approved-sha $asha --class control-plane --scope \"PR #<PR number>\" --go-by <the GO-giver> --approved-by <reviewer login> --gate merge --rung integration --token \"<the owner's words>\"" >&2
      echo "land's --ref is the PR NUMBER (it must equal --scope), not actuate's head branch." >&2
      return 1 ;;
    *)
      echo "ACTUATE REFUSED: unrecognised or missing change-class '$cls_val' — this gate proceeds only" >&2
      echo "                 for an explicitly recorded 'ordinary' or 'sensitive' class (allowlist)." >&2
      echo "                 A note with no class, or one this vocabulary does not know, cannot be" >&2
      echo "                 judged, and an unjudgeable class is never a permission. Re-record the GO" >&2
      echo "                 with \`record --class <ordinary|sensitive|control-plane>\`." >&2
      return 1 ;;
  esac

  # 1c. THE MERGE RELATIONSHIP (D-241014-1), read from origin's default branch and said in ONE line before anything merges.
  pv_merge_relationship actuate
  pv_handover actuate   # MUT-HO-REL
  #     SWAS-727: the merge GO's act. In REVIEW mode `actuate` merges NOTHING: it trusts a label `record` wrote earlier and never re-reads
  #     the forge, so only `land` (which reads it live) can honour a later Request changes as the NO-GO. A design or plan gate stays typed
  #     in every mode, so it is judged as before. SEPARATE adds G1 and G2 below, in the team arm, once the approver id is known.
  pv_go_dials actuate
  _act_mode="$PV_GO_ACT"
  if pv_go_gate_typed "$(printf '%s\n' "$note" | sed -n 's/^gate: //p' | head -1)"; then _act_mode=absent; fi
  if [ "$_act_mode" = review ]; then
    echo "ACTUATE REFUSED (GO_ACT=review): in review mode an APPROVED forge review by a GO_GIVERS login is the merge GO and only \`land\` reads it live, so actuate merges nothing. Nothing was merged. Run:" >&2
    echo "  sh scripts/promotion-verify.sh land --ref <PR number> --approved-sha $asha --class <the class> --scope \"PR #<PR number>\" --approved-by <the GO-giver's reviewer login> --gate merge --rung integration" >&2
    echo "land's --ref is the PR NUMBER (it must equal --scope), not actuate's head branch; an empty-body approval takes no --token or --go-by." >&2
    return 1
  fi

  # 2. SOLO: the solo bar (the owner's named GO, bound to the sha, the tree and origin; pv_solo_go_ok) REPLACES the label bar
  #    below and the author SoD at step 3 — with one forge account the approver is the author by construction. TEAM (the default,
  #    and every undeclared or unreadable case) is exactly what it always was. The team body below is deliberately NOT re-indented,
  #    so this change leaves steps 2 and 3 themselves byte-identical.
  if [ "$PV_REL" = solo ]; then
    pv_solo_go_ok actuate "$note" "$asha" || return 1
  else

  # 2 (team). Read the DERIVED label from the `approved-by:` line ONLY — extract the trailing [...] on that
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
    label="$(printf '%s' "$label" | LC_ALL=C tr -d '[:cntrl:]')"   # N4: note-derived text never carries a control byte to the terminal
    echo "ACTUATE REFUSED: assurance '$label' does not meet the control-plane bar ([authenticated: <forge>-review] required)" >&2
    return 1
  fi

  # (2b, the control-plane refusal, moved ahead of step 2 — see 1b above.)

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
  #    The author read, its fail-closed refusals (commit absent from this clone / unreadable author) and the
  #    case- and whitespace-insensitive compare live in pv_sod_author_check (shared with `land`).
  pv_sod_author_check actuate "$asha" "$aby_id" || return 1
  #    GO_ACT=separate (SWAS-727): G2 (the note records a GO-giver) and G1 (the giver is not the approver), judged on the note.
  if [ "$_act_mode" = separate ]; then pv_separate_ok actuate "$(pv_note_goby_name "$note")" "$aby_id" || return 1; fi
  fi   # closes the team arm (steps 2-3); the metering gate below runs in BOTH relationships

  # 3b. THE PER-SLICE METERING GATE (RUNAWAY-METERING-LANDING-GATE): after SoD, BEFORE the merge, so a
  #     refusal attempts no merge. The row is the note's OWN `kit-row:` projection (the same read
  #     pv_release_claim makes). NO new note key. ⚠️ The GO note ALREADY EXISTS (`record` is a separate
  #     verb), so a refusal here leaves a recorded-but-unmerged GO — the recordless-merge backstop is
  #     unaffected (design F5c).
  _act_mrow_line="$(printf '%s\n' "$note" | grep '^kit-row:' | head -1 || true)"
  #     fix round 3 (F-C): in ENFORCE the note's row must equal the approved commit's own Kit-Row trailer —
  #     `record` never writes a mismatch, so one is a hand-written note naming an already-metered row. No
  #     trailer on the commit keeps today's behaviour (the no-row rule reads the note's value). The mode is
  #     read quietly here; pv_meter_gate re-reads it and prints the WARNs once.
  if [ "$(pv_dial_mode "$asha" 2>/dev/null)" = enforce ]; then
    _act_trow="$(git -C "$ROOT" log -1 --no-show-signature --format='%(trailers:key=Kit-Row,valueonly)' "$asha" 2>/dev/null | sed -n '1p' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true)"
    _act_nrow="$(printf '%s' "${_act_mrow_line#kit-row:}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    if [ -n "$_act_trow" ] && [ "$_act_trow" != "$_act_nrow" ]; then
      printf '%s\n' "ACTUATE REFUSED (metering gate): the note's kit-row ($(printf '%s' "$_act_nrow" | tr -d '[:cntrl:]' | cut -c1-60)) does not match the approved commit's Kit-Row ($(printf '%s' "$_act_trow" | tr -d '[:cntrl:]' | cut -c1-60)) — a hand-written note?" >&2
      return 1
    fi
  fi
  if ! pv_meter_gate "${_act_mrow_line#kit-row:}" actuate "$asha"; then return 1; fi

  # 3c. EXACT-HEAD CI EVIDENCE (SWAS-537, S3-SEC-2): the PR is the one the note's scope names, and a completed run of the CI
  #     workflow on the exact approved head must have graded at least the light set. Before the merge, so a refusal attempts none.
  _act_pr="$(pv_ev_pr_number "$(printf '%s\n' "$note" | sed -n 's/^scope: //p' | head -1)")" || _act_pr=""
  pv_ci_evidence actuate "$_act_pr" "$asha" 0 "$ref" || return 1
  #     SWAS-901: solo only (a no-op elsewhere): the head's solo-go-bound runs, before the lease so a long wait never holds it.
  pv_sg_gate actuate "$_act_pr" "$asha" "${_mrhd#refs/heads/}" "$ref" || return 1
  #     E6 R2-4: in solo the DEFAULT merge goes by the bound PR's own number, so a second PR from the same head branch cannot be the one merged (--match-head-commit still pins the sha).
  if [ "$PV_REL" = solo ] && [ "$_act_caller" = 0 ] && pv_sg_installed; then merge_cmd="gh pr merge \"$_act_pr\" --squash --match-head-commit \"$asha\""; fi   # MUT-SG-MERGE

  # 3d. THE LAND LEASE (SWAS-192 slice B, B7), as `land` takes it: only in a checkout that opted in; HELD is rc 5 before any merge.
  pv_land_lease_take actuate || return $?

  # 4. Execute the (swappable) NORMAL merge. Non-zero -> loud failure, propagate the code.
  if eval "$merge_cmd"; then mrc=0; else mrc=$?; fi
  if [ "$mrc" -ne 0 ]; then
    echo "ACTUATE FAILED: merge command exited $mrc" >&2; return "$mrc"
  fi

  # 5. Post-check, KEEPING ITS RC — a merge that has happened ALWAYS reaches step 6 and the board tail (A4). The old
  #    tail returned here on a failed check, so the merge ran but the claim was never released and the card never
  #    moved (#806, #808, #840). A mismatch is still rc 1 and loud; it no longer leaves a stale claim behind.
  #    HONEST CEILING: this local post-check REPEATS step 0 — the named head ref still carries the approved tree.
  #    With the pin that means the forge merged the approved head; it does NOT read the trunk. The real
  #    shipped == approved check is CI's recordless-merge backstop, `promotion-verify.sh trace --recent` on main,
  #    which matches every trunk commit to a note by tree.
  if do_check --ref "$ref" --approved-sha "$asha"; then crc=0; else crc=$?; fi

  # 6. RELEASE THE BOARD CLAIM (BOARD-CLAIM-MECHANISM design §3.5). The merge is the end of the
  #    slice, so the row's claim ref (refs/claims/<kit-row>) has done its job and must not linger:
  #    a stale claim blocks the next session from taking the row and shows up in `check --all` as
  #    work nobody is doing. The row comes from the note's OWN `kit-row:` projection — derived from
  #    the approved commit's trailer by `record`, never a flag here.
  #    `--stale` IS REQUIRED AND IS NOT A SHORTCUT: the merger is routinely not the claimant (builder
  #    != ratifier is the point), so the holder check would refuse every real merge. The release names
  #    the holder it removes either way, which is the audit line.
  #    ⚠️ FAILURE HERE IS A **WARN**, NEVER A MERGE FAILURE. The merge ALREADY HAPPENED at step 4 —
  #    returning non-zero now would report a successful, verified promotion as failed, and no rc can
  #    un-merge it. What is printed is the exact command to run by hand.
  pv_release_claim "$note" actuate
  pv_land_lease_return   # the land lease goes back after the claim release (the trap returns it on any other way out)

  # Honest success line: the note is RECORDED, not necessarily AUTHENTICATED — a git note is
  # self-authorable (the label bar is audit + defense-in-depth over it). Where the plan can enforce it, server-side
  # branch protection is what binds; in a solo-declared repo the server-side block is the required check `solo-go-bound` once `branch-protection-apply.sh --replace` has written the solo-agent profile (before that, none), and the GO is
  # self-asserted by name, so the control is the recorded GO bound to the sha + the forge's --match-head-commit pin,
  # and only after-the-fact review of the trail (trace --recent) catches a fabricated one. Do not imply the label authenticates.
  [ -z "$PV_STOP_LINE" ] || printf '%s\n' "$PV_STOP_LINE"
  pv_handover actuate   # MUT-HO-OK
  if [ "$crc" -eq 0 ]; then
    echo "OK: actuated $ref on recorded GO (approved-sha $asha) — head ref carries the approved tree (shipped == approved on the trunk: run promotion-verify.sh trace --recent on main yourself; the kit's own CI runs it, an adopter's does not)"
  else
    echo "ACTUATE: the merge HAS happened and the post-check failed (rc $crc, see SHIPPED != APPROVED above) — the board step below ran regardless." >&2
  fi
  echo "${PV_BOARD_TAIL:-board: NOT CLOSED — see the WARN above}"
  return "$crc"
}

# ---------------------------------------------------------------------------------------------------------------------
# REVIEW-MODE `land` HELPERS (SWAS-727). The review body is UNTRUSTED PROSE: it is kept only as DATA, in a variable, and goes
# into the note only through pv_words_safe (and only on a held approval that a typed GO releases). It never enters
# `approval-token`, a label or a shell word.
# ---------------------------------------------------------------------------------------------------------------------
# pv_sha256 -> the hex sha256 of stdin (sha256sum, else shasum, else openssl).
pv_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else openssl dgst -sha256 2>/dev/null | sed 's/^.*= //'
  fi
}
# pv_words_safe <raw body> -> the words, made safe, on one line: every control character (C0, DEL and the C1 pair C2 80..C2 9F)
# becomes a space, whitespace runs collapse to one space, the ends are trimmed, a backslash is doubled (\\) and then a double quote escaped (\"), so the form is unambiguous, and the result is
# capped at 1000 bytes ON A UTF-8 BOUNDARY, with "…[truncated]" (14 bytes) counted inside the 1000. The raw body is hashed by the
# caller; this is the readable copy. (A lone 0x80..0x9F byte is a UTF-8 continuation byte, never a C1 character, and is kept.)
pv_words_safe() {
  _ws_c1="$(printf '\302[\200-\237]')"
  _ws_t="$(printf '%s' "$1" | LC_ALL=C tr '\000-\037\177' ' ' | LC_ALL=C sed "s/$_ws_c1/ /g" | LC_ALL=C tr -s ' ' \
           | LC_ALL=C sed 's/^ *//; s/ *$//' | LC_ALL=C sed 's/\\/\\\\/g; s/"/\\"/g')"
  if [ "$(printf '%s' "$_ws_t" | wc -c | tr -d ' ')" -gt 1000 ]; then
    _ws_n=986
    while [ "$_ws_n" -gt 0 ]; do   # the first byte left out must not be a continuation byte (10xxxxxx = 128..191), else back up
      _ws_b="$(printf '%s' "$_ws_t" | LC_ALL=C tail -c +"$((_ws_n + 1))" | head -c 1 | od -An -tu1 | tr -d ' \n')"
      case "$_ws_b" in
        12[89]|1[3-8][0-9]|19[01]) _ws_n=$((_ws_n - 1)) ;;
        *) break ;;
      esac
    done
    _ws_t="$(printf '%s' "$_ws_t" | head -c "$_ws_n")$(printf '\342\200\246[truncated]')"
  fi
  printf '%s' "$_ws_t"
}
# pv_land_held_why -> the clause(s) saying why the approval is held: its own comment, and/or a later comment by a GO_GIVERS login.
pv_land_held_why() {
  _hw=""
  if [ "$PV_FR_OWN" = 1 ]; then _hw=" but carries a comment"; fi
  if [ -n "$PV_FR_LATER" ]; then _hw="$_hw, and a later comment holds it (review $PV_FR_LATER)"; fi
  _hw_ids=""
  for _hw_t in $PV_FR_LATERERR; do   # ids whose read failed; bad = an id that is not digits; scan = the scan itself failed
    case "$_hw_t" in
      bad) _hw="$_hw, and a later review id is not digits, so it holds" ;;
      dup) _hw="$_hw, and the approval's id is on two rows, so it holds" ;;
      scan) _hw="$_hw, and the later reviews could not be scanned, so it holds" ;;
      *) _hw_ids="${_hw_ids:+$_hw_ids }$_hw_t" ;;
    esac
  done
  if [ -n "$_hw_ids" ]; then _hw="$_hw, and a later review ($_hw_ids): its comment could not be read, so it holds"; fi
  printf '%s' "$_hw"
}
# pv_land_review_derive — review mode's step 0d(ii), in place of the team label derivation. Sets _land_pre (the label) and
# _land_rkind (`oneact` | `held`), and refuses (rc 1, or rc 2 for the cases the design names) BEFORE any note is written. Needs
# land's locals: asha, land_aby, land_scope, land_goby, land_goby_given, land_tok_given. The forge read runs WITHOUT a command
# substitution (stdout to a file) so PV_FR_* survive.
pv_land_review_derive() {
  _land_rkind=""
  if [ -z "$PV_GO_GIVERS" ]; then
    echo "LAND REFUSED (GO_ACT=review): GO_GIVERS is empty or unreadable in .kit/dials.conf on origin's default branch, so no review can be a GO and every merge is refused. Add the reviewer's login there (a control-plane change), or set GO_ACT=separate. Nothing was written or merged." >&2
    return 2
  fi
  _lr_f="$(mktemp 2>/dev/null)" || { echo "LAND REFUSED (GO_ACT=review): no scratch file for the forge read." >&2; return 2; }
  _lr_lab="$(derive_assurance "$asha" "$land_aby")"
  forge_review_upgrade "$land_scope" "$asha" "$land_aby" "$_lr_lab" "$PV_GO_GIVERS" >"$_lr_f" || :
  _land_pre="$(cat "$_lr_f")"; rm -f "$_lr_f"
  if [ "$PV_FR_WHY" = review-id-invalid ]; then
    echo "LAND REFUSED (GO_ACT=review): the forge returned a review id that is not 1-20 digits, so it is not recorded as the GO. Nothing was written or merged." >&2
    return 2
  fi
  if ! printf '%s' "$_land_pre" | grep -Eq '^authenticated: [A-Za-z0-9_-]+-review$'; then
    echo "LAND REFUSED (GO_ACT=review): the GO is an APPROVED forge review on $asha by a login on GO_GIVERS, and --approved-by '$(printf '%s' "$land_aby" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-80)' derives [$_land_pre] (the reason is on the line above). No note was written and nothing was merged." >&2
    return 1
  fi
  if [ "$PV_FR_HELD" = 1 ]; then
    _lr_w="$(pv_words_safe "$PV_FR_BODY")"
    echo "LAND HELD: review $PV_FR_ID by '$(printf '%s' "$land_aby" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-80)' approves ${asha}$(pv_land_held_why), and a comment may hold a condition no check can enforce, so the click alone does not merge it." >&2
    printf '%s\n' "           the owner's words (made safe): $_lr_w" >&2   # printf, never echo: dash's echo would expand a \c or \0NNN in the words
    if [ "$land_tok_given" != 1 ] || [ -z "$land_goby" ]; then
      echo "           Give the typed GO to release it: land ... --token \"<the owner's words>\" --go-by <the GO-giver> (both). Nothing was written or merged." >&2
      return 2
    fi
    PV_REC_GOACT=separate; PV_REC_GOWORDS="$_lr_w"; PV_REC_GOSHA="$(printf '%s' "$PV_FR_BODY" | pv_sha256)"
    if [ "${#PV_REC_GOSHA}" != 64 ]; then
      echo "LAND REFUSED (GO_ACT=review): no sha256 tool (sha256sum, shasum, openssl) is available to hash the held review's words. Nothing was written or merged." >&2
      return 2
    fi
    _land_rkind=held
    return 0
  fi
  if [ "$land_tok_given" = 1 ] || [ "$land_goby_given" = 1 ]; then
    echo "LAND REFUSED (GO_ACT=review): this approval has no comment, so it is the whole GO: land takes no --token and no --go-by (the modes do not mix; the review id is recorded as the act). Re-run without them. Nothing was written or merged." >&2
    return 2
  fi
  PV_REC_GOACT=review
  _land_rkind=oneact
  return 0
}
# pv_land_class_refuse <class> — land's allowlist refusal for ordinary / sensitive (they actuate), printed and rc 2 by the caller.
pv_land_class_refuse() {
  echo "LAND REFUSED: --class '$1' — land is the control-plane/direct-path verb. Ordinary" >&2
  echo "              and sensitive promotions actuate through \`promotion-verify.sh actuate\`," >&2
  echo "              which carries the forge-review label bar and the SoD for those classes. Use" >&2
  echo "              \`actuate\` for this class (land never had their label bar; the CP/direct path" >&2
  echo "              does not)." >&2
}
# pv_land_update_behind <pr number> <full head sha> — SWAS-1031 (design 4.4): ask the forge to update the PR branch, pinned to the head
# the approval is on. It records nothing and merges nothing; rc 6 = "update requested (202), not merged", rc 1 = the forge refused the update.
pv_land_update_behind() {
  if ! gh api -X PUT "repos/{owner}/{repo}/pulls/$1/update-branch" -f expected_head_sha="$2" >/dev/null 2>&1; then   # MUT-1031-EXPECT
    echo "LAND REFUSED: --update-behind: the forge did not update PR $1 (it refuses when the branch moved since $(printf '%s' "$2" | cut -c1-12), or has a conflict)." >&2
    echo "              Update the branch by hand, then record and land again. Nothing was recorded or merged." >&2
    return 1
  fi
  echo "land: the forge was asked to update PR $1 (pinned to $(printf '%s' "$2" | cut -c1-12)): UPDATE REQUESTED (202), NOT MERGED (rc 6). Nothing was recorded." >&2
  echo "      Wait for CI on the new head, then land again; a re-approval is owed only if the update changed the PR's diff." >&2
  return 6
}
# pv_land_belt <head sha> <origin's default-branch tip> — SWAS-1031 (design 3.3): the belt. A head that is a MERGE must be a plain update
# from main, judged on B1-B3 only; a head that is not a merge is not judged. It runs no classify and no per-path test (those are the held
# lane's), so a code move on main lands on its full CI run. It writes nothing: it runs after step 0f and before the record.
pv_land_belt() {
  _pb_line="$(git -C "$ROOT" rev-list --parents -n 1 "$1" 2>/dev/null || true)"
  _pb_n="$(printf '%s\n' "$_pb_line" | awk '{print NF - 1}')"
  if [ "$_pb_n" -le 1 ] && [ -n "$_pb_line" ]; then return 0; fi
  _pb_why=""
  if [ -z "$_pb_line" ]; then _pb_why="the head's parents could not be read"; fi
  if [ -z "$_pb_why" ] && [ "$_pb_n" -ne 2 ]; then _pb_why="B1: it has $_pb_n parents, not two"; fi   # MUT-1031-BELT-B1
  _pb_p1="$(printf '%s\n' "$_pb_line" | awk '{print $2}')"
  _pb_p2="$(printf '%s\n' "$_pb_line" | awk '{print $3}')"
  if [ -z "$_pb_why" ] && ! git -C "$ROOT" merge-base --is-ancestor "$_pb_p2" "$2" >/dev/null 2>&1; then   # MUT-1031-BELT-B2
    _pb_why="B2: its second parent $(printf '%s' "$_pb_p2" | cut -c1-12) is not an ancestor of origin's tip"
  fi
  _pb_mt=""
  if [ -z "$_pb_why" ]; then
    # the exit code is read, never masked: 0 = a clean tree on the first line, 1 = conflicts, anything else (or no output) = merge-tree could not run
    _pb_mrc=0
    _pb_mo="$(git -C "$ROOT" merge-tree --write-tree --allow-unrelated-histories "$_pb_p2" "$_pb_p1" 2>/dev/null)" || _pb_mrc=$?
    _pb_mt="$(printf '%s\n' "$_pb_mo" | head -n 1)"
    if [ "$_pb_mrc" -eq 1 ]; then
      _pb_why="B3: the update conflicts (merge-tree exit 1): rebase onto origin's default branch"
    elif [ "$_pb_mrc" -ne 0 ] || [ -z "$_pb_mt" ]; then
      _pb_why="B3: \`git merge-tree --write-tree\` could not run (needs git 2.38 or later): rebase onto origin's default branch"
    fi
  fi
  _pb_ht="$(git -C "$ROOT" rev-parse -q --verify "$1^{tree}" 2>/dev/null || true)"
  if [ -z "$_pb_why" ] && { [ -z "$_pb_mt" ] || [ "$_pb_mt" != "$_pb_ht" ]; }; then   # MUT-1031-BELT-B3
    _pb_why="B3: its tree is not merge-tree's result for its two parents (a hand-resolved or evil merge)"
  fi
  # MUT-1031-BELTB4: a per-path "main's bytes only" test (the held lane's B4) would be added HERE; the belt has none.
  # MUT-1031-BELTLANE: a classify / B5 / B6 call (the held lane's predicate) would be added HERE; the belt has none.
  if [ -z "$_pb_why" ]; then return 0; fi
  echo "LAND REFUSED: the head is a merge that is not a plain update from main ($_pb_why). Nothing was recorded or merged." >&2
  echo "              A re-approval does not release this: the head itself is not a plain update. Update the branch afresh (\`land ... --update-behind\`)" >&2
  echo "              or rebase it onto origin's default branch, resolving conflicts in ordinary commits, then wait for CI and an approval on the new head." >&2
  return 1
}

# do_land — ONE transactional actuation verb for the DIRECT / control-plane path (SESSION-SURFACE
# slice 3d F3, design 2026-09-10 §3 F3, Option A; owner GO 2026-09-10).
#
# THE HOLE IT CLOSES. Landing a merge on the direct/CP path is two UNBOUND commands —
# `promotion-verify.sh record` then `gh pr merge` — with nothing tying them. At PR #658 the merge was
# actuated and the record forgotten, so a commit sat on `main` with no recoverable board row (and
# `--delete-branch` compounded it: the branch object holding that commit was gone). `land` makes it
# ONE verb: it RECORDS the GO first (record's own self-unwinding transaction, inherited whole) and
# only then MERGES — the record cannot be forgotten because the SAME verb writes it before the merge.
# It NEVER deletes the branch (deletion is a separate human act, D-240819-4) and NEVER emits `--admin`.
#
# WHY A SEPARATE SUBCOMMAND, NOT `actuate`. The Tier-3 sitting is CLOSED (D-241014-1 item 6): `land` is the
# control-plane verb, by ruling, in BOTH relationships, and `actuate` points a control-plane note here (its step
# 1b). `land` already holds the stronger transaction (record, confirm on origin, vet, pin). It changes NO
# boundary: the guard still denies `--admin` and CP Write/Edit, branch protection is unchanged, the human
# still renders the GO.
#
# ⚠️ HONEST CEILING — VERB-SCOPED, NOT A HARD GATE (design A1, BUILD-BINDING). By the friction test —
# would it bind if the model stopped cooperating? — `land` does NOT: a raw `gh pr merge` still exists
# and an uncooperative agent runs where this local tool is absent. `land` refuses a recordless merge
# ONLY ON ITS OWN PATH. The friction-test hard gate for a recordless merge is the CI recordless-merge
# backstop (`promotion-verify.sh trace --recent`, server-side) plus branch protection; NO
# prevent-at-merge gate is possible for a self-authorable git note. So every string below is
# VERB-SCOPED — it never says a recordless merge is "impossible" unqualified, only that THIS VERB
# refuses one and names the universal net.
#
# THE BAR `land` ENFORCES ON ITS OWN PATH (GO-IDENTITY-AND-LAND-SOD, owner ruling 2026-10-02), stated
# truthfully: it merges control-plane ONLY on an AUTHENTICATED NON-AUTHOR forge approval — the label
# derived (derive_assurance + forge_review_upgrade, the very functions `record` uses) must match
# [authenticated: <forge>-review] before the record (a refusal writes no note) and again from the note on
# origin before the merge — and it records the GO-giver BY NAME (`--go-by`, [self-asserted] by design).
# That label is derived over the LOCAL `gh` credential at record time: a drift control at the note's own
# trust tier. An agent that controls PATH can fake reviews, and a raw `gh pr merge` still exists, so the
# control that BINDS is server-side branch protection + required review; `land` refuses on its own path
# and that is all it claims. SOLO-DECLARED (MERGE_RELATIONSHIP=solo on origin's default branch, D-241014-1): one
# forge account, so there is no authenticated approval to find; `land` skips the author SoD and the forge
# pre-derivation and judges the SOLO BAR (pv_solo_go_ok) on the note read back from origin instead — the owner's
# named GO bound to the sha, the tree and origin, and pinned at the forge with --match-head-commit. That GO is
# self-asserted by name and there is no server-side kill-switch; only after-the-fact review catches a fabricated
# one. An UNDECLARED one-account repo still reads team, so `land` refuses it by construction: the agent records
# the GO (`record`) and the HUMAN merges (an admin merge is the human's act; the guard denies the agent --admin).
do_land() {
  ref=""; merge_cmd=""; asha=""; land_cls=""; land_aby=""; land_goby=""; land_goby_given=0; land_scope=""
  # SWAS-727: land_gate and land_tok_given are PEEKED, never consumed (the pass-through arm still moves them on to record), so the
  # S2-1 argv reading below is unchanged. PV_REC_* are reset here so nothing from an earlier call in this process reaches record.
  land_gate=""; land_rung=""; land_tok_given=0; _land_noncp=0; _land_rkind=""
  # SWAS-1031: --update-behind is CONSUMED (like --ref), never re-appended, so it cannot reach record.
  land_upd=0
  PV_REC_GOACT=""; PV_REC_GOWORDS=""; PV_REC_GOSHA=""
  # Strip land's OWN two flags (--ref, --merge-cmd) and PEEK --approved-sha / --class / --approved-by /
  # --go-by / --scope (shared with record: record binds the note to the sha, the merge pins
  # --match-head-commit to it; land derives its CP-path decision from --class, its SoD check from
  # --approved-by, its GO-giver requirement from --go-by and its forge-review pre-derivation from --scope), then pass
  # EVERYTHING ELSE through to do_record verbatim — spaces intact — via the rotate-the-positional-
  # parameters idiom (no arrays in POSIX sh). $_argc counts ORIGINAL args only; re-appended pass-through
  # args pile at the BACK, so a value read guarded by `_argc -ge 2` can only ever read a still-
  # unprocessed original at the front, never a re-appended one (which would let a trailing `--ref`
  # swallow a pass-through value). --class / --approved-by are LAST-WINS here exactly as they are in
  # do_record's own loop, so land and record agree on the value each judges.
  # A PEEKED VALUE NEVER STARTS WITH '-' (security S2-1). land's peek and record's parse split the SAME argv by
  # different rules: given `--token --go-by --gate g`, land reads --go-by's value as `--gate` while record reads
  # `--go-by` as the TOKEN, so land judged a go-by that record never wrote and merged `(none recorded)`. A
  # flag-shaped value for a peeked flag is refused outright, rc 2, naming the flag.
  _argc=$#
  while [ "$_argc" -gt 0 ]; do
    case "$1" in
      --approved-sha|--class|--approved-by|--go-by|--scope|--gate|--rung)
        # only an ORIGINAL argument has a value to check: with fewer than two left, $2 is a moved-back argument, never this flag's value
        _land_pv=""; if [ "$_argc" -ge 2 ]; then _land_pv="${2:-}"; fi
        case "$_land_pv" in
          -*) echo "land: $1 value '$(printf '%s' "$2" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-40)' starts with '-' — refused (a flag-shaped value for $1 is how a record-only flag's value gets swallowed; land and record would then judge different arguments)" >&2
              return 2 ;;
        esac ;;
    esac
    case "$1" in
      --token|--token-file) land_tok_given=1 ;;
    esac
    case "$1" in
      --gate)
        # CONSUMED, like the other peeked flags (a bare peek let `--gate design --basis --gate` read an EMPTY gate here while record
        # read `design`): last wins, as in record, and the whole-note check below compares the recorded gate with this value.
        [ "$_argc" -ge 2 ] || { echo "land: --gate needs a value" >&2; usage; return 2; }
        land_gate="$2"
        # SWAS-948: fold HERE, so the value re-appended for record (and the one land reads back by) is the lowercase list spelling and an
        # unlisted one is refused before any network read. An empty value is left for record's own "missing --gate".
        if [ -n "$land_gate" ]; then
          _lf="$(_pv_gate_ok "$land_gate")" || { _pv_vocab_refuse land gate "$land_gate"; return 2; }
          land_gate="$_lf"
        fi
        set -- "$@" "$1" "$land_gate"; shift 2; _argc=$((_argc-2)) ;;
      --rung)
        [ "$_argc" -ge 2 ] || { echo "land: --rung needs a value" >&2; usage; return 2; }
        land_rung="$2"
        if [ -n "$land_rung" ]; then
          _lf="$(_pv_rung_ok "$land_rung")" || { _pv_vocab_refuse land rung "$land_rung"; return 2; }
          land_rung="$_lf"
        fi
        set -- "$@" "$1" "$land_rung"; shift 2; _argc=$((_argc-2)) ;;
      --ref)
        [ "$_argc" -ge 2 ] || { echo "land: --ref needs a value" >&2; usage; return 2; }
        ref="$2"; shift 2; _argc=$((_argc-2)) ;;
      --merge-cmd)
        [ "$_argc" -ge 2 ] || { echo "land: --merge-cmd needs a value" >&2; usage; return 2; }
        merge_cmd="$2"; shift 2; _argc=$((_argc-2)) ;;
      --update-behind)
        land_upd=1; shift; _argc=$((_argc-1)) ;;
      --approved-sha)
        [ "$_argc" -ge 2 ] || { echo "land: --approved-sha needs a value" >&2; usage; return 2; }
        asha="$2"; set -- "$@" "$1" "$2"; shift 2; _argc=$((_argc-2)) ;;
      --class)
        [ "$_argc" -ge 2 ] || { echo "land: --class needs a value" >&2; usage; return 2; }
        land_cls="$2"; set -- "$@" "$1" "$2"; shift 2; _argc=$((_argc-2)) ;;
      --approved-by)
        [ "$_argc" -ge 2 ] || { echo "land: --approved-by needs a value" >&2; usage; return 2; }
        land_aby="$2"; set -- "$@" "$1" "$2"; shift 2; _argc=$((_argc-2)) ;;
      --go-by)
        [ "$_argc" -ge 2 ] || { echo "land: --go-by needs a value" >&2; usage; return 2; }
        land_goby="$2"; land_goby_given=1; set -- "$@" "$1" "$2"; shift 2; _argc=$((_argc-2)) ;;
      --scope)
        [ "$_argc" -ge 2 ] || { echo "land: --scope needs a value" >&2; usage; return 2; }
        land_scope="$2"; set -- "$@" "$1" "$2"; shift 2; _argc=$((_argc-2)) ;;
      --no-push)
        # REFUSE --no-push in land (do NOT pass it through). A landing merge MUST publish the GO
        # record so it reaches origin; --no-push is record's offline-maintenance escape, never
        # landing's. Landing on a local-only note is the exact #658 hole — a note that never reaches
        # origin is not recoverable by CI's recordless-merge backstop.
        echo "land: --no-push is REFUSED — a landing merge must PUBLISH the GO record so it reaches" >&2
        echo "      origin. --no-push is record's offline escape, never landing's; a note that never" >&2
        echo "      reaches origin is not recoverable by CI's recordless-merge backstop (this would" >&2
        echo "      reopen the #658 hole). Re-run without --no-push." >&2
        return 2 ;;
      *)
        set -- "$@" "$1"; shift; _argc=$((_argc-1)) ;;
    esac
  done
  if [ -z "$ref" ];  then echo "land: --ref required" >&2; usage; return 2; fi
  if [ -z "$asha" ]; then echo "land: --approved-sha required" >&2; usage; return 2; fi
  # Reuse actuate's option-like + charset validation: $ref and $asha are interpolated into the merge
  # command eval'd below, so a metacharacter must never reach the shell — even though the caller is
  # already the agent, this verb must never be a shell-injection primitive. Real refs/SHAs never
  # start with '-' and contain only [A-Za-z0-9._/-].
  case "$ref" in
    -*) echo "land: invalid --ref '$ref' (must not start with '-')" >&2; return 2 ;;
  esac
  case "$asha" in
    -*) echo "land: invalid --approved-sha '$asha' (must not start with '-')" >&2; return 2 ;;
  esac
  case "$ref" in
    *[!A-Za-z0-9._/-]*) echo "land: invalid --ref '$ref' (allowed chars: A-Za-z0-9._/-)" >&2; return 2 ;;
  esac
  case "$asha" in
    *[!A-Za-z0-9._/-]*) echo "land: invalid --approved-sha '$asha' (allowed chars: A-Za-z0-9._/-)" >&2; return 2 ;;
  esac

  # 0. CP-PATH VERB (F3-2, owner-adjudicated 2026-09-10). `land` is the direct/control-plane verb the
  #    design describes; ordinary and sensitive promotions actuate through `actuate`, which carries the
  #    forge-review label bar AND the SoD for those classes. Read the class from the SAME --class arg
  #    land passes to do_record, and refuse BEFORE record runs (no note is written on a refusal).
  #    ALLOWLIST-STYLE, like do_actuate's step 2b: proceed ONLY for an explicit control-plane class;
  #    ordinary/sensitive point at `actuate`; unknown or missing refuses too — an unjudgeable class is
  #    never a permission. Case-folded, matched exactly (never a substring). This makes land strictly
  #    the CP/direct path and closes the non-CP control regression, without touching do_actuate.
  _land_cls_lc="$(printf '%s' "$land_cls" | LC_ALL=C tr 'A-Z' 'a-z')"
  case "$_land_cls_lc" in
    control-plane) ;;
    ordinary|sensitive)
      # SWAS-727: in review mode `actuate` refuses (it never re-reads the forge), so `land` is the only route for EVERY class. The
      # dial is read at step 0a, so this refusal moves there (pv_land_class_refuse) unless the mode turns out to be review.
      _land_noncp=1 ;;
    *)
      echo "LAND REFUSED: unrecognised or missing --class '$land_cls' — land proceeds ONLY for an" >&2
      echo "              explicitly recorded 'control-plane' class (allowlist). An unjudgeable class is" >&2
      echo "              never a permission. Re-run with --class control-plane, or use \`actuate\` for" >&2
      echo "              an ordinary/sensitive promotion." >&2
      return 2 ;;
  esac

  # 0a. THE MERGE RELATIONSHIP (D-241014-1), read from origin's default branch and said in ONE line before anything is
  #     recorded or merged. SOLO (an explicit MERGE_RELATIONSHIP=solo on the base, no Governance `team` over it): steps 0b and
  #     0d(ii) below are skipped — with one forge account there is no second approver to find or compare — and step 2b judges the
  #     SOLO BAR on the note read back from origin instead of the forge-review label. Everything else `land` holds is kept in
  #     both relationships: --go-by, scope == ref, the whole-note match, --no-push refused, the origin confirm, the vet and the
  #     pin. TEAM (the default, and every undeclared or unreadable case) is exactly what it always was.
  pv_merge_relationship land
  pv_handover land   # MUT-HO-REL
  #     SWAS-727: the merge GO's act (GO_ACT / GO_GIVERS), from the same origin tip; absent under solo and for a design or plan gate
  #     (those stay typed in every mode). `_land_mode` is the mode THIS land runs under.
  pv_go_dials land
  _land_mode="$PV_GO_ACT"
  if pv_go_gate_typed "$land_gate"; then _land_mode=absent; fi
  if [ "$_land_noncp" = 1 ] && [ "$_land_mode" != review ]; then
    pv_land_class_refuse "$land_cls"
    return 2
  fi

  # 0b. SoD (builder != ratifier) — RUN BEFORE do_record (N2). Team only (the arm is not re-indented, to keep its diff empty). It sits beside the class gate, which
  #     already runs pre-record with $asha/$land_aby in hand, so a self-approval NEVER publishes a GO
  #     note on origin: the old placement (after record + the on-origin confirm) meant every SoD refusal
  #     left a PUBLISHED self-approved note, and the recordless-merge backstop reads binding only, not
  #     approver — so the drift artifact the system trusts was created before this control spoke.
  #     The author of $asha is resolvable locally with `git show -s --format='%an'/'%ae'` exactly as
  #     do_actuate's step 3 resolves it. NORMALIZE the approver with the SAME whitespace strip do_actuate
  #     applies to its note-read approver id (leading at :1065, trailing at :1130) — copied, not
  #     reinvented — so a padded `--approved-by "t "` cannot slip land's SoD though actuate would refuse
  #     the note it writes. Refuse an empty/whitespace-only approver too (it can never satisfy SoD).
  #     ⚠️ HONEST TIER: this is a DRIFT CONTROL at the GO note's own trust tier, NOT authentication. The
  #     real boundary is server-side branch protection + required review; a git note is self-authorable
  #     and this check rides on the caller-supplied approver. It catches the honest self-approval, not a
  #     determined one.
  if [ "$PV_REL" != solo ]; then
  _land_aby_norm="$(printf '%s' "$land_aby" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  if [ -z "$_land_aby_norm" ]; then
    echo "LAND REFUSED: empty approver (--approved-by) — cannot satisfy builder != ratifier (SoD). This" >&2
    echo "              is a drift control at the GO note's own tier (branch protection is the real" >&2
    echo "              boundary), not authentication. Re-run with a non-author --approved-by." >&2
    return 1
  fi
  pv_sod_author_check land "$asha" "$_land_aby_norm" || return 1
  fi   # solo skips 0b: the approver is the author by construction (record still requires a non-empty --approved-by)

  # 0c. THE PER-SLICE METERING GATE (RUNAWAY-METERING-LANDING-GATE) — after SoD, BEFORE do_record, so a
  #     refusal writes NO note (the same property the class gate and SoD have). The row is the `Kit-Row`
  #     trailer of the approved commit, derived here the way step 2c derives it later.
  _land_mrow="$(git -C "$ROOT" log -1 --no-show-signature --format='%(trailers:key=Kit-Row,valueonly)' "$asha" 2>/dev/null | head -1)"
  if ! pv_meter_gate "$_land_mrow" land "$asha"; then return 1; fi

  # 0d. THE CONTROL-PLANE BAR (GO-IDENTITY-AND-LAND-SOD, owner ruling 2026-10-02: the forge Approve is the
  #     ONLY identity the kit AUTHENTICATES; the owner's GO is recorded BY NAME; `land` merges control-plane
  #     only on an authenticated NON-AUTHOR approval). Before this, `land` — the verb for the STRONGER class
  #     — never read the label it was about to record, so a [self-asserted] GO merged (half-2 §6), while
  #     `actuate` for the weaker classes already demanded [authenticated: <forge>-review]. It sits AFTER the
  #     class gate, SoD and the meter gate and BEFORE do_record, so a refusal here writes NO note and runs
  #     NO merge (the same property those three have).
  #     (i) --go-by is REQUIRED: `land` records the owner's GO by name.
  if [ "$land_goby_given" = 1 ] && [ -z "$(printf '%s' "$land_goby" | tr -d ' \t')" ]; then
    echo "land: --go-by is empty or whitespace-only — rejected (name the person who gave the GO)" >&2
    return 2
  fi
  #     In REVIEW mode (SWAS-727) the approval itself is the GO and the typed --go-by is judged by pv_land_review_derive below (an
  #     empty-body approval takes none; a held one takes it with --token), so this requirement is skipped there.
  if [ -z "$land_goby" ] && [ "$_land_mode" != review ]; then
    echo "LAND REFUSED: land records the owner's GO by name: add \`--go-by <the GO-giver>\` (the person whose" >&2
    echo "              judgment this GO is; recorded [self-asserted] by design — the kit never authenticates" >&2
    echo "              the GO-giver). --approved-by is a DIFFERENT identity: the forge login of the reviewer." >&2
    return 1
  fi
  #     GO_ACT=separate (SWAS-727): the GO-giver is not the reviewer (G1; folded like the commit-author SoD). Before the record.
  if [ "$_land_mode" = separate ]; then pv_separate_ok land "$land_goby" "$land_aby" || return 1; fi
  #     (i-b) THE MERGED PR IS THE JUDGED PR (security S2-2). The forge derivation reads the reviews of the PR
  #     --scope names; the merge acts on --ref. Normalise --scope to its digits with the SAME four shapes
  #     forge_review_upgrade accepts (`PR #N`, `PR-N`, `#N`, `N`) and require them to equal --ref (digits too),
  #     else an approval on one PR could authenticate a merge of another. Before the record: no note, no merge.
  case "$land_scope" in
    'PR #'*) _land_sn="${land_scope#PR #}" ;;
    'PR-'*)  _land_sn="${land_scope#PR-}" ;;
    '#'*)    _land_sn="${land_scope#\#}" ;;
    *)       _land_sn="$land_scope" ;;
  esac
  case "$_land_sn" in
    ''|*[!0-9]*) _land_sn="" ;;
  esac
  if [ -z "$_land_sn" ]; then
    echo "LAND REFUSED: --scope '$(printf '%s' "$land_scope" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-60)' is not a PR id. A control-plane land is bound to the PR it merges and" >&2
    echo "              authenticates by that PR's reviews: --scope must be the PR id (PR #N, PR-N, #N or N)." >&2
    return 1
  fi
  _land_rn="$ref";
  case "$_land_rn" in
    *[!0-9]*) _land_rn="" ;;
  esac
  if [ -z "$_land_rn" ] || [ "$(printf '%s' "$_land_rn" | sed 's/^0*//')" != "$(printf '%s' "$_land_sn" | sed 's/^0*//')" ]; then
    echo "LAND REFUSED: --scope names PR $_land_sn but --ref is '$ref' — the PR judged must be the PR merged." >&2
    echo "              Pass the same PR number as --ref and --scope. No note was written and nothing was merged." >&2
    return 1
  fi
  #     (ii) PRE-DERIVE the label with the SAME two functions `record` will use, and require what `actuate`
  #     requires (the same regex). forge_review_upgrade already refuses the PR author (case-insensitive), a
  #     Bot, a withdrawn or dismissed approval and a stale-sha one, and prints its fixed-enumeration reason
  #     on stderr (e.g. reviewer-not-in-reviews, reviewer-is-pr-author), which stays visible above.
  #     Team only: a solo-declared repo has no second approver to derive (the arm is not re-indented, to keep its diff empty).
  if [ "$_land_mode" = review ]; then
    #     SWAS-727 REVIEW MODE: the same read, widened (GO_GIVERS, the digits-only review id, the body), in place of the team one.
    #     It refuses with its own lines, so the team refusal below is not reached. A one-act GO takes no --token / --go-by: the
    #     review id is the recorded act; here the arguments record will receive are completed.
    # rc 3 is RESERVED for "merged, tree mismatch" (SWAS-323b): a refusal here is 1 or 2, whatever the helper returned.
    _lrd=0; pv_land_review_derive || _lrd=$?
    if [ "$_lrd" -ne 0 ]; then if [ "$_lrd" -eq 3 ]; then _lrd=1; fi; return "$_lrd"; fi
    if [ "$_land_rkind" = oneact ]; then
      set -- "$@" --token "forge-review:$PV_FR_ID" --go-by "$land_aby"
      land_goby="$land_aby"
    fi
  elif [ "$PV_REL" != solo ]; then
  _land_pre="$(derive_assurance "$asha" "$land_aby")"
  _land_pre="$(forge_review_upgrade "$land_scope" "$asha" "$land_aby" "$_land_pre")"
  if ! printf '%s' "$_land_pre" | grep -Eq '^authenticated: [A-Za-z0-9_-]+-review$'; then
    _land_abyp="$(printf '%s' "$land_aby" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-80)"
    echo "LAND REFUSED: a control-plane merge needs an AUTHENTICATED NON-AUTHOR forge approval, and --approved-by" >&2
    echo "              '$_land_abyp' derives [$_land_pre] (the reason is on the line above)." >&2
    echo "              --approved-by is the forge LOGIN of a non-author reviewer whose APPROVED review is on" >&2
    echo "              $asha; the GO-giver (the owner) goes in --go-by." >&2
    echo "              SOLO (one forge account, no second approver)? Declare it: MERGE_RELATIONSHIP=solo in .kit/dials.conf on the" >&2
    echo "              default branch, merged once by hand after you record your GO on that PR (docs/adoption/vc-hosts.md). Until" >&2
    echo "              then, record the GO with \`promotion-verify.sh record\` (it takes --go-by too) and the HUMAN merges: an" >&2
    echo "              admin squash-merge is the human's act, never the agent's (the guard denies the agent --admin). No note was" >&2
    echo "              written and nothing was merged. This is a drift control at the note's own tier (the label is derived over" >&2
    echo "              the local gh credential); server-side branch protection + required review is what binds." >&2
    return 1
  fi
  fi   # closes the team arm of 0d(ii)

  # 0e. EXACT-HEAD CI EVIDENCE (SWAS-537, S3-SEC-2): a completed run of the CI workflow on the exact approved head must have
  #     graded at least the light set (and recorded a `gate` job). It sits AFTER the class gate, SoD, the meter gate and the
  #     forge bar and BEFORE do_record, so a refusal writes NO note and merges nothing (the same property those have).
  _land_full="$(git -C "$ROOT" rev-parse -q --verify "${asha}^{commit}" 2>/dev/null || true)"
  pv_ci_evidence land "$_land_sn" "${_land_full:-$asha}" 1 || return 1

  # 0f. THE SERIAL PRECONDITION (SWAS-323b, design 4). The land record says landed-tree = approved-tree, which holds only when origin's
  #     default branch is an ancestor of the approved head (the up-to-date state the strict branch setting enforces today). Otherwise the
  #     squash result is a different tree and the train, not this verb, computes the prefixes. It runs AFTER every check above, and BEFORE
  #     any record is written, so a refusal writes nothing. The tip is read afresh from origin (pv_remote_ref_sha): it is the land record's
  #     base-sha too.
  _land_bref="${_mrhd:-refs/heads/main}"
  _land_base="$(pv_remote_ref_sha "$_land_bref" || true)"
  _land_brc=0
  if [ -n "$_land_base" ]; then git -C "$ROOT" merge-base --is-ancestor "$_land_base" "${_land_full:-$asha}" >/dev/null 2>&1 || _land_brc=$?; fi
  if [ -z "$_land_base" ] || [ "$_land_brc" -ne 0 ]; then
    #     SWAS-1031 (design 4.4): with --update-behind, a readable tip and a full head sha to pin to, the forge updates the branch instead of
    #     the refusal below: rc 6 ("update requested (202), not merged"), no record, no merge. The helper prints its own lines.
    if [ "$land_upd" = 1 ] && [ -n "$_land_base" ] && [ -n "$_land_full" ]; then
      _lub=0; pv_land_update_behind "$_land_sn" "$_land_full" || _lub=$?
      return "$_lub"
    fi
    echo "LAND REFUSED: serial land needs an up-to-date head; the train computes prefixes." >&2
    if [ -z "$_land_base" ]; then
      echo "              Origin's ${_land_bref#refs/heads/} tip could not be read, so the head cannot be shown to be up to date. Nothing was recorded or merged." >&2
    else
      echo "              Origin's ${_land_bref#refs/heads/} tip $(printf '%s' "$_land_base" | cut -c1-12) is not an ancestor of the approved head $(printf '%s' "${_land_full:-$asha}" | cut -c1-12) (or is not in this clone): run \`git fetch origin ${_land_bref#refs/heads/}\` first, then \`land ... --update-behind\` asks the forge to update the branch; wait for CI on the new head, then land again; a re-approval is owed only if the update changed the PR's diff. Nothing was recorded or merged." >&2
    fi
    echo "              (land assumes the PR targets origin's default branch, ${_land_bref#refs/heads/}; it does not read the PR's own base.)" >&2
    return 1
  fi
  #     SWAS-1031 (design 3.3): the belt, on a merge head only; after the serial precondition, before any record, so a refusal writes nothing.
  pv_land_belt "${_land_full:-$asha}" "$_land_base" || return 1

  # 1. RECORD FIRST — the whole point of the verb. do_record is a self-unwinding transaction (fetch,
  #    refuse on divergence, write, publish, unwind its own unpublished note on push reject); land
  #    inherits it whole and passes record's args through untouched. If record does not complete,
  #    REFUSE to merge and propagate its code — a merge without a recoverable GO note is refused BY
  #    THIS VERB (verb-scoped honesty: never "impossible", only "land will not merge").
  #    SWAS-323b: record also writes the LAND record beside the GO record, in the same transaction (PV_REC_LAND).
  PV_REC_LAND=1; PV_LAND_BASE="$_land_base"
  if do_record "$@"; then _lrc=0; else _lrc=$?; fi
  PV_REC_LAND=""
  if [ "$_lrc" -ne 0 ]; then
    echo "LAND REFUSED: the GO record did not complete (rc $_lrc) — land will not merge without a" >&2
    echo "              recoverable GO note. This verb refuses a recordless merge on its OWN path;" >&2
    echo "              the universal net for a recordless merge is the CI recordless-merge backstop." >&2
    if [ "$_lrc" -eq 3 ]; then _lrc=2; fi   # rc 3 is RESERVED for "merged, tree mismatch" (SWAS-323b)
    return "$_lrc"
  fi

  # 2. CONFIRM THE NOTE IS ON ORIGIN — not merely local — before merging; fail CLOSED otherwise.
  #    This is the belt on #658: a note that lives only in this clone is NOT recoverable by CI's
  #    recordless-merge backstop, so a local `git notes show` would PASS on the exact state the hole
  #    is made of. `land` refuses --no-push above, so record HAS published; here we re-read ORIGIN's
  #    own copy and require the bind to exist THERE. Fetch origin's ledger into a throwaway,
  #    PID-scoped notes ref and check the bind on that copy (never trusting the local ref).
  _land_confirm="kit-land-confirm-$$"
  # C2 (the B1 twin): `fetch -f` writes THROUGH a symbolic ref, and a plain `update-ref -d` deletes through one — so a
  # ref planted at this pid-named name would clobber, then delete, the ledger. Refuse if ANYTHING is there, name it,
  # and delete only with --no-deref. C1: --refmap= so the fetch cannot ALSO update the local ledger.
  if _pv_ref_exists "refs/notes/$_land_confirm"; then
    echo "LAND REFUSED: the confirm ref refs/notes/$_land_confirm already exists (a stale leftover or a planted ref) —" >&2
    echo "              refused before any fetch into it. The GO note IS recorded. Inspect it (git for-each-ref" >&2
    echo "              refs/notes/$_land_confirm), delete it if stale, then land again." >&2
    return 1
  fi
  if ! git fetch --refmap= --no-tags -f origin "refs/notes/$NOTES_REF:refs/notes/$_land_confirm" >/dev/null 2>&1; then
    git update-ref --no-deref -d "refs/notes/$_land_confirm" >/dev/null 2>&1 || true
    echo "LAND REFUSED: record reported success but origin's refs/notes/$NOTES_REF could not be" >&2
    echo "              fetched back — land will not merge without confirming the GO note reached" >&2
    echo "              origin (fail closed). This verb refuses on its OWN path; the universal net" >&2
    echo "              is the CI recordless-merge backstop." >&2
    return 1
  fi
  # SWAS-323: the note on origin is a LIST of records; the one judged below is the record keyed (--scope, --gate) that record just wrote.
  if ! _land_cwhole="$(git notes --ref="$_land_confirm" show "$asha" 2>/dev/null)" \
     || ! _land_cnote="$(_pv_note_pick "$_land_cwhole" "$land_scope" "$land_gate")"; then
    git update-ref --no-deref -d "refs/notes/$_land_confirm" >/dev/null 2>&1 || true
    echo "LAND REFUSED: record reported success but no GO note is bound to $asha ON ORIGIN — land" >&2
    echo "              will not merge without a note that reached origin (fail closed). A note that" >&2
    echo "              never reaches origin is not recoverable by CI's recordless-merge backstop." >&2
    return 1
  fi
  git update-ref --no-deref -d "refs/notes/$_land_confirm" >/dev/null 2>&1 || true

  # 2b. THE BELT (GO-IDENTITY-AND-LAND-SOD): re-judge the label from the NOTE ON ORIGIN — the bytes CI and
  #     `trace` will read — not from the pre-check. The forge is asked twice (land's pre-derivation, then
  #     record's own); if its answer changed in between (an approval withdrawn or dismissed), the note carries
  #     the weaker label and the pre-check's "yes" is stale. Parsed EXACTLY as `actuate` parses it: the
  #     `approved-by:` line only, the trailing [...] on it, the same regex. Never a body scan.
  _land_bl="$(printf '%s\n' "$_land_cnote" | grep '^approved-by:' | head -1 || true)"
  _land_bl="$(printf '%s' "${_land_bl#approved-by:}" | sed 's/^[[:space:]]*//')"
  _land_blab=""
  case "$_land_bl" in
    *'['*']') _land_blab="${_land_bl##*\[}"; _land_blab="${_land_blab%]}" ;;
  esac
  #     SOLO: the same note read back from origin is judged by the SOLO BAR instead of the label (its whole-note match below stays).
  if [ "$PV_REL" = solo ]; then
    pv_solo_go_ok land "$_land_cnote" "$asha" || return 1
  else
  if ! printf '%s' "$_land_blab" | grep -Eq '^authenticated: [A-Za-z0-9_-]+-review$'; then
    _land_blab="$(printf '%s' "$_land_blab" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-80)"
    echo "LAND REFUSED: the GO note on origin carries assurance '[$_land_blab]', not [authenticated: <forge>-review] —" >&2
    echo "              the forge answered differently between land's pre-check and record's own read (an" >&2
    echo "              approval withdrawn or dismissed meanwhile). The note IS recorded; land will not merge on it." >&2
    echo "              Re-run land once the approval stands on $asha — record supersedes the note." >&2
    return 1
  fi
  fi   # closes the team arm of the 2b label check (not re-indented, to keep its diff empty)
  #     THE WHOLE NOTE, NOT ONLY THE LABEL (security S2-1b): land and record parse the same argv separately, so
  #     the note on origin must say exactly what land judged. Each field is read by its own line key and
  #     compared byte-for-byte (class case-folded, as record accepts it); any mismatch refuses the merge.
  _land_nf() { printf '%s\n' "$_land_cnote" | sed -n "s/^$1: //p" | head -1; }
  _land_bad=""
  [ "$_land_bl" = "$land_aby [$_land_blab]" ] || _land_bad="$_land_bad approved-by"
  [ "$(_land_nf scope)" = "$land_scope" ] || _land_bad="$_land_bad scope"
  [ "$(_land_nf change-class | LC_ALL=C tr 'A-Z' 'a-z')" = "$_land_cls_lc" ] || _land_bad="$_land_bad change-class"
  # SWAS-727: the recorded gate is the gate land judged, in EVERY mode (what the mode was read from), and a review-mode note never
  # carries a design or plan gate.
  [ "$(_land_nf gate)" = "$land_gate" ] || _land_bad="$_land_bad gate"
  if [ -n "$_land_rkind" ] && pv_go_gate_typed "$(_land_nf gate)"; then _land_bad="$_land_bad gate"; fi
  if [ "$_land_rkind" = oneact ]; then
    # SWAS-727: a one-act note says exactly what the review derivation judged: the act, one authenticated identity in both fields,
    # and the review id (digits, from the same read) as the token.
    [ "$(_land_nf go-by)" = "$land_aby [authenticated: github-review]" ] || _land_bad="$_land_bad go-by"
    [ "$(_land_nf go-act)" = review ] || _land_bad="$_land_bad go-act"
    [ "$(_land_nf approval-token)" = "\"forge-review:$PV_FR_ID\"" ] || _land_bad="$_land_bad approval-token"
  else
    [ "$(_land_nf go-by)" = "$land_goby [self-asserted]" ] || _land_bad="$_land_bad go-by"
  fi
  if [ "$_land_rkind" = held ]; then
    [ "$(_land_nf go-act)" = separate ] || _land_bad="$_land_bad go-act"
    [ "$(_land_nf go-words)" = "\"$PV_REC_GOWORDS\"" ] || _land_bad="$_land_bad go-words"
    [ "$(_land_nf go-words-sha256)" = "$PV_REC_GOSHA" ] || _land_bad="$_land_bad go-words-sha256"
  fi
  if [ -n "$_land_bad" ]; then
    echo "LAND REFUSED: the GO note on origin does not say what land judged (mismatched:$_land_bad) — land and record read" >&2
    echo "              the arguments differently. The note IS recorded; land will not merge on it. Fix the arguments" >&2
    echo "              and re-run land — record supersedes the note." >&2
    return 1
  fi
  # SWAS-323: the LAST check. Every field above matched, and the record on origin under this (scope, gate) must still be, byte for byte,
  # the record this land just composed and wrote ($nbody, set by do_record in this shell): a hand-minted record of the same key, or one
  # a racing writer put there, is not judged.
  if [ "$_land_cnote" != "$nbody" ]; then
    echo "LAND REFUSED: the GO record on origin under this scope and gate is not the one land just wrote (mismatched: record) — land will not merge on it." >&2
    echo "              The note IS recorded; inspect it with promotion-verify.sh log, then re-run land — record supersedes the record." >&2
    return 1
  fi
  # SWAS-323b, also LAST: the land record on origin under this scope must be, byte for byte, the one this land composed beside the GO record.
  if ! _land_clr="$(_pv_note_pick_land "$_land_cwhole" "$land_scope")" || [ "$_land_clr" != "$lbody" ]; then
    echo "LAND REFUSED: the land record on origin under this scope is missing or is not the one land just wrote (mismatched: land record) — land will not merge on it." >&2
    echo "              The note IS recorded; inspect it with promotion-verify.sh log, then re-run land — record supersedes the record." >&2
    return 1
  fi

  # 2c. A9 HYGIENE RE-READ (design §8, D-240919-2(7)). A9 is HYGIENE, NOT a control — the binding
  #     form is B5 (loop-state's own gate on the pushed head), so this leg NEVER hard-blocks land on
  #     a can't-read; it refuses ONLY when a fresh re-read shows the row has demonstrably LEFT the
  #     in-flight states between the Entry Declaration and this merge (e.g. it was independently
  #     closed/reopened/cancelled out from under the approval). Reference pattern:
  #     `_seam_tracker_prepare` (hooks/pre-push, T1, commit 73c7cbd) — same conf/origin resolution,
  #     the same fixed record path, the same injectable shape, the same reader rc contract. This is
  #     an INTENTIONAL, BOUNDED duplication (the file set for this slice forbids a shared helper); a
  #     future `tracker-local-read` extraction is a noted follow-up, not built here.
  #     `md`/unrecognised/undeclared backends are BYTE-IDENTICAL to before this leg: the reader is
  #     never invoked, nothing is printed, land proceeds exactly as it always has.
  # I2 parity (hooks/pre-push's `_seam_tracker_prepare`): SEAM_RECORD/SEAM_HEAD are plain shell
  # variables, never exported — cleared at this block's OWN entry, so a caller-inherited value never
  # leaks in, and neither is left set (nor exported) on exit unintentionally.
  unset SEAM_RECORD SEAM_HEAD
  _land_row="$(git log -1 --no-show-signature --format='%(trailers:key=Kit-Row,valueonly)' "$asha" 2>/dev/null | head -1)"
  _land_a9_lib="$ROOT/conformance/backlog-lib.sh"
  if [ -n "$_land_row" ] && [ -f "$_land_a9_lib" ] && [ -r "$_land_a9_lib" ]; then
    # shellcheck disable=SC1090  # dynamic source path; readability checked above
    . "$_land_a9_lib"
    # shellcheck disable=SC2034  # SEAM_ROOT is read by the sourced backlog-lib.sh seam functions
    SEAM_ROOT=$ROOT
    if _land_backend=$(seam_backend 2>/dev/null); then _land_bkrc=0; else _land_bkrc=$?; fi
    case "$_land_bkrc:$_land_backend" in
      0:github | 0:jira | 0:ado | 0:linear | 0:gitlab)
        _land_tconf="$ROOT/.kit/tracker.conf"
        if [ -f "$_land_tconf" ] && [ -r "$_land_tconf" ]; then
          _land_torigin=$(mktemp 2>/dev/null) || _land_torigin=""
          if [ -n "$_land_torigin" ] \
              && { git -C "$ROOT" show origin/main:.kit/tracker.conf 2>/dev/null \
                    || git -C "$ROOT" show origin/master:.kit/tracker.conf 2>/dev/null; } >"$_land_torigin" \
              && [ -s "$_land_torigin" ]; then
            # M2 (parity with pre-push): an absolute git-dir so the record path holds for linked
            # worktrees / `.git`-file setups too. S-10: fixed, per-repo, never env-inherited.
            _land_trecord="$(git -C "$ROOT" rev-parse --absolute-git-dir)/kit-tracker-local-record"
            # LAND_TRACKER_READER — an injectable, EVAL'D via `sh -c`, exactly the
            # PREPUSH_TRACKER_READER/BOARD_DRIFT_PR_STATE convention: set ONLY from trusted config
            # (the selftest's own fixture), NEVER from repo/PR input.
            if [ -n "${LAND_TRACKER_READER:-}" ]; then
              if _land_rdout=$(sh -c "$LAND_TRACKER_READER"' "$@"' sh "$_land_tconf" "$_land_torigin" \
                  "$_land_trecord" "$_land_row" "$asha" ready in-progress in-review 2>&1); then
                _land_rdrc=0
              else
                _land_rdrc=$?
              fi
            else
              if _land_rdout=$(sh "$ROOT/scripts/tracker-read.sh" "$_land_tconf" "$_land_torigin" \
                  "$_land_trecord" "$_land_row" "$asha" ready in-progress in-review 2>&1); then
                _land_rdrc=0
              else
                _land_rdrc=$?
              fi
            fi
            rm -f "$_land_torigin"
            if [ "$_land_rdrc" -eq 0 ]; then
              # shellcheck disable=SC2034  # SEAM_RECORD/SEAM_HEAD are read cross-source by backlog-lib.sh seam_row_state via the $()-subshell below (SEAM_RECORD = the record path; SEAM_HEAD checked by H-2, backlog-lib.sh:1045); shellcheck cannot trace it. NOT exported (E3, closes the L1 env-leak twin of pre-push M-2).
              SEAM_RECORD=$_land_trecord
              # shellcheck disable=SC2034  # (as above) SEAM_HEAD read cross-source by seam_row_state's H-2 subject-sha check
              SEAM_HEAD=$asha
              if _land_rowstate=$(seam_row_state "$_land_row" 2>/dev/null); then
                _land_srsrc=0
              else
                _land_srsrc=$?
              fi
              unset SEAM_RECORD SEAM_HEAD
              if [ "$_land_srsrc" -eq 0 ]; then
                case "$_land_rowstate" in
                  in-progress | in-review) : ;;   # still in-flight — proceed
                  *)
                    echo "LAND REFUSED (HYGIENE): a fresh re-read of $_land_row shows it has LEFT the" >&2
                    echo "              in-flight states (now '$_land_rowstate'). This is an AGENT-SIDE" >&2
                    echo "              hygiene check, not a binding control (the binding form is B5," >&2
                    echo "              D-240919-2(7)) — re-open/return the row, confirm this merge is" >&2
                    echo "              still correct, or use the land override for this class if one" >&2
                    echo "              exists before re-running." >&2
                    return 1 ;;
                esac
              fi
              # _land_srsrc != 0 (unverified/ambiguous on an otherwise-bound record) -> N/A, proceed;
              # hygiene never hard-blocks on a non-answer.
            fi
            # _land_rdrc != 0 (no token / S-2 mismatch / unreachable / no adapter) -> N/A, proceed;
            # nothing further printed here (S-6) — the reader's own sentence is not relayed on land's
            # path, since a can't-read here is never a refusal.
          else
            rm -f "$_land_torigin" 2>/dev/null || true
            # No origin pin to compare -> N/A, proceed. FAIL-CLOSED (S-2): the token is NEVER sent.
          fi
        fi
        ;;
      *) : ;;   # md, empty, unrecognized:*, or seam_backend rc2 — byte-identical, reader never runs
    esac
  fi

  # 2c. SWAS-901: solo only (a no-op elsewhere): the head's solo-go-bound runs. The note is already on origin, so a re-run sees it.
  pv_sg_gate land "$_land_sn" "${_land_full:-$asha}" "${_land_bref#refs/heads/}" || return 1

  # 3. Default merge = the CP-safe direct path, PINNED to the approved sha; never --admin, never
  #    --delete-branch. Swappable via --merge-cmd (tests pass a stub). --match-head-commit binds the
  #    merge to the exact reviewed head, so a race that advanced the PR branch is rejected server-side.
  [ -n "$merge_cmd" ] || merge_cmd="gh pr merge \"$ref\" --squash --match-head-commit \"$asha\""

  # 3b+4. VET the merge command: the shared helper (metacharacters, branch deletion, --admin), extracted from
  #     this verb UNCHANGED in SWAS-207a so `actuate` runs the very same vet. See pv_merge_cmd_vet.
  pv_merge_cmd_vet land "$merge_cmd" || return 1

  # 4c. THE LAND LEASE (SWAS-192 slice B, B7): in a checkout that opted in to the checkout lease, the merge runs under the land lease on origin,
  #     taken here with this process's own pid and the checkout token, and returned after step 6 (and by the EXIT/INT/TERM/HUP trap on any way out).
  #     HELD is rc 5, before anything is merged; the GO note IS recorded and `land` can be re-run.
  pv_land_lease_take land || return $?

  # 5. MERGE. Non-zero -> loud failure and propagate; the GO note IS already recorded and recoverable,
  #    so only the merge did not complete.
  if eval "$merge_cmd"; then _mrc=0; else _mrc=$?; fi
  if [ "$_mrc" -ne 0 ]; then
    echo "LAND FAILED: merge command exited $_mrc (the GO note IS recorded and recoverable; only the" >&2
    echo "             merge did not complete). Re-run the merge, or land again — record supersedes." >&2
    if [ "$_mrc" -eq 3 ]; then _mrc=1; fi   # the merge command's own rc 3 must not read as "merged, tree mismatch" (SWAS-323b)
    return "$_mrc"
  fi

  # 5b. THE POST-MERGE TREE (SWAS-323b, design 4): the new tip of origin's default branch must carry the land record's landed-tree. A mismatch
  #     is the loud SHIPPED != APPROVED line and rc 1, as `actuate`'s post-check prints it, and it never skips step 6 (the merge HAS happened).
  #     When origin's default branch has not moved, the merge result is not visible yet (a forge that merges later, or a stubbed merge command):
  #     that is said as UNVERIFIED, never as a pass, and `trace --recent` checks the trunk commit by tree once it lands.
  _land_post=0
  _land_ntip="$(pv_remote_ref_sha "$_land_bref" || true)"
  if [ -n "$_land_ntip" ] && [ "$_land_ntip" != "$_land_base" ]; then
    if git fetch --refmap= --no-tags origin "$_land_bref" >/dev/null 2>&1 && _land_ntree="$(git rev-parse -q --verify 'FETCH_HEAD^{tree}' 2>/dev/null)"; then
      if [ "$_land_ntree" != "$atree" ]; then
        echo "SHIPPED != APPROVED: origin's ${_land_bref#refs/heads/} tree after the merge ($_land_ntree) is not the land record's landed-tree ($atree) — the merge carried something the GO did not approve." >&2
        echo "land: the merge HAPPENED (exit 3 = merged, tree mismatch; it is NOT 'refused, nothing merged')." >&2
        _land_post=3
      fi
    else
      echo "land: the new tip of origin's ${_land_bref#refs/heads/} could not be fetched, so the post-merge tree is UNVERIFIED here (trace --recent checks it by tree)."
    fi
  else
    echo "land: origin's ${_land_bref#refs/heads/} (assumed to be the PR's base) has not moved yet, so the post-merge tree check is UNVERIFIED here (a merge queue or auto-merge lands later; trace --recent checks the trunk commit by tree once it lands)."
  fi

  # 6. RELEASE THE ROW'S OWN BOARD CLAIM — the same shared helper `actuate` calls, and the gap that
  #    left eight stale claim refs behind on 2026-09-15 (B2-SESSION-IDENTITY-LEDGER decision 6). It
  #    runs AFTER the merge and can only WARN. The note text is read back from the ref `record` just
  #    wrote and confirmed on origin, so the `kit-row:` projection is the note's own, never a flag.
  _land_note="$(git notes --ref="$NOTES_REF" show "$asha" 2>/dev/null || true)"
  pv_release_claim "$_land_note" land
  pv_land_lease_return   # the land lease goes back after the claim release (the trap returns it on any other way out)

  # Honest success line, VERB-SCOPED: the record was written BEFORE the merge, so THIS merge is
  # recoverable by this verb — not that recordless merges are impossible (they are detected later by
  # the CI backstop, which stays the friction-test gate).
  [ -z "$PV_STOP_LINE" ] || printf '%s\n' "$PV_STOP_LINE"
  pv_handover land   # MUT-HO-OK
  echo "OK: land recorded the GO note on $asha, CONFIRMED it on origin, and merged $ref — $_land_cls_lc"
  if [ "$_land_rkind" = oneact ]; then
    printf '%s\n' "    GO = forge review $PV_FR_ID by $(printf '%s' "$land_aby" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-80) (go-act: review): the approval on the exact head was the GO; no typed GO."
  fi
  if [ "$PV_REL" = solo ]; then
    echo "    merged on your recorded GO, bound to the head sha (solo); the GO-giver is recorded by name,"
    echo "    self-asserted, and nothing authenticated it. The record was published BEFORE the merge and verified on origin, so this merge"
  elif [ "$_land_rkind" = oneact ]; then
    echo "    merged on an authenticated non-author forge approval; go-by is that same login, authenticated (github-review), not self-asserted."
    echo "    The record was published BEFORE the merge and verified on origin, so this merge"
  else
    echo "    merged on an authenticated non-author forge approval; the GO-giver is recorded by name,"
    echo "    self-asserted. The record was published BEFORE the merge and verified on origin, so this merge"
  fi
  echo "    is recoverable. HONEST CEILING: the approval label was derived over the local gh credential at"
  echo "    record time (a drift control at the note's own tier), so server-side branch protection +"
  echo "    required review is what binds; the net for a recordless merge is the CI recordless-merge"
  echo "    backstop."
  echo "${PV_BOARD_TAIL:-board: NOT CLOSED — see the WARN above}"
  return "$_land_post"
}

# ---------------------------------------------------------------------------------------------
# sync — reconcile a DIVERGED local ledger with origin's (design 2026-09-29, PROMOTION-LEDGER-SYNC-VERB).
# Steps 1-9: front door, fetch, fast paths, classify by TREE CONTENT (1-4), re-validate every candidate
# (5), build, back up, swap, publish (6-8), postcondition (9); and --dry-run through step 5. The exit
# codes (0 reconciled / nothing to do; 2 refused, unreachable or a loud rare failure; 130/143 a signal)
# are stated in the contract's exit-code paragraph: docs/governance/promotion-contract.md §sync.
# ---------------------------------------------------------------------------------------------
# I4: a temp NOTES ref is named literally under refs/notes/ — `git notes --ref=refs/kit/x` silently
# writes refs/notes/refs/kit/x (MEASURED), which the trap would never delete.
NOTES_SYNCREF="refs/notes/kit-sync-$$"
# --no-deref, as for the scratch ref (B1): never delete THROUGH a symbolic ref planted at this name.
_pv_drop_syncref() { git update-ref --no-deref -d "$NOTES_SYNCREF" >/dev/null 2>&1 || true; }
# DEFERRED SIGNALS (C9, then fix round 1 F1). INT/TERM must STOP the run (130/143) — the old trap cleaned
# up and let the script carry on — but a stop INSIDE `record`'s write->push->unwind window (or `sync`'s
# backup->swap->push->unwind->postcondition window) breaks the publish-or-unwind guarantee: it leaves an
# UNPUBLISHED local note (the #658 stranded note) or leaves the publish state unknown. The handler cannot
# know whether an interrupted push reached origin, so it must NOT unwind. It only RECORDS the signal
# (_pv_sig) while _pv_crit=1; leaving the section (_pv_crit_leave) exits with that code, having
# published or unwound. Outside a section it cleans up and exits at once. The EXIT trap below drops BOTH
# temp refs (the scratch ref and the sync build ref).
_pv_sig=""; _pv_crit=0
_pv_die() { _pv_drop_scratch; _pv_drop_syncref; exit "$1"; }
_pv_crit_enter() { [ -z "$_pv_sig" ] || _pv_die "$_pv_sig"; _pv_crit=1; }
_pv_crit_leave() { _pv_crit=0; [ -z "$_pv_sig" ] || _pv_die "$_pv_sig"; }
# THE LAND LEASE (SWAS-192 slice B, B7). `land` and `actuate` take `refs/leases/land` on origin just before the merge and return it after the claim
# release; the EXIT trap returns it on every other way out (a failed merge, a refused step, a signal: INT/TERM/HUP all exit through it). A trap runs
# once the foreground merge command has ended, so a signal sent while the merge runs returns the lease when that command finishes. (A signal in the
# instant between the lease push and the capture of its token leaves the lease held; this process is then dead, which checkout-lease.sh proves, so the
# next holder breaks it at once, B8.) Only in a checkout
# that opted in (`_pv_ltok`, the checkout token, is set); any other checkout runs as before, plus ONE warning line when the land lease is held.
_pv_llt=""
# pv_land_lease_take <verb> -> rc 0 (held, or nothing to take) · 5 refused (sentences printed; nothing merged)
pv_land_lease_take() {
  _pv_llt=""
  if [ -z "${_pv_ltok:-}" ]; then
    # one ls-remote, and only the line that ends in a tab and exactly this ref counts (a pattern also matches `<prefix>/refs/leases/land`)
    if [ -f "${_pv_lsh:-/nonexistent}" ] && git ls-remote origin refs/leases/land 2>/dev/null | awk -F '\t' '$2 == "refs/leases/land" { f = 1 } END { exit !f }'; then
      echo "$1: WARN — the land lease on origin (refs/leases/land) is held by another holder; this checkout has not opted in to the lease, so $1 runs as it always did." >&2
    fi
    return 0
  fi
  _pv_lrc=0; _pv_lout=$(sh "$_pv_lsh" acquire --lease land --purpose "$1" --pid "$$" --lease-token "$_pv_ltok" 2>&1) || _pv_lrc=$?   # MUT-LGATE
  if [ "$_pv_lrc" -ne 0 ]; then
    printf '%s\n' "$_pv_lout" | LC_ALL=C tr -cd '[:print:]\n' >&2
    echo "$1: REFUSED — the land lease is held or could not be taken (above). The GO note IS recorded; nothing was merged. Re-run $1 once the land lease is released." >&2
    return 5
  fi
  _pv_llt=$(printf '%s\n' "$_pv_lout" | sed -n 's/^lease-token: //p' | head -1)
  return 0
}
# pv_land_lease_return -> returns the land lease this run took (idempotent; a failure is a WARN, never a new exit code)
pv_land_lease_return() {
  [ -n "${_pv_llt:-}" ] || return 0
  _pv_lt=$_pv_llt; _pv_llt=""
  sh "$_pv_lsh" release --lease land --lease-token "$_pv_lt" >/dev/null 2>&1 || echo "WARN — the land lease was not returned (refs/leases/land on origin may still be held, and the next land or actuate is refused (rc 5) until a person runs 'sh scripts/checkout-lease.sh break --lease land --reason <why>', outside any kit-guard shims; SWAS-842)." >&2
  return 0
}
trap '_pv_drop_scratch; _pv_drop_syncref; pv_land_lease_return || :' EXIT   # MUT-LTRAP
trap '_pv_sig=130; [ "$_pv_crit" = 1 ] || _pv_die 130' INT
trap '_pv_sig=143; [ "$_pv_crit" = 1 ] || _pv_die 143' TERM
trap '_pv_sig=129; [ "$_pv_crit" = 1 ] || _pv_die 129' HUP

_pv_sync_clean() { LC_ALL=C tr -d '\000-\011\013-\037\177'; }
_pv_sync_hex40() { case "$1" in
    *[!0-9a-f]*|'') return 1 ;;
  esac; [ "${#1}" = 40 ]; }
# ECHO SWEEP (whole-branch fix round 1, A5/B2): dash's builtin `echo` EXPANDS `\0NNN`, so an `echo` of any
# variable that holds note text, a git-derived string or a remote string can emit a terminal escape on
# Linux (and bash-as-sh on macOS does the same). Every message below that interpolates such text is a
# `printf '%s\n'`, and the untrusted ones also go through _pv_sync_clean.
_pv_sync_say() { if [ "$_sy_dry" = 1 ]; then printf '%s\n' "WOULD $*"; else printf '%s\n' "$*"; fi; }
_pv_sync_is_discard() { case " $_sy_disc " in
    *" $1 "*) return 0 ;;
  esac; return 1; }
# FAIL-CLOSED READS (fix round 1): `do_sync` runs under `if`, so `set -e` is OFF. Every git read that
# feeds the classification is captured into a variable FIRST and its rc checked; only then is the
# text post-processed. A failed read is a refusal (rc 2), never "no difference" / "no history".
# _pv_sync_blob <ls-tree listing> <object-sha> — the blob id of that object's note, fanout-agnostic;
# empty = absent. (Pure text post-processing of an already-captured listing; no git call.)
_pv_sync_blob() {
  printf '%s\n' "$1" | while read -r _bm _bt _bb _bp; do
    if [ "$(printf '%s' "$_bp" | tr -d '/')" = "$2" ]; then printf '%s\n' "$_bb"; break; fi
  done
}
# _pv_sync_refuse_read <what> — the one refusal shape for a failed git read.
_pv_sync_refuse_read() { printf '%s\n' "sync: cannot $1 — REFUSED; the ledger is unchanged." | _pv_sync_clean >&2; return 2; }
# _pv_sync_refsha <full-ref> — that ref's object id (empty = the ref is absent); rc 2 if the read fails.
# C2: a BROKEN ref (it names an object that is not there) must refuse, never read as ABSENT: some git
# versions make `for-each-ref` skip such a ref with rc 0. So resolve the ref directly first (that prints
# the id even for a broken ref), check that the object exists, and only THEN treat "does not resolve" as
# absent — and only if for-each-ref does not list the name either.
_pv_sync_broken() { printf '%s\n' "sync: ledger ref $1 is broken (it does not name a readable object) — REFUSED; nothing changed." >&2; }
_pv_sync_refsha() {
  _rs_o="$(git rev-parse -q --verify "$1" 2>/dev/null)" || _rs_o=""
  # F3: EXACT full refname only. `rev-parse --verify` DWIMs `refs/notes/x` to `refs/heads/refs/notes/x` when
  # no notes ref exists (measured, git 2.48.1), so a branch of that name would read as the ledger. A resolve
  # that landed on any other ref is not this ref: fall through to the absent/broken check below.
  if [ -n "$_rs_o" ]; then
    _rs_f="$(git rev-parse -q --symbolic-full-name "$1" 2>/dev/null)" || _rs_f=""
    if [ "$_rs_f" = "$1" ]; then
      git rev-parse -q --verify "$_rs_o^{object}" >/dev/null 2>&1 || { _pv_sync_broken "$1"; return 2; }
      printf '%s\n' "$_rs_o"; return 0
    fi
  fi
  _rs_l="$(git for-each-ref --format='%(refname)' "$1" 2>/dev/null)" || { _pv_sync_broken "$1"; return 2; }
  if printf '%s\n' "$_rs_l" | grep -qxF "$1"; then _pv_sync_broken "$1"; return 2; fi
  return 0
}
_pv_sync_field() { printf '%s\n' "$1" | sed -n "s/^$2: //p" | head -1; }
# _pv_sync_resolve <hex> — the commit a (possibly abbreviated) sha names, or failure.
_pv_sync_resolve() {
  case "$1" in
    *[!0-9a-f]*|'') return 1 ;;
  esac
  git rev-parse -q --verify "$1^{commit}" 2>/dev/null
}
# R1: identity fields byte-exact (approved-sha compared RESOLVED); only token/basis/recorded-at may differ.
_pv_sync_same_identity() {
  for _ik in approved-tree approved-by gate rung change-class kit-row scope; do
    [ "$(_pv_sync_field "$1" "$_ik")" = "$(_pv_sync_field "$2" "$_ik")" ] || return 1
  done
  # go-by is an IDENTITY field (GO-IDENTITY-AND-LAND-SOD): a twin with a different GO-giver is a different
  # GO. A LEGACY note carries no go-by line and counts as `(none recorded)`, the same as a new note without one.
  _ig1="$(_pv_sync_field "$1" go-by)"; _ig2="$(_pv_sync_field "$2" go-by)"
  [ "${_ig1:-"(none recorded)"}" = "${_ig2:-"(none recorded)"}" ] || return 1
  # go-act (SWAS-727) is an IDENTITY field too: a one-act GO and a typed GO on the same commit are different GOs. A note without
  # it (every legacy and every ordinary note) reads empty on both sides.
  [ "$(_pv_sync_field "$1" go-act)" = "$(_pv_sync_field "$2" go-act)" ] || return 1
  _ia="$(_pv_sync_field "$1" approved-sha)"; _ib="$(_pv_sync_field "$2" approved-sha)"
  [ "$_ia" = "$_ib" ] && return 0
  _ia="$(_pv_sync_resolve "$_ia")" || return 1
  _ib="$(_pv_sync_resolve "$_ib")" || return 1
  [ "$_ia" = "$_ib" ]
}
_pv_sync_refuse() { _sy_refused=$((_sy_refused + 1)); }
_pv_sync_discarded() { # <sha> <why>
  _pv_sync_say "discarded-local $1 ($2)"; _sy_used="$_sy_used $1"; _sy_drop=$((_sy_drop + 1)); _sy_dn=$((_sy_dn + 1))
}
# SWAS-323: a note is a LIST of records, and the identity check below reads the first record only. Until sync learns a record-wise
# union (its own card), a multi-record note on either side of a twin, or as a local-only candidate, is REFUSED (fail closed).
_pv_sync_multi() { [ "$(printf '%s\n' "$1" | kit_note_records n)" -gt 1 ]; }
_pv_sync_refuse_multi() { # <sha> <what>
  printf '%s\n' "sync: REFUSED $1: $2 holds more than one record, and sync compares and publishes one record per commit (a record-wise union is not built)." >&2
  printf '%s\n' "        remedy: sync --discard-local $1   (origin's note wins; nothing published), then re-record what you need" >&2
  _pv_sync_refuse
}
_pv_sync_twin() { # <sha> <origin-body> <local-body>
  if _pv_sync_multi "$2" || _pv_sync_multi "$3"; then
    if _pv_sync_is_discard "$1"; then _pv_sync_discarded "$1" "multi-record twin"; return 0; fi
    _pv_sync_refuse_multi "$1" "the note on one side of this twin"; return 0
  fi
  if _pv_sync_same_identity "$2" "$3"; then
    _pv_sync_say "twin-origin-wins $1"; _sy_drop=$((_sy_drop + 1)); _sy_ow=$((_sy_ow + 1)); return 0
  fi
  if _pv_sync_is_discard "$1"; then _pv_sync_discarded "$1" "identity twin"; return 0; fi
  printf '%s\n' "sync: REFUSED $1: same commit, DIFFERENT identity (approved-by/go-by/tree/gate/rung/class/row/scope)." >&2
  echo "--- origin's note ---" >&2; printf '%s\n' "$2" | _pv_sync_clean >&2
  echo "--- local note ---" >&2;    printf '%s\n' "$3" | _pv_sync_clean >&2
  printf '%s\n' "        remedy: sync --discard-local $1   (origin's note wins; nothing published)" >&2
  _pv_sync_refuse
}
_pv_sync_local_only() { # <sha> <local-blob> — a candidate, unless origin's history ever carried it (voided upstream)
  if [ -n "$_sy_hist" ] && printf '%s\n' "$_sy_hist" | grep -qx "$1"; then
    if _pv_sync_is_discard "$1"; then _pv_sync_discarded "$1" "voided upstream"; return 0; fi
    printf '%s\n' "sync: REFUSED $1: origin once carried a note on this commit and no longer does (VOIDED upstream)." >&2
    printf '%s\n' "        Re-publishing it would resurrect a voided record. remedy: sync --discard-local $1" >&2
    _pv_sync_refuse; return 0
  fi
  if _pv_sync_is_discard "$1"; then _pv_sync_discarded "$1" "candidate dropped"; return 0; fi
  _lo_body="$(git cat-file blob "$2" 2>/dev/null)" || _lo_body=""
  if _pv_sync_multi "$_lo_body"; then _pv_sync_refuse_multi "$1" "the local-only note"; return 0; fi
  _pv_sync_say "candidate $1"; _sy_cand=$((_sy_cand + 1))
  _sy_cands="$_sy_cands$1 $2
"
  return 0
}
# Both notes exist with DIFFERENT blob ids (trailing-newline-only differences included — F7): read
# both bodies (rc checked) and apply the twin rule.
_pv_sync_twin_blobs() { # <sha> <origin-blob> <local-blob>
  _ob="$(git cat-file blob "$2")" || { _pv_sync_refuse_read "read origin's note blob for $1"; return 2; }
  _lb="$(git cat-file blob "$3")" || { _pv_sync_refuse_read "read the local note blob for $1"; return 2; }
  _pv_sync_twin "$1" "$_ob" "$_lb"
}
_pv_sync_one() { # <origin-listing> <local-listing> <sha>
  _oo="$(_pv_sync_blob "$1" "$3")"; _ll="$(_pv_sync_blob "$2" "$3")"
  if [ -n "$_oo" ] && [ -z "$_ll" ]; then
    _pv_sync_say "kept-origin $3 (local-absent)"; return 0
  fi
  if [ -z "$_oo" ] && [ -n "$_ll" ]; then _pv_sync_local_only "$3" "$_ll"; return 0; fi
  if [ -z "$_oo" ]; then
    _pv_sync_refuse_read "find a note for $3 on either side although the trees differ"; return 2
  fi
  [ "$_oo" != "$_ll" ] || return 0
  _pv_sync_twin_blobs "$3" "$_oo" "$_ll"
}
# _pv_sync_shallow_check — B4, refined (C3): the voided arm reads the ledger's HISTORY, so refuse only when a
# ledger chain (the LOCAL tip _sy_lt, or origin's fetched tip _sy_st) is TRUNCATED, i.e. it contains a commit listed in
# the shallow file. A shallow BRANCH clone whose notes chain was fetched in full is fine. Fail-closed: any read
# failure refuses. No shallow file (or an empty one) -> nothing to check.
_pv_sync_shallow_check() {
  _sh_f="$(git rev-parse --git-path shallow)" || { _pv_sync_refuse_read "locate the shallow file"; return 2; }
  [ -s "$_sh_f" ] || return 0
  for _sh_t in "$_sy_lt" "$_sy_st"; do
    [ -n "$_sh_t" ] || continue
    _sh_l="$(git rev-list "$_sh_t")" || { _pv_sync_refuse_read "walk a ledger chain (the shallow check)"; return 2; }
    _sh_rc=0; _sh_hit="$(printf '%s\n' "$_sh_l" | grep -F -x -f "$_sh_f")" || _sh_rc=$?
    case "$_sh_rc" in
      1) ;;
      0) printf '%s\n' "sync: the ledger history is TRUNCATED by a SHALLOW fetch (commit $(printf '%s' "$_sh_hit" | head -n 1 | _pv_sync_clean) is a shallow boundary) — origin's older ledger history is not present, so the voided-upstream check would be blind; REFUSED; the ledger is unchanged." >&2
         printf '%s\n' "      Deepen it first (git fetch --unshallow), then re-run." >&2
         return 2 ;;
      *) _pv_sync_refuse_read "intersect a ledger chain with the shallow file"; return 2 ;;
    esac
  done
  return 0
}
# _pv_sync_classify <origin-base> <local-tip> — TREE-content classification (never commit-based).
# Sets _sy_refused/_sy_cand/_sy_drop; prints one line per record. rc 2 = a git read failed (refused).
_pv_sync_classify() {
  _sy_refused=0; _sy_cand=0; _sy_drop=0; _sy_used=""; _sy_cands=""; _sy_ow=0; _sy_dn=0
  _pv_sync_shallow_check || return 2
  # --full-tree: `ls-tree` otherwise shows only the cwd's own subtree when run from a subdirectory.
  _cl_ot="$(git ls-tree -r --full-tree "$1")" || { _pv_sync_refuse_read "list origin's ledger tree"; return 2; }
  _cl_lo="$(git ls-tree -r --full-tree "$2")" || { _pv_sync_refuse_read "list the local ledger tree"; return 2; }
  _pv_sync_resolve_prefixes || return 2
  _cl_raw="$(git diff-tree -r --no-renames --name-only "$1" "$2")" || { _pv_sync_refuse_read "diff the local and origin ledger trees"; return 2; }
  _cl_shas="$(printf '%s\n' "$_cl_raw" | tr -d '/' | sort -u)"
  # A `while read` over the captured text: a `for x in $var` would pathname-expand a '*' path (F4).
  # The heredoc's lone `\` first line is dropped by the shell (unquoted heredoc); semgrep's bash grammar needs it to parse this loop whole.
  while IFS= read -r _cs; do
    if ! _pv_sync_hex40 "$_cs"; then
      # B3: a non-40-hex path on the LOCAL side is refused, never dropped (it would vanish with no backup);
      # this also covers a SHA-256 repository (64-hex paths). An origin-only oddity is origin's own.
      if [ -n "$(_pv_sync_blob "$_cl_lo" "$_cs")" ]; then
        printf '%s\n' "sync: REFUSED: the local ledger holds an entry '$(printf '%s' "$_cs" | _pv_sync_clean)' that is not a 40-hex note path (a non-note entry, or a SHA-256 repository) — sync cannot classify it; nothing written." >&2
        printf '%s\n' "      sync cannot discard it (--discard-local names notes only). Inspect it with: git ls-tree -r refs/notes/$NOTES_REF" >&2
        printf '%s\n' "      Removing a non-note entry is an operator-only plumbing repair (D-240805-3: a raw notes write is guard-denied for agents)." >&2
        return 2
      fi
      continue
    fi
    _pv_sync_one "$_cl_ot" "$_cl_lo" "$_cs" || return 2
  done <<EOF
\
$_cl_shas
EOF
  set -f
  for _cd in $_sy_disc; do
    case " $_sy_used " in
      *" $_cd "*) ;;
      *) printf '%s\n' "sync: note: --discard-local $_cd matched no refused or candidate record" >&2 ;;
    esac
  done
  set +f
  return 0
}
# _pv_sync_resolve_prefixes — resolve each short --discard-local prefix against the NOTE PATHS of the two
# listings just read (A1): a note can name a commit this clone does not have (V2's "object absent", a voided
# note, an identity twin), so a prefix can never be resolved against COMMITS. Unique -> added to _sy_disc;
# unknown or ambiguous -> refuse (rc 2) naming the value. Pure text over the captured listings.
_pv_sync_prefix_hits() { # <prefix> — every note path (slashes stripped) in either listing that starts with it
  printf '%s\n%s\n' "$_cl_ot" "$_cl_lo" | while read -r _bm _bt _bb _bp; do
    _rq="$(printf '%s' "$_bp" | tr -d '/')"
    case "$_rq" in
      "$1"*) printf '%s\n' "$_rq" ;;
    esac
  done
}
_pv_sync_resolve_prefixes() {
  set -f
  for _rp in $_sy_pref; do
    _rp_hits="$(_pv_sync_prefix_hits "$_rp" | sort -u | grep -x '[0-9a-f]\{40\}')" || _rp_hits=""
    _rp_n="$(printf '%s' "$_rp_hits" | grep -c . || true)"
    if [ "$_rp_n" = 0 ]; then
      set +f; printf '%s\n' "sync: --discard-local '$_rp' matches no note in the local or origin ledger — REFUSED; nothing changed." >&2; return 2
    fi
    if [ "$_rp_n" != 1 ]; then
      set +f; printf '%s\n' "sync: --discard-local '$_rp' is ambiguous ($_rp_n notes share that prefix) — REFUSED; give more characters (or the full 40-hex)." >&2; return 2
    fi
    _sy_disc="$_sy_disc $_rp_hits"
  done
  set +f
  return 0
}
# _pv_sync_args "$@" — parses flags into _sy_dry / _sy_disc / _sy_pref; returns 2 on a bad flag.
# --discard-local takes a LOWERCASE hex value: 40 chars are used AS-IS (the object need not exist — the
# remedy the refusals print must run when the approved commit is absent); 4-39 chars are a PREFIX, resolved
# later against the ledger listings (_pv_sync_resolve_prefixes). Uppercase / non-hex is refused here.
_pv_sync_args() {
  _sy_dry=0; _sy_disc=""; _sy_pref=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) _sy_dry=1; shift ;;
      --discard-local)
        _dv="${2:-}"
        case "$_dv" in
          ''|*[!0123456789abcdef]*) _dv="" ;;
        esac
        if [ "${#_dv}" = 40 ]; then _sy_disc="$_sy_disc $_dv"
        elif [ "${#_dv}" -ge 4 ] && [ "${#_dv}" -lt 40 ]; then _sy_pref="$_sy_pref $_dv"
        else
          printf '%s\n' "sync: --discard-local '$(printf '%s' "${2:-}" | _pv_sync_clean)' must be a lowercase 40-hex sha, or a lowercase hex prefix (4+ chars) of a note in the ledger" >&2; return 2
        fi
        shift 2 ;;
      *) printf '%s\n' "sync: unknown arg '$(printf '%s' "$1" | _pv_sync_clean)'" >&2; usage; return 2 ;;
    esac
  done
}
# _pv_sync_fetch — step 2. Sets _sy_st (origin tip) and _sy_hist; probe 2 = origin has no ledger.
_pv_sync_fetch() {
  _sy_st=""; _sy_hist=""; _sy_base="4b825dc642cb6eb9a060e54bf8d69288fbee4904"
  if git ls-remote --exit-code origin "refs/notes/$NOTES_REF" >/dev/null 2>&1; then _sy_probe=0; else _sy_probe=$?; fi
  case "$_sy_probe" in
    0) _pv_scratch_free sync || return 2   # N3: re-checked on EVERY attempt (attempt 2 re-fetches into the same name)
       if ! git fetch --refmap= --no-tags --no-recurse-submodules -f origin "refs/notes/$NOTES_REF:$NOTES_SCRATCH" >/dev/null 2>&1; then
         printf '%s\n' "sync: fetching refs/notes/$NOTES_REF from origin failed; refusing." >&2; return 2
       fi
       _pv_sync_refsha "$NOTES_SCRATCH" >/dev/null || return 2   # C2: a broken scratch ref refuses too
       _sy_st="$(git rev-parse -q --verify "$NOTES_SCRATCH^{commit}" 2>/dev/null)" || {
         _pv_sync_refuse_read "verify that origin's ledger is a readable commit"; return 2; }
       _sy_base="$_sy_st"
       # F3: --no-renames -m, so a note carried only by a MERGE commit still counts as history. Captured
       # FIRST, rc checked, THEN slash-stripped (a failed log must not read as "no history").
       # A2: `log` is PORCELAIN and reads user config — `--root` pins the root commit's listing (log.showRoot=false
       # would hide it), `--no-show-signature` pins out any `gpg:` lines (log.showSignature), `--no-renames` pins
       # diff.renames.
       _sy_hist="$(git log --root --no-show-signature --no-renames --diff-merges=separate --name-only --format= "$_sy_st")" || {
         _pv_sync_refuse_read "read origin's ledger history (the voided-upstream check)"; return 2; }
       _sy_hist="$(printf '%s\n' "$_sy_hist" | tr -d '/')" ;;
    2) printf '%s\n' "sync: origin has no refs/notes/$NOTES_REF yet — every local record is a candidate." >&2 ;;
    *) printf '%s\n' "sync: cannot reach the ledger remote — 'git ls-remote origin refs/notes/$NOTES_REF' exited $_sy_probe. A sync that cannot read origin is blind; REFUSED." >&2
       return 2 ;;
  esac
}
_pv_sync_cas() { # <new> <old> — compare-and-swap the ledger; refuse (rc 2) if it moved.
  if git update-ref "refs/notes/$NOTES_REF" "$1" "$2" >/dev/null 2>&1; then return 0; fi
  echo "sync: the ledger moved under this sync (compare-and-swap refused); nothing changed." >&2; return 2
}

# _pv_sync_local_tip — sets _sy_lt (the LOCAL ledger tip; empty = no local ledger). A ref that exists
# but is not a readable commit, or a failed read, is a refusal — never read as "no local ledger".
_pv_sync_local_tip() {
  _sy_lt=""
  _lt_raw="$(_pv_sync_refsha "refs/notes/$NOTES_REF")" || return 2   # refsha prints its own refusal (stderr passes through)
  [ -n "$_lt_raw" ] || return 0
  _sy_lt="$(git rev-parse -q --verify "$_lt_raw^{commit}" 2>/dev/null)" || {
    _sy_lt=""; _pv_sync_refuse_read "verify that the local ledger refs/notes/$NOTES_REF is a commit"; return 2; }
}
# _pv_sync_ff_probe — sets _sy_ff=1 when the local ledger is an ancestor of origin's tip (or absent while
# origin has one). merge-base --is-ancestor: rc 0 yes, rc 1 no, anything else is an ERROR -> refuse.
_pv_sync_ff_probe() {
  _sy_ff=0
  [ -n "$_sy_st" ] || return 0
  if [ -z "$_sy_lt" ]; then _sy_ff=1; return 0; fi
  _ff_rc=0; git merge-base --is-ancestor "$_sy_lt" "$_sy_st" >/dev/null 2>&1 || _ff_rc=$?
  case "$_ff_rc" in
    0) _sy_ff=1 ;;
    1) _sy_ff=0 ;;
    *) _pv_sync_refuse_read "compare the local ledger with origin's (merge-base exited $_ff_rc)"; return 2 ;;
  esac
}

# ---- step 5: RE-VALIDATE a candidate as exactly what `record` would write NOW (design §4, V1-V7) --------
# A stranded note and a plumbing-minted one look the same, so a candidate is published only if every
# check passes. NEVER rewritten, NEVER downgraded: `sync` publishes bytes it verified, not bytes it made.
# Every failure names the sha, the failed field, and both remedies (I2).
_pv_vc_fail() { # <field> <why>
  # $2 can carry NOTE text (a label, a kit-row, an approved-sha) and a commit's own trailer: printf, never
  # echo (dash expands \0NNN), and cleaned of control bytes (A5, B2).
  printf '%s\n' "sync: REFUSED $_vc_sha: the local note fails re-validation — $1: $2" | _pv_sync_clean >&2
  printf '%s\n' "        remedy: sync --discard-local $_vc_sha   (drops the local note; the backup ref keeps it)," >&2
  echo "                or re-issue the GO properly with promotion-verify.sh record" >&2
  return 1
}
# The keys, in `record`'s order (line 1 is the literal header, checked separately). FOUR SHAPES, because
# GO-IDENTITY-AND-LAND-SOD added `go-by` at line 5 and a ledger holds both: a NEW note is 13 lines
# (_vc_fmt=13) and a LEGACY note (written before) is 12 lines with no go-by (_vc_fmt=12). SWAS-727 adds two more, each the 13
# lines plus lines AFTER recorded-at: a ONE-ACT note (_vc_fmt=14, line 14 `go-act: review`) and a HELD-THEN-TYPED note
# (_vc_fmt=16, `go-act: separate`, `go-words`, `go-words-sha256`). The shape is read from the lines themselves (see
# _pv_vc_grammar), never guessed from a count alone.
_pv_vc_key() {
  if [ "$_vc_fmt" = 13 ] || [ "$_vc_fmt" = 14 ] || [ "$_vc_fmt" = 16 ]; then
    case "$1" in
      2) echo approved-sha ;; 3) echo approved-tree ;; 4) echo approved-by ;; 5) echo go-by ;;
      6) echo gate ;; 7) echo rung ;; 8) echo change-class ;; 9) echo kit-row ;; 10) echo scope ;;
      11) echo approval-token ;; 12) echo basis ;; 13) echo recorded-at ;;
      14) if [ "$_vc_fmt" != 13 ]; then echo go-act; fi ;;
      15) if [ "$_vc_fmt" = 16 ]; then echo go-words; fi ;;
      16) if [ "$_vc_fmt" = 16 ]; then echo go-words-sha256; fi ;;
    esac
    return 0
  fi
  case "$1" in
    2) echo approved-sha ;; 3) echo approved-tree ;; 4) echo approved-by ;; 5) echo gate ;;
    6) echo rung ;; 7) echo change-class ;; 8) echo kit-row ;; 9) echo scope ;;
    10) echo approval-token ;; 11) echo basis ;; 12) echo recorded-at ;;
  esac
}
# V1 — the body grammar: byte-exact `record` shape. Sets _vc_asha/_vc_tree/_vc_by/_vc_goby/_vc_gate/_vc_rung/
# _vc_cls/_vc_row/_vc_scope/_vc_tok/_vc_basis/_vc_ts from the note's own lines (_vc_goby is `(none recorded)`
# for a legacy note, which is what a new note without --go-by says too).
_pv_vc_grammar() {
  _vc_body="$(git cat-file blob "$_vc_blob")" || { _pv_vc_fail grammar "cannot read the note blob"; return 1; }
  _vc_sz="$(git cat-file -s "$_vc_blob")" || { _pv_vc_fail grammar "cannot size the note blob"; return 1; }
  _vc_len="$(printf '%s\n' "$_vc_body" | wc -c | tr -d ' ')"
  [ "$_vc_len" = "$_vc_sz" ] || { _pv_vc_fail grammar "not the record body plus exactly ONE trailing newline (or it holds a NUL byte)"; return 1; }
  [ "$(printf '%s' "$_vc_body" | _pv_sync_clean)" = "$_vc_body" ] || {
    _pv_vc_fail grammar "a control byte other than the line feeds"; return 1; }
  # THE SHAPE: line 5 is `go-by: ...` in a new note and `gate: ...` in a legacy one.
  _vc_fmt=12
  case "$(printf '%s\n' "$_vc_body" | sed -n '5p')" in
    "go-by: "*) _vc_fmt=13 ;;
  esac
  # SWAS-727: a 13-line note whose line 14 is `go-act: ...` is a one-act (review) or a held-then-typed (separate) note.
  _vc_goact=""; _vc_gow=""; _vc_gosha=""
  if [ "$_vc_fmt" = 13 ]; then
    case "$(printf '%s\n' "$_vc_body" | sed -n '14p')" in
      "go-act: review") _vc_fmt=14 ;;
      "go-act: separate") _vc_fmt=16 ;;
      "go-act: "*) _pv_vc_fail grammar "go-act is neither 'review' nor 'separate'"; return 1 ;;
    esac
  fi
  _vc_goby="(none recorded)"
  _vc_n=0
  # The heredoc's lone `\` first line is dropped by the shell (unquoted heredoc); semgrep's bash grammar needs it to parse this loop whole.
  while IFS= read -r _vc_l; do
    _vc_n=$((_vc_n + 1))
    # F4(b): `record` stores through `notes add -F -`, which strips trailing whitespace, so a line ending in a
    # space is not a body record wrote. (A trailing TAB is a control byte, refused above.)
    case "$_vc_l" in
      *' ') _pv_vc_fail grammar "line $_vc_n ends in a space (record never stores one)"; return 1 ;;
    esac
    if [ "$_vc_n" = 1 ]; then
      [ "$_vc_l" = "record: promotion GO (approve->execute->log)" ] || { _pv_vc_fail grammar "line 1 is not record's header"; return 1; }
      continue
    fi
    _vc_k="$(_pv_vc_key "$_vc_n")"
    [ -n "$_vc_k" ] || { _pv_vc_fail grammar "more than the $_vc_fmt lines record writes"; return 1; }
    case "$_vc_l" in
      "$_vc_k: "*) ;;
      *) _pv_vc_fail grammar "line $_vc_n is not '$_vc_k: ...'"; return 1 ;;
    esac
    _vc_v="${_vc_l#"$_vc_k: "}"
    case "$_vc_k" in
      approved-sha) _vc_asha="$_vc_v" ;; approved-tree) _vc_tree="$_vc_v" ;; approved-by) _vc_by="$_vc_v" ;;
      go-by) _vc_goby="$_vc_v" ;; gate) _vc_gate="$_vc_v" ;; rung) _vc_rung="$_vc_v" ;;
      change-class) _vc_cls="$_vc_v" ;; kit-row) _vc_row="$_vc_v" ;; scope) _vc_scope="$_vc_v" ;;
      approval-token) _vc_tok="$_vc_v" ;; basis) _vc_basis="$_vc_v" ;; recorded-at) _vc_ts="$_vc_v" ;;
      go-act) _vc_goact="$_vc_v" ;; go-words) _vc_gow="$_vc_v" ;; go-words-sha256) _vc_gosha="$_vc_v" ;;
    esac
  done <<EOF
\
$_vc_body
EOF
  [ "$_vc_n" = "$_vc_fmt" ] || { _pv_vc_fail grammar "$_vc_n lines, record writes exactly $_vc_fmt for this note's shape (12 legacy, 13 with go-by, 14 one-act review, 16 held-then-typed)"; return 1; }
  for _vc_f in "$_vc_asha" "$_vc_tree" "$_vc_by" "$_vc_goby" "$_vc_gate" "$_vc_rung" "$_vc_cls" "$_vc_row" "$_vc_scope" "$_vc_tok" "$_vc_basis" "$_vc_ts"; do
    [ -n "$_vc_f" ] || { _pv_vc_fail grammar "an empty field"; return 1; }
  done
  _pv_vc_goby || return 1
  _pv_vc_goact || return 1
  # F4(c): recorded-at is what `record` composes: `date -u +%Y-%m-%dT%H:%M:%SZ`, or the literal `unknown`.
  case "$_vc_ts" in
    unknown|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
    *) _pv_vc_fail recorded-at "not YYYY-MM-DDTHH:MM:SSZ or 'unknown'"; return 1 ;;
  esac
  case "$_vc_tok" in
    '"'*'"') [ "${#_vc_tok}" -ge 2 ] || { _pv_vc_fail grammar "approval-token is not \"...\""; return 1; } ;;
    *) _pv_vc_fail grammar "approval-token is not \"...\""; return 1 ;;
  esac
}
# V1b — go-by: exactly `(none recorded)` or `<name> [self-asserted]`, nothing else. The label is a FIXED literal
# `record` writes, never derived and never authenticated, so a note carrying ANY other label (a forged
# [authenticated: github-review], [committer], [signed: gpg]) is not one `record` could have written NOW.
# Checked inside V1 (pure string checks, no API call), so it runs before V7's forge derivation.
_pv_vc_goby() {
  [ "$_vc_fmt" != 14 ] || return 0   # a one-act note's go-by carries the authenticated label: _pv_vc_goact judges it
  [ "$_vc_goby" != "(none recorded)" ] || return 0
  case "$_vc_goby" in
    *' [self-asserted]') ;;
    *) _pv_vc_fail go-by "not '<name> [self-asserted]' or '(none recorded)' (the GO-giver is never authenticated)"; return 1 ;;
  esac
  _vc_gid="${_vc_goby%' [self-asserted]'}"
  [ -n "$(printf '%s' "$_vc_gid" | tr -d ' \t')" ] || { _pv_vc_fail go-by "the GO-giver name is whitespace-only (record refuses one)"; return 1; }
  case "$_vc_gid" in
    *'['*|*']'*) _pv_vc_fail go-by "a bracket inside the name (the label is a fixed literal, never supplied)"; return 1 ;;
  esac
  return 0
}
# V1c — the go-act shapes (SWAS-727). No API call; pure string checks. A ONE-ACT note (_vc_fmt=14) is accepted only when go-act is
# `review`, go-by and approved-by are the SAME login and both carry the fixed `[authenticated: github-review]` label, and the token is
# exactly "forge-review:<digits>" (no other byte). A HELD-THEN-TYPED note (_vc_fmt=16) only when go-act is `separate`, go-words-sha256 is
# 64 lowercase hex, go-words is one quoted line of at most 1000 bytes, and a named GO-giver (self-asserted, V1b) is recorded. The
# approved-by label is then re-derived by V7 like any other note's.
_pv_vc_goact() {
  case "$_vc_fmt" in
    14|16) ;;
    *) return 0 ;;
  esac
  if [ "$_vc_fmt" = 14 ]; then
    [ "$_vc_goact" = review ] || { _pv_vc_fail go-act "not 'review' in a one-act note"; return 1; }
    case "$_vc_goby" in
      *' [authenticated: github-review]') ;;
      *) _pv_vc_fail go-by "a one-act note's go-by must carry the fixed [authenticated: github-review] label"; return 1 ;;
    esac
    _vc_gid="${_vc_goby%' [authenticated: github-review]'}"
    [ -n "$_vc_gid" ] || { _pv_vc_fail go-by "empty login"; return 1; }
    case "$_vc_gid" in
      *'['*|*']'*|*' '*) _pv_vc_fail go-by "a bracket or a space inside the login (the label is a fixed literal)"; return 1 ;;
    esac
    [ "$_vc_by" = "$_vc_gid [authenticated: github-review]" ] || { _pv_vc_fail go-by "a one-act note's go-by must equal its approved-by (one authenticated identity in two fields)"; return 1; }
    case "$_vc_tok" in
      '"forge-review:'*'"') ;;
      *) _pv_vc_fail approval-token "a one-act note's token is exactly \"forge-review:<digits>\""; return 1 ;;
    esac
    _vc_tid="${_vc_tok#'"forge-review:'}"; _vc_tid="${_vc_tid%'"'}"
    case "$_vc_tid" in
      ''|*[!0-9]*) _pv_vc_fail approval-token "the review id is not digits"; return 1 ;;
    esac
    [ "${#_vc_tid}" -le 20 ] || { _pv_vc_fail approval-token "the review id is longer than 20 digits"; return 1; }
    return 0
  fi
  [ "$_vc_goact" = separate ] || { _pv_vc_fail go-act "not 'separate' in a held-then-typed note"; return 1; }
  [ "$_vc_goby" != "(none recorded)" ] || { _pv_vc_fail go-by "a held-then-typed note names its GO-giver"; return 1; }
  case "$_vc_gosha" in
    *[!0-9a-f]*|'') _pv_vc_fail go-words-sha256 "not 64 lowercase hex characters"; return 1 ;;
  esac
  [ "${#_vc_gosha}" = 64 ] || { _pv_vc_fail go-words-sha256 "not 64 lowercase hex characters"; return 1; }
  case "$_vc_gow" in
    '"'*'"') ;;
    *) _pv_vc_fail go-words "not a quoted line"; return 1 ;;
  esac
  [ "$(printf '%s' "$_vc_gow" | wc -c | tr -d ' ')" -le 1002 ] || { _pv_vc_fail go-words "more than 1000 bytes"; return 1; }
  return 0
}
# V6b — template text in angle brackets (SWAS-902). `record` refuses it in eight fields, so a LOCAL-ONLY note holding it is not one
# `record` could write NOW. Each stored field is read back to what `record` screened: the token without its quotes, go-by without
# ` [self-asserted]`, approved-by as the id only. Never go-words or kit-row (`record` screens neither). The same shared predicate.
_pv_vc_placeholder() {
  _vp_tok="${_vc_tok#'"'}"; _vp_tok="${_vp_tok%'"'}"
  _vp_goby="${_vc_goby%' [self-asserted]'}"
  _vp_by="${_vc_by%% \[*}"
  # The note's own keys name the field (as the other V legs do); _pv_vc_fail's line and remedies stand alone, no flag-style message.
  for _vp_p in "approval-token=$_vp_tok" "basis=$_vc_basis" "approved-by=$_vp_by" "go-by=$_vp_goby" "scope=$_vc_scope" \
               "gate=$_vc_gate" "rung=$_vc_rung" "change-class=$_vc_cls"; do
    _vp_fn="${_vp_p%%=*}"; _vp_fv="${_vp_p#*=}"
    if _pv_placeholder_span "$_vp_fv" >/dev/null; then
      _pv_vc_fail "$_vp_fn" "template text in angle brackets (record would refuse it)"; return 1
    fi
  done
  return 0
}
# V7 — approved-by: `<id> [<label>]`; the label must equal one `record` could derive NOW. Runs LAST (I5):
# the forge derivation interpolates the note's untrusted scope into an API path, so V1-V6 sanitize first.
_pv_vc_by() {
  case "$_vc_by" in
    *' ['*']') ;;
    *) _pv_vc_fail approved-by "not '<id> [<label>]'"; return 1 ;;
  esac
  _vc_id="${_vc_by%% \[*}"
  _vc_lab="${_vc_by#"$_vc_id" \[}"; _vc_lab="${_vc_lab%\]}"
  [ -n "$_vc_id" ] && [ "$_vc_id [$_vc_lab]" = "$_vc_by" ] || { _pv_vc_fail approved-by "not '<id> [<label>]'"; return 1; }
  # A3: `record` refuses a whitespace-only --approved-by; a note it could not have written is refused too.
  [ -n "$(printf '%s' "$_vc_id" | tr -d ' \t')" ] || { _pv_vc_fail approved-by "the approver id is whitespace-only (record refuses one)"; return 1; }
  case "$_vc_id$_vc_lab" in
    *'['*|*']'*) _pv_vc_fail approved-by "a bracket inside the id or the label"; return 1 ;;
  esac
  _vc_e1="$(derive_assurance "$_vc_sha" "$_vc_id")"
  [ "$_vc_lab" != "$_vc_e1" ] || return 0
  # B6: relay the forge derivation's fallback notice (a FIXED enumeration; no API byte) instead of hiding it.
  # Its notice goes to stderr BEFORE the label is printed to stdout, so with both merged the LAST line is the label.
  _vc_fo="$(forge_review_upgrade "$_vc_scope" "$_vc_sha" "$_vc_id" "$_vc_e1" 2>&1)" || _vc_fo=""
  _vc_e2="$(printf '%s\n' "$_vc_fo" | tail -n 1)"
  _vc_fn="$(printf '%s\n' "$_vc_fo" | sed '$d')"
  [ -z "$_vc_fn" ] || printf '%s\n' "sync: $_vc_sha: $_vc_fn" | _pv_sync_clean >&2
  [ "$_vc_lab" = "$_vc_e2" ] || {
    _pv_vc_fail approved-by "label [$_vc_lab] is not one record could derive now ([$_vc_e1]${_vc_e2:+ / [$_vc_e2]})"; return 1; }
}
_pv_validate_candidate() { # <object-sha> <note-blob>
  _vc_sha="$1"; _vc_blob="$2"
  git rev-parse -q --verify "$_vc_sha^{commit}" >/dev/null 2>&1 || {
    _pv_vc_fail approved-sha "the approved commit is not present locally, so the note cannot be re-derived"; return 1; }
  _pv_vc_grammar || return 1                                                                       # V1
  case "$_vc_asha" in
    -*) _pv_vc_fail approved-sha "starts with '-'"; return 1 ;;
  esac
  _vc_r="$(git rev-parse -q --verify "$_vc_asha^{commit}" 2>/dev/null)" || _vc_r=""
  [ "$_vc_r" = "$_vc_sha" ] || { _pv_vc_fail approved-sha "'$_vc_asha' resolves to '${_vc_r:-nothing}', not the note's own commit"; return 1; }   # V2
  _vc_t="$(git rev-parse -q --verify "$_vc_sha^{tree}" 2>/dev/null)" || _vc_t=""
  { _pv_sync_hex40 "$_vc_tree" && [ "$_vc_tree" = "$_vc_t" ]; } || { _pv_vc_fail approved-tree "is not the commit's own tree"; return 1; }   # V3
  _vc_tr="$(git log -1 --no-show-signature --format='%(trailers:key=Kit-Row,valueonly)' "$_vc_sha" -- 2>/dev/null)" || {   # `--`: a worktree FILE named like the sha must not make it ambiguous (F4 fixture)
    _pv_vc_fail kit-row "cannot read the commit's Kit-Row trailer"; return 1; }
  _vc_kr="$(printf '%s\n' "$_vc_tr" | head -1)"; [ -n "$_vc_kr" ] || _vc_kr="(none)"
  [ "$_vc_row" = "$_vc_kr" ] || { _pv_vc_fail kit-row "note says '$_vc_row', the commit's own trailer says '$_vc_kr'"; return 1; }              # V4
  _pv_class_ok "$_vc_cls" || { _pv_vc_fail change-class "not one of ordinary | sensitive | control-plane"; return 1; }                          # V5
  _vc_sc=0; _pv_scope_shape "$_vc_scope" || _vc_sc=$?
  [ "$_vc_sc" = 0 ] || { _pv_vc_fail scope "record would refuse this scope (branch/ rules)"; return 1; }                                         # V6
  _pv_vc_placeholder || return 1   # PV-PLACEHOLDER-SYNC (SWAS-902: the shared predicate, local-only notes only)
  _pv_vc_by || return 1                                                                                                                          # V7
}
# Validate every candidate (all of them, so one run names every failure). Failures count as refusals.
# A6: `</dev/null` — a command inside this heredoc-fed loop that reads stdin (a `gh`, a hook) would eat the
# remaining candidate lines and silently validate fewer than were counted; and the count is CHECKED against
# the number classify found (rc 2 if they differ) before anything is built.
_pv_sync_validate_all() {
  _va_n=0
  # The heredoc's lone `\` first line is dropped by the shell (unquoted heredoc); semgrep's bash grammar needs it to parse this loop whole.
  while IFS=' ' read -r _va_s _va_b; do
    [ -n "$_va_s" ] || continue
    _va_n=$((_va_n + 1))
    _pv_validate_candidate "$_va_s" "$_va_b" </dev/null || _pv_sync_refuse
  done <<EOF
\
$_sy_cands
EOF
  if [ "$_va_n" != "$_sy_cand" ]; then
    printf '%s\n' "sync: validated $_va_n candidate(s) but classification found $_sy_cand — REFUSED; nothing written." >&2
    return 2
  fi
  return 0
}

# ---- steps 6-8: build the result, back up (R2), swap, publish --------------------------------------
# Build on refs/notes/kit-sync-$$ starting at ORIGIN'S tip (absent when origin has no ledger), adding
# each candidate's EXACT local blob (-C: byte-identical, trailing newline included). The result is a
# linear descendant of origin's tip: no merge commit, no local history. Sets _sy_res.
_pv_sync_build() {
  _sy_res=""
  # B1: created MUST-NOT-EXIST and NEVER-DEREF (`""` old value + `--no-deref`), so a ref — a symbolic one
  # especially — planted at this pid-named ref is refused, never written THROUGH to the ledger.
  if [ -n "$_sy_st" ]; then
    git update-ref --no-deref "$NOTES_SYNCREF" "$_sy_st" "" >/dev/null 2>&1 || { printf '%s\n' "sync: cannot create the build ref $NOTES_SYNCREF at origin's tip (it may already exist) — REFUSED; nothing changed." >&2; return 2; }
  elif _pv_ref_exists "$NOTES_SYNCREF"; then
    printf '%s\n' "sync: the build ref $NOTES_SYNCREF already exists — REFUSED; nothing changed." >&2; return 2
  fi
  # The heredoc's lone `\` first line is dropped by the shell (unquoted heredoc); semgrep's bash grammar needs it to parse this loop whole.
  while IFS=' ' read -r _bd_s _bd_b; do
    [ -n "$_bd_s" ] || continue
    # I1, asserted: a candidate is absent from origin's tip BY CONSTRUCTION; if it is not, refuse.
    if [ -n "$(_pv_sync_blob "$_cl_ot" "$_bd_s")" ]; then
      printf '%s\n' "sync: REFUSED $_bd_s: origin already has a note on it — a published note is never overwritten (I1). Nothing changed." >&2; return 2
    fi
    KIT_PROMOTION_FRONT_DOOR=1 git notes --ref="${NOTES_SYNCREF#refs/notes/}" add -C "$_bd_b" "$_bd_s" >/dev/null 2>&1 || {
      printf '%s\n' "sync: could not add the note for $_bd_s to the build ref — REFUSED; nothing changed." >&2; return 2; }
  done <<EOF
\
$_sy_cands
EOF
  _sy_res="$(git rev-parse -q --verify "$NOTES_SYNCREF^{commit}" 2>/dev/null)" || {
    echo "sync: could not read the built result — REFUSED; nothing changed." >&2; return 2; }
}
# R2: refs/kit/promotions-presync-<UTC> -> the OLD local tip, only when local content is dropped. Never
# pushed. Created must-not-exist so a same-second run can never clobber an earlier backup. Sets _sy_bk.
_pv_sync_backup() {
  _sy_bk=""
  _bk_ref="refs/kit/promotions-presync-$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo unknown)"
  # --no-deref: the backup name is PREDICTABLE (UTC to the second), so a symbolic ref planted at it must be
  # refused (must-not-exist), never written through / deleted through.
  if ! git update-ref --no-deref "$_bk_ref" "$_sy_lt" "" >/dev/null 2>&1; then
    _bk_ref="$_bk_ref-$$"
    git update-ref --no-deref "$_bk_ref" "$_sy_lt" "" >/dev/null 2>&1 || {
      printf '%s\n' "sync: cannot create the backup ref $_bk_ref — REFUSED; nothing changed." >&2; return 2; }
  fi
  _sy_bk="$_bk_ref"
}
# Delete only the backup THIS run created.
_pv_sync_unbackup() {
  if [ -n "$_sy_bk" ]; then   # F5: a failed delete is said aloud (the ledger is already unwound), never swallowed
    git update-ref --no-deref -d "$_sy_bk" >/dev/null 2>&1 || printf '%s\n' "sync: WARNING: could not delete this run's backup ref $_sy_bk — remove it: git update-ref -d $_sy_bk" >&2
  fi
  _sy_bk=""
}
# Publish, exactly as `record` does: plain push of exactly ONE ref (I3), never forced. rc 0 = pushed;
# 3 = non-fast-forward on the FIRST attempt (retry the whole transaction); 2 = refused. Nothing dangles:
# on any failure the ledger is CAS-unwound to the old local tip and this run's backup is deleted.
_pv_sync_publish() {
  # A2 sweep: the ONE explicit refspec cannot be widened by config. `remote.origin.push` and `push.default`
  # are ignored when a refspec is given on the command line; `push.followTags` (would add annotated tags),
  # `push.recurseSubmodules` and `push.gpgSign` are not, so they are pinned OFF. No `--no-verify`: the
  # kit's pre-push hook still runs.
  if _pp_out="$(git push --no-follow-tags --no-recurse-submodules --no-signed origin "refs/notes/$NOTES_REF" 2>&1)"; then return 0; fi
  case "$_pp_out" in
    *non-fast-forward*|*'fetch first'*) _pp_nonff=1 ;;
    *) _pp_nonff=0 ;;
  esac
  _pp_out="$(printf '%s' "$_pp_out" | _pv_sync_clean)"
  if ! _pv_unwind "$_sy_lt" "$_sy_target"; then
    echo "sync: the push was rejected AND the ledger moved under this sync — refs/notes/$NOTES_REF is NOT unwound" >&2
    echo "      (the compare-and-swap refused rather than clobber someone else's commit). The pre-sync backup, if any," >&2
    echo "      is kept: ${_sy_bk:-none}. Inspect with promotion-verify.sh log --unpushed." >&2
    printf '%s\n' "$_pp_out" >&2; return 2
  fi
  _pv_sync_unbackup
  if [ "$_pp_nonff" = 1 ] && [ "$_sy_try" = 1 ]; then return 3; fi
  if [ "$_pp_nonff" = 1 ]; then
    echo "sync: NOT published and nothing left dangling: the remote ledger moved twice during this sync. Re-run it." >&2; return 2
  fi
  echo "sync: publishing refs/notes/$NOTES_REF to origin failed for a reason a re-sync cannot fix; the ledger was" >&2
  echo "      unwound (nothing dangling). git said:" >&2
  printf '%s\n' "$_pp_out" >&2; return 2
}
# Postcondition: origin's tip now EQUALS the local ledger tip (measured, not assumed).
_pv_sync_postcondition() {
  # F5: capture git's output and CHECK its rc first (a pipeline into a brace group hid it), then pick the ONE
  # answer line whose ref field is EXACTLY refs/notes/<ledger> (ls-remote patterns match trailing path
  # components, so a look-alike refs/heads/refs/notes/<ledger> also answers, and may sort first). No exact
  # line, or more than one, leaves _pc_r empty and refuses; only then compare.
  _pc_r=""; _pc_hit=0
  if _pc_raw="$(git ls-remote --exit-code origin "refs/notes/$NOTES_REF" 2>/dev/null)"; then
    # The heredoc's lone `\` first line is dropped by the shell (unquoted heredoc); semgrep's bash grammar needs it to parse this loop whole.
    while read -r _pc_o _pc_n; do
      [ "$_pc_n" = "refs/notes/$NOTES_REF" ] || continue
      _pc_hit=$((_pc_hit + 1)); _pc_r="$_pc_o"
    done <<EOF
\
$_pc_raw
EOF
    [ "$_pc_hit" = 1 ] || _pc_r=""
  fi
  _pc_l="$(_pv_sync_refsha "refs/notes/$NOTES_REF" 2>/dev/null)" || _pc_l=""
  [ -n "$_pc_l" ] && [ "$_pc_r" = "$_pc_l" ] && return 0
  # B7: a mismatch is not always a failure — another `record` may have landed ON TOP of our push. Re-read
  # origin's tip (rc-checked, NON-forced, into a scratch ref that must not exist) and ask whether OUR tip is an
  # ancestor of it. Yes -> the publish landed; no / any read failure -> the postcondition really failed.
  if [ -n "$_pc_l" ] && [ -n "$_pc_r" ]; then
    _pv_drop_scratch
    if _pv_scratch_free sync 2>/dev/null \
       && git fetch --refmap= --no-tags --no-recurse-submodules origin "refs/notes/$NOTES_REF:$NOTES_SCRATCH" >/dev/null 2>&1; then
      _pc_t="$(git rev-parse -q --verify "$NOTES_SCRATCH^{commit}" 2>/dev/null)" || _pc_t=""
      if [ -n "$_pc_t" ] && git merge-base --is-ancestor "$_sy_target" "$_pc_t" >/dev/null 2>&1; then
        _pv_drop_scratch
        printf '%s\n' "sync: published (origin has since moved on: another record landed after this push)."
        return 0
      fi
    fi
    _pv_drop_scratch
  fi
  printf '%s\n' "sync: POSTCONDITION FAILED — after the push origin's ledger is '$(printf '%s' "${_pc_r:-unreadable}" | _pv_sync_clean)' but the local ledger is '$(printf '%s' "${_pc_l:-unreadable}" | _pv_sync_clean)'." >&2
  echo "      Inspect with promotion-verify.sh log --unpushed before doing anything else." >&2
  return 2
}
_pv_sync_report() { # the per-record `published` lines, then the final line
  # The heredoc's lone `\` first line is dropped by the shell (unquoted heredoc); semgrep's bash grammar needs it to parse this loop whole.
  while IFS=' ' read -r _rp_s _rp_b; do
    [ -z "$_rp_s" ] || printf '%s\n' "published $_rp_s"
  done <<EOF
\
$_sy_cands
EOF
  _rp_bk="no backup"; [ -z "$_sy_bk" ] || _rp_bk="backup $_sy_bk"
  printf '%s\n' "sync: reconciled — $_sy_cand published, $_sy_ow origin-wins, $_sy_dn discarded ($_rp_bk)"
}
# One attempt of the whole transaction: fetch, classify, validate, build, back up, swap, publish.
# rc 0 = done (or nothing to do) · 2 = refused · 3 = the remote moved: retry ONCE.
_pv_sync_attempt() {
  _sy_bk=""; _sy_res=""; _sy_target=""
  _pv_sync_local_tip || return 2
  _pv_sync_fetch || return 2
  if [ -z "$_sy_lt" ] && [ -z "$_sy_st" ]; then echo "sync: no ledger locally or on origin — nothing to reconcile."; return 0; fi
  # 3. FAST PATHS.
  if [ "$_sy_lt" = "$_sy_st" ]; then echo "sync: local ledger already equals origin's — nothing to do."; return 0; fi
  _pv_sync_ff_probe || return 2
  if [ "$_sy_ff" = 1 ]; then
    if [ "$_sy_dry" = 1 ]; then echo "WOULD fast-forward local ledger to origin's tip"; return 0; fi
    _pv_sync_cas "$_sy_st" "$_sy_lt" || return 2
    echo "sync: fast-forwarded refs/notes/$NOTES_REF to origin's tip."; return 0
  fi
  # 4. CLASSIFY by tree content (also covers "local strictly ahead": publish-only; the voided arm still applies).
  _pv_sync_classify "$_sy_base" "$_sy_lt" || return 2
  if [ "$_sy_refused" -gt 0 ]; then echo "sync: REFUSED ($_sy_refused record(s)); nothing written." >&2; return 2; fi
  # 5. RE-VALIDATE every candidate (also under --dry-run: it is the owner's verification surface).
  _pv_sync_validate_all || return 2
  if [ "$_sy_refused" -gt 0 ]; then echo "sync: REFUSED ($_sy_refused record(s)); nothing written." >&2; return 2; fi
  # Origin has no ledger and nothing would remain to publish: refuse; NEVER delete the local ledger (destruction).
  if [ "$_sy_cand" = 0 ] && [ -z "$_sy_st" ]; then
    echo "sync: origin has no ledger and nothing would remain to publish — nothing done; record afresh." >&2; return 2
  fi
  if [ "$_sy_dry" = 1 ]; then return 0; fi
  _sy_target="$_sy_st"
  if [ "$_sy_cand" -gt 0 ]; then _pv_sync_build || return 2; _sy_target="$_sy_res"; fi
  # CRITICAL SECTION (deferred signals): from just before the backup to the end of push/unwind/postcondition
  # (left in do_sync once this attempt has returned). A signal already pending here drops the temp ref and
  # exits with no backup and no swap.
  _pv_crit_enter
  if [ "$_sy_drop" -gt 0 ] && [ -n "$_sy_lt" ]; then _pv_sync_backup || return 2; fi
  # 7. SWAP by compare-and-swap; if anything moved the ledger meanwhile, nothing changes.
  _pv_sync_cas "$_sy_target" "$_sy_lt" || { _pv_sync_unbackup; return 2; }
  if [ "$_sy_cand" = 0 ]; then _pv_sync_report; return 0; fi     # only dropped local content: the ledger IS origin's tip now
  # 8. PUBLISH, then check the postcondition.
  _pp_rc=0; _pv_sync_publish || _pp_rc=$?
  [ "$_pp_rc" = 0 ] || return "$_pp_rc"
  _pv_sync_postcondition || return 2
  _pv_sync_report
}

do_sync() {
  _pv_sync_args "$@" || return 2
  # 1. FRONT DOOR: a symbolic ledger ref is a repointing (same arm as `record`); an unreadable origin is blind.
  _sy_sr=0; git symbolic-ref -q "refs/notes/$NOTES_REF" >/dev/null 2>&1 || _sy_sr=$?
  case "$_sy_sr" in
    1) ;;   # not symbolic (or absent): the only proceed answer
    0) echo "sync: ledger ref refs/notes/$NOTES_REF is symbolic — repointed; refusing to sync." >&2
       echo "      Restore it (git symbolic-ref --delete refs/notes/$NOTES_REF) before syncing." >&2
       return 2 ;;
    *) _pv_sync_refuse_read "read whether refs/notes/$NOTES_REF is symbolic"; return 2 ;;
  esac
  # B1: neither temp ref may pre-exist (a symbolic ref planted at either pid-named ref would be written through
  # to the ledger). After each attempt this run's OWN copies are dropped, so a retry starts clean.
  _pv_scratch_free sync || return 2
  if _pv_ref_exists "$NOTES_SYNCREF"; then
    printf '%s\n' "sync: the build ref $NOTES_SYNCREF already exists (a stale leftover or a planted ref) — REFUSED before anything is written; nothing changed." >&2
    return 2
  fi
  # At most two attempts; the second only after a NON-FAST-FORWARD rejection (re-fetch, re-classify, re-validate).
  _sy_try=1
  while :; do
    _sy_arc=0; _pv_sync_attempt || _sy_arc=$?
    _pv_drop_scratch; _pv_drop_syncref
    _pv_crit_leave    # a signal deferred inside the attempt stops the run HERE, published or unwound
    if [ "$_sy_arc" = 3 ]; then
      _sy_try=2; echo "sync: origin's ledger moved during the publish; unwound, re-reconciling once." >&2; continue
    fi
    return "$_sy_arc"
  done
}

cmd="${1:-}"
[ $# -gt 0 ] && shift || true

# SWAS-903: ONE probe per gh-reaching verb, in this parent shell, BEFORE the lease gate (so the gate child and every `eval "$merge_cmd"` inherit the
# result). It exports SSL_CERT_FILE only on the macOS sandbox's x509 signature and only when the root-owned system bundle passes its checks.
case "$cmd" in
  record|land|actuate|trace|evidence)
    if command -v kit_gh_tls_pin >/dev/null 2>&1; then kit_gh_tls_pin; fi ;;
esac

# ── THE CHECKOUT LEASE (SWAS-192 slice A; scripts/checkout-lease.sh) ───────────────────────────────
# `record`, `land` and `actuate` push refs/notes/promotions (and `land`/`actuate` merge), which is custody of the main
# checkout. In a checkout that opted in (`kit.checkoutLease`) each needs the holder's `--lease-token <sha>`, stripped from
# the arguments here so the verb's own parser never sees it. A checkout that never opted in runs exactly as before. The
# key fails closed (a lease ref present, the key gone: refuse). The check runs at dispatch, after nothing of the verb has
# run and before it reads or writes anything. DRIFT CONTROL between cooperating clients: the token is a ref's sha.
case "$cmd" in
  record|land|actuate)
    _pv_ltok=""; _pv_n=$#
    while [ "$_pv_n" -gt 0 ]; do
      _pv_a=$1; shift; _pv_n=$((_pv_n - 1))
      if [ "$_pv_a" = --lease-token ] && [ "$_pv_n" -gt 0 ]; then _pv_ltok=$1; shift; _pv_n=$((_pv_n - 1)); continue; fi
      set -- "$@" "$_pv_a"
    done
    _pv_lsh=$(dirname -- "$0")/checkout-lease.sh
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
      :   # outside a repository there is no checkout to lease; the verb's own checks speak
    elif [ -f "$_pv_lsh" ]; then
      if [ -n "$_pv_ltok" ]; then
        sh "$_pv_lsh" gate --verb "$cmd" --lease-token "$_pv_ltok" || exit $?
      else
        sh "$_pv_lsh" gate --verb "$cmd" || exit $?
      fi
    elif [ -n "$(git config --local --get kit.checkoutLease 2>/dev/null || true)" ]; then
      echo "$cmd: REFUSED — kit.checkoutLease is set but scripts/checkout-lease.sh is missing; restore it, or a human removes the key." >&2
      exit 5
    fi ;;
esac

case "$cmd" in
  record)  if do_record  "$@"; then rc=0; else rc=$?; fi ;;
  sync)    if do_sync  "$@"; then rc=0; else rc=$?; fi ;;
  log)     if do_log     "$@"; then rc=0; else rc=$?; fi ;;
  trace)   if do_trace   "$@"; then rc=0; else rc=$?; fi ;;
  check)   if do_check   "$@"; then rc=0; else rc=$?; fi ;;
  actuate) if do_actuate "$@"; then rc=0; else rc=$?; fi ;;
  land)    if do_land    "$@"; then rc=0; else rc=$?; fi ;;
  evidence) if do_evidence "$@"; then rc=0; else rc=$?; fi ;;
  # KIT-MODE: go-bound
  go-bound) if do_go_bound "$@"; then rc=0; else rc=$?; fi ;;
  -h|--help) usage; rc=2 ;;
  *) usage; rc=2 ;;
esac
exit "$rc"
