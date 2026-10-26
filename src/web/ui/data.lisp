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
                               (empty "Ingen oppføringer.") id attributes))
  (:group "Data")
  (:doc "En liste med poster, som ordre, kunder eller fakturaer. Første kolonne er det som
kjenner igjen posten: på en smal skjerm blir den tittelen på et kort, og de andre verdiene står
med kolonnens navn. Med ROW-HREF er hele raden en lenke til posten; beløp og tall høyrestilles
med :align :end. En kolonne med :sort NØKKEL kan sorteres: overskriften blir en lenke til
SORT-HREF (en funksjon av nøkkelen og \"asc\" eller \"desc\", eller en formatstreng), og
:sorted :asc eller :desc viser hvordan radene er sortert. Siden sorterer; tabellen viser bare
overskriftene.")
  (:source "Basecoat table (Vega); kort på mobil etter GOV.UK og Aksel")
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
   (("Ordreliste" :layout :stack)
    (table (:caption "Ordre siste uke"
                     :columns '(("Ordre" :width :min) "Kunde" ("Dato" :width :min) "Status"
                                ("Beløp" :align :end))
                     :rows '(("10482" "Fjordkaffe AS" "12.10.2026" "Ny" "4 380,00 kr")
                             ("10481" "Hansen Bygg og Anlegg AS" "11.10.2026" "Under arbeid"
                              "128 950,00 kr")
                             ("10480" "Kari Nordmann" "10.10.2026" "Sendt" "649,00 kr")
                             ("10479" "Tromsø Sykkelverksted" "09.10.2026" "Fakturert"
                              "12 400,00 kr")
                             ("10478" "Bakeriet på Hjørnet" "08.10.2026" "Kansellert" "0,00 kr"))
                     :row-href (lambda (row) (format nil "/ordre/~a" (first row))))))
   (("Fakturalinjer med sum og skjult tekst" :layout :stack)
    (table (:caption "Linjer på faktura 2026-0193" :caption-hidden t
                     :columns '(("Beskrivelse" :wrap t) ("Antall" :align :end :width :min)
                                ("Pris" :align :end :width :min) ("Sum" :align :end :width :min))
                     :rows '(("Montering av kjøkkenskap, inkludert justering av dører og skuffer"
                              "6 t" "850,00 kr" "5 100,00 kr")
                             ("Benkeplate i eik, 240 cm" "1" "4 990,00 kr" "4 990,00 kr")
                             ("Kjøring" "38 km" "5,00 kr" "190,00 kr"))
                     :footer '("Totalt eks. mva." nil nil "10 280,00 kr"))))
   (("Sorterbare kolonner" :layout :stack)
    (table (:caption "Saker"
                     :columns '(("Sak" :sort "title") ("Kunde" :sort "customer")
                                ("Opprettet" :sort "created" :sorted :desc :width :min) "Status")
                     :rows '(("Eksporten til regnskap feiler" "Fjordkaffe AS" "21.10.2026" "Ny")
                             ("Vis lager på ordren" "Hansen Bygg AS" "20.10.2026" "Planlagt"))
                     :sort-href "/saker?sort=~a&retning=~a")))
   (("Uten rader" :layout :stack)
    (table (:caption "Fakturaer til forfall"
                     :columns '("Faktura" "Kunde" "Forfall" ("Beløp" :align :end))
                     :rows '()
                     :empty "Ingen fakturaer forfaller de neste 14 dagene."))))
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
               ;; hears every «Endre» on its own when it lists the links.
               `((:dd (:@ :class "tun-summary-list-action")
                      (:a (:@ :href ,href)
                          ,action
                          (:span (:@ :class "tun-summary-list-hidden") " " ,key))))))))

(define-component summary-list ((&key rows (action "Endre") id attributes))
  (:group "Data")
  (:doc "Detaljene i én post, som en kunde eller en ordre: et navn og en verdi per rad, og
gjerne en lenke for å endre verdien. På mobil står navnet over verdien.")
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
   (("Kunde" :layout :stack)
    (summary-list
     (:rows '(("Navn" "Hansen Bygg og Anlegg AS" :href "/kunder/412/endre#navn")
              ("Organisasjonsnummer" "912 345 678")
              ("Kontaktperson" "Ole Hansen" :href "/kunder/412/endre#kontakt")
              ("E-post" "ole.hansen@example.no" :href "/kunder/412/endre#e-post")
              ("Telefon" "+47 912 34 567" :href "/kunder/412/endre#telefon")
              ("Fakturaadresse" ((:p "Industriveien 14") (:p "7080 Heimdal"))
               :href "/kunder/412/endre#adresse")))))
   (("Uten lenker" :layout :stack)
    (summary-list
     (:rows '(("Ordre" "10481")
              ("Bestilt" "11. oktober 2026 kl. 14.32")
              ("Levering" "Hentes i butikken, Storgata 3, Tromsø")
              ("Betalingsmåte" "Faktura, 14 dager"))))))
  `(:dl ,(attrs (list :class "tun-summary-list" :id id) attributes)
        ,@(mapcar (lambda (row) (summary-list-row row action)) rows)))

