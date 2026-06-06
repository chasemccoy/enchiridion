import type { PredicateSlug } from './predicates';
import type { RecordType } from './index';
import type { DbId } from './api';

/**
 * The character that opens a typeahead menu in the ramble editor.
 *  - `@` references any record type (defaults to `related_to`)
 *  - `#` references concepts only (defaults to `tagged_with`)
 */
export type RambleTrigger = '@' | '#';

/**
 * Discriminated union over the three pill types that can appear in the editor.
 * Each variant captures exactly the data needed to (a) re-render the pill,
 * (b) derive the eventual graph edge, and (c) hydrate a serialized doc.
 */
export type RambleToken =
  | {
      kind: 'mention';
      id: DbId;
      slug: string;
      type: RecordType;
      label: string;
      predicate: PredicateSlug;
    }
  | { kind: 'concept'; id: DbId; slug: string; label: string; predicate: PredicateSlug }
  | { kind: 'link'; url: string; predicate: PredicateSlug };

/** A reference shown in the preview "Links" section. */
export type DraftReference = {
  id: DbId;
  slug: string;
  type: RecordType;
  label: string;
  predicate: PredicateSlug;
};

/** Shape consumed by the preview UI. */
export type DraftRecord = {
  title: string | null;
  content: string;
  recordType: RecordType;
  urls: { url: string; predicate: PredicateSlug }[];
  references: DraftReference[];
};

/**
 * Default predicate per trigger. # is a tagging gesture, @ is a looser
 * reference — the user can still override via the pill menu.
 */
export const RAMBLE_DEFAULT_PREDICATE: Record<RambleTrigger, PredicateSlug> = {
  '#': 'tagged_with',
  '@': 'related_to',
};
