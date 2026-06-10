# Runtime-Guard Portability (Slice 9d-b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the red-teamed deny-matrix from `.claude/hooks/guard.sh` into a sourceable `guard-core.sh` (single source of truth), consumed by a slimmed Claude adapter, a universal git pre-push hook, and a `kit-guard` CLI — so non-Claude runtimes and humans inherit the same destructive-action denials.

**Architecture:** `guard-core.sh` holds the matrix as three pure functions (`guard_check_command`, `guard_check_path`, `guard_check_push`) plus the 9b control-plane helpers; each prints a `"13: …"` reason to stdout and returns 1 on deny, 0 on allow. Three thin adapters source it and translate that contract to their surface (Claude PreToolUse JSON · git-hook exit code · CLI exit code). Correctness is proven by `conformance/agent-autonomy.sh` classifying the existing corpus **identically** before vs after.

**Tech Stack:** POSIX `sh` (dash-clean), `jq` (Claude adapter only), `git` plumbing (`merge-base --is-ancestor`, `rev-parse`), the kit's existing `conformance/*.sh` harness pattern.

---

## Execution constraints (READ FIRST)

Two constraints shape every task:

1. **`.claude/` files are control-plane — the agent cannot write them.** `guard-core.sh` and `guard.sh` live under `.claude/`, which the guard blocks. So those two files are **built and validated in `/tmp`, then applied by Bradley** with `KIT_GUARD_SELFEDIT=1 cp …`. Everything else (`hooks/`, `scripts/`, `conformance/`, `docs/`, `incept.sh`, `VERSION`, `CHANGELOG`, roadmap) is agent-editable. `.github/workflows/ci.yml` is also control-plane → Bradley `cp`.

2. **Never put a dangerous token in a Bash *command string*.** The live guard inspects the command string of every Bash call; a test payload like `rm -rf /` or `.claude/hooks/guard.sh` in your command will block your own call. **Always run adversarial corpora from inside a script file** (`sh some-script.sh`) — the guard does not read file contents or subprocess internals, only the top-level command string. Every `--selftest` in this plan follows that rule.

**Branch:** `feature/slice-9d-b-runtime-guard` (already created off `main`). The spec is committed at `docs/superpowers/specs/2026-06-09-slice9db-runtime-guard-portability-design.md`.

---

## File structure

| File | Responsibility |
|------|----------------|
| `.claude/hooks/guard-core.sh` (new) | The deny-matrix as pure functions + 9b helpers. Single source of truth. **Bradley `cp`.** |
| `.claude/hooks/guard.sh` (rewrite) | Thin Claude PreToolUse adapter: jq-parse → call core → emit decision. **Bradley `cp`.** |
| `hooks/pre-push` (new) | Git hook: parse pushed refs → `guard_check_push` → block + `--no-verify` note. `--selftest`. |
| `scripts/kit-guard` (new) | CLI over the core: `cmd`/`path`/`--selftest`. Portable entry point for other runtimes. |
| `conformance/guard-core-sourced.sh` (new) | Asserts all three consumers source the one core (anti-fork). |
| `conformance/agent-autonomy.sh` (modify) | Add deny cases for the new control-plane files. |
| `scripts/incept.sh` (modify) | Default-on, brownfield-safe pre-push install + next-steps line. |
| `docs/operations/runtime-guards.md` (new) | One matrix, three surfaces; runtime wiring; honesty note. |
| `docs/enterprise/platform-safety-boundary.md` (modify) | Cross-link runtime-guards. |
| `conformance/README.md` (modify) | Index row for `guard-core-sourced.sh`; note the new selftests. |
| `.github/workflows/ci.yml` (modify) | Wire the three new selftests. **Bradley `cp`.** |
| `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md` (modify) | 2.29.0; 9d-b → shipped. |

---

## Task 1: Extract `guard-core.sh` + slim `guard.sh` (behavior-identical)

**Files:**
- Create: `/tmp/guard-core.sh` → applied to `.claude/hooks/guard-core.sh`
- Rewrite: `/tmp/guard.sh` → applied to `.claude/hooks/guard.sh`
- Test: `/tmp/aa-candidate.sh` (a copy of `conformance/agent-autonomy.sh` pointed at `/tmp/guard.sh`)

- [ ] **Step 1: Capture the behavior baseline (current guard).**

Run: `sh conformance/agent-autonomy.sh > /tmp/aa-baseline.txt; echo "exit=$?"`
Expected: last line `OK: agent-autonomy …`, `exit=0`. `/tmp/aa-baseline.txt` now holds the canonical PASS/FAIL line for every case.

- [ ] **Step 2: Write `/tmp/guard-core.sh`** — the pure core. Header + helpers + three functions. The helpers `selfedit_allowed` and `is_control_plane_path` are moved verbatim from `guard.sh:43-51`, **with the new control-plane files added** to the case list.

