;;;; tests/posted-form-tests.lisp -- what a page's FORM holds (spec/ui.md 8,
;;;; «A client's pages» 2, «Public pages» 1): a name posted once is its text,
;;;; a name posted more than once, as a group of checkboxes posts it, an array
;;;; of its texts in order, on a staff page and on a public page.

(in-package #:tun.tests)
(def-suite posted-forms :in core)
(in-suite posted-forms)

(defvar *posted-form* nil "The FORM the test's pages got last.")

(defun posted-form-page (method path form query)
  "A staff page that keeps the FORM it was posted, for the test to read."
  (declare (ignore path query))
  (when (eq method :post)
    (setf (sb-ext:symbol-global-value '*posted-form*) form))
  (if (tun.web:htmx-request-p)
      (values 200 :fragment (list '(:p "Kept")))
      (values 200 "Posted" (list '(:p "Kept")))))

(defun posted-form-public-page (method parts form session)
  "A public page that keeps the FORM it was posted, for the test to read."
  (declare (ignore parts session))
  (when (eq method :post)
    (setf (sb-ext:symbol-global-value '*posted-form*) form))
  (values 200 "Posted" (list '(:p "Kept"))))

(defmacro with-posted-form-pages (() &body body)
  "Run BODY with the test's staff page at /posted-test and its public page
at /posted-public."
  `(unwind-protect
        (progn (tun.web:register-staff-page "posted-test" 'posted-form-page
                                            :policy :employee :navigation nil)
               (tun.web:register-public-page "posted-public" 'posted-form-public-page)
               (setf (sb-ext:symbol-global-value '*posted-form*) nil)
               ,@body)
     (remhash "posted-test" tun.web::*staff-pages*)
     (remhash "posted-public" tun.web::*public-pages*)))

(defparameter +posted-days+
  '(("mon" "Mon") ("tue" "Tue") ("wed" "Wed") ("thu" "Thu") ("fri" "Fri"))
  "The choices of the test's group of checkboxes.")

(defun days-form-fields (ticked)
  "What a browser posts of a form with a group of checkboxes named days, the
days TICKED among +POSTED-DAYS+ ticked, and a title: the form's fields as
TUN.TEST-SUPPORT reads them from the rendered page."
  (let ((html (tun.html:render-html
               `(:form (:@ :method "post" :action "/posted-test")
                       (:input (:@ :name "title" :value "Visit"))
                       ,(tun.ui:checkboxes (:legend "Days" :name "days" :choices +posted-days+
                                            :selected ticked))
                       ,(tun.ui:button (:type "submit") "Save")))))
    (tun.test-support::page-form-fields (first (tun.test-support::page-forms html)))))

(defun post-fields (port path fields &key multipart headers (actor "employee:anna"))
  "POST FIELDS, (NAME . VALUE) pairs, to PATH as ACTOR (NIL for no one),
urlencoded or as multipart/form-data; the status."
  (let ((headers (append (and actor (list (cons "X-Tun-Actor" actor))) headers)))
    (if multipart
        (post-octets port path (multipart-octets "tun-test-grense"
                                                 (mapcar (lambda (field)
                                                           (list (car field) (cdr field)))
                                                         fields))
                     :content-type "multipart/form-data; boundary=tun-test-grense"
                     :headers headers)
        (nth-value 1 (drakma:http-request (format nil "http://127.0.0.1:~d~a" port path)
                                          :method :post :parameters fields
                                          :external-format-out :utf-8 :redirect nil
                                          :additional-headers headers)))))

(defun posted-days ()
  "What the last FORM held under days: its JSON, as its text or its array as
a list, or :ABSENT."
  (multiple-value-bind (value found) (jget (sb-ext:symbol-global-value '*posted-form*) "days")
    (cond ((not found) :absent)
          ((stringp value) value)
          (t (coerce value 'list)))))

(defun check-days-posted (port path &rest options)
  "Post the days form with none, one and three ticked to PATH, with OPTIONS
for POST-FORM, and check what the page's FORM held each time."
  (loop for (ticked json) in '((() :absent)
                               (("mon") "mon")
                               (("mon" "wed" "fri") ("mon" "wed" "fri")))
        do (setf (sb-ext:symbol-global-value '*posted-form*) nil)
           (let ((fields (days-form-fields ticked)))
             (is (= (length ticked) (count "days" fields :key #'car :test #'string=))
                 "the form posts days once for each box ticked: ~s" fields)
             (is (= 200 (apply #'post-fields port path fields options))
                 "~a ~s: posted" path ticked)
             (let ((form (sb-ext:symbol-global-value '*posted-form*)))
               (is-true form "~a ~s: the page got the form" path ticked)
               (is (equal json (posted-days)) "~a ~s ticked gives ~s: ~s" path ticked json
                   (posted-days))
               (is (equal ticked (tun.web:query-values form "days"))
                   "~a ~s ticked reads ~s" path ticked (tun.web:query-values form "days"))
               (is (equal "Visit" (jget form "title")) "~a: a name posted once is its text"
                   path)))))

(test a-staff-page-keeps-every-box-ticked
  (with-posted-form-pages ()
    (with-test-server (port)
      (check-days-posted port "/posted-test")
      (check-days-posted port "/posted-test" :multipart t)
      (check-days-posted port "/posted-test"
                         :headers '(("HX-Request" . "true") ("HX-Request-Type" . "partial"))))))

(test a-public-page-keeps-every-box-ticked
  (with-posted-form-pages ()
    (with-test-server (port)
      (check-days-posted port "/posted-public" :actor nil)
      (check-days-posted port "/posted-public" :actor nil
                         :headers '(("HX-Request" . "true") ("HX-Request-Type" . "partial"))))))

(test a-name-posted-once-is-its-text
  (with-posted-form-pages ()
    (with-test-server (port)
      (dolist (path '("/posted-test" "/posted-public"))
        (post-fields port path '(("title" . "Æble") ("note" . "") ("days" . "tue"))
                   :actor (and (string= path "/posted-test") "employee:anna"))
        (let ((form (sb-ext:symbol-global-value '*posted-form*)))
          (is (equalp (jobj "title" "Æble" "note" "" "days" "tue") form)
              "~a: each name its text, an empty one kept: ~a" path (to-json-string form)))
        (post-fields port path '(("note" . "") ("note" . "b") ("note" . ""))
                   :actor (and (string= path "/posted-test") "employee:anna"))
        (let ((form (sb-ext:symbol-global-value '*posted-form*)))
          (is (equalp #("" "b" "") (jget form "note")) "~a: empty texts kept in order" path)
          (is (equal '("b") (tun.web:query-values form "note"))
              "~a: and left out when read" path))))))

(test a-posted-file-is-still-its-array
  (with-posted-form-pages ()
    (with-test-server (port)
      (let ((png (fixture "skjermbilde.png")))
        (is (= 200 (post-octets port "/posted-test"
                                (multipart-octets "tun-test-grense"
                                                  (list '("title" "Med fil") '("days" "mon")
                                                        '("days" "tue")
                                                        (list "shots" "skjerm.png" png)))
                                :content-type "multipart/form-data; boundary=tun-test-grense"
                                :headers '(("X-Tun-Actor" . "employee:anna")))))
        (let* ((form (sb-ext:symbol-global-value '*posted-form*))
               (files (jget form "shots")))
          (is (equal "Med fil" (jget form "title")))
          (is (equalp #("mon" "tue") (jget form "days")))
          (is (and (vectorp files) (= 1 (length files))) "one file: ~s" files)
          (is (equal "skjerm.png" (jget (aref files 0) "filename")))
          (is (stringp (jget (aref files 0) "upload")) "its handle"))))))
