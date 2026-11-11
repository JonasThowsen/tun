# A client names the page that / and a sign-in lead to

- loop: home-page
- mode: reviewed
- stage: done
- base: 6805e42bf050cbfacf92000b8871ca770ca7b71d
- item: sak_kkjhmzdebpadhtxf
- tags: kind:ui core module:web
- drafted: 15m
- estimate: 1h 2h 4h
- like: client-modules login-return customers-update
- verified: c5d2266826bb7a09c9d0809b2dd5efdab3cff7e2
- shown: c5d2266826bb7a09c9d0809b2dd5efdab3cff7e2

## Brief

From the factory's orchestrator, 2026-11-11 (Ferdig sak_kkjhmzdebpadhtxf,
project «Tun»): two builders of Tun ERP hit the same wall on 2026-11-11.
`front-page`:

> The page is «Today» at `/today` … It can't be where `/` leads: Tun has
> no way for a client to choose that, and `/` still opens the customers
> list. … What Tun lacks: a way for a client to name its home page,
> either a `define-application` option or a `home-path` seam. Tun's
> `home-path` always sends `/` and sign-in to the first resource.

And `setup-wizard`: «Tun gives a module no way to choose where `/` or a
sign-in leads, and no page guard», so a new company's admin cannot be
taken to the setup.

What must hold, from the orchestrator: a client says which page is home,
in `define-application` or by a documented method, and `/` and the
landing after sign-in go there for a signed-in person; without it,
today's behaviour exactly. The answer may depend on the person (their
role, and a function of the client's or a module's choosing): Tun ERP
wants «Today» for everyone, and a new company's admin taken to
`/company/setup` until the setup is completed. The smallest general
mechanism that allows both, saying how a module's and a client's answers
combine. It must never send a person to a page their role cannot open,
never loop, and never redirect off the site; a `next` given at sign-in
still wins when it is allowed. Spec (`spec/ui.md` and where sign-in's
landing is specified), `docs/client-api.md`, tests, and a browser check
in the showcase or the test client. Mode: reviewed. A core change.

The page guard («no page guard») is not asked for here: this loop is
where `/` and a sign-in lead.

## Criteria

1. Without `:home` and without a `home-path` method of the client or its
   modules, a signed-in person's `/`, a claimed sign-in and a provider's
   sign-in lead to the same page as before: the first resource with
   record pages, else the first resource, else the first menu page, else
   `/access`. The tests that pinned it change only in how they find that
   page, not in what it is: `home-location` in `tests/fake-provider.lisp`
   (used by `sign-in-tests.lisp` lines 30, 351, 352) asked `/` without a
   sign-in, which now answers `/login`; it becomes the path of the test
   client's first resource with record pages, and a new test asserts it
   is `/orders`, named literally. The test
   `home-is-the-first-page-in-the-menu-without-a-resource` calls Tun's
   default (renamed `default-home-path`, since `home-path` becomes the
   seam) with the same assertions. (`tests/home-tests.lisp`,
   `tests/sign-in-tests.lisp`, `tests/web-tests.lisp`)
2. `/` for someone not signed in answers 303 to `/login` with no `next`.
   (`tests/home-tests.lisp`)
3. `(:home "/today")` in `define-application` sends a signed-in person's
   `/`, `GET /login` while signed in, a claimed sign-in
   (`/login?actor=…`) and a provider's sign-in to `/today` (303).
   (`tests/home-tests.lisp`)
