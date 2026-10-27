# Filer, som skjermbilder, kan legges ved en sak

- loop: attachments
- mode: autonomous
- stage: ship
- base: bf51a48cdc1fde6dd6aa2fdbc789fe260f876169
- verified: 750291403154e8b8c3f9eac073b3743d6e4de5b2
- shown: 750291403154e8b8c3f9eac073b3743d6e4de5b2

## Brief

Requested by Jonas on 2026-10-26, through an agent working on a client:

> Files attached to records (core). Uploading images, screenshots in
> particular, and showing them.
> - Pages: a form field for one or more files (click, drag-drop, and
>   paste from the clipboard, which matters for screenshots).
> - MCP and /api: base64 or a URL, your call, so an agent can attach a
>   screenshot.
> - Stored by Tun, in Postgres or on disk; your call, given the deploy
>   setup. Size limit and allowed types (at least png, jpeg, webp, gif,
>   pdf).
> - Served only to those allowed to see the record they belong to,
>   through the client's policy.
> - Shown as thumbnails that open full size.

Jonas approved it on this condition: «make sure the parts that are in
tun are agnostic to [the client] itself».

The contract is the new `spec/files.md`, with pointers from
`spec/core.md` (§7.5, bounded inputs), `spec/ui.md` §6, `spec/api.md`
and `spec/README.md`. The change is shown in the showcase: its cards
take files, `/saker/ID` shows a card's files and adds more, and
`/saker/ny` reports a card with screenshots in one post.

## Criteria

Tests are in `tests/files-tests.lisp` unless another file is named;
checks in `checks/showcase/checks/`.

1. **Opting in.** An entity with `:attachments t` takes files, at most
   20 per record; `(:max N :policy ROLE)` sets both. `:max` outside
   1–100, a `:policy` other than `:employee` or `:admin`, an unknown
   key, and the option on an embedded entity are refused when the
   definition is compiled. `registry_describe` gives each entity's
   `attachments` as `{"max", "policy"}` or `null`. Attaching to a record
   of an entity without the option is `invalid_input`.
2. **Types by bytes.** A PNG, a JPEG, a WebP (lossy, lossless and
   extended), a GIF and a PDF are each stored with the `content_type` of
   `spec/files.md` §2.1 whatever their filename says (a PNG named
   `a.pdf` is `image/png`). Refused with `invalid_input` and the
   message of §2.1 at the file's place (`files[1]`): an SVG named
   `bilde.png`, an HTML file, text named `.png`, a ZIP.
3. **Damaged files.** Refused as damaged, with the message of §2.1:
   - PNG: cut off inside `IHDR`; a chunk whose stated length runs past
     the end; no `IDAT`; no `IEND`; an unknown critical chunk (`ABCD`);
   - JPEG: a segment whose stated length runs past the end; no frame
     header before the scan; a second frame header; a `DNL` segment, and
     a frame of height 0; no `EOI` (while a JPEG with fill bytes, `FF FF
     FF` before a marker, is taken);
   - WebP: a RIFF size past the end; a chunk whose stated length runs
     past the end; no image data;
   - GIF: a colour table or an image descriptor cut off; a sub-block
     whose length runs past the end; a block of an unknown kind (`0x2A`);
     no trailer; a logical screen of width 0;
   - an APP1 stating 4 octets followed by `Exif\0\0` is read within its
     own segment;
   - a JPEG with `RST0`, `RST7` or `TEM` outside a scan;
   - for each format, a file of 100 001 pieces (JPEG `DRI` segments, PNG
     `gAMA` chunks, GIF graphic control extensions, WebP `ALPH` chunks);
     the same with 99 000 is taken;
   - fifty seeded mutations (cut off, octets changed, octets put in) of
     each format's test files are each taken or refused as damaged, and
     none fails in any other way.
4. **Size and dimensions.** Width and height are read from each image
   type's header; a JPEG with Exif orientation 6 gives them swapped; a PDF
   has `null` for both. An image of 30 001 px on a side, or 50 000 001
   pixels in all, is refused, and so is a GIF whose logical screen is
   small but one of whose frames is 30 001 px wide, and a WebP with such
   an `ANMF` frame; 30 000 × 1 600 is taken. A file of exactly 10 MiB is
   taken, one byte more is refused, and an empty file is refused; 11
   files in one call, or files of more than 25 MiB together, are
   refused. A call that would take a record past its `:max` is refused,
   and none of its files is stored.
