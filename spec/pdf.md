# Documents as PDF

Status: v1, core 2.43.0. How an application makes a PDF of a document it
describes, such as an invoice, a quote or a delivery note: described
once as nodes, in the same grammar as a mail's HTML (`mail.md` §2.1), and
made into a PDF's bytes that it stores on a record, serves, or attaches
to a mail. Making it is a port: Typst, a typesetter run as a program, in
a server; a fake in tests, so a test asserts what a document says
without a renderer.

## 1. Making a PDF

`(make-pdf TREE &key title paper margins header footer (page-numbers
t))`, in the TUN package for a client and in TUN.CORE for a module
(`tun-platform.md` §2.3), returns the PDF's bytes, a vector of octets.

```lisp
(make-pdf `((:h1 ,(tr "Invoice ~a" number))
            (:table (:thead (:tr (:th ,(tr "Description"))
                                 (:th (:@ :style "text-align: right") ,(tr "Amount"))))
                    (:tbody ,@(mapcar #'line-row lines))
                    (:tfoot (:tr (:td ,(tr "Total"))
                                 (:td (:@ :style "text-align: right") ,(money-text total))))))
          :title (tr "Invoice ~a" number)
          :footer (tr "Pay to account ~a by ~a" account (date-text due)))
```

- `TREE` is the document's body, a node tree (§2). `title`, a text of 1
  to 200 characters, is required: it is the PDF's title, which a reader
  shows in its window and which a screen reader announces.
- `paper` is `:a4` (210 × 297 mm), the default, or `:letter` (8.5 × 11
  in).
- `margins` is the space around the page's text in millimetres: one
  number for all four sides, or a list of four, top, right, bottom and
  left, as CSS writes them. Each is from 5 to 50; the default is 20.
- `header` and `footer` are node trees shown on every page, above and
  below the text, in a smaller grey type; NIL is none.
- `page-numbers`, true by default, shows «Page 2 of 5» at the bottom
  right of every page, in the language the document is written in
  («Side 2 av 5» in Norwegian); NIL shows none.
- The document is written in the current language (`i18n.md` §2.4): the
  tenant's, or the one `with-language` binds, so a client makes a
  customer's invoice in the customer's language as it does a mail.
  Typst is told it, for hyphenation and the PDF's language; English for
  source text.
- Money and dates are text the client writes with `money-text`,
  `date-text` and the other formats (`i18n.md` §5, §6), as on a page: a
  document holds strings, never amounts to format.
- A bad argument, a tree outside §2 or past §2.3's limits, signals an
  error, so the operation fails `invalid_input` on the field named
  (`document`, `title`, `paper`, `margins`, `header`, `footer`) with a
  message saying what was refused, as `send-mail` does.
- When the renderer gives no PDF (§3.3), `make-pdf` fails the operation
  with `unavailable`, «The PDF could not be made.», and the reason goes
  to the server's log.
- It may be called inside an operation, a job or a page's code; it reads
  and writes nothing in the store. A PDF made inside a write is made
  while the write is open, so a long document holds the writer for its
  time (§5): a document of hundreds of lines is better made in a job.

`(pdf-text TREE &key header footer)` returns what the document says, as
the text part of a mail is made from its tree (`mail.md` §2.1, the text
part): a block a paragraph of its own, a table's rows as lines with its
cells separated by « | », the header first and the footer last. It
checks the tree as `make-pdf` does and makes no PDF. A test asserts a
document's content with it, and a page can show a document's text before
it is made.

## 2. The document

### 2.1 Nodes

The grammar of a mail's HTML (`mail.md` §2.1): a string, which is shown
as text, never read as markup; a number; NIL; a proper list of nodes; an
element `(:tag [(:@ :attr value …)] child…)`. What `mail.md` §2.1 refuses
for being outside the grammar is refused here the same way.

| Element | In the PDF |
|---|---|
| `h1`, `h2`, `h3` | a heading, 18, 14 and 12 pt, bold; also the PDF's outline |
| `p`, `div` | a block of text |
| `ul`, `ol`, `li` | a list with bullets, or numbered |
| `strong`, `em`, `span` | bold, italic, plain |
| `br` | a line break |
| `hr` | a thin line across the text |
| `a` | a link, its `href` checked and made whole as in a mail |
| `table`, `caption`, `thead`, `tbody`, `tfoot`, `tr`, `th`, `td` | a table (§2.2) |

- The attributes a mail allows (`mail.md` §2.1) are allowed and checked
  as there: `style`, `title`, `lang` and `dir` on any element, `href` on
  `a`, `colspan`, `rowspan` and `scope` on `th` and `td`. So a tree made
  for a mail is a document too, but for its images.
- `img` is refused («<img> cannot be used in a PDF yet»): a document has
  no images in this version (§6).
- Text is 10 pt, in Liberation Sans, with DejaVu Sans for the letters it
  lacks (§3.2). Spaces and line breaks in a string collapse to one space,
  as HTML shows them; `br` breaks a line.

**Style.** `style` is checked as in a mail, and a declaration outside
that list is refused the same way. Of what passes, the PDF applies:

| Declaration | On | Does |
|---|---|---|
| `text-align` | any block, `th`, `td` | `left`, `right` or `center` |
| `vertical-align` | `th`, `td` | `top`, `middle` or `bottom` |
| `font-weight` | any | `bold`, `normal`, or 100 to 900 |
| `font-style` | any | `italic` or `normal` |
| `font-size` | any | in `px` (¾ pt each) or `pt`, clamped to 6 to 36 pt: 48 px is 36 pt |
| `color` | any | `#rgb` or `#rrggbb` |
| `background-color` | `th`, `td` | `#rgb` or `#rrggbb`, the cell's fill |
| `width` | `th`, `td` of a table's first row | the column's width, in `%`, `px` or `pt` |

The others a mail allows (margins, padding, borders, line height,
`max-width`, `height`, `text-decoration`) are accepted and leave the PDF
as it is, so a mail's tree is not refused for them; a value the PDF
applies but cannot read, such as `color: rgb(…)` or `width: auto`, is
left out too.

### 2.2 Tables

A document's lines are a table:

- `thead`'s rows are the table's header, shown again at the top of every
  page the table continues on, with a line under it. `tbody`'s rows, and
  rows directly in the `table`, follow; `tfoot`'s rows come last, once,
  after a line, such as the totals.
- A table with a `thead` has a hairline between its rows. A table
  without one has no lines at all, so two columns of addresses side by
  side are a table of one row.
- A row is never split across two pages: a row that does not fit on
  what is left of a page starts the next.
- The columns: a cell's `width` in the first row sets its column's.
  The first column without one takes the width that is left, and each
  other column without one is as wide as its widest cell: a description
  first and amounts after it need no widths, and a narrow line number
  before the description is given one, such as `width: 6%`. `colspan`
  and `rowspan` span as in HTML.
- A `caption` is shown above the table, bold.
- `th` is bold.

### 2.3 Limits

- At most 50 levels deep, refused past that (Typst reads the document as
  JSON, which it nests twice as deep, and refuses past 128).
- At most 25 000 elements and 1 000 000 characters of text in the body,
  header and footer together: about 2 500 lines of a table, which Typst
  makes in about a second with about 300 MB (§5).

## 3. How it is made

### 3.1 The port

`make-pdf` checks the tree, writes it as the document's data, and asks
the application's PDF renderer for the bytes: `(render-pdf RENDERER
DOCUMENT)`, a generic function in TUN.PDF whose methods are the
adapters. DOCUMENT is the checked document as JSON: the paper, the
margins, the language, the title, the page label and the header, footer
and body as nodes, each a string or `{"tag", "style", "href", "colspan",
"rowspan", "c"}`, a table as its caption, column widths and rows of
`head`, `body` and `foot`.

The renderer is chosen when the application opens:

| Where | Renderer |
|---|---|
| Given to `open-application` as `:pdf-renderer` | that one |
| A server (`main`), whose environment names Typst (§3.2): with `--test-clock` too, so a preview makes real PDFs | Typst, which `main` gives to `open-application` |
| Otherwise, `open-application` with the test clock (a test, `with-test-app`, or a server whose environment names no Typst) | the fake |
| Otherwise, a server without the test clock whose environment names no Typst | none: `make-pdf` fails `unavailable` and logs why |

The first row that applies wins: the choice is `main`'s when it finds
Typst, and `open-application` chooses only when it is given none.

**The fake** (`fake-pdf-renderer`) makes, with no program, a small PDF
of the document's text as `pdf-text` writes it, one line per line of
text, in Helvetica: a real PDF, which a file and a mail take (`files.md`
§2.1), opening in any reader, characters outside Latin-1 shown as `?`.
It is made in Lisp and takes no measurable time, so a client's tests
store and mail made PDFs as a server would. A test asserts what a
document says with `pdf-text`.

### 3.2 Typst

The real adapter, `typst-pdf-renderer`, runs Typst 0.14 from nixpkgs:

- **What it runs.** The server's environment names the program, `TUN_TYPST`,
  and the fonts' directory, `TUN_PDF_FONTS`; the client's server
  (`buildClient`), Tun's and a client's dev shell set both to paths in
  the Nix store. Typst is not looked up on `PATH` and is not one of the
  application's `(:programs …)`.
- **The layout is Tun's.** `src/pdf/document.typ` is the only Typst code
  that runs. Each document is written into a directory of its own, made
  for it under the server's temporary directory, readable by the server
  only, as `data.json` beside a copy of the layout; Typst reads that
  directory only (`--root`), and the directory is removed when the PDF
  has been read, whatever happened.
- **Data, never code.** The layout reads the document with `json()` and
  places its strings in the page as text. Nothing in the data is read as
  Typst markup or code: a string `#read("/etc/passwd")`,
  `#import "@preview/…"`, `]` or `$x$` is printed as it is. The layout
  imports nothing, evaluates nothing and reads no file but `data.json`,
  so a document cannot make Typst read a file, fetch a package from the
  network or do anything else; Typst has no way to run a program at all.
