;;;; tests/ui-layout-tests.lisp -- the layout and navigation components:
;;;; the current page in a menu, the skip link and its target, the phone
;;;; menu, breadcrumbs (spec/ui.md 6).

(in-package #:tun.tests)

(def-suite ui-layout :in core)
(in-suite ui-layout)

(defun attribute-values (html element attribute)
  "The values of ATTRIBUTE on each ELEMENT tag in HTML, in order; NIL for a
tag without it."
  (let ((values '()))
    (cl-ppcre:do-matches-as-strings (tag (format nil "<~a[ >][^>]*>" element) html)
      (push (cl-ppcre:register-groups-bind (value)
                ((format nil " ~a=\"([^\"]*)\"" attribute) tag)
              value)
            values))
    (nreverse values)))

(defparameter +main-menu+
  '((:label "Oversikt" :href "/")
    (:label "Kunder" :href "/kunder" :icon :users :count 128)
    (:label "Ordre" :href "/ordre" :icon :shopping-cart)
    (:label "Ordremaler" :href "/ordremaler")))

(defun menu-marks (current &optional (items +main-menu+))
  "The aria-current value of each link in a menu of ITEMS on the page CURRENT."
  (attribute-values (tun.html:render-html
                     (tun.ui:nav-list* (list :label "Meny" :items items :current current)))
                    "a" "aria-current"))

(test only-the-current-menu-item-is-the-page
  (is (equal '(nil "page" nil nil) (menu-marks "/kunder")))
  (is (equal '("page" nil nil nil) (menu-marks "/")) "the front page is current only on itself")
  (is (equal '(nil nil nil nil) (menu-marks nil))))

(test a-page-below-a-menu-item-marks-its-section
  (is (equal '(nil "true" nil nil) (menu-marks "/kunder/42"))
      "a customer's page is in Kunder, though the link is not to that page")
  (is (equal '(nil nil "page" nil) (menu-marks "/ordre")) "/ordremaler is not below /ordre")
  (is (equal '(nil "true" nil)
             (menu-marks "/kunder/42/ordre/1042"
                         '((:label "Oversikt" :href "/kunder/42")
                           (:label "Ordre" :href "/kunder/42/ordre")
                           (:label "Faktura" :href "/kunder/42/faktura"))))
      "only the closest section is marked, not every level above the page"))

(test a-menu-is-named-and-its-groups-are-labelled
  (let* ((groups '((:heading "Firma" :items ((:label "Brukere" :href "/brukere")))))
         (html (tun.html:render-html
                (tun.ui:nav-list* (list :label "Innstillinger" :groups groups))))
         (heading-id (find-if #'identity (attribute-values html "div" "id"))))
    (is (search "<nav class=\"tun-nav-list\" aria-label=\"Innstillinger\">" html))
    (is (stringp heading-id))
    (is (equal (list heading-id) (attribute-values html "ul" "aria-labelledby")))))

(defun shell-html (&rest options)
  (tun.html:render-html
   (tun.ui:app-shell* (append options
                              (list :title "Nordvik Utleie" :nav +main-menu+ :current "/kunder"
                                    :user "admin:jonas" :logout-action "/logout"))
                      (tun.ui:page-header (:title "Kunder")))))

(test the-skip-link-leads-to-the-main-content
  (let ((html (shell-html)))
    (is (search "<a class=\"tun-app-shell-skip\" href=\"#hovedinnhold\">Hopp til hovedinnholdet</a>"
                html))
    (is (< (search "tun-app-shell-skip" html) (search "<header" html))
        "the skip link comes before the menu")
    (is (equal '("hovedinnhold") (attribute-values html "main" "id")))
    (is (equal '("-1") (attribute-values html "main" "tabindex"))
        "main takes the focus the skip link moves to it"))
  (let ((html (shell-html :main-id "innhold")))
    (is (search "href=\"#innhold\"" html))
    (is (equal '("innhold") (attribute-values html "main" "id")))))

(test the-shell-marks-the-current-section-and-signs-out-by-post
  (let ((html (shell-html)))
    (is (equal '(nil "page" nil nil)
               (attribute-values (subseq html (search "<nav" html)) "a" "aria-current"))
        "in the main menu, exactly the Kunder link is the current page")
    (is (search "<form class=\"tun-app-shell-logout\" method=\"post\" action=\"/logout\">" html))
    (is (search "Logg ut</button>" html))
    (is (search "admin:jonas" html))))

(test the-menu-button-opens-the-menu-panel
  (let* ((html (shell-html))
         (panel-id (cl-ppcre:register-groups-bind (id)
                       ("<div class=\"tun-app-shell-panel\" id=\"([^\"]+)\" popover=\"auto\"" html)
                     id)))
    (is (stringp panel-id) "the menu is a popover, which opens without JavaScript")
    (is (equal (list panel-id panel-id nil) (attribute-values html "button" "popovertarget"))
        "the menu button and the close button point at it, «Logg ut» does not")
    (is (search "aria-label=\"Meny\"" html))
    (is (search "popovertargetaction=\"hide\"" html)))
  (let ((html (tun.html:render-html (tun.ui:app-shell (:title "Nordvik Utleie") "Innhold"))))
    (is (not (search "popover" html)) "a shell with no menu has no menu button")))

(test a-narrow-shell-marks-its-content-narrow
  (is (not (search "data-width" (shell-html))) "the default width needs no attribute")
  (let ((html (tun.html:render-html
               (tun.ui:app-shell (:title "Nordvik Utleie" :width :narrow) "Skjema"))))
    (is (search "<div class=\"tun-app-shell-content\" data-width=\"narrow\">Skjema</div>" html)))
  (is (search "data-width=\"wide\""
              (tun.html:render-html (tun.ui:app-shell (:title "Nordvik Utleie" :width :wide) "Tavle")))
      "a wide shell, for a board")
  (signals type-error (tun.ui:app-shell* (list :title "Nordvik Utleie" :width :huge))))

(test breadcrumbs-mark-the-current-page-and-lead-back-one-level
  (let ((html (tun.html:render-html
               (tun.ui:breadcrumbs (:items '((:label "Kunder" :href "/kunder")
                                             (:label "Ole Hansen AS" :href "/kunder/42")
                                             (:label "Rediger kunde")))))))
    (is (search "<nav class=\"tun-breadcrumbs\" aria-label=\"Brødsmuler\">" html))
    (is (search "<span aria-current=\"page\">Rediger kunde</span>" html))
    (is (equal '(nil "true" nil "true" nil) (attribute-values html "li" "aria-hidden"))
        "the separators between the levels are hidden from screen readers")
    (is (search "href=\"/kunder/42\"><svg" html))
    (is (search "Tilbake til Ole Hansen AS" html) "the phone shows the level above"))
  (is (not (search "Tilbake" (tun.html:render-html
                              (tun.ui:breadcrumbs (:items '((:label "Oversikt"))))))))
  (signals error (tun.ui:breadcrumbs (:items '()))))

(test a-page-header-has-the-one-heading-of-the-page
  (let ((html (tun.html:render-html
               (tun.ui:page-header (:title "Ole Hansen AS"
                                           :breadcrumbs '((:label "Kunder" :href "/kunder")
                                                          (:label "Ole Hansen AS"))
                                           :actions (list (tun.ui:button () "Ny ordre")))))))
    (is (= 1 (cl-ppcre:count-matches "<h1" html)))
    (is (< (search "tun-breadcrumbs" html) (search "<h1" html)))
    (is (search "tun-page-header-actions" html)))
  (is (search "<h3" (tun.html:render-html (tun.ui:section (:title "Merknader" :level 3)))))
  (signals error (tun.ui:section (:title "Merknader" :level 4))))

(test layout-options-come-from-a-small-set
  (is (search "data-gap=\"lg\"" (tun.html:render-html (tun.ui:stack (:gap :lg) "a"))))
  (is (search "data-justify=\"between\""
              (tun.html:render-html (tun.ui:cluster (:justify :between) "a"))))
  (is (search "data-min=\"xs\"" (tun.html:render-html (tun.ui:grid (:min :xs) "a"))))
  (signals error (tun.ui:stack (:gap :huge)))
  (signals error (tun.ui:cluster (:justify :around)))
  (signals error (tun.ui:grid (:min "12rem"))))
