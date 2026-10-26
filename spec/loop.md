# The feature loop

Status: v1, built 2026-10-24, core 1.13.0: the hands-on and reviewed
modes; the tracker (§6.1), core 1.17.0. It is built
on previews and checks (`preview.md`).

## 1. What it is

An agent takes a request, such as «I can't drag a card to another column
on my phone», from the idea to a deployed change. It goes through fixed
stages. Each stage ends on a condition the agent can check itself, and
at three gates someone approves before it goes on. The person who asks
says how much they want to be asked: every gate, or only the deploy
(§4).

Agent sessions in Tun and in a client ran this by hand on 2026-10-21
and 2026-10-22: the client's session passed on a person's request, Tun's
specified, built, checked in Chromium and pushed, and the client's moved,
deployed and passed on the answer. The loop makes those steps the agent's procedure, and the
waiting between them a gate with a link.

**No harness of its own.** The loop is three things any agent can use:

- **a procedure**, `docs/loop.md`, that `AGENTS.md` points to;
- **a record**, a Markdown file in the repository (§5);
- **`tun loop`** (§6), which runs the mechanical steps, refuses steps out
  of order, and always ends by saying what comes next.

It needs nothing from the agent's harness beyond reading and writing
files, running commands and talking to the person. Claude Code, Codex, pi
or a person at a terminal run it the same way. It does not depend on
whatever else a harness has, such as subagents, skills, hooks or memory.
An agent that has lost its context, or a new session, finds where a loop
is with `tun loop status`. A reviewer (§4) is whatever program
`TUN_REVIEWER` names, or a fresh session the person starts.

## 2. Kinds of change

| Kind | Changed in | Shown in | Shipped as |
|---|---|---|---|
| Client feature | the client's repository | `tun preview` of the client | a commit and a deploy of the client |
| Module feature | `modules/M` in Tun | a client using M, previewed against the Tun worktree (`bin/tun preview --dir CLIENT`) | a Tun commit, then `tun update` and a deploy in the clients that use M |
| Core feature | Tun's kernel | the client that asked, previewed against the Tun worktree | a core version, a Tun commit, then `tun update` and a deploy of that client |

A loop's record is in the repository the change is made in. A loop in
Tun names the client it is shown in (`--client`). Without one, it is shown
in the showcase (`checks/showcase/`). The client's own changes, such as a
scenario or a check, belong to the same loop. The client's preview runs on
the Tun worktree until Tun is pushed.

## 3. Stages

1. **Brief.** The request in the asker's words, where it came from (an
   item in a tracker, a message), and the mode (§4).
2. **Shape.** Questions only for decisions that are the asker's; any
   other choice is made and written down. The result is the acceptance
   criteria, each written as a check could test it: «a card held at the
   right edge brings the next column into view within a second».
3. **Spec.** The contract changes first (`AGENTS.md`). **Gate A.**
4. **Build.** Code, tests, the scenario and the browser checks for the
   criteria. A core change also raises the core version here, so the tree
   that is shown is the one that ships.
5. **Verify.** `tun loop verify` (§6). A failure goes back to Build.
   After five failed rounds in a row, the loop stops and asks the person.
6. **Show.** `tun loop show`: a shared preview, screenshots at phone and
   desktop widths of the pages that changed, and a report. **Gate B.**
7. **Ship.** Commit the shown tree, and push where pushing is
   authorized. For a deploy: `tun update` in the client, then **Gate C**
   before the deploy itself.
8. **Follow.** `tun loop finish`. An answer to the change, such as «not
   really what I wanted», starts a new loop with this one as its context
   (`--after`).

## 4. Gates and modes

| Mode | A: spec | B: preview | C: deploy |
|---|---|---|---|
| Hands-on | the person | the person | the person |
| Reviewed | a reviewer | a reviewer | the person |
| Autonomous | a reviewer | a reviewer | a reviewer, only for targets marked for it |

- The asker picks the mode per request; hands-on is the default.
- Deploying to production stays with a person (`AGENTS.md`). No target is
  marked for an autonomous deploy yet, so in v1 autonomous asks the person
  at C, as reviewed does.
- **The person.** `tun loop gate` prints what the agent tells the person:
  what is to be decided, and the link and report where there is one. The
  agent then waits for the answer, in whatever way its harness talks to
  the person, and records it with `tun loop decide`, quoting the person.
  An agent that cannot wait ends its turn with the gate open. The record
  says it is waiting.
