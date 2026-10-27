# Files attached to records

Status: v1, built 2026-10-26, core 1.20.0. How a record carries files,
such as a screenshot on a reported issue: which records may, which files
are taken and what is stripped from them, how a person attaches them in
a form (choosing, dragging, pasting), how an agent attaches them through
MCP or `/api`, where they are stored, who may fetch them, and how pages
show them.

Examples use an invented rental business, Nordvik Utleie, whose staff
report problems as items (`item`, «Sak»).

## 1. Which records carry files

An entity takes files when its definition says so:

```lisp
(define-entity item (:id-prefix "itm" :label "Sak"
                     :attachments (:max 20)
                     :record-policy ((:admin t) (:employee "author = :actor_name")))
  ((title :type (string :min 1 :max 200) :required t :label "Tittel")
   (author :type (string :max 64) :input nil :label "Meldt av")))
```

- `:attachments` is `t` or a property list of `:max`, the most files one
  record holds (an integer from 1 to 100, default 20), and `:policy`, the
  least role that may add them and remove their own (`:employee` or
  `:admin`, default `:employee`); who may remove which is §4.2. Anything else, and the option on an
  embedded entity, is refused when the definition is compiled.
- Without the option no record of the entity takes a file.
- A file belongs to one record, named by its entity and id. The entity's
  own table is not changed, so a module's entity takes files when its
  module says so, and an existing entity can start taking them without a
  migration of its table.
- `registry_describe` lists each entity's `attachments` as `{"max",
  "policy"}`, or `null`.

## 2. The files Tun takes

### 2.1 Types, decided by the bytes

A file's type is decided from its first bytes (its magic number) and its
structure, never from a declared Content-Type, the filename's extension
or anything else the caller says. A caller cannot name a type.

| Type | Served as | Recognised by |
|---|---|---|
| PNG | `image/png` | `89 50 4E 47 0D 0A 1A 0A`, then an `IHDR` chunk |
| JPEG | `image/jpeg` | `FF D8 FF`, then segments up to a frame header (`SOFn`) and a scan |
| WebP | `image/webp` | `RIFF`, a size, `WEBP`, then a `VP8 `, `VP8L` or `VP8X` chunk |
| GIF | `image/gif` | `GIF87a` or `GIF89a`, then the logical screen descriptor |
| PDF | `application/pdf` | `%PDF-` at the start |

- Every other file is refused, whatever its name: SVG (it can hold
  script), HTML, text, archives, and a file whose name says `.png` but
  whose bytes are not a PNG. The answer is `invalid_input` at the file
  (§4.1): «Filtypen er ikke tillatt. Tillatt er PNG, JPEG, WebP, GIF og
  PDF.»
- **Damaged files are refused** («Bildet er skadet eller ufullstendig.»),
  each format's structure walked to its end by the lengths it states:
  - PNG: a chunk whose stated length (with its CRC) runs past the end of
    the file, no `IDAT`, no `IEND`, an `IHDR` that is not the first chunk
    or not 13 bytes, or a critical chunk other than `IHDR`, `PLTE`,
    `IDAT` and `IEND` (a browser cannot show such a file);
  - JPEG: a segment whose stated length runs past the end, no frame
    header (`SOFn`) or no scan (`SOS`) before the end, a second frame
    header, a `DNL` segment (Tun does not take a height given after the
    scan, so a frame of height 0 is refused as below), or no end of the
    image (`EOI`). Fill bytes (`FF` repeated before a marker) are
    allowed;
  - WebP: a RIFF size or a chunk whose stated length runs past the end,
    or no `VP8 `, `VP8L` or `ANMF` image data;
  - GIF: a colour table, an image descriptor, or a sub-block whose
    stated length runs past the end, a block of an unknown kind, or no
    trailer (`3B`);
  - any image whose width or height is 0;
  - a JPEG with a restart marker (`RSTn`) or `TEM` outside a scan;
  - a file of more than 100 000 chunks, segments or blocks, counted as
    its format's walk goes.

  What is kept of a file is copied into one buffer as the walk goes, so
  walking a file costs a small multiple of its size, however many pieces
  it has.

  A PDF is recognised by its header alone: Tun does not parse PDF.

### 2.2 Size and dimensions

- **Per file:** 1 byte to 10 MiB (10 485 760 bytes), measured after
  decoding. An empty file is refused («Filen er tom.»), a larger one
  «Filen er større enn 10 MB.»
- **Per call:** at most 10 files, and at most 25 MiB together.
- **Per record:** at most the entity's `:max` (§1). A call that would
  take a record past it stores none of its files: «Høyst 20 filer per
  sak.», with the entity's maximum and label.
- **Which file.** A refusal of one file starts with its name as given, in
  «», so a person who sent several sees which: «skjerm.txt»: Filtypen er
  ikke tillatt. Tillatt er PNG, JPEG, WebP, GIF og PDF.
- **Pixels:** an image is at most 30 000 pixels on either side and
  50 000 000 pixels in all, so a full-page screenshot fits but an image
  built to exhaust a viewer's memory when decoded does not («Bildet er
  for stort: høyst 30 000 piksler på hver side og 50 megapiksler.»).
- The pixel bounds hold for every frame too: each GIF image descriptor
  and each WebP `ANMF` frame is checked against them, not only the
  image's own size.
- Width and height are read from the header (PNG `IHDR`, JPEG `SOFn`,
  the GIF logical screen, WebP's `VP8X`, `VP8 ` or `VP8L` header). They
  are the size the image is shown at: for a JPEG whose orientation (§3)
  turns it a quarter, width and height are swapped.
- **Nothing uploaded is decompressed or decoded.** Tun reads headers and
  walks a file's chunks, segments or blocks by their stated lengths; it
  never inflates image data (PNG's zlib, GIF's LZW), decodes pixels or
  parses a PDF's objects.

### 2.3 Names

The filename is kept for showing and downloading. A given filename is
at most 255 characters; a longer one is refused at the file («Filnavnet
kan ikke være lengre enn 255 tegn.»). It is taken as the caller gives
it, with any directory part (up to the last `/` or `\`) dropped,
control characters and `"` removed, and spaces at the ends trimmed. The
control characters
are those of Unicode's categories Cc and Cf, among them the direction
controls U+202A–U+202E and U+2066–U+2069, which can make
`faktura‮gnp.pdf` read as «fakturafdp.png», and the line and paragraph
separators U+2028 and U+2029. When the name does not
end in an extension of the file's type (`.png`; `.jpg` or `.jpeg`;
`.webp`; `.gif`; `.pdf`, in any case), that extension is added:
«skjermbilde» is stored as `skjermbilde.png`, and a PDF named `faktura.png`
as `faktura.png.pdf`. An empty name becomes `fil` and the extension.
Last, a name longer than 200 characters, the added extension included,
is cut to 200 by shortening what comes before its extension.

