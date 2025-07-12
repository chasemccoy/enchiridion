import { z } from 'zod/v4';
import slugifyLib from 'slugify';

/**
 * Converts string to title case (first letter of each word capitalized)
 * Works in both client and server environments
 */
export const toTitleCase = (str: string) => str.replace(/\b\w/g, (char) => char.toUpperCase());

/**
 * Transforms empty strings to null when validating with Zod
 *
 * This helper creates a Zod transformer that converts empty strings to null
 * before validating with the provided schema. Useful for handling optional
 * string fields from APIs that might return empty strings instead of null.
 *
 * @param schema - The Zod schema to apply after the transformation
 * @returns A Zod schema that transforms empty strings to null before validation
 * @example
 * const nameSchema = emptyStringToNull(z.string())
 * // '' -> null, 'value' -> 'value'
 */
export const emptyStringToNull = <T extends z.ZodTypeAny>(schema: T) =>
  z.preprocess((val) => (val === '' ? null : val), schema.nullable());

export const capitalize = (str: string) => str.charAt(0).toUpperCase() + str.slice(1);

export const formatDateToDbString = (date?: Date) => {
  if (!date) return null;

  const pad = (n: number) => n.toString().padStart(2, '0');

  const year = date.getUTCFullYear();
  const month = pad(date.getUTCMonth() + 1);
  const day = pad(date.getUTCDate());

  const hours = pad(date.getUTCHours());
  const minutes = pad(date.getUTCMinutes());
  const seconds = pad(date.getUTCSeconds());

  return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
};

export const slugify = (str: string) => {
  return slugifyLib(str, {
    lower: true,
    strict: true,
    locale: 'en',
    trim: true,
  });
};

export const formatDate = (date: Date | string, options?: { year?: boolean }) => {
  if (typeof date === 'string') {
    date = new Date(date + 'Z');
  }

  const { year = true } = options ?? {};

  return date.toLocaleDateString('en-US', {
    year: year ? 'numeric' : undefined,
    month: 'long',
    day: 'numeric',
  });
};

export function pluralize(
  count: number,
  singular: string,
  plural: string,
  { excludeCount }: { excludeCount?: boolean } = {
    excludeCount: false,
  },
): string {
  return [!excludeCount ? count : false, count === 1 ? singular : plural]
    .filter((value) => value !== false)
    .join(' ');
}
