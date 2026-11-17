// The showcase's screen, built by Vite with Svelte's plugin into dist/
// (spec/typescript.md 6): served at /sign-off, so its files' paths are under
// it, and every asset a file of its own, never a data: URL the page's policy
// would refuse.
import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";

export default defineConfig({
  base: "/sign-off/",
  plugins: [svelte()],
  build: { outDir: "dist", assetsInlineLimit: 0 },
});
