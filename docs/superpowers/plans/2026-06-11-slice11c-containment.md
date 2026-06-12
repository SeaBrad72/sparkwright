# Slice 11c — Sandbox + scoped-credential references + conformance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a single containment reference + a conditional three-state `conformance/containment-ready.sh` that verifies the agent-containment posture (sandbox FS · scoped tokens · separate prod creds) is *declared + attested* — closing the exfiltratable-at-source surface (A8 controls #2/#3/#4) without claiming in-process enforcement.

**Architecture:** `containment-ready.sh` reuses the 11b `egress-policy.sh` idioms (deploy/integration-surface trigger, RUNBOOK attestation + optional config detection, three-state exit 0/1/2 with CI/`--require` escalation, mktemp `--selftest`, the token-anchored N/A grep from the 11b security fix). It classifies **three sub-aspects independently** (one RUNBOOK line each) and reports **overall = weakest aspect**.

**Tech Stack:** POSIX `sh` (dash-clean), `grep -E`, `mktemp` fixtures. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-06-11-slice11c-containment-design.md`

**Honesty invariant:** verifies declaration + attestation, never enforcement. PASS ≠ "the FS is actually read-only / tokens actually expire / prod creds actually unreachable" (those are Manual rows). UNVERIFIED is a first-class non-pass. Crosswalk → Kit-assisted, never Kit-enforced.

---

## File structure

| File | Responsibility | Control-plane? |
|------|----------------|----------------|
| `conformance/containment-ready.sh` | NEW — three-aspect conditional three-state check + `--selftest` | no |
| `conformance/containment-readiness.md` | NEW — Auto vs Manual checklist | no |
| `docs/operations/containment.md` | NEW — reference (sandbox FS / scoped tokens / separate prod creds patterns + how to attest) | no |
| `templates/RUNBOOK-TEMPLATE.md` | MODIFY — three attestation lines | no |
| `docs/enterprise/compliance-crosswalk.md` (rows 37/38/39) + `conformance/audit-evidence-checklist.md` | MODIFY — Org-owned → Kit-assisted | no |
| `docs/enterprise/platform-safety-boundary.md` | MODIFY — note controls #2/#3/#4 reference-shipped + verify-wired | no |
| `conformance/README.md` | MODIFY — index row | no |
| `.github/workflows/ci.yml` | MODIFY — `containment-ready.sh --selftest` step | **YES — human `cp`** |
| `VERSION` · `CHANGELOG.md` · `docs/ROADMAP-SLICE11.md` | MODIFY — release v2.42.0 | no |

Branch: `feature/slice-11c-containment` (already created off latest main; spec committed on it).

---

## Task 1: `conformance/containment-ready.sh` (the three-aspect check + selftest)

**Files:** Create `conformance/containment-ready.sh`

The conformance corpus IS the test. Write the full script including the `--selftest` battery, then run `--selftest`.

- [ ] **Step 1: Write the full script.**

```sh
#!/bin/sh
# containment-ready.sh — conditional, three-state agent-containment posture check (Slice 11c).
#
# Closes what is reachable to exfiltrate AT THE SOURCE (A8 controls #2/#3/#4): a sandboxed/
# read-only FS, scoped short-lived tokens, and separate production credentials. The kit cannot
# make a host FS read-only or expire a token, so this does NOT enforce — it ships a reference
# (docs/operations/containment.md) and verifies the posture is DECLARED + ATTESTED-wired.
#
# Three sub-aspects, each keyed on a RUNBOOK line; OVERALL = WEAKEST aspect:
#   Sandbox FS:       read-only work-tree mounts (host secrets unreachable)
#   Scoped tokens:    OIDC->role, short TTL, least-privilege
#   Prod credentials: separate + break-glass (SoD)
#
# THREE-STATE (mirrors egress-policy.sh / branch-protection.sh):
#   exit 0 — PASS (every aspect declared+attested, or N/A) OR N/A (no integration/deploy surface)
#   exit 1 — FAIL (an applicable aspect is undeclared)
#   exit 2 — UNVERIFIED (an aspect declared but not attested) — NOT a pass.
# Escalation: under CI (CI env set) or --require, UNVERIFIED becomes exit 1.
#
# Per-aspect: DECLARED = the RUNBOOK line names a mechanism (and, for Sandbox FS only, an in-repo
# read-only-mount config also counts); ATTESTED = the line records `enforced: <ISO date>` (not the
# [date] placeholder). N/A = the line records `N/A — <reason>`.
#
# SCOPE — a green run proves the posture is DECLARED + ATTESTED, NOT that the FS is actually
# read-only, tokens actually expire, or prod creds are actually unreachable (Manual rows in
# containment-readiness.md). A green run is necessary, not sufficient.
#
# Usage:
#   sh conformance/containment-ready.sh [project-dir] [--require]   (default dir: .)
#   sh conformance/containment-ready.sh --selftest
set -eu