- **Fonts.** `--ignore-system-fonts` and `--font-path TUN_PDF_FONTS`:
  Liberation Sans in its four styles (Latin, Greek, Cyrillic), and
  DejaVu Sans and DejaVu Sans Bold for Hebrew, Arabic, Armenian, Georgian
  and other letters Liberation lacks, with Typst's own embedded fonts
  after them. Every font used is embedded in the PDF, as the subset of
  its glyphs the document uses. A letter no font has, such as Chinese,
  Japanese, Korean, Thai or an emoji, is drawn as an empty box and the
  PDF is made all the same (§6).
- **The PDF** is PDF 1.7, tagged for accessibility as Typst makes it by
  default (its headings, paragraphs, lists and tables marked), with the
  title and language in its metadata.

### 3.3 Running it

- Typst runs as `run-program` runs a program (`outbound.md` §6): no
  shell, its arguments a list, in its own process group, its output
  bounded, counted among the tenant's four programs at once, a step of
  kind `external` named `typst compile …` in the request's trace. Its
  environment is `HOME` and `TMPDIR`, both the document's directory, and
  `LANG` as the server has it: nothing else of the server's, no secret
  among it.
- It has 30 seconds, held to the operation's deadline less a second.
- No PDF comes when Typst cannot be started, runs past its time, ends
  with a code other than 0, or leaves no file starting `%PDF-`; then
  `make-pdf` fails `unavailable` as §1 says, and the log line names the
  document's title and the first lines of what Typst wrote.
