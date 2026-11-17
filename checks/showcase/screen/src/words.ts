// words.ts -- the screen's words in each language the showcase has
// (spec/typescript.md 4): the server writes the language of the person's
// pages into <html lang>, and the screen picks its words by it.

export interface Words {
  title: string;
  count: (n: number) => string;
  note: string;
  signOff: string;
  signedOff: (by: string, credential: string) => string;
  noAnswer: string;
  notUnderstood: (status: number) => string;
}

const english: Words = {
  title: "Sign off",
  count: (n) => `${n} signed off so far`,
  note: "Note",
  signOff: "Sign off",
  signedOff: (by, credential) => `Signed off by ${by} (${credential})`,
  noAnswer: "No answer came. Try again.",
  notUnderstood: (status) => `The answer was not understood (${status}).`,
};

const norwegian: Words = {
  title: "Signer",
  count: (n) => `${n} signert så langt`,
  note: "Notat",
  signOff: "Signer",
  signedOff: (by, credential) => `Signert av ${by} (${credential})`,
  noAnswer: "Det kom ikke noe svar. Prøv igjen.",
  notUnderstood: (status) => `Svaret ble ikke forstått (${status}).`,
};

/** The words for LANGUAGE, a language code such as "nb"; English for any other. */
export function wordsFor(language: string): Words {
  return language === "nb" ? norwegian : english;
}
