#!/bin/sh
# build-output-ignored.sh — conformance gate (CP7R5-K4-IGNORE): build output dropped into the kit's
# REFERENCE TREES (profiles/, conformance/fixtures/) is ignored by a rule that OUTLIVES incept's
# profile prune.
#
# THE DEFECT THIS CLOSES (CP-7 run-5, K4). Every profile's build-output ignore rules live at
# profiles/<stack>/scaffold/.gitignore. `incept` prunes unselected profiles, deleting that file with
# the profile — so the ignore rule is scoped to a SHORTER LIFETIME than the path it protects. Any
# artifact a toolchain drops there afterwards is unignored and a baseline `git add -A` commits it.
# In run 5 that made `verify.sh --require` red on an untouched origin/main and failed AC4.
#
# THE PREDICATE IS ABOUT THE RULE'S SOURCE, NOT MERELY "IS IT IGNORED".
# A naive "is this path ignored?" check is VACUOUS here: in the kit's own repo 15 of 16 probe paths
# ARE ignored today — by per-item files that do not survive. So each probe must resolve to a
# TREE-LEVEL or ROOT ignore file (.gitignore, profiles/.gitignore, conformance/fixtures/.gitignore),
# never to a per-item file INSIDE the tree. Per-item files fail two ways, and the predicate catches
# both: profiles/<stack>/scaffold/.gitignore is DELETED by the prune, and a newly added profile or
# fixture simply has no such file at all. Tree-level coverage is therefore also a family-completeness
# property — a new item arrives covered by construction.
#
# NO FILES ARE CREATED. `git check-ignore` evaluates PATH STRINGS against the ignore rules, so the
# probes are synthetic paths that need not exist. That is deliberate: it makes this check read-only
# with no temp trees and no cleanup trap (conformance disk-safety — leaked mktemp trees have twice
# filled a work machine), while still asserting git's OWN verdict rather than a bespoke regex.
#
#   sh conformance/build-output-ignored.sh            # scan this repo (the real run)
#   sh conformance/build-output-ignored.sh --selftest # mutation-proof it has teeth
# HONEST CEILING: proves git WILL NOT SURFACE these paths, and that the rule outlives the prune. It
# does NOT prevent GENERATION (artifacts still land on disk), does NOT stop `git add -f`, and does
# NOT prove the pattern list is complete for every toolchain — completeness rests on the manifest
# evidence in the design/plan, not on this check.
# What it changes: nothing — read-only; evaluates ignore rules for synthetic paths via git check-ignore.
# Guardrails: read-only; creates no files and no temp trees; no network. Selftest builds throwaway repos under mktemp and removes them.
# Exit: 0 = every probe covered by a surviving rule · 1 = a probe uncovered or covered only by a per-item file · 2 = usage.
# POSIX sh; dash-clean.
set -eu
cd "$(dirname "$0")/.." 2>/dev/null || true

# The ignore files whose rules SURVIVE incept's prune. A rule sourced anywhere else is not durable.
# Kept as an exact-match set (not a prefix glob) so a per-item file can never be mistaken for one:
# "profiles/.gitignore" survives; "profiles/dotnet/scaffold/.gitignore" does not.
SURVIVING='.gitignore profiles/.gitignore conformance/fixtures/.gitignore'

# PROBES — one synthetic path per (reference tree x build-output pattern). The leaf component is
# irrelevant; the pattern component is what is under test. `__probe__` is a directory name that
# exists in no tree, which is the point: the rule must apply by PATTERN, not because some specific
# real directory happens to carry its own ignore file.
#
# The pattern set is evidence-derived (design 4.2 / plan 1.3): the union of the 8 shipped scaffold
# .gitignore files MINUS editor/OS/env noise, PLUS .pytest_cache (profiles/ml/evals/ is real Python
# and ships no scaffold .gitignore — it was uncovered entirely before this gate).
PATTERNS='bin obj publish TestResults target build .gradle __pycache__ .pytest_cache dist coverage node_modules .venv *.egg-info'
# File-shaped (not directory) build outputs — probed as leaf files, not as parent dirs.
FILE_PATTERNS='cover.out coverage.json .coverage'

