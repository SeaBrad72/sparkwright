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
# `actuate` wires ORDINARY and SENSITIVE promotions: on an authenticated, SHA-bound recorded GO it
# performs the merge. CONTROL-PLANE is REFUSED by `actuate` pending the open
# TIER-3-CP-MERGE-ACTUATION-RULING sitting (step 2b) — control-plane merges take the direct path
# instead. That refusal is a DRIFT CONTROL, not a boundary: the class is caller-recorded.
#
# POSIX sh; dash-clean (no `local`, no bashisms). Operates on the current working tree's git repo.
# The notes ref name is overridable with PROMOTION_NOTES_REF (default: promotions) for testing.
# What it changes: `record` binds a GO record as a git NOTE under refs/notes/promotions (tree-invariant — the commit's tree/SHA is unchanged); `actuate` performs a real control-plane PR merge (default `gh pr merge --squash`, swappable via --merge-cmd) bound to the approved SHA; `sync` reconciles a diverged local ledger with origin's by tree content and publishes it (fast-forward only, never rewriting a published note; it moves refs/notes/promotions and leaves a local refs/kit/promotions-presync-<UTC> backup when it drops local content); `log`, `check` and `trace` are read-only.
# Guardrails: `check` asserts shipped==approved by TREE equality (exit 1 on MISMATCH); the approved-by assurance label is DERIVED from the commit's own evidence (never from input) — a note BINDS, it does not AUTHENTICATE. `actuate` fails CLOSED unless a SHA-bound [authenticated: <forge>-review] GO exists and approver != author, rejects `$ref` metacharacters, NEVER emits `--admin`, and re-verifies shipped==approved after the merge. `record` derives `kit-row:` from the approved commit's own trailer (never a flag), records `(none)` rather than inventing one, and sanitises it with every other free-text field; `trace` matches a trunk commit to its note by TREE (never ancestry, which a squash breaks), reds on any recordless commit in a `--recent` window, and fails closed on an empty window. `sync` publishes only local-only notes that re-validate as exactly what `record` would write NOW (never a label it could not derive), never rewrites, forces or merges, refuses a note origin once held and removed (voids visible in origin's history). Operator-only by policy (the script does not detect CI or a subagent): never CI, never a subagent.
set -eu
# A `refs/replace/*` ref can make every object read (tree, blob, trailer, author) of an approved sha return a
# crafted commit; the metering gate reads the approved commit, so it must read the REAL object.
export GIT_NO_REPLACE_OBJECTS=1

# ROOT — same idiom as hooks/pre-push (`ROOT=$(git rev-parse --show-toplevel) || ROOT=.`), used only
# by `land`'s A9 hygiene re-read (design §8) to locate conformance/backlog-lib.sh, .kit/tracker.conf,
# and scripts/tracker-read.sh regardless of the caller's cwd within the working tree.
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=.

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
_pv_sync_in() {
  if git ls-remote --exit-code origin "refs/notes/$NOTES_REF" >/dev/null 2>&1; then
    _si_probe=0
  else
    _si_probe=$?
  fi
  case "$_si_probe" in
    0) ;;
    2) echo "record: origin has no refs/notes/$NOTES_REF yet — recording the first entry; publish will create it." >&2
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

usage() {
  echo "usage:" >&2
  echo "  promotion-verify.sh record --approved-sha <sha> --approved-by <id> --gate <g> \\" >&2
  echo "                             --rung <r> --class <c> --scope <pr> --token <str> [--basis <t>]" >&2
  echo "                             [--go-by <name>] [--no-push]" >&2
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
  echo "        --token       their words, verbatim (the owner's own GO sentence)." >&2
  echo "        --class must be one of: ordinary | sensitive | control-plane (case-insensitive)" >&2
  echo "  promotion-verify.sh log [--unpushed]" >&2
  echo "        --unpushed lists only the records the remote ledger does not have; it fails CLOSED" >&2
  echo "                   (UNKNOWN, rc 2) when the remote cannot be read — never a silent '0'." >&2
  echo "  promotion-verify.sh sync [--dry-run] [--discard-local <sha>]..." >&2
  echo "        reconcile a DIVERGED local ledger with origin's by tree content: origin-only notes are" >&2
  echo "        kept, same-commit twins whose identity agrees take origin's bytes, and a note origin" >&2
  echo "        once held and removed is refused (voided). --dry-run prints WOULD lines, writes nothing." >&2
  echo "        sync is a TRANSACTION: it fetches origin's ledger, classifies by tree content, re-validates" >&2
  echo "        every local-only note as exactly what record would write NOW (the label is re-derived," >&2
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
  echo "  promotion-verify.sh check  --ref <merged-ref|tag> [--approved-sha <sha>]" >&2
  echo "  promotion-verify.sh actuate --ref <pr|tag|merged-ref> --approved-sha <sha> [--merge-cmd \"<cmd>\"]" >&2
  echo "  promotion-verify.sh land --ref <pr|tag|merged-ref> --merge-cmd \"<cmd>\" \\" >&2
  echo "                           --approved-sha <sha> --approved-by <id> --gate <g> --rung <r> \\" >&2
  echo "                           --class <c> --scope <s> --token <str> --go-by <the GO-giver> [--basis <t>]" >&2
  echo "        land (control-plane) merges ONLY on an AUTHENTICATED NON-AUTHOR forge approval: --approved-by is" >&2
  echo "        the forge login of a non-author reviewer whose APPROVED review is on <sha> (checked BEFORE the" >&2
  echo "        record, so a refusal writes no note, and again from the note on origin BEFORE the merge); the" >&2
  echo "        owner who gave the GO goes in --go-by, recorded [self-asserted]. --scope must be the PR id (a" >&2
  echo "        branch/<name> scope has no reviews to read, so land refuses it). SOLO (one account, no second" >&2
  echo "        approver): land refuses; record the GO with 'record' and the HUMAN merges (admin merge is the" >&2
  echo "        human's act, never the agent's)." >&2
  echo "        land is ONE transactional verb for the direct/control-plane path: it RECORDS the GO" >&2
  echo "        (record's own args + transaction), CONFIRMS the note reached origin, then MERGES then" >&2
  echo "        leaves the branch INTACT. If the record does not complete or the note is not on" >&2
  echo "        origin, land does NOT merge. --no-push is REFUSED (a landing merge must publish the" >&2
  echo "        GO so it reaches origin — landing on a local-only note would reopen #658). Default" >&2
  echo "        merge: gh pr merge <ref> --squash --match-head-commit <sha> — NEVER --admin, NEVER --delete-branch." >&2
  echo "        Verb-scoped: land refuses a recordless merge on its OWN path; the universal net for a" >&2
  echo "        recordless merge is the CI recordless-merge backstop (promotion-verify.sh trace --recent)." >&2
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
# by construction, not by escaping).
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
# _fr_fallback <reason> <label> — print the fixed-enumeration notice, echo the unchanged label.
_fr_fallback() {
  echo "forge-review derivation: $1 — recording [$2]" >&2
  printf '%s\n' "$2"
}

# forge_review_upgrade <scope> <approved-sha> <approved-by> <fallback-label> -> the label to record.
forge_review_upgrade() {
  _fr_scope="$1"; _fr_sha="$2"; _fr_by="$3"; _fr_lab="$4"; _fr_n=""
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
  case "$_fr_n" in ''|*[!0-9]*) _fr_n="" ;; esac
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
        --jq '.[]|[(.state//""),(.commit_id//""),(.user.login//""),(.user.type//"")]|@tsv' 2>/dev/null)"; then
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

