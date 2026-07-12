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
#
#   log
#       -> render refs/notes/promotions as a human-readable trail (a PROJECTION of the notes,
#          not a second synced surface — replaces the retired docs/governance/promotion-log.md).
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
#   * `never-infer` — that the agent WAITED for an explicit recorded per-gate human GO — is FLOOR
#     discipline, NOT enforced by this tool. A green `check` proves what shipped carries the approved
#     SHA; it does NOT prove the agent's judgment or that it refused to infer.
# Control-plane stays human-actuated (bootstrap); this tool wires NON-control-plane promotions only.
#
# POSIX sh; dash-clean (no `local`, no bashisms). Operates on the current working tree's git repo.
# The notes ref name is overridable with PROMOTION_NOTES_REF (default: promotions) for testing.
# What it changes: `record` binds a GO record as a git NOTE under refs/notes/promotions (tree-invariant — the commit's tree/SHA is unchanged); `actuate` performs a real control-plane PR merge (default `gh pr merge --squash`, swappable via --merge-cmd) bound to the approved SHA; `log` and `check` are read-only.
# Guardrails: `check` asserts shipped==approved by TREE equality (exit 1 on MISMATCH); the approved-by assurance label is DERIVED from the commit's own evidence (never from input) — a note BINDS, it does not AUTHENTICATE. `actuate` fails CLOSED unless a SHA-bound [authenticated: <forge>-review] GO exists and approver != author, rejects `$ref` metacharacters, NEVER emits `--admin`, and re-verifies shipped==approved after the merge.
set -eu

NOTES_REF="${PROMOTION_NOTES_REF:-promotions}"

usage() {
  echo "usage:" >&2
  echo "  promotion-verify.sh record --approved-sha <sha> --approved-by <id> --gate <g> \\" >&2
  echo "                             --rung <r> --class <c> --scope <pr> --token <str> [--basis <t>]" >&2
  echo "  promotion-verify.sh log" >&2
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
  # Reject '[' or ']' ANYWHERE in --approved-by (S5a review): the assurance label is DERIVED below,
  # never supplied. A trailing-only strip left a mid-string "[signed: gpg]" decoy in the body that
  # could fool a substring grep — reject brackets outright instead.
  case "$aby" in
    *'['* | *']'*)
      echo "record: --approved-by must not contain '[' or ']' (assurance label is derived, not supplied) — rejected" >&2
      return 2 ;;
  esac
  [ -n "$basis" ] || basis="(none recorded)"
  # the approved-sha must resolve to a real commit before we bind a note to it.
  if ! git rev-parse -q --verify "${asha}^{commit}" >/dev/null 2>&1; then
    echo "record: approved-sha '$asha' is not a resolvable commit in this repo" >&2; return 2
  fi
  # The assurance label is DERIVED (below), never accepted from input. Brackets in --approved-by were
  # rejected above, so the id is the caller string verbatim — input can't manufacture assurance.
  aby_id="$aby"
  assurance="$(derive_assurance "$asha" "$aby_id")"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
  # Bind the structured record to the approved commit as a note (tree-invariant). `-f` overwrites a
  # prior note on the same commit (re-record supersedes) — honest: notes are mutable (see ceiling).
  if ! printf '%s\n' \
      "record: promotion GO (approve->execute->log)" \
      "approved-sha: $asha" \
      "approved-by: $aby_id [$assurance]" \
      "gate: $gate" \
      "rung: $rung" \
      "change-class: $cls" \
      "scope: $scope" \
      "approval-token: \"$token\"" \
      "basis: $basis" \
      "recorded-at: $ts" \
      | git notes --ref="$NOTES_REF" add -f -F - "$asha" >/dev/null 2>&1; then
    echo "record: failed to write note refs/notes/$NOTES_REF on $asha" >&2; return 2
  fi
  echo "OK: recorded approval for $scope (approved-sha $asha) -> note refs/notes/$NOTES_REF [$assurance]"
  echo "     share it: git push origin refs/notes/$NOTES_REF"
  return 0
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
      --ref)          ref="${2:-}";  shift 2 ;;
      --approved-sha) asha="${2:-}"; shift 2 ;;
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
    *'['*']') label="${aby_rest##*[}"; label="${label%]}" ;;
  esac
  if ! printf '%s' "$label" | grep -Eq '^authenticated: [A-Za-z0-9_-]+-review$'; then
    echo "ACTUATE REFUSED: assurance '$label' does not meet the control-plane bar ([authenticated: <forge>-review] required)" >&2
    return 1
  fi

  # 3. approver != author (builder != ratifier — real SoD teeth). The approver id is the text BEFORE
  #    the trailing ' [label]'. Strip from the SAME last '[' the label read used (not a
  #    space-prefixed '[') so a hand-crafted 'Name[label]' (no space) can't leave the bracket
  #    suffix in aby_id and slip the SoD check. Compare to the approved commit's author name AND email.
  aby_id="${aby_rest%[*}"
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
  check)   if do_check   "$@"; then rc=0; else rc=$?; fi ;;
  actuate) if do_actuate "$@"; then rc=0; else rc=$?; fi ;;
  -h|--help) usage; rc=2 ;;
  *) usage; rc=2 ;;
esac
exit "$rc"