5. **Metadata taken out, by allowlist.** In each case what is kept is
   byte for byte as given:
   - from a JPEG with Exif holding GPS, XMP, IPTC (`APP13`), a comment,
     an `APP0` `JFXX`, a JFIF `APP0` with a thumbnail, an `MPF` segment,
     an `APP15`, and a second image after `EOI`, the stored file has
     none of them (no `Exif\0\0` but the minimal one, no
     `http://ns.adobe.com/xap`, no `Photoshop 3.0`, no `JFXX`, no `MPF`,
     nothing after the first `EOI`) and its JFIF `APP0` has thumbnail
     size 0 × 0, while its `ICC_PROFILE`, `Adobe`, tables, frame header
     and scan data are kept; a progressive JPEG with a comment between
     two scans loses it and keeps both scans; its orientation 6 is kept
     as a minimal Exif with only that tag, and a JPEG with orientation 1
     gets no Exif at all;
   - a PNG keeps only the chunks listed in §3 (with `iCCP`, `pHYs` and
     APNG's `acTL`, `fcTL` and `fdAT` in the test file) and loses
     `eXIf`, `tEXt`, `zTXt`, `iTXt`, `tIME`, an unknown ancillary chunk
     (`prVt`) and anything after `IEND`;
   - a WebP keeps only the chunks listed in §3 and loses `EXIF`, `XMP `
     and an unknown chunk; its `VP8X` flags for them are cleared and its
     RIFF size matches its length;
   - a JPEG whose Exif has its IFD offset past its end, and one with two
     Exif segments, are taken upright as stored, with no Exif;
   - a GIF loses its comment extensions, its plain text extensions, an
     `XMP DataXMP` application extension and bytes after the trailer, and
     keeps `NETSCAPE2.0`, its graphic control extensions and every frame;
   - a PDF is stored byte for byte as given.

   Nothing in the file handling inflates or decodes image data or runs a
   program: a test reads `tun.asd` and the file handling's sources and
   fails when the systems they belong to depend on `chipz`, `deflate`,
   `zlib`, `salza2`, `opticl`, `pngload`, `png-read`, `cl-jpeg`,
   `retrospectiff` or `skippy`, or when those sources call `run-program`
   (`sb-ext:` or `uiop:`) or `launch-program`.
6. **Names.** `../../etc/passwd.png` with PNG bytes is stored as
   `passwd.png`; `C:\Users\kari\Skjerm "1".png` as `Skjerm 1.png`;
   `faktura‮gnp.pdf` (U+202E) with PDF bytes as `fakturagnp.pdf`; a name
   holding a tab, U+0000, U+200B, U+200E, U+2066 and U+2029 loses each of
   them; a 250-character name ending in `.png` is cut to 200 keeping
   `.png`, and a 198-character name without an extension, with PDF
   bytes, is 200 characters with its `.pdf`; a 256-character name is
   refused with the message of §2.3, and 255 is taken;
   `skjermbilde` with PNG bytes is `skjermbilde.png`, `faktura.png` with
   PDF bytes `faktura.png.pdf`, `bilde.JPEG` stays, and an empty name is
   `fil.png`.
7. **Agents' input.** Over MCP and `/api`, `attachments_add` takes files
   as `{"filename", "data"}` with standard base64; line breaks in `data`
   are ignored; a character outside the alphabet, or bad padding, is
   refused; a `data` starting `data:image/png;base64,` is refused with
   its own message (§4.1); an object with `url` is refused with the
   message of §4.1 and nothing is fetched; an `upload` handle sent over
   MCP is refused. The tool's JSON Schema in `tools/list` has
   `contentEncoding: base64`.
8. **The tools.** `attachments_add` (employee), `attachments_list`
   (viewer) and `attachments_remove` (employee) do what §4.2 says and are
   audited with the record as their target; `attachments_add` with the
   same `request_key` twice stores the files once. A viewer adding is
   `forbidden`, and an employee adding to an entity with `:policy :admin`
   is `forbidden`. On Postgres, with a record policy that gives each
   employee their own records, Ola gets `not_found` from all three tools
   for Kari's record and her file, the same answer as for an id that does
   not exist. `attachments_remove` of a file whose entity is no longer
   defined, or no longer has `:attachments`, is `not_found` for an admin.
   Removing: Kari removes a file she attached; Ola, an employee who may
   see the record, gets `forbidden` for Kari's file and it stays, while
   an admin removes it; after Kari's role changes to admin and back, her
   files are still hers (`created_by` names the account, compared by
   name); a file the system attached is `forbidden` to an employee and
   removed by an admin; an employee who may not see the record gets
   `not_found`, never `forbidden`. Each attachment's `created_by` is the
   actor that attached it.
9. **The `files` type in an operation, and what requests keep.** A
   client operation taking `(files :max 3)` that inserts a record and
   calls `attach-files` stores both in one transaction: with one file
   refused, neither the record nor any file is there. A stored field of
   type `files` is refused when the entity is compiled. After a call over
   MCP with a file, the request record in the in-memory history (the
   object itself, not `introspect_request`'s JSON) keeps that file's
   input as exactly `{"filename", "bytes"}`, its filename at most 255
   characters, and no string anywhere in the record is longer than
   1 MiB or holds the file's base64; the same for a call from a page (no
   handle kept; a page's request record keeps no operation input at all,
   so the test checks that it holds no handle and no string over 1 MiB).
   When such a call fails as a fault, the error recorded
   in the store (`error_groups` and `error_occurrences`) keeps no input,
   and its message holds no part of the base64. A large body whose
   `title`, or any string but a file's `data`, is over 1 MiB is answered
   413 (`-32600` on `/mcp`) before any tool runs, and the request record
   holds no string over 1 MiB.
10. **Fetching.** `GET /files/ID` by one who may see the record answers
    200 with exactly the stored bytes and the headers of §5.3: the type,
    length, `Content-Disposition` `inline` with the filename for an image
    and `attachment` for a PDF (`filename*` for a name with `ø`),
    `nosniff`, the CSP, `Cross-Origin-Resource-Policy: same-origin`,
    `Referrer-Policy: no-referrer`, `Cache-Control: private, no-cache`
    and the ETag; with `If-None-Match` it answers 304 with no body. Ola
    (record policy, on Postgres) gets 404 for Kari's file, with the same
    body as for an unknown id and for a file whose record was deleted; a
    file of an entity the code no longer defines, and one whose entity
    no longer has `:attachments`, is 404 for an admin too; with no
    session or token the answer is 401; an access token in
    `Authorization: Bearer` fetches it; `HEAD` gives the headers without
    the body. A page defined at the prefix `files` is refused.
11. **Request size** (`tests/safety-tests.lisp`). Each of these is
    answered 413 before its body is read:
    - 3 MiB to `/mcp` and to `/api/attachments_add` with no token;
    - 3 MiB to `/api/registry_describe` (a tool without a `files`
      parameter) with a token;
    - 3 MiB to `/mcp` and to `/api/attachments_add` with a viewer's
      token (no tool with files admits a viewer);
    - 17 MiB to `/api/attachments_add` with an employee's token, and
      27 MiB multipart with a session.

    And 3 MiB of multipart from a viewer's session to a page whose
    policy is `:employee` is answered 403 before its body is read.

    A 12 MiB `tools/call` of `attachments_add` on `/mcp` with an
    employee's token attaches its file; a 3 MiB `tools/call` of another
    tool with that token is answered 413 with JSON-RPC error `-32600` and
    «Over 2 MB tas bare imot for et verktøy som tar filer.» A 20 MiB
    multipart post with a session reaches the page. A file of about
    1 MiB, its body under 2 MiB, is attached over `/api` and over `/mcp`.
    A body with a key of 1.5 MiB in a file, and one to `/mcp` with a
    1.5 MiB string to another tool, are answered 413 with «Bare innholdet
    i en fil kan være lengre enn 1 MB.»; the answer and the request's
    record hold no string over 1 MiB.
12. **Multipart posts** (`tests/safety-tests.lisp`). A multipart post
    another site sent (`Sec-Fetch-Site: cross-site`) is answered 403
    before its body is read. A posted part's name is not made a symbol. A
    `multipart/form-data` post without a signed-in session is answered
    401 before its body is read, at 1 KiB and at 3 MiB, and so is one
    carrying only a public page's `tun_public` session. With a session,
    each of these reaches no page and is answered with the status and
    the exact message of `spec/files.md` §4.3: 65 parts (413); 11 file
    parts (413); a part's headers over 8 KiB (413); a text part of 1 MiB
    and one byte (413); no `boundary`, a boundary of 71 characters, no
    closing delimiter, a part without `Content-Disposition`, and one
    without `name` (each 400). A post of 10 files and 54 text parts
    reaches the page. A `filename` holding `%22`, `%0D%0A`, `%41` and the
    bytes `C3 28` arrives as `"`, a line break that §2.3 then removes,
    `%41` as written and U+FFFD followed by `(`; a part with `filename=""`
    and no content is left out, and one with `filename="tom.png"` and no
    content is refused as «Filen er tom.». No file is written under
    `/tmp` (Hunchentoot's temporary directory stays empty) by any of
    these.
13. **Four at once, within the heap** (`tests/safety-tests.lisp`). While
    four large requests are being answered (held in their operation, after
    their bodies were read), a fifth large body gets 503 with
    `Retry-After: 1` before it is read (to a page: a page with the message
    of §4.3, as `text/html`), and a small call to `/api` is answered as
    usual;
    when one of the four finishes, a large request is taken again. A
    large body sent slowly is cut off at the time limit (120 s; the test
    sets it shorter): it is answered 408 and its connection closed, and a
    large request is taken again at once.
    Four requests at the largest bounds at once (16 MiB to `/mcp` and
    16 MiB to `/api/attachments_add`, each with two PNGs of 5.85 MiB, and
    two 26 MiB multipart posts to a page that attaches their PNGs), every
    file walked, stripped and stored whole (a PNG's image data is kept as
    it is), repeated three times beside ordinary reads, are all
    answered and the server stays up, in a process started with
    `--dynamic-space-size 2048`, the image's default. So are four at once
    with one file of each format of 99 000 pieces each, three times; and
    a burst of 48 calls at once, each under 2 MiB with one such file, is
    answered 200 or 503 (every body over 256 KiB takes a place), at least
    four of them 200, the server still up.
    Every answer given before the body is read (401, 403, 413, 503) and
    the 408 after a stalled body end their connection: a request sent
    right after them on the same connection gets no answer, and the
    connection ends within seconds, also while the sender trickles; a
    reader that stops reading a file is cut off and the connection ends
    at once.
13a. **How much a request's JSON may hold** (`tests/safety-tests.lisp`,
    `core.md` §7.5). A body of 6 000 empty objects is answered 413 with
    «Forespørselen har for mange JSON-verdier (høyst 10 000).» on `/api`,
    and with JSON-RPC error `-32600` on `/mcp`; one of 4 990 is parsed (and
    its unknown member refused). A call to `/api/file_notes_create` with
    unknown keys and a 512 KiB title keeps in its record only `title`, as
    «[utelatt: …]», the input under 65 KiB and the message under 5 000
    characters. In the 2048 MiB process: four bodies of about 15.6 MiB at
    the value limit (two files and 4 970 empty objects) at once, two to
    `/api/attachments_add` and two to `/mcp`, are all answered; twenty more
    in turn are answered, and the live heap after a full collection grows
    by less than 64 MiB from the fifth to the twentieth; a burst of 48
    viewer calls, half at the limit and half of 1.8 MiB past it, is
    answered 422, or 413 or 503 for those past it (over 256 KiB, they
    take a place), every one at the limit 422 and at least four past it
    413, and the server stays up.
13b. **Records, forms and MCP bodies** (`tests/safety-tests.lisp`).
    - In the 2048 MiB process, 1 100 viewer calls of `heap_notes_get`, each
      with `id` an array of 4 990 empty objects, are each answered 422;
      the live heap after a full collection grows by less than 96 MiB
      over them; then four uploads of two 5.85 MiB files at once are each
      answered 200.
    - The four at once of criterion 13a are answered exactly 200 and 422
      on `/api` (`record_id` padded to the value limit, both files decoded
      first) and 200 with and without `isError` on `/mcp`; twenty more
      padded ones in turn are each 422.
    - An anonymous urlencoded post of 2 MiB of `a=b&` to `/login` is
      answered 413 «Skjemaet har for mange felt (høyst 1 000).»; one with a
      value over 1 MiB 413 «Et felt i skjemaet er for langt.»; 24 such
      posts at once in the 2048 MiB process, each answered 413 or 503
      (at least four 413), leave the live heap within 32 MiB of where it
      was; a form of 1 000 fields is read, `+` as a space and `%C3%B8` as
      «ø».
    - As an employee on `/mcp`, the bodies `[{… ping}]`, `null`, `1`,
      `true`, `[]`, `"x"` and a JSON string holding a `tools/call` are each
      answered 200 with JSON-RPC error `-32600`, and the call in the
      string is not run.
    - A chunked body is answered 411 and its connection ended.
    - A 700 KiB unknown key is repeated in an answer under 4 KiB.
13c. **Hostile callers and the memory budget** (`tests/hostile-tests.lisp`,
    `core.md` §7.5), in the 2048 MiB process:
    - Each kind of request at its costliest, alone, allocates at most its
      line of the budget: with a body up to 256 KiB (JSON with one long
      ASCII string, with astral text and at the value bound, to `/api`
      and `/mcp`, from a viewer and from no one; a form of ASCII and of
      astral escapes; a fault whose message is the body; a public page's
      fault; a multipart post) at most 8 MiB; with a body over 256 KiB, a
      2 MiB JSON body (two strings of 1 MiB and the value bound) at most
      16 MiB, a 2 MiB form of two 1 MiB values 12 MiB, 16 MiB of files as
      JSON with 2 MiB of long text beside them 72 MiB, and a 26 MiB
      multipart post with 2 MiB of text 169 MiB. Each is answered with
      its own status.
    - Sixty of those small requests and eight large ones at once, three
      times over, are each answered in full or with 503 (more than half
      in full); the heap at its highest stays under 1 604 MiB; the live
      heap after them is within 64 MiB of where it was; the server stays
      up.
    - A thousand records at the cap, then a hundred requests with hostile
      text, ASCII and astral, in every field a record keeps (a 30 000
      character tool path, a percent-encoded astral path, a 200 000
      character JSON-RPC method, an astral tool name, long and astral
      input to `/mcp` and `/api`, faults whose message is that text, a
      page's 30 000 character path and a public page's fault, a 20 000
      character `X-Tun-Actor`): every one answered in full; the history
      holds 1 000 records, the largest keeping between 48 and 64 KiB of
      text; the live heap grows by less than 96 MiB; an unknown method's
      error repeats under 200 characters of it.
    - A record's tool given 100 000 characters keeps 256 octets ending in
      «…», its message given 50 000 astral characters at most 4 096
      octets of valid UTF-8; its slot refuses 1 000 octets and a string
      (`type-error`); a declared input of 100 000 astral characters is
      kept in at most 48 KiB as «[utelatt: …]».
    - A thousand connections each sending 32 KiB of headers and never
      ending them hold at most 192 MiB.
    - A `Content-Length` of `12, 12`, `12, 13`, `+12`, `1e3` and `0x10` is
      answered 400 before the body is read; a 300 KiB body that stops
      coming after 1 000 octets is answered 408 and its connection ended
      within the read timeout.
13d. **Numbers and trickling senders** (`tests/hostile-tests.lisp`,
    `core.md` §7.5).
    - From a caller, `1e9999999`, `1e99999999`, `-1E+10000`, `1e401`,
      `2.5e-399`, `123456789e395`, `1e309`, `1.8e308`, `1e-330`,
      `1.5e-308` and `2.2250738585072013e-308` are each refused with
      «Et tall må være 0, eller mellom 2.2250738585072014e-308 og
      1.7976931348623157e308, med eller uten minus.», and
      `12345678901234567890` and `1.2345678901234567890123e248` with «Et
      tall kan ha høyst 19 sifre.», each in under 100 ms: parsed, on
      `/api` as 400 `invalid_json`, on `/mcp` as JSON-RPC error `-32700`.
      `1.5e300`, `1e-300`, `1.7976931348623157e308`,
      `±2.2250738585072014e-308`, `1.234567890123456789e-307`, a fraction
      of 60 zeros and a 1, `1234567890123456789`, `-0.0` and `0e10` are
      read; `true` and `false` are not taken for exponents.
    - JSON Tun wrote reads back whatever number it holds: the largest and
      the least normal double, the least subnormal, `2.5e-308`, `1e19`,
      `12345678901234567890`, `-2^200` and `10^300`, in a json field and
      in a receipt, which replays, and receipts are redacted.
    - A body of 9 900 numbers at a double's edge, and one of 9 990 numbers
      of 64 characters, each cost within their line of the budget
      (criterion 13c).
    - A JSON port registered with `:authorize` answers a wrong or missing
      secret 403 without parsing the body, even one with `1e99999999`;
      the right secret then meets the number's 400. The inbox's
      `/inbound/mail` does so: with a wrong secret and `1e99999999` it
      answers 403 and its handler never runs, with the right one 400
      (inbox 1.1.0, core ≥ 1.20.0).
    - A body declared to `/health`, or to a GET that is sent to HTTPS,
      trickled a byte every 0.3 s, gets its answer (200, 301) and the
      connection ends within 3.5 s.
    - A generated form's quantity of 500 000 digits, posted to `/orders`,
      is answered in under 2 s: 403 for a viewer, 422 for an employee with
      «er for langt for et tall: høyst 40 tegn».
    - Without a session or token, a body of 300 KiB to `/login`,
      `/api/registry_describe`, `/mcp` and, with a wrong secret,
      `/inbound/mail` is answered 413 before it is read; four anonymous
      senders trickling 300 KiB forms are each refused at once, and an
      employee's upload over 256 KiB meanwhile is answered 200.
    - A request line and headers trickled a byte every 0.3 s are answered
      408 at the header deadline (1 s in the test) and the connection
      ends; the server answers others.
    - With two places in all, two senders trickling small bodies hold
      both; a call meanwhile is answered 503, then 200 once their body
      deadline (1 s in the test) has answered each 408 and ended its
      connection, within 3 s.
14. **Sending files in parts.** A 10 MiB file is fetched with exactly its
    bytes; the store is read for it in parts of at most 1 MiB, each in a
    read transaction that has ended before the part is written; `HEAD`,
    a 304 and a 404 read no content (counted at the store). A file deleted
    after its first part is cut off short of its length. A reader that
    stops reading has its connection closed at the time limit. Thirty-two
    fetches of a 10 MiB file at once, beside ordinary reads, in a process
    started with `--dynamic-space-size 2048`, are all answered with the
    whole file, and the server stays up (`tests/safety-tests.lisp`).
15. **Storage and deleting.** On Postgres the bytes are in
    `attachment_contents` as `BYTEA` and a file of all 256 byte values
    reads back exactly; `introspect_schema` lists both tables. The SQLite
    store refuses to attach with a message naming Postgres.
    `delete-entity` of a record deletes its attachments and their bytes;
    when the transaction rolls back they are still there. The schedule
    `attachments_sweep` is in `schedules_list`, at `30 3 * * *`; run, it
    deletes the files of a record that was deleted behind the kernel's
    back and keeps those of an entity the code does not define.
16. **Components** (`tests/ui-forms-tests.lisp`,
    `tests/ui-data-tests.lisp`). `file-input` renders a `field` with
    label, hint and error tied by `aria-describedby`, `aria-invalid` with
    an error, and an `<input type="file" multiple>` with its name and
    `accept="image/png,image/jpeg,image/webp,image/gif,application/pdf"`
    in a `data-tun-file-input` zone; it renders the same in extension
    output, and a form's `enctype` passes there. `attachments` renders an
    image as a link to its path, `/files/ID`, around an `<img>` with `alt`, `width`,
    `height`, `loading="lazy"` and `decoding="async"`, a PDF as a tile
    with its name, size and link, and «Ingen vedlegg» with no items. Both
    have documentation, a source and examples in `/ui`. A generated form
    for an operation with a `files` parameter has
    `enctype="multipart/form-data"` and a `file-input`.
17. **A page receives files** (`tests/web-tests.lisp`). A multipart post
    gives FORM the text parts and, per name, an array of `{"filename",
    "upload"}`, leaving out a part with no file; `web-call` with them
    attaches the files; a refused file answers the page 422 with the
    error at the field and in the error summary.
18. **Choosing** (`files-choose.py`, at 390×844). On a card's page
    (`/saker/ID`), choosing two images and a PDF in the control lists all
    three before anything is sent, the images with a preview, each with
    its name and size, under their own names; «Fjern» on one takes it out
    of the list and out of the input; sending the form shows the two
    remaining files on the card's page, and a reload still does.
19. **Dropping** (`files-drop.py`, desktop). Dragging a PNG over the zone
    marks it and says «Slipp for å legge ved»; dropping it lists it under
    its own name; dropping a text file instead lists nothing and says
    why; dropping three files of 9 MB each lists the first two and says
    «Filene kan ikke være større enn 25 MB til sammen.» for the third;
    sending the form attaches what is listed.
20. **Pasting** (`files-paste.py`). On «Meld en sak» (`/saker/ny`), with
    the browser's clock set to 14:23:05 local time and focus in the
    title, pasting a clipboard holding a PNG named `image.png` lists it
    as `skjermbilde-142305.png` and leaves the title as it was; a second
    such paste in the same second lists `skjermbilde-142305-2.png`; a
    pasted JPEG named `image.jpeg` is `skjermbilde-142305.jpg`; a pasted
    file named `kvittering.pdf` keeps its name; pasting text into the
    title pastes the text and lists nothing; sending the form creates the
    card with its files, shown on the card's page under those names.
21. **Without JavaScript** (`files-without-javascript.py`). With
    JavaScript off, choosing a file in the plain control and sending the
    form attaches it.
22. **Thumbnails** (`files-thumbnails.py`). On the scenario's card with a
    screenshot and a PDF, the screenshot is a lazy thumbnail with its own
    width and height; clicking it opens a dialog showing the whole image
    (its `naturalWidth` is the stored width), with «Åpne original»
    linking to `/files/ID`, and Escape closes it; the PDF is a tile whose
    link is the file's URL. At 390 px wide the page does not scroll
    sideways.
23. **Done.** `+core-version+` and `coreVersion` are 1.20.0; no check sees
    a JavaScript error; `bin/build` has no warnings; `bin/test` and
    `bin/check` pass. Nothing in `src/` or `spec/files.md` names a client.

## Decisions

- **Files belong to a record, opted into per entity** (`:attachments`).
  A file names its record's entity and id rather than being a field, so
  any entity, a module's or a client's, takes files without a column or
  a migration of its own table, and the kernel can find, check and
  delete them for every entity alike. Opting in keeps every existing
  entity as it is.
- **Stored in Postgres, as `BYTEA` in a table of their own.** The deploy
  contract makes the database the tenant's data: the image has no volume,
  nixploy runs two containers during a switch, and the backups and
  restore of `spec/deploy.md` §4 are of the database. Files on disk would
  need a volume per target, shared between slots, and a second backup
  and restore that can drift from the records they belong to. In the
  database a file is written and deleted in its record's transaction, a
  dump has both or neither, and nothing changes in nixploy. Large
  objects were rejected: they live outside the row, need `lo_unlink` or
  `vacuumlo` to be deleted, and complicate dumps with `--no-owner`.
  The bytes are in `attachment_contents`, apart from the metadata, so
  listing a record's files never reads their content. The cost, a write
  of up to 25 MiB holding the single writer, is bounded: the bytes are
  decoded and checked before the transaction opens (§4.1), so the lock
  is held only for the insert itself. The dump grows by the files; at
  10 MiB a file and 20 a record this suits the issue trackers and
  checklists Tun's clients are, not a photo archive.
- **The type is decided by the bytes; only five types.** Content-Type
  and extensions are the caller's word. SVG is refused outright: it is
  XML that can hold script, and refusing it is simpler and safer than
  serving it only as a download. A filename's extension is corrected to
  the real type, so a download opens in the right program.
- **No server-side thumbnails; the browser scales, lazily.** A real
  thumbnail needs the server to decode untrusted images, either in Lisp
  (no maintained, hardened decoder for all four formats) or by calling
  libvips or ImageMagick, whose decoders are where image attacks land,
  and which would add a program to an image that today has none. It
  would also break the rule of not decompressing uploads. Instead Tun
  reads width and height from the header, so a thumbnail's box is right
  before it loads, and pages use `loading="lazy"` and `decoding="async"`.
  The pixel bound (30 000 a side, 50 megapixels) keeps a decompression
  bomb out of viewers' browsers. Smaller copies are under Not yet.
- **Metadata out by keeping a known list of segments and chunks, never
  by re-encoding.** Re-encoding would need a decoder (above) and would
  change the picture. An allowlist rather than a blocklist, so metadata
  Tun has not heard of goes too: for JPEG the frame, tables and scans,
  JFIF (rewritten without its thumbnail), the ICC profile and Adobe's
  colour segment; `JFXX` goes since its thumbnail may show the uncropped
  original. Anything after `EOI` goes, where phones keep extra images
  with their own Exif. The orientation is kept as a minimal Exif,
  because without it a photo taken on its side shows sideways. PNG and
  WebP keep their image and colour chunks only. GIF has no Exif but can
  carry XMP in an application extension and text in comments; its
  blocks are walked by their sub-block lengths, without decoding LZW, so
  those go, with the plain text extension (text that hardly any viewer
  draws, so a place to hide words), and the looping extension stays. A PDF's metadata is part of
  a document its owner chose to share, and taking it out means parsing
  PDF, so it is kept as given and the spec says so.
- **An Exif Tun cannot read gives no orientation, not a refusal.** The
  Exif is dropped either way, so what is at stake is only how the photo
  is turned; refusing a photo for a malformed tag would turn away files
  that every browser shows. Two Exif segments are ambiguous about which
  orientation holds, so neither is used.
- **No `DNL`.** A JPEG may give its height after the first scan, in a
  `DNL` segment; hardly any encoder does, and taking it would mean
  allowing height 0 in the frame and finding the real one later. Height
  0 stays damaged and a `DNL` is refused, so every image has its size
  from its frame header.
- **Damaged files are refused, not repaired.** Each walk follows the
  lengths a file states; a length past the end, a missing end marker
  (`IEND`, `EOI`, the GIF trailer) or a block Tun cannot place means a
  file it cannot vouch for, and keeping part of one could keep what the
  missing part was meant to drop. Every frame of an animation is held
  to the pixel bounds, since a browser decodes each.
- **Names lose Unicode's control and format characters** (Cc and Cf,
  with the line and paragraph separators): a direction override can make
  a PDF read as a PNG in a list, and invisible characters can make two
  names look alike.
