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
  - **The Jira adapter behind a forward proxy:** `scripts/tracker-jira.sh` honours `HTTPS_PROXY` (or `https_proxy`) and `NO_PROXY` (or `no_proxy`) for routing only. The proxy reaches curl through its stdin config, never its environment or argv, so a `user:password@` in the proxy URL stays off the process list. TLS stays end to end to the tracker host: the proxy sees the host name, not the token. CA variables (`SSL_CERT_FILE`, `CURL_CA_BUNDLE`, `SSL_CERT_DIR`) are ignored on purpose, because honouring them would let whoever sets the environment add a trust anchor; to trust an organisation's own root, add it to the system trust store. A proxy value with an unexpected byte or a scheme other than `http://` or `https://` is refused, never silently dropped. `NO_PROXY` is checked the same way, and a bad `NO_PROXY` refuses every call even when no proxy is set. Percent-encode any special character in a proxy password; IPv6 bracket literals are not accepted. `--preflight` reports `(via a proxy)` or `(direct)` on its reach line, and a refused value as a FAIL. `ALL_PROXY` and SOCKS proxies are not read. One residual remains: a TLS-inspecting proxy whose root certificate is already in the system trust store can read the traffic, including the token. That is the organisation's own interception of every tool on the machine, not a channel the adapter opens.
  - **`kit-update`'s network git behind an authenticating proxy:** the two commands that talk to the remote (the base publish push, and the shared-base `ls-remote` and `fetch`) scrub the environment's git config, so config cannot inject a credential helper or a URL rewrite. They add back only two settings from the environment's own command-scope git config, which is how a sandboxed session authenticates git to its proxy: `http.proxyAuthMethod` (the operative one), and the `credential.<proxy origin>.helper` entry scoped to the effective proxy (`https_proxy`, else `HTTPS_PROXY`; scheme, host and port), whose value may be empty (a helper-list reset). The entries are read with `git config --show-scope -z --get-regexp`; the quoted `GIT_CONFIG_PARAMETERS` format is never parsed in shell, only git's NUL-separated output is split, with any byte that could forge a record mapped out of the way first. Nothing else from the environment's git config passes: no helper for another URL, no `url.*.insteadOf`, no `core.*`, no other `http.*`. The kit never reads, stores or prints the proxy credential; git runs its own helper. If a publish fails with `Proxy CONNECT aborted` or a 407, this is the first place to look.
  - **What forwards nothing (fail-safe, today's plain scrub):** no proxy variable set; a proxy URL with no scheme, or a `socks5` one; `ALL_PROXY` alone; the proxy set as `http.proxy` in git config instead of the environment; a value containing a newline or a 0x01 byte; a credential key carrying a path or a trailing slash. Then git reaches the proxy as it did before this change. This is a code-level change; the live check from a sandboxed session is made in the cold run on the published release, not recorded here.

## How to attest (what the check reads)
Record one line in `RUNBOOK.md` (deploy/security section). The phrase and date are what `egress-policy.sh` keys on:

```
Network egress: default-deny via <k8s NetworkPolicy | cloud egress firewall | forward proxy> — enforced: 2026-06-01
```

- **No outbound network at all?** Record `Network egress: N/A — <reason>` (→ N/A).
- **Declared but not yet enforced?** Leave `enforced: [date]` — the check reports **UNVERIFIED** (not a pass) until you record a real date.

## The ceiling (honest)
A committed manifest proves *intent*, not *enforcement*. PASS means declared + attested; **it does not prove packets are dropped** — verify that from inside the workload (an un-allowlisted `curl` must fail) and record it as a Manual row in `../../conformance/egress-readiness.md`. Enforcement stays platform-owned (`../enterprise/platform-safety-boundary.md` control #1).
