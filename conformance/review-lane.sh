#!/bin/sh
# Why this gate: docs/architecture/2026-09-04-loop-stage-artifact-gate-design.md
# Also: docs/architecture/2026-09-05-review-lane-waiting-is-green-design.md
# review-lane.sh — LOOP-STAGE-ARTIFACT-GATE: the PLAN and REVIEW stages must leave ARTIFACTS, and the
# review artifact must name a reviewer who is not the builder.
#
# ⚠️ THE ATTESTATION LEG IS GONE (`REVIEW-LANE-WAITING-IS-GREEN`, 2026-09-05). This script no longer
# reads the forge at all, in any mode. It grades ARTIFACTS — a property of the code, decided once per
# push — and exits 0 or 2. There is no waiting state left to colour, because there is nothing left in
# it that waits on a human.
#   WHY: the leg returned rc 1 (WAITING) until a non-author approval sat on the head. A CI job has no
#   yellow, so WAITING rendered RED, and nothing triggers on `pull_request_review`, so the Approve that
#   cleared it never re-ran the job — measured on three consecutive PRs (#644, #645, #646), each
#   cleared by a MANUAL re-run of a matrix that had already graded the tree once.
#   WHAT REPLACES IT: nothing here — the forge's own review requirement, which enforces the same three
#   properties server-side, on every merge attempt, with no run and no colour:
#     a non-author APPROVED review exists  ->  required_approving_review_count >= 1
#     the approval sits on THIS head       ->  dismiss_stale_reviews (a push dismisses prior approvals)
#     the approver did not write the head  ->  require_last_push_approval (supersedes the deleted
#                                              rl_role_swap login-vs-email heuristic, as a rule)
#   All three are asserted live by `conformance/branch-protection.sh` (the `branch-protection-live`
#   required context). THE SETTINGS ARE THE CONTROL; THIS CHECK IS THE EXPLANATION — drop any of them
#   and an unattested PR merges green. That dependency is declared, not hidden (`REQUIRED-CHECKS.md`).
#
# ⚠️ THIS FILE WAS A 23-LINE PRESENCE CHECK UNTIL 2026-09-04 and is now a RECORD GRADER. The presence
# legs are KEPT VERBATIM as one leg (rl_presence_leg) — they were never wrong, only insufficient: they
# proved the TEMPLATE ships, never that anyone instantiated it. Measured at design time: zero review
# records existed in this tree and the shipped template had never been instantiated.
#
# WHAT IT PROVES, AND WHAT IT DOES NOT (design section 5 — read before quoting a green).
#   PROVES: a plan file and a review record exist at the graded head, are tracked regular files, are
#   well-formed, name commits INSIDE this PR, name a Reviewer string that differs from the Builder
#   string, close every round, dispose of every finding, resolve every design-promised control to an
#   EXECUTABLE line, and carry a security-review verdict (or a waiver with all four D-240904-1
#   criteria). A design doc this change adds carries the twelve lens names under a Lens review heading
#   (presence, never content; DESIGN-SKILL-LENS-LIST).
#
#   ⚠️ THE REVIEWER TYPES NOTHING (owner ruling `D-240904-2`, 2026-09-04). Before that ruling the gate
#   required the approver to paste a typed attestation line (record path, its sha256, the head sha and
#   the security state) into the review body, and graded that line. It is STRUCK, with the stamp-
#   printing mode and the whole body-parsing arm.
#   The reason is the kit's own doctrine turned on itself: a typed line is AUTHOR-CONTROLLED TEXT. It
#   proved only that a human could copy a string a command printed for them — the ceremony was real,
#   the assurance was not — while making the approver's job a two-step ritual that a busy reviewer
#   would satisfy by pasting without reading, which is the very posture the row exists to end.
#   The keystroke that remains is a plain non-author Approve, and the forge — not this script — is
#   what binds it to the tree.
#
#   DOES NOT PROVE: that the reviewer read the diff, or the record, or that the findings are real, or
#   ANYTHING AT ALL ABOUT WHO APPROVED — since 2026-09-05 that is the forge's question, and this
#   script does not re-verify branch protection at runtime (the workflow token cannot read it;
#   `D-240828-1` (4)). What the gate buys is that "never reviewed" is RED: the record's own grading
#   (rules 2-7) refuses a PR with no record, a malformed one, or one whose reviewer is its builder.
#
# THE GRADER'S POSTURE (design 4.3, vet H4). In CI this script runs from the BASE tree, and everything
# it reads from the PR head is read AS AN OBJECT (`git ls-tree`, `git cat-file -p <head>:<path>`) —
# never a checkout. PR-head code therefore cannot alter the grader that judges it. Corollary, and it
# is disclosed rather than hidden: on the PR that INTRODUCES this grader the base tree still holds the
# 23-line presence check, so THAT PR CANNOT BE ITS OWN FIRST CI-GRADED RUN. It is graded by hand.
#
# HEAD-SIDE CONFINEMENT (design section 7, vet M4) — everything read from the head is DATA:
# trailer values are charset-bounded, prefix-bounded, `.md`-suffixed and traversal-free; the record
# blob must be mode 100644 (a symlink or a gitlink is refused); it must not carry the template's own
# "Copy into your project" marker sentence nor `___` placeholder residue; it is size-bounded; and C0
# bytes are stripped from anything that reaches a log or a step summary.
#
# EXIT CONTRACT — a two-value contract since `REVIEW-LANE-WAITING-IS-GREEN` (2026-09-05):
#     0  PASS, or N-A (the scope cut: an ORDINARY change-set that is also DOCS-ONLY owes nothing)
#     2  ANOMALY / REFUSAL — a missing, malformed, unreadable or self-reviewed RECORD (rules 2-7), or
#        a change-set the gate could not derive.
#   ⚠️ rc 1 IS RETIRED. It meant WAITING — "a human has not acted yet" — and it was the only rc this
#   gate could return that a CI job cannot render: a job has no yellow, so it showed RED and needed a
#   manual re-run to clear. Every property it waited on is now the forge's (see the block above). The
#   value is left UNUSED rather than recycled, so an old runner, an old workflow copy or a stale local
#   script that still branches on `rc == 1` finds nothing that produces it.
#   `--selftest` is NOT part of that contract: it returns 1 on a genuine suite failure.
#
# Usage:
#   sh conformance/review-lane.sh --pr <n> --head <sha> [--base-ref <ref>]   (the CI predicate)
#   sh conformance/review-lane.sh --pre-push                                 (operator, branch-keyed)
#   sh conformance/review-lane.sh --selftest
#   `--pr <n>` is still ACCEPTED and still validated, and nothing reads it: the CI call site and the
#   version-skew probe both key on the flag, and the number is what a future forge-side leg would need.
#   The two modes now grade the SAME question; they differ only in how the head and base are supplied.
#
# What it changes: nothing — read-only. Reads git objects and the working tree's shipped docs. IT
# READS NO FORGE STATE AND REQUIRES NO NETWORK, NO `gh` AND NO `jq`, in either mode — pinned by the
# `forge never read` selftest case, whose aborting `gh` stub must never be invoked.
set -eu
# shellcheck disable=SC1007 # `CDPATH= cd` clears CDPATH for this one command so a user's CDPATH cannot
# redirect the cd; the empty assignment is intentional, not a mistyped value.
DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

# The repository whose HEAD is graded. Production is this repo; selftest() points it at throwaway
# fixtures IN-PROCESS. Deliberately NOT environment-overridable (the banked OBLIGATION-TESTMODE-ENV-FLAG
# rule): a gate whose graded tree can be moved by an ambient variable grades nothing.
RL_REPO="$DIR"
# RECORD SIZE BOUND — 16 KB since 2026-09-04 (orchestrator design amendment; design §7, §10).
#
# ⚠️ IT WAS 8192, AND THAT NUMBER WAS BORROWED FROM THE WRONG THING. 8 KB is the STEP-SUMMARY RENDER
# precedent — the bound on how much text a gate may push into a GitHub summary before the forge drops
# it. This record is not rendered anywhere: it is a FILE, read as a git object, that must hold EVERY
# review round, every finding with its disposition, the design-promised-controls table and the security
# verdict. MEASURED on this gate's own record: 8171 bytes with ONE round recorded — a second round
# could not have fitted. A bound that refuses a record for carrying the second review is the gate
# refusing the very thing it exists to require, so the number now comes from the artifact's job rather
# than from an unrelated render limit.
# The head-side confinement argument is UNCHANGED and still holds at 16 KB: the point of a bound here is
# that an unbounded blob from the PR head must not be read into memory or into a log, not that records
# should be short. C0 stripping and the `grep -F` marker check are what actually confine the content.
RL_MAX_RECORD_BYTES=16384
# THE TEMPLATE MARKER, and its ceiling, stated (measured on this gate's own review record at the fix
# round): the match is a `grep -F` for the sentence anywhere in the file, so a record that legitimately
# QUOTES the marker while discussing it is refused exactly like an uncopied template. That is the blunt
# end of a blunt instrument and it is kept blunt on purpose — every narrowing (line position, "only
# outside code spans", pairing with a second template-only anchor) is a way for a real template to slip
# through, and the remedy for the false positive is one word of prose in the record.
RL_TEMPLATE_MARKER='Copy into your project'
RL_PLAN_PREFIX='docs/plans/'
RL_REVIEW_PREFIX='docs/reviews/'
# DESIGN-SKILL-LENS-LIST: the design docs this gate grades for lens PRESENCE, and the twelve lens names a
# `## Lens review` table must carry. Constants, not environment-overridable (the rule above): the list is
# the single copy in skills/design/SKILL.md, and the selftest copies that section so the two cannot drift.
RL_DESIGN_GLOB='docs/architecture/*-design.md'
RL_LENSES='Project principles
Friction
Software practice
Agentic practice
CI
DevOps and operations
Security, privacy and guardrails
Cost and size
Product
Design
Architecture
UX and accessibility'
# The four D-240904-1 waiver criteria, verbatim tokens. A security waiver must carry ALL FOUR — the
# design's test made literal, so "waived" can never be a bare word.
RL_WAIVER_CRITERIA='no-untrusted-input no-new-permission no-control-plane-surface no-operator-shell'
# THE STATE TOKENS ARE LINE-ANCHORED, NOT SUBSTRINGS, and that is a defect found and fixed during this
# build rather than shipped: a bare `grep 'ran'` matches `warranted`, `transparent`, `guarantee` — so a
# security section that said "no review was warranted" would have read as `ran` and been asked only for
# a verdict word. The token must open the line (optionally after a list bullet or `**`), and `waived`
# is anchored the same way so the two states cannot both match on prose.
RL_SEC_RAN_RE='^[[:space:]]*[-*]*[[:space:]]*(\*\*)?ran([^A-Za-z]|$)'
RL_SEC_WAIVED_RE='^[[:space:]]*[-*]*[[:space:]]*(\*\*)?waived([^A-Za-z]|$)'
# The only paths a commit AFTER the closing APPROVE round may touch (rule 3, vet H3). Without this the
# closed-round rule is unsatisfiable: the commit that appends the APPROVE row cannot cite its own sha.
RL_POST_APPROVE_PATHS="$RL_REVIEW_PREFIX $RL_PLAN_PREFIX BACKLOG.md"

# rl_safe — strip C0 + DEL before any head-controlled value reaches a log or the step summary
# (loop-state's measured rule: CR/LF alone still leaves ANSI/ESC log corruption reachable).
rl_safe() { LC_ALL=C printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177'; }

# ── LEG 0: the presence check this file used to BE. Kept whole. It reads $DIR (the tree the script
#    ships in), never $RL_REPO, so it asks the same question in the kit and in an adopter export while
#    the grading legs below are pointed at a fixture.
rl_presence_leg() {
  _rp=0
  _need()  { [ -e "$DIR/$1" ] || { echo "FAIL: missing $1"; _rp=1; }; }
  _grepq() { grep -qi "$2" "$DIR/$1" 2>/dev/null || { echo "FAIL: $1 missing '$2'"; _rp=1; }; }
  _need templates/REVIEW-RECORD-TEMPLATE.md
  _need templates/PLAN-RECORD-TEMPLATE.md
  _need docs/operations/review-lane.md
  _grepq docs/operations/review-lane.md 'High-risk'
  _grepq docs/operations/review-lane.md 'compensating'
  _grepq docs/operations/review-lane.md 'enforce_admins'
  _grepq templates/REVIEW-RECORD-TEMPLATE.md 'Acknowledgments'
  _grepq DEVELOPMENT-PROCESS.md 'review-lane'
  _grepq conformance/audit-evidence-checklist.md 'REVIEW-RECORD'
  return "$_rp"
}

# ── THE BASE. Same candidate-ladder SHAPE as ceremony-binding's containment_base: caller-first,
#    LOCAL READS ONLY (a merge gate that needs the network fails for the network's reasons), and an
#    unresolvable base is a DISCLOSED degradation, never a refusal. Prints merge-base(base, head).
rl_base() {   # $1 = graded head
  _rb_cands=""
  if [ -n "${_rl_base_ref:-}" ]; then
    case "$_rl_base_ref" in
      -*) return 1 ;;
    esac
    case "$_rl_base_ref" in
      ''|*[!A-Za-z0-9_.:/-]*) return 1 ;;
    esac
    _rb_cands="$_rl_base_ref origin/$_rl_base_ref refs/remotes/origin/$_rl_base_ref"
  else
    _rb_dh=$(git -C "$RL_REPO" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
    _rb_cands="$_rb_dh origin/main origin/master main master"
  fi
  # shellcheck disable=SC2086 # deliberate word-split; every element is a literal or charset-checked.
  for _rb_c in $_rb_cands; do
    [ -n "$_rb_c" ] || continue
    git -C "$RL_REPO" rev-parse -q --verify "$_rb_c^{commit}" >/dev/null 2>&1 || continue
    if _rb_mb=$(git -C "$RL_REPO" merge-base "$_rb_c" "$1" 2>/dev/null) && [ -n "$_rb_mb" ]; then
      printf '%s\n' "$_rb_mb"; return 0
    fi
  done
  return 1
}

# rl_changed — the change-set listing this gate classifies, written to $2. Cumulative base..head, which
# is the same surface REQUIRED-CHECKS' other PR gates judge.
rl_changed() {   # $1 = head, $2 = out file
  if [ -n "${_rl_mb:-}" ]; then
    git -C "$RL_REPO" diff --name-only "$_rl_mb" "$1" > "$2" 2>/dev/null || return 1
  else
    git -C "$RL_REPO" show --name-only --pretty=format: "$1" > "$2" 2>/dev/null || return 1
  fi
  return 0
}

# rl_class — the change-class from THE SINGLE AUTHORITY, never re-derived here. Fails CLOSED: an empty
# or unrecognised answer is a DERIVE FAILURE (rc 1), never an implicit `ordinary`, which would be
# fail-OPEN on exactly the decision this gate exists to protect. The child's environment is SCRUBBED
# (`env -u`), the banked precedent from ceremony-binding and backlog-presence: KIT_ADAPTERS_DIR moves
# the control-plane path set and KIT_UNION_LIB selects the matcher, so an ambient variable would decide
# whether the scope cut applies.
rl_class() {   # $1 = listing file
  _rc_out="$(env -u KIT_ADAPTERS_DIR -u KIT_UNION_LIB sh "$DIR/conformance/promotion-readiness.sh" \
              --changed "$1" --class 2>/dev/null | tail -1)" || _rc_out=""
  case "$_rc_out" in
    ordinary|sensitive|control-plane) printf '%s\n' "$_rc_out"; return 0 ;;
    *) return 1 ;;
  esac
}

# rl_docs_only — the OTHER existing authority, used for two different questions: the scope cut, and the
# closed-round rule's "docs-only tail". Its verdict is its OUTPUT (it always exits 0), so an unreadable
# listing reads `false`, which is the fail-safe direction here too: not-docs-only means MORE is required.
rl_docs_only() {   # $1 = listing file -> 0 = docs-only
  [ "$(sh "$DIR/conformance/ci-classify-changes.sh" "$1" 2>/dev/null | tail -1)" = "docs_only=true" ]
}

