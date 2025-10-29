import { db } from '@db/index';
import {
  readwiseAuthors,
  readwiseDocuments,
  ReadwiseLocation,
  readwiseTags,
  records,
  type LinkInsert,
  type ReadwiseAuthorSelect,
  type ReadwiseDocumentSelect,
  type ReadwiseTagSelect,
  type RecordInsert,
} from '@db/schema';
import { slugify } from '@shared/lib/formatting';
import { createIntegrationLogger } from '@integrations/utils/log';
import { eq, sql } from 'drizzle-orm';
import { bulkInsertLinks, getPredicateId, linkRecords } from '@integrations/utils/db';

const logger = createIntegrationLogger('readwise', 'create-records');

// ------------------------------------------------------------------------
// 1. Create readwise authors and upsert corresponding index entities
// ------------------------------------------------------------------------

/**
 * Maps a Readwise author to a record
 *
 * @param author - The Readwise author to map
 * @returns A record insert object
 */
const mapReadwiseAuthorToRecord = (author: ReadwiseAuthorSelect): RecordInsert => {
  return {
    id: author.recordId ?? undefined,
    type: 'entity',
    title: author.name,
    slug: slugify((author.name || author.recordId?.toString()) ?? author.id.toString()),
    url: author.origin,
    isCurated: false,
    source: 'readwise',
  };
};

/**
 * Creates records from Readwise authors that don't have associated records yet
 */
export async function createRecordsFromReadwiseAuthors() {
  logger.start('Creating records from Readwise authors');

  const authors = await db.query.readwiseAuthors.findMany({
    where: {
      documents: {
        location: ReadwiseLocation.enum.archive, // Only map authors with at least one document in the archive.
        source: {
          ne: 'instapaper',
        },
        OR: [
          {
            tags: {
              isNotNull: true,
            },
          },
          {
            children: {
              id: {
                isNotNull: true,
              },
            },
          },
          {
            notes: {
              isNotNull: true,
            },
          },
        ],
      },
      recordId: {
        isNull: true,
      },
      deletedAt: {
        isNull: true,
      },
    },
  });

  if (authors.length === 0) {
    logger.skip('No new or updated authors to process');
    return;
  }

  logger.info(`Found ${authors.length} unmapped Readwise authors`);

  for (const author of authors) {
    const entity = mapReadwiseAuthorToRecord(author);

    logger.info(entity.slug, entity.url);

    let newRecord: { id: number };

    try {
      const [newEntity] = await db
        .insert(records)
        .values(entity)
        .onConflictDoUpdate({
          target: records.id,
          set: { recordUpdatedAt: sql`(CURRENT_TIMESTAMP)` },
        })
        .returning({ id: records.id });

      newRecord = newEntity;
    } catch (error) {
      logger.error(`Failed to create record for author ${author.name} with error: ${error}`);
      continue;
    }

    if (!newRecord) {
      logger.error(`Failed to create record for author ${author.name}`);
      continue;
    }

    logger.info(`Created record ${newRecord.id} for author ${author.name} (${author.id})`);

    await db
      .update(readwiseAuthors)
      .set({ recordId: newRecord.id })
      .where(eq(readwiseAuthors.id, author.id));

    logger.info(`Linked author ${author.name} to record ${newRecord.id}`);
  }

  logger.complete(`Processed ${authors.length} Readwise authors`);
}

// ------------------------------------------------------------------------
// 2. Upsert readwise tags (and build document–tag links)
// ------------------------------------------------------------------------

/**
 * Maps a Readwise tag to a record
 *
 * @param tag - The Readwise tag to map
 * @returns A record insert object
 */
const mapReadwiseTagToRecord = (tag: ReadwiseTagSelect): RecordInsert => {
  return {
    id: tag.recordId ?? undefined,
    type: 'concept',
    title: tag.tag,
    slug: slugify(tag.tag || tag.id.toString()),
    isCurated: false,
    source: 'readwise',
  };
};

