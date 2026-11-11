;;;; application.lisp -- the showcase application: the kernel alone, its copy
;;;; written in English and offered in Norwegian too (nb.lisp).

(in-package #:showcase)

(define-application showcase ()
  (:web-app :short-name "Showcase" :icons "icons/")
  (:locale :languages ("en" "nb"))
  (:home "/graph")
  (:default-initargs :name "showcase")
  (:documentation "Pages for Tun's browser checks."))

(defmethod home-path ((app showcase) actor)
  ;; spec/ui.md 8, «Home»: admins finish the welcome first (welcome.lisp).
  (if (and (eq (actor-role actor) :admin) (not (welcome-finished-p)))
      "/welcome"
      (call-next-method)))

(defparameter *application-class* 'showcase
  "The application class the server runs.")
