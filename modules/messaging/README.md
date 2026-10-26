# tun module `messaging`

ASDF system `tun-messaging`, package `tun.messaging`; pinned by clients through
`flake.nix` in this directory (tun-platform.md §2, §4).

- **Owns:** immutable customer `message` snapshots and `delivery` outcomes, legacy immediate staff messages, the transport port and fake transport, versioned data templates, preview/send and human outcome-resolution operations, and communication/composer staff screens. `messages_list` accepts a template filter. Without this module nothing is sent.
- **Depends on:** `orders`, `customers`, `notifications`, `inbox`.
- **Core range:** builds against core `>= 1.3.0, < 2.0` (its deliveries are jobs) (`flake.nix` `core`,
  and `define-module` in the Lisp source; the client build and the module's
  load both refuse a core outside it, naming the constraint).
- **Publishes:** templates (a client template with the same key replaces a default), `send-message`, `message-status`. Its exported symbols are its interface for
  the modules that depend on it; what clients may use is what it publishes
  to `TUN`.
- **Rollback:** its migrations only add tables and nullable columns, so the
  previous revision starts on a migrated database; whether it can also read
  every stored record is what the rollback preflight checks
  (core.md §6.4): it refuses when a record holds a value the
  previous core cannot decode (a status, price mode or movement kind it
  lacks), an order-line field its next write would drop, or delivery records
  whose outcome the older registry cannot represent. Legacy staff actor TEXT
  remains readable without rewriting its recipient
  (docs/architecture.md, "Tenants and deployment").

The outbox rechecks erasure and marketing consent in its claim transaction.
Suppressed deliveries are failed and audited without a provider call or failure
notification. Provider calls run outside requests with a 4/10-second deadline.
At most four live provider calls, including abandoned calls, occupy a tenant;
further deliveries remain queued until a slot is free. Shutdown stops new
claims and abandons waiting port calls before closing the store.

## Contract

Errors, policy, idempotency and audit are the kernel's (core.md §3.3–§3.8):
reads are `viewer`, mutations `employee`. Every mutation is audited and
takes `request_key`. Settings are the kernel's registry (core.md §5.3), link
tokens the kernel's (core.md §5.4), workflows the kernel's (core.md §4) and
jobs spec/jobs.md's.

### 1. What the module does

Messaging sends mail to customers. A message is rendered from a template
once, frozen as a snapshot, and handed to an outbox; the outbox makes one
provider call per delivery, ever, outside every client request, and keeps
an outcome a person can trust. The module also keeps the communication
history of an order or a customer, outbound and inbound.

