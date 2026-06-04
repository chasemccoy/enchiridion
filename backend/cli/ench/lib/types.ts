/**
 * CLI type definitions for the `ench` command.
 */

export type OutputFormat = 'json' | 'table';

export interface ParsedArgs {
  command: string;
  subcommand: string;
  args: string[];
  options: RawCLIOptions;
}

export type RawCLIOptions = Record<string, string | boolean | number | undefined>;

/**
 * A value safe to ship through the CLI's JSON envelope.
 *
 * The object case uses lowercase `object` instead of `{[k: string]: ResultValue}`
 * on purpose: TypeScript's index-signature check is strict and would reject any
 * typed interface (`RecordSelect`, `SimilarRecord`, …) that doesn't explicitly
 * declare `[k: string]: …` — even though those interfaces are perfectly
 * JSON-serialisable. `object` accepts any non-primitive without that ceremony,
 * which gives us a meaningful constraint (no functions, no symbols, no naked
 * `unknown`) without forcing every domain type to grow an index signature.
 */
export type ResultValue =
  | string
  | number
  | boolean
  | null
  | undefined
  | Date
  | readonly ResultValue[]
  | object;

export interface ResultMeta {
  count?: number;
  total?: number;
  limit?: number;
  offset?: number;
  duration?: number;
}

export interface SuccessResult<T extends ResultValue = ResultValue> {
  data: T;
  meta?: ResultMeta;
}

export interface CLIError {
  code: ErrorCode;
  message: string;
  details?: string;
}

export interface ErrorResult {
  error: CLIError;
}

export type ErrorCode =
  | 'VALIDATION_ERROR'
  | 'NOT_FOUND'
  | 'CONFLICT'
  | 'DB_ERROR'
  | 'IO_ERROR'
  | 'EMBEDDING_ERROR'
  | 'PERMISSION_DENIED'
  | 'UNKNOWN_COMMAND'
  | 'INTERNAL_ERROR';

export type CommandHandler<T extends ResultValue = ResultValue> = (
  args: string[],
  options: RawCLIOptions,
) => Promise<SuccessResult<T>>;

export type CommandMap = Record<string, Record<string, CommandHandler>>;
