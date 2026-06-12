# SP-1 — Security Gates (SAST + License) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two conditional CI gates — `gate-sast` (first-party static security analysis) and `gate-license` (a stack-neutral, self-flagging license-policy check over the existing CycloneDX SBOM) — wired into §7/§14/`conditional-gates.sh`, all 10 profiles + `_TEMPLATE`, and a new `docs/operations/security-scanning.md` carrying the per-stack upgrade ladder.

**Architecture:** Both join the conditional-gate family (a11y/load/eval): named in `DEVELOPMENT-PROCESS.md` §7 + `DEVELOPMENT-STANDARDS.md` §14, verified by `conformance/conditional-gates.sh`. `gate-sast` is doc + per-profile reference (Semgrep default, CodeQL alt) — no kit-side tool. `gate-license` ships a real reference tool `scripts/license-check.sh` (sh+jq over the SBOM) that flags denylisted copyleft as a violation and **self-flags undetermined/NOASSERTION components**, pointing to the per-stack upgrade ladder. Honesty: a green gate proves the scan ran + policy applied, never that the code is secure or licenses legally cleared.

**Tech Stack:** `sh` (dash-clean), `jq` (hard-required kit prerequisite). Spec: `docs/superpowers/specs/2026-06-12-security-privacy-completeness-arc-design.md`. Branch: `feature/secpriv-arc` (arc spec already committed there).

**Doc-budget constraint:** PROCESS 468/470, STANDARDS 317/320 — every core-doc edit runs `doc-budget.sh`; prefer `+0` appends; bulk lives in `security-scanning.md`.

---

## File Structure
- **Create** `scripts/license-check.sh` — the stack-neutral SBOM license-policy tool + `--selftest`.
- **Create** `scripts/fixtures/sbom/sample-cyclonedx.json` — fixture SBOM (MIT/GPL/LGPL/undetermined).
- **Create** `docs/operations/security-scanning.md` — SAST + license guidance + the per-stack upgrade ladder + when-to-upgrade triggers.
- **Modify** `conformance/conditional-gates.sh` — add `gate-sast` + `gate-license` §7 markers + extend `--selftest`.
- **Modify** `DEVELOPMENT-PROCESS.md` §7 — two conditional-gate table rows.
- **Modify** `DEVELOPMENT-STANDARDS.md` §14 — a one-line conditional-gates mention (budget-checked).
- **Modify** all 10 `profiles/<stack>.md` + `profiles/_TEMPLATE.md` — a SAST + license line in the security section.
- **Modify** `profiles/typescript-node/ci.yml` — reference `gate-sast` + `gate-license` steps (agent-editable).
- **Modify** `conformance/verify.sh` — `check control license-check sh scripts/license-check.sh --selftest`-style row (see Task 8).
- **Modify** `README.md`-equivalent registry: `conformance/README.md` + `conformance/audit-evidence-checklist.md` rows.
- **Hand-apply (control-plane, Bradley):** kit-CI `license-check.sh --selftest` smoke step.

---

## Conventions
- `#!/bin/sh`, `set -eu`, dash-clean (`dash -n`), quote expansions. jq does all JSON shaping.
- `--selftest` fixtures committed under `scripts/fixtures/`, left in place (7e guard).
- Cross-cutting per-stack line reaches ALL 10 profiles + `_TEMPLATE` (MAINTAINING rule).
- Commit per task (Conventional Commits). Run `doc-budget.sh` after any core-doc edit.

---

## Task 1: Fixture SBOM + default policy understanding

**Files:** Create `scripts/fixtures/sbom/sample-cyclonedx.json`

A minimal CycloneDX SBOM with four components exercising every branch: `alpha`=MIT (ok), `beta`=GPL-3.0-only (denylisted → violation), `delta`=LGPL-3.0-only (**must NOT be flagged** — weak copyleft, proves anchored matching), `gamma`=no license (undetermined).

- [ ] **Step 1: Write the fixture**

