/**
 * Canonical predicate vocabulary
 * ──────────────────────────────
 * Predicates define the types of relationships between records.
 * They are stored in code (not in the database) for compile-time
 * type safety and simpler lookups.
 *
 * • Only predicates with `canonical: true` are stored in `links`.
 * • `inverseSlug` supplies a readable label when traversing the edge
 *   in the opposite direction.
 */

export const predicateTypeEnum = [
  'creation', // authorship, ownership …
  'containment', // has_part, sequence …
  'description', // about, tag …
  'association', // related_to, similar_to …
  'reference', // cites, responds_to …
  'identity', // instance_of, same_as …
] as const;

export type PredicateType = (typeof predicateTypeEnum)[number];

export interface Predicate {
  slug: string;
  name: string;
  type: PredicateType;
  role?: string;
  inverseSlug: string;
  canonical: boolean;
}

const PREDICATES_LIST = [
  /* ────────────  Creation  ──────────── */
  {
    slug: 'created_by',
    name: 'created by',
    type: 'creation',
    role: 'creator',
    inverseSlug: 'creator_of',
    canonical: true,
  },
  {
    slug: 'creator_of',
    name: 'creator of',
    type: 'creation',
    role: 'creator',
    inverseSlug: 'created_by',
    canonical: false,
  },
  {
    slug: 'via',
    name: 'via',
    type: 'creation',
    role: 'referrer',
    inverseSlug: 'source_for',
    canonical: true,
  },
  {
    slug: 'source_for',
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
    inverseSlug: 'related_to',
    canonical: true,
  },

  /* ───────────  Identity  ─────────── */
  {
    slug: 'same_as',
    name: 'same as',
    type: 'identity',
    inverseSlug: 'same_as',
    canonical: true,
  },
] as const satisfies readonly Predicate[];

export type PredicateSlug = (typeof PREDICATES_LIST)[number]['slug'];

/** Map from slug → Predicate for O(1) lookups */
export const PREDICATES: Record<PredicateSlug, Predicate> = Object.fromEntries(
  PREDICATES_LIST.map((p) => [p.slug, p]),
) as Record<PredicateSlug, Predicate>;

/** All predicates as an array */
export const ALL_PREDICATES: readonly Predicate[] = PREDICATES_LIST;

/** Only canonical predicates (the ones stored in links) */
export const CANONICAL_PREDICATES: readonly Predicate[] = PREDICATES_LIST.filter(
  (p) => p.canonical,
);

/** Get predicate by slug, or throw */
export function getPredicate(slug: string): Predicate {
  const p = PREDICATES[slug as PredicateSlug];
  if (!p) throw new Error(`Unknown predicate slug: ${slug}`);
  return p;
}

/** Get the inverse predicate for a given slug */
export function getInversePredicate(slug: string): Predicate {
  const p = getPredicate(slug);
  return getPredicate(p.inverseSlug);
}

/** All valid predicate slugs (for schema validation) */
export const predicateSlugEnum: [string, ...string[]] = PREDICATES_LIST.map(
  (p) => p.slug,
) as unknown as [string, ...string[]];

/** Only canonical slugs (for schema validation) */
export const canonicalPredicateSlugEnum: [string, ...string[]] = CANONICAL_PREDICATES.map(
  (p) => p.slug,
) as unknown as [string, ...string[]];
