# Client definition API

Client packages use `CL` and `TUN`. Each module publishes its supported
symbols into `TUN`; dependencies belong in the client's ASDF system and
application manifest. Definition metadata records the owning module and source
location. Define features as mixin classes and include them in
`define-application`. Never read a module's private tables or internals.

`tun new NAME MODULE...` creates a client repository in this shape, and
`tun add MODULE` enables another module in it later, and `tun update`
moves it to a newer Tun (`spec/cli.md`). `tun
list MODULE` shows what a module defines: its entities, operations, screens
and extension points. Its `deploy.nix` names the servers nixploy deploys it
to (`spec/deploy.md`).

## Entities and client storage

`define-entity name (options) (fields)` defines a stored entity, or an
embedded entity with `:embedded t`. Field options include `:type`, `:required`,
`:initform`, `:input`, `:label`, and `:description`. JSON uses snake_case names.

```lisp
(define-entity request-note (:id-prefix "rnt" :label "Request note")
  ((order-id :type (id order) :required t)
   (text :type (string :min 1 :max 500) :required t)))

(define-operation request-notes-create ((:draft request-note))
    (:entity request-note :kind :create :policy :employee)
  (insert request-note))
```

`insert`, `save`, `fetch`, `fetch!`, `select` and `select-one` work inside an
operation's transaction. An operation returns a record, or a JSON object
built with `jobj` and `jarr`; `entity->json` gives a record as callers see
it, for a result that holds several, such as `(jobj "items" (jarr (mapcar
#'entity->json records)))`. Clients can store their own entities and update their
own extension fields. They cannot change module-owned fields through these
functions. Use the owning module's operation to change its entity.

```lisp
(extend-entity customer (:name customer-details)
  ((organisation :type (string :max 120) :label "Organisation")))
```

## Queries

A read that `select` cannot express, such as a join, a count or a group,
is SQL in a `define-query` (`spec/store.md` §5). It defines a function
with keyword arguments that returns records, or JSON objects for
`(:rows ...)`. Write `{entity}` for an entity's table and `:name` for a
parameter; columns have the fields' snake_case names. The server runs
every query once at start, so a renamed field stops the start with the
query's name. Queries only read: changes go through `insert`, `save` and
operations.

```lisp
(define-query notes-per-order ()
    (:returns (:rows (order-id :type (id order)) (notes :type integer)))
  "SELECT order_id, count(*) AS notes FROM {request-note} GROUP BY order_id")

(define-query recent-notes ((order-id :type (id order) :required t))
    (:returns request-note)
  "SELECT n.* FROM {request-note} n WHERE n.order_id = :order_id ORDER BY n.seq DESC")
```

## Record policies

An operation's `:policy` says who may call it; an entity's
`:record-policy` says which of its records each role reads and writes
(`spec/store.md` §6). A clause per role is `t` for every record or an SQL
condition on one record: its columns by name, `this` for the record
inside a subquery, and `:actor_name` for the caller's name. A role without
a clause reaches nothing. `fetch`, `select` and `{entity}` in a query see
only admitted records; anything else is not found. A write the condition
does not admit, such as an item authored by someone else, is `forbidden`.

```lisp
(define-entity item (:id-prefix "itm" :label "Sak"
                     :record-policy ((:admin t)
                                     (:employee "author = :actor_name")))
  ((title :type (string :min 1 :max 200) :required t)
   (author :type (string :max 64) :input nil)))

(define-operation items-create ((:draft item))
    (:entity item :kind :create :policy :employee)
  (setf (item-author item) (actor-name *actor*))
  (insert item))
```

Code that must reach records the caller cannot, such as a notice for an
admin, runs as the system: `(with-actor ((system-actor "items")) ...)`.

## Operations, rules, computed fields and hooks

`define-operation name (parameters) (options) body` declares input schemas,
authorization, transactions and audit behavior. `:required t` validates a
parameter; `:default` supplies an omitted value; `:secret t` marks one that
carries a credential, which a request's record shows as `"***"`. `:confirm t` requires the
kernel's confirmation round trip. `:kind :read` selects a read transaction;
mutating kinds are `:create`, `:update`, and `:transition`; `:kind :wait`
reads until something changes (below). `request_key` is provided by the
kernel. `invoke` calls an operation within the same request. A
parameter's and a field's `:label` and `:description` are strings written
out: the specs are data, not evaluated, so a constant's name there is
refused when the definition is compiled.

