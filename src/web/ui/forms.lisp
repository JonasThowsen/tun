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
         (:span (:span (:@ :class ,(format nil "~a-prefix" class)) "Feil:") " " ,error))))

(defun optional-markup (class optional)
  (when optional
    `(:span (:@ :class ,class) " (valgfritt)")))

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
  (:group "Skjema")
  (:doc "Rammen rundt hver kontroll: ledetekst øverst, hjelpetekst under den, feilmelding
over kontrollen, bundet sammen med for, aria-describedby og aria-invalid (control-attributes
gir en egen kontroll de samme attributtene). Som GOV.UK merkes ikke påkrevde felt med
stjerne; spør bare om det dere trenger, og merk de få valgfrie feltene «(valgfritt)» med
OPTIONAL.")
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
   (("Med en egen kontroll" :layout :stack)
    (field (:label "Vedlegg" :for "ordre-vedlegg" :optional t
                   :hint "PDF eller bilde, høyst 10 MB.")
      `(:input ,(attrs (list :type "file" :name "vedlegg" :accept "application/pdf,image/*")
                       (control-attributes "ordre-vedlegg" :hint t)))))
   (("En egen kontroll med feil" :layout :stack)
    (field (:label "Vedlegg" :for "tilbud-vedlegg" :hint "PDF eller bilde, høyst 10 MB."
                   :error "Filen er større enn 10 MB")
      `(:input ,(attrs (list :type "file" :name "vedlegg" :accept "application/pdf,image/*")
                       (control-attributes "tilbud-vedlegg" :hint t :error t))))))
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
  (:group "Skjema")
  (:doc "Et tekstfelt for én linje: tekst, e-post, telefon, tall, passord, dato, søk eller
nettadresse. Gi WIDTH (antall tegn: 2, 3, 4, 5, 10, 20 eller 30) når svaret har kjent
lengde, som postnummer (4) og organisasjonsnummer (10); bruk AUTOCOMPLETE bare når brukeren
fyller inn sine egne opplysninger.")
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
   (("Med og uten hjelpetekst" :layout :stack)
    (text-input (:label "Kundenavn" :name "navn"))
    (text-input (:label "E-post" :name "epost" :type :email
                        :hint "Fakturaen sendes hit. Bruk gjerne en felles adresse.")))
   (("Med feil" :layout :stack)
    (text-input (:label "Telefon" :name "telefon" :type :tel :width 20 :value "912 34"
                        :error "Telefonnummeret må ha 8 siffer, som 912 34 567")))
   (("Valgfritt felt" :layout :stack)
    (text-input (:label "Kundens referanse" :name "referanse" :optional t
                        :hint "Står på fakturaen, som «Prosjekt 1042» eller en bestillers navn.")))
   (("Faste bredder" :layout :stack)
    (text-input (:label "Postnummer" :name "postnummer" :width 4 :inputmode "numeric"))
    (text-input (:label "Organisasjonsnummer" :name "orgnr" :width 10 :inputmode "numeric"))
    (text-input (:label "Poststed" :name "poststed" :width 20))
    (text-input (:label "Fakturaadresse, linje 1" :name "adresse" :width 30)))
   (("Typer" :layout :stack)
    (text-input (:label "Leveringsdato" :name "leveringsdato" :type :date))
    (text-input (:label "Antall timer" :name "timer" :type :number :width 5
                        :attributes '(:min 0 :step "0.5")))
    (text-input (:label "Nettside" :name "nettside" :type :url
                        :placeholder "https://www.firma.no"))
    (text-input (:label "Passord" :name "passord" :type :password
                        :autocomplete "current-password")))
   (("Deaktivert og skrivebeskyttet" :layout :stack)
    (text-input (:label "Kundenummer" :name "kundenummer" :value "10234" :readonly t :width 10
                        :hint "Settes av Tun når kunden lagres."))
    (text-input (:label "Fakturert beløp" :name "belop" :value "12 500 kr" :disabled t
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
  (:group "Skjema")
  (:doc "Et tekstfelt for flere linjer, som et notat eller en beskrivelse av oppdraget. ROWS
gir høyden i linjer; brukeren kan gjøre feltet høyere.")
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
   (("Med hjelpetekst" :layout :stack)
    (textarea (:label "Beskrivelse av oppdraget" :name "beskrivelse"
                      :hint "Hva skal gjøres, hvor, og når kunden vil ha det ferdig.")))
   (("Med feil" :layout :stack)
    (textarea (:label "Beskrivelse av oppdraget" :name "beskrivelse" :rows 3
                      :value "Male"
                      :error "Beskrivelsen må ha minst 20 tegn")))
   (("Valgfritt og deaktivert" :layout :stack)
    (textarea (:label "Intern merknad" :name "merknad" :optional t :rows 3
                      :placeholder "Bare synlig for dere"))
    (textarea (:label "Kundens kommentar" :name "kommentar" :rows 3 :disabled t
                      :value "Leveres på baksiden av bygget, ring 40 00 00 00 ved ankomst."))))
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
  (:group "Skjema")
  (:doc "En nedtrekksliste, nettleserens egen, for å velge ett av mange kjente svar. OPTIONS
er en liste av (VERDI TEKST) eller (VERDI TEKST :disabled t); PROMPT gir et tomt første valg.
Har listen fem valg eller færre, er radios bedre: da ser brukeren alle svarene.")
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
   (("Med tomt første valg" :layout :stack)
    (select (:label "Betalingsfrist" :name "betalingsfrist" :prompt "Velg frist"
                    :options '(("10" "10 dager") ("14" "14 dager") ("30" "30 dager")
                               ("kontant" "Kontant ved levering" :disabled t)))))
   (("Valgt verdi og hjelpetekst" :layout :stack)
    (select (:label "Mva-sats" :name "mva" :selected 25
                    :hint "Gjelder alle linjene på fakturaen."
                    :options '((25 "25 % – vanlig sats") (15 "15 % – mat og drikke")
                               (12 "12 % – persontransport og overnatting")
                               (0 "0 % – fritatt")))))
   (("Med feil" :layout :stack)
    (select (:label "Ansvarlig selger" :name "selger" :prompt "Velg selger"
                    :error "Velg hvem som er ansvarlig for kunden"
                    :options '(("kari" "Kari Nordmann") ("ola" "Ola Hansen")
                               ("fatima" "Fatima Ali")))))
   (("Deaktivert" :layout :stack)
    (select (:label "Lager" :name "lager" :selected "drammen" :disabled t
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
  (:group "Skjema")
  (:doc "Samler felt som hører sammen under en overskrift (legend), som en adresse, og ligger
rundt checkboxes og radios. LEGEND-SIZE :page gjør overskriften til sidens h1 når gruppen er
hele spørsmålet på siden, :section til en mellomtittel i et langt skjema.")
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
   (("Adresse som del av et skjema" :layout :stack)
    (fieldset (:legend "Fakturaadresse" :legend-size :section
                       :hint "Der kunden vil ha fakturaen, hvis den sendes i posten.")
      (text-input (:label "Gateadresse" :name "gateadresse" :autocomplete "off"))
      (text-input (:label "Postnummer" :name "postnummer" :width 4 :inputmode "numeric"))
      (text-input (:label "Poststed" :name "poststed" :width 20))))
   (("Som sidetittel" :layout :stack)
    (fieldset (:legend "Hvor skal varene leveres?" :legend-size :page
                       :hint "Vi leverer i hele Norge, men ikke til postboks.")
      (text-input (:label "Gateadresse" :name "leveringsadresse"))
      (text-input (:label "Postnummer" :name "leveringspostnummer" :width 4
                          :inputmode "numeric"))
      (text-input (:label "Poststed" :name "leveringssted" :width 20))))
   (("Med feil for hele gruppen" :layout :stack)
    (fieldset (:legend "Kontaktperson" :error "Fyll inn telefon eller e-post, eller begge")
      (text-input (:label "Telefon" :name "kontakt-telefon" :type :tel :width 20))
      (text-input (:label "E-post" :name "kontakt-epost" :type :email))))
   (("Deaktivert" :layout :stack)
    (fieldset (:legend "Leveringsadresse" :legend-size :section :disabled t
                       :hint "Samme som fakturaadressen.")
      (text-input (:label "Gateadresse" :name "adresse" :value "Storgata 12"))
      (text-input (:label "Postnummer" :name "postnr" :value "3015" :width 4)))))
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
  (:group "Skjema")
  (:doc "Én avkrysningsboks med teksten ved siden av, for et ja/nei-felt eller «Jeg godtar
…». Hele raden er trykkflaten. Feilmeldingen står over boksen.")
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
   ("Vanlig"
    (checkbox (:label "Kunden vil ha nyhetsbrev på e-post" :name "nyhetsbrev")))
   (("Med hjelpetekst" :layout :stack)
    (checkbox (:label "Send ordrebekreftelse til kunden" :name "bekreftelse" :checked t
                      :hint "Sendes til post@example.no når ordren lagres.")))
   (("Med feil" :layout :stack)
    (checkbox (:label "Jeg har lest og godtar vilkårene for oppdraget" :name "vilkar"
                      :error "Du må godta vilkårene før du kan sende tilbudet")))
   ("Deaktivert"
    (checkbox (:label "Faktura sendt" :name "sendt" :checked t :disabled t))
    (checkbox (:label "Purring sendt" :name "purret" :disabled t))))
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
  (:group "Skjema")
  (:doc "En gruppe avkrysningsbokser under en overskrift, der brukeren kan velge flere.
CHOICES er en liste av (VERDI TEKST &key HINT DISABLED) og SELECTED en liste av valgte
verdier; INLINE legger korte valg på én linje. ID går til første boks, som feilsammendraget
lenker til.")
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
   (("Med hjelpetekster" :layout :stack)
    (checkboxes (:legend "Hvordan vil kunden få fakturaen?" :name "fakturakanal"
                         :hint "Velg alle som passer." :selected '("ehf")
                         :choices '(("ehf" "EHF" :hint "Rett inn i kundens regnskapssystem.")
                                    ("epost" "E-post med PDF")
                                    ("papir" "Papir i posten" :hint "Gebyr 59 kr per faktura.")))))
   (("På én linje" :layout :stack)
    (checkboxes (:legend "Hvilke dager kan vi komme?" :name "dager" :inline t
                         :selected '("man" "ons")
                         :choices '(("man" "Man") ("tir" "Tir") ("ons" "Ons") ("tor" "Tor")
                                    ("fre" "Fre")))))
   (("Med feil" :layout :stack)
    (checkboxes (:legend "Hvilke tjenester gjelder oppdraget?" :name "tjenester"
                         :id "oppdrag-tjenester" :error "Velg minst én tjeneste"
                         :choices '(("maling" "Maling") ("tapetsering" "Tapetsering")
                                    ("snekring" "Snekring")))))
   (("Deaktivert valg" :layout :stack)
    (checkboxes (:legend "Varsler på e-post" :name "varsler" :optional t
                         :selected '("ordre")
                         :choices '(("ordre" "Ny ordre") ("betaling" "Betaling mottatt")
                                    ("sms" "SMS ved forsinkelse" :disabled t
                                     :hint "Krever SMS-modulen.")))))
   (("Hele gruppen deaktivert" :layout :stack)
    (checkboxes (:legend "Leveringsdager" :name "levering" :inline t :disabled t
                         :selected '("tir")
                         :choices '(("man" "Man") ("tir" "Tir") ("ons" "Ons"))))))
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
  (:group "Skjema")
  (:doc "En gruppe radioknapper under en overskrift, der brukeren velger ett svar. CHOICES er
en liste av (VERDI TEKST &key HINT DISABLED) og SELECTED den valgte verdien; INLINE legger
korte valg som Ja og Nei på én linje. ID går til første knapp, som feilsammendraget lenker
til.")
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
   (("Med hjelpetekster" :layout :stack)
    (radios (:legend "Kundetype" :name "kundetype" :selected "bedrift"
                     :choices '(("bedrift" "Bedrift" :hint "Faktura på EHF.")
                                ("privat" "Privatperson")
                                ("offentlig" "Offentlig virksomhet"
                                 :hint "Faktura med EHF og bestillingsnummer.")))))
   (("Ja og nei på én linje" :layout :stack)
    (radios (:legend "Skal ordren faktureres nå?" :name "fakturer" :inline t
                     :choices '(("ja" "Ja") ("nei" "Nei")))))
   (("Med feil" :layout :stack)
    (radios (:legend "Hvordan skal varene leveres?" :name "levering" :id "ordre-levering"
                     :error "Velg hvordan varene skal leveres"
                     :choices '(("hent" "Kunden henter selv") ("bud" "Bud samme dag")
                                ("post" "Posten, 2–4 virkedager")))))
   (("Som sidetittel" :layout :stack)
    (radios (:legend "Hva slags oppdrag er dette?" :legend-size :page :name "oppdragstype"
                     :hint "Du kan endre det senere."
                     :choices '(("fastpris" "Fastpris" :hint "Kunden betaler avtalt sum.")
                                ("timer" "Etter medgått tid"
                                 :hint "Kunden betaler for timer og materialer.")))))
   (("Deaktivert valg" :layout :stack)
    (radios (:legend "Betaling" :name "betaling" :selected "faktura"
                     :choices '(("faktura" "Faktura")
                                ("kort" "Kort i butikk")
                                ("vipps" "Vipps" :disabled t :hint "Ikke satt opp ennå."))))))
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
  (:group "Skjema")
  (:doc "En av/på-bryter for en innstilling som gjelder med en gang eller når skjemaet lagres,
med teksten til venstre og bryteren til høyre. Bruk checkbox når svaret er et ja til noe,
som å godta vilkår.")
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
   (("Med beskrivelse" :layout :stack)
    (switch (:label "Send påminnelse om ubetalte fakturaer" :name "paminnelse" :checked t
                    :description "Kunden får e-post 3 og 10 dager etter forfall."))
    (switch (:label "Vis priser med mva." :name "med-mva"
                    :description "Gjelder bare det du ser, ikke fakturaene.")))
   (("Uten beskrivelse" :layout :stack)
    (switch (:label "Ta imot bestillinger på nett" :name "nettbestilling" :checked t)))
   (("Deaktivert" :layout :stack)
    (switch (:label "Automatisk purring" :name "purring" :disabled t
                    :description "Krever at fakturamodulen er slått på."))
    (switch (:label "Sikkerhetskopi hver natt" :name "backup" :checked t :disabled t))))
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
  (:group "Skjema")
  (:doc "Et tekstfelt med noe fast foran eller bak: tekst som «kr», «%» og «stk» (PREFIX,
SUFFIX) eller et ikon (ICON, ICON-END). Skjermlesere hopper over det faste, som hos GOV.UK,
så enheten må også stå i ledeteksten eller hjelpeteksten.")
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
   (("Enhet etter feltet" :layout :stack)
    (input-group (:label "Timepris" :name "timepris" :suffix "kr" :inputmode "decimal"
                         :width 10 :hint "I kroner, uten mva."))
    (input-group (:label "Rabatt i prosent" :name "rabatt" :suffix "%" :inputmode "decimal"
                         :width 3))
    (input-group (:label "Antall" :name "antall" :suffix "stk" :type :number :width 5)))
   (("Ikon foran" :layout :stack)
    (input-group (:label "Søk i kunder" :name "sok" :type :search :icon :search
                         :placeholder "Navn, e-post eller org.nr.")))
   (("Tekst foran" :layout :stack)
    (input-group (:label "Nettside" :name "nettside" :prefix "https://" :optional t
                         :placeholder "www.firma.no")))
   (("Med feil" :layout :stack)
    (input-group (:label "Beløp" :name "belop" :suffix "kr" :width 10 :value "1250,-"
                         :hint "I kroner, med mva."
                         :error "Beløpet må være et tall, som 1250 eller 1250,50")))
   (("Deaktivert" :layout :stack)
    (input-group (:label "Fraktkostnad" :name "frakt" :suffix "kr" :width 10 :value "149"
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

(define-component error-summary ((&key (title "For å gå videre må du rette opp følgende feil:")
                                       errors id attributes)
                                 &rest children)
  (:group "Skjema")
  (:doc "Feilsammendraget øverst på siden når et skjema kommer tilbake med feil: én lenke per
feil til feltet det gjelder, med samme tekst som feilmeldingen ved feltet. ERRORS er en liste
av (ID MELDING). Sammendraget får fokus når siden lastes (er det det eneste på siden), og en
lenke flytter fokus til feltet.")
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
   (("Med feltene det gjelder" :layout :stack)
    (error-summary (:errors '(("tilbud-kunde" "Velg en kunde")
                              ("tilbud-gyldig" "Gyldig til må være en dato i fremtiden"))))
    (select (:label "Kunde" :name "kunde" :id "tilbud-kunde" :prompt "Velg kunde"
                    :error "Velg en kunde"
                    :options '(("1" "Vestvik Bygg AS") ("2" "Hansen Rør og Varme"))))
    (text-input (:label "Gyldig til" :name "gyldig" :type :date
                        :id "tilbud-gyldig" :value "2026-09-30"
                        :error "Gyldig til må være en dato i fremtiden")))
   (("Med forklaring og egen tittel" :layout :stack)
    (error-summary (:title "Tilbudet er ikke sendt"
                           :errors '(("tilbud-epost" "Kunden har ingen e-postadresse. Legg den inn
på kunden først.")))
      '(:p "Rett opp dette, så sender vi tilbudet til kunden."))))
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

(define-component form-actions ((&key cancel (cancel-label "Avbryt") id attributes)
                                &rest children)
  (:group "Skjema")
  (:doc "Knappene nederst i et skjema: hovedknappen først, så andre handlinger, og CANCEL, en
lenke tilbake uten å lagre. På en smal skjerm fyller knappene bredden og ligger under
hverandre.")
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
   (("Et helt skjema: Ny kunde" :layout :stack)
    `(:form (:@ :method "post" :action "/kunder" :novalidate t)
            ,(fieldset (:legend "Ny kunde" :legend-size :page)
               (text-input (:label "Navn" :name "navn"))
               (text-input (:label "E-post" :name "epost" :type :email
                                   :hint "Fakturaer og ordrebekreftelser sendes hit."))
               (text-input (:label "Telefon" :name "telefon" :type :tel :width 20))
               (text-input (:label "Organisasjonsnummer" :name "orgnr" :width 10
                                   :inputmode "numeric" :optional t
                                   :hint "9 siffer. Står i Brønnøysundregistrene."))
               (fieldset (:legend "Adresse" :legend-size :section)
                 (text-input (:label "Gateadresse" :name "gateadresse"))
                 (text-input (:label "Postnummer" :name "postnummer" :width 4
                                     :inputmode "numeric"))
                 (text-input (:label "Poststed" :name "poststed" :width 20)))
               (radios (:legend "Kundetype" :name "kundetype" :selected "bedrift"
                                :choices '(("bedrift" "Bedrift" :hint "Faktura på EHF.")
                                           ("privat" "Privatperson")
                                           ("offentlig" "Offentlig virksomhet"
                                            :hint "Faktura med EHF og bestillingsnummer."))))
               (checkbox (:label "Kunden vil ha nyhetsbrev på e-post" :name "nyhetsbrev"))
               (textarea (:label "Notat" :name "notat" :optional t :rows 3
                                 :hint "Bare for dere, kunden ser det ikke."))
               (form-actions (:cancel "/kunder")
                 (button (:type "submit") "Lagre kunde")
                 (button (:type "submit" :variant :outline :name "neste" :value "ny")
                         "Lagre og legg til ny")))))
   (("Det samme skjemaet med feil" :layout :stack)
    (error-summary (:errors '(("kunde-navn" "Skriv inn navnet på kunden")
                              ("kunde-epost"
                               "Skriv inn en gyldig e-postadresse, som ola@example.no")
                              ("kunde-orgnr" "Organisasjonsnummeret må ha 9 siffer")
                              ("kunde-postnummer" "Postnummeret må ha 4 siffer")
                              ("kunde-kundetype" "Velg kundetype"))))
    `(:form (:@ :method "post" :action "/kunder" :novalidate t)
            ,(fieldset (:legend "Ny kunde" :legend-size :page)
               (text-input (:label "Navn" :name "navn" :id "kunde-navn"
                                   :error "Skriv inn navnet på kunden"))
               (text-input (:label "E-post" :name "epost" :type :email :id "kunde-epost"
                                   :value "ola@firma"
                                   :hint "Fakturaer og ordrebekreftelser sendes hit."
                                   :error "Skriv inn en gyldig e-postadresse, som ola@example.no"))
               (text-input (:label "Telefon" :name "telefon" :type :tel :width 20
                                   :value "+47 912 34 567"))
               (text-input (:label "Organisasjonsnummer" :name "orgnr" :width 10
                                   :id "kunde-orgnr" :inputmode "numeric" :optional t
                                   :value "99887766"
                                   :hint "9 siffer. Står i Brønnøysundregistrene."
                                   :error "Organisasjonsnummeret må ha 9 siffer"))
               (fieldset (:legend "Adresse" :legend-size :section)
                 (text-input (:label "Gateadresse" :name "gateadresse"
                                     :value "Storgata 12"))
                 (text-input (:label "Postnummer" :name "postnummer" :width 4
                                     :id "kunde-postnummer" :inputmode "numeric" :value "30"
                                     :error "Postnummeret må ha 4 siffer"))
                 (text-input (:label "Poststed" :name "poststed" :width 20
                                     :value "Drammen")))
               (radios (:legend "Kundetype" :name "kundetype" :id "kunde-kundetype"
                                :error "Velg kundetype"
                                :choices '(("bedrift" "Bedrift" :hint "Faktura på EHF.")
                                           ("privat" "Privatperson")
                                           ("offentlig" "Offentlig virksomhet"
                                            :hint "Faktura med EHF og bestillingsnummer."))))
               (checkbox (:label "Kunden vil ha nyhetsbrev på e-post" :name "nyhetsbrev"
                                 :checked t))
               (textarea (:label "Notat" :name "notat" :optional t :rows 3
                                 :hint "Bare for dere, kunden ser det ikke."
                                 :value "Ring før levering, porten er låst etter kl. 16."))
               (form-actions (:cancel "/kunder")
                 (button (:type "submit") "Lagre kunde")
                 (button (:type "submit" :variant :outline :name "neste" :value "ny")
                         "Lagre og legg til ny")))))
   (("Lagre, en annen handling og avbryt" :layout :stack)
    (form-actions (:cancel "/ordre")
      (button (:type "submit") "Lagre ordre")
      (button (:type "submit" :variant :outline :name "kladd" :value "ja") "Lagre som kladd")))
   (("Bare én knapp" :layout :stack)
    (form-actions ()
      (button (:type "submit" :icon-end :arrow-right) "Fortsett")))
   (("Slette" :layout :stack)
    (form-actions (:cancel "/kunder/10234" :cancel-label "Nei, behold kunden")
      (button (:type "submit" :variant :destructive) "Ja, slett Vestvik Bygg AS"))))
  `(:div ,(attrs (list :class "tun-form-actions" :id id) attributes)
         (:div (:@ :class "tun-form-actions-row")
               ,@children
               ,(when cancel
                  `(:a (:@ :class "tun-form-actions-cancel" :href ,cancel) ,cancel-label)))))
