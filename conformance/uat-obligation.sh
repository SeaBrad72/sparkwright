#!/bin/sh
# Why this gate: sparkwright explain uat
# uat-obligation.sh — HITL obligation: a change-set touching a user-facing TASTE surface (the
# components/views/pages/screens/ui/frontend/styles directories, at repo ROOT or nested, plus the UI and
# view-template MARKUP EXTENSIONS enumerated in UAT_SURFACE_GLOBS below — that variable is the single
# source of truth, and the selftest derives its probes FROM it) MUST carry a filled UAT-SIGNOFF record,
# else FAIL. Diff-level, riding the shipped obligation engine (same as threat-obligation.sh); the
# HITL-3 board Done-edge flag is the discipline layer — THIS gate is the hard backstop.
#
# RENAMES ARE FOLLOWED (H1): the engine's derivation passes `--no-renames`, so a taste-surface file MOVED
# out of a UI directory still triggers on its SOURCE path. Before that, git's default rename detection
# emitted only the DESTINATION, so a `git mv` in the same PR silently derived N/A on this gate too.
#
# SCOPE (honest ceiling): green = a UAT-SIGNOFF record EXISTS and is FILLED for a triggered change —
# NOT that a human actually engaged their taste / exercised the surface, nor that the acceptance
# judgment is sound (UAT sign-off + review backstop that), nor that the record is FRESH for this change
# (one committed root UAT-SIGNOFF.md satisfies every later UI PR; the record carries a Date and a
# Feature/story link so a reviewer can see staleness, but this gate cannot). N-A = the change-set touches
# no taste surface (trigger-absence), exactly like threat-obligation.sh. CONSERVATIVE by design:
# clear-UI globs ONLY — ambiguous/non-UI files are N-A and false-negatives are accepted (the only
# 'uncertain' source is a derive-failure, which fails CLOSED). Better to miss a borderline surface than
# to nag on prose. "Filled" is coarse but no longer trivially faked: the engine rejects the template
# banner, its stub tokens, AND any record below its minimum-substance floor (OBL_MIN_SUBSTANCE_LINES),
# so `touch UAT-SIGNOFF.md` no longer satisfies it. Eight lines of prose under a heading still passes —
# the floor measures STRUCTURE, never QUALITY.
#
# SURFACE vs a11y-obligation.sh: the SAME clear-UI directory set and the same view-template extensions,
# because a11y and taste are two DIFFERENT judgments about the SAME user-facing surface (a WCAG verdict
# signed by the designer/a11y owner vs. an acceptance verdict signed by QA/PO). ONE deliberate
# divergence: a11y additionally lists *.html/*.htm, this check does not. See UAT_SURFACE_GLOBS for why,
# and for the cost of keeping it.
#
# Usage:
#   sh conformance/uat-obligation.sh                 (derive change-set: merge-base HEAD origin/main)
#   sh conformance/uat-obligation.sh --changed FILE  (fixture path list; honored ONLY under
#                                                      --selftest / the KIT_OBL_TEST env flag — ignored in production)
#   sh conformance/uat-obligation.sh --selftest
set -eu
# shellcheck disable=SC1007 # `CDPATH= cd` is the correct idiom: it clears CDPATH for this one command so
# a user's CDPATH cannot redirect the cd; the empty assignment is intentional, not a mistyped value.
DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# Tell the engine it is being SOURCED (not executed directly), so its --selftest dispatch stays inert
# here: without this, `sh uat-obligation.sh --selftest` would run the LIB's selftest (the sourced lib
# sees $1=--selftest) instead of this obligation's 9-leg selftest. Value is 'yes' (NOT a numeric flag) so
# the non-vacuity sweep — which neuters a pre-marker numeric-flag assignment — cannot flip it; this line
# carries no mutable idiom, so run_uat_obligation stays the (idiomless) mutation region and this file's
# verdict is unchanged. A $0-basename guard would not survive the sweep renaming the lib's copy to .nv-mut-*.
OBL_LIB_SOURCED=yes
. "$DIR/conformance/obligation-lib.sh"

