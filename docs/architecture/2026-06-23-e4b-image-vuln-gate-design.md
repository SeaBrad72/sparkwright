# E4b — Image-vuln gate: a Trivy CVE scan that actually gates (and is proven to)

**Status:** Design approved 2026-06-23 (owner-ratified). Second build slice of the E4 epic.
**Tracked here** (not `docs/superpowers/specs/`) per the C7 lesson — the superpowers spec path is
kit-gitignored; committed design docs live in `docs/architecture/`.

---

## 0. Context

E4 is the **containment** epic. E4a (v3.42.0) shipped the first *behavioural* containment proof
(boot the sandbox, probe FS-scope/egress/caps). E4b closes a named gap-assessment **blind spot:
"the SBOM enumerates, nothing gates."**

Today the reference CI (all 7 Dockerfile profiles) *builds* the image and runs `gate-image-sbom`
(`anchore/sbom-action` → *enumerates* packages into an SBOM artifact) — but **nothing scans the
built image for known CVEs or fails on them.** `gate-dep-scan` (npm audit / pip-audit) covers
*source* dependencies, not the OS packages + bundled libraries in the *built image*.
`conformance/container-supply-chain.sh` gates the *contract* (multi-stage, non-root, the
`gate-image-sbom` + `gate-image-provenance` ids, a digest-bound attestation) — never a CVE policy.

E4b adds a real **image-vuln gate** and — unlike the contract-only sbom/provenance gate-ids, which
`container-supply-chain.sh` checks *exist* but never *runs* — **proves it actually runs and
discriminates** in golden-path (the E-series "behaviour, not declaration" thesis; E4a's GREEN+RED
bar transferred to image scanning).

---

## 1. Owner-ratified decisions

1. **Scanner: Trivy.** Already a kit-known tool (the `terraform` profile uses `aquasecurity/trivy-action`); scans OS + language packages; ubiquitous.
2. **Fail-policy: fixable CRITICAL/HIGH.** `--severity CRITICAL,HIGH --ignore-unfixed --exit-code 1`. Gates *actionable* risk (a version bump exists); avoids unactionable noise from base-image CVEs with no upstream fix — the cry-wolf antipattern that gets gates disabled. Unfixed CVEs remain enumerated by the SBOM, not gated.
3. **Proven depth: behavioural + non-vacuous RED.** golden-path scans the reference image (must PASS clean) *and* a pinned known-vulnerable image (must FAIL) — proving the gate discriminates, not vacuously passes.
4. **Breadth: all 7 Dockerfile profiles.** `gate-image-vuln` becomes required wherever a Dockerfile ships, consistent with `gate-image-sbom`/`gate-image-provenance`. Behavioural proof stays on the ts-node reference (golden-path).

---

## 2. Components (4 parts)

### 2.1 `gate-image-vuln` step in all 7 Dockerfile profiles' `ci.yml` (agent-editable)
`profiles/*/` is not control-plane (reference templates). In each profile's `build` job, after the
image is built, a **SHA-pinned** `aquasecurity/trivy-action` scans the built image:

```yaml
      - name: Image vulnerability scan (fixable CRITICAL/HIGH)
        id: gate-image-vuln
        uses: aquasecurity/trivy-action@<SHA>  # vX.Y.Z (resolved + pinned in the plan)
        with:
          image-ref: <profile-image>:ci        # the same image gate-image-sbom scans
          severity: 'CRITICAL,HIGH'
          ignore-unfixed: true
          exit-code: '1'
          vuln-type: 'os,library'
```

