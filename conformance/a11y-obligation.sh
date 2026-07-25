#!/bin/sh
# Why this gate: sparkwright explain a11y
# a11y-obligation.sh — HITL obligation: a change-set touching a user-facing UI surface (the
# components/views/pages/screens/ui/frontend/styles directories, at repo root or nested, plus the UI and
# view-template MARKUP EXTENSIONS enumerated in A11Y_SURFACE_GLOBS below — that variable is the single
# source of truth; the selftest derives its probes FROM it AND locks it against a corpus of real framework
# paths, so a glob mistyped into matching nothing real reds) MUST carry a filled A11Y-SIGNOFF record,
# else FAIL. Diff-level, riding the shipped obligation engine (same as threat-obligation.sh /
# uat-obligation.sh). Closes the Definition-of-Done Accessibility item (CLAUDE.md) and
# DEVELOPMENT-STANDARDS.md §8 (WCAG 2.1 AA), which were prose-only until now.
#
# RENAMES ARE FOLLOWED (H1): the engine's derivation passes `--no-renames`, so a UI file MOVED out of a UI
# directory still triggers on its SOURCE path. Before that, git's default rename detection emitted only the
# DESTINATION, so a `git mv` in the same PR silently derived N/A on this gate too.
#
# SCOPE (honest ceiling): green = an A11Y-SIGNOFF record EXISTS and is FILLED for a triggered change —
# NOT that WCAG 2.1 AA was actually met, that axe/Lighthouse was actually run, that the recorded pass/fail
# verdicts are truthful, or that the record is FRESH for this change (review + the signer's name backstop
# those). "Filled" is coarse, but no longer trivially faked: the engine rejects the template banner, its
# stub tokens, AND — since OBLIGATION-RECORD-FLOOR — any record below its minimum-substance floor
# (`OBL_MIN_SUBSTANCE_LINES`), so an empty, sub-floor or heading-less record now FAILs where it used to
# read as filled (verified on the production path). The ceiling that remains: eight lines of prose under a
# heading still passes, and the floor measures STRUCTURE, never QUALITY. This paragraph previously said
# that floor was "boarded, not claimed" — it shipped in the same slice, and a check header that
# UNDERSTATES its own teeth is the same defect as one that overstates them. N-A = the
# change-set touches no user-facing UI surface (trigger-absence), exactly like uat-obligation.sh.
# CONSERVATIVE by design: clear-UI globs ONLY — ambiguous/non-UI files are N-A and false-negatives are
# accepted (the only 'uncertain' source is a derive-failure, which fails CLOSED).
#
# The record is read at the REPOSITORY ROOT (./A11Y-SIGNOFF.md) — not docs/sign-offs/. The template's
# banner states this; a record filed elsewhere reds with "absent", which is fail-closed but confusing.
#
# SURFACE vs uat-obligation.sh: the SAME clear-UI directory set, because a11y and taste are two DIFFERENT
# judgments about the SAME user-facing surface (a WCAG verdict signed by the designer/a11y owner vs. an
# acceptance verdict signed by QA/PO). Two DELIBERATE divergences, each from evidence, not taste:
#  1. VIEW-TEMPLATE MARKUP EXTENSIONS replace uat's bare `*/templates/*`. A directory named `templates/`
#     is NOT a UI signal — Helm, CloudFormation and cookiecutter all use it, and this repo carries 14 such
#     files (profiles/*/deploy/helm/templates/*.yaml). Gating them would demand a WCAG sign-off for a
#     Kubernetes Deployment manifest: a false positive with no honest way to satisfy it, and a gate that
#     reds on compliant behavior is a gate that gets deleted. A view template is identified instead by its
#     MARKUP EXTENSION, which also catches a view template living OUTSIDE a templates/ dir.
#     HONEST TRADE (do not restate this as a strict win — an earlier draft did, and review falsified it):
#     the extension list is broader in one direction and NARROWER in another. A view template whose
#     extension is not listed (.vm, .st, .dust, a bare .tmpl variant) is now N/A where the bare directory
#     glob would have caught it. The list below enumerates the mainstream engines, including those the
#     kit's own profiles ship (.gohtml/.tmpl for go, .cshtml/.razor for dotnet, .ftl for java-spring);
#     the residual false-negative is accepted under the conservative posture and named here.
#  2. *.html/*.htm: semantic HTML is a first-class a11y surface, whereas a raw .html edit is not
#     necessarily a taste change.
#
# CONFIG TEMPLATES (OBLIGATION-CONFIG-TEMPLATE-EXT — CLOSED, not open): several listed extensions are also
# used for NON-UI templates — Ansible/Chef config (roles/nginx/templates/nginx.conf.j2, app.conf.erb),
# Terraform, and — note the irony — Helm's own _helpers.tpl, the exact case the paragraph above uses to
# justify dropping */templates/*. This gate used to demand a WCAG sign-off for an nginx config and said so
# here as a disclosed defect. The engine now takes an exclusion list evaluated BEFORE the surface globs and
# this check declares one ($A11Y_EXCLUDE_GLOBS, below), so those paths are N/A. The list is compound
# SUFFIXES and Helm's `_`-prefixed partials — never a bare extension, which would delete the surface it is
# refining. TWO legs hold that: LEG 11 asserts the SHAPE of every entry (an exclusion of any other shape is
# refused outright — the engine's own refusal catches only a glob matching EVERY path, far weaker than this
# list needs), and LEG 12 holds real view templates on those same extensions still gated — plus, since the
# shape rule bounds an exclusion's blast radius without deciding config-vs-UI, two canonical UI
# compound-suffix conventions (`*.component.html`, `*.module.css`) that no structural rule can protect.
# THE RESIDUAL IS A CLASS, NOT A CASE, and an earlier version of this line said "THE residual" was a bare
# `<name>.tpl`: in fact ANY compound suffix not enumerated in the list still triggers — `*.json.tpl`,
# `*.env.tpl`, `*.ini.j2`, `*.sh.j2`, `*.yml.erb`, `*.sh.erb` (the last two the commonest Chef shapes) all
# measured FAIL. The list is the mainstream cases, NOT exhaustive; $A11Y_EXCLUDE_GLOBS records why chasing
# the class with a longer list is refused. The bare `<name>.tpl` case (Terraform's `user_data.tpl`, as
# against `user_data.sh.tpl` or the `.tftpl` convention, which never matched `*.tpl` at all) is still worth
# naming because unlike the rest it could not be excluded even in principle: it is indistinguishable BY
# PATH from a Smarty view template. Accepted under the conservative posture.
#
# KNOWN FALSE NEGATIVES: a view template whose extension is not listed (.vm, .st, .dust), server-rendered
# .php/.blade.php, and Android res/layout/*.xml are all N/A. Conservative posture, accepted, named.
#
# NON-ASCII PATHS: fixed in the engine this slice (obl_changeset sets core.quotePath=false and splits on
# NUL). Before that fix a path with one accented byte was quote-wrapped and evaded every EXTENSION glob —
# and because this obligation's surface is mostly extensions, it was the gate this bit hardest.
#
# FRESHNESS (the same disclosure threat-obligation.sh:8 makes): this gate proves a filled record EXISTS —
# NOT that it is fresh for THIS change. One committed root A11Y-SIGNOFF.md satisfies every later UI PR.
# The record carries a Date and a Feature/story link so a reviewer can see staleness; the gate cannot.
#
# Usage:
#   sh conformance/a11y-obligation.sh                 (derive change-set: merge-base HEAD origin/main)
#   sh conformance/a11y-obligation.sh --changed FILE  (fixture path list; honored ONLY under
#                                                      --selftest / the KIT_OBL_TEST env flag — ignored in production)
#   sh conformance/a11y-obligation.sh --selftest
set -eu
# shellcheck disable=SC1007 # `CDPATH= cd` is the correct idiom: it clears CDPATH for this one command so
# a user's CDPATH cannot redirect the cd; the empty assignment is intentional, not a mistyped value.
DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# Tell the engine it is being SOURCED (not executed directly), so its --selftest dispatch stays inert
# here: without this, `sh a11y-obligation.sh --selftest` would run the LIB's selftest (the sourced lib
# sees $1=--selftest) instead of this obligation's 13-leg selftest. Value is 'yes' (NOT a numeric flag) so
# the non-vacuity sweep — which neuters a pre-marker numeric-flag assignment — cannot flip it; this line
# carries no mutable idiom, so run_a11y_obligation stays the (idiomless) mutation region and this file's
# verdict is unchanged. A $0-basename guard would not survive the sweep renaming the lib's copy to .nv-mut-*.
OBL_LIB_SOURCED=yes
. "$DIR/conformance/obligation-lib.sh"

