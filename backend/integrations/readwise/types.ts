import { z } from 'zod/v4';
import { ReadwiseCategory, ReadwiseLocation } from '@db/schema/readwise';
import { emptyStringToNull } from '@shared/lib/formatting';

const ReadwiseTagSchema = z.object({
  name: z.string(),
  type: z.string(),
  created: z.number(),
});

export const ReadwiseArticleSchema = z.object({
  id: z.string(),
  title: z.string().nullable(),
  summary: z.string().nullable(),
  author: z.string().nullable(),
  site_name: z.string().nullable(),
  source: z.string().nullable(),
  content: z.string().nullable(),
  html_content: z.string().optional(),
  notes: z.string().nullable(),
  category: ReadwiseCategory,
  location: ReadwiseLocation.nullable(),
  tags: z
    .record(z.string(), ReadwiseTagSchema)
    .nullable()
    .transform((val) => {
      const keys = Object.keys(val ?? {});
      return keys.length > 0 ? keys : null;
    }),
  word_count: z.number().int().nullable(),
  url: z.url(), // Internal Readwise URL
  source_url: emptyStringToNull(z.url().nullable()),
  image_url: emptyStringToNull(z.url().nullable()),
  parent_id: z.string().nullable(),
  reading_progress: z.number().min(0).max(1),
  saved_at: z.coerce.date(),
  created_at: z.coerce.date(),
  updated_at: z.coerce.date(),
  last_moved_at: z.coerce.date(),
  published_date: z.coerce.date().nullable(),
  first_opened_at: z.coerce.date().nullable(),
  last_opened_at: z.coerce.date().nullable(),
});

export const ReadwiseArticlesResponseSchema = z.object({
  results: z.array(ReadwiseArticleSchema),
  nextPageCursor: z.string().nullable(),
  count: z.number(),
});

export type ReadwiseArticle = z.infer<typeof ReadwiseArticleSchema>;
export type ReadwiseArticlesResponse = z.infer<typeof ReadwiseArticlesResponseSchema>;

// Legacy API v2 schemas for book highlights
const ReadwiseBookTagSchema = z.object({
  id: z.number(),
  name: z.string(),
});

export const ReadwiseBookHighlightSchema = z.object({
  id: z.number(),
  is_deleted: z.boolean(),
  text: z.string(),
  location: z.number().nullable(),
  location_type: z.string().nullable(),
  note: z.string().nullable(),
  color: z.string().nullable(),
  highlighted_at: z.coerce.date(),
  created_at: z.coerce.date(),
  updated_at: z.coerce.date(),
  external_id: z.string().nullable(),
  end_location: z.number().nullable(),
  url: z.string().nullable(),
  book_id: z.number(),
  tags: z.array(ReadwiseBookTagSchema),
  is_favorite: z.boolean(),
  is_discard: z.boolean(),
  readwise_url: z.string().nullable(),
});

export const ReadwiseBookSchema = z.object({
  user_book_id: z.number(),
  is_deleted: z.boolean(),
  title: z.string(),
  author: z.string().nullable(),
  readable_title: z.string(),
  source: z.string().nullable(),
  cover_image_url: z.string().nullable(),
  unique_url: z.string().nullable(),
  book_tags: z.array(ReadwiseBookTagSchema),
  category: z.string().nullable(),
  document_note: z.string().nullable(),
  summary: z.string().nullable(),
  readwise_url: z.string().nullable(),
  source_url: z.string().nullable(),
  external_id: z.string().nullable(),
  asin: z.string().nullable(),
  highlights: z.array(ReadwiseBookHighlightSchema),
});

export const ReadwiseBookExportResponseSchema = z.object({
  count: z.number(),
  nextPageCursor: z.string().nullable(),
  results: z.array(ReadwiseBookSchema),
});

export type ReadwiseBookHighlight = z.infer<typeof ReadwiseBookHighlightSchema>;
export type ReadwiseBook = z.infer<typeof ReadwiseBookSchema>;
export type ReadwiseBookExportResponse = z.infer<typeof ReadwiseBookExportResponseSchema>;
