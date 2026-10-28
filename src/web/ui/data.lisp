;;;; web/ui/data.lisp -- the data group (spec/ui.md 6): how a small
;;;; business's records are shown.  Lists of records are tables, one record
;;;; is a summary list, key figures are stats, and the history of a record
;;;; is a timeline.

(in-package #:tun.ui)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Table

(defun table-column (column)
  "COLUMN of a table, a header string or a list (HEADER &key ALIGN WIDTH WRAP
SORT SORTED), as a plist with every option.  SORT is the key the page sorts
the column by; SORTED is :ASC or :DESC on the column the rows are sorted by."
  (destructuring-bind (header &key (align :start) width wrap sort sorted)
      (if (listp column) column (list column))
    (check-type header string)
    (check-type align (member :start :center :end))
    (check-type width (member nil :min :sm :md :lg))
    (check-type sort (or null string))
    (check-type sorted (member nil :asc :desc))
    (list :header header :align align :width width :wrap wrap :sort sort :sorted sorted)))

(defun sort-link (sort-href key direction)
  "Where the header of a column sorted by KEY leads, to sort it in DIRECTION
(:ASC or :DESC): SORT-HREF is a function of the key and \"asc\" or \"desc\",
or a format string taking them."
  (let ((direction (option-string direction)))
    (etypecase sort-href
      (null (error "A table with a sortable column needs :sort-href"))
      (string (format nil sort-href key direction))
      ((or function symbol) (funcall sort-href key direction)))))

(defun table-header (column sort-href)
  "The header cell of COLUMN.  A sortable column's header is a link that
sorts by it, ascending, or descending when it is sorted ascending already,
with an arrow; aria-sort says how the rows are sorted."
  (destructuring-bind (&key header sort sorted &allow-other-keys) column
    `(:th ,(attrs (list :scope "col"
                        :aria-sort (case sorted (:asc "ascending") (:desc "descending")))
                  (table-cell-attributes column))
          ,(if sort
               `(:a (:@ :class "tun-table-sort"
                        :href ,(sort-link sort-href sort (if (eq sorted :asc) :desc :asc)))
                    ,header
                    ,(icon* (list :name (case sorted
                                          (:asc :arrow-up)
                                          (:desc :arrow-down)
                                          (t :arrow-up-down)))))
               header))))

(defun table-cell-attributes (column)
  "The attributes a header or data cell of COLUMN carries for its alignment,
width and wrapping."
  (destructuring-bind (&key align width wrap &allow-other-keys) column
    (list :data-align (unless (eq align :start) (option-string align))
          :data-width (option-string width)
          :data-wrap (when wrap "true"))))

(defun table-cell (column content &optional href)
  "A data cell of COLUMN holding CONTENT.  The cell carries its column's header
as a label, which is shown when rows are cards on a narrow screen.  With HREF
the content is the link that the whole row leads to."
  `(:td ,(attrs (table-cell-attributes column))
        (:span (:@ :class "tun-table-label") ,(getf column :header))
        (:span (:@ :class "tun-table-value")
               ,(if href
                    `(:a (:@ :class "tun-table-row-link" :href ,href)
                         ,content
                         ,(icon (:name :chevron-right)))
                    content))))

