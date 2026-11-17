;;;; visits.lisp -- /visit-days, a group of checkboxes that saves every box
;;;; ticked (spec/ui.md 8, «A client's pages» 2): the form posts the name days
;;;; once for each, and the page reads them with query-values.  Out of the
;;;; menu.

(in-package #:showcase)

(defparameter +visit-days+ '("mon" "tue" "wed" "thu" "fri")
  "The days a visit can be made, as they are stored and posted.")

(define-entity visit-plan (:label "Visit days" :id-prefix "vst" :table "visit_plans")
  ((days :type (list-of (enum "mon" "tue" "wed" "thu" "fri")) :initform '() :label "Days"
         :description "The weekdays a visit can be made.")))

(define-operation visit-days-set
    ((days :type (list-of (enum "mon" "tue" "wed" "thu" "fri")) :label "Days"
           :description "The weekdays a visit can be made; none for none."))
    (:entity visit-plan :kind :create :policy :employee :title "Set the visit days"
             :description "Keeps the weekdays a visit can be made, in place of those kept.")
  (let ((plan (select-one 'visit-plan)))
    (cond (plan
           (setf (visit-plan-days plan) days)
           (save plan))
          (t (insert (make-instance 'visit-plan :days days))))))

(define-operation visit-days-get ()
    (:entity visit-plan :kind :read :policy :employee :title "Visit days"
             :description "The weekdays a visit can be made, as kept.")
  (let ((plan (select-one 'visit-plan)))
    (jobj "days" (jarr (and plan (visit-plan-days plan))))))

(defun visit-day-name (day)
  "DAY, a value of +VISIT-DAYS+, as the current language names it."
  ;; A cond: the days are a list's elements, no field ecase-of could name.
  (cond ((equal day "mon") (tr "Monday"))
        ((equal day "tue") (tr "Tuesday"))
        ((equal day "wed") (tr "Wednesday"))
        ((equal day "thu") (tr "Thursday"))
        ((equal day "fri") (tr "Friday"))
        (t day)))

(defun visit-days-form (ticked)
  "The form of the five days, those in TICKED ticked."
  `(:form (:@ :method "post" :action "/visit-days")
          ,(ui:stack (:gap :lg)
             (ui:checkboxes (:legend (tr "Which days can we come?") :name "days" :optional t
                             :hint (tr "Tick every day that suits.")
                             :choices (mapcar (lambda (day) (list day (visit-day-name day)))
                                              +visit-days+)
                             :selected ticked))
             (ui:form-actions () (ui:button (:type "submit" :icon :save) (tr "Save"))))))

(defun saved-days (days)
  "What is kept, DAYS, as a line marked with their values."
  `(:p (:@ :data-saved-days ,(format nil "~{~a~^ ~}" days))
       ,(if days
            (tr "Saved: ~a." (format nil "~{~a~^, ~}" (mapcar #'visit-day-name days)))
            (tr "No days are saved."))))

(define-page visit-days-page ("visit-days" :title "Visit days" :icon :calendar-days
                                           :policy :employee :navigation nil)
    (method path form query)
  (declare (ignore query))
  (cond (path (values 404 (tr "Visit days") (list (ui:alert (:variant :warning
                                                             :title (tr "Page not found"))))))
        ((eq method :post)
         (let ((ticked (query-values form "days")))
           (multiple-value-bind (result code) (web-call "visit_days_set"
                                                        (jobj "days" (jarr ticked)))
             (if code
                 (values 422 (tr "Visit days") (list (error-alert result)
                                                     (ui:card () (visit-days-form ticked))))
                 (values 303 "/visit-days")))))
        (t
         (let ((days (coerce (jget (web-call "visit_days_get" (jobj)) "days") 'list)))
           (values 200 (tr "Visit days")
                   (list (ui:card () (visit-days-form days) (saved-days days))))))))
