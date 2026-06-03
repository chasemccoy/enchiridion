import { z } from 'zod/v4';

export const predicateTypes = [
  'creation', // authorship, ownership …
  'containment', // has_part, sequence …
  'description', // about, tag …
  'association', // related_to, similar_to …
  'reference', // cites, responds_to …
  'identity', // instance_of, same_as …
] as const;

export type PredicateType = (typeof predicateTypes)[number];

/**
 * Predicate definition for relationship types between records.
 *
 * Predicates define the semantic meaning of links (edges) in the knowledge graph.
 * Each predicate has a canonical form and an inverse for traversing the edge
 * in the opposite direction.
 */
export interface Predicate {
  /** Unique identifier slug (e.g., 'created_by', 'contained_by') */
  slug: string;
  /** Human-readable name (e.g., 'created by', 'contained by') */
  name: string;
  /** Category of relationship */
  type: PredicateType;
  /** Optional role (e.g., 'creator', 'editor') for creation predicates */
  role?: string;
  /** Slug of the inverse predicate */
  inverseSlug: string;
  /**
   * Whether this is the canonical direction for storage.
   * Only canonical predicates are stored in the `links` table.
   * Non-canonical predicates are flipped to their canonical inverse on write.
   */
  canonical: boolean;
}

/**
 * Canonical predicate vocabulary
 *
 * - Only rows with `canonical: true` are stored in `links`.
 * - `inverseSlug` supplies a readable label when traversing the edge
 *   in the opposite direction.
 * - Active-present verb style: created_by, contained_by, format_of …
 */
export const PREDICATES = {
  /* ────────────  Creation  ──────────── */
  created_by: {
    slug: 'created_by',
    name: 'created by',
    type: 'creation',
    role: 'creator',
    inverseSlug: 'creator_of',
    canonical: true,
  },
  creator_of: {
    slug: 'creator_of',
    name: 'creator of',
    type: 'creation',
    role: 'creator',
    inverseSlug: 'created_by',
    canonical: false,
  },
  via: {
    slug: 'via',
    name: 'via',
    type: 'creation',
    role: 'referrer',
    inverseSlug: 'source_for',
    canonical: true,
  },
  source_for: {
    slug: 'source_for',
    name: 'source for',
    type: 'creation',
    role: 'referrer',
    inverseSlug: 'via',
    canonical: false,
  },
  edited_by: {
    slug: 'edited_by',
    name: 'edited by',
    type: 'creation',
    role: 'editor',
    inverseSlug: 'editor_of',
    canonical: true,
  },
  editor_of: {
    slug: 'editor_of',
    name: 'editor of',
    type: 'creation',
    role: 'editor',
    inverseSlug: 'edited_by',
    canonical: false,
  },

  /* ─────── Containment (child → parent) ─────── */
  contained_by: {
    slug: 'contained_by',
    name: 'contained by',
    type: 'containment',
    inverseSlug: 'contains',
    canonical: true,
  },
  contains: {
    slug: 'contains',
    name: 'contains',
    type: 'containment',
    inverseSlug: 'contained_by',
    canonical: false,
  },
  quotes: {
    slug: 'quotes',
    name: 'quotes',
    type: 'containment',
    inverseSlug: 'quoted_in',
    canonical: true,
  },
  quoted_in: {
    slug: 'quoted_in',
    name: 'quoted in',
    type: 'containment',
    inverseSlug: 'quotes',
    canonical: false,
  },

  /* ───────────  Description  ─────────── */
  has_format: {
    slug: 'has_format',
    name: 'has format',
    type: 'description',
    inverseSlug: 'format_of',
    canonical: true,
  },
  format_of: {
    slug: 'format_of',
    name: 'format of',
    type: 'description',
    inverseSlug: 'has_format',
    canonical: false,
  },
  tagged_with: {
    slug: 'tagged_with',
    name: 'tagged with',
    type: 'description',
    inverseSlug: 'tag_of',
    canonical: true,
  },
  tag_of: {
    slug: 'tag_of',
    name: 'tag of',
    type: 'description',
    inverseSlug: 'tagged_with',
    canonical: false,
  },

  /* ───────────  Reference  ─────────── */
  references: {
    slug: 'references',
    name: 'references',
    type: 'reference',
    inverseSlug: 'referenced_by',
    canonical: true,
  },
  referenced_by: {
    slug: 'referenced_by',
    name: 'referenced by',
    type: 'reference',
    inverseSlug: 'references',
    canonical: false,
  },
  about: {
    slug: 'about',
    name: 'about',
    type: 'reference',
    inverseSlug: 'subject_of',
    canonical: true,
  },
  subject_of: {
    slug: 'subject_of',
    name: 'subject of',
    type: 'reference',
    inverseSlug: 'about',
    canonical: false,
  },

  /* ───────────  Association  ─────────── */
  related_to: {
    slug: 'related_to',
    name: 'related to',
    type: 'association',
    inverseSlug: 'related_to', // self-inverse
    canonical: true,
  },

  /* ───────────  Identity  ─────────── */
  same_as: {
    slug: 'same_as',
    name: 'same as',
    type: 'identity',
    inverseSlug: 'same_as', // self-inverse
    canonical: true,
  },
} as const satisfies Record<string, Predicate>;