```sh
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
is_control_plane_path() {
  case "$1" in
    *.claude/hooks/guard.sh|*.claude/hooks/guard-core.sh|\
    *.claude/settings.json|*.claude/settings.local.json|\
    */hooks/pre-push|hooks/pre-push|*/scripts/kit-guard|scripts/kit-guard|\
    */.github/workflows/*|.github/workflows/*|*/CODEOWNERS|CODEOWNERS|*/.git/*|.git/*)
      return 0 ;;
  esac
  return 1
}

# guard_check_command "<cmd>": print reason + return 1 if denied, else return 0.
guard_check_command() {
  cmd=$1
  # --- control-plane shell mutation (moved from guard.sh:81-93, + new files) ---
  if ! selfedit_allowed && printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+config[[:space:]]+([^;&|]*[[:space:]])?core\.hooksPath'; then
    printf '%s' '13: git config core.hooksPath would disable the agent guard - human-gated. Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'; return 1
  fi
  if ! selfedit_allowed && printf '%s' "$cmd" | grep -Eq '(\.claude(/|[[:space:]]|$)|\.github/workflows|/CODEOWNERS|(^|[^a-zA-Z.])CODEOWNERS|\.git(/|[[:space:]]|$)|hooks/pre-push|scripts/kit-guard)'; then
    if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])(rm|rmdir|mv|cp|truncate|shred|chmod|chown|dd|sed|tee|ln|install|patch)[[:space:]]' \
       || printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])git[[:space:]]+(checkout|restore)([[:space:]]|$)' \
       || printf '%s' "$cmd" | grep -Eq '>[[:space:]]*[^[:space:]]*(\.claude|\.github/workflows|CODEOWNERS|\.git|hooks/pre-push|scripts/kit-guard)'; then
      printf '%s' '13: mutating the guard / its config / CI gates via shell is denied (control-plane integrity). Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'; return 1
    fi
  fi
  # --- destructive matrix: moved VERBATIM from guard.sh:96-242 ---
  # Transformation rule applied to EACH rule in that range:
  #   emit_deny "MESSAGE"   becomes   { printf '%s' 'MESSAGE'; return 1; }
  # (keep every grep -Eq pattern byte-for-byte identical; only the emit changes.)
  # <PASTE-AND-TRANSFORM guard.sh:96-242 HERE>
  return 0
}

# guard_check_path "<path>": print reason + return 1 if denied, else 0.
# Moved from guard.sh:245-265 (drop the jq line — caller passes the path).
guard_check_path() {
  fp=$1
  fpn=$(printf '%s' "$fp" | sed -e 's#//*#/#g' -e 's#/\./#/#g')
  base=$(basename "$fp" 2>/dev/null || printf '%s' "$fp")
  if ! selfedit_allowed && { is_control_plane_path "$fp" || is_control_plane_path "$fpn"; }; then
    printf '%s' '13: modifying the guard / its config / CI gates is denied (control-plane integrity). Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'; return 1
  fi
  if ! selfedit_allowed; then
    case "$base" in
      guard.sh|guard-core.sh|kit-guard|pre-push|settings.json|settings.local.json|CODEOWNERS)
        printf '13: modifying a control-plane file (%s) is denied (control-plane integrity). Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.' "$base"; return 1 ;;
    esac
  fi
  [ "$base" = ".env.example" ] && return 0
  case "$fp" in
    *.env|*/.env|*.env.local|*.env.production|*.env.development|*.pem|*.key|*id_rsa*|*/secrets/*|*/secret/*)
      printf '13: writing secret material (%s) - human-gated (use .env.example + a secrets manager).' "$base"; return 1 ;;
  esac
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
```

> **Doing the paste-and-transform (Step 2 core region):** open `.claude/hooks/guard.sh`, take lines 96–242 (everything from the recursive-rm rule through the last prod-target rule, i.e. the body of the `Bash)` case up to but NOT including `allow ;;`), paste into the marked region, and replace each `emit_deny "X"` with `{ printf '%s' 'X'; return 1; }`. Do not alter any `grep -Eq` pattern. The control-plane block at the top of `guard_check_command` already replaces `guard.sh:81-93` (do not paste those again).

- [ ] **Step 3: Write `/tmp/guard.sh`** — the thin adapter.

```sh
#!/bin/sh
# guard.sh — Claude Code PreToolUse adapter over guard-core.sh (the deny-matrix).
# Intentionally THIN: parse the Claude tool-call JSON, call the shared core, emit a
# Claude permission decision. ALL deny logic lives in guard-core.sh (single source of
# truth), reused by hooks/pre-push and scripts/kit-guard. Requires jq; jq-absent or
# non-JSON input denies mutating tools (fail closed). See docs/operations/runtime-guards.md.
set -eu

. "$(dirname "$0")/guard-core.sh"

INPUT=$(cat)

emit_deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}
allow() { exit 0; }

tool_name_grep() {
  printf '%s' "$INPUT" | tr -d '\n' | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}
deny_if_mutating() {
  case "$1" in
    Bash|Write|Edit|NotebookEdit)
      emit_deny "agent-guard: $2 (DEVELOPMENT-PROCESS.md 13). Mutating tools are denied until resolved." ;;
    *) allow ;;
  esac
}

if ! command -v jq >/dev/null 2>&1; then
  deny_if_mutating "$(tool_name_grep)" "jq is required to evaluate tool safety; install jq"
fi
if ! TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null); then
  emit_deny "agent-guard: tool input is not valid JSON — cannot verify safety; denying (DEVELOPMENT-PROCESS.md 13)."
fi

case "$TOOL" in
  Bash)
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || printf '')
    if reason=$(guard_check_command "$CMD"); then allow; else emit_deny "$reason"; fi ;;
  Write|Edit|NotebookEdit)
    FP=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || printf '')
    if reason=$(guard_check_path "$FP"); then allow; else emit_deny "$reason"; fi ;;
  *)
    allow ;;
esac
```

- [ ] **Step 4: dash-syntax-check both candidates.**

Run: `dash -n /tmp/guard-core.sh && dash -n /tmp/guard.sh && echo "syntax OK"`
Expected: `syntax OK`. Fix any error before proceeding.

