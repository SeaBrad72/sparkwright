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
# What it changes: `record` binds a GO record as a git NOTE under refs/notes/promotions (tree-invariant — the commit's tree/SHA is unchanged); `actuate` performs a real control-plane PR merge (default `gh pr merge --squash`, swappable via --merge-cmd) bound to the approved SHA; `log`, `check` and `trace` are read-only.
# Guardrails: `check` asserts shipped==approved by TREE equality (exit 1 on MISMATCH); the approved-by assurance label is DERIVED from the commit's own evidence (never from input) — a note BINDS, it does not AUTHENTICATE. `actuate` fails CLOSED unless a SHA-bound [authenticated: <forge>-review] GO exists and approver != author, rejects `$ref` metacharacters, NEVER emits `--admin`, and re-verifies shipped==approved after the merge. `record` derives `kit-row:` from the approved commit's own trailer (never a flag), records `(none)` rather than inventing one, and sanitises it with every other free-text field; `trace` matches a trunk commit to its note by TREE (never ancestry, which a squash breaks), reds on any recordless commit in a `--recent` window, and fails closed on an empty window.
set -eu

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
_pv_drop_scratch() { git update-ref -d "$NOTES_SCRATCH" >/dev/null 2>&1 || true; }
trap '_pv_drop_scratch' EXIT INT TERM

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
  if git fetch --no-tags origin "refs/notes/$NOTES_REF:refs/notes/$NOTES_REF" >/dev/null 2>&1; then
    return 0
  fi
  # The fetch refused. Split "diverged" (the case with a real remedy) from everything else by
  # MEASURING the two chains against each other, locally — never by trusting the remote's answer.
  if ! git fetch --no-tags -f origin "refs/notes/$NOTES_REF:$NOTES_SCRATCH" >/dev/null 2>&1; then
    echo "record: fetching refs/notes/$NOTES_REF from origin failed and the reason could not be" >&2
    echo "        determined (the ref is present but unfetchable). Refusing to record." >&2
    return 2
  fi
  _si_n="$(git rev-list "refs/notes/$NOTES_REF" ^"$NOTES_SCRATCH" --count 2>/dev/null || echo 0)"
  _pv_drop_scratch
  if [ "${_si_n:-0}" -gt 0 ] 2>/dev/null; then
    echo "record: ledger diverged: the local refs/notes/$NOTES_REF carries $_si_n record(s) the remote" >&2
    echo "        does not; publish them first (git push origin refs/notes/$NOTES_REF) or, if they are" >&2
    echo "        not yours, inspect them with promotion-verify.sh log --unpushed. Refusing to record." >&2
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
  echo "                             [--no-push]" >&2
  echo "        record is a TRANSACTION: it fetches refs/notes/<ref> from origin first, refuses if" >&2
  echo "        the local ledger has diverged, writes the note, PUBLISHES it, and unwinds its own" >&2
  echo "        unpublished note if the push is rejected (retrying once on a non-fast-forward)." >&2
  echo "        --no-push skips BOTH the fetch and the publish (fixtures / explicitly offline" >&2
  echo "                  maintenance); its OK line ends UNPUBLISHED." >&2
  echo "        --scope takes a PR id (CI's key) or branch/<name> (the pre-push key, ruling D11)" >&2
  echo "        --approved-by must be the reviewer's FORGE LOGIN, verbatim (e.g. 'ISBrad72', not" >&2
  echo "                      'Bradley James'): the [authenticated: <forge>-review] upgrade requires a" >&2
  echo "                      BYTE-EQUAL match to the review's user.login, so a display name records a" >&2
  echo "                      weaker label and says why on stderr rather than failing." >&2
  echo "        --class must be one of: ordinary | sensitive | control-plane (case-insensitive)" >&2
  echo "  promotion-verify.sh log [--unpushed]" >&2
  echo "        --unpushed lists only the records the remote ledger does not have; it fails CLOSED" >&2
  echo "                   (UNKNOWN, rc 2) when the remote cannot be read — never a silent '0'." >&2
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
  #    refusal do_actuate already makes at :651.
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

