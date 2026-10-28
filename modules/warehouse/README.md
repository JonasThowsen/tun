# tun module `warehouse`

ASDF system `tun-warehouse`, package `tun.warehouse`; pinned by clients
through `flake.nix` in this directory (tun-platform.md §2, §4; the contract
below).

- **Owns:** `task`, `task_event`; `tasks_create`, `tasks_update`,
  `tasks_assign`, `tasks_complete`, `tasks_reopen`, `tasks_list`,
  `tasks_get`, `task_events_list`.
- **Depends on:** `staffing` (employees and the client's departments). A
  task knows no order and is never created from one (§1).
- **Core range:** builds against core `>= 2.0.0, < 3.0` (`flake.nix` `core`,
  and `define-module` in the Lisp source).
- **Publishes:** the kernel's extension kinds on `task` (core.md §1.1); no
  seam. Every list is bounded (`limit` up to 100,
  `has_more`; core.md §2.4).
- **Rollback:** an older core without this module cannot show a task: the
  rollback preflight counts every task (§5; docs/architecture.md, "Tenants
  and deployment").

## Contract

### 1. Scope

Warehouse tasks: work in one of the client's departments, with a due date
and an optional assignee from that department, and an append-only ledger
of one event per change. Departments and employees are staffing's
(`departments`, `employee`, `actor-employee`). Tasks are never created from
orders and know no order. Kernel rules (policy, results and error codes,
idempotency, audit) are core.md §3.

### 2. Task

`task = {"id","revision","department","title","description","status":"open"|"completed","due_date","assignee_id","created_by","completed_at","completed_by","created_at"}`.

| Field | Rule |
|---|---|
| `department` | required, one of the client's departments: blank is `invalid_input` `Velg avdeling for lageroppgaven`, unknown is `invalid_input` `Ukjent avdeling <d> (gyldige: …)`; never changes |
| `title` | trimmed, 2..160, else `invalid_input` `Tittelen må ha mellom 2 og 160 tegn` |
| `description` | optional, ≤ 2000, kept as given |
| `due_date` | optional date |
| `assignee_id` | optional employee whose current department is the task's, else `invalid_input` `Ansvarlig må tilhøre samme avdeling som lageroppgaven` |
| `revision` | starts at 1, bumped by every change; a stale `revision` is `conflict` |
| `completed_at`, `completed_by` | set on completion, cleared on reopen |

Status: `open` → `completed` (`tasks_complete`), `completed` → `open`
(`tasks_reopen`).

### 3. Events

`task_event = {"id","task_id","kind":"created"|"changed"|"assigned"|"completed"|"reopened","actor","at","recipient_id","details"}`.

Every mutation writes exactly one event in the mutation's transaction, so an
event that cannot be written rolls the mutation back. Events are append-only.

| Event | Written by | `recipient_id`, `details` |
|---|---|---|
| `created` | `tasks_create` | the assignee, `{"deep_link":"/tasks/<id>"}` |
| `changed` | `tasks_update` | `{"fields":[…]}`, the changed fields sorted |
| `assigned` | `tasks_assign` to someone | the assignee, `{"deep_link":"/tasks/<id>"}` |
| `changed` | `tasks_assign` to null | `{"assignment_removed":true}` |
| `completed` | `tasks_complete` | |
| `reopened` | `tasks_reopen` | |

### 4. Operations

#### 4.1 Writes

- `tasks_create {department, title, description?, due_date?, assignee_id?}`
  (create, admin).
- `tasks_update {id, revision, title?, description?, due_date?}` (update,
  admin): `description: null` and `due_date: null` clear them.
- `tasks_assign {id, revision, assignee_id | null}` (update, admin): the
  current assignee again is `invalid_input` `Oppgaven er allerede tildelt
  denne personen`; null removes the assignment.
- `tasks_complete {id, revision}` (transition, employee): an admin may
  complete any task; anyone else must be the current assignee, else
  `forbidden` `Bare nåværende ansvarlig kan fullføre lageroppgaven`, and
  belong to the task's department, else `forbidden` `Du må tilhøre samme
  avdeling som lageroppgaven for å fullføre den`. A task that is not open is
  `invalid_transition` `Oppgaven er allerede fullført`.
- `tasks_reopen {id, revision}` (transition, admin): a task that is not
  completed is `invalid_transition` `Oppgaven er ikke fullført`.

#### 4.2 Reads

- `tasks_list {department?, status?, mine?, query?, limit?}` (read): `mine`
  keeps the tasks in the actor's department or assigned to the actor (an
  actor without an employee record sees none); `query` is a
  case-insensitive substring of title or description. Sorted open first,
  then by due date ascending with no due date last, then newest first.
- `tasks_get {id}` (read).
- `task_events_list {id, limit?}` (read): the task's events, oldest first.

### 5. Rollback

An older core without this module cannot show a task: the rollback
preflight (core.md §6.4) counts every task.