## 3. What is taken out of a file

A photo from a phone carries where it was taken. Tun stores files with
such metadata taken out, by dropping whole segments, chunks and blocks
(and the thumbnail inside a JFIF segment); the image data itself is kept
byte for byte.

What is kept is listed; everything else is dropped, so a kind of
metadata Tun does not know of goes too.

- **JPEG.** Kept: the frame header (`SOFn`), the tables (`DQT`, `DHT`,
  `DAC`, `DRI`), the scans (`SOS` and their data, with `RSTn`),
  `APP0` only when it is `JFIF\0`, rewritten without the thumbnail JFIF
  may carry, `APP2` only when it holds an `ICC_PROFILE` (colours), and
  `APP14` only when it is `Adobe` (it decides the colour transform).
  Dropped: every other `APPn`, among them `APP0` `JFXX` (a thumbnail,
  perhaps of the uncropped original), `APP1` (Exif, with GPS, and XMP),
  `APP2` `MPF` (a phone's extra images) and `APP13` (IPTC); every
  comment (`COM`); and anything after the end of the image (`EOI`),
  where phones put extra images with their own Exif. The segments
  between scans of a progressive JPEG are walked the same way. When the
  dropped Exif gave an orientation from 2 to 8, a minimal Exif segment
  with only that orientation is written after `SOI` (and `APP0`), so a
  photo taken on its side is still shown upright. An Exif Tun cannot
  read (an offset or a count past its end, no orientation tag, a value
  outside 1 to 8), and a JPEG with more than one Exif segment, give no
  orientation: the file is taken, upright as stored, with no Exif.
- **PNG.** Kept: the critical chunks `IHDR`, `PLTE`, `IDAT` and `IEND`,
  and of the others only `tRNS`, `cHRM`, `gAMA`, `iCCP`, `sBIT`, `sRGB`,
  `cICP`, `bKGD`, `pHYs` and APNG's `acTL`, `fcTL` and `fdAT`, each as
  it was. Dropped: every other chunk (`eXIf`, `tEXt`, `zTXt`, `iTXt`,
  `tIME` among them) and anything after `IEND`.
- **WebP.** Kept: `VP8 `, `VP8L`, `VP8X`, `ALPH`, `ANIM`, `ANMF` and
  `ICCP`. Dropped: every other chunk (`EXIF` and `XMP ` among them) and
  anything after the RIFF size; the `VP8X` flags for Exif and XMP are
  cleared and the RIFF size is made to match.
- **GIF.** A GIF has no Exif, but it can carry XMP in an application
  extension and any text in a comment. Its blocks are walked by their
  stated sizes and their sub-blocks by their lengths, without decoding
  the LZW image data. Kept: the header, the logical screen and its
  colour table, the graphic control extensions, the `NETSCAPE2.0`
  application extension (looping), and each image (its descriptor,
  colour table and data), each as it was, then the trailer. Dropped:
  comment extensions, plain text extensions (text drawn over the image,
  which hardly any viewer shows), every other application extension
  (`XMP DataXMP` among them) and anything after the trailer.
- **PDF** is stored as given. A PDF's metadata (author, title) is part
  of the document its owner chose to send, and taking it out would mean
  parsing the PDF.

The stored file is the one with metadata taken out; its size and SHA-256
are of that file.

## 4. Attaching files

### 4.1 The `files` type

An operation takes files through a parameter of the type `files`:

```lisp
(define-operation items-create ((:draft item)
                                (screenshots :type (files :max 5) :label "Skjermbilder"))
    (:entity item :kind :create :policy :employee :title "Meld en sak")
  (setf (item-author item) (actor-name *actor*))
  (insert item)
  (attach-files item screenshots)
  item)
```

- `(files :max N)`, N from 1 to 10, default 10, is for operation
  parameters only; a stored field of the type is refused when the entity
  is compiled. An absent or empty list is no files.
- **Over MCP and `/api`**, the value is an array of objects, each
  `{"filename": "skjermbilde.png", "data": "iVBORw0KGgo…"}`: `filename` a
  string of at most 255 characters, and `data` the file's bytes in base64
  (RFC 4648 §4, the standard alphabet, padding as it should be; line
  breaks are ignored, any other character is refused). Its JSON Schema in
  `tools/list` says so, with `"contentEncoding": "base64"` and the
  allowed types in the description.
- **A URL is not taken.** An object with `url` is refused: «Tun henter
  ikke filer fra en adresse. Send innholdet som base64 i data.» Tun
  never fetches a file on a caller's behalf. A `data` that starts as a
  data URL (`data:image/png;base64,…`) is refused with its own message:
  «Send bare base64-innholdet i data, uten «data:…;base64,» foran.»
- **From a page**, the files a person chose arrive in the posted form
  (§6.2), and `web-call` passes them on as they are.
- Each file is checked by §2 and stripped by §3 while the input is
  decoded, before the operation's transaction opens, so the single writer
  is not held while it is done. A refused file is an `invalid_input`
  field error at its place, such as `screenshots[1]`, and nothing of the
  call is stored.
- **Only `data` is long.** In a body that may carry files (§4.3, of any
  size), the one string allowed past the 1 MiB bound of `core.md` §7.5 is
  the `data` member of a file in a `files` parameter. Any other string
  over 1 MiB, a value or a key, answers the request 413 before any tool
  runs, with «Bare innholdet i en fil kan være lengre enn 1 MB.» (as the
  JSON-RPC error `-32600` on `/mcp`), and neither the answer nor the
  request's record holds that string.
- **Request records keep no content.** The request's record of a call
  over MCP or `/api`, in the history of recent requests in memory
  (`core.md` §8.1, a thousand by default), keeps each file only as
  `{"filename", "bytes"}`: its name, at
  most 255 characters as given (§2.3), and its decoded size. The base64
  or the handle is replaced when the record is made, not when it is
  shown, so neither `introspect_request` nor anything else that reads
  the record can give it back, and the history never holds a file. The
  record of a page's post keeps no operation's input at all, so neither a
  file nor its handle. A
  fault recorded in the store keeps no input at all (`errors.md` §4),
  and its message is Tun's own text about the file (such as «Filtypen er
  ikke tillatt…»), never any of the file's content.