```json
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.5",
  "components": [
    { "type": "library", "name": "alpha", "version": "1.0.0", "licenses": [ { "license": { "id": "MIT" } } ] },
    { "type": "library", "name": "beta", "version": "2.0.0", "licenses": [ { "license": { "id": "GPL-3.0-only" } } ] },
    { "type": "library", "name": "delta", "version": "3.0.0", "licenses": [ { "license": { "id": "LGPL-3.0-only" } } ] },
    { "type": "library", "name": "gamma", "version": "4.0.0" }
  ]
}
```

- [ ] **Step 2: Verify valid JSON**

Run: `jq -e . scripts/fixtures/sbom/sample-cyclonedx.json >/dev/null && echo valid`
Expected: `valid`.

- [ ] **Step 3: Commit**

```bash
git add scripts/fixtures/sbom/sample-cyclonedx.json
git commit -m "test(license-check): fixture CycloneDX SBOM (MIT/GPL/LGPL/undetermined)"
```

---

## Task 2: `scripts/license-check.sh` + `--selftest` (TDD core)

**Files:** Create `scripts/license-check.sh`

- [ ] **Step 1: Write the script with its selftest as the test harness**

```sh
#!/bin/sh
# license-check.sh — stack-neutral license-policy gate over a CycloneDX SBOM (SP-1).
# Flags denylisted (strong-copyleft) licenses as a VIOLATION; counts undetermined /
# NOASSERTION components and points to the per-stack upgrade ladder. Reuses gate-sbom
# output — no per-stack license tool. sh + jq (jq is a hard-required kit prerequisite).
#
# HONESTY: green = the DECLARED licenses passed the policy AND undetermined ones were
# surfaced — NOT that licenses are legally cleared. The SBOM has blind spots
# (NOASSERTION / incomplete fields); for higher fidelity see the per-stack upgrade
# ladder in docs/operations/security-scanning.md. Necessary, not sufficient.
#
# Default deny (anchored SPDX prefixes, strong copyleft): AGPL, GPL, SSPL, OSL, EUPL,
# CC-BY-NC. NOTE the anchor excludes LGPL (weak copyleft) by design. Override with
# --policy <file> (newline list of anchored regex patterns; '#' lines ignored).
#
# Usage:
#   sh scripts/license-check.sh --sbom <file> [--policy <file>] [--strict] [--stdout]
#   sh scripts/license-check.sh --selftest
# Exit: 0 = clean (or only-undetermined, non-strict) · 1 = a denylisted license (or
#       undetermined under --strict) · 2 = bad usage / unreadable SBOM.
set -eu

SBOM=""; POLICY=""; STRICT=0
DEFAULT_DENY='^(AGPL|GPL|SSPL|OSL|EUPL|CC-BY-NC)'

deny_regex() {
  if [ -n "$POLICY" ] && [ -f "$POLICY" ]; then
    # join non-comment, non-blank lines with '|'
    _r=$(grep -vE '^[[:space:]]*(#|$)' "$POLICY" | paste -sd '|' -)
    [ -n "$_r" ] && { printf '%s' "$_r"; return; }
  fi
  printf '%s' "$DEFAULT_DENY"
}

# analyze <sbom> <deny-regex>: emits a summary JSON {violations:[{name,lic}], undetermined, total}.
analyze() {
  jq --arg deny "$2" '
    [ .components[]? | {
        name: (.name // "?"),
        lic:  ( (.licenses[0]?.license.id // .licenses[0]?.license.name // .licenses[0]?.expression) // "NOASSERTION" )
      } ] as $c
    | { violations: [ $c[] | select(.lic | test($deny)) ],
        undetermined: ([ $c[] | select(.lic == "NOASSERTION") ] | length),
        total: ($c | length) }
  ' "$1"
}

run() {
  [ -n "$SBOM" ] || { echo "license-check: --sbom <file> required" >&2; exit 2; }
  [ -f "$SBOM" ] || { echo "license-check: SBOM not found: $SBOM" >&2; exit 2; }
  _deny=$(deny_regex)
  _sum=$(analyze "$SBOM" "$_deny") || { echo "license-check: could not parse SBOM (not CycloneDX JSON?)" >&2; exit 2; }
  _v=$(printf '%s' "$_sum" | jq '.violations | length')
  _u=$(printf '%s' "$_sum" | jq '.undetermined')
  _t=$(printf '%s' "$_sum" | jq '.total')
  printf 'license-check: %s component(s) scanned · %s policy violation(s) · %s undetermined\n' "$_t" "$_v" "$_u"
  if [ "$_v" -gt 0 ]; then
    printf '%s' "$_sum" | jq -r '.violations[] | "  VIOLATION: \(.name) — \(.lic) (denylisted)"'
  fi
  if [ "$_u" -gt 0 ]; then
    printf '  REVIEW: %s component(s) have undetermined licenses the SBOM can'\''t clear — flagged for review.\n' "$_u"
    printf '          For higher-fidelity license detection on this stack, see\n'
    printf '          docs/operations/security-scanning.md -> per-stack upgrade.\n'
  fi
  if [ "$_v" -gt 0 ]; then echo "license-check: FAIL (denylisted license present)"; exit 1; fi
  if [ "$_u" -gt 0 ] && [ "$STRICT" -eq 1 ]; then echo "license-check: FAIL (undetermined under --strict)"; exit 1; fi
  echo "license-check: OK (no denylisted licenses; undetermined surfaced for review). NOTE: declared licenses only — not a legal clearance."
  exit 0
}

selftest() {
  st_fail=0
  fx="$(dirname "$0")/fixtures/sbom/sample-cyclonedx.json"
  _deny="$DEFAULT_DENY"
  out=$(analyze "$fx" "$_deny")
  [ "$(printf '%s' "$out" | jq '.violations | length')" = "1" ] || { echo "selftest FAIL: expected 1 violation (GPL)"; st_fail=1; }
  [ "$(printf '%s' "$out" | jq -r '.violations[0].name')" = "beta" ] || { echo "selftest FAIL: beta should be the violation"; st_fail=1; }
  [ "$(printf '%s' "$out" | jq '.undetermined')" = "1" ] || { echo "selftest FAIL: expected 1 undetermined (gamma)"; st_fail=1; }
  # LGPL (delta) must NOT be flagged — anchored regex excludes weak copyleft
  [ "$(printf '%s' "$out" | jq -r '[.violations[].name] | index("delta")')" = "null" ] || { echo "selftest FAIL: LGPL delta wrongly flagged"; st_fail=1; }
  # end-to-end exit code: default run over the fixture FAILs (GPL present)
  if SBOM="$fx" STRICT=0 POLICY="" run >/dev/null 2>&1; then echo "selftest FAIL: fixture run should exit 1 (GPL)"; st_fail=1; else :; fi
  if [ "$st_fail" -ne 0 ]; then echo "license-check --selftest: FAIL" >&2; return 1; fi
  echo "license-check --selftest: OK (GPL flagged, LGPL not, undetermined counted, fixture FAILs)"
  return 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --sbom) SBOM=${2:?}; shift 2 ;;
    --policy) POLICY=${2:?}; shift 2 ;;
    --strict) STRICT=1; shift ;;
    --stdout) shift ;;
    --selftest) selftest; exit $? ;;
    *) echo "usage: license-check.sh --sbom <file> [--policy <file>] [--strict] | --selftest" >&2; exit 2 ;;
  esac
done
run
```

