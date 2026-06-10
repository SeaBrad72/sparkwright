# Slice 9h — Hosted-Tracker Bootstrap (design)

**Date:** 2026-06-10 · **Arc:** Slice 9, Tier 2 (R8) · **Version target:** MINOR → **v2.37.0**
**Input:** the review's R8 finding — the kit names hosted trackers and maps them in `docs/work-tracking/adapters.md`, but `incept --backlog jira` only prints a one-line note (no concrete setup), and **nothing verifies** a configured tracker actually satisfies the §6 work-item contract. The non-obvious, load-bearing step — Jira's **"Only Assignee" transition condition** that turns claiming into a real server-enforced single-owner change — is buried in prose.

## Scope (ratified at brainstorm)
Make hosted-tracker adoption concrete and checkable: `incept` emits a setup artifact for the chosen backend (a deep `JIRA-SETUP.md`, a short stub for the convention-tier trackers), and a new three-state `tracker-contract.sh` verifies a live Jira against §6 (with the kit's UNVERIFIED-not-false-pass honesty). Templates + one conformance check + an incept arm. No API client shipped.

## Components

### 1. `scripts/incept.sh` — emit a setup artifact per hosted choice
The `case "$BACKLOG"` block (currently `md` → BACKLOG.md, `*` → a note) gains real arms:
- **`jira`** → copy `templates/JIRA-SETUP-TEMPLATE.md` → `JIRA-SETUP.md` (stamp `[Project Name]`); note points at `tracker-contract.sh` to verify.
- **`github|ado|linear|gitlab`** → copy `templates/TRACKER-SETUP-TEMPLATE.md` → `TRACKER-SETUP.md` (stamp project name + the chosen backend); note points at `adapters.md`.
- **`md`** → `BACKLOG.md` (unchanged).
`incept.sh` is agent-editable (not control-plane). The `md` bootstrap path the CI exercises is untouched.

### 2. `templates/JIRA-SETUP-TEMPLATE.md` (new) — the deep, copy-pasteable guide
- **6 workflow statuses** mapped to §6: `Backlog → Ready → In Progress → In Review → Released → Done` (+ `Blocked`).
- **Custom fields:** a **Size** select and a **Risk** field — with the explicit "do **not** use Story Points as size" warning (§1 forbids estimation-as-forecast).
- **The "Only Assignee" transition condition** — step-by-step (Project settings → Workflow → the In-Progress transition → add the *Only Assignee* condition). This is what makes Jira the only **structural-tier** hosted claim; the template states plainly that without it you are on the convention tier.
- **Dev-panel wiring** for branch/commit/PR links; a closing **"verify it: `sh conformance/tracker-contract.sh`"** pointer.

### 3. `templates/TRACKER-SETUP-TEMPLATE.md` (new) — convention-tier stub
Short and honest for github/ado/linear/gitlab: board columns = the six §6 states; claim = **assign-when-empty + re-read-after-write** (convention tier, not server-enforced); `→ docs/work-tracking/adapters.md §<backend>` for the full map. A `[BACKEND]` placeholder incept stamps.

### 4. `conformance/tracker-contract.sh` (new) — three-state Jira verifier
Mirrors `branch-protection.sh`'s honesty exactly:
- **`--selftest`** → runs the contract-assertion logic against two recorded fixtures (a conformant Jira-export blob + a gap blob missing a status/field) → proves the LOGIC in CI without a live Jira. Exit 0.
- **Live** (when `JIRA_BASE_URL` + `JIRA_EMAIL` + `JIRA_TOKEN` are set): `curl` the REST API for statuses + fields, assert the **6 statuses** and the **Size/Risk fields** exist → PASS/FAIL. The **Only-Assignee transition condition** is reported as **ATTESTED, not auto-verified** — basic REST cannot cheaply introspect workflow conditions, and the kit will not fake what it cannot check (`green ≠ verified`).
- **No creds** → **UNVERIFIED** (exit 2) — never a silent pass.
- Zero-dependency core: the contract check is **grep-based** (each required status/field name must appear in the JSON), so neither `--selftest` nor the live path needs `jq`. `curl` is used only on the live path. POSIX sh, `dash -n` clean.

### 5. Docs + wiring
- `docs/work-tracking/adapters.md` Jira section gains a one-line pointer to `JIRA-SETUP.md` (emitted at incept) and `tracker-contract.sh` (to verify). §6 gains the same pointer where it references the adapter guide.
- `conformance/README.md` index row.
- `.github/workflows/ci.yml`: run `tracker-contract.sh --selftest` (the live path is UNVERIFIED in kit CI — no Jira — so only the selftest runs). **One control-plane `cp`.**
- `VERSION` 2.37.0; CHANGELOG; roadmap 9h → shipped.

## Files

| File | Change | Owner |
|------|--------|-------|
| `scripts/incept.sh` | `case "$BACKLOG"` arms: jira → JIRA-SETUP.md, hosted → TRACKER-SETUP.md | agent |
| `templates/JIRA-SETUP-TEMPLATE.md` | **New** — deep setup (statuses, fields, Only-Assignee condition) | agent |
| `templates/TRACKER-SETUP-TEMPLATE.md` | **New** — convention-tier stub | agent |
| `conformance/tracker-contract.sh` | **New** — three-state Jira verifier + `--selftest` | agent |
| `docs/work-tracking/adapters.md` | Jira section → JIRA-SETUP + verifier pointer | agent |
| `conformance/README.md` | index row | agent |
| `.github/workflows/ci.yml` | `tracker-contract.sh --selftest` step | **human `cp`** |
| `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md` | 2.37.0; 9h → shipped | agent |

## Verification
- `sh conformance/tracker-contract.sh --selftest` → PASS (conformant fixture passes, gap fixture fails). `dash -n` clean.
- `sh conformance/tracker-contract.sh` with no creds → UNVERIFIED, exit 2 (honest, not a pass).
- `sh conformance/backlog-adapters.sh` → still green (the named-backend set is unchanged).
- A temp bootstrap with `--backlog jira` writes `JIRA-SETUP.md`; with `--backlog github` writes `TRACKER-SETUP.md`; with `--backlog md` writes `BACKLOG.md` (unchanged).
- `sh conformance/check-links.sh` + `sh conformance/verify.sh` → green.
- Anonymization: generic ([[kit-anonymization]]); the templates use placeholders, not a real Jira URL/org.

## Out of scope / deferred
- **A shipped Jira API client** — the kit ships guidance + a `curl`-based verifier, not an integration library.
- **Live verifiers for github/ado/linear/gitlab** — they are convention-tier; the claim is enforced by runtime assign-when-empty + re-read, not by server config, so there is nothing static to verify. Their stub documents the convention.
- **Auto-creating the Jira workflow** — the adopter configures it (the kit guides + verifies); the kit does not mutate a live Jira.
- **Introspecting the Only-Assignee condition over REST** — reported as attested, not auto-verified (a deeper workflow-scheme API call is an adopter-side enhancement).

## Known implications
- `incept --backlog jira` now produces a real, project-stamped runbook for standing up a contract-conformant Jira, and the adopter can prove the mechanically-checkable parts with one command.
- The kit stays honest about claim strength: structural (Jira, once configured) vs convention (the rest), and about what the verifier does and does not prove (states/fields verified live; the transition condition attested).
- A future deeper verifier (workflow-scheme introspection, or live convention-tier re-read demos) extends `tracker-contract.sh` without changing the §6 contract.
