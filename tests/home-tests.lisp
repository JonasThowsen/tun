;;;; tests/home-tests.lisp -- the home page: where / and a sign-in lead,
;;;; the (:home path) option and the HOME-PATH seam (spec/ui.md 8, «Home»;
;;;; spec/auth.md 3.4, 3.5).

(in-package #:tun.tests)

(def-suite home :in core)
(in-suite home)

;;; ------------------------------------------------------------------
;;; The applications and pages the tests ask about

(tun.web:define-page home-today-page ("test-today" :title "Today" :navigation nil)
    (method path form query)
  (values 200 "Today" (list '(:p "today"))))

(tun.web:define-page home-setup-page ("test-setup" :title "Setup" :policy :admin
                                                   :navigation nil)
    (method path form query)
  (values 200 "Setup" (list '(:p "setup"))))

(define-application home-plain-app ())

(define-application home-option-app ()
  (:home "/test-today"))

(define-application home-admin-option-app ()
  (:home "/test-setup"))

(defclass home-client-feature () ()
  (:documentation "A client's feature with its own HOME-PATH method."))

(define-application home-client-app (home-client-feature)
  (:home "/test-today"))

(defvar *module-home* nil
  "What the customers module's test method answers for an admin: a path, or
NIL to pass on.  :READ answers from the store, to show it may be read.")

(defvar *client-home* nil
  "What HOME-CLIENT-FEATURE's method answers for anyone: a path, or NIL to
pass on to the modules and the option.")

(defvar *home-read* nil
  "What the module's method saw when *MODULE-HOME* is :READ: the actor bound
and the number of customers.")

;; Every application has the customers module's mixin once the module is
;; loaded, so this method is guarded by *MODULE-HOME* and otherwise passes on.
(defmethod tun.web:home-path ((app tun.customers::customers-module) actor)
  (case *module-home*
    ((nil) (call-next-method))
    (:read (setf *home-read* (list *actor* (length (select 'tun.customers::customer))))
     "/test-today")
    (t (if (eq (actor-role actor) :admin) *module-home* (call-next-method)))))

(defmethod tun.web:home-path ((app home-client-feature) actor)
  (declare (ignore actor))
  (or *client-home* (call-next-method)))

(defun home-for (application-class actor)
  "Where / leads ACTOR, a role:name string, in a fresh APPLICATION-CLASS, and
as a second value what was written to the error output."
  (with-test-app (:class application-class)
    (let ((tun.web::*web-app* *app*)
          (*error-output* (make-string-output-stream)))
      (with-application (*app*)
        (values (tun.web::person-home-path (parse-actor actor))
                (get-output-stream-string *error-output*))))))

(defun root-location (port &optional jar)
  "Where / sends a browser holding JAR."
  (location (nth-value 2 (web-request port "/" :jar jar))))

;;; ------------------------------------------------------------------
;;; Without a home page of the client's: as before

(test tuns-default-home-is-the-first-resource-with-record-pages
  (is (equal "/orders" (home-location nil)) "what sign-in-tests compare with"))

(test without-home-the-root-and-a-sign-in-lead-where-they-did
  (with-test-server (port :class 'home-plain-app)
    (is (equal "/orders" (root-location port (web-login port "employee:anna"))))
    (is (equal "/orders" (root-location port (web-login port "admin:root"))))
    (is (equal "/orders"
               (location (nth-value 2 (web-request port "/login"
                                                   :parameters '(("actor" . "viewer:vera"))))))
        "a claimed sign-in")))

(test the-root-sends-someone-not-signed-in-to-the-login
  (with-test-server (port :class 'home-option-app)
    (is (equal "/login" (root-location port))))
  (with-test-server (port :class 'home-plain-app)
    (is (equal "/login" (root-location port)))))

;;; ------------------------------------------------------------------
;;; The option

(test the-home-option-leads-the-root-and-a-sign-in-there
  (with-test-server (port :class 'home-option-app)
    (let ((jar (web-login port "employee:anna")))
      (is (equal "/test-today" (root-location port jar)))
      (is (equal "/test-today" (location (nth-value 2 (web-request port "/login" :jar jar))))
          "/login while signed in"))
    (is (equal "/test-today"
               (location (nth-value 2 (web-request port "/login"
                                                   :parameters '(("actor" . "employee:per"))))))
        "a claimed sign-in, for the person it signs in")
    (is (equal "/customers?q=1"
               (location (nth-value 2 (web-request port "/login"
                                                   :parameters '(("actor" . "employee:per")
                                                                 ("next" . "/customers?q=1"))))))
        "a next kept wins")))

(test a-home-option-that-is-not-a-page-here-is-refused-when-compiled
  (dolist (path '("/" "/?x=1" "/#a" "//evil.example" "https://evil.example" "today"
                  "/a\\b" "/login" "/logout" "/auth/test" "/setup/x" "" 42))
    (signals error (macroexpand-1 `(define-application home-bad-app () (:home ,path)))
      "~s is refused" path))
  (signals error (macroexpand-1 '(define-application home-bad-app ()
                                  (:home "/a" "/b"))))
  (signals error (macroexpand-1 `(define-application home-bad-app ()
                                   (:home ,(format nil "/a~cb" #\Tab)))))
  (signals error (macroexpand-1 `(define-application home-bad-app ()
                                   (:home ,(format nil "/~a" (make-string 2000 :initial-element #\a))))))
  (finishes (macroexpand-1 '(define-application home-good-app () (:home "/today?view=week")))))

(test home-path-is-a-published-seam
  (is (eq 'tun.web:home-path (find-symbol "HOME-PATH" "TUN")))
  (is (documentation 'tun.web:home-path 'function))
  (with-test-app (:class 'home-option-app)
    (is (equal "/test-today" (tun.web:home-path *app* (parse-actor "employee:anna")))
        "Tun's method answers the option"))
  (with-test-app (:class 'home-plain-app)
    (is (null (tun.web:home-path *app* (parse-actor "employee:anna"))))))

;;; ------------------------------------------------------------------
;;; The seam: a module's answer and a client's

(test a-modules-answer-wins-over-the-option
  (let ((*module-home* "/test-setup"))
    (is (equal "/test-setup" (home-for 'home-option-app "admin:root")))
    (is (equal "/test-today" (home-for 'home-option-app "employee:anna"))
        "the module passes on for an employee, to the option")))

(test a-clients-answer-wins-over-a-modules
  (let ((*module-home* "/test-setup"))
    (let ((*client-home* "/customers"))
      (is (equal "/customers" (home-for 'home-client-app "admin:root"))))
    (is (equal "/test-setup" (home-for 'home-client-app "admin:root"))
        "with call-next-method, the module's answer")
    (is (equal "/test-today" (home-for 'home-client-app "employee:anna"))
        "and through it the option")))

(test a-method-reads-the-store-as-the-actor
  (let ((*module-home* :read) (*home-read* nil))
    (is (equal "/test-today" (home-for 'home-plain-app "employee:anna")))
    (is (equal "employee:anna" (actor-string (first *home-read*))))
    (is (integerp (second *home-read*)))))

(test an-answer-the-person-cannot-open-is-not-taken
  ;; A page of a module the application does not enable: the test page,
  ;; registered again as if a module named absent had defined it.
  (setf (gethash "test-absent" tun.web::*staff-pages*)
        (let ((page (tun.web::copy-staff-page (gethash "test-today" tun.web::*staff-pages*))))
          (setf (tun.web::staff-page-module page) "absent")
          page))
  (unwind-protect
       (dolist (answer (list "//evil.example" "https://evil.example" "/" "/?x=1" "/login"
                             "/auth/test" "/no-such-page" "/test-absent" "/test-setup"
                             (format nil "/test-today~c" #\Newline) 42))
         (let ((*client-home* answer))
           (multiple-value-bind (home said) (home-for 'home-client-app "employee:anna")
             (is (equal "/test-today" home) "~s falls to the option" answer)
             (is (search "is not one employee:anna can open" said) "~s is written out" answer))))
    (remhash "test-absent" tun.web::*staff-pages*)))

(test an-answer-a-person-can-open-is-taken
  (dolist (answer '("/customers" "/customers/cus_1" "/access" "/test-today?view=week"))
    (let ((*client-home* answer))
      (multiple-value-bind (home said) (home-for 'home-client-app "employee:anna")
        (is (equal answer home))
        (is (equal "" said)))))
  (let ((*client-home* "/test-setup"))
    (is (equal "/test-setup" (home-for 'home-client-app "admin:root")) "an admin's page")))

(test an-option-the-person-cannot-open-falls-to-the-default
  (is (equal "/test-setup" (home-for 'home-admin-option-app "admin:root")))
  (multiple-value-bind (home said) (home-for 'home-admin-option-app "employee:anna")
    (is (equal "/orders" home))
    (is (search "/test-setup" said))))

;;; ------------------------------------------------------------------
;;; A provider's sign-in

(test a-providers-sign-in-lands-on-the-persons-home
  (with-test-server (port :identity :authenticated :class 'home-option-app)
    (with-provider (provider)
      (make-account "kari" "person" "employee" "kari@example.no")
      (make-account "ola" "person" "admin" "ola@example.no")
      ;; Set, not bound: the server answers in threads of its own.
      (setf *module-home* "/test-setup")
      (unwind-protect
           (flet ((lands (sub email)
                    (person-at provider sub email)
                    (multiple-value-bind (status body headers) (sign-in-over-provider port)
                      (declare (ignore body))
                      (and (= 303 status) (location headers)))))
             (is (equal "/test-today" (lands "1" "kari@example.no")) "the option, for an employee")
             (is (equal "/test-setup" (lands "2" "ola@example.no")) "the module's, for an admin"))
        (setf *module-home* nil))
      (let* ((jar (make-instance 'drakma:cookie-jar))
             (authorization (go-to-provider port :jar jar
                                                 :parameters '(("next" . "/customers")))))
        (person-at provider "1" "kari@example.no")
        (is (equal "/customers"
                   (location (nth-value 2 (absolute-request (come-back authorization) :jar jar))))
            "a next kept wins")))))

(test a-sign-in-that-sets-up-the-first-admin-goes-to-access
  (with-test-server (port :identity :authenticated :class 'home-option-app)
    (with-provider (provider)
      (person-at provider "1001" "kari@example.no" "name" "Kari Nordmann")
      (let* ((jar (make-instance 'drakma:cookie-jar))
             (authorization (go-to-provider port :jar jar :path (setup-path)
                                                 :parameters '(("name" . "kari")
                                                               ("provider" . "test")))))
        (is (equal "/access"
                   (location (nth-value 2 (absolute-request (come-back authorization)
                                                            :jar jar)))))))))
