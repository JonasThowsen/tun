;;;; tun-staffing.asd -- the staffing module (tun-platform.md 2).

(defsystem "tun-staffing"
  :description "tun module staffing: employees, departments, assignments, unavailability, work sessions."
  :version "1.0.0"
  :depends-on ("tun" "tun-orders")
  :serial t
  :components ((:file "staffing")
               (:file "assignments")
               (:file "unavailability")))
