import { eq, inArray, sql } from 'drizzle-orm';
import { db } from '@db/index';
import {
  readwiseAuthors,
  readwiseDocuments,
  readwiseDocumentTags,
  readwiseTags,
  type ReadwiseAuthorSelect,
  type ReadwiseDocumentInsert,
} from '@db/schema';
import { requireEnv } from '../utils/env';
import { createIntegrationLogger } from '../utils/log';
import type {
  ReadwiseArticle,
  ReadwiseArticlesResponse,
  ReadwiseBook,
  ReadwiseBookHighlight,
  ReadwiseBookExportResponse,
} from './types';
import { ReadwiseArticlesResponseSchema, ReadwiseBookExportResponseSchema } from './types';
import { formatDateToDbString } from '@shared/lib/formatting';

const API_BASE_URL = 'https://readwise.io/api/v3/list/';
const RETRY_DELAY_BASE = 1000; // 1 second in milliseconds
const READWISE_TOKEN = requireEnv('READWISE_TOKEN');

export const logger = createIntegrationLogger('readwise', 'sync');

/**
 * Gets the oldest date from an array of dates
 *
 * @param dates - Array of dates to compare
 * @returns The oldest date, or current date if array is empty
 */
export function getOldestDate(dates: Date[]): Date {
  return dates.length > 0 ? new Date(Math.min(...dates.map((d) => d.getTime()))) : new Date();
}

/**
 * Retrieves the most recent update time from the database
 *
 * This is used to determine the cutoff point for fetching new documents
 *
 * @returns The date of the most recently updated document, or null if none exists
 */
export async function getMostRecentUpdateTime(): Promise<Date | null> {
  const mostRecent = await db.query.readwiseDocuments.findFirst({
    columns: {
      contentUpdatedAt: true,
    },
    orderBy: {
      contentUpdatedAt: 'desc',
    },
  });

  if (mostRecent) {
    logger.info(
      `Last known readwise date: ${mostRecent.contentUpdatedAt?.toLocaleString() ?? 'none'}`,
    );

    if (!mostRecent.contentUpdatedAt) return null;

    return new Date(mostRecent.contentUpdatedAt);
  }

  logger.info('No existing documents found');
  return null;
}

/**
 * Fetches documents from the Readwise API
 *
 * This function handles pagination and rate limiting automatically.
 *
 * @param pageCursor - Optional cursor for pagination
 * @param updatedAfter - Optional date to filter documents updated after this time
 * @returns Promise resolving to the API response with documents
 * @throws Error if the API request fails
 */
export async function fetchReadwiseDocuments(
  pageCursor?: string,
  updatedAfter?: Date,
): Promise<ReadwiseArticlesResponse> {
  const params = new URLSearchParams();

  if (pageCursor) params.append('pageCursor', pageCursor);

  if (updatedAfter) {
    const afterDate = new Date(updatedAfter.getTime() + 1);
    params.append('updatedAfter', afterDate.toISOString());
  }

  params.append('withHtmlContent', 'true');

  let attempt = 0;

  while (true) {
    const response = await fetch(`${API_BASE_URL}?${params.toString()}`, {
      headers: {
        Authorization: `Token ${READWISE_TOKEN}`,
        'Content-Type': 'application/json',
      },
    });

    if (response.ok) {
      const data = await response.json();
      return ReadwiseArticlesResponseSchema.parse(data);
    }

    if (response.status === 429) {
      const retryAfter = parseInt(response.headers.get('Retry-After') || '60', 10);
      logger.warn(`Rate limit hit, waiting ${retryAfter} seconds before retrying...`);
      await new Promise((r) => setTimeout(r, retryAfter * RETRY_DELAY_BASE));
      continue;
    }

    attempt++;

    if (attempt >= 3) {
      throw new Error(
        `Failed to fetch Readwise documents: ${response.statusText} (${response.status})`,
      );
    }

    logger.warn(`Request failed with status ${response.status}, retrying...`);
    await new Promise((r) => setTimeout(r, RETRY_DELAY_BASE));
  }
}

/**
 * Maps a Readwise article to a document format for database insertion
 *
 * This function validates URLs and handles null values appropriately.
 *
 * @param article - The Readwise article to map
 * @param integrationRunId - The ID of the current integration run
 * @returns A document object ready for database insertion
 */
