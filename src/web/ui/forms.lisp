;;;; web/ui/forms.lisp -- the forms group: GOV.UK behaviour, Basecoat look
;;;; (spec/ui.md 6).
;;;;
;;;; Every control is drawn inside a FIELD (or, for a group of choices, a
;;;; FIELDSET): the label above, the hint under the label, the error message
;;;; above the control, as GOV.UK does.  The control carries the component's
;;;; class (tun-text-input, tun-select, ...), and its :ID and :ATTRIBUTES go on
;;;; the control itself, since that is the element labels, hints, errors and
;;;; the error summary point at.

(in-package #:tun.ui)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Tying a control to its label, hint and error

(defun hint-id (id)
  "The id of the hint that describes control ID."
  (format nil "~a-hint" id))

(defun error-id (id)
  "The id of the error message that describes control ID."
  (format nil "~a-error" id))

(defun described-by (id hint error)
  "The aria-describedby value for control ID: its hint's id, its error's id,
or NIL when it has neither."
  (let ((ids (append (when hint (list (hint-id id))) (when error (list (error-id id))))))
    (when ids (format nil "~{~a~^ ~}" ids))))

(defun control-attributes (id &key hint error)
  "The attributes that tie control ID to the FIELD around it, as a property
list for ATTRS: its id, aria-describedby naming the field's hint and error
when it has them, and aria-invalid when it has an error.  HINT and ERROR are
the values given to the field (only whether they are there matters)."
  (list :id id
        :aria-describedby (described-by id hint error)
        :aria-invalid (when error "true")))

(export 'control-attributes)

(defun require-label (component label &optional (option :label))
  "Signal an error unless LABEL, COMPONENT's OPTION, is given: every control
is labelled (spec/ui.md 5)."
  (when (or (null label) (and (stringp label) (zerop (length (string-trim " " label)))))
    (error "~(~a~) needs ~s: every control has a label (spec/ui.md 5)" component option)))

(defun hint-markup (class id hint)
  (when hint
    `(:p (:@ :class ,class :id ,(hint-id id)) ,hint)))

(defun error-markup (class id error)
  "GOV.UK's error message: an icon, a prefix only screen readers hear, the text."
  (when error
    `(:p (:@ :class ,class :id ,(error-id id))
         ,(icon (:name :circle-alert :size :sm))
         (:span (:span (:@ :class ,(format nil "~a-prefix" class)) ,(tr "Error:")) " " ,error))))

(defun optional-markup (class optional)
  (when optional
    `(:span (:@ :class ,class) " " ,(tr "(optional)"))))

(defun same-value-p (a b)
  "True when option values A and B are the same, whether given as strings,
numbers or keywords."
  (and a b (string= (princ-to-string a) (princ-to-string b))))

;;; ------------------------------------------------------------------
;;; CSS shared by several components
;;;
;;; A component's CSS starts at its own root class, so CSS that several
;;; components need is written once here and spliced into each.  In a
;;; template, $ stands for the class prefix of the component's parts.

(defun css-template (template prefix)
  "TEMPLATE with every $ replaced by PREFIX."
  (with-output-to-string (out)
    (loop for char across template
          do (if (char= char #\$) (write-string prefix out) (write-char char out)))))

(defparameter +control-border+ "color-mix(in oklab, var(--foreground) 45%, var(--background))"
  "The border of a control.  Basecoat's --input is a decoration colour (1.2:1 on
the page); the edge of a text box, a checkbox or a switch shows where the
control is, so it needs 3:1 against the page (WCAG 1.4.11).  This mix gives
about 3.6:1 in both themes.")

(defparameter +visually-hidden-css+ "
    position: absolute;
    width: 1px;
    height: 1px;
    margin: 0;
    padding: 0;
    overflow: hidden;
    clip-path: inset(50%);
    border: 0;
    white-space: nowrap;
    user-select: none;"
  "Hide an element on the screen but not from screen readers (GOV.UK).")

(defparameter +invalid-ring+
  "0 0 0 3px light-dark(color-mix(in oklab, var(--destructive) 20%, transparent),
                       color-mix(in oklab, var(--destructive) 40%, transparent))"
  "The ring around a control with an error (Basecoat's aria-invalid ring).")

(defun message-css (prefix)
  "The hint and the error message of a component whose parts start with PREFIX."
  (css-template (concatenate 'string "
  & .$-hint {
    color: var(--muted-foreground);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
  }
  & .$-error {
    display: flex;
    align-items: flex-start;
    gap: calc(var(--spacing) * 1.5);
    color: var(--destructive);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    font-weight: var(--font-weight-medium);
    & > .tun-icon { margin-top: calc((1lh - var(--spacing) * 3.5) / 2); }
  }
  & .$-error-prefix {" +visually-hidden-css+ "
  }")
                prefix))

(defun control-css (&key (focus "&:focus-visible") (invalid "&[aria-invalid='true']")
                      (disabled "&:disabled"))
  "The surface of a text box, a select or an input group (Basecoat input,
Vega): declarations, then rules for the states.  FOCUS, INVALID and DISABLED
are the selectors of those states."
  (format nil "
  border: 1px solid ~a;
  border-radius: var(--radius-md);
  background-color: light-dark(var(--background),
                               color-mix(in oklab, var(--input) 30%, transparent));
  color: var(--foreground);
  font-size: var(--control-font-size);
  box-shadow: var(--shadow-xs);
  outline: none;
  transition-property: color, border-color, box-shadow;
  transition-duration: var(--duration-fast);
  transition-timing-function: var(--ease);
  ~a { border-color: var(--ring); box-shadow: var(--focus-ring); }
  ~a {
    border-color: light-dark(var(--destructive),
                             color-mix(in oklab, var(--destructive) 50%, transparent));
    box-shadow: ~a;
  }
  ~a { cursor: not-allowed; opacity: 0.5; }"
          +control-border+ focus invalid +invalid-ring+ disabled))

(defun choice-css (prefix)
  "The rows of a list of checkboxes or radio buttons whose parts start with
PREFIX: a label that takes the whole row, so the target is large (a control's
height, 44px on a touch screen), the box at the start of its first line, and
the hint under the text."
  (css-template (concatenate 'string "
  --tun-choice-size: calc(var(--spacing) * 4);
  @media (pointer: coarse) { --tun-choice-size: calc(var(--spacing) * 5); }
  & .$-label {
    display: flex;
    align-items: flex-start;
    gap: calc(var(--spacing) * 2.5);
    width: fit-content;
    max-width: 100%;
    padding-block: calc((var(--control-height) - 1lh) / 2);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    cursor: pointer;
    touch-action: manipulation;
    &:has(> :disabled) { cursor: not-allowed; color: var(--muted-foreground); }
  }
  & .$-input {
    appearance: none;
    display: flex;
    flex-shrink: 0;
    align-items: center;
    justify-content: center;
    width: var(--tun-choice-size);
    height: var(--tun-choice-size);
    margin-top: calc((1lh - var(--tun-choice-size)) / 2);
    border: 1px solid " +control-border+ ";
    background-color: light-dark(var(--background),
                                 color-mix(in oklab, var(--input) 30%, transparent));
    box-shadow: var(--shadow-xs);
    outline: none;
    cursor: inherit;
    transition-property: background-color, border-color, box-shadow;
    transition-duration: var(--duration-fast);
    transition-timing-function: var(--ease);
    &:checked { border-color: var(--primary); background-color: var(--primary);
      color: var(--primary-foreground); }
    &:focus-visible { border-color: var(--ring); box-shadow: var(--focus-ring); }
    &[aria-invalid='true']:not(:checked) { border-color: var(--destructive); }
    &[aria-invalid='true'] { box-shadow: " +invalid-ring+ "; }
    &:disabled { opacity: 0.5; }
  }
  & .$-hint {
    margin-top: calc((1lh - var(--control-height)) / 2 + var(--spacing) * 0.5);
    padding-left: calc(var(--tun-choice-size) + var(--spacing) * 2.5);
    color: var(--muted-foreground);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
  }")
                prefix))

;;; ------------------------------------------------------------------
;;; Field

(define-component field ((&key label for hint error optional label-hidden id attributes)
                         &rest children)
  (:group "Forms")
  (:doc "The frame around every control: the label at the top, the hint under it, the error
message above the control, tied together with for, aria-describedby and aria-invalid
(control-attributes gives a control of your own the same attributes). As at GOV.UK, required
fields are not marked with a star; ask only for what you need, and mark the few optional
fields «(optional)» with OPTIONAL.")
  (:source "GOV.UK form group, label, hint and error message; Basecoat field (Vega)")
  (:css (concatenate 'string "
.tun-field {
  display: flex;
  flex-direction: column;
  gap: calc(var(--spacing) * 2);
  min-width: 0;
  max-width: 40rem;
  & > .tun-field-label {
    width: fit-content;
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    font-weight: var(--font-weight-medium);
    &[data-hidden] {" +visually-hidden-css+ "
    }
  }
  & .tun-field-optional {
    color: var(--muted-foreground);
    font-weight: var(--font-weight-normal);
  }
  & > .tun-field-hint { margin-top: calc(var(--spacing) * -1); }
  &:has(:is(input, select, textarea):disabled) > .tun-field-label { opacity: 0.5; }"
    (message-css "tun-field") "
}"))
  (:examples
   (("With a control of its own" :layout :stack)
    (field (:label "Attachment" :for "order-attachment" :optional t
                   :hint "A PDF or an image, at most 10 MB.")
      `(:input ,(attrs (list :type "file" :name "attachment" :accept "application/pdf,image/*")
                       (control-attributes "order-attachment" :hint t)))))
   (("A control of its own with an error" :layout :stack)
    (field (:label "Attachment" :for "quote-attachment" :hint "A PDF or an image, at most 10 MB."
                   :error "The file is larger than 10 MB")
      `(:input ,(attrs (list :type "file" :name "attachment" :accept "application/pdf,image/*")
                       (control-attributes "quote-attachment" :hint t :error t))))))
  (require-label 'field label)
  (unless for
    (error "field needs :for, the id of the control it labels"))
  `(:div ,(attrs (list :class "tun-field" :id id :data-invalid (when error "true"))
                 attributes)
         (:label ,(attrs (list :class "tun-field-label" :for for
                               :data-hidden (when label-hidden "true")))
                 ,label ,(optional-markup "tun-field-optional" optional))
         ,(hint-markup "tun-field-hint" for hint)
         ,(error-markup "tun-field-error" for error)
         ,@children))

;;; ------------------------------------------------------------------
;;; Text input

(defparameter +text-input-types+
  '("text" "email" "tel" "number" "password" "date" "search" "url"))

(defparameter +text-input-widths+ '(2 3 4 5 10 20 30)
  "GOV.UK's fixed widths, in characters, for a value of a known length.")

(defun text-input-markup (class id &key type name value hint error required placeholder
                                     autocomplete inputmode disabled readonly width
                                     attributes)
  "The <input> of TEXT-INPUT and INPUT-GROUP, with class CLASS and id ID."
  (let ((type (option-string type)))
    (unless (member type +text-input-types+ :test #'string=)
      (error "~s is not a text input type; use one of ~{~a~^, ~}" type +text-input-types+))
    `(:input ,(attrs (list :class class :type type :name name :value value
                           :placeholder placeholder :autocomplete autocomplete
                           :inputmode inputmode
                           ;; GOV.UK: spelling suggestions only get in the way of an address.
                           :spellcheck (when (string= type "email") "false")
                           :required required :disabled disabled :readonly readonly
                           :data-width (when width (princ-to-string width)))
                     (control-attributes id :hint hint :error error)
                     attributes))))

(defun check-width (width)
  (unless (or (null width) (eq width :full) (member width +text-input-widths+))
    (error "~s is not a width; use :full or one of ~{~a~^, ~} characters"
           width +text-input-widths+)))

(define-component text-input ((&key label name value (type :text) hint error required optional
                                    label-hidden placeholder autocomplete inputmode width
                                    disabled readonly id attributes))
  (:group "Forms")
  (:doc "A text box for one line: text, email, phone, number, password, date, search or web
address. Give WIDTH (a number of characters: 2, 3, 4, 5, 10, 20 or 30) when the answer has a
known length, such as a postcode (4) or an organisation number (10); use AUTOCOMPLETE only
when users fill in their own details.")
  (:source "Basecoat input (Vega); GOV.UK text input, its widths and its behaviour")
  (:css (concatenate 'string "
.tun-text-input {
  display: block;
  width: 100%;
  min-width: 0;
  height: var(--control-height);
  padding: var(--spacing) calc(var(--spacing) * 2.5);"
                     (control-css) "
  &::placeholder { color: var(--muted-foreground); }
  &:read-only:not(:disabled) {
    background-color: color-mix(in oklab, var(--muted) 60%, transparent);
    box-shadow: none;
  }
  /* GOV.UK's fixed widths: the characters, the padding and the border, and
     one character more for the browser's autofill icon. */
  &[data-width='2'] { max-width: calc(3ch + var(--spacing) * 5 + 2px); }
  &[data-width='3'] { max-width: calc(4ch + var(--spacing) * 5 + 2px); }
  &[data-width='4'] { max-width: calc(5ch + var(--spacing) * 5 + 2px); }
  &[data-width='5'] { max-width: calc(6ch + var(--spacing) * 5 + 2px); }
  &[data-width='10'] { max-width: calc(11ch + var(--spacing) * 5 + 2px); }
  &[data-width='20'] { max-width: calc(21ch + var(--spacing) * 5 + 2px); }
  &[data-width='30'] { max-width: calc(31ch + var(--spacing) * 5 + 2px); }
  /* A date has a known length too, and the browser's calendar button. */
  &[type='date'] { max-width: calc(12ch + var(--spacing) * 11 + 2px); }
}"))
  (:examples
   (("With and without a hint" :layout :stack)
    (text-input (:label "Customer name" :name "name"))
    (text-input (:label "Email" :name "email" :type :email
                        :hint "The invoice is sent here. A shared address is a good choice.")))
   (("With an error" :layout :stack)
    (text-input (:label "Phone" :name "phone" :type :tel :width 20 :value "912 34"
                        :error "The phone number must have 8 digits, like 912 34 567")))
   (("An optional field" :layout :stack)
    (text-input (:label "The customer's reference" :name "reference" :optional t
                        :hint "Shown on the invoice, such as “Project 1042” or a buyer's name.")))
   (("Fixed widths" :layout :stack)
    (text-input (:label "Postcode" :name "postcode" :width 4 :inputmode "numeric"))
    (text-input (:label "Organisation number" :name "orgno" :width 10 :inputmode "numeric"))
    (text-input (:label "Town" :name "town" :width 20))
    (text-input (:label "Invoice address, line 1" :name "address" :width 30)))
   (("Types" :layout :stack)
    (text-input (:label "Delivery date" :name "delivery-date" :type :date))
    (text-input (:label "Number of hours" :name "hours" :type :number :width 5
                        :attributes '(:min 0 :step "0.5")))
    (text-input (:label "Website" :name "website" :type :url
                        :placeholder "https://www.company.example"))
    (text-input (:label "Password" :name "password" :type :password
                        :autocomplete "current-password")))
   (("Disabled and read-only" :layout :stack)
    (text-input (:label "Customer number" :name "customer-number" :value "10234" :readonly t
                        :width 10 :hint "Set by Tun when the customer is saved."))
    (text-input (:label "Amount invoiced" :name "amount" :value "€12,500" :disabled t
                        :width 20))))
  (require-label 'text-input label)
  (check-width width)
  (let ((id (or id (element-id (or name "input")))))
    (field* (list :label label :for id :hint hint :error error :optional optional
                  :label-hidden label-hidden)
            (text-input-markup "tun-text-input" id
                               :type type :name name :value value :hint hint :error error
                               :required required :placeholder placeholder
                               :autocomplete autocomplete :inputmode inputmode
                               :disabled disabled :readonly readonly
                               :width (unless (eq width :full) width)
                               :attributes attributes))))

;;; ------------------------------------------------------------------
;;; Textarea

(define-component textarea ((&key label name value (rows 5) hint error required optional
                                  label-hidden placeholder disabled readonly id attributes))
  (:group "Forms")
  (:doc "A text box for several lines, such as a note or a description of the job. ROWS
gives the height in lines; the user can make the box taller.")
  (:source "Basecoat textarea (Vega); GOV.UK textarea")
  (:css (concatenate 'string "
.tun-textarea {
  display: block;
  width: 100%;
  min-width: 0;
  min-height: calc(var(--spacing) * 16);
  padding: calc(var(--spacing) * 2) calc(var(--spacing) * 2.5);
  line-height: var(--text-base--line-height);
  resize: vertical;"
                     (control-css) "
  &::placeholder { color: var(--muted-foreground); }
  &:read-only:not(:disabled) {
    background-color: color-mix(in oklab, var(--muted) 60%, transparent);
    box-shadow: none;
  }
}"))
  (:examples
   (("With a hint" :layout :stack)
    (textarea (:label "Description of the job" :name "description"
                      :hint "What is to be done, where, and when the customer wants it done.")))
   (("With an error" :layout :stack)
    (textarea (:label "Description of the job" :name "description" :rows 3
                      :value "Paint"
                      :error "The description must have at least 20 characters")))
   (("Optional and disabled" :layout :stack)
    (textarea (:label "Internal note" :name "note" :optional t :rows 3
                      :placeholder "Seen only by you"))
    (textarea (:label "The customer's comment" :name "comment" :rows 3 :disabled t
                      :value "Deliver at the back of the building, call 40 00 00 00 on arrival."))))
  (require-label 'textarea label)
  (let ((id (or id (element-id (or name "textarea")))))
    (field* (list :label label :for id :hint hint :error error :optional optional
                  :label-hidden label-hidden)
            `(:textarea ,(attrs (list :class "tun-textarea" :name name :rows rows
                                      :placeholder placeholder :required required
                                      :disabled disabled :readonly readonly)
                                (control-attributes id :hint hint :error error)
                                attributes)
                        ,(or value "")))))

;;; ------------------------------------------------------------------
;;; Select

(defun option-markup (option selected)
  "OPTION, (VALUE LABEL &key DISABLED), as an <option>."
  (destructuring-bind (value label &key disabled) option
    `(:option ,(attrs (list :value (princ-to-string value)
                            :selected (same-value-p value selected)
                            :disabled disabled))
              ,label)))

(define-component select ((&key label name options selected prompt hint error required
                                optional label-hidden disabled id attributes))
  (:group "Forms")
  (:doc "A drop-down list, the browser's own, for choosing one of many known answers. OPTIONS
is a list of (VALUE TEXT) or (VALUE TEXT :disabled t); PROMPT gives an empty first choice.
When the list has five choices or fewer, radios are better: the user then sees every
answer.")
  (:source "Basecoat native select (Vega); GOV.UK select")
  (:css (concatenate 'string "
.tun-select {
  position: relative;
  display: block;
  width: 100%;
  min-width: 0;
  & > select {
    appearance: none;
    display: block;
    width: 100%;
    min-width: 0;
    height: var(--control-height);
    padding: var(--spacing) calc(var(--spacing) * 9) var(--spacing) calc(var(--spacing) * 2.5);
    text-overflow: ellipsis;"
                     (control-css) "
    & option, & optgroup { background-color: Canvas; color: CanvasText; }
    &:has(> option[value='']:checked) { color: var(--muted-foreground); }
  }
  & > .tun-icon {
    position: absolute;
    top: 50%;
    right: calc(var(--spacing) * 2.5);
    translate: 0 -50%;
    color: var(--muted-foreground);
  }
  &:has(> select:disabled) > .tun-icon { opacity: 0.5; }
}"))
  (:examples
   (("With an empty first choice" :layout :stack)
    (select (:label "Payment terms" :name "payment-terms" :prompt "Choose the terms"
                    :options '(("10" "10 days") ("14" "14 days") ("30" "30 days")
                               ("cash" "Cash on delivery" :disabled t)))))
   (("A chosen value and a hint" :layout :stack)
    (select (:label "VAT rate" :name "vat" :selected 25
                    :hint "Applies to every line of the invoice."
                    :options '((25 "25% – the standard rate") (15 "15% – food and drink")
                               (12 "12% – passenger transport and accommodation")
                               (0 "0% – exempt")))))
   (("With an error" :layout :stack)
    (select (:label "Responsible salesperson" :name "seller" :prompt "Choose a salesperson"
                    :error "Choose who is responsible for the customer"
                    :options '(("kari" "Kari Nordmann") ("ola" "Ola Hansen")
                               ("fatima" "Fatima Ali")))))
   (("Disabled" :layout :stack)
    (select (:label "Warehouse" :name "warehouse" :selected "drammen" :disabled t
                    :options '(("drammen" "Drammen") ("oslo" "Oslo"))))))
  (require-label 'select label)
  (let ((id (or id (element-id (or name "select")))))
    (field* (list :label label :for id :hint hint :error error :optional optional
                  :label-hidden label-hidden)
            `(:div (:@ :class "tun-select")
                   (:select ,(attrs (list :name name :required required :disabled disabled)
                                    (control-attributes id :hint hint :error error)
                                    attributes)
                            ,@(when prompt
                                `((:option (:@ :value "") ,prompt)))
                            ,@(mapcar (lambda (option) (option-markup option selected))
                                      options))
                   ,(icon (:name :chevron-down))))))

;;; ------------------------------------------------------------------
;;; Fieldset

(define-component fieldset ((&key legend (legend-size :default) hint error optional disabled
                                  id attributes)
                            &rest children)
  (:group "Forms")
  (:doc "Gathers fields that belong together under a heading (legend), such as an address,
and goes around checkboxes and radios. LEGEND-SIZE :page makes the heading the page's h1 when
the group is the whole question on the page, :section a subheading in a long form.")
  (:source "GOV.UK fieldset; Basecoat fieldset (Vega)")
  (:css (concatenate 'string "
.tun-fieldset {
  min-width: 0;
  max-width: 40rem;
  & > .tun-fieldset-legend {
    max-width: 100%;
    margin-bottom: calc(var(--spacing) * 2);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    font-weight: var(--font-weight-medium);
  }
  &[data-size='section'] > .tun-fieldset-legend {
    margin-bottom: calc(var(--spacing) * 4);
    font-size: var(--text-lg);
    line-height: var(--text-lg--line-height);
    font-weight: var(--font-weight-semibold);
  }
  &[data-size='page'] > .tun-fieldset-legend { margin-bottom: calc(var(--spacing) * 6); }
  &:not([data-size='default']) > .tun-fieldset-legend:has(+ .tun-fieldset-hint) {
    margin-bottom: calc(var(--spacing) * 2);
  }
  & .tun-fieldset-optional {
    color: var(--muted-foreground);
    font-weight: var(--font-weight-normal);
  }
  & > .tun-fieldset-hint, & > .tun-fieldset-error { margin-bottom: calc(var(--spacing) * 2); }
  &[data-size='page'] > .tun-fieldset-hint { margin-bottom: calc(var(--spacing) * 4); }
  &[data-size='section'] > .tun-fieldset-hint { margin-bottom: calc(var(--spacing) * 4); }
  & > .tun-fieldset-body {
    display: flex;
    flex-direction: column;
    gap: calc(var(--spacing) * 6);
  }
  &:disabled > .tun-fieldset-legend { opacity: 0.5; }"
                     (message-css "tun-fieldset") "
}"))
  (:examples
   (("An address as part of a form" :layout :stack)
    (fieldset (:legend "Invoice address" :legend-size :section
                       :hint "Where the customer wants the invoice, if it is sent by post.")
      (text-input (:label "Street address" :name "street-address" :autocomplete "off"))
      (text-input (:label "Postcode" :name "postcode" :width 4 :inputmode "numeric"))
      (text-input (:label "Town" :name "town" :width 20))))
   (("As the page's title" :layout :stack)
    (fieldset (:legend "Where should the goods be delivered?" :legend-size :page
                       :hint "We deliver all over Norway, but not to a PO box.")
      (text-input (:label "Street address" :name "delivery-address"))
      (text-input (:label "Postcode" :name "delivery-postcode" :width 4
                          :inputmode "numeric"))
      (text-input (:label "Town" :name "delivery-town" :width 20))))
   (("With an error for the whole group" :layout :stack)
    (fieldset (:legend "Contact" :error "Fill in a phone number or an email, or both")
      (text-input (:label "Phone" :name "contact-phone" :type :tel :width 20))
      (text-input (:label "Email" :name "contact-email" :type :email))))
   (("Disabled" :layout :stack)
    (fieldset (:legend "Delivery address" :legend-size :section :disabled t
                       :hint "The same as the invoice address.")
      (text-input (:label "Street address" :name "address" :value "Storgata 12"))
      (text-input (:label "Postcode" :name "postcode" :value "3015" :width 4)))))
  (require-label 'fieldset legend :legend)
  (check-type legend-size (member :default :section :page))
  (let ((base (or id (element-id "fieldset"))))
    `(:fieldset ,(attrs (list :class "tun-fieldset" :id id
                              :data-size (option-string legend-size)
                              :data-invalid (when error "true")
                              :aria-describedby (described-by base hint error)
                              :disabled disabled)
                        attributes)
       (:legend (:@ :class "tun-fieldset-legend")
                ,@(let ((text (list legend (optional-markup "tun-fieldset-optional"
                                                            optional))))
                    (if (eq legend-size :page) `((:h1 ,@text)) text)))
       ,(hint-markup "tun-fieldset-hint" base hint)
       ,(error-markup "tun-fieldset-error" base error)
       (:div (:@ :class "tun-fieldset-body") ,@children))))

;;; ------------------------------------------------------------------
;;; Checkbox, checkboxes and radios

(define-component checkbox ((&key label name (value "true") checked hint error required
                                  disabled id attributes))
  (:group "Forms")
  (:doc "One checkbox with its text beside it, for a yes/no field or «I agree …». The whole
row is the target. The error message stands above the box.")
  (:source "Basecoat checkbox (Vega); GOV.UK checkboxes with one item")
  (:css (concatenate 'string "
.tun-checkbox {
  display: flex;
  flex-direction: column;
  min-width: 0;"
                     (choice-css "tun-checkbox") "
  & .tun-checkbox-input {
    border-radius: 4px;
    /* The tick is two borders of a box turned 45 degrees (GOV.UK), so it
       takes the colour of the text in both themes. */
    &:checked::after {
      content: '';
      width: 56%;
      height: 30%;
      border: solid currentColor;
      border-width: 0 0 2px 2px;
      translate: 0 -20%;
      rotate: -45deg;
    }
  }"
                     (message-css "tun-checkbox") "
  & > .tun-checkbox-error { margin-bottom: calc(var(--spacing) * 0.5); }
}"))
  (:examples
   ("Plain"
    (checkbox (:label "The customer wants the newsletter by email" :name "newsletter")))
   (("With a hint" :layout :stack)
    (checkbox (:label "Send an order confirmation to the customer" :name "confirmation"
                      :checked t :hint "Sent to post@example.com when the order is saved.")))
   (("With an error" :layout :stack)
    (checkbox (:label "I have read and agree to the terms of the job" :name "terms"
                      :error "You must agree to the terms before you can send the quote")))
   ("Disabled"
    (checkbox (:label "Invoice sent" :name "sent" :checked t :disabled t))
    (checkbox (:label "Reminder sent" :name "reminded" :disabled t))))
  (require-label 'checkbox label)
  (let ((id (or id (element-id (or name "checkbox")))))
    `(:div ,(attrs (list :class "tun-checkbox" :data-invalid (when error "true")))
           ,(error-markup "tun-checkbox-error" id error)
           (:label (:@ :class "tun-checkbox-label" :for ,id)
                   (:input ,(attrs (list :class "tun-checkbox-input" :type "checkbox"
                                         :name name :value value :checked checked
                                         :required required :disabled disabled)
                                   (control-attributes id :hint hint :error error)
                                   attributes))
                   (:span ,label))
           ,(hint-markup "tun-checkbox-hint" id hint))))

(defun choice-ids (id count)
  "The ids of COUNT choices: ID for the first, so the error summary can link
to it, then ID-2, ID-3 ... (GOV.UK)."
  (loop for n from 1 to count
        collect (if (= n 1) id (format nil "~a-~d" id n))))

(defun check-choices (component choices)
  (when (null choices)
    (error "~(~a~) needs :choices, a list of (VALUE LABEL &key HINT DISABLED)" component))
  (dolist (choice choices)
    (destructuring-bind (value label &key hint disabled) choice
      (declare (ignore value hint disabled))
      (require-label component label "a label for each choice"))))

(define-component checkboxes ((&key legend name choices selected hint error inline optional
                                    (legend-size :default) disabled id attributes))
  (:group "Forms")
  (:doc "A group of checkboxes under a heading, where the user can choose several. CHOICES
is a list of (VALUE TEXT &key HINT DISABLED) and SELECTED a list of the chosen values; INLINE
puts short choices on one line. ID goes to the first box, which the error summary links
to.")
  (:source "GOV.UK checkboxes; Basecoat checkbox (Vega)")
  (:css "
.tun-checkboxes {
  display: flex;
  flex-direction: column;
  &[data-inline] { flex-direction: row; flex-wrap: wrap; column-gap: calc(var(--spacing) * 6); }
  & > .tun-checkbox:has(> .tun-checkbox-hint):not(:last-child) {
    padding-bottom: calc(var(--spacing) * 2);
  }
  &[data-invalid] .tun-checkbox-input:not(:checked) { border-color: var(--destructive); }
}")
  (:examples
   (("With hints" :layout :stack)
    (checkboxes (:legend "How does the customer want the invoice?" :name "invoice-channel"
                         :hint "Choose all that apply." :selected '("ehf")
                         :choices '(("ehf" "EHF" :hint "Straight into the customer's ledger.")
                                    ("email" "Email with a PDF")
                                    ("paper" "Paper by post" :hint "A fee of €5 per invoice.")))))
   (("On one line" :layout :stack)
    (checkboxes (:legend "Which days can we come?" :name "days" :inline t
                         :selected '("mon" "wed")
                         :choices '(("mon" "Mon") ("tue" "Tue") ("wed" "Wed") ("thu" "Thu")
                                    ("fri" "Fri")))))
   (("With an error" :layout :stack)
    (checkboxes (:legend "Which services does the job cover?" :name "services"
                         :id "job-services" :error "Choose at least one service"
                         :choices '(("painting" "Painting") ("wallpapering" "Wallpapering")
                                    ("carpentry" "Carpentry")))))
   (("A disabled choice" :layout :stack)
    (checkboxes (:legend "Notifications by email" :name "notifications" :optional t
                         :selected '("order")
                         :choices '(("order" "New order") ("payment" "Payment received")
                                    ("sms" "SMS on a delay" :disabled t
                                     :hint "Needs the SMS module.")))))
   (("The whole group disabled" :layout :stack)
    (checkboxes (:legend "Delivery days" :name "delivery" :inline t :disabled t
                         :selected '("tue")
                         :choices '(("mon" "Mon") ("tue" "Tue") ("wed" "Wed"))))))
  (require-label 'checkboxes legend :legend)
  (check-choices 'checkboxes choices)
  (let ((ids (choice-ids (or id (element-id (or name "checkboxes"))) (length choices))))
    (fieldset* (list :legend legend :legend-size legend-size :hint hint :error error
                     :optional optional :disabled disabled :attributes attributes)
               `(:div ,(attrs (list :class "tun-checkboxes" :data-inline (when inline "true")
                                    :data-invalid (when error "true")))
                      ,@(loop for choice in choices
                              for choice-id in ids
                              collect (destructuring-bind (value label &key hint disabled) choice
                                        (checkbox*
                                         (list :label label :name name
                                               :value (princ-to-string value) :id choice-id
                                               :hint hint :disabled disabled
                                               :checked (and (member value selected
                                                                     :test #'same-value-p)
                                                             t)))))))))

(defun radio-markup (choice id name selected required)
  "One radio button of RADIOS: CHOICE is (VALUE LABEL &key HINT DISABLED)."
  (destructuring-bind (value label &key hint disabled) choice
    `(:div (:@ :class "tun-radios-item")
           (:label (:@ :class "tun-radios-label" :for ,id)
                   (:input ,(attrs (list :class "tun-radios-input" :type "radio" :id id
                                         :name name :value (princ-to-string value)
                                         :checked (same-value-p value selected)
                                         :required required :disabled disabled
                                         :aria-describedby (when hint (hint-id id)))))
                   (:span ,label))
           ,(hint-markup "tun-radios-hint" id hint))))

(define-component radios ((&key legend name choices selected hint error inline optional
                                (legend-size :default) disabled required id attributes))
  (:group "Forms")
  (:doc "A group of radio buttons under a heading, where the user chooses one answer.
CHOICES is a list of (VALUE TEXT &key HINT DISABLED) and SELECTED the chosen value; INLINE
puts short choices such as Yes and No on one line. ID goes to the first button, which the
error summary links to.")
  (:source "GOV.UK radios; Basecoat radio group (Vega)")
  (:css (concatenate 'string "
.tun-radios {
  display: flex;
  flex-direction: column;
  &[data-inline] { flex-direction: row; flex-wrap: wrap; column-gap: calc(var(--spacing) * 6); }
  & > .tun-radios-item { display: flex; flex-direction: column; min-width: 0; }
  & > .tun-radios-item:has(> .tun-radios-hint):not(:last-child) {
    padding-bottom: calc(var(--spacing) * 2);
  }"
                     (choice-css "tun-radios") "
  & .tun-radios-input {
    border-radius: var(--radius-full);
    &:checked::before {
      content: '';
      width: calc(var(--tun-choice-size) / 2);
      height: calc(var(--tun-choice-size) / 2);
      border-radius: var(--radius-full);
      background-color: currentColor;
    }
  }
  &[data-invalid] .tun-radios-input { border-color: var(--destructive); }
}"))
  (:examples
   (("With hints" :layout :stack)
    (radios (:legend "Kind of customer" :name "customer-kind" :selected "business"
                     :choices '(("business" "Business" :hint "Invoiced by EHF.")
                                ("private" "Private person")
                                ("public" "Public body"
                                 :hint "Invoiced by EHF with an order number.")))))
   (("Yes and no on one line" :layout :stack)
    (radios (:legend "Should the order be invoiced now?" :name "invoice" :inline t
                     :choices '(("yes" "Yes") ("no" "No")))))
   (("With an error" :layout :stack)
    (radios (:legend "How should the goods be delivered?" :name "delivery" :id "order-delivery"
                     :error "Choose how the goods should be delivered"
                     :choices '(("collect" "The customer collects them")
                                ("courier" "Courier the same day")
                                ("post" "By post, 2–4 working days")))))
   (("As the page's title" :layout :stack)
    (radios (:legend "What kind of job is this?" :legend-size :page :name "job-kind"
                     :hint "You can change it later."
                     :choices '(("fixed" "Fixed price" :hint "The customer pays an agreed sum.")
                                ("hours" "By time spent"
                                 :hint "The customer pays for hours and materials.")))))
   (("A disabled choice" :layout :stack)
    (radios (:legend "Payment" :name "payment" :selected "invoice"
                     :choices '(("invoice" "Invoice")
                                ("card" "Card in the shop")
                                ("vipps" "Vipps" :disabled t :hint "Not set up yet."))))))
  (require-label 'radios legend :legend)
  (check-choices 'radios choices)
  (let ((ids (choice-ids (or id (element-id (or name "radios"))) (length choices))))
    (fieldset* (list :legend legend :legend-size legend-size :hint hint :error error
                     :optional optional :disabled disabled :attributes attributes)
               `(:div ,(attrs (list :class "tun-radios" :data-inline (when inline "true")
                                    :data-invalid (when error "true")))
                      ,@(loop for choice in choices
                              for choice-id in ids
                              collect (radio-markup choice choice-id name selected
                                                    required))))))

;;; ------------------------------------------------------------------
;;; Switch

(define-component switch ((&key label name (value "true") checked description disabled
                                id attributes))
  (:group "Forms")
  (:doc "An on/off switch for a setting that applies at once or when the form is saved, with
the text on the left and the switch on the right. Use checkbox when the answer is a yes to
something, such as agreeing to terms.")
  (:source "Basecoat switch (Vega); a checkbox with role switch")
  (:css (concatenate 'string "
.tun-switch {
  --tun-switch-width: calc(var(--spacing) * 8);
  --tun-switch-thumb: calc(var(--spacing) * 4);
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  align-items: center;
  column-gap: calc(var(--spacing) * 4);
  max-width: 40rem;
  @media (pointer: coarse) {
    --tun-switch-width: calc(var(--spacing) * 11);
    --tun-switch-thumb: calc(var(--spacing) * 5.5);
  }
  & > .tun-switch-label {
    grid-column: 1;
    padding-block: calc((var(--control-height) - 1lh) / 2);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    font-weight: var(--font-weight-medium);
    cursor: pointer;
    touch-action: manipulation;
  }
  & > .tun-switch-description {
    grid-column: 1;
    margin-top: calc((1lh - var(--control-height)) / 2);
    color: var(--muted-foreground);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
  }
  & > .tun-switch-input {
    grid-column: 2;
    grid-row: 1 / span 2;
    appearance: none;
    display: inline-flex;
    flex-shrink: 0;
    align-items: center;
    width: var(--tun-switch-width);
    height: calc(var(--tun-switch-thumb) + 2.4px);
    border: 1px solid transparent;
    border-radius: var(--radius-full);
    background-color: " +control-border+ ";
    box-shadow: var(--shadow-xs);
    outline: none;
    cursor: pointer;
    transition-property: background-color, box-shadow;
    transition-duration: var(--duration-fast);
    transition-timing-function: var(--ease);
    &::before {
      content: '';
      display: block;
      width: var(--tun-switch-thumb);
      height: var(--tun-switch-thumb);
      border-radius: var(--radius-full);
      background-color: light-dark(var(--background), var(--foreground));
      pointer-events: none;
      transition: translate var(--duration) var(--ease);
    }
    &:checked { background-color: var(--primary); }
    &:checked::before {
      translate: calc(var(--tun-switch-width) - var(--tun-switch-thumb) - 2px) 0;
      background-color: light-dark(var(--background), var(--primary-foreground));
    }
    &:focus-visible { border-color: var(--ring); box-shadow: var(--focus-ring); }
    &:disabled { cursor: not-allowed; opacity: 0.5; }
  }
  &:has(> :disabled) > :is(.tun-switch-label, .tun-switch-description) { opacity: 0.5; }
  &:has(> :disabled) > .tun-switch-label { cursor: not-allowed; }
}"))
  (:examples
   (("With a description" :layout :stack)
    (switch (:label "Send reminders of unpaid invoices" :name "reminders" :checked t
                    :description "The customer is emailed 3 and 10 days after the due date."))
    (switch (:label "Show prices with VAT" :name "with-vat"
                    :description "Applies only to what you see, not to the invoices.")))
   (("Without a description" :layout :stack)
    (switch (:label "Take orders online" :name "online-orders" :checked t)))
   (("Disabled" :layout :stack)
    (switch (:label "Automatic reminders" :name "auto-reminders" :disabled t
                    :description "Needs the invoicing module to be turned on."))
    (switch (:label "A backup every night" :name "backup" :checked t :disabled t))))
  (require-label 'switch label)
  (let ((id (or id (element-id (or name "switch")))))
    `(:div ,(attrs (list :class "tun-switch"))
           (:label (:@ :class "tun-switch-label" :for ,id) ,label)
           ,(when description
              `(:p (:@ :class "tun-switch-description" :id ,(hint-id id)) ,description))
           (:input ,(attrs (list :class "tun-switch-input" :type "checkbox" :role "switch"
                                 :id id :name name :value value :checked checked
                                 :disabled disabled
                                 :aria-describedby (when description (hint-id id)))
                           attributes)))))

;;; ------------------------------------------------------------------
;;; Input group

(define-component input-group ((&key label name value (type :text) hint error required
                                     optional label-hidden placeholder autocomplete inputmode
                                     width disabled readonly prefix suffix icon icon-end
                                     id attributes))
  (:group "Forms")
  (:doc "A text box with something fixed before or after it: text such as «€», «%» and «pcs»
(PREFIX, SUFFIX) or an icon (ICON, ICON-END). Screen readers skip what is fixed, as at
GOV.UK, so the unit must also be in the label or the hint.")
  (:source "Basecoat input group (Vega); GOV.UK text input prefix and suffix")
  (:css (concatenate 'string "
.tun-input-group {
  display: flex;
  align-items: center;
  width: 100%;
  min-width: 0;
  height: var(--control-height);
  overflow: hidden;"
                     (control-css :focus "&:focus-within"
                                  :invalid "&:has(> [aria-invalid='true'])"
                                  :disabled "&:has(> :disabled)") "
  & > .tun-input-group-control {
    flex: 1 1 auto;
    width: 100%;
    min-width: 0;
    height: 100%;
    padding-inline: calc(var(--spacing) * 2.5);
    border: 0;
    background-color: transparent;
    font-size: var(--control-font-size);
    outline: none;
    &::placeholder { color: var(--muted-foreground); }
    &:disabled { cursor: not-allowed; }
  }
  & > .tun-input-group-addon {
    display: inline-flex;
    flex-shrink: 0;
    align-items: center;
    gap: calc(var(--spacing) * 2);
    color: var(--muted-foreground);
    font-size: var(--text-sm);
    font-weight: var(--font-weight-medium);
    white-space: nowrap;
    user-select: none;
    &:first-child { padding-left: calc(var(--spacing) * 2.5); }
    &:last-child { padding-right: calc(var(--spacing) * 2.5); }
  }
  & > .tun-input-group-addon:first-child + .tun-input-group-control {
    padding-left: calc(var(--spacing) * 1.5);
  }
  & > .tun-input-group-control:has(+ .tun-input-group-addon) {
    padding-right: calc(var(--spacing) * 1.5);
  }
  &[data-width] { width: fit-content; max-width: 100%; }
  &[data-width='2'] > .tun-input-group-control { width: calc(3ch + var(--spacing) * 4); }
  &[data-width='3'] > .tun-input-group-control { width: calc(4ch + var(--spacing) * 4); }
  &[data-width='4'] > .tun-input-group-control { width: calc(5ch + var(--spacing) * 4); }
  &[data-width='5'] > .tun-input-group-control { width: calc(6ch + var(--spacing) * 4); }
  &[data-width='10'] > .tun-input-group-control { width: calc(11ch + var(--spacing) * 4); }
  &[data-width='20'] > .tun-input-group-control { width: calc(21ch + var(--spacing) * 4); }
  &[data-width='30'] > .tun-input-group-control { width: calc(31ch + var(--spacing) * 4); }
}"))
  (:examples
   (("A unit after the box" :layout :stack)
    (input-group (:label "Hourly rate" :name "hourly-rate" :prefix "€" :inputmode "decimal"
                         :width 10 :hint "In euros, without VAT."))
    (input-group (:label "Discount in per cent" :name "discount" :suffix "%" :inputmode "decimal"
                         :width 3))
    (input-group (:label "Quantity" :name "quantity" :suffix "pcs" :type :number :width 5)))
   (("An icon before it" :layout :stack)
    (input-group (:label "Search customers" :name "search" :type :search :icon :search
                         :placeholder "Name, email or organisation number")))
   (("Text before it" :layout :stack)
    (input-group (:label "Website" :name "website" :prefix "https://" :optional t
                         :placeholder "www.company.example")))
   (("With an error" :layout :stack)
    (input-group (:label "Amount" :name "amount" :prefix "€" :width 10 :value "1250,-"
                         :hint "In euros, with VAT."
                         :error "The amount must be a number, like 1250 or 1250.50")))
   (("Disabled" :layout :stack)
    (input-group (:label "Shipping" :name "shipping" :prefix "€" :width 10 :value "149"
                         :disabled t))))
  (require-label 'input-group label)
  (check-width width)
  (let ((id (or id (element-id (or name "input"))))
        (width (unless (eq width :full) width)))
    (flet ((addon (text icon-name)
             (when (or text icon-name)
               `(:span (:@ :class "tun-input-group-addon" :aria-hidden "true")
                       ,(when icon-name (icon (:name icon-name)))
                       ,text))))
      (field* (list :label label :for id :hint hint :error error :optional optional
                    :label-hidden label-hidden)
              `(:div ,(attrs (list :class "tun-input-group"
                                   :data-width (when width (princ-to-string width))))
                     ,(addon prefix icon)
                     ,(text-input-markup "tun-input-group-control" id
                                         :type type :name name :value value :hint hint
                                         :error error :required required
                                         :placeholder placeholder
                                         :autocomplete autocomplete :inputmode inputmode
                                         :disabled disabled :readonly readonly
                                         :attributes attributes)
                     ,(addon suffix icon-end))))))

;;; ------------------------------------------------------------------
;;; Error summary

(define-component error-summary ((&key (title (tr "There is a problem"))
                                       errors id attributes)
                                 &rest children)
  (:group "Forms")
  (:doc "The error summary at the top of the page when a form comes back with errors: one
link per error to the field it is about, with the same text as the error message by the
field. ERRORS is a list of (ID MESSAGE). The summary takes focus when the page loads (when it
is the only one on the page), and a link moves focus to the field.")
  (:source "GOV.UK error summary; Designsystemet's wording; Basecoat alert (Vega)")
  (:css "
.tun-error-summary {
  max-width: 40rem;
  padding: calc(var(--spacing) * 4);
  border: 1px solid color-mix(in oklab, var(--destructive) 50%, var(--border));
  border-radius: var(--radius-lg);
  background-color: var(--card);
  color: var(--card-foreground);
  outline: none;
  &:focus-visible {
    box-shadow: 0 0 0 3px color-mix(in oklab, var(--destructive) 25%, transparent);
  }
  & > .tun-error-summary-alert {
    display: grid;
    grid-template-columns: auto minmax(0, 1fr);
    column-gap: calc(var(--spacing) * 3);
    & > .tun-icon {
      grid-row: 1 / span 2;
      margin-top: calc((1lh - 1rem) / 2);
      color: var(--destructive);
    }
  }
  & .tun-error-summary-title {
    font-size: var(--text-base);
    line-height: var(--text-base--line-height);
    font-weight: var(--font-weight-semibold);
    color: var(--destructive);
  }
  & .tun-error-summary-body {
    display: flex;
    flex-direction: column;
    gap: calc(var(--spacing) * 2);
    margin-top: calc(var(--spacing) * 2);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
  }
  & .tun-error-summary-list {
    display: flex;
    flex-direction: column;
    gap: calc(var(--spacing) * 2);
  }
  & .tun-error-summary-list a {
    color: var(--destructive);
    font-weight: var(--font-weight-medium);
    text-decoration-line: underline;
    text-underline-offset: 4px;
    text-decoration-thickness: 1px;
    @media (hover: hover) { &:hover { text-decoration-thickness: 2px; } }
  }
}")
  (:script "
// GOV.UK's error summary: take focus when the page loads, or when htmx
// brings it in, so a screen reader reads it out at once, and let a link
// focus the field it names, scrolled so its label or legend shows too.  A
// page has one error summary; with several (a page of examples) none takes
// focus.
const focusSummary = (root) => {
  const found = root.querySelectorAll('[data-tun-error-summary]');
  if (found.length === 1) found[0].focus();
};
tunOnContent(focusSummary);

const labelFor = (input) => {
  const legend = input.closest('fieldset')?.querySelector(':scope > legend');
  if (legend) {
    if (input.type === 'checkbox' || input.type === 'radio') return legend;
    // Show the legend too, unless the field would then sit in the lower half
    // of the screen, under a phone's keyboard.
    const top = legend.getBoundingClientRect().top;
    const field = input.getBoundingClientRect();
    if (field.top + field.height - top < window.innerHeight / 2) return legend;
  }
  return document.querySelector(`label[for='${CSS.escape(input.id)}']`) ?? input.closest('label');
};

document.addEventListener('click', (event) => {
  const link = event.target.closest('[data-tun-error-summary] a[href^=\"#\"]');
  if (!link) return;
  const input = document.getElementById(decodeURIComponent(link.hash.slice(1)));
  const label = input && labelFor(input);
  if (!label) return;
  event.preventDefault();
  label.scrollIntoView();
  input.focus({ preventScroll: true });
});")
  (:examples
   (("With the fields it is about" :layout :stack)
    (error-summary (:errors '(("quote-customer" "Choose a customer")
                              ("quote-valid" "Valid until must be a date in the future"))))
    (select (:label "Customer" :name "customer" :id "quote-customer" :prompt "Choose a customer"
                    :error "Choose a customer"
                    :options '(("1" "Vestvik Building Ltd") ("2" "Hansen Pipes and Heating"))))
    (text-input (:label "Valid until" :name "valid" :type :date
                        :id "quote-valid" :value "2026-09-30"
                        :error "Valid until must be a date in the future")))
   (("With an explanation and its own title" :layout :stack)
    (error-summary (:title "The quote has not been sent"
                           :errors '(("quote-email" "The customer has no email address. Add it
to the customer first.")))
      '(:p "Correct this, and we will send the quote to the customer."))))
  `(:div ,(attrs (list :class "tun-error-summary" :id id :tabindex "-1"
                       :data-tun-error-summary "true")
                 attributes)
         ;; GOV.UK keeps role=alert on a child, so focusing the summary does not
         ;; race the announcement.
         (:div (:@ :class "tun-error-summary-alert" :role "alert")
               ,(icon (:name :circle-alert))
               (:h2 (:@ :class "tun-error-summary-title") ,title)
               (:div (:@ :class "tun-error-summary-body")
                     ,@children
                     ,(when errors
                        `(:ul (:@ :class "tun-error-summary-list")
                              ,@(loop for (target message) in errors
                                      collect `(:li ,(if target
                                                         `(:a (:@ :href ,(format nil "#~a"
                                                                                 target))
                                                              ,message)
                                                         message)))))))))

;;; ------------------------------------------------------------------
;;; Form actions

(define-component form-actions ((&key cancel (cancel-label (tr "Cancel")) id attributes)
                                &rest children)
  (:group "Forms")
  (:doc "The buttons at the bottom of a form: the main button first, then other actions, and
CANCEL, a link back without saving. On a narrow screen the buttons fill the width and stand
one under another.")
  (:source "GOV.UK button group; Basecoat button (Vega)")
  (:css "
.tun-form-actions {
  container-type: inline-size;
  & > .tun-form-actions-row {
    display: flex;
    flex-direction: column;
    align-items: stretch;
    gap: calc(var(--spacing) * 3);
  }
  & .tun-button { width: 100%; }
  & .tun-form-actions-cancel {
    display: inline-flex;
    align-self: center;
    align-items: center;
    min-height: var(--control-height);
    padding-inline: calc(var(--spacing) * 2);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    font-weight: var(--font-weight-medium);
    text-decoration-line: underline;
    text-underline-offset: 4px;
    @media (hover: hover) { &:hover { text-decoration-thickness: 2px; } }
  }
  @container (min-width: 30rem) {
    & > .tun-form-actions-row { flex-direction: row; flex-wrap: wrap; align-items: center; }
    & .tun-button { width: auto; }
  }
}")
  (:examples
   (("A whole form: a new customer" :layout :stack)
    `(:form (:@ :method "post" :action "/customers" :novalidate t)
            ,(fieldset (:legend "New customer" :legend-size :page)
               (text-input (:label "Name" :name "name"))
               (text-input (:label "Email" :name "email" :type :email
                                   :hint "Invoices and order confirmations are sent here."))
               (text-input (:label "Phone" :name "phone" :type :tel :width 20))
               (text-input (:label "Organisation number" :name "orgno" :width 10
                                   :inputmode "numeric" :optional t
                                   :hint "9 digits. In the Brønnøysund Register Centre."))
               (fieldset (:legend "Address" :legend-size :section)
                 (text-input (:label "Street address" :name "street-address"))
                 (text-input (:label "Postcode" :name "postcode" :width 4
                                     :inputmode "numeric"))
                 (text-input (:label "Town" :name "town" :width 20)))
               (radios (:legend "Kind of customer" :name "customer-kind" :selected "business"
                                :choices '(("business" "Business" :hint "Invoiced by EHF.")
                                           ("private" "Private person")
                                           ("public" "Public body"
                                            :hint "Invoiced by EHF with an order number."))))
               (checkbox (:label "The customer wants the newsletter by email" :name "newsletter"))
               (textarea (:label "Note" :name "note" :optional t :rows 3
                                 :hint "Only for you; the customer does not see it."))
               (form-actions (:cancel "/customers")
                 (button (:type "submit") "Save the customer")
                 (button (:type "submit" :variant :outline :name "next" :value "new")
                         "Save and add another")))))
   (("The same form with errors" :layout :stack)
    (error-summary (:errors '(("customer-name" "Enter the customer's name")
                              ("customer-email"
                               "Enter a valid email address, like ola@example.com")
                              ("customer-orgno" "The organisation number must have 9 digits")
                              ("customer-postcode" "The postcode must have 4 digits")
                              ("customer-kind" "Choose the kind of customer"))))
    `(:form (:@ :method "post" :action "/customers" :novalidate t)
            ,(fieldset (:legend "New customer" :legend-size :page)
               (text-input (:label "Name" :name "name" :id "customer-name"
                                   :error "Enter the customer's name"))
               (text-input (:label "Email" :name "email" :type :email :id "customer-email"
                                   :value "ola@company"
                                   :hint "Invoices and order confirmations are sent here."
                                   :error "Enter a valid email address, like ola@example.com"))
               (text-input (:label "Phone" :name "phone" :type :tel :width 20
                                   :value "+47 912 34 567"))
               (text-input (:label "Organisation number" :name "orgno" :width 10
                                   :id "customer-orgno" :inputmode "numeric" :optional t
                                   :value "99887766"
                                   :hint "9 digits. In the Brønnøysund Register Centre."
                                   :error "The organisation number must have 9 digits"))
               (fieldset (:legend "Address" :legend-size :section)
                 (text-input (:label "Street address" :name "street-address"
                                     :value "Storgata 12"))
                 (text-input (:label "Postcode" :name "postcode" :width 4
                                     :id "customer-postcode" :inputmode "numeric" :value "30"
                                     :error "The postcode must have 4 digits"))
                 (text-input (:label "Town" :name "town" :width 20
                                     :value "Drammen")))
               (radios (:legend "Kind of customer" :name "customer-kind" :id "customer-kind"
                                :error "Choose the kind of customer"
                                :choices '(("business" "Business" :hint "Invoiced by EHF.")
                                           ("private" "Private person")
                                           ("public" "Public body"
                                            :hint "Invoiced by EHF with an order number."))))
               (checkbox (:label "The customer wants the newsletter by email" :name "newsletter"
                                 :checked t))
               (textarea (:label "Note" :name "note" :optional t :rows 3
                                 :hint "Only for you; the customer does not see it."
                                 :value "Call before delivery, the gate is locked after 4 pm."))
               (form-actions (:cancel "/customers")
                 (button (:type "submit") "Save the customer")
                 (button (:type "submit" :variant :outline :name "next" :value "new")
                         "Save and add another")))))
   (("Save, another action and cancel" :layout :stack)
    (form-actions (:cancel "/orders")
      (button (:type "submit") "Save the order")
      (button (:type "submit" :variant :outline :name "draft" :value "yes") "Save as a draft")))
   (("Only one button" :layout :stack)
    (form-actions ()
      (button (:type "submit" :icon-end :arrow-right) "Continue")))
   (("Deleting" :layout :stack)
    (form-actions (:cancel "/customers/10234" :cancel-label "No, keep the customer")
      (button (:type "submit" :variant :destructive) "Yes, delete Vestvik Building Ltd"))))
  `(:div ,(attrs (list :class "tun-form-actions" :id id) attributes)
         (:div (:@ :class "tun-form-actions-row")
               ,@children
               ,(when cancel
                  `(:a (:@ :class "tun-form-actions-cancel" :href ,cancel) ,cancel-label)))))
