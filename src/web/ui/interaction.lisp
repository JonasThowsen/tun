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

(define-component dialog ((&key id title description (variant :default) (size :default) icon
                                footer action (method "post") shortcut attributes)
                          &rest children)
  (:group "Interaction")
  (:doc "A window over the page for a short task or a question that must be answered before
going on. The button that opens it has :attributes (list :command \"show-modal\" :commandfor
ID); «Cancel» has :command \"close\". The variants confirm and destructive are for «Are you
sure?»: they do not close on a click outside and have no close button, only the choices in
FOOTER. With :shortcut (\"/\", \"Ctrl+K\" or a list of them) the dialog opens on that key from
anywhere on the page; Ctrl is Cmd on a Mac, and a key without Ctrl does nothing while typing
in a field. :size :large gives it a fixed box from 40rem, for content that changes as one types,
such as a search's results.")
  (:source "Basecoat dialog and alert dialog (Vega)")
  (:css "
.tun-dialog {
  --tun-dialog-padding: calc(var(--spacing) * 4);
  /* A strip of the page shows above the highest dialog, so it reads as
     over the page. */
  --tun-dialog-strip: calc(var(--spacing) * 8);
  /* The window less what a keyboard covers (the script's
     --tun-visual-top and --tun-visual-bottom) and the strip. */
  --tun-dialog-max-height: calc(100% - var(--tun-visual-top, 0px)
                                - var(--tun-visual-bottom, 0px) - var(--tun-dialog-strip));
  /* On a phone the dialog is a sheet along the bottom edge of the part of
     the window the keyboard leaves. */
  inset-block: var(--tun-visual-top, 0px) var(--tun-visual-bottom, 0px);
  width: 100%;
  max-width: 100%;
  max-height: var(--tun-dialog-max-height);
  margin: auto 0 0;
  padding: var(--tun-dialog-padding);
  padding-bottom: max(var(--tun-dialog-padding), env(safe-area-inset-bottom));
  overflow-y: auto;
  overscroll-behavior: contain;
  border: 0;
  border-radius: var(--radius-xl) var(--radius-xl) 0 0;
  background-color: var(--popover);
  color: var(--popover-foreground);
  font-size: var(--text-running);
  line-height: var(--text-running--line-height);
  box-shadow: 0 0 0 1px var(--border), var(--shadow-lg);
  /* Opening focuses a control in it; a ring around the whole of it would
     only be noise. */
  outline: none;
  /* Closed, and leaving: below the window.  A transition takes the
     duration of the state it goes to, so leaving is --duration-close. */
  translate: 0 100%;
  transition-property: opacity, translate, display, overlay;
  transition-duration: var(--duration-close);
  transition-timing-function: var(--ease);
  transition-behavior: allow-discrete;
  &:not([open]) { pointer-events: none; }
  &[open] {
    display: flex;
    translate: none;
    transition-duration: var(--duration-sheet);
    @starting-style { translate: 0 100%; }
  }
  &[open], & > .tun-dialog-form {
    flex-direction: column;
    gap: calc(var(--spacing) * 5);
    min-height: 0;
  }
  & > .tun-dialog-form { display: flex; flex: 1; }
  /* The page behind dims in one fade, darker while the dialog opens and
     lighter while it closes, never a second layer across it. */
  &::backdrop {
    background-color: var(--overlay);
    opacity: 0;
    transition-property: opacity, display, overlay;
    transition-duration: var(--duration-close);
    transition-timing-function: var(--ease);
    transition-behavior: allow-discrete;
  }
  &[open]::backdrop {
    opacity: 1;
    transition-duration: var(--duration);
    @starting-style { opacity: 0; }
  }

  & .tun-dialog-header {
    display: flex;
    flex: none;
    flex-direction: column;
    gap: calc(var(--spacing) * 1.5);
    padding-inline-end: calc(var(--spacing) * 10);
  }
  & .tun-dialog-title {
    font-size: var(--text-base);
    line-height: var(--text-base--line-height);
    font-weight: var(--font-weight-medium);
    letter-spacing: normal;
    overflow-wrap: anywhere;
  }
  & .tun-dialog-description { color: var(--muted-foreground); }
  /* Only the body scrolls, between the header and the footer; the inset
     keeps the focus rings of its fields from being cut off. */
  & .tun-dialog-body {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    overscroll-behavior: contain;
    margin: calc(var(--spacing) * -1);
    padding: var(--spacing);
    & > * + * { margin-top: calc(var(--spacing) * 3); }
  }
  /* On a phone the buttons share one row, the step last. */
  & .tun-dialog-footer {
    display: flex;
    flex: none;
    flex-wrap: wrap;
    gap: calc(var(--spacing) * 2);
    & > * { flex: 1 1 auto; }
  }
  & .tun-dialog-close {
    position: absolute;
    top: calc(var(--spacing) * 3);
    right: calc(var(--spacing) * 3);
  }

  &:is([data-variant='confirm'], [data-variant='destructive']) {
    & .tun-dialog-header { padding-inline-end: 0; }
    & .tun-dialog-title { font-size: var(--text-lg); line-height: var(--text-lg--line-height); }
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

  /* A dialog to type in fills the phone from the start, so the keyboard
     moves only its bottom edge and never pushes its top off the screen. */
  @media (max-width: 39.99rem) {
    &:has(textarea, [role='combobox'], input:not([type='checkbox'], [type='radio'],
                                                [type='hidden'], [type='file'], [type='submit'],
                                                [type='button'], [type='reset'], [type='image'],
                                                [type='range'], [type='color'])) {
      height: var(--tun-dialog-max-height);
    }
  }

  /* From 40rem it is centred, and rises a little as it fades in. */
  @media (min-width: 40rem) {
    --tun-dialog-padding: calc(var(--spacing) * 6);
    width: calc(100% - var(--spacing) * 8);
    max-width: 28rem;
    margin: auto;
    border-radius: var(--radius-xl);
    opacity: 0;
    translate: 0 calc(var(--spacing) * 2);
    & .tun-dialog-close { top: calc(var(--spacing) * 4); right: calc(var(--spacing) * 4); }
    &[open] {
      opacity: 1;
      translate: none;
      transition-duration: var(--duration);
      @starting-style { opacity: 0; translate: 0 calc(var(--spacing) * 2); }
    }
    & .tun-dialog-footer {
      justify-content: flex-end;
      & > * { flex: none; }
    }
    /* A fixed box whatever it holds, so what changes inside as one types
       never moves its edges (spec/ui.md 6.4): 40rem by 36rem, less where
       the window is smaller. */
    &[data-size='large'] {
      width: min(40rem, calc(100% - var(--spacing) * 8));
      max-width: none;
      height: min(36rem, calc(100dvh - var(--spacing) * 16));
    }
    &:is([data-variant='confirm'], [data-variant='destructive']) {
      max-width: 32rem;
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

// What opened each dialog, which the focus goes back to when it closes.
const openers = new WeakMap();

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
  const button = event.target instanceof Element && event.target.closest('button[commandfor]');
  const target = button && document.getElementById(button.getAttribute('commandfor'));
  if (!target || !target.matches('[data-tun-dialog]')) return;
  const command = button.getAttribute('command');
  if (command === 'show-modal' && !target.open) openers.set(target, button);
  if (invokers) return;
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
    if (!shortcut || dialog.open || (!/^ctrl\\+/i.test(shortcut) && typing(event.target))) continue;
    event.preventDefault();
    openers.set(dialog, document.activeElement);
    dialog.showModal();
    return;
  }
});

// The controls of a dialog, in the order Tab goes through them.
const focusable = 'a[href], button:not(:disabled), input:not(:disabled):not([type=hidden]), '
  + 'select:not(:disabled), textarea:not(:disabled), summary, [tabindex]:not([tabindex=\"-1\"])';
const controls = (dialog) => [...dialog.querySelectorAll(focusable)]
  .filter((control) => control.getClientRects().length > 0 && !control.closest('[inert]'));
const modals = () => [...document.querySelectorAll('dialog[open]')].filter(tunModal);

// Opening puts the focus on the control with autofocus, else on the first
// control, unless the browser or the script that opened it put it on one.
const focusInto = (dialog) => {
  const active = document.activeElement;
  if (active && active !== dialog && dialog.contains(active)) return;
  const first = dialog.querySelector('[autofocus]') || controls(dialog)[0];
  first?.focus({ preventScroll: true });
};

// While a modal dialog is open the page behind it holds still.  The room
// of a scroll bar that takes room is kept, so nothing moves sideways.
let held = null;
const hold = () => {
  const root = document.documentElement;
  if (modals().length > 0 && !held) {
    held = { overflow: root.style.overflow, gutter: root.style.scrollbarGutter };
    if (window.innerWidth > root.clientWidth) root.style.scrollbarGutter = 'stable';
    root.style.overflow = 'hidden';
  } else if (modals().length === 0 && held) {
    root.style.overflow = held.overflow;
    root.style.scrollbarGutter = held.gutter;
    held = null;
  }
};

// The keyboard (spec/ui.md 6): while a modal dialog is open, how far the
// visible part of the window is from its top and its bottom, which a
// dialog stands between, so a keyboard laid over the page (Safari) or
// shrinking only what is visible (Chrome on Android) never covers it.
// Nothing while the page is zoomed in, where the visible part is meant to
// be smaller, and nothing once no dialog is open.
const fit = () => {
  const root = document.documentElement;
  const viewport = window.visualViewport;
  let inset = null;
  if (viewport && modals().length > 0 && Math.abs((viewport.scale ?? 1) - 1) <= 0.01) {
    const top = Math.max(0, Math.round(viewport.offsetTop || 0));
    const bottom = Math.max(0, Math.round(root.clientHeight - top - viewport.height));
    if (top > 1 || bottom > 1) inset = { top, bottom };
  }
  if (inset) {
    root.style.setProperty('--tun-visual-top', `${inset.top}px`);
    root.style.setProperty('--tun-visual-bottom', `${inset.bottom}px`);
    // The field being typed in stays in sight above the keyboard.
    const field = document.activeElement;
    if (field instanceof Element && field.closest('dialog[open]')
        && field.matches('input, textarea, [contenteditable]'))
      field.scrollIntoView({ block: 'nearest' });
  } else {
    root.style.removeProperty('--tun-visual-top');
    root.style.removeProperty('--tun-visual-bottom');
  }
};
window.visualViewport?.addEventListener('resize', fit);
window.visualViewport?.addEventListener('scroll', fit);
document.addEventListener('focusin', (event) => {
  if (event.target instanceof Element && event.target.closest('dialog[open]')) fit();
});

// A dialog opens and closes by its open attribute, whoever sets it: the
// browser's invoker commands, showModal from a script, a form's method=dialog.
new MutationObserver((records) => {
  for (const { target } of records)
    if (target instanceof HTMLDialogElement && target.open && tunModal(target)) focusInto(target);
  hold();
  fit();
}).observe(document.documentElement,
            { subtree: true, attributes: true, attributeFilter: ['open'] });

// Closing gives the focus back to what opened the dialog, where the
// browser has not already.
document.addEventListener('close', (event) => {
  const dialog = event.target;
  if (!(dialog instanceof HTMLDialogElement)) return;
  const opener = openers.get(dialog);
  openers.delete(dialog);
  const active = document.activeElement;
  if (opener?.isConnected && (!active || active === document.body || dialog.contains(active)))
    opener.focus({ preventScroll: true });
}, true);

// Tab and Shift+Tab go round the controls of a modal dialog, never out of it.
document.addEventListener('keydown', (event) => {
  if (event.key !== 'Tab' || event.defaultPrevented || event.altKey || event.ctrlKey
      || event.metaKey) return;
  const active = document.activeElement;
  const dialog = active instanceof Element && active.closest('dialog[open]');
  if (!dialog || !tunModal(dialog)) return;
  const all = controls(dialog);
  if (all.length === 0) return;
  const first = all[0];
  const last = all[all.length - 1];
  if (event.shiftKey && (active === first || active === dialog)) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && (active === last || active === dialog)) {
    event.preventDefault();
    first.focus();
  }
});")
  (:examples
   ("A task in a dialog"
    (button (:variant :outline :icon :send
                      :attributes (list :command "show-modal" :commandfor "send-invoice"))
            "Send invoice")
    (dialog (:id "send-invoice"
                 :title "Send invoice 2024-117"
                 :description "The invoice is sent as a PDF to the customer's invoice address."
                 :footer (list (button (:variant :outline
                                                 :attributes (list :command "close"
                                                                   :commandfor "send-invoice"))
                                       "Cancel")
                               (button (:type "submit") "Send invoice"))
                 :action "/invoices/2024-117/send")
            `(:p "To " (:strong "Nordvik Bakery Ltd") ", invoice@example.com.")
            `(:p "Amount €12,450, due 14 days after sending.")))
   ("A confirmation before deleting"
    (button (:variant :destructive :icon :trash
                      :attributes (list :command "show-modal" :commandfor "delete-order"))
            "Delete order")
    (dialog (:id "delete-order"
                 :variant :destructive
                 :title "Delete order 1042?"
                 :description "The order and all its lines are deleted for good. This cannot be
undone."
                 :action "/orders/1042/delete"
                 :footer (list (button (:variant :outline
                                                 :attributes (list :command "close"
                                                                   :commandfor "delete-order"))
                                       "Cancel")
                               (button (:type "submit" :variant :destructive)
                                       "Delete the order")))))
   ("A question without danger"
    (button (:variant :secondary
                      :attributes (list :command "show-modal" :commandfor "complete-job"))
            "Complete the job")
    (dialog (:id "complete-job"
                 :variant :confirm
                 :icon :circle-check
                 :title "Are you sure?"
                 :description "The job is marked as complete, and the customer is told by email."
                 :footer (list (button (:variant :outline
                                                 :attributes (list :command "close"
                                                                   :commandfor "complete-job"))
                                       "Cancel")
                               (button () "Complete")))))
   ("Search from anywhere, with / or Ctrl+K"
    (button (:variant :outline :icon :search :shortcut "/"
                      :attributes (list :command "show-modal" :commandfor "search"))
            "Search")
    (dialog (:id "search" :title "Search" :shortcut '("/" "Ctrl+K")
                 :action "/search" :method "get"
                 :footer (list (button (:type "submit") "Search")))
            (text-input (:label "Search for items, customers and people" :name "q" :type :search
                                :attributes (list :autofocus t)))))
   ("A note to type: on a phone it fills the screen at once"
    (button (:variant :outline :attributes (list :command "show-modal" :commandfor "add-note"))
            "Add a note")
    (dialog (:id "add-note" :title "Note on order 1042" :action "/orders/1042/notes"
             :footer (list (button (:variant :outline
                                    :attributes (list :command "close" :commandfor "add-note"))
                                   "Cancel")
                           (button (:type "submit") "Save the note")))
            (textarea (:label "Note" :name "note" :rows 4))))
   ("Without a footer"
    (button (:variant :ghost :attributes (list :command "show-modal" :commandfor "shortcuts"))
            "Keyboard shortcuts")
    (dialog (:id "shortcuts" :title "Keyboard shortcuts")
            `(:p "Press " ,(kbd () "/") " to search, and " ,(kbd () "Esc")
                 " to close a window.")))
   ("Long content scrolls inside the dialog"
    (button (:variant :ghost
                      :attributes (list :command "show-modal" :commandfor "terms"))
            "Read the terms")
    (dialog (:id "terms"
                 :title "Terms for jobs"
                 :description "Apply to every job ordered after 1 January 2026."
                 :footer (list (button (:attributes (list :command "close" :commandfor "terms"))
                                       "I have read the terms")))
            (loop for (heading text)
                  in '(("Ordering" "A job is binding once the customer has accepted the quote in
writing, by email or text message too.")
                       ("Price" "The price in the quote is valid for 30 days. Work beyond what is
described is invoiced by time spent at €85 an hour excluding VAT.")
                       ("Cancelling" "The customer can cancel free of charge up to seven days
before the start. A later cancellation is invoiced at 25 per cent of the agreed price.")
                       ("Payment" "Payment is due within 14 days. Late payment carries interest
under the Late Payment Act.")
                       ("Complaints" "Defects are reported in writing within a reasonable time
after they were found, and at the latest five years after handover.")
                       ("Liability" "We are liable for damage we cause to the customer's property
during the work, up to the value of the job. We are not liable for indirect loss.")
                       ("Personal data" "We keep name, address and phone number for as long as
the customer relationship lasts, and after that as long as the Bookkeeping Act requires.")
                       ("Disputes" "The parties shall first try to settle a disagreement by
negotiation. The venue is the district court where the job was done."))
                  collect `(:p (:strong ,heading ". ") ,text)))))
  (unless (and id title)
    (error "A dialog needs :id, which its buttons name, and :title"))
  (check-type variant (member :default :confirm :destructive))
  (check-type size (member :default :large))
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
                        ,(button (:variant :ghost :size :icon-sm :label (tr "Close")
                                           :attributes (list :command "close" :commandfor id))
                                 (icon (:name :x)))))))))
    `(:dialog ,(attrs (list :class "tun-dialog" :id id :data-variant (option-string variant)
                            :data-size (unless (eq size :default) (option-string size))
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
;;; confirm-dialog

(defun confirm-attributes (question &key detail action)
  "The attributes that make a control (a button, a link, a menu item) ask
QUESTION in the page's CONFIRM-DIALOG before it acts, as a property list for
its :ATTRIBUTES (spec/ui.md 6).  QUESTION names the record, «Delete order
1042?»; DETAIL is one sentence of what follows; ACTION is the words of the
dialog's action button, for a control whose own words do not say it, such
as one that is only an icon.  Without JavaScript the control acts unasked."
  (check-type question string)
  (check-type detail (or null string))
  (check-type action (or null string))
  (list :data-tun-confirm question :data-tun-confirm-detail detail
        :data-tun-confirm-action action))

(export 'confirm-attributes)

(define-component confirm-dialog ((&key id attributes))
  (:group "Interaction")
  (:doc "The page's one dialog that asks before an action, instead of the browser's own box.
Every app-shell holds one. A control marked with (confirm-attributes QUESTION :detail D) asks
in it on a click and acts only when the person agrees, and so does htmx's hx-confirm. Its
action repeats the control's words, in red when the control is destructive. Without
JavaScript the control acts unasked, and a page that asks on the server still asks.")
  (:source "Basecoat alert dialog (Vega); GOV.UK confirmation (the question names the record)")
  (:css "
.tun-confirm-dialog {
  /* Only the dialog inside it takes room, once it is open. */
  display: contents;
}")
  (:script "
// One confirm (spec/ui.md 6): a control marked data-tun-confirm, and an
// element with htmx's hx-confirm, ask in the page's confirm dialog before
// they act.  The texts are the page's: the question and the sentence on the
// control, and the words of Cancel and of the action when the control has
// none in the dialog's data-cancel-label and data-confirm-label.  The
// buttons are empty until it asks, so a page that shows no «Cancel» of its
// own does not hold one in its text.
const confirmDialog = () => document.querySelector('[data-tun-confirm-dialog] > dialog');
const words = (text) => String(text ?? '').replace(/\\s+/g, ' ').trim();
// A control's own words: its text without its key caps and icons, else
// its name.
const ownWords = (control) => {
  const copy = control.cloneNode(true);
  for (const part of copy.querySelectorAll('.tun-kbd, svg, [aria-hidden=true]')) part.remove();
  return words(copy.textContent) || words(control.getAttribute('aria-label'));
};
const destructive = (control) => control?.getAttribute('data-variant') === 'destructive';
// Where the focus goes back to: the control, or the button of the menu it
// was in, which has closed.
const returnTo = (control) => {
  const menu = control.closest('[popover]');
  if (!menu || tunPopoverOpen(menu) || !menu.id) return control;
  return document.querySelector(`[popovertarget='${CSS.escape(menu.id)}']`) || control;
};

const ask = (control, question, detail, action, danger) => new Promise((answer) => {
  const dialog = confirmDialog();
  if (!dialog) {
    answer(window.confirm(detail ? `${question} ${detail}` : question));
    return;
  }
  if (dialog.open) {
    answer(false);
    return;
  }
  const ok = dialog.querySelector('[data-tun-confirm-ok]');
  const cancel = dialog.querySelector('[data-tun-confirm-cancel]');
  const sentence = dialog.querySelector('.tun-dialog-description');
  const labels = dialog.parentElement.dataset;
  cancel.textContent = labels.cancelLabel;
  dialog.querySelector('.tun-dialog-title').textContent = question;
  sentence.textContent = detail;
  sentence.hidden = !detail;
  ok.textContent = action.length > 0 && action.length <= 40 ? action : labels.confirmLabel;
  ok.dataset.variant = danger ? 'destructive' : 'primary';
  dialog.returnValue = '';
  dialog.addEventListener('close', () => {
    const yes = dialog.returnValue === 'ok';
    if (!yes && control?.isConnected) returnTo(control).focus({ preventScroll: true });
    answer(yes);
  }, { once: true });
  dialog.showModal();
  // Something that cannot be undone starts on Cancel, so Enter is safe.
  (danger ? cancel : ok).focus({ preventScroll: true });
});

// A marked control's click is held back while the dialog asks; once the
// person agrees the control is clicked again and let through, once.
const agreed = new WeakSet();
document.addEventListener('click', (event) => {
  if (!(event.target instanceof Element)) return;
  const asking = event.target.closest('[data-tun-confirm-dialog] > dialog');
  if (asking) {
    if (event.target.closest('[data-tun-confirm-ok]')) asking.close('ok');
    else if (event.target.closest('[data-tun-confirm-cancel]')) asking.close('');
    return;
  }
  const control = event.target.closest('[data-tun-confirm]');
  if (!control || control.matches(':disabled, [aria-disabled=true]')) return;
  if (agreed.has(control)) {
    agreed.delete(control);
    return;
  }
  event.preventDefault();
  event.stopImmediatePropagation();
  ask(control, words(control.dataset.tunConfirm), words(control.dataset.tunConfirmDetail),
      words(control.dataset.tunConfirmAction) || ownWords(control), destructive(control))
    .then((yes) => {
      if (!yes || !control.isConnected) return;
      agreed.add(control);
      control.click();
    });
}, true);

// htmx asks before a request with hx-confirm: the text up to and with its
// first question mark is the question, the rest the sentence.
document.addEventListener('htmx:confirm', (event) => {
  if (!confirmDialog()) return;
  event.preventDefault();
  const { ctx, issueRequest, dropRequest } = event.detail;
  const control = ctx.sourceEvent?.submitter || event.target;
  const text = words(ctx.confirm);
  const end = text.indexOf('?');
  ask(control, end >= 0 ? text.slice(0, end + 1) : text, end >= 0 ? text.slice(end + 1).trim() : '',
      ownWords(control), destructive(control))
    .then((yes) => (yes ? issueRequest() : dropRequest()));
});")
  (:examples
   ("A destructive action asks first"
    (confirm-dialog (:id "confirm-delete"))
    `(:form (:@ :method "post" :action "/orders/1042/delete")
            ,(button (:type "submit" :variant :destructive :icon :trash
                      :attributes (confirm-attributes
                                   "Delete order 1042?"
                                   :detail "The order and all its lines are deleted for good."))
                     "Delete order")))
   ("Without danger, and a link"
    (confirm-dialog (:id "confirm-send"))
    `(:form (:@ :method "post" :action "/invoices/2024-117/send")
            ,(button (:type "submit" :icon :send
                      :attributes (confirm-attributes
                                   "Send invoice 2024-117?"
                                   :detail "It goes as a PDF to the customer's invoice address."))
                     "Send invoice"))
    (button (:variant :outline :href "/orders"
             :attributes (confirm-attributes "Leave order 1042 without saving?"
                                             :detail "What you changed is lost."
                                             :action "Leave"))
            "Back to the orders"))
   ("htmx's hx-confirm asks in it too"
    (confirm-dialog (:id "confirm-archive"))
    (button (:variant :outline
             :attributes (list :hx-post "/orders/1042/archive" :hx-swap "none"
                               :hx-confirm
                               "Archive order 1042? It leaves the list of open orders."))
            "Archive"))
   ("Long words, and a text without a question"
    (confirm-dialog (:id "confirm-remind"))
    (button (:variant :outline
             :attributes (confirm-attributes
                          "Send 12 reminders?"
                          :detail "Each customer with an unpaid invoice gets one by email."))
            "Send a reminder of every unpaid invoice to its customer")
    (button (:variant :outline
             :attributes (list :hx-post "/orders/archive-finished" :hx-swap "none"
                               :hx-confirm "Every finished order is archived."))
            "Archive the finished orders"))
   ("From inside a dialog"
    (confirm-dialog (:id "confirm-edit"))
    (button (:variant :outline :attributes (list :command "show-modal" :commandfor "edit-order"))
            "Edit order 1042")
    (dialog (:id "edit-order" :title "Edit order 1042" :action "/orders/1042"
             :footer (list (button (:type "submit" :variant :destructive
                                    :attributes (append
                                                 (list :formaction "/orders/1042/delete")
                                                 (confirm-attributes
                                                  "Delete order 1042?"
                                                  :detail
                                                  "The order and all its lines are deleted for good.")))
                                   "Delete")
                           (button (:type "submit") "Save")))
            (text-input (:label "Reference" :name "reference" :value "Spring fair")))))
  `(:div ,(attrs (list :class "tun-confirm-dialog" :data-tun-confirm-dialog t
                       :data-cancel-label (tr "Cancel") :data-confirm-label (tr "Confirm"))
                 attributes)
         ;; One id for the one on a page, so a page renders the same every
         ;; time (the offline page's version is its content's hash).
         ,(dialog* (list :id (or id "tun-confirm-dialog")
                         :variant :confirm :title "" :description ""
                         :footer (list (button (:variant :outline
                                                :attributes (list :data-tun-confirm-cancel t)))
                                       (button (:attributes (list :data-tun-confirm-ok t))))))))

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
     ,@(when icon (list (if (consp icon) icon (icon* (list :name icon)))))
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
  (:group "Interaction")
  (:doc "A button that opens a list of actions, for choices that do not fit as buttons of
their own. LABEL is the button's text; with an icon size (:size :icon) only ICON shows, and
LABEL becomes the button's name for screen readers. Each entry of ITEMS is (:label :href :icon
:shortcut :variant :disabled :attributes), :separator or (:group HEADING :items (...)); an
item's ICON is an icon's name or an icon already made.")
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
    border-radius: var(--radius-lg);
    background-color: var(--popover);
    color: var(--popover-foreground);
    box-shadow: 0 0 0 1px var(--border), var(--shadow-md);
    outline: none;
    /* Closed, and leaving: a little below its place, faded. */
    opacity: 0;
    translate: 0 var(--spacing);
    transition-property: opacity, translate, display, overlay;
    transition-duration: var(--duration-close);
    transition-timing-function: var(--ease);
    transition-behavior: allow-discrete;
    &:not(:popover-open) { pointer-events: none; }
    &:popover-open {
      opacity: 1;
      translate: none;
      transition-duration: var(--duration-fast);
      @starting-style { opacity: 0; translate: 0 var(--spacing); }
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
    }
    &[data-align='end'] .tun-dropdown-menu-content {
      position-area: block-end span-inline-start;
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
    &:active { background-color: var(--pressed); transition-duration: 0s; }
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
  for (const menu of document.querySelectorAll(menuSelector)) if (tunPopoverOpen(menu)) place(menu);
};
window.addEventListener('resize', placeOpenMenus);
document.addEventListener('scroll', placeOpenMenus, true);

