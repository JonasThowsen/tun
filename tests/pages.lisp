;;;; tests/pages.lisp -- every page for every role (spec/testing.md 5): the
;;;; application's pages opened over HTTP as each actor, the paths they link
;;;; to followed breadth first, and the forms they offer posted untouched.
;;;;
;;;; Only pages Tun's renderer wrote are read, and it always double-quotes
;;;; and escapes its attributes, so links and forms are read with regular
;;;; expressions rather than an HTML parser.

(in-package #:tun.test-support)

(declaim (optimize (safety 3) (debug 2)))

(defparameter *paths-per-shape* 2 "How many paths of one shape an actor opens.")
(defparameter *paths-per-actor* 150 "How many paths an actor opens in all.")

(defparameter +left-out-segments+ '("login" "logout" "auth" "setup" "assets" "ui")
  "The first segments of the paths outside the pages, never opened, posted
to or followed.")

(defparameter +no-actor+ "no actor" "How a report names a request without an actor.")

;;; ------------------------------------------------------------------
;;; Reading a page

(defun html-unescape (text)
  "TEXT, an attribute's value or a text area's text as the renderer escaped
it, as the browser reads it."
  (if (find #\& text)
      (cl-ppcre:regex-replace-all
       "&(amp|lt|gt|quot|#39|#x?[0-9a-fA-F]+);" text
       (lambda (match name)
         (declare (ignore match))
         (cond ((string= name "amp") "&")
               ((string= name "lt") "<")
               ((string= name "gt") ">")
               ((string= name "quot") "\"")
               ((string= name "#39") "'")
               ((char-equal (char name 1) #\x)
                (string (code-char (parse-integer name :start 2 :radix 16))))
               (t (string (code-char (parse-integer name :start 1))))))
       :simple-calls t)
      text))

(defun tag-attributes (text)
  "The attributes in TEXT, what an opening tag holds after its name: an
alist from each name, in lower case, to its value, or T for one without."
  (let ((attributes '()))
    (cl-ppcre:do-register-groups (name value)
        ("([a-zA-Z_:][-a-zA-Z0-9_:.]*)(?:=\"([^\"]*)\")?" text)
      (push (cons (string-downcase name) (if value (html-unescape value) t)) attributes))
    (nreverse attributes)))

(defun tag-attribute (name attributes)
  "The value of the attribute NAME in ATTRIBUTES, TAG-ATTRIBUTES' alist."
  (cdr (assoc name attributes :test #'string=)))

(defun page-links (html)
  "What HTML names to open, in order: a list of (URL . KIND), KIND NIL for
an <a>'s href, else the HX-Request-Type htmx sends for an hx-get:
\"full\" when its target is the body or it selects, \"partial\" otherwise."
  (let ((links '()))
    (cl-ppcre:do-register-groups (tag text) ("<([a-zA-Z][a-zA-Z0-9-]*)\\s([^>]*)>" html)
      (let ((attributes (tag-attributes text)))
        (let ((href (tag-attribute "href" attributes)))
          (when (and (string-equal tag "a") (stringp href))
            (push (cons href nil) links)))
        (let ((get (or (tag-attribute "hx-get" attributes)
                       (tag-attribute "data-hx-get" attributes))))
          (when (stringp get)
            (push (cons get (if (or (equal (or (tag-attribute "hx-target" attributes)
                                               (tag-attribute "data-hx-target" attributes))
                                           "body")
                                    (tag-attribute "hx-select" attributes)
                                    (tag-attribute "data-hx-select" attributes))
                                "full"
                                "partial"))
                  links)))))
    (nreverse links)))

(defstruct (page-form (:constructor make-page-form (action multipart fields)))
  "A form a page offers to post: its action as written, whether it sends
multipart/form-data, and its fields as a browser sends them untouched, an
alist of names to values in order."
  action multipart fields)

(defun select-value (options)
  "The value a select with OPTIONS, the text between its tags, sends: its
selected option's, else its first's."
  (let ((first nil) (selected nil))
    (cl-ppcre:do-register-groups (text label) ("(?s)<option\\b([^>]*)>(.*?)</option>" options)
      (let* ((attributes (tag-attributes text))
             (value (let ((value (tag-attribute "value" attributes)))
                      (if (stringp value) value (html-unescape label)))))
        (unless first (setf first value))
        (when (and (not selected) (tag-attribute "selected" attributes))
          (setf selected value))))
    (or selected first)))

(defparameter +form-controls+
  (concatenate 'string "(?s)<(input|button)\\b([^>]*)>"
               "|<select\\b([^>]*)>(.*?)</select>"
               "|<textarea\\b([^>]*)>(.*?)</textarea>")
  "The controls of a form: an input or a button and its attributes, a select
and its attributes and options, or a text area and its attributes and text.")

(defun form-controls (html owner)
  "The controls in HTML that a form sends, in order, each (:FIELD NAME VALUE)
or (:BUTTON NAME VALUE): each named input with its value, a checkbox or a
radio only when checked and a file input never; each select's value; each
text area's text; and each named submit button.  With OWNER, a form's id,
only the controls that name it with form=OWNER; without, those that name
no other form."
  (let ((controls '()))
    (flet ((owned-p (attributes)
             (let ((form (tag-attribute "form" attributes)))
               (if owner (equal form owner) (not (stringp form))))))
      (cl-ppcre:do-register-groups (control text select-text options area-text area)
          (+form-controls+ html)
        (let* ((attributes (tag-attributes (or text select-text area-text)))
               (name (tag-attribute "name" attributes)))
          (when (and (stringp name) (owned-p attributes)
                     (not (tag-attribute "disabled" attributes)))
            (cond
              (control
               (let ((type (string-downcase
                            (let ((type (tag-attribute "type" attributes)))
                              (cond ((stringp type) type)
                                    ((string-equal control "button") "submit")
                                    (t "text")))))
                     (value (let ((value (tag-attribute "value" attributes)))
                              (if (stringp value) value ""))))
                 (cond ((member type '("submit" "image") :test #'string=)
                        (push (list :button name value) controls))
                       ((member type '("button" "reset" "file") :test #'string=))
                       ((member type '("checkbox" "radio") :test #'string=)
                        (when (tag-attribute "checked" attributes)
                          (push (list :field name (if (stringp (tag-attribute "value" attributes))
                                                      value
                                                      "on"))
                                controls)))
                       (t (push (list :field name value) controls)))))
              (select-text
               (let ((value (select-value options)))
                 (when value (push (list :field name value) controls))))
              (t
               ;; A browser drops the line break right after <textarea>.
               (push (list :field name (html-unescape (string-left-trim '(#\Newline) area)))
                     controls)))))))
    (nreverse controls)))

(defun form-fields (controls)
  "What a browser sends of CONTROLS, FORM-CONTROLS' answer, when their form
is posted untouched: the first named submit button, then the fields."
  (let ((button (find :button controls :key #'first)))
    (mapcar (lambda (control) (cons (second control) (third control)))
            (append (and button (list button))
                    (remove :button controls :key #'first)))))

(defun page-forms (html)
  "The forms of HTML that post, in order.  A form's controls are those
inside it and those elsewhere that name it with form=\"ID\", as a board's
move buttons do."
  (let ((forms '()))
    (cl-ppcre:do-scans (start end starts ends "(?s)<form\\b([^>]*)>(.*?)</form>" html)
      (let* ((attributes (tag-attributes (subseq html (aref starts 0) (aref ends 0))))
             (content (subseq html (aref starts 1) (aref ends 1)))
             (id (tag-attribute "id" attributes)))
        (when (string-equal (let ((method (tag-attribute "method" attributes)))
                              (if (stringp method) method "get"))
                            "post")
          (push (make-page-form
                 (let ((action (tag-attribute "action" attributes)))
                   (if (stringp action) action ""))
                 (equalp (tag-attribute "enctype" attributes) "multipart/form-data")
                 (form-fields
                  (append (form-controls content nil)
                          (and (stringp id)
                               (form-controls (concatenate 'string (subseq html 0 start)
                                                           (subseq html end))
                                              id)))))
                forms))))
    (nreverse forms)))

;;; ------------------------------------------------------------------
;;; Paths

(defun path-segments (path)
  "The segments of PATH, without its query."
  (remove "" (cl-ppcre:split "/" (subseq path 0 (or (position #\? path) (length path))))
          :test #'string=))

(defun without-query (path)
  (subseq path 0 (or (position #\? path) (length path))))

(defun left-out-path-p (path)
  "True for a path outside the pages (spec/testing.md 5), by its first
whole segment."
  (member (first (path-segments path)) +left-out-segments+ :test #'string=))

(defun site-path (url from origin)
  "The path on the site that URL names, read on the page at FROM, a path,
served at ORIGIN (http://127.0.0.1:PORT); or NIL for a link with only a #
fragment, a path on another site and one left out."
  (let* ((url (subseq url 0 (or (position #\# url) (length url))))
         (path (cond ((string= url "") nil)
                     ((eql 0 (search origin url))
                      (let ((rest (subseq url (length origin))))
                        (if (or (string= rest "") (char= (char rest 0) #\?))
                            (concatenate 'string "/" rest)
                            (and (char= (char rest 0) #\/) rest))))
                     ((cl-ppcre:scan "^[a-zA-Z][a-zA-Z0-9+.-]*:" url) nil)
                     ((eql 0 (search "//" url)) nil)
                     ((char= (char url 0) #\/) url)
                     ((char= (char url 0) #\?)
                      (concatenate 'string (without-query from) url))
                     (t (concatenate 'string
                                     (subseq from 0 (1+ (or (position #\/ from :from-end t
                                                                       :end (or (position #\? from)
                                                                                (length from)))
                                                            0)))
                                     url)))))
    (and path (not (left-out-path-p path)) path)))

(defun path-shape (path)
  "PATH's shape: its segments, each holding a digit or an _ written as :id,
and the names of its query's keys, sorted."
  (let* ((query (position #\? path))
         (keys (and query
                    (sort (mapcar (lambda (pair)
                                    (subseq pair 0 (or (position #\= pair) (length pair))))
                                  (cl-ppcre:split "&" (subseq path (1+ query))))
                          #'string<))))
    (format nil "/~{~a~^/~}~@[?~{~a~^&~}~]"
            (mapcar (lambda (segment)
                      (if (or (find-if #'digit-char-p segment) (find #\_ segment)) ":id" segment))
                    (path-segments path))
            keys)))

;;; ------------------------------------------------------------------
;;; Requests

(defun browser-encoded (path)
  "PATH as a browser sends it: each character a URL may not hold as it is,
such as a space, | or a letter outside ASCII, as % and the hex of its UTF-8
bytes."
  (with-output-to-string (out)
    (loop for char across path
          do (if (or (char<= #\a char #\z) (char<= #\A char #\Z) (char<= #\0 char #\9)
                     (find char "-._~:/?@!$&'()*+,;=%"))
                 (write-char char out)
                 (loop for byte across (sb-ext:string-to-octets (string char)
                                                                :external-format :utf-8)
                       do (format out "%~2,'0X" byte))))))

(defun page-request (port actor method path &key htmx fields multipart)
  "Request PATH from the test server on PORT as ACTOR, a string or NIL:
values the status, the body when the answer is text/html, where it
redirects to (Location, or for htmx HX-Location or HX-Redirect), and its
X-Tun-Request-Id."
  (multiple-value-bind (bytes status headers)
      (drakma:http-request (format nil "http://127.0.0.1:~d~a" port (browser-encoded path))
                           :method method :parameters fields :form-data multipart
                           :redirect nil :force-binary t :external-format-out :utf-8
                           :additional-headers
                           (append (and actor (list (cons "X-Tun-Actor" actor)))
                                   (and htmx (list (cons "HX-Request" "true")
                                                   (cons "HX-Request-Type" htmx)))))
    (let ((type (cdr (assoc :content-type headers))))
      (values status
              (and bytes type (search "text/html" type)
                   (sb-ext:octets-to-string bytes :external-format :utf-8))
              (if (<= 300 status 399)
                  (cdr (assoc :location headers))
                  ;; htmx follows these where a browser follows Location.
                  (or (cdr (assoc :hx-location headers)) (cdr (assoc :hx-redirect headers))))
              (cdr (assoc :x-tun-request-id headers))))))

;;; ------------------------------------------------------------------
;;; The report

(defstruct (page-failure (:constructor make-page-failure (actor method path status from problem)))
  "What went wrong: ACTOR's request of PATH with METHOD answered STATUS,
which PROBLEM, a text, says is wrong; FROM is the path whose link, form or
redirect led there, or :LISTED for a page of the application's list.  FAULT
is the first line of the fault the server recorded, or NIL."
  actor method path status from problem fault)

(defstruct (actor-tally (:constructor make-actor-tally (actor)))
  "What one actor did: the paths opened, in order, and their shapes, the
forms posted, in order, and the number of paths the bound left out."
  actor (opened 0) (paths '()) (shapes (make-hash-table :test 'equal)) (posted 0) (forms '())
  (left-out 0) (seconds 0))

(defun note-opened (tally path)
  (incf (actor-tally-opened tally))
  (push path (actor-tally-paths tally))
  (incf (gethash (path-shape path) (actor-tally-shapes tally) 0)))

(defstruct (page-report (:constructor make-page-report (scenario listed)))
  "A run's report: the scenario's name or NIL, the listed pages, each
actor's tally, the failures, the listed paths some actor got a page for,
and how long the run took."
  scenario listed (tallies '()) (failures '()) (answered (make-hash-table :test 'equal))
  (seconds 0))

(defun page-failure-text (failure)
  "FAILURE as a text for a person."
  (let ((from (page-failure-from failure)))
    (format nil "~a: ~a ~a answered ~a: ~a~@[ (~a)~]~@[~%  fault: ~a~]"
            (page-failure-actor failure) (page-failure-method failure) (page-failure-path failure)
            (page-failure-status failure) (page-failure-problem failure)
            (cond ((eq from :listed) "a page of the application")
                  (from (format nil "reached from ~a" from)))
            (page-failure-fault failure))))

(defun pages-summary (report what)
  "The summary of REPORT, a run on the pages of WHAT, for a person: what
each actor opened and posted, and the listed pages no actor got a page of."
  (with-output-to-string (out)
    (format out "Pages of ~a~@[, scenario ~a~]: ~d listed, opened as ~d actors in ~,1f s."
            what (page-report-scenario report) (length (page-report-listed report))
            (length (page-report-tallies report)) (page-report-seconds report))
    (dolist (tally (reverse (page-report-tallies report)))
      (format out "~%  ~a: ~d paths in ~d shapes, ~d forms posted~
                   ~[~:;, ~:*~d left out by the bound~], ~,1f s."
              (actor-tally-actor tally) (actor-tally-opened tally)
              (hash-table-count (actor-tally-shapes tally)) (actor-tally-posted tally)
              (actor-tally-left-out tally) (actor-tally-seconds tally)))
    (let ((unanswered (remove-if (lambda (page)
                                   (gethash (getf page :path) (page-report-answered report)))
                                 (page-report-listed report))))
      (when unanswered
        (format out "~%  Answered no actor with a page:~{ ~a~}"
                (mapcar (lambda (page) (getf page :path)) unanswered))))))

;;; ------------------------------------------------------------------
;;; What the server recorded

(defparameter +fault-wait+ 2
  "How many seconds to wait for the server to record the fault of a request
it answered with a server error: it records it as the request ends.")

(defun first-line (text)
  (subseq text 0 (or (position #\Newline text) (length text))))

(defun recorded-fault (request-id)
  "The first line of the fault the application recorded for the request
REQUEST-ID, its error's type and message, or NIL when it recorded none."
  (when request-id
    (loop with deadline = (+ (get-internal-real-time)
                             (* +fault-wait+ internal-time-units-per-second))
          do (let ((fault (with-application (*app*)
                          (with-actor ((system-actor "pages"))
                            (with-transaction (:read)
                              (let ((occurrence (select-one 'tun.errors:error-occurrence
                                                            :where `(:= "request_id" ,request-id))))
                                (when occurrence
                                  (let* ((id (tun.errors:error-occurrence-group-id occurrence))
                                         (group (select-one 'tun.errors:error-group
                                                            :where `(:= "id" ,id))))
                                    (format nil "~@[~a: ~]~a"
                                            (and group (tun.errors:error-group-error-type group))
                                            (first-line (or (tun.errors:error-occurrence-message
                                                             occurrence)
                                                            "")))))))))))
               (when fault (return fault))
               (when (> (get-internal-real-time) deadline) (return nil))
               (sleep 0.02)))))

;;; ------------------------------------------------------------------
;;; One actor's pages

(defstruct (page-crawl (:constructor make-page-crawl (actor port report tally within)))
  "One actor's run: what it has opened, by path, with the status it got;
the forms its pages offered; and the paths waiting to be opened, each
(PATH FROM HTMX).  WITHIN is NIL, or the first segments of the only paths
it opens, for a test of the crawl itself."
  actor port report tally within
  (statuses (make-hash-table :test 'equal))
  (forms '()) (form-keys (make-hash-table :test 'equal))
  (queue '()) (queue-end nil))

(defun crawl-origin (crawl) (format nil "http://127.0.0.1:~d" (page-crawl-port crawl)))

(defun actor-name-of (crawl) (or (page-crawl-actor crawl) +no-actor+))

(defun note-failure (crawl method path status from problem fault)
  (push (let ((failure (make-page-failure (actor-name-of crawl) method path status from problem)))
          (setf (page-failure-fault failure) fault)
          failure)
        (page-report-failures (page-crawl-report crawl))))

(defun enqueue-path (crawl path from htmx)
  (let ((cell (list (list path from htmx))))
    (unless (within-p path (page-crawl-within crawl))
      (return-from enqueue-path nil))
    (if (page-crawl-queue crawl)
        (setf (cdr (page-crawl-queue-end crawl)) cell (page-crawl-queue-end crawl) cell)
        (setf (page-crawl-queue crawl) cell (page-crawl-queue-end crawl) cell))))

(defun crawl-request (crawl method path &rest options)
  "Request PATH as the crawl's actor: values its status, its HTML, its
redirect's Location as sent, and the first line of a fault the server
recorded for it.  A request that cannot be sent, such as to a path the
HTTP client cannot read, has the status :UNSENT and, as its fault, why."
  (multiple-value-bind (status html location request-id)
      (handler-case (apply #'page-request (page-crawl-port crawl) (page-crawl-actor crawl)
                           method path options)
        (error (condition)
          (return-from crawl-request
            (values :unsent nil nil (first-line (princ-to-string condition))))))
    (values status html location (and (>= status 500) (recorded-fault request-id)))))

(defun error-problem (status)
  (if (eq status :unsent) "a request that could not be sent" "a server error"))

(defun server-error-p (status)
  "True for a status the page test fails: a server error, or a request it
could not send."
  (or (eq status :unsent) (>= status 500)))

(defun redirect-path (crawl location from)
  "The path on the site a redirect's LOCATION, answered at FROM, leads to, or
NIL when it leads off the site or out of the pages."
  (and location (site-path location from (crawl-origin crawl))))

(defun learn-from (crawl path html location)
  "Queue what the answer at PATH leads to: its redirect's path on the site,
and the links and forms of its HTML."
  (let ((target (redirect-path crawl location path)))
    (when target (enqueue-path crawl target path nil)))
  (when html
    (loop for (url . htmx) in (page-links html)
          for target = (site-path url path (crawl-origin crawl))
          when target do (enqueue-path crawl target path htmx))
    (dolist (form (page-forms html))
      (let ((action (site-path (if (string= (page-form-action form) "")
                                   path
                                   (page-form-action form))
                               path (crawl-origin crawl))))
        (when (and action (within-p action (page-crawl-within crawl)))
          (let ((key (format nil "~a~{ ~a~}" action (mapcar #'car (page-form-fields form)))))
            (unless (gethash key (page-crawl-form-keys crawl))
              (setf (gethash key (page-crawl-form-keys crawl)) t)
              (push (list action path form) (page-crawl-forms crawl)))))))))

(defun listed-expectation (page actor)
  "What a GET of PAGE, a listed page's plist, must answer ACTOR, an actor
string or NIL: a function of the status and the redirect's Location that
returns a problem's text, or NIL when the answer is right."
  (let ((admitted (and actor (eq (getf page :kind) :staff)
                       (actor-permits-p (parse-actor actor) (getf page :policy)))))
    (ecase (getf page :kind)
      (:public (constantly nil))
      ((:staff :resource)
       (cond ((null actor)
              (lambda (status location)
                (unless (and (eql status 303) location
                             (let ((path (cl-ppcre:regex-replace "^https?://[^/]*" location "")))
                               (equal (first (path-segments path)) "login")))
                  "not a 303 to the login, with no actor")))
             ((eq (getf page :kind) :resource) (constantly nil))
             ((not admitted)
              (lambda (status location)
                (declare (ignore location))
                (unless (eql status 403) "not 403, to a role the page's policy does not admit")))
             ((getf page :navigation)
              (lambda (status location)
                (declare (ignore location))
                (when (>= status 400) "a refusal, to a role the page's policy admits")))
             (t (constantly nil)))))))

(defun open-listed-pages (crawl listed)
  "GET each page of LISTED as the crawl's actor and check its answer."
  (dolist (page listed)
    (let ((path (getf page :path)))
      (multiple-value-bind (status html location fault) (crawl-request crawl :get path)
        (note-opened (page-crawl-tally crawl) path)
        (setf (gethash path (page-crawl-statuses crawl)) status)
        (cond ((server-error-p status)
               (note-failure crawl "GET" path status :listed (error-problem status) fault))
              (t (let ((problem (funcall (listed-expectation page (page-crawl-actor crawl))
                                         status location)))
                   (when problem (note-failure crawl "GET" path status :listed problem nil)))))
        (when (and (integerp status) (<= 200 status 299))
          (setf (gethash path (page-report-answered (page-crawl-report crawl))) t))
        (when (and (integerp status) (< status 400))
          (learn-from crawl path html location))))))

(defun open-linked-paths (crawl)
  "Open, breadth first, the paths the opened pages lead to, within the
bounds, and check each answer (spec/testing.md 5)."
  (let ((tally (page-crawl-tally crawl))
        (statuses (page-crawl-statuses crawl)))
    (loop while (page-crawl-queue crawl)
          do (destructuring-bind (path from htmx) (pop (page-crawl-queue crawl))
               (let ((known (gethash path statuses))
                     (shape (path-shape path)))
                 (cond
                   ;; Opened before: a link to it is checked by what it answered.
                   (known
                    (when (member known '(403 404))
                      (note-failure crawl "GET" path known from
                                    "a link its actor cannot follow" nil)))
                   ((or (>= (actor-tally-opened tally) *paths-per-actor*)
                        (>= (gethash shape (actor-tally-shapes tally) 0) *paths-per-shape*))
                    (incf (actor-tally-left-out tally))
                    ;; Counted once, however many pages lead there.
                    (setf (gethash path statuses) :left-out))
                   (t
                    (multiple-value-bind (status html location fault)
                        (crawl-request crawl :get path :htmx htmx)
                      (note-opened tally path)
                      (setf (gethash path statuses) status)
                      (cond ((server-error-p status)
                             (note-failure crawl "GET" path status from (error-problem status)
                                           fault))
                            ((member status '(403 404))
                             (note-failure crawl "GET" path status from
                                           "a link its actor cannot follow" nil)))
                      (when (and (integerp status) (< status 400))
                        (learn-from crawl path html location))))))))))

(defun post-forms (crawl)
  "Post each form the crawl's pages offered, once, in the order they were
found, and follow each redirect on the site once."
  (dolist (entry (reverse (page-crawl-forms crawl)))
    (destructuring-bind (action from form) entry
      (multiple-value-bind (status html location fault)
          (crawl-request crawl :post action :fields (page-form-fields form)
                                            :multipart (page-form-multipart form))
        (declare (ignore html))
        (let ((tally (page-crawl-tally crawl)))
          (incf (actor-tally-posted tally))
          (push action (actor-tally-forms tally)))
        (when (server-error-p status)
          (note-failure crawl "POST" action status from (error-problem status) fault))
        (let ((target (redirect-path crawl location action)))
          (when target
            (multiple-value-bind (status html location fault) (crawl-request crawl :get target)
              (declare (ignore html location))
              (when (server-error-p status)
                (note-failure crawl "GET" target status action
                              (format nil "~a, after a post's redirect" (error-problem status))
                              fault)))))))))

(defun open-pages-as (actor port report listed &optional within)
  "Open LISTED and what they lead to as ACTOR, a string or NIL, on the
server on PORT, then post the forms they offer; record it in REPORT.  WITHIN
is as a PAGE-CRAWL's."
  (let* ((tally (make-actor-tally (or actor +no-actor+)))
         (crawl (make-page-crawl actor port report tally within))
         (start (get-internal-real-time)))
    (push tally (page-report-tallies report))
    (enqueue-path crawl "/" :listed nil)
    (open-listed-pages crawl listed)
    (open-linked-paths crawl)
    (post-forms crawl)
    (setf (actor-tally-paths tally) (reverse (actor-tally-paths tally))
          (actor-tally-forms tally) (reverse (actor-tally-forms tally))
          (actor-tally-seconds tally) (/ (- (get-internal-real-time) start)
                                         internal-time-units-per-second))))

;;; ------------------------------------------------------------------
;;; Every actor

(defun call-with-global-values (symbols values function)
  "Call FUNCTION with each of SYMBOLS' global value, the one every thread
sees that has not bound it, set to the matching one of VALUES, and set
back after, unbound again where it was.  The test server's threads run
the pages, and they see no binding of the test's thread."
  (let ((old (mapcar (lambda (symbol)
                       (handler-case (sb-ext:symbol-global-value symbol)
                         (unbound-variable () '%unbound)))
                     symbols)))
    (unwind-protect
         (progn (mapc (lambda (symbol value) (setf (sb-ext:symbol-global-value symbol) value))
                      symbols values)
                (funcall function))
      ;; Back to front, so a symbol named twice ends with its first value.
      (mapc (lambda (symbol value)
              (if (eq value '%unbound)
                  ;; MAKUNBOUND unbinds the value the calling thread sees,
                  ;; here the test's own binding, so a thread with none
                  ;; unbinds the global one.
                  (sb-thread:join-thread
                   (sb-thread:make-thread (lambda () (makunbound symbol))
                                          :name "unbind a global"))
                  (setf (sb-ext:symbol-global-value symbol) value)))
            (reverse symbols) (reverse old)))))

(defun isolated-globals (run)
  "The variables a page test sets for every thread, and their values:
those RUN unsets, at the values its scenario left them with, and Tun's
answers for other systems, as CALL-WITH-FUZZED-APPLICATION binds them in
the test's own thread."
  (values (append (fuzz-run-variables run)
                  '(tun:*http-json-handler* tun:*program-handler* *await-limit*))
          (append (fuzz-run-values run)
                  (list #'unreachable-system #'program-not-started 0))))

(defun serve-pages-to (actor run report within)
  "On *APP*, serve the application over HTTP and open its pages as ACTOR,
WITHIN as a PAGE-CRAWL's."
  (multiple-value-bind (symbols values) (isolated-globals run)
    (call-with-global-values
     symbols values
     (lambda ()
       ;; Starting the server looks up 127.0.0.1 to listen on it.
       (let* ((*loopback-port* 0)
              (acceptor (tun.http:start-server *app* :port 0)))
         (unwind-protect
              (progn
                (setf *loopback-port* (tun.http:server-port acceptor))
                (open-pages-as actor *loopback-port* report (page-report-listed report) within))
           (tun.http:stop-server acceptor)))))))

(defun within-p (path within)
  "True when PATH is opened under WITHIN, a PAGE-CRAWL's."
  (or (null within) (member (first (path-segments path)) within :test #'string=)))

(defun page-actors (actors named)
  "The actors whose pages are opened: NAMED, the scenario's, and of ACTORS
those whose role none of NAMED has.  The scenario's actors own its records,
as the people who use the pages do."
  (let ((roles (mapcar (lambda (actor) (actor-role (parse-actor actor))) named)))
    (append named
            (remove-if (lambda (actor) (member (actor-role (parse-actor actor)) roles)) actors))))

(defun open-every-page (&key (class 'application) scenario (actors +fuzz-actors+) variables
                             (database :memory) within)
  "Open every page of an application of CLASS as the actors SCENARIO names,
each of ACTORS whose role none of them has, and no actor; follow what the
pages lead to and post what they offer, as spec/testing.md 5 says: each
actor on a fresh copy of a database the records of SCENARIO fill, made as
FUZZ-TOOLS makes it, with VARIABLES unset.  WITHIN, for a test of the
crawl itself, is NIL or a list of first segments: only the pages and paths
under them are opened.  Returns a PAGE-REPORT."
  (check-type database (member :memory :postgres))
  (let* ((actors (append (page-actors actors (and scenario (scenario-actors scenario)))
                         (list nil)))
         (run (make-fuzz-run class scenario actors 0 0 (append *isolated-variables* variables)
                             database nil))
         (report nil)
         (start (get-internal-real-time)))
    (with-connections-refused ()
      (take-connection-attempts)
      (unwind-protect
           (progn
             (make-template run)
             (dolist (actor actors)
               (call-with-fuzzed-application
                run
                (lambda (state)
                  (declare (ignore state))
                  (unless report
                    (setf report (make-page-report
                                  (and scenario (scenario-name scenario))
                                  (remove-if-not (lambda (page) (within-p (getf page :path) within))
                                                 (tun.web:application-pages *app*)))))
                  (serve-pages-to actor run report within))
                :initargs '(:identity :claimed))
               (dolist (attempt (take-connection-attempts))
                 (push (make-page-failure
                        (or actor +no-actor+) "CONNECT" attempt "refused" nil
                        "a page tried to reach another host; nothing may leave the process")
                       (page-report-failures report)))))
        (drop-template run)))
    (setf (page-report-failures report) (reverse (page-report-failures report))
          (page-report-seconds report) (/ (- (get-internal-real-time) start)
                                          internal-time-units-per-second))
    report))

(defun check-every-page-answers-every-role (what &rest options)
  "Run OPEN-EVERY-PAGE with OPTIONS for WHAT, a name for the summary, print
the summary, and fail the FiveAM test for each failure."
  (let ((report (apply #'open-every-page options)))
    (format t "~&~a~%" (pages-summary report what))
    (dolist (failure (page-report-failures report))
      (fiveam:fail "~a" (page-failure-text failure)))
    (fiveam:pass)
    report))
