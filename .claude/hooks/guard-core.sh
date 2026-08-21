#!/bin/sh
# guard-core.sh — runtime-agnostic deny-matrix (the SINGLE SOURCE OF TRUTH).
# Pure: no stdin parsing, no runtime-specific emit. Each check prints the "13: …"
# reason to STDOUT and returns 1 (deny); returns 0 (allow) with no output.
# Consumed by: .claude/hooks/guard.sh (Claude PreToolUse), hooks/pre-push (git),
# scripts/kit-guard (CLI). See docs/operations/runtime-guards.md.
# A SPEED BUMP, not a boundary — the real control is platform-owned
# (docs/enterprise/platform-safety-boundary.md). POSIX sh; no `local` (dash-clean).

selfedit_allowed() { [ "${KIT_GUARD_SELFEDIT:-0}" = "1" ]; }

# control-plane paths an agent must never silently modify (guard integrity + gates).
# scanner-config allowlists/ignores — an edit here can silently narrow a required gate (KW10):
# .gitleaks.toml / .gitleaksignore / .semgrepignore / .trivyignore / .checkov.yaml|.yml are
# enumerated in the case below (both bare + */-prefixed forms). Honest ceiling: this covers
# DEDICATED scanner-config files (path-matchable). Coverage thresholds embedded in SHARED
# multi-purpose files (pyproject.toml, .golangci.yml) are NOT path-matchable without blocking the
# whole file — that is a content-level problem, out of scope here.
# is_control_plane_path <path> — CASE-INSENSITIVE since A2. On a case-INSENSITIVE filesystem (the
# macOS default, and the kit's own development platform) `.Claude/hooks/guard-core.sh` resolves to the
# REAL guard while a byte-literal match classified it `ordinary` — so the guard could be edited out of
# the way by typing one capital letter, and the required §13 gate derived `ordinary` for it. Measured.
#
# STRICTLY FAIL-SAFE: folding can only ever ADD paths to the control-plane set, and no consumer treats
# a `true` verdict as a grant (guard_check_path denies, is_control_plane_target denies,
# promotion-readiness escalates). The cost is that a genuinely-distinct `Skills/` file on a
# case-SENSITIVE filesystem is now treated as control-plane — a guard prompt, never a bypass.
#
# HOT PATH: this runs on every PreToolUse, twice per path. The literal `case` below is tried FIRST and
# decides every all-lowercase path with zero subprocesses; only a path that actually contains an
# uppercase byte AND missed the literal match pays one `tr`. `LC_ALL=C` + the explicit `A-Z`/`a-z`
# ranges keep it byte-safe: under a Turkish locale `[:upper:]` maps I->ı, which would then fail to
# match `i` in the patterns.
#
# CEILING: closes CASE variance only. It does NOT close Unicode normalization (NFC/NFD) or homoglyphs —
# a related class, deliberately not claimed. Do not read this green as closing those.
# _fs_case_insensitive: is THIS filesystem case-insensitive? Probed ONCE and cached — the fold's cost
# and its false-positive risk both depend on the answer, and it cannot change mid-process. Uses `/tmp`
# (POSIX-required to exist) with `$HOME` as a fallback; no files are written. A Linux box that happens
# to have a real `/TMP` directory answers "insensitive" and simply folds more — the safe direction.
_kit_fs_ci=""
_fs_case_insensitive() {
  if [ -z "$_kit_fs_ci" ]; then
    _kit_fs_ci=0
    # PROBE THE TREE WE ARE JUDGING, not `/` or `$HOME`. An earlier draft tested `/tmp` vs `/TMP` with a
    # `$HOME` fallback, which answers for the WRONG VOLUME and is wrong in real setups: a repo on a
    # case-insensitive disk image or a `+F` casefold ext4 directory under a case-sensitive `/`, a Linux
    # container with a macOS bind mount, or a case-sensitive APFS volume mounted under a
    # case-insensitive `/`. In each the probe said "sensitive" while the variant genuinely resolved.
    # `.github` is present in this repo and in every incepted adopter, so it is a reliable in-tree
    # anchor; `$PWD` is the fallback for a caller running outside a kit tree. No files are written and
    # no env value steers the answer.
    for _kfd in "." ".."; do
      if [ -d "$_kfd/.github" ] && [ -d "$_kfd/.GITHUB" ]; then _kit_fs_ci=1; break; fi
    done
    if [ "$_kit_fs_ci" = 0 ] && [ -d "${PWD:-.}" ]; then
      _kfu=$(printf '%s' "${PWD:-.}" | LC_ALL=C tr 'a-z' 'A-Z')
      [ "$_kfu" != "${PWD:-.}" ] && [ -d "$_kfu" ] && _kit_fs_ci=1
    fi
  fi
  [ "$_kit_fs_ci" = 1 ]
}

# is_control_plane_path <path> — case-insensitive since A2, in TWO tiers.
#
# WHY TWO TIERS. Folding everything unconditionally was measured to break three SHIPPED profiles:
# `src/Adapters/Repo.cs`, `Adapters/Http/StripeAdapter.cs` and `Skills/Onboarding.cs` all derived
# control-plane, and PascalCase directories are the language convention in profiles/dotnet,
# profiles/java-spring and profiles/kotlin — `Adapters/` being the idiomatic ports-and-adapters folder.
# On a case-SENSITIVE filesystem (every CI runner) that is not a guard prompt but a MERGE BLOCK on an
# ordinary PR, clearable only with `--admin` — defeating §13 rather than enforcing it. The design's
# stated cost ("rare, and only a guard prompt") was wrong on both halves.
#
#   TIER 1 — kit-owned names, folded ALWAYS. `.claude/`, `.github/`, `.git/`, the ENUMERATED `.kit/`
#   confs (budget · roster · model-tiers · model-map · dials — a FILENAME enumeration, NOT a `.kit/`
#   directory prefix; the earlier wording claimed a prefix the patterns never implemented, which is
#   how `.kit/dials.conf` measured ORDINARY the day before it shipped), `codeowners`,
#   `claude.md`, `development-*.md`, the named scripts, the scanner-ignore files. Nobody names
#   application code `CLAUDE.md`, so there is no false-positive surface and these stay closed on EVERY
#   platform. This is the tier the real attacks used (`.Claude/hooks/guard-core.sh`, `Claude.md`).
#
#   TIER 2 — generic directory prefixes (`conformance/`, `skills/`, `adapters/`, `agents/`, `scripts/`),
#   folded ONLY on a case-insensitive filesystem. There the variant genuinely RESOLVES to the real
#   directory, which is what makes it dangerous; on a case-sensitive filesystem `Adapters/` is simply a
#   different directory and folding it would be a false positive with no corresponding risk.
#
# ⚠️ RESIDUAL, stated rather than hidden: a path committed on a case-SENSITIVE machine that would
# collide on a case-INSENSITIVE checkout is classified on the CI runner's filesystem, not the
# developer's. Tier 1 is unconditional precisely because that is where a cross-platform collision would
# actually matter; Tier 2's residual is a generic directory an adopter has deliberately named.
is_control_plane_path() {
  _cpp_match "$1" && return 0
  case "$1" in *[A-Z]*) : ;; *) return 1 ;; esac
  _cppf=$(printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z')
  _cpp_kitowned "$_cppf" && return 0
  _fs_case_insensitive && _cpp_match "$_cppf" && return 0
  return 1
}

# TIER 1 set — kit-owned, unambiguous, folded on every platform.
#
# ⚠️ THE LINE IS DRAWN AT FILENAME GRANULARITY, NOT DIRECTORY GRANULARITY. The first cut of this split
# put whole directories in Tier 2 (`skills/`, `conformance/`, `agents/`, `scripts/`) because
# `Skills/Onboarding.cs` and `src/Adapters/Repo.cs` are plausible adopter code. But the ambiguity is in
# the FILE, not the folder: no dotnet/java/kotlin adopter ships `Skills/review/SKILL.md`,
# `Agents/reviewer.agent.md`, `Conformance/verify.sh` or `Scripts/promotion-verify.sh`. Drawing the line
# at the directory left those classified ORDINARY on every Linux runner — a live §13 bypass (below) —
# while buying no false-positive protection they needed.
#
# THE BYPASS THIS CLOSES, measured: an attacker opens a PR adding `Skills/incident-response/SKILL.md`.
# On ubuntu-latest the class derived `ordinary`, `control-plane-ratification` posted GREEN "nothing to
# ratify", and it merged under an ordinary review. Git then checks a NEW file at a case-variant path
# out SILENTLY into the real directory on any case-insensitive clone — no collision warning, unlike an
# existing file (which warns, and whose real content wins because the lowercase path sorts later). So
# the attacker's file becomes a live agent-instruction surface carrying kit authority.
#
# `.claude/` IS A SEGMENT-ANCHORED FAMILY (GUARD-PATH-ENUMERATION-INCOMPLETE S1). It began as
# `guard.sh`/`guard-core.sh` by name, so every other file in the hook directory derived `ordinary` —
# measured: `.claude/hooks/entry-core.sh` -> ordinary, with Write, Edit and `sed -i` on it all ALLOWED.
# That was cured for `hooks/` with a directory prefix; the SAME hole then measured live one level up:
# `.claude/commands/*` and `.claude/plugins/*` both derived ordinary at 9d29406e (neither directory
# exists yet, which is exactly why no census over tracked files could see them). The whole directory is
# wired into settings.json as agent instrumentation, so ANY file in it is a live control-plane surface
# an agent could author unratified. The family is the fix the per-directory prefix was a down payment
# on: `.claude/*|*/.claude/*` — one rule, no list, and a sub-directory invented tomorrow is covered
# before it exists.
# THE ANCHOR IS THE POINT. `.claude/*|*/.claude/*` matches a full `.claude` PATH SEGMENT (at the start
# or after a `/`), NEVER `*.claude/...`: the loose form also matched any component merely ENDING in
# `.claude` — measured, `my.claude/hooks/x` and `src/mycompany.claude/hooks/z` both derived
# control-plane. Those are ordinary adopter files, and an unnecessary control-plane classification is
# an unnecessary ratification demand on an ordinary PR. The anchored family still captures a vendored
# `vendor/pkg/.claude/hooks/h.sh` and, via this tier's unconditional fold, `.Claude/Hooks/Entry.sh`.
# THE FOUR SIBLING `*.claude/...` PATTERNS ARE NOW GONE — deliberately, WITH the evidence the comment
# they replace demanded. `*.claude/settings.json` · `*.claude/settings.local.json` ·
# `*.claude/mcp-policy.json` · `*.claude/agents/*` each carried the identical `<x>.claude/...` false
# positive (measured: `my.claude/settings.json`, `my.claude/mcp-policy.json`, `my.claude/agents/x.md`
# all derived control-plane). The old note left them alone because narrowing four patterns on the file
# that decides what may be edited at all is its own change — "its own fixtures, its own monotonicity
# run, its own review". This slice IS that change: the sibling-relief ALLOW fixtures on BOTH routes and
# the corner-spelling DENY fixtures live in conformance/agent-autonomy.sh, the fold-monotonicity sweep
# runs over synthetic never-tracked family paths in promotion-readiness-wired.sh, and the pathhit
# `.claude` leg is re-anchored in the same commit so the relief is not route-split.
# ⚠️ COVERAGE WIDENS ONE STEP with the family: files sitting DIRECTLY in `.claude/` (`.claude/README.md`,
# `.claude/settings.local.json`) are control-plane now where the enumeration reached only four names.
# That is the intended direction — everything in the agent's own instrumentation directory is governing
# — and it is fail-SAFE (a ratification demand, never a missed one). Fixtures record it explicitly so
# it reads as a decision, not as drift.
# ⚠️ THE RELIEF ARM BELOW IS FIRST ON PURPOSE, AND IT IS THE ONLY HOLE IN THE `.claude/` FAMILY.
# GUARD-CLAUDE-HOME-INSTRUMENTATION-FP (design docs/architecture/2026-08-17-guard-claude-home-fp-design.md).
# The family above is segment-anchored, so `*/.claude/*` matches ANY absolute path carrying a
# `/.claude/` segment — including the agent harness's OWN home directory. Measured 2026-08-17, minutes
# after S1 shipped: `~/.claude/projects/<p>/memory/*.md` (persistent agent memory) and
# `~/.claude/plans/*.md` (plan mode) were guard-DENY on both the Edit and Write tool routes, which
# broke the standing memory directive and plan mode in EVERY session wherever this hook is wired.
# Those two subtrees are the agent's WORKSPACE, not its instrumentation. Everything else under
# `.claude/` — settings.json, settings.local.json, mcp-policy.json, hooks/, agents/, commands/,
# plugins/, skills/, workflows/, CLAUDE.md, statusline-command.sh (which the harness EXECUTES), and
# every name invented tomorrow — stays family-denied: those are the user-level halves of the exact
# permission surfaces PERMISSION-LOCAL-ACCRETION-SIGNAL monitors, and the categorical owner-keystroke
# bright line. `tasks/`/`todos/` are deliberately NOT relieved: each addition is its own ratified
# control-plane change, which is the correct friction direction.
# POSIX `case` is FIRST-MATCH-WINS, so this arm must precede the family arm or it is inert.
# ⚠️ IT MUST BE ADDED TO **BOTH** TIERS ATOMICALLY. Tier 1 ⊆ Tier 2 is the fold's soundness
# invariant: relieving only here would leave Tier 1 NARROWER (harmless) while relieving only in
# `_cpp_match` would leave Tier 1 BROADER — manufacturing control-plane-ness on the folded spelling.
# A one-sided WIDENING confined to `_cpp_kitowned` is caught on every filesystem only by the
# BRIGHTLINE-T1 predicate in conformance/promotion-readiness-wired.sh; a one-sided RELIEF in either
# direction is caught by the relief ALLOW legs, the case-variant one FS-independently.
# WHY THE RELIEF HALF NEEDS NO STRUCTURAL LEG (measured, and an earlier draft of this comment claimed
# otherwise): once `_cpp_kitowned` returns 0 the wrapper returns control-plane IMMEDIATELY — the
# conditional Tier-2 re-check below it never runs — so a relief missing from Tier 1 turns the
# case-variant subject `…/.CLAUDE/PLANS/x.md` control-plane on a case-INSENSITIVE host too, not just
# on CI. The WIDENING half is the genuinely FS-dependent one (vet C2): a widened Tier 1 hands the
# subject back to that same re-check, which still denies on macOS, so it dies only on CI at the
# verdict level — which is what BRIGHTLINE-T1 exists to cover.
# ⚠️ THE RELIEF IS CLASSIFIER-ONLY, BY OWNER RULING (design §3, C1 = option (b)). The `_CP8B_PATHHIT_*`
# regex legs deny DIRECTLY without ever consulting this function, so a non-read-verb shell spelling
# (`sed -i`, `tee`, an interpreter's `open(...)`) aimed at a relieved name STILL denies. That is a
# DISCLOSED RETAINED FALSE POSITIVE, fixtured in conformance/agent-autonomy.sh — the broken workflows
# use the tool route exclusively, and this keeps the guard's hottest deny leg byte-untouched.
# ⚠️ TWO FACES DISCLOSED RATHER THAN DISCOVERED: (i) the arm returns EARLY, so a family name nested
# UNDER a relieved one (`.claude/projects/x/hooks/pre-push`) classifies ordinary — pinned as a
# recorded decision, not drift; (ii) the relief is by subtree NAME, not location, so a repo that
# TRACKED these subtrees would derive `ordinary` at `promotion-readiness --class` and merge without
# control-plane ratification (pinned in promotion-readiness-wired.sh). $HOME-anchored patterns were
# rejected as the alternative: env-dependent matching is the worse failure mode.
_cpp_kitowned() {
  case "$1" in
    .claude/projects/*|*/.claude/projects/*|.claude/plans/*|*/.claude/plans/*) return 1 ;;
    .claude/*|*/.claude/*|\
    */.github/workflows/*|.github/workflows/*|*/.git/*|.git/*|\
    .kit/budget.conf|*/.kit/budget.conf|.kit/roster.conf|*/.kit/roster.conf|\
    .kit/model-tiers.conf|*/.kit/model-tiers.conf|.kit/model-map.conf|*/.kit/model-map.conf|\
    .kit/dials.conf|*/.kit/dials.conf|\
    codeowners|*/codeowners|claude.md|*/claude.md|\
    development-standards.md|*/development-standards.md|\
    development-process.md|*/development-process.md|\
    agents.md|*/agents.md|\
    required-checks.md|*/required-checks.md|\
    .gitattributes|*/.gitattributes|\
    */hooks/pre-push|hooks/pre-push|*/scripts/kit-guard|scripts/kit-guard|\
    .gitleaks.toml|*/.gitleaks.toml|.gitleaksignore|*/.gitleaksignore|\
    .semgrepignore|*/.semgrepignore|.trivyignore|*/.trivyignore|\
    .checkov.yaml|*/.checkov.yaml|.checkov.yml|*/.checkov.yml|\
    docs/governance/.meta-control-last|*/docs/governance/.meta-control-last|\
    docs/governance/meta-control-log.md|*/docs/governance/meta-control-log.md|\
    conformance/*.sh|*/conformance/*.sh|\
    skills/*/skill.md|*/skills/*/skill.md|\
    agents/*.agent.md|*/agents/*.agent.md|\
    scripts/incept.sh|*/scripts/incept.sh|scripts/dora.sh|*/scripts/dora.sh|\
    scripts/agent-scorecard.sh|*/scripts/agent-scorecard.sh|\
    scripts/agent-trace.sh|*/scripts/agent-trace.sh|\
    scripts/escalate.sh|*/scripts/escalate.sh|\
    scripts/coverage-ratchet.sh|*/scripts/coverage-ratchet.sh|\
    scripts/license-check.sh|*/scripts/license-check.sh|\
    scripts/preflight.sh|*/scripts/preflight.sh|\
    scripts/new-adapter.sh|*/scripts/new-adapter.sh|\
    scripts/new-profile.sh|*/scripts/new-profile.sh|\
    scripts/doctor.sh|*/scripts/doctor.sh|\
    scripts/postmortem.sh|*/scripts/postmortem.sh|\
    scripts/tier-advice.sh|*/scripts/tier-advice.sh|\
    scripts/sparkwright|*/scripts/sparkwright|\
    scripts/containment-audit.sh|*/scripts/containment-audit.sh|\
    scripts/sod-check.sh|*/scripts/sod-check.sh|\
    scripts/model-tier.sh|*/scripts/model-tier.sh|\
    scripts/runaway-guard.sh|*/scripts/runaway-guard.sh|\
    scripts/orchestrator-run.sh|*/scripts/orchestrator-run.sh|\
    scripts/release-tag.sh|*/scripts/release-tag.sh|\
    scripts/promotion-verify.sh|*/scripts/promotion-verify.sh|\
    adapters/*/adapter.json|*/adapters/*/adapter.json|\
    conformance/claims.tsv|*/conformance/claims.tsv|\
    conformance/aggregate-exclusions.txt|*/conformance/aggregate-exclusions.txt|\
    conformance/incept-manifests/*|*/conformance/incept-manifests/*|\
    conformance/fixtures/*|*/conformance/fixtures/*|\
    scripts/fixtures/*|*/scripts/fixtures/*)
      return 0 ;;
  esac
  return 1
}

# ⚠️ TIER 1 MUST BE A STRICT SUBSET OF _cpp_match. The fold's only sound invariant is
#   is_control_plane_path(p)  =>  is_control_plane_path(tolower(p))
# i.e. folding may only ever PRESERVE control-plane-ness, never CREATE it. An earlier draft listed
# `*.claude/*` and `*/.github/*` here while `_cpp_match` carried only `.github/workflows/*` and five
# specific `.claude/` files — so Tier 1 was BROADER than the set it folds and manufactured new
# classifications. Measured over all tracked files: `.github/ISSUE_TEMPLATE/*`,
# `.github/PULL_REQUEST_TEMPLATE.md` and `.claude/README.md` flipped ordinary -> control-plane on EVERY
# platform. Those are GitHub's own uppercase conventions, present in near-every adopter, so a PR editing
# a bug-report template demanded non-author ratification — the merge block this whole split exists to
# avoid, arriving through the tier that was supposed to be the safe one.
# `conformance/invariant-fold-monotone` (promotion-readiness-wired.sh) now asserts the invariant over
# every tracked path, because it is a PROPERTY, not an example — an anchor list cannot catch this.
# ⚠️ THE TRACKED-FILE CENSUS IS BLIND WHERE THIS SLICE WORKS. `scripts/zz-*`, `.claude/commands/*`,
# `profiles/zz-*` are not tracked (two of those directories do not exist at all), so a sweep over
# `git ls-files` says nothing about them. The invariant is therefore ALSO asserted over synthetic,
# never-tracked family paths — same check, explicit list — or the subset relation would be proven
# only where it was never in doubt.

# The pattern set, LOWERCASED. Both sides of the comparison are folded — the subject by the wrapper
# above, the patterns here at authoring time. ⚠️ Every pattern in this list MUST stay lowercase: a
# pattern carrying an uppercase byte can never match a folded subject, which would SILENTLY DECLASSIFY
# it. That is not hypothetical — the first draft of this change kept `CODEOWNERS`, `CLAUDE.md`,
# `DEVELOPMENT-STANDARDS.md` and `DEVELOPMENT-PROCESS.md` byte-identical and turned all four `ordinary`.
# The `.claude/*` family is the IDENTICAL segment-anchored form Tier 1 carries (see the note above
# `_cpp_kitowned`, which records the measurements behind it): Tier 1 must stay a strict subset of this
# set, so the two patterns are kept byte-identical rather than merely equivalent.
#
# GUARD-PATH-ENUMERATION-INCOMPLETE S1 — THE DIRECTORY FAMILIES LIVE HERE, AND ONLY HERE.
# `scripts/*|*/scripts/*` and `profiles/*|*/profiles/*` join `conformance/`, `skills/` and `adapters/`
# in TIER 2 — deliberately NOT in `_cpp_kitowned`. Tier 1 folds on EVERY platform, so a generic
# `scripts/` prefix there would fold `src/Scripts/Deploy.cs` into control-plane on case-SENSITIVE
# Linux and reinstate the exact false-positive class the tier split was built to close (the same
# measurement that produced `src/Adapters/Repo.cs` and `Skills/Onboarding.cs`). Tier 1 keeps its
# per-NAME script entries as the unambiguous-filename floor; because the family lives only here, the
# "Tier 1 ⊆ Tier 2" invariant above stops being self-satisfied and becomes a real proof.
# WHY A FAMILY AT ALL: `scripts/` was protected per-file (~20 names), and the class demonstrated itself
# live — `scripts/branch-protection-apply.sh` was born 2026-08-06 outside the hand list and was
# guard-writable and mergeable as `ordinary` for ten days. `profiles/` carries the enforcement-bearing
# surfaces an adopter's CI actually runs (`adopter-gates.yml`, `ratification.yml`, per-stack `ci.yml`,
# `BRANCH-PROTECTION.md`), and any curated sub-list inside it would be the same defect reborn.
# The DEEP arm (`*/scripts/*`, `*/profiles/*`) SHIPS on measurement, not on taste: `git archive HEAD`
# retains 403 `profiles/` paths (no export-ignore entry) and `scripts/incept.sh` §5a4 keeps
# `profiles/<STACK>/`, `ratification.yml` and `adopter-gates.yml`, so incepted adopter trees carry a
# real `profiles/` root; the arm also catches the 14 tracked `profiles/*/scaffold/scripts/*` files.
# ⚠️ DISCLOSED, NOT DISCOVERED LATER: "scripts" and "profiles" are far commoner directory names in an
# adopter app tree than conformance/skills/adapters, so `frontend/scripts/build.js` and
# `src/profiles/user.ts` become guard-DENY in ANY adopter tree where this hook is wired (byte-literal
# on every platform — the case-conditioning only ever protects case-VARIANT spellings). Fail-safe by
# direction, and the price is stated rather than waved at: ~37 profiles-touching commits/month
# measured on the kit itself, all of which become dev-clone + ratification work.
# ⚠️ THERE IS NO "OBSERVE MODE" ON THIS ROUTE, AND AN EARLIER DRAFT OF THIS COMMENT SAID OTHERWISE.
# `LOOP_STATE_MODE` softens the CI class/loop-state route ONLY. This file has no mode knob of any
# kind, and `.claude/` ships in the adopter export — so wherever the PreToolUse hook is wired, these
# denies are UNCONDITIONAL from the first tool call. "Observe-mode adopters see advisories, not
# blocks" was false here and is the kind of softener that turns a disclosed cost into a surprise.
# The per-name `scripts/*.sh` entries below are now SUBSUMED by the family. They are kept, not pruned:
# they are the byte-identical mirror of Tier 1's floor, and deleting entries from the list that decides
# what may be edited at all is a change that would need its own evidence — not a tidy-up.
# THE CURATED ROOT ADDITIONS, with the property named. `agents.md` (the roster-authority floor; the
# file `incept` renames into the adopter's governing doc), `required-checks.md` (binds which CI
# contexts block merge — the same enforcement-bearing class), and `.gitattributes` AT EVERY DEPTH
# (`git archive` honors it per-directory, so a nested `docs/.gitattributes` flipping `export-ignore`
# carries the identical export-control property; root-only would have been incomplete). `.gitignore` is
# deliberately EXCLUDED — untracked files never export, so the property does not cover it.
# ⚠️ HONEST CEILING: root-level governing files are NOT structurally derivable. This stays a curated
# list, and a NEW root governing file still needs a list edit. The compensating detection is a
# guard-vs-class census lock (S2), which is where "the list drifted" becomes a red instead of a probe
# finding. Do not read the families above as covering this row.
# THE HOME-INSTRUMENTATION RELIEF ARM IS MIRRORED HERE, BYTE-IDENTICALLY, AND FIRST
# (GUARD-CLAUDE-HOME-INSTRUMENTATION-FP — the full rationale sits above `_cpp_kitowned`, where the
# same arm leads Tier 1). Kept byte-identical rather than merely equivalent, exactly as the
# `.claude/*` family patterns are, because Tier 1 ⊆ Tier 2 is asserted structurally and a relief
# present in only one tier is the failure mode that check exists to catch. `case` is
# first-match-wins: this arm must precede the family arm below or it is inert.
_cpp_match() {
  case "$1" in
    .claude/projects/*|*/.claude/projects/*|.claude/plans/*|*/.claude/plans/*) return 1 ;;
    .claude/*|*/.claude/*|\
    docs/governance/.meta-control-last|*/docs/governance/.meta-control-last|\
    docs/governance/meta-control-log.md|*/docs/governance/meta-control-log.md|\
    */hooks/pre-push|hooks/pre-push|*/scripts/kit-guard|scripts/kit-guard|\
    */.github/workflows/*|.github/workflows/*|*/codeowners|codeowners|*/.git/*|.git/*|\
    .gitleaks.toml|*/.gitleaks.toml|.gitleaksignore|*/.gitleaksignore|\
    .semgrepignore|*/.semgrepignore|.trivyignore|*/.trivyignore|\
    .checkov.yaml|*/.checkov.yaml|.checkov.yml|*/.checkov.yml|\
    conformance/*|*/conformance/*|adapters/*|*/adapters/*|\
    skills/*|*/skills/*|\
    scripts/*|*/scripts/*|\
    profiles/*|*/profiles/*|\
    agents.md|*/agents.md|\
    required-checks.md|*/required-checks.md|\
    .gitattributes|*/.gitattributes|\
    scripts/fixtures/*|*/scripts/fixtures/*|\
    scripts/incept.sh|*/scripts/incept.sh|scripts/dora.sh|*/scripts/dora.sh|\
    scripts/agent-scorecard.sh|*/scripts/agent-scorecard.sh|\
    scripts/agent-trace.sh|*/scripts/agent-trace.sh|\
    scripts/escalate.sh|*/scripts/escalate.sh|\
    scripts/coverage-ratchet.sh|*/scripts/coverage-ratchet.sh|\
    scripts/license-check.sh|*/scripts/license-check.sh|\
    scripts/preflight.sh|*/scripts/preflight.sh|\
    scripts/new-adapter.sh|*/scripts/new-adapter.sh|\
    scripts/new-profile.sh|*/scripts/new-profile.sh|\
    scripts/doctor.sh|*/scripts/doctor.sh|\
    scripts/postmortem.sh|*/scripts/postmortem.sh|\
    scripts/tier-advice.sh|*/scripts/tier-advice.sh|\
    scripts/sparkwright|*/scripts/sparkwright|\
    scripts/containment-audit.sh|*/scripts/containment-audit.sh|\
    scripts/sod-check.sh|*/scripts/sod-check.sh|\
    .kit/budget.conf|*/.kit/budget.conf|\
    .kit/roster.conf|*/.kit/roster.conf|\
    .kit/model-tiers.conf|*/.kit/model-tiers.conf|\
    .kit/model-map.conf|*/.kit/model-map.conf|\
    .kit/dials.conf|*/.kit/dials.conf|\
    scripts/model-tier.sh|*/scripts/model-tier.sh|\
    scripts/runaway-guard.sh|*/scripts/runaway-guard.sh|\
    scripts/orchestrator-run.sh|*/scripts/orchestrator-run.sh|\
    scripts/release-tag.sh|*/scripts/release-tag.sh|\
    scripts/promotion-verify.sh|*/scripts/promotion-verify.sh|\
    agents/*.agent.md|*/agents/*.agent.md|\
    development-standards.md|*/development-standards.md|\
    development-process.md|*/development-process.md|\
    claude.md|*/claude.md)
      return 0 ;;
  esac
  return 1
}

