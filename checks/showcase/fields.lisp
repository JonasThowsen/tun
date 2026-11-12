;;;; fields.lisp -- /fields, a form of the date, time and money fields that
;;;; posts and shows what the server read from each (spec/ui.md 6,
;;;; date-input, time-input, money-input; spec/i18n.md 5.4, 6.2).

(in-package #:showcase)

(defun fields-form (&key values errors)
  "The form of the three fields, VALUES the posted form and ERRORS the
fields' messages by name."
  (flet ((value (name) (and values (jget values name)))
         (error-of (name) (cdr (assoc name errors :test #'string=))))
    `(:form (:@ :method "post" :action "/fields" :novalidate t)
            ,(ui:stack (:gap :lg)
               (ui:date-input (:label (tr "Delivery date") :name "date" :id "field-date"
                               :quick t :value (value "date") :error (error-of "date")))
               (ui:date-input (:label (tr "Return date") :name "return" :id "field-return"
                               :optional t :min "2026-11-01" :max "2026-12-31"
                               :value (value "return") :error (error-of "return")))
               (ui:time-input (:label (tr "Pick-up time") :name "time" :id "field-time"
                               :optional t :value (value "time") :error (error-of "time")))
               (ui:money-input (:label (tr "Price") :name "price" :id "field-price"
                                :optional t :value (value "price") :error (error-of "price")))
               (ui:cluster () (ui:button (:type "submit") (tr "Send")))))))

(defun read-fields (form)
  "What the server reads from FORM: values a list of (NAME . VALUE) read and
a list of (NAME . MESSAGE) refused."
  (let ((read '()) (refused '()))
    (loop for (name reader) in (list (list "date" #'read-date-text)
                                     (list "return" #'read-date-text)
                                     (list "time" #'read-time-text)
                                     (list "price" #'read-money-text))
          for text = (jget form name)
          do (multiple-value-bind (value problem)
                 (and (stringp text) (plusp (length (string-trim " " text)))
                      (funcall reader text))
               (cond (value (push (cons name value) read))
                     (problem (push (cons name (princ-to-string problem)) refused)))))
    (unless (or (assoc "date" read :test #'string=) (assoc "date" refused :test #'string=))
      (push (cons "date" (tr "Enter a delivery date")) refused))
    (values (nreverse read) (nreverse refused))))

(defun read-list (read)
  "What the server read, each value in an element marked with its name."
  `(:dl (:@ :class "showcase-read")
        ,@(loop for (name . value) in read
                append `((:dt ,name) (:dd (:output (:@ :data-read ,name) ,(princ-to-string value)))))))

(define-page fields-page ("fields" :title "Fields" :icon :calendar :policy :employee)
    (method path form query)
  (declare (ignore query))
  (cond (path (values 404 (tr "Fields") (list (ui:alert (:variant :warning
                                                         :title (tr "Page not found"))))))
        ((eq method :post)
         (multiple-value-bind (read refused) (read-fields form)
           (if refused
               (values 422 (tr "Fields") (list (fields-form :values form :errors refused)))
               (values 200 (tr "Fields")
                       (list (ui:card (:title (tr "What the server read"))
                               (read-list read))
                             (fields-form :values form))))))
        (t (values 200 (tr "Fields") (list (fields-form))))))
