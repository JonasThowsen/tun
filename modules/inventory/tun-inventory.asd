;;;; tun-inventory.asd -- the inventory module (tun-platform.md 2).

(defsystem "tun-inventory"
  :description "tun module inventory: stock articles, the ledger, reservations, consumption, forecast, transfers."
  :version "1.0.0"
  :depends-on ("tun" "tun-catalog")
  :serial t
  :components ((:file "inventory")
               (:file "articles")
               (:file "stock")
               (:file "consumption")
               (:file "forecast")
               (:file "publish")))
