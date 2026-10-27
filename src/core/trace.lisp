;;;; core/trace.lisp -- request records and step traces (core.md §8.1), and
;;;; source locations of definitions (core.md §8.2, introspect_extensions).
;;;;
;;;; Every top-level operation call, workflow run and UI request gets a
;;;; REQUEST-RECORD: who, what, the input (minus confirmation_token and
;;;; request_key), the outcome, and a list of timed steps (policy, decode,
;;;; idempotency, confirmation, rule, hook, operation, store, external,
;;;; audit, commit).  The code that does the work records its own steps with
;;;; WITH-STEP; outside a request nothing is recorded and WITH-STEP costs one
;;;; special-variable test.  Finished records go into a ring of the last
;;;; *REQUEST-HISTORY-SIZE* requests, in memory only: they are lost on
;;;; restart.  Running requests are in the in-flight table.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Clock: microseconds, monotonic

(declaim (inline trace-clock-us))
(defun trace-clock-us ()
  (multiple-value-bind (seconds nanoseconds) (sb-unix:clock-gettime sb-unix:clock-monotonic)
    (+ (* seconds 1000000) (floor nanoseconds 1000))))

(defun us->ms (us) (and us (/ (round us 10) 100.0d0)))

;;; ------------------------------------------------------------------
;;; Recorded text (core.md §7.5, §8.1).  A record keeps what a caller sent
;;; -- the tool or method named, the path, the actor, the input, the error
;;; message -- only as UTF-8 octets written here, each field clipped to its
;;; bound, so a record costs at most +MOST-RECORD-OCTETS+ of text whatever
;;; the caller sent.  The record's slots are typed to these bounds: an
;;; uncapped string cannot be stored in one.

(defparameter +most-recorded-short+ 256
  "The most octets of a tool, method or path, actor, credential or error type a record keeps.")
(defparameter +most-recorded-message+ 4096
  "The most octets of an error's message a record keeps.")
(defparameter +most-recorded-backtrace+ 8192
  "The most octets of a backtrace's frame names a record keeps.")
(defparameter +most-recorded-input+ (* 48 1024)
  "The most octets of input a record keeps (RECORDED-INPUT).")
(defparameter +input-left-out+ "[utelatt: posten holder høyst 48 KB av input]"
  "What a record keeps of an input value past +MOST-RECORDED-INPUT+.")

(defparameter +most-record-octets+ (* 64 1024)
  "The most octets of text one record keeps: its fields' bounds together.")

(defun recorded-short-p (octets) (<= (length octets) +most-recorded-short+))
(defun recorded-message-p (octets) (<= (length octets) +most-recorded-message+))
(defun recorded-backtrace-p (octets) (<= (length octets) +most-recorded-backtrace+))
(defun recorded-input-p (octets) (<= (length octets) +most-recorded-input+))

