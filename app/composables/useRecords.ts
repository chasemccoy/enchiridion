import useApiClient, { ApiEndpoints } from '@app/composables/useApiClient';
import { useQuery } from '@tanstack/vue-query';
import type { ListRecordsAPIResponse } from '@db/queries/records';
import type { ListRecordsInput } from '@shared/types/api';
import { toValue, type MaybeRef } from 'vue';

export default function useRecords(options?: MaybeRef<ListRecordsInput>) {
  const { fetch } = useApiClient();

  return useQuery({
    queryKey: ['list-records', options],
    queryFn: () =>
      fetch<ListRecordsAPIResponse>(ApiEndpoints.records, {
        method: 'POST',
        body: JSON.stringify(toValue(options)),
      }),
  });
}
