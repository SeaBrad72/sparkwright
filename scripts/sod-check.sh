#!/bin/sh
# sod-check.sh — neutral separation-of-duties gate (the FLOOR; forge-agnostic).
# PASS iff at least one approver identity is distinct from the PR/MR author AND from
# every commit-author — i.e. a ratifier exists who did not author the work. Pure
# identity-set comparison; NO forge-specific code. A per-forge adapter (e.g.
# docs/operations/sod-gate.github.yml, or GitLab native approval rules) supplies inputs.
#   Inputs (env; identities space/newline-separated; normalized: trimmed + case-folded;
#           each token is ONE identity — embedded spaces are reinterpreted as separators):
#     SOD_AUTHOR          the PR/MR author identity (required)
#     SOD_APPROVERS       approving-reviewer identities
#     SOD_COMMIT_AUTHORS  commit-author identities on the branch
#   exit 0 — PASS (a distinct ratifier exists)
#   exit 1 — FAIL (no distinct ratifier) OR unverifiable under CI/--require (fail-closed)
#   exit 2 — UNVERIFIED (inputs absent) when NOT under CI/--require — NOT a pass.
# Honest ceiling: this proves the IDENTITY logic. Server-side enforcement is the adopter's
# branch-protection / forge approval rules; the ratifying identity must be one the building
# agent cannot assume. See docs/operations/separation-of-duties.md.
#   usage: sh scripts/sod-check.sh [--require] | --seat-approvals | --selftest
# SECOND MODE — `--seat-approvals` (A5, `D-240825-1`; the SENTENCE RULE was RETIRED 2026-08-28):
# DETECT whether a declared RATIFICATION SEAT is among the approvers, BY LOGIN. Same file because it
# is the same question one level down — who ratified, and on what standing. It reports; it does not
# grade. The approval BODY is never read (see the retirement note above seat_approvals() below).
# What it changes: Read-only — pure identity-set comparison (author vs approvers vs commit-authors), plus seat DETECTION by login; mutates nothing.
# Guardrails: exit 0 only when a distinct ratifier exists; fail-closed (exit 1) when unverifiable under CI/--require; exit 2 (UNVERIFIED, NOT a pass) when inputs are absent off-CI; proves the logic only — server-side enforcement is the adopter's branch protection.
set -eu

REQUIRE="${REQUIRE:-0}"
[ -n "${CI:-}" ] && REQUIRE=1
for a in "$@"; do
  case "$a" in
    --require) REQUIRE=1 ;;
    --selftest) ;;    # dispatched below
    --seat-approvals) ;; # dispatched below
    --seat-bodies) ;;    # DEPRECATED ALIAS of --seat-approvals; dispatched below
    -*) echo "usage: sod-check.sh [--require] | --seat-approvals | --selftest" >&2; exit 2 ;;
  esac
done

# normalize a blob of identities -> one lowercased, trimmed, de-duped identity per line.
norm() {
  printf '%s' "$1" | tr ' \t' '\n' | tr '[:upper:]' '[:lower:]' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | sort -u || true
}

# decide: prints the verdict and EXITS with the status (mirrors branch-protection.sh's
# classify() — exit-in-function so the run path terminates; selftest calls it in a subshell).
decide() {
  author=$(norm "${SOD_AUTHOR:-}")
  approvers=$(norm "${SOD_APPROVERS:-}")
  commit_authors=$(norm "${SOD_COMMIT_AUTHORS:-}")
  if [ -z "$author" ] || [ -z "$approvers" ]; then
    if [ "$REQUIRE" = "1" ]; then
      echo "FAIL: separation-of-duties unverifiable (missing author or approvers) and verification is required (CI/--require)."
      exit 1
    fi
    echo "UNVERIFIED: supply SOD_AUTHOR + SOD_APPROVERS. (NOT a pass.)"
    exit 2
  fi
  # excluded = the author plus everyone who committed (a code author cannot be the sole ratifier).
  excluded=$(printf '%s\n%s\n' "$author" "$commit_authors" | grep -v '^$' | sort -u || true)
  # A distinct ratifier = an approver in NONE of the excluded identities. Compared with grep -x -F
  # (whole-line, FIXED strings): identities match LITERALLY — never as a glob or regex, never
  # word-split — so a token like '*' or 'a.b' is a literal identity and the verdict can NEVER depend
  # on the working directory. -F takes the newline-separated excluded set as multiple fixed patterns.
  ratifier=$(printf '%s\n' "$approvers" | grep -vxF -- "$excluded" | head -n 1 || true)
  if [ -n "$ratifier" ]; then
    echo "OK: separation-of-duties satisfied — '$ratifier' ratified work it did not author."
    exit 0
  fi
  echo "FAIL: no approver is distinct from the author and all commit-authors — author cannot ratify own work."
  exit 1
}

