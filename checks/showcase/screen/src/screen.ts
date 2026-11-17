// screen.ts -- the showcase's single-page screen (spec/typescript.md 4): a
// person signs off with a note through the generated module, and sees the
// answer of each call in place, a refusal at its field.

import { signOffsCreate, signOffsList, type Refusal } from "./api.js";

function element<T extends Element>(selector: string): T {
  const found = document.querySelector<T>(selector);
  if (found === null) throw new Error("The screen has no " + selector);
  return found;
}

const form = element<HTMLFormElement>("#sign-off");
const note = element<HTMLTextAreaElement>("#note");
const noteError = element<HTMLElement>("#note-error");
const answerText = element<HTMLElement>("#answer");
const count = element<HTMLElement>("#count");

async function showCount(): Promise<void> {
  const answer = await signOffsList();
  if (answer.kind === "ok") {
    count.textContent = `${answer.value.returned} signed off so far`;
  }
}

function showRefusal(refusal: Refusal): void {
  const message = refusal.fields["note"];
  if (message !== undefined) {
    noteError.textContent = message;
    noteError.hidden = false;
    note.setAttribute("aria-invalid", "true");
    note.focus();
  } else {
    answerText.textContent = refusal.message;
  }
}

function clear(): void {
  noteError.hidden = true;
  noteError.textContent = "";
  note.removeAttribute("aria-invalid");
  answerText.textContent = "";
}

form.addEventListener("submit", (event) => {
  event.preventDefault();
  clear();
  void signOffsCreate({ note: note.value }).then((answer) => {
    switch (answer.kind) {
      case "ok":
        answerText.textContent =
          `Signed off by ${answer.value.signed_by ?? "?"} (${answer.value.credential ?? "?"})`;
        note.value = "";
        void showCount();
        break;
      case "refused":
        showRefusal(answer.refusal);
        break;
      case "failed":
        answerText.textContent = answer.failure.reason === "network"
          ? "No answer came. Try again."
          : `The answer was not understood (${answer.failure.status}).`;
        break;
    }
  });
});

void showCount();