4. `(:home X)` is refused when the form is compiled for X not a string
   starting with one `/`, `/` alone or with a query or fragment (`/?x=1`,
   `/#a`), `//host`, a path with `\` or a
   control character, longer than 2000, `/login`, `/logout` or under
   `/auth/` or `/setup/`. (`tests/home-tests.lisp`, by macroexpansion)
5. `home-path` is a generic function in `TUN` of (APPLICATION ACTOR),
   with a docstring and registered for `introspect_extensions`; Tun's
   method answers the `:home` option or NIL. A module's method on its
   mixin wins over `:home`; a client's method on its application class
   wins over both, and with `call-next-method` gets the module's answer
   or the option. The method runs in a read transaction with `*actor*`
   bound to ACTOR (a method that calls `select` works). (`tests/home-tests.lisp`)
6. An answer is not taken, and the option (when the actor can open it)
   or else the default is, when it is: another site (`//evil.example`,
   `https://evil.example`), `/` or `/?x=1`, a sign-in step, a path with
   no page, a page of a module the application does not enable, or a
   staff page whose policy refuses the actor's role (an `:admin` page
   answered for an employee); each refusal is written to the error
   output. A resource's list or record and a kernel page such as
   `/access` are taken. (`tests/home-tests.lisp`)
7. A `next` kept at sign-in (`/login?next=/items`, a provider's attempt
   with a return path) still wins over the home page.
   (`tests/home-tests.lisp`; `checks/showcase/checks/home-page.py`)
8. A provider's sign-in that sets up the first admin still lands on
   `/access`, whatever `:home` or a method answers.
   (`tests/home-tests.lisp`, with `:home` set)
9. In the browser at 390 px, in the showcase, whose `(:home "/graph")`
   is «Graph» for everyone and whose method sends an admin to
   «Welcome» (`/welcome`, an admin page) until they press «Done»:
   employee anna opening `/` lands on `/graph`; signing in as an admin
   from `/login` lands on `/welcome`, and after «Done» `/` leads to
   `/graph`; signing in from `/login?next=/items` lands on `/items`.
   (`checks/showcase/checks/home-page.py`)
10. `spec/ui.md` §8 «Home» and §10, `spec/auth.md` §3.4 and §3.5 step 6,
   and `docs/client-api.md` («The home page», with the ERP example) say
   this; the core version is the next free on main when pushed, 2.21.0
   now, in `src/core/module.lisp` and `flake.nix`.

## Decisions

- **An option and a seam, the option as the seam's default.** The
  option covers «Today for everyone» in one line; the generic function
  `(home-path APPLICATION ACTOR)` covers what depends on the person.
  Tun's method is specialised on nothing, so it is the least specific:
  a module's mixin and a client's class come before it in the
  application's class precedence (a client's class, its features,
  `application`, the module mixins). Standard method combination gives
  «the client's, then the modules', then the option» with
  `call-next-method`, which client code already uses for seams; no new
  combination is needed.
- **Combining a module and a client.** A module's method wins over the
  option (the setup wizard must beat «Today»); a client's method wins
  over a module's, since the client is the one who knows, and chooses
  by calling `call-next-method` or not. A client that only uses `:home`
  writes no method, and its modules' answers come first.
- **Checked when it runs, not trusted.** Tun takes an answer only when
  the person's role opens it, the same checks a staff page and a
  resource make when they answer; a refused answer falls to the option,
  then to the default, which only lists pages the person sees. This
  keeps `/` from a 403, from another site (the `next` rules), and from
  looping (`/` is never an answer). A module mixin is in every
  application's precedence once the module is loaded, even where it is
  not enabled, so a page of a module not enabled is refused too. The
  refusal is written to the error output, since it is a mistake in a
  client or a module that a developer should see.
- **`/` for someone not signed in goes to `/login`.** Before, it went to
  the first resource, which went on to `/login?next=/customers`, and
  the sign-in then landed there: a `next`, which wins over the home
  page. Without `next` the sign-in lands on the person's home, which
  for a client without `:home` is that same first resource, so where
  people land is unchanged; one redirect less.
- **A `next` is not checked against the role.** It is what the person
  opened; a page they cannot open answers 403 as a link would, as
  before. Only the home page, which Tun chooses, is checked.
- **A provider's sign-in** knows the account, not yet an actor in the
  request: the home page is computed for the account's actor
  (`account-actor`).
- **No page guard.** `setup-wizard` also asked for a guard that keeps
  the admin on the setup; that is a different change (every page, not
  `/`) and not in this brief.
