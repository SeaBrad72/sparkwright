# Design — Slice 7d: Work-Tracking Adapter Guidance

**Date:** 2026-06-08
**Status:** Approved (design) — pending spec review
**Author:** Bradley James + agent
**Roadmap:** Fourth sub-slice of Slice 7. Closes audit gap G9 (work-tracking has no per-tracker mapping guidance; ADO/GitLab not named). Plan: `~/.claude/plans/drifting-stirring-thunder.md` §7d.

---

## 1. Goal

Lift the kit's named backlog backends from **"named but figure-it-out-yourself"** to **"documented adapters with a concrete mapping recipe."** Today `DEVELOPMENT-PROCESS.md` §6 names four backends and asserts an adapter "must satisfy the contract" but never shows *how* any tracker maps to it. This slice writes that mapping, adds **Azure DevOps** and **GitLab** to the named set, and locks the named set / incept flag / guide against drift — **guidance only, no integration code.**

## 2. Decisions

- **Named set (six engineering work-queues):** `BACKLOG.md` (default, scaffolded) · GitHub Issues+Projects · Jira (Atlassian) · **Azure DevOps Boards** (new) · Linear · **GitLab Issues/Boards** (new). General PM tools (Asana/Monday/ClickUp) are **deliberately excluded** — they lack a race-safe atomic-claim primitive and native PR/commit linkage, so naming them would imply a parity they don't have; the generic recipe covers them if an adopter must.
- **One guide, contract-anchored, single template per tracker.** A new `docs/work-tracking/adapters.md`. Every tracker is mapped against the *same fixed template* derived from the §6 contract, so the guide teaches a reusable pattern, not tool trivia.
- **"Bring your own tracker" recipe** keeps the set open-ended (not a closed directory).
- **Consistency lock:** a new `conformance/backlog-adapters.sh` asserts the three surfaces agree — the `incept.sh --backlog` accepted set, the §6 named set, and the guide's tracker sections — so "named ≠ supported" drift cannot recur.
- **No integration code.** Flag parsing extends to record the choice; only `BACKLOG.md` is scaffolded (unchanged behavior). MINOR → **2.16.0**.

## 3. Deliverables

| Part | Files |
|------|-------|
| Mapping guide | `docs/work-tracking/adapters.md` (new) |
| Contract surface | `DEVELOPMENT-PROCESS.md` §6 (extend backend table + point at guide) |
| Bootstrap | `scripts/incept.sh` (`--backlog` accepted set + guide pointer in the non-md note) |
| Project config | `templates/PROJECT-CLAUDE-TEMPLATE.md` §3 (backlog-backend line → add ADO/GitLab + guide link) |
| Conformance | `conformance/backlog-adapters.sh` (new, drift lock); `conformance/README.md` (list it) |
| Meta | `VERSION` 2.16.0; `CHANGELOG.md`; `docs/ROADMAP-KIT.md` (7d row) |

## 4. Detailed design

### 4.1 The mapping guide — `docs/work-tracking/adapters.md`
Opens by restating the §6 contract it serves (states · required fields · atomic claim) and that it is **guidance, not integration code**. Then one section per named tracker, each following a fixed sub-template:

- **State map** — the tracker's native statuses → `Backlog → Ready → In Progress → In Review → Released → Done` (+ `Blocked`).
- **Field map** — `title · intent · acceptance criteria · size · risk/complexity · owner · links (spec/PR/milestone)` → the tracker's fields / labels / custom fields.
- **Atomic claim** — the exact mechanism that makes "enter In Progress" a race-safe single-owner change (the multi-agent requirement).
- **Fit notes** — honest caveats / what's lossy.

Trackers covered (the worked content the plan will fill verbatim):
1. **`BACKLOG.md`** — the reference: states are headings; fields are table columns; atomic claim = the move-to-In-Progress commit (git is the lock). The baseline every other adapter is measured against.
2. **GitHub Issues + Projects** — Project board columns = states; labels/custom fields = fields; atomic claim = assignee + column move (single-assignee convention).
3. **Jira** — workflow statuses = states; standard + custom fields; atomic claim = assignee + transition (workflow guard / condition).
4. **Azure DevOps Boards** — Board columns / `State` field; Area/Iteration + fields; atomic claim = `Assigned To` + State change; native branch/PR linking.
5. **Linear** — workflow states; properties/labels; atomic claim = assignee + state; GitHub/GitLab sync for links.
6. **GitLab Issues/Boards** — board lists / labels-as-state; issue fields + labels; atomic claim = assignee + label move; native MR/commit linking.
7. **Bring your own tracker** — the generic recipe: satisfy the three contract points; if your tool lacks a race-safe claim, document the compensating convention (e.g. single-assignee + a short claim TTL) and its risk.

