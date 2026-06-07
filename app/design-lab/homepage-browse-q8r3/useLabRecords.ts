// Shared data + derived helpers for the homepage-browse exploration.
// One fetch of the full record set (same shape the real home uses), plus the
// derivations each variant needs: media lookup, month grouping, type buckets,
// tag-frequency, and serendipitous "older" picks.
import useApiClient from '@app/composables/useApiClient';
import useRecords from '@app/composables/useRecords';
import type { ListRecordsAPIResponse } from '@db/queries/records';
import { isPredicateType } from '@shared/types';
import { computed } from 'vue';

export type LabRecord = ListRecordsAPIResponse[number];

export function useLabRecords() {
  const { backendBaseUrl } = useApiClient();
  const { data, isLoading } = useRecords({
    limit: 100000,
    filters: { hideUntitledChildren: true },
    orderBy: [{ field: 'recordCreatedAt', direction: 'desc' }],
  });

  const records = computed<LabRecord[]>(() => data.value ?? []);

  const titled = computed(() => records.value.filter((r) => r.title));

  const withImage = computed(() => titled.value.filter((r) => firstImage(r)));

  const byType = computed(() => ({
    artifact: titled.value.filter((r) => r.type === 'artifact'),
    concept: titled.value.filter((r) => r.type === 'concept'),
    entity: titled.value.filter((r) => r.type === 'entity'),
  }));

  // Records grouped by "Month Year", newest group first — mirrors the real home.
  const byMonth = computed(() => {
    const groups: { label: string; records: LabRecord[] }[] = [];
    const index = new Map<string, LabRecord[]>();
    for (const r of titled.value) {
      if (!r.recordCreatedAt) continue;
      const d = new Date(r.recordCreatedAt + 'Z');
      const label = d.toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
      if (!index.has(label)) {
        const bucket: LabRecord[] = [];
        index.set(label, bucket);
        groups.push({ label, records: bucket });
      }
      index.get(label)!.push(r);
    }
    return groups;
  });

  // Tag frequency across the whole graph — concepts/entities a record points at
  // via a description predicate (tagged_with, etc.). The spine of "themes".
  const topTags = computed(() => {
    const tally = new Map<string, { slug: string; title: string; count: number; type: string }>();
    for (const r of records.value) {
      for (const link of r.outgoingLinks ?? []) {
        if (!isPredicateType(link.predicate, 'description')) continue;
        const t = link.target;
        if (!t?.slug) continue;
        const entry = tally.get(t.slug) ?? {
          slug: t.slug,
          title: t.title ?? t.slug,
          count: 0,
          type: t.type,
        };
        entry.count += 1;
        tally.set(t.slug, entry);
      }
    }
    return [...tally.values()].sort((a, b) => b.count - a.count);
  });

  const recordBySlug = computed(() => {
    const m = new Map<string, LabRecord>();
    for (const r of records.value) m.set(r.slug, r);
    return m;
  });

  // Concepts only, popularity-ranked. The list endpoint's link targets only
  // carry {id,title,slug} (no type), so we resolve the real type via the
  // top-level record map; description-predicate targets are concepts anyway.
  const topConcepts = computed(() =>
    topTags.value.filter((t) => {
      const rec = recordBySlug.value.get(t.slug);
      return !rec || rec.type === 'concept';
    }),
  );

  // concept slug -> the records tagged with it (newest first, inherited order).
  const recordsByConcept = computed(() => {
    const m = new Map<string, LabRecord[]>();
    for (const r of titled.value) {
      for (const t of tagsOf(r)) {
        if (!t?.slug) continue;
        if (!m.has(t.slug)) m.set(t.slug, []);
        m.get(t.slug)!.push(r);
      }
    }
    return m;
  });

  // Serendipity: a spread of older records (skip the most-recent slice), stepped
  // so picks aren't clustered. Deterministic — no Math.random across renders.
  const olderPicks = computed(() => {
    const pool = titled.value.slice(40);
    if (pool.length === 0) return [];
    const step = Math.max(1, Math.floor(pool.length / 18));
    const out: LabRecord[] = [];
    for (let i = 0; i < pool.length && out.length < 12; i += step) out.push(pool[i]!);
    return out;
  });

  return {
    backendBaseUrl,
    isLoading,
    records,
    titled,
    withImage,
    byType,
    byMonth,
    topTags,
    topConcepts,
    recordBySlug,
    recordsByConcept,
    olderPicks,
  };
}

export function firstImage(record: LabRecord): string | null {
  const m = record.media?.[0];
  return m && m.type === 'image' ? m.url : null;
}

// Tags (description-predicate targets) attached to a single record.
export function tagsOf(record: LabRecord) {
  return (record.outgoingLinks ?? [])
    .filter((l) => isPredicateType(l.predicate, 'description'))
    .map((l) => l.target)
    .filter((t) => t?.slug);
}

export function creatorOf(record: LabRecord) {
  return (record.outgoingLinks ?? []).find((l) => l.predicate === 'created_by')?.target ?? null;
}

// A compact editorial byline: creator, then host, then date.
export function bylineParts(record: LabRecord): string[] {
  const parts: string[] = [];
  const creator = creatorOf(record);
  if (creator?.title) parts.push(`By ${creator.title}`);
  const host = hostOf(record);
  if (host) parts.push(host);
  if (record.recordCreatedAt) {
    parts.push(
      new Date(record.recordCreatedAt + 'Z').toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
      }),
    );
  }
  return parts;
}

export function hostOf(record: LabRecord): string | null {
  if (!record.url) return null;
  try {
    return new URL(record.url).hostname.replace(/^www\./, '');
  } catch {
    return null;
  }
}

// Flatten markdown-ish text into a clean preview one-liner.
export function plain(input?: string | null): string {
  if (!input) return '';
  return input
    .replace(/`{1,3}[^`]*`{1,3}/g, '')
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/[#>*_~]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}
