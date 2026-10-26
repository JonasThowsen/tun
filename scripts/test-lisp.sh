#!/usr/bin/env bash
# Check lisp, from slynk-cli, on Tun (spec/tooling.md, "Agent REPL"): an
# image of tun/core through .slynk-cli.sexp, compiled under the project's
# policy into the image's own directory, paused at an error in Tun's own
# code.  Its records go to a directory of the test's, so an agent's image
# of this checkout is left alone.  slynk-cli's own test checks the rest.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/tun-lisp.XXXXXX")"
export SLYNK_CLI_STATE="$work/state"
# A system of the test's own under the root, to see the policy it compiles with.
probe="$here/.build/lisp-policy-probe"
trap 'lisp stop >/dev/null 2>&1 || true; rm -rf "$work" "$probe"' EXIT
cd "$here"

out="$work/answer"
code=0
run() {
  code=0
  lisp "$@" >"$out" 2>&1 </dev/null || code=$?
}
fail() {
  echo "--- lisp $*" >&2
  cat "$out" >&2
  exit 1
}
expect() {
  local expected="$1"
  shift
  [ "$code" -eq "$expected" ] || fail "exited $code, not $expected"
  for pattern in "$@"; do
    grep -qE -- "$pattern" "$out" || fail "has no line matching: $pattern"
  done
}

command -v lisp >/dev/null || { echo "test-lisp: lisp is not on PATH; run inside nix develop" >&2; exit 1; }
run start tun/core
expect 0 'tun/core loaded'
run eval "(namestring (asdf:apply-output-translations \"$here/src/core/util.lisp\"))"
expect 0 "$SLYNK_CLI_STATE/fasl/src/core/util"
mkdir -p "$probe"
echo '(defsystem "lisp-policy-probe" :components ((:file "probe")))' >"$probe/lisp-policy-probe.asd"
echo '(eval-when (:compile-toplevel) (defparameter cl-user::*probe-policy* (sb-ext:restrict-compiler-policy)))' \
  >"$probe/probe.lisp"
run eval "(progn (asdf:load-asd \"$probe/lisp-policy-probe.asd\") (asdf:load-system \"lisp-policy-probe\") cl-user::*probe-policy*)"
expect 0 '\(\(DEBUG \. 3\)\)'
run eval '(tun.core::date-add-days "no date" 1)'
expect 1 'is paused in the debugger' 'invalid date "no date"' '^ +0  \(TUN.CORE:+DATE-ADD-DAYS "no date" 1\)  src/core/util.lisp:17[0-9]$'
id="$(grep -oE 'evaluation [0-9]+' "$out" | head -1 | grep -oE '[0-9]+')"
run frame "$id" 0
expect 0 'days  #@[0-9]+ = 1' 'restartable: yes'
run stop
expect 0 'stopped the image'
echo "== lisp checks on Tun passed"