### 4.2 Contract surface — `DEVELOPMENT-PROCESS.md` §6
Extend the backend table to the six named trackers (add ADO + GitLab rows) and add a sentence pointing at `docs/work-tracking/adapters.md` for the per-tracker mapping. The §6 **contract remains the authority**; the guide is the *how*. No contract change (states/fields/claim unchanged).

### 4.3 Bootstrap — `scripts/incept.sh`
- Extend the `--backlog` accepted set from `md|github|linear|jira` to `md|github|jira|ado|linear|gitlab`; update the usage string and the interactive prompt.
- Behavior unchanged: `md` scaffolds `BACKLOG.md`; any other value records the choice and prints the existing "declare it in CLAUDE.md §3" note, now extended with "→ see `docs/work-tracking/adapters.md`."
- No integration code; the script still refuses to run if already incepted.

### 4.4 Project config — `templates/PROJECT-CLAUDE-TEMPLATE.md` §3
Update the backlog-backend line (currently `[\`BACKLOG.md\` / GitHub Issues+Projects / Linear / Jira]`) to include Azure DevOps and GitLab, and append a pointer: "see `docs/work-tracking/adapters.md` for the mapping."

### 4.5 Conformance — `conformance/backlog-adapters.sh`
A small POSIX `sh` drift lock. Defines the canonical named set once and asserts all three surfaces contain exactly it:
- the `--backlog` accepted set parsed from `scripts/incept.sh`,
- the named backends in `DEVELOPMENT-PROCESS.md` §6,
- the per-tracker section headings in `docs/work-tracking/adapters.md`.
Fail-closed (exit 1) if any surface is missing a named tracker or names one the others don't. Stack-neutral, zero-dependency. Listed in `conformance/README.md`. (Implementation detail — exact match strategy — settled in the plan; the principle is: one source of truth, three surfaces must agree.)

## 5. Validation / testing
- `sh conformance/check-links.sh` → 0 (new guide + all cross-links resolve).
- `sh conformance/backlog-adapters.sh` → 0 (the three surfaces agree on the six-tracker set); plus a **negative test** in the plan (drop a tracker from one surface → must FAIL exit 1), so the lock is proven non-vacuous.
- `sh conformance/profile-completeness.sh`, `agent-autonomy.sh`, `ci-gates.sh` ×10, `container-supply-chain.sh` → green (no regression; this slice touches none of those domains).
- Manual: a non-md `incept.sh --backlog jira` run records the choice and points at the guide; the guide lets a reader map Jira to the contract without external docs.
- Kit CI green.

## 6. Risks & mitigations
- **Guide drifts from the named set / flag.** Mitigation: `backlog-adapters.sh` is the lock; it fails CI if they diverge (the slice eats its own dog food — the bug it fixes is "named ≠ supported").
- **Implying PM-tool parity.** Mitigation: PM tools excluded from the named set; the generic recipe covers them with explicit caveats.
- **Scope creep into integration code.** Mitigation: guidance only; `incept.sh` change is flag-parsing + a doc pointer, no API calls.
- **Mapping inaccuracy for a tracker.** Mitigation: each map is contract-anchored (same three points) and review-gated; fit notes name what's lossy rather than overclaiming.

## 7. Out of scope
- Reference adapter **code** / API integration for any tracker (guidance only).
- Changing the §6 **contract** (states/fields/atomic-claim model) — unchanged.
- Auto-provisioning or auto-syncing a tracker at Inception.
- General PM tools (Asana/Monday/ClickUp) in the named set — covered only by the generic recipe.

## 8. Definition of Done
- `docs/work-tracking/adapters.md` ships: contract restatement + six tracker maps (each with state/field/claim/fit) + bring-your-own recipe.
- §6 names the six backends and points at the guide; contract unchanged.
- `incept.sh --backlog` accepts the six; scaffolds only `md`; non-md note points at the guide.
- `PROJECT-CLAUDE-TEMPLATE.md` §3 updated (ADO/GitLab + guide link).
- `conformance/backlog-adapters.sh` present, fail-closed, drift-locks the three surfaces; negative test proves it; listed in `conformance/README.md`.
- All conformance green; `VERSION` 2.16.0; CHANGELOG + ROADMAP (7d).
- Feature branch → PR → **human ratification** (governing-doc change → Security-Owner lens). Agent never self-merges.
