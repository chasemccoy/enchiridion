import useApiClient from '@app/composables/useApiClient';
import type { SyncRunAPIResponse } from '@api/integrations';
import { useMutation, useQueryClient } from '@tanstack/vue-query';

export default function useIntegrations() {
  const { fetch } = useApiClient();
  const queryClient = useQueryClient();

  function readwise() {
    return useMutation({
      mutationFn: () => fetch<SyncRunAPIResponse>('/sync/readwise', { method: 'POST' }),
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ['list-records'] });
      },
    });
  }

  return { readwise };
}