do_record() {
  asha=""; aby=""; gate=""; rung=""; cls=""; scope=""; token=""; basis=""; nopush=0
  goby=""; goby_given=0
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
      --token)        token="${2:-}"; shift 2 ;;
      --basis)        basis="${2:-}"; shift 2 ;;
      *) echo "record: unknown arg '$1'" >&2; usage; return 2 ;;
    esac
  done
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
  case "$asha" in -*) echo "record: invalid --approved-sha '$asha' (must not start with '-')" >&2; return 2 ;; esac
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
  [ -n "$basis" ] || basis="(none recorded)"
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
  # STEP 0 (security vet M1). A SYMBOLIC ledger ref is a repointing — measured: a fetch and a plain
  # `update-ref` both write THROUGH a symref, while `--no-deref` clobbers the symref itself. Either
  # way the operator's ledger is not where they think it is, so the guard's bypass #8 becomes a loud
  # FRONT-DOOR refusal here rather than a silent mis-write. Before anything is composed or written.
  if git symbolic-ref -q "refs/notes/$NOTES_REF" >/dev/null 2>&1; then
    echo "record: ledger ref refs/notes/$NOTES_REF is symbolic — repointed; refusing to record." >&2
    echo "        Restore it (git symbolic-ref --delete refs/notes/$NOTES_REF) before recording." >&2
    return 2
  fi
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
    if ! printf '%s\n' "$nbody" \
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
    printf '%s  kit-row: %s  approved-sha: %s  gate: %s  scope: %s  approved-by: %s  go-by: %s\n' \
      "$(printf '%s' "$_tc" | cut -c1-12)" "$_trow" "$(printf '%s' "$_ta" | cut -c1-12)" \
      "${_tgate:-(none)}" "${_tscope:-(none)}" "${_taby:-(none)}" "${_tgo:-(none recorded)}"
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
#   HONEST CEILING (rewritten at PR 11, when the sentence it replaced stopped being true): the
#   forge-review -> [authenticated: github-review] derivation IS NOW WIRED in `record`, so this gate
#   is reachable by a production path and `actuate` opens for ORDINARY and SENSITIVE changes on an
#   authenticated recorded GO. CONTROL-PLANE is refused here (step 2b) pending the open
#   TIER-3-CP-MERGE-ACTUATION-RULING sitting; those merges use the direct path.
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
pv_release_claim() {
  _pvnote="$1"; _pvverb="$2"
  _pvkr_line="$(printf '%s\n' "$_pvnote" | grep '^kit-row:' | head -1 || true)"
  _pvkr="${_pvkr_line#kit-row:}"
  # ⚠️ CONTROL BYTES OUT FIRST (security S-L6). It comes from a GIT NOTE — self-authorable text —
  # and it is printed straight into an operator's terminal by the WARN lines below. An ANSI escape in
  # a `kit-row:` projection could repaint or forge those lines, which are the audit record of a
  # merge. Stripped once, here, so every consumer downstream (the prints AND the argument handed to
  # board-claim.sh) sees the sanitised value; board-claim's own row grammar is the second gate.
  _pvkr="$(printf '%s' "$_pvkr" | tr -d '[:cntrl:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  _pvbc="$(dirname -- "$0")/board-claim.sh"
  if [ -z "$_pvkr" ] || [ "$_pvkr" = '(none)' ]; then
    echo "$_pvverb: no kit-row on the GO note — no board claim to release (nothing invented)."
  elif [ ! -f "$_pvbc" ]; then
    echo "$_pvverb: WARN — board-claim.sh not found beside this script; claim on '$_pvkr' NOT released." >&2
  elif sh "$_pvbc" release "$_pvkr" --stale; then
    echo "$_pvverb: board claim on '$_pvkr' released (refs/claims/$_pvkr deleted on origin)."
  else
    echo "$_pvverb: WARN — could not release the board claim on '$_pvkr' (refs/claims/$_pvkr may still exist)." >&2
    echo "        The merge SUCCEEDED and is verified; release by hand:" >&2
    echo "        sh scripts/board-claim.sh release $_pvkr --stale" >&2
  fi
  return 0
}

