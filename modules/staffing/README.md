# tun module `staffing`

ASDF system `tun-staffing`, package `tun.staffing`; pinned by clients through
`flake.nix` in this directory (tun-platform.md §2, §4).

- **Owns:** employees, departments, assignments, unavailability, work sessions (§2–§8 below).
- **Depends on:** `orders`.
- **Core range:** builds against core `>= 1.0, < 2.0` (`flake.nix` `core`,
  and `define-module` in the Lisp source; the client build and the module's
  load both refuse a core outside it, naming the constraint).
- **Publishes:** rule point `assignment_eligibility`, the client's departments (also to the catalog: `catalog_departments`), `to-utc` (Norwegian local time to UTC), `actor-employee` (the employee bound to an actor or its header text; the warehouse alert's recipient lookup, §2.4). Its exported symbols are its interface for
  the modules that depend on it; what clients may use is what it publishes
  to `TUN`.
- **Rollback:** its migrations only add tables and nullable columns, so the
  previous revision starts on a migrated database; whether it can also read
  every stored record is what the rollback preflight checks
  (core.md §6.4): it refuses when a record holds a value the
  previous core cannot decode (a status, price mode or movement kind it
  lacks), an order-line field its next write would drop, or a record of a
  kind the previous revision does not have
  (docs/architecture.md, "Tenants and deployment").

## Contract

Errors, policy, audit and idempotency are the kernel's (core.md §3.3–§3.8):
reads are `viewer`, mutations `employee`, and a tool marked admin below is
`admin`. Every mutation is audited and takes `request_key`. The order
statuses, the lock and the order revision are the orders module's (orders
README §2.1, §2.3, §1.2).

### 1. What the module does

Staffing records who works for the business, which department they belong
to, which orders they are assigned to, when they are not available and how
long they worked on an order. It implements three seams of the orders
module and one of the catalog:

| Seam | Module | What staffing does |
|---|---|---|
| `departments` | orders | adds the client's departments to those an order may name |
| `catalog_departments` | catalog | adds them to those a product or stock article may name |
| `department_changed` | orders | runs automatic assignment (§5) inside the order's save |
| `closure_guard` | orders | refuses closing an order while a work session on it runs (§6.3) |

It declares a setting type check: a setting of type `actor` names an
existing employee (core.md §5.3).

### 2. Employees and departments

#### 2.1 Employee

`employee = {"id","name","actor","role","department","auto_assign_in_department","active","created_at"}`.

| Field | Rule |
|---|---|
| `name` | 1–120 characters |
| `actor` | the exact actor text, `role:name` (`employee:kari`); unique |
| `role` | `viewer`, `employee` or `admin` |
| `department` | one of the client's departments (§2.2), or null |
| `auto_assign_in_department` | default false |
| `active` | default true |

An actor that does not parse as `role:name` with role `admin`, `employee`
or `viewer` is `invalid_input` `Aktør må være på formen rolle:navn (admin,
employee eller viewer)`. A second employee with the same actor is
`conflict` `Aktøren <actor> er allerede knyttet til en ansatt`.

#### 2.2 Departments

The client declares its departments with a method on the rule point
`departments` (for example `nord` and `sør`); without one there are none. A
department that is not declared is `invalid_input` `Ukjent avdeling <d>
(gyldige: …)`. Orders, products and stock articles name departments from
the same list.

#### 2.3 Tools

| Tool | Kind, policy | Input | Result |
|---|---|---|---|
| `employees_create` | create, admin | the employee's fields | employee |
| `employees_get` | read | `{"id"}` | employee |
| `employees_list` | read | `{"department"?,"active"?,"limit"?=20}` | `{"items","returned","has_more"}`, oldest first (core.md §2.4) |
| `employees_update` | update, admin | `{"id", any field}` | employee; a field given as null is cleared; changing `role`, `department`, `auto_assign_in_department` or `active` runs §5.5 |

#### 2.4 The actor's employee

