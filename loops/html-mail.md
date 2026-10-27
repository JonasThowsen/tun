# E-post i HTML, bygd av noder som sider

- loop: html-mail
- mode: autonomous
- stage: done
- base: 3b16f24030fb81b5e70bcf7a1f2dca2282de3ce0
- verified: 6c58bd36e7ee30e4a4d5d0bd32ee43c348a5cadd
- shown: 6c58bd36e7ee30e4a4d5d0bd32ee43c348a5cadd

## Brief

From Jonas on 2026-10-27, through an agent working on a client:

> A client can't build an HTML mail today. `send-mail` takes `:html`, but
> `render-html` and `escape-html` live in tun.html and aren't in the TUN
> package. A daily summary would be much easier to read on a phone as
> HTML, with titles as links instead of bare URLs that wrap. What's
> needed is a public way to give `send-mail` HTML built from nodes,
> escaped, like pages are built (perhaps `:html` taking a node tree,
> rendered through the same allow-list). Anything generic is fine.

The contract is `spec/mail.md` §2 and the new §2.1.

## Criteria

1. `(send-mail … :html TREE)` takes a node tree, as a page is built; its
   strings are escaped (`<`, `>`, `&`, quotes), and the mail stores the
   tree rendered inside the default frame (`tests/mail-html-tests.lisp`).
2. Every element outside the mail allow-list (`script`, `style`, `form`,
   `iframe`, `input`, `b`, …) is refused: the operation fails
   `invalid_input` on the field `html`, with a message naming the
   element, and no mail is stored.
3. Every attribute outside the list is refused the same way, naming it:
   event handlers (`onclick`), `class`, `id`, `data-*`, `srcdoc`, and
   `href` or `src` on an element that does not take it.
4. Links: an `href` of `javascript:` and `JavaScript:`, `data:`,
   `//host`, `/\host`, a relative `saker`, a `#part` or an empty value is
   refused. `https://`, `http://` and `mailto:` match in any ASCII case
   (`HTTPS://`, `MAILTO:`) and are written as given; a path `/saker/1` is
   made whole with the server's public URL, and stays a path without
   one. An `href` or `src` with a space, a control character or a
   backslash anywhere is refused, also a space before an allowed URL
   (` https://…`, ` javascript:…`): nothing is trimmed. An `img`'s `src`
   other than `https://…` (any ASCII case) is refused.
5. A `style` with a property outside the list, `url(…)`,
   `expression(…)`, `!important`, quotes, a backslash, a non-ASCII
   letter or a declaration without `:` is refused, naming it; property
   names match in any case and are written in lower case; one inside the
   list is written again as checked.
6. A string as the whole `html` is refused, so raw HTML a caller wrote
   by hand never goes out escaped.
7. What is outside the node grammar is refused with `invalid_input` on
   `html`, naming it, never an internal error: an attribute value T (or
   anything but NIL, a string or a number), an attribute name that is
   not a keyword, a `(:@ …)` of odd length or not right after the tag, a
   node that is a symbol, a character, a vector, an improper list or one
   of the renderer's own `trusted`/`untrusted` objects, a circular list,
   or a tree deeper than 200 levels. Attribute names match in any case,
   so `:|href|` is `href`, in the HTML and in the text part.
8. Without `:text`, the text part is made from the tree: links as «text
   (url)» (the url alone when it is the text), `ul` items with «- », `ol`
   items numbered, nested lists indented, headings and paragraphs on
   their own lines with a blank line between, `br` a line break, table
   rows as lines, spaces collapsed. A `:text` given is kept unchanged; a
   blank `:text` beside `:html` is refused on `text`, as without it. A
   text made from the tree that is empty (an `img` without `alt` alone)
   or over 100 000 characters fails `invalid_input` on `text`; a
   rendered HTML part over 500 000 fails on `html`.
9. The frame is a whole document with `lang`, `charset`, a `viewport` and
   the subject as `title`, escaped there as the tree's strings are, so a
   subject `</title><img src=x onerror=alert(1)>` is text in the title
   and adds no element (`tests/mail-html-tests.lisp`); it has no
   `<link>`, `<style>`, `<script>` or external URL of its own; in the
   showcase at 390 px the mail scrolls no sideways and its body text is
   16 px or more, and on a desktop its column is at most 600 px wide
   (`checks/showcase/checks/mail-preview.py`).
10. The Resend adapter receives `text` and `html` both for a mail built
   from a tree without `:text` (the fake Resend in the tests).
