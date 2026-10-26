;;;; web/ui/board.lisp -- the board: records as cards in columns, one column
;;;; per state, moving a card to another column, and on an ordered board
;;;; putting it in its place within a column (spec/ui.md 6.1).
;;;;
;;;; Moving is a plain form per card, posted by the buttons of the card's
;;;; menu, so it works without JavaScript and from the keyboard.  The script
;;;; adds dragging: a dropped card is moved at once and the menu's button for
;;;; its new column is clicked, which posts the same form, through htmx when
;;;; the page has it.  On an ordered board the card has a second form, for
;;;; its place within its own column; a button posts one name, so the move
;;;; form holds the card and its place (the buttons give the column) and the
;;;; order form the card and its column (the buttons give the place).

(in-package #:tun.ui)

(declaim (optimize (safety 3) (debug 2)))

(defun board-form (id action fields &rest children)
  "A hidden form ID that posts the hidden FIELDS, a plist of names and
values, and CHILDREN to ACTION, through htmx into the board."
  `(:form (:@ :id ,id :method "post" :action ,action :hidden t
              :hx-post ,action :hx-target "closest .tun-board" :hx-swap "outerMorph")
          ,@(loop for (name value) on fields by #'cddr
                  collect `(:input (:@ :type "hidden" :name ,name :value ,value
                                       ,@(when (string= name "before")
                                           (list :data-tun-board-before t)))))
          ,@children))

(defun board-order-items (place form-id)
  "The «Rekkefølge» items of a card at PLACE in its column, a plist
(:FIRST :PREVIOUS :NEXT :AFTER-NEXT) of card ids: each submits the order
form FORM-ID with the before= that puts the card there."
  (destructuring-bind (&key first previous next after-next) place
    (flet ((item (label icon before)
             (list :label label :icon icon
                   :attributes (list :type "submit" :form form-id :name "before"
                                     :value before))))
      (append (when previous
                (list (item "Flytt øverst" :arrow-up-to-line first)
                      (item "Flytt opp" :arrow-up previous)))
              (when next
                (list (item "Flytt ned" :arrow-down (or after-next ""))
                      (item "Flytt nederst" :arrow-down-to-line "")))))))

(defun board-move-item (column form-id)
  "The menu item that moves a card to COLUMN: a button that submits the
card's form FORM-ID with column=KEY."
  (destructuring-bind (&key key title &allow-other-keys) column
    (list :label title :icon :arrow-right
          :attributes (list :type "submit" :form form-id :name "column" :value key
                            :data-tun-board-move key))))

