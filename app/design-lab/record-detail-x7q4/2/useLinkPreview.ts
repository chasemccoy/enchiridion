// Fetches the full record for a link target so variants can show host,
// summary, tags, type icon — the metadata they'd lose if they only used the
// title+slug returned by /record/:id/links. Same pattern RecordLink.vue uses.

import useRecord from '@app/composables/useRecord';
import { computed, type MaybeRefOrGetter, toValue } from 'vue';
import { getIconForRecordType } from '@app/utils';
import { isPredicateType } from '@shared/types';

function getHost(url: string): string {
  try {
    return new URL(url).host.replace(/^www\./, '');
  } catch {
    return url;
  }
}

function faviconFor(url: string): string | null {
  try {
    const host = new URL(url).host;
    return `https://www.google.com/s2/favicons?domain=${host}&sz=32`;
  } catch {
    return null;
  }
}

export function useLinkPreview(id: MaybeRefOrGetter<number>) {
  const { getRecord } = useRecord();
  const { data: record } = getRecord(id);

  const view = computed(() => {
    const r = record.value;
    if (!r) return null;
    const tagEdges =
      r.outgoingLinks?.filter((l) => isPredicateType(l.predicate, 'description')) ?? [];
    const tags = tagEdges
      .map((l) => l.target.title || l.target.slug)
      .filter(Boolean)
      .slice(0, 3);
    const tagLinks = tagEdges
      .map((l) => ({ slug: l.target.slug, title: l.target.title || l.target.slug }))
      .slice(0, 4);
    return {
      tagLinks,
      id: r.id,
      slug: r.slug,
      title: r.title,
      summary: r.summary,
      url: r.url,
      host: r.url ? getHost(r.url) : null,
      favicon: r.url ? faviconFor(r.url) : null,
      type: r.type,
      icon: r.type ? getIconForRecordType(r.type) : null,
      notes: r.notes,
      tags,
    };
  });

  // Fallback display when the record hasn't loaded yet — read from the link
  // target so the row doesn't flash empty. Useful for the first paint.
  void toValue(id);
  return { view };
}