# --- CP-8c: dev-clone affordance ----------------------------------------------------
# _resolve_physical "<path>": echo the physical (symlink-resolved) absolute path. Resolves the
# DEEPEST EXISTING ancestor with `cd … && pwd -P` (collapsing `..`, symlinks, the macOS
# /tmp->/private/tmp landmine) and re-appends the not-yet-existing tail.
# SUBPROCESSES: `pwd -P` (CP-4's sanctioned one), plus `readlink` for the leaf loop below and `tr`
# in _under_temp's folded arm — both added 2026-08-01 by GUARD-PATH-ALIAS-BYPASS. The earlier
# "`pwd -P` is the one sanctioned subprocess" wording is superseded; leaving it would have been a
# false certification of the same shape as the cp/hardlink one this slice also corrects. Both new
# calls fail SAFE: an absent `readlink` returns 127 => `return 1` => callers deny.
# ⚠️ It resolves the physical PARENT plus a symlink-resolved leaf — it does NOT detect HARDLINKS
# (a hardlink has no link to follow; see GUARD-CP-HARDLINK-ALIAS).
_resolve_physical() {
  _rp=$1
  case "$_rp" in /*) : ;; *) _rp="$(pwd)/$_rp" ;; esac
  # GUARD-PATH-ALIAS-BYPASS (P0): resolve a symlinked LEAF. The ancestor walk below never examines
  # the final component, so a one-symlink leaf named innocuously reached any target unseen. Bounded
  # at 64: SYMLOOP_MAX is 32 here, so exhaustion means adversarial, never deep-but-legitimate.
  # Exit on "still a symlink" rather than on the counter, so a legitimate chain of exactly 64 that
  # DID resolve is not refused. A relative target resolves against the LINK's own directory; `..`
  # inside a target is left to `cd -P` and never collapsed textually. Failure => rc 1 => callers deny.
  _n=0
  while [ -L "$_rp" ] && [ "$_n" -lt 64 ]; do
    _t=$(readlink "$_rp") || return 1
    case "$_t" in /*) _rp=$_t ;; *) _rp="$(dirname "$_rp")/$_t" ;; esac
    _n=$((_n+1))
  done
  [ -L "$_rp" ] && return 1
  [ "$_rp" = / ] && { printf '/'; return 0; }   # degenerate root; avoids a `//` result
  _rpd=$(dirname "$_rp"); _rpb=$(basename "$_rp"); _rps=$_rpb
  while [ ! -d "$_rpd" ]; do
    _rpb=$(basename "$_rpd"); _rpd=$(dirname "$_rpd"); _rps="$_rpb/$_rps"
    [ "$_rpd" = "/" ] && break
  done
  # `cd` (logical) canonicalises `..` against the path STRING before chdir, so a `..` following a
  # symlink erases the symlink instead of following it — the original P0. `-P` chdirs physically.
  _rpp=$(CDPATH='' cd -P "$_rpd" 2>/dev/null && pwd -P) || return 1
  if [ "$_rpp" = / ]; then printf '/%s' "$_rps"; else printf '%s/%s' "$_rpp" "$_rps"; fi
}

# _under_temp "<physical_path>": 0 iff the path is under a HARDCODED temp root. The set is FIXED
# and never read from $TMPDIR — reading an env var to WIDEN "disposable temp" is the fail-open
# direction (a poisoned TMPDIR=$HOME would relax ~/.claude). Covers Linux /tmp, macOS
# /private/tmp, and the macOS per-user temp (resolved: /private/var/folders/*/T/).
_under_temp() {
  case "$1/" in
    /tmp/*|/private/tmp/*|/var/folders/*/T/*|/private/var/folders/*/T/*) return 0 ;;
  esac
  # GUARD-UNDER-TEMP-CASE: a case-folded SECOND arm, never a replacement. Folding only the subject
  # against the list above would make its literal uppercase `T` unmatchable — and since a bare
  # `mktemp -d` yields /var/folders/…/T/… on macOS, every dev-clone would stop relaxing while Linux
  # CI (TMPDIR unset => /tmp) stayed green. Arm 1 is byte-identical to before and returns first, so
  # this can only ever ADD a temp match. The short-circuit keeps the hot path subprocess-free —
  # but with an EXPLICIT set, not `[A-Z]`: under a UTF-8 locale bash's range collation matches
  # lowercase too, so `[A-Z]` fires on every path and spawns the very subprocess it exists to avoid.
  # Measured — bash-as-/bin/sh matched "/tmp/foo"; dash did not. (Line 90 carries the same latent
  # issue in a colder path; left alone here to keep this slice's diff to its own subject.)
  case "$1" in *[ABCDEFGHIJKLMNOPQRSTUVWXYZ]*) : ;; *) return 1 ;; esac
  _ut=$(printf '%s/' "$1" | LC_ALL=C tr 'A-Z' 'a-z')
  case "$_ut" in
    /tmp/*|/private/tmp/*|/var/folders/*/t/*|/private/var/folders/*/t/*) return 0 ;;
  esac
  return 1
}

# guard_dev_clone_relaxable "<path>" "<protected_root>": return 0 IFF a control-plane edit to
# <path> is safe to relax. THREE conditions, all physically resolved:
#   1. <path> is UNDER a (hardcoded) temp root, AND
#   2. <path> is OUTSIDE the protected repo root, AND
#   3. the protected root is NOT itself under temp.
# Condition 3 is load-bearing: when the protected tree is itself disposable (the mktemp'd export,
# a CI checkout), a path escaping the root lands as a temp-SIBLING that satisfies 1+2 — condition 3
# disables the affordance there, where there is no live control plane to protect anyway. A real
# repo (~/Development/…) is never under temp, so the dev-clone case is unaffected.
# Empty protected_root => 1 (fail-safe). A surviving `..` in the resolved path => 1 (an unresolved
# tail that could escape back into root). Only the CALLER (guard_check_path) uses this, only to skip
# the control-plane deny — never the secret or destructive denies.
guard_dev_clone_relaxable() {
  _dp=$1; _droot=$2
  [ -n "$_droot" ] || return 1
  _dphys=$(_resolve_physical "$_dp") || return 1
  _drootp=$(_resolve_physical "$_droot") || return 1
  [ -n "$_dphys" ] && [ -n "$_drootp" ] || return 1
  # GUARD-PATH-ALIAS-BYPASS (P0): this predicate is the one that turns control-plane denies OFF, so
  # it takes the CONJUNCTION — the LITERAL path must qualify too, not just the resolved one.
  # Without it, leaf resolution carries an inside-root control-plane path out to temp, all three
  # resolved-side conditions hold, and DENY flips to ALLOW. $_dp arrives RAW (:303) — absolutise and
  # collapse `..` (the same fixpoint guard_check_path uses) or relative spellings sail past.
  # NOT `|| is_control_plane_path "$_dp"`: _cp8c_relax is only read where that is already true, so
  # the disjunct would be unconditionally true and disable the affordance entirely (measured).
  _dpa=$_dp
  case "$_dpa" in /*) : ;; *) _dpa="$(CDPATH='' pwd -P)/$_dpa" ;; esac
  _dpa=$(printf '%s' "$_dpa" | sed -e 's#//*#/#g' -e 's#/\./#/#g' -e ':a' -e 's#[^/]*/\.\./##' -e 'ta')
  case "$_drootp" in /) return 1 ;; esac              # degenerate root: `//*` matches nothing
  case "$_dpa/" in "$_drootp"/*) return 1 ;; esac     # literal inside the root => never relax
  # The literal must ALSO be under temp. When it is not but the RESOLVED path is, the caller was
  # addressing a genuine clone through a symlink from outside temp — a legitimate workflow that used
  # to work. Flag it so guard_check_path can name the real-path remedy instead of falling through to
  # the generic control-plane reason, whose only signposted escape is the global kill switch.
  if ! _under_temp "$_dpa"; then
    # Only promise the real-path remedy when that spelling would GENUINELY relax — i.e. when the
    # affordance's OTHER conditions already hold: the root must not itself be under temp (condition
    # 3), the resolved path must be outside the root (condition 2), and must carry no surviving
    # `..`. Without these the message sends the operator to a spelling that also denies, and THAT
    # denial's only signpost is the global kill switch — the endorsed-bypass class, one hop out.
    if _under_temp "$_dphys" && ! _under_temp "$_drootp"; then
      case "/$_dphys/" in
        *"/../"*) : ;;
        *) case "$_dphys/" in
             "$_drootp"/*) : ;;
             *) _cp8c_hint=symlinked-clone ;;
           esac ;;
      esac
    fi
    return 1
  fi
  case "/$_dphys/" in *"/../"*) return 1 ;; esac
  _under_temp "$_drootp" && return 1          # condition 3: disposable root => affordance off
  case "$_dphys/" in "$_drootp"/*) return 1 ;; esac  # condition 2: must be outside root
  _under_temp "$_dphys" && return 0           # condition 1: target under temp
  return 1
}

# =============================================================================================
# GUARD-CP-HARDLINK-ALIAS — the guard resolves SYMLINKS but not HARDLINKS. A hardlink is a second
# directory entry for one inode; there is no link to follow, so a benign-named hardlink's resolved
# path IS the benign name and every union arm (literal ∨ normalised ∨ resolved) passes it. This adds
# a RESOLVED-INODE disjunct to the same unions: if the resolved target shares its inode with a
# control-plane or secret file reached by a different directory entry, it writes/reads THAT file, and
# the name it is reached by does not change what it touches. (design 2026-08-18-guard-cp-hardlink-alias)
# =============================================================================================

# _is_secret_path "<path>" — the ONE source of truth for "is this a secret filename". Reproduces the
# two arms every direct secret site carries: the byte-literal glob AND the case-folded arm (a
# case-variant .ENV/.PEM on a case-insensitive filesystem reaches the same inode). Consolidated here
# (GUARD-CP-HARDLINK-ALIAS §2c) from the eight inlined copies so the pattern cannot drift; the coupling
# selftest in agent-autonomy.sh pins the alternation string byte-identical. The TEMPLATE allowlist is
# deliberately NOT folded in — it stays byte-literal at each call site (never fold an allow matcher).
_is_secret_path() {
  case "$1" in
    *.env|*/.env|*.env.*|*.pem|*.key|*id_rsa*|*/secrets/*|*/secret/*|secrets/*|secret/*) return 0 ;;
  esac
  case "$1" in *[A-Za-z]*)
    _isp=$(printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z')
    case "$_isp" in
      *.env|*/.env|*.env.*|*.pem|*.key|*id_rsa*|*/secrets/*|*/secret/*|secrets/*|secret/*) return 0 ;;
    esac ;;
  esac
  return 1
}

# _is_secret_hit "<path>" — the secret classifier the INODE check uses. Same as _is_secret_path but
# with the TEMPLATE-NAME EXEMPTION (BUILD CONDITION A, vet round 2): the inode wrapper has no allowlist
# in front of it, so without this a hardlinked `.env.example` whose only sibling is a benign file would
# self-classify (its own returned name `.env.example` matches `*.env.*`) and over-deny every write/read
# to a legitimate hardlinked template. A find-returned name that IS a template name does not count as a
# secret hit; the cloak still denies because the REAL `.env` sibling is a non-template secret.
_is_secret_hit() {
  case "$(basename "$1" 2>/dev/null || printf '%s' "$1")" in
    .env.example|.env.sample|.env.template|.env.dist) return 1 ;;
  esac
  _is_secret_path "$1"
}

# _nlink_of "<path>" — echo the target's hard-link count; rc 1 (echo nothing) when it cannot be a
# number. BSD (`stat -f '%l'`, darwin) vs GNU (`stat -c '%h'`) branch: GNU form tried first because
# BSD stat rejects `-c` (measured: "illegal option -- c"), while GNU stat's `-f` means --file-system
# (a different datum), so the order matters. ⚠️ BUILD MANDATE (vet, HIGH): parse with the
# DECLINE-ON-NON-DIGIT negated-class idiom — an empty/absent/non-digit count routes to fail-safe (the
# caller treats rc 1 as "cannot count => run find / deny"), NEVER to a head-anchored positive match
# that would let ""/"x" slip to the nlink==1 ALLOW.
_nlink_of() {
  _nl=$(stat -c '%h' "$1" 2>/dev/null) || _nl=$(stat -f '%l' "$1" 2>/dev/null) || _nl=''
  case "$_nl" in ''|*[!0-9]*) return 1 ;; esac   # decline-on-non-digit (vet BUILD MANDATE)
  printf '%s' "$_nl"
}

# _devino_of "<path>" — echo "<device> <inode>" (both decimal); rc 1 on any non-"digits SP digits".
# Same BSD/GNU branch and the same decline-on-non-digit discipline as _nlink_of.
_devino_of() {
  _di=$(stat -c '%d %i' "$1" 2>/dev/null) || _di=$(stat -f '%d %i' "$1" 2>/dev/null) || _di=''
  case "$_di" in
    *[!0-9\ ]*|''|*' '*' '*) return 1 ;;   # exactly two space-separated digit fields
  esac
  case "$_di" in *' '*) : ;; *) return 1 ;; esac
  printf '%s' "$_di"
}

# _hl_physical_home — echo the PHYSICALLY-resolved $HOME (rc 1 + empty when $HOME is unset/unreadable).
# ⚠️ H1 (reviewer, round 3): the cap MUST compare the PHYSICAL $HOME, not the raw env string. A
# symlinked $HOME (e.g. HOME=/tmp/homelink -> /private/tmp/fakehome) never prefix-matches a
# physically-resolved candidate, so a raw-env compare silently misses and reopens the `find $HOME` DoS.
_hl_physical_home() { CDPATH= cd "${HOME:-/}" 2>/dev/null && pwd -P; }

# _hl_at_or_above_home "<physical-path>" — rc 0 iff <physical-path> IS $HOME or an ancestor of $HOME
# (then "$HOME/" glob-matches "$path"/*). Used to CAP both the derived AND the passed root (LOW-1):
# a repo rooted at/above $HOME would scope a home-or-wider find. Empty/unreadable home => rc 1 (no cap).
_hl_at_or_above_home() {
  _hah_home=$(_hl_physical_home) || return 1
  [ -n "$_hah_home" ] || return 1
  case "$_hah_home/" in "$1"/*) return 0 ;; esac
  return 1
}

# _hlink_repo_root "<path>" — derive the NEAREST ancestor of <path> containing .git or .claude
# (GUARD-CP-HARDLINK-ALIAS §2d). ONLY reached when no protected root was PASSED (kit-guard CLI, older
# adapters, and — until MEDIUM-1 threaded it — the read side); when a root is passed, that
# authoritative, unsteerable value is used directly.
# ⚠️ NEAREST, and CAPPED STRICTLY BELOW the PHYSICAL $HOME (H1). The earlier OUTERMOST climb was a DoS:
# `~/.claude` EXISTS on a real machine, so for a repo under `~` the outermost ancestor became $HOME and
# `find $HOME -inum` walked the ENTIRE home directory on the highest-frequency tool path. So: return
# the NEAREST `.git`/`.claude` ancestor, and NEVER $HOME, any ancestor at/above $HOME, or `/`. If the
# nearest boundary IS $HOME, or the walk reaches $HOME/`/` with no repo boundary strictly below,
# derivation FAILS (rc 1) → the engine fail-safes to a HIT (deny) for that one nlink>1 target.
_hlink_repo_root() {
  _hrr=$1
  case "$_hrr" in /*) : ;; *) _hrr="$(pwd)/$_hrr" ;; esac
  _hrhome=$(_hl_physical_home) || _hrhome=''
  _hrd=$(dirname "$_hrr")
  while : ; do
    case "$_hrd" in /) return 1 ;; esac                       # reached / with no boundary => fail
    if [ -n "$_hrhome" ]; then
      # A candidate that IS $HOME or an ancestor of $HOME is disqualified — BEFORE the boundary test,
      # so a repo at/above $HOME never scopes a home-or-wider find. Strictly-below or outside passes.
      case "$_hrhome/" in "$_hrd"/*) return 1 ;; esac
    fi
    if [ -e "$_hrd/.git" ] || [ -d "$_hrd/.claude" ]; then printf '%s' "$_hrd"; return 0; fi
    _hrd=$(dirname "$_hrd")
  done
}

# _hl_find_inode "<root>" "<ino>" — echo the names sharing <ino> under <root> (standard prune),
# guarded by a fail-safe WATCHDOG (reviewer I1, the durable class-closer). If the find exceeds
# KIT_HL_FIND_BUDGET seconds it is KILLED and this returns rc 1 (=> the engine fail-safes to a
# HIT/deny). `timeout(1)` is not portable (absent on macOS), so: the find runs in the background
# writing a trap-cleaned temp file; a DISARM-FLAG watchdog kills it on expiry and can never kill a
# REUSED pid (it checks the flag first). Any orphaned `sleep` self-terminates and finds its flag gone.
_hl_find_inode() {
  _hlf_root=$1; _hlf_ino=$2
  _hlf_tmp=$(mktemp 2>/dev/null) || return 1
  _hlf_arm="$_hlf_tmp.arm"; : > "$_hlf_arm" 2>/dev/null || { rm -f "$_hlf_tmp"; return 1; }
  # ⚠️ Both background jobs MUST detach ALL inherited fds (</dev/null >/dev/null 2>&1). This engine is
  # itself run inside a `$(...)` capture by the caller; a backgrounded job that inherits the capture's
  # stdout pipe holds it open, so `$(...)` blocks for the FULL budget even when find returns instantly
  # (measured: ~10s per check). find writes to its own temp file; the watchdog talks to no one.
  find "$_hlf_root" -xdev \
      \( -type d \( -path '*/.git/objects' -o -path '*/.git/lfs' -o -name node_modules \) \) -prune \
      -o -inum "$_hlf_ino" -print > "$_hlf_tmp" 2>/dev/null </dev/null &
  _hlf_fpid=$!
  ( sleep "${KIT_HL_FIND_BUDGET:-10}" 2>/dev/null; [ -f "$_hlf_arm" ] && kill "$_hlf_fpid" 2>/dev/null ) </dev/null >/dev/null 2>&1 &
  _hlf_wpid=$!
  if wait "$_hlf_fpid" 2>/dev/null; then _hlf_rc=0; else _hlf_rc=1; fi   # non-zero (error OR kill) => fail-safe
  rm -f "$_hlf_arm"                          # DISARM: an orphaned sleep now finds the flag gone (no PID-reuse kill)
  kill "$_hlf_wpid" 2>/dev/null || :         # best-effort reap of the watchdog subshell
  wait "$_hlf_wpid" 2>/dev/null || :
  if [ "$_hlf_rc" -eq 0 ]; then cat "$_hlf_tmp" 2>/dev/null; rm -f "$_hlf_tmp"; return 0; fi
  rm -f "$_hlf_tmp"; return 1
}

# _hardlink_alias_hit "<resolved>" "<root>" "<classifier-fn>" — the engine. Returns rc 0 in TWO cases,
# both of which the caller treats as a HIT (deny): a GENUINE hit echoes the (sanitized) offending path;
# a FAIL-SAFE hit echoes NOTHING (empty). rc 1 = no alias (ALLOW), echoes nothing. So the caller
# denies on rc 0 and picks its reason by whether the echoed name is non-empty (M1 — a DISTINCT
# fail-safe reason, true for what may be an ordinary file). Fail-safe fires on any tooling anomaly
# (stat/find cannot run, no root derivable, device mismatch, root at/above $HOME, or the find watchdog
# timing out) — over-denying a resolvable target rather than silently opening the alias route.
_hardlink_alias_hit() {
  _ha_res=$1; _ha_root=$2; _ha_cls=$3
  # 0. A hardlink requires an EXISTING file (a new-file Write, or an unresolved leaf, has no inode and
  #    no aliases) — so a non-existent target is NOT a hit here (the string matchers already judge its
  #    NAME). This must precede the stat fail-safe, or every write to a new path would over-deny.
  [ -e "$_ha_res" ] || return 1
  # 0b. GUARD-HL-REVIEW-FASTFOLLOW F1 — a DIRECTORY subject exits HERE, before the nlink pre-filter.
  #    Every directory has st_nlink >= 2 (`.` + its parent entry + one per subdir), so step 1's cheap
  #    exit NEVER fires for one; and guard.sh routes Grep/Glob `.tool_input.path` (usually a directory)
  #    through guard_check_read, so the agent's highest-frequency search tools were paying mktemp + a
  #    backgrounded repo-wide find + the watchdog subshell per call (~83ms measured).
  #    SOUNDNESS — scoped to the SUPPORTED filesystems (ext*/xfs/btrfs/APFS): POSIX link() on a
  #    directory is refused there, and BOTH classifier arms (is_control_plane_path, _is_secret_hit)
  #    only ever name FILES, so a directory can never be the hardlink alias of a CP/secret file — the
  #    skipped inode check is provably redundant for it. Legacy HFS+ DID allow directory hardlinks;
  #    that is disclosed in docs/operations/runtime-guards.md. A directory named at a control-plane
  #    path is still judged by the STRING matchers, which run outside this helper. Symlinked
  #    directories are unaffected (symlinks resolve BEFORE this helper, which takes the resolved path).
  #    The dir-swap-between-decision-and-write TOCTOU is §4 CEILING 2's existing class, not a new one.
  [ -d "$_ha_res" ] && return 1
  # 1. Fast pre-filter: link count. nlink<=1 => no alias => ALLOW (the subprocess-cheap common case).
  #    On an EXISTING target a count that cannot be parsed is anomalous and fails safe to a HIT.
  _ha_nl=$(_nlink_of "$_ha_res") || return 0
  [ "$_ha_nl" -le 1 ] 2>/dev/null && return 1
  # 2. The target's own (dev,ino). Fail-safe HIT if unreadable.
  _ha_di=$(_devino_of "$_ha_res") || return 0
  _ha_dev=${_ha_di%% *}; _ha_ino=${_ha_di##* }
  # 3. Root: the PASSED protected root (live hook — authoritative) else derive the NEAREST repo
  #    boundary strictly below $HOME (§2d). No derivable root fails safe to a HIT.
  if [ -z "$_ha_root" ]; then
    _ha_root=$(_hlink_repo_root "$_ha_res") || return 0
  fi
  # 3b. Cap the FINAL root — passed OR derived — at the PHYSICAL $HOME (LOW-1). A repo rooted AT $HOME
  #     (or above) would `find $HOME`; resolve the root physically and fail safe to a HIT there. The
  #     physical resolution also aligns the root with _res (both physical) for the scan below.
  _ha_root=$(CDPATH= cd "$_ha_root" 2>/dev/null && pwd -P) || return 0
  _hl_at_or_above_home "$_ha_root" && return 0
  # 4. Device coherence (vet C3, MEDIUM). A hardlink cannot cross devices, so any alias is on _res's
  #    device. If the root sits on a DIFFERENT device, do NOT skip (skip = no-hit = fail-OPEN): re-root
  #    at _res's own repo (re-capped); if that is still cross-device, fail safe to a HIT.
  _ha_rd=$(_devino_of "$_ha_root") || return 0
  if [ "${_ha_rd%% *}" != "$_ha_dev" ]; then
    _ha_root=$(_hlink_repo_root "$_ha_res") || return 0
    _ha_root=$(CDPATH= cd "$_ha_root" 2>/dev/null && pwd -P) || return 0
    _hl_at_or_above_home "$_ha_root" && return 0
    _ha_rd=$(_devino_of "$_ha_root") || return 0
    [ "${_ha_rd%% *}" = "$_ha_dev" ] || return 0
  fi
  # 5. Enumerate the inode's other names within the repo, on the one filesystem (-xdev), under the
  #    fail-safe find WATCHDOG (I1). PRUNE ONLY the internally-hardlinked BULK that never shares an
  #    inode with a worktree write-target: .git/objects, .git/lfs (vet C1 — the rest of .git, incl.
  #    config/hooks/refs, is control-plane and STAYS in scope) and node_modules (vet C2 — DISCLOSED
  #    residual). A find that errors OR exceeds the time budget fails safe to a HIT.
  _ha_names=$(_hl_find_inode "$_ha_root" "$_ha_ino") || return 0
  # 6. Classify each returned name whose DEVICE equals _res's (kills the inode-number-coincidence FP
  #    across devices). A genuine hit echoes the sanitized path (LOW-3: strip control chars, cap length
  #    — a newline in a filename would otherwise break the deny JSON).
  _ha_ofs=$IFS; IFS='
'
  for _ha_p in $_ha_names; do
    [ -n "$_ha_p" ] || continue
    _ha_pd=$(_devino_of "$_ha_p") || continue
    [ "${_ha_pd%% *}" = "$_ha_dev" ] || continue
    if "$_ha_cls" "$_ha_p"; then
      IFS=$_ha_ofs
      printf '%s' "$_ha_p" | tr -d '\000-\037\177' | cut -c1-200
      return 0
    fi
  done
  IFS=$_ha_ofs
  return 1
}

# Thin wrappers over the one engine (design §2b). BOTH forward the PASSED protected root ($2) — the
# live hook's root is authoritative and unsteerable, and using it avoids the home-walk DoS entirely
# (the engine only DERIVES when $2 is empty). The CP wrapper classifies with is_control_plane_path;
# the SECRET wrapper with _is_secret_hit (template exemption). When no root is passed (kit-guard CLI),
# the engine derives the NEAREST repo boundary strictly below the PHYSICAL $HOME.
_hardlink_alias_hit_cp()     { _hardlink_alias_hit "$1" "$2" is_control_plane_path; }
_hardlink_alias_hit_secret() { _hardlink_alias_hit "$1" "$2" _is_secret_hit; }

# guard_check_read "<file>": deny reading SECRET material into the agent's context (the read half of
# exfil, A8 family 6) — the secret then reaches the model provider / logs / a PR. Symmetric with the
# secret-WRITE deny in guard_check_path but NARROWER: it does NOT deny control-plane reads (reading the
# guard/CI to understand it is legitimate). Template env files (.env.example/.sample/.template/.dist)
# are allowed; a single file_path means `*.env.*` is safe here (no multi-arg form to abuse). Honest
# ceilings: an interpreter (python -c open()) bypasses the shell path, and jq-absent leaves Read allowed.
guard_check_read() {
  fp=$1
  # MEDIUM-1 (round 3): the live hook now threads its PROTECTED_ROOT here as $2, so the read-side
  # secret-inode check uses the AUTHORITATIVE, unsteerable root instead of always deriving (closes the
  # live-read planted-`sub/.git` steer). Empty $2 (kit-guard CLI) keeps the nearest-derive fallback.
  _gcr_root=${2:-}
  base=$(basename "$fp" 2>/dev/null || printf '%s' "$fp")
  # GUARD-PATH-ALIAS-BYPASS (P0): the read half was the variant proven reachable end to end — a
  # renamed symlink returned a planted secret's contents through the real Read tool. Same union
  # rule as the write side: allowlist on literal AND resolved; deny on literal OR resolved; a
  # failure to resolve is itself a denial. The allowlist below short-circuits before everything,
  # which is exactly why it must take the conjunction rather than either name alone.
  _rres=''; _rrok=0
  _rres=$(_resolve_physical "$fp") && _rrok=1 || _rrok=0
  _rrbase=''; [ "$_rrok" = 1 ] && _rrbase=$(basename "$_rres" 2>/dev/null || printf '%s' "$_rres")
  if ! selfedit_allowed && [ "$_rrok" = 0 ]; then
    printf '13: path (%s) could not be resolved - refusing to read a target that cannot be identified.' "$fp"; return 1
  fi
  # GUARD-CP-HARDLINK-ALIAS (§2b): the secret-INODE check goes BEFORE the template allowlist (vet
  # HIGH-1) — a single end-of-function placement would be dead code for the flagship cloak (a hardlink
  # named `.env.example` onto a real `.env` satisfies the conjunctive allowlist and returns ALLOW
  # first). Gated `! selfedit_allowed` only (there is no root on the read path; the wrapper derives it).
  # Reads of CONTROL-PLANE files stay legitimate, so the read side denies ONLY on a secret hit — this
  # closes the silent-exfil case a gate provably cannot catch. A non-empty name => a genuine secret
  # hardlink; empty => the engine's fail-safe (M1: a DISTINCT, true reason, not the secret-specific one).
  if ! selfedit_allowed && [ "$_rrok" = 1 ]; then
    if _hlnamed=$(_hardlink_alias_hit_secret "$_rres" "$_gcr_root"); then
      if [ -n "$_hlnamed" ]; then
        printf '13: this path is a hardlink to secret material (%s) - reading it is the read half of exfil, human-gated. The name it is reached by does not change what it reads.' "$_hlnamed"
      else
        printf '13: could not verify the target'\''s hardlink aliases (stat/find unavailable, timed out, or an ambiguous root) - denied fail-safe (refusing to read a target whose aliases cannot be confirmed). Remedy: usually an unreadable directory under the repo root, or a find that exceeded its time budget - make that directory searchable, or raise KIT_HL_FIND_BUDGET (seconds); see docs/operations/runtime-guards.md, section Hardlink aliases.'
      fi
      return 1
    fi
  fi
  case "$base" in
    .env.example|.env.sample|.env.template|.env.dist)
      case "$_rrbase" in
        .env.example|.env.sample|.env.template|.env.dist) return 0 ;;
      esac ;;
  esac
  if ! selfedit_allowed; then
    # GUARD-CP-HARDLINK-ALIAS §2c: the byte-literal + case-folded secret arms are consolidated into
    # _is_secret_path (one source of truth, byte-identity-coupled). The template ALLOW above stays
    # byte-literal (never folded), so a case-variant `.ENV.EXAMPLE` still falls through to this deny —
    # the existing accepted over-deny (design §3/§4a). Deny MESSAGE stays here (literal wording).
    if _is_secret_path "$fp"; then
      printf '13: reading secret material (%s) into context is the read half of exfil (-> model/logs/PR) - human-gated. Use .env.example / a secrets manager / redact; KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.' "$base"; return 1
    fi
    # …and the union on the RESOLVED target (both arms, via the same helper), so a benign name cannot
    # front a secret file.
    if [ "$_rrok" = 1 ] && _is_secret_path "$_rres"; then
      printf '13: this path resolves to secret material (%s) - reading it is the read half of exfil, human-gated. The name it is reached by does not change what it reads.' "$_rres"; return 1
    fi
  fi
  return 0
}

# --- CP-8a: leading-verb discipline -------------------------------------------------
# A segment's LEADING VERB decides whether its arguments are CODE or DATA. These two
# commands contain identical bytes; only the verb tells them apart:
#     bash -c "rm -rf /"          <- the argument is CODE   (a weapon)   -> must DENY
#     grep -rn "rm -rf" scripts/  <- the argument is DATA   (a search)   -> must ALLOW
# guard_read_only_command returns 0 ONLY for a command that is provably a SINGLE read-only
# invocation; for everything else the destructive matrix below runs UNCHANGED on the RAW
# command. It never rewrites or splits the command (see the closing note).
#
# INVARIANT (load-bearing): a verdict may only move DENY -> ALLOW when a safe lead is
# POSITIVELY RECOGNIZED. An unknown lead strips nothing, so behaviour is byte-for-byte
# today's. A bug here therefore fails CLOSED (over-denies), never OPEN.
#
# There is NO splitting: a shell metacharacter (; | & < > $ ( ) or backtick) ANYWHERE makes
# the whole command non-exempt outright. That is why a quoted separator cannot trick the
# exemption — it never parses the command into segments at all. Fail-closed.
#
# A segment is exempt ONLY if ALL of these hold:
#   1. it contains no < > $ ( ) or backtick — a redirect can truncate a file even under a
#      read verb (`echo -n > ci.yml`), and a command substitution smuggles code past it
#      (`grep foo $(rm -rf /)`). Unparseable => never exempt.
#   2. its first token carries no env-assignment (`GIT_EXTERNAL_DIFF=rm git diff`) and is not
#      a wrapper — the lead must be the verb itself, plainly.
#   3. that verb is in the STRICT set below: tools that write ONLY to stdout.
# The set deliberately EXCLUDES every tool with a write/exec escape, exactly as the WS1 note
# at guard_check_command already established — this is that vetted list, not a fresh one:
#   sed  (`s///e` EXECUTES the pattern space; `w file` writes one)
#   awk  (`system()`, `print > "file"`)
#   find (`-exec` / `-delete`)
#   sort (`-o file`)  ·  uniq (`uniq in out`)  ·  less/more (`!cmd`)  ·  xxd (`-r` writes)
# Admitting any of them would hand the guard an arbitrary-execution primitive to save a
# keystroke. `sed -n` stays denied; `head`/`tail` do the same job with no escape.
# `git` is admitted only on subcommands that cannot destroy (NOT push/reset/clean/checkout);
# `kit-guard` only on its read-only subcommands, so a guard slice can probe the guard.
# Returns 0 (exempt) ONLY for a command that is provably a SINGLE read-only invocation.
# It never REWRITES the command: on the non-exempt path the destructive matrix receives the
# raw string byte-for-byte, so not one of its ~40 rules has its assumptions perturbed. (An
# earlier draft split the command into segments and rejoined them with ';' — that destroyed
# the pipe `curl x | sh` detects and the end-of-string `--admin` anchors on, silently turning
# two DENY rules into ALLOW. Do not reintroduce rewriting.)
guard_read_only_command() {
  _c=$1
  # 1. ANY separator, redirect, substitution, expansion or backtick => not a simple, single
  #    invocation => never exempt. This is what makes the exemption safe rather than clever:
  #    `grep foo && rm -rf /`, `grep foo $(rm -rf /)`, `echo -n > ci.yml` all fail here.
  printf '%s' "$_c" | grep -q '[;|&<>$()`]' && return 1
  # 2. the leading verb, plainly: strip only whitespace and a leading backslash. An
  #    env-assignment prefix (`GIT_EXTERNAL_DIFF=rm git diff`) is not plainly a verb.
  _lead=$(printf '%s' "$_c" | sed -E 's/^[[:space:]]*\\?[[:space:]]*//; s/[[:space:]].*$//')
  _arg1=$(printf '%s' "$_c" | sed -E 's/^[[:space:]]*//; s/^[^[:space:]]+[[:space:]]+//; s/[[:space:]].*$//')
  case "$_lead" in
    *=*) return 1 ;;
    # 3. STRICT set: tools that write ONLY to stdout. Deliberately EXCLUDES every tool with a
    #    write/exec escape — exactly as the WS1 note below already established. This is that
    #    vetted list, not a fresh one:
    #      sed  (`s///e` EXECUTES the pattern space; `w file` writes one)
    #      awk  (`system()`, `print > "file"`)   ·  find (`-exec` / `-delete`)
    #      sort (`-o file`)  ·  uniq (`uniq in out`)  ·  less/more (`!cmd`)  ·  xxd (`-r`)
    #    Admitting any of them would hand the guard an arbitrary-execution primitive to save a
    #    keystroke. `sed -n` therefore stays denied; head/tail do the job with no escape.
    grep|egrep|fgrep|rg|ls|cat|head|tail|wc|diff|stat|du|cut|tr|nl|od|hexdump|column|tac|comm|cmp|basename|dirname|realpath|readlink|echo|printf|which|type)
      return 0 ;;
    git)
      # only subcommands that cannot destroy — NOT push/reset/clean/checkout.
      case "$_arg1" in
        # NOT diff|log|show — they honor --output=<file>, an arbitrary file WRITE via the
        # diff machinery (see the git --output deny in guard_check_command). commit|status|
        # blame|describe carry no such write flag.
        commit|status|blame|describe) return 0 ;;
      esac ;;
    kit-guard|*/kit-guard)
      # the guard's own read-only CLI, so a guard slice can probe the guard.
      # ⚠️ GUARD-READONLY-FP-RELIEF structural finding S2 (2026-08-19, measured both ways, security
      # vet L1): this clause is DEAD FOR CP-CLASSIFYING ARGUMENTS ONLY — STILL REQUIRED FOR BARE
      # `kit-guard` PROBING. `guard_read_only_command` runs at the bottom of `guard_check_command`,
      # AFTER the CP-8b control-plane block, so a `kit-guard path <control-plane-path>` has already
      # been decided (and, before Arm A, denied) by the time control reaches here — which is why
      # relief for that face is built in the CP arms (`_cp8b_tad_is_kit_query`) and NOT here.
      # The clause is LIVE for the far more common probe whose argument is a destructive command
      # rather than a path: `kit-guard cmd 'rm -rf /'` reaches this line and is exempted from the
      # destructive matrix by it. Deleting it would break guard self-probing outright.
      case "$_arg1" in
        cmd|path|mcp) return 0 ;;
      esac ;;
  esac
  return 1
}