- **Agents send base64; Tun never fetches a URL.** A URL would make the
  server fetch addresses a caller chooses, an SSRF risk that needs the
  outbound safeguards and adds failure modes; an agent attaching a
  screenshot already has its bytes. An object with `url` gets a message
  saying what to do instead, and so does a `data` that is a data URL, the
  mistake an agent is most likely to make.
- **Larger bodies only where files go, and only for callers who may
  send them.** The 2 MiB bound stays for everything else. `/api/TOOL`
  knows its tool from the path, so the bound is raised before reading
  only for a tool with a `files` parameter and a caller its policy
  admits. `/mcp` names its tool inside the body, so a body over 2 MiB is
  read only from a caller whose role some tool with files admits, and
  then refused unless it is a call of such a tool.
- **A file's data is set aside before the body is parsed.** Parsed as
  JSON, a file's base64 became a string of four bytes a character, grown
  by doubling in the parser's buffer and then copied: about 470 MiB
  allocated for one 16 MiB call, near 2 GiB for the four places. Taking
  every string over 1 MiB out of the octets first, decoding its base64
  in place and leaving a placeholder, makes the same call cost about
  60 MiB, and holding what is left to 2 MiB keeps the parse at an
  ordinary body's cost. A placeholder outside a file's `data` counts as
  the long string it replaced, so the rules of §4.1 are unchanged.
