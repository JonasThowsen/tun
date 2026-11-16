# Tun makes a PDF from a document's nodes, for documents an application sends or hands out

- loop: pdf
- mode: reviewed
- stage: ship
- base: ac5436d805099c26ab907af938381479621da21f
- item: sak_tsfth3mm5m4013rb
- estimate: 4h 7h 12h
- like: tun/mail-files tun/html-mail tun/programs tun/checks-under-load
- tags: kind:feature core
- verified: fea804e75ab446e777ef300311728315fa653b5c
- shown: fea804e75ab446e777ef300311728315fa653b5c

## Brief

Ferdig sak_tsfth3mm5m4013rb («pdf: Tun makes a PDF from a page's nodes,
for documents an application sends or hands out»), brought by the
factory's orchestrator on 2026-11-16, after `mail-files`. The item, as
filed:

> To be one feature loop in Tun, after `mail-files`
> (`sak_fa5kq5e2ep52h8ed`). Tun ERP's `invoice-pdf` waits on it, and
> quotes and delivery notes will use it.
>
> What is wanted:
>
> 1. An application describes a document once (the same nodes it uses
>    for a page or an HTML mail, or a small set of document nodes:
>    header, lines table, totals, footer, page numbers) and gets a PDF's
>    bytes: A4 and Letter, margins, a table that breaks across pages with
>    its header repeated, the tenant's language, money and dates as
>    elsewhere in Tun.
> 2. The PDF can be stored as a file on a record, served, and attached to
>    a mail (with `mail-files`).
> 3. Making it is a port with a fake, so tests assert the document's
>    content without a renderer; one real adapter, built with Nix, with
>    no network at run time.
> 4. The loop's first step is to choose how it is made and write why: a
>    typesetter run as a program (such as Typst), a headless browser
>    printing Tun's own HTML, or a Lisp library. To weigh: closure size on
>    a host, speed per document, fonts and non-Latin scripts, PDF/A and
>    embedded e-invoice XML (later need), that it runs in the sandbox of a
>    Nix build and of the service.
> 5. Speed stated and tested with `is-fast`; a document of 200 lines.
>
> Not in this loop: e-invoice formats, signing.

