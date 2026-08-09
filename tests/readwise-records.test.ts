/**
 * Readwise record-creation invariants: a document whose title-derived slug
 * already belongs to an existing record (the same article saved under a
 * different URL — e.g. an author domain migration) must be mapped to that
 * record instead of inserted as a duplicate, and highlight children must end
 * up linked contained_by the parent's record — including children mapped in
 * an earlier run while the parent's insert was still failing.
 */
import { describe, expect, it } from 'vitest';
import { and, eq } from 'drizzle-orm';
import { db } from '@db/index';
import { integrationRuns, links, readwiseDocuments } from '@db/schema';
import { createRecordsFromReadwiseDocuments } from '@integrations/readwise/records';
import { createRecord } from './helpers';

async function createIntegrationRun(): Promise<number> {
  const [run] = await db
    .insert(integrationRuns)
    .values({ integrationType: 'readwise', runStartTime: new Date().toISOString() })
    .returning({ id: integrationRuns.id });
  if (!run) throw new Error('integration run fixture insert failed');
  return run.id;
}

type DocOverrides = Partial<typeof readwiseDocuments.$inferInsert> & { id: string };

async function insertDoc(integrationRunId: number, overrides: DocOverrides) {
  const now = '2026-08-09T00:00:00Z';
  await db.insert(readwiseDocuments).values({
    url: `https://read.example.com/${overrides.id}`,
    savedAt: now,
    lastMovedAt: now,
    integrationRunId,
    ...overrides,
  });
}

async function findContainedByLink(sourceId: number, targetId: number) {
  const rows = await db
    .select()
    .from(links)
    .where(
      and(
        eq(links.sourceId, sourceId),
        eq(links.targetId, targetId),
        eq(links.predicate, 'contained_by'),
      ),
    );
  return rows;
}

describe('createRecordsFromReadwiseDocuments', () => {
  it('maps a slug-colliding document to the existing record and links its children', async () => {
    const existing = await createRecord({
      slug: 'the-internet-wants-to-be-fragmented',
      title: 'The internet wants to be fragmented',
      url: 'https://www.noahpinion.blog/p/the-internet-wants-to-be-fragmented',
      isCurated: true,
    });

    const runId = await createIntegrationRun();
    await insertDoc(runId, {
      id: 'parent-doc',
      title: 'The internet wants to be fragmented',
      sourceUrl: 'https://noahpinion.substack.com/p/the-internet-wants-to-be-fragmented',
      category: 'article',
      location: 'archive',
    });
    await insertDoc(runId, {
      id: 'child-doc',
      parentId: 'parent-doc',
      category: 'highlight',
      content: 'On the old internet, you could show a different side of yourself.',
    });

    await createRecordsFromReadwiseDocuments();

    // The colliding parent is mapped to the existing record, not duplicated.
    const parentDoc = await db.query.readwiseDocuments.findFirst({ where: { id: 'parent-doc' } });
    expect(parentDoc?.recordId).toBe(existing.id);

    const collided = await db.query.records.findMany({
      where: { slug: 'the-internet-wants-to-be-fragmented' },
    });
    expect(collided).toHaveLength(1);

    // The highlight child got its own record, linked to the existing parent record.
    const childDoc = await db.query.readwiseDocuments.findFirst({ where: { id: 'child-doc' } });
    expect(childDoc?.recordId).toBeTruthy();
    expect(childDoc?.recordId).not.toBe(existing.id);

    const link = await findContainedByLink(childDoc!.recordId!, existing.id);
    expect(link).toHaveLength(1);
  });

  it('heals children mapped in an earlier run once the parent finally maps', async () => {
    // Aftermath of the old bug: the child became a record in a previous sync,
    // but the parent's insert kept failing on the slug collision, so no
    // contained_by link was ever created.
    const orphanRecord = await createRecord({ slug: 'orphan-highlight' });
    const existingParentRecord = await createRecord({
      slug: 'previously-colliding-article',
      title: 'Previously colliding article',
    });

    const runId = await createIntegrationRun();
    await insertDoc(runId, {
      id: 'stuck-parent',
      title: 'Previously colliding article',
      category: 'article',
      location: 'archive',
    });
    await insertDoc(runId, {
      id: 'orphan-child',
      parentId: 'stuck-parent',
      category: 'highlight',
      content: 'A highlight stranded by the collision.',
      recordId: orphanRecord.id,
    });

    await createRecordsFromReadwiseDocuments();

    const parentDoc = await db.query.readwiseDocuments.findFirst({ where: { id: 'stuck-parent' } });
    expect(parentDoc?.recordId).toBe(existingParentRecord.id);

    const healedLink = await findContainedByLink(orphanRecord.id, existingParentRecord.id);
    expect(healedLink).toHaveLength(1);
  });
});
