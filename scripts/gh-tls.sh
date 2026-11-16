#!/bin/sh
# gh-tls.sh - one sourced function, kit_gh_tls_pin (SWAS-903; design docs/architecture/2026-11-15-sandbox-github-lockout-903-design.md).
#
# THE PROBLEM. Inside the shipped macOS agent sandbox the system trust service is unreachable, so every `gh` call fails with
# `tls: failed to verify certificate: x509: OSStatus -26276` and the kit's own verbs (record, actuate, land, trace, evidence, the lease's CI proof) cannot reach GitHub.
#
# WHAT THIS DOES. Each gh-calling verb sources this file and calls kit_gh_tls_pin once, in the PARENT shell, before its first gh call. The function makes one
# `gh api rate_limit` call and reads its stderr. ONLY on that exact x509 + OSStatus -26276 signature, and ONLY if the root-owned system CA bundle passes the checks below,
# it exports SSL_CERT_FILE=<that bundle>, so every subshell, `eval` and child script of the verb inherits it. It runs only on Darwin, and never when SSL_CERT_FILE or
# SSL_CERT_DIR already holds a NON-EMPTY value (a value a person chose is never overwritten; an empty one is read as unset). It always returns 0 (safe under the caller's
# `set -eu`). It adds nothing to the guard: no prefix is admitted anywhere; the kit's verb sets its own trust store.
#
# THE PIN CHECKS. The leaf is a regular file (never a symlink) owned by uid 0 whose mode string neither ends in `+` (an ACL) nor grants group or world write; each parent
# (/private/etc/ssl, /private/etc, /private) is a real directory (never a symlink) with the same owner and mode rules. `ls` and `awk` are called by absolute path
# (/bin/ls, /usr/bin/awk) and so is `uname`; no variable, flag or environment value changes the path, the uid or those tools (the selftest edits a COPY).
#
# THE HONEST CEILING. The exported value reaches every child of the verb, git and curl included; that is no wider than what `gh` itself reaches today. A client that
# honours the variable reads that one file only, so for that process tree a root that lives only in the keychain, and a keychain distrust setting, are not seen.
#
# POSIX sh, dash-clean, no `local`. Sourcing loads ONLY the pin functions below; the selftest is defined after the direct-run test and never loads when sourced.
# Run `sh scripts/gh-tls.sh --selftest`.
#
# What it changes: exports SSL_CERT_FILE=/private/etc/ssl/cert.pem in the CALLER's shell (so its subshells and children inherit it), only on the macOS sandbox's x509 OSStatus -26276
# signature; it writes no file and changes no other variable. A direct `--selftest` run writes only a mktemp fixture directory, which it removes.
# Guardrails: Darwin only; an already non-empty SSL_CERT_FILE or SSL_CERT_DIR is never overwritten; one probe call per use; the bundle must pass the root-owned pin checks
# (a regular file, never a symlink, owner uid 0, no ACL, no group or world write, real root-owned parent directories) or nothing is exported; it always returns 0.

_GHT_PIN=/private/etc/ssl/cert.pem   # GHTLS-PIN
_GHT_UID=0   # GHTLS-UID
_GHT_PARENTS='/private/etc/ssl /private/etc /private'   # GHTLS-PARENTS
_GHT_UNAME=/usr/bin/uname   # GHTLS-UNAME
_GHT_LS=/bin/ls   # GHTLS-LS

# _ght_owner <path> / _ght_mode <path>: the numeric owner and the mode string of what the path resolves to.
_ght_owner() { "$_GHT_LS" -ldnL "$1" 2>/dev/null | LC_ALL=C /usr/bin/awk '{ print $3 }'; }
_ght_mode() { "$_GHT_LS" -ldL "$1" 2>/dev/null | LC_ALL=C /usr/bin/awk '{ print $1 }'; }

# _ght_modeok <path> <type: - for a file, d for a directory>: rc 0 when the mode string is that type, has no ACL mark and no group or world write; else rc 1 with
# _GHT_WHYK set to acl or mode.
_ght_modeok() {
  _ght_m=$(_ght_mode "$1")
  case "$_ght_m" in
    *+) _GHT_WHYK=acl; return 1 ;;   # GHTLS-ACL
  esac
  # macOS prints a file's ACL entries as indented lines after the first (`ls -lde`); any such line refuses the pin. An `@` (an extended attribute) is NOT refused.
  _ght_e=$("$_GHT_LS" -lde "$1" 2>/dev/null | LC_ALL=C /usr/bin/awk 'NR > 1 { n++ } END { print n + 0 }')
  [ "$_ght_e" = 0 ] || { _GHT_WHYK=acl; return 1; }   # GHTLS-ACLE
  case "$_ght_m" in
    "$2"????[!w]??[!w]*) return 0 ;;   # GHTLS-MODE
    *) _GHT_WHYK=mode; return 1 ;;
  esac
}

