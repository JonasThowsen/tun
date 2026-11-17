// Svelte's options for the showcase's screen: each component's styles go
// into the built style sheet, never a <style> put in the page at run time,
// which the page's policy would refuse (spec/typescript.md 4).
export default {
  compilerOptions: { css: "external" },
};
