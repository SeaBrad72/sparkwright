#!/usr/bin/env python3
"""E3a installer — applies the thin 4-seat orchestrator-loop slice (control-plane).

Run from the repo root. Idempotent: every edit checks its own anchor / applied-marker.
Reads new-file bodies from scratchpad/e3a/ (copied into the clone for the dry-run).
Folds in version finishing (VERSION/README/CHANGELOG/ROADMAP -> 3.52.0) + the meta-control GO verdict."""
import json, os, sys

VER = "3.52.0"
DATE = "2026-06-26"
PAY = "scratchpad/e3a"

def die(msg): print(f"apply.py ABORT: {msg}", file=sys.stderr); sys.exit(1)
def read(p):
    with open(p, encoding="utf-8") as f: return f.read()
def write(p, s, mode=0o644):
    os.makedirs(os.path.dirname(p) or ".", exist_ok=True)
    with open(p, "w", encoding="utf-8") as f: f.write(s)
    os.chmod(p, mode); print(f"  wrote {p}")
def payload(rel):
    p = os.path.join(PAY, rel)
    if not os.path.exists(p): die(f"payload missing: {p}")
    return read(p)
def patch(path, old, new, required=True):
    s = read(path)
    if new in s: print(f"  [skip] {path}: already patched"); return
    if old not in s:
        if required: die(f"anchor not found in {path}: {old!r}")
        print(f"  [warn] anchor absent in {path}: {old!r}"); return
    write(path, s.replace(old, new, 1), os.stat(path).st_mode & 0o777)
def replace_all(path, old, new):
    s = read(path)
    if old not in s:
        if new in s: print(f"  [skip] {path}: {old!r} already repointed"); return
        die(f"repoint anchor not found in {path}: {old!r}")
    write(path, s.replace(old, new), os.stat(path).st_mode & 0o777)
def append_once(path, marker, text):
    s = read(path)
    if marker in s: print(f"  [skip] {path}: append marker present"); return
    write(path, s + text, os.stat(path).st_mode & 0o777)

print("== E3a installer ==")

# ---------------------------------------------------------------- 1. new files
print("-- install new files")
for a in ("orchestrator", "engineer", "reviewer", "security"):
    write(f"agents/{a}.agent.md", payload(f"agents/{a}.agent.md"))
write(".claude/agents/orchestrator.md", payload("claude-agents/orchestrator.md"))
write(".claude/agents/engineer.md", payload("claude-agents/engineer.md"))
loop = payload("scripts/orchestrator-run.sh").replace('printf "$budget"', "printf '%b' \"$budget\"")
write("scripts/orchestrator-run.sh", loop, 0o755)
write("scripts/fixtures/engineer-fixture.sh", payload("scripts/fixtures/engineer-fixture.sh"), 0o755)
lock = payload("conformance/orchestrator-loop-wired.sh").replace(
    'grep -qF "runaway-guard.sh step" "$f"',
    "grep -Eq 'runaway-guard\\.sh\"?[[:space:]]+step' \"$f\"")
write("conformance/orchestrator-loop-wired.sh", lock, 0o755)

# ---------------------------------------------------------------- 2. retire stand-in
print("-- retire the E5-thin stand-in")
if os.path.exists("scripts/orchestrator-trace-demo.sh"):
    os.remove("scripts/orchestrator-trace-demo.sh"); print("  removed scripts/orchestrator-trace-demo.sh")
else: print("  [skip] stand-in already removed")

# ---------------------------------------------------------------- 3. FLOOR ref lines
print("-- link native defs to FLOOR")
append_once(".claude/agents/reviewer.md", "FLOOR contract: agents/reviewer.agent.md",
            "\n> FLOOR contract: agents/reviewer.agent.md\n")
append_once(".claude/agents/security-reviewer.md", "FLOOR contract: agents/security.agent.md",
            "\n> FLOOR contract: agents/security.agent.md\n")

