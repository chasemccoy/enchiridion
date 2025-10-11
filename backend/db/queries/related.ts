import { db } from '@db/index';
import { type RecordSelect } from '@db/schema';
import type { APIResponse } from '@shared/types/api';

export interface RelatedRecord {
  record: RecordSelect;
  score: number;
  reasons: string[];
}

export interface RelatedRecordsInput {
  recordId: RecordSelect['id'];
  limit?: number;
  minScore?: number;
  includeContent?: boolean;
}

// Define the type for records with links that we get from the database
interface RecordWithLinks {
  id: number;
  title: string;
  summary: string;
  content?: string;
  type: RecordSelect['type'];
  recordCreatedAt: string;
  recordUpdatedAt: string;
  outgoingLinks: Array<{
    predicateId: number;
    targetId: number;
    predicate: {
      type: string;
      slug: string;
    };
  }>;
  incomingLinks: Array<{
    predicateId: number;
    sourceId: number;
    predicate: {
      type: string;
      slug: string;
    };
  }>;
}

/**
 * Finds records related to a given record using a multi-factor similarity algorithm
 *
 * Algorithm factors:
 * 1. Direct link relationships (highest weight)
 * 2. Shared predicates with other records
 * 3. Text similarity in title, summary, and content
 * 4. Content overlap and shared keywords
 * 5. Temporal proximity (recent records get slight boost)
 */
export const findRelatedRecords = async (input: RelatedRecordsInput): Promise<RelatedRecord[]> => {
  const { recordId, limit = 20, minScore = 0.1, includeContent = false } = input;

  // TODO: CACHING - Consider implementing Redis/memory cache for frequently requested records

  // Get the source record
  const sourceRecord = await db.query.records.findFirst({
    where: { id: recordId },
    columns: {
      id: true,
      title: true,
      summary: true,
      content: true,
      type: true,
      recordCreatedAt: true,
    },
  });

  if (!sourceRecord) {
    throw new Error('Source record not found');
  }

  // Get all records that the source connects to (outgoing links)
  const sourceOutgoingConnections = await db.query.links.findMany({
    where: { sourceId: recordId },
    columns: { targetId: true },
  });

  // Get all records that connect to the source (incoming links)
  const sourceIncomingConnections = await db.query.links.findMany({
    where: { targetId: recordId },
    columns: { sourceId: true },
  });

  // Create sets of connected record IDs for efficient lookup
  const sourceOutgoingIds = new Set(sourceOutgoingConnections.map((link) => link.targetId));
  const sourceIncomingIds = new Set(sourceIncomingConnections.map((link) => link.sourceId));
  const sourceAllConnections = new Set([...sourceOutgoingIds, ...sourceIncomingIds]);

  // Extract keywords from source record
  const sourceKeywords = extractKeywords(
    sourceRecord.title,
    sourceRecord.summary,
    sourceRecord.content,
  );

  // TODO: PERFORMANCE - This query fetches ALL records with their relationships, which is expensive
  // Alternative: Start with 1-2 hop connections and expand if needed
  const allRecords = await db.query.records.findMany({
    columns: {
      id: true,
      title: true,
      summary: true,
      content: includeContent ? true : false,
      type: true,
      recordCreatedAt: true,
      recordUpdatedAt: true,
    },
    with: {
      outgoingLinks: {
        columns: {
          predicateId: true,
          targetId: true,
        },
        with: {
          predicate: {
            columns: { type: true, slug: true },
          },
        },
      },
      incomingLinks: {
        columns: {
          predicateId: true,
          sourceId: true,
        },
        with: {
          predicate: {
            columns: { type: true, slug: true },
          },
        },
      },
    },
    where: {
      NOT: {
        id: recordId,
      },
    },
  });

  // Calculate similarity scores for each record
  const scoredRecords: RelatedRecord[] = [];

  for (const record of allRecords) {
    // Cast the record to our expected type structure
    const recordWithLinks = record as RecordWithLinks;

    // Skip records that are already directly linked to the source
    const isDirectlyLinked = sourceOutgoingIds.has(record.id) || sourceIncomingIds.has(record.id);

    if (isDirectlyLinked) {
      continue;
    }

    // Get all records that this target connects to
    const targetOutgoingIds = new Set(recordWithLinks.outgoingLinks.map((link) => link.targetId));
    const targetIncomingIds = new Set(recordWithLinks.incomingLinks.map((link) => link.sourceId));
    const targetAllConnections = new Set([...targetOutgoingIds, ...targetIncomingIds]);

    const score = await calculateSimilarityScore(
      sourceRecord,
      recordWithLinks,
      sourceKeywords,
      sourceAllConnections,
      targetAllConnections,
    );

    if (score >= minScore) {
      // TODO: PERFORMANCE - This creates an additional database query for each record
      // Consider fetching full records in the initial query or implementing a batch fetch
      // Alternative: Use the partial data we already have and only fetch full records for top results
      const fullRecord = await db.query.records.findFirst({
        where: { id: record.id },
      });

      if (fullRecord) {
        scoredRecords.push({
          record: fullRecord,
          score,
          reasons: await generateReasons(
            sourceRecord,
            fullRecord,
            score,
            sourceKeywords,
            recordWithLinks,
            sourceAllConnections,
            targetAllConnections,
          ),
        });
      }
    }
  }

  // Sort by score (descending) and return top results
  return scoredRecords.sort((a, b) => b.score - a.score).slice(0, limit);
};

