;;;; web/ui/interaction.lisp -- the interaction group: dialogs, menus and
;;;; disclosure (spec/ui.md 6).
;;;;
;;;; Each component uses the browser's own behaviour first: <dialog> opened
;;;; with invoker commands (command, commandfor), the Popover API for menus,
;;;; <details name=...> for accordions, CSS anchor positioning.  The scripts
;;;; add what HTML lacks (arrow keys, focus, aria-expanded, tabs) and stand
;;;; in for invoker commands and anchor positioning where a browser has
;;;; neither.

(in-package #:tun.ui)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Helpers

(defun element-attributes (node)
  "The attribute plist of the element NODE, (:TAG [(:@ ...)] CHILD...)."
  (let ((second (second node)))
    (when (and (consp second) (eq (first second) :@))
      (rest second))))

(defun add-element-attributes (node plist)
  "NODE, one element (:TAG [(:@ ...)] CHILD...), with the attributes in PLIST
joined to its own (ATTRS: a value in PLIST replaces NODE's)."
  (unless (and (consp node) (keywordp (first node)))
    (error "Expected one element, not ~s" node))
  (let* ((own (element-attributes node))
         (children (if own (cddr node) (rest node))))
    `(,(first node) ,(attrs own plist) ,@children)))

(defun join-ids (&rest ids)
  "The non-NIL IDS as one space-separated attribute value, or NIL."
  (let ((present (remove nil ids)))
    (when present (format nil "~{~a~^ ~}" present))))

;;; ------------------------------------------------------------------
;;; dialog

(define-component dialog ((&key id title description (variant :default) icon footer action
                                (method "post") shortcut attributes)
                          &rest children)
  (:group "Interaksjon")
  (:doc "Et vindu over siden for en kort oppgave eller et spørsmål som må besvares før man går
videre. Knappen som åpner det, har :attributes (list :command \"show-modal\" :commandfor ID);
«Avbryt» har :command \"close\". Variantene confirm og destructive er for «Er du sikker?»: de
lukkes ikke ved klikk utenfor og har ingen lukkeknapp, bare valgene i FOOTER. Med :shortcut
(\"/\", \"Ctrl+K\" eller en liste av dem) åpnes dialogen med den tasten fra hvor som helst på
siden; Ctrl er Cmd på en Mac, og en tast uten Ctrl virker ikke mens man skriver i et felt.")
  (:source "Basecoat dialog and alert dialog (Vega)")
  (:css "
.tun-dialog {
  --tun-dialog-padding: calc(var(--spacing) * 6);
  /* On a phone the dialog is a sheet along the bottom edge. */
  width: 100%;
  max-width: 100%;
  max-height: calc(100dvh - var(--spacing) * 8);
  margin: auto 0 0;
  padding: var(--tun-dialog-padding);
  padding-bottom: max(var(--tun-dialog-padding), env(safe-area-inset-bottom));
  overflow-y: auto;
  overscroll-behavior: contain;
  border: 0;
  border-radius: var(--radius-xl) var(--radius-xl) 0 0;
  background-color: var(--popover);
  color: var(--popover-foreground);
  font-size: var(--text-sm);
  line-height: var(--text-sm--line-height);
  box-shadow: 0 0 0 1px color-mix(in oklab, var(--foreground) 10%, transparent), var(--shadow-lg);
  /* Opening focuses the dialog itself; a ring around the whole of it would
     only be noise. */
  outline: none;
  opacity: 0;
  translate: 0 100%;
  transition-property: opacity, translate, scale, display, overlay;
  transition-duration: var(--duration);
  transition-timing-function: var(--ease);
  transition-behavior: allow-discrete;
  &[open] {
    display: flex;
    opacity: 1;
    translate: none;
    @starting-style { opacity: 0; translate: 0 100%; }
  }
  &[open], & > .tun-dialog-form {
    flex-direction: column;
    gap: calc(var(--spacing) * 6);
    min-height: 0;
  }
  & > .tun-dialog-form { display: flex; flex: 1; }
  /* The page behind: Basecoat's black at 10% is too faint on a dark page. */
  &::backdrop {
    background-color: light-dark(rgb(0 0 0 / 0.1), rgb(0 0 0 / 0.5));
    backdrop-filter: blur(4px);
    opacity: 0;
    transition-property: opacity, display, overlay;
    transition-duration: var(--duration);
    transition-behavior: allow-discrete;
  }
  &[open]::backdrop {
    opacity: 1;
    @starting-style { opacity: 0; }
  }

  & .tun-dialog-header {
    display: flex;
    flex-direction: column;
    gap: calc(var(--spacing) * 2);
    padding-inline-end: calc(var(--spacing) * 10);
  }
  & .tun-dialog-title {
    font-size: var(--text-base);
    line-height: var(--text-base--line-height);
    font-weight: var(--font-weight-medium);
    letter-spacing: normal;
  }
  & .tun-dialog-description { color: var(--muted-foreground); }
  /* The body scrolls when the dialog is taller than the screen; the inset
     keeps the focus rings of its fields from being cut off. */
  & .tun-dialog-body {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    margin: calc(var(--spacing) * -1);
    padding: var(--spacing);
    & > * + * { margin-top: calc(var(--spacing) * 3); }
  }
  & .tun-dialog-footer {
    display: flex;
    flex-direction: column-reverse;
    gap: calc(var(--spacing) * 2);
  }
  & .tun-dialog-close {
    position: absolute;
    top: calc(var(--spacing) * 4);
    right: calc(var(--spacing) * 4);
  }

  &:is([data-variant='confirm'], [data-variant='destructive']) {
    width: calc(100% - var(--spacing) * 8);
    max-width: 32rem;
    margin: auto;
    padding-bottom: var(--tun-dialog-padding);
    border-radius: var(--radius-xl);
    translate: none;
    scale: 0.95;
    &[open] {
      scale: none;
      @starting-style { opacity: 0; translate: none; scale: 0.95; }
    }
    & .tun-dialog-header {
      align-items: center;
      gap: calc(var(--spacing) * 1.5);
      padding-inline-end: 0;
      text-align: center;
    }
    & .tun-dialog-title { font-size: var(--text-lg); line-height: var(--text-lg--line-height); }
    & .tun-dialog-description { text-wrap: balance; }
  }
  & .tun-dialog-icon {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: calc(var(--spacing) * 12);
    height: calc(var(--spacing) * 12);
    margin-bottom: calc(var(--spacing) * 2);
    border-radius: var(--radius-lg);
    background-color: var(--muted);
    & .tun-icon:not([data-size]) {
      width: calc(var(--spacing) * 6);
      height: calc(var(--spacing) * 6);
    }
  }
  &[data-variant='destructive'] .tun-dialog-icon {
    background-color: var(--destructive-soft);
    color: var(--destructive);
  }

  @media (min-width: 40rem) {
    width: calc(100% - var(--spacing) * 8);
    max-width: 28rem;
    margin: auto;
    padding-bottom: var(--tun-dialog-padding);
    border-radius: var(--radius-xl);
    translate: none;
    scale: 0.95;
    &[open] {
      scale: none;
      @starting-style { opacity: 0; translate: none; scale: 0.95; }
    }
    & .tun-dialog-footer { flex-direction: row; justify-content: flex-end; }
    &:is([data-variant='confirm'], [data-variant='destructive']) {
      max-width: 32rem;
      & .tun-dialog-header { align-items: flex-start; text-align: start; }
      & .tun-dialog-description { text-wrap: pretty; }
      & .tun-dialog-header:has(.tun-dialog-icon) {
        display: grid;
        grid-template-columns: auto 1fr;
        column-gap: calc(var(--spacing) * 5);
        & .tun-dialog-icon { grid-row: span 2; margin-bottom: 0; }
        & > :not(.tun-dialog-icon) { grid-column: 2; }
      }
    }
  }
}")
  (:script "
// Invoker commands (command, commandfor) where the browser has none yet:
// the buttons that open and close a Tun dialog.
const invokers = 'commandForElement' in HTMLButtonElement.prototype;
const close = (dialog) => (dialog.requestClose ? dialog.requestClose() : dialog.close());

// A click on the backdrop closes a dismissible dialog.  The press must start
// there too, so selecting text in the dialog and letting go outside does not.
let pressed = null;
document.addEventListener('pointerdown', (event) => { pressed = event.target; });
const outside = (dialog, event) => {
  const box = dialog.getBoundingClientRect();
  return event.clientX < box.left || event.clientX > box.right
    || event.clientY < box.top || event.clientY > box.bottom;
};

document.addEventListener('click', (event) => {
  const dialog = event.target;
  if (dialog instanceof HTMLDialogElement && dialog.open && dialog === pressed
      && dialog.dataset.tunDialog === 'dismissible' && outside(dialog, event)) {
    close(dialog);
    return;
  }
  if (invokers) return;
  const button = event.target.closest('button[commandfor]');
  const target = button && document.getElementById(button.getAttribute('commandfor'));
  if (!target || !target.matches('[data-tun-dialog]')) return;
  const command = button.getAttribute('command');
  if (command === 'show-modal' && !target.open) target.showModal();
  else if (command === 'close') target.close(button.value);
  else if (command === 'request-close') close(target);
});

// A dialog with a shortcut opens on it from anywhere on the page:
// data-tun-dialog-shortcut holds keys such as '/' and 'Ctrl+K', apart by
// spaces.  Ctrl is Cmd on a Mac; a key without Ctrl is left to a field
// being typed in.
const pressedKey = (event, shortcut) => {
  const parts = shortcut.toLowerCase().split('+');
  const key = parts.pop();
  return event.key.toLowerCase() === key && !event.altKey
    && parts.includes('ctrl') === (event.ctrlKey || event.metaKey);
};
const typing = (target) => target instanceof Element
  && target.closest('input, textarea, select, [contenteditable]');
document.addEventListener('keydown', (event) => {
  if (event.defaultPrevented || event.repeat) return;
  for (const dialog of document.querySelectorAll('dialog[data-tun-dialog-shortcut]')) {
    const shortcut = dialog.dataset.tunDialogShortcut.split(' ')
      .find((each) => pressedKey(event, each));
    if (!shortcut || dialog.open || (!/^ctrl\+/i.test(shortcut) && typing(event.target))) continue;
    event.preventDefault();
    dialog.showModal();
    return;
  }
});")
  (:examples
   ("En oppgave i en dialog"
    (button (:variant :outline :icon :send
                      :attributes (list :command "show-modal" :commandfor "send-faktura"))
            "Send faktura")
    (dialog (:id "send-faktura"
                 :title "Send faktura 2024-117"
                 :description "Fakturaen sendes som PDF til kundens fakturaadresse."
                 :footer (list (button (:variant :outline
                                                 :attributes (list :command "close"
                                                                   :commandfor "send-faktura"))
                                       "Avbryt")
                               (button (:type "submit") "Send faktura"))
                 :action "/fakturaer/2024-117/send")
            `(:p "Til " (:strong "Bakeri Nordvik AS") ", faktura@example.no.")
            `(:p "Beløp 12 450 kr, forfall 14 dager etter sending.")))
   ("Bekreftelse før sletting"
    (button (:variant :destructive :icon :trash
                      :attributes (list :command "show-modal" :commandfor "slett-ordre"))
            "Slett ordre")
    (dialog (:id "slett-ordre"
                 :variant :destructive
                 :title "Slette ordre 1042?"
                 :description "Ordren og alle ordrelinjene slettes for godt. Dette kan ikke
angres."
                 :action "/ordre/1042/slett"
                 :footer (list (button (:variant :outline
                                                 :attributes (list :command "close"
                                                                   :commandfor "slett-ordre"))
                                       "Avbryt")
                               (button (:type "submit" :variant :destructive) "Slett ordren")))))
   ("Spørsmål uten fare"
    (button (:variant :secondary
                      :attributes (list :command "show-modal" :commandfor "fullfor-oppdrag"))
            "Fullfør oppdrag")
    (dialog (:id "fullfor-oppdrag"
                 :variant :confirm
                 :icon :circle-check
                 :title "Er du sikker?"
                 :description "Oppdraget merkes som fullført, og kunden får beskjed på e-post."
                 :footer (list (button (:variant :outline
                                                 :attributes (list :command "close"
                                                                   :commandfor "fullfor-oppdrag"))
                                       "Avbryt")
                               (button () "Fullfør")))))
   ("Søk fra hvor som helst, med / eller Ctrl+K"
    (button (:variant :outline :icon :search :shortcut "/"
                      :attributes (list :command "show-modal" :commandfor "sok"))
            "Søk")
    (dialog (:id "sok" :title "Søk" :shortcut '("/" "Ctrl+K")
                 :action "/sok" :method "get"
                 :footer (list (button (:type "submit") "Søk")))
            (text-input (:label "Søk etter saker, kunder og personer" :name "q" :type :search
                                :attributes (list :autofocus t)))))
   ("Langt innhold ruller inne i dialogen"
    (button (:variant :ghost
                      :attributes (list :command "show-modal" :commandfor "vilkar"))
            "Les vilkårene")
    (dialog (:id "vilkar"
                 :title "Vilkår for oppdrag"
                 :description "Gjelder alle oppdrag bestilt etter 1. januar 2026."
                 :footer (list (button (:attributes (list :command "close" :commandfor "vilkar"))
                                       "Jeg har lest vilkårene")))
            (loop for (heading text)
                  in '(("Bestilling" "Et oppdrag er bindende når kunden har godtatt tilbudet
skriftlig, også på e-post eller SMS.")
                       ("Pris" "Prisen i tilbudet gjelder i 30 dager. Arbeid utover det som er
beskrevet, faktureres etter medgått tid med 850 kr per time eksklusive merverdiavgift.")
                       ("Avbestilling" "Kunden kan avbestille kostnadsfritt inntil sju dager
før oppstart. Senere avbestilling faktureres med 25 prosent av avtalt pris.")
                       ("Betaling" "Betalingsfristen er 14 dager. Ved forsinket betaling
beregnes forsinkelsesrente etter forsinkelsesrenteloven.")
                       ("Reklamasjon" "Mangler meldes skriftlig innen rimelig tid etter at de
ble oppdaget, og senest fem år etter overtakelse.")
                       ("Ansvar" "Vi er ansvarlige for skade vi påfører kundens eiendom
under arbeidet, begrenset til oppdragets verdi. Vi er ikke ansvarlige for indirekte tap.")
                       ("Personopplysninger" "Vi lagrer navn, adresse og telefonnummer så
lenge kundeforholdet varer, og deretter så lenge bokføringsloven krever.")
                       ("Tvister" "Partene skal først forsøke å løse uenighet ved
forhandlinger. Verneting er tingretten der oppdraget ble utført."))
                  collect `(:p (:strong ,heading ". ") ,text)))))
  (unless (and id title)
    (error "A dialog needs :id, which its buttons name, and :title"))
  (check-type variant (member :default :confirm :destructive))
  (let* ((asking (member variant '(:confirm :destructive)))
         (icon (or icon (when (eq variant :destructive) :triangle-alert)))
         (title-id (format nil "~a-title" id))
         (description-id (when description (format nil "~a-description" id)))
         (content
          `((:header (:@ :class "tun-dialog-header")
                     ,@(when icon
                         `((:div (:@ :class "tun-dialog-icon") ,(icon* (list :name icon)))))
                     (:h2 (:@ :class "tun-dialog-title" :id ,title-id) ,title)
                     ,@(when description
                         `((:p (:@ :class "tun-dialog-description" :id ,description-id)
                               ,description))))
            ,@(when children `((:div (:@ :class "tun-dialog-body") ,@children)))
            ,@(when footer `((:footer (:@ :class "tun-dialog-footer") ,@footer)))
            ,@(unless asking
                `((:div (:@ :class "tun-dialog-close")
                        ,(button (:variant :ghost :size :icon-sm :label "Lukk"
                                           :attributes (list :command "close" :commandfor id))
                                 (icon (:name :x)))))))))
    `(:dialog ,(attrs (list :class "tun-dialog" :id id :data-variant (option-string variant)
                            :role (when asking "alertdialog")
                            :aria-labelledby title-id :aria-describedby description-id
                            :data-tun-dialog (if asking "confirm" "dismissible")
                            :data-tun-dialog-shortcut (and shortcut
                                                           (format nil "~{~a~^ ~}"
                                                                   (if (listp shortcut)
                                                                       shortcut
                                                                       (list shortcut)))))
                      attributes)
              ,@(if action
                    `((:form ,(attrs (list :class "tun-dialog-form" :method method :action action
                                           :enctype (when (holds-file-input-p content)
                                                      "multipart/form-data")))
                             ,@content))
                    content))))

