#!/usr/bin/env python3
"""auto-tag-on-merge installer (control-plane). Run from repo root. Idempotent.
Reads new-file bodies from scratchpad/auto-tag/ (flat scratch paths; mapped to real paths here).
Folds in version finishing -> 3.53.0."""
import os, sys

VER = "3.53.0"
DATE = "2026-06-27"
PAY = "scratchpad/auto-tag"

def die(m): print(f"apply.py ABORT: {m}", file=sys.stderr); sys.exit(1)
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
def patch(path, old, new):
    s = read(path)
    if new in s: print(f"  [skip] {path}: already patched"); return
    if old not in s: die(f"anchor not found in {path}: {old!r}")
    write(path, s.replace(old, new, 1), os.stat(path).st_mode & 0o777)
def replace_all(path, old, new):
    s = read(path)
    if old not in s:
        if new in s: print(f"  [skip] {path}: already replaced"); return
        die(f"replace anchor not found in {path}: {old!r}")
    write(path, s.replace(old, new), os.stat(path).st_mode & 0o777)
def append_once(path, marker, text):
    s = read(path)
    if marker in s: print(f"  [skip] {path}: marker present"); return
    write(path, s + text, os.stat(path).st_mode & 0o777)

print("== auto-tag-on-merge installer ==")

# -- 1. new files (flat scratch -> real paths)
print("-- install new files")
write("scripts/release-tag.sh", payload("scripts/release-tag.sh"), 0o755)
write(".github/workflows/release-tag.yml", payload("release-tag.yml"))
write("conformance/release-tag-wired.sh", payload("release-tag-wired.sh"), 0o755)
write("docs/operations/release-tag.gitlab-ci.yml", payload("docs/operations/release-tag.gitlab-ci.yml"))
write("docs/operations/release-tag.md", payload("docs/operations/release-tag.md"))

# -- 2. claims.tsv
print("-- claims.tsv")
TAB = "\t"
row = ("release-tag-on-merge" + TAB +
       "auto-tag-on-merge: v<VERSION> is tagged on the merge commit coherently + idempotently on any "
       "forge (FLOOR scripts/release-tag.sh proven by --selftest; GitHub binding live, GitLab reference)"
       + TAB + "sh conformance/release-tag-wired.sh")
append_once("conformance/claims.tsv", "release-tag-on-merge\t", row + "\n")

# -- 3. claims-registry REQUIRED_IDS (silent-drop integrity; NOT carved — all paths ship)
print("-- claims-registry REQUIRED_IDS")
patch("conformance/claims-registry.sh", 'orchestrator-loop"', 'orchestrator-loop release-tag-on-merge"')

# -- 4. verify.sh
print("-- verify.sh register")
patch("conformance/verify.sh",
      "check control orchestrator-loop sh conformance/orchestrator-loop-wired.sh",
      "check control orchestrator-loop sh conformance/orchestrator-loop-wired.sh\n"
      "check control release-tag       sh conformance/release-tag-wired.sh")

# -- 5. guard-core is_control_plane_path (tool path; release mechanics are control-plane)
print("-- guard-core is_control_plane_path")
patch(".claude/hooks/guard-core.sh",
      "    scripts/orchestrator-run.sh|*/scripts/orchestrator-run.sh|\\",
      "    scripts/orchestrator-run.sh|*/scripts/orchestrator-run.sh|\\\n"
      "    scripts/release-tag.sh|*/scripts/release-tag.sh|\\")
# shell-mutation parity (M2-S5 two-matcher standard): the SAME `agents/...agent.md)` tail ends BOTH
# shell matchers (the outer "mentions a control-plane path" grep AND the redirect-target grep), so a
# single replace_all adds release-tag.sh to both -> sed -i / > / mv against it are denied (run still allowed).
replace_all(".claude/hooks/guard-core.sh",
            "agents/[^[:space:]]*\\.agent\\.md)",
            "agents/[^[:space:]]*\\.agent\\.md|scripts/release-tag\\.sh)")