# rl_warn — a FORM finding: advisory, never sets a failure accumulator (RECORD-GRAMMAR-ESSENTIALS §2).
# `WARN: <RL-token>: <what> — fix: <one line>` on stderr (ci-gates.sh's shape); under Actions the same
# text is also a `::warning::` annotation so it shows on the PR where the approver looks.
rl_warn() {
  printf 'WARN: %s\n' "$1" >&2
  if [ "${GITHUB_ACTIONS:-}" = true ]; then printf '::warning::%s\n' "$(rl_annot_escape "$1")"; fi
  return 0
}
# rl_annot_escape — GitHub's workflow-command data encoding: % -> %25, CR -> %0D, LF -> %0A, so a path
# or value in the text cannot end the annotation early or forge a second command.
rl_annot_escape() {
  _ae_cr=$(printf '\r')
  printf '%s' "$1" | sed -e 's/%/%25/g' -e "s/$_ae_cr/%0D/g" \
    | awk '{ if (NR > 1) printf "%%0A"; printf "%s", $0 }'
}

# ── THE XS/S ORDINARY CEILING (RECORD-GRAMMAR-ESSENTIALS §3). Every arm that cannot PROVE "ordinary,
#    sized XS/S at the merge-base, row bound to this PR" returns 1 = owed, today's RL-TRAILER path.
# rl_row_size <base> <row-id> <tmpdir> -> prints the row's Size cell on the BASE board; rc 1 = unknown.
rl_row_size() {
  _rs_f="$3/base-board.md"
  git -C "$RL_REPO" show "$1:BACKLOG.md" > "$_rs_f" 2>/dev/null || return 1
  mkdir -p "$3/bk"
  git -C "$RL_REPO" show "$1:CLAUDE.md" > "$3/bk/CLAUDE.md" 2>/dev/null || : > "$3/bk/CLAUDE.md"
  # shellcheck source=/dev/null
  . "$DIR/conformance/backlog-lib.sh"
  # The seam's own wrapper (never raw resolve_backend). A non-zero rc (unset root) or any non-md token
  # (a tracker backend, an unrecognized value) -> size unknown -> owed.
  # shellcheck disable=SC2034  # read by the sourced seam_backend (backlog-lib.sh)
  SEAM_ROOT="$3/bk"
  _rs_be=$(seam_backend 2>/dev/null) || return 1
  case "$_rs_be" in
    ''|md) ;;
    *) return 1 ;;
  esac
  _rs_hits=0; _rs_size=""
  for _rs_sec in "Ready" "In Progress" "In Review" "Blocked" "Released" "Done" "Backlog (unrefined)"; do
    _rs_rows=$(section_rows "$_rs_f" "$_rs_sec")
    [ -n "$_rs_rows" ] || continue
    _rs_hdr=$(printf '%s\n' "$_rs_rows" | head -1); _rs_ix=$(col_index "$_rs_hdr" Size); _rs_n=0
    # The heredoc's lone `\` first line is dropped by the shell (unquoted heredoc); semgrep's bash grammar needs it to parse this loop whole.
    while IFS= read -r _rs_row; do
      _rs_n=$((_rs_n + 1)); [ "$_rs_n" -eq 1 ] && continue
      is_sep_row "$_rs_row" && continue
      [ "$(backtick_id "$(gfm_cell "$_rs_row" 1)")" = "$2" ] || continue
      # A row already Done/Released at the merge-base cannot be the slice being built -> owed.
      case "$_rs_sec" in
        Done|Released) return 1 ;;
      esac
      _rs_hits=$((_rs_hits + 1))
      [ -z "$_rs_ix" ] || _rs_size=$(gfm_cell "$_rs_row" "$_rs_ix")
    done <<EOF
\
$_rs_rows
EOF
  done
  [ "$_rs_hits" -eq 1 ] && [ -n "$_rs_size" ] || return 1
  printf '%s' "$_rs_size"
}

# rl_row_touched <base> <head> <row-id> — the id, backticked, sits on an added/changed BACKLOG.md line.
rl_row_touched() {
  # shellcheck source=/dev/null
  . "$DIR/conformance/backlog-lib.sh"
  _rt_added=$(git -C "$RL_REPO" diff "$1" "$2" -- BACKLOG.md 2>/dev/null | grep '^+' | grep -v '^+++' || true)
  [ -n "$_rt_added" ] || return 1
  # Only a TABLE ROW whose Item cell LEADS with exactly this id counts: an Order line, a prose line or
  # another row's cell that merely mentions the id must not bind it.
  # The heredoc's lone `\` first line is dropped by the shell (unquoted heredoc); semgrep's bash grammar needs it to parse this loop whole.
  while IFS= read -r _rt_l; do
    _rt_l=${_rt_l#+}
    case "$_rt_l" in
      '|'*) ;;
      *) continue ;;
    esac
    [ "$(backtick_id "$(gfm_cell "$_rt_l" 1)")" = "$3" ] && return 0
  done <<EOF
\
$_rt_added
EOF
  return 1
}

# rl_ceiling_exempt <head> <class> <tmpdir> — rc 0 (and a NOTE) iff ordinary AND the head's Kit-Row is
# sized XS/S at the merge-base AND this PR's board diff touches it AND the head volunteers no records.
rl_ceiling_exempt() {
  [ "$2" = ordinary ] && [ -n "${_rl_mb:-}" ] || return 1
  [ "$(rl_trailer_count "$1" Kit-Plan)" -eq 0 ] && [ "$(rl_trailer_count "$1" Kit-Review)" -eq 0 ] || return 1
  [ "$(rl_trailer_count "$1" Kit-Row)" -eq 1 ] || return 1
  _ce_row=$(rl_trailer "$1" Kit-Row | head -1)
  case "$_ce_row" in
    ''|[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789]*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-]*) return 1 ;;
  esac
  _ce_size=$(rl_row_size "$_rl_mb" "$_ce_row" "$3") || return 1
  case "$_ce_size" in
    XS|S) ;;
    *) return 1 ;;
  esac
  rl_row_touched "$_rl_mb" "$1" "$_ce_row" || return 1
  echo "review-lane: NOTE — XS/S ordinary ($_ce_row, size $_ce_size): no plan/record owed; the design note + task brief ride the PR body, the verdict rides the PR (body/comment) and the owner's forge Approve"
  return 0
}

# ── TRAILERS. loop-state's parser idiom, REUSED rather than re-derived: `%(trailers:key=…,valueonly)`
#    parses the trailer BLOCK, where `grep '^Kit-'` matches any line anywhere in the message — the
#    severed-block defect loop-state's own fixture pins. The two gates must not disagree on parsing, so
#    Kit-Plan / Kit-Review are also declared in loop-state's advisory map.
rl_trailer() {   # $1 = sha, $2 = key
  git -C "$RL_REPO" log -1 --format="%(trailers:key=$2,valueonly)" "$1" 2>/dev/null
}
rl_trailer_count() {   # `grep -c .`, never `wc -l` — the --format output appends a newline
  rl_trailer "$1" "$2" | grep -c . || true
}

# rl_path_ok — head-side confinement for ONE artifact path (design section 7). Charset, literal prefix,
# `.md` suffix, no `..` segment. Refused at the boundary, before the value reaches git or a log.
rl_path_ok() {   # $1 = path, $2 = required prefix
  case "$1" in
    ''|*[!A-Za-z0-9_./-]*) return 1 ;;
  esac
  case "$1" in
    "$2"*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    *.md) ;;
    *) return 1 ;;
  esac
  case "$1" in
    *..*) return 1 ;;
  esac
  return 0
}

# rl_blob_ok — the artifact is a TRACKED REGULAR FILE at the graded head. mode 100644 only: 120000 is a
# symlink (which would resolve outside the tree) and 160000 is a gitlink (a submodule pointer nobody
# grades). Reading by OBJECT is what makes "never check out the head" true rather than nearly-true.
rl_blob_ok() {   # $1 = head, $2 = path
  _bo=$(git -C "$RL_REPO" ls-tree "$1" -- "$2" 2>/dev/null | awk '{print $1}')
  [ "$_bo" = "100644" ]
}
rl_blob() { git -C "$RL_REPO" cat-file -p "$1:$2" 2>/dev/null; }

# ── RECORD STRUCTURE. Sections are `## <Name>` … next `## `; table rows are `|`-leading lines minus the
#    separator row and minus the FIRST row (the column header). Deliberately structural rather than a
#    grep: a grep for "APPROVE" is satisfied by the word appearing in prose.
rl_section() {   # $1 = file, $2 = section name
  awk -v s="## $2" 'BEGIN{i=0} /^## /{ i = ($0 == s) ? 1 : 0; next } i==1 {print}' "$1"
}
rl_rows() {   # stdin: a section; stdout: its data rows
  grep '^|' | grep -vE '^\|[[:space:]]*:?-' | awk 'NR>1'
}
rl_cell() { printf '%s' "$1" | awk -F'|' -v n="$2" '{print $(n+1)}' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

# rl_added_designs — the design docs this change-set ADDS (never amends: the 142 existing docs are in the
# base), one path per line to $2. --no-renames: a rename is an add plus a delete, so it owes the table.
rl_added_designs() {   # $1 = head, $2 = out file
  if [ -n "${_rl_mb:-}" ]; then
    git -C "$RL_REPO" diff --name-only --no-renames --diff-filter=A "$_rl_mb" "$1" > "$2.all" 2>/dev/null || return 1
  else
    git -C "$RL_REPO" show --name-only --no-renames --diff-filter=A --pretty=format: "$1" > "$2.all" 2>/dev/null || return 1
  fi
  : > "$2"
  while IFS= read -r _ad_p; do
    # shellcheck disable=SC2254  # the glob IS the pattern; RL_DESIGN_GLOB is a constant, never head-controlled
    case "$_ad_p" in
      $RL_DESIGN_GLOB) printf '%s\n' "$_ad_p" >> "$2" ;;
      # git QUOTES a name with a non-ASCII byte, control char, quote or backslash (core.quotePath); the
      # quoted line never matches the glob, so it is passed on for rl_lens_leg to refuse by charset.
      '"docs/architecture/'*'-design.md"') printf '%s\n' "$_ad_p" >> "$2" ;;
    esac
  done < "$2.all"
  return 0
}

# rl_lens_leg — rule 9. Each added design doc needs a `## Lens review` heading (a section prefix such as
# `9.`, `9a.` or `§9` is fine) and a table cell equal to each of the twelve names. PRESENCE only: content is
# never read (the skill's veto on prose scanners). One pattern, read by the heading grep AND the awk cell pass.
RL_LENS_SECT=$(printf '\302\247')   # U+00A7 SECTION SIGN as its two UTF-8 bytes; the source stays ASCII
RL_LENS_HEAD="^## ((${RL_LENS_SECT})?[0-9]+[a-zA-Z]*[.]? )?Lens review"
rl_lens_leg() {   # $1 = head, $2 = scratch dir -> 0 | 2
  _ll_rc=0
  rl_added_designs "$1" "$2/added.txt" || { echo "RL-NO-CHANGESET: the added design docs could not be listed — fail closed"; return 2; }
  while IFS= read -r _ll_p; do
    [ -n "$_ll_p" ] || continue
    if ! rl_path_ok "$_ll_p" docs/architecture/ || ! rl_blob_ok "$1" "$_ll_p"; then
      # printf, never echo: dash and macOS sh turn a quoted name's literal \n back into a real newline (log forgery)
      printf '%s\n' "RL-DESIGN-PATH: '$(rl_safe "$_ll_p")' is an added design doc that is not a tracked regular file with a plain name — fail closed"; _ll_rc=2; continue
    fi
    rl_blob "$1" "$_ll_p" | tr -d '\r' > "$2/design.md"
    if ! LC_ALL=C grep -Eq -e "$RL_LENS_HEAD" "$2/design.md"; then
      echo "RL-DESIGN-NO-LENS-TABLE: $_ll_p is a design doc added by this change and has no '## Lens review' section — the M/Sensitive/Control-plane design answers the twelve lenses in skills/design/SKILL.md (N/A with a reason is an answer)"; _ll_rc=2; continue
    fi
    LC_ALL=C awk -v re="$RL_LENS_HEAD" 'BEGIN{i=0;d=0} /^## /{ if (d==0 && $0 ~ re) { i=1; d=1 } else { i=0 }; next } i==1 && /^\|/ { n=split($0, f, "|"); for (k=2; k<n; k++) { c=f[k]; gsub(/^[ \t]+/, "", c); gsub(/[ \t]+$/, "", c); if (length(c) > 4 && substr(c,1,2) == "**" && substr(c,length(c)-1) == "**") c=substr(c,3,length(c)-4); print c } }' "$2/design.md" > "$2/cells.txt"
    # The heredoc's lone `\` first line is dropped by the shell (unquoted heredoc); semgrep's bash grammar needs it to parse this loop whole.
    while IFS= read -r _ll_n; do
      grep -qFx "$_ll_n" "$2/cells.txt" || { echo "RL-DESIGN-LENS-MISSING: $_ll_p has a Lens review section but no row for '$_ll_n' — add the row; N/A with a reason is an answer"; _ll_rc=2; }
    done <<EOF
\
$RL_LENSES
EOF
  done < "$2/added.txt"
  return "$_ll_rc"
}

# rl_containment — a cited commit must be an ANCESTOR of the graded head AND NOT an ancestor of the
# merge-base with the base. ceremony-binding's two legs, and for its measured reason: leg 1 alone is
# satisfied by any commit already on the mainline, so a record could cite integrated history and pass.
# `--is-ancestor` reports its verdict in the EXIT STATUS, so every call captures the rc rather than
# letting `set -e` kill the run mid-adjudication.
rl_containment() {   # $1 = commit, $2 = head -> 0 contained, 1 outside, 2 unevaluable
  _ct=0; git -C "$RL_REPO" merge-base --is-ancestor "$1" "$2" >/dev/null 2>&1 || _ct=$?
  [ "$_ct" = 0 ] || { [ "$_ct" = 1 ] && return 1; return 2; }
  if [ -n "${_rl_mb:-}" ]; then
    _ct2=0; git -C "$RL_REPO" merge-base --is-ancestor "$1" "$_rl_mb" >/dev/null 2>&1 || _ct2=$?
    [ "$_ct2" = 0 ] && return 1
    [ "$_ct2" = 1 ] || return 2
  fi
  return 0
}

# ── RULE 10 — THE SEAT ROLES (SWAS-300; docs/architecture/2026-10-18-typed-seats-day-one-design.md §5).
# The record names each seat by a ROLE (builder, reviewer, security, conductor), and the roles are
# the vocabulary the kit's neutral definitions declare: one `Seat role: <name>` line per
# `agents/*.agent.md`, read AS GIT OBJECTS at the MERGE-BASE, so a PR cannot widen the set it is graded
# against (the same posture as the grader itself, above). No `.claude/` file, no subagent type string
# and no model name is read: the vocabulary is harness-neutral, and the model or tier after the role
# word is free text that is never graded or required.
#
# ⚠️ THE CEILING, SAID HERE SO NOBODY QUOTES A GREEN AS MORE (the same words as rule 4's): every token
# is BUILDER-TYPED TEXT. A green from this rule means the record NAMES declared seats; it does not
# show that any seat ran, that two seats were two dispatches, or that a seat followed its skill. A
# conductor that reviewed inline can type `reviewer` and pass. The dispatch is conduct, not enforced.
RL_SEAT_LINE_RE='^Seat role: ([a-z][a-z-]*)$'