# The obligation: clear-UI taste-surface globs + UAT-SIGNOFF record. THIS STRING IS THE SINGLE SOURCE OF
# TRUTH: the coverage leg DERIVES one probe path per glob from it, so adding a glob automatically adds its
# proof and a glob written in an unprobeable SHAPE is itself a failure (a11y-obligation.sh's LEG 5
# pattern, ported here because this check gained 32 globs at once and a hand-listed probe set cannot keep
# up with that). What derivation CANNOT do, stated rather than implied: a probe derived FROM a glob always
# matches that glob, so a MISTYPED glob (`*.sccs`, `*/screen/*`) self-validates and the leg stays green.
# Deletion is caught by the exact count lock; a typo is caught by nothing here — review is the backstop.
#
# EACH DIRECTORY APPEARS TWICE — `x/*` for a repo-root directory and `*/x/*` for a nested one, because
# `*/x/*` requires a leading path segment (UAT-ROOT-DIR-GLOB). The root form was missing until now, so
# `components/Button.ts` — the Next.js and Vite DEFAULT layout — was N/A, masked only by the `.tsx`/`.css`
# EXTENSION globs catching the common cases. LEG 7 holds all five measured paths.
#
# THE BARE `*/templates/*` GLOB IS RETIRED, replaced by view-template MARKUP EXTENSIONS
# (OBLIGATION-TEMPLATES-GLOB) — the same repair a11y-obligation.sh already shipped, and for the same
# reason: a directory named `templates/` is not a UI signal (Helm, CloudFormation and cookiecutter all
# use it), and THIS REPO's 14 `profiles/*/deploy/helm/templates/*.yaml` manifests were red-ing, demanding
# a QA acceptance sign-off for a Kubernetes Deployment. MEASURED on a 243,157-path corpus of real project
# trees: the swap DROPS 759 paths from the surface (317 `.md`, 108 `.yaml`, 118 `.js`, 105 `.ts` — almost
# all of them this kit's own `templates/*.md` document set as adopters carry it) and ADDS 4. It is a
# near-pure false-positive removal on real trees, not a trade.
# WHAT THE "ADDS 4" ACTUALLY ARE, enumerated rather than left as a number (re-measured on this build):
# THREE are mypyc's `lib-rt/module_shim.tmpl` / `module_shim_no_gil_multiphase.tmpl` — a BARE `.tmpl`
# that is neither a view template nor a config template but C SOURCE for the mypyc runtime, vendored
# under `.venv/`. That class is the real cost of listing `.tmpl`, and it is not reachable by a compound-
# suffix exclusion (there is no inner extension to key on). The FOURTH is
# `@vercel/analytics/dist/astro/index.astro` — a genuine Astro component, i.e. a CORRECT add, not a cost.
# So the honest ledger is: 759 false positives removed, 3 vendored C-source shims gained, 1 real UI file
# gained. All four sit under `node_modules/`/`.venv/`, which a diff-relative gate rarely sees at all.
# HONEST TRADE ANYWAY (do not restate this as a strict win — an earlier a11y draft did and review
# falsified it): a view template whose extension is NOT listed is now N/A where the bare directory glob
# caught it. `.mako` is the measured instance — 12 in that corpus — and `.vm`, `.st` and `.dust` are the
# same class. Accepted under the conservative posture, named here rather than discovered later.
#
# THE `*.html`/`*.htm` DIVERGENCE FROM a11y IS DELIBERATE AND IS KEPT: semantic HTML is a first-class
# ACCESSIBILITY surface, whereas a raw `.html` edit is not necessarily a change of TASTE. a11y-obligation
# .sh lists both extensions and states the same divergence from its side.
# THE COST OF KEEPING IT, disclosed because it is a REGRESSION this change introduces rather than an
# inherited limitation: a Django/Flask/Rails view template at `app/templates/index.html` red-ed under the
# bare `*/templates/*` glob and is now N/A for THIS gate. It is still gated for a11y (which lists
# `*.html`), so the file does not escape the HITL ceremonies altogether — it escapes the TASTE one. The
# corpus measured 0 instances of the class, so there is no evidence to size it with; it is a reasoned
# consequence, and the narrower repair (`templates/*.html` + `*/templates/*.html`, an html file UNDER a
# templates dir, which is unambiguously a view template rather than a raw html edit) is left for the
# owner to rule on rather than taken unilaterally — it would add a glob shape neither sibling check has.
#
# NO EXCLUSION LIST (`--exclude-globs`), and that is a decision with evidence, not an oversight.
# a11y-obligation.sh carries a 12-entry exclusion list because markup EXTENSIONS also match CONFIG
# templates (Ansible `nginx.conf.j2`, Chef `app.conf.erb`, Helm's own `templates/_helpers.tpl`). This
# check inherits that false-positive class. It is NOT excluded here, for three measured/structural
# reasons: (a) that class — precisely, the COMPOUND-SUFFIX config templates a11y's list enumerates
# (`*.conf.j2`, `*.yml.erb`, `*.sh.tpl`, Helm's `templates/_*.tpl`, …) — measured ZERO hits in the
# 243,157-path corpus when the 12 exclusion globs were run over it directly, so there is no local
# evidence to size the benefit; (b) every such path that this repo or that corpus actually contains ALREADY red-ed
# under the retired `*/templates/*` glob, so this change introduces no regression in that direction —
# `roles/nginx/templates/nginx.conf.j2` was red before and is red after; and (c) an exclusion list is an
# OFF-SWITCH, and shipping one here would mean either duplicating a11y's 12 entries AND its ~60-line
# shape+coverage proof into a second file that can then drift, or shipping the off-switch UNPROVEN. The
# right shape is ONE shared exclusion constant both checks read, which needs a file outside this task's
# set. Boarded rather than bodged. THE RESIDUAL IS TWO CLASSES, and only the second was measured to
# exist: (1) a config template on a markup extension OUTSIDE a `templates/` dir (`app.conf.erb` at a
# project root) — new, reasoned, and measured at ZERO instances on the corpus, so it is a class rather
# than a case; and (2) a BARE `.tmpl`/`.tpl` that is neither a view nor a config template — mypyc's
# `lib-rt/module_shim*.tmpl` C-source shims, 3 measured instances, and the only one of the two that
# actually appeared. Class (2) is unreachable by a compound-suffix exclusion by construction (no inner
# extension to key on), so even the shared constant above would not close it.
UAT_SURFACE_GLOBS='components/*|*/components/*|views/*|*/views/*|pages/*|*/pages/*|screens/*|*/screens/*|ui/*|*/ui/*|frontend/*|*/frontend/*|styles/*|*/styles/*|*.tsx|*.jsx|*.vue|*.svelte|*.css|*.scss|*.less|*.j2|*.jinja|*.jinja2|*.erb|*.hbs|*.handlebars|*.ejs|*.twig|*.pug|*.haml|*.slim|*.liquid|*.mustache|*.astro|*.njk|*.tmpl|*.gohtml|*.templ|*.tpl|*.cshtml|*.razor|*.jsp|*.jspx|*.ftl|*.heex|*.eex'

