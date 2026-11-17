<!-- Screen.svelte -- the showcase's single-page screen (spec/typescript.md 4):
     a person signs off with a note through the generated module, and sees the
     answer of each call in place, a refusal at its field. -->
<script lang="ts">
  import { signOffsCreate, signOffsList, type Refusal } from "./api";
  import type { Words } from "./words";
  // An asset of the screen's own, which the build writes as a file under
  // the screen's prefix: a data: URL would be refused by the page's policy.
  import signedIcon from "./signed.svg";

  let { words }: { words: Words } = $props();

  let note = $state("");
  let noteError: string | null = $state(null);
  let answer = $state("");
  let signed = $state(false);
  let count: number | null = $state(null);
  let noteField: HTMLTextAreaElement | undefined = $state();

  async function showCount(): Promise<void> {
    const listed = await signOffsList();
    if (listed.kind === "ok") count = listed.value.returned;
  }

  function showRefusal(refusal: Refusal): void {
    const message = refusal.fields["note"];
    if (message !== undefined) {
      noteError = message;
      noteField?.focus();
    } else {
      answer = refusal.message;
    }
  }

  async function signOff(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    noteError = null;
    answer = "";
    signed = false;
    const made = await signOffsCreate({ note });
    switch (made.kind) {
      case "ok":
        answer = words.signedOff(made.value.signed_by ?? "?", made.value.credential ?? "?");
        signed = true;
        note = "";
        void showCount();
        break;
      case "refused":
        showRefusal(made.refusal);
        break;
      case "failed":
        answer = made.failure.reason === "network"
          ? words.noAnswer
          : words.notUnderstood(made.failure.status);
        break;
    }
  }

  void showCount();
</script>

<main>
  <h1>{words.title}</h1>
  <p id="count" class="muted" data-count={count}>{count === null ? " " : words.count(count)}</p>
  <form id="sign-off" novalidate onsubmit={signOff}>
    <label for="note">{words.note}</label>
    <textarea id="note" name="note" rows="3" aria-describedby="note-error"
              aria-invalid={noteError === null ? undefined : "true"}
              bind:value={note} bind:this={noteField}></textarea>
    <p id="note-error" class="error" hidden={noteError === null}>{noteError ?? ""}</p>
    <button type="submit">{words.signOff}</button>
  </form>
  <p id="answer-line" role="status">
    {#if signed}<img id="signed" src={signedIcon} alt="" width="20" height="20">{/if}
    <span id="answer">{answer}</span>
  </p>
</main>

<style>
  /* Tun's design tokens (/assets/tokens.css, spec/ui.md 3): the pages' own
     colours, type, spacing and radii, light and dark. */
  :global(body) {
    margin: 0;
    background: var(--background);
    color: var(--foreground);
    font-family: var(--font-sans);
    font-size: var(--text-base);
    line-height: var(--text-base--line-height);
  }

  /* The pages' focus ring (spec/ui.md 3): the accent, outside the edge. */
  :global(:focus-visible) {
    outline: 2px solid var(--ring);
    outline-offset: 2px;
  }

  main {
    max-width: 36rem;
    margin: 0 auto;
    padding: calc(var(--spacing) * 6) calc(var(--spacing) * 4);
  }

  h1 {
    margin: 0 0 var(--spacing);
    font-size: var(--text-2xl);
    line-height: var(--text-2xl--line-height);
    font-weight: var(--font-weight-semibold);
  }

  .muted {
    margin: 0 0 calc(var(--spacing) * 6);
    color: var(--muted-foreground);
  }

  form {
    display: grid;
    gap: calc(var(--spacing) * 2);
  }

  label {
    font-weight: var(--font-weight-semibold);
  }

  textarea {
    box-sizing: border-box;
    width: 100%;
    padding: calc(var(--spacing) * 2) calc(var(--spacing) * 3);
    border: 1px solid var(--input);
    border-radius: var(--radius-md);
    background: var(--input-background);
    color: inherit;
    font: inherit;
  }

  textarea[aria-invalid="true"] {
    border-color: var(--destructive);
  }

  .error {
    margin: 0;
    color: var(--destructive);
  }

  button {
    justify-self: start;
    min-height: var(--control-height-lg);
    padding: 0 calc(var(--spacing) * 5);
    border: 0;
    border-radius: var(--radius-md);
    background: var(--primary);
    color: var(--primary-foreground);
    font: inherit;
    font-weight: var(--font-weight-semibold);
  }

  #answer-line {
    display: flex;
    gap: calc(var(--spacing) * 2);
    align-items: center;
    min-height: calc(var(--spacing) * 6);
    margin: calc(var(--spacing) * 4) 0 0;
  }
</style>
