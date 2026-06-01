import { type Db } from '@db/index';
import { links, type LinkInsert } from '@db/schema';
import { sql } from 'drizzle-orm';
import { createIntegrationLogger } from './log';

const predicateCache = new Map<string, number>();
const recordCache = new Map<string, number>();

const logger = createIntegrationLogger('utils', 'db');

export async function getPredicateId(slug: string, db: Db): Promise<number> {
  if (predicateCache.has(slug)) return predicateCache.get(slug)!;

  const row = await db.query.predicates.findFirst({
    where: {
      slug: slug,
    },
  });

  if (!row) throw new Error(`Predicate slug ${slug} not found in DB`);
  predicateCache.set(slug, row.id);
  return row.id;
}

export async function getRecordId(slug: string, db: Db): Promise<number> {
  if (recordCache.has(slug)) return recordCache.get(slug)!;

  const row = await db.query.records.findFirst({
    where: {
      slug: slug,
    },
  });

  if (!row) throw new Error(`Record slug ${slug} not found in DB`);
  recordCache.set(slug, row.id);
  return row.id;
}

/**
 * Links a record to a target record with a specific relation type
 *
 * @param sourceId - The ID of the source record
 * @param targetId - The ID of the target record
 * @param predicateSlug - The slug of the relation type
 * @returns A promise that resolves when the link is created
 */
export async function linkRecords(
  sourceId: number,
  targetId: number,
  predicateSlug: string,
  db: Db,
): Promise<void> {
  const predicateId = await getPredicateId(predicateSlug, db);

  try {
    await db
      .insert(links)
      .values({
        sourceId,
        targetId,
        predicateId,
      })
      .onConflictDoUpdate({
        target: [links.sourceId, links.targetId, links.predicateId],
        set: {
          recordUpdatedAt: sql`(CURRENT_TIMESTAMP)`,
        },
      });

    // logger.info(
    // 	`Linked record ${sourceId} to record ${targetId} with relation type ${predicateSlug} (${predicateId})`,
    // );
  } catch (error) {
    logger.error(`Failed to link record ${sourceId} to record ${targetId}`, error);
    throw error;
  }
}

export async function bulkInsertLinks(linksToInsert: LinkInsert[], db: Db): Promise<void> {
  await db
    .insert(links)
    .values(linksToInsert)
    .onConflictDoUpdate({
      target: [links.sourceId, links.targetId, links.predicateId],
      set: {
        recordUpdatedAt: sql`(CURRENT_TIMESTAMP)`,
      },
    });
}
