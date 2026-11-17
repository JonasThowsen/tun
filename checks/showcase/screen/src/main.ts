// main.ts -- the showcase's single-page screen (spec/typescript.md 4): its
// component mounted in the page, in the language and the theme of the
// person's pages.

import { mount } from "svelte";
import Screen from "./Screen.svelte";
import { wordsFor } from "./words";

// The theme a person chose on the pages, which they keep in this browser
// (the kit's theme switch); without one the system's.
try {
  const theme = localStorage.getItem("tun-theme");
  if (theme === "light" || theme === "dark") document.documentElement.dataset["theme"] = theme;
} catch {
  // Storage refused: the system's theme.
}

const words = wordsFor(document.documentElement.lang);
document.title = words.title;

const target = document.getElementById("screen");
if (target === null) throw new Error("The screen has no #screen");
mount(Screen, { target, props: { words } });
