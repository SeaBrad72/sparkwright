# MCP Capability Gate (Slice 11a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route MCP tool calls through the guard and deny un-allowlisted destructive/egress MCP capabilities by default (ON, fail-closed), classifying by an action-name heuristic with a per-project allowlist — closing W3.

**Architecture:** A new pure `guard_check_mcp` in the shared `guard-core.sh`; a `mcp__*)` adapter case in `guard.sh` that loads `.claude/mcp-policy.json`; the settings matcher extended to `mcp__.*`; a `kit-guard mcp` subcommand (portable contract); conformance + docs. Several control-plane files → built/validated in `/tmp`, applied by the human in one `cp` block. MINOR → v2.40.0.

**Tech Stack:** POSIX `sh` + jq (already a guard dependency). The core stays pure (adapter passes the policy in); validated by sourcing the candidate via `KIT_GUARD_CORE`.

---

## Execution notes
- **Control-plane `cp` (one block, Task 6):** `.claude/hooks/guard-core.sh` · `.claude/hooks/guard.sh` · `.claude/settings.json` · `.claude/mcp-policy.json` (new) · `scripts/kit-guard` · `.github/workflows/ci.yml`. Applied with `KIT_GUARD_SELFEDIT=1`. **Security-owner lens** on the whole diff: only MCP routing/policy added; the destructive matrix byte-for-byte intact.
- **Pre-cp validation uses `KIT_GUARD_CORE`** — `kit-guard` and `conformance/mcp-policy.sh` both honor `KIT_GUARD_CORE` to source a candidate core, so the new `guard_check_mcp` is proven against `/tmp/guard-core.sh.11a` before it's applied.
- **The guard over-blocks commands that pair a control-plane path with a verb** — run test corpora from script files (`sh /tmp/x.sh`), never inline.
- **Branch:** `feature/slice-11a-mcp-capability-gate` (holds the spec, commit `f80898e`).
- **Anonymization** ([[kit-anonymization]]): generic.

## File structure

| File | Responsibility |
|------|----------------|
| `.claude/hooks/guard-core.sh` (modify, cp) | `guard_check_mcp` (pure) + `mcp-policy.json` in control-plane path lists |
| `.claude/hooks/guard.sh` (modify, cp) | `mcp__*)` case loads policy → core; jq-absent fail-closed for MCP |
| `.claude/settings.json` (modify, cp) | matcher `…|mcp__.*` |
| `.claude/mcp-policy.json` (new, cp) | portable policy, shipped empty-allow |
| `scripts/kit-guard` (modify, cp) | `mcp <tool> [policy]` subcommand + 2 selftest cases |
| `conformance/mcp-policy.sh` (new) | classification corpus (sources core via `KIT_GUARD_CORE`) |
| `conformance/agent-autonomy.sh` (modify) | MCP live-path cases |
| `conformance/README.md` (modify) | index row |
| `docs/operations/runtime-guards.md` (modify) | the mcp-policy contract + classification + honesty |
| `docs/enterprise/platform-safety-boundary.md` (modify) | one-line MCP-gate note |
| `.github/workflows/ci.yml` (modify, cp) | `mcp-policy.sh` step |
| `docs/ROADMAP-SLICE11.md`, `VERSION`, `CHANGELOG.md` (modify) | 11a → shipped; 2.40.0 |

---

## Task 1: Build + validate the `guard-core.sh` candidate (`guard_check_mcp`)

**Files:** Read `.claude/hooks/guard-core.sh`; Write `/tmp/guard-core.sh.11a`

- [ ] **Step 1: Read the live core** (`.claude/hooks/guard-core.sh`) with the Read tool.

- [ ] **Step 2: Write `/tmp/guard-core.sh.11a`** = the live core, with TWO changes:

  **(2a) Add `mcp-policy.json` to the two control-plane path lists** so an agent cannot edit the policy. In `is_control_plane_path()`, add to the `case` alternation: `*.claude/mcp-policy.json|.claude/mcp-policy.json|` (place alongside the `settings.local.json` line). In `guard_check_path()`'s basename `case`, add `mcp-policy.json` to the list `guard.sh|guard-core.sh|kit-guard|pre-push|settings.json|settings.local.json|CODEOWNERS`.

  **(2b) Add the `guard_check_mcp` function** immediately after `guard_check_command()` (before `guard_check_path`):
