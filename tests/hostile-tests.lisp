;;;; tests/hostile-tests.lisp -- hostile callers (core.md §7.5): what each
;;;; kind of request costs at its worst, measured in the default heap; the
;;;; server with every limit reached at once, by callers who are anonymous,
;;;; viewers and employees; and request records, which keep what a caller
;;;; sent only clipped.  The memory budget in core.md §7.5 names these tests.

(in-package #:tun.tests)

(def-suite hostile :in core)
(in-suite hostile)

;;; ------------------------------------------------------------------
;;; The budget's lines (core.md §7.5): what one request may allocate, all
;;; of it, while it is answered alone.  What is live at once is less.

(defparameter +small-request-cost+ (* 8 +mib+)
  "The most one request with a body of at most 256 KiB may allocate.")

(defparameter +large-request-costs+
  `((:json ,(* 16 +mib+))               ; a 2 MiB JSON body, 8 times
    (:form ,(* 12 +mib+))               ; a 2 MiB urlencoded body, 6 times
    (:files-json ,(* 72 +mib+))         ; a 16 MiB body with files, 4.5 times
    (:multipart ,(* 169 +mib+)))        ; a 26 MiB multipart post, 6.5 times
  "The most one request with a body over 256 KiB, holding a large place, may
allocate, by the kind of body.")

(defparameter +peak-heap+ (* 1604 +mib+)
  "The most heap, garbage included, the server may use with every limit
reached at once: the budget's total.")

(defparameter +viewer+ '(("X-Tun-Actor" . "viewer:vera")))
(defparameter +employee+ '(("X-Tun-Actor" . "employee:anna")))

(defun heap-number (port tool)
  "What TOOL, one of the heap server's operations, answers in bytes."
  (jget (parse-json (nth-value 1 (post-octets port (format nil "/api/~a" tool) (bytes "{}")
                                              :headers +viewer+)))
        "bytes"))

(defun request-cost (port function)
  "The octets the server allocates while answering the request FUNCTION
makes, less what asking it costs; and FUNCTION's value."
  (let* ((a (heap-number port "heap_consed"))
         (b (heap-number port "heap_consed"))
         (c (heap-number port "heap_consed"))
         (result (funcall function))
         (d (heap-number port "heap_consed")))
    (values (- d c (- b a)) result)))

;;; Hostile bodies, each at its bound

(defun ascii-text (length) (make-string length :initial-element #\a))

(defun astral-text (length)
  "LENGTH characters outside the Basic Multilingual Plane: four octets each in UTF-8."
  (make-string length :initial-element (code-char #x1F600)))

(defun json-body (object) (sb-ext:string-to-octets (to-json-string object) :external-format :utf-8))

(defun percent-encoded (text)
  "TEXT's UTF-8 octets, each but a letter or a digit as %XX."
  (with-output-to-string (out)
    (loop for octet across (sb-ext:string-to-octets text :external-format :utf-8)
          do (if (or (<= 48 octet 57) (<= 65 octet 90) (<= 97 octet 122))
                 (write-char (code-char octet) out)
                 (format out "%~2,'0X" octet)))))

(defun form-body (&rest names-and-values)
  "A urlencoded body of NAMES-AND-VALUES."
  (sb-ext:string-to-octets
   (format nil "~{~a=~a~^&~}" (mapcar #'percent-encoded names-and-values))
   :external-format :latin-1))

(defun object-array-text (count)
  "JSON text: an array of COUNT empty objects, each a hash table when parsed."
  (with-output-to-string (out)
    (write-char #\[ out)
    (dotimes (i count) (when (plusp i) (write-char #\, out)) (write-string "{}" out))
    (write-char #\] out)))

(defun values-and-strings-body (strings)
  "A JSON object: an id of 4 990 empty objects, at the value bound, and a
member for each of STRINGS."
  (sb-ext:string-to-octets
   (format nil "{\"id\": ~a~{, \"s~d\": ~s~}}" (object-array-text 4990)
           (loop for string in strings for i from 0 append (list i string)))
   :external-format :utf-8))

(defun mcp-body (tool arguments-text)
  (sb-ext:string-to-octets
   (format nil "{\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"tools/call\", ~
                \"params\": {\"name\": ~s, \"arguments\": ~a}}"
           tool arguments-text)
   :external-format :utf-8))

(defparameter +small-body+ (- (* 256 1024) 400)
  "About the most octets a body has and not take a large place.")

(defun small-requests (port)
  "The requests with a body up to 256 KiB at their costliest, of each path
and caller, as (NAME STATUSES FUNCTION): FUNCTION makes the request and
values its status, one of STATUSES."
  (let* ((ascii (ascii-text +small-body+))
         (astral (astral-text (floor +small-body+ 4)))
         (heavy (values-and-strings-body (list (ascii-text (- +small-body+ 12000)))))
         ;; Numbers of 19 significant digits at the edge of a double's range.
         (numbers (numbers-body "1.234567890123456789e-307" 9900))
         (api-ascii (json-body (jobj "id" ascii)))
         (api-astral (json-body (jobj "id" astral)))
         (mcp-heavy (mcp-body "heap_notes_get"
                              (sb-ext:octets-to-string heavy :external-format :utf-8)))
         (mcp-ascii (mcp-body "heap_notes_get" (to-json-string (jobj "id" ascii))))
         (form-ascii (form-body "a" ascii))
         (form-astral (form-body "a" (astral-text (floor +small-body+ 12))))
         (fault (json-body (jobj "text" ascii)))
         (public-fault (form-body "text" ascii))
         (multipart (list (list "note" "hpn_finnesikke")
                          (list "filer" "a.png" (large-png (- +small-body+ 1000))))))
    (flet ((api (body headers) (post-octets port "/api/heap_notes_get" body :headers headers))
           (form (path body) (post-octets port path body
                                          :content-type "application/x-www-form-urlencoded")))
      (list (list "/api, viewer, one long string" '(422) (lambda () (api api-ascii +viewer+)))
            (list "/api, viewer, astral text" '(422) (lambda () (api api-astral +viewer+)))
            (list "/api, viewer, values at the bound" '(422) (lambda () (api heavy +viewer+)))
            (list "/api, viewer, numbers at their costliest" '(422)
                  (lambda () (api numbers +viewer+)))
            (list "/api, anonymous" '(401) (lambda () (api api-ascii nil)))
            (list "/mcp, viewer, values at the bound" '(200)
                  (lambda () (post-octets port "/mcp" mcp-heavy :headers +viewer+)))
            (list "/mcp, anonymous" '(200) (lambda () (post-octets port "/mcp" mcp-ascii)))
            (list "form, anonymous" '(404) (lambda () (form "/login" form-ascii)))
            (list "form, anonymous, astral escapes" '(404) (lambda () (form "/login" form-astral)))
            (list "fault, viewer" '(500)
                  (lambda () (post-octets port "/api/heap_fault" fault :headers +viewer+)))
            (list "public page fault, anonymous" '(500)
                  (lambda () (form "/feilside" public-fault)))
            (list "multipart, employee" '(422) (lambda () (post-form port "/heap" multipart)))))))

(defun large-requests (port)
  "The requests with a body over 256 KiB at their costliest, of each kind of
body, as (KIND NAME STATUSES FUNCTION)."
  (let* ((mib (- +mib+ 10000))
         (json (values-and-strings-body (list (ascii-text mib) (ascii-text mib))))
         (mcp-json (mcp-body "heap_notes_get"
                             (sb-ext:octets-to-string json :external-format :utf-8)))
         (form (form-body "a" (ascii-text mib) "b" (ascii-text mib)))
         ;; As many as the value bound lets in, each of 64 characters.
         (numbers (numbers-body
                   "0.0000000000000000000000000000000000000000001234567890123456789" 9990))
         (files (json-body (jobj "entity" "heap_note" "record_id" "hpn_finnesikke"
                                 "files" (files-json "a.png" (large-png (* 10 +mib+)))
                                 "x" (ascii-text mib) "y" (ascii-text (round mib 1.2)))))
         (multipart (list (list "note" "hpn_finnesikke")
                          (list "t" (ascii-text mib)) (list "u" (ascii-text mib))
                          (list "filer" "a.png" (large-png (* 10 +mib+)))
                          (list "filer" "b.png" (large-png (* 10 +mib+)))
                          (list "filer" "c.png" (large-png (* 3 +mib+))))))
    (assert (< (length files) (* 16 +mib+)))
    (list (list :json "/api, viewer, numbers of 64 characters" '(422)
                (lambda () (post-octets port "/api/heap_notes_get" numbers :headers +viewer+)))
          (list :json "/api, viewer" '(422)
                (lambda () (post-octets port "/api/heap_notes_get" json :headers +viewer+)))
          (list :json "/mcp, viewer" '(200)
                (lambda () (post-octets port "/mcp" mcp-json :headers +viewer+)))
          (list :json "/mcp, anonymous, refused unread" '(413)
                (lambda () (post-octets port "/mcp" mcp-json)))
          (list :form "form, anonymous, refused unread" '(413)
                (lambda () (post-octets port "/login" form
                                        :content-type "application/x-www-form-urlencoded")))
          (list :form "form, viewer" '(404)
                (lambda () (post-octets port "/login" form :headers +viewer+
                                        :content-type "application/x-www-form-urlencoded")))
          (list :files-json "/api, employee, a file and long text" '(404 422)
                (lambda () (post-octets port "/api/attachments_add" files :headers +employee+)))
          (list :multipart "multipart, employee, files and long text" '(422)
                (lambda () (post-form port "/heap" multipart))))))

(test each-kind-of-request-costs-at-most-its-line-of-the-budget
  (multiple-value-bind (costs alive)
      (with-default-heap-server (port)
        (flet ((worst (function)
                 ;; The first answer of a kind also compiles and fills caches.
                 (funcall function)
                 (let ((costs (loop repeat 2 collect (multiple-value-list
                                                      (request-cost port function)))))
                   (list (reduce #'max costs :key #'first) (mapcar #'second costs)))))
          (append (loop for (name statuses function) in (small-requests port)
                        collect (list* name statuses +small-request-cost+ (worst function)))
                  (loop for (kind name statuses function) in (large-requests port)
                        collect (list* name statuses (second (assoc kind +large-request-costs+))
                                       (worst function))))))
    (loop for (name statuses most cost answers) in costs
          do (is (<= cost most) "~a: ~,1f MiB, at most ~,1f MiB" name (/ cost +mib+) (/ most +mib+))
             (is (subsetp answers statuses) "~a: answered ~s" name answers))
    (is-true alive "the server is still up")))

(defun request-thread (name statuses function &optional from)
  "A thread that makes FUNCTION's request, from the address FROM when it is
given; joined, it gives (NAME STATUSES STATUS), STATUS :RESET when the
connection ended before an answer came."
  (sb-thread:make-thread
   (lambda ()
     (let ((*request-from* from))
       (list name statuses (handler-case (funcall function)
                             (error () :reset)))))))

(defun loopback-address (i count)
  "The Ith of COUNT loopback addresses from 127.0.0.2: callers that many
addresses apart, each under its own bound of connections (core.md 7.5)."
  (format nil "127.0.0.~d" (+ 2 (mod i count))))

(test hostile-callers-at-every-limit-at-once-keep-the-server-up
  (multiple-value-bind (results alive)
      (with-default-heap-server (port)
        (let* ((small (small-requests port))
               (large (large-requests port))
               (start (live-heap port)))
          (heap-number port "heap_peak")
          (let ((answers
                  ;; Each round sixty with a small body and eight with a
                  ;; large one at once: past the 64 answered at once and the
                  ;; four large places.  They come from eight addresses, so
                  ;; that those limits are reached and not one address's.
                  (loop repeat 3
                        append (mapcar #'sb-thread:join-thread
                                       (append
                                        (loop for i below 60
                                              collect (apply #'request-thread
                                                             (append
                                                              (nth (mod i (length small)) small)
                                                              (list (loopback-address i 8)))))
                                        (loop for i below 8
                                              collect (apply #'request-thread
                                                             (append
                                                              (rest (nth (mod i (length large))
                                                                         large))
                                                              (list (loopback-address i 8))))))))))
            (list answers (heap-number port "heap_peak") start (live-heap port)))))
    (destructuring-bind (&optional answers peak start after) results
      (is (and start (< start (* 128 +mib+))) "the image at rest holds at most 128 MiB: ~a" start)
      (is (= 204 (length answers)) "every request made")
      (loop for (name statuses status) in answers
            unless (member status (list* 503 :reset statuses))
              do (is (member status (list* 503 :reset statuses)) "~a: answered ~a" name status))
      (let ((in-full (count-if (lambda (answer) (member (third answer) (second answer))) answers)))
        (is (< 102 in-full) "most of them answered in full: ~d of 204" in-full))
      (is (and peak (< peak +peak-heap+)) "the heap at its highest: ~,1f MiB of at most ~,1f MiB"
          (and peak (/ peak +mib+)) (/ +peak-heap+ +mib+))
      (is (and start after (< (- after start) (* 64 +mib+)))
          "and once they are answered the live heap is as it was: ~a → ~a" start after))
    (is-true alive "the server is still up")))

;;; ------------------------------------------------------------------
;;; Request records keep a caller's text clipped (core.md §7.5, §8.1)

(test a-record-cannot-hold-uncapped-text
  (let ((record (tun.core::make-request-record :id "req_x")))
    (setf (request-tool record) (ascii-text 100000)
          (request-error-message record) (astral-text 50000))
    (is (<= (length (tun.core::request-%tool record)) 256) "the tool clipped to 256 octets")
    (is (string= "…" (subseq (request-tool record) (1- (length (request-tool record)))))
        "and marked")
    (is (<= (length (tun.core::request-%error-message record)) 4096)
        "astral text counted in octets")
    (is (every (lambda (char) (member char (list (code-char #x1F600) #\…)))
               (request-error-message record))
        "cut at a character: the octets are valid UTF-8")
    ;; The record's slot refuses octets past its bound, and a string: only
    ;; recorded text goes in.
    (signals type-error (setf (tun.core::request-%tool record)
                              (make-array 1000 :element-type '(unsigned-byte 8))))
    (signals type-error (setf (tun.core::request-%tool record) (ascii-text 10)))
    (is (<= (+ (* 5 tun.core::+most-recorded-short+) tun.core::+most-recorded-message+
               tun.core::+most-recorded-backtrace+ tun.core::+most-recorded-input+)
            tun.core::+most-record-octets+)
        "its fields' bounds together are the record's"))
  (let* ((op (find-operation-by-tool "file_notes_create"))
         (octets (recorded-input (make-input (jobj "title" (astral-text 100000))) op))
         (input (parse-json octets)))
    (is (<= (length octets) tun.core::+most-recorded-input+) "input in octets: ~d" (length octets))
    (is (search "utelatt" (jget input "title")) "the value past it left out")))

(defun hostile-record-requests (port)
  "Requests whose every field a record keeps is hostile, ASCII and astral:
the tool or path, the method, the actor, the input and the error message."
  (let* ((ascii (ascii-text 200000))
         (astral (astral-text 50000)))
    (flet ((mcp (body &optional (headers +viewer+)) (post-octets port "/mcp" body :headers headers))
           (api (tool body headers)
             (post-octets port (format nil "/api/~a" tool) (json-body body) :headers headers))
           (form (path body)
             (post-octets port path body :content-type "application/x-www-form-urlencoded")))
      (list (lambda () (api (ascii-text 30000) (jobj) +viewer+))
            ;; Over a socket of its own: Drakma would encode the path again.
            (lambda () (raw-request port (list (format nil "POST /api/~a HTTP/1.1"
                                                       (percent-encoded (astral-text 2400)))
                                               "Host: x" "X-Tun-Actor: viewer:vera"
                                               "Content-Length: 2")
                                    :body (bytes "{}")))
            (lambda () (mcp (json-body (jobj "jsonrpc" "2.0" "id" 1 "method" ascii))))
            (lambda () (mcp (json-body (jobj "jsonrpc" "2.0" "id" 1 "method" "tools/call"
                                             "params" (jobj "name" astral "arguments" (jobj))))))
            (lambda () (mcp (json-body (jobj "jsonrpc" "2.0" "id" 1 "method" "tools/call"
                                             "params" (jobj "name" "heap_notes_create"
                                                            "arguments" (jobj "title" ascii))))
                            +employee+))
            (lambda () (api "heap_notes_create" (jobj "title" astral) +employee+))
            (lambda () (api "heap_fault" (jobj "text" ascii) +viewer+))
            (lambda () (api "heap_fault" (jobj "text" astral) +viewer+))
            (lambda () (form (format nil "/~a" (ascii-text 30000)) (form-body "a" ascii)))
            (lambda () (form "/feilside" (form-body "text" astral)))
            (lambda () (api "heap_notes_get" (jobj "id" ascii)
                            `(("X-Tun-Actor" . ,(format nil "viewer:~a" (ascii-text 20000))))))))))

