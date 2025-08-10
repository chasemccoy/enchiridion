import { defineRelations } from 'drizzle-orm';
import * as schema from './index';

export const relations = defineRelations(schema, (r) => ({
  media: {
    record: r.one.records({
      from: r.media.recordId,
      to: r.records.id,
    }),
  },
  records: {
    outgoingLinks: r.many.links({
      from: r.records.id,
      to: r.links.sourceId,
    }),
    incomingLinks: r.many.links({
      from: r.records.id,
      to: r.links.targetId,
    }),
    media: r.many.media(),
    readwiseAuthors: r.many.readwiseAuthors(),
    readwiseDocuments: r.many.readwiseDocuments(),
    readwiseTags: r.many.readwiseTags(),
  },
  links: {
    source: r.one.records({
      from: r.links.sourceId,
      to: r.records.id,
      optional: false,
    }),
    target: r.one.records({
      from: r.links.targetId,
      to: r.records.id,
      optional: false,
    }),
    predicate: r.one.predicates({
      from: r.links.predicateId,
      to: r.predicates.id,
      optional: false,
    }),
  },
  predicates: {
    links: r.many.links({
      from: r.predicates.id,
      to: r.links.predicateId,
    }),
    inverse: r.one.predicates({
      from: r.predicates.inverseSlug,
      to: r.predicates.slug,
    }),
  },
  readwiseAuthors: {
    documents: r.many.readwiseDocuments({
      from: r.readwiseAuthors.id,
      to: r.readwiseDocuments.authorId,
    }),
    record: r.one.records({
      from: r.readwiseAuthors.recordId,
      to: r.records.id,
    }),
  },
  readwiseDocuments: {
    integrationRun: r.one.integrationRuns({
      from: r.readwiseDocuments.integrationRunId,
      to: r.integrationRuns.id,
    }),
    record: r.one.records({
      from: r.readwiseDocuments.recordId,
      to: r.records.id,
    }),
    children: r.many.readwiseDocuments({
      from: r.readwiseDocuments.id,
      to: r.readwiseDocuments.parentId,
    }),
    parent: r.one.readwiseDocuments({
      from: r.readwiseDocuments.parentId,
      to: r.readwiseDocuments.id,
    }),
    author: r.one.readwiseAuthors({
      from: r.readwiseDocuments.authorId,
      to: r.readwiseAuthors.id,
    }),
    documentTags: r.many.readwiseDocumentTags({
      from: r.readwiseDocuments.id,
      to: r.readwiseDocumentTags.documentId,
    }),
  },
  readwiseDocumentTags: {
    document: r.one.readwiseDocuments({
      from: r.readwiseDocumentTags.documentId,
      to: r.readwiseDocuments.id,
      optional: false,
    }),
    tag: r.one.readwiseTags({
      from: r.readwiseDocumentTags.tagId,
      to: r.readwiseTags.id,
      optional: false,
    }),
  },
  readwiseTags: {
    documents: r.many.readwiseDocuments({
      from: r.readwiseTags.id.through(r.readwiseDocumentTags.tagId),
      to: r.readwiseDocuments.id.through(r.readwiseDocumentTags.documentId),
    }),
    record: r.one.records({
      from: r.readwiseTags.recordId,
      to: r.records.id,
    }),
  },
}));
