;;;; tun-orders.asd -- the orders module (tun-platform.md 2).

(defsystem "tun-orders"
  :description "tun module orders: orders, quotes, pricing, logistics, checklists, bookings, reservations."
  :version "1.0.0"
  :depends-on ("tun" "tun-customers" "tun-catalog" "tun-inventory" "tun-reviews")
  :serial t
  :components ((:file "package")
               (:file "orders")
               (:file "requirements")
               (:file "plans")
               (:file "stock")
               (:file "transitions")
               (:file "quotes")
               (:file "public-offers")
               (:file "checklists")
               (:file "publish")
               (:file "nb")))
