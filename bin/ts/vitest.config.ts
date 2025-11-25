import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Run tests in Node.js environment
    environment: "node",

    // Include test files
    include: ["src/**/*.{test,spec}.{js,mjs,cjs,ts,mts,cts,jsx,tsx}"],

    // Coverage configuration
    coverage: {
      provider: "v8",
      reporter: ["text", "json", "html"],
      include: ["src/**/*.ts"],
      exclude: [
        "src/**/*.{test,spec}.ts",
        "src/lib/testing/**",
        "src/cli.ts", // Template file
        "src/clipboard.ts", // Platform-specific, skip
        // Exclude I/O-heavy scripts per user guidance to avoid "silly" testing
        "src/downloader.ts", // User requested: don't test
        "src/converter.ts", // User requested: don't test
        "src/read-tree.ts", // User requested: don't test
        "src/wt.ts", // User requested: don't test
        "src/s3upload.ts", // Mostly AWS I/O, minimal business logic
        "src/git-cleanup.ts", // Mostly git I/O wrappers
        "src/git-prune-old.ts", // Mostly git I/O wrappers
        "src/claude-notify.ts", // Mostly tmux/notification I/O
      ],
      thresholds: {
        // Adjusted thresholds for focused testing of business logic
        lines: 15,
        functions: 19,
        branches: 15,
        statements: 15,
      },
    },

    // TypeScript configuration
    globals: true,

    // Test timeout
    testTimeout: 10000,

    // Watch settings
    watch: false,
  },
});
