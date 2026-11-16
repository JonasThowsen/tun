;;;; application.lisp -- the showcase application: the kernel, the
;;;; customers module, whose list is a generated one (spec/ui.md 8), and its
;;;; own module meetings, a generated list and form that choose a customer
;;;; (modules/meetings), its copy
;;;; written in English and offered in Norwegian too (nb.lisp); its search
;;;; finds the cards and the module's customers (spec/ui.md 6.4).

(in-package #:showcase)

(define-application showcase ()
  (:modules customers meetings)
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

(defun planted-search-slowdown ()
  "How many times the search does its work: 1000 when the test-only switch
TUN_TEST_PLANT is slow-search, a slowdown planted to see ui-search's speed
check fail (spec/tooling.md, \"Speed and time in tests\"), else 1.  On
this machine 250 times measured 114 to 221 ms of the server's processor
time under a made load and stayed under 100 ms on a quiet one, so 1000
times is past the check's 100 ms on either."
  (if (equal (uiop:getenv "TUN_TEST_PLANT") "slow-search") 1000 1))

(defmethod search-records ((app showcase) query actor)
  ;; spec/ui.md 6.4: the cards are found by their title, beside the
  ;; customers the module finds.
  (let ((found nil))
    (dotimes (i (planted-search-slowdown) found)
      (setf found (append (search-entity query 'card
                                         :kind "card" :label (tr "Card") :icon :list-checks
                                         :title #'card-title
                                         :meta (lambda (card) (list (column-title (card-status card))))
                                         :href (lambda (card) (format nil "/items/~a" (entity-id card))))
                          (call-next-method app query actor))))))

(defparameter *application-class* 'showcase
  "The application class the server runs.")
