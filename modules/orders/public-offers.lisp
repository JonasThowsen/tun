;;;; public-offers.lisp -- token-authorized offer pages through the kernel HTML port.
(in-package #:tun.orders)

(defun offer-date-text (date)
  (if date (format nil "~a.~a.~a" (subseq date 8 10) (subseq date 5 7) (subseq date 0 4)) "dato ikke fastsatt"))
(defun offer-money-text (ore)
  (let ((digits (write-to-string (floor ore 100))))
    (format nil "~a,~2,'0d kr"
      (with-output-to-string (out)
        (loop for c across digits for i from 0 do
          (when (and (plusp i) (zerop (mod (- (length digits) i) 3))) (write-char #\Space out))
          (write-char c out))) (mod ore 100))))
(defun offer-not-found () (values 404 "Siden finnes ikke" '((:p "Kontroller lenken i e-posten."))))
(defun offer-conflict ()
  (values 409 "Tilbudet er oppdatert"
    '((:p "Tilbudet har blitt oppdatert eller svart på i en annen fane. Åpne lenken fra den nyeste e-posten for å se gjeldende tilbud."))))
(defun offer-expired-page (sender)
  (values 410 "Tilbudet er utløpt" `((:p ,(format nil "Ta kontakt med ~a dersom dere ønsker et oppdatert tilbud." sender)))))
(defun offer-period (snapshot)
  "The days of the offer's event: one date, or the first and the last."
  (let ((date (jget snapshot "event_date")) (end (jget snapshot "end_date")))
    (if (and (stringp end) (not (equal end date)))
        (format nil "~a–~a" (offer-date-text date) (offer-date-text end))
        (offer-date-text (and (stringp date) date)))))

(defun offer-facts (quote snapshot)
  "When and where, and until when the offer can be answered."
  (let ((expiry (order-quote-expires-at quote))
        (site (jget snapshot "site_address")))
    (ui:summary-list
     (:rows (list (list "Periode" (offer-period snapshot))
                  (list "Sted" (if (stringp site) site ""))
                  (list "Gyldig til" (format nil "~a kl. ~a"
                                             (offer-date-text (local-date-of expiry))
                                             (local-time-of expiry))))))))

(defun offer-lines (snapshot)
  "The products of the offer with their amounts, and the total."
  (let ((rows (map 'list (lambda (line)
                           (list (jget line "name")
                                 (princ-to-string (jget line "quantity"))
                                 (offer-money-text (jget line "line_effective_ore"))))
                   (jget snapshot "lines")))
        (total (offer-money-text (jget snapshot "total_ore"))))
    (ui:table (:columns '("Produkt" ("Antall" :align :end) ("Beløp" :align :end))
                        :rows rows
                        :footer (list "Totalt" nil total)))))

(defun answer-button (response label &rest options)
  "The button that answers the offer with RESPONSE, accept or decline."
  (ui:button* (list* :type "submit" :name "response" :value response options) label))

(defun offer-answer-form (quote)
  "The form that accepts or declines the offer, with the proof of its revision."
  (let ((proof (sign-response-proof (entity-id quote) (order-quote-revision quote))))
    `(:form (:@ :method "post" :action ,(format nil "/tilbud/~a/svar" (entity-id quote)))
            (:input (:@ :type "hidden" :name "proof" :value ,proof))
            ,(ui:cluster ()
                         (answer-button "accept" "Godta tilbudet" :icon :check)
                         (answer-button "decline" "Avslå tilbudet" :variant :outline)))))

(defun offer-content (quote sender)
  (let ((snapshot (order-quote-snapshot quote))
        (who (format nil "Svaret sendes til ~a. En ansatt bekrefter ordren før den blir endelig."
                     sender)))
    (list
     '(:p "Her er en oversikt over det som er foreslått for arrangementet deres.")
     (offer-facts quote snapshot)
     (ui:section (:title "Dette er inkludert")
                 (offer-lines snapshot))
     (ui:section (:title "Vil dere gå videre?" :description who)
                 (offer-answer-form quote)))))

(defun offer-gate (quote &key error)
  "The form that asks for the code in the offer's e-mail, with ERROR after a wrong one."
  (let ((action (format nil "/tilbud/~a/apne" (entity-id quote)))
        (hint "Koden står i e-posten med tilbudet, for eksempel ABCDE-FGHIJ."))
    (list
     (ui:card ()
              `(:form (:@ :method "post" :action ,action :novalidate t)
                      ,(ui:stack (:gap :lg)
                                 (ui:text-input (:label "Kode" :name "code" :required t
                                                        :width 20 :autocomplete "off"
                                                        :error error :hint hint))
                                 (ui:form-actions ()
                                   (ui:button (:type "submit") "Åpne tilbudet"))))))))

(defun public-offer-page (method parts form session)
  (let* ((quote (with-transaction (:read)
                  (let ((q (fetch 'order-quote (first parts))))
                    (when (and q (not (customer-erased (order-customer (find-order (order-quote-order-id q)))))) q))))
         (sender (with-transaction (:read) (setting-value-at-use "avsender.navn" "Tun")))
         (heading (format nil "Tilbud fra ~a" sender))
         (action (second parts)))
    (unless quote (return-from public-offer-page (offer-not-found)))
    (cond
      ((and (eq method :post) (equal action "svar"))
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
                     (values 200 "Takk" `((:p ,(format nil "Tilbudet er akseptert. ~a følger opp og bekrefter ordren." sender))))
                     (values 200 "Svaret er registrert" `((:p ,(format nil "Tilbudet er avslått. Ta kontakt med ~a hvis dere ønsker å avklare noe." sender))))))
             (operation-error () (offer-conflict))))))
      ((quote-expired-p quote) (offer-not-found))
      ((member (order-quote-status quote) '("accepted" "declined") :test #'equal)
       (values 200 "Svar registrert" `((:p ,(if (equal (order-quote-status quote) "accepted") "Tilbudet er allerede akseptert" "Tilbudet er avslått")))))
      ((and (eq method :get) (null action))
       (values 200 heading (offer-gate quote)))
      ((and (eq method :post) (equal action "apne"))
       (let* ((code (jget form "code")) (key (entity-id quote)))
         (cond ((and code (same-code-p (normalise-access-code code) (order-quote-access-code quote)))
                (setf (gethash key session) 0)
                (values 200 heading (with-transaction (:read) (offer-content quote sender))))
               ((>= (incf (gethash key session 0)) 6)
                (values 429 "For mange forsøk" '((:p "Vent litt før du prøver koden igjen."))))
               (t (values 422 heading
                          (offer-gate quote :error "Koden stemmer ikke. Kontroller koden i
e-posten og prøv igjen."))))))
      (t (offer-not-found)))))
(tun.web:register-public-page "tilbud" #'public-offer-page)