- [ ] **Step 5: Build the candidate harness and prove behavior-identical.**

**Guard-safety note:** do NOT build the candidate harness with a `sed`/`cp` command that names a `.claude/…` path — the live guard blocks a mutation verb next to a control-plane path. Instead: copy the harness (the `cp` source is under `conformance/`, not control-plane), then change the one `GUARD=` line with the **Edit tool** (which checks only the `/tmp` target path, not its content).

Run: `cp conformance/agent-autonomy.sh /tmp/aa-candidate.sh`
Then use the **Edit tool** on `/tmp/aa-candidate.sh` to replace the line `GUARD=".claude/hooks/guard.sh"` with `GUARD="/tmp/guard.sh"`.
Then run:
```sh
sh /tmp/aa-candidate.sh > /tmp/aa-candidate.txt; echo "exit=$?"
diff /tmp/aa-baseline.txt /tmp/aa-candidate.txt && echo "IDENTICAL — behavior preserved"
```
Expected: `exit=0`, then `IDENTICAL — behavior preserved` with **no diff output**. A non-empty diff means the extraction changed behavior — fix `/tmp/guard-core.sh` until the diff is empty. (`/tmp/guard.sh` sources `/tmp/guard-core.sh` via `dirname "$0"`, so both being in `/tmp` makes the candidate self-contained.)

- [ ] **Step 6: Hand the two files to Bradley to apply (control-plane `cp`).**

Tell Bradley to run, from the repo root:
```bash
KIT_GUARD_SELFEDIT=1 cp /tmp/guard-core.sh .claude/hooks/guard-core.sh
KIT_GUARD_SELFEDIT=1 cp /tmp/guard.sh      .claude/hooks/guard.sh
chmod +x .claude/hooks/guard-core.sh .claude/hooks/guard.sh
git add .claude/hooks/guard-core.sh .claude/hooks/guard.sh && git log --oneline -1
```
(He commits, or you commit after he applies — `git add` of an already-changed control-plane file is not a guard-blocked mutation. Prefer Bradley commits for a clean human-ratified control-plane change.)

- [ ] **Step 7: Verify the deployed refactor matches the baseline.**

Run: `sh conformance/agent-autonomy.sh > /tmp/aa-deployed.txt; echo "exit=$?"; diff /tmp/aa-baseline.txt /tmp/aa-deployed.txt && echo "DEPLOYED == BASELINE"`
Expected: `exit=0`, `DEPLOYED == BASELINE`, no diff.

- [ ] **Step 8: Add regression cases for the new control-plane files** to `conformance/agent-autonomy.sh`. Insert after line 196 (`assert_deny "install over guard" …`):

```sh
# --- 9d-b: new control-plane files (guard-core / kit-guard / pre-push) (must DENY) ---
assert_deny "Write guard-core"     '{"tool_name":"Write","tool_input":{"file_path":".claude/hooks/guard-core.sh","content":"x"}}'
assert_deny "Edit kit-guard"       '{"tool_name":"Edit","tool_input":{"file_path":"scripts/kit-guard","old_string":"a","new_string":"b"}}'
assert_deny "Write pre-push"       '{"tool_name":"Write","tool_input":{"file_path":"hooks/pre-push","content":"x"}}'
assert_deny "sed -i guard-core"    '{"tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ .claude/hooks/guard-core.sh"}}'
assert_deny "rm kit-guard"         '{"tool_name":"Bash","tool_input":{"command":"rm scripts/kit-guard"}}'
# --- 9d-b: must still ALLOW (no new over-block) ---
assert_allow "read guard-core"     '{"tool_name":"Read","tool_input":{"file_path":".claude/hooks/guard-core.sh"}}'
assert_allow "run kit-guard sh"    '{"tool_name":"Bash","tool_input":{"command":"sh scripts/kit-guard --selftest"}}'
```

- [ ] **Step 9: Run the extended harness; confirm all pass.**

Run: `sh conformance/agent-autonomy.sh; echo "exit=$?"`
Expected: every line `PASS …`, final `OK: …`, `exit=0`. (The new `assert_allow "run kit-guard sh"` will pass even before Task 2 exists, because the guard ALLOWS that command; it asserts non-over-block, not that kit-guard runs.)

- [ ] **Step 10: Commit.**

```bash
git add conformance/agent-autonomy.sh
git commit -m "feat(guard): 9d-b — extract deny-matrix into sourceable guard-core.sh

guard.sh becomes a thin Claude PreToolUse adapter over guard-core.sh (single
source of truth); guard_check_command/guard_check_path moved verbatim, plus a
new ref-based guard_check_push. Behavior proven identical via agent-autonomy.sh;
new control-plane files (guard-core/kit-guard/pre-push) added to the deny set."
```
(The `.claude/` files were applied by Bradley in Step 6; this commit captures the harness additions. If Bradley already committed the `.claude/` files separately, this is a second commit — fine.)

---

## Task 2: `scripts/kit-guard` CLI

**Files:**
- Create: `scripts/kit-guard`

- [ ] **Step 1: Write `scripts/kit-guard`.**

