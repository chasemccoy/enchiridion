import { hybridSearchListRecords } from '@db/queries/hybrid-search';
import { listRecords } from '@db/queries/records';
import { semanticSearchListRecords } from '@db/queries/semantic-search';
import { isEmbeddingEnabled } from '@integrations/embeddings';
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

// Semantic (vector) search over record embeddings. Returns rows in the same
// shape as `listRecords` so the UI can reuse RecordCard, with a cosine
// similarity `score` (in [-1, 1]) attached to each row.
searchRoutes.get('/search/semantic', async (req, res, next) => {
  try {
    const query = typeof req.query.q === 'string' ? req.query.q : '';
    const limit = req.query.limit ? parseInt(String(req.query.limit), 10) : 50;

    if (!query.trim()) {
      res.status(400).json({ error: 'Missing query parameter "q"' });
      return;
    }
    if (!isEmbeddingEnabled()) {
      res.status(503).json({ error: 'Embeddings are not configured (set OPENAI_API_KEY)' });
      return;
    }

    const results = await semanticSearchListRecords({
      query,
      limit: Number.isFinite(limit) ? limit : 50,
    });
    res.json(results);
  } catch (error) {
    next(error);
  }
});

// Hybrid search: reciprocal-rank-fusion of full-text + semantic. One ranked
// list with a fused `score` per row (same shape as the other search endpoints).
// Degrades to text-only when embeddings aren't configured, so it never 503s.
searchRoutes.get('/search/hybrid', async (req, res, next) => {
  try {
    const query = typeof req.query.q === 'string' ? req.query.q : '';
    const limit = req.query.limit ? parseInt(String(req.query.limit), 10) : 50;

    if (!query.trim()) {
      res.status(400).json({ error: 'Missing query parameter "q"' });
      return;
    }

    const results = await hybridSearchListRecords({
      query,
      limit: Number.isFinite(limit) ? limit : 50,
    });
    res.json(results);
  } catch (error) {
    next(error);
  }
});