NOTE for the implementer: `selftest` calls `run` in a subshell with `SBOM=... run` — since `run` reads the globals, prefix-assignment works in POSIX only if `run` is invoked as a command; if dash scoping makes that unreliable, set the globals explicitly before the call (`SBOM="$fx"; STRICT=0; run`) inside a `( … )` subshell so they don't leak. Iterate until the selftest passes.

- [ ] **Step 2: Run the selftest until green**

Run: `sh scripts/license-check.sh --selftest`
Expected: `license-check --selftest: OK (...)`. Fix the jq/exit logic until all assertions pass.

- [ ] **Step 3: Spot-check the human output + dash-clean**

Run: `sh scripts/license-check.sh --sbom scripts/fixtures/sbom/sample-cyclonedx.json; echo "exit=$?"; dash -n scripts/license-check.sh && echo dash-clean`
Expected: report showing 4 scanned / 1 violation (beta GPL) / 1 undetermined (gamma) + the REVIEW upgrade pointer; `exit=1`; `dash-clean`.

- [ ] **Step 4: Commit**

```bash
git add scripts/license-check.sh
git commit -m "feat(scripts): license-check.sh — stack-neutral SBOM license gate + self-flagging"
```

---

## Task 3: Extend `conformance/conditional-gates.sh` (markers + selftest)

