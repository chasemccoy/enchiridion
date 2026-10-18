import useLink from '@app/composables/useLink';
import useMedia from '@app/composables/useMedia';
import type { LinkInsert } from '@db/schema';

/**
 * What a new record's form adds once the record exists: its files and its links. Each is awaited on its own
 * (`mutateAsync`), since a shared mutation reports only its last call, and a failure is reported once with a count,
 * so an attachment or link that didn't save is never lost silently.
 */
export default function useNewRecordExtras() {
  const toast = useToast();
  const { mutateAsync: uploadMediaAsync } = useMedia().uploadMedia();
  const { mutateAsync: upsertLinkAsync } = useLink().upsertLink();

  async function addExtras(
    recordId: number,
    files: Array<{ file?: File | null }>,
    links: Array<Omit<LinkInsert, 'sourceId'>>,
  ) {
    const results = await Promise.allSettled([
      ...files.flatMap(({ file }) => (file ? [uploadMediaAsync({ file, recordId })] : [])),
      ...links.map((link) => upsertLinkAsync({ sourceId: recordId, ...link })),
    ]);
    const failures = results.filter(
      (result): result is PromiseRejectedResult => result.status === 'rejected',
    );
    if (failures.length === 0) return;
    const first = failures[0]?.reason;
    toast.add({
      title: `The record was saved, but ${failures.length} ${failures.length === 1 ? 'attachment or link' : 'attachments or links'} didn’t`,
      description: first instanceof Error ? first.message.slice(0, 250) : undefined,
      color: 'error',
      icon: 'i-lucide-circle-alert',
    });
  }

  return { addExtras };
}
