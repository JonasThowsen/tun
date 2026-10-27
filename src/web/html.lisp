;;;; web/html.lisp -- HTML as data.  A node is a string (escaped), a number,
;;;; a list of nodes, or (:tag [(:@ :attr value ...)] child...).  Core's own
;;;; literals that must not be escaped (doctype, the style sheet) are TRUSTED
;;;; objects only core can make.  Output from extensions (screens) is wrapped
;;;; with UNTRUSTED and rendered through an allow-list: safe elements and
;;;; attributes only, no scripts, no event handlers, no javascript: URLs,
;;;; and of htmx's attributes only those that cannot run code.

(defpackage #:tun.html
  (:use #:cl)
  (:export #:render-html #:escape-html #:trusted #:untrusted))

(in-package #:tun.html)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +void-elements+ '("area" "br" "col" "hr" "img" "input" "link" "meta"))

(defstruct (trusted-html (:constructor trusted (text))) (text "" :type string))
(defstruct (untrusted-html (:constructor untrusted (nodes))) nodes)

(defparameter +safe-elements+
  '("a" "b" "br" "caption" "code" "dd" "div" "dl" "dt" "em" "h1" "h2" "h3" "h4" "h5" "h6" "hr" "i"
    "li" "ol" "p" "pre" "section" "small" "span" "strong" "table" "tbody" "td" "tfoot" "th" "thead"
    "tr" "ul" "form" "input" "select" "option" "button" "label" "fieldset" "legend" "textarea"
    ;; What the design system's components are made of (spec/ui.md 5).
    "abbr" "article" "aside" "col" "colgroup" "details" "dialog" "figcaption" "figure" "footer"
    "header" "hgroup" "img" "kbd" "main" "mark" "menu" "meter" "nav" "optgroup" "output" "progress"
    "s" "search" "sub" "summary" "sup" "time"
    ;; Inline SVG for icons: shapes only, nothing that loads or runs.
    "svg" "g" "path" "circle" "ellipse" "line" "polyline" "polygon" "rect"))

(defparameter +safe-attributes+
  '("class" "id" "title" "href" "name" "value" "type" "method" "action" "for" "colspan" "rowspan"
    "selected" "checked" "disabled" "required" "min" "max" "step" "placeholder" "lang" "role"
    "accept" "alt" "autocomplete" "autofocus" "cols" "command" "commandfor" "datetime" "dir" "enterkeyhint"
    "form" "formaction" "formmethod" "formnovalidate" "headers" "height" "hidden" "high" "inert"
    "inputmode" "label" "loading" "low" "maxlength" "minlength" "multiple" "novalidate" "open"
    "optimum" "pattern" "popover" "popovertarget" "popovertargetaction" "readonly" "reversed"
    "rows" "scope" "size" "spellcheck" "src" "start" "tabindex" "width"
    ;; A form that sends files, a link that downloads one, an image decoded aside.
    "enctype" "download" "decoding"
    "viewbox" "xmlns" "fill" "stroke" "stroke-width" "stroke-linecap" "stroke-linejoin" "d" "cx"
    "cy" "r" "rx" "ry" "x" "y" "x1" "y1" "x2" "y2" "points" "focusable"))

(defparameter +htmx-attributes+
  '("hx-get" "hx-post" "hx-target" "hx-swap" "hx-trigger" "hx-select" "hx-select-oob"
    "hx-swap-oob" "hx-push-url" "hx-replace-url" "hx-indicator" "hx-include" "hx-vals"
    "hx-confirm" "hx-boost" "hx-disable" "hx-sync" "hx-preserve" "hx-validate")
  "The htmx attributes extension output may carry (spec/ui.md 5), each also
with the modifiers in +HTMX-MODIFIERS+.  Left out are those that run code or
reach further, such as hx-on, hx-headers, hx-config and hx-status; the page's
htmx refuses to run code besides (TUN.UI's kit script).")

(defparameter +htmx-modifiers+ '("inherited" "append")
  "What may follow an allowed htmx attribute's name after a colon, as in
hx-target:inherited.")

(defparameter +url-attributes+ '("href" "action" "src" "formaction" "hx-get" "hx-post")
  "Attributes whose value is fetched or followed: only same-site paths and http(s) URLs.")

(defvar *untrusted* nil "True while rendering extension output.")

(defun safe-url-p (value)
  (let ((v (string-left-trim '(#\Space #\Tab #\Newline #\Return) value)))
    (or (and (plusp (length v)) (char= (char v 0) #\/) (not (and (> (length v) 1) (char= (char v 1) #\/))))
        (and (plusp (length v)) (char= (char v 0) #\#))
        (eql 0 (search "https://" v :test #'char-equal))
        (eql 0 (search "http://" v :test #'char-equal)))))

(defun htmx-name (name)
  "The htmx attribute NAME stands for, without the data- that htmx also
reads (data-hx-get is hx-get) and without its modifiers (hx-target:inherited
is hx-target), or NIL when it is not one of htmx's.  The second value is
true when every modifier is one of +HTMX-MODIFIERS+."
  (let ((bare (if (eql 0 (search "data-" name)) (subseq name 5) name)))
    (when (eql 0 (search "hx-" bare))
      (destructuring-bind (base &rest modifiers) (cl-ppcre:split ":" bare)
        (values base (every (lambda (modifier)
                              (member modifier +htmx-modifiers+ :test #'string=))
                            modifiers))))))

(defun attribute-allowed-p (name value)
  (or (not *untrusted*)
      (multiple-value-bind (htmx modifiers-allowed) (htmx-name name)
        (and (if htmx
                 (and modifiers-allowed (member htmx +htmx-attributes+ :test #'string=))
                 (or (member name +safe-attributes+ :test #'string=)
                     (eql 0 (search "data-" name))
                     (eql 0 (search "aria-" name))))
             (or (not (member (or htmx name) +url-attributes+ :test #'string=))
                 (eq value t)
                 (safe-url-p (princ-to-string value)))))))

(defun escape-html (string &optional stream)
  (flet ((emit (out)
           (loop for ch across string
                 do (case ch
                      (#\& (write-string "&amp;" out))
                      (#\< (write-string "&lt;" out))
                      (#\> (write-string "&gt;" out))
                      (#\" (write-string "&quot;" out))
                      (#\' (write-string "&#39;" out))
                      (t (write-char ch out))))))
    (if stream (emit stream) (with-output-to-string (out) (emit out)))))

(defun render-node (node out)
  (cond ((null node))
        ((stringp node) (escape-html node out))
        ((numberp node) (format out "~a" node))
        ((trusted-html-p node)
         (if *untrusted*
             (escape-html (trusted-html-text node) out)
             (write-string (trusted-html-text node) out)))
        ((untrusted-html-p node)
         (let ((*untrusted* t)) (render-node (untrusted-html-nodes node) out)))
        ((and (consp node) (keywordp (first node)))
         (let* ((tag (string-downcase (symbol-name (first node))))
                (rest (rest node))
                (attrs (when (and (consp (first rest)) (eq (first (first rest)) :@))
                         (rest (first rest))))
                (children (if (and (consp (first rest)) (eq (first (first rest)) :@)) (rest rest) rest)))
           (if (and *untrusted* (not (member tag +safe-elements+ :test #'string=)))
               (escape-html (format nil "[~a fjernet]" tag) out)
               (progn
                 (format out "<~a" tag)
                 (loop for (key value) on attrs by #'cddr
                       for name = (string-downcase (symbol-name key))
                       when (and value (attribute-allowed-p name value))
                         do (format out " ~a" name)
                            (unless (eq value t)
                              (write-string "=\"" out)
                              (escape-html (princ-to-string value) out)
                              (write-char #\" out)))
                 (write-char #\> out)
                 (unless (member tag +void-elements+ :test #'string=)
                   (dolist (child children) (render-node child out))
                   (format out "</~a>" tag))))))
        ((consp node) (dolist (child node) (render-node child out)))
        (t (escape-html (princ-to-string node) out))))

(defun render-html (node)
  (with-output-to-string (out) (render-node node out)))