(defun holds-file-input-p (markup)
  "Whether MARKUP, a node or a list of them, holds an <input type=\"file\"> at
any depth, so the form around it must post files (spec/files.md 6.4). Markup
inside a raw HTML string is not looked into."
  (and (consp markup)
       (or (and (eq (first markup) :input)
                (consp (second markup))
                (eq (first (second markup)) :@)
                (equal (getf (rest (second markup)) :type) "file"))
           (some #'holds-file-input-p markup))))

;;; ------------------------------------------------------------------
;;; dropdown-menu

(defun dropdown-menu-item (&key label href icon shortcut variant disabled attributes)
  (unless label (error "A menu item needs :label"))
  `(,(if href :a :button)
     ,(attrs (list :class "tun-dropdown-menu-item" :role "menuitem"
                   :data-variant (option-string variant))
             (if href
                 (list :href (unless disabled href) :aria-disabled (when disabled "true"))
                 (list :type "button" :disabled disabled))
             attributes)
     ,@(when icon (list (icon* (list :name icon))))
     (:span (:@ :class "tun-dropdown-menu-text") ,label)
     ,@(when shortcut `((:kbd (:@ :class "tun-dropdown-menu-shortcut") ,shortcut)))))

(defun dropdown-menu-entry (entry)
  "The markup of one entry in a dropdown menu's :ITEMS: :SEPARATOR, a group
(:GROUP HEADING :ITEMS (ITEM...)) or an item (:LABEL ... )."
  (cond ((eq entry :separator)
         '(:div (:@ :class "tun-dropdown-menu-separator" :role "separator")))
        ((getf entry :group)
         (let ((heading-id (element-id "tun-dropdown-menu-heading")))
           `(:div (:@ :class "tun-dropdown-menu-group" :role "group"
                      :aria-labelledby ,heading-id)
                  (:div (:@ :class "tun-dropdown-menu-heading" :id ,heading-id
                            :role "presentation")
                        ,(getf entry :group))
                  ,@(mapcar #'dropdown-menu-entry (getf entry :items)))))
        (t (apply #'dropdown-menu-item entry))))

(define-component dropdown-menu ((&key label items (variant :outline) (size :default) icon
                                       (icon-end :chevron-down) (align :start) id attributes))
  (:group "Interaksjon")
  (:doc "En knapp som åpner en liste med handlinger, for valg som ikke får plass som egne
knapper. LABEL er knappens tekst; med en ikonstørrelse (:size :icon) vises bare ICON, og LABEL
blir knappens navn for skjermlesere. Hvert punkt i ITEMS er (:label :href :icon :shortcut
:variant :disabled :attributes), :separator eller (:group OVERSKRIFT :items (...)).")
  (:source "Basecoat dropdown menu (Vega), on the Popover API")
  (:css "
.tun-dropdown-menu {
  display: inline-flex;
  & .tun-dropdown-menu-content {
    min-width: 8rem;
    width: max-content;
    max-width: min(20rem, calc(100vw - var(--spacing) * 4));
    max-height: min(24rem, calc(100dvh - var(--spacing) * 4));
    margin: auto;
    padding: var(--spacing);
    overflow-x: hidden;
    overflow-y: auto;
    overscroll-behavior: contain;
    border: 0;
    border-radius: var(--radius-md);
    background-color: var(--popover);
    color: var(--popover-foreground);
    box-shadow: 0 0 0 1px color-mix(in oklab, var(--foreground) 10%, transparent),
      var(--shadow-md);
    outline: none;
    opacity: 0;
    scale: 0.95;
    transition-property: opacity, scale, display, overlay;
    transition-duration: var(--duration-fast);
    transition-timing-function: var(--ease);
    transition-behavior: allow-discrete;
    &:popover-open {
      opacity: 1;
      scale: none;
      @starting-style { opacity: 0; scale: 0.95; }
    }
  }
  /* Under its button where the browser can anchor it; the script places it
     elsewhere, and without either the browser centres it on the screen. */
  @supports (anchor-scope: all) and (position-try-fallbacks: flip-block) {
    anchor-scope: --tun-dropdown-menu;
    & > .tun-button { anchor-name: --tun-dropdown-menu; }
    & .tun-dropdown-menu-content {
      position-anchor: --tun-dropdown-menu;
      position-area: block-end span-inline-end;
      position-try-fallbacks: flip-inline, flip-block, flip-block flip-inline;
      inset: auto;
      margin: var(--spacing) 0;
      min-width: max(8rem, anchor-size(width));
      transform-origin: top left;
    }
    &[data-align='end'] .tun-dropdown-menu-content {
      position-area: block-end span-inline-start;
      transform-origin: top right;
    }
  }

  & .tun-dropdown-menu-item {
    display: flex;
    width: 100%;
    min-height: var(--control-height-sm);
    align-items: center;
    gap: calc(var(--spacing) * 2);
    padding: calc(var(--spacing) * 1.5) calc(var(--spacing) * 2);
    border-radius: var(--radius-sm);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    text-align: start;
    text-decoration: none;
    user-select: none;
    outline: none;
    &:focus { background-color: var(--accent); color: var(--accent-foreground); }
    @media (hover: hover) {
      &:hover { background-color: var(--accent); color: var(--accent-foreground); }
    }
    &:disabled, &[aria-disabled='true'] { pointer-events: none; opacity: 0.5; }
    & .tun-icon:not([data-size]) {
      width: calc(var(--spacing) * 4);
      height: calc(var(--spacing) * 4);
      color: var(--muted-foreground);
    }
    &[data-variant='destructive'] {
      color: var(--destructive);
      & .tun-icon { color: var(--destructive); }
      &:focus {
        background-color: light-dark(color-mix(in oklab, var(--destructive) 10%, transparent),
                                     color-mix(in oklab, var(--destructive) 20%, transparent));
        color: var(--destructive);
      }
      @media (hover: hover) {
        &:hover {
          background-color: light-dark(color-mix(in oklab, var(--destructive) 10%, transparent),
                                       color-mix(in oklab, var(--destructive) 20%, transparent));
        }
      }
    }
    @media (pointer: coarse) { min-height: var(--control-height); }
  }
  & .tun-dropdown-menu-text { flex: 1; min-width: 0; }
  & .tun-dropdown-menu-shortcut {
    margin-inline-start: auto;
    padding-inline-start: calc(var(--spacing) * 4);
    color: var(--muted-foreground);
    font-family: var(--font-sans);
    font-size: var(--text-xs);
    letter-spacing: 0.1em;
  }
  & .tun-dropdown-menu-heading {
    padding: calc(var(--spacing) * 1.5) calc(var(--spacing) * 2);
    color: var(--muted-foreground);
    font-size: var(--text-xs);
    line-height: var(--text-xs--line-height);
    font-weight: var(--font-weight-medium);
  }
  & .tun-dropdown-menu-separator {
    height: 1px;
    margin: var(--spacing) calc(var(--spacing) * -1);
    background-color: var(--border);
  }
}")
  (:script "
// The menu button pattern on top of the popover: aria-expanded, focus into
// the menu and back, arrow keys, Home and End, typing a letter, Tab.
const anchored = CSS.supports('anchor-scope: all')
  && CSS.supports('position-try-fallbacks: flip-block');
const menuSelector = '[data-tun-dropdown-menu] > [popover]';
const triggerOf = (menu) => menu.parentElement.querySelector(':scope > [popovertarget]');
const itemsOf = (menu) => [...menu.querySelectorAll('[role=menuitem]')]
  .filter((item) => !item.matches(':disabled, [aria-disabled=true]'));
let focusOnOpen = null;

// Where the browser cannot anchor the menu: under its button, or above it
// when there is more room there, and always inside the window.
const place = (menu) => {
  const edge = 8;
  const gap = 4;
  const button = triggerOf(menu).getBoundingClientRect();
  Object.assign(menu.style, { position: 'fixed', inset: 'auto', margin: '0', maxHeight: '' });
  menu.style.minWidth = `${Math.max(button.width, 128)}px`;
  const width = menu.offsetWidth;
  const viewport = document.documentElement.clientWidth;
  const below = window.innerHeight - button.bottom - gap - edge;
  const above = button.top - gap - edge;
  const atEnd = menu.parentElement.dataset.align === 'end';
  const left = atEnd ? button.right - width : button.left;
  menu.style.left = `${Math.max(edge, Math.min(left, viewport - width - edge))}px`;
  if (menu.offsetHeight <= below || below >= above) {
    menu.style.top = `${button.bottom + gap}px`;
    menu.style.maxHeight = `${below}px`;
  } else {
    menu.style.maxHeight = `${above}px`;
    menu.style.top = `${button.top - gap - menu.offsetHeight}px`;
  }
};
const placeOpenMenus = () => {
  if (anchored) return;
  for (const menu of document.querySelectorAll(`${menuSelector}:popover-open`)) place(menu);
};
window.addEventListener('resize', placeOpenMenus);
document.addEventListener('scroll', placeOpenMenus, true);

const syncExpanded = (root) => {
  for (const menu of root.querySelectorAll(menuSelector))
    triggerOf(menu)?.setAttribute('aria-expanded', String(menu.matches(':popover-open')));
};
tunOnContent(syncExpanded);

document.addEventListener('toggle', (event) => {
  const menu = event.target;
  if (!(menu instanceof Element) || !menu.matches(menuSelector)) return;
  const trigger = triggerOf(menu);
  const open = event.newState === 'open';
  trigger.setAttribute('aria-expanded', String(open));
  if (open) {
    if (!anchored) place(menu);
    const items = itemsOf(menu);
    const first = { first: items[0], last: items[items.length - 1] }[focusOnOpen];
    (first || menu).focus({ preventScroll: true });
    focusOnOpen = null;
  } else if (menu.contains(document.activeElement) || document.activeElement === document.body) {
    trigger.focus({ preventScroll: true });
  }
}, true);

const closeMenu = (menu) => {
  if (menu.matches(':popover-open')) menu.hidePopover();
  triggerOf(menu).focus({ preventScroll: true });
};

document.addEventListener('click', (event) => {
  const trigger = event.target.closest('[data-tun-dropdown-menu] > [popovertarget]');
  // A click from the keyboard (Enter, Space) has no pointer position.
  if (trigger) focusOnOpen = event.detail === 0 ? 'first' : null;
  const item = event.target.closest(`${menuSelector} [role=menuitem]`);
  if (item) closeMenu(item.closest(menuSelector));
});

const move = (items, index) => items[(index + items.length) % items.length]?.focus();

document.addEventListener('keydown', (event) => {
  if (!(event.target instanceof Element)) return;
  const trigger = event.target.closest('[data-tun-dropdown-menu] > [popovertarget]');
  if (trigger && (event.key === 'ArrowDown' || event.key === 'ArrowUp')) {
    const menu = document.getElementById(trigger.getAttribute('popovertarget'));
    event.preventDefault();
    if (menu.matches(':popover-open')) {
      const items = itemsOf(menu);
      move(items, event.key === 'ArrowDown' ? 0 : -1);
    } else {
      focusOnOpen = event.key === 'ArrowDown' ? 'first' : 'last';
      menu.showPopover({ source: trigger });
    }
    return;
  }
  const menu = event.target.closest(`${menuSelector}:popover-open`);
  if (!menu || event.altKey || event.ctrlKey || event.metaKey) return;
  const items = itemsOf(menu);
  const index = items.indexOf(document.activeElement);
  if (event.key === 'ArrowDown') move(items, index + 1);
  else if (event.key === 'ArrowUp') move(items, index === -1 ? -1 : index - 1);
  else if (event.key === 'Home') move(items, 0);
  else if (event.key === 'End') move(items, -1);
  else if (event.key === 'Tab') {
    // Close and let Tab move on from the button, as if the menu were not there.
    menu.hidePopover();
    triggerOf(menu).focus({ preventScroll: true });
    return;
  } else if (event.key === ' ' && event.target.matches('a[role=menuitem]')) {
    event.target.click();
  } else if (event.key.length === 1 && event.key !== ' ') {
    const letter = event.key.toLocaleLowerCase();
    const after = [...items.slice(index + 1), ...items.slice(0, index + 1)];
    after.find((item) => item.textContent.trim().toLocaleLowerCase().startsWith(letter))?.focus();
  } else return;
  event.preventDefault();
});

// The pointer moves the highlight, as the arrow keys do; leaving the menu
// takes it away.
document.addEventListener('pointermove', (event) => {
  if (event.pointerType !== 'mouse' || !(event.target instanceof Element)) return;
  const item = event.target.closest(`${menuSelector} [role=menuitem]`);
  if (item && item !== document.activeElement && !item.matches(':disabled, [aria-disabled=true]'))
    item.focus({ preventScroll: true });
});
document.addEventListener('pointerout', (event) => {
  if (event.pointerType !== 'mouse' || !(event.target instanceof Element)) return;
  const menu = event.target.closest(menuSelector);
  if (menu && !menu.contains(event.relatedTarget) && menu.contains(document.activeElement))
    menu.focus({ preventScroll: true });
});")
  (:examples
   ("Handlinger for en ordre"
    (dropdown-menu (:label "Handlinger"
                           :items (list (list :group "Ordre 1042"
                                              :items (list (list :label "Rediger" :icon :pencil
                                                                 :href "/ordre/1042/rediger"
                                                                 :shortcut "E")
                                                           (list :label "Dupliser" :icon :copy
                                                                 :shortcut "D")
                                                           (list :label "Last ned PDF"
                                                                 :icon :download
                                                                 :href "/ordre/1042.pdf")))
                                        :separator
                                        (list :label "Send til kunden" :icon :send)
                                        :separator
                                        (list :label "Slett ordre" :icon :trash
                                              :variant :destructive
                                              :attributes (list :command "show-modal"
                                                                :commandfor "meny-slett-ordre")))))
    (dialog (:id "meny-slett-ordre"
                 :variant :destructive
                 :title "Slette ordre 1042?"
                 :description "Ordren og alle ordrelinjene slettes for godt."
                 :action "/ordre/1042/slett"
                 :footer (list (button (:variant :outline
                                                 :attributes (list :command "close"
                                                                   :commandfor "meny-slett-ordre"))
                                       "Avbryt")
                               (button (:type "submit" :variant :destructive) "Slett ordren")))))
   ("Bare ikon, i enden av en rad"
    (dropdown-menu (:label "Flere valg for Bakeri Hansen AS" :size :icon :variant :ghost
                           :icon :ellipsis :align :end
                           :items (list (list :label "Vis kunden" :icon :user :href "/kunder/17")
                                        (list :label "Ny ordre" :icon :plus
                                              :href "/kunder/17/ordre/ny")
                                        (list :label "Send påminnelse om ubetalt faktura"
                                              :icon :mail)
                                        :separator
                                        (list :label "Slå sammen med en annen kunde" :icon :users
                                              :disabled t)))))
   ("Konto"
    (dropdown-menu (:label "Kari Nordmann" :variant :ghost :icon :user
                           :items (list (list :group "Kari Nordmann, Rørlegger Nordmann AS"
                                              :items (list (list :label "Profil" :icon :user
                                                                 :href "/profil")
                                                           (list :label "Innstillinger"
                                                                 :icon :settings
                                                                 :href "/innstillinger")))
                                        :separator
                                        (list :label "Logg ut" :icon :log-out
                                              :attributes (list :type "submit"
                                                                :form "logg-ut")))))
    '(:form (:@ :id "logg-ut" :method "post" :action "/logout"))))
  (unless (and label items)
    (error "A dropdown menu needs :label, its button's text or name, and :items"))
  (let* ((base (or id (element-id "tun-dropdown-menu")))
         (trigger-id (format nil "~a-trigger" base))
         (menu-id (format nil "~a-menu" base))
         (icon-only (member size '(:icon :icon-xs :icon-sm :icon-lg))))
    `(:div ,(attrs (list :class "tun-dropdown-menu" :id id
                         :data-align (unless (eq align :start) (option-string align))
                         :data-tun-dropdown-menu t)
                   attributes)
           ,(button* (list :variant variant :size size :id trigger-id
                           :label (when icon-only label)
                           :icon (unless icon-only icon)
                           :icon-end (unless icon-only icon-end)
                           :attributes (list :popovertarget menu-id :aria-haspopup "menu"
                                             :aria-controls menu-id))
                     (if icon-only (icon* (list :name (or icon :ellipsis))) label))
           (:div (:@ :class "tun-dropdown-menu-content" :id ,menu-id :popover t :role "menu"
                     :aria-labelledby ,trigger-id :tabindex "-1")
                 ,@(mapcar #'dropdown-menu-entry items)))))

;;; ------------------------------------------------------------------
;;; tooltip

(define-component tooltip ((&key text (side :top) id attributes) &rest children)
  (:group "Interaksjon")
  (:doc "En kort forklaring som vises når pekeren er over eller tastaturet er på en knapp,
gjerne en knapp med bare ikon. Den vises ikke på berøringsskjermer, så den må aldri være det
eneste stedet viktig informasjon står. Teksten leses opp i tillegg til knappens navn, så den
bør utfylle navnet, ikke gjenta det.")
  (:source "Basecoat tooltip (Vega)")
  (:css "
.tun-tooltip {
  position: relative;
  display: inline-flex;
  & .tun-tooltip-content {
    position: absolute;
    z-index: var(--z-dropdown);
    bottom: 100%;
    left: 50%;
    width: max-content;
    max-width: min(16rem, calc(100vw - var(--spacing) * 4));
    margin-bottom: calc(var(--spacing) * 1.5);
    padding: calc(var(--spacing) * 1.5) calc(var(--spacing) * 3);
    border-radius: var(--radius-md);
    background-color: var(--foreground);
    color: var(--background);
    font-size: var(--text-xs);
    line-height: var(--text-xs--line-height);
    font-weight: var(--font-weight-normal);
    text-align: start;
    white-space: normal;
    visibility: hidden;
    opacity: 0;
    translate: -50% 0;
    scale: 0.95;
    transition-property: opacity, scale, visibility;
    transition-duration: var(--duration-fast);
    transition-timing-function: var(--ease);
  }
  &[data-side='bottom'] .tun-tooltip-content {
    top: 100%;
    bottom: auto;
    margin: calc(var(--spacing) * 1.5) 0 0;
  }
  &:is([data-side='left'], [data-side='right']) .tun-tooltip-content {
    top: 50%;
    bottom: auto;
    margin: 0;
    translate: 0 -50%;
  }
  &[data-side='left'] .tun-tooltip-content {
    right: 100%;
    left: auto;
    margin-right: calc(var(--spacing) * 1.5);
  }
  &[data-side='right'] .tun-tooltip-content {
    left: 100%;
    margin-left: calc(var(--spacing) * 1.5);
  }
  /* Anchored where the browser can: fixed to the window, so it can never
     widen the page, and turned to another side when it does not fit. */
  @supports (anchor-scope: all) and (position-try-fallbacks: flip-block) {
    anchor-scope: --tun-tooltip;
    & > :first-child { anchor-name: --tun-tooltip; }
    &[data-side] .tun-tooltip-content {
      position: fixed;
      position-anchor: --tun-tooltip;
      inset: auto;
      margin: calc(var(--spacing) * 1.5);
      translate: none;
    }
    &[data-side='top'] .tun-tooltip-content {
      position-area: top;
      position-try-fallbacks: top span-right, top span-left, flip-block,
        bottom span-right, bottom span-left;
    }
    &[data-side='bottom'] .tun-tooltip-content {
      position-area: bottom;
      position-try-fallbacks: bottom span-right, bottom span-left, flip-block,
        top span-right, top span-left;
    }
    &[data-side='left'] .tun-tooltip-content {
      position-area: left;
      position-try-fallbacks: flip-inline, top, bottom;
    }
    &[data-side='right'] .tun-tooltip-content {
      position-area: right;
      position-try-fallbacks: flip-inline, top, bottom;
    }
  }
  /* Hover only where there is a pointer that hovers: on a touch screen a tap
     would leave it standing. */
  @media (hover: hover) {
    &:not([data-dismissed]):hover .tun-tooltip-content {
      visibility: visible;
      opacity: 1;
      scale: none;
    }
  }
  &:not([data-dismissed]):has(:focus-visible) .tun-tooltip-content {
    visibility: visible;
    opacity: 1;
    scale: none;
  }
}")
  (:script "
// Escape hides a tooltip without moving focus or the pointer (WCAG 1.4.13),
// and so does pressing the button; leaving it brings the tooltip back.
const shown = () => [...document.querySelectorAll('[data-tun-tooltip]:not([data-dismissed])')]
  .filter((tooltip) => tooltip.matches(':hover') || tooltip.matches(':has(:focus-visible)'));

document.addEventListener('keydown', (event) => {
  if (event.key !== 'Escape') return;
  for (const tooltip of shown()) {
    tooltip.dataset.dismissed = '';
    // Escape on the focused button only hides its tooltip, not the dialog
    // or menu around it.
    if (tooltip.contains(document.activeElement)) event.preventDefault();
  }
}, true);

document.addEventListener('pointerdown', (event) => {
  const tooltip = event.target instanceof Element && event.target.closest('[data-tun-tooltip]');
  if (tooltip) tooltip.dataset.dismissed = '';
});

const reset = (event) => {
  const tooltip = event.target instanceof Element
    && event.target.closest('[data-tun-tooltip][data-dismissed]');
  if (!tooltip || tooltip.contains(event.relatedTarget)) return;
  const hovered = event.type === 'focusout' && tooltip.matches(':hover');
  const focused = event.type === 'mouseout' && tooltip.contains(document.activeElement);
  if (!hovered && !focused) delete tooltip.dataset.dismissed;
};
document.addEventListener('mouseout', reset);
document.addEventListener('focusout', reset);")
  (:examples
   ("Ikonknapper"
    (tooltip (:text "Kopier lenken til fakturaen")
             (button (:size :icon :variant :outline :label "Kopier lenke") (icon (:name :copy))))
    (tooltip (:text "Last ned som PDF")
             (button (:size :icon :variant :outline :label "Last ned") (icon (:name :download))))
    (tooltip (:text "Skriv ut pakkseddel for alle ordre som skal sendes i dag")
             (button (:size :icon :variant :outline :label "Pakkseddel")
                     (icon (:name :file-text)))))
   ("Sider"
    (tooltip (:text "Over" :side :top)
             (button (:variant :outline) "Over"))
    (tooltip (:text "Under" :side :bottom)
             (button (:variant :outline) "Under"))
    (tooltip (:text "Til venstre" :side :left)
             (button (:variant :outline) "Venstre"))
    (tooltip (:text "Til høyre" :side :right)
             (button (:variant :outline) "Høyre"))))
  (unless (and text (= 1 (length children)))
    (error "A tooltip needs :text and exactly one element to explain, such as a button"))
  (check-type side (member :top :bottom :left :right))
  (let* ((content-id (element-id "tun-tooltip"))
         (trigger (first children))
         (described (getf (element-attributes trigger) :aria-describedby)))
    `(:span ,(attrs (list :class "tun-tooltip" :id id :data-side (option-string side)
                          :data-tun-tooltip t)
                    attributes)
            ,(add-element-attributes trigger
                                     (list :aria-describedby (join-ids described content-id)))
            (:span (:@ :class "tun-tooltip-content" :id ,content-id :role "tooltip") ,text))))

;;; ------------------------------------------------------------------
;;; accordion

(define-component accordion ((&key items exclusive name id attributes))
  (:group "Interaksjon")
  (:doc "Overskrifter som folder ut innholdet sitt, for tekst man sjelden trenger å se alt av på
en gang, som vanlige spørsmål. Hvert punkt i ITEMS er (:title :content :open). Med EXCLUSIVE er
bare ett punkt åpent om gangen. Virker uten JavaScript.")
  (:source "Basecoat accordion (Vega), on <details>")
  (:css "
.tun-accordion {
  display: flex;
  width: 100%;
  flex-direction: column;
  interpolate-size: allow-keywords;
  & .tun-accordion-item:not(:last-child) { border-bottom: 1px solid var(--border); }
  & .tun-accordion-trigger {
    display: flex;
    min-height: var(--control-height);
    align-items: flex-start;
    justify-content: space-between;
    gap: calc(var(--spacing) * 4);
    /* Room inside the focus ring, without moving the text off its edge. */
    margin-inline: calc(var(--spacing) * -2);
    padding: calc(var(--spacing) * 4) calc(var(--spacing) * 2);
    border: 1px solid transparent;
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    font-weight: var(--font-weight-medium);
    text-align: start;
    list-style: none;
    cursor: pointer;
    outline: none;
    transition-property: box-shadow, border-color;
    transition-duration: var(--duration-fast);
    &::-webkit-details-marker { display: none; }
    &:focus-visible { border-color: var(--ring); box-shadow: var(--focus-ring); }
    @media (hover: hover) {
      &:hover .tun-accordion-title {
        text-decoration-line: underline;
        text-underline-offset: 4px;
      }
    }
    & .tun-icon {
      margin-top: calc(var(--spacing) * 0.5);
      color: var(--muted-foreground);
      transition: rotate var(--duration) var(--ease);
    }
  }
  & .tun-accordion-item[open] > .tun-accordion-trigger .tun-icon { rotate: 180deg; }
  & .tun-accordion-content {
    padding-bottom: calc(var(--spacing) * 4);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    & > * + * { margin-top: calc(var(--spacing) * 3); }
  }
  /* Opening slides where the browser can animate to height: auto; the
     motion tokens are zero under prefers-reduced-motion. */
  & .tun-accordion-item::details-content {
    block-size: 0;
    overflow: hidden;
    transition-property: block-size, content-visibility;
    transition-duration: var(--duration);
    transition-timing-function: var(--ease);
    transition-behavior: allow-discrete;
  }
  & .tun-accordion-item[open]::details-content { block-size: auto; }
}")
  (:examples
   (("Vanlige spørsmål, ett åpent om gangen" :layout :stack)
    (accordion (:items (list (list :title "Hvor lang er leveringstiden?"
                                   :open t
                                   :content "Varer på lager sendes samme dag når du
bestiller før klokken 14. Du får dem vanligvis innen to til fire virkedager.")
                             (list :title "Kan jeg endre en ordre etter at den er sendt?"
                                   :content "Nei, men du kan returnere varene innen 30
dager og legge inn en ny ordre.")
                             (list :title "Hvordan fungerer fakturering for bedrifter?"
                                   :content
                                   (list '(:p "Bedrifter får faktura med 14 dagers
betalingsfrist. Fakturaen sendes som EHF når vi har organisasjonsnummeret ditt.")
                                         '(:p "Privatpersoner betaler med kort eller
Vipps når de bestiller."))))
                       :exclusive t)))
   (("Flere åpne samtidig" :layout :stack)
    (accordion (:items (list (list :title "Kontaktinformasjon"
                                   :open t
                                   :content "Bakeri Hansen AS, Storgata 12, 0155 Oslo.")
                             (list :title "Betalingsbetingelser"
                                   :open t
                                   :content "14 dager netto. Purregebyr 35 kr.")
                             (list :title "Merknader fra montøren om tilkomst, nøkler og
parkering ved oppdraget i bakgården"
                                   :content "Nøkkel hentes i butikken. Parker i
Dronningens gate."))))))
  (unless items (error "An accordion needs :items"))
  (let ((name (or name (when exclusive (or id (element-id "tun-accordion"))))))
    `(:div ,(attrs (list :class "tun-accordion" :id id) attributes)
           ,@(loop for item in items
                   collect (destructuring-bind (&key title content open) item
                             (unless title (error "An accordion item needs :title"))
                             `(:details (:@ :class "tun-accordion-item" :name ,name :open ,open)
                                        (:summary (:@ :class "tun-accordion-trigger")
                                                  (:span (:@ :class "tun-accordion-title")
                                                         ,title)
                                                  ,(icon (:name :chevron-down)))
                                        (:div (:@ :class "tun-accordion-content")
                                              ,content)))))))

;;; ------------------------------------------------------------------
;;; tabs

(defun tab-items (items base)
  "ITEMS with the ids of their tab and panel and which one is selected:
(TAB-ID PANEL-ID SELECTED-P . ITEM) for each.  The first is selected when
none says :selected."
  (let ((selected (or (position-if (lambda (item) (getf item :selected)) items) 0)))
    (loop for item in items
          for index from 0
          collect (list* (format nil "~a-tab-~d" base (1+ index))
                         (or (getf item :id) (format nil "~a-panel-~d" base (1+ index)))
                         (= index selected)
                         item))))

(defun tab-panels (label items variant heading-level id attributes)
  (let ((base (or id (element-id "tun-tabs")))
        (heading (heading-tag heading-level)))
    `(:div ,(attrs (list :class "tun-tabs" :id id :data-variant (option-string variant)
                         :data-tun-tabs t)
                   attributes)
           (:div (:@ :class "tun-tabs-list" :role "tablist" :aria-label ,label)
                 ,@(loop for (tab-id panel-id selected . item) in (tab-items items base)
                         collect `(:button (:@ :class "tun-tabs-tab" :type "button" :role "tab"
                                               :id ,tab-id :aria-controls ,panel-id
                                               :aria-selected ,(if selected "true" "false")
                                               :tabindex ,(if selected "0" "-1"))
                                           ,@(when (getf item :icon)
                                               (list (icon* (list :name (getf item :icon)))))
                                           ,(getf item :label))))
           ,@(loop for (tab-id panel-id selected . item) in (tab-items items base)
                   collect `(:section (:@ :class "tun-tabs-panel" :role "tabpanel"
                                          :id ,panel-id :aria-labelledby ,tab-id :tabindex "0"
                                          :data-selected ,(if selected "true" "false"))
                                      (,heading (:@ :class "tun-tabs-heading")
                                                ,(getf item :label))
                                      ,(getf item :content))))))

(defun tab-links (label items variant id attributes)
  `(:nav ,(attrs (list :class "tun-tabs" :id id :data-variant (option-string variant)
                       :aria-label label)
                 attributes)
         (:ul (:@ :class "tun-tabs-list")
              ,@(loop for item in items
                      collect `(:li (:a (:@ :class "tun-tabs-tab" :href ,(getf item :href)
                                            :aria-current ,(when (getf item :current) "page"))
                                        ,@(when (getf item :icon)
                                            (list (icon* (list :name (getf item :icon)))))
                                        ,(getf item :label)))))))

(define-component tabs ((&key label items (variant :default) (heading-level 2) id attributes))
  (:group "Interaksjon")
  (:doc "Faner som deler innholdet på én side i deler man ser én av om gangen. Hvert punkt i
ITEMS er (:label :content :icon :selected :id); uten JavaScript vises alle delene etter hverandre,
hver under sin overskrift. Er punktene lenker (:label :href :current), er fanene navigasjon
mellom egne sider. LABEL sier hva fanene gjelder.")
  (:source "Basecoat tabs (Vega); without JavaScript as GOV.UK tabs")
  (:css "
.tun-tabs {
  display: flex;
  min-width: 0;
  flex-direction: column;
  gap: calc(var(--spacing) * 2);
  & .tun-tabs-list {
    display: flex;
    width: fit-content;
    max-width: 100%;
    height: var(--control-height);
    align-items: center;
    padding: 3px;
    overflow-x: auto;
    border-radius: var(--radius-lg);
    background-color: var(--muted);
    color: var(--muted-foreground);
    scrollbar-width: none;
    & li { display: flex; height: 100%; flex: 1 0 auto; }
  }
  & .tun-tabs-tab {
    position: relative;
    display: inline-flex;
    height: 100%;
    flex: 1 0 auto;
    align-items: center;
    justify-content: center;
    gap: calc(var(--spacing) * 1.5);
    padding: var(--spacing) calc(var(--spacing) * 2);
    border: 1px solid transparent;
    border-radius: var(--radius-md);
    color: light-dark(color-mix(in oklab, var(--foreground) 60%, transparent),
                      var(--muted-foreground));
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    font-weight: var(--font-weight-medium);
    white-space: nowrap;
    text-decoration: none;
    outline: none;
    transition-property: color, background-color, box-shadow, border-color;
    transition-duration: var(--duration-fast);
    @media (hover: hover) { &:hover { color: var(--foreground); } }
    &:focus-visible { border-color: var(--ring); box-shadow: var(--focus-ring); }
    & .tun-icon:not([data-size]) {
      width: calc(var(--spacing) * 4);
      height: calc(var(--spacing) * 4);
    }
    &:has(> .tun-icon:first-child) { padding-inline-start: calc(var(--spacing) * 1.5); }
    &:is([aria-selected='true'], [aria-current='page']) {
      border-color: light-dark(transparent, var(--input));
      background-color: light-dark(var(--background),
                                   color-mix(in oklab, var(--input) 30%, transparent));
      color: var(--foreground);
      box-shadow: var(--shadow-sm);
    }
  }
  &[data-variant='line'] {
    & .tun-tabs-list {
      width: 100%;
      gap: var(--spacing);
      padding: 0;
      border-radius: 0;
      background-color: transparent;
      box-shadow: inset 0 -1px var(--border);
    }
    & .tun-tabs-tab {
      flex-grow: 0;
      border-radius: var(--radius-md) var(--radius-md) 0 0;
      &::after {
        content: '';
        position: absolute;
        inset: auto 0 -1px;
        height: 2px;
        background-color: var(--foreground);
        opacity: 0;
        transition: opacity var(--duration-fast);
      }
      &:is([aria-selected='true'], [aria-current='page']) {
        border-color: transparent;
        background-color: transparent;
        box-shadow: none;
        &::after { opacity: 1; }
      }
      &:focus-visible { box-shadow: inset var(--focus-ring); }
    }
  }
  & .tun-tabs-panel {
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    border-radius: var(--radius-sm);
    outline: none;
    /* The panel's text runs to its edge, so its ring stands off a little. */
    &:focus-visible { box-shadow: 0 0 0 4px var(--background), 0 0 0 6px var(--ring); }
    & > * + * { margin-top: calc(var(--spacing) * 3); }
  }
  & .tun-tabs-heading {
    font-size: var(--text-base);
    line-height: var(--text-base--line-height);
  }
  /* Without scripts the list cannot switch panels, so every panel shows
     under its own heading instead. */
  @media (scripting: none) {
    & > .tun-tabs-list[role='tablist'] { display: none; }
    & > .tun-tabs-panel + .tun-tabs-panel { margin-top: calc(var(--spacing) * 4); }
  }
  @media (scripting: enabled) {
    & > .tun-tabs-panel[data-selected='false'], & .tun-tabs-heading { display: none; }
  }
}")
  (:script "
// The ARIA tabs pattern: one tab in the Tab order, arrow keys move between
// tabs and select as they go.
const select = (tab, focus) => {
  for (const other of tab.closest('[role=tablist]').querySelectorAll('[role=tab]')) {
    const selected = other === tab;
    other.setAttribute('aria-selected', String(selected));
    other.tabIndex = selected ? 0 : -1;
    document.getElementById(other.getAttribute('aria-controls'))
      ?.setAttribute('data-selected', String(selected));
  }
  if (focus) tab.focus();
  tab.scrollIntoView({ block: 'nearest', inline: 'nearest' });
};

document.addEventListener('click', (event) => {
  const tab = event.target instanceof Element
    && event.target.closest('[data-tun-tabs] [role=tab]');
  if (tab && !tab.disabled) select(tab, false);
});

document.addEventListener('keydown', (event) => {
  const tab = event.target instanceof Element
    && event.target.closest('[data-tun-tabs] [role=tab]');
  if (!tab) return;
  const tabs = [...tab.closest('[role=tablist]').querySelectorAll('[role=tab]:not(:disabled)')];
  const index = tabs.indexOf(tab);
  const next = { ArrowRight: tabs[(index + 1) % tabs.length],
                 ArrowLeft: tabs[(index - 1 + tabs.length) % tabs.length],
                 Home: tabs[0], End: tabs[tabs.length - 1] }[event.key];
  if (!next) return;
  event.preventDefault();
  select(next, true);
});

// A link to a panel (#id) opens its tab.
const fromHash = () => {
  const id = decodeURIComponent(location.hash.slice(1));
  const tab = id && document.querySelector(
    `[data-tun-tabs] [role=tab][aria-controls='${CSS.escape(id)}']`);
  if (tab) select(tab, false);
};
document.addEventListener('DOMContentLoaded', fromHash);
window.addEventListener('hashchange', fromHash);")
  (:examples
   (("Faner på en side" :layout :stack)
    (tabs (:label "Ordre 1042"
                  :items (list (list :label "Detaljer"
                                     :content
                                     (list '(:p "Bestilt 3. oktober 2026 av Bakeri Hansen AS.")
                                           '(:p "Leveres til Storgata 12, 0155 Oslo.")))
                               (list :label "Ordrelinjer" :selected t
                                     :content (list '(:p "3 linjer, til sammen 12 450 kr.")
                                                    '(:ul (:li "Hvetemel 25 kg, 10 sekker")
                                                      (:li "Rugmel 25 kg, 4 sekker")
                                                      (:li "Frakt"))))
                               (list :label "Historikk"
                                     :content '(:p "Ordren ble opprettet av Kari Nordmann."))))))
   (("Strek, med ikoner og mange faner" :layout :stack)
    (tabs (:label "Kunde" :variant :line
                  :items (list (list :label "Oversikt" :icon :house
                                     :content '(:p "Bakeri Hansen AS har vært kunde siden 2019."))
                               (list :label "Ordre" :icon :package
                                     :content '(:p "12 ordre i år."))
                               (list :label "Fakturaer" :icon :receipt
                                     :content '(:p "2 ubetalte fakturaer, til sammen 18 900 kr."))
                               (list :label "Kontaktpersoner" :icon :users
                                     :content '(:p "Ola Hansen, daglig leder."))
                               (list :label "Notater" :icon :message-square
                                     :content '(:p "Leveres bakveien før klokken 7."))))))
   (("Lenker til egne sider" :layout :stack)
    (tabs (:label "Kunde" :variant :line
                  :items (list (list :label "Oversikt" :href "/kunder/17")
                               (list :label "Ordre" :href "/kunder/17/ordre" :current t)
                               (list :label "Fakturaer" :href "/kunder/17/fakturaer")
                               (list :label "Kontaktpersoner" :href "/kunder/17/kontakter"))))
    (tabs (:label "Periode"
                  :items (list (list :label "I dag" :href "/salg?periode=dag" :current t)
                               (list :label "Denne uken" :href "/salg?periode=uke")
                               (list :label "Denne måneden" :href "/salg?periode=maned"))))))
  (unless (and label items)
    (error "Tabs need :label, what they are about, and :items"))
  (check-type variant (member :default :line))
  (let ((links (count-if (lambda (item) (getf item :href)) items)))
    (cond ((= links (length items)) (tab-links label items variant id attributes))
          ((zerop links) (tab-panels label items variant heading-level id attributes))
          (t (error "Tabs are either all links (:href) or all panels (:content)")))))
