;;;; web/ui/fields.lisp -- the fields a person types a date, a time of day
;;;; and an amount in, as they write them, and the date's calendar
;;;; (spec/ui.md 6, date-input, time-input, money-input).
;;;;
;;;; Each field posts what is typed, and the server reads it
;;;; (READ-DATE-TEXT, READ-TIME-TEXT, READ-MONEY-TEXT): one reader judges
;;;; every value.  The calendar's script reads a date only to open on it.

(in-package #:tun.ui)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Date

(defun date-calendar-data ()
  "The attributes that give the calendar's script the page's words and
today: the month names, their short forms, the label of a day, today (the
tenant's) and the form a date is written in."
  (flet ((names (function count)
           (format nil "~{~a~^|~}" (loop for n from 1 to count collect (funcall function n)))))
    (list :data-months (names #'month-name 12)
          :data-month-abbreviations (names #'month-abbreviation 12)
          :data-days (names #'calendar-day-name 7)
          :data-day-label (tr "{weekday} {day} {month} {year}")
          :data-title (tr "{month} {year}")
          :data-week-start (princ-to-string (week-first-day))
          :data-today (page-today)
          :data-format (if (equal (current-language) "nb") "nb" "en"))))

(defun quick-dates (quick today)
  "The quick choices QUICK asks for: T for «Today» and «Tomorrow», else
QUICK's own (LABEL DATE) pairs."
  (if (eq quick t)
      (list (list (tr "Today") today)
            (list (tr "Tomorrow") (date-add-days today 1)))
      quick))

(defun outside-range-p (date min max)
  "True when DATE, YYYY-MM-DD, is before MIN or after MAX (either may be NIL)."
  (and (or (and min (string< date min)) (and max (string> date max))) t))

(defun date-calendar (id title-id &key min max quick)
  "The calendar a date field's button opens: its month between two buttons,
the grid the script fills, and QUICK's choices."
  (let ((today (page-today))
        (first (week-first-day)))
    `(:div ,(attrs (list :class "tun-date-input-calendar" :id id :popover "auto"
                         :role "dialog" :aria-modal "true" :aria-labelledby title-id
                         :data-tun-date-calendar t :data-min min :data-max max)
                   (date-calendar-data))
           (:div (:@ :class "tun-date-input-calendar-head")
                 ,(button (:variant :ghost :size :icon :label (tr "Previous month")
                           :attributes (list :data-tun-date-step "-1"))
                          (icon (:name :chevron-left)))
                 (:h2 (:@ :class "tun-date-input-calendar-title" :id ,title-id
                          :aria-live "polite"))
                 ,(button (:variant :ghost :size :icon :label (tr "Next month")
                           :attributes (list :data-tun-date-step "1"))
                          (icon (:name :chevron-right)))
                 (:div (:@ :class "tun-date-input-calendar-close")
                       ,(button (:variant :ghost :size :icon :label (tr "Close")
                                 :attributes (list :popovertarget id :popovertargetaction "hide"))
                                (icon (:name :x)))))
           (:table (:@ :class "tun-date-input-grid" :role "grid" :aria-labelledby ,title-id)
                   (:thead
                    (:tr ,@(loop for n from 0 below 7
                                 for day = (1+ (mod (+ first n -1) 7))
                                 collect `(:th (:@ :scope "col" :abbr ,(calendar-day-name day))
                                               ,(calendar-day-short-name day)))))
                   (:tbody))
           ,@(when quick
               `((:div (:@ :class "tun-date-input-quick")
                       ,@(loop for (label date) in (quick-dates quick today)
                               collect (button (:variant :outline :size :sm
                                                :disabled (outside-range-p date min max)
                                                :attributes (list :data-tun-date-quick date))
                                               label))))))))

(defun date-hint (hint form-hint)
  "HINT, the caller's, followed by the form a date is written in when
FORM-HINT; NIL for neither."
  (if form-hint
      (format nil "~@[~a ~]~a" hint (tr "For example, ~a" (date-text "2026-10-21")))
      hint))

(defun date-value (value)
  "VALUE as a date field shows it, and the date it names, YYYY-MM-DD, when
it names one: an ISO date as DATE-TEXT writes it, any other text as it is."
  (cond ((not (stringp value)) (values nil nil))
        ((valid-date-string-p value) (values (date-text value) value))
        (t (values value (read-date-text value)))))

(define-component date-input ((&key label name value hint error required optional label-hidden
                                    min max quick autocomplete disabled (form-hint t) id
                                    attributes))
  (:group "Forms")
  (:doc "A text field for a date, typed as a person writes it (21.10.2026, 21102026, 21 Oct),
with a calendar where scripts run. VALUE, YYYY-MM-DD, is shown as the page's language writes a
date; another text, such as one posted back with its error, as it is. The page reads what is
posted with read-date-text. MIN and MAX grey out the calendar's other days; QUICK is t for
«Today» and «Tomorrow», or (LABEL DATE) pairs. The hint ends with the form a date is written
in, unless FORM-HINT is nil, as for a second field beside a first.")
  (:source "The owner's rules for an admin application, 2026-11 (the date field); WAI-ARIA date
picker dialog pattern; Basecoat input (Vega), its look")
  (:css (concatenate 'string "
.tun-date-input {
  position: relative;
  display: flex;
  width: 100%;
  /* A date as the longest language writes it, and the calendar's button. */
  max-width: calc(12ch + var(--spacing) * 5 + var(--control-height) + 2px);
  & .tun-date-input-control { font-variant-numeric: tabular-nums; }
  & .tun-date-input-open {
    display: none;
    position: absolute;
    inset-block: 0;
    inset-inline-end: 0;
    align-items: center;
    justify-content: center;
    width: var(--control-height);
    border: 0;
    border-radius: 0 var(--radius-md) var(--radius-md) 0;
    background-color: transparent;
    color: var(--muted-foreground);
    outline: none;
    cursor: pointer;
    touch-action: manipulation;
    transition-property: background-color, color, box-shadow;
    transition-duration: var(--duration-fast);
    transition-timing-function: var(--ease);
    & .tun-icon { width: calc(var(--spacing) * 4); height: calc(var(--spacing) * 4); }
    &:focus-visible { box-shadow: var(--focus-ring-inset); }
    @media (hover: hover) { &:hover { background-color: var(--accent); color: var(--foreground); } }
    &:active { background-color: var(--pressed); transition-duration: 0s; }
    &:disabled { cursor: not-allowed; opacity: 0.5; }
  }
  /* The calendar's button only where a script opens it. */
  @media (scripting: enabled) {
    & .tun-date-input-open { display: inline-flex; }
    & .tun-date-input-control { padding-inline-end: var(--control-height); }
  }

  /* The calendar: a popover under the field that rises a little as it fades
     in and sinks as it leaves. */
  & .tun-date-input-calendar {
    position: fixed;
    width: 20rem;
    max-width: calc(100vw - var(--spacing) * 4);
    max-height: calc(100dvh - var(--spacing) * 4);
    margin: auto;
    padding: calc(var(--spacing) * 3);
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
    /* On a phone a floating sheet at the bottom, over the dim. */
    @media (max-width: 39.99rem) {
      inset: auto calc(var(--spacing) * 3) calc(var(--spacing) * 3 + env(safe-area-inset-bottom));
      width: auto;
      max-width: none;
      max-height: 85dvh;
      margin: 0;
      padding: calc(var(--spacing) * 2) calc(var(--spacing) * 2) calc(var(--spacing) * 3);
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
  /* Under the field where the browser can anchor it; the script places it
     elsewhere. */
  @media (min-width: 40rem) {
    @supports (anchor-scope: all) and (position-try-fallbacks: flip-block) {
      anchor-scope: --tun-date-input;
      anchor-name: --tun-date-input;
      & .tun-date-input-calendar {
        position-anchor: --tun-date-input;
        position-area: block-end span-inline-end;
        position-try-fallbacks: flip-inline, flip-block, flip-block flip-inline;
        inset: auto;
        margin: var(--spacing) 0;
      }
    }
  }
  & .tun-date-input-calendar-head {
    display: flex;
    align-items: center;
    gap: var(--spacing);
    margin-bottom: calc(var(--spacing) * 2);
  }
  & .tun-date-input-calendar-title {
    flex: 1;
    min-width: 0;
    text-align: center;
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    font-weight: var(--font-weight-semibold);
    text-wrap: nowrap;
  }
  & .tun-date-input-calendar-close {
    display: none;
    @media (max-width: 39.99rem) { display: block; }
  }
  & .tun-date-input-grid {
    width: 100%;
    table-layout: fixed;
    border-collapse: separate;
    border-spacing: 0;
    & th {
      padding-block: var(--spacing);
      color: var(--muted-foreground);
      font-size: var(--text-xs);
      line-height: var(--text-xs--line-height);
      font-weight: var(--font-weight-normal);
      text-align: center;
    }
  }
  /* A day.  Today has a frame and the chosen day the ink fill, at the
     weight and size of the others: choosing moves nothing. */
  & .tun-date-input-day {
    height: calc(var(--spacing) * 10);
    padding: 0;
    border: 1px solid transparent;
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    font-variant-numeric: tabular-nums;
    text-align: center;
    cursor: pointer;
    user-select: none;
    outline: none;
    touch-action: manipulation;
    transition-property: background-color, color, border-color, box-shadow;
    transition-duration: var(--duration-fast);
    transition-timing-function: var(--ease);
    @media (pointer: coarse) { height: calc(var(--spacing) * 11); }
    &[data-outside] { color: var(--muted-foreground); }
    &[aria-current='date'] { border-color: var(--border-strong); }
    &[aria-selected='true'] { background-color: var(--primary); color: var(--primary-foreground); }
    /* A day that cannot be chosen: faded and struck through, as in the
       source; 0.4 keeps the number legible. */
    &[aria-disabled='true'] { cursor: not-allowed; opacity: 0.4; text-decoration: line-through; }
    &:focus-visible { box-shadow: var(--focus-ring-inset); }
    @media (hover: hover) {
      &:hover:not([aria-disabled='true'], [aria-selected='true']) {
        background-color: var(--accent);
      }
    }
    &:active:not([aria-disabled='true'], [aria-selected='true']) {
      background-color: var(--pressed);
      transition-duration: 0s;
    }
  }
  & .tun-date-input-quick {
    display: flex;
    flex-wrap: wrap;
    gap: calc(var(--spacing) * 2);
    margin-top: calc(var(--spacing) * 3);
  }
}"))
  (:script "
// The date field's calendar (spec/ui.md 6, date-input): a month the button
// opens under the field (a floating sheet on a phone), the WAI-ARIA date
// picker dialog pattern's keys, and a chosen day written in the field as
// the page writes a date.  The script never judges a date: it reads one
// only to open on it, and the server reads what is posted.
if (typeof HTMLElement.prototype.showPopover !== 'function') return;
const dateParts = (element) => {
  const box = element.closest('[data-tun-date-input]');
  return box && {
    box,
    input: box.querySelector('.tun-date-input-control'),
    button: box.querySelector('.tun-date-input-open'),
    calendar: box.querySelector('[data-tun-date-calendar]'),
  };
};
const pad = (number, size = 2) => String(number).padStart(size, '0');
const isoOf = (year, month, day) => `${pad(year, 4)}-${pad(month)}-${pad(day)}`;
const utc = (iso) => { const [y, m, d] = iso.split('-').map(Number); return new Date(Date.UTC(y, m - 1, d)); };
const isoOfDate = (date) => isoOf(date.getUTCFullYear(), date.getUTCMonth() + 1, date.getUTCDate());
const realDate = (year, month, day) => {
  if (!(year >= 1900 && year <= 9999 && month >= 1 && month <= 12 && day >= 1)) return null;
  const iso = isoOf(year, month, day);
  return isoOfDate(utc(iso)) === iso ? iso : null;
};
const addDays = (iso, count) => { const date = utc(iso); date.setUTCDate(date.getUTCDate() + count); return isoOfDate(date); };
const addMonths = (iso, count) => {
  const date = utc(iso);
  const first = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + count, 1));
  const last = new Date(Date.UTC(first.getUTCFullYear(), first.getUTCMonth() + 1, 0)).getUTCDate();
  first.setUTCDate(Math.min(date.getUTCDate(), last));
  return isoOfDate(first);
};
// 1 for Monday to 7 for Sunday.
const weekdayOf = (iso) => ((utc(iso).getUTCDay() + 6) % 7) + 1;
const words = (calendar, key) => (calendar.dataset[key] || '').split('|');
const outside = (calendar, iso) => (calendar.dataset.min && iso < calendar.dataset.min)
  || (calendar.dataset.max && iso > calendar.dataset.max);

// A day as the page writes a date: 21.10.2026, or 21 Oct 2026.
const writtenDate = (calendar, iso) => {
  const [year, month, day] = iso.split('-');
  return calendar.dataset.format === 'nb' ? `${day}.${month}.${year}`
    : `${Number(day)} ${words(calendar, 'monthAbbreviations')[Number(month) - 1]} ${year}`;
};

// The date the field holds, to open on: the one the page wrote or the
// calendar chose, or one written as ISO, as D.M.YYYY or as the page writes
// a date; else none.
const fieldDate = (parts) => {
  const { input, calendar } = parts;
  const text = input.value.trim();
  if (input.tunChosen && input.tunChosen.text === input.value) return input.tunChosen.iso;
  if (input.dataset.tunDateValue && input.value === input.defaultValue) return input.dataset.tunDateValue;
  let match = /^(\\d{4})-(\\d{1,2})-(\\d{1,2})$/.exec(text);
  if (match) return realDate(+match[1], +match[2], +match[3]);
  match = /^(\\d{1,2})[.\\/-](\\d{1,2})[.\\/-](\\d{4})$/.exec(text);
  if (match) return realDate(+match[3], +match[2], +match[1]);
  match = /^(\\d{1,2})\\.? ([^\\s\\d]+) (\\d{4})$/u.exec(text);
  if (match) {
    const month = words(calendar, 'monthAbbreviations')
      .findIndex((name) => name.toLowerCase() === match[2].toLowerCase()) + 1;
    if (month > 0) return realDate(+match[3], month, +match[1]);
  }
  return null;
};

const dayLabel = (calendar, iso) => {
  const [year, month, day] = iso.split('-').map(Number);
  return tunText(calendar.dataset.dayLabel, {
    weekday: words(calendar, 'days')[weekdayOf(iso) - 1], day,
    month: words(calendar, 'months')[month - 1], year });
};

// Six weeks from the week's first day on or before the 1st of ISO's month,
// so the calendar keeps its height; FOCUS is the one day Tab reaches.
const showMonth = (parts, focus) => {
  const { calendar } = parts;
  const [year, month] = focus.split('-').map(Number);
  const first = isoOf(year, month, 1);
  const start = Number(calendar.dataset.weekStart || 1);
  let day = addDays(first, -((weekdayOf(first) - start + 7) % 7));
  const title = calendar.querySelector('.tun-date-input-calendar-title');
  title.textContent = tunText(calendar.dataset.title,
                              { month: words(calendar, 'months')[month - 1], year });
  const body = calendar.querySelector('tbody');
  body.replaceChildren();
  for (let week = 0; week < 6; week += 1) {
    const row = document.createElement('tr');
    for (let n = 0; n < 7; n += 1) {
      const cell = document.createElement('td');
      cell.className = 'tun-date-input-day';
      cell.dataset.date = day;
      cell.textContent = String(Number(day.slice(8)));
      cell.setAttribute('aria-label', dayLabel(calendar, day));
      cell.tabIndex = day === focus ? 0 : -1;
      if (day.slice(0, 7) !== first.slice(0, 7)) cell.dataset.outside = '';
      if (day === calendar.dataset.today) cell.setAttribute('aria-current', 'date');
      if (day === calendar.tunChosen) cell.setAttribute('aria-selected', 'true');
      if (outside(calendar, day)) cell.setAttribute('aria-disabled', 'true');
      row.append(cell);
      day = addDays(day, 1);
    }
    body.append(row);
  }
  calendar.tunFocus = focus;
};

const focusDay = (parts, iso) => {
  const cell = parts.calendar.querySelector(`td[data-date='${iso}']`);
  if (!cell || cell.hasAttribute('data-outside')) showMonth(parts, iso);
  else {
    for (const each of parts.calendar.querySelectorAll('td[tabindex]')) each.tabIndex = -1;
    cell.tabIndex = 0;
    parts.calendar.tunFocus = iso;
  }
  parts.calendar.querySelector(`td[data-date='${iso}']`)?.focus({ preventScroll: true });
};

const placeCalendar = (parts) => {
  const anchored = CSS.supports('anchor-scope: all') && CSS.supports('position-try-fallbacks: flip-block');
  if (anchored || window.innerWidth < 640) return;
  const { calendar } = parts;
  const edge = 8;
  const gap = 4;
  const box = parts.box.getBoundingClientRect();
  Object.assign(calendar.style, { inset: 'auto', margin: '0' });
  const width = calendar.offsetWidth;
  const height = calendar.offsetHeight;
  const viewport = document.documentElement.clientWidth;
  calendar.style.left = `${Math.max(edge, Math.min(box.left, viewport - width - edge))}px`;
  const below = window.innerHeight - box.bottom - gap - edge;
  const above = box.top - gap - edge;
  calendar.style.top = height <= below || below >= above
    ? `${box.bottom + gap}px` : `${Math.max(edge, box.top - gap - height)}px`;
};

const chooseDay = (parts, iso) => {
  if (!iso || outside(parts.calendar, iso)) return;
  const text = writtenDate(parts.calendar, iso);
  parts.input.value = text;
  parts.input.tunChosen = { iso, text };
  parts.input.dispatchEvent(new Event('input', { bubbles: true }));
  parts.input.dispatchEvent(new Event('change', { bubbles: true }));
  parts.calendar.hidePopover();
  parts.button.focus({ preventScroll: true });
};

document.addEventListener('toggle', (event) => {
  const calendar = event.target;
  if (!(calendar instanceof Element) || !calendar.matches('[data-tun-date-calendar]')) return;
  const parts = dateParts(calendar);
  const open = event.newState === 'open';
  parts.button.setAttribute('aria-expanded', String(open));
  if (open) {
    calendar.tunChosen = fieldDate(parts);
    let start = calendar.tunChosen || calendar.dataset.today;
    if (calendar.dataset.min && start < calendar.dataset.min) start = calendar.dataset.min;
    if (calendar.dataset.max && start > calendar.dataset.max) start = calendar.dataset.max;
    showMonth(parts, start);
    placeCalendar(parts);
    focusDay(parts, start);
  } else {
    // Escape, a press outside or a choice gives the focus back to the
    // button, unless the press put it on another control.
    const active = document.activeElement;
    const control = active && active !== document.body && !calendar.contains(active)
      && active.matches('input, select, textarea, button, a[href], [tabindex]:not([tabindex=\"-1\"])');
    if (!control) parts.button.focus({ preventScroll: true });
  }
}, true);

document.addEventListener('click', (event) => {
  if (!(event.target instanceof Element)) return;
  const calendar = event.target.closest('[data-tun-date-calendar]');
  if (!calendar) return;
  const parts = dateParts(calendar);
  const step = event.target.closest('[data-tun-date-step]');
  const quick = event.target.closest('[data-tun-date-quick]');
  const day = event.target.closest('td[data-date]');
  if (step) showMonth(parts, addMonths(calendar.tunFocus, Number(step.dataset.tunDateStep)));
  else if (quick) chooseDay(parts, quick.dataset.tunDateQuick);
  else if (day) chooseDay(parts, day.dataset.date);
});

// The pattern's keys on a day, and Tab kept inside the calendar.
document.addEventListener('keydown', (event) => {
  if (!(event.target instanceof Element)) return;
  const calendar = event.target.closest('[data-tun-date-calendar]');
  if (!calendar) return;
  const parts = dateParts(calendar);
  if (event.key === 'Tab') {
    const stops = [...calendar.querySelectorAll('button:not(:disabled), td[tabindex=\"0\"]')]
      .filter((element) => element.getClientRects().length > 0);
    const at = stops.indexOf(document.activeElement);
    const next = stops[(at + (event.shiftKey ? -1 : 1) + stops.length) % stops.length];
    if (next) { event.preventDefault(); next.focus({ preventScroll: true }); }
    return;
  }
  const cell = event.target.closest('td[data-date]');
  if (!cell) return;
  const iso = cell.dataset.date;
  const start = Number(calendar.dataset.weekStart || 1);
  const intoWeek = (weekdayOf(iso) - start + 7) % 7;
  const moves = {
    ArrowLeft: () => addDays(iso, -1), ArrowRight: () => addDays(iso, 1),
    ArrowUp: () => addDays(iso, -7), ArrowDown: () => addDays(iso, 7),
    PageUp: () => addMonths(iso, event.shiftKey ? -12 : -1),
    PageDown: () => addMonths(iso, event.shiftKey ? 12 : 1),
    Home: () => addDays(iso, -intoWeek), End: () => addDays(iso, 6 - intoWeek),
  };
  if (moves[event.key]) {
    event.preventDefault();
    focusDay(parts, moves[event.key]());
  } else if (event.key === 'Enter' || event.key === ' ') {
    event.preventDefault();
    chooseDay(parts, iso);
  }
});

window.addEventListener('resize', () => {
  for (const calendar of document.querySelectorAll('[data-tun-date-calendar]'))
    if (tunPopoverOpen(calendar)) placeCalendar(dateParts(calendar));
});")
  (:examples
   (("Empty, filled, with an error, disabled" :layout :stack)
    (date-input (:label "Delivery date" :name "delivery"))
    (date-input (:label "Invoice date" :name "invoice-date" :value "2026-11-21"))
    (date-input (:label "Return date" :name "return" :value "31.11.2026"
                 :error "The date must exist, such as 30.11.2026"))
    (date-input (:label "Ordered on" :name "ordered" :value "2026-10-02" :disabled t)))
   (("With quick choices and the days that can be chosen" :layout :stack)
    (date-input (:label "Event date" :name "event" :quick t :min "2026-11-01" :max "2027-06-30"
                 :hint "The first day of the event.")))
   (("Quick choices of the page's own" :layout :stack)
    (date-input (:label "Due date" :name "due" :value "2026-12-01"
                 :quick '(("In 14 days" "2026-11-26") ("End of the month" "2026-11-30"))))))
  (require-label 'date-input label)
  (let* ((id (or id (element-id (or name "date"))))
         (calendar-id (format nil "~a-calendar" id))
         (title-id (format nil "~a-calendar-title" id))
         (hint (date-hint hint form-hint)))
    (multiple-value-bind (shown date) (date-value value)
      (field* (list :label label :for id :hint hint :error error :optional optional
                    :label-hidden label-hidden)
              `(:div (:@ :class "tun-date-input" :data-tun-date-input t)
                     ,(text-input-markup "tun-text-input tun-date-input-control" id
                                         :type :text :name name :value shown :hint hint
                                         :error error :required required
                                         :autocomplete (or autocomplete "off")
                                         :inputmode "decimal" :disabled disabled
                                         :attributes (append (list :data-tun-date-value date)
                                                             attributes))
                     (:button ,(attrs (list :type "button" :class "tun-date-input-open"
                                            :popovertarget calendar-id
                                            :aria-label (tr "Choose a date")
                                            :aria-haspopup "dialog" :aria-expanded "false"
                                            :aria-controls calendar-id :disabled disabled))
                              ,(icon (:name :calendar)))
                     ,(date-calendar calendar-id title-id :min min :max max :quick quick))))))

