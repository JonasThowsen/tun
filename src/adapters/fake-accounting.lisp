;;;; adapters/fake-accounting.lisp -- an accounting adapter that records
;;;; calls instead of talking to a provider.  It counts every CREATE-INVOICE
;;;; call (so a duplicate send would show calls = 2) while still answering
;;;; idempotently with the first reference for a repeated intent id.

(defpackage #:tun.accounting.fake
  (:use #:cl #:tun.core #:tun.accounting)
  (:export #:fake-accounting #:fake-latency-ms))

(in-package #:tun.accounting.fake)

(declaim (optimize (safety 3) (debug 2)))

(define-entity fake-accounting-call (:json-name "fake_accounting_call" :label "Regnskapskall (fake)"
                                     :id-prefix "fac" :table "fake_accounting_calls" :internal t
                                     :indexes (("intent_id") ("invoice_id")))
  ((intent-id :type (string :max 200) :input nil)
   (invoice-id :type id :input nil)
   (external-ref :type (string :max 200) :input nil)
   (total-ore :type integer :input nil)
   (at :type timestamp :input nil)))

(defun environment-latency-ms ()
  (let ((value (sb-ext:posix-getenv "FAKE_ACCOUNTING_LATENCY_MS")))
    (or (and value (ignore-errors (max 0 (parse-integer value)))) 0)))

(defclass fake-accounting (accounting-adapter)
  ((latency-ms :initarg :latency-ms :initform (environment-latency-ms) :accessor fake-latency-ms
               :documentation "A stalled provider: --fake-accounting-latency-ms, else
FAKE_ACCOUNTING_LATENCY_MS from the environment, else 0.")))

(defmethod adapter-name ((adapter fake-accounting)) "fake")

(defmethod create-invoice ((adapter fake-accounting) intent)
  ;; The simulated provider delay comes first, outside any transaction.
  (when (plusp (fake-latency-ms adapter))
    (sleep-with-deadline (fake-latency-ms adapter)))
  ;; Each call is logged in its own transaction, like a provider's own
  ;; records: a later rollback of the caller's work does not erase it.
  (with-transaction (:write)
    (let* ((previous (select 'fake-accounting-call :where `(:= "intent_id" ,(intent-id intent))))
           (ref (if previous
                    (fake-accounting-call-external-ref (first previous))
                    (format nil "FAKE-~a" (subseq (sha256-hex (intent-id intent)) 0 12)))))
      (insert (make-instance 'fake-accounting-call :intent-id (intent-id intent)
                                                   :invoice-id (intent-invoice-id intent)
                                                   :external-ref ref
                                                   :total-ore (intent-total-ore intent)
                                                   :at (now)))
      ref)))

(defmethod lookup-invoice ((adapter fake-accounting) intent-id)
  (with-transaction (:read)
    (let ((call (select-one 'fake-accounting-call :where `(:= "intent_id" ,intent-id))))
      (and call (fake-accounting-call-external-ref call)))))

(defmethod adapter-status ((adapter fake-accounting))
  (let ((by-invoice '()))
    (dolist (call (select 'fake-accounting-call))
      (let ((cell (assoc (fake-accounting-call-invoice-id call) by-invoice :test #'string=)))
        (if cell
            (incf (getf (cdr cell) :calls))
            (push (list (fake-accounting-call-invoice-id call)
                        :external-ref (fake-accounting-call-external-ref call) :calls 1)
                  by-invoice))))
    (mapcar (lambda (cell) (list* :invoice-id (car cell) (cdr cell))) (nreverse by-invoice))))
