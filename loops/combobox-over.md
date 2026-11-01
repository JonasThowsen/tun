# A combobox's list shows over a card or a dialog around it

- loop: combobox-over
- mode: hands-on
- stage: ship
- base: 4070a9d795956e1d81212a304f96cc255243b714
- after: combobox
- verified: af8ef84ecda1cfbdd962440f45db7aa24bc679da
- shown: af8ef84ecda1cfbdd962440f45db7aa24bc679da

## Brief

Jonas, 2026-11-01, with a client's deploy card on its overview, a strict
`ui:combobox` inside a `ui:card`, after typing «ferdig»: «does not seem like
it is working correctly? no options show up?». The list opened, but the
card, which hides what overflows it, cut it off below the field. The
combobox loop's check drove it on a page with no card around it.

## Criteria

1. A combobox's list shows whole under its field inside a card, a dialog
   or any element that hides what overflows it, on a phone and a desktop.
2. It stays under its field when the page scrolls or the window changes
   size while it is open, and above the field when there is more room
   there than under it.
3. Everything the combobox loop promised still holds: narrowing, picking
   by touch and keyboard, «No match», `:strict`, `:button`, htmx swaps,
   and the browser's own list without the script.
4. The showcase's «Find» page holds its combobox in a card, and the
   browser check sees the list's options inside the window, not only in
   the page.

## Decisions

- **The top layer,** as `dropdown-menu`'s list: the list is a manual
  popover, which no ancestor's overflow clips. The script shows and hides
  it and places it under the field with fixed coordinates; CSS anchor
  positioning is left for later, as a fixed place is enough for a list
  under one field.
- **The check looks at where the options are,** with their boxes inside
  the window and on top at their own centre (`elementFromPoint`), since
  Playwright counts a clipped element as visible.

## Log

- 2026-11-01 09:41  started, hands-on
- 2026-11-01 09:41  gate A asked of the person
- 2026-11-01 09:44  gate A: approve (jonas): «Approve (Recommended)»
- 2026-11-01 09:58  verify 1: passed build, test, check
- 2026-11-01 09:59  shown (/find)
- 2026-11-01 09:59  gate B asked of the person
- 2026-11-01 10:29  gate B: approve (jonas): «Approve and push (Recommended)»
- 2026-11-01 10:43  verify 2: passed build, test, check
- 2026-11-01 10:43  shown (/find)
- 2026-11-01 10:43  gate B asked of the person
- 2026-11-01 11:22  gate B: approve (jonas): «Approve and push (Recommended)», after the core version was raised to 2.4.1