export const mapReadwiseArticleToDocument = (
  article: ReadwiseArticle,
  integrationRunId: number,
): ReadwiseDocumentInsert => {
  let validSourceUrl: string | null = null;

  if (article.source_url) {
    try {
      if (/^https?:\/\//.test(article.source_url)) {
        new URL(article.source_url);
        validSourceUrl = article.source_url;
      }
    } catch {
      logger.warn(`Skipping invalid source_url: ${article.source_url}`);
    }
  }

  let validImageUrl: string | null = null;

  if (article.image_url) {
    try {
      if (/^https?:\/\//.test(article.image_url)) {
        new URL(article.image_url);
        validImageUrl = article.image_url;
      }
    } catch {
      logger.warn(`Skipping invalid image_url: ${article.image_url}`);
    }
  }

  return {
    id: article.id,
    parentId: article.parent_id,
    url: article.url,
    title: article.title || null,
    author: article.author || null,
    source: article.source,
    category: article.category,
    location: article.location,
    tags: article.tags,
    siteName: article.site_name || null,
    wordCount: article.word_count,
    summary: article.summary || null,
    content: article.content || null,
    htmlContent: article.html_content || null,
    notes: article.notes || null,
    imageUrl: validImageUrl,
    sourceUrl: validSourceUrl,
    readingProgress: article.reading_progress,
    firstOpenedAt: formatDateToDbString(article.first_opened_at),
    lastOpenedAt: formatDateToDbString(article.last_opened_at),
    savedAt: formatDateToDbString(article.saved_at) || '',
    lastMovedAt: formatDateToDbString(article.last_moved_at) || '',
    publishedDate: article.published_date
      ? article.published_date.toISOString().split('T')[0]
      : null,
    contentCreatedAt: formatDateToDbString(article.created_at),
    contentUpdatedAt: formatDateToDbString(article.updated_at),
    integrationRunId,
  };
};

/**
 * Sorts documents by their hierarchical relationship
 *
 * This ensures that parent documents are processed before their children.
 *
 * @param documents - The documents to sort
 * @returns Sorted array of documents
 */
export function sortDocumentsByHierarchy(documents: ReadwiseArticle[]): ReadwiseArticle[] {
  // Create a map of id to document for quick lookup
  const idToDocument = new Map(documents.map((doc) => [doc.id, doc]));

  // Helper function to get the ancestry chain for a document
  function getAncestryChain(doc: ReadwiseArticle): string[] {
    const chain: string[] = [];
    let current = doc;
    while (current.parent_id) {
      const parent = idToDocument.get(current.parent_id);
      if (!parent) break;
      chain.push(current.parent_id);
      current = parent;
    }
    return chain;
  }

  // Sort by ancestry chain length (parents first), then by creation date
  return [...documents].sort((a, b) => {
    const aChain = getAncestryChain(a);
    const bChain = getAncestryChain(b);
    if (aChain.length !== bChain.length) {
      return aChain.length - bChain.length;
    }
    return new Date(a.created_at).getTime() - new Date(b.created_at).getTime();
  });
}

/**
 * Creates authors from Readwise documents that don't have associated authors yet
 *
 * @param integrationRunId - The ID of the current integration run
 * @returns A promise resolving to the processed documents
 */
export async function createReadwiseAuthors(integrationRunId: number) {
  logger.start('Creating authors from Readwise documents');

  const documentsWithoutAuthors = await db.query.readwiseDocuments.findMany({
    where: {
      author: {
        isNotNull: true,
      },
      authorId: {
        isNull: true,
      },
      integrationRunId,
    },
  });

  if (documentsWithoutAuthors.length === 0) {
    logger.skip('No documents without authors found');
    return;
  }

  logger.info(`Found ${documentsWithoutAuthors.length} documents without authors`);

  for (const document of documentsWithoutAuthors) {
    if (!document.author) {
      logger.warn(`Document ${document.id} has no author`);
      continue;
    }

    let origin: string | null = null;

    try {
      if (document.sourceUrl) {
        const url = new URL(document.sourceUrl);
        origin = url.origin;
      }
    } catch {
      logger.warn(`Skipping invalid author: ${document.author}`);
      continue;
    }

    let insertedRecord: ReadwiseAuthorSelect | null = null;

    try {
      const [newRecord] = await db
        .insert(readwiseAuthors)
        .values({
          name: document.author,
          origin,
        })
        .onConflictDoUpdate({
          target: [readwiseAuthors.name, readwiseAuthors.origin],
          set: {
            recordUpdatedAt: sql`(CURRENT_TIMESTAMP)`,
          },
        })
        .returning();

      insertedRecord = newRecord ?? null;
    } catch (error) {
      logger.error(`Failed to create author ${document.author} with error: ${error}`);
      continue;
    }

    if (!insertedRecord) {
      logger.error(`Failed to create author ${document.author}`);
      continue;
    }

    logger.info(`Linked document ${document.id} to author ${insertedRecord.id}`);

    await db
      .update(readwiseDocuments)
      .set({ authorId: insertedRecord.id })
      .where(eq(readwiseDocuments.id, document.id));
  }

  logger.complete(`Processed ${documentsWithoutAuthors.length} documents without authors`);
}

