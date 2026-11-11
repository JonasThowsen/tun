;;;; tests/ui-header-tests.lisp -- the page's frame: the header's row and its
;;;; «More actions» menu, the shell and the theme colours on the chrome,
;;;; section links, the record's facts by spacing, tabs on the page's ground,
;;;; and no description under a title in Tun's own pages (spec/ui.md 4.2, 6,
;;;; 8, 10).

(in-package #:tun.tests)

(def-suite ui-header :in core)
(in-suite ui-header)

(defun header-html (title actions)
  (tun.html:render-html (tun.ui:page-header* (list :title title :actions actions))))

(defun before-p (html first second)
  "True when FIRST and SECOND are both in HTML, FIRST before SECOND."
  (let ((a (search first html)) (b (search second html)))
    (and a b (< a b))))

;;; ------------------------------------------------------------------
;;; The header's row (criterion 1)

(test the-title-and-the-actions-share-one-row-and-the-filled-one-is-last
  (let ((html (header-html "Kunder"
                           (list (tun.ui:button () "Ny kunde")
                                 (tun.ui:button (:variant :outline) "Eksporter")
                                 nil
                                 (tun.ui:button (:variant :ghost) "Importer")))))
    (is (= 1 (cl-ppcre:count-matches "<h1" html)))
    (is (before-p html "<h1" "tun-page-header-actions"))
    (is (search "<div class=\"tun-page-header-row\"><div class=\"tun-page-header-text\">" html)
        "the title's text and the actions are in one row")
    (is (before-p html ">Eksporter<" ">Importer<") "the others keep the page's order")
    (is (before-p html ">Importer<" ">Ny kunde<") "the filled one comes last"))
  (let ((html (header-html "Ordre 1042"
                           (list `(:form (:@ :method "post" :action "/ordre/1042/send")
                                         ,(tun.ui:button (:type "submit") "Send"))
                                 (tun.ui:button (:variant :outline) "Kopier")))))
    (is (before-p html ">Kopier<" ">Send<") "a form holding the filled button is filled too"))
  (let ((css (tun.ui:component-css (tun.ui:find-component "page-header"))))
    (is (search "container: tun-page-header / inline-size;" css))
    (is (not (search "flex-wrap: wrap;" (subseq css 0 (search ".tun-page-header-meta" css))))
        "neither the row nor the actions wrap")
    (is (search "overflow-wrap: anywhere;" css) "a long word of the title breaks")))

;;; ------------------------------------------------------------------
;;; The «More actions» menu (criterion 2)

(test icon-actions-that-fit-are-not-folded
  (let ((html (header-html "Items"
                           (list (tun.ui:button (:variant :outline :size :icon :label "Search"
                                                 :icon :search))
                                 (tun.ui:button (:variant :outline :size :icon :label "Filter"
                                                 :icon :funnel))
                                 (tun.ui:button (:icon :plus) "New item")))))
    (is (not (search "tun-page-header-more" html)))
    (is (not (search "data-tun-folded" html)))
    (is (not (search "data-tun-compact" html)))))

(test a-short-title-folds-the-others-and-keeps-the-filled-words
  (let ((html (header-html "Ole Hansen Ltd"
                           (list (tun.ui:button (:variant :outline :icon :pencil
                                                 :href "/customers/42/edit")
                                                "Edit")
                                 (tun.ui:button (:icon :plus) "New order")))))
    (is (search "tun-page-header-more" html))
    (is (cl-ppcre:scan "<a class=\"tun-button\"[^>]*href=\"/customers/42/edit\"[^>]* data-tun-folded>"
                       html)
        "the link stays in the row, folded")
    (is (cl-ppcre:scan "<a class=\"tun-dropdown-menu-item\" role=\"menuitem\" href=\"/customers/42/edit\"><svg[^>]*>.*?</svg><span class=\"tun-dropdown-menu-text\">Edit</span></a>"
                       html)
        "its item has its link, its icon and its words")
    (is (search "aria-label=\"More actions\"" html))
    (is (search "data-variant=\"ghost\" data-size=\"icon\"" html) "a frameless icon button")
    (is (before-p html "tun-page-header-more" ">New order<") "the menu stands before the filled")
    (is (not (search "data-tun-compact" html)) "the filled action keeps its words")))

(test a-long-title-folds-forms-and-shows-the-filled-icon-alone
  (let ((html (header-html
               "Quote 2024-031: A summer party with a tent for Fjord Catering"
               (list (tun.ui:button (:icon :send) "Send to the customer")
                     (tun.ui:button (:variant :outline :icon :eye
                                     :attributes (list :hx-get "/quotes/1/preview"
                                                       :hx-target "#preview"))
                                    "Preview")
                     `(:form (:@ :method "post" :action "/quotes/1/withdraw")
                             (:input (:@ :type "hidden" :name "key" :value "k1"))
                             ,(tun.ui:button (:type "submit" :variant :destructive :icon :trash
                                              :attributes (tun.ui:confirm-attributes
                                                           "Withdraw quote 1?"))
                                             "Withdraw"))))))
    (let ((form-id (cl-ppcre:register-groups-bind (id)
                       ("<form method=\"post\" action=\"/quotes/1/withdraw\" id=\"([^\"]+)\" data-tun-folded>"
                        html)
                     id)))
      (is (stringp form-id) "the form stays in the row, with an id, folded")
      (let ((item (cl-ppcre:scan-to-strings
                   (format nil "<button class=\"tun-dropdown-menu-item\"[^>]*form=\"~a\"[^>]*>"
                           form-id)
                   html)))
        (is (stringp item) "its item names the form")
        (is (and item (search "type=\"submit\"" item)) "and submits it")
        (is (and item (search "data-variant=\"destructive\"" item)) "red")
        (is (and item (search "data-tun-confirm=\"Withdraw quote 1?\"" item))
            "and still asks first")))
    (is (cl-ppcre:scan "role=\"menuitem\" type=\"button\" hx-get=\"/quotes/1/preview\" hx-target=\"#preview\"" html)
        "an item keeps the action's htmx attributes")
    (is (cl-ppcre:scan "<button class=\"tun-button\" data-variant=\"primary\"[^>]*data-tun-compact>"
                       html)
        "the filled action shows its icon alone on a phone")
    (is (search ">Send to the customer<" html) "its words stay its name")))

(test what-is-not-a-button-never-folds
  (let* ((menu (tun.ui:dropdown-menu (:label "Actions" :items '((:label "Approve")))))
         (html (header-html "Quote 2024-031: A summer party with a tent for Fjord Catering"
                            (list menu (tun.ui:button (:icon :send) "Send to the customer")))))
    (is (not (search "tun-page-header-more" html)) "a menu is not folded into a menu")
    (is (search "data-tun-compact" html) "the filled action gives room instead"))
  (let ((html (header-html "A title long enough to need the room of every action here"
                           (list (tun.ui:button () "Save the whole quote now")))))
    (is (not (search "data-tun-compact" html)) "without an icon a filled action keeps its words")))

(test the-more-menu-speaks-norwegian
  (let ((html (with-language ("nb")
                (header-html "Ole Hansen AS"
                             (list (tun.ui:button (:variant :outline :icon :pencil) "Rediger")
                                   (tun.ui:button (:icon :plus) "Ny ordre"))))))
    (is (search "aria-label=\"Flere handlinger\"" html))))

(test the-css-folds-only-below-40rem
  (let ((declarations (component-declarations "page-header")))
    (flet ((under (selector property)
             (find-if (lambda (d) (and (search selector (selectors-text d))
                                       (string= property (declaration-property d))))
                      declarations)))
      (let ((folded (under "[data-tun-folded]" "display"))
            (more (under ".tun-page-header-more" "display")))
        (is (equal "none" (declaration-value folded)))
        (is (find "@container tun-page-header (width < 40rem)" (declaration-media folded)
                  :test #'string=))
        (is (equal "contents"
                   (declaration-value
                    (find-if (lambda (d) (and (search ".tun-page-header-more" (selectors-text d))
                                              (declaration-media d)))
                             declarations))))
        (is (equal "none" (declaration-value more)))))))

(test meta-is-a-row-of-live-facts-under-the-title
  (let ((html (tun.html:render-html
               (tun.ui:page-header (:title "Ordre 1042"
                                    :meta (list (tun.ui:badge (:variant :info) "Sendt"))
                                    :description "For en klient som vil ha en.")))))
    (is (before-p html "<h1" "tun-page-header-meta"))
    (is (search "<div class=\"tun-page-header-meta\"><span class=\"tun-badge\"" html))
    (is (search "<p class=\"tun-page-header-description\">For en klient som vil ha en.</p>" html)
        "a client's description still renders")))

;;; ------------------------------------------------------------------
;;; The shell and the theme colours (criteria 3 and 4)

(test the-shell-is-the-chrome-and-dims-with-the-overlay
  (let ((css (tun.ui:component-css (tun.ui:find-component "app-shell"))))
    (is (not (search "backdrop-filter" css)))
    (is (search "background-color: var(--overlay);" css) "the phone menu's dim")
    (is (not (search "rgb(0 0 0" css)))))

(test the-theme-colours-default-to-the-chrome
  (let ((options (tun.core::web-app-options 'probe '(:icons "icons/"))))
    (is (string= (token-colour "--chrome" :light) (getf options :theme-color)))
    (is (string= (token-colour "--chrome" :dark) (getf options :dark-theme-color)))
    (is (string= "#ffffff" (getf options :background-color)) "the start screen is the page's"))
  (let ((options (tun.core::web-app-options 'probe '(:icons "icons/" :theme-color "#ffffff"))))
    (is (string= "#ffffff" (getf options :theme-color)) "a client's own colour is kept")))

;;; ------------------------------------------------------------------
;;; Section links (criterion 5)

(test section-links-are-plain-links-in-a-named-row
  (let ((html (tun.html:render-html
               (tun.ui:section-links (:label "På denne siden"
                                      :items '((:label "Detaljer" :href "#detaljer")
                                               (:label "Linjer" :href "#linjer")))))))
    (is (search "<nav class=\"tun-section-links\" aria-label=\"På denne siden\" data-tun-section-links>"
                html))
    (is (search "<li><a href=\"#detaljer\">Detaljer</a></li><li><a href=\"#linjer\">Linjer</a></li>"
                html))
    (is (not (search "aria-current" html)) "none is marked without the script"))
  (signals error (tun.ui:section-links (:label "Tom")))
  (let ((declarations (component-declarations "section-links")))
    (flet ((value (selector property)
             (declaration-value
              (find-if (lambda (d) (and (string= selector (car (last (declaration-selectors d))))
                                        (string= property (declaration-property d))))
                       declarations))))
      (is (equal "nowrap" (value "& ul" "white-space")))
      (is (equal "auto" (value "& ul" "overflow-x")))
      (is (equal "var(--foreground)" (value "&[aria-current]" "color")))
      (is (equal "currentColor" (value "&[aria-current]" "text-decoration-color")))))
  (let ((script (tun.ui:component-script (tun.ui:find-component "section-links"))))
    (is (search "setAttribute('aria-current', 'location')" script))
    (is (search "scrollMarginTop" script) "the top a followed link puts a section at")
    (is (search "tunOnContent(later)" script))))

;;; ------------------------------------------------------------------
;;; Tabs and the facts (criteria 6 and 7)

(test tabs-stand-in-a-frame-on-their-ground
  (let ((declarations (component-declarations "tabs")))
    (flet ((value (last-selector property &optional (count 1))
             (declaration-value
              (nth (1- count)
                   (remove-if-not (lambda (d)
                                    (and (string= last-selector
                                                  (car (last (declaration-selectors d))))
                                         (string= property (declaration-property d))))
                                  declarations)))))
      (is (equal "1px solid var(--border)" (value "& .tun-tabs-list" "border")))
      (is (null (value "& .tun-tabs-list" "background-color")) "no grey fill")
      (is (equal "var(--secondary)"
                 (value "&:is([aria-selected='true'], [aria-current='page'])"
                        "background-color")))
      (is (equal "0" (value "& li" "flex-grow")) "line tabs keep their width"))))

(test the-facts-are-set-apart-by-space
  (let ((declarations (component-declarations "summary-list")))
    (is (notany (lambda (d) (let ((property (declaration-property d)))
                              (and (search "border" property) (not (search "radius" property)))))
                declarations)
        "no line or box between the facts")
    (is (search "repeat(auto-fit,"
                (declaration-value
                 (find "grid-template-columns" declarations
                       :key #'declaration-property :test #'string=)))
        "two columns where they fit")
    (is (find-if (lambda (d) (and (string= "grid-template-areas" (declaration-property d))
                                  (string= "'key value' '. action'" (declaration-value d))
                                  (null (declaration-media d))))
                 declarations)
        "on a phone the label stands beside the value")
    (is (find-if (lambda (d) (and (string= "grid-template-areas" (declaration-property d))
                                  (string= "'key action' 'value value'" (declaration-value d))
                                  (find "@container tun-summary-list (width >= 30rem)"
                                        (declaration-media d) :test #'string=)))
                 declarations)
        "in two columns above it")
    (is (notany (lambda (d) (and (equal (declaration-selectors d) '(".tun-summary-list"))
                                 (member (declaration-property d) '("padding" "margin")
                                         :test #'string=)))
                declarations)
        "no padding of its own, so its edges are its box's")))

;;; ------------------------------------------------------------------
;;; No description in Tun's own pages (criterion 8)

(defun symbol-named-p (thing &rest names)
  (and (symbolp thing) (member (symbol-name thing) names :test #'string=)))

(defun gives-description-p (arguments)
  "True when ARGUMENTS hold :description with a value of their own, not the
variable DESCRIPTION passed on from a client page."
  (loop for tail on arguments
        while (consp tail)
        thereis (and (eq (first tail) :description)
                     (consp (rest tail))
                     (not (symbol-named-p (second tail) "DESCRIPTION")))))

(defun list-form-arguments (form)
  "The arguments of FORM when it is (LIST ...), else NIL."
  (and (consp form) (symbol-named-p (first form) "LIST") (rest form)))

(defun description-under-a-title-p (form)
  "True when FORM puts a description under a page's or a section's title."
  (let ((head (first form)))
    (cond ((symbol-named-p head "PAGE-HEADER" "SECTION")
           (and (listp (second form)) (gives-description-p (second form))))
          ((symbol-named-p head "PAGE-HEADER*" "SECTION*")
           (gives-description-p (list-form-arguments (second form))))
          ((symbol-named-p head "RESPOND" "GUEST-PAGE")
           (gives-description-p (cddr form)))
          ((symbol-named-p head "VALUES")
           (gives-description-p (list-form-arguments (fifth form)))))))

(defun descriptions-in (form)
  "Every subform of FORM that puts a description under a title."
  (let ((found '()))
    (labels ((walk (x)
               (cond ((typep x 'sb-impl::comma) (walk (sb-impl::comma-expr x)))
                     ((consp x)
                      (when (and (symbolp (first x)) (description-under-a-title-p x))
                        (push x found))
                      (loop for tail on x
                            do (walk (if (consp tail) (first tail) tail))
                            while (consp tail))))))
      (walk form))
    found))

(defun lisp-file-forms (path)
  "The forms of the Lisp file PATH, read in the packages it names."
  (with-open-file (in path :external-format :utf-8)
    (let ((*package* (find-package '#:cl-user))
          (*read-eval* nil))
      (loop for form = (read in nil in)
            until (eq form in)
            collect form
            when (and (consp form) (symbol-named-p (first form) "IN-PACKAGE"))
              do (setf *package* (find-package (second form)))))))

(defun tun-page-sources ()
  "The Lisp files of Tun's own pages: src/ and modules/, but the component
library, whose examples show the option, and the template of a new client."
  (let ((root (asdf:system-source-directory "tun")))
    (remove-if (lambda (path)
                 (let ((name (namestring path)))
                   (or (search "/src/web/ui/" name) (search "/src/cli/template/" name))))
               (append (directory (merge-pathnames "src/**/*.lisp" root))
                       (directory (merge-pathnames "modules/**/*.lisp" root))))))

(test the-scan-finds-a-description-under-a-title
  (is (descriptions-in '(tun.ui:section (:title "x" :description "y"))))
  (is (descriptions-in '(tun.ui:page-header* (list :title "x" :description (tr "y")))))
  (is (descriptions-in '(values 200 "x" nil (list :description "y" :breadcrumbs nil))))
  (is (descriptions-in '(respond 200 "x" nil :description (tr "y"))))
  (is (null (descriptions-in '(respond 200 "x" nil :description description)))
      "a client's description passed on is not Tun's own")
  (is (null (descriptions-in '(tun.ui:card (:title "x" :description "y")))) "a card keeps its own"))

(test tuns-own-pages-put-no-description-under-a-title
  (let ((files (tun-page-sources)))
    (is (< 40 (length files)) "the scan reads Tun's sources")
    (dolist (path files)
      (let ((found (loop for form in (lisp-file-forms path) append (descriptions-in form))))
        (is (null found) "~a puts a description under a title: ~s"
            (file-namestring path) (first found))))))

(test a-record-shows-its-status-in-the-headers-meta
  (with-test-server (port)
    (let* ((jar (web-login port "employee:anna"))
           (customer (jget (call-ok "customers_create" "employee:anna" "name" "Kari"
                                    "email" "kari@example.no")
                           "id"))
           (product (jget (call-ok "products_create" "employee:anna" "name" "Popcornmaskin"
                                   "kind" "rental" "unit" "stk" "unit_price_minor" 150000
                                   "stock_tracked" nil "units_owned" 1)
                          "id"))
           (order (jget (call-ok "orders_create" "employee:anna" "customer_id" customer
                                 "event_date" "2026-06-20"
                                 "lines" (jarr (list (jobj "product_id" product "quantity" 1))))
                        "id"))
           (page (nth-value 1 (web-request port (format nil "/orders/~a" order) :jar jar))))
      (is (cl-ppcre:scan "<div class=\"tun-page-header-meta\"><span class=\"tun-badge\"" page))
      (is (not (search "tun-page-header-description" page)))
      (is (search "id=\"record-details\"" page) "the record's sections have ids")
      (let ((sections (cl-ppcre:count-matches "<section class=\"tun-section\" id=\"record-" page))
            (links (search "<nav class=\"tun-section-links\"" page)))
        (if (>= sections 3)
            (is (and links (< links (search "id=\"record-details\"" page))
                     (search "<a href=\"#record-details\">" page))
                "three sections or more start with links to them")
            (is (null links) "fewer than three have none"))))))

(test a-record-of-three-sections-starts-with-links-to-them
  (flet ((html (count)
           (tun.html:render-html
            (loop for n from 1 to count
                  collect (list (format nil "record-~d" n) (format nil "Del ~d" n) "Tekst")
                    into entries
                  finally (return (tun.web::record-sections entries))))))
    (let ((three (html 3)))
      (is (search "<nav class=\"tun-section-links\" aria-label=\"On this page\"" three))
      (is (< (search "tun-section-links" three) (search "<section" three))
          "the links come first")
      (is (search "<a href=\"#record-1\">Del 1</a>" three))
      (is (search "<a href=\"#record-3\">Del 3</a>" three))
      (is (search "<section class=\"tun-section\" id=\"record-3\">" three)))
    (is (not (search "tun-section-links" (html 2))) "two sections need no links")))

;;; ------------------------------------------------------------------
;;; The account's flash (criterion 9)

(test the-flash-after-an-account-is-created-stays-in-the-page
  (with-test-server (port :identity :authenticated)
    (with-provider (provider)
      (let ((jar (admin-session port provider)))
        (flet ((post (parameters)
                 (nth-value 1 (web-request port "/access/accounts" :method :post :jar jar
                                                                    :parameters parameters))))
          (dolist (body (list (post '(("name" . "ola") ("kind" . "person") ("role" . "admin")
                                      ("email" . "ola@example.no")))
                              (post '(("name" . "eva") ("kind" . "person")
                                      ("role" . "employee") ("email" . "eva@example.no")
                                      ("invite" . "on")))))
            (is (cl-ppcre:scan "<div class=\"tun-flash\"[^>]*data-placement=\"page\"" body)
                "what the person signs in with does not leave by itself")))))))
