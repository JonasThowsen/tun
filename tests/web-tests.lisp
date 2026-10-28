;;;; tests/web-tests.lisp -- phase 6: the generated UI calls the same
;;;; operations as MCP; viewers cannot submit; confirmation works in the UI.

(in-package #:tun.tests)

(def-suite web :in core)
(in-suite web)

(test login-and-access
  (with-test-server (port)
    (is (= 401 (web-request port "/customers")) "not logged in")
    (is (= 400 (web-request port "/login" :parameters '(("actor" . "boss:x")))))
    (let ((jar (make-instance 'drakma:cookie-jar)))
      (multiple-value-bind (status body headers)
          (web-request port "/login" :parameters '(("actor" . "employee:anna")) :jar jar)
        (declare (ignore body))
        (is (= 303 status))
        (is (string= "/orders" (location headers)))
        (let ((cookie (cdr (assoc :set-cookie headers))))
          (is (search "HttpOnly" cookie))
          (is (search "SameSite=Strict" cookie))))
      (multiple-value-bind (status body) (web-request port "/customers" :jar jar)
        (is (= 200 status))
        (is (search "employee:anna" body))
        (is (search "name=\"name\"" body) "the create form is generated from customers_create")
        (is (search "name=\"email\"" body))
        (is (search "type=\"email\"" body))))))

(test form-create-is-read-back-through-mcp
  (with-test-server (port)
    (let ((jar (web-login port "employee:anna")))
      (multiple-value-bind (status body headers)
          (web-request port "/customers" :method :post :jar jar
                       :parameters '(("name" . "Åse <b>Ødegård</b>") ("email" . "aase@example.no")
                                     ("request_key" . "skjema-1")))
        (declare (ignore body))
        (is (= 303 status))
        (is (string= "/customers" (location headers))))
      (let ((found (call-ok "customers_list" "viewer:vera" "query" "Ødegård")))
        (is (= 1 (jget found "returned")) "created through the form, read through MCP")
        (is (string= "Åse <b>Ødegård</b>" (jget (aref (jget found "items") 0) "name"))))
      (let ((body (nth-value 1 (web-request port "/customers" :jar jar))))
        (is (search "Åse &lt;b&gt;Ødegård&lt;/b&gt;" body) "user text is escaped")
        (is (not (search "<b>Ødegård" body))))
      (is (string= "employee:anna" (jget (aref (jget (call-ok "audit_list" "viewer:vera" "entity_type" "customer") "items") 0)
                                         "actor"))
          "the form submission is audited like any operation call"))))

(test viewer-cannot-submit
  (with-test-server (port)
    (let ((jar (web-login port "viewer:vera")))
      (multiple-value-bind (status body)
          (web-request port "/customers" :method :post :jar jar
                       :parameters '(("name" . "Ikke Lov") ("email" . "ikke@example.no")))
        (is (= 403 status))
        (is (search "data-code=\"forbidden\"" body)))
      (is (= 0 (jget (call-ok "customers_list" "viewer:vera" "query" "Ikke Lov") "returned")))
      (let ((entry (aref (jget (call-ok "audit_list" "viewer:vera") "items") 0)))
        (is (equal '("customers_create" "rejected" "viewer:vera")
                   (list (jget entry "tool") (jget entry "outcome") (jget entry "actor"))))))))

(test invalid-form-input-is-reported
  (with-test-server (port)
    (let ((jar (web-login port "employee:anna")))
      (multiple-value-bind (status body)
          (web-request port "/customers" :method :post :jar jar
                       :parameters '(("name" . "  ") ("email" . "ikke-epost")))
        (is (= 422 status))
        (is (search "invalid_input" body)))
      (is (= 0 (jget (call-ok "customers_list" "viewer:vera") "returned"))))))

(test orders-through-the-ui-with-confirmation
  (with-test-server (port)
    (let* ((jar (web-login port "employee:anna"))
           (customer (jget (call-ok "customers_create" "employee:anna" "name" "Kari" "email" "kari@example.no") "id"))
           (product (jget (call-ok "products_create" "employee:anna" "name" "Popcornmaskin" "kind" "rental"
                                   "unit" "stk" "unit_price_minor" 150000 "stock_tracked" nil "units_owned" 1)
                          "id"))
           (form (nth-value 1 (web-request port "/orders" :jar jar))))
      (is (search "name=\"lines[0][product_id]\"" form) "list inputs become rows")
      (is (search (format nil "value=\"~a\"" customer) form) "references become choices from customers_list")
      (multiple-value-bind (status body headers)
          (web-request port "/orders" :method :post :jar jar
                       :parameters `(("customer_id" . ,customer) ("event_date" . "2026-06-20")
                                     ("lines[0][product_id]" . ,product) ("lines[0][quantity]" . "1")))
        (declare (ignore body))
        (is (= 303 status))
        (let* ((path (location headers))
               (id (subseq path (length "/orders/"))))
          (is (string= "draft" (jget (call-ok "orders_get" "viewer:vera" "id" id) "status")))
          (let ((detail (nth-value 1 (web-request port path :jar jar))))
            (is (search "data-field=\"status\"" detail))
            (is (search "data-tool=\"orders_send_quote\"" detail)))
          (is (= 303 (web-request port (format nil "/orders/~a/orders_send_quote" id) :method :post :jar jar)))
          (is (= 303 (web-request port (format nil "/orders/~a/orders_accept" id) :method :post :jar jar)))
          ;; Confirmation: the first POST shows the summary and carries the token.
          (multiple-value-bind (status body)
              (web-request port (format nil "/orders/~a/orders_confirm" id) :method :post :jar jar)
            (is (= 200 status))
            (is (string= "accepted" (jget (call-ok "orders_get" "viewer:vera" "id" id) "status")))
            (let* ((start (search "name=\"confirmation_token\" value=\"" body))
                   (token (and start (subseq body (+ start 33) (position #\" body :start (+ start 33))))))
              (is (stringp token))
              (is (= 303 (web-request port (format nil "/orders/~a/orders_confirm" id) :method :post :jar jar
                                      :parameters `(("confirmation_token" . ,token)))))
              (is (string= "confirmed" (jget (call-ok "orders_get" "viewer:vera" "id" id) "status")))
              (is (= 303 (web-request port (format nil "/orders/~a/orders_complete" id) :method :post :jar jar)))
              (is (= 409 (web-request port (format nil "/orders/~a/orders_complete" id) :method :post :jar jar))
                  "the operation's invalid_transition is shown as 409"))))))))

(test a-refused-form-keeps-its-values-and-marks-its-fields
  (with-test-server (port)
    (let ((jar (web-login port "employee:anna")))
      (multiple-value-bind (status body)
          (web-request port "/customers" :method :post :jar jar
                       :parameters '(("name" . "Kari Nordmann") ("email" . "ikke-epost")))
        (is (= 422 status))
        (is (search "value=\"Kari Nordmann\"" body) "what was typed is kept")
        (is (search "href=\"#customers_create-email\"" body)
            "the error summary links to the field")
        (is (search "aria-invalid=\"true\"" body) "the field is marked")))))

;;; ------------------------------------------------------------------
;;; A page as a client defines one (spec/ui.md 8)

(defvar *posted-notes* '() "What the notes page was sent, newest first.")

(tun.web:define-page notes-page ("test-notater" :title "Notater" :icon :file-text
                                                :navigation nil)
    (method path form query)
  (cond ((eq method :post)
         (push (jget form "text") *posted-notes*)
         (values 303 "/test-notater/sendt"))
        ((equal path '("endret"))
         (fail :conflict "Notatet er endret"))
        (t (values 200 (format nil "Notater ~{~a~^/~}" path)
                   (list `(:p ,(or (jget query "q") "uten søk")))
                   (list :description "Alle notatene"
                         :breadcrumbs '((:label "Notater" :href "/test-notater")
                                        (:label "Ett")))))))

(test a-page-answers-its-paths-and-posts
  (with-test-server (port)
    (let ((jar (web-login port "employee:anna")))
      (multiple-value-bind (status body) (web-request port "/test-notater/a/b" :jar jar
                                                      :parameters '(("q" . "lim")))
        (is (= 200 status))
        (is (search "Notater a/b" body) "the parts after the prefix")
        (is (search "lim" body) "the query")
        (is (search "Alle notatene" body) "the header's description")
        (is (search "href=\"/test-notater\"" body) "its breadcrumbs"))
      (multiple-value-bind (status body headers)
          (web-request port "/test-notater" :method :post :jar jar
                       :parameters '(("text" . "Ring Kari")))
        (declare (ignore body))
        (is (= 303 status))
        (is (string= "/test-notater/sendt" (location headers)))
        (is (equal "Ring Kari" (first *posted-notes*))))
      (multiple-value-bind (status body) (web-request port "/test-notater/endret" :jar jar)
        (is (= 409 status) "an operation error it does not catch")
        (is (search "data-code=\"conflict\"" body)))
      (is (not (search "href=\"/test-notater\"" (nth-value 1 (web-request port "/customers"
                                                                         :jar jar))))
          "navigation nil keeps it out of the menu"))
    (is (= 403 (web-request port "/test-notater" :jar (web-login port "viewer:vera")))
        "a role the policy does not admit")))

(test a-page-defined-again-replaces-itself
  (let ((before (gethash "test-notater" tun.web::*staff-pages*)))
    (unwind-protect
         (progn
           (tun.web:register-staff-page "test-notater" 'notes-page :title "Notatene"
                                                                   :navigation nil)
           (let ((after (gethash "test-notater" tun.web::*staff-pages*)))
             (is (equal "Notatene" (tun.web::staff-page-title after)))
             (is (= (tun.web::staff-page-sequence before) (tun.web::staff-page-sequence after))
                 "it keeps its place in the menu"))
           (signals extension-error
             (tun.web:register-staff-page "test-notater" 'another-notes-page))
           (signals extension-error
             (tun.web:register-staff-page "test-notater" (lambda (&rest request) request))))
      (setf (gethash "test-notater" tun.web::*staff-pages*) before))))

(test home-is-the-first-page-in-the-menu-without-a-resource
  (let ((tun.web::*resources* '())
        (*actor* (parse-actor "employee:anna")))
    (is (equal (getf (first (tun.web::navigation-items)) :href) (tun.web::home-path)))
    (is (string/= "/login-info" (tun.web::home-path))))
  (let ((tun.web::*resources* '())
        (*actor* nil))
    (is (string= "/login-info" (tun.web::home-path)) "before anyone is logged in")))

;;; ------------------------------------------------------------------
;;; The menu: the business's work first, the system's pages last (spec/ui.md 8)

(test the-menu-ends-with-the-system-pages
  (let ((*actor* (parse-actor "admin:root")))
    (let* ((groups (tun.web::navigation))
           (system (car (last groups)))
           (work (mapcar (lambda (item) (getf item :href)) (getf (first groups) :items))))
      (is (equal "System" (getf system :heading)))
      (is (subsetp '("/settings" "/access") (mapcar (lambda (item) (getf item :href))
                                                   (getf system :items))
                   :test #'equal)
          "settings and access are the system's")
      (is (null (intersection '("/settings" "/access") work :test #'equal)))
      (is (equal (tun.web::resource-path (first (last tun.web::*resources*))) (first work))
          "the first resource leads the work without a client page"))))

;;; ------------------------------------------------------------------
;;; htmx (spec/ui.md 4.1, 8.1)

(defvar *moves* '() "What the board page was sent, newest first.")

(tun.web:define-page moves-page ("test-tavle" :title "Tavle" :navigation nil)
    (method path form query)
  (cond ((and (eq method :post) (equal path '("flytt")))
         (push (list (jget form "card") (jget form "column")) *moves*)
         (if (tun.web:htmx-request-p)
             (values 200 :fragment (list `(:p "flyttet " ,(jget form "column")))
                     (list :trigger "tun:moved"))
             (values 303 "/test-tavle")))
        ((equal path '("videre"))
         (values 303 "/test-tavle"))
        ((equal path '("feil"))
         (fail :conflict "Saken er endret"))
        (t (values 200 "Tavle" (list '(:p "hele tavlen"))))))

(defparameter +htmx-headers+ '(("HX-Request" . "true") ("HX-Request-Type" . "partial"))
  "What htmx sends when it asks for part of a page.")

(test staff-pages-go-through-htmx
  (with-test-server (port)
    (let ((body (nth-value 1 (web-request port "/test-tavle" :jar (web-login port "employee:anna")))))
      (is (search "hx-boost:inherited=\"true\"" body) "a staff page is boosted")
      (is (search "hx-headers:inherited" body))
      (is (search (tun.ui:asset-hashes) body) "and sends its assets' hashes")
      (is (search "name=\"htmx-config\"" body))
      (is (search "&quot;mode&quot;:&quot;same-origin&quot;" body) "htmx asks only this server")
      (is (search "&quot;extensions&quot;:&quot;tun&quot;" body) "and loads only Tun's extension")
      (is (search "registerExtension('tun'" (tun.ui:script)) "which refuses to run code")
      (is (< (search (tun.ui:htmx-path) body) (search (tun.ui:script-path) body))
          "htmx is loaded before the components' script"))
    (let ((login (nth-value 1 (web-request port "/login"))))
      (is (search (tun.ui:htmx-path) login))
      (is (not (search "hx-boost" login)) "signing in is not boosted"))
    (multiple-value-bind (status body headers) (web-request port (tun.ui:htmx-path))
      (is (= 200 status))
      (is (search "htmx" body))
      (is (search "immutable" (cdr (assoc :cache-control headers)))))))

(test a-page-answers-htmx-with-a-fragment
  (with-test-server (port)
    (let ((jar (web-login port "employee:anna")))
      (multiple-value-bind (status body headers)
          (web-request port "/test-tavle/flytt" :method :post :jar jar :headers +htmx-headers+
                       :parameters '(("card" . "itm_1") ("column" . "ferdig")))
        (is (= 200 status))
        (is (string= "<p>flyttet ferdig</p>" body) "the fragment alone")
        (is (equal "tun:moved" (cdr (assoc :hx-trigger headers))) "and the event it names")
        (is (equal '("itm_1" "ferdig") (first *moves*))))
      (multiple-value-bind (status body headers)
          (web-request port "/test-tavle/flytt" :method :post :jar jar
                       :parameters '(("card" . "itm_1") ("column" . "ny")))
        (declare (ignore body))
        (is (= 303 status) "without htmx, the plain form's answer")
        (is (string= "/test-tavle" (location headers))))
      (multiple-value-bind (status body headers)
          (web-request port "/test-tavle/videre" :jar jar :headers +htmx-headers+)
        (declare (ignore body))
        (is (= 200 status) "a 303 to htmx for part of a page")
        (is (equal "/test-tavle" (cdr (assoc :hx-location headers)))))
      (multiple-value-bind (status body headers)
          (web-request port "/test-tavle/videre" :jar jar
                       :headers '(("HX-Request" . "true") ("HX-Request-Type" . "full")
                                  ("HX-Boosted" . "true")))
        (declare (ignore body))
        (is (= 303 status) "a boosted request follows the 303 itself")
        (is (string= "/test-tavle" (location headers))))
      (multiple-value-bind (status body) (web-request port "/test-tavle/flytt" :method :post :jar jar
                                                      :headers '(("HX-Request" . "true")
                                                                 ("HX-Request-Type" . "full"))
                                                      :parameters '(("card" . "itm_1")
                                                                    ("column" . "ny")))
        (declare (ignore body))
        (is (= 303 status) "htmx asking for a whole page gets the whole answer"))
      (multiple-value-bind (status body) (web-request port "/test-tavle/feil" :jar jar
                                                      :headers +htmx-headers+)
        (is (= 409 status))
        (is (search "data-code=\"conflict\"" body))
        (is (not (search "<!doctype" body)) "an uncaught error is the alert alone")))))

(test stale-assets-load-the-page-in-full
  (with-test-server (port)
    (let ((jar (web-login port "employee:anna"))
          (boosted '(("HX-Request" . "true") ("HX-Request-Type" . "full") ("HX-Boosted" . "true"))))
      (multiple-value-bind (status body headers)
          (web-request port "/test-tavle?x=1" :jar jar
                       :headers (cons '("Tun-Assets" . "000000000000 000000000000") boosted))
        (declare (ignore status body))
        (is (equal "/test-tavle?x=1" (cdr (assoc :hx-redirect headers)))))
      (multiple-value-bind (status body headers)
          (web-request port "/test-tavle" :jar jar
                       :headers (cons (cons "Tun-Assets" (tun.ui:asset-hashes)) boosted))
        (is (= 200 status))
        (is (search "hele tavlen" body))
        (is (null (assoc :hx-redirect headers)) "the current assets go on")))))

;;; ------------------------------------------------------------------
;;; A page that remembers its query for each account (spec/ui.md 8, item 7)

(tun.web:define-page filters-page ("test-filtre" :title "Filtre" :navigation nil
                                                 :remembers '("status" "sort"))
    (method path form query)
  (if (eq method :post)
      (values 303 "/test-notater")
      (values 200 "Filtre" (list `(:p "status " ,(jget query "status" "alle"))))))

(defun filters-request (port path jar &rest options)
  "Values the status of a GET of PATH and where it is sent, if anywhere."
  (multiple-value-bind (status body headers) (apply #'web-request port path :jar jar options)
    (declare (ignore body))
    (values status (location headers))))

(test a-page-sends-a-person-back-to-what-they-left-it-with
  (with-test-server (port)
    (let ((anna (web-login port "employee:anna")))
      (is (= 200 (filters-request port "/test-filtre" anna)) "nothing kept yet")
      (is (= 200 (filters-request port "/test-filtre?status=open&sort=" anna)))
      (is (equal '(303 "/test-filtre?status=open")
                 (multiple-value-list (filters-request port "/test-filtre" anna)))
          "the bare address goes to what was kept, without the cleared key")
      (is (equal "/test-filtre?q=lim&status=open"
                 (nth-value 1 (filters-request port "/test-filtre?q=lim" anna)))
          "after the parameters it had")
      (is (equal "/test-filtre?status=open"
                 (nth-value 1 (filters-request port "/test-filtre" (web-login port "employee:anna"))))
          "the account's, in another browser too")
      (is (= 200 (filters-request port "/test-filtre" (web-login port "employee:bob")))
          "not another account's")
      (is (equal "/test-filtre?status=open"
                 (nth-value 1 (filters-request
                               port "/test-filtre" anna
                               :headers '(("HX-Request" . "true") ("HX-Request-Type" . "full")
                                          ("HX-Boosted" . "true")))))
          "a boosted request gets the 303 itself")
      (filters-request port "/test-filtre" anna
                       :parameters '(("sort" . "nyest") ("status" . "på vent")))
      (is (equal "/test-filtre?status=p%C3%A5%20vent&sort=nyest"
                 (nth-value 1 (filters-request port "/test-filtre" anna)))
          "in the order the page names its keys, encoded")
      (is (= 200 (filters-request port "/test-filtre?sort=" anna)))
      (is (= 200 (filters-request port "/test-filtre" anna))
          "a key named without a value is kept as cleared"))))

(test only-the-pages-own-address-is-remembered
  (with-test-server (port)
    (let ((anna (web-login port "employee:anna")))
      (filters-request port "/test-filtre/sak_1?status=open" anna)
      (filters-request port "/test-filtre?status=open" anna :method :post)
      (filters-request port "/test-filtre?status=open" anna :headers +htmx-headers+)
      (is (= 200 (filters-request port "/test-filtre" anna))
          "a record's page, a post and a part htmx asks for keep nothing")
      (filters-request port "/test-filtre?status=open" anna)
      (is (= 200 (filters-request port "/test-filtre" anna :headers +htmx-headers+))
          "and a part htmx asks for is not sent anywhere")
      (is (= 200 (filters-request port "/test-filtre/sak_1" anna)))
      (is (= 200 (filters-request port "/test-notater" anna))
          "nor is a page that remembers nothing")))
  (dolist (remembers '("status" (:status)))
    (signals extension-error
      (tun.web:register-staff-page "test-feil" 'filters-page :remembers remembers))))

;;; Preloads: a page records nothing for them (spec/ui.md 4.1)

(defparameter +preload-headers+
  '(("HX-Request" . "true") ("HX-Request-Type" . "full") ("HX-Boosted" . "true")
    ("Tun-Preload" . "true"))
  "What Tun's script sends for a page it loads before the click.")

(defvar *page-views* 0 "How many times the counted page was viewed.")

(tun.web:define-page counted-page ("test-visninger" :title "Visninger" :navigation nil)
    (method path form query)
  (if (tun.web:preload-request-p)
      (tun.web:decline-preload)
      (values 200 "Visninger" (list `(:p ,(princ-to-string (incf *page-views*)))))))

(test a-preload-saves-nothing-and-the-click-after-it-does
  (with-test-server (port)
    (let ((anna (web-login port "employee:anna")))
      (multiple-value-bind (status body headers)
          (web-request port "/test-filtre?status=open" :jar anna :headers +preload-headers+)
        (declare (ignore body))
        (is (= 204 status) "a preload that would save is declined")
        (is (equal "declined" (cdr (assoc :tun-preload headers)))))
      (is (= 200 (filters-request port "/test-filtre" anna)) "and saved nothing")
      (filters-request port "/test-filtre?status=open" anna)
      (is (equal "/test-filtre?status=open" (nth-value 1 (filters-request port "/test-filtre" anna)))
          "the click after it saves")
      (is (= 200 (filters-request port "/test-filtre?status=open" anna :headers +preload-headers+))
          "a preload of what is saved already is answered")
      (is (equal '(303 "/test-filtre?status=open")
                 (multiple-value-list (filters-request port "/test-filtre" anna
                                                       :headers +preload-headers+)))
          "and so is one of the bare address, with where it leads")
      (let ((before *page-views*))
        (multiple-value-bind (status body headers)
            (web-request port "/test-visninger" :jar anna :headers +preload-headers+)
          (declare (ignore body))
          (is (= 204 status) "a page that would record something declines")
          (is (equal "declined" (cdr (assoc :tun-preload headers)))))
        (is (= before *page-views*))
        (is (= 200 (web-request port "/test-visninger" :jar anna)))
        (is (= (1+ before) *page-views*) "and records it for the click")))))

(test new-assets-reload-a-preloaded-page-too
  (with-test-server (port)
    (multiple-value-bind (status body headers)
        (web-request port "/test-tavle" :jar (web-login port "employee:anna")
                     :headers (cons '("Tun-Assets" . "000000000000 000000000000")
                                    +preload-headers+))
      (declare (ignore status body))
      (is (equal "/test-tavle" (cdr (assoc :hx-redirect headers)))))))

;;; ------------------------------------------------------------------
;;; Width and what a client adds to every page (spec/ui.md 8)

(define-application extras-test-app ())

(defmethod tun.web:staff-page-extras ((application extras-test-app))
  (list (tun.ui:dialog (:id "test-sok" :title "Søk" :shortcut "/") "søkefelt")))

(tun.web:define-page wide-page ("test-bred" :title "Bred" :navigation nil :width :wide)
    (method path form query)
  (values 200 "Bred" (list '(:p "bred side"))))

(test a-page-can-be-wide-and-carry-the-clients-extras
  (with-test-server (port :class 'extras-test-app)
    (let ((jar (web-login port "employee:anna")))
      (let ((wide (nth-value 1 (web-request port "/test-bred" :jar jar))))
        (is (search "data-width=\"wide\"" wide))
        (is (search "id=\"test-sok\"" wide) "the client's dialog on its page")
        (is (search "data-tun-dialog-shortcut=\"/\"" wide)))
      (let ((other (nth-value 1 (web-request port "/settings" :jar (web-login port "admin:root")))))
        (is (not (search "data-width=\"wide\"" other)) "other pages keep their width")
        (is (search "id=\"test-sok\"" other) "and the extras are on Tun's own pages too"))
      (is (not (search "test-sok" (nth-value 1 (web-request port "/login"))))
          "but not for someone not logged in"))))

;;; ------------------------------------------------------------------
;;; A page's files (spec/files.md 6.2)

(test a-page-receives-the-files-of-a-multipart-post
  (with-files-page ()
    (with-test-server (port)
      (let ((png (fixture "skjermbilde.png")))
        (post-form port "/filprove" (list (list "title" "Med skjermbilde")
                                          (list "filer" "skjerm.png" png)
                                          (list "filer" "" (bytes))))
        (is (equal "Med skjermbilde" (jget *page-seen* "title")))
        (let ((files (coerce (jget *page-seen* "filer") 'list)))
          (is (= 1 (length files)) "a part with no file is left out")
          (is (equal "skjerm.png" (jget (first files) "filename")))
          (is (string-prefix-p "upl_" (jget (first files) "upload"))))
        (with-application (*app*)
          (with-actor ((system-actor "test"))
            (is (= 1 (length (with-transaction (:read) (select 'tun.files:attachment))))
                "web-call attached the file")))
        (multiple-value-bind (status text)
            (post-form port "/filprove" (list (list "title" "Feil")
                                              (list "filer" "notat.png" (bytes "tekst"))))
          (is (= 422 status))
          (is (search "“notat.png”: This type of file is not allowed." text)))))))

(test a-refused-file-shows-at-its-field-and-in-the-summary
  (let* ((op (find-operation 'file-notes-create))
         (field (jobj "field" "screenshots[0]"
                      "message" "“notat.png”: This type of file is not allowed."))
         (error-json (jobj "error" (jobj "code" "invalid_input" "message" "Ugyldig input"
                                         "fields" (jarr (list field)))))
         (page (tun.html:render-html
                (tun.web::operation-form op "/notater" :error-json error-json))))
    (is (search "tun-error-summary" page))
    (is (search "tun-field-error" page))
    (is (>= (count-matches "“notat\\.png”: This type of file is not allowed" page) 2)
        "at the field and in the summary")))

(test a-page-calls-record-keeps-no-file-and-no-handle
  (with-files-page ()
    (with-test-server (port)
      (let ((png (bytes (fixture "skjermbilde.png") (make-array (* 2 +mib+) :initial-element 0))))
        (post-form port "/filprove" (list (list "title" "Med fil") (list "filer" "skjerm.png" png)))
        (let ((record (find "web:POST /filprove" (finished-requests) :key #'request-tool
                                                                     :test #'equal)))
          (is-true record)
          (is (notany (lambda (s) (search "upl_" s)) (record-strings record)) "no handle")
          (is (< (reduce #'max (mapcar #'length (record-strings record)) :initial-value 0)
                 +mib+)
              "nothing of the file"))))))