"The actor's employee" is the employee whose `actor` equals the request's
actor text. `actor-employee` finds it with one indexed lookup, given an
actor or its text (such as `admin:lager`). Other modules use it instead of
paging `employees_list`: the warehouse alert finds its recipient this way,
and records a missing recipient on the workflow run. A `mine` filter
returns nothing when the actor has no employee.

### 3. Assignments

#### 3.1 Assignment

`assignment = {"id","order_id","employee_id","auto","auto_department","started_at","ended_at"}`.
An assignment is active while `ended_at` is null. Assignments are ended,
never deleted: an ended row stays and keeps its work sessions. At most one
assignment per (order, employee) is active. `auto` marks an automatic
assignment (§5) and `auto_department` the department it was made for.

Every order carries the computed field `assignments`: its active
assignments as `[{"id","employee_id","employee_name","auto"}]`.
`order-assignees` gives the names of the active assignees in assignment
order (the calendar shows them).

Creating or ending an assignment bumps the order's revision. The after
point `assignment_created` runs for every new assignment, manual or
automatic, in its transaction (the notifications module uses it).

#### 3.2 `assignments_create`

`{"order_id","employee_id","override_reason"?}`, admin. The checks, in
order:

1. The order is `avbrutt` or `fullført` → `invalid_transition` `Ordren har
   status <s>; ingen kan tildeles`.
2. The order is locked (`send_faktura`) → `conflict` with the orders
   module's lock message.
3. The employee is not active → `invalid_input` `Den ansatte er ikke aktiv`.
4. The employee is already actively assigned → `conflict` `Den ansatte er
   allerede tildelt ordren`.
5. The rule point `assignment_eligibility` refuses (§3.4) → `invalid_input`
   with the rule's message.
6. Unavailability in the order period (§4).

The result is the assignment, `auto: false`.

#### 3.3 Ending and listing

| Tool | Kind, policy | Input | Result |
|---|---|---|---|
| `assignments_end` | transition, admin | `{"id"}` | the assignment, ended now |
| `assignments_list` | read | `{"order_id"?,"employee_id"?,"mine"?,"active"?=true}` | `{"items"}` |
| `assignment_overrides_list` | read, admin | `{"order_id"}` | `{"items"}`, the order's overrides (§4) |

`assignments_end` is refused with the lock `conflict` on a locked order,
with `invalid_transition` `Tildelingen er allerede avsluttet` when it is
ended, and with `conflict` `Stopp aktiv timer før tildelingen avsluttes`
while a work session on it runs. `assignments_list` with `active: true`
lists active rows only, with `active: false` ended rows only; `mine` keeps
the actor's employee's rows (§2.4).

#### 3.4 The rule point `assignment_eligibility`

A client method receives the order and the employee and returns NIL to
allow the assignment or a Norwegian message to refuse it. Example: Nordvik
Utleie refuses an employee of department `nord` on an order of department
`sør`, and the reverse. Automatic assignment (§5) skips an employee the
rule refuses.

### 4. Unavailability conflicts and overrides

Before an assignment is created, the employee's unavailability (§7) is
checked against the order period, taken as whole local days: from local
midnight of `event_date` to local midnight after `end_date ?? event_date`
(§8). A dateless order has no period and never conflicts. On a conflict:

- an actor who is not admin → `forbidden` `Den ansatte er utilgjengelig i
  ordreperioden og kan ikke tildeles` (the tool is admin, so this is a
  second guard, not a path a caller reaches);
- a blank `override_reason` → `invalid_input` `Begrunnelse er påkrevd ved
  overstyring av utilgjengelighet`;
- a reason over 500 characters → `invalid_input` `Begrunnelsen kan ikke være
  lengre enn 500 tegn`;
- otherwise the assignment is created and, in the same transaction, an
  override record is written and the audit entry carries the reason.

`assignment_override = {"id","assignment_id","order_id","employee_id","reason","conflict_ids","conflict_summary","created_by","created_at"}`.
Overrides are append-only. `conflict_ids` are the overlapping entries;
`conflict_summary` has one part per entry, joined by `; `:
`dd.mm.yyyy[–dd.mm.yyyy] (hele dager)` or `dd.mm.yyyy (kl. HH:MM–HH:MM)`.

