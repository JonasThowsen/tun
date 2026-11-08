# Every page for every role: no server error, no broken link, refused where the policy says

- loop: page-smoke
- mode: reviewed
- stage: ship
- base: 932792b188947434b781cacc93930e68949b179c
- verified: 4f56d8f4634f9f2c011de0751299a12d241892d5
- shown: 4f56d8f4634f9f2c011de0751299a12d241892d5

## Brief

The sixth loop of the test programme Jonas asked for on 2026-11-06:

> in order for Tun to be reliable at the client level, the generated tests
> need to be fast and reliable ... We need to be able to Perform fuzz
> testing, and all other sorts of important test types that ensure our
> systems run correctly, and it needs to happen fast. Make that happen.

The approved order ended with «6 page smoke (every page × role, no
500)». Loops 1 to 5 are done (loops/fast-tests.md to loops/sequences.md).
Jonas, 2026-11-08, after loop 5 and the markdown loop: «go ahead».

## Criteria

1. Every client gets a ninth generated test,
   `generated-every-page-answers-every-role`, through
   `define-generated-tests`, as spec/testing.md 5 says.
2. As each actor and with no actor, every page of the list in
   spec/testing.md 5 is requested with GET. Probe pages in Tun's suite
   show that a failure is found, naming the actor, the path and the
   status, for each of these:
   - a page that answers 500 to one role only;
   - a staff page in the menu that answers 403 to a role its policy
     admits, while a page outside the menu that answers 404 at its bare
     prefix passes;
   - a staff page that answers a role its policy does not admit with
     anything but 403;
   - a staff page that, with no actor, answers anything but 303 to the
     login;
   - a public page that answers 500 with no actor.
3. The pages lead on. A failure is found, naming the page that led there,
   for each of these:
   - a page answering 500 that only a link on another page reaches;
   - a fragment answering 500 that only an `hx-get` reaches, requested as
     htmx requests it, `HX-Request-Type` included, so that
     `htmx-request-p` holds in the page;
   - a page answering 500 that only a GET's redirect reaches;
   - a link that answers 404;
   - a link to a page its actor may not open (403).
   The left-out paths are never opened, posted to or followed, as whole
   segments: a probe page at `/uitleg` is opened. A link to a file is
   fetched and not read.
4. Forms.
   - A form whose untouched post answers 500 is found.
   - So is a post whose redirect answers 500.
   - A form is read as a browser sends it: checked and unchecked boxes
     and radios, a select with and without a selected option, a text
     area, the first named submit button and a file input. A test of the
     reading says so.
   - Forms of one action and the same names are posted once.
   - A form posting to another site, or to `/logout`, is not posted.
     A post that redirects to another site is not followed.
5. Nothing leaves the process. A probe page that calls another system
   through `*http-json-handler*` when posted gets that system's
   unreachable answer, in the server's thread, with no connection made. A
   probe page that connects to another host itself fails the test.
6. Bounds and order.
   - At most 2 paths of a shape and 150 paths per actor are opened.
   - The summary gives the number left out.
   - Two runs on the probe pages, whose lists are ordered by title, open
     the same paths in the same order, each id read as the record it
     names.
7. Reports. A failure gives the first line of the fault the server
   recorded. The summary names a listed page that answered no actor with
   a page.
8. Tun's suite opens core's and every module's pages this way, from the
   scenario `fuzz-records`, and they pass. Any fault the test finds in
   them is fixed in this loop.
9. The test takes under 5 s in ferdig, kurs and nixploy-dashboard each,
   and each client's generated tests together stay under 30 s. Timed
   against the pinned Tun, back to back.
10. ferdig, kurs and nixploy-dashboard pass it on the new Tun, with what
    it finds in them fixed. They are pinned to it at gate C.

## Decisions

- **Reviewed**, as the whole programme: a fresh reviewer decides gates A
  and B, and Jonas gate C.
- **Over HTTP, through a test server**, not by calling page functions.
  That checks what a browser gets: the dispatch, the login redirect, the
  refusals, the htmx headers and the error page. It also uses claimed
  identity, so an actor needs no login, as with the fuzzing actors.
- **A copy per actor.** One actor's posts do not change what the next one
  sees. Each actor's GETs come before its posts, so its links are checked
  on the scenario's records.
- **The HTML is read with regular expressions**, not a parser. Only
  pages Tun's own renderer wrote are read, and it always double-quotes
  and escapes attributes. No new dependency.
