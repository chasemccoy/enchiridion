import 'dotenv/config';
import { backfillEmbeddings, isEmbeddingEnabled, EMBEDDING_MODEL } from '@integrations/embeddings';

/* eslint-disable no-console */

async function main() {
  if (!isEmbeddingEnabled()) {
    console.error('❌ OPENAI_API_KEY is not set. Add it to your .env to generate embeddings.');
    process.exit(1);
  }

  // Pass --force to re-embed every record even if its text is unchanged.
  const force = process.argv.includes('--force');

  console.log(`🧠 Generating embeddings with ${EMBEDDING_MODEL}${force ? ' (force)' : ''}...`);

  const { embedded, skipped, removed } = await backfillEmbeddings({
    force,
    onProgress: (done, total) => {
      console.log(`   embedded ${done}/${total}`);
    },
  });

  console.log(
    `✅ Done. embedded: ${embedded}, skipped (unchanged): ${skipped}, pruned (orphans): ${removed}`,
  );
  process.exit(0);
}

void main().catch((error) => {
  console.error('❌ Embedding backfill failed:', error);
  process.exit(1);
});