# --- CP-8b: bind a verb/flag to its TARGET ------------------------------------------
# The block this replaces matched the CO-OCCURRENCE of a mutation verb and a control-plane path
# anywhere in the flat command string, and never asked whether the verb's TARGET was that path. Two
# symmetric faces of that one missing relation:
#   over-DENY : `cp conformance/x /tmp/b` (copying OUT) - both tokens present, so denied.
#   over-ALLOW: `git archive -o conformance/x` (a real write) - `git archive` is not a mutation verb,
#               and `mv conformance /tmp` (the BARE directory) - the path patterns all require a
#               trailing slash, so they match a file INSIDE the dir and never the dir ITSELF.
# See docs/architecture/2026-07-12-cp8-guard-ergonomics-design.md sections 7-13.
#
# INVARIANT (load-bearing, inherited from CP-8a): a verdict may move DENY -> ALLOW only where a safe
# shape is POSITIVELY RECOGNIZED. Every relaxation below is an allow-back from the existing deny floor;
# anything unrecognized keeps today's behavior. A bug here therefore fails CLOSED, never OPEN.

# bare control-plane DIRECTORY names, for TARGET matching only. is_control_plane_path is deliberately
# NOT widened: it also drives the Write/Edit path (guard_check_path), and this slice adds no blast
# radius there. `mv conformance/ /tmp` was already denied; `mv conformance /tmp` was not - and that one
# command relocates every gate in the repo.
# CASE-INSENSITIVE since A2, for the same reason as is_control_plane_path and via the same two-step:
# literal first (zero subprocesses for an all-lowercase target), fold only on an uppercase miss.
# Measured before the fix: `mv skills /tmp/x` -> DENY but `mv Skills /tmp/x` -> ALLOW, and on a
# case-insensitive filesystem that second command relocates the REAL skills/ directory — precisely the
# command the comment above exists to deny. is_control_plane_path does NOT cover these: its patterns
# are `skills/*`, which a bare directory name never matches.
is_control_plane_target() {
  is_control_plane_path "$1" && return 0
  # GUARD-CP-WRITE-ROUTES Cure 1 (Route 1): normalize the subject through _cp8b_norm (collapse
  # //, a /./ FIXPOINT, trailing /, leading ./, and .. traversal) before the exact-literal match,
  # so a redundant-syntax spelling (hooks//pre-push, hooks/./pre-push, hooks/./././pre-push,
  # x/../hooks/pre-push) can no longer evade it. The normalized value feeds is_control_plane_path
  # AS WELL AS _ctm_match: the Route-1 exploit targets are FILES (hooks/pre-push, scripts/kit-guard,
  # scripts/dora.sh) matched ONLY by is_control_plane_path — _ctm_match is bare-DIRECTORY names, so
  # feeding _ctm_match alone would leave the file route open (K-N1b pins this line). Canonical-only:
  # normalization collapses redundant syntax, it never reclassifies a genuinely-ordinary path.
  _ct=$(_cp8b_norm "$1")
  is_control_plane_path "$_ct" && return 0
  _ctm_match "$_ct" && return 0
  case "$_ct" in
    *[A-Z]*) _ctm_match "$(printf '%s' "$_ct" | LC_ALL=C tr 'A-Z' 'a-z')" && return 0 ;;
  esac
  # GUARD-DENY-TRIO M1: a glob-spelled target whose literal prefix segment-intersects a protected leaf
  # (`hooks/pre-pus*`, `AGENTS.m*`, `agents/*.agent.m*`) is a write to a governing file. Reached from the
  # write-verb route (_cp8b_cp_target_in), the combined-redirect route (_cp8b_tad_redir_cp /
  # _cp8b_redirect_hits_cp) and the bare-token walk (_cp8b_tok_is_cp) — one site covers all. Reads never
  # reach here (read verbs' args are data). Fast-exits on a metachar-free target, so ordinary paths and
  # the hot path are untouched; the broad-glob relief (`*`, `docs/*`, `build/out-*`) survives inside it.
  _cp8b_glob_hits_cp "$1" && return 0
  return 1
}

# Bare control-plane DIRECTORY names, LOWERCASED (see the _cpp_match warning: an uppercase byte in any
# pattern here can never match a folded subject and would silently un-protect that directory).
#
# ⚠️ THIS IS THE FOURTH MATCHER, AND IT IS THE ONE A NEW DIRECTORY FAMILY IS MOST LIKELY TO MISS.
# The C5 completeness discipline names THREE matcher sites (`is_control_plane_path` + the two pathhit
# regex tiers); this list is a fourth, and it is invisible from all three because it holds BARE
# directory names — `is_control_plane_path`'s patterns are `profiles/*`, which a bare `profiles` never
# matches. GUARD-PATH-ENUMERATION-INCOMPLETE S1 shipped the `profiles/` family through the three named
# sites and left this one out; measured on the shipped build, `mv profiles /tmp/x` and
# `chmod -R 777 profiles` both ALLOWED while every file inside `profiles/` denied. That is the exact
# hole the `mv conformance /tmp` note above records, reopened for a new family one release later: a
# family is only as protected as its least-protected route, and the single command that relocates the
# whole directory is the one worth the most to an attacker. ANY future directory family must be added
# HERE as well as to `_cpp_match` and both pathhit tiers — four sites, not three.
_ctm_match() {
  case "$1" in
    conformance|skills|adapters|agents|scripts|profiles|hooks|.claude|.github|.git|.kit|\
    */conformance|*/skills|*/adapters|*/agents|*/scripts|*/profiles|*/hooks|*/.claude|*/.github|*/.git|*/.kit)
      return 0 ;;
  esac
  return 1
}

# GUARD-DENY-TRIO M1 — close the glob-spelled write-route evasion by LITERAL-PREFIX-ANCHORED,
# SEGMENT-SAFE disqualification (design docs/architecture/2026-08-18-guard-deny-trio-design.md §3,
# D-240816-1). A write-verb argument or combined-redirect target spelled as a glob (`hooks/pre-pus*`,
# `AGENTS.m*`, `agents/*.agent.m*`) evades the exact-literal pathhit corpus: `hooks/pre-push` is a
# full-filename leaf, so `hooks/pre-pus*` matches no exact pattern and ALLOWs. The cure denies a glob
# token IFF, after Cure-1 normalization, its NON-EMPTY literal prefix segment-intersects a protected
# leaf. NOT the naive `case "<leaf>" in <token>)` (design H-1, REJECTED): POSIX `case` lets `*` cross
# `/`, so that shape denies `cp x.txt docs/*` (`docs/*` would match `docs/governance/…`). The SLASH-COUNT
# guard in _cp8b_glob_scan is the H-1 lock — token and leaf must have equal slash counts, which makes a
# `*` unable to consume a `/`, so the match is per-segment even though POSIX `case` is used.
#
# _CP8B_GLOB_LEAVES is the residual pathhit-T1 leaf set (the SAME protected NAMES is_control_plane_path
# classifies — NOT a new enumeration of glob spellings, the D-240816-1 trap — the existing leaf NAMES
# re-consulted prefix-wise). Directory-family members (.claude/ .github/ .git/ conformance/ skills/
# adapters/ scripts/ profiles/) are DELIBERATELY ABSENT: a glob under them already pathhits
# (`skills/[^space]*` matches `skills/foo*`), so they need no prefix consult. `agents/*.agent.md` is
# the one glob-shaped leaf (agents/ is not a directory family — only `agents/*.agent.md` is protected),
# kept as a glob and matched by _cp8b_glob_scan's DIRECTIONAL branch (§10 A3), NOT a raw `case` — a
# raw `case "$leaf" in $token)` under-matched every CONCRETE-name glob (`agents/reviewer.agent.m*`).
# A selftest cross-checks every entry is
# is_control_plane_path-classified, binding this list to the authoritative corpus so it cannot drift to
# a non-CP name. ⚠️ A NEW full-filename CP leaf OUTSIDE a directory family must be added HERE too — this
# is the glob-write route's site, a FIFTH alongside the is_control_plane_path/_ctm_match/two-pathhit
# sites the C5 completeness discipline already names. `_LC` mirrors _CP8B_PATHHIT_T1_LC: a lowercased
# copy consulted on an uppercase-token miss (so `CODEOWNER*`, `AGENTS.m*`, `REQUIRED-CHECKS.m*` fold),
# authored lowercase to match a folded subject.
# ⚠️ ADOPTER-SAFETY CONSTRAINT (what _cp8b_glob_scan actually requires): a PATTERN leaf must be
# single-dir-segment with the `*` in the FINAL path segment (the `dir/*.ext` shape, e.g.
# `agents/*.agent.md`). A leaf with the glob NOT last, or a multi-segment-deep protected family, is NOT
# covered by _cp8b_glob_scan and would silently UNDER-match — add such a family to the pathhit tiers /
# _cpp_match instead, or extend _cp8b_glob_scan first. (The nested-depth residual is §10 A5.)
_CP8B_GLOB_LEAVES='hooks/pre-push docs/governance/meta-control-log.md docs/governance/.meta-control-last CODEOWNERS AGENTS.md REQUIRED-CHECKS.md .gitattributes .gitleaks.toml .gitleaksignore .semgrepignore .trivyignore .checkov.yaml .checkov.yml .kit/budget.conf .kit/roster.conf .kit/model-tiers.conf .kit/model-map.conf .kit/dials.conf agents/*.agent.md'
_CP8B_GLOB_LEAVES_LC='hooks/pre-push docs/governance/meta-control-log.md docs/governance/.meta-control-last codeowners agents.md required-checks.md .gitattributes .gitleaks.toml .gitleaksignore .semgrepignore .trivyignore .checkov.yaml .checkov.yml .kit/budget.conf .kit/roster.conf .kit/model-tiers.conf .kit/model-map.conf .kit/dials.conf agents/*.agent.md'

# _cp8b_glob_scan "<token>" "<leaf-list>": 0 iff <token> (a glob pattern, already normalized/folded)
# segment-safe intersects a leaf. Slash-count equality per leaf (pure parameter-expansion counter, no
# fork) forbids `*` from crossing `/`. TWO leaf shapes:
#   • CONCRETE leaf (no metachar): `case "$leaf" in $token)` — the token-glob matches the literal leaf.
#   • PATTERN leaf (`agents/*.agent.md`, carrying its OWN `*`): the raw `case` above UNDER-matches — a
#     literal `*` in the SUBJECT aligns only a token whose metachar sits at the same spot, so a
#     CONCRETE-name glob like `agents/reviewer.agent.m*` (which expands onto the real `.agent.md` file)
#     slipped (GUARD-DENY-TRIO §10 A3, both review seats). Instead do a DIRECTIONAL glob-intersection:
#     split the leaf at its `*` into LP (`agents/`) and LS (`.agent.md`); the token DENIES iff its
#     DIRECTORY segment glob-intersects the leaf's literal dir (leaf-dir as SUBJECT / token-dir as
#     PATTERN, so a dir metachar like `ag*`/`agent?`/`agen[t]s` that expands onto `agents/` still
#     commits — §10 A4) AND its BASENAME COMMITS ITS LITERAL to LS — some suffix that STARTS WITH LS's
#     first byte glob-matches LS (`case "$LS" in <suffix>)`). The starts-with-LS[0] anchor is the
#     non-overshoot lock: a bare trailing `*` never starts with `.`, so `agents/foo*` and
#     `ag*/notes.txt` (broad globs that do NOT spell `.agent…`) stay ALLOW — `agents/` is NOT a blanket
#     CP prefix; only the `*.agent.md` family is. slash-count equality keeps both single-segment (no
#     `*` crosses `/`). The leaf word-split runs under `set -f`.
_cp8b_glob_scan() {
  _gsn=0; _gsr=$1; while : ; do case "$_gsr" in */*) _gsn=$((_gsn+1)); _gsr=${_gsr#*/} ;; *) break ;; esac; done
  _gsg=0; case "$-" in *f*) _gsg=1 ;; esac
  set -f
  # shellcheck disable=SC2086  # deliberate word-split of the leaf list; globbing disabled above
  for _gl in $2; do
    _gln=0; _glr=$_gl; while : ; do case "$_glr" in */*) _gln=$((_gln+1)); _glr=${_glr#*/} ;; *) break ;; esac; done
    [ "$_gsn" = "$_gln" ] || continue
    case "$_gl" in
      *[*?[]*)
        # PATTERN leaf: directional glob-intersection (see header). Split the leaf at its first metachar
        # into LP (dir, incl trailing /) and LS (literal suffix); split the TOKEN at its LAST / into a
        # directory segment and a basename.
        _glp=${_gl%%[*?[]*}; _gls=${_gl#*[*?[]}
        case "$1" in */*) _gtd=${1%/*}; _gtb=${1##*/} ;; *) continue ;; esac
        # The token's DIRECTORY segment must glob-INTERSECT the leaf's literal dir (leaf-dir as SUBJECT,
        # token-dir as PATTERN — the concrete-leaf branch's own shape), so a DIR-segment metachar
        # (`ag*`, `agent?`, `agen[t]s`) that expands onto `agents/` still commits. The first A3 cut
        # anchored LP as a LITERAL (`case "$1" in "$LP"*`) and evaded on exactly those spellings
        # (§10 A4). slash-count equality already bounds both to a single dir segment, so POSIX `*`
        # cannot cross a `/` here — no H-1 over-deny (`ag*/notes.txt` stays ALLOW via the LS test below).
        # shellcheck disable=SC2254  # $_gtd is a DELIBERATE glob pattern (the token's dir segment)
        case "${_glp%/}" in $_gtd) : ;; *) continue ;; esac
        # …AND the token's BASENAME must COMMIT its literal to LS: some suffix that STARTS WITH LS's
        # first byte glob-matches LS. The starts-with-LS[0] anchor is the non-overshoot lock — a bare
        # trailing `*` never starts with `.`, so `<dir>/notes.txt` and `<dir>/foo*` stay ALLOW.
        _gl0=${_gls%"${_gls#?}"}
        _gss=$_gtb
        while [ -n "$_gss" ]; do
          case "$_gss" in
            "$_gl0"*)
              # shellcheck disable=SC2254  # $_gss is a DELIBERATE glob pattern (a token-basename suffix)
              case "$_gls" in $_gss) [ "$_gsg" = 1 ] || set +f; return 0 ;; esac ;;
          esac
          _gss=${_gss#?}
        done ;;
      *)
        # shellcheck disable=SC2254  # $1 is a DELIBERATE glob pattern (the proposed write token)
        case "$_gl" in
          $1) [ "$_gsg" = 1 ] || set +f; return 0 ;;
        esac ;;
    esac
  done
  [ "$_gsg" = 1 ] || set +f
  return 1
}

# _cp8b_glob_hits_cp "<token>": 0 (DENY) iff <token> is a glob whose non-empty literal prefix segment-
# intersects a _CP8B_GLOB_LEAVES member. Fast-exits on the common no-metachar token (one `case`), so the
# hot path pays nothing; only a glob-bearing write/redirect target runs the scan. Cure-1 normalization
# runs BEFORE the prefix test (design H-2), so `./hooks/pre-pus*` (leading `./` stripped) and
# `hooks//pre-pus*` (// collapsed) deny like `hooks/pre-pus*`. An EMPTY literal prefix (bare `*`, or
# `./*` -> `*` after norm) never denies — the broad-glob relief (`*`, `docs/*`, `cp x.txt ./*`).
_cp8b_glob_hits_cp() {
  case "$1" in *[*?[]*) : ;; *) return 1 ;; esac      # no glob metachar -> not this predicate
  _gt=$(_cp8b_norm "$1")
  case "${_gt%%[*?[]*}" in '') return 1 ;; esac        # empty literal prefix -> ALLOW (bare * / ./*)
  _cp8b_glob_scan "$_gt" "$_CP8B_GLOB_LEAVES" && return 0
  case "$_gt" in *[A-Z]*) : ;; *) return 1 ;; esac      # fold only on an uppercase byte (mirrors :93)
  _cp8b_glob_scan "$(printf '%s' "$_gt" | LC_ALL=C tr 'A-Z' 'a-z')" "$_CP8B_GLOB_LEAVES_LC"
}

# _cp8b_joinlines: collapse backslash-newline CONTINUATIONS to a space. A continuation is NOT a command
# separator, and grep is LINE-oriented: `git push \<nl> origin main` puts `push` and `main` on different
# lines, so the flat push rule's regex matches neither (a pre-existing hole). Join first, split second.
_cp8b_joinlines() {
  printf '%s\n' "$1" | sed -e :a -e '/\\$/N; s/\\\n/ /; ta'
}

# _cp8b_segments "<cmd>": print one segment per line (split on ; && || | & and newline).
# Used ONLY by the CP-8b logic below. It is NEVER fed back into the destructive matrix, which keeps
# seeing the raw, unsplit string. (CP-8a: an earlier draft split the command and REJOINED it with ';',
# which destroyed the pipe `curl x | sh` detects and the end-of-string `--admin` anchors on, silently
# turning two DENY rules into ALLOW. Nothing is rejoined here.)
# A separator inside a quoted string over-splits into a bogus segment whose lead is unrecognized ->
# scan-and-deny. Over-DENY, fail-closed - and identical to today's verdict.
# GUARD-DENY-TRIO M1 (fd-dup/combined-redirect half): the `&` of a REDIRECT operator (`>&`, `&>`,
# `2>&`, `>>&`) is NOT a command separator and must not split the command. Before this, `s/&/;/g`
# turned `echo x >&conformance/verify.sh` into `echo x >` + `conformance/verify.sh`, orphaning the
# redirect TARGET into a bare segment that the kit-exec recognizer then read as "running the script" and
# ALLOWED — a combined-redirect WRITE laundered as a command. (The boarded GUARD-REDIRECT-FD-DUP-
# COMBINED-BYPASS mechanism, absorbed here.) The design named `_redir_targets`' `&`-exclusion as the
# fix, but the split happens HERE first, so `_redir_targets` never saw `>&word`; both must change. A
# redirect `&` is protected via the _cp8b_soh sentinel across the `&`->`;` pass, then restored, so ONLY
# a true separator `&` (background/`&&` already collapsed above) splits. fd-dups (`2>&1`, `>&-`) keep
# their `&` and stay one segment — _redir_targets then classifies them (numeric/`-` => excluded).
_cp8b_soh=$(printf '\001')
_cp8b_segments() {
  _cp8b_joinlines "$1" \
    | sed -e 's/&&/;/g' -e 's/||/;/g' -e 's/|/;/g' \
          -e "s/>&/>$_cp8b_soh/g" -e "s/&>/$_cp8b_soh>/g" \
          -e 's/&/;/g' \
          -e "s/$_cp8b_soh/\&/g" \
    | tr ';\n' '\n\n'
}

# _cp8b_unparseable "<seg>": 0 iff the segment carries a construct the guard CANNOT resolve to the bytes
# the shell will actually execute: $VAR, $(...), `...`, <(...). The guard reads PRE-shell-parse bytes;
# the tool acts POST-parse. Such a segment is NEVER relaxed - and, for a git WRITE subcommand, is denied
# OUTRIGHT (see _cp8b_git_write_denied). That is the attack this closes:
#     git archive -o $(echo conformance/verify.sh) HEAD
# would otherwise slip BOTH the target-bind (target unresolvable) AND the co-occurrence floor
# (`git archive` is not a mutation verb). A bare '(' is NOT unparseable - a subshell's lead token is
# unrecognized and already fails closed - so conventional-commit subjects like "fix(guard): ..." parse.
_cp8b_unparseable() {
  printf '%s' "$1" | grep -q '[$`]' && return 0
  printf '%s' "$1" | grep -q '<(' && return 0
  return 1
}

# _cp8b_lead "<seg>": the leading verb, plainly. An env-assignment prefix (`GIT_EXTERNAL_DIFF=rm git
# diff`) yields a token containing '=', which matches no verb set -> unknown -> fail closed.
_cp8b_lead() {
  printf '%s' "$1" | sed -E 's/^[[:space:]]*\\?[[:space:]]*//; s/[[:space:]].*$//'
}

# _cp8b_dequote "<tok>": strip quote/escape bytes; for --flag=value / of=value forms, yield the VALUE.
# Safe in THIS DIRECTION ONLY: stripping normalizes TOWARD the real path, so --output="conformance/x"
# -> conformance/x -> matches -> DENY. It is NOT general shell parsing; $VAR and $(...) are
# unrecoverable, which is exactly why _cp8b_unparseable REFUSES them rather than parsing them badly.
# (CP-8a's review broke a target-parse whose failure direction was OPEN. Here unparseability is caught
# first and routed to deny, so what remains is a byte-match on a de-quoted literal whose worst case is
# an over-match -> over-DENY -> closed.)
_cp8b_dequote() {
  printf '%s' "$1" | sed -e "s/'//g" -e 's/"//g' -e 's/\\//g'
}

# _cp8b_tok_is_cp "<tok>": 0 iff the token, de-quoted and stripped of a flag= prefix, is a control-plane
# target.
_cp8b_tok_is_cp() {
  _tt=$(_cp8b_dequote "$1")
  case "$_tt" in *=*) _tt=${_tt#*=} ;; esac
  [ -n "$_tt" ] || return 1
  is_control_plane_target "$_tt"
}

# _cp8b_cp_target_in "<mode>" "<seg>": 0 iff a control-plane TARGET appears among the segment's argument
# tokens.
#   mode=all  - EVERY non-flag token is a target: rm/rmdir/shred/truncate/chmod/chown/tee/patch/dd/sed;
#               mv/rsync (whose SOURCE is destroyed too - which is what catches `mv conformance /tmp`);
#               and ln (which creates a WRITABLE ALIAS to its source - see the dispatch rationale below).
#   mode=last - only the LAST non-flag token is a target: cp/install, which copy CONTENT, so their source
#               is merely READ. This is what makes `cp conformance/verify.sh /tmp/b.sh` (copying OUT)
#               legitimate. A destination-naming flag (-t/--target-directory) is bound explicitly below,
#               in EITHER mode, because it inverts the positional heuristic.
# Globbing is disabled around the word-split so `rm *.sh` cannot expand against the real filesystem.
_cp8b_cp_target_in() {
  _m=$1
  _pg=0; case "$-" in *f*) _pg=1 ;; esac
  set -f
  # shellcheck disable=SC2086  # deliberate word-splitting; globbing disabled above
  set -- $2
  [ $# -gt 0 ] && shift          # drop the leading verb
  _hit=1; _last=''
  while [ $# -gt 0 ]; do
    case "$1" in
      # A destination-naming flag INVERTS the positional heuristic: `cp -t <dir> <src>` and
      # `--target-directory=<dir>` make <dir> the destination even though it is not the last token.
      # Bind it explicitly (any mode) - otherwise the "last token" rule checks the SOURCE and misses
      # the real write target. This is the same flag-binding as `git worktree add -b`. install/ln share
      # -t/--target-directory. A bare `-t` without a value is a malformed command -> nothing to bind.
      -t|--target-directory)
        if [ $# -ge 2 ]; then
          _dt=$(_cp8b_dequote "$2")
          [ -n "$_dt" ] && is_control_plane_target "$_dt" && { _hit=0; break; }
          shift
        fi
        shift; continue ;;
      # Joined short form (`-tconformance`) and abbreviated/`=`-joined long forms (`--target-di=…`,
      # `--target-directory=…`). GNU getopt honors a joined short-option value and any UNAMBIGUOUS long
      # prefix, so a partial match here is not paranoia - it is the exact evasion the security review
      # demonstrated. For cp/ln/install, `--target-d…` is unambiguous (no other `--target-*` option), so
      # matching the family closes the hole without a per-tool option table.
      # CAVEAT (verb-set-coupled): this `--target-d*` match is safe only because NO verb currently routed
      # here (cp/install/mv/rsync/rm/rmdir/shred/truncate/chmod/chown/tee/patch/dd/sed/ln) carries a
      # distinct `--target-d*` option. If a future verb with one is added to these groups, revisit.
      -t?*)
        _dt=$(_cp8b_dequote "${1#-t}")
        _dt=${_dt#=}
        [ -n "$_dt" ] && is_control_plane_target "$_dt" && { _hit=0; break; }
        shift; continue ;;
      --target-d*=*)
        _dt=$(_cp8b_dequote "${1#*=}")
        [ -n "$_dt" ] && is_control_plane_target "$_dt" && { _hit=0; break; }
        shift; continue ;;
      --target-d*)
        if [ $# -ge 2 ]; then
          _dt=$(_cp8b_dequote "$2")
          [ -n "$_dt" ] && is_control_plane_target "$_dt" && { _hit=0; break; }
          shift
        fi
        shift; continue ;;
      -*) shift; continue ;;     # any other flag is not a path target
    esac
    _d=$(_cp8b_dequote "$1")
    case "$_d" in *=*) _d=${_d#*=} ;; esac
    if [ -n "$_d" ]; then
      _last=$_d
      if [ "$_m" = all ] && is_control_plane_target "$_d"; then _hit=0; break; fi
    fi
    shift
  done
  if [ "$_m" = last ] && [ "$_hit" = 1 ] && [ -n "$_last" ] && is_control_plane_target "$_last"; then
    _hit=0
  fi
  [ "$_pg" = 1 ] || set +f
  return $_hit
}

# _cp8b_git_sub "<seg>": the git subcommand, after skipping GLOBAL options. Empty if unresolvable
# (an unknown global option) -> the caller fails closed. A subcommand is a token in COMMAND POSITION:
# you cannot quote your way into `git commit` actually being `git diff`, which is why binding to the
# SUBCOMMAND is sound where CP-8a's review proved binding to the TARGET was not.
_cp8b_git_sub() {
  _pg=0; case "$-" in *f*) _pg=1 ;; esac
  set -f
  # shellcheck disable=SC2086
  set -- $1
  [ $# -gt 0 ] && shift          # drop `git`
  _gs=''
  while [ $# -gt 0 ]; do
    case "$1" in
      -c|-C|--git-dir|--work-tree|--exec-path|--namespace)
        [ $# -ge 2 ] || break
        shift 2; continue ;;
      --git-dir=*|--work-tree=*|--exec-path=*|--namespace=*)
        shift; continue ;;
      -p|--paginate|--no-pager|--bare|--no-replace-objects|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs)
        shift; continue ;;
      -*) _gs=''; break ;;       # an unknown global option -> unresolvable -> fail closed
      *)  _gs=$1; break ;;
    esac
  done
  [ "$_pg" = 1 ] || set +f
  printf '%s' "$_gs"
}

# _cp8b_git_target_is_cp "<sub>" "<seg>": 0 iff the git WRITE subcommand's own destination is a
# control-plane target. Each subcommand names its destination differently - that is the whole point of
# target-binding, and why a flat regex could never do this.
_cp8b_git_target_is_cp() {
  _gsub=$1
  _pg=0; case "$-" in *f*) _pg=1 ;; esac
  set -f
  # shellcheck disable=SC2086
  set -- $2
  _hit=1; _seen=0
  case "$_gsub" in
    archive)
      # `git archive` writes a file ONLY via -o / --output; without it, it streams to stdout.
      # Separated (`-o x`), `=`-joined (`-o=x`, `--output=x`), and short-JOINED (`-ox`) forms all bind.
      while [ $# -gt 0 ]; do
        case "$1" in
          -o|--output)
            if [ $# -ge 2 ] && _cp8b_tok_is_cp "$2"; then _hit=0; break; fi ;;
          --output=*)
            if _cp8b_tok_is_cp "$1"; then _hit=0; break; fi ;;
          -o?*)
            _ov=$(_cp8b_dequote "${1#-o}"); _ov=${_ov#=}
            [ -n "$_ov" ] && is_control_plane_target "$_ov" && { _hit=0; break; } ;;
        esac
        shift
      done ;;
    bundle|worktree)
      # `git bundle create <file> <rev>` · `git worktree add [-b <branch>] <path> [<commit>]`.
      # Scan EVERY non-flag token after the marker, not just the first: a flag that takes a VALUE
      # (`git worktree add -b br conformance/wt`) consumes the first slot, so a "first non-flag token"
      # heuristic checks `br` and never sees the real path. Over-scanning can only ADD denies.
      # Only `create`/`add` write into a new path; bundle verify/list and worktree list/prune do not.
      # (The orchestrator uses `git worktree add /tmp/…` on every fan-out, so this MUST stay allowed
      # outside the control plane — corpus family D locks that.)
      while [ $# -gt 0 ]; do
        if [ "$_seen" = 1 ]; then
          case "$1" in
            -*) : ;;
            *) if _cp8b_tok_is_cp "$1"; then _hit=0; break; fi ;;
          esac
        fi
        case "$1" in create|add) _seen=1 ;; esac
        shift
      done ;;
    init|clone|checkout|restore)
      # init: [<dir>] · clone: <src> <dir> · checkout/restore: pathspecs (they OVERWRITE the worktree).
      # Any non-flag token naming a control-plane path is a write target. `git checkout -b fix/x` has
      # no such token -> allowed (the A4 false positive).
      [ $# -gt 0 ] && shift      # drop `git`
      [ $# -gt 0 ] && shift      # drop the subcommand
      while [ $# -gt 0 ]; do
        case "$1" in
          -*) : ;;
          *) if _cp8b_tok_is_cp "$1"; then _hit=0; break; fi ;;
        esac
        shift
      done ;;
  esac
  [ "$_pg" = 1 ] || set +f
  return $_hit
}