- **A link that answers 403 or 404 fails.** A link its reader cannot
  follow is a bug in the page. A link to a record the reader may not see
  would tell them the record is there. This sets a rule for every client's
  pages, so what it finds in them is named to Jonas at gate C, with the
  fixes.
- **Only the menu's pages must answer their bare prefix.** A page left out
  of the menu may live only under its prefix, as messaging's `/messages`,
  the dashboard's `/runs/ID` and kurs's `/shares/SYMBOL` do (gate A,
  round 1).
- **Redirects are followed** when a GET answers them, since `/` and the
  pages that moved lead on that way. A post's redirect is followed once.
- **A post fails only at 500 and above.** An untouched form is often
  refused, such as with a required field left blank, and a 4xx is the
  right answer to it. Made-up values are §2's job, for tools; for forms,
  spec/testing.md 6 names it as not yet.
- **Bounds: 2 paths a shape, 150 an actor.** Record ids make many paths
  of one shape, and the test must stay within its share of a client's
  30 s.
- **The scenario's actors, and fuzz actors only for roles they lack**
  (decided while building, spec/testing.md 5 «Who»).
  - In ferdig, admin:fuzz and the scenario's admin:jonas did the same
    work, 2.1 s each, and the test took 6.5 s against criterion 9's 5 s.
  - The scenario's actors are also the realistic ones: they have
    accounts and own records, as the people who use the pages do.
- **No seed**: the crawl is breadth first in the order the pages name
  their links. Ids are random, so where a page orders records by id, or
  by a time the test clock makes equal, another run may open other paths
  of the same shapes. A failure is then found again in its shape, as the
  summary counts them.
- **The server's threads** are where the pages run, so §2's isolation is
  set there too: as global values for the length of the test, not as
  bindings of the test's thread. The generated tests of a process run one
  at a time.
- **Tun's own pages run in one suite, `pages`**, not split into core and
  modules as the tools are. The pages link to each other through one
  menu, so splitting them would open the same pages twice.

## Log

- 2026-11-08 15:45  started, reviewed
- 2026-11-08 15:46  gate A asked of a reviewer
- 2026-11-08 15:51  gate A: changes (reviewer): hx-get must send HX-Request-Type as htmx does; the below-400 rule fails pages that only exist under a sub-path; isolation (§2) must hold for the whole test and only same-site posts and redirects be followed; same paths across runs is undecidable with random ids. Also: follow GET redirects, probes for the login redirect, fault line and summary, exclusions as whole segments, read only text/html.
- 2026-11-08 15:52  gate A asked of a reviewer
- 2026-11-08 15:58  gate A: approve (reviewer): Round 1 addressed; criteria fit the brief and the code. Build-time notes: controls with form=ID count; the 403/404 rule covers named and redirected-to paths; follow HX-Location/HX-Redirect; say how links and forms are sent; timing risk; §1 item 9 should name the 403/404 rule.
- 2026-11-08 16:25  verify 1: passed build, test, check
- 2026-11-08 16:38  verify 2: failed test
- 2026-11-08 16:45  verify 3: failed test
- 2026-11-08 16:52  verify 4: failed test
- 2026-11-08 16:58  verify 5: passed build, test, check
- 2026-11-08 16:58  verify 2-4 failed in preview's a-stale-claim-is-taken-over-and-a-held-one-skipped, which passed alone: its free-preview-ports took ports whose socket directory another preview's Postgres held, which claim-port skips. The helper now skips them too (tests/preview-tests.lisp); verify 5 passed.
- 2026-11-08 16:58  shown (/ui)
- 2026-11-08 16:59  gate B asked of a reviewer
- 2026-11-08 17:09  gate B: changes (builder): The reviewer approved, with notes. Before shipping, the builder takes note 1 (an href drakma cannot parse stops the whole test without naming the page) and notes 4, 6, 7 and 8 (a weak assertion, style, the order of stopping, unbound isolate variables); notes 2 and 3 go to spec §6. The tree that ships is reviewed again.
- 2026-11-08 17:22  verify 6: passed build, test, check
- 2026-11-08 17:23  shown (/ui)
- 2026-11-08 17:23  gate B asked of a reviewer
- 2026-11-08 17:27  gate B: approve (reviewer): The notes taken are fixed and tested; criteria 1-10 met. Small points: a misleading comment on restoring in reverse, path-segments could use without-query, redirect-only pages always listed in the summary.
