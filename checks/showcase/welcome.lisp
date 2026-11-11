;;;; welcome.lisp -- where / and a sign-in lead (spec/ui.md 8, «Home»): the
;;;; graph for everyone, as (:home "/graph") in application.lisp says, and
;;;; /welcome for an admin until one of them presses «Done» there, as a
;;;; setup a new company's admin finishes once.

(in-package #:showcase)

(define-entity welcome (:label "Welcome" :id-prefix "wlc" :table "welcomes")
  ((finished-by :type (string :max 64) :input nil :label "Finished by"
                :description "The admin who finished the welcome.")))

(define-operation welcome-finish ()
    (:entity welcome :kind :create :policy :admin :title "Finish the welcome"
             :description "Marks the welcome as done, so / leads admins to the graph too.")
  (or (select-one 'welcome)
      (insert (make-instance 'welcome :finished-by (actor-name *actor*)))))

(defun welcome-finished-p ()
  "True once an admin has finished the welcome."
  (and (select-one 'welcome) t))

(define-page welcome-page ("welcome" :title "Welcome" :icon :circle-check :policy :admin
                                     :navigation nil)
    (method path form query)
  (declare (ignore path form query))
  (cond ((eq method :post)
         (multiple-value-bind (result code) (web-call "welcome_finish" (jobj))
           (if code
               (values 422 (tr "Welcome") (list (error-alert result)))
               (values 303 "/"))))
        (t
         (values 200 (tr "Welcome")
                 (list (ui:card (:title (tr "Set up the showcase"))
                         `(:p ,(tr "Until an admin finishes this step, / leads admins here."))
                         `(:form (:@ :method "post" :action "/welcome")
                                 ,(ui:form-actions ()
                                    (ui:button (:type "submit" :icon :circle-check)
                                      (tr "Done"))))))))))