**Files:** Modify `conformance/conditional-gates.sh`

The check asserts §7 names each conditional-gate row by a fixed-string marker. Add SAST + license markers.

- [ ] **Step 1: Add the two markers to the `check_doc` heredoc**

Find the heredoc block listing the three markers (`Accessibility** *(user-facing UI)*`, `Eval gate** *(AI features)*`, `Resilience readiness** *(deployable services)*`) and add two lines inside it:
```
SAST** *(first-party code)*
License compliance** *(when an SBOM is produced)*
```

- [ ] **Step 2: Update the `--selftest` "ok" fixture** to include the two new rows so the complete-set passes. In the selftest's `ok` tree `printf`, append the two rows:
```
| **SAST** *(first-party code)* | x |
| **License compliance** *(when an SBOM is produced)* | x |
```
(The "gap" fixture — which omits Accessibility — still correctly FAILs; no change needed there.)

- [ ] **Step 3: Run the selftest**

Run: `sh conformance/conditional-gates.sh --selftest`
Expected: `OK: conditional-gates selftest` (gap detected; complete set — now five rows — passes).

- [ ] **Step 4: dash-clean + commit**

Run: `dash -n conformance/conditional-gates.sh && echo dash-clean`
```bash
git add conformance/conditional-gates.sh
git commit -m "feat(conformance): conditional-gates names SAST + license rows (SP-1)"
```

---

## Task 4: Core-doc rows — §7 table + §14 sentence (budget-checked)

**Files:** Modify `DEVELOPMENT-PROCESS.md`, `DEVELOPMENT-STANDARDS.md`

- [ ] **Step 1: Add the two §7 conditional-gate rows**

In `DEVELOPMENT-PROCESS.md` §7, in the conditional-gate table (where the `**Accessibility** *(user-facing UI)*` / `**Eval gate** *(AI features)*` rows live), add directly after the Eval gate row:
```markdown
| **SAST** *(first-party code)* | Does static analysis of our own code pass — no high-severity injection / auth-bypass / SSRF / unsafe-deserialization findings? (`docs/operations/security-scanning.md`) | Builder + reviewer |
| **License compliance** *(when an SBOM is produced)* | Do dependency licenses pass policy — no denylisted copyleft in a proprietary build; undetermined ones reviewed? (`scripts/license-check.sh`) | Builder + reviewer |
```

- [ ] **Step 2: Verify PROCESS budget**

Run: `sh conformance/doc-budget.sh`
Expected: `PASS: DEVELOPMENT-PROCESS.md 470/470 lines` (or below) and `OK: core docs within budget`. **If it reports >470**, compress the two rows' descriptions (shorten the question text) until ≤470, re-run.

- [ ] **Step 3: Add a §14 conditional-gates sentence**

In `DEVELOPMENT-STANDARDS.md` §14, find the "Conditional gates (a11y / load / eval)" paragraph and **append to its existing sentence** (a `+0`-friendly extension; do not add a new line if avoidable):
` Two further conditional gates — **SAST** (first-party static analysis; Semgrep/CodeQL) and **license compliance** (`scripts/license-check.sh` over the SBOM) — apply on the same N/A-with-reason basis (`docs/operations/security-scanning.md`).`

- [ ] **Step 4: Verify STANDARDS budget + links**

Run: `sh conformance/doc-budget.sh && sh conformance/check-links.sh`
Expected: STANDARDS ≤320; links OK. (If STANDARDS would exceed 320, move the sentence wholesale into `security-scanning.md` and leave only `→ docs/operations/security-scanning.md` appended to the existing line.)