- **Only a file's `data` may be long.** A large body exists for file
  content; any other string over 1 MiB in it is refused before a tool
  runs, so the request record, which keeps inputs as they came, never
  holds one, and a file name is bounded at 255 characters for the same
  reason.
- **Four large requests at once, each held until it is answered.** A
  large request's memory peaks after its body is read: the parsed JSON
  or the multipart's parts, the decoded base64 and the stripped copy. Counting only the read would let many
  requests be in that phase at once. Four at the largest bounds fit the
  image's default heap of 2 GiB with room for ordinary traffic, and a
  test runs exactly that. A person whose post meets four taken places
  gets a page that says to try again, not a bare 503.
- **Every body over 256 KiB takes a place, whoever sends it.** Any
  body costs a few times its size to read and parse: JSON and forms as
  well as files, from anyone, anonymous callers included. `--max-inflight`
  (64) alone would let 64 bodies of 2 MiB be parsed at once, and a
  reviewer's test showed 64 anonymous forms of two 1 MiB values, or
  viewers' JSON with two 1 MiB strings, ending the server. So every body
  over 256 KiB takes one of the four places before it is read, and a
  burst gets 503 and comes back; a smaller one costs too little to
  matter (at most 8 MiB, measured). Walking a file copies what is kept
  into one buffer, and a file has at most 100 000 pieces, so no file
  costs more than a few times its size, whatever it holds.
