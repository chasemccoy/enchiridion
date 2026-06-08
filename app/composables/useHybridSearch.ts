import useApiClient from '@app/composables/useApiClient';
import { useQuery } from '@tanstack/vue-query';
import { computed, toValue, type MaybeRef } from 'vue';
import type { HybridSearchListRecordsAPIResponse } from '@db/queries/hybrid-search';

export type HybridSearchResults = HybridSearchListRecordsAPIResponse;
export type HybridSearchResult = HybridSearchResults[number];

/**
 * Hybrid search: reciprocal-rank-fusion of full-text + semantic, behind the
 * `/search/hybrid` endpoint. Returns rows in the same shape as the other search
 * composables, with a fused relevancy `score` attached.
 */
export default function useHybridSearch(
  query?: MaybeRef<string>,
  enabled: MaybeRef<boolean> = true,
  limit: MaybeRef<number> = 100,
) {
  const { fetch } = useApiClient();

  const params = computed(() => {
    return new URLSearchParams({
      q: toValue(query) ?? '',
      limit: String(toValue(limit)),
    });
  });

  return useQuery({
    queryKey: ['hybrid-search', query, limit],
    queryFn: () => fetch<HybridSearchResults>(`/search/hybrid?${params.value.toString()}`),
    enabled,
    placeholderData: (previousData) => previousData,
  });
}
