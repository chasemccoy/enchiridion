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

export type ResultValue =
  | undefined
  | string
  | number
  | boolean
  | null
  | Date
  | ResultValue[]
  | { [key: string]: ResultValue };

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
