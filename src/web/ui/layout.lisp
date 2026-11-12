;;;; web/ui/layout.lisp -- the layout and navigation group (spec/ui.md 6):
;;;; the frame of a staff page, the top of a page and its sections,
;;;; breadcrumbs, a list of links, and three layout primitives (stack,
;;;; cluster, grid).

(in-package #:tun.ui)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Layout primitives

(define-component cluster ((&key (gap :sm) (justify :start) (align :center) id attributes)
                           &rest children)
  (:group "Layout and navigation")
  (:doc "Puts its content side by side and wraps to a new line when the room runs out:
buttons, badges, filters. JUSTIFY (start, center, end, between) and ALIGN (start, center,
end, baseline, stretch) set where things go.")
  (:source "Every Layout cluster, Tailwind's flex utilities")
  (:css "
.tun-cluster {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: calc(var(--spacing) * 2);
  min-width: 0;
  &[data-gap='xs'] { gap: var(--spacing); }
  &[data-gap='md'] { gap: calc(var(--spacing) * 4); }
  &[data-gap='lg'] { gap: calc(var(--spacing) * 6); }
  &[data-gap='xl'] { gap: calc(var(--spacing) * 8); }
  &[data-justify='center'] { justify-content: center; }
  &[data-justify='end'] { justify-content: flex-end; }
  &[data-justify='between'] { justify-content: space-between; }
  &[data-align='start'] { align-items: flex-start; }
  &[data-align='end'] { align-items: flex-end; }
  &[data-align='baseline'] { align-items: baseline; }
  &[data-align='stretch'] { align-items: stretch; }
}")
  (:examples
   (("Buttons" :layout :stack)
    (cluster ()
             (button (:icon :plus) "New order")
             (button (:variant :outline :icon :download) "Export")
             (button (:variant :ghost) "More options"))
    (cluster (:justify :end)
             (button (:variant :outline) "Cancel")
             (button () "Save the quote")))
   (("Spread out and on the baseline" :layout :stack)
    (cluster (:justify :between :align :baseline)
             '(:strong "Invoice 2024-118")
             '(:span "Due on 30 October")
             '(:strong "€12,450"))))
  (check-type gap (member :xs :sm :md :lg :xl))
  (check-type justify (member :start :center :end :between))
  (check-type align (member :start :center :end :baseline :stretch))
  `(:div ,(attrs (list :class "tun-cluster" :id id :data-gap (option-string gap)
                       :data-justify (unless (eq justify :start) (option-string justify))
                       :data-align (unless (eq align :center) (option-string align)))
                 attributes)
         ,@children))

(define-component stack ((&key (gap :md) id attributes) &rest children)
  (:group "Layout and navigation")
  (:doc "Puts its content one under another with an even space (GAP: xs, sm, md, lg or xl).
Use it instead of margins when parts of a page need room between them.")
  (:source "Every Layout stack, Tailwind's spacing scale")
  (:css "
.tun-stack {
  display: flex;
  flex-direction: column;
  gap: calc(var(--spacing) * 4);
  min-width: 0;
  &[data-gap='xs'] { gap: var(--spacing); }
  &[data-gap='sm'] { gap: calc(var(--spacing) * 2); }
  &[data-gap='lg'] { gap: calc(var(--spacing) * 6); }
  &[data-gap='xl'] { gap: calc(var(--spacing) * 8); }
}")
  (:examples
   (("Spaces" :layout :stack)
    (stack (:gap :xs)
           '(:strong "Ole Hansen Ltd")
           '(:span "Storgata 12, 0155 Oslo")
           '(:span "ole@example.com"))
    (stack (:gap :lg)
           '(:p "The order has been packed and sent with Bring.")
           '(:p "The customer gets the tracking number by email when the parcel is registered.")
           (cluster () (button (:variant :outline) "Show the order") (button () "Send invoice")))))
  (check-type gap (member :xs :sm :md :lg :xl))
  `(:div ,(attrs (list :class "tun-stack" :id id :data-gap (option-string gap)) attributes)
         ,@children))

(define-component grid ((&key (min :md) (gap :md) id attributes) &rest children)
  (:group "Layout and navigation")
  (:doc "A grid that fills the row with as many columns as fit, each at least MIN wide (xs
10rem, sm 14rem, md 18rem, lg 24rem). On a phone it becomes one column by itself.")
  (:source "Every Layout grid (auto-fit and minmax)")
  (:css "
.tun-grid {
  --tun-grid-min: 18rem;
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(var(--tun-grid-min), 100%), 1fr));
  gap: calc(var(--spacing) * 4);
  min-width: 0;
  &[data-min='xs'] { --tun-grid-min: 10rem; }
  &[data-min='sm'] { --tun-grid-min: 14rem; }
  &[data-min='lg'] { --tun-grid-min: 24rem; }
  &[data-gap='xs'] { gap: var(--spacing); }
  &[data-gap='sm'] { gap: calc(var(--spacing) * 2); }
  &[data-gap='lg'] { gap: calc(var(--spacing) * 6); }
  &[data-gap='xl'] { gap: calc(var(--spacing) * 8); }
}")
  (:examples
   (("Narrow columns (xs)" :layout :stack)
    (grid (:min :xs :gap :sm)
          '(:p "Open orders: 7")
          '(:p "To be invoiced: 3")
          '(:p "Overdue: 1")
          '(:p "Sent today: 12")))
   (("Wide columns (md)" :layout :stack)
    (grid ()
          (stack (:gap :xs) '(:strong "Ole Hansen Ltd") '(:span "Storgata 12, 0155 Oslo"))
          (stack (:gap :xs) '(:strong "Fjord Catering") '(:span "Bryggen 3, 5003 Bergen"))
          (stack (:gap :xs) '(:strong "Northern Lights Events and Tents") '(:span "Tromsø")))))
  (check-type min (member :xs :sm :md :lg))
  (check-type gap (member :xs :sm :md :lg :xl))
  `(:div ,(attrs (list :class "tun-grid" :id id :data-min (option-string min)
                       :data-gap (option-string gap))
                 attributes)
         ,@children))

;;; ------------------------------------------------------------------
;;; Breadcrumbs

(defun breadcrumbs-trail (items)
  "The list items of the breadcrumb trail ITEMS: a link for each level above
the current page, a chevron between them, and the current page last."
  (loop for (item . more) on items
        for label = (getf item :label)
        append (if more
                   (list `(:li (:@ :class "tun-breadcrumbs-item")
                               (:a (:@ :href ,(getf item :href)) ,label))
                         `(:li (:@ :class "tun-breadcrumbs-separator" :aria-hidden "true")
                               ,(icon (:name :chevron-right))))
                   (list `(:li (:@ :class "tun-breadcrumbs-item")
                               (:span (:@ :aria-current "page") ,label))))))

(define-component breadcrumbs ((&key items id attributes))
  (:group "Layout and navigation")
  (:doc "Shows where the page is: the levels above it as links and the page itself last.
ITEMS is a list of (:label TEXT :href PATH); the last is the page you are on. On a narrow
screen only a link back to the level above shows.")
  (:source "Basecoat breadcrumb (Vega); GOV.UK back link on a phone")
  (:css "
.tun-breadcrumbs {
  container-type: inline-size;
  font-size: var(--text-sm);
  line-height: var(--text-sm--line-height);
  color: var(--muted-foreground);
  & a {
    border-radius: var(--radius-sm);
    text-decoration: none;
    transition: color var(--duration-fast) var(--ease);
    @media (hover: hover) {
      &:hover { color: var(--foreground); }
    }
    &:active { background-color: var(--pressed); }
  }
  & ol {
    display: none;
    flex-wrap: wrap;
    align-items: center;
    gap: calc(var(--spacing) * 1.5);
    overflow-wrap: anywhere;
  }
  & .tun-breadcrumbs-item,
  & .tun-breadcrumbs-separator {
    display: inline-flex;
    align-items: center;
    gap: calc(var(--spacing) * 1.5);
  }
  & .tun-breadcrumbs-separator {
    user-select: none;
    & .tun-icon { width: calc(var(--spacing) * 3.5); height: calc(var(--spacing) * 3.5); }
  }
  & [aria-current='page'] { color: var(--foreground); cursor: default; }
  & .tun-breadcrumbs-back {
    display: inline-flex;
    align-items: center;
    gap: calc(var(--spacing) * 1.5);
    min-height: calc(var(--spacing) * 6);
    & .tun-icon { width: calc(var(--spacing) * 3.5); height: calc(var(--spacing) * 3.5); }
  }
  /* A whole trail rarely fits a phone, and the level above is the one
     people go back to.  Without a level above, the trail is all there is. */
  & ol:first-child { display: flex; }
  @container (min-width: 30rem) {
    & ol { display: flex; }
    & .tun-breadcrumbs-back { display: none; }
  }
}")
  (:examples
   (("Three levels" :layout :stack)
    (breadcrumbs (:items '((:label "Customers" :href "/customers")
                           (:label "Ole Hansen Ltd" :href "/customers/42")
                           (:label "Edit the customer")))))
   (("Many levels and a long text" :layout :stack)
    (breadcrumbs (:items '((:label "Overview" :href "/")
                           (:label "Orders" :href "/orders")
                           (:label "Order 1042 – Northern Lights Events and Tents Ltd"
                            :href "/orders/1042")
                           (:label "Packing slip and waybill")))))
   (("Only the page itself" :layout :stack)
    (breadcrumbs (:items '((:label "Overview"))))))
  (check-type items cons)
  (let ((parent (when (rest items) (first (last items 2)))))
    `(:nav ,(attrs (list :class "tun-breadcrumbs" :id id :aria-label (tr "Breadcrumbs"))
                   attributes)
           ,@(when parent
               (list `(:a (:@ :class "tun-breadcrumbs-back" :href ,(getf parent :href))
                          ,(icon (:name :arrow-left))
                          ,(tr "Back to ~a" (getf parent :label)))))
           (:ol ,@(breadcrumbs-trail items)))))

;;; ------------------------------------------------------------------
;;; Lists of links

(defun path-below-p (path href)
  "True when PATH is a page below HREF: /customers/42 is below /customers, and
nothing is below the front page /."
  (and (> (length path) (length href))
       (string= href path :end2 (length href))
       (char= #\/ (char path (length href)))
       (string/= href "/")))

(defun nav-list-marked (hrefs current)
  "Which of HREFS to mark when the page is CURRENT, and how.  Values the href
and \"page\" when one of them is CURRENT, else the longest href CURRENT lies
below and \"true\" (GOV.UK's active section), else NIL."
  (cond ((null current) nil)
        ((member current hrefs :test #'string=) (values current "page"))
        (t (let ((section (loop with best = nil
                                for href in hrefs
                                when (and (path-below-p current href)
                                          (> (length href) (length best)))
                                do (setf best href)
                                finally (return best))))
             (when section (values section "true"))))))

(defun nav-list-link (item marked mark)
  (destructuring-bind (&key label href icon count) item
    `(:li (:a (:@ :class "tun-nav-list-link" :href ,href
                  :aria-current ,(when (equal href marked) mark))
              ,@(when icon (list (icon (:name icon))))
              (:span (:@ :class "tun-nav-list-label") ,label)
              ,@(when count (list `(:span (:@ :class "tun-nav-list-count") ,count)))))))

(defun nav-list-group (group marked mark)
  (destructuring-bind (&key heading items) group
    (let ((heading-id (when heading (element-id "tun-nav-list-heading"))))
      `(:div (:@ :class "tun-nav-list-group")
             ,@(when heading
                 (list `(:div (:@ :class "tun-nav-list-heading" :id ,heading-id) ,heading)))
             (:ul (:@ :aria-labelledby ,heading-id)
                  ,@(mapcar (lambda (item) (nav-list-link item marked mark)) items))))))

(define-component nav-list ((&key label items groups current id attributes))
  (:group "Layout and navigation")
  (:doc "A vertical list of links, for a menu in the page or a settings page. ITEMS are links
(:label :href :icon :count); GROUPS are groups (:heading TEXT :items LINKS). The link to
CURRENT is marked; when there is none, the nearest link above it is (/customers for
/customers/42). LABEL names the menu for screen readers.")
  (:source "Basecoat sidebar menu (Vega); GOV.UK service navigation for aria-current")
  (:css "
.tun-nav-list {
  display: flex;
  flex-direction: column;
  gap: calc(var(--spacing) * 4);
  font-size: var(--text-sm);
  line-height: var(--text-sm--line-height);
  & .tun-nav-list-group { display: flex; flex-direction: column; gap: var(--spacing); }
  & ul { display: flex; flex-direction: column; gap: var(--spacing); }
  & .tun-nav-list-heading {
    display: flex;
    align-items: center;
    min-height: calc(var(--spacing) * 8);
    padding-inline: calc(var(--spacing) * 2);
    font-size: var(--text-xs);
    line-height: var(--text-xs--line-height);
    font-weight: var(--font-weight-medium);
    color: var(--muted-foreground);
  }
  & .tun-nav-list-link {
    display: flex;
    align-items: center;
    gap: calc(var(--spacing) * 2);
    min-height: calc(var(--spacing) * 8);
    padding: calc(var(--spacing) * 1.5) calc(var(--spacing) * 2);
    border: 1px solid transparent;
    border-radius: var(--radius-md);
    color: var(--foreground);
    text-decoration: none;
    outline: none;
    transition-property: background-color, border-color, box-shadow;
    transition-duration: var(--duration-fast);
    transition-timing-function: var(--ease);
    &:focus-visible { box-shadow: var(--focus-ring); }
    @media (hover: hover) {
      &:hover { background-color: var(--accent); color: var(--accent-foreground); }
    }
    /* The current entry stands out as a panel of the page's ground in its
       frame, at the weight of the others, so marking it moves nothing. */
    &[aria-current] {
      border-color: var(--border);
      background-color: var(--background);
      box-shadow: var(--shadow-xs);
    }
    &:active { background-color: var(--pressed); transition-duration: 0s; }
    & .tun-icon { color: var(--muted-foreground); }
    &[aria-current] .tun-icon { color: var(--foreground); }
  }
  & .tun-nav-list-label { flex: 1; min-width: 0; overflow-wrap: anywhere; }
  & .tun-nav-list-count {
    flex-shrink: 0;
    min-width: calc(var(--spacing) * 5);
    font-size: var(--text-xs);
    line-height: var(--text-xs--line-height);
    font-weight: var(--font-weight-medium);
    font-variant-numeric: tabular-nums;
    text-align: end;
    color: var(--muted-foreground);
  }
  /* A finger needs the bigger target; the text grows with it. */
  @media (pointer: coarse) {
    font-size: var(--text-base);
    line-height: var(--text-base--line-height);
    & .tun-nav-list-link { min-height: var(--control-height); }
    & .tun-nav-list-link .tun-icon {
      width: calc(var(--spacing) * 5);
      height: calc(var(--spacing) * 5);
    }
    & .tun-nav-list-count { font-size: var(--text-sm); }
  }
}")
  (:examples
   (("Settings in groups" :layout :stack)
    (nav-list (:label "Settings"
                      :current "/settings/users"
                      :groups '((:heading "Company"
                                 :items ((:label "Company details" :href "/settings/company"
                                                 :icon :building)
                                         (:label "Users" :href "/settings/users"
                                                 :icon :users :count 4)
                                         (:label "Access and roles" :href "/settings/access"
                                                 :icon :shield-check)))
                                (:heading "Sales"
                                 :items ((:label "Invoices and terms of payment"
                                                 :href "/settings/invoices" :icon :receipt)
                                         (:label "Shipping" :href "/settings/shipping" :icon :truck)
                                         (:label "Exporting accounting data to the accountant"
                                                 :href "/settings/export" :icon :download
                                                 :count 12)))))))
   (("Without icons, below a chosen page" :layout :stack)
    (nav-list (:label "Customer"
                      :current "/customers/42/orders/1042"
                      :items '((:label "Overview" :href "/customers/42")
                               (:label "Orders" :href "/customers/42/orders" :count 18)
                               (:label "Invoices" :href "/customers/42/invoices" :count 2)
                               (:label "Notes" :href "/customers/42/notes"))))))
  (check-type label string)
  `(:nav ,(attrs (list :class "tun-nav-list" :id id :aria-label label) attributes)
         ,@(let ((groups (or groups (list (list :items items)))))
             (multiple-value-bind (marked mark)
                 (nav-list-marked (loop for group in groups
                                        append (mapcar (lambda (item) (getf item :href))
                                                       (getf group :items)))
                                  current)
               (mapcar (lambda (group) (nav-list-group group marked mark)) groups)))))

;;; ------------------------------------------------------------------
;;; The page header's actions (spec/ui.md 6, page-header)
;;;
;;; The header reads the actions it is given as markup: a button (the
;;; button component, a link or a button), a form holding one, or anything
;;; else.  It reckons whether they fit beside the title on the narrowest
;;; phone, and when they do not, folds the buttons that are not filled into
;;; a «More actions» menu, which the CSS shows only on a phone.

(defun node-attributes (node)
  "The attribute plist of the markup NODE, (TAG (:@ ...) CHILD...), or NIL."
  (let ((second (and (consp node) (second node))))
    (and (consp second) (eq (first second) :@) (rest second))))

(defun node-children (node)
  "The children of the markup NODE."
  (if (node-attributes node) (cddr node) (rest node)))

(defun node-tag (node)
  (and (consp node) (keywordp (first node)) (first node)))

(defun node-with-attributes (node &rest plist)
  "NODE with PLIST's attributes added, replacing any of the same name."
  (list* (first node) (attrs (node-attributes node) plist) (node-children node)))

(defun node-text (node)
  "The words in NODE: its text, without icons and key caps."
  (cond ((stringp node) node)
        ((numberp node) (princ-to-string node))
        ((member (node-tag node) '(:svg :kbd)) "")
        ((node-tag node) (format nil "~{~a~}" (mapcar #'node-text (node-children node))))
        ((consp node) (format nil "~{~a~}" (mapcar #'node-text node)))
        (t "")))

(defun squeezed-text (text)
  "TEXT trimmed, its runs of white space one space."
  (format nil "~{~a~^ ~}" (uiop:split-string (string-trim '(#\Space #\Tab #\Newline) text)
                                             :separator '(#\Space #\Tab #\Newline))))

(defun button-node-p (node)
  (and (member (node-tag node) '(:a :button))
       (equal (getf (node-attributes node) :class) "tun-button")))

(defun form-button (node)
  "The one button of NODE when it is a form holding one button, else NIL."
  (when (eq (node-tag node) :form)
    (let ((buttons (remove-if-not #'button-node-p (node-children node))))
      (and buttons (null (rest buttons)) (first buttons)))))

(defun action-button (node)
  "The button the header action NODE is, or holds as a form; else NIL."
  (if (button-node-p node) node (form-button node)))

(defun filled-action-p (node)
  "True for an action that is the filled (primary) button, the one next step."
  (let ((button (action-button node)))
    (and button (equal (getf (node-attributes button) :data-variant) "primary"))))

(defun button-label (button)
  "What BUTTON says: its words, else its aria-label."
  (let ((words (squeezed-text (node-text button))))
    (if (plusp (length words)) words (or (getf (node-attributes button) :aria-label) ""))))

(defun button-width (button)
  "How wide BUTTON is on a phone, reckoned in rem (spec/ui.md 6, page-header)."
  (let ((size (or (getf (node-attributes button) :data-size) "")))
    (if (and (>= (length size) 4) (string= "icon" size :end2 4))
        2.75
        (+ 1.25
           (* 1.375 (count :svg (node-children button) :key #'node-tag))
           (* 0.5 (length (squeezed-text (node-text button))))))))

(defun action-width (node)
  "How wide the header action NODE is on a phone, in rem: a button's or a
form's button's, a menu's button's, anything else 6rem."
  (let ((button (or (action-button node)
                    (and (eq (node-tag node) :div)
                         (equal (getf (node-attributes node) :class) "tun-dropdown-menu")
                         (find-if #'button-node-p (node-children node))))))
    (if button (button-width button) 6)))

(defun actions-fit-p (title widths)
  "True when actions WIDTHS wide (rem) fit beside TITLE on a 320px phone,
whose content is 18rem wide: the title keeps the room of its words, at most
6rem, and 1rem between it and the actions."
  (<= (+ (reduce #'+ widths)
         (* 0.5 (max 0 (1- (length widths))))
         1
         (min 6 (* 0.75 (length (squeezed-text (node-text title))))))
      18))

(defun folded-item (node form-id)
  "The «More actions» menu's item for the header action NODE, whose form,
when it is one, has FORM-ID."
  (let* ((button (action-button node))
         (attributes (node-attributes button)))
    (list :label (button-label button)
          :icon (find :svg (node-children button) :key #'node-tag)
          :href (getf attributes :href)
          :variant (when (equal (getf attributes :data-variant) "destructive") :destructive)
          :disabled (or (getf attributes :disabled)
                        (equal (getf attributes :aria-disabled) "true"))
          :attributes (append (when form-id (list :type "submit" :form form-id))
                              (loop for (key value) on attributes by #'cddr
                                    unless (member key '(:class :id :data-variant :data-size
                                                         :aria-label :aria-keyshortcuts :href
                                                         :aria-disabled :disabled))
                                      append (list key value))))))

(defun compact-action (node)
  "The filled action NODE showing its icon alone on a phone, when it has one."
  (let ((button (action-button node)))
    (cond ((not (find :svg (node-children button) :key #'node-tag)) node)
          ((eq node button) (node-with-attributes node :data-tun-compact t))
          (t (list* (first node) (cons :@ (node-attributes node))
                    (mapcar (lambda (child)
                              (if (eq child button)
                                  (node-with-attributes child :data-tun-compact t)
                                  child))
                            (node-children node)))))))

(defun header-actions (title actions)
  "The header's row of ACTIONS beside TITLE: the others, then the «More
actions» menu when some fold, then the filled ones (spec/ui.md 6)."
  (let* ((actions (remove nil actions))
         (filled (remove-if-not #'filled-action-p actions))
         (others (remove-if #'filled-action-p actions)))
    (if (actions-fit-p title (mapcar #'action-width actions))
        (append others filled)
        (let* ((foldable (remove-if-not #'action-button others))
               (forms (mapcar (lambda (node)
                                (and (eq (node-tag node) :form)
                                     (or (getf (node-attributes node) :id)
                                         (element-id "tun-page-header-form"))))
                              foldable))
               (kept (remove-if #'action-button others))
               (fits (actions-fit-p title (append (mapcar #'action-width kept)
                                                  (when foldable (list 2.75))
                                                  (mapcar #'action-width filled)))))
          (append (mapcar (lambda (node)
                            (let ((form-id (let ((at (position node foldable)))
                                             (and at (nth at forms)))))
                              (cond ((not (member node foldable)) node)
                                    (form-id (node-with-attributes node :id form-id
                                                                        :data-tun-folded t))
                                    (t (node-with-attributes node :data-tun-folded t)))))
                          others)
                  (when foldable
                    (list `(:div (:@ :class "tun-page-header-more")
                                 ,(dropdown-menu* (list :label (tr "More actions") :size :icon
                                                        :variant :ghost :icon :ellipsis
                                                        :align :end
                                                        :items (mapcar #'folded-item
                                                                       foldable forms))))))
                  (if fits filled (mapcar #'compact-action filled)))))))

;;; ------------------------------------------------------------------
;;; The top of a page and its sections

(define-component page-header ((&key title description meta breadcrumbs actions id attributes)
                               &rest children)
  (:group "Layout and navigation")
  (:doc "The top of a page: breadcrumbs (BREADCRUMBS, or as children), the title as the only
h1 and the page's actions (ACTIONS, a list of buttons) beside it on one row, a phone's too, the
filled button (the one next step) last at the right edge. On a phone the actions that do not
fit fold into a «More actions» menu. META is a row of live facts under the title, such as a
status badge; DESCRIPTION a sentence under it, which Tun's own pages do not use.")
  (:source "shadcn/ui dashboard page heading, in Basecoat's tokens; the owner's rules for an
admin application, 2026-11")
  (:css "
.tun-page-header {
  container: tun-page-header / inline-size;
  display: flex;
  flex-direction: column;
  gap: calc(var(--spacing) * 3);
  /* The title and the actions share one row at every width: the actions
     at the right edge, never wrapping; the title wraps beside them. */
  & .tun-page-header-row {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: calc(var(--spacing) * 4);
  }
  & .tun-page-header-text {
    display: flex;
    flex: 1 1 0;
    flex-direction: column;
    gap: calc(var(--spacing) * 1.5);
    min-width: 0;
  }
  & .tun-page-header-title {
    font-size: var(--text-2xl);
    line-height: var(--text-2xl--line-height);
    font-weight: var(--font-weight-semibold);
    letter-spacing: -0.025em;
    /* A word longer than the line breaks with a hyphen where the page's
       language has one for it, else anywhere. */
    hyphens: auto;
    overflow-wrap: anywhere;
  }
  & .tun-page-header-description { color: var(--muted-foreground); max-width: 65ch; }
  & .tun-page-header-meta {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: calc(var(--spacing) * 2);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    color: var(--muted-foreground);
  }
  /* The actions stand on the title's first line: a control is as high as
     that line, near enough, so the two are centred on each other. */
  & .tun-page-header-actions {
    display: flex;
    flex-shrink: 0;
    align-items: center;
    gap: calc(var(--spacing) * 2);
    min-height: var(--text-2xl--line-height);
  }
  & .tun-page-header-more { display: none; }
  /* A phone: what folds hides from the row and the menu holds it; a filled
     action that must give room shows its icon alone, its words its name. */
  @container tun-page-header (width < 40rem) {
    & .tun-page-header-actions > [data-tun-folded] { display: none; }
    & .tun-page-header-more { display: contents; }
    & .tun-page-header-actions [data-tun-compact] {
      width: var(--control-height);
      padding: 0;
      gap: 0;
      font-size: 0;
    }
  }
  @container tun-page-header (width >= 48rem) {
    & .tun-page-header-title {
      font-size: var(--text-3xl);
      line-height: var(--text-3xl--line-height);
    }
    & .tun-page-header-actions { min-height: var(--text-3xl--line-height); }
  }
}")
  (:examples
   (("With breadcrumbs, live facts and actions" :layout :stack)
    (page-header (:title "Ole Hansen Ltd"
                         :meta (list (badge (:variant :success) "Active")
                                     "Customer since March 2021")
                         :breadcrumbs '((:label "Customers" :href "/customers")
                                        (:label "Ole Hansen Ltd"))
                         :actions (list (button (:variant :outline :icon :pencil) "Edit")
                                        (button (:icon :plus) "New order")))))
   (("Only a title" :layout :stack)
    (page-header (:title "Customers")))
   (("A long title and three actions: on a phone, «More actions»" :layout :stack)
    (page-header (:title "Quote 2024-031: A summer party with a tent for Fjord Catering"
                         :breadcrumbs '((:label "Quotes" :href "/quotes")
                                        (:label "Quote 2024-031"))
                         :actions (list (button (:icon :send) "Send to the customer")
                                        (button (:variant :outline :icon :eye
                                                 :href "/quotes/2024-031/preview")
                                                "Preview")
                                        `(:form (:@ :method "post"
                                                    :action "/quotes/2024-031/withdraw")
                                                ,(button (:type "submit" :variant :destructive
                                                          :icon :trash)
                                                         "Withdraw"))))))
   (("A title of one long word" :layout :stack)
    (page-header (:title "Leveringsbetingelsesdokumentasjonsoversikten"
                         :actions (list (button (:variant :outline :icon :copy) "Duplicate")
                                        (button (:variant :outline :icon :download) "Export")
                                        (button (:icon :pencil) "Edit")))))
   (("Icon actions that fit" :layout :stack)
    (page-header (:title "Items"
                         :actions (list (button (:variant :outline :size :icon :label "Search"
                                                 :icon :search))
                                        (button (:variant :outline :size :icon :label "Filter"
                                                 :icon :funnel))
                                        (button (:icon :plus) "New item")))))
   (("With a description, for a client that wants one" :layout :stack)
    (page-header (:title "Ole Hansen Ltd"
                         :description "A customer since March 2021. Invoiced monthly, 14 days."))))
  (check-type title (not null))
  `(:header ,(attrs (list :class "tun-page-header" :id id) attributes)
            ,@(when breadcrumbs (list (breadcrumbs (:items breadcrumbs))))
            ,@children
            (:div (:@ :class "tun-page-header-row")
                  (:div (:@ :class "tun-page-header-text")
                        (:h1 (:@ :class "tun-page-header-title") ,title)
                        ,@(when description
                            (list `(:p (:@ :class "tun-page-header-description")
                                       ,description))))
                  ,@(when (remove nil actions)
                      (list `(:div (:@ :class "tun-page-header-actions")
                                   ,@(header-actions title actions)))))
            ,@(let ((meta (if (or (node-tag meta) (stringp meta)) (list meta) (remove nil meta))))
                (when meta
                  (list `(:div (:@ :class "tun-page-header-meta") ,@meta))))))

(define-component section ((&key title description meta actions (level 2) id attributes)
                           &rest children)
  (:group "Layout and navigation")
  (:doc "A part of a page with a heading of its own (h2, or h3 with LEVEL 3) and actions that
concern only this part. In an app-shell or a stack the sections get room between them. ID lets
section-links lead to it. META is a row of this part's live facts under the heading, as a page
header's, such as a count or a status badge; never put them among the actions. DESCRIPTION, a
sentence under the heading, is for a client that wants one; Tun's own pages do not use it.")
  (:source "Basecoat card header (Vega), without the card")
  (:css "
.tun-section {
  display: flex;
  flex-direction: column;
  gap: calc(var(--spacing) * 4);
  min-width: 0;
  & .tun-section-header {
    display: flex;
    flex-wrap: wrap;
    align-items: flex-start;
    justify-content: space-between;
    gap: calc(var(--spacing) * 3);
  }
  & .tun-section-text {
    display: flex;
    flex: 1 1 18rem;
    flex-direction: column;
    gap: var(--spacing);
    min-width: 0;
  }
  & .tun-section-title {
    font-size: var(--text-lg);
    line-height: var(--text-lg--line-height);
    font-weight: var(--font-weight-semibold);
    letter-spacing: -0.0125em;
    overflow-wrap: anywhere;
  }
  & h3.tun-section-title {
    font-size: var(--text-base);
    line-height: var(--text-base--line-height);
  }
  /* The part's live facts, in the look of the page header's. */
  & .tun-section-meta {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: calc(var(--spacing) * 2);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    color: var(--muted-foreground);
  }
  & .tun-section-description {
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    color: var(--muted-foreground);
    max-width: 65ch;
  }
  & .tun-section-actions {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: calc(var(--spacing) * 2);
  }
}")
  (:examples
   (("With an action, and a description for a client that wants one" :layout :stack)
    (section (:title "Contacts"
                     :description "The first gets order confirmations and invoices by email."
                     :actions (list (button (:variant :outline :size :sm :icon :user-plus)
                                            "Add")))
             '(:p "Kari Nordmann, managing director – kari@example.com – 912 34 567")
             '(:p "Per Olsen, purchasing – per@example.com")))
   (("With live facts under the heading" :layout :stack)
    (section (:title "Order lines"
                     :meta (list "3 lines" (badge (:variant :info) "With the customer"))
                     :actions (list (button (:variant :outline :size :sm :icon :plus)
                                            "Add a line")))
             '(:p "Tent 6 × 12 m, 2 units; Folding table, 20 units; Bench, 40 units")))
   (("Two sections in a stack, the last with h3" :layout :stack)
    (stack (:gap :xl)
           (section (:title "Delivery address")
                    '(:p "Storgata 12, 0155 Oslo"))
           (section (:title "Notes for the driver" :level 3)
                    '(:p "Call ahead. The gate is locked after 4 pm."))))
   (("A long title and several actions" :layout :stack)
    (section (:title "Order lines waiting for goods from the supplier"
                     :actions (list (button (:variant :ghost :size :sm) "Show all")
                                    (button (:variant :outline :size :sm :icon :refresh-cw)
                                            "Check the stock")))
             '(:p "3 lines are waiting. Delivery expected on 18 October."))))
  (check-type title (not null))
  (check-type level (member 2 3))
  `(:section ,(attrs (list :class "tun-section" :id id) attributes)
             (:div (:@ :class "tun-section-header")
                   (:div (:@ :class "tun-section-text")
                         (,(if (= level 3) :h3 :h2) (:@ :class "tun-section-title") ,title)
                         ,@(let ((meta (if (or (node-tag meta) (stringp meta))
                                           (list meta)
                                           (remove nil meta))))
                             (when meta
                               (list `(:div (:@ :class "tun-section-meta") ,@meta))))
                         ,@(when description
                             (list `(:p (:@ :class "tun-section-description") ,description))))
                   ,@(when actions
                       (list `(:div (:@ :class "tun-section-actions") ,@actions))))
             ,@children))

;;; ------------------------------------------------------------------
;;; A short muted line in a page's flow

(define-component note ((&key id attributes) &rest children)
  (:group "Layout and navigation")
  (:doc "A short muted line in a page's flow that says what follows from what is beside it:
under a pair of buttons («Your answer goes to Nordvik Bakery Ltd.»), under a table («The first
100 found; search to narrow them.»). Not a field's hint, a table's caption, an empty list's
text, a live fact (META) or a message that something happened (flash, alert).")
  (:source "Tun's own, after its owner's rules for an admin application, 2026-11")
  (:css "
.tun-note {
  margin: 0;
  max-width: 65ch;
  font-size: var(--text-sm);
  line-height: var(--text-sm--line-height);
  color: var(--muted-foreground);
  overflow-wrap: break-word;
}")
  (:examples
   (("Under a pair of buttons" :layout :stack)
    (stack (:gap :sm)
      (cluster ()
        (button () "Accept the quote")
        (button (:variant :outline) "Decline"))
      (note () "Your answer goes to Nordvik Bakery Ltd.")))
   (("Under a table" :layout :stack)
    (stack (:gap :sm)
      (table (:caption "Customers" :caption-hidden t
              :columns '("Name" "Email")
              :rows '(("Nordvik Bakery Ltd" "post@nordvik.example")
                      ("Fjord Events" "hello@fjord.example"))))
      (note () "The first 100 found; search to narrow them."))))
  `(:p ,(attrs (list :class "tun-note" :id id) attributes) ,@children))

(define-component section-links ((&key label items id attributes))
  (:group "Layout and navigation")
  (:doc "A row of links to the sections of a page read as a whole, such as a record's details,
lines and history: ITEMS is a list of (:label TEXT :href \"#ID\"), LABEL names the row for
screen readers. The row stays one line and scrolls sideways on a phone. Where scripts run, the
link of the section in view is marked. Use tabs only for parts seen one at a time.")
  (:source "GOV.UK contents list; the owner's rules for an admin application, 2026-11")
  (:css "
.tun-section-links {
  min-width: 0;
  /* One line that scrolls in its own box.  The box reaches a link's
     padding past the row's edges, so the first link's words line up with
     the page's edge, and keeps 4px inside it, the focus ring's reach, so
     the ring is not cut off. */
  & ul {
    display: flex;
    gap: var(--spacing);
    margin: -4px calc(var(--spacing) * -2.5 - 4px);
    padding: 4px;
    overflow-x: auto;
    overscroll-behavior-x: contain;
    scrollbar-width: none;
    white-space: nowrap;
  }
  & li { flex-shrink: 0; }
  & a {
    display: inline-flex;
    align-items: center;
    min-height: var(--control-height-sm);
    padding-inline: calc(var(--spacing) * 2.5);
    border-radius: var(--radius-md);
    color: var(--muted-foreground);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    font-weight: var(--font-weight-medium);
    text-decoration-line: underline;
    text-decoration-color: transparent;
    text-decoration-thickness: 2px;
    text-underline-offset: calc(var(--spacing) * 1.5);
    outline: none;
    transition-property: color, background-color, text-decoration-color, box-shadow;
    transition-duration: var(--duration-fast);
    transition-timing-function: var(--ease);
    &:focus-visible { box-shadow: var(--focus-ring); }
    @media (hover: hover) {
      &:hover { background-color: var(--accent); color: var(--foreground); }
    }
    &:active { background-color: var(--pressed); transition-duration: 0s; }
    /* The section in view: the text colour and an underline, at the weight
       and size of the others, so marking it moves nothing. */
    &[aria-current] { color: var(--foreground); text-decoration-color: currentColor; }
    @media (pointer: coarse) { min-height: var(--control-height); }
  }
}")
  (:script "
// The link of the section in view: the last section whose top has passed
// the top of the content, where following its link puts it (its
// scroll-margin-top, under a sticky header), else the first.  At the foot
// of the page, where the last sections cannot reach the top, the section a
// followed link named when its top is in the window.
const linksOf = (nav) => [...nav.querySelectorAll('a[href^=\"#\"]')]
  .map((link) => ({ link, target: document.getElementById(
    decodeURIComponent(link.getAttribute('href').slice(1))) }))
  .filter(({ target }) => target);
const inView = (entries) => {
  let current = entries[0];
  for (const entry of entries) {
    const top = entry.target.getBoundingClientRect().top;
    if (top <= parseFloat(getComputedStyle(entry.target).scrollMarginTop) + 1) current = entry;
  }
  const root = document.documentElement;
  if (root.scrollTop > 0 && innerHeight + root.scrollTop >= root.scrollHeight - 2) {
    const shown = entries.filter(({ target }) => {
      const top = target.getBoundingClientRect().top;
      return top >= 0 && top < innerHeight;
    });
    current = shown.find(({ target }) => '#' + target.id === location.hash) || current;
  }
  return current;
};
// The marked link in sight in its row, which scrolls sideways; the page
// itself is not moved.
const showInRow = (link) => {
  const row = link.closest('ul');
  const box = link.getBoundingClientRect();
  const inside = row.getBoundingClientRect();
  if (box.left < inside.left) row.scrollLeft -= inside.left - box.left;
  else if (box.right > inside.right) row.scrollLeft += box.right - inside.right;
};
const mark = () => {
  for (const nav of document.querySelectorAll('[data-tun-section-links]')) {
    const entries = linksOf(nav);
    if (entries.length === 0) continue;
    const current = inView(entries);
    for (const { link } of entries) {
      if (link === current.link) {
        if (!link.hasAttribute('aria-current')) {
          link.setAttribute('aria-current', 'location');
          showInRow(link);
        }
      } else link.removeAttribute('aria-current');
    }
  }
};
let pending = false;
const later = () => {
  if (pending) return;
  pending = true;
  requestAnimationFrame(() => { pending = false; mark(); });
};
document.addEventListener('scroll', later, { passive: true });
window.addEventListener('resize', later);
window.addEventListener('hashchange', later);
tunOnContent(later);")
  (:examples
   (("A record's sections" :layout :stack)
    (section-links (:label "On this page"
                    :items '((:label "Details" :href "#order-details")
                             (:label "Order lines" :href "#order-lines")
                             (:label "Delivery" :href "#order-delivery")
                             (:label "Invoices and payments" :href "#order-invoices")
                             (:label "History" :href "#order-history"))))
    (stack (:gap :xl)
           (section (:title "Details" :id "order-details")
                    (summary-list (:rows '(("Customer" "Hansen Bakery Ltd")
                                           ("Ordered" "3 October 2026")
                                           ("Reference" "Spring fair")))))
           (section (:title "Order lines" :id "order-lines")
                    '(:p "Wheat flour 25 kg, 10 sacks.")
                    '(:p "Rye flour 25 kg, 4 sacks."))
           (section (:title "Delivery" :id "order-delivery")
                    '(:p "Storgata 12, 0155 Oslo, on 18 October before 7 am."))
           (section (:title "Invoices and payments" :id "order-invoices")
                    '(:p "Invoice 2026-118, €12,450, due on 30 October."))
           (section (:title "History" :id "order-history")
                    '(:p "Created by Kari Nordmann on 3 October 2026.")))))
  (unless (and label items)
    (error "Section links need :label, what the row is, and :items"))
  `(:nav ,(attrs (list :class "tun-section-links" :id id :aria-label label
                       :data-tun-section-links t)
                 attributes)
         (:ul ,@(loop for item in items
                      collect `(:li (:a (:@ :href ,(getf item :href)) ,(getf item :label)))))))

;;; ------------------------------------------------------------------
;;; The frame of a staff page

(defun app-shell-account (user logout-action)
  "Who is signed in and the form that signs them out, at the foot of the menu."
  (when (or user logout-action)
    `(:div (:@ :class "tun-app-shell-account")
           ,@(when user
               (list `(:div (:@ :class "tun-app-shell-user")
                            (:span (:@ :class "tun-app-shell-avatar") ,(icon (:name :user)))
                            (:span (:@ :class "tun-app-shell-who")
                                   (:span (:@ :class "tun-app-shell-signed-in")
                                          ,(tr "Signed in as"))
                                   (:span (:@ :class "tun-app-shell-name") ,user)))))
           ,@(when logout-action
               (list `(:form (:@ :class "tun-app-shell-logout" :method "post"
                                 :action ,logout-action)
                             ,(button (:type "submit" :variant :outline :icon :log-out)
                                      (tr "Sign out"))))))))

(define-component app-shell ((&key title (home "/") nav nav-groups current user logout-action
                                   (width :default) (main-id "main-content") search id
                                   attributes)
                             &rest children)
  (:group "Layout and navigation")
  (:doc "The frame around every page for the staff: a link past the menu, the app's name, the
main menu (NAV, links as in nav-list, with CURRENT marked), who is signed in and «Sign out».
On a phone the menu is behind a menu button and works without JavaScript. From 64rem it is a
sidebar, not a menu at the top: six entries with an icon and a count do not fit beside the
name and the user on a narrower screen, and a sidebar has room for more modules. With :width
:narrow the content stands narrow in the middle of the page, for a page with one short form
such as signing in; with :width :wide it uses the whole width beside the menu, for a board or
a wide overview. SEARCH, the path of the application's search page, adds the search: a button
in the top bar on a phone, a row at the top of the sidebar with its Ctrl K keys, and its dialog
(spec/ui.md 6.4).")
  (:source "Basecoat sidebar (Vega); GOV.UK skip link and service navigation")
  (:css "
.tun-app-shell {
  position: relative;
  & .tun-app-shell-skip {
    position: absolute;
    top: calc(var(--spacing) * 2);
    left: calc(var(--spacing) * 2);
    z-index: calc(var(--z-sticky) + 1);
    padding: calc(var(--spacing) * 2.5) calc(var(--spacing) * 4);
    border-radius: var(--radius-md);
    background-color: var(--primary);
    color: var(--primary-foreground);
    font-size: var(--text-sm);
    font-weight: var(--font-weight-medium);
    text-decoration: none;
    box-shadow: var(--shadow-lg);
    &:not(:focus) {
      clip-path: inset(50%);
      width: 1px;
      height: 1px;
      padding: 0;
      overflow: hidden;
      white-space: nowrap;
    }
  }

  /* The loading sign (spec/ui.md 4.1): a thin bar across the top of the
     window while a person's htmx request goes unanswered, its short part
     sliding across; under reduced motion it stands still as stripes. */
  & .tun-app-shell-loading {
    position: fixed;
    inset: 0 0 auto 0;
    z-index: var(--z-toast);
    height: 3px;
    overflow: hidden;
    background-color: color-mix(in oklab, var(--primary) 20%, transparent);
    background-image: linear-gradient(var(--primary), var(--primary));
    background-repeat: no-repeat;
    background-size: 40% 100%;
    pointer-events: none;
    /* A loop keeps an even easing of its own; --ease is for a change of state. */
    animation: tun-app-shell-loading 1.2s ease-in-out infinite;
    &[hidden] { display: none; }
    @media (prefers-reduced-motion: reduce) {
      animation: none;
      background-image: repeating-linear-gradient(
        -45deg, var(--primary) 0 6px, transparent 6px 12px);
      background-size: auto;
    }
  }
  & .tun-app-shell-loading-status {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
    white-space: nowrap;
  }

  /* The top bar, the sidebar and the phone's menu stand on the chrome
     ground; a focus ring there leaves its gap in that ground. */
  & .tun-app-shell-header {
    --focus-ring: 0 0 0 2px var(--chrome), 0 0 0 4px var(--ring);
    position: sticky;
    top: 0;
    z-index: var(--z-sticky);
    border-bottom: 1px solid var(--chrome-border);
    /* The chrome itself, not a tint: an installed app's theme colour is
       this ground, so the phone's status bar and the bar are one surface. */
    background-color: var(--chrome);
  }
  & .tun-app-shell-bar {
    display: flex;
    align-items: center;
    gap: var(--spacing);
    height: calc(var(--spacing) * 14);
    padding-inline: var(--spacing) calc(var(--spacing) * 4);
  }
  & .tun-app-shell-title {
    display: inline-flex;
    align-items: center;
    gap: calc(var(--spacing) * 2.5);
    min-width: 0;
    padding: var(--spacing);
    border-radius: var(--radius-md);
    font-weight: var(--font-weight-semibold);
    text-decoration: none;
  }
  & .tun-app-shell-mark {
    display: grid;
    place-items: center;
    flex-shrink: 0;
    width: calc(var(--spacing) * 7);
    height: calc(var(--spacing) * 7);
    border-radius: var(--radius-md);
    background-color: var(--primary);
    color: var(--primary-foreground);
    font-size: var(--text-sm);
  }
  & .tun-app-shell-name-text { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  & .tun-app-shell-bar > [data-tun-search-open] { margin-inline-start: auto; }

  /* The search's row at the top of the sidebar reads as a field, its keys
     at its end; on a phone the top bar's button stands for it. */
  & .tun-app-shell-search { display: none; }
  & .tun-app-shell-search-row {
    display: flex;
    align-items: center;
    gap: calc(var(--spacing) * 2);
    height: var(--control-height);
    padding-inline: calc(var(--spacing) * 2.5) calc(var(--spacing) * 1.5);
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    background-color: var(--input-background);
    color: var(--muted-foreground);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    text-decoration: none;
    & > .tun-kbd { margin-inline-start: auto; }
    &:focus-visible { outline: none; box-shadow: var(--focus-ring); }
    &:active { background-color: var(--pressed); transition: none; }
  }
  @media (hover: hover) {
    & .tun-app-shell-search-row:hover { border-color: var(--border-strong); }
  }

  /* On a phone the menu is a popover: a panel that slides in from the left
     over a dimmed page, opened by the menu button without any script. */
  & .tun-app-shell-panel {
    position: fixed;
    inset: 0 auto 0 0;
    flex-direction: column;
    width: min(20rem, calc(100vw - calc(var(--spacing) * 12)));
    height: 100dvh;
    max-height: none;
    margin: 0;
    padding: 0;
    border: 0;
    border-right: 1px solid var(--chrome-border);
    background-color: var(--chrome);
    color: var(--foreground);
    box-shadow: var(--shadow-lg);
    overflow: hidden;
    translate: -100% 0;
    transition: translate var(--duration) var(--ease),
                display var(--duration) allow-discrete,
                overlay var(--duration) allow-discrete;
    &:popover-open {
      display: flex;
      translate: 0 0;
      @starting-style { translate: -100% 0; }
    }
    &::backdrop {
      background-color: var(--overlay);
      opacity: 0;
      transition: opacity var(--duration) var(--ease),
                  display var(--duration) allow-discrete,
                  overlay var(--duration) allow-discrete;
    }
    &:popover-open::backdrop {
      opacity: 1;
      @starting-style { opacity: 0; }
    }
  }
  & .tun-app-shell-panel-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-shrink: 0;
    height: calc(var(--spacing) * 14);
    padding-inline: calc(var(--spacing) * 4) var(--spacing);
    border-bottom: 1px solid var(--chrome-border);
    font-weight: var(--font-weight-semibold);
  }
  & .tun-app-shell-nav {
    flex: 1;
    min-height: 0;
    padding: calc(var(--spacing) * 3);
    overflow-y: auto;
    overscroll-behavior: contain;
  }
  & .tun-app-shell-account {
    display: flex;
    flex-direction: column;
    gap: calc(var(--spacing) * 3);
    flex-shrink: 0;
    padding: calc(var(--spacing) * 4);
    padding-bottom: max(calc(var(--spacing) * 4), env(safe-area-inset-bottom));
    border-top: 1px solid var(--chrome-border);
  }
  & .tun-app-shell-user {
    display: flex;
    align-items: center;
    gap: calc(var(--spacing) * 3);
    min-width: 0;
  }
  & .tun-app-shell-avatar {
    display: grid;
    place-items: center;
    flex-shrink: 0;
    width: calc(var(--spacing) * 9);
    height: calc(var(--spacing) * 9);
    border-radius: var(--radius-full);
    background-color: var(--muted);
    color: var(--muted-foreground);
  }
  & .tun-app-shell-who { display: flex; flex-direction: column; min-width: 0; }
  & .tun-app-shell-signed-in {
    font-size: var(--text-xs);
    line-height: var(--text-xs--line-height);
    color: var(--muted-foreground);
  }
  & .tun-app-shell-name {
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    font-weight: var(--font-weight-medium);
    overflow-wrap: anywhere;
  }
  & .tun-app-shell-logout { display: grid; }

  & .tun-app-shell-main {
    min-width: 0;
    &:focus { outline: none; }
    /* Below the sticky header, a jump to an id lands in view. */
    & [id] { scroll-margin-top: calc(var(--spacing) * 18); }
  }
  & .tun-app-shell-content {
    display: flex;
    flex-direction: column;
    gap: calc(var(--spacing) * 8);
    width: 100%;
    max-width: 72rem;
    margin-inline: auto;
    padding: calc(var(--spacing) * 6) calc(var(--spacing) * 4) calc(var(--spacing) * 16);
  }
  @media (min-width: 48rem) {
    & .tun-app-shell-content { padding-inline: calc(var(--spacing) * 8); }
  }
  @media (min-width: 64rem) {
    & .tun-app-shell-content {
      padding: calc(var(--spacing) * 10) calc(var(--spacing) * 10) calc(var(--spacing) * 16);
    }
  }
  /* A large screen: a little wider, with more air at the sides. */
  @media (min-width: 90rem) {
    & .tun-app-shell-content { max-width: 84rem; padding-inline: calc(var(--spacing) * 12); }
  }
  @media (min-width: 120rem) {
    & .tun-app-shell-content { padding-inline: calc(var(--spacing) * 16); }
  }
  & .tun-app-shell-content[data-width='narrow'] { max-width: 32rem; }
  /* A page that needs the room, such as a board: the whole width. */
  & .tun-app-shell-content[data-width='wide'] { max-width: none; }
  /* Content that holds an element made to fill (data-tun-fill, a board),
     directly or in stacks, is as tall as the screen under the header, and
     that element takes the height the rest leaves it, at least 20rem: its
     bottom edge shows when the page loads, above a strip of page a finger
     can scroll by.  Each stack on the way grows to pass the height on. */
  & .tun-app-shell-content:has(> [data-tun-fill], > .tun-stack > [data-tun-fill],
                               > .tun-stack > .tun-stack > [data-tun-fill]) {
    min-height: calc(100dvh - var(--spacing) * 14 - 1px);
    padding-block-end: calc(var(--spacing) * 10);
    & > .tun-stack:has(> [data-tun-fill], > .tun-stack > [data-tun-fill]),
    & > .tun-stack > .tun-stack:has(> [data-tun-fill]) { flex-grow: 1; }
    & > [data-tun-fill], & > .tun-stack > [data-tun-fill],
    & > .tun-stack > .tun-stack > [data-tun-fill] {
      flex: 1 1 0;
      min-height: 20rem;
      padding-block-end: 0;
      --tun-fill-align: stretch;
      --tun-fill-max-height: none;
    }
  }

  /* From 64rem the header is a sidebar and the menu stands in it.  A shell
     without a menu keeps its top bar. */
  @media (min-width: 64rem) {
    &:has(.tun-app-shell-panel) {
      display: grid;
      grid-template-columns: 16rem minmax(0, 1fr);
    }
    &:has(.tun-app-shell-panel) .tun-app-shell-header {
      display: flex;
      flex-direction: column;
      height: 100dvh;
      border-bottom: 0;
      border-right: 1px solid var(--chrome-border);
      background-color: var(--chrome);
    }
    & .tun-app-shell-bar { flex-shrink: 0; padding-inline: calc(var(--spacing) * 3); }
    & .tun-app-shell-bar > :is([popovertarget], [data-tun-search-open]) { display: none; }
    & .tun-app-shell-search {
      display: block;
      flex-shrink: 0;
      padding: calc(var(--spacing) * 3) calc(var(--spacing) * 3) 0;
    }
    & .tun-app-shell-panel,
    & .tun-app-shell-panel:popover-open {
      position: static;
      display: flex;
      flex: 1;
      width: auto;
      height: auto;
      min-height: 0;
      border: 0;
      background-color: transparent;
      box-shadow: none;
      translate: none;
      transition: none;
    }
    & .tun-app-shell-panel-head { display: none; }
    & .tun-app-shell-nav { padding-block: var(--spacing); }
    &:has(.tun-app-shell-panel) .tun-app-shell-main [id] {
      scroll-margin-top: calc(var(--spacing) * 4);
    }
    /* Beside the sidebar there is no header above the content. */
    &:has(.tun-app-shell-panel) .tun-app-shell-content:has(> [data-tun-fill],
        > .tun-stack > [data-tun-fill], > .tun-stack > .tun-stack > [data-tun-fill]) {
      min-height: 100dvh;
    }
  }
}
@keyframes tun-app-shell-loading {
  from { background-position: -70% 0; }
  to { background-position: 170% 0; }
}")
  (:script "
// The loading sign (spec/ui.md 4.1): a person's htmx request for a whole
// page, or for a part that a click or a submission started, shows the bar
// and says «Loading…» once if it is not answered within DELAY, and both go
// when the last such request ends, however it ends.  A page swapped in
// while another such request is still under way, as after Back, brings a
// hidden bar of its own, which is shown again.  A preload is a plain
// fetch, not an htmx request, and never shows it.
const delay = 300;
let waiting = 0;
let timer = null;
let showing = false;
const bars = () => document.querySelectorAll('[data-tun-loading]');
const show = () => {
  timer = null;
  showing = true;
  for (const bar of bars()) bar.hidden = false;
  for (const region of document.querySelectorAll('[data-tun-loading-status]'))
    region.textContent = region.dataset.tunLoadingStatus;
};
const clear = () => {
  clearTimeout(timer);
  timer = null;
  waiting = 0;
  showing = false;
  for (const bar of bars()) bar.hidden = true;
  for (const region of document.querySelectorAll('[data-tun-loading-status]'))
    region.textContent = '';
};
document.addEventListener('htmx:after:swap', () => {
  if (showing) for (const bar of bars()) bar.hidden = false;
});
const shows = (ctx) => ctx.request?.headers?.['HX-Request-Type'] === 'full'
  || ['click', 'submit'].includes(ctx.sourceEvent?.type);
document.addEventListener('htmx:before:request', (event) => {
  const ctx = event.detail.ctx;
  if (!ctx || !shows(ctx)) return;
  ctx.tunLoading = true;
  waiting += 1;
  if (waiting === 1) timer = setTimeout(show, delay);
});
document.addEventListener('htmx:finally:request', (event) => {
  if (!event.detail.ctx?.tunLoading) return;
  waiting -= 1;
  if (waiting <= 0) clear();
});
window.addEventListener('pageshow', (event) => { if (event.persisted) clear(); });

// The phone menu is a popover.  When the window grows wide enough for the
// sidebar (a tablet turned on its side) while the menu is open, close it, so
// the menu does not stay on top of the page.
if (!('hidePopover' in HTMLElement.prototype)) return;
const wide = window.matchMedia('(min-width: 64rem)');
wide.addEventListener('change', () => {
  if (!wide.matches) return;
  for (const panel of document.querySelectorAll('[data-tun-app-shell-menu]'))
    if (tunPopoverOpen(panel)) panel.hidePopover();
});")
  (:examples
   (("A whole page" :layout :stack)
    (app-shell (:title "Nordvik Rentals"
                       :nav '((:label "Customers" :href "/customers" :icon :users :count 128)
                              (:label "Orders" :href "/orders" :icon :shopping-cart :count 7)
                              (:label "Quotes" :href "/quotes" :icon :file-text :count 3)
                              (:label "Stock" :href "/stock" :icon :package)
                              (:label "Settings" :href "/settings" :icon :settings)
                              (:label "Access" :href "/access" :icon :shield-check))
                       :current "/customers/42"
                       :user "admin:jonas"
                       :logout-action "/logout")
               (page-header (:title "Ole Hansen Ltd"
                                    :meta (list (badge (:variant :success) "Active")
                                                "Customer since March 2021")
                                    :breadcrumbs '((:label "Customers" :href "/customers")
                                                   (:label "Ole Hansen Ltd"))
                                    :actions (list (button (:variant :outline :icon :pencil)
                                                           "Edit")
                                                   (button (:icon :plus) "New order"))))
               (section (:title "Contact")
                        (summary-list (:rows '(("Contact" "Kari Nordmann, managing director")
                                               ("Email" "kari@example.com")
                                               ("Phone" "912 34 567")
                                               ("Invoice address"
                                                ((:p "Storgata 12") (:p "0155 Oslo")))))))
               (section (:title "Latest orders"
                                :actions (list (button (:variant :outline :size :sm
                                                                 :href "/orders?customer=42")
                                                       "Show all")))
                        (stack (:gap :sm)
                               (cluster (:justify :between)
                                        '(:span "Order 1042, 3 October")
                                        '(:strong "€12,450"))
                               (cluster (:justify :between)
                                        '(:span "Order 1031, 14 September")
                                        '(:strong "€4,800"))))))
   (("Without a user and a menu, narrow" :layout :stack)
    (app-shell (:title "Nordvik Rentals" :width :narrow)
               (page-header (:title "Sign in"))
               (card ()
                     (form-actions ()
                       (button (:type "submit" :icon :log-in) "Sign in"))))))
  (check-type title string)
  (check-type width (member :default :narrow :wide))
  (let* ((menu-p (or nav nav-groups user logout-action))
         (menu-id (element-id "tun-app-shell-menu"))
         (open-button (button (:variant :ghost :size :icon :label (tr "Menu")
                                        :attributes (list :popovertarget menu-id))
                              (icon (:name :menu))))
         (close-button (button (:variant :ghost :size :icon :label (tr "Close the menu")
                                         :attributes (list :popovertarget menu-id
                                                           :popovertargetaction "hide"))
                               (icon (:name :x))))
         ;; The search's links lead to its page without scripts; a click
         ;; opens its dialog instead where they run, so htmx neither
         ;; follows nor preloads them.
         (search-link (list :href search :data-tun-search-open t :hx-boost "false"
                            :data-tun-preload "off")))
    `(:div ,(attrs (list :class "tun-app-shell" :id id) attributes)
           (:a (:@ :class "tun-app-shell-skip" :href ,(format nil "#~a" main-id))
               ,(tr "Skip to the main content"))
           (:div (:@ :class "tun-app-shell-loading" :data-tun-loading t :hidden t
                     :aria-hidden "true"))
           (:div (:@ :class "tun-app-shell-loading-status" :role "status"
                     :data-tun-loading-status ,(tr "Loading…")))
           (:header (:@ :class "tun-app-shell-header")
                    (:div (:@ :class "tun-app-shell-bar")
                          ,@(when menu-p (list open-button))
                          (:a (:@ :class "tun-app-shell-title" :href ,home)
                              (:span (:@ :class "tun-app-shell-mark" :aria-hidden "true")
                                     ,(subseq title 0 (min 1 (length title))))
                              (:span (:@ :class "tun-app-shell-name-text") ,title))
                          ,@(when search
                              (list (button (:variant :ghost :size :icon :label (tr "Search")
                                             :href search
                                             :attributes (rest (rest search-link)))
                                            (icon (:name :search))))))
                    ,@(when menu-p
                        (list
                         `(:div (:@ :class "tun-app-shell-panel" :id ,menu-id :popover "auto"
                                    :data-tun-app-shell-menu t)
                                (:div (:@ :class "tun-app-shell-panel-head")
                                      (:span ,(tr "Menu"))
                                      ,close-button)
                                ,@(when search
                                    (list `(:div (:@ :class "tun-app-shell-search")
                                                 (:a ,(attrs (list :class "tun-app-shell-search-row"
                                                                   :aria-keyshortcuts
                                                                   (aria-keyshortcuts '("Ctrl" "K")))
                                                             search-link)
                                                     ,(icon (:name :search))
                                                     (:span ,(tr "Search"))
                                                     ,(shortcut-caps '("Ctrl" "K"))))))
                                ,@(when (or nav nav-groups)
                                    (list `(:div (:@ :class "tun-app-shell-nav")
                                                 ,(nav-list (:label (tr "Main menu") :items nav
                                                                    :groups nav-groups
                                                                    :current current)))))
                                ,@(when (or user logout-action)
                                    (list (app-shell-account user logout-action)))))))
           (:main (:@ :class "tun-app-shell-main" :id ,main-id :tabindex "-1")
                  (:div (:@ :class "tun-app-shell-content"
                            :data-width ,(unless (eq width :default) (option-string width)))
                        ,@children))
           ;; The page's one dialog that asks before an action (spec/ui.md 6).
           ,(confirm-dialog ())
           ;; The search's dialog comes last, after every dialog of the page,
           ;; so a page's own dialog on Ctrl K opens on it instead (6.4).
           ,@(when search (list (search-dialog (:action search)))))))
