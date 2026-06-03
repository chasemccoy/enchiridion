/**
 * Argument parsing for the CLI. No external dependencies; parses argv directly.
 */

import { z } from 'zod/v4';
import type { ZodType } from 'zod/v4';
import { IdSchema, LimitSchema, OffsetSchema } from '@shared/types/api';
import { createError } from './errors';
import type { ParsedArgs, RawCLIOptions, ResultValue } from './types';

// ─────────────────────────────────────────────────────────────
// Reusable CLI Schemas
// ─────────────────────────────────────────────────────────────

export const BaseOptionsSchema = z.object({
  format: z.enum(['json', 'table']).default('json'),
  help: z.boolean().default(false),
  version: z.boolean().default(false),
  debug: z.boolean().default(false),
  raw: z.boolean().default(false),
});

export type BaseOptions = z.infer<typeof BaseOptionsSchema>;

const CoercedIdSchema = z.coerce.number().int().positive();

/** Comma-separated list of IDs (e.g., "1,2,3" or just a single number) */
export const CommaSeparatedIdsSchema = z.preprocess((value) => {
  if (typeof value === 'number') return [value];
  if (typeof value === 'string') {
    return value
      .split(',')
      .map((item) => item.trim())
      .filter((item) => item.length > 0)
      .map((item) => Number(item));
  }
  return value;
}, z.array(IdSchema));

export { IdSchema, LimitSchema, OffsetSchema };

function parseOptionValue(value: string): string | number | boolean {
  if (value === 'true') return true;
  if (value === 'false') return false;
  const num = Number(value);
  if (!isNaN(num) && value.trim() !== '') return num;
  return value;
}

const SHORT_OPTIONS_WITH_VALUES = new Set(['f', 'o', 'n']);

export function parseArgs(argv: string[]): ParsedArgs {
  const options: RawCLIOptions = {};
  const positional: string[] = [];

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]!;

    if (arg === '--') {
      positional.push(...argv.slice(i + 1));
      break;
    }
    if (arg === '--help' || arg === '-h') {
      options.help = true;
    } else if (arg === '--version' || arg === '-v') {
      options.version = true;
    } else if (arg.startsWith('--')) {
      const eqIndex = arg.indexOf('=');
      if (eqIndex !== -1) {
        const key = arg.slice(2, eqIndex);
        const value = arg.slice(eqIndex + 1);
        options[key] = parseOptionValue(value);
      } else {
        const key = arg.slice(2);
        const nextArg = argv[i + 1];
        if (nextArg && !nextArg.startsWith('-')) {
          options[key] = parseOptionValue(nextArg);
          i++;
        } else {
          options[key] = true;
        }
      }
    } else if (arg.startsWith('-') && arg.length > 3 && !arg.startsWith('--') && arg[2] === '=') {
      const key = arg[1];
      const value = arg.slice(3);
      if (key) options[key] = parseOptionValue(value);
    } else if (arg.startsWith('-') && arg.length === 2) {
      const key = arg.slice(1);
      if (key === 'h') {
        options.help = true;
      } else if (key === 'v') {
        options.version = true;
      } else if (SHORT_OPTIONS_WITH_VALUES.has(key)) {
        const nextArg = argv[i + 1];
        if (nextArg && !nextArg.startsWith('-')) {
          options[key] = parseOptionValue(nextArg);
          i++;
        } else {
          options[key] = true;
        }
      } else {
        options[key] = true;
      }
    } else {
      positional.push(arg);
    }
  }

  return {
    command: positional[0] ?? '',
    subcommand: positional[1] ?? '',
    args: positional.slice(2),
    options,
  };
}

export function parseBaseOptions(options: RawCLIOptions): BaseOptions {
  const result = z.looseObject(BaseOptionsSchema.shape).safeParse(options);
  if (!result.success) {
    throw createError('VALIDATION_ERROR', result.error.message);
  }
  return result.data;
}

export function parseOptions<T>(schema: ZodType<T>, options: RawCLIOptions): T {
  const result = schema.safeParse(options);
  if (!result.success) {
    throw createError('VALIDATION_ERROR', result.error.message);
  }
  return result.data;
}

/** Read piped stdin to a string. */
async function readStdin(): Promise<string> {
  if (process.stdin.isTTY) return '';
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks).toString('utf-8');
}

/** Parse a JSON string from args or piped stdin. */
export async function parseJsonInput<T extends ResultValue>(
  schema: ZodType<T>,
  args: string[],
): Promise<T> {
  const jsonStr = args.length > 0 ? args.join(' ') : await readStdin();

  if (!jsonStr.trim()) {
    throw createError('VALIDATION_ERROR', 'No JSON input provided');
  }

  let parsed: ResultValue;
  try {
    parsed = JSON.parse(jsonStr);
  } catch {
    throw createError('VALIDATION_ERROR', 'Invalid JSON input');
  }

  const result = schema.safeParse(parsed);
  if (!result.success) {
    throw createError('VALIDATION_ERROR', result.error.message);
  }
  return result.data;
}

/** Parse a list of IDs from args (coerces strings to numbers). */
export function parseIds(args: string[]): number[] {
  const result = z.array(CoercedIdSchema).safeParse(args);
  if (!result.success) {
    throw createError('VALIDATION_ERROR', `Invalid ID(s): ${args.join(', ')}`);
  }
  return result.data;
}

/** Parse a single required ID from args. */
export function parseId(args: string[], position = 0): number {
  const arg = args[position];
  if (arg === undefined) {
    throw createError('VALIDATION_ERROR', 'ID is required');
  }
  const result = CoercedIdSchema.safeParse(arg);
  if (!result.success) {
    throw createError('VALIDATION_ERROR', `Invalid ID: ${arg}`);
  }
  return result.data;
}