(defun records-at-the-cap (port)
  "Requests whose records keep as much as a record may: input that just
fits, ASCII and astral, and a long error message."
  (let ((ascii (json-body (jobj "text" (ascii-text (* 47 1024)))))
        (astral (json-body (jobj "text" (astral-text (* 11 1024))))))
    (list (lambda () (post-octets port "/api/heap_fault" ascii :headers +viewer+))
          (lambda () (post-octets port "/api/heap_fault" astral :headers +viewer+)))))

(test hostile-text-in-every-record-field-is-kept-clipped
  ;; A thousand records at the cap, then a hundred with hostile text in
  ;; every field: the history holds as much as it ever may.
  (multiple-value-bind (results alive)
      (with-default-heap-server (port)
        (let* ((full (records-at-the-cap port))
               (hostile (hostile-record-requests port))
               (start (live-heap port))
               (statuses (loop for i below 1100
                               collect (if (< i 1000)
                                           (funcall (nth (mod i 2) full))
                                           (funcall (nth (mod i (length hostile)) hostile)))))
               (after (live-heap port))
               (records (parse-json (nth-value 1 (post-octets port "/api/heap_records" (bytes "{}")
                                                              :headers +viewer+))))
               (echo (nth-value 1 (post-octets port "/mcp"
                                               (json-body (jobj "jsonrpc" "2.0" "id" 1
                                                                "method" (ascii-text 100000)))
                                               :headers +viewer+))))
          (list statuses start after records echo)))
    (destructuring-bind (&optional statuses start after records echo) results
      (is (= 1100 (length statuses)) "every request answered")
      (is (notany (lambda (status) (member status '(nil 503))) statuses) "each in full")
      (is (= 1000 (jget records "count")) "the history holds its thousand")
      (is (<= (* 48 1024) (jget records "most_octets") (* 64 1024))
          "a record keeps up to 64 KiB of text, and no more: ~d" (jget records "most_octets"))
      (is (and start after (< (- after start) (* 96 +mib+)))
          "the live heap grows by what the records keep: ~a → ~a" start after)
      (is (< (length (jget (jget (parse-json echo) "error") "message")) 200)
          "an unknown method's name is cut in its error"))
    (is-true alive "the server is still up")))

(test a-thousand-connections-in-their-headers-fit-the-budget
  ;; Each sends a request line and headers just under the 32 KiB budget and
  ;; never ends them, fifty from each of twenty addresses: past what one
  ;; address may hold (core.md 7.5).
  (multiple-value-bind (results alive)
      (with-default-heap-server (port)
        (let* ((head (sb-ext:string-to-octets
                      (apply #'crlf (list* "POST /api/heap_notes_get HTTP/1.1" "Host: x"
                                           (loop for i below 45
                                                 collect (format nil "X-Fyll-~d: ~a" i
                                                                 (ascii-text 700)))))
                      :external-format :latin-1))
               (start (live-heap port))
               (sockets '()))
          (unwind-protect
               (progn
                 (dotimes (i 1000)
                   (let ((socket (connect-from (loopback-address i 20) port)))
                     (push socket sockets)
                     (write-sequence head socket)
                     (finish-output socket)))
                 (sleep 2)
                 (list (length head) start (live-heap port)))
            (close-all sockets))))
    (destructuring-bind (&optional length start during) results
      (is (and length (< (* 31 1024) length (* 32 1024))) "each just under the budget")
      (is (and start during (< (- during start) (* 192 +mib+)))
          "a thousand of them hold at most 192 MiB: ~a → ~a" start during))
    (is-true alive "the server is still up")))

;;; ------------------------------------------------------------------
;;; A body's length and how it arrives

(test a-content-length-that-is-not-plain-digits-is-refused
  (with-test-server (port)
    (dolist (lengths '(("12" "12") ("12" "13") ("+12") ("1e3") ("0x10")))
      (let ((head (append (list "POST /api/registry_describe HTTP/1.1" "Host: x"
                                "X-Tun-Actor: viewer:vera")
                          (mapcar (lambda (length) (format nil "Content-Length: ~a" length))
                                  lengths))))
        (is (refused-unread-p port head 400) "400 for Content-Length ~{~a~^, ~}" lengths)))))

(test a-large-body-that-stops-coming-is-answered-408
  (let ((hunchentoot:*default-connection-timeout* 1))
    (with-test-server (port)
      (let* ((socket (usocket:socket-connect "127.0.0.1" port :element-type '(unsigned-byte 8)))
             (stream (usocket:socket-stream socket))
             (start (get-internal-real-time)))
        (unwind-protect
             (progn
               (write-sequence (sb-ext:string-to-octets
                                (crlf "POST /api/registry_describe HTTP/1.1" "Host: x"
                                      "X-Tun-Actor: viewer:vera"
                                      (format nil "Content-Length: ~d" (* 300 1024)) "")
                                :external-format :latin-1)
                               stream)
               (write-sequence (make-array 1000 :element-type '(unsigned-byte 8)
                                                :initial-element 32)
                               stream)
               (finish-output stream)
               (let ((text (with-output-to-string (out)
                             (handler-case
                                 (sb-sys:with-deadline (:seconds 5)
                                   (loop for byte = (read-byte stream nil nil)
                                         while byte do (write-char (code-char byte) out)))
                               (sb-sys:deadline-timeout () (write-string "<open>" out))
                               (error () nil)))))
                 (is (search " 408" text) "answered 408: ~s" (subseq text 0 (min 40 (length text))))
                 (is (not (search "<open>" text)) "and the connection ended")
                 (is (< (- (get-internal-real-time) start) (* 5 internal-time-units-per-second)))))
          (usocket:socket-close socket))))))

;;; ------------------------------------------------------------------
;;; Numbers past a double's range (core.md §7.5)

(defparameter +numbers-refused+
  '(("1e9999999" :range) ("1e99999999" :range) ("-1E+10000" :range) ("1e401" :range)
    ("2.5e-399" :range) ("123456789e395" :range) ("1e309" :range) ("1.8e308" :range)
    ("1e-330" :range) ("1.5e-308" :range) ("2.2250738585072013e-308" :range)
    ("12345678901234567890" :digits) ("1.2345678901234567890123e248" :digits))
  "Numbers refused from a caller, and why: past a double's normal range, or
more than 19 significant digits.")

(defparameter +numbers-in-range+
  '("1.5e300" "1e-300" "1.7976931348623157e308" "2.2250738585072014e-308"
    "-2.2250738585072014e-308" "1.234567890123456789e-307"
    "0.000000000000000000000000000000000000000000000000000000000001"
    "1234567890123456789" "-0.0" "0e10")
  "Numbers at the edges that are still read.")

(defun refusal-message (why)
  (ecase why (:range +number-out-of-range+) (:digits +number-too-many-digits+)))

(defun numbers-body (number count)
  "A JSON object whose id is an array of COUNT times NUMBER."
  (sb-ext:string-to-octets
   (format nil "{\"id\": [~{~a~^,~}]}" (make-list count :initial-element number))
   :external-format :utf-8))

(defun timed (function)
  "Values how many seconds FUNCTION took and its values as a list."
  (let* ((start (get-internal-real-time))
         (values (multiple-value-list (funcall function))))
    (values (/ (- (get-internal-real-time) start) internal-time-units-per-second) values)))

(test a-number-past-a-doubles-range-is-refused-at-once
  (loop for (number why) in +numbers-refused+
        do (multiple-value-bind (seconds result)
               (timed (lambda ()
                        (handler-case (parse-request-json (format nil "{\"x\": ~a}" number))
                          (json-number-out-of-range (refusal) (json-number-message refusal)))))
             (is (equal (list (refusal-message why)) result) "~a refused: ~s" number result)
             (is (< seconds 0.1) "~a refused in ~,3f s" number seconds)))
  (dolist (number +numbers-in-range+)
    (is (realp (jget (parse-request-json (format nil "{\"x\": ~a}" number)) "x"))
        "~a read" number))
  (is (equal '(t nil) (coerce (parse-request-json "[true, false]") 'list))
      "the e of true and false is no exponent")
  (with-test-server (port)
    (post-octets port "/api/registry_describe" (bytes "{}") :headers +viewer+)
    (loop for (number why) in +numbers-refused+
          for message = (refusal-message why)
          do (multiple-value-bind (seconds result)
                 (timed (lambda ()
                          (post-octets port "/api/registry_describe"
                                       (bytes (format nil "{\"x\": ~a}" number))
                                       :headers +viewer+)))
               (destructuring-bind (status text &rest rest) result
                 (declare (ignore rest))
                 (is (= 400 status) "/api: 400 for ~a" number)
                 (is (search "invalid_json" text))
                 (is (search message text) "/api: ~a told why: ~a" number text)
                 (is (< seconds 0.1) "/api: ~a answered in ~,3f s" number seconds)))
             (multiple-value-bind (seconds result)
                 (timed (lambda ()
                          (post-octets port "/mcp"
                                       (mcp-body "registry_describe"
                                                 (format nil "{\"x\": ~a}" number))
                                       :headers +viewer+)))
               (let ((error (jget (parse-json (second result)) "error")))
                 (is (eql -32700 (jget error "code")) "/mcp: -32700 for ~a" number)
                 (is (equal message (jget error "message")))
                 (is (< seconds 0.1) "/mcp: ~a answered in ~,3f s" number seconds))))))

(test json-tun-wrote-reads-back-whatever-numbers-it-holds
  ;; The bounds on a caller's numbers never apply to JSON Tun wrote: a
  ;; field, a receipt, an answer from another system.
  (let ((values (list most-positive-double-float least-positive-normalized-double-float
                      least-positive-double-float 2.5d-308 -1.5d300 0.1d0 (expt 10 19)
                      12345678901234567890 (- (expt 2 200)) (expt 10 300))))
    (dolist (value values)
      (is (= value (aref (parse-json (to-json-string (jarr (list value)))) 0))
          "~s reads back" value))
    (is (equalp (coerce values 'vector)
                (tun.core::db->type (make-instance 'tun.core::json-type)
                                    (to-json-string (jarr values))))
        "a json field holding them reads back")
    (with-test-app ()
      (let ((widget (jget (call-ok "widgets_create" "employee:anna" "name" "Tall") "id"))
            (result (to-json-string (jobj "id" "wdg_annen" "tall" (jarr values)))))
        (with-application (*app*)
          (with-transaction (:write)
            (insert (make-instance 'tun.core::receipt
                                   :actor "employee:anna" :tool "widgets_create"
                                   :request-key "tall" :input-hash "h" :result result
                                   :created-at (now))))
          (with-transaction (:read)
            (is (equalp (coerce values 'vector)
                        (jget (tun.core::replay-receipt (find-operation-by-tool "widgets_create")
                                                        (parse-actor "employee:anna") "tall" "h")
                              "tall"))
                "a receipt holding them replays"))
          (with-transaction (:write)
            ;; Redacting receipts reads every one of them.
            (finishes (tun.core::redact-entity-receipts (fetch! 'widget widget)))))))))

(test a-json-port-checks-its-secret-before-it-parses
  (let ((parsed 0))
    (tun.http:register-json-endpoint "/proveport"
                                     (lambda (body secret)
                                       (declare (ignore body secret))
                                       (incf parsed)
                                       (values 200 (jobj "ok" t)))
                                     :authorize (lambda (secret) (equal secret "hemmelig")))
    (unwind-protect
         (with-test-server (port)
           (flet ((post (body secret)
                    (post-octets port "/proveport" (bytes body)
                                 :headers (and secret `(("X-Tun-Inbound-Secret" . ,secret))))))
             (is (= 403 (post "{\"x\": 1e99999999}" "feil")) "a wrong secret: 403, unparsed")
             (is (= 403 (post "{}" nil)) "no secret: 403")
             (is (= 0 parsed) "the handler never ran")
             (is (= 400 (post "{\"x\": 1e99999999}" "hemmelig"))
                 "the right one: the number refused")
             (is (= 200 (post "{\"x\": 1}" "hemmelig")))
             (is (= 1 parsed))
             (is (= 413 (post (format nil "{\"x\": ~a}" (object-array-text 6000)) "hemmelig"))
                 "more than 10 000 values: 413")))
      (remhash "/proveport" tun.http::*json-endpoints*))))

;;; ------------------------------------------------------------------
;;; Senders that trickle (core.md §7.5)

(defun trickle (port head &key (body-length 0) (every 0.3) (seconds 4))
  "Send HEAD's lines (and, with BODY-LENGTH, the header that declares a body
of that length and its end), then a byte EVERY seconds; values what came
back within SECONDS and whether the connection ended."
  (let* ((socket (usocket:socket-connect "127.0.0.1" port :element-type '(unsigned-byte 8)))
         (stream (usocket:socket-stream socket))
         (sender nil))
    (unwind-protect
         (progn
           (write-sequence (sb-ext:string-to-octets
                            (if (plusp body-length)
                                (apply #'crlf (append head (list (format nil "Content-Length: ~d"
                                                                         body-length)
                                                                 "")))
                                (apply #'crlf head))
                            :external-format :latin-1)
                           stream)
           (finish-output stream)
           (setf sender (sb-thread:make-thread
                         (lambda ()
                           (handler-case (loop repeat 100
                                               do (write-byte 120 stream)
                                                  (finish-output stream)
                                                  (sleep every))
                             (error () nil)))))
           (let* ((ended nil)
                  (text (with-output-to-string (out)
                          (handler-case
                              (sb-sys:with-deadline (:seconds seconds)
                                (loop for byte = (read-byte stream nil nil)
                                      while byte do (write-char (code-char byte) out)
                                      finally (setf ended t)))
                            (sb-sys:deadline-timeout () nil)
                            (error () (setf ended t))))))
             (values text ended)))
      (usocket:socket-close socket)
      (when sender (sb-thread:join-thread sender :default nil)))))

(test headers-that-trickle-are-answered-408
  (let ((limit tun.http:*header-seconds*))
    (setf tun.http:*header-seconds* 1)      ; global: the server's threads read it
    (unwind-protect
         (with-test-server (port)
           (multiple-value-bind (seconds result)
               (timed (lambda () (trickle port (list "POST /api/registry_describe HTTP/1.1"
                                                             "Host: x" "X-Fyll: "))))
             (destructuring-bind (text ended) result
               (is (search " 408" text) "answered 408: ~s" text)
               (is-true ended "and the connection ended")
               (is (< seconds 3) "within the deadline: ~,1f s" seconds)))
           (is (= 200 (fetch-file port "/health")) "the server answers others"))
      (setf tun.http:*header-seconds* limit))))

(test small-bodies-that-trickle-free-their-places-in-time
  ;; Two places in all; two senders trickle their small bodies; a call that
  ;; came meanwhile is answered once their time is up.
  (let ((limit tun.http:*small-body-seconds*))
    (setf tun.http:*small-body-seconds* 1)
    (unwind-protect
         (with-test-app (:identity :claimed)
           (let* ((port (free-port))
                  (acceptor (tun.http:start-server *app* :port port :max-inflight 2)))
             (unwind-protect
                  (let* ((head (list "POST /api/registry_describe HTTP/1.1" "Host: x"
                                     "X-Tun-Actor: viewer:vera"))
                         (senders (loop repeat 2
                                        collect (sb-thread:make-thread
                                                 (lambda ()
                                                   (multiple-value-list
                                                    (trickle port head :body-length 200)))))))
                    (sleep 0.3)
                    (let* ((start (get-internal-real-time))
                           (statuses (loop for status = (post-octets port "/api/registry_describe"
                                                                     (bytes "{}") :headers +viewer+)
                                           collect status
                                           until (or (eql status 200)
                                                     (> (- (get-internal-real-time) start)
                                                        (* 5 internal-time-units-per-second)))
                                           do (sleep 0.1)))
                           (answers (mapcar #'sb-thread:join-thread senders)))
                      (is (eql 503 (first statuses)) "while both trickle, the call is told to wait")
                      (is (eql 200 (car (last statuses))) "and is answered once a place frees: ~s"
                          statuses)
                      (is (< (- (get-internal-real-time) start)
                             (* 3 internal-time-units-per-second)))
                      (loop for (text ended) in answers
                            do (is (search " 408" text) "the trickling sender gets 408: ~s" text)
                               (is-true ended "and its connection ends"))))
               (tun.http:stop-server acceptor))))
      (setf tun.http:*small-body-seconds* limit))))

(test bodies-sent-where-nothing-reads-them-end-their-connection
  ;; /health and the redirect to HTTPS answer before any body is read; a
  ;; body declared there is dropped for at most two seconds, then the
  ;; connection ends, however slowly it trickles.
  (with-test-server (port :public-url "https://tun.example")
    (dolist (case (list (list (list "POST /health HTTP/1.1" "Host: x") " 200")
                        (list (list "GET /login HTTP/1.1" "Host: x" "X-Forwarded-Proto: http")
                              " 301")))
      (destructuring-bind (head status) case
        (multiple-value-bind (seconds result)
            (timed (lambda () (trickle port head :body-length 200)))
          (destructuring-bind (text ended) result
            (is (search status text) "~a: answered~a: ~s" (first head) status text)
            (is-true ended "~a: and the connection ended" (first head))
            (is (< seconds 3.5) "~a: within the time a body is dropped for: ~,1f s"
                (first head) seconds)))))))

(test the-inbox-checks-its-secret-before-it-parses
  (with-test-server (port)
    (call-ok "settings_set" "admin:a" "key" "innboks.hemmelighet" "value" "hemmelig")
    (let* ((endpoint (gethash "/inbound/mail" tun.http::*json-endpoints*))
           (handler (car endpoint))
           (called 0))
      (setf (car endpoint) (lambda (body secret) (incf called) (funcall handler body secret)))
      (unwind-protect
           (flet ((post (body secret)
                    (post-octets port "/inbound/mail" (bytes body)
                                 :headers `(("X-Tun-Inbound-Secret" . ,secret)))))
             (is (= 403 (post "{\"from_email\": 1e99999999}" "feil"))
                 "a wrong secret: 403, the body unparsed")
             (is (= 0 called) "the handler never ran")
             (is (= 400 (post "{\"from_email\": 1e99999999}" "hemmelig"))
                 "the right secret: the number refused")
             (is (= 0 called) "nor then"))
        (setf (car endpoint) handler)))))

(test a-long-number-in-a-generated-form-is-not-parsed
  (with-test-server (port)
    (let ((digits (make-string 500000 :initial-element #\7)))
      (dolist (case '(("viewer:vera" 403) ("employee:anna" 422)))
        (destructuring-bind (actor status) case
          (multiple-value-bind (seconds result)
              (timed (lambda ()
                       (web-request port "/orders" :method :post :jar (web-login port actor)
                                    :parameters `(("event_date" . "2026-06-20")
                                                  ("lines[0][product_id]" . "prd_x")
                                                  ("lines[0][quantity]" . ,digits)))))
            (is (= status (first result)) "~a: ~a" actor (first result))
            (when (= status 422)
              (is (search "for langt for et tall" (second result)) "~a: told why" actor))
            (is (< seconds 2) "~a: answered in ~,1f s" actor seconds)))))))

;;; ------------------------------------------------------------------
;;; Anonymous callers send at most 256 KiB (core.md §7.5)

(test an-anonymous-body-over-256-kib-is-refused-unread
  (with-test-server (port)
    (dolist (head (list (list "POST /login HTTP/1.1" "Host: x"
                              "Content-Type: application/x-www-form-urlencoded")
                        (list "POST /api/registry_describe HTTP/1.1" "Host: x")
                        (list "POST /mcp HTTP/1.1" "Host: x")
                        (list "POST /inbound/mail HTTP/1.1" "Host: x"
                              "X-Tun-Inbound-Secret: feil")))
      (is (refused-unread-p port (append head (list (format nil "Content-Length: ~d"
                                                            (* 300 1024))))
                            413)
          "~a: 413 before the body is read" (first head)))
    ;; Four anonymous senders trickling large forms take no place: a
    ;; signed-in person's upload over 256 KiB is still answered.
    (let* ((head (list "POST /login HTTP/1.1" "Host: x"
                       "Content-Type: application/x-www-form-urlencoded"))
           (tricklers (loop repeat 4
                            collect (sb-thread:make-thread
                                     (lambda () (trickle port head :body-length (* 300 1024))))))
           (png (padded-png (* 300 1024))))
      (sleep 0.3)
      (is (= 200 (post-octets port "/api/file_notes_create"
                              (json-body (jobj "title" "Stor" "screenshots"
                                               (files-json "a.png" png)))
                              :headers +employee+))
          "the upload has a place")
      (dolist (thread tricklers)
        (is (search " 413" (sb-thread:join-thread thread)) "each trickler refused at once")))))

;;; ------------------------------------------------------------------
;;; What one client address holds (core.md §7.5): connections counted by
;;; their peer, requests and waits through the trusted proxy by the client
;;; it names.  Loopback addresses stand for clients: a socket bound to
;;; 127.0.0.2 reaches the server on 127.0.0.1 from that address.

(defmacro with-address-server ((port acceptor &key trusted-proxy) &body body)
  "Run BODY with *APP* served on PORT by ACCEPTOR, with claimed identity and
TRUSTED-PROXY.  BODY closes the connections it holds, so the server stops
without waiting for them."
  `(with-test-app (:identity :claimed)
     (let* ((,port (free-port))
            (,acceptor (tun.http:start-server *app* :port ,port :trusted-proxy ,trusted-proxy)))
       (unwind-protect (progn ,@body)
         (tun.http:stop-server ,acceptor)))))

(defun send-text (stream text)
  (write-sequence (sb-ext:string-to-octets text :external-format :latin-1) stream)
  (finish-output stream))

(defun request-head (method path &rest headers)
  "A request line and HEADERS, ended, with Host and Connection: close."
  (apply #'crlf (format nil "~a ~a HTTP/1.1" method path) "Host: x" "Connection: close"
         (append headers (list ""))))

(defun answer-head (stream &optional (seconds 3))
  "The status line and headers STREAM is answered within SECONDS, as text,
or :TIMEOUT, or :RESET when the connection ended first."
  (let ((octets (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer t)))
    (handler-case
        (sb-sys:with-deadline (:seconds seconds)
          (loop for byte = (read-byte stream nil nil)
                while byte
                do (vector-push-extend byte octets)
                until (and (>= (length octets) 4)
                           (equalp (subseq octets (- (length octets) 4)) #(13 10 13 10))))
          (if (plusp (length octets))
              (sb-ext:octets-to-string octets :external-format :latin-1)
              :reset))
      (sb-sys:deadline-timeout () :timeout)
      (error () :reset))))

(defun head-status (head)
  "The status of an answer's HEAD, or HEAD itself when it is not text."
  (if (stringp head)
      (parse-integer head :start 9 :end 12 :junk-allowed t)
      head))

(defun status-from (address port head &optional (seconds 3))
  "Send HEAD, a request, from ADDRESS; the status it is answered."
  (let ((socket (connect-from address port)))
    (unwind-protect
         (progn (send-text socket head)
                (head-status (answer-head socket seconds)))
      (close socket))))

(defun health-from (address port &rest headers)
  "The status /health is answered from ADDRESS with HEADERS."
  (status-from address port (apply #'request-head "GET" "/health" headers)))

(defun holding-headers (address port)
  "A connection from ADDRESS whose request line has come and its headers
never end."
  (let ((socket (connect-from address port)))
    (send-text socket (crlf "GET /health HTTP/1.1" "Host: x"))
    socket))

(defun holding-body (address port &rest headers)
  "A connection from ADDRESS whose request's headers have come and its body
never ends."
  (let ((socket (connect-from address port)))
    (send-text socket (concatenate 'string
                                   (apply #'request-head "POST" "/mcp"
                                          "Content-Type: application/json"
                                          "Content-Length: 100" headers)
                                   "{"))
    socket))

(defun answered-p (stream)
  "True when something has come back on STREAM."
  (listen stream))

(defun eventually (function &optional (seconds 5))
  "True once FUNCTION is, within SECONDS."
  (loop with end = (+ (get-internal-real-time) (* seconds internal-time-units-per-second))
        thereis (funcall function)
        while (< (get-internal-real-time) end)
        do (sleep 0.02)))

(defun close-all (streams)
  (dolist (stream streams)
    ;; A connection the server ended already: closing it is all that is left.
    (ignore-errors (close stream))))

(defun holds (counts key number)
  "True once KEY holds NUMBER in COUNTS, within five seconds."
  (eventually (lambda () (= number (key-count counts key)))))

(test an-address-holds-at-most-64-connections-while-others-are-served
  (with-address-server (port acceptor)
    (let ((counts (tun.http::acceptor-connections acceptor))
          (held '()))
      (unwind-protect
           (progn
             (dotimes (i tun.http:*connections-per-address*)
               (push (holding-headers "127.0.0.2" port) held))
             (is-true (holds counts "127.0.0.2" 64) "64 held in their headers")
             (let* ((socket (connect-from "127.0.0.2" port))
                    (head (answer-head socket)))
               (close socket)
               (is (eql 503 (head-status head)) "the 65th is refused before it sends: ~s" head)
               (is (and (stringp head) (search "Retry-After: 1" head)))
               (is (and (stringp head) (search "Connection: close" head))))
             (dotimes (i 3)
               (is (eql 503 (health-from "127.0.0.2" port "X-Forwarded-For: 203.0.113.9"))
                   "a 65th that has sent its request, naming another address, reads the 503"))
             (is (eql 200 (health-from "127.0.0.3" port)) "another address is served")
             (close (pop held))
             (is-true (holds counts "127.0.0.2" 63))
             (is (eql 200 (health-from "127.0.0.2" port)) "and the first again once one ends"))
        (close-all held)))))

(test x-forwarded-for-is-read-from-the-trusted-proxy-only
  (with-address-server (port acceptor :trusted-proxy "127.0.0.1")
    (let ((held '()))
      (unwind-protect
           (progn
             (dotimes (i 17)
               (push (holding-body "127.0.0.2" port "X-Forwarded-For: 203.0.113.7") held))
             (is-true (holds (tun.http::acceptor-connections acceptor) "127.0.0.2" 17))
             (sleep 0.5)
             (is (notany #'answered-p held) "all 17 held, none refused")
             (is (= 0 (key-count (tun.http::acceptor-proxied-requests acceptor) "203.0.113.7"))
                 "counted as 127.0.0.2's connections, not as the client's requests"))
        (close-all held)))))

(test a-client-through-the-proxy-has-at-most-16-requests-in-progress
  (with-address-server (port acceptor :trusted-proxy "127.0.0.1")
    (let ((counts (tun.http::acceptor-proxied-requests acceptor))
          (held '())
          (idle '()))
      (unwind-protect
           (progn
             (dotimes (i tun.http:*requests-per-address*)
               (push (holding-body "127.0.0.1" port "X-Forwarded-For: 203.0.113.7") held))
             (is-true (holds counts "203.0.113.7" 16) "16 held while their bodies come")
             (let* ((socket (holding-body "127.0.0.1" port "X-Forwarded-For: 203.0.113.7"))
                    (head (answer-head socket)))
               (close socket)
               (is (eql 503 (head-status head)) "the 17th is refused at once: ~s" head)
               (is (and (stringp head) (search "Retry-After: 1" head))))
             (is (eql 200 (health-from "127.0.0.1" port "X-Forwarded-For: 203.0.113.8"))
                 "another client is served")
             (is (eql 200 (health-from "127.0.0.1" port
                                       "X-Forwarded-For: 203.0.113.7, 198.51.100.1"))
                 "the last entry is the client")
             (dotimes (i 70)
               (push (connect-from "127.0.0.1" port) idle))
             (send-text (first idle) (request-head "GET" "/health"))
             (is (eql 200 (head-status (answer-head (first idle))))
                 "the proxy's own connections are not counted")
             (close-all held)
             (setf held '())
             (is-true (holds counts "203.0.113.7" 0))
             (is (eql 200 (health-from "127.0.0.1" port "X-Forwarded-For: 203.0.113.7"))
                 "and the client is served again once its requests end"))
        (close-all held)
        (close-all idle)))))

(test a-request-through-the-proxy-naming-no-client-counts-as-the-proxys
  (with-address-server (port acceptor :trusted-proxy "127.0.0.1")
    (let ((counts (tun.http::acceptor-proxied-requests acceptor))
          (held '()))
      (unwind-protect
           (progn
             (dotimes (i 8)
               (push (holding-body "127.0.0.1" port) held)
               (push (holding-body "127.0.0.1" port "X-Forwarded-For: unknown") held))
             (is-true (holds counts "127.0.0.1" 16)
                      "without X-Forwarded-For, or with no address in it")
             (let ((socket (holding-body "127.0.0.1" port)))
               (is (eql 503 (head-status (answer-head socket))))
               (close socket))
             (is (eql 200 (health-from "127.0.0.1" port "X-Forwarded-For: 203.0.113.8"))))
        (close-all held)))))

(test the-address-a-client-counts-under
  (flet ((key (text) (tun.http:address-key (tun.http:parse-ip-address text))))
    (is (equal "203.0.113.7" (key "203.0.113.7")))
    (is (equal "203.0.113.7" (key "::ffff:203.0.113.7")) "IPv4 written as IPv6")
    (is (equal (key "2001:db8:1:2::5") (key "2001:db8:1:2:ffff::1")) "one /64")
    (is (string/= (key "2001:db8:1:2::5") (key "2001:db8:1:3::1")) "another /64")
    (is (equal "2001:db8:1:2::/64" (key "2001:DB8:1:2::5")))
    (dolist (text '("" "unknown" "203.0.113" "256.1.1.1" "203.0.113.7:80" "1:::2" "12345::1"
                    "[2001:db8::1]" "2001:db8::1::2"))
      (is (null (tun.http:parse-ip-address text)) "~s is not an address" text))))

(defun waits-for (port client &key (seconds 6))
  "A thread that waits SECONDS through the proxy for CLIENT on a new
widget; joined, it gives the call's status and the JSON-RPC result's
text."
  (let ((id (new-widget))
        (app *app*))
    (sb-thread:make-thread
     (lambda ()
       (let ((*app* app))
         (multiple-value-bind (status body)
             (post-octets port "/mcp" (tools-call-text "widgets_await_archived"
                                                       (jobj "id" id "seconds" seconds))
                          :headers `(("X-Tun-Actor" . "employee:anna")
                                     ("X-Forwarded-For" . ,client)))
           (list status body)))))))

(test waits-leave-their-clients-requests-in-progress
  (with-address-server (port acceptor :trusted-proxy "127.0.0.1")
    (let ((waits (loop for i below 20
                       collect (prog1 (waits-for port "203.0.113.7")
                                 (eventually (lambda () (= (1+ i) (client-waiting-count
                                                                   "203.0.113.7"))))))))
      (is (= 20 (client-waiting-count "203.0.113.7")) "20 waiting for one client")
      (is (eql 200 (post-octets port "/mcp" (tools-call-text "registry_describe" (jobj))
                                :headers '(("X-Tun-Actor" . "viewer:vera")
                                           ("X-Forwarded-For" . "203.0.113.7"))))
          "and an ordinary call for that client is answered")
      (dolist (answer (mapcar #'sb-thread:join-thread waits))
        (is (eql 200 (first answer)))
        (is (search "aktiv" (second answer)) "each wait answered when it ends")))))

(test a-client-has-at-most-32-calls-waiting
  (with-address-server (port acceptor :trusted-proxy "127.0.0.1")
    (let ((waits (loop for i below tun.core:*max-waiting-per-client*
                       collect (prog1 (waits-for port "203.0.113.7")
                                 (eventually (lambda () (= (1+ i) (client-waiting-count
                                                                   "203.0.113.7"))))))))
      (is (= 32 (client-waiting-count "203.0.113.7")))
      (let* ((start (get-internal-real-time))
             (answer (sb-thread:join-thread (waits-for port "203.0.113.7"))))
        (is (< (elapsed-since start) 2) "the 33rd is refused before it waits")
        (is (search "unavailable" (second answer)) "~a" (second answer))
        (is (search "32 kall venter allerede fra samme adresse" (second answer))))
      (let ((other (waits-for port "203.0.113.8")))
        (is-true (eventually (lambda () (= 1 (client-waiting-count "203.0.113.8"))))
                 "another client's wait is taken")
        (push other waits))
      (dolist (answer (mapcar #'sb-thread:join-thread waits))
        (is (eql 200 (first answer)))))))

(test a-refused-connection-drops-what-it-was-sent-before-it-closes
  ;; The request has arrived when the refusal is made, as it may have when a
  ;; connection is refused: read and dropped, so the connection ends with
  ;; the answer and a clean close, not a reset that can lose the answer.
  (let* ((listener (usocket:socket-listen "127.0.0.1" 0 :reuse-address t
                                                        :element-type '(unsigned-byte 8)))
         (client (connect-from "127.0.0.2" (usocket:get-local-port listener)))
         (server (usocket:socket-accept listener)))
    (unwind-protect
         (progn
           (send-text client (request-head "GET" "/health"
                                           (format nil "X-Fyll: ~a" (ascii-text 8000))))
           (sleep 0.2)
           (tun.http::refuse-connection server)
           (is (eql 503 (head-status (answer-head client))))
           (is (eq :end (handler-case (if (read-byte client nil nil) :more :end)
                          (error () :reset)))
               "and the connection ends cleanly"))
      (close-all (list client))
      (usocket:socket-close listener))))
