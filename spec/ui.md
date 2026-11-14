# The design system

Status: v1, 2026-10-13; a client's pages (§8), 2026-10-15; htmx 4 (§4.1,
§8.1) and the board (§6.1), 2026-10-21; installing as an app (§4.2),
2026-10-22; ordering a board's cards within a column (§6.1), 2026-10-26,
core 1.18.0; push notifications in the service worker and `push-switch`
(`push.md`), 2026-10-26, core 1.19.0; `file-input` and `attachments`
(`files.md`), 2026-10-26, core 1.20.0; pages in the person's language,
amounts and dates by its formats (`i18n.md`), 2026-10-27, core 2.0.0;
`line-chart` and `sparkline` (§6), the chart token (§3) and
`preserveAspectRatio` in extension output (§5), 2026-11-02, core 2.6.0;
`graph`, nodes and the edges between them (§6.3), 2026-11-10, core
2.18.0; its list for narrow boxes, 2026-11-10, core 2.20.0; the home
page a client names (§8, «Home»), 2026-11-11, core 2.21.0; the loading
sign (§4.1), 2026-11-11, core 2.22.0; the look and the states of the
components (§2.1, §3, §6), 2026-11-11, core 2.25.0; the dialog as a
sheet on a phone, the motion of what opens, `confirm-dialog` and the
flash as a toast (§2.1, §3, §6), 2026-11-11, core 2.26.0; the page
header's row and its «more» menu, `section-links`, the record's facts by
spacing, `tabs` on the page's ground, the shell and the theme colours on
the chrome, and no description in Tun's own pages (§4.2, §6, §8),
2026-11-11, core 2.27.0; a list's toolbar, `list-toolbar`, its filters in
the address, a repeated query key and the generated list's filters (§6,
§8), 2026-11-12, core 2.28.0; every table's rows on a phone, in a box
that scrolls sideways, a row that leads somewhere pressed as one target,
and a page title's long word hyphenated (§2.1, §6, §8), 2026-11-12, core
2.29.0; the date, time and money fields, the calendar, and a period as a
filter of a list (§6, §8, §9), 2026-11-12, core 2.30.0; one search for
the whole application, its rule, `search-results`, `search-dialog` and
the dialog's `:size :large` (§6, §6.4, §8, §9), 2026-11-12, core 2.31.0;
a summary list's label column, a section's `:meta`, `note`, the marks
of a result found by its second line, and the specimen's theme switch
(§6, §6.4, §7, §8), 2026-11-12, core 2.32.0; `choice-input`,
`choice-options`, a list's `:choice` filter, answering and reading a
choice, `query-address`, and the specimen's options (§6, §7, §8, §9),
2026-11-12, core 2.34.0; the generated pages choosing a record by
typing, `/choices/ENTITY`, and the specimen's choice answered by
`choice-answer` (§7, §8, §9), 2026-11-12, core 2.35.0; a form's alert
naming its fields by their labels, Enter saving in a form with an asked
choice, «must be chosen», and `record-choice`, a module's shape of its
records' choice (§2.1, §6, §8, §9), 2026-11-12, core 2.36.0.
How every Tun page looks and behaves: the tokens, the components that
are built from them, the specimen that shows them, and the rules a
component follows. The
generated screens (`ui.lisp`, `access.lisp`) and a client's own screens
are built from these components and nothing else.

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

The look of the grounds, the edges, the states and the motion (§2.1,
§3) is Tun's own, after its owner's rules for an admin
application of 2026-11-10 and 2026-11-11; the token names stay shadcn's.

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
- **In the person's language.** Copy is written in English and shown in
  the tenant's language (`i18n.md` §2.4, §3), Norwegian as bokmål; code
  identifiers and class names are English.
- **Plain CSS.** No build step, no Tailwind, no preprocessor. Modern CSS
  only: custom properties, `@layer`, nesting, `:has()`, `color-mix()`,
  container queries.
- **Tokens decide.** A component's CSS uses tokens (§3) for every colour,
  size, radius, shadow and duration. A literal value needs a reason in a
  comment.

### 2.1 The look

- **Three grounds.** The page (`--background`), the panels on it
  (`--card`, `--popover`: cards, dialogs, menus) and the chrome around
  it (`--chrome`, its edge `--chrome-border`): the sidebar, the phone's
  top bar and its menu, a strip of tabs in the shell. In the light the
  page and the panels are white and the chrome grey; in the dark the page
  and the panels share one ground and the chrome is darker. A field
  stands on `--input-background`.
- **One thin edge.** Controls and panels have a 1px edge, `--border`;
  `--border-strong` is the edge under a pointer and of what is chosen. A
  field, a box to tick and a switch, whose edge is all there is of them,
  take `--input`, 3:1 on the page and the chrome (WCAG 1.4.11). No edge
  is wider than 1px but a mark (the tick of a checkbox, a graph node's
  tone, the confirm panel's «!»).
- **Two radii.** A control's, `--radius-md` (0.5rem), and a panel's,
  `--radius-lg` and `--radius-xl` (0.75rem: cards, dialogs, menus and
  popovers); a pill, a switch and an avatar are fully round
  (`--radius-full`). A part inside a padded control or menu (a menu's
  item, a segmented tab, a key cap, a checkbox) takes `--radius-sm`, the
  control's less its inset (0.375rem). No box with an edge has a square
  corner; the joined sides of a button group are the one exception.
- **Text.** The text colour is `#171717`, `#ededed` in the dark. Running
  text (a card's, a dialog's, a summary list's, a page's own) is 0.875rem
  on a 1.375rem line (`--text-running`); a control's text 0.875rem on
  1.25rem (`--text-sm`); meta text 0.75rem on 1rem (`--text-xs`); a field
  keeps 1rem on a coarse pointer (§2). Quieter text is
  `--muted-foreground`, the text colour at 72 %, never a second grey: at
  least 6.5:1 on every ground in both schemes. No component writes text
  in capitals (`text-transform: uppercase`) or letter-spaced
  (`letter-spacing` above 0), the menu's «System» heading included.
- **Ink and the accent.** The primary button is ink: the text colour as
  its fill. The accent, `--highlight` (`#005ff2`, `#47a8ff` in the
  dark), is only for focus (`--ring`), for what is on (a switch that is
  on, a checked checkbox or radio), for what is selected (the selection
  of text) and for where a dragged thing will drop (a board's column, a
  file field).
- **Focus.** A focused control shows `--focus-ring`, a 2px gap in the
  ground's colour and a 2px ring in the accent (`0 0 0 2px GROUND, 0 0 0
  4px ACCENT`), on every ground: the chrome sets the gap in its own
  colour. A row or a strip of tabs that fills its box draws its ring
  inside it (`--focus-ring-inset`, 2px of the accent), where a ring
  outside would be cut off. A link in running text has the browser's
  outline in the same shape: 2px of the accent, 2px off.
- **Panels.** A card, a stat and a table on a phone have the edge
  and `--shadow-panel` (`0 1px 2px rgb(0 0 0 / .04), 0 2px 8px rgb(0 0 0
  / .03)` in the light, none in the dark). A group inside a panel stands
  on `--soft` (the text colour at 5 %) rather than a frame of its own: no
  component draws a frame in a frame in its own markup.
- **Pressed.** What a person taps answers while it is pressed
  (`:active`), at once, with no transition into it: a button, a card
  that is a link, a table row that is a link, a `nav-list` entry, a tab,
  a `dropdown-menu` item, a `combobox` option, a sortable header, a
  pagination link, an accordion's summary, a link (`link`, a
  breadcrumb, a summary list's action, the links of `error-summary`, of
  an `alert` and of `form-actions`), a `board` card and a `graph` node that are links, and
  an attachment's tile. Every component with a style under a pointer has
  one while pressed, but `tooltip`, which shows on hover. A checkbox, a
  radio, a switch and a field answer with the browser's own change of
  state and their focus ring. The tint is `--pressed`
  (the text colour at 8 %, 10 % in the dark) over the control's own
  ground; the primary button's fill turns lighter instead.
- **Hover only where a pointer hovers.** Every `:hover` style is inside
  `@media (hover: hover)`, so a phone never keeps one after a tap. Under
  a pointer a control takes `--accent` (black at 5 %, white at 6 % in the
  dark) over its ground.
- **Choosing moves nothing.** A chosen or current item (the chosen tab,
  the current `nav-list` entry, the current page of `pagination`, a
  pressed toggle button, the active option of a `combobox` or a menu) has
  the font weight, size, padding and edge width of its siblings, and
  shows that it is chosen by its fill, its frame or a mark.
- **Motion.** Changes of state ease with `--ease` over `--duration-fast`
  or `--duration`; `--duration-sheet` and `--duration-close` are for
  what opens as a sheet and what closes. Every duration is 0 under
  `prefers-reduced-motion`. A loop (a spinner, the loading sign, an
  agent's pulse) keeps an even easing of its own.
- **What opens moves into place.** A dialog, a menu, a combobox's list,
  a tooltip and a flash move in as they open and out as they close, and
  only by `opacity` and `translate`, never
  `transform`, `scale` or a size (a script that places a menu owns its
  `transform` and inline position). A sheet slides up over
  `--duration-sheet`; the rest rise a few pixels and fade in over
  `--duration` or `--duration-fast`; everything leaves over
  `--duration-close`. The opening and leaving are CSS's own for the top
  layer (`@starting-style`, `transition-behavior: allow-discrete` with
  `display` and `overlay`), so no script times them, and a browser
  without them opens and closes at once. The duration follows the state
  it goes to: the open state names the opening duration, the closed
  state `--duration-close`.
- **The dim only gets darker.** The page behind a modal dialog dims in
  one fade of its `::backdrop`, in `--overlay`, from nothing to whole
  while the dialog opens and back while it closes; there is no second
  layer to cross it and no blur.

## 3. Tokens

Tokens are CSS custom properties on `:root`, in the layer `tokens`. The
colour names are shadcn's, so a shadcn theme fits; Tun adds status
colours, sizes and motion.

- **Colour:** `--background`, `--foreground`, `--card`,
  `--card-foreground`, `--popover`, `--popover-foreground`, `--primary`,
  `--primary-foreground`, `--secondary`, `--secondary-foreground`,
  `--muted`, `--muted-foreground`, `--accent`, `--accent-foreground`,
  `--destructive`, `--destructive-foreground`, `--border`, `--input`,
  `--ring`. Tun adds `--chrome` and `--chrome-border` (the chrome's
  ground and edge), `--input-background` (a field's ground),
  `--border-strong`, `--pressed`, `--soft`, and `--highlight`,
  `--highlight-foreground` and `--highlight-soft` (the accent, text on
  it, and a tint of it), and `--overlay`, the dim behind a modal dialog
  (black at 40 % in the light, `#00000066`, and at 54 % in the dark,
  `#0000008a`). `--accent` keeps shadcn's meaning, the ground under a
  pointer; `--ring` is `--highlight`.

  | Token | Light | Dark |
  |---|---|---|
  | `--background`, `--card`, `--popover` | `#ffffff` | `#19191c` |
  | `--chrome` | `#f6f6f7` | `#111113` |
  | `--chrome-border` | `#0000000f` | `#ffffff12` |
  | `--input-background` | `#ffffff` | `#141417` |
  | `--foreground` | `#171717` | `#ededed` |
  | `--muted-foreground` | the text colour at 72 % | the same |
  | `--primary` | `#171717` | `#ededed` |
  | `--secondary`, `--muted` | `#f3f3f4` | `#222226` |
  | `--accent` | `#0000000d` | `#ffffff0f` |
  | `--pressed` | the text colour at 8 % | at 10 % |
  | `--soft` | the text colour at 5 % | the same |
  | `--border` | `#0000001f` | `#ffffff24` |
  | `--border-strong` | the text colour at 26 % | at 30 % |
  | `--input` | the text colour at 50 % | at 40 % |
  | `--highlight` | `#005ff2` | `#47a8ff` |
  | `--overlay` | `#00000066` | `#0000008a` |
- **Status:** for each of `info`, `success`, `warning` and `destructive`:
  `--STATUS` (icons, borders, text on the soft background),
  `--STATUS-foreground` (text on `--STATUS`) and `--STATUS-soft` (a tinted
  background). `--STATUS` is at least 4.5:1 on `--STATUS-soft` and on the
  page, and `--STATUS-foreground` on `--STATUS`, in both schemes: info
  `#005ff2` on `#f0f7ff` (`#47a8ff` on `#06193a`), success `#107d32` on
  `#ecf6ef` (`#00ac3a` on `#0b2615`), warning `#aa4d00` on `#fff4e5`
  (`#ffae00` on `#2e1d05`), destructive `#d8001b` on `#ffeeef`
  (`#ff565f` on `#330a11`).
- **Charts:** `--chart-1`, the colour of a chart's line, blue:
  `#2a78d6` on the light card (4.4:1 against white) and `#3987e5` on the
  dark one (4.8:1 against `#19191c`), above the 3:1 WCAG asks of
  a graphic. It is shadcn's token name, so a shadcn theme sets it too.
- **Type:** `--font-sans`, `--font-mono`; `--text-xs`, `--text-sm`,
  `--text-running`, `--text-base`, `--text-lg`, `--text-xl`, `--text-2xl`, `--text-3xl`,
  each with `--text-SIZE--line-height`; `--font-weight-normal`,
  `-medium`, `-semibold`, `-bold`.
- **Space:** `--spacing` (0.25rem); a component writes
  `calc(var(--spacing) * N)` as Tailwind's `N` would be.
- **Radius:** `--radius` and `--radius-sm`, `-md`, `-lg`, `-xl`, `-full`:
  `-md` 0.5rem, `-lg`, `-xl` and `--radius` 0.75rem, `-sm` 0.375rem (§2.1).
- **Shadow:** `--shadow-xs`, `-sm`, `-md`, `-lg`, and `--shadow-panel`.
- **Controls:** `--control-height` (2.25rem; 2.75rem on a coarse
  pointer), `--control-height-sm`, `--control-height-lg`,
  `--control-font-size` (0.875rem; 1rem on a coarse pointer).
- **Focus:** `--focus-ring`, the box-shadow of a focused control,
  `0 0 0 2px var(--background), 0 0 0 4px var(--ring)`, and
  `--focus-ring-inset`, `inset 0 0 0 2px var(--ring)`.
