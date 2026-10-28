#!/bin/sh
# publish-public.sh — promote a released kit into the PUBLIC product repo.
#   sh scripts/publish-public.sh [--remote <url>] [--dry-run] [--allow-untagged] [--selftest]
#   sh scripts/publish-public.sh --gate [--require-ids] [--ids-base <rev>]   # (--ids-base: WARN, counts only, when the list drops entries <rev> had; --require-ids: rc 2 if the identifier list is absent/empty) read-only Layer-2 scan of committed HEAD; runs on every PR (CI secret-scan)
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
# Release-note reference floor (SWAS-366): the newest CHANGELOG heading EXEMPT from public_note_refs and from
# the malformed-marker finding. That heading and every OLDER one (the file is newest-first) are not graded,
# because their published blocks predate the rule and cite things (an export-ignored path such as the tracker
# conf, say) that the rule refuses. Task 0 of the build measured it. A plain assignment, no env seam: a standing
# exemption moves only by a reviewed edit here. Empty means grade every block.
# The floor is a VERSION compare, never a position: a heading is exempt only if it is a plain semver N.N.N that
# is numerically <= the floor, field by field. Anything else (`Unreleased` too) is graded, and a stray or
# misordered floor heading cannot exempt a newer block below it (SWAS-366 security S1). `_PNR_VLE` is the one
# awk compare function; public_note_refs prepends it to its program and `_pnr_exempt` runs it for the gate.
PUBNOTE_REF_FLOOR=3.240.0
_PNR_VLE='function vle(v, f,   a, b, i, x, y) {
  if (f == "" || v !~ /^[0-9]+[.][0-9]+[.][0-9]+$/) return 0
  split(v, a, "."); split(f, b, ".")
  for (i = 1; i <= 3; i++) { x = a[i] + 0; y = b[i] + 0; if (x < y) return 1; if (x > y) return 0 }
  return 1
}'
_pnr_exempt() { PNR_HEADING=$1 LC_ALL=C awk -v f="$PUBNOTE_REF_FLOOR" "$_PNR_VLE"' BEGIN { exit (vle(ENVIRON["PNR_HEADING"], f) ? 0 : 1) }'; }   # ENVIRON, not -v: -v unescapes backslashes

usage() { echo "usage: publish-public.sh [--remote <url>] [--dry-run] [--allow-untagged] | --gate [--require-ids] [--ids-base <rev>] | --selftest" >&2; exit 2; }

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
  # ONE marker grammar (SWAS-366). rc 0 = a block (printed), rc 1 = no block, rc 3 = a MALFORMED block, with
  # nothing printed: two markers on one line, or a second start before the end. The gate reads rc 3 as the
  # `[malformed-block]` finding and the publish path refuses it, so a one-line block can no longer open a block
  # that spills the internal bullets after it. The lines ending `# PNR-RC3` or `# PNR-BOTH` are the rc-3 clause
  # (the selftest mutant PNM2 deletes both; PNM4 deletes only the both-markers line, `# PNR-BOTH`). The text before the first `## [` heading (the header prose) is not an entry.
  awk -v ver="$_epn_ver" '
    index($0, "## [" ver "]") == 1 { insec=1; next }                 # closing "]" stops 9.9.9==9.9.99
    insec && index($0, "## [") == 1 { exit }                         # left the entry (emit iff done)
    insec {
      s = index($0, "<!-- public:start -->"); e = index($0, "<!-- public:end -->")
      if (s && e) { bad = 1; exit }                                  # PNR-BOTH
      if (s && started) { bad = 1; exit }                            # PNR-RC3
      if (s) { started = 1; next }
      if (e && started) { done = 1; exit }
      if (started) buf = buf $0 ORS
    }
    END { if (bad) exit 3; if (done) printf "%s", buf; else exit 1 }
  ' "$_epn_file"
}

# --- SWAS-366 — a public block may not point at anything a public reader cannot open --------------------
# The public repo is a generated mirror with no PR history, so a PR number there links to nothing or to the
# wrong item (the v3.241.0 note cited #891 and #880-#889), and its change log and export-ignored files do not
# exist. public_note_refs <changelog> <scope> [<tracker-conf>] reads the public blocks of <changelog> (<scope>
# is a version, or `all`; PUBNOTE_REF_FLOOR and older are not graded; the header prose before the first
# `## [` heading is not an entry) and prints one DEDUPLICATED line per finding, `[<kind>] CHANGELOG.md:<line>
# [<version>]`, never the matched text. Kinds:
#   [pr-ref]           #<digits> (not after a letter, digit, _, & or /), PR #N / PR#N, owner/repo#N, GH-N,
#                      an encoded &#35; / &#x23; / &num; before a digit (any case), and a forge URL whose path
#                      holds /pull(s)/, /issues/ or /commit(s)/ plus a hex run, or a scheme-less (or schemed)
#                      github/gitlab/bitbucket .com/.org /<o>/<r>/ path under pull(s), issues, commit(s), compare,
#                      tree or blob (an optional www. too). Over-denied on purpose: links into the public repo's own
#                      tree/blob are refused. file.md#anchor is not a finding. A forge host written some other way, or a
#                      self-hosted forge, passes (stated ceiling).
#   [tracker-key]      <KEY><sep><digits>, sep one of space, _ or -, KEY = the project= value of <tracker-conf>
#                      (default .kit/tracker.conf), case-INsensitive, word-bounded (a short or common-word key such
#                      as IT can match prose like "it 3": it fails loudly and is cured by rewording). It must match ^[A-Z][A-Z0-9]+$, else rc 2 (it enters a
#                      regex). No conf: one N/A note on stderr, unless CLAUDE.md declares the Jira backend
#                      (the kit's own repo), where a missing conf is rc 2 (fail closed).
#   [internal-pointer] the text [Unreleased], or the word changelog (any case).
#   [export-ignored]   a path-like token (holds / or ends .md .sh .conf .yml .yaml .txt .json), minus trailing
#                      punctuation and a leading ./ or /, that the root .gitattributes marks export-ignore
#                      (git check-attr --stdin -z). A token that starts with .., holds a .. component or holds
#                      :// is skipped. Only paths the file matches AS WRITTEN are seen: a directory pattern
#                      or a path written without its last part passes (stated ceiling).
# rc 0 clean · 1 findings · 2 could not read (fail closed). Tokens are cut in awk and travel through files, so no
# token ever meets a shell glob or word split. The awk keeps every regex on one line ending `# PNK-<kind>`
# where the selftest's per-kind mutants delete it. No awk builtin is used as a variable name (the F1 trap).
public_note_refs() {
  _pr_cl=$1; _pr_scope=$2; _pr_conf=${3:-$ROOT/.kit/tracker.conf}
  [ -f "$_pr_cl" ] || { echo "SCAN-ERROR: no changelog to read" >&2; return 2; }
  _pr_d=$(mktemp -d "${TMPDIR:-/tmp}/sw-pnr.XXXXXX") || return 2
  _pr_rc=0
  _pnr_run "$_pr_cl" "$_pr_scope" "$_pr_conf" "$_pr_d" || _pr_rc=$?
  rm -rf "$_pr_d"
  return "$_pr_rc"
}

# _pnr_key <conf> — prints the tracker project key ('' = none to check); rc 2 = fail closed.
_pnr_key() {
  if [ ! -f "$1" ]; then
    if [ -f "$ROOT/CLAUDE.md" ] && grep -Eq 'Backlog backend[^:]*: *Jira' "$ROOT/CLAUDE.md"; then
      echo "SCAN-ERROR: CLAUDE.md declares the Jira backend but the tracker conf is missing, so the tracker key cannot be read" >&2
      return 2
    fi
    echo "publish-public: note: no tracker conf - the [tracker-key] kind is N/A" >&2
    return 0
  fi
  _pk=$(sed -n 's/^project=//p' "$1" | head -1 | tr -d '\r') || return 2
  if ! printf '%s\n' "$_pk" | LC_ALL=C grep -Eq '^[A-Z][A-Z0-9]+$'; then
    echo "SCAN-ERROR: the tracker conf project key is missing or is not an upper-case key" >&2
    return 2
  fi
  printf '%s\n' "$_pk"
}

# _pnr_run <changelog> <scope> <conf> <workdir> — the body of public_note_refs (see above).
_pnr_run() {
  _pr_key=$(_pnr_key "$3") || return 2
  # characters that wrap a token; the colon stays (a URL is skipped by its ://) and the brackets go below
  _pr_wrap="[(){}<>,;=\"'\`!?|]"
  LC_ALL=C awk -v scope="$2" -v floor="$PUBNOTE_REF_FLOOR" -v key="$_pr_key" -v wrap="$_pr_wrap" "$_PNR_VLE"'
    function hit(kind) { printf "F\t%s\t%d\t%s\n", kind, NR, ver }
    function tok(x) {
      sub("[.:]+$", "", x); sub("^[.]/", "", x); sub("^/+", "", x)
      if (x == "" || index(x, "://") || x ~ "^[.][.]" || x ~ "(^|/)[.][.](/|$)") return
      if (index(x, "/") || x ~ "[.](md|sh|conf|yml|yaml|txt|json)$") printf "T\t%s\t%d\t%s\n", x, NR, ver
    }
    function scan(t,   lo, u, y, n, w, i) {
      lo = tolower(t); u = t
      gsub("([A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+[.](md|sh|yml|yaml|txt|json|conf)#", "X", u)
      if (u ~ "(^|[^A-Za-z0-9_&/])#[0-9]+" || lo ~ "(^|[^a-z0-9_])pr ?#[0-9]+" || u ~ "[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+" || lo ~ "(^|[^a-z0-9_])gh-[0-9]+" || lo ~ "&(#35|#x23|num);[0-9]") hit("pr-ref")   # PNK-pr
      n = split(lo, w, "[ \t]+")
      for (i = 1; i <= n; i++) if ((index(w[i], "://") && w[i] ~ "/(pulls?|issues|commits?)/[0-9a-f]+") || w[i] ~ "(^|[^a-z0-9._-])(www[.])?(github|gitlab|bitbucket)[.](com|org)/[^/]+/[^/]+/(pulls?|issues|commits?|compare|tree|blob)/") hit("pr-ref")   # PNK-url
      if (key != "" && lo ~ ("(^|[^a-z0-9_])" tolower(key) "[ _-][0-9]+([^a-z0-9_]|$)")) hit("tracker-key")   # PNK-key
      if (index(lo, "[unreleased]") || index(lo, "changelog")) hit("internal-pointer")   # PNK-ptr
      y = t; gsub("\\[", " ", y); gsub("\\]", " ", y); gsub(wrap, " ", y)
      n = split(y, w, "[ \t]+")
      for (i = 1; i <= n; i++) tok(w[i])
    }
    BEGIN { ver = ""; exempt = 0; on = 0 }
    index($0, "## [") == 1 {
      v = substr($0, 5); i = index(v, "]"); ver = (i > 0) ? substr(v, 1, i - 1) : v
      on = 0
      exempt = 0   # PNM5
      if (vle(ver, floor)) exempt = 1
      next
    }
    ver == "" || exempt || (scope != "all" && ver != scope) { next }
    { s = index($0, "<!-- public:start -->"); e = index($0, "<!-- public:end -->") }
    s && e { next }
    s { on = 1; next }
    e { on = 0; next }
    on { scan($0) }
  ' "$1" > "$4/raw" || { echo "SCAN-ERROR: the release-note reference read failed" >&2; return 2; }
  awk -F '\t' '$1 == "F" { printf "[%s] CHANGELOG.md:%s [%s]\n", $2, $3, $4 }' "$4/raw" > "$4/found" || return 2
  awk -F '\t' '$1 == "T" { print $2 }' "$4/raw" > "$4/toks.raw" || return 2
  LC_ALL=C sort -u "$4/toks.raw" > "$4/toks" || return 2
  : > "$4/exfound"
  if [ -s "$4/toks" ]; then
    _pnr_export_ignored "$4" || return 2
  fi
  LC_ALL=C sort -u "$4/found" "$4/exfound" > "$4/all" || return 2
  if [ -s "$4/all" ]; then cat "$4/all"; return 1; fi
  return 0
}

