#!/usr/bin/env node
/**
 * `ench` launcher.
 *
 * Resolves the real (post-symlink) path of this file, walks up to the project
 * root, and execs `tsx` with TSX_TSCONFIG_PATH set explicitly — so the CLI
 * works no matter the CWD or whether it was reached via `pnpm link --global`.
 *
 * Prefers the project-local tsx in node_modules/.bin; falls back to whatever
 * `tsx` is on PATH. Forwards stdio and exit code untouched.
 */

import { spawn } from 'node:child_process';
import { existsSync, realpathSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptPath = realpathSync(fileURLToPath(import.meta.url));
// backend/cli/ench/bin.js → project root
const projectRoot = resolve(dirname(scriptPath), '../../..');
const entry = resolve(projectRoot, 'backend/cli/ench/index.ts');
const tsconfig = resolve(projectRoot, 'tsconfig.json');

const localTsx = resolve(projectRoot, 'node_modules/.bin/tsx');
const tsxCmd = existsSync(localTsx) ? localTsx : 'tsx';

// CWD is left alone so user-supplied relative paths (--out, --file, restore
// targets, etc.) resolve against the user's working directory the way every
// other CLI behaves. The DB file is anchored separately in backend/db/index.ts.
const child = spawn(tsxCmd, [entry, ...process.argv.slice(2)], {
  stdio: 'inherit',
  env: { ...process.env, TSX_TSCONFIG_PATH: tsconfig },
});

child.on('error', (err) => {
  if ('code' in err && err.code === 'ENOENT') {
    process.stderr.write(
      `ench: could not find tsx. Run 'pnpm install' in ${projectRoot}, or 'pnpm add -g tsx' for a global install.\n`,
    );
    process.exit(127);
  }
  process.stderr.write(`ench: failed to launch tsx: ${err.message}\n`);
  process.exit(1);
});

child.on('exit', (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exit(code ?? 1);
});