# rl_seat_vocab <scratch> — write the base's role set to <scratch>/vocab. Fails CLOSED (RL-SEAT-VOCAB, rc 2)
# on: no merge-base, no definition, a definition with zero or two `Seat role:` lines or a line off the
# strict grammar, or two definitions declaring the same role. A gate whose vocabulary is broken grades nothing.
rl_seat_vocab() {
  : > "$1/vocab"
  if [ -z "${_rl_mb:-}" ]; then
    echo "RL-SEAT-VOCAB: no merge-base, so there is no trusted seat vocabulary (the agents/*.agent.md definitions are read from the base, never the head) — fail closed"; return 2
  fi
  _sv=0
  git -C "$RL_REPO" ls-tree --name-only "$_rl_mb" agents/ > "$1/defs" 2>/dev/null || : > "$1/defs"
  while IFS= read -r _sv_p; do
    case "$_sv_p" in
      agents/*.agent.md) ;;
      *) continue ;;
    esac
    rl_blob "$_rl_mb" "$_sv_p" > "$1/def.md" || : > "$1/def.md"
    _sv_loose=$(grep -c '^Seat role:' "$1/def.md" || true)
    _sv_strict=$(grep -Ec "$RL_SEAT_LINE_RE" "$1/def.md" || true)
    if [ "$_sv_loose" != 1 ] || [ "$_sv_strict" != 1 ]; then
      echo "RL-SEAT-VOCAB: the base definition '$(rl_safe "$_sv_p")' must carry exactly one line 'Seat role: <name>' ([a-z][a-z-]*, one space, nothing trailing) — found $_sv_loose, $_sv_strict well-formed"; _sv=2; continue
    fi
    grep -E "$RL_SEAT_LINE_RE" "$1/def.md" | sed 's/^Seat role: //' >> "$1/vocab"
  done < "$1/defs"
  if ! grep -q . "$1/vocab"; then
    echo "RL-SEAT-VOCAB: the base tree declares no seat role (no agents/*.agent.md with a 'Seat role:' line) — fail closed"; return 2
  fi
  if [ -n "$(sort "$1/vocab" | uniq -d)" ]; then
    echo "RL-SEAT-VOCAB: two base definitions declare the same role '$(rl_safe "$(sort "$1/vocab" | uniq -d | head -1)")' — a duplicate would let one seat stand in for another"; _sv=2
  fi
  return "$_sv"
}

# rl_seat_word — stdin: a record cell or line; prints its first whitespace-delimited word, normalised:
# surrounding backticks and bold stripped, one trailing ':' or ',' stripped, lowercased.
rl_seat_word() {
  awk '{ print $1; exit }' | sed -e 's/^[`*]*//' -e 's/[`*]*[:,]\{0,1\}[`*]*$//' | LC_ALL=C tr 'A-Z' 'a-z'
}

# rl_seat_member <word> <vocab-file> — 0 iff the word is a well-formed role AND a member.
rl_seat_member() {
  case "$1" in
    ''|[!a-z]*|*[!a-z-]*) return 1 ;;
  esac
  grep -qxF "$1" "$2"
}

# rl_seat_leg <record file> <scratch> <record path> — rule 10 proper. Prints one refusal per defect; 0 | 2.
rl_seat_leg() {
  _sl=0
  rl_seat_vocab "$2" || return 2
  _sl_set=$(tr '\n' ' ' < "$2/vocab" | sed 's/ $//')
  # 1. the Builder line opens with a declared role (`conductor` is legal: building inline stays visible).
  _sl_w=$(grep -m1 '^Builder:' "$1" | sed 's/^Builder:[[:space:]]*//' | rl_seat_word || true)
  if ! rl_seat_member "$_sl_w" "$2/vocab"; then
    echo "RL-SEAT-UNKNOWN: the Builder line of $3 opens with '$(rl_safe "$_sl_w")', which is not a declared seat role (declared: $_sl_set) — fix: open the line with a role, e.g. 'Builder: builder (two seats)'"; _sl=2
  fi
  # 2. every Rounds seat is a declared role, and the role is `reviewer`.
  while IFS= read -r _sl_row; do
    [ -n "$_sl_row" ] || continue
    _sl_w=$(rl_cell "$_sl_row" 2 | rl_seat_word || true)
    if ! rl_seat_member "$_sl_w" "$2/vocab"; then
      echo "RL-SEAT-UNKNOWN: a Rounds row of $3 names the seat '$(rl_safe "$_sl_w")', which is not a declared seat role (declared: $_sl_set) — fix: open the cell with 'reviewer'"; _sl=2
    elif [ "$_sl_w" != reviewer ]; then
      echo "RL-SEAT-NOT-REVIEWER: a Rounds row of $3 names the seat '$(rl_safe "$_sl_w")'; every review round is the 'reviewer' role — fix: open the cell with 'reviewer'"; _sl=2
    fi
  done < "$2/rounds"
  # 3 and 4. the security section: a `ran` line names a declared seat (`security` on Sensitive or
  # Control-plane work), and a `waived` section is refused on those classes.
  _sl_sec=$(rl_section "$1" 'Security review' 2>/dev/null || true)
  _sl_hard=0
  case "${_rl_class:-control-plane}" in
    ordinary) ;;
    *) _sl_hard=1 ;;
  esac
  if printf '%s' "$_sl_sec" | grep -qE "$RL_SEC_RAN_RE"; then
    _sl_w=$(printf '%s\n' "$_sl_sec" | grep -E "$RL_SEC_RAN_RE" | head -1 \
            | awk '{ for (i = 1; i < NF; i++) if ($i == "seat") { print $(i + 1); exit } }' | rl_seat_word || true)
    if [ -z "$_sl_w" ]; then
      echo "RL-SEAT-SECURITY-MISSING: the security line of $3 names no seat — fix: write 'ran — seat security, verdict: …' (declared roles: $_sl_set)"; _sl=2
    elif ! rl_seat_member "$_sl_w" "$2/vocab"; then
      echo "RL-SEAT-UNKNOWN: the security line of $3 names the seat '$(rl_safe "$_sl_w")', which is not a declared seat role (declared: $_sl_set) — fix: write 'seat security'"; _sl=2
    elif [ "$_sl_hard" = 1 ] && [ "$_sl_w" != security ]; then
      echo "RL-SEAT-SECURITY-NOT-DISTINCT: the security line of $3 names the seat '$(rl_safe "$_sl_w")'; on a ${_rl_class:-control-plane} change the security review is the separate 'security' seat — fix: write 'seat security'"; _sl=2
    fi
  elif [ "$_sl_hard" = 1 ] && printf '%s' "$_sl_sec" | grep -qE "$RL_SEC_WAIVED_RE"; then
    echo "RL-SEAT-SECURITY-WAIVED-CP: $3 waives the security review on a ${_rl_class:-control-plane} change; the four waiver criteria are literal tokens, and a change with this surface cannot honestly claim them — run the 'security' seat"; _sl=2
  fi
  return "$_sl"
}

# ── THE RECORD GRADER (design 4.2 rules 2-7). Prints one refusal line per defect, each carrying a
#    NAMED TOKEN so a consumer can key on the reason rather than on prose. Returns 0 or 2.
rl_grade_record() {   # $1 = head, $2 = record path, $3 = scratch dir
  _gr=0; _gp="$2"; _gf="$3/record.md"
  rl_blob "$1" "$_gp" > "$_gf" 2>/dev/null || true
  if [ ! -s "$_gf" ]; then
    echo "RL-RECORD-EMPTY: $_gp is empty at the graded head — a stub is not a record"; return 2
  fi
  if [ "$(wc -c < "$_gf" | tr -d ' ')" -gt "$RL_MAX_RECORD_BYTES" ]; then
    echo "RL-RECORD-OVERSIZE: $_gp exceeds $RL_MAX_RECORD_BYTES bytes at the graded head"; _gr=2
  fi
  if grep -qF "$RL_TEMPLATE_MARKER" "$_gf"; then
    echo "RL-RECORD-IS-TEMPLATE: $_gp still carries the template's '$RL_TEMPLATE_MARKER' marker sentence — the template itself is not a record"; _gr=2
  fi
  # `___` residue in the IDENTITY LINES: the template's own placeholder. A record whose Builder or
  # Reviewer is still `___` is unfilled, and a string-inequality test would happily pass two of them.
  # ANCHORED ON THE TWO LINES, not `head -8` (reviewer m5): the window was both too narrow and too
  # wide — a template with prose above the fields put them past line 8 (missed), while a legitimate
  # `___` in an unrelated header cell inside the window redded a filled-in record (false positive).
  if grep -qE '^(Builder|Reviewer):.*___' "$_gf"; then
    echo "RL-RECORD-PLACEHOLDER: $_gp still carries the template's '___' placeholder on its Builder or Reviewer line — the record is unfilled"; _gr=2
  fi

  # --- rule 4: Builder != Reviewer (normalised: trimmed, case-folded, whitespace-collapsed).
  _gb=$(grep -m1 '^Builder:' "$_gf" 2>/dev/null | sed 's/^Builder:[[:space:]]*//; s/[[:space:]]*Reviewer:.*$//' \
        | tr 'A-Z' 'a-z' | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
  _gv=$(grep -m1 'Reviewer:' "$_gf" 2>/dev/null | sed 's/^.*Reviewer:[[:space:]]*//' \
        | tr 'A-Z' 'a-z' | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
  if [ -z "$_gb" ] || [ -z "$_gv" ]; then
    echo "RL-IDENTITY-MISSING: $_gp must name both a Builder and a Reviewer"; _gr=2
  elif [ "$_gb" = "$_gv" ]; then
    # THE CEILING, SAID HERE SO NOBODY QUOTES THIS LEG AS MORE: both strings are BUILDER-TYPED. This
    # refuses the record that does not even CLAIM a second identity; what makes the review
    # non-self-attested is the forge's own review requirement (rule 8's declared dependency), not this
    # comparison.
    echo "RL-SAME-IDENTITY: $_gp names the same Builder and Reviewer ('$(rl_safe "$_gb")')"; _gr=2
  fi

  # --- rule 3: rounds — containment, then the CLOSED-ROUND rule.
  _grounds="$3/rounds"; rl_section "$_gf" 'Rounds' | rl_rows > "$_grounds" || true
  if ! grep -q '[^[:space:]]' "$_grounds" 2>/dev/null; then
    echo "RL-NO-ROUNDS: $_gp has no review round — an empty Rounds table records nothing"; return 2
  fi
  _glast=""; _gopen=0
  while IFS= read -r _grow; do
    [ -n "$_grow" ] || continue
    _gc=$(rl_cell "$_grow" 1); _gvd=$(rl_cell "$_grow" 3)
    case "$_gc" in
      *[!0123456789abcdefABCDEF]*|'') echo "RL-ROUND-SHA: round row cites '$(rl_safe "$_gc")', which is not a commit object name"; _gr=2; continue ;;
    esac
    if ! git -C "$RL_REPO" rev-parse -q --verify "$_gc^{commit}" >/dev/null 2>&1; then
      echo "RL-ROUND-UNKNOWN: $_gp cites commit $_gc, which is not in this repository — a force-push after the record leaves it citing commits no longer in the PR; re-review and re-attest"; _gr=2; continue
    fi
    _gcc=0; rl_containment "$_gc" "$1" || _gcc=$?
    if [ "$_gcc" = 1 ]; then
      echo "RL-ROUND-OUTSIDE: $_gp cites commit $_gc, which is not part of THIS change (not an ancestor of the head, or already integrated into the base)"; _gr=2; continue
    elif [ "$_gcc" = 2 ]; then
      echo "RL-ROUND-UNEVALUABLE: containment for $_gc could not be evaluated — fail closed"; _gr=2; continue
    fi
    case "$_gvd" in
      APPROVE)     _glast="$_gc"; _gopen=0 ;;
      NEEDS-FIXES) _gopen=1 ;;
      *) echo "RL-ROUND-VERDICT: round row for $_gc carries verdict '$(rl_safe "$_gvd")' — only APPROVE or NEEDS-FIXES"; _gr=2 ;;
    esac
  done < "$_grounds"
  if [ "$_gopen" = 1 ] || [ -z "$_glast" ]; then
    echo "RL-OPEN-ROUND: $_gp has no closing APPROVE round (a NEEDS-FIXES with no later APPROVE is an open review)"; _gr=2
  else
    # THE CLOSED-ROUND RULE (vet H3). The commit that APPENDS the APPROVE row cannot cite its own sha,
    # so a literal "the last round cites the head" is unsatisfiable. Instead: everything after the
    # closing APPROVE must be BOOKKEEPING — docs-only by the classifier's own verdict AND confined to
    # the record/plan/board paths. One code commit after the approval re-opens the round.
    _gtail="$3/tail"
    git -C "$RL_REPO" diff --name-only "$_glast" "$1" > "$_gtail" 2>/dev/null || : > "$_gtail"
    if grep -q '[^[:space:]]' "$_gtail"; then
      if ! rl_docs_only "$_gtail"; then
        rl_warn "RL-OPEN-ROUND: commits after the closing APPROVE ($_glast) are not docs-only — fix: re-review and re-approve at the new head if the change is substantive"
      else
        while IFS= read -r _gt; do
          [ -n "$_gt" ] || continue
          _gok=1
          for _gpfx in $RL_POST_APPROVE_PATHS; do
            case "$_gt" in
              "$_gpfx"*) _gok=0; break ;;
            esac
          done
          [ "$_gok" = 0 ] || rl_warn "RL-OPEN-ROUND: '$(rl_safe "$_gt")' changed after the closing APPROVE and is outside the bookkeeping set ($RL_POST_APPROVE_PATHS) — fix: re-review at the new head, or keep post-approval edits to the record, plan and board"
        done < "$_gtail"
      fi
    fi
  fi

  # --- rule 5: every finding is DISPOSED, in the grammar. An undisposed finding is how a real defect
  # becomes a note nobody actioned. An EMPTY table is legal — "no findings" is a recordable result.
  rl_section "$_gf" 'Findings' | rl_rows | while IFS= read -r _grow; do
    [ -n "$_grow" ] || continue
    _gd=$(rl_cell "$_grow" 4); _gi=$(rl_cell "$_grow" 1)
    case "$_gd" in
      # `fixed <sha>` IS CHECKED AGAINST THE PR, not merely against the hex charset (security S-L3).
      # An unchecked sha is a citation to nothing: `fixed deadbeef` disposed of a HIGH finding with a
      # string. The sha must be a real commit AND contained in this change — the same two-leg test the
      # Rounds table gets, because a fix that lives outside the PR is a fix this PR does not carry.
      'fixed '[0-9a-f]*)
        _gfx=$(printf '%s' "$_gd" | awk '{print $2}')
        if ! git -C "$RL_REPO" rev-parse -q --verify "$_gfx^{commit}" >/dev/null 2>&1; then
          echo "RL-FIX-OUTSIDE: finding '$(rl_safe "$_gi")' is disposed 'fixed $(rl_safe "$_gfx")', which is not a commit in this repository"
        else
          _gfc=0; rl_containment "$_gfx" "$1" || _gfc=$?
          [ "$_gfc" = 0 ] || echo "RL-FIX-OUTSIDE: finding '$(rl_safe "$_gi")' cites fix commit $_gfx, which is not part of THIS change (not an ancestor of the head, or already in the base)"
        fi ;;
      'accepted '*) [ "${#_gd}" -ge 20 ] || echo "RL-FINDING-DISPOSITION: finding '$(rl_safe "$_gi")' is accepted with no reason of substance" ;;
      'waived '*WAIVER-*) ;;
      *) echo "RL-FINDING-DISPOSITION: finding '$(rl_safe "$_gi")' carries no disposition in the grammar (fixed <sha> | accepted - <reason> | waived - WAIVER-<id>)" ;;
    esac
  done > "$3/find" 2>/dev/null || true
  if grep -q '[^[:space:]]' "$3/find" 2>/dev/null; then cat "$3/find"; _gr=2; fi
  # A waived finding must cite a WAIVER id that EXISTS in the register at the graded head. A citation to
  # nothing is the same hole as no disposition, wearing a process word.
  rl_section "$_gf" 'Findings' | rl_rows | while IFS= read -r _grow; do
    [ -n "$_grow" ] || continue
    _gd=$(rl_cell "$_grow" 4)
    case "$_gd" in
      *WAIVER-*) _gw=$(printf '%s' "$_gd" | sed 's/.*\(WAIVER-[A-Za-z0-9_.-]*\).*/\1/')
        rl_blob "$1" WAIVER-REGISTER.md 2>/dev/null | grep -qF "$_gw" \
          || echo "RL-WAIVER-MISSING: $_gw is cited but not present in WAIVER-REGISTER.md at the graded head" ;;
    esac
  done > "$3/waiv" 2>/dev/null || true
  if grep -q '[^[:space:]]' "$3/waiv" 2>/dev/null; then cat "$3/waiv"; _gr=2; fi

  # --- rule 6: every design-promised control RESOLVES. `path::test-name` must exist at the head AND
  # carry the token on an EXECUTABLE LINE — not a comment (the CI-lane slice's rule, vet M5). A control
  # discharged by a comment or a fixture string is discharged by nothing. Remaining ceiling, disclosed:
  # a DEAD function still resolves.
  _gsec="$3/ctl"; rl_section "$_gf" 'Design-promised controls' > "$_gsec" 2>/dev/null || : > "$_gsec"
  if [ ! -s "$_gsec" ]; then
    echo "RL-NO-CONTROLS-SECTION: $_gp has no 'Design-promised controls' section"; _gr=2
  fi
  rl_rows < "$_gsec" | while IFS= read -r _grow; do
    [ -n "$_grow" ] || continue
    _gk=$(rl_cell "$_grow" 1); _gdd=$(rl_cell "$_grow" 2)
    case "$_gdd" in
      *'not built, because'*)
        _gwhy=$(printf '%s' "$_gdd" | sed 's/.*not built, because//' | tr -d '[:space:]')
        [ "${#_gwhy}" -ge 20 ] || echo "RL-CONTROL-UNRESOLVED: control '$(rl_safe "$_gk")' says 'not built, because' with no reason of substance" ;;
      *::*)
        _gpath=$(printf '%s' "$_gdd" | sed 's/.*[^A-Za-z0-9_./-]\([A-Za-z0-9_./-]*\)::.*/\1/; s/^`//')
        _gtest=$(printf '%s' "$_gdd" | sed 's/.*:://; s/[`].*$//' | sed 's/[[:space:]]*$//')
        if [ -z "$_gpath" ] || [ -z "$_gtest" ]; then
          echo "RL-CONTROL-UNRESOLVED: control '$(rl_safe "$_gk")' cites an unparseable path::test-name"
        elif ! git -C "$RL_REPO" cat-file -e "$1:$_gpath" 2>/dev/null; then
          echo "RL-CONTROL-UNRESOLVED: control '$(rl_safe "$_gk")' cites '$(rl_safe "$_gpath")', which does not exist at the graded head"
        elif ! rl_blob "$1" "$_gpath" | grep -vE '^[[:space:]]*#' | grep -qF "$_gtest"; then
          echo "RL-CONTROL-UNRESOLVED: control '$(rl_safe "$_gk")' cites test '$(rl_safe "$_gtest")', which appears on no executable line of '$(rl_safe "$_gpath")'"
        fi ;;
      *) echo "RL-CONTROL-UNRESOLVED: control '$(rl_safe "$_gk")' is discharged by neither a path::test-name nor 'not built, because <reason>'" ;;
    esac
  done > "$3/ctlout" 2>/dev/null || true
  if grep -q '[^[:space:]]' "$3/ctlout" 2>/dev/null; then cat "$3/ctlout"; _gr=2; fi

  # --- rule 7: the security review section (D-240904-1 made literal).
  _gsr=$(rl_section "$_gf" 'Security review' 2>/dev/null || true)
  if [ -z "$(printf '%s' "$_gsr" | tr -d '[:space:]')" ]; then
    echo "RL-SECURITY-ABSENT: $_gp has no 'Security review' section — D-240904-1 makes the diff security review the default, and its record is a stage artifact"; _gr=2
  elif printf '%s' "$_gsr" | grep -qE "$RL_SEC_RAN_RE"; then
    printf '%s' "$_gsr" | grep -qE 'verdict[[:space:]]*[:=]?[[:space:]]*[A-Za-z]' \
      || { echo "RL-SECURITY-NO-VERDICT: the security review says 'ran' but names no verdict"; _gr=2; }
  elif printf '%s' "$_gsr" | grep -qE "$RL_SEC_WAIVED_RE"; then
    for _gcr in $RL_WAIVER_CRITERIA; do
      printf '%s' "$_gsr" | grep -qF "$_gcr" \
        || { echo "RL-SECURITY-WAIVER-INCOMPLETE: the security waiver omits the criterion '$_gcr' — all four D-240904-1 tokens are required, verbatim"; _gr=2; }
    done
  else
    echo "RL-SECURITY-STATE: the security review section states neither 'ran' nor 'waived'"; _gr=2
  fi

  # --- rule 10: the record names declared seat roles (SWAS-300). Shape, not occurrence — see rl_seat_leg.
  rl_seat_leg "$_gf" "$3" "$_gp" || _gr=2
  return "$_gr"
}

