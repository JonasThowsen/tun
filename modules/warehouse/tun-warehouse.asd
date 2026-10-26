;;;; tun-warehouse.asd -- the warehouse module (tun-platform.md 2; README).

(defsystem "tun-warehouse"
  :description "tun module warehouse: warehouse tasks and their event ledger."
  :version "1.0.0"
  :depends-on ("tun" "tun-staffing")
  :components ((:file "warehouse")))
