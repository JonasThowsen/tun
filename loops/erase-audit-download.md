# Three gaps a client met: a job erases a customer, a read is audited, a page answers a file made on the spot

- loop: erase-audit-download
- mode: reviewed
- stage: ship
- base: d9d8568bf56f5f2d0c41375dd4ddaf1a6fe047c9
- item: sak_ygs66kh0329hq80h
- estimate: 2h30m 4h 8h
- like: tun/pdf tun/mail-files tun/customers-update
- tags: kind:feature core
- verified: 293e48c545e1966e2273d1906d074861f9f1624e
- shown: 293e48c545e1966e2273d1906d074861f9f1624e

## Brief

Ferdig sak_ygs66kh0329hq80h («Three gaps a client met: a job cannot erase
a customer, a read cannot be audited, a staff page cannot answer a
file»), brought by the factory's orchestrator on 2026-11-16, after
`pdf`. The item, as filed:

> Found by a client's loop on core 2.41.0 (a customer's data exported,
> and erasure that waits some days before a job runs it). Each was worked
> around in the client; each workaround is a copy or a detour Tun should
> make unnecessary.
>
> 1. **A module's job cannot erase a customer.** `customers_erase` is
>    `:confirm t` (`modules/customers/customers.lisp:236-237`); the kernel
>    refuses a confirm tool called from an operation, workflow or job
>    without a token, and a token used in the call that asked for it
>    (`src/core/execution.lisp:570-575`, `:325-326`). Nothing exported
>    erases a customer outside the operation. The client's job repeats
>    the module's steps in its order (`customers.lisp:238-250`) through
>    `customer-erasing`, `redact-request-traces`, `redact-entity-receipts`.
>    Wanted: an exported `erase-customer` that does exactly what the tool
>    does (and that the tool calls), usable from a job under a system
>    actor, audited.
> 2. **A read cannot be audited.** Only mutations get an audit entry
>    (`src/core/execution.lisp`, about 500–530), so the client's export of
>    a person's data is declared an update that changes nothing, to have
>    it in the audit log. Wanted: a read operation can ask for an audit
>    entry (`:audit t` or the like), with who, what record and a reason.
> 3. **A staff page cannot answer a file made on the spot.** `define-page`
>    returns HTML only (`src/web/ui.lisp:79-93`) and `safe-url-p` refuses
>    `data:` links (`src/web/html.lisp:69-84`). The client shows the JSON
>    in a code block to copy. Wanted: a page (or a route beside it)
>    answers octets with a content type and a file name as a download,
>    under the page's own policy. PDF making (sak_tsfth3mm5m4013rb) needs
>    the same to hand a made PDF to the browser.
>
> Criteria, each decided by a test: a job erases a customer once with the
> same result as the tool, audited; a read operation that asks for it
> leaves an audit entry and one that does not leaves none; a page answers
> a generated file as a download with its name and type, refused for whom
> the page is refused, on a phone and without JavaScript; the clients
> pass, and the one that copied the erasure's steps can drop its copy.

The orchestrator's brief adds: the confirm rule for the tool, as a person
or agent calls it, is unchanged; choose the read's form from how
mutations are audited and say why; a download's headers are safe
(`Content-Disposition` with a properly encoded name, `nosniff`, a type
from a list Tun allows or `application/octet-stream`, never inline HTML or
SVG from data); the showcase's «Document» page gets a «Download the PDF»
that uses it, without storing the file on a record. Security in all
three, each tested: an erasure from a job must not be reachable by a
caller who could not erase through the tool; an audited read must not
put the read's data into the audit log, only who, what record and why; a
download must not let a page's data choose a dangerous type or a name
with path or header characters. Clients do not adopt these in this loop;
`docs/client-api.md` shows how a client uses each, with code, and
«Clients» below says what a client that copied the erasure's steps can
drop. Pictures in `~/coding/tun-wt/erase-audit-download-shots/`.

## Criteria

Erasing (`modules/customers/README.md` §5.1):

1. **One erasure, two ways in.** `erase-customer` is exported from
   `TUN.CUSTOMERS` and published to `TUN`, and `customers_erase`'s body is
   a call of it. Through the tool nothing changes: the existing erasure
   tests (`customers-tests`, `communication-tests`) pass unchanged; a
   call without a token answers a token; one with it erases and writes
   one entry, `customers_erase` `ok`, as its caller. (tests)
2. **A job erases as the tool does.** Of two customers alike, each with a
   quote, one erased by the tool and one by a job (`define-job`,
   enqueued by an admin, run as `system:job`) that calls `erase-customer`:
   every field of the two erased customers is alike but the id, the
   placeholder's suffix and the times; both quotes' snapshot names
   `[erased]`; both customers' receipts hold the anonymised record; the
   job succeeds and writes exactly one entry, `customers_erase` `ok` by
   `system:job` naming the customer, with the reason given, and with
   «job JOB-ID, enqueued by admin:…» when none is given. (test)
3. **Without a transaction, from a workflow, from a schedule.** A job
   with `:transaction nil` queued by an admin, a workflow an admin's call
   planned (`system:workflow`), and a job a schedule queued (a sweep, as
   `system:schedule`) erase a customer the same way, each audited once.
   (test)