# (`rl_security_state` lived here until `D-240904-2`. It existed only to put the record's `ran|waived`
# word into the typed attestation line so an approver would sign it explicitly. With the typed line
# struck it had no second consumer, so it is deleted rather than left as an unreferenced helper — the
# security section is still GRADED, by rule 7 above, which is where the assurance always came from.)

# ── LEG 8 IS NOT A LEG ANY MORE. `rl_attest` and `rl_role_swap` lived here until
# `REVIEW-LANE-WAITING-IS-GREEN` (2026-09-05), together with the `gh`/`jq` preconditions, the forge
# review-list read and the shared `group_by(login)|map(last)` jq filter. All of it is DELETED, not
# reduced: what it computed — a non-author APPROVED review, sitting on THIS head, from someone who did
# not write the head — is exactly what `required_approving_review_count >= 1`, `dismiss_stale_reviews`
# and `require_last_push_approval` enforce server-side on every merge attempt, with no run to wait on.
#
# `rl_role_swap` deserves its epitaph, because its successor is not identical. It matched a forge
# LOGIN against the head commit's author/committer name or email local-part, case-insensitively — a
# DETECTOR of the cheap swap, never a proof, since the two namespaces have no offline mapping.
# `require_last_push_approval` is stronger (a server-side rule on an account, not a string guess) but
# binds a DIFFERENT subject: the PUSHER, where the heuristic bound the commit's author/committer. A
# commit authored as B and pushed by A, approved by B, passes the forge and would have tripped the
# heuristic — a shape that needs two cooperating accounts, which no gate in this kit claims to stop.
# That is a stated ceiling, not a silent one (design §5).
#
# (`rl_stamp_line`, the stamp-printing mode and `rl_sha256` went one ruling earlier, under
# `D-240904-2`, when the typed attestation line was struck.)

# ── THE GATE. Assembles the legs and owns the exit contract.
rl_run() {   # uses $_rl_mode $_rl_pr $_rl_head $_rl_base_ref
  _rl_d=$(mktemp -d "${TMPDIR:-/tmp}/review-lane.XXXXXX") || { echo "review-lane: could not create a scratch directory"; return 2; }
  # TRAP-CLEAN, always: heavy conformance runs have leaked hundreds of GB in this repo before.
  trap 'rm -rf "$_rl_d"' EXIT INT TERM

  rl_presence_leg || { echo "review-lane: the lane's own artifacts are missing (see above)"; return 2; }

  if [ -z "$_rl_head" ]; then
    _rl_head=$(git -C "$RL_REPO" rev-parse -q --verify HEAD 2>/dev/null) || _rl_head=""
  fi
  _rl_head=$(git -C "$RL_REPO" rev-parse -q --verify "${_rl_head}^{commit}" 2>/dev/null) || _rl_head=""
  [ -n "$_rl_head" ] || { echo "RL-NO-HEAD: the graded head could not be resolved — the gate evaluated nothing"; return 2; }

  # ── THE BASE, AND WHY AN UNRESOLVABLE ONE IS NOT A FREE PASS (security S-M1) ────────────────────
  # Without a merge-base, rl_changed falls back to the HEAD COMMIT's own file list. On a branch whose
  # last commit is a docs tidy sitting on top of real code, that listing is all-`.md` — so the class
  # derives `ordinary`, the docs-only predicate says true, and the gate takes the N-A SCOPE CUT on a
  # change-set it never saw. The cut is only sound when the change-set is the whole branch.
  #   --pr      : rc 2. CI always supplies a base; if it could not be resolved something is wrong with
  #               the checkout, and a gate that cannot see the change-set has evaluated nothing.
  #   --pre-push: GRADE ANYWAY, never N-A. A fresh local clone with no origin is a normal developer
  #               state and must not red for its shape, but it must also not buy the cut for free —
  #               so the artifacts are still required and containment degrades to reachability-only.
  #               SWAS-300: rule 10 now DOES red a record-owing --pre-push run with no base (RL-SEAT-VOCAB):
  #               there is no trusted seat vocabulary without a merge-base, and that is a deliberate refusal.
  _rl_mb=""; _rl_nobase=0
  _rl_mb=$(rl_base "$_rl_head") || { _rl_mb=""; _rl_nobase=1; }
  if [ "$_rl_nobase" = 1 ]; then
    if [ "$_rl_mode" = pr ]; then
      echo "RL-NO-BASE: no base history could be resolved, so the change-set could not be derived. CI supplies --base-ref, so this is a broken checkout, not a shallow clone — and a gate that cannot see the change-set must not take the docs-only scope cut on it."
      return 2
    fi
    echo "review-lane: NOTE — no base history could be resolved. Containment runs with the reachability leg only, and the docs-only scope cut is DISABLED for this run (a cut taken on a change-set the gate could not derive is a pass bought by a missing remote)."
  fi

  rl_changed "$_rl_head" "$_rl_d/changed.txt" || { echo "RL-NO-CHANGESET: the change-set could not be derived — fail closed"; return 2; }
  _rl_class=$(rl_class "$_rl_d/changed.txt") || { echo "RL-CLASS-UNDERIVABLE: the change-class could not be derived; fail closed (never an implicit 'ordinary')"; return 2; }
  if [ "$_rl_nobase" = 0 ] && [ "$_rl_class" = ordinary ] && rl_docs_only "$_rl_d/changed.txt"; then
    # DESIGN-SKILL-LENS-LIST amendment A1: a design doc added on a docs-only change-set is graded too, or
    # an M design filed in its own docs PR is never seen. No added design doc -> the N-A line below, unchanged.
    rl_added_designs "$_rl_head" "$_rl_d/docs-added.txt" || { echo "RL-NO-CHANGESET: the added design docs could not be listed — fail closed"; return 2; }
    if [ -s "$_rl_d/docs-added.txt" ]; then
      if rl_ceiling_exempt "$_rl_head" "$_rl_class" "$_rl_d"; then return 0; fi
      rl_lens_leg "$_rl_head" "$_rl_d" || return 2
    fi
    echo "review-lane: N-A — ordinary AND docs-only. The scope cut is the CLASSIFIER's, not this gate's judgment (design 4.1)."
    return 0
  fi
  if rl_ceiling_exempt "$_rl_head" "$_rl_class" "$_rl_d"; then return 0; fi
  echo "review-lane: grading head $_rl_head (class=$_rl_class)"

  # ★ LEG ORDER IS PART OF THE CONTRACT, NOT AN ACCIDENT OF LAYOUT (design 4.2, rules 1 then 2).
  # RULE 1 — resolve the base, derive the change-set, derive the class, apply or refuse the scope cut —
  # runs to completion ABOVE this line, and rule 2's trailer legs run below it. The order is load-
  # bearing in one direction: a head that carries no trailers AND has no derivable base must report
  # RL-NO-BASE, because "the gate could not see the change-set" is a stronger and earlier fact than
  # "the change-set owes artifacts". Invert them and the operator is told to add trailers to fix a
  # broken checkout. The `no base in --pr mode` selftest case pins this: its head has no trailers at
  # all, so if these two blocks are ever swapped it reds with RL-TRAILER and its token assertion fails.
  # --- rule 2: the two trailers, exactly one each, head-side-confined.
  _rl_rc=0; _rl_records=""
  for _rl_k in Kit-Plan Kit-Review; do
    _rl_n=$(rl_trailer_count "$_rl_head" "$_rl_k")
    if [ "$_rl_n" -ne 1 ]; then
      echo "RL-TRAILER: the head commit carries $_rl_n '$_rl_k' trailer(s) — exactly one is required. The $_rl_class change-set owes a plan file and a review record."
      _rl_rc=2; continue
    fi
    _rl_v=$(rl_trailer "$_rl_head" "$_rl_k" | head -1)
    case "$_rl_k" in
      Kit-Plan) _rl_pfx="$RL_PLAN_PREFIX" ;;
      *) _rl_pfx="$RL_REVIEW_PREFIX" ;;
    esac
    # Kit-Review may carry a COMMA-SEPARATED set when a consolidated PR absorbs several slices; each
    # element is confined independently, and every one is graded (design 4.4).
    # THE SPLIT NEVER TOUCHES $IFS — see loop-state.sh's note: semgrep's
    # `bash.lang.security.ifs-tampering` refuses an `IFS=<value>` assignment on the exported artifact,
    # and it flagged this pattern on PR #644. `IFS= read` is the read builtin's own idiom and is not
    # flagged. FIXED AS A CLASS: the CI report named loop-state.sh only, but this file carried the
    # identical shape in two places, so both move — repairing the reported instance and shipping the
    # sibling is how the same red comes back on the next PR.
    # The HEREDOC (not a pipe) keeps the loop in THIS shell: `_rl_rc=2` and `_rl_records` are assigned
    # in the body, and a subshell would discard both — the gate would collect no records and then
    # report a structural pass over an empty set.
    _rl_vals=$(printf '%s' "$_rl_v" | tr ',' '\n')
    # The heredoc's lone `\` first line is dropped by the shell (unquoted heredoc); semgrep's bash grammar needs it to parse this loop whole.
    while IFS= read -r _rl_p; do
      _rl_p=$(printf '%s' "$_rl_p" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
      if ! rl_path_ok "$_rl_p" "$_rl_pfx"; then
        echo "RL-PATH: '$(rl_safe "$_rl_p")' is not an acceptable $_rl_k value (charset [A-Za-z0-9_./-], prefix '$_rl_pfx', '.md' suffix, no '..')"; _rl_rc=2; continue
      fi
      if ! rl_blob_ok "$_rl_head" "$_rl_p"; then
        echo "RL-PATH-UNTRACKED: '$_rl_p' is not a tracked regular file (mode 100644) at the graded head — a symlink, a gitlink and an untracked path are all refused"; _rl_rc=2; continue
      fi
      if [ "$_rl_k" = Kit-Review ]; then
        _rl_g=0; rl_grade_record "$_rl_head" "$_rl_p" "$_rl_d" || _rl_g=$?
        [ "$_rl_g" = 0 ] || _rl_rc=2
        _rl_records="$_rl_records $_rl_p"
      else
        # The plan file is graded for EXISTENCE and SUBSTANCE only. Its content contract is the review
        # record's "Design-promised controls" table, which is graded above — pricing a second grammar
        # here would be ceremony with no assurance returned.
        [ "$(rl_blob "$_rl_head" "$_rl_p" | wc -c | tr -d ' ')" -ge 200 ] \
          || { echo "RL-PLAN-STUB: '$_rl_p' is under 200 bytes at the graded head — a stub is not a plan"; _rl_rc=2; }
      fi
    done <<EOF
\
$_rl_vals
EOF
  done
  # --- rule 9: an added design doc carries the twelve lens names (presence). After the trailer loop so its
  # refusals print beside an RL-TRAILER one; past both scope cuts above, so XS/S ordinary is never graded.
  rl_lens_leg "$_rl_head" "$_rl_d" || _rl_rc=2
  [ "$_rl_rc" = 0 ] || return 2

  # --- rule 8: the attestation, DECLARED RATHER THAN EVALUATED, and identically in both modes since
  # `REVIEW-LANE-WAITING-IS-GREEN`. It is printed on every pass because the green above is otherwise
  # read as "the review lane passed" when what passed is the structural half only (security S-L1): the
  # line names the control that covers the other half and the check that asserts it live, so an
  # operator quoting this rc knows exactly which assurance came from where.
  echo "review-lane: attestation — the forge's review requirement (required_approving_review_count >= 1 + dismiss_stale_reviews + require_last_push_approval; asserted live by conformance/branch-protection.sh)"
  echo "review-lane: rc=0 (structural pass; the approval is branch protection's, not this check's)"
  return 0
}