# _cp8b_git_write_denied "<seg>": PREDICATE - returns 0 (TRUE, "deny this") and prints the reason, or 1
# (allow). Note the inverted convention vs. the guard_check_* API: this is an internal predicate, named
# so at the call site.
#
# `-o` is --output (a WRITE) for `git archive` and --only (a READ) for `git commit`. That ambiguity is
# why the flat rule could not resolve it, and why `git commit -m "... --output ..."` was a false
# positive (CP-8a's recorded residual). Subcommand-binding resolves it.
_cp8b_git_write_denied() {
  _ws=$1
  [ "$(_cp8b_lead "$_ws")" = git ] || return 1
  _wsub=$(_cp8b_git_sub "$_ws")
  case "$_wsub" in
    archive|bundle|worktree|init|clone|checkout|restore) : ;;
    diff|log|show|format-patch)
      # The diff machinery honors --output=<file>: an arbitrary file WRITE/TRUNCATE with NO shell
      # redirect, which slips every redirect guard. Denied OUTRIGHT - NO target is parsed, because a
      # quoted / escaped / substituted target evades a byte match while git writes the real path (a live
      # bypass caught in CP-8a re-review). Unchanged from CP-8a; only its SCOPE narrows, from "any git"
      # to "the subcommands that actually honor the flag".
      # Match --output (space/=/joined) AND -o (space, or JOINED value `-oconformance`). This is an
      # OUTRIGHT deny with no target parsed, so a joined value cannot smuggle a write past it.
      if printf '%s' "$_ws" | grep -Eq '(^|[[:space:]])(--output([=[:space:]]|$)|-o([[:space:]]|$|[^[:space:]]))'; then
        printf '13: git %s --output/-o writes an arbitrary file via the diff machinery (defeats the shell-redirect guards) - human-gated. Redirect to a non-control-plane path instead (git diff > /tmp/x), or KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.' "$_wsub"
        return 0
      fi
      return 1 ;;
    *) return 1 ;;
  esac
  # A write subcommand. Unparseable target => we CANNOT prove it lands outside the control plane => DENY
  # OUTRIGHT (fail-closed). See _cp8b_unparseable for why this specific clause is the attack surface.
  if _cp8b_unparseable "$_ws"; then
    printf '13: git %s with an unresolvable (variable/substituted) target cannot be proven to land outside the control plane - denied (fail-closed). Use a literal path, or KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.' "$_wsub"
    return 0
  fi
  if _cp8b_git_target_is_cp "$_wsub" "$_ws"; then
    printf '13: git %s would write into the control plane (guard / CI gates / conformance) - denied (control-plane integrity). Target a path outside the control plane, or KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.' "$_wsub"
    return 0
  fi
  return 1
}

# _cp8b_scan_denied "<seg>": PREDICATE - today's CO-OCCURRENCE rule, applied to ONE segment. This is the
# fail-closed floor for every segment whose lead is an interpreter, a wrapper, or simply unrecognized.
# Extended in exactly one direction - it now also matches a BARE control-plane directory token - which
# can only ADD denies (monotone).
# _cp8b_redirect_hits_cp "<segment>": does any REDIRECT TARGET in this segment land on a control-plane
# path? Derived from is_control_plane_path / is_control_plane_target — the SINGLE SOURCE OF TRUTH —
# rather than a second, hand-maintained inventory.
#
# WHY: the redirect arm used to carry its own regex alternation listing control-plane paths. It drifted
# from the classifier by construction, and the drift was measured: `echo evil > scripts/dora.sh`,
# `> scripts/agent-scorecard.sh`, `> scripts/new-adapter.sh`, `> scripts/postmortem.sh`,
# `> scripts/sparkwright`, `> scripts/fixtures/*` and three more were ALLOWED while classifying
# control-plane at the gate. Adding names closed nine and left nine — "a named set with no
# family-completeness lock rots by construction". Deriving the answer cannot drift.
#
# Targets are extracted after `>` or `>>`, with any fd digit and surrounding whitespace stripped, and
# quotes removed so `> "conformance/x.sh"` is seen. Case folding is inherited from the classifier.
# _redir_targets "<segment>": GUARD-CP-WRITE-ROUTES Cure 2 (Route 2) — the SHARED redirect-target
# EXTRACTION + POSITIVE literal-path allowlist disqualifier, called by BOTH redirect bail sites
# (_cp8b_redirect_hits_cp and _cp8b_tad_redir_cp) so the extraction and the disqualifier cannot drift.
# Each caller keeps its OWN classification loop (composed-vs-plain); this helper only produces the
# candidate literal targets and signals a disqualifying non-literal.
#
# Prints each SAFE (allowlist-clean) target on its own line. Return code:
#   0 = clean — every extracted target is a plain literal (or an fd-dup, which is excluded);
#   2 = a NON-LITERAL target was seen — the caller MUST bail to the deny side (fail-closed): the
#       guard cannot prove an unresolvable $(…)/$VAR/glob/backslash target is not control-plane.
# THE DISQUALIFIER IS A POSITIVE ALLOWLIST, not a bad-byte denylist: a target is recognized safe ONLY
# if every byte is in `[A-Za-z0-9._/@:+=,-]`; anything else ($ backtick * ? [ { ~ \ space etc.)
# disqualifies. A denylist lost twice here — `$`/backtick failed open on globs, an 8-byte set failed
# open on backslash (`hooks\/pre-push`). The allowlist closes the class definitively.
# fd-dups (`2>&1`, `>&2`, `N>&M`) extract to `&N` tokens, and an `&`-led token is EXCLUDED from the
# scan — otherwise a naive allowlist would spuriously disqualify legitimate fd-dups (over-deny).
# DISCLOSED RESIDUAL, not masked (security seat C1, MED): the `&`-exclusion is BROADER than true
# fd-dups. bash's `>&<word>` combined-redirect with a NON-NUMERIC word writes a FILE, but its
# `&<word>` token is `&`-led and so is dropped here too — meaning `_redir_targets` NEVER scans a
# combined-redirect target. A combined-redirect to a control-plane target is therefore not caught by
# THIS arm; it is only ever denied when another arm (the pathhit substring / token walk) independently
# catches the literal, so a spelling that evades those would slip through as an ALLOWED CP-write. This
# is PRE-EXISTING (the old extraction produced the same `&`-led token) and OUTSIDE the two routes this
# slice closes; the functional cure is boarded as its own deny-side slice,
# GUARD-REDIRECT-FD-DUP-COMBINED-BYPASS. Named here so the `&`-exclusion cannot read as complete.
# The split runs under `set -f` (globbing off) with the caller's `-f` state restored, so a `*` target
# is judged as raw text before any pathname expansion.
_redir_targets() {
  case "$1" in *'>'*) : ;; *) return 0 ;; esac
  _rt=$(printf '%s' "$1" | tr '\n' ' ' | sed -e 's/[0-9]*>>*/\n/g' | sed -e '1d' \
        -e 's/^[[:space:]]*//' -e 's/[[:space:]].*$//' -e 's/^["'"'"']//' -e 's/["'"'"']$//')
  [ -n "$_rt" ] || return 0
  _rtc=0
  _rtg=0; case "$-" in *f*) _rtg=1 ;; esac
  set -f
  # shellcheck disable=SC2086
  set -- $_rt
  while [ $# -gt 0 ]; do
    _rtk=$1; shift
    [ -n "$_rtk" ] || continue
    case "$_rtk" in
      # GUARD-DENY-TRIO M1: a post-`&` token that is ALL-DIGITS (`>&1`, `N>&M`) or `-` (`>&-`) is a
      # true fd-dup/close — not a filesystem target — and stays excluded (the 14 relief forms). A
      # NON-NUMERIC word (`>&conformance/verify.sh`, `>&hooks/pre-pus*`, `>&$VAR`) is bash's combined-
      # redirect FILE write: strip the `&` and let it fall through to the literal/allowlist classifier
      # below, so a literal CP target denies and a glob/$VAR target fails closed (rc 2). This narrows the
      # previously-broad `&`-exclusion (disclosed residual C1) without disturbing any fd-dup form.
      '&'*)
        _rtd=${_rtk#&}
        case "$_rtd" in
          ''|-) continue ;;                             # >&-  / bare & — close/dup, never a file target
          *[!0-9]*) _rtk=$_rtd ;;                        # >&<non-numeric word> — a combined-redirect write
          *) continue ;;                                # >&N (all-digits) — fd-dup, never a file target
        esac ;;
    esac
    case "$_rtk" in
      # GUARD-READONLY-FP-RELIEF Arm G(ii) — a `~`-ROOTED target is a LITERAL for this classifier.
      # `~` was outside the allowlist, so every out-of-repo scratch append (`printf x >> ~/notes.txt`)
      # disqualified and the Cure-2 launder arm denied it. Unlike `$VAR`, a `~` target shows every
      # byte after the home root LITERALLY, so it is control-plane-CHECKABLE — and it is checked:
      # `is_control_plane_target` classifies the `~/…` spelling directly (measured), so
      # `> ~/proj/.claude/settings.json` still denies via the callers' own CP test.
      # ***THE `$VAR` FORM IS DELIBERATELY NOT HERE*** (security vet H1): with the DIRECTORY in the
      # variable, the visible suffix (`pre-push`, `settings.json`, `reviewer.agent.md`) does not
      # self-classify, so relieving it would partially revert the Cure-2 closure — a deny-side
      # weakening inside a false-positive slice. The `$SCRATCH` idiom is answered by a TIP instead.
      # Declines (fall through to rc 2, fail-closed): a `..` byte anywhere in the suffix (it climbs
      # out of $HOME, so the target is no longer shown literally); any non-literal byte after the `~`
      # (a glob/backslash/substitution); and — the design's "cannot SEGMENT-MATCH a control-plane
      # path" condition — any `~` target that trips `_cp8b_pathhit`.
      # ⚠️ THE `_cp8b_pathhit` DISQUALIFIER IS LOAD-BEARING AND WAS FOUND BY A FLOOR REGRESSION, not
      # by design. `is_control_plane_target` ALONE is not enough: `GUARD-CLAUDE-HOME-INSTRUMENTATION-FP`
      # relieved `.claude/plans/*` and `.claude/projects/*` from the CLASSIFIER (a path-route relief),
      # while agent-autonomy.sh pins `echo x >> ~/.claude/plans/x.md` DENY on the COMMAND route as a
      # deliberate retained false positive. With only the classifier consulted, this arm would have
      # silently flipped that pinned decision — a deny-side change belonging to that slice, not this
      # one. `_cp8b_pathhit` is the segment matcher, it still hits the whole `.claude` family, and it
      # keeps every one of those legs green (measured). Widening this arm past `_cp8b_pathhit` is a
      # deny-side decision and needs its own slice.
      # REVIEW I3 (2026-08-19): a HOME-ROOT DOTFILE (`~/.gitconfig`, `~/.config/git/config` — where
      # core.hooksPath ALSO lives — `~/.zshrc`, `~/.ssh/authorized_keys`) moved DENY->ALLOW here,
      # undisclosed: these are not repo control-plane so `_cp8b_pathhit` misses them, but a write to
      # them is a real out-of-repo escalation (`~/.config/git/config` reopens exactly the guard-disable
      # vector Arm F defends). Decline any `~/`-suffix whose FIRST byte after the home root is `.`
      # (the `/.*` glob on the `~`-stripped suffix). The three legit relief legs (`~/notes.txt`,
      # `~/scratch/out.txt`, `~/logs/verify.log`) do not start with `/.`, so they stay allowed.
      '~'|'~/'*)
        case "${_rtk#\~}" in
          *..*|*[!A-Za-z0-9._/@:+=,-]*|/.*) _rtc=2 ;;
          *) if _cp8b_pathhit "$_rtk"; then _rtc=2; else printf '%s\n' "$_rtk"; fi ;;
        esac ;;
      *[!A-Za-z0-9._/@:+=,-]*) _rtc=2 ;;                # NOT a plain literal -> disqualify (fail-closed)
      *) printf '%s\n' "$_rtk" ;;
    esac
  done
  [ "$_rtg" = 1 ] || set +f
  return $_rtc
}

_cp8b_redirect_hits_cp() {
  _rh=$1
  case "$_rh" in *'>'*) : ;; *) return 1 ;; esac
  _rt=$(_redir_targets "$_rh") || return 0   # rc 2 => a non-literal target => fail closed (K-R1b)
  [ -n "$_rt" ] || return 1
  _rg=0; case "$-" in *f*) _rg=1 ;; esac
  set -f
  # shellcheck disable=SC2086
  set -- $_rt
  while [ $# -gt 0 ]; do
    if [ -n "$1" ] && { is_control_plane_path "$1" || is_control_plane_target "$1"; }; then
      [ "$_rg" = 1 ] || set +f
      return 0
    fi
    shift
  done
  [ "$_rg" = 1 ] || set +f
  return 1
}

# _cp8b_pathhit "<segment>": 0 iff a control-plane path appears anywhere in the segment TEXT (the
# string-level basis). SINGLE SOURCE OF TRUTH — called by both the old verb-arm (_cp8b_scan_denied)
# and the new resolved-target arm (_cp8b_target_arm_denied), so the regex cannot drift between them.
# The regex is byte-identical to the inline form _cp8b_scan_denied carried before the target-arm fold
# (GUARD-BASENAME-AFTER-CD-BYPASS), so the old arm's verdict is unchanged. It is REQUIRED for the lifted
# gate: the P0 case `python3 -c "open('hooks/pre-push','w')"` hides the path inside interpreter syntax
# the token split cannot see, but this substring grep does.
# GUARD-HOOKSPATH-CASE-BYPASS (seat MEDIUM, characterized): the alternation is split into the same
# TWO TIERS `is_control_plane_path` already established (:64-98) — reused here, not reinvented, so
# the fold rationale cannot drift between the two matchers. TIER 1 (kit-owned, unambiguous names —
# `.claude`, CODEOWNERS, `.git`, hooks/pre-push, the enumerated `.kit/*.conf` + named scripts, the
# scanner-ignore files, and `agents/*.agent.md`, which is already unconditional in
# `is_control_plane_path`'s own Tier 1) folds on EVERY platform: no adopter coincidentally names a
# different thing `.CLAUDE` or `HOOKS/PRE-PUSH`. TIER 2 (the generic directory prefixes `skills/`,
# `conformance/`, `adapters/`) folds ONLY when `_fs_case_insensitive` — folding it unconditionally
# would reintroduce the EXACT false-positive `is_control_plane_path`'s own A2 fix measured and closed
# (`src/Adapters/Repo.cs`, `Skills/Onboarding.cs` are legitimate adopter code on a case-sensitive
# filesystem). `_fs_case_insensitive` is sound here for the SAME reason it is sound for
# `is_control_plane_path`: these are repo-relative prefixes, always judged against the tree the guard
# itself sits on — not an arbitrary absolute path that could live on a different mounted volume (the
# reason a filesystem probe was REJECTED for the `.env` secret arm, design §3 resolution (B)).
# GUARD-PATH-ENUMERATION-INCOMPLETE S1 — THE `.claude` LEG IS LEFT-ANCHORED, AND THE ANCHOR CLASS IS
# PINNED. The leg used to be `\.claude(/|…)` with NO left anchor, so it matched `foo.claude/` and
# `v2.claude/` — the same `<x>.claude/...` false positive the path globs carried. Relieving it on the
# path route ALONE would have been worse than leaving it: the redirect/cmd route would keep denying an
# ordinary adopter file while the acceptance criterion greened on the path route (route-split relief).
# ⚠️ THE ANCHOR IS `(^|[^A-Za-z0-9._-])`, NOT `(^|/)`. Do NOT transplant the path-glob phrasing "at the
# start or after a /" into this regex: it matches COMMAND TEXT, not a path. `(^|/)` would drop the
# quoted (`".claude/x"`), post-space (`verb .claude/x`) and post-`=` (`--out=.claude/x`) spellings out
# of pathhit entirely — and for the interpreter form `python3 -c "open('.claude/settings.json','w')"`
# pathhit is the ONLY arm that fires (the token walk cannot see a path inside the parentheses), so
# `(^|/)` would re-open that P0 class outright. The class excludes every byte that can end a FILENAME
# (letters, digits, `.`, `_`, `-`), so `foo.claude/` and `v2.claude/` relieve while start-of-string,
# post-`/`, post-space, post-quote, post-`=`, post-`:` all still deny. Corner-spelling DENY fixtures and
# sibling ALLOW fixtures both live in conformance/agent-autonomy.sh; this narrowing is a deny
# RELAXATION and carries its own fixtures and its own monotonicity run, per the standing rule.
# AGENTS.md and REQUIRED-CHECKS.md use the CODEOWNERS-style anchor `(^|[^a-zA-Z.])`: an unanchored
# `agents\.md` would substring-match `subagents.md`.
# ⚠️ `.gitattributes` IS LEFT-ANCHORED WITH THE PINNED CLASS, NOT LEFT BARE. It shipped as a plain
# substring in the first cut of this slice, copied from the `.gitleaksignore` precedent — and that was
# an UNDECLARED deviation from the design, which specifies segment-anchored membership. It produced a
# measured ROUTE SPLIT: `foo.gitattributes` and `docs/my.gitattributes` ALLOWED at the Write/Edit path
# route (the globs `​.gitattributes|*/.gitattributes` are already segment-exact) while DENYING here under
# any unrecognized lead verb. The precedent did not transfer: nothing is plausibly named
# `foo.gitleaksignore`, but `<tool>.gitattributes` is an ordinary generated-file spelling. Anchoring
# aligns this leg with the globs it is supposed to mirror; the class is the same one the `.claude` leg
# pins, so start-of-string, post-`/`, post-space, post-quote, post-`=` and post-`:` all still deny.
# ⚠️ INHERITED-ANCHOR FACE, DECLARED (M3): the CODEOWNERS class `(^|[^a-zA-Z.])` admits `-`, so
# `SUB-AGENTS.md` DENIES here while the path route ALLOWS it (the glob `agents.md|*/agents.md` is
# segment-exact). That asymmetry is inherited from the CODEOWNERS convention this leg copies, not
# introduced by it, and it is fail-SAFE in the direction it errs. It is stated rather than fixed
# because narrowing the shared CODEOWNERS anchor class is a change to an existing deny with its own
# fixtures and its own monotonicity run — not a tidy-up to ride along here.
_CP8B_PATHHIT_T1='((^|[^A-Za-z0-9._-])\.claude(/|[[:space:]]|$)|\.github/workflows|/CODEOWNERS|(^|[^a-zA-Z.])CODEOWNERS|(^|[^a-zA-Z.])AGENTS\.md|(^|[^a-zA-Z.])REQUIRED-CHECKS\.md|(^|[^A-Za-z0-9._-])\.gitattributes|\.git(/|[[:space:]]|$)|hooks/pre-push|scripts/kit-guard|docs/governance/\.meta-control-last|docs/governance/meta-control-log\.md|\.kit/budget\.conf|\.kit/roster\.conf|\.kit/model-map\.conf|\.kit/model-tiers\.conf|\.kit/dials\.conf|scripts/model-tier\.sh|scripts/orchestrator-run\.sh|agents/[^[:space:]]*\.agent\.md|scripts/release-tag\.sh|scripts/promotion-verify\.sh|scripts/escalate\.sh|\.gitleaks\.toml|\.gitleaksignore|\.semgrepignore|\.trivyignore|\.checkov\.yaml|\.checkov\.yml)'
_CP8B_PATHHIT_T1_LC='((^|[^A-Za-z0-9._-])\.claude(/|[[:space:]]|$)|\.github/workflows|/codeowners|(^|[^a-z.])codeowners|(^|[^a-z.])agents\.md|(^|[^a-z.])required-checks\.md|(^|[^A-Za-z0-9._-])\.gitattributes|\.git(/|[[:space:]]|$)|hooks/pre-push|scripts/kit-guard|docs/governance/\.meta-control-last|docs/governance/meta-control-log\.md|\.kit/budget\.conf|\.kit/roster\.conf|\.kit/model-map\.conf|\.kit/model-tiers\.conf|\.kit/dials\.conf|scripts/model-tier\.sh|scripts/orchestrator-run\.sh|agents/[^[:space:]]*\.agent\.md|scripts/release-tag\.sh|scripts/promotion-verify\.sh|scripts/escalate\.sh|\.gitleaks\.toml|\.gitleaksignore|\.semgrepignore|\.trivyignore|\.checkov\.yaml|\.checkov\.yml)'
# TIER 2 gains `scripts/` and `profiles/` — the redirect-route half of the directory families added to
# `_cpp_match`. They land HERE and never in T1, for the identical reason: T1 folds on every platform,
# and an unconditionally-folded `scripts/` would reinstate the measured case-sensitive FP class on the
# cmd route one argument position to the left of where `_cpp_match` closed it.
# ⚠️ THE TWO NEW LEGS ARE LEFT-ANCHORED; the three older ones are not. This is deliberate and it is
# NOT a drive-by symmetry to "finish": these families are SEGMENT properties, and a bare substring
# `scripts/` would deny `myscripts/x.sh` — an ordinary adopter directory that merely ends in the family
# name, i.e. the `my.claude/` false positive rebuilt in a new matcher. The anchor admits `/` (so a real
# `frontend/scripts/build.js` segment still denies, as the design's consequences disclose) and every
# quote/space/`=` lead-in, while excluding filename-tail bytes. Anchoring the three EXISTING legs would
# be a deny RELAXATION on skills/conformance/adapters, which needs its own fixtures and its own
# monotonicity run — it is a separate change, not a tidy-up, and it is not made here.
_CP8B_PATHHIT_T2='(skills/[^[:space:]]*|conformance/[^[:space:]]*|adapters/[^[:space:]]*|(^|[^A-Za-z0-9._-])scripts/[^[:space:]]*|(^|[^A-Za-z0-9._-])profiles/[^[:space:]]*)'
_cp8b_pathhit() {
  printf '%s' "$1" | grep -Eq "${_CP8B_PATHHIT_T1}|${_CP8B_PATHHIT_T2}" && return 0
  # Arm 1 above is byte-identical to the pre-fold regex and returns first (the `_under_temp`
  # add-only shape at :309-328) — this can only ever ADD a pathhit. HOT PATH (Fix 2, dual-review
  # round): guard on an UPPERCASE byte only (`*[A-Z]*`), mirroring `is_control_plane_path:93` — `tr
  # 'A-Z' 'a-z'` cannot change a string that has no uppercase byte, so an all-lowercase command (the
  # common case, on every Bash call) pays zero extra subprocess. `*[A-Za-z]*` (ANY letter) was wrong:
  # it forked `tr`+`grep` on nearly every ordinary lowercase command, since almost every command has
  # a letter somewhere.
  case "$1" in *[A-Z]*) : ;; *) return 1 ;; esac
  _phl=$(printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z')
  printf '%s' "$_phl" | grep -Eq "$_CP8B_PATHHIT_T1_LC" && return 0
  _fs_case_insensitive && printf '%s' "$_phl" | grep -Eq "$_CP8B_PATHHIT_T2"
}

_cp8b_scan_denied() {
  _ss=$1
  _pathhit=1
  if _cp8b_pathhit "$_ss"; then
    _pathhit=0
  else
    # bare control-plane DIRECTORY token (the D1 gap): `bash -c "mv conformance /tmp"`.
    _pg=0; case "$-" in *f*) _pg=1 ;; esac
    set -f
    # shellcheck disable=SC2086
    set -- $_ss
    while [ $# -gt 0 ]; do
      if _cp8b_tok_is_cp "$1"; then _pathhit=0; break; fi
      shift
    done
    [ "$_pg" = 1 ] || set +f
  fi
  [ "$_pathhit" = 0 ] || return 1
  # A2 (case) — the REDIRECT arm is a matcher of its own and was still byte-literal. Measured before
  # this fold: `echo evil > .claude/settings.json` DENY but `> .Claude/settings.json` ALLOW; `> CODEOWNERS`
  # DENY but `> codeowners` ALLOW — the sharper one, because A2 ADDED `codeowners` to the classifier, so
  # the class said control-plane while the guard still permitted the redirect write. Fold the scanned
  # segment once here (the alternation below is authored lowercase to match), rather than duplicating
  # case variants into an already-dense regex. `_ssl` is used ONLY for these greps; every message and
  # every other decision still reads the original `$_ss`.
  _ssl=$_ss
  case "$_ss" in *[A-Z]*) _ssl=$(printf '%s' "$_ss" | LC_ALL=C tr 'A-Z' 'a-z') ;; esac
  # VERBS FOLD TOO. On a case-insensitive filesystem `/bin/RM` resolves to `/bin/rm`, so a byte-literal
  # verb match is the same defect as a byte-literal PATH match, one argument position to the left.
  # Measured before this fold: `rm -rf conformance` DENY but `RM -rf conformance` ALLOW; likewise
  # `MV conformance /tmp/x`, which relocates every gate in the repo — the exact command the
  # is_control_plane_target comment exists to deny. `_ssl` is already computed above.
  if printf '%s' "$_ssl" | grep -Eq '(^|[^[:alnum:]_])(rm|rmdir|mv|cp|truncate|shred|chmod|chown|dd|sed|tee|ln|install|patch)[[:space:]]' \
     || printf '%s' "$_ssl" | grep -Eq '(^|[^[:alnum:]_])git[[:space:]]+(checkout|restore)([[:space:]]|$)' \
     || _cp8b_redirect_hits_cp "$_ss"; then
    return 0
  fi
  return 1
}

# _cp8b_deny_reason "<seg>": print the control-plane deny reason, NAMING the offending segment. Every
# non-git-write deny arm calls this so the block never denies with a BLANK reason (a regression the
# security + code reviews both caught: `main` always printed the `13: … KIT_GUARD_SELFEDIT=1 …` guidance,
# and an empty reason leaves a blocked agent with no explanation and no override hint - in an ERGONOMICS
# slice). The segment name closes the CP-8a section-1.2 UX gap (a denied COMPOUND gave no signal about
# WHICH part offended). Truncated so a pathological segment cannot flood the reason channel.
# _cp8b_message_tip: DRIFT-2. When the RAW command is a git/gh message-carrying invocation, a
# control-plane deny is most often a MULTILINE MESSAGE BODY being segmented on its newlines and scanned as
# code — the message DATA mis-read as a command. The guard does NOT relax the decision (a quote-aware
# segmenter would fail OPEN: it could miss a real `; rm -rf` split); instead it NAMES the safe escape, which
# passes the body from a FILE and cannot execute. This is ADDITIVE to the reason text only — it changes no
# deny/allow verdict, and it is harmless on a genuine attack (the command is still denied; the tip helps no
# bypass). Reads $_cp8b_raw, set at the top of _cp8b_control_plane_denied (its only caller of this arm).
# GUARD-READONLY-FP-RELIEF (the (c′) tip-loss fix + the §3 kept-denied tips). TWO ARGUMENTS now:
#   $1 = the RAW command   — the right key for whole-command shapes (a message body, a heredoc, a
#                            loop head, a quoted alternation) that SPAN segments
#   $2 = the OFFENDING SEGMENT — the right key for lead-verb shapes. Keying these on the RAW was a
#                            measured defect: `cd x && sed -n … <cp>` lost the head/tail escape hint
#                            because the raw lead was `cd`, i.e. the tip disappeared exactly when a
#                            compound made the deny hardest to read. Defaults to $1 for old callers.
# Every arm here is ADDITIVE TO REASON TEXT ONLY — no verdict moves, and naming an escape helps no
# bypass (the command is still denied). The first matching arm returns, so the arms stay exclusive.
_cp8b_message_tip() {
  _mt_raw=$1; _mt_seg=${2:-$1}
  case "$_mt_raw" in
    *"git commit"*|*"git merge"*|*"git tag"*|*"git notes"*|*"gh pr"*|*"gh issue"*|*"gh release"*)
      printf ' TIP: a multi-line commit/PR message body is scanned as data and can trip this; pass it from a FILE instead of an inline -m/--body — `git commit -F <file>` or `gh pr create --body-file <file>` (the file content is never executed).'
      return ;;
  esac
  # Arm E's DECLINE cases land here: the heredoc body was NOT excluded (unquoted delimiter, `<<-`,
  # >1 heredoc, an ambiguous terminator) so its lines were scanned as code. Name the cure.
  case "$_mt_raw" in
    *'<<'*)
      printf ' TIP: a heredoc BODY is scanned as data-mistaken-for-code unless it is inert. Use a quoted heredoc delimiter (`<<'"'"'EOF'"'"'` or `<<"EOF"`, terminator on its own line, no `<<-`), or pass the content from a file — an unquoted or tab-stripped delimiter cannot be bounded safely, so it stays scanned.'
      return ;;
  esac
  # §3 kept-denied, keyed on the RAW LEAD because the offending segment is a FRAGMENT of the
  # construct (a quoted `|` over-splits; a loop BODY is its own segment).
  _mt_rl=$(_cp8b_lead "$_mt_raw")
  case "$_mt_rl" in
    grep|egrep|fgrep|rg)
      case "$_mt_raw" in
        *'|'*)
          printf ' TIP: a quoted alternation/pipe is scanned as a command SEPARATOR (segmentation is deliberately quote-blind — a quote-aware split fails OPEN on a real `; rm -rf`). Use one pattern per invocation, `grep -e A -e B`, or the Grep tool.'
          return ;;
      esac ;;
    for|while|until)
      printf ' TIP: a loop over control-plane paths is scanned per segment and the loop HEAD carries the whole deny (relieving it segment-locally would allow a mass-delete body). Use the Read/Grep tool, or one invocation per file.'
      return ;;
  esac
  # DRIFT-2b: a read-oriented sed/awk/… on a control-plane path is denied because these tools carry write/exec
  # escapes (`sed s///e`/`w`, `awk system()`); NAME the escape-free paths. Detect the LEAD VERB (not a
  # substring — a message body mentioning "sed" must not trigger this). Names BOTH read and edit exits, so it
  # is accurate whether the operator meant `sed -n` (read) or `sed -i` (edit) — no program sub-parse.
  # GUARD-READONLY-FP-RELIEF: keyed on the OFFENDING SEGMENT's lead, not the raw lead (the (c′) fix).
  _mt_lead=$(_cp8b_lead "$_mt_seg")
  case "$_mt_lead" in
    sed|awk|sort|uniq|find|less|more|xxd)
      printf ' TIP: %s is denied on control-plane paths (write/exec escapes). For a plain READ use head/tail/cat or the Read tool; to EDIT a control-plane file use the Edit/Write tool in a dev-clone (never via shell).' "$_mt_lead"
      return ;;
    python|python3|node|ruby|perl|source|.)
      printf ' TIP: an interpreter'"'"'s arguments are treated as code, never as data, so a control-plane path inside them cannot be cleared. Use the Read tool, or run the program from a file that names no control-plane path.'
      return ;;
    sh|bash|dash|zsh|ksh)
      case " $_mt_seg " in
        *' -c '*)
          printf ' TIP: an interpreter'"'"'s arguments are treated as code, never as data, so a control-plane path inside them cannot be cleared. Use the Read tool, or run the program from a file that names no control-plane path.'
          return ;;
      esac ;;
    *=*)
      printf ' TIP: an UNVETTED `NAME=value` prefix is not peeled before the scan (the vetted-name allowlist is deliberately closed — widening it per false positive is enumeration creep). Set the variable with `export` as a separate statement, or use a vetted name.'
      return ;;
  esac
}
# _cp8b_trigger_tip "<trigger>" "<segment>": the target-arm sites that had NO tip at all.
_cp8b_trigger_tip() {
  case "$1" in
    redir-nonliteral)
      printf ' TIP: the redirect TARGET is not a plain literal (a `$VAR`, glob, substitution or backslash), so the guard cannot tell whether it names a protected path — and it refuses to guess. Spell the redirect target literally (`> /tmp/out.txt`), use a `~/`-rooted path, or use the Write tool.' ;;
  esac
}
_cp8b_deny_reason() {
  _dr=$(printf '%s' "$1" | cut -c1-160)
  printf '13: mutating the guard / its config / CI gates via shell is denied (control-plane integrity) - offending segment: [%s].%s Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.' "$_dr" "$(_cp8b_message_tip "${_cp8b_raw:-}" "$1")"
}

