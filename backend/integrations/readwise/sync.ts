import type { ReadwiseArticle } from './types';
import { runIntegration } from '@integrations/utils/runIntegration';
import {
  createReadwiseAuthors,
  createReadwiseTags,
  fetchReadwiseDocuments,
  getMostRecentUpdateTime,
  logger,
  mapReadwiseArticleToDocument,
  sortDocumentsByHierarchy,
} from '@integrations/readwise/utils';
import { db } from '@db/index';
import { readwiseDocuments } from '@db/schema';
import { sql } from 'drizzle-orm';
import {
  createRecordsFromReadwiseAuthors,
  createRecordsFromReadwiseDocuments,
  createRecordsFromReadwiseTags,
  type NewRecordInfo,
} from '@integrations/readwise/records';
import { syncReadwiseBooks } from '@integrations/readwise/legacy-sync';
import { report } from '@integrations/utils/progress';
import { pluralize } from '@shared/lib/formatting';

/**
 * Synchronizes Readwise documents with the database
 *
 * This function:
 * 1. Determines the last sync point
 * 2. Fetches new or updated documents from the API
 * 3. Processes and stores the documents
 * 4. Creates related entities (authors, tags, records)
 *
 * @throws Error if API requests fail
 */
export async function syncReadwiseDocuments(integrationRunId: number) {
  try {
    logger.info('Starting Readwise documents sync');
    report({ type: 'phase', phase: 'documents', status: 'start' });

    // Step 1: Determine last sync point
    const lastUpdateTime = await getMostRecentUpdateTime();

    // Step 2: Fetch all documents
    logger.info('Fetching documents from Readwise API');
    const allDocuments: ReadwiseArticle[] = [];
    let nextPageCursor: string | null = null;

    do {
      const response = await fetchReadwiseDocuments(
        nextPageCursor ?? undefined,
        lastUpdateTime ?? undefined,
      );
      allDocuments.push(...response.results);
      nextPageCursor = response.nextPageCursor;

      logger.info(`Retrieved ${response.results.length} documents (total: ${allDocuments.length})`);
      report({
        type: 'progress',
        phase: 'documents',
        message: `Fetched ${pluralize(allDocuments.length, 'document', 'documents')} so far`,
        current: allDocuments.length,
      });
    } while (nextPageCursor);

    // Step 3: Process documents
    let successCount = 0;
    if (allDocuments.length > 0) {
      logger.info(`Processing ${allDocuments.length} documents`);

      // Sort documents to ensure parents are processed before children
      const sortedDocuments = sortDocumentsByHierarchy(allDocuments);

      // Process each document
      for (const doc of sortedDocuments) {
        try {
          // Map and insert the document
          const documentToInsert = mapReadwiseArticleToDocument(doc, integrationRunId);
          await db
            .insert(readwiseDocuments)
            .values(documentToInsert)
            .onConflictDoUpdate({
              target: readwiseDocuments.id,
              set: { ...documentToInsert, recordUpdatedAt: sql`(CURRENT_TIMESTAMP)` },
            });

          successCount++;

          // Log progress periodically
          if (successCount % 20 === 0) {
            logger.info(`Processed ${successCount} of ${sortedDocuments.length} documents`);
            report({
              type: 'progress',
              phase: 'documents',
              message: `Stored ${successCount} of ${sortedDocuments.length} documents`,
              current: successCount,
              total: sortedDocuments.length,
            });
          }
        } catch (error) {
          logger.error('Error processing document', {
            documentId: doc.id,
            error: error instanceof Error ? error.message : String(error),
          });
        }
      }

      logger.complete('Processed documents', successCount);
    }

    report({
      type: 'phase',
      phase: 'documents',
      status: allDocuments.length > 0 ? 'done' : 'skip',
      count: successCount,
      message:
        allDocuments.length > 0
          ? `Stored ${pluralize(successCount, 'new or updated document', 'new or updated documents')}`
          : 'Nothing new since the last sync',
    });
  } catch (error) {
    logger.error('Error syncing Readwise documents', error);
    throw error;
  }
}

/**
 * Creates all Readwise entities (authors, tags, records) from synced data
 *
 * This function consolidates entity creation to run once per integration run,
 * after both Reader documents and legacy books have been synced.
 *
 * @param integrationRunId - The integration run ID
 * @returns Array of all newly created records with their title and slug
 */
async function createReadwiseEntities(integrationRunId: number): Promise<NewRecordInfo[]> {
  logger.info('Creating related entities');

  // Each phase pairs the Readwise-side upsert (authors/tags tables) with the
  // records it yields, so the progress view can report one outcome per phase.
  // The three are independent of one another; only the documents phase
  // depends on authors and tags having their records first.
  report({ type: 'phase', phase: 'authors', status: 'start' });
  await createReadwiseAuthors(integrationRunId);
  const authorRecords = await createRecordsFromReadwiseAuthors();
  reportPhaseOutcome('authors', authorRecords.length, 'author');

  report({ type: 'phase', phase: 'tags', status: 'start' });
  await createReadwiseTags(integrationRunId);
  const tagRecords = await createRecordsFromReadwiseTags();
  reportPhaseOutcome('tags', tagRecords.length, 'tag');

  report({ type: 'phase', phase: 'records', status: 'start' });
  const documentRecords = await createRecordsFromReadwiseDocuments();
  reportPhaseOutcome('records', documentRecords.length, 'document');

  const allNewRecords = [...authorRecords, ...tagRecords, ...documentRecords];
  logger.complete('Created all related entities');
  return allNewRecords;
}

function reportPhaseOutcome(
  phase: 'authors' | 'tags' | 'records',
  created: number,
  noun: string,
): void {
  report({
    type: 'phase',
    phase,
    status: created > 0 ? 'done' : 'skip',
    count: created,
    message:
      created > 0
        ? `Created ${pluralize(created, 'record', 'records')} from ${noun === 'document' ? 'documents' : `${noun}s`}`
        : `No new ${noun}s to create records for`,
  });
}

export async function syncReadwiseData(): Promise<void> {
  await runIntegration('readwise', async (integrationRunId) => {
    await syncReadwiseDocuments(integrationRunId);
    await syncReadwiseBooks(integrationRunId);
    const newRecords = await createReadwiseEntities(integrationRunId);

    // Log all newly created records
    if (newRecords.length > 0) {
      logger.info(`\n📝 New records created (${newRecords.length}):`);
      for (const record of newRecords) {
        const displayName = record.title || record.slug;
        logger.info(`  • ${displayName} (slug: ${record.slug})`);
      }
    }

    return newRecords.length;
  });
}
