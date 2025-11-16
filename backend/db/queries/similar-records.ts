import { db, sqliteClient } from '@db/index';
import { type RecordSelect, type FTS5SearchResult } from '@db/schema';
import type { APIResponse } from '@shared/types/api';

export interface SimilarRecord {
  record: RecordSelect;
  score: number;
  reasons: string[];
}

export interface SimilarRecordsInput {
  recordId: RecordSelect['id'];
  limit?: number;
  minScore?: number;
  includeContent?: boolean;
}

/**
 * FTS5 query configuration - adjust these values to fine-tune search results
 */
interface FTS5Config {
  // Term extraction
  minTermLength: number; // Minimum word length to consider (default: 3)
  maxTerms: number; // Maximum number of terms to extract (default: 20)

  // NEAR query settings
  nearDistance: number; // Maximum token distance for NEAR queries (default: 10)
  maxNearPairs: number; // Maximum number of NEAR query pairs (default: 5)

  // Query strategy
  usePrefixMatching: boolean; // Use "*" for prefix matching (default: true)
  useNearQueries: boolean; // Include NEAR queries (default: true)
  usePhraseMatching: boolean; // Include phrase queries (default: true)
  queryOperator: 'OR' | 'AND'; // How to combine query strategies (default: 'OR')

  // Score normalization
  bm25SigmoidScale: number; // Scale factor for sigmoid normalization (default: 5)

  // Result filtering
  initialQueryMultiplier: number; // Multiply limit for initial query (default: 2)

  // Creator/author search
  includeCreatorInSearch: boolean; // Include creator names in search (default: true)
}

/**
 * Default FTS5 configuration
 *
 * Modify these values to test different search behaviors:
 * - For broader, more inclusive results: increase maxTerms, nearDistance, use 'OR'
 * - For stricter, more precise results: decrease maxTerms, nearDistance, use 'AND'
 * - For faster queries: decrease maxNearPairs, initialQueryMultiplier
 * - For better relevance: adjust bm25SigmoidScale based on your score distribution
 */
const DEFAULT_FTS5_CONFIG: FTS5Config = {
  // Term extraction - adjust for broader/narrower term selection
  minTermLength: 3,
  maxTerms: 40,

  // NEAR query settings - adjust for semantic proximity matching
  nearDistance: 10,
  maxNearPairs: 5,

  // Query strategy - enable/disable features and choose operator
  usePrefixMatching: true,
  useNearQueries: true,
  usePhraseMatching: true,
  queryOperator: 'OR',

  // Score normalization - adjust sigmoid curve steepness
  bm25SigmoidScale: 5,

  // Result filtering - adjust initial candidate pool size
  initialQueryMultiplier: 20,

  // Creator/author search
  includeCreatorInSearch: true,
};

/**
 * Extracts meaningful search terms from text
 */
function extractSearchTerms(text: string, config: FTS5Config): string[] {
  if (!text || text.trim().length === 0) {
    return [];
  }

  const commonWords = new Set([
    'the',
    'a',
    'an',
    'and',
    'or',
    'but',
    'in',
    'on',
    'at',
    'to',
    'for',
    'of',
    'with',
    'by',
    'is',
    'are',
    'was',
    'were',
    'be',
    'been',
    'have',
    'has',
    'had',
    'do',
    'does',
    'did',
    'will',
    'would',
    'could',
    'should',
    'may',
    'might',
    'can',
    'this',
    'that',
    'these',
    'those',
  ]);

  return text
    .toLowerCase()
    .replace(/[^\w\s]/g, ' ')
    .split(/\s+/)
    .filter((word) => word.length >= config.minTermLength && !commonWords.has(word))
    .slice(0, config.maxTerms);
}

/**
 * Builds an FTS5 query string from search terms
 */