# _ght_pin_ok: rc 0 when the pin passes every check; else rc 1 with _GHT_WHY naming the first check that failed.
_ght_pin_ok() {
  _GHT_WHY=''
  if [ -L "$_GHT_PIN" ]; then _GHT_WHY=leaf-symlink; return 1; fi   # GHTLS-NOLINK
  [ -f "$_GHT_PIN" ] || { _GHT_WHY=leaf-not-regular; return 1; }
  [ "$(_ght_owner "$_GHT_PIN")" = "$_GHT_UID" ] || { _GHT_WHY=leaf-owner; return 1; }   # GHTLS-OWN
  _ght_modeok "$_GHT_PIN" - || { _GHT_WHY=leaf-$_GHT_WHYK; return 1; }
  for _ght_d in $_GHT_PARENTS; do
    if [ ! -d "$_ght_d" ]; then _GHT_WHY=parent-$_ght_d-not-dir; return 1; fi
    if [ -L "$_ght_d" ]; then _GHT_WHY=parent-$_ght_d-not-dir; return 1; fi   # GHTLS-PARENT-LINK
    [ "$(_ght_owner "$_ght_d")" = "$_GHT_UID" ] || { _GHT_WHY=parent-$_ght_d-owner; return 1; }   # GHTLS-PARENT-OWN
    _ght_modeok "$_ght_d" d || { _GHT_WHY=parent-$_ght_d-$_GHT_WHYK; return 1; }
  done
  return 0
}

kit_gh_tls_pin() {
  [ -z "${SSL_CERT_FILE-}" ] && [ -z "${SSL_CERT_DIR-}" ] || return 0   # GHTLS-INHERIT
  case "$("$_GHT_UNAME" -s 2>/dev/null || :)" in
    Darwin) : ;;   # GHTLS-DARWIN
    *) return 0 ;;
  esac
  command -v gh >/dev/null 2>&1 || return 0
  _ght_rc=0
  _ght_err=$(gh api rate_limit --jq .rate.limit 2>&1 >/dev/null) || _ght_rc=$?   # GHTLS-CAPTURE
  [ "$_ght_rc" -ne 0 ] || return 0
  case "$_ght_err" in
    *'x509:'*'OSStatus -26276'*) : ;;   # GHTLS-SIG
    *) return 0 ;;
  esac
  if _ght_pin_ok; then
    SSL_CERT_FILE=$_GHT_PIN; export SSL_CERT_FILE   # GHTLS-EXPORT
    printf '%s\n' 'gh: the macOS sandbox blocks the system trust service; using the system CA bundle for this run' >&2 || :
    return 0
  fi
  printf '%s\n' "gh: the macOS sandbox blocks the system trust service; the system CA bundle failed the $_GHT_WHY check, so nothing was pinned" >&2 || :
  return 0
}

# ---- everything below loads ONLY on a direct run (`sh scripts/gh-tls.sh --selftest`); a sourcing caller stops here ----------------------------------------------
case "${0##*/}" in
  gh-tls.sh) : ;;   # GHTLS-DIRECT
  *) return 0 2>/dev/null || exit 0 ;;
esac

# GHT_T is a fixture directory. A fake `gh` logs "<argv>|SSL_CERT_FILE=<value>" and fails with the x509 text unless SSL_CERT_FILE is set; the library copy's _GHT_UNAME
# points at a fake `uname` that prints $GHT_T/os, and (for the ACL cells) _GHT_LS at a fake `ls` that adds a `+` to the mode of the path named in $GHT_T/aclpath.
# Every cell runs the library COPY in a child script named drv.sh, so no cell ever sources it under the name gh-tls.sh.
ght_ok() { echo "PASS: $1"; GHT_N=$((GHT_N + 1)); }
ght_no() { echo "FAIL: $1"; GHT_N=$((GHT_N + 1)); GHT_FAIL=1; }

