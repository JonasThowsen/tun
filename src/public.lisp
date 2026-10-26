;;;; public.lisp -- the TUN package: the documented public interface for
;;;; client projects.  A client package uses only these symbols (enforced by
;;;; the client test-suite); everything else in the tun.* packages is
;;;; internal.  After loading, the core packages are locked, so a client
;;;; cannot redefine core functions or classes either.

;;; SAVE and INSERT as clients see them.  Core's own SAVE and INSERT can
;;; write anything; through the public interface an extension may store
;;; changes to its *own* fields of a core record (a client's field on a
;;; product) and create records of its *own* entities, but never change a
;;; core-owned field or create a core record directly -- that is what
;;; operations, with their checks, are for.

(defpackage #:tun.guarded
  (:use #:cl)
  (:export #:save #:insert))

(in-package #:tun.guarded)

(defun core-record-p (entity)
  (eq :core (tun.core:entity-source (class-of entity))))

(defun check-own-table (entity)
  "Refuse a record whose class is not the registered owner of its table
(an entity defined over another's table)."
  (let* ((class (class-of entity))
         (owner (and (tun.core:entity-table class) (tun.core:table-owner (tun.core:entity-table class)))))
    (unless (eq owner (class-name class))
      (tun.core:extension-error "~a records cannot be stored: table ~a belongs to ~a"
                                (class-name class) (tun.core:entity-table class) (or owner "no registered entity")))))

(defun insert (entity)
  "Store a new record of an extension-defined entity."
  (check-own-table entity)
  (when (core-record-p entity)
    (tun.core:extension-error "Extensions cannot create ~a records directly; call the operation"
                              (tun.core:entity-json-name (class-of entity))))
  (tun.core:insert entity))

(defun save (entity)
  "Store changes to an existing record; for a core record, only to fields the
extension added (core fields must be unchanged)."
  (check-own-table entity)
  (when (core-record-p entity)
    (let* ((class (class-of entity))
           (stored (tun.core:fetch (class-name class) (tun.core:entity-id entity))))
      (unless stored
        (tun.core:extension-error "No stored ~a with id ~a" (tun.core:entity-json-name class) (tun.core:entity-id entity)))
      (dolist (field (tun.core:entity-stored-fields class))
        (when (eq :core (tun.core:field-source field))
          (let ((type (tun.core:field-type field)))
            (unless (equal (tun.core:type->db type (tun.core:field-value entity field))
                           (tun.core:type->db type (tun.core:field-value stored field)))
              (tun.core:extension-error "Extension code changed the core field ~a of ~a ~a"
                                        (tun.core:field-json-name field) (tun.core:entity-json-name class)
                                        (tun.core:entity-id entity))))))))
  (tun.core:save entity))

(defpackage #:tun.public-builder
  (:use #:cl)
  (:export #:define-facade))

(in-package #:tun.public-builder)

(defmacro define-facade (name &body groups)
  "DEFPACKAGE NAME re-exporting, for each (PACKAGE SYMBOL...) group, exactly
the listed symbols (the same symbol objects, not copies)."
  `(defpackage ,name
     (:use)
     ,@(loop for (package . symbols) in groups collect `(:import-from ,package ,@symbols))
     (:export ,@(loop for (nil . symbols) in groups append symbols))))

(define-facade #:tun
  ;; Defining things
  (#:tun.core
   #:define-entity #:extend-entity #:define-rule #:define-computed-field #:define-operation
   #:define-workflow #:define-message-template #:define-application #:define-setting #:define-setting-initial-value #:setting-value-at-use
   ;; field type designators (string, integer and boolean are CL's own)
   #:email #:enum #:date #:timestamp #:id #:list-of #:json
   ;; the application and its context
   #:application #:*application* #:entity #:stored-entity #:entity-id
   #:now #:today #:local-today #:date-add-days #:date-add-months #:date-at #:date-of #:parse-date #:format-date #:format-quantity #:format-kroner
   #:format-rfc3339 #:parse-rfc3339 #:date<= #:date<
   ;; a link at the server's public URL, for mail (spec/deploy.md 1)
   #:absolute-url
   ;; inside operations, rules, workflows
   #:fail #:input-value #:input-provided-p #:operation-result #:invoke
   ;; a :wait operation's body waits for a change (spec/waiting.md)
   #:await
   ;; who is asking: record policies (spec/store.md 6) compare with the actor's name
   #:*actor* #:actor-name #:actor-role #:actor-string #:with-actor #:system-actor
   ;; the messaging port: sends through the messaging module when it is enabled
   #:notify
   #:fetch #:fetch! #:select #:select-one #:define-query
   ;; JSON: a record as callers see it, for results that hold several
   #:entity->json #:jobj #:jarr #:jget
   ;; rank keys: records in an order a person chose (spec/core.md 2.6)
   #:rank-between #:rank-order-error #:rank-order-error-low #:rank-order-error-high)
  ;; Writes, guarded: an extension's own fields and records only
  (#:tun.guarded #:insert #:save)
  ;; The web UI: screens a client can override, and its own pages, built
  ;; from the components in TUN.UI (spec/ui.md 8)
  (#:tun.web
   #:render-screen #:section #:json-table #:entity-detail
   #:define-page #:web-call #:error-alert #:timestamp-text #:htmx-request-p #:staff-page-extras
   #:preload-request-p #:decline-preload)
  ;; Mail: queued in the caller's write, delivered after it commits
  ;; (spec/mail.md), and whom to send it to (spec/auth.md 2).  A client
  ;; creates and invites a person with (invoke 'accounts-create ...).
  (#:tun.mail #:send-mail)
  ;; Push notifications to an installed app's devices: queued in the
  ;; caller's write, delivered after it commits (spec/push.md)
  (#:tun.push #:notify-push)
  ;; Calling other systems' JSON APIs, and answering for them in tests
  ;; (spec/outbound.md)
  (#:tun.outbound #:http-json-post #:*http-json-handler*
   #:remote-failure #:remote-failure-status #:remote-failure-body #:remote-failure-url)
  ;; Jobs: work later, again when it fails, in the background (spec/jobs.md)
  (#:tun.jobs #:define-job #:enqueue-job #:cancel-job #:snooze-job #:fail-job #:last-attempt-p
   #:define-schedule #:define-trigger)
  (#:tun.auth #:account-address #:account-welcomed-p #:actor-account-kind #:account-names #:accounts-create)
  ;; Workflows (the kernel's engine)
  (#:tun.workflows
   #:schedule-workflow #:cancel-workflows #:pending-workflows #:note-workflow-run
   #:workflow #:workflow-kind #:workflow-order-id #:workflow-customer-id #:workflow-subject-id #:workflow-key
   #:workflow-due-at #:workflow-status))

;;; Each module publishes its own client-facing symbols into TUN when it
;;; loads (TUN.CORE:PUBLISH): a client sees exactly the modules it enables.

(setf tun.runtime::*core-packages*
  '(#:tun #:tun.core #:tun.workflows #:tun.accounting #:tun.accounting.fake #:tun.mail #:tun.push #:tun.outbound #:tun.jobs #:tun.platform #:tun.errors
    #:tun.introspection #:tun.auth #:tun.mcp #:tun.http #:tun.html #:tun.ui #:tun.web
    #:tun.guarded
    #:tun.runtime #:tun.store.memory #:tun.store.sqlite #:tun.store.postgres #:tun.public-builder))

;; Lock the kernel.  A client may still add methods to exported generic
;; functions (that is the extension mechanism) but cannot redefine kernel
;; functions, classes or macros, nor intern new symbols in kernel packages --
;; as long as its code is not compiled with *PACKAGE* set to a kernel
;; package: SBCL never enforces a package's lock while that package is
;; current.  The client interface check rejects such IN-PACKAGE forms, and
;; the integrity snapshot catches redefinitions at start-up whatever route
;; they took.  SNAPSHOT-CORE-DEFINITIONS snapshots and locks these packages
;; now that the kernel is complete; modules seal theirs as they load.

(defpackage #:tun-eval
  (:use #:cl #:tun))

(tun.runtime::snapshot-core-definitions)
