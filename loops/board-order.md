# Kort kan ordnes innenfor en kolonne

- loop: board-order
- mode: autonomous
- stage: ship
- base: b7a392cdc7c9a04b02339d58cca4ac2b06a4b308
- verified: 56ec0825b8fd436073e77dddf4cbf87a9f9bda95
- shown: 56ec0825b8fd436073e77dddf4cbf87a9f9bda95

## Brief

Requested by Jonas on 2026-10-26, through an agent working on a client:

> Ordering within a board column (ui:board). Today a drop only posts a
> move between columns. The client needs a manual order within each
> column (agents take the next item from the top).
> - Let a card be dropped between two cards, in the same column or
>   another, with the mouse, by touch on a phone (the existing
>   hold-to-drag) and from the keyboard.
> - The post carries the position, e.g. the id of the card it now sits
>   before (or none, for the bottom).
> - The client stores the order. A small core helper for rank keys
>   between two neighbours would be welcome if it fits Tun.
> - Same answer contract as moves today: a fragment, 303, or a refusal
>   answering the board as it was.

Jonas approved it on this condition: «make sure the parts that are in
tun are agnostic to [the client] itself».

## Criteria

1. `rank-between` (spec/core.md §2.6): `(rank-between nil nil)` is
   `"a0"`; for keys LOW before HIGH it returns a key after LOW and before
   HIGH by code point; `nil` LOW gives a key before HIGH, `nil` HIGH one
   after LOW; the same arguments give the same key.
   `tests/rank-tests.lisp`.
2. Keys stay short and in order: 10 000 keys added one after another at
   the end, and 10 000 at the top, are each at most 4 characters and in
   order; 1 000 added each time directly after the same first key, and
   1 000 each time directly before the same last key, are in order and at
   most 210 characters; a list built by 2 000 insertions at seeded random
   places stays sorted, and sorting the keys by `string<` gives the
   list's order. `tests/rank-tests.lisp`.
3. The key format of spec/core.md §2.6, by `tests/rank-tests.lisp`:
   - each of these, as LOW or as HIGH, is a `type-error`: `""`; a key
     with a character outside `0-9A-Za-z` (`"a0-"`, `"aø"`); one starting
     with a digit (`"0a"`); one shorter than its whole part (`"b0"`,
     `"Y0"`); one whose fraction ends in `0` (`"a0V0"`); the smallest
     whole part alone (`A` and 26 `0`s); a non-string such as `1`;
   - LOW equal to or after HIGH signals `rank-order-error`, whose
     `rank-order-error-low` and `rank-order-error-high` are the two keys;
     a non-key in the wrong order (`("b0" "a0")`) is a `type-error`;
   - the fraction digit is the midpoint rounded half up: `("a0" "a1")` →
     `"a0V"`, `("a0V" "a1")` → `"a0l"`; adjacent digits keep LOW's and go
     on (`("a0V" "a0W")` → `"a0VV"`); a top key before a HIGH with the
     smallest whole part and a fraction sorts before HIGH and keeps that
     whole part;
   - whole parts step as the format says: after `"a0"` comes `"a1"`,
     after `"az"` `"b00"`, before `"a0"` `"Zz"`, before `"Z0"` `"Yzz"`,
     before `"a0V"` `"a0"`; the largest whole part (`z` and 26 `z`s)
     followed by nothing gets a key with that whole part and a fraction,
     and so does a key before the smallest whole part with a fraction;
   - keys stored from known values of rocicorp's implementation
     (`(nil nil)` → `"a0"`, `("a0" nil)` → `"a1"`, `(nil "a0")` → `"Zz"`,
     `("a0" "a1")` → `"a0V"`, `("a0V" "a1")` → `"a0l"`, `("a1" "a2")` →
     `"a1V"`) are reproduced exactly, so a later change to the format
     fails a test.
4. An ordered board (`:ordered t` and `:action`) is marked
   `data-tun-board-ordered`; each card's move form carries `before`
   empty and a hidden button for the card's own column; a card in a
   column with other cards has a menu group «Rekkefølge» whose items post
   `card`, its own column and `before`: «Flytt øverst» the first card and
   «Flytt opp» the card above (only when not first), «Flytt ned» the card
   two below or empty and «Flytt nederst» empty (only when not last). A
   card alone in its column has no «Rekkefølge» group, and has its menu
   when there are other columns; a card alone on a board of one column
   has no menu. Every board with ACTION, ordered or not, has a
   `role="status"` region whose CSS clips it (visually hidden) and which
   carries neither the `hidden` attribute nor `display: none`. A board
   without `:ordered` renders its forms and menus as before: no
   `before`, no «Rekkefølge». `tests/ui-data-tests.lisp`.
