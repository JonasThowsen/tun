;;;; tests/search-tests.lisp -- the application's one search (spec/ui.md 6.4):
;;;; the rule and its marks, the seam and who contributes, what the actor
;;;; may open, the order and the limits, the modules' results, the shell,
;;;; the page, the fragment and the tool, the CSS, and its speed.  The
;;;; record policy's test runs on Postgres when TUN_TEST_POSTGRES names a
;;;; server.

(in-package #:tun.tests)

(def-suite search :in core)
(in-suite search)

(defun q (text &rest keys)
  (apply #'make-search-query text keys))

;;; ------------------------------------------------------------------
;;; The rule (criterion 2)

(test the-fold-lowers-strips-marks-and-letters-and-spaces
  (is (string= "bjorn asen cafe ost" (search-fold "  Bjørn ÅSEN	 Café
Øst ")))
  (is (string= "asen" (search-fold "Aasen")) "a run of a is one a: aa is å")
  (is (string= "hakon" (search-fold "Haakon")))
  (is (string= "aeble strasse lodz oeuvre" (search-fold "Æble Straße Łódź Œuvre")))
  (is (string= "cafe" (search-fold (format nil "Cafe~a" (code-char #x301))))
      "a separate mark is the letter's")
  (is (string= "" (search-fold "   ")))
  (multiple-value-bind (folded from) (search-fold "Bjørn  Åsen")
    (is (string= "bjorn asen" folded))
    (is (= 7 (aref from 6)) "each folded character knows where it came from")))

(test every-word-is-found-in-some-text-in-any-order
  (let ((names '("Sukkerspinnmaskin – Super Floss")))
    (is (eql 45 (search-match (q "floss super") :names names)))
    (is (eql 45 (search-match (q "SUPER sukker") :names names)) "case")
    (is (eql 25 (search-match (q "loss pinn") :names names)) "a part of a word")
    (is (null (search-match (q "floss mega") :names names)) "a word missing")
    (is (eql 10 (search-match (q "floss pink") :names names :texts '("A pink one")))
        "a word found only in the other texts")
    (is (null (search-match (q "") :names names)) "nothing typed finds nothing")))

(test a-name-scores-by-where-it-matched
  (let ((names '("Nordvik Bakery Ltd")))
    (is (eql 80 (search-match (q "nordvik bakery ltd") :names names)))
    (is (eql 60 (search-match (q "Nordvik Ba") :names names)))
    (is (eql 45 (search-match (q "bak nord") :names names)))
    (is (eql 25 (search-match (q "ordvik") :names names)))
    (is (eql 10 (search-match (q "nordvik") :names '("Fjord Events")
                                            :texts '("post@nordvik.example")))))
  (is (eql 80 (search-match (q "bjorn") :names '("Bjørn"))) "compared folded"))

(test identifiers-match-whole-or-by-their-start
  (is (eql 100 (search-match (q "412 34 567") :identifiers '("41234567"))) "spaces")
  (is (eql 100 (search-match (q "#1042") :identifiers '("1042"))) "signs")
  (is (eql 100 (search-match (q "Kari@Example.no") :identifiers '("kari@example.no"))))
  (is (eql 90 (search-match (q "104") :identifiers '("1042"))))
  (is (eql 90 (search-match (q "412 34") :identifiers '("412 34 567"))) "a phone's start")
  (is (null (search-match (q "kari") :identifiers '("kari@example.no")))
      "the start of an email does not count")
  (is (null (search-match (q "10") :identifiers '("1042"))) "a start of two characters")
  (is (null (search-match (q "042") :identifiers '("1042"))) "not inside")
  (is (eql 100 (search-match (q "kari") :names '("Kari Nordmann") :identifiers '("kari")))
      "the best of the two ways")
  (is (eql 60 (search-match (q "kari") :names '("Kari Nordmann") :identifiers '("ola"))))
  (is (null (search-match (q "1042") :names '() :texts '() :identifiers '(nil ""))))
  (is (null (search-match (q "%") :names '("Kari") :identifiers '("kari"))) "«%» is not everything")
  (is (eql 80 (search-match (q "50%") :names '("50%"))) "and a sign is itself"))

(defparameter +search-letters-to-try+ "abcdeéfghijklmnoøpqrstuvwxyzæå"
  "The letters the property test builds words of.")

(defun random-word (random &key (from 2) (to 8))
  (coerce (loop repeat (+ from (random (- to from) random))
                collect (char +search-letters-to-try+
                              (random (length +search-letters-to-try+) random)))
          'string))

(defun dressed (word random)
  "WORD as a person might type it: in upper case, or with its letters
folded away, or as it is."
  (case (random 3 random)
    (0 (string-upcase word))
    (1 (search-fold word))
    (t word)))

(defun shuffled (list random)
  (let ((vector (coerce list 'vector)))
    (loop for i from (1- (length vector)) downto 1
          do (rotatef (aref vector i) (aref vector (random (1+ i) random))))
    (coerce vector 'list)))

(test random-records-are-found-by-their-own-words-and-not-by-others
  (let ((random (sb-ext:seed-random-state 6400)))
    (dotimes (i 2000)
      (let* ((name-words (loop repeat (1+ (random 4 random)) collect (random-word random)))
             (text-words (loop repeat (random 4 random) collect (random-word random)))
             (names (list (format nil "~{~a~^ ~}" name-words)))
             (texts (list (format nil "~{~a~^, ~}" text-words)))
             (own (shuffled (append name-words text-words) random))
             (some (subseq own 0 (1+ (random (length own) random))))
             (typed (format nil "~{~a~^ ~}" (mapcar (lambda (w) (dressed w random)) some))))
        (is (search-match (q typed) :names names :texts texts)
            "~s finds ~s ~s" typed names texts)
        (let ((starts (format nil "~{~a~^ ~}"
                              (mapcar (lambda (w) (subseq w 0 (1+ (random (length w) random))))
                                      some))))
          (is (search-match (q starts) :names names :texts texts)
              "the words' starts ~s find ~s ~s" starts names texts))
        (let ((other (random-word random :from 3 :to 9))
              (all (search-fold (format nil "~a ~a" (first names) (first texts)))))
          (unless (search (search-fold other) all)
            (is (null (search-match (q (format nil "~a ~a" typed other))
                                    :names names :texts texts))
                "~s with ~s, in neither ~s nor ~s, finds nothing" typed other names texts)))))))

;;; ------------------------------------------------------------------
;;; The marks (criterion 3)

(test the-marks-cover-the-stored-characters-each-word-matched
  (is (equal '((0 . 4)) (search-mark-ranges (q "kafe") "Kafé Øst")))
  (is (equal '((0 . 5)) (search-mark-ranges (q "bjorn") "Bjørn Åsen")))
  (is (equal '((0 . 5) (6 . 9)) (search-mark-ranges (q "ase bjorn") "Bjørn Åsen")))
  (is (equal '((6 . 10)) (search-mark-ranges (q "aasen") "Bjørn Åsen")) "«aa» marks «Å»")
  (is (equal '((8 . 11)) (search-mark-ranges (q "ost") "Kostnad Ostehuset"))
      "a word's start before its first match anywhere")
  (is (equal '((0 . 7)) (search-mark-ranges (q "nord nordvik") "Nordvik"))
      "overlapping marks join")
  (is (null (search-mark-ranges (q "zebra") "Nordvik")))
  (let ((html (tun.html:render-html
               (tun.ui:search-results (:query "kafe" :items '((:kind "customer" :label "Customer"
                                                               :icon :users :title "Kafé Øst"
                                                               :href "/customers/c1")))))))
    (is (search "<mark>Kafé</mark> Øst" html))))

;;; ------------------------------------------------------------------
;;; The seam (criteria 1, 4, 5)

(defvar *search-test-results* nil
  "What SEARCH-TEST-FEATURE's method finds: a function of the query and the
actor answering results, or NIL for none.")

(defclass search-test-feature () ()
  (:documentation "A client's feature that finds what *SEARCH-TEST-RESULTS* says."))

(defmethod search-records ((app search-test-feature) query actor)
  (append (and *search-test-results* (funcall *search-test-results* query actor))
          (call-next-method)))

(define-application search-test-app (search-test-feature))

(define-application search-plain-app ()
  (:modules dashboard))

(tun.web:define-page search-test-page ("test-search-page" :title "Found" :navigation nil)
    (method path form query)
  (values 200 "Found" (list '(:p "found"))))

(tun.web:define-page search-test-admin-page ("test-search-admin" :title "Found" :policy :admin
                                                                 :navigation nil)
    (method path form query)
  (values 200 "Found" (list '(:p "found"))))

(defun test-result (title href &key (kind "thing") (score 50))
  (make-search-result :kind kind :label "Thing" :icon :file :title title :href href
                      :score score))

(defun found (tool-json)
  (map 'list (lambda (item) (jget item "title")) (jget tool-json "items")))

(defun search-as (actor text &rest arguments)
  (found (apply #'call-ok "search" actor "query" text arguments)))

(test the-seam-is-tuns-traced-and-listed
  (is (eq (find-symbol "SEARCH-RECORDS" '#:tun) 'search-records) "a client reaches it in TUN")
  (dolist (name '("SEARCH-ENTITY" "SEARCH-MATCH" "MAKE-SEARCH-RESULT" "SEARCH-QUERY-KINDS"))
    (is (find-symbol name '#:tun) "~a is in TUN" name))
  (is (eq 'traced-protocol (sb-pcl::method-combination-type-name
                            (sb-mop:generic-function-method-combination #'search-records))))
  (is (find 'search-records *extension-protocols* :key #'extension-protocol-name))
  (with-test-app ()
    (is (find "search" (coerce (jget (call-ok "registry_describe" "admin:jonas") "extension_points")
                               'list)
              :key (lambda (item) (jget item "name")) :test #'equal)
        "the registry names the seam")
    (is (find "search_records" (coerce (jget (call-ok "introspect_extensions" "admin:jonas") "items")
                                       'list)
              :key (lambda (item) (jget item "target")) :test #'equal)
        "introspect_extensions lists the modules' methods on it")))

(test a-modules-results-and-the-clients-are-both-kept-the-clients-first
  (let ((*search-test-results*
          (lambda (query actor)
            (declare (ignore actor))
            (list (make-search-result :kind "thing" :label "Thing" :icon :file
                                      :title "Kari's thing" :href "/test-search-page/1"
                                      :score (search-match query :names '("Kari Nordmann")))))))
    (with-test-app (:class 'search-test-app)
      (call-ok "customers_create" "employee:anna" "name" "Kari Nordmann" "email" "k@example.no")
      (is (equal '("Kari's thing" "Kari Nordmann") (search-as "employee:anna" "kari nordmann"))
          "equal scores: the client's kind first, then the module's"))))

(test the-default-finds-nothing-and-an-application-without-contributors-has-none
  (with-test-app (:class 'search-test-app)
    (is (null (search-as "employee:anna" "nord")) "no records, no client results: nothing"))
  (is (not (search-contributors-p (make-instance 'search-plain-app)))
      "an application enabling no module that finds anything")
  (with-test-app (:class 'search-test-app)
    (is (search-contributors-p *app*) "the customers and orders modules find"))
  (let ((tun.web::*web-app* (make-instance 'search-plain-app)))
    (is (= 404 (tun.web::search-page :get nil (jobj) (jobj "q" "nord")))))
  (is (null (tun.web::shell-search-path (make-instance 'search-plain-app)))
      "a staff page's shell is given no search")
  (is (equal "/search" (tun.web::shell-search-path (make-instance 'search-test-app))))
  (flet ((shell (search)
           (tun.html:render-html (tun.ui:app-shell* (list :title "Nordvik" :user "employee:anna"
                                                          :logout-action "/logout"
                                                          :search search)
                                                    '(:p "page")))))
    (let ((without (shell nil))
          (with (shell "/search")))
      (dolist (marker '("data-tun-search-open" "tun-app-shell-search-row" "id=\"tun-search\""
                        "data-tun-dialog-shortcut" "aria-keyshortcuts"))
        (is (not (search marker without)) "without a search, no ~a" marker)
        (is (search marker with) "with one, ~a" marker)))))

(test only-what-the-actor-may-open-is-kept
  (let ((*search-test-results*
          (lambda (query actor)
            (declare (ignore query actor))
            (list (test-result "mine" "/test-search-page/1")
                  (test-result "admins'" "/test-search-admin/1")
                  (test-result "another site" "//example.com/x")
                  (test-result "no page" "/no-such-page/1")
                  (test-result "a customer" "/customers/cus_x")))))
    (with-test-app (:class 'search-test-app)
      (let ((*error-output* (make-string-output-stream)))
        (is (equal '("mine" "a customer") (search-as "employee:anna" "thing")))
        (let ((said (get-output-stream-string *error-output*)))
          (is (search "dropped the thing result \"admins'\"" said) "written out: ~a" said)
          (is (search "another site" said))))
      (let ((*error-output* (make-string-output-stream)))
        (is (equal '("mine" "admins'" "a customer") (search-as "admin:jonas" "thing"))
            "an admin opens the admins' page")
        (is (equal '("a customer") (search-as "viewer:vera" "thing"))
            "a viewer reads customers but does not open the employees' page")))))

(test results-come-best-first-five-of-a-kind-twenty-in-all
  (let ((results (append (loop for i below 7 collect (test-result (format nil "a~d" i) "/x"
                                                                  :kind "a" :score 50))
                         (loop for i below 3 collect (test-result (format nil "b~d" i) "/x"
                                                                  :kind "b" :score 60))
                         (loop for i below 2 collect (test-result (format nil "c~d" i) "/x"
                                                                  :kind "c" :score 50)))))
    (is (equal '("b0" "b1" "b2" "a0" "a1" "a2" "a3" "a4" "c0" "c1")
               (mapcar #'search-result-title (search-order results)))))
  (let ((many (loop for kind in '("a" "b" "c" "d" "e" "f")
                    append (loop for i below 5 collect (test-result kind "/x" :kind kind)))))
    (is (= 20 (length (search-order many))))
    (is (equal '("a" "b" "c" "d") (remove-duplicates (mapcar #'search-result-kind
                                                             (search-order many))
                                                     :test #'string= :from-end t)))))

(test the-tools-kinds-and-limit
  (with-test-app ()
    (call-ok "customers_create" "employee:anna" "name" "Kari Nordmann" "email" "kari@example.no")
    (call-ok "customers_create" "employee:anna" "name" "Kari Hansen" "email" "kh@example.no")
    (is (equal '("Kari Hansen" "Kari Nordmann") (search-as "employee:anna" "kari"))
        "the newest first among equals")
    (is (equal '("Kari Hansen") (search-as "employee:anna" "kari" "limit" 1)))
    (is (null (search-as "employee:anna" "kari" "kinds" (jarr '("order")))))
    (is (equal '("Kari Hansen" "Kari Nordmann")
               (search-as "employee:anna" "kari" "kinds" (jarr '("customer" "order")))))
    (with-application (*app*)
      (with-actor ((parse-actor "employee:anna"))
        (with-transaction (:read)
          (is (null (search-records *app* (q "kari" :kinds '("order")) *actor*))
              "the modules do not find a kind left out, before Tun drops it")
          (is (= 2 (length (search-records *app* (q "kari") *actor*)))))))
    (dolist (bad (list (list "query" "k") (list "query" (make-string 121 :initial-element #\a))
                       (list "query" "kari" "limit" 0) (list "query" "kari" "limit" 21)))
      (is (equal "invalid_input" (nth-value 1 (apply #'call "search" "employee:anna" bad)))
          "~s is refused" bad))))

;;; ------------------------------------------------------------------
;;; The modules' results (criterion 6)

(test customers-are-found-by-name-email-and-phone-orders-by-their-customer
  (with-test-app ()
    (let ((bjorn (jget (call-ok "customers_create" "employee:anna" "name" "Bjørn Åsen"
                                "email" "bjorn@asen.example" "phone" "412 34 567")
                       "id"))
          (product (jget (call-ok "products_create" "employee:anna" "name" "Telt" "kind" "rental"
                                  "unit" "stk" "unit_price_minor" 1000 "stock_tracked" nil
                                  "units_owned" 2)
                         "id")))
      (call-ok "customers_create" "employee:anna" "name" "Ola Hansen" "email" "ola@example.no")
      (let ((order (jget (call-ok "orders_create" "employee:anna" "customer_id" bjorn
                                  "event_date" "2026-12-12"
                                  "lines" (jarr (list (jobj "product_id" product "quantity" 1))))
                         "id"))
            (items (coerce (jget (call-ok "search" "employee:anna" "query" "bjorn") "items")
                           'list)))
        (is (equal '("customer" "order") (mapcar (lambda (i) (jget i "kind")) items))
            "the customer before its order")
        (destructuring-bind (customer order-item) items
          (is (equal (format nil "/customers/~a" bjorn) (jget customer "href")))
          (is (equal 60 (jget customer "score")) "the name starts with it")
          (is (equal '("bjorn@asen.example" "412 34 567") (coerce (jget customer "meta") 'list)))
          (is (equal "users" (jget customer "icon")))
          (is (equal (format nil "/orders/~a" order) (jget order-item "href")))
          (is (equal "Bjørn Åsen" (jget order-item "title")))
          (is (equal 45 (jget order-item "score")) "its customer's less 15")
          (is (equal "Order" (jget order-item "kind_label"))))
        (is (equal '("Bjørn Åsen") (search-as "employee:anna" "41234567" "kinds" (jarr '("customer")))))
        (is (equal '("Bjørn Åsen") (search-as "employee:anna" "BJORN@asen.example"
                                              "kinds" (jarr '("customer")))))
        (is (equal (list "Bjørn Åsen") (search-as "employee:anna" order "kinds" (jarr '("order"))))
            "an order by its id")))))

(test an-erased-customer-is-not-found
  (with-test-app ()
    (let ((id (jget (call-ok "customers_create" "employee:anna" "name" "Kari Nordmann"
                             "email" "kari@example.no")
                    "id")))
      (two-step "customers_erase" "admin:jonas" "id" id)
      (is (null (search-as "employee:anna" "kari" "kinds" (jarr '("customer")))))
      (is (null (search-as "employee:anna" "erased" "kinds" (jarr '("customer"))))))))

;;; ------------------------------------------------------------------
;;; The record policy (criterion 4), on Postgres

(test the-record-policy-decides-what-each-person-finds
  (if (not (postgres-available-p))
      (skip "no Postgres: run the suite under bin/with-postgres with TUN_TEST_POSTGRES set")
      (let ((*search-test-results*
              (lambda (query actor)
                (declare (ignore actor))
                (search-entity query 'memo :kind "memo" :label "Memo" :icon :file
                                           :title #'memo-text
                                           :href (lambda (memo)
                                                   (format nil "/test-search-page/~a"
                                                           (entity-id memo)))))))
        (with-test-app (:db (scratch-postgres "search") :class 'search-test-app)
          (with-application (*app*)
            (as-actor ("system" :write)
                      (dolist (memo '(("memo k1" "kari") ("memo k2" "kari") ("memo o1" "ola")))
                        (insert (make-instance 'memo :text (first memo) :author (second memo)))))
            (is (equal '("memo k2" "memo k1")
                       (search-as "employee:kari" "memo" "kinds" (jarr '("memo")))))
            (is (equal '("memo o1") (search-as "employee:ola" "memo" "kinds" (jarr '("memo")))))
            (is (= 3 (length (search-as "admin:jonas" "memo" "kinds" (jarr '("memo")))))))))))

;;; ------------------------------------------------------------------
;;; The shell (criterion 8), the page, the fragment and the tool (9)

(test the-shell-holds-the-search-for-every-role-its-dialog-last
  (with-test-server (port)
    (call-ok "customers_create" "employee:anna" "name" "Kari Nordmann" "email" "kari@example.no")
    (dolist (actor '("admin:jonas" "employee:anna" "viewer:vera"))
      (let ((page (nth-value 1 (web-request port "/customers" :jar (web-login port actor)))))
        (is (search "<a class=\"tun-button\" data-variant=\"ghost\" data-size=\"icon\" aria-label=\"Search\" href=\"/search\"" page)
            "~a: the top bar's button is a link to the page" actor)
        (is (html-has page "aria-label=\"Search\"" "data-tun-search-open" "hx-boost=\"false\""
                      "data-tun-preload=\"off\""))
        (is (search "class=\"tun-app-shell-search-row\" aria-keyshortcuts=\"Control+K Meta+K\" href=\"/search\"" page)
            "~a: the sidebar's row" actor)
        (is (search "<kbd class=\"tun-kbd\" data-tun-key=\"ctrl\">Ctrl</kbd>" page))
        (is (search "id=\"tun-search\" data-variant=\"default\" data-size=\"large\"" page))
        (is (search "data-tun-dialog-shortcut=\"Ctrl+K\"" page))
        (is (< (search "tun-confirm-dialog" page) (search "id=\"tun-search\"" page))
            "the search's dialog comes last")))))

(defclass search-own-dialog-feature () ()
  (:documentation "A client that adds its own dialog on Ctrl K to every page."))

(defmethod tun.web:staff-page-extras ((app search-own-dialog-feature))
  (list (tun.ui:dialog (:id "own-search" :title "Own search" :shortcut "Ctrl+K")
                       '(:p "own"))))

(define-application search-own-dialog-app (search-own-dialog-feature))

(test a-pages-own-ctrl-k-dialog-comes-before-the-search
  (with-test-server (port :class 'search-own-dialog-app)
    (let ((page (nth-value 1 (web-request port "/customers" :jar (web-login port "employee:anna")))))
      (is (< (search "id=\"own-search\"" page) (search "id=\"tun-search\"" page))
          "the shortcut opens the first dialog that takes it: the client's")
      (is (search "data-tun-search-open" page) "the search keeps its button"))))

(test the-page-the-fragment-and-the-tool-agree
  (with-test-server (port)
    (call-ok "customers_create" "employee:anna" "name" "Nordvik Bakery Ltd"
             "email" "post@nordvik.example")
    (call-ok "customers_create" "employee:anna" "name" "Fjord Events" "email" "nordvik@fjord.example")
    (let* ((jar (web-login port "employee:anna"))
           (page (nth-value 1 (web-request port "/search?q=nordvik" :jar jar)))
           (fragment (nth-value 1 (web-request port "/search?q=nordvik" :jar jar
                                               :headers '(("HX-Request" . "true")
                                                          ("HX-Request-Type" . "partial")))))
           (tool (search-as "employee:anna" "nordvik")))
      (is (equal '("Nordvik Bakery Ltd" "Fjord Events") tool))
      (dolist (html (list page fragment))
        (is (< (search "<mark>Nordvik</mark> Bakery Ltd" html) (search "Fjord Events" html))
            "the same results in the same order"))
      (is (search "<form class=\"tun-search-page-form\" method=\"get\" action=\"/search\" role=\"search\"" page))
      (is (search "<h1" page))
      (is (not (search "<h1" fragment)) "the fragment is the list alone")
      (is (search "role=\"listbox\"" fragment) "the dialog's list")
      (is (search "data-tun-search-query=\"nordvik\"" fragment) "it says what it answers")
      (is (search "Customer · post@nordvik.example" page) "the meta line starts with the kind")
      (is (search "href=\"/customers/" page))
      (let ((none (nth-value 1 (web-request port "/search?q=zebra" :jar jar))))
        (is (search "No results for «zebra»" none)))
      (let ((short (nth-value 1 (web-request port "/search?q=n" :jar jar))))
        (is (not (search "No results" short)) "under two characters, nothing")
        (is (not (search "tun-search-results-list" short)))))))

(test the-search-in-norwegian
  (with-language ("nb")
    (let ((html (tun.html:render-html (tun.ui:search-dialog (:value "zebra" :items '())))))
      (is (html-has html "Ingen treff på «zebra»" "Søket feilet. Prøv igjen." ">Søk<")))))

;;; ------------------------------------------------------------------
;;; The CSS (criterion 10)

(defun component-css-text (name)
  (tun.ui:component-css (tun.ui:find-component name)))

(test the-marked-row-changes-its-ground-not-its-size
  (let ((css (component-css-text 'tun.ui:search-results)))
    (is (cl-ppcre:scan "\\[aria-selected='true'\\] \\{\\s*background-color: var\\(--accent\\);\\s*box-shadow: inset 0 0 0 1px var\\(--border-strong\\);\\s*\\}" css))
    (is (cl-ppcre:scan "& mark \\{\\s*padding: 0;\\s*background-color: color-mix\\(in oklab, var\\(--foreground\\) 14%, transparent\\);" css))
    (is (search "&:active { background-color: var(--pressed); transition: none; }" css))))

(test the-large-dialog-is-a-fixed-box-and-only-the-results-scroll
  (let ((css (component-css-text 'tun.ui:dialog)))
    (is (cl-ppcre:scan "&\\[data-size='large'\\] \\{\\s*width: min\\(40rem, calc\\(100% - var\\(--spacing\\) \\* 8\\)\\);\\s*max-width: none;\\s*height: min\\(36rem, calc\\(100dvh - var\\(--spacing\\) \\* 16\\)\\);" css)))
  (let ((css (component-css-text 'tun.ui:search-dialog)))
    (is (cl-ppcre:scan "\\.tun-search-dialog-results \\{\\s*flex: 1;\\s*min-height: 0;[^}]*overflow-y: auto;" css))
    (is (search "& .tun-search-dialog-form { flex: none; }" css))))

(test the-dialogs-field-asks-as-one-types-and-says-what-it-answers
  (let ((html (tun.html:render-html (tun.ui:search-dialog ()))))
    (is (html-has html "hx-get=\"/search\"" "hx-trigger=\"input changed delay:150ms\""
                  "hx-target=\"#tun-search-results\"" "hx-swap=\"innerHTML\""
                  "hx-sync=\"this:replace\"" "role=\"combobox\"" "aria-controls=\"tun-search-results\""
                  "autocomplete=\"off\"" "data-tun-search-failed=\"The search failed. Try again.\""
                  "<form class=\"tun-search-dialog-form\" method=\"get\" action=\"/search\" role=\"search\"")))
  (let ((script (tun.ui:component-script (tun.ui:find-component 'tun.ui:search-dialog))))
    (is (not (search "setTimeout" script)) "the pause is htmx's own")
    (is (not (search ":popover-open" script)))
    (is (not (search ":modal" script)))))

;;; ------------------------------------------------------------------
;;; Speed (criterion 7)

(defun time-search-ms (text)
  "The server's time for the search tool with TEXT, in milliseconds."
  (let ((start (get-internal-real-time)))
    (call-ok "search" "employee:anna" "query" text)
    (/ (* 1000 (- (get-internal-real-time) start)) internal-time-units-per-second)))

(defun many-customers (count)
  (with-application (*app*)
    (as-actor ("system" :write)
              (dotimes (i count)
                (insert (make-instance 'tun.customers:customer
                                       :name (format nil "Kunde ~d Nordmann" i)
                                       :email (format nil "kunde~d@example.no" i)
                                       :phone (format nil "9~7,'0d" i)))))))

(test two-thousand-customers-are-searched-within-100-ms
  (flet ((measure (label)
           (many-customers 2000)
           (time-search-ms "kunde")      ; once to warm up
           (let ((times (sort (loop repeat 5 collect (time-search-ms "nordmann 19")) #'<)))
             (format t "~&;; search of 2000 customers, ~a: ~{~,1f~^ ~} ms~%" label
                     (mapcar (lambda (ms) (float ms)) times))
             (is (< (third times) 100) "~a: ~,1f ms" label (float (third times))))))
    (with-test-app () (measure "memory"))
    (when (postgres-available-p)
      (with-test-app (:db (scratch-postgres "search_speed")) (measure "postgres")))))


;;; ------------------------------------------------------------------
;;; The plain rule, as core 2.32.0 had it, which the faster rule must
;;; answer the same as (search-reads, criterion 4)

(defun plain-words (query)
  (remove "" (uiop:split-string (search-fold (search-query-text query)) :separator " ")
          :test #'string=))

(defun plain-identifier-key (text)
  (remove-if (lambda (c) (find c " +-.#()/")) (search-fold text)))

(defun plain-word-start-p (folded index)
  (or (zerop index) (not (alphanumericp (char folded (1- index))))))

(defun plain-word-starts-p (word folded)
  (loop for start = (search word folded) then (search word folded :start2 (1+ start))
        while start
        thereis (plain-word-start-p folded start)))

(defun plain-folded-texts (texts)
  (loop for text in texts
        when (and (stringp text) (plusp (length text)))
          collect (search-fold text)))

(defun plain-identifier-score (query identifiers)
  (let* ((key (plain-identifier-key (search-query-text query)))
         (number (find-if #'digit-char-p key)))
    (when (plusp (length key))
      (loop with best = nil
            for identifier in identifiers
            when (and (stringp identifier) (plusp (length identifier)))
              do (let ((candidate (plain-identifier-key identifier)))
                   (cond ((string= key candidate) (return 100))
                         ((and number (>= (length key) 3) (< (length key) (length candidate))
                               (string= key candidate :end2 (length key)))
                          (setf best 90))))
            finally (return best)))))

(defun plain-names-score (query names)
  (let ((whole (search-fold (search-query-text query)))
        (words (plain-words query)))
    (flet ((in-names-p (test)
             (every (lambda (word) (some (lambda (name) (funcall test word name)) names))
                    words)))
      (cond ((member whole names :test #'string=) 80)
            ((some (lambda (name) (and (<= (length whole) (length name))
                                       (string= whole name :end2 (length whole))))
                   names)
             60)
            ((in-names-p #'plain-word-starts-p) 45)
            ((in-names-p (lambda (word name) (search word name))) 25)
            (t 10)))))

(defun plain-search-match (query &key names texts identifiers)
  (let* ((names (plain-folded-texts names))
         (all (append names (plain-folded-texts texts)))
         (words (plain-words query))
         (by-words (and words
                        (every (lambda (word) (some (lambda (text) (search word text)) all))
                               words)
                        (plain-names-score query names))))
    (let ((by-identifier (plain-identifier-score query identifiers)))
      (if (and by-words by-identifier) (max by-words by-identifier) (or by-identifier by-words)))))

(defun plain-identifier-mark-range (query text)
  (let ((key (plain-identifier-key (search-query-text query))))
    (when (plusp (length key))
      (multiple-value-bind (folded from) (search-fold text)
        (let ((kept (loop for char across folded
                          for index from 0
                          unless (find char " +-.#()/") collect (cons char (aref from index)))))
          (when (and (<= (length key) (length kept))
                     (every (lambda (char pair) (char= char (car pair))) key kept)
                     (or (= (length key) (length kept))
                         (and (find-if #'digit-char-p key) (>= (length key) 3))))
            (cons (cdr (first kept)) (1+ (cdr (nth (1- (length key)) kept))))))))))

(defun plain-word-mark-ranges (query text)
  (multiple-value-bind (folded from) (search-fold text)
    (let ((ranges '()))
      (dolist (word (plain-words query))
        (let ((start (or (loop for at = (search word folded) then (search word folded :start2 (1+ at))
                               while at
                               when (plain-word-start-p folded at) return at)
                         (search word folded))))
          (when start
            (let ((end (+ start (length word))))
              (push (cons (aref from start)
                          (if (< end (length folded)) (aref from end) (length text)))
                    ranges)))))
      (let ((joined '()))
        (dolist (range (sort ranges #'< :key #'car) (nreverse joined))
          (if (and joined (<= (car range) (cdr (first joined))))
              (setf (cdr (first joined)) (max (cdr range) (cdr (first joined))))
              (push (cons (car range) (cdr range)) joined)))))))

(defun plain-mark-ranges (query text &key identifier)
  (or (plain-word-mark-ranges query text)
      (let ((range (and identifier (plain-identifier-mark-range query text))))
        (and range (list range)))))

(defun plain-search-results (query rows &key names texts identifiers title (less 0))
  "2.32.0's SEARCH-ENTITY over ROWS: (TITLE SCORE MATCHED) of the five best."
  (let ((scored '()))
    (dolist (row rows)
      (let ((match (plain-search-match query :names (funcall names row) :texts (funcall texts row)
                                             :identifiers (funcall identifiers row))))
        (when match (push (cons (- match less) row) scored))))
    (loop for (points . row) in (stable-sort scored #'> :key #'car)
          repeat 5
          collect (list (funcall title row) points
                        (tun.core::search-matched-text query (funcall title row) '()
                                             (remove-if-not #'stringp
                                                            (append (funcall names row)
                                                                    (funcall texts row)
                                                                    (funcall identifiers row))))))))

(defparameter +search-random-pieces+
  #("Nord" "nordvik" "AAsen" "aa" "a" "Bjørn" "kafé" "Kafe" "SO-1042" "1042" "412 34 567" "x"
    "Gården" "post@nord.example" "#7" "(22)" "  " "ab" "Ha" "rose bush" "ROSE" "Straße" "ß"
    "Æble" "œuvre" "Łódź" "ﬁne" "Ωmega" "Жук" "ı" "þing" "e" "-" "." "/" "Saab" "aaa"
    "Cafe" "50%" "90" "7" "Ola" "ola-nordmann" "Øst")
  "What the random texts and queries of the rule's property test are made of: words
folded and not, letters beyond Latin, signs, digits and runs of spaces and «a».")

(defun random-piece-text (random &key (most 3))
  (with-output-to-string (out)
    (loop repeat (1+ (random most random))
          for first = t then nil
          do (unless first
               (write-string (case (random 6 random)
                               (0 "  ") (1 (string #\Tab)) (2 (string (code-char #xA0)))
                               (3 "") (t " "))
                             out))
             (write-string (aref +search-random-pieces+
                                 (random (length +search-random-pieces+) random))
                           out)
             (when (zerop (random 8 random))
               (write-char (code-char #x301) out)))))

(test the-faster-rule-answers-as-the-plain-rule
  (let ((random (sb-ext:seed-random-state 2330))
        (compared 0))
    (dotimes (i 3000)
      (let* ((names (loop repeat (1+ (random 2 random)) collect (random-piece-text random)))
             (texts (loop repeat (random 3 random) collect (random-piece-text random)))
             (identifiers (loop repeat (random 3 random) collect (random-piece-text random :most 2)))
             (own (append names texts identifiers))
             (typed (if (zerop (random 3 random))
                        (random-piece-text random :most 2)
                        (let ((text (nth (random (length own) random) own)))
                          (subseq text 0 (min (length text) (+ 2 (random 12 random)))))))
             (query (q typed)))
        (dolist (text own)
          (is (string= (search-fold text) (tun.core::fold-to-string text))
              "the fold of ~s" text))
        (is (eql (plain-search-match query :names names :texts texts :identifiers identifiers)
                 (search-match query :names names :texts texts :identifiers identifiers))
            "«~a» against ~s ~s ~s" typed names texts identifiers)
        (unless (some #'tun.core::phone-national-start own)
          (incf compared)
          (dolist (text own)
            (is (equal (plain-mark-ranges query text :identifier t)
                       (search-mark-ranges query text :identifier t))
                "the marks of «~a» in ~s" typed text)))))
    (is (> compared 2700) "most records were compared whole: ~d" compared)))

(test search-among-finds-as-the-plain-rule-in-the-same-order
  (let ((random (sb-ext:seed-random-state 4106)))
    (dotimes (i 600)
      (let* ((rows (loop for n below 12
                         collect (jobj "id" (format nil "r~d" n)
                                       "name" (random-piece-text random)
                                       "text" (random-piece-text random)
                                       "number" (random-piece-text random :most 1))))
             (query (q (random-piece-text random :most 2)))
             (names (lambda (row) (list (jget row "name"))))
             (texts (lambda (row) (list (jget row "text"))))
             (identifiers (lambda (row) (list (jget row "number"))))
             (title (lambda (row) (jget row "name"))))
        (unless (some (lambda (row) (some #'tun.core::phone-national-start
                                          (list (jget row "name") (jget row "text")
                                                (jget row "number"))))
                      rows)
          (is (equal (plain-search-results query rows :names names :texts texts
                                                      :identifiers identifiers :title title :less 3)
                     (mapcar (lambda (result)
                               (list (search-result-title result) (search-result-score result)
                                     (search-result-matched result)))
                             (search-among query rows :kind "row" :title title :names names
                                                      :texts texts :identifiers identifiers
                                                      :href (constantly "/x")
                                                      :score (lambda (score) (- score 3)))))
              "«~a»" (search-query-text query)))))))

;;; ------------------------------------------------------------------
;;; Rows (criterion 3)

(test search-among-takes-records-json-objects-and-property-lists
  (let ((plists (list (list :id "p1" :name "Kari Nordmann" :number "SO-1042")
                      (list :id "p2" :name "Ola Nordmann" :number "SO-1043"))))
    (flet ((found (rows &rest keys)
             (mapcar (lambda (result)
                       (list (search-result-title result) (search-result-score result)
                             (search-result-id result) (search-result-href result)))
                     (apply #'search-among (q "nordmann") rows :kind "row" :href (constantly "/x")
                            keys))))
      (is (equal '(("Ola Nordmann" 45 "p2" "/x") ("Kari Nordmann" 45 "p1" "/x"))
                 (found plists :title (lambda (row) (getf row :name))))
          "property lists, the newest first among equals, the id by :id")
      (is (equal '(("Ola Nordmann" 45 "p2" "/x") ("Kari Nordmann" 45 "p1" "/x"))
                 (found (mapcar (lambda (row) (jobj "id" (getf row :id) "name" (getf row :name)))
                                plists)
                        :title (lambda (row) (jget row "name"))))
          "JSON objects, the id by \"id\"")
      (is (equal '(("Kari Nordmann" 45 "K" "/x"))
                 (found plists :title (lambda (row) (getf row :name))
                               :keep (lambda (row) (string= "p1" (getf row :id)))
                               :id (lambda (row) (string-upcase (subseq (getf row :name) 0 1)))))
          "KEEP, and ID's own function")
      (is (null (apply #'search-among (q "nordmann" :kinds '("order")) plists
                       (list :kind "row" :title #'identity :href (constantly "/x"))))
          "a kind not asked for")
      (let ((result (first (search-among (q "so-1042") plists
                                         :kind "row" :title (lambda (row) (getf row :name))
                                         :identifiers (lambda (row) (list (getf row :number)))
                                         :href (constantly "/x")))))
        (is (equal "SO-1042" (search-result-matched result)) "what it was found by")
        (is (eql 100 (search-result-score result)))))
    (with-test-app ()
      (call-ok "customers_create" "employee:anna" "name" "Kari Nordmann" "email" "kari@example.no")
      (with-application (*app*)
        (as-actor ("employee:anna")
          (let ((result (first (search-among (q "kari") (select 'tun.customers:customer)
                                             :kind "customer" :title #'tun.customers:customer-name
                                             :href (constantly "/x")))))
            (is (equal "Kari Nordmann" (search-result-title result)))
            (is (string-prefix-p "cus" (search-result-id result)) "a record's id")))))))

;;; ------------------------------------------------------------------
;;; Some fields (criterion 2)

(defun call-on-every-store (name function)
  "Call FUNCTION in a fresh application on the memory store, SQLite and, when
the test server is there, Postgres, with the store's name."
  (with-test-app () (funcall function "memory"))
  (with-test-app (:db (namestring (scratch-path name))) (funcall function "sqlite"))
  (when (postgres-available-p)
    (with-test-app (:db (scratch-postgres name)) (funcall function "postgres"))))

(test select-reads-only-the-fields-it-is-given
  (call-on-every-store
   "search_fields"
   (lambda (store)
     (call-ok "customers_create" "employee:anna" "name" "Ola Hansen" "email" "ola@example.no"
              "phone" "+47 412 34 567")
     (call-ok "customers_create" "employee:anna" "name" "Kari Nordmann" "email" "kari@example.no")
     (with-application (*app*)
       (as-actor ("employee:anna")
         (let ((read (select 'tun.customers:customer :fields '("name" "phone")
                                                     :order-by '(("name" :asc)))))
           (is (equal '("Kari Nordmann" "Ola Hansen") (mapcar #'tun.customers:customer-name read))
               "~a: the fields, in ORDER-BY's order" store)
           (is (equal '(nil "+47 412 34 567") (mapcar #'tun.customers:customer-phone read))
               "~a: a field read empty is NIL" store)
           (is (every (lambda (customer) (string-prefix-p "cus" (entity-id customer))) read)
               "~a: the id" store)
           (is (not (slot-boundp (first read) 'tun.customers::email)) "~a: the others unbound"
               store)
           (signals unbound-slot (tun.customers:customer-email (first read))))
         (is (equal '("Ola Hansen")
                    (mapcar #'tun.customers:customer-name
                            (select 'tun.customers:customer :fields '("name" "id")
                                                            :where '(:= "email" "ola@example.no"))))
             "~a: WHERE on a field not read" store)
         (signals error (select 'tun.customers:customer :fields '("nope")))
         (is (= 2 (length (select 'tun.customers:customer :fields '("name"))))))
       (let ((partial (as-actor ("employee:anna")
                        (first (select 'tun.customers:customer :fields '("name"))))))
         (signals error (as-actor ("system" :write) (save partial)))
         (is (equal "Ola Hansen"
                    (as-actor ("employee:anna")
                      (tun.customers:customer-name (fetch 'tun.customers:customer
                                                          (entity-id partial)))))
             "~a: nothing was saved" store))))))

;;; ------------------------------------------------------------------
;;; Answering a kind in place of a module (criterion 1)

(defvar *search-reads* :off
  "While a list, the reads the store is asked for, newest first: (CLASS-NAME
MODULE FIELDS) for a select, (SQL MODULE) for a query, MODULE the one whose
method of a traced protocol runs and FIELDS the fields the select read, NIL
for whole records.")

(defmethod store-select :around (store class-name &rest keys &key &allow-other-keys)
  (declare (ignore store))
  (unless (eq *search-reads* :off)
    (push (list class-name tun.core::*protocol-method-module* (getf keys :fields))
          *search-reads*))
  (call-next-method))

(defmethod store-query :around (store sql parameters)
  (declare (ignore store parameters))
  (unless (eq *search-reads* :off)
    (push (list sql tun.core::*protocol-method-module*) *search-reads*))
  (call-next-method))

(defvar *search-replacing* '(("customer" "customers"))
  "What SEARCH-REPLACING-FEATURE's SEARCH-REPLACEMENTS answers.")

(defvar *search-replacing-extra* nil
  "When true, SEARCH-REPLACING-FEATURE also makes results as if the customers
module made them without asking.")

(defclass search-replacing-feature () ()
  (:documentation "A client's feature that finds customers its own way, for
employees and up, in place of the customers module's."))

(defmethod search-replacements ((app search-replacing-feature))
  (append *search-replacing* (call-next-method)))

(defmethod search-records ((app search-replacing-feature) query actor)
  (append (when (actor-permits-p actor :employee)
            (search-entity query 'tun.customers:customer
                           :fields '("name") :kind "customer" :label "Customer"
                           :title (lambda (customer)
                                    (format nil "Own ~a" (tun.customers:customer-name customer)))
                           :href (lambda (customer)
                                   (format nil "/test-search-page/~a" (entity-id customer)))))
          (when *search-replacing-extra*
            (let ((tun.core::*protocol-method-module* "customers"))
              (list (test-result "unasked customer" "/test-search-page/1" :kind "customer")
                    (test-result "unasked thing" "/test-search-page/2"))))
          (call-next-method)))

(define-application search-replacing-app (search-replacing-feature))

(defun reads-searching (actor text)
  "The titles ACTOR's search for TEXT finds, and the reads it made."
  (let ((*search-reads* '()))
    (let ((titles (search-as actor text)))
      (values titles (prog1 *search-reads* (setf *search-reads* :off))))))

(defun customer-reads (reads &optional module)
  "The reads of READS of the customers, by a select or a query, by MODULE if given."
  (remove-if-not (lambda (read)
                   (destructuring-bind (what by &optional fields) read
                     (declare (ignore fields))
                     (and (if (stringp what)
                              (search "customers" what)
                              (eq what 'tun.customers:customer))
                          (or (null module) (equal module by)))))
                 reads))

(defun every-search-store (name function)
  "Call FUNCTION in SEARCH-REPLACING-APP in memory and, when the test server
is there, on Postgres."
  (with-test-app (:class 'search-replacing-app) (funcall function "memory"))
  (when (postgres-available-p)
    (with-test-app (:class 'search-replacing-app :db (scratch-postgres name))
      (funcall function "postgres"))))

(test a-kind-answered-in-place-of-a-module-is-not-read-by-it-for-any-role
  (every-search-store
   "search_replaced"
   (lambda (store)
     (call-ok "customers_create" "employee:anna" "name" "Kari Nordmann" "email" "kari@example.no")
     (dolist (actor '("admin:jonas" "employee:anna" "viewer:vera"))
       (multiple-value-bind (titles reads) (reads-searching actor "kari")
         (is (null (customer-reads reads "customers"))
             "~a ~a: the customers module reads no customer: ~s" store actor reads)
         (if (equal actor "viewer:vera")
             (progn (is (null titles) "~a: the viewer finds no customer: ~s" store titles)
                    (is (null (customer-reads reads "client"))
                        "~a: nor does the feature, for a viewer" store))
             (is (equal '("Own Kari Nordmann") titles) "~a ~a: ~s" store actor titles))))
     (let ((*search-replacing* '()))
       (dolist (actor '("admin:jonas" "employee:anna" "viewer:vera"))
         (multiple-value-bind (titles reads) (reads-searching actor "kari")
           (is (= 1 (length (customer-reads reads "customers")))
               "~a ~a: without it, the module reads the customers once a search" store actor)
           (is (member "Kari Nordmann" titles :test #'equal) "~a ~a: ~s" store actor titles)))))))

(test a-replacement-silences-only-the-module-and-kind-it-names
  (with-test-app (:class 'search-replacing-app)
    (call-ok "customers_create" "employee:anna" "name" "Kari Nordmann" "email" "kari@example.no")
    (let ((*search-replacing-extra* t))
      (is (equal '("unasked thing" "Own Kari Nordmann") (search-as "employee:anna" "kari"))
          "the module's result of the kind dropped, its other kind and the client's kept"))
    (let ((*error-output* (make-string-output-stream))
          (*search-replacing* '(("customer" "client") ("customer" "no_such_module") "junk")))
      (is (equal '("Kari Nordmann" "Own Kari Nordmann") (search-as "employee:anna" "kari"))
          "an entry naming no loaded module silences nothing")
      (let ((said (get-output-stream-string *error-output*)))
        (is (search "ignored the replacement (\"customer\" \"client\")" said) "~a" said)
        (is (search "no_such_module" said))
        (is (search "\"junk\"" said))))
    (is (find "search_replacements"
              (coerce (jget (call-ok "registry_describe" "admin:jonas") "extension_points") 'list)
              :key (lambda (item) (jget item "name")) :test #'equal)
        "the registry names the seam")
    (is (find-if (lambda (item) (and (equal "search_replacements" (jget item "target"))
                                     (equal "seam" (jget item "kind"))))
                 (coerce (jget (call-ok "introspect_extensions" "admin:jonas") "items") 'list))
        "introspect_extensions lists the seam, and with it a client's methods"))
  (is (find-symbol "SEARCH-REPLACEMENTS" '#:tun))
  (is (find-symbol "SEARCH-AMONG" '#:tun))
  (is (find-symbol "SEARCH-PHONE-FORMS" '#:tun))
  (is (eq 'traced-protocol (sb-pcl::method-combination-type-name
                            (sb-mop:generic-function-method-combination #'search-replacements)))))

(test the-customers-and-orders-modules-read-only-the-fields-they-use
  (with-test-app ()
    (let ((customer (jget (call-ok "customers_create" "employee:anna" "name" "Kari Nordmann"
                                   "email" "kari@example.no")
                          "id"))
          (product (jget (call-ok "products_create" "employee:anna" "name" "Telt" "kind" "rental"
                                  "unit" "stk" "unit_price_minor" 1000 "stock_tracked" nil
                                  "units_owned" 2)
                         "id")))
      (call-ok "orders_create" "employee:anna" "customer_id" customer
               "lines" (jarr (list (jobj "product_id" product "quantity" 1))))
      (multiple-value-bind (titles reads) (reads-searching "employee:anna" "kari")
        (is (equal '("Kari Nordmann" "Kari Nordmann") titles) "the customer and its order")
        (flet ((selects (module class)
                 (mapcar #'third (remove-if-not (lambda (read)
                                                  (and (eq class (first read))
                                                       (equal module (second read))))
                                                reads))))
          (is (equal '(("name" "email" "phone" "erased"))
                     (selects "customers" 'tun.customers:customer))
              "the customers module: ~s" reads)
          (is (equal '(("customer_id" "delivery_address" "status" "event_date"))
                     (selects "orders" 'tun.orders:order))
              "the orders module's orders: ~s" reads)
          (is (equal '(("name")) (selects "orders" 'tun.customers:customer))
              "the orders module's customers' names: ~s" reads))))))

;;; ------------------------------------------------------------------
;;; Phone numbers (criterion 6)

(test a-phone-with-its-country-code-is-found-by-its-national-number
  (is (equal '("+47 912 34 567" "91234567" "091234567") (search-phone-forms "+47 912 34 567")))
  (is (equal '("0047 912 34 567" "91234567" "091234567") (search-phone-forms "0047 912 34 567")))
  (is (equal '("+44 (0)20 7946 0958" "02079460958")
             (search-phone-forms "+44 (0)20 7946 0958"))
      "«(0)» belongs to the national number")
  (is (equal '("412 34 567") (search-phone-forms "412 34 567")) "no country code")
  (is (equal '("+47") (search-phone-forms "+47")) "no number after the code")
  (is (equal '("+47 kontor") (search-phone-forms "+47 kontor")) "not a number")
  (is (null (search-phone-forms nil)))
  (is (null (search-phone-forms "")))
  (flet ((finds (typed stored)
           (search-match (q typed) :identifiers (search-phone-forms stored))))
    (dolist (typed '("91234567" "912 34 567" "+47 912 34 567" "4791234567"))
      (is (eql 100 (finds typed "+47 912 34 567")) "«~a» is it" typed))
    (is (eql 90 (finds "912 34" "+47 912 34 567")) "the start of the national number")
    (is (eql 100 (finds "030 1234567" "+49 30 1234567")) "Germany, with the trunk's 0")
    (is (eql 100 (finds "301234567" "+49 30 1234567")))
    (is (eql 100 (finds "020 7946 0958" "+44 20 7946 0958")) "the United Kingdom")
    (is (eql 100 (finds "(212) 555-0100" "+1 212 555 0100")) "the United States")
    (is (eql 100 (finds "06 1234 5678" "+39 06 1234 5678")) "Italy keeps its 0")
    (is (eql 100 (finds "41234567" "412 34 567")) "no country code: itself")
    (is (eql 90 (finds "412 34" "412 34 567")) "and its start")
    (dolist (stored '("+47 912 34 567" "+49 30 1234567" "+44 20 7946 0958" "+1 212 555 0100"
                      "412 34 567"))
      (dolist (typed '("34567" "1234"))
        (is (null (finds typed stored)) "«~a» does not find ~a from its middle" typed stored))))
  (is (equal '((4 . 14)) (search-mark-ranges (q "91234567") "+47 912 34 567" :identifier t))
      "the national part marked")
  (is (equal '((4 . 7) (8 . 10)) (search-mark-ranges (q "912 34") "+47 912 34 567" :identifier t))
      "words found are marked as words, as before")
  (is (equal '((4 . 14)) (search-mark-ranges (q "091234567") "+47 912 34 567" :identifier t)))
  (is (equal '((1 . 14)) (search-mark-ranges (q "4791234567") "+47 912 34 567" :identifier t)))
  (is (null (search-mark-ranges (q "34567") "+47 912 34 567" :identifier t)))
  (let ((html (tun.html:render-html
               (tun.ui:search-results (:query "91234567"
                                       :items '((:kind "customer" :label "Customer" :icon :users
                                                 :title "Bjørn Åsen"
                                                 :meta ("bjorn@asen.example" "+47 912 34 567")
                                                 :href "/customers/c1")))))))
    (is (search "+47 <mark>912 34 567</mark>" html) "the line marks it: ~a" html))
  (with-test-app ()
    (call-ok "customers_create" "employee:anna" "name" "Bjørn Åsen" "email" "bjorn@asen.example"
             "phone" "+47 912 34 567")
    (call-ok "customers_create" "employee:anna" "name" "Hans Müller" "email" "hans@example.de"
             "phone" "+49 30 1234567")
    (is (equal '("Bjørn Åsen") (search-as "employee:anna" "91234567")) "the customers module")
    (is (equal '("Bjørn Åsen") (search-as "employee:anna" "912 34 567")))
    (is (equal '("Hans Müller") (search-as "employee:anna" "030 1234567")))
    (is (null (search-as "employee:anna" "34567")))))

;;; ------------------------------------------------------------------
;;; Speed of every kind together (criterion 5)

(defparameter +search-body-words+
  #("leie" "telt" "bord" "stoler" "lys" "scene" "levering" "henting" "faktura" "avtale"
    "bryllup" "konfirmasjon" "jubileum" "sommerfest" "julebord" "gulv" "varme" "strøm"
    "parkering" "nøkkel" "kontakt" "adresse" "tidspunkt" "rigging" "nedrigg" "pris")
  "The words the long texts of the speed test are made of.")

(defun long-text (random words)
  "A text of WORDS words drawn by RANDOM from +SEARCH-BODY-WORDS+."
  (format nil "~{~a~^ ~}" (loop repeat words
                                collect (aref +search-body-words+
                                              (random (length +search-body-words+) random)))))

(defun inquiry-search-results (query actor)
  "A client's inquiries in the search, read through SEARCH-ENTITY with only
the fields it matches and shows."
  (declare (ignore actor))
  (search-entity query 'tun.inbox:inquiry
                 :fields '("subject" "body" "from_name" "from_email")
                 :kind "inquiry" :label "Inquiry" :icon :mail
                 :title #'tun.inbox:inquiry-subject
                 :texts (lambda (inquiry) (list (tun.inbox:inquiry-body inquiry)))
                 :identifiers (lambda (inquiry) (list (tun.inbox:inquiry-from-email inquiry)))
                 :meta (lambda (inquiry) (list (tun.inbox:inquiry-from-name inquiry)))
                 :href (lambda (inquiry) (format nil "/test-search-page/~a" (entity-id inquiry)))))

(defun many-of-every-kind (count)
  "COUNT customers with a phone with its country code, COUNT orders of them
with the six lines of an order made through orders_create, and COUNT inquiries
whose text is 200 words long."
  (let* ((first (jget (call-ok "customers_create" "employee:anna" "name" "Model Kunde"
                               "email" "model@example.no")
                      "id"))
         (product (jget (call-ok "products_create" "employee:anna" "name" "Telt" "kind" "rental"
                                 "unit" "stk" "unit_price_minor" 1000 "stock_tracked" nil
                                 "units_owned" 50)
                        "id"))
         (model (jget (call-ok "orders_create" "employee:anna" "customer_id" first
                               "event_date" "2026-12-12"
                               "lines" (jarr (loop for quantity from 1 to 6
                                                   collect (jobj "product_id" product
                                                                 "quantity" quantity))))
                      "id"))
         (random (sb-ext:seed-random-state 3300)))
    (with-application (*app*)
      (as-actor ("system" :write)
        (let ((lines (tun.orders:order-lines (fetch 'tun.orders:order model)))
              (ids '()))
          (dotimes (i count)
            (let ((customer (make-instance 'tun.customers:customer
                                           :name (format nil "Kunde ~d Nordmann" i)
                                           :email (format nil "kunde~d@example.no" i)
                                           :phone (format nil "+47 9~2,'0d ~2,'0d ~3,'0d"
                                                          (mod i 100) (mod (floor i 100) 100) i))))
              (insert customer)
              (push (entity-id customer) ids)))
          (dolist (id ids)
            (insert (make-instance 'tun.orders:order
                                   :customer-id id :lines lines
                                   :delivery-address (format nil "Storgata ~d, Oslo"
                                                             (random 200 random)))))
          (dotimes (i count)
            (insert (make-instance 'tun.inbox:inquiry
                                   :subject (format nil "Forespørsel ~d om ~a" i (long-text random 2))
                                   :body (long-text random 200)
                                   :from-name (format nil "Avsender ~d" i)
                                   :from-email (format nil "avsender~d@example.no" i)))))))))

(defun time-search-as-ms (actor text)
  "The server's time for the search tool as ACTOR with TEXT, in milliseconds."
  (let ((start (get-internal-real-time)))
    (call-ok "search" actor "query" text)
    (/ (* 1000 (- (get-internal-real-time) start)) internal-time-units-per-second)))

(defparameter +search-every-kind-limit-ms+ 90
  "The median a search of every kind may take in the speed test: under the 100
ms rule, with room over what this loop measured on Postgres while other suites
ran beside it (loops/search-reads.md, criterion 5).")

(test every-kind-of-two-thousand-records-is-searched-within-the-limit
  (let ((*search-test-results* #'inquiry-search-results))
    (flet ((measure (label)
             (many-of-every-kind 2000)
             (is (equal '("Kunde 1999 Nordmann")
                        (search-as "employee:anna" "999 19 1999" "kinds" (jarr '("customer"))))
                 "~a: a customer by the start of its national number" label)
             (time-search-as-ms "employee:anna" "kunde")      ; once to warm up
             (dolist (text '("kunde 1999" "nordmann" "julebord rigging" "zebra" "912 19"))
               (let ((times (sort (loop repeat 9 collect (time-search-as-ms "employee:anna" text))
                                  #'<)))
                 (format t "~&;; search of every kind, 2000 of each, ~a, «~a»: ~{~,1f~^ ~} ms~%"
                         label text (mapcar #'float times))
                 (is (< (fifth times) +search-every-kind-limit-ms+)
                     "~a «~a»: ~,1f ms" label text (float (fifth times)))))))
      (with-test-app (:class 'search-test-app) (measure "memory"))
      (when (postgres-available-p)
        (with-test-app (:class 'search-test-app :db (scratch-postgres "search_every_kind"))
          (measure "postgres"))))))