# The `--` before "$@" is LOAD-BEARING, not decoration: it closes this check's own definition, and the
# engine refuses the six gate-defining arguments after it. Without it a caller could append
# `--stub-pattern …` and switch Signal 2 off from the command line — the engine's first-assignment-wins
# rule cannot defend an argument this file never sets (measured before the fix: the bare command FAILed,
# the same command with `--stub-pattern '\[zzz'` PASSed). LEG 6 below is the proof; delete the `--` and it
# reds. The fixture flags in "$@" (--changed/--root/--force-uncertain) still parse — the sentinel fences
# only the six.
run_uat_obligation() {   # args: forwarded (--changed FILE | none)
  obligation_gate \
    --name "uat" \
    --surface-globs "$UAT_SURFACE_GLOBS" \
    --record "UAT-SIGNOFF.md" \
    --template-marker "templates/UAT-SIGNOFF-TEMPLATE.md" \
    -- \
    "$@"
}

# ---- selftest() marker: the non-vacuity sweep mutates ONLY lines ABOVE here ----
selftest() {
  _tmp="$(mktemp -d "${TMPDIR:-/tmp}/uat-st.XXXXXX")"; trap 'rm -rf "$_tmp"' EXIT INT TERM
  export KIT_OBL_TEST=1   # honor the fixture flags (--changed/--root/--force-uncertain) only in-test (M1)
  rc=0
  # LEG 1 (liveness/negative): taste surface touched, NO record -> RED
  printf 'src/components/Login.tsx\n' > "$_tmp/changed"
  if run_uat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: taste surface with no UAT-SIGNOFF did not FAIL"; rc=1
  fi
  # LEG 2 (positive): no taste surface -> green (N-A)
  printf 'docs/README.md\n' > "$_tmp/changed"
  if ! run_uat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: non-UI change did not pass (N-A)"; rc=1
  fi
  # LEG 3 (fail-safe, simulated): --force-uncertain simulates the uncertain band (the conservative posture
  # has no per-file uncertain heuristic; the REAL uncertain trigger is a derive-failure — LEG 4). NO record -> RED
  printf 'config/settings.yaml\n' > "$_tmp/changed"
  if run_uat_obligation --changed "$_tmp/changed" --root "$_tmp" --force-uncertain >/dev/null 2>&1; then
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
  if ( cd "$_dr" && run_uat_obligation --root "$_dr" ) >/dev/null 2>&1; then
    echo "SELFTEST FAIL: underivable change-set (no resolvable base) did not FAIL (derive fail-open)"; rc=1
  fi
  # LEG 5 (positive, false-positive guard): taste surface touched, a GENUINELY-FILLED UAT-SIGNOFF whose
  # banner is deleted and whose stubs are all substituted -> must be treated as FILLED and PASS. The
  # template's own '> **Template.**' banner is absent and no unfilled bracket stub remains, so the
  # engine's obl_is_placeholder must NOT flag it. This kills a regression that would wrongly FAIL a
  # filled record.
  # REBUILT FROM THE SHIPPED TEMPLATE (OBLIGATION-RECORD-FLOOR follow-up). The old fixture was
  # hand-written and — measured — exactly 12 non-blank lines against a floor of 8: the SMALLEST margin in
  # the suite, and a coincidence rather than a coupling, because the number came from a human copying the
  # template's shape rather than from the template. Deriving it means this leg reds the day
  # UAT-SIGNOFF-TEMPLATE.md is trimmed below the engine's floor or adopts a stub token the engine cannot
  # see — the gap that let an inert `[describe:` stub ship green through HITL-4's first review round.
  # A hand-written fixture cannot do that no matter how carefully it is padded.
  printf 'src/components/Login.tsx\n' > "$_tmp/changed"
  _tpl="$DIR/templates/UAT-SIGNOFF-TEMPLATE.md"
  if [ ! -f "$_tpl" ] || [ ! -s "$_tpl" ]; then
    echo "SELFTEST FAIL: templates/UAT-SIGNOFF-TEMPLATE.md is missing or empty — the filled-record leg cannot run"; rc=1
  else
    # fill_uat(): the shipped template, guidance banner deleted and every bracketed stub substituted.
    # ONE GENERIC bracket pattern, NOT the engine's own stub vocabulary — an oracle that recognises only
    # the tokens it already knows cannot detect a template that adopts a NEW one (a11y LEG 6's lesson).
    fill_uat() {
      grep -v '^> \*\*Template\.\*\*' "$_tpl" \
        | sed 's/\[[^]]*\]/accepted after a live demo walkthrough, Jane Roe QA 2026-07-24/g'
    }
    fill_uat > "$_tmp/UAT-SIGNOFF.md"
    if ! run_uat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
      echo "SELFTEST FAIL: the SHIPPED UAT template, banner-stripped and fully filled, was wrongly FAILed as a placeholder"; rc=1
    fi
  fi
  # LEG 6 (THE `--` SENTINEL — this wrapper's half of it). The engine's first-assignment-wins rule can only
  # defend an argument THIS FILE SETS, and it does not set --stub-pattern. Measured on the true production
  # path before the sentinel: `sh conformance/uat-obligation.sh` FAILed and the same command with
  # `--stub-pattern '\[zzz'` appended PASSed — Signal 2 switched off from the command line. The fix is half
  # here (the `--` that closes run_uat_obligation's own definition) and half in the engine, so the proof
  # must live HERE: an engine-only leg cannot see this file forgetting its sentinel.
  # THREE assertions, because "still FAILs" alone proves nothing if the decoy was inert:
  #  (i)   liveness — the bare wrapper FAILs on this record (the DEFAULT threat vocabulary catches it, and
  #        the default is what governs here precisely because this wrapper sets no --stub-pattern);
  #  (ii)  potency  — the decoy pattern really would flip it, shown against the engine with NO sentinel;
  #  (iii) the sentinel — the same decoy appended to the WRAPPER is ignored, so the verdict is unchanged.
  # The fixture is derived from $OBL_MIN_SUBSTANCE_LINES (the sourced engine's constant), never hardcoded,
  # so a retune of the floor moves it instead of invalidating it.
  printf 'src/components/Login.tsx\n' > "$_tmp/changed"
  { echo '# UAT Sign-off'
    echo '| Summary  | [summary] |'
    echo '| Threat   | [threat] |'
    echo '| Boundary | [boundary 1] |'
    _i=5; while [ "$_i" -le "$OBL_MIN_SUBSTANCE_LINES" ]; do echo "line $_i"; _i=$((_i+1)); done; } > "$_tmp/UAT-SIGNOFF.md"
  _noop='\[zzz-no-such-stub-token'
  if run_uat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: a UAT-SIGNOFF left as template stubs PASSed the bare wrapper — the sentinel leg below would be vacuous"; rc=1
  fi
  if ! obligation_gate --name t --surface-globs '*.tsx' --record UAT-SIGNOFF.md --template-marker T \
       --stub-pattern "$_noop" --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: the decoy --stub-pattern does not disable Signal 2 for this record — the sentinel leg below would be vacuous"; rc=1
  fi
  _msg="$(run_uat_obligation --stub-pattern "$_noop" --changed "$_tmp/changed" --root "$_tmp" 2>&1 || true)"
  case "$_msg" in
    *"PASS:"*) echo "SELFTEST FAIL: a caller-appended --stub-pattern disabled Signal 2 through this wrapper — its obligation_gate call is missing the '--' sentinel: $_msg"; rc=1 ;;
  esac
  # …and the wrapper's OWN definition still governs everything else on that same run: its record name and
  # its template marker must still be the ones the author is pointed at.
  case "$_msg" in
    *"UAT-SIGNOFF.md"*"templates/UAT-SIGNOFF-TEMPLATE.md"*) ;;
    *) echo "SELFTEST FAIL: the wrapper's own record/template-marker did not survive the sentinel — it said: $_msg"; rc=1 ;;
  esac
  # ---------------------------------------------------------------------------------------------
  # LEGS 7-9 ALL RUN WITH THE RECORD ABSENT. Legs 5 and 6 leave a UAT-SIGNOFF.md behind in $_tmp, so this
  # line makes what follows independent of whatever the previous leg happened to write.
  # WHAT IT ACTUALLY BUYS, built rather than asserted (an earlier draft of this comment claimed it stops
  # leg 9 going "green for free" and leg 7 being inverted; the mutants falsify that):
  #  - delete this line ALONE and the selftest still prints OK — leg 6 leaves a STUB record, which a
  #    triggering path still FAILs on, so legs 7-9 keep discriminating. The line was UNASSERTED.
  #  - replace it with a genuinely FILLED record — the shape a future edit to leg 6 could produce — and
  #    the selftest goes LOUD RED (all five leg-7 root-dir paths report "did not demand"), never silently
  #    green.
  # So it prevents a SPURIOUS RED, not a silent green, and it is cheap determinism rather than a control.
  # The assertion below is what makes the line itself asserted: remove the `rm` and this reds immediately,
  # which is the property the prose alone was standing in for.
  rm -f "$_tmp/UAT-SIGNOFF.md"
  [ ! -f "$_tmp/UAT-SIGNOFF.md" ] || { echo "SELFTEST FAIL: legs 7-9 must run with the record absent"; rc=1; }
  # LEG 7 (UAT-ROOT-DIR-GLOB): a REPO-ROOT UI directory. The shipped surface carried only the nested
  # `*/components/*` form, and `*/x/*` requires a leading path segment — so `components/Button.ts` at the
  # repo root was N/A. That is the Next.js and Vite DEFAULT layout, which made HITL-2 and HITL-3 — two of
  # the six RC-lock ceremonies — effectively unenforced for a frontend-first adopter. It was masked only
  # because `.tsx`/`.css` are caught by EXTENSION globs; every one of the five paths below carries an
  # extension this surface does not list, so each isolates the directory glob and nothing else.
  # (a11y-obligation.sh already carried both forms and documents the doubling; this is uat catching up.)
  for _p in components/Button.ts ui/icon.svg views/index.php frontend/main.ts styles/theme.styl; do
    printf '%s\n' "$_p" > "$_tmp/changed"
    if run_uat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
      printf 'SELFTEST FAIL: repo-root UI path %s did not demand a UAT sign-off — only the nested */x/* form is present\n' "$_p"; rc=1
    fi
  done
  # LEG 8 (GLOB COVERAGE): EVERY surface glob must be load-bearing. Without it, only the globs a fixture
  # happens to exercise are proven and the rest can be DELETED while the selftest still prints OK — a
  # mutation probe on a11y measured 15 of 16 globs unproven before its equivalent leg existed, and this
  # check just took on 32 more. Each directory glob is probed with the inert extension '.q' so it cannot
  # double-match an extension glob, and each extension glob with a path in no matching directory.
  # SPLIT VIA `tr` + `IFS= read`, NOT a save/restore of the global IFS: semgrep's
  # bash.lang.security.ifs-tampering flags the save/restore form, and this fleet's SAST gate reads these
  # files. Reading from a FILE (not a pipe) keeps the loop in this shell, so `rc` survives it.
  UAT_SURFACE_GLOB_COUNT=47     # alternations in UAT_SURFACE_GLOBS (EXTERNALLY DECLARED, not computed)
  _covered=0; _globcount=0
  printf '%s\n' "$UAT_SURFACE_GLOBS" | tr "$OBL_GLOB_SEP" '\n' > "$_tmp/globs"
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
      if run_uat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
        printf 'SELFTEST FAIL: surface glob dead — %s (probe %s) touched with no UAT-SIGNOFF did not FAIL\n' "$_g" "$_p"; rc=1
      fi
      _covered=$((_covered + 1))
    fi
  done < "$_tmp/globs"
  # Family-completeness: every glob got a probe. Guards the derivation itself going silently inert.
  [ "$_covered" = "$_globcount" ] || { printf 'SELFTEST FAIL: only %s of %s surface globs were probed\n' "$_covered" "$_globcount"; rc=1; }
  # EXACT count lock, not a floor. On a11y a floor (>= 20 against an actual 49) let 26 globs — the entire
  # view-template extension set — be deleted with the selftest still printing OK. Changing this surface
  # must update this number deliberately; a silent deletion reds here.
  [ "$_globcount" = "$UAT_SURFACE_GLOB_COUNT" ] || {
    printf 'SELFTEST FAIL: %s surface globs parsed, expected exactly %s — a glob was added or removed without updating UAT_SURFACE_GLOB_COUNT\n' \
      "$_globcount" "$UAT_SURFACE_GLOB_COUNT"; rc=1; }
  # LEG 9 (OBLIGATION-TEMPLATES-GLOB): a `templates/` DIRECTORY is not a UI signal. Helm, CloudFormation
  # and cookiecutter all use the name, and THIS REPO carries 14 such files
  # (profiles/*/deploy/helm/templates/{deployment,service}.yaml) which the bare `*/templates/*` glob
  # red-ed — demanding a QA acceptance sign-off for a Kubernetes Deployment manifest, a false positive
  # with no honest way to satisfy it. A gate that reds on compliant behaviour is a gate that gets deleted.
  # The manifests are ENUMERATED FROM THE LIVE TREE, not hand-listed: a hand-list would say nothing
  # about a profile added later (its manifest would simply never be probed), and this leg's whole claim
  # is about files that actually exist. The pairing with an EXTERNALLY DECLARED count is what keeps that
  # safe — a glob expanding to nothing would otherwise make the loop vacuous and the leg green for free.
  # FOUR-PART, because "the manifests are N/A" alone would also be satisfied by deleting the surface:
  #  (i)   every live manifest this tree carries                    -> N/A  (at whatever count it carries)
  #  (i-b) a canonical FIXTURE manifest set                         -> N/A  (tree-independent, always runs)
  #  (ii)  a REAL view template on a listed markup extension        -> RED  (the replacement is live)
  #  (iii) each (i-b) fixture against the RETIRED bare glob         -> RED  (the N/A is caused by THIS
  #        change, not by those paths never having been on the surface at all)
  #
  # THE COUNT LOCK IS A KIT-TREE PROPERTY AND ONLY A KIT-TREE PROPERTY (CP7R5-VERIFY-NONTS class). It
  # shipped unconditional and reddened all four artifact-gate variants: `scripts/incept.sh` PRUNES the
  # unselected stack profiles (its "prune unselected stack profiles" section), so the kit tree's 10
  # profiles / 14 manifests become ONE profile / 2 manifests on an incepted adopter tree. 14 was never a
  # property of the check — it is a property of the tree the check happened to be written on.
  # A `> 0` FLOOR IS ALSO WRONG, and this is measured rather than assumed: only 7 of the 10 profiles ship a
  # chart (dotnet, go, java-spring, kotlin, python, rust, typescript-node), so an adopter incepted on
  # data-engineering, ml or terraform carries ZERO manifests — legitimately. CI only ever incepts
  # typescript-node, so a floor would have shipped green here and reddened on a real adopter later, which is
  # this defect moved rather than fixed.
  # CLASSIFIED BY THE KIT-MARKER PAIR, NOT BY THE PROFILE SET, and the distinction is load-bearing. Keying on
  # "all 10 profiles present" is self-referential: REMOVING a profile is one of the two events the lock
  # exists to catch, and it would instead silence the lock by demoting the tree to "adopter". The marker pair
  # (docs/ROADMAP-KIT.md + .github/workflows/golden-path.yml, both `export-ignore`d, so an adopter export
  # strips both) is ORTHOGONAL to the profile set — the same un-spoofable classifier verify.sh's `--kitself`
  # and incept-first-run-green.sh key on. Fail-CLOSED toward running the lock: EITHER marker present == kit
  # tree, matching verify.sh's mixed-marker rule exactly.
  # WHY NOT `--kitself` ON THE WHOLE CHECK: that mechanism lives in verify.sh's `check()` and is per-CHECK —
  # it renders N-A and never runs the command at all, which would delete legs 1-8 from adopter-tree coverage
  # (the surface globs, both directory forms, the `--` sentinel, the fail-closed derive) to repair one leg.
  # It would also leave every DIRECT `sh conformance/uat-obligation.sh --selftest` — ci.yml's own obligation
  # job, non-vacuity.sh — still red, because those never pass through `check()`.
  # HONEST CEILING, stated rather than implied: on a pruned tree "the charts moved" is NOT detectable by
  # count, and nothing here pretends otherwise — part (i) simply asserts the claim over however many
  # manifests exist, and (i-b)/(iii) carry the leg's teeth. Chart relocation is a KIT-MAINTENANCE event and
  # the kit tree is where it is caught; the count lock below is unweakened there.
  UAT_HELM_MANIFEST_COUNT=14    # KIT TREE ONLY: profiles/*/deploy/helm/templates/*.yaml (declared, not counted)
  if [ -f "$DIR/docs/ROADMAP-KIT.md" ] || [ -f "$DIR/.github/workflows/golden-path.yml" ]; then
    _uat_tree=kit
  else
    _uat_tree=adopter
  fi
  _helm=0
  for _mf in "$DIR"/profiles/*/deploy/helm/templates/*.yaml; do
    [ -f "$_mf" ] || continue
    _helm=$((_helm + 1))
    printf '%s\n' "${_mf#"$DIR"/}" > "$_tmp/changed"
    if ! run_uat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
      printf 'SELFTEST FAIL: Helm manifest %s still demands a UAT sign-off — the bare */templates/* glob is back\n' "${_mf#"$DIR"/}"; rc=1
    fi
  done
  if [ "$_uat_tree" = kit ] && [ "$_helm" != "$UAT_HELM_MANIFEST_COUNT" ]; then
    printf 'SELFTEST FAIL: %s Helm manifests found under profiles/*/deploy/helm/templates/, expected exactly %s on the KIT tree — either the charts moved (making the N/A assertions above vacuous) or a profile was added/removed without updating UAT_HELM_MANIFEST_COUNT\n' \
      "$_helm" "$UAT_HELM_MANIFEST_COUNT"; rc=1
  fi
  # (i-b) THE TREE-INDEPENDENT FIXTURE SET — what keeps this leg non-vacuous where the live enumeration
  # cannot be counted (and where it can legitimately enumerate NOTHING). These are FIXTURE STRINGS, not
  # files: obl_detect glob-scans the change-set as text and never stats those paths, which is the same
  # property part (iii) already relied on (it named a profiles/go/ path while --root pointed at an empty
  # temp dir). So the set is identical on every tree, and its own count is locked against a literal list.
  # It deliberately spans BOTH layouts: the kit's per-profile chart, and the `deploy/helm/` and `charts/`
  # roots an adopter's own chart actually lives at — paths the retired glob red-ed and this change frees.
  { echo 'profiles/typescript-node/deploy/helm/templates/deployment.yaml'
    echo 'profiles/go/deploy/helm/templates/service.yaml'
    echo 'deploy/helm/templates/deployment.yaml'
    echo 'charts/app/templates/ingress.yaml'; } > "$_tmp/helmfx"
  UAT_HELM_FIXTURE_COUNT=4      # literal lines written directly above (declared, not counted)
  for _real in app/templates/index.j2 mailers/welcome.erb site/page.twig emails/show.hbs; do
    printf '%s\n' "$_real" > "$_tmp/changed"
    if run_uat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
      printf 'SELFTEST FAIL: real view template %s stopped demanding a UAT sign-off — the markup extensions that replaced */templates/* are not live\n' "$_real"; rc=1
    fi
  done
  # (i-b) and (iii) are asserted TOGETHER, per fixture: the N/A claim and the proof that the retired glob
  # would have red-ed that exact path. Split apart, (iii) proved one hand-picked path while (i-b) claimed
  # four — pairing them per-path means no fixture can be N/A "for free" because it was never on the surface.
  _fxn=0
  while IFS= read -r _fx; do
    [ -n "$_fx" ] || continue
    _fxn=$((_fxn + 1))
    printf '%s\n' "$_fx" > "$_tmp/changed"
    if ! run_uat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
      printf 'SELFTEST FAIL: canonical Helm manifest path %s still demands a UAT sign-off — the bare */templates/* glob is back\n' "$_fx"; rc=1
    fi
    if obligation_gate --name uat --surface-globs '*/templates/*' --record UAT-SIGNOFF.md \
         --template-marker T --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
      printf 'SELFTEST FAIL: the retired */templates/* glob does not itself red %s — its N/A above proves nothing about this change\n' "$_fx"; rc=1
    fi
  done < "$_tmp/helmfx"
  [ "$_fxn" = "$UAT_HELM_FIXTURE_COUNT" ] || {
    printf 'SELFTEST FAIL: %s canonical Helm fixtures probed, expected exactly %s — the fixture list was edited without updating UAT_HELM_FIXTURE_COUNT, or the loop went vacuous\n' \
      "$_fxn" "$UAT_HELM_FIXTURE_COUNT"; rc=1; }
  unset KIT_OBL_TEST   # defence in depth: if this file is ever SOURCED rather than run, the fixture-flag
                       # escape hatch must not survive into the caller's environment.
  # EVERY figure IS INTERPOLATED FROM WHAT THE RUN ACTUALLY DID, never spelled out and never taken from a
  # DECLARED constant: the Helm figure was once hardcoded as "14" while the glob figure was already a %s, so
  # bumping UAT_HELM_MANIFEST_COUNT to 15 still printed "all 14" — a banner asserting a number the run did
  # not use is the same defect class this file's count locks exist to stop. The Helm figure now reads $_helm
  # (what was enumerated), NOT UAT_HELM_MANIFEST_COUNT (what a kit tree is required to enumerate): on a
  # pruned adopter tree those differ, and printing the constant would restate exactly that defect. The tree
  # mode is named for the same reason — a reader must be able to see whether the count lock was in force.
  [ "$rc" = 0 ] && printf 'OK (uat-obligation: 9 legs; all %s surface globs derived+probed and count-locked, both the repo-root and nested forms of every UI directory live, and all %s live Helm manifest(s) on this %s tree + %s canonical Helm fixture(s) held N/A against a live view-template extension set%s)\n' \
    "$UAT_SURFACE_GLOB_COUNT" "$_helm" "$_uat_tree" "$UAT_HELM_FIXTURE_COUNT" \
    "$([ "$_uat_tree" = kit ] && printf ', exact count lock %s in force' "$UAT_HELM_MANIFEST_COUNT" || printf '; the exact count lock is a kit-tree property and does not apply here')"
  return $rc
}

# dispatch — BELOW the selftest() definition so the function is defined before it is called
# (POSIX sh executes top-to-bottom; a forward reference to selftest fails with 'command not found').
# The non-vacuity marker is the selftest() line above, so the check-logic region (run_uat_obligation)
# is still mutated; this dispatch sits after the marker and is emitted verbatim by the sweep.
if [ "${1:-}" = "--selftest" ]; then selftest; exit $?; fi
run_uat_obligation "$@"; exit $?
