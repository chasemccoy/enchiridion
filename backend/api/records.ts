import { Router } from 'express';
import { RecordInsertSchema } from '@db/schema';
import { IdParamSchema, IdSchema, ListRecordsInputSchema } from '@shared/types/api';
import {
  getRecord,
  listRecords,
  upsertRecord,
  deleteRecord,
  linksForRecord,
  getRecordBySlug,
  linksToRecordWithPredicateSlug,
} from '@db/queries/records';
import { findSimilarRecords } from '@db/queries/similar-records';
import { findAllRelatedRecords } from '@db/queries/related-records';
import { getFamilyTree } from '@db/queries/tree';
import {
  claimArchive,
  listArchiveVersions,
  pastVersionStamp,
  runArchive,
} from '@integrations/archive';
import { db } from '@db/index';
import { PredicateSlugSchema } from '@shared/types';
import { z } from 'zod/v4';

export const recordRoutes = Router();

// ============================================================================
// GET
// ============================================================================

recordRoutes.get('/record/:id', async (req, res, next) => {
  try {
    const { id } = IdParamSchema.parse(req.params);

    const record = await getRecord(id);

    if (!record) {
      res.status(404).send(`Record with id ${id} not found`);
      return;
    }

    res.json(record);
  } catch (error) {
    next(error);
  }
});

recordRoutes.get('/record/slug/:slug', async (req, res, next) => {
  try {
    const { slug } = req.params;
    const record = await getRecordBySlug(slug);

    if (!record) {
      res.status(404).send(`Record with slug ${slug} not found`);
      return;
    }

    res.json(record);
  } catch (error) {
    next(error);
  }
});

recordRoutes.get('/record/:id/links', async (req, res, next) => {
  try {
    const { id } = IdParamSchema.parse(req.params);
    const links = await linksForRecord(id);
    res.json(links);
  } catch (error) {
    next(error);
  }
});

recordRoutes.get('/record/:id/tree', async (req, res, next) => {
  try {
    const { id } = IdParamSchema.parse(req.params);
    const tree = await getFamilyTree(id);
    res.json(tree);
  } catch (error) {
    next(error);
  }
});

// Example: `/record/556/links/related_to`
recordRoutes.get('/record/:id/links/:predicateSlug', async (req, res, next) => {
  const paramSchema = z.object({ id: IdSchema, predicateSlug: PredicateSlugSchema });

  try {
    const { id, predicateSlug } = paramSchema.parse(req.params);
    const links = await linksToRecordWithPredicateSlug(id, predicateSlug);
    res.json(links);
  } catch (error) {
    next(error);
  }
});

recordRoutes.get('/record/:id/similar', async (req, res, next) => {
  try {
    const { id } = IdParamSchema.parse(req.params);

    const limit = req.query.limit ? parseInt(req.query.limit as string) : undefined;
    const minScore = req.query.minScore ? parseFloat(req.query.minScore as string) : 0.1;
    const includeContent = req.query.includeContent === 'true';

    const similarRecords = await findSimilarRecords({
      recordId: id,
      limit,
      minScore,
      includeContent,
    });

    res.json(similarRecords);
  } catch (error) {
    next(error);
  }
});

recordRoutes.get('/record/:slug/related', async (req, res, next) => {
  try {
    const { slug } = req.params;
    const relatedRecords = await findAllRelatedRecords(slug);
    res.json(relatedRecords);
  } catch (error) {
    next(error);
  }
});

// ============================================================================
// POST
// ============================================================================

recordRoutes.post('/records', async (req, res, next) => {
  try {
    const input = ListRecordsInputSchema.parse(req.body || {});
    const records = await listRecords(input);
    res.json(records);
  } catch (error) {
    next(error);
  }
});

// The captures in a record's archive folder, newest first: the current copy and its past versions (amber keeps them
// as folders, so this reads them from disk). Empty until the record has been archived.
recordRoutes.get('/record/:id/archive/versions', async (req, res, next) => {
  try {
    const { id } = IdParamSchema.parse(req.params);
    const archive = await db.query.archives.findFirst({ where: { recordId: id } });
    res.json(listArchiveVersions(archive?.path ?? null));
  } catch (error) {
    next(error);
  }
});

// Start archiving (or re-archiving) a record's URL into a local offline copy.
// A body of `{ at }` (a date, a Wayback timestamp, "latest", or a web.archive.org
// link to this page) archives that past version from the Wayback Machine instead,
// filed into the same folder's timeline.
// Responds 202 with the claimed 'pending' archive row immediately — the capture
// can take minutes (longer than browsers keep a request open), so it continues
// in the background and writes 'ok' or 'failed' onto the same row, which
// clients observe by refetching the record. 409 when a run is already in
// flight (here or via the CLI).
recordRoutes.post('/record/:id/archive', async (req, res, next) => {
  try {
    const { id } = IdParamSchema.parse(req.params);

    const record = await getRecord(id);
    if (!record) {
      res.status(404).send(`Record with id ${id} not found`);
      return;
    }
    if (!record.url) {
      res.status(400).send(`Record with id ${id} has no URL to archive`);
      return;
    }

    let at: string | undefined;
    const requested = (req.body as { at?: unknown } | undefined)?.at;
    if (typeof requested === 'string' && requested.trim()) {
      try {
        at = pastVersionStamp(requested, record.url);
      } catch (error) {
        res.status(400).json({ message: (error as Error).message });
        return;
      }
    }

    const pending = await claimArchive(record);
    if (!pending) {
      res.status(409).json({ message: `Record ${id} is already being archived` });
      return;
    }
    res.status(202).json(pending);

    // Detached on purpose: runArchive persists its own failures onto the row,
    // so this catch only covers that persistence itself blowing up.
    runArchive(record, { at }).catch((error) => {
      // eslint-disable-next-line no-console
      console.error(`Archive run for record ${id} failed to persist its outcome:`, error);
    });
  } catch (error) {
    next(error);
  }
});

// ============================================================================
// PUT
// ============================================================================

recordRoutes.put('/record', async (req, res, next) => {
  try {
    const record = RecordInsertSchema.parse(req.body);
    // Saves arrive every second or so while someone types: embed once the record settles.
    const updatedRecord = await upsertRecord(record, { embed: 'debounced' });
    res.json(updatedRecord);
  } catch (error) {
    next(error);
  }
});

// ============================================================================
// DELETE
// ============================================================================

recordRoutes.delete('/record/:id', async (req, res, next) => {
  try {
    const { id } = IdParamSchema.parse(req.params);
    const deletedRecords = await deleteRecord([id]);
    res.json(deletedRecords);
  } catch (error) {
    next(error);
  }
});
