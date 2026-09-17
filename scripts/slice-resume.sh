#!/bin/sh
# slice-resume.sh — reconstruct a PARKED slice from the tracked ledger alone, and name ONE next step
# (B2-SESSION-IDENTITY-LEDGER, design decision 7; routed as `sparkwright resume <ROW>`).
#
# THE DEFECT THIS CLOSES. A slice parked at the end of a session leaves its state in five places —
# the claim ref on origin, the branch head's trailers, the plan, the review record, and the board row
# — and the only thing that knew how to read them together was the session that wrote them. The cold
# start therefore began with a human (or an agent) re-deriving all five by hand, which is exactly the
# moment a wrong assumption gets made and a second session claims a row somebody still holds.
#
#   sh scripts/slice-resume.sh <ROW-ID>
#   sh scripts/slice-resume.sh --selftest
#
# EXIT CODES: 0 rendered · 1 no claim on the row (the "not parked" reading) · 2 usage / bad row id /
#             REMOTE UNREACHABLE. A silent 0 is never an answer here either.
#
# WHAT IT IS NOT: not a claim, not a checkout, not a write of ANY kind. It reads, it renders, and it
# names the act — the resuming conductor performs it. Every fact NAMES ITS SOURCE or reads `unknown`,
# and anything not derivable makes the next-step table fall through to its most conservative row.
#
# HONEST CEILING:
#   * `session.id` is DECLARED, NEVER AUTHENTICATED (B2 decision 1). When the claim's session differs
#     from this worktree's, that is printed — and it does NOT prove the other session is gone. Two
#     live sessions of one human on one branch are indistinguishable from a resume.
#   * A design-GO assurance label is printed VERBATIM, beside the NOTE'S OWN COMMITTER, under the
#     sentence "label as recorded, not re-derived". It is a DRIFT CONTROL against front-door misuse
#     (a `[committer]` GO on a slice the owner never saw is visible at the cold start) and it is
#     honestly NOT a control against a forger who writes the stronger label through a raw route.
#   * The next step is DERIVED FROM A FIXED TABLE, not judged. It is the most conservative act
#     consistent with what is readable, not a plan.
# POSIX sh; dash-clean (no `local`, no bashisms).
# What it changes: NOTHING — it is read-only. It fetches into PID-scoped scratch refs under
#   `refs/kit-scratch/` and drops them on EXIT; it writes no file, edits no board, and touches no
#   claim, note or branch on any remote.
# Guardrails: the row id is validated against `[A-Z0-9][A-Z0-9-]*` and the claim's `branch:` against
#   `git check-ref-format --branch` BEFORE either becomes part of a refspec, so a planted CLAIM
#   carrying `--upload-pack=<cmd>` is refused before any git call; branches are only ever passed as
#   full refspecs (`refs/heads/<b>:refs/kit-scratch/<pid>`) or as `--head=<b>` to `gh`, never as bare
#   arguments; trailer values are read with git's OWN trailer parser, never a regex over the body; a
#   path value from a trailer is held to `[A-Za-z0-9._/-]` with no leading `/` and no `..`; every
#   blob is read through `git show <scratch>:<path> | head -c 65536`; and an unreachable remote
#   REFUSES (rc 2) rather than rendering a slice state nobody could look up.
set -eu

SR_REMOTE="${BOARD_CLAIM_REMOTE:-origin}"
SR_SELF=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")
SR_BC=$(dirname -- "$SR_SELF")/board-claim.sh
# THE BRANCH REF inside the isolated dir. `refs/scratch` is fine there — it is a private throwaway.
SR_SCRATCH="refs/scratch"
# ⚠️ THE NOTES SCRATCH REF MUST LIVE UNDER `refs/notes/` — measured: `git notes --ref=<x>` PREPENDS
# `refs/notes/` to anything that does not already start with it, so a scratch under a different
# prefix silently became `refs/notes/refs/…` and every `list` came back empty (the design-GO lookup
# read `unknown` for a note that was right there).
SR_NOTES="refs/notes/kit-scratch"
SR_MAX_BYTES=65536

# ── ISOLATED READS — the same class of bug board-claim.sh's isolated-reads block documents (fix
# round 2). This verb's branch fetch is `--depth=1`, and a `--depth` fetch writes `.git/shallow`
# into the repo it fetches INTO; even though `resume` never pushes, leaving the OPERATOR'S live
# clone shallow is the bug (their next push would be rejected by a remote that enforces
# `receive.shallowUpdate` — ubuntu git, MEASURED). So every fetch here goes into a THROWAWAY git dir
# that the operator never pushes from, and it is removed on EXIT. The named remote is resolved to a
# URL/path once, because a fresh `git init` dir has no `origin` to name.
# ⚠️ CREATED EAGERLY, IN THE PARENT SHELL. `resume` queries this ONE dir repeatedly (trailers,
# blobs, the notes ref), so `SR_ISO` must persist across the whole render — a lazy
# `SR_ISO=$(mktemp -d)` reached only from a command-substitution subshell would set it in the
# subshell and leave the parent's `sr_show`/`sr_trailer` seeing nothing (and the EXIT trap leaking
# the dir). `resume` always fetches the branch when the claim resolves, so eager creation is not
# wasted; if mktemp/init fails, `SR_ISO` is empty and the readers degrade to `unknown`.
SR_ISO=$(mktemp -d 2>/dev/null || echo '')
if [ -n "$SR_ISO" ] && ! git init -q "$SR_ISO" >/dev/null 2>&1; then rm -rf "$SR_ISO"; SR_ISO=""; fi
sr_remote_url() { git remote get-url "$SR_REMOTE" 2>/dev/null || printf '%s' "$SR_REMOTE"; }
sr_iso() { [ -n "$SR_ISO" ] && printf '%s\n' "$SR_ISO"; }

