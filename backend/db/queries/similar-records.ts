import { type RecordSelect } from '@db/schema';
import { findSimilarRecordsByEmbedding } from '@integrations/embeddings';
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
  /** No-op, retained for API back-compat. */
  includeContent?: boolean;
}

/**
 * Find records similar to a given record via cosine similarity over their
 * sqlite-vec embeddings. Returns an empty array if the source record has no
 * stored embedding (run `pnpm embed` to backfill).
 */
export const findSimilarRecords = async (input: SimilarRecordsInput): Promise<SimilarRecord[]> => {
  const { recordId, limit = 10, minScore = 0.1 } = input;
  return findSimilarRecordsByEmbedding({ recordId, limit, minScore });
};

export type SimilarRecordsAPIResponse = APIResponse<typeof findSimilarRecords>;