```sh
#!/bin/sh
# kit-guard — portable CLI over the runtime-agnostic deny-matrix (guard-core.sh).
# The entry point any non-Claude runtime pipes a proposed action through:
#   kit-guard cmd "<command>"   -> exit 0 allow · exit 1 deny (reason on stderr)
#   kit-guard path "<file>"     -> exit 0 allow · exit 1 deny (reason on stderr)
#   kit-guard --selftest        -> run the deny battery through the CLI
#   kit-guard --help
# A SPEED BUMP, not a boundary (docs/enterprise/platform-safety-boundary.md).
# Resolve the core relative to this script, or via KIT_GUARD_CORE override.
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CORE="${KIT_GUARD_CORE:-$SELF_DIR/../.claude/hooks/guard-core.sh}"
[ -f "$CORE" ] || { echo "kit-guard: guard-core.sh not found ($CORE); set KIT_GUARD_CORE" >&2; exit 2; }
. "$CORE"

usage() { sed -n '2,9p' "$0"; }

cmd=${1:-}
case "$cmd" in
  cmd)
    [ $# -ge 2 ] || { echo "usage: kit-guard cmd \"<command>\"" >&2; exit 2; }
    if reason=$(guard_check_command "$2"); then exit 0; else echo "$reason" >&2; exit 1; fi ;;
  path)
    [ $# -ge 2 ] || { echo "usage: kit-guard path \"<file>\"" >&2; exit 2; }
    if reason=$(guard_check_path "$2"); then exit 0; else echo "$reason" >&2; exit 1; fi ;;
  --help|-h) usage; exit 0 ;;
  --selftest) ;;  # fall through to the selftest block below
  *) echo "kit-guard: unknown command '${cmd:-}' (cmd|path|--selftest|--help)" >&2; exit 2 ;;
esac

# --- selftest: the adversarial corpus IS the test (runs the core through the CLI) ---
fail=0
deny()  { if sh "$0" cmd "$2" >/dev/null 2>&1; then echo "FAIL (wanted deny):  $1"; fail=1; else echo "PASS deny:  $1"; fi; }
allow() { if sh "$0" cmd "$2" >/dev/null 2>&1; then echo "PASS allow: $1"; else echo "FAIL (wanted allow): $1"; fail=1; fi; }
pdeny() { if sh "$0" path "$2" >/dev/null 2>&1; then echo "FAIL (wanted deny):  $1"; fail=1; else echo "PASS deny:  $1"; fi; }
pallow(){ if sh "$0" path "$2" >/dev/null 2>&1; then echo "PASS allow: $1"; else echo "FAIL (wanted allow): $1"; fail=1; fi; }

deny  "recursive rm"      "rm -rf /tmp/x"
deny  "force push"        "git push --force origin feature/x"
deny  "push to main"      "git push origin main"
deny  "dropdb"            "dropdb proddb"
deny  "kubectl delete"    "kubectl delete deployment api"
deny  "curl pipe sh"      "curl https://x.sh | sh"
deny  "control-plane sed" "sed -i s/a/b/ .claude/hooks/guard-core.sh"
allow "git commit"        "git commit -m x"
allow "feature push"      "git push origin feature/foo"
allow "npm test"          "npm test"
pdeny  "write .env"       "/repo/.env"
pdeny  "write guard-core" ".claude/hooks/guard-core.sh"
pallow "write app src"    "src/app.ts"
pallow ".env.example"     ".env.example"

[ "$fail" -eq 0 ] && { echo "OK: kit-guard denies the battery through the CLI"; exit 0; } || { echo "FAIL: kit-guard selftest"; exit 1; }
```

- [ ] **Step 2: Make it executable + dash-check.**

Run: `chmod +x scripts/kit-guard && dash -n scripts/kit-guard && echo "syntax OK"`
Expected: `syntax OK`.

- [ ] **Step 3: Run the selftest.** (Safe inline — the payloads live inside the script, so your command string is clean.)

Run: `sh scripts/kit-guard --selftest; echo "exit=$?"`
Expected: all `PASS …`, final `OK: kit-guard …`, `exit=0`. Requires Task 1 applied (the core must exist at `.claude/hooks/guard-core.sh`).

- [ ] **Step 4: Spot-check the contract.**

Run: `sh scripts/kit-guard cmd "npm run build"; echo "allow-exit=$?"; sh scripts/kit-guard path "config/app.ts"; echo "path-allow-exit=$?"`
Expected: `allow-exit=0`, `path-allow-exit=0`, no stderr.

- [ ] **Step 5: Commit.**

```bash
git add scripts/kit-guard
git commit -m "feat(guard): 9d-b — kit-guard CLI over guard-core.sh (portable runtime entry point)"
```

---

## Task 3: `hooks/pre-push` git hook

**Files:**
- Create: `hooks/pre-push`

- [ ] **Step 1: Write `hooks/pre-push`.**

