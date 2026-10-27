;;;; mail/html.lisp -- a mail's HTML and text parts from a node tree
;;;; (spec/mail.md 2.1).
;;;;
;;;; A client gives SEND-MAIL its HTML as nodes, as a page is built.  The
;;;; tree is first checked against the mail allow-list, which refuses rather
;;;; than drops: the tree is the client's code, and what a person typed is a
;;;; string in it, which the renderer always escapes.  Checking also makes
;;;; the tree ready to send: a path in a link becomes a whole link, and each
;;;; element's style is its default followed by its own, written again as
;;;; checked.  TUN.HTML's renderer then writes the checked tree inside the
;;;; frame, and the text part is read from the same checked tree.

(in-package #:tun.mail)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; The allow-list

(defparameter +mail-elements+
  '("a" "p" "h1" "h2" "h3" "ul" "ol" "li" "strong" "em" "br" "hr" "span" "div" "img"
    "table" "caption" "thead" "tbody" "tfoot" "tr" "th" "td")
  "The elements a mail's tree may hold.")

(defparameter +mail-attributes+
  '((t "style" "title" "lang" "dir")
    ("a" "href")
    ("img" "src" "alt" "width" "height")
    ("th" "colspan" "rowspan" "scope")
    ("td" "colspan" "rowspan" "scope"))
  "The attributes each element may carry: an element's name, or T for every
element, then the attributes' names.")

(defparameter +mail-style-properties+
  '("color" "background-color" "font-size" "font-weight" "font-style" "line-height"
    "text-align" "text-decoration" "vertical-align" "width" "max-width" "height"
    "margin" "margin-top" "margin-right" "margin-bottom" "margin-left"
    "padding" "padding-top" "padding-right" "padding-bottom" "padding-left"
    "border" "border-top" "border-bottom" "border-radius")
  "The properties a style attribute may set.")

