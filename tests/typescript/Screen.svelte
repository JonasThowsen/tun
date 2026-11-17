<!-- Screen.svelte -- the type-check fixture: a Svelte component's code against
     the module the fixture's operations give (tests/typescript-tests.lisp).
     An operation that changes under it makes svelte-check refuse this file. -->
<script lang="ts">
  import {
    tsNotesAnswer, tsNotesCount, tsNotesCreate, tsNotesRename, type Answer, type TsNote,
  } from "./api";

  let shown = $state("");

  async function run(): Promise<string> {
    const created: Answer<TsNote> = await tsNotesCreate({ title: "Buy milk", status: "open" });
    if (created.kind === "refused") return created.refusal.fields["title"] ?? created.refusal.code;
    if (created.kind === "failed") return created.failure.reason;
    const note: TsNote = created.value;
    const renamed = await tsNotesRename({ id: note.id, new_title: "Buy bread" });
    const answered = await tsNotesAnswer({ id: note.id, answer: "later" });
    const counted = await tsNotesCount();
    const count: number = counted.kind === "ok" ? counted.value.count : 0;
    return `${renamed.kind} ${answered.kind} ${count} ${note.title} ${note.done} ${note.tags.join(",")}`;
  }

  void run().then((text) => { shown = text; });
</script>

<p>{shown}</p>