# probe_tree <repo-dir> <tree> : emit "PATH<TAB>SOURCE" for each probe under <tree>; SOURCE is the
# ignore file git attributes the match to, or the literal string NONE when nothing matches.
probe_tree() {
  _dir=$1; _tree=$2
  for _p in $PATTERNS; do
    _path="$_tree/__probe__/$_p/leaf.txt"
    _src=$( cd "$_dir" && git check-ignore -v "$_path" 2>/dev/null | cut -f1 ) || true
    printf '%s\t%s\n' "$_path" "${_src:-NONE}"
  done
  for _p in $FILE_PATTERNS; do
    _path="$_tree/__probe__/$_p"
    _src=$( cd "$_dir" && git check-ignore -v "$_path" 2>/dev/null | cut -f1 ) || true
    printf '%s\t%s\n' "$_path" "${_src:-NONE}"
  done
}

# is_surviving <source> : 0 when <source> names one of the durable ignore files.
# `git check-ignore -v` field 1 is the TRIPLE "<file>:<line>:<pattern>" — NOT a bare filename — so
# this matches on the "<file>:" PREFIX. Comparing the whole triple for equality silently rejects
# every layout including the correct one (measured: it made the selftest's positive anchor fail).
# Prefix-matching also cannot confuse a per-item file with a tree-level one: the triple
# "profiles/dotnet/scaffold/.gitignore:2:obj/" does not start with "profiles/.gitignore:".
is_surviving() {
  for _s in $SURVIVING; do
    case "$1" in "$_s":*) return 0 ;; esac
  done
  return 1
}

# check_tree <repo-dir> : the LOAD-BEARING assertion. rc0 = every probe in both reference trees
# resolves to a surviving ignore file. rc1 = at least one probe is uncovered (NONE) or is covered
# only by a per-item file that the prune deletes. The _rc accumulator is what --selftest kills:
# neuter it and an uncovered tree passes, which the selftest catches (KILLED).
# Reports EVERY finding, not just the first. A gate that names one failure per run costs the operator
# a diagnostic round trip per pattern — the CP7R5-K3-DIAG complaint, which this check must not repeat.
# The probe output is collected into a variable and fed to `read` via a heredoc so the loop runs in
# the CURRENT shell: a `probe_tree | while` pipeline puts the loop in a SUBSHELL, where the findings
# accumulator would be discarded.
check_tree() {
  _dir=$1
  _rc=0
  _findings=''
  for _tree in profiles conformance/fixtures; do
    _out=$(probe_tree "$_dir" "$_tree")
    while IFS="$(printf '\t')" read -r _path _src; do
      [ -n "$_path" ] || continue
      if [ "$_src" = NONE ]; then
        _findings="${_findings}  NOT IGNORED         $_path
"
        _rc=1
      elif ! is_surviving "$_src"; then
        _findings="${_findings}  NOT DURABLE         $_path
                      covered only by $_src
"
        _rc=1
      fi
    done <<EOF
$_out
EOF
  done
  if [ "$_rc" != 0 ]; then
    echo "FAIL: build output is not durably ignored in the kit's reference trees:" >&2
    printf '%s' "$_findings" >&2
    echo "  NOT IGNORED = nothing covers it; a baseline 'git add -A' commits build output." >&2
    echo "  NOT DURABLE = covered only by a per-item file, which incept's prune deletes with its" >&2
    echo "  profile and which a newly added profile/fixture would not have at all." >&2
    echo "  Fix: put the pattern in a tree-level ignore file — profiles/.gitignore," >&2
    echo "  conformance/fixtures/.gitignore, or the repo-root .gitignore." >&2
  fi
  return $_rc
}

# ---------------------------------------------------------------------------------------------------
# COMPLETENESS LOCK — closes this check's own blind spot.
#
# THE HOLE IT CLOSES. $PATTERNS above is hardcoded IN THIS FILE, so check_tree only ever asserts "the
# patterns I already know about are covered". A pattern missing from BOTH the list and the ignore file
# is invisible to it — the same failure class as K4 itself: coverage correlating with what someone
# remembered rather than with what is actually shipped. Add a profile tomorrow whose toolchain emits
# `.build/` and check_tree stays green while the tree-level file silently lacks it.
#
# WHY THIS IS NOT A TAUTOLOGY. The obvious lock — encode a toolchain->pattern mapping and assert it —
# compares one hand-maintained list against another and proves nothing (the vacuous-anchor class). This
# instead uses an INDEPENDENT source already in the repo: each profile's own scaffold/.gitignore, which
# declares what THAT toolchain produces. Comparing "what each profile declares it emits" against "what
# the tree-level file durably covers" is a comparison between two genuinely different things.
#
# FAIL-CLOSED. Anything a scaffold declares that is not in the excluded set below MUST appear in
# profiles/.gitignore. A newly declared, unrecognised pattern therefore FAILS until a human either
# covers it or excludes it with a reason — it can never silently pass.
#
# EXCLUDED, with reasons (editor/OS/user state is not build output; the repo-root .gitignore owns it):
#   .idea/ *.iml .vscode/ .DS_Store  — editor / OS noise
#   *.user                            — Visual Studio PER-USER project state, not build output
#   .env                              — env-file policy belongs to the repo root, not to a profile
#   app                               — go's compiled binary, declared root-anchored as `/app` in the go
#                                       scaffold. Generalising a bare `app` tree-wide is UNSAFE: on a
#                                       case-insensitive filesystem (macOS default) it would also match
#                                       the TRACKED source directory profiles/dotnet/scaffold/src/App/.
#                                       Anchored-to-one-scaffold patterns do not generalise; the go
#                                       scaffold's own .gitignore keeps covering it while it exists.
EXCLUDED_DECLARATIONS='.idea *.iml .vscode .DS_Store *.user .env app Thumbs.db'

