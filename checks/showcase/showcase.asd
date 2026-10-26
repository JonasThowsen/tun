;;;; showcase.asd -- the client Tun's own browser checks drive
;;;; (spec/preview.md 4): pages that show the design system's components with
;;;; a server behind them. bin/check previews it and runs checks/*.py.

(defsystem "showcase"
  :description "Pages for Tun's browser checks."
  :version "0.1.0"
  :depends-on ("tun")
  :serial t
  :components ((:file "package")
               (:file "cards")
               (:file "pages")
               (:file "application")))

(defsystem "showcase/tests"
  :description "The showcase's scenarios."
  :depends-on ("showcase" "tun-test-support")
  :serial t
  :components ((:module "tests"
                :components ((:file "package")
                             (:file "scenarios")))))
