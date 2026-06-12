# Definition-of-Ready Robustness (Slice 9i-b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote the Definition of Ready from a scattered parenthetical to a first-class enumerated entry gate in `CLAUDE.md` (peer to the DoD), tied to the gate doc and the `FEATURE-REQUEST` intake, with a completeness drift-guard.

**Architecture:** A new `## Definition of "Ready"` block in `CLAUDE.md` above the DoD (DoD untouched); three reference-only edits in `DEVELOPMENT-PROCESS.md`; a DoR checklist in `FEATURE-REQUEST-TEMPLATE.md` + the `BACKLOG` Ready column; a POSIX-sh completeness guard `conformance/dor-defined.sh`; CI wiring. Additive → MINOR v2.34.0.

**Tech Stack:** Markdown + POSIX `sh`. Verified by `dor-defined.sh --selftest`, `dash -n`, `check-links.sh`, and a diff-review confirming the DoD block is byte-for-byte unchanged.

---

## Execution notes
- **One control-plane `cp`:** Task 6 (`.github/workflows/ci.yml`). Everything else is agent-editable (`conformance/dor-defined.sh` is in `conformance/`, not control-plane; `CLAUDE.md`/`DEVELOPMENT-PROCESS.md` are governing docs but not guard-protected — edited as proposals, ratified by merge).
- **`CLAUDE.md` is the authoritative principles file** — the new DoR block is **additive** (a new entry gate). The DoD block must remain byte-for-byte unchanged; this gets the security-owner lens at review.
- **Anonymization** ([[kit-anonymization]]): generic throughout.
- **Branch:** `feature/slice-9i-b-dor-robustness` (holds the spec already, commit `c979797`).

## File structure

| File | Responsibility |
|------|----------------|
| `CLAUDE.md` (modify) | New `## Definition of "Ready"` block above the DoD (entry gate vs exit gate); DoD untouched |
| `DEVELOPMENT-PROCESS.md` (modify) | §7 gate row, §11 ritual, §4 Plan line → reference the canonical DoR (no list duplication) |
| `templates/FEATURE-REQUEST-TEMPLATE.md` (modify) | New `## Definition of Ready` checklist section (fill-to-ready at intake) |
| `templates/BACKLOG-TEMPLATE.md` (modify) | "Ready" column blockquote → points at the enumerated DoR |
| `conformance/dor-defined.sh` (new) | Completeness drift-guard + `--selftest` |
| `conformance/README.md` (modify) | index row |
| `.github/workflows/ci.yml` (modify, **human cp**) | `dor-defined.sh` step + selftest |
| `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md` (modify) | 2.34.0; 9i-b row → shipped |

---

## Task 1: The DoR block in `CLAUDE.md` (governing surface)

**Files:** Modify `CLAUDE.md`

- [ ] **Step 1: Insert the `## Definition of "Ready"` block immediately above `## Definition of "Done"`.** Find this exact anchor (the DoD heading + its first two lines):

```
## Definition of "Done"

A feature is NOT done until ALL are true:
```

Replace it with the DoR block, a separator, and the **unchanged** DoD heading lines:

```
## Definition of "Ready"

The **entry gate** — an item is NOT ready to enter Build until ALL mandatory items are true. (The Definition of Done below is the **exit gate**: safe to ship.) Conditional items are quick applicability checks — mark **N/A** when they don't apply.

**Mandatory**
- **Acceptance criteria** — written and testable (how we'll know it's done).
- **INVEST-sliced** — a small, independent, vertical increment (not a phase or an epic).
- **Dependencies known** — blocking deps, data, and access identified.
- **Success metric / hypothesis** — a measurable statement of what "worked" means (§5 Discovery).

**Conditional flags** *(flag the obligation now so no downstream gate is a surprise)*
- **Threat-model** *(if sensitive/regulated)* — flagged for the §7 security gate.
- **UX/a11y obligation** *(if a user-facing surface)* — flagged; recorded later in the a11y sign-off (the Accessibility item below).
- **Eval criteria** *(if an AI feature)* — flagged for the §7 eval gate.
- **Compliance obligation** *(if a regulated domain)* — flagged for the §7 compliance gate.

If any **mandatory** box is unchecked, the item is **not Ready** — it does not enter Build.

---

## Definition of "Done"

A feature is NOT done until ALL are true:
```

