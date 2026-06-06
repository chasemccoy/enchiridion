import type { LinkInsert, RecordInsert } from '@db/schema';
import { slugify } from '@shared/lib/formatting';
import type { DraftRecord } from '@shared/types/ramble';

export type DraftSubmission = {
  record: RecordInsert;
  /**
   * Links missing `sourceId` — the caller fills it in with the newly-created
   * record id after `upsertRecord` resolves. Targets are referenced by id
   * because the editor already captured them at pill-creation time.
   */
  links: Omit<LinkInsert, 'sourceId'>[];
};

/**
 * Build the payload shape `upsertRecord` + `upsertLink` expect from a
 * preview-ready {@link DraftRecord}.
 *
 * Conventions:
 *  - Record title = draft title, or first 80 chars of content as a fallback.
 *  - Record content = draft.content (the prose minus pill labels).
 *  - Record url = the FIRST URL pill (subsequent URL pills become reference
 *    links — we don't multi-URL a single record).
 *  - Record source = 'manual'.
 *  - Type = draft.recordType.
 *  - Slug = slugify(title). If both title and content are empty we throw —
 *    nothing useful to save.
 */
export function draftToSubmission(draft: DraftRecord): DraftSubmission {
  const title = draft.title?.trim() || draft.content.trim().slice(0, 80) || '';
  if (!title) {
    throw new Error('Draft is empty — nothing to save.');
  }

  const [primaryUrl, ...extraUrls] = draft.urls;

  const record: RecordInsert = {
    type: draft.recordType,
    title,
    slug: slugify(title),
    source: 'manual',
    content: draft.content || undefined,
    url: primaryUrl?.url,
  };

  // Extra URL pills (beyond the first) can't become links yet — pointing a
  // link at a bare URL would require auto-creating a stub record for it,
  // which is a separate move. They quietly drop on save for now.
  void extraUrls;

  const links: DraftSubmission['links'] = draft.references.map((ref) => ({
    targetId: ref.id,
    predicate: ref.predicate,
  }));

  return { record, links };
}
