;;;; tun-calendar.asd -- the calendar module (tun-platform.md 2).

(defsystem "tun-calendar"
  :description "tun module calendar: calendar events and the merged calendar."
  :version "1.0.0"
  :depends-on ("tun" "tun-orders" "tun-staffing")
  :components ((:file "calendar") (:file "nb")))
