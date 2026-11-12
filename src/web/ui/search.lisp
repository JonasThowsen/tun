;;;; web/ui/search.lisp -- the application's one search (spec/ui.md 6.4):
;;;; its results, as a list of links with what the rule matched marked, and
;;;; its dialog, which asks for them as one types.

(in-package #:tun.ui)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; search-results

(defun marked-text (query text &key identifier)
  "TEXT as markup, the stored characters QUERY's words matched in <mark>;
with IDENTIFIER, those it covers as an identifier when no word matched."
  (let ((at 0) (parts '()))
    (loop for (start . end) in (search-mark-ranges query text :identifier identifier)
          do (when (> start at) (push (subseq text at start) parts))
             (push `(:mark ,(subseq text start end)) parts)
             (setf at end))
    (when (< at (length text)) (push (subseq text at) parts))
    (nreverse parts)))

(defun search-meta-line (query item)
  "The line under a result's title: its kind's word, then what it was found
by (MATCHED) when it has that, then its META; when the title holds no mark,
the matches in MATCHED and META are marked (spec/ui.md 6.4, «Why it was
found»)."
  (let ((mark (null (search-mark-ranges query (getf item :title))))
        (parts (remove-if (lambda (text) (zerop (length text)))
                          (mapcar #'princ-to-string
                                  (remove nil (cons (getf item :matched) (getf item :meta)))))))
    (cons (princ-to-string (getf item :label))
          (loop for part in parts
                append (cons " · " (if mark
                                       (marked-text query part :identifier t)
                                       (list part)))))))

(defun search-row (query item index listbox)
  "The row of ITEM, the INDEXth result, a link to its page."
  `(:li ,@(when listbox '((:@ :role "none")))
        (:a ,(attrs (list :class "tun-search-results-row" :href (getf item :href)
                          :id (when listbox (format nil "tun-search-result-~d" index))
                          :role (when listbox "option")
                          :aria-selected (when listbox (if (zerop index) "true" "false"))))
            (:span (:@ :class "tun-search-results-icon" :aria-hidden "true")
                   ,(icon* (list :name (or (getf item :icon) :file))))
            (:span (:@ :class "tun-search-results-text")
                   (:span (:@ :class "tun-search-results-title")
                          ,@(marked-text query (getf item :title)))
                   (:span (:@ :class "tun-search-results-meta")
                          ,@(search-meta-line query item))))))

(define-component search-results ((&key query items listbox id attributes))
  (:group "Data")
  (:doc "What the application's one search found for QUERY: a list of links, each with its
kind's icon, its title with what matched marked, and a line that starts with its kind. ITEMS
are plists of :kind, :label (the kind's word), :icon, :title, :meta (a list of texts),
:matched (what it was found by, when neither the title nor META shows it) and :href, best first.
A result whose title holds no match has its match marked in the line under it. Under two
characters it is empty; with none it says so. LISTBOX makes it the list a search dialog's
field moves through.")
  (:source "Tun's own, after its owner's rules for an admin application, 2026-11")
  (:css "
.tun-search-results {
  & .tun-search-results-list {
    display: flex;
    flex-direction: column;
    gap: 1px;
    margin: 0;
    padding: 0;
    list-style: none;
  }
  & .tun-search-results-row {
    display: flex;
    align-items: center;
    gap: calc(var(--spacing) * 3);
    min-height: 2.75rem;
    padding: calc(var(--spacing) * 1.5) calc(var(--spacing) * 2.5);
    border-radius: var(--radius-md);
    color: inherit;
    text-decoration: none;
    -webkit-tap-highlight-color: transparent;
    &:focus-visible { outline: none; box-shadow: var(--focus-ring-inset); }
    /* The row Enter opens is chosen: the ground of a row under a pointer
       and the frame of what is chosen, at the others' weight, size and
       padding. */
    &[aria-selected='true'] {
      background-color: var(--accent);
      box-shadow: inset 0 0 0 1px var(--border-strong);
    }
    &:active { background-color: var(--pressed); transition: none; }
  }
  @media (hover: hover) {
    & .tun-search-results-row:hover { background-color: var(--accent); }
  }
  & .tun-search-results-icon {
    display: grid;
    place-items: center;
    flex: none;
    width: calc(var(--spacing) * 8);
    height: calc(var(--spacing) * 8);
    border-radius: var(--radius-md);
    background-color: var(--soft);
    color: var(--muted-foreground);
  }
  & .tun-search-results-text { display: flex; flex-direction: column; min-width: 0; }
  & .tun-search-results-title {
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    font-weight: var(--font-weight-medium);
    overflow-wrap: anywhere;
  }
  & .tun-search-results-meta {
    overflow: hidden;
    color: var(--muted-foreground);
    font-size: var(--text-xs);
    line-height: var(--text-xs--line-height);
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  /* A match inside a word does not split it: a tint of the text colour
     and no padding (the accent is for focus and what is on, spec/ui.md
     2.1). */
  & mark {
    padding: 0;
    background-color: color-mix(in oklab, var(--foreground) 14%, transparent);
    color: inherit;
  }
  & .tun-search-results-empty {
    margin: 0;
    padding: calc(var(--spacing) * 6) calc(var(--spacing) * 3);
    color: var(--muted-foreground);
    text-align: center;
    overflow-wrap: anywhere;
  }
}")
  (:examples
   ("Results for «nord»"
    (search-results (:query "nord"
                     :items '((:kind "customer" :label "Customer" :icon :users
                               :title "Nordvik Bakery Ltd" :meta ("post@nordvik.example")
                               :href "/customers/cus_1")
                              (:kind "order" :label "Order" :icon :shopping-cart
                               :title "Nordvik Bakery Ltd" :meta ("Confirmed" "21 Nov 2026")
                               :href "/orders/ord_1")
                              (:kind "card" :label "Card" :icon :list-checks
                               :title "Move the Nordic price list" :meta ("Planned")
                               :href "/items/crd_1")))))
   ("Accents and case do not matter: «bjorn» marks «Bjørn»"
    (search-results (:query "bjorn ase"
                     :items '((:kind "customer" :label "Customer" :icon :users
                               :title "Bjørn Åsen" :meta ("bjorn@example.com" "412 34 567")
                               :href "/customers/cus_2")))))
   ("Found by the line under the title: the match is marked there"
    (search-results (:query "ex"
                     :items '((:kind "customer" :label "Customer" :icon :users
                               :title "Fjord Events" :meta ("hello@fjord.example")
                               :href "/customers/cus_3")
                              (:kind "order" :label "Order" :icon :shopping-cart
                               :title "Fjord Events" :matched "Exhibition hall 2, Storgata 12"
                               :meta ("Confirmed" "21 Nov 2026")
                               :href "/orders/ord_2")))))
   ("Nothing found"
    (search-results (:query "zebra" :items '()))))
  (let* ((text (or query ""))
         (search (make-search-query text)))
    `(:div ,(attrs (list :class "tun-search-results" :id id :data-tun-search-query text)
                   attributes)
           ,@(cond ((< (length (string-trim " " text)) 2) '())
                   (items
                    `((:ul ,(attrs (list :class "tun-search-results-list"
                                         :role (when listbox "listbox")
                                         :aria-label (when listbox (tr "Results"))))
                           ,@(loop for item in items
                                   for index from 0
                                   collect (search-row search item index listbox)))))
                   (t `((:p (:@ :class "tun-search-results-empty")
                            ,(tr "No results for «~a»" text))))))))

;;; ------------------------------------------------------------------
;;; search-dialog

(define-component search-dialog ((&key (action "/search") value items attributes))
  (:group "Data")
  (:doc "The application's one search in a dialog: a field that asks ACTION for its results
as one types, after a pause, and the results under it, which alone scroll. It opens on Ctrl K
(Cmd K on a Mac) and from a link marked data-tun-search-open; the arrows move the mark over the
results, Enter opens the marked one and Escape closes it. Every app-shell of an application
with a search holds one; a page needs none of its own. VALUE and ITEMS are what it shows when
it opens.")
  (:source "Tun's own, after its owner's rules for an admin application, 2026-11")
  (:css "
.tun-search-dialog {
  display: flex;
  flex-direction: column;
  gap: calc(var(--spacing) * 3);
  height: 100%;
  min-height: 0;
  & .tun-search-dialog-form { flex: none; }
  /* Only the results scroll; the inset keeps the marked row's ring whole. */
  & .tun-search-dialog-results {
    flex: 1;
    min-height: 0;
    margin: calc(var(--spacing) * -0.5);
    padding: calc(var(--spacing) * 0.5);
    overflow-y: auto;
    overscroll-behavior: contain;
  }
}")
  (:script "
// The application's one search (spec/ui.md 6.4).  htmx asks for the
// results as one types (the field's hx-trigger waits for a pause); this
// opens the dialog from its links, shows only the answer for what the field
// holds now, says when an answer failed, and moves the mark and opens the
// marked row from the keys, an Enter typed before the latest answer
// waiting for it.
const searchDialog = () => document.querySelector('dialog[data-tun-search]');
const field = (dialog) => dialog?.querySelector('[data-tun-search-field]');
const box = (dialog) => dialog?.querySelector('[data-tun-search-results]');
const rows = (dialog) => [...(box(dialog)?.querySelectorAll('[role=option]') ?? [])];
const shown = (dialog) => box(dialog)?.querySelector('[data-tun-search-query]')
  ?.getAttribute('data-tun-search-query');
const waiting = new WeakMap();
const opener = new WeakMap();

const mark = (dialog, row) => {
  for (const each of rows(dialog)) each.setAttribute('aria-selected', String(each === row));
  const input = field(dialog);
  if (row) {
    input.setAttribute('aria-activedescendant', row.id);
    row.scrollIntoView({ block: 'nearest' });
  } else input.removeAttribute('aria-activedescendant');
};
const marked = (dialog) => rows(dialog).find((row) => row.getAttribute('aria-selected') === 'true');
const open = (dialog, row) => {
  if (!row) return;
  dialog.close();
  row.click();
};
// The field holds something to search for that no answer has shown yet.
const behind = (dialog) => {
  const value = field(dialog).value;
  return value.trim().length >= 2 && shown(dialog) !== value;
};

document.addEventListener('click', (event) => {
  const link = event.target instanceof Element && event.target.closest('a[data-tun-search-open]');
  const dialog = searchDialog();
  if (!link || !dialog || event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey
      || event.altKey) return;
  event.preventDefault();
  opener.set(dialog, link);
  if (!dialog.open) dialog.showModal();
  field(dialog)?.focus();
});

// What was typed before is chosen when the field takes the focus from
// outside the dialog, so typing replaces it.
document.addEventListener('focusin', (event) => {
  const input = event.target;
  if (!(input instanceof HTMLInputElement) || !input.matches('[data-tun-search-field]')) return;
  const dialog = input.closest('dialog');
  if (!(event.relatedTarget instanceof Element && dialog.contains(event.relatedTarget)))
    input.select();
});

document.addEventListener('close', (event) => {
  const dialog = event.target;
  if (!(dialog instanceof HTMLDialogElement) || !dialog.matches('[data-tun-search]')) return;
  waiting.delete(dialog);
  const link = opener.get(dialog);
  opener.delete(dialog);
  const active = document.activeElement;
  if (link?.isConnected && (!active || active === document.body || dialog.contains(active)))
    link.focus({ preventScroll: true });
}, true);

document.addEventListener('keydown', (event) => {
  const input = event.target;
  if (!(input instanceof HTMLInputElement) || !input.matches('[data-tun-search-field]')
      || event.altKey || event.ctrlKey || event.metaKey || event.isComposing) return;
  const dialog = input.closest('dialog');
  const all = rows(dialog);
  if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
    event.preventDefault();
    if (all.length === 0) return;
    const at = all.indexOf(marked(dialog));
    const step = event.key === 'ArrowDown' ? 1 : -1;
    mark(dialog, all[(at + step + all.length) % all.length]);
  } else if (event.key === 'Enter') {
    event.preventDefault();
    if (behind(dialog)) waiting.set(dialog, true);
    else open(dialog, marked(dialog) ?? all[0]);
  } else if (event.key === 'Escape') {
    // A search field's own Escape empties it; here it closes the search
    // and keeps what was typed for the next time.
    event.preventDefault();
    dialog.close();
  }
});

// An answer is shown only when it answers what the field holds now: a
// slow answer for earlier keys that comes after a newer one is dropped.  A
// failed answer says so, in the words the server wrote on the dialog.
const failed = (dialog) => {
  const results = box(dialog);
  const text = document.createElement('p');
  text.className = 'tun-search-results-empty';
  text.setAttribute('role', 'alert');
  text.textContent = dialog.dataset.tunSearchFailed;
  const holder = document.createElement('div');
  holder.className = 'tun-search-results';
  holder.setAttribute('data-tun-search-query', field(dialog).value);
  holder.append(text);
  results.replaceChildren(holder);
  waiting.delete(dialog);
};
const answered = (text) => new DOMParser().parseFromString(text ?? '', 'text/html')
  .querySelector('[data-tun-search-query]')?.getAttribute('data-tun-search-query');
document.addEventListener('htmx:before:swap', (event) => {
  const input = event.target;
  if (!(input instanceof Element) || !input.matches('[data-tun-search-field]')) return;
  const dialog = input.closest('dialog');
  const ctx = event.detail.ctx;
  if ((ctx?.response?.status ?? 200) >= 400) {
    event.preventDefault();
    failed(dialog);
  } else if (answered(ctx?.text) !== input.value) event.preventDefault();
});
document.addEventListener('htmx:error', (event) => {
  const input = event.target;
  if (!(input instanceof Element) || !input.matches('[data-tun-search-field]')) return;
  if (event.detail?.error?.name === 'AbortError') return;
  failed(input.closest('dialog'));
});
document.addEventListener('htmx:after:swap', (event) => {
  const input = event.target;
  if (!(input instanceof Element) || !input.matches('[data-tun-search-field]')) return;
  const dialog = input.closest('dialog');
  mark(dialog, marked(dialog) ?? null);
  if (waiting.get(dialog) && !behind(dialog)) {
    waiting.delete(dialog);
    open(dialog, rows(dialog)[0]);
  }
});")
  (:examples
   ("The search, opened with Ctrl K or its button"
    (button (:variant :outline :icon :search :shortcut "Ctrl+K" :href "/search"
             :attributes (list :data-tun-search-open t :hx-boost "false"))
            "Search")
    (search-dialog (:value "nord"
                    :items '((:kind "customer" :label "Customer" :icon :users
                              :title "Nordvik Bakery Ltd" :meta ("post@nordvik.example")
                              :href "/customers/cus_1")
                             (:kind "card" :label "Card" :icon :list-checks
                              :title "Move the Nordic price list" :meta ("Planned")
                              :href "/items/crd_1"))))))
  (dialog (:id "tun-search" :title (tr "Search") :size :large :shortcut "Ctrl+K"
           :attributes (append (list :data-tun-search t
                                     :data-tun-search-failed (tr "The search failed. Try again."))
                               attributes))
          `(:div (:@ :class "tun-search-dialog")
                 (:form (:@ :class "tun-search-dialog-form" :method "get" :action ,action
                            :role "search")
                        ,(text-input (:label (tr "Search") :label-hidden t :name "q"
                                      :type :search :value value :autocomplete "off"
                                      :id "tun-search-field"
                                      :attributes (list :autofocus t :role "combobox"
                                                        :aria-expanded "true"
                                                        :aria-autocomplete "list"
                                                        :aria-controls "tun-search-results"
                                                        :data-tun-search-field t
                                                        :hx-get action
                                                        :hx-trigger "input changed delay:150ms"
                                                        :hx-target "#tun-search-results"
                                                        :hx-swap "innerHTML"
                                                        :hx-sync "this:replace"))))
                 (:div (:@ :class "tun-search-dialog-results" :id "tun-search-results"
                           :data-tun-search-results t)
                       ,(search-results (:query value :items items :listbox t))))))