/**
 * Calculates a similarity score between two records (0-1 scale)
 */
async function calculateSimilarityScore(
  source: Pick<RecordSelect, 'id' | 'title' | 'summary' | 'content' | 'type' | 'recordCreatedAt'>,
  target: RecordWithLinks,
  sourceKeywords: string[],
  sourceAllConnections: Set<number>,
  targetAllConnections: Set<number>,
): Promise<number> {
  let totalScore = 0;
  let maxPossibleScore = 0;

  // 1. Direct link relationships
  const linkScore = calculateLinkScore(
    source.id,
    target,
    sourceAllConnections,
    targetAllConnections,
  );
  totalScore += linkScore * 0.4;
  maxPossibleScore += 0.4;

  // 2. Text similarity
  const textScore = calculateTextSimilarity(source, target, sourceKeywords);
  totalScore += textScore * 0.3;
  maxPossibleScore += 0.3;

  // 3. Temporal proximity (weight: 0.15) - only include if not seeded
  const temporalScore = await calculateTemporalProximityExcludingSeeding(
    source.recordCreatedAt,
    target.recordCreatedAt,
  );

  // Check if temporal proximity was excluded due to seeding
  const isSeeded =
    temporalScore === 0 && (await isRecordSeeded(source.recordCreatedAt, target.recordCreatedAt));

  if (!isSeeded) {
    totalScore += temporalScore * 0.1;
    maxPossibleScore += 0.1;
  }

  // 4. Content overlap (weight: 0.15)
  const overlapScore = calculateContentOverlap(target, sourceKeywords);
  totalScore += overlapScore * 0.2;
  maxPossibleScore += 0.2;

  return totalScore / maxPossibleScore;
}

/**
 * Calculates score based on direct link relationships and shared connections
 */
function calculateLinkScore(
  sourceId: number,
  target: RecordWithLinks,
  sourceAllConnections: Set<number>,
  targetAllConnections: Set<number>,
): number {
  let score = 0;

  // Check for direct links between source and target
  // Direct link: source -> target (source has outgoing link to target)
  const hasOutgoingLink = target.incomingLinks.some((link) => link.sourceId === sourceId);

  // Direct link: target -> source (target has outgoing link to source)
  const hasIncomingLink = target.outgoingLinks.some((link) => link.targetId === sourceId);

  if (hasOutgoingLink || hasIncomingLink) {
    // Strong relationship: direct link exists
    score += 0.6;
  }

  // Score based on connections to similar records
  // Calculate overlap between source and target connection sets
  const connectionOverlap = new Set(
    [...sourceAllConnections].filter((id) => targetAllConnections.has(id)),
  );

  if (connectionOverlap.size > 0) {
    // Calculate Jaccard similarity for connection overlap
    const unionSize =
      sourceAllConnections.size + targetAllConnections.size - connectionOverlap.size;
    const connectionSimilarity = connectionOverlap.size / unionSize;

    // Score based on connection similarity (0.2 weight)
    score += connectionSimilarity * 0.4;
  }

  return Math.min(1, score);
}

/**
 * Calculates text similarity using keyword overlap and fuzzy matching
 */