```lisp
(define-operation request-notes-get ((id :type (id request-note) :required t))
    (:entity request-note :kind :read :policy :employee)
  (fetch! 'request-note id))

(define-rule organisation-required (customer c)
    (:field "organisation" :message "Company customers need an organisation")
  (or (not (equal (customer-kind c) "bedrift"))
      (not (blank-p (customer-organisation c)))))

(define-computed-field customer label (c) (:type string :label "Label")
  (customer-name c))

(defclass request-note-feature () ())
(defmethod orders-confirm :after ((app request-note-feature) input)
  (declare (ignore input))
  (let ((order (operation-result)))
    (insert (make-instance 'request-note :order-id (entity-id order)
                          :text "Confirmed"))))
```

Rules return true to accept and false to reject. Computed fields are evaluated
when reading the entity and declare their result type. The operation result in
an after hook is a guarded copy: call public operations for module-owned writes.
Before hooks can refuse the operation using `reject` or `fail`; an exception
rolls back the whole transaction, including all hook effects.

## Waiting for a person

An agent's call can wait for what a person does in the UI, such as
answering its question, and get it in the same call (`spec/waiting.md`).
The operation is `:kind :wait`; its body runs outside a transaction, and
`await` looks again after every commit until the value is what it waits
for, or the time is up (at most 600 seconds). It returns the last value
and whether it came.

```lisp
(define-operation questions-wait ((id :type (id question) :required t)
                                  (seconds :type (integer :min 1 :max 600) :default 120))
    (:kind :wait :entity question :policy :employee :title "Vent på svar")
  (await (:seconds seconds :until #'question-answered-at)
    (fetch! 'question id)))
```

Over MCP a wait longer than 25 seconds is answered as an SSE stream with
progress every 25 seconds, so Claude Code's idle timeout and a proxy do not
cut it; over `/api` and for a client that takes only JSON a wait lasts at
most 90 seconds, and the caller calls again. `(:instructions "…")` in
`define-application` tells agents, in MCP's `initialize`, how the client's
tools are meant to be used together.

## Seams

Each seam is a generic function with a documented contract. Specialize on a
client feature class and the declared arguments. `register-extension-protocol`
records the seam for `introspect_extensions`; clients specialize published seams
rather than registering a second implementation under the same name.

```lisp
(defmethod order-discount ((app request-note-feature) order customer)
  (declare (ignore customer))
  (round (* (order-subtotal-ore order) 1/20)))
```

Use `call-next-method` when augmenting a seam's default behavior. Returning a
replacement result is appropriate for seams such as `order-discount`.

## Templates and workflows

A template takes keyword context and returns subject and body strings. A client
may replace a module's non-final template with the same template key.

```lisp
(define-message-template company-quote (:template "tilbud" :label "Quote")
    (&key order customer)
  (values "Your offer" (format nil "Hello ~a, order ~a."
                              (customer-name customer) (entity-id order))))

(define-workflow note-reminder (:kind "note_reminder" :label "Reminder"
                                :templates ("tilbud")) (wf)
  (let ((order (find-order (workflow-order-id wf))))
    (send-message "tilbud" :order order :customer (order-customer order))))
```

`schedule-workflow` accepts `:order`, or opaque `:order-id`/`:subject-id`, and
`:due-at` in universal time. The engine records its own request and executes as
`system:workflow`. `pending-workflows` and `cancel-workflows` accept an order id
and optional `:kinds`. A workflow kind has exactly one handler. Declare the
`:templates` it may send so `introspect_workflows` can explain them without
running the handler.

## Screens and application manifests

Screens return structured HTML through the public renderer. See
`tests/client/screens.lisp` for the complete order-screen signature and the
list-screen example. Keep user text
in escaped nodes rather than raw HTML strings.