(defparameter +style-value+
  (cl-ppcre:create-scanner "^(?:[A-Za-z0-9#.,% -]|[rR][gG][bB][aA]?\\([0-9.,% ]*\\))+$")
  "What a style's value may be: ASCII letters and digits, spaces, # . , % -,
and rgb() or rgba() of numbers.  No other function, so no url() or
expression(), and no quotes, backslashes or !important.")

(define-condition mail-html-refused (error)
  ((reason :initarg :reason :reader mail-html-refused-reason))
  (:report (lambda (c s) (write-string (mail-html-refused-reason c) s)))
  (:documentation "A mail's tree holds something outside the allow-list or
the node grammar; the reason says what, in Norwegian."))

(defun refuse-html (control &rest arguments)
  (error 'mail-html-refused :reason (apply #'format nil control arguments)))

(defparameter +mail-tree-depth+ 200
  "The deepest a mail's tree may nest: deeper is refused, not followed until
the stack runs out.")

(defun shown (object)
  "OBJECT as a refusal names it: printed a few levels deep, also when it is
circular, and at most 60 characters."
  (let ((text (if (stringp object)
                  object
                  (let ((*print-circle* t) (*print-level* 3) (*print-length* 8))
                    (prin1-to-string object)))))
    (if (> (length text) 60) (concatenate 'string (subseq text 0 60) "…") text)))

(defun proper-list-p (object)
  "True when OBJECT is a list that ends in NIL; false for a dotted or a
circular one, which the slow pointer and the fast one meet in."
  (do ((fast object (cddr fast))
       (slow object (cdr slow))
       (first t nil))
      (nil)
    (cond ((null fast) (return t))
          ((atom fast) (return nil))
          ((null (cdr fast)) (return t))
          ((atom (cdr fast)) (return nil))
          ((and (not first) (eq fast slow)) (return nil)))))

;;; ------------------------------------------------------------------
;;; Links

(defun ascii-downcase (char)
  "CHAR in lower case when it is an ASCII capital, else CHAR: unlike
CHAR-DOWNCASE, no other letter is folded, so no look-alike passes for one."
  (if (char<= #\A char #\Z) (code-char (+ (char-code char) 32)) char))

(defun scheme-p (scheme url)
  "True when URL starts with SCHEME, in lower case, in any ASCII case."
  (and (>= (length url) (length scheme))
       (loop for expected across scheme
             for char across url
             always (char= expected (ascii-downcase char)))))

(defun check-url-characters (url name tag)
  "Refuse URL, the attribute NAME on TAG, when it holds a space, a control
character or a backslash: browsers drop or reinterpret those, so a URL that
holds one may not be the URL that was checked."
  (when (find-if (lambda (char)
                   (or (<= (char-code char) 32) (<= 127 (char-code char) 160) (char= char #\\)))
                 url)
    (refuse-html "~a på <~a> kan ikke ha mellomrom, kontrolltegn eller \\ i e-post: «~a»"
                 name tag (shown url))))

(defun mail-link (url)
  "The href URL as the mail writes it: a whole link as given, or a path made
whole with the server's public URL."
  (check-url-characters url "href" "a")
  (cond ((some (lambda (scheme) (scheme-p scheme url)) '("https://" "http://" "mailto:"))
         url)
        ((and (plusp (length url)) (char= (char url 0) #\/)
              (not (and (> (length url) 1) (member (char url 1) '(#\/ #\\)))))
         (absolute-url url))
        (t (refuse-html "lenken «~a» må begynne med https://, http://, mailto: eller /"
                        (shown url)))))

(defun image-source (url)
  "The src URL of an image, which must be https."
  (check-url-characters url "src" "img")
  (unless (scheme-p "https://" url)
    (refuse-html "bildet «~a» må ha en adresse som begynner med https://" (shown url)))
  url)

;;; ------------------------------------------------------------------
;;; Style

(defparameter +default-styles+
  '(("h1" "font-size: 24px" "line-height: 1.25" "margin: 0 0 16px")
    ("h2" "font-size: 20px" "line-height: 1.3" "margin: 24px 0 8px")
    ("h3" "font-size: 17px" "line-height: 1.4" "margin: 20px 0 8px")
    ("a" "color: #1d4ed8" "text-decoration: underline")
    ("img" "max-width: 100%" "height: auto" "border: 0")
    ("table" "width: 100%" "border-collapse: collapse" "margin: 0 0 16px")
    ("th" "padding: 6px 8px" "text-align: left" "vertical-align: top"
     "border-bottom: 1px solid #d4d4d8")
    ("td" "padding: 6px 8px" "text-align: left" "vertical-align: top"
     "border-bottom: 1px solid #e4e4e7")
    ("hr" "border: 0" "border-top: 1px solid #e4e4e7" "margin: 24px 0"))
  "The declarations each element's style starts with, so that a tree without
styles reads well on a phone (spec/mail.md 2.1, the frame).  A paragraph, a
list and the inline elements keep the mail app's own.")

(defun checked-style (text tag)
  "The declarations of TEXT, the style attribute of TAG, each as
\"property: value\", refusing any outside the list."
  (loop for part in (cl-ppcre:split ";" text)
        for declaration = (trim part)
        unless (string= declaration "")
          collect (let ((colon (position #\: declaration)))
                    (unless colon
                      (refuse-html "stilen «~a» på <~a> mangler «:»" (shown declaration) tag))
                    (let ((property (trim (subseq declaration 0 colon)))
                          (value (trim (subseq declaration (1+ colon)))))
                      ;; ASCII before lower case, so no other letter folds into a name.
                      (unless (and (every (lambda (char)
                                            (or (char<= #\a (ascii-downcase char) #\z)
                                                (char= char #\-)))
                                          property)
                                   (member (string-downcase property) +mail-style-properties+
                                           :test #'string=))
                        (refuse-html "stilen «~a» kan ikke brukes i e-post" (shown property)))
                      (unless (cl-ppcre:scan +style-value+ value)
                        (refuse-html "verdien «~a» for ~(~a~) kan ikke brukes i e-post"
                                     (shown value) property))
                      (format nil "~(~a~): ~a" property value)))))

;;; ------------------------------------------------------------------
;;; Checking the tree

(defun attribute-allowed-p (tag name)
  (some (lambda (entry)
          (and (or (eq (first entry) t) (string= (first entry) tag))
               (member name (rest entry) :test #'string=)))
        +mail-attributes+))

(defun checked-attributes (tag attributes)
  "ATTRIBUTES, the property list of an element TAG, checked and ready to
write: a path link made whole, the style the default's and TAG's own."
  (unless (and (proper-list-p attributes) (evenp (length attributes)))
    (refuse-html "(:@ …) på <~a> må ha et navn og en verdi for hvert attributt" tag))
  (let ((style (rest (assoc tag +default-styles+ :test #'string=)))
        (checked '()))
    (loop for (key value) on attributes by #'cddr
          do (unless (keywordp key)
               (refuse-html "~a på <~a> er ikke et attributtnavn; ~
                             et navn er et nøkkelord, som :href"
                            (shown key) tag))
             (let ((name (string-downcase (symbol-name key))))
               (unless (attribute-allowed-p tag name)
                 (refuse-html "attributtet ~a kan ikke brukes på <~a> i e-post" name tag))
               (when value
                 (unless (or (stringp value) (numberp value))
                   (refuse-html "attributtet ~a på <~a> må være en tekst eller et tall, ikke ~a"
                                name tag (shown value)))
                 ;; The keyword in its usual case, so :|href| is read as :href later.
                 (let ((text (princ-to-string value))
                       (key (intern (string-upcase name) "KEYWORD")))
                   (cond ((string= name "style")
                          (setf style (append style (checked-style text tag))))
                         ((string= name "href") (push (list key (mail-link text)) checked))
                         ((string= name "src") (push (list key (image-source text)) checked))
                         (t (push (list key text) checked)))))))
    (append (and style (list :style (format nil "~{~a~^; ~}" style)))
            (reduce #'append (reverse checked)))))

(defun checked-element (element depth)
  "ELEMENT, (:tag [(:@ ...)] child...), checked and ready to write; it is
DEPTH levels into the tree."
  (unless (proper-list-p element)
    (refuse-html "«~a» er ikke en node: lista er ikke avsluttet" (shown element)))
  (when (eq (first element) :@)
    (refuse-html "(:@ …) må stå rett etter taggen: «~a»" (shown element)))
  (multiple-value-bind (tag attributes children) (node-parts element)
    (unless (member tag +mail-elements+ :test #'string=)
      (refuse-html "<~a> kan ikke brukes i e-post" tag))
    (let ((attributes (checked-attributes tag attributes)))
      `(,(first element) ,@(and attributes `((:@ ,@attributes)))
        ,@(mapcar (lambda (child) (checked-node child (1+ depth))) children)))))

(defun checked-node (node &optional (depth 0))
  "NODE, DEPTH levels into the tree, checked against the mail allow-list and
the node grammar, ready to render; anything else is refused with
MAIL-HTML-REFUSED."
  (when (> depth +mail-tree-depth+)
    (refuse-html "html er dypere enn ~d nivåer" +mail-tree-depth+))
  (cond ((null node) nil)
        ((or (stringp node) (numberp node)) node)
        ((and (consp node) (keywordp (first node))) (checked-element node depth))
        ((and (consp node) (proper-list-p node))
         (mapcar (lambda (child) (checked-node child (1+ depth))) node))
        (t (refuse-html "«~a» er ikke en node: en node er en tekst, et tall, en liste eller ~
                         et element som (:p …)"
                        (shown node)))))

;;; ------------------------------------------------------------------
;;; The frame

(defparameter +mail-column-style+
  (format nil "~{~a~^; ~}"
          `("box-sizing: border-box" "max-width: 600px" "margin: 0 auto" "padding: 24px 16px"
            ,(concatenate 'string "font-family: -apple-system, BlinkMacSystemFont, Segoe UI, "
                          "Roboto, Helvetica, Arial, sans-serif")
            "font-size: 16px" "line-height: 1.5" "color: #18181b"
            "overflow-wrap: break-word" "word-break: break-word"))
  "The column a mail's tree is read in: narrow enough to read on a desktop,
the whole width on a phone, and long words and links broken rather than
widening it.")

(defun mail-frame (tree subject)
  "The whole HTML document of a mail titled SUBJECT holding TREE, checked."
  (check-type subject (or null string))
  (list (trusted "<!doctype html>")
        `(:html (:@ :lang "no")
                (:head (:meta (:@ :charset "utf-8"))
                       (:meta (:@ :name "viewport" :content "width=device-width, initial-scale=1"))
                       (:title ,(or subject "")))
                (:body (:@ :style "margin: 0; padding: 0; background-color: #ffffff")
                       (:div (:@ :style ,+mail-column-style+) ,tree)))))

;;; ------------------------------------------------------------------
;;; The text part

(defstruct (text-writer (:constructor make-text-writer ()))
  "The text part as it is written: what is owed before the next word, and
the indent of a line inside a list."
  (out (make-string-output-stream))
  (started nil)
  (pending nil :type (member nil :line :paragraph))
  (space nil)
  (indent "")
  (depth 0))

(defun break-text (writer kind)
  "Owe WRITER a line break, KIND :LINE, or a blank line, :PARAGRAPH, before
its next word; inside a list item, a block only starts a line."
  (let ((kind (if (and (eq kind :paragraph) (plusp (text-writer-depth writer))) :line kind)))
    (unless (eq (text-writer-pending writer) :paragraph)
      (setf (text-writer-pending writer) kind))
    (setf (text-writer-space writer) nil)))

(defun settle-text (writer)
  "Write what WRITER owes before a word: a break and the line's indent, or
a space."
  (let ((out (text-writer-out writer)))
    (cond ((and (text-writer-pending writer) (text-writer-started writer))
           (write-string (if (eq (text-writer-pending writer) :paragraph)
                             (format nil "~%~%")
                             (format nil "~%"))
                         out)
           (write-string (text-writer-indent writer) out))
          ((and (text-writer-space writer) (text-writer-started writer))
           (write-char #\Space out)))
    (setf (text-writer-pending writer) nil
          (text-writer-space writer) nil
          (text-writer-started writer) t)))

(defun write-words (writer string)
  "Write STRING with its spaces and line breaks collapsed to one space, as
the HTML shows it."
  (loop for char across string
        do (if (member char '(#\Space #\Tab #\Newline #\Return #\Page))
               (setf (text-writer-space writer) t)
               (progn
                 (when (or (text-writer-pending writer) (text-writer-space writer)
                           (not (text-writer-started writer)))
                   (settle-text writer))
                 (write-char char (text-writer-out writer))))))

(defun write-literal (writer string)
  "Write STRING as it is, after what WRITER owes."
  (settle-text writer)
  (write-string string (text-writer-out writer)))

(defun inline-text (nodes)
  "NODES as one line of text, as a link's text is read."
  (let ((writer (make-text-writer)))
    (dolist (node nodes) (write-text writer node))
    (get-output-stream-string (text-writer-out writer))))

(defun link-text (url children)
  "A link to URL with CHILDREN as its text: «text (url)», or URL alone when
the text says nothing more."
  (let ((text (trim (inline-text children)))
        (target (if (scheme-p "mailto:" url) (subseq url 7) url)))
    (if (or (string= text "") (string= text url) (string= text target))
        target
        (format nil "~a (~a)" text target))))

(defun write-list (writer children ordered)
  "Write the items of a list, CHILDREN, each on its own line, numbered when
ORDERED, a list inside an item indented two spaces."
  (break-text writer :paragraph)
  (let ((indent (text-writer-indent writer))
        (number 0))
    (dolist (child children)
      (if (and (consp child) (keywordp (first child))
               (string= (node-parts child) "li"))
          (let ((marker (if ordered (format nil "~d. " (incf number)) "- ")))
            (break-text writer :line)
            (write-literal writer marker)
            (setf (text-writer-indent writer)
                  (concatenate 'string indent
                               (make-string (length marker) :initial-element #\Space)))
            (incf (text-writer-depth writer))
            (multiple-value-bind (tag attributes item) (node-parts child)
              (declare (ignore tag attributes))
              (dolist (node item) (write-text writer node)))
            (decf (text-writer-depth writer))
            (setf (text-writer-indent writer) indent))
          (write-text writer child))))
  (break-text writer :paragraph))

(defun write-row (writer cells)
  "Write a table row, CELLS, on its own line, its cells separated by « | »."
  (break-text writer :line)
  (let ((first t))
    (dolist (cell cells)
      (if (and (consp cell) (keywordp (first cell)) (member (node-parts cell) '("td" "th")
                                                            :test #'string=))
          (progn
            (unless first (write-literal writer " | "))
            (setf first nil)
            (dolist (node (nth-value 2 (node-parts cell))) (write-text writer node)))
          (write-text writer cell))))
  (break-text writer :line))

(defun write-text (writer node)
  "Write NODE, part of a checked tree, as the text part reads it
(spec/mail.md 2.1, the text part)."
  (cond ((null node))
        ((stringp node) (write-words writer node))
        ((numberp node) (write-words writer (princ-to-string node)))
        ((keywordp (first node))
         (multiple-value-bind (tag attributes children) (node-parts node)
           (flet ((block-of (nodes)
                    (break-text writer :paragraph)
                    (dolist (child nodes) (write-text writer child))
                    (break-text writer :paragraph)))
             (cond ((string= tag "a")
                    (let ((url (getf attributes :href)))
                      (if url
                          (write-words writer (link-text url children))
                          (dolist (child children) (write-text writer child)))))
                   ((string= tag "br")
                    (setf (text-writer-pending writer)
                          (if (text-writer-pending writer) :paragraph :line)))
                   ((string= tag "hr") (block-of '("---")))
                   ((string= tag "img")
                    (let ((alt (getf attributes :alt)))
                      (when alt (write-words writer alt))))
                   ((string= tag "ul") (write-list writer children nil))
                   ((string= tag "ol") (write-list writer children t))
                   ((string= tag "tr") (write-row writer children))
                   ((string= tag "caption")
                    (break-text writer :line)
                    (dolist (child children) (write-text writer child))
                    (break-text writer :line))
                   ((member tag '("p" "h1" "h2" "h3" "div" "table" "li") :test #'string=)
                    (block-of children))
                   (t (dolist (child children) (write-text writer child)))))))
        (t (dolist (child node) (write-text writer child)))))

(defun tree-text (tree)
  "The text part of a mail made from TREE, checked."
  (let ((writer (make-text-writer)))
    (write-text writer tree)
    (get-output-stream-string (text-writer-out writer))))

;;; ------------------------------------------------------------------
;;; The parts

(defun mail-parts (html subject text)
  "Values the HTML part and the text part of a mail with the node tree HTML,
SUBJECT and TEXT: TEXT when given, else the text made from HTML.  When HTML
is NIL, values NIL and TEXT.  A tree that is refused is an input error on
html, collected for COLLECTING-INPUT-ERRORS, and its parts are NIL and TEXT."
  (handler-case
      (cond ((null html) (values nil text))
            ((stringp html)
             (refuse-html "html er noder, som (:p \"…\"), ikke tekst med HTML; ~
                           ren tekst går i text"))
            (t (let ((tree (checked-node html)))
                 (values (render-html (mail-frame tree subject))
                         (or text (tree-text tree))))))
    (mail-html-refused (refusal)
      (input-error "html" "~a" (mail-html-refused-reason refusal))
      (values nil text))))

(defun checked-parts (html subject text)
  "Values the HTML and the text a mail with HTML, SUBJECT and TEXT stores,
each checked as its field checks it; the errors are collected for
COLLECTING-INPUT-ERRORS.  Text is required unless the tree was refused,
which is then the one error."
  (multiple-value-bind (html-part text-part) (mail-parts html subject text)
    (values (mail-argument "html" html-part)
            (mail-argument "text" text-part :required (or text (null html) html-part)))))

(defun render-mail (html &key subject text)
  "Values the HTML part and the text part that SEND-MAIL would store for the
node tree HTML, SUBJECT and TEXT, with the same checks, storing nothing
(spec/mail.md 2.1).  A tree outside the allow-list fails with invalid_input."
  (values-list
   (collecting-input-errors
     (let ((subject (mail-argument "subject" subject)))
       (if html
           (multiple-value-list (checked-parts html subject text))
           (input-error "html" "må fylles ut"))))))