# ---------------------------------------------------------------- 4. adapter.json orchestration dim
print("-- adapter.json: orchestration dimension")
def add_dim(path, val):
    m = json.loads(read(path))
    if "orchestration" in m.get("dimensions", {}): print(f"  [skip] {path}: orchestration present"); return
    m.setdefault("dimensions", {})["orchestration"] = val
    write(path, json.dumps(m, indent=2) + "\n", os.stat(path).st_mode & 0o777)
add_dim("adapters/claude-code/adapter.json",
        {"level": "native", "proof": {"files": [".claude/agents/orchestrator.md", ".claude/agents/engineer.md",
                                                  "agents/orchestrator.agent.md", "agents/engineer.agent.md"]}})
for h in ("codex", "cursor", "gemini", "generic", "_TEMPLATE"):
    add_dim(f"adapters/{h}/adapter.json", {"level": "floor"})

# ---------------------------------------------------------------- 5. harness-adapter.sh
print("-- harness-adapter.sh: require orchestration")
patch("conformance/harness-adapter.sh",
      'DIMS="context-binding command-guard history-protection review-roles mcp-gate"',
      'DIMS="context-binding command-guard history-protection review-roles mcp-gate orchestration"')
patch("conformance/harness-adapter.sh",
      "    mcp-gate)           [ -f scripts/kit-guard ] ;;",
      "    mcp-gate)           [ -f scripts/kit-guard ] ;;\n"
      "    orchestration)      [ -f agents/orchestrator.agent.md ] && [ -f agents/engineer.agent.md ] && [ -f agents/reviewer.agent.md ] && [ -f agents/security.agent.md ] ;;")
replace_all("conformance/harness-adapter.sh",
            '"mcp-gate":{"level":"n-a"}}}',
            '"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"}}}')
patch("conformance/harness-adapter.sh",
      '  expect 1 "$base/missing" "missing review-roles dimension"',
      '  expect 1 "$base/missing" "missing review-roles dimension"\n\n'
      '  mkconf "$base/missorch" \'{"harness":"fixture","controlPlanePaths":[".claude/settings.json"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"}}}\'\n'
      '  expect 1 "$base/missorch" "missing orchestration dimension"')

# ---------------------------------------------------------------- 6. named-adapters.sh fixtures
print("-- named-adapters.sh: fixtures declare orchestration")
replace_all("conformance/named-adapters.sh",
            '"mcp-gate":{"level":"n-a"}}}',
            '"mcp-gate":{"level":"n-a"},"orchestration":{"level":"floor"}}}')

# ---------------------------------------------------------------- 7. claims.tsv (+ B1 runaway qualifier)
print("-- claims.tsv: orchestrator-loop claim + discharge panel-#4 B1")
TAB = "\t"
row = ("orchestrator-loop" + TAB +
       "the 4-seat orchestration loop runs end-to-end (fan-out -> contain -> integrate -> trace) "
       "-- reference loop proven by golden-path on a fixture engineer; LLM agent work exercised live, substituted in CI"
       + TAB + "sh conformance/orchestrator-loop-wired.sh")
append_once("conformance/claims.tsv", "orchestrator-loop\t", row + "\n")
patch("conformance/claims.tsv",
      "the runaway circuit-breaker is installed and enforces token/step/agent ceilings",
      "the runaway circuit-breaker is installed and enforces token/step/agent ceilings on reported usage "
      "(agent-immutable config; best-effort post-step tally; enforced when the orchestration loop calls it)")

# ---------------------------------------------------------------- 8. verify.sh registration
print("-- verify.sh: register the lock")
patch("conformance/verify.sh",
      "check control mode-blind       sh conformance/mode-enforcement-blind.sh",
      "check control mode-blind       sh conformance/mode-enforcement-blind.sh\n"
      "check control orchestrator-loop sh conformance/orchestrator-loop-wired.sh")

