;;;; tests/generated-choice-tests.lisp -- the generated pages choosing a
;;;; record by typing (spec/ui.md 8, «Choosing a record»): /choices/ENTITY,
;;;; whose records under the list operation's policy and the record
;;;; policies, what it reads and how fast, a record's text, the form's
;;;; field with few and many records, its find step and the check of what is
;;;; posted, the list's :choice filter, and the specimen's choices (§7).
;;;; The record policies' test runs on Postgres when TUN_TEST_POSTGRES names
;;;; a server.

(in-package #:tun.tests)

(def-suite generated-choice :in core)
(in-suite generated-choice)

(defparameter +htmx-part+ '(("HX-Request" . "true") ("HX-Request-Type" . "partial"))
  "The headers of htmx asking for part of a page.")

(defun choice-customer (name)
  "A customer named NAME, made by the system; its id."
  (with-application (*app*)
    (as-actor ("system" :write)
      (entity-id (insert (make-instance 'tun.customers:customer
                                        :name name
                                        :email (format nil "~a@example.no"
                                                       (substitute #\. #\Space
                                                                   (string-downcase name)))))))))

(defun choice-product ()
  "A rental product; its id."
  (jget (call-ok "products_create" "employee:anna" "name" "Popcornmaskin" "kind" "rental"
                 "unit" "stk" "unit_price_minor" 150000 "stock_tracked" nil "units_owned" 20)
        "id"))

(defun choice-order (customer product)
  "A draft order for CUSTOMER of one PRODUCT; its id."
  (jget (call-ok "orders_create" "employee:anna" "customer_id" customer "event_date" "2026-06-20"
                 "lines" (jarr (list (jobj "product_id" product "quantity" 1))))
        "id"))

(defun element-html (html id &optional (tag "select"))
  "The element TAG whose id is ID in HTML, from its start to its end tag."
  (let ((start (search (format nil "id=\"~a\"" id) html)))
    (when start
      (let ((open (position #\< html :end start :from-end t)))
        (subseq html open (+ (search (format nil "</~a>" tag) html :start2 start)
                             (length tag) 3))))))

(defun tag-html (html id)
  "The start tag of the element whose id is ID in HTML."
  (let ((start (search (format nil "id=\"~a\"" id) html)))
    (when start
      (subseq html (position #\< html :end start :from-end t)
              (1+ (position #\> html :start start))))))

(defun option-count (html id)
  "How many options the select ID in HTML holds, its empty first included."
  (occurrences "<option" (or (element-html html id) "")))

(defun orders-made ()
  (jget (call-ok "orders_list" "employee:anna") "items"))

(defun median-ms (function &optional (times 9))
  "The median of TIMES calls of FUNCTION, in milliseconds."
  (let ((all (sort (loop repeat times
                         collect (let ((start (get-internal-real-time)))
                                   (funcall function)
                                   (/ (* 1000.0 (- (get-internal-real-time) start))
                                      internal-time-units-per-second)))
                   #'<)))
    (nth (floor times 2) all)))

(defmacro as-web-actor ((actor) &body body)
  "Run BODY as ACTOR in the application's web pages, with nothing read yet."
  `(with-application (*app*)
     (let ((tun.web::*web-app* *app*)
           (tun.web::*record-choices* nil)
           (*actor* (as ,actor)))
       ,@body)))

;;; ------------------------------------------------------------------
;;; The address (criterion 1)

(test the-choices-address-answers-the-records-by-the-rule
  (with-test-server (port)
    (choice-customer "Bjørn Åsen")
    (dotimes (i 30) (choice-customer (format nil "Kunde ~d Nordmann" i)))
    (let ((jar (web-login port "employee:anna")))
      (multiple-value-bind (status fragment)
          (web-request port "/choices/customer" :parameters '(("q" . "bjorn ase"))
                                                :jar jar :headers +htmx-part+)
        (is (= 200 status))
        (is (search "data-tun-choice-query=\"bjorn ase\"" fragment))
        (is (search "<span class=\"tun-choice-options-text\">Bjørn Åsen</span>" fragment))
        (is (= 1 (occurrences "role=\"option\"" fragment)) "the one match")
        (is (not (search "<h1" fragment)) "the list alone"))
      (let ((all (nth-value 1 (web-request port "/choices/customer?q=" :jar jar
                                                                    :headers +htmx-part+))))
        (is (= 20 (occurrences "role=\"option\"" all)) "the first 20")
        (is (search "11 more. Type to narrow them." all) "the rest counted")
        (is (< (search "Bjørn Åsen" all) (search "Kunde 0 Nordmann" all))
            "in the order of their names"))
      (multiple-value-bind (status page) (web-request port "/choices/customer?q=kunde" :jar jar)
        (is (= 200 status))
        (is (search "<h1" page) "a page to any other request")
        (is (search "Choices" page)))
      (is (= 403 (web-request port "/choices/account" :jar jar)) "accounts_list is for admins")
      (is (= 200 (web-request port "/choices/account" :jar (web-login port "admin:jonas"))))
      (is (= 200 (web-request port "/choices/customer" :jar (web-login port "viewer:vera")))
          "customers_list admits a viewer")
      (dolist (path '("/choices" "/choices/no_such_entity" "/choices/memo" "/choices/customer/x"))
        (is (= 404 (web-request port path :jar jar)) "~a" path))
      (is (= 404 (web-request port "/choices/customer" :method :post :jar jar)) "a POST")
      (is (= 303 (web-request port "/choices/customer")) "someone not signed in signs in first"))))

;;; ------------------------------------------------------------------
;;; Under the record policies (criteria 2 and 5), on Postgres

(define-entity choice-note (:label "Choice note" :id-prefix "chn" :table "test_choice_notes"
                            :record-policy ((:admin t) (:employee "author = :actor_name")))
  ((name :type (string :min 1 :max 120) :required t :label "Name")
   (author :type (string :max 64) :input nil :label "Author")
   (parent :type (id choice-note) :label "Part of")))

(define-operation choice-notes-list ()
    (:entity choice-note :kind :read :policy :viewer :title "Choice notes"
     :description "The notes the caller may read.")
  (jobj "items" (jarr (mapcar #'entity->json (select 'choice-note)))))

(test the-record-policies-decide-what-a-person-chooses-and-sees-named
  (if (not (postgres-available-p))
      (skip "no Postgres: run the suite under bin/with-postgres with TUN_TEST_POSTGRES set")
      (with-test-server (port :db (scratch-postgres "choices"))
        (destructuring-bind (kari-note ola-note)
            (with-application (*app*)
              (as-actor ("system" :write)
                (list (entity-id (insert (make-instance 'choice-note :name "Karis plan"
                                                                     :author "kari")))
                      (entity-id (insert (make-instance 'choice-note :name "Olas plan"
                                                                     :author "ola"))))))
          (let ((kari (nth-value 1 (web-request port "/choices/choice_note?q="
                                                :jar (web-login port "employee:kari")
                                                :headers +htmx-part+)))
                (vera (nth-value 1 (web-request port "/choices/choice_note?q="
                                                :jar (web-login port "viewer:vera")
                                                :headers +htmx-part+))))
            (is (search "Karis plan" kari))
            (is (not (search "Olas plan" kari)) "never a record the policy hides")
            (is (zerop (occurrences "role=\"option\"" vera)) "a role without a clause chooses none"))
          (as-web-actor ("employee:kari")
            (let* ((class (find-class 'choice-note))
                   (type (field-type (find-field class "parent")))
                   (field (tun.html:render-html
                           (tun.web::form-control (tun.web::field-input-spec
                                                   (find-field class "parent") class)
                                                  "parent" "f-parent"))))
              (is (search "Karis plan" field) "her field offers her own")
              (is (not (search "Olas plan" field)))
              (is (equal kari-note (read-choice kari-note (lambda (id)
                                                            (tun.web::record-choice-text class id)))))
              (is (not (null (nth-value 1 (read-choice ola-note
                                                       (lambda (id)
                                                         (tun.web::record-choice-text class id))))))
                  "another's id is refused")
              (is (equal "Karis plan" (tun.web::reference-markup type kari-note)))
              (is (equal ola-note (tun.web::reference-markup type ola-note))
                  "another's record is shown by its id, never its name")))
          (as-web-actor ("admin:jonas")
            (is (equal "Olas plan" (tun.web::reference-markup
                                    (field-type (find-field (find-class 'choice-note) "parent"))
                                    ola-note))
                "an admin, who reaches it, sees its name"))))))

;;; ------------------------------------------------------------------
;;; One read of two fields (criterion 3)

(test the-choices-are-one-read-of-the-names
  (with-test-server (port)
    (choice-customer "Bjørn Åsen")
    (choice-customer "Kari Hansen")
    (let ((jar (web-login port "employee:anna")))
      (unwind-protect
           (progn
             (setf *search-reads* '())
             (web-request port "/choices/customer?q=bjorn" :jar jar :headers +htmx-part+))
        (let ((reads (remove 'tun.customers:customer *search-reads* :key #'first :test-not #'eq)))
          (setf *search-reads* :off)
          (is (= 1 (length reads)) "one read of the customers: ~s" reads)
          (is (equal '("name") (third (first reads))) "their names alone"))))))

;;; ------------------------------------------------------------------
;;; Fast (criterion 4)

(test two-thousand-records-are-chosen-among-within-100-ms
  (flet ((measure (label)
           (with-test-server (port :db (and (string= label "postgres")
                                            (scratch-postgres "choices_speed")))
             (many-customers 2000)
             (let ((jar (web-login port "employee:anna")))
               (flet ((ask (text)
                        (lambda () (web-request port "/choices/customer" :jar jar
                                                :parameters (list (cons "q" text))
                                                :headers +htmx-part+))))
                 (funcall (ask "kunde"))           ; once to warm up
                 (dolist (text '("kunde 19" ""))
                   (let ((ms (median-ms (ask text))))
                     (format t "~&;; /choices/customer of 2000, ~a, «~a»: ~,1f ms~%" label text ms)
                     (is (< ms 100) "~a «~a»: ~,1f ms" label text ms))))))))
    (measure "memory")
    (when (postgres-available-p) (measure "postgres"))))

(test the-names-add-little-to-the-pages-that-show-them
  (flet ((measure (label)
           (with-test-server (port :db (and (string= label "postgres")
                                            (scratch-postgres "choices_pages")))
             (let* ((product (choice-product))
                    (orders (loop for i below 10
                                  collect (choice-order (choice-customer (format nil "Kunde ~d" i))
                                                      product)))
                    (jar (web-login port "employee:anna")))
               (flet ((pages ()
                        (web-request port "/orders" :jar jar)    ; once to warm up
                        (list (median-ms (lambda () (web-request port "/orders" :jar jar)))
                              (median-ms (lambda ()
                                           (web-request port (format nil "/orders/~a"
                                                                     (first orders))
                                                        :jar jar))))))
                 (let ((few (pages)))
                   (many-customers 1990)
                   (let ((many (pages)))
                     (format t "~&;; the orders' list and an order's page, ~a, 10 and 2000 ~
                                customers: ~{~,1f~^ ~} and ~{~,1f~^ ~} ms~%" label few many)
                     (loop for page in '("the orders' list" "an order's page")
                           for before in few
                           for after in many
                           do (is (< (- after before) 50) "~a, ~a: ~,1f ms more"
                                  label page (- after before))))))))))
    (measure "memory")
    (when (postgres-available-p) (measure "postgres"))))

;;; ------------------------------------------------------------------
;;; A record's text (criterion 5)

(test a-record-past-the-first-hundred-is-named
  (with-test-server (port)
    (let ((product (choice-product)))
      (dotimes (i 104) (choice-customer (format nil "Kunde ~d Nordmann" i)))
      (let* ((zelda (choice-customer "Zelda Zahl"))
             (order (choice-order zelda product))
             (jar (web-login port "employee:anna")))
        (is (search "Zelda Zahl" (nth-value 1 (web-request port "/orders" :jar jar)))
            "in the orders' table")
        (is (search "Zelda Zahl" (nth-value 1 (web-request port (format nil "/orders/~a" order)
                                                           :jar jar)))
            "on the order's page")))))

(test a-record-the-person-may-not-choose-is-shown-by-its-id
  (with-test-app ()
    (let ((account (jget (call-ok "accounts_create" "admin:root" "name" "kari" "kind" "person"
                                  "role" "employee" "email" "kari@example.no")
                         "id"))
          (type (field-type (find-field (find-class 'tun.auth:access-token) "account_id"))))
      (as-web-actor ("employee:anna")
        (is (equal account (tun.web::reference-markup type account))
            "accounts_list does not admit an employee"))
      (as-web-actor ("admin:jonas")
        (is (equal "kari" (tun.web::reference-markup type account)))))))

;;; ------------------------------------------------------------------
;;; The form and the filter, few and many (criteria 6, 7, 8)

(test the-form-and-the-filter-hold-few-and-ask-for-many
  (with-test-server (port)
    (choice-product)
    (dotimes (i 30) (choice-customer (format nil "Kunde ~d Nordmann" i)))
    (let* ((jar (web-login port "employee:anna"))
           (page (nth-value 1 (web-request port "/orders" :jar jar))))
      (is (search "<select class=\"tun-choice-input-select\" name=\"customer_id\"" page)
          "the customer field is a choice-input")
      (is (= 31 (option-count page "orders_create-customer_id")) "every customer with the page")
      (is (not (search "hx-get=\"/choices/customer\"" page)) "and nothing asked")
      (is (search "<select class=\"tun-choice-input-select\" name=\"lines[0][product_id]\"" page)
          "a line's product field too")
      (is (= 31 (option-count page "tun-list-toolbar-customer_id-choice"))
          "the list's filter holds every customer, after «All»")
      (choice-customer "Bjørn Åsen")
      (let ((page (nth-value 1 (web-request port "/orders" :jar jar))))
        (is (search "hx-get=\"/choices/customer\""
                    (tag-html page "orders_create-customer_id-search"))
            "with 31 the field asks")
        (is (= 1 (option-count page "orders_create-customer_id")) "and holds nothing else")
        (is (search "hx-get=\"/choices/customer\""
                    (tag-html page "tun-list-toolbar-customer_id-search"))
            "the filter asks too")
        (is (= 1 (option-count page "tun-list-toolbar-customer_id-choice")) "«All» alone")))))

(test the-form-knows-only-the-chosen-and-what-a-find-found
  (with-test-server (port)
    (let ((product (choice-product)))
      (dotimes (i 30) (choice-customer (format nil "Kunde ~d Nordmann" i)))
      (let ((bjorn (choice-customer "Bjørn Åsen"))
            (jar (web-login port "employee:anna")))
        (multiple-value-bind (status page)
            (web-request port "/orders" :method :post :jar jar
                                        :parameters `(("customer_id" . ,bjorn)
                                                      ("event_date" . "2026-06-20")))
          (is (= 422 status) "no lines: the operation refuses")
          (let ((select (element-html page "orders_create-customer_id")))
            (is (= 2 (occurrences "<option" select)) "the empty option and the posted one")
            (is (search (format nil "<option value=\"~a\" selected>Bjørn Åsen</option>" bjorn)
                        select))))
        (multiple-value-bind (status page)
            (web-request port "/orders" :method :post :jar jar
                                        :parameters `(("tun-find" . "customer_id")
                                                      ("customer_id-find" . "bjorn")
                                                      ("event_date" . "2026-06-20")
                                                      ("lines[0][product_id]" . ,product)
                                                      ("lines[0][quantity]" . "1")))
          (is (= 200 status) "a find step")
          (let ((select (element-html page "orders_create-customer_id")))
            (is (= 2 (occurrences "<option" select)) "the empty option and the one match")
            (is (search ">Bjørn Åsen</option>" select)))
          (is (search "1 found" page))
          (is (not (search "tun-error-summary" page)) "nothing refused")
          (is (zerop (length (orders-made))) "nothing saved"))))))

(test a-posted-id-that-is-none-of-the-choices-is-refused-at-its-field
  (with-test-server (port)
    (let* ((product (choice-product))
           (customer (choice-customer "Kari Hansen"))
           (jar (web-login port "employee:anna")))
      (flet ((post (customer product)
               (web-request port "/orders" :method :post :jar jar
                                           :parameters `(("customer_id" . ,customer)
                                                         ("event_date" . "2026-06-20")
                                                         ("lines[0][product_id]" . ,product)
                                                         ("lines[0][quantity]" . "1")))))
        (multiple-value-bind (status page) (post "cus_nope" product)
          (is (= 422 status))
          (is (search "tun-error-summary" page))
          (is (search "must be one of the choices" page))
          (is (search "href=\"#orders_create-customer_id\"" page) "the summary links to the field")
          (is (zerop (length (orders-made))) "the operation is not called"))
        (multiple-value-bind (status page) (post customer "prd_nope")
          (is (= 422 status))
          (is (search (format nil "href=\"#~a\""
                              (tun.web::control-id "orders_create" "lines[0][product_id]"))
                      page)
              "a line's product too")
          (is (zerop (length (orders-made)))))
        (is (= 303 (post customer product)) "one of the choices makes the order")
        (is (= 1 (length (orders-made))))))))

;;; ------------------------------------------------------------------
;;; The list's filter (criterion 9)

(test the-list-filters-by-a-chosen-record-under-the-inputs-name
  (with-test-server (port)
    (let* ((product (choice-product))
           (kari (choice-customer "Kari Hansen"))
           (ola (choice-customer "Ola Nordmann"))
           (karis (choice-order kari product))
           (olas (choice-order ola product))
           (jar (web-login port "employee:anna")))
      (let ((page (nth-value 1 (web-request port (format nil "/orders?customer_id=~a" kari)
                                            :jar jar))))
        (is (search karis page))
        (is (not (search olas page)) "the list is called with the address's id")
        (is (search "<span class=\"tun-list-toolbar-filter-value\">Kari Hansen</span>" page)
            "its button names the customer")
        (is (search "data-kind=\"choice\" data-in-use=\"true\" data-tun-list-toolbar-filter=\"customer_id\""
                    page)))
      (let ((page (nth-value 1 (web-request port "/orders?customer_id=cus_nope" :jar jar))))
        (is (search "Nothing matches" page) "an id that is none of the choices goes as given")
        (is (search "href=\"/orders?customer_id=&amp;status=&amp;dateless=&amp;tag=&amp;from=&amp;to=\""
                    page)
            "«Reset» names it")
        (is (search "<span class=\"tun-list-toolbar-filter-value\">cus_nope</span>" page)
            "and its button shows the id")))))

;;; ------------------------------------------------------------------
;;; Where there is nothing to choose from (criterion 10)

(test an-id-no-one-may-choose-among-stays-a-text-field
  (with-test-server (port)
    (let ((memo (field-type (find-field (find-class 'memo-share) "memo_id")))
          (account (field-type (find-field (find-class 'tun.auth:access-token) "account_id"))))
      (as-web-actor ("employee:anna")
        (dolist (type (list memo account))
          (let ((html (tun.html:render-html
                       (tun.web::form-control (tun.web::make-input-spec :name "x" :label "X"
                                                                        :type type)
                                              "x" "f-x"))))
            (is (search "class=\"tun-text-input\"" html) "~a: a text field" type)
            (is (not (search "data-tun-choice" html))))))
      (flet ((account-filter (actor)
               (as-web-actor (actor)
                 (tun.web::list-filter-kind
                  (find "account_id" (operation-parameters (find-operation-by-tool "tokens_list"))
                        :key #'parameter-json-name :test #'string=)))))
        (is (null (account-filter "employee:anna")) "no filter for one who may not list accounts")
        (is (eq :choice (account-filter "admin:jonas"))))
      (call-ok "accounts_create" "admin:root" "name" "agent-1" "kind" "agent" "role" "employee")
      (let ((page (nth-value 1 (web-request port "/access" :jar (web-login port "admin:jonas")))))
        (is (search "name=\"account_id\"" page))
        (is (not (search "tun-choice-input-select\" name=\"account_id\"" page))
            "the choices a page gives stay a select")))))

;;; ------------------------------------------------------------------
;;; The specimen (criterion 13)

(test the-specimens-choices-are-choice-answers
  (with-test-server (port)
    (let ((page (nth-value 1 (web-request port "/ui/choice-input/options?q="))))
      (is (search "<h1" page) "a page to a request for a whole page")
      (is (search "16 more. Type to narrow them." page) "eight shown, the rest counted"))
    (let ((fragment (nth-value 1 (web-request port "/ui/choice-input/options?q="
                                              :headers +htmx-part+))))
      (is (not (search "<h1" fragment)) "the list alone to htmx")
      (is (= 8 (occurrences "role=\"option\"" fragment))))
    (is (search "id=\"specimen-found-text\" data-tun-choice-text>Bjørn Åsen</span>"
                (nth-value 1 (web-request port "/ui/choice-input")))
        "the find step's example is chosen")))