selftest() {
  st=0
  # LIVENESS ANCHOR — the shipped tree's own presence leg must pass. An always-FAIL implementation
  # breaks THIS leg, and the negatives below break an always-PASS one.
  rl_presence_leg >/dev/null 2>&1 || { echo "selftest FAIL: the shipped lane artifacts must satisfy rl_presence_leg"; st=1; }

  _fx=$(mktemp -d "${TMPDIR:-/tmp}/rl-selftest.XXXXXX") || { echo "selftest FAIL: no scratch"; return 1; }
  trap 'rm -rf "$_fx"' EXIT INT TERM
  _sv_repo="$RL_REPO"

  # ── THE FIXTURE. A repo with a base branch, a head branch carrying a task commit, a plan, a review
  #    record, and a stubbed `gh` that answers `pr view --json reviews|author` from files. The stub is
  #    PATH-scoped INSIDE the fixture only (threat T4) — it is never installed globally.
  fx_new() {   # $1 = name -> prints the repo dir
    _r="$_fx/$1"; mkdir -p "$_r/docs/plans" "$_r/docs/reviews" "$_r/conformance"
    git -C "$_r" init -q 2>/dev/null || git init -q "$_r"
    # ★ THE INITIAL BRANCH NAME IS PINNED, NOT INHERITED — and this was a REAL non-hermeticity, caught
    # by `selftest-hermetic.sh --touched` face (a) and by CI, not by any local run. `git init` takes the
    # branch name from `init.defaultBranch`, which is GLOBAL CONFIG: a developer tree says `main`, a
    # stripped-env runner says `master`. The two no-base cases below delete the base branch to make
    # rl_base fail — and on the runner they deleted `main` while `master` still existed, so a base
    # resolved after all, RL-NO-BASE was never reached, and both cases redded for the wrong reason
    # (RL-TRAILER). `symbolic-ref` is used rather than `git init -b`: it works on every git version and
    # on a repo that already exists.
    git -C "$_r" symbolic-ref HEAD refs/heads/main
    git -C "$_r" config user.email t@e; git -C "$_r" config user.name t
    printf 'base\n' > "$_r/README.md"
    printf 'WAIVER-0001 — a real waiver\n' > "$_r/WAIVER-REGISTER.md"
    printf 'x() { :; }\ntest_review_lane_grades() { :; }\n' > "$_r/conformance/probe.sh"
    # SWAS-300: the BASE carries the four neutral seat definitions, so rule 10 has a vocabulary to read.
    mkdir -p "$_r/agents"
    for _fx_s in engineer:builder orchestrator:conductor reviewer:reviewer security:security; do
      printf '# %s (fixture definition)\n\n## Role\nSeat role: %s\n' "${_fx_s%%:*}" "${_fx_s##*:}" > "$_r/agents/${_fx_s%%:*}.agent.md"
    done
    git -C "$_r" add -A >/dev/null; git -C "$_r" commit -qm base >/dev/null
    git -C "$_r" branch -f main HEAD >/dev/null 2>&1 || true
    printf '%s\n' "$_r"
  }
  fx_plan() {
    mkdir -p "$(dirname "$2")"
    { printf '# Plan record — FIXTURE\n\n## Task list\n'
      printf '1. Build the grader and watch its fixtures red first.\n'
      printf '2. Extend the review record template with the graded shape.\n'
      printf '3. Wire the lane into CI and declare the required context.\n'
      printf '\n## Design-promised controls\n| control | expected discharge |\n|---|---|\n'
      printf '| an unattested approval is refused | `conformance/probe.sh::test_review_lane_grades` |\n'
    } > "$2"
  }
  # fx_record <file> <builder> <reviewer> <round-sha> <verdict> [findings] [controls] [security-line] [rounds-seat]
  fx_record() {
    _f=$1; mkdir -p "$(dirname "$_f")"
    { printf '# Review record — FIXTURE — PR #1 | branch feat/x\n'
      printf 'Builder: %s\n' "$2"
      printf 'Reviewer: %s\n' "$3"
      printf '\n## Rounds\n| commit | reviewer seat | verdict | findings (n) |\n|---|---|---|---|\n'
      printf '| %s | %s | %s | 0 |\n' "$4" "${9:-reviewer}" "$5"
      printf '\n## Findings\n| id | file:line | severity | disposition |\n|---|---|---|---|\n'
      printf '%s' "${6:-}"
      printf '\n## Design-promised controls\n| control | discharged by |\n|---|---|\n'
      printf '%s\n' "${7:-"| the grader refuses an unattested approval | \`conformance/probe.sh::test_review_lane_grades\` |"}"
      printf '\n\n## Security review\n%s\n' "${8:-ran — seat security, verdict: no findings}"
    } > "$_f"
  }
  # (`fx_gh` — a `gh` stub answering `pr view --json reviews|author` from files — and `rv`, which built
  # the review JSON, are DELETED with the leg they fed. The only `gh` stub left in this suite is the
  # ABORTING one in the `forge never read` case, whose job is to prove it is never called.)
  # run the gate inside a fixture, with the fixture's own .bin first on PATH
  fx_run() {   # $1 = repo, $2 = mode(pr|prepush), [$3 = base ref; '-' means NONE (the S-M1 no-base case)]
    RL_REPO="$1"; _rl_mode="$2"; _rl_pr=1; _rl_head=$(git -C "$1" rev-parse HEAD)
    case "${3:-main}" in
      -) _rl_base_ref="" ;;
      *) _rl_base_ref="${3:-main}" ;;
    esac
    # The gate's own output is CAPTURED, not discarded: a failing leg prints it (ck), so a red names
    # the refusal token rather than only the rc. A selftest that hides the reason costs an hour.
    _o=0; ( PATH="$1/.bin:$PATH"; rl_run ) > "$_fx/last.log" 2>&1 || _o=$?
    RL_REPO="$_sv_repo"; printf '%s' "$_o"
  }
  # fx_strip_base — remove EVERY branch except the checked-out one, then ASSERT that rl_base really
  # cannot resolve. The two no-base cases depend on a PRECONDITION, and a precondition a fixture merely
  # hopes for is how both of them passed locally and redded on the runner for an unrelated reason:
  # `git branch -D main` deleted a branch that a stripped-env `git init` had never created (it made
  # `master`), so a base still resolved. Deleting by enumeration removes the guess; asserting removes
  # the hope. If this assertion ever fires, the CASES below are void — not merely failing.
  fx_strip_base() {   # $1 = repo
    _cur=$(git -C "$1" symbolic-ref --short HEAD)
    git -C "$1" for-each-ref --format='%(refname:short)' refs/heads | while IFS= read -r _b; do
      [ "$_b" = "$_cur" ] || git -C "$1" branch -D "$_b" >/dev/null 2>&1 || true
    done
    RL_REPO="$1"; _rl_base_ref=""
    if rl_base "$(git -C "$1" rev-parse HEAD)" >/dev/null 2>&1; then
      echo "selftest FAIL: fx_strip_base left a resolvable base in $1 — the no-base cases below would grade a DIFFERENT question than their labels claim"; st=1
    fi
    RL_REPO="$_sv_repo"
  }

  # build a fully-conformant head, then let the caller perturb one thing
  fx_full() {   # $1 name -> repo dir, leaves $HEADSHA set
    _r=$(fx_new "$1")
    if [ "${2:-}" = olddoc ]; then   # the BASE carries an old design doc with no lens table
      mkdir -p "$_r/docs/architecture"; printf '# old design\nno table\n' > "$_r/docs/architecture/2026-01-01-old-design.md"
      git -C "$_r" add -A >/dev/null; git -C "$_r" commit -qm olddoc >/dev/null
    fi
    # SWAS-300: a BASE whose neutral definitions are broken (the vocabulary mutants N6, N8, N9).
    case "${2:-}" in
      upper) printf '# engineer\n\n## Role\nSeat role: Builder\n' > "$_r/agents/engineer.agent.md" ;;
      dup)  printf '# security\n\n## Role\nSeat role: reviewer\n' > "$_r/agents/security.agent.md" ;;
      zero) printf '# engineer\n\n## Role\nno role line here\n' > "$_r/agents/engineer.agent.md" ;;
      two)  printf '# engineer\n\n## Role\nSeat role: builder\nSeat role: security\n' > "$_r/agents/engineer.agent.md" ;;
    esac
    case "${2:-}" in
      dup|zero|two|upper) git -C "$_r" add -A >/dev/null; git -C "$_r" commit -qm "broken seat definitions" >/dev/null ;;
    esac
    git -C "$_r" checkout -qb feat/x
    printf 'code\n' > "$_r/conformance/thing.sh"; git -C "$_r" add -A >/dev/null
    git -C "$_r" commit -qm "task

Kit-Row: FIXTURE
Kit-Class: control-plane" >/dev/null
    _task=$(git -C "$_r" rev-parse HEAD)
    fx_plan "$_r" "$_r/docs/plans/2026-09-04-fixture.md"
    fx_record "$_r/docs/reviews/2026-09-04-fixture.md" builder reviewer "$_task" APPROVE
    git -C "$_r" add -A >/dev/null
    git -C "$_r" commit -qm "record

Kit-Row: FIXTURE
Kit-Class: control-plane
Kit-Plan: docs/plans/2026-09-04-fixture.md
Kit-Review: docs/reviews/2026-09-04-fixture.md" >/dev/null
    printf '%s' "$_r"
  }
  # ck <label> <expected-rc> <actual-rc> [expected-token]
  # THE TOKEN ARGUMENT IS THE POINT, not decoration. An rc-only assertion is satisfied by ANY refusal,
  # so a fixture meant to exercise the attestation leg can pass because the plan file was a stub two
  # legs earlier — measured during this build, on eight legs at once. Each negative therefore names the
  # refusal token it is FOR, and a red for a different reason is a selftest failure.
  ck() {
    if [ "$2" != "$3" ]; then
      echo "selftest FAIL: $1 expected rc $2, got $3"; sed 's/^/    | /' "$_fx/last.log" 2>/dev/null || true; st=1; return 0
    fi
    if [ -n "${4:-}" ] && ! grep -qF "$4" "$_fx/last.log" 2>/dev/null; then
      echo "selftest FAIL: $1 gave the right rc $3 for the WRONG reason — expected the token '$4'"
      sed 's/^/    | /' "$_fx/last.log" 2>/dev/null || true; st=1; return 0
    fi
    echo "OK: $1 -> rc $3${4:+" ($4)"}"; return 0
  }
  # ── THE `--pr` CASES. There is no approval case left to write: since
  # `REVIEW-LANE-WAITING-IS-GREEN` nothing here reads the forge, so what `--pr` grades is what
  # `--pre-push` grades. The two cases below are the ones that PIN that — one proves the forge is
  # never touched, the other proves the waiting state is gone — and every structural negative further
  # down runs through `--pre-push`, which is the same code path.

  # (+) POSITIVE — a full record + plan at the graded head -> 0, with no forge state anywhere.
  r=$(fx_full pos)
  ck "full record + plan at the graded head" 0 "$(fx_run "$r" pr)" "the approval is branch protection's"

  # (+) LIVENESS — THE FORGE IS NEVER READ (design §6). A `gh` stub that records its own invocation
  #     and then aborts sits first on PATH inside the fixture; a `--pr` run must pass without ever
  #     waking it. LOAD-BEARING NEGATIVE: re-introduce one `gh pr view` call and the stub fires, so the
  #     case reds twice over — the rc is no longer 0 and the sentinel file appears.
  r=$(fx_full noforge)
  mkdir -p "$r/.bin"
  printf '#!/bin/sh\n: > "%s"\nexit 99\n' "$r/.bin/gh-was-called" > "$r/.bin/gh"
  chmod +x "$r/.bin/gh"
  ck "forge never read" 0 "$(fx_run "$r" pr)" "grading head"
  if [ -e "$r/.bin/gh-was-called" ]; then
    echo "selftest FAIL: forge never read — the gh stub WAS invoked; --pr must read nothing from the forge"; st=1
  else
    echo "OK: forge never read — the aborting gh stub was never invoked"
  fi

  # (+) NO WAITING ARM. The same well-formed fixture with no approvals anywhere. Until
  #     REVIEW-LANE-WAITING-IS-GREEN this returned rc 1 with a WAITING verdict; a job has no yellow, so
  #     that rc rendered RED and only a manual re-run after the Approve ever cleared it. rc 0 now, and
  #     the word itself must not appear in the output.
  r=$(fx_full nowait)
  ck "no WAITING arm" 0 "$(fx_run "$r" pr)"
  if grep -q 'WAITING' "$_fx/last.log" 2>/dev/null; then
    echo "selftest FAIL: no WAITING arm — the --pr output still contains 'WAITING'"; st=1
  else
    echo "OK: no WAITING arm — the --pr output carries no waiting state"
  fi

  # (The cases that lived here — no approval, an author-only approval, an approval on a stale head, a
  # DISMISSED review, each expecting rc 1 and a WAITING verdict — are DELETED with the leg that
  # produced them. Their questions are the forge's now, and `branch-protection.sh`'s new arms are what
  # assert that the forge is configured to ask them.)

  # ── STRUCTURAL NEGATIVES (graded before the forge is ever read; --pre-push isolates them).
  # (+) --pre-push on a conformant head passes — the same question `--pr` asks, from a local head.
  r=$(fx_full pp); ck "--pre-push on a conformant head" 0 "$(fx_run "$r" prepush)"

  # (−) no Kit-Review trailer on a code PR.
  r=$(fx_new notrl); git -C "$r" checkout -qb feat/x
  printf 'code\n' > "$r/conformance/thing.sh"; git -C "$r" add -A >/dev/null; git -C "$r" commit -qm task >/dev/null
  ck "no Kit-Review on a code change" 2 "$(fx_run "$r" prepush)" RL-TRAILER

  # (+) docs-only ORDINARY is N-A — the classifier's cut, printed.
  r=$(fx_new na); git -C "$r" checkout -qb feat/x
  printf 'prose\n' > "$r/NOTES.md"; git -C "$r" add -A >/dev/null; git -C "$r" commit -qm docs >/dev/null
  ck "docs-only ordinary" 0 "$(fx_run "$r" prepush)" "N-A — ordinary AND docs-only"

  # (−) the record path is the TEMPLATE itself (it still carries the marker sentence).
  r=$(fx_full tmpl)
  printf '%s\n' "$RL_TEMPLATE_MARKER" >> "$r/docs/reviews/2026-09-04-fixture.md"
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "record still carries the template marker" 2 "$(fx_run "$r" prepush)" RL-RECORD-IS-TEMPLATE

  # (−) Builder == Reviewer.
  r=$(fx_full same); t=$(git -C "$r" rev-parse HEAD~1)
  fx_record "$r/docs/reviews/2026-09-04-fixture.md" same-seat same-seat "$t" APPROVE
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "Builder == Reviewer" 2 "$(fx_run "$r" prepush)" RL-SAME-IDENTITY

  # (−) a round commit OUTSIDE the PR (a base commit — leg 2 of containment is what catches it).
  r=$(fx_full out); b=$(git -C "$r" rev-parse main)
  fx_record "$r/docs/reviews/2026-09-04-fixture.md" builder reviewer "$b" APPROVE
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "round commit already in the base" 2 "$(fx_run "$r" prepush)" RL-ROUND-OUTSIDE

  # (−) an OPEN round — NEEDS-FIXES with no later APPROVE.
  r=$(fx_full open); t=$(git -C "$r" rev-parse HEAD~1)
  fx_record "$r/docs/reviews/2026-09-04-fixture.md" builder reviewer "$t" NEEDS-FIXES
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "open round (NEEDS-FIXES, no APPROVE)" 2 "$(fx_run "$r" prepush)" RL-OPEN-ROUND

  # (+) RECORD-GRAMMAR-ESSENTIALS (owner Q1): a CODE commit after the closing APPROVE is FORM, not
  #     substance — it WARNs (`WARN: RL-OPEN-ROUND: …`, same token operators already grep) and rc stays 0.
  #     It was rc 2; this leg is RED against that code. RL-OPEN-ROUND for a genuinely open round stays
  #     FAIL (the "open round" leg above).
  r=$(fx_full reopen)
  printf 'more\n' > "$r/conformance/late.sh"; git -C "$r" add -A >/dev/null
  git -C "$r" commit -qm "late code

Kit-Row: FIXTURE
Kit-Class: control-plane
Kit-Plan: docs/plans/2026-09-04-fixture.md
Kit-Review: docs/reviews/2026-09-04-fixture.md" >/dev/null
  ck "code commit after the closing APPROVE warns, does not fail" 0 "$(fx_run "$r" prepush)" "WARN: RL-OPEN-ROUND: commits after the closing APPROVE"

  # (+) the second demoted rule: a docs-only commit after the APPROVE that is OUTSIDE the bookkeeping
  #     set (NOTES.md is not under docs/reviews/, docs/plans/ or BACKLOG.md) also WARNs, rc 0.
  r=$(fx_full reopenpath)
  printf 'prose\n' > "$r/NOTES.md"; git -C "$r" add -A >/dev/null
  git -C "$r" commit -qm "late prose

Kit-Row: FIXTURE
Kit-Class: control-plane
Kit-Plan: docs/plans/2026-09-04-fixture.md
Kit-Review: docs/reviews/2026-09-04-fixture.md" >/dev/null
  ck "path outside the bookkeeping set after the APPROVE warns, does not fail" 0 "$(fx_run "$r" prepush)" "WARN: RL-OPEN-ROUND: 'NOTES.md' changed after the closing APPROVE"

  # (+) the WARN is ALSO an annotation in Actions, where the approver looks (design §2).
  _ga_was="${GITHUB_ACTIONS-__unset__}"
  export GITHUB_ACTIONS=true
  ck "WARN under GITHUB_ACTIONS=true still rc 0" 0 "$(fx_run "$r" prepush)" "WARN: RL-OPEN-ROUND"
  if grep -qF '::warning::' "$_fx/last.log" 2>/dev/null; then
    echo "OK: the WARN is emitted as a ::warning:: annotation under GITHUB_ACTIONS=true"
  else
    echo "selftest FAIL: no ::warning:: annotation under GITHUB_ACTIONS=true"; sed 's/^/    | /' "$_fx/last.log"; st=1
  fi
  if [ "$_ga_was" = "__unset__" ]; then unset GITHUB_ACTIONS; else export GITHUB_ACTIONS="$_ga_was"; fi

  # (−) a finding with no disposition.
  r=$(fx_full find); t=$(git -C "$r" rev-parse HEAD~1)
  fx_record "$r/docs/reviews/2026-09-04-fixture.md" builder reviewer "$t" APPROVE '| F1 | a.sh:1 | HIGH | noted |
'
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "finding with no disposition" 2 "$(fx_run "$r" prepush)" RL-FINDING-DISPOSITION

  # (−) a waived finding citing a WAIVER id that is not in the register.
  r=$(fx_full waiv); t=$(git -C "$r" rev-parse HEAD~1)
  fx_record "$r/docs/reviews/2026-09-04-fixture.md" builder reviewer "$t" APPROVE '| F1 | a.sh:1 | LOW | waived — WAIVER-9999 |
'
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "waiver id absent from the register" 2 "$(fx_run "$r" prepush)" RL-WAIVER-MISSING

  # (−) a control row citing a path::test that does not resolve.
  r=$(fx_full ctl); t=$(git -C "$r" rev-parse HEAD~1)
  fx_record "$r/docs/reviews/2026-09-04-fixture.md" builder reviewer "$t" APPROVE '' '| a control | `conformance/probe.sh::test_that_does_not_exist` |
'
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "control cites an unresolvable path::test" 2 "$(fx_run "$r" prepush)" "RL-CONTROL-UNRESOLVED: control 'a control' cites test"

  # SAST-PARSE-MERGE-TOOL: one cell per disposition / control arm whose case pattern was rewritten (a quoted literal where a
  # backslash-blank stood). Each pins ITS OWN refusal token, plus a liveness partner; they pin behaviour, not red-first.
  r=$(fx_full accshort); t=$(git -C "$r" rev-parse HEAD~1)
  fx_record "$r/docs/reviews/2026-09-04-fixture.md" builder reviewer "$t" APPROVE '| F1 | a.sh:1 | LOW | accepted - ok |
'
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "accepted with no reason of substance" 2 "$(fx_run "$r" prepush)" "is accepted with no reason of substance"
  r=$(fx_full acclong); t=$(git -C "$r" rev-parse HEAD~1)
  fx_record "$r/docs/reviews/2026-09-04-fixture.md" builder reviewer "$t" APPROVE '| F1 | a.sh:1 | LOW | accepted - the reviewer judged this cosmetic and unreachable |
'
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "accepted with a reason of substance" 0 "$(fx_run "$r" prepush)" "the approval is branch protection's"
  r=$(fx_full fixabsent); t=$(git -C "$r" rev-parse HEAD~1)
  fx_record "$r/docs/reviews/2026-09-04-fixture.md" builder reviewer "$t" APPROVE '| F1 | a.sh:1 | LOW | fixed deadbeefdeadbeef |
'
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "fixed <sha> naming no commit" 2 "$(fx_run "$r" prepush)" "which is not a commit in this repository"
  r=$(fx_full fixword); t=$(git -C "$r" rev-parse HEAD~1)
  fx_record "$r/docs/reviews/2026-09-04-fixture.md" builder reviewer "$t" APPROVE '| F1 | a.sh:1 | LOW | fixed zzz |
'
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "fixed <non-hex> is no disposition" 2 "$(fx_run "$r" prepush)" "carries no disposition in the grammar"
  r=$(fx_full nbshort); t=$(git -C "$r" rev-parse HEAD~1)
  fx_record "$r/docs/reviews/2026-09-04-fixture.md" builder reviewer "$t" APPROVE '' '| a control | not built, because no |
'
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "control 'not built, because' with no reason of substance" 2 "$(fx_run "$r" prepush)" "says 'not built, because' with no reason of substance"
  r=$(fx_full nblong); t=$(git -C "$r" rev-parse HEAD~1)
  fx_record "$r/docs/reviews/2026-09-04-fixture.md" builder reviewer "$t" APPROVE '' '| a control | not built, because the pinned test is deferred to a follow-up card |
'
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "control 'not built, because' with a reason of substance" 0 "$(fx_run "$r" prepush)" "the approval is branch protection's"

  # (−) a control discharged by a COMMENT line only (vet M5's executable-line rule).
  r=$(fx_full cmt); t=$(git -C "$r" rev-parse HEAD~1)
  printf '# test_comment_only is mentioned only here\n' > "$r/conformance/probe.sh"
  fx_record "$r/docs/reviews/2026-09-04-fixture.md" builder reviewer "$t" APPROVE '' '| a control | `conformance/probe.sh::test_comment_only` |
'
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "control discharged by a comment line" 2 "$(fx_run "$r" prepush)" "appears on no executable line"

  # (−) the security-review section is ABSENT.
  r=$(fx_full nosec); t=$(git -C "$r" rev-parse HEAD~1)
  fx_record "$r/docs/reviews/2026-09-04-fixture.md" builder reviewer "$t" APPROVE '' '' ''
  sed '/^## Security review$/,+1d' "$r/docs/reviews/2026-09-04-fixture.md" > "$r/.t" && mv "$r/.t" "$r/docs/reviews/2026-09-04-fixture.md"
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "security review section absent" 2 "$(fx_run "$r" prepush)" RL-SECURITY-ABSENT

  # (−) a security WAIVER carrying only three of the four D-240904-1 criteria.
  r=$(fx_full w3); t=$(git -C "$r" rev-parse HEAD~1)
  fx_record "$r/docs/reviews/2026-09-04-fixture.md" builder reviewer "$t" APPROVE '' '' \
    'waived — no-untrusted-input · no-new-permission · no-control-plane-surface'
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "security waiver with three of four criteria" 2 "$(fx_run "$r" prepush)" "RL-SECURITY-WAIVER-INCOMPLETE: the security waiver omits the criterion 'no-operator-shell'"

  # (−) REGRESSION, and it reproduced a real defect in this build: the state tokens were matched as
  #     SUBSTRINGS, so a section reading "no review was warranted" contained `ran` and was graded as a
  #     completed review that merely owed a verdict word. Line-anchored now; this case is red before
  #     that fix and green after.
  r=$(fx_full ransub); t=$(git -C "$r" rev-parse HEAD~1)
  fx_record "$r/docs/reviews/2026-09-04-fixture.md" builder reviewer "$t" APPROVE '' '' \
    'no review was warranted here, and the transparent guarantee is that nothing untrusted is read'
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "prose containing the substring 'ran' is not a security verdict" 2 "$(fx_run "$r" prepush)" RL-SECURITY-STATE

  # (−) a SYMLINKED record path — head-side confinement (design section 7).
  r=$(fx_full link)
  rm "$r/docs/reviews/2026-09-04-fixture.md"
  ln -s ../../README.md "$r/docs/reviews/2026-09-04-fixture.md"
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "record path is a symlink" 2 "$(fx_run "$r" prepush)" RL-PATH-UNTRACKED

  # (−) a traversing Kit-Review value never reaches git.
  r=$(fx_full trav)
  git -C "$r" commit -q --amend -m "record

Kit-Row: FIXTURE
Kit-Class: control-plane
Kit-Plan: docs/plans/2026-09-04-fixture.md
Kit-Review: docs/reviews/../../etc/passwd.md" >/dev/null
  ck "traversing Kit-Review value" 2 "$(fx_run "$r" prepush)" RL-PATH
  # SAST-PARSE-MERGE-TOOL: the other three rl_path_ok arms (charset, prefix, '.md' suffix), one cell each: all three assert `RL-PATH: `, and each value fails exactly one arm.
  _bpn=0
  for _bp in 'docs/reviews/a b.md' 'docs/plans/2026-09-04-fixture.md' 'docs/reviews/2026-09-04-fixture.txt'; do
    _bpn=$((_bpn + 1)); r=$(fx_full "badpath$_bpn")
    git -C "$r" commit -q --amend -m "record

Kit-Row: FIXTURE
Kit-Class: control-plane
Kit-Plan: docs/plans/2026-09-04-fixture.md
Kit-Review: $_bp" >/dev/null
    ck "Kit-Review value '$_bp' is refused by the path confinement" 2 "$(fx_run "$r" prepush)" "RL-PATH: "
  done
  # SAST-PARSE-MERGE-TOOL: rl_base refuses a flag-shaped or metacharacter --base-ref (never handed to git): in --pr mode no
  # base means RL-NO-BASE. The conformant head passes with the real base 'main' (the cell above), so the refusal is the ref's.
  r=$(fx_full basedash)
  ck "a --base-ref starting with '-' is refused" 2 "$(fx_run "$r" pr -x)" RL-NO-BASE
  # The metacharacter ref is a REAL branch at the base (git allows ';'), so only rl_base's charset arm can refuse it.
  r=$(fx_full basemeta); git -C "$r" branch 'ma;in' main
  ck "a --base-ref with a metacharacter is refused" 2 "$(fx_run "$r" pr 'ma;in')" RL-NO-BASE
  r=$(fx_full basegood)
  ck "a plain --base-ref resolves" 0 "$(fx_run "$r" pr main)" "the approval is branch protection's"

  # (+) CONSOLIDATED PR — BOTH records are graded (rules 2-7). Under the typed line this case came in
  #     pairs (one record named, both named) because the approver had to enumerate them; `D-240904-2`
  #     removed the enumeration and `REVIEW-LANE-WAITING-IS-GREEN` removed the approval read, so what
  #     remains is the part that was always load-bearing here: the tree's completeness is the
  #     Kit-Review trailer's job, and every record it names is graded. The SECOND record is
  #     deliberately well-formed here — the negative that matters is the next case, where it is not.
  r=$(fx_full cons); t=$(git -C "$r" rev-parse HEAD~1)
  fx_record "$r/docs/reviews/2026-09-04-second.md" builder reviewer "$t" APPROVE
  git -C "$r" add -A >/dev/null
  git -C "$r" commit -q --amend -m "record

Kit-Row: FIXTURE
Kit-Class: control-plane
Kit-Plan: docs/plans/2026-09-04-fixture.md
Kit-Review: docs/reviews/2026-09-04-fixture.md,docs/reviews/2026-09-04-second.md" >/dev/null
  ck "consolidated PR — both records graded" 0 "$(fx_run "$r" pr)"

  # (−) CONSOLIDATED PR where the SECOND record is defective. This is what stops a consolidated
  #     Kit-Review from loosening the set: one record in the set is not graded-clean, and rules 2-7
  #     refuse it. Without this leg "one trailer covers the set" would mean the set is unchecked.
  r=$(fx_full cons2); t=$(git -C "$r" rev-parse HEAD~1)
  fx_record "$r/docs/reviews/2026-09-04-second.md" same-seat same-seat "$t" APPROVE
  git -C "$r" add -A >/dev/null
  git -C "$r" commit -q --amend -m "record

Kit-Row: FIXTURE
Kit-Class: control-plane
Kit-Plan: docs/plans/2026-09-04-fixture.md
Kit-Review: docs/reviews/2026-09-04-fixture.md,docs/reviews/2026-09-04-second.md" >/dev/null
  ck "consolidated PR — the second record is self-reviewed" 2 "$(fx_run "$r" pr)" RL-SAME-IDENTITY

  # ── FIX-ROUND CASES (reviewer + security seats, 2026-09-04) ───────────────────────────────────
  # (+) R-M1 — A RECORD DERIVED FROM THE REAL SHIPPED TEMPLATE must grade. The first build's template
  #     used `###` for the five graded headings while rl_section matches `^## `, so EVERY record an
  #     adopter produced by following the template would have redded with "no review round" — the
  #     grader and its own template disagreed, and no fixture noticed because every fixture emitted
  #     its own markdown. This case reads THE SHIPPED FILE, so the two can never drift again.
  r=$(fx_full tmplok); t=$(git -C "$r" rev-parse HEAD~1)
  grep -vF "$RL_TEMPLATE_MARKER" "$DIR/templates/REVIEW-RECORD-TEMPLATE.md" \
    | sed -e 's/^Builder: ___/Builder: builder/' \
          -e 's/^Reviewer: ___/Reviewer: reviewer-seat/' \
          -e '/^| ___/d' \
          -e 's/^ran — seat security, verdict: ___/ran — seat security, verdict: no findings/' \
    | awk -v sha="$t" '{print} /^## Rounds$/{rr=1} rr==1 && /^\|---/{print "| " sha " | reviewer | APPROVE | 0 |"; rr=0}' \
    > "$r/docs/reviews/2026-09-04-fixture.md"
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "a record derived from the SHIPPED template grades" 0 "$(fx_run "$r" prepush)" "structural pass"

  # (−) R-M2 — THE SHIPPED TEMPLATE ITSELF, verbatim, must be refused. The marker sentence was LINE-
  #     WRAPPED in the template while the grader matches it with grep -F, so RL-RECORD-IS-TEMPLATE
  #     could never fire on the real file: the check was live, its subject was unreachable.
  r=$(fx_full tmplraw)
  cp "$DIR/templates/REVIEW-RECORD-TEMPLATE.md" "$r/docs/reviews/2026-09-04-fixture.md"
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "the shipped template used AS the record" 2 "$(fx_run "$r" prepush)" RL-RECORD-IS-TEMPLATE

  # (R-M3, the ROLE SWAP case — a non-author approval whose login was the head commit's own committer
  #  identity — is DELETED with `rl_role_swap`. Its successor is `require_last_push_approval`, which is
  #  the forge's rule, not this script's, and the case that pins it lives in
  #  `conformance/branch-protection.sh`'s selftest instead.)

  # (−) m4 — a round citing a sha that is not in this repository at all.
  r=$(fx_full unk)
  fx_record "$r/docs/reviews/2026-09-04-fixture.md" builder reviewer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa APPROVE
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "round cites a sha not in the repository" 2 "$(fx_run "$r" prepush)" RL-ROUND-UNKNOWN

  # (−) m4 — the plan file is a stub.
  r=$(fx_full planstub)
  printf '# Plan\n' > "$r/docs/plans/2026-09-04-fixture.md"
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "plan file is a stub" 2 "$(fx_run "$r" prepush)" RL-PLAN-STUB

  # (−) m4 — the record is over the size bound.
  # ⚠️ THE PADDING IS DERIVED FROM $RL_MAX_RECORD_BYTES, NOT A FIXED LINE COUNT. It used to be a flat
  # 400 lines, which comfortably cleared 8192 and would still have cleared 16384 — so the leg would
  # have kept passing while saying "8 KB", and the next raise could have carried it past the real bound
  # into a silent always-green. Sized from the constant, the case tracks every future change to it, and
  # the assertion below pins that the padded record really is over.
  r=$(fx_full big)
  awk -v n="$RL_MAX_RECORD_BYTES" 'BEGIN{for(i=0;i<(n/40)+40;i++) print "padding padding padding padding padd"}' \
    >> "$r/docs/reviews/2026-09-04-fixture.md"
  [ "$(wc -c < "$r/docs/reviews/2026-09-04-fixture.md" | tr -d ' ')" -gt "$RL_MAX_RECORD_BYTES" ] \
    || { echo "selftest FAIL: the oversize fixture is NOT over $RL_MAX_RECORD_BYTES bytes — the leg would pass vacuously"; st=1; }
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "record exceeds the $RL_MAX_RECORD_BYTES-byte bound" 2 "$(fx_run "$r" prepush)" RL-RECORD-OVERSIZE

  # (−) m4 — the identity lines still carry the template's `___`.
  r=$(fx_full ph); t=$(git -C "$r" rev-parse HEAD~1)
  fx_record "$r/docs/reviews/2026-09-04-fixture.md" ___ reviewer-seat "$t" APPROVE
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "identity line still holds the ___ placeholder" 2 "$(fx_run "$r" prepush)" RL-RECORD-PLACEHOLDER

  # (The RL-FORGE-UNREADABLE case — a broken `gh` must not make the attestation half disappear — is
  #  DELETED. Its whole premise was that the gate reads the forge; the `forge never read` case above is
  #  its inverse and its replacement, asserting that a `gh` which would abort on contact never runs.)

  # (−) S-L3 — `fixed <sha>` citing a commit that is already in the base. A disposition is a citation;
  #     an uncheckable one disposes of a HIGH finding with a string.
  r=$(fx_full fixout); t=$(git -C "$r" rev-parse HEAD~1); b=$(git -C "$r" rev-parse main)
  fx_record "$r/docs/reviews/2026-09-04-fixture.md" builder reviewer "$t" APPROVE "| F1 | a.sh:1 | HIGH | fixed $b |
"
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "a fix sha outside this change" 2 "$(fx_run "$r" prepush)" RL-FIX-OUTSIDE

  # (−) S-M1 — NO BASE + a docs-only HEAD COMMIT on top of code. Without a merge-base the change-set
  #     falls back to the head commit's own file list, which is all-.md here — so the class derives
  #     ordinary, docs-only says true, and the gate would take the N-A cut on a branch it never saw.
  #     The cut is DISABLED without a base; the artifacts are still owed.
  r=$(fx_new nobase); git -C "$r" checkout -qb feat/x
  printf 'code\n' > "$r/conformance/thing.sh"; git -C "$r" add -A >/dev/null; git -C "$r" commit -qm code >/dev/null
  printf 'prose\n' > "$r/NOTES.md"; git -C "$r" add -A >/dev/null; git -C "$r" commit -qm docs >/dev/null
  fx_strip_base "$r"
  ck "no base + docs-only head commit does NOT buy the scope cut" 2 "$(fx_run "$r" prepush -)" "scope cut is DISABLED"

  # (−) S-M1, the CI half — no base in --pr mode is a broken checkout, not a shallow clone.
  # ⚠️ THIS CASE IS ALSO THE LEG-ORDER PIN. Its head carries NO trailers at all, so if the base/scope
  # legs ever move BELOW the trailer legs it reds with RL-TRAILER instead and the token assertion
  # catches it — which is exactly how the runner reported this file's own non-hermeticity.
  r=$(fx_new nobasepr); git -C "$r" checkout -qb feat/x
  printf 'code\n' > "$r/conformance/thing.sh"; git -C "$r" add -A >/dev/null; git -C "$r" commit -qm code >/dev/null
  fx_strip_base "$r"
  ck "no base in --pr mode" 2 "$(fx_run "$r" pr -)" RL-NO-BASE

  # ── RECORD-GRAMMAR-ESSENTIALS — THE XS/S ORDINARY CEILING (design §3). ─────────────────────────────
  # fx_ord <name> <base-size> <head-size> <touch> <row-id|-> <code-path> [backend-text]
  #   Builds a repo whose BASE (main) carries a BACKLOG.md with row `XSROW` at <base-size>, and a feat/x
  #   head with ONE code commit at <code-path> carrying `Kit-Row: <row-id>` + `Kit-Class: ordinary`
  #   (no Kit-Plan / Kit-Review — the point). <touch> = 1 rewrites the row's Intent (and Size to
  #   <head-size>) on the head; 2 also boards a brand-new `NEWROW`; 0 leaves the board alone.
  #   <code-path> src/app.js derives ORDINARY and is not docs-only; conformance/thing.sh is control-plane.
  #   [backend-text] seeds a base CLAUDE.md `Backlog backend:` line. Prints the repo dir.
  fx_board() {   # $1 = file, $2 = size, $3 = intent text, [$4 = done | dup]
    printf '# Backlog\n\n## Ready\n| Item | Intent | Size |\n|---|---|---|\n' > "$1"
    [ "${4:-}" = "done" ] || printf '| `XSROW` · a slice | %s | %s |\n' "$3" "$2" >> "$1"
    printf '| `OTHER` · unrelated | o | XS |\n' >> "$1"
    [ "${4:-}" != dup ] || printf '\n## In Progress\n| Item | Owner |\n|---|---|\n| `XSROW` · dup | me |\n' >> "$1"
    # the `done` variant's Done table CARRIES a Size column (XSROW sized there), so the ONLY thing
    # that makes that leg owed is the Done/Released check, not a missing Size column.
    if [ "${4:-}" = "done" ]; then printf '\n## Done\n| Item | Closed | Size |\n|---|---|---|\n' >> "$1"
    else printf '\n## Done\n| Item | Closed | Retro/outcome |\n|---|---|---|\n' >> "$1"; fi
    [ "${4:-}" != "done" ] || printf '| `XSROW` · a slice | %s | %s |\n' "$3" "$2" >> "$1"
  }
  fx_ord() {
    _r=$(fx_new "$1")
    fx_board "$_r/BACKLOG.md" "$2" "base intent" "${8:-}"
    [ -z "${7:-}" ] || printf 'Backlog backend: %s\n' "$7" > "$_r/CLAUDE.md"
    git -C "$_r" add -A >/dev/null; git -C "$_r" commit -qm board >/dev/null
    git -C "$_r" checkout -qb feat/x
    mkdir -p "$(dirname "$_r/$6")"; printf 'code\n' > "$_r/$6"
    if [ "$4" != 0 ]; then
      case "$4" in
        3|4) fx_board "$_r/BACKLOG.md" "$3" "base intent" "${8:-}" ;;   # the row ITSELF is unchanged
        *)   fx_board "$_r/BACKLOG.md" "$3" "head intent" "${8:-}" ;;
      esac
      [ "$4" != 2 ] || printf '| `NEWROW` · new | n | XS |\n' >> "$_r/BACKLOG.md"
      [ "$4" != 3 ] || printf '> Order: `XSROW` first, then `OTHER`\n' >> "$_r/BACKLOG.md"
      [ "$4" != 4 ] || printf '| `OTHER2` · follows `XSROW` | x | XS |\n' >> "$_r/BACKLOG.md"
    fi
    _m="slice"
    if [ "$5" = - ]; then _m="$_m

Kit-Class: ordinary"; else _m="$_m

Kit-Row: $5
Kit-Class: ordinary"; fi
    git -C "$_r" add -A >/dev/null; git -C "$_r" commit -qm "$_m" >/dev/null
    printf '%s' "$_r"
  }

  # (+) XS ordinary, no trailers, row touched by this PR's own board diff, size read at the merge-base
  #     -> rc 0 with the NOTE. RED against the code that preceded this slice (it demanded the trailers).
  r=$(fx_ord xs XS XS 1 XSROW src/app.js)
  ck "XS ordinary, no trailers, row touched -> no plan/record owed" 0 "$(fx_run "$r" prepush)" "XS/S ordinary (XSROW, size XS): no plan/record owed"
  r=$(fx_ord sz S S 1 XSROW src/app.js)
  ck "S ordinary, no trailers, row touched -> no plan/record owed" 0 "$(fx_run "$r" prepush)" "size S"

  # (−) over-owe: every unknown or larger arm falls through to today's RL-TRAILER refusal.
  r=$(fx_ord mrow M M 1 XSROW src/app.js)
  ck "M ordinary, no trailers -> still owes the trailers" 2 "$(fx_run "$r" prepush)" RL-TRAILER
  r=$(fx_ord cpxs XS XS 1 XSROW conformance/thing.sh)
  ck "control-plane change citing an XS row -> still owes the trailers" 2 "$(fx_run "$r" prepush)" RL-TRAILER
  r=$(fx_ord shrink M S 1 XSROW src/app.js)
  ck "row shrunk M->S in the PR's own diff -> size is the BASE's, still owed" 2 "$(fx_run "$r" prepush)" RL-TRAILER
  r=$(fx_ord norow XS XS 1 - src/app.js)
  ck "ordinary non-docs with no Kit-Row -> owed" 2 "$(fx_run "$r" prepush)" RL-TRAILER
  r=$(fx_ord absent XS XS 2 NEWROW src/app.js)
  ck "Kit-Row boarded in this PR (absent at the base) -> owed" 2 "$(fx_run "$r" prepush)" RL-TRAILER
  r=$(fx_ord untouched XS XS 0 XSROW src/app.js)
  ck "Kit-Row names an XS row this PR's board diff does not touch -> owed" 2 "$(fx_run "$r" prepush)" RL-TRAILER
  r=$(fx_ord trk XS XS 1 XSROW src/app.js Jira)
  ck "tracker backend -> size unknown -> owed" 2 "$(fx_run "$r" prepush)" RL-TRAILER
  # SAST-PARSE-MERGE-TOOL: the ceiling's row-id charset arm (a one-line `case` split for semgrep) pins its own refusal.
  r=$(fx_ord lowid XS XS 1 xsrow src/app.js)
  ck "a lowercase Kit-Row is not a board id -> owed" 2 "$(fx_run "$r" prepush)" RL-TRAILER

  # ── FIX ROUND 1 legs (row binding must be the ROW, not a mention; Done/Released/duplicate owed;
  #    annotation escaping). (a)(b)(c) and (e) are RED against the pre-fix hunk; (d) is a guard.
  # (a) the head edits a prose/Order-style line naming `XSROW`, not the row itself -> owed.
  r=$(fx_ord bindprose XS XS 3 XSROW src/app.js)
  ck "an Order/prose line mentioning the id does not bind the row" 2 "$(fx_run "$r" prepush)" RL-TRAILER
  # (b) ANOTHER row's added cell mentions `XSROW` -> owed.
  r=$(fx_ord bindcell XS XS 4 XSROW src/app.js)
  ck "another row's cell mentioning the id does not bind the row" 2 "$(fx_run "$r" prepush)" RL-TRAILER
  # (c) the row is already Done at the merge-base (and touched on the head) -> owed.
  r=$(fx_ord bdone XS XS 1 XSROW src/app.js "" "done")
  ck "a row already Done at the base cannot be the slice -> owed" 2 "$(fx_run "$r" prepush)" RL-TRAILER
  # (d) the same id on two base sections -> ambiguous -> owed.
  r=$(fx_ord bdup XS XS 1 XSROW src/app.js "" dup)
  ck "a duplicate id at the base -> owed" 2 "$(fx_run "$r" prepush)" RL-TRAILER
  # (e) a '%' in a WARN's text is percent-encoded in the ::warning:: annotation (and stays literal on stderr).
  r=$(fx_full warnesc)
  printf 'prose\n' > "$r/NOTES%x.md"; git -C "$r" add -A >/dev/null
  git -C "$r" commit -qm "late prose

Kit-Row: FIXTURE
Kit-Class: control-plane
Kit-Plan: docs/plans/2026-09-04-fixture.md
Kit-Review: docs/reviews/2026-09-04-fixture.md" >/dev/null
  _ga_was="${GITHUB_ACTIONS-__unset__}"; export GITHUB_ACTIONS=true
  ck "WARN naming a path with a percent sign, under Actions" 0 "$(fx_run "$r" prepush)" "WARN: RL-OPEN-ROUND: 'NOTES%x.md'"
  if grep -qF "::warning::RL-OPEN-ROUND: 'NOTES%25x.md'" "$_fx/last.log" 2>/dev/null; then
    echo "OK: the ::warning:: annotation percent-encodes '%' as %25"
  else
    echo "selftest FAIL: the ::warning:: annotation is not percent-encoded"; sed 's/^/    | /' "$_fx/last.log"; st=1
  fi
  if [ "$_ga_was" = "__unset__" ]; then unset GITHUB_ACTIONS; else export GITHUB_ACTIONS="$_ga_was"; fi

  # (−) a VOLUNTEERED pair of trailers is graded exactly as today: XS ordinary + a stub plan -> refused.
  r=$(fx_ord vol XS XS 1 XSROW src/app.js); t=$(git -C "$r" rev-parse HEAD)
  printf '# Plan\n' > "$r/docs/plans/2026-09-30-vol.md"
  fx_record "$r/docs/reviews/2026-09-30-vol.md" builder reviewer "$t" APPROVE
  git -C "$r" add -A >/dev/null
  git -C "$r" commit -qm "record

Kit-Row: XSROW
Kit-Class: ordinary
Kit-Plan: docs/plans/2026-09-30-vol.md
Kit-Review: docs/reviews/2026-09-30-vol.md" >/dev/null
  ck "XS ordinary that volunteers the trailers is graded (stub plan refused)" 2 "$(fx_run "$r" prepush)" RL-PLAN-STUB

  # ── DESIGN-SKILL-LENS-LIST — the lens leg. A design doc the change ADDS carries the twelve lens names.
  # fx_design <repo> <mode: full|eleven|none> [heading] — writes an added design doc; `full` is the Lens review
  # section COPIED OUT OF the shipped skill, so a lens renamed in the skill or in RL_LENSES reds leg 1.
  fx_design() {
    mkdir -p "$1/docs/architecture"
    _fd="$1/docs/architecture/2026-10-08-fixture-design.md"
    case "$2" in
      none) printf '# fixture design\n\nno table here\n' > "$_fd" ;;
      *)    { printf '# fixture design\n\n'
            awk '/^## /{ i = ($0 ~ /^## Lens review/) } i' "$DIR/skills/design/SKILL.md"
            } > "$_fd"
            [ "$2" != eleven ] || { grep -v '| Cost and size |' "$_fd" > "$_fd.tmp"; mv "$_fd.tmp" "$_fd"; } ;;
    esac
    [ -z "${3:-}" ] || { awk -v h="$3" '/^## Lens review/ && !d { print h; d=1; next } 1' "$_fd" > "$_fd.tmp"; mv "$_fd.tmp" "$_fd"; }
    git -C "$1" add -A >/dev/null
  }
  # leg 1 (+): control-plane, added doc with the full table; the OLD doc is amended without one (not graded)
  r=$(fx_full lensok olddoc)
  printf '# old design\namended, still no table\n' > "$r/docs/architecture/2026-01-01-old-design.md"
  fx_design "$r" full; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "added design doc carries the lens table -> pass" 0 "$(fx_run "$r" prepush)" "the approval is branch protection's"
  # leg 2 (−): eleven rows, no 'Cost and size' -> named. LOAD-BEARING: the call site in rl_run.
  r=$(fx_full lensmiss)
  fx_design "$r" eleven; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "M/CP design doc without a full lens table is named" 2 "$(fx_run "$r" prepush)" RL-DESIGN-LENS-MISSING
  grep -qF "Cost and size" "$_fx/last.log" || { echo "selftest FAIL: the refusal must NAME the missing lens 'Cost and size'"; st=1; }
  # SWAS-239 heading grammar: a section prefix (9a. / §9) is accepted; a different word or an extra word is not.
  # LOAD-BEARING: the positives and the agreement leg red (rc 2) on the pre-change `^## ([0-9]+[.] )?Lens review`.
  _sec=$(printf '\302\247')
  r=$(fx_full lenssub)
  fx_design "$r" full "## 9a. Lens review"; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "heading '## 9a. Lens review' is accepted" 0 "$(fx_run "$r" prepush)" "the approval is branch protection's"
  r=$(fx_full lenssect)
  fx_design "$r" full "## ${_sec}9 Lens review"; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "heading '## §9 Lens review' is accepted" 0 "$(fx_run "$r" prepush)" "the approval is branch protection's"
  r=$(fx_full lensless)
  fx_design "$r" full "## 9a. Lessons review"; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "heading '## 9a. Lessons review' is NO-LENS-TABLE" 2 "$(fx_run "$r" prepush)" RL-DESIGN-NO-LENS-TABLE
  r=$(fx_full lensnot)
  fx_design "$r" full "## Not a Lens review"; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "heading '## Not a Lens review' is NO-LENS-TABLE" 2 "$(fx_run "$r" prepush)" RL-DESIGN-NO-LENS-TABLE
  # agreement: the awk cell pass must see the section the grep accepted. LOAD-BEARING: revert only the awk and all twelve are named.
  r=$(fx_full lensagree)
  fx_design "$r" eleven "## ${_sec}9 Lens review"; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "section-sign heading with eleven rows names only the missing lens" 2 "$(fx_run "$r" prepush)" RL-DESIGN-LENS-MISSING
  [ "$(grep -c RL-DESIGN-LENS-MISSING "$_fx/last.log")" = 1 ] || { echo "selftest FAIL: the section-sign heading must name exactly one missing lens"; st=1; }
  grep -qF "'Cost and size'" "$_fx/last.log" || { echo "selftest FAIL: the section-sign refusal must NAME 'Cost and size'"; st=1; }
  ! grep -qF "'Project principles'" "$_fx/last.log" || { echo "selftest FAIL: the awk cell pass missed the section the grep accepted"; st=1; }
  ! grep -q RL-DESIGN-NO-LENS-TABLE "$_fx/last.log" || { echo "selftest FAIL: the section-sign heading was refused as no lens table"; st=1; }
  # leg 3 (+): XS ordinary adding a design doc with no table is exempt (the ceiling cut runs first)
  r=$(fx_ord xslens XS XS 1 XSROW src/app.js)
  fx_design "$r" none; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "XS ordinary design doc without a table is not flagged" 0 "$(fx_run "$r" prepush)" "XS/S ordinary (XSROW, size XS)"
  # leg 5 (−): git quotes a non-ASCII name; the quoted line must reach RL-DESIGN-PATH, not be skipped.
  # LOAD-BEARING: remove the quoted-name arm in rl_added_designs and this reds (rc 0).
  r=$(fx_full lensquote)
  mkdir -p "$r/docs/architecture"; printf '# x\n' > "$r/docs/architecture/caf$(printf '\303\251')-design.md"
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "a quoted-name added design doc is refused" 2 "$(fx_run "$r" prepush)" RL-DESIGN-PATH
  # leg 5b (−): a newline in the name must not forge a log line (echo would expand the literal \n). LOAD-BEARING: swap printf for echo and this reds under dash.
  r=$(fx_full lensnl)
  _nl=$(printf '\nX'); _nl=${_nl%X}
  mkdir -p "$r/docs/architecture"; printf '# x\n' > "$r/docs/architecture/a${_nl}FORGED-LINE-design.md"
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "a newline-bearing design doc name is refused" 2 "$(fx_run "$r" prepush)" RL-DESIGN-PATH
  ! grep -q '^FORGED-LINE' "$_fx/last.log" || { echo "selftest FAIL: a filename forged a log line"; st=1; }
  # leg 5c (+): a quoted NON-design name under docs/architecture is not the lens leg's business
  r=$(fx_full lensnd)
  mkdir -p "$r/docs/architecture"; printf '# x\n' > "$r/docs/architecture/caf$(printf '\303\251')-notes.md"
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "a quoted non-design name is not refused by the lens leg" 0 "$(fx_run "$r" prepush)" "the approval is branch protection's"
  # leg 6 (+): an XS ordinary design-only docs PR (no code) is exempt. LOAD-BEARING: delete the
  # rl_ceiling_exempt line on the docs-only path and the lens leg reds this (rc 2).
  r=$(fx_ord xsdocs XS XS 1 XSROW docs/architecture/2026-10-08-fixture-design.md)
  ck "XS ordinary design-only docs PR without a table is not flagged" 0 "$(fx_run "$r" prepush)" "XS/S ordinary (XSROW, size XS)"
  # leg 4 (−), amendment A1: a design-only docs PR is graded too. LOAD-BEARING: the call site above the N-A return.
  r=$(fx_new lensdocs); git -C "$r" checkout -qb feat/x
  fx_design "$r" none; git -C "$r" commit -qm "design only" >/dev/null
  ck "design-only docs PR adding a design doc without the table is named" 2 "$(fx_run "$r" prepush)" RL-DESIGN-NO-LENS-TABLE

  # ── SWAS-300 — RULE 10, THE SEAT ROLES (design 2026-10-18-typed-seats-day-one-design.md, section 5.3).
  # fx_seat <name> <base-mode> <builder> <rounds-seat> <security-line> — a control-plane fixture whose
  # record is rewritten with the given seat words. <base-mode> '' | dup | zero | two breaks the BASE's
  # neutral definitions (the vocabulary mutants). Prints the repo dir.
  fx_seat() {
    _s=$(fx_full "$1" "$2"); _st=$(git -C "$_s" rev-parse HEAD~1)
    fx_record "$_s/docs/reviews/2026-09-04-fixture.md" "$3" reviewer "$_st" APPROVE '' '' "$5" "$4"
    git -C "$_s" add -A >/dev/null; git -C "$_s" commit -q --amend --no-edit >/dev/null
    printf '%s' "$_s"
  }
  r=$(fx_seat n1 "" builder general-purpose "")
  ck "SEAT-N1 a Rounds seat outside the vocabulary" 2 "$(fx_run "$r" prepush)" RL-SEAT-UNKNOWN
  r=$(fx_seat n2 "" builder reviewer "ran — seat reviewer, verdict: PASS")
  ck "SEAT-N2 a combined reviewer-plus-security seat on Control-plane" 2 "$(fx_run "$r" prepush)" RL-SEAT-SECURITY-NOT-DISTINCT
  r=$(fx_seat n3 "" builder reviewer "ran — verdict: PASS")
  ck "SEAT-N3 a security line naming no seat (the v3.240.0 shape)" 2 "$(fx_run "$r" prepush)" RL-SEAT-SECURITY-MISSING
  r=$(fx_seat n4 "" builder general-purpose "")
  printf '# gp\n\n## Role\nSeat role: general-purpose\n' > "$r/agents/general-purpose.agent.md"
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "SEAT-N4 a definition the PR itself adds is not in the vocabulary" 2 "$(fx_run "$r" prepush)" RL-SEAT-UNKNOWN
  r=$(fx_seat n5 "" builder reviewer "ran — seat security-reviewer, verdict: PASS")
  ck "SEAT-N5 a harness binding name is not a role" 2 "$(fx_run "$r" prepush)" RL-SEAT-UNKNOWN
  r=$(fx_seat n6 dup builder reviewer "")
  ck "SEAT-N6 two base definitions declare the same role" 2 "$(fx_run "$r" prepush)" RL-SEAT-VOCAB
  r=$(fx_seat n7 "" builder reviewer "waived — no-untrusted-input · no-new-permission · no-control-plane-surface · no-operator-shell")
  ck "SEAT-N7 a security waiver on Control-plane" 2 "$(fx_run "$r" prepush)" RL-SEAT-SECURITY-WAIVED-CP
  r=$(fx_seat n8 zero builder reviewer "")
  ck "SEAT-N8 a base definition with no Seat role line" 2 "$(fx_run "$r" prepush)" RL-SEAT-VOCAB
  r=$(fx_seat n9 two builder reviewer "")
  ck "SEAT-N9 a base definition with two Seat role lines" 2 "$(fx_run "$r" prepush)" RL-SEAT-VOCAB
  r=$(fx_seat n13 upper builder reviewer "")
  ck "SEAT-N13 an off-grammar definition line" 2 "$(fx_run "$r" prepush)" RL-SEAT-VOCAB
  r=$(fx_seat n10 "" builder reviewer ""); fx_strip_base "$r"
  ck "SEAT-N10 no merge-base in --pr mode" 2 "$(fx_run "$r" pr -)" RL-NO-BASE
  ck "SEAT-N10 no merge-base, pre-push: no trusted vocabulary is a refusal, not an empty pass" 2 "$(fx_run "$r" prepush -)" RL-SEAT-VOCAB
  r=$(fx_seat n11 "" orchestrator reviewer "")
  ck "SEAT-N11 a Builder line opening with a file name, not a role" 2 "$(fx_run "$r" prepush)" RL-SEAT-UNKNOWN
  r=$(fx_seat n12 "" builder builder "")
  ck "SEAT-N12 a Rounds seat that is a role but not reviewer" 2 "$(fx_run "$r" prepush)" RL-SEAT-NOT-REVIEWER
  # P1: Ordinary M, security 'seat reviewer' is legal; the same record naming a seat outside the vocabulary is not.
  r=$(fx_ord p1 M M 1 XSROW src/app.js); t=$(git -C "$r" rev-parse HEAD)
  fx_plan "$r" "$r/docs/plans/2026-10-20-p1.md"
  fx_record "$r/docs/reviews/2026-10-20-p1.md" builder reviewer "$t" APPROVE '' '' 'ran — seat reviewer, verdict: PASS'
  git -C "$r" add -A >/dev/null
  git -C "$r" commit -qm "record