It is the adapter of the kernel's messaging port (core.md §5.1): `notify`
from any module (the orders module's `tilbud`, invoicing's `faktura`, a
client's workflows) renders and queues through `send-message`. A tenant
without this module sends nothing and still works. It reads inbound items
from the inbox module (§11) and publishes `leveranse_feilet` through the
notifications module (§9).

Settings it declares:

| Key | Type | Default | Used for |
|---|---|---|---|
| `avsender.navn` | string | `Tun` | the sender's name |
| `avsender.epost` | email | `noreply@example.invalid` | the from address |
| `avsender.svar_til` | email, nullable | null, meaning `avsender.epost` | reply-to |

The sender is read from the settings when a message is rendered and frozen
in it; a setting changed afterwards does not change a stored message.

### 2. Templates

#### 2.1 Registration

A template is registered with the kernel's `define-message-template` by a
module or a client: `{"name","version","subject","text","html"?,"variables","manual","marketing","final","module","source"}`.
A data template has a subject and text with placeholders (§3); a code
template is a function returning subject and body. A client template with
the name of a module's template replaces it and bumps the version, unless
the module marked it `final`, which is refused at start. `manual` templates
may be sent by staff (§4); `marketing` templates are under the consent
guard (§9).

`templates_list {}` (read) lists every template, sorted by name, with
`"overridden_by":"client"|null`.

#### 2.2 The module's defaults

| Name | Kind | Text |
|---|---|---|
| `tilbud` | data | subject `Tilbud`, text `Hei {{kunde.navn}}, her er tilbudet ditt: {{ordre.total}}.` |
| `faktura` | code | `Faktura`; the invoice of the order is sent, with its total |
| `lagervarsel` | code | `Lagervarsel: varer som mangler`; the missing articles by name |

A client usually replaces them with its own wording.

### 3. Rendering

Subjects and texts contain `{{path}}` placeholders: dotted paths, no logic.
Each is replaced by the context's value, inserted verbatim. A path listed
in the template's `variables` but missing from the context is
`template_variable_missing: <path>`: a manual send answers `invalid_input`,
a workflow run fails with a note naming the variable (core.md §4.3). Any
other missing path renders as the empty string.

| Path | Value |
|---|---|
| `kunde.navn`, `kunde.epost` | the customer; a blank name is `Kunde`; absent for an erased customer |
| `avsender.navn`, `avsender.epost` | the settings |
| `ordre.id`, `ordre.ref` | the order's id; `ref:<order id>` |
| `ordre.dato`, `ordre.periode` | `dd.mm.yyyy`, or `dato ikke fastsatt` for a dateless order; the period `dd.mm.yyyy–dd.mm.yyyy` or the single date |
| `ordre.sted`, `ordre.sted_suffix` | the site address or empty; ` på <address>` or empty |
| `ordre.linjer` | one line per order line, `<product> · <quantity>: <amount>`, the amount after the line's price mode; joined by newlines |
| `ordre.total` | the order's total |
| `levering.tid`, `levering.adresse`, `levering.metode` | `kl. HH:MM` from the delivery side's earliest time, or `ikke avtalt`; the site address or `adressen dere oppga`; the delivery method or empty |
| `bruksanvisninger_avsnitt` | `Digital bruksanvisning:` and one `<product>: <url>` line per rental product with a manual URL, then a blank line; or empty |
| `tilbud.lenke`, `tilbud.kode`, `tilbud.gyldig_til` | `<lenker.base_url>/tilbud/<quote id>`; the access code as `XXXXX-XXXXX`; the expiry as an instant |
| `tilbud.spørsmål_avsnitt` | `Vi mangler noen opplysninger:` and one `- <question>` line per open question of the order, then a blank line; or empty |
| `lenke.tilbakemelding`, `lenke.avmeld` | `<lenker.base_url>/tilbakemelding/<token>` (inbox README §3.4), `<lenker.base_url>/avmeld/<token>` (customers README §6) |
| `anmeldelse_avsnitt` | `Ellers setter vi stor pris på en aldri så liten anbefaling:` and the setting `anmeldelse.url`, when the client declares and sets it; or empty |
| `melding` | the free text of a manual `ordremelding`; default `Ta kontakt ved å svare på denne e-posten hvis noe må avklares.` |

Formats: money `5 390,00 kr` (two decimals, a comma, thousands separated by
a space); dates `dd.mm.yyyy`; instants `dd.mm.yyyy kl. HH:MM` in Norwegian
time (core.md §2.2).

The HTML variant is derived from the text: `& < > "` escaped, URLs made
links, a blank line starts a paragraph, a newline inside one becomes
`<br>`. The subject of a message about an order gets ` [ref:<order id>]`
appended, by this module and not by the template; inbound matching reads
it (inbox README §4).

### 4. Preview and manual send

#### 4.1 Tools

| Tool | Kind, policy | Input | Result |
|---|---|---|---|
| `messages_preview` | read, employee | `{"template","order_id"?,"customer_id"?,"subject"?,"text"?}` | `{"template","version","recipient","sender","subject","body","html","variables","snapshot_hash"}` |
| `messages_send` | create, employee | the same, plus `snapshot_hash` | the message (§5.1) |

`variables` in the preview is the rendering context.

#### 4.2 Checks, in order

1. Exactly one of `order_id` and `customer_id`, else `invalid_input` `Oppgi
   enten ordre eller kunde`; a template other than `neste_år` needs an
   order, else `invalid_input` `Malen krever en ordre`.
2. An unknown template → `not_found` `Malen finnes ikke`.
3. A `marketing` template for a customer who may not get marketing →
   `invalid_input` `kunden har ikke samtykket til markedsføring`.
4. An erased customer → `invalid_input` `kunden er slettet`.
5. A template that is not `manual` → `invalid_input` `Malen kan ikke sendes
   manuelt`.
6. `ordremelding` by an actor who is not admin → `forbidden` `Ordremelding
   krever admin`.
7. `text` for a template other than `ordremelding` → `invalid_input` `Tekst
   kan bare endres for ordremelding`.
8. The copy rules (§4.3) for `text`, then rendering, then the copy rules for
   `subject`.

`subject` replaces the template's subject; `text` is the `melding` value.

#### 4.3 Copy rules

All `invalid_input`; the texts are compared verbatim.

| Copy | Rule | Message |
|---|---|---|
| subject | a control character (U+0000–U+001F, U+007F–U+009F) | `Emnet kan ikke inneholde linjeskift eller kontrolltegn` |
| subject | empty after NFC and trimming | `Emne og meldingstekst må fylles ut` |
| subject | over 200 graphemes or 800 bytes | `Emnet kan være opptil 200 tegn eller 800 byte` |
| text | CRLF and CR become LF; then a control character other than TAB and LF | `Meldingsteksten inneholder et kontrolltegn som ikke er tillatt` |
| text | empty after NFC and trimming | `Emne og meldingstekst må fylles ut` |
| text | over 4000 graphemes or 16 000 bytes | `Meldingsteksten kan være opptil 4000 tegn eller 16 000 byte` |

HTML in copy is escaped, never interpreted.

#### 4.4 The snapshot hash

`snapshot_hash` is the lower-case hex SHA-256 of the canonical JSON (sorted
keys, no whitespace, UTF-8) of `{template, version, recipient, sender,
subject, body, order_revision, customer_revision}`; the subject already
carries ` [ref:…]`. `messages_send` renders again and compares: a different
hash is `conflict` `Forhåndsvisningen er utdatert. Åpne en ny forhåndsvisning
før du sender.` and nothing is stored. A preview for an actor who is not
admin masks the quote's access code (orders README §6.6) and carries the hash of
the complete snapshot, so an employee's and an admin's previews agree.

### 5. Messages and deliveries

#### 5.1 Message

`message = {"id","order_id","customer_id","template","version","kind","subject","body","html","recipient":{"name","email"},"sender":{"name","email","reply_to"},"scheduled_at","sent_at","status","delivery","employee_id","request_id","created_at"}`.
`kind` is `utgående` for the module's own rows; inbound items in the
history are `innkommende` (§11). `status` is `sendt` from the moment the
message is handed to the outbox (`planlagt` is for a message created ahead
of its send time); `sent_at` is the time it was queued. `delivery` is the
message's delivery (§5.2) or null. A message is stored once, rendered, and
never rendered again: later changes to the order, the customer or a setting
do not touch it. For an actor who is not admin every projection masks
quote access codes.

#### 5.2 Delivery

`delivery = {"id","message_id","status","attempt_count","transition_version","idempotency_key","provider","provider_message_id","error_code","safe_error_message","queued_at","sending_started_at","accepted_at","failed_at","resolved_by","resolution_note","job_id"}`.
One per message. `job_id` is the `send_delivery` job that makes its call
(§7). Delivery rows keep their statuses and times when a customer is
erased.

#### 5.3 The idempotency key

`idempotency_key` is `<template>:<order or customer id>:<workflow key or
snapshot_hash>`. A second send with the same key returns the first message
unchanged (`messages_send`) or does nothing more (a workflow).

#### 5.4 Sending from code

`send-message` (the port adapter, §1) renders the template for the order
or customer and queues it under the key of §5.3, using the running
workflow's key (or its id) when a workflow sends. A `marketing` template
for a customer who may not get marketing sends nothing; inside a workflow
run it notes `kunden har ikke samtykket til markedsføring` on the run.

#### 5.5 Staff messages

Called with `employee_id`, `send-message` renders a code template and
hands it at once to the message transport (`message-transport`; the fake
marks it `sendt`). This is the older path the warehouse alert uses. The
staff recipient is stored as plain actor text (`admin:lager`), the way
older deployments wrote it, and read back unchanged.

### 6. Delivery states

| From | To | By | When |
|---|---|---|---|
| — | `queued` | the send, in its transaction | |
| `queued` | `failed` (`suppressed`) | the claim | the customer is gone or erased, or a `marketing` template's customer withdrew consent (§9) |
| `queued` | `sending` | the claim | `attempt_count` + 1, `sending_started_at`, the watchdog scheduled (§10) |
| `sending` | `accepted` | the worker | the provider accepted; `provider`, `provider_message_id`, `accepted_at` |
| `sending` | `failed` | the worker | a deterministic refusal; `error_code`, `safe_error_message`, `failed_at` |
| `sending` | `outcome_unknown` | the worker, the watchdog, the start | an ambiguous error, a crash or timeout in the call, or a process gone mid-call |
| `outcome_unknown` | `accepted` or `failed` | `messages_resolve` | a person's decision |

Every transition bumps `transition_version`. `accepted` and `failed` are
final. Exactly one provider call per delivery, ever: nothing calls again
after a claim.

### 7. The outbox

Each delivery has a job, `send_delivery`, in the `:outbox` queue
(spec/jobs.md): outside a transaction, one attempt, failed (not retried)
after a crash, unique per delivery. The job decides when the worker runs;
the claim decides whether it calls the provider.

1. The job runs only while the tenant has fewer than four live provider
   calls (abandoned ones included) and the outbox is not busy with another
   delivery; otherwise it snoozes and runs again. Claims and calls run one
   at a time per tenant.
2. The claim, in one write transaction: the delivery must still be
   `queued`; erasure and marketing consent are checked again and a
   suppressed delivery fails (§9); otherwise it becomes `sending`.
3. The provider call runs outside every transaction and request, as
   `system:outbox`, with a deadline of 10 s (4 s in test mode). Passing the
   deadline is `outcome_unknown` `timeout`; the call is abandoned and the
   worker moves on.
4. The outcome is written in a new transaction, only while the delivery is
   still `sending` with the claim's `transition_version`.

In test mode the outbox drains right after the request that queued a
delivery commits, before the next request; a server's job workers do it in
normal mode. Shutdown stops new claims and abandons waiting calls.

### 8. The provider port and the fake adapter

#### 8.1 The port

`deliver-snapshot(adapter, request, mode, call-number)` with
`request = {"message_id","delivery_id","from","reply_to","to","subject","text","html","headers":{"X-Tun-Message-Id"}}`
answers a status (`accepted`, `failed` or `outcome_unknown`), an error code
and the provider's message id. Only these safe classifications leave the
adapter; raw provider errors are never stored or returned. The application's
`message-transport` is the adapter; the fake is the default. A real adapter
lives behind the same port with its credentials outside the application.

#### 8.2 The fake's modes

`messaging_provider_set {"mode"}` (update, admin, test mode only) sets the
mode for the calls that follow; it persists. `messaging_provider_get {}`
(read, admin) answers `{"mode","calls"}`, `calls` counting provider calls.

| Mode | Behaviour | Status, `error_code` |
|---|---|---|
| `accept` (default) | accepts; `provider_message_id` `fake-<n>` | `accepted` |
| `reject` | refuses | `failed`, `provider_rejected` |
| `unauthorized` | refuses | `failed`, `provider_unauthorized` |
| `disabled` | refuses | `failed`, `provider_disabled` |
| `rate_limited` | ambiguous | `outcome_unknown`, `rate_limited` |
| `transport` | ambiguous | `outcome_unknown`, `transport` |
| `timeout` | sleeps past the deadline | `outcome_unknown`, `timeout` |
| `crash` | signals an error | `outcome_unknown`, `unknown_provider_outcome` |
| `slow` | accepts after 3 s | `accepted` |

In test mode the hidden mode `sleep_ok` (accepted by
`messaging_provider_set`, absent from its schema) sleeps 11 s and then
accepts, so a test can show the deadline at work.

#### 8.3 Safe error messages

| `error_code` | `safe_error_message` |
|---|---|
| `suppressed` | `Meldingen ble ikke sendt: kunden har trukket samtykket eller er slettet.` |
| `provider_disabled` | `E-postlevering er deaktivert. Meldingen ble ikke sendt.` |
| `provider_rejected` | `E-postleverandøren avviste meldingen. Kontroller mottaker og innhold.` |
| `provider_unauthorized` | `E-postleverandøren avviste tilgangen. Meldingen ble ikke sendt.` |
| `invalid_message` | `Meldingssnapshotet er ugyldig og ble ikke sendt.` |
| `rate_limited` | `E-postleverandøren ba oss vente. Utfallet må avklares før nytt forsøk.` |
| `timeout` | `E-postleveringen fikk tidsavbrudd. Utfallet er ukjent og må gjennomgås.` |
| `transport` | `Forbindelsen til e-postleverandøren brøt. Utfallet er ukjent og må gjennomgås.` |
| `unknown_provider_outcome` | `E-postleverandørens utfall er ukjent. Ingen automatisk retry utføres.` |

### 9. The consent guard and the failure notice

A `marketing` template never reaches a customer who has not consented or
is erased (customers README §4), by any path: a manual send is refused
(§4.2), a send from code sends nothing (§5.4), and the claim checks again
(§7), so consent withdrawn while a message waits still stops it. A
suppressed delivery fails with `suppressed`, is audited as
`outbox.suppressed` by `system:outbox`, and makes no provider call and no
notification. The guard is this module's, not the client's.

A delivery reaching `failed` (other than `suppressed`) or `outcome_unknown`
publishes the notification `leveranse_feilet` to the admins:
`En e-post til <recipient name> kunne ikke sendes.`, linking to
`/orders/<id>` or `/customers/<id>` (notifications README §3).

### 10. Watchdog, restart and resolution

The claim schedules the workflow `leveranse_vakt` due 300 s later, keyed
`<delivery id>:<attempt>`. It marks a delivery still `sending` with that
attempt `outcome_unknown` (`unknown_provider_outcome`), never calls the
provider, and does nothing otherwise.

When the module opens, before serving, every `sending` delivery whose job is
not running in a live process becomes `outcome_unknown`
(`unknown_provider_outcome`): a crashed or stopped process's, never the
other process's during a blue/green switch (spec/jobs.md §7). Every
`queued` delivery gets its job; the job is unique, so one that has a job
keeps it.

`messages_resolve {"id","outcome","note"}` (update, admin): `outcome` is
`accepted` or `failed`, `note` 1–2000 characters. Only from
`outcome_unknown`, else `invalid_transition` `Leveransen kan ikke avklares`.
It sets `resolved_by`, `resolution_note` and `accepted_at` or `failed_at`.

### 11. History

| Tool | Kind | Input | Result |
|---|---|---|---|
| `messages_list` | read | `{"order_id"?,"customer_id"?,"template"?,"kind"?,"limit"?=20}` | `{"items"}`, oldest first, at most 100 |
| `messages_get` | read | `{"id"}` | a message, or an inbound item by its henvendelse id; else `not_found` `Meldingen finnes ikke` |

The history of an order is every outbound message about it and every
inbound henvendelse threaded to it (inbox README §9): `kind:
"innkommende"`, `henvendelse_id`, `status: "mottatt"`, `template: null`,
`delivery: null`. The history of a customer is both directions over every
order. Items sort by `scheduled_at` (an inbound item's is its time of
receipt). A `template` filter or `kind: "utgående"` leaves inbound items out;
`kind: "innkommende"` leaves outbound out.

The order's `communication` summary (an orders seam) gains `outbound`,
`failed` (deliveries `failed` or `outcome_unknown`) and `last_outbound_at`.

### 12. Erasure

On `customer_erasing` (customers README §5) every message of the customer
gets `[slettet]` for the recipient's name and email, the subject, the body
and the HTML, and the stored results of its receipts are redacted. The
delivery rows keep their statuses. When the module opens it redacts the
receipts of messages of customers erased before.

### 13. Screens

- The order page gets a section «Kommunikasjon» (spec/ui.md): the order's
  open questions, then its newest 100 messages, newest first, each with
  subject, recipient, the safe error message when any, the text, and its
  label: `Lagt i kø`, `Sender`, `Akseptert av e-postleverandør`, `Kunne ikke
  sendes`, `Ukjent leveringsutfall`, `Mottatt` (inbound), and `Avklart` when
  resolved. An admin gets the resolve form on an `outcome_unknown` row.
- Employees get a composer: a manual template, `Forhåndsvis melding`; admins
  also an `ordremelding` with `Emne` and `Melding`, `Forhåndsvis
  ordremelding`. The preview page shows the message and `Bekreft og legg i
  kø`. The forms post to `/messages/preview`, `/messages/send` and
  `/messages/resolve`, which call the same tools; the stale-preview
  conflict of §4.4 shows on the page.

### 14. Invariants

1. A message is rendered and stored once and never rendered again.
2. A stale `snapshot_hash` stores nothing; the same `request_key` returns
   the same message; the same idempotency key never yields two messages.
3. One provider call per delivery in every mode, a crash, a timeout, a
   restart during `sending` and the watchdog included.
4. Every delivery ends `accepted`, `failed` or `outcome_unknown`, and only
   a person moves `outcome_unknown` on.
5. A slow or timed-out provider does not delay other requests:
   `messages_send` returns before the provider is called.
6. Raw provider errors never leave the adapter: only §8.3's codes and texts.
7. A `marketing` template is never sent without consent, by any path.
