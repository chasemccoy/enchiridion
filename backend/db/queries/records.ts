import { inArray, sql } from 'drizzle-orm';
import { db } from '@db/index';
import {
  readwiseAuthors,
  readwiseDocuments,
  readwiseTags,
  records,
  type RecordInsert,
  type RecordSelect,
} from '@db/schema';
import { ListRecordsInputSchema, type APIResponse, type ListRecordsInput } from '@shared/types/api';
import { archiveUrlToWayback } from '@integrations/wayback/archive';
import { getPredicate, type PredicateSlug } from '@shared/predicates';
import { canonicalPredicateSlugEnum } from '@shared/predicates';

export const getRecord = (recordId: RecordSelect['id']) => {
  return db.query.records.findFirst({
    where: {
      id: recordId,
    },
    with: {
      outgoingLinks: {
        columns: {
          predicate: true,
        },
        with: {
          target: true,
        },
      },
      media: true,
    },
  });
};

export type GetRecordAPIResponse = APIResponse<typeof getRecord>;

export const getRecordBySlug = (slug: RecordSelect['slug']) => {
  return db.query.records.findFirst({
    where: {
      slug,
    },
    with: {
      media: true,
    },
  });
};

export type GetRecordBySlugAPIResponse = APIResponse<typeof getRecordBySlug>;

export const listRecords = async (input: ListRecordsInput = {}) => {
  const { filters, limit, offset, orderBy } = ListRecordsInputSchema.parse(input);

  const { type, title, text, url: domain, hasParent, isCurated, hasMedia } = filters || {};

  // Get slugs of predicates that match the desired types
  const creationAndDescriptionSlugs = canonicalPredicateSlugEnum.filter((slug) => {
    const p = getPredicate(slug);
    return p.type === 'creation' || p.type === 'description';
  });

  const containmentSlugs = canonicalPredicateSlugEnum.filter((slug) => {
    const p = getPredicate(slug);
    return p.type === 'containment';
  });

  const rows = await db.query.records.findMany({
    columns: {
      id: true,
      slug: true,
      title: true,
      url: true,
      type: true,
      content: true,
      summary: true,
      recordCreatedAt: true,
      recordUpdatedAt: true,
      contentCreatedAt: true,
      notes: true,
      isCurated: true,
      source: true,
    },
    with: {
      media: true,
      outgoingLinks: {
        columns: {
          predicate: true,
        },
        where: {
          predicate: {
            in: creationAndDescriptionSlugs,
          },
        },
        with: {
          target: {
            columns: {
              id: true,
              title: true,
              slug: true,
            },
          },
        },
      },
      incomingLinks: {
        columns: {
          predicate: true,
        },
      },
    },
    where: {
      type,
      title:
        title === null
          ? {
              isNull: true,
            }
          : title
            ? {
                like: `%${title}%`,
              }
            : undefined,
      OR: text
        ? [
            {
              title: { like: `%${text}%` },
            },
            {
              slug: { like: `%${text}%` },
            },
            {
              content: { like: `%${text}%` },
            },
            {
              summary: { like: `%${text}%` },
            },
            {
              notes: { like: `%${text}%` },
            },
          ]
        : undefined,
      url:
        domain === null
          ? {
              isNull: true,
            }
          : domain
            ? {
                like: `%${domain}%`,
              }
            : undefined,
      isCurated,
      ...(hasParent === true
        ? {
            outgoingLinks: {
              predicate: {
                in: containmentSlugs,
              },
            },
          }
        : hasParent === false
          ? {
              NOT: {
                outgoingLinks: {
                  predicate: {
                    in: containmentSlugs,
                  },
                },
              },
            }
          : {}),
      media: hasMedia,
    },
    limit,
    offset,
    // TODO: fix type issue
    orderBy: (records, { asc, desc }) => {
      return orderBy.map(({ field, direction }) => {
        const orderColumn = records[field];
        const lower = sql`lower(${orderColumn})`;
        return direction === 'asc' ? asc(lower) : desc(lower);
      });
    },
  });

  return rows;
};

export type ListRecordsAPIResponse = APIResponse<typeof listRecords>;