- **The memory budget is measured, as allocation.** Each line of
  `core.md` §7.5's budget is what a request allocates in all while it is
  answered alone (`sb-ext:get-bytes-consed`, in the heap server), at its
  costliest: more than it ever holds at once, so the total is a bound,
  not an estimate. The tests assert each line's allowance and, with
  every limit reached at once, the heap's highest use, garbage included.
- **A multipart post holds at most 2 MiB of text.** Twenty-five text
  parts of 1 MiB made a 26 MiB post cost 350 MiB as strings; besides its
  files a post may hold what an ordinary body may, as a JSON body with
  files may.
- **Headers at most 32 KiB.** A connection holds its headers as text
  while it reads them, about four times their size, and Hunchentoot runs
  up to 1 024 connections: at 64 KiB a thousand connections that never
  end their headers held 256 MiB. 32 KiB, as much as nginx takes by
  default, is far more than a browser or an agent sends.
- **No number past a double's range.** jzon reads `1eN` by making 10 to
  the N as an integer before it makes a double, in time that grows with
  N's square: 20 bytes held a core and a slot for minutes. A double has
  no use for an exponent past about 324, so the first pass refuses an
  exponent of more than 4 digits, or one that with the digits is over
  400. Mantissas need no more: 64 characters bound them.
- **Deadlines for headers and every body.** The 20-second read timeout
  bounds only a silence, so a sender trickling a byte every 19 seconds
  held a slot without end. Headers get 30 seconds, and a body is read
  first, before the caller's checks, in 30 seconds when small and 120 in
  a place. Reading a small body before refusing a caller costs at most
  256 KiB, already inside the slot's budget.
