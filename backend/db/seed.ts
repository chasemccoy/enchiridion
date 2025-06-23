import {
  links,
  predicates,
  records,
  type PredicateInsert,
  type RecordInsert,
} from './schema/records';
import { db } from '.';
import { slugify } from '@shared/lib/formatting';

export const recordSeed: RecordInsert[] = [
  {
    slug: 'chase-mccoy',
    title: 'Chase McCoy',
    type: 'entity',
    isCurated: true,
  },
  {
    slug: 'enchiridion',
    title: 'Enchiridion',
    type: 'artifact',
    isCurated: true,
  },
  ...[
    'aphorism',
    'article',
    'blog',
    'book',
    'definition',
    'essay',
    'film',
    'idea',
    'newsletter',
    'novel',
    'podcast',
    'product',
    'quote',
    'short story',
    'talk',
    'tool',
    'tweet',
    'video',
    'website',
  ].map((type) => ({
    slug: slugify(type),
    title: type,
    type: 'concept' as const,
    isCurated: true,
  })),
];

const insertedRecords = await db.insert(records).values(recordSeed).returning({ id: records.id });

/**
 * Canonical predicate vocabulary
 * ──────────────────────────────
 * • Only rows with `canonical: true` are stored in `links`.
 * • `inverseSlug` supplies a readable label when traversing the edge
 *   in the opposite direction.
 * • Active-present verb style: has_creator, contained_by, format_of …
 */

export const predicateSeed: PredicateInsert[] = [
  /* ────────────  Creation  ──────────── */
  {
    slug: 'created_by', // work → person
    name: 'created by',
    type: 'creation',
    role: 'creator',
    inverseSlug: 'creator_of',
    canonical: true,
  },
  {
    slug: 'creator_of', // person ← work
    name: 'creator of',
    type: 'creation',
    role: 'creator',
    inverseSlug: 'created_by',
    canonical: false,
  },
  {
    slug: 'via', // work → referrer
    name: 'via',
    type: 'creation',
    role: 'referrer',
    inverseSlug: 'source_for',
    canonical: true,
  },
  {
    slug: 'source_for', // referrer ← work
    name: 'source for',
    type: 'creation',
    role: 'referrer',
    inverseSlug: 'via',
    canonical: false,
  },
  {
    slug: 'edited_by',
    name: 'edited by',
    type: 'creation',
    role: 'editor',
    inverseSlug: 'editor_of',
    canonical: true,
  },
  {
    slug: 'editor_of',
    name: 'editor of',
    type: 'creation',
    role: 'editor',
    inverseSlug: 'edited_by',
    canonical: false,
  },

  /* ─────── Containment (child → parent) ─────── */
  {
    slug: 'contained_by',
    name: 'contained by',
    type: 'containment',
    inverseSlug: 'contains',
    canonical: true,
  },
  {
    slug: 'contains',
    name: 'contains',
    type: 'containment',
    inverseSlug: 'contained_by',
    canonical: false,
  },
  {
    slug: 'quotes',
    name: 'quotes',
    type: 'containment',
    inverseSlug: 'quoted_in',
    canonical: true,
  },
  {
    slug: 'quoted_in',
    name: 'quoted in',
    type: 'containment',
    inverseSlug: 'quotes',
    canonical: false,
  },

  /* ───────────  Description  ─────────── */
  {
    slug: 'has_format',
    name: 'has format',
    type: 'description',
    inverseSlug: 'format_of',
    canonical: true,
  },
  {
    slug: 'format_of',
    name: 'format of',
    type: 'description',
    inverseSlug: 'has_format',
    canonical: false,
  },
  {
    slug: 'tagged_with',
    name: 'tagged with',
    type: 'description',
    inverseSlug: 'tag_of',
    canonical: true,
  },
  {
    slug: 'tag_of',
    name: 'tag of',
    type: 'description',
    inverseSlug: 'tagged_with',
    canonical: false,
  },

  /* ───────────  Reference  ─────────── */
  {
    slug: 'references',
    name: 'references',
    type: 'reference',
    inverseSlug: 'referenced_by',
    canonical: true,
  },
  {
    slug: 'referenced_by',
    name: 'referenced by',
    type: 'reference',
    inverseSlug: 'references',
    canonical: false,
  },
  {
    slug: 'about',
    name: 'about',
    type: 'reference',
    inverseSlug: 'subject_of',
    canonical: true,
  },
  {
    slug: 'subject_of',
    name: 'subject of',
    type: 'reference',
    inverseSlug: 'about',
    canonical: false,
  },

  /* ───────────  Association  ─────────── */
  {
    slug: 'related_to',
    name: 'related to',
    type: 'association',
    inverseSlug: 'related_to', // self-inverse
    canonical: true,
  },

  /* ───────────  Identity  ─────────── */
  {
    slug: 'same_as',
    name: 'same as',
    type: 'identity',
    inverseSlug: 'same_as',
    canonical: true, // self-inverse
  },
];

const insertedPredicates = await db
  .insert(predicates)
  .values(predicateSeed)
  .returning({ id: predicates.id, slug: predicates.slug });

const createdByPredicate = insertedPredicates.find((p) => p.slug === 'created_by');

if (createdByPredicate) {
  await db.insert(links).values({
    sourceId: insertedRecords[1].id,
    targetId: insertedRecords[0].id,
    predicateId: createdByPredicate!.id,
    notes: 'Created during initial seeding',
  });
}