A screen is rendered inside the page's design-system frame (`spec/ui.md`),
whose stylesheet resets bare elements: a `<p>` reads as text, but a bare
`<table>`, `<button>` or `<input>` has no look of its own. Build tables and
sections with `json-table` and `section`, which draw the design system's
table and section, and reuse the generated record with `call-next-method` or
`entity-detail`. `json-table` takes JSON objects whose keys are the column
headings; with `:link` each row leads to a page.

```lisp
(defmethod render-screen ((app request-note-feature) (screen (eql :customer-list)) &key items)
  (declare (ignore items))
  (call-next-method))

(define-application notes-client (request-note-feature)
  (:modules customers catalog inventory reviews orders messaging staffing)
  (:default-initargs :name "Notes client"))
```

## Pages

A client's own pages are built from the design system's components in
`TUN.UI`, which the client's package names `ui` (`(:local-nicknames (#:ui
#:tun.ui))`; `tun new` writes it), and defined with `define-page`
(`spec/ui.md` §8). A page serves its prefix and the paths under it, is in
the menu, and calls operations with `web-call`, as the logged-in person,
so the operations' policies, record policies and audit apply. It returns
its status, title and components, or `(values 303 PATH)` after a post.
`/ui` shows every component with its options.

```lisp
(define-page notes-page ("notater" :title "Notater" :icon :file-text)
    (method path form query)
  (declare (ignore path query))
  (if (eq method :post)
      (multiple-value-bind (note code) (web-call "request_notes_create" form)
        (if code
            (values 422 "Notater" (list (error-alert note)))
            (values 303 "/notater")))
      (values 200 "Notater"
              (list (ui:card (:title "Nytt notat")
                      `(:form (:@ :method "post" :action "/notater")
                              ,(ui:textarea (:label "Tekst" :name "text"))
                              ,(ui:button (:type "submit") "Lagre")))))))
