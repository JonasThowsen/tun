;;;; tun-messaging.asd -- the messaging module (tun-platform.md 2).

(defsystem "tun-messaging"
  :description "tun module messaging: messages, transport, default templates."
  :version "1.0.0"
  :depends-on ("tun" "tun-orders" "tun-customers" "tun-notifications" "tun-inbox")
  :serial t
  :components ((:file "messaging") (:file "outbox") (:file "web") (:file "nb")))