ght_setup() {
  mkdir -p "$GHT_T/bin" "$GHT_T/pin" "$GHT_T/gwp" || return 1
  printf '%s\n' '#!/bin/sh' 'd=$(dirname "$0")/..' 'printf "%s|SSL_CERT_FILE=%s\n" "$*" "${SSL_CERT_FILE-}" >> "$d/gh.log"' \
    'if [ -n "${SSL_CERT_FILE-}" ]; then exit 0; fi' \
    'if [ "$(cat "$d/mode")" = 404 ]; then echo "HTTP 404" >&2; exit 1; fi' \
    'echo "tls: failed to verify certificate: x509: OSStatus -26276" >&2' 'exit 1' > "$GHT_T/bin/gh"
  printf '%s\n' '#!/bin/sh' 'cat "$(dirname "$0")/../os"' > "$GHT_T/bin/uname"
  # the fake ls: for the path in aclpath the mode string gets a `+`; for the path in entpath the mode string gets an `@` and `ls -lde` prints one ACL entry line after it
  printf '%s\n' '#!/bin/sh' 'd=$(dirname "$0")/..' 'for a in "$@"; do last=$a; done' \
    'if [ "$1" = -lde ]; then if [ "$last" = "$(cat "$d/entpath" 2>/dev/null)" ]; then echo "-rw-r--r--@ 1 0 0 1 Jan 1 00:00 x"; echo " 0: user:fixture allow read"; fi; exit 0; fi' \
    'out=$(/bin/ls "$@")' \
    'if [ "$last" = "$(cat "$d/aclpath" 2>/dev/null)" ]; then printf "%s\n" "$out" | sed "s/^\([^ ]*\)/\1+/"; elif [ "$last" = "$(cat "$d/entpath" 2>/dev/null)" ]; then printf "%s\n" "$out" | sed "s/^\([^ ]*\)/\1@/"; else printf "%s\n" "$out"; fi' > "$GHT_T/bin/ls"
  printf '%s\n' '. "$1"' 'if [ "${2-}" = redirect ]; then kit_gh_tls_pin 2>/dev/null; else kit_gh_tls_pin; fi' \
    'printf "SELF:%s\n" "${SSL_CERT_FILE-unset}"' 'sh "$(dirname "$0")/child.sh"' 'x=$(gh sub)' 'eval "gh evl"' > "$GHT_T/drv.sh"
  printf '%s\n' 'printf "CHILD:%s\n" "${SSL_CERT_FILE-unset}"' 'gh chd' > "$GHT_T/child.sh"
  printf '%s\n' '. "$1"' 'if command -v _ght_main > /dev/null 2>&1 || command -v ght_setup > /dev/null 2>&1; then echo LEAKED; else echo SOURCED; fi' > "$GHT_T/src.sh"
  chmod 755 "$GHT_T/bin/gh" "$GHT_T/bin/uname" "$GHT_T/bin/ls" || return 1
  : > "$GHT_T/aclpath"; : > "$GHT_T/entpath"
  printf 'fixture ca bundle\n' > "$GHT_T/pin/cert.pem"; printf 'fixture ca bundle\n' > "$GHT_T/pin/gw.pem"; printf 'fixture ca bundle\n' > "$GHT_T/pin/ww.pem"
  printf 'fixture ca bundle\n' > "$GHT_T/gwp/cert.pem"
  chmod 644 "$GHT_T/pin/cert.pem" "$GHT_T/gwp/cert.pem"; chmod 664 "$GHT_T/pin/gw.pem"; chmod 646 "$GHT_T/pin/ww.pem"
  ln -s cert.pem "$GHT_T/pin/ln.pem" || return 1
  ln -s pin "$GHT_T/lnk" || return 1
  chmod 755 "$GHT_T" "$GHT_T/pin"; chmod 775 "$GHT_T/gwp"
  printf 'tls\n' > "$GHT_T/mode"
}

