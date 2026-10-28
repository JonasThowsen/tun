;;;; tests/language-tests.lisp -- the client is a Norwegian tenant: its
;;;; generated and module pages have Norwegian for every text core and the
;;;; modules look up, and write nothing they did not look up
;;;; (spec/i18n.md 3.7).

(in-package #:test-client.tests)

(def-suite client-languages :in client)
(in-suite client-languages)

(defparameter +client-copy+
  '("Timer på ordren" "Ordren har ingen linjer." "Produkt" "Antall" "Timer"
    "Navn" "Kundetype" "E-post" "Organisasjonsnummer" "ID")
  "The client's own copy on its screen overrides (screens.lisp), written in
Norwegian and shown as it is, as a client from before core 2.0 writes it.")

(defun some-records ()
  "A customer, a rental and an order of it, made as an employee."
  (let ((customer (customer "Anders" "anders@example.no" "kind" "privat"))
        (tent (rental "Partytelt")))
    (call-ok "orders_create" "employee:anna" "customer_id" customer "event_date" "2026-06-20"
             "lines" (lines-of (list "product_id" tent "quantity" 1 "hours" 4)))))

(defun page-links (port jar path)
  "The path of each link on the page at PATH, fetched with JAR, once each."
  (let ((body (nth-value 1 (web-request port path :jar jar)))
        (paths '()))
    (cl-ppcre:do-register-groups (link) ("<a [^>]*href=\"(/[^\"?#]*)\"" body)
      (pushnew link paths :test #'string=))
    (nreverse paths)))

(defun staff-paths (port jar)
  "The pages in the staff menu, and the pages they link to below them, such
as a record's: every generated and module page the records reach."
  (let ((menu (remove-if (lambda (path) (member path '("/" "/logout") :test #'string=))
                         (page-links port jar "/settings"))))
    (remove-duplicates
     (append menu
             (loop for page in menu
                   append (remove-if-not (lambda (link)
                                           (and (> (length link) (1+ (length page)))
                                                (string= (format nil "~a/" page) link
                                                         :end2 (1+ (length page)))))
                                         (page-links port jar page))))
     :test #'string= :from-end t)))

(defun nested-json-keys (value)
  "The keys of every object inside the JSON VALUE, not VALUE's own: a JSON
field's value is shown as the module gives it, keys and all."
  (labels ((keys (value)
             (cond ((hash-table-p value)
                    (append (tun.core:jkeys value) (loop for v being the hash-values of value
                                                append (keys v))))
                   ((tun.core:json-array-p value) (loop for v across value append (keys v)))
                   (t nil))))
    (when (hash-table-p value)
      (loop for v being the hash-values of value append (keys v)))))

(defun module-owners ()
  "Core and every module that writes a text: every owner but the client."
  (remove "client" (remove-duplicates (mapcar #'third (known-texts)) :test #'equal)
          :test #'equal))

(test every-page-has-norwegian-for-what-core-and-the-modules-write
  (with-test-server (port :class 'test-client:nordvik)
    (let* ((admin (web-login port "admin:ada"))
           (paths (progn (some-records) (staff-paths port admin))))
      (is (< 3 (length paths)) "the menu and its records give ~s" paths)
      (multiple-value-bind (missing bodies)
          (pages-missing-translations port admin paths :owners (module-owners))
        (is (null missing) "no Norwegian for ~s" missing)
        (loop for path in paths
              for body in bodies
              do (is (search "lang=\"nb\"" body) "~a says it is Norwegian" path))))))

(test every-page-looks-up-what-it-writes
  (with-test-server (port :class 'test-client:nordvik)
    (let ((order (some-records)))
      (call-ok "settings_set" "admin:ada" "key" "locale.language" "value" "qps")
      (let* ((admin (web-login port "admin:ada"))
             ;; The data the pages show as it is: records, settings, the
             ;; actor, and the client's own copy.
             (allowed (append (stored-strings) (data-codes) +client-copy+
                              (json-strings (call-ok "settings_list" "admin:ada"))
                              (nested-json-keys (call-ok "orders_get" "admin:ada"
                                                         "id" (jget order "id")))
                              '("admin:ada"))))
        (dolist (path (staff-paths port admin))
          (let ((problems (pseudo-page-problems port path admin :allowed allowed)))
            (is (null problems) "~a writes ~s without a lookup" path problems)))))))
