#!/bin/sh
# install-shellcheck.sh — install the kit's PINNED shellcheck, checksum-verified (SWAS-499).
# Why it exists: the runner image's shellcheck is 0.9.0, and on it conformance/agent-autonomy.sh peaks near 7 GB and OOM-killed the
# 7.9 GB CI runner three times. conformance/shellcheck.sh turns data-flow analysis off for three files on shellcheck >=0.10, so
# every CI job that lints runs this installer first and then `--check`. The version and BOTH checksums are literals HERE and nowhere
# else; there is no version argument and no environment variable. An adopter can run it the same way (it needs curl, tar, xz, sha256sum).
#   sh scripts/install-shellcheck.sh <dest-dir>   download the linux asset for `uname -m`, verify sha256, put shellcheck in <dest-dir>
#                                                 (CI then adds <dest-dir> to $GITHUB_PATH so it shadows the image's copy)
#   sh scripts/install-shellcheck.sh --check      the shellcheck FIRST on PATH must report exactly the pinned version
#   sh scripts/install-shellcheck.sh --selftest   network-free: a sed copy of this file whose fetch copies a local fixture
# Exit: 0 = installed / matches / selftest ok · 1 = refused (unsupported OS or architecture, a missing tool, download or checksum or
# version failure) · 2 = bad usage. POSIX sh; dash-clean.
# What it changes: writes one file, <dest-dir>/shellcheck (its temp dir is removed); --check and --selftest change nothing outside mktemp.
# Guardrails: the version and sha256 values are literals; the checksum is verified before extraction; an unsupported OS, an unknown architecture or a missing tool is refused by name; no env or argv picks the version.
set -eu

SC_VERSION=0.11.0
SC_SHA256_X86_64=8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198
SC_SHA256_AARCH64=12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588
SC_URL_BASE="https://github.com/koalaman/shellcheck/releases/download/v$SC_VERSION"

die() { echo "install-shellcheck: $1" >&2; exit 1; }

# need <tool> — a missing tool is a NAMED exit 1, never a silent skip (tar -J needs xz; the check needs sha256sum).
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required but was not found on PATH"; }

# have_pinned_version <binary> — 0 only when its --version output holds the exact line "version: <pinned>".
have_pinned_version() { "$1" --version 2>/dev/null | grep -Fqx "version: $SC_VERSION"; }

install_to() {  # <dest-dir>
  _dest=$1
  [ "$(uname -s)" = Linux ] || die "unsupported OS $(uname -s): only the Linux asset has a pinned checksum"
  case $(uname -m) in
    x86_64)
      _arch=x86_64; _sum=$SC_SHA256_X86_64 ;;
    aarch64)
      _arch=aarch64; _sum=$SC_SHA256_AARCH64 ;;
    *)
      die "unsupported architecture $(uname -m): only x86_64 and aarch64 have a pinned checksum" ;;
  esac
  need curl
  need tar
  need xz
  need sha256sum
  _tmp=$(mktemp -d); trap 'rm -rf "$_tmp"' EXIT
  _dl="$_tmp/shellcheck.tar.xz"
  curl -sSfL -o "$_dl" "$SC_URL_BASE/shellcheck-v$SC_VERSION.linux.$_arch.tar.xz" || die "download failed ($SC_URL_BASE)"
  printf '%s  %s\n' "$_sum" "$_dl" | sha256sum -c - >/dev/null 2>&1 || die "sha256 mismatch on the downloaded archive (wanted $_sum): refusing to install"
  tar -xJf "$_dl" -C "$_tmp" || die "cannot extract the archive"
  mkdir -p "$_dest"
  cp "$_tmp/shellcheck-v$SC_VERSION/shellcheck" "$_dest/shellcheck" || die "the archive holds no shellcheck-v$SC_VERSION/shellcheck"
  chmod 755 "$_dest/shellcheck"
  have_pinned_version "$_dest/shellcheck" || die "the installed $_dest/shellcheck does not report version $SC_VERSION"
  echo "install-shellcheck: installed shellcheck $SC_VERSION ($_arch) in $_dest"
}