# ght_lib <out> [pin] [uid] [parents] [extra sed]: a COPY of this file with the constants pointed at the fixture, plus an optional mutation. The edits go through a sed
# script file; $GHT_LSSED (when set) is one more edit, used by the ACL cells to put the fake ls in place.
ght_lib() {
  _gl_pin=${2:-$GHT_T/pin/cert.pem}; _gl_uid=${3:-$(id -u)}; _gl_par=${4:-$GHT_T/pin $GHT_T}
  printf '%s\n' "s|^_GHT_PIN=.*# GHTLS-PIN\$|_GHT_PIN=$_gl_pin   # GHTLS-PIN|" "s|^_GHT_UID=.*# GHTLS-UID\$|_GHT_UID=$_gl_uid   # GHTLS-UID|" \
    "s|^_GHT_PARENTS=.*# GHTLS-PARENTS\$|_GHT_PARENTS='$_gl_par'   # GHTLS-PARENTS|" \
    "s|^_GHT_UNAME=.*# GHTLS-UNAME\$|_GHT_UNAME=$GHT_T/bin/uname   # GHTLS-UNAME|" > "$GHT_T/ed.sed"
  if [ -n "${GHT_LSSED-}" ]; then printf '%s\n' "$GHT_LSSED" >> "$GHT_T/ed.sed"; fi
  if [ -n "${5-}" ]; then printf '%s\n' "$5" >> "$GHT_T/ed.sed"; fi
  sed -f "$GHT_T/ed.sed" "$GHT_SELF" > "$1"
}

# ght_run <lib> <os> <mode> <none|file|file2|dir> <how>: drv.sh in a child, with the inherited trust variables as named.
ght_run() {
  printf '%s\n' "$2" > "$GHT_T/os"; printf '%s\n' "$3" > "$GHT_T/mode"; : > "$GHT_T/gh.log"
  case "$4" in
    none) env -u SSL_CERT_FILE -u SSL_CERT_DIR PATH="$GHT_T/bin:$PATH" sh "$GHT_T/drv.sh" "$1" "$5" > "$GHT_T/out" 2> "$GHT_T/err" || : ;;
    file) env -u SSL_CERT_DIR SSL_CERT_FILE=/fixture/user.pem PATH="$GHT_T/bin:$PATH" sh "$GHT_T/drv.sh" "$1" "$5" > "$GHT_T/out" 2> "$GHT_T/err" || : ;;
    file2) env -u SSL_CERT_DIR SSL_CERT_FILE=/etc/ssl/cert.pem PATH="$GHT_T/bin:$PATH" sh "$GHT_T/drv.sh" "$1" "$5" > "$GHT_T/out" 2> "$GHT_T/err" || : ;;
    dir) env -u SSL_CERT_FILE SSL_CERT_DIR=/fixture/certs PATH="$GHT_T/bin:$PATH" sh "$GHT_T/drv.sh" "$1" "$5" > "$GHT_T/out" 2> "$GHT_T/err" || : ;;
  esac
}
ght_in() { grep -qF -- "$2" "$1"; }   # <file> <fixed string>
ght_probes() { grep -c 'rate_limit' "$GHT_T/gh.log" || :; }

