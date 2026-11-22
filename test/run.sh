#!/usr/bin/env bash
# test/run.sh - test nb-secrets against a test double of age, inside a pseudo-terminal
#
# Usage:
#   test/run.sh
#   test/run.sh -h | --help
#
# No real secret and no real passphrase is involved: test/shim/age records the "passphrase" in
# the file instead of encrypting. Commands that need a terminal run in a pseudo-terminal
# (test/pty.py, needs python3).
# Exits 0 if every check passes, 1 otherwise.

# SC2016: the single-quoted bash -c snippets below are meant to expand in the child shell.
# shellcheck disable=SC2016
set -uo pipefail

case "${1:-}" in
  -h|--help) sed -n '2,/^$/{/^$/!p;}' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

here=$(cd "$(dirname "$0")" && pwd)
NBS="$here/../bin/nb-secrets"
work=$(mktemp -d "${TMPDIR:-/tmp}/nb-secrets-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
export PATH="$here/shim:$PATH"
export NB_SECRETS_DIR="$work/secrets"
mkdir -m 700 "$NB_SECRETS_DIR"
cd "$work" || exit 1

pass=0; fail=0
ok()   { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

# pty <stdin-text> <bash-command>: run the command with a terminal on stdin/stdout/stderr;
# <stdin-text> is typed into it. Sets $out (CRs removed) and $rc.
pty() {
  local text="$1" cmd="$2"
  out=$(printf '%b' "$text" | python3 -I "$here/pty.py" bash -c "$cmd" 2>&1); rc=$?
  out=$(printf '%s' "$out" | tr -d '\r')
}
has()  { printf '%s' "$out" | grep -qF -- "$1"; }
check() { # check <name> <condition...>
  local name="$1"; shift
  if "$@"; then ok "$name"; else bad "$name" "rc=$rc out=$(printf '%s' "$out" | head -3 | tr '\n' '|')"; fi
}
rc_is() { [ "$rc" -eq "$1" ]; }

F="$NB_SECRETS_DIR/t.env.age"
SECRET1='s3cr3t-value-ONE'
SECRET2='second value $with#chars'

echo "help and usage"
out=$("$NBS" -h); rc=$?
check "-h prints usage on stdout, exit 0" bash -c '[ '"$rc"' -eq 0 ] && printf "%s" "$1" | grep -q "^Usage:"' _ "$out"
out=$("$NBS" --version); rc=$?
check "--version" bash -c 'printf "%s" "$1" | grep -q "^nb-secrets "' _ "$out"
out=$("$NBS" 2>&1); rc=$?
check "no arguments: usage, exit 1" rc_is 1
out=$("$NBS" bogus 2>&1); rc=$?
check "unknown command: exit 1" rc_is 1

echo "terminal requirement"
out=$("$NBS" set "$F" X </dev/null 2>&1); rc=$?
check "set refuses without a terminal" bash -c '[ '"$rc"' -ne 0 ] && printf "%s" "$1" | grep -q "interactive terminal"' _ "$out"
printf 'export Q=1\n' | age -p -o "$work/q.age"
out=$("$NBS" run "$work/q.age" -- true </dev/null 2>&1); rc=$?
check "run refuses without a terminal" bash -c '[ '"$rc"' -ne 0 ] && printf "%s" "$1" | grep -q "interactive terminal"' _ "$out"

echo "set / list"
pty "$SECRET1\n" "'$NBS' set '$F' API_TOKEN"
check "set creates a new file" rc_is 0
check "set reports added" has "added: API_TOKEN"
check "set never prints the value" bash -c '! printf "%s" "$1" | grep -qF "$2"' _ "$out" "$SECRET1"
check "file mode is 600" bash -c '[ "$(stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1")" = 600 ]' _ "$F"
pty "$SECRET2\n" "'$NBS' set '$F' DB_PASSWORD"
check "set adds a second variable" has "added: DB_PASSWORD"
pty "" "'$NBS' list '$F'"
check "list shows both names" bash -c 'printf "%s" "$1" | grep -q API_TOKEN && printf "%s" "$1" | grep -q DB_PASSWORD' _ "$out"
check "list shows today's date" has "$(date +%F)"
check "list never prints a value" bash -c '! printf "%s" "$1" | grep -qF "$2"' _ "$out" "$SECRET1"
pty "" "'$NBS' list"
check "list (no file) shows the .age files" has "t.env.age"
pty "v2\n" "'$NBS' set '$F' API_TOKEN"
check "set replaces an existing name" has "replaced: API_TOKEN"
pty "x\n" "'$NBS' set '$F' PATH"
check "set refuses PATH" bash -c '[ '"$rc"' -ne 0 ] && printf "%s" "$1" | grep -q refusing' _ "$out"
pty "x\n" "'$NBS' set '$F' 'bad name'"
check "set refuses an invalid name" bash -c '[ '"$rc"' -ne 0 ]' 
pty "\n" "'$NBS' set '$F' EMPTY"
check "set refuses an empty value" bash -c '[ '"$rc"' -ne 0 ] && printf "%s" "$1" | grep -q "empty value"' _ "$out"
pty "piped-value\n" "echo piped | '$NBS' set '$F' FROM_PIPE"
check "set reads the value from a pipe" has "added: FROM_PIPE"

echo "run"
pty "" "'$NBS' run '$F' -- sh -c 'echo \"len=\${#DB_PASSWORD} api=\$API_TOKEN\"'"
check "run exports the variables to the command" has "len=${#SECRET2} api=v2"
pty "" "'$NBS' run --only DB_PASSWORD '$F' -- sh -c 'echo \"db=\${DB_PASSWORD:+set} api=\${API_TOKEN:-unset}\"'"
check "run --only passes only the named variable" has "db=set api=unset"
pty "" "'$NBS' run --only NOPE '$F' -- echo ran"
check "run --only stops on an unknown name, command not run" bash -c '[ '"$rc"' -ne 0 ] && ! printf "%s" "$1" | grep -qx ran' _ "$out"
pty "" "SHIM_PW=wrong '$NBS' run '$F' -- echo ran"
check "run with a wrong passphrase does not run the command" bash -c '[ '"$rc"' -ne 0 ] && ! printf "%s" "$1" | grep -qx ran && printf "%s" "$1" | grep -q "decrypt failed"' _ "$out"
pty "" "'$NBS' run '$F' -- sh -c 'exit 7'"
check "run returns the command's exit status" rc_is 7
pty "" "API_TOKEN=outer '$NBS' run '$F' -- true; echo \"after=\${DB_PASSWORD:-gone}\""
check "run leaves nothing in the calling shell" has "after=gone"

echo "delete"
pty "n\n" "'$NBS' delete '$F' FROM_PIPE"
check "delete answered n changes nothing" has "cancelled"
pty "y\n" "'$NBS' delete '$F' FROM_PIPE"
check "delete answered y removes it" has "deleted: FROM_PIPE"
pty "y\n" "'$NBS' delete '$F' NOT_THERE"
check "delete of an unknown name fails" bash -c '[ '"$rc"' -ne 0 ]'

echo "passwd"
pty "" "SHIM_PW=pw SHIM_PW_ENC=newpw '$NBS' passwd '$F'"
check "passwd re-encrypts under the new passphrase" has "passphrase changed"
pty "" "SHIM_PW=pw '$NBS' list '$F'"
check "the old passphrase no longer opens the file" bash -c '[ '"$rc"' -ne 0 ]'
pty "" "SHIM_PW=newpw '$NBS' list '$F'"
check "the new passphrase opens the file" bash -c '[ '"$rc"' -eq 0 ] && printf "%s" "$1" | grep -q API_TOKEN' _ "$out"
export SHIM_PW=newpw

echo "list --stale"
old=$(date -v-120d +%F 2>/dev/null || date -d '120 days ago' +%F)
S="$NB_SECRETS_DIR/stale.env.age"
printf 'export OLD1=x  # updated=%s\nexport NEW1=y  # updated=%s\nexport NODATE=z\n' "$old" "$(date +%F)" | SHIM_PW=newpw age -p -o "$S"
pty "" "'$NBS' list --stale 90 '$S'"
check "--stale flags old and undated, exits 1" bash -c '[ '"$rc"' -eq 1 ] && printf "%s" "$1" | grep -q "OLD1.*older than 90" && printf "%s" "$1" | grep -q "NODATE.*no date" && ! printf "%s" "$1" | grep "NEW1" | grep -q "<-"' _ "$out"
pty "" "'$NBS' list --stale 400 '$S'"
check "--stale 400 flags only the undated one" bash -c 'printf "%s" "$1" | grep -q "NODATE.*no date" && ! printf "%s" "$1" | grep "OLD1" | grep -q "<-"' _ "$out"

echo "compare"
printf 'export A=1\nexport B=2\nexport C=3\nexport PATH=/x:$PATH\n' | SHIM_PW=newpw age -p -o "$work/c.age"
printf 'export A=1\nexport B=different\n#export C=3\nexport PATH=/nowhere\n' > "$work/old.env"
pty "" "'$NBS' compare '$work/old.env' '$work/c.age'"
check "compare: OK for equal" bash -c 'printf "%s" "$1" | grep -Eq "^A +OK"' _ "$out"
check "compare: DIFF for different" bash -c 'printf "%s" "$1" | grep -Eq "^B +DIFF"' _ "$out"
check "compare: MISSING-IN-OLD for commented-out" bash -c 'printf "%s" "$1" | grep -Eq "^C +MISSING-IN-OLD"' _ "$out"
check "compare: skips PATH with a warning and survives it" bash -c 'printf "%s" "$1" | grep -q "PATH is defined"' _ "$out"
check "compare: exit 1 when something differs" rc_is 1
check "compare never prints a value" bash -c '! printf "%s" "$1" | grep -q "different"' _ "$out"

echo "doctor"
good="$work/good"; mkdir -m 700 "$good"; : > "$good/a.age"; chmod 600 "$good/a.age"
pty "" "NB_SECRETS_DIR='$good' HOME='$work/home' '$NBS' doctor"
check "doctor: passes on a clean directory (ignoring git)" bash -c 'printf "%s" "$1" | grep -q "700" && printf "%s" "$1" | grep -q "1 .age file"' _ "$out"
badd="$work/bad"; mkdir -m 755 "$badd"; : > "$badd/b.age"; chmod 644 "$badd/b.age"; : > "$badd/plain.env"; : > "$badd/c.age.new"
pty "" "NB_SECRETS_DIR='$badd' HOME='$work/home' '$NBS' doctor"
check "doctor: flags mode, plaintext and leftover temp file; exit 1" bash -c '[ '"$rc"' -eq 1 ] && printf "%s" "$1" | grep -q "mode 755" && printf "%s" "$1" | grep -q "mode 644" && printf "%s" "$1" | grep -q "plain.env" && printf "%s" "$1" | grep -q "leftover temp"' _ "$out"
out=$(NB_SECRETS_DIR="$good" HOME="$work/home" "$NBS" doctor 2>&1 </dev/null); rc=$?
check "doctor needs no terminal and no passphrase" bash -c 'printf "%s" "$1" | grep -q "age installed"' _ "$out"

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
