import { z } from 'zod/v4';

export const recordTypeEnum = [
  'entity', // an actor in the world, has will
  'concept', // a category, idea, or abstraction
  'artifact', // physical or digital objects, content, or media
] as const;

export const RecordTypeSchema = z.enum(recordTypeEnum);
export type RecordType = z.infer<typeof RecordTypeSchema>;
