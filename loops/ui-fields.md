# The date, time and money fields, and a period as a filter of a list

- loop: ui-fields
- mode: reviewed
- stage: done
- base: f09131bd848069d9296bccd9f13dd3190caf6a92
- item: sak_t5gvvtw1rr2nbwe8
- estimate: 2h20m 3h15m 5h30m
- like: tun/ui-filters tun/ui-sheets
- tags: kind:ui core module:ui
- verified: e5871517766aaa423fff5fc5f7891b43646c2173
- shown: e5871517766aaa423fff5fc5f7891b43646c2173

## Brief

Ferdig sak_t5gvvtw1rr2nbwe8, brought by the factory's orchestrator on
2026-11-12, the sixth loop of the work on Tun's component library after
`ui-look` (2.25.0), `ui-sheets` (2.26.0), `ui-header` (2.27.0),
`ui-filters` (2.28.0) and `ui-lists` (2.29.0). Jonas, 2026-11-11: he has
polished the admin UI of another application of his for two weeks and
wants the best of it carried into Tun's component library, «to make the UI
component Library of Tun superb». The source is the owner's rules for an
admin application, 2026-11; rules, values, anatomy, behaviour and the tests
that pin them carry over, code does not.

The item: «A date field a person can type in their own format, with a
calendar that opens as the other things that open do; a time field; a
money field; and a period (from and to) as a kind of filter in the list
toolbar, so generated lists can offer their date inputs.» The
orchestrator's brief, in short:

1. **`date-input`**: a text field a person types a date in, in their
   locale's form, forgiving about how it is typed (day.month.year with one
   or two digits, two-digit years, eight digits without separators; the
   English forms decided here), every accepted and refused form pinned in a
   property-style test of the server's parser. The form posts one value the
   server reads; a value that cannot be read comes back in the field with
   its error, never silently changed. Without JavaScript a plain text field
   with a hint of the form. `inputmode` and `autocomplete` right for a
   phone.
