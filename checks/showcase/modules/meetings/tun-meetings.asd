;;;; tun-meetings.asd -- the showcase's module meetings (meetings.lisp).

(defsystem "tun-meetings"
  :description "The showcase's module meetings: a meeting with a customer."
  :version "0.1.0"
  :depends-on ("tun" "tun-customers")
  :serial t
  :components ((:file "meetings")
               (:file "nb")))
