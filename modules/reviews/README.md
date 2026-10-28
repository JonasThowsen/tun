# tun module `reviews`

ASDF system `tun-reviews`, package `tun.reviews`; pinned by clients through
`flake.nix` in this directory (tun-platform.md §2, §4; the contract below).

- **Owns:** `review`; `reviews_list`, `reviews_get`, `reviews_resolve`.
- **Depends on:** none. A review knows its subject, proposal and source only
  as `{type, id, revision}`: no order, no plan (§1).
- **Core range:** builds against core `>= 2.0.0, < 3.0` (`flake.nix` `core`,
  and `define-module` in the Lisp source).
- **Publishes:** `request-review` and `supersede-reviews` for the modules
  that ask for reviews, and two seams a requesting module implements for its
  kinds: `resolve_review` (the kind's handler: approve or reject, or report
  the review superseded) and `review_details` (what `reviews_get` adds, e.g.
  the order plan's `diff`).  Without a handler `reviews_resolve` answers
  `invalid_transition`.
- **Rollback:** an older core without this module cannot take a pending
  review (nobody could resolve it): the rollback preflight counts pending
  reviews (§6; docs/architecture.md, "Tenants and deployment").

## Contract

### 1. Scope

A review asks an admin to approve or reject a proposal about a subject. The
module knows neither: subject, proposal and source are `{type, id,
revision}` objects, and the module that requested the review handles its
kind through two seams (§4). The order plan review of orders is one such
kind (orders README, requirement plans). The module's own rules: an
idempotency key names at most one review, there is one pending review per
proposal, only a pending review is resolved, and the resolution and the
handler's effects commit together. Kernel rules (policy, results and error
codes, audit) are core.md §3.

### 2. Review

`review = {"id","kind","status","priority","subject":{"type","id","revision"},"proposal":{"type","id","revision"},"source":{"type","id"},"idempotency_key","title","summary","requested_by","requested_at","due_at","reviewed_by","reviewed_at","note","subject_id","proposal_id"}`.

- `status`: `pending` → `approved`, `rejected` or `superseded`; nothing
  leaves those three.
- `priority`: `critical`, `high`, `normal` (default) or `low`.
- `idempotency_key` is unique.
- `subject_id` and `proposal_id` repeat the ids of `subject` and
  `proposal` as columns a query can use.

### 3. Requesting reviews

Functions for the module that requests reviews:

- `request-review &key kind priority subject proposal source idempotency-key title summary requested-by due-at`
  returns the pending review of the proposal when there is one, else the
  review that already has the idempotency key (in any status), else a new
  pending review. `idempotency-key` is required.
- `supersede-reviews &key proposal-id subject-id` marks the pending reviews
  of a proposal (or, without one, of anything about a subject) `superseded`.
- `pending-review-for proposal-id` and `pending-reviews-of subject-id`
  (oldest first) look them up.

### 4. Kind handlers

Seams (core.md §1.1) a requesting module implements for its kinds; a method
handles its own kind and calls the next method for any other:

| Seam | Kind | Does | Default |
|---|---|---|---|
| `resolve_review` | rule | the handler: given `approve` or `reject`, applies the decision and answers `approved`, `rejected`, or `superseded` with a reason when the proposal no longer holds | `invalid_transition` `Ingen behandler for gjennomganger av typen <kind>` |
| `review_details` | before | what `reviews_get` shows for the kind beyond the review (e.g. a plan's diff) | the review alone |

An operation error from the handler (such as `invalid_transition`) leaves
the review pending. A result outside the three is an extension error
(`internal`, core.md §3.5).

### 5. Tools

- `reviews_list {status?="pending", kind?, limit?}` (read): sorted by
  priority (critical, high, normal, low), then `requested_at` ascending,
  then creation order; bounded per core.md §2.4.
- `reviews_get {id}` (read): the review with what its kind adds (§4).
- `reviews_resolve {id, decision: approve|reject, note?}` (transition,
  admin): locks the review; one that is not pending is
  `invalid_transition` `Gjennomgangen er allerede behandlet`; dispatches to
  the kind's handler; then records `status` = the handler's result,
  `reviewed_by`, `reviewed_at` and `note`, all in one transaction. A note
  is the audit reason (core.md §3.8). Returns
  `{"result","reason","review"}`.

### 6. Rollback

An older core without this module cannot take a pending review: the
rollback preflight (core.md §6.4) counts pending reviews.
