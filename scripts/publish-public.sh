#!/bin/sh
# publish-public.sh — promote a released kit into the PUBLIC product repo.
#   sh scripts/publish-public.sh [--remote <url>] [--dry-run] [--allow-untagged] [--selftest]
#   sh scripts/publish-public.sh --gate [--require-ids]   # (--require-ids: rc 2 if the identifier list is absent/empty) read-only Layer-2 scan of committed HEAD; runs on every PR (CI secret-scan)
#
# THE MENTAL MODEL (load-bearing): promotion is REGENERATION, not cherry-picking. You never hand-pick
# files or commits to move public — that is where leaks come from. The public repo is a GENERATED
# SNAPSHOT of the shippable product, refreshed per release. The unit of promotion is a RELEASE (the
# whole clean tree), so there is no per-file decision to get wrong: `adopter-export` defines the
# correct set deterministically from `.gitattributes export-ignore`.
#
# Distinct from the kit's "promotion contract" (docs/governance/promotion-contract.md) — that is the
# GO/NO-GO for MERGING CODE. This is how a released `main` becomes the PUBLIC PRODUCT.
#
# TWO INDEPENDENT SAFETY LAYERS:
#   Layer 1 — the export contract (allow-by-omission): `adopter-export` ships everything MINUS the
#     export-ignored set. The primary filter.
#   Layer 2 — the promotion gate (deny-by-default): this script re-scans the GENERATED TREE and
#     ABORTS on any withheld-document path, home-directory path, or secret. Layer 1 is a contract;
#     Layer 2 assumes the contract was broken — it catches a document nobody remembered to withhold.
#
# HONEST CEILING — read before trusting it. A green run proves the published tree matches the export,
# trips no KNOWN-withheld pattern, and is fully scannable. It does NOT prove the tree is free of a
# genuinely-NEW CATEGORY of withheld content that no pattern matches, nor that candid PROSE inside an
# otherwise-shippable file is safe. The denylist is only as good as its maintenance, and prose is a
# human judgement. That is why step 4 (human diff review) is not optional and cannot be automated
# away: it is the reviewer with standing to say no. Add patterns as new document types appear.
#
# What it changes: writes a generated snapshot into a temp dir and, unless --dry-run, commits/tags/
#   pushes it to the PUBLIC repo. Never writes inside the private dev repo; never edits the public
#   repo by hand.
# Guardrails: refuses a dirty worktree and an untagged HEAD (the export archives committed HEAD, so a
#   dirty tree would publish something other than what you reviewed); the sensitivity scan is
#   rc-driven and fails CLOSED — an unreadable path, a tool error, or a missing gitleaks ABORTS the
#   whole publish, it never treats an incomplete scan as clean; the mirror is a two-step tar (no
#   pipe) so a read-side failure cannot be masked, and syncs with deletes so the public tree cannot
#   accumulate stale files.
# POSIX sh; dash-clean.
set -eu

ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd -P)
PUBLIC_REMOTE_DEFAULT="https://github.com/SeaBrad72/sparkwright.git"
# Owner-identifier denylist source. Kept OUT of this shipped file so the kit stays identity-neutral
# and portable (no personal name/email/home-path literal ships anywhere), and so adopters configure
# their own. One identifier per line, `#` comments allowed; the file is `.gitattributes export-ignore`d
# so it never reaches an export. Overridable for the selftest.
PUBLISH_ID_FILE="${PUBLISH_ID_FILE:-$ROOT/.publish-identifiers}"

usage() { echo "usage: publish-public.sh [--remote <url>] [--dry-run] [--allow-untagged] | --gate [--require-ids] | --selftest" >&2; exit 2; }

# --- P1.2-pre-b: the immutability rule, as a PURE function so it can be proven ------------------
# publish_decision <tag_already_published:0|1> <changed_paths:N> -> publish | noop | refuse
#
#   tag published?  tree differs?   decision   why
#   ---------------------------------------------------------------------------------------------
#   NO              no              publish    THE PARTIAL-PUBLISH CASE. main landed but the tag push
#                                             failed (or a prior run half-published): the tree already
#                                             matches, yet the TAG IS MISSING. "re-run to converge"
#                                             only converges if this PUBLISHES the absent tag. (dual
#                                             review: treating this as noop left a release permanently
#                                             untagged while the check red-ed forever.)
#   NO              yes             publish    a new release
#   yes             no              noop       benign idempotent re-run — the tag is present AND its
#                                             tree matches. MUST stay green: a gate that fires on the
#                                             happy path teaches people to ignore it.
#   yes             YES             refuse     THE DEFECT. Publishing would MOVE a released tag: every
#                                             adopter pinned to it silently receives a different tree
#                                             than the one they audited.
#
# Tag ABSENCE always publishes (the tag is the deliverable). Only a PRESENT tag with a MATCHING tree
# is a no-op. A blunt "refuse whenever the tag exists" would kill the benign re-run; a blunt "noop
# whenever the tree matches" leaves a half-published release stuck — precision matters at both edges.
publish_decision() {
  _tp=$1; _ch=$2
  if [ "$_tp" -eq 0 ]; then echo publish; return 0; fi   # tag absent -> publish it, always
  if [ "$_ch" -eq 0 ]; then echo noop;    return 0; fi   # tag present + tree matches -> benign no-op
  echo refuse                                             # tag present + tree differs -> the defect
}

# --- PUB-CHANGELOG — the public release note is the CURATED block, never the internal changelog -----
# The public repo has no PR history (it is a generated mirror), so GitHub cannot auto-generate notes.
# Each CHANGELOG.md entry carries a `<!-- public:start -->…<!-- public:end -->` block: a user-facing
# summary, deliberately separate from the internal bullets. This extracts THAT block for <ver> — never
# the internal detail. Empty output = no block; the caller fails closed rather than publish empty/sausage.
extract_public_notes() {
  _epn_ver=$1; _epn_file=${2:-$ROOT/CHANGELOG.md}
  [ -f "$_epn_file" ] || return 1
  # BOTH markers are required. Lines are BUFFERED and emitted ONLY on a complete start..end pair — a
  # dangling start (missing `<!-- public:end -->`) or an absent block emits NOTHING and returns non-zero,
  # so the caller fails closed. Without this, a forgotten end marker would spill the internal bullets
  # (everything to the next `## [` heading or EOF) straight into the public Release note (security HIGH).
  awk -v ver="$_epn_ver" '
    index($0, "## [" ver "]") == 1 { insec=1; next }                 # closing "]" stops 9.9.9==9.9.99
    insec && index($0, "## [") == 1 { exit }                         # left the entry (emit iff done)
    insec && index($0, "<!-- public:start -->") { started=1; next }
    insec && started && index($0, "<!-- public:end -->") { done=1; exit }
    insec && started { buf = buf $0 ORS }
    END { if (done) printf "%s", buf; else exit 1 }
  ' "$_epn_file"
}

