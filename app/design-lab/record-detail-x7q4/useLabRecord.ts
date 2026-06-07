// Tiny composable: fetches the sample record + its links + related so each
// variant can render against real data without re-deriving the wiring used in
// RecordDetailView. Lab-only.

import useRecord from '@app/composables/useRecord';
import useRelatedRecords from '@app/composables/useRelatedRecords';
import { computed } from 'vue';
import { getPredicateSafe, type PredicateSlug } from '@shared/types';
import { sampleSlug } from './manifest';

export function humanizePredicate(slug: string, direction: 'outgoing' | 'incoming' = 'outgoing'): string {
  const pred = getPredicateSafe(slug as PredicateSlug);
  if (!pred) return slug.replace(/_/g, ' ');
  // PREDICATES has both an outgoing entry and its inverse; getPredicateSafe
  // returns whichever slug matches. The display name is the predicate's name,
  // which already reads naturally for the slug's direction.
  if (direction === 'incoming') {
    // Heuristic: if caller asks for incoming display of an outgoing slug,
    // fall back to the slug-with-spaces. Most call sites already pass the
    // right slug for their direction.
    return pred.name;
  }
  return pred.name;
}

export function useLabRecord() {
  const { getRecordBySlug, getRecordLinks, getSimilarRecords } = useRecord();
  const { data: record } = getRecordBySlug(sampleSlug);
  const recordId = computed(() => record.value?.id ?? null);
  const isFetched = computed(() => !!recordId.value);
  const { data: links } = getRecordLinks(recordId, isFetched);
  const { data: similarRecords } = getSimilarRecords(recordId, isFetched);
  const { data: relatedRecords } = useRelatedRecords(
    computed(() => sampleSlug),
    isFetched,
  );

  return { record, links, relatedRecords, similarRecords };
}
