# A mail carries attachments, a module reads a stored file, and the file gaps a client found

- loop: mail-files
- mode: reviewed
- stage: ship
- base: fe05dc5d18dd7f3193c14db95af7aa0d50193119
- item: sak_fa5kq5e2ep52h8ed
- estimate: 3h 5h 9h
- like: tun/html-mail tun/attachments-gaps tun/attachments
- tags: kind:feature core
- verified: a91a07afd07c16e3085808d3276491bb6d92b87a
- shown: a91a07afd07c16e3085808d3276491bb6d92b87a

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
  itself tells a screen reader what is chosen. The owner chose this
  reading over showing the browser's own control without JavaScript:
  «21 A» (Ferdig kom_7k2j6vd2m8k3p5fv, 2026-11-15), to «as built: never
  the browser's English text; a person without JavaScript gets no
  confirmation of the choice».
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
- **Existing tests that change, and why.** The behaviour they pinned
  changed by the spec: `tests/mail-tests.lisp`'s scripted provider takes
  the files `deliver-mail` now passes, and records them; `tests/ui-data-tests.lisp`
  asserted that `attachments` renders a `<dialog>`, now that it renders
  none and carries the dialog's texts; `tests/ui-interaction-tests.lisp`
  found the `tun-attachments-dialog` among the dialogs the examples
  render, and now holds the script-made dialog's CSS to the same margin
  rule; `tests/ui-forms-tests.lisp` checks the control's order with the
  button and the line in it. Nothing else in them changes.
- **The test client's module shows it.** `logbook`'s entry takes files;
  `logbook_attach`, `logbook_mail` (the entry's note with its files, by
  their ids) and `logbook_file` (`file-octets`) use the five functions
  through `TUN.CORE`, so the module interface check of a client's own
  module runs over a real use of them.
- **A minor version, 2.41.0:** new public functions and a new keyword
  argument; no call's shape changes.

## Verify rounds

Load averages on the shared machine were 50 to 77 for most of the loop,
with another builder's suites and browser checks beside these.

1. Build: a parenthesis too many in the test client's new test (mine).
   Checks: `files-one-dialog` counted every `<dialog>` of the page, the
   search's among them (the check fixed to count the image dialog);
   `files-language` clicked the button's place before scrolling it into
   view (fixed); `board-drag-on-a-phone` and `ui-search` (100 ms) failed,
   and passed alone.
2. Tests: an unused Norwegian entry («Email attachment»: internal
   entities' labels are not shown), the control's hover without a
   pressed state (`:active` added), and the generated sequence test,
   which took `logbook_file`'s `id` for an entry's id (renamed
   `file_id`). Checks: `files-language` waited for a chooser that did not
   come once under load; `ui-motion` (a fade sampled within 300 ms)
   failed, and failed alone too at a load of 54.
3. Tests: `group-commit` (passed alone). Checks: `board-order-on-a-phone`
   (failed once alone, then passed twice alone), `files-language`'s
   chooser again (the check now listens for the chooser from the start;
   passed alone), `ui-search` (passed alone).
4. With `TUN_TEST_JOBS=3`. Tests: `preview` (`pg_ctl … start exited with
   status 1` in a test of a start that fails). Checks:
   `push-notification-opens-its-page`, `ui-search` (124 to 215 ms
   against 100).
5. Build and tests green; one check, `ui-motion` (the accordion's fade at
   390 and 1280 px, every sampled frame already at full opacity), at a
   load of 57 to 65. Five rounds in a row failed: the loop is stuck, and
   waits for the person.

`ui-motion` alone after round 5, this tree and the base (`fe05dc5d`, a
worktree of its own) in turns, twelve runs, with the load average when
each began:

| Time | Load | Tree | `ui-motion` |
|---|---|---|---|
| 10:38 | 56.6 | base | ok |
| 10:39 | 52.7 | this | ok |
| 10:40 | 55.2 | base | ok |
| 10:42 | 52.4 | this | ok |
| 10:42 | 56.6 | base | ok |
| 10:44 | 77.1 | this | 2 of 51 failed |
| 10:46 | 79.5 | base | 1 of 51 failed |
| 10:48 | 85.9 | this | 1 of 51 failed |
| 10:49 | 84.5 | base | ok |
| 10:51 | 86.0 | this | ok |
| 10:52 | 74.5 | base | ok |
| 10:53 | 75.1 | this | ok |

The base fails it under the same load, and this loop changes nothing the
accordion's fade uses: the failure is the machine's load, not the change.

## Clients

On this loop's tree at `cdc3538b` (after verify round 4), each client's
`bin/test` with `--override-input tun` at it (and `dashboard`, and the
ERP client's `customers`, at their `modules/` directories of the same
commit), one at a time, from clones in a scratch folder, unchanged, at
core 2.41.0: kurs (352 checks), factory (690), nixploy-dashboard (1421),
ferdig (812) and the factory's ERP client (its suites of 7828, 72716,
378, 349, 304, 8856, 255, 109918, 90918, 16264 and 26123 checks) pass,
with no compiler warning and no failure. No client changes.

