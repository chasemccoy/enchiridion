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
import { findRelatedRecords } from '@db/queries/related';
import { getFamilyTree } from '@db/queries/tree';
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
  const paramSchema = z.object({ id: IdSchema, predicateSlug: z.string() });

  try {
    const { id, predicateSlug } = paramSchema.parse(req.params);
    const links = await linksToRecordWithPredicateSlug(id, predicateSlug);
    res.json(links);
  } catch (error) {
    next(error);
  }
});

recordRoutes.get('/record/:id/related', async (req, res, next) => {
  try {
    const { id } = IdParamSchema.parse(req.params);

    const limit = req.query.limit ? parseInt(req.query.limit as string) : 20;
    const minScore = req.query.minScore ? parseFloat(req.query.minScore as string) : 0.1;
    const includeContent = req.query.includeContent === 'true';

    const relatedRecords = await findRelatedRecords({
      recordId: id,
      limit,
      minScore,
      includeContent,
    });

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

// ============================================================================
// PUT
// ============================================================================

recordRoutes.put('/record', async (req, res, next) => {
  try {
    const record = RecordInsertSchema.parse(req.body);
    const updatedRecord = await upsertRecord(record);
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