```sh
# guard_check_mcp "<tool>" "<allowlist>" "<overrides>": ALLOW (return 0) / DENY (return 1 + reason).
# Pure: the adapter loads the policy and passes it in (the core never reads a file).
#   <tool>      a Claude MCP tool name, mcp__<server>__<action> (action = segment after the last __)
#   <allowlist> newline list of exact mcp__server__action OR mcp__server__* wildcards (explicit permit)
#   <overrides> newline list of "mcp__server__action=class" (reclassify; class 'read'/'data.read' => allow)
# Decision: allowlist > override-class > tokenized action-verb heuristic > fail-closed deny.
#   The heuristic tokenizes the action (camelCase->snake, lowercased): the first token must be a
#   read verb to allow, and ANY destructive verb token downgrades to deny (so get_and_delete /
#   fetchAndExport deny; list_deployments / get_updates stay read - the noun is not the verb).
# Honest ceiling: classifies by what the NAME reveals; a renamed action (get_data that exfiltrates),
# a server wildcard that admits a destructive tool, and real egress are NOT caught here
# (egress is the platform allowlist — docs/enterprise/platform-safety-boundary.md).
guard_check_mcp() {
  t=$1; al=$2; ov=$3
  # 1. explicit allowlist: exact tool, or its server wildcard (mcp__server__*)
  if printf '%s\n' "$al" | grep -qxF -- "$t" 2>/dev/null; then return 0; fi
  if printf '%s\n' "$al" | grep -qxF -- "${t%__*}__*" 2>/dev/null; then return 0; fi
  # 2. class: a per-tool override wins; else heuristic on the action segment.
  act=${t##*__}
  cls=$(printf '%s\n' "$ov" | while IFS='=' read -r k v; do [ "$k" = "$t" ] && { printf '%s' "$v"; break; }; done || true)  # || true: loop exits 1 on no-match; set -e would abort the assignment
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
  fi
  case "$cls" in
    read|data.read) return 0 ;;
    unknown) printf '13: MCP tool %s is not classifiable as read-only - denied (fail-closed). Allowlist it in .claude/mcp-policy.json if safe.' "$t"; return 1 ;;
    *) printf '13: MCP tool %s is a destructive/egress capability (%s) - human-gated. Allowlist it in .claude/mcp-policy.json if intended.' "$t" "$cls"; return 1 ;;
  esac
}
```

- [ ] **Step 3: dash-check + source-test the candidate from a script file** (the corpus payloads must not be inline). Write `/tmp/mcp-srctest.sh`:
```sh
#!/bin/sh
. /tmp/guard-core.sh.11a
chk() { if guard_check_mcp "$1" "$2" "$3" >/dev/null 2>&1; then echo "ALLOW: $1"; else echo "DENY:  $1"; fi; }
chk "mcp__postgres__query"          "" ""                                  # expect ALLOW (read)
chk "mcp__filesystem__delete_file"  "" ""                                  # expect DENY (destructive)
chk "mcp__filesystem__delete_file"  "mcp__filesystem__delete_file" ""      # expect ALLOW (allowlist)
chk "mcp__filesystem__delete_file"  "mcp__filesystem__*" ""                # expect ALLOW (wildcard)
chk "mcp__reports__export_csv"      "" ""                                  # expect DENY (export excluded)
chk "mcp__reports__export_csv"      "" "mcp__reports__export_csv=read"     # expect ALLOW (override)
chk "mcp__weird__frobnicate"        "" ""                                  # expect DENY (fail-closed)
chk "mcp__github__createIssue"      "" ""                                  # expect DENY (camelCase create)
```
  Run: `dash -n /tmp/guard-core.sh.11a && echo "syntax OK"`.
  Run: `sh /tmp/mcp-srctest.sh`.
  Expected: ALLOW for query / allowlisted-delete / wildcard-delete / override-export; DENY for delete_file / export_csv / frobnicate / createIssue.

