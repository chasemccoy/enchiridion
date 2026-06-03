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
  // Get the starting record
  const startRecord = await db.query.records.findFirst({
    where: { slug: recordSlug },
    columns: { id: true },
  });

  if (!startRecord) {
    throw new Error(`Record with slug "${recordSlug}" not found`);
  }

  const visitedRecordIds = new Set<number>([startRecord.id]);

  // Map from record ID to the path of links connecting it to the start record
  const recordPaths = new Map<number, LinkSelect[]>();

  // Queue stores [recordId, pathToRecord]
  const queue: Array<[number, LinkSelect[]]> = [[startRecord.id, []]];

  // Breadth-first traversal of the related_to graph
  while (queue.length > 0) {
    const [currentRecordId, currentPath] = queue.shift()!;

    // Find all records related to the current record via `related_to` predicate
    // Check both outgoing links (current -> related) and incoming links (related -> current)
    const outgoingLinks = await db.query.links.findMany({
      where: {
        sourceId: currentRecordId,
        predicate: 'related_to',
      },
      with: {
        source: {
          columns: {
            id: true,
            title: true,
            slug: true,
          },
        },
        target: {
          columns: {
            id: true,
            title: true,
            slug: true,
          },
        },
      },
    });

    const incomingLinks = await db.query.links.findMany({
      where: {
        targetId: currentRecordId,
        predicate: 'related_to',
      },
      with: {
        source: {
          columns: {
            id: true,
            title: true,
            slug: true,
          },
        },
        target: {
          columns: {
            id: true,
            title: true,
            slug: true,
          },
        },
      },
    });

    // Process outgoing links
    for (const link of outgoingLinks) {
      const relatedId = link.targetId;

      // Skip if we've already visited this record
      if (visitedRecordIds.has(relatedId)) {
        continue;
      }

      // Mark as visited
      visitedRecordIds.add(relatedId);

      // Create new path by appending this link
      const newPath = [...currentPath, link];
      recordPaths.set(relatedId, newPath);

      // Add to queue to continue traversal
      queue.push([relatedId, newPath]);
    }

    // Process incoming links
    for (const link of incomingLinks) {
      const relatedId = link.sourceId;

      // Skip if we've already visited this record
      if (visitedRecordIds.has(relatedId)) {
        continue;
      }

      // Mark as visited
      visitedRecordIds.add(relatedId);

      // Create new path by appending this link
      const newPath = [...currentPath, link];
      recordPaths.set(relatedId, newPath);

      // Add to queue to continue traversal
      queue.push([relatedId, newPath]);
    }
  }

  // Fetch all related records
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

  // Combine records with their paths
  return records.map((record) => ({
    record,
    path: recordPaths.get(record.id) ?? [],
  }));
};

export type FindAllRelatedRecordsAPIResponse = APIResponse<typeof findAllRelatedRecords>;