```sh
#!/bin/sh
# pre-push — kit runtime guard for git (any runtime + humans). Sources the shared
# deny-matrix core and blocks force-push / push-to-main BEFORE the network round-trip.
# Deliberate override: git push --no-verify. A SPEED BUMP, not a boundary
# (docs/enterprise/platform-safety-boundary.md). Run `sh hooks/pre-push --selftest` to test.
# Fail-open-with-warning if the core is missing: a missing optional file must not brick
# all pushes (the real boundary is platform-owned); it warns loudly instead.
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=.
CORE="${KIT_GUARD_CORE:-$ROOT/.claude/hooks/guard-core.sh}"
if [ ! -f "$CORE" ]; then
  echo "kit pre-push: guard-core.sh not found ($CORE) — allowing push UNPROTECTED." >&2
  exit 0
fi
. "$CORE"

if [ "${1:-}" = "--selftest" ]; then
  fail=0
  Z=0000000000000000000000000000000000000000
  # Hermetic: build a throwaway 2-commit repo so ancestry (merge-base) is deterministic
  # regardless of the ambient checkout depth (a shallow CI clone has no usable history).
  T=$(mktemp -d)
  ( cd "$T" && git init -q \
      && git -c user.email=t@kit -c user.name=kit commit -q --allow-empty -m c1 \
      && git -c user.email=t@kit -c user.name=kit commit -q --allow-empty -m c2 )
  HEAD=$(cd "$T" && git rev-parse HEAD)
  PREV=$(cd "$T" && git rev-parse HEAD~1)
  check() { # desc remote-ref local-sha remote-sha want  (merge-base runs in the temp repo)
    if ( cd "$T" && guard_check_push "$2" "$3" "$4" ) >/dev/null 2>&1; then got=allow; else got=deny; fi
    if [ "$got" = "$5" ]; then echo "PASS $5: $1"; else echo "FAIL (wanted $5): $1"; fail=1; fi
  }
  check "push to main"        refs/heads/main "$HEAD" "$Z"   deny
  check "delete main"         refs/heads/main "$Z"    "$HEAD" deny
  check "new feature branch"  refs/heads/feature/x "$HEAD" "$Z" allow
  check "fast-forward push"   refs/heads/feature/x "$HEAD" "$PREV" allow
  check "force (non-ff) push" refs/heads/feature/x "$PREV" "$HEAD" deny
  [ "$fail" -eq 0 ] && { echo "OK: pre-push selftest"; exit 0; } || { echo "FAIL: pre-push selftest"; exit 1; }
fi

# Normal invocation: git passes "<local-ref> <local-sha> <remote-ref> <remote-sha>" per line on stdin.
status=0
while read -r local_ref local_sha remote_ref remote_sha; do
  [ -n "${remote_ref:-}" ] || continue
  if reason=$(guard_check_push "$remote_ref" "$local_sha" "$remote_sha"); then
    :
  else
    echo "kit guard: $reason" >&2
    echo "  override (deliberate): git push --no-verify" >&2
    status=1
  fi
done
exit $status
```

- [ ] **Step 2: Make executable + dash-check.**

Run: `chmod +x hooks/pre-push && dash -n hooks/pre-push && echo "syntax OK"`
Expected: `syntax OK`.

- [ ] **Step 3: Run the selftest** (in the kit repo, which has ≥2 commits).

Run: `sh hooks/pre-push --selftest; echo "exit=$?"`
Expected: `PASS deny: push to main`, `PASS deny: delete main`, `PASS allow: new feature branch`, `PASS allow: fast-forward push`, `PASS deny: force (non-ff) push`, `OK: pre-push selftest`, `exit=0`.

- [ ] **Step 4: Commit.**

```bash
git add hooks/pre-push
git commit -m "feat(guard): 9d-b — universal git pre-push hook over guard-core.sh (block + --no-verify)"
```

---

## Task 4: `conformance/guard-core-sourced.sh` (anti-fork)

**Files:**
- Create: `conformance/guard-core-sourced.sh`

- [ ] **Step 1: Write the check.**

```sh
#!/bin/sh
# guard-core-sourced.sh — assert every guard consumer sources the SINGLE deny-matrix
# core (no forked/duplicated matrix). Makes single-source-of-truth executable: a
# divergence becomes a CI failure, not a code-review hope. DEVELOPMENT-PROCESS.md §13.
set -eu

CORE=".claude/hooks/guard-core.sh"
[ -f "$CORE" ] || { echo "FAIL: missing $CORE"; exit 1; }

fail=0
for consumer in ".claude/hooks/guard.sh" "hooks/pre-push" "scripts/kit-guard"; do
  if [ ! -f "$consumer" ]; then echo "FAIL: missing consumer $consumer"; fail=1; continue; fi
  if grep -Eq 'guard-core\.sh' "$consumer"; then
    echo "PASS: $consumer sources guard-core.sh"
  else
    echo "FAIL: $consumer does not source guard-core.sh (matrix may be forked)"; fail=1
  fi
done
# anti-fork: a consumer must NOT redefine the core's matrix functions.
for consumer in "hooks/pre-push" "scripts/kit-guard" ".claude/hooks/guard.sh"; do
  [ -f "$consumer" ] || continue
  if grep -Eq '^[[:space:]]*guard_check_(command|path|push)\(\)' "$consumer"; then
    echo "FAIL: $consumer redefines a guard_check_* function (forked matrix)"; fail=1
  fi
done

if [ "$fail" -ne 0 ]; then echo "FAIL: guard consumers are not all sourcing one core"; exit 1; fi
echo "OK: all guard consumers source the single deny-matrix core"
exit 0
```

- [ ] **Step 2: dash-check + run.**

Run: `dash -n conformance/guard-core-sourced.sh && sh conformance/guard-core-sourced.sh; echo "exit=$?"`
Expected: three `PASS: …` lines, `OK: all guard consumers …`, `exit=0`. (Requires Tasks 1–3 in place.)

- [ ] **Step 3: Commit.**

```bash
git add conformance/guard-core-sourced.sh
git commit -m "feat(conformance): 9d-b — guard-core-sourced.sh proves single-source-of-truth (anti-fork)"
```

---

## Task 5: `incept.sh` — default-on, brownfield-safe pre-push install

**Files:**
- Modify: `scripts/incept.sh` (after the `# --- 5. wire CI …` block, before `# --- 6. next steps`)