# _cp8b_next_seg: pop the first newline-delimited segment off $_walk into $_seg, leaving the remainder in
# $_walk. Returns 0 while a segment remains, 1 when exhausted. This is PURE PARAMETER EXPANSION - it never
# touches IFS (a global IFS reassignment is the bash.lang.security.ifs-tampering finding, and it also risks
# leaking a modified IFS into the ~40 destructive-matrix rules that run AFTER this block). And it is NOT a
# `cmd | while read` pipe, which would run the body in a SUBSHELL and silently lose the caller's `return`
# (CP-1 shipped exactly that bug, green the whole time). The caller seeds $_walk from _cp8b_segments.
_cp8b_nl='
'
_cp8b_next_seg() {
  [ -n "$_walk" ] || return 1
  case "$_walk" in
    *"$_cp8b_nl"*) _seg=${_walk%%"$_cp8b_nl"*}; _walk=${_walk#*"$_cp8b_nl"} ;;
    *)             _seg=$_walk; _walk='' ;;
  esac
  return 0
}

# GUARD-READONLY-FP-RELIEF Arm E — QUOTED-heredoc body exclusion (cures register face N3).
# A heredoc with a QUOTED delimiter (`<<'EOF'` / `<<"EOF"`) is INERT DATA by shell semantics: no
# expansion, no execution. Today each body LINE becomes a segment and is scanned as code, which is
# the false positive that bit one orchestrator session four times. This removes the body REGION from
# the copy the two control-plane arms segment. The RAW command is untouched — every flat rule in
# `guard_check_command` (recursive rm, push-to-main, secret reads, …) still sees every byte, and the
# deny REASONS still print the raw/segment text.
#
# ***THE FAIL DIRECTION IS OVER-EXCLUSION*** (security vet M2): swallowing past a mis-found terminator
# would let a REAL command escape the scan. So every ambiguity resolves to NOT-excluded, and each
# decline below has a must-stay-DENY leg in agent-autonomy.sh that places a live mutator AFTER the
# true terminator. Declines, in order:
#   · a here-STRING (`<<<`) — different construct, not this arm
#   · any CR byte — a CRLF terminator will not compare equal, so the whole command is ambiguous
#   · anything other than EXACTLY ONE `<<` in the command (two heredocs = two body regions to bound;
#     this decline is a conservative BELT — with the exact-terminator rule below, dropping it can
#     only ever exclude the FIRST body, which is inert either way, so no fixture separates it. Stated,
#     not claimed as coverage: the `_kx` precedent at C4 Arm 2, mutant dropped with rationale.)
#   · `<<-` (tab-stripped terminators), an UNQUOTED delimiter, or a delimiter that is not a plain
#     `[A-Za-z0-9_]+` word — the extraction below simply fails to match, and a failed match declines
#   · a heredoc whose own redirect TARGET classifies control-plane or is non-literal
#   · NO line after the start line that is EXACTLY the delimiter — never strip to the end
#   · any earlier line that TRIMS to the delimiter but is not exactly it (whitespace ambiguity)
# ***REVIEW C2 (2026-08-19), residual DIRECTION CORRECTED — the earlier claim was FALSIFIED.*** A
# `<<'WORD'` sequence inside an ordinary quoted argument IS treated as a heredoc start, and the earlier
# comment claimed "the direction of any residual error is a body that stays scanned — over-deny." That
# was WRONG. `: "<<'X'"` followed by `sed -i s/return 1/return 0/ .claude/hooks/guard-core.sh` and a
# line `X` made the first REAL command the heredoc body: it was stripped from the scanned copy and the
# write to the guard's OWN source ALLOWED — an escape from ALL cp8b protection, measured ALLOW on the
# branch, DENY on main. The failure direction is OVER-EXCLUSION, not over-deny. The in-body declines
# (`<<-`, unquoted, whitespace-ambiguous) were never the gap; the ENTRY was. A REAL heredoc operator
# never has a QUOTE byte before the `<<` on its start line (`cat <<'EOF'` — no quote precedes `<<`),
# so declining when one does closes the argument-embedded shape. Disclosed OVER-DENY, the safe
# direction: a genuine heredoc whose start line ALSO carries an earlier quoted string
# (`echo "hi" && cat <<'EOF'`) declines too and its body stays scanned — accepted, since the fail
# direction is over-deny and the common heredoc spelling leads with the redirect verb, unquoted.
# Mutant M-E8 removes that line and reopens the hole.
_cp8b_cr=$(printf '\r')
_cp8b_strip_heredocs() {
  case "$1" in *'<<'*) : ;; *) printf '%s' "$1"; return ;; esac
  case "$1" in *'<<<'*) printf '%s' "$1"; return ;; esac
  case "$1" in *"$_cp8b_cr"*) printf '%s' "$1"; return ;; esac
  _hdc=$(printf '%s' "$1" | grep -o '<<' | wc -l | tr -d '[:space:]')
  [ "$_hdc" = 1 ] || { printf '%s' "$1"; return; }
  _hdl=$(printf '%s\n' "$1" | grep -n '<<' | head -1 | cut -d: -f1)
  [ -n "$_hdl" ] || { printf '%s' "$1"; return; }
  _hds=$(printf '%s\n' "$1" | sed -n "${_hdl}p")
  # REVIEW C2 — ENTRY guard: a quote byte BEFORE the `<<` on the start line means the `<<` is embedded
  # in an argument, not a heredoc operator. Decline (never strip). `${_hds%%<<*}` is the text before
  # the first `<<`; a `'` or `"` in it is the tell.
  case "${_hds%%<<*}" in *[\'\"]*) printf '%s' "$1"; return ;; esac
  # The two SEMANTIC guards, deliberately kept as their own lines so each is separately mutatable
  # (the extraction below is intentionally permissive; these decide, not the regex).
  case "$_hds" in *'<<-'*) printf '%s' "$1"; return ;; esac              # tab-stripped terminator (M2)
  printf '%s' "$_hds" | grep -q "<<-\{0,1\}['\"]" || { printf '%s' "$1"; return; }  # QUOTED delimiter only
  _hdw=$(printf '%s' "$_hds" | sed -n 's/.*<<-\{0,1\}["'"'"']*\([A-Za-z0-9_][A-Za-z0-9_]*\).*/\1/p')
  [ -n "$_hdw" ] || { printf '%s' "$1"; return; }
  if _cp8b_tad_redir_cp "$_hds"; then printf '%s' "$1"; return; fi
  _hdo=$(printf '%s\n' "$1" | awk -v start="$_hdl" -v w="$_hdw" '
    NR <= start { pre = pre $0 "\n"; next }
    !seen {
      if ($0 == w) { seen = 1; next }
      t = $0; gsub(/^[ \t]+/, "", t); gsub(/[ \t]+$/, "", t)
      if (t == w) { amb = 1 }
      next
    }
    { post = post $0 "\n" }
    END { if (!seen || amb) exit 3; printf "%s%s", pre, post }') || { printf '%s' "$1"; return; }
  printf '%s' "$_hdo"
}

# _cp8b_control_plane_denied "<cmd>": PREDICATE - the CP-8b control-plane decision. Walks the segments
# and binds each segment's LEADING VERB to that segment's OWN arguments (design section 9.4).
_cp8b_control_plane_denied() {
  _cp8b_raw=$1   # DRIFT-2: the whole command, for _cp8b_message_tip (the message-body escape hint).
  _walk=$(_cp8b_segments "$(_cp8b_strip_heredocs "$1")")
  while _cp8b_next_seg; do
    [ -n "$(printf '%s' "$_seg" | tr -d '[:space:]')" ] || continue

    # 1. git write-primitives are subcommand-bound and apply REGARDLESS of a control-plane mention
    #    (`git diff --output` writes anywhere). Checked first.
    if _cp8b_git_write_denied "$_seg"; then return 0; fi

    # 2. a segment we cannot parse, or one carrying a redirect, is NEVER relaxed - it keeps today's
    #    scan-and-deny. (`echo -n > .github/workflows/ci.yml` leads with a READ verb; only the redirect
    #    check stands between it and an allow-back.)
    if _cp8b_unparseable "$_seg" || printf '%s' "$_seg" | grep -q '[<>]'; then
      if _cp8b_scan_denied "$_seg"; then _cp8b_deny_reason "$_seg"; return 0; fi
      continue
    fi

    _lv=$(_cp8b_lead "$_seg")
    case "$_lv" in
      # 3. READ TOOLS - CP-8a's strict stdout-only set, REUSED VERBATIM, not re-derived. It deliberately
      #    excludes every tool with a write/exec escape: sed (s///e executes, `w` writes), awk (system(),
      #    print >), find (-exec/-delete), sort (-o), uniq (out), less/more (!cmd), xxd (-r). Their
      #    arguments are DATA: a read command cannot mutate the path it merely mentions.
      grep|egrep|fgrep|rg|ls|cat|head|tail|wc|diff|stat|file|du|cut|tr|nl|od|hexdump|column|tac|comm|cmp|basename|dirname|realpath|readlink|echo|printf|which|type)
        : ;;
      git)
        _sub=$(_cp8b_git_sub "$_seg")
        case "$_sub" in
          # Read subcommands whose arguments are DATA — `git commit -m "… conformance/x …"` is a MESSAGE,
          # not a target. This set is CP-8a's, REUSED VERBATIM and deliberately NOT widened.
          #
          # Every other git subcommand is left to fall through to scan-and-deny below, and that is a
          # decision, not an oversight. An earlier cut of this slice also certified
          # `add|fetch|pull|rebase|merge|stash|tag|branch|config|push` as "reads" — which would have
          # handed back an arbitrary-execution primitive, because `git rebase --exec "rm -rf conformance"`
          # RUNS the string. That is CP-8a's fail-open repeating exactly: certifying a capability safe by
          # NAMING it, without enumerating every flag it carries ("git diff is a read" — false for
          # --output). None of them NEED the exemption: with no mutation verb in the segment, scan-and-deny
          # allows them anyway. Speculative exemptions are treated as guilty.
          commit|status|blame|describe)
            : ;;
          checkout|restore|archive|bundle|worktree|init|clone)
            : ;;   # already TARGET-BOUND in step 1; a clean pass there is a real ALLOW.
          *)
            if _cp8b_scan_denied "$_seg"; then _cp8b_deny_reason "$_seg"; return 0; fi ;;
        esac ;;
      # 4. MUTATION VERBS - target-bound. Two sub-classes by what the verb does to its SOURCE:
      #    - ALL path tokens are targets when the verb can WRITE THROUGH any of its arguments:
      #        mv/rsync DESTROY the source (this is what catches `mv conformance /tmp/gone`);
      #        ln creates a WRITABLE ALIAS - `ln -s conformance/x /tmp/link` then `echo … > /tmp/link`
      #        writes the control-plane file, so `ln` is NOT a content-copy and every token it names is a
      #        target (security review of CP-8b: grouping `ln` with `cp` was the family's signature
      #        error - certifying a capability safe by the name it is grouped under, not by what it does);
      #        rm/chmod/… mutate their targets in place.
      #    - Only the DESTINATION is a target for cp/install, which copy CONTENT: editing the copy cannot
      #      reach the original, so copying a control-plane file OUT (`cp conformance/x /tmp/b`) is safe.
      #      ⚠️ NOT TRUE OF EVERY cp/install INVOCATION. Some flags make the destination an ALIAS of
      #      the source rather than a copy of its content, and this comment asserted otherwise until
      #      2026-08-01. Same signature error the `ln` note above records — certifying a capability by
      #      the family it is grouped under rather than by what it does. NOT fixed here: the remedy is
      #      a command-matrix change with a different blast radius from this file's path work, and it
      #      is tracked as GUARD-CP-HARDLINK-ALIAS. The flag detail lives on that row, not in this
      #      file — a guard's own source is read by the agent it denies, so an open hole is described
      #      here by its shape, not by a recipe.
      mv|rsync|ln|rm|rmdir|shred|truncate|chmod|chown|tee|patch|dd|sed)
        if _cp8b_cp_target_in all "$_seg"; then _cp8b_deny_reason "$_seg"; return 0; fi ;;
      cp|install)
        if _cp8b_cp_target_in last "$_seg"; then _cp8b_deny_reason "$_seg"; return 0; fi ;;
      # 5. ANYTHING ELSE - an interpreter, a wrapper, or simply unrecognized. Its arguments may be CODE.
      #    Today's behavior, byte for byte. This is the branch that makes the whole change monotone.
      *)
        if _cp8b_scan_denied "$_seg"; then _cp8b_deny_reason "$_seg"; return 0; fi ;;
    esac
  done
  return 1
}

# ============================================================================================
# GUARD-BASENAME-AFTER-CD-BYPASS + GUARD-INTERPRETER-FAMILY-BYPASS — the resolved-target arm.
# (design: docs/architecture/2026-08-13-guard-judge-resolved-target-design.md §3.)
# The guard judges the RESOLVED target, not the verb. COMPOSITION PROPERTY (§3-C, §9(b)): the final
# control-plane deny is `old-verb-arm (_cp8b_control_plane_denied) ∨ new-target-arm (below)`. The old
# arm is retained VERBATIM — so every existing DENY fixture stays green by construction and this is a
# monotone ADD (panel #19 shape). REALIZATION NOTE: the design's "union at four sites" is realized here
# as one cohesive parallel arm OR'd with the retained old arm — this reproduces the census oracle
# (scratchpad out_MIN2.tsv = today_cp ∨ newarm) exactly and touches no existing decision site, keeping
# the blast radius to an addition. Reads/CP-script execution stay allowed; ordinary-target writes by
# the same tools stay allowed.
#
# HONEST CEILING (design §6): this narrows the drift window for SINGLE-COMMAND, QUOTE-FREE writes only.
# Persisted cwd (no `cd` in the command), `$VAR`/`bash -c`/quoted-separator cd, and `python3 -c`
# building a path by concatenation remain disclosed residuals — the guard stays a speed bump (D3′).

# _cp8b_norm "<path>": textual normalization — collapse //, a /./ FIXPOINT, trailing /, and a `..`
# fixpoint. Byte-identical to guard_check_path's twin sed (single source of truth for composed-path
# shape) — the two are pinned equal by a byte-identity selftest leg (GUARD-CP-WRITE-ROUTES K-COUPLE).
# The /./ leg is a labelled fixpoint (`:b … tb`) mirroring the `..` leg: a single `g` pass misses
# OVERLAPPING /./ runs (hooks/./././pre-push -> hooks/./pre-push residual), so the loop is required to
# fully collapse repeated /./ (K-N2 pins it).
_cp8b_norm() {
  printf '%s' "$1" | sed -e 's#//*#/#g' -e ':b' -e 's#/\./#/#' -e 'tb' -e 's#^\./##' -e 's#/*$##' -e ':a' -e 's#[^/]*/\.\./##' -e 'ta'
}