4. **Not reachable by who could not erase.** `erase-customer` fails
   `forbidden`, with the customer unchanged, when it is called: in an
   operation an employee calls; in one an admin calls (not
   `customers_erase`); in an employee's operation under `with-actor` of a
   system actor; in a job an employee's operation queued, also when it
   queued it under `with-actor` of a system actor (its `enqueued_by` is
   the employee's: the outermost call's caller, jobs.md §3); in a job queued
   by a job an employee's operation queued (its `enqueued_by` is the
   employee's, jobs.md §3); and in a workflow an employee's operation
   planned. Each job among them fails at once, after one attempt; each
   refusal writes one entry `customers_erase` `rejected` `forbidden`
   naming the customer, as the actor it ran as, which outlives the
   rollback. `customers_erase` called from an operation without a token
   is still `confirmation_invalid`. (tests)
5. **A refusal of the erasure.** A customer with an open order is not
   erased by a job: `conflict`, as through the tool, nothing changed.
   (test)

Audited reads (`spec/core.md` §3.8):

6. **An entry for a read that asks.** A read declared `:audit t` writes
   one entry per successful call: its caller, tool, `ok`, the record (the
   one the body named with `audit-target`, else a stored record it
   returned, else the one its input names: `id`, or an `…_id`
   parameter), the reason the body gave with `audit-reason`, the
   request's id and the credential. The same read without `:audit` leaves none, and neither
   does `customers_get`. (test)
7. **Nothing read goes in.** An audited export of a customer whose name,
   email, phone and note are distinctive: the entry, as `audit_list`
   gives it and as stored, holds none of them. (test)
8. **The entry before the data.** An audited read whose entry cannot be
   written fails, and returns nothing of what it read; one that fails
   `not_found` writes no `ok` entry; one refused for its policy is
   audited `rejected`, as every call is. Inside a mutation its entry is
   in the mutation's transaction, and is gone when the mutation rolls
   back. Called inside another read it fails before its body runs, and
   the outer read with it, with no entry and none of its data returned.
   (tests)
9. **Declared, shown, and kept to reads.** `audit-reason` and
   `audit-target` are published to `TUN`. `:audit` on a mutation, a
   wait or a workflow operation is refused when the definition is
   expanded; `registry_describe` gives `"audit": true` for an audited
   read and for a mutation, false for another read. `audit-reason` outside a mutation and an
   audited read signals an error, and a reason over 500 characters is
   cut to 500. (tests)

Files made on the spot (`spec/files.md` §5.5, `spec/ui.md` §8):

10. **A download from a page.** `make-download` is published to `TUN`; a
    page that returns `(values 200 :download (make-download OCTETS
    :filename NAME :content-type TYPE))` answers 200 with exactly the
    octets (a string as UTF-8) and the headers of §5.5: its type
    (`; charset=utf-8` for the text types and JSON), `Content-Length`,
    `Content-Disposition: attachment; filename="…"; filename*=UTF-8''…`,
    `nosniff`, the file's `Content-Security-Policy`,
    `Cross-Origin-Resource-Policy: same-origin`, `Referrer-Policy:
    no-referrer`, `Cache-Control: no-store`. (test)
11. **Data chooses no dangerous type.** `text/html`, `image/svg+xml`,
    `application/xhtml+xml`, `text/javascript`, `application/xml`,
    `text/html; charset=utf-8`, `application/pdf\r\nX-Evil: 1` and an
    empty type are each sent as `application/octet-stream`, attachment;
    each allowed type of the table is sent as the table says, whatever
    its case. (test)
12. **Data chooses no dangerous name.** `../../etc/passwd`,
    `C:\\x\\report.pdf`, a name with CR, LF, `"`, `;`, U+202E and
    U+2028, `rapport.html` as a PDF, a name as `application/octet-stream`,
    an empty name, one of 300 characters, and «Økonomi «2026».pdf»: each
    `Content-Disposition` is one line with no CR, LF or `"` inside its
    quotes, a `filename*` of only attr-chars and `%XX`, and the cleaned
    name §5.5 gives (`passwd.pdf`, `report.pdf`, `rapport.html.pdf`, a
    name ending `.bin`, `download.pdf`, and 200 characters, `.pdf`
    included, for the long one). (test)
13. **Refused for whom the page is refused.** To a viewer, a page of
    `:employee` that answers a download answers the 403 page and makes
    nothing (its function is not called); without a session it goes to
    the login. (test)
14. **htmx and preloads.** htmx's GET of a download is answered with
    `HX-Redirect` to the same address and no body; htmx's POST with 400
    and no file; a preload with 204, declined. (test)

The showcase:

15. **«Download the PDF».** The «Document» page has a «Download the PDF»
    link; at 390 px, with and without JavaScript, and at 1280 px, a click
    downloads `board-estimate.pdf`, whose bytes start `%PDF-`, the page
    stays where it was, and no document is stored (the list of PDFs made
    is as before); the answer is `application/pdf`, attachment,
    `nosniff`; a viewer is refused it. (`checks/showcase/checks/pdf-download.py`)
16. **An audited export as a file.** The showcase's «Customer data» page
    (admin) takes a customer and a reason and downloads the customer's
    data as JSON named after the customer, at 390 px with and without
    JavaScript; an empty reason is refused with an alert and no file;
    the showcase's «Audit log» page then shows the export's entry, by
    the admin, naming the customer and the reason, and not the
    customer's email. (`checks/showcase/checks/audited-download.py`)

