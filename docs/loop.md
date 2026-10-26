# Running the feature loop

This is the procedure an agent follows to take a request from the idea to a
deployed change. The contract is `spec/loop.md`. Everything here is done
with files, commands and the conversation with the person you work for, so
it works the same in any agent harness. Use what your harness has beyond
that only as a convenience, never as a step of the loop.

**When.** Every change to what Tun or a client does that someone asked
for runs the loop. A typo, a comment or a refactor that changes no
behaviour does not, unless the person asks for it.

**Where you are.** `tun loop status` says which stage a loop is at and
what comes next. Run it first when you take up a loop, and after anything
that may have cost you your context. In Tun, `tun` is `bin/tun`.

## 1. Brief

```
tun loop start NAME --title "Kort som dras på telefonen bytter kolonne" \
    [--mode reviewed] [--client ~/coding/tracker] [--after earlier-loop]
```

- NAME is short and in English, such as `board-paging`. The title is the
  request in a line, in the asker's language.
- The mode is hands-on unless the asker says otherwise: «just get it done
  and show me» is reviewed. Never choose a mode the asker did not.
- `--client` in Tun: the client the request came from, where the change is
  shown. Without it, the showcase (`checks/showcase/`).
- Write **Brief** in `loops/NAME.md`: the request in the asker's words,
  quoted, where it came from (a tracker item and its number, a message), and
  anything they said about it since.

## 2. Shape

- Read the code and the spec the request touches. Ask the asker only
  about decisions that are theirs: what they want, not how to build it.
  Make every other choice yourself and write it under **Decisions**, with
  why.
- Write **Criteria**, numbered. Each is a sentence a check or a test can
  decide: «a card held at the right edge for a second brings the next
  column into view», not «dragging works better». Criteria a browser shows
  become browser checks, the rest tests.

## 3. Spec and gate A

- Change the contract first: Tun's `spec/`, or the client's spec. A small
  change to a client may have no spec change. Then say so under
  **Decisions**.
- `tun loop gate A`. It prints what to tell the person, or runs the
  reviewer (§9). Tell the person exactly that, with your criteria and the
  spec change in short, and wait for the answer.
- Record the answer, quoting the person: `tun loop decide A approve --by
  jonas --why "«ja, kjør»"`. If they want changes: `tun loop decide A
  changes --by jonas --why "…"`, then go back to §2.
- If you cannot wait, for example because you run without a person, end
  your turn and say the loop is at gate A. Never decide a person's gate
  yourself.

## 4. Build

- Code, tests, and what the criteria need to be shown: the client's
  scenario in `tests/scenarios.lisp`, and browser checks in `checks/`
  (Tun's own: `checks/showcase/checks/`). The scenario is the data the
  person will see in the preview, so make it show the change.
- A change to Tun's kernel raises `+core-version+`
  (`src/core/module.lisp`) and `coreVersion` (`flake.nix`) here, not at
  Ship, so the tree that is shown is the one that ships.
- Follow `AGENTS.md`, `reference/style.md` and `reference/pitfalls.md` as
  for any change.

## 5. Verify

- `tun loop verify` runs everything the repository's rules ask for and
  records the round. When it fails, read the step's log under
  `.build/loop/NAME/`, fix, and run it again.
- After five failed rounds in a row the loop is `stuck`. Tell the person
  what fails and what you tried, and wait. Their go-ahead, with whatever
  they decide, is `tun loop resume --by jonas --why "…"`.

## 6. Show and gate B

- `tun loop show --path /saker [--path /saker/12] [--actor employee:kari]`
  starts the shared preview and takes the screenshots. It needs the tree
  that passed verify, so change nothing between the two.
- Look at the screenshots yourself before asking anyone. A screenshot that
  does not show the change is a reason to fix the scenario or the path, not
  to ask.
- `tun loop gate B`, then tell the person what it prints: the link they
  open on their phone, the sign-in link, what changed, and what was
  checked. Record their answer with `tun loop decide B …`. Changes go back
  to §4.

## 7. Ship and gate C

- Commit, in the repository and in the client when the loop changed it.
  The commit holds the shown tree exactly, with `loops/NAME.md`. Push only
  where the person has authorized pushing.
- Nothing to deploy, such as a change to Tun that no client uses yet:
  `tun loop finish`.
- A deploy: in the client, `tun update` to the pushed Tun, `bin/test`,
  commit. Then `tun loop gate C`, tell the person what will be deployed
  and where, and record their answer. Only after an approval, deploy as
  `spec/deploy.md` says, and `tun loop log "deployed tracker to …"`.

## 8. Follow

- `tun loop finish`, then commit the record.
- Tell whoever asked, where they asked, that it is done. In a tracker,
  that is a comment on the item.
- A reply that wants more, or something else, is a new loop:
  `tun loop start NAME --after THIS-LOOP`, its brief quoting the reply.

## 9. A reviewer instead of the person

In the reviewed mode, gates A and B go to a reviewer. Gate C always goes to
the person.

- With `TUN_REVIEWER` set, `tun loop gate` runs it and records the verdict
  itself. Read the reasons in the log and act on them as you would on the
  person's.
- Without it, `tun loop gate` prints a line to start a reviewer with in a
  fresh session of any agent. Ask the person to start one, or start one
  yourself where your harness can start a separate session that does not
  share your context. Record the answer: `tun loop decide B changes --by
  reviewer --why "…"`.
- Two *changes* in a row from a reviewer at one gate pass that gate to the
  person. `tun loop gate` says when this happens.