# ---------------------------------------------------------------- 8b. claims-registry REQUIRED_IDS (silent-drop integrity)
print("-- claims-registry.sh: add orchestrator-loop to REQUIRED_IDS (carved on export like its siblings)")
patch("conformance/claims-registry.sh",
      "runaway-killswitch version-tag-coherent\"",
      "runaway-killswitch version-tag-coherent orchestrator-loop\"")

# ---------------------------------------------------------------- 9. guard-core.sh control-plane
print("-- guard-core.sh: roster *.agent.md + orchestrator-run.sh control-plane (tool + shell matchers)")
# is_control_plane_path (tool path) — SCOPED to the roster contract files, NOT the whole agents/ dir
# (an adopter's src/agents/ app code must stay writable).
patch(".claude/hooks/guard-core.sh",
      "    scripts/runaway-guard.sh|*/scripts/runaway-guard.sh|\\",
      "    scripts/runaway-guard.sh|*/scripts/runaway-guard.sh|\\\n"
      "    scripts/orchestrator-run.sh|*/scripts/orchestrator-run.sh|\\\n"
      "    agents/*.agent.md|*/agents/*.agent.md|\\")
# outer "mentions a control-plane path" matcher (line 77): add the loop script AND the roster defs,
# so `sed -i`/`mv`/`tee` against them is denied (run/read still falls through to the WS1 allow-back).
patch(".claude/hooks/guard-core.sh",
      "hooks/pre-push|scripts/kit-guard|docs/governance/\\.meta-control-last|docs/governance/meta-control-log\\.md|\\.kit/budget\\.conf)'; then",
      "hooks/pre-push|scripts/kit-guard|docs/governance/\\.meta-control-last|docs/governance/meta-control-log\\.md|\\.kit/budget\\.conf|scripts/orchestrator-run\\.sh|agents/[^[:space:]]*\\.agent\\.md)'; then")
# inner redirect-target matcher (line 80): deny `> scripts/orchestrator-run.sh` AND `> agents/*.agent.md`
patch(".claude/hooks/guard-core.sh",
      ">[[:space:]]*[^[:space:]]*(\\.claude|\\.github/workflows|CODEOWNERS|\\.git|hooks/pre-push|scripts/kit-guard|docs/governance/\\.meta-control-last|docs/governance/meta-control-log\\.md|\\.kit/budget\\.conf)",
      ">[[:space:]]*[^[:space:]]*(\\.claude|\\.github/workflows|CODEOWNERS|\\.git|hooks/pre-push|scripts/kit-guard|docs/governance/\\.meta-control-last|docs/governance/meta-control-log\\.md|\\.kit/budget\\.conf|scripts/orchestrator-run\\.sh|agents/[^[:space:]]*\\.agent\\.md)")

# ---------------------------------------------------------------- 10. agent-autonomy.sh fixtures
print("-- agent-autonomy.sh: E3a deny/allow regressions (tool + shell parity, + adopter over-block guard)")
patch("conformance/agent-autonomy.sh",
      'if [ "$fail" -ne 0 ]; then echo "FAIL: agent-autonomy conformance failed"; exit 1; fi',
      "# --- E3a: roster FLOOR defs + the loop script are control-plane (DENY write/redirect/sed, ALLOW read/run) ---\n"
      "assert_deny \"Write roster def\"      '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"agents/orchestrator.agent.md\",\"content\":\"x\"}}'\n"
      "assert_deny \"Edit loop script\"      '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"scripts/orchestrator-run.sh\",\"old_string\":\"a\",\"new_string\":\"b\"}}'\n"
      "assert_deny \"redirect over loop\"    '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo x > scripts/orchestrator-run.sh\"}}'\n"
      "assert_deny \"redirect over roster\"  '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo x > agents/orchestrator.agent.md\"}}'\n"
      "assert_deny \"sed -i over roster\"    '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"sed -i s/a/b/ agents/security.agent.md\"}}'\n"
      "assert_allow \"read roster def\"      '{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"agents/engineer.agent.md\"}}'\n"
      "assert_allow \"run loop script\"      '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"sh scripts/orchestrator-run.sh alpha\"}}'\n"
      "assert_allow \"adopter agents code\"  '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"src/agents/handler.ts\",\"content\":\"x\"}}'\n"
      'if [ "$fail" -ne 0 ]; then echo "FAIL: agent-autonomy conformance failed"; exit 1; fi')