# The obligation: user-facing-UI globs + A11Y-SIGNOFF record. THIS STRING IS THE SINGLE SOURCE OF TRUTH:
# the selftest's coverage leg DERIVES one probe path per glob from it, so adding a glob automatically adds
# its proof and a glob written in an unprobeable SHAPE is itself a failure. Do not hand-maintain a probe
# list alongside it — an earlier draft did, and a newly-added glob then shipped unproven.
# WHAT DERIVED PROBES CANNOT DO (measured, so the comment does not overclaim as an earlier one did): a
# probe derived FROM a glob always matches that glob, so a MISTYPED glob (*.sccs, */screen/*) self-
# validates and that leg stays green. The EXACT count lock catches a glob being DROPPED. A typo used to be
# caught by nothing, which this comment recorded as an open residual; the CORPUS LOCK in LEG 5 now closes
# the part of it that matters — a glob matching nothing real reds — by going path -> glob instead of
# glob -> path. Its own ceiling is stated there (a typo that merely WIDENS a glob is still uncaught, and
# review is still the backstop). Round-1's hand-listed probes caught typos but missed additions;
# derivation is the opposite trade, and the corpus lock is what buys back the half it gave up.
# Each directory appears TWICE: `x/*` for a repo-root directory and `*/x/*` for a nested one. `*/x/*`
# requires a leading path segment, so root-level `components/Nav.tsx` would otherwise be N/A.
A11Y_SURFACE_GLOBS='components/*|*/components/*|views/*|*/views/*|pages/*|*/pages/*|screens/*|*/screens/*|ui/*|*/ui/*|frontend/*|*/frontend/*|styles/*|*/styles/*|*.tsx|*.jsx|*.vue|*.svelte|*.css|*.scss|*.less|*.html|*.htm|*.j2|*.jinja|*.jinja2|*.erb|*.hbs|*.handlebars|*.ejs|*.twig|*.pug|*.haml|*.slim|*.liquid|*.mustache|*.astro|*.njk|*.tmpl|*.gohtml|*.templ|*.tpl|*.cshtml|*.razor|*.jsp|*.jspx|*.ftl|*.heex|*.eex'

# CONFIG TEMPLATES ARE NOT UI (OBLIGATION-CONFIG-TEMPLATE-EXT). Detecting a view template by its markup
# EXTENSION cannot tell one from a CONFIG template that borrows the same extension, and the check header
# disclosed that as an open false positive: Ansible and Chef write roles/nginx/templates/nginx.conf.j2 and
# app.conf.erb, and `.tpl` covers Terraform's templatefile() inputs AND Helm's own templates/_helpers.tpl —
# the very case the paragraph above uses to justify dropping the bare `*/templates/*` glob, re-entering
# through the extension list. The engine now takes an exclusion list, evaluated BEFORE any surface glob.
#
# AN EXCLUSION IS AN OFF-SWITCH, so the SHAPE of every entry is the safety property, not a detail:
#  - COMPOUND SUFFIXES ONLY (`*.conf.j2`), never a bare extension. `*.j2` as an exclusion would delete the
#    surface it is meant to refine. WHAT A COMPOUND SUFFIX ACTUALLY GUARANTEES, stated exactly — because
#    this bullet used to claim it "can only ever remove the config half" and that is FALSE: it can only
#    match a path whose final component carries at least two dots, so it can never delete a whole
#    EXTENSION (`Nav.css` and `page.html` keep triggering). It CAN still name a real UI CONVENTION.
#    MEASURED, count lock held at 12, each substituted one at a time for a real entry: `*.component.html`
#    (Angular), `*.module.css` (CSS Modules / Next.js), `*.module.scss`, `*.page.tsx`, `*.view.hbs` and
#    `*.html.haml` each survived ALL 13 LEGS green, and on the true production path
#    `src/app/hero/hero.component.html` went from FAIL to "N/A: no a11y surface touched" — one
#    plausible-looking entry deleting every screen of an Angular app from the surface. So the shape rule
#    BOUNDS THE BLAST RADIUS; it does not decide config-vs-UI, and it cannot be made to — `*.stories.tsx`
#    and `*.test.tsx` are the same shape and are arguably LEGITIMATE exclusions, so no structural rule
#    separates the two. That judgment is NAMED, not automated: LEG 12's fixtures now hold
#    `*.component.html` and `*.module.css` behaviourally (both red there), and REVIEW is the backstop for
#    every convention not in that fixture list — `*.module.scss`, `*.page.tsx`, `*.view.hbs` and
#    `*.html.haml` were re-measured AFTER those two fixtures landed and still survive all 13 legs.
#  - the only non-suffix entries are Helm's `_`-prefixed partials, written twice (`templates/_*.tpl` and
#    `*/templates/_*.tpl`) because `*/x/*` requires a leading path segment and a chart at the repo root has
#    none — the same doubling A11Y_SURFACE_GLOBS uses for its directory globs.
#  - WHAT ENFORCES THAT SHAPE IS LEG 11's SHAPE ASSERTION, and this bullet used to name the wrong
#    mechanism. It said the ENGINE refuses any exclusion matching every path, "so this list cannot be
#    widened into a blanket N/A even by a bad edit here" — attributing the defence to the one mechanism
#    that does not provide it. The engine's universal test is `*[!*?]*` -> not universal, so ANY glob
#    naming a single character escapes it. MEASURED with the count lock held at 12: swapping a real entry
#    for `*/pages/*.tsx` or `*/views/*.vue` passed all 13 legs GREEN and silently deleted Next.js `pages/`
#    and Vue `views/` from the surface. LEG 11 now asserts the shape rule itself — derived from the glob
#    string, not a deny-list — so the claim is true as written. The engine's refusal stays as defence in
#    depth for the universal case, and LEG 12 stays the behavioural half (a real view template on each
#    excluded EXTENSION must still trigger — and, per the first bullet, two canonical UI compound-suffix
#    conventions the shape rule cannot tell apart from a config suffix).
# THE RESIDUAL IS A CLASS, NOT A CASE. An earlier version of this paragraph called "THE residual" a bare
# `<name>.tpl` with no inner extension. The definite article was wrong, and UNDERSTATING a gate's reach is
# the same defect as overstating it — the rule this check's own SCOPE paragraph states. The true statement:
# ANY compound suffix not enumerated above still demands a sign-off. MEASURED on this check —
# `infra/policy.json.tpl`, `terraform/vars.env.tpl`, `roles/x/templates/app.ini.j2`, `.../app.service.j2`,
# `.../deploy.sh.j2`, `.../data.json.j2`, `cookbooks/x/templates/db.yml.erb` and `.../app.sh.erb` all FAIL,
# and the last two are the two most common Chef shapes. The list is THE MAINSTREAM CASES, NOT EXHAUSTIVE,
# and it is deliberately NOT being extended to chase the class: the class is unbounded (`*.toml.j2`,
# `*.xml.j2`, `*.properties.j2`, `*.hcl.tpl`, `*.json.erb`, `*.sql.j2` … each measured FAIL too), so no
# finite list makes a definite article true — while every entry added is another off-switch, and for an
# EXCLUSION an ADDITION is the dangerous direction (see LEG 11's count lock). One case within the class is
# still worth naming because it could not be excluded even in principle: a bare `<name>.tpl` (Terraform's
# `user_data.tpl`, as opposed to the `user_data.sh.tpl` / `*.tftpl` conventions) is INDISTINGUISHABLE BY
# PATH from a Smarty view template, which really is a11y-relevant. `*.tftpl` never matched `*.tpl` in the
# first place and was already N/A.
A11Y_EXCLUDE_GLOBS='*.conf.j2|*.cfg.j2|*.yaml.j2|*.yml.j2|*.conf.erb|*.ini.erb|templates/_*.tpl|*/templates/_*.tpl|*.conf.tpl|*.yaml.tpl|*.yml.tpl|*.sh.tpl'

