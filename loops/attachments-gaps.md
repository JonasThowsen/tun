# Filer i dialoger, og filene ved en post i en klients operasjon

- loop: attachments-gaps
- mode: autonomous
- stage: done
- base: 62e7632430f790e88dba67ce0bb32d142e6326ff
- verified: 131008e784bbbc9c411ba34a23f4c589864d2837
- shown: 131008e784bbbc9c411ba34a23f4c589864d2837

## Brief

Two gaps in core 1.20.0, met by an agent building attachments in a client
(Jonas approved that client's change at its gate A on 2026-10-27):

> `ui:dialog` with `:action` renders its own form and has no way to set
> `enctype`, so a `ui:file-input` inside a dialog posts no files. [...]
> (b) the dialog sets `enctype="multipart/form-data"` by itself when its
> children hold a `file-input`. The generated forms already do that.

> Inside an operation a client can't list a record's attachments:
> `attach-files` is the only export [...]. What I'd need is a public
> function [...] It would return the same JSON objects `attachments_list`
> gives [...] and check the record policy as the current actor. A batch
> form for several records of one entity [...] would save one query per
> comment, but it isn't required.

Both complete what spec/files.md promised a client: a file field in any
form Tun makes, and the files of a record in its own operations.

## Criteria

1. A `dialog` with `:action` whose content holds an `<input type="file">`
   at any depth (a `file-input`'s, or one written by hand) renders its
   form with `enctype="multipart/form-data"`; without one, or without
   `:action`, no `enctype` (`tests/ui-interaction-tests.lisp`).
2. A file chosen in such a dialog reaches the page's operation: a browser
   check posts a file from a dialog in the showcase and sees it attached
   (`checks/showcase/checks/files-in-a-dialog.py`).
3. `(attachments-of RECORD)` gives the record's files as attachment
   objects, the same JSON as `attachments_list`, in the order added; none
   for a record the caller may not see, meaning one the record policy
   does not admit to `*actor*` or that is not `entity-readable-p` for
   them, also when the caller's code read it with the system actor
   (`tests/files-tests.lisp`).
4. `(attachments-of LIST)` gives an `equal` hash table from id to list
   for every record in LIST, with two queries whatever its length; an
   empty list gives an empty table. A record, or a list, of an entity
   that takes no files, a record never stored, or records of two
   entities, signal an error.
5. `attachments-of` is exported from `TUN`; core 1.21.0.

## Decisions

- (b), as the client suggested: the dialog finds the field itself, as
  generated forms do, so a page cannot forget it.
- The function takes records, not an entity name and ids: the client has
  the records already, and an entity name in a string is what the tools
  need, not Lisp code. It reads them again by id as `*actor*` (one
  `select` for the batch) and checks `entity-readable-p`, as the brief
  asks: a client may have read them as the system actor (`store.md` §6.2),
  and the answer must be the tool's.
- The batch form answers by id in a hash table, so a client looks up each
  comment's files without a second pass.
- A minor version: a new public function.


## Log

- 2026-10-27 18:11  started, autonomous
- 2026-10-27 18:11  gate A asked of a reviewer
- 2026-10-27 18:14  gate A: changes (reviewer): the brief asks for the record policy as the caller; records read with the system actor would leak their files' metadata, so re-read the ids as *actor* in one select; errors for a single record; say the dialog detects any input type=file; status, evidence and client-api at build
- 2026-10-27 18:14  gate A asked of a reviewer
- 2026-10-27 18:15  gate A: approve (reviewer): the policy point and the smaller ones met; criteria decidable; nothing beyond the brief
- 2026-10-27 18:32  verify 1: failed check
- 2026-10-27 18:44  verify 2: passed build, test, check
- 2026-10-27 18:44  shown (/vedlegg)
- 2026-10-27 18:44  gate B asked of a reviewer
- 2026-10-27 18:50  gate B: changes (reviewer): no test fails without entity-readable-p in attachments-of; the two-query promise is untested; the TUN export is not exercised
- 2026-10-27 19:04  verify 3: passed build, test, check
- 2026-10-27 19:04  shown (/vedlegg)
- 2026-10-27 19:04  gate B asked of a reviewer
- 2026-10-27 19:09  gate B: approve (reviewer): the three tests each fail without what they guard (mutation-checked); criteria 1-5 met; files 375/375 on Postgres
- 2026-10-27 19:09  finished at tun 166bf0b
