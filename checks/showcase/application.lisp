;;;; application.lisp -- the showcase application: the kernel alone, its copy
;;;; written in English and offered in Norwegian too (nb.lisp).

(in-package #:showcase)

(define-application showcase ()
  (:web-app :short-name "Showcase" :icons "icons/")
  (:locale :languages ("en" "nb"))
  (:default-initargs :name "showcase")
  (:documentation "Pages for Tun's browser checks."))

(defparameter *application-class* 'showcase
  "The application class the server runs.")
