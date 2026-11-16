;;;; tests/pdf-tests.lisp -- documents as PDF (spec/pdf.md): the tree checked
;;;; as a mail's, the document's data, PDF-TEXT, the fake in tests, Typst in
;;;; a server (paper, margins, a table across pages, page numbers, hostile
;;;; text, failures, its environment), bytes attached to a record and a
;;;; mail, and the speed of a 200-line document.  A made PDF is read with
;;;; Poppler's pdfinfo and pdftotext, which Tun's dev shell carries.

(in-package #:tun.tests)

(def-suite pdf :in core)
(in-suite pdf)

;;; ------------------------------------------------------------------
;;; Documents

(defparameter +right+ "text-align: right")

(defun invoice-line (i)
  "The description of line I of the test invoice."
  (format nil "Telt 6 x 12 m med gulv, linje ~d" i))

(defun invoice-tree (lines &key (amount "1 250,00 kr"))
  "An invoice of LINES lines, as the client-api example builds one: a table
of two address columns, then the lines with a head and totals."
  `((:h1 "Faktura 10042")
    (:table (:tr (:td (:strong "Kunde AS") (:br) "Storgata 1" (:br) "0155 Oslo")
                 (:td "Fakturadato: 16.11.2026" (:br) "Forfall: 30.11.2026")))
    (:table (:thead (:tr (:th (:@ :style "width: 6%") "Nr")
                         (:th "Beskrivelse")
                         (:th (:@ :style ,+right+) "Antall")
                         (:th (:@ :style ,+right+) "Pris")
                         (:th (:@ :style ,+right+) "Beløp")))
            (:tbody ,@(loop for i from 1 to lines
                            collect `(:tr (:td ,i) (:td ,(invoice-line i))
                                          (:td (:@ :style ,+right+) 2)
                                          (:td (:@ :style ,+right+) ,amount)
                                          (:td (:@ :style ,+right+) ,amount))))
            (:tfoot (:tr (:td (:@ :colspan 4 :style ,+right+) (:strong "Å betale"))
                         (:td (:@ :style ,+right+) (:strong "Sum alt")))))
    (:p "Takk for handelen.")))

(defun typst-renderer ()
  "Typst as the environment names it: Tun's dev shell sets TUN_TYPST and
TUN_PDF_FONTS."
  (or (tun.pdf:environment-pdf-renderer)
      (error "TUN_TYPST and TUN_PDF_FONTS are not set: run the tests in nix develop")))

(defmacro with-typst ((&rest app-args) &body body)
  "Run BODY in a test application that makes PDFs with Typst."
  `(with-test-app (:pdf-renderer (typst-renderer) ,@app-args)
     (with-application (*app*) ,@body)))

(defmacro with-fake-pdf (() &body body)
  `(with-test-app ()
     (with-application (*app*) ,@body)))

(defun refusal-of (thunk)
  "Values the code and the field errors THUNK fails with, as (path . message
in English) pairs, or NIL when it does not fail."
  (handler-case (progn (funcall thunk) nil)
    (operation-error (e)
      (values (json-name-of (operation-error-code e))
              (with-language (:source)
                (mapcar (lambda (field) (cons (car field) (render-text (cdr field))))
                        (operation-error-fields e)))))))

