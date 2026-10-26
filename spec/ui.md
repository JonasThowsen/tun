# The design system

Status: v1, 2026-10-13; a client's pages (§8), 2026-10-15; htmx 4
(§4.1, §8.1) and the board (§6.1), 2026-10-21; installing as an app
(§4.2), 2026-10-22; ordering a board's cards within a column (§6.1),
2026-10-26, core 1.18.0; push notifications in the service worker and
`push-switch` (`push.md`), 2026-10-26, core 1.19.0. How every Tun
page looks and behaves: the tokens, the components that are built from
them, the specimen that shows them, and the rules a component follows.
The generated screens (`ui.lisp`, `access.lisp`) and a client's own
screens are built from these components and nothing else.

## 1. Sources

Tun does not invent its look. Each component is converted from an open
source design system, and says which one:

| Source | Licence | What Tun takes |
|---|---|---|
| [Basecoat](https://basecoatui.com), shadcn/ui in plain HTML | MIT | The look: tokens, markup and CSS of each component, its default style (Vega). |
| [GOV.UK Design System](https://design-system.service.gov.uk) | MIT (code) | Behaviour of forms: labels, hints, errors on the field and in a summary, fieldsets, confirmation, the summary list. |
| [Designsystemet](https://www.designsystemet.no) (Digdir) and [Aksel](https://aksel.nav.no) (NAV) | MIT | Norwegian wording, accessibility, dense staff screens. |
| [Lucide](https://lucide.dev) | ISC | Icons, as inline SVG. |

`reference/ui-sources.md` holds the licences and copyright lines these
licences require, and which Tun file uses which source.

## 2. Principles

- **HTML first.** Every page works with JavaScript off: links navigate,
  forms post, `<details>` opens, `<dialog>` and popovers use the
  browser's own behaviour where it has one. JavaScript only adds what
  HTML cannot do (copying to the clipboard, a menu that closes on Escape
  where the browser does not already, tabs, dragging a card).
- **Snappy.** With JavaScript on, htmx (§4.1) swaps pages and parts of
  pages in place of full loads. The server still renders every piece of
  HTML: htmx only decides where an answer goes. A component's own script
  is plain JavaScript, for what htmx does not do.
- **Phone first.** Every component is designed at 390 px wide first and
  works down to 320 px without horizontal scrolling of the page. Wide
  content (a table) scrolls inside its own box or changes layout.
- **Touch.** On a coarse pointer, controls are at least 44 px high
  (`--control-height` grows, §3); inputs use 16 px text so phones do not
  zoom.
- **Accessible.** WCAG 2.2 AA: contrast of text at least 4.5:1, every
  control has a label, errors are tied to their field
  (`aria-describedby`, `aria-invalid`), focus is always visible,
  `prefers-reduced-motion` stops motion.
- **Norwegian.** Labels and copy are Norwegian bokmål; code identifiers
  and class names are English.
- **Plain CSS.** No build step, no Tailwind, no preprocessor. Modern CSS
  only: custom properties, `@layer`, nesting, `:has()`, `color-mix()`,
  container queries.
- **Tokens decide.** A component's CSS uses tokens (§3) for every colour,
  size, radius, shadow and duration. A literal value needs a reason in a
  comment.

## 3. Tokens

Tokens are CSS custom properties on `:root`, in the layer `tokens`. The
colour names are shadcn's, so a shadcn theme fits; Tun adds status
colours, sizes and motion.

- **Colour:** `--background`, `--foreground`, `--card`,
  `--card-foreground`, `--popover`, `--popover-foreground`, `--primary`,
  `--primary-foreground`, `--secondary`, `--secondary-foreground`,
  `--muted`, `--muted-foreground`, `--accent`, `--accent-foreground`,
  `--destructive`, `--destructive-foreground`, `--border`, `--input`,
  `--ring`.
- **Status:** for each of `info`, `success`, `warning` and `destructive`:
  `--STATUS` (icons, borders, text on the soft background),
  `--STATUS-foreground` (text on `--STATUS`) and `--STATUS-soft` (a tinted
  background).
- **Type:** `--font-sans`, `--font-mono`; `--text-xs`, `--text-sm`,
  `--text-base`, `--text-lg`, `--text-xl`, `--text-2xl`, `--text-3xl`,
  each with `--text-SIZE--line-height`; `--font-weight-normal`,
  `-medium`, `-semibold`, `-bold`.
- **Space:** `--spacing` (0.25rem); a component writes
  `calc(var(--spacing) * N)` as Tailwind's `N` would be.
- **Radius:** `--radius` and `--radius-sm`, `-md`, `-lg`, `-xl`, `-full`.
- **Shadow:** `--shadow-xs`, `-sm`, `-md`, `-lg`.
- **Controls:** `--control-height` (2.25rem; 2.75rem on a coarse
  pointer), `--control-height-sm`, `--control-height-lg`,
  `--control-font-size` (0.875rem; 1rem on a coarse pointer).
- **Focus:** `--focus-ring`, the box-shadow of a focused control.
- **Motion:** `--duration-fast`, `--duration`, `--ease`; all 0 under
  `prefers-reduced-motion`.
- **Layers above the page:** `--z-sticky`, `--z-dropdown`, `--z-dialog`,
  `--z-toast`.

Each colour token holds both its values, `light-dark(LIGHT, DARK)`, and
`color-scheme` on `<html>` picks one: the visitor's system setting, or
`data-theme="light"` or `"dark"` when they chose one. A component that
needs a different value in the dark writes `light-dark()` itself; no
component has a dark-mode selector.

## 4. The stylesheet and the script

- One stylesheet, in this layer order:
  `@layer reset, tokens, base, components, client;`. `reset` and `base`
  style bare elements (body, headings, links, code); `components` holds
  every component's CSS; `client` is reserved for a client's theme.
- Each component's CSS is kept beside its markup (§5) and the kernel
  joins them. The stylesheet is served at `/assets/tun-HASH.css`, and the
  components' script at `/assets/tun-HASH.js` (loaded with `defer`),
  where HASH is the first 12 hex digits of the content's SHA-256. Both
  are sent with `Cache-Control: public, max-age=31536000, immutable`.
  Redefining a component in the REPL changes the hash, so the next page
  load takes the new CSS.
- Pages carry no `style` attributes and no inline scripts. A script may
  set an element's style while it runs (placing a menu, a dragged card).
- Every page has `<meta name="viewport" content="width=device-width,
  initial-scale=1">`.
- A script that prepares elements once they are in the page (reveals a
  copy button, focuses an error summary) runs its setup through
  `tunOnContent(SETUP)`: once the page has loaded, and again after each
  swap htmx makes, so content htmx brings in is set up too.

### 4.1 htmx

- Tun serves [htmx](https://htmx.org) 4.0.0 (0BSD), unchanged, at
  `/assets/htmx-HASH.js` with the same cache headers, loaded with `defer`
  before the components' script. `reference/ui-sources.md` names the
  version and the SHA-256 of the file.
- Every page's `<head>` carries htmx's configuration as
  `<meta name="htmx-config">`:
  - `mode` `same-origin`: htmx only asks this server;
  - `extensions` `tun`: no extension loads but Tun's own;
  - `noSwap` 204 and 304: every other answer is swapped in, so a refused
    form (422), a 403 or a 404 shows its page as it would without htmx;
  - `includeIndicatorCSS` false: htmx adds no styles of its own.
- Tun's extension, in the components' script, keeps htmx from running
  JavaScript: it gives htmx a `Function` that refuses, so `hx-on`, `js:`
  values and trigger filters do nothing, and a script policy that empties
  every `<script>` htmx swaps in.
- htmx keeps no copy of a page in the browser's storage, where it would
  outlive a logout: Back fetches the page again as a whole page.
- A staff page's `app-shell` carries `hx-boost:inherited="true"`: its links
  and forms load the next page with htmx, which swaps the `<body>`, sets
  the title and pushes the URL; a 303 after a post is followed and its URL
  pushed. A page for someone not logged in is not boosted, so signing in
  goes through the browser.
- The shell also sends `Tun-Assets: CSS-HASH JS-HASH` with each htmx
  request (`hx-headers:inherited`). After a deploy that changed the
  stylesheet or a script, htmx asking for a whole page with hashes that
  are not the current ones is answered with `HX-Redirect` to the page, so
  the browser loads it in full with the new assets.
- **Preloading.** A link htmx boosts loads its page in the background
  when a person shows they are about to follow it: a mouse pointer that
  stays on it for 100 ms, a touch, or a mouse button pressed on it. A
  click within 10 seconds shows that page without another request;
  htmx swaps it, sets the title and pushes the address as for any
  boosted link. A mouse click on a link preloads it once at most: the
  press and the click end a pointer's rest on it, and a link no longer
  in the page is not preloaded.
- A preload serves only the next request from this window: every htmx
  request, a GET too, drops every other preloaded page, those still
  loading too, when it starts and again when it ends, and no page is
  preloaded while an htmx request is under way. So a page is never
  shown from before a change made from this window, whether a post made
  it or a GET (§8, `:remembers`).
- A preload request carries the headers the click would send, htmx's
  and the shell's `Tun-Assets`, and `Tun-Preload: true` besides, and so
  does the request a redirect of it leads to. Its answer is handled as
  the click's own would be, so an `HX-Redirect` for new assets loads
  the page in full. `(preload-request-p)` is true while a page answers a
  preload.
- A page records nothing for a preload: one that would record something
  for the GET answers `(decline-preload)` instead, which is 204 with
  `Tun-Preload: declined`, and the click then asks the server as it
  would without preloading. A page that `:remembers` declines a preload
  that would save its query (§8).
- Not preloaded: a link to another site, with a `target` or `download`,
  with an htmx request of its own (`hx-get` and the like), or inside an
  element with `data-tun-preload="off"`, the link itself included, as a
  link that acts on a GET should be.

### 4.2 Installing as an app

A client that declares `(:web-app ...)` in `define-application` can be
installed as an app on a phone or a computer (a progressive web app).
Without it, no page links a manifest and nothing is installed.

```lisp
(:web-app :short-name "Saker"
          :theme-color "#ffffff" :dark-theme-color "#0a0a0a"
          :background-color "#ffffff"
          :icons "icons/")
```

- **The options.** `:icons` is required: a directory, relative to the
  file that holds `define-application`. `:short-name`, the name under
  the icon, is at most 12 characters, and defaults to the application's
  title. The colours are `#rgb` or `#rrggbb`. The theme colours are the
  browser's bar in light and dark mode, and they default to the design
  system's background, `#ffffff` and `#0a0a0a`. `:background-color` is
  the screen shown while the app starts, and it defaults to `#ffffff`.
  A wrong option is an error when the form is compiled.
- **The icons.** The directory holds `icon.svg`, `icon-192.png`
  (192×192), `icon-512.png` (512×512), `icon-maskable-512.png`
  (512×512, its content inside the middle 80 %, as Android crops it)
  and `apple-touch-icon.png` (180×180). They are read when the form is
  compiled, so the compiled client holds them and a built server needs
  no source tree: the directory must be in the client's build sources
  (`tun new`'s flake takes `icons/`). A missing file, a PNG of the
  wrong size or an SVG that is not one is an error then.
  Each is served at `/assets/NAME-HASH.EXT` with the cache headers of
  §4.
- **The manifest.** `/manifest.webmanifest`, as
  `application/manifest+json` and `Cache-Control: no-cache`: `id`,
  `start_url` and `scope` `/`, `name` the application's title,
  `short_name`, `display` `standalone`, `lang` `no`, `theme_color` (the
  light one), `background_color`, and the icons: the SVG (`sizes`
  `any`), the 192 and 512 PNGs, and the maskable one with `purpose`
  `maskable`.
- **The head.** Every page Tun renders (`page-document`, the staff
  frame and the frame for someone not logged in) links the manifest and
  has `theme-color` twice, for `(prefers-color-scheme: light)` and
  `(prefers-color-scheme: dark)`, `rel=icon` for the SVG and the 192
  PNG, `rel=apple-touch-icon`, `apple-mobile-web-app-title` (the short
  name) and `mobile-web-app-capable` `yes`.
- **The offline page.** `/offline` is a page for someone not logged in,
  «Du er frakoblet», with «Prøv igjen», which loads the address again.
  It holds nothing about who is signed in.
- **The service worker.** `/sw.js`, scope `/`, as
  `text/javascript` and `Cache-Control: no-cache`. The components'
  script registers it on a page that links a manifest. When it installs,
  it keeps the current stylesheet, the components' script, htmx and the
  offline page in a cache named after their versions. It answers a
  request for one of those assets from that cache. It answers a page
  (a navigation, GET) from the network, and with the offline page when
  the network fails. It lets every other request through untouched,
  and it never stores a response: pages, `/api` and `/mcp` carry
  signed-in data. A new version (a deploy that changed an asset, the
  title or the offline page) takes over at once and deletes the older
  caches. It also shows the notifications pushed to the device and
  opens their page on a click (`push.md` §7).
- **Without `:web-app`,** `/manifest.webmanifest`, `/offline` and the
  icons are not found, and `/sw.js` is a worker that deletes Tun's
  caches and unregisters itself, so a client that drops the option
  leaves nothing behind in the browsers that installed it.
- `/manifest.webmanifest`, `/sw.js` and `/offline` are Tun's paths, as
  `/login` is: a client's page cannot take them. None of them needs a
  login. The paths under `/push/` are Tun's too, and a client's page
  cannot take them either; which of them need a login is `push.md`
  §2.3.

## 5. Components

A component is defined with `define-component` in the package `TUN.UI`:

```lisp
(define-component button ((&key (variant :primary) (size :default) (type "button")
                                href name value disabled)
                          &rest children)
  (:doc "En knapp for en handling, eller en lenke som ser ut som en.")
  (:source "Basecoat button (Vega)")
  (:css ".tun-button { ... }")
  (:examples ("Varianter" (button () "Lagre") (button (:variant :outline) "Avbryt")))
  ...markup...)
```

- **Call shape.** `(button OPTIONS CHILD...)`: OPTIONS is a property
  list, `()` when there are none; the children are markup nodes
  (`tun.html`). The result is a markup node.
- **Root class.** The outermost element has the class `tun-NAME`.
  Variants and sizes are attributes on it, `data-variant` and
  `data-size`, never extra classes. Inner parts have classes
  `tun-NAME-PART`.
- **Scoped CSS.** Every selector in a component's CSS starts with its
  root class, so no component's styles reach another's. The registry
  checks this at definition.
- **Safe markup.** A component produces only elements and attributes the
  renderer allows in extension output (`tun.html`), so a client's
  screen can use any component. That output may carry these htmx
  attributes, with or without `data-` and with the modifiers `:inherited`
  and `:append`: `hx-get`, `hx-post` (a same-site path or an http(s) URL,
  as `href`), `hx-target`, `hx-swap`, `hx-trigger`, `hx-select`,
  `hx-select-oob`, `hx-swap-oob`, `hx-push-url`, `hx-replace-url`,
  `hx-indicator`, `hx-include`, `hx-vals`, `hx-confirm`, `hx-boost`,
  `hx-disable`, `hx-sync`, `hx-preserve`, `hx-validate`. Any other `hx-`
  or `data-hx-` attribute (`hx-on`, `hx-headers`, `hx-config`,
  `hx-status`, …) is left out.
- **Documented.** `:doc` (Norwegian, one or two sentences on when to use
  it), `:source` (what it was converted from, §1) and at least one
  example are required. Examples are ordinary calls; the specimen shows
  each one rendered and its source.
- **Common options.** Every component takes `:id` and `:attributes`, a
  property list of further attributes for its root element (`aria-*`,
  `data-*`, `hx-*`, `popovertarget` and the like). There is no `:class`: a
  component looks the way its variants say.
- **Accessible by construction.** A form control takes its label as an
  argument and cannot be made without one. Hints and errors are linked
  with `aria-describedby`; an error sets `aria-invalid`.
- **Script.** `(:script "...")` adds JavaScript to the shared script.
  It finds its elements by `data-tun-*` attributes, through event
  delegation on `document`, so it works for markup added later too, and
  prepares elements through `tunOnContent` (§4).

## 6. The component set

| Group (file in `src/web/ui/`) | Components |
|---|---|
| Handlinger (`actions`) | `button`, `icon`, `button-group`, `link`, `kbd`, `badge`, `avatar` |
| Skjema (`forms`, `push`), GOV.UK behaviour | `field`, `text-input`, `textarea`, `select`, `checkbox`, `checkboxes`, `radios`, `switch`, `fieldset`, `input-group`, `error-summary`, `form-actions`, `push-switch` (`push.md` §2.1) |
| Data (`data`, `board`) | `table`, `summary-list`, `card`, `stat`, `empty-state`, `pagination`, `timeline`, `code-block`, `board` |
| Tilbakemelding (`feedback`) | `alert`, `flash`, `confirm-panel`, `progress`, `spinner`, `skeleton` |
| Interaksjon (`interaction`) | `dialog`, `dropdown-menu`, `tooltip`, `accordion`, `tabs` |
| Oppsett og navigasjon (`layout`) | `app-shell`, `page-header`, `section`, `breadcrumbs`, `nav-list`, `stack`, `cluster`, `grid` |

`dialog` with `:shortcut` opens on that key from anywhere on the page;
Ctrl is Cmd on a Mac, and a key without Ctrl is left to a field being
typed in. `showModal` focuses the control that has `autofocus`.

`button` with `:shortcut` (`"Ctrl+K"` or `"/"`, as a dialog's) shows
that shortcut, and does nothing on it itself: the dialog or script the
key opens binds it. After the button's content, and after its
`:icon-end`, come its keys as caps, a `kbd` holding a `kbd` per key,
side by side. The caps are `aria-hidden`; the button
keeps its `:label` as its `aria-label` and carries `aria-keyshortcuts`
instead: `Control+K Meta+K` for Ctrl, since either opens a dialog, and
a key without Ctrl as itself (`"/"` is `/`). The caps show from 48rem
wide, where a keyboard is likely, and not below it, so an icon button on
a phone stays a square; from 48rem an icon button with a shortcut is as
wide as its icon and keys, on one line, at the button's height. On a
Mac, an iPhone or an iPad the Ctrl cap reads «⌘». A shortcut is a key
or Ctrl and a key, the ones a dialog opens on; any other, such as `""`,
`"Ctrl+"` or `"Shift+K"`, cannot be made.

`table` keeps its columns on a wide screen and shows each row as a card
on a narrow one. A column given `:sort KEY` has a header that is a link
to `:sort-href` (a function of the key and `"asc"` or `"desc"`, or a
format string): ascending, or descending when it is sorted ascending
already, with an arrow, and `aria-sort` on the column `:sorted :asc` or
`:desc`. The page sorts the rows; the link reloads it, so sorting works
without JavaScript. On a narrow screen the sortable headers stay, as a
row of links above the cards. `confirm-panel` is the form a `:confirm` operation
shows before it runs. `flash` is a message carried over a redirect.

### 6.1 The board

`board` shows records as cards in columns, one column per state, as in
Asana or GitHub's project boards, and lets a person move a card to
another column.

```lisp
(ui:board (:label "Saker etter status" :action "/saker/flytt"
           :columns (list (list :key "ny" :title "Ny"
                                :cards (list (list :id "itm_1" :title "Eksporten feiler"
                                                   :href "/saker/itm_1"
                                                   :badges (list (ui:badge (:variant :destructive) "Feil"))
                                                   :meta "Kari · 21.10.2026")))
                          (list :key "planlagt" :title "Planlagt" :cards '()))))
```

- **Columns.** Each column is `(:key :title :cards [:count] [:empty])`:
  KEY is the value posted when a card is moved there, TITLE its heading,
  COUNT what the heading shows beside it (the number of cards when
  omitted; a page that shows only some cards gives the whole count, or
  a text such as `"20+"`), EMPTY the text of a column with no cards
  («Ingen»).
- **Cards.** Each card is `(:id :title [:href] [:badges] [:meta])`: ID
  the record's id, TITLE its name, a link to HREF when given, BADGES a
  list of `badge`s, META a line of small text under them.
- **Moving.** With ACTION, every card carries a «Flytt til» menu of the
  other columns. Choosing one posts `card=ID` and `column=KEY` to ACTION,
  as a plain form. With JavaScript, a card can also be dragged to
  another column, with a mouse, or on a touch screen after holding it
  for a moment (so a swipe still scrolls). The card moves at once, and
  the same post is sent through htmx, its answer morphed into the board
  (`hx-target` the closest `.tun-board`, `hx-swap` `outerMorph`), so the
  columns stay scrolled where they were. Escape while dragging puts the
  card back. A board without ACTION shows the cards and moves nothing.
- **Dragging to another column.** Dragged near the left or right edge of
  the columns' box, or of the screen where it cuts the box off, the
  columns scroll: steadily with a mouse; with a finger, held there for a
  moment (350 ms), they scroll one column, then one more each second
  while it is held. The columns do not snap while a card is dragged, and
  snap to a column again after. A finger beside the box, at the screen's
  edge, is over the column at the box's edge, the one showing there.
- **Order within a column.** With `:ordered t` as well as ACTION, the
  order of the cards in a column is the person's to set: the board shows
  each column's cards in the order the page gives them, and every post
  also carries `before`, the id of the card the moved card now sits
  directly before in its column, or empty when it is last there.
  - *Dragging.* A card dragged over a column, its own or another, goes
    directly before the first other card in it whose vertical middle is
    below the pointer, or last when there is none, and a drop posts that
    place: its column and the card below it. A drop where the card
    started posts nothing.
  - *The menu.* Above «Flytt til», a group «Rekkefølge» has «Flytt
    øverst» and «Flytt opp» on a card that is not first in its column,
    and «Flytt ned» and «Flytt nederst» on one that is not last. Each
    posts the card's own column and the `before` that puts it there: the
    first card, the card above, the card two below (empty when the card
    below is the last), and empty. «Flytt til» another column posts
    `before` empty, to the end of that column. A group with no items,
    such as on a card alone in its column, is left out, and the card has
    its menu whenever the menu has any item.
  - *The page* keeps the order: it puts the card directly before
    `before` in COLUMN, or last there when `before` is empty, and refuses
    a `before` that is not another card in COLUMN, such as one from a
    board that is out of date or the moved card itself, as it refuses any
    move. A page that shows only some of a column's cards reads an empty
    `before` as the end of the whole column. `rank-between` (`core.md`
    §2.6) gives a key to sort by for such a place.
  - Without `:ordered`, a post is `card` and `column` alone and a card
    dragged within its own column goes back where it was, as before.
- **The answer.** The page at ACTION answers an htmx request with the
  board alone, as a fragment (§8.1), and any other request with
  `(values 303 PATH)`; a refused move answers the board as it was, with
  the error in MESSAGE. After a move from the keyboard, focus returns to
  the moved card's menu button, in its new column or its new place.
- **Saying where a card went.** A board with ACTION has a status region
  (`role="status"`), visually hidden: clipped to nothing on the screen
  but not `hidden` or `display: none`, so screen readers read it. After a
  move through htmx whose answer has the card somewhere else than before
  it was moved, the board says there:
  «Flyttet «TITLE» til plass N av COUNT i COLUMN.» on an ordered board,
  N counted from the top of the column and COUNT what its heading shows,
  and «Flyttet «TITLE» til COLUMN.» on another. An answer that has the
  card where it was, as a refused move does, says nothing there; its
  MESSAGE says why.
- **MESSAGE.** Nodes shown above the columns, in a live region, such as
  an `error-alert`.
- **Ids.** The ids of the cards and their menus are made from the
  board's `:id` («tun-board» when omitted) and the cards' ids, the same in
  every answer; two boards on one page need an `:id` each.
- **Narrow screens.** The columns stand side by side and the board
  scrolls sideways inside its own box, a column at a time; on a phone
  each column is nearly the screen's width, with the next one showing
  at the edge.
- **Long columns.** A column shows about ten cards (at most 70 % of the
  window's height) and scrolls inside, under its heading and count.
  Dragging a card near the top or bottom of a column scrolls it.
- **Filling the screen.** A board in a page's content, directly or in
  up to two `stack`s, fills the height the page leaves it (§8): its
  columns stretch to that height and their cards scroll inside, so when
  the page loads every column's bottom edge shows, above a 3rem strip of
  page a finger can scroll by. It is at least 20rem high; on a shorter
  screen the page scrolls. A board elsewhere, such as in a card, keeps
  the limits above; on a phone (40rem wide or less) such a column is as
  tall as fits under the app shell's sticky header, and the board leaves
  3rem of page below it.
## 7. The specimen

- `/ui` shows every component: its documentation, its source, and each
  example rendered beside its Lisp. `/ui/NAME` shows one. The specimen
  is public; it holds no data.
- A theme switch on the specimen sets `data-theme` and remembers it in
  the browser.
- `bin/ui-specimen [DIR]` writes the specimen as standalone files (the
  CSS and script inline): `index.html` and `NAME.html` for each
  component.
- `bin/ui-shots [NAME...]` screenshots those files in Chromium at 390
  and 1280 px wide (`--widths` for others, such as 1440 and 1920),
  light and dark, into `.build/ui/shots/`.

## 8. Screens

The generated screens use the components: the page is an `app-shell`,
lists are `table`s, a record is a `summary-list`, an operation is a
form of `field`s with an `error-summary`, a confirmation is a
`confirm-panel`. A client's screen does the same.

- **Filling the screen.** An element marked `data-tun-fill` (a board)
  that is in the content directly or in up to two `stack`s makes the
  content as tall as the screen under the header (the whole height
  beside the sidebar), with 2.5rem below it instead of 4rem. The element
  takes the height the rest leaves, at least 20rem, and each stack on
  the way grows to pass it on. The shell sets `--tun-fill-align:
  stretch` and `--tun-fill-max-height: none` on it, which the board
  uses to stretch its columns and drop their own limit.
- **The page header on a phone.** The title and the actions share one
  row when they fit, centred on it; otherwise the actions go below.
- **The frame.** A staff page is an `app-shell` with the menu, the actor
  and «Logg ut». Its content is at most 72rem wide, 84rem from a
  1440 px window, centred, with more space at the sides the wider the
  window; a page defined with `:width :wide` uses the whole width beside
  the menu, for a board or a wide overview. A client adds components to
  every staff page, after its content, with a method on
  `staff-page-extras`: a dialog with a `:shortcut` (`"/"`, `"Ctrl+K"`)
  opens from anywhere, as a search does.
- **The menu.** First the business's work: the client's own pages in the
  order they are defined, the resources, then the modules' pages and the
  kernel's. Then, under the heading «System», the pages about the system
  rather than the work: those defined with `:group :system` (the
  dashboard's «Jobber», «Feil» and «Logg»), then the kernel's
  «Innstillinger» and «Tilgang». Each entry shows only to those its
  page's policy admits, so a person who is not an admin sees only
  «Tilgang» there. A page for someone not logged in
  (login, setup, a public page) is an `app-shell`
  without the menu. A page with one short form (login, setup) is narrow
  and centred (`:width :narrow`): the form's card, then
  a card that explains it. Every page starts with a `page-header`.
- **Lists.** The generated list is a `table` of at most five columns: the
  record's name (else its id, linked to its page), then its status as a
  `badge`, the records it refers to by their names, its first date, its
  total, and its other inputs. No records is an `empty-state`.
- **A record.** A `page-header` (breadcrumbs, the status as a badge, the
  status operations as buttons, or a `dropdown-menu` when there are more
  than two), a `summary-list` of the fields that have a value, a `table`
  per list of records, and computed JSON in an `accordion`.
- **Forms.** A control per input, chosen by its type: text, e-mail,
  number, date, a `select` or `radios` (four choices or fewer, required)
  for an enum, `checkboxes` for a list of an enum, a `checkbox` for a
  boolean, a `select` of the records an id refers to, a `textarea` for
  long text and JSON, and a `fieldset` per row of a list of records, its
  optional inputs folded away. The description is the hint; an optional
  input says «(valgfritt)». A form with inputs carries `novalidate`, as
  GOV.UK's do: the server checks every submission, and its answer is
  shown in the page, where the browser's own bubble is easy to miss on a
  phone. A refused submission keeps what was typed, puts each field's
  error at the field and lists them in an `error-summary` that links to
  them.
- **Values.** Amounts in øre are shown in kroner (12 450,00 kr), dates as
  DD.MM.YYYY, instants in Norwegian time, stored words such as
  `tilbud_sendt` as «Tilbud sendt», references by the record's name.
- **Modules** build their pages (staff pages, public pages, sections on a
  record) from the components through `TUN.UI`, one of the kernel's
  public packages for modules.
- **A client's pages.** A client builds pages from the same components:
  its package names `TUN.UI` with a local nickname, `(:local-nicknames
  (#:ui #:tun.ui))`, and the interface check allows `TUN.UI`'s external
  symbols beside `TUN`'s. A page is defined with `define-page`:

  ```lisp
  (define-page items-page ("saker" :title "Saker" :icon :list-todo :policy :employee)
      (method path form query)
    ...)
  ```

  `:group :system` puts the page under «System» in the menu, and
  `:width :wide` gives it the whole width.

  1. It serves `/PREFIX` and every path under it to a logged-in person
     the policy admits (`:employee` when omitted); anyone else gets the
     403 page. TITLE and ICON are its menu entry; `:navigation nil` keeps
     it out of the menu.
  2. NAME is a function of the request. METHOD is `:get` or `:post`, PATH
     the parts after the prefix (`/saker/sak_1` gives `("sak_1")`), FORM
     and QUERY the posted and the query parameters as JSON objects.
  3. It returns `(values STATUS TITLE BODY)`, BODY a list of components
     shown under a page header with TITLE, and may add a fourth value, a
     plist of the header's `:description`, `:actions` and
     `:breadcrumbs`. `(values 303 PATH)` sends the browser to PATH, as a
     successful post should.
  4. `web-call TOOL ARGUMENTS` calls an operation as the logged-in
     person, through the execution path. It returns the result, or the
     error document and its code; `error-alert` shows that document.
     An operation error the page does not catch is shown as that alert,
     with the code's status. `timestamp-text` writes an instant in
     Norwegian time.
  5. Evaluating the definition again, in a running server too, replaces
     the page; another definition with the same prefix is refused, as
     two modules' pages are.
  6. A page answers an htmx request for part of a page as §8.1 says.
  7. `:remembers '("prosjekt" "status")`, a list of query keys, makes
     the page remember them for each account, so a person who leaves a
     list filtered finds it so again, on any device. A GET of the page's
     own path (`/saker`, not `/saker/sak_1`) whose query has any of the
     keys saves their values for the signed-in account, in place of what
     was saved: a key absent or empty is saved as cleared. A GET of the
     own path with none of the keys, while the account has a value saved,
     is answered 303 to the path with the saved keys that have a value,
     in the order of `:remembers`, after the query parameters it had
     (`/saker?status=open`, not `/saker?prosjekt=&status=open`). A
     boosted request follows it, so the address bar shows the saved
     query, and Back returns to the page before. A link that clears a
     page's filters names one of its keys (`/saker?prosjekt=`). A POST
     and an htmx request for part of a page neither save nor are sent
     anywhere. A preload (§4.1) that would save is declined, so the
     click that follows it saves. What is saved is kept with the
     account's name, in an internal entity. `:remembers` that is not a
     list of strings is refused when the page is defined.
- **Home.** `/` leads to the first resource with record pages, else the
  first resource, else the first page a module or client defines that
  the person may see, in the menu's order.

### 8.1 Answering htmx

- `(htmx-request-p)` is true while a page answers a request htmx sent
  for part of a page: `HX-Request-Type: partial`. A boosted request
  (§4.1), a page fetched for Back and an `HX-Location` are `full`: they
  want the whole page, and get it.
- `(values STATUS :fragment BODY)` answers BODY, a list of components,
  alone: no document, no shell, no page header. A page answers so when
  `(htmx-request-p)`; any other request should get a whole page.
- `(values 303 PATH)` to an htmx request for part of a page is answered
  200 with `HX-Location: PATH`, so htmx loads PATH as a boosted link
  would. A boosted request gets the 303 itself.
- A fourth value may hold `:trigger NAME`: the answer then carries
  `HX-Trigger: NAME`, and htmx fires the event NAME on the element that
  asked, for another part of the page to listen to (`hx-trigger="NAME
  from:body"`).
- The markup that asks is ordinary: a component's `:attributes`, or a
  page's own elements, with `hx-post`, `hx-target`, `hx-swap` and the
  other attributes §5 allows. It is a form or a link that works without
  htmx too.
## 9. Not yet

- A client's theme (`define-theme`) beyond overriding tokens in the
  `client` layer.
- Charts, a date picker beyond the browser's own, a combobox with
  search.
- htmx's own extensions (server-sent events, the head merge,
  morphing).
- Path patterns with typed parameters for pages (`/saker/:item`), and
  links that name their page (`docs/roadmap.md`).

## 10. Evidence

- `tests/ui-tests.lisp`: every component has its documentation, source
  and examples; every example renders, and renders the same in
  extension output (only allowed markup); every selector is scoped to
  its component; the stylesheet, the script and htmx are served with
  their hash and cache headers; pages have the viewport tag and htmx's
  configuration; the allowed htmx attributes pass extension output, with
  `:inherited`, and others (`hx-on`, `data-hx-on`, `hx-headers`,
  `hx-status`, an unknown modifier, a `javascript:` `hx-get`) do not.
- `tests/ui-data-tests.lisp`: the board's columns, counts, cards, move
  menus and their forms, and a board without an action; an ordered
  board's `before`, its «Rekkefølge» items and what each posts, its
  status region, and a board without `:ordered` posting as before.
- `tests/rank-tests.lisp`: `rank-between` (`core.md` §2.6).
- `checks/showcase/checks/`: dragging a card to another column with a
  mouse and on a phone (`board-drag-*`), a board filling a phone
  (`board-fills-a-phone`), and ordering within a column with a mouse, by
  touch and from the keyboard, with what is said and a refused move
  (`board-order-*`), and a board without `:ordered` posting as before.
- `tests/web-tests.lisp`: a page defined with `define-page` answers
  its path and the paths under it, posts, redirects, refuses a role its
  policy does not admit, shows an uncaught operation error, and is
  replaced when defined again; `/` leads to a page when there is no
  resource; a staff page is boosted and a guest page is not; a page
  answers a fragment, an `HX-Location` for a 303 to htmx, `HX-Trigger`,
  and `HX-Redirect` for stale assets.
- `tests/web-app-tests.lisp`: the `:web-app` options and icons are
  checked; the manifest, the icons, the offline page and the service
  worker are served without a login, with their types and cache
  headers; every page's head carries the tags; the worker keeps the
  current assets and the offline page and nothing else; without
  `:web-app` there is no manifest and the worker removes itself; a
  client's page cannot take the paths. `push.md` §10 has the evidence
  for push notifications.
- `bin/ui-shots` and a review of the screenshots before a component is
  accepted.