(deftype record-octets () '(simple-array (unsigned-byte 8) (*)))
(deftype recorded-short () '(or null (and record-octets (satisfies recorded-short-p))))
(deftype recorded-message () '(or null (and record-octets (satisfies recorded-message-p))))
(deftype recorded-backtrace () '(or null (and record-octets (satisfies recorded-backtrace-p))))
(deftype recorded-input () '(or null (and record-octets (satisfies recorded-input-p))))

(defun utf-8-length (code)
  "How many octets the character whose code is CODE takes in UTF-8."
  (cond ((< code #x80) 1) ((< code #x800) 2) ((< code #x10000) 3) (t 4)))

(defclass recorder (sb-gray:fundamental-character-output-stream)
  ((octets :initarg :octets :reader recorder-octets)
   (most :initarg :most :accessor recorder-most)
   (full :initform nil :accessor recorder-full
         :documentation "True once a character did not fit: nothing more is kept.")
   (abort :initarg :abort :initform nil :reader recorder-abort
          :documentation "When true, a character that does not fit throws to this recorder."))
  (:documentation "A character stream that keeps what is written to it as UTF-8
octets, at most MOST of them."))

(defun make-recorder (most &key abort)
  (make-instance 'recorder :most most :abort abort
                           :octets (make-array (min most 1024) :element-type '(unsigned-byte 8)
                                                               :adjustable t :fill-pointer 0)))

(defmethod sb-gray:stream-write-char ((stream recorder) char)
  (unless (recorder-full stream)
    (let* ((octets (recorder-octets stream))
           (code (char-code char))
           (code (if (<= #xD800 code #xDFFF) #xFFFD code))
           (length (utf-8-length code)))
      (cond ((> (+ (fill-pointer octets) length) (recorder-most stream))
             (setf (recorder-full stream) t)
             (when (recorder-abort stream) (throw stream nil)))
            ((= length 1) (vector-push-extend code octets))
            (t (let ((shift (* 6 (1- length))))
                 (vector-push-extend (logior (ecase length (2 #xC0) (3 #xE0) (4 #xF0))
                                             (ash code (- shift)))
                                     octets)
                 (loop for s from (- shift 6) downto 0 by 6
                       do (vector-push-extend (logior #x80 (ldb (byte 6 s) code)) octets)))))))
  char)

(defmethod sb-gray:stream-write-string ((stream recorder) string &optional (start 0) end)
  (loop for i from start below (or end (length string))
        until (recorder-full stream)
        do (write-char (char string i) stream))
  string)

(defmethod sb-gray:stream-line-column ((stream recorder)) nil)

(defun recorder-result (recorder)
  "What RECORDER kept, as a simple octet vector."
  (coerce (recorder-octets recorder) 'record-octets))

(defun record-text (value most)
  "VALUE, a string, as a record keeps it: its UTF-8 octets, at most MOST of
them; clipped at a character, with … at the end, when it is longer.  NIL
for NIL."
  (when value
    (let ((value (if (stringp value) value (princ-to-string value)))
          (recorder (make-recorder most)))
      (write-string value recorder)
      (when (recorder-full recorder)
        ;; Make room for the … (three octets) at a character's boundary:
        ;; back over the octets that continue a character (10xxxxxx).
        ;; AREF reads past the fill pointer, at what was taken back.
        (let ((octets (recorder-octets recorder)))
          (setf (fill-pointer octets) (max 0 (- (fill-pointer octets) 3)))
          (loop while (and (plusp (fill-pointer octets))
                           (= (logand (aref octets (fill-pointer octets)) #xC0) #x80))
                do (decf (fill-pointer octets)))
          (setf (recorder-full recorder) nil)
          (write-char #\HORIZONTAL_ELLIPSIS recorder)))
      (recorder-result recorder))))

(defun recorded-fits-p (recorder function)
  "Call FUNCTION, which writes to RECORDER, a recorder made with :ABORT: true
when all it wrote fitted, NIL when it stopped at what did not."
  (catch recorder
    (funcall function)
    t))

(defun recorded-string (octets)
  "The text OCTETS, a field a record keeps, hold; NIL for NIL."
  (and octets (sb-ext:octets-to-string octets :external-format :utf-8)))

;;; ------------------------------------------------------------------
;;; Records and steps

(defparameter *request-history-size* 1000
  "Finished requests kept in memory (core.md §8.1: at least 1000; --request-history N).")
(defparameter *max-steps-per-request* 400 "Steps beyond this are counted, not kept.")

(defstruct (trace-step (:constructor make-trace-step (kind name source order started detail)))
  kind name source order started (duration nil) detail)

(defstruct (request-record (:conc-name request-))
  id at started-us
  ;; What the caller sent, as recorded text: written only by the accessors
  ;; below, which clip it (RECORD-TEXT, RECORDED-INPUT).
  (%actor nil :type recorded-short)
  (%credential nil :type recorded-short)
  (%tool nil :type recorded-short)      ; the tool, method or page's path
  (%input nil :type recorded-input)     ; RECORDED-INPUT's JSON text
  (kind :operation)                     ; :operation, :mcp, :api, :web, :job or :workflow
  application                           ; the application it ran in, when known
  outcome
  (%error-code nil :type (or symbol recorded-short))
  (%error-message nil :type recorded-message)
  (%error-type nil :type recorded-short) ; the reported condition's type
  policy-required actor-role decision
  (steps (make-array 16 :adjustable t :fill-pointer 0))
  (store-statements 0)
  (write-lock-wait-us 0)
  total-us
  (%backtrace nil :type recorded-backtrace) ; frame names, one per line
  (conditions '())                      ; recent (condition . backtrace), newest first
  (backtrace-chosen nil)
  (state :running)                      ; :running, :waiting-write-lock or :external-call
  (dropped-steps 0)
  (redacted nil)                       ; erasure removes payloads, including later steps
  (claimed t)                           ; NIL: the next top-level operation call owns this record
  (lock (sb-thread:make-mutex :name "request record")))

;;; The fields a caller's text reaches.  Each writer clips what it is given;
;;; each reader gives back text.

(defmacro define-recorded-field (name slot most)
  `(progn
     (defun ,name (record) (recorded-string (,slot record)))
     (defun (setf ,name) (value record)
       (setf (,slot record) (record-text value ,most))
       value)))

(define-recorded-field request-actor request-%actor +most-recorded-short+)
(define-recorded-field request-credential request-%credential +most-recorded-short+)
(define-recorded-field request-tool request-%tool +most-recorded-short+)
(define-recorded-field request-error-type request-%error-type +most-recorded-short+)
(define-recorded-field request-error-message request-%error-message +most-recorded-message+)

(defun request-error-code (record)
  (let ((code (request-%error-code record)))
    (if (symbolp code) code (recorded-string code))))

(defun (setf request-error-code) (code record)
  (setf (request-%error-code record)
        (if (symbolp code) code (record-text code +most-recorded-short+)))
  code)

(defun request-input (record)
  "RECORD's input as the JSON text's octets RECORDED-INPUT made, or NIL."
  (request-%input record))

(defun (setf request-input) (input record)
  "Keep INPUT as RECORD's input: octets RECORDED-INPUT made, or a JSON
object the kernel made (a job's or a workflow's), recorded within the same
bound; NIL for none."
  (setf (request-%input record)
        (cond ((null input) nil)
              ((typep input 'record-octets)
               (if (recorded-input-p input)
                   input
                   (recorded-json-object (jobj "_" +input-left-out+))))
              (t (recorded-json-object input))))
  input)

(defun recorded-json-object (object)
  "OBJECT, a JSON object, as a record's input: its JSON text's octets, or
+INPUT-LEFT-OUT+ in its place when the text is over +MOST-RECORDED-INPUT+."
  (let ((recorder (make-recorder +most-recorded-input+ :abort t)))
    (if (recorded-fits-p recorder (lambda () (write-json object recorder)))
        (recorder-result recorder)
        (recorded-json-object (jobj "_" +input-left-out+)))))

(defun request-backtrace (record)
  "RECORD's backtrace: the frames' names, innermost first."
  (let ((text (recorded-string (request-%backtrace record))))
    (and text (uiop:split-string text :separator '(#\Newline)))))

(defun (setf request-backtrace) (frames record)
  (setf (request-%backtrace record)
        (and frames (record-text (format nil "~{~a~^~%~}" frames) +most-recorded-backtrace+)))
  frames)

(defun request-record-octets (record)
  "How many octets of text RECORD keeps: never more than +MOST-RECORD-OCTETS+."
  (+ (length (or (request-%actor record) #()))
     (length (or (request-%credential record) #()))
     (length (or (request-%tool record) #()))
     (length (or (request-%input record) #()))
     (let ((code (request-%error-code record))) (if (symbolp code) 0 (length code)))
     (length (or (request-%error-message record) #()))
     (length (or (request-%error-type record) #()))
     (length (or (request-%backtrace record) #()))))

(defvar *request-id* nil
  "Identity of the top-level request (one MCP call, one web request, one
top-level Lisp call). A confirmation token is never accepted in the request
that issued it, so code running inside a request -- a client :after method,
a workflow, a screen -- cannot confirm on the user's behalf.")

(defvar *request-record* nil "The record of the request running in this thread, if any.")

(defun add-step (record kind name source order detail)
  (sb-thread:with-mutex ((request-lock record))
    (if (>= (fill-pointer (request-steps record)) *max-steps-per-request*)
        (progn (incf (request-dropped-steps record)) nil)
        (let ((step (make-trace-step kind name source order (trace-clock-us)
                                     (if (request-redacted record) "[slettet]" detail))))
          (vector-push-extend step (request-steps record))
          step))))

(defun call-with-step (kind name source order detail function)
  (let ((record *request-record*))
    (if (null record)
        (funcall function)
        (let ((step (add-step record kind name source order detail)))
          (if (null step)
              (funcall function)
              (unwind-protect (funcall function)
                (setf (trace-step-duration step) (- (trace-clock-us) (trace-step-started step)))))))))

(defmacro with-step ((kind &key name source order detail) &body body)
  "Run BODY as a timed step of the current request (if any).  KIND is one of
:policy :decode :idempotency :confirmation :rule :hook :operation :store
:external :audit :commit."
  `(call-with-step ,kind ,name ,source ,order ,detail (lambda () ,@body)))

(defun note-step (kind &key name source order detail (started (trace-clock-us)) (duration 0))
  "Record a step that already happened (STARTED and DURATION in microseconds)."
  (let ((record *request-record*))
    (when record
      (let ((step (add-step record kind name source order detail)))
        (when step
          (setf (trace-step-started step) started
                (trace-step-duration step) duration))))))

(defun statement-verb (sql)
  (let ((end (or (position #\Space sql) (length sql))))
    (subseq sql 0 (min end 24))))

(defun note-store-statement (sql started)
  "A store adapter executed SQL (a string), which began at STARTED (microseconds)."
  (let ((record *request-record*))
    (when record
      (incf (request-store-statements record))
      ;; The SQL text is kept by reference (it is mostly a cached string);
      ;; its verb and a shortened copy are made only when the trace is read.
      (note-step :store :detail sql :started started :duration (- (trace-clock-us) started)))))

(defun note-write-lock-wait (microseconds)
  (let ((record *request-record*))
    (when record (incf (request-write-lock-wait-us record) microseconds))))

(defmacro with-request-state ((state) &body body)
  "Mark the current request STATE (:waiting-write-lock, :external-call) around BODY."
  (let ((record (gensym "RECORD")) (old (gensym "OLD")))
    `(let* ((,record *request-record*)
            (,old (and ,record (request-state ,record))))
       (if (null ,record)
           (progn ,@body)
           (unwind-protect (progn (setf (request-state ,record) ,state) ,@body)
             (setf (request-state ,record) ,old))))))

;;; ------------------------------------------------------------------
;;; Outcomes and backtraces

(defparameter +rejection-codes+ '(:forbidden :confirmation-invalid :idempotency-conflict)
  "Codes audited as rejected (core.md §3.8); every other error code is outcome error.")

(defun outcome-for-code (code)
  (if (member code +rejection-codes+) "rejected" "error"))

(defun frame-name (frame)
  (let ((*package* (find-package :cl-user))
        (*print-length* 4) (*print-level* 3) (*print-readably* nil))
    (string-downcase (prin1-to-string (sb-di:debug-fun-name (sb-di:frame-debug-fun frame))))))

(defun capture-backtrace (&key (count 40))
  "Function names (no arguments: they may hold secrets) of the frames above
the signal point, innermost first."
  (let ((frames '()))
    (ignore-errors
     (sb-debug:map-backtrace (lambda (frame) (push (frame-name frame) frames)) :count (+ count 12)))
    (setf frames (nreverse frames))
    ;; Drop this function, the handler and the signalling machinery: start
    ;; below the frame that signalled (ERROR, CERROR or SIGNAL).
    (let ((start (position-if (lambda (name) (member name '("error" "cerror" "signal") :test #'string=))
                              frames :end (min 16 (length frames)))))
      (when start
        (setf frames (nthcdr (1+ start) frames))))
    (subseq frames 0 (min count (length frames)))))

(defun note-request-error (record condition)
  "Called when CONDITION is signalled inside RECORD's request: keep its
backtrace (for the last few conditions); which one is reported is decided
when the request ends (CHOOSE-REQUEST-BACKTRACE)."
  (unless (assoc condition (request-conditions record) :test #'eq)
    (let ((entry (cons condition (capture-backtrace))))
      (setf (request-conditions record)
            (cons entry (subseq (request-conditions record) 0 (min 7 (length (request-conditions record)))))))))

(defmacro with-backtrace-capture ((record) &body body)
  "Note the backtrace of every fault signalled in BODY for RECORD.  Must sit
inside the handlers that catch it: a HANDLER-CASE between the signal and
this form would unwind before it is consulted."
  (let ((r (gensym "RECORD")))
    `(let ((,r ,record))
       (if (null ,r)
           (progn ,@body)
           (handler-bind ((error (lambda (c) (unless (typep c 'rejection-signal) (note-request-error ,r c))))
                          (storage-condition (lambda (c) (note-request-error ,r c))))
             ,@body)))))

(defun condition-type-text (condition)
  "CONDITION's type as text, such as simple-error or tun.mail::mail-not-delivered."
  (let ((*package* (find-package :cl-user)))
    (string-downcase (prin1-to-string (type-of condition)))))

(defun choose-request-backtrace (record condition)
  "Report the backtrace taken when CONDITION was signalled (first choice wins)."
  (when (and record (not (request-backtrace-chosen record)))
    (let ((entry (assoc condition (request-conditions record) :test #'eq)))
      (when entry
        (setf (request-backtrace record) (cdr entry)
              (request-error-type record) (condition-type-text condition)
              (request-backtrace-chosen record) t)))))

(defun set-request-outcome (record outcome &key code message)
  (setf (request-outcome record) outcome
        (request-error-code record) code
        (request-error-message record) (if (and message (request-redacted record)) "[slettet]" message)))

(defun request-input-json (record)
  "RECORD's input as a JSON object: {} when it has none."
  (let ((input (request-input record)))
    (if input (parse-json (recorded-string input)) (jobj))))

(defun set-request-policy (record required role decision)
  (unless (request-policy-required record)
    (setf (request-policy-required record) required
          (request-actor-role record) role
          (request-decision record) decision)))

;;; ------------------------------------------------------------------
;;; Retention

(defvar *history-lock* (sb-thread:make-mutex :name "request history"))
(defvar *history* (make-array 0 :initial-element nil) "Ring of finished records.")
(defvar *history-next* 0)
(defvar *history-index* (make-hash-table :test 'equal) "Request id -> record (history and in flight).")
(defvar *in-flight* '() "Records of running requests.")

(defun ensure-history ()
  (unless (= (length *history*) *request-history-size*)
    (setf *history* (make-array *request-history-size* :initial-element nil)
          *history-next* 0)))

(defun register-in-flight (record)
  (sb-thread:with-mutex (*history-lock*)
    (push record *in-flight*)
    (setf (gethash (request-id record) *history-index*) record)))

(defun retire-request (record)
  (sb-thread:with-mutex (*history-lock*)
    (sb-thread:with-mutex ((request-lock record))
      (when (request-redacted record) (redact-request-payload record)))
    (ensure-history)
    (setf *in-flight* (delete record *in-flight* :count 1))
    (let ((evicted (aref *history* *history-next*)))
      (when (and evicted (eq (gethash (request-id evicted) *history-index*) evicted))
        (remhash (request-id evicted) *history-index*)))
    (setf (aref *history* *history-next*) record
          *history-next* (mod (1+ *history-next*) (length *history*))
          (gethash (request-id record) *history-index*) record)))

(defun find-request (id)
  (sb-thread:with-mutex (*history-lock*) (gethash id *history-index*)))

(defun in-flight-requests ()
  (sb-thread:with-mutex (*history-lock*) (copy-list *in-flight*)))

(defun finished-requests ()
  "Finished records, newest first."
  (sb-thread:with-mutex (*history-lock*)
    (ensure-history)
    (let ((size (length *history*)) (out '()))
      (loop for i from 1 to size
            for record = (aref *history* (mod (- *history-next* i) size))
            while record
            do (push record out))
      (nreverse out))))

(defun redact-request-payload (record)
  "Discard trace payloads without changing identity, outcome or timing; caller holds its lock."
  (setf (request-redacted record) t (request-input record) nil)
  (when (request-error-message record) (setf (request-error-message record) "[slettet]"))
  (loop for step across (request-steps record) do (setf (trace-step-detail step) "[slettet]")))

(defvar *stored-diagnostics-redactors* '()
  "Functions of NEEDLES that erase the diagnostics kept in the store which
match them, in the erasing write transaction: TUN.ERRORS adds the recorded
errors' (spec/errors.md 4).")

(defun redact-request-traces (needles)
  "Erase retained diagnostic payloads matching subject IDs or personal data in this write transaction.
In-flight requests are fenced too: a pending read can still append old data.
Rollback restores prior payloads; completed unrelated records retain their diagnostics.
Diagnostics kept in the store are erased in the same transaction."
  (assert-writable)
  (dolist (redactor *stored-diagnostics-redactors*)
    (funcall redactor needles))
  (let ((needles (remove-if-not (lambda (value) (and (stringp value) (plusp (length value)))) needles))
        (snapshots nil))
    (labels ((concerns-subject-p (value)
               (cond ((stringp value) (some (lambda (needle) (search needle value :test #'char-equal)) needles))
                     ;; A recorded input, kept as its JSON text's octets.
                     ((typep value '(vector (unsigned-byte 8)))
                      (concerns-subject-p (sb-ext:octets-to-string value :external-format :utf-8)))
                     ((hash-table-p value) (loop for nested being the hash-values of value thereis (concerns-subject-p nested)))
                     ((vectorp value) (some #'concerns-subject-p value))
                     ((consp value) (or (concerns-subject-p (car value)) (concerns-subject-p (cdr value)))))))
      (sb-thread:with-mutex (*history-lock*)
        (maphash (lambda (id record)
                   (declare (ignore id))
                   (sb-thread:with-mutex ((request-lock record))
                     (when (and (not (request-redacted record))
                                (or (member record *in-flight*)
                                    (concerns-subject-p (request-input record))
                                    (concerns-subject-p (request-error-message record))
                                    (some (lambda (step) (concerns-subject-p (trace-step-detail step))) (request-steps record))))
                       (push (list record (request-input record) (request-error-message record)
                                   (map 'list (lambda (step) (cons step (trace-step-detail step))) (request-steps record))) snapshots)
                       (redact-request-payload record))))
                 *history-index*)))
    (on-rollback (lambda ()
                   (dolist (snapshot snapshots)
                     (destructuring-bind (record input message details) snapshot
                       (sb-thread:with-mutex ((request-lock record))
                         (setf (request-redacted record) nil (request-input record) input (request-error-message record) message)
                         (dolist (entry details) (setf (trace-step-detail (car entry)) (cdr entry))))))))))

;;; ------------------------------------------------------------------
;;; The request boundary

(define-condition rejection-signal (error) ()
  (:documentation "Mixin for conditions that are rejections, not faults: no backtrace is kept."))

(defgeneric request-finished (application record)
  (:documentation "Called when RECORD, the request record of a request that ran in
APPLICATION, has ended and been retired, outside any request: the kernel
records a fault and writes the request's log line (spec/errors.md).")
  (:method (application record)
    (declare (ignore application record))
    nil))

(defun call-with-request-record (function &key id at actor credential tool input (kind :operation)
                                                application force-new claimable)
  "Run FUNCTION as one recorded request of APPLICATION, unless a request is
already being recorded in this thread (then it is part of that one), or
FORCE-NEW.  A CLAIMABLE record (the transport's, for one /mcp request) is
taken over by the first operation called in it."
  (if (and *request-record* (not force-new))
      (funcall function)
      (let ((record (make-request-record :id (or id (new-id "req")) :at at
                                         :started-us (trace-clock-us)
                                         :kind kind :application application
                                         :claimed (not claimable))))
        (setf (request-actor record) actor
              (request-credential record) credential
              (request-tool record) tool
              (request-input record) input)
        (unwind-protect
             (let ((*request-record* record)
                   (finished nil))
               (register-in-flight record)
               (unwind-protect
                    (handler-bind ((error (lambda (c)
                                            (unless (typep c 'rejection-signal)
                                              (note-request-error record c))))
                                   (storage-condition (lambda (c) (note-request-error record c))))
                      (multiple-value-prog1 (funcall function)
                        (setf finished t)))
                 (end-request record finished)))
          ;; Whatever request-finished does is not a step of this request,
          ;; nor of a request this one ran inside.
          (let ((*request-record* nil))
            (request-finished (request-application record) record))))))

(defun end-request (record finished)
  "Give RECORD its time and, when nothing gave it one, its outcome: ok when
the request FINISHED, else the error of the condition that ended it; then
retire it to the history."
  (setf (request-total-us record) (- (trace-clock-us) (request-started-us record)))
  (let ((latest (first (request-conditions record))))
    (unless (request-outcome record)
      (if finished
          (set-request-outcome record "ok")
          (set-request-outcome record "error"
                               :code :internal-error
                               :message (or (and latest (ignore-errors (princ-to-string (car latest))))
                                            "Forespørselen ble avbrutt"))))
    (when (and (equal (request-outcome record) "error") (not (request-backtrace-chosen record))
               latest)
      (setf (request-backtrace record) (cdr latest)
            (request-error-type record) (condition-type-text (car latest)))))
  ;; Condition objects can hold large data; the backtrace strings are enough.
  (setf (request-conditions record) '())
  (retire-request record))

(defmacro with-request-record ((&rest keys) &body body)
  `(call-with-request-record (lambda () ,@body) ,@keys))

;;; ------------------------------------------------------------------
;;; JSON projections

(defun code-string (code) (and code (if (keywordp code) (json-name-of code) (princ-to-string code))))

(defun step->json (record step)
  (let ((object (jobj "kind" (string-downcase (symbol-name (trace-step-kind step)))
                      "started_ms" (us->ms (- (trace-step-started step) (request-started-us record)))
                      "duration_ms" (if (trace-step-duration step) (us->ms (trace-step-duration step)) :null))))
    (let ((name (or (trace-step-name step)
                    (and (eq (trace-step-kind step) :store) (stringp (trace-step-detail step))
                         (statement-verb (trace-step-detail step))))))
      (when name (setf (gethash "name" object) name)))
    (when (trace-step-source step)
      (setf (gethash "source" object) (string-downcase (symbol-name (trace-step-source step)))))
    (when (trace-step-order step) (setf (gethash "order" object) (trace-step-order step)))
    (let ((detail (if (request-redacted record) "[slettet]" (trace-step-detail step))))
      (when detail
        (setf (gethash "detail" object)
              (if (and (stringp detail) (> (length detail) 300)) (concatenate 'string (subseq detail 0 300) "…") detail))))
    object))

(defun request-elapsed-us (record)
  (or (request-total-us record) (- (trace-clock-us) (request-started-us record))))

(defun request->json (record)
  (let* ((steps (sb-thread:with-mutex ((request-lock record)) (copy-seq (request-steps record))))
         (running (null (request-total-us record)))
         (object (jobj "request_id" (request-id record)
                       "at" (if (request-at record) (format-rfc3339 (request-at record)) :null)
                       "actor" (or (request-actor record) :null)
                       "tool" (or (request-tool record) :null)
                       "input" (if (request-redacted record) (jobj) (request-input-json record))
                       "outcome" (if running "running" (request-outcome record))
                       "policy" (jobj "required" (or (code-string (request-policy-required record)) :null)
                                      "actor_role" (or (code-string (request-actor-role record)) :null)
                                      "decision" (or (request-decision record) :null))
                       "steps" (jarr (map 'list (lambda (s) (step->json record s)) steps))
                       "store_statements" (request-store-statements record)
                       "write_lock_wait_ms" (us->ms (request-write-lock-wait-us record))
                       "total_ms" (us->ms (request-elapsed-us record)))))
    (when (request-error-code record)
      (setf (gethash "error" object)
            (jobj "code" (code-string (request-error-code record))
                  "message" (if (request-redacted record) "[slettet]" (or (request-error-message record) "")))))
    (when (and (equal (request-outcome record) "error") (not running))
      (setf (gethash "backtrace" object) (jarr (request-backtrace record))))
    (when (plusp (request-dropped-steps record))
      (setf (gethash "steps_dropped" object) (request-dropped-steps record)))
    (when (request-credential record)
      (setf (gethash "credential" object) (request-credential record)))
    (unless (eq (request-kind record) :operation)
      (setf (gethash "kind" object) (request-kind-string record)))
    object))

(defun request-kind-string (record)
  (string-downcase (symbol-name (request-kind record))))

(defun request-summary->json (record)
  (let ((object (jobj "request_id" (request-id record)
                      "at" (if (request-at record) (format-rfc3339 (request-at record)) :null)
                      "kind" (request-kind-string record)
                      "actor" (or (request-actor record) :null)
                      "tool" (or (request-tool record) :null)
                      "outcome" (request-outcome record)
                      "total_ms" (us->ms (request-elapsed-us record)))))
    (when (request-error-code record)
      (setf (gethash "error_code" object) (code-string (request-error-code record))
            (gethash "message" object) (if (request-redacted record)
                                           "[slettet]"
                                           (or (request-error-message record) ""))))
    object))

;;; ------------------------------------------------------------------
;;; Source locations (introspect_extensions)

(defun asd-directory (directory)
  "The nearest directory at or above DIRECTORY that holds an .asd file, and that file's name."
  (loop for dir = directory then (uiop:pathname-parent-directory-pathname dir)
        for asd = (first (directory (merge-pathnames "*.asd" dir)))
        when asd return (values dir (pathname-name asd))
        until (equal dir (uiop:pathname-parent-directory-pathname dir))))

(defun display-source-path (file)
  "FILE relative to its system: core files as e.g. modules/orders.lisp, client
files as clients/<system>/<file>, the same in a working tree and a Nix build."
  (multiple-value-bind (root system) (ignore-errors (asd-directory (uiop:pathname-directory-pathname file)))
    (cond ((null root) (file-namestring file))
          ((string= system "tun") (enough-namestring file root))
          ((string-prefix-p "tun-" system)
           (format nil "modules/~a/~a" (subseq system 4) (enough-namestring file root)))
          (t (format nil "clients/~a/~a" system (enough-namestring file root))))))

(defun current-source-location ()
  "\"file:line\" of the top-level form being compiled (or loaded from source)
now, or NIL.  Called by the defining macros at expansion time."
  (let* ((file (or *compile-file-truename* *load-truename*))
         (info (and (boundp 'sb-c::*source-info*) sb-c::*source-info*))
         (stream (and info (ignore-errors (sb-c::source-info-stream info))))
         (line (and stream (sb-int:form-tracking-stream-p stream)
                    (ignore-errors
                     (car (sb-int:line/col-from-charpos
                           stream (sb-int:form-tracking-stream-form-start-char-pos stream)))))))
    (and file (format nil "~a:~d" (display-source-path file) (or line 0)))))

(defvar *toplevel-lines* (make-hash-table :test 'equal :synchronized t)
  "Source file namestring -> vector of the line on which each top-level form starts.")

(defun scan-toplevel-lines (pathname)
  "Lines of the top-level forms of the Lisp file PATHNAME, by a scanner that
knows strings, comments, character literals and |symbols| (no READ: nothing
in the file is interpreted)."
  (let ((lines (make-array 0 :adjustable t :fill-pointer 0))
        (text (uiop:read-file-string pathname)))
    (let ((i 0) (n (length text)) (line 1) (depth 0))
      (flet ((peek (k) (if (< (+ i k) n) (char text (+ i k)) #\Nul)))
        (loop while (< i n)
              for c = (char text i)
              do (cond ((char= c #\Newline) (incf line) (incf i))
                       ((char= c #\;) (loop while (and (< i n) (char/= (char text i) #\Newline)) do (incf i)))
                       ((and (char= c #\#) (char= (peek 1) #\|))
                        (incf i 2)
                        (loop while (and (< i n) (not (and (char= (char text i) #\|) (char= (peek 1) #\#))))
                              do (when (char= (char text i) #\Newline) (incf line)) (incf i))
                        (incf i 2))
                       ((and (char= c #\#) (char= (peek 1) #\\)) (incf i 3)
                        (loop while (and (< i n) (alpha-char-p (char text i))) do (incf i)))
                       ((or (char= c #\") (char= c #\|))
                        (incf i)
                        (loop while (and (< i n) (char/= (char text i) c))
                              do (when (char= (char text i) #\\) (incf i))
                                 (when (and (< i n) (char= (char text i) #\Newline)) (incf line))
                                 (incf i))
                        (incf i))
                       ((char= c #\()
                        (when (zerop depth) (vector-push-extend line lines))
                        (incf depth) (incf i))
                       ((char= c #\)) (setf depth (max 0 (1- depth))) (incf i))
                       (t (incf i))))))
    lines))

(defun toplevel-form-line (pathname number)
  (let* ((key (namestring pathname))
         (lines (or (gethash key *toplevel-lines*)
                    (setf (gethash key *toplevel-lines*)
                          (or (ignore-errors (scan-toplevel-lines pathname)) #())))))
    (and (< -1 number (length lines)) (aref lines number))))

(defun definition-source-location (object)
  "\"file:line\" for a function or method OBJECT (via SBCL's recorded
definition source: file and top-level form number), or NIL."
  (let ((source (ignore-errors (sb-introspect:find-definition-source object))))
    (when source
      (let ((pathname (sb-introspect:definition-source-pathname source))
            (form (first (sb-introspect:definition-source-form-path source))))
        (when pathname
          (format nil "~a:~d" (display-source-path pathname)
                  (or (and form (probe-file pathname) (toplevel-form-line pathname form)) 0)))))))

;;; ------------------------------------------------------------------
;;; Dry runs (explain) and the protocols clients extend

(defun call-collecting-steps (function)
  "Call FUNCTION with a scratch request record; values: FUNCTION's primary
value and the steps it recorded.  The steps are also appended to the
current request, if any."
  (let* ((outer *request-record*)
         (scratch (make-request-record :id "dry-run" :started-us (trace-clock-us)))
         (result (let ((*request-record* scratch)) (funcall function)))
         (steps (coerce (request-steps scratch) 'list)))
    (when outer
      (dolist (step steps)
        (let ((copy (add-step outer (trace-step-kind step) (trace-step-name step) (trace-step-source step)
                              (trace-step-order step) (trace-step-detail step))))
          (when copy
            (setf (trace-step-started copy) (trace-step-started step)
                  (trace-step-duration copy) (trace-step-duration step))))))
    (values result steps)))

(defclass extension-protocol ()
  ((name :initarg :name :reader extension-protocol-name
         :documentation "The generic function a client (or a dependent module) adds methods to.")
   (kind :initarg :kind :reader extension-protocol-kind
         :documentation "The introspect_extensions kind of its methods: \"before\" for seams that
feed an operation's computation, \"screen\" for screens, \"rule\" for rule points.")
   (point :initarg :point :reader extension-protocol-point
          :documentation "The published name of the extension point (e.g. \"discount\").")
   (module :initarg :module :reader extension-protocol-module)
   (description :initarg :description :initform nil :reader extension-protocol-description)))

(defvar *extension-protocols* '()
  "The named extension points (seams, rule points, screens) modules and the
kernel publish, as EXTENSION-PROTOCOL objects in registration order.")

(defun register-extension-protocol (name kind &key point module description)
  "Publish the generic function NAME as an extension point of KIND.  POINT is
its published name (default: NAME in snake_case); MODULE defaults to the
module loading this form."
  (let ((protocol (make-instance 'extension-protocol
                                 :name name :kind kind :point (or point (json-name-of name))
                                 :module (or module (current-definition-module))
                                 :description description)))
    (setf *extension-protocols*
          (append (remove name *extension-protocols* :key #'extension-protocol-name) (list protocol))))
  name)