do_record() {
  asha=""; aby=""; gate=""; rung=""; cls=""; scope=""; token=""; basis=""; nopush=0
  while [ $# -gt 0 ]; do
    case "$1" in
      # ARGUMENT ONLY, never an env var (security vet T3): the offline escape must be visible in the
      # command the operator ran and in the shell history, not settable by ambient state.
      --no-push)      nopush=1; shift ;;
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
  # CHANGE-CLASS VOCABULARY (review M1 / security F2 — the two ends of one hardening; the other end is
  # do_actuate's allowlist). `change-class:` is now a DECIDING field: actuate proceeds only for
  # ordinary/sensitive and refuses control-plane. A free-text class was therefore a way to record a
  # note that no consumer can classify — a typo (`contol-plane`, `Control Plane`) would sail past
  # record and then be refused at actuate with a confusing message, or worse, be read as neither.
  # Validate at the FRONT DOOR, fail closed at rc 2, so the defect is caught where it is cheap.
  # Placed here deliberately: AFTER the control-char and bracket rejections (nothing may precede
  # those), and before the note is composed.
  case "$(printf '%s' "$cls" | LC_ALL=C tr 'A-Z' 'a-z')" in
    ordinary|sensitive|control-plane) ;;
    *)
      echo "record: invalid --class '$cls' — must be one of: ordinary | sensitive | control-plane" >&2
      echo "        (case-insensitive). The class DECIDES whether \`actuate\` may merge, so an" >&2
      echo "        unrecognised value would record a GO no consumer can classify. Rejected (fail closed)." >&2
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
      "gate: $gate" \
      "rung: $rung" \
      "change-class: $cls" \
      "kit-row: $kitrow" \
      "scope: $scope" \
      "approval-token: \"$token\"" \
      "basis: $basis" \
      "recorded-at: $ts")"

  # THE TRANSACTION: sync-in -> write -> publish -> unwind. At most two attempts; the second only
  # ever happens on a NON-FAST-FORWARD rejection, which is the one failure a fresh sync-in can fix.
  attempt=1
  while : ; do
    if [ "$nopush" = 0 ]; then
      _pv_sync_in || return 2
    fi
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
      0) if ! git fetch --no-tags -f origin "+refs/notes/$NOTES_REF:$NOTES_SCRATCH" >/dev/null 2>&1; then
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
      done
    done
    _pv_drop_scratch
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
  kr_line="$(printf '%s\n' "$note" | grep '^kit-row:' | head -1 || true)"
  kr="${kr_line#kit-row:}"
  # ⚠️ CONTROL BYTES OUT FIRST (security S-L6). `kr` comes from a GIT NOTE — self-authorable text —
  # and it is printed straight into an operator's terminal by the WARN lines below. An ANSI escape in
  # a `kit-row:` projection could repaint or forge those lines, which are the audit record of a merge.
  # Stripped once, here, so every consumer downstream (the prints AND the argument handed to
  # board-claim.sh) sees the sanitised value; board-claim's own row grammar is the second gate.
  kr="$(printf '%s' "$kr" | tr -d '[:cntrl:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  bc_sh="$(dirname -- "$0")/board-claim.sh"
  if [ -z "$kr" ] || [ "$kr" = '(none)' ]; then
    echo "actuate: no kit-row on the GO note — no board claim to release (nothing invented)."
  elif [ ! -f "$bc_sh" ]; then
    echo "actuate: WARN — board-claim.sh not found beside this script; claim on '$kr' NOT released." >&2
  elif sh "$bc_sh" release "$kr" --stale; then
    echo "actuate: board claim on '$kr' released (refs/claims/$kr deleted on origin)."
  else
    echo "actuate: WARN — could not release the board claim on '$kr' (refs/claims/$kr may still exist)." >&2
    echo "               The merge SUCCEEDED and is verified; release by hand:" >&2
    echo "               sh scripts/board-claim.sh release $kr --stale" >&2
  fi

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
