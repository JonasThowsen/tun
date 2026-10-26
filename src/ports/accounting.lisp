;;;; ports/accounting.lisp -- the accounting port, owned by core.
;;;;
;;;; Core speaks only this contract: an invoice intent in, an external
;;;; reference out, idempotent on the intent id.  Adapters (the fake here, a
;;;; Fiken adapter later) implement it; no vendor vocabulary or credentials
;;;; cross this boundary.  A real adapter would hold no secrets itself and
;;;; call a credential gateway.

(defpackage #:tun.accounting
  (:use #:cl)
  (:export #:invoice-intent #:make-invoice-intent #:intent-id #:intent-invoice-id #:intent-customer
           #:intent-lines #:intent-total-ore
           #:accounting-adapter #:create-invoice #:lookup-invoice #:adapter-name #:adapter-status))

(in-package #:tun.accounting)

(declaim (optimize (safety 3) (debug 2)))

(defstruct (invoice-intent (:constructor make-invoice-intent (&key id invoice-id customer lines total-ore))
                           (:conc-name intent-))
  "What core asks the accounting system to book. ID is stable per invoice, so a
retried send reuses it and the provider can de-duplicate."
  (id "" :type string :read-only t)
  (invoice-id "" :type string :read-only t)
  (customer nil :read-only t)              ; JSON object snapshot
  (lines nil :type list :read-only t)      ; JSON objects
  (total-ore 0 :type integer :read-only t))

(defclass accounting-adapter () ()
  (:documentation "Base class of accounting adapters."))

(defgeneric create-invoice (adapter intent)
  (:documentation "Book INTENT in the accounting system; return its external reference
(a string). Must be idempotent on (INTENT-ID INTENT)."))

(defgeneric lookup-invoice (adapter intent-id)
  (:documentation "The external reference the accounting system holds for INTENT-ID,
or NIL if it never received it.  Used to reconcile intents whose outcome was
not recorded (core.md §7.3) before any retry."))

(defgeneric adapter-name (adapter)
  (:documentation "Short name reported by accounting_status."))

(defgeneric adapter-status (adapter)
  (:documentation "List of plists (:invoice-id :external-ref :calls) describing what the adapter has seen."))
