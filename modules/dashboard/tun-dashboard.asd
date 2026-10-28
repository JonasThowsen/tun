;;;; tun-dashboard.asd -- the dashboard module (tun-platform.md 2).

(defsystem "tun-dashboard"
  :description "tun module dashboard: the developer's pages: Jobs for background jobs and schedules, Errors for errors, Log for requests."
  :version "1.1.0"
  :depends-on ("tun")
  :components ((:file "dashboard") (:file "jobs") (:file "errors") (:file "log") (:file "nb")))