function calculateTextSimilarity(
  source: Pick<RecordSelect, 'title' | 'summary' | 'content'>,
  target: RecordWithLinks,
  sourceKeywords: string[],
): number {
  let score = 0;

  // Title similarity
  if (source.title && target.title) {
    const titleSimilarity = calculateStringSimilarity(source.title, target.title);
    score += titleSimilarity * 0.4;
  }

  // Summary similarity
  if (source.summary && target.summary) {
    const summarySimilarity = calculateStringSimilarity(source.summary, target.summary);
    score += summarySimilarity * 0.3;
  }

  // Content similarity (if available)
  if (source.content && target.content) {
    const contentSimilarity = calculateStringSimilarity(source.content, target.content);
    score += contentSimilarity * 0.3;
  }

  // Keyword overlap
  const targetKeywords = extractKeywords(target.title, target.summary, target.content);
  const keywordOverlap = calculateKeywordOverlap(sourceKeywords, targetKeywords);
  score += keywordOverlap * 0.2;

  return Math.min(1, score);
}

/**
 * Calculates temporal proximity between two records, excluding database seeding date
 */
async function calculateTemporalProximityExcludingSeeding(
  sourceDate: string,
  targetDate: string,
): Promise<number> {
  if (!sourceDate || !targetDate) return 0;

  // Get the database seed date from record ID #1
  const seedRecord = await db.query.records.findFirst({
    where: { id: 1 },
    columns: { recordCreatedAt: true },
  });

  if (!seedRecord?.recordCreatedAt) return 0;

  const seedDate = new Date(seedRecord.recordCreatedAt);
  const sourceTime = new Date(sourceDate).getTime();
  const targetTime = new Date(targetDate).getTime();
  const seedTime = seedDate.getTime();

  // Check if either record was created on the seed date
  const sourceIsSeeded = Math.abs(sourceTime - seedTime) < 24 * 60 * 60 * 1000; // Within 24 hours
  const targetIsSeeded = Math.abs(targetTime - seedTime) < 24 * 60 * 60 * 1000; // Within 24 hours

  // If either record was created on the seed date, exclude temporal proximity
  if (sourceIsSeeded || targetIsSeeded) return 0;

  const diffDays = Math.abs(sourceTime - targetTime) / (1000 * 60 * 60 * 24);

  // Exponential decay: closer dates get higher scores
  return Math.exp(-diffDays / 30); // 30 days half-life
}

/**
 * Checks if a record was created during the database seeding date.
 */
async function isRecordSeeded(sourceDate: string, targetDate: string): Promise<boolean> {
  const seedRecord = await db.query.records.findFirst({
    where: { id: 1 },
    columns: { recordCreatedAt: true },
  });

  if (!seedRecord?.recordCreatedAt) return false;

  const seedTime = new Date(seedRecord.recordCreatedAt).getTime();
  const sourceTime = new Date(sourceDate).getTime();
  const targetTime = new Date(targetDate).getTime();

  return (
    Math.abs(sourceTime - seedTime) < 24 * 60 * 60 * 1000 ||
    Math.abs(targetTime - seedTime) < 24 * 60 * 60 * 1000
  );
}

/**
 * Calculates content overlap based on shared keywords and concepts
 */
function calculateContentOverlap(target: RecordWithLinks, sourceKeywords: string[]): number {
  const targetKeywords = extractKeywords(target.title, target.summary, target.content);
  return calculateKeywordOverlap(sourceKeywords, targetKeywords);
}

/**
 * Extracts meaningful keywords from text fields
 */
function extractKeywords(
  title?: string | null,
  summary?: string | null,
  content?: string | null,
): string[] {
  const allText = [title, summary, content].filter(Boolean).join(' ').toLowerCase();

  // Simple keyword extraction: split by spaces, filter out common words
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

  return allText
    .split(/\s+/)
    .filter((word) => word.length > 2 && !commonWords.has(word))
    .slice(0, 20); // Limit to top 20 keywords
}

/**
 * Calculates keyword overlap between two sets
 */
function calculateKeywordOverlap(keywords1: string[], keywords2: string[]): number {
  if (keywords1.length === 0 || keywords2.length === 0) return 0;

  const set1 = new Set(keywords1);
  const set2 = new Set(keywords2);

  const intersection = new Set([...set1].filter((x) => set2.has(x)));
  const union = new Set([...set1, ...set2]);

  return intersection.size / union.size; // Jaccard similarity
}

