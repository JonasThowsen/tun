#!/usr/bin/env bash
# Exercise the indentation CLI on disposable source files.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/tun-indent.XXXXXX")"
trap 'rm -rf "$work"' EXIT

expect_exit() {
  local expected="$1" status=0
  shift
  "$@" >"$work/output" 2>&1 || status=$?
  if [ "$status" -ne "$expected" ]; then
    cat "$work/output" >&2
    echo "expected exit $expected, got $status" >&2
    exit 1
  fi
}
cat >"$work/input.lisp" <<'LISP'
(define-operation greet ((name :type string))
(:kind :read)
(with-actor (actor)
(format nil "Hei, ~a" name)))
LISP
cat >"$work/expected.lisp" <<'LISP'
(define-operation greet ((name :type string))
    (:kind :read)
  (with-actor (actor)
    (format nil "Hei, ~a" name)))
LISP
cp "$work/input.lisp" "$work/original.lisp"
expect_exit 1 "$here/bin/indent" --check "$work/input.lisp"
cmp "$work/original.lisp" "$work/input.lisp"
printf '%s\n' "$work/input.lisp" >"$work/changed-files"
cmp "$work/changed-files" "$work/output"
"$here/bin/indent" "$work/input.lisp"
cmp "$work/expected.lisp" "$work/input.lisp"
cp "$work/input.lisp" "$work/indented.lisp"
"$here/bin/indent" "$work/input.lisp"
cmp "$work/indented.lisp" "$work/input.lisp"
expect_exit 0 "$here/bin/indent" --check "$work/input.lisp"
[ ! -s "$work/output" ]

cat >"$work/expected-macros.lisp" <<'LISP'
(define-entity customer
    (:label "Kunde")
  ((name :type string)))
(tun:define-operation customers-get ((id :type string))
    (:kind :read)
  (fetch id))
(define-rule name-required (customer c)
    (:field "name")
  (customer-name c))
(define-computed-field customer label (c)
    (:type string)
  (customer-name c))
(define-workflow remind
    (:kind "påminnelse")
    (wf)
  (send-message wf))
(define-message-template greeting
    (:template "hei")
    (&key customer)
  (customer-name customer))
(define-module customers
  (:core ">= 1.0"))
(extend-entity customer
    (:name details)
  ((note :type string)))
(define-setting "avsender"
    (:type string))
(define-application example
    (customer-feature)
  (:modules customers))
(with-transaction (:write)
  (with-application (app)
    (with-audit-scope
      (with-constraint-mapping
        (save-record)))))
LISP
sed 's/^ *//' "$work/expected-macros.lisp" >"$work/macros.lisp"
"$here/bin/indent" "$work/macros.lisp"
cmp "$work/expected-macros.lisp" "$work/macros.lisp"

# Paths are relative to the caller, and -- protects option-like filenames.
cp "$work/original.lisp" "$work/-copy with spaces.lisp"
(cd "$work" && "$here/bin/indent" -- '-copy with spaces.lisp')
cmp "$work/expected.lisp" "$work/-copy with spaces.lisp"
expect_exit 2 "$here/bin/indent" --unknown-option
expect_exit 2 "$here/bin/indent" "$work/missing.lisp"
printf '(defun broken ()\n(print :unfinished)\n' >"$work/broken.lisp"
cp "$work/broken.lisp" "$work/original-broken.lisp"
expect_exit 2 "$here/bin/indent" "$work/broken.lisp"
cmp "$work/original-broken.lisp" "$work/broken.lisp"

cat >"$work/text.lisp" <<'LISP'
(defun text ()
"æ, ø og å
   literal indentation"
;; A comment with #.(error "do not evaluate source").
(list #\) #\( "#| text |#"))
LISP
cat >"$work/expected-text.lisp" <<'LISP'
(defun text ()
  "æ, ø og å
   literal indentation"
  ;; A comment with #.(error "do not evaluate source").
  (list #\) #\( "#| text |#"))
LISP
"$here/bin/indent" "$work/text.lisp"
cmp "$work/expected-text.lisp" "$work/text.lisp"
echo "== indentation CLI checks passed"