- `(attach-files RECORD FILES)`, inside a write, stores FILES, the
  parameter's value, as attachments of RECORD, a stored record of an
  entity that takes files, and returns them. It refuses past the entity's
  `:max` (§2.2). It is ordinary code in the operation: the operation's
  policy and the record's policy have already decided the call.

### 4.2 The tools

| Tool | Policy | Input | Output |
|---|---|---|---|
| `attachments_add` | employee, and the entity's `:policy` | `{"entity", "record_id", "files"}` | `{"items": [attachment]}`, the files added |
| `attachments_list` | viewer | `{"entity", "record_id"}` | `{"items", "returned", "has_more"}`, every file of the record in the order added, `has_more` false |
| `attachments_remove` | employee, and the entity's `:policy`; the one who attached the file, or an admin | `{"id"}` | `{"id", "removed": true}` |

- `entity` is the entity's name as `registry_describe` gives it (`item`).
  One that does not exist or takes no files is `invalid_input`.
- The record must be one the caller may see (§5.2); otherwise, and for an
  unknown id, the answer is `not_found`, the same for both. A role below
  the entity's `:policy` is `forbidden`.
- **Who removes which.** Each file records the account that attached
  it, by its name (`created_by` is `employee:kari`; the account is
  `kari`, which it keeps when its role changes). An admin who may see the
  record may remove any of its files. Anyone else may remove only those
  their own account attached: another's file is `forbidden`, once the
  record is one they may see; one whose record they may not see is
  `not_found`, as above. A file attached by the system (a job, a
  workflow, a scenario) is removed by an admin only.
