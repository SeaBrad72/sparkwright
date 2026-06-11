# A9 — Arc Exit Red-Team: Containment & the Platform Boundary

**Type:** Analysis run (the arc's exit gate; no production change in this artifact). **Lens:** adversarial security-owner.
**Arc:** [`docs/ROADMAP-SLICE11.md`](../../ROADMAP-SLICE11.md). Closes the loop opened by [A8](2026-06-10-A8-mcp-egress-attack-surface.md). Built on v2.43.0 (11a–11d shipped).
**Method:** three independent adversarial red-teams (MCP gate / egress+containment honesty / cross-arc honesty ledger), each driving the **live** controls, not reading alone. Findings reconciled below.

**North star (A8):** *"Nothing should become a green check that implies containment a shell cannot deliver."*

---

## Verdict

**ARC CLOSES HONESTLY ONCE ONE GAP IS REMEDIATED** — the `secret.read` MCP class (A8 family 6), designated **deny-by-default** in the arc's own attack map, ships as **ALLOW** with no disclosure. This is both a real exposure (the read half of exfil) and an honesty defect (A8's honesty-check claims it is "genuinely denied"). **Resolution ratified: gate it** (Slice 11e). Everything else holds.

| Facet | Verdict |
|-------|---------|
| **W3 — MCP capability gate** | Structurally **closed-in-kit** (deny-by-default, fail-closed, control-plane-protected, spoofing-resistant) **except `secret.read`** (the one blocker). |
| **W2 — egress / containment conformance** | **Honestly bounded** — no false-PASS, no overclaim, interpreter tail correctly platform-owned. Two LOW honor-based nits (optional). |
| **Cross-arc honesty** | **Holds** — no green check implies containment a shell can't deliver; tiers honest; honor-based-attestation MED disclosed + carried. |

---

## Finding A9-1 — `secret.read` MCP tools are ALLOWed, undisclosed (BLOCKER → remediating in 11e)

**A8's design** ([A8](2026-06-10-A8-mcp-egress-attack-surface.md) line 51, line 64, line 147): family 6 `secret.read` — *"reading a credential is read-only yet feeds exfil, so it is **deny-by-default**"*; the §1.3 taxonomy lists `secret.read | … | **deny**`; the honesty-check lists `secret.read` among classes the gate *"genuinely denies."*

**Shipped reality** (`guard_check_mcp`, `.claude/hooks/guard-core.sh`): the tokenized classifier leads with read verbs (`read get list …`) and has **no secret-material signal**, so secret-reads classify as ordinary `data.read` → **ALLOW**. Confirmed live (`sh .claude/hooks/guard.sh`):

```
mcp__vault__read                     -> ALLOW
mcp__aws__get_secret_value           -> ALLOW
mcp__1password__get_item             -> ALLOW
mcp__google_drive__read_file_content -> ALLOW
mcp__x__get_secret                   -> ALLOW
(mcp__filesystem__delete_file        -> DENY, for contrast)
```

