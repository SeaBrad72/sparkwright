# E4a′ — Token-scope static gate: OIDC discipline on the shipped workflows

**Status:** Design approved 2026-06-23 (owner-ratified). E4a′ — completes the 4-platform-controls coverage.
**Tracked here** (not `docs/superpowers/specs/`) per the C7 lesson.

---

## 0. Context

E4 (containment) ships the 4 platform controls. E4a (v3.42.0) proved **three behaviourally**
(FS-scope, egress, caps — by booting the sandbox). The remaining two — **scoped-tokens (§10 #3)**
and **prod-cred SoD (§10 #4)** — are **cloud-IAM-owned**: the kit can't boot an adopter's IAM to
prove a token actually expires or that a dev token can't touch prod. Today they are RUNBOOK
attestation only (`containment-ready.sh` reads a `Scoped tokens:` / `Prod credentials:` line).

But the kit *can* statically verify the **workflows it ships** embody the OIDC discipline the
attestation claims. E4a′ adds `conformance/token-scope.sh` — a structural gate (mirroring
`provenance-precondition.sh`) that the reference + kit workflows scope OIDC tokens to the job that
needs them and carry **no long-lived cloud credentials**.

**Honest boundary (unchanged from E4a's "prove-what-we-ship"):** this is a **static structural**
check on shipped workflow YAML — not a behavioural proof of the adopter's cloud IAM. The adopter's
real token TTL / role scoping / prod-cred separation stay platform-owned and RUNBOOK-attested
(`containment-ready.sh` is **unchanged**). E4a′ closes the gap "nothing checks the shipped
workflow's token scoping" — it does not claim to enforce cloud IAM.

This completes the platform-controls coverage: **3 proven behaviourally (E4a) + token-scope proven
structurally (E4a′)**; prod-cred SoD's deployment-specific separation remains attestation (no honest
static signal exists on a stack-neutral template).

---

## 1. Owner-ratified decisions

1. **Two checked properties** (below), prod-cred SoD stays RUNBOOK attestation.
2. **Scope:** `profiles/*/ci.yml` (the adopter reference) **+ `.github/workflows/*.yml`** (the kit
   self-checks — defense-in-depth on the kit's own CI).
3. **Registered headline claim** `token-scope` (claims **26 → 27**), with `--selftest`, wired into
   `verify.sh` + `ci.yml` — consistent with `provenance-precondition.sh`.

---

## 2. The check — `conformance/token-scope.sh`

For each workflow file, two properties:

### Property 1 — OIDC token-scope (least privilege)
The **top-level** (column-0) `permissions:` block must not grant `id-token: write` nor `write-all`.
`id-token: write` is legitimate **only inside a job's** `permissions:` (the reference's `provenance`
/ `image-provenance` jobs hold it job-scoped). A workflow-level grant lets *every* job mint OIDC
tokens — a privilege over-grant.

Parse: locate the col-0 `permissions:` line; the block is the subsequent indented lines until the
next col-0 key (`jobs:`, `on:`, `concurrency:`, …). If that block contains `id-token:` with `write`,
or a top-level `permissions: write-all` (block or inline), FAIL. Job-level (indented) permissions
blocks are never matched. Inline form `permissions: { id-token: write }` on the top-level line is
also caught.

### Property 2 — no long-lived cloud credentials
A **curated** forbidden list of long-lived cloud-credential identifiers anywhere in the file:
`AWS_SECRET_ACCESS_KEY`, `AWS_ACCESS_KEY_ID`, `AZURE_CLIENT_SECRET`, `GCP_SA_KEY`,
`GOOGLE_APPLICATION_CREDENTIALS`. These are static keys that OIDC federation exists to eliminate.

Curated to avoid false positives: `secrets.GITHUB_TOKEN` (built-in, short-lived) and OIDC role
identifiers like `AWS_ROLE_ARN` / `role-to-assume` (an ARN is not a credential) are **not** forbidden.

### Result model
Binary, mirroring `provenance-precondition.sh`: exit 0 = all scanned files clean (or N/A — no
workflow files found); exit 1 = a violation (with the offending file + line). `--selftest` fixtures:

- **clean** (top-level `permissions: contents: read`, a job-scoped `id-token: write`, no static keys) → PASS
- **top-level `id-token: write`** → FAIL
- **top-level `permissions: write-all`** → FAIL
- **`AWS_SECRET_ACCESS_KEY` present** → FAIL
- **job-scoped id-token only** → PASS (the discriminator: job-level is fine, top-level is not)
- **no permissions / no workflows** → PASS / N/A

### Day-one safety (verified)
Kit workflows + all 7 profiles already satisfy both properties (no top-level id-token/write-all;
`id-token: write` is job-scoped in the provenance jobs only; zero static cloud secrets). The gate
fires only on a regression — it reds nothing on landing.

---

## 3. Scope, claim, wiring

- **Scans** `profiles/*/ci.yml` + `.github/workflows/*.yml`.
- **Claim** `token-scope` in `claims.tsv` (verifier `sh conformance/token-scope.sh`); id added to
  `REQUIRED_IDS` in `claims-registry.sh` → claims **26 → 27**.
- **Wired** into `verify.sh` (a `check control` line) + a `ci.yml` `--selftest` step (so
  `ci-selftest-coverage` requires it).
- **No export-carve needed.** `token-scope.sh` scans *whatever workflow files exist*; it never
  *requires* an export-ignored path (unlike `feature-flags-wired` which greps `golden-path.yml`). In
  an adopter export it scans `profiles/<stack>/ci.yml` + `.github/workflows/ci.yml` (all present),
  passes, and the export's `claims-registry` stays green. (Verified in the plan's clone+export dry-run.)

---

## 4. Footprint

- **Control-plane → AMBER mechanic** (flat `/tmp/e4ap_scratch/` → human-run `apply.py` →
  **security-review-of-scratch MANDATORY**): new `conformance/token-scope.sh`, `claims.tsv` row,
  `REQUIRED_IDS` in `claims-registry.sh`, `verify.sh` line, `ci.yml` selftest step.
- **Agent-editable on-branch:** a `docs/operations/containment.md` §2 note (the static gate
  complements the RUNBOOK attestation; cloud-IAM enforcement stays platform-owned), VERSION 3.44.0,
  CHANGELOG, README badge, `docs/ROADMAP-KIT.md` (E4a′ ✅ + decomposition).
- **Mirrors `provenance-precondition.sh`** (proven structural-lock pattern). Fully static — no docker;
  local red-green is fast.
- **apply.py invariants:** explicit ROOT, idempotent, atomic, fail-loud anchors, mode-preserve 0755.

---

## 5. Verification / Definition of Done

- `token-scope.sh --selftest` green (all fixtures incl. the job-vs-top-level discriminator + write-all + static-secret).
- `token-scope.sh` green on the real tree (kit workflows + 7 profiles clean).
- claim registered; `claims-registry` green at 27; `ci-selftest-coverage` green.
- `verify.sh --require` green; `doctor` Overall PASS.
- Clone + adopter-export dry-run: the exported tree's `claims-registry` passes (no carve needed, confirmed).
- builder ≠ reviewer + security-review-of-scratch both APPROVE (nits folded in scratch).
- Merge landed verified; VERSION/CHANGELOG/README/ROADMAP updated.

---

## 6. E4 decomposition (updated)

| Slice | Status |
|---|---|
| E4a — boot+probe sandbox (FS/egress/caps PROVEN) | ✅ v3.42.0 |
| E4b — image-vuln CVE gate | ✅ v3.43.0 |
| **E4a′ — token-scope static gate (this)** | **building** — completes the 4-platform-controls coverage |
| E4c — DAST / runtime-security reference | next candidates |
| E4d — cost-ceiling / runaway kill-switch | **deferred to land with E3** (provable core needs the orchestration loop; cost is platform-owned) |
| E4e — R2 bot-identity ratification gate | |
| E4f — G8 per-segment guard | |
| /work-mount reference fix (E4a follow-up) | |

E3 (orchestration) builds after E4. Order: E2 ✓ → E4 → E3 → E1/E5/E6.
