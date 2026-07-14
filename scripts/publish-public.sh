#!/bin/sh
# publish-public.sh — promote a released kit into the PUBLIC product repo.
#   sh scripts/publish-public.sh [--remote <url>] [--dry-run] [--allow-untagged] [--selftest]
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

usage() { echo "usage: publish-public.sh [--remote <url>] [--dry-run] [--allow-untagged] [--selftest]" >&2; exit 2; }

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
die()   { echo "publish-public: $*" >&2; exit 1; }
say()   { echo "publish-public: $*"; }

REMOTE=$PUBLIC_REMOTE_DEFAULT
DRY_RUN=0
ALLOW_UNTAGGED=0
SELFTEST=0
while [ $# -gt 0 ]; do
  case $1 in
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
#   - Owner identifiers in file CONTENT — the owner's name/email/home-path, read from the
#     EXPORT-IGNORED `.publish-identifiers` file (see PUBLISH_ID_FILE). A GENERIC /Users|/home scan
#     was rejected: it false-positives on legitimately-shipped example paths (e.g. a `/home/u/.ssh/
#     id_rsa` deny-case fixture in conformance/agent-autonomy.sh) and would abort every publish.
#     Targeting the OWNER's real identifiers via an external file catches the confirmed leak class
#     (a pre-anonymization personal path) with no false positives AND keeps this shipped file
#     identity-neutral. Binaries are scanned too (grep -a), since the export is small. If the file is
#     absent (an adopter's checkout), this dimension is N/A — the path denylist + gitleaks + step-4
#     still apply.
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
       -o \( -ipath "$_tree/docs/*" \
             -a \( -iname '*harvest*' -o -iname '*field-report*' -o -iname '*postmortem*' \) \) \
    \) -print 2>>"$_errf" | sed "s|^$_tree/||"

  # (2) owner identifiers in CONTENT, from the export-ignored config (identity-neutral by construction;
  #     absent => this dimension is N/A). -F: fixed strings, no regex surprises; -a: scan binaries too.
  if [ -f "$PUBLISH_ID_FILE" ]; then
    while IFS= read -r _id || [ -n "$_id" ]; do
      case "$_id" in ''|\#*) continue ;; esac
      grep -rlaF -e "$_id" "$_tree" 2>>"$_errf" | sed "s|^$_tree/||"
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
  printf '# test identifiers\nACME-OWNER-TOKEN-42\nowner@example.test\n' > "$PUBLISH_ID_FILE"
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
  : > "$_t/docs/2026-07-11-a-harvest.md"
  : > "$_t/docs/2026-07-11-a-field-report.md"
  : > "$_t/docs/2026-07-11-a-postmortem.md"
  printf 'owner path noted as ACME-OWNER-TOKEN-42 here\n'  > "$_t/docs/leaky.md"
  printf 'contact owner@example.test\n'                    > "$_t/docs/leaky-email.md"
  printf 'deny-case fixture: /home/u/.ssh/id_rsa\n'        > "$_t/docs/legit-example.md"
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
  _hit  docs/2026-07-11-a-harvest.md        "harvest (candid synthesis)"
  _hit  docs/2026-07-11-a-field-report.md   "field report"
  _hit  docs/2026-07-11-a-postmortem.md     "postmortem"
  _hit  docs/leaky.md                       "owner identifier in content (from config)"
  _hit  docs/leaky-email.md                 "owner email in content (from config)"
  _pass docs/legit-example.md               "generic /home/u example is NOT a false-positive"
  _pass templates/FIELD-REPORT-TEMPLATE.md  "blank template is shipped machinery"
  _pass templates/POSTMORTEM-TEMPLATE.md    "blank template is shipped machinery"
  _pass scripts/postmortem.sh               "shipped maintainer script (not a report)"
  _hit  docs/adoption/templates/a-postmortem.md "candid report under a nested templates/ (M1: no smuggling)"
  _pass SECURITY.md                         "product vocabulary is not a record"

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

  rm -rf "$_t"; rm -f "$PUBLISH_ID_FILE"
  [ "$_fail" -eq 0 ] || { echo "publish-public --selftest: $_fail failed" >&2; exit 1; }
  echo "publish-public --selftest: all passed"
  exit 0
}
[ "$SELFTEST" -eq 1 ] && selftest

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

WORK=$(mktemp -d "${TMPDIR:-/tmp}/sw-publish.XXXXXX") || die "mktemp failed"
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
say "published $TAG -> $REMOTE"
