import { db } from '@db/index';
import { type LinkSelect, type RecordSelect } from '@db/schema';
import type { APIResponse } from '@shared/types/api';

export interface RelatedRecordWithPath {
  record: RecordSelect;
  path: LinkSelect[];
}

/**
 * Recursively finds all records related to a given record via the `related_to` predicate.
 * Follows each related record and gets all of its related records, continuing until
 * there are no more relation predicates to follow.
 *
 * @param recordSlug - The slug of the record to find related records for
 * @returns An array of all records reachable via `related_to` predicates (excluding the starting record),
 *          each with an array of links showing the connection path to the original record
 */
export const findAllRelatedRecords = async (
  recordSlug: RecordSelect['slug'],
): Promise<RelatedRecordWithPath[]> => {
  const startRecord = await db.query.records.findFirst({
    where: { slug: recordSlug },
    columns: { id: true },
  });

  if (!startRecord) {
    throw new Error(`Record with slug "${recordSlug}" not found`);
  }

  // Pull every `related_to` link in one shot. The links_predicate_idx makes
  // this fast even with many links, and it lets the BFS run entirely in memory
  // instead of hitting the DB twice per node visited.
  const allRelatedLinks = await db.query.links.findMany({
    where: { predicate: 'related_to' },
  });

  // Build an adjacency map keyed by record id. Each entry records the link that
  // connects the two records, in whichever direction the link is oriented.
  const adjacency = new Map<number, Array<{ link: LinkSelect; otherId: number }>>();
  for (const link of allRelatedLinks) {
    if (!adjacency.has(link.sourceId)) adjacency.set(link.sourceId, []);
    if (!adjacency.has(link.targetId)) adjacency.set(link.targetId, []);
    adjacency.get(link.sourceId)!.push({ link, otherId: link.targetId });
    adjacency.get(link.targetId)!.push({ link, otherId: link.sourceId });
  }

  const visitedRecordIds = new Set<number>([startRecord.id]);
  const recordPaths = new Map<number, LinkSelect[]>();
  const queue: Array<[number, LinkSelect[]]> = [[startRecord.id, []]];

  while (queue.length > 0) {
    const [currentRecordId, currentPath] = queue.shift()!;
    const neighbors = adjacency.get(currentRecordId);
    if (!neighbors) continue;

    for (const { link, otherId } of neighbors) {
      if (visitedRecordIds.has(otherId)) continue;
      visitedRecordIds.add(otherId);
      const newPath = [...currentPath, link];
      recordPaths.set(otherId, newPath);
      queue.push([otherId, newPath]);
    }
  }

  if (recordPaths.size === 0) {
    return [];
  }

  const relatedRecordIds = Array.from(recordPaths.keys());
  const records = await db.query.records.findMany({
    where: {
      id: {
        in: relatedRecordIds,
      },
    },
  });

  return records.map((record) => ({
    record,
    path: recordPaths.get(record.id) ?? [],
  }));
};

export type FindAllRelatedRecordsAPIResponse = APIResponse<typeof findAllRelatedRecords>;