# The cells. Each takes the library COPY to judge and returns 0 when the cell's expectation holds.
ghc_T1() { ght_run "$1" Darwin tls none direct; [ "$(ght_probes)" = 1 ] && ght_in "$GHT_T/out" "SELF:$GHT_T/pin/cert.pem" && ght_in "$GHT_T/out" "CHILD:$GHT_T/pin/cert.pem" && ght_in "$GHT_T/err" 'using the system CA bundle for this run'; }
ghc_T2() { ght_run "$1" Darwin tls none direct; [ "$(ght_probes)" = 1 ] && ght_in "$GHT_T/gh.log" "sub|SSL_CERT_FILE=$GHT_T/pin/cert.pem" && ght_in "$GHT_T/gh.log" "evl|SSL_CERT_FILE=$GHT_T/pin/cert.pem" && ght_in "$GHT_T/gh.log" "chd|SSL_CERT_FILE=$GHT_T/pin/cert.pem"; }
ghc_T3() { ght_run "$1" Darwin 404 none direct; ght_in "$GHT_T/out" 'SELF:unset' && ght_in "$GHT_T/out" 'CHILD:unset'; }
ghc_T4b() { ght_run "$1" Linux tls none direct; [ "$(ght_probes)" = 0 ] && ght_in "$GHT_T/out" 'SELF:unset'; }
ghc_T5() { ght_run "$1" Darwin tls file direct; [ "$(ght_probes)" = 0 ] && ght_in "$GHT_T/out" 'SELF:/fixture/user.pem'; }
ghc_T5b() { ght_run "$1" Darwin tls file2 direct; [ "$(ght_probes)" = 0 ] && ght_in "$GHT_T/out" 'SELF:/etc/ssl/cert.pem'; }
ghc_T6() { ght_run "$1" Darwin tls dir direct; [ "$(ght_probes)" = 0 ] && ght_in "$GHT_T/out" 'SELF:unset'; }
ghc_T7() { ght_run "$1" Darwin tls none direct; ght_in "$GHT_T/out" 'SELF:unset' && ght_in "$GHT_T/err" "$2"; }   # <lib> <named check>
ghc_T9() { ght_run "$1" Darwin tls none redirect; ght_in "$GHT_T/out" "SELF:$GHT_T/pin/cert.pem" && [ "$(ght_probes)" = 1 ]; }
# GH-W1 / GH-W2 (wiring): a COPY of promotion-verify.sh beside a fixture copy of this library, run with the fake gh and uname. W1 (a non-repository directory): the FIRST gh
# call is the probe. W2 (a repository with a fake checkout-lease.sh that logs the pin it sees): the probe comes FIRST and the lease gate, run next as a child, SEES the pin.
# <$1> is a sed expression applied to the copy ('' = none).
ghc_W1() {
  mkdir -p "$GHT_T/wire"; ght_lib "$GHT_T/wire/gh-tls.sh"
  _gw_pv=$(dirname "$GHT_SELF")/promotion-verify.sh
  if [ -n "$1" ]; then sed -e "$1" "$_gw_pv" > "$GHT_T/wire/promotion-verify.sh"; else cp "$_gw_pv" "$GHT_T/wire/promotion-verify.sh"; fi
  : > "$GHT_T/gh.log"; printf 'Darwin\n' > "$GHT_T/os"; printf 'tls\n' > "$GHT_T/mode"
  ( cd "$GHT_T/wire" && env -u SSL_CERT_FILE -u SSL_CERT_DIR PATH="$GHT_T/bin:$PATH" sh "$GHT_T/wire/promotion-verify.sh" record < /dev/null > "$GHT_T/out" 2> "$GHT_T/err" ) || :
  [ "$(sed -n 1p "$GHT_T/gh.log")" = 'api rate_limit --jq .rate.limit|SSL_CERT_FILE=' ]
}
ghc_W2() {
  mkdir -p "$GHT_T/wire2"; [ -d "$GHT_T/wire2/.git" ] || git init -q "$GHT_T/wire2" > /dev/null 2>&1 || return 1
  ght_lib "$GHT_T/wire2/gh-tls.sh"
  _gw_pv=$(dirname "$GHT_SELF")/promotion-verify.sh
  if [ -n "$1" ]; then sed -e "$1" "$_gw_pv" > "$GHT_T/wire2/promotion-verify.sh"; else cp "$_gw_pv" "$GHT_T/wire2/promotion-verify.sh"; fi
  printf '%s\n' '#!/bin/sh' 'printf "LEASE-GATE|SSL_CERT_FILE=%s\n" "${SSL_CERT_FILE-}" >> "$(dirname "$0")/../gh.log"' 'exit 0' > "$GHT_T/wire2/checkout-lease.sh"
  : > "$GHT_T/gh.log"; printf 'Darwin\n' > "$GHT_T/os"; printf 'tls\n' > "$GHT_T/mode"
  ( cd "$GHT_T/wire2" && env -u SSL_CERT_FILE -u SSL_CERT_DIR -u GIT_DIR PATH="$GHT_T/bin:$PATH" sh "$GHT_T/wire2/promotion-verify.sh" record < /dev/null > "$GHT_T/out" 2> "$GHT_T/err" ) || :
  [ "$(sed -n 1p "$GHT_T/gh.log")" = 'api rate_limit --jq .rate.limit|SSL_CERT_FILE=' ] && [ "$(sed -n 2p "$GHT_T/gh.log")" = "LEASE-GATE|SSL_CERT_FILE=$GHT_T/pin/cert.pem" ]
}
ghc_S1() { : > "$GHT_T/gh.log"; _gs_o=$(env PATH="$GHT_T/bin:$PATH" sh "$GHT_T/src.sh" "$1" 2>/dev/null) || _gs_o=died; [ "$_gs_o" = SOURCED ] && [ ! -s "$GHT_T/gh.log" ]; }