check() {
  command -v shellcheck >/dev/null 2>&1 || die "no shellcheck on PATH"
  _ck=$(command -v shellcheck)
  have_pinned_version "$_ck" || die "the shellcheck first on PATH ($_ck) does not report version $SC_VERSION"
  echo "install-shellcheck: OK ($_ck is shellcheck $SC_VERSION)"
}

# --- --selftest: every cell runs a SED COPY of this file (no knob changes what the shipped script runs), and each has a mutant
# that must change its verdict. Every `return 1` is inside these functions.
_st_copy() {  # <dst> <sed-expr…> — a copy of this file with the edits; an edit that changed nothing fails the selftest
  _stc_dst=$1; shift
  : > "$_st_d/ed.sed"
  for _stc_e in "$@"; do printf '%s\n' "$_stc_e" >> "$_st_d/ed.sed"; done
  sed -f "$_st_d/ed.sed" "$_st_self" > "$_stc_dst"
  if cmp -s "$_st_self" "$_stc_dst"; then echo "selftest FAIL: the edits changed nothing: $*"; return 1; fi
}
_st_run() {  # <script> [args…] — sets _st_rc and _st_out; the stubs come first on PATH
  _str_s=$1; shift
  if _st_out=$(PATH="$_st_d/bin:$PATH" sh "$_str_s" "$@" 2>&1); then _st_rc=0; else _st_rc=$?; fi
}
_st_want() {  # <cell> <want-rc> <needle> — the last _st_run must have that rc and print that needle
  if [ "$_st_rc" != "$2" ]; then echo "selftest FAIL: $1 (rc $_st_rc, wanted $2): $_st_out"; return 1; fi
  case $_st_out in
    *"$3"*) return 0 ;;
  esac
  echo "selftest FAIL: $1 (output lacks '$3'): $_st_out"; return 1
}

_st_i5() {  # <script> — 0 only when a wrong-checksum run exited 1, said "sha256 mismatch" and the stub tar was never run (no sentinel)
  rm -f "$_st_d/sentinel"
  if _st_i5o=$(PATH="$_st_d/tbin:$_st_d/bin:$PATH" sh "$1" "$_st_d/dest5" 2>&1); then _st_i5rc=0; else _st_i5rc=$?; fi
  [ ! -e "$_st_d/sentinel" ] && [ "$_st_i5rc" = 1 ] && case $_st_i5o in *"sha256 mismatch"*) true ;; *) false ;; esac
}

