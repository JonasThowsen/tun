;;;; tests/page-test.lisp -- page tests over HTTP (spec/testing.md 6): a
;;;; server in the test's own process on a copy of a scenario's records,
;;;; requests sent as a browser sends them, and a reader of what the answer
;;;; shows: its elements by a small subset of CSS selectors, its text, its
;;;; links and its forms.  What a browser check asserts from the server's
;;;; answer, a test asserts here without a browser (spec/preview.md 4).
;;;;
;;;; A package of its own, which a test reaches by a local nickname
;;;; (page:visit), so its short names never meet a client's own helpers in
;;;; a package that uses tun.test-support.  It reaches Tun only through
;;;; exported symbols.
;;;;
;;;; Only pages Tun's renderer wrote are read, and it writes well-formed
;;;; HTML with double-quoted, escaped attributes, so a small reader builds
;;;; the element tree; it is not an HTML5 parser.

(defpackage #:tun.page-test
  (:use #:cl)
  (:local-nicknames (#:support #:tun.test-support))
  (:export
   ;; the server and its requests
   #:with-server #:visit #:post #:submit #:follow
   ;; an answer
   #:answer #:status #:location #:header #:content-type #:body #:json
   ;; what it shows
   #:read-html #:element #:elements #:part #:parts #:text #:attribute #:tag
   #:title #:headings #:links #:alerts
   ;; its forms
   #:form #:forms #:form-action #:form-method #:form-multipart-p #:form-fields
   #:form-value #:form-values #:form-errors #:form-error))

(in-package #:tun.page-test)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; The element tree

(defstruct (node (:constructor make-node (tag attributes parent)))
  "An element: its TAG in lower case, its ATTRIBUTES as an alist from each
name in lower case to its value (T for one without), its CHILDREN in order,
elements and strings of text, and its PARENT, NIL for the document."
  tag attributes (children '()) parent)

(defmethod print-object ((node node) stream)
  ;; Its parent and children would print the whole document, round.
  (print-unreadable-object (node stream :type nil)
    (format stream "~a~@[#~a~]~@[ data-part=~a~]" (or (node-tag node) "document")
            (let ((id (attribute-value node "id"))) (and (stringp id) id))
            (let ((part (attribute-value node "data-part"))) (and (stringp part) part)))))

(defparameter +void-elements+
  '("area" "base" "br" "col" "embed" "hr" "img" "input" "link" "meta" "source" "track" "wbr")
  "The elements that have no content and no end tag.")

(defparameter +raw-text-elements+ '("script" "style")
  "The elements whose content is text up to their end tag, never markup.")

(defparameter +escapable-raw-text-elements+ '("textarea" "title")
  "The elements whose content is text up to their end tag, entities read.")

(defparameter +named-entities+
  '(("amp" . "&") ("lt" . "<") ("gt" . ">") ("quot" . "\"") ("apos" . "'") ("nbsp" . " "))
  "The named character references Tun's renderer writes, and the space
that cannot break.")

(defun unescape (text)
  "TEXT with its character references read, as a browser reads them."
  (if (find #\& text)
      (cl-ppcre:regex-replace-all
       "&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);" text
       (lambda (match name)
         (cond ((char= (char name 0) #\#)
                (string (code-char (if (char-equal (char name 1) #\x)
                                       (parse-integer name :start 2 :radix 16)
                                       (parse-integer name :start 1)))))
               (t (or (cdr (assoc name +named-entities+ :test #'string=)) match))))
       :simple-calls t)
      text))

(defun name-char-p (char)
  (or (alphanumericp char) (find char "-_:.")))

(defun space-char-p (char)
  (member char '(#\Space #\Tab #\Newline #\Return #\Page)))

(defun skip-space (html index)
  (or (position-if-not #'space-char-p html :start index) (length html)))

(defun after-char (html char index)
  "The index after the first CHAR in HTML from INDEX, or the end of HTML."
  (let ((found (position char html :start index)))
    (if found (1+ found) (length html))))

(defun read-attribute-value (html index)
  "The value written at INDEX in HTML, quoted or bare, read: values it and
the index after it."
  (let ((quote (and (< index (length html)) (find (char html index) "\"'"))))
    (if quote
        (let ((close (or (position quote html :start (1+ index)) (length html))))
          (values (unescape (subseq html (1+ index) close)) (min (length html) (1+ close))))
        (let ((close (or (position-if (lambda (c) (or (space-char-p c) (char= c #\>)))
                                      html :start index)
                         (length html))))
          (values (unescape (subseq html index close)) close)))))

(defun read-attributes (html index)
  "The attributes of the tag whose attributes begin at INDEX in HTML: values
the alist, the index after the tag's >, and whether it ended with />."
  (let ((attributes '())
        (length (length html)))
    (loop
     (setf index (skip-space html index))
     (when (>= index length)
       (return (values (nreverse attributes) index nil)))
     (let ((char (char html index)))
       (cond ((char= char #\>)
              (return (values (nreverse attributes) (1+ index) nil)))
             ((and (char= char #\/) (< (1+ index) length) (char= (char html (1+ index)) #\>))
              (return (values (nreverse attributes) (+ index 2) t)))
             ((char= char #\/) (incf index))
             (t
              (let* ((end (max (1+ index)
                               (or (position-if-not #'name-char-p html :start index) length)))
                     (name (string-downcase (subseq html index end)))
                     (after (skip-space html end)))
                (if (and (< after length) (char= (char html after) #\=))
                    (multiple-value-bind (value next)
                        (read-attribute-value html (skip-space html (1+ after)))
                      (push (cons name value) attributes)
                      (setf index next))
                    (progn (push (cons name t) attributes)
                           (setf index after))))))))))

(defun add-child (parent child)
  (push child (node-children parent)))

(defun close-node (node)
  (setf (node-children node) (nreverse (node-children node))))

(defun read-text-content (html index node)
  "Give NODE, a script, style, text area or title opened before INDEX in
HTML, its text up to its end tag; the index after that tag."
  (let* ((tag (node-tag node))
         (close (or (search (format nil "</~a" tag) html :start2 index :test #'char-equal)
                    (length html)))
         (content (subseq html index close)))
    (when (plusp (length content))
      (setf (node-children node)
            (list (if (member tag +raw-text-elements+ :test #'string=)
                      content
                      (unescape content)))))
    (if (< close (length html)) (after-char html #\> close) (length html))))

(defun tag-name-at (html start)
  "The name of a tag that begins at START in HTML, in lower case, and the
index after it."
  (let ((end (or (position-if-not #'name-char-p html :start start) (length html))))
    (values (string-downcase (subseq html start end)) end)))

(defun parse-html (html)
  "The document HTML holds, as a node of no tag whose children are its
elements and texts."
  (let* ((document (make-node nil '() nil))
         (stack (list document))
         (index 0)
         (length (length html)))
    (labels ((next-char-p (test)
               (and (< (1+ index) length) (funcall test (char html (1+ index)))))
             (text (string)
               (when (plusp (length string))
                 (add-child (first stack) string)))
             (close-to (tag)
               ;; An end tag closes the open element it names and those
               ;; opened inside it; one that names no open element is dropped.
               (when (find tag (butlast stack) :key #'node-tag :test #'equal)
                 (loop for node = (pop stack)
                       do (close-node node)
                       until (equal (node-tag node) tag))))
             (open-tag ()
               (multiple-value-bind (tag end) (tag-name-at html (1+ index))
                 (multiple-value-bind (attributes after closed) (read-attributes html end)
                   (let ((node (make-node tag attributes (first stack))))
                     (add-child (first stack) node)
                     (setf index after)
                     (cond ((or closed (member tag +void-elements+ :test #'string=)))
                           ((or (member tag +raw-text-elements+ :test #'string=)
                                (member tag +escapable-raw-text-elements+ :test #'string=))
                            (setf index (read-text-content html index node)))
                           (t (push node stack))))))))
      (loop while (< index length)
            do (let ((open (or (position #\< html :start index) length)))
                 (text (unescape (subseq html index open)))
                 (setf index open)
                 (when (< index length)
                   (cond
                     ((eql 0 (search "<!--" html :start2 index :end2 (min length (+ index 4))))
                      (setf index (let ((end (search "-->" html :start2 (+ index 4))))
                                    (if end (+ end 3) length))))
                     ((next-char-p (lambda (c) (find c "!?")))
                      (setf index (after-char html #\> index)))
                     ((next-char-p (lambda (c) (char= c #\/)))
                      (multiple-value-bind (tag end) (tag-name-at html (+ index 2))
                        (close-to tag)
                        (setf index (after-char html #\> end))))
                     ((next-char-p #'alpha-char-p) (open-tag))
                     (t (text "<") (incf index))))))
      (mapc #'close-node stack)
      document)))

;;; ------------------------------------------------------------------
;;; Selectors: a small subset of CSS

(defstruct (compound (:constructor make-compound ()))
  "One step of a selector: a tag or NIL for any, and the tests of its
attributes, each (NAME OPERATOR VALUE), OPERATOR NIL when only being there
counts."
  tag (tests '()))

(defun refuse-selector (selector why)
  (error "The selector ~s ~a; a page test reads a type, #id, .class, [attr] and ~
          [attr=value] (also ~~=, ^=, $=, *=), joined by a space or >, several by ,"
         selector why))

(defun ident-end (selector start)
  (or (position-if-not (lambda (c) (or (alphanumericp c) (find c "-_"))) selector :start start)
      (length selector)))

(defun parse-compound (selector index)
  "Read a compound selector at INDEX: values it and the index after it."
  (let ((compound (make-compound))
        (start index))
    (flet ((ident (from)
             (let ((end (ident-end selector from)))
               (when (= end from)
                 (refuse-selector selector (format nil "has no name at ~d" from)))
               (values (subseq selector from end) end))))
      (loop while (< index (length selector))
            do (let ((char (char selector index)))
                 (cond
                   ((and (= index start) (char= char #\*)) (incf index))
                   ((and (= index start) (alpha-char-p char))
                    (multiple-value-bind (name end) (ident index)
                      (setf (compound-tag compound) (string-downcase name) index end)))
                   ((char= char #\#)
                    (multiple-value-bind (name end) (ident (1+ index))
                      (push (list "id" "=" name) (compound-tests compound))
                      (setf index end)))
                   ((char= char #\.)
                    (multiple-value-bind (name end) (ident (1+ index))
                      (push (list "class" "~=" name) (compound-tests compound))
                      (setf index end)))
                   ((char= char #\[)
                    (let ((close (position #\] selector :start index)))
                      (unless close (refuse-selector selector "does not close its ["))
                      (push (parse-attribute-test selector (subseq selector (1+ index) close))
                            (compound-tests compound))
                      (setf index (1+ close))))
                   (t (return))))))
    (when (= index start)
      (refuse-selector selector
                       (format nil "has ~s where a step begins"
                               (subseq selector index (min (length selector) (1+ index))))))
    (setf (compound-tests compound) (nreverse (compound-tests compound)))
    (values compound index)))

(defun parse-attribute-test (selector text)
  "TEXT, what [ and ] hold, as a test (NAME OPERATOR VALUE)."
  (let* ((text (string-trim " " text))
         (end (or (position-if-not (lambda (c) (or (alphanumericp c) (find c "-_:"))) text)
                  (length text)))
         (name (string-downcase (subseq text 0 end)))
         (rest (string-trim " " (subseq text end))))
    (when (zerop (length name)) (refuse-selector selector "names no attribute in [ ]"))
    (if (zerop (length rest))
        (list name nil nil)
        (let* ((operator (cond ((eql 0 (search "=" rest)) "=")
                               ((and (> (length rest) 1) (char= (char rest 1) #\=)
                                     (find (char rest 0) "~^$*"))
                                (subseq rest 0 2))
                               (t (refuse-selector selector (format nil "has the test ~s" text)))))
               (value (string-trim " " (subseq rest (length operator)))))
          (list name operator
                (if (and (>= (length value) 2) (find (char value 0) "\"'")
                         (char= (char value 0) (char value (1- (length value)))))
                    (subseq value 1 (1- (length value)))
                    value))))))

(defun parse-selector (selector)
  "SELECTOR as a list of alternatives, each a list of (COMBINATOR .
COMPOUND) from the left, COMBINATOR :DESCENDANT or :CHILD (NIL for the
first)."
  (let ((alternatives '()) (steps '()) (combinator nil) (index 0))
    (flet ((space-p (c) (member c '(#\Space #\Tab #\Newline))))
      (loop
       (let ((after (or (position-if-not #'space-p selector :start index) (length selector))))
         (when (and steps (> after index) (null combinator))
           (setf combinator :descendant))
         (setf index after))
       (when (>= index (length selector))
         (when (or (null steps) combinator)
           (refuse-selector selector "ends without a step"))
         (push (nreverse steps) alternatives)
         (return))
       (let ((char (char selector index)))
         (cond ((char= char #\>)
                (unless steps (refuse-selector selector "begins with >"))
                (setf combinator :child)
                (incf index))
               ((char= char #\,)
                (when (or (null steps) (eq combinator :child))
                  (refuse-selector selector "has an empty part before ,"))
                (push (nreverse steps) alternatives)
                (setf steps '() combinator nil)
                (incf index))
               (t
                (multiple-value-bind (compound end) (parse-compound selector index)
                  (push (cons (and steps (or combinator :descendant)) compound) steps)
                  (setf combinator nil index end)))))))
    (nreverse alternatives)))

(defun attribute-value (node name)
  (cdr (assoc name (node-attributes node) :test #'string=)))

(defun words (text)
  (cl-ppcre:split "\\s+" (string-trim '(#\Space #\Tab #\Newline) text)))

(defun test-matches-p (node test)
  (destructuring-bind (name operator expected) test
    (let ((value (attribute-value node name)))
      (and value
           (or (null operator)
               (let ((value (if (stringp value) value "")))
                 (cond ((string= operator "=") (string= value expected))
                       ((string= operator "~=") (member expected (words value) :test #'string=))
                       ((string= operator "^=") (and (plusp (length expected))
                                                     (eql 0 (search expected value))))
                       ((string= operator "$=") (and (plusp (length expected))
                                                     (>= (length value) (length expected))
                                                     (string= expected value
                                                              :start2 (- (length value)
                                                                         (length expected)))))
                       ((string= operator "*=") (and (plusp (length expected))
                                                     (search expected value) t)))))))))

(defun compound-matches-p (node compound)
  (and (node-tag node)
       (or (null (compound-tag compound)) (string= (compound-tag compound) (node-tag node)))
       (every (lambda (test) (test-matches-p node test)) (compound-tests compound))))

(defun steps-match-p (node steps)
  "True when NODE matches the last of STEPS and its ancestors the ones
before, as their combinators say."
  (let ((last (car (last steps))))
    (and (compound-matches-p node (cdr last))
         (let ((before (butlast steps)))
           (or (null before)
               (ecase (car last)
                 (:child (and (node-parent node) (steps-match-p (node-parent node) before)))
                 (:descendant
                  (loop for ancestor = (node-parent node) then (node-parent ancestor)
                        while ancestor
                        thereis (steps-match-p ancestor before)))))))))

(defun descendants (node)
  "The elements inside NODE, in document order."
  (let ((found '()))
    (labels ((walk (node)
               (dolist (child (node-children node))
                 (when (node-p child)
                   (push child found)
                   (walk child)))))
      (walk node))
    (nreverse found)))

;;; ------------------------------------------------------------------
;;; An answer

(defstruct (page-form (:constructor make-page-form (node controls)))
  "A form of a page: its element NODE and its CONTROLS, the named elements
it sends, in document order."
  node controls)

(defmethod print-object ((form page-form) stream)
  (print-unreadable-object (form stream)
    (let ((action (attribute-value (page-form-node form) "action")))
      (format stream "form~@[ to ~a~]" (and (stringp action) action)))))

(defstruct (answer (:constructor make-answer (method path status headers octets port)))
  "What the server answered METHOD PATH: its STATUS, its HEADERS (an alist
by keyword, as Drakma gives them) and its body's OCTETS; PORT is the
server's.  Its document is read when first asked for."
  method path status headers octets port (document nil))

(defmethod print-object ((answer answer) stream)
  (print-unreadable-object (answer stream :type t)
    (format stream "~a ~a ~a" (answer-status answer) (answer-method answer) (answer-path answer))))

(defun status (answer)
  "The status ANSWER came with."
  (answer-status answer))

(defun header (answer name)
  "The header NAME, a string or a keyword, of ANSWER, or NIL."
  (cdr (assoc (if (stringp name) (intern (string-upcase name) :keyword) name)
              (answer-headers answer))))

(defun content-type (answer)
  "ANSWER's media type, without its parameters, in lower case, or NIL."
  (let ((type (header answer :content-type)))
    (and type (string-downcase (string-trim " " (subseq type 0 (or (position #\; type)
                                                                   (length type))))))))

(defun text-type-p (type)
  (and type (or (eql 0 (search "text/" type))
                (search "json" type) (search "xml" type) (search "javascript" type))))

(defun body (answer)
  "ANSWER's body: a string for a text or JSON type, else its octets."
  (let ((octets (or (answer-octets answer) (make-array 0 :element-type '(unsigned-byte 8)))))
    (if (text-type-p (content-type answer))
        (sb-ext:octets-to-string octets :external-format :utf-8)
        octets)))

(defun json (answer)
  "ANSWER's body read as JSON."
  (tun.core:parse-json (sb-ext:octets-to-string (answer-octets answer) :external-format :utf-8)))

(defun site-path (url port)
  "The path and query URL names when it is on the server of PORT (or is a
path), else URL as it is."
  (let ((match (nth-value 1 (cl-ppcre:scan-to-strings "^https?://([^/?#]*)(.*)$" url))))
    (cond ((null match) url)
          ((member (aref match 0)
                   (list (format nil "127.0.0.1:~d" port) (format nil "localhost:~d" port))
                   :test #'string-equal)
           (let ((rest (aref match 1))) (if (string= rest "") "/" rest)))
          (t url))))

(defun location (answer)
  "Where ANSWER leads: the path of a redirect's Location, or of the
HX-Redirect or HX-Location an htmx request was answered with; NIL when it
leads nowhere."
  (let ((url (or (and (<= 300 (status answer) 399) (header answer :location))
                 (header answer :hx-redirect)
                 (let ((htmx (header answer :hx-location)))
                   (and htmx (if (eql 0 (search "{" htmx))
                                 (tun.core:jget (tun.core:parse-json htmx) "path")
                                 htmx))))))
    (and url (site-path url (answer-port answer)))))

(defun document (where)
  "The element tree of WHERE: an answer's body read as HTML, an element, or
a form's element."
  (etypecase where
    (node where)
    (page-form (page-form-node where))
    (answer (or (answer-document where)
                (setf (answer-document where)
                      (parse-html (sb-ext:octets-to-string
                                   (or (answer-octets where)
                                       (make-array 0 :element-type '(unsigned-byte 8)))
                                   :external-format :utf-8)))))))

;;; ------------------------------------------------------------------
;;; What it shows

(defun read-html (text)
  "TEXT, HTML such as a frame's srcdoc, read as an answer's body is: its
document, which the readers below take as they take an answer."
  (parse-html text))

(defun elements (where selector)
  "Every element inside WHERE, an answer or an element, that SELECTOR names,
in document order."
  (let ((alternatives (parse-selector selector)))
    (remove-if-not (lambda (node)
                     (some (lambda (steps) (steps-match-p node steps)) alternatives))
                   (descendants (document where)))))

(defun element (where selector)
  "The first element inside WHERE that SELECTOR names, or NIL."
  (first (elements where selector)))

(defun parts (where name)
  "Every element inside WHERE whose data-part is NAME."
  (remove-if-not (lambda (node) (equal (attribute-value node "data-part") name))
                 (descendants (document where))))

(defun part (where name)
  "The first element inside WHERE whose data-part is NAME, or NIL."
  (first (parts where name)))

(defun attribute (element name)
  "The value of ELEMENT's attribute NAME: a string, T for one without a
value, or NIL when it has none."
  (attribute-value element (string-downcase name)))

(defun tag (element)
  "ELEMENT's tag, in lower case."
  (node-tag element))

(defparameter +unread-elements+ '("script" "style" "template" "head")
  "The elements whose content a person does not read on the page.")

(defparameter +inline-elements+
  '("a" "abbr" "b" "bdi" "bdo" "cite" "code" "data" "del" "dfn" "em" "i" "ins" "kbd" "label"
    "mark" "q" "s" "samp" "small" "span" "strong" "sub" "sup" "time" "u" "var" "img" "svg"
    "use" "path")
  "The elements that stand inside a line: their edges are not a space.")

(defun collapse-space (text)
  (string-trim " " (cl-ppcre:regex-replace-all "[ \\t\\n\\r\\f]+" text " ")))

(defun text (where)
  "The text of WHERE, an answer or an element, as a person reads it: white
space collapsed to one space and trimmed, the edges of an element that is
not inline a space, and nothing of scripts, styles, templates and elements
marked hidden."
  (let ((out (make-string-output-stream)))
    (labels ((walk (node)
               (dolist (child (node-children node))
                 (if (stringp child)
                     (write-string child out)
                     (let ((tag (node-tag child)))
                       (unless (or (member tag +unread-elements+ :test #'string=)
                                   (attribute-value child "hidden"))
                         (let ((block (not (member tag +inline-elements+ :test #'string=))))
                           (when block (write-char #\Space out))
                           (if (member tag '("input" "br") :test #'string=)
                               (write-char #\Space out)
                               (walk child))
                           (when block (write-char #\Space out)))))))))
      (let ((root (document where)))
        (if (and (node-tag root) (or (member (node-tag root) +unread-elements+ :test #'string=)
                                     (equal (node-tag root) "title")))
            ;; Asked for itself, such as the title: its own text.
            (dolist (child (node-children root)) (when (stringp child) (write-string child out)))
            (walk root))))
    (collapse-space (get-output-stream-string out))))

(defun title (answer)
  "The document's title, or NIL."
  (let ((title (element answer "title")))
    (and title (text title))))

(defun headings (where)
  "The text of each heading inside WHERE, h1 to h6, in order."
  (mapcar #'text (elements where "h1, h2, h3, h4, h5, h6")))

(defun links (where)
  "Each link inside WHERE, an <a> with an href, as (TEXT . HREF), in order."
  (mapcar (lambda (node) (cons (text node) (attribute-value node "href")))
          (remove-if-not (lambda (node) (stringp (attribute-value node "href")))
                         (elements where "a"))))

(defun alerts (where)
  "The text of each alert inside WHERE: a .tun-alert, or an element of
role alert."
  (mapcar #'text (elements where ".tun-alert, [role=alert]")))

;;; ------------------------------------------------------------------
;;; Forms

(defun form-of-control (node)
  "The id a control names in form=, else the form element it is inside, or NIL."
  (or (let ((owner (attribute-value node "form"))) (and (stringp owner) owner))
      (loop for ancestor = (node-parent node) then (node-parent ancestor)
            while ancestor
            when (equal (node-tag ancestor) "form") return ancestor)))

(defun page-forms (where)
  "Every form of WHERE, each with the controls inside it and those that name
it with form=ID: those with a name, and its submit buttons, named or not."
  (let* ((all (descendants (root-of (document where))))
         (controls (remove-if-not (lambda (node)
                                    (and (member (node-tag node)
                                                 '("input" "button" "select" "textarea")
                                                 :test #'string=)
                                         (or (stringp (attribute-value node "name"))
                                             (submit-button-p node))))
                                  all)))
    (mapcar (lambda (form)
              (let ((id (attribute-value form "id")))
                (make-page-form form
                                (remove-if-not (lambda (control)
                                                 (let ((owner (form-of-control control)))
                                                   (or (eq owner form)
                                                       (and (stringp id) (equal owner id)))))
                                               controls))))
            (remove-if-not (lambda (node) (equal (node-tag node) "form"))
                           (descendants (document where))))))

(defun forms (where)
  "Every form inside WHERE, in order."
  (page-forms where))

(defun form (where &optional selector)
  "The form SELECTOR names inside WHERE; without one, the first form inside
the page's <main>, else the first form; NIL when there is none."
  (let ((all (page-forms where)))
    (if selector
        (let ((nodes (elements where selector)))
          (find-if (lambda (form) (member (page-form-node form) nodes)) all))
        (or (let ((main (element where "main")))
              (and main (let ((inside (descendants main)))
                          (find-if (lambda (form) (member (page-form-node form) inside)) all))))
            (first all)))))

(defun form-action (form)
  "The action FORM's element names, or NIL."
  (let ((action (attribute-value (page-form-node form) "action")))
    (and (stringp action) action)))

(defun form-method (form)
  "\"get\" or \"post\"."
  (let ((method (attribute-value (page-form-node form) "method")))
    (if (and (stringp method) (string-equal method "post")) "post" "get")))

(defun form-multipart-p (form)
  "True when FORM posts multipart/form-data."
  (equalp (attribute-value (page-form-node form) "enctype") "multipart/form-data"))

(defun control-type (node)
  (let ((type (attribute-value node "type")))
    (cond ((stringp type) (string-downcase type))
          ((equal (node-tag node) "button") "submit")
          (t "text"))))

(defun submit-button-p (node)
  (and (member (node-tag node) '("input" "button") :test #'string=)
       (member (control-type node) '("submit" "image") :test #'string=)))

(defun option-value (option)
  (let ((value (attribute-value option "value")))
    (if (stringp value) value (text option))))

(defun control-values (node)
  "What the control NODE sends of itself when its form is sent, a list of
values: none for a button, a file, an unticked box or a disabled control."
  (unless (attribute-value node "disabled")
    (let ((tag (node-tag node)))
      (cond
        ((equal tag "select")
         (let* ((options (elements node "option"))
                (selected (remove-if-not (lambda (option) (attribute-value option "selected"))
                                         options)))
           (mapcar #'option-value
                   (cond (selected (if (attribute-value node "multiple") selected (last selected)))
                         ((attribute-value node "multiple") '())
                         (options (list (first options)))))))
        ((equal tag "textarea")
         ;; A browser drops the line break right after <textarea>.
         (list (string-left-trim '(#\Newline) (format nil "~{~a~}" (node-children node)))))
        (t
         (let ((type (control-type node))
               (value (let ((value (attribute-value node "value")))
                        (if (stringp value) value ""))))
           (cond ((member type '("submit" "image" "button" "reset" "file") :test #'string=) '())
                 ((member type '("checkbox" "radio") :test #'string=)
                  (and (attribute-value node "checked")
                       (list (if (stringp (attribute-value node "value")) value "on"))))
                 (t (list value)))))))))

(defun button-named-p (node button)
  (or (equal (attribute-value node "name") button)
      (equal (text node) button)
      (and (equal (node-tag node) "input") (equal (attribute-value node "value") button))))

(defun pressed-button (form button)
  "The submit button of FORM pressed: the one named or labelled BUTTON, or
without BUTTON the first named one; NIL for none."
  (let ((buttons (remove-if-not #'submit-button-p (page-form-controls form))))
    (if button
        (or (find-if (lambda (node) (button-named-p node button)) buttons)
            (error "The form ~@[to ~a ~]has no submit button named or labelled ~s; ~
                    it has ~{~s~^, ~}"
                   (form-action form) button (mapcar #'text buttons)))
        (find-if (lambda (node) (stringp (attribute-value node "name"))) buttons))))

(defun sent-fields (form &optional pressed)
  "What a browser sends of FORM untouched, PRESSED the submit button
pressed: an alist of names and values, in document order."
  (loop for control in (page-form-controls form)
        for name = (attribute-value control "name")
        if (submit-button-p control)
        when (and (eq control pressed) (stringp name))
        collect (cons name (let ((value (attribute-value control "value")))
                             (if (stringp value) value "")))
        end
        else
        when (stringp name)
        append (mapcar (lambda (value) (cons name value)) (control-values control))))

(defun form-fields (form)
  "What a browser sends of FORM when it is sent untouched, its first named
submit button pressed: an alist of names and values, in order."
  (sent-fields form (pressed-button form nil)))

(defun form-values (form name)
  "The values FORM sends for NAME untouched, in order."
  (loop for (field . value) in (form-fields form)
        when (equal field name) collect value))

(defun form-value (form name)
  "The first value FORM sends for NAME untouched, or NIL."
  (first (form-values form name)))

(defun root-of (node)
  "The document NODE is in."
  (loop while (node-parent node) do (setf node (node-parent node)))
  node)

(defun error-message (control)
  "The message of the field whose control CONTROL is refused, or NIL: the
text of the element its aria-describedby names that is a field's error."
  (let ((described (attribute-value control "aria-describedby")))
    (when (stringp described)
      (loop for id in (words described)
            for node = (find id (descendants (root-of control))
                             :key (lambda (node) (attribute-value node "id")) :test #'equal)
            when (and node (let ((class (attribute-value node "class")))
                             (and (stringp class) (search "-error" class))))
            return (text node)))))

(defun form-errors (form)
  "Each field of FORM marked refused, as (NAME . MESSAGE), in order."
  (loop for control in (page-form-controls form)
        when (equal (attribute-value control "aria-invalid") "true")
        collect (cons (attribute-value control "name")
                      (error-message control))))

(defun form-error (form name)
  "The message of FORM's refused field NAME, or NIL."
  (cdr (assoc name (form-errors form) :test #'equal)))

(defparameter +file-types+
  '(("png" . "image/png") ("jpg" . "image/jpeg") ("jpeg" . "image/jpeg") ("gif" . "image/gif")
    ("webp" . "image/webp") ("svg" . "image/svg+xml") ("pdf" . "application/pdf")
    ("txt" . "text/plain") ("csv" . "text/csv") ("json" . "application/json"))
  "The media type a browser gives a file it sends, by its extension.")

(defun field-value (value)
  "VALUE as a form sends it: a pathname as that file, named and typed as a
browser sends it (multipart); anything else as text."
  (if (pathnamep value)
      (list value :filename (file-namestring value)
            :content-type (or (cdr (assoc (pathname-type value) +file-types+ :test #'string-equal))
                              "application/octet-stream"))
      (princ-to-string value)))

(defun replace-fields (fields given)
  "FIELDS, an alist, with GIVEN's names in place: each entry of GIVEN, a
name and a value or a list of values, takes the place of every field of
that name, where the first was, or last when there was none."
  (let ((result (copy-list fields)))
    (loop for (name . value) in given
          for values = (mapcar (lambda (value) (cons name (field-value value)))
                               (if (listp value) value (list value)))
          for at = (position name result :key #'car :test #'equal)
          do (setf result (remove name result :key #'car :test #'equal))
          (setf result (if at
                           (append (subseq result 0 (min at (length result))) values
                                   (nthcdr (min at (length result)) result))
                           (append result values))))
    result))

;;; ------------------------------------------------------------------
;;; The server

(defstruct (server (:constructor make-server (port actor)))
  "The server a WITH-SERVER body asks: its PORT, the ACTOR its requests are
sent as by default, and each actor's cookies."
  port actor (jars (make-hash-table :test 'equal)))

(defvar *server* nil "The server of the WITH-SERVER being run.")

(defun current-server ()
  (or *server* (error "A page test's request runs inside page:with-server")))

(defvar *templates* (make-hash-table :test 'equal)
  "The records of each scenario made in this process, by (CLASS SCENARIO
DATABASE): a memory store or the URL of a Postgres template database, or
:PER-SERVER for a scenario that set a global variable.")

(defun tun-package-p (package)
  "True for a package of Tun's own, whose state is the kernel's, not a
client's."
  (let ((name (package-name package)))
    (or (string= name "TUN") (eql 0 (search "TUN." name)))))

(defun scenario-packages (class scenario)
  "The packages whose global variables tell whether SCENARIO did more than
make records: its own, the client's, and CLASS's with those named after it,
such as its tests', unless CLASS is Tun's own."
  (let* ((own (symbol-package class))
         (prefix (concatenate 'string (package-name own) ".")))
    (remove-duplicates
     (append (and (not (tun-package-p own))
                  (cons (package-name own)
                        (loop for package in (list-all-packages)
                              when (eql 0 (search prefix (package-name package)))
                              collect (package-name package))))
             (and scenario
                  (loop for package in (list-all-packages)
                        when (eq scenario (support:find-scenario (support:scenario-name scenario)
                                                                 :package package))
                        collect (package-name package)))
             support:*client-packages*)
     :test #'string=)))

(defun open-on (class database)
  "An application of CLASS on the test clock with claimed identity, on
DATABASE: (:store STORE) or (:db URL)."
  (apply #'tun.runtime:open-application class :test-clock t :identity :claimed database))

(defun make-records (class scenario database)
  "Make SCENARIO's records in a fresh store of DATABASE's kind: values its
initargs and whether making it changed a global variable."
  (let* ((initargs (ecase database
                     (:memory (list :store (make-instance 'tun.store.memory:memory-store)))
                     (:postgres (list :db (support:scratch-postgres "page_template")))))
         (support:*app* (open-on class initargs))
         (before (support:global-values (scenario-packages class scenario))))
    (unwind-protect (when scenario (support:run-scenario scenario))
      (tun.runtime:close-application support:*app*))
    (values initargs
            (and (support:changed-variables
                  before (support:global-values (scenario-packages class scenario)))
                 t))))

(defun template-for (class scenario database)
  "The template of SCENARIO's records for CLASS on DATABASE, made the first
time it is asked for in this process."
  (let ((key (list class (and scenario (support:scenario-name scenario)) database)))
    (or (gethash key *templates*)
        (setf (gethash key *templates*)
              (multiple-value-bind (initargs changed) (make-records class scenario database)
                (if changed
                    (progn (when (getf initargs :db)
                             (support:drop-scratch-postgres (getf initargs :db)))
                           :per-server)
                    (or (getf initargs :store) (getf initargs :db))))))))

(defun call-with-database (class scenario database function)
  "Call FUNCTION with the initargs of a database holding SCENARIO's records
for CLASS, a copy of its template, and whether the server must make the
scenario itself; a Postgres copy is dropped after."
  (let ((template (template-for class scenario database)))
    (cond ((eq template :per-server)
           (ecase database
             (:memory (funcall function
                               (list :store (make-instance 'tun.store.memory:memory-store)) t))
             (:postgres (let ((url (support:scratch-postgres "page")))
                          (unwind-protect (funcall function (list :db url) t)
                            (support:drop-scratch-postgres url))))))
          ((eq database :memory)
           (funcall function (list :store (tun.store.memory:copy-memory-store template)) nil))
          (t (let ((url (support:scratch-postgres "page" :template template)))
               (unwind-protect (funcall function (list :db url) nil)
                 (support:drop-scratch-postgres url)))))))

(defun call-with-server (function &key (class 'tun.core:application) scenario (database :memory)
                                    language actor)
  "Call FUNCTION with *SERVER* serving an application of CLASS holding
SCENARIO's records over HTTP in this process (spec/testing.md 6)."
  (check-type database (member :memory :postgres))
  (let ((scenario (and scenario
                       (or (if (and (symbolp scenario) (symbol-package scenario)
                                    (not (keywordp scenario)))
                               (support:find-scenario scenario :package (symbol-package scenario))
                               (support:find-scenario scenario))
                           (error "There is no scenario ~(~a~); the scenarios are ~{~a~^, ~}"
                                  scenario (support:scenario-names))))))
    (call-with-database
     class scenario database
     (lambda (initargs make)
       (let ((support:*app* (open-on class initargs)))
         (unwind-protect
              (progn
                (when (and make scenario) (support:run-scenario scenario))
                (when language
                  (support:call-ok "settings_set" "admin:page-test"
                                   "key" "locale.language" "value" language))
                (let ((acceptor (tun.http:start-server support:*app* :port 0)))
                  (unwind-protect
                       (let ((*server* (make-server (tun.http:server-port acceptor) actor)))
                         (funcall function))
                    (tun.http:stop-server acceptor))))
           (tun.runtime:close-application support:*app*)))))))

(defmacro with-server ((&rest options &key class scenario database language actor) &body body)
  "Run BODY with *APP* an application of CLASS on the test clock holding the
records of SCENARIO (a name; none when NIL), in memory or, with DATABASE
:POSTGRES, on the test Postgres server, served over HTTP in this process
with claimed identity; LANGUAGE the tenant's language when given, and
ACTOR who BODY's requests are sent as unless they name another
(spec/testing.md 6)."
  (declare (ignore class scenario database language actor))
  `(call-with-server (lambda () ,@body) ,@options))

;;; ------------------------------------------------------------------
;;; Requests

(defun browser-encoded (path)
  "PATH as a browser sends it: each character a URL may not hold as it is
as % and the hex of its UTF-8 bytes."
  (with-output-to-string (out)
    (loop for char across path
          do (if (or (char<= #\a char #\z) (char<= #\A char #\Z) (char<= #\0 char #\9)
                     (find char "-._~:/?@!$&'()*+,;=%"))
                 (write-char char out)
                 (loop for byte across (sb-ext:string-to-octets (string char)
                                                                :external-format :utf-8)
                       do (format out "%~2,'0X" byte))))))

(defun actor-jar (actor)
  (let ((jars (server-jars (current-server))))
    (or (gethash actor jars)
        (setf (gethash actor jars) (make-instance 'drakma:cookie-jar)))))

(defun asked-path (url)
  "The path and query a request for URL asks this server: URL itself when
it is a path, else what follows its scheme and host, for a test reaches no
other site."
  (let ((match (nth-value 1 (cl-ppcre:scan-to-strings "^[a-zA-Z][a-zA-Z0-9+.-]*://[^/?#]*(.*)$"
                                                      url))))
    (cond ((null match) url)
          ((string= (aref match 0) "") "/")
          (t (aref match 0)))))

(defun query-string (fields)
  "FIELDS, an alist of names and values, as a URL's query, UTF-8 encoded."
  (format nil "~{~a~^&~}"
          (mapcar (lambda (field)
                    (format nil "~a=~a" (drakma:url-encode (car field) :utf-8)
                            (drakma:url-encode (cdr field) :utf-8)))
                  fields)))

(defun request (method path &key (actor nil actor-p) htmx target headers fields multipart)
  "Send METHOD PATH to the server as ACTOR (the server's when not given; NIL
sends none), with FIELDS as its form, and answer what it answered."
  (let* ((server (current-server))
         (actor (if actor-p actor (server-actor server)))
         (path (asked-path path)))
    (check-type htmx (member nil :partial :full))
    (multiple-value-bind (octets status response-headers)
        (apply #'drakma:http-request
               (format nil "http://127.0.0.1:~d~a" (server-port server) (browser-encoded path))
               :method method :parameters fields :form-data multipart
               ;; The path goes as it is written: Drakma would encode its
               ;; query's % again.
               :preserve-uri t
               :cookie-jar (actor-jar actor) :redirect nil
               :force-binary t :external-format-out :utf-8
               :additional-headers
               (append (and actor (list (cons "X-Tun-Actor" actor)))
                       (and htmx (list (cons "HX-Request" "true")
                                       (cons "HX-Request-Type" (string-downcase htmx))))
                       (and target (list (cons "HX-Target" target)))
                       headers)
               ;; Measured and sent whole, as a browser does: Hunchentoot
               ;; takes no chunked request.
               (and multipart (list :content-length t)))
      (make-answer method path status response-headers octets (server-port server)))))

(defun field-pairs (fields)
  "FIELDS, an alist of a name and a value or a list of values, as the pairs
a form posts: a name once for each of its values, a pathname a file."
  (loop for (name . value) in fields
        append (mapcar (lambda (value) (cons name (field-value value)))
                       (if (listp value) value (list value)))))

(defun visit (path &rest options &key actor htmx target headers)
  "GET PATH (a path, or a whole URL, asked of this server by its path) and
answer what the server answered; no redirect is followed."
  (declare (ignore actor htmx target headers))
  (apply #'request :get path options))

(defun post (path fields &rest options &key actor htmx target headers multipart)
  "POST FIELDS, an alist of a name and a value or a list of values, to PATH;
multipart/form-data with MULTIPART."
  (declare (ignore actor htmx target headers multipart))
  (apply #'request :post path :fields (field-pairs fields) options))

(defun submit (answer &rest options &key form fields button actor htmx target headers)
  "Send a form of ANSWER as a browser sends it untouched, with FIELDS in
place of the page's values of their names and BUTTON (a name or a text)
the submit button pressed: the form FORM names, else the one BUTTON
belongs to, else the first in the page's <main>, else the first."
  (declare (ignore actor htmx target headers))
  (let* ((options (loop for (key value) on options by #'cddr
                        unless (member key '(:form :fields :button)) append (list key value)))
         (chosen (cond (form (or (form answer form)
                                 (error "The page ~a has no form ~s" (answer-path answer) form)))
                       (button (or (find-if (lambda (candidate)
                                              (some (lambda (node)
                                                      (and (submit-button-p node)
                                                           (button-named-p node button)))
                                                    (page-form-controls candidate)))
                                            (page-forms answer))
                                   (error "The page ~a has no form with a button ~s"
                                          (answer-path answer) button)))
                       (t (or (form answer)
                              (error "The page ~a has no form" (answer-path answer))))))
         (pressed (pressed-button chosen button))
         (formaction (and pressed (attribute-value pressed "formaction")))
         (action (cond ((stringp formaction) formaction)
                       ((form-action chosen))
                       (t (answer-path answer))))
         (sent (replace-fields (sent-fields chosen pressed) fields)))
    (if (string= (form-method chosen) "post")
        (apply #'request :post action :fields sent :multipart (form-multipart-p chosen) options)
        (apply #'request :get
               (format nil "~a~:[?~;&~]~a"
                       (subseq action 0 (or (position #\# action) (length action)))
                       (find #\? action)
                       (query-string sent))
               options))))

(defun follow (answer &rest options &key actor)
  "GET where ANSWER leads (its LOCATION)."
  (declare (ignore actor))
  (let ((location (location answer)))
    (unless location
      (error "The answer ~a to ~a ~a leads nowhere" (status answer) (answer-method answer)
             (answer-path answer)))
    (apply #'request :get location options)))