- **The showcase shows it**: `:home "/graph"` and a `/welcome` page for
  admins with «Done», kept in a small showcase entity, so the browser
  check has both a home for everyone and one for a role until a step is
  done.
- **Core version** 2.21.0, the next free minor; additive.
- **`bin/test` unsets `TUN_TRACKER`** (at build): verify ran the suites
  from a shell whose loop reports to the factory's tracker, and
  `a-loop-goes-from-start-to-finish-through-its-gates`, which does not
  set the variable, then reported its own test loop there and failed on
  the tracker's log. A test that wants a tracker sets one.

## Actuals

```json
{"loop":"home-page","title":"A client names the page that / and a sign-in lead to","repository":"tun","mode":"reviewed","stage":"done","item":"sak_kkjhmzdebpadhtxf","tags":["kind:ui","core","module:web"],"like":["client-modules","login-return","customers-update"],"started":"2026-11-11 09:19","ended":"2026-11-11 09:54","minutes":{"total":35,"waiting_person":0,"waiting_reviewer":3,"working":32,"drafted":15,"person_at_gates":null,"agent":null},"estimate":{"best":60,"likely":120,"worst":240,"at":"brief"},"latest_estimate":{"best":60,"likely":120,"worst":240,"at":"brief"},"within_estimate":false,"ratio":0.29,"verify":{"rounds":2,"failed":1},"changes":{"A":1,"B":0,"C":0},"interventions":0,"cost":{"tokens_in":null,"tokens_out":null,"usd":null,"agent_minutes":null}}
```

## Log

- 2026-11-11 09:19  started, reviewed
- 2026-11-11 09:21  estimated 1h 2h 4h at brief, like client-modules login-return customers-update
- 2026-11-11 09:21  gate A asked of a reviewer
- 2026-11-11 09:22  gate A: changes (reviewer)
  I'm asking for changes. Criterion 1 promises that two existing tests stay unchanged, but criteria 2 and 5 mean they can't.
  
  **What is right**
  - **The brief is fully covered.** The `:home` option, the per-person seam (role, plus a client's or a module's function), and how a module's and a client's answers combine are all there. The criteria also cover: never a page the person's role can't open, never a loop, never another site, a `next` still wins, the docs, the tests and a showcase browser check. The page guard is left out, which the brief says is correct.
  - **The design is sound.** It uses standard CLOS ordering through `call-next-method`, with Tun's own method as the least specific. Each answer is checked when it is used, not trusted. A module's answer beating `:home` is exactly what the setup wizard needs to beat «Today».
  - **The default matches today's code.** Criterion 1 says the same as `src/web/ui.lisp:1651-1659`: first resource with record pages, else first resource, else first menu page, else `/access`.
  - **The spec changes say the same as the criteria.** That is `spec/ui.md` §8 «Home» items 1–5 and the §10 tests entry, `spec/auth.md` §3.4 and §3.5 step 6, and `docs/client-api.md`. Each criterion can be decided by a named test or check.
  - **Two decisions are acceptable without asking.** Sending a signed-out `/` to `/login` keeps where people land the same, and the old `auth.md` text already pointed that way. Leaving a kept `next` unchecked against the role keeps today's behaviour.
  
  **Changes**
  1. **Criterion 1 can't hold as written (`loop.md:52-54`).** It says `sign-in-tests.lisp` and `home-is-the-first-page-in-the-menu-without-a-resource` stay unchanged.
     - `tests/fake-provider.lisp:205-207` (`home-location`) finds "home" by sending a request to `/` without signing in. Under criterion 2 that request now answers `/login`. So these three assertions would fail while sign-in still lands on `/customers`:
       - `tests/sign-in-tests.lisp:30`
       - `tests/sign-in-tests.lisp:351`
       - `tests/sign-in-tests.lisp:352`
     - `tests/web-tests.lisp:184-191` calls `(tun.web::home-path)` with no arguments. Criterion 5 makes `home-path` a two-argument generic function in `TUN`, so this test also has to change, or the old function has to be renamed.
  
     Restate criterion 1 to name these tests and say how they change while still pinning the old landing page. For example, `home-location` could follow `/` as a signed-in person, or the tests could assert `/customers` directly. Otherwise the main guard for "without it, today's behaviour exactly" gets quietly rewritten at gate B.
  2. **Criterion 4 and `spec/ui.md` §8 item 2 should also refuse `/` with a query at compile time.** As written, `(:home "/?x=1")` compiles but criterion 6 rejects it on every request: a fallback and an error-output line each time. A mistake that can only fail should be refused when the form is compiled.
  3. **Say what happens to a setup sign-in.** A provider sign-in for the first admin's setup goes to `/access` today (`src/web/access.lisp:183`). The new text in `spec/auth.md` §3.5 step 6 and `ui.md` §8 says any sign-in not returning to a page goes to the home page. Add to a criterion and to the spec that a setup sign-in still lands on `/access`, whatever `:home` or a method answers.
  4. **Small: `spec/auth.md`, the added text in §3.4 (diff line 63)** is one long line ending "…as a link to it would. The provider never sees PATH…". Re-wrap it to the file's width.