(defun table-row (columns cells &optional href)
  (unless (= (length cells) (length columns))
    (error "A table row has ~d cells but the table has ~d columns: ~s"
           (length cells) (length columns) cells))
  `(:tr ,(attrs (list :data-link (when href "true")))
        ,@(loop for column in columns
                for cell in cells
                for first = t then nil
                collect (table-cell column cell (when first href)))))

(defun table-row-hrefs (row-href rows)
  "The link of each of ROWS: ROW-HREF is NIL, a list parallel to ROWS, or a
function from a row (its cells) to its URL or NIL."
  (etypecase row-href
    (list (unless (or (null row-href) (= (length row-href) (length rows)))
            (error "The table has ~d rows but ~d links" (length rows) (length row-href)))
          (or row-href (make-list (length rows))))
    ((or function symbol) (mapcar row-href rows))))

(define-component table ((&key columns rows row-href sort-href footer caption caption-hidden
                               (empty (tr "No entries.")) id attributes))
  (:group "Data")
  (:doc "A list of records, such as orders, customers or invoices. The first column is what
identifies the record: on a narrow screen it becomes the title of a card, and the other
values stand with their column's name. With ROW-HREF the whole row is a link to the record;
amounts and numbers are right-aligned with :align :end. A column with :sort KEY can be
sorted: its header becomes a link to SORT-HREF (a function of the key and \"asc\" or
\"desc\", or a format string), and :sorted :asc or :desc shows how the rows are sorted. The
page sorts; the table only shows the headers.")
  (:source "Basecoat table (Vega); cards on a phone after GOV.UK and Aksel")
  (:css "
.tun-table {
  container: tun-table / inline-size;
  width: 100%;
  overflow-x: auto;
  & table {
    width: 100%;
    caption-side: top;
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    font-variant-numeric: tabular-nums;
  }
  /* The caption is the table's title, above it as GOV.UK places it. */
  & caption {
    margin-bottom: calc(var(--spacing) * 3);
    color: var(--muted-foreground);
    font-weight: var(--font-weight-medium);
    text-align: start;
  }
  & caption[data-hidden] {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
    white-space: nowrap;
  }
  & thead tr, & tbody tr { border-bottom: 1px solid var(--border); }
  & tbody tr {
    transition: background-color var(--duration-fast) var(--ease);
    &:last-child { border-bottom: 0; }
  }
  & tfoot {
    border-top: 1px solid var(--border);
    background-color: color-mix(in oklab, var(--muted) 50%, transparent);
    font-weight: var(--font-weight-medium);
  }
  & th {
    height: calc(var(--spacing) * 10);
    padding-inline: calc(var(--spacing) * 2);
    color: var(--foreground);
    font-weight: var(--font-weight-medium);
    text-align: start;
    vertical-align: middle;
    white-space: nowrap;
  }
  & td {
    padding: calc(var(--spacing) * 2);
    vertical-align: middle;
    white-space: nowrap;
  }
  & :is(th, td)[data-align='end'] { text-align: end; }
  & .tun-table-sort {
    display: inline-flex;
    align-items: center;
    gap: var(--spacing);
    border-radius: var(--radius-sm);
    text-decoration: none;
    & .tun-icon {
      width: calc(var(--spacing) * 3.5);
      height: calc(var(--spacing) * 3.5);
      color: var(--muted-foreground);
    }
    @media (hover: hover) {
      &:hover { text-decoration-line: underline; text-underline-offset: 4px; }
    }
  }
  & th[aria-sort] .tun-table-sort .tun-icon { color: var(--foreground); }
  & :is(th, td)[data-align='center'] { text-align: center; }
  /* :min shrinks a column to its content, for dates, numbers and actions. */
  & th[data-width='min'] { width: 1%; }
  & th[data-width='sm'] { width: 6rem; }
  & th[data-width='md'] { width: 10rem; }
  & th[data-width='lg'] { width: 16rem; }
  & td[data-wrap] { min-width: 12rem; white-space: normal; }
  & .tun-table-label, & .tun-table-row-link .tun-icon { display: none; }
  & .tun-table-empty td {
    padding-block: calc(var(--spacing) * 8);
    color: var(--muted-foreground);
    text-align: center;
    white-space: normal;
  }
  @media (hover: hover) {
    & tbody tr:not(.tun-table-empty):hover {
      background-color: color-mix(in oklab, var(--muted) 50%, transparent);
    }
  }

  /* A row with a link: the first cell's link covers the whole row, so the
     row is one target and the link's text is its name. */
  & tr[data-link] {
    position: relative;
    & :is(a, button, input, select, label):not(.tun-table-row-link) {
      position: relative;
      z-index: 1;
    }
    @media (hover: hover) {
      &:hover .tun-table-row-link { text-decoration-line: underline; }
    }
  }
  & .tun-table-row-link {
    font-weight: var(--font-weight-medium);
    text-underline-offset: 4px;
    outline: none;
    &::after { content: ''; position: absolute; inset: 0; border-radius: inherit; }
    &:focus-visible::after { box-shadow: inset 0 0 0 2px var(--ring); }
  }

  /* Narrow, as on a phone: each row is a card titled by its first cell, the
     record's identity, and each other cell is a line with its column's
     name. */
  @container tun-table (width < 36rem) {
    & table, & tbody, & tfoot, & tr, & td { display: block; }
    & thead { display: none; }
    /* The sortable headers stay, as a row of links above the cards. */
    & thead:has(.tun-table-sort) { display: block; margin-bottom: calc(var(--spacing) * 3); }
    & thead:has(.tun-table-sort) tr {
      display: flex;
      flex-wrap: wrap;
      gap: calc(var(--spacing) * 2) calc(var(--spacing) * 4);
      border: 0;
    }
    & thead th { height: auto; padding: 0; }
    & thead th:not(:has(.tun-table-sort)) { display: none; }
    & caption { display: block; }
    & tbody { display: flex; flex-direction: column; gap: calc(var(--spacing) * 3); }
    & tfoot { margin-top: calc(var(--spacing) * 3); border: 0; background: none; }
    & tbody tr, & tfoot tr, & tbody tr:last-child {
      padding: calc(var(--spacing) * 2) calc(var(--spacing) * 4);
      border: 1px solid var(--border);
      border-radius: var(--radius-lg);
      background-color: var(--card);
      box-shadow: var(--shadow-xs);
    }
    & tfoot tr { background-color: var(--muted); box-shadow: none; }
    & td {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: calc(var(--spacing) * 4);
      padding: calc(var(--spacing) * 1.5) 0;
      white-space: normal;
      text-align: end;
    }
    & td[data-wrap] { min-width: 0; }
    & td:has(> .tun-table-value:empty) { display: none; }
    & .tun-table-label {
      display: block;
      flex-shrink: 0;
      color: var(--muted-foreground);
      text-align: start;
    }
    & .tun-table-value { min-width: 0; overflow-wrap: anywhere; }
    & td[data-align='end'] .tun-table-value { white-space: nowrap; }
    /* The title: its label is left for a screen reader only. */
    & td:first-child {
      justify-content: flex-start;
      font-weight: var(--font-weight-semibold);
      text-align: start;
      & .tun-table-label {
        position: absolute;
        width: 1px;
        height: 1px;
        overflow: hidden;
        clip-path: inset(50%);
        white-space: nowrap;
      }
    }
    & tbody tr[data-link] td:first-child { padding-inline-end: calc(var(--spacing) * 6); }
    & .tun-table-row-link { font-weight: inherit; }
    /* The chevron sits at the end of the title's line: the card's top
       padding, the cell's, and half the difference between the line and
       the icon. */
    & .tun-table-row-link .tun-icon {
      display: block;
      position: absolute;
      inset-inline-end: calc(var(--spacing) * 3);
      top: calc(var(--spacing) * 3.5 + (var(--text-sm) * var(--text-sm--line-height) - 1rem) / 2);
      color: var(--muted-foreground);
    }
    & .tun-table-row-link::after { border-radius: var(--radius-lg); }
    & .tun-table-empty td {
      display: block;
      padding-block: calc(var(--spacing) * 6);
      text-align: center;
    }
    & tbody tr.tun-table-empty { border-style: dashed; box-shadow: none; }
  }
  /* An empty state brings its own space. */
  & .tun-table-empty td:has(> .tun-empty-state) { padding: 0; }
}")
  (:examples
   (("A list of orders" :layout :stack)
    (table (:caption "Orders in the last week"
                     :columns '(("Order" :width :min) "Customer" ("Date" :width :min) "Status"
                                ("Amount" :align :end))
                     :rows '(("10482" "Fjord Coffee Ltd" "12 Oct 2026" "New" "€4,380.00")
                             ("10481" "Hansen Building and Construction Ltd" "11 Oct 2026"
                              "In progress" "€128,950.00")
                             ("10480" "Kari Nordmann" "10 Oct 2026" "Sent" "€649.00")
                             ("10479" "Tromsø Bicycle Workshop" "9 Oct 2026" "Invoiced"
                              "€12,400.00")
                             ("10478" "The Corner Bakery" "8 Oct 2026" "Cancelled" "€0.00"))
                     :row-href (lambda (row) (format nil "/orders/~a" (first row))))))
   (("Invoice lines with a total and a hidden caption" :layout :stack)
    (table (:caption "Lines on invoice 2026-0193" :caption-hidden t
                     :columns '(("Description" :wrap t) ("Quantity" :align :end :width :min)
                                ("Price" :align :end :width :min) ("Total" :align :end :width :min))
                     :rows '(("Fitting kitchen cabinets, including adjusting doors and drawers"
                              "6 h" "€850.00" "€5,100.00")
                             ("Oak worktop, 240 cm" "1" "€4,990.00" "€4,990.00")
                             ("Driving" "38 km" "€5.00" "€190.00"))
                     :footer '("Total excluding VAT" nil nil "€10,280.00"))))
   (("Sortable columns" :layout :stack)
    (table (:caption "Items"
                     :columns '(("Item" :sort "title") ("Customer" :sort "customer")
                                ("Created" :sort "created" :sorted :desc :width :min) "Status")
                     :rows '(("The export to accounting fails" "Fjord Coffee Ltd" "21 Oct 2026"
                              "New")
                             ("Show stock on the order" "Hansen Building Ltd" "20 Oct 2026"
                              "Planned"))
                     :sort-href "/items?sort=~a&direction=~a")))
   (("Without rows" :layout :stack)
    (table (:caption "Invoices falling due"
                     :columns '("Invoice" "Customer" "Due" ("Amount" :align :end))
                     :rows '()
                     :empty "No invoices fall due in the next 14 days."))))
  (let ((columns (mapcar #'table-column columns))
        (hrefs (table-row-hrefs row-href rows)))
    `(:div ,(attrs (list :class "tun-table" :id id) attributes)
           (:table
            ,@(when caption
                `((:caption ,(attrs (list :data-hidden (when caption-hidden "true")))
                            ,caption)))
            (:thead
             (:tr ,@(loop for column in columns
                          collect (table-header column sort-href))))
            (:tbody
             ,@(if rows
                   (loop for row in rows
                         for href in hrefs
                         collect (table-row columns row href))
                   `((:tr (:@ :class "tun-table-empty")
                          (:td (:@ :colspan ,(length columns)) ,empty)))))
            ,@(when footer
                `((:tfoot ,(table-row columns footer))))))))

;;; ------------------------------------------------------------------
;;; Summary list

(defun summary-list-row (row default-action)
  "A row of a summary list: ROW is (KEY VALUE &key HREF ACTION)."
  (destructuring-bind (key value &key href (action default-action)) row
    `(:div (:@ :class "tun-summary-list-row")
           (:dt (:@ :class "tun-summary-list-key") ,key)
           (:dd (:@ :class "tun-summary-list-value") ,value)
           ,@(when href
               ;; The key follows the action for a screen reader, which
               ;; hears every «Change» on its own when it lists the links.
               `((:dd (:@ :class "tun-summary-list-action")
                      (:a (:@ :href ,href)
                          ,action
                          (:span (:@ :class "tun-summary-list-hidden") " " ,key))))))))

(define-component summary-list ((&key rows (action (tr "Change")) id attributes))
  (:group "Data")
  (:doc "The details of one record, such as a customer or an order: a name and a value per
row, and often a link to change the value. On a phone the name stands above the value.")
  (:source "GOV.UK summary list, Basecoat look")
  (:css "
.tun-summary-list {
  container: tun-summary-list / inline-size;
  width: 100%;
  font-size: var(--text-sm);
  line-height: var(--text-sm--line-height);
  & .tun-summary-list-row {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    grid-template-areas: 'key action' 'value value';
    column-gap: calc(var(--spacing) * 4);
    row-gap: var(--spacing);
    padding-block: calc(var(--spacing) * 3);
    border-bottom: 1px solid var(--border);
    &:first-child { padding-top: 0; }
    &:last-child { padding-bottom: 0; border-bottom: 0; }
  }
  & .tun-summary-list-key {
    grid-area: key;
    color: var(--muted-foreground);
    font-weight: var(--font-weight-medium);
  }
  & .tun-summary-list-value {
    grid-area: value;
    overflow-wrap: anywhere;
    & > p + p { margin-top: var(--spacing); }
  }
  & .tun-summary-list-action {
    grid-area: action;
    text-align: end;
    & a {
      font-weight: var(--font-weight-medium);
      text-decoration-line: underline;
      text-decoration-color: color-mix(in oklab, currentColor 40%, transparent);
      text-underline-offset: 4px;
      border-radius: var(--radius-sm);
      @media (hover: hover) {
        &:hover { text-decoration-color: currentColor; }
      }
    }
  }
  & .tun-summary-list-hidden {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
    white-space: nowrap;
  }
  @container tun-summary-list (width >= 32rem) {
    & .tun-summary-list-row {
      grid-template-columns: minmax(0, 1fr) minmax(0, 2fr) minmax(4rem, auto);
      grid-template-areas: 'key value action';
    }
  }
}")
  (:examples
   (("A customer" :layout :stack)
    (summary-list
     (:rows '(("Name" "Hansen Building and Construction Ltd" :href "/customers/412/edit#name")
              ("Organisation number" "912 345 678")
              ("Contact" "Ole Hansen" :href "/customers/412/edit#contact")
              ("Email" "ole.hansen@example.com" :href "/customers/412/edit#email")
              ("Phone" "+47 912 34 567" :href "/customers/412/edit#phone")
              ("Invoice address" ((:p "Industriveien 14") (:p "7080 Heimdal"))
               :href "/customers/412/edit#address")))))
   (("Without links" :layout :stack)
    (summary-list
     (:rows '(("Order" "10481")
              ("Ordered" "11 October 2026 at 14:32")
              ("Delivery" "Collected in the shop, Storgata 3, Tromsø")
              ("Payment" "Invoice, 14 days"))))))
  `(:dl ,(attrs (list :class "tun-summary-list" :id id) attributes)
        ,@(mapcar (lambda (row) (summary-list-row row action)) rows)))

;;; ------------------------------------------------------------------
;;; Card

(define-component card ((&key title description action footer href (heading-level 3)
                              (size :default) id attributes)
                        &rest children)
  (:group "Data")
  (:doc "A frame around content that belongs together, with a title, a description, content
and a footer. With HREF the whole card is a link (the title is the link's text); ACTION is a
button or a link in the top corner.")
  (:source "Basecoat card (Vega)")
  (:css "
.tun-card {
  display: flex;
  flex-direction: column;
  gap: calc(var(--spacing) * 6);
  padding-block: calc(var(--spacing) * 6);
  overflow: hidden;
  border-radius: var(--radius-xl);
  background-color: var(--card);
  color: var(--card-foreground);
  font-size: var(--text-sm);
  line-height: var(--text-sm--line-height);
  box-shadow: 0 0 0 1px color-mix(in oklab, var(--foreground) 10%, transparent),
              var(--shadow-xs);
  & .tun-card-header {
    display: grid;
    grid-auto-rows: min-content;
    align-items: start;
    gap: var(--spacing);
    padding-inline: calc(var(--spacing) * 6);
    &:has(> .tun-card-action) { grid-template-columns: minmax(0, 1fr) auto; }
  }
  & .tun-card-title {
    font-size: var(--text-base);
    line-height: var(--text-base--line-height);
    font-weight: var(--font-weight-medium);
    letter-spacing: normal;
  }
  & .tun-card-description { color: var(--muted-foreground); }
  & .tun-card-action {
    grid-column: 2;
    grid-row: 1 / span 2;
    align-self: start;
    justify-self: end;
  }
  /* The card hides what overflows it, so a long word (a link in a message)
     breaks rather than being cut off on a phone. */
  & .tun-card-content { padding-inline: calc(var(--spacing) * 6); overflow-wrap: anywhere; }
  & .tun-card-footer {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: calc(var(--spacing) * 2);
    padding-inline: calc(var(--spacing) * 6);
  }

  &[data-size='sm'] {
    gap: calc(var(--spacing) * 4);
    padding-block: calc(var(--spacing) * 4);
    & :is(.tun-card-header, .tun-card-content, .tun-card-footer) {
      padding-inline: calc(var(--spacing) * 4);
    }
    & .tun-card-title {
      font-size: var(--text-sm);
      line-height: var(--text-sm--line-height);
    }
  }

  /* A card that is a link: the title's link covers the card. */
  &[data-variant='link'] {
    position: relative;
    transition-property: background-color, box-shadow;
    transition-duration: var(--duration-fast);
    transition-timing-function: var(--ease);
    & :is(a, button, input, select, label):not(.tun-card-link) {
      position: relative;
      z-index: 1;
    }
    @media (hover: hover) {
      &:hover {
        background-color: light-dark(color-mix(in oklab, var(--muted) 50%, var(--card)),
                                     color-mix(in oklab, var(--muted) 60%, var(--card)));
        box-shadow: 0 0 0 1px color-mix(in oklab, var(--foreground) 20%, transparent),
                    var(--shadow-sm);
      }
    }
    &:has(.tun-card-link:focus-visible) { outline: 2px solid var(--ring); outline-offset: 2px; }
  }
  & .tun-card-link {
    outline: none;
    &::after { content: ''; position: absolute; inset: 0; }
  }
}")
  (:examples
   (("With a title, an action and a footer" :layout :stack)
    (card (:title "Hansen Building and Construction Ltd"
                  :description "A customer since March 2021"
                  :action (button (:variant :outline :size :sm :href "/customers/412/edit"
                                            :icon :pencil)
                                  "Edit")
                  :footer (list (button (:href "/orders/new?customer=412" :icon :plus)
                                        "New order")
                                (button (:variant :ghost :href "/customers/412/orders")
                                        "All orders")))
          (summary-list (:rows '(("Contact" "Ole Hansen")
                                 ("Phone" "+47 912 34 567")
                                 ("Outstanding" "€18,400.00"))))))
   ("Cards that are links"
    (card (:title "Jobs in week 42" :href "/jobs?week=42" :size :sm
                  :description "12 jobs, 3 with no one responsible")
          '(:p "Next: fitting at Kari Nordmann's, Tuesday at 08:00."))
    (card (:title "Invoices falling due" :href "/invoices?status=due" :size :sm
                  :description "4 invoices, €31,250.00")
          '(:p "The oldest fell due on 3 October.")))
   ("Content only"
    (card ()
          '(:p "A card without a title is only a frame around its content, for example a note
about the customer: “Call before delivery, the gate is locked after 4 pm.”"))))
  (when (and href (null title))
    (error "A card that is a link needs :title, which is the link's text"))
  `(:div ,(attrs (list :class "tun-card" :id id
                       :data-size (unless (eq size :default) (option-string size))
                       :data-variant (when href "link"))
                 attributes)
         ,@(when (or title description action)
             `((:header (:@ :class "tun-card-header")
                        ,@(when title
                            `((,(heading-tag heading-level) (:@ :class "tun-card-title")
                                ,(if href
                                     `(:a (:@ :class "tun-card-link" :href ,href) ,title)
                                     title))))
                        ,@(when description
                            `((:p (:@ :class "tun-card-description") ,description)))
                        ,@(when action
                            `((:div (:@ :class "tun-card-action") ,action))))))
         ,@(when children
             `((:div (:@ :class "tun-card-content") ,@children)))
         ,@(when footer
             `((:footer (:@ :class "tun-card-footer") ,footer)))))

;;; ------------------------------------------------------------------
;;; Stat

(defun change-direction (change)
  "Whether the change CHANGE, a string such as \"+12%\" or \"−3%\", is :UP,
:DOWN or neither (NIL), by its sign."
  (let ((first (find-if-not (lambda (char) (char= char #\Space)) change)))
    (case first
      (#\+ :up)
      ((#\- #\MINUS_SIGN) :down))))

(define-component stat ((&key label value change change-tone note icon id attributes))
  (:group "Data")
  (:doc "A key figure on an overview, such as turnover or the number of open orders, with
its change and a short note. The change is green when it goes up and red when it goes down;
set CHANGE-TONE when up is bad, as for amounts outstanding.")
  (:source "shadcn/ui dashboard cards, Basecoat card (Vega)")
  (:css "
.tun-stat {
  display: flex;
  flex: 1 1 11rem;
  flex-direction: column;
  align-self: stretch;
  gap: var(--spacing);
  min-width: 0;
  padding: calc(var(--spacing) * 5);
  border-radius: var(--radius-xl);
  background-color: var(--card);
  color: var(--card-foreground);
  box-shadow: 0 0 0 1px color-mix(in oklab, var(--foreground) 10%, transparent),
              var(--shadow-xs);
  & .tun-stat-label {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: calc(var(--spacing) * 2);
    color: var(--muted-foreground);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    font-weight: var(--font-weight-medium);
  }
  & .tun-stat-value {
    font-size: var(--text-2xl);
    line-height: var(--text-2xl--line-height);
    font-weight: var(--font-weight-semibold);
    letter-spacing: -0.025em;
    font-variant-numeric: tabular-nums;
    overflow-wrap: anywhere;
  }
  & .tun-stat-meta {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    column-gap: calc(var(--spacing) * 1.5);
    color: var(--muted-foreground);
    font-size: var(--text-xs);
    line-height: var(--text-xs--line-height);
  }
  & .tun-stat-change {
    display: inline-flex;
    align-items: center;
    gap: var(--spacing);
    font-weight: var(--font-weight-medium);
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
    &[data-variant='success'] { color: var(--success); }
    &[data-variant='destructive'] { color: var(--destructive); }
    &[data-variant='neutral'] { color: var(--foreground); }
  }
}")
  (:examples
   ("An overview"
    (stat (:label "Turnover in October" :value "€184,250" :change "+12%"
                  :note "from September" :icon :banknote))
    (stat (:label "Open orders" :value "23" :change "−3" :note "from last week"
                  :icon :shopping-cart))
    (stat (:label "Outstanding" :value "€31,250" :change "+8%" :change-tone :destructive
                  :note "4 invoices" :icon :receipt))
    (stat (:label "Jobs this week" :value "12" :note "3 with no one responsible" :icon :wrench)))
   ("Without a change and an icon"
    (stat (:label "Customers" :value "1,204"))
    (stat (:label "Average order value" :value "€2,940" :change "0%"
                  :note "unchanged"))))
  (let* ((direction (and change (change-direction change)))
         (tone (or change-tone (case direction (:up :success) (:down :destructive)
                                     (t :neutral)))))
    (check-type tone (member :success :destructive :neutral))
    `(:dl ,(attrs (list :class "tun-stat" :id id) attributes)
          (:dt (:@ :class "tun-stat-label")
               (:span ,label)
               ,@(when icon (list (icon (:name icon)))))
          (:dd (:@ :class "tun-stat-value") ,value)
          ,@(when (or change note)
              `((:dd (:@ :class "tun-stat-meta")
                     ,@(when change
                         `((:span (:@ :class "tun-stat-change"
                                      :data-variant ,(option-string tone))
                                  ,@(when direction
                                      (list (icon (:name (if (eq direction :up)
                                                             :trending-up
                                                             :trending-down)
                                                         :size :sm))))
                                  ,change)))
                     ,@(when note `((:span ,note)))))))))

;;; ------------------------------------------------------------------
;;; Empty state

(define-component empty-state ((&key (icon :inbox) title description (heading-level 3)
                                     (variant :default) id attributes)
                               &rest children)
  (:group "Data")
  (:doc "What shows where there is nothing yet, such as an empty list of orders: what is
missing, why, and the buttons to get started. The variant outline gives a dashed border.")
  (:source "Basecoat empty (Vega)")
  (:css "
.tun-empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: calc(var(--spacing) * 4);
  width: 100%;
  min-width: 0;
  padding: calc(var(--spacing) * 8) calc(var(--spacing) * 4);
  border-radius: var(--radius-lg);
  text-align: center;
  text-wrap: balance;
  white-space: normal;
  &[data-variant='outline'] { border: 1px dashed var(--border); }
  & .tun-empty-state-header {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: calc(var(--spacing) * 2);
    max-width: 24rem;
  }
  & .tun-empty-state-media {
    display: flex;
    align-items: center;
    justify-content: center;
    width: calc(var(--spacing) * 12);
    height: calc(var(--spacing) * 12);
    margin-bottom: calc(var(--spacing) * 2);
    border-radius: var(--radius-full);
    background-color: var(--muted);
    color: var(--foreground);
    & .tun-icon:not([data-size]) {
      width: calc(var(--spacing) * 6);
      height: calc(var(--spacing) * 6);
    }
  }
  & .tun-empty-state-title {
    color: var(--foreground);
    font-size: var(--text-lg);
    line-height: var(--text-lg--line-height);
    font-weight: var(--font-weight-medium);
    letter-spacing: -0.0125em;
  }
  & .tun-empty-state-description {
    color: var(--muted-foreground);
    font-size: var(--text-sm);
    line-height: 1.625;
  }
  & .tun-empty-state-actions {
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    gap: calc(var(--spacing) * 2);
  }
  @media (min-width: 40rem) {
    & { padding: calc(var(--spacing) * 12); }
  }
}")
  (:examples
   (("No orders yet" :layout :stack)
    (empty-state (:icon :shopping-cart :title "No orders yet"
                        :description "When a customer orders, the order comes here. You can
also register an order yourself.")
                 (button (:href "/orders/new" :icon :plus) "New order")
                 (button (:variant :outline :href "/orders/import" :icon :upload) "Import")))
   (("With a border, without actions" :layout :stack)
    (empty-state (:variant :outline :icon :search :title "No customers match the search"
                           :description "Check the spelling, or search by organisation number
or phone number.")))
   (("In a table" :layout :stack)
    (table (:columns '("Order" "Customer" "Date" ("Amount" :align :end))
                     :rows '()
                     :empty (empty-state (:icon :shopping-cart :title "No orders yet"
                                                :description "Your orders show here.")
                                         (button (:size :sm :href "/orders/new" :icon :plus)
                                                 "New order"))))))
  (check-type title string)
  `(:div ,(attrs (list :class "tun-empty-state" :id id
                       :data-variant (unless (eq variant :default) (option-string variant)))
                 attributes)
         (:div (:@ :class "tun-empty-state-header")
               ,@(when icon
                   `((:div (:@ :class "tun-empty-state-media") ,(icon (:name icon)))))
               (,(heading-tag heading-level) (:@ :class "tun-empty-state-title") ,title)
               ,@(when description
                   `((:p (:@ :class "tun-empty-state-description") ,description))))
         ,@(when children
             `((:div (:@ :class "tun-empty-state-actions") ,@children)))))

;;; ------------------------------------------------------------------
;;; Pagination

(defun pagination-items (page pages)
  "The pages a pagination shows around PAGE of PAGES, with :GAP for a run of
pages left out.  Seven items at most, so the control keeps its width: the
first page, the last, and the pages around PAGE."
  (cond ((<= pages 7)
         (loop for n from 1 to pages collect n))
        ((<= page 4)
         (append (loop for n from 1 to 5 collect n) (list :gap pages)))
        ((>= page (- pages 3))
         (cons 1 (cons :gap (loop for n from (- pages 4) to pages collect n))))
        (t
         (list 1 :gap (1- page) page (1+ page) :gap pages))))

(defun page-url (href page)
  "The URL of PAGE: HREF is a format string with ~D or a function of the page."
  (etypecase href
    (string (format nil href page))
    ((or function symbol) (funcall href page))))

(define-component pagination ((&key page pages href (label (tr "Pagination")) id attributes))
  (:group "Data")
  (:doc "Links between the pages of a long list. HREF is a format string with ~d or a
function from a page number to its address. On a phone only Previous, Next and «Page 3 of 12»
show. With only one page there is no pagination.")
  (:source "Basecoat pagination (Vega); wording from Designsystemet")
  (:css "
.tun-pagination {
  container: tun-pagination / inline-size;
  width: 100%;
  & .tun-pagination-list {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--spacing);
  }
  & .tun-pagination-page .tun-button {
    width: auto;
    min-width: var(--control-height);
    padding-inline: calc(var(--spacing) * 2);
    font-variant-numeric: tabular-nums;
  }
  & .tun-pagination-gap {
    display: flex;
    align-items: center;
    justify-content: center;
    width: var(--control-height);
    height: var(--control-height);
    color: var(--muted-foreground);
  }
  & .tun-pagination-status {
    display: none;
    color: var(--muted-foreground);
    font-size: var(--text-sm);
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }
  & .tun-pagination-hidden {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
    white-space: nowrap;
  }
  @container tun-pagination (width < 30rem) {
    & .tun-pagination-list { justify-content: space-between; }
    & :is(.tun-pagination-page, .tun-pagination-gap) { display: none; }
    & .tun-pagination-status { display: block; }
  }
}")
  (:examples
   (("Page 3 of 12" :layout :stack)
    (pagination (:page 3 :pages 12 :href "/orders?page=~d")))
   (("In the middle, with a function for the address" :layout :stack)
    (pagination (:page 7 :pages 24
                       :href (lambda (page) (format nil "/customers?page=~d&sort=name" page)))))
   (("The first and the last page" :layout :stack)
    (pagination (:page 1 :pages 5 :href "/invoices?page=~d"))
    (pagination (:page 5 :pages 5 :href "/invoices?page=~d"))))
  (check-type pages integer)
  (check-type page integer)
  (unless (<= 1 page (max pages 1))
    (error "Page ~d is outside 1 to ~d" page pages))
  (when (> pages 1)
    `(:nav ,(attrs (list :class "tun-pagination" :id id :aria-label label) attributes)
           (:ul (:@ :class "tun-pagination-list")
                (:li (:@ :class "tun-pagination-previous")
                     ,(button (:variant :ghost :href (page-url href (max 1 (1- page)))
                                        :icon :chevron-left
                                        :disabled (= page 1) :label (tr "Previous page"))
                              (tr "Previous")))
                ,@(loop for item in (pagination-items page pages)
                        collect (if (eq item :gap)
                                    `(:li (:@ :class "tun-pagination-gap")
                                          ,(icon (:name :ellipsis))
                                          (:span (:@ :class "tun-pagination-hidden")
                                                 ,(tr "More pages")))
                                    `(:li (:@ :class "tun-pagination-page")
                                          ,(button (:variant (if (= item page) :outline :ghost)
                                                             :size :icon :href (page-url href item)
                                                             :label (tr "Page ~d" item)
                                                             :attributes (when (= item page)
                                                                           '(:aria-current "page")))
                                                   (princ-to-string item)))))
                (:li (:@ :class "tun-pagination-status")
                     ,(tr "Page ~d of ~d" page pages))
                (:li (:@ :class "tun-pagination-next")
                     ,(button (:variant :ghost :href (page-url href (min pages (1+ page)))
                                        :icon-end :chevron-right :disabled (= page pages)
                                        :label (tr "Next page"))
                              (tr "Next")))))))

;;; ------------------------------------------------------------------
;;; Timeline

(defun timeline-entry (entry)
  "An entry of a timeline: ENTRY is a plist (:TIME :DATETIME :ACTOR :TEXT :ICON
:VARIANT :DETAIL)."
  (destructuring-bind (&key time datetime actor text icon (variant :default) detail) entry
    (check-type variant (member :default :success :info :warning :destructive))
    `(:li (:@ :class "tun-timeline-entry")
          (:span ,(attrs (list :class "tun-timeline-marker"
                               :data-variant (unless (eq variant :default)
                                               (option-string variant))))
                 ,(if icon
                      (icon (:name icon :size :sm))
                      '(:span (:@ :class "tun-timeline-dot"))))
          (:div (:@ :class "tun-timeline-body")
                (:p (:@ :class "tun-timeline-text")
                    ,@(when actor `((:span (:@ :class "tun-timeline-actor") ,actor) " "))
                    ,text)
                ,@(when time
                    `((:time ,(attrs (list :class "tun-timeline-time" :datetime datetime))
                             ,time)))
                ,@(when detail
                    `((:div (:@ :class "tun-timeline-detail") ,detail)))))))

(define-component timeline ((&key entries label id attributes))
  (:group "Data")
  (:doc "What has happened to a record, such as an order's history: who did what, and when.
Newest first or oldest first, but the same everywhere in the product.")
  (:source "shadcn/ui activity feed, Basecoat look")
  (:css "
.tun-timeline {
  display: flex;
  flex-direction: column;
  font-size: var(--text-sm);
  line-height: var(--text-sm--line-height);
  & .tun-timeline-entry {
    position: relative;
    display: grid;
    grid-template-columns: auto minmax(0, 1fr);
    column-gap: calc(var(--spacing) * 3);
    padding-bottom: calc(var(--spacing) * 6);
    &:last-child { padding-bottom: 0; }
    /* The line from this entry's marker down to the next one's. */
    &:not(:last-child)::before {
      content: '';
      position: absolute;
      top: calc(var(--spacing) * 9);
      bottom: var(--spacing);
      inset-inline-start: calc(var(--spacing) * 4 - 0.5px);
      width: 1px;
      background-color: var(--border);
    }
  }
  & .tun-timeline-marker {
    display: flex;
    align-items: center;
    justify-content: center;
    width: calc(var(--spacing) * 8);
    height: calc(var(--spacing) * 8);
    border-radius: var(--radius-full);
    background-color: var(--muted);
    color: var(--muted-foreground);
    &[data-variant='success'] { background-color: var(--success-soft); color: var(--success); }
    &[data-variant='info'] { background-color: var(--info-soft); color: var(--info); }
    &[data-variant='warning'] { background-color: var(--warning-soft); color: var(--warning); }
    &[data-variant='destructive'] {
      background-color: var(--destructive-soft);
      color: var(--destructive);
    }
  }
  & .tun-timeline-dot {
    width: calc(var(--spacing) * 2);
    height: calc(var(--spacing) * 2);
    border-radius: var(--radius-full);
    background-color: currentColor;
  }
  & .tun-timeline-body {
    display: flex;
    flex-direction: column;
    gap: calc(var(--spacing) * 0.5);
    min-width: 0;
    padding-top: calc(var(--spacing) * 1.5);
  }
  & .tun-timeline-text { overflow-wrap: anywhere; }
  & .tun-timeline-actor { font-weight: var(--font-weight-medium); }
  & .tun-timeline-time {
    color: var(--muted-foreground);
    font-size: var(--text-xs);
    line-height: var(--text-xs--line-height);
    font-variant-numeric: tabular-nums;
  }
  & .tun-timeline-detail {
    margin-top: calc(var(--spacing) * 1.5);
    padding: calc(var(--spacing) * 2.5) calc(var(--spacing) * 3);
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    background-color: color-mix(in oklab, var(--muted) 40%, transparent);
    overflow-wrap: anywhere;
  }
}")
  (:examples
   (("An order's history" :layout :stack)
    (timeline
     (:label "History of order 10481"
             :entries '((:time "11 Oct 2026 at 14:32" :datetime "2026-10-11T14:32+02:00"
                         :actor "Ole Hansen" :text "ordered in the web shop" :icon :shopping-cart)
                        (:time "11 Oct 2026 at 15:05" :datetime "2026-10-11T15:05+02:00"
                         :actor "Kari Nordmann"
                         :text "confirmed the order and emailed the customer"
                         :icon :mail :variant :info)
                        (:time "12 Oct 2026 at 09:40" :datetime "2026-10-12T09:40+02:00"
                         :actor "Kari Nordmann" :text "added a comment" :icon :message-square
                         :detail "The customer wants delivery after 4 pm; the gate is locked
before then.")
                        (:time "13 Oct 2026 at 07:15" :datetime "2026-10-13T07:15+02:00"
                         :actor "Bring" :text "reported that the parcel is a day late"
                         :icon :truck :variant :warning)
                        (:time "14 Oct 2026 at 16:48" :datetime "2026-10-14T16:48+02:00"
                         :actor "Jonas Berg" :text "delivered the order" :icon :circle-check
                         :variant :success)))))
   (("Without icons" :layout :stack)
    (timeline
     (:entries '((:time "Today at 10:12" :datetime "2026-10-13T10:12+02:00"
                  :actor "Tun" :text "sent a reminder for invoice 2026-0187")
                 (:time "Yesterday at 08:00" :datetime "2026-10-12T08:00+02:00"
                  :actor "Tun" :text "marked invoice 2026-0187 as overdue"
                  :variant :destructive))))))
  `(:ol ,(attrs (list :class "tun-timeline" :id id :aria-label label) attributes)
        ,@(mapcar #'timeline-entry entries)))

;;; ------------------------------------------------------------------
;;; Code block

(define-component code-block ((&key title wrap (copy t) (copy-label (tr "Copy")) id attributes)
                              &rest children)
  (:group "Data")
  (:doc "Text to be copied exactly, such as an access token or a command, with a button that
copies it. Without JavaScript the button is hidden, and the text can be selected and copied
as usual. WRAP breaks long lines instead of scrolling sideways.")
  (:source "shadcn/ui code block, Basecoat look")
  (:css "
.tun-code-block {
  position: relative;
  min-width: 0;
  overflow: hidden;
  border: 1px solid var(--border);
  border-radius: var(--radius-lg);
  background-color: color-mix(in oklab, var(--muted) 60%, transparent);
  & .tun-code-block-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: calc(var(--spacing) * 2);
    min-height: calc(var(--spacing) * 10);
    padding-inline: calc(var(--spacing) * 4) calc(var(--spacing) * 1);
    border-bottom: 1px solid var(--border);
    color: var(--muted-foreground);
    font-size: var(--text-xs);
    line-height: var(--text-xs--line-height);
    font-weight: var(--font-weight-medium);
  }
  & .tun-code-block-pre {
    overflow-x: auto;
    padding: calc(var(--spacing) * 3) calc(var(--spacing) * 4);
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    line-height: 1.7;
    tab-size: 2;
  }
  &[data-wrap] .tun-code-block-pre { white-space: pre-wrap; overflow-wrap: anywhere; }
  & .tun-code-block-tools {
    display: flex;
    align-items: center;
    gap: calc(var(--spacing) * 2);
  }
  /* Without a header the button stands beside the text, so text that
     scrolls sideways never runs under it. */
  &:has(> .tun-code-block-tools) { display: flex; align-items: flex-start; }
  & > .tun-code-block-pre { flex: 1; min-width: 0; }
  & > .tun-code-block-tools {
    position: relative;
    flex-shrink: 0;
    padding: calc(var(--spacing) * 1.5);
    & .tun-code-block-status {
      position: absolute;
      top: 50%;
      inset-inline-end: 100%;
      translate: 0 -50%;
      white-space: nowrap;
    }
    & .tun-code-block-status:not(:empty) {
      padding: calc(var(--spacing) * 0.5) calc(var(--spacing) * 2);
      border-radius: var(--radius-sm);
      background-color: var(--background);
      box-shadow: var(--shadow-xs);
    }
  }
  & .tun-code-block-status {
    color: var(--muted-foreground);
    font-size: var(--text-xs);
    line-height: var(--text-xs--line-height);
    font-weight: var(--font-weight-medium);
  }
  & [data-tun-copy] {
    & .tun-icon[data-state='done'] { display: none; }
    &[data-copied] .tun-icon[data-state='done'] { display: block; color: var(--success); }
    &[data-copied] .tun-icon[data-state='idle'] { display: none; }
  }
}")
  (:script "
// The copy buttons: [data-tun-copy=ID] copies the text of the element ID and
// says so in [data-tun-copy-status=ID], with the texts that element holds.
// The buttons are hidden until this script knows the browser can copy.
const reveal = (root) => {
  if (!navigator.clipboard) return;
  for (const button of root.querySelectorAll('[data-tun-copy][hidden]')) button.hidden = false;
};
tunOnContent(reveal);
document.addEventListener('click', async (event) => {
  const button = event.target.closest('[data-tun-copy]');
  if (!button) return;
  const id = button.dataset.tunCopy;
  const source = document.getElementById(id);
  const status = document.querySelector(`[data-tun-copy-status='${CSS.escape(id)}']`);
  if (!source) return;
  const say = (text) => { if (status) status.textContent = text; };
  try {
    await navigator.clipboard.writeText(source.textContent);
    button.dataset.copied = '';
    say(status?.dataset.tunCopyDone);
  } catch (error) {
    window.getSelection().selectAllChildren(source);
    say(status?.dataset.tunCopyFailed);
  }
  clearTimeout(button.tunCopyTimer);
  button.tunCopyTimer = setTimeout(() => {
    delete button.dataset.copied;
    say('');
  }, 2000);
});")
  (:examples
   (("A command" :layout :stack)
    (code-block (:copy-label "Copy the command")
                "claude mcp add --transport http tun https://customer.example.com/mcp"))
   (("An access token with a title, broken over several lines" :layout :stack)
    (code-block (:title "Access token" :wrap t :copy-label "Copy the access token")
                "tun_live_7f3a9c2e1b8d4f60a5e7c9b1d3f2a4e6c8b0d2f4a6e8c0b2d4f6a8e0c2b4d6f8"))
   (("Several lines, without copying" :layout :stack)
    (code-block (:title "Setup" :copy nil)
                "nix develop .
bin/repl --port 4005
bin/test --only ui")))
  (let ((code-id (element-id "tun-code")))
    (flet ((tools ()
             (when copy
               `((:div (:@ :class "tun-code-block-tools")
                       (:span (:@ :class "tun-code-block-status" :role "status"
                                  :aria-live "polite" :data-tun-copy-status ,code-id
                                  :data-tun-copy-done ,(tr "Copied")
                                  :data-tun-copy-failed
                                  ,(tr "Could not copy. The text is selected.")))
                       ,(button (:variant :ghost :size :icon-sm :label copy-label
                                          :attributes (list :hidden t :data-tun-copy code-id))
                                (icon (:name :copy :attributes '(:data-state "idle")))
                                (icon (:name :check :attributes '(:data-state "done")))))))))
      `(:div ,(attrs (list :class "tun-code-block" :id id :data-wrap (when wrap "true"))
                     attributes)
             ,@(when title
                 `((:div (:@ :class "tun-code-block-header")
                         (:span ,title)
                         ,@(tools))))
             (:pre (:@ :class "tun-code-block-pre")
                   (:code (:@ :class "tun-code-block-code" :id ,code-id) ,@children))
             ,@(unless title (tools))))))
