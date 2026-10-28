# Mail

Status: v1, 2026-10-15; HTML built from nodes (§2.1), core 1.22.0; the
frame's language, and Tun's own mail in the tenant's (`i18n.md` §8), core
2.0.0. How
an application sends email: a mail is written in the same transaction as
the work that sends it, and delivered after that work commits, through the
application's mail provider, with retries. Resend is the provider Tun
ships; without one, mail is recorded and logged but not sent.

## 1. Choosing the provider

`define-application` names it in its `(:mail …)` option
(`docs/client-api.md`):

```lisp
(define-application tracker-application ()
  (:mail (:resend :api-key (:env "RESEND_API_KEY")
                  :from (:env "MAIL_FROM"))))
```

| Provider | Settings |
|---|---|
| `(:resend …)` | `:api-key`, `:from` |
| `(:log)` | none |

- A setting is a string, or `(:env "NAME")`: the value of that
  environment variable, read when the server starts, as for sign-in
  (`auth.md` §3.5). The API key belongs in the deployment's SOPS file
  (`deploy.md` §3), never in the repository.
- `:from` is the sender, such as `Saker <varsel@example.no>`. Resend
  sends only from a domain verified in its dashboard.
- Without the option, the provider is `(:log)`.
- In authenticated mode a server whose provider lacks a value refuses to
  start, with exit status 2 and a line naming what is missing. In claimed
  mode, and in an application opened in-process (a test), it uses
  `(:log)` instead and says so.
- `(:log)` sends nothing. It accepts every mail at once, records it as
  sent by `log`, and writes the recipient and subject, not the text, to
  the server's standard output.

## 2. Sending

`(send-mail &key to subject text html reply-to key)`, in the TUN package,
is called inside a write: an operation, a workflow, or an `:on-open`
function.

- `to` is one address and `subject` (at most 998 characters) is
  required. `text` (at most 100 000 characters) is the plain-text part;
  `html`, a node tree (§2.1), is the HTML part. A mail needs `text`, or
  `html` for the text to be made from. `reply-to` (one address) is
  optional. An address is checked as the `email` field type checks it. A
  bad argument signals an error, so the operation fails `invalid_input`
  and nothing is written.
- It stores a mail with status `queued` and returns it. The mail is part
  of the caller's transaction: when the operation fails or rolls back, no
  mail exists and none is sent.
- `key`, a string of at most 200 characters, makes the send once only:
  when a mail with that key exists, in any status, `send-mail` returns it
  and stores nothing. A notification uses one, such as
  `"answer:kom_…"`, so sending it again is harmless.

### 2.1 HTML from nodes

`html` is markup as data, in the node grammar of the renderer in
`src/web/html.lisp`, as a page is built: a node is a
string, which is escaped, a number, NIL, which is nothing, a proper list
of nodes, or an element `(:tag [(:@ :attr value …)] child…)`, its tag a
keyword. Tun renders it with its escaping renderer, checked against the
mail allow-list below, inside a default frame, and stores the result; a
result over 500 000 characters fails on `html`.