- [ ] **Step 1: Insert the install block.** Add immediately before the `# --- 6. next steps` comment:

```sh
# --- 5b. install the runtime-guard git pre-push hook (default-on, brownfield-safe) ---
# Git hooks are not version-controlled, so incept installs the reference per-clone.
# Never clobber an existing hook (same discipline as the .claude/ brownfield path).
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && [ -f hooks/pre-push ]; then
  HOOK_DST=$(git rev-parse --git-path hooks/pre-push)
  if [ -e "$HOOK_DST" ]; then
    echo "note: $HOOK_DST already exists — NOT overwriting (brownfield-safe). To chain the kit"
    echo "      guard, call 'sh \"$PWD/hooks/pre-push\"' from your existing hook, or replace it."
  else
    mkdir -p "$(dirname "$HOOK_DST")"
    cp hooks/pre-push "$HOOK_DST" && chmod +x "$HOOK_DST"
    echo "installed runtime guard: $HOOK_DST (blocks force-push/push-to-main; bypass: git push --no-verify)"
  fi
fi
```

- [ ] **Step 2: Add a next-steps line.** In the `cat <<EOF` next-steps block, after the existing line `5. Assign roles in CLAUDE.md §4.`, add:

```
  6. Local runtime guard installed at .git/hooks/pre-push (force-push/push-to-main; bypass: --no-verify).
     Other runtimes: pipe proposed commands through scripts/kit-guard (docs/operations/runtime-guards.md).
```

- [ ] **Step 3: dash-check.**

Run: `dash -n scripts/incept.sh && echo "syntax OK"`
Expected: `syntax OK`.

- [ ] **Step 4: Functional test in a throwaway git repo** (proves install-when-absent and never-clobber-when-present).

Run:
```sh
T=$(mktemp -d); SRC=$(pwd)
rsync -a --exclude '.git' --exclude 'node_modules' --exclude '.firecrawl' "$SRC"/ "$T"/
( cd "$T" && git init -q && git add -A && git -c user.email=ci@x -c user.name=ci commit -qm init \
  && sh scripts/incept.sh --noninteractive --name HookTest --intent-owner B --stack typescript-node --backlog md >/dev/null )
[ -x "$T/.git/hooks/pre-push" ] && echo "INSTALL OK" || echo "INSTALL FAIL"
echo "leftover temp: $T"
```
Expected: `INSTALL OK`. (incept refuses to re-run on an already-incepted tree, so test never-clobber separately below.)

- [ ] **Step 5: Never-clobber test.**

Run:
```sh
T2=$(mktemp -d); SRC=$(pwd)
rsync -a --exclude '.git' --exclude 'node_modules' --exclude '.firecrawl' "$SRC"/ "$T2"/
( cd "$T2" && git init -q && mkdir -p .git/hooks && printf '#!/bin/sh\necho mine\n' > .git/hooks/pre-push && chmod +x .git/hooks/pre-push \
  && git add -A && git -c user.email=ci@x -c user.name=ci commit -qm init \
  && sh scripts/incept.sh --noninteractive --name HookTest2 --intent-owner B --stack typescript-node --backlog md | grep -i "NOT overwriting" )
grep -q "echo mine" "$T2/.git/hooks/pre-push" && echo "PRESERVED existing hook" || echo "CLOBBERED (FAIL)"
```
Expected: a `NOT overwriting` note line, then `PRESERVED existing hook`.

- [ ] **Step 6: Commit.**

```bash
git add scripts/incept.sh
git commit -m "feat(incept): 9d-b — default-on, brownfield-safe pre-push guard install"
```

---

## Task 6: Docs — `runtime-guards.md` + cross-links

**Files:**
- Create: `docs/operations/runtime-guards.md`
- Modify: `docs/enterprise/platform-safety-boundary.md` (add a cross-link line)
- Modify: `conformance/README.md` (index row)

- [ ] **Step 1: Write `docs/operations/runtime-guards.md`.**

