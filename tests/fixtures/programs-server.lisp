;;;; tests/fixtures/programs-server.lisp -- a server whose application
;;;; declares a program that is not on PATH, for the start check of
;;;; spec/outbound.md 6: sbcl --load this --port N --db PATH.  Its main
;;;; refuses to start, exiting 2 with a line naming the program.

(load (merge-pathnames "../../scripts/setup.lisp" *load-truename*))
(in-package #:tun-build)

(load-quietly "tun")

(defpackage #:programs-server
  (:use #:cl #:tun))
(in-package #:programs-server)

(define-application programs-server-application ()
  (:programs "sh" "tun-test-no-such-program"))

(tun.runtime:main 'programs-server-application :name "programs-server")