# ght_cell <label> <cell fn> [args]: the cell on the good copy. ght_cellp <label> <fn> <pin> <uid> <parents> [args]: the same with the fixture's pin, uid and parents.
# ght_mutp <label> <sed> <pin> <uid> <parents> <fn> [args], ght_mut <label> <sed> <fn> [args]: the same cell on a copy mutated by <sed> must FAIL (the sed must apply, the
# copy must parse).
ght_cell() { _gc_l=$1; _gc_f=$2; shift 2; ght_lib "$GHT_T/good.sh"; if "$_gc_f" "$GHT_T/good.sh" "$@"; then ght_ok "$_gc_l"; else ght_no "$_gc_l"; fi; }
ght_cellp() { _gc_l=$1; _gc_f=$2; _gc_pin=$3; _gc_uid=$4; _gc_par=$5; shift 5; ght_lib "$GHT_T/good.sh" "$_gc_pin" "$_gc_uid" "$_gc_par"; if "$_gc_f" "$GHT_T/good.sh" "$@"; then ght_ok "$_gc_l"; else ght_no "$_gc_l"; fi; }
ght_mutp() {
  _gm_l=$1; _gm_s=$2; _gm_pin=$3; _gm_uid=$4; _gm_par=$5; _gm_f=$6; shift 6
  ght_lib "$GHT_T/good.sh" "$_gm_pin" "$_gm_uid" "$_gm_par"; ght_lib "$GHT_T/mut.sh" "$_gm_pin" "$_gm_uid" "$_gm_par" "$_gm_s"
  if cmp -s "$GHT_T/good.sh" "$GHT_T/mut.sh"; then ght_no "$_gm_l (the mutation matched nothing; the leg is unbound)"; return 0; fi
  if ! sh -n "$GHT_T/mut.sh" 2>/dev/null; then ght_no "$_gm_l (the mutant does not parse)"; return 0; fi
  if "$_gm_f" "$GHT_T/mut.sh" "$@"; then ght_no "$_gm_l (the mutant still passes the cell)"; else ght_ok "$_gm_l"; fi
}
ght_mut() { _gm2_l=$1; _gm2_s=$2; shift 2; ght_mutp "$_gm2_l" "$_gm2_s" "$GHT_T/pin/cert.pem" "$(id -u)" "$GHT_T/pin $GHT_T" "$@"; }
# ght_wmut <label> <wiring cell fn> <sed>: the wiring cell on a promotion-verify.sh copy mutated by <sed> must FAIL (the sed must apply).
ght_wmut() {
  _gw_pv2=$(dirname "$GHT_SELF")/promotion-verify.sh
  sed -e "$3" "$_gw_pv2" > "$GHT_T/pvm.sh"
  if cmp -s "$_gw_pv2" "$GHT_T/pvm.sh"; then ght_no "$1: the mutation matched nothing; the leg is unbound"
  elif ! sh -n "$GHT_T/pvm.sh" 2>/dev/null; then ght_no "$1: the mutant copy does not parse"
  elif "$2" "$3"; then ght_no "$1: the cell still passes"
  else ght_ok "$1"; fi
}

ght_acl() {   # <label> <acl path> <named check> <pin> <parents> <marker file: aclpath|entpath> <anchor of the arm the mutant deletes>: the ACL cell and its mutant
  printf '%s\n' "$2" > "$GHT_T/$6"
  GHT_LSSED="s|^_GHT_LS=.*# GHTLS-LS\$|_GHT_LS=$GHT_T/bin/ls   # GHTLS-LS|"
  ght_cellp "$1: refused, the check is named" ghc_T7 "$4" "$(id -u)" "$5" "$3"
  ght_mutp "$1 mutant: the $7 test deleted -> exported" "/# $7\$/d" "$4" "$(id -u)" "$5" ghc_T7 "$3"
  GHT_LSSED=''; : > "$GHT_T/aclpath"; : > "$GHT_T/entpath"
}