# ── --seat-approvals: the RATIFICATION-SEAT mode (A5, `D-240825-1`) ─────────────────────────────────
# A DIFFERENT question from decide()'s. decide() asks whether a distinct ratifier EXISTS. This mode
# asks WHICH of the approvers is a declared ratification SEAT — an account that is the maintainer's
# own second identity, declared in .kit/ratification-seats.conf.
#
# WHY IT EXISTS. On a solo repo the second identity satisfies decide() perfectly while providing no
# second person. That is not a fake control: the seat enforces `agent ≠ ratifier`, because the
# building agent cannot mint that approval, and that property is friction-test-real. What it is NOT is
# two-person review. The 2026-08-25 evaluation found 8/8 recent merged PRs with author = merger and
# the seat as sole approver, against docs saying that does not satisfy SoD. The ruling reclassified
# the seat rather than retiring it, and this mode is how the reclassification travels with each PR.
#
# ── THE SENTENCE RULE IS RETIRED (owner ruling, 2026-08-28). This mode used to read the approval BODY
# and require the phrase "Ratification seat" in it, failing the check when it was absent. That graded
# a human's typing, not the change: the disclosure is derivable from the LOGIN, which the forge
# supplies and which no body text can make truer, so demanding it be retyped added a way to be wrong
# and no way to be safer. The caller now DERIVES the disclosure from this mode's output and prints it
# as a ::notice. The body is not read at all — there is no phrase to match, and no FAIL path for a
# missing sentence.
#
# ── HONEST CEILING, STATED FIRST. THIS DETECTS AN IDENTITY. It does not prove a human read the diff.
# Its whole value is that the PR page cannot silently read as an independent second approval — the
# disclosure is emitted beside the approval instead of living in a doc nobody opens. Do not quote a
# zero exit here as "separation of duties satisfied"; it is the opposite claim, recorded.
#
# EXIT 1 MEANS "NO SEAT APPROVED", NOT "SOMETHING IS WRONG". A PR with no approvals at all, or
# approvals only from non-seat accounts, is the ordinary case and exits 1 — the caller's cue to print
# nothing. Grading presence is decide()'s job and the forge's; this mode has no opinion on it.
#   Inputs (env): SOD_SEATS      space/newline-separated seat logins (case-folded)
#                 SOD_APPROVALS  one approval per line: <login>[<TAB><body>]  (the body is IGNORED)
#   stdout — the declared seat login(s) that approved, one per line
#   exit 0 — at least one declared seat approved · 1 — none did.
SOD_TAB=$(printf '\t')

