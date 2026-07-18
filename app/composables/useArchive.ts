import useApiClient from '@app/composables/useApiClient';
import type { ArchiveSelect } from '@db/schema';
import { useMutation, useQueryClient } from '@tanstack/vue-query';

export default function useArchive() {
  const { fetch, backendBaseUrl } = useApiClient();
  const queryClient = useQueryClient();

  /** Trigger (or re-trigger) a local archive of a record's page. */
  function archiveRecord() {
    return useMutation({
      mutationFn: (id: number) =>
        fetch<ArchiveSelect>(`/record/${id}/archive`, {
          method: 'POST',
        }),
      onSuccess: () => {
        // The record carries its archive via the `archives` relation, so refetch
        // the record to pick up the new state.
        queryClient.invalidateQueries({ queryKey: ['get-record-by-slug'] });
        queryClient.invalidateQueries({ queryKey: ['get-record'] });
      },
    });
  }

  /** Same-origin URL of a stored archive's offline copy (null until archived). */
  function archiveSrc(archive: Pick<ArchiveSelect, 'path'> | null | undefined): string | null {
    if (!archive?.path) return null;
    return `${backendBaseUrl}/archives/${archive.path}/index.html`;
  }

  return {
    archiveRecord,
    archiveSrc,
  };
}
