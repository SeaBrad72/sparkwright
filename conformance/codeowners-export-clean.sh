#!/bin/sh
# codeowners-export-clean.sh — the A2 archive lock (row CODEOWNERS-ROOT-EXPORT-LEAK): the adopter
# distribution must carry NO live CODEOWNERS rule naming a kit-maintainer identity.
#
# THE DEFECT THIS CLOSES. The kit's root CODEOWNERS was not export-ignored, so a real
# `git archive HEAD` shipped 7 active rules naming the maintainers' own handles into every adopter
# tree — where a forge that resolves root first (GitLab: root -> docs/ -> .gitlab/; GitHub bare
# export: root is the only file) would route or, with require_code_owner_reviews, BLOCK every merge
# on handles the adopter cannot use. The fix keeps ONE authoritative, export-ignored file
# (.github/CODEOWNERS); this lock makes reintroducing a shipped maintainer rule a red build.
#
# HOW IT DECIDES (derive, never hardcode). The maintainer-identity set is DERIVED from the live
# (non-commented) rules of the SOURCE tree's .github/CODEOWNERS — no handle is written into this
# file. It then archives HEAD of the tree under test into a mktemp dir (trap cleanup) and scans
# EVERY file named CODEOWNERS in the archive: a live rule naming a derived identity FAILs; an
# archive whose CODEOWNERS files are inert (commented) or name only non-maintainer placeholders
# (e.g. @your-org/*) PASSes; no CODEOWNERS at all PASSes.
#
# THREE-STATE. A tree that is not a git repository, or a repository with no commit yet (unborn
# HEAD — exactly a freshly incepted adopter: incept git-inits but does not commit), has no
# `git archive HEAD` output to assert against -> N/A with the reason, exit 0.
#
# HONEST CEILING. Proves the ARCHIVE is clean — not any forge's CODEOWNERS precedence (that is the
# forges' documented contract, not testable from this repo). The lock is exactly as strong as the
# declared identity source: a tree whose .github/CODEOWNERS is inert or absent yields an empty
# identity set and an OK-with-note (nothing declared, nothing to leak) — in the kit's own repo the
# source is live, so the lock binds. Identity matching is containment-with-right-boundary
# (fail-closed: over-detects a decorated handle rather than under-detecting a real one).
# Offline: `git archive` is local; no network.
# What it changes: nothing — read-only; archives HEAD into a temp dir and scans the extraction.
# Guardrails: read-only on the tree under test; all temp state under mktemp with trap cleanup; no
# network; the selftest builds throwaway repos under mktemp with SYNTHETIC identities only and
# never touches the real tree.
#
#   sh conformance/codeowners-export-clean.sh [tree-dir]   (default: .)
#   sh conformance/codeowners-export-clean.sh --selftest
# Exit: 0 = archive clean or N/A · 1 = a live maintainer rule ships (or the archive step failed —
# fail-closed) · 2 = usage. POSIX sh; dash-clean.
set -eu
cd "$(dirname "$0")/.." 2>/dev/null || true

