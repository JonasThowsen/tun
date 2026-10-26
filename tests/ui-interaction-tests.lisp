;;;; tests/ui-interaction-tests.lisp -- the interaction group's markup: the
;;;; ids and ARIA attributes that tie a dialog, menu, tooltip, accordion or
;;;; set of tabs together (spec/ui.md 6).  Behaviour in a browser (keyboard,
;;;; focus, opening and closing) is checked with Playwright, not here.

(in-package #:tun.tests)

(def-suite ui-interaction :in core)
(in-suite ui-interaction)

;;; ------------------------------------------------------------------
;;; Reading markup nodes

(defun node-attributes (node)
  "The attribute plist of the element NODE, (:TAG [(:@ ...)] CHILD...)."
  (let ((second (second node)))
    (when (and (consp second) (eq (first second) :@)) (rest second))))

(defun node-attribute (node name)
  (getf (node-attributes node) name))

(defun element-node-p (node)
  (and (consp node) (keywordp (first node)) (not (eq (first node) :@))))

(defun node-children (node)
  (if (node-attributes node) (cddr node) (rest node)))

(defun find-nodes (predicate markup)
  "Every element in MARKUP, in document order, for which PREDICATE is true."
  (let ((found '()))
    (labels ((walk (node)
               (cond ((element-node-p node)
                      (when (funcall predicate node) (push node found))
                      (mapc #'walk (node-children node)))
                     ((consp node) (mapc #'walk node)))))
      (walk markup))
    (nreverse found)))

(defun nodes-with (name value markup)
  "The elements in MARKUP whose attribute NAME is VALUE."
  (find-nodes (lambda (node) (equal (node-attribute node name) value)) markup))

(defun node-with-id (id markup)
  (first (nodes-with :id id markup)))

(defun node-text (node)
  (with-output-to-string (out)
    (labels ((walk (node)
               (cond ((stringp node) (write-string node out))
                     ((element-node-p node) (mapc #'walk (node-children node)))
                     ((consp node) (mapc #'walk node)))))
      (walk node))))

;;; ------------------------------------------------------------------
;;; dialog

(test a-dialog-is-labelled-by-its-title-and-described-by-its-description
  (let* ((markup (tun.ui:dialog (:id "ny-kunde" :title "Ny kunde"
                                     :description "Fyll inn kontaktinformasjonen.")
                                "Innhold"))
         (dialog (first (nodes-with :class "tun-dialog" markup))))
    (is (eq :dialog (first dialog)))
    (is (string= "Ny kunde" (node-text (node-with-id (node-attribute dialog :aria-labelledby)
                                                     markup))))
    (is (string= "Fyll inn kontaktinformasjonen."
                 (node-text (node-with-id (node-attribute dialog :aria-describedby) markup))))
    (is (string= "dismissible" (node-attribute dialog :data-tun-dialog)))
    (is (null (node-attribute dialog :role)) "a plain dialog keeps the role of <dialog>")))

(test a-dialog-has-a-labelled-close-button-that-names-it
  (let* ((markup (tun.ui:dialog (:id "ny-kunde" :title "Ny kunde")))
         (close (first (nodes-with :command "close" markup))))
    (is (string= "ny-kunde" (node-attribute close :commandfor)))
    (is (string= "Lukk" (node-attribute close :aria-label)))
    (is (null (node-attribute (first (nodes-with :class "tun-dialog" markup))
                              :aria-describedby))
        "no description, no aria-describedby")))

(test a-confirmation-is-an-alert-dialog-without-a-close-button
  (dolist (variant '(:confirm :destructive))
    (let* ((markup (tun.ui:dialog (:id "slett" :variant variant :title "Slette ordre 1042?")))
           (dialog (first (nodes-with :class "tun-dialog" markup))))
      (is (string= "alertdialog" (node-attribute dialog :role)))
      (is (string= "confirm" (node-attribute dialog :data-tun-dialog))
          "a click outside does not close it")
      (is (null (nodes-with :command "close" markup))))))

(test a-dialog-with-an-action-wraps-its-content-in-a-form
  (let* ((markup (tun.ui:dialog (:id "slett" :variant :destructive :title "Slette?"
                                     :action "/ordre/1042/slett"
                                     :footer (list (tun.ui:button (:type "submit") "Slett")))))
         (form (first (find-nodes (lambda (node) (eq :form (first node))) markup))))
    (is (string= "/ordre/1042/slett" (node-attribute form :action)))
    (is (string= "post" (node-attribute form :method)))
    (is (nodes-with :type "submit" form) "the footer's submit button is inside the form")))

(test a-dialog-needs-an-id-and-a-title
  (signals error (tun.ui:dialog (:title "Uten id")))
  (signals error (tun.ui:dialog (:id "uten-tittel"))))

;;; ------------------------------------------------------------------
;;; dropdown-menu

(test a-dropdown-menu-button-controls-its-menu
  (let* ((markup (tun.ui:dropdown-menu (:label "Handlinger"
                                               :items (list (list :label "Rediger" :href "/x")
                                                            :separator
                                                            (list :label "Slett"
                                                                  :variant :destructive)))))
         (trigger (first (nodes-with :aria-haspopup "menu" markup)))
         (menu (first (nodes-with :role "menu" markup))))
    (is (string= (node-attribute menu :id) (node-attribute trigger :popovertarget)))
    (is (string= (node-attribute menu :id) (node-attribute trigger :aria-controls)))
    (is (string= (node-attribute trigger :id) (node-attribute menu :aria-labelledby)))
    (is (eq t (node-attribute menu :popover)))
    (is (null (node-attribute trigger :aria-expanded))
        "without the script the browser reports the popover's state itself")
    (let ((items (nodes-with :role "menuitem" markup)))
      (is (equal '(:a :button) (mapcar #'first items)))
      (is (string= "button" (node-attribute (second items) :type))))
    (is (= 1 (length (nodes-with :role "separator" markup))))))

(test a-dropdown-menu-group-is-labelled-by-its-heading
  (let* ((profile (list :label "Profil" :href "/profil"))
         (markup (tun.ui:dropdown-menu (:label "Konto"
                                               :items (list (list :group "Kari Nordmann"
                                                                  :items (list profile))))))
         (group (first (nodes-with :role "group" markup))))
    (is (string= "Kari Nordmann"
                 (node-text (node-with-id (node-attribute group :aria-labelledby) markup))))
    (is (= 1 (length (nodes-with :role "menuitem" group))))))

(test an-icon-dropdown-menu-names-its-button
  (let* ((markup (tun.ui:dropdown-menu (:label "Flere valg" :size :icon :icon :ellipsis
                                               :items (list (list :label "Vis")))))
         (trigger (first (nodes-with :aria-haspopup "menu" markup))))
    (is (string= "Flere valg" (node-attribute trigger :aria-label)))
    (is (string= "" (string-trim " " (node-text trigger))) "only the icon shows")))

(test disabled-menu-items-are-marked
  (let ((markup (tun.ui:dropdown-menu (:label "Valg"
                                              :items (list (list :label "Lenke" :href "/x"
                                                                 :disabled t)
                                                           (list :label "Knapp" :disabled t))))))
    (destructuring-bind (link button) (nodes-with :role "menuitem" markup)
      (is (string= "true" (node-attribute link :aria-disabled)))
      (is (null (node-attribute link :href)) "a disabled link leads nowhere")
      (is (eq t (node-attribute button :disabled))))))

(test a-dropdown-menu-needs-a-label-and-items
  (signals error (tun.ui:dropdown-menu (:items (list (list :label "Vis")))))
  (signals error (tun.ui:dropdown-menu (:label "Valg")))
  (signals error (tun.ui:dropdown-menu (:label "Valg" :items (list (list :href "/x"))))
           "an item needs a label"))

;;; ------------------------------------------------------------------
;;; tooltip

(test a-tooltip-describes-the-element-it-explains
  (let* ((markup (tun.ui:tooltip (:text "Kopier lenken")
                                 (tun.ui:button (:size :icon :label "Kopier")
                                                (tun.ui:icon (:name :copy)))))
         (button (first (nodes-with :class "tun-button" markup)))
         (tip (first (nodes-with :role "tooltip" markup))))
    (is (string= (node-attribute tip :id) (node-attribute button :aria-describedby)))
    (is (string= "Kopier lenken" (node-text tip)))
    (is (string= "Kopier" (node-attribute button :aria-label)) "the button keeps its name")))

(test a-tooltip-keeps-an-existing-description
  (let* ((markup (tun.ui:tooltip (:text "Mer")
                                 '(:button (:@ :type "button" :aria-describedby "hint") "?")))
         (button (first (find-nodes (lambda (node) (eq :button (first node))) markup)))
         (tip (first (nodes-with :role "tooltip" markup))))
    (is (string= (format nil "hint ~a" (node-attribute tip :id))
                 (node-attribute button :aria-describedby)))))

(test a-tooltip-explains-exactly-one-element
  (signals error (tun.ui:tooltip (:text "To") (tun.ui:button () "A") (tun.ui:button () "B")))
  (signals error (tun.ui:tooltip (:text "Tekst") "bare tekst"))
  (signals error (tun.ui:tooltip () (tun.ui:button () "A"))))

;;; ------------------------------------------------------------------
;;; accordion

(test an-exclusive-accordion-shares-one-name
  (let* ((markup (tun.ui:accordion (:exclusive t
                                               :items (list (list :title "En" :content "1" :open t)
                                                            (list :title "To" :content "2")))))
         (items (find-nodes (lambda (node) (eq :details (first node))) markup))
         (names (mapcar (lambda (item) (node-attribute item :name)) items)))
    (is (= 2 (length items)))
    (is (stringp (first names)))
    (is (equal (first names) (second names)))
    (is (equal '(t nil) (mapcar (lambda (item) (node-attribute item :open)) items)))))

(test a-plain-accordion-lets-several-stay-open
  (let ((markup (tun.ui:accordion (:items (list (list :title "En") (list :title "To"))))))
    (is (every (lambda (item) (null (node-attribute item :name)))
               (find-nodes (lambda (node) (eq :details (first node))) markup)))))

;;; ------------------------------------------------------------------
;;; tabs

(defun ordre-tabs ()
  (tun.ui:tabs (:label "Ordre 1042"
                       :items (list (list :label "Detaljer" :content "a")
                                    (list :label "Linjer" :content "b" :selected t)
                                    (list :label "Historikk" :content "c" :id "historikk")))))

(test tabs-and-panels-point-at-each-other
  (let* ((markup (ordre-tabs))
         (tabs (nodes-with :role "tab" markup))
         (panels (nodes-with :role "tabpanel" markup)))
    (is (= 3 (length tabs) (length panels)))
    (is (string= "Ordre 1042" (node-attribute (first (nodes-with :role "tablist" markup))
                                              :aria-label)))
    (loop for tab in tabs
          for panel in panels
          do (is (string= (node-attribute panel :id) (node-attribute tab :aria-controls)))
          (is (string= (node-attribute tab :id) (node-attribute panel :aria-labelledby)))
          (is (string= "0" (node-attribute panel :tabindex))))
    (is (string= "historikk" (node-attribute (third panels) :id)) "an item's :id names its panel")))

(test one-tab-is-selected-and-in-the-tab-order
  (let* ((markup (ordre-tabs))
         (tabs (nodes-with :role "tab" markup))
         (panels (nodes-with :role "tabpanel" markup)))
    (is (equal '("false" "true" "false")
               (mapcar (lambda (tab) (node-attribute tab :aria-selected)) tabs)))
    (is (equal '("-1" "0" "-1") (mapcar (lambda (tab) (node-attribute tab :tabindex)) tabs)))
    (is (equal '("false" "true" "false")
               (mapcar (lambda (panel) (node-attribute panel :data-selected)) panels)))))

(test without-selected-the-first-tab-is
  (let ((tabs (nodes-with :role "tab" (tun.ui:tabs (:label "Faner"
                                                           :items (list (list :label "A")
                                                                        (list :label "B")))))))
    (is (equal '("true" "false")
               (mapcar (lambda (tab) (node-attribute tab :aria-selected)) tabs)))))

(test every-panel-has-a-heading-for-pages-without-scripts
  (dolist (panel (nodes-with :role "tabpanel" (ordre-tabs)))
    (let ((heading (first (nodes-with :class "tun-tabs-heading" panel))))
      (is (eq :h2 (first heading)))
      (is (plusp (length (node-text heading)))))))

(test link-tabs-are-navigation-with-the-current-page-marked
  (let* ((markup (tun.ui:tabs (:label "Kunde"
                                      :items (list (list :label "Oversikt" :href "/kunder/17")
                                                   (list :label "Ordre" :href "/kunder/17/ordre"
                                                         :current t)))))
         (links (find-nodes (lambda (node) (eq :a (first node))) markup)))
    (is (eq :nav (first markup)))
    (is (string= "Kunde" (node-attribute markup :aria-label)))
    (is (null (nodes-with :role "tab" markup)) "links are not ARIA tabs")
    (is (equal '(nil "page") (mapcar (lambda (link) (node-attribute link :aria-current)) links)))))

(test tabs-are-all-links-or-all-panels
  (signals error (tun.ui:tabs (:label "Blandet"
                                      :items (list (list :label "A" :href "/a")
                                                   (list :label "B" :content "b")))))
  (signals error (tun.ui:tabs (:items (list (list :label "A"))))))

(test a-dialog-opens-on-its-shortcut
  (let ((html (tun.html:render-html
               (tun.ui:dialog (:id "sok" :title "Søk" :shortcut '("/" "Ctrl+K"))
                 (tun.ui:text-input (:label "Søk" :name "q" :attributes (list :autofocus t)))))))
    (is (search "data-tun-dialog-shortcut=\"/ Ctrl+K\"" html))
    (is (search " autofocus" (tun.html:render-html
                              (tun.html:untrusted (tun.ui:text-input (:label "Søk" :name "q"
                                                                      :attributes '(:autofocus t))))))
        "autofocus survives extension output"))
  (is (search "data-tun-dialog-shortcut=\"/\""
              (tun.html:render-html (tun.ui:dialog (:id "x" :title "X" :shortcut "/")))))
  (is (search "dialog[data-tun-dialog-shortcut]" (tun.ui:script))))
