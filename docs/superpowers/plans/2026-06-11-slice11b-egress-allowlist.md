# Slice 11b — Egress-allowlist reference + conformance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a default-deny network-egress reference + a three-state `conformance/egress-policy.sh` that verifies the platform egress control is *declared and attested-wired* — the honest W2 close, never an in-process egress guard.

**Architecture:** `egress-policy.sh` composes two existing kit patterns: `resilience-ready.sh`'s deploy-surface detection + RUNBOOK-record + placeholder-rejection, and `branch-protection.sh`'s three-state (exit 0 PASS/N-A · 1 FAIL · 2 UNVERIFIED, escalating to FAIL under CI/`--require`). The reference doc + RUNBOOK attestation line + crosswalk row-move are docs. Only `.github/workflows/ci.yml` is control-plane (human `cp`).

**Tech Stack:** POSIX `sh` (dash-clean), `grep -E`, `mktemp` fixtures. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-06-11-slice11b-egress-allowlist-design.md`

**Honesty invariant:** the check never inspects traffic. PASS = declared + attested; UNVERIFIED is a first-class non-pass; live-blocking is a Manual row. Crosswalk → Kit-assisted, never Kit-enforced.

---

## File structure

| File | Responsibility | Control-plane? |
|------|----------------|----------------|
| `conformance/egress-policy.sh` | NEW — the three-state check + `--selftest` corpus | no (edit directly) |
| `conformance/egress-readiness.md` | NEW — Auto vs Manual checklist (what a green run does/doesn't prove) | no |
| `docs/operations/egress-control.md` | NEW — the reference (k8s NetworkPolicy concrete + cloud/proxy patterns + how to attest) | no |
| `templates/RUNBOOK-TEMPLATE.md` | MODIFY — add the egress attestation line the script keys on | no |
| `docs/enterprise/compliance-crosswalk.md` (+ `conformance/audit-evidence-checklist.md`) | MODIFY — egress row Org-owned → Kit-assisted | no |
| `docs/enterprise/platform-safety-boundary.md` | MODIFY — note egress now reference-shipped + verify-wired | no |
| `conformance/README.md` | MODIFY — index row | no |
| `.github/workflows/ci.yml` | MODIFY — `egress-policy.sh --selftest` step | **YES — human `cp`** |
| `VERSION` · `CHANGELOG.md` · `docs/ROADMAP-SLICE11.md` | MODIFY — release v2.41.0 | no |

Branch: `feature/slice-11b-egress-allowlist` (already created, off latest main). The spec is already committed on it.

---

## Task 1: `conformance/egress-policy.sh` (the three-state check + selftest)

**Files:**
- Create: `conformance/egress-policy.sh`

The conformance corpus IS the test (the kit's established pattern — `agent-autonomy.sh`, `mcp-policy.sh`, `resilience-ready.sh` all self-test). We write the full script including its `--selftest` battery, then run `--selftest` as the test.

- [ ] **Step 1: Write the full script.**

```sh
#!/bin/sh
# egress-policy.sh — conditional, three-state default-deny-egress wiring check (Slice 11b).
#
# The honest W2 close. Interpreter/DNS/build-tool exfil has NO reliable command signature
# (A8 Part 2), so the kit does NOT gate egress in-process. Instead it ships a default-deny
# network-egress REFERENCE (docs/operations/egress-control.md) and this check verifies the
# PLATFORM control is DECLARED and ATTESTED-wired — it never inspects or blocks traffic.
#
# THREE-STATE (mirrors branch-protection.sh):
#   exit 0 — PASS (declared + attested enforced) OR N/A (no network surface / RUNBOOK N/A)
#   exit 1 — FAIL (networked project declares NO egress control)
#   exit 2 — UNVERIFIED (declared but not attested enforced) — NOT a pass.
# Escalation: under CI (CI env set) or --require, UNVERIFIED (declared-not-attested) becomes
# exit 1 — in a gate the control must be attested, not merely declared.
#
# DECLARED  = an in-repo egress manifest (a YAML with `kind: NetworkPolicy` + `Egress`) in a
#             conventional location, OR a RUNBOOK "Network egress:" line naming a mechanism
#             (NetworkPolicy / cloud egress firewall / forward proxy).
# ATTESTED  = the RUNBOOK "Network egress:" line records `enforced: <ISO date>` (not the
#             [date] placeholder).
#
# SCOPE — a green run proves egress is DECLARED + ATTESTED, NOT that traffic is actually
# blocked (that is a Manual row in egress-readiness.md — platform/operator evidence). A
# committed NetworkPolicy proves intent, not enforcement; the RUNBOOK attestation is the
# authoritative "wired" signal. A green run is necessary, not sufficient.
#
# Usage:
#   sh conformance/egress-policy.sh [project-dir] [--require]   (default dir: .)
#   sh conformance/egress-policy.sh --selftest
#
# Run at the deploy/security gate (DEVELOPMENT-PROCESS.md §7); also self-tested in kit CI.
set -eu

