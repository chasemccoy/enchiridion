/**
 * Graph traversal queries over a fixture graph: family tree shape, the
 * related_to BFS (including cycle safety), and the per-record link bundle.
 */
import { describe, expect, it } from 'vitest';
import { db } from '@db/index';
import { links } from '@db/schema';
import { getFamilyTree } from '@db/queries/tree';
import { findAllRelatedRecords } from '@db/queries/related-records';
import { linksForRecord } from '@db/queries/records';
import { createRecord } from './helpers';

describe('getFamilyTree', () => {
  it('reports parent, grandparent, siblings, and children', async () => {
    const grandparent = await createRecord({ title: 'Grandparent' });
    const parent = await createRecord({ title: 'Parent' });
    const child = await createRecord({ title: 'Child' });
    const sibling = await createRecord({ title: 'Sibling' });

    // `contained_by` points from the contained record to its container.
    await db.insert(links).values([
      { sourceId: parent.id, targetId: grandparent.id, predicate: 'contained_by' },
      { sourceId: child.id, targetId: parent.id, predicate: 'contained_by' },
      { sourceId: sibling.id, targetId: parent.id, predicate: 'contained_by' },
    ]);

    const tree = await getFamilyTree(child.id);
    expect(tree?.id).toBe(child.id);

    const parents = tree?.outgoingLinks.map((l) => l.target.id) ?? [];
    expect(parents).toEqual([parent.id]);

    const parentNode = tree?.outgoingLinks[0]?.target;
    const grandparents = parentNode?.outgoingLinks.map((l) => l.target.id) ?? [];
    expect(grandparents).toEqual([grandparent.id]);

    const siblings = parentNode?.incomingLinks.map((l) => l.source.id) ?? [];
    expect(siblings).toContain(sibling.id);

    // From the parent's perspective the children arrive as incoming links.
    const parentTree = await getFamilyTree(parent.id);
    const children = parentTree?.incomingLinks.map((l) => l.source.id) ?? [];
    expect(children).toContain(child.id);
    expect(children).toContain(sibling.id);
  });

  it('ignores non-family predicates', async () => {
    const a = await createRecord();
    const b = await createRecord();
    await db.insert(links).values({ sourceId: a.id, targetId: b.id, predicate: 'related_to' });
    const tree = await getFamilyTree(a.id);
    expect(tree?.outgoingLinks).toEqual([]);
    expect(tree?.incomingLinks).toEqual([]);
  });
});

describe('findAllRelatedRecords', () => {
  it('walks related_to transitively in both directions with shortest paths', async () => {
    const a = await createRecord({ title: 'A' });
    const b = await createRecord({ title: 'B' });
    const c = await createRecord({ title: 'C' });
    const isolated = await createRecord({ title: 'Isolated' });

    await db.insert(links).values([
      { sourceId: a.id, targetId: b.id, predicate: 'related_to' },
      // Reverse orientation on purpose: the walk must treat links as undirected.
      { sourceId: c.id, targetId: b.id, predicate: 'related_to' },
    ]);

    const related = await findAllRelatedRecords(a.slug);
    const byId = new Map(related.map((r) => [r.record.id, r]));

    expect(byId.get(b.id)?.path).toHaveLength(1);
    expect(byId.get(c.id)?.path).toHaveLength(2);
    expect(byId.has(isolated.id)).toBe(false);
    expect(byId.has(a.id)).toBe(false);
  });

  it('terminates on cycles', async () => {
    const a = await createRecord();
    const b = await createRecord();
    const c = await createRecord();
    await db.insert(links).values([
      { sourceId: a.id, targetId: b.id, predicate: 'related_to' },
      { sourceId: b.id, targetId: c.id, predicate: 'related_to' },
      { sourceId: c.id, targetId: a.id, predicate: 'related_to' },
    ]);

    const related = await findAllRelatedRecords(a.slug);
    expect(related.map((r) => r.record.id).sort()).toEqual([b.id, c.id].sort());
    // Both neighbors are one hop away around the triangle.
    for (const entry of related) expect(entry.path).toHaveLength(1);
  });

  it('throws for an unknown slug', async () => {
    await expect(findAllRelatedRecords('no-such-slug')).rejects.toThrow(/not found/);
  });
});

describe('linksForRecord', () => {
  it('bundles outgoing and incoming links with their endpoints', async () => {
    const center = await createRecord({ title: 'Center' });
    const out = await createRecord({ title: 'Out' });
    const inn = await createRecord({ title: 'In' });
    await db.insert(links).values([
      { sourceId: center.id, targetId: out.id, predicate: 'related_to' },
      { sourceId: inn.id, targetId: center.id, predicate: 'about' },
    ]);

    const bundle = await linksForRecord(center.id);
    expect(bundle?.outgoingLinks.map((l) => l.target.slug)).toEqual([out.slug]);
    expect(bundle?.incomingLinks.map((l) => l.source.slug)).toEqual([inn.slug]);
  });
});
