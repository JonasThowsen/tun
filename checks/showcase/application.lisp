;;;; application.lisp -- the showcase application: the kernel and the
;;;; customers module, whose list is a generated one (spec/ui.md 8), its copy
;;;; written in English and offered in Norwegian too (nb.lisp); its search
;;;; finds the cards and the module's customers (spec/ui.md 6.4).

(in-package #:showcase)

(define-application showcase ()
  (:modules customers)
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

(defmethod search-records ((app showcase) query actor)
  ;; spec/ui.md 6.4: the cards are found by their title, beside the
  ;; customers the module finds.
  (declare (ignore actor))
  (append (search-entity query 'card
                         :kind "card" :label (tr "Card") :icon :list-checks
                         :title #'card-title
                         :meta (lambda (card) (list (column-title (card-status card))))
                         :href (lambda (card) (format nil "/items/~a" (entity-id card))))
          (call-next-method)))

(defparameter *application-class* 'showcase
  "The application class the server runs.")
