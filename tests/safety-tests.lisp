;;;; tests/safety-tests.lisp -- phase 2: actor, policy, confirmation,
;;;; idempotency and audit, all enforced in the operation execution path.

(in-package #:tun.tests)

(def-suite safety :in core)
(in-suite safety)

(defun audit-items (&rest args)
  (coerce (jget (apply #'call-ok "audit_list" "admin:ada" args) "items") 'list))

(defun widget-count ()
  (jget (call-ok "widgets_count" "viewer:vera") "count"))

(test actor-is-required-for-direct-calls
  (with-test-app ()
    (with-application (*app*)
      (let ((*actor* nil))
        (signals actor-error
          (widgets-create *app* (make-input (jobj "name" "x"))))))))

(test viewer-cannot-mutate-and-is-audited
  (with-test-app ()
    (multiple-value-bind (json code) (call "widgets_create" "viewer:vera" "name" "x" "request_key" "k1")
      (is (string= "forbidden" code))
      (is (stringp (jget (jget json "error") "message"))))
    (is (= 0 (widget-count)))
    (let ((entry (first (audit-items))))
      (is (string= "rejected" (jget entry "outcome")))
      (is (string= "widgets_create" (jget entry "tool")))
      (is (string= "viewer:vera" (jget entry "actor")))
      (is (string= "k1" (jget entry "request_key")))
      (is (string= "forbidden" (jget entry "error_code"))))))

(test policy-is-checked-before-lookup
  (with-test-app ()
    (multiple-value-bind (json code) (call "widgets_purge" "employee:anna" "id" "wdg_finnes_ikke")
      (declare (ignore json))
      (is (string= "forbidden" code)))
    (multiple-value-bind (json code) (call "widgets_purge" "admin:ada" "id" "wdg_finnes_ikke")
      (declare (ignore json))
      (is (string= "not_found" code)))
    (multiple-value-bind (json code) (call "widgets_archive" "viewer:vera" "id" "wdg_finnes_ikke")
      (declare (ignore json))
      (is (string= "forbidden" code)))))

(test read-operations-cannot-write
  (with-test-app ()
    (signals error (call "widgets_sneaky_read" "viewer:vera" "name" "x"))
    (is (= 0 (widget-count)))))

(test confirmation-two-step
  (with-test-app ()
    (let* ((id (jget (call-ok "widgets_create" "employee:anna" "name" "Rød") "id"))
           (first (call-ok "widgets_archive" "employee:anna" "id" id))
           (token (jget first "confirmation_token")))
      (is (eq t (jget first "confirmation_required")))
      (is (stringp token))
      (is (<= 43 (length token)) "token is high-entropy")
      (is (string= "2026-03-01T09:10:00Z" (jget first "expires_at")))
      (is (search "Rød" (jget first "summary")))
      (is (string= "aktiv" (jget (call-ok "widgets_get" "viewer:vera" "id" id) "status"))
          "no mutation without a token")
      (let ((done (call-ok "widgets_archive" "employee:anna" "id" id "confirmation_token" token)))
        (is (string= "arkivert" (jget done "status"))))
      (multiple-value-bind (json code)
          (call "widgets_archive" "employee:anna" "id" id "confirmation_token" token)
        (declare (ignore json))
        (is (string= "confirmation_invalid" code) "a token is one-time")))))

(test confirmation-token-is-bound-to-actor-tool-and-input
  (with-test-app ()
    (let* ((a (jget (call-ok "widgets_create" "employee:anna" "name" "A") "id"))
           (b (jget (call-ok "widgets_create" "employee:anna" "name" "B") "id"))
           (token (jget (call-ok "widgets_archive" "employee:anna" "id" a) "confirmation_token")))
      (is (string= "confirmation_invalid"
                   (nth-value 1 (call "widgets_archive" "employee:bob" "id" a "confirmation_token" token))))
      (is (string= "confirmation_invalid"
                   (nth-value 1 (call "widgets_archive" "employee:anna" "id" b "confirmation_token" token))))
      (is (string= "confirmation_invalid"
                   (nth-value 1 (call "widgets_archive" "employee:anna" "id" a "confirmation_token" "feil"))))
      (is (string= "aktiv" (jget (call-ok "widgets_get" "viewer:vera" "id" a) "status")))
      ;; Failed attempts did not burn the token for its rightful use.
      (is (string= "arkivert" (jget (call-ok "widgets_archive" "employee:anna" "id" a "confirmation_token" token)
                                    "status")))
      (let ((rejected (remove "ok" (audit-items) :key (lambda (e) (jget e "outcome")) :test #'string=)))
        (is (= 3 (length rejected)))
        (is (every (lambda (e) (string= "confirmation_invalid" (jget e "error_code"))) rejected))))))

(test confirmation-token-expires-after-ten-minutes
  (with-test-app ()
    (let* ((id (jget (call-ok "widgets_create" "employee:anna" "name" "Gammel") "id"))
           (token (jget (call-ok "widgets_archive" "employee:anna" "id" id) "confirmation_token")))
      (set-test-clock (application-clock *app*) (+ (parse-rfc3339 "2026-03-01T09:10:01Z")))
      (is (string= "confirmation_invalid"
                   (nth-value 1 (call "widgets_archive" "employee:anna" "id" id "confirmation_token" token)))))))

(test tokens-are-stored-hashed-and-never-audited
  (with-test-app ()
    (let* ((id (jget (call-ok "widgets_create" "employee:anna" "name" "Hemmelig") "id"))
           (token (jget (call-ok "widgets_archive" "employee:anna" "id" id) "confirmation_token")))
      (call-ok "widgets_archive" "employee:anna" "id" id "confirmation_token" token)
      (with-application (*app*)
        (with-transaction (:read)
          (let ((rows (select 'tun.core::confirmation)))
            (is (= 1 (length rows)))
            (is (string= (sha256-hex token) (tun.core::confirmation-token-hash (first rows))))
            (is (not (search token (to-json-string (mapcar #'entity->json rows))))))
          (is (not (search token (to-json-string (mapcar #'entity->json (select 'audit-entry))))))
          (is (not (search token (to-json-string (mapcar #'entity->json (select 'tun.core::receipt)))))))))))

(test idempotent-replay-returns-the-original-result
  (with-test-app ()
    (let ((first (call-ok "widgets_create" "employee:anna" "name" "Én" "request_key" "nøkkel-1"))
          (again (call-ok "widgets_create" "employee:anna" "name" "Én" "request_key" "nøkkel-1")))
      (is (string= (jget first "id") (jget again "id")))
      (is (string= (to-json-string first) (to-json-string again)))
      (is (= 1 (widget-count)))
      (is (= 1 (count "ok" (audit-items) :key (lambda (e) (jget e "outcome")) :test #'string=))))))

(test idempotency-conflict-on-changed-input
  (with-test-app ()
    (call-ok "widgets_create" "employee:anna" "name" "Én" "request_key" "k")
    (is (string= "idempotency_conflict"
                 (nth-value 1 (call "widgets_create" "employee:anna" "name" "To" "request_key" "k"))))
    (is (= 1 (widget-count)))
    (is (string= "idempotency_conflict" (jget (first (audit-items)) "error_code")))))

(test idempotency-key-is-scoped-to-the-actor
  (with-test-app ()
    (let ((a (call-ok "widgets_create" "employee:anna" "name" "Én" "request_key" "felles"))
          (b (call-ok "widgets_create" "employee:bob" "name" "Én" "request_key" "felles")))
      (is (string/= (jget a "id") (jget b "id")))
      (is (= 2 (widget-count))))))

(test confirmed-call-with-key-replays-instead-of-failing
  (with-test-app ()
    (let* ((id (jget (call-ok "widgets_create" "employee:anna" "name" "X") "id"))
           (token (jget (call-ok "widgets_archive" "employee:anna" "id" id "request_key" "arkiv")
                        "confirmation_token"))
           (done (call-ok "widgets_archive" "employee:anna" "id" id "confirmation_token" token
                          "request_key" "arkiv"))
           (retry (call-ok "widgets_archive" "employee:anna" "id" id "confirmation_token" token
                           "request_key" "arkiv")))
      (is (string= "arkivert" (jget done "status")))
      (is (string= (to-json-string done) (to-json-string retry))))))

(test audit-entry-commits-with-the-mutation
  (with-test-app ()
    (let ((before (length (audit-items))))
      (is (string= "conflict" (nth-value 1 (call "widgets_explode" "employee:anna" "name" "Bom"))))
      (is (= 0 (widget-count)) "the business write rolled back")
      (is (= before (length (audit-items))) "and so did its audit entry"))
    (let* ((w (call-ok "widgets_create" "employee:anna" "name" "Ok" "request_key" "r"))
           (entry (first (audit-items))))
      (is (string= "ok" (jget entry "outcome")))
      (is (string= "widget" (jget entry "entity_type")))
      (is (string= (jget w "id") (jget entry "entity_id")))
      (is (string= "employee:anna" (jget entry "actor")))
      (is (string= "r" (jget entry "request_key")))
      (is (= 1 (length (audit-items "entity_type" "widget" "entity_id" (jget w "id"))))))))

(test concurrent-calls-with-one-key-mutate-once
  (dolist (db (list nil (scratch-path "idem")))
    (with-test-app (:db db)
      (let ((results (run-concurrently 12 (lambda (i)
                                            (declare (ignore i))
                                            (call "widgets_create" "employee:anna"
                                                  "name" "Samtidig" "request_key" "samme")))))
        (is (every #'hash-table-p results) "no call failed: ~s" results)
        (is (= 1 (widget-count)) "store ~a" (if db "sqlite" "memory"))
        (is (= 1 (length (remove-duplicates (map 'list (lambda (r) (and (hash-table-p r) (jget r "id")))
                                                 results)
                                            :test #'equal))))))))

;;; ------------------------------------------------------------------
;;; Bodies that carry files (spec/files.md 4.3)

(defparameter +mib+ (* 1024 1024))

(defun raw-request (port head &key (body nil))
  "Send HEAD, the request line and headers as lines, and BODY's octets when
given; values the response's status line, or :CLOSED, and how long it took
in seconds."
  (let ((socket (usocket:socket-connect "127.0.0.1" port :element-type '(unsigned-byte 8)))
        (start (get-internal-real-time)))
    (unwind-protect
         (handler-case
             (let ((stream (usocket:socket-stream socket)))
               (write-sequence (sb-ext:string-to-octets (apply #'crlf (append head (list "")))
                                                        :external-format :utf-8)
                               stream)
               (when body (write-sequence body stream))
               (finish-output stream)
               (let ((line (with-output-to-string (out)
                             (loop for byte = (read-byte stream nil nil)
                                   while (and byte (/= byte 13))
                                   do (write-char (code-char byte) out)))))
                 (values (if (plusp (length line)) line :closed)
                         (/ (- (get-internal-real-time) start) internal-time-units-per-second))))
           (error () (values :closed 0)))
      (usocket:socket-close socket))))

(defun refused-unread-p (port head status)
  "True when HEAD, a request whose Content-Length promises a body never sent,
is answered STATUS within two seconds: before its body is read."
  (multiple-value-bind (line seconds) (raw-request port head)
    (and (stringp line) (search (format nil " ~d" status) line) (< seconds 2))))

(defun multipart-head (name filename)
  "The headers of the multipart part NAME, of a file FILENAME unless that is
NIL, and the blank line after them, as octets."
  (let ((line-end (format nil "~c~c" #\Return #\Newline)))
    (sb-ext:string-to-octets
     (if filename
         (format nil "Content-Disposition: form-data; name=\"~a\"; filename=\"~a\"~a~
                      Content-Type: application/octet-stream~a~a"
                 name filename line-end line-end line-end)
         (format nil "Content-Disposition: form-data; name=\"~a\"~a~a" name line-end line-end))
     :external-format :utf-8)))

(defun multipart-octets (boundary parts)
  "A multipart/form-data body with BOUNDARY: each part (NAME VALUE) or
(NAME FILENAME OCTETS)."
  (let ((line-end (format nil "~c~c" #\Return #\Newline)))
    (apply #'bytes
           (append (loop for part in parts
                         append (destructuring-bind (name value &optional (octets nil filep)) part
                                  (list (format nil "--~a~a" boundary line-end)
                                        (multipart-head name (and filep value))
                                        (if filep
                                            octets
                                            (sb-ext:string-to-octets value :external-format :utf-8))
                                        line-end)))
                   (list (format nil "--~a--~a" boundary line-end))))))

(defun post-octets (port path octets &key (content-type "application/json") headers)
  "POST OCTETS to PATH; values the status, the body as text and the headers."
  (multiple-value-bind (body status response-headers)
      (drakma:http-request (format nil "http://127.0.0.1:~d~a" port path)
                           :method :post :content octets :content-type content-type
                           :additional-headers headers :redirect nil :force-binary t)
    (values status (if body (sb-ext:octets-to-string body :external-format :utf-8) "")
            response-headers)))

(defun post-form (port path parts &key (actor "employee:anna") (boundary "tun-test-grense"))
  (post-octets port path (multipart-octets boundary parts)
               :content-type (format nil "multipart/form-data; boundary=~a" boundary)
               :headers (and actor `(("X-Tun-Actor" . ,actor)))))

(defun padded-png (octets)
  "A PNG of about OCTETS: the screenshot with zeros after it, which Tun drops."
  (bytes (fixture "skjermbilde.png") (make-array (- octets 16000) :initial-element 0)))

(defun padded-pdf (octets)
  "A PDF of exactly OCTETS, which Tun keeps as given."
  (bytes "%PDF-1.4" 10 (make-array (- octets 9) :initial-element 32)))

(defun tools-call-text (tool arguments)
  (sb-ext:string-to-octets
   (to-json-string (jobj "jsonrpc" "2.0" "id" 1 "method" "tools/call"
                         "params" (jobj "name" tool "arguments" arguments)))
   :external-format :utf-8))

(defvar *page-seen* nil "What the files test page last received.")

(defun files-test-page (method path form query)
  (declare (ignore path query))
  (cond ((not (eq method :post)) (values 200 "Filer" (list "skjema")))
        (t (setf *page-seen* form)
           (let ((files (jget form "filer")))
             (if (and files (jget form "title"))
                 (multiple-value-bind (json code)
                     (tun.web:web-call "file_notes_create" (jobj "title" (jget form "title")
                                                                 "screenshots" files))
                   (values (if code 422 200) "Filer"
                           (list (if code (tun.web:error-alert json) "lagret"))))
                 (values 200 "Filer" (list "mottatt")))))))

(defmacro with-files-page (() &body body)
  `(progn
     (tun.web:register-staff-page "filprove" 'files-test-page :policy :employee)
     (unwind-protect (progn ,@body)
       (remhash "filprove" tun.web::*staff-pages*))))

(defun content-length-head (method path length &rest headers)
  (list* (format nil "~a ~a HTTP/1.1" method path) "Host: x"
         (format nil "Content-Length: ~d" length) headers))

(test a-large-body-is-read-only-for-a-caller-who-may-send-files
  (with-test-server (port :identity :authenticated)
    (let ((employee (make-token (make-account "agent-ansatt" "agent" "employee")))
          (viewer (make-token (make-account "agent-leser" "agent" "viewer"))))
      (flet ((bearer (token) (format nil "Authorization: Bearer ~a" token))
             (authorization (token) `(("Authorization" . ,(format nil "Bearer ~a" token)))))
        (is (refused-unread-p port (content-length-head "POST" "/mcp" (* 3 +mib+)) 413))
        (is (refused-unread-p port (content-length-head "POST" "/api/attachments_add" (* 3 +mib+))
                              413))
        (is (refused-unread-p port (content-length-head "POST" "/api/registry_describe" (* 3 +mib+)
                                                        (bearer employee))
                              413)
            "a tool without files")
        (is (refused-unread-p port (content-length-head "POST" "/mcp" (* 3 +mib+) (bearer viewer))
                              413)
            "no tool with files admits a viewer")
        (is (refused-unread-p port (content-length-head "POST" "/api/attachments_add" (* 3 +mib+)
                                                        (bearer viewer))
                              413))
        (is (refused-unread-p port (content-length-head "POST" "/api/attachments_add" (* 17 +mib+)
                                                        (bearer employee))
                              413))
        (let* ((id (jget (call-ok "file_notes_create" "employee:anna" "title" "Stor") "id"))
               (body (tools-call-text "attachments_add"
                                      (jobj "entity" "file_note" "record_id" id
                                            "files" (files-json "stor.png"
                                                                (padded-png (* 9 +mib+)))))))
          (is (< (* 11 +mib+) (length body) (* 13 +mib+)))
          (multiple-value-bind (status text)
              (post-octets port "/mcp" body :headers (authorization employee))
            (is (= 200 status))
            (is (search "stor.png" text) "attached: ~a" (subseq text 0 (min 300 (length text))))))
        (multiple-value-bind (status text)
            (post-octets port "/mcp" (tools-call-text "registry_describe"
                                                      (jobj "x" (make-string (* 3 +mib+)
                                                                             :initial-element #\a)))
                         :headers (authorization employee))
          (is (= 413 status))
          (is (equal -32600 (jget (jget (parse-json text) "error") "code"))))
        (multiple-value-bind (status text)
            (post-octets port "/api/attachments_add"
                         (sb-ext:string-to-octets
                          (to-json-string
                           (jobj "entity" "file_note" "record_id" "fnt_x"
                                 "files" (jarr (list (jobj "filename"
                                                           (make-string (* 2 +mib+)
                                                                        :initial-element #\a)
                                                           "data" "AAAA")))))
                          :external-format :utf-8)
                         :headers (authorization employee))
          (declare (ignore text))
          (is (= 413 status) "a long string that is not a file's data"))))))

(test a-large-multipart-post-needs-a-person-the-page-admits
  (with-files-page ()
    (with-test-server (port)
      (let ((form "Content-Type: multipart/form-data; boundary=b"))
        (is (refused-unread-p port (content-length-head "POST" "/filprove" (* 27 +mib+)
                                                        "X-Tun-Actor: employee:anna" form)
                              413))
        (is (refused-unread-p port (content-length-head "POST" "/filprove" (* 3 +mib+)
                                                        "X-Tun-Actor: viewer:vera" form)
                              403)
            "a viewer, for an employee's page"))
      (multiple-value-bind (status text)
          (post-form port "/filprove" (list (list "filer" "a.pdf" (padded-pdf (* 10 +mib+)))
                                            (list "filer" "b.pdf" (padded-pdf (* 10 +mib+)))))
        (is (= 200 status))
        (is (search "mottatt" text))
        (is (= 2 (length (jget *page-seen* "filer"))))))))

(test a-multipart-post-is-for-a-signed-in-person
  (with-files-page ()
    (with-test-server (port)
      (let ((form "Content-Type: multipart/form-data; boundary=b"))
        (is (refused-unread-p port (content-length-head "POST" "/filprove" 1024 form) 401))
        (is (refused-unread-p port (content-length-head "POST" "/filprove" (* 3 +mib+) form) 401))
        (is (refused-unread-p port (content-length-head "POST" "/filprove" 1024 form
                                                        "Cookie: tun_public=pub_123")
                              401)
            "a public page's session is not one")))))

(test a-multipart-post-is-read-within-its-bounds
  (with-files-page ()
    (with-test-server (port)
      (let ((png (fixture "skjermbilde.png"))
            (temporary (directory (merge-pathnames "*.*" hunchentoot:*tmp-directory*))))
        (flet ((answer (parts &rest keys)
                 (multiple-value-bind (status text) (apply #'post-form port "/filprove" parts keys)
                   (list status text)))
               (says (answer status message)
                 (and (= status (first answer)) (search message (second answer)) t)))
          (is (says (answer (loop for i below 65 collect (list (format nil "f~d" i) "x")))
                    413 "Skjemaet har for mange felt (høyst 64)."))
          (is (says (answer (loop for i below 11
                                  collect (list "filer" (format nil "~d.png" i) png)))
                    413 "Du kan sende høyst 10 filer om gangen."))
          (is (says (answer (list (list (make-string 9000 :initial-element #\n) "x")))
                    413 "En del av skjemaet har for lange overskrifter (høyst 8 KB)."))
          (is (says (answer (list (list "title" (make-string (1+ +mib+) :initial-element #\a))))
                    413 "Et felt i skjemaet er lengre enn 1 MB."))
          (let ((unreadable "Skjemaet kunne ikke leses."))
            (flet ((raw-form (content-type octets)
                     (multiple-value-bind (status text)
                         (post-octets port "/filprove" octets
                                      :content-type content-type
                                      :headers '(("X-Tun-Actor" . "employee:anna")))
                       (list status text))))
              (is (says (raw-form "multipart/form-data" (bytes "--b" 13 10)) 400 unreadable)
                  "no boundary")
              (is (says (raw-form (format nil "multipart/form-data; boundary=~a"
                                          (make-string 71 :initial-element #\b))
                                  (bytes "--b" 13 10))
                        400 unreadable)
                  "a boundary of 71 characters")
              (is (says (raw-form "multipart/form-data; boundary=b"
                                  (bytes "--b" 13 10 "Content-Disposition: form-data; name=\"a\""
                                         13 10 13 10 "x"))
                        400 unreadable)
                  "no closing delimiter")
              (is (says (raw-form "multipart/form-data; boundary=b"
                                  (bytes "--b" 13 10 "Content-Type: text/plain" 13 10 13 10
                                         "x" 13 10 "--b--" 13 10))
                        400 unreadable)
                  "no Content-Disposition")
              (is (says (raw-form "multipart/form-data; boundary=b"
                                  (bytes "--b" 13 10 "Content-Disposition: form-data" 13 10 13 10
                                         "x" 13 10 "--b--" 13 10))
                        400 unreadable)
                  "no name")))
          (is (says (answer (append (loop for i below 10
                                          collect (list "filer" (format nil "~d.png" i) png))
                                    (loop for i below 54 collect (list (format nil "t~d" i) "x"))))
                    200 "mottatt"))
          (is (= 10 (length (jget *page-seen* "filer"))))
          ;; Names as browsers write them.
          (let ((disposition "Content-Disposition: form-data; name=\"filer\"; filename="))
            (post-octets port "/filprove"
                         (bytes "--b" 13 10 disposition "\"a%22b%0D%0Ac%41" #xC3 #x28 ".png\""
                                13 10 13 10 png 13 10
                                "--b" 13 10 disposition "\"\"" 13 10 13 10 13 10
                                "--b" 13 10 disposition "\"tom.png\"" 13 10 13 10 13 10
                                "--b--" 13 10)
                         :content-type "multipart/form-data; boundary=b"
                         :headers '(("X-Tun-Actor" . "employee:anna"))))
          (let ((files (coerce (jget *page-seen* "filer") 'list)))
            (is (= 2 (length files)) "the part with nothing chosen is left out")
            (is (equal (format nil "a\"b~c~cc%41~c(.png" #\Return #\Newline (code-char #xFFFD))
                       (jget (first files) "filename")))
            (is (equal "tom.png" (jget (second files) "filename"))))
          (multiple-value-bind (status text)
              (post-form port "/filprove" (list (list "title" "Tom fil")
                                                (list "filer" "tom.png" (bytes))))
            (is (= 422 status))
            (is (search "«tom.png»: Filen er tom." text)))
          (is (equal temporary (directory (merge-pathnames "*.*" hunchentoot:*tmp-directory*)))
              "nothing written to a temporary file"))))))

(defvar *hold-files* nil "A semaphore FILES-HOLD waits on, or NIL.")
(defvar *held-files* (list 0) "How many FILES-HOLD calls wait.")

(define-operation files-hold ((files :type (files :max 10) :required t :label "Filer"))
    ;; A wait holds no transaction, so four can be held at once.
    (:entity file-note :kind :wait :policy :employee :title "Holder filer")
  (sb-ext:atomic-incf (car *held-files*))
  (unwind-protect (sb-thread:wait-on-semaphore *hold-files* :timeout 30)
    (sb-ext:atomic-decf (car *held-files*)))
  (jobj "held" (length files)))

(defun files-hold-body ()
  "The body of a large call of files_hold over /mcp."
  (tools-call-text "files_hold" (jobj "files" (files-json "a.png" (padded-png (* 3 +mib+))))))

(defun files-hold-head (body)
  "The request line and headers that send BODY to /mcp as Anna."
  (list "POST /mcp HTTP/1.1" "Host: x" "X-Tun-Actor: employee:anna"
        "Content-Type: application/json" (format nil "Content-Length: ~d" (length body))))

(test four-large-requests-are-answered-at-once
  (with-test-server (port)
    (let* ((semaphore (sb-thread:make-semaphore :count 0))
           (body (files-hold-body))
           (head (files-hold-head body)))
      (setf *hold-files* semaphore)
      (unwind-protect
           (let ((threads (loop repeat 4
                                collect (sb-thread:make-thread
                                         (lambda () (raw-request port head :body body))))))
             (loop repeat 100 until (= 4 (car *held-files*)) do (sleep 0.1))
             (is (= 4 (car *held-files*)) "four are held in their operation")
             (is (refused-unread-p port (append head (list "X-Unused: 1")) 503)
                 "a fifth is refused before its body is read")
             (is (= 200 (post-octets port "/api/registry_describe" (bytes "{}")
                                     :headers '(("X-Tun-Actor" . "viewer:vera"))))
                 "a small call is answered as usual")
             (sb-thread:signal-semaphore semaphore 1)
             (loop repeat 100 until (= 3 (car *held-files*)) do (sleep 0.1))
             (let ((fifth (sb-thread:make-thread (lambda () (raw-request port head :body body)))))
               (sb-thread:signal-semaphore semaphore 10)
               (is (search " 200" (princ-to-string (sb-thread:join-thread fifth)))
                   "taken again once one has finished"))
             (mapc #'sb-thread:join-thread threads))
        (setf *hold-files* nil)
        (sb-thread:signal-semaphore semaphore 10)))))

(defun raw-response (port head)
  "Send HEAD, a request without the body its Content-Length promises, and
return the whole response as text: what is answered before the body is read."
  (let ((socket (usocket:socket-connect "127.0.0.1" port :element-type '(unsigned-byte 8))))
    (unwind-protect
         (let ((stream (usocket:socket-stream socket)))
           (write-sequence (sb-ext:string-to-octets (apply #'crlf (append head (list "")))
                                                    :external-format :utf-8)
                           stream)
           (finish-output stream)
           (let ((octets (make-array 0 :element-type '(unsigned-byte 8)
                                       :adjustable t :fill-pointer 0)))
             (handler-case (loop for byte = (read-byte stream nil nil) while byte
                                 do (vector-push-extend byte octets))
               (error () nil))
             (sb-ext:octets-to-string octets :external-format :utf-8)))
      (usocket:socket-close socket))))

(test a-page-post-meeting-full-places-gets-a-page
  (with-files-page ()
    (with-test-server (port)
      (let* ((semaphore (sb-thread:make-semaphore :count 0))
             (body (files-hold-body))
             (head (files-hold-head body)))
        (setf *hold-files* semaphore)
        (unwind-protect
             (let ((threads (loop repeat 4
                                  collect (sb-thread:make-thread
                                           (lambda () (raw-request port head :body body))))))
               (loop repeat 100 until (= 4 (car *held-files*)) do (sleep 0.1))
               (let ((answer (raw-response
                              port (list "POST /filprove HTTP/1.1" "Host: x"
                                         "X-Tun-Actor: employee:anna"
                                         "Content-Type: multipart/form-data; boundary=b"
                                         (format nil "Content-Length: ~d" (* 3 +mib+))))))
                 (is (search " 503" answer))
                 (is (search "Serveren tar imot mange filer akkurat nå." answer))
                 (is (search "Content-Type: text/html" answer))
                 (is (search "Retry-After: 1" answer)))
               (sb-thread:signal-semaphore semaphore 10)
               (mapc #'sb-thread:join-thread threads))
          (setf *hold-files* nil)
          (sb-thread:signal-semaphore semaphore 10))))))

(test a-large-body-must-arrive-in-time
  (let ((limit tun.http:*large-body-seconds*)
        (places tun.http:*large-body-places*))
    ;; Globals: the server's threads read them.
    (setf tun.http:*large-body-seconds* 2
          tun.http:*large-body-places* 1)
    (unwind-protect
         (with-test-server (port)
           (let* ((socket (usocket:socket-connect "127.0.0.1" port
                                                  :element-type '(unsigned-byte 8)))
                  (stream (usocket:socket-stream socket))
                  (start (get-internal-real-time)))
             (unwind-protect
                  (progn
                    (write-sequence (sb-ext:string-to-octets
                                     (crlf "POST /api/attachments_add HTTP/1.1" "Host: x"
                                           "X-Tun-Actor: employee:anna"
                                           "Content-Type: application/json"
                                           (format nil "Content-Length: ~d" (* 3 +mib+)) "")
                                     :external-format :latin-1)
                                    stream)
                    (write-sequence (bytes "{\"entity\": ") stream)
                    (finish-output stream)
                    (let ((line (with-output-to-string (out)
                                  (handler-case
                                      (loop for byte = (read-byte stream nil nil)
                                            while (and byte (/= byte 13))
                                            do (write-char (code-char byte) out))
                                    (error () nil)))))
                      (is (< (/ (- (get-internal-real-time) start)
                                internal-time-units-per-second)
                             6)
                          "cut off at the limit")
                      (is (search " 408" line) "answered 408: ~s" line)))
               (usocket:socket-close socket))
             ;; With one place, a large request is taken again only if it was freed.
             (let ((body (sb-ext:string-to-octets
                          (to-json-string (jobj "entity" "file_note" "record_id" "fnt_x"
                                                "files" (files-json "a.png"
                                                                    (padded-png (* 3 +mib+)))))
                          :external-format :utf-8)))
               (is (= 404 (post-octets port "/api/attachments_add" body
                                       :headers '(("X-Tun-Actor" . "employee:anna"))))
                   "the place was freed"))))
      (setf tun.http:*large-body-seconds* limit
            tun.http:*large-body-places* places))))

;;; The memory a large request takes, in a server whose heap is the image's
;;; default (spec/files.md 4.3, 5.4): a process of its own, so this suite's
;;; larger heap does not hide a request that needs more.

(defmacro with-default-heap-server ((port) &body body)
  "Run BODY with PORT a server of tests/fixtures/files-heap-server.lisp in a
process started with --dynamic-space-size 2048; BODY's value and whether the
process was still running after it."
  (let ((process (gensym "PROCESS")) (line (gensym "LINE")))
    `(let* ((,port (free-port))
            (,process (uiop:launch-program
                       (list "sbcl" "--dynamic-space-size" "2048" "--noinform" "--non-interactive"
                             "--no-userinit" "--no-sysinit" "--load"
                             (namestring (asdf:system-relative-pathname
                                          "tun" "tests/fixtures/files-heap-server.lisp"))
                             "--port" (princ-to-string ,port))
                       ;; Its standard input closes when this process ends,
                       ;; and the server ends with it.
                       :input :stream :output :stream :error-output nil)))
       (unwind-protect
            (progn
              (loop for ,line = (read-line (uiop:process-info-output ,process) nil nil)
                    until (or (null ,line) (search "ready" ,line)))
              (values (progn ,@body) (uiop:process-alive-p ,process)))
         (uiop:terminate-process ,process :urgent t)
         (uiop:wait-process ,process)))))

(defun ordinary-reads (port seconds)
  "Threads that ask for /health and registry_describe for SECONDS; join them
for how many answers were not 200."
  (loop repeat 4
        collect (sb-thread:make-thread
                 (lambda ()
                   (let ((end (+ (get-internal-real-time)
                                 (* seconds internal-time-units-per-second)))
                         (bad 0))
                     (loop while (< (get-internal-real-time) end)
                           do (unless (eql 200 (ignore-errors (fetch-file port "/health")))
                                (incf bad))
                              (unless (eql 200 (ignore-errors
                                                (post-octets port "/mcp"
                                                             (tools-call-text "registry_describe"
                                                                              (jobj))
                                                             :headers '(("X-Tun-Actor"
                                                                         . "viewer:vera")))))
                                (incf bad)))
                     bad)))))

(defun large-png (octets)
  "A PNG of about OCTETS that Tun stores whole: the screenshot with one more
IDAT chunk, which Tun keeps as it is and never inflates."
  (let ((png (fixture "skjermbilde.png")))
    (png-with png :before-idat (list (png-chunk "IDAT" (make-array (- octets (length png) 12)
                                                                   :initial-element 0))))))

(defun heap-note (port headers)
  "A new note on the heap server; its id."
  (jget (parse-json (nth-value 1 (post-octets port "/api/heap_notes_create"
                                              (bytes "{\"title\": \"Stor\"}")
                                              :headers headers)))
        "id"))

(test four-requests-at-the-largest-bounds-fit-the-default-heap
  (multiple-value-bind (statuses alive)
      (with-default-heap-server (port)
        (let* ((headers '(("X-Tun-Actor" . "employee:anna")))
               (note (heap-note port headers))
               (six (large-png (round (* 5.85 +mib+))))
               (arguments (jobj "entity" "heap_note" "record_id" note
                                "files" (files-json "a.png" six "b.png" six)))
               (mcp (tools-call-text "attachments_add" arguments))
               (api (sb-ext:string-to-octets (to-json-string arguments) :external-format :utf-8))
               (form (list (list "note" note)
                           (list "filer" "a.png" (large-png (* 10 +mib+)))
                           (list "filer" "b.png" (large-png (* 10 +mib+)))
                           (list "filer" "c.png" (large-png (* 5 +mib+))))))
          (is (< (* 15 +mib+) (length mcp) (* 16 +mib+)))
          (is (< (* 15 +mib+) (length api) (* 16 +mib+)))
          (loop repeat 3
                append (let ((readers (ordinary-reads port 3))
                             (large (list (sb-thread:make-thread
                                           (lambda ()
                                             (post-octets port "/mcp" mcp :headers headers)))
                                          (sb-thread:make-thread
                                           (lambda () (post-octets port "/api/attachments_add" api
                                                                   :headers headers)))
                                          (sb-thread:make-thread
                                           (lambda () (post-form port "/heap" form)))
                                          (sb-thread:make-thread
                                           (lambda () (post-form port "/heap" form))))))
                         (prog1 (mapcar #'sb-thread:join-thread large)
                           (is (every #'zerop (mapcar #'sb-thread:join-thread readers))
                               "ordinary reads answered"))))))
    (is (every (lambda (status) (eql 200 status)) statuses)
        "every large request answered: ~s" statuses)
    (is-true alive "the server is still up")))

(test thirty-two-fetches-of-a-large-file-fit-the-default-heap
  (multiple-value-bind (lengths alive)
      (with-default-heap-server (port)
        (let* ((headers '(("X-Tun-Actor" . "employee:anna")))
               (note (parse-json (nth-value 1 (post-octets port "/api/heap_notes_create"
                                                           (bytes "{\"title\": \"Stor\"}")
                                                           :headers headers))))
               (added (parse-json
                       (nth-value 1 (post-octets port "/api/attachments_add"
                                                 (sb-ext:string-to-octets
                                                  (to-json-string
                                                   (jobj "entity" "heap_note"
                                                         "record_id" (jget note "id")
                                                         "files" (files-json
                                                                  "stor.pdf"
                                                                  (padded-pdf (* 10 +mib+)))))
                                                  :external-format :utf-8)
                                                 :headers headers))))
               (url (jget (aref (jget added "items") 0) "url"))
               (readers (ordinary-reads port 5))
               (fetches (loop repeat 32
                              collect (sb-thread:make-thread
                                       (lambda ()
                                         (multiple-value-bind (status body)
                                             (fetch-file port url :actor "viewer:vera")
                                           (and (eql 200 status) (length body))))))))
          (prog1 (mapcar #'sb-thread:join-thread fetches)
            (is (every #'zerop (mapcar #'sb-thread:join-thread readers))
                "ordinary reads answered"))))
    (is (every (lambda (length) (eql (* 10 +mib+) length)) lengths)
        "every fetch got the whole file")
    (is-true alive "the server is still up")))

;;; ------------------------------------------------------------------
;;; Long strings in a body that may carry files (spec/files.md 4.1, 4.3)

(test a-file-of-about-a-megabyte-is-taken-over-api-and-mcp
  (with-test-server (port)
    (let* ((headers '(("X-Tun-Actor" . "employee:anna")))
           (id (jget (call-ok "file_notes_create" "employee:anna" "title" "En megabyte") "id"))
           (arguments (jobj "entity" "file_note" "record_id" id
                            "files" (files-json "megabyte.png" (large-png (* 1 +mib+)))))
           (api (sb-ext:string-to-octets (to-json-string arguments) :external-format :utf-8))
           (mcp (tools-call-text "attachments_add" arguments)))
      (is (< +mib+ (length api) (* 2 +mib+)) "its data is over 1 MiB, the body under 2 MiB")
      (is (= 200 (post-octets port "/api/attachments_add" api :headers headers)))
      (multiple-value-bind (status text) (post-octets port "/mcp" mcp :headers headers)
        (is (= 200 status))
        (is (search "megabyte.png" text) "attached over MCP: ~a"
            (subseq text 0 (min 200 (length text)))))
      (is (= 2 (note-file-count id))))))

(defun last-request (kind)
  "The request of KIND (:api, :mcp) the history finished last."
  (find kind (finished-requests) :key #'request-kind))

(defun longest-record-string (record)
  "The length of the longest string RECORD, a request's record, holds."
  (reduce #'max (mapcar #'length (record-strings record)) :initial-value 0))

(test only-a-files-data-may-be-long-in-keys-too
  (with-test-server (port)
    (let* ((headers '(("X-Tun-Actor" . "employee:anna")))
           (key (make-string (round (* 1.5 +mib+)) :initial-element #\k))
           (arguments (jobj "entity" "file_note" "record_id" "fnt_x"
                            "files" (jarr (list (jobj "filename" "a.png" key "x"
                                                      "data" (make-string
                                                              (* 2 +mib+)
                                                              :initial-element #\A)))))))
      (multiple-value-bind (status text)
          (post-octets port "/api/attachments_add"
                       (sb-ext:string-to-octets (to-json-string arguments) :external-format :utf-8)
                       :headers headers)
        (is (= 413 status))
        (is (search "Bare innholdet i en fil kan være lengre enn 1 MB." text))
        (is (< (longest-string text) +mib+) "the answer does not repeat the key")
        (is (<= (longest-record-string (last-request :api)) +mib+)
            "the request's record holds no string over 1 MiB"))
      (multiple-value-bind (status text)
          (post-octets port "/mcp" (tools-call-text "attachments_add" arguments) :headers headers)
        (is (= 413 status))
        (is (search "Bare innholdet i en fil kan være lengre enn 1 MB." text))
        (is (<= (longest-record-string (last-request :mcp)) +mib+))))))

(test each-refusal-of-a-large-body-says-its-own-reason
  (with-test-server (port)
    (let ((headers '(("X-Tun-Actor" . "employee:anna"))))
      (multiple-value-bind (status text)
          (post-octets port "/mcp" (tools-call-text "registry_describe"
                                                    (jobj "x" (make-string (* 3 +mib+)
                                                                           :initial-element #\a)))
                       :headers headers)
        (is (= 413 status))
        (is (search "Over 2 MB tas bare imot for et verktøy som tar filer." text)))
      (multiple-value-bind (status text)
          (post-octets port "/mcp" (tools-call-text "registry_describe"
                                                    (jobj "x" (make-string (round (* 1.5 +mib+))
                                                                           :initial-element #\a)))
                       :headers headers)
        (is (= 413 status) "a long string under 2 MiB")
        (is (search "Bare innholdet i en fil kan være lengre enn 1 MB." text))))))

(test a-multipart-post-from-another-site-is-refused-unread
  (with-files-page ()
    (with-test-server (port)
      (is (refused-unread-p port (content-length-head
                                  "POST" "/filprove" 1024
                                  "X-Tun-Actor: employee:anna"
                                  "Content-Type: multipart/form-data; boundary=b"
                                  "Sec-Fetch-Site: cross-site")
                            403)))))

(test a-posted-part-name-is-not-interned
  (with-files-page ()
    (with-test-server (port)
      (let ((name (format nil "del-~a" (random-token-string 40))))
        (post-form port "/filprove" (list (list name "x.png" (fixture "skjermbilde.png"))))
        (is (jget *page-seen* name) "the page has the part")
        (is (null (find-symbol name :keyword)) "and no symbol was made for its name")))))

;;; ------------------------------------------------------------------
;;; A refusal ends its connection (spec/files.md 4.3)

(defun smuggled ()
  "A second request, sent where a refused request's body would be."
  (crlf "GET /health HTTP/1.1" "Host: x" ""))

(defun answers-on-one-connection (port head &key (seconds 3))
  "Send HEAD, a request whose Content-Length is that of +SMUGGLED+, and
+SMUGGLED+ at once after it; values how many answers came on the
connection, and whether it ended within SECONDS."
  (let ((socket (usocket:socket-connect "127.0.0.1" port :element-type '(unsigned-byte 8)))
        (octets (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0)))
    (unwind-protect
         (let ((stream (usocket:socket-stream socket)))
           (write-sequence (sb-ext:string-to-octets
                            (concatenate 'string (apply #'crlf (append head (list ""))) (smuggled))
                            :external-format :latin-1)
                           stream)
           (finish-output stream)
           (let ((ended (handler-case
                            (sb-sys:with-deadline (:seconds seconds)
                              (loop for byte = (read-byte stream nil nil)
                                    while byte do (vector-push-extend byte octets)
                                    finally (return t)))
                          (sb-sys:deadline-timeout () nil)
                          (error () t))))
             (values (count-matches "HTTP/1\\.1 \\d{3}"
                                    (sb-ext:octets-to-string octets :external-format :latin-1))
                     ended)))
      (usocket:socket-close socket))))

(defun one-answer-then-end-p (port head)
  (multiple-value-bind (answers ended) (answers-on-one-connection port head)
    (and (= 1 answers) ended)))

(test a-request-refused-unread-ends-its-connection
  (with-files-page ()
    (with-test-server (port)
      (let ((length (format nil "Content-Length: ~d" (length (smuggled))))
            (form "Content-Type: multipart/form-data; boundary=b"))
        (is (one-answer-then-end-p port (list "POST /filprove HTTP/1.1" "Host: x" length form))
            "401: a multipart post without a session")
        (is (one-answer-then-end-p port (list "POST /filprove HTTP/1.1" "Host: x" length form
                                              "X-Tun-Actor: employee:anna"
                                              "Sec-Fetch-Site: cross-site"))
            "403: from another site")
        (is (one-answer-then-end-p port (list "POST /mcp HTTP/1.1" "Host: x"
                                              (format nil "Content-Length: ~d" (* 3 +mib+))))
            "413: over the bound")
        (let ((places tun.http:*large-body-places*))
          (setf tun.http:*large-body-places* 0)   ; global: the server's threads read it
          (unwind-protect
               (is (one-answer-then-end-p port (list "POST /api/attachments_add HTTP/1.1"
                                                     "Host: x" "X-Tun-Actor: employee:anna"
                                                     (format nil "Content-Length: ~d"
                                                             (* 300 1024))))
                   "503: every place taken")
            (setf tun.http:*large-body-places* places)))))))

(test a-body-past-its-time-ends-its-connection-at-once
  (let ((limit tun.http:*large-body-seconds*))
    (setf tun.http:*large-body-seconds* 1)
    (unwind-protect
         (with-test-server (port)
           (let* ((socket (usocket:socket-connect "127.0.0.1" port
                                                  :element-type '(unsigned-byte 8)))
                  (stream (usocket:socket-stream socket))
                  (start (get-internal-real-time))
                  (trickle nil))
             (unwind-protect
                  (progn
                    (write-sequence (sb-ext:string-to-octets
                                     (crlf "POST /api/attachments_add HTTP/1.1" "Host: x"
                                           "X-Tun-Actor: employee:anna"
                                           (format nil "Content-Length: ~d" (* 300 1024)) "")
                                     :external-format :latin-1)
                                    stream)
                    (finish-output stream)
                    ;; A sender that trickles a byte now and then.
                    (setf trickle (sb-thread:make-thread
                                   (lambda ()
                                     (handler-case (loop repeat 30
                                                         do (write-byte 32 stream)
                                                            (finish-output stream)
                                                            (sleep 0.2))
                                       (error () nil)))))
                    (let ((text (with-output-to-string (out)
                                  (handler-case
                                      (sb-sys:with-deadline (:seconds 4)
                                        (loop for byte = (read-byte stream nil nil)
                                              while byte do (write-char (code-char byte) out)))
                                    (sb-sys:deadline-timeout () (write-string "<open>" out))
                                    (error () nil)))))
                      (is (search " 408" text) "answered 408")
                      (is (not (search "<open>" text)) "and the connection ended")
                      (is (< (- (get-internal-real-time) start)
                             (* 4 internal-time-units-per-second))
                          "at once, though the sender still trickles")))
               (when trickle (sb-thread:join-thread trickle :default nil))
               (usocket:socket-close socket))))
      (setf tun.http:*large-body-seconds* limit))))

;;; Files of as many small pieces as Tun takes cost what their octets cost
;;; (spec/files.md 2.1), in the default heap.

(defun many-piece-files ()
  "One file of each format with about 99 000 kept pieces, as (NAME OCTETS)."
  (list (list "mange.jpg" (many-piece-jpeg 99000)) (list "mange.png" (many-piece-png 99000))
        (list "mange.gif" (many-piece-gif 99000)) (list "mange.webp" (many-piece-webp 99000))))

(test many-piece-files-at-the-bounds-fit-the-default-heap
  (multiple-value-bind (statuses alive)
      (with-default-heap-server (port)
        (let* ((headers '(("X-Tun-Actor" . "employee:anna")))
               (note (heap-note port headers))
               (files (many-piece-files))
               (arguments (jobj "entity" "heap_note" "record_id" note
                                "files" (apply #'files-json (apply #'append files))))
               (mcp (tools-call-text "attachments_add" arguments))
               (api (sb-ext:string-to-octets (to-json-string arguments) :external-format :utf-8))
               (form (cons (list "note" note)
                           (mapcar (lambda (file) (list "filer" (first file) (second file)))
                                   files))))
          (loop repeat 3
                append (let ((readers (ordinary-reads port 3))
                             (large (list (sb-thread:make-thread
                                           (lambda ()
                                             (post-octets port "/mcp" mcp :headers headers)))
                                          (sb-thread:make-thread
                                           (lambda () (post-octets port "/api/attachments_add" api
                                                                   :headers headers)))
                                          (sb-thread:make-thread
                                           (lambda () (post-form port "/heap" form)))
                                          (sb-thread:make-thread
                                           (lambda () (post-form port "/heap" form))))))
                         (prog1 (mapcar #'sb-thread:join-thread large)
                           (is (every #'zerop (mapcar #'sb-thread:join-thread readers))
                               "ordinary reads answered"))))))
    (is (every (lambda (status) (eql 200 status)) statuses)
        "every request answered and its files stored: ~s" statuses)
    (is-true alive "the server is still up")))

(test a-burst-of-calls-with-many-piece-files-fits-the-default-heap
  (multiple-value-bind (statuses alive)
      (with-default-heap-server (port)
        (let* ((headers '(("X-Tun-Actor" . "employee:anna")))
               (note (heap-note port headers))
               (bodies (mapcar (lambda (file)
                                 (sb-ext:string-to-octets
                                  (to-json-string
                                   (jobj "entity" "heap_note" "record_id" note
                                         "files" (files-json (first file) (second file))))
                                  :external-format :utf-8))
                               (remove "mange.png" (many-piece-files) :key #'first
                                                                      :test #'string=)))
               (threads (loop for i below 48
                              collect (let ((body (nth (mod i (length bodies)) bodies)))
                                        (sb-thread:make-thread
                                         (lambda ()
                                           (post-octets port "/api/attachments_add" body
                                                        :headers headers)))))))
          (is (every (lambda (body) (< (length body) (* 2 +mib+))) bodies) "each under 2 MiB")
          (mapcar #'sb-thread:join-thread threads)))
    (is (every (lambda (status) (member status '(200 503))) statuses)
        "each answered, stored or told to come back: ~s" statuses)
    (is (<= 4 (count 200 statuses)) "and those with a place are stored")
    (is-true alive "the server is still up")))

;;; ------------------------------------------------------------------
;;; How many values a request's JSON may hold (core.md §7.5)

(defun empty-objects (count)
  "JSON text of an array of COUNT empty objects."
  (with-output-to-string (out)
    (write-char #\[ out)
    (dotimes (i count) (when (plusp i) (write-char #\, out)) (write-string "{}" out))
    (write-char #\] out)))

(defun structured-body (prefix count)
  "A JSON object's text: PREFIX, its first members as text (or empty), then
\"x\": an array of COUNT empty objects."
  (sb-ext:string-to-octets
   (format nil "{~a~:[~;,~]\"x\": ~a}" prefix (plusp (length prefix)) (empty-objects count))
   :external-format :utf-8))

(test a-body-of-too-many-values-is-refused
  (with-test-server (port)
    (let ((headers '(("X-Tun-Actor" . "viewer:vera"))))
      (multiple-value-bind (status text)
          (post-octets port "/api/registry_describe" (structured-body "" 6000) :headers headers)
        (is (= 413 status))
        (is (search "Forespørselen har for mange JSON-verdier (høyst 10 000)." text)))
      (multiple-value-bind (status text)
          (post-octets port "/mcp"
                       (sb-ext:string-to-octets
                        (format nil "{\"jsonrpc\": \"2.0\", \"id\": 1, ~
                                     \"method\": \"tools/call\", \"params\": ~
                                     {\"name\": \"registry_describe\", \"arguments\": {\"x\": ~a}}}"
                                (empty-objects 6000))
                        :external-format :utf-8)
                       :headers headers)
        (is (= 413 status))
        (is (equal -32600 (jget (jget (parse-json text) "error") "code"))))
      (is (= 422 (post-octets port "/api/registry_describe" (structured-body "" 4990)
                              :headers headers))
          "a body at the limit is parsed, and its unknown member refused"))))

(test a-request-record-keeps-only-declared-input-and-little-of-it
  (with-test-server (port)
    (let ((headers '(("X-Tun-Actor" . "employee:anna"))))
      (post-octets port "/api/file_notes_create"
                   (sb-ext:string-to-octets
                    (to-json-string (jobj "title" (make-string (* 512 1024) :initial-element #\t)
                                          "ukjent" "x" "annet" (jarr (list 1 2 3))))
                    :external-format :utf-8)
                   :headers headers)
      (let* ((record (find "file_notes_create" (finished-requests) :key #'request-tool
                                                                  :test #'equal))
             (input (request-input-json record)))
        (is (equal '("title") (jkeys input)) "no key the operation does not declare")
        (is (< (length (to-json-string input)) (* 65 1024)) "and no more than the cap")
        (is (search "utelatt" (jget input "title")) "what is past it is marked")
        (is (< (length (request-error-message record)) 5000) "nor a long message")))))

;;; Structure-heavy bodies, at the value limit, in the default heap.

(defun structured-files-arguments (record-id)
  "The members of an attachments_add body, as text: RECORD-ID, JSON text, and
two files of 5.85 MiB, about 15.6 MiB of base64 together."
  (let ((six (large-png (round (* 5.85 +mib+)))))
    (format nil "\"entity\": \"heap_note\", \"record_id\": ~a, \"files\": ~a"
            record-id (to-json-string (files-json "a.png" six "b.png" six)))))

(defun live-heap (port)
  (jget (parse-json (nth-value 1 (post-octets port "/api/heap_live_bytes" (bytes "{}")
                                              :headers '(("X-Tun-Actor" . "viewer:vera")))))
        "bytes"))

(defun structured-mcp-body (arguments-text)
  (sb-ext:string-to-octets
   (format nil "{\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"tools/call\", ~
                \"params\": {\"name\": \"attachments_add\", \"arguments\": {~a}}}"
           arguments-text)
   :external-format :utf-8))

(defun json-object-octets (members-text)
  (sb-ext:string-to-octets (format nil "{~a}" members-text) :external-format :utf-8))

(test structure-heavy-bodies-at-the-limit-fit-the-default-heap
  ;; Each body holds two files of 5.85 MiB.  The padded ones also give the
  ;; declared record_id as an array of 4 970 empty objects, at the value
  ;; limit: refused for it, 422, but only after both files are decoded and
  ;; walked, as every input is decoded before an answer.
  (multiple-value-bind (results alive)
      (with-default-heap-server (port)
        (let* ((headers '(("X-Tun-Actor" . "employee:anna")))
               (note (heap-note port headers))
               (plain (structured-files-arguments (to-json-string note)))
               (padded (structured-files-arguments (empty-objects 4970)))
               (api-plain (json-object-octets plain))
               (api-padded (json-object-octets padded))
               (mcp-plain (structured-mcp-body plain))
               (mcp-padded (structured-mcp-body padded)))
          (is (< (* 15 +mib+) (length api-padded) (* 16 +mib+)))
          (flet ((call (body path)
                   (multiple-value-bind (status text) (post-octets port path body :headers headers)
                     (if (string= path "/mcp")
                         (list status (jget (jget (parse-json text) "result") "isError"))
                         status))))
            (let* ((add "/api/attachments_add")
                   (at-once (mapcar #'sb-thread:join-thread
                                    (loop for (body path) in (list (list api-plain add)
                                                                   (list api-padded add)
                                                                   (list mcp-plain "/mcp")
                                                                   (list mcp-padded "/mcp"))
                                          collect (let ((body body) (path path))
                                                    (sb-thread:make-thread
                                                     (lambda () (call body path)))))))
                   (before (progn (dotimes (i 5) (call api-padded "/api/attachments_add"))
                                  (live-heap port)))
                   (in-turn (loop repeat 15 collect (call api-padded "/api/attachments_add")))
                   (after (live-heap port)))
              (list at-once in-turn before after)))))
    (destructuring-bind (&optional at-once in-turn before after) results
      (is (equal '(200 422 (200 nil) (200 t)) at-once)
          "four at once: stored, refused, stored over MCP, refused over MCP: ~s" at-once)
      (is (every (lambda (status) (eql 422 status)) in-turn) "twenty in turn, each refused: ~s"
          in-turn)
      (is (and before after (< (- after before) (* 64 +mib+)))
          "the live heap stays flat: ~a → ~a" before after))
    (is-true alive "the server is still up")))

(test a-burst-of-small-structure-heavy-bodies-fits-the-default-heap
  (multiple-value-bind (statuses alive)
      (with-default-heap-server (port)
        (let* ((headers '(("X-Tun-Actor" . "viewer:vera")))
               (at-limit (structured-body "" 4990))
               (past-limit (structured-body "" (round (* 1.8 +mib+) 3)))
               (threads (loop for i below 48
                              collect (let ((body (if (evenp i) at-limit past-limit)))
                                        (sb-thread:make-thread
                                         (lambda ()
                                           (post-octets port "/api/registry_describe" body
                                                        :headers headers)))))))
          (is (< (length past-limit) (* 2 +mib+)))
          (mapcar #'sb-thread:join-thread threads)))
    ;; The bodies past the limit are over 256 KiB: four at a time have a place.
    (is (every (lambda (status) (member status '(413 422 503))) statuses)
        "each answered: refused for its unknown member, for too many values, or told to ~
         come back: ~s" statuses)
    (is (= 24 (count 422 statuses)) "every body at the limit is parsed")
    (is (<= 4 (count 413 statuses)) "and those past it with a place refused")
    (is-true alive "the server is still up")))

;;; ------------------------------------------------------------------
;;; Request records cost what their text does (core.md §7.5)

(test more-records-than-the-history-holds-fit-the-default-heap
  (multiple-value-bind (results alive)
      (with-default-heap-server (port)
        (let* ((viewer '(("X-Tun-Actor" . "viewer:vera")))
               (employee '(("X-Tun-Actor" . "employee:anna")))
               (heavy (sb-ext:string-to-octets (format nil "{\"id\": ~a}" (empty-objects 4990))
                                               :external-format :utf-8))
               (start (live-heap port))
               (refused (loop repeat 1100
                              count (eql 422 (post-octets port "/api/heap_notes_get" heavy
                                                          :headers viewer))))
               (after (live-heap port))
               (note (heap-note port employee))
               (uploads (json-object-octets (structured-files-arguments (to-json-string note))))
               (stored (mapcar #'sb-thread:join-thread
                               (loop repeat 4
                                     collect (sb-thread:make-thread
                                              (lambda ()
                                                (post-octets port "/api/attachments_add" uploads
                                                             :headers employee)))))))
          (list refused start after stored)))
    (destructuring-bind (&optional refused start after stored) results
      (is (eql 1100 refused) "each refused for its id: ~s" refused)
      (is (and start after (< (- after start) (* 96 +mib+)))
          "a thousand records later the live heap is about as it was: ~a → ~a" start after)
      (is (equal '(200 200 200 200) stored) "and four large uploads still succeed: ~s" stored))
    (is-true alive "the server is still up")))

;;; ------------------------------------------------------------------
;;; Plain forms are read within bounds (core.md §7.5)

(defun many-pairs (octets)
  "A urlencoded body of about OCTETS: a=b& over and over."
  (sb-ext:string-to-octets (with-output-to-string (out)
                             (loop repeat (floor octets 4) do (write-string "a=b&" out)))
                           :external-format :latin-1))

(test a-form-of-too-many-fields-is-refused-before-it-is-read-as-pairs
  ;; From a signed-in person: anonymous bodies over 256 KiB are not read at all.
  (with-test-server (port)
    (multiple-value-bind (status text)
        (post-octets port "/login" (many-pairs (* 2 +mib+))
                     :content-type "application/x-www-form-urlencoded"
                     :headers '(("X-Tun-Actor" . "viewer:vera")))
      (is (= 413 status))
      (is (search "Skjemaet har for mange felt (høyst 1 000)." text)))
    (multiple-value-bind (status text)
        (post-octets port "/login" (sb-ext:string-to-octets
                                    (format nil "a=~a"
                                            (make-string (1+ +mib+) :initial-element #\b))
                                    :external-format :latin-1)
                     :content-type "application/x-www-form-urlencoded"
                     :headers '(("X-Tun-Actor" . "viewer:vera")))
      (is (= 413 status))
      (is (search "Et felt i skjemaet er for langt." text))))
  (multiple-value-bind (statuses alive)
      (with-default-heap-server (port)
        (let* ((body (many-pairs (* 2 +mib+)))
               (start (live-heap port))
               (statuses (mapcar #'sb-thread:join-thread
                                 (loop repeat 24
                                       collect (sb-thread:make-thread
                                                (lambda ()
                                                  (post-octets
                                                   port "/login" body
                                                   :content-type
                                                   "application/x-www-form-urlencoded"
                                                   :headers '(("X-Tun-Actor"
                                                               . "viewer:vera"))))))))
               (after (live-heap port)))
          (is (< (- after start) (* 32 +mib+)) "the live heap is as it was: ~a → ~a" start after)
          statuses))
    ;; Each body is over 256 KiB: four at a time have a place.
    (is (every (lambda (status) (member status '(413 503))) statuses)
        "each post refused, or told to come back: ~s" statuses)
    (is (<= 4 (count 413 statuses)) "and those with a place read and refused")
    (is-true alive "the server is still up")))

(test a-form-within-the-bounds-is-read
  (with-files-page ()
    (with-test-server (port)
      (post-octets port "/filprove"
                   (sb-ext:string-to-octets
                    (format nil "title=Gr%C3%B8nn+sak&~{f~d=x~^&~}"
                            (loop for i below 998 collect i))
                    :external-format :latin-1)
                   :content-type "application/x-www-form-urlencoded"
                   :headers '(("X-Tun-Actor" . "employee:anna")))
      (is (equal "Grønn sak" (jget *page-seen* "title")) "decoded as UTF-8, + as a space")
      (is (equal "x" (jget *page-seen* "f997"))))))

;;; ------------------------------------------------------------------
;;; Smaller fixes

(test a-chunked-body-is-refused-and-its-connection-ended
  (with-test-server (port)
    (is (one-answer-then-end-p port (list "POST /mcp HTTP/1.1" "Host: x"
                                          "Transfer-Encoding: chunked")))))

(test an-unknown-key-is-repeated-only-in-part
  (with-test-server (port)
    (multiple-value-bind (status text)
        (post-octets port "/api/file_notes_create"
                     (sb-ext:string-to-octets
                      (to-json-string (jobj "title" "Kort"
                                            (make-string (* 700 1024) :initial-element #\k) "x"))
                      :external-format :utf-8)
                     :headers '(("X-Tun-Actor" . "employee:anna")))
      (is (= 422 status))
      (is (< (length text) 4096) "the answer repeats 100 characters of the key: ~d"
          (length text)))))

(test an-employees-mcp-body-that-is-not-one-object-is-refused
  (with-test-server (port)
    (let ((headers '(("X-Tun-Actor" . "employee:anna")))
          (wrapped (to-json-string
                    (to-json-string (jobj "jsonrpc" "2.0" "id" 1 "method" "tools/call"
                                          "params" (jobj "name" "file_notes_create"
                                                         "arguments" (jobj "title" "Smuglet")))))))
      (dolist (body (list "[{\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"ping\"}]"
                          "null" "1" "true" "[]" "\"x\"" wrapped))
        (multiple-value-bind (status text)
            (post-octets port "/mcp" (sb-ext:string-to-octets body :external-format :utf-8)
                         :headers headers)
          (is (= 200 status) "~a: ~a" body status)
          (is (equal -32600 (jget (jget (parse-json text) "error") "code"))
              "~a is not one JSON-RPC object: ~a" body text)))
      (with-application (*app*)
        (with-actor ((system-actor "test"))
          (is (null (with-transaction (:read)
                      (select 'file-note :where '(:= "title" "Smuglet"))))
              "the request in a string was not run"))))))
