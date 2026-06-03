import { db } from '@db/index';
import { links, type LinkInsert, type LinkSelect } from '@db/schema';
import type { APIResponse } from '@shared/types/api';
import { getPredicate } from '@shared/types';
import { eq, sql } from 'drizzle-orm';

export const deleteLink = async (linkId: LinkSelect['id']) => {
  return db.delete(links).where(eq(links.id, linkId)).returning();
};

export type DeleteLinkAPIResponse = APIResponse<typeof deleteLink>;

export const upsertLink = async (link: LinkInsert) => {
  /* 1 ─ look up predicate definition */
  const predicate = getPredicate(link.predicate);

  /* 2 ─ compute canonical direction */
  let { sourceId, targetId, predicate: predicateSlug } = link;

  if (!predicate.canonical) {
    const inverse = getPredicate(predicate.inverseSlug as typeof predicate.slug);

    if (!inverse.canonical) {
      throw new Error('Non-canonical predicate is not reversible');
    }

    sourceId = link.targetId;
    targetId = link.sourceId;
    predicateSlug = inverse.slug as typeof predicateSlug;
  }

  if (sourceId === targetId) {
    throw new Error('sourceId and targetId cannot be identical');
  }

  /* 3 ─ build write payload with only safe fields */
  const linkData = {
    sourceId,
    targetId,
    predicate: predicateSlug,
    notes: link.notes ?? null,
  } satisfies Partial<LinkInsert>;

  let row: LinkSelect | undefined;

  if (link.id) {
    /* UPDATE --------------------------------------------------- */
    [row] = await db
      .update(links)
      .set({ ...linkData, recordUpdatedAt: sql`(CURRENT_TIMESTAMP)` })
      .where(eq(links.id, link.id))
      .returning();

    if (!row) {
      throw new Error('Link not found for update');
    }
  } else {
    /* INSERT … ON CONFLICT ------------------------------------ */
    [row] = await db
      .insert(links)
      .values(linkData)
      .onConflictDoUpdate({
        target: [links.sourceId, links.targetId, links.predicate],
        set: { ...linkData, recordUpdatedAt: sql`CURRENT_TIMESTAMP` },
      })
      .returning();

    if (!row) {
      throw new Error('Failed to insert or update link');
    }
  }

  if (!row) {
    // This case should theoretically be unreachable due to checks above,
    // but included for exhaustive handling.
    throw new Error('Failed to obtain result from upsert operation');
  }

  return row;
};

export type UpsertLinkAPIResponse = APIResponse<typeof upsertLink>;