# ---------------------------------------------------------------------------------------------
# RUNAWAY-METERING-LANDING-GATE (design 2026-09-29, §2.2 with the §5a/§5b/§5c amendments binding).
# `land` and `actuate` consult the PER-SLICE METER (`runaway-guard.sh meter`) behind the
# RUNAWAY_METERING_GATE dial: a row that was never metered on this machine is REFUSED in enforce (before
# any note is written / any merge is attempted), and noted in observe. The dial is ABSENT on an adopter
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
  _ddrb="$(GIT_TERMINAL_PROMPT=0 git -C "$ROOT" ls-remote --exit-code origin refs/heads/main 2>/dev/null | head -1)" || _ddrb=""
  _ddrsha="${_ddrb%%[[:space:]]*}"
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
    3) if [ "$_mgmode" = enforce ]; then
         printf '%s\n' "$_mgVERB REFUSED (metering gate): $_mgrow has no metered lines in this repo's tally on this machine." >&2
         printf '%s\n' "              Record the slice's ACTUAL summed dispatch usage with \`sh scripts/runaway-guard.sh step --row $_mgrow --tokens N --agents N\`;" >&2
         printf '%s\n' "              if the usage is unknown, STOP and ask the owner — never estimate. Or the owner ratifies a dial change" >&2
         printf '%s\n' "              (RUNAWAY_METERING_GATE in .kit/dials.conf) on the default branch." >&2
         return 1
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

  # 2b. CONTROL-PLANE REFUSAL — the arm the forge-review derivation MADE NECESSARY (PR 11, design
  #     §4.7 arm (a)). Before that derivation existed, "control-plane stays human-actuated through
  #     this tool" was enforced BY CONSTRUCTION: no path could produce an [authenticated:] label, so
  #     step 2 closed the gate for every class. Wiring the derivation opens step 2 for every class at
  #     once — including control-plane, while TIER-3-CP-MERGE-ACTUATION-RULING is an OPEN SITTING.
  #     Fail closed until that sitting rules, rather than let this slice render its ruling by side
  #     effect (a lean is not a ruling).
  #     This does NOT contradict the promotion contract's "the agent may actuate on a recorded GO,
  #     control-plane included": that allowance is exercised today by the direct working path
  #     (`gh pr merge --squash --match-head-commit <sha>` after `record`), which stays available. Only
  #     this subcommand stays conservative.
  #     HONEST TIER: `change-class:` is CALLER-RECORDED, so this is a DRIFT CONTROL at the note's own
  #     trust tier — exactly like the label bar above it — never a boundary. Removable by the ruling.
  #     Read LINE-ANCHORED from the `change-class:` line only (never a body scan — the S5a decoy
  #     lesson), and matched EXACTLY after case-folding: a substring test would refuse a legitimate
  #     class merely containing the word.
  cls_line="$(printf '%s\n' "$note" | grep '^change-class:' | head -1 || true)"
  cls_val="${cls_line#change-class:}"
  cls_val="$(printf '%s' "$cls_val" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  cls_lc="$(printf '%s' "$cls_val" | LC_ALL=C tr 'A-Z' 'a-z')"
  # AN ALLOWLIST, NOT A DENYLIST (security review F2). A denylist on "control-plane" fails OPEN on
  # everything it does not recognise: a note with NO `change-class:` line at all, or a typo'd value,
  # or a class this vocabulary gains later, would all sail through the refusal and be merged. Since
  # the note is caller-recorded, that is a one-character evasion. Proceed ONLY for the two classes
  # this subcommand is wired for; everything else — missing, empty, unrecognised — refuses with its
  # own reason. `record` validates the same vocabulary at the front door, so a note reaching here with
  # an unrecognised class was written by something other than `record`, which is worth saying out loud.
  case "$cls_lc" in
    ordinary|sensitive) ;;
    control-plane)
      echo "ACTUATE REFUSED: change-class '$cls_val' — control-plane actuation through this subcommand is" >&2
      echo "                 held closed pending the open TIER-3-CP-MERGE-ACTUATION-RULING sitting." >&2
      echo "                 Ordinary/Sensitive actuate here on an authenticated recorded GO. This is a" >&2
      echo "                 DRIFT CONTROL (the class is caller-recorded, at the note's own trust tier)," >&2
      echo "                 and it is removable by that ruling. Control-plane merges use the direct" >&2
      echo "                 path: gh pr merge --squash --match-head-commit <approved-sha>." >&2
      return 1 ;;
    *)
      echo "ACTUATE REFUSED: unrecognised or missing change-class '$cls_val' — this gate proceeds only" >&2
      echo "                 for an explicitly recorded 'ordinary' or 'sensitive' class (allowlist)." >&2
      echo "                 A note with no class, or one this vocabulary does not know, cannot be" >&2
      echo "                 judged, and an unjudgeable class is never a permission. Re-record the GO" >&2
      echo "                 with \`record --class <ordinary|sensitive|control-plane>\`." >&2
      return 1 ;;
  esac

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

  # Honest success line: the note is RECORDED, not necessarily AUTHENTICATED — a git note is
  # self-authorable (the label bar is audit + defense-in-depth over it; the real solo control is
  # server-side branch protection + the human-only admin bypass). Do not imply the label authenticates.
  [ -z "$PV_STOP_LINE" ] || printf '%s\n' "$PV_STOP_LINE"
  echo "OK: actuated $ref on recorded GO (approved-sha $asha) — shipped == approved"
  return 0
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
# WHY A NEW SUBCOMMAND, NOT `actuate`. `actuate` refuses control-plane (step 2b) to protect the open
# TIER-3-CP-MERGE-ACTUATION-RULING sitting; extending it to cover CP would delete that refusal and
# render the sitting by side effect. `land` changes NO boundary: the guard still denies `--admin` and
# CP Write/Edit, branch protection is unchanged, the human still renders the GO and directs the merge.
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
# and that is all it claims. SOLO (one account, no second approver) there is no authenticated approval to
# find, so `land` refuses by construction: the agent records the GO (`record`) and the HUMAN merges
# (an admin merge is the human's act; the guard denies the agent --admin).
do_land() {
  ref=""; merge_cmd=""; asha=""; land_cls=""; land_aby=""; land_goby=""; land_goby_given=0; land_scope=""
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
      --approved-sha|--class|--approved-by|--go-by|--scope)
        case "${2:-}" in
          -*) echo "land: $1 value '$(printf '%s' "$2" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-40)' starts with '-' — refused (a flag-shaped value for $1 is how a record-only flag's value gets swallowed; land and record would then judge different arguments)" >&2
              return 2 ;;
        esac ;;
    esac
    case "$1" in
      --ref)
        [ "$_argc" -ge 2 ] || { echo "land: --ref needs a value" >&2; usage; return 2; }
        ref="$2"; shift 2; _argc=$((_argc-2)) ;;
      --merge-cmd)
        [ "$_argc" -ge 2 ] || { echo "land: --merge-cmd needs a value" >&2; usage; return 2; }
        merge_cmd="$2"; shift 2; _argc=$((_argc-2)) ;;
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
  case "$ref"  in -*) echo "land: invalid --ref '$ref' (must not start with '-')" >&2; return 2 ;; esac
  case "$asha" in -*) echo "land: invalid --approved-sha '$asha' (must not start with '-')" >&2; return 2 ;; esac
  case "$ref"  in *[!A-Za-z0-9._/-]*) echo "land: invalid --ref '$ref' (allowed chars: A-Za-z0-9._/-)" >&2; return 2 ;; esac
  case "$asha" in *[!A-Za-z0-9._/-]*) echo "land: invalid --approved-sha '$asha' (allowed chars: A-Za-z0-9._/-)" >&2; return 2 ;; esac

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
      echo "LAND REFUSED: --class '$land_cls' — land is the control-plane/direct-path verb. Ordinary" >&2
      echo "              and sensitive promotions actuate through \`promotion-verify.sh actuate\`," >&2
      echo "              which carries the forge-review label bar and the SoD for those classes. Use" >&2
      echo "              \`actuate\` for this class (land never had their label bar; the CP/direct path" >&2
      echo "              does not)." >&2
      return 2 ;;
    *)
      echo "LAND REFUSED: unrecognised or missing --class '$land_cls' — land proceeds ONLY for an" >&2
      echo "              explicitly recorded 'control-plane' class (allowlist). An unjudgeable class is" >&2
      echo "              never a permission. Re-run with --class control-plane, or use \`actuate\` for" >&2
      echo "              an ordinary/sensitive promotion." >&2
      return 2 ;;
  esac

  # 0b. SoD (builder != ratifier) — RUN BEFORE do_record (N2). It sits beside the class gate, which
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
  _land_aby_norm="$(printf '%s' "$land_aby" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  if [ -z "$_land_aby_norm" ]; then
    echo "LAND REFUSED: empty approver (--approved-by) — cannot satisfy builder != ratifier (SoD). This" >&2
    echo "              is a drift control at the GO note's own tier (branch protection is the real" >&2
    echo "              boundary), not authentication. Re-run with a non-author --approved-by." >&2
    return 1
  fi
  pv_sod_author_check land "$asha" "$_land_aby_norm" || return 1

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
  if [ -z "$land_goby" ]; then
    echo "LAND REFUSED: land records the owner's GO by name: add \`--go-by <the GO-giver>\` (the person whose" >&2
    echo "              judgment this GO is; recorded [self-asserted] by design — the kit never authenticates" >&2
    echo "              the GO-giver). --approved-by is a DIFFERENT identity: the forge login of the reviewer." >&2
    return 1
  fi
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
  case "$_land_sn" in ''|*[!0-9]*) _land_sn="" ;; esac
  if [ -z "$_land_sn" ]; then
    echo "LAND REFUSED: --scope '$(printf '%s' "$land_scope" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-60)' is not a PR id. A control-plane land is bound to the PR it merges and" >&2
    echo "              authenticates by that PR's reviews: --scope must be the PR id (PR #N, PR-N, #N or N)." >&2
    return 1
  fi
  _land_rn="$ref"; case "$_land_rn" in *[!0-9]*) _land_rn="" ;; esac
  if [ -z "$_land_rn" ] || [ "$(printf '%s' "$_land_rn" | sed 's/^0*//')" != "$(printf '%s' "$_land_sn" | sed 's/^0*//')" ]; then
    echo "LAND REFUSED: --scope names PR $_land_sn but --ref is '$ref' — the PR judged must be the PR merged." >&2
    echo "              Pass the same PR number as --ref and --scope. No note was written and nothing was merged." >&2
    return 1
  fi
  #     (ii) PRE-DERIVE the label with the SAME two functions `record` will use, and require what `actuate`
  #     requires (the same regex). forge_review_upgrade already refuses the PR author (case-insensitive), a
  #     Bot, a withdrawn or dismissed approval and a stale-sha one, and prints its fixed-enumeration reason
  #     on stderr (e.g. reviewer-not-in-reviews, reviewer-is-pr-author), which stays visible above.
  _land_pre="$(derive_assurance "$asha" "$land_aby")"
  _land_pre="$(forge_review_upgrade "$land_scope" "$asha" "$land_aby" "$_land_pre")"
  if ! printf '%s' "$_land_pre" | grep -Eq '^authenticated: [A-Za-z0-9_-]+-review$'; then
    _land_abyp="$(printf '%s' "$land_aby" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-80)"
    echo "LAND REFUSED: a control-plane merge needs an AUTHENTICATED NON-AUTHOR forge approval, and --approved-by" >&2
    echo "              '$_land_abyp' derives [$_land_pre] (the reason is on the line above)." >&2
    echo "              --approved-by is the forge LOGIN of a non-author reviewer whose APPROVED review is on" >&2
    echo "              $asha; the GO-giver (the owner) goes in --go-by." >&2
    echo "              SOLO (one account, no second approver)? Record the GO with \`promotion-verify.sh record\`" >&2
    echo "              (it takes --go-by too), then the HUMAN merges: an admin squash-merge is the human's act," >&2
    echo "              never the agent's (the guard denies the agent --admin). No note was written and nothing" >&2
    echo "              was merged. This is a drift control at the note's own tier (the label is derived over the" >&2
    echo "              local gh credential); server-side branch protection + required review is what binds." >&2
    return 1
  fi

  # 1. RECORD FIRST — the whole point of the verb. do_record is a self-unwinding transaction (fetch,
  #    refuse on divergence, write, publish, unwind its own unpublished note on push reject); land
  #    inherits it whole and passes record's args through untouched. If record does not complete,
  #    REFUSE to merge and propagate its code — a merge without a recoverable GO note is refused BY
  #    THIS VERB (verb-scoped honesty: never "impossible", only "land will not merge").
  if do_record "$@"; then _lrc=0; else _lrc=$?; fi
  if [ "$_lrc" -ne 0 ]; then
    echo "LAND REFUSED: the GO record did not complete (rc $_lrc) — land will not merge without a" >&2
    echo "              recoverable GO note. This verb refuses a recordless merge on its OWN path;" >&2
    echo "              the universal net for a recordless merge is the CI recordless-merge backstop." >&2
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
  if ! _land_cnote="$(git notes --ref="$_land_confirm" show "$asha" 2>/dev/null)"; then
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
  if ! printf '%s' "$_land_blab" | grep -Eq '^authenticated: [A-Za-z0-9_-]+-review$'; then
    _land_blab="$(printf '%s' "$_land_blab" | LC_ALL=C tr -d '[:cntrl:]' | cut -c1-80)"
    echo "LAND REFUSED: the GO note on origin carries assurance '[$_land_blab]', not [authenticated: <forge>-review] —" >&2
    echo "              the forge answered differently between land's pre-check and record's own read (an" >&2
    echo "              approval withdrawn or dismissed meanwhile). The note IS recorded; land will not merge on it." >&2
    echo "              Re-run land once the approval stands on $asha — record supersedes the note." >&2
    return 1
  fi
  #     THE WHOLE NOTE, NOT ONLY THE LABEL (security S2-1b): land and record parse the same argv separately, so
  #     the note on origin must say exactly what land judged. Each field is read by its own line key and
  #     compared byte-for-byte (class case-folded, as record accepts it); any mismatch refuses the merge.
  _land_nf() { printf '%s\n' "$_land_cnote" | sed -n "s/^$1: //p" | head -1; }
  _land_bad=""
  [ "$_land_bl" = "$land_aby [$_land_blab]" ] || _land_bad="$_land_bad approved-by"
  [ "$(_land_nf scope)" = "$land_scope" ] || _land_bad="$_land_bad scope"
  [ "$(_land_nf change-class | LC_ALL=C tr 'A-Z' 'a-z')" = control-plane ] || _land_bad="$_land_bad change-class"
  [ "$(_land_nf go-by)" = "$land_goby [self-asserted]" ] || _land_bad="$_land_bad go-by"
  if [ -n "$_land_bad" ]; then
    echo "LAND REFUSED: the GO note on origin does not say what land judged (mismatched:$_land_bad) — land and record read" >&2
    echo "              the arguments differently. The note IS recorded; land will not merge on it. Fix the arguments" >&2
    echo "              and re-run land — record supersedes the note." >&2
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

  # 3. Default merge = the CP-safe direct path, PINNED to the approved sha; never --admin, never
  #    --delete-branch. Swappable via --merge-cmd (tests pass a stub). --match-head-commit binds the
  #    merge to the exact reviewed head, so a race that advanced the PR branch is rejected server-side.
  [ -n "$merge_cmd" ] || merge_cmd="gh pr merge \"$ref\" --squash --match-head-commit \"$asha\""

  # 3b. REFUSE any --merge-cmd carrying a shell metacharacter ANYWHERE. The eval'd shell (step 5) can
  #     rebuild a --admin or --delete-branch flag from characters the step-4 token scan cannot see: it
  #     sees only the PRE-eval bytes and strips only quotes/backslash, but the shell expands/word-splits.
  #     The DECLINED SET IS PARITY with the guard's own word-shape vet for a plain command operand —
  #     `_cp8b_seg_word_shape_ok` (.claude/hooks/guard-core.sh) refuses `{ } , * ? [`, and its sibling
  #     `_cp8b_seg_path_ok` refuses `$ ` backtick ` < > ; & |` — plus `\` (which land already had and the
  #     guard handles via its own backslash treatment). land and the guard therefore agree BY
  #     CONSTRUCTION: a merge-cmd character land refuses is a character the guard refuses in an operand.
  #     Every one is a rebuild vector at eval:
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
  #     ([A-Za-z0-9._/-]) above — so no legitimate landing merge is refused. Refused as a CLASS here,
  #     BEFORE the step-4 delete/--admin token scan; that scan then handles the quoted/=value/tab
  #     spellings that carry NO metacharacter.
  case "$merge_cmd" in
    *'$'* | *'`'* | *'\'* | *'<'* | *'>'* | *';'* | *'&'* | *'|'* | *'{'* | *'}'* | *','* | *'*'* | *'?'* | *'['*)
      echo "LAND REFUSED: --merge-cmd carries a shell metacharacter — the merge command is eval'd and the" >&2
      echo "              default needs none. The refused set is parity with the guard's word-shape vet:" >&2
      echo "              \$ backtick \\ < > ; & | { } , * ? [. Such a spelling (e.g. \\--admin," >&2
      echo "              --\$(echo admin), --{admin,}, --admi[n], --admin;) can smuggle a --admin or a" >&2
      echo "              --delete-branch past the token scan, which strips only quotes, because the" >&2
      echo "              eval'd shell rebuilds the flag. Re-run with a merge command free of those." >&2
      return 1 ;;
  esac

  # 4. REFUSE a branch deletion or an --admin bypass in the merge command. TOKENIZE the merge-cmd on
  #    IFS (space/tab/newline) and inspect each token. TRUE SCOPE, no overclaim: the merge-cmd is the
  #    AGENT'S OWN string — same trust model as `actuate` — so this is an ergonomic foot-gun guard,
  #    not an adversarial parser; it is tokenized (not shell-lexed) and defeatable by an uncooperative
  #    caller (the friction-test net stays the CI backstop). It exists because the old space-anchored
  #    globs (`*' --delete-branch'*` etc.) missed a TAB-separated flag and a bundled short cluster
  #    (`-sd`/`-ds` = --squash --delete-branch). It refuses: any --delete-branch/--delete* long flag;
  #    any SHORT cluster (single '-', not '--', containing 'd', so -d/-sd/-ds/-dq); and ANY --admin
  #    form — bare --admin OR --admin=<value> (F3-1: the old EXACT --admin arm let --admin=true ride
  #    in on a value suffix; a landing merge never needs --admin in ANY form, so the whole --admin=*
  #    class is refused — over-refusing the cosmetic --admin=false is the correct, disclosed trade).
  #    QUOTE-STRIP each token first (F3-1): the merge-cmd is one string, so a caller who QUOTES a flag
  #    ('--delete-branch', "--admin") or SPLITS it across adjacent quotes (--del''ete-branch) leaves
  #    the quote bytes on the token here — this is a tokenize, not a shell re-lex. Deleting every ', "
  #    and \ normalizes the quoted/split spelling to its bare form before the case. SCOPE OF "no evade"
  #    (N1/N3, corrected): this token scan defeats the QUOTED / =value / TAB-separated spellings that
  #    carry NO shell metacharacter; every metacharacter spelling — backslash (\--admin), substitution
  #    (--$(echo admin)), brace (--{admin,}, --ad{m,}in), glob (--admi[n]) and glued operator/redirect
  #    (--admin;, --admin|x, --admin>x) — is refused UPSTREAM by the step-3b metachar-decline arm (parity
  #    with the guard's word-shape vet), before this loop. The two arms together are what make "none
  #    evade" true — this scan alone did NOT catch the metacharacter spellings (their tokens are not
  #    --admin/--delete* here — the brace/glob tokens fall through the `--*` arm as inert flags — but the
  #    eval'd shell rebuilds them). The \ added to the tr set below is belt-and-suspenders: step-3b
  #    already refused any token bearing one.
  #    land NEVER deletes a branch (D-240819-4 — the branch object holds the commit the GO note binds)
  #    and NEVER emits a bypass.
  #    ⚠️ SCOPE — the GUARD does NOT cover branch deletion via `git push`: `git push origin --delete
  #    <b>` and `git push origin :<b>` are guard-ALLOW (uncovered, disclosed; D-240819-6 is about
  #    Claude's SETTINGS allow-rules — a prompt — not the guard tier). This matcher scans the
  #    merge-cmd precisely because that push form is not covered elsewhere; `land` itself never deletes
  #    and refuses a `--merge-cmd` that would. ⚠️ Likewise a `git push origin :<b>` colon-refspec
  #    deletion INSIDE a --merge-cmd is out of THIS token scan's scope (disclosed at the guard tier): a
  #    bare `:branch` token carries no shell metacharacter, so the step-3b metachar-decline arm does not
  #    catch it either — the friction-test net for it stays the CI backstop + branch protection.
  _land_deny=""
  _land_oifs=${IFS-__unset__}
  _land_tab="$(printf '\t')"
  _land_nl='
'
  IFS=" $_land_tab$_land_nl"
  set -f
  for _land_tok in $merge_cmd; do
    # Strip every ', " and \ from the token before matching (F3-1 + N1 belt). tr's set is the two
    # quote bytes plus backslash (a token bearing \ was already refused upstream by step-3b).
    _land_norm="$(printf '%s' "$_land_tok" | tr -d "\"'\\\\")"
    case "$_land_norm" in
      --delete-branch|--delete*) _land_deny='delete' ;;
      --admin|--admin=*)         _land_deny='admin' ;;
      --*)                       : ;;
      -*d*)                      _land_deny='delete' ;;
    esac
    if [ -n "$_land_deny" ]; then break; fi
  done
  set +f
  if [ "$_land_oifs" = __unset__ ]; then unset IFS; else IFS=$_land_oifs; fi
  if [ "$_land_deny" = delete ]; then
    echo "LAND REFUSED: --merge-cmd carries a branch-deletion flag (--delete-branch/--delete or a" >&2
    echo "              short cluster like -d/-sd/-ds) — land NEVER deletes a branch. Deletion is a" >&2
    echo "              separate human act (D-240819-4); the branch object holds the commit the GO" >&2
    echo "              note binds. Re-run without the deletion flag." >&2
    return 1
  fi
  if [ "$_land_deny" = admin ]; then
    echo "LAND REFUSED: --merge-cmd carries an --admin token — land NEVER emits a branch-protection" >&2
    echo "              bypass. Approval authorizes promotion, never a bypass (the bypass is the" >&2
    echo "              human's solo kill-switch, denied to the agent by the guard). Re-run without" >&2
    echo "              --admin." >&2
    return 1
  fi

  # 5. MERGE. Non-zero -> loud failure and propagate; the GO note IS already recorded and recoverable,
  #    so only the merge did not complete.
  if eval "$merge_cmd"; then _mrc=0; else _mrc=$?; fi
  if [ "$_mrc" -ne 0 ]; then
    echo "LAND FAILED: merge command exited $_mrc (the GO note IS recorded and recoverable; only the" >&2
    echo "             merge did not complete). Re-run the merge, or land again — record supersedes." >&2
    return "$_mrc"
  fi

  # 6. RELEASE THE ROW'S OWN BOARD CLAIM — the same shared helper `actuate` calls, and the gap that
  #    left eight stale claim refs behind on 2026-09-15 (B2-SESSION-IDENTITY-LEDGER decision 6). It
  #    runs AFTER the merge and can only WARN. The note text is read back from the ref `record` just
  #    wrote and confirmed on origin, so the `kit-row:` projection is the note's own, never a flag.
  _land_note="$(git notes --ref="$NOTES_REF" show "$asha" 2>/dev/null || true)"
  pv_release_claim "$_land_note" land

  # Honest success line, VERB-SCOPED: the record was written BEFORE the merge, so THIS merge is
  # recoverable by this verb — not that recordless merges are impossible (they are detected later by
  # the CI backstop, which stays the friction-test gate).
  [ -z "$PV_STOP_LINE" ] || printf '%s\n' "$PV_STOP_LINE"
  echo "OK: land recorded the GO note on $asha, CONFIRMED it on origin, and merged $ref — control-plane"
  echo "    merged on an authenticated non-author forge approval; the GO-giver is recorded by name,"
  echo "    self-asserted. The record was published BEFORE the merge and verified on origin, so this merge"
  echo "    is recoverable. HONEST CEILING: the approval label was derived over the local gh credential at"
  echo "    record time (a drift control at the note's own tier), so server-side branch protection +"
  echo "    required review is what binds; the net for a recordless merge is the CI recordless-merge"
  echo "    backstop."
  return 0
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
trap '_pv_drop_scratch; _pv_drop_syncref' EXIT
trap '_pv_sig=130; [ "$_pv_crit" = 1 ] || _pv_die 130' INT
trap '_pv_sig=143; [ "$_pv_crit" = 1 ] || _pv_die 143' TERM

