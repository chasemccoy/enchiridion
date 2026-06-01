import { listRecords } from '@db/queries/records';
import { isEmbeddingEnabled, searchRecordsByEmbedding } from '@integrations/embeddings';
import { Router } from 'express';

export const searchRoutes = Router();

// ============================================================================
// GET
// ============================================================================

searchRoutes.get('/search', async (req, res, next) => {
  try {
    const { q } = req.query;
    const results = await listRecords({ filters: { text: q as string } });
    res.json(results);
  } catch (error) {
    next(error);
  }
});

// Semantic (vector) search over record embeddings.
searchRoutes.get('/search/semantic', async (req, res, next) => {
  try {
    const query = typeof req.query.q === 'string' ? req.query.q : '';
    const limit = req.query.limit ? parseInt(String(req.query.limit), 10) : 10;

    if (!query.trim()) {
      res.status(400).json({ error: 'Missing query parameter "q"' });
      return;
    }
    if (!isEmbeddingEnabled()) {
      res.status(503).json({ error: 'Embeddings are not configured (set OPENAI_API_KEY)' });
      return;
    }

    const results = await searchRecordsByEmbedding({
      query,
      limit: Number.isFinite(limit) ? limit : 10,
    });
    res.json(results);
  } catch (error) {
    next(error);
  }
});