- **Anonymous callers send at most 256 KiB** (Jonas: «Refuse anonymous
  bodies over 256 KiB»). Four anonymous connections trickling 300 KB
  forms to `/login` held the four places, so no one could upload. A
  caller Tun cannot name before the body is read (no token, session or
  port secret) is refused at 256 KiB, on every path; nothing anonymous
  needs more.
- **A caller's numbers only** (Jonas: «Keep refusing, clearer message»).
  The bounds on significant digits and range apply to what callers send;
  JSON Tun wrote (fields, receipts) and other systems' answers keep only
  the exponent-digit and 1 000-character guards, so nothing stored before
  becomes unreadable. Each refusal says which limit and what it is, and
  the least normal double itself is taken.
- **Numbers within a double's normal range, 19 significant digits.**
  An exponent's digits were not enough: a subnormal or a long mantissa
  makes jzon work in big integers, a few kilobytes a number, and writing
  such a double back with `~F` (into a record's input) cost bignums of 300
  digits. So a number has at most 19 significant digits and a power of
  ten from -307 to 308, and Tun writes doubles in their shortest form
  (Schubfach, as jzon does). A generated form's number field is parsed
  only up to 40 characters.
- **A declared body nothing reads is dropped, not read.** `/health` and
  the redirect to HTTPS answer before the body would be read, and
  Hunchentoot then read it with no deadline. Every request that leaves a
  declared body unread ends its connection after dropping the body for
  at most 2 seconds, whichever path it took.
- **Follow-ups, not in this loop.** Many callers that reconnect again and
  again can still take Hunchentoot's 1 024 connection threads; that needs
  limits per address, or a proxy (Caddy) that buffers requests. And
  `define-job` accepting a `(files …)` parameter, which no job needs yet.
- **A JSON port checks its secret before parsing.** `register-json-endpoint`
  takes `:authorize`; the inbox's port uses it, which needs this core.
- **A refused body is read and dropped for two seconds.** Closing a
  connection whose body is still arriving makes the system reset it, and
  a client still sending, a browser posting 26 MiB among them, then loses
  the answer that says why. Reading and dropping the rest of the body it
  declared, for at most 2 seconds and 26 MiB, lets it read the answer;
  the connection then ends as before.
- **A large body must arrive within 120 seconds.** A place is held from
  before the body is read, so a sender that stalls would otherwise keep
  it for as long as it likes. 120 seconds is 26 MiB at under 2 Mbit/s,
  slower than a phone on a poor connection; past it the connection is
  dropped and the place freed.
- **Files are sent 1 MiB at a time, and no transaction is held while
  sending.** A page of thumbnails asks for many files at once; reading a
  whole `BYTEA` for each would put 10 MiB per request in the heap.
  Reading `substring`s in their own short read transactions bounds an
  answer to 1 MiB and keeps a slow reader from holding a database
  connection or a snapshot. Content never changes under an id, so parts
  from separate transactions are of one file; a file deleted meanwhile
  ends the answer short, which the browser sees as a failed load.
  `HEAD`, 304 and refusals read only metadata. The same 120 seconds
  bound a reader that stops reading.
- **Multipart is parsed by Tun, in memory, and only for a signed-in
  person.** Hunchentoot's own parser writes every file part to `/tmp`
  as it reads, before any check of how many there are. Tun's parser
  reads the body it already bounded, counts parts (64), file parts (10)
  and header bytes (8 KiB) as it goes, and stops at the first excess, so
  a post can neither fill a disk nor make thousands of parts. Files are
  for staff: a `multipart/form-data` post without a staff session is
  refused before its body is read, a public page's session included,
  until a public page needs files (Not yet). A large one is read only
  when the page at its path admits the person's role, so a viewer
  cannot make the server read 26 MiB for a page that would refuse them.
  Malformed posts get one 400 page; names are read as browsers write
  them (UTF-8, with their `%22`, `%0D` and `%0A`), with invalid bytes
  replaced rather than refused, since the name is cleaned anyway and a
  person cannot fix how their browser encoded it. A chosen file that is
  empty is a mistake to tell the person about («Filen er tom.»); a
  control with nothing chosen is no file.
- **The `files` parameter type, and handles for a page's uploads.** An
  operation can create a record and attach its files in one transaction
  (a sak with its screenshot, over MCP or from a form), so a refused file
  never leaves a record without it. A page passes what the browser sent
  as request-local handles rather than base64, which would multiply the
  memory a 25 MiB post takes; a handle means nothing outside the request
  that posted it, so an MCP or API caller cannot use one.
- **Request records keep a file as its name and size only.** The
  history holds a thousand requests in memory, so keeping base64 there
  would hold up to 16 MiB per request long after it ended, and hand a
  file to anyone who reads diagnostics. The record is made with the
  content already replaced. A stored fault keeps no input at all, as
  `spec/errors.md` §4 already says, and its message is Tun's own text.
- **A record keeps a caller's text only clipped, through one choke
  point.** Kept as a parsed value, a record of a small input could hold
  hundreds of times its text in hash tables, and the history holds a
  thousand; a tool name, a method or a path kept by reference could be
  as long as the body or the headers. So every field a record keeps of
  what a caller sent (tool, method, path, actor, credential, input,
  error code, type and message, backtrace) is written by one accessor
  that clips it into UTF-8 octets, and the record's slots are typed to
  each field's bound: an uncapped string cannot be stored. The bounds
  add up to 64 KiB, the input 48 KiB of it, counted in octets so astral
  text costs what it does. The input is written as JSON straight into
  its octets, stopping a value once it cannot fit.
- **Tun reads plain forms itself**, as it reads multipart: Hunchentoot
  would make a pair for every `&` of a 2 MiB body, half a million, from
  anyone, on a public page too. Counting the fields first, and bounding
  names and values, keeps a post's cost near its size; each value is
  decoded once, counted first and then written into one string of its
  length, with no copy on the way.
- **The dependency check stands in for review.** That nothing
  decompresses or decodes uploads is checked by a test over `tun.asd`
  and the file handling's sources (no decompression or image library,
  no `run-program`), so a later change that adds one fails the suite.