**SHA pin is mandatory** — `action-pinning.sh` checks `profiles/typescript-node/ci.yml` + kit
workflows; an unpinned `@vX` would fail the gate. (The `terraform` profile's existing `@0.24.0` is
out of `action-pinning.sh`'s scope; this new one is in scope.)

### 2.2 `conformance/container-supply-chain.sh` (control-plane)
Add `gate-image-vuln` to the required gate-id loop (line 59): `for id in gate-image-sbom
gate-image-provenance gate-image-vuln`. Every Dockerfile profile must now declare it (fail-closed,
profile-wide — the existing pattern). Not a registered claim (it's a `verify.sh`/CI control-check),
so the **claim count stays 26**.

### 2.3 A dedicated `image-vuln` job in `.github/workflows/golden-path.yml` (control-plane)
Mirrors the E4a `containment-audit` job (self-contained, path-filtered, ts-node reference). It:
incept a temp ts-node project → stage the Dockerfile → `docker build` the reference image →

- **PASS scan:** SHA-pinned `aquasecurity/trivy-action` scans the reference image with the policy →
  must exit 0 (ts-node slim reference is clean) — proves the scanner runs and the reference passes.
- **RED scan (non-vacuous):** the same SHA-pinned `aquasecurity/trivy-action` scans a **pinned
  known-vulnerable base image** (by digest) with the *identical* policy, with `continue-on-error:
  true`. A shell assert step then checks *both* that the trivy-action step `outcome == 'failure'`
  *and* that `jq '[.Results[]?.Vulnerabilities // [] | length] | add // 0' trivy-red.json` is
  greater than 0 — proving the gate blocked on actual CRITICAL/HIGH *findings*, not merely on a
  network/pull failure. This findings-count assert is the canonical GHA idiom for non-vacuous RED
  proofs; it closes the false-"RED OK" hole that would occur if the fixture became unpullable (404)
  while the vuln DB was fine.

**Trivy mechanism in the proof job:** the SHA-pinned **`aquasecurity/trivy-action`** for both PASS
and RED scans (with `format: json` + `output: trivy-red.json` on the RED so the assert step can
count findings). The policy (severity/ignore-unfixed/vuln-type) is identical to the profile gate.
The `continue-on-error: true` + outcome-assert-on-findings idiom is the canonical GHA way to assert
a step failed on real data — not a bare exit-code check that a pull failure would satisfy.

### 2.4 `conformance/golden-path-wired.sh` (control-plane)
Extend its token list to lock the new `image-vuln` job + its load-bearing steps (the PASS scan, the
RED fixture + the non-zero assertion). Reuses the existing `golden-path` claim — **no new claim**.

### 2.5 Docs (control-plane: `DEVELOPMENT-STANDARDS.md` §14; agent-editable: the rest)
- `DEVELOPMENT-STANDARDS.md` §14 — extend the container image supply-chain bullet to include the
  image-vuln scan (fixable CRITICAL/HIGH) as part of the conditional gate.
- `CHANGELOG`, README badge, `docs/ROADMAP-KIT.md` (E4b ✅ + decomposition), this design doc.

---

## 3. The non-vacuous RED fixture

A **pinned-by-digest old base image** (a 2+-year-old `node`/`debian`/`python` slim) that reliably
carries fixable CRITICAL/HIGH — immutable images only *accrue* CVEs over time, so a pinned old
digest stays a reliable RED. Documented as **swappable** if it ever scans clean. The exact image +
digest is resolved and verified in the plan (scan it locally first; confirm fixable CRITICAL/HIGH
present).

`★` Trivy scans image layers (not host bind-mounts), so unlike E4a this is **not** Mac-vs-Linux
fragile. But CI remains the canonical proof: the Trivy DB and the fixture's current CVE set resolve
at run time on the runner.

---

## 4. Error handling / scope / footprint

- **Network:** Trivy pulls its vuln DB (golden-path has network; the action caches it). The
  RED fixture is pulled by digest.
- **Scan target:** the **runtime** image (what ships — distroless nonroot), same target as `gate-image-sbom`.
- **Honest boundary:** gates **fixable** CRITICAL/HIGH only (actionable). Unfixed CVEs are
  enumerated by the SBOM, not gated — stated in the gate comment + STANDARDS so it's not read as
  "zero CVEs."
- **Control-plane footprint → AMBER mechanic** (flat `/tmp/e4b_scratch/` → human-run `apply.py` →
  **security-review-of-scratch MANDATORY**): `container-supply-chain.sh`, `golden-path.yml`,
  `golden-path-wired.sh`, `DEVELOPMENT-STANDARDS.md`.
- **Agent-editable on-branch** (build subagent): the 7 `profiles/*/ci.yml`, VERSION, CHANGELOG,
  README badge, ROADMAP, this doc.
- **Proof model (G2/E4a):** local Trivy red-green if installable (PASS reference + RED fixture);
  **golden-path `image-vuln` job GREEN on PR + main = the canonical proof.** Local docker/trivy is a
  decent proxy here (image-layer scan, not bind-mount), but CI is authoritative (E4a lesson).
- **apply.py invariants:** explicit ROOT, idempotent, atomic, fail-loud anchors, mode-preserving.
- **No new claim** (claims stay 26 — extends the `container-supply-chain` contract + the
  `golden-path` behavioural lock).

---

## 5. Verification / Definition of Done

- `image-vuln` golden-path job GREEN on the PR and the main push (PASS reference + RED fixture blocked).
- `container-supply-chain.sh` requires `gate-image-vuln`; all 7 profiles declare it; check green.
- `golden-path-wired.sh` locks the new job; `--selftest` green.
- `action-pinning.sh` green (trivy-action SHA-pinned in ts-node + golden-path).
- `verify.sh --require` green; `doctor` Overall PASS; claims 26.
- builder ≠ reviewer + security-review-of-scratch both APPROVE (nits folded in scratch).
- Merge landed verified (main HEAD + tag + PR MERGED); VERSION/CHANGELOG/README/ROADMAP updated.

---

## 6. E4 decomposition (updated; only E4b built now)

| Slice | Status |
|---|---|
| E4a — boot+probe sandbox (FS/egress/caps PROVEN) | ✅ v3.42.0 |
| **E4b — image-vuln CVE gate (this)** | **building** |
| E4a′ — scoped-tokens/prod-SoD honest static check | next candidates |
| E4c — DAST / runtime-security reference | |
| E4d — cost-ceiling / runaway kill-switch | |
| E4e — R2 bot-identity ratification gate (author≠approver) | |
| E4f — G8 per-segment guard | |
| /work-mount reference fix (E4a follow-up) | |

E3 (orchestration) builds after E4. Order: E2 ✓ → E4 → E3 → E1/E5/E6.
