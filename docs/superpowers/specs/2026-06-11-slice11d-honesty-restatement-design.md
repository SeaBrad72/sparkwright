# Slice 11d — Honesty & assurance restatement

**Status:** design approved (brainstorm), pre-plan.
**Arc:** Containment & the Platform Boundary (`docs/ROADMAP-SLICE11.md`). Follows 11a (MCP gate), 11b (egress), 11c (containment). Aimed by [A8](../reviews/2026-06-10-A8-mcp-egress-attack-surface.md).
**Version target:** v2.43.0 — **MINOR** (docs reconciliation + one drift-guard; no behaviour change).

---

## Problem

11a/11b/11c made controls real, but the **summary/narrative docs still describe the pre-arc world**: they frame the guard as a pure shell deny-list "speed bump" and the four platform controls as wholly **Org-owned**. Two specific gaps:
1. **Stale narratives** in `docs/enterprise/platform-safety-boundary.md` (top Status + "Why this exists"), `docs/enterprise/EXEC-BRIEF.md` (the "speed bump, not a boundary" line + the assurance table), and `DEVELOPMENT-PROCESS.md` §13 (the guard-boundary paragraph).
2. **The MCP capability gate (11a) was never recorded** in `docs/enterprise/compliance-crosswalk.md` or `conformance/audit-evidence-checklist.md` — it has no compliance row at all, despite being the one genuinely *Kit-enforced* in-process control.

11d reconciles these **without overclaiming** (the arc exists to prevent false assurance) and **regression-locks** the responsibility tiers so they cannot silently revert.

## The three responsibility tiers (now accurately assigned)

- **Kit-enforced** — the MCP capability gate (11a). The PreToolUse hook is in the control path and actually *denies* the call. Honest caveat: it gates MCP tool capability **by name**; the `net.egress` class within it is a name-match speed bump, not egress containment, and a renamed action is uncaught.
- **Kit-assisted** — egress (11b) + sandboxed FS / scoped tokens / separate prod creds (11c). The kit ships a reference and verifies a declared+wired attestation, but the **host enforces** (drops the packet, read-onlys the mount, expires the token).
- **Org-owned / speed-bump** — the shell/interpreter deny-list guard remains a speed bump for honest mistakes; the platform boundary is still the real control.

**The distinction 11d encodes:** Kit-enforced vs Kit-assisted turns on *who can stop the action*. Collapsing them into one "we cover it" tier is the overclaim the arc prevents — so the drift-guard enforces it mechanically.

## Goals

1. Reconcile the three narrative docs to reflect the new coverage without overclaiming.
2. Add the **MCP capability gate** to the crosswalk + audit-evidence at tier **Kit-enforced** (with the by-name caveat).
3. Ship **`conformance/assurance-tiers.sh`** — a drift-guard that the crosswalk states each arc control at its real tier; CI-wired + a live control in `verify.sh`.
4. Resolve the carried 11c LOW (honor-based attestation dates) by **documenting** it.

## Non-goals

- No new runtime behaviour, no new enforcement. Pure docs + one consistency check.
- No re-litigation of the 11a/b/c tier moves already in the crosswalk (egress + rows 37/38/39 are already Kit-assisted).
- A9 (red-team exit gate) is separate.

---

## Components

### 1. Narrative reconciliation (no overclaiming)
Each edit *adds* the new reality as a qualifier; it never deletes the honest core (the deny-list argument, "these four controls are the boundary", "enforcement is platform-owned").

- **`docs/enterprise/platform-safety-boundary.md`** — keep the title "(Org-owned)", the "Why this exists" deny-list argument, and the four controls. Add a short **"What the kit now provides"** note after the four controls: the kit ships references for #1–4 and verifies them declared+wired (**Kit-assisted**); the guard now *gates MCP capabilities in-process* (**Kit-enforced** for that surface, by name); **enforcement of #1–4 remains platform-owned**, and the shell/interpreter deny-list is still a speed bump.
- **`docs/enterprise/EXEC-BRIEF.md`** — the "speed bump, not a boundary" sentence gains a clause: *…for shell and interpreter commands; it now also enforces a deny-by-default MCP capability gate (the one in-process control that is real enforcement), and the kit ships + verifies references for the four platform controls — which remain platform-enforced.* The assurance table reflects egress/sandbox/tokens/creds as Kit-assisted (reference + verified) rather than purely Org-owned.
- **`DEVELOPMENT-PROCESS.md` §13** (the guard paragraph) — the guard is a speed bump for shell/interpreter **and** a deny-by-default gate for MCP capabilities (Kit-enforced); the four platform controls are now kit-referenced + verify-wired (Kit-assisted); enforcement still platform-owned. (`DEVELOPMENT-PROCESS.md` is NOT control-plane-protected — editable directly. Watch the `doc-budget.sh` line budget.)