11. `(render-mail TREE &key subject text)`, exported from `TUN`, returns
    the HTML and text that `send-mail` stores for the same arguments, and
    stores nothing. Its subject is checked as `send-mail`'s: a list, a
    number or a subject over 998 characters fails `invalid_input` on
    `subject`.
12. The showcase has a page «E-post» that previews a summary of its cards
    with `render-mail`: the HTML in an `<iframe>` with `srcdoc` and a
    `sandbox` attribute that is empty, with no `allow-*` token (no
    `allow-same-origin`, no `allow-scripts`), the text part below it.
    The browser check reads the attribute, and sees that the links in
    the frame, written as paths, start with the preview's public URL
    (`checks/showcase/checks/mail-preview.py`).
13. `docs/client-api.md` «Sending mail» shows `:html` as a node tree,
    with a link by path, and names `render-mail`.
14. The existing mail tests in `tests/mail-tests.lisp` pass, with only
    these changes (see Decisions): the test operation `mail-test-send`
    turns its JSON string `html` into a tree, and three tests,
    `a-mail-exists-only-when-its-write-commits`,
    `only-admins-read-and-retry-mail` and
    `resend-receives-the-mail-with-its-key`, send `"html" "Hei, Ola."`
    (or `"Hei"`) and check that the stored or sent HTML is a framed
    document holding `<p>Hei, Ola.</p>`. Nothing else in the file
    changes, the assertion that a mail without HTML sends none to Resend
    included. `bin/build` has no warnings, `bin/test` and `bin/check`
    pass; core 1.22.0.

## Decisions

- **`:html` takes a node tree only.** `git grep` finds no caller in Tun
  that passes `:html` except the mail tests, and the client the request
  came from passes none, so there is no one to stay compatible with. A
  string as the whole `html` is refused rather than escaped: an old
  caller learns at once, instead of mailing visible tags.
- **What changes in the existing mail tests.** Three tests passed a
  hand-written string, `"<p>Hei, Ola.</p>"` or `"<p>Hei</p>"`, through
  the test operation `mail-test-send`, which declares `(html :type
  string)` and is called over JSON, and compared the stored or sent
  HTML with it (`a-mail-exists-only-when-its-write-commits`,
  `only-admins-read-and-retry-mail`, `resend-receives-the-mail-with-its-key`).
  A tree cannot travel as JSON, so the operation keeps its string
  parameter and sends it as the text of a paragraph, `(:p html)`; the
  three tests pass `"Hei, Ola."` or `"Hei"`, and their three `html`
  assertions check that the HTML starts `<!doctype html>` and holds
  `<p>Hei, Ola.</p>` (or `<p>Hei</p>`), since the frame now surrounds
  it. A paragraph has no default style, so it appears exactly. Every
  other line of `tests/mail-tests.lisp` stays as it is, among them
  «no html when the mail has none». The new behaviour is tested in a
  file of its own, `tests/mail-html-tests.lisp`, which calls
  `send-mail` with trees directly.
- **Schemes are compared as ASCII,** not with Lisp's `char-equal`, which
  folds some non-ASCII letters too: `https`, `http` and `mailto` match
  only in ASCII upper or lower case.
- **URLs are checked as written, never trimmed,** and a space, a control
  character or a backslash anywhere refuses them. Browsers drop leading
  spaces and controls and read `\` as `/`, which is how ` javascript:`
  or `/\host` slip past a check that trims or looks only at `//`; a URL
  in a mail has no need of any of them (`%20` is a space). Schemes match
  in any case, as browsers read them, and are written as given.
- **One field for each failure.** The tree, the frame's size and the
  grammar fail on `html`; the text, given or made, fails on `text`, with
  the messages and limits it always had. A blank `:text` stays refused
  rather than quietly replaced, so `:text` means one thing whether or
  not there is HTML; NIL is how to ask for it to be made.
- **Refused, not dropped.** A page drops what its allow-list lacks
  («[script fjernet]»); a mail refuses it. The tree is the client's
  code, and what a person typed is a string in it, which is always
  escaped, so a refusal is a programming mistake a test finds, and a
  mail never goes out looking different from what was written. It fails
  the operation as every other bad argument to `send-mail` does
  (`invalid_input`), so there is one rule for all of them.