(No commit — this is a `/tmp` candidate applied in Task 6.)

---

## Task 2: `conformance/mcp-policy.sh` (classification corpus)

**Files:** Create `conformance/mcp-policy.sh`

- [ ] **Step 1: Write it** (sources the core via `KIT_GUARD_CORE` so it validates the `/tmp` candidate now and the live core in CI):
```sh
#!/bin/sh
# mcp-policy.sh — proves the MCP capability gate's classification (Slice 11a).
# The corpus IS the test: drives guard_check_mcp directly with fixture allowlists/overrides.
# Sources the deny-matrix core (override with KIT_GUARD_CORE for pre-apply validation).
#   sh conformance/mcp-policy.sh
# Exit: 0 = all cases correct · 1 = a case wrong. POSIX sh; dash-clean.
set -eu

CORE="${KIT_GUARD_CORE:-.claude/hooks/guard-core.sh}"
[ -f "$CORE" ] || { echo "FAIL: guard-core not found ($CORE)"; exit 1; }
. "$CORE"

fail=0
deny()  { if guard_check_mcp "$2" "$3" "$4" >/dev/null 2>&1; then echo "FAIL (wanted deny):  $1"; fail=1; else echo "PASS deny:  $1"; fi; }
allow() { if guard_check_mcp "$2" "$3" "$4" >/dev/null 2>&1; then echo "PASS allow: $1"; else echo "FAIL (wanted allow): $1"; fail=1; fi; }

# deny-by-default destructive/egress (empty policy)
deny  "fs delete"          "mcp__filesystem__delete_file"  "" ""
deny  "db drop"            "mcp__postgres__drop_table"     "" ""
deny  "cloud deploy"       "mcp__vercel__deploy_project"   "" ""
deny  "vcs write"          "mcp__github__createIssue"      "" ""
deny  "msg send (egress)"  "mcp__slack__post_message"      "" ""
deny  "export (exfil)"     "mcp__reports__export_csv"      "" ""
deny  "fail-closed verb"   "mcp__weird__frobnicate"        "" ""
# allow read-only by default
allow "db read"            "mcp__postgres__query"          "" ""
allow "list"               "mcp__github__list_issues"      "" ""
# allowlist + wildcard + override escape hatches
allow "allowlisted exact"  "mcp__filesystem__delete_file"  "mcp__filesystem__delete_file" ""
allow "allowlisted wild"   "mcp__filesystem__write_file"   "mcp__filesystem__*" ""
allow "override to read"   "mcp__reports__export_csv"      "" "mcp__reports__export_csv=read"

[ "$fail" -eq 0 ] && { echo "OK: MCP capability gate classifies correctly"; exit 0; } || { echo "FAIL: mcp-policy"; exit 1; }
```

- [ ] **Step 2: Make executable + dash + run against the candidate.**
  Run: `chmod +x conformance/mcp-policy.sh && dash -n conformance/mcp-policy.sh && echo "syntax OK"`.
  Run: `KIT_GUARD_CORE=/tmp/guard-core.sh.11a sh conformance/mcp-policy.sh; echo "exit=$?"` → all PASS, `OK`, exit 0. (The live core lacks `guard_check_mcp` until Task 6, so validate against the candidate now.)

- [ ] **Step 3: Commit.**
  ```bash
  git add conformance/mcp-policy.sh
  git commit -m "feat(conformance): 11a — mcp-policy.sh proves the MCP capability-gate classification"
  ```

---

## Task 3: Build the remaining control-plane candidates

**Files:** Write `/tmp/guard.sh.11a`, `/tmp/settings.json.11a`, `/tmp/mcp-policy.json.11a`, `/tmp/kit-guard.11a`

- [ ] **Step 1: `/tmp/mcp-policy.json.11a`** (the shipped default — empty allow):
```json
{
  "_comment": "MCP capability gate policy (Slice 11a). guard_check_mcp denies un-allowlisted destructive/egress MCP tools by default. Add the tools this project needs. Control-plane: edit only via human maintenance.",
  "allow": [],
  "classOverride": {}
}
```