# --- PUB-CHANGELOG — create the GitHub Release from the (already-scanned) curated note ---------------
# Idempotent + best-effort, and called on BOTH the publish path AND the noop path — so a re-run
# CONVERGES a Release that a prior `gh` failure left missing (the noop path exits before the publish
# block, so without this a missing Release would only ever be fixable by hand). The tag IS the release;
# a gh failure degrades LOUD, never as a publish failure. Uses $NOTE_DIR/release-notes.md (scanned clean
# in step 2b) and runs inside $MIRROR so gh targets the public remote.
ensure_release() {
  command -v gh >/dev/null 2>&1 || { say "WARNING: gh not installed — $TAG has no GitHub Release. Install gh and create it from the CHANGELOG public block."; return 0; }
  ( cd "$MIRROR" && gh release view "$TAG" >/dev/null 2>&1 ) && return 0   # already exists -> idempotent
  if ( cd "$MIRROR" && gh release create "$TAG" --title "$TAG" --notes-file "$NOTE_DIR/release-notes.md" >/dev/null 2>&1 ); then
    say "      created GitHub Release $TAG with the curated public notes"
  else
    say "WARNING: could not create GitHub Release $TAG (it IS tagged/published). Create it by hand: (cd <clone of $REMOTE> && gh release create $TAG --title $TAG --notes-file notes.md)"
  fi
}
die()   { echo "publish-public: $*" >&2; exit 1; }
say()   { echo "publish-public: $*"; }

REMOTE=$PUBLIC_REMOTE_DEFAULT
DRY_RUN=0
ALLOW_UNTAGGED=0
SELFTEST=0
GATE=0
REQUIRE_IDS=0
while [ $# -gt 0 ]; do
  case $1 in
    --gate)           GATE=1; shift ;;
    --require-ids)    REQUIRE_IDS=1; shift ;;
    --remote)         [ $# -ge 2 ] || usage; REMOTE=$2; shift 2 ;;
    --dry-run)        DRY_RUN=1; shift ;;
    --allow-untagged) ALLOW_UNTAGGED=1; shift ;;
    --selftest)       SELFTEST=1; shift ;;
    -h|--help)        usage ;;
    *)                echo "publish-public: unknown argument '$1'" >&2; usage ;;
  esac
done

# --- Layer 2: the sensitivity scan ------------------------------------------------------------
# sensitive_hits <tree>
#   stdout : one offending path per line, repo-relative (empty == no KNOWN-withheld content found)
#   rc     : 0 = the scan SAW the whole tree · non-zero = the scan could NOT complete
# The caller MUST treat a non-zero rc as ABORT, independently of stdout: a scan that could not read
# every path has NOT proven the tree clean (the C2 fail-open this replaces). The verdict is rc AND
# output — never output alone.
#
# POLICY (ratified 2026-07-12, deny-by-pattern). Matched by PATH, never by content keyword — a
# content grep for "vulnerability"/"bypass" hits SECURITY.md and the promotion contract, where those
# are the product's own vocabulary. Two document classes plus one content check:
#   - Withheld documents (the candid dev record + roadmaps + the full dev CHANGELOG). CHANGELOG.md is
#     export-ignored (the dev changelog narrates deferred hardening across the whole history); it is
#     listed here too as defence-in-depth, so removing the export-ignore still aborts the publish.
#   - Harvest/field-report/postmortem docs — scoped to docs/ so a SHIPPED script like
#     scripts/postmortem.sh (a maintainer tool, not a candid report) is not swept up (the C1/M1
#     regression this closes).
#   - The kit's OWN postmortems — the ROOT `postmortems/` directory exactly (PUBLISH-WITHHOLD-ROOT-
#     POSTMORTEMS), beside its `.gitattributes` export-ignore. Not a `*postmortem*` name pattern:
#     templates/POSTMORTEM-TEMPLATE.md and scripts/postmortem.sh are the product and must ship.
#   - Owner identifiers in file CONTENT — the owner's name/email/home-path, read from the
#     EXPORT-IGNORED `.publish-identifiers` file (see PUBLISH_ID_FILE). A GENERIC /Users|/home scan
#     was rejected: it false-positives on legitimately-shipped example paths (e.g. a `/home/u/.ssh/
#     id_rsa` deny-case fixture in conformance/agent-autonomy.sh) and would abort every publish.
#     Targeting the OWNER's real identifiers via an external file catches the confirmed leak class
#     (a pre-anonymization personal path) with no false positives AND keeps this shipped file
#     identity-neutral. Binaries are scanned too (grep -a), since the export is small. If the file is
#     absent (an adopter's checkout), this dimension is N/A — the path denylist + gitleaks + step-4
#     still apply.
#     FIXTURE CONVENTION (PUBLIC-DEIDENT-FIXTURE-LOGINS): a fixture or test that needs a forge login
#     uses a NEUTRAL placeholder, never a real account — a second-person login (a reviewer / approver)
#     is `reviewer-login`, an author is `author-login` (a cased variant keeps its case shape, e.g.
#     `Reviewer-Login`). Agents write fixtures from the logins they see in a session; this is the word
#     to use instead. `--gate` runs this same scan on every PR, so a real login is red at review time.
# MAINTENANCE OBLIGATION: when a new candid document type appears, add it HERE — step 4 is a
# backstop, not a substitute.
sensitive_hits() {
  _tree=$1
  [ -d "$_tree" ] || { echo "SCAN-ERROR: not a directory: $_tree" >&2; return 2; }
  _errf=$(mktemp "${TMPDIR:-/tmp}/sw-scan.XXXXXX") || return 2

  # (1) withheld-document PATHS. find's stderr (unreadable dir, permission denied) is captured and
  #     turned into a scan failure below — an unseeable subtree must not read as clean.
  find "$_tree" \
    \( -iname 'BACKLOG.md' \
       -o -iname 'SPARKWRIGHT-CONSOLIDATED-BACKLOG.md' \
       -o -iname 'CHANGELOG.md' \
       -o -iname 'KIT-FEEDBACK.md' \
       -o -iname 'ROADMAP.md' \
       -o -iname 'ROADMAP-KIT.md' \
       -o -iname 'meta-control-log.md' \
       -o -iname '.meta-control-last' \
       -o -ipath "$_tree/docs/architecture/*" \
       -o -ipath "$_tree/postmortems/*" \
       -o \( -ipath "$_tree/docs/*" \
             -a \( -iname '*harvest*' -o -iname '*field-report*' -o -iname '*postmortem*' \) \) \
    \) -print 2>>"$_errf" | sed "s|^$_tree/||"

  # (2) owner identifiers in CONTENT, from the export-ignored config (identity-neutral by construction;
  #     absent => this dimension is N/A). -F: fixed strings, no regex surprises; -a: scan binaries too;
  #     -i: case-INSENSITIVE — a cased variant of a denylisted token (e.g. a login capitalised in
  #     prose) must not slip past a case-sensitive match (PUBLIC-DEIDENTIFICATION fix round).
  if [ -f "$PUBLISH_ID_FILE" ]; then
    while IFS= read -r _id || [ -n "$_id" ]; do
      case "$_id" in ''|\#*) continue ;; esac
      grep -rlaiF -e "$_id" "$_tree" 2>>"$_errf" | sed "s|^$_tree/||"
    done < "$PUBLISH_ID_FILE"
  fi

  # fail CLOSED: any stderr from find/grep means the scan could not see everything.
  if [ -s "$_errf" ]; then
    echo "SCAN-ERROR: scan could not complete: $(head -1 "$_errf")" >&2
    rm -f "$_errf"; return 2
  fi
  rm -f "$_errf"
  return 0
}