_ght_selftest() {
  GHT_SELF=$1; GHT_N=0; GHT_FAIL=0; GHT_LSSED=''
  GHT_T=$(mktemp -d "${TMPDIR:-/tmp}/ght-st.XXXXXX") || { echo "FAIL: gh-tls: mktemp failed"; return 1; }
  trap 'rm -rf "$GHT_T"' EXIT
  trap 'exit 130' INT TERM
  ght_setup || { echo "FAIL: gh-tls: the fixture could not be built"; return 1; }
  _gt_uid=$(id -u)
  ght_cell "GH-T1 the signature pins once: one probe, the variable exported, one note" ghc_T1
  ght_mut "GH-T1 mutant: the export deleted -> the child sees it unset" '/# GHTLS-EXPORT$/d' ghc_T1
  ght_cell "GH-T2 a subshell, an eval and a child script all inherit the pin" ghc_T2
  ght_mut "GH-T2 mutant: a gh() function wrapper instead of an export -> the child script sees it unset" \
    's|^.*# GHTLS-EXPORT$|    gh() { SSL_CERT_FILE=$_GHT_PIN command gh "$@"; }   # GHTLS-EXPORT|' ghc_T2
  ght_cell "GH-T3 another error (HTTP 404) pins nothing" ghc_T3
  ght_mut "GH-T3 mutant: every failure read as the signature -> exported" 's|^    \*.x509:.\*.OSStatus -26276.\*) : ;;   # GHTLS-SIG$|    *) : ;;   # GHTLS-SIG|' ghc_T3
  ght_cell "GH-T4 Linux: no probe at all" ghc_T4b
  ght_mut "GH-T4 mutant: the Darwin test deleted -> the probe line appears" 's|^    Darwin) : ;;   # GHTLS-DARWIN$|    *) : ;;   # GHTLS-DARWIN|' ghc_T4b
  ght_cell "GH-T5 an inherited SSL_CERT_FILE: no probe, the value unchanged" ghc_T5
  ght_mut "GH-T5 mutant: the SSL_CERT_FILE test deleted -> a probe happens" '/# GHTLS-INHERIT$/s|\[ -z "${SSL_CERT_FILE-}" \] && ||' ghc_T5
  ght_cell "GH-T5b run A's own path /etc/ssl/cert.pem inherited: no probe, the value byte-identical" ghc_T5b
  ght_mut "GH-T5b mutant: the SSL_CERT_FILE test deleted -> a probe happens" '/# GHTLS-INHERIT$/s|\[ -z "${SSL_CERT_FILE-}" \] && ||' ghc_T5b
  ght_cell "GH-T6 SSL_CERT_DIR set: no probe, nothing exported" ghc_T6
  ght_mut "GH-T6 mutant: the SSL_CERT_DIR test deleted -> exported" '/# GHTLS-INHERIT$/s| && \[ -z "${SSL_CERT_DIR-}" \]||' ghc_T6
  ght_cellp "GH-T7a a symlink leaf: nothing exported, the check is named" ghc_T7 "$GHT_T/pin/ln.pem" "$_gt_uid" "$GHT_T/pin $GHT_T" leaf-symlink
  ght_mutp "GH-T7a mutant: the no-symlink test deleted -> exported" '/# GHTLS-NOLINK$/d' "$GHT_T/pin/ln.pem" "$_gt_uid" "$GHT_T/pin $GHT_T" ghc_T7 leaf-symlink
  ght_cellp "GH-T7b a group-writable leaf: nothing exported, the check is named" ghc_T7 "$GHT_T/pin/gw.pem" "$_gt_uid" "$GHT_T/pin $GHT_T" leaf-mode
  ght_mutp "GH-T7b mutant: the mode test accepts everything -> exported" '/# GHTLS-MODE$/s|^    .*) return 0 ;;|    *) return 0 ;;|' "$GHT_T/pin/gw.pem" "$_gt_uid" "$GHT_T/pin $GHT_T" ghc_T7 leaf-mode
  ght_cellp "GH-T7d a world-writable leaf: nothing exported, the check is named" ghc_T7 "$GHT_T/pin/ww.pem" "$_gt_uid" "$GHT_T/pin $GHT_T" leaf-mode
  ght_mutp "GH-T7d mutant: the mode test accepts everything -> exported" '/# GHTLS-MODE$/s|^    .*) return 0 ;;|    *) return 0 ;;|' "$GHT_T/pin/ww.pem" "$_gt_uid" "$GHT_T/pin $GHT_T" ghc_T7 leaf-mode
  ght_cellp "GH-T7c a foreign owner: nothing exported, the check is named" ghc_T7 "$GHT_T/pin/cert.pem" "$((_gt_uid + 1))" "$GHT_T/pin $GHT_T" leaf-owner
  ght_mutp "GH-T7c mutant: the owner test deleted -> exported" '/# GHTLS-OWN$/d' "$GHT_T/pin/cert.pem" "$((_gt_uid + 1))" "$GHT_T/pin $GHT_T" ghc_T7 leaf-owner
  ght_cellp "GH-T8 a group-writable parent: nothing exported, the check is named" ghc_T7 "$GHT_T/gwp/cert.pem" "$_gt_uid" "$GHT_T/gwp $GHT_T" parent-
  ght_mutp "GH-T8 mutant: the parent list emptied -> exported" 's|^_GHT_PARENTS=.*# GHTLS-PARENTS$|_GHT_PARENTS=""   # GHTLS-PARENTS|' "$GHT_T/gwp/cert.pem" "$_gt_uid" "$GHT_T/gwp $GHT_T" ghc_T7 parent-
  ght_cellp "GH-T8b a symlinked parent: nothing exported, the check is named" ghc_T7 "$GHT_T/lnk/cert.pem" "$_gt_uid" "$GHT_T/lnk $GHT_T" -not-dir
  ght_mutp "GH-T8b mutant: the parent no-symlink test deleted -> exported" '/# GHTLS-PARENT-LINK$/d' "$GHT_T/lnk/cert.pem" "$_gt_uid" "$GHT_T/lnk $GHT_T" ghc_T7 -not-dir
  if [ "$_gt_uid" = 0 ]; then
    echo "PASS: GH-T8c and its mutant: N/A - running as root, so a non-root parent cannot be built (the leg was NOT exercised)"
  else
    ght_cellp "GH-T8c a parent not owned by uid 0 (the real /): nothing exported, the check is named" ghc_T7 "$GHT_T/pin/cert.pem" "$_gt_uid" "$GHT_T/pin /" -owner
    ght_mutp "GH-T8c mutant: the parent owner test deleted -> exported" '/# GHTLS-PARENT-OWN$/d' "$GHT_T/pin/cert.pem" "$_gt_uid" "$GHT_T/pin /" ghc_T7 -owner
  fi
  ght_acl "GH-T10a leaf: a mode string ending in +" "$GHT_T/pin/cert.pem" leaf-acl "$GHT_T/pin/cert.pem" "$GHT_T/pin $GHT_T" aclpath GHTLS-ACL
  ght_acl "GH-T10b parent: a mode string ending in +" "$GHT_T/pin" -acl "$GHT_T/pin/cert.pem" "$GHT_T/pin $GHT_T" aclpath GHTLS-ACL
  ght_acl "GH-T10c leaf: an @ mode plus an ACL entry line" "$GHT_T/pin/cert.pem" leaf-acl "$GHT_T/pin/cert.pem" "$GHT_T/pin $GHT_T" entpath GHTLS-ACLE
  ght_acl "GH-T10d parent: an @ mode plus an ACL entry line" "$GHT_T/pin" -acl "$GHT_T/pin/cert.pem" "$GHT_T/pin $GHT_T" entpath GHTLS-ACLE
  ght_cell "GH-T9 a caller that redirects stderr to /dev/null: the probe still reads the signature" ghc_T9
  ght_mut "GH-T9 mutant: the capture sends stderr to /dev/null -> no signature seen" '/# GHTLS-CAPTURE$/s|2>&1 >/dev/null|2>/dev/null|' ghc_T9
  ght_cell "GH-S1 sourced from a caller not named gh-tls.sh, it runs nothing and defines no selftest" ghc_S1
  ght_mut "GH-S1 mutant: the direct-run test matches every name -> sourcing runs the main" '/# GHTLS-DIRECT$/s|^  gh-tls.sh) : ;;|  *) : ;;|' ghc_S1
  if ghc_W1 ''; then ght_ok "GH-W1 promotion-verify.sh record: the probe is the first gh call"; else ght_no "GH-W1 promotion-verify.sh record: the probe is the first gh call"; fi
  ght_wmut "GH-W1 mutant: the probe case deleted in the copy -> the first gh call is no longer the probe" ghc_W1 '/^    if command -v kit_gh_tls_pin /d'
  if command -v git > /dev/null 2>&1; then
    if ghc_W2 ''; then ght_ok "GH-W2 the probe runs before the lease gate: the gate child sees the pin"; else ght_no "GH-W2 the probe runs before the lease gate: the gate child sees the pin"; fi
    ght_wmut "GH-W2 mutant: the probe case no longer runs before the gate -> the gate runs unprobed" ghc_W2 's/^  record|land|actuate|trace|evidence)$/  never)/'
  else
    echo "PASS: GH-W2 and its mutant: N/A - git is not available here (the leg was NOT exercised)"
  fi
  rm -rf "$GHT_T"
  if [ "$GHT_FAIL" = 0 ]; then echo "OK: gh-tls selftest passed ($GHT_N cells)"; return 0; fi
  echo "FAIL: gh-tls selftest failed"; return 1
}

_ght_main() {
  case "${1-}" in
    --selftest) _ght_selftest "$0"; exit $? ;;
    *) echo "usage: sh scripts/gh-tls.sh --selftest   (the file is meant to be sourced: . scripts/gh-tls.sh; kit_gh_tls_pin)" >&2; exit 2 ;;
  esac
}

_ght_main "$@"