# _cp8b_has_quote "<segment>": 0 iff the segment carries a quote/escape byte. A quote byte means the
# quote-blind segmenter (:568) MAY have crossed a quote, so a cd in this segment is not trustworthy
# (security C1). This is the fail-safe that keeps the desync attack DENY (see _cp8b_eff_update).
_cp8b_has_quote() { case "$1" in *\'*|*\"*|*\\*) return 0 ;; esac; return 1; }

# _cp8b_cd_arg "<segment>": the second token of a `cd` segment.
_cp8b_cd_arg() { printf '%s' "$1" | sed -E 's/^[[:space:]]*//' | awk '{print $2}'; }

# Part A — cd-state accumulator, fail-safe against desync. $_CP8B_EFF is '' (repo-relative root) or a
# pure relative DESCENT prefix. It updates ONLY on a pure relative descent in a QUOTE-FREE cd segment.
# Every climb-out / relaxation direction (a quote byte, absolute arg, `..`, arg-less cd, `cd -`,
# `cd ~`, `$VAR`/command-substitution) is a NO-OP that LEAVES the prefix unchanged. Rationale (C1): a
# forged *descent* via quote-desync could relax (compose a deeper, ordinary path), so a quoted cd
# segment is not trusted; a forged *climb-out* (absolute/..) is ignored, so the prior real prefix
# survives and the real target still composes → DENY. A no-op only ever RETAINS denials (composition
# is unioned with the literal token), so it is never worse than today — fail-closed by construction.
# The desync attack `cd hooks && echo "z || cd /tmp" && tee pre-push`: the bogus ` cd /tmp"` segment is
# BOTH quoted and absolute → no-op → $_CP8B_EFF stays `hooks` → `tee pre-push` composes hooks/pre-push
# → DENY. (Leg K-D binds this; K-A binds the accumulator itself.)
_cp8b_eff_update() {  # $1 = the cd segment ; reads/writes $_CP8B_EFF
  if _cp8b_has_quote "$1"; then return; fi
  _ea=$(_cp8b_cd_arg "$1")
  case "$_ea" in
    ''|-|'~'*|/*|*..*|*'$'*|*'`'*) return ;;
  esac
  if [ -z "$_CP8B_EFF" ]; then _CP8B_EFF=$(_cp8b_norm "$_ea")
  else _CP8B_EFF=$(_cp8b_norm "$_CP8B_EFF/$_ea"); fi
}

# _cp8b_compose "<token>": composed normalized path (effective-dir ⊕ token) on stdout; rc 1 if the
# token is not composable (no effective dir, or an absolute token). Part B reuses the :1426 fixpoint.
_cp8b_compose() {
  [ -n "$_CP8B_EFF" ] || return 1
  case "$1" in /*) return 1 ;; esac
  _cp8b_norm "$_CP8B_EFF/$1"
}

# _cp8b_composed_is_cp "<token>": 0 iff the token, dequoted and `flag=`-stripped (like _cp8b_tok_is_cp
# :609 — defect 2: else `dd if=/tmp/x of=pre-push` composes hooks/of=pre-push and escapes), composes
# to a control-plane path against the effective dir.
_cp8b_composed_is_cp() {
  _ct2=$(_cp8b_dequote "$1"); case "$_ct2" in *=*) _ct2=${_ct2#*=} ;; esac
  _cc=$(_cp8b_compose "$_ct2") || return 1
  [ -n "$_cc" ] && is_control_plane_target "$_cc"
}

# _cp8b_tad_redir_cp "<segment>": 0 iff a redirect TARGET bails to the deny side — either it classifies
# control-plane (literal ∨ composed) OR it is a NON-LITERAL target (GUARD-CP-WRITE-ROUTES Cure 2, via
# the shared _redir_targets disqualifier). Returning 0 makes the read/kit-exec recognition DECLINE, so a
# `sh conformance/verify.sh > $(echo hooks/pre-push)` is no longer laundered — the pathhit trigger then
# fires on the CP substring the reader was pointed at. The classification loop (composed-vs-plain) is
# kept per-caller so the cd-composition catch (`cd hooks && … > pre-push`) survives (K-R-COMPOSED); the
# split adopts _cp8b_redirect_hits_cp's `set -f` discipline (R2), not the old bare `for`.
_cp8b_tad_redir_cp() {
  case "$1" in *'>'*) : ;; *) return 1 ;; esac
  _rt=$(_redir_targets "$1") || return 0   # rc 2 => a non-literal target => fail closed (K-R1a)
  [ -n "$_rt" ] || return 1
  _rg=0; case "$-" in *f*) _rg=1 ;; esac
  set -f
  # shellcheck disable=SC2086
  set -- $_rt
  while [ $# -gt 0 ]; do
    if [ -n "$1" ]; then
      is_control_plane_target "$1" && { [ "$_rg" = 1 ] || set +f; return 0; }
      _cp8b_composed_is_cp "$1" && { [ "$_rg" = 1 ] || set +f; return 0; }
    fi
    shift
  done
  [ "$_rg" = 1 ] || set +f
  return 1
}

# Part C allow-side. _cp8b_tad_is_read "<segment>": a read-recognized segment never denies. A segment
# carrying a REDIRECT is read-recognized only when the redirect target is NOT control-plane (E5) — this
# is why the two mandatory flips fire: `printf`/`echo` are read verbs (:973), so without E5 narrowing
# `cd hooks && printf x > pre-push` would relax. The read set is CP-8a's stdout-only list, REUSED and
# PINNED (M1): awk/sed/find/sort/less/xxd/uniq stay OUT — each carries a write/exec escape and admitting
# any fails OPEN under the lifted gate. E2 adds git READ subcommands, safe only because the old
# scan-arm still denies `git diff --output=<cp>` (§9(b)); do not retire the old arm.
# C4 Arm 1 (E4a, face a) tier 1 — PLAIN-LIST adds: stdout-only readers, each verified to carry NO
# file-write flag in any form (jq writes only via shell redirect, which E5 already narrows via the
# `>`-target bail at :1180, so `shellcheck cp.sh > hooks/pre-push` stays DENY). Sole consumer of this
# list is _cp8b_tad_is_read (Finding 4 confirmed). `sort`/`less` stay OUT (sort -o writes, less
# shell-escapes); awk/sed/find stay OUT (E4b rejected). `yq`/`tree` are NOT here — they carry
# file-write flags and are handled by the decline-on-any-flag conditional arm below.
_CP8B_READ_VERBS='grep egrep fgrep rg ls cat head tail wc diff stat file du cut tr nl od hexdump column tac comm cmp basename dirname realpath readlink echo printf which type shellcheck jq shasum md5 cksum yamllint'
_CP8B_GIT_READ_SUBS='commit status blame describe add diff log show grep stash ls-files'
_cp8b_in_list() { for _w in $2; do [ "$_w" = "$1" ] && return 0; done; return 1; }
# _cp8b_seg_has_flag "<seg>": 0 iff ANY token after the leading verb begins with '-'. The
# decline-on-ANY-flag disqualifier for the yq/tree conditional read arm (vet Finding 1): genuine
# fail-by-disqualification, NOT a write-flag denylist (a denylist fails OPEN on the next unknown write
# flag — exactly the `yq -s <expr>` hole the vet caught).
_cp8b_seg_has_flag() {
  _pgf=0; case "$-" in *f*) _pgf=1 ;; esac
  set -f
  # shellcheck disable=SC2086  # deliberate word-split; globbing disabled above
  set -- $1
  [ $# -gt 0 ] && shift               # drop the leading verb
  while [ $# -gt 0 ]; do
    case "$1" in -*) [ "$_pgf" = 1 ] || set +f; return 0 ;; esac
    shift
  done
  [ "$_pgf" = 1 ] || set +f
  return 1
}
# _cp8b_seg_is_shell_n "<seg>": 0 iff the segment is EXACTLY a shell syntax check — the second token is
# EXACTLY `-n` and NO other token begins with `-`. Fail-by-disqualification, mirroring
# _cp8b_seg_has_flag: `-x` executes, `-nc` executes, `-n -c '<cmd>'` executes, and any second flag is an
# unknown, so all of them decline and fall through to the existing deny path. F2-KL pins the exact
# match: relaxing it to "any flag" read-recognizes `sh -x <cp>`, which EXECUTES the file.
_cp8b_seg_is_shell_n() {
  _pnf=0; case "$-" in *f*) _pnf=1 ;; esac
  set -f
  # shellcheck disable=SC2086  # deliberate word-split; globbing disabled above
  set -- $1
  [ $# -ge 3 ] || { [ "$_pnf" = 1 ] || set +f; return 1; }   # verb + -n + at least one file
  shift                                                      # drop the lead verb (sh|bash|dash)
  [ "$1" = "-n" ] || { [ "$_pnf" = 1 ] || set +f; return 1; }
  shift
  while [ $# -gt 0 ]; do
    case "$1" in -*) [ "$_pnf" = 1 ] || set +f; return 1 ;; esac
    shift
  done
  [ "$_pnf" = 1 ] || set +f
  return 0
}
_cp8b_tad_is_read() {
  case "$1" in *'>'*) _cp8b_tad_redir_cp "$1" && return 1 ;; esac
  _rv=$(_cp8b_lead "$1")
  _cp8b_in_list "$_rv" "$_CP8B_READ_VERBS" && return 0
  # C4 Arm 1 tier 2 (face a) — CONDITIONAL readers `yq`/`tree`. Both carry file-write flags
  # (`yq -i` in place; `yq -s/--split-exp <expr>` writes an expression-named file — no CP token in
  # argv; `tree -o <file>`). DECLINE-ON-ANY-FLAG: read-recognized ONLY when the segment carries NO
  # `-`-leading token at all (pure `yq '<expr>' <file>`, `yq . <file>`, `tree <dir>`). Any flag ->
  # decline -> fall through to the existing deny path. Over-deny on harmless flags (`yq -P`,
  # `tree -H`) is an accepted, disclosed FP. K-H pins this decline.
  # GUARD-FP-RELIEF-2 Arm C (face 3) — `actionlint` joins this SAME conditional tier, deliberately NOT
  # _CP8B_READ_VERBS: `-shellcheck=<cmd>` and `-pyflakes=<cmd>` make it run an arbitrary program, an
  # exec primitive, so the plain list is unavailable. Decline-on-any-flag keeps both exec-flag forms
  # DENY with zero enumeration; over-deny on `-oneline`/`-color` is a disclosed FP, the `yq -P` trade.
  # Bare `actionlint` was never denied (no control-plane token in argv). F2-KK pins the decline.
  case "$_rv" in
    yq|tree|actionlint) _cp8b_seg_has_flag "$1" || return 0 ;;
  esac
  # GUARD-FP-RELIEF-2 Arm D (face 4) — `sh|bash|dash -n <file>` is a shell SYNTAX CHECK. POSIX `-n`
  # reads and parses without executing, so this is a READ arm, not an exec arm, and the file argument
  # may be any path: reading a control-plane script for syntax is already granted via `cat`/`shellcheck`
  # (capability-equivalent). zsh/ksh are excluded — unmeasured need, add on evidence. The E5 redirect
  # bail at the top of this function runs FIRST, so `sh -n cp.sh > hooks/pre-push` stays DENY.
  case "$_rv" in
    sh|bash|dash) _cp8b_seg_is_shell_n "$1" && return 0 ;;
  esac
  if [ "$_rv" = git ]; then
    _rgs=$(_cp8b_git_sub "$1")
    _cp8b_in_list "$_rgs" "$_CP8B_GIT_READ_SUBS" && return 0
  fi
  return 1
}

# E1′ — kit-script EXECUTION exemption (NARROW). Lead sh/bash/dash/zsh/ksh + a conformance/*.sh |
# scripts/*.sh | scripts/kit-guard | scripts/sparkwright script token (bare or ./-prefixed), NO
# redirect, AND every OTHER token still classified. The broad "exempt the whole segment" form fails
# OPEN (`sh conformance/verify.sh .claude/hooks/guard-core.sh` would ALLOW); the narrow form re-denies
# it. Script ARGUMENTS stay unexamined (already the D3′ ceiling). (Leg K-E binds this — C2.)
# C4 Arm 2 (face b) — wrapper-prefix RECOGNITION strip. Produces a recognition-copy of a kit-exec
# segment with vetted benign wrappers peeled, so `timeout 600 sh conformance/verify.sh` is recognized
# as the kit-exec it wraps. Fail-by-disqualification: each shape strips ONLY its exact vetted form;
# anything else (a flag, an env assignment, a non-numeric timeout value) STOPS the loop, leaving a
# non-shell / non-kit lead -> not kit-exec -> deny (over-deny, safe). Bounded to 3 iterations; a
# residual non-wrapper lead breaks earlier. Used ONLY inside _cp8b_tad_is_kit_exec (constraint ii:
# the copy NEVER leaves this arm — deny reasons keep printing the original $_seg).
#   env    : BARE only (constraint i / vet Finding 2) — any following NAME=value assignment OR any
#            flag disqualifies (keeps `env KIT_GUARD_SELFEDIT=1 …`, `env PATH=/tmp …`, `env -i …` DENY;
#            K-F pins both the assignment and the flag leg).
#   timeout: `timeout <[0-9]+[smhd]?>` — a flagged/non-numeric value (`timeout -s KILL`) disqualifies.
#   nice   : bare `nice`, or `nice -n <digits>` — any other flag, or a non-digit -n value
#            (`nice -n hooks/pre-push`), disqualifies.
#   command: bare `command` — `command -v/-p/-V` disqualifies.
# GUARD-FP-RELIEF-2 Arm B (face 2) adds two more tokens in the same grammar:
#   time   : BARE only — any flag (`time -p`) disqualifies (disclosed over-deny). F2-KJ pins it.
#   {      : the bare `{` token of a brace group. Safe by the same recognition-copy argument: the RAW
#            segment still feeds every trigger, so `{ rm -rf conformance` stays DENY (lead after the
#            strip is `rm`, not a shell) and `{ sh cp.sh > hooks/pre-push` still bails on the redirect.
#
# GUARD-FP-RELIEF-2 Arm A (face 1) — the VETTED ASSIGNMENT-PREFIX allowlist. A leading `NAME=value`
# token is peeled from the recognition copy ONLY when NAME is a member of this list AND the value
# passes `_cp8b_assign_val_safe`. Membership IS the whole enforcement: it fails closed on every unknown
# name, so all nine measured face-1 negatives keep their DENY with ZERO deny-side edits.
#
# ***THE NEVER-ADD CLASS — the line this list does not cross.*** This arm precedes a kit-script
# EXECUTION, so the danger is CODE-LOADING / EXEC-ENVIRONMENT variables. Permanently excluded, and no
# future "reasonable" widening may include them: PATH, IFS, LD_PRELOAD, LD_LIBRARY_PATH,
# DYLD_INSERT_LIBRARIES, DYLD_LIBRARY_PATH, BASH_ENV, ENV, SHELLOPTS, and the whole GIT_* family
# (GIT_SSH_COMMAND, GIT_EXTERNAL_DIFF, GIT_PAGER … each names a program git will run). Interpreter
# option variables (NODE_OPTIONS, PERL5OPT, PYTHONSTARTUP, RUBYOPT) are the same class and are equally
# excluded — they look harmless and are not. KIT_* names are never vetted either (KIT_GUARD_SELFEDIT is
# the kill switch, KIT_PUSH_CITE a dial), but note KIT_* in command TEXT is inert — `selfedit_allowed`
# reads the guard's OWN process env, not `$cmd` — so the exec-env family above, not KIT_*, is the
# security-load-bearing exclusion (security vet MED-1).
#
# Contents are MEASURED-USAGE ONLY (owner ruling, design 2026-08-15 §8-Q1/A2): LANG/TZ are vet-confirmed
# exec-inert and were still held out, because monotone add-only makes a token near-irreversible and
# every token owes an evidence-backed leg. Widening costs one token plus one leg, on a measured denial.
_CP8B_VETTED_ASSIGN='SELFTEST LC_ALL'
# _cp8b_assign_val_safe "<value>": 0 iff the value is a plain literal with no shell-active byte.
# ***BUILD MANDATE (security vet HIGH-1).*** This MUST be the decline-on-any-bad-char NEGATED-CLASS
# idiom and MUST NEVER become a positive match: `grep -Eq '^[A-Za-z0-9._:/-]+'` anchors only the HEAD,
# so `SELFTEST=x$(rm -rf conformance)` would satisfy it, strip clean, and ALLOW while the substitution
# executes — fail-by-parse wearing a disqualification costume, the exact class D-240813-3 bans. The
# metachar-FIRST forms (`SELFTEST=$(whoami)`) decline under BOTH builds and cannot tell them apart;
# the valid-char-then-metachar fixtures and mutant F2-KI2b are what pin the idiom itself.
_cp8b_assign_val_safe() {
  case "$1" in ''|*[!A-Za-z0-9._:/-]*) return 1 ;; esac
  return 0
}
# _cp8b_peel_lead_assign "<seg>": drop a leading well-formed `NAME=value` token and the whitespace
# after it. The pattern re-states the SAME character class the disqualifier enforces, so for every
# NON-EMPTY value a mutant that flips only _cp8b_assign_val_safe SURVIVES — this pattern rejects the
# same value a second time. That is why F2-KI2/F2-KI2b flip BOTH halves and honestly pin the PAIR, as
# the C4 literal-side-conjunction leg does.
# THE REDUNDANCY IS NOT TOTAL, and the earlier "no fixture can separate them" claim was FALSE (review
# F1, falsified by measurement): the value pattern is `*` (zero-or-more) while the disqualifier also
# rejects the EMPTY value, so `SELFTEST= sh <kit-script>` separates the halves — a val_safe-only mutant
# IS killable there. Mutant F2-KI2c pins that half ALONE via the empty-value leg. Keep the `*`: making
# it `+` would re-orphan that mutant by restoring total redundancy.
_cp8b_peel_lead_assign() {
  printf '%s' "$1" | sed -E 's%^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[A-Za-z0-9._:/-]*[[:space:]]+%%'
}
_cp8b_strip_wrappers() {
  _sw=$1
  _swi=0
  while [ "$_swi" -lt 3 ]; do
    _swl=$(_cp8b_lead "$_sw")
    _sw2=$(printf '%s' "$_sw" | sed -E 's/^[[:space:]]*//' | awk '{print $2}')
    case "$_swl" in
      timeout)
        case "$_sw2" in [0-9]*) : ;; *) break ;; esac         # value must start with a digit
        case "$_sw2" in *[!0-9smhd]*) break ;; esac           # ... and be a pure [0-9]+[smhd]? duration
        _sw=$(printf '%s' "$_sw" | sed -E 's/^[[:space:]]*timeout[[:space:]]+[0-9]+[smhd]?[[:space:]]+//') ;;
      nice)
        case "$_sw2" in
          -n)
            _sw3=$(printf '%s' "$_sw" | sed -E 's/^[[:space:]]*//' | awk '{print $3}')
            case "$_sw3" in ''|*[!0-9]*) break ;; esac        # `nice -n` needs a digit value
            _sw=$(printf '%s' "$_sw" | sed -E 's/^[[:space:]]*nice[[:space:]]+-n[[:space:]]+[0-9]+[[:space:]]+//') ;;
          -*) break ;;                                        # any other flag disqualifies
          *) _sw=$(printf '%s' "$_sw" | sed -E 's/^[[:space:]]*nice[[:space:]]+//') ;;   # bare nice
        esac ;;
      command)
        case "$_sw2" in -*) break ;; esac                     # command -v/-p/-V disqualify
        _sw=$(printf '%s' "$_sw" | sed -E 's/^[[:space:]]*command[[:space:]]+//') ;;
      env)
        [ -n "$_sw2" ] || break                               # `env` with no argument -> nothing to strip
        case "$_sw2" in -*|*=*) break ;; esac                 # BARE env only (constraint i; K-F pins)
        _sw=$(printf '%s' "$_sw" | sed -E 's/^[[:space:]]*env[[:space:]]+//') ;;
      time)
        case "$_sw2" in ''|-*) break ;; esac                  # BARE time only; `time -p` disqualifies
        _sw=$(printf '%s' "$_sw" | sed -E 's/^[[:space:]]*time[[:space:]]+//') ;;
      '{')
        [ -n "$_sw2" ] || break                               # a lone `{` has nothing to peel toward
        _sw=$(printf '%s' "$_sw" | sed -E 's/^[[:space:]]*\{[[:space:]]+//') ;;
      *=*)
        # Arm A: vetted-NAME assignment prefix. Both tests must pass or the loop breaks (-> deny).
        _swn=${_swl%%=*}; _swv=${_swl#*=}
        _cp8b_in_list "$_swn" "$_CP8B_VETTED_ASSIGN" || break
        _cp8b_assign_val_safe "$_swv" || break
        # TIGHTEN (security vet Finding 1, owner chose the narrowing cure): decline the peel when the
        # VALUE itself classifies control-plane. Without this the peel removes a CP-classifying token
        # from the recognition copy BEFORE the kit-exec token walk sees it, so
        # `SELFTEST=hooks/pre-push sh <kit-script>` would ALLOW — and it is NOT equivalence-covered,
        # because the two-statement spellings (`SELFTEST=hooks/pre-push ; sh …`, `export SELFTEST=…`)
        # both DENY (measured). This is ALLOW-side narrowing (a peel we decline to perform), not a deny
        # edit. Both spellings of the target are checked, exactly as _cp8b_tad_redir_cp does:
        #   literal  — `SELFTEST=hooks/pre-push …`                              (F2-KI3 pins)
        #   composed — `cd hooks && SELFTEST=pre-push …`, which composes to hooks/pre-push under the
        #              effective dir and was MEASURED ALLOW under a literal-only cure (F2-KI3b pins).
        # Both helpers take the whole `NAME=value` token: each already dequotes and strips the `flag=`
        # prefix, so they classify the VALUE by the same rule the token walk and composed trigger use.
        _cp8b_tok_is_cp "$_swl" && break
        _cp8b_composed_is_cp "$_swl" && break
        # Shape-restricted peel: name and value were both validated above, so this matches exactly the
        # lead token. A non-match makes no progress and the ≤3 bound then exits with a non-shell lead
        # -> not kit-exec -> deny (over-deny, safe).
        _sw=$(_cp8b_peel_lead_assign "$_sw") ;;
      *) break ;;
    esac
    _swi=$((_swi + 1))
  done
  printf '%s' "$_sw"
}
_cp8b_tad_is_kit_exec() {
  # FIX 2: mirror E5's read-arm narrowing — bail (fall through to deny) ONLY when a redirect TARGET
  # classifies control-plane. An fd-dup (`2>&1`, `>&2`, `N>&M`) and an ordinary target (`> /tmp/out`)
  # are non-targets, so the canonical `sh conformance/verify.sh 2>&1` / `> /tmp/out.log` stay kit-exec.
  # `_cp8b_tad_redir_cp` reuses the effective-dir compose, so `cd hooks && sh …verify.sh > pre-push`
  # still bails and denies (target composes to hooks/pre-push). An input `<` redirect target that is
  # control-plane is caught downstream by the literal-token walk below (a read, never a write).
  # C4 Arm 2 constraint iii: the redirect bail runs on the RAW `$1` FIRST, BEFORE wrapper stripping.
  case "$1" in *'>'*) _cp8b_tad_redir_cp "$1" && return 1 ;; esac
  # C4 Arm 2: peel vetted benign wrappers into a recognition-copy (`_kx`). Consumed ONLY below —
  # never fed to the outer trigger evaluation (:1311-1313) or the effective-dir logic (constraint ii).
  # SAFETY IS STRUCTURAL, NOT TEST-GUARDED: `_kx` is function-local and `$_seg`/`$1` are untouched
  # downstream, so no fixture pins this. A future refactor that assigns `_seg=$_kx` (leaking the
  # stripped copy back to the triggers) would NOT be caught by any mutant — the strip set is all
  # non-CP tokens, so such a leak cannot flip a verdict today, which is exactly why it is unmutatable
  # (design §10-A3, mutant K-F2 dropped-with-rationale). Keep `_kx` read-only to this arm.
  _kx=$(_cp8b_strip_wrappers "$1")
  _kv=$(_cp8b_lead "$_kx")
  case "$_kv" in
    sh|bash|dash|zsh|ksh) _ksc=$(printf '%s' "$_kx" | sed -E 's/^[[:space:]]*//' | awk '{print $2}') ;;
    *) _ksc=$_kv ;;
  esac
  _ksc=$(_cp8b_dequote "$_ksc"); _ksc=${_ksc#./}
  case "$_ksc" in
    conformance/*.sh|scripts/*.sh|scripts/kit-guard|scripts/sparkwright) : ;;
    *) return 1 ;;
  esac
  _kpg=0; case "$-" in *f*) _kpg=1 ;; esac
  set -f
  # shellcheck disable=SC2086
  set -- $_kx
  while [ $# -gt 0 ]; do
    _kt=$(_cp8b_dequote "$1"); _kt=${_kt#./}
    if [ "$_kt" != "$_ksc" ] && _cp8b_tok_is_cp "$1"; then [ "$_kpg" = 1 ] || set +f; return 1; fi
    shift
  done
  [ "$_kpg" = 1 ] || set +f
  return 0
}

# GUARD-READONLY-FP-RELIEF Arm A — the kit-exec READ-ONLY QUERY allowlist (cures register faces
# (f1)+(h) in ONE arm). `_cp8b_tad_is_kit_exec` above declines the WHOLE segment as soon as any
# token OTHER than the script classifies control-plane. That disqualifier is right for an unknown
# script (a CP path in argv may be a WRITE target — `sh conformance/verify.sh <cp>` must stay DENY),
# and wrong for the handful of DECLARED query modes whose entire job is to be ASKED about a path:
#   sh scripts/kit-guard path <cp>                                  — ask the guard about a path
#   sh conformance/promotion-readiness.sh --class --changed <listing>  — the ENTRY CONTRACT's act 1
#   sh conformance/agent-boundary.sh --changed <listing> --ratified 0  — its act-1 cross-check
#
# A PAIR MUST NAME A SCRIPT THAT EXISTS. The first cut of this table listed `conformance/phase-gate.sh`
# one merge after that script was parked and deleted: the arm is a pure token match and never stats the
# file, so the allow was unprovable and the behavioural lock below passed over a pair that could not run
# (GUARD-ALLOWLIST-OUTLIVES-ITS-SCRIPT). The lock now asserts existence before it runs a pair, so a
# table entry that outlives its script REDs by name instead of passing vacuously.
#
# THE ENFORCEMENT IS THE DECLARED TABLE, NOT A PARSE (D-240813-3: fail-by-parse cures are banned).
# `_cp8b_kit_query_toks` is the whole allowlist: an unknown script yields the empty set and the arm
# DECLINES, so every unlisted kit script keeps today's verdict with zero deny-side edits — the
# `_CP8B_VETTED_ASSIGN` shape. Adding a pair costs one table line, one leg, and a green coupling lock.
#
# ⚠️ READ-ONLINESS IS LOCKED BEHAVIORALLY, NOT BY REVIEW MEMORY (security vet M1). Every pair in this
# table is RUN against a fixture control-plane argument by `conformance/agent-autonomy.sh`'s Arm-A
# coupling lock, which asserts the repo worktree is byte-unchanged afterwards. A pair that GAINS a
# write path reds that lock. A grep-lock over this list would have been fail-by-hope.
#
# Decline-on-ANY (each is a disqualifier, so a bug here over-denies):
#   · any redirect byte (`<` or `>`) in the segment — `… --path CLAUDE.md > conformance/out.txt`
#   · any `$` / backtick — the guard reads PRE-shell-parse bytes and cannot resolve them
#   · any `..` byte in the script token (belt; the anchored exact table match is the primary)
#   · a script token that is not an EXACT table key after `./`-stripping (no path-alias spellings)
#   · a FIRST post-script token outside the declared set — this is what keeps the WRITER subcommand
#     `scripts/kit-guard install-shims` off the arm
#   · ANY other flag-shaped token outside the declared set (vet M1: presence-matching `--class` alone
#     would let `--class --<writer>` ride). Note the declared sets are per-script SETS, not a single
#     flag: `--class --changed` is already two flag tokens, so a literal one-flag rule could not cure
#     the named face. Non-flag tokens after the query token are DATA (the coupling lock is what makes
#     that safe), which is why a quoted `kit-guard cmd "<probe>"` still recognizes.
# The script position is POSITIONAL (token 1, or token 2 after a bare interpreter): an interpreter
# FLAG (`sh -x …`, `sh -c …`) or an env-assignment prefix lands in the script slot, misses the table
# and declines.
_cp8b_kit_query_toks() {
  case "$1" in
    scripts/kit-guard)                  printf '%s' 'path cmd mcp' ;;
    conformance/promotion-readiness.sh) printf '%s' '--class --changed' ;;
    conformance/agent-boundary.sh)      printf '%s' '--changed --ratified' ;;
  esac
}
_cp8b_tad_is_kit_query() {
  case "$1" in *'>'*|*'<'*) return 1 ;; esac
  case "$1" in *'$'*|*'`'*) return 1 ;; esac
  _kqg=0; case "$-" in *f*) _kqg=1 ;; esac
  set -f
  # shellcheck disable=SC2086  # deliberate word-split; globbing disabled above
  set -- $1
  [ $# -gt 0 ] || { [ "$_kqg" = 1 ] || set +f; return 1; }
  case "$1" in sh|bash|dash|zsh|ksh) shift ;; esac      # bare interpreter lead: script is next
  [ $# -gt 0 ] || { [ "$_kqg" = 1 ] || set +f; return 1; }
  _kqs=$(_cp8b_dequote "$1"); _kqs=${_kqs#./}; shift
  case "$_kqs" in *..*) [ "$_kqg" = 1 ] || set +f; return 1 ;; esac
  _kqv=$(_cp8b_kit_query_toks "$_kqs")
  [ -n "$_kqv" ] || { [ "$_kqg" = 1 ] || set +f; return 1; }
  [ $# -gt 0 ] || { [ "$_kqg" = 1 ] || set +f; return 1; }
  _cp8b_in_list "$1" "$_kqv" || { [ "$_kqg" = 1 ] || set +f; return 1; }
  while [ $# -gt 0 ]; do
    case "$1" in
      -*) _cp8b_in_list "$1" "$_kqv" || { [ "$_kqg" = 1 ] || set +f; return 1; } ;;
    esac
    shift
  done
  [ "$_kqg" = 1 ] || set +f
  return 0
}

# GUARD-READONLY-FP-RELIEF Arm B — shell TEST EXPRESSIONS (cures register face N1). `test -f <cp>`
# and `[ -f <cp> ]` interrogate a path's METADATA; neither builtin can mutate the path it names, so
# a control-plane token there is DATA in the strictest sense.
#
# ***THE LEAD SET IS `test` AND `[` ONLY — `if`/`elif` ARE DELIBERATELY EXCLUDED*** (security vet C1,
# substantiated live). `if`/`elif` do not introduce a test EXPRESSION; they introduce a COMMAND whose
# exit status is tested. `if rm <cp>; then :; fi` and `if node write.js <cp>; then :; fi` both wear
# the same "lead + operands" shape as a real test and both MUTATE. Re-adding either keyword to this
# case arm is a write-surface widening, and mutant M-B2 in agent-autonomy.sh exists to catch exactly
# that. An `if [ -f <cp> ]` false positive is cured only TRANSITIVELY — when the segmenter yields the
# inner `[ …` as its own segment; otherwise it keeps today's deny plus the §3 tip.
#
# Decline-on-ANY (a bug here over-denies): any redirect byte; any `$`/backtick; any flag-shaped token
# that is not EXACTLY a single-letter operator (`-exec`, `--remove`, `-pi` all decline — a long flag
# is an unknown, and the numeric comparators `-eq`/`-lt`/… decline with them, a disclosed over-deny
# on expressions that carry no path anyway); any token that is a known mutator verb.
# The mutator-verb list is a BELT: `_cp8b_control_plane_denied`'s verb regex already denies every
# member on this route, so no fixture can separate the two (stated, not claimed as coverage — the
# `_kx` precedent at C4 Arm 2). It is kept because the two lists drift independently.
_CP8B_TEST_MUTATORS='rm rmdir mv cp ln dd tee sed chmod chown install rsync shred truncate patch awk find sort uniq xxd git'
_cp8b_tad_is_test_expr() {
  case "$1" in *'>'*|*'<'*) return 1 ;; esac
  case "$1" in *'$'*|*'`'*) return 1 ;; esac
  _teg=0; case "$-" in *f*) _teg=1 ;; esac
  set -f
  # shellcheck disable=SC2086  # deliberate word-split; globbing disabled above
  set -- $1
  [ $# -gt 0 ] || { [ "$_teg" = 1 ] || set +f; return 1; }
  case "$1" in test|'[') shift ;; *) [ "$_teg" = 1 ] || set +f; return 1 ;; esac
  while [ $# -gt 0 ]; do
    case "$1" in
      -[A-Za-z]) : ;;                                    # a single-letter test operator
      -*) [ "$_teg" = 1 ] || set +f; return 1 ;;         # -exec / --remove / -pi / -eq -> unknown
      ']'|'!'|'='|'!='|'-') : ;;                          # expression punctuation
      *) if _cp8b_in_list "$1" "$_CP8B_TEST_MUTATORS"; then [ "$_teg" = 1 ] || set +f; return 1; fi ;;
    esac
    shift
  done
  [ "$_teg" = 1 ] || set +f
  return 0
}

# E3 — message carriers: git commit/merge/tag + gh pr/issue/release with a message flag and NO
# redirect. A control-plane hit is inside the message DATA, not a target (an injected `;` splits to its
# own segment and is judged there). The enforcement counterpart of the advisory _cp8b_message_tip.
_cp8b_tad_is_msg_carrier() {
  case "$1" in
    *"git commit"*|*"git merge"*|*"git tag"*|*"gh pr"*|*"gh issue"*|*"gh release"*) : ;;
    *) return 1 ;;
  esac
  case "$1" in *'>'*) return 1 ;; esac
  printf '%s' "$1" | grep -Eq '(^|[[:space:]])(-m|-F|--message|--body|--body-file|--notes|--title)([=[:space:]]|$)'
}

# _cp8b_tad_pathhit "<segment>": trigger 1 — string-level pathhit (single source of truth).
_cp8b_tad_pathhit() { _cp8b_pathhit "$1"; }

# _cp8b_tad_literal_tok "<segment>": trigger 2 — a LITERAL token classifies control-plane (M2 union:
# the literal arm is retained alongside the composed arm; a climb-out desync can never remove it).
_cp8b_tad_literal_tok() {
  _lpg=0; case "$-" in *f*) _lpg=1 ;; esac
  set -f
  # shellcheck disable=SC2086
  set -- $1
  while [ $# -gt 0 ]; do
    if _cp8b_tok_is_cp "$1"; then [ "$_lpg" = 1 ] || set +f; return 0; fi
    shift
  done
  [ "$_lpg" = 1 ] || set +f
  return 1
}

# _cp8b_tad_composed_tok "<segment>": trigger 3 — a cd-COMPOSED token (or composed redirect target)
# classifies control-plane.
_cp8b_tad_composed_tok() {
  [ -n "$_CP8B_EFF" ] || return 1
  _cts=$1                                # capture BEFORE set -- consumes the positionals (FIX 1)
  _cpg=0; case "$-" in *f*) _cpg=1 ;; esac
  set -f
  # shellcheck disable=SC2086
  set -- $1
  while [ $# -gt 0 ]; do
    if _cp8b_composed_is_cp "$1"; then [ "$_cpg" = 1 ] || set +f; return 0; fi
    shift
  done
  [ "$_cpg" = 1 ] || set +f
  # A GLUED redirect (`>pre-push`) is one token that composes to `hooks/>pre-push` (not CP), so the
  # loop above misses it; the redirect-target parse recovers the bare target. Passing $1 here was DEAD
  # CODE — the loop's `shift` empties the positionals, so the old `"$1"` was always "" (FIX 1).
  _cp8b_tad_redir_cp "$_cts"
}

# E6 — cp/install destination-binding: judge the copy DESTINATION (literal last token, per :1004-1005,
# OR the composed destination), not "any control-plane token" — so `cp conformance/verify.sh /tmp/b`
# (copy-OUT) stays ALLOW while `cd conformance && cp /tmp/x verify.sh` denies. Declines to close the
# open GUARD-CP-HARDLINK-ALIAS row (cp -l aliasing) — leaves it exactly as today, stated not claimed.
_cp8b_tad_cp_dest_denied() {
  _cp8b_cp_target_in last "$1" && return 0
  _cd=$(printf '%s' "$1" | awk '{for(i=NF;i>=1;i--) if(substr($i,1,1)!="-"){print $i; exit}}')
  _cp8b_composed_is_cp "$_cd" && return 0
  _cp8b_tad_redir_cp "$1"
}

# _cp8b_redir_launder_denied "<seg>": GUARD-CP-WRITE-ROUTES Cure 2 outright-deny — a READER / KIT-EXEC
# segment whose redirect target is NON-LITERAL (glob / $VAR / $(…) / backslash — _redir_targets rc 2)
# denies OUTRIGHT. Such a launder verb (printf/cat/`sh conformance/verify.sh`) declined recognition
# above precisely because its target disqualified; when there is ALSO no literal control-plane substring
# to trip the pathhit trigger (`printf x > hooks/pre-pus*` — a glob the shell would expand onto the real
# hook), nothing else denies it. This arm is that closer, and it is the disclosed `reader > $OUT`
# over-deny made real. SCOPED to reader/kit-exec (the disclosed ceiling, not every verb): recognition is
# re-tested on a redirect-STRIPPED copy, so an ordinary `make > $OUT` is NOT a laundering verb and stays
# allowed. Reuses the shared _redir_targets disqualifier (K-R1a pins this arm's disqualifier).
#
# GUARD-READONLY-FP-RELIEF Arm G(i) — THE CLOSE (this half DENIES MORE). Recognition ran on the
# segment's own lead, so wrapping the laundering verb in a brace group or subshell moved the redirect
# into a `}`/`)`-led segment this arm did not recognize, and the whole Cure-2 closure fell to two
# bytes: `{ printf evil ; } > $VAR/pre-push` and `( printf evil ) > $VAR/pre-push` were both MEASURED
# ALLOW at the 2026-08-19 probe. `_cp8b_strip_group` peels the group tokens and recognition is
# re-tested on the residual; a segment that is ONLY a group CLOSE (or has no verb at all — a bare
# `> $V/pre-push` truncate) is itself the laundering site and denies.
# DISCLOSED OVER-DENY, fixtured both ways: this is scoped by SEGMENT SHAPE, not by what the group
# contains — those live in a different segment. So `{ make ; } > $OUT` now denies while the bare
# `make > $OUT` still allows (the deliberate "not a laundering verb" scope). Spell the target
# literally, or drop the braces.
_cp8b_strip_group() {
  printf '%s' "$1" | sed -E 's/^[[:space:]]*[{(][[:space:]]+//; s/[[:space:]]*[})][[:space:]]*$//; s/^[[:space:]]+//; s/[[:space:]]+$//'
}
_cp8b_redir_launder_denied() {
  case "$1" in *'>'*) : ;; *) return 1 ;; esac
  _redir_targets "$1" >/dev/null && return 1   # rc 0 => every target is a plain literal => not this arm
  _lnr=$(printf '%s' "$1" | sed -e 's/[0-9]*>>*.*$//')   # drop from the first redirect operator onward
  _cp8b_tad_is_read "$_lnr" && return 0
  _cp8b_tad_is_kit_exec "$_lnr" && return 0
  _lng=$(_cp8b_strip_group "$_lnr")
  case "$_lng" in ''|'}'|')') return 0 ;; esac           # a bare group CLOSE / verbless redirect
  _cp8b_tad_is_read "$_lng" && return 0
  _cp8b_tad_is_kit_exec "$_lng" && return 0
  return 1
}

# _cp8b_target_reason "<segment>" "<trigger>": signpost the composition and name the cheap escape.
_cp8b_target_reason() {
  _trs=$(printf '%s' "$1" | cut -c1-160)
  printf '13: writes/executes against a resolved control-plane target (guard / CI gates / conformance) - denied (control-plane integrity; trigger=%s). Offending segment: [%s].%s%s Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.' "$2" "$_trs" "$(_cp8b_message_tip "${_tad_raw:-}" "$1")" "$(_cp8b_trigger_tip "$2")"
}

# C4 Arm 3 (face c) — remote-URL token disqualification for git-lead segments. Replaces each WHOLE
# url-shaped token with the placeholder `REMOTE-URL`: a remote URL is not a local write target, so its
# `.git` suffix / any CP substring inside it must not classify. A token is url-shaped iff it is
# SCHEME-BEARING (https|http|ssh|git ://) or SCP-FORM (user@host:path). `file://` is NEVER masked (a
# file URL IS a filesystem path — and its `.git` write stays DENY via the raw clone-dest arm). Masking
# is TOKEN-BOUNDED, never greedy (vet Finding 3, K-G2 pins): `[^[:space:]]*` stops at whitespace, so a
# following CP destination (`… .git hooks`) is never swallowed. No CP path is scheme-bearing or
# scp-shaped, so masking url-shaped tokens can never erase a real CP path token.
_cp8b_mask_remote_urls() {
  printf '%s' "$1" | sed -E \
    -e 's#(^|[[:space:]])(https|http|ssh|git)://[^[:space:]]*#\1REMOTE-URL#g' \
    -e 's#(^|[[:space:]])[A-Za-z0-9._~-]+@[A-Za-z0-9._-]+:[^[:space:]]*#\1REMOTE-URL#g'
}

# _cp8b_target_arm_denied "<cmd>": PREDICATE - Parts A+B+C. Prints the reason and returns 0 to deny.
_cp8b_target_arm_denied() {
  _tad_raw=$1
  _walk=$(_cp8b_segments "$(_cp8b_strip_heredocs "$1")")   # Arm E: a quoted heredoc BODY is inert data
  _CP8B_EFF=''
  while _cp8b_next_seg; do
    [ -n "$(printf '%s' "$_seg" | tr -d '[:space:]')" ] || continue
    _lv=$(_cp8b_lead "$_seg")
    if [ "$_lv" = cd ]; then _cp8b_eff_update "$_seg"; continue; fi
    case "$_lv" in pushd|popd) continue ;; esac        # dir change we cannot track -> no-op (keep prefix)
    _cp8b_tad_is_read "$_seg" && continue
    _cp8b_tad_is_kit_exec "$_seg" && continue
    _cp8b_tad_is_kit_query "$_seg" && continue   # Arm A: a DECLARED read-only kit query (see the table)
    _cp8b_tad_is_test_expr "$_seg" && continue   # Arm B: a `test`/`[` metadata expression
    _cp8b_tad_is_msg_carrier "$_seg" && continue
    case "$_lv" in
      cp|install)
        if _cp8b_tad_cp_dest_denied "$_seg"; then _cp8b_target_reason "$_seg" cp-dest; return 0; fi
        continue ;;
    esac
    # C4 Arm 3: for a git-lead segment, evaluate the three CP triggers on a recognition-copy in which
    # url-shaped tokens are masked (a remote URL's `.git` suffix is not a local write target). Reasons
    # print the ORIGINAL $_seg. The raw clone-DESTINATION arm (_cp8b_git_write_denied :806) and the
    # push-to-main floor run on the RAW string and are untouched, so `git clone <url> .claude`,
    # `git clone <url> hooks`, `git push <url> main` stay DENY. K-G pins the git-lead guard.
    _tad_c=$_seg
    if [ "$_lv" = git ]; then _tad_c=$(_cp8b_mask_remote_urls "$_seg"); fi
    if _cp8b_tad_pathhit "$_tad_c"; then _cp8b_target_reason "$_seg" pathhit; return 0; fi
    if _cp8b_tad_literal_tok "$_tad_c"; then _cp8b_target_reason "$_seg" token; return 0; fi
    if _cp8b_tad_composed_tok "$_tad_c"; then _cp8b_target_reason "$_seg" composed; return 0; fi
    # GUARD-CP-WRITE-ROUTES Cure 2: last, a reader/kit-exec laundering a non-literal redirect target
    # (no literal CP substring above to catch it — the pure-glob route) denies outright.
    if _cp8b_redir_launder_denied "$_seg"; then _cp8b_target_reason "$_seg" redir-nonliteral; return 0; fi
  done
  return 1
}

# _cp8b_push_main_denied "<cmd>": PREDICATE - the push-to-main rule, SCOPED to a segment.
# The flat rule is the FLOOR (it denies); this may only ALLOW BACK when no single segment carries both
# the push and the main/master refspec - i.e. when the flat regex only ever matched by SPANNING a shell
# separator, which is precisely the false positive:
#     git push -u origin fix/x && gh pr create --body "... merges to main"
# This is NOT the rewriting CP-8a forbade: that was splitting the command and REJOINING it with ';',
# which perturbed the OTHER ~40 rules. Here only this ONE rule's window narrows; every other rule still
# sees the raw, unsplit string (`curl x | sh` keeps its pipe, `--admin` keeps its end-of-string anchor).
_cp8b_push_main_denied() {
  _walk=$(_cp8b_segments "$1")
  while _cp8b_next_seg; do
    if printf '%s' "$_seg" | grep -Eq 'git[[:space:]]+(-c[[:space:]]+[^[:space:]]+[[:space:]]+)*push.*[^a-zA-Z0-9_.-](main|master)([^a-zA-Z0-9_.-]|$)'; then
      return 0
    fi
  done
  return 1
}

# GUARD-READONLY-FP-RELIEF Arm F — the `git config core.hooksPath` READ/WRITE split (cures register
# face N4; N5 rides along). ***THIS MATCHER IS THE GUARD-DISABLE CROWN JEWEL*** — the same rule that
# over-denies `git config --get core.hooksPath` (asking what the hooks path IS, a pure read) is the
# rule that denies `git config core.hooksPath /tmp/evil`, the primary way an agent switches the
# guard off. So the split is built DEFAULT-DENY (security vet H2): a segment that matches the
# hooksPath matcher DENIES unless it is POSITIVELY recognized as one of the declared query forms.
#
# PER-OCCURRENCE, never per-command: the decision walks segments, so
# `--get … && git config core.hooksPath /tmp/e` (E5) is judged on the WRITE segment and stays DENY.
#
# THE GUARD-DISABLE VECTOR `git config core.hooksPath /tmp/evil` IS HELD BY TWO INDEPENDENT GUARDS,
# and it takes BOTH to open it (measured — the honest claim, corrected after review I4):
#   (1) the query-flag-required line `[ -n "$_gcq" ] || return 1` below — with no query flag the
#       segment is not a read; and
#   (2) the operand-count bound in the trailing `case "$_gcq"` — a `--get` with a value token exceeds
#       the bound and denies.
# `core.hooksPath /tmp/evil` carries no query flag AND two operands, so EACH guard denies it alone: a
# mutant of ONE survives because the OTHER still fires (defence in depth, not redundancy claimed as
# coverage). Only the PAIR opens it — that is why the gate-time kill is M-F6 (removes both, flips it),
# not a single-guard mutant. M-F1 and M-F5 each show one guard alone still holds.
#
# NEVER RECOGNIZED AS A READ, by construction (vet H2 + L2): any segment whose second token is not
# literally `config` — which is what keeps `-c`/`-C`/`--exec-path` carriers off this arm — and any
# segment carrying an option outside the two declared lists. The PRE-EXISTING inline-`-c` hole
# (`git -c core.hooksPath=/tmp/evil <subcmd>` ALLOWs today, because the flat matcher below requires
# `git config` adjacency) is UNCHANGED here and boarded as GUARD-GIT-INLINE-C-HOOKSPATH-HOLE; this
# arm must never be widened to "recognize" such a segment.
# DISCLOSED RIDER (probe surprise 9): `--get-regexp` takes a PATTERN, so a key-spelling that matches
# `core.hooks` without spelling `core.hooksPath` never reaches the flat matcher at all — pre-existing,
# unchanged, and not claimed closed.
_CP8B_GITCFG_QUERY='--get --get-all --get-regexp --get-urlmatch --list -l'
# Read-side scope/output modifiers, each verified to select or format a READ and never to write.
# `--file`/`--blob`/`--config-env`/`-c` are deliberately ABSENT: default-deny sends them to the deny.
_CP8B_GITCFG_SCOPE='--global --local --system --worktree --null -z --name-only --show-origin --show-scope'
_cp8b_gitcfg_is_read() {
  case "$1" in *'>'*|*'<'*) return 1 ;; esac
  case "$1" in *'$'*|*'`'*) return 1 ;; esac
  _gcg=0; case "$-" in *f*) _gcg=1 ;; esac
  set -f
  # shellcheck disable=SC2086  # deliberate word-split; globbing disabled above
  set -- $1
  if [ "${1:-}" != git ];    then [ "$_gcg" = 1 ] || set +f; return 1; fi
  shift
  if [ "${1:-}" != config ]; then [ "$_gcg" = 1 ] || set +f; return 1; fi
  shift
  _gcq=''; _gco=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -*)
        if _cp8b_in_list "$1" "$_CP8B_GITCFG_QUERY"; then
          if [ -n "$_gcq" ]; then [ "$_gcg" = 1 ] || set +f; return 1; fi   # two query flags: unknown
          _gcq=$1
        elif _cp8b_in_list "$1" "$_CP8B_GITCFG_SCOPE"; then
          :
        else
          [ "$_gcg" = 1 ] || set +f; return 1                               # DEFAULT-DENY on unknowns
        fi ;;
      *) _gco=$((_gco + 1)) ;;
    esac
    shift
  done
  if [ -z "$_gcq" ]; then [ "$_gcg" = 1 ] || set +f; return 1; fi   # <== THE CROWN-JEWEL LINE (M-F1)
  case "$_gcq" in
    --list|-l)      if [ "$_gco" -ne 0 ]; then [ "$_gcg" = 1 ] || set +f; return 1; fi ;;
    --get-urlmatch) if [ "$_gco" -gt 2 ]; then [ "$_gcg" = 1 ] || set +f; return 1; fi ;;
    *)              if [ "$_gco" -gt 1 ]; then [ "$_gcg" = 1 ] || set +f; return 1; fi ;;
  esac
  [ "$_gcg" = 1 ] || set +f
  return 0
}
# N5 — a commit/PR MESSAGE that merely NAMES the key is data, not a config write. The exemption is
# narrowed beyond `_cp8b_tad_is_msg_carrier` by a `$`/backtick decline: without it,
# `git commit -m "$(git config core.hooksPath /tmp/evil)"` would wear the message costume while the
# substitution ran the real write (measured DENY today; it must stay DENY).
# ***REVIEW C1 (2026-08-19): the exemption MUST anchor on the LEADING token pair, not a substring.***
# `_cp8b_tad_is_msg_carrier` is a substring match, so a trailing shell COMMENT
# (`git config core.hooksPath /tmp/evil # git commit -m x`) put the `git commit` bytes anywhere in the
# segment and stole the exemption while the REAL lead ran the hooksPath write — measured ALLOW on the
# branch, DENY on main, a write-path widening this slice opened. A genuine message carrier LEADS with
# `git commit`/`gh pr`/…, so keying on the first two whitespace-normalized tokens closes it and moves
# no other verdict (the F3 comment-suffix battery + mutant M-F7 pin it).
_cp8b_gitcfg_msg_data() {
  case "$1" in *'$'*|*'`'*) return 1 ;; esac
  _gmd=$(printf '%s' "$1" | sed -E 's/^[[:space:]]*//; s/[[:space:]]+/ /g' | cut -d' ' -f1,2)
  case "$_gmd" in
    "git commit"|"git merge"|"git tag"|"git notes"|"gh pr"|"gh issue"|"gh release") : ;;
    *) return 1 ;;
  esac
  _cp8b_tad_is_msg_carrier "$1"
}