# --- gate — the Layer-2 scan, runnable on every PR (PUBLIC-DEIDENT-FIXTURE-LOGINS) ---------------
# `--gate`: export COMMITTED HEAD with the same generator a publish uses (scripts/adopter-export.sh),
# run sensitive_hits over that tree AND over every `public:` block of CHANGELOG.md (the release notes —
# CHANGELOG.md is export-ignored, so the tree scan cannot see them). Read-only: no tag check, no dirty
# check (it archives HEAD, so uncommitted edits are not scanned), no mirror, no network, no gitleaks
# (the CI job it runs in already runs gitleaks over full history).
#   rc 0 clean · rc 1 a hit (each offending PATH printed, never an identifier value, plus one cure line)
#   rc 2 a scan could not complete (fail-closed, same as the publish path)
gate() {
  cd "$ROOT"
  _gw=$(mktemp -d "${TMPDIR:-/tmp}/sw-gate.XXXXXX") || { echo "publish-public: gate: mktemp failed" >&2; exit 2; }
  trap 'rm -rf "$_gw"' EXIT
  trap 'exit 2' HUP INT TERM
  # The exporter honours the WORKTREE .gitattributes (export-ignore) while archiving HEAD's content, so an
  # uncommitted attributes edit would change what is scanned: refuse rather than scan a hybrid.
  # LIMIT: only the root .gitattributes is checked; nested */.gitattributes and .git/info/attributes also steer
  # `git archive --worktree-attributes`, which a fresh CI checkout cannot carry dirty.
  if [ -n "$(git status --porcelain -- .gitattributes 2>/dev/null)" ]; then
    echo "publish-public: gate: .gitattributes has uncommitted changes — the exporter reads the worktree copy, so the scan would not match committed HEAD. Commit or stash it." >&2
    exit 2
  fi
  say "gate: scanning the tree COMMITTED at HEAD (git archive) — uncommitted edits are not seen"
  if [ "$REQUIRE_IDS" -eq 1 ]; then
    if [ ! -f "$PUBLISH_ID_FILE" ] || ! grep -v '^[[:space:]]*#' "$PUBLISH_ID_FILE" | grep -q '[^[:space:]]'; then
      echo "publish-public: gate: --require-ids: the identifier list is absent or has no entries — the owner-identifier scan would be vacuous." >&2
      exit 2
    fi
  fi
  [ -f "$PUBLISH_ID_FILE" ] || say "gate: no identifier list at \$PUBLISH_ID_FILE — the owner-identifier dimension is N/A; the withheld-path scan still runs"
  if ! sh scripts/adopter-export.sh "$_gw/export" >/dev/null 2>"$_gw/export.err"; then
    echo "publish-public: gate: adopter-export failed — nothing could be scanned: $(head -1 "$_gw/export.err")" >&2
    exit 2
  fi
  # every public block of the COMMITTED CHANGELOG.md -> one scan target (absent CHANGELOG at HEAD: rc 2)
  mkdir -p "$_gw/note"; : > "$_gw/note/release-notes.md"
  # The kit repo always carries a CHANGELOG.md: absent at HEAD means the note scan cannot run -> rc 2.
  git cat-file -e HEAD:CHANGELOG.md 2>/dev/null || { echo "publish-public: gate: no CHANGELOG.md at HEAD — the release-note scan cannot run" >&2; exit 2; }
  git show HEAD:CHANGELOG.md > "$_gw/CHANGELOG.md" || { echo "publish-public: gate: cannot read CHANGELOG.md at HEAD" >&2; exit 2; }
  # The scanned note text is the UNION of (1) every block, by a line-level awk (a line naming BOTH markers —
  # the header prose that documents the convention — is not a block) and (2) what the PUBLISH ships for every
  # `## [<v>]` heading: extract_public_notes itself, run on this same HEAD copy, so the two cannot diverge.
  awk 'index($0, "<!-- public:start -->") && index($0, "<!-- public:end -->") { next }
       index($0, "<!-- public:start -->") { on=1; next }
       index($0, "<!-- public:end -->")   { on=0; next }
       on { print }' "$_gw/CHANGELOG.md" > "$_gw/note/release-notes.md" \
    || { echo "publish-public: gate: could not extract the public release-note blocks" >&2; exit 2; }
  _gvers=$(sed -n 's/^## \[\([^]]*\)\].*/\1/p' "$_gw/CHANGELOG.md") || { echo "publish-public: gate: could not list CHANGELOG versions" >&2; exit 2; }
  _gi=0
  printf '%s\n' "$_gvers" | while IFS= read -r _gv; do
    [ -n "$_gv" ] || continue
    extract_public_notes "$_gv" "$_gw/CHANGELOG.md" > "$_gw/note/v-$_gi.md" 2>/dev/null || : > "$_gw/note/v-$_gi.md"
    _gi=$((_gi+1))
  done
  _gbad=0
  _gtree=$(sensitive_hits "$_gw/export") || { echo "publish-public: gate: the tree scan could not complete (an unscannable tree is not proven clean)" >&2; exit 2; }
  if [ -n "$_gtree" ]; then
    _gbad=1
    echo "publish-public: gate: the generated tree carries content that must not go public, in:" >&2
    printf '%s\n' "$_gtree" | sort -u | sed 's/^/  /' >&2
  fi
  _gnote=$(sensitive_hits "$_gw/note") || { echo "publish-public: gate: the release-note scan could not complete" >&2; exit 2; }
  if [ -n "$_gnote" ]; then
    _gbad=1
    echo "publish-public: gate: a CHANGELOG.md public block (release note) carries owner content, in:" >&2
    echo "  CHANGELOG.md (between <!-- public:start --> and <!-- public:end -->)" >&2
  fi
  if [ "$_gbad" -ne 0 ]; then
    echo "publish-public: gate: cure — replace the owner identifier with a neutral placeholder (reviewer-login / author-login); the identifier list is .publish-identifiers (export-ignored); a withheld-document path is cured by export-ignoring it in .gitattributes." >&2
    exit 1
  fi
  say "gate: clean — $(find "$_gw/export" -type f | wc -l | tr -d ' ') exported files and the public release-note blocks carry no owner identifier or withheld path"
  exit 0
}

