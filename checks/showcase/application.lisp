;;;; application.lisp -- the showcase application: the kernel alone.

(in-package #:showcase)

(define-application showcase ()
  (:web-app :short-name "Showcase" :icons "icons/")
  (:default-initargs :name "showcase")
  (:documentation "Pages for Tun's browser checks."))

(defparameter *application-class* 'showcase
  "The application class the server runs.")