/**
 * Creates records from Readwise tags that don't have associated records yet
 */
export async function createRecordsFromReadwiseTags() {
  logger.start('Creating records from Readwise tags');

  const tags = await db.query.readwiseTags.findMany({
    where: {
      recordId: {
        isNull: true,
      },
      deletedAt: {
        isNull: true,
      },
      tag: {
        ne: 'instapaper-favorites',
      },
    },
    with: {
      documents: true,
    },
  });

  if (tags.length === 0) {
    logger.skip('No new or updated tags to process');
    return;
  }

  logger.info(`Found ${tags.length} unmapped Readwise tags`);

  for (const tag of tags) {
    const category = mapReadwiseTagToRecord(tag);

    const [newCategory] = await db
      .insert(records)
      .values(category)
      .onConflictDoUpdate({
        target: records.id,
        set: { recordUpdatedAt: sql`(CURRENT_TIMESTAMP)` },
      })
      .returning({ id: records.id });

    if (!newCategory) {
      logger.error(`Failed to create record for tag ${tag.tag}`);
      continue;
    }

    logger.info(`Created record ${newCategory.id} for tag ${tag.tag} (${tag.id})`);

    const [updatedTag] = await db
      .update(readwiseTags)
      .set({ recordId: newCategory.id })
      .where(eq(readwiseTags.id, tag.id))
      .returning();

    if (!updatedTag) {
      logger.error(`Failed to update tag ${tag.tag} with record ${newCategory.id}`);
      continue;
    }

    logger.info(`Linked tag ${tag.tag} to record ${newCategory.id}`);

    // Link documents to tag
    for (const tagDocument of tag.documents) {
      if (tagDocument.recordId) {
        logger.info(`Linking tag ${tag.tag} to record ${tagDocument.recordId}`);
        await linkRecords(tagDocument.recordId, newCategory.id, 'tagged_with', db);
      }
    }
  }

  logger.complete(`Processed ${tags.length} Readwise tags`);
}

// ------------------------------------------------------------------------
// 3. Create readwise records (and auto-link parent-child as well as record → index relationships)
// ------------------------------------------------------------------------

/**
 * Type for a Readwise document with its children
 */
type ReadwiseDocumentWithChildren = ReadwiseDocumentSelect & {
  children: ReadwiseDocumentSelect[];
};

/**
 * Maps a Readwise document to a record
 *
 * @param document - The Readwise document to map
 * @returns A record insert object
 */
export const mapReadwiseDocumentToRecord = (
  document: ReadwiseDocumentWithChildren,
): RecordInsert => {
  // Combine notes from children and document
  const notes = [
    document.notes,
    ...document.children.filter((child) => child.category === 'note').map((child) => child.content),
  ]
    .filter(Boolean)
    .join('\n\n');

  return {
    id: document.recordId ?? undefined,
    type: 'artifact',
    title: document.title || null,
    slug: slugify(document.title || document.id.toString()),
    url: document.sourceUrl || document.url,
    content: document.content ? document.content.replace(/(?<!\n)\n(?!\n)/g, '\n\n').trim() : null, // Normalize newlines: add extra newlines between paragraphs but keep existing double newlines.
    summary: document.summary ? document.summary.trim() : null,
    notes: notes ? notes.trim() : null,
    isCurated: false,
    source: 'readwise',
    contentCreatedAt: document.contentCreatedAt,
    contentUpdatedAt: document.contentUpdatedAt,
  };
};

/**
 * Creates records from Readwise documents that don't have associated records yet
 */