**Why it blocks clean closure.** It is the *read half* of exfil that A8 explicitly paired with the (correctly-denied) `msg.send` half — an agent can pull a credential into context. More decisively for an *honesty* arc: A8 (the arc's source-of-truth) claims this class is gated; the shipped honest-ceiling discloses only *renamed/obfuscated* actions, not *plainly-named secret reads*. A reader is led to believe a control exists that does not. That violates the north star.

**Design note for the remediation (11e).** The gate classifies by the **action** segment only, but secret-ness frequently lives in the **server** (`mcp__vault__read` → action is just `read`). A robust-as-possible-by-name close needs **both**: (a) an action-token secret-noun catch (`secret/credential/token/password/api_key/private_key/passphrase`), and (b) a known-secret-store **server** catch on read-led actions (`vault/1password/onepassword/secretsmanager/keyvault/ssm/sops/credstash/doppler/infisical`). Plus an **honest ceiling**: a secret read through a generic-named server/action (e.g. `mcp__storage__read_blob` holding secrets) is **not** caught by name — the same disclosed ceiling as the rest of the gate; the real close is the 11c sandbox (FS can't read host secrets) + scoped tokens.

---

## What HOLDS (confirmed live)

### W3 — MCP gate (everything except A9-1)
- **8 of 9 deny-by-default families deny out-of-box** (empty policy): fs.write, db.mutate, cloud.deploy, cloud.delete, vcs.write, msg.send, pkg.publish all DENY; `data.read` allows.
- **Classifier spoofing resists tokenization attacks:** `list_and_delete`, `describe_then_drop`, `getDelete`, `fetchAndExport`, `read_then_upload` all DENY; non-verb lookalikes (`getter`, `counter`) fail-closed DENY.
- **Fail-closed** on malformed JSON and jq-absent (the `mcp__*` matcher routes to a fail-closed deny).
- **Policy is control-plane-protected** — the agent cannot widen its own `.claude/mcp-policy.json` allowlist (Write/Edit/relative/absolute/`./`-prefixed all denied).
- **Wired-not-dark:** `mcp-policy.sh` structurally asserts the `mcp__*` PreToolUse matcher is present.

### W3 — disclosed bounds (honest, not blockers)
- **`net.egress` MCP class is a name-match speed bump, not containment** — disclosed in `guard-core.sh` honest-ceiling, the 11a spec, the crosswalk, and the boundary doc. `mcp__http__fetch_url` ALLOWing is consistent with "name match only."
- **Built-in `WebFetch`** (A8 family 7) is not `mcp__`-prefixed, so the MCP gate doesn't see it; it is `permissions.ask`-gated in `settings.json` (a UI prompt). Egress is platform-owned by design — disclosed, MED, acceptable-with-disclosure.
- **Server-wildcard** (`mcp__server__*` allowlist entry) bypasses classification for that server — a documented, human-authored, control-plane opt-in. LOW, disclosed.

### W2 — egress / containment conformance
- **Three-state machinery is honest:** UNVERIFIED (exit 2) genuinely escalates to FAIL (exit 1) under CI/`--require`; no UNVERIFIED path can be coaxed to PASS. Weakest-aspect aggregation holds (2-of-3 PASS + 1 FAIL → FAIL). Same-line attestation anchoring, substring-key defense, N/A token-anchoring, and date-shape all hold under adversarial fixtures.
- **No overclaim:** every PASS string carries an explicit disclaimer ("does NOT verify traffic is actually blocked / the FS is actually read-only / tokens actually expire"); the reference docs attach "closes/contains" only to the **platform** control; `egress-control.md` states the check "does not inspect traffic."
- **W2 tail correctly platform-owned:** nothing in 11b/11c claims the interpreter/DNS/build-tool exfil tail is *closed by the kit*.
- **LOW-1 (optional):** `egress-policy.sh` declares egress present on any mechanism keyword incl. bare `proxy`, and never requires a `default-deny` token — so a line describing allow-all-via-proxy + a date can PASS. Honor-based self-attestation gap (the real "default-deny + least-privilege" check is a Manual row), not an overclaim.
- **LOW-2 (optional):** `containment-ready.sh` aspect lines need only `<key>: … enforced: <date>` with no mechanism token — `Prod credentials: we share one root key — enforced: <date>` PASSes. Explicitly conceded as honor-based in `containment-readiness.md`.
- **INFO:** surface-trigger asymmetry — egress keys on a *deploy* surface, containment on *any* workflow; a CI-only repo with real outbound exposure is N/A for egress but in-scope for containment. Documented conditional model.

### Cross-arc honesty
- **Tiers honest + locked:** crosswalk states MCP gate = Kit-enforced (by name), the four platform controls = Kit-assisted (host-enforced); `assurance-tiers.sh` regression-locks this (final-cell match, un-gameable).
- **Green-check audit:** every new check (`mcp-policy.sh`, `egress-policy.sh`, `containment-ready.sh`, `assurance-tiers.sh`) states what a PASS does **not** prove; none implies containment a shell can't deliver.
- **Honor-based attestation (MED, disclosed, carried):** `egress-policy.sh` / `containment-ready.sh` treat a RUNBOOK `enforced: <date>` as the authoritative "wired" signal — a project can type a date without the control existing. Disclosed in CHANGELOG 2.43.0 + the readiness Manual rows. Carry forward; keep the Manual-row adjacency explicit in any auditor-facing packaging.

---

## Residual ledger (post-arc, after 11e lands)

| Residual | Severity | Status |
|----------|----------|--------|
| **W3** (guard saw only Bash-family tools) | was HIGH | **CLOSED-IN-KIT** once 11e gates `secret.read` (Kit-enforced, by name, regression-locked) |
| **W2** (no interpreter-egress control) | was HIGH | **HONESTLY BOUNDED / platform-owned** — reference shipped + wiring verified three-state; in-process tail never claimed closed (open-by-design) |
| **Honor-based attestation** | MED | disclosed; carried forward (Manual-row adjacency) |
| **`net.egress` / `secret.read` name-match ceiling** | LOW | disclosed in 11e's honest-ceiling — a generic-named secret store / in-server egress is not caught by name; real close is the 11c sandbox + platform egress allowlist |
| **W2 honor-based self-attestation nits (LOW-1/LOW-2)** | LOW | optional tightening; not blocking |

**No new residual** was introduced by the arc beyond the disclosed honor-based-attestation dependency. The boundary statement ("these four controls are the boundary … platform-owned") is preserved verbatim throughout.

---

## Disposition

1. **11e — `secret.read` gating remediation** (ratified): gate the named secret-read surface (action-noun + secret-store server), disclose the generic-named ceiling, correct A8's honesty-check + the guard-core ceiling, add corpus cases. Then W3 is fully closed-in-kit.
2. On 11e merge, mark **A9 ✅** and the **Containment arc CLOSED** (W3 closed-in-kit; W2 honestly-bounded/platform-owned), carrying the honor-based-attestation MED forward as a documented, auditor-adjacent residual.
3. The two W2 LOW nits are optional and may be folded into 11e or left as documented honor-based behavior.