- **A reviewer** gets a packet (§6): the record, the diffs, the
  verification, the screenshots and the reviewer's instructions
  (`docs/review.md`). It does not get the builder's reasoning. It answers
  *approve* or *changes*, with reasons, ending on a line
  `VERDICT: approve` or `VERDICT: changes`. With `TUN_REVIEWER` set to a
  command, such as `claude -p` or `codex exec -`, `tun loop gate` runs it
  in the packet's directory with the instructions on its standard input,
  and records its verdict and reasons. Without it, `tun loop gate` prints
  how to start a reviewer in a fresh session, and the agent records the
  answer with `tun loop decide`.
- Two answers of *changes* in a row at one gate from a reviewer pass that
  gate to the person.
- Every gate decision is in the record: the gate, who decided, when, and
  why.

## 5. The record

`loops/NAME.md` in the repository, committed with the change. NAME matches
`[a-z][a-z0-9-]*`. `tun loop start` writes it:

```markdown
# Kort som dras på telefonen bytter kolonne

- loop: board-paging
- mode: hands-on
- stage: brief
- base: 23d6bcd4…
- client: ~/coding/tracker
- client-base: 4c58fa5e…

## Brief

## Criteria

## Decisions

## Log

- 2026-10-24 15:02  started, hands-on
```

- **The fields** are the `- key: value` lines before the first `##`.
  `tun loop` sets them; the agent does not edit them. `base` is the
  revision the loop started from, and the diffs are taken from it. The
  other fields are `client` and `client-base`, `after` (the loop this one
  answers), `verified` and `shown` (the trees that passed and were shown,
  §6), `failures` (failed verify rounds in a row), and `item`, the loop's
  item in a tracker (§6.1).
- **No machine's address is in it.** The record is committed, and the
  repository may be public, so the link of a shared preview, which names
  the machine it runs on and its tailnet, is kept in
  `.build/loop/NAME/show/link` instead. `status`, the person's gate and
  the packet read it from there. Saving a record takes out a `preview`
  field and a link in a `shown at LINK (…)` line of an older `tun loop`.
- **Brief, Criteria and Decisions** are the agent's. They hold the request
  in the asker's words and where it came from; the criteria, numbered, each
  naming the check or test that shows it once there is one; and the choices
  made without the asker, with why.