2. **The calendar**, where scripts run: a button in the field opens a month
   calendar, a popover under the field on a wide screen and a floating
   sheet on a phone (as a filter's popover from `ui-filters`), moving in
   and out with the motion tokens; Escape and a press outside close it and
   the focus returns; the keyboard (arrows, PageUp/PageDown, Home/End,
   Enter); the week from the locale's first day; today and the chosen day
   marked without a change of weight or size; `min`/`max` greying days out;
   quick choices where the caller asks («Today», «Tomorrow», or the
   caller's); roles and names as the WAI-ARIA date picker dialog pattern;
   month and day names from Tun's translations, English and Norwegian.
3. **`time-input`**: a time of day, forgiving («9», «930», «09:30»,
   «9.30» → 09:30, decided and pinned), 24 hours, no picker unless the
   source has one worth carrying.
4. **`money-input`** (or an honest extension of `input-group`): an amount,
   right-aligned in tabular digits, the currency before or after by the
   locale, the locale's decimal mark and groups as typed («1 250,50»,
   «1250.5»), read on the server into minor units by the currency's minor
   digits, more decimals refused, the value coming back formatted; decimal
   `inputmode`; no rounding in the browser.
5. **Generated forms and filters use them**: `date-type`, a time type if
   Tun has one, and the money type render with the new fields, and what a
   client receives from a posted form keeps its shape (ISO dates); say how,
   and why. `text-input :type :date` keeps the browser's own field.
6. **A period in the list toolbar**: a new filter kind with from and to as
   two address keys the caller names, one button («Period: 1–14 Nov»)
   opening two date fields with the calendar and quick choices («Today»,
   «This week», «This month», «Last month», the caller's), applied when a
   whole date or a quick choice is set (not per keystroke), cleared with ×,
   a row of the «Filters» sheet on a phone, and working without JavaScript
   through «Apply». Generated lists offer a recognisable pair of date
   inputs of their list operation as a period (the rule said here).
7. The specimen shows each field empty, filled, with an error, disabled,
   and the calendar open, at 390 and 1280 px, light and dark; the showcase
   gets a page that posts them and shows what the server read, and
   `/cards` a period filter. A browser check measures typing each accepted
   form and posting it, in English and Norwegian; the calendar's box in the
   window at 320 px; the keyboard; the motion's names and durations; focus
   return; the period changing the address once per chosen date and Back
   stepping through; the flows without JavaScript.

Rules: scripts through `tunOnContent` and `data-tun-*` delegation,
`tunPopoverOpen` and `tunModal`, no `setTimeout` for motion, act on click;
`ui-look`'s scans hold for every new part, and every earlier ui-* test and
check stays green. Warnings from the source: the date picker's closing
motion was never done there (done here, as `ui-sheets` does for everything
that opens); its chosen and today days were bold (not carried); dense
toolbars on phones were the recurring trap. Out of scope: search on Ctrl K
(`ui-search`, next), moving the clients onto the new fields (the Log says
what each would change), a date and time in one field unless it falls out
cheaply. The five clients (factory, nixploy-dashboard, ferdig, kurs,
tun-erp) compile and pass unchanged; tun-erp, with orders, invoices, rental
periods and money everywhere, last and carefully.

Mode: reviewed. A core change, a minor version.

## Criteria

1. **Reading a date.** A new function `(read-date-text TEXT)` in `TUN`
   gives the date TEXT names as `YYYY-MM-DD`, or NIL and a message, in
   every language alike, with the tenant's today's year where TEXT names
   none:
   - day first: a day and a month of one or two digits and a year of four
     digits, or two (20YY), or none, between `.`, `/`, `-`, `,` or spaces,
     one or more, with one more at the end allowed: `1.2.2026`,
     `01.02.2026`, `1/2/26`, `1-2-2026`, `1 2 2026`, `1.2.`, `1.2`;
   - digits alone: eight `DDMMYYYY`, six `DDMMYY`, four `DDMM`;
   - year first: four digits, then the month and the day: `2026-02-01`,
     `2026-2-1`, `2026.02.01`;
   - with a month's name, in English or in the current language, whole or
     its first three letters, any case, a dot after it allowed, the day
     before or after it and the year after both or none: `1 Feb 2026`,
     `1. februar 2026`, `Feb 1, 2026`, `1 feb`, `21. okt.`;
   - refused: a day or a month out of range, a day the month lacks
     (`31.4.2026`, `29.2.2027`), a year of one, three or five or more
     digits, a year before 1900, five or seven digits alone, more than
     three parts, a time, any other letters, two months, and the empty
     text (NIL with no message, «nothing given»).
   A property-style test reads every day of 2024 to 2027 in each accepted
   form as itself, every refused form as refused, and 10 000 random texts
   of digits, separators and month names without an error, never a date
   out of 1900–9999. (`ui-fields-tests`)
2. **Reading a time and an amount.** `(read-time-text TEXT)` in `TUN`
   gives a time of day as `HH:MM`, 24 hours, or NIL and a message: an hour
   of one or two digits alone (`9` → `09:00`), three or four digits
   (`930` → `09:30`, `1330`), or the hour and two digits of minutes
   between `:`, `.`, `,` or a space (`9:30`, `09.30`, `9,30`); refused: an
   hour past 23, minutes past 59, minutes of one digit, seconds, `am` or
   `pm`, and anything else; every minute of a day in each accepted form is
   read as itself. `read-money-text`, as `i18n.md` §5.4 has it, is in
   `TUN` too. Over a page (`web-call`) a `date` input given text that is
   not `YYYY-MM-DD` is read with `read-date-text`, as an amount is read
   today: read, the operation gets the ISO date; not, the field's error is
   «must be a date, such as 21 Oct 2026» («må være en dato, som
   21.10.2026»). Over MCP and `/api` a date stays `YYYY-MM-DD` only.
   (`ui-fields-tests`)
3. **`date-input`.** A new component in the forms group, `(date-input
   (:label :name :value :hint :error :min :max :quick ...))`: a `field`
   holding a text field (`inputmode="decimal"`, `autocomplete="off"`
   unless given) whose VALUE, an ISO date, is written as `date-text` writes
   it («21 Oct 2026», «21.10.2026») and any other text as it is; its hint
   ends with the form, «For example, 21 Oct 2026» («For eksempel
   21.10.2026»), after the caller's (unless `:form-hint nil`, for a
   second field beside a first); an error sets `aria-invalid` and is
   tied by `aria-describedby`, as `text-input`'s. It posts what is in the
   field under NAME. Where scripts run, a calendar button stands inside
   the field's end; without them it is not shown and the field is a plain
   text field. (`ui-fields-tests`: the markup in both languages;
   `ui-fields.py`: the button shown and not without JavaScript)
4. **The calendar.** The button (`aria-haspopup="dialog"`, named «Choose a
   date») opens a `popover="auto"` with `role="dialog"`, `aria-modal`,
   named by its month's title: the month and year («November 2026»,
   «november 2026»), a previous and a next month button, a grid
   (`role="grid"`) of six weeks from Monday, its columns headed by the
   days' short names with their full names as `abbr`, all from the
   catalogue. It opens on the field's date when the field holds one the
   page wrote or the calendar chose, or one written as `YYYY-MM-DD`, as
   `D.M.YYYY` or as `date-text` writes it; else on today's month (the
   tenant's today, from the server). Today has `aria-current="date"` and a
   frame; the chosen day `aria-selected="true"` and the ink fill; both at
   the weight and size of the others. Days before MIN or after MAX are
   `aria-disabled` and greyed and cannot be chosen. Arrows move a day or a
   week, PageUp/PageDown a month, Shift with them a year, Home/End the
   start and end of the week, Enter or Space chooses, Escape closes, Tab
   stays inside; the focused day is the one tabbable day. Choosing writes
   the day in the field as `date-text` writes it, fires `input` and
   `change`, closes the calendar, and gives the focus back to the button,
   as Escape and a press outside do. QUICK (`t` for «Today» and
   «Tomorrow», or `(LABEL DATE)` pairs) adds buttons under the grid that
   choose their day. (`ui-fields.py`, light and dark: the roles and names,
   the week's first day, today and the chosen day, the keyboard walk, min
   and max, the focus back, the font weight of chosen, today and other days
   equal; `ui-fields-tests`: the markup and the catalogue)
