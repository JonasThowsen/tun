;;;; tests/download-tests.lisp -- a file a page makes on the spot, answered as a
;;;; download (spec/files.md 5.5): its headers, the types and names a page's
;;;; data cannot make dangerous, the page's policy, htmx and preloads.

(in-package #:tun.tests)
(def-suite downloads :in core)
(in-suite downloads)

(defvar *download-page-calls* 0 "How many times the test's download page ran.")

(defparameter +download-octets+ (coerce #(37 80 68 70 45 49) '(vector (unsigned-byte 8)))
  "What the test's download page answers without a text: «%PDF-1».")

(defun download-test-page (method path form query)
  "A staff page of :employee whose path download.bin answers a download whose
type and name come from the query, as a page's data might choose them."
  (declare (ignore method form))
  (incf *download-page-calls*)
  (if (equal path '("download.bin"))
      (values 200 :download
              (tun.web:make-download (or (jget query "text") +download-octets+)
                                     :filename (jget query "name")
                                     :content-type (jget query "type")))
      (values 200 "Downloads" (list "a page"))))

(defmacro with-download-page (() &body body)
  "Run BODY with the test's download page registered at /download-test."
  `(unwind-protect
        (progn (tun.web:register-staff-page "download-test" 'download-test-page
                                            :policy :employee :navigation nil)
               (setf *download-page-calls* 0)
               ,@body)
     (remhash "download-test" tun.web::*staff-pages*)))

(defun download-path (&rest pairs)
  "The test page's download with PAIRS, (KEY . VALUE), as its query."
  (tun.web:query-address "/download-test/download.bin" pairs))

(defun fetch-address (port path &key actor (method :get) headers)
  "Values the status, the body's octets and the headers of METHOD on PATH, sent
as written, as ACTOR (claimed identity) when given."
  (multiple-value-bind (body status response-headers)
      (drakma:http-request (format nil "http://127.0.0.1:~d~a" port path)
                           :method method :redirect nil :force-binary t :preserve-uri t
                           :additional-headers (append (and actor (list (cons "X-Tun-Actor" actor)))
                                                       headers))
    (values status body response-headers)))

(defun fetch-download (port &rest pairs)
  "Values status, body and headers of the download with PAIRS as employee:anna,
the query encoded as UTF-8 (PURI cannot parse an address that holds it)."
  (multiple-value-bind (body status headers)
      (drakma:http-request (format nil "http://127.0.0.1:~d/download-test/download.bin" port)
                           :parameters pairs :external-format-out :utf-8
                           :redirect nil :force-binary t
                           :additional-headers '(("X-Tun-Actor" . "employee:anna")))
    (values status body headers)))

(defun disposition-name (headers)
  "The filename*'s name of HEADERS' Content-Disposition, decoded."
  (let* ((value (response-header :content-disposition headers))
         (encoded (subseq value (+ (search "filename*=UTF-8''" value) 17))))
    (hunchentoot:url-decode encoded :utf-8)))

(test a-page-answers-a-file-it-made-as-a-download
  (with-download-page ()
    (with-test-server (port)
      (multiple-value-bind (status body headers)
          (fetch-download port '("type" . "application/pdf") '("name" . "Økonomi «2026».pdf"))
        (is (= 200 status))
        (is (equalp #(37 80 68 70 45 49) body) "exactly the octets")
        (is (equal "application/pdf" (response-header :content-type headers)))
        (is (equal "6" (response-header :content-length headers)))
        (is (equal (concatenate 'string "attachment; filename=\"_konomi _2026_.pdf\"; "
                                "filename*=UTF-8''%C3%98konomi%20%C2%AB2026%C2%BB.pdf")
                   (response-header :content-disposition headers)))
        (is (equal "nosniff" (response-header :x-content-type-options headers)))
        (is (equal tun.web::+file-security-policy+
                   (response-header :content-security-policy headers)))
        (is (equal "same-origin" (response-header :cross-origin-resource-policy headers)))
        (is (equal "no-referrer" (response-header :referrer-policy headers)))
        (is (equal "no-store" (response-header :cache-control headers))))
      (multiple-value-bind (status body headers)
          (fetch-download port '("type" . "application/json") '("name" . "data.json")
                          '("text" . "{\"navn\":\"Åse\"}"))
        (is (= 200 status))
        (is (equalp (sb-ext:string-to-octets "{\"navn\":\"Åse\"}" :external-format :utf-8) body)
            "a string is sent as UTF-8")
        (is (equal "application/json; charset=utf-8" (response-header :content-type headers)))
        (is (equal (princ-to-string (length body)) (response-header :content-length headers)))))))

(test a-pages-data-chooses-no-dangerous-type
  (with-download-page ()
    (with-test-server (port)
      (dolist (type (list "text/html" "image/svg+xml" "application/xhtml+xml" "text/javascript"
                          "application/xml" "text/html; charset=utf-8"
                          (format nil "application/pdf~c~cX-Evil: 1" #\Return #\Linefeed)
                          "" "application/octet-stream"))
        (multiple-value-bind (status body headers)
            (fetch-download port (cons "type" type) '("name" . "page.html"))
          (declare (ignore body))
          (is (= 200 status) "~s answers" type)
          (is (equal "application/octet-stream" (response-header :content-type headers))
              "~s is sent as octets: ~a" type (response-header :content-type headers))
          (is (null (response-header :x-evil headers)) "~s adds no header" type)
          (is (string-prefix-p "attachment; filename=\"page.html.bin\""
                               (response-header :content-disposition headers))
              "~s is downloaded, named as octets: ~a" type
              (response-header :content-disposition headers))))
      (loop for (type sent name) in
            '(("application/pdf" "application/pdf" "a.pdf")
              ("APPLICATION/PDF" "application/pdf" "a.pdf")
              ("application/json" "application/json; charset=utf-8" "a.json")
              ("text/csv" "text/csv; charset=utf-8" "a.csv")
              ("text/plain" "text/plain; charset=utf-8" "a.txt")
              ("text/calendar" "text/calendar; charset=utf-8" "a.ics")
              ("image/png" "image/png" "a.png")
              ("image/jpeg" "image/jpeg" "a.jpg")
              ("image/webp" "image/webp" "a.webp")
              ("image/gif" "image/gif" "a.gif")
              ("application/zip" "application/zip" "a.zip")
              ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
               "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" "a.xlsx")
              ("application/vnd.openxmlformats-officedocument.wordprocessingml.document"
               "application/vnd.openxmlformats-officedocument.wordprocessingml.document" "a.docx"))
            do (multiple-value-bind (status body headers)
                   (fetch-download port (cons "type" type) '("name" . "a"))
                 (declare (ignore body))
                 (is (= 200 status))
                 (is (equal sent (response-header :content-type headers))
                     "~a is sent as ~a" type sent)
                 (is (equal name (disposition-name headers)) "~a is named ~a" type name))))))

(test a-pages-data-chooses-no-dangerous-name
  (with-download-page ()
    (with-test-server (port)
      (flet ((name-of (given &optional (type "application/pdf"))
               (multiple-value-bind (status body headers)
                   (fetch-download port (cons "type" type) (cons "name" given))
                 (declare (ignore body))
                 (is (= 200 status))
                 (let* ((value (response-header :content-disposition headers))
                        (quoted (subseq value (1+ (position #\" value))
                                        (position #\" value :from-end t)))
                        (encoded (subseq value (+ (search "filename*=UTF-8''" value) 17))))
                   (is (notany (lambda (c) (member c '(#\Return #\Linefeed))) value)
                       "~s: one line" given)
                   (is (notany (lambda (c) (member c '(#\" #\\))) quoted)
                       "~s: nothing to end the quoted name: ~a" given quoted)
                   (is (every (lambda (c) (or (alphanumericp c) (find c "!#$&+-.^_`|~%"))) encoded)
                       "~s: filename* is attr-chars and %XX: ~a" given encoded)
                   (is (every (lambda (c) (< (char-code c) 128)) quoted)
                       "~s: filename is ASCII" given)
                   (disposition-name headers)))))
        (is (equal "passwd.pdf" (name-of "../../etc/passwd")))
        (is (equal "report.pdf" (name-of "C:\\x\\report.pdf")))
        (is (equal "ab; c.pdf"
                   (name-of (format nil "a~c~cb\"; c~c~c.pdf" #\Return #\Linefeed
                                    (code-char #x202E) (code-char #x2028)))))
        (is (equal "rapport.html.pdf" (name-of "rapport.html")))
        (is (equal "run.sh.bin" (name-of "run.sh" "text/x-shellscript")))
        (is (equal "download.pdf" (name-of "")))
        (is (equal "download.pdf" (name-of "   ")))
        (let ((long (name-of (make-string 300 :initial-element #\a))))
          (is (= 200 (length long)))
          (is (eql 196 (search ".pdf" long :from-end t))))
        (is (equal "Økonomi «2026».pdf" (name-of "Økonomi «2026».pdf")))))))

(test a-download-is-refused-for-whom-the-page-is-refused
  (with-download-page ()
    (with-test-server (port)
      (multiple-value-bind (status body headers)
          (fetch-address port (download-path '("type" . "application/pdf")) :actor "viewer:vera")
        (is (= 403 status))
        (is (string-prefix-p "text/html" (response-header :content-type headers)))
        (is (null (search "%PDF-1" (sb-ext:octets-to-string body :external-format :utf-8))))
        (is (null (response-header :content-disposition headers))))
      (is (zerop *download-page-calls*) "the page's function did not run for the viewer")
      (multiple-value-bind (status body headers) (fetch-address port (download-path))
        (declare (ignore body))
        (is (= 303 status) "no session: to the login")
        (is (search "/login" (location headers))))
      (is (zerop *download-page-calls*) "nor for no one"))))

(test a-download-through-htmx-or-a-preload
  (with-download-page ()
    (with-test-server (port)
      (let ((path (download-path '("type" . "application/pdf") '("name" . "a.pdf"))))
        (multiple-value-bind (status body headers)
            (fetch-address port path :actor "employee:anna" :headers '(("HX-Request" . "true")))
          (is (= 200 status))
          (is (zerop (length body)) "no file to swap into the page")
          (is (equal path (response-header :hx-redirect headers))
              "the browser fetches it itself: ~a" (response-header :hx-redirect headers)))
        (multiple-value-bind (status body headers)
            (fetch-address port path :actor "employee:anna" :method :post
                           :headers '(("HX-Request" . "true")))
          (is (= 400 status))
          (is (null (response-header :content-disposition headers)))
          (is (null (search "%PDF-1" (sb-ext:octets-to-string body :external-format :utf-8)))))
        (multiple-value-bind (status body headers)
            (fetch-address port path :actor "employee:anna" :headers '(("Tun-Preload" . "true")))
          (is (= 204 status))
          (is (zerop (length body)))
          (is (equal "declined" (response-header :tun-preload headers))))
        (multiple-value-bind (status body headers)
            (fetch-address port path :actor "employee:anna" :method :post)
          (is (= 200 status) "a form's post without htmx downloads")
          (is (equalp #(37 80 68 70 45 49) body))
          (is (string-prefix-p "attachment" (response-header :content-disposition headers))))))))

(test make-download-checks-its-arguments
  (signals type-error (tun.web:make-download 42 :filename "a.pdf" :content-type "application/pdf"))
  (signals type-error (tun.web:make-download "x" :filename 'name))
  (let ((download (tun.web:make-download "æ" :filename nil :content-type nil)))
    (is (equal "download.bin" (tun.web:download-filename download)))
    (is (equal "application/octet-stream" (tun.web:download-content-type download)))
    (is (equalp #(195 166) (tun.web:download-octets download)))))

;;; ------------------------------------------------------------------
;;; A download from a public page (spec/ui.md 8, «Public pages» 6): decided
;;; by the page's own handler, answered as a staff page's.

(defparameter +public-made-files+
  `(("pdf" "application/pdf" "Økonomi «2026».pdf")
    ("json" "application/json" "data.json")
    ("html" "text/html" "page.html")
    ("svg" "image/svg+xml" "page.html")
    ("header" ,(format nil "application/pdf~c~cX-Evil: 1" #\Return #\Linefeed) "page.html"))
  "The files the test's public page makes on the spot, by the last part of
its path: the type and the name a page's data might give.")

(defun public-made-file-page (method parts form session)
  "/public-made/KIND: a file made on the spot, of KIND in +PUBLIC-MADE-FILES+;
anything else its 404."
  (declare (ignore method form session))
  (let ((made (assoc (first parts) +public-made-files+ :test #'equal)))
    (if (and made (null (rest parts)))
        (values 200 :download (tun.web:make-download +download-octets+
                                                     :content-type (second made)
                                                     :filename (third made)))
        (values 404 "Page not found" (list '(:p "Check the link in the email."))))))

(defvar *unreadable-by-link* '()
  "The ids of the notes the test's shared page no longer hands out: the
module's own rule of which records a link may still read.")

(defun shared-test-page (method parts form session)
  "/shared-test/ID/TOKEN/FILE-ID: the file FILE-ID of the note ID, whose
reading link has TOKEN, as a download; anything else, the page's 404.  The
pattern of spec/files.md 5.5, «From a public page»."
  (declare (ignore form session))
  (let ((download
          (and (member method '(:get :head)) (= (length parts) 3)
               (with-transaction (:read)
                 (with-actor ((system-actor "shared-link"))
                   (destructuring-bind (id token file-id) parts
                     (let ((note (fetch 'file-note id)))
                       (when (and note
                                  (constant-time-string= token (link-token "note-reading" id))
                                  (not (member id *unreadable-by-link* :test #'equal)))
                         (let ((file (find file-id (tun.files:attachments-of note)
                                           :key (lambda (file) (jget file "id"))
                                           :test #'equal)))
                           (when file
                             (tun.web:make-download
                              (tun.files:file-octets file-id)
                              :filename (jget file "filename")
                              :content-type (jget file "content_type"))))))))))))
    (if download
        (values 200 :download download)
        (values 404 "Page not found" (list '(:p "Check the link in the email."))))))

(defun link-token-of (purpose id)
  "The link token of PURPOSE for the record ID in the test's application."
  (with-application (*app*)
    (with-transaction (:read) (link-token purpose id))))

(defmacro with-public-download-pages (() &body body)
  "Run BODY with the test's public pages /public-made and /shared-test."
  `(unwind-protect
        (progn (tun.web:register-public-page "public-made" 'public-made-file-page)
               (tun.web:register-public-page "shared-test" 'shared-test-page)
               ,@body)
     (remhash "public-made" tun.web::*public-pages*)
     (remhash "shared-test" tun.web::*public-pages*)))

(defun is-no-file (status body headers what &key (octets +download-octets+))
  "Check that an answer STATUS, BODY, HEADERS is the page's 404 and holds
nothing of OCTETS.  A HEAD's BODY is NIL."
  (setf body (or body (make-array 0 :element-type '(unsigned-byte 8))))
  (is (= 404 status) "~a: the page's 404: ~a" what status)
  (is (null (response-header :content-disposition headers)) "~a: no file" what)
  (is (string-prefix-p "text/html" (response-header :content-type headers))
      "~a: a page: ~a" what (response-header :content-type headers))
  (is (null (search octets body)) "~a: none of the file's bytes" what)
  (is (or (zerop (length body))
          (search "Check the link in the email."
                  (sb-ext:octets-to-string body :external-format :utf-8)))
      "~a: the handler's own page" what))

(test a-public-page-answers-a-file-it-made-as-a-download
  (with-public-download-pages ()
    (with-test-server (port)
      (multiple-value-bind (status body headers) (fetch-address port "/public-made/pdf")
        (is (= 200 status))
        (is (equalp +download-octets+ body) "exactly the octets")
        (is (equal "application/pdf" (response-header :content-type headers)))
        (is (equal "6" (response-header :content-length headers)))
        (is (equal (concatenate 'string "attachment; filename=\"_konomi _2026_.pdf\"; "
                                "filename*=UTF-8''%C3%98konomi%20%C2%AB2026%C2%BB.pdf")
                   (response-header :content-disposition headers)))
        (is (equal "nosniff" (response-header :x-content-type-options headers)))
        (is (equal tun.web::+file-security-policy+
                   (response-header :content-security-policy headers)))
        (is (equal "same-origin" (response-header :cross-origin-resource-policy headers)))
        (is (equal "no-referrer" (response-header :referrer-policy headers)))
        (is (equal "no-store" (response-header :cache-control headers)))
        (is (null (response-header :set-cookie headers)) "no session for it"))
      (multiple-value-bind (status body headers) (fetch-address port "/public-made/json")
        (declare (ignore body))
        (is (= 200 status))
        (is (equal "application/json; charset=utf-8" (response-header :content-type headers))))
      (dolist (kind '("html" "svg" "header"))
        (multiple-value-bind (status body headers)
            (fetch-address port (format nil "/public-made/~a" kind))
          (declare (ignore body))
          (is (= 200 status))
          (is (equal "application/octet-stream" (response-header :content-type headers))
              "~a is sent as octets: ~a" kind (response-header :content-type headers))
          (is (null (response-header :x-evil headers)) "~a adds no header" kind)
          (is (string-prefix-p "attachment; filename=\"page.html.bin\""
                               (response-header :content-disposition headers))
              "~a: named as octets: ~a" kind (response-header :content-disposition headers))))
      (multiple-value-bind (status body headers)
          (fetch-address port "/public-made/pdf" :headers '(("Tun-Preload" . "true")))
        (is (= 204 status) "a preload is declined")
        (is (zerop (length body)))
        (is (null (response-header :content-disposition headers))))
      (multiple-value-bind (status body headers)
          (fetch-address port "/public-made/pdf" :method :post
                                                 :headers '(("HX-Request" . "true")))
        (is (= 400 status) "htmx's post is refused")
        (is (null (response-header :content-disposition headers)))
        (is (null (search +download-octets+ body)))))))

(test a-public-pages-file-goes-only-to-the-link-its-handler-checks
  (with-public-download-pages ()
    (with-test-server (port)
      (let* ((note (jget (call-ok "file_notes_create" "employee:anna" "title" "Delt") "id"))
             (other (jget (call-ok "file_notes_create" "employee:anna" "title" "Annen") "id"))
             (pdf (fixture "kvittering.pdf"))
             (file (jget (first (attach-over-api "employee:anna" "file_note" note
                                                 "kvittering ø.pdf" pdf))
                         "id"))
             (other-file (jget (first (attach-over-api "employee:anna" "file_note" other
                                                       "skjermbilde.png"
                                                       (fixture "skjermbilde.png")))
                               "id"))
             (token (link-token-of "note-reading" note))
             (other-token (link-token-of "note-reading" other))
             (answer-token (link-token-of "note-answer" note)))
        (flet ((shared (id token file-id)
                 (format nil "/shared-test/~a/~a/~a" id token file-id)))
          (multiple-value-bind (status body headers) (fetch-address port (shared note token file))
            (is (= 200 status) "the link's own file: ~a" status)
            (is (equalp pdf body) "exactly its bytes")
            (is (equal "application/pdf" (response-header :content-type headers)))
            (is (equal (concatenate 'string "attachment; filename=\"kvittering _.pdf\"; "
                                    "filename*=UTF-8''kvittering%20%C3%B8.pdf")
                       (response-header :content-disposition headers)))
            (is (equal "nosniff" (response-header :x-content-type-options headers)))
            (is (equal tun.web::+file-security-policy+
                       (response-header :content-security-policy headers)))
            (is (equal "no-store" (response-header :cache-control headers)))
            (is (null (response-header :set-cookie headers)) "no session for it"))
          (multiple-value-bind (status body headers)
              (fetch-address port (shared note token file) :method :head)
            (is (= 200 status) "HEAD with the right link: ~a" status)
            (is (zerop (length body)) "no body to a HEAD")
            (is (equal (princ-to-string (length pdf)) (response-header :content-length headers))))
          (loop for (path what) in
                (list (list (shared note "AAAAAAAAAAAAAAAAAAAA" file) "a token that is no token")
                      (list (shared note answer-token file) "a token of another purpose")
                      (list (shared note other-token file) "another record's token")
                      (list (shared other other-token file) "another record with its token")
                      (list (shared note token other-file) "another record's file")
                      (list (shared note token "fil_finnes_ikke") "a file that is none")
                      (list (format nil "/shared-test/~a/~a" note token) "no file")
                      (list (format nil "/shared-test/~a/~a/~a/x" note token file) "more after"))
                do (multiple-value-bind (status body headers) (fetch-address port path)
                     (is-no-file status body headers what :octets pdf))
                   (multiple-value-bind (status body headers)
                       (fetch-address port path :method :head)
                     (is-no-file status body headers (format nil "HEAD, ~a" what) :octets pdf)))
          (multiple-value-bind (status body headers)
              (fetch-address port (shared note token file) :method :post)
            (is-no-file status body headers "a post" :octets pdf))
          (setf (sb-ext:symbol-global-value '*unreadable-by-link*) (list note))
          (unwind-protect
               (multiple-value-bind (status body headers)
                   (fetch-address port (shared note token file))
                 (is-no-file status body headers "a record the module no longer hands out"
                             :octets pdf))
            (setf (sb-ext:symbol-global-value '*unreadable-by-link*) '()))
          (multiple-value-bind (status body headers)
              (fetch-address port (format nil "/files/~a" file))
            (declare (ignore body))
            (is (= 303 status) "/files/ID still sends no session to the login: ~a" status)
            (is (search "/login" (location headers)))))))))

(test a-public-page-without-a-download-answers-as-before
  (with-public-download-pages ()
    (with-test-server (port)
      (multiple-value-bind (status body headers) (fetch-address port "/public-made/none")
        (is (= 404 status) "the status the handler gave")
        (is (equal "text/html; charset=utf-8" (response-header :content-type headers)))
        (is (null (response-header :content-disposition headers)))
        (is (equal "no-referrer" (response-header :referrer-policy headers)))
        (is (string-prefix-p "default-src 'self'; script-src 'self'"
                             (response-header :content-security-policy headers))
            "the page's own policy, not a file's: ~a"
            (response-header :content-security-policy headers))
        (let ((page (sb-ext:octets-to-string body :external-format :utf-8)))
          (is (search "<title>Page not found" page) "the handler's heading: ~a"
              (subseq page 0 (min 400 (length page))))
          (is (search "Check the link in the email." page)))))))