(defun board-card-menu (base title targets order-items form-id)
  "The card's menu: its «Rekkefølge» ORDER-ITEMS, then «Flytt til» the
TARGETS columns, each group only when it has items; NIL when neither has."
  (let ((groups (append (when order-items
                          (list (list :group "Rekkefølge" :items order-items)))
                        (when targets
                          (list (list :group "Flytt til"
                                      :items (mapcar (lambda (column)
                                                       (board-move-item column form-id))
                                                     targets)))))))
    (when groups
      `(:div (:@ :class "tun-board-card-actions")
             ,(dropdown-menu* (list :id (format nil "~a-move" base)
                                    :label (format nil "Flytt «~a»" title)
                                    :size :icon-sm :variant :ghost :icon :ellipsis
                                    :align :end
                                    :items groups))))))

(defun board-card (card &key board-id action columns column-key place)
  "The markup of CARD, a plist (:ID :TITLE :HREF :BADGES :META), in the
column COLUMN-KEY of the board BOARD-ID.  With ACTION it carries the form
that moves it and a menu of the other COLUMNS to move it to.  PLACE, on an
ordered board, is where it is in its column (see BOARD-ORDER-ITEMS): the
card then also has the form and the menu items that order it there."
  (destructuring-bind (&key id title href badges meta) card
    (unless (and id title)
      (error "A board card needs :id and :title"))
    (let* ((base (format nil "~a-~a" board-id id))
           (form-id (format nil "~a-form" base))
           (order-form-id (format nil "~a-order-form" base))
           (targets (remove column-key columns :key (lambda (column) (getf column :key))
                                               :test #'equal))
           (order-items (when place (board-order-items place order-form-id))))
      `(:li (:@ :class "tun-board-card" :id ,base :data-tun-board-card ,id)
            (:div (:@ :class "tun-board-card-head")
                  ,(if href
                       `(:a (:@ :class "tun-board-card-title" :href ,href) ,title)
                       `(:span (:@ :class "tun-board-card-title") ,title))
                  ,@(when action
                      (let ((menu (board-card-menu base title targets order-items form-id)))
                        (when menu (list menu)))))
            ,@(when badges
                `((:div (:@ :class "tun-board-card-badges") ,@badges)))
            ,@(when meta
                `((:p (:@ :class "tun-board-card-meta") ,meta)))
            ,@(when action
                (list (if place
                          ;; The script sets before= and clicks the button
                          ;; of the column a card is dropped in, its own too.
                          (board-form form-id action (list "card" id "before" "")
                                      `(:button (:@ :type "submit" :name "column"
                                                    :value ,column-key
                                                    :data-tun-board-move ,column-key)))
                          (board-form form-id action (list "card" id)))))
            ,@(when order-items
                (list (board-form order-form-id action (list "card" id "column" column-key))))))))

(defun card-places (cards)
  "Where each of CARDS is in its column, as BOARD-CARD's :place."
  (let ((ids (mapcar (lambda (card) (getf card :id)) cards)))
    (loop for previous = nil then (first tail)
          for tail on ids
          collect (list :first (first ids) :previous previous
                        :next (second tail) :after-next (third tail)))))

(defun board-column (column &key board-id action columns heading-level ordered)
  "The markup of COLUMN, a plist (:KEY :TITLE :CARDS :COUNT :EMPTY).  ORDERED
gives each card the menu items and form that put it in its place."
  (destructuring-bind (&key key title cards count (empty "Ingen")) column
    (unless (and key title)
      (error "A board column needs :key and :title"))
    (let ((heading-id (format nil "~a-~a" board-id key))
          (places (if ordered (card-places cards) (make-list (length cards)))))
      `(:section (:@ :class "tun-board-column" :data-tun-board-column ,key
                     :aria-labelledby ,heading-id)
                 (:header (:@ :class "tun-board-column-header")
                          (,(heading-tag heading-level) (:@ :class "tun-board-column-title"
                                                            :id ,heading-id)
                           ,title)
                          (:span (:@ :class "tun-board-column-count" :data-tun-board-count t)
                                 ,(princ-to-string (or count (length cards)))))
                 (:ol (:@ :class "tun-board-cards")
                      ,@(mapcar (lambda (card place)
                                  (board-card card :board-id board-id :action action
                                                   :columns columns :column-key key
                                                   :place place))
                                cards places))
                 (:p (:@ :class "tun-board-empty") ,empty)))))

(define-component board ((&key label columns action ordered message (heading-level 3) id
                                attributes))
  (:group "Data")
  (:doc "Saker som kort i kolonner, én kolonne per status, som en tavle i Asana eller GitHub.
Hver kolonne i COLUMNS er (:key :title :cards :count :empty), hvert kort (:id :title :href
:badges :meta). Med ACTION har hvert kort en meny «Flytt til», som poster card=ID og
column=KEY dit, og med JavaScript kan kortet dras til en annen kolonne (på en berøringsskjerm
etter at man har holdt på det et øyeblikk). Med ORDERED bestemmer man også rekkefølgen i en
kolonne: kortet kan dras mellom to kort, i sin egen kolonne eller en annen, og menyen får
«Rekkefølge» (øverst, opp, ned, nederst); hver post har da også before=ID, kortet det nå står
rett over, eller tom når det står nederst. Siden lagrer rekkefølgen, for eksempel med
rank-between. Etter en flytting sier tavla til skjermlesere hvor kortet havnet. MESSAGE vises
over kolonnene, for eksempel en feil. To tavler på én side trenger hver sin :id.")
  (:source "Tun's own, after GitHub Projects' board and Basecoat card (Vega)")
  (:css (concatenate 'string "
/* A board fills the height the page leaves it when the app shell gives it
   one (data-tun-fill, spec/ui.md 8): the shell sets --tun-fill-align to
   stretch the columns to that height and --tun-fill-max-height to none, so
   each column's cards take the rest of it.  Elsewhere a column is as tall
   as its cards, up to its own limit. */
.tun-board {
  display: flex;
  flex-direction: column;
  gap: calc(var(--spacing) * 3);
  min-width: 0;
  /* On a phone, a strip of page under the board, where a finger scrolls
     the page rather than a column's cards. */
  @media (max-width: 40rem) { padding-block-end: calc(var(--spacing) * 12); }
  & .tun-board-message:empty { display: none; }
  /* Where a card went, for screen readers (spec/ui.md 6.1). */
  & .tun-board-status {" +visually-hidden-css+ "
  }
  /* Side by side, scrolling sideways in their own box; on a phone a column
     is nearly the screen's width, and the next one shows at the edge. */
  & .tun-board-columns {
    display: grid;
    flex: 1 1 auto;
    min-height: 0;
    grid-auto-flow: column;
    grid-auto-columns: minmax(15rem, 1fr);
    grid-template-rows: minmax(0, 1fr);
    align-items: var(--tun-fill-align, start);
    gap: calc(var(--spacing) * 3);
    overflow-x: auto;
    overscroll-behavior-x: contain;
    scroll-snap-type: x proximity;
    padding-block-end: calc(var(--spacing) * 2);
    @media (max-width: 40rem) {
      grid-auto-columns: calc(100% - var(--spacing) * 10);
    }
  }
  /* While a card is dragged the columns do not snap, or each step the
     script scrolls them would be pulled back to the column's start. */
  &[data-tun-board-moving] .tun-board-columns { scroll-snap-type: none; }
  & .tun-board-column {
    display: flex;
    min-width: 0;
    min-height: 0;
    flex-direction: column;
    gap: calc(var(--spacing) * 2);
    padding: calc(var(--spacing) * 2);
    border-radius: var(--radius-lg);
    background-color: var(--muted);
    scroll-snap-align: start;
    transition-property: box-shadow;
    transition-duration: var(--duration-fast);
    transition-timing-function: var(--ease);
    &[data-tun-board-over] { box-shadow: inset 0 0 0 2px var(--ring); }
  }
  & .tun-board-column-header {
    display: flex;
    align-items: center;
    gap: calc(var(--spacing) * 2);
    padding: var(--spacing);
  }
  & .tun-board-column-title {
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    font-weight: var(--font-weight-semibold);
  }
  & .tun-board-column-count {
    min-width: calc(var(--spacing) * 5);
    padding-inline: calc(var(--spacing) * 1.5);
    border-radius: var(--radius-full);
    background-color: var(--background);
    color: var(--muted-foreground);
    font-size: var(--text-xs);
    line-height: var(--text-xs--line-height);
    font-weight: var(--font-weight-medium);
    font-variant-numeric: tabular-nums;
    text-align: center;
  }
  /* A column shows its cards, or, with none, the text that says so.  A long
     column scrolls under its header, showing about ten cards, so what
     follows the board is not far down the page.  The padding keeps a
     card's ring and focus outline inside the scrolling box.  On a phone a
     column instead fills the screen but what must stay in view around it
     when the page is scrolled to its end: the app shell's sticky header
     (3.5rem and its border), the column's padding, heading and gap
     (2.75rem), and below it the columns' padding (0.5rem), the board's
     strip (3rem) and the shell's padding under its content (4rem). */
  & .tun-board-cards {
    display: flex;
    flex: 1 1 auto;
    min-height: 0;
    max-height: var(--tun-fill-max-height, min(70dvh, 46rem));
    flex-direction: column;
    gap: calc(var(--spacing) * 2);
    margin: calc(var(--spacing) * -1);
    padding: var(--spacing);
    overflow-y: auto;
    overscroll-behavior-y: contain;
    @media (max-width: 40rem) {
      max-height: var(--tun-fill-max-height, min(46rem, calc(100dvh - var(--spacing) * 55 - 1px)));
    }
  }
  & .tun-board-empty {
    padding: calc(var(--spacing) * 3) var(--spacing);
    color: var(--muted-foreground);
    font-size: var(--text-sm);
  }
  & .tun-board-column:not(:has(.tun-board-card)) .tun-board-cards { display: none; }
  & .tun-board-column:has(.tun-board-card) .tun-board-empty { display: none; }

  & .tun-board-card {
    position: relative;
    display: grid;
    gap: calc(var(--spacing) * 2);
    padding: calc(var(--spacing) * 3);
    border-radius: var(--radius-md);
    background-color: var(--card);
    color: var(--card-foreground);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    box-shadow: 0 0 0 1px color-mix(in oklab, var(--foreground) 10%, transparent),
                var(--shadow-xs);
    &:has(.tun-board-card-title:focus-visible) { outline: 2px solid var(--ring); outline-offset: 2px; }
    @media (hover: hover) {
      &:has(a.tun-board-card-title):hover {
        box-shadow: 0 0 0 1px color-mix(in oklab, var(--foreground) 20%, transparent),
                    var(--shadow-sm);
      }
    }
  }
  /* A card that can be dragged: a press must not select its text or open
     the phone's menu for its link. */
  &[data-tun-board] .tun-board-card {
    cursor: grab;
    user-select: none;
    -webkit-user-select: none;
    -webkit-touch-callout: none;
  }
  & .tun-board-card-head {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    align-items: start;
    gap: calc(var(--spacing) * 2);
  }
  & .tun-board-card-title {
    font-weight: var(--font-weight-medium);
    overflow-wrap: anywhere;
  }
  /* The title's link covers the card; the menu stays above it. */
  & a.tun-board-card-title {
    outline: none;
    &::after { content: ''; position: absolute; inset: 0; border-radius: inherit; }
  }
  & .tun-board-card-actions {
    position: relative;
    z-index: 1;
    margin: calc(var(--spacing) * -1.5) calc(var(--spacing) * -1.5) 0 0;
  }
  & .tun-board-card-badges {
    display: flex;
    flex-wrap: wrap;
    gap: var(--spacing);
  }
  & .tun-board-card-meta {
    color: var(--muted-foreground);
    font-size: var(--text-xs);
    line-height: var(--text-xs--line-height);
  }
  & .tun-board-card[data-tun-board-dragging] { opacity: 0.4; }
  /* The copy that follows the pointer; the script sets where. */
  & .tun-board-card[data-tun-board-ghost] {
    position: fixed;
    z-index: var(--z-dropdown);
    margin: 0;
    pointer-events: none;
    cursor: grabbing;
    rotate: 1.5deg;
    box-shadow: 0 0 0 1px color-mix(in oklab, var(--foreground) 15%, transparent),
                var(--shadow-lg);
  }
}"))
  (:script "
// Dragging a card to another column, and on an ordered board to its place
// in a column.  A mouse drags once it has moved a few pixels; a finger
// first holds the card still for a moment, so a swipe still scrolls.  The
// card moves while it is dragged, and a drop in another column, or on an
// ordered board in another place, clicks that column's button for the
// card's form, which posts it: through htmx, whose answer replaces the
// board, or as a plain form.  Escape puts the card back.
const threshold = 6;
const holdMs = 300;
const edge = 48;
// A finger held at the edge pages one column after a moment, then the next
// while it is still held.
const pageHoldMs = 350;
const pageRepeatMs = 1000;
let press = null;
let drag = null;
// After a drag, the click the browser sends when the pointer is lifted.
let suppressClick = false;
// Where a dropped card was before it was dragged, for what is said after.
let droppedFrom = null;

const cardSelector = '[data-tun-board] [data-tun-board-card]';

// The column under the point.  A point beside the columns' box, such as a
// finger at the screen's edge over the page's gutter, is over the column at
// the box's edge.
const columnAt = (x, y) => {
  const rect = drag.board.querySelector('.tun-board-columns').getBoundingClientRect();
  const inside = Math.min(Math.max(x, rect.left + 1), rect.right - 1);
  const column = document.elementFromPoint(inside, y)?.closest('[data-tun-board-column]');
  return column && column.closest('[data-tun-board]') === drag.board ? column : null;
};

const mark = (column) => {
  for (const other of drag.board.querySelectorAll('[data-tun-board-over]'))
    if (other !== column) delete other.dataset.tunBoardOver;
  if (column) column.dataset.tunBoardOver = '';
};

// Where CARD is: its column's key and its index there.
const positionOf = (card) => {
  const column = card.closest('[data-tun-board-column]');
  const cards = [...column.querySelectorAll('.tun-board-cards > [data-tun-board-card]')];
  return { column: column.dataset.tunBoardColumn, index: cards.indexOf(card) };
};

// Put the card where the pointer is: before the first other card in the
// column under the pointer whose vertical middle is below it, or last; on
// a board that is not ordered, back in its place over its own column.
const place = (x, y) => {
  const column = columnAt(x, y);
  if (!column) return;
  mark(column);
  if (column === drag.origin && !drag.ordered) {
    drag.origin.querySelector('.tun-board-cards').insertBefore(drag.card, drag.next);
    return;
  }
  const list = column.querySelector('.tun-board-cards');
  const before = [...list.querySelectorAll(':scope > [data-tun-board-card]')]
    .find((card) => card !== drag.card
      && card.getBoundingClientRect().top + card.offsetHeight / 2 > y);
  if (drag.card.parentElement !== list || drag.card.nextElementSibling !== (before || null))
    list.insertBefore(drag.card, before || null);
};

const follow = (x, y) => {
  drag.x = x;
  drag.y = y;
  drag.ghost.style.left = `${x - drag.offsetX}px`;
  drag.ghost.style.top = `${y - drag.offsetY}px`;
  place(x, y);
};

// Scroll the columns' box to the start of the next column, BY 1 to the
// right or -1 to the left.
const page = (box, by) => {
  const left = box.getBoundingClientRect().left;
  const starts = [...box.children]
    .map((column) => box.scrollLeft + column.getBoundingClientRect().left - left);
  const start = by > 0 ? starts.find((start) => start > box.scrollLeft + 1)
                       : starts.findLast((start) => start < box.scrollLeft - 1);
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (start !== undefined) box.scrollTo({ left: start, behavior: still ? 'auto' : 'smooth' });
};

// Near an edge of the columns' box, of the cards of the column under the
// pointer, or of the window, scroll it on.  The box's edge counts where the
// screen cuts it off.  A mouse scrolls the columns steadily; a finger pages
// them a column at a time, as on a phone a column is nearly the screen's
// width.  The card is placed again every frame, as what is under the
// pointer moves while the columns scroll.
const scroll = (now) => {
  if (!drag) return;
  const nearEdge = (at, start, end) => (at < start + edge ? -1 : at > end - edge ? 1 : 0);
  const box = drag.board.querySelector('.tun-board-columns');
  const rect = box.getBoundingClientRect();
  const sideways = nearEdge(drag.x, Math.max(rect.left, 0), Math.min(rect.right, window.innerWidth));
  const list = columnAt(drag.x, drag.y)?.querySelector('.tun-board-cards');
  const listRect = list?.getBoundingClientRect();
  const inList = list && list.scrollHeight > list.clientHeight
    ? nearEdge(drag.y, listRect.top, listRect.bottom) : 0;
  const down = nearEdge(drag.y, 0, window.innerHeight);
  if (!sideways) drag.paging = null;
  else if (!drag.touch) box.scrollLeft += sideways * 12;
  else if (drag.paging?.by !== sideways) drag.paging = { by: sideways, at: now + pageHoldMs };
  else if (now >= drag.paging.at) {
    page(box, sideways);
    drag.paging.at = now + pageRepeatMs;
  }
  if (inList) list.scrollTop += inList * 12;
  else if (down) window.scrollBy(0, down * 12);
  place(drag.x, drag.y);
  drag.frame = requestAnimationFrame(scroll);
};

const begin = (x, y) => {
  const { card } = press;
  const rect = card.getBoundingClientRect();
  const ghost = card.cloneNode(true);
  ghost.removeAttribute('id');
  for (const element of ghost.querySelectorAll('[id]')) element.removeAttribute('id');
  ghost.dataset.tunBoardGhost = '';
  ghost.setAttribute('aria-hidden', 'true');
  ghost.inert = true;
  ghost.style.width = `${rect.width}px`;
  const board = card.closest('[data-tun-board]');
  board.append(ghost);
  board.dataset.tunBoardMoving = '';
  card.dataset.tunBoardDragging = '';
  drag = {
    card, ghost, board,
    ordered: board.hasAttribute('data-tun-board-ordered'),
    from: positionOf(card),
    touch: press.touch,
    paging: null,
    origin: card.closest('[data-tun-board-column]'),
    next: card.nextElementSibling,
    offsetX: x - rect.left,
    offsetY: y - rect.top,
    x, y,
  };
  press = null;
  follow(x, y);
  drag.frame = requestAnimationFrame(scroll);
};

const bump = (column, by) => {
  const count = column.querySelector('[data-tun-board-count]');
  const text = count.textContent.trim();
  if (/^[0-9]+$/.test(text)) count.textContent = String(Number(text) + by);
};

const end = (dropped) => {
  const { card, ghost, board, origin, next, frame, ordered, from } = drag;
  cancelAnimationFrame(frame);
  mark(null);
  ghost.remove();
  delete board.dataset.tunBoardMoving;
  delete card.dataset.tunBoardDragging;
  const column = card.closest('[data-tun-board-column]');
  const moved = column !== origin || (ordered && card.nextElementSibling !== next);
  drag = null;
  if (!dropped || !moved) {
    origin.querySelector('.tun-board-cards').insertBefore(card, next);
  } else {
    if (column !== origin) {
      bump(origin, -1);
      bump(column, 1);
    }
    if (ordered)
      card.querySelector('[data-tun-board-before]').value =
        card.nextElementSibling?.dataset.tunBoardCard ?? '';
    droppedFrom = from;
    card.querySelector(`[data-tun-board-move='${CSS.escape(column.dataset.tunBoardColumn)}']`)
      ?.click();
  }
  // The click the browser sends when the pointer is lifted, after a drop or
  // after Escape, is not a click on the card's link (see 'pointerup').
  suppressClick = true;
};

const release = () => {
  if (press?.timer) clearTimeout(press.timer);
  press = null;
};

document.addEventListener('pointerdown', (event) => {
  if (drag || event.button !== 0 || !(event.target instanceof Element)) return;
  const card = event.target.closest(cardSelector);
  if (!card || event.target.closest('button, input, select, textarea, [popover]')) return;
  press = { card, x: event.clientX, y: event.clientY, pointer: event.pointerId,
            touch: event.pointerType !== 'mouse' };
  if (press.touch) press.timer = setTimeout(() => { if (press) begin(press.x, press.y); }, holdMs);
});

document.addEventListener('pointermove', (event) => {
  if (drag) {
    follow(event.clientX, event.clientY);
    return;
  }
  if (!press || event.pointerId !== press.pointer) return;
  const moved = Math.hypot(event.clientX - press.x, event.clientY - press.y) > threshold;
  if (press.touch) {
    if (moved) release();   // a swipe: let the browser scroll
    else { press.x = event.clientX; press.y = event.clientY; }
  } else if (moved) {
    begin(press.x, press.y);
    follow(event.clientX, event.clientY);
  }
});

document.addEventListener('pointerup', () => {
  if (drag) end(true);
  release();
  // That click comes right after this event, or not at all (the pointer was
  // lifted off the card): either way no later click is held back.
  if (suppressClick) setTimeout(() => { suppressClick = false; }, 0);
});
document.addEventListener('pointercancel', () => {
  if (drag) end(false);
  release();
});
window.addEventListener('blur', () => {
  if (drag) end(false);
  release();
});
document.addEventListener('keydown', (event) => {
  if (drag && event.key === 'Escape') {
    event.preventDefault();
    end(false);
  }
});

// While a finger drags, the page must not scroll under it, and holding a
// link must not open the browser's menu for it.
document.addEventListener('touchmove', (event) => {
  if (drag) event.preventDefault();
}, { passive: false });
document.addEventListener('contextmenu', (event) => {
  if (drag || press?.touch) event.preventDefault();
});
document.addEventListener('dragstart', (event) => {
  if (event.target instanceof Element && event.target.closest(cardSelector))
    event.preventDefault();
});
document.addEventListener('click', (event) => {
  if (!suppressClick || !(event.target instanceof Element)
      || !event.target.closest(cardSelector)) return;
  suppressClick = false;
  event.preventDefault();
  event.stopPropagation();
}, true);

// Saying where a card went (spec/ui.md 6.1).  A post of a card's form
// notes where the card was; when htmx's answer has settled, the board's
// status region says where it is now, if that is somewhere else.  A
// refused move, which leaves it where it was, says nothing there.
let moving = null;
document.addEventListener('submit', (event) => {
  const card = event.target instanceof HTMLFormElement && event.target.closest(cardSelector);
  if (!card) return;
  moving = { board: card.closest('[data-tun-board]').id, card: card.dataset.tunBoardCard,
             from: droppedFrom ?? positionOf(card) };
  droppedFrom = null;
}, true);
document.addEventListener('htmx:after:settle', () => {
  if (!moving) return;
  const { board: boardId, card: cardId, from } = moving;
  const board = document.getElementById(boardId);
  const card = document.getElementById(`${boardId}-${cardId}`);
  const status = board?.querySelector('[data-tun-board-status]');
  if (!card || !status) return;
  moving = null;
  const at = positionOf(card);
  if (at.column === from.column && at.index === from.index) return;
  const column = card.closest('[data-tun-board-column]');
  const title = card.querySelector('.tun-board-card-title').textContent.trim();
  const heading = column.querySelector('.tun-board-column-title').textContent.trim();
  const count = column.querySelector('[data-tun-board-count]').textContent.trim();
  status.textContent = board.hasAttribute('data-tun-board-ordered')
    ? `Flyttet «${title}» til plass ${at.index + 1} av ${count} i ${heading}.`
    : `Flyttet «${title}» til ${heading}.`;
});")
  (:examples
   (("Saker etter status" :layout :stack)
    (board (:label "Saker etter status" :action "/saker/flytt"
                   :columns (list (list :key "ny" :title "Ny"
                                        :cards (list (list :id "itm_1" :title "Eksporten til regnskap feiler"
                                                           :href "/saker/itm_1"
                                                           :badges (list (badge (:variant :destructive) "Feil")
                                                                         (badge (:variant :outline) "Nordvik"))
                                                           :meta "Kari Nordmann · 21.10.2026")
                                                     (list :id "itm_2" :title "Vis lagerbeholdning på ordren"
                                                           :href "/saker/itm_2"
                                                           :badges (list (badge (:variant :info) "Ønske"))
                                                           :meta "Ole Hansen · 20.10.2026")))
                                  (list :key "planlagt" :title "Planlagt"
                                        :cards (list (list :id "itm_3" :title "Ny side for fakturaer"
                                                           :href "/saker/itm_3"
                                                           :badges (list (badge (:variant :info) "Ønske")))))
                                  (list :key "under_arbeid" :title "Under arbeid" :cards '())
                                  (list :key "ferdig" :title "Ferdig" :count "20+"
                                        :cards (list (list :id "itm_4" :title "Rett skrivefeil i ordrebekreftelsen"
                                                           :href "/saker/itm_4"
                                                           :meta "Ferdig 18.10.2026")))))))
   (("Ordnet: neste sak øverst" :layout :stack)
    (board (:id "ko" :label "Køen" :action "/ko/flytt" :ordered t
            :columns (list (list :key "neste" :title "Neste"
                                 :cards (list (list :id "itm_6" :title "Kunden får ikke logget inn"
                                                    :badges (list (badge (:variant :destructive)
                                                                    "Haster")))
                                              (list :id "itm_7" :title "Eksport til regnskap")
                                              (list :id "itm_8" :title "Ny side for fakturaer")))
                           (list :key "senere" :title "Senere"
                                 :cards (list (list :id "itm_9" :title "Mørk modus")))))))
   ("Bare til å se på, med en melding"
    (board (:label "Mine saker"
                   :message (list (alert (:variant :warning :title "Saken ble ikke flyttet")
                                         "Du kan bare flytte dine egne saker."))
                   :columns (list (list :key "ny" :title "Ny"
                                        :cards (list (list :id "itm_5" :title "Kan ikke logge inn"
                                                           :meta "21.10.2026")))
                                  (list :key "ferdig" :title "Ferdig" :empty "Ingen ferdige ennå"))))))
  (unless (and label columns)
    (error "A board needs :label, what its cards are, and :columns"))
  ;; The ids of cards and their menus come from the board's, the same in
  ;; every answer, so htmx gives focus back to the menu a move was made with.
  (let ((board-id (or id "tun-board")))
    `(:div ,(attrs (list :class "tun-board" :id board-id :role "region" :aria-label label
                         :data-tun-board (when action t)
                         :data-tun-board-ordered (when (and action ordered) t)
                         :data-tun-fill t)
                   attributes)
           (:div (:@ :class "tun-board-message" :aria-live "polite") ,@message)
           ,@(when action
               '((:p (:@ :class "tun-board-status" :role "status" :data-tun-board-status t))))
           (:div (:@ :class "tun-board-columns")
                 ,@(mapcar (lambda (column)
                             (board-column column :board-id board-id :action action
                                                  :columns columns
                                                  :heading-level heading-level
                                                  :ordered (and action ordered)))
                           columns)))))
