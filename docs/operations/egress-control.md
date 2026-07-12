# Network egress control (default-deny) — reference

How to make the kit's stated platform control #1 real: **default-deny outbound network, allow only DNS + package registries + your required APIs.** This is the only reliable defense against the interpreter / DNS / build-tool exfiltration tail — an un-allowlisted destination simply does not connect, regardless of whether the socket came from `curl`, `python -c`, `/dev/tcp`, or a DNS lookup.

`conformance/egress-policy.sh` verifies this control is **declared and attested**; it does **not** inspect traffic. See `conformance/egress-readiness.md`.

## The principle
1. **Default-deny** all egress from agent, CI, and workload environments.
2. **Allowlist** only: DNS (53), your package registries, and the specific APIs your service calls.
3. **Attest** enforcement in the RUNBOOK (the line `egress-policy.sh` keys on).

## Kubernetes paved road (concrete)
Two policies: a default-deny-egress baseline, then an explicit allow. Apply both to the workload namespace (requires a CNI that enforces `NetworkPolicy` — Calico, Cilium, etc.).

```yaml
# 1. default-deny ALL egress in the namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: app
spec:
  podSelector: {}
  policyTypes: [Egress]
  # no egress rules => all egress denied
---
# 2. allow ONLY DNS + HTTPS to required CIDRs (replace with your registry/API ranges)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-and-apis
  namespace: app
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:                              # DNS to kube-dns
        - namespaceSelector: {}
          podSelector:
            matchLabels: { k8s-app: kube-dns }
      ports:
        - { protocol: UDP, port: 53 }
        - { protocol: TCP, port: 53 }
    - to:                              # your registries / APIs (REPLACE these CIDRs)
        - ipBlock: { cidr: 203.0.113.0/24 }
      ports:
        - { protocol: TCP, port: 443 }
```

## Non-k8s patterns
- **Cloud egress firewall:** AWS security-group **egress** rules (default-deny by attaching an SG with no egress allow, then allow specific CIDRs/prefix-lists); GCP egress firewall rules / Cloud NAT with restricted ranges; Azure NSG outbound deny + selective allow.
- **Forward-proxy allowlist:** route all outbound through an explicit-allowlist HTTP/S proxy (e.g. Squus/Envoy with a domain allowlist) and block direct egress at the network layer. Catches DNS-name-based allowlisting that CIDR rules can't.

## How to attest (what the check reads)
Record one line in `RUNBOOK.md` (deploy/security section). The phrase and date are what `egress-policy.sh` keys on:

```
Network egress: default-deny via <k8s NetworkPolicy | cloud egress firewall | forward proxy> — enforced: 2026-06-01
```

- **No outbound network at all?** Record `Network egress: N/A — <reason>` (→ N/A).
- **Declared but not yet enforced?** Leave `enforced: [date]` — the check reports **UNVERIFIED** (not a pass) until you record a real date.

## The ceiling (honest)
A committed manifest proves *intent*, not *enforcement*. PASS means declared + attested; **it does not prove packets are dropped** — verify that from inside the workload (an un-allowlisted `curl` must fail) and record it as a Manual row in `../../conformance/egress-readiness.md`. Enforcement stays platform-owned (`../enterprise/platform-safety-boundary.md` control #1).
