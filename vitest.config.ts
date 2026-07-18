import * as path from 'node:path';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  resolve: {
    alias: {
      '@db': path.resolve(import.meta.dirname, 'backend/db'),
      '@api': path.resolve(import.meta.dirname, 'backend/api'),
      '@shared': path.resolve(import.meta.dirname, 'shared'),
      '@app': path.resolve(import.meta.dirname, 'app'),
      '@integrations': path.resolve(import.meta.dirname, 'backend/integrations'),
    },
  },
  test: {
    include: ['tests/**/*.test.ts'],
    // Each test file gets its own forked process — and, via tests/setup.ts, its
    // own scratch database — so files can run in parallel without sharing state.
    pool: 'forks',
    setupFiles: ['tests/setup.ts'],
    // Archive tests run a real (local, static) capture; give them headroom.
    testTimeout: 30_000,
    server: {
      deps: {
        // amber is a link: dependency whose entry point is raw TypeScript —
        // inline it so vitest transpiles it instead of handing it to Node.
        inline: ['amber'],
      },
    },
  },
});