5. **The calendar moves into place.** From 40rem of the window it stands
   under the field (above when there is more room there), inside the
   window, rising 0.25rem and fading in over `--duration-fast`; below 40rem
   it is a floating sheet at the window's bottom, 0.75rem from its sides
   and above the bottom's safe area, every corner `--radius-xl`, with a
   close button, over the `--overlay` dim, rising from below over
   `--duration`; it leaves over `--duration-close`, sinking and fading,
   animating only `opacity` and `translate`. At 320, 360 and 390 px its
   box is wholly inside the window and every day at least 2.5rem high.
   (`ui-fields-tests` with `ui-sheets`' scan of what opens; `ui-fields.py`:
   the boxes, the transition's properties and durations open and closing)
6. **`time-input` and `money-input`.** `time-input` is a text field 5
   characters wide with the hint «For example, 09:30» («For eksempel
   09:30») after the caller's, `inputmode="decimal"`, tabular digits, no
   picker. `money-input` is an `input-group` (`tun-money-input
   tun-input-group`) whose field is right-aligned in tabular digits,
   `inputmode="decimal"`, `autocomplete="off"`, 10 characters wide unless
   given, the currency (`:currency`, the tenant's by default) before it in
   English and after it in Norwegian, as `money-text` writes it (`€`,
   `NOK`; `kr`, `€`); a VALUE that is an integer of minor units is written
   as the language writes the amount without its currency («1,250.50»,
   «1 250,50»), any other text as it is; nothing is read or rounded in the
   browser. (`ui-fields-tests`; `ui-fields.py`: right-aligned, tabular)
7. **Generated forms.** A `date` input of a generated form is a
   `date-input`, a `money` input a `money-input`; what a person types is
   posted as it is and read on the server (criterion 2), so the operation
   gets `YYYY-MM-DD` and minor units as before, a test posting
   `2026-11-12` gets what it got, and a value that cannot be read comes
   back in its field, as typed, with its error. Tun has no time type, so
   no generated form shows a `time-input`. `text-input :type :date` is the
   browser's own field, as before. (`ui-fields-tests` on the test client's
   generated forms: a typed `12.11.2026`, `2026-11-12` and a refused
   `31.11.2026`, and an amount; `ui-forms-tests` unchanged)
8. **A period in the list toolbar.** A filter of KIND `:period`,
   `(:kind :period :label L :names (FROM TO) :value (FROM-VALUE TO-VALUE)
   [:quick ((LABEL FROM TO)...)] [:errors (FROM-ERROR TO-ERROR)])`, sends
   two address keys, FROM and TO, both in every submission and in every
   clear and «Reset» link. Its button says L, or in use «L: 1–14 Nov», as
   a new `(period-text FROM TO)` in `TUN` writes it (`1–14 Nov`,
   `28 Oct – 3 Nov`, the years when not this year, `From 1 Nov`, `Until 14
   Nov`; nb `01.–14.11.`, `28.10.–03.11.`, `Fra 01.11.`, `Til 14.11.`), at
   the weight, size and height of one not in use, with its clear ×. It
   opens the popover of `ui-filters` (a floating sheet on a phone) holding
   the quick choices «Today», «This week» (Monday to Sunday), «This month»,
   «Last month» and the caller's, each a link to the address with that
   period, the one in use `aria-current="true"` by its frame, and two
   `date-input`s, «From» and «To», with their calendars, the form hint
   under «From» alone; it opens with the focus on a quick choice. Where scripts run
   a quick choice fills both fields, closes the popover with the focus on
   its button and submits; a day chosen in a calendar, and a date typed and
   left (or Enter), submits once, the popover staying open; nothing
   submits while a date is typed, and a submission whose fields are the
   same as the last is not sent. In the «Filters» sheet it is a row with
   its quick choices and fields under it. Without JavaScript the popover
   opens, a quick choice is a link, and «Apply» submits the typed dates.
   (`ui-fields-tests`: markup, keys, links, summary in both languages;
   `ui-fields.py`: the address once per choice, Back stepping through,
   the sheet, without JavaScript)
9. **The generated list's period.** A generated list whose list operation
   has two `date` inputs named `from` and `to`, `since` and `until`,
   `from_date` and `to_date`, or `start_date` and `end_date` (the first
   such pair) gets one `:period` filter «Period» («Periode») with those
   keys, after its other filters; the values from the address go to the
   operation as given, read there (criterion 2), and a refused one shows
   its error at its field in the popover as well as the list's refusal.
   The test client's `/orders` gets a period of `from` and `to`, and
   `/orders?from=1.11.2026&to=` lists what `from=2026-11-01` does.
   (`ui-fields-tests`)
10. **The specimen, the showcase and the pictures.** `/ui/date-input`,
    `/ui/time-input` and `/ui/money-input` show each field empty, filled,
    with an error and disabled (and `date-input` with QUICK and MIN/MAX);
    `/ui/list-toolbar` a period in use. The showcase gains `/fields`, a
    form of the three fields that posts and shows what the server read
    (the ISO date, `HH:MM`, minor units) or the fields' errors, and
    `/days`, the cards as a list with a toolbar of a search, a period over
    the cards' «Reported on» (keys `from` and `to`), a status and a toggle,
    with cards reported on different days (`/cards` keeps its three
    filters, which `ui-filters.py` and `ui-lists.py` measure). Pictures before and after of the
    specimen's field pages and `list-toolbar` at 390 and 1280 px, light and
    dark, and of the calendar open and the period open. A new
    `checks/showcase/checks/ui-fields.py` measures criteria 3–6 and 8 and:
    typing each form of criterion 1's list on `/fields` and posting gives
    the ISO date the server read, in English and in Norwegian; the time
    and amount forms of criterion 2; no page error; no page scrolling
    sideways at 320, 360 and 390 px. Every earlier ui-* test and check
    stays green, none weakened.
11. **The spec, the clients.** `spec/ui.md` §6 (`date-input`,
    `time-input`, `money-input`, the period), §8 (forms and lists), §9 (the
    date picker no longer «not yet»), §10; `spec/i18n.md` §6.2 (reading a
    date and a time); `docs/client-api.md`; core 2.30.0. No component's
    call shape changes; the five clients build and pass their own
    `bin/test` against this tree, unchanged, each result in the Log, and
    the Log names every place tun-erp's pages would now render a new field
    and whether its tests' posted values still read, and what each client
    would change to move its own date and amount fields onto the new ones.

## Decisions

- **One reader, on the server.** The field posts what the person sees, and
  the server reads it (`read-date-text`, `read-time-text`,
  `read-money-text`). No hidden ISO field: it would make two paths (ISO
  with scripts, text without), so every page would still have to read text
  and the two readers could disagree; the server is the judge of every
  value. What a client receives keeps its shape because the reading is
  where it was for amounts: a generated form's values go through
  `web-call`, which reads them into what the operation takes, so the
  operation gets `YYYY-MM-DD` as before; a client's page that calls
  `text-input :type :date` keeps the browser's field and its ISO value,
  and a client's page that moves to `date-input` reads with
  `read-date-text`. The script reads a date only to open the calendar on
  it (the forms the page and the calendar write, and ISO), never to judge
  or post one.
- **Day first in both languages.** Tun writes dates day first in English
  too («21 Oct 2026»), so a typed `1/2/2026` is the 1st of February in
  every language, and an address typed in one language reads the same in
  the other. The field writes a date as `date-text` does, unambiguous in
  English since the month is a name. Month names are read in English
  and in the current language. This is a choice for Jonas (the report asks
  it): a person used to month first would misread `1/2`.
- **Two-digit years are 20YY**, as the source does; another century is
  typed in four digits.
- **`inputmode="decimal"`** for dates and times: a phone's decimal pad has
  digits and a mark (`.` or `,`), both read as separators, and eight digits
  need none; `numeric` would leave no separator at all.
- **The week starts on Monday** in both languages (ISO 8601, and how Tun's
  English writes dates); one function decides it, for a regional setting
  later.
- **The calendar is a popover with `role="dialog"`** and `aria-modal`, Tab
  kept inside, as the WAI-ARIA date picker dialog pattern has it; the
  grid is built by the script from the names the server wrote in the page
  (no copy in the script, `i18n.md` §3.6), and today is the tenant's,
  written by the server, not the browser's clock. No week numbers (the
  source has a column of them): left for later.