/**
 * Creates tags from Readwise documents and links them to documents
 *
 * @param integrationRunId - Optional integration run ID to limit processing
 * @returns A promise resolving to the processed documents
 */
export async function createReadwiseTags(integrationRunId: number) {
  logger.start('Processing document tags');

  const documents = await db.query.readwiseDocuments.findMany({
    where: {
      tags: {
        isNotNull: true,
      },
      integrationRunId,
    },
  });

  if (documents.length === 0) {
    logger.skip('No new or updated tags to process');
    return;
  }

  logger.info(`Found ${documents.length} documents with tags to process`);

  // Extract unique tags from all documents
  const uniqueTags = [...new Set(documents.map((document) => document.tags).flat())].filter(
    (tag): tag is string => tag !== null,
  );

  // Insert or update tags
  const insertedTags = await db
    .insert(readwiseTags)
    .values(uniqueTags.map((tag) => ({ tag })))
    .onConflictDoUpdate({
      target: readwiseTags.tag,
      set: {
        recordUpdatedAt: sql`(CURRENT_TIMESTAMP)`,
      },
    })
    .returning();

  logger.info(`Upserted ${insertedTags.length} tags`);

  // Create a map of tag names to tag IDs
  const tagMap = new Map(insertedTags.map((tag) => [tag.tag, tag.id]));

  // Clear existing document-tag relationships
  logger.info('Clearing existing document tags');

  if (integrationRunId) {
    const documentIds = documents.map((document) => document.id);
    const deletedDocumentTags = await db
      .delete(readwiseDocumentTags)
      .where(inArray(readwiseDocumentTags.documentId, documentIds))
      .returning();

    logger.info(
      `Deleted ${deletedDocumentTags.length} document tags for ${documents.length} documents in integration run ${integrationRunId}`,
    );
  } else {
    logger.info('No integration run id provided, deleting all document tags');
    await db.delete(readwiseDocumentTags);
  }

  // Create new document-tag relationships
  const documentTagPromises = documents.flatMap((document) => {
    if (!document.tags) return [];

    return document.tags.map(async (tag) => {
      const tagId = tagMap.get(tag);
      if (!tagId) return undefined;

      const [documentTag] = await db
        .insert(readwiseDocumentTags)
        .values({
          documentId: document.id,
          tagId,
        })
        .onConflictDoUpdate({
          target: [readwiseDocumentTags.documentId, readwiseDocumentTags.tagId],
          set: { recordUpdatedAt: sql`(CURRENT_TIMESTAMP)` },
        })
        .returning();

      return documentTag;
    });
  });

  const newDocumentTags = (await Promise.all(documentTagPromises)).filter(Boolean);
  logger.info(`Inserted ${newDocumentTags.length} document tags`);

  logger.complete(`Processed tags for ${documents.length} documents`);
  return documents;
}

// ------------------------------------------------------------------------
// Legacy API v2 utilities for book highlights
// ------------------------------------------------------------------------

const LEGACY_API_BASE_URL = 'https://readwise.io/api/v2/export/';

/**
 * Retrieves the most recent update time from legacy books in the database
 *
 * This is used to determine the cutoff point for fetching new books
 *
 * @returns The date of the most recently updated legacy book, or null if none exists
 */
export async function getMostRecentBookUpdateTime(): Promise<Date | null> {
  const mostRecent = await db.query.readwiseDocuments.findFirst({
    where: {
      category: 'highlight', // Use highlights since they have updated_at timestamps
    },
    columns: {
      contentUpdatedAt: true,
    },
    orderBy: {
      contentUpdatedAt: 'desc',
    },
  });

  if (mostRecent) {
    logger.info(
      `Last known book highlight date: ${mostRecent.contentUpdatedAt?.toLocaleString() ?? 'none'}`,
    );

    if (!mostRecent.contentUpdatedAt) return null;

    return new Date(mostRecent.contentUpdatedAt);
  }

  logger.info('No existing book highlights found');
  return null;
}

/**
 * Fetches books from the legacy Readwise API v2
 *
 * This function handles pagination and rate limiting automatically.
 *
 * @param pageCursor - Optional cursor for pagination
 * @param updatedAfter - Optional date to filter books updated after this time
 * @returns Promise resolving to the API response with books
 * @throws Error if the API request fails
 */
