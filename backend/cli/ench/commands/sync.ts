/**
 * Sync commands for the `ench` CLI.
 *
 * Each sync wraps the same entry function the `pnpm sync:*` scripts use, so
 * CLI runs and the existing scripts produce identical results.
 */

import { z } from 'zod/v4';
import { syncReadwiseData } from '@integrations/readwise/sync';
import { backfillEmbeddings, isEmbeddingEnabled, EMBEDDING_MODEL } from '@integrations/embeddings';
import { BaseOptionsSchema, parseOptions } from '../lib/args';
import { createError } from '../lib/errors';
import { success } from '../lib/output';
import type { CommandHandler } from '../lib/types';

const IntegrationSchema = z.enum(['readwise', 'twitter', 'embeddings']);
type Integration = z.infer<typeof IntegrationSchema>;

const SyncOptionsSchema = z.looseObject({
  ...BaseOptionsSchema.shape,
  force: z.boolean().optional(),
  'dry-run': z.boolean().optional(),
});

async function runIntegration(name: Integration, opts: { force?: boolean }) {
  const start = performance.now();
  switch (name) {
    case 'readwise': {
      await syncReadwiseData();
      return {
        integration: 'readwise' as const,
        success: true,
        durationMs: Math.round(performance.now() - start),
      };
    }
    case 'twitter': {
      // Twitter records are added one-at-a-time through the UI's "add tweet"
      // flow (see backend/integrations/twitter/fetchTweet.ts). There's no bulk
      // sync to wrap, so this is intentionally a no-op rather than an error so
      // `ench sync` (all integrations) doesn't fall over.
      return {
        integration: 'twitter' as const,
        success: true,
        skipped: true,
        reason: 'Twitter has no bulk sync; tweets are added on demand from the UI.',
        durationMs: Math.round(performance.now() - start),
      };
    }
    case 'embeddings': {
      if (!isEmbeddingEnabled()) {
        throw createError(
          'EMBEDDING_ERROR',
          'OPENAI_API_KEY is not set — cannot generate embeddings.',
        );
      }
      const result = await backfillEmbeddings({ force: opts.force });
      return {
        integration: 'embeddings' as const,
        success: true,
        model: EMBEDDING_MODEL,
        ...result,
        durationMs: Math.round(performance.now() - start),
      };
    }
  }
}

/**
 * Dispatch to a single integration sync, or run them all.
 * Usage:
 *   ench sync                  # readwise + embeddings (twitter is a no-op)
 *   ench sync readwise
 *   ench sync twitter
 *   ench sync embeddings [--force]
 */
export const run: CommandHandler = async (args, options) => {
  const parsed = parseOptions(SyncOptionsSchema, options);
  const dryRun = parsed['dry-run'] === true || options.n === true;
  const rawIntegration = args[0]?.toLowerCase();

  if (rawIntegration) {
    const integrationResult = IntegrationSchema.safeParse(rawIntegration);
    if (!integrationResult.success) {
      throw createError(
        'VALIDATION_ERROR',
        `Unknown integration: ${rawIntegration}. Available: ${IntegrationSchema.options.join(', ')}`,
      );
    }
    if (dryRun) {
      return success({ wouldRun: integrationResult.data });
    }
    const result = await runIntegration(integrationResult.data, { force: parsed.force });
    return success(result);
  }

  if (dryRun) {
    return success({ wouldRun: IntegrationSchema.options });
  }

  // Run all integrations in order. Failures are recorded but don't stop the run.
  const results = [];
  for (const integration of IntegrationSchema.options) {
    try {
      results.push(await runIntegration(integration, { force: parsed.force }));
    } catch (e) {
      results.push({
        integration,
        success: false,
        error: e instanceof Error ? e.message : String(e),
      });
    }
  }
  const succeeded = results.filter((r) => r.success).length;
  return success(
    { results, summary: { total: results.length, succeeded, failed: results.length - succeeded } },
    { count: results.length },
  );
};

// Allow `ench sync <integration>` to dispatch through the same handler.
export { run as readwise };
export { run as twitter };
export { run as embeddings };