Kept:

17. **Clients unchanged.** Every client of Tun (factory,
    nixploy-dashboard, ferdig, kurs, tun-erp) compiles and passes its
    `bin/test` unchanged against this tree, and «Clients» below says what
    the client that copied the erasure's steps can drop, and what each
    workaround becomes.
18. **Where people read it.** `modules/customers/README.md` §5.1,
    `spec/core.md` §3.8 and §3.9, `spec/files.md` §5.5, `spec/ui.md` §8,
    `spec/pdf.md` §4, `spec/jobs.md` §3 and §4.3, and `docs/client-api.md` («Operations…», «Pages»,
    «Making a PDF», «Background jobs») say it, with code.
19. **The build.** Core 2.44.0 (`+core-version+`, `coreVersion`);
    `bin/build` warning-free, `bin/test` and `bin/check` green.

## Decisions

### Erasing outside the tool

- **`erase-customer ID &key reason`**, the tool's four steps moved into a
  function the tool's body calls, so there is one erasure. It runs in the
  caller's write transaction, or opens one when none is open (a job with
  `:transaction nil`).
- **Where it may run.** A function any Lisp code can call would let a
  client's employee operation erase without the admin policy and without
  the confirmation. So it erases only (a) inside `customers_erase`, where
  the kernel already checked the admin policy and the token, or (b) under
  a system actor, which no caller can claim (`parse-actor` refuses
  `system`). Under a person's or agent's actor, an admin's included, it is
  `forbidden`: a person's erasure keeps its confirmation, as before.
- **The job's origin.** A job runs as `system:job` whoever queued it, so
  «under a system actor» alone would let an employee's operation queue
  an erasure. A job keeps `enqueued_by`; a job queued in a job's body now
  keeps the `enqueued_by` of the job that queued it, so a chain names the
  call it started from, and a workflow, which runs in a `run-workflow`
  job queued where it was planned, names its planner the same way. A
  job queued in an operation names the operation's outermost caller
  (`*caller*`, new in the kernel), not the actor its code binds, so an
  employee's operation that queues under `with-actor` of a system actor
  still queues as the employee (gate B, round 1). A job's run and the
  schedules' tending bind no caller, also when `clock_set` runs them.
  `erase-customer` in a job erases only when that origin is an admin or
  the system, and otherwise fails the job at once (`fail-job`): another
  attempt cannot succeed. In a workflow it fails the workflow instead
  (`forbidden`, which the workflow's run records as failed): a workflow
  left planned would be queued again when the application opens, as the
  system, and erase. Not closed: a workflow whose job ended for good for
  another reason (three crashes) while it stayed planned is queued again
  when the application opens, as `system` (`enqueue-planned-workflows`);
  an erasure planned by an employee could then run. It takes three
  crashes of the same workflow first; recording who planned a workflow
  on the workflow itself would close it, a change to the kernel's
  `workflows` table that this loop does not make. It needs a job to be running (`running-job`,
  new in `tun.jobs`, exported, not published) and a system actor, so
  `with-actor` of a system actor inside a person's operation is refused
  too: no job runs there.
- **The system's own decisions erase.** A schedule or a trigger queues
  as `system:schedule`: the application's code decides, on records it
  reads. The client's own design is this one (an admin asks with a
  reason and confirmation, the request waits some days, an hourly sweep
  erases what is due), so refusing system-queued erasures would leave
  the client its copy. Who may write the records a sweep reads is the
  application's policy; the README says to ask for an erasure in an
  admin's confirmed operation, as the tool is. Whether a schedule's job
  should be allowed is put to the owner in the report.
- **Audited as the tool.** Outside the tool it writes the entry itself,
  tool `customers_erase`, so `audit_list` of the customer shows every
  erasure under one tool name, the system actor, and as `reason` the
  caller's or where it ran («job JOB-ID, enqueued by admin:ada»), which
  ties it to who asked. Inside the tool, the tool's own entry is the
  audit, and no second is written. A refusal writes a `rejected` entry
  deferred past the rollback (`defer-audit`), as the kernel's refusals.
- **Erasing twice** erases again, as the tool does today; a job that may
  run after another erasure checks `customer-erased` (the example does).
  Making a second erasure do nothing would change the tool.

### Audited reads: `:audit t`

- **The form follows the mutations'.** A mutation is audited by the
  kernel, its record taken from the result or the input or named with
  `audit-target`, its reason given by the body. A read declared `:audit
  t` gets exactly that entry, written by the same `write-audit`. So the
  record is found as for a mutation (an export's `customer_id` names its
  customer), and the reason comes from the body, which takes it from a
  parameter the operation declares, required or not as the operation
  wants: the input schema is where a caller learns that a reason is
  asked, as for every other input. A reason the kernel added as a hidden
  parameter would be the only input not declared.
- **`audit-target`** is published to `TUN` too, so a client's audited
  read that returns a document, not a record, names its record.
- **`audit-reason TEXT`**, new and published: clients have no
  `audit-as` (it can also name another actor, which a client should not
  write into the log), and an audited read needs a reason. It signals an
  error outside a mutation or an audited read, so a reason given in a
  read that is not audited is not silently lost.
