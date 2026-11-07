;;;; live-definitions.lisp -- observed function changes and loaded source hashes.
(in-package #:tun.core)

(defun application-definition-packages (app)
  (remove-duplicates
   (cons (symbol-package (class-name (class-of app)))
         (mapcar #'find-package *sealed-packages*))))

(defun definition-objects (entry)
  (let ((function (third entry)))
    (if (typep function 'generic-function) (fourth entry) (list function))))

(defun definition-object-source (object)
  (ignore-errors (sb-introspect:find-definition-source object)))

(defun live-source-hash (object)
  "Hash retained compiler source where available; null means no retained source."
  (let* ((function (if (typep object 'method) (closer-mop:method-function object) object))
         (expression (ignore-errors (function-lambda-expression function)))
         (source (definition-object-source object))
         (text (and source (getf (sb-introspect:definition-source-plist source) :emacs-string)))
         (path (and source (sb-introspect:definition-source-pathname source))))
    (cond (text (sha256-hex text))
          (expression (sha256-hex (with-standard-io-syntax (prin1-to-string expression))))
          ((and path (probe-file path)
                (eql (file-write-date path) (sb-introspect:definition-source-file-write-date source)))
           (sha256-hex (uiop:read-file-string path)))
          (t :null))))

(defvar *source-files* (make-hash-table :test 'equal :synchronized t)
  "Path -> ((write-date . length) shown-path hash) of each source file a
snapshot has read.")

(defun source-file-entry (path)
  "What a snapshot lists of the source file at PATH: its path as shown and
its SHA-256.  The file is read and its system looked up again only when its
write date or length is not what it was when it was last read: every
application opened in one image, such as each test's, would otherwise read
every source file."
  (let ((stamp (cons (file-write-date path)
                     (with-open-file (stream path :element-type '(unsigned-byte 8))
                       (file-length stream))))
        (known (gethash path *source-files*)))
    (unless (and known (equal stamp (first known)))
      (setf known (list stamp (display-source-path path) (sha256-hex (uiop:read-file-string path)))
            (gethash path *source-files*) known))
    (jobj "path" (second known) "source_hash" (third known))))

(defun snapshot-live-definitions (app)
  (let ((entries (mapcan #'package-definitions (application-definition-packages app)))
        (paths (make-hash-table :test 'equal)))
    (dolist (entry entries)
      (dolist (object (definition-objects entry))
        (let* ((source (definition-object-source object))
               (path (and source (sb-introspect:definition-source-pathname source))))
          (when (and path (not (gethash path paths)) (probe-file path))
            (setf (gethash path paths) (source-file-entry path))))))
    (setf (application-live-definitions app) entries
          (application-definition-sources app)
          (sort (loop for item being the hash-values of paths collect item)
                #'string< :key (lambda (item) (jget item "path")))))
  app)

(defun same-definition-p (old new)
  (and new (eq (third old) (third new))
       (= (length (fourth old)) (length (fourth new)))
       (every (lambda (method) (member method (fourth new))) (fourth old))))

(defun live-definition-patches (app)
  "Record observed changes once, including client methods on module generics."
  (sb-thread:with-mutex ((application-definitions-lock app))
    (let* ((current (mapcan #'package-definitions (application-definition-packages app)))
           (previous (application-live-definitions app))
           (symbols (remove-duplicates (append (mapcar #'first previous) (mapcar #'first current)))))
      (dolist (symbol symbols)
        (let ((old (assoc symbol previous)) (new (assoc symbol current)))
          (unless (same-definition-p old new)
            (let* ((changed (and new (remove-if (lambda (object) (and old (member object (definition-objects old))))
                                               (definition-objects new))))
                   (hashes (mapcar #'live-source-hash changed)))
              (push (jobj "symbol" (format nil "~a:~a" (package-name (symbol-package symbol)) (symbol-name symbol))
                          "time" (format-rfc3339 (get-universal-time))
                          "source_hash" (cond ((and (= 1 (length hashes)) (stringp (first hashes))) (first hashes))
                                              ((and hashes (notany #'json-null-p hashes))
                                               (sha256-hex (format nil "~{~a~^|~}" hashes)))
                                              (t :null))
                          "change" (if new "redefined" "removed"))
                    (application-live-patches app))))))
      (setf (application-live-definitions app) current))
    (reverse (application-live-patches app))))

(defun live-definition-sources (app)
  (application-definition-sources app))
