import { z } from 'zod/v4';

export * from './predicates';

export const recordTypeEnum = [
  'entity', // an actor in the world, has will
  'concept', // a category, idea, or abstraction
  'artifact', // physical or digital objects, content, or media
  'note', // a personal, first-class jotting; sits beside records
] as const;

export const RecordTypeSchema = z.enum(recordTypeEnum);
export type RecordType = z.infer<typeof RecordTypeSchema>;

/**
 * Slug of the record representing the app owner. New notes are auto-linked to
 * this record via the `created_by` predicate, and the seed creates it.
 */
export const OWNER_RECORD_SLUG = 'chase-mccoy';