Kit-Row: XSROW
Kit-Class: ordinary
Kit-Plan: docs/plans/2026-10-20-p1.md
Kit-Review: docs/reviews/2026-10-20-p1.md" >/dev/null
  ck "SEAT-P1 Ordinary M, security seat reviewer is legal" 0 "$(fx_run "$r" prepush)" "structural pass"
  fx_record "$r/docs/reviews/2026-10-20-p1.md" builder reviewer "$t" APPROVE '' '' 'ran — seat general-purpose, verdict: PASS'
  git -C "$r" add -A >/dev/null; git -C "$r" commit -q --amend --no-edit >/dev/null
  ck "SEAT-P1b Ordinary M, a security seat outside the vocabulary is still refused" 2 "$(fx_run "$r" prepush)" RL-SEAT-UNKNOWN
  # P2: Control-plane, conductor builds inline, free text after the role is never graded.
  r=$(fx_seat p2 "" "conductor integrated" "reviewer (deep tier)" "ran — seat security, verdict: PASS-WITH-NOTES")
  ck "SEAT-P2 conductor, a tier note and a notes verdict are free text" 0 "$(fx_run "$r" prepush)" "structural pass"
  # P3: the record's role word is normalised (backticks, bold, one trailing , or :, case) before membership.
  r=$(fx_seat p3 "" '`Builder`: two seats' '**Reviewer**, deep tier' "ran — seat \`Security\`, verdict: PASS")
  ck "SEAT-P3 a decorated, mixed-case role word is read as the role" 0 "$(fx_run "$r" prepush)" "structural pass"

  # ── THE STRUCK MODE IS STILL AN ASSERTION. `--stamp` was removed by `D-240904-2`, and the failure to
  # guard against is not that it stops working — it is that it silently starts DOING NOTHING while
  # exiting 0, which is exactly how the arm behaved for one commit before it was deleted. A stale
  # script, a copied runbook line or an operator's muscle memory must get a LOUD refusal, so the
  # dispatch must reject the flag rather than ignore it.
  if sh "$0" --stamp >/dev/null 2>&1; then
    echo "selftest FAIL: --stamp still SUCCEEDS; the struck mode must be refused, not silently accepted"; st=1
  else
    echo "OK: --stamp is refused with a usage error (struck by D-240904-2)"
  fi
  # SAST-PARSE-MERGE-TOOL: the dispatch's `--pr` number check (a one-line `case` split for semgrep) refuses a non-number, rc 2.
  _pr_rc=0; _pr_out=$(sh "$0" --pr 12x --head abc 2>&1) || _pr_rc=$?
  if [ "$_pr_rc" = 2 ] && printf '%s' "$_pr_out" | grep -qF 'review-lane: --pr needs a number'; then
    echo "OK: --pr 12x is refused (rc 2, 'review-lane: --pr needs a number')"
  else
    echo "selftest FAIL: --pr 12x rc=$_pr_rc out=[$_pr_out]"; st=1
  fi

  RL_REPO="$_sv_repo"
  rm -rf "$_fx"; trap - EXIT INT TERM
  [ "$st" = 0 ] && { echo "OK: review-lane — record grader load-bearing (structure, containment, dispositions, controls, security; no forge read, no waiting state)"; return 0; }
  echo "review-lane: SELFTEST FAILED"; return 1
}

