;;;; showcase.asd -- the client Tun's own browser checks drive
;;;; (spec/preview.md 4): pages that show the design system's components with
;;;; a server behind them. bin/check previews it and runs checks/*.py.

(defsystem "showcase"
  :description "Pages for Tun's browser checks."
  :version "0.1.0"
  :depends-on ("tun" "tun-customers" "tun-meetings")
  :serial t
  :components ((:file "package")
               (:file "cards")
               (:file "pages")
               (:file "lists")
               (:file "fields")
               (:file "prices")
               (:file "markdown")
               (:file "graph")
               (:file "notifications")
               (:file "mail")
               (:file "welcome")
               (:file "wait")
               (:file "application")
               (:file "public")
               (:file "nb")))

(defsystem "showcase/tests"
  :description "The showcase's scenarios."
  :depends-on ("showcase" "tun-test-support")
  :serial t
  :components ((:module "tests"
                :components ((:file "package")
                             (:file "scenarios")))))