- [ ] **Step 5: Commit**

```bash
git add DEVELOPMENT-PROCESS.md DEVELOPMENT-STANDARDS.md
git commit -m "docs: name SAST + license conditional gates in §7/§14 (budget-safe)"
```

---

## Task 5: `docs/operations/security-scanning.md` (the bulk + upgrade ladder)

**Files:** Create `docs/operations/security-scanning.md`

- [ ] **Step 1: Create the file**

```markdown
# Security Scanning — SAST & License Compliance

Two **conditional** gates (the a11y/load/eval family — first-class but trigger-bound,
N/A-with-reason). They sit alongside the universal `gate-secret-scan` and `gate-dep-scan`:
secret-scan finds committed secrets, dep-scan finds *known-vulnerable dependencies*, and
these two add **first-party code analysis** and **license policy**.

## SAST — `gate-sast` (trigger: first-party application code)

Static analysis of *your own* code for injection, auth-bypass, SSRF, unsafe deserialization,
and similar patterns — the class `gate-dep-scan` (deps) and `gate-secret-scan` (secrets) miss.

- **Reference tool: Semgrep** (multi-language, OSS) — `semgrep --config auto --error`. Portable default.
- **Alternative: CodeQL** (GitHub-native code scanning) where the repo is on GitHub Advanced Security.
- **N/A-with-reason** for a repo with no first-party application code (pure IaC modules, docs).
- **Honesty:** a green `gate-sast` proves the scan ran with no findings above the configured
  severity — not that the code is secure. Tune rulesets per project; triage findings, don't suppress.

## License compliance — `gate-license` (trigger: an SBOM is produced)

The kit already emits a CycloneDX SBOM (`gate-sbom`). `gate-license` **acts on it**:
`scripts/license-check.sh --sbom <sbom.json>` flags denylisted strong-copyleft licenses
(default: `AGPL`, `GPL`, `SSPL`, `OSL`, `EUPL`, `CC-BY-NC` — the anchor deliberately excludes
weak-copyleft `LGPL`) and **counts undetermined / NOASSERTION components**, which it surfaces
for review rather than silently passing. Override the policy with `--policy <file>` (a newline
list of anchored SPDX patterns); make undetermined a hard failure with `--strict`.

### Stack-neutral by default — and its blind spot

The SBOM-based check is uniform across all stacks and reuses output you already produce, but the
SBOM can emit `NOASSERTION` / incomplete license fields. The check **tells you** when it hits
this (`N component(s) have undetermined licenses … see per-stack upgrade`). It is
**necessary, not sufficient** — it clears declared licenses against policy; it is not a legal
clearance.

### Per-stack upgrade ladder (higher fidelity — contract-preserving)

When you need stronger license detection, replace the default implementation with your stack's
native tool **but keep the same `gate-license` id and the same policy intent**, so conformance
still passes (the kit's "rewrite the reference, keep the contract" rule):

| Stack | Higher-fidelity native tool |
|-------|------------------------------|
| typescript-node | `license-checker` / `license-compliance` |
| python · ml · data-engineering | `pip-licenses` |
| go | `go-licenses` |
| rust | **`cargo-deny`** (license + advisory + ban in one) |
| java-spring · kotlin | `license-maven-plugin` / `gradle-license-report` |
| dotnet | `nuget-license` |
| terraform | mostly N/A (providers, not libraries) |

### When to upgrade (concrete triggers)
1. The default repeatedly reports undetermined-license components.
2. A strict / audited legal license-compliance obligation.
3. Shipping a proprietary product with copyleft exposure.
4. You need build-graph scoping (allow a dev-only copyleft tool, deny it at runtime).
```

- [ ] **Step 2: Links + commit**

Run: `sh conformance/check-links.sh`
Expected: links OK.
```bash
git add docs/operations/security-scanning.md
git commit -m "docs(operations): security-scanning — SAST + license + per-stack upgrade ladder"
```

---

## Task 6: Per-stack reference line in all 10 profiles + `_TEMPLATE`