### 2. MCP capability gate → Kit-enforced rows
- `docs/enterprise/compliance-crosswalk.md`: add a row — control "Agent/runtime MCP capability gate (deny-by-default)", evidence "`conformance/mcp-policy.sh` + `agent-autonomy.sh` MCP cases", tier **Kit-enforced**, with the inline caveat "gates MCP tool capability by name; the net.egress class is a name-match speed bump, not egress containment".
- `conformance/audit-evidence-checklist.md`: add the matching row → **Auto:** `sh conformance/mcp-policy.sh`.

### 3. `conformance/assurance-tiers.sh` (drift-guard)
Grep-based (badge-version/doc-budget style). For each arc control it locates the crosswalk row by a label regex and asserts the expected tier token is present; fail-closed if a row is missing or carries the wrong tier.

| Control (row label regex) | Asserted tier |
|---|---|
| `MCP capability gate` | `Kit-enforced` |
| `network-egress allowlist` | `Kit-assisted` |
| `sandboxed filesystem` | `Kit-assisted` |
| `scoped short-lived tokens` | `Kit-assisted` |
| `separate prod credentials` | `Kit-assisted` |

`--selftest` battery (mktemp crosswalk fixtures): a correct fixture → PASS; a reverted fixture (egress → `Org-owned`) → FAIL; a missing-row fixture → FAIL. Default target `docs/enterprise/compliance-crosswalk.md`; overridable by arg for the fixtures.

Wiring: a CI `--selftest` step **and** added to `conformance/verify.sh` as a live **control** (so a Review-time `verify.sh` catches a real tier revert). `conformance/README.md` index row.

### 4. The carried 11c LOW — document-and-accept
Add one line to `conformance/containment-readiness.md` (Honesty section): attestation dates are honor-based and must sit on the aspect's own line; the gate verifies the date's presence + shape, not authorship intent. No code change — both candidate fixes false-negative (`[^:]*` breaks colon-containing descriptions; end-of-line anchoring breaks the RUNBOOK template's own trailing comments).

### 5. Meta / CI
- `.github/workflows/ci.yml` (control-plane → human `cp`): add a `assurance-tiers.sh --selftest` step.
- `VERSION` → `2.43.0`; `CHANGELOG.md`; `docs/ROADMAP-SLICE11.md` 11d → ✅ shipped.

---

## Honesty boundary (this slice IS an honesty claim)

- The restatement must **add qualifiers, not delete caveats.** Every edit keeps: the deny-list-is-a-speed-bump argument, "these four controls are the boundary", "enforcement is platform-owned".
- "Kit-enforced" appears only for the MCP gate, always with the **by-name caveat**.
- `assurance-tiers.sh` verifies the tiers are **stated** (consistency/drift), not that they are "true" — it is a documentation drift-guard, and says so in its header.

## Testing

- `dash -n conformance/assurance-tiers.sh`; `assurance-tiers.sh --selftest` green (correct/reverted/missing fixtures behave); live `assurance-tiers.sh` → PASS against the real crosswalk after the MCP row lands.
- `check-links.sh`, `doc-budget.sh` (narrative edits within budget), `verify.sh` → OK (now including the assurance-tiers control).
- Security-owner-lens review of the restatement before the PR.

## Governance

Feature branch → PR → **human ratification** (Bradley merges; agent never self-merges). Control-plane `cp` for `ci.yml`. Security-owner lens on the restatement (the whole slice is an honesty claim). Kit stays generic/anonymized ([[kit-anonymization]]).

## Out of scope / deferred
- A9 — red-team re-test of the MCP gate + W2/W3 closure (the arc's exit gate, next).
- Any change to runtime behaviour or the 11a/b/c controls themselves.