- **Only for `:read`.** A mutation is always audited; a wait or a
  workflow operation is not a read the caller asks for once.
- **The entry first, then the data.** The read runs in its read
  transaction, then the entry is written in a short write of its own,
  and only then is the result returned. If the entry cannot be written
  the call fails, so no data leaves unaudited. Holding a write
  transaction for the whole read would make a long export block every
  writer. Nested in a mutation, the entry is in its write. Nested in a
  read, it cannot be written before the data goes to the outer read, so
  the audited read is refused there before it reads (an error, as a
  write in a read is); a deferred entry whose write could fail after the
  data was returned is what this avoids.
- **Nothing of the data.** The entry has no field for a result, and its
  input is only the target's id and the request key; a test asserts that
  an export's distinctive values are in no entry.

### Downloads: `(values 200 :download (make-download …))`

- **A return value of the page's function**, beside `:fragment` and
  303, rather than a route of its own: the page's policy, login redirect
  and 403 are the ones the page already has, decided before its
  function runs, so a download can never be reached by someone the page
  refuses, and nothing new is registered. A route beside the page is the
  page's own path (`/document/board-estimate.pdf`).
- **The type is the page's word, from a list.** Tun does not sniff the
  bytes: the list is what a browser saves rather than runs, and anything
  else, `text/html` and SVG among them, goes as `application/octet-stream`
  rather than failing the page, since the type may come from data. With
  `attachment`, `nosniff` and the file's sandbox CSP, a wrong type is
  harmless in the browser.
- **The name ends in its type's extension**, `.bin` for
  `application/octet-stream`: a saved `x.html` of a page's data would
  open as a page from the disk, outside every header. The cleaning is
  the stored file's (`files.md` §2.3), shared, so CR and LF never reach a
  header.
- **`Cache-Control: no-store`**, where a stored file has `private,
  no-cache` and an ETag: a made file may hold a person's data and is
  made again each time.
- **htmx.** A staff page's links are boosted; a boosted download would be
  swapped into the page as text. The link carries `hx-boost="false"`
  (documented); one that forgets is answered `HX-Redirect`, so the
  browser fetches it itself (made twice, but it works); htmx's POST
  cannot be repeated, so it is answered 400. A preload is declined, as a
  page that records something declines one.
- **Sent whole from memory**: the content is already made and in memory;
  sending in parts is for stored files read from the database.

### The showcase

- «Download the PDF» on «Document» makes the same PDF as «Make the PDF»
  and answers it; nothing is stored, and the check counts the documents
  before and after.
- A «Customer data» page (admin, under «System») exports a customer's
  data through an audited read of the showcase's, `customer_data_export`,
  with a reason, as a JSON download named after the customer, and an
  «Audit log» page (admin, under «System») lists `audit_list`, so the
  pictures show the audited read in the log. The client's case is this
  one: an export of a person's data, now a read.

### The rest

- **The core version** goes to 2.44.0: new interface (`erase-customer`,
  `:audit`, `audit-reason`, `make-download`, `running-job`). The
  customers module reads the running job with `running-job`, so its core
  range becomes `>= 2.44.0` (`define-module` and its `flake.nix`).

## Verify rounds

1. Build and tests green. Six checks failed, for two faults of mine and
   one I did not cause: the showcase's new `customer-options` had the
   name of a function `lists.lisp` already defines, so the item form that
   used the old one answered 500 (`files-paste`, `form-nits`,
   `generated-choice`, `ui-choice`); the «Download the PDF» page read the
   cards with `with-transaction`, which a client's package does not have,
   so it answered 500 and the browser cancelled the download
   (`pdf-download`). Fixed: the function renamed, and the page reads the
   estimate through a read operation of the showcase's,
   `documents_estimate`, as a client's page must; `docs/client-api.md`'s
   example does the same. `loading-sign` failed one of its 23 steps («a
   fast page swapped in after the bar showed keeps it while the slow one
   is under way»), which this loop does not touch. The round waited 31
   minutes for the verify lock.
2. Green: build, tests, all 53 checks, `loading-sign` among them, so its
   step in round 1 failed for a reason of its own (another builder's load
   is the likely one; nothing here changes what it measures). The round
   waited 31 minutes for the verify lock.
3. After gate B's first round (a job queued under `with-actor` of a
   system actor named that actor, not the caller): build and tests
   green, `loading-sign` failed the same one step as in round 1, and
   every other check passed. Run alone it passed (after 36 minutes for
   the lock).
4. The same: build and tests green, `loading-sign`'s same step failed
   in the full run; alone, three times in a row, it passed.
5. Green: build, tests, all 53 checks.

`loading-sign`'s failing step is a race in the check, not in this
loop's change, which touches neither the kit's script nor the `/wait`
page: after it taps «A fast page» it waits for «This page waited 0
ms.», which the page it is on already says, so it reads the bar at any
moment of the fast page's swap. The kit gives the swapped-in page a
hidden bar and shows it again on `htmx:after:swap`; a read between the
two finds it hidden. It failed in three of five full runs and in none
of four lone runs here. Waiting for the swap itself (counting
`htmx:after:swap`) before reading would make it hold; that is the
check's own loop's to change, and is in the report.