export async function fetchBookExport(
  pageCursor?: string,
  updatedAfter?: Date,
): Promise<ReadwiseBookExportResponse> {
  const params = new URLSearchParams();

  if (pageCursor) params.append('pageCursor', pageCursor);

  if (updatedAfter) {
    const afterDate = new Date(updatedAfter.getTime() + 1);
    params.append('updatedAfter', afterDate.toISOString());
  }

  let attempt = 0;

  while (true) {
    const response = await fetch(`${LEGACY_API_BASE_URL}?${params.toString()}`, {
      headers: {
        Authorization: `Token ${READWISE_TOKEN}`,
        'Content-Type': 'application/json',
      },
    });

    if (response.ok) {
      const data = await response.json();
      return ReadwiseBookExportResponseSchema.parse(data);
    }

    if (response.status === 429) {
      const retryAfter = parseInt(response.headers.get('Retry-After') || '60', 10);
      logger.warn(`Rate limit hit, waiting ${retryAfter} seconds before retrying...`);
      await new Promise((r) => setTimeout(r, retryAfter * RETRY_DELAY_BASE));
      continue;
    }

    attempt++;

    if (attempt >= 3) {
      throw new Error(`Failed to fetch legacy books: ${response.statusText} (${response.status})`);
    }

    logger.warn(`Request failed with status ${response.status}, retrying...`);
    await new Promise((r) => setTimeout(r, RETRY_DELAY_BASE));
  }
}

/**
 * Maps a book to a document format for database insertion
 *
 * @param book - The legacy book to map
 * @param integrationRunId - The ID of the current integration run
 * @returns A document object ready for database insertion
 */
export const mapBookToDocument = (
  book: ReadwiseBook,
  integrationRunId: number,
): ReadwiseDocumentInsert => {
  let validImageUrl: string | null = null;

  if (book.cover_image_url) {
    try {
      if (/^https?:\/\//.test(book.cover_image_url)) {
        new URL(book.cover_image_url);
        validImageUrl = book.cover_image_url;
      }
    } catch {
      logger.warn(`Skipping invalid cover_image_url: ${book.cover_image_url}`);
    }
  }

  // Find the oldest highlight creation date
  const oldestHighlightDate = getOldestDate(book.highlights.map((h) => new Date(h.created_at)));

  return {
    id: book.user_book_id.toString(),
    parentId: null,
    url: book.readwise_url || `https://readwise.io/book/${book.user_book_id}`,
    title: book.title,
    author: book.author || null,
    source: 'books',
    category: 'book',
    location: 'archive',
    tags: book.book_tags.length > 0 ? book.book_tags.map((tag) => tag.name) : null,
    siteName: null,
    wordCount: null,
    summary: book.summary || null,
    content: null,
    htmlContent: null,
    notes: book.document_note || null,
    imageUrl: validImageUrl,
    sourceUrl: book.source_url || null,
    readingProgress: null,
    firstOpenedAt: null,
    lastOpenedAt: null,
    savedAt: formatDateToDbString(oldestHighlightDate) || '',
    lastMovedAt: formatDateToDbString(oldestHighlightDate) || '',
    publishedDate: null,
    contentCreatedAt: formatDateToDbString(oldestHighlightDate),
    contentUpdatedAt: formatDateToDbString(oldestHighlightDate),
    integrationRunId,
  };
};

/**
 * Maps a book highlight to a document format for database insertion
 *
 * @param highlight - The book highlight to map
 * @param bookId - The ID of the parent book
 * @param integrationRunId - The ID of the current integration run
 * @returns A document object ready for database insertion
 */
export const mapBookHighlightToDocument = (
  highlight: ReadwiseBookHighlight,
  bookId: string,
  integrationRunId: number,
): ReadwiseDocumentInsert => {
  return {
    id: highlight.id.toString(),
    parentId: bookId,
    url: highlight.readwise_url || `https://readwise.io/book/${bookId}/highlight/${highlight.id}`,
    title: null,
    author: null,
    source: 'books',
    category: 'highlight',
    location: null,
    tags: highlight.tags.length > 0 ? highlight.tags.map((tag) => tag.name) : null,
    siteName: null,
    wordCount: null,
    summary: null,
    content: highlight.text,
    htmlContent: null,
    notes: highlight.note || null,
    imageUrl: null,
    sourceUrl: highlight.url || null,
    readingProgress: null,
    firstOpenedAt: null,
    lastOpenedAt: null,
    savedAt: formatDateToDbString(highlight.highlighted_at) || '',
    lastMovedAt: formatDateToDbString(highlight.highlighted_at) || '',
    publishedDate: null,
    contentCreatedAt: formatDateToDbString(highlight.created_at),
    contentUpdatedAt: formatDateToDbString(highlight.updated_at),
    integrationRunId,
  };
};

/**
 * Sorts books and highlights by their hierarchical relationship
 *
 * This ensures that books are processed before their highlights.
 *
 * @param books - The books to sort
 * @returns Sorted array of books with their highlights
 */
export function sortBooksByHierarchy(books: ReadwiseBook[]): ReadwiseBook[] {
  // Sort books by user_book_id for consistent processing order
  return [...books].sort((a, b) => {
    return a.user_book_id - b.user_book_id;
  });
}