- `attachments_remove` of a file whose entity the running code does not
  define, or whose entity no longer takes files, is `not_found` for
  everyone, admins too, as `GET /files/ID` is (§5.2).
- They are audited as any tool, with the record as `entity_type` and
  `entity_id`; `attachments_add` takes `request_key`.
- An attachment is `{"id", "entity", "record_id", "filename",
  "content_type", "size", "width", "height", "created_at", "created_by",
  "url"}`: `width` and `height` null for a PDF, `created_by` the actor
  that attached it, as the audit records it,
  and `url` the path `/files/ID`, at the public URL when the server has
  one (`deploy.md` §1).

### 4.3 Request size

The bounds of `core.md` §7.5 stay for every request but these, which may
carry files:

| Request | Body at most | When |
|---|---|---|
| `POST /api/TOOL`, TOOL a tool with a `files` parameter | 16 MiB | the caller is authenticated (`api.md` §2) with a role TOOL's policy admits |
| `POST /mcp` | 16 MiB | the caller is authenticated with a role the policy of some tool with a `files` parameter admits; a body over 2 MiB must be one `tools/call` of such a tool |
| `POST` of `multipart/form-data` to a page | 26 MiB | the request carries the session of a signed-in person whose role the page at the path admits |

- **Before the body is read.** The caller, its role and the tool or page
  are decided from the request line and headers alone. A body over
  2 MiB that the table does not admit is answered before it is read: 413
  when it is over the bound or the caller is not one the table names, as
  a body over a request's bound is now, and 403 for a multipart post
  from a person the page does not admit (the page's 403, as `ui.md` §8
  says).
- **Values.** Every body is held to `core.md` §7.5's 10 000 JSON values,
  however large it may be: a file's data is one long string, not many
  values.
- **A file's data is set aside.** In a body from a caller who may send
  files, to `/api/TOOL` for a tool that takes files from them or to
  `/mcp`, each string longer than 1 MiB of the body's octets is taken as a
  file's data before the body is parsed: its base64 is decoded straight
  from the body's octets (the escapes `\/`, `\n` and `\r` allowed), and
  the string is never made as text. Whatever the body's size, a file of
  about a megabyte fits in a body under 2 MiB. What is left of the body
  must be at most 2 MiB, or it is answered 413 «Utenom filenes innhold
  kan en forespørsel være høyst 2 MB.». A string set aside anywhere but in
  a file's `data`, and any other string, value or key, over 1 MiB, is
  refused (§4.1): 413 «Bare innholdet i en fil kan være lengre enn 1 MB.»
- A body over 2 MiB to `/mcp` that is anything but such a call is answered
  413, with the JSON-RPC error `-32600` «Over 2 MB tas bare imot for et
  verktøy som tar filer.»
- **Four at once.** Every body over 256 KiB takes one of the four places
  of `core.md` §7.5 before it is read, these among them: every body over
  2 MiB is one. A place is held until the answer is sent, since memory
  peaks after the read, while the files are decoded and checked. With
  the four taken, a page's multipart post is answered with a page with
  the message «Serveren tar imot mange filer akkurat nå. Prøv igjen om et
  øyeblikk.», so a person sees why and that trying again will do. Four
  such requests at their largest, beside ordinary traffic, stay within
  the memory budget of `core.md` §7.5.
- **A time limit.** A body over 256 KiB must arrive within 120 seconds of
  when it is read (a smaller one within 30, `core.md` §7.5). One that has not, or that stops coming, is answered 408
  and its connection closed, and its place is freed, so a slow or stalled
  sender cannot hold a place.
- A caller Tun does not know before reading the body (no token, no
  signed-in session) never makes the server read more than 256 KiB
  (`core.md` §7.5).