function buildFTS5Query(
  terms: string[],
  title: string | null | undefined,
  config: FTS5Config,
): string {
  const queries: string[] = [];

  // Strategy 1: Individual term matching (broad search)
  if (terms.length > 0) {
    const termQuery = terms
      .map((term) => {
        const escaped = term.replace(/"/g, '""');
        return config.usePrefixMatching ? `"${escaped}"*` : `"${escaped}"`;
      })
      .join(' OR ');
    queries.push(termQuery);
  }

  // Strategy 2: NEAR queries for pairs of terms (semantic proximity)
  if (config.useNearQueries && terms.length >= 2) {
    const maxPairs = Math.min(terms.length - 1, config.maxNearPairs);
    for (let i = 0; i < maxPairs; i++) {
      const term1 = terms[i]!.replace(/"/g, '""');
      const term2 = terms[i + 1]!.replace(/"/g, '""');
      queries.push(`NEAR("${term1}" "${term2}", ${config.nearDistance})`);
    }
  }

  // Strategy 3: Phrase matching for title (exact phrases are important)
  if (config.usePhraseMatching && title) {
    const titleTerms = extractSearchTerms(title, { ...config, minTermLength: 2, maxTerms: 5 });
    if (titleTerms.length >= 2) {
      queries.push(`"${titleTerms.join(' ')}"`);
    }
  }

  // Combine all query strategies
  return queries.join(` ${config.queryOperator} `);
}

/**
 * Finds records related to a given record using FTS5 full-text search
 *
 * Searches across:
 * - Title
 * - Summary
 * - Content
 * - Notes
 * - Creator/Author names (via links)
 *
 * Uses FTS5 features:
 * - BM25 ranking for relevance
 * - NEAR queries for semantic proximity
 * - Phrase matching for exact matches
 * - Prefix matching for fuzzy search
 */
export const findRelatedRecords = async (input: SimilarRecordsInput): Promise<SimilarRecord[]> => {
  const { recordId, limit = 5, minScore = 0.1 } = input;
  const config = DEFAULT_FTS5_CONFIG;

  // Get the source record with all text fields
  const sourceRecord = await db.query.records.findFirst({
    where: { id: recordId },
    columns: {
      id: true,
      title: true,
      summary: true,
      content: true,
      notes: true,
      type: true,
      recordCreatedAt: true,
    },
  });

  if (!sourceRecord) {
    throw new Error('Source record not found');
  }

  // Collect all searchable text from the source record
  const searchableText: string[] = [
    sourceRecord.title,
    sourceRecord.summary,
    sourceRecord.content,
    sourceRecord.notes,
  ].filter(Boolean) as string[];

  // Include creator/author names if enabled
  if (config.includeCreatorInSearch) {
    // Get creators via links with "created_by" predicate
    const creatorLinks = await db.query.links.findMany({
      where: {
        sourceId: recordId,
        predicate: {
          type: 'creation',
        },
      },
      with: {
        target: {
          columns: {
            title: true,
          },
        },
      },
    });

    // Get authors from readwise documents
    const readwiseDocs = await db.query.readwiseDocuments.findMany({
      where: {
        recordId: recordId,
      },
      columns: {
        author: true,
        authorId: true,
      },
    });

    // Get author names for documents that have authorId
    const authorIds = readwiseDocs
      .map((doc) => doc.authorId)
      .filter((id): id is number => id !== null && id !== undefined);

    const authors =
      authorIds.length > 0
        ? await db.query.readwiseAuthors.findMany({
            where: {
              id: {
                in: authorIds,
              },
            },
            columns: {
              name: true,
            },
          })
        : [];

    // Add creator names to searchable text
    for (const link of creatorLinks) {
      if (link.target?.title) {
        searchableText.push(link.target.title);
      }
    }

    // Add author names to searchable text
    for (const doc of readwiseDocs) {
      // Include the author field directly from the document (text field)
      if (doc.author) {
        searchableText.push(doc.author);
      }
    }

    // Add author names from the authors table
    for (const author of authors) {
      if (author.name) {
        searchableText.push(author.name);
      }
    }
  }

  // Combine all searchable text
  const allText = searchableText.join(' ');

  if (!allText || allText.trim().length === 0) {
    return [];
  }

  // Extract meaningful terms
  const terms = extractSearchTerms(allText, config);

  if (terms.length === 0) {
    return [];
  }

  // Build FTS5 query
  const fts5Query = buildFTS5Query(terms, sourceRecord.title, config);

  if (!fts5Query || fts5Query.trim().length === 0) {
    return [];
  }

  // Get records to exclude (source record and directly linked records)
  const sourceOutgoingConnections = await db.query.links.findMany({
    where: { sourceId: recordId },
    columns: { targetId: true },
  });
  const sourceIncomingConnections = await db.query.links.findMany({
    where: { targetId: recordId },
    columns: { sourceId: true },
  });
  const excludeIds = new Set([
    recordId,
    ...sourceOutgoingConnections.map((l) => l.targetId),
    ...sourceIncomingConnections.map((l) => l.sourceId),
  ]);

  const excludeIdsArray = Array.from(excludeIds);
  const excludeClause =
    excludeIdsArray.length > 0 ? `AND id NOT IN (${excludeIdsArray.join(',')})` : '';

  // Execute FTS5 query with BM25 ranking
  const querySQL = `
    SELECT 
      id,
      rank,
      bm25(records_fts) as bm25
    FROM records_fts
    WHERE records_fts MATCH '${fts5Query.replace(/'/g, "''")}'
      ${excludeClause}
    ORDER BY bm25(records_fts) ASC
    LIMIT ${limit * config.initialQueryMultiplier}
  `;

  const fts5Results = sqliteClient.prepare(querySQL).all() as FTS5SearchResult[];

  if (!fts5Results || fts5Results.length === 0) {
    return [];
  }

  // Fetch full records for the top FTS5 results
  const resultIds = fts5Results.map((r) => r.id);
  const records = await db.query.records.findMany({
    where: {
      id: {
        in: resultIds,
      },
    },
  });

  // Create a map for quick lookup
  const recordsMap = new Map(records.map((r) => [r.id, r]));

  // Build RelatedRecord results with normalized scores
  const relatedRecords: SimilarRecord[] = [];
  for (const fts5Result of fts5Results) {
    const record = recordsMap.get(fts5Result.id);
    if (!record) continue;

    // Normalize BM25 score to 0-1 range
    // BM25 scores are typically negative (better = less negative)
    // Convert to positive score: better matches get higher scores
    const bm25Score = fts5Result.bm25 || 0;
    // Use sigmoid transformation: 1 / (1 + exp(bm25 / scale))
    const normalizedScore = 1 / (1 + Math.exp(bm25Score / config.bm25SigmoidScale));
    const finalScore = Math.max(0, Math.min(1, normalizedScore));

    if (finalScore >= minScore) {
      // Build reasons for why this record is related
      const reasons: string[] = [];
      reasons.push(`FTS5 BM25: ${bm25Score.toFixed(2)}`);
      reasons.push(`Rank: ${fts5Result.rank}`);

      // Add specific match reasons
      if (sourceRecord.title && record.title) {
        const titleTerms = extractSearchTerms(sourceRecord.title, config);
        const recordTitleTerms = extractSearchTerms(record.title, config);
        const titleOverlap = titleTerms.filter((t) => recordTitleTerms.includes(t));
        if (titleOverlap.length > 0) {
          reasons.push(`Shared title terms: ${titleOverlap.slice(0, 3).join(', ')}`);
        }
      }

      relatedRecords.push({
        record,
        score: finalScore,
        reasons,
      });
    }
  }

  // Sort by score (descending) and return top results
  return relatedRecords.sort((a, b) => b.score - a.score).slice(0, limit);
};

export type RelatedRecordsAPIResponse = APIResponse<typeof findRelatedRecords>;
