;;;; tests/slice1-review-tests.lisp -- regressions in the orders, staffing and
;;;; calendar modules: each test guards a defect an independent review found.

(in-package #:tun.tests)

(def-suite slice1-review :in core)
(in-suite slice1-review)

;;; A package standing for client code: CL and TUN only, not a TUN.* name.
(defpackage #:s1r-client (:use #:cl #:tun))

(defun s1r-eval (form)
  "Evaluate FORM as client code (the definition macros read *PACKAGE*)."
  (let ((*package* (find-package '#:s1r-client)))
    (eval form)))

(defun s1r-forget-entities (&rest names)
  (setf tun.core::*entities* (set-difference tun.core::*entities* names))
  (tun.core::invalidate-field-caches))

;;; Finding 1: an entity could take over a module's table (probe p4).
(test s1r-1-an-entity-cannot-take-another-entitys-table-name-or-prefix
  (let ((names (mapcar (lambda (n) (intern n '#:s1r-client))
                       '("SHADOW-ORDER" "SHADOW-PREFIX" "SHADOW-NAME" "SHADOW-HISTORY" "OWN-THING"))))
    (unwind-protect
         (destructuring-bind (shadow-order shadow-prefix shadow-name shadow-history own-thing) names
           (flet ((define (name &rest options)
                    (s1r-eval `(define-entity ,name (:label "Skygge" ,@options)
                                 ((status :type (string :max 50) :label "S"))))))
             (signals extension-error (define shadow-order :table "orders" :id-prefix "zzq"))
             (signals extension-error (define shadow-prefix :table "zz_prefix" :id-prefix "ord"))
             (signals extension-error (define shadow-name :json-name "order" :table "zz_name" :id-prefix "zzn"))
             (signals extension-error (define shadow-history :table "schema_history" :id-prefix "zzh"))
             (is (notany (lambda (n) (member n tun.core::*entities*)) (list shadow-order shadow-prefix shadow-name shadow-history))
                 "nothing refused is registered")
             (is (null (entity-registry-conflicts)))
             ;; A client's own entity is fine; moved onto the orders table after
             ;; registration, start-up and the guarded writes refuse it.
             (define own-thing :table "zz_own_things" :id-prefix "zzo")
             (let ((class (find-class own-thing)))
               (setf (entity-table class) "orders")
               (unwind-protect
                    (progn
                      (is (entity-registry-conflicts) "the shared table is a conflict")
                      (signals extension-error (tun.runtime:open-application 'application))
                      (signals extension-error (tun:insert (make-instance own-thing :status "x")))
                      (signals extension-error (tun:save (make-instance own-thing :status "x"))))
                 (setf (entity-table class) "zz_own_things")))))
      (apply #'s1r-forget-entities names))))

;;; Finding 9: a client's workflow kind silently replaced core's debug_ping.
(test s1r-9-a-workflow-kind-cannot-be-taken-over
  (let ((before (find-workflow-kind "debug_ping"))
        (hijack (intern "HIJACK" '#:s1r-client)))
    (signals extension-error
      (s1r-eval `(define-workflow ,hijack (:kind "debug_ping" :label "kapret") (wf) (declare (ignore wf)) nil)))
    (is (eq before (find-workflow-kind "debug_ping")) "the kernel's handler stays")
    (is (string= "core" (workflow-kind-module (find-workflow-kind "debug_ping"))))
    ;; The same handler registering its kind again (a reload) is not a conflict.
    (is (string= "debug_ping" (tun.core::register-workflow-kind "debug_ping" (workflow-kind-function before)
                                                                  :label (workflow-kind-label before) :source :core)))
    (setf tun.core::*workflow-kinds*
          (append (remove "debug_ping" tun.core::*workflow-kinds* :key #'workflow-kind-name :test #'string=)
                  (list before)))))

;;; Finding 2: SB-INT:ENCAPSULATE on a sealed function passed the integrity
;;; snapshot (FDEFINITION strips the wrapper), the snapshot was compared only
;;; at start, and modules could use every external of SB-EXT and SB-INT (probe p1).
(test s1r-2-a-wrapped-kernel-function-is-refused-at-start-and-per-request
  (with-test-app ()
    (unwind-protect
         (progn
           (sb-int:encapsulate 'actor-permits-p 's1r (lambda (function &rest args) (declare (ignore function args)) t))
           (is (find-if (lambda (v) (search "ACTOR-PERMITS-P" v)) (definition-integrity-violations)))
           (signals extension-error (tun.runtime:open-application 'application))
           ;; The running application refuses the next request.
           (signals extension-error (call "employees_create" "viewer:mallory" "name" "M" "actor" "admin:m" "role" "admin")))
      (sb-int:unencapsulate 'actor-permits-p 's1r))
    (is (null (definition-integrity-violations)) "clean again")
    (is (equalp #() (jget (call-ok "employees_list" "admin:a") "items")) "no employee was created")
    ;; A generic function keeps its wrapper inside: checked too.
    (unwind-protect
         (progn
           (sb-int:encapsulate 'tun.orders:order-discount 's1r (lambda (function &rest args) (apply function args)))
           (is (find-if (lambda (v) (search "ORDER-DISCOUNT was wrapped" v)) (definition-integrity-violations))))
      (sb-int:unencapsulate 'tun.orders:order-discount 's1r))
    (is (null (definition-integrity-violations))))
  ;; A module's source may not name SB-EXT/SB-INT operators.
  (let ((violations (public-interface-violations
                     "(in-package #:tun.calendar)
(defun f () (sb-ext:unlock-package :tun.orders)
  (sb-ext:without-package-locks (sb-int:encapsulate 'g 'x (lambda (f &rest a) (declare (ignore f a)) t))))"
                     :package "TUN.CALENDAR" :public-packages +kernel-public-packages+
                     :library-packages +module-library-packages+)))
    (dolist (name '("UNLOCK-PACKAGE" "WITHOUT-PACKAGE-LOCKS" "ENCAPSULATE"))
      (is (find-if (lambda (v) (search name v)) violations) "~a is refused: ~s" name violations))))

;;; Finding 5: the reader check missed reflective lookups, PROGV, COERCE to a
;;; function, and code in a .asd; module .asd files were never scanned.
(test s1r-5-the-reader-check-catches-the-evasions
  (let ((violations (public-interface-violations
                     "(in-package #:s1r-client)
(defun internal (name)
  (or (loop for s being the present-symbols of (symbol-package 'tun:now)
            when (string= (symbol-name s) name) return s)
      (first (apropos-list name))))
(defun as-admin (thunk)
  (progv (list (internal \"*ACTOR*\")) (list (funcall (internal \"PARSE-ACTOR\") \"admin:x\"))
    (funcall thunk)))
(defun make-fn (form) (coerce form 'function))
(defun call-by-name (x) (format nil \"~/tun.core:actor-permits-p/\" x))
(defun walk () (with-package-iterator (next (list :tun) :internal) (next)))"
                     :package "S1R-CLIENT")))
    (dolist (what '("LOOP over a package" "SYMBOL-PACKAGE" "APROPOS-LIST" "PROGV" "COERCE" "~/name/"
                    "WITH-PACKAGE-ITERATOR"))
      (is (find-if (lambda (v) (search what v)) violations) "~a is caught: ~s" what violations)))
  ;; Harmless uses stay allowed.
  (is (null (public-interface-violations
             "(in-package #:s1r-client)
(defun tags (order) (coerce (tun:jget order \"tags\") 'list))
(defun keys (table) (loop for k being the hash-keys of table collect k))"
             :package "S1R-CLIENT")))
  ;; A .asd is data: no :perform, no UIOP, no keyword designators of symbols.
  (let ((violations (asd-violations "(defsystem \"evil\" :depends-on (\"tun\")
  :perform (load-op :after (o c) (declare (ignore o c))
             (uiop:symbol-call :sb-ext :unlock-package :tun.core)
             (setf (symbol-function (uiop:find-symbol* :actor-permits-p :tun.core)) (constantly t))))")))
    (is (find-if (lambda (v) (search ":PERFORM" v)) violations) "~s" violations))
  (is (asd-violations "(defsystem \"x\" :components ((:file \"a\"))) (uiop:symbol-call :sb-ext :unlock-package :tun.core)"))
  (is (null (asd-violations "(defsystem \"ok\" :version \"1.0\" :depends-on (\"tun\") :serial t :components ((:module \"m\" :components ((:file \"a\")))))")))
  ;; Every module's .asd is scanned (and clean).
  (dolist (module (mapcar #'module-name (all-modules)))
    (is (= 1 (length (module-asd-files module))) "~a has its .asd scanned" module)
    (is (null (module-violations module)) "~a: ~s" module (module-violations module))))

;;; Finding 3: a client seam method set the order's status through a
;;; published setf accessor (probe p2); a client rule could do the same.
(test s1r-3-client-seams-and-rules-cannot-change-core-fields
  (let ((feature (intern "SNEAKY-FEATURE" '#:s1r-client))
        (app (intern "SNEAKY-APP" '#:s1r-client)))
    (s1r-eval `(defclass ,feature () ()))
    (s1r-eval `(defclass ,app (,feature application) ()))
    (let ((method (s1r-eval `(defmethod tun.orders:order-discount ((app ,feature) order customer)
                               (declare (ignore customer))
                               (when (find "rental" (coerce (tun.orders:order-tags order) 'list) :test #'equal)
                                 (setf (tun.orders:order-status order) "confirmed"))
                               (call-next-method)))))
      (unwind-protect
           (with-test-app (:class app)
             (let* ((customer (make-customer))
                    (machine (make-product :units-owned 1))
                    (order (new-order customer "event_date" "2026-06-01" "lines" (jarr (list (line machine 1)))))
                    (id (jget order "id")))
               (signals extension-error
                 (call "orders_update" "employee:anna" "id" id "revision" (jget order "revision")
                       "tags" (jarr (list "rental"))))
               (let ((stored (order-of id)))
                 (is (equal "draft" (jget stored "status")))
                 (is (equalp #() (jget stored "bookings")))
                 (is (equalp #() (jget stored "tags")) "nothing of the update was stored"))
               ;; The same order updated without the trigger works: computing is fine.
               (is (equal "draft" (jget (call-ok "orders_update" "employee:anna" "id" id
                                                  "revision" (jget order "revision") "tags" (jarr (list "entertainment")))
                                         "status")))))
        (remove-method #'tun.orders:order-discount method))))
  ;; A client rule on order that "fixes" a field in passing.
  (let ((rule (intern "SNEAKY-RULE" '#:s1r-client)))
    (s1r-eval `(define-rule ,rule (tun.orders:order o) (:message "x")
                 (setf (tun.orders:order-delivery-address o) "Kapret 1")
                 t))
    (unwind-protect
         (with-test-app ()
           (let ((customer (make-customer))
                 (product (make-product)))
             (signals extension-error (new-order customer "lines" (jarr (list (line product 1))))))
           (is (equalp #() (jget (call-ok "orders_list" "viewer:vera") "items")) "nothing stored"))
      (setf (entity-rules (find-class 'tun.orders:order))
            (remove rule (entity-rules (find-class 'tun.orders:order)) :key #'rule-name)))))

;;; Finding 6: eval was read-only only in its own thread; a thread it started
;;; created an admin employee (SQLite) or hung to the deadline (memory store).
(test s1r-6-eval-is-read-only-in-the-threads-it-starts
  (dolist (db (list (scratch-path "s1r-6") nil))
    (with-test-app (:allow-eval t :db db)
      (let* ((start (get-internal-real-time))
             (result (call-ok "eval" "admin:ops" "code"
                              "(let ((app tun:*application*))
                                 (sb-thread:join-thread
                                  (sb-thread:make-thread
                                   (lambda ()
                                     (handler-case
                                         (tun.core:call-tool \"employees_create\"
                                                             (tun:jobj \"name\" \"Ghost\" \"actor\" \"admin:ghost\" \"role\" \"admin\")
                                                             :application app
                                                             :actor (tun.core:parse-actor \"admin:someone-else\"))
                                       (error (e) (princ-to-string e)))))))"))
             (seconds (/ (- (get-internal-real-time) start) internal-time-units-per-second)))
        (is (search "started by eval" (aref (jget result "values") 0)) "the thread's write is refused: ~a" (jget result "values"))
        (is (< seconds 5) "no wait for the deadline (~,1f s)" seconds)
        (is (equalp #() (jget (call-ok "employees_list" "admin:a") "items")) "no employee was created")))))

;;; The rollback preflight (core.md §6.4): an older core on a newer database
;;; would misread statuses and price modes and drop them on its next write.
;;; tests/fixtures/lite-registry.json is the registry_describe of a client
;;; deployment on the oldest supported core (3775ab3), the one a rollback of
;;; core goes back to; "lite" below names that core.
(defun lite-registry-path ()
  (merge-pathnames "tests/fixtures/lite-registry.json" (asdf:system-source-directory "tun")))

(defun s1r-confirmed-rental (customer machine date)
  (let ((id (jget (new-order customer "event_date" date "lines" (jarr (list (line machine 1)))) "id")))
    (advance-to-accepted id)
    (two-step "orders_confirm" "employee:anna" "id" id)
    id))

(test s1r-7-rollback-preflight-refuses-what-the-older-core-cannot-read
  (let ((compatible (scratch-path "s1r-7-compatible"))
        (slice1 (scratch-path "s1r-7-slice1")))
    ;; A database the lite core can take: an order written the lite way.
    (with-test-app (:db compatible)
      (s1r-confirmed-rental (make-customer) (make-product :units-owned 5) "2026-06-20"))
    ;; Its order still fits lite; the new delivery intentionally prevents
    ;; returning to a messaging implementation without outcome tracking.
    (let ((findings (tun.runtime::rollback-preflight 'application compatible (lite-registry-path))))
      (is (search "delivery:" (caar findings)))
      ;; Core 2.0 renamed the workflow statuses, which the older core cannot read.
      (is (every (lambda (f) (or (search "delivery:" (car f)) (search "workflow.status = " (car f))))
                 findings)
          "~s" findings))
    ;; The same, plus orders in picked_up, returned and ready_for_invoice and one
    ;; with a fixed discount.
    (with-test-app (:db slice1)
      (let* ((customer (make-customer))
             (machine (make-product :units-owned 5)))
        (s1r-confirmed-rental customer machine "2026-06-20")
        (let ((picked (s1r-confirmed-rental customer machine "2026-06-21"))
              (returned (s1r-confirmed-rental customer machine "2026-06-22"))
              (invoicing (s1r-confirmed-rental customer machine "2026-06-23")))
          (dolist (id (list picked returned invoicing))
            (call-ok "orders_register_pickup" "employee:anna" "id" id "condition" "ok"))
          (dolist (id (list returned invoicing))
            (call-ok "orders_register_return" "employee:anna" "id" id "condition" "ok"))
          (call-ok "orders_ready_for_invoice" "employee:anna" "id" invoicing))
        (new-order customer "price_mode" "fixed_discount" "discount_input_minor" 5000 "price_reason" "Fast kunde"
                   "lines" (jarr (list (line machine 1))))
        ;; A line discount: the lite core's next write of the order drops it.
        (new-order customer "lines" (jarr (list (line machine 1 "price_mode" "percent_discount" "discount_percent" 10))))))
    (let ((findings (tun.runtime::rollback-preflight 'application slice1 (lite-registry-path))))
      (dolist (kind '("order.status = picked_up" "order.status = returned"
                      "order.status = ready_for_invoice"
                      "order.price_mode set (fixed_discount)" "order.lines[].discount_percent set"))
        (let ((finding (find-if (lambda (f) (eql 0 (search kind (car f)))) findings)))
          (is (and finding (= 1 (cdr finding))) "~a counted once: ~s" kind findings)))
      (is (null (find-if (lambda (f) (search "confirmed" (car f))) findings)) "the lite-compatible orders pass"))))

;;; Finding 11: calendar_list read every order with event_date <= to (no lower
;;; bound, no cap).
(test s1r-11-calendar-list-is-bounded
  (with-test-app ()
    (let* ((customer (make-customer))
           (machine (make-product :units-owned 50))
           (old (jget (new-order customer "event_date" "2026-01-10" "lines" (jarr (list (line machine 1)))) "id"))
           (long (jget (new-order customer "event_date" "2026-05-25" "end_date" "2026-06-03"
                                  "lines" (jarr (list (line machine 1))))
                       "id"))
           (inside (jget (new-order customer "event_date" "2026-06-10" "lines" (jarr (list (line machine 1)))) "id")))
      (flet ((ids (json) (map 'list (lambda (e) (jget e "id")) (jget json "items"))))
        (let ((june (call-ok "calendar_list" "viewer:vera" "from" "2026-06-01" "to" "2026-06-30")))
          (is (equal (list long inside) (ids june)) "an order ending before the period is not read")
          (is (null (jget june "truncated"))))
        (is-error "invalid_input" nil (call "calendar_list" "viewer:vera" "from" "2026-01-01" "to" "2027-06-30"))
        (is-error "invalid_input" nil (call "calendar_list" "viewer:vera" "from" "2026-06-30" "to" "2026-06-01"))
        (let ((tun.calendar::*calendar-list-max-items* 1))
          (let ((capped (call-ok "calendar_list" "viewer:vera" "from" "2026-06-01" "to" "2026-06-30")))
            (is (equal (list long) (ids capped)))
            (is (eq t (jget capped "truncated")))))
        (is (member old (ids (call-ok "calendar_list" "viewer:vera" "from" "2026-01-01" "to" "2026-01-31")) :test #'equal))))))

;;; Finding 12: quote access codes were compared with STRING= (early exit)
;;; and wrong codes were not throttled.
(test s1r-12-wrong-access-codes-are-throttled
  (is (tun.orders::same-code-p "ABCDEFGHJK" "ABCDEFGHJK"))
  (is (not (tun.orders::same-code-p "ABCDEFGHJA" "ABCDEFGHJK")))
  (is (not (tun.orders::same-code-p "ABCDEFGHJ" "ABCDEFGHJK")))
  (with-test-app ()
    (let* ((order (jget (new-order (make-customer) "lines" (jarr (list (line (make-product) 1)))) "id")))
      (call-ok "orders_send_quote" "employee:anna" "id" order)
      (let* ((quote (call-ok "quotes_get" "admin:a" "order_id" order))
             (id (jget quote "id"))
             (code (jget quote "access_code")))
        (flet ((respond (access)
                 (call "quotes_respond" "viewer:kunde" "quote_id" id "revision" 1 "access_code" access
                       "response" "accept")))
          (dotimes (i 5)
            (is-error "forbidden" "Wrong access code for the quote" (respond "AAAAAAAAAA")))
          (is-error "forbidden" nil (respond code))
          (is (equal "quote_sent" (jget (order-of order) "status")) "the right code waits for the window")
          (call-ok "clock_set" "admin:a" "now" (format-rfc3339 (+ (now-of *app*) (* 16 60))))
          (is (equal "accepted" (jget (respond code) "status")) "after the window the right code works")
          (is (equal "accepted" (jget (order-of order) "status"))))))))
