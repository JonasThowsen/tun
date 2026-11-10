;;;; tun-logbook.asd -- the test client's module logbook (README).

(defsystem "tun-logbook"
  :description "The test client's module logbook: notes the staff keep."
  :version "0.1.0"
  :depends-on ("tun")
  :serial t
  :components ((:file "logbook")
               (:file "nb")))
