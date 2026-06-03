import { z } from 'zod/v4';

export const RecordFiltersSchema = z.object({
  title: z.string().nullable().optional(),
  text: z.string().nullable().optional(),
  url: z.string().nullable().optional(),
  hasParent: z.boolean().optional(),
  isCurated: z.boolean().optional(),
  hasMedia: z.boolean().optional(),
});

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
  field: OrderByFieldSchema.optional().default('recordCreatedAt'),
  direction: OrderDirectionSchema.optional().default('desc'),
});

export const LimitSchema = z.number().int().positive();
export const OffsetSchema = z.number().int().gte(0);
export const OrderBySchema = z.array(OrderCriteriaSchema);