- It needs no network, no home directory and nothing outside the Nix
  store but the temporary directory: it runs the same in a Nix build's
  sandbox, in the client's image (`deploy.md` §2), and under a systemd
  service with a private network and temporary directory, a read-only
  file system and no home.

## 4. Storing, serving and mailing it

- **Mailed.** `(send-mail … :attachments (list (list :filename NAME
  :content PDF)))` (`mail.md` §2.2).
- **Stored on a record.** `(attach-files RECORD (list (list :filename
  NAME :content PDF)))` stores it as a file of the record (`files.md`
  §4.1), checked as an uploaded file. Then `GET /files/ID` serves it to
  whoever may see the record, as a download (`files.md` §5.3), and a
  page links to it.
- **Not answered by a page.** A page cannot answer bytes it made as a
  download (`ui.md` §8); a page that offers a document makes it in an
  operation that stores it on a record, and links to the file.

## 5. Speed

Measured on the builders' machine, 2026-11-16, an invoice of 200 lines of
five cells each (5 pages A4):

| | Processor time | Wall time | Memory |
|---|---|---|---|
| Typst alone, warm | 0.08 to 0.10 s | 0.08 to 0.11 s | 48 MB |
| Typst alone, its files out of the page cache | 0.10 to 0.11 s | 0.12 to 0.13 s | 48 MB |
| Typst, 20 lines | 0.02 s | 0.02 s | 31 MB |
| Typst, 2 000 lines (45 pages) | 0.8 s | 0.8 to 0.9 s | 220 MB |

The PDF of 200 lines is about 410 kB, of 2 000 lines about 3.8 MB; most
of it is the accessibility tags.

- `make-pdf` of a 200-line document, Typst, the data and the files
  included, is under 1 second of processor time, this process's and
  Typst's together (`tooling.md`, «Speed and time in tests»).
- `pdf-text` of the same document, and `make-pdf` with the fake, are
  under 150 ms of processor time.

## 6. Not yet

- Images in a document, such as a logo: `img` is refused.
- Fonts for Chinese, Japanese, Korean and Thai, and emoji: their
  letters are empty boxes. Noto Sans CJK alone would add about 62 MB to
  every server. Devanagari is drawn from a fallback font without its
  joined forms.
- PDF/A and a file embedded in the PDF, for e-invoices (Factur-X,
  ZUGFeRD, EHF): Typst 0.14 makes PDF/A-3b with an attached XML file
  (`--pdf-standard a-3b` and `pdf.attach`), which veraPDF 1.28 passed in
  the measurements for this loop; Tun does not offer it yet.
- Signing a PDF.
- A page answering a made PDF as a download without storing it.
- A page break where the client wants one, and a document's own fonts
  and colours.

## 7. Evidence

- `tests/pdf-tests.lisp`: the tree checked as a mail's, each refusal
  naming what it refused, `img` refused; the limits; the arguments;
  `pdf-text`; the fake's PDF taken by `attach-files` and `send-mail`; the
  document's data (a table's head, body and foot, widths, styles, the
  language and page label); with Typst: a PDF of 200 lines whose head
  repeats on every page, its page labels, A4 and Letter, the margins;
  hostile strings printed as text and no file read; a Typst that fails,
  runs past its time or is missing failing `unavailable` and leaving no
  directory behind; the speed of §5 with `is-fast`.
- `checks/showcase/checks/pdf-document.py`: the showcase's «Document»
  page shows the board's estimate as text, makes its PDF, and links to
  it; the link answers a PDF as a download.
- `loops/pdf.md`: the choice of Typst, with its measurements, and what
  the pictures of the 200-line invoice show (its first page, and the
  bottom of page 1 beside the top of page 2), which are kept beside the
  worktree, outside the repository.