/** Union type of all valid predicate slugs */
export type PredicateSlug = keyof typeof PREDICATES;

/** Array of all predicate slugs for validation */
export const predicateSlugs = Object.keys(PREDICATES) as [PredicateSlug, ...PredicateSlug[]];

/** Zod schema validating a predicate slug */
export const PredicateSlugSchema = z.enum(predicateSlugs);

/** Array of all predicate definitions */
export const allPredicates: Predicate[] = Object.values(PREDICATES);

/** Array of canonical predicates (those that get stored in the links table) */
export const canonicalPredicates: Predicate[] = allPredicates.filter((p) => p.canonical);

/** Array of canonical predicate slugs */
export const canonicalPredicateSlugs = canonicalPredicates.map((p) => p.slug) as PredicateSlug[];

/**
 * Get a predicate by its slug. Throws on unknown slugs so write paths fail
 * loudly rather than constructing invalid data; read paths that need to
 * tolerate unknown slugs should use {@link getPredicateSafe} instead.
 */
export function getPredicate(slug: PredicateSlug): Predicate {
  const predicate = PREDICATES[slug];
  if (!predicate) throw new Error(`Unknown predicate slug: ${slug}`);
  return predicate;
}

/**
 * Get a predicate by its slug, or undefined if not in the canonical vocabulary.
 * Use this in render paths so a stale/unknown slug in the DB degrades gracefully
 * instead of crashing the component.
 */
export function getPredicateSafe(slug: string): Predicate | undefined {
  return PREDICATES[slug as PredicateSlug];
}

/**
 * Get the inverse predicate for a given slug. Throws on unknown slugs.
 * For self-inverse predicates (related_to, same_as), returns the same predicate.
 */
export function getInverse(slug: PredicateSlug): Predicate {
  return getPredicate(getPredicate(slug).inverseSlug as PredicateSlug);
}

/** Check if a string is a valid predicate slug. */
export function isPredicateSlug(value: string): value is PredicateSlug {
  return value in PREDICATES;
}

/** True iff `slug` names a predicate of the given type. Safe for unknown slugs. */
export function isPredicateType(slug: string | undefined, type: PredicateType): boolean {
  if (!slug) return false;
  const predicate = PREDICATES[slug as PredicateSlug];
  return predicate?.type === type;
}

/** Predicate slugs for a given type (both canonical and non-canonical) */
export function predicateSlugsByType(type: PredicateType): PredicateSlug[] {
  return allPredicates.filter((p) => p.type === type).map((p) => p.slug) as PredicateSlug[];
}

/** Predicate slugs for all containment relationships (structural and citation) */
export const containmentPredicateSlugs = predicateSlugsByType('containment');

/** Predicate slugs for description relationships (tags, format, etc.) */
export const descriptionPredicateSlugs = predicateSlugsByType('description');

/** Predicate slugs for creation relationships (creator, editor, etc.) */
export const creationPredicateSlugs = predicateSlugsByType('creation');
