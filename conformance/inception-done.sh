#!/bin/sh
# inception-done.sh — verify the Inception-Done gate (START-HERE.md / DEVELOPMENT-PROCESS.md §3)
# in a project directory. Usage: sh conformance/inception-done.sh [dir]   (default: .)
#          sh conformance/inception-done.sh --selftest   (mutation-proven fixture matrix; T3)
# NOTE: the gate is expected to FAIL at the kit root (the kit is the template source, not an
# instantiated project). It passes only in a project that has completed Inception. The --selftest
# mode is INDEPENDENT of that: it builds its own throwaway project fixtures (git clone/init) and
# asserts the gate's SPECIFIC leg/guard-line verdicts (repo live · hook live · harness-aware guard
# line) — never the whole-gate "OK" verdict, which would pull in the `export-ignore`d ADR/BACKLOG and
# couple the selftest to the tree it runs in. So it passes at the kit root, on an export tree, and for
# a fresh adopter (before their ADR/BACKLOG exist), and is wired as a control check.
# A green Inception-Done must mean the ENFORCEMENT SURFACE is PRESENT — not that a config
# file mentions it. So we assert a real git repo (T2.1) and an installed pre-push hook floor
# leg (T2.2), and the runtime-guard line is harness-aware (T2.3), driven by each adapter's
# OWN adapters/<h>/adapter.json .dimensions.command-guard.level — never a hardcoded harness list.
#
# Brownfield-foreign-hook rule (T2.2): .git/hooks/pre-push present + executable + carrying the
#   kit marker => PASS; absent, or the kit's marker but not executable => FAIL; present but NOT
#   the kit's (no marker) => PASS-with-note (a pre-existing hook incept declined to overwrite —
#   the "NOT overwriting" brownfield-safe case; we don't punish it).
# Multi-harness rule (T2.3): each declared harness is classified by its adapter.json level. A
#   native adapter runs its declared command-guard check — on PASS we print the PreToolUse leg
#   labelled with that harness; a native adapter whose check FAILs is a FAIL. A floor adapter
#   NEVER prints the PreToolUse leg — it prints the floor message; the floor legs (repo+hook+CI)
#   are asserted globally regardless. Missing adapter.json / jq absent / unreadable level => FAIL
#   (fail-closed — never a silent PASS).
set -eu