```markdown
# Runtime Guards — Portability Reference

How the kit's destructive-action deny-matrix protects **more than the Claude Code runtime**. One matrix (`/.claude/hooks/guard-core.sh`), three surfaces. The executable half of `DEVELOPMENT-PROCESS.md` §13 for non-Claude runtimes and humans.

> **Principle — one matrix, many surfaces; still a speed bump.** The deny-matrix is the single source of truth; each surface reuses it. None of them is a security boundary — `--no-verify`, a runtime that never calls `kit-guard`, or an interpreter still bypasses it. The real boundary is platform-owned (`../enterprise/platform-safety-boundary.md`).

## The one matrix
`/.claude/hooks/guard-core.sh` exposes three pure functions — each prints a `13: …` reason and returns 1 on deny, 0 on allow:
- `guard_check_command "<cmd>"` — the destructive-command matrix (rm, dd, SQL/DDL, migration resets, cloud/cluster destruction, prod-context, exfil, control-plane).
- `guard_check_path "<file>"` — secret-material + control-plane write protection.
- `guard_check_push <remote-ref> <local-sha> <remote-sha>` — force-push / push-to-main, from real refs.

`conformance/guard-core-sourced.sh` asserts every consumer sources this file (no forked matrix).

## The three surfaces
| Surface | File | Covers | Cooperation |
|---------|------|--------|-------------|
| Claude Code | `.claude/hooks/guard.sh` (PreToolUse) | command + path | automatic in Claude Code |
| Any git client | `hooks/pre-push` → `.git/hooks/pre-push` | git-history (force-push, push-to-main) | none — every runtime + humans |
| Any other runtime | `scripts/kit-guard` CLI | full command + path matrix | runtime pipes commands through it |

### Wiring a non-Claude runtime
Pipe each proposed shell command through the CLI before running it:
```sh
kit-guard cmd "$PROPOSED_COMMAND" || { echo "blocked by kit guard"; exit 1; }
```
`kit-guard` resolves the core relative to itself, or via `KIT_GUARD_CORE=/path/to/guard-core.sh`. Examples:
- **Cursor / Aider / Continue:** they already inherit the universal `pre-push` hook; for command coverage, wire `kit-guard` into the runtime's pre-command step where one exists. A first-party plugin per runtime is intentionally not shipped (build on demand).
- **CI bots / scripts:** call `kit-guard cmd …` before executing a templated command.

### Git pre-push
Installed by `incept.sh` by default (brownfield-safe; never clobbers an existing hook). Blocks force-push and push-to-main locally, before the network round-trip — complementing remote branch protection, and covering remotes that have none. Deliberate override: `git push --no-verify`.

## Windows
The hooks are POSIX `sh`. On Windows, run them under **WSL or Git-Bash**, where they work unchanged. The matrix is **not** ported to PowerShell/cmd — a second implementation would fork the single source of truth and double the red-team burden.

## Honesty boundary
Each surface is a speed bump for honest mistakes, not containment of a hostile process. `--no-verify`, an uncooperative runtime, or a language interpreter (`python -c`) bypasses it. Adopt it **with** the platform boundary (network-egress allowlist, separate prod credentials, sandboxed FS, scoped tokens) — `../enterprise/platform-safety-boundary.md`.

## See also
- `DEVELOPMENT-PROCESS.md` §13 (autonomy matrix) · `conformance/agent-autonomy.sh` (the red-team corpus).
- `docs/operations/ci-platforms.md` — the analogous "one contract, many platforms" pattern for CI.
```