# ---------------------------------------------------------------- 11. golden-path.yml + ci.yml
print("-- golden-path.yml: agentops repoint + orchestrator-loop job + filters")
GP = ".github/workflows/golden-path.yml"
replace_all(GP, "sh scripts/orchestrator-trace-demo.sh", "sh scripts/orchestrator-run.sh")
replace_all(GP, "'scripts/orchestrator-trace-demo.sh'",
            "'scripts/orchestrator-run.sh', 'scripts/fixtures/engineer-fixture.sh', 'conformance/orchestrator-loop-wired.sh'")
patch(GP,
      '          echo "agentops-sensor: OK — real emit->adapt->score loop, denial_rate derived from emitted span"',
      '          echo "agentops-sensor: OK — real emit->adapt->score loop, denial_rate derived from emitted span"\n'
      "\n"
      "  orchestrator-loop:\n"
      "    # E3a — PROVE the thin 4-seat loop runs end-to-end: fan-out (isolated worktrees) -> contain\n"
      "    # (runaway-guard halts on breach) -> integrate -> emit the trace the scorecard reads. The\n"
      "    # fixture engineer is the deterministic null-LLM actor; an LLM engineer rides the same rails live.\n"
      "    runs-on: ubuntu-latest\n"
      "    steps:\n"
      "      - uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10  # v6.0.3\n"
      "      - name: the orchestration loop runs (fan-out + guard-halt + integrate + trace)\n"
      "        run: |\n"
      "          sh scripts/orchestrator-run.sh --selftest\n"
      "          sh conformance/orchestrator-loop-wired.sh --selftest\n"
      '          echo "orchestrator-loop: OK — real loop self-isolating selftest + wiring lock green"')
print("-- ci.yml: repoint stand-in selftest + wire orchestrator-loop selftest")
replace_all(".github/workflows/ci.yml",
            "sh scripts/orchestrator-trace-demo.sh --selftest",
            "sh scripts/orchestrator-run.sh --selftest")
patch(".github/workflows/ci.yml",
      "        run: sh conformance/agentops-sensor-wired.sh --selftest",
      "        run: sh conformance/agentops-sensor-wired.sh --selftest\n"
      "      - name: orchestrator-loop self-test (E3a — real loop + wiring lock)\n"
      "        run: sh conformance/orchestrator-loop-wired.sh --selftest")

# ---------------------------------------------------------------- 12. agentops-sensor-wired.sh repoint
print("-- agentops-sensor-wired.sh: repoint to orchestrator-run")
replace_all("conformance/agentops-sensor-wired.sh", "orchestrator-trace-demo", "orchestrator-run")

# ---------------------------------------------------------------- 13. adopter-export carve (both loops)
print("-- adopter-export.sh: carve orchestrator-loop (both loops)")
replace_all("scripts/adopter-export.sh", "runtime-security agentops-sensor; do",
            "runtime-security agentops-sensor orchestrator-loop; do")

# ---------------------------------------------------------------- 14. agentic-ops.md note
print("-- agentic-ops.md: stand-in -> real loop note")
replace_all("docs/operations/agentic-ops.md", "orchestrator-trace-demo", "orchestrator-run")