# --- dispatch ---
_rl_mode=""; _rl_pr=""; _rl_head=""; _rl_base_ref=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --pr)       _rl_mode='pr'; _rl_pr="${2:-}"; shift 2 ;;
    --head)     _rl_head="${2:-}"; shift 2 ;;
    --base-ref) _rl_base_ref="${2:-}"; shift 2 ;;
    --pre-push) _rl_mode=prepush; shift ;;
    # `--stamp` IS GONE (`D-240904-2`) and is deliberately NOT accepted as a no-op: an operator or a
    # stale script that still passes it gets the usage error and reads why, rather than a silent
    # success that leaves them believing they produced something the gate wants.
    --selftest) _rl_mode=selftest; shift ;;
    *) echo "usage: review-lane.sh --pr <n> --head <sha> [--base-ref <ref>] | --pre-push | --selftest   (--stamp was removed by D-240904-2: the reviewer types nothing — a plain non-author Approve on the graded head is the attestation, and since REVIEW-LANE-WAITING-IS-GREEN the forge enforces it, not this script)" >&2; exit 2 ;;
  esac
done

case "$_rl_mode" in
  selftest) selftest ;;
  pr)
    case "$_rl_pr" in
      ''|*[!0-9]*) echo "review-lane: --pr needs a number" >&2; exit 2 ;;
    esac
    [ -n "$_rl_head" ] || { echo "review-lane: --pr requires --head <sha>" >&2; exit 2; }
    _rc=0; rl_run || _rc=$?
    echo "review-lane => rc=$_rc (0 pass/N-A · 2 anomaly/refusal)"
    exit "$_rc" ;;
  prepush)
    _rc=0; rl_run || _rc=$?
    echo "review-lane => rc=$_rc (0 pass/N-A · 2 anomaly/refusal)"
    exit "$_rc" ;;
  *) echo "usage: review-lane.sh --pr <n> --head <sha> [--base-ref <ref>] | --pre-push | --selftest" >&2; exit 2 ;;
esac
