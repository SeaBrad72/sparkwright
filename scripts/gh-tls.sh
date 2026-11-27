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
# `set -eu`). It adds nothing to the guard: the guard admits only the one exact byte-0 literal `SSL_CERT_FILE=/private/etc/ssl/cert.pem ` (D-241120-1); the kit's verb sets its own trust store.
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

# ---- SWAS-945 TLS-C: the census. A static scan of every shipped scripts/*.sh, scripts/kit-guard and conformance/*.sh -----------------------------------------------
# A file that matches a pattern below must name gh-tls.sh on a non-comment line (the source line) or sit on the exempt list (_GHT_EXEMPT), each entry with a reason.
# THE PATTERNS (whole-line comments are skipped; each is an ERE over one line): gh-command = `gh ` at a command position (line start, after ; & | ( { ! or a backtick, or after
# then/do/else/if/elif/while/until); command-gh = `command gh`; gh-var = "$GH", `$GH ` or ${GH}; curl-github = a `curl` line that names github.com (api.github.com too) or githubusercontent.com;
# seam-gh = the seam default `:-gh ` (for example ${X_GH_CMD:-gh repo view}); env-gh = `env` with options or NAME=value words, then `gh `; assign-gh = a `NAME=value gh ` prefix;
# timeout-gh = `timeout [-opts] N gh `; exec-gh = `exec gh `.
# THE LIMIT, STATED: the census does NOT see a gh reached through a wrapper function or script whose own body uses a form not listed above; a `${GH:-gh}`-style default whose
# text is not `:-gh ` followed by a space; `"$(command -v gh)"`; `xargs gh`; `nice gh`; `sh -c "gh ..."`; a string built and run by eval; a child binary; a host held in a
# variable; or any file outside scripts/*.sh, scripts/kit-guard and conformance/*.sh (hooks/, scripts/sparkwright, subdirectories). An exemption is per FILE and is never
# re-proved: a gh call added later to an exempt file is not seen. A script that merely names gh-tls.sh in a non-comment line passes (the census proves the source line
# exists, not that the pin call sits before the first network call: the TLS-W cells and the reviewer read that).
_GHT_CP_GH='(^|[;&|({!`])[[:space:]]*gh[[:space:]]'
_GHT_CP_GH2='(^|[^A-Za-z0-9_./-])(then|do|else|if|elif|while|until)[[:space:]]+gh[[:space:]]'
_GHT_CP_CMD='(^|[^A-Za-z0-9_./-])command[[:space:]]+gh([[:space:]]|$)'
_GHT_CP_VAR='"\$GH"|\$GH[[:space:]]|\$\{GH\}'
_GHT_CP_SEAM=':-gh[[:space:]]'
_GHT_CP_ENV='(^|[^A-Za-z0-9_./-])env([[:space:]]+(-u[[:space:]]+[A-Za-z_][A-Za-z0-9_]*|-[A-Za-z-]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*))*[[:space:]]+gh[[:space:]]'
_GHT_CP_ASSIGN='(^|[^A-Za-z0-9_./-])[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+gh[[:space:]]'
_GHT_CP_TIMEOUT='(^|[^A-Za-z0-9_./-])timeout([[:space:]]+-[A-Za-z-]+)*[[:space:]]+[0-9][0-9.]*[smhd]?[[:space:]]+gh[[:space:]]'
_GHT_CP_EXEC='(^|[^A-Za-z0-9_./-])exec[[:space:]]+gh[[:space:]]'
_GHT_EXEMPT='scripts/gh-tls.sh|the library itself: its one probe call is the pin, so it cannot source itself
scripts/new-profile.sh|prints doc text that names gh; it makes no gh call
scripts/kit-guard|holds gh only as deny-cell strings for the guard battery; it makes no gh call
conformance/agent-autonomy.sh|names gh only in allow and deny cell text; it makes no gh call
conformance/tool-coverage.sh|names gh only in fixture and pattern text; it makes no gh call
conformance/ratification-parity.sh|names gh only in text and fixtures; it makes no gh call
conformance/permission-surface-audit.sh|names gh only as settings-pattern text; it makes no gh call
conformance/agent-boundary.sh|names gh only as deny-pattern text and fixtures; it makes no gh call
conformance/ci-gates.sh|its curl lines name github hosts only as workflow text it reads; it makes no network call of its own
conformance/proportional-gate-wired.sh|its curl lines name github hosts only as workflow text it reads; it makes no network call of its own
conformance/adopter-gates-parity.sh|names gh only in workflow fixtures it writes and greps; it makes no gh call
conformance/poster-parity.sh|names gh only in workflow fixtures it scans; it makes no gh call
conformance/promotion-actuate-wired.sh|names gh only as guard-verdict cell text and a fake gh shim; it makes no real gh call
conformance/promotion-verify-wired.sh|names gh only in comments, cell text and a fake gh shim; it makes no real gh call'

