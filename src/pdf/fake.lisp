;;;; pdf/fake.lisp -- the fake PDF renderer (spec/pdf.md 3.1).
;;;;
;;;; In tests a document is made without Typst: a small PDF, written here,
;;;; of the document's text as PDF-TEXT writes it, in Helvetica, sixty lines
;;;; a page.  It is a real PDF, so a file and a mail take it as they take
;;;; Typst's, and a person who opens one from a test reads what it says.
;;;; Characters outside Latin-1 are written as ?.

(in-package #:tun.pdf)

(declaim (optimize (safety 3) (debug 2)))

(defclass fake-pdf-renderer () ()
  (:documentation "Makes a PDF of a document's text without a program, for tests."))

(defparameter +fake-lines-per-page+ 60 "How many lines of text the fake writes on a page.")

(defun paper-size (paper)
  "The width and height in points of PAPER, as the document's data names it."
  (if (equal paper "us-letter") (values 612 792) (values 595 842)))

(defun pdf-string (text)
  "TEXT as a PDF string literal in Latin-1: parentheses and backslashes
escaped, other characters past Latin-1 as ?."
  (with-output-to-string (out)
    (write-char #\( out)
    (loop for char across text
          do (cond ((member char '(#\( #\) #\\)) (write-char #\\ out) (write-char char out))
                   ((or (< (char-code char) 32) (> (char-code char) 255)) (write-char #\? out))
                   (t (write-char char out))))
    (write-char #\) out)))

(defun document-lines (document)
  "The lines of DOCUMENT's text, as PDF-TEXT would give them, with long
lines cut at 95 characters."
  (let ((text (format nil "~{~a~^~%~%~}"
                      (remove "" (mapcar (lambda (key)
                                           (trim (tree-text (json-tree (gethash key document)))))
                                         '("header" "body" "footer"))
                              :test #'string=))))
    (loop for line in (uiop:split-string text :separator '(#\Newline))
          append (loop for start from 0 below (max 1 (length line)) by 95
                       collect (subseq line start (min (length line) (+ start 95)))))))

(defun json-tree (json)
  "The document's JSON nodes JSON as a node tree TREE-TEXT reads."
  (cond ((stringp json) json)
        ((vectorp json) (map 'list #'json-tree json))
        ((hash-table-p json)
         (let ((tag (intern (string-upcase (gethash "tag" json)) "KEYWORD")))
           (if (eq tag :table)
               `(:table ,@(map 'list (lambda (row)
                                       `(:tr ,@(map 'list (lambda (cell)
                                                            `(:td ,@(json-tree (gethash "c" cell))))
                                                    row)))
                               (concatenate 'vector (gethash "head" json) (gethash "body" json)
                                            (gethash "foot" json))))
               `(,tag ,@(let ((href (gethash "href" json))) (and href `((:@ :href ,href))))
                      ,@(json-tree (gethash "c" json))))))
        (t nil)))

(defun page-content (lines height)
  "The content stream of a page holding LINES, from the top of a page HEIGHT
points high."
  (with-output-to-string (out)
    (format out "BT /F1 10 Tf 12 TL 50 ~d Td~%" (- height 60))
    (dolist (line lines)
      (format out "~a Tj T*~%" (pdf-string line)))
    (format out "ET~%")))

(defun pdf-objects (document)
  "The objects of the fake's PDF of DOCUMENT, as strings, object 1 first."
  (multiple-value-bind (width height) (paper-size (gethash "paper" document))
    (let* ((lines (document-lines document))
           (pages (loop for start from 0 below (max 1 (length lines)) by +fake-lines-per-page+
                        collect (subseq lines start (min (length lines)
                                                         (+ start +fake-lines-per-page+)))))
           (count (length pages))
           ;; 1 catalog, 2 pages, 3 font, 4 info, then a page and its content each.
           (kids (loop for i below count collect (format nil "~d 0 R" (+ 5 (* 2 i))))))
      (append
       (list "<< /Type /Catalog /Pages 2 0 R >>"
             (format nil "<< /Type /Pages /Kids [~{~a~^ ~}] /Count ~d >>" kids count)
             "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"
             (format nil "<< /Title ~a /Producer (Tun, fake renderer) >>"
                     (pdf-string (gethash "title" document))))
       (loop for page in pages
             for i from 0
             for content = (page-content page height)
             append (list (format nil "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ~d ~d] ~
                                   /Resources << /Font << /F1 3 0 R >> >> /Contents ~d 0 R >>"
                                  width height (+ 6 (* 2 i)))
                          (format nil "<< /Length ~d >>~%stream~%~aendstream"
                                  (length content) content)))))))

(defmethod render-pdf ((renderer fake-pdf-renderer) document)
  ;; Every character written is Latin-1, one octet each, so a string's
  ;; length is its offset in the file.
  (let ((pieces (list (format nil "%PDF-1.4~%")))
        (offsets '()))
    (flet ((size () (reduce #'+ pieces :key #'length)))
      (loop for object in (pdf-objects document)
            for number from 1
            do (push (size) offsets)
               (push (format nil "~d 0 obj~%~a~%endobj~%" number object) pieces))
      (let ((xref (size))
            (count (1+ (length offsets))))
        (push (format nil "xref~%0 ~d~%0000000000 65535 f ~%~{~10,'0d 00000 n ~%~}~
                           trailer~%<< /Size ~d /Root 1 0 R /Info 4 0 R >>~%startxref~%~d~%%%EOF~%"
                      count (reverse offsets) count xref)
              pieces)))
    (sb-ext:string-to-octets (apply #'concatenate 'string (reverse pieces))
                             :external-format :latin-1)))