# --- selftest — the non-vacuity oracle ----------------------------------------------------------
# Drives the REAL sensitive_hits() (not a re-derived copy of its expression — the KW27 trap). Every
# denylist pattern has its OWN anchored RED fixture (so deleting any one pattern turns the selftest
# RED — the C2 vacuity this closes), plus the known FALSE-POSITIVE traps as GREEN fixtures, plus the
# fail-closed rc contract.
selftest() {
  _t=$(mktemp -d "${TMPDIR:-/tmp}/sw-pub-st.XXXXXX") || die "mktemp failed"
  _fail=0
  # isolate the identifier config: a controlled token no source file contains, so the scan is exercised
  # without depending on (or embedding) the real owner identifiers.
  PUBLISH_ID_FILE=$(mktemp "${TMPDIR:-/tmp}/sw-pub-ids.XXXXXX") || die "mktemp failed"
  printf '# test identifiers\nACME-OWNER-TOKEN-42\nowner@example.test\nprivate-fork-dev\nOwner Human\nownerlogin\n' > "$PUBLISH_ID_FILE"
  # anchored: the offending path must appear as a WHOLE line, so no fixture can satisfy another's assertion.
  _hit()  { if sensitive_hits "$_t" | grep -qxF "$1"; then echo "  ok   RED   $2"; else echo "  FAIL missed   $2  ($1)"; _fail=$((_fail+1)); fi; }
  _pass() { if sensitive_hits "$_t" | grep -qxF "$1"; then echo "  FAIL false-pos $2  ($1)"; _fail=$((_fail+1)); else echo "  ok   PASS  $2"; fi; }

  mkdir -p "$_t/docs/architecture" "$_t/docs/adoption/templates" "$_t/templates" "$_t/scripts"
  # RED — one dedicated fixture per pattern.
  : > "$_t/BACKLOG.md"
  : > "$_t/SPARKWRIGHT-CONSOLIDATED-BACKLOG.md"
  : > "$_t/CHANGELOG.md"
  : > "$_t/KIT-FEEDBACK.md"
  : > "$_t/ROADMAP.md"
  : > "$_t/ROADMAP-KIT.md"
  : > "$_t/meta-control-log.md"
  : > "$_t/.meta-control-last"
  : > "$_t/docs/architecture/a-design.md"
  mkdir -p "$_t/postmortems"
  : > "$_t/postmortems/x.md"                        # the kit's own root postmortems (PUBLISH-WITHHOLD-ROOT-POSTMORTEMS)
  : > "$_t/docs/2026-07-11-a-harvest.md"
  : > "$_t/docs/2026-07-11-a-field-report.md"
  : > "$_t/docs/2026-07-11-a-postmortem.md"
  printf 'owner path noted as ACME-OWNER-TOKEN-42 here\n'  > "$_t/docs/leaky.md"
  printf 'contact owner@example.test\n'                    > "$_t/docs/leaky-email.md"
  printf 'deny-case fixture: /home/u/.ssh/id_rsa\n'        > "$_t/docs/legit-example.md"
  # PUBLIC-DEIDENTIFICATION: private-repo name + owner name/login leaking into a shipped file body
  # (the class the scan missed — it caught secrets + home-paths only, not identity literals buried
  # in a test/script body). Driven by the SAME generic PUBLISH_ID_FILE mechanism as the owner
  # name/email above — no new code path, just a maintained denylist.
  printf 'git clone https://github.com/example-org/private-fork-dev.git\n' > "$_t/docs/leaky-repo.md"
  printf 'approved-by: Owner Human [committer]\n'          > "$_t/docs/leaky-name.md"
  printf 'seat: ownerlogin\n'                               > "$_t/docs/leaky-login.md"
  printf 'see https://github.com/example-org/product for the public repo\n' > "$_t/docs/legit-public-org.md"
  # a CASED variant of a lowercase denylist token (real regression: a case-sensitive match let
  # "Bradley James" past a lowercase "bradley" entry) — the config carries 'ownerlogin' lowercase,
  # this fixture carries it capitalised, proving the -i match catches it.
  printf 'ratification seat: OwnerLogin\n'                  > "$_t/docs/leaky-login-cased.md"
  # GREEN — shipped machinery / product vocabulary that must NOT trip the gate.
  : > "$_t/templates/FIELD-REPORT-TEMPLATE.md"      # blank form, not a report
  : > "$_t/templates/POSTMORTEM-TEMPLATE.md"        # blank form
  : > "$_t/scripts/postmortem.sh"                   # a shipped maintainer tool (the C1 regression)
  : > "$_t/docs/adoption/templates/a-postmortem.md" # candid report smuggled under a NESTED templates/ (M1)
  : > "$_t/SECURITY.md"                             # product vocabulary, not a candid record

  echo "publish-public --selftest: denylist fixtures"
  _hit  BACKLOG.md                          "backlog (the candid record)"
  _hit  SPARKWRIGHT-CONSOLIDATED-BACKLOG.md "consolidated backlog"
  _hit  CHANGELOG.md                        "full dev changelog (defence-in-depth)"
  _hit  KIT-FEEDBACK.md                     "kit-feedback log"
  _hit  ROADMAP.md                          "roadmap"
  _hit  ROADMAP-KIT.md                      "kit roadmap"
  _hit  meta-control-log.md                 "candid go/no-go verdicts"
  _hit  .meta-control-last                  "meta-control state"
  _hit  docs/architecture/a-design.md       "internal architecture doc"
  _hit  postmortems/x.md                    "the kit's own root postmortems never ship (PUBLISH-WITHHOLD-ROOT-POSTMORTEMS)"
  _hit  docs/2026-07-11-a-harvest.md        "harvest (candid synthesis)"
  _hit  docs/2026-07-11-a-field-report.md   "field report"
  _hit  docs/2026-07-11-a-postmortem.md     "postmortem"
  _hit  docs/leaky.md                       "owner identifier in content (from config)"
  _hit  docs/leaky-email.md                 "owner email in content (from config)"
  _hit  docs/leaky-repo.md                  "private-repo name leaked into a shipped file (PUBLIC-DEIDENTIFICATION)"
  _hit  docs/leaky-name.md                  "owner display name leaked into a shipped file (PUBLIC-DEIDENTIFICATION)"
  _hit  docs/leaky-login.md                 "owner login leaked into a shipped file (PUBLIC-DEIDENTIFICATION)"
  _hit  docs/leaky-login-cased.md           "a CASED variant of a lowercase denylist token is caught (-i, PUBLIC-DEIDENTIFICATION fix round)"
  _pass docs/legit-public-org.md            "the PUBLIC org/repo URL is NOT in the denylist and must not false-positive"
  _pass docs/legit-example.md               "generic /home/u example is NOT a false-positive"
  _pass templates/FIELD-REPORT-TEMPLATE.md  "blank template is shipped machinery"
  _pass templates/POSTMORTEM-TEMPLATE.md    "blank template is shipped machinery"
  _pass scripts/postmortem.sh               "shipped maintainer script (not a report)"
  _hit  docs/adoption/templates/a-postmortem.md "candid report under a nested templates/ (M1: no smuggling)"
  _pass SECURITY.md                         "product vocabulary is not a record"
  # case variant, in its OWN tree (it would collide with postmortems/ on a case-insensitive macOS FS)
  _t_main=$_t
  _t=$(mktemp -d "${TMPDIR:-/tmp}/sw-pub-st-case.XXXXXX") || die "mktemp failed"
  mkdir -p "$_t/Postmortems"; : > "$_t/Postmortems/y.md"
  _hit  Postmortems/y.md                    "case variant: the gate is the backstop where git archive is case-sensitive"
  rm -rf "$_t"; _t=$_t_main

  # rc contract — the scan must fail CLOSED, and the caller idiom must surface it.
  if sensitive_hits "$_t/does-not-exist" >/dev/null 2>&1; then
    echo "  FAIL non-directory scanned as if clean (rc 0)"; _fail=$((_fail+1))
  else
    echo "  ok   RC    non-existent tree -> non-zero rc (fail-closed)"
  fi

  # --- P1.2-pre-b: the immutability rule (pure decision) ----------------------------------------
  echo "publish-public --selftest: immutable released tags"
  _dec() {  # <want> <tag_published> <changed> <label>
    _got=$(publish_decision "$2" "$3")
    if [ "$_got" = "$1" ]; then echo "  ok   DEC   $4 -> $_got"
    else echo "  FAIL $4: want $1 got $_got"; _fail=$((_fail+1)); fi
  }
  _dec publish 0 12 "tag NOT published, tree differs        (a new release)"
  _dec publish 0 1  "tag NOT published, one path            (a new release)"
  _dec publish 0 0  "tag ABSENT, tree matches               (PARTIAL PUBLISH -> publish the missing tag)"
  _dec noop    1 0  "tag published, tree IDENTICAL          (benign re-run stays GREEN)"
  _dec refuse  1 1  "tag PUBLISHED, tree DIFFERS            (THE DEFECT -> refuse)"
  _dec refuse  1 99 "tag PUBLISHED, tree differs a lot      (THE DEFECT -> refuse)"

  # --- P1.2-pre-b: prove the SECOND layer is real, not asserted ---------------------------------
  # The refusal above is our logic. Underneath it, a NON-FORCE `git push` of an existing tag must be
  # rejected by git itself — that is what still holds if a concurrent publish lands the tag between
  # our clone and our push (the TOCTOU window our refusal cannot close). Do not take this on faith:
  # exercise it against a real local repo (git ls-remote/push accept a path — no network, no creds).
  _g="$_t/immutable"; mkdir -p "$_g/remote" "$_g/work"
  ( cd "$_g/remote" && git init --quiet --bare ) 2>/dev/null
  (
    cd "$_g/work" && git init --quiet && git config user.email t@t && git config user.name t
    echo one > f && git add f && git commit --quiet -m one
    git tag v9.9.9 && git push --quiet "$_g/remote" HEAD:main "refs/tags/v9.9.9"
    echo two > f && git commit --quiet -am two && git tag -f v9.9.9   # move the tag locally
  ) >/dev/null 2>&1
  if ( cd "$_g/work" && git push --quiet "$_g/remote" "refs/tags/v9.9.9" ) >/dev/null 2>&1; then
    echo "  FAIL PUSH  a NON-FORCE tag push MOVED an existing tag (the second layer is not real!)"; _fail=$((_fail+1))
  else
    echo "  ok   PUSH  non-force tag push REFUSES to move a published tag (second layer holds)"
  fi
  # ...and the load-bearing negative: --force DOES move it, so the fixture above is live, not vacuous.
  if ( cd "$_g/work" && git push --quiet --force "$_g/remote" "refs/tags/v9.9.9" ) >/dev/null 2>&1; then
    echo "  ok   PUSH  --force DOES move it (so the non-force result above is load-bearing)"
  else
    echo "  FAIL PUSH  --force failed to move the tag — the fixture proves nothing"; _fail=$((_fail+1))
  fi

  # --- PUB-CHANGELOG: the GitHub Release note is the CURATED public block, NEVER the internal bullets
  echo "publish-public --selftest: public release-notes extraction"
  _cl="$_t/CHANGELOG.md"
  cat > "$_cl" <<'EOF'
# Changelog

## [9.9.9] — 2026-01-01
<!-- public:start -->
Ninety-nine: the user-facing summary.
<!-- public:end -->
### Changed — internal headline
- INTERNAL-ONLY sausage bullet (CP-XYZ) that must NOT reach public.

## [9.9.8] — 2026-01-01
<!-- public:start -->
Older release summary.
<!-- public:end -->
### Changed
- older internal bullet.
EOF
  _notes=$(extract_public_notes 9.9.9 "$_cl")
  if printf '%s' "$_notes" | grep -q "Ninety-nine: the user-facing summary."; then
    echo "  ok   NOTES extracts the public block for the target version"
  else
    echo "  FAIL NOTES did not extract the public block"; _fail=$((_fail+1))
  fi
  if printf '%s' "$_notes" | grep -qE "INTERNAL-ONLY|sausage"; then
    echo "  FAIL NOTES leaked the internal bullets into the public release note"; _fail=$((_fail+1))
  else
    echo "  ok   NOTES ships ONLY the public block (no internal detail leaks)"
  fi
  if printf '%s' "$_notes" | grep -q "Older release summary"; then
    echo "  FAIL NOTES bled into an adjacent version's block"; _fail=$((_fail+1))
  else
    echo "  ok   NOTES scoped to the target version only"
  fi
  if [ -z "$(extract_public_notes 9.9.7 "$_cl")" ]; then
    echo "  ok   NOTES empty for a version with no public block (caller fails closed)"
  else
    echo "  FAIL NOTES returned content for a version that has none"; _fail=$((_fail+1))
  fi
  # HIGH-1 (security): a dangling start (no matching end) must fail CLOSED — never spill the bullets.
  _cld="$_t/CHANGELOG-dangling.md"
  cat > "$_cld" <<'EOF'
# Changelog

## [7.7.7] — 2026-01-01
<!-- public:start -->
Public summary with NO end marker.
### Changed — internal
- INTERNAL sausage bullet that must NEVER leak.

## [7.7.6] — 2026-01-01
<!-- public:start -->
older summary.
<!-- public:end -->
EOF
  _dangling=$(extract_public_notes 7.7.7 "$_cld") || true
  if [ -z "$_dangling" ]; then
    echo "  ok   NOTES dangling start (no end marker) -> empty (fail-closed)"
  else
    echo "  FAIL NOTES leaked past a dangling start marker"; _fail=$((_fail+1))
  fi
  if printf '%s' "$_dangling" | grep -q "sausage"; then
    echo "  FAIL NOTES leaked the internal bullet on a dangling start"; _fail=$((_fail+1))
  else
    echo "  ok   NOTES no internal bullet leaks on a dangling start"
  fi

  # --- PUBLIC-DEIDENT-FIXTURE-LOGINS: `--gate` on a throwaway git repo ---------------------------------
  # FAITHFUL, not stubbed: the throwaway repo carries COPIES of the real publish-public.sh and
  # adopter-export.sh, so `--gate` derives its ROOT from its own location (no override knob needed) and
  # exports the repo's committed HEAD through the real generator. The identifier list is the selftest's
  # TEST list (PUBLISH_ID_FILE above) — never the real .publish-identifiers.
  echo "publish-public --selftest: --gate (per-PR Layer-2 scan of committed HEAD)"
  _gate_repo() {  # <dir> <fixture-body> <public-block-body>
    mkdir -p "$1/scripts" "$1/docs"
    cp "$ROOT/scripts/publish-public.sh" "$1/scripts/publish-public.sh"
    cp "$ROOT/scripts/adopter-export.sh" "$1/scripts/adopter-export.sh"
    # the kit export-ignores CHANGELOG.md too; this copy of the script holds the TEST tokens as literals
    # (it is the machinery under test, not a shipped fixture), so it must not be exported into the scan.
    printf 'CHANGELOG.md export-ignore\nscripts/publish-public.sh export-ignore\n' > "$1/.gitattributes"
    printf '%s\n' "$2" > "$1/docs/fixture.md"
    printf '# Changelog\n\n## [1.0.0]\n<!-- public:start -->\n%s\n<!-- public:end -->\n- internal bullet\n' "$3" > "$1/CHANGELOG.md"
    ( cd "$1" && git init -q && git config user.email t@t && git config user.name t \
        && git add -A && git commit -q -m fixture ) >/dev/null 2>&1
  }
  _gate_run() {  # <dir> [extra-flag] [id-file]  -> sets _grc and _gout
    _grc=0
    _gout=$( cd "$1" && env -u GIT_DIR -u GIT_WORK_TREE PUBLISH_ID_FILE="${3:-$PUBLISH_ID_FILE}" sh scripts/publish-public.sh --gate ${2:-} 2>&1 ) || _grc=$?
  }
  _gate_commit() {  # <dir> — commit whatever the test just changed in the throwaway repo
    ( cd "$1" && git add -A && git commit -q -m change ) >/dev/null 2>&1
  }
  _want_rc() {  # <want> <pass-label> <fail-label>
    if [ "$_grc" -eq "$1" ]; then echo "  ok   $2"; else echo "  FAIL $3: want rc $1, got rc $_grc"; _fail=$((_fail+1)); fi
  }
  _no_value() {  # <label> <planted value>
    if printf '%s' "$_gout" | grep -qiF -e "$2"; then echo "  FAIL VALUE $1: output echoed the planted identifier"; _fail=$((_fail+1))
    else echo "  ok   VALUE $1: the planted identifier is never echoed"; fi
  }
  _gate_repo "$_t/gate-tree" "seat: ACME-OWNER-TOKEN-42 reviews this" "A clean user-facing summary."
  _gate_run "$_t/gate-tree"
  if [ "$_grc" -eq 1 ] && printf '%s\n' "$_gout" | grep -qxF "  docs/fixture.md"; then
    echo "  ok   GATE  identifier in a shipped fixture -> rc 1, file named"
  else echo "  FAIL GATE  tree plant: want rc 1 naming docs/fixture.md, got rc $_grc"; _fail=$((_fail+1)); fi
  _no_value "tree plant" "ACME-OWNER-TOKEN-42"
  _gate_repo "$_t/gate-note" "a clean fixture" "Shipped with help from ownerlogin."
  _gate_run "$_t/gate-note"
  if [ "$_grc" -eq 1 ] && printf '%s\n' "$_gout" | grep -qF "CHANGELOG.md (between"; then
    echo "  ok   GATE  identifier in a CHANGELOG public block -> rc 1, release note named"
  else echo "  FAIL GATE  note plant: want rc 1 naming the CHANGELOG public block, got rc $_grc"; _fail=$((_fail+1)); fi
  _no_value "note plant" "ownerlogin"
  _gate_repo "$_t/gate-clean" "a clean fixture" "A clean user-facing summary."
  _gate_run "$_t/gate-clean"
  if [ "$_grc" -eq 0 ]; then echo "  ok   GATE  clean tree + clean notes -> rc 0 (the red above is load-bearing)"
  else echo "  FAIL GATE  clean repo: want rc 0, got rc $_grc ($_gout)"; _fail=$((_fail+1)); fi
  # an identifier in a NON-public part of CHANGELOG.md is out of scope (internal history is not shipped)
  _gate_repo "$_t/gate-internal" "a clean fixture" "A clean user-facing summary."
  # ...including after a header-prose line that names BOTH markers inline (not a block: must not open one)
  printf -- '> each entry carries a <!-- public:start -->...<!-- public:end --> block\n- internal note about ownerlogin\n' >> "$_t/gate-internal/CHANGELOG.md"
  ( cd "$_t/gate-internal" && git commit -q -am internal ) >/dev/null 2>&1
  _gate_run "$_t/gate-internal"
  if [ "$_grc" -eq 0 ]; then echo "  ok   GATE  identifier only in the internal (non-public) changelog, even after an inline marker mention -> rc 0 (not shipped)"
  else echo "  FAIL GATE  internal-only plant should not red, got rc $_grc"; _fail=$((_fail+1)); fi

  # S-1: the gate must scan AT LEAST what the publish ships. A line naming BOTH markers inside a `## [v]`
  # section opens a block for extract_public_notes (the publish's extractor) — the gate scans its output too.
  _gate_repo "$_t/gate-both" "a clean fixture" "A clean user-facing summary."
  printf '## [2.0.0]\n> prose <!-- public:start -->x<!-- public:end --> inline\nthanks to ownerlogin\n<!-- public:end -->\n' >> "$_t/gate-both/CHANGELOG.md"
  _gate_commit "$_t/gate-both"
  _gate_run "$_t/gate-both"
  if [ "$_grc" -eq 1 ] && printf '%s\n' "$_gout" | grep -qF "CHANGELOG.md (between"; then
    echo "  ok   GATE  both-markers line inside a version section: what the publish extractor ships is scanned -> rc 1"
  else echo "  FAIL GATE  both-markers divergence: want rc 1 naming the release note, got rc $_grc"; _fail=$((_fail+1)); fi
  _no_value "both-markers plant" "ownerlogin"

  # S-2: fail-closed WIRING — an exporter that fails, or a missing CHANGELOG, is rc 2 (never clean, never rc 1/0).
  _gate_repo "$_t/gate-exportfail" "a clean fixture" "A clean user-facing summary."
  # the stub leaves a partial CLEAN tree behind before failing, so only the exporter's rc (not a later scan
  # error on an empty/absent tree) can produce rc 2 — deleting the gate's exit-2 on export failure goes red.
  printf 'mkdir -p "$1"; echo ok > "$1/a.md"; exit 1\n' > "$_t/gate-exportfail/scripts/adopter-export.sh"
  _gate_commit "$_t/gate-exportfail"
  _gate_run "$_t/gate-exportfail"
  _want_rc 2 "GATE  adopter-export failing -> rc 2 (fail-closed)" "GATE  exporter failure"
  if printf '%s\n' "$_gout" | grep -qF "gate: clean"; then echo "  FAIL GATE  exporter failure printed a clean line"; _fail=$((_fail+1))
  else echo "  ok   GATE  exporter failure prints no clean line"; fi
  _gate_repo "$_t/gate-nocl" "a clean fixture" "A clean user-facing summary."
  ( cd "$_t/gate-nocl" && git rm -q CHANGELOG.md && git commit -q -m nocl ) >/dev/null 2>&1
  _gate_run "$_t/gate-nocl"
  _want_rc 2 "GATE  no CHANGELOG.md at HEAD -> rc 2 (the note scan cannot run)" "GATE  absent CHANGELOG"

  # S-3: --require-ids — a vacuous identifier dimension is rc 2 only when the caller demands the list.
  _gate_run "$_t/gate-clean" --require-ids "$_t/no-such-ids"
  _want_rc 2 "GATE  --require-ids with an ABSENT list -> rc 2" "GATE  require-ids absent"
  printf '# only comments\n\n   \n' > "$_t/ids-comments"
  _gate_run "$_t/gate-clean" --require-ids "$_t/ids-comments"
  _want_rc 2 "GATE  --require-ids with a COMMENTS-ONLY list -> rc 2" "GATE  require-ids comments-only"
  _gate_run "$_t/gate-clean" "" "$_t/no-such-ids"
  _want_rc 0 "GATE  absent list WITHOUT --require-ids keeps the N/A behaviour -> rc 0" "GATE  absent list default"
  _gate_run "$_t/gate-clean" --require-ids
  _want_rc 0 "GATE  --require-ids with a populated list -> rc 0" "GATE  require-ids populated"

  # S-4: the exporter reads the WORKTREE .gitattributes, so an uncommitted edit would scan a hybrid.
  printf '# uncommitted\n' >> "$_t/gate-clean/.gitattributes"
  _gate_run "$_t/gate-clean"
  _want_rc 2 "GATE  uncommitted .gitattributes -> rc 2 (refuses to scan a hybrid)" "GATE  dirty gitattributes"

  rm -rf "$_t"; rm -f "$PUBLISH_ID_FILE"
  [ "$_fail" -eq 0 ] || { echo "publish-public --selftest: $_fail failed" >&2; exit 1; }
  echo "publish-public --selftest: all passed"
  exit 0
}
[ "$SELFTEST" -eq 1 ] && selftest
[ "$REQUIRE_IDS" -eq 1 ] && [ "$GATE" -eq 0 ] && { echo "publish-public: --require-ids is only valid with --gate" >&2; usage; }
[ "$GATE" -eq 1 ] && gate