# ---------------------------------------------------------------- 15. version finishing
print("-- version finishing -> %s" % VER)
write("VERSION", VER + "\n")
patch("README.md", "`v3.51.1`", "`v" + VER + "`")
entry = (f"## [{VER}] — {DATE}\n\n"
         "### Added\n"
         "- **E3a — the thin 4-seat orchestrator loop** (Orchestrator + Engineer×N + Reviewer + Security): "
         "fresh-authored harness-neutral roster (`agents/*.agent.md` FLOOR + `.claude/agents/` NATIVE bindings) "
         "+ the real mechanical loop `scripts/orchestrator-run.sh` (fan-out to isolated git worktrees -> meter each "
         "step through `runaway-guard.sh step` [the kill-switch's first live call-site] -> integrate -> emit the OTel "
         "trace the **unchanged** scorecard reads). Replaces the E5-thin stand-in (`orchestrator-trace-demo.sh`, retired). "
         "Deterministic fixture engineer proves the loop in CI without an LLM (self-isolating selftest + golden-path "
         "`orchestrator-loop` job). New `orchestration` adapter dimension proves the roster binding per harness. "
         "Behaviour lock `orchestrator-loop` (claim).\n"
         "- **Self-hosting commitment** (owner-ratified): the kit ships its own fresh-authored superpowers-equivalent "
         "and progressively shifts its own build onto it; E10 capstone = build a slice using only the kit's own roster.\n\n"
         "### Honest ceiling\n"
         "- E3a proves the loop's *mechanics*, not that an LLM writes good code. Enforced worktree isolation, "
         "conflict-safe parallel writes, and guard-at-fleet-scale are E3b/E4 (see the §10 status table in "
         "`docs/operations/orchestration.md`). The runaway meter is post-step/cumulative (bounds total fan-out; not "
         "per-action sandboxing). Security's threat-model hat is authored but only the review hat is exercised by the thin loop.\n\n")
patch("CHANGELOG.md", "## [3.51.1] — 2026-06-26", entry + "## [3.51.1] — 2026-06-26")
patch("docs/ROADMAP-KIT.md", "**Last Updated:** 2026-06-26 (",
      "**Last Updated:** 2026-06-26 (**E3a — thin 4-seat orchestrator loop SHIPPED — v3.52.0** "
      "[Orchestrator + Engineer×N + Reviewer + Security; real `scripts/orchestrator-run.sh` replaces the E5-thin "
      "stand-in + wires `runaway-guard.sh step` (first live caller); FLOOR roster `agents/*.agent.md` + NATIVE "
      "`.claude/agents/` bindings + `orchestration` adapter dimension; deterministic fixture-engineer proof + "
      "golden-path `orchestrator-loop` job; claim `orchestrator-loop`. **Self-hosting ratified** — kit ships its own "
      "superpowers-equivalent, E10 = build a slice with only the kit's roster. Meta-control panel #5 = GO]. Prior: (")

# ---------------------------------------------------------------- 16. meta-control verdict (A5)
print("-- meta-control: panel #5 verdict log + marker (3.52.0 GO; marker==VERSION = allowed ship-seam)")
logrow = ("| 2026-06-26 | 3.52.0 | E3a per-slice M verdict (A5) + freshness cadence | light (5-lens) | GO | "
          "docs/architecture/2026-06-26-meta-control-5.md | 0 blockers · 0 highs · A1/A2/A5 honored "
          "(§10 table present, runaway-guard wired+A2-teeth-locked, this panel = A5); honesty truthful+surfaced "
          "(mechanics-not-LLM-quality, isolation used-not-enforced, threat-model authored-not-exercised); "
          "orchestration adapter dim = real binding seam; self-host bounded to E10; fix-forward folded "
          "(B1 runaway qualifier, self-host tense, guard agents/ scope+shell-parity per dual review) |\n")
append_once("docs/governance/meta-control-log.md", "| 2026-06-26 | 3.52.0 | E3a", logrow)
write("docs/governance/.meta-control-last", "3.52.0 GO\n")

print("\n== E3a installer: DONE. ==")
