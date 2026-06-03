import { Router } from 'express';
import { IdParamSchema } from '@shared/types/api';
import { LinkInsertSchema } from '@db/schema';
import { upsertLink, deleteLink } from '@db/queries/links';

export const linkRoutes = Router();

// ============================================================================
// PUT
// ============================================================================

linkRoutes.put('/link', async (req, res, next) => {
  try {
    const link = LinkInsertSchema.parse(req.body);
    const updatedLink = await upsertLink(link);
    res.json(updatedLink);
  } catch (error) {
    next(error);
  }
});

// ============================================================================
// DELETE
// ============================================================================

linkRoutes.delete('/link/:id', async (req, res, next) => {
  try {
    const { id } = IdParamSchema.parse(req.params);
    const deletedLink = await deleteLink(id);
    res.json(deletedLink);
  } catch (error) {
    next(error);
  }
});
