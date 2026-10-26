;;;; workflows.lisp -- a reminder 48 hours after a quote is sent, while the
;;;; quote is still open: a message template, a workflow, and :after methods
;;;; on the orders module's operations that plan and cancel it.

(in-package #:test-client)

(define-message-template reminder-message
    (:template "påminnelse" :label "Påminnelse om tilbud" :manual t
     :subject "Vi har fortsatt et tilbud til deg"
     :text "Hei {{kunde.navn}},

Vi har fortsatt et tilbud til deg for {{ordre.periode}}. Se og svar på det her:
{{tilbud.lenke}}

Med vennlig hilsen
{{avsender.navn}}")
    (&key order customer))

(define-workflow quote-reminder (:kind "tilbud_påminnelse" :label "Påminnelse om tilbud"
                                 :templates ("påminnelse"))
    (wf)
  (let ((order (find-order (workflow-order-id wf))))
    (if (equal (order-status order) "tilbud_sendt")
        (send-message "påminnelse" :order order :customer (order-customer order))
        (note-workflow-run "ikke nødvendig: tilbudet er ikke åpent"))))

(defparameter +reminder-delay-hours+ 48
  "How long after a quote is sent its reminder is due.")

(defclass workflow-feature () ()
  (:documentation "The quote reminder, planned and cancelled by :after methods."))

;;; A quote sent again plans its reminder afresh, from the newest send.
(defmethod orders-send-quote :after ((app workflow-feature) input)
  (declare (ignore input))
  (let ((order (operation-result)))
    (cancel-workflows (entity-id order) :kinds '("tilbud_påminnelse"))
    (schedule-workflow "tilbud_påminnelse" :order order :key (entity-id order)
                                           :due-at (+ (now) (* +reminder-delay-hours+ 3600)))))

(defmethod orders-accept :after ((app workflow-feature) input)
  (declare (ignore input))
  (cancel-workflows (entity-id (operation-result)) :kinds '("tilbud_påminnelse")))
