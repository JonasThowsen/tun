;;;; web/ui/specimen.lisp -- the specimen: every component with its
;;;; documentation and its examples, rendered and as Lisp (spec/ui.md 7).
;;;;
;;;; The same pages are served at /ui and written as standalone files (the
;;;; stylesheet and script inline) for screenshots and for sharing.

(in-package #:tun.ui)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +groups+
  '("Handlinger" "Skjema" "Data" "Tilbakemelding" "Interaksjon" "Oppsett og navigasjon")
  "The specimen's groups in the order it shows them; other groups come after.")

(define-component specimen ((&key) &rest children)
  (:internal t)
  (:css "
.tun-specimen {
  min-height: 100dvh;
  & .tun-specimen-header {
    position: sticky;
    top: 0;
    z-index: var(--z-sticky);
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: calc(var(--spacing) * 2);
    padding: calc(var(--spacing) * 2) calc(var(--spacing) * 4);
    border-bottom: 1px solid var(--border);
    background-color: color-mix(in oklab, var(--background) 90%, transparent);
    backdrop-filter: blur(8px);
  }
  & .tun-specimen-title { font-weight: var(--font-weight-semibold); }
  & .tun-specimen-themes {
    display: flex;
    & [aria-pressed='true'] { background-color: var(--muted); }
  }
  & .tun-specimen-body { display: grid; grid-template-columns: minmax(0, 1fr); }
  & .tun-specimen-nav { display: none; }
  & .tun-specimen-jump {
    margin: calc(var(--spacing) * 4) calc(var(--spacing) * 4) 0;
    border: 1px solid var(--border);
    border-radius: var(--radius-lg);
    & summary {
      padding: calc(var(--spacing) * 3) calc(var(--spacing) * 4);
      font-size: var(--text-sm);
      font-weight: var(--font-weight-medium);
      cursor: pointer;
    }
    & .tun-specimen-links { padding: 0 calc(var(--spacing) * 4) calc(var(--spacing) * 4); }
  }
  & .tun-specimen-links {
    display: flex;
    flex-direction: column;
    gap: calc(var(--spacing) * 4);
    font-size: var(--text-sm);
    & h2 {
      margin-bottom: var(--spacing);
      font-size: var(--text-xs);
      line-height: var(--text-xs--line-height);
      font-weight: var(--font-weight-medium);
      color: var(--muted-foreground);
      text-transform: uppercase;
      letter-spacing: 0.05em;
    }
    & a {
      display: block;
      text-decoration: none;
      padding: calc(var(--spacing) * 1.5) calc(var(--spacing) * 2);
      border-radius: var(--radius-md);
      @media (hover: hover) { &:hover { background-color: var(--muted); } }
      &[aria-current='page'] {
        background-color: var(--muted);
        font-weight: var(--font-weight-medium);
      }
    }
  }
  & .tun-specimen-main {
    display: flex;
    flex-direction: column;
    gap: calc(var(--spacing) * 12);
    width: 100%;
    max-width: 60rem;
    padding: calc(var(--spacing) * 6) calc(var(--spacing) * 4) calc(var(--spacing) * 16);
  }
  & .tun-specimen-component {
    display: flex;
    flex-direction: column;
    gap: calc(var(--spacing) * 4);
    scroll-margin-top: 4.5rem;
  }
  & .tun-specimen-name { font-family: var(--font-mono); }
  & .tun-specimen-doc { color: var(--muted-foreground); }
  & .tun-specimen-source { font-size: var(--text-xs); color: var(--muted-foreground); }
  & .tun-specimen-example {
    border: 1px solid var(--border);
    border-radius: var(--radius-lg);
    overflow: hidden;
    & > h3 {
      padding: calc(var(--spacing) * 2) calc(var(--spacing) * 4);
      border-bottom: 1px solid var(--border);
      background-color: color-mix(in oklab, var(--muted) 50%, transparent);
      font-size: var(--text-sm);
      line-height: var(--text-sm--line-height);
      font-weight: var(--font-weight-medium);
    }
  }
  & .tun-specimen-preview {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: calc(var(--spacing) * 3);
    padding: calc(var(--spacing) * 6) calc(var(--spacing) * 4);
    & > * { min-width: 0; }
    &[data-layout='stack'] { flex-direction: column; align-items: stretch; flex-wrap: nowrap; }
  }
  & .tun-specimen-code {
    border-top: 1px solid var(--border);
    & summary {
      padding: calc(var(--spacing) * 2) calc(var(--spacing) * 4);
      font-size: var(--text-xs);
      color: var(--muted-foreground);
      cursor: pointer;
    }
    & pre {
      padding: calc(var(--spacing) * 3) calc(var(--spacing) * 4);
      overflow-x: auto;
      background-color: var(--muted);
      font-size: var(--text-xs);
      line-height: var(--text-xs--line-height);
    }
  }
  & .tun-specimen-error { color: var(--destructive); font-family: var(--font-mono); }
  @media (min-width: 64rem) {
    & .tun-specimen-body { grid-template-columns: 15rem minmax(0, 1fr); }
    & .tun-specimen-jump { display: none; }
    & .tun-specimen-nav {
      display: block;
      position: sticky;
      top: 3.25rem;
      height: calc(100dvh - 3.25rem);
      overflow-y: auto;
      padding: calc(var(--spacing) * 6) calc(var(--spacing) * 3);
      border-right: 1px solid var(--border);
    }
    & .tun-specimen-main { padding-inline: calc(var(--spacing) * 10); }
  }
}")
  `(:div (:@ :class "tun-specimen") ,@children))

(defun grouped-components ()
  "The listed components as (GROUP . COMPONENTS), groups in +GROUPS+ order."
  (let ((components (all-components)))
    (loop for group in (remove-duplicates (append +groups+ (mapcar #'component-group components))
                                          :test #'string= :from-end t)
          for members = (remove group components :key #'component-group :test-not #'string=)
          when members collect (cons group members))))

(defun component-slug (component)
  (string-downcase (symbol-name (component-name component))))

(defun specimen-links (link current)
  `(:div (:@ :class "tun-specimen-links")
         (:a (:@ :href ,(funcall link nil) :aria-current ,(unless current "page"))
             "Alle komponenter")
         ,@(loop for (group . members) in (grouped-components)
                 collect `(:section
                           (:h2 ,group)
                           ,@(loop for component in members
                                   collect `(:a (:@ :href ,(funcall link component)
                                                    :aria-current ,(when (eq component current)
                                                                     "page"))
                                                ,(component-slug component)))))))

