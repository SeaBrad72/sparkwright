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

**SPDX expressions & multi-entry licenses (the policy, stated).** The check evaluates **every**
license entry on a component (not just the first) and splits SPDX expressions on `AND` / `OR` /
parentheses into tokens. It flags the component if **any** token is denylisted — deliberately
conservative: `Apache-2.0 AND GPL-3.0` flags (every `AND` operand binds), **and so does
`MIT OR GPL-3.0`** even though a permissive option exists. A flagging-for-review gate errs toward
surfacing, never hiding a copyleft obligation; if an `OR`-permissive alternative legitimately
clears it, record that in review (or adjust `--policy`). Weak-copyleft `LGPL` is **not** denied by
default (the anchor is `^(AGPL|GPL|…)`).

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

## DAST — dynamic application security testing (E4c)

SAST (`gate-sast`), dependency scans (`gate-dep-scan`), and image scans (`gate-image-vuln`) are all
**static** — they read code, lockfiles, and image layers. DAST tests the **running** app: it sends
real requests and inspects responses for misconfigurations, missing protections, and injection.

**The proven floor — runtime-security headers (shipped + gated).** The reference app sets four
security headers on every response (`X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`,
`Content-Security-Policy: default-src 'none'`, `Referrer-Policy: no-referrer`), and the `golden-path`
workflow **asserts them on the booted container** (locked by `conformance/runtime-security.sh`). This
is a real, deterministic runtime-security check — not a pentest.

**Full DAST — the reference pattern (opt-in).** For a real web attack surface (routes, forms, auth,
user input), wire an **OWASP ZAP baseline** scan against the deployed / preview URL. Copy-paste,
SHA-pin when you adopt it:

```yaml
  dast:
    runs-on: ubuntu-latest
    steps:
      - uses: zaproxy/action-baseline@<pin-a-sha>   # OWASP ZAP baseline
        with:
          target: ${{ env.PREVIEW_URL }}            # your deployed/preview URL (see preview-environments.md)
          # fail_action: true   # gate the PR on new alerts once you've tuned the rules
```

**Honest boundary.** The kit *proves* the runtime-security header floor on its (intentionally
trivial) reference app; **full DAST against your real surface is yours to wire** — it is a documented
reference, **not** a forced gate (a heavy ZAP run on every service would be false universality, the
trap the §14 conditional-gate framework warns against). HSTS is intentionally **not** emitted by the
reference (it terminates plain HTTP; `Strict-Transport-Security` is the TLS-terminator's
responsibility — ingress / load balancer).
