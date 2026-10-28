;;;; public-offers.lisp -- token-authorized offer pages through the kernel HTML port,
;;;; in the tenant's language (README §6.6).
(in-package #:tun.orders)

(declaim (optimize (safety 3) (debug 2)))

(defun offer-date-text (date)
  "DATE of the offer's event as the current language writes it, or that it is not set."
  (if (stringp date) (date-text date) (tr "date not set")))
(defun offer-not-found ()
  (values 404 (tr "The page does not exist") `((:p ,(tr "Check the link in the email.")))))
(defun offer-conflict ()
  (values 409 (tr "The offer has been updated")
          `((:p ,(tr "The offer has been updated or answered in another tab. Open the link in the latest email to see the current offer.")))))
(defun offer-expired-page (sender)
  (values 410 (tr "The offer has expired")
          `((:p ,(tr "Contact ~a if you would like an updated offer." sender)))))
(defun offer-period (snapshot)
  "The days of the offer's event: one date, or the first and the last."
  (let ((date (jget snapshot "event_date")) (end (jget snapshot "end_date")))
    (if (and (stringp end) (not (equal end date)))
        (format nil "~a–~a" (offer-date-text date) (offer-date-text end))
        (offer-date-text date))))

(defun offer-facts (quote snapshot)
  "When and where, and until when the offer can be answered."
  (let ((expiry (order-quote-expires-at quote))
        (site (jget snapshot "site_address")))
    (ui:summary-list
     (:rows (list (list (tr "Period") (offer-period snapshot))
                  (list (tr "Location") (if (stringp site) site ""))
                  (list (tr "Valid until") (instant-text expiry)))))))

(defun offer-lines (snapshot)
  "The products of the offer with their amounts, and the total."
  (let ((rows (map 'list (lambda (line)
                           (list (jget line "name")
                                 (number-text (jget line "quantity"))
                                 (money-text (jget line "line_effective_minor"))))
                   (jget snapshot "lines")))
        (total (money-text (jget snapshot "total_minor"))))
    (ui:table (:columns (list (tr "Product") (list (tr "Quantity") :align :end)
                              (list (tr "Amount") :align :end))
                        :rows rows
                        :footer (list (tr "Total") nil total)))))

(defun answer-button (response label &rest options)
  "The button that answers the offer with RESPONSE, accept or decline."
  (ui:button* (list* :type "submit" :name "response" :value response options) label))

(defun offer-answer-form (quote)
  "The form that accepts or declines the offer, with the proof of its revision."
  (let ((proof (sign-response-proof (entity-id quote) (order-quote-revision quote))))
    `(:form (:@ :method "post" :action ,(format nil "/offer/~a/respond" (entity-id quote)))
            (:input (:@ :type "hidden" :name "proof" :value ,proof))
            ,(ui:cluster ()
                         (answer-button "accept" (tr "Accept the offer") :icon :check)
                         (answer-button "decline" (tr "Decline the offer") :variant :outline)))))

(defun offer-content (quote sender)
  (let ((snapshot (order-quote-snapshot quote))
        (who (tr "Your answer goes to ~a. A member of staff confirms the order before it is final."
                 sender)))
    (list
     `(:p ,(tr "Here is an overview of what is proposed for your event."))
     (offer-facts quote snapshot)
     (ui:section (:title (tr "This is included"))
                 (offer-lines snapshot))
     (ui:section (:title (tr "Would you like to go ahead?") :description who)
                 (offer-answer-form quote)))))

(defun offer-gate (quote &key error)
  "The form that asks for the code in the offer's e-mail, with ERROR after a wrong one."
  (let ((action (format nil "/offer/~a/open" (entity-id quote)))
        (hint (tr "The code is in the email with the offer, for example ABCDE-FGHIJ.")))
    (list
     (ui:card ()
              `(:form (:@ :method "post" :action ,action :novalidate t)
                      ,(ui:stack (:gap :lg)
                                 (ui:text-input (:label (tr "Code") :name "code" :required t
                                                        :width 20 :autocomplete "off"
                                                        :error error :hint hint))
                                 (ui:form-actions ()
                                   (ui:button (:type "submit") (tr "Open the offer")))))))))

(defun public-offer-page (method parts form session)
  (let* ((quote (with-transaction (:read)
                  (let ((q (fetch 'order-quote (first parts))))
                    (when (and q (not (customer-erased (order-customer (find-order (order-quote-order-id q)))))) q))))
         (sender (with-transaction (:read) (setting-value-at-use "sender.name" "Tun")))
         (heading (tr "Offer from ~a" sender))
         (action (second parts)))
    (unless quote (return-from public-offer-page (offer-not-found)))
    (cond
      ((and (eq method :post) (equal action "respond"))
       (let ((proof (jget form "proof")) (response (jget form "response")))
         (unless (and proof response) (return-from public-offer-page (offer-not-found)))
         (multiple-value-bind (revision expiry) (with-transaction (:read) (verify-response-proof proof (entity-id quote)))
           (unless revision (return-from public-offer-page (offer-not-found)))
           (when (or (<= expiry (now)) (quote-expired-p quote)) (return-from public-offer-page (offer-expired-page sender)))
           (unless (and (= revision (order-quote-revision quote)) (equal (order-quote-status quote) "awaiting_response")
                        (member response '("accept" "decline") :test #'equal))
             (return-from public-offer-page (offer-conflict)))
           (handler-case
               (progn
                 (call-tool "quotes_respond" (jobj "quote_id" (entity-id quote) "revision" revision
                                                  "access_code" (order-quote-access-code quote) "response" response)
                            :actor (make-actor :customer (entity-id quote)))
                 (if (equal response "accept")
                     (values 200 (tr "Thank you")
                             `((:p ,(tr "The offer is accepted. ~a will follow up and confirm the order." sender))))
                     (values 200 (tr "Your answer is registered")
                             `((:p ,(tr "The offer is declined. Contact ~a if there is anything you would like to clear up." sender))))))
             (operation-error () (offer-conflict))))))
      ((quote-expired-p quote) (offer-not-found))
      ((member (order-quote-status quote) '("accepted" "declined") :test #'equal)
       (values 200 (tr "Answer registered")
               `((:p ,(if (equal (order-quote-status quote) "accepted")
                          (tr "The offer is already accepted")
                          (tr "The offer has been declined"))))))
      ((and (eq method :get) (null action))
       (values 200 heading (offer-gate quote)))
      ((and (eq method :post) (equal action "open"))
       (let* ((code (jget form "code")) (key (entity-id quote)))
         (cond ((and code (same-code-p (normalise-access-code code) (order-quote-access-code quote)))
                (setf (gethash key session) 0)
                (values 200 heading (with-transaction (:read) (offer-content quote sender))))
               ((>= (incf (gethash key session 0)) 6)
                (values 429 (tr "Too many attempts") `((:p ,(tr "Wait a little before you try the code again.")))))
               (t (values 422 heading
                          (offer-gate quote :error (tr "The code is not right. Check the code in the email and try again.")))))))
      (t (offer-not-found)))))
(tun.web:register-public-page "offer" #'public-offer-page)
