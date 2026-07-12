# Egress-readiness checklist

**Gate:** deploy/security gate (`DEVELOPMENT-PROCESS.md` §7). **Companion:** `conformance/egress-policy.sh`.
**Reference:** `docs/operations/egress-control.md`.

The honest W2 control. Interpreter/DNS/build-tool exfiltration has no reliable command signature, so the kit does **not** gate egress in-process — it verifies the **platform** default-deny-egress control is declared and attested. A green `egress-policy.sh` is **necessary, not sufficient**.

## Auto (proven by `egress-policy.sh`)
- [ ] **Declared** — an in-repo egress manifest (`kind: NetworkPolicy` + `Egress`) in a conventional location, **or** a RUNBOOK `Network egress:` line naming the mechanism (NetworkPolicy / cloud egress firewall / forward proxy).
- [ ] **Attested-wired** — the RUNBOOK `Network egress:` line records `enforced: <date>` (not the `[date]` placeholder).
- [ ] **N/A is explicit** — a deployable with no outbound network records `Network egress: N/A — <reason>`.

## Manual (the script CANNOT prove — platform/operator evidence)
- [ ] **Traffic is actually blocked** — an un-allowlisted destination genuinely fails to connect (tested from inside the workload: a `curl`/`python -c` to an un-allowlisted host times out/refuses). A committed NetworkPolicy proves intent, not enforcement.
- [ ] **The allowlist is least-privilege** — only DNS + required registries + your APIs are allowed; no `0.0.0.0/0` egress.
- [ ] **It covers the interpreter tail** — the same default-deny applies to dev/CI agent environments, not only prod (that is where the A8 §2.2 exfil tail lives).

## Honesty
PASS means egress is **declared + attested**, never that the kit verified packets are dropped. Enforcement is platform-owned (`docs/enterprise/platform-safety-boundary.md` control #1); 11b makes it **verifiable** (Kit-assisted), not Kit-enforced.
