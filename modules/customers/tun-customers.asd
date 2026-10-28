;;;; tun-customers.asd -- the customers module (tun-platform.md 2).

(defsystem "tun-customers"
  :description "tun module customers: customer records."
  :version "1.0.0"
  :depends-on ("tun")
  :serial t
  :components ((:file "customers")
               (:file "nb")))
