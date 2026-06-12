# Slice 11d — Honesty & assurance restatement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconcile the kit's narrative/summary docs to the post-11a/b/c reality (without overclaiming), record the MCP capability gate as Kit-enforced, and regression-lock the responsibility tiers with a drift-guard.

**Architecture:** Pure docs reconciliation + one grep-based drift-guard (`assurance-tiers.sh`, badge-version/doc-budget style) asserting the crosswalk states each arc control at its real tier. No runtime behaviour changes.

**Tech Stack:** POSIX `sh` (dash-clean), `grep`, `mktemp` fixtures. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-06-11-slice11d-honesty-restatement-design.md`

**Honesty invariant (this slice IS an honesty claim):** every edit ADDS a qualifier, never deletes a caveat. Keep: the deny-list-is-a-speed-bump argument, "these four controls are the boundary", "enforcement is platform-owned". "Kit-enforced" appears only for the MCP gate, always with the by-name caveat. `assurance-tiers.sh` verifies the tiers are *stated*, not "true".

**Control-plane note:** only `.github/workflows/ci.yml` is guard-protected (→ human `cp`, Task 5). `DEVELOPMENT-PROCESS.md`, all `docs/enterprise/*`, `conformance/*` (incl. `verify.sh`) are editable directly (verified against `is_control_plane_path`).

---

## File structure

| File | Responsibility | Control-plane? |
|------|----------------|----------------|
| `conformance/assurance-tiers.sh` | NEW — drift-guard: crosswalk states each arc control at its real tier; `--selftest` | no |
| `docs/enterprise/compliance-crosswalk.md` | MODIFY — add MCP capability gate row (Kit-enforced) | no |
| `conformance/audit-evidence-checklist.md` | MODIFY — add MCP capability gate row | no |
| `docs/enterprise/platform-safety-boundary.md` | MODIFY — "What the kit now provides" note | no |
| `docs/enterprise/EXEC-BRIEF.md` | MODIFY — speed-bump line + table clarifier | no |
| `DEVELOPMENT-PROCESS.md` | MODIFY — §13 guard paragraph | no |
| `conformance/containment-readiness.md` | MODIFY — honor-based-date note (the carried 11c LOW) | no |
| `conformance/verify.sh` | MODIFY — add assurance-tiers as a live control | no |
| `conformance/README.md` | MODIFY — index row | no |
| `.github/workflows/ci.yml` | MODIFY — `assurance-tiers.sh --selftest` step | **YES — human `cp`** |
| `VERSION` · `CHANGELOG.md` · `docs/ROADMAP-SLICE11.md` | MODIFY — release v2.43.0 | no |

Branch: `feature/slice-11d-honesty-restatement` (created off latest main; spec committed on it).

---

## Task 1: `conformance/assurance-tiers.sh` (the tier drift-guard + selftest)

**Files:** Create `conformance/assurance-tiers.sh`

- [ ] **Step 1: Write the full script.**

```sh
#!/bin/sh
# assurance-tiers.sh — drift-guard (Slice 11d): the compliance crosswalk states each Containment-arc
# control at its REAL responsibility tier, and they cannot silently revert. Asserts, per control
# (matched by a row-label regex), that its crosswalk row carries the expected tier token
# (Kit-enforced / Kit-assisted). This verifies the tiers are STATED (documentation drift), NOT that
# they are "true" — enforcement reality lives in the controls themselves (11a/b/c).
#
#   sh conformance/assurance-tiers.sh [crosswalk-path]   (default: docs/enterprise/compliance-crosswalk.md)
#   sh conformance/assurance-tiers.sh --selftest
# Exit: 0 = all tiers stated correctly · 1 = a row missing or at the wrong tier. POSIX sh; dash-clean.
set -eu

check_file() {
  cw="$1"
  if [ ! -f "$cw" ]; then echo "FAIL: crosswalk not found ($cw)"; return 1; fi
  fail=0
  # assert_tier <row-label-regex> <expected-tier> <human-name>
  assert_tier() {
    _lab="$1"; _tier="$2"; _name="$3"
    _row=$(grep -iE "$_lab" "$cw" | head -1 || true)
    if [ -z "$_row" ]; then
      echo "FAIL: no crosswalk row for $_name (/$_lab/)"; fail=1; return 0
    fi
    if printf '%s' "$_row" | grep -qF "$_tier"; then
      echo "PASS: $_name -> $_tier"
    else
      echo "FAIL: $_name must be '$_tier' — its crosswalk row carries a different tier (drift / silent revert?)"; fail=1
    fi
  }
  assert_tier 'MCP capability gate'        'Kit-enforced' 'MCP capability gate'
  assert_tier 'network-egress allowlist'   'Kit-assisted' 'network egress allowlist'
  assert_tier 'sandboxed filesystem'       'Kit-assisted' 'sandboxed filesystem'
  assert_tier 'scoped short-lived tokens'  'Kit-assisted' 'scoped short-lived tokens'
  assert_tier 'separate prod credentials'  'Kit-assisted' 'separate prod credentials'
  if [ "$fail" -ne 0 ]; then echo "assurance-tiers: FAIL ($cw)"; return 1; fi
  echo "assurance-tiers: OK — arc controls stated at their real tier ($cw)"
  return 0
}

# mktemp fixtures; assert each outcome. Fixtures LEFT in place (no rm -rf; 7e guard).
selftest() {
  st=0
  base=$(mktemp -d)
  hdr='| Kit control | Where | SOC 2 | ISO | SSDF | Evidence | Responsibility |'

  good="$base/good.md"
  {
    printf '%s\n' "$hdr"
    printf '| Agent/runtime MCP capability gate (deny-by-default) | x | x | x | x | ev | Kit-enforced |\n'
    printf '| Agent/runtime platform boundary · network-egress allowlist | x | x | x | x | ev | Kit-assisted |\n'
    printf '| Agent/runtime platform boundary · sandboxed filesystem | x | x | x | x | ev | Kit-assisted |\n'
    printf '| Agent/runtime platform boundary · scoped short-lived tokens | x | x | x | x | ev | Kit-assisted |\n'
    printf '| Agent/runtime platform boundary · separate prod credentials (SoD) | x | x | x | x | ev | Kit-assisted |\n'
  } > "$good"
  if check_file "$good" >/dev/null 2>&1; then echo "selftest PASS: correct tiers -> OK"; else echo "selftest FAIL: correct tiers should pass"; st=1; fi

  rev="$base/reverted.md"
  sed 's/network-egress allowlist | x | x | x | x | ev | Kit-assisted/network-egress allowlist | x | x | x | x | ev | Org-owned/' "$good" > "$rev"
  if check_file "$rev" >/dev/null 2>&1; then echo "selftest FAIL: reverted egress (Org-owned) should FAIL"; st=1; else echo "selftest PASS: reverted egress -> FAIL"; fi

  miss="$base/missing.md"
  grep -v 'MCP capability gate' "$good" > "$miss"
  if check_file "$miss" >/dev/null 2>&1; then echo "selftest FAIL: missing MCP row should FAIL"; st=1; else echo "selftest PASS: missing MCP row -> FAIL"; fi

  if [ "$st" -ne 0 ]; then echo "assurance-tiers --selftest: FAIL" >&2; return 1; fi
  echo "assurance-tiers --selftest: OK (correct/reverted/missing all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *) check_file "${1:-docs/enterprise/compliance-crosswalk.md}"; exit $? ;;
esac
```

- [ ] **Step 2: Make executable, dash-check, run the selftest.**

Run: `chmod +x conformance/assurance-tiers.sh && dash -n conformance/assurance-tiers.sh && echo "syntax OK"` → `syntax OK`.
Run: `sh conformance/assurance-tiers.sh --selftest` → 3 `selftest PASS` lines + `assurance-tiers --selftest: OK ...`, exit 0.

- [ ] **Step 3: Confirm the LIVE check FAILs until Task 2 adds the MCP row.**

Run: `sh conformance/assurance-tiers.sh; echo "exit=$?"`
Expected: `PASS` for the four Kit-assisted rows (already in the crosswalk from 11b/11c) but `FAIL: no crosswalk row for MCP capability gate ...`, `exit=1`. This is expected — Task 2 adds the row. Do not "fix" it here.

- [ ] **Step 4: Commit.**

```bash
git add conformance/assurance-tiers.sh
git commit -m "feat(conformance): 11d — assurance-tiers.sh drift-guard (crosswalk states each arc control at its real tier)"
```

---

## Task 2: MCP capability gate → Kit-enforced rows (crosswalk + audit-evidence)

**Files:** Modify `docs/enterprise/compliance-crosswalk.md`, `conformance/audit-evidence-checklist.md`

- [ ] **Step 1: Add the MCP gate row to the crosswalk.** The table columns are `| Kit control | Where in the kit | SOC 2 | ISO 27001:2022 | NIST SSDF (800-218) | Evidence artifact | Responsibility |`. Insert this row immediately BEFORE the `Agent/runtime platform boundary · network-egress allowlist` row (so the in-process gate leads the agent-runtime cluster):

```markdown
| Agent/runtime MCP capability gate (deny-by-default) | `.claude/hooks/guard-core.sh` (`guard_check_mcp`) · `.claude/mcp-policy.json` | CC6.1, CC6.3 | A.8.2 (privileged access rights), A.5.15 (access control) | PO.5, PS.1 | `conformance/mcp-policy.sh` + `agent-autonomy.sh` MCP cases — gates MCP tool capability **by name**; the `net.egress` class is a name-match speed bump, not egress containment | Kit-enforced |
```

- [ ] **Step 2: Add the matching audit-evidence row.** In `conformance/audit-evidence-checklist.md`, immediately BEFORE the `Network egress · default-deny allowlist (if networked)` row (find it: `grep -n 'Network egress' conformance/audit-evidence-checklist.md`), add (columns `| Control | Crosswalk ref | Evidence artifact | Check | Present? |`):

```markdown
| Agent/runtime MCP capability gate (deny-by-default) | CC6.1, CC6.3 / A.8.2, A.5.15 / PO.5, PS.1 | un-allowlisted destructive/egress MCP tool denied in-process (by name) | **Auto:** `sh conformance/mcp-policy.sh` + `sh conformance/agent-autonomy.sh` | |
```

- [ ] **Step 3: Verify the live drift-guard now PASSes.**

Run: `sh conformance/assurance-tiers.sh; echo "exit=$?"` → all 5 `PASS` lines, `assurance-tiers: OK ...`, `exit=0`.
Run: `sh conformance/check-links.sh 2>&1 | tail -1` → OK.

- [ ] **Step 4: Commit.**

```bash
git add docs/enterprise/compliance-crosswalk.md conformance/audit-evidence-checklist.md
git commit -m "docs(enterprise): 11d — record the MCP capability gate as Kit-enforced (by-name caveat)"
```

---

## Task 3: Narrative reconciliation (no overclaiming)

**Files:** Modify `docs/enterprise/platform-safety-boundary.md`, `docs/enterprise/EXEC-BRIEF.md`, `DEVELOPMENT-PROCESS.md`, `conformance/containment-readiness.md`

- [ ] **Step 1: `platform-safety-boundary.md` — add a "What the kit now provides" note.** Insert this new subsection AFTER control #4 (the line ending "…enforcement remains platform-owned.") and BEFORE `## Relationship to the guard`:

```markdown
## What the kit now provides (Slices 11a–11c)

The boundary above stays **platform-owned and platform-enforced** — but the kit no longer only *documents* it:
- **Kit-enforced (one surface):** the agent guard now gates **MCP tool capabilities** in-process — `guard_check_mcp` denies un-allowlisted destructive/egress MCP calls deny-by-default (Slice 11a). This is real enforcement *for MCP tool names*; it does **not** contain a renamed action, an interpreter, or in-server egress — the `net.egress` class is a name-match speed bump.
- **Kit-assisted (the four controls):** for the network-egress allowlist (#1), sandboxed filesystem (#3), scoped tokens (#4), and separate prod credentials (#2), the kit now ships a copy-pasteable reference and a three-state conformance check that the control is **declared + attested-wired** (`conformance/egress-policy.sh`, `conformance/containment-ready.sh`). The **host still enforces** — the kit verifies the posture is wired, not that a packet is dropped or a mount is read-only.

Net: the shell/interpreter deny-list is still a **speed bump**; one narrow surface (MCP capability) is now Kit-enforced; the four platform controls moved Org-owned → **Kit-assisted**. Per-row detail: [compliance-crosswalk.md](compliance-crosswalk.md); verified by `conformance/assurance-tiers.sh`.
```

- [ ] **Step 2: `EXEC-BRIEF.md` §5 — amend the speed-bump paragraph.** Replace:

```markdown
The runtime guard is a **speed bump, not a boundary.** It is a deny-list over a shell, and a deny-list cannot contain a determined or compromised agent (interpreters and obfuscation defeat pattern-matching; `--no-verify` bypasses the git hook). The **real** controls are **Org-owned** and live in your platform: a network-egress allowlist (the only real exfiltration defense), separate production credentials, a sandboxed filesystem, and scoped short-lived tokens. Adopt both — the guard prevents accidents cheaply; the platform boundary is what you certify. See [platform-safety-boundary.md](platform-safety-boundary.md).
```

with:

```markdown
The runtime guard is a **speed bump, not a boundary** for shell and interpreter commands — a deny-list over a shell cannot contain a determined or compromised agent (interpreters and obfuscation defeat pattern-matching; `--no-verify` bypasses the git hook). Two honest refinements (Slices 11a–11c): the guard now **enforces** a deny-by-default **MCP capability gate** in-process (the one in-process control that is real enforcement — by tool name only), and the kit now **ships + verifies references** for the four platform controls — a network-egress allowlist (the only real exfiltration defense), separate production credentials, a sandboxed filesystem, and scoped short-lived tokens — which remain **platform-enforced** (Kit-assisted, not Kit-enforced). Adopt both — the guard prevents accidents cheaply; the platform boundary is what you certify. See [platform-safety-boundary.md](platform-safety-boundary.md).
```

- [ ] **Step 3: `EXEC-BRIEF.md` §6 — add a tier clarifier after the table.** Find the line `Full mapping, with per-row *Kit-enforced / Kit-assisted / Org-owned* responsibility → [compliance-crosswalk.md](compliance-crosswalk.md).` and insert immediately after it:

```markdown

Since Slices 11a–11c, the agent/runtime platform-boundary rows (egress, sandboxed FS, scoped tokens, separate prod credentials) are **Kit-assisted** (reference shipped + wiring verified, host-enforced), and the **MCP capability gate** is **Kit-enforced** (by tool name). The drift-guard `conformance/assurance-tiers.sh` holds these tiers in place.
```

- [ ] **Step 4: `DEVELOPMENT-PROCESS.md` §13 — amend the guard paragraph.** Replace:

```markdown
The guard is a **best-effort speed bump for honest agent mistakes, not a security boundary** — a deny-list over a shell cannot contain a determined or compromised agent. The real boundary is platform-owned (network-egress allowlist, separate prod credentials, sandboxed filesystem, scoped tokens); see [`docs/enterprise/platform-safety-boundary.md`](docs/enterprise/platform-safety-boundary.md). Adopt both.
```

with:

```markdown
The guard is a **best-effort speed bump for honest agent mistakes, not a security boundary** — a deny-list over a shell cannot contain a determined or compromised agent. Two refinements (Slices 11a–11c): the guard additionally **enforces a deny-by-default MCP capability gate** in-process (`guard_check_mcp` — real enforcement, by tool name only), and the four platform controls are now kit-referenced + verify-wired (**Kit-assisted**). The real boundary remains platform-owned (network-egress allowlist, separate prod credentials, sandboxed filesystem, scoped tokens); see [`docs/enterprise/platform-safety-boundary.md`](docs/enterprise/platform-safety-boundary.md). Adopt both.
```

- [ ] **Step 5: `containment-readiness.md` — document the carried 11c LOW.** In the `## Honesty` section, append one bullet/sentence:

```markdown
- **Attestation dates are honor-based.** The gate verifies an `enforced: <date>` is present and well-shaped on the aspect's own line — not that the date is accurate or that the aspect isn't self-contradicted elsewhere on that line. Keep one aspect per line; the date attests *that line's* aspect.
```

- [ ] **Step 6: Verify budget + links + commit.**

Run: `sh conformance/doc-budget.sh; echo "exit=$?"` → PASS, exit 0 (the `DEVELOPMENT-PROCESS.md` edit stays within budget; if it FAILs, the budget is a ratified ceiling — STOP and report rather than trimming governance text).
Run: `sh conformance/check-links.sh 2>&1 | tail -1` → OK.

```bash
git add docs/enterprise/platform-safety-boundary.md docs/enterprise/EXEC-BRIEF.md DEVELOPMENT-PROCESS.md conformance/containment-readiness.md
git commit -m "docs(11d): reconcile guard/boundary narratives to post-arc reality (MCP Kit-enforced; #1-4 Kit-assisted; no overclaim) + honor-based-date note"
```

---

## Task 4: Wire the drift-guard into verify.sh + README

**Files:** Modify `conformance/verify.sh`, `conformance/README.md`

- [ ] **Step 1: Add assurance-tiers as a live control in `verify.sh`.** Find the curated check list (`grep -n '^check ' conformance/verify.sh`); add after the `check control check-links …` line:

```sh
check control assurance-tiers sh conformance/assurance-tiers.sh
```

- [ ] **Step 2: Add the `conformance/README.md` index row.** After the `containment-ready.sh` row (`grep -n 'containment-ready.sh' conformance/README.md`), add:

```markdown
| `assurance-tiers.sh` | script | Slice 11d — the compliance crosswalk states each Containment-arc control at its real responsibility tier (MCP gate = Kit-enforced; egress/sandbox/tokens/prod-creds = Kit-assisted); drift-guard against a silent revert. Verifies the tiers are *stated*, not "true" | CI / Review |
```

- [ ] **Step 3: Verify + commit.**

Run: `sh conformance/verify.sh 2>&1 | tail -1` → `RESULT: OK (...)` (the live assurance-tiers control passes now that Task 2 added the MCP row).
Run: `sh conformance/check-links.sh 2>&1 | tail -1` → OK.

```bash
git add conformance/verify.sh conformance/README.md
git commit -m "feat(conformance): 11d — wire assurance-tiers into verify.sh (live control) + README index row"
```

---

## Task 5: CI wiring (control-plane `cp`)

**Files:** Modify `.github/workflows/ci.yml` (control-plane — human `cp`)

- [ ] **Step 1: Build the CI candidate.** Read `.github/workflows/ci.yml`; with Read/Write tools (NOT a shell command naming `ci.yml`) write `/tmp/ci.yml.11d` = the live file with one step added in the `conformance` job immediately after the `Containment-ready self-test …` step:

```yaml
      - name: Assurance-tiers drift-guard self-test (crosswalk tiers)
        run: sh conformance/assurance-tiers.sh --selftest
```

Validate:
```bash
diff .github/workflows/ci.yml /tmp/ci.yml.11d
```
Expected: only the two added lines.
```bash
python3 -c 'import yaml; d=yaml.safe_load(open("/tmp/ci.yml.11d")); print(",".join(d["jobs"].keys()))' 2>/dev/null || grep -E '^  [a-z-]+:$' /tmp/ci.yml.11d
```
Expected: `conformance,bootstrap,docs-links`.

- [ ] **Step 2: Hand Bradley the control-plane `cp`.** Present exactly:

```bash
cd ~/Development/agentic-sdlc-kit && KIT_GUARD_SELFEDIT=1 sh -c '
  cp /tmp/ci.yml.11d .github/workflows/ci.yml &&
  git add .github/workflows/ci.yml &&
  git commit -m "ci(11d): run assurance-tiers.sh --selftest in the conformance job"
'
```
Wait for confirmation before continuing.

---

## Task 6: Release (VERSION / CHANGELOG / roadmap)

**Files:** Modify `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE11.md`, `README.md` (badge)

- [ ] **Step 1: `VERSION`** → `2.43.0`: `printf '2.43.0\n' > VERSION`.

- [ ] **Step 2: Badge sync.** `sh conformance/badge-version.sh --fix && sh conformance/badge-version.sh; echo "exit=$?"` → `PASS: README badge v2.43.0 matches VERSION 2.43.0`, exit 0.

- [ ] **Step 3: CHANGELOG** — insert above the current top entry (`## [2.42.0] - ...`). No `[2.43.0]:` link-def (recent convention omits them):

```markdown
## [2.43.0] - 2026-06-11

Honesty & assurance restatement (Slice 11d — Containment arc). Reconciles the kit's narrative/summary docs to the post-11a/b/c reality and regression-locks the responsibility tiers. **MINOR** — docs + one drift-guard; no behaviour change.

### Added
- **`conformance/assurance-tiers.sh`** — drift-guard asserting the compliance crosswalk states each arc control at its real tier (MCP capability gate = **Kit-enforced**; egress / sandboxed FS / scoped tokens / separate prod creds = **Kit-assisted**); `--selftest`; wired into CI and `verify.sh` (live control).
- **MCP capability gate** now recorded in the compliance crosswalk + audit-evidence checklist as **Kit-enforced** (with the honest by-name caveat: it gates MCP tool capability by name; the net.egress class is a name-match speed bump).

### Changed
- `platform-safety-boundary.md`, `EXEC-BRIEF.md`, and `DEVELOPMENT-PROCESS.md` §13 reconciled: the guard is a speed bump for shell/interpreter **and** a deny-by-default MCP capability gate (Kit-enforced); the four platform controls are kit-referenced + verify-wired (**Kit-assisted**) — enforcement remains platform-owned. No caveat removed (no overclaim).
- `containment-readiness.md`: documented that attestation dates are honor-based (the carried 11c LOW — resolved by documentation; both candidate code fixes would false-negative).

### Honesty
- The restatement only **adds qualifiers**; every honest caveat (deny-list speed bump, "these four controls are the boundary", platform-owned enforcement) is preserved. "Kit-enforced" appears only for the MCP gate, always with the by-name caveat. The drift-guard verifies the tiers are *stated*, not "true".
```

- [ ] **Step 4: Roadmap.** In `docs/ROADMAP-SLICE11.md`, set the `11d` row Status → `✅ shipped v2.43.0` with a one-line summary (match the 11a/11b/11c row style).

- [ ] **Step 5: Verify + commit.**

Run: `cat VERSION && sh conformance/check-links.sh 2>&1 | tail -1`.

```bash
git add VERSION README.md CHANGELOG.md docs/ROADMAP-SLICE11.md
git commit -m "chore(release): 2.43.0 — honesty & assurance restatement (11d)"
```

---

## Task 7: Final verify + independent security-owner review + PR

- [ ] **Step 1: Full suite (post-`cp`, live).**

```sh
sh conformance/assurance-tiers.sh --selftest >/dev/null && echo "assurance-tiers selftest OK"
sh conformance/assurance-tiers.sh >/dev/null && echo "assurance-tiers live OK (crosswalk tiers correct)"
sh conformance/containment-ready.sh --selftest >/dev/null && echo "containment selftest OK (regression)"
sh conformance/egress-policy.sh --selftest >/dev/null && echo "egress selftest OK (regression)"
sh conformance/check-links.sh >/dev/null && echo "links OK"
sh conformance/doc-budget.sh >/dev/null && echo "doc-budget OK"
sh conformance/badge-version.sh >/dev/null && echo "badge OK"
sh conformance/verify.sh 2>&1 | tail -1
```
Expected: all OK; `verify.sh` RESULT: OK (includes the new assurance-tiers control).

- [ ] **Step 2: Independent security-owner-lens review** (builder ≠ reviewer). Dispatch a security reviewer against `git diff main...HEAD` with the honesty framing: confirm (a) every edit ADDED a qualifier and DELETED no caveat — the deny-list-speed-bump argument, "these four controls are the boundary", and "platform-owned enforcement" all survive in each doc; (b) "Kit-enforced" appears ONLY for the MCP gate and ALWAYS carries the by-name caveat; (c) the crosswalk MCP row is Kit-enforced and the four platform rows are Kit-assisted (not Org-owned, not Kit-enforced); (d) `assurance-tiers.sh` is honest about verifying *stated* tiers, fail-closed on a revert/missing row, dash-clean, no fixture `rm -rf`; (e) no overclaim crept in anywhere (no sentence implies the kit enforces egress/FS/tokens or verifies their actual state). Fold cheap honesty-relevant findings; carry the rest.

- [ ] **Step 3: Push + open PR** (Bradley merges — agent never self-merges).

```bash
git push -u origin feature/slice-11d-honesty-restatement
gh pr create --base main --head feature/slice-11d-honesty-restatement --title "Slice 11d — Honesty & assurance restatement (v2.43.0)" --body "<summary: reconcile narratives to post-arc reality without overclaiming; MCP gate recorded Kit-enforced (by name); #1-4 Kit-assisted; assurance-tiers.sh drift-guard regression-locks the tiers; carried 11c LOW documented; MINOR>"
```

- [ ] **Step 4: Report** the PR number + merge command (`gh pr merge <n> --squash --admin --delete-branch`) and the next arc step (A9 — the red-team exit gate).

---

## Verification (whole slice)

- `assurance-tiers.sh --selftest` → 3 PASS, exit 0; live `assurance-tiers.sh` → 5 PASS, exit 0 (after the MCP row lands).
- A reverted tier (egress → Org-owned) or a missing arc row → FAIL (proven by selftest fixtures).
- Every narrative doc keeps its honest caveats; "Kit-enforced" only on the MCP gate, with the by-name caveat.
- `verify.sh` RESULT: OK (now including the assurance-tiers control); `check-links`, `doc-budget`, badge green; egress/containment regressions green.
- Governance: feature branch → PR → human ratification; `ci.yml` via control-plane `cp`; security-owner lens before PR.