# _pnr_export_ignored <workdir> — asks git which of <workdir>/toks the root .gitattributes marks export-ignore,
# and writes `[export-ignored]` findings for them to <workdir>/exfound. The answer is read by position, three
# NUL-separated fields per path (path, attribute, value); a count that is not three per token fails closed.
_pnr_export_ignored() {
  tr '\n' '\000' < "$1/toks" > "$1/toks0" || return 2
  git -C "$ROOT" check-attr --stdin -z export-ignore < "$1/toks0" > "$1/ca0" 2> "$1/ca.err" || return 2
  [ ! -s "$1/ca.err" ] || return 2
  tr '\000' '\n' < "$1/ca0" > "$1/ca" || return 2
  _pe_n=$(wc -l < "$1/toks" | tr -d ' '); _pe_c=$(wc -l < "$1/ca" | tr -d ' ')
  [ "$_pe_c" -eq $((_pe_n * 3)) ] || { echo "SCAN-ERROR: the attribute read did not answer every token" >&2; return 2; }
  awk 'NR == FNR { tk[FNR] = $0; next } FNR % 3 == 0 && $0 == "set" { print tk[FNR / 3] }' "$1/toks" "$1/ca" > "$1/setfile" || return 2
  awk -F '\t' 'NR == FNR { st[$0] = 1; next } $1 == "T" && ($2 in st) { printf "[export-ignored] CHANGELOG.md:%s [%s]\n", $3, $4 }' "$1/setfile" "$1/raw" > "$1/exfound"   # PNK-ex
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
IDS_BASE=""
while [ $# -gt 0 ]; do
  case $1 in
    --gate)           GATE=1; shift ;;
    --require-ids)    REQUIRE_IDS=1; shift ;;
    --ids-base)       [ $# -ge 2 ] || usage; IDS_BASE=$2; shift 2 ;;
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
#   - ENTRY FORMS (PUBLISH-GATE-HARDENING), one parser (publish_ids) for the scan and --require-ids:
#       `Acmely`        plain  — a case-insensitive fixed SUBSTRING (the default; unchanged).
#       `word:Acmely`   whole-word — matches `Acmely`, `acmely-corp`, `Acmely.`, not `tacmely` or
#                       `acmely_token`. For a name that is also a substring of an ordinary word. Pinned to
#                       LC_ALL=C (a word character is [A-Za-z0-9_]); an empty or non-ASCII `word:` value is
#                       rc 2, naming the list line number only. A non-ASCII name stays a plain entry.
#     Blank lines, `#` lines (indented too) and a trailing CR (a CRLF list) are ignored/stripped. A typo
#     is refused (rc 2, line number only), never silently matched to nothing: whitespace around an
#     entry or after `word:`, `Word:`/`word :` near-misses of the prefix, and a CR inside an entry.
#   - NAMES (PUBLISH-GATE-HARDENING): every file and directory NAME is scanned with the same entries. A hit
#     prints `<prefix>/<name withheld> [name]`: the value is never echoed (see _redact_path).
#   - SYMLINKS (PUBLISH-GATE-HARDENING): a symlink in the tree is a hit, `<path> [symlink]`. Its target is
#     never read; the kit ships none. Cure: replace it with the file.
#   - The scan runs RELATIVE to the tree (cd into it), so the tree path never reaches a glob or a regex.
# MAINTENANCE OBLIGATION: when a new candid document type appears, add it HERE — step 4 is a
# backstop, not a substitute.
sensitive_hits() {
  _tree=$1
  [ -d "$_tree" ] || { echo "SCAN-ERROR: not a directory: $_tree" >&2; return 2; }
  _errf=$(mktemp "${TMPDIR:-/tmp}/sw-scan.XXXXXX") || return 2
  _idl=$(mktemp "${TMPDIR:-/tmp}/sw-scan-ids.XXXXXX") || { rm -f "$_errf"; return 2; }
  # one parse of the list for the whole scan; a malformed entry is rc 2 (publish_ids names the line).
  publish_ids > "$_idl" || { rm -f "$_errf" "$_idl"; return 2; }

  # The scan runs INSIDE the tree: the tree path never reaches a glob or a regex (`[`, `*`, `?` in a
  # TMPDIR cannot make a rule fail open). A subshell that fails (a failed cd, an aborted pipeline step)
  # is a scan failure, never a clean tree.
  _scan_rc=0
  ( CDPATH='' cd -- "$_tree" && _scan_tree ) 2>>"$_errf" || _scan_rc=$?

  # fail CLOSED: a failed scan, or any stderr from find/grep, means the scan could not see everything.
  if [ "$_scan_rc" -ne 0 ] || [ -s "$_errf" ]; then
    echo "SCAN-ERROR: scan could not complete: $(_err_text "$_errf")" >&2
    rm -f "$_errf" "$_idl"; return 2
  fi
  rm -f "$_errf" "$_idl"
  return 0
}

# _pi_bad <line-number> <reason> — publish_ids' error line: the NUMBER only, never the value.
_pi_bad() { echo "SCAN-ERROR: .publish-identifiers line $1: $2" >&2; }

# publish_ids — the ONE parser of $PUBLISH_ID_FILE (the scan and `--require-ids` both read it).
#   stdout : one normalised entry per line, `plain<TAB>value` or `word<TAB>value`
#   rc     : 0 · 2 = a malformed `word:` entry (SCAN-ERROR names the line NUMBER, never the value)
# An absent file is no entries, rc 0 (the caller decides whether that is acceptable).
publish_ids() {
  [ -f "$PUBLISH_ID_FILE" ] || return 0
  _pi_cr=$(printf '\r'); _pi_tab=$(printf '\t'); _pi_n=0
  while IFS= read -r _pi || [ -n "$_pi" ]; do
    _pi_n=$((_pi_n+1))
    _pi=${_pi%"$_pi_cr"}                                    # a CRLF list: strip one trailing CR
    case $_pi in *"$_pi_cr"*) _pi_bad "$_pi_n" "a carriage return inside an entry (a CR-only list?)"; return 2 ;; esac
    case $_pi in *[![:space:]]*) ;; *) continue ;; esac     # blank
    _pi_lead=${_pi%%[![:space:]]*}
    case ${_pi#"$_pi_lead"} in \#*) continue ;; esac        # comment, indented or not
    # a typo must fail closed, never silently match nothing: whitespace around an entry, and any
    # near-miss of the exact lowercase `word:` prefix, are refused (line number only, never the value).
    case $_pi in
      [[:space:]]*|*[[:space:]]) _pi_bad "$_pi_n" "an entry has leading or trailing whitespace"; return 2 ;;
    esac
    case $_pi in
      word:*)
        _pi_v=${_pi#word:}
        if [ -z "$_pi_v" ] || printf '%s\n' "$_pi_v" | LC_ALL=C grep -q '[^ -~]'; then
          _pi_bad "$_pi_n" "a word: entry must be a non-empty printable-ASCII value (a non-ASCII name is a plain entry)"; return 2
        fi
        case $_pi_v in [[:space:]]*) _pi_bad "$_pi_n" "a word: entry has whitespace after the colon"; return 2 ;; esac
        printf 'word%s%s\n' "$_pi_tab" "$_pi_v" ;;
      [Ww][Oo][Rr][Dd]:*|[Ww][Oo][Rr][Dd][[:space:]]*:*)
        _pi_bad "$_pi_n" "only exactly lowercase word: starts a whole-word entry"; return 2 ;;
      *) printf 'plain%s%s\n' "$_pi_tab" "$_pi" ;;
    esac
  done < "$PUBLISH_ID_FILE"
  return 0
}

# _ids_warn <text> — a gate WARN on stderr; under GitHub Actions it also carries the annotation prefix.
_ids_warn() {
  if [ "${GITHUB_ACTIONS:-}" = true ]; then echo "::warning title=publish identifiers::publish-public: gate: WARN $1" >&2
  else echo "publish-public: gate: WARN $1" >&2; fi
}

