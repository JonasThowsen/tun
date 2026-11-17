;;;; web/single-page.lisp -- a single-page screen of the client's own
;;;; (spec/typescript.md 4): a folder of built files served under a staff
;;;; page's prefix, behind its policy, with the session's proof put in its
;;;; index.html so its calls to /api in the person's session are admitted
;;;; (5).  The page's Content-Security-Policy, set for every answer by
;;;; DISPATCH-WEB, holds for it too.

(in-package #:tun.web)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +single-page-types+
  '(("js" . "text/javascript; charset=utf-8") ("mjs" . "text/javascript; charset=utf-8")
    ("css" . "text/css; charset=utf-8") ("svg" . "image/svg+xml") ("png" . "image/png")
    ("jpg" . "image/jpeg") ("jpeg" . "image/jpeg") ("webp" . "image/webp")
    ("gif" . "image/gif") ("ico" . "image/x-icon") ("woff" . "font/woff")
    ("woff2" . "font/woff2") ("json" . "application/json; charset=utf-8")
    ("txt" . "text/plain; charset=utf-8"))
  "The extensions a single-page screen's files may have, and the type each is
answered with (spec/typescript.md 4).")

(defmacro define-single-page (name (prefix &key (title prefix) (icon :file) (policy :employee)
                                           (navigation t) (group :work))
                              &key files)
  "Define NAME, a single-page screen at /PREFIX and the paths under it
(spec/typescript.md 4): a staff page with TITLE, ICON, POLICY, NAVIGATION
and GROUP as DEFINE-PAGE takes them, whose answers are the files of the
folder FILES names, (SYSTEM PATH): PATH in the directory of the ASDF system
SYSTEM, found where the system was loaded from."
  (unless (and (consp files) (= 2 (length files)) (every #'stringp files))
    (error "define-single-page ~s: :files is (SYSTEM PATH), two strings, not ~s" name files))
  `(progn
     (defun ,name (method path form query)
       (declare (ignore form query))
       (serve-single-page ',files method path))
     (register-staff-page ,prefix ',name :policy ,policy :title ,title :icon ,icon
                          :navigation ,navigation :group ,group)
     ',name))

(defun single-page-folder (files)
  "The folder FILES, (SYSTEM PATH), names."
  (destructuring-bind (system path) files
    (uiop:ensure-directory-pathname (asdf:system-relative-pathname system path))))

(defun single-page-part-p (part)
  "True for a part of a file's path a screen may have: letters, digits, .,
_ and -, not starting with a dot."
  (and (cl-ppcre:scan "^[A-Za-z0-9_-][A-Za-z0-9._-]*$" part) t))

(defun single-page-file (folder parts)
  "Values the file PARTS, a path's parts, names in FOLDER, and its type; NIL
unless every part is one a screen may have, its extension is one of
+SINGLE-PAGE-TYPES+, and the file, followed to what it is, is in the
folder."
  (when (and parts (every #'single-page-part-p parts))
    (let* ((name (car (last parts)))
           (dot (position #\. name :from-end t))
           (type (and dot (cdr (assoc (string-downcase (subseq name (1+ dot)))
                                      +single-page-types+ :test #'string=))))
           (root (probe-file folder)))
      (when (and type root)
        (let ((file (probe-file (merge-pathnames (uiop:parse-unix-namestring
                                                  (format nil "~{~a~^/~}" parts))
                                                 folder))))
          (when (and file (not (uiop:directory-pathname-p file))
                     (eql 0 (search (namestring root) (namestring file))))
            (values file type)))))))

(defun file-octets-of (file)
  "The bytes of FILE."
  (with-open-file (in file :element-type '(unsigned-byte 8))
    (let ((octets (make-array (file-length in) :element-type '(unsigned-byte 8))))
      (read-sequence octets in)
      octets)))

(defun with-api-proof (html)
  "HTML, a screen's index.html, with the proof of this request's session
right after <head> (spec/typescript.md 5.1); unchanged when the request
carries no session's cookie."
  (let ((cookie (tun.http:session-cookie-value *web-app*)))
    (if (null cookie)
        html
        (let ((meta (format nil "<meta name=\"tun-api-proof\" content=\"~a\">"
                            (tun.http:api-proof cookie))))
          (multiple-value-bind (start end) (cl-ppcre:scan "(?i)<head(\\s[^>]*)?>" html)
            (if start
                (concatenate 'string (subseq html 0 end) meta (subseq html end))
                (concatenate 'string meta html)))))))

(defun single-page-not-found ()
  (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
  (values 404 :answered ""))

(defun serve-single-page-index (folder)
  "The screen's index.html in FOLDER with the session's proof, never cached."
  (let ((file (probe-file (merge-pathnames "index.html" folder))))
    (cond ((null file)
           (format *error-output* "~&;; tun web: a single-page screen has no index.html in ~a~%"
                   (namestring folder))
           (single-page-not-found))
          (t (setf (hunchentoot:content-type*) "text/html; charset=utf-8"
                   (hunchentoot:header-out "Cache-Control") "no-store")
             (values 200 :answered
                     (sb-ext:string-to-octets
                      (with-api-proof (uiop:read-file-string file :external-format :utf-8))
                      :external-format :utf-8))))))

(defun serve-single-page (files method parts)
  "Answer METHOD on the single-page screen of FILES at the path PARTS under
its prefix, for someone its policy admits (spec/typescript.md 4)."
  (let ((folder (single-page-folder files)))
    (cond ((preload-request-p) (decline-preload))
          ((not (eq method :get))
           (setf (hunchentoot:header-out "Allow") "GET"
                 (hunchentoot:content-type*) "text/plain; charset=utf-8")
           (values 405 :answered ""))
          ;; A menu entry's link, boosted by htmx, would swap the screen's
          ;; document into the shell: the browser loads it whole instead.
          ((hunchentoot:header-in* :hx-request)
           (setf (hunchentoot:header-out "HX-Redirect") (hunchentoot:request-uri*))
           (values 200 :answered ""))
          ((null parts) (serve-single-page-index folder))
          (t (multiple-value-bind (file type) (single-page-file folder parts)
               (cond ((null file) (single-page-not-found))
                     (t (setf (hunchentoot:content-type*) type
                              (hunchentoot:header-out "Cache-Control") "no-cache"
                              (hunchentoot:header-out "X-Content-Type-Options") "nosniff")
                        (values 200 :answered (file-octets-of file)))))))))
