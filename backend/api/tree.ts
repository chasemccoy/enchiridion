import { Router } from 'express';
import { IdParamSchema } from '@shared/types/api';
import { getFamilyTree } from '@db/queries/tree';

export const treeRoutes = Router();

// ============================================================================
// GET
// ============================================================================

treeRoutes.get('/tree/:id', async (req, res, next) => {
  try {
    const { id } = IdParamSchema.parse(req.params);
    const tree = await getFamilyTree(id);
    res.json(tree);
  } catch (error) {
    next(error);
  }
});