# ── run_gate [dir] : the Inception-Done gate. All FAIL paths accumulate into `fail`; a non-zero
#    `fail` yields a non-zero return. These accumulators are the mutation surface non-vacuity.sh
#    neuters — every one is caught by a negative fixture in selftest() below.
run_gate() {
DIR="${1:-.}"
cd "$DIR"
fail=0
is_repo=0
HARNESSES=''

need() { if [ -e "$1" ]; then echo "PASS present: $1"; else echo "FAIL missing: $1"; fail=1; fi; }

need ENGINEERING-PRINCIPLES.md
need CLAUDE.md
need RUNBOOK.md
need .env.example
need .claude

# CI pipeline — platform-aware: accept the GitHub OR GitLab path (incept writes one per --ci),
# so a GitLab adopter doesn't dead-end at this gate (it hard-required the GitHub path before).
if [ -f .github/workflows/ci.yml ] || [ -f .gitlab-ci.yml ]; then
  echo "PASS present: CI pipeline (.github/workflows/ci.yml or .gitlab-ci.yml)"
else
  echo "FAIL missing: a CI pipeline (.github/workflows/ci.yml or .gitlab-ci.yml)"; fail=1
fi

# T2.1 (F2) — a real git repo must exist. The runtime guard's floor leg is installed into
# .git/hooks; without a repo there is nothing to enforce. This alone fails the adopter walk.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "PASS: git repository present (.git)"
  is_repo=1
else
  echo "FAIL: not a git repository — run 'git init' (Inception installs the runtime guard into .git/hooks)"; fail=1
fi

# T2.2 (F2) — the pre-push git-hook FLOOR leg must be actually installed, not merely provided.
# Marker 'KIT_GUARD_CORE' is a stable, guard-specific token in hooks/pre-push (its core-source
# path var); a foreign hook won't carry it. See the brownfield-foreign-hook rule in the header.
if [ "$is_repo" -eq 1 ]; then
  HOOK=.git/hooks/pre-push
  if [ ! -f "$HOOK" ]; then
    echo "FAIL: pre-push git hook missing ($HOOK) — re-run incept (it installs the runtime guard into .git/hooks)"; fail=1
  elif grep -q 'KIT_GUARD_CORE' "$HOOK" 2>/dev/null; then
    if [ -x "$HOOK" ]; then
      echo "PASS present: pre-push git hook installed and executable (kit runtime guard)"
    else
      echo "FAIL: pre-push git hook present but not executable ($HOOK) — re-run incept, or: chmod +x $HOOK"; fail=1
    fi
  else
    echo "PASS (note): pre-push git hook present but not the kit's (foreign hook preserved — brownfield 'NOT overwriting' case); kit guard is not managing it"
  fi
else
  echo "SKIP: pre-push git-hook check — not a git repository (see the repo failure above)"
fi

if ls docs/architecture/ADR-000*.md >/dev/null 2>&1; then
  echo "PASS present: docs/architecture/ADR-000*.md"
else
  echo "FAIL missing: docs/architecture/ADR-000*.md"; fail=1
fi

if [ -f BACKLOG.md ] || grep -q "Backlog backend" CLAUDE.md 2>/dev/null; then
  echo "PASS present: backlog (BACKLOG.md or declared backend)"
else
  echo "FAIL missing: BACKLOG.md or a declared backlog backend"; fail=1
fi

# project CLAUDE.md key header fields must be filled (no leftover placeholders)
if grep -Eq '\*\*Project:\*\* \[name\]|\*\*Intent owner:\*\* \[who owns' CLAUDE.md 2>/dev/null; then
  echo "FAIL: project CLAUDE.md key fields not filled (Project / Intent owner)"; fail=1
else
  echo "PASS: project CLAUDE.md key header fields filled"
fi

# the Target harness(es) field must be stamped AND every selected adapter must conform to the
# boundary contract — the Inception-Done enforcement of the harness floor (brownfield-critical:
# an adopter's merged repo can't pass Inception until its declared adapter(s) actually conform).
hline=$(grep -E '^\- \*\*Target harness\(es\)\*\*' CLAUDE.md 2>/dev/null || true)
if [ -z "$hline" ]; then
  echo "FAIL: project CLAUDE.md missing the Target harness(es) field"; fail=1
else
  # value after the '(§harness-neutrality): ' marker, first whitespace token (the comma-list)
  hval=$(printf '%s' "$hline" | sed 's/^.*(§harness-neutrality): *//' | cut -d' ' -f1)
  case "$hval" in
    *'['*|'') echo "FAIL: Target harness(es) not stamped (placeholder remains)"; fail=1 ;;
    *)
      for _h in $(printf '%s' "$hval" | tr ',' ' '); do
        _h=$(printf '%s' "$_h" | sed 's/[[:punct:][:space:]]*$//')  # G13: tolerate a trailing period/space in the stamped value
        [ -z "$_h" ] && continue
        HARNESSES="$HARNESSES $_h"  # T2.3: resolved list feeds the harness-aware runtime-guard leg below
        if ! [ -d "adapters/$_h" ]; then
          echo "FAIL: harness adapter '$_h' directory not found — expected: adapters/$_h"; fail=1
        elif sh conformance/harness-adapter.sh "adapters/$_h" >/dev/null 2>&1; then
          echo "PASS: harness adapter '$_h' conforms to the boundary contract"
        else
          echo "FAIL: harness adapter '$_h' does not conform — run: sh conformance/harness-adapter.sh adapters/$_h"; fail=1
        fi
      done ;;
  esac
fi

# T2.3 (F3) — harness-aware runtime-guard leg. Classify EACH declared harness by its OWN
# adapters/<h>/adapter.json .dimensions.command-guard.level (never a hardcoded name list), so
# the gate's claim and the incept notice's honesty cannot diverge. See the multi-harness rule
# in the header. Fail-closed: no harness resolved / jq absent / json missing / level unreadable.
if [ -z "$HARNESSES" ]; then
  echo "FAIL: runtime-guard leg — no target harness resolved, cannot classify command-guard (fail-closed)"; fail=1