- **No time picker.** The source's hour and minute columns are a second
  sheet for what four digits say; a forgiving text field is quicker.
- **`money-input` is its own component that renders an `input-group`**
  with a second class, so it keeps the group's frame and states and adds
  the alignment; `input-group` itself is unchanged.
- **The period in the address is what the fields hold.** A quick choice
  without scripts is a link with ISO dates; with scripts it fills the
  fields with the dates as `date-text` writes them and submits, as a
  calendar choice does; the page reads either. A page gets FROM-VALUE and
  TO-VALUE as the address gives them and shows them as they are, so a
  morph never rewrites a field under the person's hands, and a second
  `change` never sends the same period again.
- **Applied on `change` and Enter, not on `input`**: a text field's
  `change` fires when it is left or Enter is pressed, never per key; the
  toolbar drops a submission whose fields equal the last one sent, so
  Enter and the `change` that follows send once.
- **The period's popover stays open after a calendar choice** (a from date
  is usually followed by a to date) and closes after a quick choice, which
  sets both, as a `:several` and a `:one` filter do.
- **The generated list's pair rule** is the names agents already use for
  periods in Tun's modules (`from`/`to`) and the usual English pairs; a
  pair is offered whether or not its inputs are required, and nothing
  else changes in the list.
- **The field shows a refused value as typed**, its error beside it, and a
  value it can read as the page gives it: a generated form gives back what
  was posted, the toolbar what the address holds.
