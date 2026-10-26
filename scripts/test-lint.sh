#!/usr/bin/env bash
# Exercise the lint CLI without loading the application.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/tun-lint.XXXXXX")"
trap 'rm -rf "$work"' EXIT

expect_exit() {
  local expected="$1" status=0
  shift
  "$@" >"$work/output" 2>"$work/errors" || status=$?
  if [ "$status" -ne "$expected" ]; then
    cat "$work/output" "$work/errors" >&2
    echo "expected exit $expected, got $status" >&2
    exit 1
  fi
}
cat >"$work/clean.lisp" <<'LISP'
(defpackage #:lint-example
  (:use #:cl))
(in-package #:lint-example)
(defun twice (number)
  (* 2 number))
LISP
"$here/bin/lint" "$work/clean.lisp" >"$work/output"

cat >"$work/exported.lisp" <<'LISP'
(defpackage #:lint-exported
  (:use #:cl)
  (:export #:undocumented))
(in-package #:lint-exported)
(defun undocumented ()
  :result)
LISP
expect_exit 1 "$here/bin/lint" "$work/exported.lisp"
grep -q 'missing-docstring' "$work/output"

expect_exit 0 "$here/bin/lint" --format json "$work/clean.lisp"
cp "$work/output" "$work/report.json"
sbcl --noinform --non-interactive --no-userinit --no-sysinit \
  --load "$here/scripts/setup.lisp" \
  --eval '(tun-build:load-quietly "com.inuoe.jzon")' \
  --eval "(com.inuoe.jzon:parse (uiop:read-file-string \"$work/report.json\"))"

expect_exit 0 "$here/bin/lint" --baseline "$work/baseline.md" \
  "$work/exported.lisp" "$work/clean.lisp"
awk -F '|' '
  $2 ~ /exported.lisp/ { seen=1; if ($3 + 0 != 1) exit 1 }
  END { if (!seen) exit 1 }
' "$work/baseline.md"
grep -q 'missing-docstring (1)' "$work/baseline.md"

cat >"$work/read-eval.lisp" <<LISP
#.(with-open-file (out "$work/evaluated" :direction :output) (write-line "executed" out))
LISP
expect_exit 0 "$here/bin/lint" "$work/read-eval.lisp"
[ ! -e "$work/evaluated" ]

echo "original report" >"$work/error-report.md"
cp "$work/error-report.md" "$work/expected.md"
expect_exit 3 "$here/bin/lint" --baseline "$work/error-report.md" --unknown-option
cmp "$work/expected.md" "$work/error-report.md"
echo "== lint CLI checks passed"