- **A mail allow-list of its own,** not the page's: a page allows forms,
  htmx and `class`, which mean nothing or worse in a mail, and lacks
  `style`, which a mail needs, since mail apps ignore most style sheets.
  The check walks the tree once and then renders it with `tun.html`'s
  escaping renderer, unchanged; `tun.html` loads before mail for that.
- **A path in `href` is made whole** with `absolute-url`. A client then
  writes `/saker/1` as on a page, and the same code works in a test and
  a preview without a public URL, where it stays a path, as
  `absolute-url` promises. Images take `https://` only: the reader's
  mail app fetches an image from wherever the reader is, often refusing
  plain `http://`, and a path would point nowhere without a public URL.
- **Style from a short list, inline only.** Enough to colour, size and
  space text and tables; a value grammar rather than a list of bad words
  (no `url(`, no functions but `rgb`/`rgba`, no quotes), so what is not
  known to be harmless is refused.
- **Default styles per element** in the frame: without a style sheet,
  readable font sizes on a phone have to be inline on each element. They
  come before the element's own declarations, which win.
- **The text part from the same tree,** collapsed as the HTML shows it,
  so the two parts say the same. `ol` items are numbered rather than
  dashed: the number is part of what they say. A `:text` given wins, for
  a client that writes its own.
- **«Every mail is multipart/alternative»** is read as: every mail with
  HTML carries text too, so no mail is HTML alone. A mail with text alone
  stays a single text part, as before and as the existing Resend test
  checks; an HTML part made from plain text would add nothing.
- **`render-mail` is exported** besides `send-mail`, because a mail that
  only exists after it is sent cannot be shown at a gate, previewed on a
  page before sending, or checked in a client's test without sending.
  It returns what `send-mail` stores, so the preview is the mail.
- **The showcase's page** previews the mail in an `<iframe>` with
  `srcdoc`, which a client's own page may hold, since it is rendered as
  core's markup. Its sandbox is empty, with no `allow-*` token: no
  scripts, no same origin, no forms, popups or navigating the page, the
  strictest the attribute allows. The mail has no script anyway; the
  sandbox is there so that a mistake in the mail's checks could not reach
  the page around it. Without a script the frame cannot take the height
  of the mail, so it is tall enough for the summary on a phone and can be
  dragged taller. The showcase is not a real client, so its summary is
  made up from its cards.
- **The tree is bounded.** A circular list, or a tree deeper than 200
  levels, is refused on `html`, so a mistake in a client's code fails the
  operation rather than hanging it or exhausting its stack. A refusal
  prints at most a few levels of what it names, for the same reason.
- **`render-mail` checks its subject** as `send-mail` does: the subject
  becomes the frame's `<title>`, and anything but a string of at most 998
  characters is refused on `subject`.
- **A minor version, 1.22.0:** a new public function, and `:html` now
  means a tree; no client passes a string.

## Log

- 2026-10-27 19:27  started, autonomous
- 2026-10-27 19:29  gate A asked of a reviewer
- 2026-10-27 19:33  gate A: changes (reviewer): name the three existing tests and exactly what changes in them; refuse /\host and say how scheme case and spaces are handled; say which field fails for an empty or over-long derived text and for a blank :text; refuse odd attributes and nodes with invalid_input; docs/client-api.md must show :html as a tree
- 2026-10-27 19:35  gate A asked of a reviewer
- 2026-10-27 19:38  gate A: changes (reviewer): the earlier five met; say and test that the subject is escaped in the frame's <title>; the showcase iframe has sandbox with no allow-* tokens, checked; give 'links whole' a criterion or drop it
- 2026-10-27 19:39  gate A asked of the person
- 2026-10-27 20:17  gate A: approve (jonas): «Approve»
- 2026-10-27 20:42  verify 1: passed build, test, check
- 2026-10-27 20:43  shown (/e-post)
- 2026-10-27 20:48  gate B asked of a reviewer
- 2026-10-27 20:57  gate B: changes (reviewer): render-mail does not check the subject, so a list subject renders a live <script> in the frame's title; check it as send-mail does, with a test
- 2026-10-27 20:58  rebased: tun 12ab0ec → 3b16f24
- 2026-10-27 21:11  verify 2: passed build, test, check
- 2026-10-27 21:22  shown (/e-post)
- 2026-10-27 21:22  gate B asked of a reviewer
- 2026-10-27 21:29  gate B: approve (reviewer): the earlier points fixed and re-attacked; escaping, allow-lists, links, styles, odd nodes and the sandbox hold; the merge kept the viewer fix
- 2026-10-27 21:29  finished at tun a90ae84
