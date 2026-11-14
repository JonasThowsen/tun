;;;; tests/form-nits-tests.lisp -- a form's alert naming its fields by their
;;;; labels (spec/ui.md 8, «A client's pages»), a row's field by its row, a
;;;; blank choice's words («Forms»), the asked choice's default submit button
;;;; (§6, choice-input, «Enter saves») and a module's shape of its records'
;;;; choice, record-choice («Choosing a record»).  The choice's tests run on
;;;; Postgres too when TUN_TEST_POSTGRES names a server.

(in-package #:tun.tests)

(def-suite form-nits :in core)
(in-suite form-nits)

(defun field-refusal (&rest paths-and-messages)
  "An invalid_input error document with a field error for each PATH MESSAGE."
  (jobj "error" (jobj "code" "invalid_input" "message" "Something needs correcting"
                      "fields" (jarr (loop for (path message) on paths-and-messages by #'cddr
                                           collect (jobj "field" path "message" message))))))

(defun alert-html (json &rest keys)
  (tun.html:render-html (apply #'tun.web:error-alert json keys)))

(defun alert-lines (html)
  "The texts of the alert HTML's lines, as a person reads them."
  (let ((lines '()))
    (cl-ppcre:do-register-groups (line) ("<li>(.*?)</li>" html)
      (push (cl-ppcre:regex-replace-all "<[^>]*>" line "") lines))
    (nreverse lines)))

(defun sample-fields ()
  "One field of each kind a form holds, each with a fixed id."
  (list (tun.ui:text-input (:label "Title" :name "title" :id "f-title"))
        (tun.ui:date-input (:label "Date" :name "starts_on" :id "f-starts" :optional t))
        (tun.ui:select (:label "Customer" :name "customer_id" :id "f-customer"
                    :options '(("cus_1" "Kari Hansen"))))
        (tun.ui:choice-input (:label "Venue" :name "venue_id" :id "f-venue" :source "/venues"))
        (tun.ui:money-input (:label "Price" :name "price" :id "f-price"))
        (tun.ui:textarea (:label "Note" :name "note" :id "f-note" :optional t))
        (tun.ui:checkbox (:label "Paid" :name "paid" :id "f-paid"))
        (tun.ui:input-group (:label "Discount" :name "discount" :id "f-discount" :suffix "%"))
        (tun.ui:radios (:legend "Delivery" :name "delivery" :id "f-delivery"
                    :choices '(("pickup" "Picked up") ("sent" "Sent"))))
        (tun.ui:checkboxes (:legend "Days" :name "days" :id "f-days"
                        :choices '(("mon" "Mon") ("tue" "Tue"))))
        (tun.ui:file-input (:label "Files" :name "files" :id "f-files" :optional t))))

;;; ------------------------------------------------------------------
;;; The alert names fields by their labels (criteria 1 to 3)

(test an-alert-names-each-field-by-its-label-and-links-to-it
  (let* ((json (field-refusal "title" "must be filled in"
                        "starts_on" "must be a date, such as 21 Oct 2026"
                        "customer_id" "must be filled in"
                        "venue_id" "must be one of the choices"
                        "price" "must be an amount"
                        "note" "cannot be longer than 500 characters"
                        "paid" "must be true or false"
                        "discount" "must be a number"
                        "delivery" "must be filled in"
                        "days[1]" "is not one of the choices"
                        "files" "The file is larger than 10 MB."))
         (html (alert-html json :fields (sample-fields))))
    (is (equal '("Title must be filled in"
                 "Date must be a date, such as 21 Oct 2026"
                 "Customer must be filled in"
                 "Venue must be one of the choices"
                 "Price must be an amount"
                 "Note cannot be longer than 500 characters"
                 "Paid must be true or false"
                 "Discount must be a number"
                 "Delivery must be filled in"
                 "Days is not one of the choices"
                 "The file is larger than 10 MB.")
               (alert-lines html)))
    (dolist (id '("f-title" "f-starts" "f-customer" "f-venue" "f-price" "f-note" "f-paid"
                  "f-discount" "f-files"))
      (is (search (format nil "href=\"#~a\"" id) html) "a link to ~a" id))
    (is (search "href=\"#f-delivery\"" html) "radios: their first")
    (is (search "href=\"#f-days\"" html) "checkboxes: their first")
    (is (= 11 (occurrences "data-tun-field-link" html)))
    (is (not (search "(optional)" html)) "a label without its «(optional)»")
    (is (search "data-code=\"invalid_input\"" html))))

(test an-alert-names-fields-in-the-pages-language
  (with-language ("nb")
    (let ((html (alert-html (field-refusal "title" (princ-to-string (tr "must be filled in"))
                                     "reported_on" "må være en dato")
                            :fields (list (tun.ui:text-input (:label "Tittel" :name "title"
                                                          :id "n-title"))
                                          (tun.ui:date-input (:label "Meldt" :name "reported_on"
                                                          :id "n-reported" :optional t))))))
      (is (equal '("Tittel må fylles ut" "Meldt må være en dato") (alert-lines html)))
      (is (not (search "(valgfritt)" html))))))

(test an-alert-names-a-rows-field-by-its-row
  (let ((in-fieldset (list (tun.ui:fieldset (:legend "Line 3")
                             (tun.ui:text-input (:label "Unit price" :name "lines[2][unit_price]"
                                             :id "l-price")))))
        (bare (list (tun.ui:text-input (:label "Unit price" :name "lines[2][unit_price]"
                                   :id "l-price")))))
    (dolist (path '("lines[2].unit_price" "lines.2.unit_price"))
      (let ((html (alert-html (field-refusal path "must be at least 0") :fields in-fieldset)))
        (is (equal '("Line 3: Unit price must be at least 0") (alert-lines html)) "~a" path)
        (is (search "href=\"#l-price\"" html))))
    (is (equal '("Row 3: Unit price must be at least 0")
               (alert-lines (alert-html (field-refusal "lines[2].unit_price" "must be at least 0")
                                        :fields bare))))
    (with-language ("nb")
      (is (equal '("Rad 3: Unit price må være minst 0")
                 (alert-lines (alert-html (field-refusal "lines[2].unit_price" "må være minst 0")
                                          :fields bare)))))))

(defun alert-as-in-2.35.0 (json)
  "The alert 2.35.0's error-alert made of the error document JSON."
  (let ((err (jget json "error")))
    (tun.ui:alert (:variant :destructive
               :title (tun.web::error-title (tun.web::error-code-keyword json))
               :attributes (list :data-code (jget err "code")))
              (let ((fields (coerce (or (jget err "fields") #()) 'list)))
                (if fields
                    `(:ul ,@(mapcar (lambda (field)
                                      `(:li ,(tun.web::field-error-sentence
                                              (jget field "field") (jget field "message"))))
                                    fields))
                    (jget err "message"))))))

(test an-alert-without-its-fields-is-as-it-was
  (let ((json (field-refusal "starts_on" "must be a date, such as 21 Oct 2026"
                       "customer_id" "must be filled in"))
        (plain (jobj "error" (jobj "code" "conflict" "message" "Someone else changed it."))))
    (dolist (document (list json plain))
      (is (equal (tun.html:render-html (alert-as-in-2.35.0 document)) (alert-html document))))
    (is (equal '("starts_on must be a date, such as 21 Oct 2026"
                 "customer_id must be filled in")
               (alert-lines (alert-html json))))
    (let ((html (alert-html json :fields (list (tun.ui:text-input (:label "Title" :name "title"
                                                               :id "u-title"))))))
      (is (equal (alert-html json) html) "a path no control is posted under, as before")
      (is (not (search "<a" html))))))

;;; ------------------------------------------------------------------
;;; The generated form: a row's field and a blank choice (criteria 2 and 4)

(test the-generated-summary-names-a-rows-field-after-its-row
  (with-test-server (port)
    (let ((customer (choice-customer "Kari Hansen"))
          (product (choice-product))
          (jar (web-login port "employee:anna")))
      (multiple-value-bind (status page)
          (web-request port "/orders" :method :post :jar jar
                                      :parameters `(("customer_id" . ,customer)
                                                    ("event_date" . "2026-06-20")
                                                    ("lines[0][product_id]" . ,product)
                                                    ("lines[0][quantity]" . "0")))
        (is (= 422 status))
        (is (search "Order line 1: Quantity must be" page) "the row, then the label")
        (is (not (search "Quantity in order line 1" page)))))))

(test a-generated-choice-left-empty-must-be-chosen
  (with-test-server (port)
    (choice-customer "Kari Hansen")
    (let ((jar (web-login port "employee:anna")))
      (multiple-value-bind (status page)
          (web-request port "/orders" :method :post :jar jar
                                      :parameters '(("customer_id" . "")
                                                    ("event_date" . "2026-06-20")))
        (is (= 422 status))
        (is (search "Customer must be chosen" page) "in the summary")
        (is (search "Must be chosen" page) "at the field")
        (is (not (search "Customer must be filled in" page)))))
    (as-web-actor ("employee:anna")
      (with-language ("nb")
        (let* ((missing (princ-to-string (tr "must be filled in")))
               (orders (tun.html:render-html
                        (tun.web::operation-form (find-operation-by-tool "orders_create")
                                                 "/orders"
                                                 :error-json (field-refusal "customer_id"
                                                                            missing))))
               (products (tun.html:render-html
                          (tun.web::operation-form (find-operation-by-tool "products_create")
                                                   "/products"
                                                   :error-json (field-refusal "kind" missing
                                                                        "name" missing)))))
          (is (search "Kunde må velges" orders) "a record's choice, in Norwegian")
          (is (search "Må velges" orders))
          (is (search "må velges" products) "an enum's choice")
          (is (search "må fylles ut" products) "a text keeps the operation's words"))))))

(test the-kernel-refuses-a-blank-id-as-a-missing-one
  (with-test-app ()
    (flet ((message (tool &rest arguments)
             (multiple-value-bind (json code) (apply #'call tool "employee:anna" arguments)
               (and code
                    (let ((field (find "customer_id" (coerce (jget (jget json "error") "fields")
                                                             'list)
                                       :key (lambda (field) (jget field "field"))
                                       :test #'equal)))
                      (if field (jget field "message") (to-json-string json)))))))
      (dolist (blank '("" "   "))
        (is (equal "must be filled in"
                   (message "orders_create" "customer_id" blank "event_date" "2026-06-20"
                            "lines" (jarr (list (jobj "product_id" "prd_x" "quantity" 1)))))
            "a draft's field: ~s" blank)
        (is (equal "must be filled in" (message "orders_list" "customer_id" blank))
            "an optional input, refused as before: ~s" blank))
      (is (null (message "orders_list" "customer_id" :null)) "null is no value, as before")
      (is (null (message "orders_list")) "and so is leaving it out"))))

;;; ------------------------------------------------------------------
;;; Enter saves without scripts (criterion 6)

(test an-asked-choice-puts-the-forms-first-submit-button-before-its-find
  (let ((asked (tun.html:render-html
                (tun.ui:choice-input (:label "Customer" :name "customer" :id "e-customer"
                                  :source "/customers/choices"))))
        (given (tun.html:render-html
                (tun.ui:choice-input (:label "Customer" :name "customer" :id "e-given"
                                  :options '(("cus_1" "Kari Hansen")))))))
    (let ((default (search "tun-choice-input-default" asked))
          (find (search "name=\"tun-find\"" asked)))
      (is (and default find (< default find)) "before «Find»")
      (let ((tag (subseq asked (position #\< asked :end default :from-end t)
                         (1+ (position #\> asked :start default)))))
        (is (search "type=\"submit\"" tag))
        (is (not (search "name=" tag)) "no name: it posts as the form's own button")
        (is (search "tabindex=\"-1\"" tag))
        (is (search "aria-hidden=\"true\"" tag))
        (is (search "data-tun-choice-off" tag) "taken out of the form where scripts run")
        (is (not (search " hidden" tag)) "rendered, so every browser presses it")))
    (is (not (search "tun-choice-input-default" given)) "a given choice has no find step")
    (is (search ".tun-choice-input-default {"
                (tun.ui:component-css (tun.ui:find-component "choice-input")))
        "out of sight by its CSS")))

;;; ------------------------------------------------------------------
;;; A module shapes its records' choice (criteria 7 and 8)

(defclass form-nits-app (application) ()
  (:documentation "An application whose own record-choice names a customer otherwise."))

(defmethod record-choice ((application form-nits-app) (entity (eql 'tun.customers:customer)))
  (list* :text (lambda (customer) (format nil "~a (client)" (tun.customers:customer-name customer)))
         (call-next-method)))

(defun shaped-customer (name email &key phone erased)
  "A customer made by the system; its id."
  (with-application (*app*)
    (as-actor ("system" :write)
      (entity-id (insert (make-instance 'tun.customers:customer :name name :email email
                                                                :phone phone :erased erased))))))

(defun erase-customer (id)
  (with-application (*app*)
    (as-actor ("system" :write)
      (let ((customer (fetch! 'tun.customers:customer id)))
        (setf (tun.customers:customer-erased customer) t)
        (save customer)))))

(defun shaped-choices (label)
  "Run the shape's checks on the store LABEL names: memory or postgres."
  (with-test-server (port :db (and (string= label "postgres") (scratch-postgres "form_nits")))
    (shaped-customer "Bjørn Åsen" "bjorn@asen.example" :phone "+47 912 34 567")
    (let* ((gro (shaped-customer "Gro Lie" "gro@lie.example"))
           (product (choice-product))
           (order (choice-order gro product))
           (jar (web-login port "employee:anna")))
      (erase-customer gro)
      (flet ((choices (text)
               (nth-value 1 (web-request port "/choices/customer" :parameters `(("q" . ,text))
                                                                  :jar jar :headers +htmx-part+))))
        (is (search "Bjørn Åsen" (choices "bjorn@asen.example")) "~a: by its email" label)
        (is (search "Bjørn Åsen" (choices "91234567")) "~a: by its phone, nationally" label)
        (is (not (search "Gro Lie" (choices ""))) "~a: an erased customer is not offered" label)
        (is (not (search "Gro Lie" (choices "gro"))) "~a: nor found" label))
      (let ((form (nth-value 1 (web-request port "/orders" :jar jar))))
        (is (search "Bjørn Åsen" (element-html form "orders_create-customer_id")))
        (is (not (search "Gro Lie" (element-html form "orders_create-customer_id")))
            "~a: not among the few options" label))
      (multiple-value-bind (status page)
          (web-request port "/orders" :method :post :jar jar
                                      :parameters `(("customer_id" . ,gro)
                                                    ("event_date" . "2026-06-20")
                                                    ("lines[0][product_id]" . ,product)
                                                    ("lines[0][quantity]" . "1")))
        (is (= 422 status) "~a: a posted erased customer is refused" label)
        (is (search "must be one of the choices" page)))
      (is (search "Gro Lie" (nth-value 1 (web-request port "/orders" :jar jar)))
          "~a: the list still names it" label)
      (is (search "Gro Lie" (nth-value 1 (web-request port (format nil "/orders/~a" order)
                                                      :jar jar)))
          "~a: and so does the order's page" label)
      (is (search "Bjørn Åsen" (nth-value 1 (web-request port "/choices/customer?q=bjorn"
                                                         :jar jar :headers +htmx-part+)))))))

(test a-module-shapes-its-records-choice
  (shaped-choices "memory")
  (if (postgres-available-p)
      (shaped-choices "postgres")
      (skip "no Postgres: run the suite under bin/with-postgres with TUN_TEST_POSTGRES set")))

(test tuns-own-record-choice-answers-nothing
  (with-test-app ()
    (is (null (record-choice *app* 'choice-note)))))

(test a-more-specific-method-wins-and-keeps-the-modules-other-keys
  (with-test-server (port :class 'form-nits-app)
    (shaped-customer "Bjørn Åsen" "bjorn@asen.example" :phone "+47 912 34 567")
    (shaped-customer "Gro Lie" "gro@lie.example" :erased t)
    (let* ((jar (web-login port "employee:anna"))
           (found (nth-value 1 (web-request port "/choices/customer?q=bjorn@asen.example"
                                            :jar jar :headers +htmx-part+)))
           (all (nth-value 1 (web-request port "/choices/customer?q=" :jar jar
                                                                      :headers +htmx-part+))))
      (is (search "Bjørn Åsen (client)" found) "the client's text, found by the module's email")
      (is (not (search "Gro Lie" all)) "the module's erased customer still out"))))