selftest() {
  if ! { command -v xz && command -v sha256sum && command -v tar; } >/dev/null 2>&1; then
    echo "install-shellcheck --selftest: SKIP (xz, tar and sha256sum are needed to build the fixture archive)"; return 0
  fi
  _st_self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
  _st_d=$(mktemp -d); trap 'rm -rf "$_st_d"' EXIT
  mkdir -p "$_st_d/bin" "$_st_d/pkg/shellcheck-v$SC_VERSION"
  printf '#!/bin/sh\necho "version: %s"\n' "$SC_VERSION" > "$_st_d/pkg/shellcheck-v$SC_VERSION/shellcheck"
  chmod +x "$_st_d/pkg/shellcheck-v$SC_VERSION/shellcheck"
  tar -cJf "$_st_d/fix.tar.xz" -C "$_st_d/pkg" "shellcheck-v$SC_VERSION"
  _st_sum=$(sha256sum "$_st_d/fix.tar.xz" | cut -d' ' -f1)
  printf '#!/bin/sh\ncase "${1:-}" in -s) echo "${STUB_OS:-Linux}" ;; *) echo "${STUB_ARCH:-x86_64}" ;; esac\n' > "$_st_d/bin/uname"; chmod +x "$_st_d/bin/uname"
  # the fetch line becomes a copy of the local fixture; the x86_64 literal becomes the fixture's checksum (the POSITIVE copy)
  _st_fetch='s|^  curl -sSfL -o "$_dl" .*$|  cp '"$_st_d"'/fix.tar.xz "$_dl" \|\| die "download failed"|'
  _st_pos="s|^SC_SHA256_X86_64=.*\$|SC_SHA256_X86_64=$_st_sum|"
  _st_copy "$_st_d/pos.sh" "$_st_fetch" "$_st_pos" || return 1
  _st_run "$_st_d/pos.sh" "$_st_d/dest"
  _st_want "positive control: a fixture archive with its checksum installs" 0 "installed shellcheck $SC_VERSION" || return 1
  [ -x "$_st_d/dest/shellcheck" ] || { echo "selftest FAIL: the positive control installed no binary"; return 1; }
  # I1: a wrong checksum is refused (rc 1, named); the mutant drops the `sha256sum -c` line and must install anyway
  _st_copy "$_st_d/bad.sh" "$_st_fetch" || return 1
  _st_run "$_st_d/bad.sh" "$_st_d/dest1"
  _st_want "I1 a checksum mismatch is refused" 1 "sha256 mismatch" || return 1
  _st_copy "$_st_d/bad-m.sh" "$_st_fetch" '/sha256sum -c/d' || return 1
  _st_run "$_st_d/bad-m.sh" "$_st_d/dest1"
  if _st_want "I1 mutant" 1 "sha256 mismatch" >/dev/null 2>&1; then echo "selftest FAIL: I1 mutant survived (the checksum line is not load-bearing)"; return 1; fi
  # I2: an architecture with no pinned checksum is refused; the mutant makes x86_64 the default
  _st_a=$(PATH="$_st_d/bin:$PATH" STUB_ARCH=riscv64 sh "$_st_d/pos.sh" "$_st_d/dest2" 2>&1) && _st_arc=0 || _st_arc=$?
  if [ "$_st_arc" != 1 ]; then echo "selftest FAIL: I2 an unknown architecture was not refused with rc 1 (rc $_st_arc): $_st_a"; return 1; fi
  case $_st_a in
    *"unsupported architecture riscv64"*) ;;
    *) echo "selftest FAIL: I2 the refusal does not name the architecture: $_st_a"; return 1 ;;
  esac
  _st_copy "$_st_d/arch-m.sh" "$_st_fetch" "$_st_pos" 's|^      die "unsupported architecture.*$|      _arch=x86_64; _sum=$SC_SHA256_X86_64 ;;|' || return 1
  _st_a=$(PATH="$_st_d/bin:$PATH" STUB_ARCH=riscv64 sh "$_st_d/arch-m.sh" "$_st_d/dest2" 2>&1) && _st_arc=0 || _st_arc=$?
  if [ "$_st_arc" = 1 ]; then echo "selftest FAIL: I2 mutant survived (the architecture default is not load-bearing)"; return 1; fi
  # I3: --check against a shellcheck that reports 0.9.0 is refused, against the pinned version it passes; the mutant's compare is always true
  printf '#!/bin/sh\necho "version: 0.9.0"\n' > "$_st_d/bin/shellcheck"; chmod +x "$_st_d/bin/shellcheck"
  _st_run "$_st_self" --check
  _st_want "I3 --check refuses a 0.9.0 shellcheck" 1 "does not report version $SC_VERSION" || return 1
  _st_copy "$_st_d/chk-m.sh" 's|grep -Fqx "version: $SC_VERSION"|true|' || return 1
  _st_run "$_st_d/chk-m.sh" --check
  if _st_want "I3 mutant" 1 "does not report version" >/dev/null 2>&1; then echo "selftest FAIL: I3 mutant survived (the version compare is not load-bearing)"; return 1; fi
  printf '#!/bin/sh\necho "version: %s"\n' "$SC_VERSION" > "$_st_d/bin/shellcheck"
  _st_run "$_st_self" --check
  _st_want "I3 --check accepts the pinned version" 0 "is shellcheck $SC_VERSION" || return 1
  # I4: a missing tool is a NAMED exit 1 (the copy asks for a tool that cannot exist in its place); the mutant's `need` never refuses. One tool
  # proves the shared `need`; the four call sites are one line each.
  _st_copy "$_st_d/need.sh" "$_st_fetch" "$_st_pos" 's|^  need xz$|  need no-such-xz|' || return 1
  _st_run "$_st_d/need.sh" "$_st_d/dest4"
  _st_want "I4 a missing tool is a named refusal" 1 "no-such-xz is required" || return 1
  _st_copy "$_st_d/need-m.sh" "$_st_fetch" "$_st_pos" 's|^  need xz$|  need no-such-xz|' 's/^need() {.*$/need() { :; }/' || return 1
  _st_run "$_st_d/need-m.sh" "$_st_d/dest4"
  if _st_want "I4 mutant" 1 "no-such-xz is required" >/dev/null 2>&1; then echo "selftest FAIL: I4 mutant survived (need is not load-bearing)"; return 1; fi
  # I5: a wrong checksum is refused BEFORE anything is extracted. A stub `tar` on PATH writes a sentinel; the shipped copy must leave none.
  # The swapped copy moves the extract ahead of the verify and must be caught (the cell has teeth).
  mkdir -p "$_st_d/tbin"
  printf '#!/bin/sh\n: > "%s/sentinel"\nexit 0\n' "$_st_d" > "$_st_d/tbin/tar"; chmod +x "$_st_d/tbin/tar"
  _st_copy "$_st_d/swap.sh" "$_st_fetch" 's|^\(  printf .*sha256sum -c.*\)$|  tar -xJf "$_dl" -C "$_tmp" \|\| die "cannot extract the archive"; \1|' || return 1
  _st_i5 "$_st_d/bad.sh" || { echo "selftest FAIL: I5 a wrong checksum extracted before it was refused (sentinel, rc or message wrong)"; return 1; }
  if _st_i5 "$_st_d/swap.sh"; then echo "selftest FAIL: I5 mutant survived (an extract-before-verify swap was not caught)"; return 1; fi
  # I6: a non-Linux OS is refused by name (the asset and both checksums are Linux); the mutant drops the check and installs on Darwin
  _st_a=$(PATH="$_st_d/bin:$PATH" STUB_OS=Darwin sh "$_st_d/pos.sh" "$_st_d/dest6" 2>&1) && _st_arc=0 || _st_arc=$?
  if [ "$_st_arc" != 1 ]; then echo "selftest FAIL: I6 a non-Linux OS was not refused with rc 1 (rc $_st_arc): $_st_a"; return 1; fi
  case $_st_a in
    *"unsupported OS Darwin"*) ;;
    *) echo "selftest FAIL: I6 the refusal does not name the OS: $_st_a"; return 1 ;;
  esac
  _st_copy "$_st_d/os-m.sh" "$_st_fetch" "$_st_pos" '/unsupported OS/d' || return 1
  _st_a=$(PATH="$_st_d/bin:$PATH" STUB_OS=Darwin sh "$_st_d/os-m.sh" "$_st_d/dest6" 2>&1) && _st_arc=0 || _st_arc=$?
  if [ "$_st_arc" = 1 ]; then echo "selftest FAIL: I6 mutant survived (the OS check is not load-bearing)"; return 1; fi
  echo "install-shellcheck --selftest: OK (checksum-before-extract, architecture, OS, --check and the tool pre-check each have a mutant that goes red)"
  return 0
}

case "${1:-}" in
  --selftest) [ "$#" -eq 1 ] || { echo "usage: install-shellcheck.sh <dest-dir> | --check | --selftest" >&2; exit 2; }
              selftest; exit $? ;;
  --check)    [ "$#" -eq 1 ] || { echo "usage: install-shellcheck.sh <dest-dir> | --check | --selftest" >&2; exit 2; }
              check; exit $? ;;
  ""|-*)      echo "usage: install-shellcheck.sh <dest-dir> | --check | --selftest" >&2; exit 2 ;;
  *)          [ "$#" -eq 1 ] || { echo "usage: install-shellcheck.sh <dest-dir> | --check | --selftest" >&2; exit 2; }
              install_to "$1"; exit $? ;;
esac
