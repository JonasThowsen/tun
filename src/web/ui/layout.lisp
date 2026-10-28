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
    border-radius: var(--radius-md);
    color: var(--foreground);
    text-decoration: none;
    transition: background-color var(--duration-fast) var(--ease);
    outline-offset: 0;
    @media (hover: hover) {
      &:hover { background-color: var(--accent); color: var(--accent-foreground); }
    }
    &:active { background-color: var(--accent); }
    &[aria-current] {
      background-color: var(--accent);
      color: var(--accent-foreground);
      font-weight: var(--font-weight-medium);
    }
    & .tun-icon { color: var(--muted-foreground); }
    &[aria-current] .tun-icon { color: var(--accent-foreground); }
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
;;; The top of a page and its sections

(define-component page-header ((&key title description breadcrumbs actions id attributes)
                               &rest children)
  (:group "Layout and navigation")
  (:doc "The top of a page: breadcrumbs (BREADCRUMBS, or as children), the title as the only
h1, a short description and the page's actions (ACTIONS, a list of buttons). The actions
stand to the right of the title when they fit beside it, on a phone too, and under it
otherwise.")
  (:source "shadcn/ui dashboard page heading, in Basecoat's tokens")
  (:css "
.tun-page-header {
  display: flex;
  flex-direction: column;
  gap: calc(var(--spacing) * 3);
  & .tun-page-header-row {
    display: flex;
    flex-wrap: wrap;
    align-items: flex-start;
    justify-content: space-between;
    gap: calc(var(--spacing) * 4);
    @media (max-width: 40rem) { align-items: center; }
  }
  /* The text takes the row and the actions wrap below it when both do
     not fit.  On a phone the text is as wide as it needs, so a short
     title and its actions share one row. */
  & .tun-page-header-text {
    display: flex;
    flex: 1 1 24rem;
    flex-direction: column;
    gap: calc(var(--spacing) * 1.5);
    min-width: 0;
    @media (max-width: 40rem) { flex-basis: auto; }
  }
  & .tun-page-header-title {
    font-size: var(--text-2xl);
    line-height: var(--text-2xl--line-height);
    font-weight: var(--font-weight-semibold);
    letter-spacing: -0.025em;
    overflow-wrap: anywhere;
  }
  & .tun-page-header-description { color: var(--muted-foreground); max-width: 65ch; }
  & .tun-page-header-actions {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: calc(var(--spacing) * 2);
  }
  @media (min-width: 48rem) {
    & .tun-page-header-title {
      font-size: var(--text-3xl);
      line-height: var(--text-3xl--line-height);
    }
  }
}")
  (:examples
   (("With breadcrumbs, a description and actions" :layout :stack)
    (page-header (:title "Ole Hansen Ltd"
                         :description "A customer since March 2021. Invoiced monthly, 14 days."
                         :breadcrumbs '((:label "Customers" :href "/customers")
                                        (:label "Ole Hansen Ltd"))
                         :actions (list (button (:variant :outline :icon :pencil) "Edit")
                                        (button (:icon :plus) "New order")))))
   (("Only a title" :layout :stack)
    (page-header (:title "Customers")))
   (("A long title" :layout :stack)
    (page-header (:title "Quote 2024-031: A summer party with a tent for Fjord Catering"
                         :breadcrumbs '((:label "Quotes" :href "/quotes")
                                        (:label "Quote 2024-031"))
                         :actions (list (button (:variant :outline) "Preview")
                                        (button (:icon :send) "Send to the customer"))))))
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
                  ,@(when actions
                      (list `(:div (:@ :class "tun-page-header-actions") ,@actions))))))

(define-component section ((&key title description actions (level 2) id attributes)
                           &rest children)
  (:group "Layout and navigation")
  (:doc "A part of a page with a heading of its own (h2, or h3 with LEVEL 3), a short
description and actions that concern only this part. In an app-shell or a stack the sections
get room between them.")
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
   (("With a description and an action" :layout :stack)
    (section (:title "Contacts"
                     :description "The first gets order confirmations and invoices by email."
                     :actions (list (button (:variant :outline :size :sm :icon :user-plus)
                                            "Add")))
             '(:p "Kari Nordmann, managing director – kari@example.com – 912 34 567")
             '(:p "Per Olsen, purchasing – per@example.com")))
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
                         ,@(when description
                             (list `(:p (:@ :class "tun-section-description") ,description))))
                   ,@(when actions
                       (list `(:div (:@ :class "tun-section-actions") ,@actions))))
             ,@children))

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
                                   (width :default) (main-id "main-content") id attributes)
                             &rest children)
  (:group "Layout and navigation")
  (:doc "The frame around every page for the staff: a link past the menu, the app's name, the
main menu (NAV, links as in nav-list, with CURRENT marked), who is signed in and «Sign out».
On a phone the menu is behind a menu button and works without JavaScript. From 64rem it is a
sidebar, not a menu at the top: six entries with an icon and a count do not fit beside the
name and the user on a narrower screen, and a sidebar has room for more modules. With :width
:narrow the content stands narrow in the middle of the page, for a page with one short form
such as signing in; with :width :wide it uses the whole width beside the menu, for a board or
a wide overview.")
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

  & .tun-app-shell-header {
    position: sticky;
    top: 0;
    z-index: var(--z-sticky);
    border-bottom: 1px solid var(--border);
    background-color: color-mix(in oklab, var(--background) 90%, transparent);
    backdrop-filter: blur(8px);
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
    border-right: 1px solid var(--border);
    background-color: var(--popover);
    color: var(--popover-foreground);
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
      /* A scrim is black in both themes, as Basecoat's. */
      background-color: rgb(0 0 0 / 0.5);
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
    border-bottom: 1px solid var(--border);
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
    border-top: 1px solid var(--border);
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
      border-right: 1px solid var(--border);
      background-color: color-mix(in oklab, var(--muted) 50%, var(--background));
      backdrop-filter: none;
    }
    & .tun-app-shell-bar { flex-shrink: 0; padding-inline: calc(var(--spacing) * 3); }
    & .tun-app-shell-bar > [popovertarget] { display: none; }
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
}")
  (:script "
// The phone menu is a popover.  When the window grows wide enough for the
// sidebar (a tablet turned on its side) while the menu is open, close it, so
// the menu does not stay on top of the page.
if (!('hidePopover' in HTMLElement.prototype)) return;
const wide = window.matchMedia('(min-width: 64rem)');
wide.addEventListener('change', () => {
  if (!wide.matches) return;
  for (const panel of document.querySelectorAll('[data-tun-app-shell-menu]:popover-open'))
    panel.hidePopover();
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
                                    :description "A customer since March 2021. Invoiced monthly."
                                    :breadcrumbs '((:label "Customers" :href "/customers")
                                                   (:label "Ole Hansen Ltd"))
                                    :actions (list (button (:variant :outline :icon :pencil)
                                                           "Edit")
                                                   (button (:icon :plus) "New order"))))
               (section (:title "Contact")
                        (grid (:min :sm)
                              (stack (:gap :xs)
                                     '(:strong "Kari Nordmann")
                                     '(:span "Managing director")
                                     '(:span "kari@example.com · 912 34 567"))
                              (stack (:gap :xs)
                                     '(:strong "Invoice address")
                                     '(:span "Storgata 12")
                                     '(:span "0155 Oslo"))))
               (section (:title "Latest orders"
                                :description "Orders from the last 90 days."
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
               (page-header (:title "Sign in" :description "Sign in to Nordvik Rentals."))
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
                               (icon (:name :x)))))
    `(:div ,(attrs (list :class "tun-app-shell" :id id) attributes)
           (:a (:@ :class "tun-app-shell-skip" :href ,(format nil "#~a" main-id))
               ,(tr "Skip to the main content"))
           (:header (:@ :class "tun-app-shell-header")
                    (:div (:@ :class "tun-app-shell-bar")
                          ,@(when menu-p (list open-button))
                          (:a (:@ :class "tun-app-shell-title" :href ,home)
                              (:span (:@ :class "tun-app-shell-mark" :aria-hidden "true")
                                     ,(subseq title 0 (min 1 (length title))))
                              (:span (:@ :class "tun-app-shell-name-text") ,title)))
                    ,@(when menu-p
                        (list
                         `(:div (:@ :class "tun-app-shell-panel" :id ,menu-id :popover "auto"
                                    :data-tun-app-shell-menu t)
                                (:div (:@ :class "tun-app-shell-panel-head")
                                      (:span ,(tr "Menu"))
                                      ,close-button)
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
                        ,@children)))))