- [ ] **Step 2: Verify the DoD block is byte-for-byte unchanged + links resolve.**
  Run: `git diff CLAUDE.md` — confirm the diff is **purely additive** (the DoR block + a `---`); no DoD line is modified or removed.
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → `OK: all relative Markdown links resolve`.
  Run: `grep -c 'Definition of "Done"' CLAUDE.md` → still `1` (we didn't duplicate the DoD).

- [ ] **Step 3: Commit.**
  ```bash
  git add CLAUDE.md
  git commit -m "docs(9i-b): add Definition of Ready entry gate to CLAUDE.md (peer to DoD; DoD unchanged)"
  ```

---

## Task 2: Reference the canonical DoR from `DEVELOPMENT-PROCESS.md`

**Files:** Modify `DEVELOPMENT-PROCESS.md` (three reference-only edits; no list duplication)

- [ ] **Step 1: §7 gate row.** Find:
```
| **Definition of Ready** | Safe to start? (criteria present, sliced, deps known) | Human/lead |
```
Replace with:
```
| **Definition of Ready** | Safe to start? (the enumerated entry gate in `CLAUDE.md` — criteria, INVEST slice, deps, success metric, + conditional flags) | Human/lead |
```

- [ ] **Step 2: §11 ritual line.** Find:
```
- **Definition of Ready** — readiness gate before Build.
```
Replace with:
```
- **Definition of Ready** — the enumerated entry gate before Build (`CLAUDE.md`, peer to the Definition of Done).
```

- [ ] **Step 3: §4 Plan-phase line.** Find (the Plan row in the stage table):
```
| **Plan** | Slice into small vertical increments; acceptance criteria; spec for non-trivial work; **threat-model** sensitive features. Must reach **Definition of Ready**. | Spec gate (human) |
```
Replace `Must reach **Definition of Ready**.` with `Must reach the **Definition of Ready** (the entry gate in \`CLAUDE.md\`).` — i.e. the new row is:
```
| **Plan** | Slice into small vertical increments; acceptance criteria; spec for non-trivial work; **threat-model** sensitive features. Must reach the **Definition of Ready** (the entry gate in `CLAUDE.md`). | Spec gate (human) |
```

- [ ] **Step 4: Verify + commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.
  Run: `grep -c "Definition of Ready" DEVELOPMENT-PROCESS.md` → ≥ 3 (the three referrers still present; the diagram mention at ~line 96 unaffected).
  ```bash
  git add DEVELOPMENT-PROCESS.md
  git commit -m "docs(9i-b): point §7/§11/§4 DoR references at the canonical CLAUDE.md entry gate"
  ```

---

## Task 3: Intake checklist (`FEATURE-REQUEST` + `BACKLOG`)

**Files:** Modify `templates/FEATURE-REQUEST-TEMPLATE.md`, `templates/BACKLOG-TEMPLATE.md`

- [ ] **Step 1: Append the DoR checklist to `FEATURE-REQUEST-TEMPLATE.md`.** The file currently ends with the `## UX & accessibility` section and its `[...]` placeholder (line 42). Append, at end of file:

```markdown

## Definition of Ready
> The entry gate (`CLAUDE.md`). Tick each mandatory box; flag each conditional item or write **N/A**. If a mandatory box can't be ticked, the item isn't Ready — that's useful signal, not a failure.

**Mandatory**
- [ ] Acceptance criteria written (testable)
- [ ] INVEST-sliced (small vertical increment)
- [ ] Dependencies known
- [ ] Success metric / hypothesis stated (see *Success metric / hypothesis* above)

**Conditional (flag or N/A)**
- [ ] Threat-model flagged — if sensitive/regulated
- [ ] UX/a11y obligation flagged — if user-facing (see *UX & accessibility* above)
- [ ] Eval criteria flagged — if an AI feature
- [ ] Compliance obligation flagged — if a regulated domain
```

- [ ] **Step 2: Update the `BACKLOG-TEMPLATE.md` "Ready" column.** Find:
```
> Passed Definition of Ready (criteria present, sliced, deps known). Safe to start.
```
Replace with:
```
> Passed the Definition of Ready (the enumerated entry gate in `CLAUDE.md`). Safe to start.
```

- [ ] **Step 3: Verify + commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.
  Run: `grep -q "Definition of Ready" templates/FEATURE-REQUEST-TEMPLATE.md && echo "intake ok"` → `intake ok`.
  Run: `grep -niE "enterprise|public.media|bradley" templates/FEATURE-REQUEST-TEMPLATE.md templates/BACKLOG-TEMPLATE.md || echo clean` → `clean`.
  ```bash
  git add templates/FEATURE-REQUEST-TEMPLATE.md templates/BACKLOG-TEMPLATE.md
  git commit -m "docs(9i-b): FEATURE-REQUEST carries the DoR checklist; BACKLOG Ready column points at it"
  ```

---

## Task 4: `conformance/dor-defined.sh`

**Files:** Create `conformance/dor-defined.sh`

- [ ] **Step 1: Write the check** (completeness drift-guard + two-tree `--selftest`, no `rm` — same shape as `persona-artifacts.sh`):

```sh
#!/bin/sh
# dor-defined.sh — completeness drift-guard for the Definition of Ready (Slice 9i-b).
# Asserts the DoR is a first-class, wired entry gate:
#   (a) CLAUDE.md carries a Definition of "Ready" block;
#   (b) DEVELOPMENT-PROCESS.md (the gate doc) references the DoR;
#   (c) templates/FEATURE-REQUEST-TEMPLATE.md carries a Definition of Ready section.
# Completeness, NOT content-equality. The DoR must be enumerated, referenced by the gate
# doc, and carried by the intake template — or this fails.
#   sh conformance/dor-defined.sh [--selftest]
# Exit: 0 = wired · 1 = a gap · 2 = bad usage. POSIX sh; dash-clean.
set -eu

PRINCIPLES="CLAUDE.md"
GATE_DOC="DEVELOPMENT-PROCESS.md"
INTAKE="templates/FEATURE-REQUEST-TEMPLATE.md"

# check_tree <principles> <gate-doc> <intake>: print PASS/FAIL; return 1 on any gap.
check_tree() {
  pf=$1; gf=$2; itf=$3; f=0
  if [ -f "$pf" ] && grep -q 'Definition of "Ready"' "$pf"; then
    echo "PASS: $pf carries the Definition of \"Ready\" block"
  else
    echo "FAIL: $pf has no Definition of \"Ready\" block"; f=1
  fi
  if [ -f "$gf" ] && grep -q 'Definition of Ready' "$gf"; then
    echo "PASS: $gf references the DoR gate"
  else
    echo "FAIL: $gf does not reference the DoR"; f=1
  fi
  if [ -f "$itf" ] && grep -q 'Definition of Ready' "$itf"; then
    echo "PASS: $itf carries a Definition of Ready section"
  else
    echo "FAIL: $itf has no Definition of Ready section"; f=1
  fi
  return $f
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  # gap tree: none of the three markers present -> must be detected
  g=$(mktemp -d)
  printf '# principles\nno ready block here\n' > "$g/CLAUDE.md"
  printf '# proc\nno gate ref\n' > "$g/proc.md"
  printf '# intake\nno dor section\n' > "$g/intake.md"
  if check_tree "$g/CLAUDE.md" "$g/proc.md" "$g/intake.md" >/dev/null 2>&1; then
    echo "FAIL: selftest — gap not detected"; sfail=1
  else
    echo "PASS: selftest — missing DoR block / gate ref / intake section detected"
  fi
  # complete tree: all three markers present -> must pass
  ok=$(mktemp -d)
  printf '# principles\n## Definition of "Ready"\n- acceptance criteria\n' > "$ok/CLAUDE.md"
  printf '# proc\nDefinition of Ready gate\n' > "$ok/proc.md"
  printf '# intake\n## Definition of Ready\n- [ ] acceptance criteria\n' > "$ok/intake.md"
  if check_tree "$ok/CLAUDE.md" "$ok/proc.md" "$ok/intake.md" >/dev/null 2>&1; then
    echo "PASS: selftest — complete set passes"
  else
    echo "FAIL: selftest — complete set wrongly rejected"; sfail=1
  fi
  [ "$sfail" -eq 0 ] && { echo "OK: dor-defined selftest"; exit 0; } || { echo "FAIL: dor-defined selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: dor-defined.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Definition-of-Ready wiring:"
if check_tree "$PRINCIPLES" "$GATE_DOC" "$INTAKE"; then
  echo "OK: DoR is enumerated in CLAUDE.md, referenced by the gate doc, and carried by the intake template"
  exit 0
else
  echo "FAIL: DoR wiring incomplete (see above)"
  exit 1
fi
```

- [ ] **Step 2: Make executable + dash-check.**
  Run: `chmod +x conformance/dor-defined.sh && dash -n conformance/dor-defined.sh && echo "syntax OK"`
  Expected: `syntax OK`.

- [ ] **Step 3: Run selftest + real check + bad usage.**
  Run: `sh conformance/dor-defined.sh --selftest; echo "exit=$?"` → two `PASS …` lines + `OK: dor-defined selftest`, `exit=0`.
  Run: `sh conformance/dor-defined.sh; echo "exit=$?"` → after Tasks 1–3, three `PASS` + `OK: …`, `exit=0`.
  Run: `sh conformance/dor-defined.sh --bogus; echo "exit=$?"` → `usage: …` on stderr, `exit=2`.

- [ ] **Step 4: Commit.**
  ```bash
  git add conformance/dor-defined.sh
  git commit -m "feat(conformance): 9i-b — dor-defined.sh completeness drift-guard (+ --selftest)"
  ```

---

## Task 5: conformance index row

**Files:** Modify `conformance/README.md`

- [ ] **Step 1: Add the index row.** In the table `| Check | Type | Contract it proves | Gate |`, after the `persona-artifacts.sh` row, add:
```markdown
| `dor-defined.sh` | script | Slice 9i-b — the Definition of Ready is enumerated in `CLAUDE.md`, referenced by the gate doc, and carried by the `FEATURE-REQUEST` intake; drift-guard | CI |
```

- [ ] **Step 2: Verify + commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.
  ```bash
  git add conformance/README.md
  git commit -m "docs(9i-b): conformance index row for dor-defined.sh"
  ```

---

## Task 6: Wire dor-defined into CI (control-plane `cp`)

**Files:** Modify `.github/workflows/ci.yml` (build `/tmp` → human applies)

- [ ] **Step 1: Build candidate.** Read `.github/workflows/ci.yml` with the Read tool. Write a copy to `/tmp/ci.yml.9ib` (use the Write tool — do NOT `cp`/`sed` the control-plane path) with two steps added to the `conformance` job immediately after the `Persona-artifact self-test` step:
  ```yaml
      - name: Definition-of-Ready wiring (DoR enumerated + gate + intake)
        run: sh conformance/dor-defined.sh
      - name: Definition-of-Ready self-test
        run: sh conformance/dor-defined.sh --selftest
  ```

- [ ] **Step 2: Validate the candidate.**
  Run: `ruby -ryaml -e 'd=YAML.load_file("/tmp/ci.yml.9ib"); puts d["jobs"].keys.join(",")'` → `conformance,bootstrap,docs-links`.
  Run: `diff .github/workflows/ci.yml /tmp/ci.yml.9ib` → the only diff is the two added steps (4 `>` lines). (`diff` is read-only; the guard allows it.)

- [ ] **Step 3: Hand to Bradley (human `cp`).** Present exactly:
  ```bash
  cd ~/Development/agentic-sdlc-kit && cp /tmp/ci.yml.9ib .github/workflows/ci.yml && git add .github/workflows/ci.yml && git commit -m "ci(kit): 9i-b — gate dor-defined wiring + selftest"
  ```
  Wait for confirmation before continuing.

---

## Task 7: Release (VERSION / CHANGELOG / roadmap)

**Files:** Modify `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md`

- [ ] **Step 1: `VERSION`** → replace `2.33.0` with `2.34.0`.

- [ ] **Step 2: CHANGELOG entry** immediately above `## [2.33.0]`:
  ```markdown
  ## [2.34.0] - 2026-06-10

  Definition-of-Ready robustness (Slice 9i-b, fast-follow of 9i). Promotes the DoR from a scattered parenthetical to a first-class enumerated entry gate, peer to the DoD. **MINOR** — additive block + template checklist + a completeness check; the Definition of Done is unchanged.

  ### Added
  - **`CLAUDE.md` — `## Definition of "Ready"`** entry gate above the DoD: 4 mandatory items (acceptance criteria · INVEST-sliced · deps known · success metric/hypothesis) + 4 conditional flags that map to existing §7 gates (threat-model / UX-a11y / eval / compliance). Frames DoR (entry) vs DoD (exit).
  - **`templates/FEATURE-REQUEST-TEMPLATE.md` — `## Definition of Ready`** checklist so an item is filled-to-ready at intake.
  - **`conformance/dor-defined.sh`** — completeness drift-guard (DoR enumerated in `CLAUDE.md` + referenced by the gate doc + carried by the intake template); `--selftest`. CI-gated.

  ### Changed
  - **`DEVELOPMENT-PROCESS.md` §7/§11/§4** DoR references now point at the canonical `CLAUDE.md` entry gate (no list duplication).
  - **`templates/BACKLOG-TEMPLATE.md`** "Ready" column points at the enumerated DoR.
  ```

- [ ] **Step 3: roadmap — mark 9i-b shipped.** In `docs/ROADMAP-SLICE9.md`, replace the `9i-b` row:
  ```markdown
  | **9i-b** ✅ | B | **Definition-of-Ready robustness** (fast-follow of 9i) — *shipped v2.34.0.* DoR promoted to a first-class enumerated entry gate in `CLAUDE.md` (peer to the DoD): 4 mandatory + 4 conditional flags mapping to existing §7 gates; §7/§11/§4 reference it; `FEATURE-REQUEST` carries the checklist; `dor-defined.sh` drift-guard. | P1 | MINOR ✅ |
  ```

- [ ] **Step 4: Verify + commit.**
  Run: `cat VERSION` → `2.34.0`. Run: `sh conformance/check-links.sh 2>&1 | tail -1` → resolve.
  ```bash
  git add VERSION CHANGELOG.md docs/ROADMAP-SLICE9.md
  git commit -m "chore(release): 2.34.0 — Definition-of-Ready robustness (9i-b)"
  ```

---

## Task 8: Final verification + independent review + PR

- [ ] **Step 1: Full local sweep.**
  ```sh
  sh conformance/dor-defined.sh >/dev/null && echo "dor-defined OK"
  sh conformance/dor-defined.sh --selftest >/dev/null && echo "selftest OK"
  dash -n conformance/dor-defined.sh && echo "dash OK"
  sh conformance/verify.sh 2>&1 | tail -1
  sh conformance/check-links.sh 2>&1 | tail -1
  git diff main..HEAD -- CLAUDE.md   # confirm the DoD block is byte-for-byte unchanged; only the DoR block is added
  grep -rniE "enterprise|public.media|bradley" conformance/dor-defined.sh templates/FEATURE-REQUEST-TEMPLATE.md || echo "anon clean"
  ```
  Expected: all OK; the `CLAUDE.md` diff is purely the additive DoR block (no DoD line touched); anon clean.

- [ ] **Step 2: Independent review (builder ≠ sole reviewer; CLAUDE.md is a governing surface → security-owner lens).** Dispatch a reviewer on `git diff main...HEAD`: (a) the `CLAUDE.md` DoR block is **additive** and the **DoD is byte-for-byte unchanged** (no requirement weakened); (b) the 8 DoR items and their gate mappings are honest — each conditional flag maps to a real §7 gate, none dangles; (c) `dor-defined.sh` POSIX correctness (`return $f`, three-file `check_tree`, two-tree selftest no-`rm`, exit codes 0/1/2, `set -eu`, `dash -n`); the selftest genuinely fails if the check were broken (gap tree fails on all three axes); (d) the FEATURE-REQUEST checklist is usable and consistent with the `CLAUDE.md` items; (e) anonymization. Fix findings; re-review if non-trivial.

- [ ] **Step 3: Push + open PR.**
  ```bash
  git push -u origin feature/slice-9i-b-dor-robustness
  gh pr create --base main --head feature/slice-9i-b-dor-robustness \
    --title "Slice 9i-b — Definition-of-Ready Robustness (v2.34.0)" --body-file /tmp/pr-9ib-body.md
  ```
  (Write `/tmp/pr-9ib-body.md`: the enumerated DoR entry gate peer to the DoD, the 8 items + gate mappings, DoD-unchanged guarantee, intake checklist, drift-guard, one cp, governance.)

- [ ] **Step 4: Confirm CI green; hand to Bradley to ratify (merge).** Agent never self-merges.

---

## Self-review (against the spec)
- **Spec coverage:** CLAUDE.md DoR block (Task 1) · §7/§11/§4 referrers (Task 2) · FEATURE-REQUEST checklist + BACKLOG Ready column (Task 3) · `dor-defined.sh` drift-guard (Task 4) · conformance index (Task 5) · CI cp (Task 6) · MINOR 2.34.0 + roadmap (Task 7) · review + PR (Task 8). All spec components + the DoD-unchanged guarantee covered.
- **Placeholder scan:** the DoR block, the checklist, and `dor-defined.sh` are complete literal content; doc edits have exact find/replace anchors. No placeholders.
- **Consistency:** the 8 DoR items are worded identically in the `CLAUDE.md` block (Task 1) and the FEATURE-REQUEST checklist (Task 3); the three grep markers in `dor-defined.sh` (`Definition of "Ready"` in CLAUDE.md, `Definition of Ready` in the gate doc + intake) match exactly what Tasks 1–3 write; version 2.34.0 consistent in Task 7.
