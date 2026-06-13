import { defineConfig } from "vitest/config";
import { sveltekit } from "@sveltejs/kit/vite";

// Vitest runs against the pure TypeScript logic (e.g. src/lib/util/*.test.ts).
// The SvelteKit plugin is included so the `$lib` alias resolves the same way it
// does in the app build — no separate alias table to drift out of sync.
export default defineConfig({
  plugins: [sveltekit()],
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"],
  },
});
