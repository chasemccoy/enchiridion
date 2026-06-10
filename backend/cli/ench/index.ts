#!/usr/bin/env tsx
/**
 * ench - Enchiridion CLI
 *
 * Stdio interface to the knowledge base. JSON output by default; agents and
 * scripts pipe everything through `jq`. Use --format=table for humans.
 *
 * Usage:
 *   ench <command> <subcommand> [args...] [options]
 */

import { existsSync, readFileSync, realpathSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs, parseBaseOptions, type BaseOptions } from './lib/args';
import { createError, CLICommandError } from './lib/errors';
import { formatError, formatOutput } from './lib/output';
import type { CommandHandler, ResultValue, SuccessResult } from './lib/types';

// ─────────────────────────────────────────────────────────────
// Env discovery: CWD .env → project-root .env → ~/.secrets
// ─────────────────────────────────────────────────────────────

function loadEnvFile(filePath: string): void {
  try {
    const content = readFileSync(filePath, 'utf-8');
    for (const line of content.split('\n')) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;
      const match = trimmed.match(/^([^=]+)=(.*)$/);
      if (!match?.[1] || match[2] === undefined) continue;
      const key = match[1].trim();
      let value = match[2].trim();
      if (
        (value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))
      ) {
        value = value.slice(1, -1);
      }
      if (!process.env[key]) process.env[key] = value;
    }
  } catch {
    // Silent — env loading is best-effort.
  }
}

const cwdEnv = resolve(process.cwd(), '.env');
if (existsSync(cwdEnv)) {
  loadEnvFile(cwdEnv);
} else {
  try {
    const scriptPath = fileURLToPath(import.meta.url);
    const realScriptPath = realpathSync(scriptPath);
    // backend/cli/ench/index.ts → project root
    const projectRoot = resolve(dirname(realScriptPath), '../../..');
    const projectEnv = join(projectRoot, '.env');
    if (existsSync(projectEnv)) {
      loadEnvFile(projectEnv);
    } else {
      const homeSecrets = join(process.env.HOME || '~', '.secrets');
      if (existsSync(homeSecrets)) loadEnvFile(homeSecrets);
    }
  } catch {
    const homeSecrets = join(process.env.HOME || '~', '.secrets');
    if (existsSync(homeSecrets)) loadEnvFile(homeSecrets);
  }
}

// Commands are loaded lazily so the env-loading above takes effect before any
// module that opens a DB connection at import time runs.
let commands: Record<string, Record<string, CommandHandler>> | null = null;

async function loadCommands() {
  if (commands) return commands;
  const [records, search, links, media, sync, db, wayback] = await Promise.all([
    import('./commands/records'),
    import('./commands/search'),
    import('./commands/links'),
    import('./commands/media'),
    import('./commands/sync'),
    import('./commands/db'),
    import('./commands/wayback'),
  ]);
  commands = { records, search, links, media, sync, db, wayback };
  return commands;
}

function withDuration<T extends ResultValue>(
  result: SuccessResult<T>,
  startTime: number,
): SuccessResult<T> {
  const duration = Math.round(performance.now() - startTime);
  const meta = result.meta ? { ...result.meta, duration } : { duration };
  return { ...result, meta };
}

const HELP_TEXT = `
ench - Enchiridion CLI

Usage:
  ench <command> <subcommand> [args...] [options]

Commands:
  records get <id...> [--links]        Fetch record(s) by ID
  records list [filters]               List records
  records create <json>                Create a record
  records update <id> <json>           Update a record
  records bulk-update <ids> <json>     Bulk-update records
  records delete <id...>               Delete record(s)
  records merge <src> <target>         Merge src into target
  records embed <id...> [--force]      Force-regenerate embedding(s)
  records tree <id...>                 Family tree (parent/siblings/children)
  records children <id>                Direct children of a record
  records parent <id>                  Direct parent of a record
  records similar <id...> [--limit=N]  Records similar by embedding

  search <query>                       Hybrid (text + semantic, RRF merge)
  search text <query>                  Trigram substring search
  search semantic <query>              Vector search
  search similar <id...>               Similarity by record id

  links list <record-id> [...]         List links for a record
  links create <json>                  Create / upsert a link
  links delete <id...>                 Delete link(s)
  links predicates                     Dump predicate vocabulary

  media get <id...> [--with-record]    Fetch media item(s)
  media list [...]                     List media
  media create --record=<id> ...       Create media from URL or file
  media update <id> <json>             Update media metadata

  sync                                 Run all integrations
  sync readwise                        Sync Readwise documents
  sync twitter                         (no-op — twitter is on-demand only)
  sync embeddings [--force]            Backfill record embeddings

  db backup [--out=path]               Online backup of the SQLite file
  db restore <path>                    Restore database from backup
  db reset                             Reset (delegates to pnpm db:reset)
  db status                            Database stats and counts

  wayback archive <url-or-id>          Submit a URL to web.archive.org/save
  wayback status <url>                 Most recent snapshot for URL

Records List Filters:
  --type=<types>          artifact|entity|concept (comma-separated)
  --source=<source>       manual|readwise|twitter (comma-separated)
  --curated[=BOOL]        Filter by isCurated
  --parent[=BOOL]         Has containment parent
  --media[=BOOL]          Has media attached
  --has-title[=BOOL]      title is non-null
  --embedding[=BOOL]      Has stored embedding (post-filter)
  --order=<field:dir,...> Order by (e.g. recordCreatedAt:desc,title:asc)
  --limit=N --offset=N    Pagination
  --full                  Return full records instead of id list

Global Options:
  --format=json|table     Output format (default: json)
  --raw                   Output just data without {data,meta} wrapper
  --dry-run, -n           Show what would change without doing it (mutations)
  --debug                 Print stack traces on errors
  --version, -v           Print package version
  --help, -h              Show this help

Examples:
  ench records list --type=artifact --curated --limit=5 --full
  ench records list --curated=false             # records needing curation
  ench records get 1 --links
  ench records similar 1 --limit=5
  ench search "knowledge graph"
  ench search semantic "ways of thinking about links" --limit=5
  ench links predicates
  ench db status
  ench db backup --out=/tmp/ench-backup.sqlite
  ench wayback status https://example.com
`.trim();