- **Who may see a file is who may see its record**, checked on every
  fetch by fetching the record as the caller, so the entity's record
  policy and `entity-readable-p` decide, which is how a client's policy
  reaches it. Not allowed and not there are the same 404, so an id tells
  nothing. Adding and removing need the tool's role and, where the
  entity says so, a higher one (`:policy`); since a record policy is one
  condition for reading and writing (`spec/store.md` §6), seeing the
  record is the rest. A file whose entity the code no longer defines, or
  that no longer takes files, is served to no one, admins included: the
  policy that decided who may see it is gone, and failing closed is the
  only answer that does not guess.
- **Ids are 130 random bits** (`fil_` and 26 characters), more than other
  ids' 80, since a file's URL is the one id likely to be pasted
  elsewhere. Secrecy is not the protection, the check is.
- **Served inert.** The sniffed Content-Type, `nosniff`, a CSP of
  `default-src 'none'` with `sandbox`, `Cross-Origin-Resource-Policy:
  same-origin` and `Content-Disposition` make a file inert even when
  opened on its own: no script runs and no other site embeds it with the
  person's cookies. A PDF is always a download, since a PDF can hold
  script and a browser's PDF viewer does not run under `sandbox`.
- **`Cache-Control: private, no-cache` with an ETag**, not `no-store`. The
  browser keeps a copy but must ask before each use, and the server
  checks the caller before it answers 304, so a removed right takes
  effect at once while a list of thumbnails costs a phone only a
  revalidation each time. Pages themselves are not `no-store` either, so
  `no-store` on files alone would protect little on a shared machine.
- **Deleting with the record, and a nightly sweep.** `delete-entity`
  takes a record's files in its transaction. The sweep is for records
  removed outside the kernel; it skips entities the running code does not
  define, so a rollback of the code does not cost a tenant its files.
- **The form control is a real file input, enhanced.** It works without
  JavaScript; with it, drop and paste add to `input.files` through a
  `DataTransfer`, so the post is the same multipart form either way and
  needs no upload endpoint or staged files. Paste is taken anywhere in
  the form, or anywhere on a page with one file field, because a person
  pastes a screenshot where they are typing; a paste with no files is
  left alone. Files are not kept after a refused post, as a browser
  cannot be given them back; the error says which file was refused.
- **A pasted screenshot is named by the device's clock.** Browsers call
  every clipboard image `image.png`, so a list of pasted screenshots
  would be indistinguishable. The name is made in the browser, where the
  paste happens, from the device's local time, the time the person sees
  on their screen; the server's clock and Norwegian time would be wrong
  for a person abroad and cannot be known before the post. A file
  pasted with a real name (copied in a file manager) keeps it.
- **Thumbnails open in a dialog with JavaScript, as the image itself
  without.** The link is the file's URL, so it works without script and
  in a new tab; the dialog keeps the person on the record.
- **Not now:** removing a file from the `attachments` component and files
  on the generated record page (a page builds its own button for
  `attachments_remove`), reading bytes through MCP (an agent fetches
  `/files/ID` with its token), SQLite, quotas and malware scanning. They
  are in `spec/files.md` §7.
- **Who may remove a file: the one who attached it, or an admin.**
  Asked of Jonas at gate A, who answered «Who attached it, or an admin».
  So every file records the account that attached it, and removal
  compares the caller's account name with it; an employee who may see
  the record may still add files, as the entity's `:policy` allows. A
  record the caller may not see stays `not_found` before anything else,
  so a refusal never tells that a record exists.
- **Agnostic.** Everything in `src/` and `spec/files.md` is about records
  and files, with no client named; the examples are Nordvik Utleie's
  items and the showcase's cards.
- **Core 1.20.0.** web-push takes 1.19.0 and ships first; this loop is
  rebased onto it then.

## Log