ght_hit() { grep -v '^[[:space:]]*#' "$1" | grep -Eq -e "$2"; }   # <file> <ERE>: rc 0 when a non-comment line matches
ght_cmatch() {   # <file>: the names of the census patterns the file matches (empty = none)
  _gcn_m=''
  if ght_hit "$1" "$_GHT_CP_GH" || ght_hit "$1" "$_GHT_CP_GH2"; then _gcn_m="$_gcn_m gh-command"; fi
  if ght_hit "$1" "$_GHT_CP_CMD"; then _gcn_m="$_gcn_m command-gh"; fi
  if ght_hit "$1" "$_GHT_CP_VAR"; then _gcn_m="$_gcn_m gh-var"; fi
  if ght_hit "$1" "$_GHT_CP_SEAM"; then _gcn_m="$_gcn_m seam-gh"; fi
  if ght_hit "$1" "$_GHT_CP_ENV"; then _gcn_m="$_gcn_m env-gh"; fi
  if ght_hit "$1" "$_GHT_CP_ASSIGN"; then _gcn_m="$_gcn_m assign-gh"; fi
  if ght_hit "$1" "$_GHT_CP_TIMEOUT"; then _gcn_m="$_gcn_m timeout-gh"; fi
  if ght_hit "$1" "$_GHT_CP_EXEC"; then _gcn_m="$_gcn_m exec-gh"; fi
  if grep -v '^[[:space:]]*#' "$1" | grep -E 'curl' | grep -Eq 'github\.com|githubusercontent\.com'; then _gcn_m="$_gcn_m curl-github"; fi
  printf '%s' "${_gcn_m# }"
}
# ght_census <root> <exempt-file>: one line per violation on stdout (empty = clean); the counts go to $GHT_T/census.stat.
ght_census() {
  _gcn_n=0; _gcn_w=0; _gcn_x=0
  awk -F'|' 'NF < 2 || $2 == "" { print "census: exempt entry without a reason: " $1 }' "$2"
  for _gcn_f in "$1"/scripts/*.sh "$1"/scripts/kit-guard "$1"/conformance/*.sh; do
    [ -f "$_gcn_f" ] || continue
    _gcn_m=$(ght_cmatch "$_gcn_f"); [ -n "$_gcn_m" ] || continue
    _gcn_n=$((_gcn_n + 1)); _gcn_r=${_gcn_f#"$1"/}
    if grep -v '^[[:space:]]*#' "$_gcn_f" | grep -Fq 'gh-tls.sh'; then _gcn_w=$((_gcn_w + 1)); continue; fi
    if awk -F'|' -v r="$_gcn_r" '$1 == r && $2 != "" { f = 1 } END { exit !f }' "$2"; then _gcn_x=$((_gcn_x + 1)); continue; fi
    printf 'census: %s matches [%s] and neither names gh-tls.sh on a non-comment line nor sits on the exempt list\n' "$_gcn_r" "$_gcn_m"
  done
  printf 'matched=%s wired=%s exempt=%s\n' "$_gcn_n" "$_gcn_w" "$_gcn_x" > "$GHT_T/census.stat"
}
ght_stat() { sed -n "s/^.*$1=\([0-9][0-9]*\).*\$/\1/p" "$GHT_T/census.stat"; }   # <matched|wired|exempt>
ght_fixtree() {   # <dir> <name> <line> <src|nosrc>: a one-script tree whose script holds <line> and, for src, the library source line
  mkdir -p "$1/scripts" "$1/conformance"
  { printf '%s\n' '#!/bin/sh'
    if [ "$4" = src ]; then printf '%s\n' '_x_ghtls=$(dirname -- "$0")/gh-tls.sh' 'if [ -f "$_x_ghtls" ]; then . "$_x_ghtls"; fi'
    else printf '%s\n' '# shellcheck source=scripts/gh-tls.sh'; fi
    printf '%s\n' "$3"; } > "$1/scripts/$2.sh"
}

# TLS-C1: the real tree is clean (and the scan is live: it saw matches and wired files).
ghc_C1() {
  _gcn_root=$(CDPATH='' cd -- "$(dirname -- "$GHT_SELF")/.." && pwd) || return 1
  printf '%s\n' "$_GHT_EXEMPT" > "$GHT_T/exempt.txt"
  ght_census "$_gcn_root" "$GHT_T/exempt.txt" > "$GHT_T/census.out"
  if [ -s "$GHT_T/census.out" ]; then sed 's/^/    /' "$GHT_T/census.out"; return 1; fi
  [ "$(ght_stat matched)" -gt 0 ] && [ "$(ght_stat wired)" -gt 0 ]
}
# TLS-C2: <name> <line>: with the source line the one-script tree is clean and the pattern matched; without it the census names the file.
ghc_CF() {
  : > "$GHT_T/none.txt"
  rm -rf "$GHT_T/cen"; ght_fixtree "$GHT_T/cen" "$1" "$2" src
  ght_census "$GHT_T/cen" "$GHT_T/none.txt" > "$GHT_T/cen.out"
  [ ! -s "$GHT_T/cen.out" ] && [ "$(ght_stat matched)" = 1 ] && [ "$(ght_stat wired)" = 1 ] || return 1
  rm -rf "$GHT_T/cen"; ght_fixtree "$GHT_T/cen" "$1" "$2" nosrc
  ght_census "$GHT_T/cen" "$GHT_T/none.txt" > "$GHT_T/cen.out"
  grep -Fq "census: scripts/$1.sh matches" "$GHT_T/cen.out"
}
ght_cenc() { if ghc_CF "$2" "$3"; then ght_ok "$1"; else ght_no "$1"; fi; }   # <label> <name> <line>
# TLS-C2 on a REAL script: scripts/dora.sh with its gh-tls.sh lines deleted is named; the untouched copy is clean.
ghc_CR() {
  : > "$GHT_T/none.txt"; _gcr_src=$(dirname -- "$GHT_SELF")/dora.sh
  rm -rf "$GHT_T/cen"; mkdir -p "$GHT_T/cen/scripts"; cp "$_gcr_src" "$GHT_T/cen/scripts/dora.sh"
  ght_census "$GHT_T/cen" "$GHT_T/none.txt" > "$GHT_T/cen.out"; [ ! -s "$GHT_T/cen.out" ] || return 1
  sed '/gh-tls\.sh/d' "$_gcr_src" > "$GHT_T/cen/scripts/dora.sh"
  ght_census "$GHT_T/cen" "$GHT_T/none.txt" > "$GHT_T/cen.out"; grep -Fq 'census: scripts/dora.sh matches' "$GHT_T/cen.out"
}
# TLS-C3: no false alarm on a comment, on a script with no gh, or on a command -v probe; an exempt entry with a reason clears an unwired file, and one without is named.
ghc_CN() {
  : > "$GHT_T/none.txt"
  rm -rf "$GHT_T/cen"; ght_fixtree "$GHT_T/cen" quiet '# gh api user is only a comment' nosrc
  printf '%s\n' 'command -v gh >/dev/null 2>&1 || exit 0' 'echo hello' >> "$GHT_T/cen/scripts/quiet.sh"
  ght_census "$GHT_T/cen" "$GHT_T/none.txt" > "$GHT_T/cen.out"; [ ! -s "$GHT_T/cen.out" ] || return 1
  ght_fixtree "$GHT_T/cen" loud 'gh api user' nosrc
  printf '%s\n' 'scripts/loud.sh|a fixture that holds the text only' > "$GHT_T/ex.txt"
  ght_census "$GHT_T/cen" "$GHT_T/ex.txt" > "$GHT_T/cen.out"; [ ! -s "$GHT_T/cen.out" ] || return 1
  printf '%s\n' 'scripts/loud.sh|' > "$GHT_T/ex.txt"
  ght_census "$GHT_T/cen" "$GHT_T/ex.txt" > "$GHT_T/cen.out"; grep -Fq 'exempt entry without a reason' "$GHT_T/cen.out" && grep -Fq 'census: scripts/loud.sh matches' "$GHT_T/cen.out"
}

# ---- SWAS-945 TLS-W: the probe is the first gh call of each newly wired script (the CL14p shape) -------------------------------------------------------------------
# ghc_WS <sed|''> <relpath> <need-gh-call: 0|1> [args...]: a COPY of the script (optionally mutated by the sed) sits in a fixture tree beside a STUB scripts/gh-tls.sh whose
# kit_gh_tls_pin logs PROBE and exports SSL_CERT_FILE=<fixture>/pin/cert.pem; the fake gh logs its call (and that variable) to the same gh.log. The first line must be PROBE;
# with need-gh-call=1 the second must be a gh call that carries the exported SSL_CERT_FILE (a pin run in a subshell would lose it).
ghc_WS() {
  _gws_sed=$1; _gws_rel=$2; _gws_n2=$3; shift 3
  _gws_root=$GHT_T/ws; _gws_src=$(dirname -- "$GHT_SELF")/..
  rm -rf "$_gws_root"; mkdir -p "$_gws_root/scripts" "$_gws_root/conformance"
  printf 'kit_gh_tls_pin() { printf "PROBE\\n" >> "%s/gh.log"; SSL_CERT_FILE=%s/pin/cert.pem; export SSL_CERT_FILE; }\n' "$GHT_T" "$GHT_T" > "$_gws_root/scripts/gh-tls.sh"
  if [ -n "$_gws_sed" ]; then sed -e "$_gws_sed" "$_gws_src/$_gws_rel" > "$_gws_root/$_gws_rel"; else cp "$_gws_src/$_gws_rel" "$_gws_root/$_gws_rel"; fi
  printf '%s\n' '# checks' '```' 'ci' '```' > "$_gws_root/REQUIRED-CHECKS.md"
  printf '%s\n' '**Security contact:** GitHub private vulnerability reporting' '**Channel repo:** `o/r`' > "$_gws_root/SECURITY.md"
  if command -v git > /dev/null 2>&1; then git init -q "$_gws_root" > /dev/null 2>&1 && git -C "$_gws_root" remote add origin https://github.com/o/r.git; fi
  : > "$GHT_T/gh.log"; printf 'Darwin\n' > "$GHT_T/os"; printf 'tls\n' > "$GHT_T/mode"
  ( cd "$_gws_root" && env -u SSL_CERT_FILE -u SSL_CERT_DIR -u GIT_DIR -u CI PATH="$GHT_T/bin:$PATH" sh "$_gws_root/$_gws_rel" "$@" < /dev/null > "$GHT_T/out" 2> "$GHT_T/err" ) || :
  [ "$(sed -n 1p "$GHT_T/gh.log")" = PROBE ] || return 1
  [ "$_gws_n2" = 0 ] || {
    _gws_l2=$(sed -n 2p "$GHT_T/gh.log"); [ -n "$_gws_l2" ] && [ "$_gws_l2" != PROBE ] || return 1
    case "$_gws_l2" in *"|SSL_CERT_FILE=$GHT_T/pin/cert.pem") return 0 ;; *) return 1 ;; esac   # the gh call carries the pin: a subshell pin would lose it
  }
}
# ght_ws <label> <relpath> <need-gh-call> [args...]: the cell, then its mutant (the pin call line deleted -> the first gh.log line is the gh call, not PROBE).
ght_ws() {
  _gwl=$1; _gwr=$2; _gwn=$3; shift 3; _gwm='/kit_gh_tls_pin; fi/d'
  if ghc_WS '' "$_gwr" "$_gwn" "$@"; then ght_ok "$_gwl"; else ght_no "$_gwl"; fi
  if sed -e "$_gwm" "$(dirname -- "$GHT_SELF")/../$_gwr" | cmp -s - "$(dirname -- "$GHT_SELF")/../$_gwr"; then ght_no "$_gwl mutant: the mutation matched nothing; the leg is unbound"
  elif ghc_WS "$_gwm" "$_gwr" "$_gwn" "$@"; then ght_no "$_gwl mutant: the pin call deleted, and the cell still passes"
  else ght_ok "$_gwl mutant: the pin call deleted -> the first gh call is not the probe"; fi
  _gws2='s/then kit_gh_tls_pin; fi/then (kit_gh_tls_pin); fi/'
  if sed -e "$_gws2" "$(dirname -- "$GHT_SELF")/../$_gwr" | cmp -s - "$(dirname -- "$GHT_SELF")/../$_gwr"; then ght_no "$_gwl subshell mutant: the mutation matched nothing; the leg is unbound"
  elif ghc_WS "$_gws2" "$_gwr" "$_gwn" "$@"; then ght_no "$_gwl subshell mutant: the pin run in a subshell, and the cell still passes"
  else ght_ok "$_gwl subshell mutant: the pin run in a subshell -> the gh call does not carry SSL_CERT_FILE"; fi
}
# TLS-W preflight (SWAS-945): a COPY of preflight.sh beside incept.sh and the REAL library copy (pointed at the fixture pin and a fake uname), run from the kit root with a fake gh
# that fails x509 unless SSL_CERT_FILE is set: `gh auth status` reads valid only when the pin ran. <$1> is a sed expression for the copy ('' = none).
ghc_PF() {
  _gpf=$GHT_T/pf; _gpf_src=$(dirname -- "$GHT_SELF"); rm -rf "$_gpf"; mkdir -p "$_gpf"
  ght_lib "$_gpf/gh-tls.sh"
  if [ -n "$1" ]; then sed -e "$1" "$_gpf_src/preflight.sh" > "$_gpf/preflight.sh"; else cp "$_gpf_src/preflight.sh" "$_gpf/preflight.sh"; fi
  cp "$_gpf_src/incept.sh" "$_gpf/incept.sh"
  : > "$GHT_T/gh.log"; printf 'Darwin\n' > "$GHT_T/os"; printf 'tls\n' > "$GHT_T/mode"
  ( cd "$_gpf_src/.." && env -u SSL_CERT_FILE -u SSL_CERT_DIR PATH="$GHT_T/bin:$PATH" sh "$_gpf/preflight.sh" < /dev/null > "$GHT_T/out" 2> "$GHT_T/err" ) || :
  ght_in "$GHT_T/out" 'ok   gh auth (logged in)'
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
  # SWAS-945. TLS-C1: the census on the real tree; TLS-C2: one negative per pattern (the same one-script tree without its source line is named); TLS-C3: no false alarm, exempt list.
  if ghc_C1; then ght_ok "TLS-C1 the census: every shipped script that reaches GitHub names gh-tls.sh or sits on the exempt list with a reason"; else ght_no "TLS-C1 the census: every shipped script that reaches GitHub names gh-tls.sh or sits on the exempt list with a reason"; fi
  ght_cenc "TLS-C2 gh at the start of a line, source line deleted -> the file is named" c2a 'gh api user'
  ght_cenc "TLS-C2 gh after \$( , source line deleted -> the file is named" c2b 'x=$(gh pr view 1)'
  ght_cenc "TLS-C2 gh after if, source line deleted -> the file is named" c2c 'if gh auth status; then :; fi'
  ght_cenc "TLS-C2 command gh, source line deleted -> the file is named" c2d 'command gh api user'
  ght_cenc "TLS-C2 \"\$GH\", source line deleted -> the file is named" c2e '"$GH" api user'
  ght_cenc "TLS-C2 \$GH followed by a space, source line deleted -> the file is named" c2f '$GH pr list'
  ght_cenc "TLS-C2 \${GH}, source line deleted -> the file is named" c2g 'x=${GH}'
  ght_cenc "TLS-C2 the seam default :-gh followed by a space, source line deleted -> the file is named" c2k 'x=${X_GH_CMD:-gh repo view}'
  ght_cenc "TLS-C2 env with options then gh, source line deleted -> the file is named" c2l 'env -u SSL_CERT_FILE gh api user'
  ght_cenc "TLS-C2 a NAME=value prefix on gh, source line deleted -> the file is named" c2m 'FOO=1 gh api user'
  ght_cenc "TLS-C2 timeout N gh, source line deleted -> the file is named" c2n 'timeout 30 gh api user'
  ght_cenc "TLS-C2 exec gh, source line deleted -> the file is named" c2o 'exec gh api user'
  ght_cenc "TLS-C2 curl naming api.github.com,source line deleted -> the file is named" c2h 'curl -s https://api.github.com/user'
  ght_cenc "TLS-C2 curl naming github.com, source line deleted -> the file is named" c2i 'curl -sL https://github.com/x/y/archive/z.tar.gz'
  ght_cenc "TLS-C2 curl naming githubusercontent.com, source line deleted -> the file is named" c2j 'curl -s https://raw.githubusercontent.com/x/y/z'
  if ghc_CR; then ght_ok "TLS-C2 the real scripts/dora.sh with its gh-tls.sh lines deleted is named"; else ght_no "TLS-C2 the real scripts/dora.sh with its gh-tls.sh lines deleted is named"; fi
  if ghc_CN; then ght_ok "TLS-C3 a comment, a command -v probe and a gh-free script pass; an exempt entry needs its reason"; else ght_no "TLS-C3 a comment, a command -v probe and a gh-free script pass; an exempt entry needs its reason"; fi
  # TLS-W: each newly wired script with a --selftest whose gh route this harness can drive without a network. The others (board-claim, board-drift, mirror-tag-protection,
  # inception-done, prepush-lane --refresh-times, publish-public, release-tag, slice-resume, agent-trace) rest on the census alone: their gh route needs a fixture of its own.
  ght_ws "TLS-W dora.sh: the probe is the first gh call" scripts/dora.sh 1
  ght_ws "TLS-W security-channel-live.sh: the probe is the first gh call" conformance/security-channel-live.sh 1 .
  ght_ws "TLS-W branch-protection-apply.sh: the probe is the first gh call" scripts/branch-protection-apply.sh 1 --repo=o/r
  ght_ws "TLS-W branch-protection.sh: the probe is the first gh call" conformance/branch-protection.sh 1 --repo=o/r
  if command -v git > /dev/null 2>&1; then
    ght_ws "TLS-W doctor.sh --as agent: the probe is the first gh call" scripts/doctor.sh 1 --as agent
  else
    echo "PASS: TLS-W doctor.sh and its mutant: N/A - git is not available here (the leg was NOT exercised)"
  fi
  # TLS-W preflight: the auth read reads valid only when the pin ran; the mutant (the source line removed) reads invalid.
  if ghc_PF ''; then ght_ok "TLS-W preflight.sh: with the pin the fake gh's auth read reads valid"; else ght_no "TLS-W preflight.sh: with the pin the fake gh's auth read reads valid"; fi
  _gpm='/then \. "\$_pf_ghtls"; fi/d'
  if sed -e "$_gpm" "$(dirname -- "$GHT_SELF")/preflight.sh" | cmp -s - "$(dirname -- "$GHT_SELF")/preflight.sh"; then ght_no "TLS-W preflight.sh mutant: the mutation matched nothing; the leg is unbound"
  elif ghc_PF "$_gpm"; then ght_no "TLS-W preflight.sh mutant: the source line removed, and the auth read still reads valid"
  else ght_ok "TLS-W preflight.sh mutant: the source line removed -> the auth read reads invalid"; fi
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
