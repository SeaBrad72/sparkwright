# Design — Slice 8c: DR / backup-restore drill + BIA-at-Inception

**Date:** 2026-06-09
**Status:** Approved (design) — pending spec review
**Author:** Bradley James + agent
**Roadmap:** Third sub-slice of Slice 8 (continuity & safe-delivery hardening). Arc-of-record: `docs/superpowers/ideation/2026-06-08-delivery-safety-continuity-gaps.md`. Closes gap **A2** (DR is prose-only — no reference, no drill enforcement, no criticality tiering, no BIA). The continuity centerpiece for the regulated, customer+affiliate-data adopter. NIST SP 800-34 anchor.

---

## 1. Goal

Turn disaster recovery from an unverified claim into a provable capability. `DEVELOPMENT-STANDARDS.md` §10 says "verify restore at least once" and `DEVELOPMENT-PROCESS.md` §15 already lists "Backup-restore verification (prove DR actually works)" as recurring work — but there is **no reference** for how to run a restore drill, **no conformance** proving one happened, **no criticality tiering** of RTO/RPO, and **no Business Impact Analysis**. 8c closes all four, keeping everything conditional on the project actually handling persistent data. MINOR → **2.21.0**.

## 2. Decisions

- **BIA = Inception step + template, enforced later by DR conformance** (the chosen option). The BIA is a *recommended* Inception step producing per-tier RTO/RPO; `inception-done.sh` is **unchanged** (no hard Inception gate — avoids forcing a heavyweight artifact on a project before it runs, and avoids branching the Inception gate). Enforcement lives in the **DR conformance** (checklist + script), conditional on the project handling persistent data, gating at Review / pre-launch / recurring — where the kit's other conformance gates sit.
- **Checklist + companion script** (the 8b pattern). Manual rows carry the judgment (backups exist; the drill *actually restored data*; RTO/RPO *actuals met* the targets); the script auto-verifies the documented floor (a BIA artifact exists; RUNBOOK §6 DR fields are filled, not placeholder; a restore-drill date is recorded).
- **Conditional + fail-closed**, mirroring `deployable-ready.sh` / `container-supply-chain.sh`. Detection of a **persistent-data surface**; no surface → N/A skip-pass (stateless tools/CLIs/libraries are not nagged about backups). Skip-passes at the kit root.
- **Anti-false-assurance is a contract requirement** (carried from 8b). A recorded "Restore verified: 2026-06-01" does **not** prove the restore succeeded or met RTO. So `dr-ready.sh`'s success output self-discloses it checks the drill was **recorded**, not that it **worked**; the checklist holds "drill actually restored data + met RTO" as **Manual** rows, signed by the on-call/operator. The checklist carries the bold "a green script is necessary, not sufficient" callout and *(documented)* / *(tested / verified)* row labels. A **`--selftest`** fixture battery (incl. a negative stateless fixture) regression-locks the positive path in kit CI.
- **`N/A` is non-absolving and the script is escalate-only** (added after design review — the directional-safety fix). For a *continuity* gate the dangerous error is a **false negative**: a real data project whose surface the detector misses prints `N/A` and ships with unproven DR. Conservative detection (needed to avoid nagging stateless tools) *increases* that risk, so it must be paired with a non-absolving `N/A`: the script may only ever **escalate** (detect → require), never **exempt**. Its `N/A` output **self-incriminates** — "if this project handles durable data, this N/A is WRONG — apply `dr-readiness.md` manually." The **BIA at Inception (a human deciding criticality) is the primary path**; the script is a backstop. The checklist intro states the `N/A` is advisory, and the checklist — applied by a human — is the gate of record.
- **DR-readiness is anchored to the Definition of Done** (added after design review — the enforcement fix). BIA-as-Inception-prompt is only real if it is backstopped by a gate nothing ships past. The kit's gates sit at Review/Release/recurring (Inception is deliberately light), so enforcement belongs in the **Definition of Done**, not a hard Inception gate: add "**DR proven for data services**" to the DoD **Production** line (`CLAUDE.md`). A data service cannot be "done" without a passed DR-readiness check.
- **Framework anchor, not a crosswalk** — one-line **NIST SP 800-34** (contingency planning) nod in the drill reference + the checklist, per the arc's fold-in decision.
- **No new universally-required CI gate.** The 8 application gate-ids and §14 are unchanged. DR readiness is a conditional checklist/Review-style gate.

