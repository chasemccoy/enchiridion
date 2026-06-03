import useApiClient from '@app/composables/useApiClient';
import { useQuery } from '@tanstack/vue-query';
import { computed, toValue, type MaybeRef } from 'vue';
import type { SemanticSearchListRecordsAPIResponse } from '@db/queries/semantic-search';

export type SemanticSearchResults = SemanticSearchListRecordsAPIResponse;
export type SemanticSearchResult = SemanticSearchResults[number];

export default function useSemanticSearch(
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
    queryKey: ['semantic-search', query, limit],
    queryFn: () => fetch<SemanticSearchResults>(`/search/semantic?${params.value.toString()}`),
    enabled,
    placeholderData: (previousData) => previousData,
  });
}
