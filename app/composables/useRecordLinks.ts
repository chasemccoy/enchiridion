import type { LinksForRecordAPIResponse } from '@db/queries/records';
import type { FindAllRelatedRecordsAPIResponse } from '@db/queries/related-records';
import { getPredicateSafe, getInverse, isPredicateType, type PredicateSlug } from '@shared/types';
import { computed, type MaybeRefOrGetter } from 'vue';
import { toValue } from 'vue';

type OutgoingLink = NonNullable<LinksForRecordAPIResponse>['outgoingLinks'][number];
type IncomingLink = NonNullable<LinksForRecordAPIResponse>['incomingLinks'][number];
type Link = OutgoingLink | IncomingLink;

// VirtualLink represents a recursive relation without a real database link.
// It includes all properties needed to render like a real link.
// `predicate` is intentionally optional and unset on construction: it gates the
// PredicateSelect dropdown in RecordLink.vue (`v-if="localPredicateSlug"`), so
// leaving it undefined hides the gear/delete actions on virtual rows. That's
// load-bearing — the virtual `id` collides with real link ids, so exposing
// those actions would let the user clobber unrelated link rows.
export type VirtualLink = Omit<
  OutgoingLink,
  'predicate' | 'recordCreatedAt' | 'recordUpdatedAt'
> & {
  predicate?: PredicateSlug;
};

export type LinkWithDirection = {
  link: Link | VirtualLink;
  direction: 'incoming' | 'outgoing';
};

function getPredicateName(slug: PredicateSlug, direction: 'incoming' | 'outgoing'): string {
  const predicate = getPredicateSafe(slug);
  if (!predicate) return slug;
  if (direction === 'incoming') return getInverse(slug).name;
  return predicate.name;
}

export default function useRecordLinks(
  links: MaybeRefOrGetter<LinksForRecordAPIResponse | undefined>,
  relatedRecords: MaybeRefOrGetter<FindAllRelatedRecordsAPIResponse | undefined>,
  currentRecordId: MaybeRefOrGetter<number | undefined>,
) {
  const linksByPredicateName = computed(() => {
    const linksValue = toValue(links);
    if (!linksValue) return {};

    const grouped: Record<string, Array<LinkWithDirection>> = {};

    const addRealLink = (link: Link, direction: 'incoming' | 'outgoing') => {
      // Skip containment links - handled separately
      if (isPredicateType(link.predicate, 'containment')) return;

      const predicateName = getPredicateName(link.predicate, direction);

      if (!grouped[predicateName]) {
        grouped[predicateName] = [];
      }
      grouped[predicateName]!.push({ link, direction });
    };

    linksValue.outgoingLinks?.forEach((link) => addRealLink(link, 'outgoing'));
    linksValue.incomingLinks?.forEach((link) => addRealLink(link, 'incoming'));

    const relatedRecordsValue = toValue(relatedRecords);
    const currentRecordIdValue = toValue(currentRecordId);

    if (relatedRecordsValue && relatedRecordsValue.length > 0 && currentRecordIdValue) {
      // Get record IDs that already have real links
      const recordsWithRealLinks = new Set<number>();
      const existingRelatedLinks = grouped['related to'] ?? [];

      for (const linkData of existingRelatedLinks) {
        const recordId =
          linkData.direction === 'outgoing' ? linkData.link.targetId : linkData.link.sourceId;
        recordsWithRealLinks.add(recordId);
      }

      // Create virtual links for records without real links
      const virtualLinks: Array<LinkWithDirection> = [];

      for (const { record } of relatedRecordsValue) {
        if (!recordsWithRealLinks.has(record.id)) {
          const virtualLink: VirtualLink = {
            id: currentRecordIdValue + record.id, // Generate unique ID
            sourceId: currentRecordIdValue,
            targetId: record.id,
            notes: null,
            target: {
              title: record.title,
              slug: record.slug,
            },
          };
          virtualLinks.push({ link: virtualLink, direction: 'outgoing' });
        }
      }

      // Add virtual links to the related_to section
      if (virtualLinks.length > 0) {
        if (!grouped['related to']) {
          grouped['related to'] = [];
        }
        grouped['related to'].push(...virtualLinks);
      }
    }

    return Object.fromEntries(Object.entries(grouped).filter(([, links]) => links.length > 0));
  });

  return {
    linksByPredicateName,
  };
}
