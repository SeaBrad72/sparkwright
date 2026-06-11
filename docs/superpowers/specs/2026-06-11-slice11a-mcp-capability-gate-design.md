# Slice 11a — MCP Capability Gate (design)

**Date:** 2026-06-11 · **Arc:** Slice 11 (Containment), step 11a · **Version target:** MINOR → **v2.40.0**
**Input:** the A8 attack-surface map ([`../reviews/2026-06-10-A8-mcp-egress-attack-surface.md`](../reviews/2026-06-10-A8-mcp-egress-attack-surface.md)) confirmed W3: the guard's PreToolUse matcher is `Bash|Write|Edit|NotebookEdit` and `guard.sh`'s adapter routes everything else to `*) allow`, so every `mcp__<server>__<action>` call bypasses the entire deny-matrix. A8 also showed W3 is **gateable in-kit** — an MCP tool name unspoofably reveals its capability — and proposed a 10-class capability taxonomy (9 deny-by-default + `data.read` allow-by-default).

## Scope (ratified at brainstorm)
Route MCP tool calls through the guard and **deny un-allowlisted destructive/egress MCP capabilities by default** (ON, fail-closed), classifying by **action-name heuristic** with a per-project **allowlist** escape hatch. Ship the gate + a runtime-agnostic policy contract + conformance. Honesty-preserving: this gates *what a name reveals*, not a guarantee against obfuscation, and the `net.egress` class is explicitly **not** egress containment (that is 11b's platform reference).

## Components

### 1. `guard_check_mcp "<tool_name>" "<allowlist>"` — the decision function (in `guard-core.sh`, kept pure)
The adapter passes the policy in as a string, so the core stays file-free and portable (mirrors `guard_check_command`). Decision order:
1. `tool_name` matches an **allowlist** entry — exact `mcp__server__action` or a `mcp__server__*` wildcard → **ALLOW** (return 0).
2. action verb is **read-only** (`read|get|list|search|query|fetch|describe|show|view|find|count`) → **ALLOW** (`data.read`). (`export`/`download` are deliberately **excluded** — they can exfiltrate — so they fall to step 4's fail-closed deny unless a project `classOverride`s or allowlists a genuinely read-only one.)
3. action verb is **destructive/egress** (`delete|drop|destroy|remove|truncate|reset|write|update|create|insert|upsert|patch|put|set|upload|publish|deploy|send|post|email|notify|apply|merge|push|revoke|rotate`) → **DENY**, printing the matched class.
4. otherwise (not confidently read-only) → **DENY (fail-closed)**, per A8.
A **classOverride** map in the policy lets a project reclassify a heuristically-misread tool (e.g. an `export` that is truly read-only). Verb match is on the action segment (after the last `__`), case-insensitive, substring-anchored so `create_table` matches `create`.

### 2. `guard.sh` — new `mcp__*)` adapter case
Loads `.claude/mcp-policy.json` (jq → newline allowlist + applies classOverride), calls `guard_check_mcp`, emits the Claude deny/allow. jq-absent → fail-closed deny for `mcp__*` (consistent with the existing jq-absent posture). The `*) allow` fallthrough remains for non-MCP, non-mutating tools (Read/Grep/Glob).

### 3. `settings.json` matcher
`"Bash|Write|Edit|NotebookEdit"` → `"Bash|Write|Edit|NotebookEdit|mcp__.*"` so MCP calls reach the hook.

### 4. `.claude/mcp-policy.json` (new, control-plane-protected)
Portable JSON:
```json
{ "allow": [], "classOverride": {} }
```
Shipped **default = empty allow** — the heuristic does the work (read-only allowed, destructive denied out-of-box). A project adds `mcp__server__action` / `mcp__server__*` entries it needs, and `classOverride` for misclassified tools. Added to `is_control_plane_path` (and the `guard.sh` shell-mutation path list) so **an agent cannot allowlist itself a bypass** — editing the policy is a human act, like `settings.json`.

### 5. `scripts/kit-guard mcp <tool_name> [policy-path]` — the portable contract
A new subcommand that loads a policy file (default `.claude/mcp-policy.json`) and calls `guard_check_mcp`, so a non-Claude runtime consumes the same gate. The **mcp-policy contract** (file format + the classification rules) is documented in `docs/operations/runtime-guards.md`.

### 6. Conformance
- **`conformance/mcp-policy.sh` (new)** — `--selftest` proves the classification on fixtures (no live policy needed): un-allowlisted destructive MCP → deny · read-only MCP → allow · explicitly-allowlisted destructive → allow · `classOverride` reclassify → allow · unknown/garbled verb → deny (fail-closed). Drives `guard_check_mcp` directly with fixture allowlists.
- **`conformance/agent-autonomy.sh`** gains MCP cases over the **live** `guard.sh` path (against the shipped empty-allow policy): `mcp__filesystem__delete_file` denied · `mcp__postgres__query` allowed.
- `conformance/guard-core-sourced.sh` still green (single core; the new function lives in the one core).

### 7. Honesty (the invariant)
`docs/operations/runtime-guards.md` + a one-line note in `docs/enterprise/platform-safety-boundary.md`: the MCP gate is **Kit-enforced for what the tool name reveals** — it stops an un-allowlisted destructive/egress MCP call, but a renamed/obfuscated action or a server that hides capability behind a read-looking name is **not** caught; and the `net.egress` class is a **name-match speed bump, not egress containment** (that is the platform allowlist, 11b). No green check implies containment a shell/heuristic can't deliver.

## Files

| File | Change | Owner |
|------|--------|-------|
| `.claude/hooks/guard-core.sh` | **New `guard_check_mcp`** + `mcp-policy.json` added to `is_control_plane_path` | **human `cp`** (security-owner lens) |
| `.claude/hooks/guard.sh` | new `mcp__*)` adapter case (loads policy, calls core) | **human `cp`** |
| `.claude/settings.json` | matcher `… |mcp__.*` | **human `cp`** |
| `.claude/mcp-policy.json` | **New** — portable policy, shipped empty-allow | **human `cp`** |
| `scripts/kit-guard` | `mcp <tool_name> [policy-path]` subcommand | **human `cp`** |
| `conformance/mcp-policy.sh` | **New** — classification `--selftest` | agent |
| `conformance/agent-autonomy.sh` | MCP live-path cases | agent |
| `conformance/README.md` | index row | agent |
| `docs/operations/runtime-guards.md` | the mcp-policy contract + classification rules + honesty | agent |
| `docs/enterprise/platform-safety-boundary.md` | one-line MCP-gate note (Kit-enforced-for-name; egress still platform) | agent |
| `.github/workflows/ci.yml` | `mcp-policy.sh` + selftest | **human `cp`** |
| `docs/ROADMAP-SLICE11.md`, `VERSION`, `CHANGELOG.md` | 11a → shipped; 2.40.0 | agent |

## Verification
- `sh conformance/mcp-policy.sh --selftest` → all classification cases pass (deny destructive, allow read, allow allowlisted, allow override, deny fail-closed).
- `sh conformance/agent-autonomy.sh` → green incl. the new MCP live-path cases AND every existing Bash/destructive/control-plane assertion (no regression).
- `sh scripts/kit-guard --selftest` + `sh hooks/pre-push --selftest` + `sh conformance/guard-core-sourced.sh` → green (single core, all consumers).
- `dash -n` clean on the edited scripts; `ruby -ryaml` parses the ci.yml candidate; `sh conformance/verify.sh` + `check-links.sh` green.
- **Security-owner lens** on the control-plane diff: confirm (a) only the MCP routing/policy is added, the existing destructive matrix is byte-for-byte intact; (b) `.claude/mcp-policy.json` is control-plane-protected (an agent editing it is denied); (c) fail-closed holds (jq-absent and unclassifiable both deny).
- Anonymization: generic ([[kit-anonymization]]).

## Out of scope / deferred
- **Egress enforcement** (W2) — 11b ships the platform egress reference + `egress-policy.sh`; 11a's `net.egress` class is name-match only, explicitly not containment.
- **Sandbox / scoped tokens** — 11c.
- **Crosswalk responsibility-tier moves** (Org-owned → Kit-enforced/assisted) — 11d, once 11b/c also land.
- A curated per-server class map — rejected at brainstorm (the heuristic + allowlist + fail-closed avoids an ever-growing kit-owned map).

## Known implications
- A freshly-adopted project is **protected against un-allowlisted destructive MCP calls by default** — W3 closed without configuration; projects allowlist what they need.
- The gate is honest about its ceiling (name-reveals-capability; obfuscation + egress remain the platform's job), so it does not re-introduce false assurance.
- A future MCP server with an unusual action vocabulary may hit a false-positive deny → the project adds an allowlist/override entry (deny-by-default favors safety).

## Post-review hardening (security-owner lens, 2026-06-11)
The independent security review returned **SHIP-WITH-NITS** (no exploitable bypass). Two findings were folded into 11a before merge:
- **Compound-name evasion (MED→closed in-kit):** the original heuristic matched only the action's *leading* verb, so a read prefix masked a destructive tail (`get_and_delete`, `fetchAndExport` classified read). The classifier now **tokenizes** the action (camelCase→snake, lowercased) and downgrades to destructive if **any** token is a destructive verb — while whole-token matching keeps legit read compounds allowed (`list_deployments`≠`deploy`). This also makes non-verb lookalikes (`getter`, `counter`) fail-closed. A *renamed* action (`get_data` that secretly exfiltrates) remains uncatchable by name and stays the platform boundary's job — the disclosed ceiling is unchanged.
- **Green-while-dark (LOW→closed):** `conformance/mcp-policy.sh` now also asserts the `settings.json` PreToolUse matcher routes `mcp__*`, so classification can't pass while the live hook is silently disconnected.
- **Server-wildcard breadth (LOW):** documented — `mcp__server__*` admits every tool on that server; the policy `_comment` and `runtime-guards.md` advise preferring exact-tool allows.
