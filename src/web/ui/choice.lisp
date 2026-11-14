;;;; web/ui/choice.lisp -- choosing one record among many by typing
;;;; (spec/ui.md 6, choice-input, choice-options): a field that posts the
;;;; chosen record's id and shows its text, its options given with the page
;;;; or asked for as one types, and the list a choice's address answers.
;;;;
;;;; One select carries the value with or without scripts; where scripts
;;;; run it is hidden and set by the script, and a button that reads as a
;;;; field opens a popover with a text field and the options.  The list's
;;;; parts are found by data-tun-choice-* attributes, so a list's toolbar
;;;; (toolbar.lisp) uses the same script for its :choice filter.

(in-package #:tun.ui)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; choice-options

(define-component choice-options ((&key query options more value label id attributes))
  (:group "Forms")
  (:doc "The options of a choice-input or a list's :choice filter, as a list a person moves
through: OPTIONS are (VALUE TEXT) pairs, the one of VALUE marked chosen; MORE, how many more
matched than are shown, gives a line that asks to type more. A choice's address answers it
(choice-answer); a page rarely writes it itself.")
  (:source "Tun's own, after its owner's rules for an admin application, 2026-11 (select with
a search); WAI-ARIA listbox")
  (:css "
.tun-choice-options {
  display: flex;
  flex-direction: column;
  gap: 1px;
  margin: 0;
  padding: 0;
  list-style: none;
  & .tun-choice-options-option {
    display: flex;
    align-items: center;
    gap: calc(var(--spacing) * 2);
    min-height: var(--control-height);
    padding: calc(var(--spacing) * 1.5) calc(var(--spacing) * 2.5);
    border-radius: var(--radius-sm);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    overflow-wrap: anywhere;
    cursor: default;
    user-select: none;
    -webkit-tap-highlight-color: transparent;
    &[hidden] { display: none; }
    /* The active option, the one Enter chooses: the ground of an option
       under a pointer and the frame of what is chosen, at the others'
       weight, size and padding. */
    &[aria-selected='true'] {
      background-color: var(--accent);
      box-shadow: inset 0 0 0 1px var(--border-strong);
    }
    &:active { background-color: var(--pressed); transition-duration: 0s; }
    & > .tun-icon {
      flex: none;
      margin-inline-start: auto;
      width: calc(var(--spacing) * 4);
      height: calc(var(--spacing) * 4);
      visibility: hidden;
    }
    /* The chosen option has its check mark. */
    &[data-chosen] > .tun-icon { visibility: visible; }
  }
  @media (hover: hover) {
    & .tun-choice-options-option:hover { background-color: var(--accent); }
  }
  & .tun-choice-options-more, & .tun-choice-options-none {
    padding: calc(var(--spacing) * 2) calc(var(--spacing) * 2.5);
    color: var(--muted-foreground);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    &[hidden] { display: none; }
  }
}")
  (:examples
   ("The options for «nord», one chosen and more found"
    (choice-options (:query "nord" :value "cus_1" :more 12
                     :options '(("cus_1" "Nordvik Bakery Ltd") ("cus_11" "Ola Nordmann")
                                ("cus_23" "Narvik Northern Lights Tours")))))
   ("Nothing found"
    (choice-options (:query "zebra" :options '()))))
  `(:ul ,(attrs (list :class "tun-choice-options" :id id :role "listbox" :aria-label label
                      :data-tun-choice-query query)
                attributes)
        ,@(loop for (option-value text) in options
                for n from 0
                collect `(:li ,(attrs (list :class "tun-choice-options-option"
                                            :id (when id (format nil "~a-~d" id n))
                                            :role "option" :aria-selected "false"
                                            :data-value (princ-to-string option-value)
                                            :data-chosen (when (same-value-p option-value value)
                                                           "true")))
                              (:span (:@ :class "tun-choice-options-text")
                                     ,(princ-to-string text))
                              ,(icon (:name :check))))
        ,@(when (and more (plusp more))
            `((:li (:@ :class "tun-choice-options-more" :role "presentation")
                   ,(tr "~a more. Type to narrow them." (number-text more)))))
        (:li ,(attrs (list :class "tun-choice-options-none" :role "presentation"
                           :hidden (when options t)))
             ,(tr "No match"))))

;;; ------------------------------------------------------------------
;;; The parts a choice's script finds, shared with a list's toolbar

(defun choice-field (id label &key source list-id placeholder)
  "The text field a choice is typed in: a combobox controlling LIST-ID, of no
form, asking SOURCE as one types when there is one."
  `(:input ,(attrs (list :class "tun-text-input" :type "text" :id id
                         :form (format nil "~a-alone" id)
                         :autocomplete "off" :spellcheck "false" :enterkeyhint "done"
                         :placeholder (or placeholder label) :aria-label label
                         :role "combobox" :aria-expanded "true" :aria-autocomplete "list"
                         :aria-controls list-id :data-tun-choice-field t)
                   (when source
                     (list :name "q" :hx-get source
                           :hx-trigger "input changed delay:150ms, tun-choice-ask"
                           :hx-target (format nil "#~a-box" list-id)
                           :hx-swap "innerHTML" :hx-sync "this:replace")))))

(defun choice-list-box (class list-id options value source)
  "The box of a choice's list, CLASS its host's, holding OPTIONS as
CHOICE-OPTIONS: an asked list carries no query until its first answer."
  `(:div (:@ :class ,class :id ,(format nil "~a-box" list-id) :data-tun-choice-list t)
         ,(choice-options* (list :id list-id :options options :value value
                                 :query (unless source "")))))

(defun choice-found-line (class find count)
  "Under a find field after a find step: how many FIND found, or that
nothing matches it."
  (when find
    `(:p (:@ :class ,class :role "status")
         ,(if (plusp count)
              (tr "~d found" count)
              (tr "Nothing matches «~a»" find)))))

(defun chosen-text (options value)
  "The text of VALUE among OPTIONS, or NIL."
  (second (find-if (lambda (option) (same-value-p (first option) value)) options)))

;;; ------------------------------------------------------------------
;;; choice-input

(define-component choice-input ((&key label name value options source find placeholder hint
                                      error required optional disabled label-hidden id
                                      attributes))
  (:group "Forms")
  (:doc "Choosing one record among many by typing, such as an order's customer: it posts the
chosen option's value (an id) under NAME and shows its text. OPTIONS are (VALUE TEXT) pairs:
every choice when they come with the page (a few dozen at most), or, with SOURCE, the address
that answers the options for what is typed (choice-answer), the chosen one and a find step's
matches. Check what is posted with read-choice. Without scripts it is a select, with SOURCE
and a «Find» step (choice-find, FIND the text found). For a short list, a select or radios are
better; for a free text with suggestions, a combobox.")
  (:source "The owner's rules for an admin application, 2026-11 (select with a search, its
clear button, opening upward); WAI-ARIA combobox and listbox; GOV.UK select")
  (:css (concatenate 'string "
.tun-choice-input {
  display: flex;
  flex-direction: column;
  gap: calc(var(--spacing) * 2);
  min-width: 0;
  /* What a script hides once it runs, and what it shows. */
  &[data-tun-ready] > .tun-choice-input-select,
  &[data-tun-ready] > .tun-choice-input-find { display: none; }
  &:not([data-tun-ready]) > .tun-choice-input-control,
  &:not([data-tun-ready]) > .tun-choice-input-popover { display: none; }
  & > .tun-choice-input-select {
    appearance: auto;
    display: block;
    width: 100%;
    min-width: 0;
    height: var(--control-height);
    padding: var(--spacing) calc(var(--spacing) * 2.5);" (control-css) "
  }
  & .tun-choice-input-control { position: relative; min-width: 0; }
  /* The button that reads as a field: the chosen text, else the
     placeholder muted, a chevron at the end. */
  & .tun-choice-input-trigger {
    display: flex;
    align-items: center;
    width: 100%;
    min-width: 0;
    height: var(--control-height);
    padding: var(--spacing) calc(var(--spacing) * 9) var(--spacing) calc(var(--spacing) * 2.5);
    text-align: start;
    cursor: pointer;
    touch-action: manipulation;
    -webkit-tap-highlight-color: transparent;" (control-css) "
    @media (hover: hover) {
      &:hover:not(:disabled) {
        background-image: linear-gradient(var(--accent), var(--accent));
      }
    }
    &:active:not(:disabled) {
      background-image: linear-gradient(var(--pressed), var(--pressed));
      transition-duration: 0s;
    }
  }
  & .tun-choice-input-text {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    &[data-empty] { color: var(--muted-foreground); }
  }
  & .tun-choice-input-chevron {
    position: absolute;
    top: 50%;
    inset-inline-end: calc(var(--spacing) * 2.5);
    translate: 0 -50%;
    display: flex;
    color: var(--muted-foreground);
    pointer-events: none;
  }
  /* The clear button, 2rem wide (the control's height on a touch screen),
     inside the field before its chevron. */
  & .tun-choice-input-clear {
    position: absolute;
    top: 50%;
    inset-inline-end: calc(var(--spacing) * 8);
    translate: 0 -50%;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: calc(var(--spacing) * 8);
    height: calc(var(--spacing) * 8);
    border: 0;
    border-radius: var(--radius-sm);
    background-color: transparent;
    color: var(--muted-foreground);
    cursor: pointer;
    outline: none;
    touch-action: manipulation;
    transition-property: background-color, color, box-shadow;
    transition-duration: var(--duration-fast);
    transition-timing-function: var(--ease);
    &[hidden] { display: none; }
    & .tun-icon { width: calc(var(--spacing) * 4); height: calc(var(--spacing) * 4); }
    &:focus-visible { box-shadow: var(--focus-ring); }
    @media (hover: hover) {
      &:hover { background-color: var(--accent); color: var(--foreground); }
    }
    &:active { background-color: var(--pressed); transition-duration: 0s; }
    @media (pointer: coarse) {
      width: var(--control-height);
      height: var(--control-height);
    }
  }
  & .tun-choice-input-control:has(> .tun-choice-input-clear:not([hidden]))
    > .tun-choice-input-trigger {
    padding-inline-end: calc(var(--spacing) * 17);
    @media (pointer: coarse) {
      padding-inline-end: calc(var(--spacing) * 9 + var(--control-height));
    }
  }

  /* The list: a popover in the top layer, under the field, or above it
     with the text field last, placed by the script; it rises a little as
     it fades in and sinks as it leaves. */
  & .tun-choice-input-popover {
    position: fixed;
    inset: auto;
    flex-direction: column;
    gap: var(--spacing);
    margin: 0;
    padding: var(--spacing);
    border: 0;
    border-radius: var(--radius-lg);
    background-color: var(--popover);
    color: var(--popover-foreground);
    box-shadow: 0 0 0 1px var(--border), var(--shadow-md);
    overflow: hidden;
    opacity: 0;
    translate: 0 var(--spacing);
    transition-property: opacity, translate, display, overlay;
    transition-duration: var(--duration-close);
    transition-timing-function: var(--ease);
    transition-behavior: allow-discrete;
    &:not(:popover-open) { pointer-events: none; }
    &:popover-open {
      display: flex;
      opacity: 1;
      translate: none;
      transition-duration: var(--duration-fast);
      @starting-style { opacity: 0; translate: 0 var(--spacing); }
    }
    &[data-above] { flex-direction: column-reverse; }
    &::backdrop { background-color: transparent; }
  }
  & .tun-choice-input-header { display: none; }
  & .tun-choice-input-list {
    flex: 1;
    min-height: 0;
    max-height: 18rem;
    overflow-y: auto;
    overscroll-behavior: contain;
  }
  /* On a phone the list is a floating sheet at the bottom of what a
     keyboard leaves of the window, over the dim, as high from the start
     as it will be, so the text field never moves. */
  @media (max-width: 39.99rem) {
    & .tun-choice-input-popover {
      inset: auto calc(var(--spacing) * 3)
             calc(var(--spacing) * 3
                  + max(var(--tun-visual-bottom, 0px), env(safe-area-inset-bottom)));
      width: auto;
      height: min(24rem, calc(100dvh - var(--tun-visual-top, 0px)
                                - var(--tun-visual-bottom, 0px) - var(--spacing) * 11));
      padding: calc(var(--spacing) * 3);
      gap: calc(var(--spacing) * 2);
      border-radius: var(--radius-xl);
      translate: 0 calc(var(--spacing) * 6);
      &:popover-open {
        transition-duration: var(--duration);
        @starting-style { opacity: 0; translate: 0 calc(var(--spacing) * 6); }
      }
      &[data-above] { flex-direction: column; }
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
    & .tun-choice-input-header {
      display: flex;
      flex: none;
      align-items: center;
      justify-content: space-between;
      gap: calc(var(--spacing) * 2);
      font-size: var(--text-base);
      line-height: var(--text-base--line-height);
      font-weight: var(--font-weight-medium);
    }
    & .tun-choice-input-list { max-height: none; }
  }

  /* Without scripts, an asked choice's «Find» step. */
  & .tun-choice-input-find {
    display: flex;
    flex-direction: column;
    gap: calc(var(--spacing) * 2);
  }
  & .tun-choice-input-find-row {
    display: flex;
    gap: calc(var(--spacing) * 2);
    & > .tun-text-input { flex: 1; }
    & > .tun-button { flex: none; }
  }
  & .tun-choice-input-found {
    color: var(--muted-foreground);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
  }
  & .tun-choice-input-find-label {
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
  }
  /* The form's first submit button, which Enter presses: out of sight, but
     rendered, since some browsers press no default button that is not. */
  & .tun-choice-input-default {" +visually-hidden-css+ "
  }
}"))
  (:script "
// Choosing one record among many by typing (spec/ui.md 6, choice-input):
// a select carries the value; once this runs it is hidden and set from a
// list of options a person narrows by typing.  Given options narrow here
// by the search's fold; asked ones come from the server (htmx asks after a
// pause), and only the answer for what the field holds now is shown.  The
// same parts serve a list's :choice filter (toolbar.lisp), found by
// data-tun-choice-* attributes.  A browser without popovers keeps the
// select.
if (typeof HTMLElement.prototype.showPopover !== 'function') return;
const choiceParts = (root) => ({
  root,
  select: root.querySelector('[data-tun-choice-select]'),
  field: root.querySelector('[data-tun-choice-field]'),
  box: root.querySelector('[data-tun-choice-list]'),
  trigger: root.querySelector('[data-tun-choice-trigger]'),
  text: root.querySelector('[data-tun-choice-text]'),
  clear: root.querySelector('[data-tun-choice-clear]'),
});
const choiceOf = (element) => choiceParts(element.closest('[data-tun-choice]'));
const choiceList = (parts) => parts.box?.querySelector('[role=listbox]');
const choiceOptions = (parts) => [...(choiceList(parts)?.querySelectorAll('[role=option]') ?? [])];
const choiceShown = (parts) => choiceOptions(parts).filter((option) => !option.hidden);
const choiceAsked = (parts) => parts.field.hasAttribute('hx-get');
const choicePopover = (parts) => parts.field.closest('[popover]');
const choiceText = (option) => option.querySelector('.tun-choice-options-text')?.textContent ?? '';
const choiceWaiting = new WeakMap();

// The search's fold (spec/ui.md 6.4): case, marks and the letters it
// spells otherwise, a run of a as one a, any run of spaces as one.
const choiceLetters = { 'ø': 'o', 'æ': 'ae', 'œ': 'oe', 'ß': 'ss', 'ł': 'l', 'đ': 'd' };
const choiceFold = (text) => text.toLowerCase().normalize('NFD').replace(/\\p{M}/gu, '')
  .replace(/[øæœßłđ]/g, (letter) => choiceLetters[letter]).replace(/a+/g, 'a')
  .replace(/\\s+/g, ' ').trim();

// The list's id is the one the field controls, and each option's follows
// it, so an answer from the server needs none of its own.
const choiceName = (parts) => {
  const list = choiceList(parts);
  if (!list) return;
  list.id = parts.field.getAttribute('aria-controls');
  choiceOptions(parts).forEach((option, n) => {
    option.id = `${list.id}-${n}`;
    option.toggleAttribute('data-chosen', option.dataset.value === parts.select.value);
  });
};

const choiceActivate = (parts, option) => {
  for (const each of choiceOptions(parts))
    each.setAttribute('aria-selected', String(each === option));
  if (option) {
    parts.field.setAttribute('aria-activedescendant', option.id);
    option.scrollIntoView({ block: 'nearest' });
  } else parts.field.removeAttribute('aria-activedescendant');
};
const choiceActive = (parts) => choiceShown(parts)
  .find((option) => option.getAttribute('aria-selected') === 'true');
const choiceChosen = (parts) => choiceShown(parts)
  .find((option) => option.dataset.value === parts.select.value && parts.select.value !== '');

// Given options: every word typed, folded, is a part of the option's text.
const choiceNarrow = (parts) => {
  const words = choiceFold(parts.field.value).split(' ').filter(Boolean);
  for (const option of choiceOptions(parts)) {
    const text = choiceFold(choiceText(option));
    option.hidden = !words.every((word) => text.includes(word));
  }
  const none = choiceList(parts)?.querySelector('.tun-choice-options-none');
  if (none) none.hidden = choiceShown(parts).length > 0;
  choiceActivate(parts, words.length > 0 ? choiceShown(parts)[0] : choiceChosen(parts));
};

// The field's button shows the chosen text, else the placeholder.
const choiceShow = (parts) => {
  const option = parts.select.selectedOptions[0];
  const chosen = parts.select.value !== '';
  if (parts.text) {
    parts.text.textContent = chosen ? option.textContent : parts.root.dataset.tunChoicePlaceholder;
    parts.text.toggleAttribute('data-empty', !chosen);
  }
  if (parts.clear) parts.clear.hidden = !chosen || parts.select.disabled;
};

const choiceAsk = (parts) => parts.field.dispatchEvent(new Event('tun-choice-ask'));
// The field holds a text no answer has shown yet.
const choiceBehind = (parts) => choiceAsked(parts)
  && choiceList(parts)?.getAttribute('data-tun-choice-query') !== parts.field.value;

const choiceChoose = (parts, option) => {
  if (!option) return;
  const value = option.dataset.value;
  let item = [...parts.select.options].find((each) => each.value === value);
  if (!item) {
    item = new Option(choiceText(option), value);
    parts.select.add(item);
  }
  parts.select.value = value;
  choiceShow(parts);
  choiceName(parts);
  const popover = choicePopover(parts);
  if (popover && tunPopoverOpen(popover)) popover.hidePopover();
  parts.trigger?.focus({ preventScroll: true });
  parts.select.dispatchEvent(new Event('change', { bubbles: true }));
};

// Under the field from 40rem, or above it, the text field last, when the
// list needs more room than there is below and there is more above; a
// phone's sheet is CSS's own.
const choicePlace = (parts) => {
  const popover = choicePopover(parts);
  if (!popover || !parts.trigger) return;
  Object.assign(popover.style, { left: '', top: '', bottom: '', width: '', maxHeight: '' });
  delete popover.dataset.above;
  if (window.innerWidth < 640) return;
  const edge = 8;
  const gap = 4;
  const rem = parseFloat(getComputedStyle(document.documentElement).fontSize) || 16;
  const box = parts.trigger.getBoundingClientRect();
  const viewport = document.documentElement.clientWidth;
  const width = Math.min(Math.max(box.width, 18 * rem), viewport - 2 * edge);
  const needed = parts.field.offsetHeight + 18 * rem + rem;
  const below = window.innerHeight - box.bottom - gap - edge;
  const above = box.top - gap - edge;
  popover.style.width = `${width}px`;
  popover.style.left = `${Math.max(edge, Math.min(box.left, viewport - width - edge))}px`;
  if (needed <= below || below >= above) {
    popover.style.top = `${box.bottom + gap}px`;
    popover.style.maxHeight = `${below}px`;
  } else {
    popover.dataset.above = '';
    popover.style.bottom = `${window.innerHeight - box.top + gap}px`;
    popover.style.maxHeight = `${above}px`;
  }
};
const choiceFollow = () => {
  for (const popover of document.querySelectorAll('[data-tun-choice-popover]'))
    if (tunPopoverOpen(popover)) choicePlace(choiceOf(popover));
};
window.addEventListener('scroll', choiceFollow, { capture: true, passive: true });
window.addEventListener('resize', choiceFollow);

tunOnContent((root) => {
  const roots = [...root.querySelectorAll('[data-tun-choice]')];
  if (root.matches?.('[data-tun-choice]')) roots.push(root);
  for (const each of roots) {
    const parts = choiceParts(each);
    // The find step's field and button leave the form, so they never post;
    // disabled, they would grey the field's label.
    for (const off of each.querySelectorAll('[data-tun-choice-off]'))
      off.setAttribute('form', 'tun-choice-off');
    each.setAttribute('data-tun-ready', '');
    if (parts.trigger) {
      const label = each.closest('.tun-field')?.querySelector(':scope > .tun-field-label');
      label?.setAttribute('for', parts.trigger.id);
    }
    choiceShow(parts);
    choiceName(parts);
  }
});

// Opening puts the focus in the text field, empty, the chosen option
// active; an asked list asks for an empty text when it holds no answer
// for it.
document.addEventListener('toggle', (event) => {
  const popover = event.target;
  if (!(popover instanceof Element) || event.newState !== 'open') return;
  const field = popover.querySelector('[data-tun-choice-field]');
  if (!field || !field.closest('[data-tun-ready]')) return;
  const parts = choiceOf(field);
  parts.trigger?.setAttribute('aria-expanded', 'true');
  field.value = '';
  choicePlace(parts);
  if (choiceAsked(parts)) {
    if (choiceBehind(parts)) choiceAsk(parts);
    choiceActivate(parts, choiceChosen(parts));
  } else choiceNarrow(parts);
  field.focus({ preventScroll: true });
}, true);
document.addEventListener('toggle', (event) => {
  const popover = event.target;
  if (!(popover instanceof Element) || event.newState !== 'closed') return;
  const field = popover.querySelector('[data-tun-choice-field]');
  if (!field) return;
  const parts = choiceOf(field);
  parts.trigger?.setAttribute('aria-expanded', 'false');
  choiceWaiting.delete(field);
  if (parts.trigger && (popover.contains(document.activeElement)
                        || document.activeElement === document.body))
    parts.trigger.focus({ preventScroll: true });
}, true);

// A list laid in place (a list's «Filters» sheet) asks when its field
// takes the focus; one in an open popover asked as it opened.
document.addEventListener('focusin', (event) => {
  const field = event.target;
  if (!(field instanceof HTMLInputElement) || !field.matches('[data-tun-choice-field]')) return;
  const parts = choiceOf(field);
  const popover = choicePopover(parts);
  if (popover && tunPopoverOpen(popover)) return;
  if (choiceAsked(parts) && choiceBehind(parts)) choiceAsk(parts);
});

document.addEventListener('input', (event) => {
  const field = event.target;
  if (!(field instanceof HTMLInputElement) || !field.matches('[data-tun-choice-field]')) return;
  const parts = choiceOf(field);
  if (!choiceAsked(parts)) choiceNarrow(parts);
});

document.addEventListener('keydown', (event) => {
  const field = event.target;
  if (!(field instanceof HTMLInputElement) || !field.matches('[data-tun-choice-field]')
      || event.altKey || event.ctrlKey || event.metaKey || event.isComposing) return;
  const parts = choiceOf(field);
  const shown = choiceShown(parts);
  const active = choiceActive(parts);
  if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
    event.preventDefault();
    if (shown.length === 0) return;
    const at = shown.indexOf(active);
    const step = event.key === 'ArrowDown' ? 1 : -1;
    const next = at < 0 ? (step > 0 ? 0 : shown.length - 1)
      : (at + step + shown.length) % shown.length;
    choiceActivate(parts, shown[next]);
  } else if ((event.key === 'Home' || event.key === 'End') && active && !event.shiftKey) {
    event.preventDefault();
    choiceActivate(parts, event.key === 'Home' ? shown[0] : shown[shown.length - 1]);
  } else if (event.key === 'Enter') {
    event.preventDefault();
    if (choiceBehind(parts)) choiceWaiting.set(field, true);
    else choiceChoose(parts, active ?? shown[0]);
  }
});

document.addEventListener('click', (event) => {
  const target = event.target instanceof Element ? event.target : null;
  const option = target?.closest('[data-tun-choice] [data-tun-choice-list] [role=option]');
  if (option) {
    choiceChoose(choiceOf(option), option);
    return;
  }
  const clear = target?.closest('[data-tun-choice-clear]');
  if (!clear) return;
  const parts = choiceOf(clear);
  parts.select.value = '';
  choiceShow(parts);
  choiceName(parts);
  parts.trigger?.focus({ preventScroll: true });
  parts.select.dispatchEvent(new Event('change', { bubbles: true }));
});
// A press on the list keeps the focus in the text field.
document.addEventListener('mousedown', (event) => {
  if (event.target instanceof Element && event.target.closest('[data-tun-choice-list]'))
    event.preventDefault();
});

// Only the answer for what the field holds now is shown; a failed one
// says so, in the words the server wrote on the choice.
const choiceFailed = (parts) => {
  const list = document.createElement('ul');
  list.className = 'tun-choice-options';
  list.setAttribute('role', 'listbox');
  list.setAttribute('data-tun-choice-query', parts.field.value);
  const line = document.createElement('li');
  line.className = 'tun-choice-options-none';
  line.setAttribute('role', 'alert');
  line.textContent = parts.root.dataset.tunChoiceFailed;
  list.append(line);
  parts.box.replaceChildren(list);
  choiceName(parts);
  choiceWaiting.delete(parts.field);
};
const choiceAnswered = (text) => new DOMParser().parseFromString(text ?? '', 'text/html')
  .querySelector('[data-tun-choice-query]')?.getAttribute('data-tun-choice-query');
document.addEventListener('htmx:before:swap', (event) => {
  const field = event.target;
  if (!(field instanceof Element) || !field.matches('[data-tun-choice-field]')) return;
  const ctx = event.detail.ctx;
  if ((ctx?.response?.status ?? 200) >= 400) {
    event.preventDefault();
    choiceFailed(choiceOf(field));
  } else if (choiceAnswered(ctx?.text) !== field.value) event.preventDefault();
});
document.addEventListener('htmx:error', (event) => {
  const field = event.target;
  if (!(field instanceof Element) || !field.matches('[data-tun-choice-field]')) return;
  if (event.detail?.error?.name === 'AbortError') return;
  choiceFailed(choiceOf(field));
});
document.addEventListener('htmx:after:swap', (event) => {
  const field = event.target;
  if (!(field instanceof Element) || !field.matches('[data-tun-choice-field]')) return;
  const parts = choiceOf(field);
  choiceName(parts);
  const first = choiceShown(parts)[0];
  choiceActivate(parts, field.value.trim() ? first : (choiceChosen(parts) ?? null));
  if (choiceWaiting.get(field) && !choiceBehind(parts)) {
    choiceWaiting.delete(field);
    choiceChoose(parts, first);
  }
});")
  (:examples
   (("Options with the page" :layout :stack)
    (choice-input (:label "Customer" :name "customer_id" :id "specimen-given"
                   :hint "Type part of the name."
                   :options '(("cus_1" "Nordvik Bakery Ltd") ("cus_2" "Hansen Plumbing")
                              ("cus_3" "Fjord Events") ("cus_4" "Bjørn Åsen")
                              ("cus_5" "Kari Hansen") ("cus_6" "Café Øst")
                              ("cus_7" "Tromsø Bicycle Workshop")))))
   (("Asked for as one types" :layout :stack)
    (choice-input (:label "Customer" :name "customer_id" :id "specimen-asked"
                   :source "/ui/choice-input/options")))
   (("Chosen" :layout :stack)
    (choice-input (:label "Customer" :name "customer_id" :id "specimen-chosen" :value "cus_5"
                   :source "/ui/choice-input/options"
                   :options '(("cus_5" "Bjørn Åsen")))))
   (("With an error, and disabled" :layout :stack)
    (choice-input (:label "Customer" :name "customer_id" :id "specimen-error"
                   :error "Choose the customer the order is for"
                   :options '(("cus_1" "Nordvik Bakery Ltd") ("cus_2" "Hansen Plumbing"))))
    (choice-input (:label "Warehouse" :name "warehouse" :id "specimen-disabled" :value "drammen"
                   :disabled t
                   :options '(("drammen" "Drammen") ("oslo" "Oslo")))))
   ;; Chosen, so that where scripts run, which hide the find step, it does
   ;; not read as an empty field.
   (("After a find step, which shows without scripts" :layout :stack)
    (choice-input (:label "Customer" :name "customer_id" :id "specimen-found" :find "hansen"
                   :value "cus_5" :source "/ui/choice-input/options"
                   :options '(("cus_5" "Bjørn Åsen") ("cus_2" "Hansen Plumbing")
                              ("cus_6" "Kari Hansen"))))))
  (require-label 'choice-input label)
  (unless name (error "choice-input needs :name, the key its value is posted under"))
  (dolist (option options)
    (unless (and (consp option) (consp (rest option)))
      (error "A choice-input's option is (VALUE TEXT), not ~s" option)))
  (let* ((id (or id (element-id name)))
         (list-id (format nil "~a-list" id))
         (popover-id (format nil "~a-popover" id))
         (placeholder (or placeholder (tr "Choose")))
         (text (chosen-text options value))
         (described (described-by id hint error)))
    (field* (list :label label :for id :hint hint :error error :optional optional
                  :label-hidden label-hidden)
            `(:div ,(attrs (list :class "tun-choice-input" :data-tun-choice t
                                 :data-tun-choice-placeholder placeholder
                                 :data-tun-choice-failed
                                 (tr "The choices could not be loaded. Try again."))
                           attributes)
                   (:select ,(attrs (list :class "tun-choice-input-select" :name name
                                          :required required :disabled disabled
                                          :data-tun-choice-select t)
                                    (control-attributes id :hint hint :error error))
                            (:option (:@ :value "") ,placeholder)
                            ,@(mapcar (lambda (option)
                                        (option-markup (list (first option) (second option))
                                                       value))
                                      options))
                   (:div (:@ :class "tun-choice-input-control")
                         (:span (:@ :id ,(format nil "~a-name" id) :hidden t) ,label)
                         (:button ,(attrs (list :type "button" :class "tun-choice-input-trigger"
                                                :id (format nil "~a-trigger" id)
                                                :disabled disabled
                                                :popovertarget popover-id
                                                :aria-haspopup "dialog" :aria-expanded "false"
                                                :aria-labelledby (format nil "~a-name ~a-text"
                                                                         id id)
                                                :aria-describedby described
                                                :aria-invalid (when error "true")
                                                :data-tun-choice-trigger t))
                                  (:span ,(attrs (list :class "tun-choice-input-text"
                                                       :id (format nil "~a-text" id)
                                                       :data-empty (unless text t)
                                                       :data-tun-choice-text t))
                                         ,(or text placeholder)))
                         (:button ,(attrs (list :type "button" :class "tun-choice-input-clear"
                                                :aria-label (tr "Clear ~a" label)
                                                :hidden (when (or (null text) disabled) t)
                                                :data-tun-choice-clear t))
                                  ,(icon (:name :x)))
                         (:span (:@ :class "tun-choice-input-chevron" :aria-hidden "true")
                                ,(icon (:name :chevron-down))))
                   (:div (:@ :class "tun-choice-input-popover" :id ,popover-id :popover "auto"
                             :role "dialog" :aria-label ,label
                             :data-tun-choice-popover t :data-tun-keyboard t)
                         (:div (:@ :class "tun-choice-input-header")
                               (:span ,label)
                               ,(button (:variant :ghost :size :icon-sm :label (tr "Close")
                                         :attributes (list :popovertarget popover-id
                                                           :popovertargetaction "hide"))
                                        (icon (:name :x))))
                         ,(choice-field (format nil "~a-search" id) label
                                        :source source :list-id list-id)
                         ,(choice-list-box "tun-choice-input-list" list-id options value source))
                   ,@(when source
                       (list (choice-find-markup id name find options value)))))))

(defun choice-find-markup (id name find options value)
  "Without scripts, an asked choice's «Find» step: a text field, a button
that posts the form as NAME's find, and after one how many it found."
  (let ((find-id (format nil "~a-find" id)))
    `(:div (:@ :class "tun-choice-input-find")
           (:label (:@ :class "tun-choice-input-find-label" :for ,find-id) ,(tr "Find"))
           (:div (:@ :class "tun-choice-input-find-row")
                 (:input ,(attrs (list :class "tun-text-input" :type "search" :id find-id
                                       :name (format nil "~a-find" name) :value find
                                       :autocomplete "off" :data-tun-choice-off t)))
                 ;; spec/ui.md 6, «Enter saves»: the form's first submit button,
                 ;; with no name, so Enter saves rather than finds.
                 (:button (:@ :type "submit" :class "tun-choice-input-default" :tabindex "-1"
                              :aria-hidden "true" :data-tun-choice-off t))
                 ,(button (:type "submit" :variant :outline
                           :attributes (list :name "tun-find" :value name :formnovalidate t
                                             :data-tun-choice-off t))
                          (tr "Find")))
           ,(choice-found-line "tun-choice-input-found" find
                               (count-if-not (lambda (option) (same-value-p (first option) value))
                                             options)))))