elif ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: runtime-guard leg UNVERIFIED — jq absent, cannot read adapters/<h>/adapter.json command-guard level (fail-closed)"; fail=1
else
  for _h in $HARNESSES; do
    _aj="adapters/$_h/adapter.json"
    if [ ! -f "$_aj" ]; then
      echo "FAIL: runtime-guard leg — $_aj missing, cannot classify '$_h' command-guard (fail-closed)"; fail=1; continue
    fi
    _lvl=$(jq -r '.dimensions."command-guard".level // empty' "$_aj" 2>/dev/null || true)
    case "$_lvl" in
      native)
        _chk=$(jq -r '.dimensions."command-guard".proof.check // empty' "$_aj" 2>/dev/null || true)
        [ -n "$_chk" ] || _chk="conformance/guard-wired.sh"
        if [ ! -f "$_chk" ]; then
          echo "FAIL: '$_h' declares command-guard=native but its check '$_chk' is missing (fail-closed)"; fail=1
        else
          # three-state, mirroring guard-wired: 0 wired · 2 UNVERIFIED (jq) · 1 dark — fail-closed on 1/2.
          if sh "$_chk" . >/dev/null 2>&1; then gw=0; else gw=$?; fi
          if [ "$gw" -eq 0 ]; then
            echo "PASS: '$_h' runtime guard wired (PreToolUse → guard.sh, matcher admits mutating tools) [native, via $_chk]"
          elif [ "$gw" -eq 2 ]; then
            echo "FAIL: '$_h' runtime guard wiring UNVERIFIED — install jq (the guard hook needs it too), then: sh $_chk"; fail=1
          else
            echo "FAIL: '$_h' runtime guard not wired — run: sh $_chk"; fail=1
          fi
        fi ;;
      floor)
        echo "PASS: runtime guard = floor (git hook + CI backstop); '$_h' has no inline command-guard (by design — adapter declares command-guard=floor)" ;;
      *)
        echo "FAIL: '$_h' command-guard level unreadable ('${_lvl:-<empty>}') in $_aj (fail-closed)"; fail=1 ;;
    esac
  done
fi

# ── Branch-protection leg (K5). MODE strict (default) | surface. GitHub -> live verify via
#    branch-protection.sh --raw (we apply our OWN policy, never its CI-collapsed exit). Non-GitHub
#    -> a recorded CLAUDE.md attestation. No remote -> outstanding/fatal per mode. exit 1
#    (verified-unprotected) is fatal in BOTH modes; unverifiable is fatal only in strict.
MODE="${MODE:-strict}"
if [ "$is_repo" -ne 1 ]; then
  echo "SKIP: branch-protection leg — not a git repository (see the repo failure above)"
else
  _remote=$(git remote get-url origin 2>/dev/null || true)
  if [ -z "$_remote" ]; then
    if [ "$MODE" = surface ]; then
      echo "OUTSTANDING: branch protection — no remote configured yet; protect main on the remote before entering the loop"
    else
      echo "FAIL: branch protection — no remote configured; main cannot be protected (not loop-ready). Add a protected remote, or run --surface for the local-surface check"; fail=1
    fi
  else
    case "$_remote" in
      *github.com*)
        if sh conformance/branch-protection.sh --raw >/dev/null 2>&1; then _bp=0; else _bp=$?; fi
        case "$_bp" in
          0) echo "PASS: verified protected (main, GitHub)" ;;
          1) echo "FAIL: branch protection — main is NOT protected on GitHub (required PR reviews / status checks missing)"; fail=1 ;;
          2) if [ "$MODE" = surface ]; then
               echo "OUTSTANDING: branch protection — GitHub state unverifiable (no gh / unauthenticated); re-run authenticated or in CI"
             else
               echo "FAIL: branch protection — GitHub state unverifiable (no gh / unauthenticated) and verification is required (strict); authenticate gh, or run --surface"; fail=1
             fi ;;
          *) echo "FAIL: branch protection — branch-protection.sh returned an unexpected status ($_bp); fail-closed"; fail=1 ;;
        esac ;;
      *)
        _bpl=$(grep -E '^\- \*\*Branch protection\*\*' CLAUDE.md 2>/dev/null | head -1 || true)
        _bpv=$(printf '%s' "$_bpl" | sed 's/^.*(§branch-protection): *//')
        # A real attestation is "attested:<...>" with NO residual template placeholder markers
        # (< > [ ]); an adopter who leaves the angle-bracket placeholder is NOT attested (fail-closed,
        # same discipline as the Target harness placeholder guard above).
        _attested=0
        case "$_bpv" in attested:*) _attested=1 ;; esac
        case "$_bpv" in *'<'*|*'>'*|*'['*|*']'*) _attested=0 ;; esac
        if [ "$_attested" = 1 ]; then
          echo "PASS: branch protection attested (non-GitHub host) [${_bpv}]"
        elif [ "$MODE" = surface ]; then
          echo "OUTSTANDING: branch protection — non-GitHub remote, no valid attestation recorded (stamp '- **Branch protection** (§branch-protection): attested: HOST and MECHANISM' in CLAUDE.md, no angle brackets; docs/adoption/vc-hosts.md)"
        else
          echo "FAIL: branch protection — non-GitHub remote and no valid recorded attestation (stamp '- **Branch protection** (§branch-protection): attested: HOST and MECHANISM' in CLAUDE.md, no angle brackets, or run --surface); docs/adoption/vc-hosts.md"; fail=1
        fi ;;
    esac
  fi
