import { runIntegration } from '@integrations/utils/runIntegration';
import { logger } from '@integrations/readwise/utils';
import { syncReadwiseDocuments } from '@integrations/readwise/sync';

try {
  logger.start('=== STARTING READWISE SYNC ===');
  await runIntegration('readwise', syncReadwiseDocuments);
  logger.complete('=== READWISE SYNC COMPLETED ===');
  logger.info('-'.repeat(50));
  process.exit(0);
} catch (error) {
  logger.error('Error in Readwise sync main function', error);
  logger.error('=== READWISE SYNC FAILED ===');
  logger.info('-'.repeat(50));
  process.exit(1);
}
