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
import {
  containmentPredicateSlugs,
  creationPredicateSlugs,
  descriptionPredicateSlugs,
  OWNER_RECORD_SLUG,
  type PredicateSlug,
} from '@shared/types';
import { archiveUrlToWayback } from '@integrations/wayback/archive';
import { embedRecord, removeRecordEmbeddings } from '@integrations/embeddings';
import { upsertLink } from '@db/queries/links';

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

// Predicates whose outgoing edges we surface inline on each record card.
// Creation = "by <author>", description = tags/format, containment = parent
// (search results show the parent inline so a hit knows which book/article it
// came from).
const inlineOutgoingPredicateSlugs = [
  ...creationPredicateSlugs,
  ...descriptionPredicateSlugs,
  ...containmentPredicateSlugs,
];

export const listRecords = async (input: ListRecordsInput = {}) => {
  const { filters, limit, offset, orderBy } = ListRecordsInputSchema.parse(input);

  const {
    type,
    title,
    text,
    url: domain,
    source,
    hasParent,
    hideUntitledChildren,
    isCurated,
    isPinned,
    hasMedia,
    hasTitle,
    ids,
  } = filters || {};

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
      isPinned: true,
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
            in: inlineOutgoingPredicateSlugs,
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
      source,
      // `ids: undefined` = no id filter (normal list); `ids: []` = match nothing
      // (a caller asked for an empty set, e.g. a record with no links — don't
      // fall through to returning every record).
      ...(ids !== undefined ? { id: { in: ids } } : {}),
      title:
        title === null || hasTitle === false
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
      isPinned,
      ...(hasParent === true
        ? {
            outgoingLinks: {
              predicate: {
                in: containmentPredicateSlugs,
              },
            },
          }
        : hasParent === false
          ? {
              NOT: {
                outgoingLinks: {
                  predicate: { in: containmentPredicateSlugs },
                },
              },
            }
          : {}),
      // Exclude untitled records that have a containment parent (highlights,
      // quotes, etc. shown inline on the parent's page). Drizzle's NOT inverts
      // the conjunction, so this keeps records where EITHER title is non-null
      // OR there's no containment outgoing link.
      ...(hideUntitledChildren === true
        ? {
            NOT: {
              title: { isNull: true },
              outgoingLinks: {
                predicate: { in: containmentPredicateSlugs },
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

export const upsertRecord = async (record: RecordInsert, options: { embed?: boolean } = {}) => {
  const { embed = true } = options;
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

  // Auto-link a newly-created note to the owner record via `created_by`, so
  // notes join the graph from creation. Idempotent (upsertLink dedupes on the
  // source/target/predicate triple) and guarded on the owner existing.
  if (isNewRecord && modifiedRecord.type === 'note') {
    const owner = await db.query.records.findFirst({
      where: { slug: OWNER_RECORD_SLUG },
      columns: { id: true },
    });
    if (owner && owner.id !== modifiedRecord.id) {
      await upsertLink({
        sourceId: modifiedRecord.id,
        targetId: owner.id,
        predicate: 'created_by',
      });
    }
  }

  // Generate/refresh the record's embedding in the background. Best-effort:
  // embedRecord never throws and no-ops when OPENAI_API_KEY is unset.
  if (embed) {
    void embedRecord(modifiedRecord);
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

  const deleted = await db.delete(records).where(inArray(records.id, recordIds)).returning();

  // Virtual/vec tables can't use FK cascade, so prune embeddings explicitly.
  removeRecordEmbeddings(recordIds);

  return deleted;
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
 * // Find all records that are linked with "related_to" predicate to record with ID 123
 * const relatedRecords = await linksToRecordWithPredicateSlug(123, 'related_to');
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
