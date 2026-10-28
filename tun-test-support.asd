;;;; tun-test-support.asd -- the test helpers of the core suite and of every
;;;; client's suite (tests/support.lisp).
;;;;
;;;; A system of its own rather than a secondary system of tun.asd, so Nix
;;;; can build it as a package beside the kernel: a client outside this
;;;; repository gets both from the store (spec/cli.md 6).

(defsystem "tun-test-support"
  :description "Helpers shared by the core and client test-suites."
  :depends-on ("tun" "drakma" "usocket")
  :components ((:module "tests" :components ((:file "support") (:file "i18n-support") (:file "scenarios")))))
