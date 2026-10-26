;;;; web/ui/actions.lisp -- the actions group (spec/ui.md 6).

(in-package #:tun.ui)

(declaim (optimize (safety 3) (debug 2)))

(defun shortcut-keys (shortcut)
  "The keys of SHORTCUT, a key or Ctrl and a key as a dialog's :shortcut takes
them: \"Ctrl+K\" is (\"Ctrl\" \"K\"), \"/\" is (\"/\") (spec/ui.md 6)."
  (check-type shortcut string)
  (let ((keys (uiop:split-string shortcut :separator "+")))
    (unless (and (every #'plusp (mapcar #'length keys))
                 (or (= (length keys) 1)
                     (and (= (length keys) 2) (string-equal (first keys) "Ctrl"))))
      (error "The shortcut ~s is not a key, or Ctrl and a key, such as \"Ctrl+K\""
             shortcut))
    keys))

(defun aria-keyshortcuts (keys)
  "KEYS as aria-keyshortcuts says them: Ctrl is both Control and Meta, since a
dialog opens on either."
  (if (rest keys)
      (format nil "Control+~a Meta+~:*~a" (second keys))
      (first keys)))

(defun shortcut-caps (keys)
  "KEYS as caps for the end of a button, hidden from screen readers, which
hear aria-keyshortcuts instead."
  (apply #'kbd* '(:attributes (:data-tun-shortcut "" :data-icon "end" :aria-hidden "true"))
         (loop for key in keys
               collect (if (string-equal key "Ctrl")
                           (kbd* '(:attributes (:data-tun-key "ctrl")) "Ctrl")
                           (kbd* '() key)))))

(define-component button ((&key (variant :primary) (size :default) (type "button") href
                                icon icon-end shortcut label name value disabled id attributes)
                          &rest children)
  (:group "Handlinger")
  (:doc "En knapp for en handling, eller en lenke (HREF) som ser ut som en. Bruk én
hovedknapp (primary) per skjema; resten secondary, outline eller ghost. En knapp med bare
ikon (størrelse icon) må ha LABEL. SHORTCUT, som \"Ctrl+K\", viser hurtigtasten for det
knappen åpner på store skjermer; tasten bindes av dialogen den åpner.")
  (:source "Basecoat button (Vega)")
  (:script "
// A shortcut's Ctrl cap reads Cmd's sign where the key is Cmd: on a Mac,
// an iPhone or an iPad.
const apple = /Mac|iPhone|iPad/.test(navigator.platform);
tunOnContent((root) => {
  if (!apple) return;
  for (const key of root.querySelectorAll('kbd[data-tun-key=ctrl]')) key.textContent = '⌘';
});")
  (:css "
.tun-button {
  display: inline-flex;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  gap: calc(var(--spacing) * 1.5);
  height: var(--control-height);
  padding-inline: calc(var(--spacing) * 2.5);
  border: 1px solid transparent;
  border-radius: var(--radius-md);
  background-clip: padding-box;
  font-size: var(--text-sm);
  line-height: var(--text-sm--line-height);
  font-weight: var(--font-weight-medium);
  white-space: nowrap;
  text-decoration: none;
  user-select: none;
  outline: none;
  transition-property: color, background-color, border-color, box-shadow, translate;
  transition-duration: var(--duration-fast);
  transition-timing-function: var(--ease);
  &:focus-visible { border-color: var(--ring); box-shadow: var(--focus-ring); }
  &:active:not([aria-haspopup]) { translate: 0 1px; }
  &:disabled, &[aria-disabled='true'] { pointer-events: none; opacity: 0.5; }
  & .tun-icon:not([data-size]) {
    width: calc(var(--spacing) * 4);
    height: calc(var(--spacing) * 4);
  }
  &:has(> [data-icon='start']) { padding-left: calc(var(--spacing) * 2); }
  &:has(> [data-icon='end']) { padding-right: calc(var(--spacing) * 2); }

  &[data-size='xs'] {
    height: calc(var(--spacing) * 6);
    gap: var(--spacing);
    padding-inline: calc(var(--spacing) * 2);
    border-radius: min(var(--radius-md), 8px);
    font-size: var(--text-xs);
    line-height: var(--text-xs--line-height);
    & .tun-icon:not([data-size]) {
      width: calc(var(--spacing) * 3);
      height: calc(var(--spacing) * 3);
    }
  }
  &[data-size='sm'] {
    height: var(--control-height-sm);
    gap: var(--spacing);
    border-radius: min(var(--radius-md), 10px);
  }
  &:is([data-size='xs'], [data-size='sm']) {
    &:has(> [data-icon='start']) { padding-left: calc(var(--spacing) * 1.5); }
    &:has(> [data-icon='end']) { padding-right: calc(var(--spacing) * 1.5); }
  }
  &[data-size='lg'] { height: var(--control-height-lg); }
  &[data-size='icon'] { width: var(--control-height); padding: 0; }
  &[data-size='icon-xs'] {
    width: calc(var(--spacing) * 6);
    height: calc(var(--spacing) * 6);
    padding: 0;
    border-radius: min(var(--radius-md), 8px);
    & .tun-icon:not([data-size]) {
      width: calc(var(--spacing) * 3);
      height: calc(var(--spacing) * 3);
    }
  }
  &[data-size='icon-sm'] {
    width: var(--control-height-sm);
    height: var(--control-height-sm);
    padding: 0;
    border-radius: min(var(--radius-md), 10px);
  }
  &[data-size='icon-lg'] {
    width: var(--control-height-lg);
    height: var(--control-height-lg);
    padding: 0;
  }
  /* A shortcut's keys show where a keyboard is likely, and an icon button
     then grows to hold them beside its icon. */
  & > [data-tun-shortcut] { display: none; }
  @media (min-width: 48rem) {
    & > [data-tun-shortcut] { display: inline-flex; }
    &[data-size^='icon']:has(> [data-tun-shortcut]) {
      width: auto;
      padding-inline: calc(var(--spacing) * 2);
    }
  }
  /* The extra small sizes stay small on a touch screen, so an invisible
     area around them takes the finger: as high as a control there, and at
     least as wide. */
  @media (pointer: coarse) {
    &:is([data-size='xs'], [data-size='icon-xs']) {
      position: relative;
      &::before {
        content: '';
        position: absolute;
        inset: min(0px, calc(50% - var(--control-height) / 2));
      }
    }
  }

  &[data-variant='primary'] {
    background-color: var(--primary);
    color: var(--primary-foreground);
    @media (hover: hover) {
      &:hover { background-color: color-mix(in oklab, var(--primary) 80%, transparent); }
    }
  }
  &[data-variant='secondary'] {
    background-color: var(--secondary);
    color: var(--secondary-foreground);
    @media (hover: hover) {
      &:hover { background-color: color-mix(in oklch, var(--secondary), var(--foreground) 5%); }
    }
    &[aria-expanded='true'] { background-color: var(--secondary); }
    &:is([aria-pressed='true'], [aria-current='page']) {
      background-color: color-mix(in oklch, var(--secondary), var(--foreground) 10%);
    }
  }
  &[data-variant='outline'] {
    border-color: light-dark(var(--border), var(--input));
    background-color: light-dark(var(--background),
                                 color-mix(in oklab, var(--input) 30%, transparent));
    color: var(--foreground);
    box-shadow: var(--shadow-xs);
    @media (hover: hover) {
      &:hover {
        background-color: light-dark(var(--muted),
                                     color-mix(in oklab, var(--input) 50%, transparent));
      }
    }
    &:is([aria-expanded='true'], [aria-pressed='true'], [aria-current='page']) {
      background-color: light-dark(var(--muted),
                                   color-mix(in oklab, var(--input) 60%, transparent));
    }
    &:focus-visible { box-shadow: var(--focus-ring); }
  }
  &[data-variant='ghost'] {
    color: var(--foreground);
    @media (hover: hover) {
      &:hover {
        background-color: light-dark(var(--muted),
                                     color-mix(in oklab, var(--muted) 50%, transparent));
      }
    }
    &:is([aria-expanded='true'], [aria-pressed='true'], [aria-current='page']) {
      background-color: var(--muted);
    }
  }
  &[data-variant='link'] {
    color: var(--primary);
    text-underline-offset: 4px;
    @media (hover: hover) {
      &:hover { text-decoration-line: underline; }
    }
  }
  &[data-variant='destructive'] {
    background-color: light-dark(color-mix(in oklab, var(--destructive) 10%, transparent),
                                 color-mix(in oklab, var(--destructive) 20%, transparent));
    /* --destructive on its own tint is 4.4:1 in the light scheme; a little
       of the text colour brings it over AA's 4.5:1. */
    color: color-mix(in oklab, var(--destructive), var(--foreground) 15%);
    @media (hover: hover) {
      &:hover {
        background-color: light-dark(color-mix(in oklab, var(--destructive) 20%, transparent),
                                     color-mix(in oklab, var(--destructive) 30%, transparent));
      }
    }
    &:focus-visible {
      border-color: color-mix(in oklab, var(--destructive) 40%, transparent);
      box-shadow: 0 0 0 3px color-mix(in oklab, var(--destructive) 20%, transparent);
    }
  }
}")
  (:examples
   ("Varianter"
    (button () "Lagre")
    (button (:variant :secondary) "Kladd")
    (button (:variant :outline) "Avbryt")
    (button (:variant :ghost) "Mer")
    (button (:variant :link) "Vis alle")
    (button (:variant :destructive) "Slett"))
   ("Størrelser"
    (button (:size :xs) "Ekstra liten")
    (button (:size :sm) "Liten")
    (button () "Vanlig")
    (button (:size :lg) "Stor"))
   ("Med ikon"
    (button (:icon :plus) "Ny ordre")
    (button (:variant :outline :icon-end :arrow-right) "Neste")
    (button (:variant :secondary :icon :download) "Last ned"))
   ("Bare ikon"
    (button (:size :icon :variant :outline :label "Rediger") (icon (:name :pencil)))
    (button (:size :icon-sm :variant :ghost :label "Flere valg") (icon (:name :ellipsis)))
    (button (:size :icon-lg :variant :destructive :label "Slett") (icon (:name :trash))))
   ("Med hurtigtast, vist på store skjermer"
    (button (:variant :outline :size :icon :label "Søk" :icon :search :shortcut "Ctrl+K"))
    (button (:variant :ghost :icon :search :shortcut "/") "Søk"))
   ("Lenke og deaktivert"
    (button (:href "/ui" :variant :outline) "Til oversikten")
    (button (:disabled t) "Lagre")
    (button (:href "/ui" :disabled t :variant :outline) "Utilgjengelig lenke"))
   ("Trykket inn (aria-pressed) og gjeldende side (aria-current)"
    (button (:variant :outline :icon :star :attributes '(:aria-pressed "true")) "Favoritt")
    (button (:variant :ghost :icon :funnel :attributes '(:aria-pressed "true")) "Filter på")
    (button (:variant :outline :size :icon :label "Side 2" :href "/ordre?side=2"
                      :attributes '(:aria-current "page"))
            "2")))
  (when (and (member size '(:icon :icon-xs :icon-sm :icon-lg)) (null label))
    (error "A button of size ~(~a~) shows only an icon, so it needs :label" size))
  (let ((keys (and shortcut (shortcut-keys shortcut))))
    `(,(if href :a :button)
       ,(attrs (list :class "tun-button" :id id :data-variant (option-string variant)
                     :data-size (option-string size) :aria-label label
                     :aria-keyshortcuts (and keys (aria-keyshortcuts keys)))
               (if href
                   (list :href (unless disabled href) :aria-disabled (when disabled "true"))
                   (list :type type :name name :value value :disabled disabled))
               attributes)
       ,@(when icon (list (icon (:name icon :attributes '(:data-icon "start")))))
       ,@children
       ,@(when icon-end (list (icon (:name icon-end :attributes '(:data-icon "end")))))
       ,@(when keys (list (shortcut-caps keys))))))

(define-component button-group ((&key label (orientation :horizontal) separated id attributes)
                                &rest children)
  (:group "Handlinger")
  (:doc "Knapper som hører sammen, satt sammen til én kontroll: valg av visning, en delt
knapp med en meny ved siden av, forrige og neste. Gi gruppen LABEL, som skjermlesere leser
opp. SEPARATED setter en skillelinje mellom delene, som trengs for knapper uten kant
(primary og secondary).")
  (:source "Basecoat button group (Vega)")
  (:css "
.tun-button-group {
  isolation: isolate;
  display: inline-flex;
  width: fit-content;
  align-items: stretch;
  /* A focused part's ring is drawn over its neighbours. */
  & > :focus-visible { position: relative; z-index: 1; }
  &:has(> .tun-button-group) { gap: calc(var(--spacing) * 2); }
  & > .tun-button-group-separator {
    flex-shrink: 0;
    align-self: stretch;
    width: 1px;
    margin-block: 1px;
    background-color: var(--input);
  }
  /* On a filled primary button the line is a shade of the button itself. */
  &:has(> [data-variant='primary']) > .tun-button-group-separator {
    background-color: color-mix(in oklab, var(--primary), var(--primary-foreground) 25%);
  }
  /* Text between the buttons, such as which page is shown. */
  & > :is(span, label, output):not([class]) {
    display: flex;
    align-items: center;
    gap: calc(var(--spacing) * 2);
    padding-inline: calc(var(--spacing) * 2.5);
    border: 1px solid light-dark(var(--border), var(--input));
    border-radius: var(--radius-md);
    background-color: var(--muted);
    box-shadow: var(--shadow-xs);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    font-weight: var(--font-weight-medium);
    white-space: nowrap;
  }

  &:not([data-orientation='vertical']) {
    & > :not(:first-child) {
      border-start-start-radius: 0;
      border-end-start-radius: 0;
      border-inline-start-width: 0;
    }
    & > :not(:last-child) {
      border-start-end-radius: 0;
      border-end-end-radius: 0;
    }
  }
  &[data-orientation='vertical'] {
    flex-direction: column;
    & > .tun-button-group-separator {
      width: auto;
      height: 1px;
      margin-block: 0;
      margin-inline: 1px;
    }
    & > :not(:first-child) {
      border-top-left-radius: 0;
      border-top-right-radius: 0;
      border-top-width: 0;
    }
    & > :not(:last-child) {
      border-bottom-left-radius: 0;
      border-bottom-right-radius: 0;
    }
  }
}")
  (:examples
   ("Knapper som hører sammen"
    (button-group (:label "Handlinger for ordre 1042")
      (button (:variant :outline) "Kopier")
      (button (:variant :outline) "Skriv ut")
      (button (:variant :outline) "Send"))
    (button-group (:label "Handlinger for ordre 1042")
      (button (:variant :outline :icon :copy) "Kopier")
      (button (:variant :outline :size :icon :label "Skriv ut") (icon (:name :file-text)))
      (button (:variant :outline :size :icon :label "Slett") (icon (:name :trash)))))
   ("Valg av visning"
    (button-group (:label "Visning")
      (button (:variant :outline :icon :list :attributes '(:aria-pressed "true")) "Liste")
      (button (:variant :outline :icon :layout-dashboard :attributes '(:aria-pressed "false"))
              "Tavle")
      (button (:variant :outline :icon :calendar :attributes '(:aria-pressed "false"))
              "Kalender")))
   ("Delt knapp"
    (button-group (:label "Send faktura" :separated t)
      (button (:icon :send) "Send faktura")
      (button (:size :icon :label "Andre måter å sende på") (icon (:name :chevron-down))))
    (button-group (:label "Lagre tilbud" :separated t)
      (button (:variant :secondary) "Lagre")
      (button (:variant :secondary :size :icon :label "Flere valg for lagring")
              (icon (:name :chevron-down))))
    (button-group (:label "Ny ordre")
      (button (:variant :outline :icon :plus) "Ny ordre")
      (button (:variant :outline :size :icon :label "Ny ordre fra mal")
              (icon (:name :chevron-down)))))
   ("Bla i sider"
    (button-group (:label "Sider i ordrelisten")
      (button (:variant :outline :size :icon :label "Forrige side" :href "/ordre?side=1")
              (icon (:name :chevron-left)))
      '(:span "Side 2 av 8")
      (button (:variant :outline :size :icon :label "Neste side" :href "/ordre?side=3")
              (icon (:name :chevron-right))))
    (button-group (:label "Sider i fakturalisten")
      (button-group ()
        (button (:variant :outline :size :icon-sm :label "Side 1" :href "/fakturaer?side=1")
                "1")
        (button (:variant :outline :size :icon-sm :label "Side 2" :href "/fakturaer?side=2"
                          :attributes '(:aria-current "page"))
                "2")
        (button (:variant :outline :size :icon-sm :label "Side 3" :href "/fakturaer?side=3")
                "3"))
      (button-group ()
        (button (:variant :outline :size :icon-sm :label "Forrige side"
                          :href "/fakturaer?side=1")
                (icon (:name :arrow-left)))
        (button (:variant :outline :size :icon-sm :label "Neste side"
                          :href "/fakturaer?side=3")
                (icon (:name :arrow-right))))))
   ("Loddrett"
    (button-group (:label "Antall" :orientation :vertical)
      (button (:variant :outline :size :icon :label "Øk antallet") (icon (:name :plus)))
      (button (:variant :outline :size :icon :label "Reduser antallet") (icon (:name :minus))))
    (button-group (:label "Flytt oppdraget" :orientation :vertical)
      (button (:variant :outline :icon :arrow-up) "Flytt opp")
      (button (:variant :outline :icon :arrow-down) "Flytt ned")))
   ("Størrelser"
    (button-group (:label "Periode")
      (button (:variant :outline :size :sm) "Dag")
      (button (:variant :outline :size :sm) "Uke")
      (button (:variant :outline :size :sm) "Måned"))
    (button-group (:label "Periode")
      (button (:variant :outline) "Dag")
      (button (:variant :outline) "Uke")
      (button (:variant :outline) "Måned"))
    (button-group (:label "Periode")
      (button (:variant :outline :size :lg) "Dag")
      (button (:variant :outline :size :lg) "Uke")
      (button (:variant :outline :size :lg) "Måned"))))
  (check-type orientation (member :horizontal :vertical))
  `(:div ,(attrs (list :class "tun-button-group" :id id :role "group" :aria-label label
                       :data-orientation (option-string orientation))
                 attributes)
         ,@(let ((parts (remove nil children)))
             (if separated
                 (loop for (part . more) on parts
                       collect part
                       when more collect (button-group-separator orientation))
                 parts))))

(defun button-group-separator (orientation)
  "The line between two parts of a button group laid out in ORIENTATION."
  `(:hr (:@ :class "tun-button-group-separator" :role "separator"
            :aria-orientation ,(if (eq orientation :vertical) "horizontal" "vertical"))))

(define-component link ((&key href (variant :default) external id attributes) &rest children)
  (:group "Handlinger")
  (:doc "En lenke i løpende tekst, til en kunde, en ordre eller en side. Variant muted er for
lenker som er mindre viktige enn teksten rundt. EXTERNAL viser at lenken går til et annet
nettsted. Bruk knappen med HREF når lenken skal se ut som en knapp.")
  (:source "shadcn/ui typography (lenke), Basecoat-utseende")
  (:css "
.tun-link {
  border-radius: 2px;
  color: var(--primary);
  font-weight: var(--font-weight-medium);
  text-decoration-line: underline;
  text-decoration-color: color-mix(in oklab, currentColor 40%, transparent);
  text-decoration-thickness: 1px;
  text-underline-offset: 4px;
  transition-property: color, text-decoration-color;
  transition-duration: var(--duration-fast);
  transition-timing-function: var(--ease);
  @media (hover: hover) {
    &:hover { text-decoration-color: currentColor; }
  }
  &[data-variant='muted'] {
    color: var(--muted-foreground);
    font-weight: inherit;
    @media (hover: hover) {
      &:hover { color: var(--foreground); }
    }
  }
  & > .tun-icon {
    display: inline-block;
    width: 0.875em;
    height: 0.875em;
    margin-inline-start: 0.125em;
    vertical-align: -0.0625em;
  }
  /* Read by screen readers, not shown. */
  & > .tun-link-hint {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
    white-space: nowrap;
  }
}")
  (:examples
   (("I løpende tekst" :layout :stack)
    `(:p "Ordren hører til "
         ,(link (:href "/kunder/218") "Rørlegger Hansen AS")
         " og ble fakturert 3. oktober. Se "
         ,(link (:href "/fakturaer/10417") "faktura 10417")
         " for beløp og forfallsdato."))
   (("Dempet" :layout :stack)
    `(:p "Sist endret av Kari Nordmann for to timer siden. "
         ,(link (:href "/ordre/1042/historikk" :variant :muted) "Vis historikken")))
   (("Til et annet nettsted" :layout :stack)
    `(:p "Organisasjonsnummeret slås opp i "
         ,(link (:href "https://www.brreg.no" :external t) "Brønnøysundregistrene")
         ".")))
  (check-type href string)
  `(:a ,(attrs (list :class "tun-link" :id id :href href
                     :data-variant (unless (eq variant :default) (option-string variant)))
               attributes)
       ,@children
       ,@(when external
           (list (icon (:name :external-link))
                 '(:span (:@ :class "tun-link-hint") " (annet nettsted)")))))

(define-component kbd ((&key id attributes) &rest children)
  (:group "Handlinger")
  (:doc "En tast på tastaturet, i hjelpetekst og ved handlinger med hurtigtast. Taster som
trykkes sammen er en KBD med en KBD for hver tast inni.")
  (:source "Basecoat kbd (Vega)")
  (:css "
.tun-kbd {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: var(--spacing);
  width: fit-content;
  min-width: calc(var(--spacing) * 5);
  height: calc(var(--spacing) * 5);
  padding-inline: var(--spacing);
  border-radius: var(--radius-sm);
  background-color: var(--muted);
  /* --muted-foreground on --muted is 4.3:1 in the light scheme; a little of
     the text colour brings it over AA's 4.5:1. */
  color: color-mix(in oklab, var(--muted-foreground), var(--foreground) 20%);
  font-family: var(--font-sans);
  font-size: var(--text-xs);
  line-height: var(--text-xs--line-height);
  font-weight: var(--font-weight-medium);
  white-space: nowrap;
  vertical-align: middle;
  pointer-events: none;
  user-select: none;
  & .tun-icon:not([data-size]) {
    width: calc(var(--spacing) * 3);
    height: calc(var(--spacing) * 3);
  }
  /* Keys pressed together: the outer KBD only lines them up. */
  &:has(> .tun-kbd) {
    min-width: 0;
    height: auto;
    padding: 0;
    background-color: transparent;
    color: inherit;
  }
}")
  (:examples
   ("Taster"
    (kbd () "Ctrl")
    (kbd () "Shift")
    (kbd () "Enter")
    (kbd () "Esc")
    (kbd () "Tab")
    (kbd () "K"))
   ("Taster som trykkes sammen"
    (kbd () (kbd () "Ctrl") "+" (kbd () "K"))
    (kbd () (kbd () "Alt") "+" (kbd () "N"))
    (kbd () (kbd () "Ctrl") "+" (kbd () "Shift") "+" (kbd () "S")))
   (("I hjelpetekst" :layout :stack)
    `(:p "Trykk " ,(kbd () (kbd () "Ctrl") "+" (kbd () "K"))
         " for å søke etter kunder og ordre, og " ,(kbd () "Esc") " for å lukke søket."))
   ("I en knapp"
    (button (:variant :outline) "Lagre" (kbd (:attributes '(:data-icon "end")) "Enter"))
    (button (:variant :ghost) "Søk" (kbd (:attributes '(:data-icon "end")) "/"))))
  `(:kbd ,(attrs (list :class "tun-kbd" :id id) attributes) ,@children))

(define-component badge ((&key (variant :primary) icon id attributes) &rest children)
  (:group "Handlinger")
  (:doc "En liten merkelapp for status eller kategori, som «Bekreftet» på en ordre. Variantene
success, warning, info og destructive er for status; primary, secondary og outline for
alt annet. Teksten sier hva det gjelder, så fargen er aldri det eneste som skiller dem.")
  (:source "Basecoat badge (Vega) med Tuns statusfarger")
  (:css "
.tun-badge {
  display: inline-flex;
  flex-shrink: 0;
  align-items: center;
  justify-content: center;
  gap: var(--spacing);
  width: fit-content;
  height: calc(var(--spacing) * 5);
  padding: calc(var(--spacing) * 0.5) calc(var(--spacing) * 2);
  overflow: hidden;
  border: 1px solid transparent;
  border-radius: var(--radius-full);
  font-size: var(--text-xs);
  line-height: var(--text-xs--line-height);
  font-weight: var(--font-weight-medium);
  white-space: nowrap;
  vertical-align: middle;
  & > .tun-icon {
    width: calc(var(--spacing) * 3);
    height: calc(var(--spacing) * 3);
  }
  &:has(> .tun-icon:first-child) { padding-inline-start: calc(var(--spacing) * 1.5); }

  &[data-variant='primary'] { background-color: var(--primary); color: var(--primary-foreground); }
  &[data-variant='secondary'] {
    background-color: var(--secondary);
    color: var(--secondary-foreground);
  }
  &[data-variant='outline'] { border-color: var(--border); color: var(--foreground); }
  &[data-variant='success'] {
    border-color: color-mix(in oklab, var(--success) 20%, transparent);
    background-color: var(--success-soft);
    color: var(--success);
  }
  &[data-variant='warning'] {
    border-color: color-mix(in oklab, var(--warning) 20%, transparent);
    background-color: var(--warning-soft);
    color: var(--warning);
  }
  &[data-variant='info'] {
    border-color: color-mix(in oklab, var(--info) 20%, transparent);
    background-color: var(--info-soft);
    color: var(--info);
  }
  &[data-variant='destructive'] {
    border-color: color-mix(in oklab, var(--destructive) 20%, transparent);
    background-color: var(--destructive-soft);
    /* --destructive on --destructive-soft is 4.4:1 in the light scheme; a
       little of the text colour brings it over AA's 4.5:1. */
    color: color-mix(in oklab, var(--destructive), var(--foreground) 15%);
  }
}")
  (:examples
   ("Varianter"
    (badge () "Ny")
    (badge (:variant :secondary) "Fast kunde")
    (badge (:variant :outline) "Kladd")
    (badge (:variant :success) "Betalt")
    (badge (:variant :warning) "Forfalt")
    (badge (:variant :info) "Til vurdering")
    (badge (:variant :destructive) "Avvist"))
   ("Status på ordre"
    (badge (:variant :outline :icon :file) "Kladd")
    (badge (:variant :info :icon :send) "Tilbud sendt")
    (badge (:variant :success :icon :check) "Bekreftet")
    (badge (:variant :warning :icon :clock) "Venter på kunden")
    (badge (:variant :secondary :icon :receipt) "Fakturert")
    (badge (:variant :destructive :icon :x) "Kansellert"))
   (("I en tabellrad" :layout :stack)
    `(:p "Ordre 1042 · Rørlegger Hansen AS · 12 500 kr "
         ,(badge (:variant :success) "Bekreftet"))))
  `(:span ,(attrs (list :class "tun-badge" :id id :data-variant (option-string variant))
                  attributes)
          ,@(when icon (list (icon (:name icon))))
          ,@children))

(defun initials (name)
  "The initials of NAME, from its first and last words: \"Kari Nordmann\" is
\"KN\", \"Anne-Lise Berg\" is \"AB\" and \"Ola\" is \"O\"."
  (let ((words (cl-ppcre:split "\\s+" (string-trim '(#\Space #\Tab #\Newline) name))))
    (string-upcase
     (cond ((null words) "")
           ((null (rest words)) (subseq (first words) 0 1))
           (t (format nil "~a~a" (char (first words) 0) (char (first (last words)) 0)))))))

(defun person-plist (person)
  "PERSON in an avatar group, a name or a plist (:name :src :alt), as a plist."
  (if (stringp person) (list :name person) person))

(defun avatar-group (people size max label id attributes)
  "The markup of an avatar group: the first MAX of PEOPLE overlapping, then
how many more there are."
  (let* ((people (mapcar #'person-plist people))
         (shown (subseq people 0 (min max (length people))))
         (hidden (nthcdr max people))
         (more (when hidden
                 (format nil "~d til: ~{~a~^, ~}" (length hidden)
                         (mapcar (lambda (person) (getf person :name)) hidden)))))
    `(:div ,(attrs (list :class "tun-avatar" :id id :data-group t :role "group"
                         :aria-label label)
                   attributes)
           ,@(mapcar (lambda (person) (avatar* (list* :size size person))) shown)
           ,@(when hidden
               `((:span (:@ :class "tun-avatar" :data-count t :role "img" :aria-label ,more
                            :title ,more :data-size ,(unless (eq size :default)
                                                       (option-string size)))
                        (:span (:@ :class "tun-avatar-initials" :aria-hidden "true")
                               ,(format nil "+~d" (length hidden)))))))))

(define-component avatar ((&key name src alt (size :default) group (max 4) label id
                                attributes))
  (:group "Handlinger")
  (:doc "En person som initialer i en sirkel, eller bildet deres med SRC. ALT er det
skjermlesere leser (navnet hvis ikke); sett ALT til \"\" når navnet står like ved. GROUP er
en liste med navn eller (:name :src) som vises overlappende, MAX av gangen, med LABEL for
hele gruppen.")
  (:source "Basecoat avatar (Vega)")
  (:script "
// A photo that does not load is hidden, so the initials under it show
// instead of the browser's broken-image sign.  Error events do not bubble,
// so they are caught on their way down; a photo that failed before this
// script ran is found when the page is ready.
const hide = (image) => { image.hidden = true; };
document.addEventListener('error', (event) => {
  if (event.target instanceof HTMLImageElement
      && event.target.matches('[data-tun-avatar-image]')) hide(event.target);
}, true);
tunOnContent((root) => {
  for (const image of root.querySelectorAll('img[data-tun-avatar-image]'))
    if (image.complete && image.naturalWidth === 0) hide(image);
});")
  (:css "
.tun-avatar {
  position: relative;
  display: inline-flex;
  flex-shrink: 0;
  width: calc(var(--spacing) * 8);
  height: calc(var(--spacing) * 8);
  border-radius: var(--radius-full);
  vertical-align: middle;
  user-select: none;
  /* A hairline that keeps a light photo apart from a light page. */
  &::after {
    content: '';
    position: absolute;
    inset: 0;
    border: 1px solid color-mix(in oklab, var(--foreground) 10%, transparent);
    border-radius: inherit;
    pointer-events: none;
  }
  &[data-size='sm'] { width: calc(var(--spacing) * 6); height: calc(var(--spacing) * 6); }
  &[data-size='lg'] { width: calc(var(--spacing) * 10); height: calc(var(--spacing) * 10); }
  & > .tun-avatar-initials {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 100%;
    height: 100%;
    border-radius: inherit;
    background-color: var(--muted);
    /* --muted-foreground on --muted is 4.3:1 in the light scheme. */
    color: color-mix(in oklab, var(--muted-foreground), var(--foreground) 20%);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    font-weight: var(--font-weight-medium);
  }
  &[data-size='sm'] > .tun-avatar-initials {
    font-size: var(--text-xs);
    line-height: var(--text-xs--line-height);
  }
  /* The photo covers the initials, which show if it does not load. */
  & > .tun-avatar-image {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    border-radius: inherit;
    object-fit: cover;
  }

  &[data-group] {
    width: auto;
    height: auto;
    border-radius: 0;
    &::after { content: none; }
    /* Overlapping only as far as the initials stay whole. */
    & > .tun-avatar {
      box-shadow: 0 0 0 2px var(--background);
      &:not(:last-child) { margin-inline-end: calc(var(--spacing) * -1.5); }
      & > .tun-avatar-initials {
        font-size: var(--text-xs);
        line-height: var(--text-xs--line-height);
      }
    }
    & > [data-size='sm'] {
      &:not(:last-child) { margin-inline-end: calc(var(--spacing) * -0.75); }
      /* Two letters fit beside the next avatar only at 10px. */
      & > .tun-avatar-initials { font-size: 0.625rem; }
    }
    & > [data-size='lg'] {
      &:not(:last-child) { margin-inline-end: calc(var(--spacing) * -2); }
      & > .tun-avatar-initials {
        font-size: var(--text-sm);
        line-height: var(--text-sm--line-height);
      }
    }
  }
}")
  (:examples
   ("Initialer"
    (avatar (:name "Kari Nordmann"))
    (avatar (:name "Anne-Lise Berg"))
    (avatar (:name "Øystein Ås"))
    (avatar (:name "Ola")))
   ("Størrelser"
    (avatar (:name "Kari Nordmann" :size :sm))
    (avatar (:name "Kari Nordmann"))
    (avatar (:name "Kari Nordmann" :size :lg)))
   ("Med bilde som ikke lastes: initialene vises"
    (avatar (:name "Per Olsen" :src "/bilder/ansatte/per-olsen.jpg" :size :lg)))
   (("Ved siden av navnet" :layout :stack)
    `(:p ,(avatar (:name "Kari Nordmann" :alt "" :size :sm))
         " Kari Nordmann tok oppdraget «Bytte av varmtvannsbereder»."))
   ("Gruppe"
    (avatar (:group '("Kari Nordmann" "Ola Hansen" "Per Olsen") :label "Montører på oppdraget"))
    (avatar (:group '("Kari Nordmann" "Ola Hansen" "Per Olsen" "Lise Berg" "Jon Dahl"
                      "Anne Moe")
                    :max 3 :size :sm :label "Følger ordren"))
    (avatar (:group '("Kari Nordmann" "Ola Hansen" "Per Olsen" "Lise Berg" "Jon Dahl")
                    :max 3 :size :lg :label "Ansatte"))))
  (check-type max (integer 1))
  (cond (group
         (when (or name src)
           (error "An avatar group takes :group, not :name or :src"))
         (avatar-group group size max label id attributes))
        (t
         (let ((text (or alt name)))
           (unless text
             (error "An avatar needs :name, or :alt with its :src"))
           `(:span ,(attrs (list :class "tun-avatar" :id id
                                 :data-size (unless (eq size :default) (option-string size))
                                 :role (unless (equal text "") "img")
                                 :aria-label (unless (equal text "") text)
                                 :aria-hidden (when (equal text "") "true"))
                           attributes)
                   ,@(when name
                       `((:span (:@ :class "tun-avatar-initials" :aria-hidden "true")
                                ,(initials name))))
                   ,@(when src
                       `((:img (:@ :class "tun-avatar-image" :src ,src :alt ""
                                   :loading "lazy" :data-tun-avatar-image t)))))))))
