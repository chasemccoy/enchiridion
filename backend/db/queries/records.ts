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

export const getRecord = (recordId: RecordSelect['id']) => {
  return db.query.records.findFirst({
    where: {
      id: recordId,
    },
    with: {
      outgoingLinks: {
        columns: {
          predicateId: true,
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
          predicateId: true,
        },
        where: {
          predicate: {
            type: {
              in: ['creation', 'description'],
            },
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
          predicate: true,
        },
      },
      incomingLinks: {
        columns: {
          predicateId: true,
        },
        with: {
          predicate: {
            columns: {
              type: true,
            },
          },
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
                type: 'containment',
              },
            },
          }
        : hasParent === false
          ? {
              NOT: {
                outgoingLinks: {
                  predicate: { type: 'containment' },
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

  return modifiedRecord;
};

export type UpsertRecordAPIResponse = APIResponse<typeof upsertRecord>;

export const markAsCurated = async (recordIds: Array<RecordSelect['id']>) => {
  const updatedRecords = await db
    .update(records)
    .set({ isCurated: true, recordUpdatedAt: sql`(CURRENT_TIMESTAMP)` })
    .where(inArray(records.id, recordIds))
    .returning({
      id: records.id,
    });

  if (updatedRecords.length !== recordIds.length) {
    throw new Error(
      `Failed to update records. Input data:\n\n${JSON.stringify(recordIds, null, 2)}`,
    );
  }

  return updatedRecords.map((r) => r.id);
};

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
          predicate: {
            with: {
              inverse: {
                columns: {
                  name: true,
                },
              },
            },
          },
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
          predicate: {
            with: {
              inverse: {
                columns: {
                  name: true,
                },
              },
            },
          },
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