5. With a mouse (`checks/showcase/checks/board-order-with-a-mouse.py`):
   a card dragged between two cards of its own column posts its column
   and `before` the card below the drop, and the answer and a reload show
   it there; dragged between two cards of another column, it posts that
   column and the card below; dropped under a column's last card it posts
   `before` empty and is last; dropped where it started, nothing is
   posted.
6. By touch at 390×844 (`board-order-on-a-phone.py`): a card held, moved
   up its column and lifted between two cards posts that place and the
   answer shows it there; a card held at the screen's edge pages to the
   next column, and lifted between two cards there posts that column and
   the card below; a swipe that does not hold scrolls the column and
   posts nothing; the card's menu, with «Rekkefølge», fits the screen.
7. From the keyboard (`board-order-from-the-keyboard.py`): from a card's
   focused menu button, Enter and the arrow keys reach «Flytt opp», and
   choosing it posts the card above as `before`; the answer has the card
   one place up, focus is on that card's menu button, and the status
   region says «Flyttet «TITLE» til plass N av COUNT i COLUMN.» with the
   new place; «Flytt nederst» makes it last; «Flytt til» another column
   puts it last there and says so.
8. A refused move answers 409. The keyboard check makes one by setting,
   with `page.evaluate`, the hidden `before` of a card's move form to the
   id of a card in another column, then choosing «Flytt til» in the
   card's menu; the answer is 409 with the board as it was and the error in
   MESSAGE, the card where it was, and the status region empty.
9. Backwards compatible: a board without `:ordered` in the showcase
   (`/tavle`) posts `card` and `column` without `before` when a card is
   dropped in another column, and its status region then says «Flyttet
   «TITLE» til COLUMN.»; it puts back a card dropped in its own column
   without posting (`board-order-with-a-mouse.py`); the existing
   checks `board-drag-with-a-mouse`, `board-drag-on-a-phone` and
   `board-fills-a-phone` pass.
10. No check sees a JavaScript error; `bin/build` has no warnings;
    `bin/test` and `bin/check` pass.

## Decisions

- **Ordering is opted into with `:ordered t`.** A board whose page sorts
  each column itself (by date, by priority) must not let a card be
  dropped between two others only to jump back, and an existing page
  must keep receiving exactly the posts it does today. So without
  `:ordered` nothing changes; with it, every post carries `before`.
- **The place is `before`, the id of the card below, empty for last**, as
  the request suggests. The page knows its column's order, so one
  neighbour is enough; «before X» still means the same place when other
  cards have moved in the meantime, and an X no longer in that column is
  an out-of-date board, which the page refuses. So is a `before` that is
  the moved card itself: the board never posts one, so it can only come
  from a hand-made or broken post, and refusing it is simpler to state
  than a silent no-op. No `after` is posted.
- **«Flytt til» another column puts the card last there** (`before`
  empty), as a new card is placed: the top is what is taken next, so a
  card moved without a chosen place should not go ahead of the others.
  A drop puts it exactly where it was dropped.
- **The keyboard path is four menu items in a group «Rekkefølge»**
  (øverst, opp, ned, nederst) in the card's existing menu, not a
  keyboard drag mode. They are plain submit buttons, so they work
  without JavaScript and with a screen reader, through the menu that
  already moves a card from the keyboard. To put a card between two
  cards of another column from the keyboard, it is moved there and then
  up.
- **Two forms per card on an ordered board.** A button posts one name,
  so each form holds the fixed part: the move form has `card` and
  `before` (the buttons give the column), the order form `card` and the
  column (the buttons give `before`). The move form also holds a hidden
  button for the card's own column, which the script clicks, after
  setting `before`, for a drop in that column, so every drop posts
  through a form htmx already sends.
- **What is said is written by the script after the answer settles,
  from the answer**, into a visually hidden `role="status"` region: the
  server decides where the card ended up, and a refused move, which
  leaves the card where it was, says nothing there while MESSAGE says
  why. Without JavaScript the plain form reloads the page, and nothing
  is said beyond the page itself. A move to another column is said too,
  without a place on a board that is not ordered.