## 3. Deliverables

| # | File | Change |
|---|------|--------|
| A | `docs/continuity/backup-restore-drill.md` (new) | Stack-neutral restore-drill reference (the "how") |
| B | `templates/BIA-TEMPLATE.md` (new) | Business Impact Analysis template (criticality tiers + per-tier RTO/RPO) |
| C | `conformance/dr-readiness.md` (new) | Conditional DR-readiness checklist (Manual + Auto rows, callout, NIST 800-34 anchor) |
| D | `conformance/dr-ready.sh` (new) | Conditional, fail-closed companion script; scope-disclaiming output; `--selftest` |
| E | `DEVELOPMENT-STANDARDS.md` §10 | Tiered RTO/RPO (by data criticality, from the BIA); point at the BIA + drill reference |
| F | `templates/RUNBOOK-TEMPLATE.md` §6 | Per-tier RTO/RPO option; keep "Restore verified: [date]" |
| G | `START-HERE.md` §6 + Inception-Done | BIA as a recommended Inception step (conditional on data-handling); a conditional Inception-Done checklist line (not a script gate) |
| H | `DEVELOPMENT-PROCESS.md` §15 (recurring) + §7 (gates) | §15 item references the drill doc; §7 adds a conditional **DR readiness** gate (data services) |
| I | `conformance/README.md` + `audit-evidence-checklist.md` | Index the two checks; a DR-drill audit row |
| J | `.github/workflows/ci.yml` | `dr-ready.sh` present + N/A + `--selftest` (3 steps) |
| K | `CLAUDE.md` (DoD Production line) | Add "DR proven for data services (`conformance/dr-readiness.md`)" — anchors the DR-readiness gate to a checkpoint nothing ships past |
| Meta | `VERSION` 2.21.0 · `CHANGELOG.md` · `docs/ROADMAP-KIT.md` (8c row) |

## 4. Detailed design — `docs/continuity/backup-restore-drill.md`

Stack-neutral reference (peer of `docs/work-tracking/adapters.md`, `docs/adoption/brownfield.md`). Sections:
- **Purpose + NIST 800-34 anchor** + the **do-no-harm rule in bold:** *never drill against production — restore into an isolated environment.*
- **The drill, step by step:** pick a tier (from the BIA) → take/identify a backup → **restore to an isolated environment** → verify data integrity (row counts, checksums, a smoke query) → **measure RTO/RPO actuals** (time-to-restore; data-loss window) → compare to the tier's targets → **record date + result** in RUNBOOK §6 and the board (the §15 recurring item).
- **Tiering guidance** — tier by criticality from the BIA; the most critical tier drills most often.
- **Cadence** — at least once per project + on schedule (§15); pre-launch for a new data service.
- **What "passed" means** — data restored, integrity verified, RTO/RPO actuals within targets. Recording a date is the floor; a *passed* drill is the bar.

## 5. Detailed design — `templates/BIA-TEMPLATE.md`

House style = guidance blockquotes + `[...]` fill-ins (like the other templates). Sections: header (owner, date, review cadence); **data/service inventory**; **criticality classification** (e.g. Critical / Important / Deferrable) with the impact of loss; **per-tier RTO/RPO targets**; **dependencies** (upstream/downstream, third parties); **max tolerable downtime**; a note that the filled copy lives at `docs/continuity/BIA.md` and feeds RUNBOOK §6 + `dr-readiness.md`. One-line NIST 800-34 anchor.

