# Slice 11 Arc — Containment & the Platform Boundary

*"From a disclosed boundary to verified containment — honestly."*

**Source:** the A7 arc-closure re-review ([superpowers/reviews/2026-06-10-A7-rereview-arc-closure.md](superpowers/reviews/2026-06-10-A7-rereview-arc-closure.md)) left two HIGH residuals open **by honest design** — the guard's two deepest gaps, disclosed as platform-owned in [`enterprise/platform-safety-boundary.md`](enterprise/platform-safety-boundary.md):

- **W2 — no PII/secret *egress* control.** The guard denies binary exfil channels (`scp`/`sftp`/`curl --upload`/`nc`/`rclone`/`mail`) but an interpreter (`python -c`, `node -e`) can open a socket and exfiltrate with no command signature.
- **W3 — the guard only sees Bash-family tools.** Its PreToolUse matcher is `Bash|Write|Edit|NotebookEdit`; any **MCP / integration tool** call hits the `*) allow` branch and bypasses the entire deny-matrix (deploy, delete, exfiltrate — invisible to the guard).

**Goal:** move W2/W3 from *honestly-disclosed-open* toward *closed-or-verified*, by (a) **gating what is gateable in-kit** — MCP tool capabilities — and (b) **making verifiable** the platform controls the kit can only reference (egress allowlist, sandboxed FS, scoped tokens, separate prod creds), **without ever fake-enforcing** what a shell guard cannot.

**Method:** each sub-slice runs the kit's own loop (brainstorm → spec → plan → subagent build → independent review → **human ratification** → merge). Governing-surface and guard changes get the **security-owner lens**. Analysis runs that *inform* a fix are scheduled immediately before it; the arc closes by **re-running the guard red-team + the W2/W3 lens** (A9).

---

## The honesty invariant (the whole point)

The kit will **gate what's gateable** (MCP capabilities), **make verifiable** the platform controls (egress / sandbox / tokens declared + wired), and **keep stating** that the enforcement boundary is platform-owned. **No green check will ever imply containment a shell can't deliver** — the exact false-assurance the Slice 9 arc closed. A deny-list over a Turing-complete interpreter cannot contain a determined agent; that truth stays in `platform-safety-boundary.md` throughout.

## Versioning stance (the fork, decided at scoping)

Containment (egress / sandbox / tokens) is **inherently environment-specific** — not every project has a network surface. **Decision: keep it MINOR.** Containment checks are **first-class but conditional** (bind for deployable / regulated / networked projects; **N/A-with-reason** otherwise), mirroring 9j's honest-demote of a11y/load/eval. The MCP capability gate is a **new in-kit control** (additive). No new *universal* required gate is introduced, so the arc stays MINOR (2.40.0+). Promoting containment to a universal required gate (a clean **3.0.0**) is left as a **future deliberate decision**, not taken here.

---

## The stepped plan

Legend: **B** = build slice (loop pass) · **A** = analysis run (no production change; produces a findings artifact).