(defun refused-on (field thunk)
  "The English message THUNK's invalid_input gives on FIELD, or NIL."
  (multiple-value-bind (code fields) (refusal-of thunk)
    (and (equal code "invalid_input") (cdr (assoc field fields :test #'string=)))))

;;; ------------------------------------------------------------------
;;; Reading a PDF with Poppler

(defvar *pdf-scratch* nil "The test run's own directory for PDFs it reads.")

(defun pdf-scratch ()
  (or *pdf-scratch*
      (setf *pdf-scratch*
            (let ((path (format nil "~apdf-tests-~a/" (namestring (uiop:temporary-directory))
                                (random-token-string 8))))
              (ensure-directories-exist path)
              path))))

(defun pdf-file (octets)
  "OCTETS written to a file of the scratch directory; its path."
  (let ((path (format nil "~adocument-~a.pdf" (pdf-scratch) (random-token-string 8))))
    (with-open-file (out path :direction :output :element-type '(unsigned-byte 8)
                              :if-exists :supersede)
      (write-sequence octets out))
    path))

(defun poppler (program &rest arguments)
  (uiop:run-program (cons program arguments) :output :string :error-output nil
                                             :external-format :utf-8))

(defun pdf-info (octets &rest options)
  (apply #'poppler "pdfinfo" (append options (list (pdf-file octets)))))

(defun pdf-pages (octets)
  "The text of each page of the PDF OCTETS, as pdftotext reads it, with
no-break spaces as spaces."
  (let ((text (substitute #\Space #\No-break_space
                          (poppler "pdftotext" "-layout" (pdf-file octets) "-"))))
    (butlast (uiop:split-string text :separator (string #\Page)))))

(defun page-count (octets)
  (let ((line (find-if (lambda (line) (uiop:string-prefix-p "Pages:" line))
                       (uiop:split-string (pdf-info octets) :separator '(#\Newline)))))
    (parse-integer (trim (subseq line 6)))))

(defun page-size (octets)
  "The first page's size line of pdfinfo, such as «595.276 x 841.89 pts (A4)»."
  (let ((line (find-if (lambda (line) (uiop:string-prefix-p "Page size:" line))
                       (uiop:split-string (pdf-info octets) :separator '(#\Newline)))))
    (trim (subseq line 10))))

(defun first-words (octets)
  "The words of the PDF's first page with their boxes, from pdftotext -bbox,
in reading order: a list of (WORD X-MIN Y-MIN X-MAX Y-MAX)."
  (let ((html (poppler "pdftotext" "-bbox" "-f" "1" "-l" "1" (pdf-file octets) "-"))
        (words '()))
    (cl-ppcre:do-register-groups (x-min y-min x-max y-max word)
        ((concatenate 'string "<word xMin=\"([0-9.]+)\" yMin=\"([0-9.]+)\" "
                      "xMax=\"([0-9.]+)\" yMax=\"([0-9.]+)\">([^<]*)</word>")
         html)
      (push (list word (read-number x-min) (read-number y-min) (read-number x-max)
                  (read-number y-max))
            words))
    (nreverse words)))

(defun read-number (text)
  (let ((*read-default-float-format* 'double-float))
    (coerce (let ((*read-eval* nil)) (read-from-string text)) 'double-float)))

(defun mm (millimetres) (* millimetres (/ 72 25.4d0)))

(defun near-p (a b tolerance) (<= (abs (- a b)) tolerance))

;;; ------------------------------------------------------------------
;;; 1, 6: the tree and its refusals

(test every-element-of-a-document-is-taken
  (with-fake-pdf ()
    (let ((tree `((:h1 "En") (:h2 "To") (:h3 "Tre")
                  (:p "Avsnitt med " (:strong "fet") ", " (:em "kursiv") " og "
                      (:span (:@ :style "color: #c00") "rød") (:br) "ny linje")
                  (:div (:@ :style "text-align: center") "Midt")
                  (:ul (:li "a") (:li "b")) (:ol (:li "c"))
                  (:p (:a (:@ :href "https://example.no/x") "lenke") " og "
                      (:a (:@ :href "/saker/1") "sti"))
                  (:hr)
                  (:table (:caption "Tabell")
                          (:thead (:tr (:th (:@ :scope "col") "A") (:th "B")))
                          (:tbody (:tr (:td (:@ :rowspan 2) "1") (:td "2")) (:tr (:td "3")))
                          (:tfoot (:tr (:td (:@ :colspan 2) "Sum")))))))
      (is (equal "%PDF-" (map 'string #'code-char (subseq (make-pdf tree :title "Alt") 0 5)))))))

(test what-a-mail-refuses-a-document-refuses-and-img-too
  (with-fake-pdf ()
    (flet ((refused (tree) (refused-on "document" (lambda () (make-pdf tree :title "T")))))
      (is (equal "<img> cannot be used in a PDF yet"
                 (refused '(:p (:img (:@ :src "https://example.no/a.png"))))))
      (is (equal "<script> cannot be used in a PDF" (refused '(:script "x"))))
      (is (equal "the attribute onclick cannot be used on <p> in a PDF"
                 (refused '(:p (:@ :onclick "x") "y"))))
      (is (equal "the style “position” cannot be used in a PDF"
                 (refused '(:p (:@ :style "position: absolute") "y"))))
      (is (equal "the value “url(x)” for color cannot be used in a PDF"
                 (refused '(:p (:@ :style "color: url(x)") "y"))))
      (is (search "must start with https://" (refused '(:a (:@ :href "javascript:alert(1)") "x"))))
      (is (search "is not a node" (refused (list :p #\x))))
      (is (search "is not a node" (refused '(:p . "x"))))
      (is (equal "<tr> holds <th> and <td> cells, not “x”" (refused '(:table (:tr "x")))))
      (is (equal "<table> holds rows, not “x”" (refused '(:table "x"))))
      (is (equal "<ul> holds <li> items, not “x”" (refused '(:ul "x"))))
      (is (search "lacks" (refused '(:p (:@ :style "color") "y")))))))

(test a-document-past-its-limits-is-refused-before-any-renderer-runs
  (with-test-app (:pdf-renderer (make-instance 'tun.pdf:typst-pdf-renderer
                                               :program "/nonexistent/typst" :fonts "/nonexistent"))
    (with-application (*app*)
      (let ((deep "x"))
        (dotimes (i 51) (setf deep (list :div deep)))
        (is (equal "a document cannot be deeper than 50 levels"
                   (refused-on "document" (lambda () (make-pdf deep :title "T"))))))
      (is (equal "a document cannot hold more than 25000 elements"
                 (refused-on "document"
                             (lambda () (make-pdf (loop repeat 25001 collect '(:br)) :title "T")))))
      (is (equal "a document cannot hold more than 1000000 characters of text"
                 (refused-on "footer"
                             (lambda ()
                               (make-pdf "x" :title "T"
                                             :footer (make-string 1000001 :initial-element #\a))))))
      (is (equal "must be filled in" (refused-on "title" (lambda () (make-pdf "x")))))
      (is (equal "can have at most 200 characters"
                 (refused-on "title"
                             (lambda ()
                               (make-pdf "x" :title (make-string 201 :initial-element #\t))))))
      (is (equal "is :a4 or :letter"
                 (refused-on "paper" (lambda () (make-pdf "x" :title "T" :paper :a3)))))
      (dolist (margins '(4 51 (10 10 10) (10 10 10 60) "20"))
        (is (equal "are millimetres from 5 to 50: one number, or a list of four"
                   (refused-on "margins" (lambda () (make-pdf "x" :title "T" :margins margins))))
            "margins ~s" margins))
      (is (search "is not a node"
                  (refused-on "header" (lambda () (make-pdf "x" :title "T" :header #\h))))))))

;;; ------------------------------------------------------------------
;;; 7: the document's data

(defun data-of (tree &rest keys)
  (with-fake-pdf () (apply #'tun.pdf:document-data tree :title "T" keys)))

(defparameter +paragraph-style+
  (concatenate 'string "text-align: right; font-weight: bold; font-style: italic; "
               "font-size: 48px; color: #c00; padding: 4px"))

(defparameter +cell-style+ "width: 30%; vertical-align: middle; background-color: #eeeeee")

(test the-document-carries-what-the-pdf-draws-of-a-style
  (let* ((data (data-of `((:p (:@ :style ,+paragraph-style+) "p")
                          (:table (:tr (:td (:@ :style ,+cell-style+) "a")
                                       (:td (:@ :style "width: 120px") "b")
                                       (:td "c") (:td "d"))))))
         (body (jget data "body"))
         (style (jget (aref body 0) "style"))
         (table (aref body 1))
         (cell (aref (aref (jget table "body") 0) 0)))
    (is (equal "right" (jget style "align")))
    (is (equal "bold" (jget style "weight")))
    (is (eq t (jget style "italic")))
    (is (= 36 (jget style "size")) "48 px is clamped to 36 pt")
    (is (equal "#cc0000" (jget style "color")))
    (is (= 5 (hash-table-count style))
        "padding is not drawn: ~s" (alexandria:hash-table-keys style))
    (is (equal "middle" (jget (jget cell "style") "valign")))
    (is (equal "#eeeeee" (jget (jget cell "style") "fill")))
    (let ((widths (jget table "widths")))
      (is (= 30 (jget (aref widths 0) "pct")))
      (is (= 90 (jget (aref widths 1) "pt")))
      (is (= 1 (jget (aref widths 2) "fr")) "the first column without a width takes the rest")
      (is (eq t (jget (aref widths 3) "auto"))))
    (let ((later (data-of '(:p (:@ :style "font-size: 9pt; font-size: 16px") "x"))))
      (is (= 12 (jget (jget (aref (jget later "body") 0) "style") "size"))
          "the later declaration wins, 16 px is 12 pt"))))

(test a-tables-rows-go-to-its-head-body-and-foot
  (let* ((table (aref (jget (data-of (invoice-tree 3)) "body") 2)))
    (is (= 1 (length (jget table "head"))))
    (is (= 3 (length (jget table "body"))))
    (is (= 1 (length (jget table "foot"))))
    (is (= 5 (length (jget table "widths"))))
    (is (= 4 (jget (aref (aref (jget table "foot") 0) 0) "colspan")))
    (is (= 1 (jget (aref (jget table "widths") 1) "fr")) "the description takes the rest")))

(test the-document-is-in-the-current-language-with-its-page-label
  (with-fake-pdf ()
    (with-language ("nb")
      (let ((data (tun.pdf:document-data "x" :title "T")))
        (is (equal "nb" (jget data "lang")))
        (is (equal "Side {page} av {pages}" (jget data "page_label")))))
    (with-language ("en")
      (is (equal "Page {page} of {pages}"
                 (jget (tun.pdf:document-data "x" :title "T") "page_label"))))
    (is (eq :null (jget (tun.pdf:document-data "x" :title "T" :page-numbers nil) "page_label")))
    (is (equal "us-letter" (jget (tun.pdf:document-data "x" :title "T" :paper :letter) "paper")))))

;;; ------------------------------------------------------------------
;;; 8: pdf-text

(test pdf-text-says-what-the-document-says
  (with-fake-pdf ()
    (let ((text (pdf-text (invoice-tree 2) :header "Utleie AS"
                                           :footer '(:p "Betal innen 30 dager"))))
      (is (uiop:string-prefix-p "Utleie AS" text))
      (is (search "Faktura 10042" text))
      (is (search "Nr | Beskrivelse | Antall | Pris | Beløp" text))
      (is (search (format nil "1 | ~a | 2 | 1 250,00 kr | 1 250,00 kr" (invoice-line 1)) text))
      (is (search "Å betale | Sum alt" text))
      (is (uiop:string-suffix-p text "Betal innen 30 dager")))
    (is (equal "<img> cannot be used in a PDF yet"
               (refused-on "document" (lambda () (pdf-text '(:img))))))))

;;; ------------------------------------------------------------------
;;; 9, 16: the fake, storing and mailing

(define-operation pdf-test-attach ((id :type (id file-note) :required t)
                                   (name :type string) (bytes :type string))
    (:entity file-note :kind :update :policy :employee :title "Attach a made PDF (test)")
  (let* ((note (fetch! 'file-note id))
         (octets (cond ((null bytes) (make-pdf (invoice-tree 3) :title "Faktura"))
                       ((string= bytes "empty") (make-array 0 :element-type '(unsigned-byte 8)))
                       (t (sb-ext:string-to-octets bytes :external-format :utf-8))))
         (file (list :filename (or name "faktura.pdf") :content octets)))
    (attach-files note (list file))
    (send-mail :to "ola@example.no" :subject "Faktura" :text "Fakturaen ligger ved."
               :attachments (list file))
    note))

(test a-test-makes-a-pdf-with-the-fake-and-stores-and-mails-it
  (with-test-server (port)
    (is (typep (application-pdf-renderer *app*) 'tun.pdf:fake-pdf-renderer))
    (let* ((id (jget (call-ok "file_notes_create" "employee:anna" "title" "Faktura") "id"))
           (files (progn (call-ok "pdf_test_attach" "employee:anna" "id" id)
                         (jget (call-ok "attachments_list" "employee:anna"
                                        "entity" "file_note" "record_id" id)
                               "items")))
           (file (aref files 0)))
      (is (equal "application/pdf" (jget file "content_type")))
      (is (equal "faktura.pdf" (jget file "filename")))
      (multiple-value-bind (status body headers) (fetch-file port (jget file "url")
                                                             :actor "employee:anna")
        (is (= 200 status))
        (is (equal "application/pdf" (response-header :content-type headers)))
        (is (uiop:string-prefix-p "attachment" (response-header :content-disposition headers)))
        (let ((pages (pdf-pages body)))
          (is (= 1 (length pages)))
          (is (search (invoice-line 3) (first pages)) "the fake's PDF shows the document's text")))
      (let ((mail (aref (jget (call-ok "mail_list" "admin:ada") "items") 0)))
        (is (equal "faktura.pdf" (jget (aref (jget mail "attachments") 0) "filename")))
        (is (equal (sha256-of (nth-value 1 (fetch-file port (jget file "url")
                                                       :actor "employee:anna")))
                   (jget (aref (jget mail "attachments") 0) "sha256"))
            "the mail carries the same bytes as the record")))))

(test bytes-attach-files-does-not-take-are-refused-on-their-place
  (with-test-app ()
    (let ((id (jget (call-ok "file_notes_create" "employee:anna" "title" "Faktura") "id")))
      (multiple-value-bind (json code) (call "pdf_test_attach" "employee:anna" "id" id
                                             "name" "notat.txt" "bytes" "bare tekst")
        (is (equal "invalid_input" code))
        (is (search "files[0]" (to-json-string json))))
      (multiple-value-bind (json code) (call "pdf_test_attach" "employee:anna" "id" id
                                             "name" (make-string 256 :initial-element #\n)
                                             "bytes" "%PDF-1.4")
        (declare (ignore json))
        (is (equal "invalid_input" code)))
      (is (zerop (length (jget (call-ok "attachments_list" "employee:anna"
                                        "entity" "file_note" "record_id" id)
                               "items"))))))
  (with-test-app ()
    (let ((id (jget (call-ok "file_notes_create" "employee:anna" "title" "Tom") "id")))
      (multiple-value-bind (json code) (call "pdf_test_attach" "employee:anna" "id" id
                                             "name" "tom.pdf" "bytes" "empty")
        (is (equal "invalid_input" code))
        (is (search "The file is empty." (to-json-string json)))))))

;;; ------------------------------------------------------------------
;;; 10: the renderer chosen

(defmacro with-environment ((&rest names-and-values) &body body)
  "Run BODY with the environment variables NAMES-AND-VALUES set, NIL unset,
and as they were after."
  (let ((saved (gensym "SAVED")))
    `(let ((,saved (list ,@(loop for (name) on names-and-values by #'cddr
                                 collect `(cons ,name (uiop:getenv ,name))))))
       (unwind-protect
            (progn ,@(loop for (name value) on names-and-values by #'cddr
                           collect `(set-environment ,name ,value))
                   ,@body)
         (loop for (name . value) in ,saved do (set-environment name value))))))

(defun set-environment (name value)
  "Set the environment variable NAME to VALUE; NIL sets it empty, which the
PDF renderer's choice reads as unset."
  (setf (uiop:getenv name) (or value "")))

(test the-renderer-is-the-fake-in-tests-and-typst-where-the-environment-names-it
  (let ((typst (uiop:getenv "TUN_TYPST")) (fonts (uiop:getenv "TUN_PDF_FONTS")))
    (is (typep (tun.pdf:environment-pdf-renderer) 'tun.pdf:typst-pdf-renderer))
    (is (typep (tun.pdf:default-pdf-renderer :test t) 'tun.pdf:fake-pdf-renderer))
    (with-environment ("TUN_TYPST" nil)
      (is (null (tun.pdf:environment-pdf-renderer)))
      (is (null (tun.pdf:default-pdf-renderer)))
      (is (typep (tun.pdf:default-pdf-renderer :test t) 'tun.pdf:fake-pdf-renderer))
      (with-test-app (:test-clock nil)
        (is (null (application-pdf-renderer *app*)))
        (with-application (*app*)
          (let ((log (make-string-output-stream)))
            (is (equal "unavailable"
                       (let ((*standard-output* log))
                         (refusal-of (lambda () (make-pdf "x" :title "Ingen Typst"))))))
            (is (search "«Ingen Typst» not made: this server names no Typst"
                        (get-output-stream-string log)))))))
    (with-environment ("TUN_TYPST" typst "TUN_PDF_FONTS" fonts)
      (with-test-app (:test-clock nil)
        (is (typep (application-pdf-renderer *app*) 'tun.pdf:typst-pdf-renderer))))))

;;; ------------------------------------------------------------------
;;; 1 to 5: with Typst

(test typst-makes-a-pdf-with-its-title-and-language
  (with-typst ()
    (with-language ("nb")
      (let* ((pdf (make-pdf '(:p "Hei") :title "Faktura 7 – Ærlig"))
             (info (pdf-info pdf))
             (meta (pdf-info pdf "-meta")))
        (is (search "Title:           Faktura 7 – Ærlig" info))
        (is (search "<rdf:li>nb</rdf:li>" meta) "the language in the metadata")))))

(test typst-makes-a4-and-letter-with-the-margins-asked
  (with-typst ()
    (is (search "595.276 x 841.89 pts" (page-size (make-pdf "Ord" :title "A4"))))
    (is (search "612 x 792 pts" (page-size (make-pdf "Ord" :title "Letter" :paper :letter))))
    (destructuring-bind (word x y &rest box)
        (first (first-words (make-pdf "Ord" :title "M" :margins 30)))
      (declare (ignore box))
      (is (equal "Ord" word))
      (is (near-p x (mm 30) 2) "left ~,1f pt, not ~,1f" x (mm 30))
      (is (near-p y (mm 30) 3) "top ~,1f pt, not ~,1f" y (mm 30)))
    (destructuring-bind (word x y &rest box)
        (first (first-words (make-pdf "Ord" :title "M" :margins '(10 20 30 40))))
      (declare (ignore word box))
      (is (near-p x (mm 40) 2) "left ~,1f pt, not ~,1f" x (mm 40))
      (is (near-p y (mm 10) 3) "top ~,1f pt, not ~,1f" y (mm 10)))))

(test a-right-aligned-amount-ends-at-the-texts-right-edge
  (with-typst ()
    (let* ((words (first-words (make-pdf (invoice-tree 1) :title "R" :margins 20)))
           (amount (find "Beløp" words :key #'first :test #'string=)))
      (is (near-p (fourth amount) (- 595.276 (mm 20)) 2.5)
          "the heading Beløp ends at ~,1f pt" (fourth amount)))))

(defun count-in (text part)
  (let ((count 0) (start 0))
    (loop for found = (search part text :start2 start)
          while found do (incf count) (setf start (1+ found)))
    count))

(test a-200-line-table-breaks-across-pages-with-its-header-on-each
  (with-typst ()
    (with-language ("nb")
      (let* ((pdf (make-pdf (invoice-tree 200) :title "Faktura 10042"
                                                :header "Utleie AS, org.nr. 999 999 999"
                                                :footer "Betal til konto 1234.56.78903"))
             (pages (pdf-pages pdf))
             (count (length pages))
             (all (format nil "~{~a~%~}" pages)))
        (is (= count (page-count pdf)))
        (is (< 1 count) "~d pages" count)
        (loop for page in pages
              for number from 1
              do (is (cl-ppcre:scan "Nr\\s+Beskrivelse\\s+Antall\\s+Pris\\s+Beløp" page)
                     "the header on page ~d" number)
                 (is (search (format nil "Side ~d av ~d" number count) page)
                     "«Side ~d av ~d» on page ~d" number count number)
                 (is (search "Utleie AS, org.nr. 999 999 999" page)
                     "the header text on page ~d" number)
                 (is (search "Betal til konto 1234.56.78903" page) "the footer on page ~d" number))
        (loop for i from 1 to 200
              do (is (= 1 (count-in all (concatenate 'string (invoice-line i) " ")))
                     "line ~d once, whole" i))
        (is (= 1 (count-in all "Å betale")))
        (is (search "Å betale" (car (last pages))) "the totals on the last page")))))

(test page-numbers-are-in-the-documents-language-or-left-out
  (with-typst ()
    (with-language ("en")
      (let ((pages (pdf-pages (make-pdf (invoice-tree 80) :title "Invoice"))))
        (is (< 1 (length pages)))
        (loop for page in pages
              for number from 1
              do (is (search (format nil "Page ~d of ~d" number (length pages)) page)
                     "«Page ~d of ~d» on page ~d" number (length pages) number))))
    (let ((pages (pdf-pages (make-pdf "Uten" :title "Uten" :page-numbers nil))))
      (is (not (search "1" (first pages)))))))

(test money-and-dates-read-in-the-pdf-as-tun-writes-them
  (with-typst ()
    (with-language ("nb")
      (let* ((amount (money-text 125000 :currency "NOK"))
             (date (date-text "2026-11-16"))
             (tree `((:p ,(format nil "Fakturadato: ~a" date))
                     (:table (:tr (:td "Sum") (:td (:@ :style "text-align: right") ,amount)))))
             (page (first (pdf-pages (make-pdf tree :title "Penger")))))
        (is (equal "1 250,00 kr" (substitute #\Space #\No-break_space amount)))
        (is (search "Fakturadato: 16.11.2026" page))
        (is (search "1 250,00 kr" page))))))

(test a-letter-no-font-has-leaves-a-box-and-the-pdf-is-made
  (with-typst ()
    (let ((page (first (pdf-pages (make-pdf "Før 发票 og 🎉 etter" :title "Tegn")))))
      (is (search "Før" page))
      (is (search "etter" page)))))

;;; ------------------------------------------------------------------
;;; 11: data, never code

(defparameter +hostile-strings+
  '("#read(\"/etc/hostname\")" "#import \"@preview/cetz:0.3.0\"" "] #panic(\"x\") ["
    "$x$ *b* _e_" "#sys.inputs" "\"}]); #eval(\"1\")" "#read(\"document.typ\")"
    "#read(\"data.json\")" "#{ let x = 1 }"))

(test hostile-text-is-printed-as-it-is-and-reads-nothing
  (with-typst ()
    (let* ((pdf (make-pdf `((:p "Start")
                            ,@(mapcar (lambda (text) `(:p ,text)) +hostile-strings+)
                            (:table (:tr (:td ,(first +hostile-strings+)))))
                          :title "#read(\"document.typ\")"))
           (text (format nil "~{~a~}" (pdf-pages pdf))))
      (dolist (hostile +hostile-strings+)
        (is (search hostile text) "printed as it is: ~a" hostile))
      (is (not (search "render-table" text)) "nothing of the layout file")
      (is (not (search "page_label" text)) "nothing of the data file"))))

(test the-layout-reads-the-data-and-nothing-else
  (let ((layout (uiop:read-file-string tun.pdf:+layout-file+)))
    (dolist (word '("eval(" "import" "include" "read(" "plugin("))
      (is (not (search word layout)) "the layout holds no ~a" word))
    (is (= 1 (count-in layout "json(")))
    (is (search "json(\"data.json\")" layout))))

;;; ------------------------------------------------------------------
;;; 12, 13: Typst's environment, its directory, and failures

(defun program-path (name)
  "The absolute path of the program NAME on the test's PATH: a script run
as Typst has no PATH."
  (trim (uiop:run-program (list "sh" "-c" (format nil "command -v ~a" name)) :output :string)))

(defun script-renderer (body &key (timeout 30))
  "A renderer whose program is a shell script running BODY."
  (let ((path (format nil "~arenderer-~a.sh" (pdf-scratch) (random-token-string 8))))
    (with-open-file (out path :direction :output :if-exists :supersede)
      (format out "#!/bin/sh~%~a~%" body))
    (uiop:run-program (list "chmod" "700" path))
    (make-instance 'tun.pdf:typst-pdf-renderer :program path :fonts "/nonexistent"
                                               :timeout timeout)))

(defun own-directories (directory)
  "The document directories left in DIRECTORY."
  (remove-if-not (lambda (path) (search "tun-pdf-" (namestring path)))
                 (uiop:subdirectories directory)))

(defmacro with-own-temporary-directory ((directory) &body body)
  "Run BODY with the temporary directory a fresh one, DIRECTORY."
  `(let* ((,directory (format nil "~atemporary-~a/" (pdf-scratch) (random-token-string 8)))
          (uiop:*temporary-directory* (pathname ,directory)))
     (ensure-directories-exist ,directory)
     ,@body))

(test typst-sees-its-directory-and-nothing-of-the-servers-environment
  (let ((report (format nil "~aenvironment-~a.txt" (pdf-scratch) (random-token-string 8))))
    (with-environment ("SECRET_FOR_PDF_TEST" "hemmelig" "DATABASE_URL" "postgresql://x:y@h/d")
      (with-test-app (:pdf-renderer (script-renderer
                                     (format nil "{ ~a; echo \"mode=$(~a -c %a \"$HOME\")\"; ~
                                                  echo \"pwd=$(pwd)/\"; } > ~a; exit 1"
                                             (program-path "env") (program-path "stat") report)))
        (with-application (*app*)
          (let ((*standard-output* (make-broadcast-stream)))
            (is (equal "unavailable" (refusal-of (lambda () (make-pdf "x" :title "Miljø")))))))))
    (let* ((lines (uiop:read-file-lines report))
           (names (loop for line in lines
                        for equals = (position #\= line)
                        when equals collect (subseq line 0 equals)))
           ;; The script's shell adds these itself.
           (own '("PWD" "SHLVL" "_" "OLDPWD" "mode" "pwd"))
           (home (subseq (find-if (lambda (line) (uiop:string-prefix-p "HOME=" line)) lines) 5)))
      (is (null (set-difference (set-difference names own :test #'string=)
                                '("HOME" "TMPDIR" "LANG") :test #'string=))
          "only HOME, TMPDIR and LANG: ~s" names)
      (is (member "HOME" names :test #'string=))
      (is (member (format nil "TMPDIR=~a" home) lines :test #'string=) "TMPDIR is the directory")
      (is (member (format nil "pwd=~a" home) lines :test #'string=) "it runs in its directory")
      (is (member "mode=700" lines :test #'string=) "the directory is the server's only")
      (is (notany (lambda (line) (search "hemmelig" line)) lines)))))

(test no-pdf-fails-unavailable-and-leaves-no-directory
  (with-own-temporary-directory (directory)
    (flet ((fails (renderer)
             (with-test-app (:pdf-renderer renderer)
               (with-application (*app*)
                 (let ((*standard-output* (make-broadcast-stream)))
                   (refusal-of (lambda () (make-pdf "x" :title "Feil"))))))))
      (is (equal "unavailable"
                 (fails (make-instance 'tun.pdf:typst-pdf-renderer :program "/nonexistent/typst"
                                                                   :fonts "/nonexistent"))))
      (is (equal "unavailable" (fails (script-renderer "exit 1"))))
      (is (equal "unavailable" (fails (script-renderer "exit 0"))) "no PDF written")
      (is (equal "unavailable" (fails (script-renderer "echo nope > document.pdf"))) "not a PDF")
      (is-within-seconds (:why "a renderer past its time is stopped" :under 3)
        (is (equal "unavailable"
                   (fails (script-renderer (format nil "~a 30" (program-path "sleep"))
                                           :timeout 1)))))
      (is (null (own-directories directory)) "no directory left: ~s" (own-directories directory)))))

(test typst-runs-as-a-step-of-the-trace
  (with-typst ()
    (let ((*request-id* (new-id "req")))
      (with-request-record (:id *request-id* :application *app*)
        (make-pdf "x" :title "Spor"))
      (let ((step (external-step *request-id*)))
        (is (uiop:string-prefix-p "typst compile --root ." (jget step "name")) "~s" step)
        (is (equal "exit 0" (jget step "detail")))))))

;;; ------------------------------------------------------------------
;;; 17: speed

(test a-200-line-document-is-fast
  (let ((tree (invoice-tree 200)))
    (with-typst ()
      (is-fast (:why "make-pdf of 200 lines with Typst, its processor time included"
                :limit-ms 1000 :runs 5)
        (make-pdf tree :title "Faktura")))
    (with-fake-pdf ()
      (is-fast (:why "pdf-text of 200 lines" :limit-ms 150)
        (pdf-text tree))
      (is-fast (:why "make-pdf of 200 lines with the fake" :limit-ms 150)
        (make-pdf tree :title "Faktura")))))

(test is-fast-counts-the-programs-a-test-ran
  (let ((measured (measure-speed (lambda ()
                                   (uiop:run-program
                                    '("python3" "-I" "-c"
                                      "import time
while time.process_time() < 0.3: pass")))
                                 :runs 3)))
    (is (<= 250 (measurement-milliseconds measured))
        "a program that burns 300 ms measures ~,1f ms" (measurement-milliseconds measured))))

(define-operation pdf-test-language ()
    (:kind :read :policy :employee :title "A document's language (test)")
  (let ((data (tun.pdf:document-data "x" :title "T")))
    (jobj "lang" (jget data "lang") "label" (jget data "page_label")
          "page" (first (pdf-pages (make-pdf "x" :title "T"))))))

(test a-document-is-in-the-tenants-language
  (with-test-app (:pdf-renderer (typst-renderer))
    (call-ok "settings_set" "admin:a" "key" "locale.language" "value" "nb")
    (let ((json (call-ok "pdf_test_language" "employee:anna")))
      (is (equal "nb" (jget json "lang")))
      (is (equal "Side {page} av {pages}" (jget json "label")))
      (is (search "Side 1 av 1" (jget json "page"))))))
