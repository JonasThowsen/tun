# One login page, and back to the page you opened after signing in

- loop: login-return
- mode: hands-on
- stage: ship
- base: 0a0bec3600fbd77c07f056250ebb474752eb2630
- verified: 78fe807bf354b125619a26c55c5345756e05f318
- shown: 78fe807bf354b125619a26c55c5345756e05f318

## Brief

Jonas, 2026-11-06, with screenshots of kurs at `/login-info` («Du er ikke
innlogget … Logg inn») and then `/login` («Logg inn i kurs.» with the
button): «One thing, is there a reason why we have kind of two login
screens». Told there was none, and that after signing in Tun sends you
home rather than to the page you opened, he answered: «yes start that loop,
and when you are finished, bump the clients of Tun to that version».

## Criteria

1. Not logged in, `GET /items` (a client's page) answers 303 to
   `/login?next=%2Fitems`; so do a resource list, a record's page and
   `/files/ID`, each with its own path and query.
2. Not logged in, `GET /` with no resource as home goes to `/login`, and
   `GET /login-info` answers 303 to `/login`.
3. A sign-in through a provider started from `/login?next=/items` ends
   with 303 to `/items`; one started from plain `/login` ends at the home
   page, as before. `next` is kept in the attempt, not in the URL sent to
   the provider.
4. In claimed mode `/login?actor=admin:demo&next=/items` answers 303 to
   `/items`, and the login page's test sign-in links carry `next`.
5. Logged in, `GET /login?next=/items` answers 303 to `/items`.
6. A `next` of `https://example.com/`, `//example.com`, `/\example.com`,
   `/login`, `/logout`, `/auth/x/callback`, `/setup/x`, one with a control
   character or over 2000 characters is ignored: the person goes home.
7. An htmx request not logged in gets `HX-Redirect` to
   `/login?next=` the page in `HX-Current-URL`.
8. A POST not logged in still answers 401 (a multipart one unread), and a
   logged-in person whose role a page does not admit still gets 403.
9. In a browser on a phone, signed out, opening the showcase's `/items`
   shows the login page; «Som administrator» there lands on `/items`.

## Decisions

- One login page: `/login`. The 401 page that only linked to it stays
  only for a POST, where there is no page to return to.
- A client's page (`define-page`) now sends someone not logged in to the
  login; it answered 403 «Siden er ikke for deg», which is why kurs'
  pages said nothing useful when signed out. A logged-in person the policy
  does not admit still gets 403.
- `next` is a path on this server or nothing (criterion 6): an open
  redirect would let a link to Tun's login send a person to another site
  after signing in. `/login`, `/logout`, `/auth/` and `/setup/` are
  refused so a login never loops or restarts a sign-in.
- The return path travels in the sign-in attempt row (a new column,
  additive), not in a cookie or the provider's `state`: the provider never
  sees it, and it is used once with the attempt.
- htmx: following a 303 inside htmx would swap the login page into a part
  of the page, so htmx requests get `HX-Redirect`, as stale assets do.
- `/login-info` answers 303 to `/login` rather than 404, for open tabs and
  bookmarks.
- Setup (the first admin) still ends at `/access`.
- Core version: a patch, 2.6.2, unless the `http-form-post` loop ships
  2.7.0 first; then this is 2.7.1. That loop's work sits uncommitted in the
  main checkout, so this one runs in a worktree of its own.
- Shown in the showcase: Tun's change, and the showcase has `/items`.
- After ship: ferdig, kurs, nixploy-dashboard and tun-demo are updated to
  this Tun (Jonas: «bump the clients»).

## Log

- 2026-11-06 19:55  started, hands-on
- 2026-11-06 19:56  gate A asked of the person
- 2026-11-06 19:57  gate A: approve (jonas): «Approve»
- 2026-11-06 20:18  verify 1: passed build, test, check
- 2026-11-06 20:19  shown (/items)
- 2026-11-06 20:19  gate B asked of the person
- 2026-11-06 20:20  gate B: approve (jonas): «Approve and push»