# --- preconditions ------------------------------------------------------------------------------
cd "$ROOT"
[ -f VERSION ] || die "no VERSION at $ROOT — not a kit root"
VERSION=$(cat VERSION)
[ -n "$VERSION" ] || die "VERSION is empty"
TAG="v$VERSION"

# The export archives COMMITTED HEAD, not the worktree. A dirty tree means what you are looking at is
# NOT what would publish — refuse rather than publish a tree nobody reviewed.
[ -z "$(git status --porcelain)" ] || die "worktree is dirty — the export archives committed HEAD, so this would publish something other than what you see. Commit or stash first."

if [ "$ALLOW_UNTAGGED" -eq 0 ]; then
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1 || die "no tag $TAG — a publish promotes a RELEASE. Tag it, or pass --allow-untagged."
  [ "$(git rev-parse "refs/tags/$TAG^{commit}")" = "$(git rev-parse HEAD)" ] || die "HEAD is not the commit tagged $TAG — refusing to publish an unreleased tree."
fi

# PUB-CHANGELOG — a release must carry a curated public note (fail-closed: never publish a release with
# empty notes, and never fall back to the internal bullets). Checked on --dry-run too, so a missing block
# is caught before the real publish, not after the tag is already pushed.
PUBLIC_NOTES=$(extract_public_notes "$VERSION") || PUBLIC_NOTES=""
[ -n "$PUBLIC_NOTES" ] || die "no public release note for $VERSION — add a complete '<!-- public:start -->…<!-- public:end -->' block to its CHANGELOG.md entry (a dangling start also fails here). It becomes the GitHub Release note; the internal bullets never ship."

