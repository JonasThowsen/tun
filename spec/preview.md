# Previews, scenarios and browser checks

Status: v1, built 2026-10-24, core 1.12.0. How a person or an agent sees a
branch running before it is deployed, and checks it in a browser. The
feature loop (`loop.md`) is built on it.

## 1. Why

The board's phone fixes of 2026-10-22 took three rounds. Each round, an
agent changed Tun, the client moved to it and deployed, and a person tried
it on their phone. To check its own work, the agent wrote a throwaway
server with a page like the client's, picked a port, and wrote a Playwright script
that sends touch events. It restarted the server by hand to get clean
data, and nothing of that was kept for the next change.

Three things replace that:

- **A preview** (§2): a working tree running on its own port, with fresh
  data and anyone's sign-in, at a link a person opens on their phone and an
  agent drives in Chromium.
- **A scenario** (§3): the data a preview or a check starts from, written
  once in the client.
- **A browser check** (§4): a committed script that drives a preview,
  such as «a card held at the right edge brings the next column into
  view», run by `tun check`.

## 2. `tun preview`

```
tun preview [--dir DIR] [--scenario NAME] [--port N] [--no-share] [--json]
tun preview list [--json]
tun preview stop NAME... | --all
```

Where it runs decides which Tun the client runs on:

| Where | Command | Tun |
|---|---|---|
| A client's dev shell | `tun preview` | the revision the client pins |
| Tun's dev shell | `bin/tun preview --dir CLIENT` | this working tree of Tun, kernel and modules, in place of the client's pins |

The second form is how a change to core is seen in the client that asked
for it, before Tun is pushed or the client moves to it. The client's files
are then compiled into the Tun worktree's `.build/preview-fasl/CLIENT/`,
apart from those its own shell compiles against its pinned Tun.

**Starting.** `tun preview` starts the client in DIR (default: the
current directory) and returns once it answers `/health`. The server
runs in a session of its own, so it outlives the terminal and the `tun`
that started it, until it is stopped.

1. **The name.** The client's name and the worktree's branch,
   `tracker-board-paging`, lower-cased with anything outside `[a-z0-9-]`
   made `-`. A detached head uses its short revision. The client's name
   is that of the `.asd` at the top of DIR.
2. **The database.** A Postgres server of its own in
   `DIR/.data/preview/`, created empty on every start and removed when
   the preview stops, with its socket in
   `$XDG_RUNTIME_DIR/tun-preview-PORT/` (a socket's path may be at most
   107 bytes, which a worktree's directory can exceed). A preview never
   keeps data between starts, so what it shows follows from the code and
   the scenario. (`bin/serve` is the one that keeps data.) `DATABASE_URL`
   is not used.
3. **The server.** The working tree as it is, uncommitted changes too,
   with its tests system, where its scenarios are. It runs with
   `--claimed-identity` (`auth.md` §1), so `/login?actor=role:name` signs
   in as anyone, and a sign-in provider or mail provider whose settings
   are missing is left out, mail going to `(:log)` (`mail.md`). It gets
   the caller's environment, as `bin/serve` does; the secrets a
   deployment reads from its SOPS file are not in it, so a call to
   another system fails unless the scenario installs a fake answer with
   `*http-json-handler*` (`outbound.md`). It listens on `127.0.0.1`
   only, on port N or the first free port from 4200.
4. **The scenario.** NAME, or `default` when the client defines one, makes
   its records once the server has opened its database and before it
   listens (§3). A NAME the client does not define stops the server,
   which names the scenarios there are.
5. **Sharing.** With `tailscale` on the machine, `tailscale serve --bg
   --https=PORT http://127.0.0.1:PORT` makes it
   `https://HOST.TAILNET.ts.net:PORT`. That address is reachable only
   from devices on the tailnet, over HTTPS, so the service worker and
   secure cookies work as they do when deployed. `--public-url` is that
   address. Never Funnel: a claimed-identity server must not be on the
   internet. `--no-share`, or no `tailscale`, gives the local address
   only. Changing `tailscale serve` needs operator rights, given once
   with `sudo tailscale set --operator=$USER`.
6. **The answer.** The address, a sign-in link for each actor the
   scenario names (`…/login?actor=employee:anna`), the branch, the
   revision (with `-dirty` when the tree has changes), the Tun it runs on,
   the scenario and its description, and the server's log. `--json`
   prints the same as one object, for agents.
7. **Again.** A second `tun preview` in a worktree that has one running
   restarts it on the same port with a fresh database. A tab open on
   the phone then shows the new code on reload. A preview of the same
   name from another directory is refused while it runs.

A server that stops before it answers, or does not answer within 180
seconds (a first compile included), is stopped and removed, and `tun`
prints the end of its log (exit 1).

**Listing and stopping.** Every preview has a file,
`$XDG_STATE_HOME/tun/previews/NAME.json` (`~/.local/state/…` without
it), with its port, process, address, directory, revision and start
time. `tun preview list` reads these, so it shows every preview on the
machine across worktrees, and marks one whose process has ended as
stopped. `tun preview stop NAME` ends the server and its Postgres,
removes the `tailscale serve` entry, the database and the socket's
directory, and deletes the file. `--all` stops every one.

## 3. Scenarios

A scenario is the data a preview or a check starts from, defined with
`define-scenario` from Tun's test support (`TUN.TEST-SUPPORT`) in the
client's tests system, `tests/scenarios.lisp` in a client `tun new`
makes:

```lisp
(define-scenario default (:actors ("admin:jonas" "employee:kari"))
  "Nordvik med Kari, prosjektet Nettside og 25 saker i Ny."
  (let ((customer (tun:jget (call-ok "customers_create" "admin:jonas" "name" "Nordvik") "id")))
    (call-ok "people_add" "admin:jonas" "customer_id" customer "account_name" "kari")
    (dotimes (i 25)
      (call-ok "items_create" "employee:kari" "title" (format nil "Sak nummer ~d" (1+ i))
               "kind" "feil"))))
```

- The body makes its records through operations, with `call-ok` as the
  actor named, so record policies, rules and the audit apply as they do
  in use. A scenario that needs a record no operation makes is a sign
  that an operation is missing.
- `:actors` are the actors a preview offers sign-in links for. Each is
  checked when the scenario is compiled. A string first in the body
  describes the scenario.
- A test starts from a scenario with `(run-scenario "NAME")` inside
  `with-test-app`, so a test, a check and a preview see the same data.
  The tests of a client `tun new` makes run every scenario once
  (`every-scenario-makes-its-records`), so none stops working unseen.
- The roadmap's factories (`docs/roadmap.md`, Testing) will make the
  bodies shorter. A scenario stays the named set of data built from
  them.

## 4. Browser checks

A check is a Python file in the client's `checks/` directory (one whose
name starts with `_` is not a check). It defines `run(t)`, and `SCENARIO
= "NAME"` when it starts from another scenario than `default`:

```python
"""On a phone, a card held at the screen's edge pages the board."""

def run(t):
    page = t.phone()                         # 390×844, touch
    page.sign_in("employee:anna")
    page.goto("/saker")
    finger = page.touch.hold(page.card("Sak nummer 1")).move_to(389, 400)
    finger.stay(0.8)
    t.check(page.visible_width("[data-tun-board-column=planlagt]") > 300,
            "«Planlagt» comes into view")
    finger.move_to(200, 400)
    with page.expect_post("/saker/flytt") as post:
        finger.lift()
    t.check("column=planlagt" in post.body, "the drop moves the card")
```

`tun check [NAME...] [--dir DIR]` runs every check, or the ones named,
each against a fresh, unshared preview of its scenario (§2), so no check
sees what another changed. The previews are named `NAME-check`, keep
their database in `DIR/.data/check/`, and are stopped when their check
ends. A check gets:

- `t.phone()` and `t.desktop()`: a page at 390×844 with touch, or at
  1280×800 with a mouse, each with its own cookies; both take another
  width and height, `permissions`, such as `["notifications"]`, which
  the page's browser grants its preview, `user_agent`, and
  `javascript=False` for a browser without JavaScript;
- `page.sign_in(actor)`, `page.goto(path)`, `page.card(title)` (the card
  with exactly that title, not the copy that follows a drag),
  `page.column(key)` and `page.visible_width(selector)`;
- `page.touch`: one finger, through the DevTools protocol's touch events,
  which scroll and drag as a finger does (Playwright's own taps do not
  move): `hold`, `move_to`, `stay`, `lift` and `swipe`;
- `page.expect_post(path)`, which waits for the post and its answer, and
  gives its `body` and `status`;
- `t.check(condition, text)`, which records a screenshot when it fails
  and carries on, so one run lists every failure;
- everything else of Playwright's page.

A check that raises, checks nothing, or leaves a JavaScript error on one
of its pages fails. The runner is Tun's `scripts/tun_check.py`, run with
`tun-check-python`, Python with Playwright and Chromium (the whole
browser, headless, so that notifications and service workers behave as
they do in Chrome), which the dev
shells of Tun and of a client have. It writes `NAME.json` with each
check's results and `NAME-N.png` for each failure to `DIR/.build/checks/`.
`tun check` prints which passed and exits 0 only when every one did.
`bin/test` does not run checks, because Chromium makes them slow. The
loop's verify stage (`loop.md` §3) runs both.

**Tun's own checks.** A component's behaviour in a browser, such as the
board's dragging, is checked against the showcase, a client in
`checks/showcase/` whose pages show components with a server behind
them: a page shaped like a tracker's `/saker`, whose board's moves are
operations. Its checks are in `checks/showcase/checks/`; `bin/check`
runs them on this working tree. The first are the board checks written
by hand on 2026-10-22: filling a phone's screen, dragging on a phone
with paging and autoscroll, and dragging with a mouse.

## 5. Decided

2026-10-24:

1. **Settings.** A preview reads no secrets of a deployment, so a
   client's calls to other systems fail in it, unless a scenario installs
   a fake answer with `*http-json-handler*`.
2. **Lifetime.** A preview runs until it is stopped.
3. **Core's showcase.** Tun's checks run against the showcase client
   (§4), not against a real client.

## 6. Evidence

- `tests/preview-tests.lisp`: a scenario's records, actors and
  description; its actors checked when compiled; a preview's name from a
  branch; the `tailscale serve` commands, never Funnel; the server's
  command on a pinned Tun and on a worktree; `list` with a process that
  has ended, `stop` removing the database and the file; the checks
  found and their scenarios; and refusals with their exit statuses.
- `bin/test-cli`: after `tun new`, a scenario with a customer. `tun
  preview` answers `/health`, offers the scenario's sign-in link and has
  its customer; a second start keeps the port and begins from a fresh
  database; `list` shows it running; `stop` leaves no server, database
  or file. A check that sees the customer passes `tun check`; broken, it
  fails, named, with a screenshot.
- `bin/check`: the showcase's checks pass. With the board's snapping fix
  of 2026-10-22 taken out, the phone check fails on «the columns do not
  snap while a card is dragged».