## Log

- 2026-11-15 05:12  started, reviewed
- 2026-11-15 05:13  estimated 3h 5h 9h at brief, like tun/html-mail tun/attachments-gaps tun/attachments
- 2026-11-15 05:20  gate A asked of a reviewer
- 2026-11-15 05:21  gate A: approve (reviewer)
  I'm approving this gate. The criteria cover everything the brief asks for, each one can be settled by a test or check, the spec says the same things, and none of the decisions should have gone back to the asker.
  
  **Brief vs. criteria**
  - **Point 1 and the orchestrator's additions:**
    - Criterion 1: the fake provider gets each attachment's name, type and exact bytes; `mail_get` and `mail_list` show metadata only.
    - Criterion 2: Resend's request shape.
    - Criterion 3: limits are refused when the mail is queued, on `attachments` / `attachments[N]`.
    - Criterion 4: retries send the same bytes; the decisions say where the bytes live before sending.
  - **Point 2:** criterion 5 covers `file-octets` with the same `not_found` rule as `/files/ID`. It also covers attaching a stored file by its id, and a real module (`logbook`) passing the interface check.
  - **Point 3:** criterion 6, a real chunked request over a socket answered 411 with a page. This matches `spec/core.md:747-748`, which already answers a chunked body 411. The cause the decision gives (`+upload-refusals+` had no 411 message) is a plausible reason for the 500.
  - **Points 4 to 6:** criteria 7, 8 and 9. Criterion 8 keeps the real `<input type="file">` as the control, reachable by Tab and named by its label, and requires the five existing file checks to pass unchanged.
  - **Point 7:** not built, and written under files.md «Not yet» with what it would need. That is the orchestrator's own reading, so it didn't need to go to the owner.
  - **Nothing beyond the brief** except the release bookkeeping (version 2.41.0, the roadmap row).
  
  **Spec vs. criteria**
  - **mail.md §2.2 matches criteria 1–4:** the three forms of an attachment, the limits and their messages, the copy (`mat_…`) kept until the mail is sent, a missing copy failing the mail at once, and the tools' metadata members.
  - **Resend:** mail.md §4 matches criterion 2.
  - **files.md** matches criteria 5–9: §4.2 for `file-octets`, §4.3 for the 411 page, §6.1 and §6.3 for the button, the line and the one dialog. The section numbers named in criterion 11 exist.
  - **Other docs:** `tun-platform.md` §2.3 and `ui.md` §6 cover the `TUN.CORE` exports and `octets-text`.
  - **Units:** the «10 MB» messages for limits counted in MiB follow the existing convention (`spec/files.md:93-95`).
  
  **Decisions:** the brief handed the builder where the bytes live, the limits and `mail_retry`, and these choices are reasoned. Copying at queueing time, so the mail doesn't need the sender's rights when it is delivered, is the sound choice. Deleting the bytes once a mail is sent follows from `mail_retry` only taking failed mails. Exporting from `TUN.CORE` rather than opening `TUN.MAIL` or `TUN.FILES` keeps the kernel's internals away from modules. A name clash with clients is settled by criterion 10. In Tun's own code, the other `octets-text` is in `tun.outbound`, which doesn't use `TUN.UI`, so it doesn't clash.
  
  **Notes for gate B (they don't block this one):**
  - **The attachment-object form:** criterion 1 tests a stored file's id and bytes given, but not the attachment-object form. That is the form in the main docs example, `:attachments (attachments-of order)`. The test list in mail.md §7 includes it; make sure the test does too.
  - **The nightly sweep:** the mail's copies sit in `attachment_contents` beside files' own bytes. `attachments_sweep` (files.md §5.1) must not delete a `mat_` row as an orphan, and a test of a queued mail surviving the sweep would show it.
  - **A record deleted before sending:** the decision covers it, but only removal through `attachments_remove` is in criterion 4.
  - **Without JavaScript:** the person no longer sees any line saying what they chose. This is a stated trade-off (files.md §6.1), and criterion 8 makes the without-JavaScript state checkable.
- 2026-11-15 06:53  verify 1: failed build, test, check
- 2026-11-15 07:26  verify 2: failed test, check
- 2026-11-15 08:18  verify 3: failed test, check
- 2026-11-15 09:28  verify 4: failed test, check
- 2026-11-15 10:36  verify 5: failed check
- 2026-11-15 11:05  resumed (jonas): Jonas, Ferdig kom_7k2j6vd2m8k3p5fv: resume; rounds 3 to 5 failed only on clock-timed browser checks while another builder's checks ran (load 50 to 86); the verify now runs only while no other builder's verify runs
- 2026-11-15 12:27  verify 6: passed build, test, check
- 2026-11-15 12:28  shown (/attachments, /ui/file-input, /ui/attachments)
- 2026-11-15 12:28  gate B asked of a reviewer
- 2026-11-15 12:29  gate B: approve (reviewer)
  I'm approving this gate. Every criterion has a test or check that would fail without the change, round 6 of verification passed (build, test and check), and no browser check in `checks/` failed.
  
  **Criteria against the diff**
  - **1. Two attachments, delivered whole.** The test sends a stored file and a PDF given as bytes. The fake provider gets both, in order, with their exact bytes. The test also checks that `mail_get` shows exactly the seven named fields and no bytes, and that `mail_list` shows the attachments too (`tests/mail-files-tests.lisp:1856`). Gate A asked that the attachment-object form be tested. It is, twice: once as an object (`:1893`) and once as `(attachments-of record)` passed as it is (`:1905`).
  - **2. Resend's shape.** `src/mail/resend.lisp:1180` builds the `attachments` array. The test checks each item's keys, its base64 content, that the content has no line breaks, and that a mail without attachments sends no `attachments` member (`:1917`).
  - **3. Limits refused at queueing.** The test covers 11 files, more than 10 MiB together, each kind of refused file by its index, and an item of no known form. Exactly 10 MiB is accepted. A file the sender may not see, an unknown id and an entity that no longer takes files all fail `not_found`. Each case asserts that no mail, no mail attachment and no delivery job was stored (`:1957`, `:1989`).
  - **4. Copies, retries and the source gone.**
    - A queued mail survives its file being removed, its record being deleted and the sweep running. This settles both gate A notes about the sweep and a deleted record (`:2027`).
    - `mail_retry` after the source file is gone sends the same bytes.
    - Once a mail is sent, its copies' bytes are gone and `kept` is false.
    - A mail whose copy is missing fails without calling the provider, and its job fails too (`:2077`).
  - **5. A module reads a file.**
    - `file-octets` has tests on the memory store and with a record policy on Postgres.
    - The five symbols are external in `TUN.CORE` and are the same symbols as in `TUN` (`:2153`).
    - `logbook` uses all of them, and its interface check passes (`tests/client/tests/interface-tests.lisp:1743`).
  - **6. A chunked multipart post.** A real socket request with `Transfer-Encoding: chunked`, signed in and not, gets 411, `Connection: close` and the page's message (`tests/safety-tests.lisp:2213`). The fix is the missing 411 entry in `src/agent/http.lisp:1083`, which matches the cause the decision gave.
  - **7. The size as text.** `octets-text` is exported, and the tests cover 640 B, 12 kB, 1.4 MB and 1,4 MB, plus a tile showing exactly what the function writes.
  - **8. `file-input` in the page's language.** `files-language.json` passes for nb and en, at 390 and 1280 px, with and without JavaScript:
    - the browser's control has opacity 0 and lies over Tun's button;
    - the label names the input, and Tab reaches it;
    - the button shows the focus ring;
    - with JavaScript a click opens the browser's chooser, and the line reads «Valgt: 2» after two files are chosen.
    
    The five existing file checks pass. The screenshots show «Velg filer / Valgt: 2» on a phone and «Choose files / No files chosen» on desktop.
  - **9. One image dialog.** `files-one-dialog.json` passes at both widths:
    - there is no dialog before an image is opened, then exactly one, at the end of the body;
    - each component's image opens in it;
    - Escape closes it and gives the focus back to the thumbnail.
    
    The markup test asserts that the component renders no `<dialog>` and carries the dialog's texts. The 390 px screenshot shows the dialog centred.
  - **10–12. Clients, docs and the build.** The record lists five clients passing unchanged. The spec and docs sections named in criterion 11 are all changed, and both «Not yet» lists are updated. The version is 2.41.0 in both places.
  
  **Code.** It reads cleanly, with no leftover debugging or dead code. The adapters now get each mail's files as a third argument to `deliver-mail`, so every method that defines it changed with it. Moving the mail module after files in `tun.asd` is explained in a comment. The bytes are dropped in the same write that records the mail `sent`, as the decision says. The existing tests that changed are the ones listed under Decisions, for the reasons given.
  
  **One small point, not blocking.** `src/mail/mail.lisp:923` takes any sequence, so a single id passed as a string, `:attachments "fil_…"`, is read as a list of characters. The caller then gets «A mail can carry at most 10 files.» instead of a message saying what is wrong. It would be worth fixing later, for example by refusing a string for `attachments` as a whole.
