// screen.ts -- the showcase's single-page screen (spec/typescript.md 4): a
// person signs off with a note through the generated module, and sees the
// answer of each call in place, a refusal at its field.
import { signOffsCreate, signOffsList } from "./api.js";
function element(selector) {
    const found = document.querySelector(selector);
    if (found === null)
        throw new Error("The screen has no " + selector);
    return found;
}
const form = element("#sign-off");
const note = element("#note");
const noteError = element("#note-error");
const answerText = element("#answer");
const count = element("#count");
async function showCount() {
    const answer = await signOffsList();
    if (answer.kind === "ok") {
        count.textContent = `${answer.value.returned} signed off so far`;
    }
}
function showRefusal(refusal) {
    const message = refusal.fields["note"];
    if (message !== undefined) {
        noteError.textContent = message;
        noteError.hidden = false;
        note.setAttribute("aria-invalid", "true");
        note.focus();
    }
    else {
        answerText.textContent = refusal.message;
    }
}
function clear() {
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