- [ ] **Step 2: `/tmp/guard.sh.11a`** = live `.claude/hooks/guard.sh` (Read it) with TWO changes:
  - In `deny_if_mutating()`, extend the matcher case so MCP is fail-closed when jq is absent:
    ```sh
    case "$1" in
      Bash|Write|Edit|NotebookEdit|mcp__*)
        emit_deny "agent-guard: $2 (DEVELOPMENT-PROCESS.md 13). Mutating tools are denied until resolved." ;;
      *) allow ;;
    esac
    ```
  - In the main `case "$TOOL" in`, add an `mcp__*)` arm BEFORE the `*) allow` arm:
    ```sh
      mcp__*)
        POL="$(dirname "$0")/../mcp-policy.json"
        AL=""; OV=""
        if [ -f "$POL" ]; then
          AL=$(jq -r '.allow[]? // empty' "$POL" 2>/dev/null || printf '')
          OV=$(jq -r '(.classOverride // {}) | to_entries[] | "\(.key)=\(.value)"' "$POL" 2>/dev/null || printf '')
        fi
        if reason=$(guard_check_mcp "$TOOL" "$AL" "$OV"); then allow; else emit_deny "$reason"; fi ;;
    ```

- [ ] **Step 3: `/tmp/settings.json.11a`** = live `.claude/settings.json` (Read it) with the matcher changed:
  `"matcher": "Bash|Write|Edit|NotebookEdit"` → `"matcher": "Bash|Write|Edit|NotebookEdit|mcp__.*"`.

- [ ] **Step 4: `/tmp/kit-guard.11a`** = live `scripts/kit-guard` (Read it) with:
  - a new `mcp)` arm in the dispatch `case` (after `path)`):
    ```sh
      mcp)
        [ $# -ge 2 ] || { echo "usage: kit-guard mcp \"<mcp__tool>\" [policy-path]" >&2; exit 2; }
        pol=${3:-$SELF_DIR/../.claude/mcp-policy.json}
        al=""; ov=""
        if [ -f "$pol" ] && command -v jq >/dev/null 2>&1; then
          al=$(jq -r '.allow[]? // empty' "$pol" 2>/dev/null || printf '')
          ov=$(jq -r '(.classOverride // {}) | to_entries[] | "\(.key)=\(.value)"' "$pol" 2>/dev/null || printf '')
        fi
        if reason=$(guard_check_mcp "$2" "$al" "$ov"); then exit 0; else echo "$reason" >&2; exit 1; fi ;;
    ```
  - the usage line list updated (`cmd|path|mcp|--selftest|--help`), and TWO selftest cases appended (after the `pallow ".env.example"` line) using a helper that runs the mcp subcommand:
    ```sh
    mdeny()  { if sh "$0" mcp "$2" >/dev/null 2>&1; then echo "FAIL (wanted deny):  $1"; fail=1; else echo "PASS deny:  $1"; fi; }
    mallow() { if sh "$0" mcp "$2" >/dev/null 2>&1; then echo "PASS allow: $1"; else echo "FAIL (wanted allow): $1"; fail=1; fi; }
    mdeny  "mcp destructive" "mcp__filesystem__delete_file"
    mallow "mcp read-only"   "mcp__postgres__query"
    ```
    (These resolve the policy via `$SELF_DIR/../.claude/mcp-policy.json` — the shipped empty-allow — so destructive denies, read allows.)

- [ ] **Step 5: Validate all four candidates.**
  Run: `dash -n /tmp/guard.sh.11a && dash -n /tmp/kit-guard.11a && echo "sh syntax OK"`.
  Run: `ruby -rjson -e 'JSON.parse(File.read("/tmp/mcp-policy.json.11a")); JSON.parse(File.read("/tmp/settings.json.11a")); puts "json OK"'`.
  Run: `diff .claude/settings.json /tmp/settings.json.11a` → only the matcher line differs.

(No commit — applied in Task 6.)

---

## Task 4: Conformance MCP live-path cases + index

**Files:** Modify `conformance/agent-autonomy.sh`, `conformance/README.md`

