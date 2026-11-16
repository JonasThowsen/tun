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
