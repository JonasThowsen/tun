# A text area in a link card can't be focused

- loop: card-link-fields
- mode: hands-on
- stage: done
- base: 9ffa5a1bfee3a955afb01af717ccce349065b8e7
- verified: 02e378ebc5f95889422178502355ad28bdc6d4aa
- shown: 02e378ebc5f95889422178502355ad28bdc6d4aa

## Brief

Reported 2026-11-02 by the ferdig session, from Jonas on his phone: in
ferdig's overview a card with `:href` holds a form with `ui:textarea`, and
tapping the text area follows the card's link to the item page instead of
focusing the field. The card's title link covers the card
(`.tun-card-link::after`, `position: absolute; inset: 0`), and only
`a, button, input, select, label` inside it are lifted above that cover
(src/web/ui/data.lisp, the card's CSS); `textarea` is not among them.
Wanted: every control in a link card works as itself, and the rest of the
card stays the link.

## Criteria

1. In a card with `:href`, a text area is the element found at its own
   centre, above the card's link, as a button, a select, a field and a
   label already are.
2. On a phone, a tap on a text area in a link card focuses it and stays
   on the page; a tap on the card's text outside its controls follows the
   card's link.
3. The specimen /ui/card shows a link card holding a form with a text
   area, as ferdig's overview does.
4. spec/ui.md says what a card with `:href` does with the controls in it.

## Decisions

- **The lifted list** becomes `a, button, input, select, textarea, label`.
  Gate A offered every focusable element (summary, contenteditable,
  tabindex) as well; Jonas chose the text area only. The cover stays a
  stretched link rather than a script, so the card still works without
  JavaScript.
- **The check** is a browser check on the showcase's /ui/card (Tun's
  checks/showcase/checks/), on a phone, since it is a question of what is
  under a finger; a render test can only see the selector.
- **Spec:** a sentence in spec/ui.md §6 beside `table`'s, since the card's
  link had no spec line yet.
- Core 2.4.6.

## Log

- 2026-11-02 12:17  started, hands-on
- 2026-11-02 12:17  gate A asked of the person
- 2026-11-02 12:18  gate A: approve (jonas): «Text area only»: lift textarea alone, not the other focusable elements
- 2026-11-02 12:35  verify 1: passed build, test, check
- 2026-11-02 12:36  shown (/ui/card)
- 2026-11-02 12:36  gate B asked of the person
- 2026-11-02 13:01  gate B: approve (jonas): «Approve and push (Recommended)»
- 2026-11-02 13:01  finished at tun 149fc8c