WORK=$(mktemp -d "${TMPDIR:-/tmp}/sw-publish.XXXXXX") || die "mktemp failed"
# Release-hygiene: the export + mirror clones under $WORK are throwaway. Reap them on ANY exit path
# (success, die, or signal) so a real publish does not leak a ~20 MB sw-publish.* tree per run
# (462 MB / 23 leaks measured 2026-07-23). Set immediately after $WORK exists so an early die still cleans.
# EXCEPTION (CP7R5-PUBLISH-DRYRUN-TREE): on --dry-run, step [5/5] hands the operator this tree to INSPECT,
# so PRESERVE it there — the unconditional reap deleted the very path the [5/5] message points at. DRY_RUN
# is parsed above; a real publish (DRY_RUN=0) still reaps.
[ "$DRY_RUN" -eq 1 ] || trap 'rm -rf "$WORK"' EXIT
TREE="$WORK/export"
MIRROR="$WORK/public"
say "kit $VERSION ($TAG) -> $REMOTE"

# --- 1. GENERATE — no hand-selection ------------------------------------------------------------
say "[1/5] generate — adopter-export from committed HEAD"
sh scripts/adopter-export.sh "$TREE" >/dev/null || die "adopter-export failed — nothing published"
say "      exported $(find "$TREE" -type f | wc -l | tr -d ' ') files"