REQUIRE="${REQUIRE:-0}"
[ -n "${CI:-}" ] && REQUIRE=1
DIR=.
for a in "$@"; do
  case "$a" in
    --require)  REQUIRE=1 ;;
    --selftest) ;;  # dispatched below
    -*) echo "usage: containment-ready.sh [project-dir] [--require] | --selftest" >&2; exit 2 ;;
    *)  DIR="$a" ;;
  esac
done

# Integration/deploy surface? (Dockerfile or any GitHub workflow — CI implies tokens to scope.)
has_surface() {
  _d="$1"
  [ -f "$_d/Dockerfile" ] && return 0
  if [ -d "$_d/.github/workflows" ]; then
    for wf in "$_d"/.github/workflows/*.yml "$_d"/.github/workflows/*.yaml; do
      [ -f "$wf" ] && return 0
    done
  fi
  return 1
}

# In-repo read-only-mount config (compose/devcontainer)? Sandbox-FS extra declaration only.
# Heuristic: can only bump an aspect FAIL->UNVERIFIED (never to PASS — PASS needs the RUNBOOK
# attestation), so a loose match here is low-risk.
has_readonly_mount_config() {
  _d="$1"
  for f in "$_d"/compose.yaml "$_d"/compose.yml "$_d"/docker-compose.yaml "$_d"/docker-compose.yml \
           "$_d"/.devcontainer/devcontainer.json "$_d"/.devcontainer/compose.yaml; do
    [ -f "$f" ] || continue
    if grep -Eiq 'read_only:[[:space:]]*true|"readOnly"[[:space:]]*:[[:space:]]*true|,readonly|readonly,' "$f" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

# classify one aspect -> echoes PASS | UNVERIFIED | FAIL | NA
#   $1 RUNBOOK path · $2 line-key (lowercase, e.g. 'sandbox fs') · $3 extra-declared (1/0)
classify_aspect() {
  _rb="$1"; _key="$2"; _extra="$3"
  _present=0; _is_na=0; _attested=0
  if [ -f "$_rb" ]; then
    # N/A token-anchored ([^[:alnum:]] is -i-safe) so 'NAS'/'native' don't read as N/A
    if grep -Eiq "$_key:[[:space:]]*n/?a([^[:alnum:]]|\$)" "$_rb"; then _is_na=1; fi
    if grep -Eiq "$_key:" "$_rb"; then _present=1; fi
    if grep -Eiq "$_key:.*enforced:[[:space:]]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" "$_rb"; then _attested=1; fi
  fi
  if [ "$_is_na" = "1" ]; then echo NA; return 0; fi
  if [ "$_present" = "0" ] && [ "$_extra" = "0" ]; then echo FAIL; return 0; fi
  if [ "$_attested" = "1" ]; then echo PASS; return 0; fi
  echo UNVERIFIED
}

check_dir() {
  dir="$1"

  if ! has_surface "$dir"; then
    echo "N/A: $dir has no integration/deploy surface (no Dockerfile / GitHub workflow) — no agent-reachable secrets or prod to contain"
    return 0
  fi

  rb="$dir/RUNBOOK.md"
  fs_extra=0
  if has_readonly_mount_config "$dir"; then fs_extra=1; fi

  s_fs=$(classify_aspect "$rb" "sandbox fs" "$fs_extra")
  s_tok=$(classify_aspect "$rb" "scoped tokens" 0)
  s_cred=$(classify_aspect "$rb" "prod credentials" 0)

  echo "  Sandbox FS:       $s_fs"
  echo "  Scoped tokens:    $s_tok"
  echo "  Prod credentials: $s_cred"

  # overall = weakest aspect: FAIL > UNVERIFIED > {PASS, NA}
  worst=PASS
  for s in "$s_fs" "$s_tok" "$s_cred"; do
    if [ "$s" = "FAIL" ]; then worst=FAIL; fi
  done
  if [ "$worst" != "FAIL" ]; then
    for s in "$s_fs" "$s_tok" "$s_cred"; do
      if [ "$s" = "UNVERIFIED" ]; then worst=UNVERIFIED; fi
    done
  fi

  case "$worst" in
    FAIL)
      echo "FAIL: $dir containment posture incomplete — an applicable aspect is undeclared. Declare all three (or N/A with reason) per docs/operations/containment.md"
      return 1 ;;
    UNVERIFIED)
      msg="$dir declares a containment aspect but does not ATTEST enforcement (need 'enforced: <date>' on each declared aspect line)"
      if [ "$REQUIRE" = "1" ]; then
        echo "FAIL: $msg — and attestation is required (CI/--require)."
        return 1
      fi
      echo "UNVERIFIED: $msg — attest enforcement in RUNBOOK. (NOT a pass.)"
      return 2 ;;
    PASS)
      echo "containment-ready: OK — Sandbox FS / Scoped tokens / Prod credentials all DECLARED + ATTESTED (or N/A). NOTE: does NOT verify the FS is actually read-only, tokens actually expire, or prod creds are actually unreachable (Manual rows in containment-readiness.md)."
      return 0 ;;
  esac
}

# mktemp fixtures; assert each outcome. Fixtures LEFT in place (no rm -rf; 7e guard).
selftest() {
  st_fail=0
  base=$(mktemp -d)

  rc_of() { ( check_dir "$1" ) >/dev/null 2>&1 && echo 0 || echo $?; }
  # Each fixture overrides REQUIRE in its OWN subshell so the global CI-derived REQUIRE=1
  # (the kit's CI runs --selftest!) never leaks in and turns an expected UNVERIFIED(2) into
  # FAIL(1). ';'-separated assignment (not VAR=val prefix) so it persists into the nested
  # check_dir subshell. Only the escalation fixture sets REQUIRE=1.
  expect() { # label dir want [require]
    _lbl="$1"; _dir="$2"; _want="$3"; _req="${4:-0}"
    _got=$( REQUIRE="$_req"; rc_of "$_dir" )
    if [ "$_got" = "$_want" ]; then echo "selftest PASS: $_lbl -> exit $_got"; else echo "selftest FAIL: $_lbl want $_want got $_got"; st_fail=1; fi
  }
  # the three dated attestation lines, reused across fixtures
  L_FS='- Sandbox FS: read-only work-tree mounts (compose read_only) — enforced: 2026-06-01'
  L_TOK='- Scoped tokens: OIDC->role, short TTL — enforced: 2026-06-01'
  L_CRED='- Prod credentials: separate + break-glass — enforced: 2026-06-01'

  # 1. no surface -> N/A (0)
  d="$base/na-nosurface"; mkdir -p "$d"; printf '# a CLI tool\n' > "$d/README.md"
  expect "no-surface -> N/A" "$d" 0

  # 2. surface, no containment section -> FAIL (1)
  d="$base/fail-bare"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n- (no containment records)\n' > "$d/RUNBOOK.md"
  expect "surface, nothing declared -> FAIL" "$d" 1

  # 3. all three declared + dated -> PASS (0)
  d="$base/pass-all"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n%s\n%s\n%s\n' "$L_FS" "$L_TOK" "$L_CRED" > "$d/RUNBOOK.md"
  expect "all three dated -> PASS" "$d" 0

  # 4. one aspect [date] placeholder -> UNVERIFIED (2)
  d="$base/unv-placeholder"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n- Sandbox FS: read-only mounts — enforced: [date]\n%s\n%s\n' "$L_TOK" "$L_CRED" > "$d/RUNBOOK.md"
  expect "one placeholder -> UNVERIFIED" "$d" 2

  # 5. Sandbox FS declared ONLY by read-only compose config (no FS RUNBOOK line),
  #    tokens+creds dated -> FS is declared-but-unattested -> UNVERIFIED (2). Isolates the config path.
  d="$base/unv-configonly"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf 'services:\n  agent:\n    read_only: true\n' > "$d/compose.yaml"
  printf '# RUNBOOK\n## Deploy\n%s\n%s\n' "$L_TOK" "$L_CRED" > "$d/RUNBOOK.md"
  expect "config-only FS (unattested) -> UNVERIFIED" "$d" 2

  # 6. read-only config + dated FS line + tokens/creds dated -> PASS (0) (config + attestation)
  d="$base/pass-config"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf 'services:\n  agent:\n    read_only: true\n' > "$d/compose.yaml"
  printf '# RUNBOOK\n## Deploy\n%s\n%s\n%s\n' "$L_FS" "$L_TOK" "$L_CRED" > "$d/RUNBOOK.md"
  expect "config + dated -> PASS" "$d" 0

  # 7. prod creds N/A + FS/tokens dated -> PASS (0) (per-aspect N/A)
  d="$base/pass-na-cred"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n%s\n%s\n- Prod credentials: N/A — no production environment\n' "$L_FS" "$L_TOK" > "$d/RUNBOOK.md"
  expect "prod-creds N/A -> PASS" "$d" 0

  # 8. only two of three lines present (creds absent, no config) -> FAIL (1)
  d="$base/fail-missing-one"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n%s\n%s\n' "$L_FS" "$L_TOK" > "$d/RUNBOOK.md"
  expect "two-of-three -> FAIL (weakest absent)" "$d" 1

  # 9. escalation: the placeholder fixture under CI/--require -> FAIL (1)
  expect "declared-not-attested + require -> FAIL" "$base/unv-placeholder" 1 1

  if [ "$st_fail" -ne 0 ]; then echo "containment-ready --selftest: FAIL" >&2; return 1; fi
  echo "containment-ready --selftest: OK (na/bare-fail/pass-all/placeholder-unv/config-only-unv/config-pass/na-cred-pass/missing-one-fail/escalation all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *)          check_dir "$DIR"; exit $? ;;
esac
```

- [ ] **Step 2: Make executable, dash-check, run the selftest (plain + under CI).**

Run: `chmod +x conformance/containment-ready.sh && dash -n conformance/containment-ready.sh && echo "syntax OK"` → `syntax OK`.
Run: `sh conformance/containment-ready.sh --selftest` → 9 `selftest PASS` lines, then `containment-ready --selftest: OK ...`, exit 0.
Run: `CI=true sh conformance/containment-ready.sh --selftest` → MUST still be 9 PASS + exit 0 (fixtures 4 and 5 stay UNVERIFIED/exit 2 via per-fixture REQUIRE isolation; only fixture 9 escalates).

- [ ] **Step 3: Confirm the kit-root behavior is the expected, unwired FAIL.** The kit root has `.github/workflows/` (surface present) but no `RUNBOOK.md` (it's a framework, not a deployed project), so the LIVE check reports per-aspect FAIL.

Run: `sh conformance/containment-ready.sh; echo "exit=$?"`
Expected: three `FAIL`-ish per-aspect lines and `exit=1`.

This is **fine and intentional**: the LIVE check is adopter-facing. The kit's own CI runs **`--selftest` only** (Task 6), and `containment-ready.sh` is a **conditional** check that is **NOT** in `conformance/verify.sh`'s curated list (confirmed: `verify.sh` lists `agent-autonomy/ci-gates/guard-wired/check-links/backlog-adapters/branch-protect/deployable-ready/dr-ready/resilience-ready` — `egress-policy.sh` is likewise excluded). So nothing runs the live containment check at the kit root in CI. **Do NOT add `containment-ready.sh` to `verify.sh`** (it would make the kit fail its own aggregate). No code change in this step — just verify the `exit=1` and move on.

- [ ] **Step 4: Commit.**

```bash
git add conformance/containment-ready.sh
git commit -m "feat(conformance): 11c — containment-ready.sh three-aspect declared+attested check"
```

---

## Task 2: `conformance/containment-readiness.md` + README index row

**Files:** Create `conformance/containment-readiness.md`; Modify `conformance/README.md`

- [ ] **Step 1: Write the checklist** (mirrors `egress-readiness.md`):

```markdown
# Containment-readiness checklist

**Gate:** deploy/security gate (`DEVELOPMENT-PROCESS.md` §7). **Companion:** `conformance/containment-ready.sh`.
**Reference:** `docs/operations/containment.md`.

Closes what is reachable to exfiltrate at the source (platform-safety-boundary controls #2/#3/#4). The kit cannot make a host FS read-only, expire a token, or broker prod access — so it verifies the **posture is declared + attested**, never that it is enforced. A green run is **necessary, not sufficient**.

## Auto (proven by `containment-ready.sh`, per aspect)
- [ ] **Sandbox FS** — declared (a read-only-mount compose/devcontainer config, or a RUNBOOK `Sandbox FS:` mechanism line) + attested `enforced: <date>`.
- [ ] **Scoped tokens** — RUNBOOK `Scoped tokens:` line names a mechanism (OIDC→role / short TTL / least-privilege) + attested.
- [ ] **Prod credentials** — RUNBOOK `Prod credentials:` line names a mechanism (separate / break-glass / SoD) + attested.
- [ ] **N/A is explicit** — an aspect that genuinely does not apply records `<Aspect>: N/A — <reason>`.
- [ ] **Overall = weakest aspect** — partial coverage never reads as adequate.

## Manual (the script CANNOT prove — platform/operator evidence)
- [ ] **The FS is actually read-only** — an agent process genuinely cannot read `~/.ssh`, `~/.aws`, other projects, or host secrets (test from inside the sandbox).
- [ ] **Tokens actually expire** — the issued credential is time-boxed and least-privilege in practice, not just declared.
- [ ] **Prod creds are actually unreachable** — a leaked dev/agent credential genuinely cannot touch production (break-glass is the only path).

## Honesty
PASS means the posture is **declared + attested**, never that the kit verified read-only FS / token TTL / cred separation. Enforcement is platform-owned (`docs/enterprise/platform-safety-boundary.md` controls #2/#3/#4); 11c makes it **verifiable** (Kit-assisted), not Kit-enforced.
```

- [ ] **Step 2: Add the `conformance/README.md` index row.** Find the `egress-policy.sh` row (`grep -n 'egress-policy.sh' conformance/README.md`) and add immediately after it:

```markdown
| `containment-ready.sh` | script | Slice 11c — agent-containment posture declared + attested-wired (sandbox FS · scoped tokens · separate prod creds; three-state, overall=weakest; never verifies enforcement). Pairs with `containment-readiness.md` / `../docs/operations/containment.md` | Review / CI (conditional on an integration/deploy surface) |
```

- [ ] **Step 3: Link-check + commit.**

Run: `sh conformance/check-links.sh 2>&1 | tail -1` → `OK: all relative Markdown links resolve`.

```bash
git add conformance/containment-readiness.md conformance/README.md
git commit -m "docs(conformance): 11c — containment-readiness checklist (Auto vs Manual) + README index row"
```

---

## Task 3: `docs/operations/containment.md` (the reference)

**Files:** Create `docs/operations/containment.md`

- [ ] **Step 1: Write the reference** (three copy-pasteable patterns + how to attest):

````markdown
# Agent containment (sandbox FS · scoped tokens · separate prod creds) — reference

How to make platform-safety-boundary controls #2/#3/#4 real. Where the egress allowlist (`egress-control.md`) closes the exfiltration *channel*, these close **what is reachable to exfiltrate in the first place** — directly defanging the MCP `secret.read` class and the interpreter exfil tail at the source (`../superpowers/reviews/2026-06-10-A8-mcp-egress-attack-surface.md`).

`conformance/containment-ready.sh` verifies this posture is **declared + attested**; it does **not** verify enforcement. See `conformance/containment-readiness.md`.

## 1. Sandbox / read-only filesystem
Run the agent in a container scoped to the work tree, with the root filesystem read-only and a `tmpfs` for scratch — so `~/.aws`, `~/.ssh`, other projects, and host secrets are simply not mounted.

```yaml
# compose.yaml — an agent service that cannot read the host
services:
  agent:
    build: .
    read_only: true                 # root FS read-only
    tmpfs:
      - /tmp                        # writable scratch only
    volumes:
      - ./:/work:rw                 # ONLY the work tree, nothing from $HOME
    working_dir: /work
    # no ~/.aws, ~/.ssh, /var/run/docker.sock, or host bind mounts
```

devcontainer equivalent: set `"workspaceMount"` to the work tree only and add `"runArgs": ["--read-only", "--tmpfs", "/tmp"]`.

## 2. Scoped, short-lived tokens
- Prefer **OIDC→role federation** over long-lived secrets (CI: GitHub OIDC → a role assumed per run; no static cloud keys in the repo or agent env).
- **Short TTL** (minutes-to-hours) and **least-privilege scope** for every integration token.
- In CI, keep `id-token` at the job/step that needs it (push-only `provenance` job), never workflow-wide.

## 3. Separate production credentials (SoD)
- Agents and dev sessions **never** hold prod write credentials.
- Production access is brokered through an audited **break-glass / approval** workflow.
- A leaked dev/agent token must not be able to touch prod (segregation of duties).

## How to attest (what the check reads)
Record three lines in `RUNBOOK.md` (deploy/security section). The phrases + dates are what `containment-ready.sh` keys on:

```
Sandbox FS: read-only work-tree mounts (compose read_only + tmpfs) — enforced: 2026-06-01
Scoped tokens: OIDC->role, <=1h TTL, least-privilege — enforced: 2026-06-01
Prod credentials: separate + break-glass (SoD) — enforced: 2026-06-01
```

Any aspect that genuinely does not apply: `<Aspect>: N/A — <reason>` (e.g. `Prod credentials: N/A — no production environment`).

## The ceiling (honest)
These patterns contain anything only **if actually applied at the platform**. A repo with the compose snippet but a host/runner that ignores it is **UNVERIFIED**, by design — and a green check never proves the FS is truly read-only, the token truly expires, or prod is truly unreachable. Those are Manual rows in `../../conformance/containment-readiness.md`. Enforcement stays platform-owned (`../enterprise/platform-safety-boundary.md`).
````

- [ ] **Step 2: Link-check + commit.**

Run: `sh conformance/check-links.sh 2>&1 | tail -1`.

```bash
git add docs/operations/containment.md
git commit -m "docs(operations): 11c — agent-containment reference (sandbox FS + scoped tokens + separate prod creds)"
```

---

## Task 4: RUNBOOK template — three attestation lines

**Files:** Modify `templates/RUNBOOK-TEMPLATE.md`

- [ ] **Step 1: Locate the egress line** (the 11b attestation, the anchor to insert after).

Run: `grep -n 'Network egress:' templates/RUNBOOK-TEMPLATE.md` → expect one line under `## 4. Deploy` (around line 31).

- [ ] **Step 2: Insert the three containment lines immediately after the `Network egress:` line** (keeping the security attestations together, before the `**Container / Kubernetes deploy (if applicable):**` subsection):

```markdown
- Sandbox FS: read-only work-tree mounts ([mechanism]) — enforced: [date]  <!-- Agent FS scoped to the work tree (host secrets unreachable); see docs/operations/containment.md; verified declared+attested by conformance/containment-ready.sh. If not applicable: replace with N/A — [reason] -->
- Scoped tokens: OIDC->role, short TTL ([mechanism]) — enforced: [date]  <!-- Least-privilege, time-boxed credentials -->
- Prod credentials: separate + break-glass ([mechanism]) — enforced: [date]  <!-- Agents never hold prod write creds; SoD -->
```

(The literal phrases `Sandbox FS:` / `Scoped tokens:` / `Prod credentials:` + `enforced: [date]` must match `containment-ready.sh`'s greps exactly. **Do NOT place the literal `<prefix>: N/A` inside a comment** — the N/A-escape grep is token-anchored but keep comments clear of the keyed phrases.)

- [ ] **Step 3: Verify a fresh template reads as UNVERIFIED** (placeholders, not a false PASS):

```bash
tmp=$(mktemp -d); printf 'FROM scratch\n' > "$tmp/Dockerfile"; cp templates/RUNBOOK-TEMPLATE.md "$tmp/RUNBOOK.md"
sh conformance/containment-ready.sh "$tmp"; echo "exit=$?"
```
Expected: per-aspect prints (each UNVERIFIED — declared via mechanism text but `[date]` placeholder) and `exit=2`. (NOT exit 0, NOT a false PASS.)

- [ ] **Step 4: Link-check + commit.**

Run: `sh conformance/check-links.sh 2>&1 | tail -1`.

```bash
git add templates/RUNBOOK-TEMPLATE.md
git commit -m "docs(templates): 11c — RUNBOOK containment attestation lines (keyed by containment-ready.sh)"
```

---

## Task 5: Crosswalk rows 37/38/39 + audit-evidence + boundary note

**Files:** Modify `docs/enterprise/compliance-crosswalk.md`, `conformance/audit-evidence-checklist.md`, `docs/enterprise/platform-safety-boundary.md`

- [ ] **Step 1: Move the three crosswalk rows Org-owned → Kit-assisted.** In `docs/enterprise/compliance-crosswalk.md`, replace each of the three rows' final cell `Org-owned` → `Kit-assisted` and update the evidence cell. Exact replacements (match the on-disk row, change evidence + owner):

Row — separate prod credentials:
```markdown
| Agent/runtime platform boundary · separate prod credentials (SoD) | `docs/enterprise/platform-safety-boundary.md` | CC6.1, CC6.3 | A.5.15 (access control), A.5.18 (access rights), A.8.2 (privileged access rights) | PO.5 | break-glass workflow, access logs | Org-owned |
```
→
```markdown
| Agent/runtime platform boundary · separate prod credentials (SoD) | `docs/enterprise/platform-safety-boundary.md` · `../operations/containment.md` | CC6.1, CC6.3 | A.5.15 (access control), A.5.18 (access rights), A.8.2 (privileged access rights) | PO.5 | break-glass workflow + RUNBOOK attestation, verified by `conformance/containment-ready.sh` | Kit-assisted |
```

Row — sandboxed filesystem:
```markdown
| Agent/runtime platform boundary · sandboxed filesystem | `docs/enterprise/platform-safety-boundary.md` | CC6.1 | A.8.31 (separation of development, test and production environments) | PO.5 | container/sandbox config | Org-owned |
```
→
```markdown
| Agent/runtime platform boundary · sandboxed filesystem | `docs/enterprise/platform-safety-boundary.md` · `../operations/containment.md` | CC6.1 | A.8.31 (separation of development, test and production environments) | PO.5 | read-only-mount reference + RUNBOOK attestation, verified by `conformance/containment-ready.sh` | Kit-assisted |
```

Row — scoped short-lived tokens:
```markdown
| Agent/runtime platform boundary · scoped short-lived tokens | `docs/enterprise/platform-safety-boundary.md` | CC6.1 | A.5.17 (authentication information), A.8.2 (privileged access rights) | PO.5 | token TTL/scope config | Org-owned |
```
→
```markdown
| Agent/runtime platform boundary · scoped short-lived tokens | `docs/enterprise/platform-safety-boundary.md` · `../operations/containment.md` | CC6.1 | A.5.17 (authentication information), A.8.2 (privileged access rights) | PO.5 | OIDC->role / short-TTL reference + RUNBOOK attestation, verified by `conformance/containment-ready.sh` | Kit-assisted |
```

- [ ] **Step 2: Add audit-evidence rows.** In `conformance/audit-evidence-checklist.md`, immediately after the `Network egress · default-deny allowlist (if networked)` row (line ~19), add three rows:

```markdown
| Sandboxed / read-only agent filesystem (if integration surface) | CC6.1 / A.8.31 / PO.5 | read-only-mount reference + RUNBOOK attestation (declared + wired) | **Auto (conditional):** `sh conformance/containment-ready.sh` | |
| Scoped, short-lived tokens (if integration surface) | CC6.1 / A.5.17, A.8.2 / PO.5 | OIDC->role / short-TTL + RUNBOOK attestation | **Auto (conditional):** `sh conformance/containment-ready.sh` | |
| Separate production credentials · SoD (if prod surface) | CC6.1, CC6.3 / A.5.15, A.5.18, A.8.2 / PO.5 | break-glass + RUNBOOK attestation | **Auto (conditional):** `sh conformance/containment-ready.sh` | |
```

- [ ] **Step 3: Boundary note.** In `docs/enterprise/platform-safety-boundary.md`, append one sentence to EACH of controls #2, #3, #4 (the numbered list items): ` The kit now ships a reference (docs/operations/containment.md) and verifies this is declared + attested (conformance/containment-ready.sh) — enforcement remains platform-owned.` Do NOT weaken the "these are the REAL boundary / platform-owned" framing.

- [ ] **Step 4: Link-check + commit.**

Run: `sh conformance/check-links.sh 2>&1 | tail -1`.

```bash
git add docs/enterprise/compliance-crosswalk.md conformance/audit-evidence-checklist.md docs/enterprise/platform-safety-boundary.md
git commit -m "docs(enterprise): 11c — controls #2/#3/#4 Org-owned -> Kit-assisted (reference shipped + wiring verified)"
```

---

## Task 6: CI wiring (control-plane `cp`) + post-`cp` verify

**Files:** Modify `.github/workflows/ci.yml` (control-plane — human `cp`)

- [ ] **Step 1: Build the CI candidate.** Read `.github/workflows/ci.yml`; with the Read/Write tools (NOT a shell command naming `ci.yml`, which the guard denies) write `/tmp/ci.yml.11c` = the live file with one step added in the `conformance` job immediately after the `Egress-policy self-test ...` step:

```yaml
      - name: Containment-ready self-test (sandbox/tokens/prod-creds three-state)
        run: sh conformance/containment-ready.sh --selftest
```

Validate (these read-only commands are allowed):
```bash
diff .github/workflows/ci.yml /tmp/ci.yml.11c
```
Expected: only the two added lines.
```bash
python3 -c 'import yaml,sys; d=yaml.safe_load(open("/tmp/ci.yml.11c")); print(",".join(d["jobs"].keys()))' 2>/dev/null || grep -E '^  [a-z-]+:$' /tmp/ci.yml.11c
```
Expected: `conformance,bootstrap,docs-links`.

- [ ] **Step 2: Hand Bradley the control-plane `cp`** (self-edit flag; the guard denies the agent writing `.github/workflows/`). Present exactly:

```bash
cd ~/Development/agentic-sdlc-kit && KIT_GUARD_SELFEDIT=1 sh -c '
  cp /tmp/ci.yml.11c .github/workflows/ci.yml &&
  git add .github/workflows/ci.yml &&
  git commit -m "ci(11c): run containment-ready.sh --selftest in the conformance job"
'
```
Wait for confirmation before continuing.

---

## Task 7: Release (VERSION / CHANGELOG / roadmap)

**Files:** Modify `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE11.md`, `README.md` (badge)

- [ ] **Step 1: `VERSION`** → `2.42.0`: `printf '2.42.0\n' > VERSION`.

- [ ] **Step 2: Badge sync.** `sh conformance/badge-version.sh --fix && sh conformance/badge-version.sh; echo "exit=$?"` → `PASS: README badge v2.42.0 matches VERSION 2.42.0`, exit 0.

- [ ] **Step 3: CHANGELOG** — insert above the current top entry (`## [2.41.0] - ...`). Do NOT add a `[2.42.0]:` link-def (recent convention omits them):

```markdown
## [2.42.0] - 2026-06-11

Sandbox + scoped-credential references + conformance (Slice 11c — Containment arc). Formalizes platform-safety-boundary controls #2/#3/#4 (sandboxed FS · scoped tokens · separate prod creds) as a declared, verifiable posture. **MINOR** — conditional three-state check + reference docs; no new universal gate.

### Added
- **`docs/operations/containment.md`** — reference: read-only-FS compose/devcontainer snippet, OIDC→role short-TTL token pattern, separate-prod-creds/break-glass pattern + how to attest.
- **`conformance/containment-ready.sh`** — one conditional three-state check over three sub-aspects (Sandbox FS / Scoped tokens / Prod credentials), overall = weakest aspect; UNVERIFIED escalates under CI/`--require`; `--selftest` corpus; CI-wired. Pairs with `conformance/containment-readiness.md` (Auto vs Manual).
- **RUNBOOK** containment attestation lines (`templates/RUNBOOK-TEMPLATE.md`).

### Changed
- Compliance crosswalk + audit-evidence: the three agent-boundary rows (#2/#3/#4) **Org-owned → Kit-assisted** (reference shipped + wiring verified). `platform-safety-boundary.md` notes each is now reference-shipped + verify-wired.

### Honesty
- The check **verifies declaration + attestation, never enforcement** — PASS ≠ "FS actually read-only / tokens actually expire / prod creds actually unreachable" (Manual rows). UNVERIFIED is a first-class non-pass; enforcement stays platform-owned.
```

- [ ] **Step 4: Roadmap.** In `docs/ROADMAP-SLICE11.md`, set the `11c` row Status → `✅ shipped v2.42.0` with a one-line summary (match the 11a/11b row style).

- [ ] **Step 5: Verify + commit.**

Run: `cat VERSION && sh conformance/check-links.sh 2>&1 | tail -1`.

```bash
git add VERSION README.md CHANGELOG.md docs/ROADMAP-SLICE11.md
git commit -m "chore(release): 2.42.0 — sandbox + scoped-credential references + conformance (11c)"
```

---

## Task 8: Final verify + independent security-owner review + PR

- [ ] **Step 1: Full suite (post-`cp`, live).**

```sh
sh conformance/containment-ready.sh --selftest >/dev/null && echo "containment selftest OK"
CI=true sh conformance/containment-ready.sh --selftest >/dev/null && echo "containment selftest (CI) OK"
sh conformance/egress-policy.sh --selftest >/dev/null && echo "egress selftest OK (regression)"
sh conformance/agent-autonomy.sh >/dev/null && echo "agent-autonomy OK"
sh conformance/check-links.sh >/dev/null && echo "links OK"
sh conformance/badge-version.sh >/dev/null && echo "badge OK"
sh conformance/doc-budget.sh >/dev/null && echo "doc-budget OK"
sh conformance/verify.sh 2>&1 | tail -1
```
Expected: all OK; `verify.sh` RESULT: OK.

- [ ] **Step 2: Independent security-owner-lens review** (builder ≠ reviewer). Dispatch a security reviewer against `git diff main...HEAD` with the honesty framing: confirm (a) no output/doc/crosswalk implies in-process enforcement or verification of the actual FS/token/cred state; (b) overall=weakest aggregation can't be gamed (2-of-3 PASS never reads green); (c) PASS unreachable without a dated attestation on every applicable aspect; (d) N/A escape is token-anchored (no `NAS`/`native` false-N/A); (e) UNVERIFIED escalates under CI/`--require`; (f) per-fixture REQUIRE isolation; (g) dash-clean, no fixture `rm -rf`; (h) crosswalk says Kit-assisted, not Kit-enforced. Fold cheap honesty-relevant findings; carry the rest.

- [ ] **Step 3: Push + open PR** (Bradley merges — agent never self-merges).

```bash
git push -u origin feature/slice-11c-containment
gh pr create --base main --head feature/slice-11c-containment --title "Slice 11c — Sandbox + scoped-credential references + conformance (v2.42.0)" --body "<summary: closes the exfiltratable-at-source surface — sandbox FS / scoped tokens / separate prod creds as a declared+attested three-aspect posture; controls #2/#3/#4 Org-owned -> Kit-assisted; verifies declaration not enforcement; MINOR>"
```

- [ ] **Step 4: Report** the PR number + merge command (`gh pr merge <n> --squash --admin --delete-branch`) and the next arc step (11d — honesty restatement).

---

## Verification (whole slice)

- `sh conformance/containment-ready.sh --selftest` → 9 PASS, exit 0, plain and under `CI=true`.
- Fresh RUNBOOK template → UNVERIFIED (exit 2), never a false PASS.
- `containment-ready.sh --selftest` runs in kit CI; not added to `verify.sh` (conditional, like egress/resilience).
- `check-links.sh`, `badge-version.sh`, `doc-budget.sh`, `verify.sh` → green.
- Crosswalk rows 37/38/39 = Kit-assisted (not Kit-enforced); boundary doc still says enforcement is platform-owned.
- Governance: feature branch → PR → human ratification; `ci.yml` via control-plane `cp`; security-owner lens before PR.