- **The rank helper is in core, as `rank-between`, exported from `TUN`.**
  It is small, pure and not about boards: any record a person orders by
  hand can use it. It is fractional indexing in base 62, after
  rocicorp's `fractional-indexing` (CC0): `0-9A-Za-z` is code-point
  order, the order every store already sorts text in (spec/store.md
  §2.6, Postgres's `"C"` collation), and the length-prefixed whole part
  keeps keys short when cards are added at the top or the end, the
  common case. There is no rebalancing: only many insertions at one spot
  lengthen keys, by a character in six, and a client can give a column
  fresh keys with successive `rank-between` calls if it ever needs to.
- **Not a field type.** The client stores the key in a `string` field it
  declares (`:input nil`), so `define-entity`, migrations and the store
  stay as they are. A non-key argument is a `type-error` through
  `check-type`; LOW not before HIGH signals `rank-order-error`, a kernel
  condition exported from `TUN` with readers for both keys, so a client
  can handle it by name.
- **The key format is part of the contract** (spec/core.md §2.6) and is
  pinned by tests of exact keys, since keys outlive the code that made
  them. Every record in an ordered set needs a key; existing records get
  keys in their current order through successive `rank-between` calls.
- **The showcase shows it**: its board is ordered, cards get keys from
  `rank-between` in a new string field `place`, replacing the integer
  `rank`, so no stored column changes type (migrations are additive; the
  old column is left as it is). `cards_move` takes an optional `before`
  and refuses one that is not another card in the column with
  `conflict`, and the default
  scenario puts a card made last at the top of «Ny», so the board page
  shows a manual order. A second, unordered board at `/tavle` keeps the
  old contract under a browser check.
- **Icons**: «Flytt øverst» and «Flytt nederst» use Lucide's
  `arrow-up-to-line` and `arrow-down-to-line`, added to the icon set;
  «Flytt opp» and «Flytt ned» use `arrow-up` and `arrow-down`.
- **Core version 1.18.0**, in `src/core/module.lisp`, `flake.nix` and
  spec/cli.md's example: this loop shipped before the other work that had
  meant to take 1.18.0, so it took that number.
- **Spec**: spec/ui.md §6.1 (order within a column, the answer, what is
  said), §9 and §10; spec/core.md §2.6 (manual order and rank keys).
  docs/client-api.md gets an example of storing and sorting by a key.

## Log

- 2026-10-26 16:59  started, autonomous
- 2026-10-26 17:02  gate A asked of a reviewer
- 2026-10-26 17:07  gate A: changes (reviewer): core.md §2.6 must give the key format exactly and say it will not change; fix the growth sentence; say how records without a key get one; say the order group is left out when empty and the menu shows on an ordered board whenever it has an item; the unordered status message needs a criterion or goes, and the region must be visually hidden, not hidden
- 2026-10-26 17:08  gate A asked of a reviewer
- 2026-10-26 17:12  gate A: changes (reviewer): criterion 2's 200-character bound contradicts the format criterion 3 pins (1000 keys directly before one key reach 202); state how the fraction digit is chosen (midpoint rounded half up); make the top rule unambiguous for HIGH with the smallest whole part
- 2026-10-26 17:13  gate A asked of the person
- 2026-10-26 17:13  gate A asked of the person
- 2026-10-26 17:36  gate A: approve (jonas): «Approve» (asked: approve the spec and criteria so building can start?)
- 2026-10-26 17:53  verify 1: passed build, test, check
- 2026-10-26 18:00  verify 2: passed build, test, check
- 2026-10-26 18:01  shown (/saker, /tavle)
- 2026-10-26 18:01  gate B asked of a reviewer
- 2026-10-26 19:46  gate B: approve (reviewer): criteria 1-10 met; rank-between matches a JS port of rocicorp in 13013 cases; unordered boards unchanged; answer contract kept
- 2026-10-26 20:03  rebased onto main 6b372fc (the rewritten history and loop-links); core 1.18.0, since this ships first
- 2026-10-26 20:10  verify 3: passed build, test, check
- 2026-10-26 20:10  shown (/saker, /tavle)
- 2026-10-26 20:10  gate B asked of a reviewer
- 2026-10-26 20:13  gate B: approve (reviewer): rebase only: the change is gate-B-1's but for core 1.18.0; verify 3 passed; no address in the record