export const upsertRecord = async (record: RecordInsert) => {
  const isNewRecord = !record.id;

  const [modifiedRecord] = await db
    .insert(records)
    .values(record)
    .onConflictDoUpdate({
      target: records.id,
      set: {
        ...record,
        recordUpdatedAt: sql`(CURRENT_TIMESTAMP)`,
      },
    })
    .returning();

  if (!modifiedRecord) {
    throw new Error(`Record upsert failed. Input data:\n\n${JSON.stringify(record, null, 2)}`);
  }

  if (modifiedRecord instanceof Error) {
    throw new Error(`Record upsert failed. Input data:\n\n${JSON.stringify(record, null, 2)}`);
  }

  // Archive URL to Wayback Machine for new records
  if (isNewRecord && modifiedRecord.url) {
    archiveUrlToWayback(modifiedRecord.url);
  }

  return modifiedRecord;
};

export type UpsertRecordAPIResponse = APIResponse<typeof upsertRecord>;

export const deleteRecord = async (recordIds: Array<RecordSelect['id']>) => {
  const recordsToDelete = await db.query.records.findMany({
    where: {
      id: {
        in: recordIds,
      },
    },
    with: {
      media: true,
    },
  });

  if (recordsToDelete.length !== recordIds.length) {
    const notFound = recordIds.filter((id) => !recordsToDelete.some((r) => r.id === id));
    // eslint-disable-next-line no-console
    console.warn(`Some records were not found: ${notFound.join(', ')}`);
  }

  // Update all associated tables with a soft delete. For each table with a recordId field, set deletedAt to now

  const deletedReadwiseAuthors = await db
    .update(readwiseAuthors)
    .set({ deletedAt: sql`(CURRENT_TIMESTAMP)` })
    .where(inArray(readwiseAuthors.recordId, recordIds))
    .returning();
  for (const author of deletedReadwiseAuthors) {
    // eslint-disable-next-line no-console
    console.log(`Deleted Readwise author ${author.name} (${author.id})`);
  }

  const deletedReadwiseDocuments = await db
    .update(readwiseDocuments)
    .set({ deletedAt: sql`(CURRENT_TIMESTAMP)` })
    .where(inArray(readwiseDocuments.recordId, recordIds))
    .returning();
  for (const document of deletedReadwiseDocuments) {
    // eslint-disable-next-line no-console
    console.log(`Deleted Readwise document ${document.title} (${document.id})`);
  }

  const deletedReadwiseTags = await db
    .update(readwiseTags)
    .set({ deletedAt: sql`(CURRENT_TIMESTAMP)` })
    .where(inArray(readwiseTags.recordId, recordIds))
    .returning();
  for (const tag of deletedReadwiseTags) {
    // eslint-disable-next-line no-console
    console.log(`Deleted Readwise tag ${tag.tag} (${tag.id})`);
  }

  return db.delete(records).where(inArray(records.id, recordIds)).returning();
};

export type DeleteRecordAPIResponse = APIResponse<typeof deleteRecord>;

export const linksForRecord = async (recordId: RecordSelect['id']) => {
  return db.query.records.findFirst({
    columns: {
      id: true,
    },
    where: {
      id: recordId,
    },
    with: {
      outgoingLinks: {
        with: {
          target: {
            columns: {
              title: true,
              slug: true,
            },
          },
        },
      },
      incomingLinks: {
        with: {
          source: {
            columns: {
              title: true,
              slug: true,
              content: true,
            },
          },
        },
      },
    },
  });
};

export type LinksForRecordAPIResponse = APIResponse<typeof linksForRecord>;

/**
 * Finds all records that are linked to a given record with a specific predicate
 * @param recordId - The ID of the record to find links for
 * @param predicateSlug - The slug of the predicate to filter links by
 * @returns A list of records that are linked to the given record with the specified predicate
 * @example
 * // Find all records that are linked with "format of" predicate to record with ID 123
 * const containedRecords = await linksToRecordWithPredicate(123, 'related_to');
 */
export const linksToRecordWithPredicateSlug = async (
  recordId: RecordSelect['id'],
  predicateSlug: PredicateSlug,
) => {
  return db.query.records.findMany({
    where: {
      OR: [
        {
          outgoingLinks: {
            predicate: predicateSlug,
            target: {
              id: recordId,
            },
          },
        },
        {
          incomingLinks: {
            predicate: predicateSlug,
            source: {
              id: recordId,
            },
          },
        },
      ],
    },
  });
};

export type LinksToRecordWithPredicateSlugAPIResponse = APIResponse<
  typeof linksToRecordWithPredicateSlug
>;