# --- 2. GATE — deny-by-default; rc-driven; abort on any hit OR any scan failure ------------------
say "[2/5] gate — sensitivity scan + gitleaks (fail-closed)"
if ! HITS=$(sensitive_hits "$TREE"); then
  die "ABORT — the sensitivity scan could not complete (unreadable path or tool error). An unscannable tree is not proven clean. Nothing published."
fi
if [ -n "$HITS" ]; then
  echo "publish-public: ABORT — Layer-2 gate found content that must not go public:" >&2
  echo "$HITS" | sed 's/^/  /' >&2
  die "nothing published."
fi
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --source "$TREE" --no-git --redact --exit-code 1 >/dev/null 2>&1 \
    || die "ABORT — gitleaks found a secret in the export. Nothing published."
  say "      gitleaks: no leaks"
else
  die "ABORT — gitleaks is not installed, and a publish must not be less safe because a tool is missing (fail-closed)."
fi

# --- 2b. GATE THE RELEASE NOTE — the note is extracted from CHANGELOG.md, which is export-IGNORED and
#     therefore ABSENT from the tree the scan above saw (security HIGH-2). Without this, the note reaches
#     the public (indexed) Releases page with NO leak gate — the tree gates never inspect it, and step-4
#     shows the tree diff, not the note. Scan it with the SAME tools, fail-closed, before any publish.
NOTE_DIR="$WORK/note"; mkdir -p "$NOTE_DIR"
printf '%s\n' "$PUBLIC_NOTES" > "$NOTE_DIR/release-notes.md"
if ! NOTE_HITS=$(sensitive_hits "$NOTE_DIR"); then
  die "ABORT — the release note could not be scanned. Nothing published."
