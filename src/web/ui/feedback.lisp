;;;; web/ui/feedback.lisp -- the feedback group (spec/ui.md 6): messages to
;;;; the user (alert, flash), the confirmation before a :confirm operation
;;;; runs (confirm-panel), and signs that something is under way (progress,
;;;; spinner, skeleton).

(in-package #:tun.ui)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +status-icons+
  '((:info . :info) (:success . :circle-check) (:warning . :triangle-alert)
    (:destructive . :circle-alert))
  "The icon each status variant of ALERT and FLASH shows unless told otherwise.")

(defun status-icon (variant)
  "The icon status VARIANT shows by default, or NIL for one without."
  (cdr (assoc variant +status-icons+)))

;;; ------------------------------------------------------------------
;;; Alert

(define-component alert ((&key (variant :default) (icon (status-icon variant)) title actions
                               (role (when (eq variant :destructive) :alert)) id attributes)
                         &rest children)
  (:group "Feedback")
  (:doc "A message on the page about something the user should know, with TITLE, a
description and perhaps actions (ACTIONS). The variant destructive gets role=\"alert\" and is
read out at once; the others are plain content without a role, since a message that is there
when the page loads need not interrupt the screen reader. Give ROLE :status to a message
inserted after the page has loaded.")
  (:source "Basecoat alert (Vega), with Tun's status colours")
  (:css "
.tun-alert {
  /* The status variants set these two; the default variant does not use them. */
  --tun-alert-tone: var(--foreground);
  --tun-alert-soft: var(--card);
  display: flex;
  align-items: flex-start;
  gap: calc(var(--spacing) * 2.5);
  width: 100%;
  padding: calc(var(--spacing) * 3) calc(var(--spacing) * 4);
  border: 1px solid var(--border);
  border-radius: var(--radius-lg);
  background-color: var(--card);
  color: var(--card-foreground);
  font-size: var(--text-sm);
  line-height: var(--text-sm--line-height);
  text-align: start;
  & > .tun-icon {
    /* Centres the 16px icon on the first 20px line of text. */
    translate: 0 calc(var(--spacing) * 0.5);
    color: currentColor;
  }
  & .tun-alert-content {
    display: grid;
    flex: 1;
    min-width: 0;
    justify-items: start;
    gap: calc(var(--spacing) * 0.5);
  }
  & .tun-alert-title {
    font-weight: var(--font-weight-medium);
    overflow-wrap: break-word;
  }
  & .tun-alert-description {
    color: var(--muted-foreground);
    text-wrap: pretty;
    overflow-wrap: break-word;
    & p + p, & p + ul, & ul + p { margin-top: calc(var(--spacing) * 2); }
    & ul { padding-left: calc(var(--spacing) * 4); list-style: disc; }
    & a { color: inherit; text-decoration-line: underline; text-underline-offset: 3px; }
  }
  & .tun-alert-actions {
    display: flex;
    flex-wrap: wrap;
    gap: calc(var(--spacing) * 2);
    margin-top: calc(var(--spacing) * 2.5);
  }

  /* Status variants: a tinted background, the tone on icon and border, and
     text mixed from the tone and the foreground, which keeps at least 6:1
     against the tint in both themes (the pure tone on the tint does not:
     destructive is 4.4:1 in the light theme). */
  &[data-variant='info'] { --tun-alert-tone: var(--info); --tun-alert-soft: var(--info-soft); }
  &[data-variant='success'] {
    --tun-alert-tone: var(--success);
    --tun-alert-soft: var(--success-soft);
  }
  &[data-variant='warning'] {
    --tun-alert-tone: var(--warning);
    --tun-alert-soft: var(--warning-soft);
  }
  &[data-variant='destructive'] {
    --tun-alert-tone: var(--destructive);
    --tun-alert-soft: var(--destructive-soft);
  }
  &:not([data-variant='default']) {
    border-color: color-mix(in oklab, var(--tun-alert-tone) 30%, transparent);
    /* The soft tints are strong in the dark theme; mixing in the card
       colour calms them and only raises the contrast of the text. */
    background-color: light-dark(var(--tun-alert-soft),
                                 color-mix(in oklab, var(--tun-alert-soft) 60%, var(--card)));
    color: color-mix(in oklab, var(--tun-alert-tone) 80%, var(--foreground));
    & > .tun-icon { color: var(--tun-alert-tone); }
    & .tun-alert-description {
      color: color-mix(in oklab, var(--tun-alert-tone) 55%, var(--foreground));
    }
  }
}")
  (:examples
   (("Variants" :layout :stack)
    (alert (:title "New in Tun")
           "You can now send reminders straight from the invoice.")
    (alert (:variant :info :title "The customer has an open case")
           "Berg Plumbing Ltd reported an error on invoice 2024-117 yesterday.")
    (alert (:variant :success :title "The invoice has been sent to accounting")
           "Invoice 2024-118 for €12,500 is booked and sent to the ledger.")
    (alert (:variant :warning :title "The customer has no organisation number")
           "You can save the order, but not invoice it until the number is added.")
    (alert (:variant :destructive :title "The order could not be saved")
           "The order could not be saved because the customer has no email."))
   (("With actions" :layout :stack)
    (alert (:variant :warning :title "The quote expires tomorrow"
                     :actions (list (button (:size :sm :variant :outline :href "/quotes/311")
                                            "Open the quote")
                                    (button (:size :sm :variant :ghost) "Not now")))
           "Quote 311 to Northern Lights Electric Ltd is valid until 15 October.")
    (alert (:variant :destructive :title "Syncing with accounting failed"
                     :actions (list (button (:size :sm :variant :outline :icon :refresh-cw)
                                            "Try again")))
           '(:p "Three invoices were not sent. The ledger did not answer within 30 seconds.")
           '(:p "The invoices are in the queue and are sent the next time you try.")))
   (("Without a title, without an icon and with a long text" :layout :stack)
    (alert (:variant :info)
           "The job has been moved to Monday 20 October.")
    (alert (:icon nil :title "A note from the accountant")
           "Remember that every voucher for the third term must be registered before the
deadline for the VAT return. Vouchers that come later are entered in the next term.")
    (alert (:variant :destructive :title "The order could not be saved")
           '(:p "Correct this and try again:")
           '(:ul (:li "The customer has no email address.")
             (:li "The delivery date 31 Sep 2026 does not exist."))))
   (("Inserted after the page has loaded" :layout :stack)
    (alert (:variant :success :role :status :title "Copied")
           "The link to the quote has been copied to the clipboard.")))
  (check-type variant (member :default :info :success :warning :destructive))
  (check-type role (member nil :alert :status))
  `(:div ,(attrs (list :class "tun-alert" :id id :data-variant (option-string variant)
                       :role (option-string role))
                 attributes)
         ,@(when icon (list (icon (:name icon))))
         (:div (:@ :class "tun-alert-content")
               ,@(when title `((:div (:@ :class "tun-alert-title") ,title)))
               ,@(when children `((:div (:@ :class "tun-alert-description") ,@children)))
               ,@(when actions `((:div (:@ :class "tun-alert-actions") ,@actions))))))

;;; ------------------------------------------------------------------
;;; Flash

(define-component flash ((&key (variant :success) (icon (status-icon variant)) (dismissible t)
                               id attributes)
                         &rest children)
  (:group "Feedback")
  (:doc "The message a page shows at its top after a redirect, such as «The customer has been
saved.». It has role=\"status\". The close button shows only when JavaScript runs; without it
the message stays until the next page.")
  (:source "Basecoat alert (Vega); GOV.UK notification banner (a message after an action)")
  (:css "
.tun-flash {
  --tun-flash-tone: var(--success);
  --tun-flash-soft: var(--success-soft);
  display: flex;
  align-items: flex-start;
  gap: calc(var(--spacing) * 2.5);
  width: 100%;
  padding: calc(var(--spacing) * 2.5) calc(var(--spacing) * 3);
  border: 1px solid color-mix(in oklab, var(--tun-flash-tone) 30%, transparent);
  border-radius: var(--radius-lg);
  background-color: light-dark(var(--tun-flash-soft),
                               color-mix(in oklab, var(--tun-flash-soft) 60%, var(--card)));
  color: color-mix(in oklab, var(--tun-flash-tone) 80%, var(--foreground));
  box-shadow: var(--shadow-xs);
  font-size: var(--text-sm);
  line-height: var(--text-sm--line-height);
  font-weight: var(--font-weight-medium);
  &[data-variant='info'] { --tun-flash-tone: var(--info); --tun-flash-soft: var(--info-soft); }
  &[data-variant='warning'] {
    --tun-flash-tone: var(--warning);
    --tun-flash-soft: var(--warning-soft);
  }
  &[data-variant='destructive'] {
    --tun-flash-tone: var(--destructive);
    --tun-flash-soft: var(--destructive-soft);
  }
  & > .tun-icon {
    translate: 0 calc(var(--spacing) * 0.5);
    color: var(--tun-flash-tone);
  }
  & .tun-flash-message {
    flex: 1;
    min-width: 0;
    overflow-wrap: break-word;
    text-wrap: pretty;
    & a { color: inherit; text-decoration-line: underline; text-underline-offset: 3px; }
  }
  /* The close button keeps its full touch target but does not make the bar
     taller than a line of text with its padding. */
  & > [data-tun-flash-close] {
    margin-block: calc((var(--control-height) - var(--text-sm) * var(--text-sm--line-height))
                       / -2);
    margin-inline-end: calc(var(--spacing) * -1.5);
    color: inherit;
    @media (hover: hover) {
      &:hover { background-color: color-mix(in oklab, var(--tun-flash-tone) 15%, transparent); }
    }
  }
}")
  (:script "
// The close button is hidden in the markup, so a page without JavaScript
// never shows a button that does nothing.
const reveal = (root) => {
  for (const button of root.querySelectorAll('[data-tun-flash-close][hidden]'))
    button.hidden = false;
};
tunOnContent(reveal);
document.addEventListener('click', (event) => {
  const button = event.target.closest('[data-tun-flash-close]');
  if (button) button.closest('.tun-flash')?.remove();
});")
  (:examples
   (("Variants" :layout :stack)
    (flash () "The customer has been saved.")
    (flash (:variant :info) "The order has been moved to Hansen Bakery Ltd.")
    (flash (:variant :warning)
           "The invoice was saved as a draft because the customer has no address.")
    (flash (:variant :destructive)
           "The order could not be saved because the customer has no email."))
   (("With a link and a long text" :layout :stack)
    (flash ()
           "Quote 311 has been sent to post@northernlights.example.com. "
           '(:a (:@ :href "/quotes/311") "Show the quote"))
    (flash (:variant :info)
           "The invoices for September have been sent to the accountant, and the copy of
the VAT report is under Documents."))
   (("Without a close button" :layout :stack)
    (flash (:dismissible nil) "You are signed out.")))
  (check-type variant (member :success :info :warning :destructive))
  `(:div ,(attrs (list :class "tun-flash" :id id :data-variant (option-string variant)
                       :role "status")
                 attributes)
         ,@(when icon (list (icon (:name icon))))
         (:div (:@ :class "tun-flash-message") ,@children)
         ,@(when dismissible
             (list (button (:variant :ghost :size :icon :label (tr "Close the message")
                                     :attributes '(:hidden t :data-tun-flash-close t))
                           (icon (:name :x)))))))

;;; ------------------------------------------------------------------
;;; Confirm panel

(defun confirm-hidden-inputs (pairs)
  "Hidden inputs for PAIRS, a list of (NAME VALUE) with string names."
  (loop for pair in pairs
        collect (destructuring-bind (name value) pair
                  (check-type name string)
                  `(:input (:@ :type "hidden" :name ,name :value ,(princ-to-string value))))))

(define-component confirm-panel ((&key title action confirm-label cancel-href
                                       (cancel-label (tr "Cancel")) (variant :destructive)
                                       (icon (when (eq variant :destructive) :triangle-alert))
                                       warning hidden id attributes)
                                 &rest children)
  (:group "Feedback")
  (:doc "What a :confirm operation shows before it runs: what will happen (the children,
often a summary-list), a warning (WARNING) when one is needed, and a form that posts to ACTION
with the fields in HIDDEN, such as the confirmation token. Use the variant primary when the
action destroys nothing.")
  (:source "GOV.UK warning text and confirmation; Basecoat alert dialog (Vega)")
  (:css "
.tun-confirm-panel {
  container-type: inline-size;
  display: grid;
  gap: calc(var(--spacing) * 4);
  /* A width rather than max-width: a confirmation reads best at about the
     measure of a GOV.UK two-thirds column, also in a wide parent. */
  width: min(100%, 40rem);
  padding: calc(var(--spacing) * 5);
  border: 1px solid var(--border);
  border-radius: var(--radius-xl);
  background-color: var(--card);
  color: var(--card-foreground);
  box-shadow: var(--shadow-xs);
  & .tun-confirm-panel-header {
    display: flex;
    align-items: center;
    gap: calc(var(--spacing) * 3);
  }
  & .tun-confirm-panel-icon {
    display: flex;
    flex-shrink: 0;
    align-items: center;
    justify-content: center;
    width: calc(var(--spacing) * 10);
    height: calc(var(--spacing) * 10);
    border-radius: var(--radius-full);
    background-color: var(--muted);
    color: var(--foreground);
    & .tun-icon { width: calc(var(--spacing) * 5); height: calc(var(--spacing) * 5); }
  }
  &[data-variant='destructive'] .tun-confirm-panel-icon {
    background-color: var(--destructive-soft);
    color: var(--destructive);
  }
  & .tun-confirm-panel-title {
    font-size: var(--text-lg);
    line-height: var(--text-lg--line-height);
    font-weight: var(--font-weight-semibold);
    overflow-wrap: break-word;
  }
  & .tun-confirm-panel-body {
    display: grid;
    gap: calc(var(--spacing) * 3);
    color: var(--muted-foreground);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    text-wrap: pretty;
    overflow-wrap: break-word;
    & strong { color: var(--foreground); }
  }
  /* GOV.UK warning text: a bold sentence behind a round exclamation mark. */
  & .tun-confirm-panel-warning {
    display: flex;
    align-items: center;
    gap: calc(var(--spacing) * 3);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    font-weight: var(--font-weight-semibold);
  }
  & .tun-confirm-panel-mark {
    display: flex;
    flex-shrink: 0;
    align-items: center;
    justify-content: center;
    width: calc(var(--spacing) * 7);
    height: calc(var(--spacing) * 7);
    border: 2px solid var(--foreground);
    border-radius: var(--radius-full);
    background-color: var(--foreground);
    color: var(--background);
    font-size: var(--text-base);
    line-height: 1;
    font-weight: var(--font-weight-bold);
    user-select: none;
    forced-color-adjust: none;
    @media (forced-colors: active) {
      border-color: CanvasText;
      background-color: Canvas;
      color: CanvasText;
    }
  }
  & .tun-confirm-panel-hidden {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
    white-space: nowrap;
  }
  & .tun-confirm-panel-actions {
    display: flex;
    flex-direction: column;
    gap: calc(var(--spacing) * 2);
    padding-top: calc(var(--spacing) * 1);
  }
  @container (min-width: 28rem) {
    & .tun-confirm-panel-actions { flex-direction: row; flex-wrap: wrap; }
  }
  /* The last step of a destructive action is the one place for a solid red
     button (GOV.UK's warning button); the button component's destructive
     variant is the softer one used everywhere else. */
  &[data-variant='destructive'] .tun-confirm-panel-actions > button[type='submit'] {
    background-color: var(--destructive);
    color: var(--destructive-foreground);
    @media (hover: hover) {
      &:hover { background-color: color-mix(in oklab, var(--destructive) 88%, var(--foreground)); }
    }
  }
}")
  (:examples
   (("Deleting a customer" :layout :stack)
    (confirm-panel (:title "Delete the customer Berg Plumbing Ltd?"
                           :action "/customers/42/customers_delete"
                           :confirm-label "Delete customer"
                           :cancel-href "/customers/42"
                           :warning "This cannot be undone."
                           :hidden '(("confirmation_token" "c7f3a9e2")))
                   '(:p "The customer and its 3 contacts are deleted. Invoices that have been
sent are kept in the accounts.")))
   (("Cancelling an order" :layout :stack)
    (confirm-panel (:title "Cancel order 10423?"
                           :action "/orders/10423/orders_cancel"
                           :confirm-label "Cancel order"
                           :cancel-href "/orders/10423"
                           :cancel-label "Keep the order"
                           :hidden '(("confirmation_token" "5d1e0b74")))
                   '(:p "The order for " (:strong "Hansen Bakery Ltd") " of " (:strong "€8,750")
                     " is cancelled, and the customer is told by email.")
                   '(:p "The confirmation expires at 14:32.")))
   (("Confirming without danger (primary)" :layout :stack)
    (confirm-panel (:title "Send invoice 2024-118?"
                           :variant :primary
                           :icon :send
                           :action "/invoices/2024-118/invoices_send"
                           :confirm-label "Send invoice"
                           :cancel-href "/invoices/2024-118"
                           :hidden '(("confirmation_token" "9a04c6f1")))
                   '(:p "The invoice of " (:strong "€12,500") " is sent to
post@northernlights.example.com, due on 30 October."))))
  (check-type title string)
  (check-type action string)
  (check-type confirm-label string)
  (check-type cancel-href string)
  (check-type variant (member :destructive :primary))
  (let ((title-id (element-id "confirm-title")))
    `(:section ,(attrs (list :class "tun-confirm-panel" :id id
                             :data-variant (option-string variant)
                             :aria-labelledby title-id)
                       attributes)
               (:div (:@ :class "tun-confirm-panel-header")
                     ,@(when icon
                         `((:span (:@ :class "tun-confirm-panel-icon") ,(icon (:name icon)))))
                     (:h2 (:@ :class "tun-confirm-panel-title" :id ,title-id) ,title))
               ,@(when children `((:div (:@ :class "tun-confirm-panel-body") ,@children)))
               ,@(when warning
                   `((:p (:@ :class "tun-confirm-panel-warning")
                         (:span (:@ :class "tun-confirm-panel-mark" :aria-hidden "true") "!")
                         (:strong (:span (:@ :class "tun-confirm-panel-hidden")
                                         ,(tr "Warning:") " ")
                                  ,warning))))
               (:form (:@ :class "tun-confirm-panel-actions" :method "post" :action ,action)
                      ,@(confirm-hidden-inputs hidden)
                      ,(button (:type "submit" :variant variant) confirm-label)
                      ,(button (:href cancel-href :variant :outline) cancel-label)))))

;;; ------------------------------------------------------------------
;;; Progress

(define-component progress ((&key label value (max 100) value-text id attributes))
  (:group "Feedback")
  (:doc "How far something has come, as a bar with LABEL above it and the value as text
(«3 of 5 steps», else a percentage). Without VALUE the bar goes back and forth, since the
length is unknown. Built on <progress>, which screen readers read themselves.")
  (:source "Basecoat progress (Vega), on the built-in <progress> element")
  (:css "
.tun-progress {
  display: grid;
  gap: calc(var(--spacing) * 2);
  width: 100%;
  & .tun-progress-header {
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    justify-content: space-between;
    column-gap: calc(var(--spacing) * 3);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
  }
  & .tun-progress-label { font-weight: var(--font-weight-medium); }
  & .tun-progress-value {
    margin-inline-start: auto;
    color: var(--muted-foreground);
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }
  & progress {
    display: block;
    appearance: none;
    width: 100%;
    height: calc(var(--spacing) * 1.5);
    overflow: hidden;
    border: 0;
    border-radius: var(--radius-full);
    background-color: var(--muted);
    color: var(--primary);
  }
  & progress::-webkit-progress-bar { background-color: var(--muted); }
  & progress::-webkit-progress-value {
    border-radius: var(--radius-full);
    background-color: var(--primary);
    transition: inline-size var(--duration) var(--ease);
  }
  & progress::-moz-progress-bar {
    border-radius: var(--radius-full);
    background-color: var(--primary);
  }
  /* Indeterminate: a short bar that slides across.  Under reduced motion it
     stands still as stripes over the whole track instead. */
  & progress:indeterminate {
    background-image: linear-gradient(var(--primary), var(--primary));
    background-repeat: no-repeat;
    background-size: 40% 100%;
    background-position: 50% 0;
    animation: tun-progress-slide 1.5s var(--ease) infinite;
    @media (prefers-reduced-motion: reduce) {
      background-image: repeating-linear-gradient(
        -45deg, color-mix(in oklab, var(--primary) 35%, transparent) 0 6px, transparent 6px 12px);
      background-size: auto;
    }
  }
  & progress:indeterminate::-webkit-progress-bar { background-color: transparent; }
  & progress:indeterminate::-moz-progress-bar { background-color: transparent; }
}
@keyframes tun-progress-slide {
  from { background-position: -70% 0; }
  to { background-position: 170% 0; }
}")
  (:examples
   (("With a value" :layout :stack)
    (progress (:label "Importing customers" :value 66))
    (progress (:label "The order is being processed" :value 3 :max 5 :value-text "3 of 5 steps"))
    (progress (:label "Vouchers uploaded" :value 12 :max 12 :value-text "12 of 12 vouchers")))
   (("Unknown length" :layout :stack)
    (progress (:label "Fetching invoices from the ledger")))
   (("A long text on a narrow screen" :layout :stack)
    (progress (:label "Sending reminders to customers with overdue invoices" :value 41
                      :max 180 :value-text "41 of 180 customers"))))
  (check-type label string)
  (check-type max (real (0)))
  (check-type value (or null (real 0)))
  (let ((progress-id (element-id "progress"))
        (text (or value-text (when value (tr "~d%" (round (* 100 value) max))))))
    `(:div ,(attrs (list :class "tun-progress" :id id) attributes)
           (:div (:@ :class "tun-progress-header")
                 (:label (:@ :class "tun-progress-label" :for ,progress-id) ,label)
                 ,@(when text
                     ;; The <progress> itself tells a screen reader the value.
                     `((:span (:@ :class "tun-progress-value" :aria-hidden "true") ,text))))
           (:progress (:@ :id ,progress-id :max ,max :value ,value :aria-valuetext ,value-text)
                      ,text))))

;;; ------------------------------------------------------------------
;;; Spinner

(define-component spinner ((&key (size :default) (label (tr "Loading…")) id attributes)
                           &rest children)
  (:group "Feedback")
  (:doc "A spinning icon while something loads, with role=\"status\". LABEL («Loading…») is
read by screen readers without being shown; the children show as text beside it. With LABEL
nil the spinner is only decoration, for example in a button that already says what is
happening.")
  (:source "Basecoat spinner (Lucide loader-circle)")
  (:css "
.tun-spinner {
  display: inline-flex;
  align-items: center;
  gap: calc(var(--spacing) * 2);
  font-size: var(--text-sm);
  line-height: var(--text-sm--line-height);
  & .tun-icon {
    animation: tun-spinner-spin 0.8s linear infinite;
  }
  &[data-size='sm'] .tun-icon { width: calc(var(--spacing) * 3); height: calc(var(--spacing) * 3); }
  &[data-size='lg'] .tun-icon { width: calc(var(--spacing) * 6); height: calc(var(--spacing) * 6); }
  &[data-size='xl'] .tun-icon { width: calc(var(--spacing) * 8); height: calc(var(--spacing) * 8); }
  & .tun-spinner-text { color: var(--muted-foreground); }
  & .tun-spinner-hidden {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
    white-space: nowrap;
  }
}
@keyframes tun-spinner-spin {
  to { rotate: 1turn; }
}")
  (:examples
   ("Sizes"
    (spinner (:size :sm))
    (spinner ())
    (spinner (:size :lg))
    (spinner (:size :xl)))
   ("With visible text"
    (spinner () "Fetching orders…")
    (spinner (:size :sm) "Processing a payment of €4,990…"))
   ("In a button"
    (button (:disabled t) (spinner (:label nil)) "Saving…")
    (button (:variant :outline :disabled t) (spinner (:label nil)) "Sending invoice…")))
  (check-type size (member :sm :default :lg :xl))
  (check-type label (or null string))
  (let ((announced (or label children)))
    `(:span ,(attrs (list :class "tun-spinner" :id id
                          :data-size (unless (eq size :default) (option-string size))
                          :role (when announced "status")
                          :aria-hidden (unless announced "true"))
                    attributes)
            ,(icon (:name :loader-circle))
            ,@(cond (children `((:span (:@ :class "tun-spinner-text") ,@children)))
                    (label `((:span (:@ :class "tun-spinner-hidden") ,label)))))))

;;; ------------------------------------------------------------------
;;; Skeleton

(defparameter +skeleton-widths+
  '(:full :three-quarters :two-thirds :half :third :quarter :xs :sm :md :lg :xl)
  "The widths a skeleton line or block can have: shares of its container, or
fixed widths from 3rem (:xs) to 16rem (:xl).")

(defparameter +skeleton-heights+ '(:xs :sm :md :lg :xl :2xl)
  "The heights a skeleton shape can have, from 0.75rem (:xs) to 10rem (:2xl).")

(define-component skeleton ((&key (shape :line) width height (direction :column) label
                                  id attributes)
                            &rest children)
  (:group "Feedback")
  (:doc "A grey placeholder in the shape of content that is loading: a line (line), a circle
(circle) or a block (block), with a width and a height from a fixed list. With children it
is a group that stacks the shapes (DIRECTION :column or :row). The shapes are hidden from
screen readers; give the outermost group a LABEL, such as «Loading customers…», so it is
read out.")
  (:source "Basecoat skeleton (Vega)")
  (:css "
.tun-skeleton {
  /* The height keywords set this; a circle uses it for its width too. */
  --tun-skeleton-height: calc(var(--spacing) * 4);
  display: block;
  width: 100%;
  max-width: 100%;
  height: var(--tun-skeleton-height);
  border-radius: var(--radius-md);
  background-color: var(--muted);
  animation: tun-skeleton-pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
  &[data-shape='block'] {
    --tun-skeleton-height: calc(var(--spacing) * 24);
    border-radius: var(--radius-lg);
  }
  &[data-shape='circle'] {
    --tun-skeleton-height: calc(var(--spacing) * 10);
    flex-shrink: 0;
    width: var(--tun-skeleton-height);
    border-radius: var(--radius-full);
  }
  &[data-width='three-quarters'] { width: 75%; }
  &[data-width='two-thirds'] { width: 66.667%; }
  &[data-width='half'] { width: 50%; }
  &[data-width='third'] { width: 33.333%; }
  &[data-width='quarter'] { width: 25%; }
  &[data-width='xs'] { width: 3rem; }
  &[data-width='sm'] { width: 5rem; }
  &[data-width='md'] { width: 8rem; }
  &[data-width='lg'] { width: 12rem; }
  &[data-width='xl'] { width: 16rem; }
  &[data-height='xs'] { --tun-skeleton-height: calc(var(--spacing) * 3); }
  &[data-height='sm'] { --tun-skeleton-height: calc(var(--spacing) * 4); }
  &[data-height='md'] { --tun-skeleton-height: calc(var(--spacing) * 6); }
  &[data-height='lg'] { --tun-skeleton-height: calc(var(--spacing) * 10); }
  &[data-height='xl'] { --tun-skeleton-height: calc(var(--spacing) * 24); }
  &[data-height='2xl'] { --tun-skeleton-height: calc(var(--spacing) * 40); }

  &[data-shape='group'] {
    display: flex;
    flex-direction: column;
    gap: calc(var(--spacing) * 2);
    height: auto;
    border-radius: 0;
    background-color: transparent;
    animation: none;
    &[data-direction='row'] {
      flex-direction: row;
      align-items: center;
      gap: calc(var(--spacing) * 3);
    }
    /* A group in a row takes the room left beside its fixed shapes. */
    &[data-direction='row'] > [data-shape='group'] { flex: 1; min-width: 0; }
  }
  & .tun-skeleton-hidden {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
    white-space: nowrap;
  }
}
@keyframes tun-skeleton-pulse {
  50% { opacity: 0.5; }
}")
  (:examples
   (("Shapes" :layout :stack)
    (skeleton ())
    (skeleton (:width :two-thirds))
    (skeleton (:width :lg :height :xs))
    (skeleton (:shape :circle))
    (skeleton (:shape :block :height :lg))
    (skeleton (:shape :block)))
   (("A card that is loading" :layout :stack)
    (skeleton (:label "Loading the customer…")
              (skeleton (:direction :row)
                        (skeleton (:shape :circle))
                        (skeleton ()
                                  (skeleton (:width :two-thirds))
                                  (skeleton (:width :half :height :xs))))
              (skeleton (:shape :block :height :xl))
              (skeleton (:direction :row)
                        (skeleton (:shape :block :width :sm :height :lg))
                        (skeleton (:shape :block :width :sm :height :lg)))))
   (("Table rows that are loading" :layout :stack)
    (skeleton (:label "Loading orders…")
              (loop repeat 4
                    collect (skeleton (:direction :row)
                                      (skeleton (:width :quarter))
                                      (skeleton (:width :half))
                                      (skeleton (:width :quarter)))))))
  (check-type shape (member :line :circle :block))
  (unless (or (null width) (member width +skeleton-widths+))
    (error "Skeleton :width ~s is not one of ~s" width +skeleton-widths+))
  (unless (or (null height) (member height +skeleton-heights+))
    (error "Skeleton :height ~s is not one of ~s" height +skeleton-heights+))
  (check-type direction (member :column :row))
  (when (and width (eq shape :circle))
    (error "A circle skeleton is as wide as it is high: give it :height, not :width"))
  (if children
      `(:div ,(attrs (list :class "tun-skeleton" :id id :data-shape "group"
                           :data-direction (option-string direction)
                           :role (when label "status")
                           :aria-hidden (unless label "true"))
                     attributes)
             ,@(when label `((:span (:@ :class "tun-skeleton-hidden") ,label)))
             ,@children)
      `(:div ,(attrs (list :class "tun-skeleton" :id id :data-shape (option-string shape)
                           :data-width (option-string width)
                           :data-height (option-string height)
                           :aria-hidden "true")
                     attributes))))
