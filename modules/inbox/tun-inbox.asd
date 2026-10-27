(defsystem "tun-inbox"
  :description "Inbound requests, matching, threading and client draft defaults."
  :version "1.1.0"
  :depends-on ("tun" "tun-customers" "tun-orders" "tun-notifications")
  :serial t
  :components ((:file "inbox") (:file "public-feedback") (:file "web")))
