;;;; web/ui/kit.lisp -- DEFINE-COMPONENT, the registry of components, the
;;;; tokens and base styles, and the stylesheet and script built from them
;;;; (spec/ui.md 3-5).
;;;;
;;;; A component is an ordinary function from an options list and children
;;;; to markup.  DEFINE-COMPONENT also records its CSS, script,
;;;; documentation and examples, which the stylesheet, the script and the
;;;; specimen are built from.

(in-package #:tun.ui)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; The registry

(defstruct (component (:constructor %make-component))
  "What DEFINE-COMPONENT records about a component besides its function."
  (name nil :type symbol :read-only t)
  (group "" :type string)
  (doc "" :type string)
  (source "" :type string)
  (css "" :type string)
  (script "" :type string)
  ;; Each example is (TITLE SOURCE-TEXT THUNK LAYOUT): THUNK returns its
  ;; markup, and LAYOUT is :ROW (side by side) or :STACK (one under another,
  ;; full width) for the specimen.
  (examples '() :type list)
  (internal-p nil :type boolean))

(defvar *lock* (sb-thread:make-mutex :name "tun.ui registry"))

(defvar *components* '()
  "Every component, in the order they were first defined.  Guarded by *LOCK*.")

(defvar *assets* nil
  "The stylesheet and script built from *COMPONENTS*, or NIL when a component
changed since.  Guarded by *LOCK*.")

(defun root-class (name)
  "The class of component NAME's outermost element: tun-NAME."
  (format nil "tun-~(~a~)" name))

(defun all-components (&key internal)
  "The components in definition order; with INTERNAL, also the specimen's own."
  (sb-thread:with-mutex (*lock*)
    (remove-if (lambda (component) (and (component-internal-p component) (not internal)))
               *components*)))

(defun find-component (name)
  "The component named NAME (a symbol or a string), or NIL."
  (find-if (lambda (component) (string-equal (symbol-name (component-name component))
                                             (string name)))
           (all-components :internal t)))

(defun register-component (component)
  "Add COMPONENT, or replace the one of the same name in its place."
  (let ((problem (scoped-css-problem (component-css component)
                                     (root-class (component-name component)))))
    (when problem
      (error "Component ~(~a~): ~a" (component-name component) problem)))
  (sb-thread:with-mutex (*lock*)
    (let ((tail (member (component-name component) *components* :key #'component-name)))
      (if tail
          (setf *components* (substitute component (first tail) *components*))
          (setf *components* (append *components* (list component)))))
    (setf *assets* nil))
  component)

;;; ------------------------------------------------------------------
;;; Scoped CSS: every top-level selector starts at the root class

(defun strip-css-comments (css)
  (cl-ppcre:regex-replace-all "(?s)/\\*.*?\\*/" css ""))

(defun css-rules (css)
  "The top-level rules of CSS (without comments) as (PRELUDE . BODY) pairs.
A statement that ends with a semicolon outside any block is returned with a
NIL body."
  (let ((rules '()) (start 0) (depth 0) (open nil) (quote-char nil))
    (loop for i from 0 below (length css)
          for c = (char css i)
          do (cond (quote-char (when (char= c quote-char) (setf quote-char nil)))
                   ((member c '(#\" #\')) (setf quote-char c))
                   ((char= c #\{)
                    (when (zerop depth) (setf open i))
                    (incf depth))
                   ((char= c #\})
                    (decf depth)
                    (when (zerop depth)
                      (push (cons (string-trim '(#\Space #\Tab #\Newline #\Return)
                                               (subseq css start open))
                                  (subseq css (1+ open) i))
                            rules)
                      (setf start (1+ i))))
                   ((and (char= c #\;) (zerop depth))
                    (push (cons (string-trim '(#\Space #\Tab #\Newline #\Return)
                                             (subseq css start i))
                                nil)
                          rules)
                    (setf start (1+ i)))))
    (nreverse rules)))

(defun split-selectors (prelude)
  "The selectors in the selector list PRELUDE: commas inside parentheses do
not split."
  (let ((parts '()) (start 0) (depth 0))
    (loop for i from 0 below (length prelude)
          for c = (char prelude i)
          do (case c
               (#\( (incf depth))
               (#\) (decf depth))
               (#\, (when (zerop depth)
                      (push (subseq prelude start i) parts)
                      (setf start (1+ i))))))
    (push (subseq prelude start) parts)
    (mapcar (lambda (part) (string-trim '(#\Space #\Tab #\Newline #\Return) part))
            (nreverse parts))))

(defun identifier-char-p (char)
  (or (alphanumericp char) (char= char #\-) (char= char #\_)))

(defun starts-at-root-p (selector root)
  (let ((prefix (format nil ".~a" root)))
    (and (eql 0 (search prefix selector))
         (or (= (length selector) (length prefix))
             (not (identifier-char-p (char selector (length prefix))))))))

(defun scoped-css-problem (css root)
  "NIL when every rule of CSS is scoped to the class ROOT (spec/ui.md 5),
else what is wrong.  @media, @supports and @container are looked into;
@keyframes names must start with ROOT."
  (labels ((check (rules)
             (loop for (prelude . body) in rules
                   for problem
                   = (cond ((null body)
                            (format nil "~s is not a rule" prelude))
                           ((or (eql 0 (search "@media" prelude))
                                (eql 0 (search "@supports" prelude))
                                (eql 0 (search "@container" prelude)))
                            (check (css-rules body)))
                           ((eql 0 (search "@keyframes" prelude))
                            (let ((name (string-trim " " (subseq prelude (length "@keyframes")))))
                              (unless (eql 0 (search root name))
                                (format nil "keyframes ~a must start with ~a" name root))))
                           ((char= (char prelude 0) #\@)
                            (format nil "~a is not allowed in a component" prelude))
                           (t (let ((stray (find-if-not (lambda (selector)
                                                          (starts-at-root-p selector root))
                                                        (split-selectors prelude))))
                                (when stray
                                  (format nil "selector ~s does not start with .~a"
                                          stray root)))))
                   when problem return problem)))
    (check (css-rules (strip-css-comments css)))))

;;; ------------------------------------------------------------------
;;; DEFINE-COMPONENT

(defparameter +clauses+ '(:group :doc :source :css :script :examples :internal)
  "The clauses a DEFINE-COMPONENT form may start its body with.")

(defun example-source (forms)
  "FORMS as the specimen shows them, in lowercase."
  (let ((*print-case* :downcase) (*print-pretty* t) (*print-right-margin* 72))
    (format nil "~{~s~^~%~}" forms)))

(defmacro define-component (name (options &rest more) &body clauses-and-body)
  "Define component NAME (spec/ui.md 5).  OPTIONS is the lambda list its
options plist is destructured with, normally (&key ...); MORE is empty or
(&rest CHILDREN).  The body starts with clauses:

  (:group \"Skjema\")             where the specimen lists it
  (:doc \"...\")                  when to use it, in Norwegian
  (:source \"...\")               what it was converted from
  (:css \"...\")                  its CSS, every selector starting at .tun-NAME
  (:script \"...\")               JavaScript for the shared script
  (:examples (\"Title\" form...) ((\"Title\" :layout :stack) form...) ...)
  (:internal t)                  the specimen's own, not listed

and the rest is the code that returns its markup.  The component is the
macro NAME, called as (NAME (KEY VALUE...) CHILD...) with the values
evaluated, and the function NAME*, called as (NAME* PLIST CHILD...) where a
plist is computed or the component is passed to APPLY or MAPCAR."
  (let* ((clauses (loop while (and (consp (first clauses-and-body))
                                   (member (first (first clauses-and-body)) +clauses+))
                        collect (pop clauses-and-body)))
         (body clauses-and-body)
         (internal (second (assoc :internal clauses)))
         (doc (second (assoc :doc clauses)))
         (examples (rest (assoc :examples clauses)))
         (options-var (gensym "OPTIONS"))
         (function (intern (format nil "~a*" (symbol-name name)))))
    (unless (or (null more) (and (eq (first more) '&rest) (symbolp (second more))
                                 (null (cddr more))))
      (error "define-component ~s: after the options come nothing or (&rest CHILDREN)" name))
    ;; A stray double quote inside the CSS would otherwise split it into
    ;; several values, and all but the first would be dropped unseen.
    (dolist (clause clauses)
      (unless (or (eq (first clause) :examples) (= (length clause) 2))
        (error "define-component ~s: ~s takes one value" name (first clause))))
    (unless (or internal (and (stringp doc) (assoc :source clauses) (assoc :group clauses)
                              examples))
      (error "define-component ~s needs :doc, :source, :group and :examples" name))
    `(progn
       (defun ,function (&optional ,options-var ,@more)
         ,@(when (stringp doc) (list doc))
         (check-type ,options-var list)
         (destructuring-bind ,options ,options-var
           ,@body))
       (defmacro ,name (&optional options &rest children)
         ,(format nil "The component ~(~a~): (~:*~(~a~) (KEY VALUE...) CHILD...).~@[~%~%~a~]"
                  name (and (stringp doc) doc))
         (unless (listp options)
           (error "~(~a~): the options are a list (KEY VALUE...), not ~s" ',name options))
         (list* ',function (cons 'list options) children))
       (export '(,name ,function))
       (register-component
        (%make-component
         :name ',name
         :group ,(or (second (assoc :group clauses)) "")
         :doc ,(or doc "")
         :source ,(or (second (assoc :source clauses)) "")
         :css ,(or (second (assoc :css clauses)) "")
         :script ,(or (second (assoc :script clauses)) "")
         :internal-p ,(and internal t)
         :examples (list ,@(loop for (heading . forms) in examples
                                 collect (destructuring-bind (title &key (layout :row))
                                             (if (listp heading) heading (list heading))
                                           (check-type layout (member :row :stack))
                                           `(list ,title ,(example-source forms)
                                                  (lambda () (list ,@forms)) ,layout))))))
       ',name)))

;;; ------------------------------------------------------------------
;;; Helpers for component bodies

(defun attrs (&rest plists)
  "The attribute list (:@ ...) of the property lists PLISTS joined: a later
value for a key replaces an earlier one, and keys whose value is NIL are
left out."
  (let ((joined '()))
    (dolist (plist plists)
      (loop for (key value) on plist by #'cddr
            do (setf joined (append (loop for (k v) on joined by #'cddr
                                          unless (eq k key) append (list k v))
                                    (list key value)))))
    (cons :@ (loop for (key value) on joined by #'cddr
                   when value append (list key value)))))

(defun option-string (value)
  "VALUE, an option given as a keyword or a string, as an attribute value:
:outline is \"outline\".  NIL stays NIL."
  (etypecase value
    (null nil)
    (keyword (string-downcase (symbol-name value)))
    (string value)))

(defun heading-tag (level)
  "The heading element for heading LEVEL, 2 to 4."
  (ecase level (2 :h2) (3 :h3) (4 :h4)))

(defvar *element-ids* (list 0))

(defun element-id (prefix)
  "A new id for an element, PREFIX followed by a number unique in this
process: for label for=, aria-describedby and aria-controls."
  (format nil "~a-~d" prefix (sb-ext:atomic-incf (car *element-ids*))))

;;; ------------------------------------------------------------------
;;; Tokens and base styles (spec/ui.md 3)

(defparameter +reset-css+ "
*, ::before, ::after, ::backdrop { box-sizing: border-box; margin: 0; padding: 0;
  border: 0 solid var(--border); }
html { line-height: 1.5; -webkit-text-size-adjust: 100%; text-size-adjust: 100%; tab-size: 4;
  font-family: var(--font-sans); -webkit-tap-highlight-color: transparent; }
h1, h2, h3, h4, h5, h6 { font-size: inherit; font-weight: inherit; }
a { color: inherit; text-decoration: inherit; }
b, strong { font-weight: var(--font-weight-semibold); }
code, kbd, samp, pre { font-family: var(--font-mono); font-size: 1em; }
small { font-size: 80%; }
table { text-indent: 0; border-color: inherit; border-collapse: collapse; }
ol, ul, menu { list-style: none; }
img, svg, video, canvas { display: block; vertical-align: middle; }
img, video { max-width: 100%; height: auto; }
button, input, select, optgroup, textarea, ::file-selector-button {
  font: inherit; font-feature-settings: inherit; letter-spacing: inherit; color: inherit;
  border-radius: 0; background-color: transparent; opacity: 1; }
::placeholder { opacity: 1; color: var(--muted-foreground); }
textarea { resize: vertical; }
[hidden]:where(:not([hidden='until-found'])) { display: none !important; }
")

(defparameter +tokens-css+ "
:root {
  color-scheme: light dark;
  --background: light-dark(oklch(1 0 0), oklch(0.145 0 0));
  --foreground: light-dark(oklch(0.145 0 0), oklch(0.985 0 0));
  --card: light-dark(oklch(1 0 0), oklch(0.205 0 0));
  --card-foreground: light-dark(oklch(0.145 0 0), oklch(0.985 0 0));
  --popover: light-dark(oklch(1 0 0), oklch(0.205 0 0));
  --popover-foreground: light-dark(oklch(0.145 0 0), oklch(0.985 0 0));
  --primary: light-dark(oklch(0.205 0 0), oklch(0.922 0 0));
  --primary-foreground: light-dark(oklch(0.985 0 0), oklch(0.205 0 0));
  --secondary: light-dark(oklch(0.97 0 0), oklch(0.269 0 0));
  --secondary-foreground: light-dark(oklch(0.205 0 0), oklch(0.985 0 0));
  --muted: light-dark(oklch(0.97 0 0), oklch(0.269 0 0));
  --muted-foreground: light-dark(oklch(0.556 0 0), oklch(0.708 0 0));
  --accent: light-dark(oklch(0.97 0 0), oklch(0.269 0 0));
  --accent-foreground: light-dark(oklch(0.205 0 0), oklch(0.985 0 0));
  --border: light-dark(oklch(0.922 0 0), oklch(1 0 0 / 10%));
  --input: light-dark(oklch(0.922 0 0), oklch(1 0 0 / 15%));
  --ring: light-dark(oklch(0.708 0 0), oklch(0.556 0 0));

  /* Status: the strong colour, text on it, and a tinted background. */
  --info: light-dark(oklch(0.546 0.245 262.881), oklch(0.707 0.165 254.624));
  --info-foreground: light-dark(oklch(0.985 0 0), oklch(0.205 0 0));
  --info-soft: light-dark(oklch(0.97 0.014 254.604), oklch(0.282 0.091 267.935));
  --success: light-dark(oklch(0.527 0.154 150.069), oklch(0.792 0.209 151.711));
  --success-foreground: light-dark(oklch(0.985 0 0), oklch(0.205 0 0));
  --success-soft: light-dark(oklch(0.982 0.018 155.826), oklch(0.266 0.065 152.934));
  --warning: light-dark(oklch(0.555 0.163 48.998), oklch(0.828 0.189 84.429));
  --warning-foreground: light-dark(oklch(0.985 0 0), oklch(0.205 0 0));
  --warning-soft: light-dark(oklch(0.987 0.022 95.277), oklch(0.279 0.077 45.635));
  --destructive: light-dark(oklch(0.577 0.245 27.325), oklch(0.704 0.191 22.216));
  --destructive-foreground: light-dark(oklch(0.985 0 0), oklch(0.205 0 0));
  --destructive-soft: light-dark(oklch(0.971 0.013 17.38), oklch(0.258 0.092 26.042));

  --font-sans: ui-sans-serif, system-ui, -apple-system, 'Segoe UI', Roboto, 'Helvetica Neue',
    Arial, sans-serif;
  --font-mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono',
    monospace;
  --text-xs: 0.75rem; --text-xs--line-height: calc(1 / 0.75);
  --text-sm: 0.875rem; --text-sm--line-height: calc(1.25 / 0.875);
  --text-base: 1rem; --text-base--line-height: 1.5;
  --text-lg: 1.125rem; --text-lg--line-height: calc(1.75 / 1.125);
  --text-xl: 1.25rem; --text-xl--line-height: calc(1.75 / 1.25);
  --text-2xl: 1.5rem; --text-2xl--line-height: calc(2 / 1.5);
  --text-3xl: 1.875rem; --text-3xl--line-height: calc(2.25 / 1.875);
  --font-weight-normal: 400; --font-weight-medium: 500;
  --font-weight-semibold: 600; --font-weight-bold: 700;

  --spacing: 0.25rem;
  --radius: 0.625rem;
  --radius-sm: calc(var(--radius) - 4px);
  --radius-md: calc(var(--radius) - 2px);
  --radius-lg: var(--radius);
  --radius-xl: calc(var(--radius) + 4px);
  --radius-full: 9999px;

  --shadow-xs: 0 1px 2px 0 rgb(0 0 0 / 0.05);
  --shadow-sm: 0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1);
  --shadow-md: 0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1);
  --shadow-lg: 0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1);

  --control-height: 2.25rem;
  --control-height-sm: 2rem;
  --control-height-lg: 2.5rem;
  --control-font-size: var(--text-sm);
  --focus-ring: 0 0 0 3px color-mix(in oklab, var(--ring) 50%, transparent);

  --duration-fast: 120ms;
  --duration: 200ms;
  --ease: cubic-bezier(0.4, 0, 0.2, 1);

  --z-sticky: 40;
  --z-dropdown: 50;
  --z-dialog: 100;
  --z-toast: 110;
}
:root[data-theme='light'] { color-scheme: light; }
:root[data-theme='dark'] { color-scheme: dark; }
/* A finger needs a bigger target than a mouse, and a phone zooms into text
   under 16px when it gets focus. */
@media (pointer: coarse) {
  :root {
    --control-height: 2.75rem;
    --control-height-sm: 2.5rem;
    --control-height-lg: 3rem;
    --control-font-size: var(--text-base);
  }
}
@media (prefers-reduced-motion: reduce) {
  :root { --duration-fast: 0ms; --duration: 0ms; }
}
")

(defparameter +base-css+ "
body { min-height: 100dvh; background-color: var(--background); color: var(--foreground);
  font-size: var(--text-base); -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale; }
h1 { font-size: var(--text-2xl); line-height: var(--text-2xl--line-height);
  font-weight: var(--font-weight-semibold); letter-spacing: -0.025em; }
h2 { font-size: var(--text-xl); line-height: var(--text-xl--line-height);
  font-weight: var(--font-weight-semibold); letter-spacing: -0.0125em; }
h3 { font-size: var(--text-lg); line-height: var(--text-lg--line-height);
  font-weight: var(--font-weight-semibold); }
h4 { font-size: var(--text-base); font-weight: var(--font-weight-semibold); }
h1, h2, h3, h4 { text-wrap: balance; }
p { text-wrap: pretty; }
a:not([class]) { text-decoration-line: underline; text-underline-offset: 4px; }
code:not([class]) { border-radius: var(--radius-sm); background-color: var(--muted);
  padding: 0.1em 0.3em; font-size: 0.875em; }
button:not(:disabled), [role='button']:not(:disabled) { cursor: pointer; }
:focus-visible { outline: 2px solid var(--ring); outline-offset: 2px; }
::selection { background-color: color-mix(in oklab, var(--primary) 20%, transparent); }
@media (prefers-reduced-motion: reduce) {
  *, ::before, ::after { animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important; transition-duration: 0.01ms !important;
    scroll-behavior: auto !important; }
}
")

(defparameter +kit-script+ "
// Set up what a component's markup needs once it is in the page: SETUP is
// called with the document when the page has loaded, and with each element
// htmx swaps in afterwards (spec/ui.md 4).
const tunOnContent = (setup) => {
  if (document.readyState === 'loading')
    document.addEventListener('DOMContentLoaded', () => setup(document));
  else setup(document);
  document.addEventListener('htmx:after:settle', (event) => {
    if (event.target instanceof Element && event.target.isConnected) setup(event.target);
  });
};

// htmx runs JavaScript written in markup (hx-on, js: values) and the
// scripts in what it swaps in.  Tun's pages need neither, so this extension,
// the only one the configuration admits, gives htmx a Function that refuses
// and a script policy that empties every script (spec/ui.md 4.1).
window.htmx?.registerExtension('tun', {
  init(api) {
    const refuse = function () {
      throw new Error('Tun runs no JavaScript from markup');
    };
    api.initSecurity({ createHTML: (html) => html, createScript: () => '' }, refuse, refuse);
  },
});

// Preloading (spec/ui.md 4.1): a link htmx boosts loads its page when a
// person shows they will follow it, a pointer resting on it or a press,
// and the click is given that answer instead of asking again.  An answer
// serves only the next htmx request, within ten seconds: every request, a
// GET too, since a GET may change what a page shows, drops the others,
// those still loading too, when it starts and when it ends, and none
// starts while one is under way, so nothing from before a change made here
// is shown.  A page that declines a preload is asked again.
(() => {
  const lifetime = 10000;
  const intent = 100;
  const preloads = new Map();
  let requests = 0;
  const nearest = (element, name) => {
    for (let at = element; at; at = at.parentElement)
      if (at.hasAttribute(name)) return at.getAttribute(name);
    return null;
  };
  const verbs = ['hx-get', 'hx-post', 'hx-put', 'hx-patch', 'hx-delete'];
  const preloadable = (link) => {
    if (!link.href || link.target || link.hasAttribute('download')) return false;
    if (link.closest('[data-tun-preload=off]')) return false;
    if (verbs.some((verb) => link.hasAttribute(verb))) return false;
    if ((nearest(link, 'hx-boost') ?? nearest(link, 'hx-boost:inherited')) !== 'true') return false;
    const url = new URL(link.href, location.href);
    return url.origin === location.origin
      && !(url.hash && url.pathname === location.pathname && url.search === location.search);
  };
  // What the click would send: htmx's headers for a boosted link, and the
  // shell's own (Tun-Assets), so new assets after a deploy still reload.
  const headers = (link) => {
    let shell = {};
    try { shell = JSON.parse(nearest(link, 'hx-headers:inherited') || '{}'); } catch (e) {}
    return { ...shell, 'HX-Request': 'true', 'HX-Request-Type': 'full', 'HX-Boosted': 'true',
             'HX-Current-URL': location.href, Accept: 'text/html', 'Tun-Preload': 'true' };
  };
  const preload = (link) => {
    if (requests > 0 || !link.isConnected || !preloadable(link)) return;
    const url = new URL(link.href, location.href).href;
    const now = performance.now();
    for (const [key, kept] of preloads) if (now - kept.at >= lifetime) preloads.delete(key);
    if (preloads.has(url)) return;
    preloads.set(url, { at: now, answer: fetch(url, { headers: headers(link) }).catch(() => null) });
  };
  const linkOf = (event) => event.target instanceof Element && event.target.closest('a[href]');

  // A pointer that comes to rest on a link waits INTENT before it
  // preloads; a press, a click or any request ends the wait, so a click
  // preloads once at most.  Only a pointer that moved starts a wait: the
  // browser also reports one under a page swapped in beneath it.
  let waiting = null;
  let at = null;
  const stopWaiting = () => {
    clearTimeout(waiting?.timer);
    waiting = null;
  };
  document.addEventListener('pointermove', (event) => {
    if (event.pointerType !== 'mouse') return;
    const moved = !at || at.x !== event.clientX || at.y !== event.clientY;
    at = { x: event.clientX, y: event.clientY };
    const link = linkOf(event);
    if (!moved || link === waiting?.link) return;
    stopWaiting();
    if (link) waiting = { link, timer: setTimeout(() => { waiting = null; preload(link); }, intent) };
  });
  for (const press of ['pointerdown', 'touchstart'])
    document.addEventListener(press, (event) => {
      stopWaiting();
      const link = linkOf(event);
      if (link) preload(link);
    }, { passive: true });
  document.addEventListener('click', stopWaiting, true);

  document.addEventListener('htmx:before:request', (event) => {
    const ctx = event.detail.ctx;
    requests += 1;
    ctx.tunCounted = true;
    stopWaiting();
    const get = (ctx.request.method || 'GET').toUpperCase() === 'GET';
    const url = new URL(ctx.request.action, location.href).href;
    const kept = get && ctx.request.headers['HX-Request-Type'] === 'full' && preloads.get(url);
    preloads.clear();
    if (!kept || performance.now() - kept.at >= lifetime) return;
    const ask = ctx.fetch;
    ctx.fetch = async (...request) => {
      const answer = await kept.answer;
      return answer && answer.headers.get('Tun-Preload') !== 'declined' ? answer : ask(...request);
    };
  });
  document.addEventListener('htmx:finally:request', (event) => {
    if (!event.detail.ctx?.tunCounted) return;
    requests = Math.max(0, requests - 1);
    preloads.clear();
  });
})();

// Installing as an app (spec/ui.md 4.2): a page that links a manifest
// registers the service worker.
if ('serviceWorker' in navigator && document.querySelector('link[rel=manifest]'))
  navigator.serviceWorker.register('/sw.js', { scope: '/' }).catch(() => {});

// The theme switch: [data-tun-theme=light|dark|system] buttons set
// data-theme on <html> and remember the choice in this browser.
(() => {
  const key = 'tun-theme';
  const apply = (theme) => {
    if (theme === 'light' || theme === 'dark') document.documentElement.dataset.theme = theme;
    else delete document.documentElement.dataset.theme;
    for (const button of document.querySelectorAll('[data-tun-theme]'))
      button.setAttribute('aria-pressed',
        String(button.dataset.tunTheme === (theme || 'system')));
  };
  let stored = null;
  try { stored = localStorage.getItem(key); } catch (e) {}
  apply(stored);
  tunOnContent(() => apply(stored));
  document.addEventListener('click', (event) => {
    const button = event.target.closest('[data-tun-theme]');
    if (!button) return;
    stored = button.dataset.tunTheme === 'system' ? null : button.dataset.tunTheme;
    apply(stored);
    try { stored ? localStorage.setItem(key, stored) : localStorage.removeItem(key); }
    catch (e) {}
  });
})();
")

;;; ------------------------------------------------------------------
;;; The stylesheet and the script (spec/ui.md 4)

(defun content-hash (text)
  "The first 12 hex digits of TEXT's SHA-256."
  (let ((octets (sb-ext:string-to-octets text :external-format :utf-8)))
    (subseq (ironclad:byte-array-to-hex-string (ironclad:digest-sequence :sha256 octets))
            0 12)))

;;; ------------------------------------------------------------------
;;; htmx (spec/ui.md 4.1)

(defmacro file-text (name)
  "The text of the file NAME beside this source file, read when it is
compiled, so the image holds it wherever the sources were."
  (uiop:read-file-string (merge-pathnames name (or *compile-file-truename* *load-truename*))
                         :external-format :utf-8))

(defparameter +htmx+ (file-text "htmx.min.js")
  "htmx 4.0.0, unchanged (reference/ui-sources.md).")

(defparameter +htmx-hash+ (content-hash +htmx+))

(defparameter +htmx-config+
  "{\"mode\":\"same-origin\",\"extensions\":\"tun\",\"noSwap\":[204,304],\"includeIndicatorCSS\":false}"
  "htmx's configuration, the content of every page's <meta name=htmx-config>:
requests stay on this server, only Tun's own extension may load (the one
that keeps htmx from running code, in the kit's script), every answer but
204 and 304 is swapped in, so a refused form shows its errors, and htmx adds
no styles of its own.")

(defun htmx-path ()
  "Where htmx is served: /assets/htmx-HASH.js."
  (format nil "/assets/htmx-~a.js" +htmx-hash+))

(defun htmx-config ()
  "The content of a page's <meta name=htmx-config> (spec/ui.md 4.1)."
  +htmx-config+)

(defstruct (assets (:constructor make-assets
                                 (css js &aux (css-hash (content-hash css))
                                      (js-hash (content-hash js)))))
  (css "" :type string :read-only t)
  (js "" :type string :read-only t)
  (css-hash "" :type string :read-only t)
  (js-hash "" :type string :read-only t))

(defun build-assets (components)
  (make-assets
   (with-output-to-string (out)
     (format out "@layer reset, tokens, base, components, client;~%")
     (format out "@layer reset {~a}~%@layer tokens {~a}~%@layer base {~a}~%"
             +reset-css+ +tokens-css+ +base-css+)
     (format out "@layer components {~%")
     (dolist (component components)
       (unless (zerop (length (component-css component)))
         (format out "~%/* ~(~a~): ~a */~%~a~%" (component-name component)
                 (component-source component) (component-css component))))
     (format out "}~%"))
   (with-output-to-string (out)
     (format out "'use strict';~%~a" +kit-script+)
     (dolist (component components)
       (unless (zerop (length (component-script component)))
         (format out "~%// ~(~a~)~%(() => {~%~a~%})();~%" (component-name component)
                 (component-script component)))))))

(defun current-assets ()
  (sb-thread:with-mutex (*lock*)
    (or *assets* (setf *assets* (build-assets *components*)))))

(defun stylesheet ()
  "The whole stylesheet: the base layers and every component's CSS."
  (assets-css (current-assets)))

(defun stylesheet-path ()
  "Where the stylesheet is served: /assets/tun-HASH.css."
  (format nil "/assets/tun-~a.css" (assets-css-hash (current-assets))))

(defun script ()
  "The components' shared script."
  (assets-js (current-assets)))

(defun script-path ()
  "Where the script is served: /assets/tun-HASH.js."
  (format nil "/assets/tun-~a.js" (assets-js-hash (current-assets))))

(defun asset-content (path)
  "The asset served at PATH, an /assets/tun-HASH.css or .js path or
/assets/htmx-HASH.js.  Values its text, its content type, and whether HASH
is the current one (an older page may ask for the version it was rendered
with).  NIL for any other path."
  (let ((assets (current-assets)))
    (cl-ppcre:register-groups-bind (name hash extension)
        ("^/assets/(tun|htmx)-([0-9a-f]{12})\\.(css|js)$" path)
      (cond ((string= name "htmx")
             (when (string= extension "js")
               (values +htmx+ "text/javascript; charset=utf-8" (string= hash +htmx-hash+))))
            ((string= extension "css")
             (values (assets-css assets) "text/css; charset=utf-8"
                     (string= hash (assets-css-hash assets))))
            (t
             (values (assets-js assets) "text/javascript; charset=utf-8"
                     (string= hash (assets-js-hash assets))))))))

(defun asset-hashes ()
  "The stylesheet's and the script's hashes, as the app shell sends them in
Tun-Assets: \"CSS-HASH JS-HASH\" (spec/ui.md 4.1)."
  (let ((assets (current-assets)))
    (format nil "~a ~a" (assets-css-hash assets) (assets-js-hash assets))))