async function main(): Promise<void> {
  const startTime = performance.now();
  const { command, subcommand, args, options: rawOptions } = parseArgs(process.argv.slice(2));

  let baseOptions: BaseOptions;
  try {
    baseOptions = parseBaseOptions(rawOptions);
  } catch (error) {
    process.stderr.write(formatError(error as Error, 'json') + '\n');
    process.exit(1);
  }

  if (baseOptions.version) {
    try {
      const scriptPath = fileURLToPath(import.meta.url);
      const realScriptPath = realpathSync(scriptPath);
      const projectRoot = resolve(dirname(realScriptPath), '../../..');
      const pkg = JSON.parse(readFileSync(join(projectRoot, 'package.json'), 'utf-8')) as {
        version: string;
      };
      process.stdout.write(pkg.version + '\n');
    } catch {
      process.stdout.write('unknown\n');
    }
    process.exit(0);
  }

  if (baseOptions.help || (!command && !subcommand)) {
    process.stdout.write(HELP_TEXT + '\n');
    process.exit(0);
  }

  const debug = baseOptions.debug;
  const cmds = await loadCommands();

  // Special case: `search <query>` with no subcommand means hybrid search.
  if (
    command === 'search' &&
    subcommand &&
    !['text', 'semantic', 'similar', 'hybrid'].includes(subcommand)
  ) {
    return runHandler(
      cmds.search!.hybrid!,
      [subcommand, ...args],
      rawOptions,
      baseOptions,
      startTime,
      debug,
    );
  }

  // Special case: `sync` without subcommand runs all.
  if (command === 'sync') {
    return runHandler(
      cmds.sync!.run!,
      subcommand ? [subcommand, ...args] : args,
      rawOptions,
      baseOptions,
      startTime,
      debug,
    );
  }

  const commandAliases: Record<string, string> = { record: 'records', link: 'links' };
  const resolvedCommand = commandAliases[command] ?? command;
  const commandGroup = cmds[resolvedCommand];
  if (!commandGroup) {
    const err = createError(
      'UNKNOWN_COMMAND',
      `Unknown command: ${command}. Run 'ench --help' for usage.`,
    );
    process.stderr.write(formatError(err, baseOptions.format) + '\n');
    process.exit(1);
  }

  const handler = commandGroup[subcommand];
  if (!handler) {
    const available = Object.keys(commandGroup).join(', ');
    const err = createError(
      'UNKNOWN_COMMAND',
      `Unknown subcommand: ${resolvedCommand} ${subcommand}. Available: ${available}`,
    );
    process.stderr.write(formatError(err, baseOptions.format) + '\n');
    process.exit(1);
  }

  return runHandler(handler, args, rawOptions, baseOptions, startTime, debug);
}

async function runHandler(
  handler: CommandHandler,
  args: string[],
  rawOptions: Record<string, string | boolean | number | undefined>,
  baseOptions: BaseOptions,
  startTime: number,
  debug: boolean,
): Promise<never> {
  try {
    const result = withDuration(await handler(args, rawOptions), startTime);
    process.stdout.write(formatOutput(result, baseOptions.format, baseOptions.raw) + '\n');
    process.exit(0);
  } catch (error) {
    const normalized = error instanceof Error ? error : new Error(String(error));
    process.stdout.write(formatError(normalized, baseOptions.format) + '\n');
    if (debug && normalized.stack) {
      process.stderr.write(normalized.stack + '\n');
    } else if (normalized instanceof CLICommandError) {
      process.stderr.write(`ench: ${normalized.code}: ${normalized.message}\n`);
    } else {
      process.stderr.write(`ench: ${normalized.message}\n`);
    }
    process.exit(1);
  }
}

void main();
