#!/usr/bin/env python3
"""release-tag guarded-manual installer (control-plane). Run from repo root. Idempotent.
Removes the live auto-tag binding, installs the opt-in reference + updated lock + doc,
updates the claim text, and folds in version finishing -> 3.54.0."""
import os, sys

VER = "3.54.0"
DATE = "2026-06-27"
PAY = "scratchpad/release-tag-guarded"
WF = ".github/workflows/release-tag.yml"

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

print("== release-tag guarded-manual installer ==")

# -- 1. remove the live auto-tag binding (the kit tags manually now)
print("-- remove the live auto-tag binding")
if os.path.exists(WF):
    os.remove(WF); print(f"  removed {WF}")
else: print(f"  [skip] {WF} already absent")

# -- 2. install the updated lock + opt-in reference + doc
print("-- install lock + opt-in reference + doc")
write("conformance/release-tag-wired.sh", payload("release-tag-wired.sh"), 0o755)
write("docs/operations/release-tag.github.yml", payload("release-tag.github.yml"))
write("docs/operations/release-tag.md", payload("release-tag.md"))

# -- 3. claim text (verifier path unchanged)
print("-- claims.tsv: claim text")
patch("conformance/claims.tsv",
      "auto-tag-on-merge: v<VERSION> is tagged on the merge commit coherently + idempotently on any "
      "forge (FLOOR scripts/release-tag.sh proven by --selftest; GitHub binding live, GitLab reference)",
      "release tagging: the coherence-guarded FLOOR scripts/release-tag.sh tags v<VERSION> idempotently "
      "+ coherently on any forge (proven by --selftest); the kit runs it manually after merge, "
      "auto-tag-on-merge ships as OPT-IN GitHub/GitLab references")

# -- 3b. ci.yml step label honesty (the kit no longer auto-tags; the FLOOR is run guarded-manual)
print("-- ci.yml: relabel the FLOOR selftest step")
patch(".github/workflows/ci.yml",
      "release-tag FLOOR self-test (auto-tag decision logic)",
      "release-tag FLOOR self-test (coherence-guarded tag decision)")

# -- 4. version finishing -> 3.54.0
print("-- version finishing -> %s" % VER)
write("VERSION", VER + "\n")
patch("README.md", "`v3.53.0`", "`v" + VER + "`")
entry = (f"## [{VER}] — {DATE}\n\n"
         "### Changed\n"
         "- **Release tagging: guarded-manual for the kit, opt-in for adopters** — corrects v3.53.0, "
         "which shipped the auto-tag binding LIVE in the kit's workflows, so an adopter's export "
         "received an active workflow that auto-creates release tags (an imposed release model). Now: "
         "the live binding is removed; the kit tags via the coherence-guarded FLOOR helper "
         "(`scripts/release-tag.sh`) run manually after merge — a mistimed run is a safe no-op and the "
         "tag always equals VERSION — keeping the human in the release decision. The auto-tag-on-merge "
         "binding ships as a copy-and-enable reference (`docs/operations/release-tag.github.yml` + the "
         "GitLab reference) for adopters who choose full automation — provided, not imposed. The FLOOR "
         "helper + coherence logic are unchanged.\n\n")
patch("CHANGELOG.md", "## [3.53.0] — 2026-06-27", entry + "## [3.53.0] — 2026-06-27")
patch("docs/ROADMAP-KIT.md", "**Last Updated:** 2026-06-27 (",
      "**Last Updated:** 2026-06-27 (**release-tag guarded-manual + opt-in SHIPPED — v3.54.0** "
      "[course-correction on v3.53.0: removed the live auto-tag binding (it imposed a release model on "
      "adopters); the kit now tags via the coherence-guarded FLOOR helper run manually after merge; "
      "auto-tag-on-merge ships as opt-in GitHub/GitLab references]. Prior: (")

print("\n== release-tag guarded-manual installer: DONE. ==")
