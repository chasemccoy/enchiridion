import { db } from '@db/index';
import { readwiseDocuments } from '@db/schema';
import { sql } from 'drizzle-orm';
import { runIntegration } from '@integrations/utils/runIntegration';
import {
  createReadwiseAuthors,
  createReadwiseTags,
  fetchBookExport,
  getMostRecentBookUpdateTime,
  logger,
  mapBookToDocument,
  mapBookHighlightToDocument,
  sortBooksByHierarchy,
} from '@integrations/readwise/utils';
import {
  createRecordsFromReadwiseAuthors,
  createRecordsFromReadwiseDocuments,
  createRecordsFromReadwiseTags,
} from '@integrations/readwise/records';
import type { ReadwiseBook } from '@integrations/readwise/types';

/**
 * Synchronizes legacy Readwise books and highlights with the database
 *
 * This function:
 * 1. Determines the last sync point for legacy books
 * 2. Fetches new or updated books from the legacy API
 * 3. Processes and stores the books and their highlights
 * 4. Creates related entities (authors, tags, records)
 *
 * @returns The number of successfully processed books
 * @throws Error if API requests fail
 */
export async function syncReadwiseBooks(integrationRunId: number): Promise<number> {
  try {
    logger.info('Starting legacy Readwise books sync');

    // Step 1: Determine last sync point
    const lastUpdateTime = await getMostRecentBookUpdateTime();

    // Step 2: Fetch all books
    logger.info('Fetching books from legacy Readwise API');
    const allBooks: ReadwiseBook[] = [];
    let nextPageCursor: string | null = null;

    do {
      const response = await fetchBookExport(
        nextPageCursor ?? undefined,
        lastUpdateTime ?? undefined,
      );
      allBooks.push(...response.results);
      nextPageCursor = response.nextPageCursor;

      logger.info(`Retrieved ${response.results.length} books (total: ${allBooks.length})`);
    } while (nextPageCursor);

    // Step 3: Process books and highlights
    let successCount = 0;
    if (allBooks.length > 0) {
      // Filter to only process actual books (not articles or tweets) with highlights
      const booksWithHighlights = allBooks.filter(
        (book) => book.category === 'books' && book.highlights.length > 0,
      );

      logger.info(`Processing ${booksWithHighlights.length} books`);

      // Sort books to ensure they are processed in order
      const sortedBooks = sortBooksByHierarchy(booksWithHighlights);

      // Process each book and its highlights
      for (const book of sortedBooks) {
        try {
          // Map and insert the book
          const bookToInsert = mapBookToDocument(book, integrationRunId);
          await db
            .insert(readwiseDocuments)
            .values(bookToInsert)
            .onConflictDoUpdate({
              target: readwiseDocuments.id,
              set: { ...bookToInsert, recordUpdatedAt: sql`(CURRENT_TIMESTAMP)` },
            });

          successCount++;

          // Process highlights for this book
          for (const highlight of book.highlights) {
            try {
              const highlightToInsert = mapBookHighlightToDocument(
                highlight,
                book.user_book_id.toString(),
                integrationRunId,
              );
              await db
                .insert(readwiseDocuments)
                .values(highlightToInsert)
                .onConflictDoUpdate({
                  target: readwiseDocuments.id,
                  set: { ...highlightToInsert, recordUpdatedAt: sql`(CURRENT_TIMESTAMP)` },
                });
            } catch (error) {
              logger.error('Error processing highlight', {
                highlightId: highlight.id,
                bookId: book.user_book_id,
                error: error instanceof Error ? error.message : String(error),
              });
            }
          }

          // Log progress periodically
          if (successCount % 10 === 0) {
            logger.info(`Processed ${successCount} of ${sortedBooks.length} books`);
          }
        } catch (error) {
          logger.error('Error processing book', {
            bookId: book.user_book_id,
            error: error instanceof Error ? error.message : String(error),
          });
        }
      }

    }

    logger.complete('Processed books', successCount);
    return successCount;
  } catch (error) {
    logger.error('Error syncing Readwise books', error);
    throw error;
  }
}

export async function syncReadwiseBookData(): Promise<void> {
  await runIntegration('readwise', syncReadwiseBooks);
}
