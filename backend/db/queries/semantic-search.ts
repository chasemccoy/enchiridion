import { db } from '@db/index';
import { isEmbeddingEnabled, searchRecordsByEmbedding } from '@integrations/embeddings';
import {
  containmentPredicateSlugs,
  creationPredicateSlugs,
  descriptionPredicateSlugs,
  type PredicateSlug,
} from '@shared/types';
import type { APIResponse } from '@shared/types/api';

// Mirrors `inlineOutgoingPredicateSlugs` in queries/records.ts so semantic-
// search hits expose the same outgoing-link shape as `listRecords`.
const inlineOutgoingPredicateSlugs: PredicateSlug[] = [
  ...creationPredicateSlugs,
  ...descriptionPredicateSlugs,
  ...containmentPredicateSlugs,
];

export interface SemanticSearchInput {
  query: string;
  limit?: number;
  /** Drop hits whose cosine similarity is below this threshold. Defaults to 0.2. */
  minScore?: number;
}

/**
 * Run a natural-language query against the embedding index and hydrate each hit
 * to the same shape `listRecords` returns, with a cosine-similarity `score`
 * (in [-1, 1]) attached. Order matches the embedding ranking — most similar
 * first. Returns an empty array when embeddings are disabled or no records hit.
 */
export const semanticSearchListRecords = async ({
  query,
  limit = 50,
  minScore = 0.2,
}: SemanticSearchInput) => {
  if (!isEmbeddingEnabled()) return [];

  const hits = await searchRecordsByEmbedding({ query, limit, minScore });
  if (hits.length === 0) return [];

  const ids = hits.map((hit) => hit.record.id);

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
          predicate: true,
        },
        where: {
          predicate: {
            in: inlineOutgoingPredicateSlugs,
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
        },
      },
      incomingLinks: {
        columns: {
          predicate: true,
        },
      },
    },
    where: {
      id: { in: ids },
    },
  });

  const byId = new Map(rows.map((row) => [row.id, row]));

  return hits.flatMap((hit) => {
    const row = byId.get(hit.record.id);
    return row ? [{ ...row, score: hit.score }] : [];
  });
};

export type SemanticSearchListRecordsAPIResponse = APIResponse<typeof semanticSearchListRecords>;