REQUIRE="${REQUIRE:-0}"
[ -n "${CI:-}" ] && REQUIRE=1
DIR=.
for a in "$@"; do
  case "$a" in
    --require)  REQUIRE=1 ;;
    --selftest) ;;  # dispatched below
    -*) echo "usage: egress-policy.sh [project-dir] [--require] | --selftest" >&2; exit 2 ;;
    *)  DIR="$a" ;;
  esac
done

# Does $1 (a workflow file) indicate a deploy surface? (Same signals as resilience-ready.sh.)
wf_is_deploy() {
  _wf="$1"
  if grep -Eq '^[[:space:]]*environment:' "$_wf"; then return 0; fi
  if grep -Eq '^[[:space:]]+deploy[A-Za-z0-9_-]*:[[:space:]]*$' "$_wf"; then return 0; fi
  return 1
}

# In-repo egress manifest in a conventional location? (NetworkPolicy declaring Egress.)
# Bounded glob (not a full-tree find) — manifests elsewhere rely on the RUNBOOK attestation,
# which is the authoritative signal anyway.
has_egress_manifest() {
  _d="$1"
  for f in "$_d"/*.yaml "$_d"/*.yml \
           "$_d"/k8s/*.yaml "$_d"/k8s/*.yml \
           "$_d"/deploy/*.yaml "$_d"/deploy/*.yml \
           "$_d"/manifests/*.yaml "$_d"/manifests/*.yml; do
    [ -f "$f" ] || continue
    if grep -qiE 'kind:[[:space:]]*NetworkPolicy' "$f" 2>/dev/null && grep -qi 'Egress' "$f" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

check_dir() {
  dir="$1"

  # 1. deploy/network surface? (no surface -> N/A skip-pass)
  deployable=0
  if [ -f "$dir/Dockerfile" ]; then deployable=1; fi
  if [ "$deployable" -eq 0 ] && [ -d "$dir/.github/workflows" ]; then
    for wf in "$dir"/.github/workflows/*.yml "$dir"/.github/workflows/*.yaml; do
      [ -f "$wf" ] || continue
      if wf_is_deploy "$wf"; then deployable=1; break; fi
    done
  fi
  if [ "$deployable" -eq 0 ]; then
    echo "N/A: $dir has no deploy/network surface (no Dockerfile / deploy workflow) — nothing to egress-gate"
    return 0
  fi

  rb="$dir/RUNBOOK.md"

  # 2. explicit N/A escape (a deployable with genuinely no outbound network)
  if [ -f "$rb" ] && grep -Eiq 'network egress:[[:space:]]*n/?a' "$rb"; then
    echo "N/A: $dir RUNBOOK records no outbound network (Network egress: N/A)"
    return 0
  fi

  # 3. declared? (in-repo manifest OR a RUNBOOK-named mechanism)
  declared=0
  if has_egress_manifest "$dir"; then declared=1; fi
  if [ -f "$rb" ] && grep -Eiq 'network egress:.*(networkpolicy|egress firewall|forward proxy|proxy)' "$rb"; then declared=1; fi

  if [ "$declared" -eq 0 ]; then
    echo "FAIL: $dir is networked but declares no default-deny egress control (no NetworkPolicy manifest, no RUNBOOK 'Network egress:' mechanism) — see docs/operations/egress-control.md"
    return 1
  fi

  # 4. attested-wired? (RUNBOOK 'Network egress: ... enforced: <ISO date>', not the placeholder)
  if [ -f "$rb" ] && grep -Eiq 'network egress:.*enforced:[[:space:]]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' "$rb"; then
    echo "egress-policy: OK — default-deny egress is DECLARED and ATTESTED enforced. NOTE: this does NOT verify traffic is actually blocked (Manual row in egress-readiness.md — platform/operator evidence)."
    return 0
  fi

  # 5. declared but not attested -> UNVERIFIED (escalates to FAIL under CI/--require)
  msg="$dir declares an egress control but does not ATTEST enforcement in RUNBOOK (need 'Network egress: default-deny via <mechanism> — enforced: <date>')"
  if [ "$REQUIRE" = "1" ]; then
    echo "FAIL: $msg — and attestation is required (CI/--require)."
    return 1
  fi
  echo "UNVERIFIED: $msg — declare it in docs/operations/egress-control.md terms and attest enforcement. (NOT a pass.)"
  return 2
}

# mktemp fixtures; assert each outcome. Fixtures LEFT in place (no rm -rf; 7e guard).
selftest() {
  st_fail=0
  base=$(mktemp -d)

  # helper: run check_dir in a subshell, capture exact exit code (1 vs 2 matter)
  rc_of() { ( check_dir "$1" ) >/dev/null 2>&1 && echo 0 || echo $?; }
  # Each fixture overrides REQUIRE in its OWN subshell so the global CI-derived REQUIRE=1
  # (the kit's CI runs --selftest!) never leaks in and turns an expected UNVERIFIED(2) into
  # FAIL(1). Use the ';'-separated assignment (not the VAR=val prefix form) so REQUIRE
  # persists into the nested check_dir subshell. Only fixture 8 sets REQUIRE=1 (escalation).
  expect() { # label dir want [require]
    _lbl="$1"; _dir="$2"; _want="$3"; _req="${4:-0}"
    _got=$( REQUIRE="$_req"; rc_of "$_dir" )
    if [ "$_got" = "$_want" ]; then echo "selftest PASS: $_lbl -> exit $_got"; else echo "selftest FAIL: $_lbl want $_want got $_got"; st_fail=1; fi
  }

  # 1. no surface -> N/A (0)
  d="$base/na-nosurface"; mkdir -p "$d"; printf '# a CLI tool\n' > "$d/README.md"
  expect "no-surface -> N/A" "$d" 0

  # 2. deployable + RUNBOOK explicit N/A -> N/A (0)
  d="$base/na-explicit"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n- Network egress: N/A — no outbound network\n' > "$d/RUNBOOK.md"
  expect "explicit N/A -> N/A" "$d" 0

  # 3. networked, nothing declared -> FAIL (1)
  d="$base/fail-bare"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n- (no egress record)\n' > "$d/RUNBOOK.md"
  expect "networked-bare -> FAIL" "$d" 1

  # 4. manifest present, no attestation -> UNVERIFIED (2)
  d="$base/unv-manifest"; mkdir -p "$d/k8s"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf 'kind: NetworkPolicy\nspec:\n  policyTypes:\n    - Egress\n' > "$d/k8s/np.yaml"
  printf '# RUNBOOK\n## Deploy\n- (egress not yet attested)\n' > "$d/RUNBOOK.md"
  expect "manifest-no-attest -> UNVERIFIED" "$d" 2

  # 5. RUNBOOK names mechanism but [date] placeholder -> UNVERIFIED (2)
  d="$base/unv-placeholder"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n- Network egress: default-deny via forward proxy — enforced: [date]\n' > "$d/RUNBOOK.md"
  expect "mechanism+placeholder -> UNVERIFIED" "$d" 2

  # 6. manifest + dated attestation -> PASS (0)
  d="$base/pass-manifest"; mkdir -p "$d/k8s"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf 'kind: NetworkPolicy\nspec:\n  policyTypes:\n    - Egress\n' > "$d/k8s/np.yaml"
  printf '# RUNBOOK\n## Deploy\n- Network egress: default-deny via k8s NetworkPolicy — enforced: 2026-06-01\n' > "$d/RUNBOOK.md"
  expect "manifest+attest -> PASS" "$d" 0

  # 7. no manifest, mechanism + dated attestation -> PASS (cloud/proxy path) (0)
  d="$base/pass-cloud"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n- Network egress: default-deny via cloud egress firewall — enforced: 2026-06-01\n' > "$d/RUNBOOK.md"
  expect "cloud-mechanism+attest -> PASS" "$d" 0

  # 8. escalation: fixture 5 under CI/--require -> FAIL (1)
  expect "declared-not-attested + require -> FAIL" "$base/unv-placeholder" 1 1

  if [ "$st_fail" -ne 0 ]; then echo "egress-policy --selftest: FAIL" >&2; return 1; fi
  echo "egress-policy --selftest: OK (na/explicit-na/bare-fail/manifest-unv/placeholder-unv/pass-manifest/pass-cloud/escalation all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *)          check_dir "$DIR"; exit $? ;;
esac
```

- [ ] **Step 2: Make executable, dash-check, run the selftest.**

Run: `chmod +x conformance/egress-policy.sh && dash -n conformance/egress-policy.sh && echo "syntax OK"`
Expected: `syntax OK`

Run: `sh conformance/egress-policy.sh --selftest`
Expected: 8 `selftest PASS` lines, then `egress-policy --selftest: OK ...`, exit 0.

- [ ] **Step 3: Verify the live kit root is N/A (the kit has no deploy surface).**

Run: `sh conformance/egress-policy.sh; echo "exit=$?"`
Expected: `N/A: . has no deploy/network surface ...` and `exit=0`.

- [ ] **Step 4: Commit.**

```bash
git add conformance/egress-policy.sh
git commit -m "feat(conformance): 11b — egress-policy.sh three-state default-deny-egress wiring check"
```

---

## Task 2: `conformance/egress-readiness.md` (the Auto-vs-Manual checklist)

**Files:**
- Create: `conformance/egress-readiness.md`

- [ ] **Step 1: Write the checklist** (mirrors `resilience-readiness.md`'s structure — Auto rows the script proves, Manual rows it can't):

```markdown
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
```

- [ ] **Step 2: Add the `conformance/README.md` index row.** After the `resilience-ready.sh` row (anchor), add:

```markdown
| `egress-policy.sh` | script | Slice 11b — default-deny network egress is declared + attested-wired (three-state; UNVERIFIED-honest; never inspects traffic). Pairs with `egress-readiness.md` / `../docs/operations/egress-control.md` | Review / CI (conditional on a network surface) |
```

- [ ] **Step 3: Link-check + commit.**

Run: `sh conformance/check-links.sh 2>&1 | tail -1`
Expected: `OK: all relative Markdown links resolve`

```bash
git add conformance/egress-readiness.md conformance/README.md
git commit -m "docs(conformance): 11b — egress-readiness checklist (Auto vs Manual) + README index row"
```

---

## Task 3: `docs/operations/egress-control.md` (the reference)

**Files:**
- Create: `docs/operations/egress-control.md`

- [ ] **Step 1: Write the reference doc** (the paved road + patterns + how to attest):

````markdown
# Network egress control (default-deny) — reference

How to make the kit's stated platform control #1 real: **default-deny outbound network, allow only DNS + package registries + your required APIs.** This is the only reliable defense against the interpreter / DNS / build-tool exfiltration tail (`../superpowers/reviews/2026-06-10-A8-mcp-egress-attack-surface.md` Part 2) — an un-allowlisted destination simply does not connect, regardless of whether the socket came from `curl`, `python -c`, `/dev/tcp`, or a DNS lookup.

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
````

- [ ] **Step 2: Link-check + commit.**

Run: `sh conformance/check-links.sh 2>&1 | tail -1`
Expected: `OK: all relative Markdown links resolve`

```bash
git add docs/operations/egress-control.md
git commit -m "docs(operations): 11b — default-deny network-egress reference (k8s paved road + cloud/proxy patterns)"
```

---

## Task 4: RUNBOOK template attestation line

**Files:**
- Modify: `templates/RUNBOOK-TEMPLATE.md`

- [ ] **Step 1: Inspect the deploy/monitoring sections** to find the right home for the egress line.

Run: `grep -n '^##\|Load/soak tested' templates/RUNBOOK-TEMPLATE.md`
Expected: section headings incl. `## 4. Deploy` and `## 8. Monitoring & alerting` with a `Load/soak tested: [date]` line.

- [ ] **Step 2: Add the egress attestation line under `## 4. Deploy`** (general bullet, applies to all targets — k8s, cloud-firewall, proxy). Insert it immediately after the `- Smoke test: …` bullet and **before** the `**Container / Kubernetes deploy (if applicable):**` subsection:

```markdown
- Network egress: default-deny via [k8s NetworkPolicy | cloud egress firewall | forward proxy] — enforced: [date]  <!-- The only reliable exfiltration defense (`docs/operations/egress-control.md`); verified declared+attested by `conformance/egress-policy.sh`. If no outbound network, replace this entire line with: N/A — [reason] -->
```

(The literal phrase `Network egress:` + `enforced: [date]` must match `egress-policy.sh`'s greps exactly — keep them in sync, same discipline as the §8 resilience line. **Do NOT put the literal `Network egress: N/A` inside the comment** — the script's N/A-escape grep would match it and the template would read as N/A instead of the required UNVERIFIED. Phrase the N/A guidance without that prefix.)

- [ ] **Step 3: Verify the template parses against the check** (a fresh template should read as UNVERIFIED — placeholder `[date]`, not a false PASS):

```bash
tmp=$(mktemp -d); printf 'FROM scratch\n' > "$tmp/Dockerfile"; cp templates/RUNBOOK-TEMPLATE.md "$tmp/RUNBOOK.md"
sh conformance/egress-policy.sh "$tmp"; echo "exit=$?"
```
Expected: `UNVERIFIED: ...` and `exit=2` (the template names a mechanism but holds the `[date]` placeholder — correctly not a pass).

- [ ] **Step 4: Link-check + commit.**

Run: `sh conformance/check-links.sh 2>&1 | tail -1`

```bash
git add templates/RUNBOOK-TEMPLATE.md
git commit -m "docs(templates): 11b — RUNBOOK egress attestation line (keyed by egress-policy.sh)"
```

---

## Task 5: Crosswalk + audit-evidence + boundary note (Org-owned → Kit-assisted)

**Files:**
- Modify: `docs/enterprise/compliance-crosswalk.md`
- Modify: `conformance/audit-evidence-checklist.md`
- Modify: `docs/enterprise/platform-safety-boundary.md`

- [ ] **Step 1: Find the egress row in the crosswalk.**

Run: `grep -niE 'egress|network.egress|exfil' docs/enterprise/compliance-crosswalk.md conformance/audit-evidence-checklist.md docs/enterprise/platform-safety-boundary.md`
Expected: at least one egress/exfil row in the crosswalk + the boundary doc's control #1.

- [ ] **Step 2: Update the crosswalk egress row** (line ~36). Replace the existing row:

```markdown
| Agent/runtime platform boundary · network-egress allowlist | `docs/enterprise/platform-safety-boundary.md` | CC6.6, CC6.7 | A.8.20 (networks security), A.8.21 (security of network services), A.8.22 (segregation of networks), A.8.23 (web filtering) | PO.5 | egress policy, deny-by-default network config | Org-owned |
```
with (evidence cell now cites the reference + check; owner Org-owned → **Kit-assisted**):
```markdown
| Agent/runtime platform boundary · network-egress allowlist | `docs/enterprise/platform-safety-boundary.md` · `../operations/egress-control.md` | CC6.6, CC6.7 | A.8.20 (networks security), A.8.21 (security of network services), A.8.22 (segregation of networks), A.8.23 (web filtering) | PO.5 | default-deny egress reference + RUNBOOK attestation, verified by `conformance/egress-policy.sh` | Kit-assisted |
```
(Enforcement is still platform-owned — Kit-assisted = reference shipped + wiring verified, not Kit-enforced. Do NOT change the boundary statement.)

- [ ] **Step 3: Add an audit-evidence row.** `conformance/audit-evidence-checklist.md` has no egress row yet. Add one immediately after the `Container image supply-chain (if service image)` row (keeping conditional rows together), matching the table's column format `| Control | Crosswalk ref | Evidence artifact | Check | Present? |`:

```markdown
| Network egress · default-deny allowlist (if networked) | CC6.6, CC6.7 / A.8.20–A.8.23 / PO.5 | egress reference + RUNBOOK attestation (declared + wired) | **Auto (conditional):** `sh conformance/egress-policy.sh` | |
```

- [ ] **Step 4: Add the boundary note.** In `docs/enterprise/platform-safety-boundary.md`, on control #1 (network-egress allowlist), append one sentence: ` The kit now ships a default-deny reference (docs/operations/egress-control.md) and verifies it is declared + attested (conformance/egress-policy.sh) — enforcement remains platform-owned.` Do NOT weaken the "this is the REAL boundary / platform-owned" framing.

- [ ] **Step 5: Link-check + commit.**

Run: `sh conformance/check-links.sh 2>&1 | tail -1`

```bash
git add docs/enterprise/compliance-crosswalk.md conformance/audit-evidence-checklist.md docs/enterprise/platform-safety-boundary.md
git commit -m "docs(enterprise): 11b — egress row Org-owned -> Kit-assisted (reference shipped + wiring verified)"
```

---

## Task 6: CI wiring (control-plane `cp`) + post-`cp` verify

**Files:**
- Modify: `.github/workflows/ci.yml` (control-plane — human `cp`)

- [ ] **Step 1: Build the CI candidate.** Read `.github/workflows/ci.yml`; write `/tmp/ci.yml.11b` = the live file with one step added to the `conformance` job after the `Resilience-ready self-test ...` step (a stable anchor):

```yaml
      - name: Egress-policy self-test (declared/attested three-state)
        run: sh conformance/egress-policy.sh --selftest
```

Validate:
```bash
diff .github/workflows/ci.yml /tmp/ci.yml.11b
```
Expected: only the two added lines.
```bash
ruby -ryaml -e 'd=YAML.load_file("/tmp/ci.yml.11b"); puts d["jobs"].keys.join(",")' 2>/dev/null || grep -E '^  [a-z-]+:$' /tmp/ci.yml.11b
```
Expected: `conformance,bootstrap,docs-links`.

- [ ] **Step 2: Hand Bradley the control-plane `cp`** (self-edit flag; the guard denies the agent writing `.github/workflows/`). Present exactly:

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit && KIT_GUARD_SELFEDIT=1 sh -c '
  cp /tmp/ci.yml.11b .github/workflows/ci.yml &&
  git add .github/workflows/ci.yml &&
  git commit -m "ci(11b): run egress-policy.sh --selftest in the conformance job"
'
```
Wait for confirmation before continuing.

---

## Task 7: Release (VERSION / CHANGELOG / roadmap)

**Files:**
- Modify: `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE11.md`, `README.md` (badge)

- [ ] **Step 1: `VERSION`** → `2.41.0`.

```bash
printf '2.41.0\n' > VERSION
```

- [ ] **Step 2: Badge sync.**

Run: `sh conformance/badge-version.sh --fix && sh conformance/badge-version.sh; echo "exit=$?"`
Expected: `PASS: README badge v2.41.0 matches VERSION 2.41.0`, exit 0.

- [ ] **Step 3: CHANGELOG** — add above the top entry:

```markdown
## [2.41.0] - 2026-06-11

Egress-allowlist reference + conformance (Slice 11b — Containment arc, the honest W2). Ships a default-deny network-egress reference and verifies the platform control is declared + attested-wired. **MINOR** — conditional three-state check + reference docs; no new universal gate.

### Added
- **`docs/operations/egress-control.md`** — default-deny network-egress reference (k8s `NetworkPolicy` paved road + cloud-egress-firewall / forward-proxy patterns + how to attest).
- **`conformance/egress-policy.sh`** — three-state check (PASS declared+attested · UNVERIFIED declared-not-attested · FAIL networked-undeclared · N/A no-surface), escalating UNVERIFIED→FAIL under CI/`--require`; `--selftest` corpus; CI-wired. Pairs with `conformance/egress-readiness.md` (Auto vs Manual).
- **RUNBOOK** egress attestation line (`templates/RUNBOOK-TEMPLATE.md`).

### Changed
- Compliance crosswalk + audit-evidence: egress row **Org-owned → Kit-assisted** (reference shipped + wiring verified). `platform-safety-boundary.md` notes egress is now reference-shipped + verify-wired.

### Honesty
- The check **never inspects traffic** — PASS = declared + attested, not "packets are dropped" (a Manual row). Interpreter/DNS/build-tool exfil is impossible to gate in-process (A8 Part 2); enforcement stays platform-owned. UNVERIFIED is a first-class non-pass.
```

- [ ] **Step 4: Roadmap.** In `docs/ROADMAP-SLICE11.md`, set the `11b` row Status → `✅ shipped v2.41.0` with a one-line summary.

- [ ] **Step 5: Verify + commit.**

Run: `cat VERSION && sh conformance/check-links.sh 2>&1 | tail -1`

```bash
git add VERSION README.md CHANGELOG.md docs/ROADMAP-SLICE11.md
git commit -m "chore(release): 2.41.0 — egress-allowlist reference + conformance (11b)"
```

---

## Task 8: Final verify + independent security-owner review + PR

- [ ] **Step 1: Full suite (post-`cp`, live).**

```sh
sh conformance/egress-policy.sh --selftest >/dev/null && echo "egress selftest OK"
sh conformance/egress-policy.sh >/dev/null && echo "kit-root egress N/A OK"
sh conformance/agent-autonomy.sh >/dev/null && echo "agent-autonomy OK"
sh conformance/mcp-policy.sh >/dev/null && echo "mcp-policy OK"
sh conformance/check-links.sh >/dev/null && echo "links OK"
sh conformance/badge-version.sh >/dev/null && echo "badge OK"
sh conformance/doc-budget.sh >/dev/null && echo "doc-budget OK"
sh conformance/verify.sh 2>&1 | tail -1
```
Expected: all OK; `verify.sh` RESULT: OK.

- [ ] **Step 2: Independent security-owner-lens review** (builder ≠ reviewer). Dispatch the `security-reviewer` agent against `git diff main...HEAD` with the honesty framing: confirm (a) the check never claims in-process enforcement; (b) UNVERIFIED is a true non-pass and escalates under CI/`--require`; (c) PASS cannot be reached without a dated attestation (no placeholder/false-pass); (d) the crosswalk says Kit-assisted, not Kit-enforced; (e) dash-clean, no fixture `rm -rf`. Fold any cheap, honesty-relevant findings; carry the rest explicitly.

- [ ] **Step 3: Push + open PR** (Bradley merges — agent never self-merges).

```bash
git push -u origin feature/slice-11b-egress-allowlist
gh pr create --base main --head feature/slice-11b-egress-allowlist --title "Slice 11b — Egress-allowlist reference + conformance (the honest W2; v2.41.0)" --body "<summary: closes W2 honestly — default-deny egress reference + three-state egress-policy.sh that verifies declared+attested, never inspects traffic; crosswalk Org-owned -> Kit-assisted; MINOR>"
```

- [ ] **Step 4: Report** the PR number + the merge command (`gh pr merge <n> --squash --admin --delete-branch`) and the next arc step (11c).

---

## Verification (whole slice)

- `sh conformance/egress-policy.sh --selftest` → 8 PASS, exit 0.
- `sh conformance/egress-policy.sh` at kit root → N/A, exit 0.
- Fresh RUNBOOK template → UNVERIFIED (exit 2), never a false PASS.
- `egress-policy.sh --selftest` runs in kit CI (conformance job).
- `check-links.sh`, `badge-version.sh`, `doc-budget.sh`, `verify.sh` → green.
- Crosswalk egress row = Kit-assisted (not Kit-enforced); boundary doc still says enforcement is platform-owned.
- Governance: feature branch → PR → human ratification; `ci.yml` via control-plane `cp`; security-owner lens before PR.
