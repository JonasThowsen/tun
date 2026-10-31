# A combobox that finds an option by typing, and a table column a phone leaves out

- loop: combobox
- mode: hands-on
- stage: done
- base: 268822c05688be422b0030571f13dab810c0f5db
- verified: 0590beb2fa80a84d08a8879c30e0d2d569db9e52
- shown: 0590beb2fa80a84d08a8879c30e0d2d569db9e52

## Brief

Jonas, 2026-10-31, at gate B of a client's loop that put a deploy card on
its overview, with a target field that used the browser's own search list
(`<datalist>`): «I want the picker to be a combobox, with the deploy button
showing as possible to press when a viable target is picked. In general i
just want the dashboard to be smaller and easier to scroll and quickly
operate». The client's overview is a table of targets, which a phone
shows as a card per row with every column.

## Criteria

1. `ui:combobox` is a text field with a list of OPTIONS under it. Focusing
   or tapping it opens the list with every option; typing narrows it to
   the options holding the text typed, ignoring case, anywhere in the
   option; an option is picked with a tap, a click, or the arrow keys and
   Enter, which fills the field and closes the list. Escape and leaving
   the field close it.
2. With `:strict t`, the submit buttons of the field's form are disabled
   until the field holds exactly one of the options, typed or picked, and
   enabled again as soon as it does. The server still checks the value,
   as a form can be posted without the script.
3. Without the script, the field is a text input with the browser's own
   list of the options (`<datalist>`), and the buttons are not disabled.
4. It is labelled and accessible as the ARIA combobox pattern says
   (`role=combobox`, `aria-expanded`, `aria-controls`,
   `aria-activedescendant`, a `listbox` of `option`s, `aria-selected`),
   takes `:hint`, `:error`, `:value`, `:placeholder` and `:required` as
   `text-input` does, and fits a phone's width. «No match» shows when
   nothing holds the text.
5. A `table` column with `:narrow nil` is left out of the card a narrow
   screen shows for each row, and kept in the table on a wide one.
6. The specimen (`/ui`) shows both. Browser checks in the showcase drive
   the combobox by touch on a phone and by keyboard on a desktop, its
   strict form's button, and a markup swapped in by htmx; and a table
   with a column a phone leaves out. Core 2.4.0.

## Decisions

- **In Tun, not the client:** a client ships no script of its own, and
  Tun's `spec/ui.md` §9 already lists a combobox with search as missing.
  The client's loop builds on this one.
- **Options are texts,** the value posted being the text shown, as the
  first use picks a target by its name. Values apart from labels can come
  when a page needs them.
- **Built on a text input and a list the script draws,** not on
  `<datalist>`, whose list a page cannot style, filter its own way or
  read the choice from; `<datalist>` stays as what works without the
  script.
- **`:strict` disables the form's own submit buttons** (those inside the
  form, or with its `form` attribute), not a button the page names: the
  field knows its form.
- **`:narrow nil`** rather than a priority per column: a page says which
  columns a phone can do without, and nothing else changes.

## Log

- 2026-10-31 21:38  started, hands-on
- 2026-10-31 21:39  gate A asked of the person
- 2026-10-31 21:40  gate A: approve (jonas): «Approve (Recommended)»
- 2026-10-31 22:10  verify 1: passed build, test, check
- 2026-10-31 22:24  verify 2: passed build, test, check
- 2026-10-31 22:25  shown (/find, /ui)
- 2026-10-31 22:25  gate B asked of the person
- 2026-10-31 22:28  gate B: approve (jonas): «Approve and push (Recommended)»
- 2026-10-31 22:28  finished at tun b30110d
