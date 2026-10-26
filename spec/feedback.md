# Feedback

Status: draft, 2026-10-20. Not built: it waits for files in core
(`docs/roadmap.md`, Files) and for a second client beside the tracker
it reports into. Agreed as a direction the same day; the open questions in §7
are decided when it is built.

The people using a Tun system report a problem, a wish or a question from
the page they are on, and it arrives as an item in the supplier's
tracker, a Tun system of its own, where the supplier and agents work it. It is the first case of
Tun systems working together (`docs/roadmap.md`, Connected systems): a
module in one tenant, a link to another.

## 1. The two parts

| Part | Where | Does |
|---|---|---|
| The `feedback` module | in each client that enables it | the form on every page, the stored report, its delivery and its status |
| The link | a port in the module, with a `tracker` adapter | creates the item in the tracker over its MCP tools, with a token, and reads its status back |

Each tenant keeps its own process and database (one process per tenant).
Nothing is shared between them but the link's calls, so either side can
be down, upgraded or restored alone.

## 2. Reporting

- Every staff page has «Meld fra» in its header. It opens a form: kind
  (`feil`, `ønske`, `spørsmål`), title, description, and an optional
  screenshot pasted or uploaded (PNG or JPEG, at most 5 MB).
- The report records what the person need not type: the page's path, who
  reported it (name and email), when, and the client's and Tun's
  revisions. An agent that reads the item knows which build to reproduce
  it on.
- Sending the form stores a report with status `queued` in the reporter's
  transaction and answers at once. Delivery comes after, as mail's does
  (`mail.md` §3): a worker, retries with backoff, the report's id as the
  idempotency key, `failed` after the last attempt, and the same admin
  tools to list and retry.
- «Mine meldinger» lists a person's reports with the status last read
  from the tracker.

## 3. The link to the tracker

Configured as mail's provider is, with settings from the environment:

```lisp
(:feedback (:tracker :url (:env "TRACKER_URL") :token (:env "TRACKER_TOKEN")))
```

- Without it the adapter is `(:log)`: reports are stored and logged, not
  sent. A test uses a fake.
- The token is an account in the tracker that is a person at this client's
  customer, with the `employee` role. The tracker's record policies then
  confine the app to the items it reported, as for any person.
- Delivering a report calls `items_create` with the report's fields and,
  once files exist, attaches the screenshot.
- Status comes back by reading: the module asks `items_get` for each open
  report's item now and then. The app reaches those items because it
  reported them, so the tracker needs no link back to the app.

## 4. What the tracker gains

A change to the tracker's own spec when this is built:

- `items_create` takes optional details from a connected app: the
  reporter's name and email, the page, the revisions. The item shows
  them, and the reporter is the app's account.
- Attachments on items, from files in core.
- The supplier sees which app an item came from.

## 5. Order

1. Files in core: a storage port, an attachment field type, limits.
2. The module and the tracker's side, with the second client that enables it.
3. Status read back into «Mine meldinger».
4. The general link between Tun systems (`docs/roadmap.md`, Connected
   systems), drawn out of this one once a second pair of systems needs to
   talk.

## 6. Not yet

- Capturing the screen in the browser. Pasting a screenshot is enough to
  start.
- The tracker answering inside the app: a question asked in the tracker is
  answered in the tracker, by mail notification, until people want it in the app.
- Reports from people who are not signed in.

## 7. Open questions

- A module, or core? Every client of one supplier would enable it, which
  argues for core; it carries one supplier's way of working, which
  argues for a module.
- Is `(:feedback …)` a `define-application` option like `(:mail …)`, or
  the first module setting? Modules have no settings yet.
- A screenshot can show personal data. How long the tracker keeps it, and
  whether a customer's erasure reaches it.