- 2026-11-11 09:23  gate A asked of a reviewer
- 2026-11-11 09:24  gate A: approve (reviewer)
  I approve gate A. All four changes asked for in the first round are made, and I found nothing new that blocks.
  
  **The first round's changes**
  1. **Criterion 1 now names the tests it changes and keeps what they pin.**
     - `tests/fake-provider.lisp:205-207` (`home-location`) asks for `/` without signing in. The criterion now has it use the path of the test client's first resource with record pages. A new test checks that path is `/customers`, written out literally.
     - That keeps the three checks at `tests/sign-in-tests.lisp:30,351,352` tied to today's landing page.
     - `tests/web-tests.lisp:184-191` will call `default-home-path` with the same assertions. That includes `"/login"` with no actor, which matches the current `src/web/ui.lisp:1651-1659`.
     - The default the criterion describes matches that code.
  2. **A `/` with a query or fragment is now refused when the form is compiled.** This is in criterion 4 (`/?x=1`, `/#a`) and in `spec/ui.md` §8 item 2.
  3. **A setup sign-in still lands on `/access`.** This is criterion 8, `spec/auth.md` §3.5 step 6 and the `ui.md` §8 lead-in. Today's code does the same (`src/web/access.lisp:183`).
  4. **The long line in `auth.md` §3.4 is re-wrapped.**
  
  **Brief against criteria**
  - Everything the brief asks for is covered:
    - the option and the seam;
    - an answer that depends on the person (their role, or a function a module or the client chooses);
    - how a module's and a client's answers combine: the client's wins, then the module's, then the option;
    - never a page the person's role can't open, never a loop, never another site;
    - a `next` still wins;
    - the specs, `docs/client-api.md`, the tests and a browser check in the showcase.
  - Leaving out the page guard is right; the brief says so.
  - Every criterion names a test or check that can decide it.
  - The spec text says the same as the criteria.
  
  **Decisions**
  None of them needed the asker:
  - Sending a signed-out `/` straight to `/login` lands people where they land today, one redirect sooner.
  - Not checking a kept `next` against the role is today's behaviour.
  - Working out a provider sign-in's home page from the account's person (`account-actor`) is an implementation detail.
  
  **Existing showcase checks**
  Making «Graph» the showcase's home does not break any of them:
  - Every check that needs a page opens it directly (`/items` and others).
  - `login-returns-to-the-page.py:23-24` only checks that `/` does not lead to `/login`.
  
  **For gate B (not blocking)**
  - **`spec/ui.md`, `diff.patch` line 110.** "…and is a path a `next` may be (`auth.md` §3.4: no `\`, no" is wider than the file's width, and lines 132-133 wrap early. Re-wrap them.
  - **The showcase's «Done» state is stored and stays between check runs.** `home-page.py` must not depend on the order checks run in, or on an earlier run.