- **Log** is `tun loop`'s, one line per event: a gate asked, a decision with
  who and why (a reviewer's reasons indented under it), a verify round
  with what failed, a show with the paths it shows, and the agent's own
  lines (`tun loop log`), such as a push or a deploy.

`tun loop` reads and writes the record and nothing else in the repository.
What it produces, such as logs, packets and screenshots, goes to
`.build/loop/NAME/`.

## 6. `tun loop`

```
tun loop start NAME --title TEXT [--mode hands-on|reviewed|autonomous]
                    [--client DIR] [--after LOOP] [--item REF]
tun loop status [NAME] [--json]
tun loop gate A|B|C [NAME]
tun loop decide A|B|C approve|changes --by WHO [--why TEXT] [NAME]
tun loop verify [NAME]
tun loop show [NAME] [--path PATH]... [--actor ACTOR] [--scenario S]
tun loop resume --by WHO --why TEXT [NAME]
tun loop log TEXT [NAME]
tun loop finish [NAME]
```

They work in the repository of the current directory, or `--dir DIR`.
Without NAME, they act on the loop that is not done, and refuse when there
are several, naming them. Each prints, last, what comes next and who acts.

**The tree** of a repository is git's tree object for its working tree,
untracked files included, ignored ones, `loops/`, `.build/` and `.data/`
left out. It is
computed with a temporary index, so git's own index is untouched. A
verify, a show and a commit are compared by their trees: what was shown is
exactly what was verified, and what is committed is exactly what was shown.
With a client, both repositories' trees count.

**Stages and what moves them:**

| Stage | Means | Moved on by |
|---|---|---|
| `brief` | the brief, criteria and spec are being written | `gate A` → `gate-a` |
| `gate-a` | waiting for A | approve → `build`; changes → `brief` |
| `build` | building | `verify`: passes → `verified`; fails → `build`, five in a row → `stuck` |
| `stuck` | five verify rounds failed in a row | `resume` (the person's go-ahead) → `build` |
| `verified` | the tree passed | `show` → `shown`; a changed tree → `verify` again |
| `shown` | the verified tree is at a shared preview | `gate B` → `gate-b` |
| `gate-b` | waiting for B | approve → `ship`; changes → `build` |
| `ship` | committing and pushing | `gate C` → `gate-c`; `finish` when nothing is deployed |
| `gate-c` | waiting for C | approve → `deploy`; changes → `build` |
| `deploy` | deploying | `finish` → `done` |

`verify` and `show` also run from `verified` and `shown`, after a change
to the tree, and `verify` also from `ship`. `decide ... changes` needs
`--why`.

- **`start`** writes the record (§5) from the current revision and moves
  to `brief`. The mode is hands-on unless given. `--item` records REF as
  the field `item`; a REF with a line break, or empty, is a usage error.
- **`verify`** runs, from the top of the repository:
  - in Tun: `bin/build`, `bin/test` and `bin/check`. When the
    environment variable `TUN_PRESSURE` names a program, a load and
    restart suite for some client, it also runs that when the change
    touches the runtime, jobs or the store (`src/runtime.lisp`,
    `src/jobs/`, `src/store/`, `src/core/store.lisp`).
    With a client, it runs `bin/tun check --dir CLIENT`, the client's
    checks on the Tun worktree;
  - in a client: `bin/test`, and `tun check` when it has checks.

  Each step runs with the ASDF settings of the shell `tun` was run from,
  which `tun`'s launcher keeps in `TUN_CALLER_CL_SOURCE_REGISTRY` and
  `TUN_CALLER_ASDF_OUTPUT_TRANSLATIONS`: its own SBCL changes them. Each
  step's output goes to `.build/loop/NAME/verify-N/STEP.log`. The
  round's line in the log names the steps that failed. It exits 1 when one
  failed.
- **`show`** needs the tree `verify` passed. It starts the shared preview
  of the client (`tun preview`, on the Tun worktree in Tun), and takes
  screenshots at 390×844 and 1280×800 of each PATH (default `/`), signed in
  as ACTOR (default the scenario's first actor). It writes
  `.build/loop/NAME/show/report.md`: the title, the link and sign-in
  links, the revision, the files changed since `base`, the verification,
  and the screenshots; and the link alone to `.build/loop/NAME/show/link`.
  The log's line is `shown (PATH, …)`.
- **`gate X`** checks the gate's precondition, writes the packet
  `.build/loop/NAME/gate-X-N/`, and asks the one who decides (§4). The
  preconditions are: for A, a criterion; for B, the shown tree; for C, a
  commit whose tree is the shown one. The packet is self-contained:
  `README.md` (the reviewer's instructions and what this gate decides),
  `loop.md` (the record), `diff.patch` (from `base`, the client's too) and,
  at B and C, `verify.txt`, the checks' results, the screenshots and
  `link`, the preview's link.
- **`decide`** records the decision of the gate the loop waits at.
- **`resume`** records the person's go-ahead after `stuck`.
- **`log`** adds a line of the agent's to the log.
- **`finish`** needs the committed tree to be the shown one, and moves to
  `done`.
- **`status`** prints the title, stage, mode, item, the preview's link
  from the last show (`"preview"` in `--json`, `null` before one), who
  decides the next gate, the next step and the last lines of the log. With `--json`, it
  prints the same as an object. Without NAME and an open loop, it says so
  and exits 0 (`null` with `--json`).

A step out of order, or a gate whose precondition does not hold, exits 1
and says what comes next. A usage error exits 2.

### 6.1 The tracker

A loop can be mirrored in a tracker the work already goes through, such
as an issue tracker: the loop is an item there, its stage the item's
status, and each event a comment. A person then answers their gate on the
item, from their phone, where they read their items anyway. The record
stays the truth; the tracker is a mirror.

- **`TUN_TRACKER`** names a command, run as `sh -c` runs it, as
  `TUN_REVIEWER` is. Without it, nothing of this section happens.
- After each event, once the record is saved, `tun loop` runs it in the
  repository's top directory as `COMMAND EVENT RECORD`: EVENT is `start`,
  `gate`, `decide`, `verify`, `show`, `log`, `resume` or `finish`, and
  RECORD the record's absolute path.
- **Its standard input** is one JSON object. Every event has these
  members, all strings except `item`, which is a string or `null`:
  `event`; `loop`, the NAME; `title`; `mode`; `stage`, after the event;
  `item`; `repository`, the top directory's absolute path; `record`, the
  record's absolute path; and `time`, ISO 8601 with the zone's offset,
  such as `2026-10-26T14:05:09+01:00`. Each event adds:

  | Event | Members |
  |---|---|
  | `start` | none |
  | `gate` | `gate`, `"A"`, `"B"` or `"C"`; `decider`, `"person"` or `"reviewer"`; `message`, the text `tun loop gate` prints for the person to be told, as one string with its line breaks, or `null` when a reviewer decides |
  | `decide` | `gate`; `decision`, `"approve"` or `"changes"`; `by`, a string; `why`, a string or `null`; `reasons`, the reviewer's reasons as one string, or `null` |
  | `verify` | `round`, an integer from 1; `passed`, a boolean; `steps`, the round's steps, and `failed`, those that failed, each an array of the names verify prints, such as `"build"`, `"test"`, `"check"`, `"pressure"` and `"client-check"` |
  | `show` | `preview`, the link, a string; `paths`, an array of strings |
  | `log` | `line`, a string |
  | `resume` | `by`, a string; `why`, a string |
  | `finish` | `commits`, an array of objects `{"repository": NAME, "revision": SHORT}`, NAME `"tun"` or the client's |

  A gate a reviewer decides is a `gate` event, then a `decide` event. A
  step refused, such as one out of order, sends no event, and neither does
  the log line of a failed tracker (below).
- **At `start` without `--item`,** when the command exits 0 within the
  time limit, the first line it printed that is not blank becomes the
  field `item`, so the later events carry it. A line of more than 500
  characters is not taken, and the log says so. Otherwise what the command
  prints is not read.
- **It may fail without stopping the loop.** A command that exits other
  than 0, or has not finished after 30 seconds and is stopped, adds a line
  `tracker: EVENT failed: …` to the log, saying the exit status or the
  time limit, and the step goes on and exits as it would have. What the
  command writes to its standard error is added to
  `.build/loop/NAME/tracker.log`.

## 7. Evidence

- `tests/loop-tests.lisp`:
  - the record's fields are read, set and taken out;
  - who decides each gate in each mode, including after two requests
    for changes from a reviewer in a row;
  - a reviewer's verdict is the last `VERDICT:` line;
  - what `show` records leaves the preview's link out of the record, in
    `.build/loop/NAME/show/link`, where gate B's text, `status` and the
    packet read it; a record of an older `tun loop` loses its link when
    saved;
  - a stand-in tracker gets each event with its fields, gives the item at
    start, and a tracker that fails or hangs adds a line to the log while
    the loop goes on;
  - the tree leaves out the record and `.build/`, and git's own index is
    untouched;
  - a loop runs in a repository of its own from start to finish, with a
    stand-in reviewer: changes at A back to the brief, five failed verify
    rounds to `stuck`, `resume`, gate B on the shown tree, and gate C and
    `finish` refused until the shown tree is committed.
- `bin/test-cli`: in a client made by `tun new`, a loop runs from start to
  finish, hands-on. Its steps are: gate A refused without criteria; verify
  with `bin/test` and `tun check`; `show` with screenshots at both widths,
  the link in `.build/loop/NAME/show/link` and none in the record;
  gate B; and `finish` refused until the shown tree is committed.
- By hand, 2026-10-24: in a copy of a client, `show` of `/saker` on the Tun
  worktree, shared on the tailnet, and gate B through a stand-in
  reviewer.

## 8. Steps

1. Build `preview.md`: previews, scenarios, checks. Done 2026-10-24.
2. The procedure for agents (`docs/loop.md`), the record and `tun loop`,
   in the hands-on mode. Built 2026-10-24; next, run it on a client's
   request.
3. The reviewer's instructions (`docs/review.md`), `TUN_REVIEWER`, and the
   reviewed mode. Built 2026-10-24.
4. The loop's state in a tracker the work already goes through (§6.1):
   `TUN_TRACKER` and `--item`. Built 2026-10-26; the adapter for a given
   tracker is the tracker's side.
5. Starting loops without a person: a session per item, started when an
   item reaches a status, within limits on how many run at once.
