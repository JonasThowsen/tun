;;;; web/files.lisp -- files in the web UI (spec/files.md 4.3, 5, 6.2): who
;;;; may post files to a page, the page a refused post gets, the files a
;;;; post carried as a page's FORM sees them, and GET /files/ID.

(in-package #:tun.web)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Posting files to a page

(defun page-admits-p (actor path)
  "True when the page at PATH, a staff page or a resource's, admits ACTOR."
  (let* ((parts (split-path path))
         (page (gethash (first parts) *staff-pages*))
         (resource (find (format nil "/~a" (first parts)) *resources*
                         :key #'resource-path :test #'string=)))
    (cond (page (actor-permits-p actor (staff-page-policy page)))
          (resource (actor-permits-p actor :employee))
          (t nil))))

(defmethod tun.http:upload-admission ((acceptor tun.http:tun-acceptor) path)
  (let ((*web-app* (tun.http:acceptor-application acceptor)))
    (with-application (*web-app*)
      (let ((actor (web-actor)))
        (cond ((cross-origin-post-p) :cross-origin)
              ((null actor) :no-session)
              ((page-admits-p actor path) :admitted)
              (t :refused))))))

(defmethod tun.http:signed-in-p ((acceptor tun.http:tun-acceptor))
  (let ((*web-app* (tun.http:acceptor-application acceptor)))
    (with-application (*web-app*)
      (and (web-actor) t))))

(defmethod tun.http:upload-refusal ((acceptor tun.http:tun-acceptor) status message)
  (let ((*web-app* (tun.http:acceptor-application acceptor)))
    (with-application (*web-app*)
      (let ((*actor* (web-actor))
            (*reference-labels* nil))
        (respond status "Skjemaet ble ikke sendt"
                 (list (ui:alert (:variant (if (= status 503) :warning :destructive)
                                           :title "Skjemaet ble ikke sendt")
                         message)
                       (if *actor*
                           (ui:cluster () (ui:button (:href (or (hunchentoot:referer) "/")
                                                            :variant :outline :icon :arrow-left)
                                            "Tilbake"))
                           (ui:cluster () (ui:button (:href "/login" :icon :log-in)
                                            "Logg inn")))))))))

(defun add-posted-files (form)
  "Put the files this post carried into FORM, a page's posted fields: under
each name, an array of {filename, upload} (spec/files.md 6.2)."
  (let ((names '()))                    ; (name . files), names as posted
    (loop for (name filename handle) in tun.http:*posted-files*
          for entry = (or (assoc name names :test #'string=)
                          (first (push (list name) names)))
          do (push (jobj "filename" filename "upload" handle) (cdr entry)))
    (loop for (name . files) in names
          do (setf (gethash name form) (jarr (reverse files))))
    form))

(defun posted-files-json (name)
  "The files this post carried under NAME, as a FILES parameter takes them,
or :ABSENT."
  (let ((files (loop for (part filename handle) in tun.http:*posted-files*
                     when (string= part name)
                     collect (jobj "filename" filename "upload" handle))))
    (if files (jarr files) :absent)))

;;; ------------------------------------------------------------------
;;; GET /files/ID (spec/files.md 5.2-5.4)

(defparameter +file-security-policy+
  "default-src 'none'; style-src 'unsafe-inline'; sandbox; frame-ancestors 'none'"
  "A file's Content-Security-Policy: no script, no request, in no frame.")

(defparameter *file-send-seconds* 120
  "How long sending one file may take before its connection is closed.")

(defun file-caller (acceptor)
  "Values the caller of a request for a file and its credential: the
signed-in person, else an access token as on /api, else NIL."
  (multiple-value-bind (actor credential) (web-actor)
    (cond (actor (values actor credential))
          ((hunchentoot:header-in* :authorization) (tun.http:mcp-caller acceptor))
          (t (values nil nil)))))

(defun ascii-filename (name)
  "NAME with every character that is not printable ASCII, and \" and \\, as _."
  (map 'string (lambda (c) (if (and (<= 32 (char-code c) 126) (not (member c '(#\" #\\)))) c #\_))
       name))

(defun rfc-5987-value (name)
  "NAME as filename* takes it (RFC 5987 3.2.1): each UTF-8 octet that is not
an attr-char percent-encoded."
  (with-output-to-string (out)
    (loop for octet across (sb-ext:string-to-octets name :external-format :utf-8)
          for char = (code-char octet)
          do (if (and (< octet 128) (or (alphanumericp char) (find char "!#$&+-.^_`|~")))
                 (write-char char out)
                 (format out "%~2,'0X" octet)))))

(defun content-disposition (attachment)
  "The Content-Disposition of ATTACHMENT: an image is shown, a PDF downloaded."
  (let ((name (tun.files:attachment-filename attachment)))
    (format nil "~:[attachment~;inline~]; filename=\"~a\"; filename*=UTF-8''~a"
            (string-prefix-p "image/" (tun.files:attachment-content-type attachment))
            (ascii-filename name)
            (rfc-5987-value name))))

(defun file-not-found ()
  (respond 404 "Fant ikke filen"
           (list (ui:alert (:variant :warning :title "Fant ikke filen")
                   "Filen finnes ikke, eller du har ikke tilgang til den."))))

(defun send-attachment (attachment method)
  "Answer ATTACHMENT's content with the headers of spec/files.md 5.3, sent a
part at a time (5.4); 304 when the browser has it, the headers alone to HEAD."
  (let ((etag (format nil "\"~a\"" (tun.files:attachment-sha256 attachment)))
        (id (entity-id attachment))
        (size (tun.files:attachment-size attachment)))
    (setf (hunchentoot:content-type*) (tun.files:attachment-content-type attachment)
          (hunchentoot:header-out "Content-Disposition") (content-disposition attachment)
          (hunchentoot:header-out "X-Content-Type-Options") "nosniff"
          (hunchentoot:header-out "Content-Security-Policy") +file-security-policy+
          (hunchentoot:header-out "Cross-Origin-Resource-Policy") "same-origin"
          (hunchentoot:header-out "Referrer-Policy") "no-referrer"
          (hunchentoot:header-out "Cache-Control") "private, no-cache"
          (hunchentoot:header-out "ETag") etag)
    (cond ((equal (hunchentoot:header-in* :if-none-match) etag)
           (setf (hunchentoot:return-code*) 304)
           "")
          (t
           (setf (hunchentoot:content-length*) size)
           (let ((stream (hunchentoot:send-headers)))
             (unless (or (eq method :head) (= size (send-parts id size stream)))
               ;; Short of its length (deleted meanwhile, or a reader too
               ;; slow), the answer can only end by closing the connection.
               (tun.http:close-after-answer)))
           nil))))

(defun send-parts (id size stream)
  "Write the content of the attachment ID, SIZE octets, to STREAM a part at a
time, within *FILE-SEND-SECONDS*; how many octets were sent.  Each part is
read in a read transaction of its own, and the time limit bounds only the
writes to the connection (SBCL's deadline for blocking I/O), so it never
cuts into the store's own code."
  (let ((sent 0)
        (end (+ (get-internal-real-time) (* *file-send-seconds* internal-time-units-per-second))))
    (handler-case
        (loop for part = (tun.files:attachment-content-part id sent)
              for left = (/ (- end (get-internal-real-time)) internal-time-units-per-second)
              while (and part (plusp (length part)) (plusp left))
              do (sb-sys:with-deadline (:seconds left)
                   (write-sequence part stream)
                   (when (>= (+ sent (length part)) size)
                     (force-output stream)))
                 (incf sent (length part))
              until (>= sent size))
      (sb-sys:deadline-timeout () nil)
      ;; A reader that went away.
      (stream-error () nil))
    sent))

(defun serve-file (acceptor method id)
  "Answer GET or HEAD /files/ID to a caller who may see the file's record,
and the same 404 to everyone else (spec/files.md 5.2)."
  (multiple-value-bind (actor credential) (file-caller acceptor)
    (let ((*actor* actor)
          (*credential* credential))
      (if (null actor)
          (require-login)
          (let ((attachment (with-transaction (:read) (tun.files:servable-attachment id))))
            (if attachment
                (send-attachment attachment method)
                (file-not-found)))))))