_pv_sync_clean() { LC_ALL=C tr -d '\000-\011\013-\037\177'; }
_pv_sync_hex40() { case "$1" in *[!0-9a-f]*|'') return 1 ;; esac; [ "${#1}" = 40 ]; }
# ECHO SWEEP (whole-branch fix round 1, A5/B2): dash's builtin `echo` EXPANDS `\0NNN`, so an `echo` of any
# variable that holds note text, a git-derived string or a remote string can emit a terminal escape on
# Linux (and bash-as-sh on macOS does the same). Every message below that interpolates such text is a
# `printf '%s\n'`, and the untrusted ones also go through _pv_sync_clean.
_pv_sync_say() { if [ "$_sy_dry" = 1 ]; then printf '%s\n' "WOULD $*"; else printf '%s\n' "$*"; fi; }
_pv_sync_is_discard() { case " $_sy_disc " in *" $1 "*) return 0 ;; esac; return 1; }
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
  case "$1" in *[!0-9a-f]*|'') return 1 ;; esac
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
  [ "${_ig1:-(none recorded)}" = "${_ig2:-(none recorded)}" ] || return 1
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
_pv_sync_twin() { # <sha> <origin-body> <local-body>
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
$_cl_shas
EOF
  set -f
  for _cd in $_sy_disc; do
    case " $_sy_used " in *" $_cd "*) ;; *) printf '%s\n' "sync: note: --discard-local $_cd matched no refused or candidate record" >&2 ;; esac
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
    case "$_rq" in "$1"*) printf '%s\n' "$_rq" ;; esac
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
        case "$_dv" in ''|*[!0-9a-f]*) _dv="" ;; esac
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
# The keys, in `record`'s order (line 1 is the literal header, checked separately). TWO SHAPES, because
# GO-IDENTITY-AND-LAND-SOD added `go-by` at line 5 and a ledger holds both: a NEW note is 13 lines
# (_vc_fmt=13) and a LEGACY note (written before) is 12 lines with no go-by (_vc_fmt=12). The shape is
# read from line 5 itself (see _pv_vc_grammar), never guessed from a count alone.
_pv_vc_key() {
  if [ "$_vc_fmt" = 13 ]; then
    case "$1" in
      2) echo approved-sha ;; 3) echo approved-tree ;; 4) echo approved-by ;; 5) echo go-by ;;
      6) echo gate ;; 7) echo rung ;; 8) echo change-class ;; 9) echo kit-row ;; 10) echo scope ;;
      11) echo approval-token ;; 12) echo basis ;; 13) echo recorded-at ;;
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
  case "$(printf '%s\n' "$_vc_body" | sed -n '5p')" in "go-by: "*) _vc_fmt=13 ;; esac
  _vc_goby="(none recorded)"
  _vc_n=0
  while IFS= read -r _vc_l; do
    _vc_n=$((_vc_n + 1))
    # F4(b): `record` stores through `notes add -F -`, which strips trailing whitespace, so a line ending in a
    # space is not a body record wrote. (A trailing TAB is a control byte, refused above.)
    case "$_vc_l" in *' ') _pv_vc_fail grammar "line $_vc_n ends in a space (record never stores one)"; return 1 ;; esac
    if [ "$_vc_n" = 1 ]; then
      [ "$_vc_l" = "record: promotion GO (approve->execute->log)" ] || { _pv_vc_fail grammar "line 1 is not record's header"; return 1; }
      continue
    fi
    _vc_k="$(_pv_vc_key "$_vc_n")"
    [ -n "$_vc_k" ] || { _pv_vc_fail grammar "more than the $_vc_fmt lines record writes"; return 1; }
    case "$_vc_l" in "$_vc_k: "*) ;; *) _pv_vc_fail grammar "line $_vc_n is not '$_vc_k: ...'"; return 1 ;; esac
    _vc_v="${_vc_l#"$_vc_k: "}"
    case "$_vc_k" in
      approved-sha) _vc_asha="$_vc_v" ;; approved-tree) _vc_tree="$_vc_v" ;; approved-by) _vc_by="$_vc_v" ;;
      go-by) _vc_goby="$_vc_v" ;; gate) _vc_gate="$_vc_v" ;; rung) _vc_rung="$_vc_v" ;;
      change-class) _vc_cls="$_vc_v" ;; kit-row) _vc_row="$_vc_v" ;; scope) _vc_scope="$_vc_v" ;;
      approval-token) _vc_tok="$_vc_v" ;; basis) _vc_basis="$_vc_v" ;; recorded-at) _vc_ts="$_vc_v" ;;
    esac
  done <<EOF