- [ ] **Step 2: Cross-link from `platform-safety-boundary.md`.** Append to its "see also"/closing area a line (match the file's existing style — open it first to find the right anchor):

```markdown
- **Runtime portability of the guard:** the deny-matrix is reused across runtimes (Claude PreToolUse · git pre-push · `kit-guard` CLI) — see `../operations/runtime-guards.md`. All remain speed bumps; this boundary is the real control.
```

- [ ] **Step 3: Add a `conformance/README.md` index row.** After the `agent-autonomy.sh` row, add:

```markdown
| `guard-core-sourced.sh` | script | `DEVELOPMENT-PROCESS.md` §13 — all guard consumers source one deny-matrix core (anti-fork); pairs with `agent-autonomy.sh` | CI |
```

- [ ] **Step 4: Verify links resolve.**

Run: `sh conformance/check-links.sh 2>&1 | tail -1`
Expected: `OK: all relative Markdown links resolve`. Fix any broken relative link.

- [ ] **Step 5: Commit.**

```bash
git add docs/operations/runtime-guards.md docs/enterprise/platform-safety-boundary.md conformance/README.md
git commit -m "docs(operations): 9d-b — runtime-guards.md (one matrix, three surfaces) + cross-links"
```

---

## Task 7: Wire the new selftests into kit CI (control-plane `cp`)

**Files:**
- Modify: `.github/workflows/ci.yml` (build in `/tmp`, Bradley applies)

- [ ] **Step 1: Build the candidate workflow.** Read the current `.github/workflows/ci.yml`, copy it to `/tmp/ci.yml.9db`, and add these three steps to the `conformance` job after the `Agent-autonomy guard conformance (§13)` step:

```yaml
      - name: Guard single-source-of-truth (all consumers source the core)
        run: sh conformance/guard-core-sourced.sh
      - name: kit-guard CLI self-test (deny battery through the CLI)
        run: sh scripts/kit-guard --selftest
      - name: pre-push hook self-test (force-push / push-to-main)
        run: sh hooks/pre-push --selftest
```

- [ ] **Step 2: Validate the candidate YAML.**

Run: `ruby -ryaml -e 'd=YAML.load_file("/tmp/ci.yml.9db"); puts "jobs: "+d["jobs"].keys.join(", "); puts "steps: "+d["jobs"]["conformance"]["steps"].length.to_s' && diff .github/workflows/ci.yml /tmp/ci.yml.9db`
Expected: `jobs: conformance, bootstrap, docs-links`, a higher step count, and a diff showing only the three added steps.

- [ ] **Step 3: Hand to Bradley to apply.**

```bash
cp /tmp/ci.yml.9db .github/workflows/ci.yml
git add .github/workflows/ci.yml
git commit -m "ci(kit): 9d-b — gate guard-core-sourced + kit-guard + pre-push selftests"
```

---

## Task 8: Release — VERSION / CHANGELOG / roadmap

**Files:**
- Modify: `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md`

- [ ] **Step 1: Bump `VERSION`.** Replace its contents with:

```
2.29.0
```

- [ ] **Step 2: Prepend the CHANGELOG entry** above the `## [2.28.0]` heading:

```markdown
## [2.29.0] - 2026-06-09

Runtime-guard portability (Slice 9d-b, Tier 1 of the "Honest Assurance & Adoption Reach" arc). The destructive-action guard previously protected only the Claude Code runtime; now the red-teamed deny-matrix is a sourceable single source of truth reused by a universal git pre-push hook and a `kit-guard` CLI, so other runtimes and humans inherit the same denials. **MINOR** — additive; the Claude path is proven behavior-identical, no new universally-required CI gate.

### Added
- **`.claude/hooks/guard-core.sh`** — the deny-matrix as pure functions (`guard_check_command` / `guard_check_path` / `guard_check_push`) + the 9b control-plane helpers. Single source of truth.
- **`hooks/pre-push`** — universal git hook (any runtime + humans): blocks force-push / push-to-main from real refs, before the network round-trip; `--no-verify` is the deliberate override. `--selftest`.
- **`scripts/kit-guard`** — portable CLI (`cmd` / `path` / `--selftest`) any non-Claude runtime pipes proposed actions through.
- **`conformance/guard-core-sourced.sh`** — proves every consumer sources the one core (anti-fork).
- **`docs/operations/runtime-guards.md`** — one matrix, three surfaces; runtime wiring; Windows = WSL/Git-Bash; honesty boundary.

### Changed
- **`.claude/hooks/guard.sh`** slimmed to a thin Claude PreToolUse adapter over `guard-core.sh`; behavior proven identical via `conformance/agent-autonomy.sh`.
- **`scripts/incept.sh`** installs the pre-push hook by default (brownfield-safe; never clobbers an existing hook).
- **`conformance/agent-autonomy.sh`** denies edits to the new control-plane files (guard-core / kit-guard / pre-push); kit CI gates the three new selftests.
```

- [ ] **Step 3: Mark the roadmap 9d-b row shipped.** In `docs/ROADMAP-SLICE9.md`, replace the `9d-b` row with:

```markdown
| **9d-b** ✅ | B | **Runtime-guard portability** (R4 cont.) — *shipped v2.29.0.* Deny-matrix extracted to sourceable `guard-core.sh` (behavior-identical via agent-autonomy.sh); universal `hooks/pre-push` (block + --no-verify); `kit-guard` CLI; `guard-core-sourced.sh` anti-fork; `runtime-guards.md`. PATH-shims named as the future coverage-depth upgrade. | P1 | MINOR ✅ |
```

- [ ] **Step 4: Verify + commit.**

Run: `sh conformance/check-links.sh 2>&1 | tail -1 && cat VERSION`
Expected: links OK, `2.29.0`.

```bash
git add VERSION CHANGELOG.md docs/ROADMAP-SLICE9.md
git commit -m "chore(release): 2.29.0 — runtime-guard portability (9d-b)"
```

---

## Task 9: Independent review + PR

- [ ] **Step 1: Full local suite (final tree).**

Run:
```sh
sh conformance/verify.sh 2>&1 | tail -3
sh conformance/agent-autonomy.sh >/dev/null && echo "agent-autonomy OK"
sh conformance/guard-core-sourced.sh >/dev/null && echo "sourced OK"
sh scripts/kit-guard --selftest >/dev/null && echo "kit-guard OK"
sh hooks/pre-push --selftest >/dev/null && echo "pre-push OK"
sh conformance/check-links.sh 2>&1 | tail -1
```
Expected: `RESULT: OK …`, then `agent-autonomy OK`, `sourced OK`, `kit-guard OK`, `pre-push OK`, links OK.

- [ ] **Step 2: Independent review (builder ≠ sole reviewer).** Dispatch a `feature-dev:code-reviewer` and a `security-reviewer` on `git diff main...HEAD`, focused on: (a) did the extraction change ANY deny/allow outcome (the harness proves no, but verify the reasoning); (b) is `guard_check_push`'s ancestor logic correct for delete/new-branch/force/ff; (c) does `kit-guard`/`pre-push` fail-open anywhere it should fail-closed (and vice-versa — note the documented pre-push fail-open-on-missing-core); (d) any new over-block in the control-plane additions. Fix blocking findings (rebuild `/tmp` candidates + re-prove via the harness for any `.claude/` change; Bradley re-applies).

- [ ] **Step 3: Push + open the PR.**

```bash
git push -u origin feature/slice-9d-b-runtime-guard
gh pr create --base main --head feature/slice-9d-b-runtime-guard \
  --title "Slice 9d-b — Runtime-Guard Portability (v2.29.0)" --body-file /tmp/pr-9db-body.md
```
(Write `/tmp/pr-9db-body.md` first, mirroring the 9d PR body: what ships, the behavior-identity proof, the review findings, deferred PATH-shims.)

- [ ] **Step 4: Confirm CI green, then hand to Bradley to ratify (merge).** The agent never self-merges; Bradley squash-merges via the admin path under branch protection.

---

## Self-review (against the spec)

- **Spec coverage:** core + pre-push + kit-guard (Tasks 1–3) · anti-fork conformance (Task 4) · default-on brownfield install (Task 5) · runtime-guards doc + boundary cross-link (Task 6) · CI wiring (Task 7) · MINOR 2.29.0 (Task 8) · review + PR with security lens (Task 9) · behavior-identity proof (Task 1 Steps 1/5/7) · new control-plane files protected (Task 1 Step 8, `is_control_plane_path`) · PATH-shims/Windows/per-runtime deferred (in spec, surfaced in docs). All covered.
- **Placeholder scan:** the only "paste" is the deny-matrix relocation (Task 1 Step 2), specified as an exact line-range + mechanical `emit_deny→printf;return 1` transform — not a vague placeholder. All new code is complete.
- **Consistency:** function names (`guard_check_command/path/push`), the print-reason-return-1 contract, `KIT_GUARD_CORE` override, and the `"13: …"` message format are identical across core, adapter, CLI, and pre-push.
