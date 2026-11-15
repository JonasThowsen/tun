# A mail carries attachments, a module reads a stored file, and the file gaps a client found

- loop: mail-files
- mode: reviewed
- stage: brief
- base: fe05dc5d18dd7f3193c14db95af7aa0d50193119
- item: sak_fa5kq5e2ep52h8ed
- estimate: 3h 5h 9h
- like: tun/html-mail tun/attachments-gaps tun/attachments
- tags: kind:feature core

## Brief

Ferdig sak_fa5kq5e2ep52h8ed («mail-files: a mail carries attachments,
and what a client's order files found in Tun's file handling»), brought
by the factory's orchestrator on 2026-11-15. A client of Tun built files
and comments on an order in one of its own modules and found what Tun's
mail and file handling lack. The item, as filed:

> 1. Mail has no attachments (spec/mail.md §6): `send-mail` and the
>    Resend adapter take attachments, and the fake records them.
> 2. A module cannot read an attachment's bytes (`TUN.FILES` is for
>    clients; `attachments-of` gives metadata only): a way to send or read
>    a stored file by its id that checks the caller may read it.
> 3. A multipart post sent with chunked transfer encoding (no
>    Content-Length) answers 500 («NIL is not of type TEXT») instead of a
>    refusal.
> 4. The function that writes a file's size as text is not exported, so a
>    module writes sizes itself.
> 5. `file-input` shows the browser's own «Choose Files / No file chosen»
>    on a page in another language.
> 6. Each `attachments` component carries its own image dialog, so a page
>    with one per file has one dialog per file.
> 7. Perhaps: short-lived public links to a file, as the alternative to
>    attaching (decide in the loop's spec; ask the owner if it is his
>    choice).

The orchestrator's brief adds: the fake adapter records attachments so a
test can assert name, type and bytes; `mail_get` and `mail_list` show an
attachment's name, type and size, never its bytes; a retried mail carries
the same attachments; the spec decides where the bytes live between
queueing and sending, the limits (refused at queueing with a problem the
caller can show), and what `mail_retry` does. A module reads a stored file
by id with the rule of `/files/ID` (files.md §5.2), and attaches a stored
file to a mail by id without handling its bytes; the interface check
allows both for modules. The chunked post is refused with the right
status or read within §4.3's bounds, decided, written and tested with a
real chunked request. The size function is exported, localised as now.
`file-input`'s visible texts come from Tun's translations with and
without JavaScript, keyboard and screen reader intact, the real input
staying the control. One dialog serves every `attachments` component on
a page. Public links: the orchestrator's reading is not to build them now
but to write under «Not yet» what they would need, unless point 1 cannot
be done well without them.

## Criteria

1. **Two attachments, delivered whole.** A mail queued with two
   attachments, a stored file by its id and a PDF given as bytes, is
   delivered by the test's fake provider with both, in order, each with
   its filename, content type and exact bytes; `mail_get` shows for each
   `id`, `filename`, `content_type`, `size`, `sha256`, `file_id` and
   `kept`, and no member holding its bytes; `mail_list` shows the same
   for each mail it lists. (`tests/mail-files-tests.lisp`)
