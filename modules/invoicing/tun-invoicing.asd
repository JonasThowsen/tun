;;;; tun-invoicing.asd -- the invoicing module (tun-platform.md 2).

(defsystem "tun-invoicing"
  :description "tun module invoicing: invoices from orders, the accounting port."
  :version "1.0.0"
  :depends-on ("tun" "tun-orders")
  :components ((:file "invoicing")))