export async function createRecordsFromReadwiseDocuments() {
  logger.start('Creating records from Readwise documents');

  // Query readwise documents that need records created (skip notes-only docs)
  // We only want to process documents that are in the archive or have no location set (i.e. are highlights within other documents) and whose parent is in the archive.
  const documents = await db.query.readwiseDocuments.findMany({
    with: {
      children: true,
      // TODO: copy URls from parent to children if null
      parent: true,
    },
    where: {
      OR: [
        // Either highlights (no location set) in archive
        {
          location: {
            isNull: true,
          },
          parent: {
            location: ReadwiseLocation.enum.archive,
          },
        },
        // OR documents in archive with tags, notes, or highlights (children)
        {
          location: ReadwiseLocation.enum.archive,
          OR: [
            {
              tags: {
                isNotNull: true,
              },
            },
            {
              children: {
                id: {
                  isNotNull: true,
                },
              },
            },
            {
              notes: {
                isNotNull: true,
              },
            },
          ],
        },
      ],
      recordId: {
        isNull: true,
      },
      // Exclude notes. TODO: I get document notes via the property on the parent document, but I don't currently get notes attached to highlights
      category: {
        ne: 'note',
      },
      // Exclude old Instapaper imports
      source: {
        OR: [
          {
            isNull: true,
          },
          {
            ne: 'instapaper',
          },
        ],
      },
      deletedAt: {
        isNull: true,
      },
    },
  });

  if (documents.length === 0) {
    logger.skip('No new or updated documents to process');
    return;
  }

  logger.info(`Found ${documents.length} unmapped Readwise documents`);

  // Map to store the new record IDs keyed by the corresponding readwise document ID.
  const recordMap = new Map<string, number>();

  // Step 1: Insert each document as a record.
  for (const doc of documents) {
    // Map the document into a record insertion payload.
    const recordPayload = mapReadwiseDocumentToRecord(doc);

    let newRecord: { id: number };

    try {
      const [insertedRecord] = await db
        .insert(records)
        .values(recordPayload)
        .onConflictDoUpdate({
          target: records.id,
          set: { recordUpdatedAt: sql`(CURRENT_TIMESTAMP)` },
        })
        .returning({ id: records.id });

      newRecord = insertedRecord;
    } catch (error) {
      logger.error(`Failed to create record for readwise document ${doc.id} with error: ${error}`);
      continue;
    }

    if (!newRecord) {
      logger.error(`Failed to create record for readwise document ${doc.id}`);
      continue;
    }

    logger.info(
      `Created record ${newRecord.id} for readwise document ${doc.title || doc.content?.slice(0, 20)} (${doc.id})`,
    );

    // Update the readwise document with the corresponding record id.
    await db
      .update(readwiseDocuments)
      .set({ recordId: newRecord.id })
      .where(eq(readwiseDocuments.id, doc.id));

    recordMap.set(doc.id, newRecord.id);
    logger.info(`Linked readwise document ${doc.id} to record ${newRecord.id}`);
  }

  // Step 2: Update the parent-child relationships.
  // For each document that has a non-null parentId, update the corresponding child record's parentId.
  for (const doc of documents) {
    if (doc.parentId) {
      const childRecordId = recordMap.get(doc.id);
      if (!childRecordId) continue;

      // Determine the parent's record id:
      // Either it was just created in this run or exists already.
      let parentRecordId = recordMap.get(doc.parentId);

      if (!parentRecordId) {
        const parentDoc = await db.query.readwiseDocuments.findFirst({
          where: {
            id: doc.parentId,
          },
          columns: { recordId: true },
        });
        parentRecordId = parentDoc?.recordId ?? undefined;
      }

      if (childRecordId && parentRecordId) {
        await linkRecords(childRecordId, parentRecordId, 'contained_by', db);
        logger.info(`Linked child record ${childRecordId} to parent record ${parentRecordId}`);
      } else {
        logger.warn(`Skipping linking for document ${doc.id} due to missing parent record id`);
      }
    }
  }

  // Step 3: Link records to index entries via recordCreators (for authors) and recordCategories (for tags).

  const authorIdsSet = new Set<number>();

  for (const doc of documents) {
    if (doc.authorId) {
      authorIdsSet.add(doc.authorId);
    }
  }

  const authorIds = Array.from(authorIdsSet);

  const authorsRows = await db.query.readwiseAuthors.findMany({
    where: {
      id: {
        in: authorIds,
      },
    },
    columns: { id: true, recordId: true },
  });

  const authorIndexMap = new Map<number, number>();

  for (const row of authorsRows) {
    if (row.recordId) {
      authorIndexMap.set(row.id, row.recordId);
    }
  }

  const tagSet = new Set<string>();

  for (const doc of documents) {
    if (doc.tags) {
      doc.tags.forEach((tag) => tagSet.add(tag));
    }
  }

  const tagsArray = Array.from(tagSet);

  const tagRows = await db.query.readwiseTags.findMany({
    where: {
      tag: {
        in: tagsArray,
      },
    },
    columns: { tag: true, recordId: true },
  });

  const tagIndexMap = new Map<string, number>();

  for (const row of tagRows) {
    if (row.recordId) {
      tagIndexMap.set(row.tag, row.recordId);
    }
  }

  // Bulk prepare linking arrays.
  const recordCreatorsValues: LinkInsert[] = [];
  const recordRelationsValues: LinkInsert[] = [];
  const recordFormatsValues: LinkInsert[] = [];

  const articleRecord = await db.query.records.findFirst({
    where: {
      slug: 'article',
    },
    columns: { id: true },
  });

  const videoRecord = await db.query.records.findFirst({
    where: {
      slug: 'video',
    },
    columns: { id: true },
  });

  const bookRecord = await db.query.records.findFirst({
    where: {
      slug: 'book',
    },
    columns: { id: true },
  });

  const createdByPredicateId = await getPredicateId('created_by', db);
  const taggedWithPredicateId = await getPredicateId('tagged_with', db);
  const hasFormatPredicateId = await getPredicateId('has_format', db);

  for (const doc of documents) {
    const recordId = recordMap.get(doc.id);
    if (!recordId) continue;

    // Link author via recordCreators.
    if (doc.authorId && authorIndexMap.has(doc.authorId)) {
      recordCreatorsValues.push({
        sourceId: recordId,
        targetId: authorIndexMap.get(doc.authorId)!,
        predicateId: createdByPredicateId,
      });
    }

    // Link tags via recordRelations.
    if (doc.tags && Array.isArray(doc.tags)) {
      for (const tag of doc.tags) {
        if (tagIndexMap.has(tag)) {
          recordRelationsValues.push({
            sourceId: recordId,
            targetId: tagIndexMap.get(tag)!,
            predicateId: taggedWithPredicateId,
          });
        }
      }
    }

    if (doc.category === 'article' && articleRecord) {
      recordFormatsValues.push({
        sourceId: recordId,
        targetId: articleRecord.id,
        predicateId: hasFormatPredicateId,
      });
    }

    if (doc.category === 'video' && videoRecord) {
      recordFormatsValues.push({
        sourceId: recordId,
        targetId: videoRecord.id,
        predicateId: hasFormatPredicateId,
      });
    }

    if (doc.category === 'book' && bookRecord) {
      recordFormatsValues.push({
        sourceId: recordId,
        targetId: bookRecord.id,
        predicateId: hasFormatPredicateId,
      });
    }
  }

  if (recordCreatorsValues.length > 0) {
    await bulkInsertLinks(recordCreatorsValues, db);
    logger.info(`Linked ${recordCreatorsValues.length} authors to records`);
  }

  if (recordRelationsValues.length > 0) {
    await bulkInsertLinks(recordRelationsValues, db);
    logger.info(`Linked ${recordRelationsValues.length} tags to records`);
  }

  if (recordFormatsValues.length > 0) {
    await bulkInsertLinks(recordFormatsValues, db);
  }

  logger.complete(`Processed ${recordMap.size} Readwise documents`);
}
