import { links, records, type RecordInsert } from './schema/records';
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

const insertedRecords = await db
  .insert(records)
  .values(recordSeed)
  .returning({ id: records.id, slug: records.slug });

const recordIdBySlug = new Map(insertedRecords.map((r) => [r.slug, r.id]));

const enchiridionId = recordIdBySlug.get('enchiridion');
const chaseId = recordIdBySlug.get('chase-mccoy');

if (enchiridionId === undefined || chaseId === undefined) {
  throw new Error('Seed root records missing: expected both "enchiridion" and "chase-mccoy".');
}

await db.insert(links).values({
  sourceId: enchiridionId,
  targetId: chaseId,
  predicate: 'created_by',
  notes: 'Created during initial seeding',
});
