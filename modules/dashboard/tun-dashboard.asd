;;;; tun-dashboard.asd -- the dashboard module (tun-platform.md 2).

(defsystem "tun-dashboard"
  :description "tun module dashboard: the developer's pages: «Jobber» for background jobs and schedules, «Feil» for errors, «Logg» for requests."
  :version "1.1.0"
  :depends-on ("tun")
  :components ((:file "dashboard") (:file "jobs") (:file "errors") (:file "log")))
