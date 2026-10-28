;;;; tests/review2-tests.lisp -- regressions in the kernel's safety: each test
;;;; guards a defect an independent review found.

(in-package #:tun.tests)

(def-suite review2 :in core)
(in-suite review2)

;;; Finding 6: malformed dates are invalid_input, never an internal error.
(test r2-6-malformed-dates-are-invalid-input
  (dolist (bad '("2026-1--01" "2026-01-1-" "2026--1-01" "-026-01-01" "2026-01-+1"))
    (is (null (parse-date bad)) "~s" bad))
  (with-test-app ()
    (let ((product (jget (call-ok "products_create" "employee:anna" "name" "M" "kind" "rental" "unit" "stk"
                                  "unit_price_minor" 1 "stock_tracked" nil)
                         "id")))
      (is (string= "invalid_input"
                   (nth-value 1 (call "availability_check" "viewer:vera" "product_id" product "date" "2026-1--01"))))
      (is (string= "invalid_input" (nth-value 1 (call "inventory_shortages" "viewer:vera" "before_date" "2026-01-1-")))))))

;;; Finding 7: amounts beyond the exact JSON/SQLite integer range are refused.
(test r2-7-amount-overflow-is-invalid-input
  (dolist (db (list nil (scratch-path "overflow")))
    (with-test-app (:db db)
      (let ((customer (jget (call-ok "customers_create" "employee:anna" "name" "X" "email" "x@example.no") "id"))
            (product (jget (call-ok "products_create" "employee:anna" "name" "M" "kind" "service" "unit" "stk"
                                    "unit_price_minor" 9007199254740991 "stock_tracked" nil)
                           "id")))
        (is (string= "invalid_input"
                     (nth-value 1 (call "orders_create" "employee:anna" "customer_id" customer
                                        "lines" (jarr (list (jobj "product_id" product "quantity" 100000))))))
            "~a" (if db "sqlite" "memory"))
        (is (string= "invalid_input"
                     (nth-value 1 (call "orders_create" "employee:anna" "customer_id" customer
                                        "lines" (jarr (list (jobj "product_id" product "quantity" 1)
                                                            (jobj "product_id" product "quantity" 1))))))
            "a subtotal over the limit too")
        (is (= 9007199254740991
               (jget (call-ok "orders_create" "employee:anna" "customer_id" customer
                              "lines" (jarr (list (jobj "product_id" product "quantity" 1))))
                     "total_minor")))))))

;;; Finding 1: request lines and headers are bounded; serious conditions in a
;;; worker or workflow never take the process down.
(defun raw-exchange (port request)
  "Send REQUEST (a string) and return the first response line, or :closed."
  (let ((socket (usocket:socket-connect "127.0.0.1" port :element-type '(unsigned-byte 8))))
    (unwind-protect
         (handler-case
             (let ((stream (usocket:socket-stream socket)))
               (write-sequence (sb-ext:string-to-octets request :external-format :latin-1) stream)
               (finish-output stream)
               (let ((line (with-output-to-string (out)
                             (loop for byte = (read-byte stream nil nil)
                                   while (and byte (/= byte 13))
                                   do (write-char (code-char byte) out)))))
                 (if (plusp (length line)) line :closed)))
           (error () :closed))
      (usocket:socket-close socket))))

(defun crlf (&rest lines)
  (format nil "~{~a~c~c~}" (loop for l in lines append (list l #\Return #\Newline))))

(test r2-1-headers-and-request-line-are-bounded
  (with-test-server (port)
    (let ((huge (make-string (* 1024 1024) :initial-element #\a)))
      (is (search " 431" (princ-to-string (raw-exchange port (crlf "GET /health HTTP/1.1" "Host: x"
                                                                    (concatenate 'string "X-Junk: " huge) "")))))
      (is (search " 431" (princ-to-string (raw-exchange port (crlf (format nil "GET /~a HTTP/1.1" huge) "Host: x" "")))))
      (is (search " 200" (raw-exchange port (crlf "GET /health HTTP/1.1" "Host: x" "")))
          "the server is still up")
      ;; Requests with bodies still work after the header phase.
      (is (null (nth-value 1 (http-tool-call port "employee:anna" "customers_create"
                                             (jobj "name" "Etter" "email" "etter@example.no"))))))))

(defun deep-recursion (n) (1+ (deep-recursion (1+ n))))

(define-workflow test-deep (:kind "test_deep" :label "Sprenger stakken") (wf)
  (declare (ignore wf))
  (deep-recursion 0))

(test r2-1-workflow-exhausting-the-stack-is-cancelled
  (with-test-app ()
    (setf *pings* 0)
    (plan "test_deep" "2026-03-02T09:00:00Z")
    (plan "test_ping" "2026-03-02T09:30:00Z")
    (is (= 1 (jget (call-ok "clock_set" "admin:ada" "now" "2026-03-02T10:00:00Z") "executed_workflows"))
        "the failing workflow is cancelled and the next one still runs")
    (is (= 1 *pings*))
    (with-application (*app*)
      (with-transaction (:read)
        (is (string= "failed" (tun.workflows:workflow-status
                                (select-one 'tun.workflows:workflow :where '(:= "kind" "test_deep")))))))))

(test r2-1-unhandled-serious-condition-aborts-only-its-thread
  (let ((saved sb-ext:*invoke-debugger-hook*))
    (unwind-protect
         (progn
           (funcall (find-symbol "INSTALL-THREAD-GUARD" "TUN.RUNTIME"))
           (let ((thread (sb-thread:make-thread (lambda () (error 'storage-condition)) :name "doomed")))
             (is (eq :aborted (sb-thread:join-thread thread :default :aborted)))))
      (setf sb-ext:*invoke-debugger-hook* saved)))
  (is (sb-thread:thread-alive-p (sb-thread:main-thread)) "the process lives on"))

;;; Finding 4: numbers are length-bounded before parsing; no parsing at all
;;; without a valid actor.
(defun seconds-taken (thunk)
  (let ((start (get-internal-real-time)))
    (funcall thunk)
    (/ (- (get-internal-real-time) start) internal-time-units-per-second)))

(test r2-4-long-numbers-are-refused-quickly
  (let ((digits (make-string 200000 :initial-element #\9)))
    (is (< (seconds-taken (lambda () (signals json-parse-failure (parse-json digits)))) 0.5))
    (is (< (seconds-taken (lambda () (signals json-parse-failure
                                       (parse-json (format nil "{\"a\":[1,~a]}" digits)))))
           0.5)))
  (is (equalp #(123 -4.5d0 1d10) (parse-json "[123,-4.5,1e10]")) "ordinary numbers still parse")
  (is (string= "9999" (jget (parse-json "{\"s\":\"9999\"}") "s")))
  (with-test-app ()
    (let ((body (format nil "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{\"x\":~a}}"
                        (make-string 300000 :initial-element #\9))))
      (let ((response nil))
        (is (< (seconds-taken (lambda () (setf response (nth-value 1 (tun.mcp:handle-mcp *app* nil body))))) 0.5)
            "no actor: answered without parsing the body")
        (is (= -32000 (jget (jget response "error") "code")))))))

;;; Finding 2: switching to a core package must neither pass the interface
;;; check nor lift the package locks.
(test r2-2-the-interface-check-sees-through-in-package
  (flet ((violations (text) (public-interface-violations text :package "TUN.TESTS" :source "evil.lisp")))
    (is (violations "(in-package #:tun.core) (defun actor-permits-p (actor policy) t)")
        "in-package to a core package")
    (is (violations "(cl:in-package \"TUN.ORDERS\")"))
    (is (violations "(defun steal () (symbol-value (find-symbol \"*ACTOR*\" \"TUN.CORE\")))")
        "reflection by name")
    (is (violations "(defpackage #:evil2 (:use #:cl #:tun.core))") "using an internal package")
    (is (violations "(defpackage #:evil3 (:use #:cl) (:local-nicknames (#:c #:tun.core)))"))
    (is (violations "(sb-ext:unlock-package \"TUN\")") "symbols from outside CL and TUN")
    (is (violations "(eval (read-from-string \"(tun.core::foo)\"))"))
    (is (null (public-interface-violations "(in-package #:tun.tests) (defun ok () (list 1 :a))"
                                           :package "TUN.TESTS"))
        "the client's own in-package is fine")))

(test the-qualifier-check-reads-past-strings-and-comments
  (flet ((qualified-p (text)
           (some (lambda (violation) (search "uses a :: qualifier" violation))
                 (public-interface-violations text :package "TUN.TESTS"))))
    (is (qualified-p "(tun.tests::foo)"))
    (is (qualified-p "(list \"a \\\" b\" tun.tests::foo)") "after a string with an escaped quote")
    (is (not (qualified-p "(list \"WHERE (:since::text IS NULL)\")")) "a Postgres cast in a query")
    (is (not (qualified-p (format nil "; tun.core::foo~%(list 1)"))) "a comment")
    (is (not (qualified-p "#| a::b #| nested |# c::d |# (list #\\: #\\: '|x::y|)")))))

(test a-client-reaches-the-components-in-tun-ui
  (flet ((violations (text)
           (public-interface-violations text :package "TUN.TESTS"
                                             :public-packages '("TUN" "TUN.UI"))))
    (is (null (violations "(defpackage #:shop (:use #:cl #:tun) (:local-nicknames (#:ui #:tun.ui)))")))
    (is (null (violations "(list (tun.ui:card (:title \"Saker\") \"Tekst\"))")))
    (is (violations "(tun.ui:not-a-component)") "only its external symbols")
    (is (violations "(defpackage #:shop (:use #:cl) (:local-nicknames (#:w #:tun.web)))")
        "not the web layer's package")))

(test r2-2-every-client-file-is-scanned
  (let* ((root (merge-pathnames (format nil ".build/test-db/fake-client-~a/" (new-id "c"))
                                (asdf:system-source-directory "tun")))
         (nested (merge-pathnames "sub/deeper/hidden.lisp" root)))
    (ensure-directories-exist nested)
    (with-open-file (out (merge-pathnames "main.lisp" root) :direction :output) (write-string "(list 1)" out))
    (with-open-file (out nested :direction :output) (write-string "(list 2)" out))
    (ensure-directories-exist (merge-pathnames "tests/t.lisp" root))
    (with-open-file (out (merge-pathnames "tests/t.lisp" root) :direction :output :if-does-not-exist :create)
      (write-string "(list 3)" out))
    (let ((names (mapcar #'file-namestring (client-files-under root))))
      (is (member "hidden.lisp" names :test #'string=) "files in subdirectories are checked")
      (is (not (member "t.lisp" names :test #'string=)) "tests are not client code"))))

(test r2-2-core-redefinition-is-refused-at-start-up
  ;; SBCL does not enforce a package's lock while it is *PACKAGE*, so code
  ;; compiled after (in-package #:tun.core) can redefine core.  The start-up
  ;; integrity check refuses to run such a deployment.
  (is (check-core-integrity-ok-p))
  (let ((original (fdefinition 'actor-permits-p)))
    (unwind-protect
         (progn
           (let ((*package* (find-package "TUN.CORE")))
             (eval (read-from-string "(defun actor-permits-p (actor policy) (declare (ignore actor policy)) t)")))
           (is (not (eq original (fdefinition 'actor-permits-p))) "the redefinition itself went through")
           (signals tun.core::extension-error (tun.runtime:open-application 'application)))
      (sb-ext:without-package-locks (setf (fdefinition 'actor-permits-p) original))))
  ;; A new function defined inside a core package is refused too.
  (unwind-protect
       (progn
         (let ((*package* (find-package "TUN.CORE")))
           (eval (read-from-string "(defun receipt (x) x)")))
         (signals tun.core::extension-error (tun.runtime:open-application 'application)))
    (sb-ext:without-package-locks (fmakunbound 'tun.core::receipt)))
  ;; Replacing a core method (same specializers) is refused too.
  (let* ((gf #'tun.orders:order-discount)
         (owner (find-class 'tun.orders::orders-module))
         (core-method (find-method gf '() (list owner (find-class t) (find-class t)))))
    (unwind-protect
         (progn
           (eval '(defmethod tun.orders:order-discount ((app tun.orders::orders-module) order customer)
                   (declare (ignore order customer)) 1))
           (signals tun.core::extension-error (tun.runtime:open-application 'application)))
      (let ((replacement (find-method gf '() (list owner (find-class t) (find-class t)) nil)))
        (when replacement (remove-method gf replacement)))
      (add-method gf core-method)))
  (is (check-core-integrity-ok-p) "clean again"))

(defun check-core-integrity-ok-p ()
  (handler-case (tun.runtime::check-core-integrity) (error () nil)))

;;; Finding 3: extension code cannot rewrite core-owned fields, shadow stored
;;; fields, or put live HTML into a page.
(defclass meddling-app (application) ())

(defvar *meddle* :save)

(defmethod tun.orders:orders-accept :after ((app meddling-app) input)
  (declare (ignore input))
  (let ((order (operation-result)))
    (setf (tun.orders:order-status order) "completed"
          (tun.orders:order-total-minor order) -5
          (tun.orders:order-discount-minor order) 999999)
    (when (eq *meddle* :save) (tun:save order))))

(defun accepted-order (customer product)
  (let ((id (jget (call-ok "orders_create" "employee:anna" "customer_id" customer
                           "lines" (jarr (list (jobj "product_id" product "quantity" 2))))
                  "id")))
    (call-ok "orders_send_quote" "employee:anna" "id" id)
    id))

(test r2-3-extensions-cannot-write-core-fields
  (with-test-app (:class 'meddling-app)
    (let ((customer (jget (call-ok "customers_create" "employee:anna" "name" "X" "email" "x@example.no") "id"))
          (product (jget (call-ok "products_create" "employee:anna" "name" "P" "kind" "service" "unit" "stk"
                                  "unit_price_minor" 100 "stock_tracked" nil)
                         "id")))
      ;; Changing core fields and saving through the public SAVE is refused:
      ;; the whole operation rolls back.
      (let ((id (accepted-order customer product)))
        (setf *meddle* :save)
        (signals error (call "orders_accept" "employee:anna" "id" id))
        (let ((order (call-ok "orders_get" "viewer:vera" "id" id)))
          (is (equal '("quote_sent" 200 0) (list (jget order "status") (jget order "total_minor")
                                                   (jget order "discount_minor"))))))
      ;; Changing the object without saving does not leak into the result.
      (let ((id (accepted-order customer product)))
        (setf *meddle* :no-save)
        (let ((result (call-ok "orders_accept" "employee:anna" "id" id)))
          (is (equal '("accepted" 200 0) (list (jget result "status") (jget result "total_minor")
                                                (jget result "discount_minor")))
              ":after methods see a copy of the result")))
      ;; The public INSERT does not create core records.
      (with-application (*app*)
        (with-transaction (:write)
          (signals error (tun:insert (make-instance 'tun.orders:order :customer-id customer :status "completed"))))))))

(test r2-3-computed-fields-cannot-shadow-stored-fields
  (signals tun.core::extension-error
    (eval '(define-computed-field tun.customers:customer created-at (c) (:type string :label "x")
            (declare (ignore c)) "1999-01-01T00:00:00Z")))
  (signals tun.core::extension-error
    (eval '(define-computed-field tun.customers:customer revision (c) (:type integer :label "x")
            (declare (ignore c)) 424242)))
  (with-test-app ()
    (let ((c (call-ok "customers_create" "employee:anna" "name" "X" "email" "x@example.no")))
      (is (= 1 (jget c "revision")))
      (is (string= "2026-03-01T09:00:00Z" (jget c "created_at"))))))

(defclass scripting-app (application) ())

(defmethod tun.web:render-screen ((app scripting-app) (screen (eql :order-detail)) &key order)
  (list (list :raw (format nil "<script>alert(~s)</script>" (jget order "delivery_address")))
        (list :script "alert(2)")
        (list :a (list :@ :href "javascript:alert(3)" :onclick "alert(4)" :data-x "ok") "lenke")
        (list :a (list :@ :href "/orders" :class "fine") "trygg lenke")
        (call-next-method)))

(test r2-3-extension-screens-cannot-inject-html
  (with-test-server (port :class 'scripting-app)
    (let* ((customer (jget (call-ok "customers_create" "employee:anna" "name" "X" "email" "x@example.no") "id"))
           (product (jget (call-ok "products_create" "employee:anna" "name" "P" "kind" "service" "unit" "stk"
                                   "unit_price_minor" 100 "stock_tracked" nil)
                          "id"))
           (order (jget (call-ok "orders_create" "employee:anna" "customer_id" customer
                                 "delivery_address" "</script><b>x"
                                 "lines" (jarr (list (jobj "product_id" product "quantity" 1))))
                        "id"))
           (body (nth-value 1 (web-request port (format nil "/orders/~a" order)
                                           :jar (web-login port "employee:anna")))))
      (let ((own (list (format nil "<script defer src=\"~a\"></script>" (tun.ui:htmx-path))
                       (format nil "<script defer src=\"~a\"></script>" (tun.ui:script-path)))))
        (dolist (script own)
          (is (search script body) "htmx and the design system's script, from the page's head"))
        (is (not (search "<script" (reduce (lambda (text script)
                                             (cl-ppcre:regex-replace-all
                                              (cl-ppcre:quote-meta-chars script) text ""))
                                           own :initial-value body)))
            "no script element from an extension"))
      (is (not (search "javascript:" body)))
      (is (not (search "onclick" body)))
      (is (search "href=\"/orders\"" body) "ordinary links survive")
      (is (search "data-x=\"ok\"" body))
      (is (search "&lt;/script&gt;&lt;b&gt;x" body) "data stays escaped"))))

;;; Finding 8: a confirm-gated tool called from inside a request or workflow
;;; is an error, not a silent confirmation_required.
(define-workflow test-auto-archive (:kind "test_auto_archive" :label "Arkiver automatisk") (wf)
  (declare (ignore wf))
  (let ((w (select-one 'widget)))
    (invoke 'widgets-archive "id" (entity-id w))))

(test r2-8-nested-confirm-calls-fail-loudly
  (with-test-app ()
    (let ((id (jget (call-ok "widgets_create" "employee:anna" "name" "Auto") "id")))
      (plan "test_auto_archive" "2026-03-02T09:00:00Z")
      (is (= 0 (jget (call-ok "clock_set" "admin:ada" "now" "2026-03-02T10:00:00Z") "executed_workflows")))
      (is (string= "aktiv" (jget (call-ok "widgets_get" "viewer:vera" "id" id) "status")))
      (with-application (*app*)
        (with-transaction (:read)
          (is (string= "failed" (tun.workflows:workflow-status (select-one 'tun.workflows:workflow))))
          (is (null (select 'tun.core::confirmation)) "no token is left behind")))
      (is (find "rejected" (coerce (jget (call-ok "audit_list" "viewer:vera" "entity_type" "workflow") "items") 'list)
                :key (lambda (e) (jget e "outcome")) :test #'string=)))))

;;; Finding 9: a token is bound to the target's revision.
(test r2-9-token-is-bound-to-the-target-revision
  (with-test-app ()
    (let* ((customer (jget (call-ok "customers_create" "employee:anna" "name" "X" "email" "x@example.no") "id"))
           (product (jget (call-ok "products_create" "employee:anna" "name" "P" "kind" "service" "unit" "stk"
                                   "unit_price_minor" 100 "stock_tracked" nil)
                          "id"))
           (order (jget (call-ok "orders_create" "employee:anna" "customer_id" customer "event_date" "2026-06-01"
                                 "lines" (jarr (list (jobj "product_id" product "quantity" 1))))
                        "id")))
      (call-ok "orders_send_quote" "employee:anna" "id" order)
      (call-ok "orders_accept" "employee:anna" "id" order)
      (let ((token (jget (call-ok "orders_confirm" "employee:anna" "id" order) "confirmation_token")))
        ;; Someone else changes the order after the summary was shown.
        (call-ok "orders_update" "employee:bob" "id" order
                 "revision" (jget (call-ok "orders_get" "viewer:vera" "id" order) "revision")
                 "lines" (jarr (list (jobj "product_id" product "quantity" 50))))
        (is (string= "confirmation_invalid"
                     (nth-value 1 (call "orders_confirm" "employee:anna" "id" order "confirmation_token" token))))
        (is (string= "accepted" (jget (call-ok "orders_get" "viewer:vera" "id" order) "status")))))))

;;; Finding 10: the invoice copies the customer's identity, not free text.
(test r2-10-invoice-snapshot-omits-core-free-text
  (with-test-app ()
    (let* ((customer (jget (call-ok "customers_create" "employee:anna" "name" "Kari" "email" "kari@example.no"
                                    "phone" "+47 900 00 000" "notes" "Hunden biter")
                           "id"))
           (product (jget (call-ok "products_create" "employee:anna" "name" "P" "kind" "service" "unit" "stk"
                                   "unit_price_minor" 100 "stock_tracked" nil)
                          "id"))
           (order (jget (call-ok "orders_create" "employee:anna" "customer_id" customer "event_date" "2026-06-01"
                                 "lines" (jarr (list (jobj "product_id" product "quantity" 1))))
                        "id")))
      (call-ok "orders_send_quote" "employee:anna" "id" order)
      (call-ok "orders_accept" "employee:anna" "id" order)
      (let ((token (jget (call-ok "orders_confirm" "employee:anna" "id" order) "confirmation_token")))
        (call-ok "orders_confirm" "employee:anna" "id" order "confirmation_token" token))
      (let ((snapshot (jget (call-ok "invoices_create_from_order" "employee:anna" "order_id" order) "customer")))
        (is (equal '("Kari" "kari@example.no") (list (jget snapshot "name") (jget snapshot "email"))))
        (is (null (nth-value 1 (jget snapshot "phone"))) "no phone on the invoice")
        (is (null (nth-value 1 (jget snapshot "notes"))) "no notes on the invoice")))))

;;; Finding 5: the send intent is committed before the accounting port is
;;; called, the call happens outside the transaction, and the fake's call
;;; log is durable, so accounting_status always equals the real calls.
(defvar *port-calls* '())

(defclass observing-fake (tun.accounting.fake:fake-accounting) ())

(defmethod tun.accounting:create-invoice :before ((adapter observing-fake) intent)
  (push (list :inside-transaction tun.core:*transaction-mode*
              :intent-committed (with-transaction (:read)
                                  (and (select-one 'tun.invoicing::send-intent
                                                   :where `(:= "intent_id" ,(tun.accounting:intent-id intent)))
                                       t)))
        *port-calls*))

(defvar *invoice-write-failures* 0)
(defmethod store-update :before ((store store) (item tun.invoicing:invoice))
  (when (and (plusp *invoice-write-failures*) (equal (tun.invoicing:invoice-status item) "sent"))
    (decf *invoice-write-failures*)
    (error "simulated failure recording the accounting result")))

(defclass flaky-after-app (application) ((failures :initform 1 :accessor failures)))

(defmethod tun.invoicing:invoices-send :after ((app flaky-after-app) input)
  (declare (ignore input))
  (when (plusp (failures app))
    (decf (failures app))
    (fail :invalid-input "simulert feil i en klientutvidelse")))

(defun invoice-ready (&key (actor "employee:anna"))
  "A confirmed order with an utkast invoice; returns the invoice id."
  (let* ((customer (jget (call-ok "customers_create" actor "name" "X" "email" "x@example.no") "id"))
         (product (jget (call-ok "products_create" actor "name" "P" "kind" "service" "unit" "stk"
                                 "unit_price_minor" 100 "stock_tracked" nil)
                        "id"))
         (order (jget (call-ok "orders_create" actor "customer_id" customer "event_date" "2026-06-01"
                               "lines" (jarr (list (jobj "product_id" product "quantity" 1))))
                      "id")))
    (call-ok "orders_send_quote" actor "id" order)
    (call-ok "orders_accept" actor "id" order)
    (let ((token (jget (call-ok "orders_confirm" actor "id" order) "confirmation_token")))
      (call-ok "orders_confirm" actor "id" order "confirmation_token" token))
    (jget (call-ok "invoices_create_from_order" actor "order_id" order) "id")))

(defun send-invoice (id)
  (let ((token (jget (call-ok "invoices_send" "admin:ada" "id" id) "confirmation_token")))
    (call "invoices_send" "admin:ada" "id" id "confirmation_token" token)))

(defun reported-calls (id)
  (let ((entry (find-by "invoice_id" id (jget (call-ok "accounting_status" "admin:ada") "invoices"))))
    (if entry (jget entry "calls") 0)))

(test r2-5-intent-is-durable-before-the-port-call
  (with-test-app (:db (scratch-path "outbox"))
    (setf (application-accounting *app*) (make-instance 'observing-fake) *port-calls* '())
    (let ((id (invoice-ready)))
      (is (string= "sent" (jget (send-invoice id) "status")))
      (is (= 1 (length *port-calls*)))
      (is (null (getf (first *port-calls*) :inside-transaction)) "the port is called outside any transaction")
      (is (eq t (getf (first *port-calls*) :intent-committed)) "after the intent committed")
      (is (= 1 (reported-calls id))))))

(test r2-5-a-failing-extension-does-not-hide-a-port-call
  (with-test-app (:class 'flaky-after-app :db (scratch-path "outbox-after"))
    (setf (application-accounting *app*) (make-instance 'observing-fake) *port-calls* '())
    (let ((id (invoice-ready)))
      (is (string= "invalid_input" (nth-value 1 (send-invoice id))) "the extension fails the first send")
      (is (string= "sent" (jget (send-invoice id) "status")))
      (is (= (length *port-calls*) (reported-calls id)) "accounting_status equals the real number of calls")
      (is (= 1 (length *port-calls*)) "the failed attempt never reached the port"))))

(test r2-5-a-failure-after-the-port-call-is-resumed
  (with-test-app (:db (scratch-path "outbox-resume"))
    (setf (application-accounting *app*) (make-instance 'observing-fake) *port-calls* '())
    (let ((id (invoice-ready)))
      ;; Fail recording the result after the accounting call. Customer mail
      ;; now queues atomically and its provider failure cannot undo an invoice.
      (let ((*invoice-write-failures* 1)) (signals error (send-invoice id)))
      (is (string= "draft" (jget (call-ok "invoices_get" "viewer:vera" "id" id) "status")))
      (is (= 1 (length *port-calls*)))
      (is (= 1 (reported-calls id)) "the call that happened is on record although its transaction failed")
      (let ((sent (send-invoice id)))
        (is (string= "sent" (jget sent "status")) "a retry resumes the pending intent")
        (is (= 2 (length *port-calls*) (reported-calls id)))
        (is (string= (jget (find-by "invoice_id" id (jget (call-ok "accounting_status" "admin:ada") "invoices"))
                           "external_ref")
                     (jget sent "external_ref"))
            "the same intent id gives the same external reference")))))

;;; Finding 11: form posts from another origin are refused.
(defun post-with (port jar headers name)
  (multiple-value-bind (bytes status)
      (drakma:http-request (format nil "http://127.0.0.1:~d/customers" port)
                           :method :post :cookie-jar jar :redirect nil :force-binary t
                           :parameters `(("name" . ,name) ("email" . "csrf@example.no"))
                           :additional-headers headers)
    (declare (ignore bytes))
    status))

(test r2-11-cross-origin-form-posts-are-refused
  (with-test-server (port)
    (let ((jar (web-login port "employee:anna")))
      (is (= 403 (post-with port jar '(("Origin" . "http://evil.example")) "Fra evil")))
      (is (= 403 (post-with port jar `(("Origin" . ,(format nil "http://127.0.0.1:~d" (1+ port)))) "Annen port"))
          "another tenant on another local port is another origin")
      (is (= 403 (post-with port jar '(("Sec-Fetch-Site" . "cross-site")) "Cross-site")))
      (is (= 403 (post-with port jar '(("Origin" . "null")) "Null uten Sec-Fetch-Site"))
          "an opaque origin is foreign unless Sec-Fetch-Site says otherwise")
      (is (= 0 (jget (call-ok "customers_list" "viewer:vera" "query" "csrf") "returned")) "nothing was created")
      (is (= 303 (post-with port jar `(("Origin" . ,(format nil "http://127.0.0.1:~d" port))
                                       ("Sec-Fetch-Site" . "same-origin"))
                            "Samme opphav")))
      (is (= 1 (jget (call-ok "customers_list" "viewer:vera" "query" "Samme opphav") "returned")))
      (is (= 303 (post-with port jar '(("Origin" . "null") ("Sec-Fetch-Site" . "same-origin"))
                            "Uten referrer"))
          "a page sent with Referrer-Policy: no-referrer posts with Origin null"))))

;;; Finding 12: the ledger locks the stock row it updates (by that row's id).
(defclass lock-recording-store (tun.store.memory:memory-store)
  ((locks :initform '() :accessor recorded-locks)))

(defmethod store-lock-row :before ((store lock-recording-store) class-name id)
  (push (cons class-name id) (recorded-locks store)))

(test r2-12-the-ledger-locks-its-article
  (let* ((store (make-instance 'lock-recording-store))
         (*app* (tun.runtime:open-application 'application :store store :test-clock t)))
    (let ((product (jget (call-ok "products_create" "employee:anna" "name" "Begre" "kind" "consumable" "unit" "stk"
                                  "unit_price_minor" 1 "stock_tracked" t)
                         "id")))
      (call-ok "inventory_receive" "employee:anna" "product_id" product "quantity" 5)
      (with-application (*app*)
        (with-transaction (:read)
          ;; The balance is the product's article's: the
          ;; ledger locks the article by its own id (not the product's).
          (let ((article (tun.catalog:product-article-id (fetch 'tun.catalog:product product))))
            (is (member (cons 'tun.inventory:article article) (recorded-locks store) :test #'equal)
                "locked the article by its id: ~s" (recorded-locks store))
            (is (not (equal product article)) "the article has an id of its own")
            (is (every (lambda (lock) (eq (car lock) 'tun.inventory:article)) (recorded-locks store))
                "only articles were locked: ~s" (recorded-locks store))))))))
