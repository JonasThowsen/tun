;;;; tests/public-title-tests.lisp -- the name a customer sees on a public
;;;; page: the PUBLIC-PAGE-TITLE seam, its fallbacks, and that staff pages
;;;; keep the application's (spec/ui.md 8, «Public pages»).

(in-package #:tun.tests)

(def-suite public-title :in core)
(in-suite public-title)

;;; ------------------------------------------------------------------
;;; The applications and the page the tests ask about

(tun.web:register-public-page
 "test-public-title"
 (lambda (method parts form session)
   (declare (ignore method form session))
   (cond ((equal parts '("ok")) (values 200 "Quote" (list '(:p "Your quote"))))
         ((equal parts '("gone")) (values 410 "The link has expired" (list '(:p "Ask again"))))
         ((equal parts '("refused")) (fail :invalid-input "The quote cannot be answered"))
         (t (values 404 "Page not found" (list '(:p "Check the link")))))))

(tun.web:register-public-page
 "test-public-plain"
 (lambda (method parts form session)
   (declare (ignore method parts form session))
   (values 200 "Notice" (list '(:p "For anyone")))))

(define-application public-title-plain-app ()
  (:default-initargs :name "erp"))

(defclass public-title-client-feature () ()
  (:documentation "A client's feature with its own PUBLIC-PAGE-TITLE method."))

(define-application public-title-client-app (public-title-client-feature)
  (:default-initargs :name "erp"))

(defvar *module-title* nil
  "What the customers module's test method answers for the prefix
test-public-title: a value, :READ for the number of customers in the store,
:ERROR to signal, or NIL to pass on.")

(defvar *client-title* nil
  "What PUBLIC-TITLE-CLIENT-FEATURE's method answers: a value, :WRAP for the
modules' answer inside its own, or NIL to pass on.")

;; Every application has the customers module's mixin once the module is
;; loaded, so this method is guarded by *MODULE-TITLE* and otherwise passes on.
(defmethod tun.web:public-page-title ((app tun.customers::customers-module) prefix)
  (if (and *module-title* (equal prefix "test-public-title"))
      (case *module-title*
        (:read (format nil "Customers: ~d" (length (select 'tun.customers::customer))))
        (:error (error "the company is not set up"))
        (t *module-title*))
      (call-next-method)))

(defmethod tun.web:public-page-title ((app public-title-client-feature) prefix)
  (declare (ignore prefix))
  (case *client-title*
    ((nil) (call-next-method))
    (:wrap (format nil "~a, by the client" (call-next-method)))
    (t *client-title*)))

(defun shell-part (class body)
  "The text of the element of CLASS in the page BODY, as written."
  (nth-value 1 (cl-ppcre:scan-to-strings
                (format nil "class=\"~a\"[^>]*>([^<]*)<" class) body)))

(defun page-names (body)
  "The shell's title, its mark and the document's title in BODY, as written."
  (list (let ((title (shell-part "tun-app-shell-name-text" body))) (and title (aref title 0)))
        (let ((mark (shell-part "tun-app-shell-mark" body))) (and mark (aref mark 0)))
        (let ((title (nth-value 1 (cl-ppcre:scan-to-strings "<title>([^<]*)</title>" body))))
          (and title (aref title 0)))))

(defun public-names (port path)
  "The status of PATH and the shell's title, mark and document title."
  (multiple-value-bind (status body) (web-request port path)
    (values status (page-names body) body)))

(defun add-customer (name)
  "Store a customer named NAME in *APP*."
  (call-ok "customers_create" "employee:anna" "name" name
           "email" (format nil "~a@example.test" (string-downcase (remove #\Space name)))))

(defun shown-title (port)
  "The shell's title on the test's public page at PORT."
  (first (nth-value 1 (public-names port "/test-public-title/ok"))))

(defun public-title-for (application-class prefix)
  "What the shell takes as the title of the public page at PREFIX in a fresh
APPLICATION-CLASS, and as a second value what was written to the error
output."
  (with-test-app (:class application-class)
    (let ((tun.web::*web-app* *app*)
          (*error-output* (make-string-output-stream)))
      (with-application (*app*)
        (values (tun.web::public-title prefix)
                (get-output-stream-string *error-output*))))))

;;; ------------------------------------------------------------------
;;; Without a method: as before

(test a-public-page-shows-the-applications-title-without-a-method
  (with-test-server (port :class 'public-title-plain-app)
    (multiple-value-bind (status names) (public-names port "/test-public-title/ok")
      (is (= 200 status))
      (is (equal '("erp" "e" "Quote – erp") names)))
    (is (search "href=\"/test-public-title/ok\""
                (nth-value 1 (web-request port "/test-public-title/ok")))
        "the title links to the page itself")))

(test the-seam-and-the-public-pages-are-published
  (is (eq 'tun.web:public-page-title (find-symbol "PUBLIC-PAGE-TITLE" "TUN")))
  (is (eq 'tun.web:register-public-page (find-symbol "REGISTER-PUBLIC-PAGE" "TUN")))
  (is (documentation 'tun.web:public-page-title 'function))
  (is (find 'tun.web:public-page-title tun.core::*extension-protocols*
            :key #'tun.core::extension-protocol-name))
  (with-test-app (:class 'public-title-plain-app)
    (is (equal "erp" (tun.web:public-page-title *app* "test-public-title"))
        "Tun's method answers the application's title")))

;;; ------------------------------------------------------------------
;;; A module's answer and a client's

(test a-modules-answer-is-the-title-a-customer-sees
  (with-global (*module-title* "Lindenhof Services")
    (with-test-server (port :class 'public-title-plain-app)
      (is (equal '("Lindenhof Services" "L" "Quote – Lindenhof Services")
                 (nth-value 1 (public-names port "/test-public-title/ok"))))
      (is (equal '("erp" "e" "Notice – erp")
                 (nth-value 1 (public-names port "/test-public-plain")))
          "a page the method passes on for keeps the application's"))))

(test a-clients-answer-wins-over-a-modules
  (let ((*module-title* "Lindenhof Services"))
    (let ((*client-title* "Fjord Events"))
      (is (equal "Fjord Events" (public-title-for 'public-title-client-app "test-public-title"))))
    (let ((*client-title* :wrap))
      (is (equal "Lindenhof Services, by the client"
                 (public-title-for 'public-title-client-app "test-public-title"))
          "with call-next-method, the module's answer"))
    (let ((*client-title* nil))
      (is (equal "Lindenhof Services"
                 (public-title-for 'public-title-client-app "test-public-title"))))))

(test a-method-reads-the-store
  (let ((*module-title* :read))
    (with-test-app (:class 'public-title-plain-app)
      (add-customer "Kari Nordmann")
      (let ((tun.web::*web-app* *app*))
        (with-application (*app*)
          (is (equal "Customers: 1" (tun.web::public-title "test-public-title"))))))))

;;; ------------------------------------------------------------------
;;; Written as text, and the fallbacks

(test an-answer-is-trimmed-and-escaped
  (with-global (*module-title* "  <b>Berg & \"Sønn\"</b>  ")
    (with-test-server (port :class 'public-title-plain-app)
      (multiple-value-bind (status names body) (public-names port "/test-public-title/ok")
        (is (= 200 status))
        (is (equal '("&lt;b&gt;Berg &amp; &quot;Sønn&quot;&lt;/b&gt;" "&lt;"
                     "Quote – &lt;b&gt;Berg &amp; &quot;Sønn&quot;&lt;/b&gt;")
                   names))
        (is (not (search "<b>" body)) "no element of its own")))))

(test no-answer-gives-the-applications-title-quietly
  (dolist (answer (list "" "   " (format nil " ~c " #\Tab)))
    (let ((*module-title* answer))
      (multiple-value-bind (title said) (public-title-for 'public-title-plain-app
                                                         "test-public-title")
        (is (equal "erp" title) "~s" answer)
        (is (string= "" said) "~s is not written out" answer))))
  (let ((*client-title* nil) (*module-title* nil))
    (multiple-value-bind (title said) (public-title-for 'public-title-plain-app
                                                         "test-public-title")
      (is (equal "erp" title))
      (is (string= "" said)))))

(test a-wrong-answer-or-an-error-gives-the-applications-title-and-is-written-out
  (dolist (answer '(42 :error))
    (let ((*module-title* answer))
      (multiple-value-bind (title said) (public-title-for 'public-title-plain-app
                                                         "test-public-title")
        (is (equal "erp" title) "~s" answer)
        (is (search ";; tun web: the title of the public page \"test-public-title\"" said)
            "~s is written out: ~a" answer said)
        (is (search (if (eq answer :error) "the company is not set up" "42 is not text") said)))
      (with-global (*module-title* answer)
        (with-test-server (port :class 'public-title-plain-app)
          (multiple-value-bind (status names body) (public-names port "/test-public-title/ok")
            (is (= 200 status) "~s: the page still answers" answer)
            (is (equal '("erp" "e" "Quote – erp") names))
            (is (search "Your quote" body))))))))

;;; ------------------------------------------------------------------
;;; Every answer of a public page, and only public pages

(test every-answer-of-a-public-page-has-the-title
  (with-global (*module-title* "Lindenhof Services")
    (with-test-server (port :class 'public-title-plain-app)
      (loop for (path status heading) in '(("/test-public-title/gone" 410 "The link has expired")
                                           ("/test-public-title/x" 404 "Page not found")
                                           ("/test-public-title/refused" 422
                                            "The message could not be saved"))
            do (multiple-value-bind (got names) (public-names port path)
                 (is (= status got) "~a" path)
                 (is (equal (list "Lindenhof Services" "L"
                                  (format nil "~a – Lindenhof Services" heading))
                            names)
                     "~a: ~s" path names))))))

(test staff-pages-sign-in-and-the-manifest-keep-the-applications-title
  (with-global (*module-title* "Lindenhof Services")
    (with-test-server (port :class 'public-title-plain-app)
      (let ((jar (web-login port "employee:anna")))
        (let ((staff (nth-value 1 (web-request port "/customers" :jar jar))))
          (is (equal "erp" (first (page-names staff))))
          (is (search "– erp</title>" staff))))
      (let ((login (nth-value 1 (web-request port "/login"))))
        (is (equal "erp" (first (page-names login))))
        (is (not (search "Lindenhof" login)))))
    (with-test-server (port :class 'installable-app)
      (is (equal "Prøveappen"
                 (jget (parse-json (nth-value 1 (web-request port "/manifest.webmanifest")))
                       "name"))))))

(test each-tenant-sees-its-own-answer-on-every-request
  (with-global (*module-title* :read)
    (with-test-server (one :class 'public-title-plain-app)
      (let ((first-app *app*))
        (with-test-server (two :class 'public-title-plain-app)
          (add-customer "Kari Nordmann")
          (add-customer "Per Hansen")
          (loop repeat 3
                do (is (equal "Customers: 0" (shown-title one)))
                   (is (equal "Customers: 2" (shown-title two))))
          (let ((*app* first-app))
            (add-customer "Ola Berg"))
          (is (equal "Customers: 1" (shown-title one)) "a change shows on the next request")
          (is (equal "Customers: 2" (shown-title two))))))))