### 5. Automatic assignment by department

#### 5.1 When it runs

Inside the transaction of `orders_create` when the order names a
department, and of `orders_update` when its department changes (the orders
seam `department_changed`). Nothing else assigns automatically.

#### 5.2 The steps

1. End the order's automatic assignments that no longer fit. One fits only
   while its `auto_department`, the employee's department and the order's
   department are the same, the employee has `auto_assign_in_department`
   and is active. A department set to null ends every automatic assignment.
2. Take the active employees of the order's department with
   `auto_assign_in_department`, in creation order (ids are opaque, so the
   store's insertion order gives the deterministic order).
3. Skip those already actively assigned to the order.
4. Assign the rest with `auto: true` and `auto_department`.

#### 5.3 Skipped employees

An employee who is unavailable in the order period (§4), or whom
`assignment_eligibility` refuses, is skipped: not assigned, no error, no
override. The order's save never fails for it.

#### 5.4 Manual assignments and running sessions

Manual assignments are never ended automatically. When an automatic
assignment that step 1 would end has a running work session, the whole
save fails with `conflict` `Stopp aktiv timer før tildelingen avsluttes`
and nothing changes.

#### 5.5 Changing an employee

`employees_update` that changes `role`, `department`,
`auto_assign_in_department` or `active` ends that employee's automatic
assignments that no longer fit (step 1's rule), on every order, locked
orders included, and bumps each such order's revision. A running session
makes the update fail as in §5.4. A settings change never assigns an
employee retroactively.

### 6. Work sessions

#### 6.1 Work session

`work_session = {"id","order_id","assignment_id","employee_id","started_at","ended_at","duration_seconds","note","source"}`.
`source` is `live` (a timer) or `manual` (registered afterwards). A session
runs while `ended_at` is null. Sessions are audited as the requests that
make them, no further.

#### 6.2 Tools

| Tool | Kind | Input | Rules |
|---|---|---|---|
| `work_sessions_start` | create | `{"order_id","assignment_id","note"?}` | the assignment must be active, on this order and the actor's own, else `forbidden`; the order must be calendar-active (`utkast`, `tilbud_sendt`, `akseptert`, `bekreftet`), else `invalid_transition` `Ordren har status <s>; timer kan ikke startes`; a running session of the actor anywhere → `conflict` `Du har allerede en aktiv timer` |
| `work_sessions_stop` | transition | `{}` | stops the actor's running session, always allowed; none → `not_found` `Du har ingen aktiv timer`; duration max(1, seconds) |
| `work_sessions_create_manual` | create | `{"order_id","assignment_id","started_at","ended_at","note"?}` | the actor's own assignment on the order (it may be ended), else `forbidden`; `ended_at > started_at`, else `invalid_input` `Sluttid må være etter starttid`; duration max(60, seconds) |
| `work_sessions_list` | read | `{"order_id"?,"mine"?,"from"?,"to"?}` | `{"items"}`; `from`/`to` filter on the session's start date in Norwegian local time |

The `forbidden` message is `Tildelingen <id> er ikke din aktive tildeling på
ordre <id>`. One employee has at most one running session.

#### 6.3 Closing an order

`orders_complete`, `orders_ready_for_invoice` and `orders_cancel` answer
`conflict` `Stopp aktive timer før ordren avsluttes` while any session on
the order runs (the orders seam `closure_guard`).

### 7. Unavailability

#### 7.1 Entry and tools

`unavailability = {"id","employee_id","start_date","end_date","whole_day","start_time","end_time","private_note","version","start_at","end_at"}`.
`start_time` and `end_time` are Norwegian local `HH:MM`; a whole-day entry
stores them as null. `start_at` and `end_at` are the entry's UTC interval
(§8), added to every result. `version` starts at 1 and grows by one on each
update.

| Tool | Kind | Input | Rules |
|---|---|---|---|
| `unavailability_create` | create | `{"employee_id"?,"start_date","end_date","whole_day","start_time"?,"end_time"?,"private_note"?}` | an admin may name any employee; anyone else only their own (`forbidden` `Du kan bare registrere din egen utilgjengelighet`); without `employee_id` the actor's employee, else `invalid_input` `Ingen ansatt er knyttet til aktøren <a>; oppgi employee_id` |
| `unavailability_update` | update | `{"id","version", any field}` | the owner or an admin |
| `unavailability_delete` | update | `{"id","version"}` | the owner or an admin; `{"deleted":true,"id"}` |
| `unavailability_list` | read | `{"employee_id"?,"from","to"}` | `{"items"}`: entries whose dates overlap the period, by start date; more than 200 → `invalid_input` `For mange registreringer; avgrens perioden` |

Updating or deleting someone else's entry without being admin is `forbidden`
`Bare eieren eller en admin kan endre registreringen`. A `version` other
than the current one is `conflict` `Endringen er basert på en utdatert
versjon. Last siden på nytt.` `private_note` is shown to the owner and to
admins; everyone else gets null.

#### 7.2 Validation, in order

All `invalid_input`. `start_date` and `end_date` are not schema-required, so
a missing or malformed date gets the Norwegian message:

1. `Fyll inn både fra- og til-dato` (a date missing or not `YYYY-MM-DD`);
2. `Til-dato kan ikke være før fra-dato`;
3. a timed entry needs both times as `HH:MM`, else `Fyll inn et gyldig
   klokkeslett`;
4. a local time in the spring gap: `Klokkeslettet finnes ikke på grunn av
   overgang til sommertid`;
5. a local time in the autumn overlap: `Klokkeslettet forekommer to ganger
   ved overgang til vintertid`;
6. `Sluttid må være etter starttid`, compared as instants after conversion.

#### 7.3 Overlaps

A new or changed entry may not overlap the employee's other entries →
`conflict` `Registreringen overlapper en eksisterende utilgjengelighet`;
nor the period (whole local days) of an order the employee is actively
assigned to → `conflict` `Perioden overlapper en aktiv ordretildeling. Fjern
tildelingen før utilgjengeligheten registreres.` Dateless orders never
overlap.

### 8. Norwegian local time

The offsets (CET +01:00, CEST +02:00), the rule for when summer time
applies and "today" are the kernel's (core.md §2.2); staffing converts the
other way. `to-utc(date, time)` computes both readings of the wall-clock
time: exactly one is a real instant → that instant; both → ambiguous (the
autumn overlap); neither → nonexistent (the spring gap).

- A whole-day interval is `[local midnight of start_date, local midnight of
  the day after end_date)`.
- A timed interval is `[to-utc(start_date, start_time), to-utc(end_date,
  end_time))`, one continuous span.
- Intervals are half-open: touching boundaries do not overlap.

Examples: 2026-01-15 09:00 → 08:00Z; 2026-07-15 09:00 → 07:00Z; 2026-03-29
02:30 does not exist; 2026-03-29 01:59 → 00:59Z and 03:00 → 01:00Z;
2026-10-25 02:30 is ambiguous; 2026-10-25 03:00 → 02:00Z. 2026-03-29 has 23
hours and 2026-10-25 has 25.

### 9. Invariants

1. At most one active assignment per (order, employee); ended rows are
   kept; `mine` follows active rows only.
2. Automatic assignment happens only when an order is created with a
   department or its department changes; it ends only automatic
   assignments, never manual ones, and never assigns retroactively.
3. Assigning an unavailable employee needs an admin and a reason of 1–500
   characters, recorded in the same transaction in an append-only override;
   unavailability cannot be registered over an active assignment.
4. A running work session blocks completing, invoicing readiness and
   cancelling its order and ending its assignment; stopping is always
   allowed; an employee has one running session at most.
5. Unavailability intervals are half-open UTC intervals from Norwegian local
   time (§8); nonexistent and ambiguous local times are refused; touching
   intervals do not overlap.
6. A dateless order never conflicts with unavailability.
