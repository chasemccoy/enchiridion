import useApiClient from '@app/composables/useApiClient';
import type { ArchiveSelect } from '@db/schema';
import type { ArchiveVersion } from '@shared/types/archive';
import { useMutation, useQuery, useQueryClient } from '@tanstack/vue-query';
import { toValue, type MaybeRefOrGetter } from 'vue';

export default function useArchive() {
  const { fetch, backendBaseUrl } = useApiClient();
  const queryClient = useQueryClient();

  /**
   * Trigger (or re-trigger) a local archive of a record's page. The backend
   * responds 202 with a 'pending' archive row and captures in the background;
   * the record queries poll while pending to pick up the outcome. `at` (a date,
   * "latest" or a web.archive.org link) archives that past version from the
   * Wayback Machine into the same timeline instead.
   */
  function archiveRecord() {
    const toast = useToast();
    return useMutation({
      mutationFn: ({ id, at }: { id: number; at?: string }) =>
        fetch<ArchiveSelect>(`/record/${id}/archive`, {
          method: 'POST',
          body: JSON.stringify(at ? { at } : {}),
        }),
      onError: (error) => {
        toast.add({
          title: 'Could not archive page',
          description: error.message,
          color: 'error',
        });
      },
      onSettled: () => {
        // The record carries its archive via the `archives` relation, so refetch
        // the record to pick up the new state — after errors too, since another
        // in-flight run (409) still means the row changed underneath us.
        queryClient.invalidateQueries({ queryKey: ['get-record-by-slug'] });
        queryClient.invalidateQueries({ queryKey: ['get-record'] });
      },
    });
  }

  /** A record's archive captures, newest first: the current copy and its past versions. */
  function archiveVersions(
    recordId: MaybeRefOrGetter<number>,
    enabled: MaybeRefOrGetter<boolean> = true,
  ) {
    return useQuery({
      queryKey: ['archive-versions', recordId],
      queryFn: () => fetch<ArchiveVersion[]>(`/record/${toValue(recordId)}/archive/versions`),
      enabled,
    });
  }

  /** Same-origin URL of one capture (a version's folder) in the archive library. */
  function versionSrc(version: Pick<ArchiveVersion, 'path'>): string {
    return `${backendBaseUrl}/archives/${version.path}/index.html`;
  }

  /** Same-origin URL of a stored archive's offline copy (null until archived). */
  function archiveSrc(archive: Pick<ArchiveSelect, 'path'> | null | undefined): string | null {
    if (!archive?.path) return null;
    return `${backendBaseUrl}/archives/${archive.path}/index.html`;
  }

  return {
    archiveRecord,
    archiveSrc,
    archiveVersions,
    versionSrc,
  };
}