- 2026-10-26 20:19  started, autonomous
- 2026-10-26 20:26  gate A asked of a reviewer
- 2026-10-26 20:33  gate A: changes (reviewer): spec/ui.md table split; hold a big-body slot until answered and test four max bodies within the heap; keep only filename and bytes in request records; bound multipart parts and refuse files without a session; refuse damaged structures; strip GIF comments, XMP and trailing data and check frames; orphaned entities' files are 404 for all; define control characters incl. bidi
- 2026-10-26 20:38  gate A asked of a reviewer
- 2026-10-26 20:46  gate A: changes (reviewer): bound memory when serving files; only a files value's data may exceed 1 MiB, multipart text parts 1 MiB, recorded filename 255; large multipart only when the page admits the role; stored faults keep no input; the control checks the 25 MB total and a full server answers with a page; a deadline for large bodies; multipart, 413 messages, JPEG and name details; criterion 5's last clause must be a check
- 2026-10-26 20:49  gate A asked of the person
- 2026-10-26 20:51  gate A: approve (jonas): «Approve»; on who may remove a file: «Who attached it, or an admin»
- 2026-10-26 20:51  Jonas at gate A on removing files: «Who attached it, or an admin»; spec/files.md §1 and §4.2, criterion 8 and Decisions changed
- 2026-10-26 21:44  rebased: tun d76c6f8 → bf51a48
- 2026-10-26 22:02  built: a file's refusal names it in «»; the per-record message is «Høyst N filer per LABEL.»; a body past its time limit is answered 408 and closed; the sweep's schedule is attachments_sweep; thumbnails link to the path /files/ID; checks may run without JavaScript (javascript=False)
- 2026-10-26 22:21  verify 1: failed test
- 2026-10-26 22:32  verify 2: passed build, test, check
- 2026-10-26 22:33  shown (/vedlegg, /saker/ny, /saker)
- 2026-10-26 22:33  gate B asked of a reviewer
- 2026-10-26 22:48  gate B: changes (reviewer): files of 0.75-1.5 MiB fail over /api and /mcp (string bound); long JSON keys pass the only-data-is-long check; a short Exif APP1 crashes the JPEG walker (500); JFIF thumbnail removal leaves a wrong length byte; with-timeout can unwind mid-call; part names interned as keywords; tests missing for parts of criteria 9 and 13; two messages differ from the spec
- 2026-10-26 22:56  gate B changes: JSON strings for a file's data are raised for any body from a files caller to a files tool, keys checked too, the two refusals keep their own messages; the JPEG walker reads an APPn's content within its segment, JFIF's length is set whole, a fuzz test; SBCL deadlines bound only blocking reads and writes; part names stay strings; cross-origin multipart refused unread; RFC 5987 filename*; a page's request record keeps no operation input at all, which the test checks instead of {filename, bytes}
- 2026-10-26 23:07  verify 3: passed build, test, check
- 2026-10-26 23:08  shown (/vedlegg, /saker/ny, /saker)
- 2026-10-26 23:08  gate B asked of a reviewer
- 2026-10-26 23:30  gate B: changes (reviewer): the earlier eight are fixed (probed); a valid file of millions of tiny kept segments (JPEG restart markers, GIF control extensions) costs ~48 bytes of heap each in the walkers' lists: four 10 MiB uploads, or 48 sub-2 MiB calls, exhaust the heap and kill the server; refused-before-reading answers do not close the connection (Hunchentoot resets *finish-processing-socket* for keep-alive), so an unread body is read as the next request
- 2026-10-26 23:43  gate B round 2 changes: walkers copy into one buffer and refuse a file of over 100 000 pieces and a stray RST/TEM; a body over 256 KiB that may carry files takes a place; every refusal before the body, the 408 and a stopped reader's answer end their connection; heap tests with files of many pieces and a burst of 48
- 2026-10-26 23:55  verify 4: failed test
- 2026-10-27 00:07  verify 5: passed build, test, check
- 2026-10-27 00:07  shown (/vedlegg, /saker/ny, /saker)
- 2026-10-27 00:07  gate B asked of the person
- 2026-10-27 06:11  gate B: changes (jonas): «Changes: fix it here» — bound the number of JSON values for every body, keep only declared parameters (capped) in request records, structure-heavy heap tests (an advisory review found a 16 MiB body of {} exhausts the heap)
- 2026-10-27 06:19  Jonas at gate B: changes; a request's JSON holds at most 10 000 values (core.md §7.5), counted before parsing; request records keep only declared inputs, at most about 64 KiB, and 4096 characters of a message; heap tests with structure-heavy bodies; servers started by tests end with them
- 2026-10-27 06:29  verify 6: passed build, test, check
- 2026-10-27 06:34  bin/test-cli passed on this tree (tun new, build, test, image, restore, serve, preview, check, loop, tun add, tun update)
- 2026-10-27 06:34  shown (/vedlegg, /saker/ny, /saker)
- 2026-10-27 06:34  gate B asked of a reviewer
- 2026-10-27 06:47  gate B: changes (reviewer): the value bound holds; but request records keep values by reference and charge containers 2 octets, so a viewer's 1000 small structure-heavy calls fill ~1 GiB of history; /mcp re-parses parsed JSON for files callers (a JSON string request is executed, batches and scalars 500); the 13a heap test accepts 500s and its /api bodies are refused before the files
- 2026-10-27 06:56  gate B round 4 changes: records keep their input as JSON text (UTF-8, about 64 KiB); /mcp never parses a body twice and refuses a parsed non-object; criterion 13a's statuses exact and its /api bodies reach the files; plain forms read by Tun within 1 000 fields; 411 ends its connection; unknown names cut to 100 characters; check-json-shape
- 2026-10-27 07:06  verify 7: failed test
- 2026-10-27 07:23  verify 8: passed build, test, check
- 2026-10-27 07:28  bin/test-cli passed on the tree of verify round 8
- 2026-10-27 07:28  shown (/vedlegg, /saker/ny, /saker)
- 2026-10-27 07:29  gate B asked of a reviewer
- 2026-10-27 07:48  gate B: changes (reviewer): the history still grows past its bound: /mcp keeps an unknown method or tool name whole (a viewer's 1 MiB names killed the server), and the input budget counts characters but keeps UTF-8 octets (about 4x the stated 64 MB); anonymous urlencoded posts within the bounds, 32-64 at once, exhaust the heap in decoding; a viewer's 2 MiB JSON with long strings, 64 at once, too
- 2026-10-27 08:37  gate B round 5 changes: one choke point for request records (typed slots, octets, 64 KiB a record, 48 KiB input); every body over 256 KiB takes a place; urlencoded values decoded once; file data set aside before parsing; JSON parsed from octets; multipart text at most 2 MiB; headers 32 KiB; refused bodies drained; 400 for a bad Content-Length, 408 for a body that stops; memory budget in core.md §7.5; tests/hostile-tests.lisp
- 2026-10-27 08:52  verify 9: passed build, test, check
- 2026-10-27 08:57  shown (/vedlegg, /saker/ny, /saker)
- 2026-10-27 08:58  gate B asked of the person
- 2026-10-27 14:28  gate B: changes (jonas): «Changes: add both fixes here» — bound JSON exponents (a 20-byte 1e999999999 holds a core and a slot for days) and give bodies of 256 KiB or less an overall deadline (slow senders could hold all 64 slots); a reviewer then finishes the probes the advisory review could not reach
- 2026-10-27 14:37  gate B round 6 changes: numbers past a double's range refused before parsing (400, -32700); JSON ports check their secret first (inbox 1.1.0); deadlines for headers (30 s) and small bodies (30 s), 408; fault line of the budget measured again (7.5 MiB)
- 2026-10-27 14:48  verify 10: failed check
- 2026-10-27 15:00  verify 11: passed build, test, check
- 2026-10-27 15:05  shown (/vedlegg, /saker/ny, /saker)
- 2026-10-27 15:05  gate B asked of a reviewer
- 2026-10-27 15:36  gate B: changes (reviewer): a body sent to /health (and the HTTPS redirect) has no deadline: 1100 trickling posts blocked everyone; no /inbound/mail test fails without its secret-first check; the budget table does not hold for bodies of long numbers (17 MiB on an 8 MiB line)
- 2026-10-27 15:47  gate B round 7 changes: a declared body nothing reads is dropped and its connection ended (/health, the HTTPS redirect, every path); numbers bounded to 19 significant digits and 1e-307..1e308, doubles written shortest; generated form numbers parsed up to 40 characters; JSON ports answer too many values 413; an /inbound/mail test; the board check waits for focus
- 2026-10-27 16:00  verify 12: passed build, test, check
- 2026-10-27 16:05  shown (/vedlegg, /saker/ny, /saker)
- 2026-10-27 16:05  gate B asked of a reviewer
- 2026-10-27 16:34  gate B: changes (reviewer): the number bound sits in parse-json, so Tun's own stored JSON, receipts and outbound answers with 20-digit integers or subnormals become unreadable; four anonymous trickling 300 KB posts hold all large places and block uploads; stale docstring. Jonas, asked meanwhile: «Refuse anonymous bodies over 256 KiB», «Keep refusing, clearer message»
- 2026-10-27 16:43  gate B round 8 changes: number bounds for callers' JSON only, Tun's own JSON reads back any number it wrote; refusals say which limit (19 digits; 0 or 2.2250738585072014e-308 to 1.7976931348623157e308); anonymous bodies over 256 KiB refused unread on every path; a form number over 40 characters told so
- 2026-10-27 16:54  verify 13: passed build, test, check
- 2026-10-27 16:59  shown (/vedlegg, /saker/ny, /saker)
- 2026-10-27 16:59  gate B asked of the person
- 2026-10-27 17:17  gate B: approve (jonas): «Approve»
