;;;; public-feedback.lisp -- bounded customer feedback through the inbox boundary.
(in-package #:tun.inbox)

(defun feedback-order-for-token (token)
  (find-if (lambda (order)
             (and (constant-time-string= (string-upcase token) (link-token "tilbakemelding" (entity-id order)))
                  (not (customer-erased (order-customer order)))
                  (or (order-end-date order) (order-event-date order))
                  (string>= (date-add-days (or (order-end-date order) (order-event-date order)) 60) (local-today))))
           (select 'order)))
(defun feedback-form ()
  "The card with the customer's feedback form."
  (let ((hint "Ros, ris eller noe vi bør vite til neste gang."))
    (ui:card ()
             `(:form (:@ :method "post")
                     ,(ui:stack (:gap :lg)
                                (ui:textarea (:label "Tilbakemeldingen din" :name "message"
                                                     :rows 6 :required t :hint hint))
                                (ui:form-actions ()
                                  (ui:button (:type "submit" :icon :send) "Send")))))))

(defun public-feedback-page (method parts form session)
  (declare (ignore session))
  (let ((order (and (= (length parts) 1) (with-transaction (:read) (feedback-order-for-token (first parts))))))
    (unless order
      (return-from public-feedback-page (values 404 "Siden finnes ikke" '((:p "Kontroller lenken i e-posten.")))))
    (if (eq method :post)
        (let ((text (jget form "message")))
          (when (or (null text) (blank-p text)) (return-from public-feedback-page (values 422 "Skriv en melding." nil)))
          (when (> (length text) 20000) (fail :invalid-input "Meldingen er for lang"))
          (let ((customer-id (order-customer-id order)))
            (call-customer-action customer-id "tilbakemelding" "henvendelse" nil
              (lambda ()
                (let* ((customer (order-customer order))
                       (item (insert (make-instance 'henvendelse :kind "tilbakemelding" :from-name (customer-name customer)
                                      :from-email (customer-email customer) :subject "Tilbakemelding" :body text
                                      :received-at (now) :request-id *request-id* :match "referanse"))))
                  (thread-request item (entity-id order) :cancel t) (save item))))
            (values 200 "Takk for tilbakemeldingen!" nil)))
        (values 200 "Hva tenker du?" (list (feedback-form))))))
(tun.web:register-public-page "tilbakemelding" #'public-feedback-page)
