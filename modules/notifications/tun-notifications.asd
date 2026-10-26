(defsystem "tun-notifications"
  :description "Employee notifications, published in the triggering transaction."
  :version "1.0.0"
  :depends-on ("tun" "tun-customers" "tun-orders" "tun-staffing")
  :serial t
  :components ((:file "notifications") (:file "web")))