- **A refusal ends the connection.** Every answer given before the body
  is read (400, 401, 403, 408, 411, 413, 503) carries `Connection: close`,
  and the connection is closed once it is sent, so nothing the client
  sent after it, such as the unread body, is read as another request.
  First, the rest of the body its `Content-Length` declared is read and
  dropped, for at most 2 seconds and 26 MiB, so a client still sending
  it can read the answer instead of finding its connection reset.

**Multipart posts.** `multipart/form-data` is for a signed-in person
only:

- A `multipart/form-data` post another site's page sent (judged as any
  page's post is, `auth.md` §3.3) is answered 403 «Skjemaet kom fra et
  annet nettsted og ble avvist.» before its body is read.
- A `multipart/form-data` post without the session of a signed-in person
  (a staff session, or with claimed identity the claimed actor) is
  answered 401, whatever its size, before its body is read. A public
  page's session (`tun_public`, for a customer's offer) is not one.
- Tun reads the parts itself, in memory, from the body it has bounded;
  nothing of a post is written to disk. It stops at the first problem,
  and the post reaches no page. Each answer is a page with its message:

  | Problem | Status | Message |
  |---|---|---|
  | more than 64 parts | 413 | «Skjemaet har for mange felt (høyst 64).» |
  | more than 10 parts with a file | 413 | «Du kan sende høyst 10 filer om gangen.» |
  | a part's headers over 8 KiB | 413 | «En del av skjemaet har for lange overskrifter (høyst 8 KB).» |
  | a text part (one without `filename`) over 1 MiB | 413 | «Et felt i skjemaet er lengre enn 1 MB.» |
  | text parts over 2 MiB together | 413 | «Feltene i skjemaet har mer enn 2 MB tekst til sammen.» |
  | no `boundary`, or one over 70 characters (RFC 2046 §5.1.1); no closing delimiter; a part without `Content-Disposition: form-data` or without `name`; headers that do not end | 400 | «Skjemaet kunne ikke leses. Last siden på nytt og prøv igjen.» |

- **Names.** A part's `name` and `filename` are the quoted strings of its
  `Content-Disposition`, read as UTF-8, with each byte that is not part
  of valid UTF-8 replaced by U+FFFD. The escapes browsers write there
  (`%22` for `"`, `%0D` and `%0A` for a line break) are decoded, and no
  other `%`; `filename*` is not read. The name is then cleaned as §2.3
  says.
- **Empty files.** A part with an empty `filename` and no content is a
  control with nothing chosen and is left out. A part with a `filename`
  and no content is a chosen file that is empty, refused as «Filen er
  tom.» when the operation decodes it.
- Text parts are read as UTF-8, as a urlencoded post's are.

So an agent attaches one file of up to about 11 MiB per call (its base64
is a third larger), and a person up to 10 files of 10 MiB, 25 MiB
together, in one post.

## 5. Storing and serving

### 5.1 In the tenant's database

- An attachment's metadata is a record of the internal entity
  `attachment` (table `attachments`, not in `registry_describe`): its id,
  `fil_` and 26 random characters (130 bits), the entity, the record's
  id, the filename, the content type, the size, width and height, the
  SHA-256, `created_at` and `created_by`.
- Its bytes are in the table `attachment_contents` (`id`, `content
  BYTEA`), written in the same transaction as the record. Only the
  kernel reads and writes it; no query, client or module names it.
- **Postgres only.** The memory store keeps files in memory, for tests.
  The SQLite store refuses an attachment, as it refuses a query
  (`store.md` §1).
- So a file is part of the tenant's data where the rest of it is
  (`deploy.md` §4): the nightly dump holds it, a restore brings it back
  with its record, two processes of a blue/green switch see the same
  files, and the image and the container's disk hold none. A plain dump
  writes bytes as hex, twice their size, which gzip mostly takes back.
- **Deleting.** `delete-entity` of a record whose entity takes files
  deletes its attachments, and their bytes, in the same transaction.
  `attachments_remove` deletes one. A core schedule, `attachments_sweep`,
  each night at 03:30 Norwegian time, deletes the attachments whose record
  no longer exists, as `system:job`, so a record deleted another way (by
  hand, in SQL) does not leave files behind. It leaves the attachments of
  an entity the running code does not know alone: after a rollback of the
  code, their records may still be there.

### 5.2 Who may fetch a file

`GET /files/ID` answers the file to a caller who may see its record, and
to no one else. It is checked on every request, by the record, never by
the address alone:

- The caller is the signed-in person of the request's session, or an
  access token sent as `Authorization: Bearer` (an agent, as on `/api`),
  or, with claimed identity, the claimed actor.
- The record is fetched as the caller, in a read transaction, so the
  entity's record policy applies (`store.md` §6), and the entity must be
  readable by the caller (`entity-readable-p`, by the entity's read
  operations' policies, which a module or client may specialise).
- A file whose entity the running code does not define, or whose entity
  no longer takes files (`:attachments` taken out), is not served to
  anyone, admins included: the code that decided who may see it is gone.
- A file whose record the caller may not see, a file that does not exist,
  a file whose record was deleted and an id that is not one all get the
  same 404. Without a caller, the answer is the 401 page a staff page gives («Du er ikke innlogget»).
- `/files/` is Tun's path, as `/login` is: no page takes the prefix
  `files`.

### 5.3 The answer

| Header | Value |
|---|---|
| `Content-Type` | the type of §2.1 |
| `Content-Length` | the size |
| `Content-Disposition` | `inline` for an image and `attachment` for a PDF, with `filename` (ASCII, others as `_`) and `filename*` (UTF-8) |
| `X-Content-Type-Options` | `nosniff` |
| `Content-Security-Policy` | `default-src 'none'; style-src 'unsafe-inline'; sandbox; frame-ancestors 'none'` |
| `Cross-Origin-Resource-Policy` | `same-origin` |
| `Referrer-Policy` | `no-referrer` |
| `Cache-Control` | `private, no-cache` |
| `ETag` | the SHA-256 in quotes |

- A request with `If-None-Match` naming the ETag, once the caller is let
  in, is answered 304 without the body.
- A PDF is always downloaded, never shown in the browser: a PDF can hold
  script, and a browser's viewer will not run under the sandbox.
- `HEAD` answers the same headers without the body.

### 5.4 Sending a file in parts

A page of thumbnails asks for many files at once, so an answer never
holds a whole file in memory:

- The caller is checked and the attachment's metadata read first, in one
  read transaction. A `HEAD`, a 304 and a refusal read nothing else:
  not a byte of the content.
- The content is then read and sent 1 MiB at a time, each part read
  (Postgres: `substring` of the `BYTEA`) in a read transaction of its
  own, which ends before the part is written to the connection. So an
  answer holds at most 1 MiB of a file and no transaction while it
  waits for a slow reader, and no connection to the database is held
  for longer than one part's read.
- A file deleted while it is being sent ends the answer early: the
  connection is closed, short of its `Content-Length`.
- An answer not sent within 120 seconds of its first byte has its
  connection closed at once, so a reader that stops reading frees its
  request. The limit bounds only the writes to the connection, never the
  store's reads.
- Thirty-two fetches of a 10 MiB file at once, beside ordinary traffic,
  are answered within the default heap of 2 GiB.

## 6. In pages

### 6.1 `file-input`

A form control (`ui.md` §6, Skjema) for one or more files:

```lisp
`(:form (:@ :method "post" :action "/saker/ny" :enctype "multipart/form-data")
        ,(ui:text-input (:label "Tittel" :name "title"))
        ,(ui:file-input (:label "Skjermbilder" :name "filer"
                         :hint "PNG, JPEG, WebP, GIF eller PDF, opptil 10 MB hver."))
        ,(ui:button (:type "submit") "Meld saken"))
```

- It is a `field` (label, hint, error, as the others) around a drop zone
  holding an ordinary `<input type="file" multiple>` with NAME and
  `accept` naming the types of §2.1. Without JavaScript the browser's own
  control chooses files and the form posts them. The form must be
  `method="post"` and `enctype="multipart/form-data"`; `enctype` is
  allowed in extension output (`tun.html`). `:max` (default 10) is the
  most files the control takes.
- **With JavaScript:**
  - a file chosen in the control, dropped on the zone, or pasted is
    added to what is chosen: a paste (`paste` with files in its
    `clipboardData`, as a screenshot is) anywhere in the form, or
    anywhere in the page when it has one `file-input` only. A paste of
    text alone is left to the field it goes into, and a paste with files
    puts nothing into the field;
  - **a pasted file's name.** A pasted file whose name is empty, or
    `image` with any extension (what browsers call an image from the
    clipboard, such as `image.png`), is named
    `skjermbilde-HHMMSS.EXT`: HHMMSS the hours (00–23), minutes and
    seconds of the browser's clock, in the device's own time zone, when
    the paste happened, and EXT `png`, `jpg`, `webp` or `gif` by the
    file's type as the browser gives it (`png` when it gives none). When
    the list already has a file of that name, `-2`, then `-3` and so on is
    added before the extension (`skjermbilde-142305-2.png`). Any other
    pasted file, such as one copied in a file manager, keeps its name.
    Choosing and dropping never rename;
  - the zone, while a file is dragged over it, is marked, and says «Slipp
    for å legge ved»;
  - what is chosen is listed under the zone before the form is sent, each
    with a small preview when it is an image, its name and size, and a
    «Fjern» button that takes that file out;
  - a file is not added, and the list says why under the zone, when
    its type, as the browser gives it, is not one §2.1 takes («NAVN:
    filtypen er ikke tillatt.»), when it is over 10 MB («NAVN er større
    enn 10 MB.»), when the control has `:max` files already («Du kan
    legge ved høyst 10 filer.»), or when it would take what is chosen
    past 25 MB together («Filene kan ikke være større enn 25 MB til
    sammen.»). The server decides again, by the bytes.
  The chosen files are the control's own (`input.files`), so the form
  posts them as it would without JavaScript, through htmx or not.
- After a refused post, the files are not kept: the person chooses them
  again. The error is at the field, as for any control. A post that
  meets the four places for large requests taken (§4.3) gets a page
  saying so, and the person sends it again.

### 6.2 What a page receives

A `multipart/form-data` post to a page (`ui.md` §8) gives the page's FORM
the text parts as before, and for each name with files a JSON array of
`{"filename", "upload"}`. `upload` is an opaque handle to the file Tun
has kept for this request, valid only until the request is answered and
only for the request that posted it: a handle a caller sends over MCP or
`/api` is refused («Filen må sendes som base64 i data.»). A part with no
file (nothing chosen) is left out. The parts are read as §4.3 says,
within its bounds, and a file over 10 MiB is refused when the operation
decodes it.

```lisp
(define-page items-page ("saker" :title "Saker" :icon :list-todo)
    (method path form query)
  (if (and (eq method :post) (equal path '("ny")))
      (multiple-value-bind (item code)
          (web-call "items_create" (jobj "title" (jget form "title")
                                         "screenshots" (jget form "filer")))
        (if code
            (values 422 "Meld en sak" (list (error-alert item) (new-item-form form item)))
            (values 303 (format nil "/saker/~a" (jget item "id")))))
      …))
```

A file of a post is held in memory for the request and dropped with it;
none is written to a temporary file.

### 6.3 `attachments`

A record's files (`ui.md` §6, Data), from `attachments_list`:

```lisp
(ui:attachments (:items (jget (web-call "attachments_list"
                                        (jobj "entity" "item" "record_id" id))
                              "items")
                 :label "Vedlegg"))
```

- An image is a thumbnail: a link to its path, `/files/ID` on the server
  the page came from, around an `<img>` with
  `alt` its filename, `width` and `height` its own, `loading="lazy"` and
  `decoding="async"`, shown in a square tile (`object-fit: cover`). The
  browser scales the image itself; Tun makes no smaller copy (§7).
- A PDF is a tile with the file icon, its name and size, linking to its
  path, which downloads it.
- A file's link is neither boosted nor preloaded by htmx (`ui.md` §4.1):
  a file is not a page.
- Without JavaScript, an image's link opens the image itself, full size.
  With it, a click opens a dialog with the whole image, as large as the
  window allows and never larger than its own size, its name, a link
  «Åpne original» to its path, and «Lukk»; Escape closes it too.
- With no items it shows EMPTY («Ingen vedlegg» when omitted).
- The tiles wrap in rows, three or more to a row on a phone, without
  scrolling the page sideways.

### 6.4 Generated forms

An operation with a `files` parameter gets a `file-input` for it in its
generated form, and the form gets `enctype="multipart/form-data"`.

## 7. Not yet

- **Smaller thumbnails made by the server.** A phone on mobile data loads
  the whole image for a thumbnail, lazily. Making a small copy means
  decoding uploaded images, in Lisp or in a tool such as libvips, which
  is the part of image handling where the attacks are; until that is
  worth it, the browser scales.
- Fetching a file from a URL (§4.1).
- Reading a file's bytes through MCP, such as an image content block; an
  agent fetches `/files/ID` with its token.
- Removing a file from the `attachments` component, and files on the
  generated record page; a page builds its own form for
  `attachments_remove`.
- Files from someone not signed in, such as a customer on a public page
  (§4.3).
- Files on SQLite; a quota of storage per tenant; scanning files for
  malware; taking metadata out of PDF.

## 8. Evidence

- `tests/files-tests.lisp`:
  - the `:attachments` option, its refusals and `registry_describe`;
  - each type recognised from its bytes whatever its name, and SVG, HTML,
    text named `.png`, a ZIP and an empty file refused;
  - for each format, a damaged file refused as §2.1 says: a chunk,
    segment, sub-block or RIFF size running past the end, a PNG without
    `IDAT` or `IEND` or with an unknown critical chunk, a JPEG without
    `EOI`, with a second frame header or with `DNL`, a GIF without its
    trailer or with a block of an unknown kind, a zero width; a JPEG with
    fill bytes taken;
  - width and height of each type, swapped for a JPEG turned a quarter;
    the pixel bounds, for a GIF frame and a WebP frame too;
  - what is kept and dropped (§3): a JPEG with Exif (GPS), XMP, IPTC, a
    comment, `JFXX`, a JFIF thumbnail, `MPF` and an image after `EOI`,
    progressive with segments between its scans; a PNG with text, time,
    Exif and an unknown ancillary chunk; a WebP with `EXIF`, `XMP ` and an
    unknown chunk; a GIF with comments, an XMP application extension,
    `NETSCAPE2.0` and bytes after the trailer; in each, what is kept is
    byte for byte as given; a PDF as given; an unreadable Exif and two
    Exif segments giving no orientation;
  - the file handling depends on no library that decompresses or
    decodes images and runs no program: a test reads `tun.asd` and the
    sources;
  - names (§2.3), the 255-character bound and the 200-character cut,
    among them `faktura‮gnp.pdf` and the other Cc and Cf
    characters; base64 and its refusals; a URL and a data URL refused,
    each with its message; a page's handle refused over MCP;
  - the limits per file, per call and per record, nothing stored when one
    file is refused or the record is full;
  - the tools: policies, the entity's `:policy`, `not_found` for a
    record the caller may not see (on Postgres, with a record policy) and
    for a file of an entity no longer defined or no longer taking files,
    audit, `request_key`;
  - a client operation with a `files` parameter: record and files in one
    transaction; the request record in the history holding each file as
    `{"filename", "bytes"}` and nothing more, and a stored fault no input
    and no content in its message; a string over 1 MiB other than `data`
    refused;
  - `GET /files/ID`: the bytes and every header of §5.3, 304, 404 alike
    for another's record, an unknown id, a deleted record and an entity no
    longer defined or taking files, 401 without a caller, an access
    token;
  - deleting a record deletes its files, and a rollback keeps them; the
    sweep deletes files whose record is gone and leaves an unknown
    entity's;
  - every byte value round-trips through Postgres; SQLite refuses;
  - a file sent in parts of 1 MiB, `HEAD` and 304 reading no content, a
    file deleted while it is sent, and a reader that stops cut off after
    the time limit;
  - 32 fetches of a 10 MiB file at once answered in a 2 GiB heap.
- `tests/safety-tests.lisp`: the bounds of §4.3:
  - 413 before reading for a caller who is not authenticated, for a role
    no tool with files admits, for another tool on `/api` and past each
    bound; a large `/mcp` call to `attachments_add` taken and one to
    another tool refused;
  - a multipart post without a signed-in session, small or large, with
    or without a public page's session, answered 401 before reading; a
    large one from a role the page does not admit answered 403 before
    reading; one with a session taken; each problem of §4.3's table
    answered with its status and message; names decoded as §4.3 says;
    an empty chosen file refused and an empty part left out; nothing
    written under `/tmp`;
  - a large body that has not arrived within the time limit, its
    connection closed and its place freed;
  - a fifth large request refused with 503 while four are being
    answered, not only while their bodies are read, with a page for a
    page's post;
  - four requests at the largest bounds at once (16 MiB to `/mcp` and
    `/api`, 26 MiB multipart), beside ordinary calls, answered while the
    server stays up, its heap at the default 2 GiB.
- `tests/hostile-tests.lisp`: the memory budget of `core.md` §7.5, the
  files' lines among it: a body of files as JSON and a multipart post at
  their bounds, with long text beside the files, each within its cost;
  eight at once beside sixty small requests, three times over.
- `tests/ui-forms-tests.lisp`, `tests/ui-data-tests.lisp`: `file-input`
  and `attachments` render as §6 says, in extension output too; a
  generated form with a `files` parameter.
- `tests/web-tests.lisp`: a page receives files as §6.2 says, and passes
  them to an operation; a refused file answers the page with the error
  at the field.
- `checks/showcase/checks/`: attaching by choosing files, by dropping
  them and by pasting a screenshot (its name by the rule of §6.1), with
  the list, its previews and «Fjern»; a form without JavaScript; a
  thumbnail opening the whole image in a dialog; a PDF's tile.