The orchestrator's brief adds: weigh with measurements made on this
machine, not from memory: closure size (`nix path-info -S`), time per
document cold and warm, which fonts ship and what a missing glyph does,
PDF/A and an embedded XML file (say whether the choice allows it, do not
build it), the sandbox of a Nix build and of a hardened service (no
network, no home, a private temporary folder), and what a malicious text
in a document's data could do: escaped for the renderer, and the renderer
unable to read files or run commands because of it, tested. Pictures of
page 1 and of a page break of the 200-line document. If handing a made
PDF to a browser needs a page to answer a file made on the spot (gap 3
of sak_ygs66kh0329hq80h, not this loop's), build only what the files
module offers, store the PDF on a record and serve it, and say what is
missing. Clients do not adopt PDFs in this loop; `docs/client-api.md`
shows how a client makes an invoice-like document, mails it and stores
it.

## Criteria

The document (`spec/pdf.md` §1, §2):

1. **Bytes from nodes.** `(make-pdf TREE :title TITLE)`, exported from
   `TUN` and `TUN.CORE`, returns a vector of octets starting `%PDF-`; with
   Typst, `pdfinfo` reads it as a PDF whose title is TITLE and whose
   language is the current one (`nb` under `(with-language ("nb"))`).
   (`tests/pdf-tests.lisp`)
2. **A4 and Letter, margins.** With Typst, `:paper :a4` gives pages of
   595 × 842 pt and `:letter` 612 × 792 pt; with `:margins 30` the first
   word of the body starts 30 mm (85 pt) from the left and top edges, and
   with `:margins (10 20 30 40)` 40 mm from the left and 10 mm from the
   top, each within 2 pt (`pdftotext -bbox`). (test)
3. **A table that breaks across pages.** A 200-line invoice (a `thead`
   of five headings, 200 rows, a `tfoot` of totals) made with Typst has
   more than one page; `pdftotext` finds the header's five headings on
   every page, each of the 200 descriptions exactly once and whole on one
   page, and the totals once, on the last page. (test)
4. **Page numbers in the document's language.** Each page of that
   document ends with «Side N av M» in Norwegian and «Page N of M» in
   English, N from 1 to M; `:page-numbers nil` gives none; `:header` and
   `:footer` texts are on every page. (test)
5. **Money and dates as elsewhere.** A document whose amount and date
   are written with `money-text` and `date-text` in Norwegian, as
   `docs/client-api.md`'s example («Making a PDF») writes them, reads in
   the PDF as Tun writes them on a page: «1 250,00 kr» and «16.11.2026».
   (test)
6. **The grammar and its refusals.** Every element of `spec/pdf.md`
   §2.1 is taken; `img`, an element a mail refuses, a node outside the
   grammar, a style a mail refuses, a tree deeper than 50 levels, more
   than 25 000 elements or 1 000 000 characters, a missing or over-long
   title, another paper, and margins outside 5 to 50 mm each fail
   `invalid_input` on their field (`document`, `header`, `footer`,
   `title`, `paper`, `margins`) with a message naming what was refused,
   and run no renderer. (test)
7. **Styles applied.** The document's data, as the renderer receives it,
   carries `text-align`, `vertical-align`, `font-weight`, `font-style`,
   `font-size` (px as ¾ pt, clamped to 6 to 36 pt), `color` and
   `background-color` (#rgb, #rrggbb), and a first row's `width` as the
   column's; the other declarations a mail allows are not in it; with
   Typst a right-aligned amount ends at the text's right edge, within 2
   pt (`pdftotext -bbox`). (test)
8. **`pdf-text`.** `(pdf-text TREE :header H :footer F)` gives the
   header, the body and the footer as text: a table's rows one a line,
   cells separated by « | », a block a paragraph; it checks the tree as
   `make-pdf` does. (test)

The port (§3):

9. **A fake in tests.** In `with-test-app`, `make-pdf` runs no program
   and returns a PDF of the document's text that `attach-files` and
   `send-mail` take (`files.md` §2.1), served by `/files/ID` as
   `application/pdf` with `Content-Disposition: attachment`. (test)
10. **Typst chosen from the environment.** A server (`main`) whose
    environment has `TUN_TYPST` and `TUN_PDF_FONTS` makes PDFs with
    Typst, also with `--test-clock`; one without them and without the
    test clock starts, and its `make-pdf` fails `unavailable` «The PDF
    could not be made.» and logs that Typst is not named; one without
    them with the test clock, and `with-test-app`, make it with the fake.
    The choice is tested on `default-pdf-renderer` and
    `environment-pdf-renderer` with the environment set and unset.
    `buildClient`'s server, Tun's dev shell and a client's dev shell set
    both to store paths. (tests; the server's script read by hand, in
    «Clients»)
11. **Data, never code.** Strings `#read("/etc/hostname")`,
    `#import "@preview/cetz:0.3.0"`, `] #panic("x") [`, `$x$ *b* _e_`,
    `#sys.inputs`, `"}]); #eval("1")` and strings reading the two files in
    the document's directory, `#read("document.typ")` and
    `#read("data.json")`, are each printed exactly as given (`pdftotext`),
    neither file's content is anywhere in the PDF, and
    the layout file holds no `eval`, `import`, `include` or `read(`, and
    no `json(` but `json("data.json")`. (test)
12. **Typst's environment and directory.** A renderer whose program is a
    script that writes out its environment and its directory's mode, run
    with `SECRET_FOR_PDF_TEST` and `DATABASE_URL` set in the server's
    environment, sees `HOME`, `TMPDIR` and `LANG` and nothing else, `HOME`
    and `TMPDIR` the document's directory, whose mode is 0700. (test)
13. **No PDF, no leftovers.** A renderer whose program does not exist,
    exits 1, writes no PDF, or sleeps past its time fails `make-pdf`
    `unavailable`, the timeout within its seconds plus 2
    (`is-within-seconds`), and leaves no directory of its own in the
    temporary directory; Typst's run is an `external` step of the trace
    named `typst compile …`. (test)
14. **Sandbox.** Typst makes the 200-line document in a Nix build's
    sandbox and in a systemd unit with `PrivateNetwork`, `PrivateTmp`,
    `ProtectSystem=strict`, `ProtectHome`, `PrivateUsers`,
    `NoNewPrivileges` and no home (measured, and measured again on the
    final `document.typ` before gate B; the record says how).
15. **A missing letter.** A document holding Chinese and an emoji is made
    with Typst all the same: `pdftotext` finds the Latin text around them.
    (test)

Storing and mailing (§4, `files.md` §4.1):

16. **Bytes on a record.** `(attach-files RECORD (list (list :filename
    NAME :content OCTETS)))` stores a made PDF as a file of RECORD;
    empty, text and over-10-MiB bytes, and a name over 255 characters,
    fail `invalid_input` on `files[N]` with nothing stored. (test)

Speed (§5):

17. **A 200-line document is fast.** `make-pdf` of the 200-line invoice
    with Typst is under 1 000 ms of processor time, this process's and
    Typst's, by `is-fast`; `pdf-text` and the fake's `make-pdf` of it
    under 150 ms. `is-fast` counts the processor time of programs the
    test ran and waited for: a program that burns 300 ms of processor
    time measures at least 250 ms. (tests)

Shown and kept (`spec/pdf.md` §7):

18. **Pictures of the document.** The 200-line invoice, made with Typst
    from the tree of `docs/client-api.md`'s example, rendered at 100 dpi
    into `~/coding/tun-wt/pdf-shots/`: `page-1.png` shows the title, the
    two address columns, the table's header and its first lines, and
    `page-break.png` shows the bottom of page 1 and the top of page 2
    side by side, the last row of one whole, the header repeated, «Side 1
    av N» and «Side 2 av N»; both looked at.
19. **The showcase.** Its «Document» page (`/document`) shows the
    board's estimate as text (`pdf-text`) at 390 px without sideways
    scrolling, and a button that makes the PDF and stores it on a record
    of its own; the page then links to the file, which answers
    `application/pdf` as a download, its bytes starting `%PDF-`.
    (`checks/showcase/checks/pdf-document.py`)
20. **Clients unchanged.** Every client of Tun (factory,
    nixploy-dashboard, ferdig, kurs, tun-erp) compiles and passes its
    `bin/test` unchanged against this tree.
21. **Where people read it.** `spec/pdf.md` (new), `spec/files.md`
    §4.1, `spec/mail.md` §2, `spec/tooling.md`, `spec/deploy.md` §2,
    `spec/tun-platform.md` §2.3, `spec/README.md` and
    `docs/client-api.md` («Making a PDF», with the invoice) say it.
22. **The build.** Core 2.43.0 (`+core-version+`, `coreVersion`);
    `bin/build` warning-free, `bin/test` and `bin/check` green.

## Decisions

### How the PDF is made: Typst

Typst 0.14.2, a typesetter run as a program, from the nixpkgs Tun pins
(`4382ed2b`). The three kinds were measured on netcup-dev on 2026-11-16
(load average 5 to 11 on 8 processors while measuring), each making the
same invoice of 200 lines of five cells (a `thead`, 200 rows, totals,
page numbers), 5 to 6 pages of A4:

| | Typst 0.14.2 | Chromium 150 headless, printing HTML | WeasyPrint 68.1 (HTML and CSS) | cl-pdf / cl-typesetting (Lisp) |
|---|---|---|---|---|
| Closure (`nix path-info -S`, in MiB and GiB) | 98 MiB | 1.8 GiB | 314 MiB | 417 MiB, almost all SBCL |
| Added to a server's closure (`sbcl-tun-2.42.0`, 526 MiB) | 43 MiB, plus 3 MiB of fonts | 1.7 GiB | 252 MiB | 4 to 6 MiB |
| 200 lines, warm (5 to 6 runs) | 0.08 to 0.11 s wall, 0.08 to 0.10 s processor | 0.51 to 0.79 s wall, 0.69 to 0.96 s processor | 1.67 to 1.94 s wall, 1.63 to 1.76 s processor | no PDF: see below |
| 200 lines, cold (its closure's pages dropped from the page cache with `posix_fadvise`) | 0.12 to 0.13 s | 0.83 to 0.87 s | 1.96 to 2.01 s | |
| 20 lines / 2 000 lines | 0.02 s / 0.8 s | | | |
| Memory (maximum resident) | 48 MB (220 MB at 2 000 lines) | 265 MB in its main process alone | 97 MB | |
| A table whose header repeats on each page | yes (`table.header`) | yes (`thead`) | yes | cl-typesetting's tables have no header rows (`:header-rows` is not an option) |
| Page numbers «N of M» | yes | yes (`@page` margin boxes) | yes | by hand |
| Fonts and non-Latin scripts | any TTF/OTF given with `--font-path`, with fallback across them, right-to-left and shaping (Hebrew and Arabic drawn right); variable fonts not supported (it warns) | fontconfig, all scripts its fonts have | fontconfig, Pango shaping | the 14 standard fonts, Latin-1 only; TrueType through converted metrics |
| PDF/A, an embedded XML file | PDF/A-3b with `pdf.attach`: veraPDF 1.28 passed it | no PDF/A | PDF/A-3b and attachments | neither |
| Runs without network, home, in a sandbox | yes, measured: Nix build sandbox, and a systemd unit (below) | needs its own sandbox off (`--no-sandbox`) in a container, or user namespaces | yes | yes |
| What a hostile text could do | nothing: the data is JSON, read with `json()` and placed as text; Typst cannot run a program, and reads only under `--root` | HTML escaped by Tun, but the browser fetches what a page names: file:// and network must be shut | the same as Chromium, its URL fetcher must be replaced | nothing |

- **cl-pdf at this nixpkgs does not write a PDF.** Both `cl-pdf`
  (20231021) and `cl-typesetting` (20210531) load, and
  `pdf:write-document` signals «The function PDF::EXTENDED-ASCII-P is
  undefined»: the two packages do not match. Even working, they offer
  Latin-1 in the standard fonts, no repeated table header, and neither
  PDF/A nor attached files, so the Lisp library would be the most work
  for the least document.
- **Chromium** is the largest by forty times, the slowest to start but
  WeasyPrint, needs its sandbox turned off or user namespaces inside the
  service, and makes no PDF/A, which e-invoices (Factur-X, ZUGFeRD) need.
- **WeasyPrint** would take Tun's HTML as it is and makes PDF/A-3 with
  attachments, but it is 250 MB of Python, Pango and Cairo on every host,
  about twenty times slower than Typst, and fetches what the HTML names
  unless its fetcher is replaced.
- **Typst** is one static program of 44.5 MB (its own fonts inside:
  Libertinus Serif, New Computer Modern, DejaVu Sans Mono), a tenth of a
  second for 200 lines cold or warm, 48 MB of memory, PDF/A-3b with an
  embedded XML file (veraPDF passed it), and the layout in a file of
  Tun's that reads the document as data. What it costs: a layout
  language that is Typst's, not HTML's, so the mail's node grammar is
  translated (§2 of the spec), and CSS is not.

**Sandbox, measured.** The 200-line document was made by Typst
in a Nix build (`runCommand`, `sandbox = true`, no network, `HOME` the
build's `/homeless-shelter`), and in a transient systemd unit
(`systemd-run --user`) with `PrivateNetwork=yes`, `PrivateTmp=yes`,
`PrivateUsers=yes`, `ProtectSystem=strict`, `ProtectHome=tmpfs`,
`NoNewPrivileges=yes`, `MemoryDenyWriteExecute=yes`,
`SystemCallFilter=@system-service`, `RestrictAddressFamilies=AF_UNIX`,
`RestrictNamespaces=yes`, an empty `CapabilityBoundingSet` and
`HOME=/nonexistent`: the same 410 223 bytes both times. Measured again
on the final `document.typ` with the data `make-pdf` writes for the
200-line invoice of the pictures and the fonts of `tun-pdf-fonts`: 412 271
bytes in the systemd unit, as outside it, and 412 261 in the Nix build,
whose `SOURCE_DATE_EPOCH` gives the PDF a shorter creation date. Tun has no NixOS
module making a service; a server runs in its OCI image under Podman
(`spec/deploy.md` §2), whose writable `/tmp` and `HOME=/tmp` are all
Typst uses.

**Fonts, measured.** Typst with `--ignore-system-fonts --font-path`
of Liberation Sans (four styles) and DejaVu Sans (regular, bold) drew
Norwegian, German, Polish, Greek, Russian, Hebrew, Arabic (both right to
left, joined), Georgian and Armenian; Hindi from a fallback without its
joined forms; Thai, Chinese, Japanese, Korean and emoji as empty boxes,
with no warning and the PDF made. Noto Sans in nixpkgs is a variable
font, which Typst 0.14 does not support («variable fonts are not
currently supported and may render incorrectly»), so the static
Liberation and DejaVu are taken. Noto Sans CJK would add 62 MB: not
taken (spec «Not yet»).

**Hostile text, measured.** A 200-line invoice whose first six
descriptions were `#read("/etc/passwd")`, `#import
"@preview/cetz:0.3.0"`, `] #panic("x") [`, `\ $x$ *bold* _em_ `raw`
<label> @ref`, `#sys.inputs` and `"}]); #eval("1")` was made with each
printed as it is (the picture of page 1).

**Size.** The 200-line PDF is 410 kB; without Typst's accessibility
tags (`--no-pdf-tags`) 43 kB. The tags are kept: a screen reader reads
the tables and headings, and 2 000 lines are still 3.8 MB, under a
file's and a mail's 10 MB.

### The rest

- **The document is a mail's node tree.** The item allows either the
  page's or mail's nodes or a small set of document nodes. A mail's
  grammar and allow-list (`spec/mail.md` §2.1) are already checked,
  documented and hold what an invoice needs (headings, paragraphs,
  tables with `thead` and `tfoot`, inline styles), and a client that
  mails a document builds one tree for both. A page's nodes are not
  taken: they are components with scripts and classes a PDF cannot
  draw. Document-wide parts that are not nodes (paper, margins, a header
  and a footer on every page, page numbers, the title) are keyword
  arguments of `make-pdf`. `img` is refused for now: a mail's images are
  https URLs, and the renderer fetches nothing.
- **Of a mail's style, what a document needs is drawn**, and the rest
  (padding, margins, borders, line height) is accepted and not drawn,
  so a mail's tree is never refused as a document for its look. A style
  a mail refuses is refused here too, with the same check.
- **The translation to Typst is data.** Lisp checks the tree and writes
  it as JSON (each element `{"tag", "style", "href", "colspan",
  "rowspan", "c"}`, a table as its head, body and foot rows and column
  widths, styles already read into numbers and colours); Tun's layout,
  `src/pdf/document.typ`, reads it with `json()` and places strings as
  text. Nothing is escaped because nothing is ever parsed as Typst: there
  is no escaping to get wrong. The alternative, writing Typst markup with
  the strings escaped, would make every string a place for a mistake.
- **Typst is named by the environment, not `PATH`.** `buildClient`'s
  server script exports `TUN_TYPST` and `TUN_PDF_FONTS` as store paths,
  so the image carries them, and the dev shells do the same. A client
  need not declare it in `(:programs …)`: making a PDF is Tun's, and the
  tenant's count of four programs at once applies to it all the same.
- **Every server carries Typst**, 47.6 MB more in each image (measured on
  `sbcl-tun-2.43.0`: 551.4 MB alone, 599.0 MB with Typst and
  `tun-pdf-fonts`, which is 3.1 MB), rather
  than only a client that asks for it: no client changes its flake, and
  a client that starts making invoices needs nothing new to deploy them.
  Whether a client should opt in is the owner's to decide: the question
  is in the report.
- **The fake in tests, Typst in servers and previews.** A test gets the
  fake unless it gives a renderer, so a client's suite makes PDFs in no
  time and asserts their content with `pdf-text`; the fake's PDF is a
  real one, so storing and mailing it is tested as it runs. A server,
  a preview's with its test clock included, uses Typst when the
  environment names it, so a person looking at a preview gets the real
  document.
- **Made in the caller's thread, as `run-program` runs a program**: a
  child process with its own group, bounded output, 30 seconds held to
  the operation's deadline, one of the tenant's four programs, a step in
  the trace. A document of 200 lines takes about 0.15 s; a client that
  makes long documents makes them in a job (`docs/client-api.md` says
  so). An internal function of `TUN.OUTBOUND`, `run-own-program`, runs a
  program by its path for the kernel, without the client's declaration
  and `*program-handler*`.
- **Limits**: 50 levels (Typst's JSON reader refuses past 128, and each
  level is two), 25 000 elements and 1 000 000 characters, about 2 500
  table lines, which Typst makes in about a second with about 300 MB.
  Four such at once fit a server's memory.
- **A page does not answer the PDF** (gap 3 of sak_ygs66kh0329hq80h, not
  this loop's): an operation stores it on a record with `attach-files`,
  which now takes `(:filename NAME :content OCTETS)` as `send-mail`
  does, and `/files/ID` serves it as a download. The showcase does
  exactly this. Missing for a client that wants a PDF made on the spot
  and handed to the browser without keeping it: a page or route that
  answers bytes.
- **`is-fast` counts the programs a test ran**, through
  `getrusage(RUSAGE_CHILDREN)`: without it a speed test of `make-pdf`
  would measure Tun's share and miss Typst's, which is most of it. Only
  ended children are counted, which is all a speed test's body leaves.
- **Tests read the PDF with Poppler** (`pdfinfo`, `pdftotext`), added to
  Tun's dev shell only: page sizes, the text of each page and the
  position of words. No server carries it.
- **The fake's PDF** is written by Tun in Lisp: one page per 60 lines of
  the document's text in Helvetica, characters outside Latin-1 as `?`.
- **The core version** goes to 2.43.0: a new interface.

## Verify rounds

1. Stopped by me while it waited for the machine's verify lock, to break
   lines over 100 columns before it ran; nothing of it ran.
2. Build and tests green (the PDF suite's speed lines: `make-pdf` of 200
   lines with Typst 128 ms of processor time, Typst's included; `pdf-text`
   3.8 ms; the fake 4.5 ms). One check failed, the new `pdf-document`: it
   counted the links before the page answering the post's 303 had loaded
   (the address does not change), and expected a file's address to be a
   path where Tun gives it whole. Fixed to wait for the navigation and to
   look for `/files/fil_` in it; passed alone.
3. Green: build, tests, all 51 checks. No round lost to another
   builder's load.

4. After gate B's first round: the English page numbers checked on every
   page, and `spec/pdf.md` §7 saying where the pictures are. Green:
   build, tests, all 51 checks.

The showcase's preview makes its PDF with Typst (`pdfinfo`: «Creator:
Typst 0.14.2»), as `main` chooses also with its test clock.

## Clients

On this loop's tree after verify round 3 (core 2.43.0), each client's
`bin/test` from a clone in a scratch folder, with `--override-input tun`
at the worktree (and `dashboard`, and the ERP client's `customers`, at
its `modules/` directories), one at a time under the verify lock,
unchanged: kurs (352 checks), factory (690), nixploy-dashboard (1421),
ferdig (812) and the factory's ERP client (its suites of 9146, 70802,
378, 387, 373, 8856, 255, 109920, 91034, 16264 and 26179 checks) pass,
with no compiler warning and no failure. No client changes. Round 4
changed only a test of Tun's and a line of the spec, nothing a client
loads, so the clients were not run again.

Criterion 10's server script, read by hand: kurs's server built with
`nix build .#default --override-input tun` at this tree exports
`TUN_TYPST=/nix/store/6k28g25h…-typst-0.14.2/bin/typst` and
`TUN_PDF_FONTS=/nix/store/bsg62h1f…-tun-pdf-fonts`; its closure is
602.9 MB, against 552.8 MB on the Tun it pins (2.42.0), 50.1 MB more.
Each client's dev shell names both too.

## Pictures

Criterion 18, all looked at, in `~/coding/tun-wt/pdf-shots/` (outside
the repository, as the brief asks). The 200-line invoice was made with
Typst by `make-pdf` from a tree as `docs/client-api.md` builds one
(`money-text`, `date-text` and `number-text` in Norwegian), with a header
and a footer: 6 pages of A4, 412 kB, rendered at 100 dpi with `pdftoppm`.

- `page-1.png`: the header line, «Faktura 10042», the customer's address
  and the invoice's dates in two columns without lines, the table's
  head with a rule under it, lines 1 to 37 with hairlines between them,
  descriptions that wrap kept whole in their row, amounts aligned to the
  text's right edge, and the footer with «Side 1 av 6».
- `page-break.png`: the bottom of page 1 (rows 28 to 37, row 37 whole,
  «Side 1 av 6») beside the top of page 2 (the header line, the table's
  head repeated, rows 38 on).
- `page-last.png`: page 6, row 200, the totals once after a rule
  («Sum eks. mva.», «Mva. 25 %», «Å betale» in bold), «Takk for
  handelen!» and «Side 6 av 6».
- `invoice-200-lines.pdf`: that PDF.
- `showcase-document-1.png`: the PDF the showcase's «Document» page made
  in the preview, with Typst: one page, 30 cards, the total once.

The text is sharp, nothing overlaps, no row is cut by a page break, and
the head is on every page. The preview's screenshots of `/document` at
390 and 1280 px are in `.build/loop/pdf/show/`: the text wraps inside its
block at 390 px, and nothing scrolls sideways.

## Log

- 2026-11-16 03:21  started, reviewed
- 2026-11-16 03:33  estimated 3h 5h 9h at brief, like tun/mail-files tun/html-mail tun/programs
- 2026-11-16 03:33  estimated 4h 7h 12h at brief, like tun/mail-files tun/html-mail tun/programs tun/checks-under-load
- 2026-11-16 03:37  gate A asked of a reviewer
- 2026-11-16 03:38  gate A: changes (reviewer)
  Most of the spec is right. Four things need fixing before it goes on.
  
  **What is right**
  - **The brief is covered.** Items 1–5 of the request each map to criteria: bytes, paper, margins, the breaking table, language, money and dates are 1–5; storing, serving and mailing are 9, 14 and 16; the port, the fake and the Nix-built adapter are 9, 10 and 13; speed with `is-fast` on 200 lines is 15. The orchestrator's additions are covered too: measurements, hostile text tested (11), what the files module lacks (`spec/pdf.md` §4 and §6), PDF/A said but not built (§6), clients unchanged (17) and the docs example (5, 18). E-invoice formats and signing are left out, as asked.
  - **The choice of Typst is well argued.** Closure, cold and warm times, fonts and what a missing glyph does, PDF/A-3b with an attached XML file, both sandboxes, and the cl-pdf failure were all measured on this machine. The approach of data, never code, makes criterion 11 meaningful and lets a test decide it.
  - **Nearly every criterion can be decided by a test or check**, with concrete numbers and tools (`pdfinfo`, `pdftotext -bbox`, within 2 pt, `is-within-seconds`).
  - **No decision needed to go to the asker first.** The two choices with the widest effect are the mail's node grammar, which the item allows, and Typst in every image. The second is reversible, the report puts it to the owner, and it is consistent with "clients do not adopt PDFs in this loop".
  
  **Changes**
  1. **No criterion for the page-break picture.** The orchestrator's brief asks for "Pictures of page 1 and of a page break of the 200-line document." The Decisions mention only "the picture of page 1", and no criterion requires either picture. Add one that says where both are kept (for example, beside `loops/pdf.md`) and what each must show.
  2. **Typst's environment is promised in the spec but not tested.** `spec/pdf.md` §3.3 promises that Typst gets only `HOME`, `TMPDIR` and `LANG`, "nothing else of the server's, no secret among it". The same section promises a document directory readable by the server only. That is a security promise with no criterion behind it. Extend criterion 12 or 11: a fake renderer program writes out its environment, and the test asserts that nothing beyond those three variables is there, with a secret set in the server's environment absent. Also test that the directory's mode is 0700 (or drop that promise from the spec).
  3. **The spec's renderer table contradicts criterion 10.** In `spec/pdf.md` §3.1, row 2 ("A server (`main`), a preview's included … Typst") and row 3 ("A test (`open-application` with the test clock …) → the fake") both match a server started with `--test-clock`. Criterion 10 says that server uses Typst. The spec should say which row wins: for example, that the choice is `main`'s, and that `open-application` with a test clock gets the fake only when `main` names no renderer.
  4. **`font-size` limits differ between the criterion and the spec.** Criterion 7 says font-size is "held to 6 to 36", which means clamped. The style table in `spec/pdf.md` §2.1 says "from 6 to 36 pt", and the text after it says unreadable values are left out. That leaves open whether 48 px is clamped, dropped or refused. Make the spec say "clamped to 6 to 36 pt" (or change the criterion to match whatever the spec chooses).
  
  **Not blocking**
  - Criterion 13 is a one-off measurement, not a repeatable test. That is acceptable for the brief, but at gate B it should be re-run on the final `document.typ`.
  - The spec says a missing glyph is drawn as an empty box and the PDF is still made (§3.2). A cheap test of that would keep it true.
- 2026-11-16 03:45  gate A asked of a reviewer
- 2026-11-16 03:46  gate A: approve (reviewer)
  **Gate A, second round: the spec now covers what was asked, and I approve it.**
  
  **The four changes from the first round**
  1. **Pictures.** Criterion 18 now asks for both `page-1.png` and `page-break.png`. It says what each must show: the title, the two address columns and the table's first lines on page 1; on the break, the last row of page 1 whole, the header repeated, and «Side 1 av N» and «Side 2 av N».
  2. **Typst's environment.** Criterion 12 runs a script as the renderer, with `SECRET_FOR_PDF_TEST` and `DATABASE_URL` set in the server's environment. It asserts that the script sees only `HOME`, `TMPDIR` and `LANG`, and that the document's directory has mode 0700. This matches the promises in `spec/pdf.md` §3.3 and §3.2.
  3. **Which renderer is used.** The table in `spec/pdf.md` §3.1 now says the first row that applies wins, and the choice is `main`'s. A server with `--test-clock` whose environment names Typst uses Typst; without Typst it uses the fake. This is now the same as criterion 10, which tests the choice on `default-pdf-renderer` and `environment-pdf-renderer`.
  4. **Font size.** The spec now says "clamped to 6 to 36 pt: 48 px is 36 pt", the same as criterion 7.
  
  **The rest of the spec**
  - **The brief is covered.**
    - Item 1 (bytes, paper, margins, a table that breaks with its header repeated, language, money and dates): criteria 1–5.
    - Item 2 (stored, served, mailed): criteria 9, 16 and 19.
    - Item 3 (a port with a fake, one real adapter built with Nix): criteria 9, 10 and 13.
    - Item 4 (the choice and why): the Decisions table, measured on this machine.
    - Item 5 (speed with `is-fast` on 200 lines): criterion 17.
  - **The orchestrator's additions are covered.** Hostile text is tested (11), both sandboxes are measured and are to be measured again before gate B (14), and a missing letter now has a test (15). What a page can't do yet is written down (`spec/pdf.md` §4 and §6). PDF/A is said to be possible but is not built, and e-invoices and signing are left out.
  - **The spec agrees with the criteria.** The limits, the refusals and the fields they fail on (§2.3 and §1, criterion 6) match. So do the 30 seconds and the failure as `unavailable` (§3.3, criterion 13), the extension of `attach-files` (`files.md` §4.1, criterion 16) and the change to `is-fast` (`tooling.md`, criterion 17).
  - **No decision should have gone to the asker first.** Typst in every server image is the one with the widest effect. It can be undone, and the owner will be asked in the report.
  
  **Not blocking, for gate B**
  - **Criterion 18 points to the wrong place.** It cites `spec/pdf.md` §7, but §7 doesn't list the pictures. Also, `~/coding/tun-wt/pdf-shots/` is outside the repository, so "kept" isn't lasting. Name them in §7, or keep them beside `loops/pdf.md`.
  - **Reading the PDF's language (criterion 1).** Plain `pdfinfo` may not print it. `pdfinfo -meta` (which shows the XMP metadata, where Typst writes the language) or reading the PDF's `/Lang` would decide it.
  - **Criterion 4 and footers.** Criterion 4 says each page "ends with" the page number, but `:footer` text is also on every page. Make sure the test's document has no footer, or check the page number's position rather than that it comes last.
  - **The tenant's language.** Only `with-language` is tested. A test that uses the tenant's language without `with-language` would cover what the brief says.
- 2026-11-16 04:14  verify 2: failed check
- 2026-11-16 04:30  verify 3: passed build, test, check
- 2026-11-16 04:30  shown (/document)
- 2026-11-16 05:20  gate B asked of a reviewer
- 2026-11-16 05:21  gate B: changes (reviewer)
  I've read the whole diff, the spec and the tests. Here is my verdict.
  
  **What is right**
  
  - **Verification passed.** `verify.txt` round 3 shows build, test and check all ok. The `pdf-document` browser check passes all 11 of its steps: the document's text shows, the page doesn't scroll sideways, «Make the PDF» adds a link, and the file answers 200 as `application/pdf`, as a download, with bytes starting `%PDF-`.
  - **The screenshots show `/document` at both widths.** At 390 px the long rows wrap inside the code block and the page doesn't scroll sideways. At 1280 px each card is one line.
  - **The design is sound.** The tree is checked as a mail's tree is, then written as JSON. `document.typ` reads it with `json("data.json")` and only ever places strings as text, so nothing needs escaping. There is a test that the layout holds no `eval`, `import`, `include` or `read(`. Typst runs through `run-own-program` with only `HOME`, `TMPDIR` and `LANG`, in a directory of mode 0700 that is always removed afterwards. Criteria 11 to 13 each have a test that would fail without the change.
  - **Most criteria have tests.** Criteria 1–4, 6–13, 15–17 and 19 are covered in `tests/pdf-tests.lisp` or the browser check. That includes:
    - title and language read with `pdfinfo -meta`
    - the margins measured with `-bbox`
    - the 200-line table, with its header on every page, each line once, and the totals on the last page
    - the renderer chosen from the environment, set and unset
    - the tenant's language without `with-language`
    - `is-fast` counting the programs a test ran
  - **The code is clean.** The `given-file-p` / `given-upload` logic moved out of `mail.lisp` into `attachments.lisp` and is shared, not copied. I found no leftover debugging. Core is 2.43.0 in both places, and the spec files named in criterion 21 are all changed.
  - **The brief is covered.** The docs say what a page cannot do yet (answer a PDF made on the spot) and how a client works around it.
  
  **Changes**
  
  1. **Criterion 18: the pictures aren't there, and nothing says anyone looked at them.**
     - No `page-1.png` or `page-break.png` is in the packet or in the repository.
     - The record never says they were looked at, which the criterion requires.
     - `spec/pdf.md` §7 (diff line 752) says `loops/pdf.md` holds "the pictures of the 200-line invoice", but `loops/pdf.md` has none.
  
     Make both pictures, keep them where §7 says, and note in the record that they show what criterion 18 lists.
  2. **Criterion 20: nothing shows the clients were checked.** It requires factory, nixploy-dashboard, ferdig, kurs and tun-erp to build and pass `bin/test` unchanged against this tree. `verify.txt` covers only Tun's own build, test and check, and the log has no such run. Run them and record the result.
  3. **Criterion 5 and its test disagree.**
     - The criterion expects «16. november 2026», but `date-text` in Norwegian writes `16.11.2026` (`src/core/formats.lisp:116`). The test at diff line 2597 rightly asserts `16.11.2026`.
     - The criterion also names "the example of `docs/client-api.md`", but the test uses a small tree of its own.
  
     Change the criterion to say what is tested and what Tun actually writes, or build the test on the docs example's `invoice-document` shape.
  
  **Not blocking**
  
  - Criterion 11 asks for a file planted in the document's directory. The test reads `document.typ` and `data.json`, which are already there, and plants nothing. That is close enough in effect, but the criterion's wording should match it.
  - Criterion 4 in English is checked only for «Page 1 of M», not on every page.
  - Criterion 10's "server's script read in `nix build`" has no test I could find in the diff.
- 2026-11-16 05:37  verify 4: passed build, test, check
- 2026-11-16 05:38  shown (/document)
- 2026-11-16 05:38  gate B asked of a reviewer
- 2026-11-16 05:39  gate B: approve (reviewer)
  I approve this gate: every criterion now has a test or check behind it, all four verify steps passed, and the three changes I asked for in round 1 are done.
  
  **The three changes from round 1**
  1. **Pictures (criterion 18).** The record now says what `page-1.png`, `page-break.png` and `page-last.png` each show, and that they were looked at. They are in `~/coding/tun-wt/pdf-shots/`, which is where the criterion puts them. `spec/pdf.md` §7 (diff line 752) now also says they are kept outside the repository. I can't reach that folder from here, so I'm relying on the record's description of them.
  2. **Clients unchanged (criterion 20).** The record has a «Clients» section. Each of kurs, factory, nixploy-dashboard, ferdig and the ERP client passed its `bin/test` against this tree with no changes and no warnings. Round 4 changed only a test and a spec line, so not running the clients again is reasonable. The server script for criterion 10 was read by hand: it exports `TUN_TYPST` and `TUN_PDF_FONTS` as store paths, and adds about 50 MB to a client's closure.
  3. **Money and dates (criterion 5).** The criterion now expects «16.11.2026», which is what `date-text` writes. The test (diff line 2593) builds the amount and date with `money-text` and `date-text`, as the docs example does, and finds both in the Typst PDF.
  
  The two non-blocking points are also done. The English page number «Page N of M» is now checked on every page (diff line 2586). The criterion 11 wording now matches the test: it reads `document.typ` and `data.json`, and plants no file.
  
  **Criteria and tests**
  - Every criterion except 14 and 18 has a test in `tests/pdf-tests.lisp` or the browser check that would fail without the change; those two are measurements, recorded under Decisions and in the record. This includes:
    - title and language read with `pdfinfo -meta`
    - margins and right alignment measured with `-bbox`
    - the 200-line table: header, page numbers, header text and footer on every page, each line once, totals on the last page
    - each refusal on its field, with a missing Typst so no renderer can run
    - the renderer chosen from the environment, set and unset, and the log line when Typst isn't named
    - hostile strings printed as given, and the layout file checked for `eval`, `import`, `include` and `read(`
    - the environment script: only `HOME`, `TMPDIR` and `LANG`, the directory mode 0700, no secret
    - failures and the timeout leaving no directory, and Typst as a step of the trace
    - Chinese and an emoji, with the Latin text around them found
    - `is-fast` counting the time of programs a test ran
  - **Sandbox (criterion 14).** It was measured again on the final `document.typ`, and the record says how.
  - **Showcase (criterion 19).** The `pdf-document` check passed all 11 steps. The screenshots show `/document` at 390 px and 1280 px with nothing scrolling sideways; the link after making the PDF is shown by the check, not the screenshots.
  
  **The code**
  - The tree is checked against the same allow-list as a mail. `given-file-p` and `given-upload` are shared with `mail.lisp`, not copied. `run-own-program` passes none of the server's environment. The document directory is removed in an `unwind-protect`, so it goes whatever happens.
  - The Norwegian refusals that are new to PDFs are in `nb-pdf.lisp`; the shared ones are already in `nb-mail.lisp`.
  - I found no leftover debugging and no dead code. Core is 2.43.0 in both places, and the spec files named in criterion 21 are all updated.
  
  **The brief**
  - A4 and Letter, margins, the repeating table header, the language, money and dates are all there. So are storing, serving and mailing, the port with its fake and a Typst adapter built with Nix, and speed checked with `is-fast`.
  - The Typst choice is measured, and the docs example and the gap about a page answering a PDF are written up. E-invoices and signing are left out, as asked.
  
  **Not blocking**
  - The test that `:page-numbers nil` gives no page numbers only checks that "1" isn't on the page. That's weak, but it passes for the right reason.