NVT=''
cleanup() { [ -n "$NVT" ] && rm -rf "$NVT" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

# derive_identities <tree> : the live @handles declared by the SOURCE tree's .github/CODEOWNERS,
# one per line, sorted. Only non-comment lines contribute — an inert (fully commented) file, or a
# missing one, yields the empty set. This is the derive-never-hardcode seam: the check has no
# opinion about WHICH handles are maintainers beyond what the tree itself declares.
derive_identities() {
  _dc="$1/.github/CODEOWNERS"
  [ -f "$_dc" ] || return 0
  grep -v '^[[:space:]]*#' "$_dc" 2>/dev/null \
    | grep -oE '@[A-Za-z0-9][A-Za-z0-9-]*(/[A-Za-z0-9._-]+)?' \
    | sort -u || true
}

# check_tree <tree> : the load-bearing assertion. rc0 = the archive of HEAD carries no live
# CODEOWNERS rule naming a derived maintainer identity (or the tree is honestly N/A). rc1 = at
# least one such rule ships — the export leak, reintroduced. The _bad accumulator is what
# --selftest kills: neuter it and a leaked archive passes, which leg (ii) catches (KILLED).
check_tree() {
  _t=$1
  if ! git -C "$_t" rev-parse --git-dir >/dev/null 2>&1; then
    echo "N/A: $_t is not a git repository — no 'git archive HEAD' output to assert against (this lock asserts the real archive, not the worktree)"
    return 0
  fi
  if ! git -C "$_t" rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "N/A: $_t has no commit yet (unborn HEAD — e.g. a freshly incepted tree); 'git archive HEAD' has nothing to archive. Commit, then this lock gives a real verdict."
    return 0
  fi
  _ids=$(derive_identities "$_t")
  if [ -z "$_ids" ]; then
    echo "OK: codeowners-export-clean — $_t/.github/CODEOWNERS declares no live maintainer identity (absent or fully inert), so there is nothing to leak; archive not scanned (the lock is as strong as the declared identity source — see HONEST CEILING)"
    return 0
  fi
  _x=$(mktemp -d "$NVT/co-archive.XXXXXX") || { echo "FAIL: mktemp failed under $NVT" >&2; return 1; }
  # --worktree-attributes matches the shipping exporter (scripts/adopter-export.sh) exactly — a
  # plain archive reads only COMMITTED attributes, so a worktree-edited .gitattributes could ship a
  # file this lock never scanned (review I-1, demonstrated leak-while-green). Identical in CI.
  if ! git -C "$_t" archive --worktree-attributes --format=tar HEAD > "$_x/a.tar" 2>/dev/null; then
    echo "FAIL: 'git archive HEAD' failed in $_t — cannot prove the export is clean (fail-closed)" >&2
    return 1
  fi
  mkdir "$_x/tree"
  if ! tar -xf "$_x/a.tar" -C "$_x/tree" 2>/dev/null; then
    echo "FAIL: could not extract the archive of $_t — cannot prove the export is clean (fail-closed)" >&2
    return 1
  fi
  _bad=0
  _hits=''
  _files=$(cd "$_x/tree" && find . -name CODEOWNERS -type f | sort)
  while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    _rel=${_f#./}
    # live rules only: numbered lines whose first non-blank char is not '#'.
    _live=$(grep -n '^[[:space:]]*[^#[:space:]]' "$_x/tree/$_rel" 2>/dev/null || true)
    [ -n "$_live" ] || continue
    for _id in $_ids; do
      # right-boundary match: the identity must not merely be a prefix of a longer handle.
      _esc=$(printf '%s' "$_id" | sed 's/[.[\*^$()+?{|]/\\&/g')
      _m=$(printf '%s\n' "$_live" | grep -E "${_esc}"'([^A-Za-z0-9_-]|$)' || true)
      if [ -n "$_m" ]; then
        _bad=1
        _hits="${_hits}  $_rel — live rule naming $_id:
$(printf '%s\n' "$_m" | sed 's/^/      line /')
"
      fi
    done
  done <<EOF
$_files
EOF
  if [ "$_bad" != 0 ]; then
    echo "FAIL: the adopter archive ('git archive HEAD' of $_t) ships a LIVE CODEOWNERS rule naming a maintainer identity:" >&2
    printf '%s' "$_hits" >&2
    echo "  Identity set (derived from $_t/.github/CODEOWNERS, never hardcoded): $(printf '%s' "$_ids" | tr '\n' ' ')" >&2
    echo "  Fix: maintainer routing lives ONLY in .github/CODEOWNERS (export-ignored). No archived" >&2
    echo "  CODEOWNERS (root, docs/, .gitlab/, profiles/) may carry a live maintainer rule." >&2
    return 1
  fi
  echo "OK: codeowners-export-clean — the archive of $_t carries no live CODEOWNERS rule naming a derived maintainer identity ($(printf '%s' "$_ids" | tr '\n' ' ' | sed 's/ $//'))"
  return 0
}

# --- selftest (the NON-VACUITY oracle; everything at/after this marker is emitted verbatim by the
#     mutation harness). Builds throwaway repos under mktemp whose archives are (i) clean, (ii)
#     carrying a LIVE maintainer root rule — the load-bearing negative: exactly reintroduction of
#     the leak — (iii) carrying an inert root file, (iii-b) carrying a live NON-maintainer
#     placeholder rule, and asserts N/A on a non-repo dir and on an unborn-HEAD repo, plus the
#     empty-identity-source OK-with-note. Identities are SYNTHETIC (@KitMaintA/@KitMaintB) — never
#     real handles. ---
selftest() {
  st=0
  gq() { git -c user.email=t@kit -c user.name=t -c init.defaultBranch=main "$@" >/dev/null 2>&1; }

  # mkfx <mode> : throwaway repo under $NVT; echoes its path. Every mode declares the SAME live
  # identity source (.github/CODEOWNERS, export-ignored) and differs only in what the ARCHIVE ships.
  mkfx() {
    _m=$1
    _d=$(mktemp -d "$NVT/fx-$_m.XXXXXX") || return 1
    gq -C "$_d" init
    mkdir -p "$_d/.github"
    printf '# maintainer routing (export-ignored)\n*  @KitMaintA @KitMaintB\n' > "$_d/.github/CODEOWNERS"
    printf '.github/CODEOWNERS export-ignore\n' > "$_d/.gitattributes"
    printf 'readme\n' > "$_d/README.md"
    case "$_m" in
      clean)       : ;;
      liveroot)    printf '# leaked maintainer file\n*  @KitMaintA\n' > "$_d/CODEOWNERS" ;;
      inertroot)   printf '# CODEOWNERS (inert)\n# *  @KitMaintA\n#*  @KitMaintB\n' > "$_d/CODEOWNERS" ;;
      placeholder) printf '# adopter template\n*  @your-org/engineering\n' > "$_d/CODEOWNERS" ;;
    esac
    gq -C "$_d" add -A
    gq -C "$_d" commit -m base
    echo "$_d"
  }

  # (i) positive anchor — a clean tree must PASS with an OK verdict (not an N/A: a check that N/As
  # everything would sail through every other leg).
  _c=$(mkfx clean)
  set +e; _cout=$(check_tree "$_c" 2>&1); _crc=$?; set -e
  if [ "$_crc" = 0 ] && printf '%s' "$_cout" | grep -q '^OK:'; then
    echo "selftest PASS: clean tree -> OK (archive carries no maintainer rule)"
  else
    echo "selftest FAIL: clean tree wrongly rejected or not an OK verdict (rc=$_crc)"; st=1
  fi

  # (ii) THE LOAD-BEARING NEGATIVE — a live maintainer rule in the archived root CODEOWNERS is
  # exactly reintroduction of the leak. MUST fail.
  _l=$(mkfx liveroot)
  if check_tree "$_l" >/dev/null 2>&1; then
    echo "selftest FAIL: a LIVE maintainer rule in the archive was NOT caught (VACUOUS — the leak can return unseen)"; st=1
  else
    echo "selftest PASS: live maintainer root CODEOWNERS caught (reintroduction reds the build)"
  fi

  # (iii) inert/commented rules ship no live routing — MUST pass.
  _i=$(mkfx inertroot)
  if check_tree "$_i" >/dev/null 2>&1; then
    echo "selftest PASS: inert (commented) root CODEOWNERS accepted (presence is not a leak)"
  else
    echo "selftest FAIL: inert root CODEOWNERS wrongly rejected"; st=1
  fi

  # (iii-b) a live rule naming a NON-maintainer placeholder (the profile-template shape) — MUST
  # pass: the identity set is derived, so @your-org/* is not a leak.
  _p=$(mkfx placeholder)
  if check_tree "$_p" >/dev/null 2>&1; then
    echo "selftest PASS: live non-maintainer placeholder rule accepted (identity set is derived, not guessed)"
  else
    echo "selftest FAIL: placeholder rule wrongly treated as a maintainer leak"; st=1
  fi

  # (iv) not a git repository -> N/A with reason, rc 0.
  _n=$(mktemp -d "$NVT/fx-norepo.XXXXXX")
  set +e; _nout=$(check_tree "$_n" 2>&1); _nrc=$?; set -e
  if [ "$_nrc" = 0 ] && printf '%s' "$_nout" | grep -q '^N/A:'; then
    echo "selftest PASS: non-repo dir -> N/A (three-state honoured)"
  else
    echo "selftest FAIL: non-repo dir did not yield N/A (rc=$_nrc)"; st=1
  fi

  # (v) a repo with no commit (unborn HEAD — a freshly incepted adopter) -> N/A, rc 0. Without this
  # the verify.sh row would redden every incepted-but-uncommitted tree (the CP-5 class).
  _u=$(mktemp -d "$NVT/fx-unborn.XXXXXX")
  gq -C "$_u" init
  mkdir -p "$_u/.github"
  printf '*  @KitMaintA\n' > "$_u/.github/CODEOWNERS"
  set +e; _uout=$(check_tree "$_u" 2>&1); _urc=$?; set -e
  if [ "$_urc" = 0 ] && printf '%s' "$_uout" | grep -q '^N/A:'; then
    echo "selftest PASS: unborn-HEAD repo -> N/A (freshly incepted trees are not false-failed)"
  else
    echo "selftest FAIL: unborn-HEAD repo did not yield N/A (rc=$_urc)"; st=1
  fi

  # (vi) empty identity source (inert .github/CODEOWNERS) -> OK-with-note, and the note says so.
  # This documents the honest ceiling rather than hiding it.
  _e=$(mkfx clean)
  printf '# all inert\n# *  @KitMaintA\n' > "$_e/.github/CODEOWNERS"
  set +e; _eout=$(check_tree "$_e" 2>&1); _erc=$?; set -e
  if [ "$_erc" = 0 ] && printf '%s' "$_eout" | grep -q 'nothing to leak'; then
    echo "selftest PASS: empty identity source -> OK-with-note (ceiling stated, not hidden)"
  else
    echo "selftest FAIL: empty identity source not reported as OK-with-note (rc=$_erc)"; st=1
  fi

  if [ "$st" = 0 ]; then
    echo "OK: codeowners-export-clean selftest — clean/inert/placeholder archives pass, a live"
    echo "    maintainer rule in the archive reds, non-repo and unborn-HEAD trees are N/A"
    return 0
  fi
  echo "FAIL: codeowners-export-clean selftest"
  return 1
}

case "${1:-}" in
  --selftest) NVT=$(mktemp -d); selftest; exit $? ;;
  -*)         echo "usage: codeowners-export-clean.sh [tree-dir | --selftest]" >&2; exit 2 ;;
  *)          NVT=$(mktemp -d); check_tree "${1:-.}"; exit $? ;;
esac