| Step | Type | What | Ver | Status |
|------|:----:|------|:---:|--------|
| **A8** | A | **MCP / egress attack-surface map** — enumerate which MCP tool families bypass the `Bash`-only guard, and the interpreter-exfil tail, so 11a/11b close a *real enumerated list* (not a guess). Mirrors how A2 aimed 9b. Artifact under `superpowers/reviews/`. | — | ✅ done (#46) — 10-class taxonomy; W3 gateable in-kit, W2 interpreter-tail platform-owned |
| **11a** | B | **MCP capability gate** (closes W3) — extend the Claude PreToolUse matcher to `mcp__.*`; `guard-core` checks each MCP call against a per-project **capability allowlist** declared at Inception (**deny-by-default** for un-allowlisted destructive/egress capability families); define a runtime-agnostic **`mcp-policy` contract** a second runtime can consume (the same honest portability model as the guard core); conformance asserts an un-allowlisted MCP tool is denied. **Control-plane `cp`** (guard + settings matcher); security-owner lens. | MINOR | ✅ shipped v2.40.0 — `guard_check_mcp` fail-closed, `.claude/mcp-policy.json` (empty-allow, protected), `kit-guard mcp` portable contract, `mcp-policy.sh` CI-gated |
| **11b** | B | **Egress-allowlist reference + conformance** (the honest W2) — ship a **default-deny network-egress reference** (k8s `NetworkPolicy` + a proxy/cloud pattern, per deploy target); add `conformance/egress-policy.sh` — three-state (declared/wired → PASS · absent → UNVERIFIED/FAIL by posture), conditional on a network surface. **Not** an in-process egress guard. Crosswalk egress row Org-owned → **Kit-assisted**. | MINOR | ✅ shipped v2.41.0 — `egress-policy.sh` three-state declared+attested check, `egress-control.md` reference, RUNBOOK attestation line, crosswalk Org-owned → Kit-assisted |
| **11c** | B | **Sandbox + scoped-credential references + conformance** — reference configs for a **read-only / sandboxed filesystem** (devcontainer / compose read-only mounts), **scoped short-lived tokens** (OIDC→role, break-glass), and **separate prod credentials**; add `conformance/containment-ready.sh` (a checklist + script, conditional three-state) that a project's containment posture is declared. Formalizes platform controls #2/#3/#4 from `platform-safety-boundary.md`. | MINOR | ✅ shipped v2.42.0 — `containment-ready.sh` three-aspect declared+attested check, `containment.md` reference, RUNBOOK attestation lines, crosswalk Org-owned → Kit-assisted |
| **11d** | B | **Honesty & assurance restatement** — update `enterprise/platform-safety-boundary.md`, the compliance crosswalk (egress/sandbox/token rows Org-owned → **Kit-assisted** where now provided + verified; the MCP capability gate → **Kit-enforced**), `enterprise/EXEC-BRIEF.md`, `DEVELOPMENT-PROCESS.md` §13, and `conformance/audit-evidence-checklist.md` — reflect the new coverage **without overclaiming** (the boundary is still platform-enforced; the kit now provides + verifies-wired + gates MCP capabilities). | MINOR | ✅ shipped v2.43.0 — narratives reconciled to post-arc reality (MCP gate Kit-enforced; #1-4 Kit-assisted; no overclaim), `assurance-tiers.sh` drift-guard regression-locks tiers, honor-based-date note |
| **A9** | A | **Re-run the guard red-team + the W2/W3 lens** — adversarially re-test the MCP gate (un-allowlisted MCP tool families, capability spoofing) and confirm the egress/containment conformance is honest (UNVERIFIED, never false-pass); verify W2/W3 moved from HIGH-open to closed-or-honestly-bounded. **This is the arc's exit gate.** | — | pending |

Targets ≈ **v2.40.0 → v2.44.0**.

---

## Why this order

1. **A8 aims the build** — A2→9b taught us to red-team before hardening so the fix closes an enumerated list, not a guess.
2. **11a first — it's the real win.** MCP capability gating is the one W3-class gap the kit can genuinely *enforce* (the Claude PreToolUse hook already receives MCP tool calls). Highest value, no honesty cost.
3. **11b/c provide + verify, don't fake.** The W2-class controls (egress / sandbox / tokens) are platform-enforced; the kit ships the reference and *verifies it's wired* (three-state UNVERIFIED where it can't reach the platform) — the SBOM / branch-protection model, not an in-process egress guard.
4. **11d re-states honesty once the coverage exists** — only after the controls are real do the crosswalk responsibility tiers move (Org-owned → Kit-assisted / Kit-enforced), so the docs never run ahead of the code.
5. **A9 closes the loop** — re-run the red-team that opened the question, proving the gap moved.

## Tracking
- Each step lands as its own PR, ratified by the maintainer, then this table's Status updates.
- W3 → 11a; W2 → 11b (egress) + 11c (sandbox/tokens), both honest-boundary-preserving.
- The arc is **not** done until A9 shows the MCP gate holds and the containment conformance is honest.

---

**Created:** 2026-06-10 · **Owner:** kit maintainer (ratifier) · **Status:** approved-pending → A8 on go.