fi

if [ "$fail" -ne 0 ]; then echo "FAIL: Inception-Done gate not satisfied in '$DIR'"; return 1; fi
echo "OK: Inception-Done gate satisfied in '$DIR'"
return 0
}

# ─────────────────────────────────────────────────────────────────────────────────────────────
# selftest() is the non-vacuity ORACLE MARKER: non-vacuity.sh mutates only lines strictly ABOVE
# this definition (the run_gate accumulators), then runs this --selftest; a neutered FAIL path that
# no fixture below catches is a VACUOUS check. So every FAIL verdict run_gate can print has a
# negative fixture here that asserts BOTH the SPECIFIC message AND the gate-not-satisfied return —
# an echo survives mutation, only the accumulator+return do not, so message-plus-return is the tooth.
# Fixtures are built with git clone (NEVER adopter-export — a kit-self surface would go N/A on an
# export tree). The st_* helpers and the st_fail accumulator live BELOW this marker so the mutation
# harness cannot neuter the test's own bookkeeping. Keep no literal <var>=1 token in any comment
# above this line (it would be a phantom accumulator to the lexer-less mutator).
selftest() {
  set +e   # the harness asserts explicitly; a fixture's non-zero return must not abort the sweep
  st_fail=0
  ROOT=$(unset CDPATH; cd "$(dirname "$0")/.." && pwd)
  WORK=$(mktemp -d)
  # Build the once-cloned fixture template. seed_fixture_template (below the oracle marker with the
  # st_* helpers) decides clone-vs-worktree-seed; its header documents the three cases (CP-5 + K9).
  if ! seed_fixture_template "$ROOT" "$WORK/tmpl"; then
    return 1
  fi

  # (a) tree with NO .git -> FAIL "not a git repository"
  echo "--- (a) no .git repository ---"
  d=$(st_mkfix a claude-code); st_install_hook "$d"; rm -rf "$d/.git"
  st_run "$d"
  st_has "FAIL: not a git repository"
  st_has "FAIL: Inception-Done gate not satisfied"
  st_rc 1

  # (b) repo but NO pre-push hook -> FAIL "pre-push git hook missing"
  echo "--- (b) repo, no pre-push hook ---"
  d=$(st_mkfix b claude-code); rm -f "$d/.git/hooks/pre-push"
  st_run "$d"
  st_has "PASS: git repository present"
  st_has "FAIL: pre-push git hook missing"
  st_has "FAIL: Inception-Done gate not satisfied"
  st_rc 1

  # (c) --harness generic (floor): repo leg live, hook leg live, floor guard-line, NO PreToolUse.
  # We assert the SPECIFIC legs T3 locks, NOT the whole-gate "OK: gate satisfied" verdict — that
  # verdict ALSO requires docs/architecture/ADR-000*.md + BACKLOG.md, both `export-ignore`d
  # (.gitattributes), so asserting it would couple the selftest to the tree it runs in: it would
  # FAIL on an export tree and for any real adopter who runs verify.sh BEFORE creating their
  # ADR/BACKLOG. A selftest must build its OWN world — these three legs print regardless of those.
  echo "--- (c) generic (floor) ---"
  d=$(st_mkfix c generic); st_install_hook "$d"
  st_run "$d" surface
  st_has "PASS: git repository present"
  st_has "PASS present: pre-push git hook installed and executable"
  st_has "runtime guard = floor (git hook + CI backstop); 'generic' has no inline command-guard"
  st_hasnt "PreToolUse"

  # (d) --harness claude-code (native): repo leg live, hook leg live, harness-aware PreToolUse leg.
  # Same rationale as (c): assert the native guard leg (harness-aware PreToolUse), NOT the whole-gate
  # verdict — so the fixture is independent of the export-ignored ADR/BACKLOG.
  echo "--- (d) claude-code (native) ---"
  d=$(st_mkfix d claude-code); st_install_hook "$d"
  st_run "$d" surface
  st_has "PASS: git repository present"
  st_has "PASS present: pre-push git hook installed and executable"
  st_has "'claude-code' runtime guard wired (PreToolUse"

  # (e) adapter.json missing -> fail-closed FAIL
  echo "--- (e) adapter.json missing ---"
  d=$(st_mkfix e claude-code); st_install_hook "$d"; rm -f "$d/adapters/claude-code/adapter.json"
  st_run "$d"
  st_has "adapters/claude-code/adapter.json missing, cannot classify 'claude-code'"
  st_has "FAIL: Inception-Done gate not satisfied"
  st_rc 1

  # (e2) adapter.json invalid (level unreadable) -> fail-closed FAIL
  echo "--- (e2) adapter.json invalid ---"
  d=$(st_mkfix e2 claude-code); st_install_hook "$d"; printf 'not json{' > "$d/adapters/claude-code/adapter.json"
  st_run "$d"
  st_has "command-guard level unreadable"
  st_has "FAIL: Inception-Done gate not satisfied"
  st_rc 1

  # (f) brownfield foreign pre-push (no kit marker) -> PASS-with-note, not a hook FAIL.
  # Assert the foreign-hook leg (repo live + "foreign hook preserved" note + no hook FAIL), NOT the
  # whole-gate verdict — export/ADR/BACKLOG-independent, same rationale as (c)/(d).
  echo "--- (f) foreign pre-push hook (brownfield) ---"
  d=$(st_mkfix f claude-code); printf '#!/bin/sh\necho foreign\nexit 0\n' > "$d/.git/hooks/pre-push"; chmod +x "$d/.git/hooks/pre-push"
  st_run "$d" surface
  st_has "PASS: git repository present"
  st_has "foreign hook preserved"
  st_hasnt "FAIL: pre-push git hook"

  # (g) K9 — pre-incept HEAD: a commit EXISTS but HEAD does NOT track hooks/pre-push (it predates
  # inception). The broken clone fast-path would copy that INCOMPLETE tree and the resulting template
  # would silently LACK hooks/pre-push. seed_fixture_template must gate the clone on HEAD tracking
  # hooks/pre-push and fall back to the worktree-seed, so the template DOES contain hooks/pre-push.
  # This drives seed_fixture_template directly (the fixture-BUILD layer), which the (a)-(f) cases,
  # keyed off the already-built $WORK/tmpl, cannot reach.
  echo "--- (g) K9 pre-incept HEAD (worktree-seed fallback) ---"
  PRE="$WORK/g-pre"; PRETMPL="$WORK/g-tmpl"   # PRETMPL must NOT pre-exist (clone fast-path needs it absent)
  mkdir -p "$PRE/hooks"
  printf '#!/bin/sh\n# KIT_GUARD_CORE\n' > "$PRE/hooks/pre-push"   # incepted worktree marker, UNTRACKED
  printf 'spec\n' > "$PRE/SPEC.md"
  git -C "$PRE" init -q
  git -C "$PRE" add SPEC.md   # commit ONLY the spec-only file => a genuine pre-incept HEAD
  git -C "$PRE" -c user.email=selftest@kit -c user.name=selftest commit -qm "pre-incept spec-only" >/dev/null 2>&1
  if seed_fixture_template "$PRE" "$PRETMPL" >/dev/null 2>&1 && [ -f "$PRETMPL/hooks/pre-push" ]; then
    printf '    ok  : pre-incept-HEAD seed contains hooks/pre-push (worktree-seed, not the broken clone)\n'
  else
    printf '    BAD : pre-incept-HEAD seed LACKS hooks/pre-push (clone copied an incomplete HEAD — K9)\n'; st_fail=1
  fi

  # ── Branch-protection leg (K5): every mode×host cell asserts a discriminating MESSAGE, not just rc.
  # (h) GitHub, verified-unprotected (bp exit 1) -> FAIL both modes
  echo "--- (h) github unprotected (bp exit 1) ---"
  d=$(st_mkfix h claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 1
  st_run "$d" strict;  st_has "FAIL: branch protection"; st_has "NOT protected"; st_rc 1
  st_run "$d" surface; st_has "FAIL: branch protection"

  # (h0) GitHub, protected (bp exit 0) -> PASS verified
  echo "--- (h0) github protected (bp exit 0) ---"
  d=$(st_mkfix h0 claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 0
  st_run "$d" strict;  st_has "PASS: verified protected"

  # (h2) GitHub, unverifiable (bp exit 2) -> strict FAIL / surface OUTSTANDING
  echo "--- (h2) github unverifiable (bp exit 2) ---"
  d=$(st_mkfix h2 claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 2
  st_run "$d" strict;  st_has "FAIL: branch protection"; st_has "unverifiable"; st_rc 1
  st_run "$d" surface; st_has "OUTSTANDING: branch protection"; st_hasnt "FAIL: branch protection"

  # (h3) LIVENESS: REAL branch-protection.sh (no stub), forced no-gh -> raw exit 2 -> OUTSTANDING (surface)
  # proves the leg actually invokes the real script with --raw, not only the stub.
  echo "--- (h3) github unverifiable via REAL script (BP_FORCE_NO_GH) ---"
  d=$(st_mkfix h3 claude-code); st_install_hook "$d"; st_gh "$d"
  OUT=$( ( export BP_FORCE_NO_GH=1; MODE=surface run_gate "$d" ) 2>&1 ); RC=$?
  st_has "OUTSTANDING: branch protection"

  # (i) non-GitHub, attested -> PASS attested
  echo "--- (i) non-github attested ---"
  d=$(st_mkfix i claude-code); st_install_hook "$d"; st_nongh "$d"; st_attest "$d"
  st_run "$d" strict;  st_has "PASS: branch protection attested (non-GitHub host)"

  # (i2) non-GitHub, NOT attested -> strict FAIL / surface OUTSTANDING
  echo "--- (i2) non-github unattested ---"
  d=$(st_mkfix i2 claude-code); st_install_hook "$d"; st_nongh "$d"
  st_run "$d" strict;  st_has "FAIL: branch protection"; st_has "no valid recorded attestation"; st_rc 1
  st_run "$d" surface; st_has "OUTSTANDING: branch protection"; st_hasnt "FAIL: branch protection"

  # (i3) non-GitHub, PLACEHOLDER attestation left unfilled -> fail-closed (NOT a valid attestation)
  echo "--- (i3) non-github placeholder attestation ---"
  d=$(st_mkfix i3 claude-code); st_install_hook "$d"; st_nongh "$d"
  printf '%s\n' '- **Branch protection** (§branch-protection): attested: <host + mechanism>' >> "$d/CLAUDE.md"
  st_run "$d" strict;  st_has "FAIL: branch protection"; st_has "no valid recorded attestation"; st_rc 1
  st_run "$d" surface; st_has "OUTSTANDING: branch protection"; st_hasnt "FAIL: branch protection"

  # (j) no remote, strict -> FAIL
  echo "--- (j) no remote, strict ---"
  d=$(st_mkfix j claude-code); st_install_hook "$d"; st_norem "$d"
  st_run "$d" strict;  st_has "FAIL: branch protection"; st_has "no remote configured"; st_rc 1

  # (k) no remote, surface -> OUTSTANDING
  echo "--- (k) no remote, surface ---"
  d=$(st_mkfix k claude-code); st_install_hook "$d"; st_norem "$d"
  st_run "$d" surface; st_has "OUTSTANDING: branch protection"; st_hasnt "FAIL: branch protection"

  # (l) GitHub, unknown bp exit (3) -> fail-closed FAIL
  echo "--- (l) github unknown bp exit -> fail-closed ---"
  d=$(st_mkfix l claude-code); st_install_hook "$d"; st_gh "$d"; st_bpstub "$d" 3
  st_run "$d" strict;  st_has "FAIL: branch protection"; st_rc 1

  rm -rf "$WORK" 2>/dev/null || true
  if [ "$st_fail" = 0 ]; then
    echo "inception-done --selftest: OK"; return 0
  fi
  echo "inception-done --selftest: FAIL" >&2; return 1
}

# ── seed_fixture_template <root> <dest> : build a committed fixture-template repo at <dest> from
#    <root>, so st_mkfix can cheaply re-clone it. Lives BELOW the oracle marker (never mutated). It
#    chooses clone-vs-worktree-seed across THREE cases:
#      1. HEAD tracks hooks/pre-push (the kit repo; the exported tree adopter-export-wired.sh
#         init+add+commits before the aggregate) -> `git clone` copies the committed content. Proven;
#         what CI has always exercised.
#      2. No commit yet (CP-5: a freshly incepted adopter — incept git-inits but does NOT commit) ->
#         `git clone` would copy an EMPTY template, so every fixture assertion silently missed and this
#         selftest reddened inside every adopter tree. Seed from the WORKING TREE instead.
#      3. K9 — a commit EXISTS but is a PRE-INCEPT HEAD that does not reflect the incepted worktree
#         (it lacks hooks/pre-push + adapters/). `git clone` would copy that INCOMPLETE tree, so the
#         fixtures would silently lack hooks/pre-push and assertions would miss. So we gate the clone
#         path on HEAD actually TRACKING hooks/pre-push (`git cat-file -e HEAD:hooks/pre-push` — the
#         incepted-marker probe), NOT merely on HEAD existing, and fall back to the SAME worktree-seed
#         as case 2. The worktree is the truth; the `hooks/pre-push absent` guard below keeps the
#         fallback fail-closed.
#    An earlier revision of the CP-5 fix copied the worktree UNCONDITIONALLY with `tar --exclude='./.git'`.
#    That passed on macOS and FAILED on Linux CI (BSD vs GNU tar disagree on the exclude), breaking
#    adopter-export-wired's selftest. The non-vacuity sweep caught it. The worktree path below uses a
#    portable `find` walk instead — no tar. Do not reintroduce tar here.
seed_fixture_template() {
  _sft_root="$1"; _sft_dest="$2"
  # K9: gate the clone fast-path on HEAD actually TRACKING hooks/pre-push (the incepted-marker probe),
  # NOT merely on HEAD existing. A pre-incept HEAD exists but does not track hooks/pre-push, so `git
  # cat-file -e HEAD:hooks/pre-push` is false and the `&&` falls through to the worktree-seed below.
  if git -C "$_sft_root" rev-parse --verify -q HEAD >/dev/null 2>&1 \
     && git -C "$_sft_root" cat-file -e HEAD:hooks/pre-push 2>/dev/null; then
    if ! git clone -q "$_sft_root" "$_sft_dest" 2>/dev/null; then
      echo "inception-done --selftest: FAIL — cannot clone the kit repo from $_sft_root (fixtures need a real git tree)"
      return 1
    fi
  else
    # Seed the template from the WORKING TREE, then init+commit it so st_mkfix can clone it exactly.
    mkdir -p "$_sft_dest"
    ( cd "$_sft_root" && find . -name .git -prune -o -type f -print ) | while IFS= read -r _f; do
      _rel=${_f#./}
      mkdir -p "$_sft_dest/$(dirname "$_rel")" 2>/dev/null || continue
      cp "$_sft_root/$_rel" "$_sft_dest/$_rel" 2>/dev/null || true
    done
    if [ ! -f "$_sft_dest/hooks/pre-push" ]; then
      echo "inception-done --selftest: FAIL — cannot seed fixtures from $_sft_root (hooks/pre-push absent)"
      return 1
    fi
    if ! git -C "$_sft_dest" init -q \
       || ! git -C "$_sft_dest" add -A \
       || ! git -C "$_sft_dest" -c user.email=selftest@kit -c user.name=selftest commit -qm fixtures; then
      echo "inception-done --selftest: FAIL — cannot seed the fixture template repo"
      return 1
    fi
  fi
}

# ── st_* helpers + the st_fail accumulator: BELOW the oracle marker (never mutated). ────────────
# st_run <dir>: capture run_gate's combined output in OUT and its return in RC (subshelled so its
#   `cd "$DIR"` does not move the selftest's own working directory).
st_run() { OUT=$( ( MODE="${2:-strict}" run_gate "$1" ) 2>&1 ); RC=$?; }
# st_has <substr>: OUT must contain <substr>. st_hasnt: OUT must NOT. st_rc <n>: RC must equal <n>.
st_has()   { case "$OUT" in *"$1"*) printf '    ok  : has [%s]\n' "$1" ;; *) printf '    BAD : MISSING [%s]\n' "$1"; st_fail=1 ;; esac; }
st_hasnt() { case "$OUT" in *"$1"*) printf '    BAD : SHOULD-NOT have [%s]\n' "$1"; st_fail=1 ;; *) printf '    ok  : absent [%s]\n' "$1" ;; esac; }
st_rc()    { if [ "$RC" = "$1" ]; then printf '    ok  : rc %s\n' "$RC"; else printf '    BAD : rc %s (wanted %s)\n' "$RC" "$1"; st_fail=1; fi; }
# st_mkfix <name> <harness>: echo the path to a fresh project fixture that (before perturbation)
#   satisfies every leg — a cheap local re-clone of the once-cloned template, with the four adopter
#   files stamped and CLAUDE.md carrying real (non-placeholder) header fields + the harness value.
st_mkfix() {
  _d="$WORK/$1"
  git clone -q "$WORK/tmpl" "$_d"
  : > "$_d/ENGINEERING-PRINCIPLES.md"; : > "$_d/RUNBOOK.md"; : > "$_d/.env.example"
  {
    echo "# Fixture project"
    echo "**Project:** fixture-project"
    echo "**Intent owner:** the fixture owner"
    echo "- **Target harness(es)** (§harness-neutrality): $2"
  } > "$_d/CLAUDE.md"
  printf '%s' "$_d"
}
st_install_hook() { cp "$1/hooks/pre-push" "$1/.git/hooks/pre-push"; chmod +x "$1/.git/hooks/pre-push"; }
# ── branch-protection leg fixtures (K5). st_gh/st_nongh/st_norem set the origin host; st_bpstub
#    swaps in a branch-protection.sh returning a fixed exit; st_attest stamps a non-GitHub attestation.
st_gh()     { git -C "$1" remote add origin https://github.com/fixture/repo.git 2>/dev/null || git -C "$1" remote set-url origin https://github.com/fixture/repo.git; }
st_nongh()  { git -C "$1" remote add origin https://gitlab.com/fixture/repo.git 2>/dev/null || git -C "$1" remote set-url origin https://gitlab.com/fixture/repo.git; }
st_norem()  { git -C "$1" remote remove origin 2>/dev/null || true; }
# st_bpstub <dir> <exit>: replace branch-protection.sh in the fixture with a stub returning <exit> (for --raw and otherwise)
st_bpstub() { printf '#!/bin/sh\nexit %s\n' "$2" > "$1/conformance/branch-protection.sh"; chmod +x "$1/conformance/branch-protection.sh"; }
# st_attest <dir>: append a non-GitHub attestation using the STABLE (§branch-protection) marker
st_attest() { printf '%s\n' '- **Branch protection** (§branch-protection): attested: gitlab protected-branches' >> "$1/CLAUDE.md"; }

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *)
    MODE=strict; _dir=.
    for a in "$@"; do case "$a" in --surface) MODE=surface ;; --strict) MODE=strict ;; *) _dir="$a" ;; esac; done
    MODE="$MODE" run_gate "$_dir"; exit $? ;;
esac