**Files:** Modify `profiles/_TEMPLATE.md` and all of `profiles/{typescript-node,python,go,rust,java-spring,kotlin,dotnet,ml,data-engineering,terraform}.md`

Add **one bullet** to each profile's **§5 Security implementation** section (the MAINTAINING cross-cutting rule — must reach all). The SAST tool name varies per stack; the license line is identical.

- [ ] **Step 1: Add the bullet to each profile**

The canonical bullet (substitute the per-stack SAST tool from the table below):
```markdown
- **Static analysis & licenses (conditional gates — `docs/operations/security-scanning.md`):** SAST via **<SAST-TOOL>** (`gate-sast`); license policy via `scripts/license-check.sh` over the CycloneDX SBOM (`gate-license`, stack-neutral default — upgrade per the ladder if needed).
```

Per-stack `<SAST-TOOL>`:
| Profile | SAST tool |
|---------|-----------|
| typescript-node | Semgrep (or CodeQL) |
| python · ml · data-engineering | Semgrep + `bandit` |
| go | Semgrep + `gosec` (already via golangci-lint) |
| rust | Semgrep + `cargo-auditable`/clippy security lints |
| java-spring · kotlin | Semgrep (or CodeQL) |
| dotnet | Semgrep (or CodeQL) |
| terraform | Checkov/Trivy already cover IaC SAST — **`gate-sast` = the existing policy gate; mark `gate-license` N/A (providers, not libs)** |

For `terraform.md`, phrase the bullet to say SAST is satisfied by the existing Checkov/Trivy policy gate and license is N/A.

- [ ] **Step 2: Verify completeness + links**

Run: `sh conformance/profile-completeness.sh 2>&1 | tail -1 && sh conformance/check-links.sh 2>&1 | tail -1`
Expected: profiles complete; links OK.

- [ ] **Step 3: Commit**

```bash
git add profiles/
git commit -m "docs(profiles): per-stack SAST + license reference line (all 10 + _TEMPLATE)"
```

---

## Task 7: Reference `gate-sast` + `gate-license` steps in the typescript-node ci.yml

**Files:** Modify `profiles/typescript-node/ci.yml`

`profiles/*/ci.yml` is agent-editable (only the kit's own `.github/workflows/ci.yml` is guarded). Add the two conditional-gate steps to the reference profile (the others follow the same pattern; document that, don't necessarily edit all 10 ci.yml in this slice).

- [ ] **Step 1: Add the steps after the SBOM step**

In `profiles/typescript-node/ci.yml`, after the `Generate SBOM (CycloneDX)` step (`id: gate-sbom`), add:
```yaml
      - name: SAST (Semgrep)
        id: gate-sast
        uses: returntocorp/semgrep-action@v1
        with:
          config: auto

      - name: License policy (over the SBOM)
        id: gate-license
        run: sh scripts/license-check.sh --sbom sbom.json
```
(NOTE: `scripts/license-check.sh` is a kit script; in an adopter repo it is vendored or replaced per the upgrade ladder. This reference step documents the gate-id + invocation shape.)

- [ ] **Step 2: Confirm the gate-ids are present (informational — ci-gates.sh checks only the 8 universal)**