/**
 * Calculates string similarity using a simple algorithm
 */
function calculateStringSimilarity(str1: string, str2: string): number {
  const longer = str1.length > str2.length ? str1 : str2;
  const shorter = str1.length > str2.length ? str2 : str1;

  if (longer.length === 0) return 1.0;

  // TODO: ALGORITHM - Current string similarity is very basic and not accurate
  // Consider implementing:
  // - Proper Levenshtein distance algorithm
  // - Jaro-Winkler similarity for better string matching
  // - Cosine similarity for longer text
  // - Fuzzy string matching libraries like Fuse.js
  let distance = 0;
  for (let i = 0; i < shorter.length; i++) {
    if (longer[i] !== shorter[i]) distance++;
  }
  distance += longer.length - shorter.length;

  return 1 - distance / longer.length;
}

/**
 * Generates human-readable reasons for the similarity score
 */
async function generateReasons(
  source: Pick<RecordSelect, 'id' | 'title' | 'type' | 'recordCreatedAt'>,
  target: RecordSelect,
  score: number,
  sourceKeywords: string[],
  targetRecord: RecordWithLinks,
  sourceAllConnections: Set<number>,
  targetAllConnections: Set<number>,
): Promise<string[]> {
  const reasons: string[] = [];

  // Overall relationship strength
  // if (score > 0.8) reasons.push('Strongly related');
  // else if (score > 0.6) reasons.push('Moderately related');
  // else if (score > 0.4) reasons.push('Somewhat related');
  // else reasons.push('Weakly related');

  // Link relationship reasons
  const hasDirectLink =
    targetRecord.incomingLinks.some((link) => link.sourceId === source.id) ||
    targetRecord.outgoingLinks.some((link) => link.targetId === source.id);

  if (hasDirectLink) {
    reasons.push('Directly linked');
  }

  // Connection to similar records reasons
  const connectionOverlap = new Set(
    [...sourceAllConnections].filter((id) => targetAllConnections.has(id)),
  );
  if (connectionOverlap.size > 0) {
    const unionSize =
      sourceAllConnections.size + targetAllConnections.size - connectionOverlap.size;
    const connectionSimilarity = connectionOverlap.size / unionSize;
    if (connectionSimilarity > 0.5) {
      reasons.push('Connected to similar records');
    } else if (connectionSimilarity > 0.3) {
      reasons.push('Somewhat connected to similar records');
    }
  }

  // Text similarity reasons
  if (source.title && target.title) {
    const titleSimilarity = calculateStringSimilarity(source.title, target.title);
    if (titleSimilarity > 0.8) reasons.push('Very similar titles');
    else if (titleSimilarity > 0.6) reasons.push('Similar titles');
    else if (titleSimilarity > 0.4) reasons.push('Somewhat similar titles');
  }

  if (source.title && target.summary) {
    const titleSummarySimilarity = calculateStringSimilarity(source.title, target.summary);
    if (titleSummarySimilarity > 0.6) reasons.push('Title matches summary');
  }

  // Content overlap reasons
  const targetKeywords = extractKeywords(target.title, target.summary, target.content);
  const keywordOverlap = calculateKeywordOverlap(sourceKeywords, targetKeywords);

  if (keywordOverlap > 0.5) reasons.push('High keyword overlap');
  else if (keywordOverlap > 0.3) reasons.push('Moderate keyword overlap');
  else if (keywordOverlap > 0.1) reasons.push('Some keyword overlap');

  // Temporal proximity reasons
  if (source.recordCreatedAt && target.recordCreatedAt) {
    const sourceTime = new Date(source.recordCreatedAt).getTime();
    const targetTime = new Date(target.recordCreatedAt).getTime();
    const diffDays = Math.abs(sourceTime - targetTime) / (1000 * 60 * 60 * 24);

    // Check if records were created during seeding
    const isSeeded = await isRecordSeeded(source.recordCreatedAt, target.recordCreatedAt);

    if (!isSeeded) {
      if (diffDays < 1) reasons.push('Created on the same day');
      else if (diffDays < 7) reasons.push('Created within a week');
      else if (diffDays < 30) reasons.push('Created within a month');
      else if (diffDays < 90) reasons.push('Created within 3 months');
    }
  }

  return reasons;
}

export type RelatedRecordsAPIResponse = APIResponse<typeof findRelatedRecords>;
