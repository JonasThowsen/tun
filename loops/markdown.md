# A component that renders a small Markdown subset safely, for text agents and people write

- loop: markdown
- mode: reviewed
- stage: done
- base: 205d5a2c0b42c81e1bfefaf7cc74ac162a6b0b6b
- verified: 60923a28edfaa9d2a4d412a9022f75f25720019e
- shown: 60923a28edfaa9d2a4d412a9022f75f25720019e

## Brief

A request from the ferdig session (a message to the Tun session,
2026-11-08), which works for Jonas on tunworks/apps/ferdig:

> Request from ferdig: a TUN.UI component that renders a small Markdown
> subset safely, for text written by agents and people.
>
> Problem: ferdig shows descriptions, comments and questions as plain
> text. Agents write Markdown by habit, so `**`, `|`, `#` and backticks
> appear literally, and a long comment with a wide table is unreadable on
> a phone. Tun has no Markdown component at the pinned revision (142c46c,
> core 2.14.0), and ferdig's AGENTS.md says what it lacks is built in
> Tun's core.
>
> Suggested: `(ui:markdown (:text STRING ...))`, returning Tun's HTML
> tree. Spec it in spec/ui.md first.
> - Subset: paragraphs, bold, italic, ordered and unordered lists,
>   headings (two levels, mapped so they cannot outrank the page's own),
>   links, inline code, fenced code blocks, simple pipe tables.
> - Safe by construction: parse to the tree, never pass HTML through.
>   Raw HTML in the source shows as text. Links only http, https and
>   mailto, others stay plain text.
> - Existing plain text must read as it does today: a single newline
>   stays a line break, as ferdig's `paragraphs` does now, and text
>   without Markdown renders the same.
> - Tables: at most 3 columns as a table; more than 3 become a card list
>   below a set width (one card per row, column heading before each
>   value), otherwise a table scrolling in its own box. Code blocks scroll
>   in their own box. The page's width must never grow.
> - Rendered on read; nothing stored changes.
> - Tests: script and HTML injection, `javascript:` links, unterminated
>   markup, a 10-column table, and a very long unbroken line.
>
> Please push when done and message me the commit hash; I will then run
> `tun update` in tunworks/apps/ferdig.

The same message asked whether agents can attach files by POSTing to
`/api/TOOL` with a token. That was answered in a reply and is not part
of this loop: they can, as JSON with base64 built in the shell
(spec/files.md 4.3, spec/api.md 1).

## Criteria

1. `(ui:markdown (:text TEXT))` renders each block of spec/ui.md 6.2:
   - paragraphs with their line breaks;
   - headings `#` and `##` as `hN` and `hN+1`, N being `:heading-level`
     (3 when omitted), and `###` to `######` as the second level;
   - unordered and ordered lists, an ordered one keeping its first
     number, and lists nested by indentation to four levels;
   - fenced code blocks in a `code-block`, an unclosed fence running to
     the end of the text;
   - rules;
   - tables, with their alignment.
2. It renders each inline rule:
   - bold, italic and both;
   - code spans;
   - links to http(s) URLs, `mailto:` addresses and same-site paths;
   - `<address>` and bare http(s) URLs as links, their final
     punctuation left out;
   - escapes;
   - `snake_case_name` left as written.
3. HTML in the text, `<script>` among it, shows as text. Links to
   `javascript:`, `data:`, `vbscript:`, `//host`, `/\host`, a path with a
   tab in it, a relative path or an address over 2048 characters show as
   written, and an address with balanced parentheses inside it links
   whole. The output renders
   alike as extension output (tun.html's untrusted rendering), its
   `mailto:` links included.
4. Unterminated marks show as written and never signal: an opening
   `**`, a backtick, a `[` and a `[text](`.
5. Lines ending in CR LF or CR read as lines ending in LF: a fence, a
   rule, a table and plain text, with no CR in the output.
   A text with none of the marks of spec/ui.md 6.2 renders as
   paragraphs and `<br>`s holding every character as written, as
   ferdig's `paragraphs` does.
6. A table of up to three columns is a table at every width. A table of
   ten columns is a card per row, each value under its heading, where
   the component is under 36rem wide, and a table scrolling in its own
   box from 36rem. At 320px and 390px wide and on a desktop, the page
   (`/markdown` in the showcase) does not scroll sideways with that
   table, a very long unbroken line, a long code line and a long URL.
   The code block scrolls in its own box.
7. Rows with fewer cells than the headings stay short, rows with more
   lose the extra cells, and a first line of 21 cells is no table.
8. Costly texts of 64 KiB, made of many `[`, `*`, backticks, `](`, `|`
   rows, nesting and long table rows, render within a second each.
   Random texts built from the marks never signal, and their output
   stays within a constant times their length.
9. In extension output, `href` keeps a `mailto:` address. Every other
   URL attribute still refuses it, and `href` still refuses
   `javascript:`. No URL attribute keeps a path starting with `/\` or
   holding a tab, line break or other control character.
10. The component has its documentation, source and examples, shown in
    the specimen. It passes the checks every component passes
    (tests/ui-tests.lisp).

## Decisions

- **Reviewed.** Jonas told the ferdig session to run autonomous loops
  unless he says otherwise. The core loops ferdig has asked for since
  (button-shortcut, page-remembers) were run reviewed by this session.
  This one follows them.
- **CommonMark and GitHub's tables, made smaller** (spec/ui.md 6.2), so
  that what an agent writes shows as it would on GitHub, except where
  safety or ferdig's old text says otherwise.
  - A single line break is kept as `<br>`, as ferdig's `paragraphs`
    keeps it, and as people write it.
  - There are no setext headings and no indented code: a line of `---`
    is a rule, which agents use as a separator, and indented text stays
    text.
  - Block quotes, images, strikethrough, task lists, reference links,
    footnotes and character references were not asked for. They show as
    written. Images, in particular, would load other sites.
- **A rule (`---`) is added** to what was asked: agents write it between
  sections, and shown as written it reads as noise.
- **Same-site paths are links too** (`/saker/12`, not `//host`): ferdig's
  agents link its own items, and the renderer allows such paths already.
- **Bare URLs become links**, as GitHub's autolinks do: agents and
  people paste addresses. Their text is unchanged, so plain text still
  reads the same. Criterion 5 counts a URL as a mark.
- **`mailto:` in `href`.** The renderer (tun.html) dropped every
  `mailto:` link in extension output, so the request's mailto links
  would have vanished in a client's page. `href` alone now takes
  `mailto:`. It runs nothing and loads nothing.
- **Linear by construction.**
  - Code spans use a table of backtick runs.
  - Brackets use a stack, as CommonMark's delimiter algorithm does, and
    so does emphasis, with a lower bound kept for each kind of mark.
  - Addresses are at most 2048 characters. Nesting is bounded.
  - Tables have at most 20 columns, add no missing cells, and give a
    card's headings as text cut at 80 characters.
  - So a hostile text in a public form, or one a feedback module passes
    on, cannot make a page slow or large.
- **Width.**
  - The root is an inline-size container, so nothing in it widens the
    page.
  - Tables of up to three columns break long words. Wider ones keep
    words whole and scroll from 36rem.
  - 36rem is the width at which Tun's `table` turns into cards too.
- **Code blocks are `code-block`**, with its copy button: agents' text
  holds commands to run.
- **The option is `:heading-level`**, named as on `card` and
  `empty-state`. It runs from 2 to 5 rather than their 2 to 4, since a
  text has two levels and the second must be at most `h6`. Its default
  is 3, below a page's `h1` and its sections' `h2`. A value out of range
  signals, as a wrong option to any component does.
- **Same-site paths, tightened.** The renderer took `/\host` and a path
  with a tab in it as same-site, and a browser follows them to another
  host (gate A, round 1). That is no hole, since links to other sites are
  allowed, but the contract would be false. So the renderer now refuses
  them in every URL attribute, and so does `markdown`.
- **Dates such as «17. mai»** at the start of a paragraph become an
  ordered list from 17, as CommonMark has it. They read the same, only
  indented. A rule against it would differ from what agents expect of
  Markdown.
- **Core 2.15.0:** a new component and a renderer change are a minor
  version.
- **Shown in the showcase** at `/markdown`, a page with a text holding
  every rule, a table of ten columns and one of three, and the long lines
  of criterion 6.

## Log

- 2026-11-08 14:26  started, reviewed
- 2026-11-08 14:32  gate A asked of a reviewer
- 2026-11-08 14:36  gate A: changes (reviewer): A same-site path must exclude /\ and tabs or line breaks (browsers read them as //host); the evidence must list [text](. Also: say where a link's address ends (balanced parentheses), reword the old hx-get parenthetical, say an out-of-range :heading-level signals, note Norwegian dates such as «17. mai» starting a list.
- 2026-11-08 14:37  gate A asked of a reviewer
- 2026-11-08 14:39  gate A: changes (reviewer): Criterion 9 (the renderer's URL rule) needs its evidence in §10's ui-tests bullet, and markdown-tests must list a path with a tab; line endings (CR LF from a textarea) must be specified, with a CR LF case in the tests.
- 2026-11-08 14:39  gate A asked of the person
- 2026-11-08 14:40  gate A: approve (jonas): «Approve the spec (Recommended)»; push: «Push after gate B (Recommended)»
- 2026-11-08 14:57  verify 1: passed build, test, check
- 2026-11-08 15:05  verify 2: passed build, test, check
- 2026-11-08 15:05  shown (/markdown, /ui/markdown)
- 2026-11-08 15:05  gate B asked of a reviewer
- 2026-11-08 15:13  gate B: changes (reviewer): Quadratic time: every link walks the stack of open brackets; a link inside a link's text survives when emphasis wraps it. Also: tabs in fences expanded, a list line does not end a table, bare URLs scanned twice and far, a stale docstring in html.lisp.
- 2026-11-08 15:23  verify 3: passed build, test, check
- 2026-11-08 15:23  shown (/markdown, /ui/markdown)
- 2026-11-08 15:23  gate B asked of a reviewer
- 2026-11-08 15:34  gate B: approve (reviewer): All six round-1 findings fixed; no security holes, no cost worse than linear, no departure from §6.2. Non-blocking: empty fences make large output (copy button), many URL starts in one run re-count up to 2048 each, leading tabs in paragraphs, nits (link-tail literal newline, table-cells setf of loop var, ::- alignment).
- 2026-11-08 15:34  pushed 081916d to main; ferdig takes it with tun update. Follow-ups from gate B: an empty fence renders a whole code-block (~1.1 KB, 400x its text); failing URL starts in one run re-count up to 2048 chars each; leading tabs in paragraphs become spaces (unstated in 6.2); nits: link-tail's literal newline, table-cells setf of its loop variable, ::- taken as start-aligned
- 2026-11-08 15:34  finished at tun 081916d