# -- 6. agent-autonomy regressions
print("-- agent-autonomy fixtures")
patch("conformance/agent-autonomy.sh",
      'if [ "$fail" -ne 0 ]; then echo "FAIL: agent-autonomy conformance failed"; exit 1; fi',
      "# --- auto-tag: release-tag.sh is control-plane (DENY write/redirect/sed, ALLOW read/run) ---\n"
      "assert_deny \"Write release-tag\"    '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"scripts/release-tag.sh\",\"content\":\"x\"}}'\n"
      "assert_deny \"redirect release-tag\" '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo x > scripts/release-tag.sh\"}}'\n"
      "assert_deny \"sed -i release-tag\"   '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"sed -i s/a/b/ scripts/release-tag.sh\"}}'\n"
      "assert_allow \"run release-tag\"     '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"sh scripts/release-tag.sh --dry-run\"}}'\n"
      'if [ "$fail" -ne 0 ]; then echo "FAIL: agent-autonomy conformance failed"; exit 1; fi')

# -- 7. ci.yml: wire both new --selftests (ci-selftest-coverage requires their basenames in ci.yml)
print("-- ci.yml selftest wiring")
patch(".github/workflows/ci.yml",
      "        run: sh conformance/orchestrator-loop-wired.sh --selftest",
      "        run: sh conformance/orchestrator-loop-wired.sh --selftest\n"
      "      - name: release-tag FLOOR self-test (auto-tag decision logic)\n"
      "        run: sh scripts/release-tag.sh --selftest\n"
      "      - name: release-tag-wired self-test (FLOOR+NATIVE wiring lock)\n"
      "        run: sh conformance/release-tag-wired.sh --selftest")

# -- 8. version finishing -> 3.53.0
print("-- version finishing -> %s" % VER)
write("VERSION", VER + "\n")
patch("README.md", "`v3.52.0`", "`v" + VER + "`")
entry = (f"## [{VER}] — {DATE}\n\n"
         "### Added\n"
         "- **Auto-tag-on-merge** — removes the human from release tagging (the recurring premature-tag "
         "fumble). Forge-neutral FLOOR `scripts/release-tag.sh` (read VERSION -> assert coherence inline via "
         "`version-tag-coherent.sh --require` -> tag `v<VERSION>` on the merge commit if absent -> push; "
         "idempotent, coherent by construction). NATIVE bindings: a live GitHub workflow "
         "(`.github/workflows/release-tag.yml`, `on: push main`, `contents: write`), a GitLab reference "
         "(`docs/operations/release-tag.gitlab-ci.yml`), and a generic-forge doc. Behaviour lock "
         "`release-tag-on-merge`. The existing `release-coherence.yml` stays as the tag-push backstop.\n\n"
         "### Honest ceiling\n"
         "- The FLOOR proves the *decision* (`--selftest`); the `git push` is exercised live, and forge auth is "
         "the binding's concern. It does not choose the version value (that's apply.py version-finishing). Manual "
         "`git tag` still works — the workflow no-ops if the tag exists.\n\n")
patch("CHANGELOG.md", "## [3.52.0] — 2026-06-26", entry + "## [3.52.0] — 2026-06-26")
patch("docs/ROADMAP-KIT.md", "**Last Updated:** 2026-06-26 (",
      "**Last Updated:** 2026-06-27 (**auto-tag-on-merge SHIPPED — v3.53.0** [forge-neutral FLOOR "
      "`scripts/release-tag.sh` + live GitHub binding + GitLab reference + generic doc; tags `v<VERSION>` on the "
      "merge commit coherently/idempotently; removes the human from release tagging; lock `release-tag-on-merge`; "
      "existing release-coherence gate unchanged]. Prior: (")

print("\n== auto-tag-on-merge installer: DONE. ==")