## 6. Detailed design — `conformance/dr-readiness.md` + `conformance/dr-ready.sh`

### Checklist (`dr-readiness.md`)
Mirrors `definition-of-deployable.md`: intro (Checklist-type; conditional N/A for non-data projects; NIST 800-34 + §10 anchor), the bold **"a green script is necessary, not sufficient"** callout, `## How to use`, a blank table, a worked example, an N/A note. The intro **must** also state: *the script's `N/A` is advisory only — detection is conservative and can miss a data project; if this project handles durable data, this checklist applies regardless of what the script prints. The script escalates, never exempts.* Rows:

| # | Item | Check |
|---|------|-------|
| 1 | BIA done — data/services classified by criticality *(documented)* | **Auto:** `dr-ready.sh` (BIA artifact present) |
| 2 | Per-tier RTO/RPO defined (from the BIA) *(documented)* | **Auto:** `dr-ready.sh` (RUNBOOK §6 filled, not placeholder) |
| 3 | Automated backups configured for production data *(verified)* | Manual |
| 4 | Restore drill **run** — date recorded in RUNBOOK §6 *(documented)* | **Auto:** `dr-ready.sh` ("Restore verified" has a real value) |
| 5 | Restore drill **succeeded** — data actually restored, integrity verified *(verified)* | Manual |
| 6 | RTO/RPO **actuals met** the tier targets in the last drill *(verified)* | Manual |
| 7 | Backups stored durably + access-controlled (off-host/region) *(verified)* | Manual |
| 8 | Drill scheduled as recurring maintenance (§15) — untagged process item | Manual |

### Script (`dr-ready.sh`)
POSIX `sh`, `set -eu`, structured like `deployable-ready.sh`. Operates on a project dir (`DIR="${1:-.}"`).

**Persistent-data detection (the conditional trigger).** Data-handling if ANY of:
- `.env.example` declares a DB/connection URL var — `grep -Eiq 'DATABASE_URL|DB_URL|POSTGRES|MYSQL|MONGO|REDIS_URL|CONNECTION_STRING'`;
- a migrations/db directory exists — `prisma/`, `migrations/`, `db/migrate/`, `alembic/`;
- a compose file declares a database service — a `compose.yaml`/`docker-compose.yml` with `image: (postgres|mysql|mariadb|mongo|redis)`.
None → a **self-incriminating, non-absolving** N/A line, exit 0: `N/A: no persistent-data surface detected (no DB url / migrations dir / compose db) — skipping. WARNING: if this project handles durable data, this N/A is WRONG — detection is conservative; apply conformance/dr-readiness.md manually. This check escalates (detect → require); it never exempts a data project.` (The script can only add a requirement, never remove one; the BIA-at-Inception and the human-applied checklist are the real gate.)

**When data-handling, assert (fail-closed accumulator):**
1. A BIA artifact exists — `docs/continuity/BIA.md`.
2. `RUNBOOK.md` exists and has a **Disaster recovery** heading.
3. RUNBOOK §6 RTO/RPO are **filled, not placeholder** — the DR section does not still contain the template's `[< 24h default]` / `[< 4h default]`.
4. A **restore-drill date is recorded** — a "Restore verified:" line whose value is not the `[date]` placeholder.

Each miss → `FAIL <reason>` + remediation hint. Success → a **scope-disclaiming** line: `dr-ready: OK — DR is DOCUMENTED and a restore drill is RECORDED. NOTE: this does NOT verify the restore succeeded or met RTO/RPO — those are Manual rows in dr-readiness.md requiring on-call/operator evidence.`

**`--selftest`** fixtures (left in `mktemp`, no `rm -rf`):
- empty dir → N/A;
- stateless (no data signals) → N/A (anti-over-trigger);
- data (`.env.example` w/ `DATABASE_URL`) + `docs/continuity/BIA.md` + RUNBOOK with filled DR + a real "Restore verified: 2026-06-01" → OK;
- data + RUNBOOK "Restore verified: [date]" (placeholder) → FAIL;
- data + no `docs/continuity/BIA.md` → FAIL.