# _ids_compare <rev> <tmpdir> — `--gate --ids-base`: count the entries <rev>'s list has that this list lacks
# (a removed, narrowed plain->word:, or substituted entry is one line of set difference). COUNTS ONLY on
# output, never a value. Advisory: always returns 0 (the control-plane ratification is the blocking control).
_ids_compare() {
  _ic_rev=$1; _ic_d=$2; _ic_tab=$(printf '\t'); _ic_s=$(printf '%s' "$_ic_rev" | cut -c1-7)
  case $_ic_rev in -*) _ids_warn "the identifier list was not compared with base $_ic_s: the base rev is unreadable."; return 0 ;; esac
  if ! git rev-parse --verify -q "$_ic_rev^{commit}" >/dev/null 2>&1; then
    _ids_warn "the identifier list was not compared with base $_ic_s: the base rev is unreadable."; return 0
  fi
  if ! git cat-file -e "$_ic_rev:.publish-identifiers" 2>/dev/null; then
    say "identifier list: the base has none, nothing to compare"; return 0
  fi
  git show "$_ic_rev:.publish-identifiers" > "$_ic_d/base.list" 2>/dev/null \
    || { _ids_warn "the identifier list was not compared with base $_ic_s: the base rev is unreadable."; return 0; }
  _ic_save=$PUBLISH_ID_FILE; PUBLISH_ID_FILE=$_ic_d/base.list
  _ic_rc=0; publish_ids > "$_ic_d/base.ids" 2>/dev/null || _ic_rc=$?
  PUBLISH_ID_FILE=$_ic_save
  [ "$_ic_rc" -eq 0 ] || { _ids_warn "the identifier list was not compared with base $_ic_s: the base list does not parse."; return 0; }
  publish_ids > "$_ic_d/head.ids" 2>/dev/null || return 0   # a malformed head list is the scan's own rc 2
  LC_ALL=C tr 'A-Z' 'a-z' < "$_ic_d/base.ids" | LC_ALL=C sort -u > "$_ic_d/base.fold"
  LC_ALL=C tr 'A-Z' 'a-z' < "$_ic_d/head.ids" | LC_ALL=C sort -u > "$_ic_d/head.fold"
  _ic_g=$(LC_ALL=C comm -23 "$_ic_d/base.fold" "$_ic_d/head.fold" | wc -l | tr -d ' ')
  [ "$_ic_g" -gt 0 ] || return 0
  _ic_b=$(wc -l < "$_ic_d/base.fold" | tr -d ' '); _ic_h=$(wc -l < "$_ic_d/head.fold" | tr -d ' ')
  _ic_bw=$(grep -c "^word$_ic_tab" "$_ic_d/base.fold" || true); _ic_hw=$(grep -c "^word$_ic_tab" "$_ic_d/head.fold" || true)
  _ids_warn "the identifier list is weaker than base $_ic_s: $_ic_g base entries missing or narrowed (base $_ic_b entries, $_ic_bw word:; this list $_ic_h entries, $_ic_hw word:). Counts only. Read the .publish-identifiers diff before the GO."
  return 0
}

# _id_grep <plain|word> <value> <grep-flag> [path…] — the ONLY place a list entry becomes a grep.
# plain: case-insensitive fixed substring, ambient locale. word: whole word, LC_ALL=C (measured identical
# on BSD, GNU and BusyBox grep). Content, names and redaction all call it, so "does it match" has one answer.
_id_grep() {
  _ig_form=$1; _ig_val=$2; _ig_flag=$3; shift 3
  if [ "$_ig_form" = word ]; then
    LC_ALL=C grep -iwF "$_ig_flag" -e "$_ig_val" "$@"
  else
    grep -iF "$_ig_flag" -e "$_ig_val" "$@"
  fi
}

# _name_listed <path-component> — rc 0 when any list entry (in $_idl) matches the component.
_name_listed() {
  _nl_tab=$(printf '\t')
  while IFS= read -r _nl_e; do
    if printf '%s\n' "$1" | _id_grep "${_nl_e%%"$_nl_tab"*}" "${_nl_e#*"$_nl_tab"}" -q; then return 0; fi
  done < "$_idl"
  return 1
}

# _redact_path <path> — sets _rp_out to the path with the first component that matches a list entry
# replaced by `<name withheld>` (the rest dropped), so a value never reaches stdout or a CI log; sets
# _rp_hit=1 when a component was withheld, else 0 (the path is kept bare). Sets variables, not stdout, so
# the flag survives (no command substitution); always rc 0 (it runs under set -e).
_redact_path() {
  _rp_rest=$1; _rp_pre=''; _rp_hit=0
  while [ -n "$_rp_rest" ]; do
    case $_rp_rest in
      */*) _rp_c=${_rp_rest%%/*}; _rp_rest=${_rp_rest#*/} ;;
      *)   _rp_c=$_rp_rest; _rp_rest='' ;;
    esac
    if _name_listed "$_rp_c"; then
      _rp_hit=1; _rp_out="${_rp_pre:+$_rp_pre/}<name withheld>"; return 0
    fi
    _rp_pre=${_rp_pre:+$_rp_pre/}$_rp_c
  done
  _rp_out=$_rp_pre
  return 0
}

# _err_text <file> — the first line of a tool's stderr, or a notice when that line names a listed value
# (an unreadable path named after an entry must not carry the value into a CI log). Always rc 0.
_err_text() {
  _et_l=$(head -1 "$1"); _et_tab=$(printf '\t')
  _et_ids=$(publish_ids 2>/dev/null) || { echo '<error text withheld: the identifier list is unreadable>'; return 0; }
  while IFS= read -r _et_e; do
    [ -n "$_et_e" ] || continue
    if printf '%s\n' "$_et_l" | _id_grep "${_et_e%%"$_et_tab"*}" "${_et_e#*"$_et_tab"}" -q; then
      echo '<error text withheld: it names a listed value>'; return 0
    fi
  done <<EOF
$_et_ids
EOF
  printf '%s\n' "$_et_l"
  return 0
}

# _redact_lines [tag] — stdin: repo-relative paths; stdout: each redacted, with ` [tag]` when given.
# A path matching an entry only as a whole (no single component does) prints `<path withheld>` instead.
_redact_lines() {
  while IFS= read -r _rl_p; do
    _redact_path "$_rl_p"
    # the whole path may match an entry (one spanning components) when no single component does: withhold it
    if [ "$_rp_hit" -eq 0 ] && _name_listed "$_rl_p"; then _rp_out='<path withheld>'; fi
    printf '%s%s\n' "$_rp_out" "${1:+ [$1]}"
  done
}

# _scan_tree — runs with the CWD at the tree root (see sensitive_hits); reads the parsed list at $_idl.
_scan_tree() {
  _scan_tab=$(printf '\t')
  # (1) withheld-document PATHS. find's stderr (unreadable dir, permission denied) is captured by the
  #     caller and turned into a scan failure — an unseeable subtree must not read as clean.
  find . \
    \( -iname 'BACKLOG.md' \
       -o -iname 'SPARKWRIGHT-CONSOLIDATED-BACKLOG.md' \
       -o -iname 'CHANGELOG.md' \
       -o -iname 'KIT-FEEDBACK.md' \
       -o -iname 'ROADMAP.md' \
       -o -iname 'ROADMAP-KIT.md' \
       -o -iname 'meta-control-log.md' \
       -o -iname '.meta-control-last' \
       -o -ipath './docs/architecture/*' \
       -o -ipath './postmortems/*' \
       -o \( -ipath './docs/*' \
             -a \( -iname '*harvest*' -o -iname '*field-report*' -o -iname '*postmortem*' \) \) \
    \) -print | sed 's|^\./||' | _redact_lines

  # (2) owner identifiers in CONTENT. -F fixed strings (no regex surprises); -a scans binaries too;
  #     -i case-INSENSITIVE — a cased variant of a denylisted token must not slip past (PUBLIC-DEIDENTIFICATION).
  while IFS= read -r _sc_e; do
    _id_grep "${_sc_e%%"$_scan_tab"*}" "${_sc_e#*"$_scan_tab"}" -rla . | sed 's|^\./||' | _redact_lines
  done < "$_idl"

  # (3) NAMES: every file and directory name, against the same entries.
  _scan_names=$(find . -print | sed -e 's|^\./||' -e '/^\.$/d')
  while IFS= read -r _sc_e; do
    printf '%s\n' "$_scan_names" | _id_grep "${_sc_e%%"$_scan_tab"*}" "${_sc_e#*"$_scan_tab"}" -h | _redact_lines name
  done < "$_idl"

  # (4) SYMLINKS are refused; the target is never read or printed.
  find . -type l -print | sed 's|^\./||' | _redact_lines symlink
  return 0
}