;;; ------------------------------------------------------------------
;;; Time of day

(define-component time-input ((&key label name value hint error required optional label-hidden
                                    disabled id attributes))
  (:group "Forms")
  (:doc "A text field for a time of day, 24 hours, typed as a person writes it (9, 930, 9.30,
09:30). It posts what is typed; the page reads it with read-time-text into HH:MM. VALUE is shown
as it is.")
  (:source "The owner's rules for an admin application, 2026-11 (the time field, without its
picker); Basecoat input (Vega), its look")
  (:css "
.tun-time-input { font-variant-numeric: tabular-nums; }")
  (:examples
   (("Empty, filled, with an error, disabled" :layout :stack)
    (time-input (:label "Starts at" :name "starts"))
    (time-input (:label "Ends at" :name "ends" :value "17:30"))
    (time-input (:label "Pick-up" :name "pickup" :value "25:00"
                 :error "The time must be from 00:00 to 23:59"))
    (time-input (:label "Delivered at" :name "delivered" :value "08:15" :disabled t))))
  (require-label 'time-input label)
  (let ((id (or id (element-id (or name "time"))))
        (hint (format nil "~@[~a ~]~a" hint (tr "For example, ~a" "09:30"))))
    (field* (list :label label :for id :hint hint :error error :optional optional
                  :label-hidden label-hidden)
            (text-input-markup "tun-time-input tun-text-input" id
                               :type :text :name name :value value :hint hint :error error
                               :required required :autocomplete "off" :inputmode "decimal"
                               :disabled disabled :width 5 :attributes attributes))))

;;; ------------------------------------------------------------------
;;; Money

(define-component money-input ((&key label name value currency hint error required optional
                                     label-hidden (width 10) disabled readonly id attributes))
  (:group "Forms")
  (:doc "An amount in a currency (CURRENCY, the tenant's by default), typed as a person writes
it in the page's language (1 250,50, 1250.5), right-aligned in tabular figures with the currency
before or after it as the language writes it. VALUE, an integer of minor units, is written as
the language writes the amount; another text as it is. The page reads what is posted with
read-money-text.")
  (:source "The owner's rules for an admin application, 2026-11 (amounts); Basecoat input group
(Vega), its look")
  (:css "
.tun-money-input {
  & > .tun-input-group-control { text-align: end; font-variant-numeric: tabular-nums; }
}")
  (:examples
   (("Empty, filled, with an error, disabled" :layout :stack)
    (money-input (:label "Price" :name "price" :currency "EUR"))
    (money-input (:label "Deposit" :name "deposit" :currency "EUR" :value 125050))
    (money-input (:label "Discount" :name "discount" :currency "EUR" :value "12.505"
                  :error "The amount can have at most 2 decimals"))
    (money-input (:label "Paid" :name "paid" :currency "NOK" :value 99900 :disabled t))))
  (require-label 'money-input label)
  (check-width width)
  (let ((id (or id (element-id (or name "amount"))))
        (currency (or currency (current-currency)))
        (width (unless (eq width :full) width)))
    (multiple-value-bind (mark place) (currency-mark currency)
      (flet ((addon () `(:span (:@ :class "tun-input-group-addon" :aria-hidden "true") ,mark)))
        (field* (list :label label :for id :hint hint :error error :optional optional
                      :label-hidden label-hidden)
                `(:div ,(attrs (list :class "tun-money-input tun-input-group"
                                     :data-width (when width (princ-to-string width))))
                       ,@(when (eq place :before) (list (addon)))
                       ,(text-input-markup "tun-input-group-control" id
                                           :type :text :name name
                                           :value (if (integerp value)
                                                      (money-number-text value :currency currency)
                                                      value)
                                           :hint hint :error error :required required
                                           :autocomplete "off" :inputmode "decimal"
                                           :disabled disabled :readonly readonly
                                           :attributes attributes)
                       ,@(when (eq place :after) (list (addon)))))))))