(defun example-markup (example)
  (destructuring-bind (title source thunk layout) example
    `(:div (:@ :class "tun-specimen-example")
           (:h3 ,title)
           (:div (:@ :class "tun-specimen-preview" :data-layout ,(option-string layout))
                 ,(handler-case (funcall thunk)
                    (error (condition)
                      `(:p (:@ :class "tun-specimen-error") ,(princ-to-string condition)))))
           (:details (:@ :class "tun-specimen-code")
                     (:summary "Lisp")
                     (:pre (:code ,source))))))

(defun component-markup (component link)
  `(:section (:@ :class "tun-specimen-component" :id ,(component-slug component))
             (:h2 (:a (:@ :class "tun-specimen-name" :href ,(funcall link component))
                      ,(component-slug component)))
             (:p (:@ :class "tun-specimen-doc") ,(component-doc component))
             (:p (:@ :class "tun-specimen-source") "Kilde: " ,(component-source component))
             ,@(mapcar #'example-markup (component-examples component))))

(defun theme-switch ()
  `(:div (:@ :class "tun-specimen-themes" :role "group" :aria-label "Tema")
         ,@(loop for (theme label) in '(("light" "Lys") ("dark" "Mørk") ("system" "System"))
                 for attributes = (list :data-tun-theme theme :aria-pressed "false")
                 collect (button (:variant :ghost :size :sm :attributes attributes) label))))

(defun specimen-document (title body inline)
  (list (trusted "<!doctype html>")
        `(:html (:@ :lang "no")
                (:head (:meta (:@ :charset "utf-8"))
                       (:meta (:@ :name "viewport" :content "width=device-width, initial-scale=1"))
                       (:title ,title)
                       ,@(if inline
                             `((:style ,(trusted (stylesheet)))
                               (:script ,(trusted (script))))
                             `((:link (:@ :rel "stylesheet" :href ,(stylesheet-path)))
                               (:script (:@ :defer t :src ,(script-path))))))
                (:body ,body))))

(defun specimen-html (&key component inline (link (lambda (component)
                                                    (if component
                                                        (format nil "/ui/~a"
                                                                (component-slug component))
                                                        "/ui"))))
  "The specimen page as an HTML string: every component, or only COMPONENT.
With INLINE the stylesheet and script are in the page.  LINK maps a
component, or NIL for the overview, to its URL."
  (let ((shown (if component (list component) (all-components))))
    (render-html
     (specimen-document
      (if component
          (format nil "~a – Tun designsystem" (component-slug component))
          "Tun designsystem")
      (specimen ()
                `(:header (:@ :class "tun-specimen-header")
                          (:a (:@ :class "tun-specimen-title" :href ,(funcall link nil))
                              "Tun designsystem")
                          ,(theme-switch))
                `(:div (:@ :class "tun-specimen-body")
                       (:nav (:@ :class "tun-specimen-nav" :aria-label "Komponenter")
                             ,(specimen-links link component))
                       (:div
                        (:details (:@ :class "tun-specimen-jump")
                                  (:summary "Komponenter")
                                  ,(specimen-links link component))
                        (:main (:@ :class "tun-specimen-main")
                               ,@(mapcar (lambda (shown-component)
                                           (component-markup shown-component link))
                                         shown)))))
      inline))))

(defun write-specimen (directory)
  "Write the specimen as standalone files into DIRECTORY: index.html and
NAME.html for each component.  Returns the files written."
  (let ((link (lambda (component)
                (if component (format nil "~a.html" (component-slug component)) "index.html"))))
    (flet ((write-page (name html)
             (let ((path (merge-pathnames name directory)))
               (ensure-directories-exist path)
               (with-open-file (out path :direction :output :if-exists :supersede
                                    :external-format :utf-8)
                 (write-string html out))
               path)))
      (cons (write-page "index.html" (specimen-html :inline t :link link))
            (mapcar (lambda (component)
                      (write-page (funcall link component)
                                  (specimen-html :component component :inline t :link link)))
                    (all-components))))))