seat_approvals() {
  _seats=$(norm "${SOD_SEATS:-}")
  if [ -z "$_seats" ]; then
    echo "none: seat-approvals — no ratification seats declared (SOD_SEATS empty)."
    return 1
  fi
  _seen=0
  while IFS= read -r _ln || [ -n "$_ln" ]; do
    [ -n "$_ln" ] || continue
    # The BODY is deliberately not extracted: since the sentence rule was retired there is nothing in
    # it this mode reads. The <TAB><body> shape stays in the input contract so the caller's jq
    # projection is unchanged (and so a future mode can use it without a caller change).
    _login=${_ln%%"$SOD_TAB"*}
    _login=$(printf '%s' "$_login" | tr '[:upper:]' '[:lower:]' \
      | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$_login" ] || continue
    # -xF: a seat login is a LITERAL whole-line identity, never a glob or a regex — the same rule
    # decide() applies, for the same reason (a login is data, and data must not become a pattern).
    printf '%s\n' "$_seats" | grep -qxF -- "$_login" || continue
    _seen=$((_seen + 1))
    # THE OUTPUT IS THE LOGIN, BARE, one per line — the caller renders the disclosure prose around it.
    printf '%s\n' "$_login"
  done <<SOD_APPROVALS_EOF
${SOD_APPROVALS:-}
SOD_APPROVALS_EOF
  if [ "$_seen" = 0 ]; then
    echo "none: seat-approvals — no approval from a declared seat on this change."
    return 1
  fi
  return 0
}

selftest() {
  st=0
  chk() {  # expect author approvers commit_authors require label
    e=$1; a=$2; ap=$3; ca=$4; req=$5; lbl=$6
    ( SOD_AUTHOR="$a"; SOD_APPROVERS="$ap"; SOD_COMMIT_AUTHORS="$ca"; REQUIRE="$req"; decide ) >/dev/null 2>&1 && g=0 || g=$?
    if [ "$g" = "$e" ]; then echo "selftest PASS: $lbl -> exit $g"; else echo "selftest FAIL: $lbl want $e got $g"; st=1; fi
  }
  chk 0 'agent-bot' 'alice'             'agent-bot'      0 "distinct approver"
  chk 1 'alice'     'alice'             'alice'          0 "author-only approves"
  chk 1 'agent-bot' 'bob'               'agent-bot bob'  0 "approver also committed"
  chk 2 'agent-bot' ''                  'agent-bot'      0 "no approvals (no CI) -> UNVERIFIED"
  chk 1 'agent-bot' ''                  'agent-bot'      1 "no approvals + require -> FAIL"
  chk 0 'agent-bot' 'agent-bot alice'   'agent-bot'      0 "distinct + author also approved"
  chk 1 'Agent-Bot' 'agent-bot'         'Agent-Bot'      0 "casing normalized -> same identity FAIL"
  chk 1 '*'         '*'                 ''               0 "metachar identity compared literally (no glob)"
  chk 0 'a.ice'     'alice'             ''               0 "regex metachar in author is literal (grep -F), not a pattern"

  # ── --seat-approvals (A5, `D-240825-1`; sentence rule RETIRED 2026-08-28). A DIFFERENT question
  # from decide()'s: not "does a distinct ratifier exist" but "WHICH approver is a declared seat".
  # 0 = a seat approved (the caller prints the disclosure); 1 = none did (the caller prints nothing).
  # Neither is a verdict on the change — this mode reports, it does not grade.
  seat_chk() {  # expect seats approvals label
    e=$1; s=$2; ap=$3; lbl=$4
    ( SOD_SEATS="$s"; SOD_APPROVALS="$ap"; seat_approvals ) >/dev/null 2>&1 && g=0 || g=$?
    if [ "$g" = "$e" ]; then echo "selftest PASS: $lbl -> exit $g"; else echo "selftest FAIL: $lbl want $e got $g"; st=1; fi
  }
  _TAB=$(printf '\t')
  seat_chk 0 'isbrad72' "isbrad72${_TAB}Ratification seat — same human as the author." \
    "seat approval WITH the old sentence -> still DETECTED (the alias case)"
  # ★ THE RETIREMENT, ASSERTED. Under the old rule this exact input was the FAIL leg. It is now the
  # ordinary, expected shape of a seat approval: GitHub's approve button submits an empty body.
  seat_chk 0 'isbrad72' "isbrad72${_TAB}" \
    "seat approval with an EMPTY body -> DETECTED (the sentence rule is retired)"
  seat_chk 0 'isbrad72' "isbrad72" \
    "…and with NO tab at all (a bare login line) -> DETECTED"
  seat_chk 1 'isbrad72' "alice${_TAB}" \
    "NON-seat approval -> NOT a seat (exit 1: the caller prints nothing)"
  seat_chk 1 'isbrad72' "" \
    "no approvals at all -> no seat detected"
  seat_chk 1 '' "isbrad72${_TAB}lgtm" \
    "no seats DECLARED -> nothing can be a seat (an adopter with no seats file)"
  seat_chk 0 'ISBrad72' "isbrad72${_TAB}lgtm" \
    "seat login is case-folded, so a cased declaration still binds"
  seat_chk 1 'isbrad72' "isbrad7${_TAB}lgtm" \
    "a login that merely PREFIXES a seat is not that seat (whole-line -xF match)"
  ( SOD_SEATS='isbrad72'; SOD_APPROVALS="isbrad72${_TAB}"; seat_approvals ) 2>/dev/null \
    | grep -qxF "isbrad72" \
    && echo "selftest PASS: the detected seat LOGIN is printed bare, for the caller's disclosure" \
    || { echo "selftest FAIL: seat_approvals did not print the detected login"; st=1; }
  # THE BODY IS NOT READ, ASSERTED: a body that is itself a rival seat login must not be detected.
  ( SOD_SEATS='isbrad72'; SOD_APPROVALS="alice${_TAB}isbrad72"; seat_approvals ) >/dev/null 2>&1 \
    && { echo "selftest FAIL: a seat login appearing in the BODY was treated as a seat approval"; st=1; } \
    || echo "selftest PASS: the approval BODY is not read (a seat login in the body is not a seat approval)"

  [ "$st" = "0" ] && echo "sod-check --selftest: OK"
  return "$st"
}

case "${1:-}" in
  --selftest)       selftest;       exit $? ;;
  --seat-approvals) seat_approvals; exit $? ;;
  # DEPRECATED ALIAS (2026-08-28). `--seat-bodies` named the retired sentence rule. Kept so an
  # in-flight caller — notably a checked-out BASE tree whose workflow is newer than its scripts, the
  # version-skew case the ratification job is built around — does not fail on an unknown flag. It is
  # the SAME mode: detection by login, no body read.
  --seat-bodies)    echo "sod-check.sh: --seat-bodies is DEPRECATED — it is an alias of --seat-approvals (the seat SENTENCE rule was retired 2026-08-28; the body is not read)." >&2
                    seat_approvals; exit $? ;;
  *) decide ;;
esac
