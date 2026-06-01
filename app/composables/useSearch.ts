import useApiClient from '@app/composables/useApiClient';
import { useQuery } from '@tanstack/vue-query';
import { computed, toValue, type MaybeRef } from 'vue';
import type { ListRecordsAPIResponse } from '@db/queries/records';

export default function useSearch(query?: MaybeRef<string>, enabled: MaybeRef<boolean> = true) {
  const { fetch } = useApiClient();

  const params = computed(() => {
    return new URLSearchParams({ q: toValue(query) ?? '' });
  });

  return useQuery({
    queryKey: ['search', query],
    queryFn: () => fetch<ListRecordsAPIResponse>(`/search?${params.value.toString()}`),
    enabled,
    placeholderData: (previousData) => previousData,
  });
}