- [ ] **Step 1: Add MCP live-path cases to `agent-autonomy.sh`.** Find the allow-block line `assert_allow "git commit --amend"  …` and after the must-DENY block add (place near the other `assert_deny` lines):
```sh
assert_deny "mcp destructive tool" '{"tool_name":"mcp__filesystem__delete_file","tool_input":{}}'
assert_allow "mcp read-only tool"  '{"tool_name":"mcp__postgres__query","tool_input":{}}'
```
(These exercise the live `guard.sh` mcp arm against the shipped empty-allow policy; they pass AFTER Task 6's `cp`.)

- [ ] **Step 2: conformance/README index row.** After the `dor-defined.sh`/other rows (any stable anchor), add to the script table:
```markdown
| `mcp-policy.sh` | script | Slice 11a — the MCP capability gate classifies correctly: un-allowlisted destructive/egress MCP tools denied (fail-closed), read-only allowed, allowlist/override honored | CI |
```

- [ ] **Step 3: Commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1`.
  ```bash
  git add conformance/agent-autonomy.sh conformance/README.md
  git commit -m "test(conformance): 11a — agent-autonomy MCP live-path cases + mcp-policy index row"
  ```

---

## Task 5: Docs — the contract + the honesty note

**Files:** Modify `docs/operations/runtime-guards.md`, `docs/enterprise/platform-safety-boundary.md`

- [ ] **Step 1: `runtime-guards.md` — the mcp-policy contract.** Append a section:
```markdown

## MCP capability gate (the mcp-policy contract)

The guard sees MCP tool calls too (Claude PreToolUse matcher `mcp__.*`). `guard_check_mcp` (in `guard-core.sh`) classifies each `mcp__<server>__<action>` by its action verb and **denies un-allowlisted destructive/egress capabilities by default** (fail-closed):
- **read-only** verbs (`read/get/list/search/query/fetch/describe/show/view/find/count`) → allow;
- **destructive/egress** verbs (`delete/drop/create/update/write/upload/publish/deploy/send/post/email/apply/merge/push/revoke/rotate/export/download…`) → deny, naming the class;
- anything not confidently read-only → **deny (fail-closed)**.

**Policy** (`.claude/mcp-policy.json`, control-plane-protected): `{ "allow": ["mcp__server__action" | "mcp__server__*"], "classOverride": { "mcp__x__export": "read" } }`. Shipped empty — a project allowlists what it needs. **Portable:** any runtime calls `kit-guard mcp "<tool>" [policy]` to apply the same gate.

**Honest ceiling:** this gates *what the tool name reveals*. A renamed/obfuscated action, or a server hiding capability behind a read-looking name, is **not** caught; and the egress class is a **name-match speed bump, not egress containment** — real exfiltration defense is the platform network-egress allowlist (`../enterprise/platform-safety-boundary.md`).
```

- [ ] **Step 2: `platform-safety-boundary.md` — one-line note.** In the "Relationship to the guard" table's guard row (or just below it), add a sentence: append to the guard row's "What it catches" cell ` · un-allowlisted destructive/egress MCP tool calls (by name — see runtime-guards.md)`. Do NOT change the boundary rows; the network-egress allowlist remains the real exfil control.

- [ ] **Step 3: Commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1`.
  ```bash
  git add docs/operations/runtime-guards.md docs/enterprise/platform-safety-boundary.md
  git commit -m "docs(11a): document the mcp-policy contract + honest ceiling (name-reveal, not egress containment)"
  ```

---

## Task 6: Apply the control-plane bundle (human) + CI step

**Files:** the 5 `.claude`/`scripts` candidates + `.github/workflows/ci.yml`

- [ ] **Step 1: Build the CI candidate.** Read `.github/workflows/ci.yml`; Write `/tmp/ci.yml.11a` with one step added to the `conformance` job after the `Action-pinning self-test` step (or any stable anchor):
  ```yaml
      - name: MCP capability gate classification
        run: sh conformance/mcp-policy.sh
  ```
  Validate: `ruby -ryaml -e 'd=YAML.load_file("/tmp/ci.yml.11a"); puts d["jobs"].keys.join(",")'` → `conformance,bootstrap,docs-links`; `diff .github/workflows/ci.yml /tmp/ci.yml.11a` → only the one step.

- [ ] **Step 2: Hand Bradley the bundle (control-plane `cp`, self-edit flag).** Present exactly:
  ```bash
  cd ~/Development/agentic-sdlc-kit && KIT_GUARD_SELFEDIT=1 sh -c '
    cp /tmp/guard-core.sh.11a .claude/hooks/guard-core.sh &&
    cp /tmp/guard.sh.11a .claude/hooks/guard.sh &&
    cp /tmp/settings.json.11a .claude/settings.json &&
    cp /tmp/mcp-policy.json.11a .claude/mcp-policy.json &&
    cp /tmp/kit-guard.11a scripts/kit-guard &&
    cp /tmp/ci.yml.11a .github/workflows/ci.yml &&
    chmod +x scripts/kit-guard &&
    git add .claude/hooks/guard-core.sh .claude/hooks/guard.sh .claude/settings.json .claude/mcp-policy.json scripts/kit-guard .github/workflows/ci.yml &&
    git commit -m "feat(guard): 11a — MCP capability gate (route mcp__* through guard_check_mcp; deny-by-default; control-plane policy)"
  '
  ```
  Wait for confirmation before continuing.

---

## Task 7: Post-`cp` verification (the gate is live)

- [ ] **Step 1: The live gate + battery.**
  ```sh
  sh conformance/mcp-policy.sh >/dev/null && echo "mcp-policy (live core) OK"
  sh conformance/agent-autonomy.sh >/dev/null && echo "agent-autonomy OK (mcp destructive denied, read allowed; all prior intact)"
  sh scripts/kit-guard --selftest >/dev/null && echo "kit-guard OK (incl. mcp cases)"
  sh hooks/pre-push --selftest >/dev/null && echo "pre-push OK"
  sh conformance/guard-core-sourced.sh >/dev/null && echo "single-core OK"
  sh conformance/verify.sh 2>&1 | tail -1
  ```
  Expected: all OK; `verify.sh` RESULT: OK.

- [ ] **Step 2: Prove the policy file is itself protected** (agent cannot allowlist a bypass). From a script file `/tmp/policy-prot.sh`:
  ```sh
  . .claude/hooks/guard-core.sh
  if guard_check_path ".claude/mcp-policy.json" >/dev/null 2>&1; then echo "FAIL: mcp-policy editable by agent"; else echo "PASS: mcp-policy is control-plane-protected"; fi
  ```
  Run: `sh /tmp/policy-prot.sh` → `PASS`.

---

## Task 8: Release (VERSION / CHANGELOG / roadmap)

**Files:** Modify `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE11.md`

- [ ] **Step 1: `VERSION`** → `2.40.0`.
- [ ] **Step 2: Badge.** `sh conformance/badge-version.sh --fix && sh conformance/badge-version.sh; echo exit=$?` → PASS.
- [ ] **Step 3: CHANGELOG** above `## [2.39.0]`:
  ```markdown
  ## [2.40.0] - 2026-06-11

  MCP capability gate (Slice 11a — Containment arc). Closes W3: the guard now sees MCP tool calls and denies un-allowlisted destructive/egress MCP capabilities by default. **MINOR** — additive in-kit control + a portable contract; no universal gate added.

  ### Added
  - **`guard_check_mcp`** (in `guard-core.sh`) — classifies `mcp__<server>__<action>` by action verb; read-only allowed, destructive/egress denied, **fail-closed** on the unclassifiable. The Claude PreToolUse matcher now routes `mcp__.*`; `.claude/mcp-policy.json` (control-plane-protected, shipped empty-allow) carries the per-project allowlist + classOverride; `kit-guard mcp` exposes the same gate to any runtime (the portable mcp-policy contract).
  - **`conformance/mcp-policy.sh`** — classification corpus (deny destructive, allow read, honor allowlist/override, fail-closed). CI-gated; plus `agent-autonomy.sh` MCP live-path cases.

  ### Honesty
  - The gate is **Kit-enforced for what the tool name reveals** — a renamed/obfuscated action is not caught, and the egress class is a name-match speed bump, **not** egress containment (the platform allowlist, 11b). Documented in `runtime-guards.md` + `platform-safety-boundary.md`.
  ```
- [ ] **Step 4: roadmap.** In `docs/ROADMAP-SLICE11.md`, set the `11a` row Status → `✅ shipped v2.40.0` (with a one-line summary).
- [ ] **Step 5: Verify + commit.**
  Run: `cat VERSION` · `sh conformance/check-links.sh 2>&1 | tail -1`.
  ```bash
  git add VERSION README.md CHANGELOG.md docs/ROADMAP-SLICE11.md
  git commit -m "chore(release): 2.40.0 — MCP capability gate (11a)"
  ```

---

## Task 9: Final verification + independent review + PR

- [ ] **Step 1: Full sweep.**
  ```sh
  sh conformance/mcp-policy.sh >/dev/null && echo "mcp-policy OK"
  sh conformance/agent-autonomy.sh >/dev/null && echo "agent-autonomy OK"
  sh scripts/kit-guard --selftest >/dev/null && echo "kit-guard OK"
  sh conformance/guard-core-sourced.sh >/dev/null && echo "single-core OK"
  sh conformance/verify.sh 2>&1 | tail -1
  sh conformance/check-links.sh 2>&1 | tail -1
  grep -rniE "enterprise|public.media|bradley" conformance/mcp-policy.sh .claude/mcp-policy.json 2>/dev/null || echo "anon clean"
  ```
- [ ] **Step 2: Independent review (security-owner lens — control-plane safety surface).** Dispatch a reviewer on `git diff main...HEAD`: (a) the guard diff adds ONLY the MCP routing + `guard_check_mcp` + the policy-path protection — the entire existing destructive matrix is byte-for-byte intact (confirm via `agent-autonomy.sh` green + read the diff); (b) **fail-closed holds** — jq-absent denies `mcp__*`, and an unclassifiable action denies; (c) `.claude/mcp-policy.json` is control-plane-protected (an agent editing it is denied — Task 7 Step 2); (d) `guard_check_mcp` POSIX correctness (the allowlist exact+wildcard match, the override lookup `while IFS='='`, the verb heuristics incl. camelCase boundary, `export`/`download` excluded from read-only); (e) the honesty docs do not overclaim (name-reveal not containment; egress still platform); (f) anonymization. Fix findings.
- [ ] **Step 3: Push + PR.**
  ```bash
  git push -u origin feature/slice-11a-mcp-capability-gate
  gh pr create --base main --head feature/slice-11a-mcp-capability-gate \
    --title "Slice 11a — MCP Capability Gate (v2.40.0)" --body-file /tmp/pr-11a-body.md
  ```
  (Write `/tmp/pr-11a-body.md`: closes W3; deny-by-default MCP gate + portable contract; control-plane policy protected; honest ceiling; the control-plane cp.)
- [ ] **Step 4: Confirm CI green; hand to Bradley to ratify. Agent never self-merges.**

---

## Self-review (against the spec)
- **Spec coverage:** `guard_check_mcp` pure + heuristic + fail-closed (T1) · classification conformance (T2) · adapter/matcher/policy/kit-guard candidates (T3) · live-path cases + index (T4) · contract + honesty docs (T5) · control-plane cp + CI (T6) · post-cp verify incl. policy-protection (T7) · release (T8) · review + PR (T9). All spec components covered.
- **Placeholder scan:** all code is complete; the `/tmp` candidate approach is concrete (built from the live file + named diffs); the cp bundle is exact. No placeholders.
- **Consistency:** `guard_check_mcp "<tool>" "<allowlist>" "<overrides>"` 3-arg signature is identical across the core (T1), `mcp-policy.sh` (T2), `guard.sh`/`kit-guard` adapters (T3); the empty-allow `.claude/mcp-policy.json` is what the live-path tests (T4) + kit-guard selftest (T3) assume; version 2.40.0 consistent (T8).
