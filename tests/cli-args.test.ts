/**
 * CLI argument parsing — the pure logic every `ench` invocation goes through.
 */
import { describe, expect, it } from 'vitest';
import {
  CommaSeparatedIdsSchema,
  parseArgs,
  parseBaseOptions,
  parseId,
  parseIds,
} from '../backend/cli/ench/lib/args';

describe('parseArgs', () => {
  it('splits command, subcommand, and positional args', () => {
    expect(parseArgs(['records', 'get', '42'])).toEqual({
      command: 'records',
      subcommand: 'get',
      args: ['42'],
      options: {},
    });
  });

  it('parses --key=value with type coercion', () => {
    const { options } = parseArgs(['records', 'list', '--limit=5', '--curated=true', '--q=hello']);
    expect(options).toEqual({ limit: 5, curated: true, q: 'hello' });
  });

  it('parses --key value and bare --flag forms', () => {
    const { options } = parseArgs(['search', 'text', '--limit', '10', '--debug']);
    expect(options).toEqual({ limit: 10, debug: true });
  });

  it('maps -h and -v to help and version', () => {
    expect(parseArgs(['-h']).options.help).toBe(true);
    expect(parseArgs(['-v']).options.version).toBe(true);
  });

  it('treats everything after -- as positional', () => {
    const parsed = parseArgs(['records', 'create', '--', '--not-a-flag']);
    expect(parsed.args).toEqual(['--not-a-flag']);
    expect(parsed.options).toEqual({});
  });
});

describe('parseBaseOptions', () => {
  it('applies defaults and passes through unknown keys', () => {
    const options = parseBaseOptions({ limit: 5 });
    expect(options.format).toBe('json');
    expect(options.help).toBe(false);
  });

  it('rejects an invalid format', () => {
    expect(() => parseBaseOptions({ format: 'yaml' })).toThrow();
  });
});

describe('id parsing', () => {
  it('parseId coerces a numeric string', () => {
    expect(parseId(['42'])).toBe(42);
  });

  it('parseId rejects missing and non-numeric values', () => {
    expect(() => parseId([])).toThrow(/ID is required/);
    expect(() => parseId(['abc'])).toThrow(/Invalid ID/);
  });

  it('parseIds coerces a list and rejects bad entries', () => {
    expect(parseIds(['1', '2'])).toEqual([1, 2]);
    expect(() => parseIds(['1', 'x'])).toThrow(/Invalid ID/);
  });

  it('CommaSeparatedIdsSchema splits and trims', () => {
    expect(CommaSeparatedIdsSchema.parse('1, 2,3')).toEqual([1, 2, 3]);
    expect(CommaSeparatedIdsSchema.parse(7)).toEqual([7]);
  });
});
