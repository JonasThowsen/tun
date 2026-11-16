;;;; pdf/typst.lisp -- the Typst renderer (spec/pdf.md 3.2, 3.3).
;;;;
;;;; Each document gets a directory of its own under the server's temporary
;;;; directory, readable by the server only, holding the document's data as
;;;; data.json and a copy of Tun's layout, document.typ.  Typst runs on it as
;;;; the kernel's own program, reading that directory only (--root) and the
;;;; fonts Tun gives it, and writes document.pdf there.  The directory is
;;;; removed when the PDF has been read, whatever happened.

(in-package #:tun.pdf)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +layout-file+
  (asdf:system-relative-pathname "tun" "src/pdf/document.typ")
  "Tun's layout of a document, the only Typst code that runs.")

(defvar *layout* nil "The layout's text, read once.")

(defun layout-text ()
  (or *layout* (setf *layout* (uiop:read-file-string +layout-file+))))

(defparameter +typst-seconds+ 30 "How long Typst has for a document, held to the deadline.")

(defparameter +most-reported-error+ 600
  "The most characters of what Typst wrote to its standard error that the
log line of a failure keeps.")

(defclass typst-pdf-renderer ()
  ((program :initarg :program :reader typst-program
            :documentation "The path of the typst program, TUN_TYPST.")
   (fonts :initarg :fonts :reader typst-fonts
          :documentation "The directory of the fonts Typst is given, TUN_PDF_FONTS.")
   (timeout :initarg :timeout :initform +typst-seconds+ :reader typst-timeout
            :documentation "The seconds Typst has for a document."))
  (:documentation "Makes a PDF with Typst, run as the kernel's own program."))

(defmethod print-object ((renderer typst-pdf-renderer) stream)
  (print-unreadable-object (renderer stream :type t)
    (format stream "~a" (typst-program renderer))))

(defun new-document-directory ()
  "A new directory under the temporary directory, mode 0700, as a
namestring ending in /."
  (let ((base (namestring (uiop:temporary-directory))))
    (loop repeat 20
          for path = (format nil "~atun-pdf-~a/" base
                             (ironclad:byte-array-to-hex-string (ironclad:random-data 12)))
          when (sb-unix:unix-mkdir (string-right-trim "/" path) #o700)
            return path
          finally (error 'pdf-failure
                         :reason (format nil "no directory could be made under ~a" base)))))

(defmacro with-document-directory ((directory) &body body)
  "Run BODY with DIRECTORY a new document directory, removed after."
  `(let ((,directory (new-document-directory)))
     (unwind-protect (progn ,@body)
       (uiop:delete-directory-tree (pathname ,directory) :validate t :if-does-not-exist :ignore))))

(defun write-file-text (path text)
  (with-open-file (out path :direction :output :if-exists :supersede :external-format :utf-8)
    (write-string text out)))

(defun read-file-octets (path)
  "The octets of the file PATH, or NIL when there is none."
  (with-open-file (in path :element-type '(unsigned-byte 8) :if-does-not-exist nil)
    (when in
      (let ((octets (make-array (file-length in) :element-type '(unsigned-byte 8))))
        (read-sequence octets in)
        octets))))

(defun pdf-octets-p (octets)
  (and octets (> (length octets) 5)
       (every #'= (map 'list #'char-code "%PDF-") (subseq octets 0 5))))

(defun clipped (text)
  (let ((text (trim (or text ""))))
    (if (> (length text) +most-reported-error+)
        (concatenate 'string (subseq text 0 +most-reported-error+) "…")
        text)))

(defun typst-arguments (renderer)
  (list "compile" "--root" "." "--ignore-system-fonts" "--font-path" (typst-fonts renderer)
        "--format" "pdf" "document.typ" "document.pdf"))

(defmethod render-pdf ((renderer typst-pdf-renderer) document)
  (with-document-directory (directory)
    (write-file-text (concatenate 'string directory "data.json") (to-json-string document))
    (write-file-text (concatenate 'string directory "document.typ") (layout-text))
    (multiple-value-bind (output code errors)
        (handler-case
            (run-own-program "typst" (typst-program renderer) (typst-arguments renderer)
                             :directory directory :timeout (typst-timeout renderer)
                             :environment (list* (cons "HOME" directory) (cons "TMPDIR" directory)
                                                 (let ((language (uiop:getenv "LANG")))
                                                   (and language (list (cons "LANG" language))))))
          (program-failure (failure)
            (error 'pdf-failure :reason (operation-error-message failure))))
      (declare (ignore output))
      (unless (eql code 0)
        (error 'pdf-failure :reason (format nil "typst exited with ~a: ~a" code (clipped errors))))
      (let ((octets (read-file-octets (concatenate 'string directory "document.pdf"))))
        (unless (pdf-octets-p octets)
          (error 'pdf-failure :reason (format nil "typst wrote no PDF: ~a" (clipped errors))))
        octets))))