**Robustness (carried lessons):** anchored heading greps; current-shell `fail` accumulator (no subshell trap, 7d); leave fixtures (7e); `_`-prefixed helper params (8b review); explicit `exit $?` after the dispatch `case`; conservative detection + a negative fixture + an inline comment that the checklist is the gate of record (8b review).

## 7. Wiring detail

- **`START-HERE.md` §6** — add a bullet: "**Business continuity (data-handling projects)** — run a BIA (`templates/BIA-TEMPLATE.md` → `docs/continuity/BIA.md`); set per-tier RTO/RPO; schedule the restore drill (`docs/continuity/backup-restore-drill.md`)." **Inception-Done** — add a conditional checklist line: "- [ ] *(data-handling projects)* BIA done; per-tier RTO/RPO set; restore drill scheduled".
- **`DEVELOPMENT-STANDARDS.md` §10** — replace the single-default RPO/RTO bullet with tiering: "define RPO/RTO in the RUNBOOK (defaults RPO < 24h, RTO < 4h); **for multi-criticality systems, tier them by data criticality from the BIA** (`templates/BIA-TEMPLATE.md`). Prove restore with a drill (`docs/continuity/backup-restore-drill.md`); a recorded drill is the floor, a passed drill is the bar."
- **`templates/RUNBOOK-TEMPLATE.md` §6** — offer a per-tier RTO/RPO mini-table option; keep "Restore verified: [date]".
- **`DEVELOPMENT-PROCESS.md` §15** — the "Backup-restore verification" recurring bullet → append "(how: `docs/continuity/backup-restore-drill.md`)".
- **`DEVELOPMENT-PROCESS.md` §7** — add a conditional gate row after Definition of Deployable: `| **DR readiness** *(data services)* | Is DR provable — BIA done, RTO/RPO tiered, restore drill passed? (\`conformance/dr-readiness.md\`) | On-call / operator + reviewer |`; add "DR-readiness" to the conditional-gates sentence.
- **`conformance/README.md`** — two index rows (checklist → Review/recurring conditional; script → conditional on a data surface).
- **`audit-evidence-checklist.md`** — a row: `| DR drill · backup-restore | CC7.5, A1.2 / A.5.29, A.8.13 | BIA + RUNBOOK §6 + recorded drill date | **Auto (conditional):** \`sh conformance/dr-ready.sh\` | |` (after the existing RUNBOOK DR/rollback row).
- **`.github/workflows/ci.yml`** conformance job — three steps: checklist present; `dr-ready.sh` (N/A at root); `dr-ready.sh --selftest`.
- **`CLAUDE.md` DoD Production line** — append "· **DR proven for data services** (`conformance/dr-readiness.md`)" to: `**Production** — deployed · smoke-tested · no errors in logs · rollback path ready · monitoring/alerting on critical paths.` This makes a passed DR-readiness check part of "done" for any data service — the mandatory anchor that backstops the BIA-as-Inception-prompt. (STANDARDS §12 defers to `CLAUDE.md`, so no edit there.)

## 8. Validation / testing

