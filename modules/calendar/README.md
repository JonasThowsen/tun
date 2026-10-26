# tun module `calendar`

ASDF system `tun-calendar`, package `tun.calendar`; pinned by clients through
`flake.nix` in this directory (tun-platform.md §2, §4).

- **Owns:** calendar events and the merged calendar (§2, §3 below).
- **Depends on:** `orders`, `staffing`.
- **Core range:** builds against core `>= 1.0, < 2.0` (`flake.nix` `core`,
  and `define-module` in the Lisp source; the client build and the module's
  load both refuse a core outside it, naming the constraint).
- **Publishes:** no extension points of its own; a client extends it with
  the kernel's extension kinds (core.md §1.1). Its exported symbols are its interface for
  the modules that depend on it; what clients may use is what it publishes
  to `TUN`.
- **Rollback:** its migrations only add tables and nullable columns, so the
  previous revision starts on a migrated database; whether it can also read
  every stored record is what the rollback preflight checks
  (core.md §6.4): it refuses when a record holds a value the previous
  core cannot decode (a status or price mode it lacks) or an order-line
  field its next write would drop (docs/architecture.md, "Tenants and deployment").

## Contract

Errors, policy and audit are the kernel's (core.md §3.3–§3.8). Dates are
`YYYY-MM-DD` (core.md §2.1). Order statuses, dateless orders and logistics
are the orders module's (orders README §2.1, §1.3, §4); assignments are staffing's
(staffing README §3).

### 1. What the module does

The calendar shows, for a period, the orders that occupy it and the events
staff put in it: a fair, maintenance, a site visit. Events are the module's
own records; orders are read from the orders module.

### 2. Calendar events

#### 2.1 Event

`calendar_event = {"id","title","description","start_date","end_date","order_id","created_at"}`.

| Field | Rule |
|---|---|
| `title` | 1–200 characters, required |
| `description` | at most 2000 characters |
| `start_date` | required |
| `end_date` | defaults to `start_date`; before it → `invalid_input` `Sluttdato kan ikke være før startdato` |
| `order_id` | an existing order (else `not_found`), or null |

Orders are never deleted. Cancelling an order leaves its events; an event
shows the linked order's current status (§3.2).

#### 2.2 Tools

All admin.

| Tool | Kind | Input | Result |
|---|---|---|---|
| `calendar_events_create` | create | the event's fields | event |
| `calendar_events_update` | update | `{"id", any field}` | event; fields not given are kept, a field given as null is cleared |
| `calendar_events_delete` | update | `{"id"}` | `{"deleted":true,"id"}` |
| `calendar_events_get` | read | `{"id"}` | event |
| `calendar_events_list` | read | `{"from","to"}` | `{"items"}`: events with `start_date ≤ to` and `end_date ≥ from` |

### 3. The merged calendar

#### 3.1 `calendar_list`

`{"from","to","mine"?}`, read (viewer). The period is checked first: `to`
before `from` → `invalid_input` `Til dato (<to>) er før fra dato (<from>)`;
longer than 366 days → `invalid_input` `Perioden kan være høyst 366 dager`.
The result is `{"items":[entry]}`; beyond 1000 entries it holds the first
1000 and `"truncated": true`.

The entries are:

- the calendar-active orders (`utkast`, `tilbud_sendt`, `akseptert`,
  `bekreftet`) whose dates overlap the period (`event_date ≤ to` and
  `end_date ?? event_date ≥ from`). Dateless orders never appear. `mine`
  keeps the orders the actor's employee is actively assigned to;
- for admins, the events overlapping the period; other actors get no
  events;
- nothing else. Unavailability is not on this calendar.

#### 3.2 Entries

An order entry:

```
{"kind":"order","id","start_date","end_date","title","customer_id","labels",
 "time_labels":{"start","end"},"status","department","assignees"}
```

`title` is the customer's name. `labels` are `PAKKET` when the order is
packed, the status label, then the order's tags in upper case.
`time_labels.start` and `.end` summarise the delivery and the return side
of the order's logistics. `assignees` are the names of the active
assignees (staffing README §3.1); `department` may be null.

An event entry:

```
{"kind":"event","id","start_date","end_date","title","labels":["Hendelse"],
 "description","order_id","order_status"}
```

`order_status` is the linked order's status, or null.

#### 3.3 Sort order

Entries sort by start date, then the delivery side's earliest time, then
the return side's earliest time, then creation, then id. An entry without
a delivery or return time sorts after a timed one with the same start
date; events have no times.

### 4. Invariants

1. Only calendar-active, dated orders appear; dateless orders never do.
2. Events are visible to admins only.
3. A period is at most 366 days and an answer at most 1000 entries, marked
   `truncated` when cut.