$_vc_body
EOF
  [ "$_vc_n" = "$_vc_fmt" ] || { _pv_vc_fail grammar "$_vc_n lines, record writes exactly $_vc_fmt for this note's shape (12 legacy, 13 with go-by)"; return 1; }
  for _vc_f in "$_vc_asha" "$_vc_tree" "$_vc_by" "$_vc_goby" "$_vc_gate" "$_vc_rung" "$_vc_cls" "$_vc_row" "$_vc_scope" "$_vc_tok" "$_vc_basis" "$_vc_ts"; do
    [ -n "$_vc_f" ] || { _pv_vc_fail grammar "an empty field"; return 1; }
  done
  _pv_vc_goby || return 1
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
  [ "$_vc_goby" != "(none recorded)" ] || return 0
  case "$_vc_goby" in *' [self-asserted]') ;; *) _pv_vc_fail go-by "not '<name> [self-asserted]' or '(none recorded)' (the GO-giver is never authenticated)"; return 1 ;; esac
  _vc_gid="${_vc_goby%' [self-asserted]'}"
  [ -n "$(printf '%s' "$_vc_gid" | tr -d ' \t')" ] || { _pv_vc_fail go-by "the GO-giver name is whitespace-only (record refuses one)"; return 1; }
  case "$_vc_gid" in *'['*|*']'*) _pv_vc_fail go-by "a bracket inside the name (the label is a fixed literal, never supplied)"; return 1 ;; esac
  return 0
}
# V7 — approved-by: `<id> [<label>]`; the label must equal one `record` could derive NOW. Runs LAST (I5):
# the forge derivation interpolates the note's untrusted scope into an API path, so V1-V6 sanitize first.
_pv_vc_by() {
  case "$_vc_by" in *' ['*']') ;; *) _pv_vc_fail approved-by "not '<id> [<label>]'"; return 1 ;; esac
  _vc_id="${_vc_by%% \[*}"
  _vc_lab="${_vc_by#"$_vc_id" \[}"; _vc_lab="${_vc_lab%\]}"
  [ -n "$_vc_id" ] && [ "$_vc_id [$_vc_lab]" = "$_vc_by" ] || { _pv_vc_fail approved-by "not '<id> [<label>]'"; return 1; }
  # A3: `record` refuses a whitespace-only --approved-by; a note it could not have written is refused too.
  [ -n "$(printf '%s' "$_vc_id" | tr -d ' \t')" ] || { _pv_vc_fail approved-by "the approver id is whitespace-only (record refuses one)"; return 1; }
  case "$_vc_id$_vc_lab" in *'['*|*']'*) _pv_vc_fail approved-by "a bracket inside the id or the label"; return 1 ;; esac
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
  case "$_vc_asha" in -*) _pv_vc_fail approved-sha "starts with '-'"; return 1 ;; esac
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
  _pv_vc_by || return 1                                                                                                                          # V7
}
# Validate every candidate (all of them, so one run names every failure). Failures count as refusals.
# A6: `</dev/null` — a command inside this heredoc-fed loop that reads stdin (a `gh`, a hook) would eat the
# remaining candidate lines and silently validate fewer than were counted; and the count is CHECKED against
# the number classify found (rc 2 if they differ) before anything is built.
_pv_sync_validate_all() {
  _va_n=0
  while IFS=' ' read -r _va_s _va_b; do
    [ -n "$_va_s" ] || continue
    _va_n=$((_va_n + 1))
    _pv_validate_candidate "$_va_s" "$_va_b" </dev/null || _pv_sync_refuse
  done <<EOF
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
  while IFS=' ' read -r _bd_s _bd_b; do
    [ -n "$_bd_s" ] || continue
    # I1, asserted: a candidate is absent from origin's tip BY CONSTRUCTION; if it is not, refuse.
    if [ -n "$(_pv_sync_blob "$_cl_ot" "$_bd_s")" ]; then
      printf '%s\n' "sync: REFUSED $_bd_s: origin already has a note on it — a published note is never overwritten (I1). Nothing changed." >&2; return 2
    fi
    KIT_PROMOTION_FRONT_DOOR=1 git notes --ref="${NOTES_SYNCREF#refs/notes/}" add -C "$_bd_b" "$_bd_s" >/dev/null 2>&1 || {
      printf '%s\n' "sync: could not add the note for $_bd_s to the build ref — REFUSED; nothing changed." >&2; return 2; }
  done <<EOF
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
  case "$_pp_out" in *non-fast-forward*|*'fetch first'*) _pp_nonff=1 ;; *) _pp_nonff=0 ;; esac
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
    while read -r _pc_o _pc_n; do
      [ "$_pc_n" = "refs/notes/$NOTES_REF" ] || continue
      _pc_hit=$((_pc_hit + 1)); _pc_r="$_pc_o"
    done <<EOF
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
  while IFS=' ' read -r _rp_s _rp_b; do
    [ -z "$_rp_s" ] || printf '%s\n' "published $_rp_s"
  done <<EOF
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
case "$cmd" in
  record)  if do_record  "$@"; then rc=0; else rc=$?; fi ;;
  sync)    if do_sync  "$@"; then rc=0; else rc=$?; fi ;;
  log)     if do_log     "$@"; then rc=0; else rc=$?; fi ;;
  trace)   if do_trace   "$@"; then rc=0; else rc=$?; fi ;;
  check)   if do_check   "$@"; then rc=0; else rc=$?; fi ;;
  actuate) if do_actuate "$@"; then rc=0; else rc=$?; fi ;;
  land)    if do_land    "$@"; then rc=0; else rc=$?; fi ;;
  -h|--help) usage; rc=2 ;;
  *) usage; rc=2 ;;
esac
exit "$rc"
