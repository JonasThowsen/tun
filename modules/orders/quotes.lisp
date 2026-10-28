;;;; modules/orders/quotes.lisp -- quotes as objects with revisions, expiry
;;;; and customer responses (README §6).
;;;;
;;;; One quote per order, a stable id and access code across re-issues.  The
;;;; snapshot is frozen at send time; "stale" and "expired" are derived.

(in-package #:tun.orders)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +quote-validity-days+ 14)
(defparameter +access-code-alphabet+ "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

(defun quote-for-order (order-id)
  (select-one 'order-quote :where `(:= "order_id" ,order-id)))

(defun quote-expired-p (quote)
  (or (string= (order-quote-status quote) "expired")
      (and (string= (order-quote-status quote) "awaiting_response")
           (<= (order-quote-expires-at quote) (now)))))

(defun quote-status (quote)
  "The stored status, or expired: awaiting a response past expires_at."
  (if (quote-expired-p quote) "expired" (order-quote-status quote)))

(defun new-access-code ()
  "10 characters from [A-Z2-7], random."
  (let ((bytes (random-bytes 10)) (code (make-string 10)))
    (dotimes (i 10 code)
      (setf (char code i) (char +access-code-alphabet+ (logand (aref bytes i) 31))))))

(defun normalise-access-code (code)
  (remove-if-not (lambda (c) (find c +access-code-alphabet+)) (string-upcase code)))

(defun same-code-p (given stored)
  "GIVEN equals STORED, compared over every character (no early exit that
would tell by its timing how much of a guess was right)."
  (let ((difference (logxor (length given) (length stored))))
    (dotimes (i (min (length given) (length stored)))
      (setf difference (logior difference (logxor (char-code (char given i)) (char-code (char stored i))))))
    (zerop difference)))

;;; Wrong codes are throttled per quote: after +ACCESS-CODE-ATTEMPTS+ within
;;; +ACCESS-CODE-WINDOW+ seconds every attempt (even the right code) is
;;; refused until the window has passed.  Kept in memory: a restart forgets
;;; (README §6.3).
(defparameter +access-code-attempts+ 5)
(defparameter +access-code-window+ 900)
(defvar *wrong-codes* (make-hash-table :test 'equal) "quote id -> (count . first attempt)")
(defvar *wrong-codes-lock* (sb-thread:make-mutex :name "quote access codes"))

(defun access-code-throttled-p (quote-id)
  (sb-thread:with-mutex (*wrong-codes-lock*)
    (let ((entry (gethash quote-id *wrong-codes*)))
      (cond ((null entry) nil)
            ((>= (- (now) (cdr entry)) +access-code-window+) (remhash quote-id *wrong-codes*) nil)
            (t (>= (car entry) +access-code-attempts+))))))

(defun note-wrong-code (quote-id)
  (sb-thread:with-mutex (*wrong-codes-lock*)
    (let ((entry (gethash quote-id *wrong-codes*)))
      (if entry
          (incf (car entry))
          (setf (gethash quote-id *wrong-codes*) (cons 1 (now)))))))

(defun snapshot-lines (order)
  (jarr (mapcar (lambda (line)
                  (jobj "name" (product-name (find-product (order-line-product-id line)))
                        "quantity" (order-line-quantity line)
                        "line_effective_minor" (or (order-line-line-effective-minor line) (order-line-line-total-minor line))))
                (order-lines order))))

(defun quote-snapshot (order &optional (customer (order-customer order)))
  "What the customer is offered: the snapshot a send freezes."
  (jobj "customer_name" (customer-name customer)
        "customer_email" (customer-email customer)
        "event_date" (or (order-event-date order) :null)
        "end_date" (or (order-end-date order) :null)
        "site_address" (or (order-delivery-address order) :null)
        "total_minor" (order-total-minor order)
        "lines" (snapshot-lines order)))

(defun quote-basis (order)
  "What the offer rests on: the total, both dates, the site address and every
field of every line (servings and the client's fields included), canonical."
  (to-json-string (jobj "total_minor" (order-total-minor order)
                        "event_date" (or (order-event-date order) :null)
                        "end_date" (or (order-end-date order) :null)
                        "site_address" (or (order-delivery-address order) :null)
                        "lines" (jarr (mapcar #'entity->storage-json (order-lines order))))
                  :canonical t))

(defun quote-stale-p (quote &optional (order (find-order (order-quote-order-id quote))))
  "True when the order's total, dates, site address or lines differ from their
values when the quote was offered (undoing a change makes it fresh again)."
  (let ((basis (order-quote-basis quote)))
    (and (stringp basis) (string/= basis (quote-basis order)))))

(defun issue-quote (order customer)
  "Create the order's quote (revision 1) or re-issue it (revision + 1): status
back to awaiting_response, a new snapshot, valid 14 days, the same code."
  (let ((quote (quote-for-order (entity-id order)))
        (now (now)))
    (if quote
        (progn
          (setf (order-quote-revision quote) (1+ (order-quote-revision quote))
                (order-quote-status quote) "awaiting_response"
                (order-quote-responded-at quote) nil
                (order-quote-offered-at quote) now
                (order-quote-expires-at quote) (+ now (* (setting-value-at-use "quotes.valid_days" +quote-validity-days+) 86400))
                (order-quote-snapshot quote) (quote-snapshot order customer)
                (order-quote-basis quote) (quote-basis order))
          (save quote))
        (insert (make-instance 'order-quote :order-id (entity-id order) :revision 1
                                            :status "awaiting_response" :offered-at now
                                            :expires-at (+ now (* (setting-value-at-use "quotes.valid_days" +quote-validity-days+) 86400))
                                            :snapshot (quote-snapshot order customer)
                                            :basis (quote-basis order)
                                            :access-code (new-access-code))))))

(defun quote->json (quote)
  "The quote as the caller may see it: the access code only for an admin."
  (let ((json (entity->json quote)))
    (remhash "basis" json)
    (setf (gethash "status" json) (quote-status quote)
          (gethash "stale" json) (json-bool (quote-stale-p quote))
          (gethash "access_code" json) (if (eq :admin (actor-role *actor*)) (order-quote-access-code quote) :null))
    json))

(define-operation quotes-get ((order-id :type (id order) :required t :label "Order ID"))
    (:entity order-quote :kind :read :title "Get the quote"
     :description "The order's quote: revision, status (awaiting_response, accepted, declined, expired), when it was sent, when it expires, the answer, the content that was sent and whether the order has changed since (stale). The access code is shown to an admin only.")
  (find-order order-id)
  (let ((quote (quote-for-order order-id)))
    (unless quote (fail :not-found "Order ~a has no quote" order-id))
    (quote->json quote)))

(define-operation quotes-preview ((order-id :type (id order) :required t :label "Order ID"))
    (:entity order-quote :kind :read :title "Preview the quote"
     :description "The content the next send of the quote would freeze, without sending anything.")
  (jobj "order_id" order-id "snapshot" (quote-snapshot (find-order order-id))))

(define-operation quotes-respond ((quote-id :type (id order-quote) :required t :label "Quote ID")
                                  (revision :type integer :required t :label "The quote's revision")
                                  (access-code :type (string :min 1 :max 100) :required t :label "Access code")
                                  (response :type (enum "accept" "decline") :required t :label "Answer"))
    (:entity order-quote :kind :transition :policy :viewer :viewer-mutation t :title "Answer the quote"
     :description "The customer's answer to the quote (accept or decline), authorised by the access code. Accepting makes the order accepted; declining leaves it quote_sent. Applies only to the quote's current revision, before it expires.")
  (let* ((quote (fetch! 'order-quote quote-id))
         (order (find-order (order-quote-order-id quote))))
    (when (access-code-throttled-p quote-id)
      (reject-as (format nil "customer:~a" quote-id) :forbidden
                 "Too many wrong access codes for the quote; try again in ~d minutes" (floor +access-code-window+ 60)))
    (unless (same-code-p (normalise-access-code access-code) (order-quote-access-code quote))
      (note-wrong-code quote-id)
      (reject-as (format nil "customer:~a" quote-id) :forbidden "Wrong access code for the quote"))
    (check-order-not-locked order)
    (unless (= revision (order-quote-revision quote))
      (fail :conflict "the quote has changed; reload the page"))
    (when (quote-expired-p quote)
      (fail :conflict "the quote has expired; send a new quote"))
    (unless (string= (order-quote-status quote) "awaiting_response")
      (fail :invalid-transition "The quote is already answered (~a)"
            (label "quote" "status" (order-quote-status quote))))
    (unless (string= (order-status order) "quote_sent")
      (fail :invalid-transition "The order is ~a and is not waiting for an answer"
            (status-text (order-status order))))
    (audit-as :actor (format nil "customer:~a" quote-id))
    (if (string= response "accept")
        (accept-order order)
        (setf (order-quote-status quote) "declined"
              (order-quote-responded-at quote) (now)))
    (unless (string= response "accept") (save quote))
    (save order)
    (quote->json (quote-for-order (entity-id order)))))

(defun order-quote-summary (order)
  "Public quote state for client automation; no private quote accessors needed."
  (let ((quote (quote-for-order (entity-id order)))) (and quote (quote->json quote))))

(defgeneric quote-expired (application quote)
  (:method-combination traced-protocol)
  (:documentation "Publish side effects of a stored quote expiry in its transaction.")
  (:method ((application orders-module) quote) (declare (ignore quote)) nil))
(register-extension-protocol 'quote-expired "after" :point "quote_expired"
  :description "Dependent modules publish an expiry notification atomically.")

(define-workflow expire-quote (:kind "quote_expiry" :label "Quote expires") (wf)
  (let ((quote (fetch 'order-quote (tun.workflows:workflow-subject-id wf))))
    (if (and quote (equal (order-quote-status quote) "awaiting_response")
             (equal (tun.workflows:workflow-key wf) (format nil "~a:~d" (entity-id quote) (order-quote-revision quote))))
        (progn (setf (order-quote-status quote) "expired") (save quote)
               (tun.workflows:cancel-workflows (order-quote-order-id quote) :kinds '("quote_reminder"))
               (quote-expired *application* quote))
        (tun.workflows:note-workflow-run (tr "not needed: the quote is not open")))))
(defun cancel-quote-expiry (order-id)
  (let ((quote (quote-for-order order-id)))
    (when quote (tun.workflows:cancel-subject-workflows (entity-id quote) :kinds '("quote_expiry")))))
(defmethod orders-send-quote :after ((app orders-module) input)
  (declare (ignore input))
  (let ((quote (quote-for-order (entity-id (operation-result)))))
    (cancel-quote-expiry (order-quote-order-id quote))
    (tun.workflows:schedule-workflow "quote_expiry" :subject-id (entity-id quote)
      :key (format nil "~a:~d" (entity-id quote) (order-quote-revision quote)) :due-at (order-quote-expires-at quote))))
(defmethod orders-accept :after ((app orders-module) input)
  (declare (ignore input)) (cancel-quote-expiry (entity-id (operation-result))))
(defmethod quotes-respond :after ((app orders-module) input)
  (declare (ignore input)) (cancel-quote-expiry (jget (operation-result) "order_id")))
(defmethod orders-cancel :after ((app orders-module) input)
  (declare (ignore input)) (cancel-quote-expiry (entity-id (operation-result))))
(defmethod orders-reactivate :after ((app orders-module) input)
  (declare (ignore input)) (cancel-quote-expiry (entity-id (operation-result))))

(defun redact-quote-receipts (quote)
  "Erased quote receipts retain the public shape and no customer access credential."
  (let ((projection (quote->json quote)))
    (setf (gethash "access_code" projection) :null)
    (redact-entity-receipts quote projection)))

(defmethod customer-erasing ((application orders-module) customer)
  (call-next-method)
  (tun.workflows:cancel-customer-workflows (entity-id customer) :kinds '("next_year"))
  (let* ((orders (select 'order :where `(:= "customer_id" ,(entity-id customer))))
         (open (count-if-not #'order-final-p orders)))
    (cond ((= open 1)
           (fail :conflict "the customer cannot be erased while they have an open order"))
          ((plusp open)
           (fail :conflict "the customer cannot be erased while they have ~d open orders" open)))
    (dolist (order orders)
      (let ((quote (quote-for-order (entity-id order))))
        (when quote
          (setf (gethash "customer_name" (order-quote-snapshot quote)) (tr "[erased]")
                (gethash "customer_email" (order-quote-snapshot quote)) (tr "[erased]"))
          (save quote) (redact-quote-receipts quote))))))

(defun mask-quote-credentials (json order-id)
  "Mask known quote codes in every staff projection, including unthreaded forwarded messages."
  (declare (ignore order-id))
  (unless (and *actor* (eq (actor-role *actor*) :admin))
    (let ((candidates (make-hash-table :test 'equal)) (codes nil))
      (labels ((collect-codes (value)
                 (cond ((stringp value)
                        (loop with cursor = 0
                              do (multiple-value-bind (start end)
                                     (cl-ppcre:scan "(?i)[A-Z2-7]{5}-?[A-Z2-7]{5}" value :start cursor)
                                   (unless start (return))
                                   (setf (gethash (string-upcase (remove #\- (subseq value start end))) candidates) t
                                         cursor (1+ start)))))
                       ((hash-table-p value) (maphash (lambda (key nested) (declare (ignore key)) (collect-codes nested)) value))
                       ((and (vectorp value) (not (stringp value))) (map nil #'collect-codes value))))
               (mask (value)
                 (cond ((stringp value)
                        (dolist (code codes value)
                          (setf value (cl-ppcre:regex-replace-all
                                        (format nil "(?i)(~a|~a-~a)" code (subseq code 0 5) (subseq code 5))
                                        value "•••••-•••••"))))
                       ((hash-table-p value) (maphash (lambda (key nested) (setf (gethash key value) (mask nested))) value) value)
                       ((vectorp value) (map 'vector #'mask value)) (t value))))
        (collect-codes json)
        (let ((keys (loop for code being the hash-keys of candidates collect code)))
          ;; Bound SQL parameters even for deliberately dense quoted text.
          (loop while keys for count = (min 200 (length keys))
                do (dolist (quote (select 'order-quote :where `(:in "access_code" ,(subseq keys 0 count))))
                     (push (order-quote-access-code quote) codes))
                   (setf keys (nthcdr count keys))))
        (mask json))))
  json)

(defun repair-quote-receipts ()
  "Redact the quote receipts of erased customers from their already anonymised
stored snapshots, so receipts stored before that redaction are repaired (README §6.6)."
  (with-transaction (:write)
    (dolist (customer (select 'customer :where '(:= "erased" t)))
      (dolist (order (select 'order :where `(:= "customer_id" ,(entity-id customer))))
        (let ((quote (quote-for-order (entity-id order))))
          (when quote (redact-quote-receipts quote)))))))
