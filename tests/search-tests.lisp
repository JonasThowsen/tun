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
