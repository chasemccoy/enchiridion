import useApiClient from '@app/composables/useApiClient';
import { useQuery } from '@tanstack/vue-query';
import type { FindAllRelatedRecordsAPIResponse } from '@db/queries/related-records';
import { toValue, type MaybeRef } from 'vue';

type OptionalMaybeRef<T> = MaybeRef<T | null>;

export default function useRelatedRecords(
  slug: OptionalMaybeRef<string>,
  enabled: MaybeRef<boolean> = true,
) {
  const { fetch } = useApiClient();

  return useQuery({
    queryKey: ['get-related-records', slug],
    queryFn: () => fetch<FindAllRelatedRecordsAPIResponse>(`/record/${toValue(slug)}/related`),
    enabled: () => toValue(enabled) && toValue(slug) != null,
  });
}