# norm_pattern <raw> : strip a leading and/or trailing '/' so `/target`, `target/` and `target` compare
# equal. Directory-ness and anchoring are irrelevant to the question "is this pattern covered at all".
norm_pattern() { _n=${1#/}; _n=${_n%/}; printf '%s' "$_n"; }

# norm_file <path> : every meaningful pattern in <path>, normalised, one per line. Comments, blanks and
# negations are dropped. Kept as a function so callers can use it inside $( ) — see check_declared_covered.
norm_file() {
  while IFS= read -r _l || [ -n "$_l" ]; do
    case "$_l" in ''|\#*|!*) continue ;; esac
    norm_pattern "$_l"; printf '\n'
  done < "$1"
}

# declared_patterns <repo-dir> : every build-output pattern DECLARED by any shipped profile scaffold,
# normalised, one per line. Comments, blanks and negations (`!/src/`) are skipped — a negation re-includes
# a path and is not an ignore obligation.
declared_patterns() {
  _dir=$1
  for _f in "$_dir"/profiles/*/scaffold/.gitignore "$_dir"/profiles/*/scaffold-cli/.gitignore; do
    [ -f "$_f" ] || continue
    while IFS= read -r _line || [ -n "$_line" ]; do
      case "$_line" in ''|\#*|!*) continue ;; esac
      norm_pattern "$_line"; printf '\n'
    done < "$_f"
  done
}

# check_declared_covered <repo-dir> : rc0 when every declared, non-excluded pattern also appears in
# profiles/.gitignore. rc1 otherwise. The _rc=1 here is what the selftest's "undeclared" leg kills.
check_declared_covered() {
  _dir=$1
  _rc=0
  _miss=''
  [ -f "$_dir/profiles/.gitignore" ] || { echo "FAIL: no profiles/.gitignore to compare against" >&2; return 1; }
  # norm_file is a FUNCTION, not an inline loop, deliberately: a `case` pattern's `)` written directly
  # inside $( ... ) is parsed as the closing paren of the command substitution (POSIX ambiguity — it
  # produced `syntax error near unexpected token ;;` here). A function body is parsed independently.
  _cover=$(norm_file "$_dir/profiles/.gitignore")
  _seen=''
  _decl=$(declared_patterns "$_dir" | sort -u)
  while IFS= read -r _p || [ -n "$_p" ]; do
    [ -n "$_p" ] || continue
    case " $EXCLUDED_DECLARATIONS " in *" $_p "*) continue ;; esac
    case " $_seen " in *" $_p "*) continue ;; esac
    _seen="$_seen $_p"
    printf '%s\n' "$_cover" | grep -qxF "$_p" || { _miss="${_miss}  $_p
"; _rc=1; }
  done <<EOF
$_decl
EOF
  if [ "$_rc" != 0 ]; then
    echo "FAIL: a profile scaffold declares build output that profiles/.gitignore does not cover:" >&2
    printf '%s' "$_miss" >&2
    echo "  Each pattern above appears in some profiles/*/scaffold/.gitignore — the profile's own" >&2
    echo "  statement of what its toolchain emits — but not in the tree-level profiles/.gitignore," >&2
    echo "  so it stops being ignored the moment incept prunes that profile." >&2
    echo "  Fix: add it to profiles/.gitignore, or add it to EXCLUDED_DECLARATIONS WITH A REASON if it" >&2
    echo "  is editor/OS/user state or is unsafe to generalise beyond its own scaffold." >&2
  fi
  return $_rc
}

run() {
  _r=0
  check_tree . || _r=1
  check_declared_covered . || _r=1
  if [ "$_r" = 0 ]; then
    echo "OK: build output in profiles/ and conformance/fixtures/ is ignored by rules that outlive the prune,"
    echo "    and every pattern a profile scaffold declares is covered tree-level"
    return 0
  fi
  return 1
}

# --- selftest (the NON-VACUITY oracle; everything at/after this marker is emitted verbatim by the
#     mutation harness, so its st=1 accumulator can never be neutered). Builds throwaway repos whose
#     ignore layout is (a) correct, (b) missing entirely, (c) present but per-item only, and (d)
#     present but INERT (the pattern commented out) — and asserts check_tree passes only on (a).
#     Leg (c) is the one that matters: it is exactly today's kit layout, and a check that merely
#     asked "is it ignored?" would pass it. Neutering check_tree's _rc=1 flips (b), (c) and (d)
#     GREEN and this selftest goes RED (KILLED). ---
selftest() {
  st=0
  # NOTE: cleanup is PER-LEG below, never accumulated. `mk` is invoked as $(mk ...), so any variable
  # it assigns is set in a SUBSHELL and never reaches this scope — an accumulator here would look
  # correct and silently leak every fixture dir (the conformance disk-safety class).

  # mk <layout> : build a throwaway repo and echo its path. Layouts:
  #   good     — tree-level profiles/.gitignore + conformance/fixtures/.gitignore (the fix)
  #   none     — no ignore files at all
  #   peritem  — per-item ignore files only (today's kit layout: the rule dies with the prune)
  #   inert    — tree-level files present, but every pattern commented out (present-but-no-effect)
  mk() {
    _t=$(mktemp -d) || return 1
    git init -q "$_t"
    mkdir -p "$_t/profiles/__probe__" "$_t/conformance/fixtures/__probe__"
    case "$1" in
      good|inert)
        for _d in "$_t/profiles/.gitignore" "$_t/conformance/fixtures/.gitignore"; do
          : > "$_d"
          for _p in $PATTERNS; do
            [ "$1" = inert ] && printf '#%s/\n' "$_p" >> "$_d" || printf '%s/\n' "$_p" >> "$_d"
          done
          for _p in $FILE_PATTERNS; do
            [ "$1" = inert ] && printf '#%s\n' "$_p" >> "$_d" || printf '%s\n' "$_p" >> "$_d"
          done
        done ;;
      peritem)
        # The rule exists, but only INSIDE the item — precisely what the prune removes.
        for _d in "$_t/profiles/__probe__/.gitignore" "$_t/conformance/fixtures/__probe__/.gitignore"; do
          : > "$_d"
          for _p in $PATTERNS;      do printf '%s/\n' "$_p" >> "$_d"; done
          for _p in $FILE_PATTERNS; do printf '%s\n'  "$_p" >> "$_d"; done
        done ;;
      none) : ;;
    esac
    echo "$_t"
  }

  # Positive anchor — the fixed layout must PASS. Without this the suite could pass by always failing.
  _g=$(mk good)
  if check_tree "$_g" >/dev/null 2>&1; then
    echo "selftest PASS: tree-level ignore files -> covered"
  else
    echo "selftest FAIL: correct tree-level layout wrongly rejected (false positive)"; st=1
  fi
  rm -rf "$_g" 2>/dev/null || true

  # Load-bearing negative A — no ignore rules at all. MUST fail.
  _n=$(mk none)
  if check_tree "$_n" >/dev/null 2>&1; then
    echo "selftest FAIL: absent ignore rules NOT caught (VACUOUS — the check has no teeth)"; st=1
  else
    echo "selftest PASS: absent ignore rules caught"
  fi
  rm -rf "$_n" 2>/dev/null || true

  # Load-bearing negative B — THE ONE THAT MATTERS. Per-item rules only: every probe IS ignored, so a
  # naive "is it ignored?" check passes here. This layout is today's kit, and it is the defect.
  _p1=$(mk peritem)
  if check_tree "$_p1" >/dev/null 2>&1; then
    echo "selftest FAIL: per-item-only rules NOT caught (VACUOUS — this is the K4 defect itself)"; st=1
  else
    echo "selftest PASS: per-item-only rules caught (the rule must outlive the prune)"
  fi
  rm -rf "$_p1" 2>/dev/null || true

  # Load-bearing negative C — present but INERT. Guards the presence-vs-effect trap: a text grep for
  # the block would pass this, because the lines are all there. git's own evaluator does not.
  _i=$(mk inert)
  if check_tree "$_i" >/dev/null 2>&1; then
    echo "selftest FAIL: inert (commented-out) rules NOT caught (presence != effect)"; st=1
  else
    echo "selftest PASS: inert rules caught (presence is not effect)"
  fi
  rm -rf "$_i" 2>/dev/null || true

  # --- completeness-lock legs -----------------------------------------------------------------
  # mkdecl <tree-level-patterns> <scaffold-patterns> : a repo whose tree-level profiles/.gitignore
  # carries <tree-level-patterns> and whose one profile scaffold DECLARES <scaffold-patterns>.
  mkdecl() {
    _t=$(mktemp -d) || return 1
    git init -q "$_t"
    mkdir -p "$_t/profiles/demo/scaffold"
    for _p in $1; do printf '%s/\n' "$_p" >> "$_t/profiles/.gitignore"; done
    for _p in $2; do printf '%s/\n' "$_p" >> "$_t/profiles/demo/scaffold/.gitignore"; done
    echo "$_t"
  }

  # Positive anchor — everything the scaffold declares is covered tree-level. MUST pass.
  _dok=$(mkdecl 'obj bin target' 'obj bin')
  if check_declared_covered "$_dok" >/dev/null 2>&1; then
    echo "selftest PASS: fully-declared coverage accepted"
  else
    echo "selftest FAIL: complete declaration wrongly rejected (false positive)"; st=1
  fi
  rm -rf "$_dok" 2>/dev/null || true

  # Load-bearing negative D — THE POINT OF THIS LOCK. A scaffold declares `.build` (a toolchain the
  # tree-level file has never heard of). check_tree CANNOT see this: `.build` is not in $PATTERNS, so
  # it is never probed. Only the declaration comparison catches it. MUST fail.
  _dbad=$(mkdecl 'obj bin' 'obj bin .build')
  if check_declared_covered "$_dbad" >/dev/null 2>&1; then
    echo "selftest FAIL: undeclared-to-tree pattern NOT caught (the completeness hole is open)"; st=1
  else
    echo "selftest PASS: a scaffold pattern missing from the tree-level file is caught"
  fi
  rm -rf "$_dbad" 2>/dev/null || true

  # INDEPENDENCE CROSS-PROOF — the load-bearing justification for adding this lock at all. Build a repo
  # with FULL tree-level coverage (so check_tree is satisfied) and then have a profile scaffold declare
  # `.build`, a pattern $PATTERNS has never heard of. check_tree MUST pass and check_declared_covered
  # MUST fail on the SAME repo. If both fail, the fixture proves nothing — an earlier version of this
  # leg used a partially-covered repo where check_tree failed too, which is why the assertion is
  # two-sided rather than one.
  _dind=$(mk good)
  mkdir -p "$_dind/profiles/demo/scaffold"
  printf '.build/\n' > "$_dind/profiles/demo/scaffold/.gitignore"
  if check_tree "$_dind" >/dev/null 2>&1; then
    if check_declared_covered "$_dind" >/dev/null 2>&1; then
      echo "selftest FAIL: neither leg caught '.build' — the completeness hole is open"; st=1
    else
      echo "selftest PASS: check_tree GREEN while the lock is RED (independent, not redundant)"
    fi
  else
    echo "selftest FAIL: fixture invalid — check_tree failed, so it cannot show independence"; st=1
  fi
  rm -rf "$_dind" 2>/dev/null || true

  # Load-bearing negative E — an EXCLUDED pattern must not be demanded. Guards against the lock
  # becoming noise that pressures a future author into ignoring editor state tree-wide.
  _dex=$(mkdecl 'obj' 'obj .idea')
  if check_declared_covered "$_dex" >/dev/null 2>&1; then
    echo "selftest PASS: excluded (editor/OS) declarations are not demanded"
  else
    echo "selftest FAIL: an excluded pattern was wrongly demanded"; st=1
  fi
  rm -rf "$_dex" 2>/dev/null || true

  if [ "$st" = 0 ]; then
    echo "OK: build-output-ignored selftest — a correct layout passes; absent, per-item-only and inert"
    echo "    layouts are caught; a scaffold-declared pattern missing tree-level is caught while"
    echo "    check_tree stays green on the same repo (the two locks are independent, not redundant)"
    return 0
  fi
  echo "FAIL: build-output-ignored selftest"
  return 1
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "")         run; exit $? ;;
  *)          echo "usage: build-output-ignored.sh [--selftest]" >&2; exit 2 ;;
esac