Run: `sh conformance/ci-gates.sh profiles/typescript-node/ci.yml`
Expected: still OK (the 8 universal gates intact; the 2 conditional gate-ids are additive and don't break it).

- [ ] **Step 3: Commit**

```bash
git add profiles/typescript-node/ci.yml
git commit -m "feat(profiles): reference gate-sast + gate-license steps (typescript-node)"
```

---

## Task 8: Wire `license-check.sh --selftest` into verify.sh + registry/audit rows

**Files:** Modify `conformance/verify.sh`, `conformance/README.md`, `conformance/audit-evidence-checklist.md`

- [ ] **Step 1: Add a control-check row to verify.sh**

In `conformance/verify.sh`, after the `check control image-supply` row, add:
```sh
check control license-check    sh scripts/license-check.sh --selftest
```
(The `--selftest` is deterministic and self-contained — a control check, like the other selftests.)

- [ ] **Step 2: Run the aggregate**

Run: `sh conformance/verify.sh 2>&1 | grep -E "license-check|RESULT"`
Expected: `[control] license-check PASS` and `RESULT: OK`.

- [ ] **Step 3: Registry + audit rows**

In `conformance/README.md`, add `license-check.sh` to the table (and `conditional-gates.sh` already covers SAST/license naming). In `conformance/audit-evidence-checklist.md`, add rows:
```markdown
| SAST gate ran (first-party code) | `gate-sast` (Semgrep/CodeQL) | Auto | CI run log |
| License policy applied | `scripts/license-check.sh` | Auto | gate-license CI step |
| Undetermined licenses reviewed | operator evidence | Manual | upgrade per ladder if needed |
```

- [ ] **Step 4: Links + commit**

Run: `sh conformance/check-links.sh && sh conformance/verify.sh | tail -3`
```bash
git add conformance/verify.sh conformance/README.md conformance/audit-evidence-checklist.md
git commit -m "feat(conformance): wire license-check selftest + registry/audit rows (SP-1)"
```

---

## Task 9: Prepare the control-plane CI smoke (hand-apply for Bradley)

**Files:** Hand-apply (Bradley): `.github/workflows/ci.yml`

- [ ] **Step 1: Produce the exact step** (next to the existing conditional-gates / scorecard smokes):
```yaml
      - name: License-check selftest (SBOM license gate)
        run: sh scripts/license-check.sh --selftest
```
- [ ] **Step 2: Surface it in the PR body** with the `KIT_GUARD_SELFEDIT=1 git add … ; git commit` apply commands (clean block, **no `#` comment lines**). *(No repo change in this task.)*

---

## Task 10: Final verification + independent review + PR

- [ ] **Step 1: Full sweep**
```bash
sh scripts/license-check.sh --selftest
sh conformance/conditional-gates.sh --selftest
dash -n scripts/license-check.sh && echo dash-clean
sh conformance/check-links.sh
sh conformance/doc-budget.sh
sh conformance/verify.sh | tail -3
```
Expected: selftests OK; dash-clean; links OK; doc-budget OK (PROCESS ≤470, STANDARDS ≤320); `verify.sh` RESULT: OK.

- [ ] **Step 2: Independent review (security-owner lens — builder ≠ sole reviewer).** Focus: (a) the deny-regex anchor truly excludes LGPL while catching GPL/AGPL (test more licenses: `GPL-2.0-or-later`, `AGPL-3.0`, `LGPL-2.1`, `MPL-2.0`, dual `MIT OR Apache-2.0`); (b) undetermined is surfaced not silently passed, and exit codes are right (violation→1, undetermined-only→0 unless --strict); (c) honesty wording (scan ran ≠ secure/cleared); (d) doc-budget held; (e) the upgrade ladder is contract-preserving (same gate-id).

- [ ] **Step 3: Address findings, then PR**
```bash
git push -u origin feature/secpriv-arc
gh pr create --title "feat(security): SP-1 — SAST + license conditional gates" --body "<summary + conditional-gate model + self-flagging/upgrade-ladder + Task-9 control-plane snippet + merge command>"
```
Report the PR number + `gh pr merge <n> --squash --admin --delete-branch`. **Do not self-merge.**

---

## Self-review (plan author)
- **Spec coverage:** SP-1 SAST gate → Tasks 3/4/5/6/7. SP-1 license gate (tool) → Tasks 1/2; self-flagging → Task 2 (REVIEW message) + selftest; upgrade ladder + when-to-upgrade → Task 5; conditional-gate wiring → Tasks 3/4; per-stack reach → Task 6; verify/registry → Task 8; CI smoke → Task 9. Honesty wording → Tasks 2/5. **No gaps.**
- **Placeholder scan:** `<SAST-TOOL>` is a substitution table (Task 6), not a placeholder gap — concrete per-stack values given. No banned patterns.
- **Consistency:** gate-ids `gate-sast`/`gate-license`, the deny-regex, and the marker strings (`SAST** *(first-party code)*`, `License compliance** *(when an SBOM is produced)*`) are identical across Tasks 2/3/4/8.
