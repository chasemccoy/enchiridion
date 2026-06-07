import { db } from '@db/index';
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

/** Collect the ids of every record directly linked to `recordId`, in either direction. */
const linkedRecordIds = async (recordId: RecordSelect['id']): Promise<Set<number>> => {
  const rows = await db.query.links.findMany({
    columns: { sourceId: true, targetId: true },
    where: {
      OR: [{ sourceId: recordId }, { targetId: recordId }],
    },
  });

  const ids = new Set<number>();
  for (const row of rows) {
    ids.add(row.sourceId === recordId ? row.targetId : row.sourceId);
  }
  return ids;
};

/**
 * Find records similar to a given record via cosine similarity over their
 * sqlite-vec embeddings. Records already linked to the source are excluded so
 * the list surfaces only net-new suggestions. Returns an empty array if the
 * source record has no stored embedding (run `pnpm embed` to backfill).
 */
export const findSimilarRecords = async (input: SimilarRecordsInput): Promise<SimilarRecord[]> => {
  const { recordId, limit = 10, minScore = 0.1 } = input;
  const excludeIds = await linkedRecordIds(recordId);
  return findSimilarRecordsByEmbedding({ recordId, limit, minScore, excludeIds });
};

export type SimilarRecordsAPIResponse = APIResponse<typeof findSimilarRecords>;