# guard_check_command "<cmd>": print reason + return 1 if denied, else return 0.
guard_check_command() {
  cmd=$1
  # --- control-plane shell mutation (moved from guard.sh:81-93, + new files) ---
  # GUARD-HOOKSPATH-CASE-BYPASS: unconditional case-fold (`-Eq` -> `-Eiq`), no fork. Git config
  # KEYS are case-insensitive by spec on every platform, so this can only ever ADD a deny — no
  # legitimate command sets a DIFFERENT config key that differs from core.hooksPath only by case.
  # GUARD-READONLY-FP-RELIEF Arm F: the flat matcher is UNCHANGED (same regex, same `-Eiq` fold) and
  # is now the CANDIDATE selector, evaluated per SEGMENT; the read/write decision is the default-deny
  # recognizer above. Segmenting also joins backslash-continuations, so `git config \<nl> core.hooksPath
  # /tmp/evil` — measured ALLOW before this slice, a line-oriented-grep hole — now denies.
  if ! selfedit_allowed; then
    _walk=$(_cp8b_segments "$cmd")
    while _cp8b_next_seg; do
      printf '%s' "$_seg" | grep -Eiq 'git[[:space:]]+config[[:space:]]+([^;&|]*[[:space:]])?core\.hooksPath' || continue
      _cp8b_gitcfg_msg_data "$_seg" && continue
      _cp8b_gitcfg_is_read "$_seg" && continue
      printf '%s' '13: git config core.hooksPath would disable the agent guard - human-gated. Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'; return 1
    done
  fi
  # --- B2 Δ4(i)′: RAW `git notes` WRITES to the promotion GO ledger (refs/notes/promotions) -----
  # WHAT THIS IS. A DRIFT CONTROL, per owner ruling D3′ (2026-07-28): "BUILD the prevention as a
  # drift control, with the FULL measured bypass set stated in the ceiling … the threat is a model
  # that IGNORES the kit, not one that ATTACKS it … Denying the default route changes default
  # behaviour, which is the goal." The default route is what the D-240805-3 incident actually took:
  # a subagent minted an owner-attributed GO record with a bare `git notes add`. That route is now
  # denied. NOTHING MORE IS CLAIMED.
  #
  # WHAT IS DENIED: the raw `git notes` WRITE verbs (add · append · copy · edit · remove · prune ·
  # merge — copy included, it overwrites a target's note) when the command text targets the
  # promotions ref in any spelling (--ref=promotions · --ref promotions · quoted · the full
  # refs/notes/promotions name).
  # WHAT IS NOT DENIED, deliberately: the ceremonial front door (scripts/promotion-verify.sh
  # record — it DERIVES the assurance label instead of accepting one), every read (show/list),
  # notes on any OTHER ref (fixtures, refs/notes/commits), and the ledger's own publish push
  # (`git push origin refs/notes/promotions`, the front door's share step).
  #
  # ⚠️ THE COMPLETE MEASURED BYPASS SET — every one of these needs NO override and is NOT caught
  # (measured independently by both review seats, 2026-08-07; the earlier claim that "any direct
  # forge of the notes ref via shell is denied" was FALSE when it was ruled on, and is retracted):
  #   1. git PLUMBING: `git hash-object` -> `git mktree` -> `git commit-tree` -> `git update-ref
  #      refs/notes/promotions` mints a valid owner-attributed record with zero denied commands.
  #   2. DESTRUCTION: `git update-ref -d refs/notes/promotions` and
  #      `git push origin :refs/notes/promotions` delete the ledger outright.
  #   3. ALIAS INDIRECTION: `git config alias.x "notes --ref=promotions add ..."` then `git x`.
  #   4. FETCH REFSPEC: `git fetch <remote> '+<src>:refs/notes/promotions'` writes the ref.
  #   5. ENV SPELLINGS: `GIT_NOTES_REF=refs/notes/promotions git notes add …` (the bare-ref
  #      alternative below catches the common form; an indirect spelling does not appear in $cmd).
  #   6. INTERPRETER WRAPPERS: python/node/ruby -c, or any script file, invoking the same git calls.
  #   7. PUSH REFSPEC ONTO THE LEDGER: `git push origin refs/notes/<src>:refs/notes/promotions`
  #      overwrites the ledger from any local ref — measured ALLOW (round 2, sec L-new-1). Entry 2
  #      covers only the DELETE spelling (`:refs/notes/promotions`) and entry 4 only `git fetch`,
  #      so the WRITE-by-push route was missing from a set that called itself COMPLETE. The FORCED
  #      spelling (`+refs/notes/<src>:refs/notes/promotions`) is denied by the unrelated
  #      force/mirror-push rule, not by this arm — that is not coverage, and the unforced form is
  #      enough to overwrite a ref the remote fast-forwards or accepts outright.
  #   8. SYMBOLIC-REF: `git symbolic-ref refs/notes/promotions refs/notes/<other>` repoints the
  #      ledger NAME at another ref — measured ALLOW. It was named in the prose below, which is not
  #      the SET, so it is numbered here.
  #   9. THE SENTINEL ITSELF, under `install-shims` only — see THE SENTINEL below for the
  #      runtime-scoped measurement.
  # NOT in this set, because it is now COVERED (GUARD-HOOKSPATH-CASE-BYPASS): a case-variant ref
  # spelling — `git notes --ref=PROMOTIONS add`, `refs/notes/PROMOTIONS` — is denied the same as the
  # lowercase form. On macOS loose refs are ordinary files, so the uppercase spelling would otherwise
  # write the exact same `.git/refs/notes/promotions` governance ledger the lowercase form protects;
  # the ref-match leg above folds case for that reason. This does not touch entries 1-9: those are a
  # DIFFERENT class (plumbing/destruction/alias/refspec/interpreter/sentinel), still disclosed as-is.
  # These are NOT matched ON PURPOSE. Extending the matcher to update-ref/symbolic-ref/fetch and
  # push refspecs is the ARMS RACE vetoed by the 2026-07-28 design §4 ("no text/graph predicate over
  # author-controlled input") and permanently dropped by [S1]; it would fail the friction test
  # (it binds nothing the moment the model stops cooperating) while growing false denials.
  #
  # THE HONEST CONTROL IS NOT THIS ARM. It is Δ4(ii)'s VISIBILITY: the matched GO record is
  # rendered at the CI judgment surface before the owner's click (D-240805-4), which binds whether
  # or not the model cooperates. Plus the subagent-brief ledger-write prohibition (process).
  # A note BINDS, it does not AUTHENTICATE (scripts/promotion-verify.sh:38-44) — an agent running
  # under the owner's git identity can mint a front-door record and no local mechanism can tell.
  # PREVENTION IS NOT CLAIMED.
  #
  # THE SENTINEL, and why it is honest to ship a forgeable one [B2 sec H1]. Under `kit-guard
  # install-shims` EVERY git invocation is routed through this arm, including promotion-verify.sh's
  # OWN single note write — so the arm blocked the very door its deny message points at, and the
  # ledger became unwritable by any route (measured, not theorised). promotion-verify.sh exports
  # KIT_PROMOTION_FRONT_DOOR=1 around that one write and this arm honours it. IT IS
  # AGENT-FORGEABLE — BUT IN ONE RUNTIME ONLY, and the earlier flat claim ("an agent can prefix the
  # same variable to a raw command") over-stated it. MEASURED BOTH WAYS (round 2, sec L-new-1):
  #   * under `kit-guard install-shims` the shim rebuilds the command from ARGV (`c=$self; for a in
  #     "$@"`), so the `KIT_PROMOTION_FRONT_DOOR=1` prefix never appears in the text this arm reads —
  #     the shell EXPORTS it into the shim's, and therefore this arm's, own environment => ALLOW.
  #   * under the Claude hook / `kit-guard cmd` runtime the prefix arrives INSIDE the command TEXT
  #     and this arm's environment does not carry it => DENY (the raw write is still refused).
  # So the forgeability is entry 9 in the set above, SCOPED to install-shims. Erring safe was right;
  # stating it unscoped was not. Either way it is consistent with the posture, not a hole in a wall —
  # the wall is Δ4(ii).
  # Over-deny residual, accepted: a `git notes` write to a FIXTURE ref whose -m message merely
  # MENTIONS refs/notes/promotions is denied, and so are the conformance fixtures that write
  # `--ref=promotions` inside throwaway repos when they are run under shims (they are not, in CI).
  # No KIT_GUARD_SELFEDIT hint on THIS rule (L2): the one rule whose purpose is to stop
  # record-minting must not close by naming its own off-switch.
  # GUARD-HOOKSPATH-CASE-BYPASS (Fix 1, dual-review round): the REF-NAME leg folds too — on macOS
  # loose refs are ordinary FILES, so `git notes --ref=PROMOTIONS add` writes the same
  # `.git/refs/notes/promotions` file as the lowercase form; this is the same case-variance class as
  # every other fold in this slice (config keys, secret names), not the ref-name family's OTHER
  # disclosed bypasses (plumbing/update-ref/refspecs/alias — those stay exactly as disclosed below).
  # `-Eq` -> `-Eiq` on THIS leg only: the verb leg (next line up) and the write-verb leg (below) stay
  # byte-literal, deliberately — folding them would not narrow the over-deny risk, only widen it for
  # no gain, since "notes"/"add" etc are already case-invariant tokens in practice for this arm's
  # own fixtures. Monotone: a strict superset of the match, so no DENY can become an ALLOW.
  if ! selfedit_allowed \
     && [ "${KIT_PROMOTION_FRONT_DOOR:-}" != "1" ] \
     && printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])git[[:space:]]+([^;&|]*[[:space:]])?notes[[:space:]]' \
     && printf '%s' "$cmd" | grep -Eiq -- "--ref[= ][\"']?(refs/notes/)?promotions[\"']?([[:space:]]|\$)|refs/notes/promotions" \
     && printf '%s' "$cmd" | grep -Eq 'notes[[:space:]]([^;&|]*[[:space:]])?(add|append|copy|edit|remove|prune|merge)([[:space:]]|$)'; then
    printf '%s' '13: raw `git notes` WRITE verbs (add/append/copy/edit/remove/prune/merge) on refs/notes/promotions are denied - this is the default route a drifting agent takes to mint a GO record (governance-ledger integrity, D-240805-3). Use the front door: scripts/promotion-verify.sh record, which derives the assurance label; publish with `git push origin refs/notes/promotions`. NOT covered, and not claimed to be: git plumbing (hash-object/mktree/commit-tree/update-ref), ledger DESTRUCTION (`update-ref -d`, `push origin :refs/notes/promotions`), alias indirection, fetch OR PUSH refspecs whose DESTINATION is the ref, `symbolic-ref` repointing the ref, GIT_NOTES_REF spellings, interpreter wrappers - see the ceiling at this rule. The control that binds is the record rendered at the CI judgment surface, not this deny.'; return 1
  fi
  # CP-8b: the CO-OCCURRENCE block that used to live here matched a mutation verb and a control-plane
  # path ANYWHERE in the flat string, and never asked whether the verb's TARGET was that path — which
  # is both why `cp conformance/x /tmp/b` (copying OUT) was denied and why `git archive -o conformance/x`
  # (a real write) was allowed. It is replaced by a SEGMENT WALK that binds each segment's leading verb
  # to that segment's OWN arguments, plus subcommand-bound git write-primitives (which also absorb
  # CP-8a's `git … --output` deny, narrowing its scope from "any git" to the subcommands that honor it).
  # Monotone: every relaxation inside the predicate is an allow-back gated on POSITIVE recognition, so a
  # bug there over-denies and cannot over-allow.
  if ! selfedit_allowed; then
    if _cp8b_reason=$(_cp8b_control_plane_denied "$cmd"); then
      # Belt-and-suspenders: every deny arm inside the predicate already prints a reason via
      # _cp8b_deny_reason / _cp8b_git_write_denied, but a blank reason must NEVER reach the adapter (it
      # would surface as an empty permissionDecisionReason - a blocked agent with no guidance). Default it.
      [ -n "$_cp8b_reason" ] || _cp8b_reason='13: mutating the guard / its config / CI gates via shell is denied (control-plane integrity). Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'
      printf '%s' "$_cp8b_reason"; return 1
    fi
    # GUARD-BASENAME-AFTER-CD-BYPASS + GUARD-INTERPRETER-FAMILY-BYPASS: the resolved-target arm.
    # UNION with the old arm above (deny = old-verb-arm ∨ new-target-arm). The old arm is retained
    # verbatim, so this can only ever ADD a denial (monotone; panel #19 add-only shape).
    if _cp8b_reason=$(_cp8b_target_arm_denied "$cmd"); then
      [ -n "$_cp8b_reason" ] || _cp8b_reason='13: writes against a resolved control-plane target via shell is denied (control-plane integrity). Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'
      printf '%s' "$_cp8b_reason"; return 1
    fi
  fi
  # H3a: secret-in-context (shell) — a content-read verb (cat/grep/strings/diff/awk/...; also
  # source/. which load a .env into the environment) targeting secret material pulls it into the
  # agent's context: the read half of exfil. Human-gate it, symmetric with the secret-WRITE deny in
  # guard_check_path. ls (metadata) is excluded; template env files (.env.example/.sample/.template/
  # .dist) are NOT in the secret-suffix list so they stay allowed (no command-wide exclusion, which
  # a `cat .env.example .env` multi-arg form could abuse). Honest ceiling: an interpreter
  # (python -c open()) or an uncommon content-emitter not in the verb list bypasses — the robust
  # path is the Read-tool deny (guard_check_read) + platform containment. Asymmetry by design: the
  # shell path enumerates common .env.<suffix> files, while the Read tool's `*.env.*` glob catches
  # any suffix (e.g. `.env.foo` / `.env.local.bak` slip the shell path but the Read equivalent denies).
  # GUARD-HOOKSPATH-CASE-BYPASS (seat HIGH, condition 2): BOTH legs fold (`-Eq` -> `-Eiq`). The
  # verb leg first — on a case-insensitive filesystem `/bin/CAT` resolves to `/bin/cat`, so a
  # byte-literal verb match is the same defect as a byte-literal path match (precedent in-file:
  # `:894-899` folds the CP-arm verbs, "same defect, one argument position to the left"). Then the
  # filename leg. Deny-side only; `.env.example` stays ALLOW because "example" is never a listed
  # suffix alternative — folding case cannot add it (design §4a).
  # GUARD-DENY-TRIO M2 (F3, D-240816-1): the verb leg now also lists CONTENT-DIGEST verbs
  # (md5/md5sum/shasum/sha*sum/cksum/sum/b2sum/b3sum/rhash/xxhsum/crc32/gpg/digest, and `openssl` scoped
  # to its TWO-WORD subcommand form `openssl dgst|sha256|…` — a bare `openssl` would over-match
  # `openssl rsa -in server.key`). A digest of a secret is a CONFIRMATION ORACLE (candidate-value
  # verification / offline brute-force of a short secret), categorically worse than metadata. METADATA
  # verbs (wc/stat/du/ls/file) stay OFF this list — the disclosed, accepted trade, fixtured both ways.
  # HONEST CEILING, stated not implied-closed: this list is NON-EXHAUSTIVE under the SAME interpreter/
  # unknown-binary ceiling the content-read arm already carries — `certutil`, a scripted `openssl -in`,
  # `python -c hashlib`, any renamed digester slips it. The oracle is NARROWED, not closed; the
  # complete-by-disqualification fix (invert to a positive metadata allowlist) is M-sized and boarded
  # separately. `_CP8B_READ_VERBS`' vetting of digests as harmless is UNCHANGED — a digest of a CONTROL-
  # PLANE config is genuinely harmless, so the secret/CP asymmetry is intentional and fixtured both ways.
  if ! selfedit_allowed \
     && printf '%s' "$cmd" | grep -Eiq '(^|[;&|]|[[:space:]])[[:space:]]*((cat|less|more|head|tail|grep|egrep|fgrep|rg|strings|xxd|od|hexdump|base64|nl|tac|diff|cmp|comm|awk|sed|sort|uniq|cut|paste|fold|jq|yq|rev|source|\.|md5|md5sum|shasum|sha1sum|sha224sum|sha256sum|sha384sum|sha512sum|cksum|sum|b2sum|b3sum|rhash|xxhsum|crc32|gpg|digest)[[:space:]]|openssl[[:space:]]+(dgst|sha1|sha224|sha256|sha384|sha512|sha3-224|sha3-256|sha3-384|sha3-512|md5|md5sum|rmd160|blake2b512|blake2s256|shake128|shake256)([[:space:]]|$))' \
     && printf '%s' "$cmd" | grep -Eiq '\.env(\.(local|production|development|staging|test|prod|dev|stage|qa|preview|ci|bak|old))?([[:space:];|&*]|$)|\.(pem|key)([[:space:];|&*]|$)|id_rsa|(^|[[:space:]/;|&])secrets?/'; then
    printf '%s' '13: reading secret material into context (the read half of exfil -> model/logs/PR) is human-gated. Use .env.example / a secrets manager / redact; KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'; return 1
  fi
  # --- destructive matrix: moved VERBATIM from the PRE-SPLIT guard.sh (see git history; the line
  #     range that stood here died with the split) ---
  # CP-8a: the leading verb decides whether the ARGUMENTS are code or data. These carry
  # identical bytes and only the verb tells them apart:
  #     bash -c "rm -rf /"          <- the argument is CODE (a weapon) -> must DENY
  #     grep -rn "rm -rf" scripts/  <- the argument is DATA (a search) -> must ALLOW
  # A provably read-only SINGLE invocation therefore skips the matrix. Everything else
  # falls through with the command UNCHANGED, so no rule below has its input perturbed.
  # CP-8a (security re-review of #297): git's diff machinery (diff/log/show) honors
  # --output=<file> — an arbitrary file WRITE/TRUNCATE with NO shell redirect, so it slips both
  # the control-plane block above and (as a read verb) the exemption below.
  # `git diff --output=.github/workflows/ci.yml HEAD` zeroes the workflow on a clean tree.
  # Do NOT parse the --output TARGET: the guard sees PRE-shell-parse bytes, so any quoting /
  # escaping / substitution of the target (`--output="conformance/x"`, `--output=$(...)`) evades a
  # path match while git still writes the real path (a live bypass caught in re-review). Deny
  # `git ... --output` OUTRIGHT — fail-closed, no target to parse. The legitimate residual is a
  # plain redirect to a non-control-plane path (`git diff > /tmp/x`, which the guard allows) or
  # KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.
  # CP-8b: CP-8a's blanket `git … --output` deny lived here. It is now SUBCOMMAND-BOUND inside
  # _cp8b_git_write_denied (called above): still an OUTRIGHT deny with no target parsed, but scoped to
  # the subcommands that actually honor the flag (diff/log/show/format-patch/archive). That removes the
  # residual CP-8a recorded — `git commit -m "… --output …"`, where a commit message merely *mentions*
  # the flag and `-o` means `--only` — without weakening the deny for any subcommand that can write.
  if guard_read_only_command "$cmd"; then return 0; fi
  # recursive rm in any flag arrangement (-rf, -fr, -r -f, --recursive), bounded so
  # 'confirm'/'npm' are not matched, but quoted forms (bash -c "rm -rf") are.
  if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])rm[[:space:]]+([^;&|]*[[:space:]])?(-[[:alnum:]]*[rR]|--recursive)'; then
    { printf '%s' '13: recursive rm is irreversible - human-gated.'; return 1; }
  fi
  # 9b: non-recursive rm of a DANGEROUS target — a glob, a data/critical file extension,
  # an absolute path, or a dotfile of record. Anchored to command position so a commit
  # message mentioning rm is not matched. Plain relative single files (rm stale.txt,
  # rm dist/bundle.js) remain ALLOWED to avoid over-blocking normal dev work.
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]]'; then
    if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]]+([^;&|]*[[:space:]])?(--[[:space:]]+)?[^;&|[:space:]]*[*?[][^;&|[:space:]]*([[:space:]]|$)' \
       || printf '%s' "$cmd" | grep -Eiq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]][^;&|]*\.(db|sqlite|sqlite3|sql|dump|pgdump|bak|rdb|mdb)([[:space:]]|$)' \
       || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]]+([^;&|]*[[:space:]])?/[^[:space:]]' \
       || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]][^;&|]*(\.env|/\.git)([[:space:]]|$|/)' \
       || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]]+([^;&|]*[[:space:]])?\.env([[:space:]]|$)'; then
      { printf '%s' '13: rm of a glob, data file, absolute path, or dotfile-of-record can be irreversible - human-gated.'; return 1; }
    fi
  fi
  # 9b: non-rm destruction primitives. Binaries are anchored to COMMAND POSITION
  # (start, or after a ; && || | separator, optional sudo) so a word like "truncate"
  # inside a commit message is NOT matched — only an actually-invoked command is.
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?(truncate|shred|wipefs|blkdiscard|mkfs(\.[a-z0-9]+)?)([[:space:]]|$)'; then
    { printf '%s' '13: in-place file/device destruction (truncate/shred/wipefs/blkdiscard/mkfs) is irreversible - human-gated.'; return 1; }
  fi
  # dd is a scalpel like rm: deny only when of= targets a device or a data-file extension
  # (dd of=test-fixture.img stays allowed; dd of=/dev/sda and dd of=db.sqlite are denied).
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?dd[[:space:]]' \
     && printf '%s' "$cmd" | grep -Eiq 'of=(/dev/|[^[:space:]]*\.(db|sqlite|sqlite3|sql|dump|pgdump|bak|rdb|mdb)([[:space:]]|$))'; then
    { printf '%s' '13: dd of= a device or data file overwrites it irreversibly - human-gated.'; return 1; }
  fi
  # redirection/empty-source truncation of an existing target. GENERIC by target: the
  # patterns below match ANY destination ([^[:space:]&|;]+), so truncating a scanner-config
  # (e.g. `: > .gitleaks.toml`) is already covered here — no path enumeration needed (KW10).
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*):[[:space:]]*>[[:space:]]*[^[:space:]&|;]+' \
     || printf '%s' "$cmd" | grep -Eq '/dev/null[[:space:]]*>[[:space:]]*[^[:space:]&|;]+' \
     || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(cat|cp)[[:space:]]+/dev/null[[:space:]]+[>]?[[:space:]]*[^[:space:]&|;]+' \
     || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)echo[[:space:]]+-n[[:space:]]*>[[:space:]]*[^[:space:]&|;]+'; then
    { printf '%s' '13: redirection/empty-source truncation zeroes a file irreversibly - human-gated. TIP: to create or replace a file, use the Write tool (a shell >/: truncation is denied because it can irreversibly zero an existing file).'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?find[[:space:]]+[^|]*-delete([[:space:]]|$)' \
     || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?find[[:space:]]+[^|]*-exec[[:space:]]+(rm|shred|truncate)([[:space:]]|$)' \
     || printf '%s' "$cmd" | grep -Eq '\|[[:space:]]*(sudo[[:space:]]+)?xargs[[:space:]]+([^|]*[[:space:]])?(rm|shred|truncate|unlink|wipefs)([[:space:]]|$)'; then
    { printf '%s' '13: bulk irreversible deletion (find -delete / -exec rm / pipe to xargs rm) - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rsync[[:space:]]+[^|]*--delete([[:space:]]|$|[^a-z])'; then
    { printf '%s' '13: rsync --delete mirrors a source and removes destination files irreversibly - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)git[[:space:]]+clean[[:space:]]+[^|]*-[a-z]*[fdx]'; then
    { printf '%s' '13: git clean -f/-d/-x force-deletes untracked/ignored files irreversibly - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?mv[[:space:]]+[^;&|]*[[:space:]]/dev/null([[:space:]]|$)'; then
    { printf '%s' '13: moving a file onto /dev/null destroys its contents - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+reset[[:space:]]+.*--hard'; then
    { printf '%s' '13: git reset --hard discards work irreversibly - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(npm|yarn|pnpm)[[:space:]]+publish'; then
    { printf '%s' '13: publishing a package is externally irreversible - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+(-c[[:space:]]+[^[:space:]]+[[:space:]]+)*push.*(--force|--force-with-lease|--mirror|[[:space:]]-f([[:space:]]|$)|[[:space:]+]\+[^[:space:]]*[[:space:]]*$)'; then
    { printf '%s' '13: force/mirror push rewrites or deletes published history - human-gated.'; return 1; }
  fi
  # push to main/master in any refspec form: 'main', '+main', 'HEAD:main', 'x:master', "main" (incl. git -c … push)
  # CP-8b: SCOPED to a segment. The identical regex now runs per-segment instead of over the flat string,
  # so it can no longer match by SPANNING a shell separator — which is the whole false positive:
  #     git push -u origin fix/x && gh pr create --body "… merges to main"
  # (`git push` in segment 1, the word "main" in segment 2's PR body). A real push to main keeps both on
  # ONE segment and still denies. Only THIS rule's window narrows; every other matrix rule below still
  # sees the raw, unsplit command (`curl … | sh` keeps its pipe; `--admin` keeps its end-of-string anchor).
  # The segmenter also JOINS backslash-newline continuations first, which closes a pre-existing hole:
  # grep is line-oriented, so `git push \<newline> origin main` put `push` and `main` on different lines
  # and the flat regex matched NEITHER.
  if _cp8b_push_main_denied "$cmd"; then
    { printf '%s' '13: pushing directly to main/master bypasses review - open a PR (human-gated).'; return 1; }
  fi
  # S6: gh pr merge --admin/--administrator BYPASSES branch protection (incl. the control-plane-
  # ratification / required-review gate) — the fox opening its own henhouse. A SPEED BUMP (string
  # match): the real boundary is the platform never issuing the agent an admin credential
  # (docs/enterprise/platform-safety-boundary.md). The agent's sanctioned path is a NORMAL merge on
  # a recorded authenticated GO (scripts/promotion-verify.sh actuate); --admin is the SOLO kill-switch.
  if printf '%s' "$cmd" | grep -Eq 'gh[[:space:]]+pr[[:space:]]+merge' \
     && printf '%s' "$cmd" | grep -Eq '(--admin|--administrator)([[:space:]]|=|$)'; then
    { printf '%s' '13: gh pr merge --admin bypasses branch protection (incl. control-plane-ratification) - human-gated. The agent actuates via a NORMAL merge on a recorded authenticated GO (scripts/promotion-verify.sh actuate); the --admin bypass is the solo kill-switch. See docs/operations/runtime-guards.md.'; return 1; }
  fi
  # destructive SQL via a DB client
  if printf '%s' "$cmd" | grep -Eiq '(psql|mysql|mariadb|sqlite3|mongosh?).*(drop[[:space:]]+(table|database)|truncate|delete[[:space:]]+from)'; then
    { printf '%s' '13: destructive SQL (DROP/TRUNCATE/DELETE via a DB client) - human-gated.'; return 1; }
  fi
  # destructive DB resets via migration runners
  if printf '%s' "$cmd" | grep -Eiq '(prisma[[:space:]]+migrate[[:space:]]+reset|prisma[[:space:]]+db[[:space:]]+push[^|]*--force-reset|sequelize[^|]*db:migrate:undo:all|knex[^|]*migrate:rollback[^|]*--all|drizzle-kit[[:space:]]+push)'; then
    { printf '%s' '13: destructive DB reset via a migration runner - human-gated.'; return 1; }
  fi
  # dropdb as an invoked command (start or after a shell separator), not when merely
  # mentioned in prose (e.g. a commit message "fix dropdb bug").
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)dropdb([[:space:]]|$)'; then
    { printf '%s' '13: dropdb destroys a database irreversibly - human-gated.'; return 1; }
  fi
  # ORM / framework DB destruction (drop/reset/wipe/fresh) across stacks
  if printf '%s' "$cmd" | grep -Eiq '(rails|rake)[[:space:]]+db:(drop|reset|migrate:reset|purge)|artisan[[:space:]]+(migrate:fresh|migrate:reset|db:wipe)|manage\.py[[:space:]]+(flush|reset_db|sqlflush)|alembic[[:space:]]+downgrade[[:space:]]+base|flyway[[:space:]]+clean|dotnet[[:space:]]+ef[[:space:]]+database[[:space:]]+(drop|update[[:space:]]+0)'; then
    { printf '%s' '13: destructive DB drop/reset via an ORM/framework tool - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'pg_restore[^|]*(--clean|[[:space:]]-c([[:space:]]|$))'; then
    { printf '%s' '13: pg_restore --clean drops objects irreversibly - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eiq 'redis-cli[^|]*(flushall|flushdb)'; then
    { printf '%s' '13: redis FLUSHALL/FLUSHDB wipes the datastore - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'kubectl[[:space:]]+([^|]*[[:space:]])?delete([[:space:]]|$)'; then
    { printf '%s' '13: kubectl delete removes cluster resources - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'docker[[:space:]]+(volume[[:space:]]+(rm|prune)|system[[:space:]]+prune[^|]*(-a|--all))'; then
    { printf '%s' '13: docker volume/system prune destroys persistent state - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'aws[[:space:]]+s3[[:space:]]+rm[^|]*--recursive|aws[[:space:]]+s3[[:space:]]+rb|aws[[:space:]]+rds[[:space:]]+delete-db-instance|aws[[:space:]]+dynamodb[[:space:]]+delete-table|gcloud[[:space:]]+sql[[:space:]]+instances[[:space:]]+delete|az[[:space:]]+group[[:space:]]+delete|az[[:space:]]+sql[^|]*[[:space:]]delete'; then
    { printf '%s' '13: cloud resource deletion (storage/DB/instance) is irreversible - human-gated.'; return 1; }
  fi
  # 9b: cloud/infra destruction as capability families (verb-agnostic across vendors)
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)terraform[[:space:]]+(destroy|apply)([[:space:]]|$)'; then
    { printf '%s' '13: terraform destroy/apply changes real infrastructure - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eiq '(^[[:space:]]*|[;&|][[:space:]]*)(aws|gcloud|az)[[:space:]][^|]*[[:space:]](delete|delete-[a-z-]+|terminate-[a-z-]+|remove|rb|destroy)([[:space:]]|$)'; then
    { printf '%s' '13: cloud resource deletion/termination is irreversible - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)helm[[:space:]]+(uninstall|delete)([[:space:]]|$)' \
     || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)kubectl[[:space:]]+(drain|cordon)([[:space:]]|$)'; then
    { printf '%s' '13: helm uninstall / kubectl drain disrupts running workloads - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eiq '(mongosh?|cockroach|psql|mysql)[^|]*(dropDatabase|drop[[:space:]]+database)' \
     || printf '%s' "$cmd" | grep -Eiq '(^[[:space:]]*|[;&|][[:space:]]*)(liquibase[[:space:]]+dropAll|flyway[[:space:]]+undo)'; then
    { printf '%s' '13: database drop via a client/migration tool is irreversible - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(curl|wget|base64[[:space:]]+(-d|--decode)|xxd[[:space:]]+-r)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh|dash|python[0-9.]*|node|perl|ruby|php)([[:space:]]|$)'; then
    { printf '%s' '13: piping a fetched/decoded payload into a shell is high-blast-radius - human-gated.'; return 1; }
  fi
  # 9b: data-exfiltration channels (PARTIAL — binary-name denial only; interpreters
  # (python -c, node -e) remain channels. The real control is the platform network-egress
  # allowlist — see docs/enterprise/platform-safety-boundary.md. This is a speed bump.)
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?(scp|sftp)[[:space:]]' \
     || printf '%s' "$cmd" | grep -Eq '(curl|wget)[[:space:]][^|]*(-T[[:space:]]|--upload-file|-F[[:space:]]*[^[:space:]&|;]*@|--data-binary[[:space:]]*@|--post-file)' \
     || printf '%s' "$cmd" | grep -Eq '\|[[:space:]]*(nc|ncat|netcat)[[:space:]]+[^[:space:]]' \
     || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)rclone[[:space:]]+(copy|sync|move)[[:space:]][^|]*[a-zA-Z0-9_-]+:' \
     || printf '%s' "$cmd" | grep -Eq '\|[[:space:]]*mail[[:space:]]'; then
    { printf '%s' '13: possible data exfiltration (scp/sftp/curl-upload/nc/rclone/mail). Partial guard - the boundary is the platform egress allowlist - human-gated.'; return 1; }
  fi
  # 9b: eval of a command substitution hides the real command from inspection.
  # Anchored to command position so "eval $(...)" inside a commit message is NOT matched.
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?eval[[:space:]]+[^;&|]*(\$\(|`)'; then
    { printf '%s' '13: eval of a command substitution obscures the executed command - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eiq '(vercel[[:space:]]+(deploy[[:space:]]+)?--prod|railway[[:space:]]+up|fly[[:space:]]+deploy|terraform[[:space:]]+apply|kubectl[[:space:]]+apply|helm[[:space:]]+(install|upgrade))'; then
    { printf '%s' '13: production deploy / infra apply is high-blast-radius - human-gated.'; return 1; }
  fi
  # prod-context catch-all: a mutating kube/helm op against a production context or namespace.
  # Patterns are intentionally `.`-prefixed (not leading `--`) so GNU grep does not parse them
  # as options; the leading `.` matches the space that always precedes the flag in real commands.
  if printf '%s' "$cmd" | grep -Eiq '.(-(kube-)?context[[:space:]=][^[:space:]]*prod)|[[:space:]]-n[[:space:]]+[^[:space:]]*prod' \
     && printf '%s' "$cmd" | grep -Eiq '(kubectl|helm)[[:space:]]([^|]*[[:space:]])?(apply|delete|create|replace|patch|scale|rollout|upgrade|install|uninstall|destroy)'; then
    { printf '%s' '13: mutating operation against a production context - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)([A-Z_]*ENV)=prod[a-z]*[[:space:]]' \
     && printf '%s' "$cmd" | grep -Eiq '(migrate|deploy|apply|reset|drop|delete|destroy|publish|flush|truncate|prune)'; then
    { printf '%s' '13: destructive/deploy command in a production environment - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eiq '.(--(env|environment)[[:space:]=]prod)' \
     && printf '%s' "$cmd" | grep -Eiq '(migrate|deploy|apply|reset|drop|delete|destroy|publish|flush|truncate|prune)'; then
    { printf '%s' '13: destructive/deploy command targeting production - human-gated.'; return 1; }
  fi
  return 0
}

# guard_check_mcp "<tool>" "<allowlist>" "<overrides>": ALLOW (return 0) / DENY (return 1 + reason).
# Pure: the adapter loads the policy and passes it in (the core never reads a file).
#   <tool>      a Claude MCP tool name, mcp__<server>__<action> (action = segment after the last __)
#   <allowlist> newline list of exact mcp__server__action OR mcp__server__* wildcards (explicit permit)
#   <overrides> newline list of "mcp__server__action=class" (reclassify; class 'read'/'data.read' => allow)
# Decision: allowlist > override-class > tokenized action-verb heuristic > fail-closed deny.
#   The heuristic tokenizes the action (camelCase->snake, lowercased): the first token must be a
#   read verb to allow, and ANY destructive verb token downgrades to deny (so get_and_delete /
#   fetchAndExport deny; list_deployments / get_updates stay read - the noun is not the verb).
# secret.read (A8 family 6) is deny-by-default by NAME: an action naming secret material, or a
# known secret-store server on a read, is denied even when a read verb leads.
# Honest ceiling: classifies by what the NAME reveals; a renamed action (get_data that exfiltrates),
# a secret read via a generic-named server/action (mcp__storage__read_blob), a server wildcard that
# admits a destructive tool, and real egress are NOT caught here — the platform egress allowlist +
# the 11c sandbox are the real controls (docs/enterprise/platform-safety-boundary.md).
guard_check_mcp() {
  t=$1; al=$2; ov=$3
  # 1. explicit allowlist: exact tool, or its server wildcard (mcp__server__*)
  if printf '%s\n' "$al" | grep -qxF -- "$t" 2>/dev/null; then return 0; fi
  if printf '%s\n' "$al" | grep -qxF -- "${t%__*}__*" 2>/dev/null; then return 0; fi
  # 2. class: a per-tool override wins; else heuristic on the action segment.
  act=${t##*__}
  _rest=${t#mcp__}; srv=$(printf '%s' "${_rest%%__*}" | tr 'A-Z' 'a-z')  # server segment, lowercased
  cls=$(printf '%s\n' "$ov" | while IFS='=' read -r k v; do [ "$k" = "$t" ] && { printf '%s' "$v"; break; }; done || true)
  if [ -z "$cls" ]; then
    # Tokenize the action: split camelCase to snake, lowercase, turn _/- into spaces.
    # Whole-token verb matching keeps legit compounds read (list_deployments, get_updates -
    # 'deployments'/'updates' are not the verbs 'deploy'/'update') while downgrading a read-
    # prefixed action that carries a destructive verb token (get_and_delete, fetchAndExport).
    rverbs=' read get list search query fetch describe show view find count '
    dverbs=' delete drop destroy remove truncate reset write update create insert upsert patch put set upload publish deploy send post email notify apply merge push revoke rotate export download '
    norm=$(printf '%s' "$act" | sed 's/\([a-zA-Z0-9]\)\([A-Z]\)/\1_\2/g' | tr 'A-Z_-' 'a-z  ')
    first=${norm%% *}
    cls=unknown
    case "$rverbs" in *" $first "*) cls=read ;; esac
    for tok in $norm; do
      case "$dverbs" in *" $tok "*) cls=destructive; break ;; esac
    done
    # secret-material READ is deny-by-default even when a read verb leads (A8 family 6 - the read
    # half of exfil). Catch it by NAME: (a) the action names secret material, or (b) the server is
    # a known secret store on a read. Ceiling: a secret read via a generic-named server/action
    # (e.g. mcp__storage__read_blob holding a secret) is NOT caught - that is the 11c sandbox's job.
    if [ "$cls" = "read" ] && printf '%s' "$act" | grep -Eiq 'secret|credential|passphrase|password|api[_-]?key|private[_-]?key|access[_-]?key|secret[_-]?key|auth[_-]?token|access[_-]?token'; then
      cls=secret.read
    fi
    if [ "$cls" = "read" ] && printf '%s' "$srv" | grep -Eiq 'vault|1password|onepassword|secretsmanager|secrets[_-]?manager|secret[_-]?manager|keyvault|key[_-]?vault|credstash|doppler|infisical|akeyless'; then
      cls=secret.read
    fi
  fi
  case "$cls" in
    read|data.read) return 0 ;;
    secret.read) printf '13: MCP tool %s reads secret/credential material - deny-by-default (the read half of exfil; A8 family 6). Allowlist it in .claude/mcp-policy.json if intended.' "$t"; return 1 ;;
    unknown) printf '13: MCP tool %s is not classifiable as read-only - denied (fail-closed). Allowlist it in .claude/mcp-policy.json if safe.' "$t"; return 1 ;;
    *) printf '13: MCP tool %s is a destructive/egress capability (%s) - human-gated. Allowlist it in .claude/mcp-policy.json if intended.' "$t" "$cls"; return 1 ;;
  esac
}

# guard_check_path "<path>": print reason + return 1 if denied, else 0.
# Moved from the PRE-SPLIT guard.sh (drop the jq line — caller passes the path); the line range that
# stood here died with the split, so this cites the file and the change, not a dead offset.
guard_check_path() {
  fp=$1
  # CP-8c: an adapter that can prove the protected repo root passes it as $2. When the target is a
  # dev clone (guard_dev_clone_relaxable), the CONTROL-PLANE denies below relax — the secret-write
  # deny does NOT. No root passed (kit-guard CLI, older adapters) => _cp8c_relax=0 => today's
  # behavior (fail-safe).
  _cp8c_root=${2:-}
  _cp8c_relax=0
  _cp8c_hint=''
  if [ -n "$_cp8c_root" ] && guard_dev_clone_relaxable "$fp" "$_cp8c_root"; then _cp8c_relax=1; fi
  # BYTE-TWIN of _cp8b_norm's sed (GUARD-CP-WRITE-ROUTES K-COUPLE) — the /./ FIXPOINT edit is applied
  # here identically; a byte-identity selftest leg pins the two seds equal so they cannot drift.
  fpn=$(printf '%s' "$fp" | sed -e 's#//*#/#g' -e ':b' -e 's#/\./#/#' -e 'tb' -e 's#^\./##' -e 's#/*$##' -e ':a' -e 's#[^/]*/\.\./##' -e 'ta')
  base=$(basename "$fp" 2>/dev/null || printf '%s' "$fp")
  # GUARD-PATH-ALIAS-BYPASS (P0): judge the UNION — literal OR normalised OR RESOLVED. The rc is
  # CAPTURED, never discarded via `is_control_plane_path "$(_resolve_physical ...)"`: that form drops
  # the rc, `is_control_plane_path ""` answers ordinary, and every resolution failure becomes a
  # silent ALLOW. Any failure to resolve is itself a denial (design ceiling 9a).
  _res=''; _resok=0
  _res=$(_resolve_physical "$fp") && _resok=1 || _resok=0
  _rbase=''; [ "$_resok" = 1 ] && _rbase=$(basename "$_res" 2>/dev/null || printf '%s' "$_res")
  if ! selfedit_allowed && [ "$_cp8c_relax" = 0 ] && [ "$_resok" = 0 ]; then
    printf '13: path (%s) could not be resolved - refusing to write to a target that cannot be identified.' "$fp"; return 1
  fi
  if ! selfedit_allowed && [ "$_cp8c_relax" = 0 ] && { is_control_plane_path "$fp" || is_control_plane_path "$fpn"; }; then
    # A dev-clone addressed through a symlink from OUTSIDE temp gets the real remedy, not the kill
    # switch. Naming KIT_GUARD_SELFEDIT here would tell an operator to disarm the guard globally to
    # do work the guard is happy to allow by its real path — the endorsed-bypass class.
    if [ "${_cp8c_hint:-}" = symlinked-clone ]; then
      printf '%s' '13: this dev-clone was addressed through a symlink from outside the temp root, so the clone affordance does not apply (control-plane integrity). Address it by its real path — `cd <clone> && pwd -P` — and the same edit is allowed.'; return 1
    fi
    printf '%s' '13: modifying the guard / its config / CI gates is denied (control-plane integrity). Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'; return 1
  fi
  if ! selfedit_allowed && [ "$_cp8c_relax" = 0 ] && [ "$_resok" = 1 ] && is_control_plane_path "$_res"; then
    printf '13: this path resolves to a control-plane file (%s) - denied (control-plane integrity). The name it is reached by does not change what it writes.' "$_res"; return 1
  fi
  # GUARD-CP-HARDLINK-ALIAS (§2b): the CP-INODE disjunct, immediately after the resolved-CP arm and
  # UNDER THE SAME dev-clone relax gate that arm carries (Leg G). A non-empty name => a genuine CP
  # hardlink; empty => the engine's fail-safe (M1: a DISTINCT reason, true for an ordinary file).
  if ! selfedit_allowed && [ "$_cp8c_relax" = 0 ] && [ "$_resok" = 1 ]; then
    if _hlnamed=$(_hardlink_alias_hit_cp "$_res" "$_cp8c_root"); then
      if [ -n "$_hlnamed" ]; then
        printf '13: this path is a hardlink to a control-plane file (%s) - denied (control-plane integrity). The name it is reached by does not change what it writes.' "$_hlnamed"
      else
        printf '13: could not verify the target'\''s hardlink aliases (stat/find unavailable, timed out, or an ambiguous root) - denied fail-safe (control-plane integrity). Remedy: usually an unreadable directory under the repo root, or a find that exceeded its time budget - make that directory searchable, or raise KIT_HL_FIND_BUDGET (seconds); see docs/operations/runtime-guards.md, section Hardlink aliases.'
      fi
      return 1
    fi
  fi
  # WS1: validate by basename when the NORMALIZED path has no real parent directory — either it is a
  # bare name, OR it still ESCAPES its root (a leading/unresolved `..` the fixpoint could not consume),
  # which cannot be trusted by directory. A path with a genuine parent dir (`.vscode/settings.json`) is
  # matched precisely by is_control_plane_path above, so the net is skipped only there. This closes the
  # `./settings.json`, `a/../guard.sh`, multi-`..`, trailing-slash, AND leading-`../name` bypasses while
  # still allowing an innocent `.vscode/settings.json` / `app/config/settings.json`.
  if ! selfedit_allowed && [ "$_cp8c_relax" = 0 ]; then
    _bare=1
    case "$fpn" in
      ..|../*|*/../*) _bare=1 ;;
      */*)           _bare=0 ;;
    esac
    if [ "$_bare" = 1 ]; then
      # A2 (case) — the FIFTH matcher. This bare/escaping-name net exists precisely for the relative
      # paths that is_control_plane_path's directory-anchored patterns cannot see, and it was still
      # byte-literal: measured, `guard-core.sh` DENIED while `Guard-Core.sh` was ALLOWED, and likewise
      # `Settings.json`, `MCP-Policy.json`, `../Guard-Core.sh`. Reachable via any harness or
      # `scripts/kit-guard` that passes a bare or escaping name. Fold once, then match a LOWERCASE list.
      _bn=$base
      case "$_bn" in *[A-Z]*) _bn=$(printf '%s' "$_bn" | LC_ALL=C tr 'A-Z' 'a-z') ;; esac
      case "$_bn" in
        guard.sh|guard-core.sh|kit-guard|pre-push|settings.json|settings.local.json|mcp-policy.json|codeowners|.meta-control-last|meta-control-log.md|\
        .gitleaks.toml|.gitleaksignore|.semgrepignore|.trivyignore|.checkov.yaml|.checkov.yml)
          printf '13: modifying a control-plane file (%s) is denied (control-plane integrity). Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.' "$base"; return 1 ;;
      esac
    fi
  fi
  # GUARD-CP-HARDLINK-ALIAS (§2b): the secret-INODE disjunct goes BEFORE the template allowlist (vet
  # HIGH-1) and is UNGATED — not relax-gated, not selfedit-gated — byte-parity with the direct secret
  # arms below (a relax-gated secret check would be strictly weaker than the direct arm it mirrors). A
  # genuine single-link `.env.example` produces no hit and falls through to the allowlist unchanged; a
  # hardlinked `.env.example`->`.env` produces a secret hit and denies before the allowlist greens it.
  # (UNGATED: the guard below carries NO _cp8c_relax — K(iv) pins that asymmetry vs the CP site above.)
  if [ "$_resok" = 1 ]; then
    if _hlnamed=$(_hardlink_alias_hit_secret "$_res" "$_cp8c_root"); then
      if [ -n "$_hlnamed" ]; then
        printf '13: this path is a hardlink to secret material (%s) - human-gated. The name it is reached by does not change what it writes.' "$_hlnamed"
      else
        printf '13: could not verify the target'\''s hardlink aliases (stat/find unavailable, timed out, or an ambiguous root) - denied fail-safe (refusing to write to a target whose aliases cannot be confirmed). Remedy: usually an unreadable directory under the repo root, or a find that exceeded its time budget - make that directory searchable, or raise KIT_HL_FIND_BUDGET (seconds); see docs/operations/runtime-guards.md, section Hardlink aliases.'
      fi
      return 1
    fi
  fi
  # The template allowlist is the SECOND predicate that turns denies off, so it takes the
  # CONJUNCTION: allow only when the literal AND the resolved basenames are both template names.
  # Literal-only is a cloak (an alias NAMED .env.example reaching a real .env); resolved-only is a
  # new fail-open (the common `.env -> .env.example` symlink would flip DENY to ALLOW).
  case "$base" in
    .env.example|.env.sample|.env.template|.env.dist)
      case "$_rbase" in
        .env.example|.env.sample|.env.template|.env.dist) return 0 ;;
      esac ;;
  esac
  # GUARD-CP-HARDLINK-ALIAS §2c: the byte-literal + case-folded secret arms are consolidated into
  # _is_secret_path (one source of truth, byte-identity-coupled). The template ALLOW above stays
  # byte-literal, so a case-variant `.ENV.EXAMPLE` falls through to THIS deny — an accepted over-deny.
  if _is_secret_path "$fp"; then
    printf '13: writing secret material (%s) - human-gated (use .env.example + a secrets manager).' "$base"; return 1
  fi
  # …and the same union on the RESOLVED path (both arms, via the same helper), so a benign name cannot
  # front a secret target.
  if [ "$_resok" = 1 ] && _is_secret_path "$_res"; then
    printf '13: this path resolves to secret material (%s) - human-gated. The name it is reached by does not change what it writes.' "$_res"; return 1
  fi
  return 0
}

# guard_check_push <remote-ref> <local-sha> <remote-sha>: print reason + return 1 if denied.
# Ref-based (more precise than the command-string git rules): real non-fast-forward detection.
guard_check_push() {
  remote_ref=$1; local_sha=$2; remote_sha=$3
  zero=0000000000000000000000000000000000000000
  case "$remote_ref" in
    refs/heads/main|refs/heads/master)
      if [ "$local_sha" = "$zero" ]; then
        printf '%s' '13: deleting main/master is destructive and bypasses review - human-gated.'; return 1
      fi
      printf '%s' '13: pushing directly to main/master bypasses review - open a PR (human-gated).'; return 1 ;;
  esac
  # force-push / non-fast-forward to ANY branch: remote tip not an ancestor of the new tip.
  if [ "$remote_sha" != "$zero" ] && [ "$local_sha" != "$zero" ]; then
    if ! git merge-base --is-ancestor "$remote_sha" "$local_sha" 2>/dev/null; then
      printf '%s' '13: non-fast-forward (force) push rewrites published history - human-gated.'; return 1
    fi
  fi
  return 0
}

# shellcheck shell=sh
# =============================================================================
# guard-core.additions.sh (Slice B) — the EXACT snippet apply.py appends to
# .claude/hooks/guard-core.sh (after guard_check_push, before EOF). Not a
# standalone script: a function fragment sourced with the rest of the core.
# =============================================================================

# guard_check_skill "<skill_name>": the roster-authority dial (Slice B, opt-in, ships OFF).
# Prints a verdict TOKEN on line 1 (allow|ask|deny) and, for ask/deny, a reason on line 2+;
# ALWAYS returns 0 — the adapter (guard.sh) maps the token to a permission decision.
#
# Dial source: KIT_ROSTER_GUARD (per-session override) wins; else MODE= in .kit/roster.conf
# (repo-root-relative; path overridable via KIT_ROSTER_CONF for tests, mirroring
# RUNAWAY_BUDGET_CONFIG). The config file is itself control-plane, so an agent cannot flip the
# dial (see is_control_plane_path + the command/redirect matchers).
#
# FAIL-SAFE toward OFF (the load-bearing invariant): any unreadable/absent/garbage config, or a
# MODE that is not exactly ask|deny, routes to `allow`. A config error must NEVER wedge the
# session — the roster-authority FLOOR contract (CLAUDE.md/AGENTS.md) still steers by preference.
#
# Namespace match resists spoofing: the namespace is the part before the FIRST ':' (no colon =>
# the whole string), trimmed and lowercased, then whole-token matched against BLOCKLIST. So
# `Superpowers:x` (capitalized) and bare `superpowers` are BOTH caught, while `x::superpowers`
# (namespace `x`) and any non-blocklisted namespace (figma/vercel/LSPs) are allowed.
guard_check_skill() {
  _sk=$1
  _conf="${KIT_ROSTER_CONF:-.kit/roster.conf}"

  # 1. mode: session override wins; else MODE= from config; else empty (=> off). Unreadable => off.
  _mode="${KIT_ROSTER_GUARD:-}"
  if [ -z "$_mode" ] && [ -r "$_conf" ]; then
    _mode=$(grep -E '^[[:space:]]*MODE[[:space:]]*=' "$_conf" 2>/dev/null | tail -n1 \
      | sed -E 's/^[[:space:]]*MODE[[:space:]]*=[[:space:]]*//; s/#.*$//; s/["'"'"']//g; s/[[:space:]].*$//')
  fi
  _mode=$(printf '%s' "$_mode" | tr 'A-Z' 'a-z')
  # 2. fail-safe: only ask|deny are active; off / empty / garbage => allow.
  case "$_mode" in
    ask|deny) : ;;
    *) printf 'allow\n'; return 0 ;;
  esac

  # 3. namespace = part before the first ':'; trim ws; lowercase (spoof-resistant).
  _ns=${_sk%%:*}
  _ns=$(printf '%s' "$_ns" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | tr 'A-Z' 'a-z')
  [ -n "$_ns" ] || { printf 'allow\n'; return 0; }

  # 4. blocklist (fail-safe empty if unreadable): whole-token membership, never substring.
  _bl=''
  if [ -r "$_conf" ]; then
    _bl=$(grep -E '^[[:space:]]*BLOCKLIST[[:space:]]*=' "$_conf" 2>/dev/null | tail -n1 \
      | sed -E 's/^[[:space:]]*BLOCKLIST[[:space:]]*=[[:space:]]*//; s/#.*$//; s/["'"'"']//g' | tr 'A-Z' 'a-z')
  fi
  case " $_bl " in
    *" $_ns "*) : ;;
    *) printf 'allow\n'; return 0 ;;
  esac

  # 5. blocklisted namespace under an active mode => emit the mode + a MODE-APPROPRIATE reason.
  #    ask: the user is prompted and just approves to proceed (a soft nudge, not a block).
  #    deny: hard-blocked; the only escape is the per-session KIT_ROSTER_GUARD=off override.
  printf '%s\n' "$_mode"
  if [ "$_mode" = ask ]; then
    printf 'kit prefers its own roster (skills/; see skills/using-skills/SKILL.md for the foreign->kit equivalent). Approve this prompt to use `%s` anyway.\n' "$_sk"
  else
    printf 'kit prefers its own roster (skills/; see skills/using-skills/SKILL.md for the foreign->kit equivalent). To use `%s` anyway, set KIT_ROSTER_GUARD=off for this session.\n' "$_sk"
  fi
  return 0
}

# kit_dial_mode "<DIAL_NAME>": the ENFORCEMENT-DIAL reader (DIAL-DELIVERY Δ-A, ruling D-240811-2.1).
# Prints exactly `enforce` or `observe` on stdout and ALWAYS returns 0 — the consumer (today
# hooks/pre-push's two legs) compares the printed word, so a dial can never wedge a push by erroring.
#
# SOURCE: $ROOT/.kit/dials.conf — the REPO-ROOT path, never cwd-relative, so a linked worktree and a
# fixture tree each read their own state (and the kit's own conf can never leak into a fixture, which
# is what keeps hooks/pre-push's dial-leg selftests observe-by-default). $ROOT is the pre-push hook's
# own derivation when set; otherwise it is derived here. PARSE, DON'T SOURCE — guard_check_skill's
# proven idiom above (:1541-1556): a conf file must never become executable code reachable from a gate.
#
# FAIL-SAFE toward OBSERVE (the load-bearing invariant, matching the roster dial's fail-safe-to-off):
# an absent/unreadable/garbage file, a missing key, a value that is not exactly `enforce`, or a dial
# NAME outside [A-Z0-9_] all print `observe`. A dial that cannot be read must never refuse a push.
#
# PRECEDENCE IS ASYMMETRIC, and that asymmetry is the mechanism, not a nicety (owner-lens finding 1):
#   * the conf value is AUTHORITATIVE;
#   * an env var of the same name may ESCALATE observe -> enforce (a per-session tightening);
#   * an env var may NOT de-escalate a conf `enforce`. It LOSES, and one loud anomaly line is printed
#     (the SEC M1 shape at hooks/pre-push:224-236). Env-wins would leave every flip one silent,
#     sticky `export` from undone — a bypass CHEAPER than --no-verify, which at least announces
#     itself per command, and the exact "remember to export" asymmetry the ruling was written to kill.
# An UNSET/empty env var is the normal case and is never an anomaly.
kit_dial_mode() {
  _kdm_name=$1
  # A dial name is a shell identifier by construction; anything else would reach the indirection
  # below, so reject it here and fail safe (this function is never a place to evaluate input).
  case "$_kdm_name" in
    ''|*[!A-Z0-9_]*) printf 'observe\n'; return 0 ;;
  esac
  _kdm_root="${ROOT:-}"
  [ -n "$_kdm_root" ] || _kdm_root=$(git rev-parse --show-toplevel 2>/dev/null) || _kdm_root=""
  [ -n "$_kdm_root" ] || _kdm_root=.
  _kdm_conf="$_kdm_root/.kit/dials.conf"
  _kdm_val=''
  if [ -r "$_kdm_conf" ]; then
    _kdm_val=$(grep -E "^[[:space:]]*${_kdm_name}[[:space:]]*=" "$_kdm_conf" 2>/dev/null | tail -n1 \
      | sed -E "s/^[[:space:]]*${_kdm_name}[[:space:]]*=[[:space:]]*//; s/#.*$//; s/[\"']//g; s/[[:space:]].*$//")
  fi
  # The env side, read INDIRECTLY (POSIX sh has no ${!name}); the name is charset-checked above.
  _kdm_env=$(eval "printf '%s' \"\${$_kdm_name:-}\"")
  if [ "$_kdm_val" = enforce ]; then
    if [ -n "$_kdm_env" ] && [ "$_kdm_env" != enforce ]; then
      # SANITIZE BEFORE INTERPOLATING (review round 1). The value is caller-controlled: a newline in
      # it would FORGE an extra instruction line on stderr — the same injection class hooks/pre-push
      # hardens `refuse_no_core` against (:17-26, where a crafted path could inject `--no-verify`
      # into a refusal). Strip CR/LF and bound the length; the diagnostic value is the first few
      # bytes, not an unbounded echo of whatever was exported.
      _kdm_safe=$(printf '%s' "$_kdm_env" | tr -d '\n\r' | cut -c1-40)
      # ONE LINE PER DIAL PER PROCESS, not per call (review round 1): decl_check_ref and go_relay each
      # consult the dial per ref-line, so a 3-ref push printed the identical anomaly 3x — the same
      # line-discipline defect go_relay's own ONE-RELAY-PER-INVOCATION rule exists to prevent. Keyed
      # per NAME so DECL and GO each still get their own warning. ⚠️ CEILING, measured (review round
      # 1): this memo binds only WITHIN ONE PROCESS. A caller that consults the dial inside a command
      # substitution runs each call in a SUBSHELL, so the assignment below cannot propagate back —
      # measured 3 anomaly lines on a 3-ref-line push both before and after this memo alone. The
      # suppression that actually binds is therefore the CALLER's: hooks/pre-push's `_kit_dial`
      # resolves each dial at most once per push invocation (3 -> 1, re-measured). This memo is kept
      # because it is correct for any in-process consumer and costs nothing; it is NOT the control.
      case " ${_kdm_warned:-} " in
        *" $_kdm_name "*) : ;;
        *)
          printf '%s\n' "kit dial: $_kdm_name='$_kdm_safe' in the environment cannot de-escalate the repo-carried enforce in .kit/dials.conf - the conf WINS (env may only escalate observe->enforce). Change the dial through the ratified control-plane ceremony; a one-off bypass is git push --no-verify, which at least announces itself." >&2
          _kdm_warned="${_kdm_warned:-} $_kdm_name" ;;
      esac
    fi
    printf 'enforce\n'; return 0
  fi
  [ "$_kdm_env" = enforce ] && { printf 'enforce\n'; return 0; }
  printf 'observe\n'; return 0
}