```

### Pages with htmx

Every page loads htmx 4, and a staff page's links and forms go through it
(`hx-boost`), so moving between pages swaps the body without a full
load and works as before without JavaScript (`spec/ui.md` §4.1). For a
part of a page, mark up an ordinary form or link with `hx-post`,
`hx-target` and `hx-swap` (in a component's `:attributes` or on a page's
own elements), and answer an htmx request with that part alone:

```lisp
(define-page items-page ("saker" :title "Saker" :icon :list-todo)
    (method path form query)
  (cond ((and (eq method :post) (equal path '("flytt")))
         (web-call "items_move" (jobj "id" (jget form "card") "status" (jget form "column")))
         (if (htmx-request-p)
             (values 200 :fragment (list (items-board)))   ; the board alone
             (values 303 "/saker")))                       ; the plain form
        (t (values 200 "Saker" (list (items-board))))))
```

htmx 4 inherits an attribute only when it says so (`hx-target:inherited`
on a container), names its events with colons (`htmx:after:swap`), and
runs no JavaScript from markup on a Tun page: `hx-on` does nothing. A
page's own script belongs in a component's `:script`.
`(values 303 PATH)` to htmx becomes `HX-Location`, and a fourth value
`(:trigger "name")` sends `HX-Trigger`. `ui:board` (`spec/ui.md` §6.1)
is a board of cards in columns whose cards move by a «Flytt til» menu or
by dragging, posting `card` and `column` to its `:action`. A page under
«System» in the menu, rather than with the business's work, is defined
with `:group :system`.

With `:ordered t`, a person also sets the order of the cards within a
column: by dragging a card between two others, or with «Flytt opp» and
the rest of «Rekkefølge» in its menu. Every post then carries `before`
too, the id of the card it now sits directly above in `column`, or empty
for the end. The page stores the order. Give the entity a field for a
rank key, and `rank-between` (`spec/core.md` §2.6) a key between the
two neighbours; moving a card changes only its own key:

```lisp
(define-entity item (:id-prefix "itm" :label "Sak")
  ((title :type (string :min 1 :max 200) :required t :label "Tittel")
   (status :type (enum "ny" "planlagt" "ferdig") :initform "ny" :label "Status")
   (place :type string :input nil :label "Plass")))   ; a rank key

(defun column-items (status)
  (select 'item :where `(:= "status" ,status) :order-by '(("place" :asc))))

(defun place-before (item status before)
  "A key putting ITEM in STATUS directly above the item BEFORE, or last."
  (let* ((others (remove (entity-id item) (column-items status)
                         :key #'entity-id :test #'equal))
         (below (when before (member before others :key #'entity-id :test #'equal)))
         (above (car (last (ldiff others below)))))
    (when (and before (null below))
      (fail :conflict "Tavla er endret. Last den inn på nytt."))
    (rank-between (and above (item-place above)) (and below (item-place (first below))))))
```

The move operation sets `(item-place item)` to `(place-before item status
before)` before it saves, and creating an item puts it last with
`(place-before item status nil)`. Every item in the set needs a key:
items made before the field existed get theirs in their current order,
each `(rank-between previous nil)`. Keys sort by code point in every
store, so a query orders by the field as `select` does:

```lisp
(define-query next-items ((status :required t))
    (:returns item)
  "SELECT * FROM {item} WHERE status = :status ORDER BY place LIMIT 5")
```

A link on a staff page loads its page in the background when a person
rests the pointer on it or presses it, so the click shows the page at
once (`spec/ui.md` §4.1). Such a request carries `Tun-Preload: true`, and
`(preload-request-p)` is true while a page answers it. A page records
nothing for a preload: one that records something for a GET (a «sett»
mark) returns `(decline-preload)` then, and the click asks again. A link
that acts on a GET is marked `data-tun-preload="off"`, or put inside an
element so marked.

A list a person filters keeps its filters when they leave it and come
back, on any device, with `:remembers`, the query keys to keep for each
account: opened without any of them, the page goes to the address with
what the person last chose (`spec/ui.md` §8). A link that clears the
filters names one of the keys, empty.

```lisp
(define-page items-page ("saker" :title "Saker" :icon :list-todo
                                 :remembers '("prosjekt" "status" "sort"))
    (method path form query)
  ...)
```

### Installing as an app

`(:web-app ...)` in `define-application` lets people install the client
on a phone or a computer, as an app with its own icon and window
(`spec/ui.md` §4.2). `:icons` names a directory beside the file that
holds `define-application`, with `icon.svg`, `icon-192.png`,
`icon-512.png`, `icon-maskable-512.png` (its content inside the middle
80 %) and `apple-touch-icon.png` (180×180). They are read when the
file is compiled, so the compiled client holds them; the build's sources
must include the directory, as `tun new`'s flake does for `icons/`. The rest is
optional: the name under the icon (at most 12 characters; the title by
default), the browser's bar in light and dark mode, and the start
screen's colour.

```lisp
(define-application notes-client ()
  (:web-app :short-name "Notater" :theme-color "#ffffff" :dark-theme-color "#0a0a0a"
            :background-color "#ffffff" :icons "icons/")
  (:default-initargs :name "Notater for Fjord AS"))
```

Tun then serves `/manifest.webmanifest`, the icons and a service worker
at `/sw.js`, which keeps the stylesheet and scripts and shows «Du er
frakoblet» when a page cannot be fetched. It never keeps a page or an
answer from `/api` or `/mcp`. After changing an icon, recompile the
file with `define-application` (`C-c C-k`, or touch it) for the new one
to be served.

### Notifications on people's phones

An installable client can notify people on the devices where they have
turned notifications on (`spec/push.md`). Put `ui:push-switch` on a page
of the client's choosing, such as a person's own settings: it turns
notifications on and off for the device it is shown on, says what to do
where they cannot work (on an iPhone, the app must be on the Home Screen
first), and offers a test notification. Then, inside an operation, a job
or a workflow, send to a person by their account's name:

```lisp
(notify-push "kari" :title "Ny sak til deg"
                    :body "Eksporten feiler for Fjord AS"
                    :url "/saker/itm_12"
                    :tag "sak:itm_12")
```

It returns how many devices it queued the notification for, and queues
nothing when the operation rolls back. URL is a path on the server, the
page a click opens; a later notification with the same TAG replaces this
one on the device. Each device's notification is a job in the `:push`
queue, retried as mail is; a device that is gone is forgotten. Tun makes
and keeps its own key; there is nothing to configure. A deployed tenant
needs an `https` `PUBLIC_URL`, which Apple's push service asks for.

### Files on a record

A record takes files, such as screenshots on an issue, when its entity
says so (`spec/files.md`): `:attachments t`, or `(:max 20 :policy
:admin)` for at most 20 files that only admins add. Tun stores them in the
tenant's database with the record, decides each file's type from its
bytes (PNG, JPEG, WebP, GIF or PDF, up to 10 MB), takes out what a photo
says about where it was taken, and serves a file only to those who may
see its record. An operation takes files through a parameter of type
`files` and attaches them in its own transaction:

```lisp
(define-entity item (:id-prefix "itm" :label "Sak" :attachments t)
  ((title :type (string :min 1 :max 200) :required t :label "Tittel")))

(define-operation items-create ((:draft item)
                                (screenshots :type (files :max 5) :label "Skjermbilder"))
    (:entity item :kind :create :policy :employee :title "Meld en sak")
  (insert item)
  (attach-files item screenshots)
  item)
```

An agent sends each file as `{"filename", "data"}`, base64, and adds files
to a record later with `attachments_add`; `attachments_list` lists them and
`attachments_remove` removes one (its attacher or an admin). On a page,
`ui:file-input` in a form with `:enctype "multipart/form-data"` lets a
person choose, drop or paste files; the posted FORM holds them under the
field's name, ready for `web-call`. `ui:attachments` shows a record's
files from `attachments_list` as thumbnails that open the whole image:

```lisp
(ui:file-input (:label "Skjermbilder" :name "filer"))
(web-call "items_create" (jobj "title" (jget form "title") "screenshots" (jget form "filer")))
(ui:attachments (:items (jget (web-call "attachments_list"
                                        (jobj "entity" "item" "record_id" id))
                              "items")))
```

## The HTTP API

Another system calls a tool with one request, `POST /api/TOOL`, its body
the arguments as JSON and `Authorization: Bearer tun_…` an agent
account's token, and gets the tool's result, or the error document with
an HTTP status by its code (`spec/api.md`). It is the same execution
path as MCP: policy, `request_key`, audit.

```
curl -X POST https://tracker.example.no/api/items_create \
  -H 'Authorization: Bearer tun_…' -H 'Content-Type: application/json' \
  -d '{"title": "Eksporten feiler", "request_key": "erp-4711"}'
```

## Signing in

`(:sign-in strategy...)` in `define-application` lists how people log in
(`spec/auth.md` 3.4, 3.5): `(:workos ...)`, `(:google ...)`, or any
OpenID Connect provider with `(:oidc ...)`. Tun keeps no passwords, so an
authenticated server needs at least one. A setting is a string or `(:env
"NAME")`, read when the server starts; keep client secrets in the
deployment's SOPS file, never in the repository.

WorkOS AuthKit is the usual choice: its page signs people in with Google,
Microsoft, email, passkeys or their company's single sign-on, as its
dashboard allows, so Tun has one button, «Logg inn».

```lisp
(define-application notes-client ()
  (:modules customers)
  (:sign-in (:workos :domain (:env "WORKOS_DOMAIN")
                     :client-id (:env "WORKOS_CLIENT_ID")
                     :client-secret (:env "WORKOS_CLIENT_SECRET"))))
```

A provider proves an email address and nothing more: an admin creates the
person's account with that email, and their first sign-in links it. In
the WorkOS dashboard, make a first-party OAuth application (Connect →
OAuth applications) with `PUBLIC_URL/auth/workos/callback` as its
redirect URI; `WORKOS_DOMAIN` is the environment's AuthKit domain, such
as `acme.authkit.app`. For Google directly, make an OAuth client of the
type web application in Google Cloud Console, with
`PUBLIC_URL/auth/google/callback` as an authorized redirect URI.

With WorkOS, MCP clients that speak OAuth, such as Claude Code, connect as
the person without an access token: `claude mcp add --transport http NAME
PUBLIC_URL/mcp`, and the person signs in through AuthKit
(`spec/auth.md` §5.1). In the dashboard, turn on Client ID Metadata
Documents and Dynamic Client Registration (Connect → Configuration) and
add `PUBLIC_URL/mcp` as a Resource Indicator.
A server refuses to start when a setting is missing, so locally either
export the variables and add `http://localhost:8080/auth/NAME/callback`
as a second redirect URI, or run `bin/serve --claimed-identity`, which
needs no provider.

A client that lets an admin add people its own way creates the account
through the core operation, so its checks and audit apply, and with
`"invite" t` the person is mailed how to sign in (`spec/auth.md` §3.6):

```lisp
(invoke 'accounts-create "name" "kari" "kind" "person" "role" "employee"
                         "email" "kari@example.no" "invite" t)
```

`accounts_invite` with the account's `id` mails the invitation again, for
a person created without one; the account's `invited_at` says when the
last went, and another within five minutes is refused with `conflict`.
`(account-welcomed-p NAME)` is true once a person has been invited or has
signed in; a client mails people about its work only then.
`(actor-account-kind *actor*)` tells whether the caller acts for a person
(`:person`), an agent such as another system's integration (`:agent`),
or no account (NIL).

## Sending mail

`(send-mail :to :subject :text)`, inside an operation, queues a mail in the
operation's transaction: it exists only if the operation commits, and is
sent after (`spec/mail.md`). `:html` and `:reply-to` are optional. `:key`
sends once only: a second `send-mail` with the same key returns the first
mail, so a notification can be sent again harmlessly.

```lisp
(define-operation notes-share ((note-id :type (id note) :required t :label "Notat")
                               (email :type email :required t :label "E-post"))
    (:entity note :kind :update :policy :employee :title "Del notat")
  (let ((note (fetch! 'note note-id)))
    (send-mail :to email
               :subject (format nil "~a delte et notat med deg" (actor-name *actor*))
               :text (note-text note)
               :key (format nil "share:~a:~a" note-id email))
    note))
```

To mail someone with an account, ask for their address by the account's
name: `(account-address name)` is the email of an active person, else
NIL, and `(account-names :role :admin)` lists the active people with a
role (`spec/auth.md` §2). `(absolute-url "/saker/sak_1")` is the link at
the server's public URL, for the mail's text; without `PUBLIC_URL` it is
the path alone.

```lisp
(dolist (name (account-names :role :admin))
  (let ((address (account-address name)))
    (when address
      (send-mail :to address
                 :subject (format nil "Nytt notat fra ~a" (actor-name *actor*))
                 :text (format nil "Les det: ~a" (absolute-url (format nil "/notater/~a" note-id)))
                 :key (format nil "new:~a:~a" note-id name)))))
```

`(:mail provider)` in `define-application` names who delivers it:

```lisp
(define-application notes-client ()
  (:mail (:resend :api-key (:env "RESEND_API_KEY")
                  :from (:env "MAIL_FROM"))))
```

Without it, and in tests, mail is recorded and logged but not sent. Resend
sends only from a domain verified in its dashboard; `:from` is such as
`Notater <varsel@example.no>`. A server refuses to start when the key is
missing, unless it runs with `--claimed-identity`. Admins see what was
sent, and why a mail failed, with `mail_list` and `mail_get`, and send a
failed one again with `mail_retry`.

## Calling other systems

`(http-json-post url body :headers ... :timeout ...)` posts a JSON body to
another system's API and returns its JSON answer, and the status as a
second value (`spec/outbound.md`). A call that gets no answer within its
timeout (10 seconds, and never past the operation's deadline less one
second), fails to connect, or answers outside 200 to 299 signals
`remote-failure`, an operation error with code `unavailable`.
`remote-failure-status` (NIL without an answer) tells a refusal from the
other system's own failure, and `remote-failure-body` holds what it said.
Call from a `:read` or `:wait` operation: in a write, the call holds the
store's single writer while it waits.

Its key comes from the environment, through a setting declared with `:env`
(see Declared settings):

```lisp
(define-setting "typesafe.api_key"
    (:type "secret" :env "TYPESAFE_API_KEY"
     :description "Nøkkelen til TypeSafe. Uten den sjekkes ikke saker før de meldes."))

(define-operation items-check ((title :type (string :max 200) :required t :label "Tittel"))
    (:kind :read :entity item :policy :employee :title "Sjekk en sak")
  (let ((key (setting-value-at-use "typesafe.api_key")))
    (if (null key)
        (jobj "checked" nil)
        (handler-case
            (http-json-post "https://api.typesafe.ai/v1/systemone" (jobj "input" title)
                            :headers `(("Authorization" . ,(format nil "Bearer ~a" key))))
          (remote-failure () (jobj "checked" nil))))))
```

Each call is a step in the request's trace, with the URL but not its query,
headers or body. A test answers for the other system by binding
`*http-json-handler*` to a function of the URL, the body and the headers
that returns a status and an answer:

```lisp
(let ((*http-json-handler* (lambda (url body headers)
                             (declare (ignore url headers))
                             (values 200 (jobj "kind" "feil" "echo" (jget body "input"))))))
  (invoke 'items-check :title "Knappen virker ikke"))
```

## Background jobs

Work that should happen later, again when it fails, or out of the
request is a job (`spec/jobs.md`). `define-job` names it once, with
arguments typed as an operation's inputs; `enqueue-job`, inside an
operation, queues one in the operation's transaction, so it exists only
if the operation commits.

```lisp
(define-job remind-reporter ((item-id :type (id item) :required t))
    (:max-attempts 5 :unique (:keys (item-id)))
  (let ((item (fetch 'item item-id)))
    (unless (and item (waiting-p item))
      (cancel-job "Saken venter ikke lenger på svar"))
    (send-reminder item)))

(enqueue-job 'remind-reporter :item-id (entity-id item) :in (* 2 24 3600))
```

- A job takes ids and values, not records: read the record when the job
  runs. It runs as `system:job`, each attempt in a request of its own.
- By default the body and the job's completion commit together, so work
  that only writes records happens once. With `:transaction nil` the
  body runs outside a transaction, for calls to other systems: it may run
  again after a crash, so make it safe to repeat, and write through
  operations (`invoke`).
- A body that signals an error is retried after a growing delay, up to
  `:max-attempts` (20); `:backoff (30 120 600)` sets the delays.
  `(cancel-job reason)` ends it as no longer needed, and
  `(snooze-job seconds)` tries again later without using an attempt.
- `:unique` returns the job already waiting instead of a second one;
  `:queue` and `(:queues (:mail 1))` in `define-application` say how many
  run at once.
- `define-schedule` enqueues a job at each occurrence of a cron time, in
  Norwegian time, once whatever runs: `(define-schedule daily-summary
  "0 7 * * 1-5" send-daily-summary)`. After downtime the latest missed
  occurrence runs if it is less than a day old (`:catch-up`, or `nil`).
  `schedules_list` shows the last and next occurrence; `schedules_run`
  runs one now.
- `define-trigger` runs a job for every record that meets a condition,
  swept every minute or at `:cron`. The job is unique by its record, and
  cancels itself if the record no longer meets the condition when it
  runs. The body should make the condition false:

  ```lisp
  (define-trigger remind-reporter (item)
      (:where `(:and (:= "status" "venter_på_svar") (:null "reminded_at")
                     (:< "asked_at" ,(- (now) (* 2 86400)))))
    (send-reminder item)
    (setf (item-reminded-at item) (now))
    (save item))
  ```
- In tests, `clock_set` runs the schedules and the jobs due by the new
  time, and
  `tun.test-support` has `enqueued-jobs`, `perform-job` and `drain-jobs`.
  Admins see and retry jobs with `jobs_list`, `jobs_get`, `jobs_retry` and
  `jobs_cancel`.

## Errors and logs

A request that fails in a way its code did not mean, an unhandled
condition, a failed job attempt or a deadline, is a fault. Core keeps each
fault in the store, grouped with the others of its cause, and admins see
them with `errors_list` and `errors_get` and mark them with
`errors_set_status` (`spec/errors.md`); the `dashboard` module shows them as
«Feil». A `fail` the code meant, such as `not_found`, is an answer, not a
fault. To hear of a new error:

```lisp
(define-application notes-client ()
  (:error-mail (:env "ERROR_MAIL_TO")))
```

A server writes a JSON line per request to standard output, which
`nixploy logs` shows; `--log none` turns it off.

## Previews, scenarios and browser checks

`tun preview` runs the working tree in the background, on a port of its
own, with a fresh database, anyone's sign-in and the records of a
scenario, at a tailnet link a person opens on their phone
(`spec/preview.md`). A scenario is defined in the client's tests system,
`tests/scenarios.lisp`, through its operations as the actors named:

```lisp
(define-scenario default (:actors ("employee:anna"))
  "To kunder."
  (dolist (name '("Kari Nordmann" "Ola Nordmann"))
    (call-ok "customers_create" "employee:anna" "name" name)))
```

A test starts from one with `(run-scenario "default")` inside
`with-test-app`. A browser check is `checks/NAME.py`, with `run(t)`;
`tun check` runs each against a fresh preview of its scenario
(`SCENARIO = "NAME"`, else `default`) in Chromium:

```python
"""Anna sees both customers on her phone."""

def run(t):
    page = t.phone()
    page.sign_in("employee:anna")
    page.goto("/")
    t.check(page.get_by_text("Ola Nordmann").count() == 1, "Ola is listed")
```

From Tun's own checkout, `bin/tun preview --dir CLIENT` runs a client on
that working tree of Tun instead of its pins, to see a change to core in
the client that asked for it.

A request for a change runs the feature loop (`docs/loop.md`,
`spec/loop.md`). `tun loop verify` runs `bin/test` and the checks.
`tun loop show` puts the verified tree at a shared preview with
screenshots. Its record, `loops/NAME.md`, is committed with the change.

## Declared settings

Settings are typed declarations, separate from their durable values. A key must
have exactly one declaration. Supported types are `string`, `bool`, `int`,
`email`, `url`, `actor`, and `secret`. Defaults live in definitions; overrides
live in the tenant's store. Declare in a client source file before application
startup:

```lisp
(define-setting "notes.reminder_hours"
    (:type "int" :default 48 :min 1 :max 720 :description "Reminder delay"))

(defun reminder-delay ()
  (* 3600 (setting-value-at-use "notes.reminder_hours")))
```

Read at use time inside the operation or workflow transaction. Administrators
write through `settings_set`; employees read non-secret values with
`settings_get`. `settings_list` masks secret defaults and values. Registry
metadata has no stored values. A secret setting receives a random, durable
initial value at application startup. Nullable declarations accept JSON null.
Actor values are validated through the staffing directory.

A setting declared with `:env "NAME"` takes its value from that environment
variable, read each time it is used, and is never stored (`spec/outbound.md`
§3). It is for keys to other systems and such, kept in the deployment's SOPS
file. Its type is `string`, `secret`, `url` or `email`; unset, its value is
the default, or NIL. `settings_set` refuses it, and `settings_list` shows the
variable's name and, for a secret, `"***"` when it is set and `null` when not.

A client may supply a first-start value for a module setting without replacing
its declaration or a tenant's stored choice:

```lisp
(define-setting-initial-value "avsender.navn" "Nordvik Utleie AS")
```

Message templates may be declarative data. The version advances when a client
overrides a module template; final templates refuse an override:

```lisp
(define-message-template company-reminder
    (:template "påminnelse" :label "Reminder" :manual t :marketing nil
     :subject "A reminder" :text "Hello {{kunde.navn}}"
     :variables ("kunde.navn")) (&key order customer))
```

`messages_preview` returns a frozen copy and `snapshot_hash`; submit that hash
with `messages_send`. A changed customer, order, sender or template requires a
fresh preview. Overrides of `ordremelding` may accept edited text; only admins
send that template. Marketing templates always apply the customer's consent
guard, including when invoked by code or a workflow.

## Module API: retained trace erasure (core 1.1.6)

`(tun.core:redact-request-traces (list subject-id name email phone))` runs in a write
transaction. It removes the input, error text and step payloads of matching
retained requests, preserving identity, outcome and timings. It also fences
in-flight requests because they can still append old data. Rollback restores
prior payloads. The customers module invokes it during `customers_erase`;
clients normally use that operation. Redacted idempotency receipts also fence
future replay traces, so resubmitting old inputs cannot restore them in diagnostics.