sr_drop() {
  { [ -n "${SR_ISO:-}" ] && rm -rf "$SR_ISO" 2>/dev/null; } || true
  SR_ISO=""
  return 0
}
# ⚠️ BEST-EFFORT, SAME REASON AS board-claim.sh's bc_cleanup (fix round 3). In dash a command that
# fails inside an EXIT trap can override the script's real exit status, and under `kit-guard
# install-shims` the guard BLOCKS `rm -rf` — so an unguarded cleanup `rm` reports a successful
# read-only `resume` as a failure. Every destructive step is wrapped so it can never change the
# exit code; `2>/dev/null` keeps a normal shimmed run quiet.
sr_cleanup() {
  sr_drop 2>/dev/null || true
  { [ -n "${sr_base:-}" ] && rm -rf "$sr_base" 2>/dev/null; } || true
  return 0
}
trap 'sr_cleanup' EXIT INT TERM

sr_usage() {
  echo "usage:" >&2
  echo "  slice-resume.sh <ROW-ID>     # reconstruct a parked slice and name ONE next step" >&2
  echo "  slice-resume.sh --selftest" >&2
}

# ── GRAMMARS — EVERY ONE OF THEM RUNS BEFORE ANY GIT CALL ───────────────────────────────────────
# The row id becomes a ref name; the branch becomes an argument to git and gh; a trailer path becomes
# an argument to `git show`. All three are untrusted (the CLAIM and the branch head are written by
# whoever held the ref), so all three are validated offline, first.
sr_row_ok() {
  case "$1" in
    '')           return 1 ;;
    [!A-Z0-9]*)   return 1 ;;
    *[!A-Z0-9-]*) return 1 ;;
  esac
  return 0
}
sr_branch_ok() {
  case "$1" in
    '')                 return 1 ;;
    -*)                 return 1 ;;
    *[!A-Za-z0-9._/-]*) return 1 ;;
    *'@{'*)             return 1 ;;
  esac
  git check-ref-format --branch "$1" >/dev/null 2>&1 || return 1
  return 0
}
# A PATH from a trailer. `..` is refused as a COMPONENT-agnostic substring on purpose: this value is
# never resolved on a filesystem, only handed to `git show <ref>:<path>`, and a refusal costs one
# `unknown` line while a traversal costs a read of whatever the branch author pointed at.
sr_path_ok() {
  case "$1" in
    '')                  return 1 ;;
    /*)                  return 1 ;;
    *'..'*)              return 1 ;;
    *[!A-Za-z0-9._/-]*)  return 1 ;;
  esac
  return 0
}

# ── READS — every one bounded, every one against the ISOLATED throwaway dir the EXIT trap drops ──
sr_show() { # <path> -> the blob, bounded; empty when absent or refused
  sr_path_ok "$1" || return 0
  [ -n "$SR_ISO" ] || return 0
  git -C "$SR_ISO" show "$SR_SCRATCH:$1" 2>/dev/null | head -c "$SR_MAX_BYTES" || true
}
# ── THIS WORKTREE'S DECLARED SESSION — READ WITH `board-claim.sh`'S OWN HYGIENE ────────────────
# [fix round 1, M5] The first build opened `.kit-run/session.id` with a bare `-f` test and a `head`.
# That file is NOT control-plane to the guard, so anyone (or any stray process) can plant one — and
# a FIFO there (`mkfifo .kit-run/session.id`) HANGS this verb forever, which is a denial of service
# on the cold-start reader, the one command a stuck session runs first. A symlink is the same class.
# So the same predicate `bc_session_read` applies runs here BEFORE any open: not a symlink, a
# regular file, owned by this uid, link count 1, bounded by `head -c 256`, held to the grammar.
# ⚠️ THE DIFFERENCE FROM THE WRITE VERB IS DELIBERATE AND IS THE RULE FOR THE READ-ONLY TWINS: a
# verb that WRITES (`claim`) REFUSES rc 2 on a bad state file, because it is about to act on it; a
# verb that REPORTS (`resume`, `agent-trace`) DEGRADES to `unknown`, NAMES THE PATH AND THE REASON,
# and carries on — refusing to describe a parked slice because a state file is malformed would take
# the cold-start reader away exactly when it is needed most.
sr_session_id() { # -> "<id>" | "unknown (<path>: <why>)"
  _ssf=""
  _sstop=$(git rev-parse --show-toplevel 2>/dev/null) || { printf 'unknown\n'; return 0; }
  [ -n "$_sstop" ] || { printf 'unknown\n'; return 0; }
  _ssd="$_sstop/.kit-run"
  _ssf="$_ssd/session.id"
  [ -L "$_ssd" ] && { printf 'unknown (%s: the directory is a symlink)\n' "$_ssd"; return 0; }
  [ -e "$_ssf" ] || { printf 'unknown\n'; return 0; }
  # `-L` BEFORE `-e`/`-f`: `-e` follows the link, so a dangling or redirecting symlink would read as
  # an ordinary file (the same ordering `runaway-guard.sh` documents for the tally).
  [ -L "$_ssf" ] && { printf 'unknown (%s: is a symlink)\n' "$_ssf"; return 0; }
  # A FIFO passes `-e` and HANGS the read — this is the plant that motivated the whole check.
  [ -p "$_ssf" ] && { printf 'unknown (%s: is a FIFO, not a regular file)\n' "$_ssf"; return 0; }
  [ -f "$_ssf" ] || { printf 'unknown (%s: is not a regular file)\n' "$_ssf"; return 0; }
  # shellcheck disable=SC3067  # `-O` is outside POSIX test and measured present on every shell this
  # runs under; a shell lacking it makes `[` fail, which lands on the degradation — fail-safe.
  [ -O "$_ssf" ] || { printf 'unknown (%s: is not owned by this user)\n' "$_ssf"; return 0; }
  _ssln=$(ls -ld -- "$_ssf" 2>/dev/null | awk '{print $2}')
  [ "$_ssln" = 1 ] || { printf 'unknown (%s: link count %s, not 1)\n' "$_ssf" "$_ssln"; return 0; }
  _ssv=$(head -c 256 -- "$_ssf" 2>/dev/null || true)
  _ssnl='
'
  case "$_ssv" in *"$_ssnl"*) printf 'unknown (%s: more than one line)\n' "$_ssf"; return 0 ;; esac
  case "$_ssv" in
    '')                printf 'unknown (%s: is empty)\n' "$_ssf"; return 0 ;;
    *[!A-Za-z0-9._-]*) printf 'unknown (%s: not [A-Za-z0-9._-]{1,64})\n' "$_ssf"; return 0 ;;
  esac
  [ "${#_ssv}" -le 64 ] || { printf 'unknown (%s: longer than 64 characters)\n' "$_ssf"; return 0; }
  printf '%s\n' "$_ssv"
}

sr_trailer() { # <Key> -> the trailer value off the branch head, through GIT'S OWN parser (isolated)
  [ -n "$SR_ISO" ] || return 0
  git -C "$SR_ISO" log -1 --format="%(trailers:key=$1,valueonly)" "$SR_SCRATCH" 2>/dev/null \
    | head -1 | tr -d '[:cntrl:]'
}

# ── main ────────────────────────────────────────────────────────────────────────────────────────
do_resume() {
  _row=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -*) echo "resume: unknown option '$1'" >&2; sr_usage; return 2 ;;
      *)  [ -z "$_row" ] || { echo "resume: one row id, not two" >&2; return 2; }; _row=$1; shift ;;
    esac
  done
  if ! sr_row_ok "$_row"; then
    echo "resume: invalid row id '$(printf '%s' "$_row" | tr -d '[:cntrl:]')' — a row id must match [A-Z0-9][A-Z0-9-]*." >&2
    return 2
  fi
  [ -f "$SR_BC" ] || { echo "resume: board-claim.sh not found beside this script ($SR_BC)." >&2; return 2; }

  echo "── resume \`$_row\` ─────────────────────────────────────────────────────────"
  echo ""

  # (a) THE CLAIM — read through board-claim.sh's MACHINE lines, never by parsing its prose.
  if _ck=$(sh "$SR_BC" check "$_row" 2>&1); then _ckrc=0; else _ckrc=$?; fi
  if [ "$_ckrc" = 2 ]; then
    printf '%s\n' "$_ck" >&2
    echo "resume: REFUSED — the claim could not be read, so no state below would be trustworthy." >&2
    return 2
  fi
  _holder=$(printf '%s\n' "$_ck" | sed -n 's/^claim-holder: //p' | head -1)
  _branch=$(printf '%s\n'  "$_ck" | sed -n 's/^claim-branch: //p' | head -1)
  _at=$(printf '%s\n'      "$_ck" | sed -n 's/^claim-at: //p' | head -1)
  _csession=$(printf '%s\n' "$_ck" | sed -n 's/^claim-session: //p' | head -1)
  [ -n "$_csession" ] || _csession=unknown

  # A CLAIM THAT IS PRESENT BUT UNREADABLE IS NOT "NO CLAIM" (the same split board-claim.sh makes).
  # `check` returns 0 for a ref whose CLAIM is missing or MALFORMED — including the branch-grammar
  # refusal — and reporting that as an unheld row would invite a second session to claim it.
  if [ "$_ckrc" = 0 ] && [ -z "$_holder" ]; then
    printf '%s\n' "$_ck" >&2
    echo "resume: REFUSED — \`$_row\` HAS a claim on $SR_REMOTE whose CLAIM cannot be read (missing," >&2
    echo "        malformed, or carrying a branch value that is not a branch name). A held row whose" >&2
    echo "        holder cannot be read is not an unheld row, and is not resumable either." >&2
    return 2
  fi
  if [ "$_ckrc" = 1 ] || [ -z "$_holder" ]; then
    # TABLE ROW 1 — no claim. The row is not parked; it is unheld.
    echo "claim:        none on $SR_REMOTE"
    _log=$(sh "$SR_BC" status 2>/dev/null | grep -A1 "\`$_row\`" | grep 'last release:' | head -1 || true)
    if [ -n "$_log" ]; then echo "last release:$_log"; fi
    echo ""
    echo "NEXT STEP:    not parked — claim it."
    echo "              sh scripts/board-claim.sh claim $_row --branch <your-branch>"
    return 1
  fi

  # THE BRANCH GRAMMAR, BEFORE ANY REFSPEC IS COMPOSED [sec-2]. A CLAIM is written by whoever holds
  # the ref; a `branch:` of `--upload-pack=<cmd>` handed to `git fetch` as a bare argument would
  # execute on THIS machine. board-claim.sh refuses such a CLAIM at read; this is the second gate,
  # and it is here so this script is safe even against a board-claim.sh that regressed.
  if ! sr_branch_ok "$_branch"; then
    echo "resume: REFUSED — the claim's branch value is not a valid branch name, so nothing here" >&2
    echo "        will be passed to git. (It would have become an argument on this machine.)" >&2
    return 2
  fi

  echo "claim:        held by $_holder"
  echo "  branch:     $_branch"
  echo "  claimed-at: $_at"
  echo "  session:    $_csession  (declared, never authenticated)"
  _mysession=$(sr_session_id)
  # Printed whether it resolved or not: when it did not, the line carries the PATH and the REASON,
  # which is the whole point of degrading instead of refusing (M5).
  echo "  this worktree's session: $_mysession"
  case "$_mysession" in unknown*) _mysession=unknown ;; esac
  if [ "$_csession" != unknown ] && [ "$_mysession" != unknown ] && [ "$_csession" != "$_mysession" ]; then
    echo "  ⚠️  this worktree's session is '$_mysession', the claim's is '$_csession'."
    echo "      Nothing here proves the other session is gone — session.id is declared, not"
    echo "      authenticated, and two LIVE sessions look exactly like a resume."
  fi
  echo ""

  # (b) THE BRANCH — fetched by FULL REFSPEC into the ISOLATED dir (fix round 2), `--depth=1`, so the
  # operator's own clone is never left shallow. The `ls-remote` probe runs against the caller's
  # clone (a read that fetches nothing), and only the `--depth` fetch is isolated.
  _haveb=0
  if git ls-remote --exit-code "$SR_REMOTE" "refs/heads/$_branch" >/dev/null 2>&1; then
    if _sr_gd=$(sr_iso) \
       && git -C "$_sr_gd" fetch --no-tags --depth=1 "$(sr_remote_url)" "refs/heads/$_branch:$SR_SCRATCH" >/dev/null 2>&1; then
      _haveb=1
    fi
  else
    _lsrc=$?
    if [ "$_lsrc" != 2 ]; then
      echo "resume: REFUSED — cannot reach $SR_REMOTE to read branch '$_branch' (rc $_lsrc)." >&2
      return 2
    fi
  fi
  if [ "$_haveb" = 0 ]; then
    # TABLE ROW 2 — the branch is not on origin. There is nothing to resume FROM ORIGIN.
    echo "branch:       ABSENT on $SR_REMOTE"
    echo ""
    echo "NEXT STEP:    never pushed or deleted — ask the holder; nothing to resume from origin."
    # ⚠️ NO `--stale` SUGGESTION HERE, AND THAT IS A FIX-ROUND REPAIR (H2). The first build printed
    # the release command on this row. But under `ONE-PUSH-PER-PR` a slice pushes ONCE, at the end,
    # so "branch absent from origin" is the NORMAL state of a healthy in-build slice — measured: this
    # verb printed "release it as stale" about the very slice that was being built at the time. A
    # cold-start reader suggesting the deletion of live work is worse than one that says "ask".
    echo "              (An absent branch is NOT evidence the holder is gone: under one-push-per-PR"
    echo "               a slice's branch reaches origin only at its final push. Ask; do not reclaim.)"
    return 0
  fi
  _head=$(git -C "$SR_ISO" rev-parse "$SR_SCRATCH" 2>/dev/null || echo unknown)
  echo "branch:       $_branch @ $_head (on $SR_REMOTE)"
  _kclass=$(sr_trailer Kit-Class); _kstage=$(sr_trailer Kit-Stage)
  _kplan=$(sr_trailer Kit-Plan);   _kreview=$(sr_trailer Kit-Review)
  echo "  trailers:   Kit-Class: ${_kclass:-unknown} · Kit-Stage: ${_kstage:-unknown}"
  echo "              Kit-Plan: ${_kplan:-unknown} · Kit-Review: ${_kreview:-unknown}"

  # (d) THE DESIGN GO — printed VERBATIM with the note's OWN committer [sec-7]. Fetched into the
  # ISOLATED dir too (fix round 2): even un-`--depth`'d, it wrote a ref into the operator's clone
  # before; now it does not. NOT `--depth`-bounded on purpose — the committer attribution walks the
  # ledger history to find the commit that introduced this note's path, which a shallow fetch could
  # not see; the isolated dir is thrown away, so the transfer is a one-run cost, not a poisoned clone.
  _golabel=unknown; _gowho=unknown
  if [ -n "$SR_ISO" ] && git -C "$SR_ISO" fetch --no-tags "$(sr_remote_url)" "refs/notes/promotions:$SR_NOTES" >/dev/null 2>&1; then
    _nl=$(git -C "$SR_ISO" notes --ref="$SR_NOTES" list 2>/dev/null | head -200 || true)
    for _pair in $(printf '%s\n' "$_nl" | awk '{print $1 ":" $2}'); do
      _nobj=${_pair%%:*}; _ncommit=${_pair##*:}
      _ntxt=$(git -C "$SR_ISO" cat-file -p "$_nobj" 2>/dev/null | head -c "$SR_MAX_BYTES" || true)
      case "$_ntxt" in
        *"scope: branch/$_branch"*) ;;
        *) continue ;;
      esac
      case "$_ntxt" in *"gate: design"*) ;; *) continue ;; esac
      _golabel=$(printf '%s\n' "$_ntxt" | sed -n 's/^approved-by: //p' | head -1 | tr -d '[:cntrl:]')
      # THE NOTE'S OWN COMMITTER, from the ledger commit that introduced this note's path — both the
      # flat and the fanned-out spellings, because git chooses between them by tree size.
      _fan="$(printf '%s' "$_ncommit" | cut -c1-2)/$(printf '%s' "$_ncommit" | cut -c3-)"
      _gowho=$(git -C "$SR_ISO" log -n 1 --format='%cn <%ce>' "$SR_NOTES" -- "$_ncommit" "$_fan" 2>/dev/null || true)
      [ -n "$_gowho" ] || _gowho=unknown
      break
    done
  fi
  echo ""
  echo "design GO:    ${_golabel:-unknown}"
  echo "  note committer: $_gowho"
  echo "  ⚠️  label as recorded, not re-derived — a note BINDS, it does not AUTHENTICATE."
  if [ "$_golabel" != unknown ] && command -v gh >/dev/null 2>&1; then
    case "$_golabel" in
      *'[authenticated:'*)
        if _rv=$(gh pr view "$_branch" --json reviews --jq '.reviews | length' 2>/dev/null); then
          [ "${_rv:-0}" -gt 0 ] || echo "  ⚠️  label unconfirmed — the forge reports no review on this head."
        else
          echo "  (label unconfirmed — gh could not be asked; that is not a contradiction.)"
        fi ;;
    esac
  fi

  # (e) THE PLAN — the numbered task count.
  _ntasks=unknown
  if [ -n "$_kplan" ] && sr_path_ok "$_kplan"; then
    _plantxt=$(sr_show "$_kplan")
    if [ -n "$_plantxt" ]; then
      _ntasks=$(printf '%s\n' "$_plantxt" | grep -cE '^[0-9]+\. ' || true)
      [ "$_ntasks" -gt 0 ] 2>/dev/null || _ntasks=unknown
    fi
  fi
  echo ""
  echo "plan:         ${_kplan:-none} (numbered tasks: $_ntasks)"

  # (f) THE REVIEW RECORD — last round verdict + sha, security rounds, and the ungraded Task status.
  _lastverdict=none; _lastsha=""; _secline=unknown; _pending=""; _ndone=0; _npending=0
  if [ -n "$_kreview" ] && sr_path_ok "$_kreview"; then
    _rectxt=$(sr_show "$_kreview")
    if [ -n "$_rectxt" ]; then
      _rounds=$(printf '%s\n' "$_rectxt" \
        | awk '/^## Rounds/{r=1;next} r && /^## /{r=0} r && /^\|/ {print}' \
        | grep -E 'APPROVE|NEEDS-FIXES' || true)
      if [ -n "$_rounds" ]; then
        _lastrow=$(printf '%s\n' "$_rounds" | tail -1)
        case "$_lastrow" in
          *NEEDS-FIXES*) _lastverdict=NEEDS-FIXES ;;
          *APPROVE*)     _lastverdict=APPROVE ;;
        esac
        _lastsha=$(printf '%s' "$_lastrow" | awk -F'|' '{v=$2; gsub(/^[ \t`]+|[ \t`]+$/,"",v); print v}')
      fi
      _secline=$(printf '%s\n' "$_rectxt" | sed -n 's/^ran — seat /ran — seat /p' | head -1)
      [ -n "$_secline" ] || _secline=unknown
      _tasks=$(printf '%s\n' "$_rectxt" \
        | awk '/^## Task status/{t=1;next} t && /^## /{t=0} t && /^\|/ {print}' || true)
      _ndone=$(printf '%s\n' "$_tasks" | grep -c '| *done *|' || true)
      _npending=$(printf '%s\n' "$_tasks" | grep -c '| *pending *|' || true)
      _pending=$(printf '%s\n' "$_tasks" | grep '| *pending *|' | head -1 \
        | awk -F'|' '{v=$2; gsub(/^[ \t]+|[ \t]+$/,"",v); print v}')
    fi
  fi
  echo "review record: ${_kreview:-none} — last round: $_lastverdict${_lastsha:+ at $_lastsha}"
  echo "  security:   $_secline"
  echo "  task status: $_ndone done, $_npending pending"

  # (g) THE BOARD ROW, on the branch itself.
  _board=$(sr_show BACKLOG.md)
  _section=unknown
  if [ -n "$_board" ]; then
    _btmp=$(mktemp); printf '%s\n' "$_board" > "$_btmp"
    for _s in "Ready" "In Progress" "In Review" "Blocked" "Released" "Done"; do
      if awk -v sec="$_s" -v want="$_row" '
            /^[[:space:]]*```/ { inf = !inf; next } inf { next }
            $0 ~ "^## " sec "[[:space:]]*$" { ins = 1; next }
            ins && /^## / { ins = 0 }
            ins && $0 ~ "`" want "`" { f = 1 }
            END { exit !f }' "$_btmp"; then
        _section=$_s; break
      fi
    done
    rm -f "$_btmp"
  fi
  echo "board:        \`$_row\` sits in '$_section' on $_branch"

  # THE PR STATE — optional, read-only, `--head=` form so the branch is one token.
  _pr=unknown
  if command -v gh >/dev/null 2>&1; then
    if _prs=$(gh pr list --head="$_branch" --state all --json state --jq '.[].state' 2>/dev/null); then
      if printf '%s\n' "$_prs" | grep -q '^OPEN$';        then _pr=OPEN
      elif printf '%s\n' "$_prs" | grep -q '^MERGED$';    then _pr=MERGED
      elif printf '%s\n' "$_prs" | grep -q '^CLOSED$';    then _pr=CLOSED
      elif [ -z "$_prs" ];                                then _pr=none
      fi
    fi
  fi
  echo "pr:           $_pr"

  # ── THE NEXT-STEP TABLE — FIRST MATCH WINS, and `unknown` always falls through to the more
  # conservative row. This is a fixed table, not a judgment: it names the most conservative act
  # consistent with what is readable, and the conductor decides.
  echo ""
  if [ -z "$_kplan" ] && [ "$_golabel" = unknown ]; then
    echo "NEXT STEP:    design gate — write or confirm the design, and obtain the owner GO."
  elif [ -z "$_kplan" ]; then
    echo "NEXT STEP:    plan — the design GO is recorded; write the plan and name it in Kit-Plan."
  elif [ -z "$_kreview" ]; then
    echo "NEXT STEP:    build: task 1 of $_ntasks."
  elif [ -n "$_pending" ]; then
    echo "NEXT STEP:    build: $_pending"
  elif [ "$_lastverdict" = NEEDS-FIXES ]; then
    echo "NEXT STEP:    fix round at ${_lastsha:-the last reviewed commit}."
  elif [ "$_lastverdict" = APPROVE ] && [ "$_pr" != OPEN ] && [ "$_pr" != MERGED ]; then
    echo "NEXT STEP:    pre-push battery, then push / open the PR."
  elif [ "$_pr" = OPEN ]; then
    echo "NEXT STEP:    await the owner's Approve, then land."
  elif [ "$_pr" = MERGED ]; then
    echo "NEXT STEP:    closed — release the claim (it should already be gone)."
  else
    echo "NEXT STEP:    build: task 1 of $_ntasks (nothing readable says otherwise)."
  fi
  echo ""
  echo "re-take:      sh scripts/board-claim.sh claim $_row --branch $_branch --board-already-moved"
  echo "              (this verb wrote nothing: no claim, no checkout, no file)"
  return 0
}

# ── ORACLE MARKER: selftest() and everything below is the non-vacuity oracle region. ─────────────
selftest() {
  sr_fail=0
  sr_base=$(mktemp -d)
  HOME="$sr_base/home"; mkdir -p "$HOME"; export HOME
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
  unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL 2>/dev/null || true
  sr_remote="$sr_base/remote.git"
  git init -q --bare "$sr_remote"
  git clone -q "$sr_remote" "$sr_base/A" 2>/dev/null
  ( cd "$sr_base/A"
    git config user.name "Session A"; git config user.email a@example.com
    git config commit.gpgsign false )
  sr_fixture_board "$sr_base/A/BACKLOG.md"
  mkdir -p "$sr_base/A/docs/plans" "$sr_base/A/docs/reviews"
  sr_fixture_plan "$sr_base/A/docs/plans/p.md"
  ( cd "$sr_base/A" && git add -A >/dev/null 2>&1 && git commit -q -m "base" >/dev/null 2>&1 \
      && git push -q origin HEAD:refs/heads/main >/dev/null 2>&1 )
  git --git-dir="$sr_remote" symbolic-ref HEAD refs/heads/main

  # ---- resume/no-claim — table row 1. Nothing holds the row: it is not parked, it is unheld. -----
  sr_run "$sr_base/A" ROW-1
  sr_expect_rc 1 "leg resume/no-claim: a row with no claim -> rc 1, never a silent 0"
  sr_has "leg resume/no-claim: the next step is to claim it" "not parked — claim it"

  # ---- resume/branch-absent — table row 2. The claim names a branch origin has never seen. -------
  sr_mkclaim ROW-1 feat/never-pushed
  sr_run "$sr_base/A" ROW-1
  sr_expect_rc 0 "leg resume/branch-absent: a claim whose branch is not on origin -> rc 0"
  sr_has "leg resume/branch-absent: the branch is reported ABSENT" "ABSENT on"
  sr_has "leg resume/branch-absent: the next step says there is nothing to resume from origin" "nothing to resume from origin"
  # …and it must NOT suggest reclaiming the row (fix round 1, H2): a branch that has not reached
  # origin is the normal mid-build state, not evidence of a dead holder.
  sr_hasnt "leg resume/branch-absent: NO --stale suggestion is printed for an unpushed branch" "--stale"
  sr_has "leg resume/branch-absent: it says why an absent branch is not evidence" "Ask; do not reclaim"
  sr_rmclaim ROW-1

  # ---- resume/design-gate — table row 3. A branch with no Kit-Plan and no design GO. -------------
  sr_mkbranch feat/slice "no trailers yet" ""
  sr_mkclaim ROW-1 feat/slice
  sr_run "$sr_base/A" ROW-1
  sr_expect_rc 0 "leg resume/design-gate: a pushed branch with no plan and no GO -> rc 0"
  sr_has "leg resume/design-gate: the next step is the design gate" "design gate"
  sr_has "leg resume/design-gate: the claim's holder is named" "Session A <a@example.com>"

  # ---- resume/plan — table row 4. A design GO exists; no Kit-Plan yet. ---------------------------
  sr_mknote feat/slice '[committer] Owner'
  sr_run "$sr_base/A" ROW-1
  sr_has "leg resume/plan: with a GO and no plan the next step is to plan" "NEXT STEP:    plan"

  # ---- resume/label-verbatim — the GO label byte-for-byte, the note's OWN committer, and the
  #      sentence that says what the pair is worth [sec-7]. A drift control, never authentication.
  sr_has "leg resume/label-verbatim: the assurance label is printed VERBATIM" "[committer] Owner"
  sr_has "leg resume/label-verbatim: the note's own committer is printed beside it" "note committer: Session A <a@example.com>"
  sr_has "leg resume/label-verbatim: …under the sentence that says it is not re-derived" "as recorded, not re-derived"

  # ---- resume/build-task-1 — table row 5. A plan, no review record: start at task 1 of N. --------
  sr_mkbranch feat/slice "plan trailer" "Kit-Plan: docs/plans/p.md"
  sr_run "$sr_base/A" ROW-1
  sr_has "leg resume/build-task-1: the next step is task 1 of the plan's own task count" "build: task 1 of 3"

  # ---- resume/build-pending — table row 6. The record's ungraded Task status names a pending task.
  sr_fixture_record "$sr_base/A/docs/reviews/r.md" APPROVE 'abc1234' pending
  sr_mkbranch feat/slice "record trailer" "Kit-Plan: docs/plans/p.md
Kit-Review: docs/reviews/r.md"
  sr_run "$sr_base/A" ROW-1
  sr_has "leg resume/build-pending: the pending task from the record is the next step" "build: 2. the pending one"
  sr_has "leg resume/build-pending: the done/pending counts are rendered" "1 done, 1 pending"

  # ---- resume/fix-round — table row 7. The last round is NEEDS-FIXES. ---------------------------
  sr_fixture_record "$sr_base/A/docs/reviews/r.md" NEEDS-FIXES 'def5678' none
  sr_mkbranch feat/slice "needs-fixes record" "Kit-Plan: docs/plans/p.md
Kit-Review: docs/reviews/r.md"
  sr_run "$sr_base/A" ROW-1
  sr_has "leg resume/fix-round: the next step is a fix round at the last reviewed sha" "fix round at def5678"

  # ---- resume/pre-push — table row 8. APPROVE, and no PR is readable (no gh in the fixture). -----
  sr_fixture_record "$sr_base/A/docs/reviews/r.md" APPROVE 'abc1234' none
  sr_mkbranch feat/slice "approved record" "Kit-Plan: docs/plans/p.md
Kit-Review: docs/reviews/r.md"
  sr_run "$sr_base/A" ROW-1
  sr_has "leg resume/pre-push: an APPROVE with no open PR -> the pre-push battery" "pre-push battery, then push"

  # ---- resume/pr-open + resume/pr-merged — table rows 9 and 10, through a STUB gh. --------------
  mkdir -p "$sr_base/ghstub"
  sr_ghstub OPEN
  sr_run_gh "$sr_base/A" ROW-1
  sr_has "leg resume/pr-open: an OPEN PR -> await the owner's Approve" "await the owner's Approve"
  sr_ghstub MERGED
  sr_run_gh "$sr_base/A" ROW-1
  sr_has "leg resume/pr-merged: a MERGED PR -> the slice is closed, release the claim" "closed — release the claim"

  # ---- resume/argv-safe — A PLANTED CLAIM AND A PLANTED TRAILER ARE REFUSED BEFORE ANY GIT CALL --
  # [sec-2] Both values become arguments: the branch to `git fetch`/`gh`, the plan path to
  # `git show`. A CLAIM is written by whoever holds the ref and a trailer by whoever pushed the
  # branch — neither is trusted, and the refusal must come BEFORE the call, not after it.
  sr_rmclaim ROW-1
  sr_mkclaim_raw ROW-1 '--upload-pack=touch /tmp/pwned'
  sr_run "$sr_base/A" ROW-1
  sr_expect_rc 2 "leg resume/argv-safe: a CLAIM whose branch is an option string -> rc 2 (refused)"
  sr_hasnt "leg resume/argv-safe: the option string is never handed onward" "upload-pack=touch"
  if [ -e /tmp/pwned ]; then
    sr_fail "leg resume/argv-safe: /tmp/pwned EXISTS — the planted branch value was executed"
    rm -f /tmp/pwned
  else
    sr_pass "leg resume/argv-safe: nothing was executed (the planted upload-pack never ran)"
  fi
  sr_rmclaim ROW-1
  sr_mkbranch feat/slice "traversal trailer" "Kit-Plan: ../../../etc/passwd"
  sr_mkclaim ROW-1 feat/slice
  sr_run "$sr_base/A" ROW-1
  sr_expect_rc 0 "leg resume/argv-safe: a traversing Kit-Plan path does not crash the verb"
  sr_has "leg resume/argv-safe: a traversing path is reported as an unreadable task count" "numbered tasks: unknown"

  # ---- resume/argv-safe (M5): THE STATE FILE THIS VERB READS IS ALSO A PLANT SURFACE ------------
  # `.kit-run/session.id` is not control-plane to the guard, so anyone can plant one — and a FIFO
  # there HANGS this verb forever, which is a denial of service on the ONE command a stuck session
  # runs first. Same predicate as `bc_session_read`, applied BEFORE any open. The DIFFERENCE from
  # the write verb is the rule for the read-only twins and is asserted here: `claim` REFUSES rc 2;
  # `resume` DEGRADES to `unknown`, NAMES the path and the reason, and still renders the slice.
  sr_mkclaim ROW-1 feat/slice
  mkdir -p "$sr_base/A/.kit-run"
  printf 'plaintext\n' > "$sr_base/A/victim"
  rm -f "$sr_base/A/.kit-run/session.id"
  ln -s "$sr_base/A/victim" "$sr_base/A/.kit-run/session.id"
  sr_run "$sr_base/A" ROW-1
  sr_expect_rc 0 "leg resume/argv-safe: a SYMLINKED session.id degrades, it does not refuse the verb"
  sr_has "leg resume/argv-safe: the degradation NAMES the path and the reason" "session.id: is a symlink"
  sr_has "leg resume/argv-safe: …and the slice is still rendered" "NEXT STEP:"
  rm -f "$sr_base/A/.kit-run/session.id"
  if mkfifo "$sr_base/A/.kit-run/session.id" 2>/dev/null; then
    # THE HANG FIXTURE. Without the `-p` test this run never returns; the leg is the proof that it
    # does. (A bounded external timeout is not available portably here, so the honest guarantee is
    # that this leg completing at all IS the assertion.)
    sr_run "$sr_base/A" ROW-1
    sr_expect_rc 0 "leg resume/argv-safe: a FIFO session.id does not HANG the cold-start verb"
    sr_has "leg resume/argv-safe: the FIFO is named as a FIFO" "is a FIFO"
    rm -f "$sr_base/A/.kit-run/session.id"
  else
    sr_fail "leg resume/argv-safe: could not build the FIFO fixture (the hang leg measured nothing)"
  fi
  printf 'evil; rm -rf /\n' > "$sr_base/A/.kit-run/session.id"
  sr_run "$sr_base/A" ROW-1
  sr_has "leg resume/argv-safe: an out-of-grammar session.id degrades, naming why" "not [A-Za-z0-9._-]{1,64}"
  sr_hasnt "leg resume/argv-safe: the malformed value is never echoed as a session" "evil;"
  rm -f "$sr_base/A/.kit-run/session.id"
  sr_rmclaim ROW-1

  # ---- resume/read-only — NOTHING CHANGED. The whole fixture is hashed before and after a full
  #      run: no ref, no file, no board. This is the property the verb's entire contract rests on.
  sr_mkbranch feat/slice "clean" "Kit-Plan: docs/plans/p.md"
  sr_before=$(sr_hash_fixture)
  sr_run "$sr_base/A" ROW-1
  sr_after=$(sr_hash_fixture)
  if [ "$sr_before" = "$sr_after" ]; then
    sr_pass "leg resume/read-only: a full run changed NO ref and NO file in the fixture"
  else
    sr_fail "leg resume/read-only: the fixture CHANGED across a run (before=$sr_before after=$sr_after)"
  fi
  # …and the scratch refs it fetched into are gone with it.
  if [ -z "$(git -C "$sr_base/A" for-each-ref 'refs/kit-scratch/*' 2>/dev/null)" ]; then
    sr_pass "leg resume/read-only: every scratch ref is dropped by the EXIT trap"
  else
    sr_fail "leg resume/read-only: a refs/kit-scratch/* ref survived the run"
  fi

  # ---- usage + grammar refusals --------------------------------------------------------------
  sr_run "$sr_base/A" 'row-1'
  sr_expect_rc 2 "leg resume/argv-safe: a lowercase row id is refused by grammar"
  sr_run "$sr_base/A"
  sr_expect_rc 2 "leg resume/argv-safe: no row id at all is a usage refusal"

  if [ "$sr_fail" -ne 0 ]; then
    echo "slice-resume --selftest: FAIL" >&2
    return 1
  fi
  echo "slice-resume --selftest: OK (fixtures under $sr_base, removed by the EXIT trap)"
  return 0
}

# --- selftest-only helpers, BELOW the marker so the mutation harness cannot neuter the oracle ----
sr_pass() { echo "selftest PASS: $1"; }
sr_fail() { echo "selftest FAIL: $1"; sr_fail=1; }

sr_fixture_board() {
  cat > "$1" <<'SR_BOARD_EOF'
# Fixture — Backlog

## Ready

| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links | Success metric / hypothesis |
|------|--------------|---------------------|------|------|------|-------|-------|-----------------------------|
| `ROW-1` — the claimable row | because | it is claimed | S | low | feature | agent | — | a claim serializes |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
SR_BOARD_EOF
}

sr_fixture_plan() {
  cat > "$1" <<'SR_PLAN_EOF'
# Plan — fixture

## Task list
1. **The first task** — do a thing.
2. **The pending one** — do another thing.
3. **The third** — and a third.
SR_PLAN_EOF
}

# sr_fixture_record <path> <verdict> <sha> <pending|none> — a review record in the graded shape,
# plus (or minus) the ungraded `## Task status` table this verb reads.
sr_fixture_record() {
  cat > "$1" <<SR_REC_EOF
# Review Record — fixture

## Rounds

| commit | reviewer seat | verdict (APPROVE\|NEEDS-FIXES) | findings (n) |
|---|---|---|---|
| $3 | reviewer | $2 | 0 |

## Security review

ran — seat Opus 5, verdict: no findings
SR_REC_EOF
  if [ "$4" = pending ]; then
    cat >> "$1" <<'SR_REC_TASKS_EOF'

## Task status

| task (from the plan) | state (`done` | `pending`) | commit |
|---|---|---|---|
| 1. the first task | done | abc1234 |
| 2. the pending one | pending | — |
SR_REC_TASKS_EOF
  fi
}

# sr_mkbranch <branch> <message> <trailers> — commit the fixture tree and push it to the branch.
sr_mkbranch() {
  (
    cd "$sr_base/A" || exit 1
    git add -A >/dev/null 2>&1 || true
    if [ -n "$3" ]; then
      printf '%s\n\n%s\n' "$2" "$3" > "$sr_base/cmsg.txt"
    else
      printf '%s\n' "$2" > "$sr_base/cmsg.txt"
    fi
    git commit -q --allow-empty -F "$sr_base/cmsg.txt" >/dev/null 2>&1
    git push -q -f origin "HEAD:refs/heads/$1" >/dev/null 2>&1
  )
}

# sr_mkclaim <row> <branch> — a real claim ref on the bare remote, in the shipped CLAIM shape.
sr_mkclaim() {
  sr_mkclaim_raw "$1" "$2"
}
sr_mkclaim_raw() {
  (
    cd "$sr_base/A" || exit 1
    _b=$(printf 'row: %s\nclaimant: Session A <a@example.com>\nbranch: %s\nclaimed-at: 2026-09-16T00:00:00Z\nsession: s-20260916-11112222 (declared)\n' "$1" "$2" | git hash-object -w --stdin)
    _t=$(printf '100644 blob %s\tCLAIM\n' "$_b" | git mktree)
    _c=$(printf 'claim %s\n' "$1" | git commit-tree "$_t")
    git push -q -f origin "$_c:refs/claims/$1"
  )
}
sr_rmclaim() { git --git-dir="$sr_remote" update-ref -d "refs/claims/$1" 2>/dev/null || true; }

# sr_mknote <branch> <label> — a design GO note on the fixture's own ledger, pushed to the remote.
sr_mknote() {
  (
    cd "$sr_base/A" || exit 1
    _sha=$(git rev-parse HEAD)
    printf 'gate: design\nscope: branch/%s\napproved-by: %s\napproved-sha: %s\nkit-row: ROW-1\n' \
      "$1" "$2" "$_sha" > "$sr_base/note.txt"
    git notes --ref=promotions add -f -F "$sr_base/note.txt" "$_sha" >/dev/null 2>&1
    git push -q -f origin refs/notes/promotions >/dev/null 2>&1
  )
}

# sr_ghstub <state> — a stub `gh` whose `pr` subcommand prints one PR state. Never the real forge.
sr_ghstub() {
  printf '%s\n' "$1" > "$sr_base/ghstub/state"
  cat > "$sr_base/ghstub/gh" <<'SR_GH_EOF'
#!/bin/sh
case "$1" in
  pr) cat "$(dirname "$0")/state" ;;
  *)  exit 1 ;;
esac
SR_GH_EOF
  chmod +x "$sr_base/ghstub/gh"
}

# sr_hash_fixture — every ref on the remote plus every tracked file's hash, as one string. The
# read-only leg compares this across a full run; anything the verb wrote would move it.
sr_hash_fixture() {
  {
    git --git-dir="$sr_remote" for-each-ref --format='%(refname) %(objectname)'
    ( cd "$sr_base/A" && find . -type f -not -path './.git/*' | sort | while IFS= read -r _f; do
        printf '%s %s\n' "$_f" "$(git hash-object "$_f")"
      done )
  } | git hash-object --stdin
}

sr_run() { # <clone-dir> [args…]
  _d=$1; shift
  if sr_out=$( cd "$_d" && sh "$SR_SELF" "$@" 2>&1 ); then sr_rc=0; else sr_rc=$?; fi
}
sr_run_gh() {
  _d=$1; shift
  if sr_out=$( cd "$_d" && PATH="$sr_base/ghstub:$PATH" sh "$SR_SELF" "$@" 2>&1 ); then sr_rc=0; else sr_rc=$?; fi
}
sr_expect_rc() {
  if [ "$sr_rc" -eq "$1" ]; then sr_pass "$2"
  else sr_fail "$2 (rc=$sr_rc, wanted $1); out=[$sr_out]"; fi
}
sr_has() {
  case "$sr_out" in
    *"$2"*) sr_pass "$1" ;;
    *) sr_fail "$1 (output does not carry '$2'); out=[$sr_out]" ;;
  esac
}
sr_hasnt() {
  case "$sr_out" in
    *"$2"*) sr_fail "$1 (output wrongly carries '$2'); out=[$sr_out]" ;;
    *) sr_pass "$1" ;;
  esac
}

sr_cmd="${1:-}"
case "$sr_cmd" in
  --selftest) if selftest; then sr_rc_main=0; else sr_rc_main=$?; fi ;;
  -h|--help)  sr_usage; sr_rc_main=2 ;;
  *)          if do_resume "$@"; then sr_rc_main=0; else sr_rc_main=$?; fi ;;
esac
exit "$sr_rc_main"