- `sh conformance/dr-ready.sh` at kit root → `N/A …`, exit 0 (verify the root has no `.env.example` DB var / migrations dir / compose db service — re-check at build time).
- `sh conformance/dr-ready.sh --selftest` → all fixtures behave (N/A / N/A-stateless / OK / FAIL-placeholder / FAIL-no-BIA), exit 0.
- Scope-disclaimer wording present (grep-assert): "does NOT verify the restore succeeded or met RTO/RPO".
- Checklist callout present; `(documented)` / `(verified)` labels present.
- `sh conformance/check-links.sh` → 0 (new docs' refs resolve; §7/§10/§15/README/audit/START-HERE links valid).
- All other conformance green (no gate-id change); `sh -n` + `dash -n` clean on `dr-ready.sh`.
- Kit CI green (the three new steps pass).

## 9. Risks & mitigations

- **False assurance — a recorded drill date misread as "DR works."** Mitigation (contract): script self-discloses scope; checklist holds "restored + RTO met" as Manual; bold callout; grep-asserted wording. The on-call/operator signs the Manual rows.
- **Detection false-negative — the primary vulnerability** (a real data project the detector misses → `N/A` → DR never enforced → unprotected production data ships silently). For a continuity gate this is far worse than a false positive. Mitigation (now a contract requirement, §2/§6): the script is **escalate-only** and its `N/A` is **self-incriminating** ("if you handle durable data this N/A is WRONG — apply the checklist"); the **BIA-at-Inception** (human criticality call) is the primary path; and **DR-readiness is anchored to the Definition of Done** for data services, so the silent gap surfaces at a gate nothing ships past. Three detection triggers reduce the miss rate; the human checklist is the gate of record.
- **Persistent-data detection false-positive** (a stateless project with an incidental cache `REDIS_URL` gets nagged for a BIA). Lower-severity (annoyance, not danger). Mitigation: conservative triggers; an inline comment; the checklist can be marked N/A-with-reason by a reviewer; a negative selftest fixture; the checklist intro documents the cache-only edge ("if your only 'data' is ephemeral cache, mark N/A — no durable data to recover").
- **Inception step ignored** (no hard Inception gate). Mitigation (now explicit): enforcement is not at Inception — it is the DR-readiness check anchored to the **Definition of Done** for data services. Inception only prompts; "done" requires the proof. Consistent with the kit's gate-placement belief (gates at Review/Release/recurring, not Inception).
- **Subshell-loses-`fail` / guard-blocks-cleanup / param clobber.** Mitigations: current-shell accumulator (7d); leave fixtures (7e); `_`-prefixed params (8b).

## 10. Out of scope

- Resilience / chaos / load-soak verification — that is **8d**.
- Progressive-delivery reference + post-deploy smoke gate — **8e**.
- Right-to-erasure path testing / retention enforcement (privacy family, Org-owned boundary) — A4, not this slice.
- Any change to the 8 application CI gate-ids or §14.
- A hard `inception-done.sh` BIA gate (explicitly chosen against).
- Real backup tooling / cloud config (Org-owned; the kit standardizes the *practice and proof*, names tooling Org-owned).

## 11. Definition of Done

- `docs/continuity/backup-restore-drill.md` created (drill how-to, isolated-env do-no-harm rule, NIST 800-34 anchor).
- `templates/BIA-TEMPLATE.md` created (criticality tiers + per-tier RTO/RPO).
- `conformance/dr-readiness.md` (callout, Manual + Auto rows, worked example, N/A-is-advisory note) + `conformance/dr-ready.sh` (conditional, fail-closed, **escalate-only / self-incriminating N/A**, scope-disclaiming success, `--selftest`, dash-clean) created; the five fixture cases pass.
- §10 tiered RTO/RPO; RUNBOOK §6 per-tier option; START-HERE BIA step + conditional Inception-Done line; §15 references the drill; §7 conditional DR-readiness gate; **`CLAUDE.md` DoD Production line includes "DR proven for data services"**.
- **Directional-safety wording shipped + grep-asserted:** the script's N/A contains "if this project handles durable data, this N/A is WRONG"; the DoD Production line contains "DR proven for data services".
- `conformance/README.md` indexes both; `audit-evidence-checklist.md` DR-drill row; kit CI runs present + N/A + selftest.
- All conformance green; `check-links.sh` 0; no §14/gate-id change; anti-false-assurance wording shipped + grep-asserted.
- `VERSION` 2.21.0; CHANGELOG 2.21.0 entry; ROADMAP 8c row.
- Feature branch → PR → **human ratification** (governing-doc surface → **security-owner lens**, per §13/RBAC). Agent never self-merges.