- **Motion:** `--ease` `cubic-bezier(0.16, 1, 0.3, 1)`, `--duration-fast`
  150ms, `--duration` 200ms, `--duration-sheet` 280ms, `--duration-close`
  160ms; all 0 under `prefers-reduced-motion`.
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
- **The browser holds pages to that.** Every answer to the browser, a
  page, a part of one, a redirect or an error, carries
  `Content-Security-Policy:`
  `default-src 'self'; script-src 'self'; style-src 'self';`
  `style-src-attr 'unsafe-inline'; img-src 'self' blob:;`
  `object-src 'none'; base-uri 'none';`
  `frame-ancestors 'none'; form-action 'self' ORIGINS`.
  The browser then runs only Tun's own script files, never code written
  in the page or in a string (`eval`, `Function`), takes style sheets only
  from Tun's, shows images only from the server and from a file
  chosen for upload (`blob:`), and lets no other site show a page in a
  frame. A `style` attribute is allowed: it runs nothing, and an email,
  whose styles are all attributes, is shown in a frame that inherits the
  policy (the showcase's `/mail`). Tun's own markup still has none, and a
  client's output cannot carry one (§5).
- ORIGINS are the origins of the identity providers' authorization
  endpoints (`auth.md` §3.5), such as `https://accounts.google.com`: a
  sign-in form posts to the server, which sends the browser on to the
  provider, and browsers hold that redirect to `form-action` too. They
  also hold the sites the client names in `define-application` for a
  form that sends the browser on to another system, such as a sign-in at
  a broker: `(:form-sites "https://sim.logonvalidation.net"
  "https://developer.saxobank.com")`. Every site of the form's redirect
  chain must be named, not just the first. Each is an
  `https://` origin with a lower-case host and no path (`http://` only
  for `127.0.0.1` and `localhost`); anything else is refused when the
  client is compiled.
- A file keeps its own, stricter policy (`files.md` §5.3), and `/ui`, the
  specimen, has the same as a page.
- An image from another site is not shown: a component that takes an
  image's address, such as the avatar's `:src`, takes one on the server.
- Every page has `<meta name="viewport" content="width=device-width,
  initial-scale=1">`.
- The components' script holds no copy: a text it shows is in the markup
  the server rendered, in the page's language (`i18n.md` §3.6).
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
- **The loading sign.** A staff page shows that it is working when a
  person's htmx request has not been answered after 300 ms: a thin bar
  across the top of the window, 3px high in `--primary` over a track of
  it at 20 %, in front of everything (`--z-toast`), its short part
  sliding across. A page that answers within 300 ms shows nothing, so
  fast pages never flash. Under `prefers-reduced-motion` the bar stands
  still, as stripes over the whole width.
  - **Which requests.** A request for the whole page (a boosted link or
    form, Back, an `HX-Location`) and a request for a part of a page a
    click or a submission started (a board's move). Not a part that
    loads by itself (`hx-trigger="load"`, `revealed`, polling), and not
    a preload, which is a plain fetch htmx never sees; a click on a link
    whose preload is still loading waits for it, and shows the sign if
    that takes longer than 300 ms.
  - **When it goes.** When the last such request ends, however it ends:
    swapped, refused (a 4xx or 5xx page is swapped in too), failed on
    the network, or cancelled (`htmx:abort` on the element that asked);
    and when the browser shows a page from its cache (`pageshow` with
    `persisted`). htmx 4 cancels no request when a person follows
    another link or presses Back while one is under way: the earlier
    request still ends, and is swapped in when it does, so the sign stays
    until then, and goes when it has. A page swapped in meanwhile, such
    as the one Back restores, keeps the bar showing; its region is not
    made to say «Loading…» again.
  - **For a screen reader.** The shell holds a polite live region
    (`role="status"`, visually hidden), empty; when the bar shows, its
    text becomes «Loading…» («Laster…»), written by the server in the
    page's language, once for that wait, and it is emptied when the bar
    goes. The bar itself is `aria-hidden`.
  - **Where.** The bar, with `hidden`, and the region are in every
    `app-shell`. The components' script shows and hides them, found by
    `data-tun-loading` and `data-tun-loading-status`, from listeners on
    `document` for `htmx:before:request` and `htmx:finally:request`. Its
    look is in the stylesheet: no style attribute and no inline script,
    within the page's policy. Without JavaScript the bar stays hidden,
    and the browser's own loading sign is what a person gets.

### 4.2 Installing as an app

A client that declares `(:web-app ...)` in `define-application` can be
installed as an app on a phone or a computer (a progressive web app).
Without it, no page links a manifest and nothing is installed.

```lisp
(:web-app :short-name "Saker"
          :theme-color "#f6f6f7" :dark-theme-color "#111113"
          :background-color "#ffffff"
          :icons "icons/")
```

- **The options.** `:icons` is required: a directory, relative to the
  file that holds `define-application`. `:short-name`, the name under
  the icon, is at most 12 characters, and defaults to the application's
  title. The colours are `#rgb` or `#rrggbb`. The theme colours are the
  browser's bar in light and dark mode, and they default to the chrome's
  ground (`--chrome`), `#f6f6f7` and `#111113`, the ground of the shell's
  top bar, so the phone's status bar and the top bar are one surface.
  `:background-color` is
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
  `short_name`, `display` `standalone`, `lang` the tenant's language,
  `theme_color` (the
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
  in the tenant's language: «You are offline» («Du er frakoblet»), with
  «Try again» («Prøv igjen»), which loads the address again.
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
  (:doc "A button for an action, or a link that looks like one.")
  (:source "Basecoat button (Vega)")
  (:css ".tun-button { ... }")
  (:examples ("Variants" (button () "Save") (button (:variant :outline) "Cancel")))
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
  screen can use any component. Its SVG is shapes only (`svg`, `g`,
  `path`, `circle`, `ellipse`, `line`, `polyline`, `polygon`, `rect`) with
  their geometry and paint, and `preserveAspectRatio`, which only says how
  a drawing fits its box; nothing in it loads or runs. That output may
  carry these htmx attributes, with or without `data-` and with the
  modifiers `:inherited` and `:append`: `hx-get`, `hx-post`,
  `hx-target`, `hx-swap`, `hx-trigger`, `hx-select`,
  `hx-select-oob`, `hx-swap-oob`, `hx-push-url`, `hx-replace-url`,
  `hx-indicator`, `hx-include`, `hx-vals`, `hx-confirm`, `hx-boost`,
  `hx-disable`, `hx-sync`, `hx-preserve`, `hx-validate`. Any other `hx-`
  or `data-hx-` attribute (`hx-on`, `hx-headers`, `hx-config`,
  `hx-status`, …) is left out.
  An attribute that is followed or fetched (`href`, `src`, `action`,
  `formaction`, `hx-get`, `hx-post`) holds a path on the same site, a
  `#` fragment or an http(s) URL, and `href` may also hold a `mailto:`
  address, its scheme in any case, as `http(s)`; with any other value it
  is left out. A path on the same site
  starts with one `/`, not with `//` or `/\`, and no value holds a tab,
  a line break or another control character, since a browser reads `\` as `/`
  and drops tabs and line breaks from a URL (`/\host` and `/⇥/host` go to
  `host`).
- **Documented.** `:doc` (English, one or two sentences on when to use
  it), `:source` (what it was converted from, §1) and at least one
  example are required. Examples are ordinary calls; the specimen shows
  each one rendered, in the current language, and its source. A text a
  component writes itself, such as a default label, is looked up
  (`i18n.md` §3.1).
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
| Actions (`actions`) | `button`, `icon`, `button-group`, `link`, `kbd`, `badge`, `avatar` |
| Forms (`forms`, `fields`, `choice`, `push`), GOV.UK behaviour | `field`, `text-input`, `combobox`, `choice-input`, `choice-options`, `textarea`, `select`, `checkbox`, `checkboxes`, `radios`, `switch`, `fieldset`, `input-group`, `error-summary`, `form-actions`, `push-switch` (`push.md` §2.1), `file-input`, `date-input`, `time-input`, `money-input` |
| Data (`data`, `toolbar`, `board`, `files`, `charts`, `markdown`, `graph`, `search`) | `table`, `list-toolbar`, `summary-list`, `card`, `stat`, `empty-state`, `pagination`, `timeline`, `code-block`, `board`, `attachments`, `line-chart`, `sparkline`, `markdown`, `graph`, `search-results`, `search-dialog` |
| Feedback (`feedback`) | `alert`, `flash`, `confirm-panel`, `progress`, `spinner`, `skeleton` |
| Interaction (`interaction`) | `dialog`, `confirm-dialog`, `dropdown-menu`, `tooltip`, `accordion`, `tabs` |
| Layout and navigation (`layout`) | `app-shell`, `page-header`, `section`, `section-links`, `note`, `breadcrumbs`, `nav-list`, `stack`, `cluster`, `grid` |

`file-input` and `attachments`, a record's files, are specified in
`files.md` §6, `markdown`, text written in Markdown, in §6.2,
`graph`, nodes and the edges between them, in §6.3, and `search-results`
and `search-dialog`, the application's one search, in §6.4.

`combobox` is a text field that finds one of its `:options`, texts, as
one types. Focusing or tapping it opens a list of every option under it;
typing narrows the list to the options holding the text, ignoring case,
anywhere in the option, and says «No match» when none does. A tap, a
click, or the arrow keys and Enter pick an option: the field holds its
text and the list closes, as it does on Escape and when the field loses
focus. The list shows over the page, under the field (or above it
when there is more room there), so a card or a dialog around the field
never cuts it off. The field is `role=combobox` with `aria-expanded`,
`aria-controls` and `aria-activedescendant`, its list a `listbox` of
`option`s with `aria-selected`; it takes `:hint`, `:error`, `:value`,
`:placeholder` and `:required` as `text-input` does. The value posted is
the text in the field. With `:strict t` the submit buttons of its form
(inside it, or naming it with `form`) are disabled until the field holds
exactly one option, and enabled again as soon as it does; the server
still checks the value. `:button`, such as the form's submit button,
stands at the end of the field's row. Without the script the field is a text input
with the browser's own list of the options (`<datalist>`), and nothing
is disabled. To choose a record and send its id, the form's field is
`choice-input` (below); `combobox` stays the text field whose answer is
the text.

`choice-input` chooses one record among many by typing and posts its
value, an id, under NAME, showing the chosen record's text:

```lisp
(choice-input (:label "Customer" :name "customer_id" :value "cus_12"
               :options '(("cus_12" "Kari Nordmann") ("cus_31" "Bjørn Åsen"))
               :source "/orders/customers"))
```

- **The options.** OPTIONS are `(VALUE TEXT)` pairs, as `select` takes
  them. Without SOURCE they are every choice and come with the page (a
  few dozen at most); typing narrows them in the browser by the search's
  rule (§6.4) as far as it applies to texts alone: every word typed,
  folded, a part of the option's text, in any order, kept in the order
  given. With SOURCE, a path on the site, the options are asked for as
  one types, and OPTIONS hold only those the page knows now: the chosen
  one, and the matches of a find step (below). VALUE is the chosen value,
  its text the option's of that value; a VALUE not among OPTIONS is shown
  as nothing chosen.
- **The value.** One element posts the value: a `select` named NAME (its
  id the field's, «Choose» («Velg»), or PLACEHOLDER, its empty first
  option, then OPTIONS, VALUE selected). Where scripts run the script
  hides it (`hidden`, so it still posts) and sets it; a chosen asked
  option the select does not hold is added to it as an `option`. The page
  checks what is posted with `read-choice` (below), the same way whether
  scripts ran or not.
- **The field where scripts run.** A button that reads as a field (the
  control's look, §2.1, its height, a chevron at the end) shows the
  chosen option's text, or PLACEHOLDER («Choose») muted. It is named by
  LABEL and the text (`aria-labelledby`), carries `aria-haspopup="dialog"`,
  `aria-expanded` and the hint and error (`aria-describedby`,
  `aria-invalid`); the field's label is given to it (`for`). While an
  option is chosen a clear button, «×» («Clear LABEL», «Fjern LABEL»
  to a screen reader), at least 2rem wide (the control's height
  on a coarse pointer), stands at the end inside the field: it empties
  the value, shows PLACEHOLDER, fires `change` on the select and gives the
  focus to the field's button.
- **The list.** The button opens a popover (`popover="auto"`,
  `role="dialog"` named LABEL) holding a text field and the options. The
  text field is `role="combobox"` with `aria-expanded="true"`,
  `aria-controls` the list, `aria-autocomplete="list"` and
  `aria-activedescendant` the active option, `autocomplete="off"`; it is
  no field of the form (`form` names no form), so it never posts. The
  list is `choice-options`: a `listbox` of `option`s. Opening puts the
  focus in the text field, empty, the chosen option active and in sight.
  Typing narrows (or asks, below) and makes the first option active.
- **The keys.** ↓ and ↑ move the active option (`aria-selected="true"`),
  going round at the ends; Home and End, while an option is active, go to
  the first and the last; Enter chooses the active option, else the
  first, and an Enter typed before the answer for what the field holds
  has come waits for it and chooses its first; Escape closes the list
  without choosing. A tap or a click on an option chooses it. Choosing
  sets the value, shows its text in the button, closes the list, gives the
  focus to the button and fires `change` on the select. Escape, a press
  outside and the close button close it, the focus back on the button.
- **The look of an option.** At least 2.25rem high, 2.75rem on a coarse
  pointer, the text wrapping. The active option has the ground of an
  option under a pointer (`--accent`) and the frame of what is chosen, 1px
  of `--border-strong` inside it, at the weight, size and padding of the
  others; the chosen option has a check mark at its end; pressed it takes
  `--pressed` at once; under a pointer `--accent` where a pointer
  hovers. «Choosing moves nothing» (§2.1).
- **Asking.** With SOURCE, the text field carries `hx-get=SOURCE`, name
  `q`, `hx-trigger="input changed delay:150ms, tun-choice-ask"`,
  `hx-target` the list's box, `hx-swap innerHTML` and
  `hx-sync="this:replace"`: htmx waits for a pause of 150 ms after the
  last key and drops a request a newer one replaces. The list asks once
  when it first opens, for an empty text (`tun-choice-ask`). An answer
  whose text (`data-tun-choice-query`) is not what the field holds now is
  not shown; an answer that fails shows «The choices could not be loaded.
  Try again.» («Valgene kunne ikke hentes. Prøv igjen.») in the list.
  SOURCE answers under the authority of the person signed in (it is a
  page of the client's, `define-page`, with its policy), with
  `choice-answer` (below).
- **Where it opens.** From 40rem of the window: under the field, the text
  field first, as wide as the field and at least 18rem, inside the
  window; when there is less room under the field than its list needs and
  more above it, above the field, the text field last, next to the field.
  It rises 0.25rem and fades in over `--duration-fast`, and sinks and
  fades over `--duration-close`. The list scrolls in its own box, at most
  18rem high. Below 40rem: a floating sheet, as a filter's popover is
  (`list-toolbar`), at the bottom of the part of the window a keyboard
  leaves (`--tun-visual-bottom`, which the script writes while it is open
  as it does for a dialog), 0.75rem from the window's sides and above the
  bottom's safe area, every corner `--radius-xl`, over the `--overlay`
  dim, headed by LABEL and a close button, then the text field, then the
  list, `min(24rem, the visible window less 2rem)` high from the moment it
  opens, so the text field never moves as the options change; it rises
  from below over `--duration`. So at 320, 360 and 390 px the text field
  and the list stand above the keyboard.
- **Without JavaScript.** The select is the field. With SOURCE, a text
  field «Find» («Finn») named `NAME-find` and a «Find» button (`name
  tun-find`, value NAME, `formnovalidate`) stand under it: the form posts,
  the page sees the find step with `(choice-find FORM NAME)`, which gives
  the text typed, and shows the form again, nothing saved, with `:find`
  that text and OPTIONS the chosen one and the matches (`choice-matches`);
  the select then holds them, and a line under the find field says
  «3 found» («3 treff»), or «Nothing matches «TEXT»» («Ingen treff på
  «TEXT»»). Where
  scripts run the find field and its button are hidden and taken out of
  the form (a `form` naming no form), so they never post.
- **Enter saves.** A browser presses a form's first submit button when
  Enter is pressed in one of its text fields, and the «Find» button
  stands before the form's own. So right before it the field puts a
  submit button of its own with no name, out of sight (clipped to
  nothing, as a visually hidden label is, since some browsers do not
  press a default button that is `display: none`), out of the tab order
  (`tabindex="-1"`) and away from a screen reader (`aria-hidden`): it is
  the form's first, and Enter in any text field of the form, the find
  field too, posts the form as its own submit button does when it has
  no name, so it saves. Pressing «Find» still finds. Where scripts run
  it is taken out of the form with the find step, so Enter is as it was.
  A form whose submit button sends a name or a `formaction` of its own
  does not get that name from Enter in a form with an asked choice; such
  a form puts a submit button of its own first.
- `:hint`, `:error`, `:required`, `:optional`, `:disabled`,
  `:label-hidden` and `:id` are `select`'s.

`choice-options` is the list of a choice: `(choice-options (:query TEXT
:options OPTIONS :more N :value VALUE))`, a `ul` (`role="listbox"`,
`data-tun-choice-query` TEXT) of an `li` (`role="option"`,
`data-value`) per option, the one of VALUE with its check mark; then,
with N above 0, a line that is no option, «12 more. Type to narrow them.»
(«12 til. Skriv for å snevre inn.»); with no options, «No match»
(«Ingen treff»). It is what SOURCE answers.

**Answering a choice.** Three functions in `TUN`:

- `(choice-matches TEXT ROWS &key value text names texts identifiers
  keep (limit 20))` answers the options of ROWS for TEXT and how many
  more match: two values, a list of `(VALUE TEXT)` and a count. ROWS are
  records, JSON objects or property lists in the order the page wants
  them (by name, say); VALUE and TEXT are functions of a row (VALUE by
  default its id, as `search-among`'s); NAMES (by default its TEXT),
  TEXTS and IDENTIFIERS are `search-match`'s (§6.4), so a choice finds
  what the search finds: «bjorn ase» finds «Bjørn Åsen». A blank TEXT
  matches every row KEEP keeps, in ROWS' order; any other the rows that
  match, best score first and in ROWS' order among equals. At most LIMIT
  are answered; the count is the rest.
- `(choice-answer QUERY ROWS &rest KEYS)`, for SOURCE's page: QUERY its
  query parameters, the text its `q`; it answers `choice-matches`' LIMIT
  as `choice-options`, with the rest as its «more» line: the fragment to
  htmx, and a page titled «Choices» («Valg») holding the list to any other
  request. It returns the page's values.
- `(read-choice TEXT OPTIONS)` checks a posted value: OPTIONS a list of
  `(VALUE TEXT)` or a function of a value that answers its text or NIL
  (one that reads the record, for an asked choice). Values, as
  `read-date-text`'s: the value, NIL and its text when it is one of
  them; NIL alone for an empty or missing value; NIL and the message
  «must be one of the choices» («må være et av valgene») for any other.
- `(choice-find FORM NAME)` is the text typed in NAME's find field when
  FORM, a posted form, is NAME's find step (its «Find» was pressed), an
  empty text when nothing was typed, and NIL for any other submission.

`date-input` is a text field a person types a date in, as they write it,
with a calendar where scripts run: `(date-input (:label "Delivery" :name
"delivery" :value "2026-11-21" :min "2026-11-12" :quick t))`.

- **The field.** A `field` around a text field (`inputmode="decimal"`,
  `autocomplete="off"` unless `:autocomplete` names one, such as `bday`)
  that posts what is in it under NAME. VALUE, a `YYYY-MM-DD` date, is
  written as `date-text` writes it («21 Nov 2026», «21.11.2026»); any other
  VALUE, such as a refused text posted back, as it is. The hint ends with
  the form, «For example, 21 Oct 2026» («For eksempel 21.10.2026»), after
  the caller's `:hint`, unless `:form-hint nil` leaves it out, as a
  period's second field does. `:error`, `:required`, `:optional`, `:disabled`
  and `:label-hidden` are `text-input`'s. The page reads what is posted
  with `read-date-text` (`i18n.md` §6.2), which takes the forms a person
  types, day first in every language; a text it cannot read is shown again
  as typed, with its error. Without JavaScript this is the whole of it.
- **The calendar.** Where scripts run, a button at the end inside the
  field («Choose a date», `aria-haspopup="dialog"`) opens a month: a
  `popover="auto"` with `role="dialog"` and `aria-modal="true"`, named by
  its title, the month and the year («November 2026», «november 2026»),
  between a previous and a next month button, over a grid (`role="grid"`)
  of six weeks from Monday whose columns are headed by the days' short
  names, their full names as `abbr`. Its names are the catalogue's,
  written into the page by the server; today is the tenant's, written by
  the server too. It opens on the field's date when the field holds one
  the page or the calendar wrote, or one written `YYYY-MM-DD`, `D.M.YYYY`
  or as `date-text` writes it, else on today's month, and the focus is on
  that day, the one day Tab reaches. Today has `aria-current="date"` and a
  frame, the chosen day `aria-selected="true"` and the ink fill, at the
  others' weight and size; days of the next and the last month are muted.
  `:min` and `:max`, dates, make the days outside them `aria-disabled`,
  greyed, unchosen; the page still checks the value.
- **The keyboard.** The arrows move a day and a week, PageUp and PageDown
  a month, with Shift a year, Home and End to the week's first and last
  day, across months as they must; Enter or Space chooses; Escape closes;
  Tab goes round the month's buttons, the close button where it shows (on
  a phone), the focused day and the quick choices, never out.
- **Choosing.** A click, a tap, Enter or Space on a day writes it in the
  field as `date-text` writes it, fires `input` and `change` on the field,
  closes the calendar and gives the focus to its button, as Escape and a
  press outside give it back too. `:quick` adds buttons under the grid
  that choose their day: `t` for «Today» and «Tomorrow» («I dag», «I
  morgen»), or a list of `(LABEL DATE)`; one whose day is outside `:min`
  and `:max` is disabled, as the grid's days are.
- **Where it stands.** From 40rem of the window, under the field, or
  above it when there is more room there, always inside the window,
  20rem wide; it rises 0.25rem and fades in over `--duration-fast`.
  Below 40rem a floating sheet as a filter's popover is (`list-toolbar`):
  at the bottom of the window, 0.75rem from its sides and above the
  bottom's safe area, every corner `--radius-xl`, with a close button, over
  the `--overlay` dim, rising from below over `--duration`, its days at
  least 2.5rem high. It sinks and fades over `--duration-close` as it
  closes.

`time-input` is a text field for a time of day, 5 characters wide, in
tabular figures, `inputmode="decimal"`, with the hint «For example, 09:30»
(«For eksempel 09:30») after the caller's; it posts what is typed, which
`read-time-text` reads into `HH:MM` (`9`, `930`, `9.30`). It has no
picker. VALUE is shown as it is.

`money-input` is an amount in a currency: an `input-group`, its control
right-aligned in tabular figures, `inputmode="decimal"`,
`autocomplete="off"`, 10 characters wide unless `:width` says otherwise,
with the currency (`:currency`, the tenant's by default) before it in
English and after it in Norwegian, as `money-text` writes it (`€`, `NOK`;
`kr`, `€`). VALUE, an integer of minor units, is written as the language
writes the amount without its currency («1,250.50», «1 250,50»); any
other VALUE as it is. It posts what is typed; `read-money-text` reads it
(`i18n.md` §5.4). Nothing is read or rounded in the browser.

`dialog` with `:shortcut` opens on that key from anywhere on the page;
Ctrl is Cmd on a Mac, and a key without Ctrl is left to a field being
typed in.

- **A sheet on a phone.** Below 40rem a dialog, of every variant, stands
  at the bottom of the window at its full width, its top corners
  `--radius-xl`, its bottom ones square, and is never taller than the
  window less a strip of 2rem of the page above it. Its header (the
  title, the description, the close button) stays at the top and its
  footer at the bottom; only its body scrolls. The footer's buttons
  share one row, «Cancel» first, each growing to fill it, and keep the
  bottom's safe area. From 40rem it is centred, 28rem wide (32rem for
  the asking variants), all its corners rounded, its buttons at the end
  of the row. `:size :large` makes it a fixed box from there, for what
  changes inside it as one types (§6.4): `min(40rem, 100% - 2rem)` wide
  and `min(36rem, 100dvh - 4rem)` high, whatever it holds.
- **The keyboard.** Below 40rem a dialog that holds a text field (an
  `input` that takes text), a `textarea` or a `combobox` is as tall as
  it may be from the moment it opens, so the on-screen keyboard moves
  only its bottom edge. While a modal dialog is open (or a popover one
  types in, a choice's list or a list filter's choices), the script writes
  how far the visible part of the window (the visual viewport) is from
  the window's top and bottom as `--tun-visual-top` and
  `--tun-visual-bottom` on `<html>`, and the dialog stands between
  them: above the keyboard, its footer and the focused field in sight.
  Nothing is written while the page is zoomed in or when the visible
  part fills the window, and both are removed when no dialog is open.
  The page behind does not scroll while a modal dialog is open: the
  script sets `overflow: hidden` on `<html>`, keeping the scroll bar's
  room when the page had one, and gives back what was there when the
  last one closes.
- **Motion.** A sheet slides up from below the window over
  `--duration-sheet` and back down over `--duration-close`; from 40rem
  the dialog rises 0.5rem and fades in over `--duration` and sinks and
  fades over `--duration-close`. The dim is §2.1's.
- **Focus.** Opening puts the focus on the control with `autofocus`,
  else on the first control in the dialog. Closing gives it back to the
  control that opened it: the `command` button, or what had the focus
  when its shortcut opened it. Escape closes the topmost dialog only.
  Tab and Shift+Tab go round the controls of an open modal dialog,
  never out of it.
- Without JavaScript a dialog opens with its button where the browser
  has invoker commands, closes, and its form posts; it is a sheet and
  moves as above, since that is CSS.

`confirm-dialog` is the page's one dialog that asks before an action:
`(confirm-dialog ())`, a `dialog` of the `:confirm` variant whose
question and sentence are empty and whose buttons are «Cancel»
(«Avbryt») and the action, «Confirm» («Bekreft»), until a control fills
them. Those two words are written on it in the page's language
(`data-cancel-label`, `data-confirm-label`), and its buttons take them
when it asks, so a page holds no «Cancel» in its text while nothing is
asked. Every `app-shell` holds one, so a client's page needs none of its
own.

- **A control that confirms.** A button, a link or a menu item marked
  `data-tun-confirm="QUESTION"`, and as it needs
  `data-tun-confirm-detail` (one sentence of what happens) and
  `data-tun-confirm-action` (the action's words), asks in that dialog
  on a click instead of acting. `(confirm-attributes QUESTION :detail D
  :action A)` gives these attributes as a plist for a component's
  `:attributes`. The question names the record, «Delete order 1042?»,
  and the sentence says what follows, «The order and its lines are
  deleted for good.».
- **What it shows.** Its title is the question and under it the
  sentence (none when there is none). The action button holds the
  action's words, else the control's own (its text without key caps,
  else its `aria-label`) when they are 1 to 40 characters, else
  «Confirm»; it is the destructive button, red words, when the control
  is destructive (`data-variant="destructive"`), else the primary.
- **Answering.** The focus starts on «Cancel» when the action is
  destructive, so Enter is safe, and on the action otherwise. Escape
  and «Cancel» close it: nothing happens, and the focus goes back to
  the control. The action closes it and clicks the control once more,
  which then acts as it would have: its form posts with it as the
  submitter, its link is followed, htmx sends its request. The action
  runs once.
- **htmx.** `hx-confirm` asks in the same dialog, from htmx's
  `htmx:confirm` event, so every `hx-confirm` in a page gets it: its
  text up to and with its first «?» is the question and the rest,
  trimmed, the sentence; a text without «?» is all question, with no
  sentence.
  htmx sends the request on the action and drops it on «Cancel» or
  Escape. Mark a control one way, not both.
- **Without JavaScript** nothing is asked in the browser: the control
  acts, and an action that asks on the server, such as a `:confirm`
  operation's `confirm-panel`, still asks there. A page without a
  `confirm-dialog` (none of Tun's) asks with the browser's own box.

The `dropdown-menu`'s list, the `combobox`'s list and a `tooltip` rise
0.25rem and fade in over `--duration-fast`, and sink and fade over
`--duration-close` as they close.

`button` keeps its variants. `:primary` is ink, the one main step of a
view. `:outline` has the page's ground and the edge; `:destructive` is
red words (`--destructive`) on that same ground and edge, never a red or
pink fill, and under a pointer and pressed it is the outline's with the
red words; a confirm panel's last step is that button too. `:secondary`
is a grey fill, `:ghost` has neither ground nor edge, `:link` is words.
A button that is only an icon (`:size` `:icon`, `:icon-xs`, `:icon-sm`
or `:icon-lg`) of the variants `:outline` and `:ghost` has no frame and
no ground at rest, so a row of them is not a row of boxes; a pointer, a
press and focus still show. `:ghost` has neither at any size; an
`:outline` one pressed (`aria-pressed`), current (`aria-current`) or
open (`aria-expanded`) has its frame and ground again. This is
decided by the `data-size` and `data-variant` it writes, never by its
content; in a `button-group` the parts keep the group's frame. `:primary`
keeps its fill at every size. On a coarse pointer every button is a
target of at least 44px each way: the sizes under a control's height
(`:xs`, `:sm`, `:icon-xs`, `:icon-sm`) keep their look and take the
finger in an invisible area around them.

`badge` is one soft, fully round pill: a tinted ground, no frame, text at
least 4.5:1 on it, in five tones, each with one meaning: `:neutral` (the
default) a normal state, such as a draft or an order in progress;
`:info` sent or confirmed; `:success` done; `:warning` waiting on
someone; `:destructive` failed or overdue. `:primary`, `:secondary` and
`:outline`, the variants it had, are the neutral tone.

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

`card` with `:href` is a link as a whole: its title is the link's text,
and a tap or a click anywhere on it follows the link, except on the
controls in it (links, buttons, fields, text areas, selects and
labels), which stay above the link and work as themselves.

`table` keeps its columns at every width, a phone's too: no row turns
into a card. Its rows stand in a box of their own that scrolls sideways
when the columns do not fit, never the page; a soft shadow at an edge
of the box says there is more beyond it, and none shows at the very
start or end, since the covers that hide it scroll with the rows. The
first column names the record. Amounts and numbers are right-aligned
with `:align :end`, and every figure is tabular.

- **On a phone**, below 36rem of the table's own width (it is a
  container), the box is one panel (§2.1): the edge, `--radius-lg` and
  `--shadow-panel` on `--card`, the row of headers on top and a 1px
  line between rows. A row is one line of cells, 2.25rem high, and at
  least 2.75rem on a coarse pointer when it leads somewhere. The first
  column's text wraps, a word broken where it must be, to at most two
  lines, and what is left is cut with «…»; it takes at most half the
  table's width, and 16rem, so the next columns start in sight; up to
  that it keeps its own width, so a short name never wraps, and where the
  columns do not fit then, the box scrolls. Every
  other cell keeps to one line, unless its column is `:wrap`. A column
  given `:narrow nil` is left out there, for a value a phone can do
  without; the others keep the order the page gives them, so a page
  puts first what a phone should see without scrolling.
- **A row that leads somewhere** (`:row-href`, a list parallel to the
  rows or a function of a row) has one link, the text of its first
  cell, whose box covers the row: a tap or a click anywhere on the row
  follows it, without JavaScript too, and the keyboard reaches it in
  one stop, its focus ring drawn inside the row (`--focus-ring-inset`).
  The row takes `--pressed` while its link is pressed, at once, and
  `--accent` under a pointer only where a pointer hovers. A link, a
  button, a field or a label in a cell stands above the row's link and
  works as itself: a click on it does not follow the row, and pressing
  it does not press the row.
- **Sorting.** A column given `:sort KEY` has a header that is a link
  to `:sort-href` (a function of the key and `"asc"` or `"desc"`, or a
  format string): ascending, or descending when it is sorted ascending
  already, with an arrow, and `aria-sort` on the column `:sorted :asc`
  or `:desc`. The page sorts the rows; the link reloads it, so the
  address holds the sort and sorting works without JavaScript. A page
  with a `list-toolbar` keeps its filters in its sort links and its sort
  in the toolbar's `:keep`. The sorted column's header has the weight of
  the others; its arrow, in the text colour where the others' are muted,
  marks it.
- **Empty.** A table of no rows keeps its headers and says EMPTY in one
  row across them, in sight in the box at its left however wide the
  columns.
- **The rows come with the page.** A table's rows are in the page's
  answer; it loads nothing after it, and has no stand-in while it loads.
  A page that shows a list a part at a time gives one way to the rest,
  under the rows: `pagination`, or one «load more» link, never both.
  While a request for the
  list runs (a filter, a sort, a search), the rows stay where they are
  until the answer replaces them, and the loading sign (§4.1) shows.

`confirm-panel` is the form a `:confirm` operation
shows before it runs. `flash` is a message carried over a redirect.

`list-toolbar` is a list's one search and its filters, above the list:

```lisp
(ui:list-toolbar (:action "/orders"
                  :search (list :name "q" :label "Search orders" :value q)
                  :filters (list (list :name "status" :label "Status" :kind :one
                                       :choices '(("draft" "Draft") ("confirmed" "Confirmed"))
                                       :value "draft")
                                 (list :name "tag" :label "Tags" :kind :several
                                       :choices '(("rental" "Rental") ("music" "Music"))
                                       :value '("rental"))
                                 (list :name "dateless" :label "Without a date" :kind :toggle
                                       :value nil))
                  :keep '(("sort" "date"))))
```

- **One form.** It is one `<form method="get" action=ACTION
  role="search">`: the search field (`type="search"`, LABEL its name,
  shown as its placeholder), each filter's fields, and the KEEP pairs as
  hidden fields, such as the list's sort. So what is chosen is the
  address: a link, a reload and Back keep it. SEARCH and FILTERS may each
  be left out. A filter is `(:name :label :kind :choices :value [:all])`:
  KIND `:one` (one of several, VALUE a text), `:several` (several of
  several, VALUE a list) or `:toggle` (on or off, VALUE true or false;
  on, it sends `NAME=true`); CHOICES are `(VALUE LABEL)` pairs, as
  `radios` takes them. A period is `(:kind :period :label :names (FROM
  TO) :value (FROM-VALUE TO-VALUE) [:quick] [:errors])`, and a record
  found by typing `(:kind :choice ...)` (below).
- **Every key, every time.** A `:one` filter's first choice is «All»
  («Alle»), or ALL, of empty value; a `:several` filter's boxes and a
  toggle's box come after a hidden field of the same name and empty
  value. Every submission names every filter's key, so a page that
  `:remembers` it (§8) takes an unticked filter as cleared, not as
  missing. A page reads a filter with `query-values` (§8).
- **The row.** From 40rem of the toolbar's own width (it is a container)
  the search and one button per filter stand on one row, in the order
  given, that never wraps: the search keeps its width (24rem) while there
  is room, so a filter put into use moves only its own button and what
  follows it; when the row is full the search narrows first, to 12rem,
  and then the filters scroll sideways in their own box. A `:one` or
  `:several` filter's button is named by LABEL and opens its choices; a `:toggle` is
  one button that is pressed while on, with no choices to open. A filter
  in use says so in its button, «Status: Draft», or the count for two or
  more of several, «Tags: 2», with its edge `--border-strong`, at the
  weight, size and height of one not in use; joined to it, a clear
  button, «×» («Clear Status», «Fjern Status» to a screen reader), is a
  link to the address with that filter cleared. With two or more in use,
  «Reset» («Nullstill»), underlined words, follows the filters, a link to
  the address with every filter cleared, the search and KEEP kept. Both
  name every filter's key, a cleared one empty
  (`/orders?q=…&status=&tags=&tags=rental&dateless=`), as a submission
  does, so they clear a page that `:remembers` them (§8).
- **The choices.** A filter's choices are radios (`:one`) or checkboxes
  (`:several`) in a popover (`popover="auto"`: one open at a time, closed
  by Escape and a press outside, the focus back on its button), under its
  button, or above it when there is more room there, always inside the
  window; it rises 0.25rem and fades in over `--duration-fast`, and sinks
  and fades over `--duration-close`. Below 40rem of the window's width it
  is a floating sheet instead: at the bottom of the window, 0.75rem from
  its sides and above the bottom's safe area (and above a keyboard while
  one types in it, `--tun-visual-bottom`, §6 `dialog`), every corner
  `--radius-xl`, headed by LABEL and a close button, over the
  `--overlay` dim, rising from below over `--duration`.
- **Applied at once.** Where scripts run, a choice, a toggle and a clear
  submit the form at once, and there is no «Apply» button. In a boosted
  shell (§4.1) htmx sends it and morphs the page into the answer
  (`hx-swap` `innerMorph`, the body its target), pushing the address:
  each choice is a step Back returns from, and the page is not loaded
  again. The toolbar's elements have fixed ids, from `:id`
  («tun-list-toolbar» when omitted; two toolbars on one page need one
  each) and the filters' names, so the morph keeps them: a `:several`
  filter's popover stays open, the focus on the box just ticked; a `:one`
  filter's popover closes on the choice, the focus on its button. The
  loading sign shows as for any request.
- **On a phone.** Below 40rem of the toolbar's own width the search fills
  its row. Three or more filters are not in the bar: they are behind one
  «Filters» («Filtre») button after the search, which shows how many are
  in use (to a screen reader «Filters, 2 in use»). It opens a `dialog`
  (a sheet, §6 `dialog`) titled «Filters», inside the form, so its fields
  are the form's: a row per filter, its LABEL and value, its clear button,
  and under it its choices, in place of the popover; a choice applies at
  once, the list behind changes, the sheet stays open, and the page
  behind does not scroll. Escape, the close button and the dim close it,
  and the focus goes back to «Filters». One
  or two filters keep their buttons, on a row under the search that
  scrolls sideways in its own box rather than wrap.
- **Without JavaScript** nothing folds on a phone: every filter keeps its
  button on the row under the search, the popovers open with their
  buttons (the Popover API), and an «Apply» («Bruk») button submits the
  form.
- **A period.** A filter of KIND `:period` is the first and the last day
  of what the list shows, under two keys, FROM and TO, both sent in every
  submission and named in every clear and «Reset» link. VALUE holds their
  values as the page has them (as the address gives them: ISO dates or
  what a person typed), ERRORS a message for either, shown at its field.
  Its button says LABEL, or in use «LABEL: 1–14 Nov», as `period-text`
  writes it (`i18n.md` §6.2), at the weight, size and height of one not in
  use, with its clear. Its popover, as a filter's (a floating sheet on a
  phone), holds the quick choices «Today», «This week» (Monday to
  Sunday), «This month» and «Last month» («I dag», «Denne uka», «Denne
  måneden», «Forrige måned»), then QUICK's `(LABEL FROM TO)`, each a link
  to the address with that period, the one in use `aria-current="true"`,
  shown by its frame; and two `date-input`s, «From» and «To» («Fra»,
  «Til»), with their calendars, the form a date is written in under
  «From» alone. The popover opens with the focus on the quick choice in
  use, else the first, so a phone shows no keyboard until a field is
  tapped. Where scripts run a quick choice fills
  both fields as `date-text` writes its days, closes the popover with the
  focus on its button and submits; a day chosen in a calendar, and a date
  typed and then left or entered, submits, the popover staying open;
  nothing is sent while a date is being typed, and the toolbar sends no
  submission whose fields are those of the last one. In the «Filters»
  sheet it is a row as the others, its quick choices and fields under it.
  Without JavaScript the popover opens, a quick choice is a link, and
  «Apply» submits the dates typed.
- **A record to choose.** A filter of KIND `:choice`, `(:name :label
  :kind :choice :choices CHOICES :value VALUE [:source PATH] [:all]
  [:find TEXT])`, is one of many found by typing, as `choice-input`
  finds it: CHOICES `(VALUE LABEL)` pairs, every choice without SOURCE,
  and with it those the page knows (the chosen one, and a find step's
  matches); SOURCE answers as `choice-input`'s does (`choice-answer`). Its
  address is a `:one` filter's, `NAME=VALUE`, one key, in every
  submission, clear and «Reset», so an address written for a `:one`
  filter of that key reads the same; `:one` stays for a short list. Its
  button says LABEL, or in use «LABEL: TEXT», TEXT the chosen choice's
  label, at the weight, size and height of one not in use, with its
  clear. Its popover (a floating sheet on a phone, above the keyboard as
  `choice-input`'s) holds the text field and `choice-options`, as
  `choice-input`'s list does, with its keys and its asking; the value is
  a `select` named NAME, «All» (ALL) its empty first option, hidden where
  scripts run. A choice sets it and submits at once, closing the popover
  with the focus on its button, as a `:one` filter's. In the «Filters»
  sheet it is a row as the others: its LABEL, value and clear, and under
  them the text field and the list in place, the list scrolling in its
  own box of at most 15rem; no popover or sheet opens over the sheet, so
  the sheet's Tab, Escape and focus stay the sheet's (§6 `dialog`); a
  choice applies at once and the sheet stays open. Without JavaScript the
  select is in the popover, and with SOURCE a text field «Find»
  (`NAME-find`): «Apply» sends both, and the page gives `:find` the text
  (`(first (query-values query "NAME-find"))`) and CHOICES its matches,
  so the select holds them on the next page.

`flash` is a toast where the browser runs scripts. It stands over the
page, out of its flow: below 40rem at the bottom, 1rem from the
window's sides and 1rem above the bottom's safe area; from 40rem 1rem
from the top and the right of the window, at most 25rem wide; in the
layer `--z-toast`. It rises in over `--duration` and sinks and fades
over `--duration-close`. `:success` and `:info` leave by themselves 5
seconds after they showed, the time standing still while a pointer is
over the flash or the focus is in it; `:warning` and `:destructive` stay
until closed. Each has its close button. `:destructive` has
`role="alert"`, the others `role="status"`. `:toast nil` keeps a flash
in the page's flow, as without scripts. Without JavaScript a flash
stands in the page where it is written and stays.

`line-chart` draws a value over time, such as a share's price:
`(line-chart (:label L :points POINTS :digits D))`. POINTS is a list of
conses of a universal time and a real, in any order (the chart sorts
them by time), at most 2000; more, or a point that is not such a cons,
is an error in the caller's code. L, a text, names the chart: it is its
caption and the `aria-label` of the plot, which has `role="img"`. D,
from 0 to 6, is how many decimals the last value, the table and the
tooltip are written with, through `number-text` (`i18n.md` §6.2); without
it, as `number-text` writes them. The tick labels have their own decimals
(below).
Its look is shadcn/ui's charts (a card's surface, quiet gridlines, a
small tooltip), drawn as plain SVG by Tun.

- **The line** is drawn in an SVG that stretches to the chart's width at
  a fixed height (`preserveAspectRatio="none"`, the stroke kept 2px wide
  at every width by `vector-effect: non-scaling-stroke`), in
  `--chart-1`, over a wash of the same colour at 10%. A chart of one
  point has no line or wash.
- **The last point** has a dot of radius 4 with a 2px ring in `--card`,
  drawn in a second SVG over the first that is not stretched and places
  it by percentage, so it stays round.
- **The y axis** has three to five ticks, evenly spaced by a step of 1,
  2, 2.5 or 5 times a power of ten, each a multiple of the step, the
  lowest at or below the least value and the highest at or above the
  greatest; the axis runs from the lowest tick to the highest and need
  not start at zero. When every value is the same, V, the ticks are V
  and one step either side, the step the least of those steps at or
  above a tenth of V's absolute value (1 when V is 0). Each tick is a 1px
  solid gridline in `--border` and a label written with `number-text`
  with as many decimals as the step has (none for 10, one for 2.5). The
  labels are HTML items of no height spread from the top of the plot to
  its bottom (`justify-content: space-between`), so they stand at their
  evenly spaced lines without a `style` attribute (§4).
- **The x axis** has two to four labels at evenly spaced times from the
  first point's to the last's, items of no width spread the same way
  across the plot: the most of four, three and two that read
  differently, else the first alone, so no two read the same and none
  overlap at 320px. A label is the day without the year (`day-text`,
  `i18n.md` §6.2); the full date (`date-text`), two at most since it is
  wider, when the first and the last point fall in different calendar
  years; the time of day when every point falls on one day; all in the
  tenant's time zone. A chart of one point has that point's label alone.
- **Text** never takes the line's colour. The caption, the last value,
  the axis labels and the tooltip are `--text-xs` at every width, in
  `--muted-foreground` but for the last value, which is in
  `--foreground`; caption and last value stand above the plot. The table
  is a `table` (above), with its own text.
- **The table**: under the plot, a `<details>` closed by default holds a
  `table` of every point's time and value, so every value is there
  without the drawing. With JavaScript off the line, the dot, the ticks
  and the labels are drawn and the `<details>` opens.
- **The crosshair**: the script makes the plot focusable. A pointer over
  it, or the arrow keys when it has focus (Home and End for the first
  and last point), moves a vertical hairline to the nearest point and
  shows a tooltip there with the value first, then the date (with the
  time of day when the x labels show times). The tooltip sits beside the
  hairline, on the side with room: at the top of the plot for a point in
  its lower half and at the bottom for one in its upper half, and only as
  tall as its two lines wherever it is. The same value and date go
  to a visually hidden polite live region beside the plot, so a screen
  reader says them as the keys or the pointer move. Escape hides the
  hairline and the tooltip; leaving the plot or moving focus away does
  too.
- With no points, «No data» stands in place of the plot, and there is no
  table.

`sparkline` is a value over time in a line of text: `(sparkline (:points
POINTS :label L :digits D))`, POINTS and D as `line-chart` takes them,
no axes and no text, 6rem wide and as high as a line of the text around
it (`1lh`), such as in a table cell, its
line 1.5px in `--chart-1`. It has `role="img"` and an `aria-label` of L
followed by its first and last value, joined by a catalogued word: en
«EQNR.OL: 412.30 to 430.00», nb «EQNR.OL: 412,30 til 430,00». With one
point it is a dot; with none it draws nothing and its label is L and
«No data».

`page-header` is the top of a page: its breadcrumbs, the title, the
page's one `h1`, and the page's actions (`:actions`, a list of nodes) in
one row beside the title, at every width, a phone's too. The actions
stand at the right edge of the header and never wrap; a long title wraps
beside them. The filled actions, a `button` of the `:primary` variant
alone or as the one button of a form (the one next step), come last, in
the markup as on the screen; the others keep the order the page gave.
`:meta` (live facts: a status badge, a count) is a row under the title's;
`:description`, a sentence under the title, is for a client that wants
one (§8: Tun's own pages have none).

`section` takes `:meta` in the same sense: the live facts of that part
of the page, such as «3 lines» or «The units are with the customer.», or
a status badge, as a list of nodes or one node. They stand in a row under
the section's heading, in the header's look: `--text-sm`, in
`--muted-foreground`, a gap of 0.5rem between them, wrapping; the
section's actions stay beside the heading. A fact is never a badge among
the actions, and `:meta` is not help text: a sentence about what the
section is for is a `:description`, which Tun's own pages do not use.

`note` is a short muted line in a page's flow: `(note () "Your answer
goes to Nordvik Bakery Ltd.")`, a `<p>` in `--text-sm` and
`--muted-foreground` (§2.1: at least 6.5:1 on every ground), no margin
of its own, its words wrapping, a long word broken where it must be.
It is for a line that says what follows from what is beside it: under a
pair of buttons («Your answer goes to COMPANY.»), under a table («The
first 100 found; search to narrow them.»), under a form's actions. It is
not a field's hint (`field`'s `:hint`, tied to its field), not a table's
caption (`table`'s `:caption`, which names what the table holds, above
it), not an empty list's text (`empty-state`), not a live fact (a
header's or a section's `:meta`) and not a message that something
happened (`flash`, `alert`). It takes the children a paragraph takes:
text, a link, `kbd`.

- **When the actions do not fit on a phone.** The header reckons, when it
  is rendered, whether its actions fit beside the title on a 320 px phone,
  whose content is 18rem wide: an icon button is 2.75rem, a button with
  words 1.25rem and 0.5rem a character of its words, and 1.375rem for
  each icon, a form or a `dropdown-menu` its button's, anything else 6rem,
  with 0.5rem between two actions; the title keeps 0.75rem a character of
  its words, at most 6rem; they fit when the actions, the title's room and
  1rem between them come to 18rem or less. A word of the title longer than
  its room breaks, with a hyphen where the page's language (`lang`) has
  one for it (`hyphens: auto`), else anywhere. When they do not, every action
  that is a `button` or a form holding one button, other than the filled
  ones, folds into one «More actions» («Flere handlinger») `dropdown-menu`
  standing before the filled actions: a `:ghost` button showing only
  `:ellipsis`, with the menu at its end. Each folded action is an item
  with its words (else its `aria-label`), its first icon, its link, its
  other attributes (`hx-*`, a confirm), destructive when it was; a form's
  item is a submit button naming the form (`form`), which keeps its place
  in the row and gets an id when it has none. When even then they do not
  fit, a filled action with an icon shows its icon alone, its words still
  its name. An action of another kind (a `dropdown-menu`, any other
  markup) never folds. This holds below 40rem of the header's own width
  (it is a container): there the folded actions are hidden from the row
  and the menu shows; from 40rem every action shows and the menu does
  not. The menu is the popover a `dropdown-menu` is, so it opens and its
  items work without JavaScript.

A `dropdown-menu` item's `:icon` is an icon's name or an icon already
made, as the header's folded items carry the action's own.

`section-links` gives a page read as a whole a row of links to its
sections: `(section-links (:label "On this page" :items '((:label
"Details" :href "#details") ...)))`, a `nav` named LABEL holding plain
links to the sections' ids. The row is one line: wider than its box, it
scrolls sideways inside it, and the page does not. Where scripts run, the
link of the section in view, the last whose top has passed the top of the
content (under the shell's top bar on a phone), else the first, or, at
the foot of the page, the section a followed link named while its top is
in the window, has `aria-current="location"`, shown by the text colour and an underline at
the weight, size and padding of the others; it follows the scroll and a
followed link. Without JavaScript the links move the page and none is
marked. Tabs are for parts seen one at a time; what is read together is
one page with section links.

`summary-list`, a record's facts, sets them apart by space alone: no line
or box between its rows, and no padding or edge of its own, so its edges
line up with the header and the sections. Narrower than 30rem (its own
width) a row is the label, in `--muted-foreground`, beside the value,
with the action under the value; from 30rem the rows stand in two
columns, a row's label above its value and its action beside the label.

- **The label's column.** Beside the value the label has a column of
  10rem, or half of what the row has left after the gap between them,
  `(100% - gap) / 2`, when that is less, the same in every row, so the
  values line up. 10rem holds a label of about
  20 characters in the device's font at 0.875rem, such as
  «Organisasjonsnummer» (about 9.5rem), on one line from a 360 px phone.
  A label longer than its column, as that one on a 320 px phone, breaks:
  with a hyphen where the page's language (`lang`, the page's or the
  list's own) has one for it (`hyphens: auto`), else where it must
  (`overflow-wrap: break-word`). No label's text ever reaches into its
  value's box, at any width; above it, too, a long word breaks the same
  way.

`tabs`, segmented (the default), is a strip with a 1px `--border` frame
on the ground it stands on, the page, a card or the chrome, and its
chosen tab a `--secondary` ground with the `--border` edge. A strip of
`:line` tabs, links too, keeps each tab its own width from the start of
the row.

`app-shell`'s top bar, its menu on a phone and its sidebar stand on
`--chrome` itself, with a 1px `--chrome-border` edge; the page is on
`--background`; the phone menu's dim is `--overlay`.

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
                                                   :meta (format nil "Kari · ~a" (date-text "2026-10-21")))))
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

### 6.2 Text written in Markdown

`markdown` shows text that people and agents write, such as an item's
description or a comment, with the parts of Markdown they use most:

```lisp
(ui:markdown (:text (item-description item)))
```

The rules are CommonMark's and GitHub's tables, made smaller. Text that
no rule takes shows as written.

- **Lines.** A line ends at LF, CR LF or CR, as in CommonMark, and the
  CR is never shown. A browser sends a text area's lines with CR LF.
- **From the text, each time.** TEXT is parsed whenever the component
  renders, and nothing stored is changed. NIL is the empty text, which
  renders an empty root.
- **Safe by construction.** TEXT becomes Tun's markup (`tun.html`),
  never HTML. Each character of it ends up in a text node, which the
  renderer escapes, or is a mark the parser read (`**`, `#`, a fence).
  HTML in TEXT, such as `<script>`, `<b>`, a comment or `&amp;`, shows as
  written. The output is allowed extension output (§5).
- **Plain text reads as before.** A text with none of the marks below
  is paragraphs: one per run of lines with no blank line between them,
  each line break inside a paragraph a `<br>`, every character as
  written. Unlike CommonMark, a single line break is always kept.
- **Bounded.** Lists nest at most four levels deep, bold and italic at
  most eight. A table has at most 20 columns. The time to render and the
  size of the output grow linearly with the text's length, whatever the
  text holds, and no text makes the component signal.

**Blocks.** A block starts at the beginning of a line, with at most three
spaces before it.

- **Paragraphs** are as above. A heading, a list, a fence, a rule or a
  table starts a new block without a blank line before it. The one
  exception is an ordered list that does not start at 1, so «Møtet
  er\n2. mai» stays one paragraph. After a blank line, a line such as
  «17. mai er fridag» starts an ordered list numbered from 17, so it
  shows «17.» before «mai er fridag», indented as a list's item is.
- **Headings.** `#` followed by a space starts a heading of the first
  level. `##` followed by a space, or `###` up to `######`, starts one of
  the second level. They are the elements `hN` and `hN+1`, where N is
  `:heading-level`, from 2 to 5, 3 when omitted; any other value is an
  error in the caller's code. So on a page whose title
  is an `h1` and whose sections are `h2`, a text's headings never outrank
  the page's own. Closing `#`s are left out. A `#` with no space after
  it, as in `#12`, is text.
- **Lists.** `-`, `*` or `+` followed by a space starts an item of an
  unordered list. One to nine digits, then `.` or `)`, then a space,
  starts an item of an ordered list, numbered from its first item's
  number (`start`).
  - A marker indented two or more spaces deeper than the item above it
    starts a list inside that item, down to the fourth level. Markers
    indented deeper than that make items of the fourth level.
  - A marker of the other kind at the same depth starts a new list
    there.
  - A line that is not a marker continues the item above it, after a
    line break. A heading, a fence or a rule ends the list instead.
  - After a blank line, the list goes on only if the next line is an
    item.
- **Code.** A fence is a line of three or more backticks, with anything
  after it except a backtick, such as a language name (not shown). It
  starts a code block, which ends at a line of at least as many backticks
  and nothing else, or at the end of the text. The block's lines are
  written as they are, in a `code-block` (§6) with its copy button,
  scrolling sideways in its own box. A fence indented by up to three
  spaces has that many spaces taken from each of its lines.
- **Rules.** A line of three or more of the same `-`, `*` or `_`, with
  spaces between them or not and nothing else, is an `<hr>`. This also
  holds under a line of text, where CommonMark would make a heading.
- **Tables**, as GitHub writes them.
  - A table starts at a line holding a `|` that is followed by a
    delimiter line, such as `|---|:--:|---:|`. The delimiter line must
    have as many cells as the first line, each made of `-` with or
    without a `:` at either end. The first line is the table's headings.
  - Each following line holding a `|` is a row, up to a blank line, a
    line with no `|`, or a line that starts another block.
  - Cells are split at each `|` not written `\|`. One `|` at each end of
    a line is optional. Each cell is trimmed.
  - `:-` aligns a column to the start, `:-:` to the centre, and `-:` to
    the end.
  - A row's cells beyond the headings' number are left out, as on
    GitHub. A row with fewer cells is shorter: no empty cells are added.
  - A first line with more than 20 cells does not start a table; it and
    the lines after it are a paragraph.
  - **Up to three columns:** a table at every width, its cells' text
    wrapping, long words included.
  - **Four or more:** where the component is less than 36rem wide, each
    row is a card, and each cell in it has its column's heading above its
    value. In a card, a heading is its text without marks, cut at 80
    characters, and an empty cell has no heading. From 36rem wide, the
    rows are a table that scrolls sideways in its own box when it does
    not fit.

**Inline**, in paragraphs, headings, items and cells:

- **Code spans.** A run of backticks up to the next run of exactly as
  many is a `<code>`. The text between them is written as it is, with no
  marks read inside, a line break as a space, and one space at each end
  left out when both ends have one and the text is not only spaces. A run
  with no match is text.
- **Bold and italic.** `**` or `__` around text is `<strong>`, `*` or
  `_` is `<em>`, and three of either is both.
  - An opening mark is followed by a character that is not a space, and
    a closing mark is preceded by one. The two must be of the same
    character and the same length.
  - `_` opens only when it does not follow a letter or digit, and closes
    only when none follows it. So `snake_case_name` stays as written,
    while `*` inside a word marks, as in `un*frigging*believable`.
  - A mark with no match is text. Inner marks are matched first, as
    CommonMark does.
- **Links.**
  - `[text](address)`, with an optional title in quotes that is not
    shown, is a link when the address is an `http:` or `https:` URL, a
    `mailto:` address, or a path on the same site as §5 says
    (`/saker/12`, but not `//host` or `/\host`).
  - The address ends at the first space or at the `)` that closes the
    link: parentheses inside it must be balanced, as in
    `https://no.wikipedia.org/wiki/Tun_(gård)`. Written inside `<` and
    `>`, it ends at the `>` and may hold parentheses unbalanced.
  - `<address>` is such a link with the address as its text.
  - So is an `http://` or `https://` URL written on its own, after the
    start of a line, a space or a character that is not a letter or
    digit. It ends at a space, `<`, `[` or `]`, and its final `.`, `,`, `:`, `;`,
    `!`, `?`, `*`, `_`, `'` or `"`, and a `)` with no `(` to match it, are
    left out of it. One whose run up to that space, `<`, `[` or `]` is
    over 2048 characters makes no link.
  - The text of a link may hold code, bold and italic, but not another
    link, at any depth: a URL or `<address>` in it is text.
  - Any other address, such as `javascript:`, `data:`, `vbscript:`, a
    relative path, `//host`, `/\host` or one over 2048 characters,
    makes no link. The text
    shows as written, brackets and parentheses included.
- **Escapes.** `\` before an ASCII punctuation character shows that
  character as written, without its meaning, as in `\*`. Before anything
  else, `\` is itself.

**Width.** The root is a container (`container-type: inline-size`). What
it holds never makes it wider than the space it is given, and it never
widens the page.

- Words longer than a line, such as a URL, break in paragraphs, headings,
  items, inline code and the tables of up to three columns.
- Code blocks and the tables of four or more columns, from 36rem, scroll
  in their own boxes.
- A `markdown` gets its width from its container, as a block does. In a
  row of flex items it needs a width of its own.

Not taken: block quotes, images, raw HTML, strikethrough, task lists,
headings underlined with `=` or `-`, indented code, reference links,
footnotes and character references (`&amp;`). Each of these shows as
written.

### 6.3 The graph

`graph` draws things and what depends on what among them, such as a
project's steps with where agents work and the items tied to each, or
Tun's modules and what each requires:

```lisp
(ui:graph (:label "Event rental"
           :nodes (list (list :id "brief" :title "Brief" :state :done :href "/steps/1")
                        (list :id "calendar" :title "Booking calendar" :meta "Factory 3"
                              :state :active :href "/steps/2"
                              :badges (list (list :text "Claude i tun" :kind :agent)
                                            (list :text "#12" :kind :ref :href "/items/12")))
                        (list :id "staging" :title "Deploy to staging" :state :waiting
                              :badges (list (list :text "2 questions" :kind :ref
                                                  :tone :warning))))
           :edges (list (list :from "brief" :to "calendar")
                        (list :from "calendar" :to "staging"))))
```

- **Nodes.** Each is `(:id :title [:meta] [:state] [:href] [:badges])`:
  ID a string, unique in the graph; TITLE its name; META a second line
  of small text; STATE one of `:planned` (the default), `:active`,
  `:waiting` (on a person), `:done`, `:failed` and `:blocked`; with
  HREF the whole node is a link, as `card`'s is, its badges' links
  staying above it; BADGES a list of badges (below).
- **The node** is a box 6.5rem high, 14rem wide in the drawing and as
  wide in the list as «The list» says: TITLE on up to two lines, cut with an
  ellipsis after the second and whole in the box's `title`; the state's
  word with a dot, then META, cut with an ellipsis and whole in its own
  `title`, on the next; the badges on the last.
- **The badges a node shows** are those that fit the line of the
  narrowest node, a list's at 12rem, with its padding (10.25rem of
  badges), as the server reckons a badge's width from its text: 1.1rem
  of padding and border, 0.45rem a character, and 0.6rem for an agent's
  dot, with 0.25rem between badges; «+N» counts as a badge of its own
  text. The first badge always shows, then each in turn while it and,
  if any are left after it, the «+N» for those still fit.
  The same badges show in both forms. «+N» says how many are left out,
  and its `title` names them (en «2 more: Kari, #21», nb «2 til: Kari,
  #21»). The badges left out are not in the node, so none of their links
  takes focus; every badge is in the table.
- **The guard.** A text can be wider than reckoned, so the badge line is
  one line high and clipped: a badge that wraps past it is out of sight
  whole, and a badge alone wider than the line ends in an ellipsis, its
  whole text in its `title`.
- **The tones.** The state's tone is a 3px stripe at the box's start and
  the dot: planned `--muted-foreground`, active `--info`, waiting
  `--warning` on a `--warning-soft` box, done `--success`, failed and
  blocked `--destructive` on `--destructive-soft`. The words are
  catalogued: «Planned», «Active», «Waiting», «Done», «Failed»,
  «Blocked» (nb «Planlagt», «Aktiv», «Venter», «Ferdig», «Feilet»,
  «Blokkert»).
- **Badges.** Each is `(:text [:kind] [:tone] [:href])`, drawn as a
  `badge`: TONE `:neutral` (the default, the outline variant),
  `:info`, `:success`, `:warning` or `:destructive`. Without KIND a
  badge is a plain label. KIND `:agent` is
  someone working there now: a dot before the text that pulses (and
  stands still when motion is reduced), the tone `:info` unless
  given, «, working now» («, arbeider nå») after the text for a screen
  reader only, and a 2px ring in `--info` around its node. KIND `:ref`
  is a count or a reference, such as «3 open» or «#12», in tabular
  figures. With HREF the badge is a link.
- **Edges.** Each is `(:from A :to B)`: B depends on A, or comes after
  it. A repeated edge is drawn once, and an edge from a node to itself
  not at all. An edge naming a node that is not in NODES is an error in
  the caller's code.
- **Bounds.** At most 150 nodes, 300 edges and 8 badges on a node; more,
  a repeated or missing ID, or a STATE, KIND or TONE not listed is an
  error in the caller's code.

**The layout** is computed on the server, in layers that run from left
to right, each edge from a layer to a later one:

1. A depth-first search through the nodes in their order, and through
   each node's edges in theirs, reverses each edge back to a node it
   is still searching from, so a cycle becomes a chain.
2. A node's layer is the longest path to it from a node with no edge
   into it; such a node then moves to the layer just before its
   earliest successor's.
3. An edge across more than one layer takes an empty place in each layer
   between, so it never runs under a node. The edges from one node share
   their empty place in a layer, so a node's long edges run as one trunk
   until they part; the edges step 1 reversed share theirs only with
   each other, so a dashed edge never runs along a solid one.
4. Within each layer, the nodes and places are ordered by the mean
   position of their neighbours in the layer before, then the layer
   after, four times each way, and the order with the fewest crossing
   edges is kept.
5. Each layer in turn takes rows that grow down it in that order, one
   place a row at least, as near as they can be, in the least squares,
   to the topmost row of each place's neighbours in the layer before; then
   the same by the layer after, back up; four times each way and once
   more down. A place with no such neighbours keeps its row as far as
   the others let it. Then a row no layer has a place in is taken out,
   and the first row is 0. Leaning to the topmost neighbour keeps a
   chain level and puts a node that feeds a wide fan level with the
   fan's top, so the drawing's first layers stand at its top.

Nodes with no edges are not in the layers: they stand in a row under
the drawing or the list that wraps to its width. The same input always
gives the same layout.

**Two forms.** The figure holds the graph twice, as **the drawing**, the
layers from left to right, and as **the list**, one column, and CSS shows
one of them by the figure's own width. The figure is a container
(`container-type: inline-size`): narrower than 40rem, as on a phone or in
a narrow column, it shows the list; from 40rem, as in a desktop's
content, the drawing. The form not shown is `display: none`, neither
seen, read nor focused. So the window does not decide: a graph in a
narrow card on a wide page is a list.

**The drawing.**

- Layers are columns 14rem wide with 3rem between them, and a layer's
  nodes and empty places are 6.5rem high with 1rem between them, so no
  `style` attribute places anything (§4). The edges are an SVG over
  the columns, behind the nodes, whose viewBox is the columns' size in
  CSS pixels at 16px to the rem.
- An edge is 1.5px in `--muted-foreground`, a curve between layers and
  straight through its empty places, and ends in an arrowhead pointing
  into its target. An edge forward runs from its source's right side,
  at the middle, to its target's left side, the arrowhead pointing
  right. An edge the search reversed, whose target is in an earlier
  layer, is dashed and runs from its source's left side to its target's
  right side, 0.5rem below their middles, the arrowhead pointing left;
  so two nodes that depend on each other show two lines.
- The drawing has its own box, which scrolls sideways when the drawing
  is wider than it; the page does not.

**The list.**

- The nodes with edges stand in one column, in the order of the
  layers, each layer from its top, one after the other with 0.5rem
  between them: the first node is at the top, and no place in the list
  is empty. Each is as wide as the figure less the gutter, at most
  40rem and at least 12rem: when the gutter leaves less, the list
  scrolls sideways in its own box.
- The gutter, left of the nodes, holds the edges as rails. A rail
  belongs to the node at its top and is a vertical line from that
  node's row down to the lowest node it joins, in a lane of its own
  among the rails its line would meet: rails are given lanes from the
  shortest, each the lane nearest the nodes that no rail whose line
  overlaps its own, from where it meets its top node to where it meets
  its lowest, holds. So a rail into a node's upper part and one out of
  its lower part may share a lane, as a chain does. Lanes are 6px
  apart.
  - A node's **solid rail** holds its edges to the nodes below it: a dot
    on the rail and a line from the lower part of the node's left side
    start it, and at each target a dot on the rail and a line to the
    upper part of the target's left side end in an arrowhead pointing
    into the target.
  - A node's **dashed rail** holds the edges step 1 reversed, from nodes
    below it into it: a line to the upper part of the node's left side
    ends in an arrowhead pointing into it, and at each source below, a
    dot on the rail and a line from the lower part of the source's left
    side start that source's edge.
  - The rails and lines are 1.5px in `--muted-foreground`, the dots
    2.5px in radius.
- The gutter is an SVG as high as the list, whose width is the lanes',
  stretched to the list's height (`preserveAspectRatio="none"`), the
  lines kept 1.5px by `vector-effect: non-scaling-stroke`.
- The figure's caption is LABEL. Under both forms, outside them, and so
  under whichever shows, a `<details>` closed by default, «Show as a table», holds a `table` with a row per
  node: its title (a link to HREF), its state's word, the titles of the
  nodes it depends on, and its badges. The rows follow the layers, from
  the first, each layer from its top; then come the nodes with no
  edges, in the order NODES gives them.
  The SVGs and the empty places are `aria-hidden`. The component has
  no script: without JavaScript it is drawn the same.
- With no nodes, «No data» stands in place of both forms, and there is
  no table.

### 6.4 The search

An application whose modules or client say what of their records can be
found has one search, on every staff page, for everything: opened with
Ctrl K (⌘ K on a Mac) from anywhere, a button in the phone's top bar or
a row at the top of the sidebar. It matches by one rule, and the same
search answers a person's page, the dialog's results and an agent's
`search` tool.

- **What can be found.** `(search-records APPLICATION QUERY ACTOR)`, a
  generic function in `TUN` with the `traced-protocol` combination,
  answers the results for QUERY that a module or the client finds, as a
  list. Tun's own method, the least specific, answers none. A module
  specialises it on its mixin and a client on its application class or a
  feature; each method returns its own results appended to
  `(call-next-method)`'s, so every contributor's are kept, the client's
  first. A method runs in a read transaction with `*actor*` bound to
  ACTOR, so it reads only what ACTOR may (`select` applies the record
  policies, `store.md` §6), and it may look at `(search-query-kinds
  QUERY)` to skip a kind the caller did not ask for (only the `search`
  tool asks for some kinds; the page and the dialog ask for all).
  `introspect_extensions` lists the seam.
- **Answering a kind in place of a module.** `(search-replacements
  APPLICATION)`, a generic function in `TUN` with the `traced-protocol`
  combination, answers a list of `(KIND MODULE)`, each saying that
  APPLICATION answers KIND itself and that MODULE's contributor does not:
  KIND a kind's key, MODULE a module's name as a lowercase string, as
  `introspect_extensions` shows it (`"customers"`). Tun's own method, the
  least specific, answers none, so every contributor answers as before. A
  module specialises it on its mixin and a client on its application
  class or a feature, each appending to `(call-next-method)`'s, as a
  module that shows a kind its own way (its own page, its own names)
  replaces a module it builds on. While MODULE's method of
  `search-records` runs, `(search-query-wants-p QUERY KIND)` is false, so
  `search-entity`, `search-among` and every contributor that asks it
  read nothing of KIND, for every role; a result of KIND that MODULE's
  method makes all the same is dropped. Nothing else is: MODULE's other
  kinds, and every other contributor's results of KIND (another module's,
  the client's), are kept, so a module silences only the one contributor
  of the one kind it names, and the client, which cannot be named, is
  never silenced. An entry whose MODULE is not a loaded module is ignored
  and written to the server's error output. `introspect_extensions`
  lists the methods, each with its place in the source.
- **A result** is `(make-search-result :kind KIND :label LABEL :icon
  ICON :title TITLE :meta META :href HREF :score SCORE :id ID)`: KIND a
  short key in English (`"customer"`), LABEL its word in the page's
  language («Customer», «Kunde»), ICON an icon's name, TITLE the record's
  name, META a list of short texts about it (an email, a status, a
  date), HREF the record's page, SCORE what the rule gave it, ID the
  record's id. `(search-entity QUERY ENTITY ...)` makes a kind's results
  from the records of an entity: it reads them, scores each by the rule
  and answers the five best. With `:fields`, a list of the entity's
  field names, it reads only those fields of each record (`store.md` §2,
  item 11; the fields' JSON names, `'("name" "email")`), and its
  functions must read no other. `(search-among QUERY
  ROWS ...)` does the same for ROWS a contributor has read itself, as
  records, as the JSON objects a `define-query` of rows answers, or as
  property lists: it takes `search-entity`'s keys (`:keep`, `:kind`,
  `:label`, `:icon`, `:title`, `:names`, `:texts`, `:identifiers`,
  `:meta`, `:href`, `:score`), each a function of a row, and `:id`, the
  row's id (by default a record's id, a JSON object's `"id"` or a
  property list's `:id`), takes ROWS in the order read, oldest first,
  and answers the five best as `search-entity` does, its `matched` too.
  `search-entity` is `select` and `search-among`.
- **Only what ACTOR may open.** Tun keeps a result only when its HREF is
  a path on the site whose page ACTOR's role opens, as the home page's
  (§8, «Home»): a staff page (`define-page`: the client's, the kernel's,
  or one of a module the application enables) whose policy admits
  ACTOR, or a resource's list, or a resource's record when ACTOR may
  call the resource's get tool. Any other result is dropped and written
  to the server's error output.
- **Who has it.** An application has the search when a method of a
  module it enables or of the client is applicable to it besides Tun's
  own. Then every `app-shell` of a staff page has the search's button,
  its row and its dialog, a viewer's too, since `/search` is a page for
  `:viewer` and up and so for every role a staff page admits; an
  application without has none of them, no shortcut, and `/search` is
  not found. The customers module finds customers (by name, email and
  phone) and the orders module orders (by their customer's name, their
  delivery address and their id), so a client enabling either has the
  search with no code of its own.

**The rule.** In one sentence: a record is found when every word typed,
folded, is in one of its texts in any order, or when all that was typed
is one of its identifiers or their start, and it ranks by where it
matched, an identifier and the name before the rest. In full:

- **Folded.** What was typed and what is stored are compared folded:
  upper and lower case alike; accents and other marks ignored («é» is
  «e», «å» is «a»), a letter written with a separate mark too; «ø» is
  «o», «æ» «ae», «œ» «oe», «ß» «ss», «ł» «l», «đ» «d»; a run of «a» is
  one «a», so «aa», the old spelling of «å», finds it («aasen» finds
  «Åsen»); any run of spaces, tabs and line breaks is one space, none at
  either end.
- **Every word, in any order.** What was typed is split into words at
  spaces. A record matches when every word is found, folded, in one of
  its searched texts, as a word, the start of one or a part of one, in
  any order and across texts; or when the whole of what was typed is
  one of its identifiers or the start of one. `(search-match QUERY
  :names NAMES :texts TEXTS :identifiers IDENTIFIERS)` decides it once
  for every contributor and answers the score, or NIL for no match.
  NAMES are the texts that name the record (a customer's name), TEXTS
  the others it is found by (a note, an address, the meta line's
  words), IDENTIFIERS the values found only whole or by their start (an
  order's number, an email, a phone number).
- **Identifiers.** An identifier and what was typed are compared folded
  and without spaces and the signs «+ - . # ( ) /», so «412 34 567»
  finds «41234567» and «#1042» finds «1042». It scores only when what
  was typed is it whole, or, when what was typed holds a digit, its
  start from three characters on: the start of a number counts (an
  order's, a phone's), the start of an email does not, so «kari» ranks
  Kari's name above another customer whose email starts so.
- **Phone numbers.** A contributor gives a phone number as identifiers
  through `(search-phone-forms TEXT)`, which answers TEXT and, when TEXT
  is written with its country code, its national number and that number
  with a leading 0 when it has none: «+47 912 34 567» answers it,
  «91234567» and «091234567», so «91234567», «912 34 567» and «912 34»
  find it as an identifier whole or by its start, and «030 1234567»
  finds «+49 30 1234567». TEXT is written with its country code when it
  starts with «+» or «00» and holds only digits, spaces and «- . ( ) /»;
  the code is as E.164 gives it by its first digits (1 and 7 are one
  digit; 20, 27, 30–34, 36, 39, 40, 41, 43–49, 51–58, 60–66, 81, 82,
  84, 86, 90–95 and 98 are two; all others three), and a «(0)» after it
  belongs to the national number. Any other TEXT answers itself alone, so
  a number stored without its code is found as before; NIL or an empty
  TEXT answers nothing. The forms are whole identifiers: the rule does
  not change, and no identifier is found from its middle («34567» finds
  none of these). The customers module gives its phones so.
- **The score.** The best of: 100 what was typed is an identifier; 90
  it holds a digit and is the start of one; 80 a name is what was typed; 60 a name starts
  with it; 45 every word starts a word of the names; 25 every word is
  in the names; 10 a word is found only in the other texts. A
  contributor may lower a score, as an order scores as its customer
  would, less 15, so a customer comes before its orders.
- **The order.** Results come best score first; among equal scores, by
  kind in the order the contributors answered them, then in each
  contributor's own order, which `search-entity` makes the newest
  first. At most five of one kind and twenty in all.
- **The marks.** Where a result is shown, the stored characters each
  word covers in the title, its first match at the start of a word,
  else its first anywhere, are marked (`<mark>`): «kafe» marks «kafé»,
  «bjorn» marks «Bjørn».
- **Why it was found.** A result whose title has no mark shows its
  match in the line under the title: the words are marked the same way
  in each META text, and a META text that is an identifier found whole
  or by its start (an email, a phone number written otherwise, «41234567»
  for «412 34 567») is marked over the characters it covers, a number
  with its country code over its national part when that found it
  («+47 <mark>912 34 567</mark>» for «91234567»). When no
  META text holds a mark, the result carries what it was found by
  (MATCHED), the first of its names, texts and identifiers that holds a
  mark, and the line shows it right after the kind's word, marked:
  «Order · <mark>Storgata</mark> 12 · Confirmed». MATCHED is that text
  whole when it is 80 characters or less; a longer one from the start of
  the word holding its first mark, «…» before it unless that is the
  text's start, and at most 80 characters of it, «…» after it when it is
  cut. `search-entity` works MATCHED out for the results it keeps;
  `make-search-result` takes it as `:matched`, NIL when left out, so a
  contributor written without it is shown as before, its META marked.
  A result whose title holds a mark shows its line unmarked, as before.
- **What it costs.** `search-entity` reads every record of its entity
  once per search, in the read transaction, and matches in Lisp: on
  Postgres one `SELECT` of the table per kind, without an index, so the
  cost grows with the records, as `customers_list`'s query does;
  `:fields` keeps it to the columns the kind needs. The rule itself costs
  little for a record it does not find: `search-match` folds each name
  and text into one buffer per search, without the index of each
  character (only the marks of the results shown need those), leaves a
  text unfolded when none of its characters folds to a word's first,
  stops folding a record's texts once every word is found, compares an
  identifier character by character as it folds, and folds the names
  into texts of their own only for a record every word was found in, the
  only ones it scores. The dialog asks only from two characters and
  after a pause of 150 ms, so a person typing asks once per pause. A
  search of 2000 customers answers within 100 ms on the server, in
  memory and on Postgres, and so does one of 2000 customers, 2000 orders
  and 2000 records with long texts, every kind together (its test's
  limit is 90 ms: under the rule, with room over what was measured on a
  loaded machine).

**The search page.** `/search?q=TEXT`, a kernel page for `:viewer`s and
up: a `page-header` «Search», a GET form (`role="search"`) with the
field and «Search», and under it `search-results`, the results as a list
of links, or «No results for «TEXT»» («Ingen treff på «TEXT»»), or,
under two characters, nothing. An htmx request for part of the page
(`HX-Request-Type: partial`) is answered with `search-results` alone,
which the dialog shows. The page and the fragment ask the `search` tool,
so the three answer the same.

**The tool.** `search` (`query`, 2 to 120 characters; `kinds`, a list
of kinds, all when left out; `limit`, 1 to 20, 20 when left out),
`:viewer`, answers `{"items": [...]}`, each item the result's `kind`,
`kind_label`, `icon`, `title`, `meta` (an array), `matched` (what it was
found by, when neither the title nor the meta shows it, else null),
`href`, `score` and `id` (null when the contributor gave none), under the
caller's authority as the page's.

**`search-results`** is the list: `(search-results (:query TEXT :items
ITEMS))`, ITEMS plists of a result's parts (`:matched` among them). Each
row is a link to HREF: the kind's icon, the title with its marks, and
under it the meta line, which starts with the kind's word, then MATCHED
when there is one, then META («Customer · post@nordvik.example»), marked
as «Why it was found» says,
in `--muted-foreground`, `--text-xs`, cut with «…» at the end of its
line. A row is at least 2.75rem high and pressed (`--pressed`) at once.
`<mark>` stands on the text colour at 14 % (`--foreground` mixed with
transparent; the accent is for focus and what is on, §2.1) in the text
colour, with no padding, so a match inside a word does not split it. With `:listbox t` (the dialog's) the list is a
`listbox` of `option`s, each with an id; the root carries the query it
answers (`data-tun-search-query`).

**`search-dialog`** is the search in a `dialog` of the size `:large`,
titled «Search», with a GET form to `/search` whose field (`type=search`,
`role=combobox`, its label «Search» hidden, `autocomplete="off"`) asks
for the results as one types and a box under it that holds them:

- **The size.** On a phone the dialog is the sheet a dialog to type in
  is (§6 `dialog`): as tall as it may be from the moment it opens, above
  the keyboard. From 40rem, `:size :large` gives a dialog a fixed box,
  `min(40rem, 100% - 2rem)` wide and `min(36rem, 100dvh - 4rem)` high,
  from the moment it opens, so the field never moves as results come
  and go; only the results scroll, inside their box.
- **Asking.** The field carries `hx-get="/search"`, `hx-trigger="input
  changed delay:150ms"`, `hx-target` the results' box, `hx-swap
  innerHTML` and `hx-sync="this:replace"`: htmx itself waits for a
  pause of 150 ms after the last key and drops the request a newer one
  replaces. The page answers nothing under two characters.
- **The latest answer wins.** An answer whose query is not what the
  field holds now, as a slow answer for earlier keys that arrives after
  a newer one, is not shown. An answer that fails (an error status, or
  no answer) shows «The search failed. Try again.» («Søket feilet.
  Prøv igjen.») in place of the results.
- **The keys.** ↑ and ↓ move the mark over the rows (`aria-selected`,
  the field's `aria-activedescendant`), going round at the ends; the
  marked row is chosen: the ground of a row under a pointer (`--accent`)
  and the frame of what is chosen, 1px of `--border-strong` inside it,
  at the weight, size and padding of the others.
  The first row is marked when results come. Enter opens the marked
  row, as a click on its link would (htmx, as any link of the shell); an
  Enter typed before the answer for what the field holds has come waits
  for it, and then opens its first row. Escape closes the dialog, and
  the focus goes back to what opened it.
- **Opening.** Ctrl K and ⌘ K open it (`:shortcut "Ctrl+K"`), and so do
  the top bar's button and the sidebar's row, with the focus in the
  field and what was typed before selected. The dialog stands last in
  the shell, after every dialog of the page, so a page's own dialog
  that opens on Ctrl K, through `staff-page-extras` or in its content,
  opens on it instead, and the search keeps its button and row.
- **The button and the row.** `app-shell`'s `:search` (the page's path,
  `/search`) adds, below 64rem, a ghost icon button «Search» in the top
  bar beside the menu button, and from 64rem a row at the top of the
  sidebar that reads as a field: the search icon, «Search» and the
  caps «Ctrl K» («⌘ K» on a Mac), `aria-keyshortcuts="Control+K
  Meta+K"`. Both are links to `/search`, which a click turns into opening
  the dialog where scripts run.
- **Without JavaScript** the button and the row lead to `/search`, whose
  form is the search; the dialog never opens.

## 7. The specimen

- `/ui` shows every component: its documentation, its source, and each
  example rendered beside its Lisp. `/ui/NAME` shows one. The specimen
  is public; it holds no data.
- A theme switch on the specimen sets `data-theme` and remembers it in
  the browser. It stands in the specimen's top bar right after the
  title, at the start of the row, so a toast (`flash`), which stands at
  the top right from 40rem, never covers it on a wide screen.
- `/ui/choice-input/options?q=TEXT` answers the specimen's asked
  choices with `choice-answer`, from a fixed list of made-up customers,
  eight at a time so its 24 show the «more» line, so its asked examples
  ask a real address; the standalone files cannot ask. The example of a
  find step has a customer chosen, so where scripts run it shows a
  chosen field rather than an empty one; its «Find» step shows without
  scripts.
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
- **The page header.** The title and the actions share one row on every
  screen (§6, `page-header`); on a phone the actions that do not fit fold
  into the «More actions» menu. No page Tun generates or ships (the
  generated lists, records and forms, sign-in and setup, access,
  settings, the offline page, the modules' pages) puts a `:description`
  under a page's or a section's title; what such a sentence said that a
  person needs stands where it is used: in a card's text or an alert,
  or, when it says what a list or a block holds, as the table's caption
  or the code block's title. A live fact of a section (a count, a state)
  is the section's `:meta`, never a badge among its actions; a short
  muted line in the page's flow (under buttons, under a table) is a
  `note`.
- **The frame.** A staff page is an `app-shell` with the menu, the actor
  and «Sign out» («Logg ut»). Its content is at most 72rem wide, 84rem from a
  1440 px window, centred, with more space at the sides the wider the
  window; a page defined with `:width :wide` uses the whole width beside
  the menu, for a board or a wide overview. A client adds components to
  every staff page, after its content, with a method on
  `staff-page-extras`: a dialog with a `:shortcut` (`"/"`, `"Ctrl+K"`)
  opens from anywhere, as a search does. An application with a search
  (§6.4) has its button in the top bar, its row at the top of the
  sidebar and its dialog last in the shell; a page's own dialog on
  Ctrl K comes before it and opens instead.
- **The menu.** First the business's work: the client's own pages in the
  order they are defined, the resources, then the modules' pages and the
  kernel's. Then, under the heading «System», the pages about the system
  rather than the work: those defined with `:group :system` (the
  dashboard's «Jobs», «Errors» and «Log»), then the kernel's «Settings»
  and «Access» («Innstillinger» and «Tilgang» in Norwegian). Each entry
  shows only to those its page's policy admits, so a person who is not an
  admin sees only «Access» there. A page for someone not logged in
  (login, setup, a public page) is an `app-shell`
  without the menu. A page with one short form (login, setup) is narrow
  and centred (`:width :narrow`): the form's card, then
  a card that explains it. Every page starts with a `page-header`.
- **Lists.** The generated list is a `table` of at most five columns: the
  record's name (else its id, linked to its page), then its status as a
  `badge`, the records it refers to by their names, its first date, its
  total, and its other inputs. No records is an `empty-state`.
  Above it stands a `list-toolbar` (§6) of what its list operation can
  filter by: an input named `query` or `q` of text is the search, an
  enum a `:one` filter, a list of an enum a `:several` filter, a boolean
  a `:toggle`, the id of a record the person may choose a `:choice`
  filter (below, «Choosing a record»), and two date inputs named `from`
  and `to`, `since` and `until`, `from_date` and `to_date`, or
  `start_date` and `end_date` (the first such pair) one `:period`
  filter, «Period» («Periode»), after the others; other ids, other
  dates, numbers, other text and `limit` are not offered. A period's
  values go to the operation as the address gives them, read there, and
  one it refuses shows its error at its field too. The address's keys
  are those inputs' names, as an agent passes them
  (`/orders?status=draft&dateless=true&customer_id=cus_12`), and the
  list operation is called with what the address gives, an id as it is
  given, so a value it refuses shows as its error. An operation with
  none of these inputs gives no toolbar. The list's rows, its first 100 records, come in the page's
  answer: nothing loads after it, and it does not page yet (§9). The
  toolbar is
  part of the generated screen: a client's
  `render-screen` method for the list shows it only through
  `call-next-method`. A list filtered to nothing says «Nothing matches»
  («Ingen treff») with «Reset».
- **A record.** A `page-header` (breadcrumbs, the status as a badge in
  its `:meta`, the status operations as buttons, or a `dropdown-menu`
  when there are more than two), a `summary-list` of the fields that have
  a value, a `table` per list of records, and computed JSON in an
  `accordion`, each in a section with an id; with three sections or
  more, `section-links` to them first.
- **Forms.** A control per input, chosen by its type: text, e-mail,
  number, date, a `select` or `radios` (four choices or fewer, required)
  for an enum, `checkboxes` for a list of an enum, a `checkbox` for a
  boolean, a `choice-input` of the records an id refers to (below,
  «Choosing a record»), a `textarea` for
  long text and JSON, an amount (`money`) as a person writes it in the
  page's language, with the currency beside it (`i18n.md` §5.4), and a
  `fieldset` per row of a list of records, its optional inputs folded
  away. A date is a `date-input` and an amount a `money-input` (§6); what
  a person types is posted as typed, and `web-call` reads it into what the
  operation takes (`i18n.md` §5.4, §6.2), so the operation gets
  `YYYY-MM-DD` and minor units, and a text it cannot read comes back in
  its field, as typed, with its error. The description is the hint; an optional input says «(optional)»
  («(valgfritt)»). A form with inputs carries `novalidate`, as
  GOV.UK's do: the server checks every submission, and its answer is
  shown in the page, where the browser's own bubble is easy to miss on a
  phone. A refused submission keeps what was typed, puts each field's
  error at the field and lists them in an `error-summary` that links to
  them, each named by its label; a field of a row of a list of records
  by its row's legend and its label, «Order line 1: Quantity must be at
  least 1» («Ordrelinje 1: Antall …»). A choice left empty (a record's
  `choice-input`, an enum's `select` or `radios`) is refused «must be
  chosen» («må velges») where the operation said «must be filled in»
  («må fylles ut»): «Customer must be chosen» in the summary and «Must
  be chosen» at the field. The kernel refuses an id input given as
  blank text (`""`, or blanks alone) with «must be filled in» («må fylles
  ut»), not «must be a valid identifier», so a page of a client's that
  posts an empty choice reads so too. `""` is refused as before,
  required or not, only in other words, and blanks alone, which passed
  as an id before, are refused the same way: an optional id with no
  value is left out or given as null, and blank text is no id.
- **Choosing a record.** An input that is the id of a record of another
  entity (`(id customer)`), in a generated form and as a generated
  list's filter, chooses among that entity's records by typing, under
  the authority of the person signed in.
  1. **Who chooses among which.** The entity's list operation (its read
     operation whose tool ends in `_list`) decides it: a person whose
     role that operation's policy admits chooses among every record of
     the entity that its record policies let them read (`store.md` §6),
     not the operation's first page; the operation itself is not called.
     For anyone else, and for an entity without a list operation, the
     input is a text field for the id, as before, and no filter.
  2. **A record's text** is what the generated pages show for it
     wherever they name it (a table's cell, a record's details, the
     field, the filter's button): its `name` field when the entity
     stores one and it is filled, else its id. Only a record the person
     may choose (1) is named: one a record policy hides from them, or of
     an entity whose list operation's policy does not admit them, is
     shown by its id, never by its name. The names a page shows are read
     once for each entity it names records of, in the same read as a
     choice's (4), so with 2000 records they add less than 50 ms to the
     page. A choice finds a record
     by the search's rule (§6.4) with that text as its one name and its
     id as its one identifier: «bjorn ase» finds «Bjørn Åsen», and a
     pasted id its record; no other field is read or searched, unless a
     module shapes the choice (below). The
     records come in the order of their names (the store's order of the
     `name` field), or as they were made when there is none.

     **A module shapes the choice.** `(record-choice APPLICATION
     ENTITY)`, a generic function in `TUN` (ENTITY an entity's class
     name), answers how ENTITY's records are named, found and offered,
     as a property list of what it changes: `:fields`, the JSON names of
     every field the other keys' functions read; `:text`, a function of a
     record that answers its text (a blank text gives its id); `:names`,
     `:texts` and `:identifiers`, functions of a record as `search-match`
     takes them (by default the text as its one name and nothing more),
     its id always one of its identifiers too; `:keep`, a function of a
     record, true for one to offer; and `:order-by`, as `select` takes
     it. Tun's own method, the least specific, answers NIL: the `name`,
     else the id, as above. A module specialises it on its mixin, an EQL
     specialiser for its entity, and a client on its application class
     or a feature, which wins over a module's; a method answers its keys
     before `(call-next-method)`'s, `(list* :text #'display-name
     (call-next-method))`, so a key it does not give stays the less
     specific method's. A method runs in the request's read transaction
     with `*actor*` bound. The records are read once a request in one
     `select` of their id and `:fields` (4). A record `:keep` does not
     keep is not offered (not among the options, not found, not counted
     by the rule of 30, and its posted id is refused as one that is none
     of the choices), but where a page names it (a cell, a record's
     details) it is named by its text, so an order of a customer erased
     since shows the customer's name. The generated pages have no form
     that edits a record (their forms create one, and a record's actions
     take no inputs), so a kept-out record is never the value a form of
     theirs already had; a page of a client's that edits one and checks
     the posted id with `read-choice` gives the record's current value
     among its options, so saving it unchanged is accepted. Tun's
     customers module names a customer by its `name`, finds it by its
     email and its phone in the forms `search-phone-forms` gives too, as
     its search does, and keeps an erased customer out:

     ```lisp
     (defmethod record-choice ((app customers-module) (entity (eql 'customer)))
       (list* :fields '("name" "email" "phone" "erased")
              :identifiers (lambda (c) (list* (customer-email c)
                                              (search-phone-forms (customer-phone c))))
              :keep (lambda (c) (not (customer-erased c)))
              (call-next-method)))
     ```

     A module or client that wants a choice no record of one entity
     answers (one among several entities' records) still writes its own
     page with `choice-input` and an address that answers with
     `choice-answer`.
  3. **Few or many.** When the person may choose among at most 30
     records, the field and the filter hold all of them with the page
     (`choice-input`'s and a `:choice` filter's options without SOURCE,
     narrowed in the browser; without JavaScript a `select` of them,
     as before). With more, they ask `/choices/ENTITY` as one types
     (SOURCE), and the page holds only the chosen record and, after a
     «Find» step, what it found.
  4. **The address.** `/choices/ENTITY?q=TEXT`, ENTITY the entity's JSON
     name (`/choices/customer`), is a kernel page for `:viewer`s and up,
     out of the menu. It answers with `choice-answer` from the records
     of (1) and (2): the first 20 by the rule, the rest counted, the
     fragment to htmx and a page «Choices» («Valg») to any other request.
     A person whose role the list operation's policy does not admit gets
     403; an entity that does not exist or has no list operation, a path
     without ENTITY or with more, and a POST get 404. It reads the
     records once, their id and `name` alone, or their id and the
     `:fields` of `record-choice` (`select`'s `:fields`, `store.md` §2,
     item 11); with 2000 records it answers within 100 ms on the server,
     in memory and on Postgres, the customers module's four fields
     included.
  5. **The form.** The field is a `choice-input` named as the input,
     required as it is. Without JavaScript a many-records field has its
     «Find» step: the form is shown again with the matches in its select
     and «N found», nothing saved, with status 200. Before the operation
     is called, every posted id of such a field, a row's of a list of
     records too (an order's lines), is checked with `read-choice`
     against the records the person may choose: an id that is none of
     them (one that does not exist, or one a record policy hides from
     the person, or one `record-choice` keeps out) is refused at its
     field, «must be one of the choices»
     («må være et av valgene»), in the form's `error-summary`, with
     status 422, and the operation is not called.
  6. **The list's filter.** A `:choice` filter labelled as the input,
     its address a `:one` filter's of the input's name
     (`customer_id=cus_12`), its «Find» text `NAME-find`; «Reset» names
     it too. Its button names the chosen record's text; an id in the
     address that is none of the person's choices is passed to the
     operation as given (above) and its button shows the id.
- **Values.** In the page's language and the tenant's currency and time
  zone (`i18n.md` §5.4, §6.2), the page's language being the tenant's: amounts as `€12,450.00` or `12 450,00 kr`,
  dates as `21 Oct 2026` or `21.10.2026`, instants in the tenant's time
  zone; stored words by their label, `quote_sent` as «Quote sent»
  («Tilbud sendt»); references by the record's name.
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
     the policy admits (`:employee` when omitted). Someone not logged in
     goes to the login and back (`auth.md` §3.4); a person the policy
     does not admit gets the 403 page. TITLE and ICON are its menu entry; `:navigation nil` keeps
     it out of the menu.
  2. NAME is a function of the request. METHOD is `:get` or `:post`, PATH
     the parts after the prefix (`/saker/sak_1` gives `("sak_1")`), FORM
     and QUERY the posted and the query parameters as JSON objects. A
     post's files arrive in FORM as `files.md` §6.2 says. A query key
     given once is a text; given more than once, as a `:several`
     filter sends it, an array of its texts in order.
     `(query-values QUERY KEY)` gives a key's values that are not empty,
     as a list, from either.
  3. It returns `(values STATUS TITLE BODY)`, BODY a list of components
     shown under a page header with TITLE, and may add a fourth value, a
     plist of the header's `:description`, `:meta`, `:actions` and
     `:breadcrumbs`. `(values 303 PATH)` sends the browser to PATH, as a
     successful post should.
  4. `web-call TOOL ARGUMENTS` calls an operation as the logged-in
     person, through the execution path. It returns the result, or the
     error document and its code; `error-alert` shows that document.
     An operation error the page does not catch is shown as that alert,
     with the code's status. `(error-alert JSON :fields FIELDS)`, FIELDS
     the form's fields as the components make them (the nodes the page
     puts in its form), names each of the document's field errors by the
     label the form shows for that field, in the page's language, and
     makes its line a link to the field's control (`#ID`, as
     `error-summary`'s links are: where scripts run the focus goes to the
     control with its label in sight, and without them the browser goes
     to it). The field of an error is the one whose control is posted
     under its path: `starts_on` names the control `starts_on`, a row's
     `lines[2].unit_price` or `lines.2.unit_price` the control
     `lines[2][unit_price]`; its label is its `field`'s, without
     «(optional)», and that of `radios` or `checkboxes` their legend. A
     row's field is named by its row and its label: «Line 3: Unit price
     must be at least 0», «Line 3» the legend of the `fieldset` the
     control stands in, else «Row 3» («Rad 3»). An error whose path no
     control in FIELDS is posted under is written as without FIELDS: its
     path and its message, with no link. Without FIELDS the alert is as
     it was. A page that builds its fields first passes them to both:

     ```lisp
     (let ((fields (order-fields values errors)))
       `(:form (:@ :method "post" :action "/orders/new")
               ,(apply #'ui:stack* (list :gap :lg)
                       (append (when problem (list (error-alert problem :fields fields)))
                               fields
                               (list (ui:form-actions () (ui:button (:type "submit") "Save")))))))
     ```

     `timestamp-text`, `date-text`,
     `money-text` and `number-text` write a value as the generated pages
     do (`i18n.md` §6.2). `(query-address PATH PAIRS)` writes an
     address: PATH and PAIRS, `(KEY . VALUE)` conses, as its query, each
     key and value percent-encoded as UTF-8 (as Tun writes its own
     links); a VALUE that is a list gives the key once for each of its
     values, NIL leaves the pair out and an empty text keeps it, as a
     cleared filter is named; after `?`, or `&` when PATH has a query
     already, and PATH alone without pairs.
  5. Evaluating the definition again, in a running server too, replaces
     the page; another definition with the same prefix is refused, as
     two modules' pages are.
  6. A page answers an htmx request for part of a page as §8.1 says.
  7. `:remembers '("prosjekt" "status")`, a list of query keys, makes
     the page remember them for each account, so a person who leaves a
     list filtered finds it so again, on any device. A GET of the page's
     own path (`/saker`, not `/saker/sak_1`) whose query has any of the
     keys saves their values for the signed-in account, in place of what
     was saved: a key absent or empty is saved as cleared, and a key given
     more than once keeps its values that are not empty, which the
     address it is sent to names each in turn. A GET of the
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
- **Home.** `/` sends a person who is signed in to their home page, and
  so does a sign-in that was not asked to return to a page (`auth.md`
  §3.4). Someone not signed in who opens `/` goes to `/login`, and
  their sign-in then lands on their home page. A sign-in that sets up
  the first admin goes to `/access`, as before (`auth.md` §3.5).
  1. **The default.** Tun's own home page is the first resource with
     record pages, else the first resource, else the first page in the
     menu the person sees, else `/access`.
  2. **The option.** `(:home "/today")` in `define-application` names the
     home page for everyone. The path starts with one `/`, is not `/`
     (alone or with a query or fragment), and is a path a `next` may be
     (`auth.md` §3.4: no `\`, no control character, at most 2000
     characters, not a step of signing in); anything else is refused
     when the client is compiled.
  3. **The seam.** `(home-path APPLICATION ACTOR)`, a generic function in
     `TUN`, answers the home page for ACTOR: a path, or NIL for no
     answer. Tun's own method, the least specific, answers the `:home`
     option, or NIL without one. A module specialises it on its mixin
     and a client on its application class or a feature, and CLOS runs
     them most specific first: the client's, then the modules', then
     Tun's. A method that does not decide for ACTOR returns
     `(call-next-method)`. So a module's answer wins over the option, and
     a client's method wins over both and chooses, by calling
     `call-next-method` or not, whether a module may answer. A method
     runs in a read transaction with `*actor*` bound to ACTOR, so it may
     read the store (`select`, `fetch`).

     ```lisp
     (defmethod home-path ((app setup-module) actor)
       (if (and (eq (actor-role actor) :admin) (not (setup-completed-p)))
           "/company/setup"
           (call-next-method)))
     ```
  4. **Only a page the person can open.** An answer is taken when it is a
     path a `next` may be and is not `/` (2), and its first segment is a
     page the application serves and ACTOR's role opens: a staff page (`define-page`, a module's or the kernel's,
     such as `/access`) of a module the application enables, whose
     policy admits ACTOR, or a resource's list or record. An answer that
     is not taken, such as a page for admins answered for an employee,
     another site or a page that does not exist, is written to the
     server's error output, and Tun takes the `:home` option instead
     when ACTOR can open that, else the default (1). So `/` never sends
     a person to another site, to a page their role is refused, or back
     to `/`.
  5. A client with no `:home` and no method of its own, whose modules
     have none, sends everyone where Tun's default (1) does, as before.
- **Public pages.** A page a customer opens without signing in (a
  quote, a feedback form, an unsubscribe link) is registered by a module
  or a client with `(register-public-page PREFIX HANDLER)`, in `TUN`.
  1. It serves `/PREFIX` and every path under it to anyone, signed in or
     not, with `Referrer-Policy: no-referrer`. HANDLER is called with
     METHOD (`:get` or `:post`), the path's parts after the prefix, the
     posted form as a JSON object, and a session, a JSON object the
     orders module keeps for an offer, which a client ignores. No
     transaction is open around it (a module's handler opens its own),
     and it returns `(values STATUS TITLE BODY)`, BODY a list of
     components under a page header with TITLE. An operation
     error it does not catch is shown as an alert with status 422. A
     second registration of the same prefix is refused.
  2. **The frame.** The page is an `app-shell` without the menu (above,
     «The frame»), its title linking to the page itself: `/PREFIX/ID`
     for every step under it. The title is what
     `(public-page-title APPLICATION PREFIX)` answers, its first letter
     the mark, and the document's `<title>` is «TITLE – that answer».
     Every answer of the page, its own 404 or 410 and the 422 above
     included, has that frame.
  3. **The seam.** `public-page-title`, a generic function in `TUN`,
     answers the name a customer sees: Tun's own method, the least
     specific, answers `(application-title APPLICATION)`, so without
     another a public page shows what it always did. A module
     specialises it on its mixin, and a client on its application class
     or a feature, which wins over a module's and reaches it with
     `(call-next-method)`; PREFIX lets a method answer for some pages and
     pass on for others. It is asked once for each answer of a public
     page, after HANDLER, in a read transaction with the request's
     application bound and `*actor*` the request's (NIL for someone not
     signed in), so it may read the store and the tenant's settings;
     nothing is kept between requests.

     ```lisp
     (defmethod public-page-title ((app company-module) prefix)
       (declare (ignore prefix))
       (or (company-name) (call-next-method)))
     ```
  4. **Fallbacks.** An answer is trimmed of surrounding whitespace and
     written as text, escaped. NIL, an empty or a blank answer gives
     `application-title`. Any other answer that is not text, or a method
     that signals an error, gives `application-title` too and is written
     to the server's error output with the prefix; the page answers as
     it would without the method.
  5. Only public pages use it: staff pages, sign-in, setup, the web
     app's manifest and every text that names the application keep
     `application-title`.

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
- Charts other than one line over time: several series in one chart
  (comparing shares, a moving average), bars, areas, stacks, scatter, and
  a chart's own time range control.
- A choice among more than one entity's records in the generated pages
  (§8, «Choosing a record»).
- Near matches in a choice for a word typed wrong (as in the search),
  and muted text inside a table cell: a cell holds its value in the text
  colour (a quieter fact is a column of its own, or `:narrow nil`).
- A date and a time in one field, a time
  picker, week numbers in the calendar, and a choice of the week's first
  day or of month-first dates.
- htmx's own extensions (server-sent events, the head merge,
  morphing).
- Paging the generated list: it shows its first 100 records.
- Path patterns with typed parameters for pages (`/saker/:item`), and
  links that name their page (`docs/roadmap.md`).
- In the search (§6.4): near matches for a word typed wrong, an index of
  the searched texts (Postgres's trigrams) in place of reading a kind's
  records, the open search in the page's address, what was searched
  before, filters inside the search, places in the menu as results, and
  full text of long texts.

## 10. Evidence

- `tests/ui-tests.lisp`: every component has its documentation, source
  and examples; every example renders, in English and in Norwegian
  without a missing translation, and in the pseudo-language with no text
  that was not looked up (`i18n.md` §3.7), and renders the same in
  extension output (only allowed markup); every selector is scoped to
  its component; the stylesheet, the script and htmx are served with
  their hash and cache headers; pages have the viewport tag and htmx's
  configuration; the allowed htmx attributes pass extension output, with
  `:inherited`, and others (`hx-on`, `data-hx-on`, `hx-headers`,
  `hx-status`, an unknown modifier, a `javascript:` `hx-get`) do not;
  in extension output, `href` keeps a `mailto:` address in any case,
  while `src`, `action`, `formaction`, `hx-get` and `hx-post` refuse it
  and `href` still refuses `javascript:`; no URL attribute keeps `//host`,
  `/\host`, or a path holding a tab, a line break or another control
  character.
- `tests/ui-data-tests.lisp`: the board's columns, counts, cards, move
  menus and their forms, and a board without an action; an ordered
  board's `before`, its «Rekkefølge» items and what each posts, its
  status region, and a board without `:ordered` posting as before.
- `tests/markdown-tests.lisp` (`markdown`, §6.2):
  - each block and inline rule, with `:heading-level`;
  - HTML and script in the text shown as text, and the links that make
    none (`javascript:`, `data:`, `vbscript:`, `//host`, a relative path,
    `/\host`, a path with a tab in it, one over 2048 characters);
  - an address with parentheses inside it;
  - unterminated marks: a fence, `**`, a backtick, a `[` and a
    `[text](`;
  - plain text giving paragraphs and line breaks, every character as
    written;
  - a fence, a rule, a table and plain text written with CR LF, and
    with CR alone, read as with LF, no CR shown;
  - a table of ten columns, rows shorter and longer than its headings,
    and one of 21 columns that stays a paragraph;
  - a very long unbroken line;
  - the output rendered alike in extension output, `mailto:` kept;
  - texts of 64 KiB built to be costly rendered within a second, and
    the time for four times the text at most about four times as long;
  - a link in bold in a link's text left as text, a code block's tabs
    kept, a list line ending a table;
  - thousands of random texts of marks rendered without an error, their
    output within a constant times their length.
- `checks/showcase/checks/markdown-fits-a-phone.py` (`/markdown`): at
  320px, 390px and on a desktop, the page does not scroll sideways with a
  table of ten columns, a long unbroken line, a long code line and a long
  URL; on a phone the ten columns are cards, each value under its
  heading, and a table of three columns stays a table; on a desktop the
  ten columns are a table scrolling in its own box, and the code block
  scrolls in its own.
- `tests/graph-tests.lisp` (`graph`, §6.3): the layout's layers, a
  chain on one row, nodes without edges in a row of their own, a
  source next to its successor, long edges through empty places,
  places never shared, crossed edges uncrossed, a cycle reversed and
  marked, and the same layout every time; the nodes' states, words and
  tones, a node's long edges sharing their empty places, the badges'
  kinds, tones and links, which badges a node shows and its «+N», the
  two forms and their breakpoint, rows leaning to the top, the list's order and its rails' lanes and
  ends, the edges drawn and
  reversed, the table, no nodes, the bounds refused, Norwegian, and
  the largest graph allowed within a second.
- `checks/showcase/checks/graph.py` (`/graph`): at 1280px every graph
  on the page is a drawing, and light and dark, every edge's ends at
  its nodes' sides, a reversed one below their middles, no nodes
  overlapping, no row empty across the 48-step drawing, the stripe in
  the state's colour, the agent's dot and ring, each badge wholly inside
  its node or, alone too long for its line, ending in an ellipsis; at
  390px every graph on the page is a list, the 48-step one's nodes at
  least 12rem wide; at both, the page does not scroll sideways; the
  table's rows, a node's and a badge's links; without the script the
  forms and the table work the same.
- `checks/showcase/checks/graph-plan.py` (`/graph`, the shape of a real
  plan of 30 components): at 390px, light and dark, it is a list of all
  30 nodes that starts at its first node with nothing empty between
  them, neither the page nor the list scrolling sideways; each
  arrowhead's tip and each dot's line at its node's left side; at least
  28 titles whole in two lines, and every state word and META whole;
  «+2» on `accounting-port`, «+1» on `order-lifecycle` and no «+N» on
  `orders`, whose two badges fit; every badge wholly inside its
  node but the one too long for the line alone, which ends in an
  ellipsis with its whole text in its `title`; at 1280px it is a
  drawing scrolling sideways in its box, with at least 24 titles whole,
  every state word and META whole, the first layer's node
  (`module-layout`) in its first two rows, and at least six nodes in
  the box's first 600px.
- `tests/rank-tests.lisp`: `rank-between` (`core.md` §2.6).
- `tests/chart-tests.lisp`: the y axis's ticks (multiples of a round
  step, three to five, their decimals, equal values), the x axis's labels
  (days, full dates across a new year, times of day, distinct, one
  point), the values written with `:digits`, no points, one point and
  points out of order, the bounds refused, the sparkline's label in
  Norwegian, and `preserveAspectRatio` in extension output while `style`
  and `<text>` stay out; `tests/i18n-tests.lisp`: `day-text` and
  `number-text` with `:digits`.
- `checks/showcase/checks/price-chart.py` (`/prices`): at 320px, 390px and
  on a desktop, light and dark, the line fills the plot at 2px in
  `--chart-1`, the dot is round, the x labels do not overlap, the labels
  are `--text-xs`, the page does not scroll sideways and a sparkline is
  6rem wide with its label; a pointer and the keys show the tooltip and
  the live region, Escape hides it; without the script the chart is
  drawn, the plot is not focusable and the table opens.
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
- `tests/home-tests.lisp` (§8, «Home»): without `:home` and methods `/`
  and a sign-in lead where they did; `/` without a sign-in goes to
  `/login`; `(:home PATH)` sends `/`, a claimed sign-in and a provider's
  sign-in there; a module's method wins over the option and a client's
  over both, calling `call-next-method` or not; a method reads the store
  with `*actor*` bound; an answer that is another site, `/`, a step of
  signing in, a page that does not exist, a page of a module the
  application does not enable or one the actor's role is refused is not
  taken, and the option or the default is; a `next` kept still wins; a
  `:home` that is not such a path is refused when compiled.
- `tests/public-title-tests.lisp` (§8, «Public pages»): without a
  method, a public page's title, mark and `<title>` are
  `application-title`'s; `public-page-title` and `register-public-page`
  are in `TUN`; a module's method answers and a client's wins over it,
  with `call-next-method`, for the prefixes it chooses, reading the
  store; the answer is escaped and trimmed; NIL and blank answers fall
  back silently, a non-text answer and an error fall back and are
  written to the error output, and the page answers as without the
  method; a 404, a 410 and the 422 of an uncaught operation error have
  the answer; staff pages, `/login` and the manifest keep
  `application-title`; two applications served at once each show their
  own answer, and a change to the store shows on the next request.
- `tests/ui-look-tests.lisp` (§2.1, §3): the token values of §3 in both
  schemes; every edge in the stylesheet 1px but the marks named in §2.1;
  every radius a token, `0` (a button group's joins) or `inherit`, and
  the radius tokens' values; no `text-transform: uppercase` and no
  positive `letter-spacing`; `--focus-ring`'s shape, and every
  `:focus-visible` box-shadow one of the two rings; every `:hover` inside
  `(hover: hover)`; no rule whose selector chooses (`aria-selected`,
  `aria-current`, `aria-pressed`, `aria-checked`, `aria-expanded`,
  `aria-sort`, `:checked`) sets a font weight, a font size, a padding,
  a margin, a width, a height or an edge's width, but on a mark
  (`::before`, `::after`); every transition's duration a token; the
  destructive button with no fill and the confirm panel without a red
  one; an icon-only outline button frameless by its attributes; and the
  contrast, computed from the token values, of the text, the muted text
  and the accent on the page, the panels, the chrome and a field's
  ground, of each badge tone's text on its ground and of
  `--STATUS-foreground` on `--STATUS`, in light and dark.
- `checks/showcase/checks/ui-look.py` (§2.1), on the specimen (`/ui/NAME`):
  at 390 and 1280 px, light and dark, every box with an edge on all four
  sides has no square corner (a button group's inner sides excepted);
  pressing each tab of `tabs` leaves every tab's box where it was;
  the chosen tab, the current `nav-list` entry and the current page of
  `pagination` have the weight of their siblings; on a phone every
  button of the specimen's `button` page is a target of at least 44px
  each way; the destructive button has the page's ground and red words;
  on `/ui/button` the icon-only outline «Edit» has a transparent edge and
  ground at rest, and the current page «2» (outline, `:icon`,
  `aria-current`) its edge; on `/ui/button-group` an icon-only outline
  part keeps its edge and ground; a focused button shows the two-ring shadow; the app shell's
  sidebar stands on `--chrome` and the menu's headings are not in
  capitals on a staff page; and no page scrolls sideways.
- `tests/ui-sheets-tests.lisp` (§2.1 «What opens moves into place», «The
  dim only gets darker», §6 `dialog`, `confirm-dialog`, `flash`): the
  CSS of `dialog`, `confirm-dialog`, `dropdown-menu`, `combobox`,
  `tooltip` and `flash` where they open animates only `opacity` and
  `translate` (with `display`, `overlay`, `visibility` and
  `content-visibility`), with no `scale`, `transform` or keyframes,
  and each has a leaving transition over `--duration-close`; the sheet's
  box, corners, strip, pinned parts and full height for a field; the
  dialog standing inside `--tun-visual-top` and `--tun-visual-bottom`;
  `--overlay` and the backdrop's one fade; `:popover-open` and `:modal`
  named only in the kit's guarded helpers; the `confirm-dialog`'s
  markup in English and Norwegian, `confirm-attributes`, one in every
  `app-shell`; the flash's roles, its `:toast nil`, its leaving after 5
  seconds for success and info only.
- `checks/showcase/checks/ui-sheets.py`, on the specimen: at 390 px a
  dialog's box at the bottom, full width, top corners rounded, bottom
  ones square, below the strip; its header and footer where they were
  while its body scrolls; a dialog with a text area as tall as it may
  be at once; with the visual viewport shrunk as a keyboard does, the
  dialog's bottom edge, its footer and the focused field above it, and
  the page not scrolling behind; at 1280 px the dialog centred; at both,
  the backdrop's opacity never falling while it opens nor rising while
  it closes, light and dark; a closing menu still in the page midway
  and gone after `--duration-close`; the focus on opening and back on
  closing, Tab going round, Escape closing the top one only; the
  `confirm-dialog`'s question, sentence, action words and red words,
  its focus, Escape and «Cancel» running nothing, the action posting a
  form once and sending an `hx-confirm` request once; the flash as a
  toast at the bottom and at the top right, leaving after 5 seconds and
  not while pointed at, a warning staying; under reduced motion nothing
  moving; without JavaScript the flash in the page and a dialog's form
  posting.
- `tests/ui-header-tests.lisp` (§4.2, §6 `page-header`, `section-links`,
  `summary-list`, `tabs`, `app-shell`, §8): the header's row and the
  filled actions last in the markup; which actions fold for which titles
  and actions, the menu's items (words, icon, link, form, attributes,
  destructive) in English and Norwegian, a filled action's icon alone,
  nothing folding of another kind; `:meta`; the shell's grounds and edges
  and the menu's dim; the theme colours' defaults equal to `--chrome`'s
  two values in the stylesheet; `section-links`' markup and its marked
  link's CSS; the facts' CSS without lines; `tabs`' frame and chosen
  ground; no call in `src/` and `modules/` (but `src/web/ui/`) of
  `page-header`, `section`, `respond` or `guest-page`, of `page-header*`
  or `section*` with a literal plist, or a page's fourth value, holding
  `:description` with any value but the variable `description` passed on
  (`respond` passes a client page's on); a client's description still
  rendered; the generated record's status in `:meta`; the flash after an
  account is created in the page's flow.
- `checks/showcase/checks/ui-header.py`, on the specimen and the
  showcase: at 390, 360 and 320 px a long title, and a title of one long
  word, with three actions on one
  row with the «More actions» button and the filled action, the filled
  action's right edge the header's, no other action shown, the menu
  holding the folded actions, and with JavaScript off the menu opening;
  at 1280 px every action shown, no menu; `/items` keeping its three
  actions on the title's row on a phone; the top bar's ground equal to
  the `theme-color` of the active scheme, light and dark, and the
  sidebar's to `--chrome`; `section-links` one line scrolling in its own
  box, its link marked as the page scrolls and when followed, at the
  others' weight, and none marked without JavaScript; the facts in one
  column on a phone and two on a desktop, without an edge, in line with
  the header; the chosen segmented tab's ground unlike the page's, light
  and dark; no page scrolling sideways.
- `tests/ui-filters-tests.lisp` (§6 `list-toolbar`, §8 «Lists» and
  QUERY): the toolbar's form, search, buttons, popovers, choices and
  hidden fields in English and Norwegian; a filter in use, its words, its
  clear link and «Reset» from two in use, both naming every key and
  clearing a `:remembers` page; the «Filters» button and its
  sheet from three filters, with the count; fixed ids; the CSS that
  chooses without a change of weight, size or edge; a repeated key in
  QUERY, `query-values`, a `:remembers` page keeping and restoring one;
  the generated list's toolbar from the test client's orders and
  customers, the operation called with the address's values, «Nothing
  matches», and a client's screen method without it.
- `checks/showcase/checks/ui-filters.py`, on the showcase's `/cards` and
  `/customers` and the specimen: at 1280 px the search and the buttons on
  one row; putting a filter into use leaving the row's height and the
  list's top where they were; a choice changing the address and the list
  without loading the page, the several popover open with the focus on
  its box, the one popover closed with the focus on its button, Back
  going a choice back and then off the list; the popover under its button
  and its motion; at 390, 360 and 320 px the «Filters» sheet's box, dim,
  rows, a choice applying with the sheet open, Escape and the focus back,
  a floating popover inside the window, and no page scrolling sideways;
  without JavaScript, at 390 px every filter's button shown, a popover
  opening and «Apply» filtering the list.
- `tests/ui-fields-tests.lisp` (§6 `date-input`, `time-input`,
  `money-input`, the period of `list-toolbar`, §8, `i18n.md` §6.2):
  every accepted and refused form of a date and a time read by
  `read-date-text` and `read-time-text`, every day of 2024 to 2027 in
  each accepted form and random texts of digits, separators and month
  names read without an error; a date read over a page and not over MCP;
  `period-text` in both languages; the three fields' markup, hints,
  errors, values and calendar in English and Norwegian; the calendar's
  CSS that opens and closes as §2.1 says, and its chosen and today days
  without a change of weight or size; the generated form's date and
  amount fields, a typed date, an ISO date and a refused one posted; the
  period's keys, links, quick choices, summary, errors and sheet row; the
  generated list's period from the test client's orders.
- `checks/showcase/checks/ui-fields.py`, on the showcase's `/fields` and
  `/days` and the specimen: in English and Norwegian, each accepted form
  typed and posted read as its date, and the time and amount forms; a
  refused date shown again as typed with its error; the calendar's roles
  and names, its first weekday, today and the chosen day at the others'
  weight, the keyboard walk, min and max, choosing, Escape and the focus
  back; its box under the field at 1280 px and inside the window as a
  floating sheet at 390, 360 and 320 px, its transition's properties and
  durations opening and closing; the money field right-aligned in tabular
  figures; the period's quick choice, a calendar choice and a typed date
  each changing the address once, Back stepping through them, the
  «Filters» sheet's row; without JavaScript no calendar button, the
  fields posting and the period applied by «Apply» and by a quick choice's
  link; no page scrolling sideways.
- `tests/ui-lists-tests.lisp` (§2.1, §6 `table`, §8 «Lists»): a
  table's cells hold their content and no card's labels; the first
  cell's text in its own part, the row's one link in it; `:narrow nil`
  marked on a column's header and cells; the empty row's text in its
  part; the CSS of a phone's panel, its lead of two lines, the pressed
  row only while its link is pressed and at once, the hover where a
  pointer hovers, the edge shadows, and no card layout left; the old
  options accepted; a page title's `hyphens: auto`; the generated list's
  rows in the page's first answer, with no part that loads after it.
- `checks/showcase/checks/ui-lists.py` (§6 `table`), on the specimen's
  `/ui/table` and the showcase's `/cards`: at 390, 360 and 320 px no page
  scrolling sideways, the table's box at the toolbar's and the header's
  left and right edges, a row's cells on one line, a link row at least
  44px and eight rows of `/cards` at most 448px high, the amounts'
  right edges equal, the lead at most two lines and the amount column
  reached by scrolling the table's box; at 1280 px every column in sight;
  a row's link covering the row, the row pressed at once, a focused row
  showing the inset ring, an inner link followed without the row and an
  inner menu's button opening its menu without the row; a sort link
  changing the address, keeping the toolbar's filters, the rows staying
  and the loading sign showing while a slow sort or filter answer comes,
  and the sorted header at the others' weight; without JavaScript a
  tap on a row and a sort link working.
- `tests/ui-layout-tests.lisp`: every `app-shell` holds the loading
  sign hidden and `aria-hidden`, and an empty `role="status"` region
  with «Loading…» in the page's language to say; the script and the
  stylesheet hold what §4.1 «The loading sign» describes.
- `checks/showcase/checks/loading-sign.py` (§4.1, «The loading sign»),
  on the showcase's `/wait`, which answers after `?ms=`: at 390 px, a
  link to a fast page and a part that loads by itself never show the
  bar; a link to a page that waits 1.5 s shows nothing at 150 ms, then
  the bar across the width and the region saying «Loading…» once, from
  300 ms after the press, and neither once the page is swapped in; a
  slow form shows it and clears it, and so does one cancelled with
  `htmx:abort`; a request that fails on the network and a 500 answer
  show it and leave no bar; after a slow link and then a fast one, and
  after Back to a boosted page while a slow page loads, it stays while
  the slow request is under way and goes when it ends; a pointer resting
  on a slow link preloads it and shows nothing; in the dark at 1280 px
  it shows; under reduced motion it stands still; without JavaScript it
  is hidden.
- `checks/showcase/checks/home-page.py`: the showcase's home for
  everyone is «Graph», and an admin's is «Welcome» until they finish
  it; at 390 px, an employee opening `/` and an admin signing in land
  there, the admin goes on to «Graph» after «Done», and a sign-in from
  a page returns to that page.
- `checks/showcase/checks/public-page-title.py`: at 390 and 1280 px,
  the showcase's `/quote/q1` shows its setting's company name as the
  shell's title, its first letter as the mark and in the tab's title;
  `/notice` and a staff page show the application's title; nothing
  scrolls sideways.
- `tests/web-app-tests.lisp`: the `:web-app` options and icons are
  checked; the manifest, the icons, the offline page and the service
  worker are served without a login, with their types and cache
  headers; every page's head carries the tags; the worker keeps the
  current assets and the offline page and nothing else; without
  `:web-app` there is no manifest and the worker removes itself; a
  client's page cannot take the paths. `push.md` §10 has the evidence
  for push notifications.
- `tests/search-tests.lisp` (§6.4): the fold, the words, the
  identifiers and every score of the rule, and a property: thousands of
  random records found by their own words folded, reordered, cased and
  accented, by each word's start, and not with a word they lack; the
  marks on the stored characters; `search-records` in `TUN`, traced and
  listed, a module's and a client's results both kept, the client's
  first; the order, five of a kind and twenty in all; results only for
  what the actor may open, for an employee and an admin, a client's own
  page kept, and by the record policy on Postgres; the tool's `kinds`
  and `limit`, and the inputs it refuses; the customers' and the orders' results; no
  button, dialog or `/search` without a contributor; the shell's
  button, row and dialog, the dialog after a page's own Ctrl K dialog;
  the page, the fragment and the `search` tool answering the same for
  one query; the CSS of the marked row, the mark and the large dialog;
  2000 customers searched within 100 ms, in memory and on Postgres.
  `search-replacements`: in `TUN`, traced and listed; with a feature
  answering customers in place of the customers module, no select of a
  customer and no query of their table for an admin, an employee or a
  viewer, the feature's customers found and the module's not, and
  without it one select a search; a replaced module's result made
  without asking dropped, its other kinds and other contributors' kept,
  an entry naming no module written out and ignored. `select`'s
  `:fields` on each store, and `search-entity` with it. `search-among`
  over records, JSON objects and property lists. A property test of the
  fast rule against the plain one (2.32.0's code, in the test): folds,
  scores, marks and results the same over thousands of random records
  and queries. The phone forms of numbers from four countries and one
  without a code, found by their national numbers and not from their
  middle, and the national part marked in a result's line. 2000
  customers, 2000 orders and 2000 records with long texts searched
  within the test's limit, in memory and on Postgres.
- `checks/showcase/checks/ui-search.py` (§6.4), on the showcase, whose
  cards and customers are found: Ctrl K and ⌘ K open the dialog with
  the focus in the field, the caps read «⌘» on a Mac; at 1280 px the
  dialog's box the same with no results, with «No results» and with
  the most it finds; results within a bound of the last key, the match in a
  `<mark>`; the arrows moving the mark at the others' weight and size,
  Enter opening the marked row, an Enter typed at once opening the
  latest answer's first row; a slow earlier answer never shown over a
  later one; a failed answer saying so; Escape closing with the focus
  back; on `/items` Ctrl K opening the page's own dialog; at 390 px the
  top bar's button opening it as tall as it may be and above a keyboard;
  without JavaScript the button leading to `/search` and its form
  listing the results; the server's time for the showcase's searches.
- `tests/ui-nits-tests.lisp` (§6 `summary-list`, `section`, `note`,
  §6.4 «Why it was found», §7): the label column's width, its
  `hyphens: auto` and `overflow-wrap: break-word`; a section's `:meta`
  under its heading, before its actions, in the header's look, and none
  without it; `note`'s markup and its muted colour and size; a result
  found by its META marked there and not when its title is marked, an
  identifier marked over the characters it covers, MATCHED for an order
  found by its address and none when META shows it, its excerpt of a
  long text, a result made without `:matched`; the `search` tool's
  `matched`, and the page, the fragment and the tool agreeing on it.
- `checks/showcase/checks/ui-nits.py`, on the specimen and the
  showcase: at 320, 360 and 390 px no label's text of the specimen's
  summary lists and of a card's page in Norwegian reaching into its
  value's box, a long label whole when its words fit its column in the
  browser's font and broken when they do not, the column 10rem at 390 px; a
  section's `:meta` under its heading on the specimen and a card's page;
  `note` in the muted colour; typing «ex» in the showcase's search
  marking «ex» in each customer's line; at 1280 px the specimen's toast
  and theme switch not overlapping, and «Dark» pressed while the toast
  shows turning the page dark; no page scrolling sideways.
- `tests/ui-choice-tests.lisp` (§6 `choice-input`, `choice-options`,
  «Answering a choice», `list-toolbar`'s `:choice`, §7, §8
  `query-address`): the field's select, button, clear, popover, text
  field and list, their ids, roles and ARIA, the chosen text and the
  placeholder, in English and Norwegian; SOURCE's attributes and the find
  field; the list's options, check mark, «more» line and «No match»;
  `choice-matches` for a blank text in the rows' order, by the rule
  («bjorn ase», a word's start, an identifier), best first and the rows'
  order among equals, LIMIT and the count, KEEP; `read-choice` over
  pairs and over a function, empty, unknown, and its message in
  Norwegian; `choice-find`; `choice-answer`'s fragment and page; the
  `:choice` filter's button, summary, select, clear, «Reset» and its
  address equal to a `:one` filter's, its row in the sheet; the CSS of the
  active option without a change of weight, size, padding or edge, the
  sheet below 40rem above `--tun-visual-bottom`; the specimen's address;
  `query-address`' encoding, lists, NIL and empty values and an address
  with a query.
- `checks/showcase/checks/ui-choice.py`, on the showcase's `/cards` (with
  hundreds of customers), its «New item» form and the specimen: typing
  narrowing the list only after the pause, one request per pause; a slow
  answer overtaken by a newer one never shown; the arrows, Home and End,
  Enter choosing the active option, Escape closing with the focus back;
  the posted form carrying the id; the clear emptying it; the active
  option at the others' weight and size; at 1280 px the list under the
  field, and above it, the text field last, when there is no room under
  it, its motion's properties and durations; at 390, 360 and 320 px the
  floating sheet inside the window and its text field and list above a
  simulated keyboard; the `:choice` filter changing the address to the id
  and the list, an address written for a `:one` filter read the same, its
  row in the «Filters» sheet choosing with the sheet open and the focus
  in it; without JavaScript the select posting an id, the find step
  listing the matches and the toolbar's «Apply»; no page scrolling
  sideways.
- `tests/generated-choice-tests.lisp` (§8 «Choosing a record», §7):
  `/choices/ENTITY`'s fragment and page, its order, LIMIT and count, its
  403, 404s and POST; on Postgres the record policies deciding what it
  answers, what a form's field may post and which records a cell names;
  one read of the id and the customers module's fields, no operation
  called; its time with 2000 records in
  memory and on Postgres, and what the names add to the orders' pages;
  a record's text in a table and on a record's page past the first 100,
  and an id for a record the person may not choose;
  the generated form's field with every record at 30 and asking at 31,
  in a row of a list of records too, its find step saving nothing and an
  id that is none of the choices refused at its field without calling
  the operation; the generated list's `:choice` filter, its address, the
  list it gives and «Reset»; an entity the person may not list or that
  has no list operation as before; the specimen's address answered by
  `choice-answer`.
- `checks/showcase/checks/generated-choice.py`, on the showcase's
  generated «Meetings» (a resource of the showcase's, each meeting for a
  customer): with 405 customers the form's field asking as one types,
  «bjorn ase» finding «Bjørn Åsen», Enter choosing and saving a meeting
  for him; the list's filter choosing a customer into the address and
  the list; without JavaScript the find step, saving and «Apply»; the
  file field of «New item» at 320, 360 and 390 px inside its column with
  no page scrolling sideways; the specimen's find-step example chosen.
  `generated-choice-few.py`, with the default scenario's four
  customers: every one in the field and the filter, narrowed in the
  browser with no request.
- `tests/form-nits-tests.lisp` (§6 `choice-input`, §8 «Forms»,
  «Choosing a record», «A client's pages»): `error-alert` with FIELDS
  naming each field error by its field's label or legend, linked to its
  control, a row's by its row, in English and Norwegian, and an unknown
  path and an alert without FIELDS as before; the generated summary's
  row wording and «must be chosen»; the kernel's «must be filled in» for
  a blank id; the asked choice's default submit button and none for a
  given one; `record-choice`: the customers module's email, phone and
  erased customer, in `/choices`, the few options, the posted id and
  the names a page shows, and a more specific method's keys winning
  over the module's.
- `checks/showcase/checks/form-nits.py`, on «New item» and the
  generated «Meetings» with 405 customers: the alert of «New item»
  naming «Title» and «Reported on» by their labels in English and
  Norwegian, at 390 and 1280 px, its links going to their fields with
  and without JavaScript; with JavaScript off, Enter in the title of
  either form saving it, not finding, and «Find» still finding; a
  generated form's empty customer «Customer must be chosen».
- `bin/ui-shots` and a review of the screenshots before a component is
  accepted.