;;; ------------------------------------------------------------------
;;; Card

(define-component card ((&key title description action footer href (heading-level 3)
                              (size :default) id attributes)
                        &rest children)
  (:group "Data")
  (:doc "En ramme rundt innhold som hører sammen, med tittel, beskrivelse, innhold og bunn.
Med HREF er hele kortet en lenke (tittelen er lenketeksten); ACTION er en knapp eller lenke
øverst i hjørnet.")
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
   (("Med tittel, handling og bunn" :layout :stack)
    (card (:title "Hansen Bygg og Anlegg AS"
                  :description "Kunde siden mars 2021"
                  :action (button (:variant :outline :size :sm :href "/kunder/412/endre"
                                            :icon :pencil)
                                  "Endre")
                  :footer (list (button (:href "/ordre/ny?kunde=412" :icon :plus) "Ny ordre")
                                (button (:variant :ghost :href "/kunder/412/ordre") "Alle ordre")))
          (summary-list (:rows '(("Kontaktperson" "Ole Hansen")
                                 ("Telefon" "+47 912 34 567")
                                 ("Utestående" "18 400,00 kr"))))))
   ("Kort som lenker"
    (card (:title "Oppdrag uke 42" :href "/oppdrag?uke=42" :size :sm
                  :description "12 oppdrag, 3 uten ansvarlig")
          '(:p "Neste: montering hos Kari Nordmann, tirsdag kl. 08.00."))
    (card (:title "Fakturaer til forfall" :href "/faktura?status=forfall" :size :sm
                  :description "4 fakturaer, 31 250,00 kr")
          '(:p "Eldste forfalt 3. oktober.")))
   ("Bare innhold"
    (card ()
          '(:p "Kortet uten tittel er bare en ramme rundt innholdet, for eksempel et notat om
kunden: «Ring før levering, porten er låst etter kl. 16.»"))))
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
  "Whether the change CHANGE, a string such as \"+12 %\" or \"−3 %\", is :UP,
:DOWN or neither (NIL), by its sign."
  (let ((first (find-if-not (lambda (char) (char= char #\Space)) change)))
    (case first
      (#\+ :up)
      ((#\- #\MINUS_SIGN) :down))))

(define-component stat ((&key label value change change-tone note icon id attributes))
  (:group "Data")
  (:doc "Et nøkkeltall på en oversikt, som omsetning eller antall åpne ordre, med endring
og en kort merknad. Endringen er grønn når den går opp og rød når den går ned; sett
CHANGE-TONE når opp er dårlig, som for utestående beløp.")
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
   ("Oversikt"
    (stat (:label "Omsetning i oktober" :value "184 250 kr" :change "+12 %"
                  :note "fra september" :icon :banknote))
    (stat (:label "Åpne ordre" :value "23" :change "−3" :note "fra forrige uke"
                  :icon :shopping-cart))
    (stat (:label "Utestående" :value "31 250 kr" :change "+8 %" :change-tone :destructive
                  :note "4 fakturaer" :icon :receipt))
    (stat (:label "Oppdrag denne uken" :value "12" :note "3 uten ansvarlig" :icon :wrench)))
   ("Uten endring og ikon"
    (stat (:label "Kunder" :value "1 204"))
    (stat (:label "Gjennomsnittlig ordreverdi" :value "2 940 kr" :change "0 %"
                  :note "uendret"))))
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
  (:doc "Det som vises der det ennå ikke finnes noe, som en tom ordreliste: hva som mangler,
hvorfor, og knappene for å komme i gang. Variant outline gir en stiplet ramme.")
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
   (("Ingen ordre ennå" :layout :stack)
    (empty-state (:icon :shopping-cart :title "Ingen ordre ennå"
                        :description "Når en kunde bestiller, kommer ordren hit. Du kan også
registrere en ordre selv.")
                 (button (:href "/ordre/ny" :icon :plus) "Ny ordre")
                 (button (:variant :outline :href "/ordre/importer" :icon :upload) "Importer")))
   (("Med ramme, uten handlinger" :layout :stack)
    (empty-state (:variant :outline :icon :search :title "Ingen kunder passer søket"
                           :description "Sjekk stavemåten, eller søk på organisasjonsnummer
eller telefonnummer.")))
   (("I en tabell" :layout :stack)
    (table (:columns '("Ordre" "Kunde" "Dato" ("Beløp" :align :end))
                     :rows '()
                     :empty (empty-state (:icon :shopping-cart :title "Ingen ordre ennå"
                                                :description "Ordrene dine vises her.")
                                         (button (:size :sm :href "/ordre/ny" :icon :plus)
                                                 "Ny ordre"))))))
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

(define-component pagination ((&key page pages href (label "Sidenavigering") id attributes))
  (:group "Data")
  (:doc "Lenker mellom sidene i en lang liste. HREF er en formatstreng med ~d eller en
funksjon fra sidenummer til adresse. På mobil vises bare Forrige, Neste og «Side 3 av 12».
Med bare én side blir det ingen sidenavigering.")
  (:source "Basecoat pagination (Vega); ordlyd fra Designsystemet")
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
   (("Side 3 av 12" :layout :stack)
    (pagination (:page 3 :pages 12 :href "/ordre?side=~d")))
   (("Midt i, med en funksjon for adressen" :layout :stack)
    (pagination (:page 7 :pages 24
                       :href (lambda (page) (format nil "/kunder?side=~d&sortering=navn" page)))))
   (("Første og siste side" :layout :stack)
    (pagination (:page 1 :pages 5 :href "/faktura?side=~d"))
    (pagination (:page 5 :pages 5 :href "/faktura?side=~d"))))
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
                                        :disabled (= page 1) :label "Forrige side")
                              "Forrige"))
                ,@(loop for item in (pagination-items page pages)
                        collect (if (eq item :gap)
                                    `(:li (:@ :class "tun-pagination-gap")
                                          ,(icon (:name :ellipsis))
                                          (:span (:@ :class "tun-pagination-hidden")
                                                 "Flere sider"))
                                    `(:li (:@ :class "tun-pagination-page")
                                          ,(button (:variant (if (= item page) :outline :ghost)
                                                             :size :icon :href (page-url href item)
                                                             :label (format nil "Side ~d" item)
                                                             :attributes (when (= item page)
                                                                           '(:aria-current "page")))
                                                   (princ-to-string item)))))
                (:li (:@ :class "tun-pagination-status")
                     ,(format nil "Side ~d av ~d" page pages))
                (:li (:@ :class "tun-pagination-next")
                     ,(button (:variant :ghost :href (page-url href (min pages (1+ page)))
                                        :icon-end :chevron-right :disabled (= page pages)
                                        :label "Neste side")
                              "Neste"))))))

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
  (:doc "Det som har skjedd med en post, som historikken til en ordre: hvem som gjorde hva,
og når. Nyeste først eller eldste først, men det samme overalt i løsningen.")
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
   (("Historikken til en ordre" :layout :stack)
    (timeline
     (:label "Historikk for ordre 10481"
             :entries '((:time "11. okt. 2026 kl. 14.32" :datetime "2026-10-11T14:32+02:00"
                         :actor "Ole Hansen" :text "bestilte i nettbutikken" :icon :shopping-cart)
                        (:time "11. okt. 2026 kl. 15.05" :datetime "2026-10-11T15:05+02:00"
                         :actor "Kari Nordmann" :text "bekreftet ordren og sendte e-post til kunden"
                         :icon :mail :variant :info)
                        (:time "12. okt. 2026 kl. 09.40" :datetime "2026-10-12T09:40+02:00"
                         :actor "Kari Nordmann" :text "la til en kommentar" :icon :message-square
                         :detail "Kunden vil ha levering etter kl. 16, porten er låst før det.")
                        (:time "13. okt. 2026 kl. 07.15" :datetime "2026-10-13T07:15+02:00"
                         :actor "Bring" :text "meldte at pakken er forsinket én dag"
                         :icon :truck :variant :warning)
                        (:time "14. okt. 2026 kl. 16.48" :datetime "2026-10-14T16:48+02:00"
                         :actor "Jonas Berg" :text "leverte ordren" :icon :circle-check
                         :variant :success)))))
   (("Uten ikoner" :layout :stack)
    (timeline
     (:entries '((:time "I dag kl. 10.12" :datetime "2026-10-13T10:12+02:00"
                  :actor "Tun" :text "sendte purring på faktura 2026-0187")
                 (:time "I går kl. 08.00" :datetime "2026-10-12T08:00+02:00"
                  :actor "Tun" :text "markerte faktura 2026-0187 som forfalt"
                  :variant :destructive))))))
  `(:ol ,(attrs (list :class "tun-timeline" :id id :aria-label label) attributes)
        ,@(mapcar #'timeline-entry entries)))

;;; ------------------------------------------------------------------
;;; Code block

(define-component code-block ((&key title wrap (copy t) (copy-label "Kopier") id attributes)
                              &rest children)
  (:group "Data")
  (:doc "Tekst som skal kopieres nøyaktig, som en tilgangsnøkkel eller en kommando, med en
knapp som kopierer den. Uten JavaScript er knappen skjult, og teksten kan merkes og kopieres
som vanlig. WRAP bryter lange linjer i stedet for å rulle sidelengs.")
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
// says so in [data-tun-copy-status=ID].  The buttons are hidden until this
// script knows the browser can copy.
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
    say('Kopiert');
  } catch (error) {
    window.getSelection().selectAllChildren(source);
    say('Kunne ikke kopiere. Teksten er merket.');
  }
  clearTimeout(button.tunCopyTimer);
  button.tunCopyTimer = setTimeout(() => {
    delete button.dataset.copied;
    say('');
  }, 2000);
});")
  (:examples
   (("Kommando" :layout :stack)
    (code-block (:copy-label "Kopier kommandoen")
                "claude mcp add --transport http tun https://kunde.example.no/mcp"))
   (("Tilgangsnøkkel med tittel, brutt over flere linjer" :layout :stack)
    (code-block (:title "Tilgangsnøkkel" :wrap t :copy-label "Kopier tilgangsnøkkelen")
                "tun_live_7f3a9c2e1b8d4f60a5e7c9b1d3f2a4e6c8b0d2f4a6e8c0b2d4f6a8e0c2b4d6f8"))
   (("Flere linjer, uten kopiering" :layout :stack)
    (code-block (:title "Oppsett" :copy nil)
                "nix develop .
bin/repl --port 4005
bin/test --only ui")))
  (let ((code-id (element-id "tun-code")))
    (flet ((tools ()
             (when copy
               `((:div (:@ :class "tun-code-block-tools")
                       (:span (:@ :class "tun-code-block-status" :role "status"
                                  :aria-live "polite" :data-tun-copy-status ,code-id))
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
