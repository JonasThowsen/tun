;;;; web/ui/toolbar.lisp -- a list's toolbar: its one search and its
;;;; filters as one GET form, so what is chosen is the address (spec/ui.md 6,
;;;; list-toolbar).
;;;;
;;;; A filter is data in the toolbar's options, rendered once: as a button
;;;; with its choices in a popover on a wide toolbar, and, from three
;;;; filters on a narrow one, as a row of the «Filters» sheet, a dialog
;;;; inside the form, so its fields are the form's wherever they show.

(in-package #:tun.ui)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; A filter's state

(defparameter +fold-from+ 3
  "From this many filters, a narrow toolbar keeps them behind «Filters».")

(defun filter-name (filter)
  "FILTER's address key; a period's is the first of its two."
  (or (getf filter :name) (first (getf filter :names))))
(defun filter-label (filter) (getf filter :label))
(defun filter-kind (filter) (getf filter :kind))

(defun filter-values (filter)
  "The values FILTER has chosen, as a list of non-empty texts: a :ONE
filter's value, a :SEVERAL filter's, or \"true\" for a :TOGGLE that is on."
  (let ((value (getf filter :value)))
    (ecase (filter-kind filter)
      (:one (and (stringp value) (plusp (length value)) (list value)))
      (:several (remove-if-not (lambda (each) (and (stringp each) (plusp (length each))))
                               (if (listp value) value (list value))))
      (:toggle (and value (list "true")))
      (:period (remove-if-not (lambda (each) (and (stringp each) (plusp (length each))))
                              value)))))

(defun filter-in-use-p (filter)
  (and (filter-values filter) t))

(defun choice-text (filter value)
  "The label of FILTER's choice VALUE, else VALUE itself."
  (or (second (find value (getf filter :choices) :key #'first :test #'equal)) value))

(defun period-dates (filter)
  "A :PERIOD FILTER's first and last day as the page gives them, each read
as a date, YYYY-MM-DD, where it names one, else as it is, or NIL."
  (mapcar (lambda (value)
            (and (stringp value) (plusp (length value))
                 (or (read-date-text value) value)))
          (list (first (getf filter :value)) (second (getf filter :value)))))

(defun filter-summary (filter)
  "What FILTER's button says it has chosen: the choice's label, for several
the count, for a period its days; NIL when it is not in use or is a toggle."
  (let ((values (filter-values filter)))
    (cond ((null values) nil)
          ((eq (filter-kind filter) :period) (apply #'period-text (period-dates filter)))
          ((member (filter-kind filter) '(:one :several))
           (if (rest values)
               (princ-to-string (length values))
               (choice-text filter (first values)))))))

(defun check-filter (filter)
  (destructuring-bind (&key name names label kind choices value all quick errors) filter
    (declare (ignore value all quick errors))
    (check-type kind (member :one :several :toggle :period))
    (if (eq kind :period)
        (unless (and (= 2 (length names))
                     (every (lambda (key) (and (stringp key) (plusp (length key)))) names))
          (error "A list-toolbar period needs :names, its two address keys: ~s" filter))
        (unless (and (stringp name) (plusp (length name)))
          (error "A list-toolbar filter needs :name, its address key: ~s" filter)))
    (require-label 'list-toolbar label "a label for each filter")
    (when (and (member kind '(:one :several)) (null choices))
      (error "The list-toolbar filter ~s needs :choices, (VALUE LABEL) pairs" name))))

;;; ------------------------------------------------------------------
;;; Addresses: every filter's key, as a submission names them

(defun filter-pairs (filter clearedp &optional period)
  "The (KEY . VALUE) pairs FILTER sends in a submission, in the order its
fields stand, or as if nothing were chosen when CLEAREDP.  PERIOD, a
period's (FROM TO), stands for what it holds."
  (let ((name (filter-name filter))
        (values (unless clearedp (filter-values filter))))
    (ecase (filter-kind filter)
      (:one (list (cons name (or (first values) ""))))
      ((:several :toggle) (cons (cons name "") (mapcar (lambda (value) (cons name value)) values)))
      (:period (let ((dates (cond (clearedp '("" ""))
                                  (period period)
                                  (t (getf filter :value)))))
                 (mapcar (lambda (key value)
                           (cons key (if (and (stringp value) (plusp (length value))) value "")))
                         (getf filter :names) (list (first dates) (second dates))))))))

(defun toolbar-href (action search filters keep &key (cleared '()) set)
  "The address of ACTION with what the toolbar sends: the search, every
filter's key (those in CLEARED, or all for :ALL, as cleared) and KEEP.
SET, (FILTER FROM TO), gives a period other days."
  (let ((pairs (append (when search
                         (list (cons (getf search :name) (or (getf search :value) ""))))
                       (loop for filter in filters
                             append (filter-pairs filter (or (eq cleared :all)
                                                             (member filter cleared))
                                                  (and (eq filter (first set)) (rest set))))
                       (loop for (key value) in keep
                             when value collect (cons key (princ-to-string value))))))
    (format nil "~a~@[?~{~a~^&~}~]" action
            (loop for (key . value) in pairs
                  collect (format nil "~a=~a" (hunchentoot:url-encode key :utf-8)
                                  (hunchentoot:url-encode value :utf-8))))))

;;; ------------------------------------------------------------------
;;; Markup

(defun filter-id (base filter &optional part)
  (format nil "~a-~a~@[-~a~]" base (filter-name filter) part))

(defun filter-clear-link (base filter href)
  "The link that clears FILTER: an ×, named «Clear LABEL»."
  ;; Not boosted: with scripts the toolbar's own script clears and submits.
  `(:a (:@ :class "tun-list-toolbar-filter-clear" :href ,href :hx-boost "false"
           :aria-label ,(tr "Clear ~a" (filter-label filter))
           :data-tun-list-toolbar-clear ,(filter-name filter)
           :aria-controls ,(filter-id base filter "choices"))
       ,(icon (:name :x))))

(defun period-quick-choices (filter)
  "A period FILTER's quick choices, (LABEL FROM TO): today, this week from
its first day, this month, last month, then the page's own."
  (let* ((today (page-today))
         (week (date-add-days today (- (mod (- (weekday-of today) (week-first-day)) 7))))
         (month (concatenate 'string (subseq today 0 8) "01"))
         (last-month (date-add-months month -1)))
    (append (list (list (tr "Today") today today)
                  (list (tr "This week") week (date-add-days week 6))
                  (list (tr "This month") month (date-add-days (date-add-months month 1) -1))
                  (list (tr "Last month") last-month (date-add-days month -1)))
            (getf filter :quick))))

(defun period-choices (base filter action search filters keep)
  "What a period FILTER's popover holds: its quick choices, each a link to
the address with its days, and a date field for its first and last day."
  (let ((dates (period-dates filter))
        (errors (getf filter :errors)))
    (list `(:div (:@ :class "tun-list-toolbar-quick")
                 ,@(loop for (label from to) in (period-quick-choices filter)
                         collect `(:a ,(attrs (list :class "tun-list-toolbar-quick-choice"
                                                    :href (toolbar-href action search filters keep
                                                                        :set (list filter from to))
                                                    :hx-boost "false"
                                                    :aria-current (when (and (equal from (first dates))
                                                                             (equal to (second dates)))
                                                                    "true")
                                                    :data-tun-list-toolbar-quick t
                                                    :data-from (date-text from)
                                                    :data-to (date-text to)))
                                      ,label)))
          `(:div (:@ :class "tun-list-toolbar-period-fields")
                 ,@(loop for key in (getf filter :names)
                         for value in (list (first (getf filter :value)) (second (getf filter :value)))
                         for label in (list (tr "From") (tr "To"))
                         for part in '("start" "end")
                         for error in (list (first errors) (second errors))
                         ;; The form a date is written in, once.
                         for form-hint = (string= part "start")
                         collect (date-input* (list :label label :name key :value value
                                                    :error error :form-hint form-hint
                                                    :id (filter-id base filter part))))))))

(defun filter-choices (base filter &optional action search filters keep)
  "The popover of a :ONE, :SEVERAL or :PERIOD filter: its choices as radios
or checkboxes, or a period's days, headed by its label, with a close button
a phone shows."
  (let ((id (filter-id base filter "choices"))
        (name (filter-name filter)))
    `(:div (:@ :class "tun-list-toolbar-choices" :id ,id :popover t
               :data-tun-list-toolbar-choices t)
           (:div (:@ :class "tun-list-toolbar-choices-close")
                 ,(button (:variant :ghost :size :icon-sm :label (tr "Close")
                           :attributes (list :popovertarget id :popovertargetaction "hide"))
                          (icon (:name :x))))
           ,@(ecase (filter-kind filter)
               (:one
                (list (radios* (list :legend (filter-label filter) :name name
                                     :id (filter-id base filter "choice")
                                     :selected (or (first (filter-values filter)) "")
                                     :choices (cons (list "" (or (getf filter :all) (tr "All")))
                                                    (getf filter :choices))))))
               (:several
                (list `(:input (:@ :type "hidden" :name ,name :value ""))
                      (checkboxes* (list :legend (filter-label filter) :name name
                                         :id (filter-id base filter "choice")
                                         :selected (filter-values filter)
                                         :choices (getf filter :choices)))))
               (:period
                (list (apply #'fieldset* (list :legend (filter-label filter)
                                               :id (filter-id base filter "choice"))
                             (period-choices base filter action search filters keep))))))))

(defun filter-markup (base filter clear-href &optional action search filters keep)
  "One filter: a :TOGGLE's one button, or a :ONE, :SEVERAL or :PERIOD
filter's button, its clear link while in use, its heading in the sheet,
and its choices; ACTION, SEARCH, FILTERS and KEEP make a period's links."
  (let* ((in-use (filter-in-use-p filter))
         (summary (filter-summary filter))
         (common (list :class "tun-list-toolbar-filter" :id (filter-id base filter)
                       :data-kind (option-string (filter-kind filter))
                       :data-in-use (when in-use "true")
                       :data-tun-list-toolbar-filter (filter-name filter))))
    (if (eq (filter-kind filter) :toggle)
        `(:div ,(attrs common)
               (:input (:@ :type "hidden" :name ,(filter-name filter) :value ""))
               (:label (:@ :class "tun-list-toolbar-toggle")
                       (:input ,(attrs (list :class "tun-list-toolbar-toggle-input"
                                             :type "checkbox" :id (filter-id base filter "input")
                                             :name (filter-name filter) :value "true"
                                             :checked in-use)))
                       (:span ,(filter-label filter))
                       (:span (:@ :class "tun-list-toolbar-toggle-off") ,(icon (:name :plus)))
                       (:span (:@ :class "tun-list-toolbar-toggle-on") ,(icon (:name :x)))))
        (let ((choices-id (filter-id base filter "choices"))
              (value `(:span (:@ :class "tun-list-toolbar-filter-value") ,summary)))
          `(:div ,(attrs common)
                 (:div (:@ :class "tun-list-toolbar-filter-control")
                       (:button (:@ :type "button" :class "tun-list-toolbar-filter-button"
                                    :id ,(filter-id base filter "button")
                                    :popovertarget ,choices-id :aria-expanded "false"
                                    :aria-controls ,choices-id)
                                (:span ,(filter-label filter) ,@(when summary (list ": " value)))
                                ,(icon (:name :chevron-down)))
                       ,@(when in-use (list (filter-clear-link base filter clear-href))))
                 (:div (:@ :class "tun-list-toolbar-filter-heading")
                       (:span ,(filter-label filter))
                       ,@(when summary (list value))
                       ,@(when in-use (list (filter-clear-link base filter clear-href))))
                 ,(filter-choices base filter action search filters keep))))))

(defun fold-button (sheet-id in-use)
  "The «Filters» button a narrow toolbar shows, with how many are in use."
  (button* (list :variant :outline :icon :sliders-horizontal
                 :attributes (list :command "show-modal" :commandfor sheet-id
                                   :aria-haspopup "dialog"
                                   :aria-label (if (plusp in-use)
                                                   (tr "Filters, ~d in use" in-use)
                                                   (tr "Filters"))
                                   :data-tun-list-toolbar-fold t))
           (tr "Filters")
           (when (plusp in-use)
             `(:span (:@ :class "tun-list-toolbar-count" :aria-hidden "true")
                     ,(princ-to-string in-use)))))

(define-component list-toolbar ((&key action search filters keep label id attributes))
  (:group "Data")
  (:doc "A list's one search and its filters, above the list, as one GET form to ACTION, so
what is chosen is the address. SEARCH is (:name :label :value); each of FILTERS is (:name
:label :kind :choices :value [:all]), KIND :one, :several or :toggle, CHOICES (VALUE LABEL)
pairs; KEEP, (KEY VALUE) pairs, go along as hidden fields, such as the sort. A period is
(:kind :period :label :names (FROM TO) :value (FROM-VALUE TO-VALUE) [:quick] [:errors]): its
first and last day under two keys, with quick choices and two date fields. A filter is a
button that opens its choices, applied at once where scripts run; a narrow toolbar keeps three
or more behind one «Filters» sheet. Two toolbars on one page need an :id each.")
  (:source "The owner's rules for an admin application, 2026-11 (filter bar and sheet); the
popover and the dialog as Tun's own")
  (:css (concatenate 'string "
.tun-list-toolbar {
  container: tun-list-toolbar / inline-size;
  & .tun-list-toolbar-row {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: calc(var(--spacing) * 2);
  }
  & .tun-list-toolbar-search {
    position: relative;
    flex: 1 1 100%;
    min-width: 0;
    & > .tun-icon {
      position: absolute;
      inset-inline-start: calc(var(--spacing) * 3);
      top: 50%;
      translate: 0 -50%;
      width: calc(var(--spacing) * 4);
      height: calc(var(--spacing) * 4);
      color: var(--muted-foreground);
      pointer-events: none;
    }
  }
  & .tun-list-toolbar-search-input {
    width: 100%;
    min-height: var(--control-height);
    padding: 0 calc(var(--spacing) * 3) 0 calc(var(--spacing) * 9);" (control-css) "
  }
  & .tun-list-toolbar-search-label {" +visually-hidden-css+ "
  }

  /* On a narrow toolbar the filters are one row under the search that
     scrolls in its own box, so a filter put into use widens only its own
     button and moves nothing below; the padding keeps focus rings whole. */
  & .tun-list-toolbar-filters {
    display: flex;
    flex: 1 1 100%;
    gap: calc(var(--spacing) * 2);
    min-width: 0;
    padding: var(--spacing);
    margin: calc(var(--spacing) * -1);
    overflow-x: auto;
  }
  & .tun-list-toolbar-filter { display: flex; flex: none; }

  /* The sheet is laid open in the row while it is not open as a dialog:
     the filters stand in it as buttons. */
  & .tun-dialog[data-tun-list-toolbar-sheet]:not([open]) {
    display: contents;
    pointer-events: auto;
    font-size: inherit;
    line-height: inherit;
    & > .tun-dialog-header, & > .tun-dialog-close { display: none; }
    & > .tun-dialog-body { display: contents; }
  }
  & .tun-button[data-tun-list-toolbar-fold] { display: none; }
  @container tun-list-toolbar (max-width: 39.99rem) {
    @media (scripting: enabled) {
      & .tun-dialog[data-tun-list-toolbar-sheet]:not([open]) { display: none; }
      & .tun-button[data-tun-list-toolbar-fold] { display: inline-flex; }
    }
  }
  & .tun-list-toolbar-count {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: calc(var(--spacing) * 5);
    height: calc(var(--spacing) * 5);
    padding-inline: calc(var(--spacing) * 1.5);
    border-radius: var(--radius-full);
    background-color: var(--primary);
    color: var(--primary-foreground);
    font-size: var(--text-xs);
    line-height: var(--text-xs--line-height);
    font-variant-numeric: tabular-nums;
  }

  /* From 40rem the search and the filters share one row that never wraps.
     The search keeps its width while there is room, so a filter put into
     use moves only its own button and what follows it; when the row is
     full the search narrows first, to 12rem, and then the filters scroll
     in their own box. */
  @container tun-list-toolbar (min-width: 40rem) {
    & .tun-list-toolbar-row { flex-wrap: nowrap; }
    /* Shrinking a thousand times as readily as the filters, the search
       gives up its room first. */
    & .tun-list-toolbar-search { flex: 0 1000 24rem; min-width: 12rem; }
    & .tun-list-toolbar-filters { flex: 0 1 auto; }
    & .tun-list-toolbar-reset, & .tun-button[data-tun-list-toolbar-apply] { flex: none; }
  }

  /* A filter's button, and its clear joined to it in one frame.  In use it
     shows by its edge and its words, never by weight or size. */
  & .tun-list-toolbar-filter-control {
    display: inline-flex;
    align-items: stretch;
    height: var(--control-height);
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    background-color: var(--background);
  }
  & .tun-list-toolbar-filter[data-in-use] .tun-list-toolbar-filter-control {
    border-color: var(--border-strong);
  }
  & .tun-list-toolbar-filter-button {
    display: inline-flex;
    align-items: center;
    gap: calc(var(--spacing) * 1.5);
    padding-inline: calc(var(--spacing) * 3) calc(var(--spacing) * 2.5);
    border: 0;
    border-radius: var(--radius-sm);
    background-color: transparent;
    color: var(--foreground);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    font-weight: var(--font-weight-medium);
    white-space: nowrap;
    cursor: pointer;
    outline: none;
    touch-action: manipulation;
    transition-property: background-color, box-shadow;
    transition-duration: var(--duration-fast);
    transition-timing-function: var(--ease);
    & .tun-icon {
      width: calc(var(--spacing) * 4);
      height: calc(var(--spacing) * 4);
      color: var(--muted-foreground);
    }
    &:focus-visible { box-shadow: var(--focus-ring); }
    @media (hover: hover) { &:hover { background-color: var(--accent); } }
    &:active { background-color: var(--pressed); transition-duration: 0s; }
  }
  & .tun-list-toolbar-filter[data-in-use] .tun-list-toolbar-filter-button {
    border-radius: var(--radius-sm) 0 0 var(--radius-sm);
  }
  & .tun-list-toolbar-filter-clear {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: calc(var(--spacing) * 8);
    border-inline-start: 1px solid var(--border);
    border-radius: 0 var(--radius-sm) var(--radius-sm) 0;
    color: var(--muted-foreground);
    outline: none;
    touch-action: manipulation;
    transition-property: background-color, color, box-shadow;
    transition-duration: var(--duration-fast);
    transition-timing-function: var(--ease);
    & .tun-icon { width: calc(var(--spacing) * 4); height: calc(var(--spacing) * 4); }
    &:focus-visible { box-shadow: var(--focus-ring); }
    @media (hover: hover) { &:hover { background-color: var(--accent); color: var(--foreground); } }
    &:active { background-color: var(--pressed); transition-duration: 0s; }
    @media (pointer: coarse) { width: var(--control-height); }
  }
  & .tun-list-toolbar-filter-heading { display: none; }

  /* A toggle is one button: a box to tick, drawn as the button it is. */
  & .tun-list-toolbar-toggle {
    position: relative;
    display: inline-flex;
    align-items: center;
    gap: calc(var(--spacing) * 1.5);
    height: var(--control-height);
    padding-inline: calc(var(--spacing) * 3) calc(var(--spacing) * 2.5);
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    background-color: var(--background);
    color: var(--foreground);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    font-weight: var(--font-weight-medium);
    white-space: nowrap;
    cursor: pointer;
    user-select: none;
    touch-action: manipulation;
    transition-property: background-color, border-color, box-shadow;
    transition-duration: var(--duration-fast);
    transition-timing-function: var(--ease);
    & .tun-icon {
      width: calc(var(--spacing) * 4);
      height: calc(var(--spacing) * 4);
      color: var(--muted-foreground);
    }
    & .tun-list-toolbar-toggle-on { display: none; }
    &:has(:checked) {
      border-color: var(--border-strong);
      background-color: var(--secondary);
      & .tun-list-toolbar-toggle-on { display: inline-flex; }
      & .tun-list-toolbar-toggle-off { display: none; }
    }
    &:has(:focus-visible) { box-shadow: var(--focus-ring); }
    @media (hover: hover) { &:hover { background-color: var(--accent); } }
    &:active { background-color: var(--pressed); transition-duration: 0s; }
  }
  & .tun-list-toolbar-toggle-input {" +visually-hidden-css+ "
  }

  /* «Reset»: words, underlined. */
  & .tun-list-toolbar-reset {
    display: inline-flex;
    align-items: center;
    min-height: var(--control-height);
    padding-inline: var(--spacing);
    border-radius: var(--radius-sm);
    color: var(--foreground);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    text-decoration: underline;
    text-underline-offset: 0.2em;
    white-space: nowrap;
    outline: none;
    touch-action: manipulation;
    &:focus-visible { box-shadow: var(--focus-ring); }
    @media (hover: hover) { &:hover { text-decoration-thickness: 2px; } }
    &:active { background-color: var(--pressed); transition-duration: 0s; }
  }
  /* «Apply» only where no script applies a choice at once. */
  & .tun-button[data-tun-list-toolbar-apply] {
    @media (scripting: enabled) { display: none; }
  }

  /* The choices: a popover under the button that rises a little as it
     fades in, sinks as it leaves. */
  & .tun-list-toolbar-choices {
    position: fixed;
    min-width: 12rem;
    width: max-content;
    max-width: min(22rem, calc(100vw - var(--spacing) * 4));
    max-height: min(28rem, calc(100dvh - var(--spacing) * 4));
    margin: auto;
    padding: calc(var(--spacing) * 3) calc(var(--spacing) * 4);
    overflow-y: auto;
    overscroll-behavior: contain;
    border: 0;
    border-radius: var(--radius-lg);
    background-color: var(--popover);
    color: var(--popover-foreground);
    box-shadow: 0 0 0 1px var(--border), var(--shadow-md);
    outline: none;
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
    &::backdrop { background-color: transparent; }
    & .tun-fieldset-legend {
      margin-bottom: var(--spacing);
      padding-inline-end: calc(var(--spacing) * 8);
    }
    & :is(.tun-radios-label, .tun-checkbox-label) { width: 100%; }
    /* On a phone the popover is a floating sheet at the bottom, over the
       dim, with its own close button. */
    @media (max-width: 39.99rem) {
      inset: auto calc(var(--spacing) * 3)
             calc(var(--spacing) * 3 + env(safe-area-inset-bottom));
      width: auto;
      min-width: 0;
      max-width: none;
      max-height: 75dvh;
      margin: 0;
      padding: calc(var(--spacing) * 4);
      border-radius: var(--radius-xl);
      translate: 0 calc(var(--spacing) * 6);
      &:popover-open {
        transition-duration: var(--duration);
        @starting-style { opacity: 0; translate: 0 calc(var(--spacing) * 6); }
      }
      &::backdrop {
        background-color: var(--overlay);
        opacity: 0;
        transition-property: opacity, display, overlay;
        transition-duration: var(--duration-close);
        transition-timing-function: var(--ease);
        transition-behavior: allow-discrete;
      }
      &:popover-open::backdrop {
        opacity: 1;
        transition-duration: var(--duration);
        @starting-style { opacity: 0; }
      }
    }
  }
  /* A period: its quick choices, a chosen one by its frame, and its two
     date fields. */
  & .tun-list-toolbar-quick {
    display: flex;
    flex-wrap: wrap;
    gap: calc(var(--spacing) * 2);
  }
  & .tun-list-toolbar-quick-choice {
    display: inline-flex;
    align-items: center;
    min-height: var(--control-height-sm);
    padding-inline: calc(var(--spacing) * 3);
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    background-color: var(--background);
    color: var(--foreground);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    font-weight: var(--font-weight-medium);
    white-space: nowrap;
    outline: none;
    touch-action: manipulation;
    transition-property: background-color, border-color, box-shadow;
    transition-duration: var(--duration-fast);
    transition-timing-function: var(--ease);
    &[aria-current='true'] { border-color: var(--border-strong); background-color: var(--secondary); }
    &:focus-visible { box-shadow: var(--focus-ring); }
    @media (hover: hover) { &:hover { background-color: var(--accent); } }
    &:active { background-color: var(--pressed); transition-duration: 0s; }
    @media (pointer: coarse) { min-height: var(--control-height); }
  }
  & .tun-list-toolbar-period-fields { display: grid; gap: calc(var(--spacing) * 4); }
  @media (min-width: 40rem) {
    & .tun-list-toolbar-filter[data-kind='period'] .tun-list-toolbar-choices { width: 20rem; }
  }
  & .tun-list-toolbar-choices-close {
    display: none;
    position: absolute;
    top: calc(var(--spacing) * 2);
    inset-inline-end: calc(var(--spacing) * 2);
    @media (max-width: 39.99rem) { display: block; }
  }
  /* Under its button where the browser can anchor it; the script places it
     elsewhere. */
  @media (min-width: 40rem) {
    @supports (anchor-scope: all) and (position-try-fallbacks: flip-block) {
      & .tun-list-toolbar-filter { anchor-scope: --tun-list-toolbar-filter; }
      & .tun-list-toolbar-filter-control { anchor-name: --tun-list-toolbar-filter; }
      & .tun-list-toolbar-choices {
        position-anchor: --tun-list-toolbar-filter;
        position-area: block-end span-inline-end;
        position-try-fallbacks: flip-inline, flip-block, flip-block flip-inline;
        inset: auto;
        margin: var(--spacing) 0;
        min-width: max(12rem, anchor-size(width));
      }
    }
  }

  /* The «Filters» sheet: a row per filter, its choices under it in place
     of the popover. */
  & .tun-dialog[data-tun-list-toolbar-sheet][open] {
    & .tun-list-toolbar-filters {
      flex-direction: column;
      gap: calc(var(--spacing) * 5);
      padding: 0;
      margin: 0;
      overflow: visible;
    }
    & .tun-list-toolbar-filter { flex-direction: column; align-items: stretch; }
    & .tun-list-toolbar-filter-control { display: none; }
    & .tun-list-toolbar-filter-heading {
      display: flex;
      align-items: center;
      gap: calc(var(--spacing) * 2);
      min-height: var(--control-height);
      font-weight: var(--font-weight-medium);
      & .tun-list-toolbar-filter-value { color: var(--muted-foreground); }
      & .tun-list-toolbar-filter-clear {
        align-self: stretch;
        margin-inline-start: auto;
        border-inline-start: 0;
        border-radius: var(--radius-md);
      }
    }
    & .tun-list-toolbar-choices {
      display: block;
      position: static;
      inset: auto;
      width: auto;
      min-width: 0;
      max-width: none;
      max-height: none;
      margin: 0;
      padding: 0;
      overflow: visible;
      border-radius: 0;
      background-color: transparent;
      box-shadow: none;
      opacity: 1;
      translate: none;
      pointer-events: auto;
      & .tun-fieldset-legend {" +visually-hidden-css+ "
      }
    }
    & .tun-list-toolbar-choices-close { display: none; }
    & .tun-list-toolbar-toggle { align-self: flex-start; }
  }
}"))
  (:script "
// A list's toolbar (spec/ui.md 6, list-toolbar): a choice, a toggle, a
// clear and «Reset» submit the form at once; in a boosted shell htmx morphs
// the page into the answer, so the open popover, the open sheet and the
// focus stay.  The choices' popover keeps its button's aria-expanded, and
// stands under it where the browser cannot anchor it.
const toolbarChoices = '[data-tun-list-toolbar] [data-tun-list-toolbar-choices]';
const toolbarAnchored = CSS.supports('anchor-scope: all')
  && CSS.supports('position-try-fallbacks: flip-block');
const choicesButton = (choices) => choices.closest('[data-tun-list-toolbar-filter]')
  ?.querySelector('.tun-list-toolbar-filter-button');
// A submission whose fields are those the page shows, or those last sent,
// is not sent again, so a date entered with Enter and then left sends once.
const toolbarFields = (form) => new URLSearchParams(new FormData(form)).toString();
const submitToolbar = (form) => {
  const fields = toolbarFields(form);
  if (form.tunSent === fields) return;
  form.tunSent = fields;
  if (form.requestSubmit) form.requestSubmit(); else form.submit();
};
const shown = (element) => element && element.getClientRects().length > 0;

const placeChoices = (choices) => {
  const button = choicesButton(choices)?.parentElement;
  if (!button || toolbarAnchored || window.innerWidth < 640) return;
  const edge = 8;
  const gap = 4;
  const box = button.getBoundingClientRect();
  Object.assign(choices.style, { inset: 'auto', margin: '0', maxHeight: '' });
  const width = choices.offsetWidth;
  const viewport = document.documentElement.clientWidth;
  const below = window.innerHeight - box.bottom - gap - edge;
  const above = box.top - gap - edge;
  choices.style.left = `${Math.max(edge, Math.min(box.left, viewport - width - edge))}px`;
  if (choices.offsetHeight <= below || below >= above) {
    choices.style.top = `${box.bottom + gap}px`;
    choices.style.maxHeight = `${below}px`;
  } else {
    choices.style.maxHeight = `${above}px`;
    choices.style.top = `${box.top - gap - choices.offsetHeight}px`;
  }
};

tunOnContent((root) => {
  for (const form of root.querySelectorAll('[data-tun-list-toolbar]')) form.tunSent = toolbarFields(form);
  if (root.matches?.('[data-tun-list-toolbar]')) root.tunSent = toolbarFields(root);
  for (const choices of root.querySelectorAll(toolbarChoices))
    choicesButton(choices)?.setAttribute('aria-expanded', String(tunPopoverOpen(choices)));
});

document.addEventListener('toggle', (event) => {
  const choices = event.target;
  if (!(choices instanceof Element) || !choices.matches(toolbarChoices)) return;
  const button = choicesButton(choices);
  const open = event.newState === 'open';
  button?.setAttribute('aria-expanded', String(open));
  if (open) {
    placeChoices(choices);
    // A period starts on its quick choices, so a phone shows no keyboard
    // until a date field is tapped.
    const first = choices.querySelector('[data-tun-list-toolbar-quick][aria-current=true]')
      || choices.querySelector('[data-tun-list-toolbar-quick]')
      || choices.querySelector('input:checked:not([type=hidden])')
      || choices.querySelector('input:not([type=hidden])');
    first?.focus({ preventScroll: true });
  } else if (choices.contains(document.activeElement) || document.activeElement === document.body) {
    button?.focus({ preventScroll: true });
  }
}, true);

// A choice applies at once: one of several closes its popover first, so
// the focus is on its button; several of several stay open.
// A period's date applies when it is left or entered, or chosen in the
// calendar, never while it is being typed.
const toolbarDate = (input) => input instanceof HTMLInputElement
  && input.matches('[data-tun-list-toolbar] .tun-date-input-control');
document.addEventListener('keydown', (event) => {
  if (event.key !== 'Enter' || !toolbarDate(event.target)) return;
  event.preventDefault();
  submitToolbar(event.target.closest('[data-tun-list-toolbar]'));
});

document.addEventListener('change', (event) => {
  const input = event.target;
  if (toolbarDate(input)) {
    submitToolbar(input.closest('[data-tun-list-toolbar]'));
    return;
  }
  if (!(input instanceof HTMLInputElement) || !input.matches('[type=radio], [type=checkbox]')) return;
  const form = input.closest('[data-tun-list-toolbar]');
  if (!form) return;
  const choices = input.closest('[data-tun-list-toolbar-choices]');
  if (input.type === 'radio' && choices && tunPopoverOpen(choices)) choices.hidePopover();
  submitToolbar(form);
});

// A clear or «Reset» empties the filters' fields and submits, so it goes
// the same way as a choice; the link is for a page without scripts.
document.addEventListener('click', (event) => {
  const link = event.target instanceof Element
    && event.target.closest('[data-tun-list-toolbar] a:is([data-tun-list-toolbar-clear], [data-tun-list-toolbar-reset])');
  if (!link || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey) return;
  const form = link.closest('[data-tun-list-toolbar]');
  const name = link.dataset.tunListToolbarClear;
  for (const filter of form.querySelectorAll('[data-tun-list-toolbar-filter]')) {
    if (name !== undefined && filter.dataset.tunListToolbarFilter !== name) continue;
    for (const input of filter.querySelectorAll('input[type=radio], input[type=checkbox]'))
      input.checked = input.type === 'radio' && input.value === '';
    for (const input of filter.querySelectorAll('.tun-date-input-control')) input.value = '';
  }
  event.preventDefault();
  const filter = name === undefined ? null
    : form.querySelector(`[data-tun-list-toolbar-filter='${CSS.escape(name)}']`);
  const inSheet = link.closest('dialog[open]');
  const next = inSheet ? filter?.querySelector('input:not([type=hidden])')
    : [filter?.querySelector('.tun-list-toolbar-filter-button'),
       form.querySelector('[data-tun-list-toolbar-fold]'),
       form.querySelector('input[type=search]')].find(shown);
  next?.focus({ preventScroll: true });
  submitToolbar(form);
});

// A period's quick choice fills both days as the page writes a date, closes
// the popover, the focus on its button, and submits; the link is for a page
// without scripts.
document.addEventListener('click', (event) => {
  const link = event.target instanceof Element
    && event.target.closest('[data-tun-list-toolbar] a[data-tun-list-toolbar-quick]');
  if (!link || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey) return;
  event.preventDefault();
  const form = link.closest('[data-tun-list-toolbar]');
  const [from, to] = link.closest('[data-tun-list-toolbar-filter]')
    .querySelectorAll('.tun-date-input-control');
  from.value = link.dataset.from;
  to.value = link.dataset.to;
  const choices = link.closest('[data-tun-list-toolbar-choices]');
  if (choices && tunPopoverOpen(choices)) choices.hidePopover();
  submitToolbar(form);
});

window.addEventListener('resize', () => {
  for (const choices of document.querySelectorAll(toolbarChoices))
    if (tunPopoverOpen(choices)) placeChoices(choices);
});")
  (:examples
   (("No filter in use" :layout :stack)
    (list-toolbar (:action "/orders" :id "orders-toolbar"
                   :search (list :name "q" :label "Search orders")
                   :filters (list (list :name "status" :label "Status" :kind :one
                                        :choices '(("draft" "Draft") ("quote_sent" "Quote sent")
                                                   ("confirmed" "Confirmed")
                                                   ("completed" "Completed")))
                                  (list :name "tag" :label "Tags" :kind :several
                                        :choices '(("rental" "Rental")
                                                   ("entertainment" "Entertainment")))))))
   (("Each kind in use, and «Reset»" :layout :stack)
    (list-toolbar (:action "/orders" :id "orders-in-use"
                   :search (list :name "q" :label "Search orders" :value "bakery")
                   :filters (list (list :name "status" :label "Status" :kind :one
                                        :choices '(("draft" "Draft") ("quote_sent" "Quote sent")
                                                   ("confirmed" "Confirmed"))
                                        :value "confirmed")
                                  (list :name "tag" :label "Tags" :kind :several
                                        :choices '(("rental" "Rental")
                                                   ("entertainment" "Entertainment"))
                                        :value '("rental" "entertainment"))
                                  (list :name "dateless" :label "Without a date" :kind :toggle
                                        :value t))
                   :keep '(("sort" "date")))))
   (("One filter in use of two" :layout :stack)
    (list-toolbar (:action "/invoices" :id "invoices-toolbar"
                   :search (list :name "q" :label "Search invoices")
                   :filters (list (list :name "state" :label "State" :kind :one
                                        :all "Every state"
                                        :choices '(("open" "Open") ("overdue" "Overdue")
                                                   ("paid" "Paid"))
                                        :value "overdue")
                                  (list :name "mine" :label "Mine" :kind :toggle)))))
   (("A period in use" :layout :stack)
    (list-toolbar (:action "/rentals" :id "rentals-toolbar"
                   :search (list :name "q" :label "Search rentals")
                   :filters (list (list :name "state" :label "State" :kind :one
                                        :choices '(("booked" "Booked") ("out" "Out")
                                                   ("returned" "Returned")))
                                  (list :kind :period :label "Period" :names '("from" "to")
                                        :value '("2026-11-01" "2026-11-14"))))))
   (("Filters without a search" :layout :stack)
    (list-toolbar (:action "/staff" :id "staff-toolbar"
                   :filters (list (list :name "team" :label "Team" :kind :several
                                        :choices '(("stage" "Stage") ("sound" "Sound")
                                                   ("light" "Light") ("drivers" "Drivers"))
                                        :value '("sound")))))))
  (unless action (error "A list toolbar needs :action, the list's address"))
  (mapc #'check-filter filters)
  (when search (require-label 'list-toolbar (getf search :label) "a label for its search"))
  (let* ((base (or id "tun-list-toolbar"))
         (sheet-id (format nil "~a-sheet" base))
         (fold (>= (length filters) +fold-from+))
         (in-use (count-if #'filter-in-use-p filters))
         (markup (mapcar (lambda (filter)
                           (filter-markup base filter
                                          (toolbar-href action search filters keep
                                                        :cleared (list filter))
                                          action search filters keep))
                         filters))
         (row `(:div (:@ :class "tun-list-toolbar-filters") ,@markup)))
    `(:form ,(attrs (list :class "tun-list-toolbar" :id base :method "get" :action action
                          :role "search" :aria-label label
                          :data-tun-list-toolbar t
                          :hx-swap "innerMorph" :hx-push-url "true")
                    attributes)
            (:div (:@ :class "tun-list-toolbar-row")
                  ,@(when search
                      (let ((input-id (format nil "~a-search" base)))
                        `((:div (:@ :class "tun-list-toolbar-search")
                                (:label (:@ :class "tun-list-toolbar-search-label" :for ,input-id)
                                        ,(getf search :label))
                                ,(icon (:name :search))
                                (:input (:@ :class "tun-list-toolbar-search-input" :id ,input-id
                                            :type "search" :name ,(getf search :name)
                                            :value ,(or (getf search :value) "")
                                            :placeholder ,(getf search :label)
                                            :enterkeyhint "search"))))))
                  ,@(when fold (list (fold-button sheet-id in-use)))
                  ,@(when filters
                      (list (if fold
                                (dialog* (list :id sheet-id :title (tr "Filters")
                                               :attributes (list :data-tun-list-toolbar-sheet t))
                                         row)
                                row)))
                  ,@(when (>= in-use 2)
                      `((:a (:@ :class "tun-list-toolbar-reset"
                                :href ,(toolbar-href action search filters keep :cleared :all)
                                :hx-boost "false"
                                :data-tun-list-toolbar-reset t)
                            ,(tr "Reset"))))
                  ,(button (:type "submit" :variant :outline
                            :attributes (list :data-tun-list-toolbar-apply t))
                           (tr "Apply")))
            ,@(loop for (key value) in keep
                    when value
                      collect `(:input (:@ :type "hidden" :name ,key
                                           :value ,(princ-to-string value)))))))
