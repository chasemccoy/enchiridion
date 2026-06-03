import { RecordTypeSchema } from '@shared/types';
import { z } from 'zod/v4';

// Must stay in sync with backend/db/schema/utils.ts → integrationTypeEnum.
// Inlined here so this shared module can be imported from the frontend without
// pulling in the backend graph.
const integrationSourceEnum = ['manual', 'readwise', 'twitter'] as const;
export const IntegrationSourceSchema = z.enum(integrationSourceEnum);
export type IntegrationSource = z.infer<typeof IntegrationSourceSchema>;

export const DEFAULT_LIMIT = 100;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type APIResponse<T extends (...args: any[]) => unknown> = Awaited<ReturnType<T>>;

export const IdSchema = z.coerce.number().int().positive();
export const IdParamSchema = z.object({ id: IdSchema });

export type DbId = z.infer<typeof IdSchema>;
export type IdParam = z.infer<typeof IdParamSchema>;

export type IdParamList = {
  ids: Array<IdParam>;
};

const OrderByFieldSchema = z.enum([
  'recordUpdatedAt',
  'recordCreatedAt',
  'title',
  'contentCreatedAt',
  'contentUpdatedAt',
  'id',
  'slug',
  'type',
]);

const OrderDirectionSchema = z.enum(['asc', 'desc']);

export const OrderCriteriaSchema = z.object({
  field: OrderByFieldSchema,
  direction: OrderDirectionSchema.optional().default('desc'),
});

export const RecordFiltersSchema = z.object({
  type: z
    .union([
      RecordTypeSchema.optional(),
      z.object({
        in: z.array(RecordTypeSchema),
      }),
    ])
    .optional(),
  title: z.string().nullable().optional(),
  text: z.string().nullable().optional(),
  url: z.string().nullable().optional(),
  source: z
    .union([
      IntegrationSourceSchema.optional(),
      z.object({
        in: z.array(IntegrationSourceSchema),
      }),
    ])
    .optional(),
  hasParent: z.boolean().optional(),
  /**
   * Exclude records that have a parent AND have no title — i.e. nested content
   * fragments (highlights, quotes) that are surfaced inside their parent's UI
   * and don't deserve their own row. Titled records with parents are kept.
   */
  hideUntitledChildren: z.boolean().optional(),
  isCurated: z.boolean().optional(),
  hasMedia: z.boolean().optional(),
  /** Filter by title presence. true = title is non-null, false = title is null. */
  hasTitle: z.boolean().optional(),
  /** Filter by presence in the sqlite-vec embeddings table. */
  hasEmbedding: z.boolean().optional(),
});

export const LimitSchema = z.number().int().positive();
export const OffsetSchema = z.number().int().gte(0);
export const OrderBySchema = z.array(OrderCriteriaSchema);

export const ListRecordsInputSchema = z.object({
  filters: RecordFiltersSchema.optional().default({}),
  limit: LimitSchema.optional().default(DEFAULT_LIMIT),
  offset: OffsetSchema.optional().default(0),
  orderBy: OrderBySchema.optional().default([{ field: 'recordCreatedAt', direction: 'desc' }]),
});

export type ListRecordsInput = z.input<typeof ListRecordsInputSchema>;

export const SUPPORTED_IMAGE_TYPES = [
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
] as const;

export const SUPPORTED_VIDEO_TYPES = ['video/mp4', 'video/quicktime', 'video/x-msvideo'] as const;

export const SUPPORTED_PDF_TYPES = ['application/pdf'] as const;

export const SUPPORTED_MEDIA_TYPES = [
  ...SUPPORTED_IMAGE_TYPES,
  ...SUPPORTED_VIDEO_TYPES,
  ...SUPPORTED_PDF_TYPES,
] as const;

export const MediaUploadSchema = z.object({
  recordId: IdSchema.optional(),
  altText: z.string().optional(),
});

export type MediaUploadInput = z.infer<typeof MediaUploadSchema>;