- 2026-11-11 09:40  verify 1: failed test
- 2026-11-11 09:51  verify 2: passed build, test, check
- 2026-11-11 09:52  shown (/, /welcome)
- 2026-11-11 09:52  gate B asked of a reviewer
- 2026-11-11 09:53  gate B: approve (reviewer)
  I approve gate B. Every criterion has a test or check that would fail without the change, the spec says what the code does, and verify round 2 passed build, test and check.
  
  **Criteria**
  - **1:** `tuns-default-home-is-the-first-resource-with-record-pages` checks `/orders`, written out literally. `without-home-the-root-and-a-sign-in-lead-where-they-did` checks the same through a real server: `/` for an employee and an admin, and a claimed sign-in. `home-location` (`tests/fake-provider.lisp:205`) now reads Tun's default instead of asking `/` without a sign-in. `web-tests.lisp:184-191` calls `default-home-path` with the same assertions.
  - **2–8:** each has its own test in `tests/home-tests.lisp`:
    - signed-out `/` goes to `/login`;
    - the option, for `/`, `GET /login` while signed in, and a claimed sign-in;
    - the paths refused when the form is compiled, including `/?x=1`, `/#a`, a tab and 2001 characters;
    - the published seam and its order: a module's answer beats the option, a client's beats both, with and without `call-next-method`;
    - a method reads the store with `*actor*` bound;
    - each answer that must not be taken (another site, `/`, a sign-in step, no such page, a module not enabled, an admin page for an employee) is refused, and the refusal is written to the error output;
    - a resource's list or record, `/access` and a path with a query are taken;
    - a kept `next` wins, for a claimed sign-in and for a provider's;
    - a provider's sign-in lands on the person's home, and a sign-in that sets up the first admin lands on `/access` with `:home` set.
  - **9:** `checks/showcase/checks/home-page.py` passed all 8 of its checks at 390 px:
    - anna lands on `/graph`;
    - signed-out `/` goes to `/login`;
    - the admin lands on `/welcome`, and `/` stays there;
    - a sign-in from `/login?next=/items` lands on `/items`;
    - after «Done» the admin goes to `/graph`, and `/` follows.
    
    At gate A I asked that the check not depend on the order checks run in or on an earlier run. It doesn't: `bin/check` runs each check against a fresh preview, so the stored «Done» state is never carried over.
  - **10:** `spec/ui.md` §8 «Home» and §10, `spec/auth.md` §3.4 and §3.5 step 6, and `docs/client-api.md` («The home page», with the ERP example) all say this. The core version is 2.21.0 in both `module.lisp` and `flake.nix`.
  
  **Screenshots:** `/` as admin:jonas is «Welcome» at both widths, as it should be before «Done». They show only the admin's side; the employee's `/graph` and «Done» leading on to `/graph` are covered by the check.
  
  **Brief:** the change does what it asks:
  - a one-line `:home` covers «Today» for everyone;
  - a method answers per person, which covers the setup wizard;
  - a module's answer beats `:home`, and a client's beats both;
  - an answer is checked when it is used, so it is never another site, never `/` (no loop) and never a page the role is refused;
  - a `next` still wins.
  
  **Code:**
  - The `next` rules moved from `access.lisp` into `site-path-p` in core and are now shared by the `:home` compile check and the run-time check, so the two can't drift apart.
  - `person-home-path` (`src/web/ui.lisp:1691`) falls back from the answer to the option to the default. It doesn't check the option twice when the answer was the option.
  - There is no leftover debugging and no dead code; the `declare (ignore account)` that the change made stale is gone.
  - The `bin/test` `unset TUN_TRACKER` is explained in a comment and under Decisions.
  
  **Not blocking:**
  - `spec/ui.md`, in §8 «Home» item 4: the line "page the application serves and ACTOR's role opens: a staff page (`define-page`, …" is wider than the rest of the file. It is the same kind of wrapping I noted at gate A.
  - In the showcase's «Welcome» card the «Done» button sits right under the paragraph, with almost no space between them at both widths.
- 2026-11-11 09:54  pushed fa86575 to Tun's main, core 2.21.0
- 2026-11-11 09:54  finished at tun fa86575