const syncExpanded = (root) => {
  for (const menu of root.querySelectorAll(menuSelector))
    triggerOf(menu)?.setAttribute('aria-expanded', String(tunPopoverOpen(menu)));
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
  if (tunPopoverOpen(menu)) menu.hidePopover();
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
    if (tunPopoverOpen(menu)) {
      const items = itemsOf(menu);
      move(items, event.key === 'ArrowDown' ? 0 : -1);
    } else {
      focusOnOpen = event.key === 'ArrowDown' ? 'first' : 'last';
      menu.showPopover({ source: trigger });
    }
    return;
  }
  const menu = event.target.closest(menuSelector);
  if (!menu || !tunPopoverOpen(menu) || event.altKey || event.ctrlKey || event.metaKey) return;
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
   ("Actions for an order"
    (dropdown-menu (:label "Actions"
                           :items (list (list :group "Order 1042"
                                              :items (list (list :label "Edit" :icon :pencil
                                                                 :href "/orders/1042/edit"
                                                                 :shortcut "E")
                                                           (list :label "Duplicate" :icon :copy
                                                                 :shortcut "D")
                                                           (list :label "Download a PDF"
                                                                 :icon :download
                                                                 :href "/orders/1042.pdf")))
                                        :separator
                                        (list :label "Send to the customer" :icon :send)
                                        :separator
                                        (list :label "Delete order" :icon :trash
                                              :variant :destructive
                                              :attributes (list :command "show-modal"
                                                                :commandfor "menu-delete-order")))))
    (dialog (:id "menu-delete-order"
                 :variant :destructive
                 :title "Delete order 1042?"
                 :description "The order and all its lines are deleted for good."
                 :action "/orders/1042/delete"
                 :footer (list (button (:variant :outline
                                                 :attributes (list :command "close"
                                                                   :commandfor "menu-delete-order"))
                                       "Cancel")
                               (button (:type "submit" :variant :destructive)
                                       "Delete the order")))))
   ("Icon only, at the end of a row"
    (dropdown-menu (:label "More options for Hansen Bakery Ltd" :size :icon :variant :ghost
                           :icon :ellipsis :align :end
                           :items (list (list :label "Show the customer" :icon :user
                                              :href "/customers/17")
                                        (list :label "New order" :icon :plus
                                              :href "/customers/17/orders/new")
                                        (list :label "Send a reminder of an unpaid invoice"
                                              :icon :mail)
                                        :separator
                                        (list :label "Merge with another customer" :icon :users
                                              :disabled t)))))
   ("Account"
    (dropdown-menu (:label "Kari Nordmann" :variant :ghost :icon :user
                           :items (list (list :group "Kari Nordmann, Nordmann Plumbing Ltd"
                                              :items (list (list :label "Profile" :icon :user
                                                                 :href "/profile")
                                                           (list :label "Settings"
                                                                 :icon :settings
                                                                 :href "/settings")))
                                        :separator
                                        (list :label "Sign out" :icon :log-out
                                              :attributes (list :type "submit"
                                                                :form "sign-out")))))
    '(:form (:@ :id "sign-out" :method "post" :action "/logout"))))
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
  (:group "Interaction")
  (:doc "A short explanation that shows when the pointer is over a button or the keyboard is
on it, often a button with only an icon. It does not show on touch screens, so it must never
be the only place important information is. The text is read out after the button's name,
so it should add to the name, not repeat it.")
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
    /* Where it stands (centred on its button), and hidden a little below
       it, faded, from where it rises. */
    --tun-tooltip-x: -50%;
    --tun-tooltip-y: 0px;
    visibility: hidden;
    opacity: 0;
    translate: var(--tun-tooltip-x) calc(var(--tun-tooltip-y) + var(--spacing));
    transition-property: opacity, translate, visibility;
    transition-duration: var(--duration-close);
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
    --tun-tooltip-x: 0px;
    --tun-tooltip-y: -50%;
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
      --tun-tooltip-x: 0px;
      --tun-tooltip-y: 0px;
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
      translate: var(--tun-tooltip-x) var(--tun-tooltip-y);
      transition-duration: var(--duration-fast);
    }
  }
  &:not([data-dismissed]):has(:focus-visible) .tun-tooltip-content {
    visibility: visible;
    opacity: 1;
    translate: var(--tun-tooltip-x) var(--tun-tooltip-y);
    transition-duration: var(--duration-fast);
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
   ("Icon buttons"
    (tooltip (:text "Copy the link to the invoice")
             (button (:size :icon :variant :outline :label "Copy link") (icon (:name :copy))))
    (tooltip (:text "Download as a PDF")
             (button (:size :icon :variant :outline :label "Download") (icon (:name :download))))
    (tooltip (:text "Print a packing slip for every order to be sent today")
             (button (:size :icon :variant :outline :label "Packing slip")
                     (icon (:name :file-text)))))
   ("Sides"
    (tooltip (:text "Above" :side :top)
             (button (:variant :outline) "Top"))
    (tooltip (:text "Below" :side :bottom)
             (button (:variant :outline) "Bottom"))
    (tooltip (:text "To the left" :side :left)
             (button (:variant :outline) "Left"))
    (tooltip (:text "To the right" :side :right)
             (button (:variant :outline) "Right"))))
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
  (:group "Interaction")
  (:doc "Headings that unfold their content, for text one seldom needs to see all of at once,
such as frequently asked questions. Each entry of ITEMS is (:title :content :open). With
EXCLUSIVE only one entry is open at a time. Works without JavaScript.")
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
    transition-property: box-shadow, border-color, background-color;
    transition-duration: var(--duration-fast);
    transition-timing-function: var(--ease);
    &::-webkit-details-marker { display: none; }
    &:focus-visible { box-shadow: var(--focus-ring); }
    &:active { background-color: var(--pressed); transition-duration: 0s; }
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
    font-size: var(--text-running);
    line-height: var(--text-running--line-height);
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
   (("Frequently asked questions, one open at a time" :layout :stack)
    (accordion (:items (list (list :title "How long is the delivery time?"
                                   :open t
                                   :content "Goods in stock are sent the same day when you
order before 2 pm. You usually get them within two to four working days.")
                             (list :title "Can I change an order after it has been sent?"
                                   :content "No, but you can return the goods within 30
days and place a new order.")
                             (list :title "How does invoicing work for businesses?"
                                   :content
                                   (list '(:p "Businesses are invoiced with 14 days to pay.
The invoice is sent by EHF when we have your organisation number.")
                                         '(:p "Private persons pay by card or Vipps when
they order."))))
                       :exclusive t)))
   (("Several open at once" :layout :stack)
    (accordion (:items (list (list :title "Contact details"
                                   :open t
                                   :content "Hansen Bakery Ltd, Storgata 12, 0155 Oslo.")
                             (list :title "Terms of payment"
                                   :open t
                                   :content "14 days net. A reminder fee of €3.")
                             (list :title "The fitter's notes on access, keys and parking
for the job in the back yard"
                                   :content "Collect the key in the shop. Park in
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
  (:group "Interaction")
  (:doc "Tabs that split the content of one page into parts seen one at a time. Each entry of
ITEMS is (:label :content :icon :selected :id); without JavaScript every part shows one after
another, each under its heading. When the entries are links (:label :href :current), the tabs
navigate between pages of their own. LABEL says what the tabs are about.")
  (:source "Basecoat tabs (Vega); without JavaScript as GOV.UK tabs")
  (:css "
.tun-tabs {
  display: flex;
  min-width: 0;
  flex-direction: column;
  gap: calc(var(--spacing) * 2);
  /* A strip in a frame on whatever ground it stands on: the page, a card
     or the chrome. */
  & .tun-tabs-list {
    display: flex;
    width: fit-content;
    max-width: 100%;
    height: var(--control-height);
    align-items: center;
    gap: 2px;
    padding: 2px;
    overflow-x: auto;
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
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
    border-radius: var(--radius-sm);
    color: var(--muted-foreground);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    font-weight: var(--font-weight-medium);
    white-space: nowrap;
    text-decoration: none;
    outline: none;
    transition-property: color, background-color, box-shadow, border-color;
    transition-duration: var(--duration-fast);
    transition-timing-function: var(--ease);
    @media (hover: hover) { &:hover { color: var(--foreground); } }
    &:focus-visible { box-shadow: var(--focus-ring); }
    & .tun-icon:not([data-size]) {
      width: calc(var(--spacing) * 4);
      height: calc(var(--spacing) * 4);
    }
    &:has(> .tun-icon:first-child) { padding-inline-start: calc(var(--spacing) * 1.5); }
    /* The chosen tab shows by its ground and frame, at the weight and size
       of the others, so choosing one moves nothing. */
    &:is([aria-selected='true'], [aria-current='page']) {
      border-color: var(--border);
      background-color: var(--secondary);
      color: var(--foreground);
    }
    &:active { background-color: var(--pressed); transition-duration: 0s; }
  }
  &[data-variant='line'] {
    & .tun-tabs-list {
      width: 100%;
      gap: var(--spacing);
      padding: 0;
      border: 0;
      border-radius: 0;
      box-shadow: inset 0 -1px var(--border);
      /* Each tab its own width, side by side from the start of the row. */
      & li { flex-grow: 0; }
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
        transition: opacity var(--duration-fast) var(--ease);
      }
      &:is([aria-selected='true'], [aria-current='page']) {
        border-color: transparent;
        background-color: transparent;
        box-shadow: none;
        &::after { opacity: 1; }
      }
      &:focus-visible { box-shadow: var(--focus-ring-inset); }
    }
  }
  & .tun-tabs-panel {
    font-size: var(--text-running);
    line-height: var(--text-running--line-height);
    border-radius: var(--radius-sm);
    outline: none;
    &:focus-visible { box-shadow: var(--focus-ring); }
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
   (("Tabs on a page" :layout :stack)
    (tabs (:label "Order 1042"
                  :items (list (list :label "Details"
                                     :content
                                     (list '(:p "Ordered on 3 October 2026 by Hansen Bakery Ltd.")
                                           '(:p "Delivered to Storgata 12, 0155 Oslo.")))
                               (list :label "Order lines" :selected t
                                     :content (list '(:p "3 lines, €12,450 in all.")
                                                    '(:ul (:li "Wheat flour 25 kg, 10 sacks")
                                                      (:li "Rye flour 25 kg, 4 sacks")
                                                      (:li "Shipping"))))
                               (list :label "History"
                                     :content '(:p "The order was created by Kari Nordmann."))))))
   (("Line, with icons and many tabs" :layout :stack)
    (tabs (:label "Customer" :variant :line
                  :items (list (list :label "Overview" :icon :house
                                     :content
                                     '(:p "Hansen Bakery Ltd has been a customer since 2019."))
                               (list :label "Orders" :icon :package
                                     :content '(:p "12 orders this year."))
                               (list :label "Invoices" :icon :receipt
                                     :content '(:p "2 unpaid invoices, €18,900 in all."))
                               (list :label "Contacts" :icon :users
                                     :content '(:p "Ola Hansen, managing director."))
                               (list :label "Notes" :icon :message-square
                                     :content '(:p "Deliver by the back way before 7 am."))))))
   (("Links to pages of their own" :layout :stack)
    (tabs (:label "Customer" :variant :line
                  :items (list (list :label "Overview" :href "/customers/17")
                               (list :label "Orders" :href "/customers/17/orders" :current t)
                               (list :label "Invoices" :href "/customers/17/invoices")
                               (list :label "Contacts" :href "/customers/17/contacts"))))
    (tabs (:label "Period"
                  :items (list (list :label "Today" :href "/sales?period=day" :current t)
                               (list :label "This week" :href "/sales?period=week")
                               (list :label "This month" :href "/sales?period=month"))))))
  (unless (and label items)
    (error "Tabs need :label, what they are about, and :items"))
  (check-type variant (member :default :line))
  (let ((links (count-if (lambda (item) (getf item :href)) items)))
    (cond ((= links (length items)) (tab-links label items variant id attributes))
          ((zerop links) (tab-panels label items variant heading-level id attributes))
          (t (error "Tabs are either all links (:href) or all panels (:content)")))))