# --- gate — the Layer-2 scan, runnable on every PR (PUBLIC-DEIDENT-FIXTURE-LOGINS) ---------------
# `--gate`: export COMMITTED HEAD with the same generator a publish uses (scripts/adopter-export.sh),
# run sensitive_hits over that tree AND over every `public:` block of CHANGELOG.md (the release notes —
# CHANGELOG.md is export-ignored, so the tree scan cannot see them). Read-only: no tag check, no dirty
# check (it archives HEAD, so uncommitted edits are not scanned), no mirror, no network, no gitleaks
# (the CI job it runs in already runs gitleaks over full history).
# It also runs public_note_refs over every public block (SWAS-366: no PR number, tracker key, change-log pointer or
# export-ignored path in a note) and reads the marker grammar (a malformed block is a finding).
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
    # the same parser the scan uses (a malformed entry is rc 2 from publish_ids itself)
    publish_ids > "$_gw/ids" || exit 2
    if [ ! -f "$PUBLISH_ID_FILE" ] || [ ! -s "$_gw/ids" ]; then
      echo "publish-public: gate: --require-ids: the identifier list is absent or has no entries — the owner-identifier scan would be vacuous." >&2
      exit 2
    fi
  fi
  [ -f "$PUBLISH_ID_FILE" ] || say "gate: no identifier list at \$PUBLISH_ID_FILE — the owner-identifier dimension is N/A; the withheld-path scan still runs"
  if [ -n "$IDS_BASE" ]; then _ids_compare "$IDS_BASE" "$_gw"; fi
  if ! sh scripts/adopter-export.sh "$_gw/export" >/dev/null 2>"$_gw/export.err"; then
    echo "publish-public: gate: adopter-export failed — nothing could be scanned: $(_err_text "$_gw/export.err")" >&2
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
  _gi=0; _gexempt=0; : > "$_gw/findings"
  # This loop runs in a SUBSHELL (it is the right side of a pipe), so a variable set in it is lost: each
  # per-version finding is appended to $_gw/findings and read after the loop (SWAS-366, N6). A heading at or
  # below the floor VERSION is not graded for a malformed block, the same compare as public_note_refs (S1).
  printf '%s\n' "$_gvers" | while IFS= read -r _gv; do
    [ -n "$_gv" ] || continue
    _gexempt=0   # PNM5
    if _pnr_exempt "$_gv"; then _gexempt=1; fi
    _er=0
    extract_public_notes "$_gv" "$_gw/CHANGELOG.md" > "$_gw/note/v-$_gi.md" 2>/dev/null || _er=$?
    if [ "$_er" -ne 0 ]; then : > "$_gw/note/v-$_gi.md"; fi
    if [ "$_er" -eq 3 ] && [ "$_gexempt" -eq 0 ]; then printf '[malformed-block] [%s]\n' "$_gv" >> "$_gw/findings"; fi   # PNM3
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
  # SWAS-366: a public block must name nothing a public reader cannot open (references, change-log pointers,
  # export-ignored paths, malformed markers). rc 2 is a read that could not complete: fail closed, never clean.
  _gref=0; _gcure=0
  public_note_refs "$_gw/CHANGELOG.md" all > "$_gw/refs.out" 2> "$_gw/refs.err" || _gref=$?   # PNM1
  if [ "$_gref" -eq 2 ]; then
    echo "publish-public: gate: the release-note reference check could not complete: $(_err_text "$_gw/refs.err")" >&2
    exit 2
  fi
  if [ -s "$_gw/refs.err" ]; then sed 's/^/publish-public: gate: /' "$_gw/refs.err" >&2; fi
  if [ "$_gref" -eq 1 ] || [ -s "$_gw/findings" ]; then
    _gbad=1; _gcure=1
    echo "publish-public: gate: a CHANGELOG.md public block (release note) holds something a public reader cannot open or is malformed, at:" >&2
    cat "$_gw/refs.out" "$_gw/findings" 2>/dev/null | LC_ALL=C sort -u | sed 's/^/  /' >&2
  fi
  if [ "$_gcure" -ne 0 ]; then
    echo "publish-public: gate: cure for those lines — a public block may not contain a # followed by digits (also PR#, owner/repo# or &#35;), a GH- number, a forge /pull(s)/, /issues/ or /commit(s)/ URL, or a github/gitlab/bitbucket URL (with or without a scheme or www.) under pull(s), issues, commit(s), compare, tree or blob, this project's tracker key with a number (any case, a space, _ or - between), the word changelog, [Unreleased], a path the export drops, or, in the block that ships, a marker that shares its line or opens twice. Reword it to name nothing a public reader cannot open (the public repo is a mirror with no PR history); see MAINTAINING.md section 3." >&2
  fi
  if [ "$_gbad" -ne 0 ]; then
    echo "publish-public: gate: cure — replace the owner identifier with a neutral placeholder (reviewer-login / author-login); the identifier list is .publish-identifiers (export-ignored); a withheld-document path is cured by export-ignoring it in .gitattributes; a [name] hit is cured by renaming (the withheld component sits under the printed prefix: git ls-files '<prefix>/'); a [symlink] hit is cured by replacing the link with the file." >&2
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
  # FAIL CLOSED (SWAS-366, following SWAS-363's sentinel exit trap): an abort anywhere in this function (a set -u
  # unbound variable, say) must never end the run green. bash 3.2 / sh take the EXIT trap's LAST status as the exit
  # status, and the old cleanup trap ended in `rm -f`, so an abort exited 0. `_st_end` exits 0 only after the
  # sentinel `_st_done=1` set immediately before the final `exit 0`; any other end exits 1. The one EXIT trap.
  _st_done=0
  _st_clean() { rm -rf "${_t:-}" "${_t_main:-}" "${_h:-}" "${_gb:-}"; rm -f "${_ids_main:-}" "${_hids:-}" "${_sef:-}" "${_st_ids0:-}"; }
  _st_end() {
    _st_code=0
    [ "${_st_done:-0}" = 1 ] || _st_code=1   # PNM6
    exit "$_st_code"
  }
  _t='' _t_main='' _h='' _gb='' _ids_main='' _hids='' _sef='' _st_ids0=''   # an inherited value must never reach the cleanup's rm
  trap '_st_clean; _st_end' EXIT
  _pnst_v=ok   # PNST-DIE
  : "$_pnst_v"
  _t=$(mktemp -d "${TMPDIR:-/tmp}/sw-pub-st.XXXXXX") || die "mktemp failed"
  _fail=0
  # isolate the identifier config: a controlled token no source file contains, so the scan is exercised
  # without depending on (or embedding) the real owner identifiers.
  PUBLISH_ID_FILE=$(mktemp "${TMPDIR:-/tmp}/sw-pub-ids.XXXXXX") || die "mktemp failed"
  _st_ids0=$PUBLISH_ID_FILE
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
  # a capitalised name past its lowercase entry) — the config carries 'ownerlogin' lowercase,
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

  # --- PUBLISH-GATE-HARDENING: two entry forms, names, symlinks, a tree-relative scan --------------
  # Each control has ONE load-bearing negative. Every list below is a TEST list (never the real one);
  # every identifier is invented. Plants live in their own tree so no other fixture can satisfy a leg.
  echo "publish-public --selftest: identifier forms, names, symlinks, relative scan"
  _t_main=$_t; _ids_main=$PUBLISH_ID_FILE
  _h=$(mktemp -d "${TMPDIR:-/tmp}/sw-pub-st-h.XXXXXX") || die "mktemp failed"
  _hids=$(mktemp "${TMPDIR:-/tmp}/sw-pub-ids-h.XXXXXX") || die "mktemp failed"
  _sef=$(mktemp "${TMPDIR:-/tmp}/sw-pub-err-h.XXXXXX") || die "mktemp failed"
  _t=$_h; PUBLISH_ID_FILE=$_hids
  # trap-clean: every temp path above is reaped on ANY exit (a die or a signal included).
  trap 'exit 2' HUP INT TERM
  _fresh() { rm -rf "$_h"; mkdir -p "$_h/docs"; }
  _src()   { _srcr=0; _so=$(sensitive_hits "$_t" 2>"$_sef") || _srcr=$?; }
  _rc_zero() {  # <label> — the last _src completed its scan (rc 0); hits are stdout, never the rc
    if [ "$_srcr" -eq 0 ]; then echo "  ok   RC    $1 -> rc 0"
    else echo "  FAIL RC    $1: want rc 0, got rc $_srcr"; _fail=$((_fail+1)); fi
  }
  _vfree() {  # <label> <value> — neither stdout nor stderr of the last _src carries the value
    if printf '%s\n' "$_so" | grep -qiF -e "$2" || grep -qiF -e "$2" "$_sef"; then
      echo "  FAIL VALUE $1: output echoed the listed value"; _fail=$((_fail+1))
    else echo "  ok   VALUE $1: the listed value is never echoed"; fi
  }

  # (a) a `word:` entry reds a whole-word hit, not its superstring (the load-bearing negative).
  _fresh
  printf 'word:acmely\nword:zorbix labs\n' > "$_hids"
  printf 'shipped by Acmely.\n'      > "$_h/docs/w-hit.md"
  printf 'ACMELY-corp notes\n'       > "$_h/docs/w-case.md"
  printf 'by Zorbix Labs today\n'    > "$_h/docs/w-multi.md"
  printf 'tacmely and acmelyish\n'   > "$_h/docs/w-super.md"
  printf 'acmely_token and acmely2\n' > "$_h/docs/w-joined.md"
  printf 'tacmely then Acmely.\n'  > "$_h/docs/w-second.md"
  _hit  docs/w-second.md "word: entry: a superstring first, then the real word on the same line, still reds"
  _hit  docs/w-hit.md    "word: entry reds a whole-word hit"
  _hit  docs/w-case.md   "word: entry is case-insensitive (ACMELY-corp)"
  _hit  docs/w-multi.md  "word: entry holds a multi-word value"
  _pass docs/w-super.md  "word: entry does NOT red a superstring (tacmely, acmelyish)"
  _pass docs/w-joined.md "word: entry does NOT red a word-joined form (acmely_token, acmely2)"
  # (b) a plain entry is still a substring (the default form is unchanged).
  printf 'zorb\n' > "$_hids"; printf 'a zorbix here\n' > "$_h/docs/p-sub.md"
  _hit  docs/p-sub.md    "plain entry keeps substring recall"

  # (c) malformed word: entries fail CLOSED (rc 2, line number only, never the value).
  _fresh; printf '# header\nword:\n' > "$_hids"
  _src
  if [ "$_srcr" -eq 2 ] && grep -qF 'line 2' "$_sef"; then echo "  ok   RC    empty word: value -> rc 2 naming the line"
  else echo "  FAIL RC    empty word: value: want rc 2 naming line 2, got rc $_srcr"; _fail=$((_fail+1)); fi
  printf 'word:caf\303\251\n' > "$_hids"
  _src
  if [ "$_srcr" -eq 2 ] && grep -qF 'line 1' "$_sef"; then echo "  ok   RC    non-ASCII word: value -> rc 2 naming the line"
  else echo "  FAIL RC    non-ASCII word: value: want rc 2 naming line 1, got rc $_srcr"; _fail=$((_fail+1)); fi
  _vfree "malformed word: entry" "caf"

  # (c2) typos fail CLOSED (rc 2, line number only), never silently match nothing.
  _closed() {  # <label> <printf-format> <value that must not be echoed>
    _fresh; printf "$2" > "$_hids"; _src
    if [ "$_srcr" -eq 2 ] && grep -qF 'line 1' "$_sef"; then echo "  ok   RC    $1 -> rc 2 naming the line"
    else echo "  FAIL RC    $1: want rc 2 naming line 1, got rc $_srcr"; _fail=$((_fail+1)); fi
    _vfree "$1" "$3"
  }
  _closed "word: with a space before the value"   'word: acmely\n'           acmely
  _closed "a plain entry with trailing whitespace" 'ACME-OWNER-TOKEN-42 \n'  ACME-OWNER-TOKEN-42
  _closed "an indented word: entry"               '  word:acmely\n'          acmely
  _closed "Word: in another case"                 'Word:acmely\n'            acmely
  _closed "WORD: in another case"                 'WORD:acmely\n'            acmely
  _closed "word : with a space before the colon"  'word :acmely\n'           acmely
  _closed "a CR-only (classic Mac) list"          'ACME-OWNER-TOKEN-42\rword:acmely\r'  ACME-OWNER-TOKEN-42
  # the load-bearing negative: a clean list with comments (indented, trailing space) is NOT refused.
  _fresh; printf '# c\n  # indented comment \n\nword:acmely\nzorb ix\n' > "$_hids"; _src
  if [ "$_srcr" -eq 0 ]; then echo "  ok   RC    a well-formed list (comments, blanks, both forms) -> rc 0"
  else echo "  FAIL RC    well-formed list refused: rc $_srcr"; _fail=$((_fail+1)); fi

  # (c3) a tool's stderr naming a listed value is withheld, not echoed (rc stays 2). Root ignores mode 000.
  if [ "$(id -u)" -eq 0 ]; then echo "  SKIP ERR   running as root: mode 000 is not enforced, the unreadable-directory leg cannot run"
  else
    _fresh; printf 'ACME-OWNER-TOKEN-42\n' > "$_hids"
    mkdir -p "$_h/docs/ACME-OWNER-TOKEN-42"; chmod 000 "$_h/docs/ACME-OWNER-TOKEN-42"
    _src; chmod 755 "$_h/docs/ACME-OWNER-TOKEN-42"
    if [ "$_srcr" -eq 2 ]; then echo "  ok   RC    an unreadable directory -> rc 2 (fail-closed)"
    else echo "  FAIL RC    unreadable directory: want rc 2, got rc $_srcr"; _fail=$((_fail+1)); fi
    _vfree "scan error naming a listed directory" "ACME-OWNER-TOKEN-42"
  fi

  # (d) a CRLF list still matches (the strip; without it a CR-ended entry misses every LF file).
  _fresh; printf 'ACME-OWNER-TOKEN-42\r\nword:acmely\r\n' > "$_hids"
  printf 'seat ACME-OWNER-TOKEN-42 here\n' > "$_h/docs/crlf-plain.md"
  printf 'shipped by Acmely.\n'            > "$_h/docs/crlf-word.md"
  _hit  docs/crlf-plain.md "CRLF list: a plain entry still matches LF content"
  _hit  docs/crlf-word.md  "CRLF list: a word: entry still matches LF content"

  # (e) one parser: an indented comment is a comment, not an identifier.
  _fresh; printf '  # commented-token-7\nword:acmely\n' > "$_hids"
  printf '  # commented-token-7\n' > "$_h/docs/indented.md"
  _pass docs/indented.md   "an indented # line in the list is a comment, not scanned as an identifier"

  # (f) a listed name in a file or directory NAME reds, redacted; the value is never echoed.
  _fresh; printf 'ACME-OWNER-TOKEN-42\nword:acmely\n' > "$_hids"
  mkdir -p "$_h/docs/ACME-OWNER-TOKEN-42"; : > "$_h/docs/ACME-OWNER-TOKEN-42/x.md"
  : > "$_h/docs/acmely-notes.md"; : > "$_h/docs/tacmely-notes.md"
  _hit  "docs/<name withheld> [name]" "a listed name in a directory or file name reds, redacted"
  _src
  _vfree "name hit" "ACME-OWNER-TOKEN-42"
  _vfree "name hit (word:)" "acmely"
  if printf '%s\n' "$_so" | grep -qF 'tacmely'; then echo "  FAIL NAME  superstring name reported"; _fail=$((_fail+1))
  else echo "  ok   NAME  a superstring in a name is not a word: hit"; fi

  # (g) a tracked symlink is refused, target never read; a regular file beside it stays clean.
  _fresh; printf 'ACME-OWNER-TOKEN-42\n' > "$_hids"
  : > "$_h/docs/real.md"; ln -s ../SECURITY.md "$_h/docs/link.md"
  ln -s ../SECURITY.md "$_h/docs/ACME-OWNER-TOKEN-42-link.md"
  _hit  "docs/link.md [symlink]"            "a symlink is refused"
  _hit  "docs/<name withheld> [symlink]"    "a symlink with a listed name is refused, redacted"
  _pass docs/real.md                        "a regular file beside the symlink is not reported"
  _src
  _rc_zero "a tree with symlink hits (hits are stdout; the scan itself completed)"
  _vfree "symlink hit" "ACME-OWNER-TOKEN-42"

  # (h) no value is echoed across EVERY hit class (content hit on a path that is itself named).
  _fresh; printf 'ACME-OWNER-TOKEN-42\n' > "$_hids"
  printf 'seat ACME-OWNER-TOKEN-42\n' > "$_h/docs/ACME-OWNER-TOKEN-42.md"
  : > "$_h/BACKLOG.md"
  ln -s x "$_h/docs/ACME-OWNER-TOKEN-42.lnk"
  _src
  _rc_zero "a tree with content, name, symlink and withheld-path hits"
  if [ -n "$_so" ]; then echo "  ok   VALUE every hit class produced output to check"
  else echo "  FAIL VALUE no hit output to check"; _fail=$((_fail+1)); fi
  _vfree "content + name + symlink + withheld-path hits" "ACME-OWNER-TOKEN-42"

  # (h2) a path-shaped entry that matches the WHOLE path but no single component is withheld too,
  #      for every tag (here a content hit and a name hit).
  _fresh; printf 'zq/split\n' > "$_hids"
  mkdir -p "$_h/zq"; printf 'see zq/split here\n' > "$_h/zq/split"
  _src
  if [ -n "$_so" ]; then echo "  ok   VALUE a path-spanning entry produced hits to check"
  else echo "  FAIL VALUE path-spanning entry produced no hit"; _fail=$((_fail+1)); fi
  _vfree "path-spanning entry (content + name hits)" "zq/split"

  # (i) the scan is relative to the tree: glob and regex metacharacters in the tree path do not fail open.
  _gb=$(mktemp -d "${TMPDIR:-/tmp}/sw-pub-st-g.XXXXXX") || die "mktemp failed"
  printf 'ACME-OWNER-TOKEN-42\n' > "$_hids"
  for _gd in 'glob[x]' 'g*b?' 'a.b'; do
    _t="$_gb/$_gd"; mkdir -p "$_t/docs/architecture" "$_t/docs"
    : > "$_t/docs/architecture/a.md"; printf 'ACME-OWNER-TOKEN-42\n' > "$_t/docs/leak.md"
    _hit  docs/architecture/a.md "tree path '$_gd': a withheld path is still found"
    _hit  docs/leak.md           "tree path '$_gd': an identifier in content is still found"
  done
  _t=$_h; rm -rf "$_gb"

  # (the end-to-end --gate legs of this control are at "S-5" below, once the gate helpers exist)
  _t=$_t_main; PUBLISH_ID_FILE=$_ids_main

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
    printf '# Changelog\n\n## [9.0.0]\n<!-- public:start -->\n%s\n<!-- public:end -->\n- internal bullet\n' "$3" > "$1/CHANGELOG.md"
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

  # S-1: the gate must scan AT LEAST what the publish ships, and the gate and the publish share ONE marker
  # grammar. A line naming BOTH markers inside a `## [v]` section used to open a block for extract_public_notes;
  # since SWAS-366 it is a MALFORMED block (rc 3), nothing is shipped from it, and the gate reds it as a
  # `[malformed-block]` finding. (This cell's old needle, "CHANGELOG.md (between", needed the old opening
  # behaviour; the design, section 3.1 step 2, replaces it. PN7 and PN13 hold the new contract.)
  _gate_repo "$_t/gate-both" "a clean fixture" "A clean user-facing summary."
  printf '## [9.1.0]\n> prose <!-- public:start -->x<!-- public:end --> inline\nthanks to ownerlogin\n<!-- public:end -->\n' >> "$_t/gate-both/CHANGELOG.md"
  _gate_commit "$_t/gate-both"
  _gate_run "$_t/gate-both"
  if [ "$_grc" -eq 1 ] && printf '%s\n' "$_gout" | grep -qF "[malformed-block] [9.1.0]"; then
    echo "  ok   GATE  both-markers line inside a version section: a malformed block, refused by the one grammar -> rc 1"
  else echo "  FAIL GATE  both-markers line: want rc 1 naming [malformed-block] [9.1.0], got rc $_grc"; _fail=$((_fail+1)); fi
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

  # S-5 (PUBLISH-GATE-HARDENING): end to end through --gate, the CI path. A word: plant reds and names its
  # file, its superstring stays green, and a malformed or comments-only list is rc 2 under --require-ids.
  printf 'word:acmely\n' > "$_hids"
  _gate_repo "$_h/gate-w" "shipped by Acmely." "A clean user-facing summary."
  _gate_run "$_h/gate-w" "" "$_hids"
  if [ "$_grc" -eq 1 ] && printf '%s\n' "$_gout" | grep -qxF "  docs/fixture.md"; then
    echo "  ok   GATE  word: plant in a shipped file -> rc 1, file named"
  else echo "  FAIL GATE  word: plant: want rc 1 naming docs/fixture.md, got rc $_grc"; _fail=$((_fail+1)); fi
  _gate_repo "$_h/gate-s" "tacmely is not it" "A clean user-facing summary."
  _gate_run "$_h/gate-s" "" "$_hids"
  _want_rc 0 "GATE  a superstring of a word: entry stays clean -> rc 0" "GATE  word: superstring"
  printf '  # only an indented comment\n' > "$_hids"
  _gate_run "$_h/gate-s" --require-ids "$_hids"
  _want_rc 2 "GATE  --require-ids with only an indented comment -> rc 2 (one parser)" "GATE  require-ids indented comment"
  printf 'word:\n' > "$_hids"
  _gate_run "$_h/gate-s" --require-ids "$_hids"
  _want_rc 2 "GATE  --require-ids with a malformed word: entry -> rc 2" "GATE  require-ids malformed"
  # an exporter whose stderr names a listed value: rc 2, and the value is withheld from the message
  _gate_repo "$_h/gate-errv" "a clean fixture" "A clean user-facing summary."
  printf 'echo "cannot read ACME-OWNER-TOKEN-42/file" >&2; exit 1\n' > "$_h/gate-errv/scripts/adopter-export.sh"
  _gate_commit "$_h/gate-errv"
  _gate_run "$_h/gate-errv"
  _want_rc 2 "GATE  an exporter error naming a listed value -> rc 2" "GATE  exporter error with a value"
  _no_value "exporter error text" "ACME-OWNER-TOKEN-42"

  # S-6 (PUBLISH-IDENTIFIERS-CONTROL-PLANE): --ids-base warns, in counts only, when a base entry is missing or narrowed.
  _gate_repo "$_h/gate-b" "a clean fixture" "A clean user-facing summary."
  printf '.publish-identifiers export-ignore\n' >> "$_h/gate-b/.gitattributes"
  printf 'Acmely\nZorbix\nword:Quillon\n' > "$_h/gate-b/.publish-identifiers"
  _gate_commit "$_h/gate-b"
  printf 'Acmely\nword:Quillon\n' > "$_h/gate-b/.publish-identifiers"
  _gate_commit "$_h/gate-b"
  _gate_run "$_h/gate-b" "--ids-base HEAD~1" "$_h/gate-b/.publish-identifiers"
  _want_rc 0 "GATE  --ids-base with a dropped entry -> rc 0 (warns, never fails)" "GATE  ids-base dropped rc"
  if printf '%s\n' "$_gout" | grep -qF "1 base entries missing or narrowed" \
     && printf '%s\n' "$_gout" | grep -qF "base 3 entries, 1 word:; this list 2 entries, 1 word:"; then
    echo "  ok   GATE  a dropped base entry prints the counts line"
  else echo "  FAIL GATE  dropped entry: the counts line is missing"; _fail=$((_fail+1)); fi
  _no_value "dropped entry (Zorbix)" "Zorbix"; _no_value "dropped entry (Acmely)" "Acmely"
  printf 'Acmely\nword:Quillon\n# same entries, one comment\n' > "$_h/gate-b/.publish-identifiers"
  _gate_commit "$_h/gate-b"
  if [ -n "$(cd "$_h/gate-b" && git show HEAD~1:.publish-identifiers 2>/dev/null)" ]; then
    _gate_run "$_h/gate-b" "--ids-base HEAD~1" "$_h/gate-b/.publish-identifiers"
    if printf '%s\n' "$_gout" | grep -qF "weaker than base"; then echo "  FAIL GATE  an unchanged list printed the weaker-than-base line"; _fail=$((_fail+1))
    else echo "  ok   GATE  an unchanged list prints no weaker-than-base line (the line above is load-bearing)"; fi
  else echo "  FAIL GATE  setup: the base commit carries no list"; _fail=$((_fail+1)); fi

  # --- SWAS-366: a public block may not point at anything a public reader cannot open --------------------
  # public_note_refs and the one marker grammar, end to end through `--gate` on throwaway repos that carry COPIES
  # of the real scripts. In a fixture the heading is line 3, the start marker line 4, so body line k is
  # CHANGELOG.md line k+4. Mutants are scratch copies of the real script with the lines ending `# <token>`
  # deleted (a `cmp -s` guard proves each differs); the cell then shows the check was load-bearing.
  echo "publish-public --selftest: release-note references and the marker grammar (SWAS-366)"
  _pn_mk() {  # <dir> <heading> <body> [tracker-conf-text] [attributes-line] [claude-md-text]
    [ "$#" -ge 3 ] || { echo "  FAIL _pn_mk: arity (want at least 3 arguments, got $#)"; _fail=$((_fail+1)); return 0; }
    _gate_repo "$1" "a clean fixture" "x"
    printf '# Changelog\n\n## [%s]\n<!-- public:start -->\n%s\n<!-- public:end -->\n- internal bullet\n' "$2" "$3" > "$1/CHANGELOG.md"
    if [ -n "${4:-}" ]; then mkdir -p "$1/.kit"; printf '%s\n' "$4" > "$1/.kit/tracker.conf"; fi
    if [ -n "${5:-}" ]; then printf '%s\n' "$5" >> "$1/.gitattributes"; fi
    if [ -n "${6:-}" ]; then printf '%s\n' "$6" > "$1/CLAUDE.md"; fi
    _gate_commit "$1"
  }
  _pn_raw() {  # <dir> <changelog-file> — a gate fixture whose CHANGELOG.md is exactly <changelog-file>
    [ "$#" -ge 2 ] || { echo "  FAIL _pn_raw: arity (want 2 arguments, got $#)"; _fail=$((_fail+1)); return 0; }
    _gate_repo "$1" "a clean fixture" "x"
    cp "$2" "$1/CHANGELOG.md"
    _gate_commit "$1"
  }
  _pn_has() {  # <label> <needle> — the last gate output holds the needle
    if printf '%s\n' "$_gout" | grep -qF -e "$2"; then echo "  ok   PN    $1"
    else echo "  FAIL PN    $1: the gate output lacks '$2'"; _fail=$((_fail+1)); fi
  }
  _pn_not() {  # <label> <needle> — the last gate output does not hold the needle
    if printf '%s\n' "$_gout" | grep -qF -e "$2"; then echo "  FAIL PN    $1: the gate output holds '$2'"; _fail=$((_fail+1))
    else echo "  ok   PN    $1"; fi
  }
  _pn_miss() {  # <label> <needle> — a mutant run: the gate still ran and reds (rc 1), and the needle is gone
    case "$_grc:$_gout" in
      1:*"$2"*) echo "  FAIL PN    $1: the mutant still reports '$2'"; _fail=$((_fail+1)) ;;
      1:*) echo "  ok   PN    $1" ;;
      *) echo "  FAIL PN    $1: the mutant run did not red cleanly (rc $_grc), so a missing needle proves nothing"; _fail=$((_fail+1)) ;;
    esac
  }
  _pn_ex() {  # <label> <want-rc> <version> <file> — extract_public_notes' rc and output (sets _pn_out)
    _pn_rc=0; _pn_out=$(extract_public_notes "$3" "$4") || _pn_rc=$?
    if [ "$_pn_rc" -eq "$2" ]; then echo "  ok   PN    $1 -> rc $_pn_rc"
    else echo "  FAIL PN    $1: want rc $2, got rc $_pn_rc"; _fail=$((_fail+1)); fi
  }
  _pn_mutant() {  # <dir> <token> <label> — a copy of the red fixture whose script lacks the lines ending "# <token>"
    rm -rf "$1"; cp -R "$_t/pn-red" "$1"
    grep -v "# $2\$" "$ROOT/scripts/publish-public.sh" > "$1/scripts/publish-public.sh"
    if cmp -s "$ROOT/scripts/publish-public.sh" "$1/scripts/publish-public.sh"; then
      echo "  FAIL PNM   $3: the mutant is identical to the original, so it proves nothing"; _fail=$((_fail+1))
    fi
    _gate_run "$1"
  }

  # (a) every refused shape, one per line, in one block of a fixture that declares the key SWAS and an export-ignored path.
  _pn_body=$(printf '%s\n' 'fixed in #880' 'see owner/repo#12' 'see gh-12' 'see PR#880' 'see &#35;880' 'see &#x23;880' \
    'see https://github.com/o/r/pull/12' 'see https://github.com/o/r/commit/abc123' 'see SWAS-363' 'see &NUM;880' 'see &#X23;880' \
    'the [Unreleased] line' 'read the Changelog' 'see docs/private.md' 'see ./docs/private.md' 'see /docs/private.md')
  _pn_mk "$_t/pn-red" Unreleased "$_pn_body" 'project=SWAS' 'docs/private.md export-ignore'
  _gate_run "$_t/pn-red"
  _want_rc 1 "PN    a block holding every refused shape -> rc 1" "PN  refused shapes"
  _pn_has "PN1   #880 -> [pr-ref] with line and version"        "[pr-ref] CHANGELOG.md:5 [Unreleased]"
  _pn_has "PN2   owner/repo#12"                                   "[pr-ref] CHANGELOG.md:6 [Unreleased]"
  _pn_has "PN3   gh-12 (lower case)"                              "[pr-ref] CHANGELOG.md:7 [Unreleased]"
  _pn_has "PN3b  PR#880"                                          "[pr-ref] CHANGELOG.md:8 [Unreleased]"
  _pn_has "PN3c  &#35;880"                                        "[pr-ref] CHANGELOG.md:9 [Unreleased]"
  _pn_has "PN3c  &#x23;880"                                       "[pr-ref] CHANGELOG.md:10 [Unreleased]"
  _pn_has "PN3d  a forge /pull/ URL"                              "[pr-ref] CHANGELOG.md:11 [Unreleased]"
  _pn_has "PN3d  a forge /commit/ URL"                            "[pr-ref] CHANGELOG.md:12 [Unreleased]"
  _pn_has "PN3e  the fixture conf's key with a number"            "[tracker-key] CHANGELOG.md:13 [Unreleased]"
  _pn_has "PN3f  &NUM;880 (any case)"                             "[pr-ref] CHANGELOG.md:14 [Unreleased]"
  _pn_has "PN3f  &#X23;880 (any case)"                            "[pr-ref] CHANGELOG.md:15 [Unreleased]"
  _pn_has "PN4   the [Unreleased] pointer"                        "[internal-pointer] CHANGELOG.md:16 [Unreleased]"
  _pn_has "PN4   the word changelog, any case"                    "[internal-pointer] CHANGELOG.md:17 [Unreleased]"
  _pn_has "PN5   an export-ignored path"                          "[export-ignored] CHANGELOG.md:18 [Unreleased]"
  _pn_has "PN5s  ./docs/private.md (leading ./ stripped)"         "[export-ignored] CHANGELOG.md:19 [Unreleased]"
  _pn_has "PN5s  /docs/private.md (leading / stripped)"           "[export-ignored] CHANGELOG.md:20 [Unreleased]"
  _no_value "finding lines" "docs/private.md"

  # (b) the negatives: none of these is a finding, and none of them errors (the same fixture's key and attributes).
  _pn_neg=$(printf '%s\n' 'see MAINTAINING.md#3-releasing' 'shipped as v3.241.0 after issue five' \
    'CVE-2024-1, SHA-256 and UTF-8 are not keys' 'see ../x.md, https://e.org/a.md, /etc/x.md and docs/*.md' 'see docs/public.md')
  _pn_mk "$_t/pn-neg" 9.0.0 "$_pn_neg" 'project=SWAS' 'docs/private.md export-ignore'
  _gate_run "$_t/pn-neg"
  _want_rc 0 "PN6   anchors, versions, CVE/SHA/UTF ids, odd and exported paths are clean -> rc 0" "PN6  negatives"

  # (c) the tracker key comes ONLY from the conf: no conf is N/A, a bad key is rc 2, and in a Jira-declared tree a missing conf is rc 2.
  _pn_mk "$_t/pn-nokey" 9.0.0 'see SWAS-363'
  _gate_run "$_t/pn-nokey"
  _want_rc 0 "PN3z  no conf and no Jira declaration: the key kind is N/A -> rc 0" "PN3z  no conf"
  _pn_mk "$_t/pn-badkey" 9.0.0 'a clean line' 'project=sw.s'
  _gate_run "$_t/pn-badkey"
  _want_rc 2 "PN3k  a project key that is not ^[A-Z][A-Z0-9]+\$ -> rc 2 (fail closed)" "PN3k  bad key"
  _pn_mk "$_t/pn-kitnoconf" 9.0.0 'a clean line' '' '' '- **Backlog backend**: Jira (project X)'
  _gate_run "$_t/pn-kitnoconf"
  _want_rc 2 "PN3k  a Jira-declared tree with no conf -> rc 2 (fail closed, not N/A)" "PN3k  kit tree without conf"

  # (d) one marker grammar: extract_public_notes' rc 3 for a malformed block, the gate's [malformed-block] finding.
  printf '# Changelog\n\n## [9.9.9]\n<!-- public:start -->one line<!-- public:end -->\n- INTERNAL-ONE\n<!-- public:start -->\nreal block\n<!-- public:end -->\n' > "$_t/pn7.md"
  _pn_ex "PN7   a one-line block in an entry: malformed" 3 9.9.9 "$_t/pn7.md"
  if [ -z "$_pn_out" ]; then echo "  ok   PN    PN7b  nothing is emitted from a malformed block"
  else echo "  FAIL PN    PN7b: a malformed block emitted text"; _fail=$((_fail+1)); fi
  _pn_ex "PN7c  no block in the entry: rc 1, not 3" 1 9.9.7 "$_t/pn7.md"
  printf '# Changelog\n\n## [9.9.9]\n<!-- public:start -->\na\n<!-- public:start -->\nb\n<!-- public:end -->\n' > "$_t/pn8.md"
  _pn_ex "PN8   a second start before the end: malformed" 3 9.9.9 "$_t/pn8.md"
  _pn_raw "$_t/pn-g7" "$_t/pn7.md"
  _gate_run "$_t/pn-g7"
  _want_rc 1 "PN7   the gate reds a one-line block in an entry -> rc 1" "PN7  gate"
  _pn_has "PN7   the finding names the version" "[malformed-block] [9.9.9]"
  printf '# Changelog\n\n## [9.1.0]\n<!-- public:start -->\nfine\n<!-- public:end -->\n\n## [9.0.0]\n<!-- public:start -->x<!-- public:end -->\n- i\n' > "$_t/pn13.md"
  _pn_raw "$_t/pn-g13" "$_t/pn13.md"
  _gate_run "$_t/pn-g13"
  _want_rc 1 "PN13  a malformed block in the SECOND heading still reds the gate (the loop is a subshell)" "PN13  second heading"
  _pn_has "PN13  the finding names the second heading" "[malformed-block] [9.0.0]"
  _pn_not "PN13  and not the clean first heading"      "[malformed-block] [9.1.0]"
  printf '# Changelog\n\n> each entry carries a <!-- public:start -->...<!-- public:end --> block\n\n## [9.0.0]\n<!-- public:start -->\nclean\n<!-- public:end -->\n' > "$_t/pn9.md"
  _pn_raw "$_t/pn-g9" "$_t/pn9.md"
  _gate_run "$_t/pn-g9"
  _want_rc 0 "PN9   the header prose naming both markers on a line is not an entry -> rc 0" "PN9  preamble"

  # (e) the floor: the heading PUBNOTE_REF_FLOOR names and every older one are not graded; newer ones are.
  printf '# Changelog\n\n## [3.241.0]\n<!-- public:start -->\nclean\n<!-- public:end -->\n\n## [3.240.0]\n<!-- public:start -->\nfixed in #880\n<!-- public:end -->\n\n## [3.239.0]\n<!-- public:start -->\nPR #12\n<!-- public:end -->\n\n## [3.238.0]\n<!-- public:start -->PR #12<!-- public:end -->\n' > "$_t/pn11a.md"
  _pn_raw "$_t/pn-g11a" "$_t/pn11a.md"
  _gate_run "$_t/pn-g11a"
  _want_rc 0 "PN11  a reference at the floor and strictly older, and a malformed block older still, are not graded -> rc 0" "PN11  below the floor"
  _pn_not "PN11  the heading strictly older than the floor is not flagged" "[3.239.0]"
  _pn_not "PN11  nor the older malformed block"                           "[3.238.0]"
  printf '# Changelog\n\n## [3.241.0]\n<!-- public:start -->\nfixed in #880\n<!-- public:end -->\n\n## [3.240.0]\n<!-- public:start -->\nfixed in #881\n<!-- public:end -->\n' > "$_t/pn11b.md"
  _pn_raw "$_t/pn-g11b" "$_t/pn11b.md"
  _gate_run "$_t/pn-g11b"
  _want_rc 1 "PN11  the same reference above the floor reds -> rc 1" "PN11  above the floor"
  _pn_has "PN11  the finding names the graded version" "[pr-ref] CHANGELOG.md:5 [3.241.0]"
  _pn_not "PN11  and not the exempt one"               "[3.240.0]"

  # (e2) the floor is a VERSION compare, not a position (security S1): a stray floor heading above a newer
  # section (a fenced example, a misordered merge) must not exempt the newer block; `Unreleased` is never exempt.
  printf '# Changelog\n\n## [3.240.0]\nstray example heading\n\n## [3.242.0]\n<!-- public:start -->\nfixed in #880\n<!-- public:end -->\n' > "$_t/pn14.md"
  _pn_raw "$_t/pn-g14" "$_t/pn14.md"
  _gate_run "$_t/pn-g14"
  _want_rc 1 "PN14  a stray floor heading above a newer section does not exempt it -> rc 1" "PN14  stray floor heading"
  _pn_has "PN14  the finding names the newer version" "[pr-ref] CHANGELOG.md:8 [3.242.0]"
  printf '# Changelog\n\n## [3.240.0]\nstray example heading\n\n## [Unreleased]\n<!-- public:start -->\nfixed in #880\n<!-- public:end -->\n' > "$_t/pn14b.md"
  _pn_raw "$_t/pn-g14b" "$_t/pn14b.md"
  _gate_run "$_t/pn-g14b"
  _want_rc 1 "PN14b [Unreleased] below a stray floor heading is still graded -> rc 1" "PN14b  Unreleased"
  _pn_has "PN14b the finding names [Unreleased]" "[pr-ref] CHANGELOG.md:8 [Unreleased]"

  # (e3) forge URLs without a scheme and other forge paths (S3); the tracker key in any case, with a space or _ (S4).
  _pn_mk "$_t/pn-g3s" 9.0.0 "$(printf '%s\n' 'see github.com/o/r/pull/12' 'see github.com/o/r/commit/abc' 'see (github.com/o/r/blob/main/x)' 'see https://gitlab.com/o/r/tree/main' 'see www.github.com/o/r/pull/12')" 'project=SWAS'
  _gate_run "$_t/pn-g3s"
  _pn_has "PN3s  a scheme-less /pull/ URL"        "[pr-ref] CHANGELOG.md:5 [9.0.0]"
  _pn_has "PN3s  a scheme-less /commit/ URL"      "[pr-ref] CHANGELOG.md:6 [9.0.0]"
  _pn_has "PN3s  a wrapped scheme-less /blob/ URL" "[pr-ref] CHANGELOG.md:7 [9.0.0]"
  _pn_has "PN3s  a /tree/ URL on another forge"   "[pr-ref] CHANGELOG.md:8 [9.0.0]"
  _pn_has "PN3s  a www.-prefixed scheme-less URL"  "[pr-ref] CHANGELOG.md:9 [9.0.0]"
  _pn_mk "$_t/pn-g3u" 9.0.0 "$(printf '%s\n' 'see swas-363' 'and SWAS 363' 'and Swas_363')" 'project=SWAS'
  _gate_run "$_t/pn-g3u"
  _pn_has "PN3u  the key in lower case"      "[tracker-key] CHANGELOG.md:5 [9.0.0]"
  _pn_has "PN3u  the key with a space"       "[tracker-key] CHANGELOG.md:6 [9.0.0]"
  _pn_has "PN3u  the key in mixed case with _" "[tracker-key] CHANGELOG.md:7 [9.0.0]"

  # (f) one finding per line and kind, and the publish path runs the check before gitleaks.
  _pn_mk "$_t/pn-g12" 9.0.0 'fixed in #880 and again #880'
  _gate_run "$_t/pn-g12"
  _pn_n=$(printf '%s\n' "$_gout" | grep -cF '[pr-ref] CHANGELOG.md:5 [9.0.0]' || true)
  if [ "$_pn_n" -eq 1 ]; then echo "  ok   PN    PN12  the same reference twice on a line is one finding line"
  else echo "  FAIL PN    PN12: want 1 finding line, got $_pn_n"; _fail=$((_fail+1)); fi
  _pn_l1=$(grep -n '^NOTE_REFS=\$(public_note_refs ' "$ROOT/scripts/publish-public.sh" | head -1 | cut -d: -f1)
  _pn_l2=$(grep -n '^gitleaks detect --source "\$NOTE_DIR"' "$ROOT/scripts/publish-public.sh" | head -1 | cut -d: -f1)
  if [ -n "$_pn_l1" ] && [ -n "$_pn_l2" ] && [ "$_pn_l1" -lt "$_pn_l2" ]; then
    echo "  ok   PN    PN10  publish step 2b checks the note's references before gitleaks (lines $_pn_l1 < $_pn_l2)"
  else echo "  FAIL PN    PN10: step 2b does not call public_note_refs before gitleaks (lines '${_pn_l1}' / '${_pn_l2}')"; _fail=$((_fail+1)); fi

  # (g) mutants: each deletes one check from a copy of the script and the cell above must then miss its finding.
  _pn_mutant "$_t/pn-m1" PNM1 "PNM1"
  _want_rc 0 "PNM1  without the public_note_refs call the red fixture is CLEAN (the call is load-bearing) -> rc 0" "PNM1  call deleted"
  _pn_mutant "$_t/pn-mpr" PNK-pr "PNK-pr"
  _pn_miss "PNK-pr  without the main reference rule line 5 is missed (the rule is load-bearing)"     "[pr-ref] CHANGELOG.md:5 "
  _pn_mutant "$_t/pn-murl" PNK-url "PNK-url"
  _pn_miss "PNK-url without the URL rule line 11 is missed (the rule is load-bearing)"             "[pr-ref] CHANGELOG.md:11 "
  _pn_mutant "$_t/pn-mkey" PNK-key "PNK-key"
  _pn_miss "PNK-key without the key rule line 13 is missed (the rule is load-bearing)"             "[tracker-key] CHANGELOG.md:13 "
  _pn_mutant "$_t/pn-mptr" PNK-ptr "PNK-ptr"
  _pn_miss "PNK-ptr without the pointer rule line 16 is missed (the rule is load-bearing)"         "[internal-pointer] CHANGELOG.md:16 "
  _pn_mutant "$_t/pn-mex" PNK-ex "PNK-ex"
  _pn_miss "PNK-ex  without the attribute join line 18 is missed (the join is load-bearing)"       "[export-ignored] CHANGELOG.md:18 "
  # PNM5: with the per-heading reset deleted the exemption is a sticky latch again; PN14's fixture must then come
  # out CLEAN (rc 0, no [pr-ref]). Strict: any other outcome is a FAIL.
  rm -rf "$_t/pn-m5"; cp -R "$_t/pn-g14" "$_t/pn-m5"
  grep -v "# PNM5\$" "$ROOT/scripts/publish-public.sh" > "$_t/pn-m5/scripts/publish-public.sh"
  if cmp -s "$ROOT/scripts/publish-public.sh" "$_t/pn-m5/scripts/publish-public.sh"; then echo "  FAIL PNM   PNM5: the mutant is identical to the original"; _fail=$((_fail+1)); fi
  _gate_run "$_t/pn-m5"
  case "$_grc:$_gout" in
    0:*"[pr-ref]"*) echo "  FAIL PNM   PNM5: rc 0 yet a [pr-ref] is printed, which is inconsistent"; _fail=$((_fail+1)) ;;
    0:*) echo "  ok   PNM   PNM5  with the reset deleted (a positional latch) PN14's fixture is CLEAN (the version compare is load-bearing)" ;;
    *) echo "  FAIL PNM   PNM5: the mutant run gave rc $_grc, not a clean rc 0, so it proves nothing"; _fail=$((_fail+1)) ;;
  esac
  rm -rf "$_t/pn-m3"; cp -R "$_t/pn-g7" "$_t/pn-m3"
  grep -v "# PNM3\$" "$ROOT/scripts/publish-public.sh" > "$_t/pn-m3/scripts/publish-public.sh"
  if cmp -s "$ROOT/scripts/publish-public.sh" "$_t/pn-m3/scripts/publish-public.sh"; then echo "  FAIL PNM   PNM3: the mutant is identical to the original"; _fail=$((_fail+1)); fi
  _gate_run "$_t/pn-m3"
  _want_rc 0 "PNM3  without the gate's rc-3 finding the one-line block fixture is CLEAN (the finding is load-bearing) -> rc 0" "PNM3  finding deleted"
  # PNM2 runs the extractor itself: the function text of a copy without its rc-3 clause leaks the internal bullet.
  sed -n '/^extract_public_notes() {/,/^}/p' "$ROOT/scripts/publish-public.sh" > "$_t/pn-fn.orig"
  grep -v -e '# PNR-RC3$' -e '# PNR-BOTH$' "$_t/pn-fn.orig" > "$_t/pn-fn.mut"
  if cmp -s "$_t/pn-fn.orig" "$_t/pn-fn.mut"; then echo "  FAIL PNM   PNM2: the mutant is identical to the original"; _fail=$((_fail+1)); fi
  _pn_m2=$( . "$_t/pn-fn.mut"; extract_public_notes 9.9.9 "$_t/pn7.md" ) || true
  case $_pn_m2 in
    *INTERNAL-ONE*) echo "  ok   PNM   PNM2  without the rc-3 clause PN7b leaks the internal bullet (the clause is load-bearing)" ;;
    *) echo "  FAIL PNM   PNM2: the mutant did not leak, so PN7b proves nothing"; _fail=$((_fail+1)) ;;
  esac
  # PNM4: a grammar that wrongly ACCEPTS a line holding both markers (the `# PNR-BOTH` line deleted) must turn
  # S-1 red: the both-markers fixture then yields no `[malformed-block]`. The mutant must still RUN and red on
  # the planted identifier (rc 1 with the "CHANGELOG.md (between" finding), so a crash cannot pass for red.
  rm -rf "$_t/pn-m4"; cp -R "$_t/gate-both" "$_t/pn-m4"
  grep -v "# PNR-BOTH\$" "$ROOT/scripts/publish-public.sh" > "$_t/pn-m4/scripts/publish-public.sh"
  if cmp -s "$ROOT/scripts/publish-public.sh" "$_t/pn-m4/scripts/publish-public.sh"; then echo "  FAIL PNM   PNM4: the mutant is identical to the original"; _fail=$((_fail+1)); fi
  _gate_run "$_t/pn-m4"
  case "$_grc:$_gout" in
    1:*"[malformed-block]"*) echo "  FAIL PNM   PNM4: the mutant still reports [malformed-block], so S-1 proves nothing"; _fail=$((_fail+1)) ;;
    1:*"CHANGELOG.md (between"*) echo "  ok   PNM   PNM4  without the both-markers clause S-1 goes red (the clause is load-bearing)" ;;
    *) echo "  FAIL PNM   PNM4: the mutant run did not red on the planted identifier (rc $_grc), so it proves nothing"; _fail=$((_fail+1)) ;;
  esac

  # PNST: the selftest fails CLOSED. A scratch copy whose selftest aborts before its first section (the line
  # ending `# PNST-DIE` deleted, so the next line reads an unbound variable under set -u) must exit NON-zero and
  # never print "all passed"; this is the old fail-open (an abort exited 0). PNM6 deletes the sentinel clause
  # (`# PNM6`) from the same dying copy and the abort must then exit 0, which shows PNST is load-bearing.
  # The copy dies on its first lines, so it never runs a nested selftest.
  # Depth guard: each copy runs under PNST_NESTED=1 with _pnst_v unset, and runs ONLY if its `cmp -s` guard shows it
  # differs (an identical copy would be a full nested selftest, which would recurse without bound). A nested
  # selftest that ever reaches this point exits 1 here.
  [ "${PNST_NESTED:-0}" != 1 ] || { echo "publish-public --selftest: nested PNST refused" >&2; exit 1; }
  mkdir -p "$_t/pnst/scripts" "$_t/pnm6/scripts"
  grep -v "# PNST-DIE\$" "$ROOT/scripts/publish-public.sh" > "$_t/pnst/scripts/publish-public.sh"
  if cmp -s "$ROOT/scripts/publish-public.sh" "$_t/pnst/scripts/publish-public.sh"; then
    echo "  FAIL PNST  the dying copy is identical to the original (not run)"; _fail=$((_fail+1))
  else
    _pnst_rc=0; env -u _pnst_v PNST_NESTED=1 sh "$_t/pnst/scripts/publish-public.sh" --selftest > "$_t/pnst/out" 2>&1 || _pnst_rc=$?
    _pnst_out=$(cat "$_t/pnst/out")
    case "$_pnst_rc:$_pnst_out" in
      0:*|*"all passed"*) echo "  FAIL PNST  an aborted selftest exited $_pnst_rc or printed 'all passed' (fail-open)"; _fail=$((_fail+1)) ;;
      *_pnst_v*) echo "  ok   PNST  a selftest that aborts before its first section exits non-zero (rc $_pnst_rc) and prints no 'all passed'" ;;
      *) echo "  FAIL PNST  the dying copy exited $_pnst_rc but not through the planted unbound variable, so it proves nothing"; _fail=$((_fail+1)) ;;
    esac
  fi
  grep -v -e "# PNST-DIE\$" -e "# PNM6\$" "$ROOT/scripts/publish-public.sh" > "$_t/pnm6/scripts/publish-public.sh"
  if cmp -s "$_t/pnst/scripts/publish-public.sh" "$_t/pnm6/scripts/publish-public.sh"; then
    echo "  FAIL PNM   PNM6: the mutant is identical to the dying copy (not run)"; _fail=$((_fail+1))
  else
    _pnm6_rc=0; env -u _pnst_v PNST_NESTED=1 sh "$_t/pnm6/scripts/publish-public.sh" --selftest > "$_t/pnm6/out" 2>&1 || _pnm6_rc=$?
    _pnm6_out=$(cat "$_t/pnm6/out")
    case "$_pnm6_rc:$_pnm6_out" in
      0:*_pnst_v*) echo "  ok   PNM   PNM6  without the sentinel clause the aborted selftest exits 0 through the same abort (the clause, and so PNST, is load-bearing)" ;;
      *) echo "  FAIL PNM   PNM6: without the sentinel clause the aborted selftest exited $_pnm6_rc (want 0 with the _pnst_v abort in its output), so PNST proves nothing"; _fail=$((_fail+1)) ;;
    esac
  fi

  rm -rf "$_t" "$_h"; rm -f "$PUBLISH_ID_FILE" "$_hids" "$_sef"
  [ "$_fail" -eq 0 ] || { echo "publish-public --selftest: $_fail failed" >&2; exit 1; }
  echo "publish-public --selftest: all passed"
  _st_done=1
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
PUBLIC_NOTES_RC=0
PUBLIC_NOTES=$(extract_public_notes "$VERSION") || PUBLIC_NOTES_RC=$?
[ "$PUBLIC_NOTES_RC" -ne 3 ] || die "the public block of $VERSION in CHANGELOG.md is malformed: two markers share a line, or a second start marker opens before the end (SWAS-366). Nothing published."
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
  printf '%s\n' "$HITS" | sort -u | sed 's/^/  /' >&2
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
# SWAS-366: the note may not point at anything a public reader cannot open (PR numbers, tracker keys, the change
# log, export-ignored paths). rc 1 = findings, rc 2 = the check could not complete; both stop the publish here,
# before gitleaks and before any push. The finding lines name a line and a version, never the matched text.
NOTE_REFS_RC=0
NOTE_REFS=$(public_note_refs "$ROOT/CHANGELOG.md" "$VERSION" 2>"$NOTE_DIR/refs.err") || NOTE_REFS_RC=$?
[ "$NOTE_REFS_RC" -ne 2 ] || die "ABORT — the release note for $VERSION could not be checked for private references: $(_err_text "$NOTE_DIR/refs.err"). Nothing published."
[ ! -s "$NOTE_DIR/refs.err" ] || say "      note: $(_err_text "$NOTE_DIR/refs.err")"
[ "$NOTE_REFS_RC" -eq 0 ] || die "ABORT — the release note for $VERSION refers to something a public reader cannot open ($(printf '%s' "$NOTE_REFS" | tr '\n' ';')). Reword its CHANGELOG public block (MAINTAINING.md section 3). Nothing published."
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
