/**
 * shared/lib/formatting — pure functions, with slugify first among equals:
 * slugs are record identity, so its behavior is load-bearing.
 */
import { describe, expect, it } from 'vitest';
import { z } from 'zod/v4';
import {
  capitalize,
  emptyStringToNull,
  formatDate,
  formatDateToDbString,
  pluralize,
  slugify,
  toTitleCase,
} from '@shared/lib/formatting';

describe('slugify', () => {
  it('lowercases, strips punctuation, and hyphenates', () => {
    expect(slugify('Hello, World!')).toBe('hello-world');
    expect(slugify("What's New?")).toBe('whats-new');
    expect(slugify('  padded  title  ')).toBe('padded-title');
  });

  it('is stable for already-slugged input', () => {
    expect(slugify('already-a-slug')).toBe('already-a-slug');
  });
});

describe('string helpers', () => {
  it('toTitleCase capitalizes each word', () => {
    expect(toTitleCase('hello wide world')).toBe('Hello Wide World');
  });

  it('capitalize touches only the first character', () => {
    expect(capitalize('hello world')).toBe('Hello world');
  });

  it('pluralize picks the right form and can drop the count', () => {
    expect(pluralize(1, 'record', 'records')).toBe('1 record');
    expect(pluralize(2, 'record', 'records')).toBe('2 records');
    expect(pluralize(0, 'record', 'records')).toBe('0 records');
    expect(pluralize(2, 'record', 'records', { excludeCount: true })).toBe('records');
  });
});

describe('date helpers', () => {
  it('formatDateToDbString renders UTC in SQLite format', () => {
    expect(formatDateToDbString(new Date(Date.UTC(2026, 0, 2, 3, 4, 5)))).toBe(
      '2026-01-02 03:04:05',
    );
    expect(formatDateToDbString(null)).toBeNull();
    expect(formatDateToDbString(undefined)).toBeNull();
  });

  it('formatDate treats DB strings as UTC', () => {
    // Midday UTC keeps the calendar date stable in any plausible local zone.
    expect(formatDate('2026-06-18 12:00:00')).toBe('June 18, 2026');
    expect(formatDate('2026-06-18 12:00:00', { year: false })).toBe('June 18');
  });
});

describe('emptyStringToNull', () => {
  it('maps empty string to null and passes values through', () => {
    const schema = emptyStringToNull(z.string());
    expect(schema.parse('')).toBeNull();
    expect(schema.parse('value')).toBe('value');
    expect(schema.parse(null)).toBeNull();
  });
});