## Pictures

In `~/coding/tun-wt/erase-audit-download-shots/` (outside the
repository), taken from the shown preview after verify round 2, all
looked at (round 3's change, who a job names as asking for it, shows on
no page):

- `document-download-phone.png`, `document-download-wide.png`: the
  «Document» page with «Make the PDF» and «Download the PDF» under it;
  the click after each picture downloaded `board-estimate.pdf`. On the
  phone's full-page picture the sticky header is drawn over the middle
  of the code block, as a full-page capture draws a sticky header.
- `customer-data-phone.png`, `customer-data-wide.png`: «Customer data»
  with a customer chosen and a reason given; the click downloaded
  `customer-Fjord Events.json`.
- `audit-log-wide.png`: the «Audit log» with the two exports on top,
  `customer_data_export` by `admin:jonas`, «customer cus_…» and each
  reason; no name or email of the customer. `audit-log-phone.png`: the
  same log on a phone, its record, reason and outcome columns scrolled
  out of the table's own box, which scrolls sideways while the page does
  not.

The preview's own screenshots of `/document`, `/customer-data` and
`/audit` at 390 and 1280 px are in `.build/loop/erase-audit-download/show/`.

## Clients

On this loop's tree after verify round 2 (core 2.44.0, commit
`02b9a188`), each client's
`bin/test` from a clone in a scratch folder, with `--override-input tun`
at the worktree (and `dashboard`, and the ERP client's `customers`, at
its `modules/` directories), one at a time under the verify lock,
unchanged: kurs (352 checks), factory (773), nixploy-dashboard (1421),
ferdig (812) and the factory's ERP client (its suites of 9154, 75409,
378, 387, 373, 8856, 255, 109920, 91034, 16264, 26179 and 111 checks)
pass, with no compiler warning and no failure. Run again after verify
round 5, on the final tree (`7f6a95c1`, with `*caller*`): the same
counts, the ERP client's second suite 71841 checks (it generates its
cases), all passing, no warning. No client changes. The
ERP client's own erasure keeps working as it was: its method on
`customer_erasing` still refuses `customers_erase`, which now reaches it
through `erase-customer`.

What the client that copied the erasure's steps (the factory's ERP
client, its customer-relationship module) can drop, once it takes
2.44.0, and what each workaround becomes:

