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
  (:group "Oppsett og navigasjon")
  (:doc "Legger innholdet side om side og bryter til en ny linje når plassen tar slutt: knapper,
merkelapper, filtre. JUSTIFY (start, center, end, between) og ALIGN (start, center, end,
baseline, stretch) styrer plasseringen.")
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
   (("Knapper" :layout :stack)
    (cluster ()
             (button (:icon :plus) "Ny ordre")
             (button (:variant :outline :icon :download) "Eksporter")
             (button (:variant :ghost) "Flere valg"))
    (cluster (:justify :end)
             (button (:variant :outline) "Avbryt")
             (button () "Lagre tilbud")))
   (("Fordelt og på grunnlinjen" :layout :stack)
    (cluster (:justify :between :align :baseline)
             '(:strong "Faktura 2024-118")
             '(:span "Forfaller 30. oktober")
             '(:strong "12 450 kr"))))
  (check-type gap (member :xs :sm :md :lg :xl))
  (check-type justify (member :start :center :end :between))
  (check-type align (member :start :center :end :baseline :stretch))
  `(:div ,(attrs (list :class "tun-cluster" :id id :data-gap (option-string gap)
                       :data-justify (unless (eq justify :start) (option-string justify))
                       :data-align (unless (eq align :center) (option-string align)))
                 attributes)
         ,@children))

(define-component stack ((&key (gap :md) id attributes) &rest children)
  (:group "Oppsett og navigasjon")
  (:doc "Legger innholdet under hverandre med lik avstand (GAP: xs, sm, md, lg eller xl). Bruk
den i stedet for marger når deler av en side skal ha luft mellom seg.")
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
   (("Avstander" :layout :stack)
    (stack (:gap :xs)
           '(:strong "Ole Hansen AS")
           '(:span "Storgata 12, 0155 Oslo")
           '(:span "ole@example.no"))
    (stack (:gap :lg)
           '(:p "Ordren er pakket og sendt med Bring.")
           '(:p "Kunden får sporingsnummeret på e-post når pakken er registrert.")
           (cluster () (button (:variant :outline) "Vis ordre") (button () "Send faktura")))))
  (check-type gap (member :xs :sm :md :lg :xl))
  `(:div ,(attrs (list :class "tun-stack" :id id :data-gap (option-string gap)) attributes)
         ,@children))

(define-component grid ((&key (min :md) (gap :md) id attributes) &rest children)
  (:group "Oppsett og navigasjon")
  (:doc "Et rutenett som fyller raden med så mange kolonner som får plass, hver minst MIN bred
(xs 10rem, sm 14rem, md 18rem, lg 24rem). På en telefon blir det én kolonne av seg selv.")
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
   (("Smale kolonner (xs)" :layout :stack)
    (grid (:min :xs :gap :sm)
          '(:p "Åpne ordre: 7")
          '(:p "Til fakturering: 3")
          '(:p "Forfalt: 1")
          '(:p "Sendt i dag: 12")))
   (("Brede kolonner (md)" :layout :stack)
    (grid ()
          (stack (:gap :xs) '(:strong "Ole Hansen AS") '(:span "Storgata 12, 0155 Oslo"))
          (stack (:gap :xs) '(:strong "Fjord Catering") '(:span "Bryggen 3, 5003 Bergen"))
          (stack (:gap :xs) '(:strong "Nordlys Event og Teltutleie") '(:span "Tromsø")))))
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
  (:group "Oppsett og navigasjon")
  (:doc "Viser hvor siden ligger: nivåene over den som lenker og siden selv til slutt. ITEMS er
en liste av (:label TEKST :href STI); den siste er siden du står på. På en smal skjerm vises
bare en lenke tilbake til nivået over.")
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
   (("Tre nivåer" :layout :stack)
    (breadcrumbs (:items '((:label "Kunder" :href "/kunder")
                           (:label "Ole Hansen AS" :href "/kunder/42")
                           (:label "Rediger kunde")))))
   (("Mange nivåer og lang tekst" :layout :stack)
    (breadcrumbs (:items '((:label "Oversikt" :href "/")
                           (:label "Ordre" :href "/ordre")
                           (:label "Ordre 1042 – Nordlys Event og Teltutleie AS"
                            :href "/ordre/1042")
                           (:label "Pakkseddel og fraktbrev")))))
   (("Bare siden selv" :layout :stack)
    (breadcrumbs (:items '((:label "Oversikt"))))))
  (check-type items cons)
  (let ((parent (when (rest items) (first (last items 2)))))
    `(:nav ,(attrs (list :class "tun-breadcrumbs" :id id :aria-label "Brødsmuler") attributes)
           ,@(when parent
               (list `(:a (:@ :class "tun-breadcrumbs-back" :href ,(getf parent :href))
                          ,(icon (:name :arrow-left))
                          "Tilbake til " ,(getf parent :label))))
           (:ol ,@(breadcrumbs-trail items)))))

;;; ------------------------------------------------------------------
;;; Lists of links

(defun path-below-p (path href)
  "True when PATH is a page below HREF: /kunder/42 is below /kunder, and
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
  (:group "Oppsett og navigasjon")
  (:doc "En loddrett liste av lenker, til en meny i siden eller en innstillingsside. ITEMS er
lenker (:label :href :icon :count); GROUPS er grupper (:heading TEKST :items LENKER). Lenken til
CURRENT er merket; finnes den ikke, merkes den nærmeste lenken over (/kunder for /kunder/42).
LABEL navngir menyen for skjermlesere.")
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
   (("Innstillinger i grupper" :layout :stack)
    (nav-list (:label "Innstillinger"
                      :current "/innstillinger/brukere"
                      :groups '((:heading "Firma"
                                 :items ((:label "Firmaopplysninger" :href "/innstillinger/firma"
                                                 :icon :building)
                                         (:label "Brukere" :href "/innstillinger/brukere"
                                                 :icon :users :count 4)
                                         (:label "Tilgang og roller" :href "/innstillinger/tilgang"
                                                 :icon :shield-check)))
                                (:heading "Salg"
                                 :items ((:label "Faktura og betalingsvilkår"
                                                 :href "/innstillinger/faktura" :icon :receipt)
                                         (:label "Frakt" :href "/innstillinger/frakt" :icon :truck)
                                         (:label "Eksport av regnskapsdata til regnskapsfører"
                                                 :href "/innstillinger/eksport" :icon :download
                                                 :count 12)))))))
   (("Uten ikoner, under en side som er valgt" :layout :stack)
    (nav-list (:label "Kunde"
                      :current "/kunder/42/ordre/1042"
                      :items '((:label "Oversikt" :href "/kunder/42")
                               (:label "Ordre" :href "/kunder/42/ordre" :count 18)
                               (:label "Faktura" :href "/kunder/42/faktura" :count 2)
                               (:label "Notater" :href "/kunder/42/notater"))))))
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
  (:group "Oppsett og navigasjon")
  (:doc "Toppen av en side: brødsmuler (BREADCRUMBS, eller som barn), tittelen som eneste h1, en
kort beskrivelse og sidens handlinger (ACTIONS, en liste av knapper). Handlingene står til høyre
for tittelen når de får plass ved siden av den, også på en telefon, og ellers under.")
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
   (("Med brødsmuler, beskrivelse og handlinger" :layout :stack)
    (page-header (:title "Ole Hansen AS"
                         :description "Kunde siden mars 2021. Faktureres månedlig, 14 dager."
                         :breadcrumbs '((:label "Kunder" :href "/kunder") (:label "Ole Hansen AS"))
                         :actions (list (button (:variant :outline :icon :pencil) "Rediger")
                                        (button (:icon :plus) "Ny ordre")))))
   (("Bare tittel" :layout :stack)
    (page-header (:title "Kunder")))
   (("Lang tittel" :layout :stack)
    (page-header (:title "Tilbud 2024-031: Sommerfest med telt og lysrigg for Fjord Catering"
                         :breadcrumbs '((:label "Tilbud" :href "/tilbud")
                                        (:label "Tilbud 2024-031"))
                         :actions (list (button (:variant :outline) "Forhåndsvis")
                                        (button (:icon :send) "Send til kunden"))))))
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
  (:group "Oppsett og navigasjon")
  (:doc "En del av en side med egen overskrift (h2, eller h3 med LEVEL 3), en kort beskrivelse og
handlinger som gjelder bare denne delen. I en app-shell eller en stack får seksjonene luft mellom
seg.")
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
   (("Med beskrivelse og handling" :layout :stack)
    (section (:title "Kontaktpersoner"
                     :description "Den første får ordrebekreftelser og faktura på e-post."
                     :actions (list (button (:variant :outline :size :sm :icon :user-plus)
                                            "Legg til")))
             '(:p "Kari Nordmann, daglig leder – kari@example.no – 912 34 567")
             '(:p "Per Olsen, innkjøp – per@example.no")))
   (("To seksjoner i en stack, den siste med h3" :layout :stack)
    (stack (:gap :xl)
           (section (:title "Leveringsadresse")
                    '(:p "Storgata 12, 0155 Oslo"))
           (section (:title "Merknader til sjåføren" :level 3)
                    '(:p "Ring på forhånd. Porten er låst etter kl. 16."))))
   (("Lang tittel og flere handlinger" :layout :stack)
    (section (:title "Ordrelinjer som venter på varer fra leverandøren"
                     :actions (list (button (:variant :ghost :size :sm) "Vis alle")
                                    (button (:variant :outline :size :sm :icon :refresh-cw)
                                            "Sjekk lager")))
             '(:p "3 linjer venter. Forventet levering 18. oktober."))))
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
                                          "Innlogget som")
                                   (:span (:@ :class "tun-app-shell-name") ,user)))))
           ,@(when logout-action
               (list `(:form (:@ :class "tun-app-shell-logout" :method "post"
                                 :action ,logout-action)
                             ,(button (:type "submit" :variant :outline :icon :log-out)
                                      "Logg ut")))))))

(define-component app-shell ((&key title (home "/") nav nav-groups current user logout-action
                                   (width :default) (main-id "hovedinnhold") id attributes)
                             &rest children)
  (:group "Oppsett og navigasjon")
  (:doc "Rammen rundt hver side for de ansatte: en lenke forbi menyen, appens navn, hovedmenyen
(NAV, lenker som i nav-list, med CURRENT merket), hvem som er innlogget og «Logg ut». På en
telefon ligger menyen bak en menyknapp og virker uten JavaScript. Fra 64rem er den en sidemeny,
ikke en meny i toppen: seks punkter med ikon og antall får ikke plass ved siden av navnet og
brukeren på en smalere skjerm, og en sidemeny har plass til flere moduler. Med :width :narrow
står innholdet smalt og midt på siden, for en side med ett kort skjema som innloggingen; med
:width :wide bruker det hele bredden ved siden av menyen, for en tavle eller en bred oversikt.")
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
   (("En hel side" :layout :stack)
    (app-shell (:title "Nordvik Utleie"
                       :nav '((:label "Kunder" :href "/kunder" :icon :users :count 128)
                              (:label "Ordre" :href "/ordre" :icon :shopping-cart :count 7)
                              (:label "Tilbud" :href "/tilbud" :icon :file-text :count 3)
                              (:label "Lager" :href "/lager" :icon :package)
                              (:label "Innstillinger" :href "/innstillinger" :icon :settings)
                              (:label "Tilgang" :href "/tilgang" :icon :shield-check))
                       :current "/kunder/42"
                       :user "admin:jonas"
                       :logout-action "/logout")
               (page-header (:title "Ole Hansen AS"
                                    :description "Kunde siden mars 2021. Faktureres månedlig."
                                    :breadcrumbs '((:label "Kunder" :href "/kunder")
                                                   (:label "Ole Hansen AS"))
                                    :actions (list (button (:variant :outline :icon :pencil)
                                                           "Rediger")
                                                   (button (:icon :plus) "Ny ordre"))))
               (section (:title "Kontakt")
                        (grid (:min :sm)
                              (stack (:gap :xs)
                                     '(:strong "Kari Nordmann")
                                     '(:span "Daglig leder")
                                     '(:span "kari@example.no · 912 34 567"))
                              (stack (:gap :xs)
                                     '(:strong "Fakturaadresse")
                                     '(:span "Storgata 12")
                                     '(:span "0155 Oslo"))))
               (section (:title "Siste ordre"
                                :description "Ordre fra de siste 90 dagene."
                                :actions (list (button (:variant :outline :size :sm
                                                                 :href "/ordre?kunde=42")
                                                       "Vis alle")))
                        (stack (:gap :sm)
                               (cluster (:justify :between)
                                        '(:span "Ordre 1042, 3. oktober")
                                        '(:strong "12 450 kr"))
                               (cluster (:justify :between)
                                        '(:span "Ordre 1031, 14. september")
                                        '(:strong "4 800 kr"))))))
   (("Uten bruker og meny, smal" :layout :stack)
    (app-shell (:title "Nordvik Utleie" :width :narrow)
               (page-header (:title "Logg inn" :description "Logg inn i Nordvik Utleie."))
               (card ()
                     (form-actions ()
                       (button (:type "submit" :icon :log-in) "Logg inn"))))))
  (check-type title string)
  (check-type width (member :default :narrow :wide))
  (let* ((menu-p (or nav nav-groups user logout-action))
         (menu-id (element-id "tun-app-shell-menu"))
         (open-button (button (:variant :ghost :size :icon :label "Meny"
                                        :attributes (list :popovertarget menu-id))
                              (icon (:name :menu))))
         (close-button (button (:variant :ghost :size :icon :label "Lukk menyen"
                                         :attributes (list :popovertarget menu-id
                                                           :popovertargetaction "hide"))
                               (icon (:name :x)))))
    `(:div ,(attrs (list :class "tun-app-shell" :id id) attributes)
           (:a (:@ :class "tun-app-shell-skip" :href ,(format nil "#~a" main-id))
               "Hopp til hovedinnholdet")
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
                                      (:span "Meny")
                                      ,close-button)
                                ,@(when (or nav nav-groups)
                                    (list `(:div (:@ :class "tun-app-shell-nav")
                                                 ,(nav-list (:label "Hovedmeny" :items nav
                                                                    :groups nav-groups
                                                                    :current current)))))
                                ,@(when (or user logout-action)
                                    (list (app-shell-account user logout-action)))))))
           (:main (:@ :class "tun-app-shell-main" :id ,main-id :tabindex "-1")
                  (:div (:@ :class "tun-app-shell-content"
                            :data-width ,(unless (eq width :default) (option-string width)))
                        ,@children)))))
