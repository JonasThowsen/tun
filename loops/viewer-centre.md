# Bildevisningen åpner midt i vinduet

- loop: viewer-centre
- mode: autonomous
- stage: ship
- base: 12ab0ec7187f415d033dd5fe3ce8e9b06ccf28af
- verified: b09094d03e1b6cbb53766040a01d504bc21e39e6
- shown: b09094d03e1b6cbb53766040a01d504bc21e39e6

## Brief

Reported on 2026-10-27 by an agent working on a client, after a reviewer of
its own traced it:

> ui:attachments' viewer opens in the top-left corner of the window
> instead of the centre. On a 1280×800 desktop, clicking a thumbnail shows
> the modal at (0,0) over the dimmed page. [...] src/web/ui/kit.lisp:274
> resets `margin: 0` on every element, and `.tun-attachments-dialog`
> (src/web/ui/files.lisp:391) never gives `margin: auto` back, so
> showModal's centring is lost. [...] It may hit any other <dialog> that
> doesn't set its own margin, so ui:dialog is worth a look too.

Jonas asked for the attachments feature this belongs to (core 1.20.0).

## Criteria

1. The open viewer is centred in the window: its left and right gaps, and
   its top and bottom gaps, differ by at most 2 px, at 1280×800 and at
   390×844 (`checks/showcase/checks/files-thumbnails.py`).
2. Every `<dialog>` Tun's components render sets its own margin, so the
   reset never leaves one at the corner: a test lists the components'
   dialogs and checks their CSS (`tests/ui-interaction-tests.lisp`).

## Decisions

- `margin: auto` on `.tun-attachments-dialog`, the browser's own
  centring for a modal dialog, rather than positioning it ourselves.
- `ui:dialog` already sets its margin (`auto` on a desktop, a sheet along
  the bottom on a phone), so it is unchanged; criterion 2 guards that
  every dialog keeps one.
- A bug fix in a component: core 1.21.1.


## Log

- 2026-10-27 19:23  started, autonomous
- 2026-10-27 19:23  gate A asked of a reviewer
- 2026-10-27 19:24  gate A: approve (reviewer): diagnosis holds; criteria cover the bug and the guard; spec matches
- 2026-10-27 19:40  verify 1: passed build, test, check
- 2026-10-27 19:40  shown (/vedlegg)
- 2026-10-27 19:40  gate B asked of a reviewer
- 2026-10-27 20:18  gate B: changes (reviewer): the guard reads nested rules, so ui:dialog's margin is not guarded: scan only a rule's own top-level declarations, and show it fails without interaction.lisp:59's margin
- 2026-10-27 20:29  verify 2: failed test
- 2026-10-27 20:41  verify 3: passed build, test, check
- 2026-10-27 20:50  shown (/vedlegg)
- 2026-10-27 20:50  gate B asked of a reviewer
- 2026-10-27 20:53  gate B: approve (reviewer): the guard reads only a rule's own declarations and fails without either dialog's margin; the viewer is centred at both widths
