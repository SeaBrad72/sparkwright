# Best-Practice Fidelity (Slice 9j) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the R10 best-practice-fidelity gaps — declare the kit's SLSA level, add a NIST SSDF crosswalk column, formalize a11y/load/eval as conditional gates (honest-demote, MINOR), and make the canonical reference pipeline satisfy its own SHA-pinning contract.

**Architecture:** Doc edits to PROCESS §7 / STANDARDS §14 + §2 / CLAUDE.md DoD / the enterprise crosswalk; SHA-pin `profiles/typescript-node/ci.yml`; two new POSIX-sh drift-guards (`conditional-gates.sh`, `action-pinning.sh`); CI wiring. No new universal gate → MINOR v2.36.0.

**Tech Stack:** Markdown + POSIX `sh` + GitHub Actions. SHAs resolved via `gh api`. Verified by both scripts' `--selftest`, `dash -n`, `ci-gates.sh` (gate-ids intact), `check-links.sh`.

---

## Execution notes
- **One control-plane `cp`:** Task 8 (`.github/workflows/ci.yml`). The two scripts live in `conformance/`; `profiles/typescript-node/ci.yml` is an adopter REFERENCE (not the kit's own control plane) — agent-editable. `CLAUDE.md`/`DEVELOPMENT-STANDARDS.md` are governing docs (security-owner lens), not guard-protected.
- **The honest-demote must add NO universal requirement** — a11y/load/eval are formalized as *conditional* gates; the universal 7 are unchanged. The `CLAUDE.md` DoD edit is a clarifying line only.
- **SLSA claim is L2** — do not overclaim L3.
- **Anonymization** ([[kit-anonymization]]): generic throughout.
- **Branch:** `feature/slice-9j-best-practice-fidelity` (holds the spec, commit `cbb26be`).

## File structure

| File | Responsibility |
|------|----------------|
| `DEVELOPMENT-PROCESS.md` (modify) | §7 add Accessibility conditional-gate row |
| `DEVELOPMENT-STANDARDS.md` (modify) | §14 universal-vs-conditional note + SLSA L2 declaration + Dependabot pin note; §2 commit/tag-signing subsection |
| `CLAUDE.md` (modify) | DoD CI/CD: one conditional-gates clarification line |
| `docs/enterprise/compliance-crosswalk.md` (modify) | NIST SSDF column + SLSA note + frameworks-covered line |
| `profiles/typescript-node/ci.yml` (modify) | every `uses:` → 40-char SHA + `# vX` |
| `conformance/conditional-gates.sh` (new) | §7 names a11y/load/eval as conditional gates; `--selftest` |
| `conformance/action-pinning.sh` (new) | canonical reference fully SHA-pinned; `--selftest` |
| `conformance/README.md` (modify) | two index rows |
| `.github/workflows/ci.yml` (modify, **human cp**) | both checks + selftests |
| `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md` (modify) | 2.36.0; 9j → shipped (MINOR) |

---

## Task 1: §7 Accessibility conditional-gate row

**Files:** Modify `DEVELOPMENT-PROCESS.md`

- [ ] **Step 1: Add the Accessibility row.** Find the Resilience-readiness row:
```
| **Resilience readiness** *(deployable services)* | Do resilience + load/soak verifications pass — breaker trips, degrades gracefully, within perf budget? (`conformance/resilience-readiness.md`) | On-call / operator + reviewer |
```
Insert immediately AFTER it:
```
| **Accessibility** *(user-facing UI)* | Keyboard / screen-reader / contrast pass (WCAG 2.1 AA)? Recorded in `templates/A11Y-SIGNOFF-TEMPLATE.md` (axe / Lighthouse evidence). | Designer / reviewer |
```

- [ ] **Step 2: Verify + commit.**
  Run: `for g in "Accessibility" "Eval gate" "Resilience readiness"; do grep -q "$g" DEVELOPMENT-PROCESS.md && echo "ok $g"; done` → 3 × ok (the conditional trio now all present in §7).
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.
  ```bash
  git add DEVELOPMENT-PROCESS.md
  git commit -m "docs(9j): §7 Accessibility conditional-gate row (names the a11y/load/eval conditional trio)"
  ```

---

## Task 2: §14 conditional-gate note + SLSA L2 declaration + Dependabot pin note

**Files:** Modify `DEVELOPMENT-STANDARDS.md`

- [ ] **Step 1: Add the universal-vs-conditional note + SLSA declaration.** Find:
```
> This raises the supply-chain posture (gates 6–7) to the baseline for **all** projects — see `DEVELOPMENT-PROCESS.md` §10.
```
Insert immediately AFTER it:
```

**Conditional gates (a11y / load / eval).** The seven above are **universal**. Three further gates are **first-class but conditional** — binding only when their trigger is present, **N/A-with-reason** otherwise (the same pattern as the 15-factor and threat-model gates):
- **Accessibility** *(user-facing UI)* — WCAG 2.1 AA; recorded in `templates/A11Y-SIGNOFF-TEMPLATE.md` (axe / Lighthouse). `DEVELOPMENT-PROCESS.md` §7.
- **Load / soak** *(deployable services)* — resilience + perf-budget verification; `conformance/resilience-readiness.md`.
- **Eval** *(AI features)* — model/prompt output meets the eval bar and does not regress; `DEVELOPMENT-PROCESS.md` §7.

They are deliberately **not** universal required gates: forcing an a11y, load, or eval gate on a CLI, library, or batch job that has no UI, no service, and no model would be false universality. Verified by `conformance/conditional-gates.sh`.

**SLSA level.** This kit's released artifacts reach **SLSA Build L2**: provenance is **authenticated and service-generated** (`actions/attest-build-provenance` runs in the push-only, least-privilege OIDC job and binds the attestation to the artifact / image digest). The **evidence** is the attestation itself. The kit does **not** yet claim **L3** — that requires a hermetic / isolated build with non-falsifiable provenance; the path is documented here as the next hardening step, not a current guarantee.
```

- [ ] **Step 2: Add the Dependabot note to the pinning sentence.** Find (in the CI hardening paragraph):
```
Pin third-party actions to a full commit SHA in production.
```
Replace with:
```
Pin third-party actions to a full commit SHA in production (keep the SHAs current with Dependabot, which updates the SHA and its `# vX` comment together); the canonical reference `profiles/typescript-node/ci.yml` models this and is enforced by `conformance/action-pinning.sh`.
```

- [ ] **Step 3: Verify + commit.**
  Run: `grep -q "SLSA Build L2" DEVELOPMENT-STANDARDS.md && grep -q "Conditional gates" DEVELOPMENT-STANDARDS.md && echo ok`.
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.
  ```bash
  git add DEVELOPMENT-STANDARDS.md
  git commit -m "docs(9j): §14 conditional-gate note + SLSA Build L2 declaration (L3 path) + Dependabot pin note"
  ```

---

## Task 3: §2 commit/tag-signing subsection

**Files:** Modify `DEVELOPMENT-STANDARDS.md`

- [ ] **Step 1: Add the subsection.** Find the AI/agent security block's end + the next heading:
```
- **Capability boundaries** — agents act only within explicitly granted capabilities (see governance in `DEVELOPMENT-PROCESS.md` §13).

### Audit logging
```
Replace with:
```
- **Capability boundaries** — agents act only within explicitly granted capabilities (see governance in `DEVELOPMENT-PROCESS.md` §13).

### Commit & tag signing (recommended hardening)
Sign commits and **release tags** so authorship and releases are verifiable. Prefer **Sigstore `gitsign`** (keyless, OIDC-backed — no long-lived keys) or GPG where an org already runs a key infrastructure. This is **recommended, not a required gate** — mandating it is a deliberate future step (it would be a contract change). Adopters who opt in verify signatures in CI; the kit documents the path and does not block on it.

### Audit logging
```

- [ ] **Step 2: Verify + commit.**
  Run: `grep -q "Commit & tag signing" DEVELOPMENT-STANDARDS.md && echo ok`.
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.
  ```bash
  git add DEVELOPMENT-STANDARDS.md
  git commit -m "docs(9j): §2 commit & tag signing subsection (recommended hardening, not a gate)"
  ```

---

## Task 4: CLAUDE.md DoD conditional-gates line (governing surface)

**Files:** Modify `CLAUDE.md`

- [ ] **Step 1: Append a conditional-gates clarification to the CI/CD DoD line.** Find:
```
**CI/CD** — pipeline green · build succeeds · the 7 required gates pass, incl. secret-scan and SBOM+provenance · no known high/critical vulnerabilities (per `DEVELOPMENT-STANDARDS.md` §14).
```
Replace with:
```
**CI/CD** — pipeline green · build succeeds · the 7 required gates pass, incl. secret-scan and SBOM+provenance · the conditional gates (a11y / load / eval) pass where their trigger applies, else N/A-with-reason · no known high/critical vulnerabilities (per `DEVELOPMENT-STANDARDS.md` §14).
```
This adds **no universal requirement** — it names the existing conditional obligation. Do NOT change "the 7 required gates."

- [ ] **Step 2: Verify (no universal gate added) + commit.**
  Run: `git diff CLAUDE.md` — confirm the ONLY change is the CI/CD line gaining the conditional-gates clause; "the 7 required gates" wording is intact.
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.
  ```bash
  git add CLAUDE.md
  git commit -m "docs(9j): DoD names the conditional gates (a11y/load/eval) where triggered — no new universal gate"
  ```

---

## Task 5: NIST SSDF crosswalk column

**Files:** Modify `docs/enterprise/compliance-crosswalk.md`

- [ ] **Step 1: Update the "Frameworks covered" line.** Find:
```
**Frameworks covered:** SOC 2 (Security + Privacy categories) · ISO 27001:2022 Annex A.
```
Replace with:
```
**Frameworks covered:** SOC 2 (Security + Privacy categories) · ISO 27001:2022 Annex A · NIST SSDF (SP 800-218 v1.1).
```

- [ ] **Step 2: Add the NIST SSDF column to the security & engineering controls table.** The header is:
```
| Kit control | Where in the kit | SOC 2 | ISO 27001:2022 | Evidence artifact | Responsibility |
|-------------|------------------|-------|----------------|-------------------|----------------|
```
Replace it (header + separator) with the same plus a NIST SSDF column inserted before "Evidence artifact":
```
| Kit control | Where in the kit | SOC 2 | ISO 27001:2022 | NIST SSDF (800-218) | Evidence artifact | Responsibility |
|-------------|------------------|-------|----------------|---------------------|-------------------|----------------|
```
Then for EACH existing data row in that table, insert the SSDF cell before its Evidence-artifact cell, using these exact mappings:
- **Lint / type-check / test + 80% coverage** → `PW.7, PW.8`
- **Reproducible production build** → `PW.6, PS.3`
- **Secret scanning (no committed secrets)** → `PW.8, PS.1`
- **Dependency vulnerability scan** → `PW.4, RV.1`
- **SBOM + build-provenance attestation** → `PS.2, PS.3 (SLSA Build L2)`
- **Least-privilege OIDC in CI (push-only provenance job)** → `PO.3, PO.5`
- **Branch protection · builder ≠ sole merger** → `PS.1, PW.7`

(Read the table first; apply the cell to each row by its "Kit control" label. If a row's control is not in the list above — e.g. a threat-model or input-validation row — map it: threat-model → `PW.1`; input validation / injection / authz → `PW.5`; PII / privacy rows → `—` with a note that SSDF is software-security-scoped, privacy is covered by SOC 2 Privacy / ISO. Keep every other cell in each row byte-for-byte.)

- [ ] **Step 3: Verify + commit.**
  Run: `grep -q "NIST SSDF" docs/enterprise/compliance-crosswalk.md && echo ok`.
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.
  ```bash
  git add docs/enterprise/compliance-crosswalk.md
  git commit -m "docs(9j): NIST SSDF (800-218) crosswalk column + SLSA L2 note"
  ```

---

## Task 6: SHA-pin the canonical reference `ci.yml`

**Files:** Modify `profiles/typescript-node/ci.yml`

- [ ] **Step 1: Resolve real SHAs.** For each action tag used in the file, resolve the commit SHA the tag points to:
  ```bash
  for a in "actions/checkout@v4" "actions/setup-node@v4" "gitleaks/gitleaks-action@v2" "actions/upload-artifact@v4" "actions/download-artifact@v4" "anchore/sbom-action@v0" "actions/attest-build-provenance@v1" "docker/login-action@v3" "docker/build-push-action@v6"; do
    repo=${a%@*}; tag=${a#*@}
    sha=$(gh api "repos/$repo/commits/$tag" --jq .sha 2>/dev/null)
    echo "$a  ->  $sha"
  done
  ```
  Record each `owner/repo@<40-char-sha>  # <tag>`.

- [ ] **Step 2: Rewrite every `uses:` in `profiles/typescript-node/ci.yml`** to its resolved SHA, keeping a trailing `# vX` comment. Use the Read tool to see the file, then Edit each `uses:` line. Every occurrence must change, e.g.:
  - `- uses: actions/checkout@v4` → `- uses: actions/checkout@<sha>  # v4` (lines with `actions/checkout@v4` appear more than once — fix all)
  - `uses: gitleaks/gitleaks-action@v2` → `uses: gitleaks/gitleaks-action@<sha>  # v2`
  - …and so on for setup-node, upload-artifact, download-artifact, sbom-action, attest-build-provenance, login-action, build-push-action.
  Do NOT change any `id:` / `name:` / `run:` line — only the `@ref` in `uses:`.

- [ ] **Step 3: Verify the pipeline contract is intact + every uses is SHA-pinned.**
  Run: `sh conformance/ci-gates.sh profiles/typescript-node/ci.yml` → still PASS (gate-ids unchanged).
  Run: `grep -nE 'uses:' profiles/typescript-node/ci.yml | grep -vE '@[0-9a-f]{40}' || echo "all uses SHA-pinned"` → `all uses SHA-pinned`.
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.

- [ ] **Step 4: Commit.**
  ```bash
  git add profiles/typescript-node/ci.yml
  git commit -m "ci(profile): 9j — SHA-pin every uses: in the canonical typescript-node reference (satisfies its own contract)"
  ```

---

## Task 7: The two conformance drift-guards

**Files:** Create `conformance/conditional-gates.sh`, `conformance/action-pinning.sh`; modify `conformance/README.md`

- [ ] **Step 1: Write `conformance/conditional-gates.sh`:**

```sh
#!/bin/sh
# conditional-gates.sh — assert the a11y/load/eval CONDITIONAL gates are named in §7 (Slice 9j).
# The honest-demote: these are first-class but conditional (trigger-bound), not universal.
# Asserts DEVELOPMENT-PROCESS.md §7 names Accessibility, Resilience (load), and Eval as gates.
#   sh conformance/conditional-gates.sh [--selftest]
# Exit: 0 = ok · 1 = a gap · 2 = bad usage. POSIX sh; dash-clean.
set -eu

GATE_DOC="DEVELOPMENT-PROCESS.md"
GATES="Accessibility Eval Resilience"

# check_doc <doc>: print PASS/FAIL; return 1 on any gap.
check_doc() {
  d=$1; f=0
  if [ ! -f "$d" ]; then echo "FAIL: missing $d"; return 1; fi
  for g in $GATES; do
    if grep -q "$g" "$d"; then echo "PASS: $d names the $g gate"; else echo "FAIL: $d omits the $g gate"; f=1; fi
  done
  return $f
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  g=$(mktemp -d)
  printf '# proc\nEval gate\nResilience readiness\n' > "$g/proc.md"   # missing Accessibility
  if check_doc "$g/proc.md" >/dev/null 2>&1; then
    echo "FAIL: selftest — missing conditional gate not detected"; sfail=1
  else
    echo "PASS: selftest — missing conditional gate detected"
  fi
  ok=$(mktemp -d)
  printf '# proc\nAccessibility\nEval gate\nResilience readiness\n' > "$ok/proc.md"
  if check_doc "$ok/proc.md" >/dev/null 2>&1; then
    echo "PASS: selftest — complete trio passes"
  else
    echo "FAIL: selftest — complete trio wrongly rejected"; sfail=1
  fi
  [ "$sfail" -eq 0 ] && { echo "OK: conditional-gates selftest"; exit 0; } || { echo "FAIL: conditional-gates selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: conditional-gates.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Conditional-gate naming (§7):"
if check_doc "$GATE_DOC"; then
  echo "OK: a11y / load / eval are named as conditional gates in §7"
  exit 0
else
  echo "FAIL: a conditional gate is unnamed in §7 (see above)"
  exit 1
fi
```

- [ ] **Step 2: Write `conformance/action-pinning.sh`:**

```sh
#!/bin/sh
# action-pinning.sh — assert the canonical reference pipeline SHA-pins every `uses:` (Slice 9j).
# The other 9 profiles are adopter-templates (pin at adoption); the contract is enforced on the
# canonical reference so the kit satisfies its own "pin to a full commit SHA" rule.
#   sh conformance/action-pinning.sh [--selftest]
# Exit: 0 = all SHA-pinned · 1 = a tag-pinned uses: · 2 = bad usage. POSIX sh; dash-clean.
set -eu

REF="profiles/typescript-node/ci.yml"

# check_pinned <workflow>: print PASS/FAIL per `uses:`; return 1 if any is not a 40-hex SHA.
check_pinned() {
  wf=$1; f=0
  if [ ! -f "$wf" ]; then echo "FAIL: missing $wf"; return 1; fi
  refs=$(grep -oE 'uses:[[:space:]]*[^[:space:]#]+' "$wf" | sed 's/uses:[[:space:]]*//')
  if [ -z "$refs" ]; then echo "FAIL: no uses: found in $wf"; return 1; fi
  for r in $refs; do
    sha=${r#*@}
    case "$r" in
      *@*) : ;;
      *) echo "FAIL: $r has no @ref"; f=1; continue ;;
    esac
    case "$sha" in
      *[!0-9a-f]*) echo "FAIL: $r is not SHA-pinned (tag/branch)"; f=1 ;;
      *) if [ "${#sha}" -eq 40 ]; then echo "PASS: $r"; else echo "FAIL: $r is not a 40-char SHA"; f=1; fi ;;
    esac
  done
  return $f
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  # gap tree: a tag-pinned uses: must be detected
  g=$(mktemp -d)
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@v4\n' > "$g/wf.yml"
  if check_pinned "$g/wf.yml" >/dev/null 2>&1; then
    echo "FAIL: selftest — tag-pin not detected"; sfail=1
  else
    echo "PASS: selftest — tag-pin detected"
  fi
  # complete tree: a 40-hex SHA-pinned uses: must pass
  ok=$(mktemp -d)
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@1111111111111111111111111111111111111111  # v4\n' > "$ok/wf.yml"
  if check_pinned "$ok/wf.yml" >/dev/null 2>&1; then
    echo "PASS: selftest — SHA-pin passes"
  else
    echo "FAIL: selftest — SHA-pin wrongly rejected"; sfail=1
  fi
  [ "$sfail" -eq 0 ] && { echo "OK: action-pinning selftest"; exit 0; } || { echo "FAIL: action-pinning selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: action-pinning.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Action-pinning ($REF):"
if check_pinned "$REF"; then
  echo "OK: every uses: in the canonical reference is SHA-pinned"
  exit 0
else
  echo "FAIL: a uses: in the canonical reference is not SHA-pinned (see above)"
  exit 1
fi
```

- [ ] **Step 3: Make executable + dash-check both.**
  Run: `chmod +x conformance/conditional-gates.sh conformance/action-pinning.sh && dash -n conformance/conditional-gates.sh && dash -n conformance/action-pinning.sh && echo "syntax OK"`.

- [ ] **Step 4: Run selftests + real + bad usage.**
  Run: `sh conformance/conditional-gates.sh --selftest; echo "exit=$?"` → 2 PASS + OK, exit 0.
  Run: `sh conformance/conditional-gates.sh; echo "exit=$?"` → 3 PASS + OK, exit 0 (after Task 1).
  Run: `sh conformance/action-pinning.sh --selftest; echo "exit=$?"` → 2 PASS + OK, exit 0.
  Run: `sh conformance/action-pinning.sh; echo "exit=$?"` → all PASS + OK, exit 0 (after Task 6).
  Run: `sh conformance/conditional-gates.sh --bogus; echo "exit=$?"` → exit 2. `sh conformance/action-pinning.sh --bogus; echo "exit=$?"` → exit 2.

- [ ] **Step 5: conformance/README index rows.** After the `agents-brief.sh` row, add:
  ```markdown
  | `conditional-gates.sh` | script | Slice 9j — §7 names the conditional gates (a11y / load / eval), trigger-bound not universal; drift-guard | CI |
  | `action-pinning.sh` | script | Slice 9j — the canonical reference pipeline SHA-pins every `uses:` (the reference satisfies its own pinning contract) | CI |
  ```

- [ ] **Step 6: Commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.
  ```bash
  git add conformance/conditional-gates.sh conformance/action-pinning.sh conformance/README.md
  git commit -m "feat(conformance): 9j — conditional-gates.sh + action-pinning.sh drift-guards (+ --selftest)"
  ```

---

## Task 8: Wire both checks into CI (control-plane `cp`)

**Files:** Modify `.github/workflows/ci.yml` (build `/tmp` → human applies)

- [ ] **Step 1: Build candidate.** Read `.github/workflows/ci.yml`; Write a copy to `/tmp/ci.yml.9j` (Write tool — do NOT `cp`/`sed` the control-plane path) with FOUR steps added to the `conformance` job immediately after the `Definition-of-Ready self-test` step:
  ```yaml
      - name: Conditional gates named in §7 (a11y / load / eval)
        run: sh conformance/conditional-gates.sh
      - name: Conditional-gates self-test
        run: sh conformance/conditional-gates.sh --selftest
      - name: Reference pipeline SHA-pins every uses:
        run: sh conformance/action-pinning.sh
      - name: Action-pinning self-test
        run: sh conformance/action-pinning.sh --selftest
  ```

- [ ] **Step 2: Validate.**
  Run: `ruby -ryaml -e 'd=YAML.load_file("/tmp/ci.yml.9j"); puts d["jobs"].keys.join(",")'` → `conformance,bootstrap,docs-links`.
  Run: `diff .github/workflows/ci.yml /tmp/ci.yml.9j` → only the four added steps (8 `>` lines).

- [ ] **Step 3: Hand to Bradley (human `cp`).** Present exactly:
  ```bash
  cd ~/Development/agentic-sdlc-kit && cp /tmp/ci.yml.9j .github/workflows/ci.yml && git add .github/workflows/ci.yml && git commit -m "ci(kit): 9j — gate conditional-gates + action-pinning (+ selftests)"
  ```
  Wait for confirmation.

---

## Task 9: Release (VERSION / CHANGELOG / roadmap)

**Files:** Modify `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md`

- [ ] **Step 1: `VERSION`** → replace `2.35.0` with `2.36.0`.

- [ ] **Step 2: Sync the badge.**
  Run: `sh conformance/badge-version.sh --fix` → `fixed: README badge set to v2.36.0`. Run: `sh conformance/badge-version.sh; echo exit=$?` → PASS exit 0.

- [ ] **Step 3: CHANGELOG entry** above `## [2.35.0]`:
  ```markdown
  ## [2.36.0] - 2026-06-10

  Best-practice fidelity (Slice 9j, Stage V of the "Honest Assurance & Adoption Reach" arc). Declares the kit's SLSA level, adds a NIST SSDF crosswalk, formalizes a11y/load/eval as conditional gates, and makes the reference pipeline satisfy its own SHA-pinning contract. **MINOR** — the a11y/load/eval fork resolved in favor of *honest conditional gates*, not a new universal gate, so no MAJOR.

  ### Added
  - **SLSA Build L2 declaration** (`DEVELOPMENT-STANDARDS.md` §14) — authenticated, service-generated provenance bound to the artifact/image digest; the honest L3 path documented (not claimed).
  - **NIST SSDF (SP 800-218) column** in `docs/enterprise/compliance-crosswalk.md`, alongside SOC 2 + ISO 27001:2022.
  - **Commit & tag signing** subsection (`DEVELOPMENT-STANDARDS.md` §2) — Sigstore `gitsign` / GPG, recommended hardening (not a gate).
  - **`conformance/conditional-gates.sh`** + **`conformance/action-pinning.sh`** drift-guards (`--selftest`), CI-gated.

  ### Changed
  - **a11y / load / eval formalized as conditional gates** (§7 + §14 + DoD): first-class but trigger-bound (UI / service / AI), N/A-with-reason otherwise — not universal. No new universal required gate.
  - **`profiles/typescript-node/ci.yml`** now SHA-pins every `uses:` (with `# vX` comments; Dependabot keeps them current) — the canonical reference satisfies its own pinning contract.
  ```

- [ ] **Step 4: roadmap — mark 9j shipped.** In `docs/ROADMAP-SLICE9.md`, replace the `9j` row:
  ```markdown
  | **9j** ✅ | B | **Best-practice fidelity** (R10) — *shipped v2.36.0 (MINOR).* SLSA Build L2 declared (L3 path noted); NIST SSDF crosswalk column; a11y/load/eval formalized as **conditional** gates (honest-demote, not universal → no MAJOR); commit/tag-signing documented; canonical reference `ci.yml` SHA-pinned + `action-pinning.sh`; `conditional-gates.sh`. | P2 | MINOR ✅ |
  ```
  Also update the **Versioning note** near the top: find `One slice (**9j**) contains a genuine fork` and append at the end of that paragraph: ` **Resolved (v2.36.0): honest-demote — a11y/load/eval are conditional gates, MINOR; no 3.0.0 from this fork.**`

- [ ] **Step 5: Verify + commit.**
  Run: `cat VERSION` → `2.36.0`. Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.
  ```bash
  git add VERSION README.md CHANGELOG.md docs/ROADMAP-SLICE9.md
  git commit -m "chore(release): 2.36.0 — best-practice fidelity (9j); fork resolved MINOR (conditional gates)"
  ```

---

## Task 10: Final verification + independent review + PR

- [ ] **Step 1: Full local sweep.**
  ```sh
  sh conformance/conditional-gates.sh >/dev/null && echo "conditional-gates OK"
  sh conformance/conditional-gates.sh --selftest >/dev/null && echo "cg selftest OK"
  sh conformance/action-pinning.sh >/dev/null && echo "action-pinning OK"
  sh conformance/action-pinning.sh --selftest >/dev/null && echo "ap selftest OK"
  dash -n conformance/conditional-gates.sh && dash -n conformance/action-pinning.sh && echo "dash OK"
  sh conformance/ci-gates.sh profiles/typescript-node/ci.yml | tail -1   # gate-ids intact after pinning
  sh conformance/verify.sh 2>&1 | tail -1
  sh conformance/check-links.sh 2>&1 | tail -1
  git diff main..HEAD -- CLAUDE.md     # confirm DoD adds NO universal gate (one conditional-gates clause)
  grep -rniE "enterprise|public.media|bradley" conformance/conditional-gates.sh conformance/action-pinning.sh || echo "anon clean"
  ```
  Expected: all OK; the `CLAUDE.md` diff is the single conditional-gates clause; anon clean.

- [ ] **Step 2: Independent review (builder ≠ sole reviewer; CLAUDE.md + §14 are governing surfaces → security-owner lens).** Dispatch a reviewer on `git diff main...HEAD`: (a) the honest-demote adds **no new universal required gate** — a11y/load/eval are conditional, the 7 unchanged, the DoD CI/CD line still says "7 required gates"; (b) the **SLSA claim is L2, not overclaimed L3**, and matches the evidence the kit produces; (c) the NIST SSDF mappings are defensible (PS.2/PS.3 for provenance, PW.4/RV.1 for dep-scan, etc.); (d) `profiles/typescript-node/ci.yml` — every `uses:` is a real 40-hex SHA, gate `id:`s unchanged (`ci-gates.sh` still green), comments name the version; (e) `conditional-gates.sh` + `action-pinning.sh` POSIX correctness (`return $f`, the `case`-based SHA validation, two-tree selftests no-`rm`, exit codes 0/1/2, `set -eu`, `dash -n`) and that each selftest genuinely catches its regression (a tag-pin / a missing conditional gate); (f) signing is recommended-not-required (no gate added); (g) anonymization. Fix findings; re-review if non-trivial.

- [ ] **Step 3: Push + open PR.**
  ```bash
  git push -u origin feature/slice-9j-best-practice-fidelity
  gh pr create --base main --head feature/slice-9j-best-practice-fidelity \
    --title "Slice 9j — Best-Practice Fidelity (v2.36.0)" --body-file /tmp/pr-9j-body.md
  ```
  (Write `/tmp/pr-9j-body.md`: the fork resolved MINOR, SLSA L2, SSDF column, conditional-gate formalization, signing-as-recommended, SHA-pinned reference + the two drift-guards, one cp.)

- [ ] **Step 4: Confirm CI green; hand to Bradley to ratify (merge).** Agent never self-merges.

---

## Self-review (against the spec)
- **Spec coverage:** §7 a11y row (T1) · §14 conditional note + SLSA L2 + Dependabot (T2) · §2 signing (T3) · DoD line (T4) · SSDF column (T5) · SHA-pin reference (T6) · both drift-guards + index (T7) · CI cp (T8) · release MINOR 2.36.0 + roadmap fork-resolution (T9) · review + PR (T10). All five spec threads covered.
- **Placeholder scan:** both scripts are complete; doc edits have exact find/replace anchors; SSDF mappings and the SHA-resolution commands are concrete. No placeholders.
- **Consistency:** the conditional trio names — **Accessibility**, **Eval**, **Resilience** — are the literal grep targets in `conditional-gates.sh` (T7) and exactly what T1/T2/T4 write; `action-pinning.sh`'s 40-hex-SHA rule matches the pins T6 produces; version 2.36.0 consistent across VERSION + badge + CHANGELOG + roadmap (T9); SLSA "Build L2" worded identically in T2 + T5 + T9.