# The `--` before "$@" is LOAD-BEARING, not decoration: it closes this check's own definition, and the
# engine refuses the six gate-defining arguments after it. Without it a caller could append
# `--stub-pattern …` and switch Signal 2 off from the command line — the engine's first-assignment-wins
# rule cannot defend an argument this file never sets (measured before the fix: the bare command FAILed,
# the same command with `--stub-pattern '\[zzz'` PASSed). LEG 10 below is the proof; delete the `--` and it
# reds. --exclude-globs is the same class one rung more dangerous — an off-switch rather than a signal —
# and LEG 13 is its proof; measured on the true production path, `--exclude-globs '*'` appended to this
# command is announced as ignored and the verdict is unchanged. The fixture flags in "$@"
# (--changed/--root/--force-uncertain) still parse — the sentinel fences only the six, and every leg
# forwards theirs AFTER it.
run_a11y_obligation() {   # args: forwarded (--changed FILE | none)
  obligation_gate \
    --name "a11y" \
    --surface-globs "$A11Y_SURFACE_GLOBS" \
    --exclude-globs "$A11Y_EXCLUDE_GLOBS" \
    --record "A11Y-SIGNOFF.md" \
    --template-marker "templates/A11Y-SIGNOFF-TEMPLATE.md" \
    -- \
    "$@"
}