```lisp
(send-mail :to address
           :subject "Sammendrag: 2 nye saker"
           :html `((:h1 "Sammendrag")
                   (:p "To nye saker siden i går:")
                   (:ul ,@(mapcar (lambda (item)
                                    `(:li (:a (:@ :href ,(format nil "/saker/~a" (entity-id item)))
                                              ,(item-title item))))
                                  items))))
```

**The allow-list.** Anything outside it is refused, not dropped: the
send fails `invalid_input` on the field `html`, with a message naming
what was refused, and nothing is stored. Anything outside the grammar
above is refused the same way, never with an internal error: a node
that is none of those (a symbol, a character, a vector, an improper
list, a keyword that is not at the head of an element, Tun's own
`trusted` and `untrusted` markup objects), an attribute name that is not
a keyword, a `(:@ …)` with an odd number of items or not right after the
tag, an attribute value other than NIL, a string or a number, such as T,
a circular list, and a tree deeper than 200 levels. Tags and attribute
names are compared in lower case, as a page writes them, so `:|href|` is
`href`. The tree is the client's code,
so a tag the list lacks is a mistake that a test should find, rather than
a mail that silently looks different; what a person typed is a string in
the tree, and a string is always escaped.

| Allowed | |
|---|---|
| Elements | `a`, `p`, `h1`, `h2`, `h3`, `ul`, `ol`, `li`, `strong`, `em`, `br`, `hr`, `span`, `div`, `img`, and `table` with `caption`, `thead`, `tbody`, `tfoot`, `tr`, `th`, `td` |
| On any of them | `style`, `title`, `lang`, `dir` |
| On `a` | `href` |
| On `img` | `src`, `alt`, `width`, `height` |
| On `th`, `td` | `colspan`, `rowspan`, `scope` |

- **Links.** An `href` starts with `https://`, `http://` or `mailto:`,
  in any case of ASCII letters (`HTTPS://`, `Mailto:`), compared as ASCII
  only, and is then written as it was
  given; or it is a path, `/` then anything but a second `/` or `\`, such
  as `/saker/sak_1`, which is made a whole link with `absolute-url`
  (`deploy.md` §1): a server without a public URL keeps the path, as
  `absolute-url` does. Anything else is refused: `javascript:`, `data:`,
  `//host`, `/\host`, a relative `saker`, a `#part`, an empty value.
- **No spaces or controls in a URL.** An `href` or `src` holding a space,
  a tab, a line break, another control character or a backslash anywhere
  is refused, also before an allowed URL (` https://…`): nothing is
  trimmed, so what is checked is what is written. A space in a link is
  written `%20`.
- **Images.** An `img`'s `src` starts with `https://`, in any ASCII case, under
  the same rule for spaces; nothing else is allowed, not a path,
  `http://` or `data:`.
- **Style.** `style` is inline only, as declarations `property: value`
  separated by `;`. A property is one of `color`, `background-color`,
  `font-size`, `font-weight`, `font-style`, `line-height`, `text-align`,
  `text-decoration`, `vertical-align`, `width`, `max-width`, `height`,
  `margin`, `padding`, each of `margin-` and `padding-` with `top`,
  `right`, `bottom` or `left`, `border`, `border-top`, `border-bottom`
  and `border-radius`. A property's name is compared in any case and
  written in lower case. A value holds only ASCII letters and digits,
  spaces and `# . , % -`, and `rgb(…)` or `rgba(…)` of digits, `.`, `,`,
  `%` and spaces; it is not empty. Anything else is refused, naming the
  declaration: another property, `url(…)`, `expression(…)`,
  `!important`, quotes, a backslash, a letter outside ASCII, a
  declaration without `:`. Empty declarations (`;;`, a `;` at the end)
  are skipped. The declarations are written again as they were checked,
  `property: value` joined by `; `.
- An attribute whose value is NIL is left out, as on a page.
- **Not a node tree.** A string as the whole `html` is refused: it is
  what a caller that wrote HTML by hand would pass, and it would arrive
  escaped. Plain text belongs in `text`. Raw HTML is not accepted in any
  form.

**The frame.** Every HTML part is a whole document: `<html lang="LANG">`
with the current language's code (`i18n.md` §2.4),
a head with `charset`, a `viewport` for phones and the subject as
`title`, escaped as the tree's strings are (a subject
`</title><img src=x onerror=…>` is text in the title, not markup), and a
body holding the tree in a column at most 600 px wide,
centred, with 24 px above and 16 px at the sides, in the system's own
sans-serif font at 16 px with a line height of 1.5, and long words and
links broken rather than widening it. It has no style sheet, no external
CSS, font or script: everything is inline. Elements get a default
`style` before their own, so a tree without styles is readable on a
phone: headings 24, 20 and 17 px, links underlined, images at most the
column's width, tables full width with padded cells, an `hr` a thin
line. A paragraph, a list and the inline elements have none, and keep
the mail app's own. A declaration of the element's own `style` comes after the
default and wins.

**The text part.** Without `text`, it is made from the same tree:

- A paragraph, a heading, a `div`, a list, a table and an `hr` stand on
  their own, a blank line between each; `br` is a line break, `hr` a line
  of three dashes.
- A link is «text (url)», with the whole link, or the url alone when the
  text is the url, or the address for `mailto:`.
- An item of a `ul` starts with «- », of an `ol` with its number, «1. »;
  a list inside an item is indented two spaces.
- A table's rows are lines, its cells separated by « | ».
- An image is its `alt`, or nothing.
- Spaces and line breaks in strings collapse to one space, as the HTML
  shows them; the text has no space at the start or end of a line.

A `text` given is used as it is, and checked as it always was: a blank
one is refused on `text`, not replaced; leave it out (NIL) to have it
made from the tree. The text made from a tree is checked as a given one
would be, on the field `text`: when it is empty, as for a tree of an
image without `alt`, the send fails `invalid_input` on `text` («må
fylles ut»), and over 100 000 characters on `text` too.

A mail with `html` always has both parts, so the provider sends it as
`multipart/alternative`; a mail with `text` alone is text alone, as
before.

**Previewing.** `(render-mail HTML &key subject text)`, in the TUN
package, returns the two parts send-mail would store, the HTML and the
text, with the same checks, its subject's included, and stores nothing.
A page that shows a mail before it is sent, or a test of what a mail
says, uses it.

## 3. Delivery

Each mail is delivered by a job (`jobs.md`), `send_queued_mail`, enqueued
with it in the sender's transaction; the mail's `job_id` names it.

- The job runs in the `:mail` queue, one at a time unless the application
  says otherwise (`(:queues (:mail N))`), outside any transaction, so a
  slow provider never holds the writer lock or delays other work.
- In test mode `clock_set` runs it with the other due jobs and answers
  how many attempts they made, as `job_attempts`.
- An attempt marks the mail `sending` and counts it, calls the provider
  within 10 seconds, then records the outcome:

| Outcome | Status | Next |
|---|---|---|
| accepted | `sent`, with `provider`, `provider_id` and `sent_at` | none |
| temporary (a timeout, no connection, 409 from a request already in progress, 429, 5xx) | `queued` | the job's next attempt, after 30 s, 2, 10 and 30 minutes, 1 hour, then 3 hours |
| permanent (any other answer) | `failed` | none: the job fails at once (`fail-job`) |

- After the seventh attempt a temporary outcome also leaves the mail
  `failed`, and its job failed. Each delay gets up to a tenth more at
  random, so mails that failed together do not retry together; in test
  mode it is exact.
- `last_error` holds the last attempt's reason, such as `resend 422
  validation_error: …`, until the mail is sent. The job keeps every
  attempt's (`jobs_get`).
- A mail left `sending` by a process that stopped during the call is
  attempted again when its job is recovered (`jobs.md` §7), within a
  minute, by whichever process notices. Nothing is requeued when a
  process merely starts, so the other process of a blue/green switch
  keeps its own.
- Every attempt sends the mail's id as the provider's idempotency key.
  Resend keeps a key for 24 hours, and every retry falls within that, so
  a retry after a lost answer never sends the mail twice.

## 4. Resend

The adapter POSTs to `https://api.resend.com/emails`, over HTTPS with the
certificate verified, with `Authorization: Bearer API-KEY`,
`Idempotency-Key: MAIL-ID` and a JSON body: `from`, `to` (a list of one),
`subject`, `text`, and `html` and `reply_to` when the mail has them: a
mail with HTML always sends `text` beside it. A
200 answer's `id` is the mail's `provider_id`. An error answer's `name`
and `message` go into `last_error`. The API key is never written to a
record, a log line or a printed adapter.

## 5. Tools

Admin only. Mails are stored records, read through the tools:

| Tool | Does |
|---|---|
| `mail_list` | The latest 100 mails, newest first, optionally only one `status` or one `to`: id, to, subject, status, attempts, last error and times, without the text. |
| `mail_get` | One mail with its text and html. |
| `mail_retry` | Queue a `failed` mail again with a new delivery job, due at once, its attempts reset; any other status is `invalid_transition`. |

A mail's text is shown only to admins.

## 6. Not yet

- Several recipients, copies, attachments and templates. A client builds
  its text and its node tree itself, in the language it binds with
  `with-language` (`i18n.md` §2.4); mail Tun sends itself is in the
  tenant's language (`i18n.md` §8).
- A frame of the client's own, such as its logo and colours, and a
  style sheet in the head for mail apps that read one.
- Images attached to the mail (`cid:`) or as `data:` URLs.
- Another provider (SMTP, Postmark). Each is one class with one method
  (`docs/client-api.md`).
- Webhooks for what happens after the provider accepts a mail: bounces,
  complaints, opens.

## 7. Evidence

- `tests/mail-tests.lisp`: sending inside a write and nothing after a
  rollback; the key; validation; delivery through a scripted provider
  (accepted, temporary with each delay, permanent, the seventh attempt);
  a mail whose process stopped mid-send, recovered with its job; the
  delivery job in the `:mail` queue, run by the scheduler's worker;
  `clock_set`; the three tools and who may call them; the provider chosen
  from `(:mail …)` and the problems reported for missing settings; the Resend adapter over
  real HTTP against a fake Resend in the test process that checks the
  key, the idempotency key and the body, and answers 200, 422, 429 and
  500.
- `tests/mail-html-tests.lisp`: strings escaped; each element and
  attribute outside the allow-list refused, naming it, with nothing
  stored; what is outside the grammar refused with `invalid_input`;
  `javascript:` and the other links refused, schemes in any case, spaces
  and backslashes refused, a path made whole, an image's `src` https
  only; style properties and values; a string as the whole `html`; the
  frame, with the subject escaped in its title; the text part made from
  the tree, a `text` given kept, and an empty, over-long or blank text
  refused on `text`; `render-mail` as send-mail stores; Resend receiving
  both parts.
- `checks/showcase/checks/mail-preview.py`: the showcase's «E-post» page
  previews a summary of its cards with `render-mail` in an
  `<iframe sandbox="">` with no `allow-*` token; the mail is read at 390
  px without sideways scrolling, its text at 16 px or more, its column at
  most 600 px on a desktop, and its links, written as paths, start with
  the preview's public URL.