fi
[ -z "$NOTE_HITS" ] || die "ABORT — the release note for $VERSION carries withheld/owner content ($NOTE_HITS). Fix its CHANGELOG public block. Nothing published."
gitleaks detect --source "$NOTE_DIR" --no-git --redact --exit-code 1 >/dev/null 2>&1 \
  || die "ABORT — gitleaks found a secret in the release note for $VERSION. Nothing published."
say "      release note: scanned clean"

# --- 3. MIRROR — full sync incl. deletes, so the public tree == the export exactly ---------------
say "[3/5] mirror — full sync into the public repo (adds, updates, DELETES)"
git clone --quiet "$REMOTE" "$MIRROR" 2>/dev/null || die "could not clone $REMOTE"
# P1.2-pre-b — IMMUTABLE RELEASED TAGS. The clone carries the remote's tags, so we can learn HERE
# whether $TAG is already published, before anything is written or pushed. The refusal itself fires
# after CHANGED is known (below): a tag that is published AND whose tree still matches is a benign
# idempotent re-run (the existing CHANGED -eq 0 no-op) and must stay green — a gate that fires on the
# happy path teaches people to ignore it (release-tagged.sh's doctrine). The case that must NEVER be
# allowed is published-tag + DIFFERENT tree: that is a silent tag MOVE under every pinned adopter.
TAG_PUBLISHED=0
( cd "$MIRROR" && git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1 ) && TAG_PUBLISHED=1
# Delete everything tracked (preserve .git), then lay the export down: no stale file survives a
# release in which it was removed.
find "$MIRROR" -mindepth 1 -maxdepth 1 -not -name '.git' -exec rm -rf {} + 2>/dev/null || true
# Two-step tar via a file — NOT a pipe. POSIX sh has no pipefail, so a piped `tar cf - | tar xf -`
# would swallow a read-side failure (the I2 mask this closes); each stage's rc is observed here.
( cd "$TREE"   && tar cf "$WORK/export.tar" . ) || die "mirror: reading the export tree failed"
( cd "$MIRROR" && tar xf "$WORK/export.tar"    ) || die "mirror: writing into the public clone failed"

# --- 4. REVIEW — the human backstop the denylist cannot replace -----------------------------------
say "[4/5] review — what changes in the public repo:"
( cd "$MIRROR" && git add -A && git status --short | head -50 )
CHANGED=$(cd "$MIRROR" && git status --porcelain | wc -l | tr -d ' ')
say "      $CHANGED path(s) changed"
case "$(publish_decision "$TAG_PUBLISHED" "$CHANGED")" in
  noop)
    ensure_release   # tag+tree already published; converge a Release a prior gh failure left missing
    say "nothing to publish — public repo already matches $TAG"; exit 0 ;;
  refuse)
    echo "publish-public: REFUSING — $TAG is ALREADY PUBLISHED on $REMOTE, but the export differs from the published tree ($CHANGED path(s) would change)." >&2
    echo "  A released tag is IMMUTABLE. Publishing would silently move $TAG out from under every adopter pinned to it." >&2
    die "Bump VERSION and publish a NEW release. Nothing published." ;;
esac

# --- 5. PUBLISH ----------------------------------------------------------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
  say "[5/5] --dry-run — NOT publishing. Generated tree: $TREE"
  exit 0
fi
say "[5/5] publish — commit + tag $TAG + push"
# EACH step is checked (dual review, security M1): a `( … ) || die` subshell suppresses errexit and
# reports only its LAST command's status, so a failed `git commit` — realistic, since a fresh mirror
# clone inherits NO git identity — would let `git tag` tag the STALE head and the pushes publish a NEW
# version tag pointing at OLD code, exit 0, "published". So: set an explicit committer identity, check
# every step, and TOLERATE an empty commit (the partial-publish case: tree already matches, only the
# tag is missing — `publish_decision` sent us here precisely to add it).
(
  cd "$MIRROR" || die "publish: cannot enter the mirror clone"
  git config user.email "publish-bot@sparkwright.local" || die "publish: could not set committer email"
  git config user.name  "sparkwright publish-public"    || die "publish: could not set committer name"
  if git diff --cached --quiet; then
    say "      tree already matches — publishing the MISSING tag only (partial-publish convergence)"
  else
    git commit --quiet -m "Release $TAG

Generated from the Sparkwright kit at $TAG by scripts/publish-public.sh.
This repository is a generated snapshot of the shippable product — do not edit by hand." \
      || die "publish: git commit failed — nothing published"
  fi
  # No `-f`/`--force`: the refusal above PROVED $TAG is not published, so both would only mask a bug.
  # A non-force tag push is rejected by git if it would MOVE a ref — the second layer under the
  # refusal, and the one that still holds if a concurrent publish landed the tag between our clone and
  # our push (the TOCTOU window the refusal alone cannot close).
  git tag "$TAG"                          || die "publish: git tag $TAG failed — nothing published"
  git push --quiet origin HEAD:main       || die "publish: push of main failed — re-run to converge"
  git push --quiet origin "refs/tags/$TAG" || die "publish: tag push failed (a concurrent publish may have landed $TAG) — nothing moved"
) || exit 1

# PUB-CHANGELOG — the tag pushed above IS the release; add the curated note as a GitHub Release so the
# public repo has a changelog (its "Releases" page). Same idempotent helper the noop path uses.
ensure_release

say "published $TAG -> $REMOTE"