- **Its copy of the erasure.** Its own function that repeats
  `customers_erase`'s steps (`customer-erasing` with its own flag set,
  `redact-request-traces` of the id, name, email, phone and note, the
  placeholder name and email, `customer-erased-at`, `save`,
  `redact-entity-receipts`) becomes one call in its job:
  `(erase-customer customer-id :reason (erasure-request-reason request))`.
  Its job is queued by its hourly schedule's sweep, `system:schedule`,
  so the erasure is allowed (README §5.1). Its `customer_erasing` method
  that refuses every erasure but its own keeps its flag, bound around
  the call. Its own audit entry (`crm_erase_customer`, with the
  request's reason) may stay; `customers_erase` by `system:job` with the
  same reason is now written beside it.
- **Its export declared an update that changes nothing**, with
  `audit-as :reason "export"` and `show-once` to keep the document out of
  its receipt, becomes a `:read` with `:audit t` and `(audit-reason
  "export")`, or a reason the caller gives: a read stores no receipt, so
  `show-once` is not needed.
- **Its page that shows the export's JSON in a code block to copy**
  becomes a download: `(values 200 :download (make-download (to-json-string
  document) :filename "customer-….json" :content-type
  "application/json"))`, as `docs/client-api.md` («Pages») shows.

## Log

- 2026-11-16 05:49  started, reviewed
- 2026-11-16 05:49  estimated 2h30m 4h 8h at brief, like tun/pdf tun/mail-files tun/customers-update
- 2026-11-16 05:53  gate A asked of a reviewer
- 2026-11-16 05:55  gate A: changes (reviewer)
  I'm asking for changes. Most of the spec is sound, but there are three substantive gaps and a few small inconsistencies.
  
  **What is right**
  - **The brief is covered.** All three items and the orchestrator's additions have criteria: erasing (1–5), audited reads (6–9), downloads (10–14), the showcase (15), clients unchanged (17), docs (18) and the version (19). The three security demands each have a test: 4, 7, and 11–12.
  - **The read's form is justified, as the brief asked.** The Decisions say why `:audit t` reuses `write-audit`, `audit-subject` and a declared reason parameter, and it matches the existing code (`src/core/execution.lisp:106-161`). Cutting the reason to 500 characters matches `audit-as` (`:136`).
  - **The criteria can be decided.** Each one names exact headers, inputs and outcomes, so a test or check can settle it.
  - **The spec text agrees with the criteria** in most places. That covers `files.md` §5.5, `core.md` §3.8, `ui.md` §8, `pdf.md` §4, `jobs.md` and customers README §5.1. The confirm rule for people and agents is kept, as the brief asked (criteria 1 and 4).
  - **The extra showcase pages are fine.** Criterion 16 («Customer data», «Audit log») goes a little beyond the brief, but it shows the client's own case and gives the pictures the audited read. I don't object to it.
  
  **Changes**
  
  1. **The security rule for erasing is left open, and widened past what was asked.** The brief says an erasure "must not be reachable by a caller who could not erase through the tool". The spec knowingly leaves two ways through:
     - **Workflows.** Erasing from a workflow (criterion 3; README §5.1, "under a system actor … a workflow's `system:workflow` … it erases") was not asked for. The brief says "usable from a job". With no record of who planned the workflow, an employee's operation that plans one can erase. The README only says not to do this.
     - **A job a job queued.** If an employee's operation queues job A and A queues job B, then B's `enqueued_by` is `system:job`, so B erases. Triggers have the same problem when an employee's write fires them.
  
     The Decisions argue this "needs client code written to do it". That is equally true of the case the spec does close (an employee's operation queuing the erasing job), so it doesn't explain why one is closed and the others aren't. Either close them or put the hole to the asker as their decision. To close them:
     - drop the workflow path, or record who planned the workflow;
     - give a job queued from a job (or a trigger) the original `enqueued_by`;
     - add those cases to criterion 4.
  
  2. **An audited read can return its data without an entry.** `core.md` §3.8 says an audited read inside another read has its entry written "when the outermost read ends" (`defer-audit`). That entry goes through `flush-deferred-audits` (`src/core/execution.lisp:166-170`), which only logs a failure. So the data has already gone to the outer read, and to its caller, while the entry can still be lost. That breaks the spec's own sentence, "a read whose entry cannot be written fails, and its data is not returned". Criterion 8 doesn't test this case. The spec should say that the outermost call fails when a deferred read entry cannot be written, with no swallowed error, and criterion 8 should test it.
  
  3. **The «Clients» section is missing.** The brief asks that "«Clients» below says what a client that copied the erasure's steps can drop". `loop.md` has no such section, and no criterion requires one. Add the section, naming the client's copy (`customer-erasing`, `redact-request-traces`, `redact-entity-receipts`, in the tool's order) and the `erase-customer` call that replaces it. Also add a line to criterion 18.
  
  4. **Small inconsistencies to fix in the same pass:**
     - **The length of a long name.** `spec/files.md` §5.5 says a long name "is cut to 200 before its extension", which allows 200 characters plus `.pdf`. Criterion 12 says "at most 200 characters". Make them say the same.
     - **`registry_describe`.** The `core.md` change says `"audit": true` "for every mutation", but criterion 9 only tests reads. Add a mutation to the criterion, or drop the claim.
     - **The order of the record in criterion 6.** It lists the input before "a record it returned". The spec and `audit-subject` use `audit-target`, then the returned record, then the input. Give criterion 6 that order, and include `audit-target`.
- 2026-11-16 05:58  gate A asked of a reviewer
- 2026-11-16 05:59  gate A: changes (reviewer)
  I'm asking for changes in round 2, but they're small. The round-1 findings are fixed. Two passages in `docs/client-api.md` don't yet match the criteria and the rest of the spec, and one of them gets the erasure's security rule wrong.
  
  **What is right**
  - **Erasing from a job chain or a workflow is closed.** A job queued by another job now keeps the first job's `enqueued_by`, and a workflow records who planned it (`spec/jobs.md` §3, at diff lines 343–349). Criterion 4 now tests an employee's job chain and an employee's workflow. The README §5.1 table agrees with it.
  - **Triggers are not a gap.** In this repository a trigger is a sweep the system runs (`spec/jobs.md` §8.1), not something an employee's write fires. So `system:schedule` is a fair origin. Who writes the records a sweep reads is honestly marked as the application's decision, and the schedule case is put to the owner. That case is needed for the client to drop its copy.
  - **An audited read inside another read now fails before its body runs.** Criterion 8 tests this, and `spec/core.md` §3.8 says the same. No deferred entry can be lost after the data has gone out.
  - **The «Clients» section is there.** It names the copied steps in the tool's order and the one `erase-customer` call that replaces them, and covers the other two workarounds. Criterion 17 requires the section.
  - **The three small points are fixed:**
    - The long-name rule (200 characters, extension included) is the same in criterion 12 and `spec/files.md` §5.5.
    - Criterion 9 now covers a mutation in `registry_describe`.
    - Criterion 6 gives the record's order as `audit-target`, then the record returned, then the input, as §3.8 does.
  - **The confirm rule for the tool is unchanged** (criteria 1 and 4), as the brief asked. Every criterion can still be decided by a test or a check.
  
  **Changes**
  1. **`docs/client-api.md`, diff line 118, says the wrong rule for where an erasure runs.** It reads: "It erases only in a job an admin or the system queued, or in a workflow". That says any workflow may erase. The README §5.1 table, `spec/jobs.md` §3 and criterion 4 all say a workflow erases only when an admin or the system planned it, and that an employee's workflow is `forbidden`. This document is where client authors learn the security rule, so it must match. Something like: "only in a job or a workflow that an admin's call or the system asked for, however many jobs lie between".
  2. **`docs/client-api.md`, diff lines 9–13, describes the audited read's record loosely.** It says "the record the input or the result names". That leaves out `audit-target` and puts the input before the result. This is the same mismatch round 1 flagged in criterion 6, which is now fixed there. Write the order as criterion 6 and §3.8 give it: `audit-target`, else a stored record returned, else the input's `id` or `…_id`.
- 2026-11-16 05:59  gate A asked of a reviewer
- 2026-11-16 06:00  gate A: approve (reviewer)
  I approve the spec at gate A.
  
  **The two changes from round 2 are made**
  - **Where an erasure may run.** `docs/client-api.md` (diff lines 117–124) now says an erasure runs only "in a job or a workflow that an admin's call or the system … asked for, however many jobs lie between". An employee's job or workflow, and any person's operation (an admin's included), gets `forbidden`. That matches the README §5.1 table, `spec/jobs.md` §3 and criterion 4.
  - **Which record an audited read names.** `docs/client-api.md` (diff lines 9–14) now gives the order as `audit-target`, then a stored record returned, then the input's `id` or `…_id`. That matches criterion 6 and `spec/core.md` §3.8.
  
  **What is right**
  - **The brief is covered.** It is all there and nothing extra is in it:
    - erasing from a job, audited, under a system actor (criteria 1–5);
    - the confirm rule unchanged for people and agents (criteria 1 and 4);
    - audited reads that keep the read's data out of the log (criteria 6–9);
    - downloads with safe headers, names and types, under the page's policy, on a phone and without JavaScript (criteria 10–15);
    - the showcase's «Download the PDF» with nothing stored (criterion 15);
    - clients unchanged and the «Clients» section (criterion 17);
    - the docs with code (criterion 18).
  - **Each security demand has its own test:** criterion 4 for erasing, 7 for audited reads, and 11–12 for downloads. Criterion 13 covers a refused page.
  - **Every criterion can be decided by a test or a check.** Each names exact inputs, headers, cleaned names and outcomes.
  - **The spec text agrees with the criteria.** This covers the audit semantics in `core.md` §3.8, the type table, name cleaning, the 200-character limit, the headers and htmx in `files.md` §5.5, and the `enqueued_by` chain and `running-job` in `jobs.md` §3.
  - **The read's form is chosen from how mutations are audited, and the Decisions say why,** as the brief asked.
  - **The schedule case is put to the owner.** Whether a schedule's job may erase is an open question, and the Decisions say it goes to the owner in the report. That case is what lets the client drop its copy, so allowing it for now is reasonable.
  
  **A note for gate B, not a reason to block**
  
  Changing `enqueued_by` for a job queued inside another job's body changes behaviour on its own. The dashboard shows that field (`modules/dashboard/jobs.lisp:190`). Today, only the erasure cases in criterion 4 would catch a regression. At gate B, check that the jobs tests assert the chained `enqueued_by` directly, next to the existing assertion at `tests/jobs-tests.lisp:117`.
- 2026-11-16 07:10  verify 1: failed check
- 2026-11-16 08:02  verify 2: passed build, test, check
- 2026-11-16 08:03  shown (/document, /customer-data, /audit)
- 2026-11-16 08:20  gate B asked of a reviewer
- 2026-11-16 08:22  gate B: changes (reviewer)
  **I'm asking for changes: one hole in the erasure's security rule. Everything else is sound.**
  
  **What is right**
  - **Verification passed.** Round 2 of `verify.txt` passed build, test and check. All 53 checks pass, `pdf-download` and `audited-download` among them, with every step `ok`.
  - **Erasing (criteria 1–5).** `customers_erase` is now a call of `erase-customer` (`modules/customers/customers.lisp`, diff 650–652), so there is one erasure.
    - `tests/erasure-tests.lisp` tests most of it: the tool path, the twin customers, the job without a transaction, the workflow, the schedule's job, the conflict case, and six of the refusal cases.
    - It also tests that each refused job fails after one attempt, and that each refusal writes one `rejected` entry.
    - The gate A note is done: `tests/jobs-tests.lisp:112` asserts the chained `enqueued_by` directly.
  - **Audited reads (criteria 6–9).** `execute-read` (diff 1032–1059) writes the entry before it returns the data. Inside a read it is refused before the body runs, and inside a mutation it rolls back with the mutation.
    - The tests cover the credential, the request id, the three ways the record is found, distinctive values absent from the entry both as `audit_list` gives it and as stored, a refusal at expansion for each kind, `registry_describe`, and the 500-character cut.
  - **Downloads (criteria 10–14).** The type comes from a fixed table matched exactly, so a CR/LF or a parameter goes to `application/octet-stream`. The name cleaning is shared with stored files.
    - `send-download` sets every header §5.5 lists and handles preloads and htmx.
    - `tests/download-tests.lisp` checks every listed type and name, the 403 without the page's function running, and the login redirect.
  - **The showcase (criteria 15–16).** «Download the PDF» works at 390 px with and without JavaScript and at 1280 px, and stores nothing. «Customer data» refuses an empty reason with an alert and no file.
    - The «Audit log» shows the export's entry with the admin, the customer and the reason, and no email.
    - The screenshots show the three pages at both widths. The preview's own phone audit-log shot predates any export, but the check asserts the entry.
  - **Docs, version and clients (criteria 17–19).** The spec, the README §5.1 and `docs/client-api.md` say the same as the code. The version is 2.44.0 in `module.lisp` and both `flake.nix` files. «Clients» reports each client passing and says what the ERP client can drop. I found no leftover debugging or dead code.
  
  **Changes**
  
  1. **An employee's operation can still erase through a job, by queuing it under a system actor.**
     - `job-origin` (`src/jobs/jobs.lisp`, diff 1249–1256) takes `enqueued_by` from the current `*actor*`. `with-actor` and `system-actor` are both published to clients (`src/public.lisp:108`).
     - So an employee's operation that runs `(with-actor ((system-actor "x")) (enqueue-job 'erase-later :customer-id id))` queues a job whose `enqueued_by` is `system:x`. `admin-or-system-p` (`customers.lisp`, diff 657–663) accepts that, and the job erases.
     - This goes against the brief ("must not be reachable by a caller who could not erase through the tool"). It also goes against the README §5.1 table and the Decisions, which both say `with-actor` of a system actor inside a person's operation is refused. Only the direct call is closed (`erase_customer_as_system`); the call through a job is not.
     - It is the same kind of hole gate A asked to close for chains of jobs.
     - **To fix it:** have `job-origin` name the person or agent behind the current call (the request's caller) whenever there is one, ahead of a rebound `*actor*`. Keep `system` only for work no person called: schedules, triggers, start-up.
     - Then add a case to `no-caller-who-could-not-erase-reaches-erase-customer`: an employee's operation that queues `erase-customer-job` under `with-actor` of a system actor is refused once, its job fails after one attempt, and its `enqueued_by` is `employee:anna`. Add that case to criterion 4 and to `spec/jobs.md` §3 as well.
- 2026-11-16 08:39  verify 3: failed check
- 2026-11-16 09:33  verify 4: failed check
- 2026-11-16 10:30  verify 5: passed build, test, check
- 2026-11-16 10:31  shown (/document, /customer-data, /audit)
- 2026-11-16 10:48  gate B asked of a reviewer
- 2026-11-16 10:49  gate B: approve (reviewer)
  I approve gate B (round 2): the fix for round 1 is made and tested, and verify round 5 passed build, test and check.
  
  **Round 1's change is fixed**
  - **The fix.** A new kernel variable, `*caller*`, holds the caller of the outermost operation (`src/core/execution.lisp`, diff 1029–1042). `job-origin` uses it before `*actor*`, after the running job's own `enqueued_by` (`src/jobs/jobs.lisp`, diff 1272–1281). So an employee's operation that queues a job under `with-actor` of a system actor still queues it as `employee:anna`.
  - **No stale caller leaks in.** The job runner (diff 1307) and the schedules' tending (diff 1322) set `*caller*` to nil. This also holds when `clock_set` runs them.
  - **The test.** `no-caller-who-could-not-erase-reaches-erase-customer` (diff 2097–2106) covers the case. It checks that the queued job's `enqueued_by` is `employee:anna`, then that the customer is not erased and has exactly one `rejected` `forbidden` entry.
  - **Criterion 4 and `spec/jobs.md` §3** (diff 916–924) now say the same.
  - **Not added to `TUN`.** `*caller*` is exported from `tun.core` only, not published to clients (`src/public.lisp`).
  
  **What is still right from round 1**
  - **Erasing (criteria 1–5).** `customers_erase` is a call of `erase-customer`. The tests cover:
    - the tool's path and its confirmation from code;
    - two like customers, one erased by the tool and one by a job;
    - a job without a transaction, a workflow and a schedule's job;
    - every refusal case, each job failing after one attempt;
    - the conflict case.
  - **The gate A note is done.** `a-job-queued-by-a-job-names-who-asked-for-the-first` (diff 2152–2172) checks the chained `enqueued_by` directly.
  - **Audited reads (criteria 6–9).** `execute-read` writes the entry before it returns the data, and refuses an audited read inside another read before its body runs.
  - **Downloads (criteria 10–14).** The type comes from a fixed list, the name cleaning is shared with stored files, and the headers, htmx and preload handling are tested in `tests/download-tests.lisp`.
  - **The showcase (criteria 15–16).**
    - The `pdf-download` and `audited-download` checks pass.
    - The shots show «Document», «Customer data» and «Audit log» at 390 and 1280 px.
    - The phone shot of the audit log was taken before any export and shows only the table's first columns. The check asserts the export's entry, so that is acceptable.
  - **Clients, docs and version (criteria 17–19).**
    - «Clients» reports every client passing on the final tree, and says what the ERP client can drop.
    - The core is 2.44.0 everywhere, and the customers module needs `>= 2.44.0`.
    - I found no leftover debugging or dead code.
  
  **One gap that the owner's report must name, not a reason to block**
  
  The Decisions name it themselves ("Not closed"), and I confirmed it in the code:
  - When a `run-workflow` job fails for good after three crashes, its workflow stays `planned`.
  - When the application opens, `enqueue-planned-workflows` (`src/platform/workflows.lisp:199-205`) queues it again under `system:reconcile`. `admin-or-system-p` accepts that, so a workflow an employee planned could then erase.
  
  Reaching it takes three crashes of the process, not something a caller can choose, and the Decisions say what would close it: recording on the workflow itself who planned it. But it falls short of the brief's "must not be reachable by a caller who could not erase through the tool". `modules/customers/README.md` §5.1 and `docs/client-api.md` also say without exception that an employee's workflow is `forbidden`. Unlike the schedule question, the Decisions don't say this goes to the owner in the report. The report should say so, and the docs should get a one-line caveat when it is next touched.