- **Core 2.30.0**: three components, a filter kind, four functions in `TUN`,
  dates read over a page; no call shape changes.

## Actuals

```json
{"loop":"ui-fields","title":"The date, time and money fields, and a period as a filter of a list","repository":"tun","mode":"reviewed","stage":"done","item":"sak_t5gvvtw1rr2nbwe8","tags":["kind:ui","core","module:ui"],"like":["tun/ui-filters","tun/ui-sheets"],"started":"2026-11-12 04:20","ended":"2026-11-12 06:20","minutes":{"total":120,"waiting_person":0,"waiting_reviewer":3,"working":117,"drafted":null,"person_at_gates":null,"agent":null},"estimate":{"best":140,"likely":195,"worst":330,"at":"brief"},"latest_estimate":{"best":140,"likely":195,"worst":330,"at":"brief"},"within_estimate":false,"ratio":0.62,"verify":{"rounds":6,"failed":3},"changes":{"A":0,"B":1,"C":0},"interventions":0,"cost":{"tokens_in":null,"tokens_out":null,"usd":null,"agent_minutes":null}}
```

## Log

- 2026-11-12 04:20  started, reviewed
- 2026-11-12 04:20  estimated 2h20m 3h15m 5h30m at brief, like tun/ui-filters tun/ui-sheets
- 2026-11-12 04:25  gate A asked of a reviewer
- 2026-11-12 04:26  gate A: approve (reviewer)
  The spec covers the whole brief, every criterion can be decided by a test or a check, and the spec changes match the criteria. I found only small gaps in wording, none worth sending back.
  
  **Brief against criteria**
  - **Item 1, reading a date:** criterion 1 lists every accepted and refused form. The property-style test checks every day of 2024–2027 in each accepted form plus 10 000 random texts. A refused value comes back as typed (criteria 7 and 10). `inputmode` and `autocomplete` are fixed in criterion 3. The text field without JavaScript is in criterion 3.
  - **Item 2, the calendar:** criteria 4 and 5 cover it.
    - the popover on a wide screen and the floating sheet on a phone
    - motion over the named tokens, only `opacity` and `translate`
    - Escape, a press outside, and the focus going back
    - the full keyboard, min and max, quick choices
    - the roles and names of the WAI-ARIA date picker pattern
    - names from the catalogue, and chosen and today days at equal weight, checked in light and dark
  - **Item 3, `time-input`:** criteria 2 and 6. The forms are pinned and every minute of a day is tested.
  - **Item 4, `money-input`:** criterion 6. Reading uses the existing `read-money-text` from i18n §5.4, so "more decimals refused" and both decimal marks rely on contract that already exists.
  - **Item 5, generated forms:** criterion 7. The how and why are in the Decisions. ISO dates are kept because `web-call` reads the text, and MCP and `/api` stay ISO-only (criterion 2). `text-input :type :date` is unchanged.
  - **Item 6, the period:** criteria 8 and 9. They cover:
    - the two keys the caller names, with the summary text
    - the four quick choices plus the caller's
    - applying on `change` or Enter, never per keystroke, with a repeated submission dropped
    - the × clear, the row in the «Filters» sheet, and «Apply» without JavaScript
    - Back stepping through
    - an explicit pair rule for generated lists, with a concrete test on `/orders`
  - **Item 7 and out of scope:** criterion 10 covers the specimen, `/fields`, `/cards` and the browser check. Criterion 11 has the five clients run unchanged and the Log naming each place tun-erp would change. Out-of-scope items are listed in §9.
  - **"`ui-look`'s scans hold for every new part":** criterion 10 only says earlier tests stay green. That is enough, because those scans already cover the whole stylesheet and every `/ui/NAME` page (`spec/ui.md:1987-2014`), so new parts are scanned automatically.
  
  **Decisions**
  - Reading dates day first in English is the one choice that is arguably the asker's. The brief delegated it ("the English forms decided here"), and the Decision openly flags it for Jonas.
  - Monday as the first day of the week matches Tun's day-first English, and one function decides it so a regional setting can come later.
  - The other decisions (one reader on the server, no hidden ISO field, no time picker, `money-input` wrapping `input-group`) are justified design choices.
  
  **Small wording gaps, worth fixing while building but not blocking**
  - `spec/ui.md` (the date-input's keyboard paragraph, diff around line 167): Tab goes round "the close button", but criterion 5 gives the calendar a close button only below 40rem. The wording should say this applies on a phone.
  - `spec/i18n.md` §6.2 doesn't state criterion 1's "year after both or none" for dates with month names, or "more than three parts" and "a time" as refused. The test should pin them, and the spec can say them.
  - What a quick choice does when its day falls outside `:min`/`:max` (for example «Today» with a minimum of tomorrow) is unstated. The likely answer is that it is disabled like the days in the grid.
- 2026-11-12 05:07  verify 1: failed test
- 2026-11-12 05:08  verify 1 failed on markdown's costly-texts-take-time-in-proportion-to-their-length (0.118 s against 0.007 s for a text 3.4 times as long, a timing under the parallel run, in a component this loop does not touch); it passed in the full bin/test run before it; build and the browser checks passed; verify again unchanged
- 2026-11-12 05:18  verify 2: passed build, test, check
- 2026-11-12 05:19  shown (/ui/date-input, /ui/time-input, /ui/money-input, /fields, /days?q=&from=2026-11-01&to=2026-11-14&status=&files=, /ui/list-toolbar)
- 2026-11-12 05:20  the period's page is /days, not /cards: /cards keeps its three filters, which ui-filters.py and ui-lists.py measure (one row of four parts at 1280 px, three buttons without JavaScript); /days lists the cards with a search, the period over «Reported on» (from, to), a status and a toggle, so a phone folds them into «Filters» and the period is a row of it; criterion 10 and spec §10 say /days
- 2026-11-12 05:20  two earlier tests change with the spec, none weakened: ui-filters' generated orders list no longer checks that no date is offered (its from and to are now the period) but that other text (department) is not, and its «Reset» address names from and to as well; the renderer's allowed attributes gain abbr (a table heading's full text, which runs nothing), for the calendar's weekday headings
- 2026-11-12 05:20  the toolbar sends no submission whose fields are those the page shows or those last sent: the page's state is taken again after every swap (tunOnContent), so Back and a morph never leave a stale baseline; Enter in a period's field submits through the same path, so Enter and the change that follows send once (ui-fields.py counts the requests)
- 2026-11-12 05:20  pictures: the specimen before (base f09131b) and after at 390 and 1280 px, light and dark, ~/coding/tun-wt/ui-fields-shots/before/ and after/ (text-input, input-group, list-toolbar, field; after also date-input, time-input, money-input, which are new); open states in after/open/: the calendar at 1280 (light, dark) and as a floating sheet at 390 (light, dark), the period open at 1280, the period as a row of the «Filters» sheet at 390, and the show's pages (/fields, /days, the specimen)
- 2026-11-12 05:20  the browser check ui-fields.py: 65 results, all passing in verify 2 (en and nb typing, the calendar at 1280/390/360/320 light and dark, keys, focus, motion open and closing, min/max, quick choices, money alignment, the period's single submissions, Back, the sheet row, without JavaScript)
- 2026-11-12 05:30  the five clients' bin/test against this tree (local commit cb7cc10, the verified tree but for spec §10's naming of /days; nix develop --override-input tun git+file of the worktree, on clones in the builder's scratch folder, one at a time), unchanged: tunworks/apps/factory 583 passed; tunworks/apps/nixploy-dashboard 1421 passed; tunworks/apps/ferdig 812 passed; kurs 352 passed; tun-erp 854, 77372, 344, 244, 304, 8852, 243, 109900, 90700, 16534 and 26225 passed; no compiler warning, no failure
- 2026-11-12 05:31  where the clients would now render a new field: nowhere. A generated form or list changes only for a resource whose operations have date or money inputs; the five clients enable dashboard (factory, nixploy-dashboard, ferdig), none (kurs) or customers among Tun's modules (tun-erp, whose crm renders /customers itself), and customers' create and list operations have no date or money input; no client registers a web resource of its own. web-call now reads a date given as text that is not YYYY-MM-DD, where it refused it before; the clients' pages pass dates from the browser's <input type=date> (ISO), so their tests' posted values read as before, and their suites pass unchanged
- 2026-11-12 05:31  what moving each client onto the new fields would change (read-only): tun-erp: about 20 hand-built date fields (text-input :type :date) on work (work-time-pages 209, pages 271/279, work-order-pages 143/144/506), sales (inquiry-pages 121, order-pages 211/213/305/307), billing (status-pages 114), messages (pages 264), overview (pages 59/60), rental (pages 45, handover-pages 107) and stock (pages 288/290) would become date-input, each page reading its value with read-date-text in place of taking the ISO string, and the browser checks that fill ISO into type=date would type a date; the from/to pairs of /orders, /work, /rental, /overview and /stock would become a :period filter of a list-toolbar (with the ui-filters move); amounts in input-group (billing status-pages 108, payment-fake 307, invoice-pages 496, sales order-pages 542, products pages 368, stock pages 212) would become money-input, which already read with read-money-text, and the percent fields stay input-group; times typed in text-input :width 5 (work start_time/end_time, messages send_time) would become time-input read with read-time-text. ferdig, factory, nixploy-dashboard and kurs have no date, time or amount field to move
- 2026-11-12 05:41  verify 3: passed build, test, check
- 2026-11-12 05:41  shown (/ui/date-input, /ui/time-input, /ui/money-input, /fields, /days?q=&from=2026-11-01&to=2026-11-14&status=&files=, /ui/list-toolbar)
- 2026-11-12 05:42  verify 3 passed after spec §10 named /days; the clients' runs on cb7cc10 stand, since only that line of the spec changed since
- 2026-11-12 05:42  gate B asked of a reviewer
- 2026-11-12 05:43  gate B: changes (reviewer)
  I'm asking for changes: one test will start failing tomorrow and another on 1 January. Otherwise the change does what the brief asks and is in good shape.
  
  **What is right**
  - **Verification:** `verify.txt` round 3 passed build, test and check. The browser check `ui-fields.py` has 65 results, all passing. The five clients ran unchanged and the Log names every place tun-erp would change.
  - **Reading dates and times** (`src/core/formats.lisp:1129-1202`): the code matches criteria 1–2. The property test reads every day of 2024–2027 in 17 forms with a year and 6 without, every minute of a day in each time form, and 10 000 random texts. Over a page a typed date is read; over MCP it stays ISO only (`src/core/types.lisp:1294-1304`, tested at `tests/ui-fields-tests.lisp:2719`).
  - **The calendar:** it has the roles of the WAI-ARIA date picker and its full keyboard, and Tab stays inside. The chosen day and today keep the weight and size of the others. It animates only `opacity` and `translate`, with no `setTimeout` and no copied text in the script. On a phone it is a floating sheet with the dim and a close button (`checks/ui-fields-calendar-390-light.png`).
  - **The period:** it sends both keys in every submission, clear link and «Reset». The toolbar sends the same fields only once (`toolbar.lisp:2456-2464`). The checks count requests and history entries and step Back through them. It is a row of the «Filters» sheet at 390 px, and «Apply» works without JavaScript. The screenshots show «Reported: 5–15 Nov» at 1280 px and the sheet row at 390 px.
  - **Generated forms and lists:** they use the new fields, and the operation still gets ISO dates and minor units (`tests/ui-fields-tests.lisp:2894-2917`, `:2976-2995`).
  - **Changes to earlier tests:** the two edits to `ui-filters-tests` follow the spec change, and neither is weakened.
  - **`/days` instead of `/cards`:** moving the period to `/days` is explained in the Log and keeps the earlier checks on `/cards` honest. It still gives the asker a list with a period.
  - **The spec:** `spec/ui.md` and `spec/i18n.md` describe the behaviour. The gate-A note about the close button showing only on a phone is fixed.
  
  **Changes**
  1. **`tests/ui-fields-tests.lisp:2783` and `:2790` will fail from 2026-11-13.** `the-calendar-speaks-norwegian-and-starts-on-monday` renders outside an application, so `page-today` reads the system clock. The test passes `:min "2026-11-13"` and expects «I dag» to be disabled, which holds only while the real date is before the 13th. From tomorrow `bin/test` fails for everyone.
     - Make the test independent of the date. For example, take `:min` as the day after `(tun.core:page-today)`, or bind the clock.
  2. **`tests/ui-fields-tests.lisp:2954-2961` will fail from 2027-01-01.** `a-period-shows-its-errors-and-speaks-norwegian` expects `01.11.–31.11.2026`. `period-text` leaves the year out only when the date is in today's year, so in 2027 the text becomes `01.11.2026–31.11.2026`.
     - Build the dates from `page-today`'s year, as `a-period-sends-two-keys-and-says-its-days` at `:2926` already does.
  
  Both are small fixes, but the first would break the shared suite within a day of the merge.
- 2026-11-12 05:44  gate B 1's changes: the-calendar-speaks-norwegian-and-starts-on-monday takes its MIN as the day after page-today, so «I dag» is outside it on any day; a-period-shows-its-errors-and-speaks-norwegian builds its days in page-today's year, so its summary leaves the year out in any year; the other tests' dates are fixed inputs (:today given, or readings that hold in any year)
- 2026-11-12 05:54  verify 4: failed check
- 2026-11-12 05:56  verify 4 failed on one of ui-lists' 92 results, «pressing a link in a row leaves the row unpressed» (the row's ground at rgba(0,0,0,0.027), the pointer's hover tint still easing in under the full check run); round 4 changed only two Lisp tests since verify 3 passed it, and ui-lists passed alone twice unchanged; verify again unchanged
- 2026-11-12 06:06  verify 5: failed test
- 2026-11-12 06:07  verify 5 failed on markdown's costly-texts-take-time-in-proportion-to-their-length again (table rows 0.053 s against 0.004 s, a pause in a timing of milliseconds under the parallel run), the same flake ui-graph-fit's verify 1 met on 2026-11-10; markdown is untouched here, and the build and the browser checks passed; verify again unchanged
- 2026-11-12 06:17  verify 6: passed build, test, check
- 2026-11-12 06:18  shown (/ui/date-input, /ui/time-input, /ui/money-input, /fields, /days?q=&from=2026-11-01&to=2026-11-14&status=&files=, /ui/list-toolbar)
- 2026-11-12 06:18  the clients' runs on cb7cc10 stand: since then only two Lisp tests and spec §10's naming of /days changed
- 2026-11-12 06:18  gate B asked of a reviewer
- 2026-11-12 06:19  gate B: approve (reviewer)
  I'm approving. Both fixes from the last round are in, verify round 6 passed, and I found no other test that will fail on a later date.
  
  **The two fixes from gate B round 1**
  - **`tests/ui-fields-tests.lisp:2780-2793`:** `the-calendar-speaks-norwegian-and-starts-on-monday` now sets `:min` to the day after `page-today`. So «I dag» is outside the allowed range and disabled on any day the suite runs, and «I morgen» still shows.
  - **`tests/ui-fields-tests.lisp:2956-2968`:** `a-period-shows-its-errors-and-speaks-norwegian` builds its dates in `page-today`'s year. The summary `01.11.–31.11.YYYY` therefore holds in any year: the from date is in this year so its year is left out, and the refused to date is written as typed. This is the same approach `a-period-sends-two-keys-and-says-its-days` (`:2927`) uses.
  
  **Other tests that could depend on the date**
  - **The Lisp tests:**
    - The readers' tests and `period-text`'s tests either pass `:today` or use dates with a year.
    - `a-quick-choice-in-use-is-marked` takes today from `page-today`.
    - `the-generated-list-offers-a-pair-of-dates-as-a-period` calls `period-text` without `:today` on both sides of its comparison, so the two always agree.
  - **The browser check `ui-fields.py`:**
    - The calendar walk and «Tomorrow» are computed from the today the page reports (`dataset.today`).
    - On `/fields` (`diff.patch:440`), the «Return date» field has a fixed min and max of 2026-11-01 to 2026-12-31. The check only asks that every disabled day lies outside that range. Each month's grid shows at least one disabled day, so the check holds before, during and after those two months.
  
  **Verification**
  - `verify.txt` round 6: build, test and check all ok.
  - `checks/ui-fields.json` has its 65 results, and no check file shows a failure.
  - Rounds 4 and 5 failed on two flaky checks in parts this loop doesn't change:
    - **Round 5:** `markdown`'s timing test. Markdown is untouched here, and the same test flaked in round 1 and in an earlier loop.
    - **Round 4:** one result of `ui-lists`, a hover tint still fading in. It passed in rounds 3 and 6 with the toolbar code unchanged, and passed twice when run alone.
  - Since round 3 passed, only the two tests above changed, and they are not code the clients use, so the five clients' runs on `cb7cc10` still stand.
  
  **Everything else** is as gate B round 1 found it:
  - Criteria 1–11 each have a test or check.
  - The screenshots cover phone and desktop widths, with the calendar open and the period open.
  - The spec changes are where the behaviour changed.
  - The two edits to `ui-filters-tests` follow the spec and weaken nothing.
- 2026-11-12 06:20  pushed 7bcd6f3 to Tun's main, core 2.30.0
- 2026-11-12 06:20  finished at tun 7bcd6f38