2. **Resend's shape.** The Resend adapter's request body carries
   `attachments`, an array in the mail's order of `{"filename",
   "content", "content_type"}`, `content` the file's bytes in base64 (RFC
   4648 §4, no line breaks), as Resend's API reference documents
   (`POST /emails`, «attachments: array … content: buffer | string …
   Base64», read 2026-11-15); a mail without attachments sends no
   `attachments` member. Tested against the fake Resend's recorded
   request, no network.
3. **Limits refused at queueing.** Eleven attachments fail
   `invalid_input` on `attachments` («A mail can carry at most 10
   files.»); attachments over 10 MiB together fail on `attachments`
   («A mail's files can be at most 10 MB together.»); a refused file
   given as bytes (text, empty, over 10 MiB) fails on `attachments[N]`
   with the files' own message, starting with its name; an item that is
   none of the three forms fails on `attachments[N]`. A stored file the
   caller may not see, an unknown id and a file whose entity no longer
   takes files fail `not_found`, the same for all. In each case no mail,
   no mail attachment and no delivery job is stored.
4. **Copies, retries and the source gone.** A stored file attached to a
   mail and then removed from its record (`attachments_remove`) before
   the mail is sent is delivered with its bytes all the same. A mail
   that failed (a permanent answer) after its source file was removed is
   sent again by `mail_retry` with the same bytes. Once a mail is sent,
   its attachments' bytes are gone from the store and `kept` is false,
   their name, type, size and SHA-256 kept. A mail whose attachment's
   bytes are missing when it is delivered fails at once (`failed`, its
   job failed), `last_error` naming the file, and the provider is not
   called.
5. **A module reads a file.** `(file-octets ID)`, exported from
   `TUN.CORE` and `TUN`, gives a stored file's bytes and its attachment
   object; for a file whose record the caller may not see (a record
   policy on Postgres), an unknown id, and a file whose entity no longer
   takes files, it fails `not_found` «Could not find the file ID», the
   same for all, as `GET /files/ID` answers 404 alike. The test client's
   module `logbook` uses `file-octets`, `attachments-of`, `attach-files`
   and `send-mail` with `:attachments`; its tools work in the test
   client's suite, and the interface check of the client's own modules
   (testing.md §1, test 10) passes on it. `send-mail`, `render-mail`,
   `attach-files`, `attachments-of` and `file-octets` are external in
   `TUN.CORE` (a test).
6. **A chunked multipart post.** A real request over a socket, `POST`
   of `multipart/form-data` to a page with `Transfer-Encoding: chunked`
   and no `Content-Length`, from a signed-in person and from no one, is
   answered 411 with a page saying why («The form was sent without its
   length. Send it again from the page.» in English), with
   `Connection: close`, never 500. (`tests/safety-tests.lisp`)
7. **The size as text.** `octets-text` is exported from `TUN.UI`,
   documented in `spec/ui.md` and `docs/client-api.md`; it writes 640 B,
   12 kB, 1.4 MB, and 1,4 MB in Norwegian; the `attachments` component's
   tile shows exactly what `octets-text` writes for its file's size.
   (test)
8. **`file-input` in the page's language.** In the showcase, on a page
   in Norwegian and on one in English, at 390 px and 1280 px, with
   JavaScript and without, the browser's own file control paints
   nothing (its computed `opacity` is 0) and lies over Tun's own button,
   which reads «Velg filer» («Choose files»; «Velg fil», «Choose file»
   with `:max 1`); with JavaScript a line beside it reads «Ingen filer
   valgt» («No files chosen») and «Valgt: 2» («Chosen: 2») after two
   files are chosen; without JavaScript there is no such line. The
   `<input type="file">` is still the control: it is the element the
   field's label names, Tab reaches it, the button shows the focus ring
   when it has focus from the keyboard, and a click on the button opens
   the browser's chooser (a file chooser event). The existing file
   checks (`files-choose.py`, `files-drop.py`, `files-paste.py`,
   `files-without-javascript.py`, `files-in-a-dialog.py`) pass unchanged.
   (`checks/showcase/checks/files-language.py`, and a test of the markup)
9. **One image dialog.** The `attachments` component renders no
   `<dialog>`; it carries the dialog's texts in its markup. In the
   showcase, `/attachments` with three components holding images has no
   dialog until an image is opened, and then exactly one, at the end of
   the body; each component's image opens in it, showing that image and
   its name, «Open the original» linking to it; Escape closes it and
   gives the focus back to the thumbnail that opened it. The existing
   `files-thumbnails.py` passes (the dialog centred, the whole image).
   (`checks/showcase/checks/files-one-dialog.py`, and a test of the
   markup)
10. **Clients unchanged.** Every client of Tun (the five the factory
    tests) compiles and passes its `bin/test` unchanged against this
    tree, each with its own modules; what a client must change, if
    anything, is in «Clients» with the code.
11. **Where people read it.** `spec/mail.md` (§2.2 new, §3, §4, §5, §6,
    §7), `spec/files.md` (§4.2, §4.3, §6.1, §6.3, §7, §8), `spec/ui.md`
    §6, `spec/tun-platform.md` §2.3 and `docs/client-api.md` («Sending
    mail», «Files on a record», «A module of the client's own») say it,
    and the «Not yet» lists are updated: attachments leave mail's,
    public links to a file join files'.
12. **The build.** Core 2.41.0 (`+core-version+`, `coreVersion`);
    `bin/build` warning-free, `bin/test` and `bin/check` green; the cases
    guard stays clean over `src/` and `modules/`.

## Decisions

- **The bytes live in the mail's own copies.** At queueing, in the
  sender's transaction, each attachment's bytes are copied into a mail
  attachment of the mail's own: an internal record (`mail_attachments`,
  `mat_…`) with its name, type, size, SHA-256 and the stored file it came
  from, its bytes in the store's content table beside files' own
  (files.md §5.1). So the mail does not lose an attachment when the file
  is removed from its record or the record is deleted before it is sent,
  and a retry sends exactly what was queued. The other reading, keeping
  only the file's id and reading it when sending, would let a mail lose
  its file, or send what another actor sees, and needs the sender's
  rights at delivery time, which a job does not carry.
- **The copies' bytes go once the mail is sent.** In the write that
  records the mail `sent`, its attachments' bytes are deleted and
  `kept` set false; their name, type, size and SHA-256 stay for
  `mail_get`. A sent mail is never sent again (`mail_retry` takes only a
  failed one), so its bytes have no further use, and keeping every sent
  file twice would grow the database by every mail's files for ever. A
  `failed` mail keeps its bytes, so `mail_retry` sends the same; a sweep
  of old failed mails' bytes is «Not yet».
- **Three forms of an attachment.** `:attachments` is a list whose items
  are a stored file's id (`"fil_…"`), an attachment object as
  `attachments-of` and `attachments_list` give it (its `"id"` is read),
  or `(:filename NAME :content OCTETS)` for bytes the caller made, such as
  a PDF it wrote. A module or client that only forwards a stored file
  names it and never holds its bytes; `(attachments-of record)` can be
  passed as it is.
- **A stored file is read as the caller, as `/files/ID` serves it.**
  `send-mail` runs in the caller's write as `*actor*`; a file whose
  record the caller may not see fails `not_found`, the same as an unknown
  id, so a mail cannot carry a file its sender could not open. A system
  actor (a job, a workflow) reads as it does today.
- **Bytes given are taken as an uploaded file.** The types, the size per
  file, the name and the metadata stripped are files.md §2 and §3's, by
  the same code, so a mail never carries a type a person could not
  attach (no HTML, SVG or script), and a generated PDF passes (Tun
  recognises PDF by its header). Other types (CSV, plain text) are «Not
  yet».
- **The limits: 10 files, 10 MiB together.** Base64 makes 10 MiB about
  13.4 MB on the wire, under Resend's 40 MB per mail («max 40MB per
  email, after Base64 encoding of the attachments») and under the 20 to
  25 MB many mail servers take, so a mail Tun accepts is one most
  readers receive. Ten files is a call's limit for files already. Each
  file keeps its own 10 MiB bound. Refused at queueing with
  `invalid_input` on `attachments` (or `attachments[N]` for one file), so
  a page shows it at the field as it shows any refusal of an operation.
- **A key that exists answers its mail.** `send-mail` with the key of an
  existing mail returns that mail with the attachments it was queued
  with; the new call's attachments are checked as its other arguments
  are, and not stored.
- **The provider gets the files as an argument.** `deliver-mail` takes
  a third argument, the mail's files (`mail-file`: filename, content
  type, octets), read in a read transaction before the provider is
  called, so the 10-second limit covers the provider alone and an
  adapter needs no transaction. The generic is Tun's own (not in `TUN`):
  Tun's two adapters and its tests' fakes change, no client defines one.
  A copy whose bytes are missing (the content table changed by hand)
  fails the mail at once, naming the file, rather than sending it
  without the file.
- **Tools show metadata only.** `mail_get` and `mail_list` give each
  mail's `attachments` as `{"id", "filename", "content_type", "size",
  "sha256", "file_id", "kept"}`: never the bytes, and the SHA-256 lets a
  client's test say which bytes went without reading them. `mail_list`
  reads them for its 100 mails in one query.
- **What a module may call is in `TUN.CORE`.** A module reaches the
  kernel through its public packages (`TUN.CORE`, `TUN.WORKFLOWS`,
  `TUN.JOBS`, `TUN.WEB`, `TUN.UI`, `TUN.ACCOUNTING`); `TUN.MAIL` and
  `TUN.FILES` are not among them, and opening them whole would give a
  module their internals (`*uploads*`, `register-upload`, the adapters).
  So `TUN.CORE` exports the five functions a module needs, `send-mail`,
  `render-mail`, `attach-files`, `attachments-of` and the new
  `file-octets`, defined where they are now; `TUN.MAIL`, `TUN.FILES` and
  the `TUN` facade keep exporting the same symbols, so a client's code
  and Tun's own references read as before. No client's or module's
  sources define a function of these names (searched in the five
  clients and their modules).
- **`file-octets` reads the whole file.** At most 10 MiB, in the
  caller's transaction, and answers the bytes with the attachment object
  as a second value. A page that serves a file sends `/files/ID`, which
  reads it a part at a time; `file-octets` is for code that needs the
  bytes, such as making a document from an image.
- **A chunked multipart post is refused, 411.** `core.md` §7.5 already
  answers a chunked body 411 on every path: a chunked body's size is
  known only by reading it, and Tun decides a body's bound and its place
  before reading. The 500 came from a page's refusal finding no message
  for 411 (`+upload-refusals+` had none), so the page that says why
  failed. Browsers send a form's `Content-Length` always, so reading
  chunked forms would serve scripts only; the refusal gets its message
  and a test with a real chunked request.
- **`octets-text` as it is.** The function the `attachments` component
  uses (`tun.ui::octets-text`) is exported from `TUN.UI`, which clients
  and modules both reach, unchanged: 640 B, 12 kB, 1.4 MB, decimal
  units, the decimal mark of the language.
- **`file-input`: Tun's button over the browser's control.** No page can
  translate the browser's file control: its button and «No file chosen»
  come from the browser's own language. The control stays the real
  `<input type="file">`, named by the field's label, in the tab order,
  laid over a button Tun draws («Choose files», «Velg filer») and made
  transparent (`opacity: 0`, not hidden or `display: none`, which would
  take it out of the tab order and away from screen readers), so a
  click or tap on the button is a click on the control, and dropping
  files on it works as before. The button shows the focus ring when the
  control has the keyboard's focus. With JavaScript a line beside the
  button says what is chosen («No files chosen», «Chosen: 2»), and the
  list under it names each file as before. Without JavaScript nothing
  can know what is chosen (CSS has no selector for a file input that
  holds files unless it is `required`), so the line is not shown: the
  browser's own «No file chosen», which was the only such line, goes,
  and a person without JavaScript sees no count of what they chose; the
  files are posted as before. The line is `aria-hidden`: the control
  itself tells a screen reader what is chosen.
- **One image dialog, made when first needed.** The component carries
  the dialog's three texts (its label, «Open the original», «Close»)
  as data attributes; the script, on the first click on a thumbnail,
  finds the page's dialog or makes it at the end of the body from the
  clicked component's texts, and every component's thumbnails open in
  it. Made by the script rather than rendered, since a component cannot
  know whether another on the page, or one htmx swaps in later, has
  rendered one; without JavaScript there is no dialog to render, as
  before (a thumbnail opens the image). Its styles move out of
  `.tun-attachments` to `.tun-attachments-dialog`, which no longer sits
  inside a component.
- **Public links to a file: not now.** A mail carries its files as
  attachments up to 10 MiB, which is enough for an order's documents
  and photos; a link would let a file reach someone without an account,
  which needs a decision of its own (who may make one, how long it
  lives, revoking it, audit) and adds a path served without a session.
  Written under files.md «Not yet» with what it would need.
- **A minor version, 2.41.0:** new public functions and a new keyword
  argument; no call's shape changes.

## Log

- 2026-11-15 05:12  started, reviewed
- 2026-11-15 05:13  estimated 3h 5h 9h at brief, like tun/html-mail tun/attachments-gaps tun/attachments
