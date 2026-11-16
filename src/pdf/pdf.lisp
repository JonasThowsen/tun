;;;; pdf/pdf.lisp -- documents as PDF (spec/pdf.md).
;;;;
;;;; MAKE-PDF takes a document described as nodes, in the grammar of a
;;;; mail's HTML (spec/mail.md 2.1), checks it, writes it as the document's
;;;; data, and asks the application's PDF renderer for the bytes.  The
;;;; renderer is a port: RENDER-PDF, whose methods are the adapters, Typst
;;;; in typst.lisp and the fake in fake.lisp.  PDF-TEXT gives what a
;;;; document says as text, made as a mail's text part is, for tests and
;;;; previews.
;;;;
;;;; Checking refuses rather than drops, as a mail's does: the tree is the
;;;; client's code, and what a person typed is a string in it, which the
;;;; renderer shows as text and never reads as anything else.

(defpackage #:tun.pdf
  (:use #:cl #:tun.core)
  (:import-from #:tun.html #:node-parts)
  (:import-from #:tun.mail #:proper-list-p #:shown #:scheme-p #:+style-value+
                #:+mail-style-properties+ #:tree-text)
  (:import-from #:tun.outbound #:run-own-program #:program-failure)
  (:export #:make-pdf #:pdf-text #:render-pdf #:pdf-failure
           #:fake-pdf-renderer #:typst-pdf-renderer #:typst-program #:typst-fonts
           #:typst-timeout #:environment-pdf-renderer #:default-pdf-renderer
           #:document-data #:+most-document-depth+ #:+most-document-elements+
           #:+most-document-characters+ #:+layout-file+))

(in-package #:tun.pdf)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; The port

(defgeneric render-pdf (renderer document)
  (:documentation "The bytes of the PDF of DOCUMENT, the checked document as
JSON (spec/pdf.md 3.1), made by RENDERER: a vector of octets that starts
with %PDF-.  A renderer that gives no PDF signals PDF-FAILURE with the
reason, which MAKE-PDF logs; it never signals anything else for a document
that was checked."))

(define-condition pdf-failure (error)
  ((reason :initarg :reason :reader pdf-failure-reason
           :documentation "Why no PDF came, for the server's log: English, never shown
to the person whose operation failed."))
  (:report (lambda (c s) (write-string (pdf-failure-reason c) s)))
  (:documentation "A renderer gave no PDF; MAKE-PDF fails the operation with
unavailable and logs the reason."))

;;; ------------------------------------------------------------------
;;; Limits (spec/pdf.md 2.3)

(defparameter +most-document-depth+ 50
  "The deepest a document's tree may nest.  Typst reads the document as
JSON, where each level is two, and refuses past 128.")

(defparameter +most-document-elements+ 25000
  "The most elements a document holds, its header and footer included:
about 2 500 lines of a table.")

(defparameter +most-document-characters+ 1000000
  "The most characters of text a document holds, its header and footer
included.")

(defparameter +most-title-characters+ 200 "The longest a document's title may be.")

(defparameter +most-margin-mm+ 50 "The widest margin, in millimetres.")
(defparameter +least-margin-mm+ 5 "The narrowest margin, in millimetres.")
(defparameter +default-margin-mm+ 20 "The margin a document gets when it names none.")

;;; ------------------------------------------------------------------
;;; Refusals

(define-condition document-refused (error)
  ((reason :initarg :reason :reader document-refused-reason
           :documentation "A TEXT, written in the language of the place it is shown."))
  (:report (lambda (c s) (write-string (render-text (document-refused-reason c)) s)))
  (:documentation "A document's tree holds something a PDF does not take; the
reason says what."))

(defmacro refuse-tree (control &rest arguments)
  "Refuse the tree, the reason the literal CONTROL with ARGUMENTS."
  `(error 'document-refused :reason (deferred-tr ,control ,@arguments)))

;;; ------------------------------------------------------------------
;;; Checking the tree (spec/pdf.md 2.1): a mail's grammar and allow-list,
;;; but for images

(defparameter +document-elements+
  '("a" "p" "h1" "h2" "h3" "ul" "ol" "li" "strong" "em" "br" "hr" "span" "div"
    "table" "caption" "thead" "tbody" "tfoot" "tr" "th" "td")
  "The elements a document's tree may hold: a mail's, but for img.")

(defparameter +document-attributes+
  '((t "style" "title" "lang" "dir")
    ("a" "href")
    ("th" "colspan" "rowspan" "scope")
    ("td" "colspan" "rowspan" "scope"))
  "The attributes each element may carry, as in a mail: an element's name, or
T for every element, then the attributes' names.")

(defvar *elements* 0 "How many elements the document being checked holds so far.")
(defvar *characters* 0 "How many characters of text it holds so far.")

(defun count-element ()
  (when (> (incf *elements*) +most-document-elements+)
    (refuse-tree "a document cannot hold more than ~d elements" +most-document-elements+)))

(defun count-characters (text)
  (when (> (incf *characters* (length text)) +most-document-characters+)
    (refuse-tree "a document cannot hold more than ~d characters of text"
                 +most-document-characters+)))

(defun check-url-characters (url)
  "Refuse URL, a link's href, when it holds a space, a control character or
a backslash, as a mail does: what is checked is what is written."
  (when (find-if (lambda (char)
                   (or (<= (char-code char) 32) (<= 127 (char-code char) 160) (char= char #\\)))
                 url)
    (refuse-tree "href on <a> cannot hold spaces, control characters or \\ in a PDF: “~a”"
                 (shown url))))

(defun document-link (url)
  "The href URL as the PDF links it: a whole link as given, or a path made
whole with the server's public URL, as in a mail (spec/mail.md 2.1)."
  (check-url-characters url)
  (cond ((some (lambda (scheme) (scheme-p scheme url)) '("https://" "http://" "mailto:"))
         url)
        ((and (plusp (length url)) (char= (char url 0) #\/)
              (not (and (> (length url) 1) (member (char url 1) '(#\/ #\\)))))
         (absolute-url url))
        (t (refuse-tree "the link “~a” must start with https://, http://, mailto: or /"
                        (shown url)))))

(defun ascii-lower-p (char)
  (or (char<= #\a char #\z) (char<= #\A char #\Z)))

(defun checked-declarations (text tag)
  "The declarations of TEXT, the style attribute of TAG, as (PROPERTY .
VALUE), the property in lower case; one outside a mail's list is refused."
  (loop for part in (cl-ppcre:split ";" text)
        for declaration = (trim part)
        unless (string= declaration "")
          collect (let ((colon (position #\: declaration)))
                    (unless colon
                      (refuse-tree "the style “~a” on <~a> lacks “:”" (shown declaration) tag))
                    (let ((property (trim (subseq declaration 0 colon)))
                          (value (trim (subseq declaration (1+ colon)))))
                      (unless (and (every (lambda (char) (or (ascii-lower-p char) (char= char #\-)))
                                          property)
                                   (member (string-downcase property) +mail-style-properties+
                                           :test #'string=))
                        (refuse-tree "the style “~a” cannot be used in a PDF" (shown property)))
                      (unless (cl-ppcre:scan +style-value+ value)
                        (refuse-tree "the value “~a” for ~(~a~) cannot be used in a PDF"
                                     (shown value) property))
                      (cons (string-downcase property) value)))))

(defun attribute-allowed-p (tag name)
  (some (lambda (entry)
          (and (or (eq (first entry) t) (string= (first entry) tag))
               (member name (rest entry) :test #'string=)))
        +document-attributes+))

(defun checked-attributes (tag attributes)
  "ATTRIBUTES, the property list of an element TAG, checked: a path link made
whole, a style's declarations checked and written again as checked."
  (unless (and (proper-list-p attributes) (evenp (length attributes)))
    (refuse-tree "(:@ …) on <~a> must have a name and a value for each attribute" tag))
  (loop for (key value) on attributes by #'cddr
        do (unless (keywordp key)
             (refuse-tree "~a on <~a> is not an attribute name; a name is a keyword, such as :href"
                          (shown key) tag))
        when value
          append (let ((name (string-downcase (symbol-name key))))
                   (unless (attribute-allowed-p tag name)
                     (refuse-tree "the attribute ~a cannot be used on <~a> in a PDF" name tag))
                   (unless (or (stringp value) (numberp value))
                     (refuse-tree "the attribute ~a on <~a> must be a text or a number, not ~a"
                                  name tag (shown value)))
                   (let ((text (princ-to-string value))
                         (key (intern (string-upcase name) "KEYWORD")))
                     (count-characters text)
                     (list key (cond ((string= name "href") (document-link text))
                                     ((string= name "style")
                                      (format nil "~{~a~^; ~}"
                                              (mapcar (lambda (declaration)
                                                        (format nil "~a: ~a" (car declaration)
                                                                (cdr declaration)))
                                                      (checked-declarations text tag))))
                                     (t text)))))))

(defun checked-element (element depth)
  "ELEMENT, (:tag [(:@ ...)] child...), checked; it is DEPTH levels into the
tree."
  (unless (proper-list-p element)
    (refuse-tree "“~a” is not a node: the list does not end" (shown element)))
  (when (eq (first element) :@)
    (refuse-tree "(:@ …) must come right after the tag: “~a”" (shown element)))
  (multiple-value-bind (tag attributes children) (node-parts element)
    (when (string= tag "img")
      (refuse-tree "<img> cannot be used in a PDF yet"))
    (unless (member tag +document-elements+ :test #'string=)
      (refuse-tree "<~a> cannot be used in a PDF" tag))
    (count-element)
    (let ((attributes (checked-attributes tag attributes)))
      `(,(first element) ,@(and attributes `((:@ ,@attributes)))
        ,@(mapcar (lambda (child) (checked-node child (1+ depth))) children)))))

(defun checked-node (node &optional (depth 0))
  "NODE, DEPTH levels into the tree, checked against the document's grammar
and allow-list; anything else is refused with DOCUMENT-REFUSED."
  (when (> depth +most-document-depth+)
    (refuse-tree "a document cannot be deeper than ~d levels" +most-document-depth+))
  (cond ((null node) nil)
        ((stringp node) (count-characters node) node)
        ((numberp node) node)
        ((and (consp node) (keywordp (first node))) (checked-element node depth))
        ((and (consp node) (proper-list-p node))
         (mapcar (lambda (child) (checked-node child (1+ depth))) node))
        (t (refuse-tree
            "“~a” is not a node: a node is a text, a number, a list or an element such as (:p …)"
            (shown node)))))

;;; ------------------------------------------------------------------
;;; Styles, read for the PDF (spec/pdf.md 2.1, «Style»)

(defun decimal-value (text)
  "TEXT, digits with at most one point, as a number, or NIL."
  (when (and (plusp (length text))
             (every (lambda (char) (or (digit-char-p char) (char= char #\.))) text)
             (<= (count #\. text) 1)
             (some #'digit-char-p text))
    (let* ((point (position #\. text))
           (whole (subseq text 0 (or point (length text))))
           (fraction (if point (subseq text (1+ point)) "")))
      (+ (if (string= whole "") 0 (parse-integer whole))
         (if (string= fraction "")
             0
             (/ (parse-integer fraction) (expt 10 (length fraction))))))))

(defun length-value (text)
  "TEXT, a number and a unit, as the number and the unit's keyword (:PX, :PT
or :PERCENT), or NIL."
  (let ((text (string-downcase (trim text))))
    (loop for (unit keyword) in '(("px" :px) ("pt" :pt) ("%" :percent))
          for end = (- (length text) (length unit))
          for number = (and (plusp end) (string= unit text :start2 end)
                            (decimal-value (subseq text 0 end)))
          when number
            return (values number keyword))))

(defun hex-colour (text)
  "TEXT as a colour #rrggbb, when it is #rgb or #rrggbb, else NIL."
  (let ((text (string-downcase (trim text))))
    (when (and (member (length text) '(4 7)) (char= (char text 0) #\#)
               (every (lambda (char) (digit-char-p char 16)) (subseq text 1)))
      (if (= (length text) 7)
          text
          (format nil "#~{~a~a~}"
                  (loop for char across (subseq text 1) append (list char char)))))))

(defun points (number)
  "NUMBER as a float JSON writes plainly, rounded to hundredths."
  (float (/ (round (* number 100)) 100) 1d0))

(defun style-entry (property value cell)
  "The JSON key and value the PDF applies for the declaration PROPERTY:
VALUE, or NIL when the PDF does not draw it.  CELL is true on a th or td."
  (let ((word (string-downcase (trim value))))
    (flet ((one-of (&rest words) (and (member word words :test #'string=) word)))
      (cond ((string= property "text-align")
             (let ((align (one-of "left" "right" "center")))
               (and align (list "align" align))))
            ((and cell (string= property "vertical-align"))
             (let ((align (one-of "top" "middle" "bottom")))
               (and align (list "valign" align))))
            ((string= property "font-weight")
             (cond ((one-of "bold" "bolder") (list "weight" "bold"))
                   ((one-of "normal") (list "weight" "regular"))
                   (t (let ((number (decimal-value word)))
                        (and number (integerp number) (<= 100 number 900)
                             (zerop (mod number 100))
                             (list "weight" number))))))
            ((string= property "font-style")
             (cond ((one-of "italic" "oblique") (list "italic" t))
                   ((one-of "normal") (list "italic" nil))))
            ((string= property "font-size")
             (multiple-value-bind (number unit) (length-value word)
               (let ((size (case unit (:px (* number 3/4)) (:pt number))))
                 (and size (list "size" (points (max 6 (min 36 size))))))))
            ((string= property "color")
             (let ((colour (hex-colour word))) (and colour (list "color" colour))))
            ((and cell (string= property "background-color"))
             (let ((colour (hex-colour word))) (and colour (list "fill" colour))))
            ((and cell (string= property "width"))
             (multiple-value-bind (number unit) (length-value word)
               (case unit
                 (:percent (and (< 0 number 100) (list "width" (jobj "pct" (points number)))))
                 (:px (list "width" (jobj "pt" (points (* number 3/4)))))
                 (:pt (list "width" (jobj "pt" (points number)))))))))))

(defun style-json (style cell)
  "The checked STYLE, an element's style text, as the JSON object of what
the PDF draws of it, later declarations winning; NIL when it draws nothing."
  (when style
    (let ((entries (jobj)))
      (dolist (part (cl-ppcre:split "; " style))
        (let ((colon (position #\: part)))
          (when colon
            (let ((entry (style-entry (subseq part 0 colon) (subseq part (1+ colon)) cell)))
              (when entry
                (setf (gethash (first entry) entries) (second entry)))))))
      (and (plusp (hash-table-count entries)) entries))))

;;; ------------------------------------------------------------------
;;; The checked tree as the document's data (spec/pdf.md 3.1)

(defun collapsed (text)
  "TEXT with each run of spaces and line breaks one space, as HTML shows it."
  (with-output-to-string (out)
    (let ((space nil))
      (loop for char across text
            do (if (member char '(#\Space #\Tab #\Newline #\Return #\Page))
                   (setf space t)
                   (progn
                     (when space (write-char #\Space out) (setf space nil))
                     (write-char char out))))
      (when space (write-char #\Space out)))))

(defun element-p (node)
  (and (consp node) (keywordp (first node))))

(defun tag-of (node)
  (and (element-p node) (node-parts node)))

(defun flat-children (children)
  "CHILDREN with the lists among them spliced in and NIL left out."
  (loop for child in children
        append (cond ((null child) '())
                     ((element-p child) (list child))
                     ((consp child) (flat-children child))
                     (t (list child)))))

(defun blank-text-p (node)
  (and (stringp node) (string= (trim node) "")))

(defun nodes-json (nodes)
  "NODES, checked, as a JSON array of the document's nodes."
  (coerce (loop for node in (flat-children nodes)
                for json = (node-json node)
                when json collect json)
          'vector))

(defun node-json (node)
  "NODE, checked, as the document's JSON: a string, or an element's object."
  (cond ((stringp node) (collapsed node))
        ((numberp node) (princ-to-string node))
        (t (multiple-value-bind (tag attributes children) (node-parts node)
             (cond ((string= tag "table") (table-json attributes children))
                   ((member tag '("ul" "ol") :test #'string=)
                    (element-json tag attributes (list-items tag children)))
                   (t (element-json tag attributes (nodes-json children))))))))

(defun element-json (tag attributes children &optional cell)
  (let ((json (jobj "tag" tag "c" children))
        (style (style-json (getf attributes :style) cell)))
    (when style (setf (gethash "style" json) style))
    (when (getf attributes :href) (setf (gethash "href" json) (getf attributes :href)))
    json))

(defun list-items (tag children)
  "The items of a list TAG, each an li; blank text between them is left out."
  (coerce (loop for child in (flat-children children)
                unless (blank-text-p child)
                  collect (if (equal (tag-of child) "li")
                              (node-json child)
                              (refuse-tree "<~a> holds <li> items, not “~a”" tag (shown child))))
          'vector))

(defun span-value (attributes key)
  "The colspan or rowspan KEY of ATTRIBUTES as a count from 1 to 1000."
  (let* ((text (getf attributes key))
         (number (and text (decimal-value (trim text)))))
    (if (and number (integerp number) (<= 1 number 1000)) number 1)))

(defun cell-json (cell)
  (multiple-value-bind (tag attributes children) (node-parts cell)
    (let ((json (element-json tag attributes (nodes-json children) t)))
      (setf (gethash "colspan" json) (span-value attributes :colspan)
            (gethash "rowspan" json) (span-value attributes :rowspan))
      json)))

(defun row-cells (row)
  "The cells of ROW, a tr, as JSON; anything but a cell and blank text is
refused."
  (loop for child in (flat-children (nth-value 2 (node-parts row)))
        unless (blank-text-p child)
          collect (if (member (tag-of child) '("th" "td") :test #'equal)
                      (cell-json child)
                      (refuse-tree "<tr> holds <th> and <td> cells, not “~a”" (shown child)))))

(defun section-rows (tag children)
  "The rows of a table's section TAG, as lists of cells' JSON."
  (loop for child in (flat-children children)
        unless (blank-text-p child)
          collect (if (equal (tag-of child) "tr")
                      (row-cells child)
                      (refuse-tree "<~a> holds rows, not “~a”" tag (shown child)))))

(defun column-count (rows)
  "How many columns ROWS fill, cells placed as HTML and Typst place them:
each in the first column of its row that a cell above does not span."
  (let ((taken (make-hash-table :test 'equal)) (most 0))
    (loop for row in rows
          for y from 0
          do (let ((x 0))
               (dolist (cell row)
                 (loop while (gethash (cons x y) taken) do (incf x))
                 (let ((columns (gethash "colspan" cell)) (lines (gethash "rowspan" cell)))
                   (dotimes (i columns)
                     (dotimes (j lines)
                       (setf (gethash (cons (+ x i) (+ y j)) taken) t)))
                   (incf x columns)
                   (setf most (max most x))))))
    (max most 1)))

(defun column-widths (first-row count)
  "The widths of COUNT columns: a first-row cell's own width, the first
column without one the width that is left, the others as wide as their
cells."
  (let ((given (make-array count :initial-element nil))
        (x 0))
    (dolist (cell first-row)
      (let ((style (gethash "style" cell)))
        (when (and style (= 1 (gethash "colspan" cell)) (< x count))
          (setf (aref given x) (gethash "width" style))))
      (incf x (gethash "colspan" cell)))
    (let ((rest-taken nil))
      (map 'vector (lambda (width)
                     (cond (width width)
                           ((not rest-taken) (setf rest-taken t) (jobj "fr" 1))
                           (t (jobj "auto" t))))
           given))))

(defun table-json (attributes children)
  "A table, checked, as the document's JSON: its caption, its rows in head,
body and foot, and its column widths."
  (let ((caption '()) (head '()) (body '()) (foot '()))
    (dolist (child (flat-children children))
      (let* ((tag (tag-of child))
             (inside (and tag (nth-value 2 (node-parts child)))))
        (cond ((blank-text-p child))
              ((equal tag "caption") (setf caption (append caption inside)))
              ((equal tag "thead") (setf head (append head (section-rows tag inside))))
              ((equal tag "tfoot") (setf foot (append foot (section-rows tag inside))))
              ((equal tag "tbody") (setf body (append body (section-rows tag inside))))
              ((equal tag "tr") (setf body (append body (list (row-cells child)))))
              (t (refuse-tree "<~a> holds rows, not “~a”" "table" (shown child))))))
    (let* ((rows (append head body foot))
           (count (column-count rows))
           (json (element-json "table" attributes #())))
      (setf (gethash "caption" json) (nodes-json caption)
            (gethash "head" json) (rows-json head)
            (gethash "body" json) (rows-json body)
            (gethash "foot" json) (rows-json foot)
            (gethash "widths" json) (column-widths (first rows) count))
      json)))

(defun rows-json (rows)
  (coerce (mapcar (lambda (row) (coerce row 'vector)) rows) 'vector))

;;; ------------------------------------------------------------------
;;; The document's arguments (spec/pdf.md 1)

(defun document-language ()
  "The language the document is written in: the current one, English for
source text."
  (let ((language (current-language)))
    (if (stringp language) language "en")))

(defun checked-part (tree field)
  "Values TREE checked and its nodes as the document's JSON, or NIL and an
empty array with an input error on FIELD."
  (handler-case (let ((checked (checked-node tree)))
                  (values checked (nodes-json (list checked))))
    (document-refused (refusal)
      (let ((reason (document-refused-reason refusal)))
        (apply #'input-error field (text-control reason) (text-args reason)))
      (values nil #()))))

(defun checked-title (title)
  (cond ((or (not (stringp title)) (string= (trim title) ""))
         (input-error "title" "must be filled in"))
        ((> (length title) +most-title-characters+)
         (input-error "title" "can have at most ~d characters" +most-title-characters+))
        (t title)))

(defun checked-paper (paper)
  (case paper
    (:a4 "a4")
    (:letter "us-letter")
    (t (input-error "paper" "is :a4 or :letter"))))

(defun checked-margins (margins)
  "MARGINS as the JSON of four margins in millimetres, or NIL with an input
error."
  (let ((four (cond ((realp margins) (list margins margins margins margins))
                    ((and (proper-list-p margins) (= 4 (length margins))) margins))))
    (if (and four (every (lambda (margin)
                           (and (realp margin) (<= +least-margin-mm+ margin +most-margin-mm+)))
                         four))
        (destructuring-bind (top right bottom left) four
          (jobj "top" (points top) "right" (points right)
                "bottom" (points bottom) "left" (points left)))
        (input-error "margins" "are millimetres from ~d to ~d: one number, or a list of four"
                     +least-margin-mm+ +most-margin-mm+))))

(defun page-label ()
  "The page numbers as the document's language writes them, {page} and
{pages} standing for the numbers Typst fills in."
  (tr "Page ~a of ~a" "{page}" "{pages}"))

(defun document-data (tree &key title (paper :a4) (margins +default-margin-mm+)
                                header footer (page-numbers t))
  "The document's data as RENDER-PDF takes it, checked as MAKE-PDF checks
it, and the checked trees of the body, the header and the footer as more
values.  A bad argument fails with invalid_input."
  (let ((*elements* 0) (*characters* 0))
    (values-list
     (collecting-input-errors
       (multiple-value-bind (body body-json) (checked-part tree "document")
         (multiple-value-bind (header header-json) (checked-part header "header")
           (multiple-value-bind (footer footer-json) (checked-part footer "footer")
             (let ((title (checked-title title))
                   (paper (checked-paper paper))
                   (margins (checked-margins margins)))
               (list (jobj "title" title "paper" paper "margin" margins
                           "lang" (document-language)
                           "page_label" (if page-numbers (page-label) :null)
                           "header" header-json "footer" footer-json "body" body-json)
                     body header footer)))))))))

;;; ------------------------------------------------------------------
;;; Making it

(defun default-pdf-renderer (&key test)
  "The renderer an application gets when it is given none (spec/pdf.md
3.1): the fake in a test, else Typst when the environment names it, else
NIL."
  (if test
      (make-instance 'fake-pdf-renderer)
      (environment-pdf-renderer)))

(defun environment-pdf-renderer ()
  "A Typst renderer when the environment names Typst and the fonts
(TUN_TYPST and TUN_PDF_FONTS), else NIL."
  (let ((program (uiop:getenv "TUN_TYPST"))
        (fonts (uiop:getenv "TUN_PDF_FONTS")))
    (and (plusp (length program)) (plusp (length fonts))
         (make-instance 'typst-pdf-renderer :program program :fonts fonts))))

(defun log-failure (title reason)
  (format t "~&tun: pdf «~a» not made: ~a~%" title reason)
  (finish-output))

(defun make-pdf (tree &key title (paper :a4) (margins +default-margin-mm+) header footer
                        (page-numbers t))
  "The bytes of a PDF of the document TREE, a node tree in a mail's grammar
but for images, titled TITLE (spec/pdf.md 1): a vector of octets.  PAPER is
:A4 or :LETTER; MARGINS millimetres, one number or a list of four (top,
right, bottom, left); HEADER and FOOTER node trees on every page;
PAGE-NUMBERS «Page 2 of 5» in the current language.  A bad argument fails
with invalid_input; a renderer that gives no PDF fails with unavailable,
the reason in the server's log."
  (let ((document (document-data tree :title title :paper paper :margins margins
                                      :header header :footer footer
                                      :page-numbers page-numbers))
        (renderer (and *application* (application-pdf-renderer *application*))))
    (handler-case
        (if renderer
            (render-pdf renderer document)
            (error 'pdf-failure :reason "this server names no Typst (TUN_TYPST and TUN_PDF_FONTS)"))
      (pdf-failure (failure)
        (log-failure title (pdf-failure-reason failure))
        (fail :unavailable "The PDF could not be made.")))))

(defun pdf-text (tree &key header footer)
  "What the document TREE says as text, its HEADER first and its FOOTER
last, made as a mail's text part is (spec/pdf.md 1): a block a paragraph, a
table's rows one a line with their cells separated by « | ».  Checks the
trees as MAKE-PDF does and makes no PDF."
  (multiple-value-bind (document body header footer)
      (document-data tree :title "text" :header header :footer footer)
    (declare (ignore document))
    (string-right-trim '(#\Newline)
                       (format nil "~{~a~^~%~%~}"
                               (remove "" (mapcar (lambda (tree) (trim (tree-text tree)))
                                                  (list header body footer))
                                       :test #'string=)))))
