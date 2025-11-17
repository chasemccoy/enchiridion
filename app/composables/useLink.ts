import useApiClient from '@app/composables/useApiClient';
import type { DeleteLinkAPIResponse, UpsertLinkAPIResponse } from '@db/queries/links';
import type { LinkInsert } from '@db/schema';
import { useMutation, useQueryClient } from '@tanstack/vue-query';

export default function useLink() {
  const { fetch } = useApiClient();
  const queryClient = useQueryClient();

  function upsertLink() {
    return useMutation({
      mutationFn: (data: LinkInsert) =>
        fetch<UpsertLinkAPIResponse>(`/link`, {
          method: 'PUT',
          body: JSON.stringify(data),
        }),
      onSuccess: ({ sourceId, targetId }) => {
        ['get-record', 'get-record-by-slug', 'get-record-links', 'get-related-records'].forEach(
          (key) => {
            queryClient.invalidateQueries({ queryKey: [key, sourceId] });
            queryClient.invalidateQueries({ queryKey: [key, targetId] });
          },
        );
      },
    });
  }

  function deleteLink() {
    return useMutation({
      mutationFn: (id: number) =>
        fetch<DeleteLinkAPIResponse>(`/link/${id}`, {
          method: 'DELETE',
        }),
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ['get-record'] });
        queryClient.invalidateQueries({ queryKey: ['get-record-by-slug'] });
        queryClient.invalidateQueries({ queryKey: ['get-record-links'] });
        queryClient.invalidateQueries({ queryKey: ['get-related-records'] });
      },
    });
  }

  return {
    upsertLink,
    deleteLink,
  };
}