# ---- selftest() marker: the non-vacuity sweep mutates ONLY lines ABOVE here ----
selftest() {
  # The four EXTERNALLY DECLARED counts the completeness locks assert against. Declared here, not computed
  # from the things they check — a lock derived from its subject can always be satisfied by construction.
  # (This line said "the two" while declaring three: a stale count in the comment that names the file's own
  # anti-drift device is the same defect class the locks below exist to catch, so it is corrected here.)
  A11Y_TEMPLATE_STUB_ROWS=10     # fillable rows in A11Y-SIGNOFF-TEMPLATE.md          (LEG 9)
  A11Y_SURFACE_GLOB_COUNT=49     # alternations in A11Y_SURFACE_GLOBS                 (LEG 5)
  A11Y_EXCLUDE_GLOB_COUNT=12     # alternations in A11Y_EXCLUDE_GLOBS                 (LEG 11)
  A11Y_CORPUS_PATH_COUNT=40      # real-world UI paths in $A11Y_SURFACE_CORPUS        (LEG 5, corpus lock)
  _tmp="$(mktemp -d "${TMPDIR:-/tmp}/a11y-st.XXXXXX")"; trap 'rm -rf "$_tmp"' EXIT INT TERM
  export KIT_OBL_TEST=1   # honor the fixture flags (--changed/--root/--force-uncertain) only in-test (M1)
  rc=0
  # LEG 1 (liveness/negative): user-facing UI surface touched, NO record -> RED
  printf 'src/components/Nav.tsx\n' > "$_tmp/changed"
  if run_a11y_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: UI surface with no A11Y-SIGNOFF did not FAIL"; rc=1
  fi
  # LEG 2 (positive): no UI surface -> green (N-A)
  printf 'docs/README.md\n' > "$_tmp/changed"
  if ! run_a11y_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: non-UI change did not pass (N-A)"; rc=1
  fi
  # LEG 3 (fail-safe, simulated): --force-uncertain simulates the uncertain band (the conservative posture
  # has no per-file uncertain heuristic; the REAL uncertain trigger is a derive-failure — LEG 4). NO record -> RED
  printf 'config/settings.yaml\n' > "$_tmp/changed"
  if run_a11y_obligation --changed "$_tmp/changed" --root "$_tmp" --force-uncertain >/dev/null 2>&1; then
    echo "SELFTEST FAIL: uncertain surface with no record did not FAIL (fail-safe broken)"; rc=1
  fi
  # LEG 4 (REAL derive-failure, C1/H1): a change-set that CANNOT be derived (no resolvable base) must fail
  # CLOSED — route to uncertain and require the record. Throwaway repo with NO origin/main and NO 'main'
  # branch, so both merge-base probes fail: a REAL derive-failure, not the --force-uncertain simulation.
  _dr="$_tmp/derive"; mkdir -p "$_dr"
  git -C "$_dr" init -q >/dev/null 2>&1
  git -C "$_dr" config user.email obl@test.local
  git -C "$_dr" config user.name obl-test
  : > "$_dr/file.txt"; git -C "$_dr" add file.txt; git -C "$_dr" commit -qm init >/dev/null 2>&1
  git -C "$_dr" branch -m obl-st-nobase >/dev/null 2>&1   # rename so neither 'main' nor 'master' resolves
  if ( cd "$_dr" && run_a11y_obligation --root "$_dr" ) >/dev/null 2>&1; then
    echo "SELFTEST FAIL: underivable change-set (no resolvable base) did not FAIL (derive fail-open)"; rc=1
  fi
  # LEG 5 (GLOB COVERAGE): EVERY surface glob must be load-bearing. Without this, only the glob a fixture
  # happens to exercise is proven and the rest can be DELETED while the selftest stays green — a mutation
  # probe confirmed 15 of 16 globs were unproven before this leg existed. Deletion is caught by the exact
  # count lock below; a MISTYPED glob is not caught by the DERIVED probes (it self-validates — see the note
  # at A11Y_SURFACE_GLOBS) and is caught instead by the CORPUS LOCK in this leg's second half. Do not read
  # the probe loop as proving the globs are correct, only that they are present and live.
  # Each directory glob is probed with the inert extension '.q' so it cannot double-match an extension
  # glob, and each extension glob with a path in no matching directory. Runs BEFORE LEG 6 creates the
  # record, so every RED here is caused by trigger + absence, never by ordering.
  # Probes are DERIVED from $A11Y_SURFACE_GLOBS, never hand-listed, so the leg cannot fall behind the
  # surface it is proving. Three recognised glob shapes; an unrecognised one is itself a failure, so a
  # future glob written in a shape this derivation cannot probe can never ship silently unproven.
  # SPLIT VIA `tr` + `IFS= read`, NOT by save/restore of the global IFS. An earlier version wrapped a
  # `for` in `_oldifs=$IFS; IFS='|'; set -f` … `IFS=$_oldifs`, which semgrep's
  # bash.lang.security.ifs-tampering flagged FOUR times — caught not by any local check but by the kit's
  # own emitted-artifact SAST gate (`artifact-gate`), on the artifact, which is precisely what that gate
  # exists for. Reproduced locally: old file 4 findings, this one 0.
  # (An earlier version of this note added "obl_detect uses a save/restore form that this rule does NOT
  # flag — it ships clean and needs no change. Do not fix it on the strength of this note." That was
  # FALSE, and measurably so: obligation-lib.sh scored 0 only because semgrep's bash grammar could not
  # parse a `case` whose first clause starts on the `case … in` line, raised a syntax error at obl_detect
  # and skipped the whole function — `Parsed lines: ~11.5%`. Split that one `case` across lines with no
  # other change and the same rule scores 3. obl_detect has since been rewritten off the save/restore
  # form and the file now parses at 100%; the reasoning is recorded at _obl_glob_scan.)
  # `IFS= read -r` is a command-scoped prefix assignment, not a global mutation. Reading from a FILE
  # (not a pipe) keeps the loop in this shell, so `rc` and the counters survive it; a `… | while` would
  # run in a subshell and silently discard every failure this leg detects.
  _covered=0; _globcount=0
  printf '%s\n' "$A11Y_SURFACE_GLOBS" | tr '|' '\n' > "$_tmp/globs"
  while IFS= read -r _g; do
    [ -n "$_g" ] || continue
    _globcount=$((_globcount + 1))
    case "$_g" in
      '*/'*'/*') _mid=${_g#*/}; _mid=${_mid%/*}; _p="a/$_mid/probe.q" ;;   # nested dir:  */components/*
      *'/*')     _mid=${_g%/*};                  _p="$_mid/probe.q"   ;;   # root dir:    components/*
      '*.'*)     _p="s/probe${_g#\*}"                                  ;;   # extension:   *.tsx
      *)         _p=""                                                 ;;
    esac
    if [ -z "$_p" ]; then
      printf 'SELFTEST FAIL: unrecognised surface-glob shape %s — the coverage leg cannot derive a probe for it, so it would ship UNPROVEN\n' "$_g"; rc=1
    else
      printf '%s\n' "$_p" > "$_tmp/changed"
      if run_a11y_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
        printf 'SELFTEST FAIL: surface glob dead — %s (probe %s) touched with no A11Y-SIGNOFF did not FAIL\n' "$_g" "$_p"; rc=1
      fi
      _covered=$((_covered + 1))
    fi
  done < "$_tmp/globs"
  # Family-completeness: every glob got a probe. Guards the derivation itself going silently inert.
  [ "$_covered" = "$_globcount" ] || { printf 'SELFTEST FAIL: only %s of %s surface globs were probed\n' "$_covered" "$_globcount"; rc=1; }
  # EXACT count lock, not a floor. A floor (>= 20 against an actual 49) let 26 globs — the entire
  # view-template extension set — be deleted with the selftest still printing OK. Same repair as leg 9's:
  # an EXTERNALLY DECLARED constant the code cannot satisfy by construction. Changing the surface must
  # update this number deliberately; a silent deletion reds here.
  [ "$_globcount" = "$A11Y_SURFACE_GLOB_COUNT" ] || {
    printf 'SELFTEST FAIL: %s surface globs parsed, expected exactly %s — a glob was added or removed without updating A11Y_SURFACE_GLOB_COUNT\n' \
      "$_globcount" "$A11Y_SURFACE_GLOB_COUNT"; rc=1; }
  # LEG 5, SECOND HALF — THE CORPUS LOCK (OBLIGATION-GLOB-SHAPE-LOCK). Part of LEG 5, not a fourteenth
  # leg, because it locks the same subject (A11Y_SURFACE_GLOBS) that LEG 5's probe loop and count lock do,
  # and the leg count is asserted in prose elsewhere in this file and in conformance/README.md.
  #
  # THE HOLE IT CLOSES: LEG 5's probes are DERIVED from the glob string, so a probe always matches its own
  # glob and a MISTYPED glob SELF-VALIDATES. MEASURED on this build before this lock existed: substituting
  # `*.tsxx` for `*.tsx`, and `*/screen/*` for `*/screens/*`, each left the whole selftest at rc=0 while
  # the gate was silently dead for that file class.
  #
  # WHY NOT THE SHAPE RULE THAT WAS BOARDED FOR THIS. A shape rule validates FORM; a typo is a CONTENT
  # error and is perfectly well-formed. MEASURED: `*.tsxx` is accepted by `^\*\.[a-z0-9]+$` ("tsxx" IS
  # lowercase alnum) and `*/screen/*` by `^\*/[a-z]+/\*$` ("screen" IS lowercase alpha) — the boarded AC
  # could not catch either of its own two examples. Replacing it with this corpus lock is owner-ratified.
  #
  # THE MECHANISM, and why it is the INVERSE of the derived-probe leg rather than more of the same: the
  # probe loop goes glob -> path (self-validating); this goes path -> glob and cannot. A dead glob matches
  # nothing real. The corpus is written as REAL FRAMEWORK PATHS — never derived from the glob strings, which
  # is the entire point — covering both the repo-root (`components/Nav.tsx`) and nested
  # (`web/src/components/UserCard.tsx`) directory forms that A11Y_SURFACE_GLOBS doubles every directory for.
  # Matching uses the ENGINE'S OWN `_obl_glob_scan`, not a re-implemented `case`, so the lock cannot drift
  # from production matching semantics.
  #
  # TWO DIRECTIONS, both load-bearing:
  #  (i)  every surface glob must match >= 1 corpus path  -> a glob that names nothing real reds;
  #  (ii) every corpus path must match >= 1 surface glob  -> the corpus cannot rot into a list of paths the
  #       gate no longer covers, and a padding entry that matches nothing is refused rather than ignored.
  # Plus an EXACT count lock on the corpus itself, for the reason LEG 5's and LEG 11's carry one — see the
  # ceiling below for which direction is the dangerous one here.
  #
  # HONEST CEILING — do NOT read this as making a dead glob impossible:
  #  - It catches a typo that leaves a glob matching NOTHING REAL. A typo that merely WIDENS or SHIFTS a
  #    glob while still matching a corpus path (`*/screens/*` -> `*/screens*`) is NOT caught here.
  #  - It makes shipping a NEW dead glob require deliberately inventing a fake path beside it AND bumping
  #    A11Y_CORPUS_PATH_COUNT — two conscious acts, not one slip. That is a raised cost, not impossibility.
  #  - It says nothing about whether a glob that DOES match real paths is the RIGHT glob.
  # REVIEW IS THE BACKSTOP for all three. Stated here rather than implied, because a lock that READS as
  # proving the surface correct while proving only that it is non-empty is the defect this check's own
  # SCOPE paragraph forbids.
  #
  # Real paths from the frameworks each glob exists for. One line per path; no path contains a space.
  A11Y_SURFACE_CORPUS='components/Nav.tsx
web/src/components/UserCard.tsx
views/dashboard.ejs
app/views/layouts/application.html.erb
pages/index.jsx
apps/web/pages/checkout.tsx
screens/LoginScreen.js
mobile/src/screens/ProfileScreen.tsx
ui/Button.svelte
packages/ui/src/Modal.vue
frontend/main.js
apps/frontend/index.html
styles/global.css
src/styles/theme.scss
src/theme/variables.less
docs/legacy/index.htm
app/templates/base.j2
myapp/templates/registration/login.jinja
templates/email/welcome.jinja2
src/templates/user-card.hbs
app/assets/templates/header.handlebars
templates/base.html.twig
views/layout.pug
app/views/users/index.html.haml
app/views/posts/show.html.slim
sections/product-header.liquid
src/templates/profile.mustache
src/pages/blog.astro
src/_includes/layouts/base.njk
web/templates/home.tmpl
internal/web/templates/layout.gohtml
views/home.templ
themes/default/header.tpl
Pages/Index.cshtml
Components/Counter.razor
src/main/webapp/WEB-INF/views/home.jsp
src/main/webapp/WEB-INF/views/list.jspx
src/main/resources/templates/index.ftl
lib/my_app_web/controllers/page_html/home.html.heex
lib/my_app_web/templates/layout/app.html.eex'
  printf '%s\n' "$A11Y_SURFACE_CORPUS" > "$_tmp/corpus"
  # (ii) + the count lock. Walks the corpus once against the WHOLE surface string, which is one
  # _obl_glob_scan call per path — the same call the production path makes per changed file.
  _cp_count=0
  while IFS= read -r _c; do
    [ -n "$_c" ] || continue
    _cp_count=$((_cp_count + 1))
    if ! _obl_glob_scan "$_c" "$A11Y_SURFACE_GLOBS"; then
      printf 'SELFTEST FAIL: corpus path %s is matched by NO surface glob — either the glob that covered it was dropped, or a padding entry was added to the corpus to legitimise a dead glob\n' "$_c"; rc=1
    fi
  done < "$_tmp/corpus"
  # The dangerous direction for the CORPUS is an ADDITION (a fake path invented to keep a dead glob
  # green), the mirror of LEG 11's exclusion asymmetry — so the count must be a conscious act either way.
  [ "$_cp_count" = "$A11Y_CORPUS_PATH_COUNT" ] || {
    printf 'SELFTEST FAIL: %s corpus paths parsed, expected exactly %s — a real-world UI path was added or removed without updating A11Y_CORPUS_PATH_COUNT\n' \
      "$_cp_count" "$A11Y_CORPUS_PATH_COUNT"; rc=1; }
  # (i) THE DEAD-GLOB ASSERTION. Reuses $_tmp/globs, which LEG 5's probe loop derived from
  # $A11Y_SURFACE_GLOBS above — so this half cannot fall behind the surface either. Inner loop redirects
  # its own stdin from the corpus file, leaving the outer loop's descriptor untouched (POSIX), and reads
  # from FILES rather than pipes so `rc` survives.
  while IFS= read -r _g; do
    [ -n "$_g" ] || continue
    _cl_hit=0
    while IFS= read -r _c; do
      [ -n "$_c" ] || continue
      if _obl_glob_scan "$_c" "$_g"; then _cl_hit=1; break; fi
    done < "$_tmp/corpus"
    [ "$_cl_hit" = 1 ] || {
      printf 'SELFTEST FAIL: surface glob %s matches NO path in the %s-path real-world UI corpus — it is DEAD. A mistyped glob (*.tsxx for *.tsx, */screen/* for */screens/*) is perfectly well-formed and self-validates against a derived probe, so this is what catches it: the file class it names is currently ungated\n' \
        "$_g" "$A11Y_CORPUS_PATH_COUNT"; rc=1; }
  done < "$_tmp/globs"
  # LEG 6 (FALSE-POSITIVE guard, derived from the SHIPPED template): UI surface touched + a genuinely
  # filled record -> PASS. The fixture is built FROM templates/A11Y-SIGNOFF-TEMPLATE.md (banner stripped,
  # every stub substituted) rather than hand-written, so this leg COUPLES the check to the artifact whose
  # tightening is this slice's headline change. A hand-written fixture cannot do that — and that gap is
  # exactly why an inert '[describe:' stub shipped green through the first review round.
  printf 'src/components/Nav.tsx\n' > "$_tmp/changed"
  _tpl="$DIR/templates/A11Y-SIGNOFF-TEMPLATE.md"
  if [ ! -f "$_tpl" ] || [ ! -s "$_tpl" ]; then
    echo "SELFTEST FAIL: templates/A11Y-SIGNOFF-TEMPLATE.md is missing or empty — the record-shape legs cannot run"; rc=1
  else
    # fill(): the shipped template with its guidance banner deleted and every stub substituted.
    # ONE GENERIC BRACKET PATTERN, not the engine's `(replace|describe|your)` vocabulary. This is the
    # round-2 correction and it is the whole point of legs 6-8: an oracle that recognises only the tokens
    # it already knows cannot detect a template that ADOPTS A NEW ONE. With the vocabulary-coupled version,
    # renaming a cell to `[attach: …]` was invisible to fill(), invisible to the stub finder, AND invisible
    # to the engine — the selftest printed "every template stub cell proven" while the cell was inert.
    # Generic `\[[^]]*\]` means any bracketed token the template adopts is substituted here and probed by
    # leg 8, so the engine must be able to see it. Consequence, deliberate: this template must not carry
    # markdown links in its VALUE cells — for a sign-off form that is a fair constraint, and violating it
    # reds loudly at leg 8 rather than silently weakening detection.
    fill() { grep -v '^> \*\*Template\.\*\*' "$_tpl" | sed 's/\[[^]]*\]/pass — axe 4.9 CI run, 0 violations, Jane Roe/g'; }
    fill > "$_tmp/A11Y-SIGNOFF.md"
    if ! run_a11y_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
      echo "SELFTEST FAIL: the SHIPPED template, banner-stripped and fully filled, was wrongly FAILed as a placeholder"; rc=1
    fi
    # LEG 7 (the BANNER-DELETE bypass this slice exists to close): the shipped template with ONLY its
    # banner line removed — every field still a raw stub — must be rejected as unfilled. Ties the claim
    # to the artifact: a future template edit that reintroduces the bypass reds HERE, forever.
    grep -v '^> \*\*Template\.\*\*' "$_tpl" > "$_tmp/A11Y-SIGNOFF.md"
    if run_a11y_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
      echo "SELFTEST FAIL: the shipped template with its banner deleted was accepted as FILLED (banner-delete bypass is open)"; rc=1
    fi
    # LEG 8 (PER-CELL stub detection): the shipped template, banner stripped and every stub filled EXCEPT
    # one — must still be rejected. Run once per stub line, so NO single cell can be the inert one. This
    # is the leg that kills the '[describe:' defect (the tool-evidence cell was invisible to Signal 1) and
    # keeps every other cell honest as the template evolves.
    # Work off the BANNER-STRIPPED template so line numbers align with the fixture and the banner — whose
    # guidance text legitimately NAMES the stub tokens — is never itself probed as a cell.
    # The stub set is found with the SAME generic bracket pattern fill() substitutes — not the engine's
    # vocabulary — so a renamed token stays in the probe set and its inertness reds here.
    grep -v '^> \*\*Template\.\*\*' "$_tpl" > "$_tmp/tpl-nobanner.md"
    _stub_lines=$(grep -n '\[[^]]*\]' "$_tmp/tpl-nobanner.md" | cut -d: -f1)
    _stub_count=$(printf '%s\n' "$_stub_lines" | grep -c '[0-9]' || true)
    if [ -z "$_stub_lines" ]; then
      echo "SELFTEST FAIL: the shipped template carries NO bracketed stub token — the tightening is gone"; rc=1
    fi
    # LEG 9 (FAMILY-COMPLETENESS LOCK) — headered so a grep for the numbered leg headers returns one line
    # per leg. This was the one leg implemented unheadered, so that grep returned 12 for 13 legs and the
    # count was not auditable from outside. The kit's presence-check-cannot-see-substitution lesson. A generic
    # pattern catches a RENAMED token, but not a REMOVED one: reverting a cell to bare `pass / fail`
    # simply drops it from the probe set, and a per-cell loop over a shrinking set stays green — 20 such
    # mutants survived the round-1 version. So the COUNT is asserted against the template's fillable-row
    # count. Deliberately a declared constant: changing the template's row set must be a conscious act
    # that updates this number, not a silent loss of coverage.
    [ "$_stub_count" = "$A11Y_TEMPLATE_STUB_ROWS" ] || {
      printf 'SELFTEST FAIL: %s of %s fillable template rows carry a bracketed stub — a cell lost its token and is invisible to the placeholder check (or a row was added without one)\n' \
        "$_stub_count" "$A11Y_TEMPLATE_STUB_ROWS"; rc=1; }
    # Short-circuit on a failed COUNT LOCK specifically — not on any prior rc, which would silently skip
    # the per-cell probe whenever an unrelated earlier leg failed and cost a fix-and-rerun cycle. The DoS
    # this guards: the per-cell loop runs two full sed passes per bracketed line, so a PR-authored template
    # with ~10^5 rows would hang the job (measured quadratic: 450 rows = 8.6s; 100k rows now reds in ~1s).
    [ "$_stub_count" = "$A11Y_TEMPLATE_STUB_ROWS" ] || _stub_lines=""
    for _ln in $_stub_lines; do
      # Fill everything, then restore ONE line VERBATIM so exactly one stub survives. Composed from
      # head/sed/tail rather than `awk -v raw=…`: awk applies escape-sequence processing to a -v
      # assignment, so a template cell containing a backslash would be restored MANGLED and the leg would
      # then pass against a fixture the real template can never produce (a false green, review round 2).
      # `head -n 0` is ILLEGAL on BSD/macOS head (GNU accepts it), so a stub on line 1 would abort the
      # whole selftest under `set -e` with only `head: illegal line count -- 0` — green on CI, broken
      # locally. Guard the boundary rather than relying on the template's current shape.
      { [ "$_ln" -gt 1 ] && fill | head -n "$((_ln - 1))"
        sed -n "${_ln}p" "$_tmp/tpl-nobanner.md"
        fill | tail -n "+$((_ln + 1))"
      } > "$_tmp/A11Y-SIGNOFF.md"
      if run_a11y_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
        # printf, never echo (echo interprets backslash escapes in dash, /bin/sh on ubuntu-latest) AND
        # strip raw control bytes: printf alone still passes a literal ESC through, and GitHub Actions
        # renders ANSI SGR and honours \r — so template-controlled text could repaint a FAIL line to read
        # as a pass in the log. The exit code was never at risk; the human reading the log was.
        # The class is \000-\010\013-\037\177: 0-8, 11-31 and DEL. It MUST include \015 (CR) — the first
        # version of this line wrote \013\014\016-\037, which skipped CR and so left the exact repaint
        # this comment claims to close. Preserves \011 (tab) and \012 (LF), which are not in the class.
        printf 'SELFTEST FAIL: template line %s left as a stub was NOT detected — that cell token is inert: %s\n' \
          "$_ln" "$(sed -n "${_ln}p" "$_tmp/tpl-nobanner.md" | LC_ALL=C tr -d '\000-\010\013-\037\177')"; rc=1
      fi
    done
  fi
  # LEG 10 (THE `--` SENTINEL — this wrapper's half of it). The engine's first-assignment-wins rule can only
  # defend an argument THIS FILE SETS, and it does not set --stub-pattern. Measured on the true production
  # path before the sentinel: `sh conformance/a11y-obligation.sh` FAILed and the same command with
  # `--stub-pattern '\[zzz'` appended PASSed — Signal 2 switched off from the command line. The fix is half
  # here (the `--` that closes run_a11y_obligation's own definition) and half in the engine, so the proof
  # must live HERE: an engine-only leg cannot see this file forgetting its sentinel.
  # THREE assertions, because "still FAILs" alone proves nothing if the decoy was inert:
  #  (i)   liveness — the bare wrapper FAILs on this record (the DEFAULT threat vocabulary catches it, and
  #        the default is what governs here precisely because this wrapper sets no --stub-pattern);
  #  (ii)  potency  — the decoy pattern really would flip it, shown against the engine with NO sentinel;
  #  (iii) the sentinel — the same decoy appended to the WRAPPER is ignored, so the verdict is unchanged.
  # The fixture is derived from $OBL_MIN_SUBSTANCE_LINES (the sourced engine's constant), never hardcoded,
  # so a retune of the floor moves it instead of invalidating it.
  printf 'src/components/Nav.tsx\n' > "$_tmp/changed"
  { echo '# A11y Sign-off'
    echo '| Summary  | [summary] |'
    echo '| Threat   | [threat] |'
    echo '| Boundary | [boundary 1] |'
    _i=5; while [ "$_i" -le "$OBL_MIN_SUBSTANCE_LINES" ]; do echo "line $_i"; _i=$((_i+1)); done; } > "$_tmp/A11Y-SIGNOFF.md"
  _noop='\[zzz-no-such-stub-token'
  if run_a11y_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: an A11Y-SIGNOFF left as template stubs PASSed the bare wrapper — the sentinel leg below would be vacuous"; rc=1
  fi
  if ! obligation_gate --name t --surface-globs '*.tsx' --record A11Y-SIGNOFF.md --template-marker T \
       --stub-pattern "$_noop" --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: the decoy --stub-pattern does not disable Signal 2 for this record — the sentinel leg below would be vacuous"; rc=1
  fi
  _msg="$(run_a11y_obligation --stub-pattern "$_noop" --changed "$_tmp/changed" --root "$_tmp" 2>&1 || true)"
  case "$_msg" in
    *"PASS:"*) echo "SELFTEST FAIL: a caller-appended --stub-pattern disabled Signal 2 through this wrapper — its obligation_gate call is missing the '--' sentinel: $_msg"; rc=1 ;;
  esac
  # …and the wrapper's OWN definition still governs everything else on that same run: its record name and
  # its template marker must still be the ones the author is pointed at.
  case "$_msg" in
    *"A11Y-SIGNOFF.md"*"templates/A11Y-SIGNOFF-TEMPLATE.md"*) ;;
    *) echo "SELFTEST FAIL: the wrapper's own record/template-marker did not survive the sentinel — it said: $_msg"; rc=1 ;;
  esac
  # LEG 11 (EXCLUSION COVERAGE, OBLIGATION-CONFIG-TEMPLATE-EXT): every exclusion glob must be load-bearing,
  # and every one of them must be provably ON the surface it is excusing — otherwise an "N/A" here is green
  # for free because the probe never matched anything. So each glob gets a PAIR:
  #   (i)  through the wrapper (its exclusion list in force)          -> N/A
  #   (ii) straight to the engine with NO exclusion list at all       -> FAIL
  # (ii) is the load-bearing negative the whole leg rests on: delete A11Y_EXCLUDE_GLOBS from the wrapper's
  # gate call and every (i) reds; delete an entry and its own (i) reds; add an entry that is not on the
  # surface and its (ii) reds.
  # Probes are DERIVED from $A11Y_EXCLUDE_GLOBS, never hand-listed, exactly as LEG 5's are — with the same
  # honest limit: a probe derived from a glob always matches that glob, so a MISTYPED exclusion
  # self-validates on (i). What catches a typo is (ii) — a mistyped exclusion usually stops naming a real
  # extension and its probe then falls off the surface — and the count lock catches a silent addition.
  # Runs last and clears the record first: legs 6-10 leave a filled A11Y-SIGNOFF.md behind, and with a
  # record present every leg here would pass whether the exclusions worked or not.
  rm -f "$_tmp/A11Y-SIGNOFF.md"
  _ex_covered=0; _ex_count=0
  printf '%s\n' "$A11Y_EXCLUDE_GLOBS" | tr '|' '\n' > "$_tmp/exglobs"
  while IFS= read -r _g; do
    [ -n "$_g" ] || continue
    _ex_count=$((_ex_count + 1))
    # SHAPE — THE ASSERTION THAT ACTUALLY CONFINES THE OFF-SWITCH, and the reason it exists is that
    # everything else in this leg proves an exclusion is LIVE and ON the surface, never that it is NARROW.
    # The check header used to credit the ENGINE's refusal for that narrowness. It does not provide it: the
    # engine's universal test is `*[!*?]*` -> not universal, so ANY glob naming a single character escapes
    # it. MEASURED on the shipped check before this rule, with the count lock held at 12 — substituting
    # `*/pages/*.tsx` or `*/views/*.vue` for a real entry passed ALL 13 LEGS GREEN while deleting Next.js
    # `pages/` and Vue `views/` from the a11y surface (true production path, `src/pages/Checkout.tsx`:
    # "N/A: no a11y surface touched" where the shipped list correctly FAILs). Nothing saw it: LEG 12's
    # fixtures are `.j2`/`.erb`/`.tpl` only, and this leg's derived probes are `<dir>/probe.q` and
    # `s/probe.<ext>`, so a DIRECTORY-CROSS-EXTENSION exclusion misses both. A shape rule stated only in
    # prose is a rule the selftest cannot enforce — this is that prose turned into an assertion.
    # DERIVED FROM THE STRING, never a deny-list of known-bad globs, so it scales to entries nobody has
    # thought of yet. Exactly two admissible shapes:
    #  (1) a COMPOUND SUFFIX — begins `*.`, carries a second `.`, and contains NO `/` and no second `*`.
    #      The `/` bar is what kills `*/pages/*.tsx` and `*/views/*.vue`; the second-`*` bar is what kills
    #      `*.*.j2` and `*.conf.*`, each of which would re-open a whole extension across every inner name.
    #  (2) the two `_`-prefixed Helm partial forms, written out literally because there are exactly two.
    # One rule refuses `*/pages/*.tsx`, `*/views/*.vue`, `*[!q]*`, `[a-z]*`, `*.css` and `*.j2`. VERIFIED
    # one mutant at a time against the full selftest: each substituted for a real entry took the suite to
    # rc=1 with THIS assertion's message naming the offending glob (the last four also red other legs —
    # that is why they were survivable before; the first two red nothing else, which is why they were not).
    # Does NOT `continue`: the derived probe below is still worth running, and skipping it would
    # additionally red the family-completeness lock and blame the wrong thing.
    case "$_g" in
      '*.'*'.'*)
        case "$_g" in
          */*|*'*'*'*'*) _shape_ok=0 ;;
          *) _shape_ok=1 ;;
        esac ;;
      'templates/_*.'*|'*/templates/_*.'*) _shape_ok=1 ;;
      *) _shape_ok=0 ;;
    esac
    [ "$_shape_ok" = 1 ] || {
      printf 'SELFTEST FAIL: exclusion %s is neither a compound suffix (*.<inner>.<ext>, containing no / and no second *) nor one of the two _-prefixed Helm partials — an exclusion of any other shape can delete an entire surface, and the engine only refuses one matching EVERY path\n' "$_g"; rc=1; }
    # Derivation: strip a leading `*/` (it stands for "some parent directory"), give a bare extension glob
    # a directory so it cannot double-match a surface DIRECTORY glob, then substitute the single remaining
    # `*` with a filler. A shape carrying more than one inner `*` leaves a `*` in the probe and is caught
    # by the guard below rather than shipping unproven.
    _pfx=""; _rest="$_g"
    case "$_rest" in
      '*/'*) _pfx="a/"; _rest="${_rest#*/}" ;;
    esac
    case "$_rest" in
      */*) ;;
      *) _pfx="${_pfx}s/" ;;
    esac
    case "$_rest" in
      *'*'*) _p="$_pfx${_rest%%\**}probe${_rest#*\*}" ;;
      *) _p="$_pfx$_rest" ;;
    esac
    case "$_p" in
      ''|*'*'*)
        printf 'SELFTEST FAIL: unrecognised exclusion-glob shape %s — the coverage leg cannot derive a probe for it, so it would ship UNPROVEN\n' "$_g"; rc=1
        continue ;;
    esac
    printf '%s\n' "$_p" > "$_tmp/changed"
    if ! run_a11y_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
      printf 'SELFTEST FAIL: exclusion dead — config-template probe %s (from %s) still demanded a WCAG sign-off\n' "$_p" "$_g"; rc=1
    fi
    if obligation_gate --name a11y --surface-globs "$A11Y_SURFACE_GLOBS" --record A11Y-SIGNOFF.md \
         --template-marker T --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
      printf 'SELFTEST FAIL: probe %s (from %s) is not on the a11y surface at all — its N/A above proves nothing about the exclusion\n' "$_p" "$_g"; rc=1
    fi
    _ex_covered=$((_ex_covered + 1))
  done < "$_tmp/exglobs"
  [ "$_ex_covered" = "$_ex_count" ] || { printf 'SELFTEST FAIL: only %s of %s exclusion globs were probed\n' "$_ex_covered" "$_ex_count"; rc=1; }
  # EXACT count lock, for the same reason LEG 5 carries one — but note the asymmetry: for the SURFACE a
  # deletion is the dangerous direction, for an EXCLUSION it is an ADDITION. An added exclusion is an added
  # off-switch, so it must be a conscious act that updates this number.
  [ "$_ex_count" = "$A11Y_EXCLUDE_GLOB_COUNT" ] || {
    printf 'SELFTEST FAIL: %s exclusion globs parsed, expected exactly %s — an exclusion was added or removed without updating A11Y_EXCLUDE_GLOB_COUNT\n' \
      "$_ex_count" "$A11Y_EXCLUDE_GLOB_COUNT"; rc=1; }
  # LEG 12 (THE EXCLUSION MUST NOT BE WIDENABLE INTO A SURFACE OFF-SWITCH). Every path below is a REAL
  # user-facing surface that must still demand a sign-off, in TWO groups with two different jobs:
  #  (a) the FIRST SIX carry an extension the exclusion list excuses somewhere. They are what forces the
  #      entries to stay compound suffixes and `_`-prefixed partials: rewrite any entry as the bare
  #      extension (`*.j2`, `*.erb`, `*.tpl`) and this leg reds. The fifth and sixth are deliberate NEAR
  #      MISSES — `app/conf.j2` has `conf.j2` but not `.conf.j2`, and `templates/helpers.tpl` is a Helm
  #      template WITHOUT the partial underscore — so the exclusions are proven anchored rather than
  #      merely substring-ish.
  #  (b) the LAST TWO carry NO excused extension at all, and that is the point. LEG 11's shape rule bounds
  #      an exclusion's blast radius but CANNOT tell a config suffix from a UI CONVENTION (see the bullet
  #      at A11Y_EXCLUDE_GLOBS): measured with the count lock held at 12, `*.component.html` and
  #      `*.module.css` each survived all 13 legs while deleting Angular templates / CSS Modules from the
  #      surface, and `src/app/hero/hero.component.html` read "N/A: no a11y surface touched" on the true
  #      production path. These two fixtures are the behavioural half of that judgment; each is FAIL under
  #      the shipped list and N/A under its own mutant, so both directions are load-bearing.
  # THIS LEG IS EXACTLY AS STRONG AS THE LIST BELOW AND NO STRONGER. Re-measured AFTER (b) landed:
  # `*.module.scss`, `*.page.tsx`, `*.view.hbs` and `*.html.haml` are the same class and STILL survive all
  # 13 legs. Chasing the class with one fixture per convention is unbounded, so REVIEW is the backstop for
  # the rest — said here rather than implied, because a leg that READS as covering a class while covering
  # eight cases is the same defect this check's SCOPE paragraph forbids.
  for _real in 'app/templates/index.j2' 'templates/page.j2' 'mailers/welcome.html.erb' \
               'themes/main.tpl' 'app/conf.j2' 'templates/helpers.tpl' \
               'src/app/hero/hero.component.html' 'src/components/Nav.module.css'; do
    printf '%s\n' "$_real" > "$_tmp/changed"
    if run_a11y_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
      printf 'SELFTEST FAIL: real user-facing surface %s stopped demanding a WCAG sign-off — an exclusion has widened into a surface off-switch\n' "$_real"; rc=1
    fi
  done
  # LEG 13 (THE `--` SENTINEL for --exclude-globs — this wrapper's half). The engine's first-assignment-wins
  # rule can only defend an argument a wrapper SETS; this one it does set, but the sentinel is what defends
  # the OTHER two wrappers, which set no exclusion list at all. Proved here because an engine-only leg
  # cannot see this file forgetting its `--`. Three assertions, so "still FAILs" cannot be green vacuously:
  #  (i)   liveness — the bare wrapper FAILs on this UI path with no record;
  #  (ii)  potency  — the decoy exclusion really would flip it, shown against the engine with NO sentinel;
  #  (iii) the sentinel — the same decoy appended to the WRAPPER is ignored and the verdict is unchanged.
  printf 'src/components/Nav.tsx\n' > "$_tmp/changed"
  if run_a11y_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: a UI path with no A11Y-SIGNOFF PASSed the bare wrapper — the exclusion-sentinel leg below would be vacuous"; rc=1
  fi
  if ! obligation_gate --name a11y --surface-globs "$A11Y_SURFACE_GLOBS" --exclude-globs '*Nav*' \
       --record A11Y-SIGNOFF.md --template-marker T --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: the decoy --exclude-globs does not itself suppress this path — the sentinel leg below would be vacuous"; rc=1
  fi
  _msg="$(run_a11y_obligation --exclude-globs '*Nav*' --changed "$_tmp/changed" --root "$_tmp" 2>&1 || true)"
  case "$_msg" in
    *"N/A:"*|*"PASS:"*) echo "SELFTEST FAIL: a caller-appended --exclude-globs switched the a11y surface off through this wrapper — its obligation_gate call is missing the '--' sentinel: $_msg"; rc=1 ;;
  esac
  unset KIT_OBL_TEST   # defence in depth: if this file is ever SOURCED rather than run, the fixture-flag
                       # escape hatch must not survive into the caller's environment.
  [ "$rc" = 0 ] && printf 'OK (a11y-obligation: 13 legs; every surface glob derived+probed AND corpus-locked against %s real-world UI paths so a mistyped glob matching nothing real reds, every bracketed template stub cell probed and count-locked at %s rows, every one of the %s config-template exclusions shape-asserted as a compound suffix or a Helm partial and derived+probed with its load-bearing negative, real view templates on the same extensions AND the two canonical UI compound-suffix conventions still gated)\n' \
    "$A11Y_CORPUS_PATH_COUNT" "$A11Y_TEMPLATE_STUB_ROWS" "$A11Y_EXCLUDE_GLOB_COUNT"
  return $rc
}

# dispatch — BELOW the selftest() definition so the function is defined before it is called
# (POSIX sh executes top-to-bottom; a forward reference to selftest fails with 'command not found').
# The non-vacuity marker is the selftest() line above, so the check-logic region (run_a11y_obligation)
# is still mutated; this dispatch sits after the marker and is emitted verbatim by the sweep.
if [ "${1:-}" = "--selftest" ]; then selftest; exit $?; fi
run_a11y_obligation "$@"; exit $?
