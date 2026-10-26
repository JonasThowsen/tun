;;;; application.lisp -- the Nordvik Utleie deployment.
;;;;
;;;; Each feature is a mixin class carrying its methods, so the features'
;;;; methods have distinct specializers and run in class precedence order:
;;;; for one operation, :before and :after methods run modules first (in
;;;; dependency order), then the client's.

(in-package #:test-client)

(define-application nordvik (loyalty-feature cleaning-feature workflow-feature
                             order-screen-feature customer-list-feature)
  ;; The manifest: the modules this client enables. The modules they depend
  ;; on (inventory, reviews, staffing, notifications, inbox) come with them;
  ;; invoicing, calendar, warehouse and dashboard stay out.
  (:modules customers catalog orders messaging)
  (:default-initargs :name "Nordvik Utleie")
  (:documentation "Nordvik Utleie AS, the client Tun's own suite tests the client surface on."))

(defparameter *application-class* 'nordvik
  "The application class bin/serve instantiates.")
