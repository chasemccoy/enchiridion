import { listRecords, type ListRecordsAPIResponse } from '@db/queries/records';
import {
  semanticSearchListRecords,
  type SemanticSearchListRecordsAPIResponse,
} from '@db/queries/semantic-search';
import { isEmbeddingEnabled } from '@integrations/embeddings';
import type { APIResponse } from '@shared/types/api';

/** RRF constant from the Cormack/Clarke/Büttcher paper. */
const RRF_K = 60;

export interface HybridSearchInput {
  query: string;
  limit?: number;
}

/**
 * Hybrid search: reciprocal-rank-fusion of the trigram-style text match
 * (`listRecords`' text filter — strong on exact tokens like names, domains,
 * slugs) and embedding-based semantic search (strong on meaning/paraphrase).
 *
 * Each retriever contributes `1 / (RRF_K + rank)` to a record's fused score; the
 * two rankings are merged and the top `limit` returned with that fused `score`
 * attached (same row shape as the other search queries, so the UI can reuse
 * RecordCard). Degrades to text-only when embeddings are disabled.
 */
export const hybridSearchListRecords = async ({ query, limit = 50 }: HybridSearchInput) => {
  const trimmed = query.trim();
  if (!trimmed) return [];

  // Over-fetch from each retriever so fusion has enough overlap to rerank well.
  const overFetch = Math.max(limit * 2, 40);

  const semanticPromise = isEmbeddingEnabled()
    ? semanticSearchListRecords({ query: trimmed, limit: overFetch })
    : Promise.resolve<SemanticSearchListRecordsAPIResponse>([]);

  const [textRows, semanticRows] = await Promise.all([
    listRecords({ filters: { text: trimmed }, limit: overFetch }),
    semanticPromise,
  ]);

  const scores = new Map<number, number>();
  const byId = new Map<number, ListRecordsAPIResponse[number]>();

  const fuse = (rows: ReadonlyArray<ListRecordsAPIResponse[number]>) => {
    rows.forEach((row, rank) => {
      byId.set(row.id, row);
      scores.set(row.id, (scores.get(row.id) ?? 0) + 1 / (RRF_K + rank));
    });
  };
  fuse(textRows);
  fuse(semanticRows);

  return [...scores.entries()]
    .sort(([, a], [, b]) => b - a)
    .slice(0, limit)
    .map(([id, score]) => ({ ...byId.get(id)!, score }));
};

export type HybridSearchListRecordsAPIResponse = APIResponse<typeof hybridSearchListRecords>;
