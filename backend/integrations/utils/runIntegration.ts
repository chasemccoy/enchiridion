/* eslint-disable no-console */
import { eq, sql } from 'drizzle-orm';
import { db } from '@db/index';
import {
  integrationRuns,
  IntegrationStatus,
  RunType,
  type IntegrationType,
} from '@db/schema/utils';

/**
 * Function signature for integration implementations
 * @param integrationRunId - The ID of the current integration run
 * @returns Promise resolving to the number of entries created during the run
 */
type IntegrationFunction = (integrationRunId: number) => Promise<number>;

/**
 * Executes an integration function within a tracked run context
 *
 * This function handles:
 * 1. Creating a run record in the database
 * 2. Executing the integration function
 * 3. Updating the run record with results or error information
 *
 * @param integrationType - The type of integration being run (e.g., 'github', 'raindrop')
 * @param fn - The integration function to execute
 * @param runType - The type of run (defaults to 'sync')
 * @throws Rethrows any errors from the integration function after logging them
 */
export async function runIntegration(
  integrationType: IntegrationType,
  fn: IntegrationFunction,
  runType: RunType = RunType.enum.sync,
): Promise<void> {
  console.log(`Starting ${integrationType} integration run for ${runType}…`);

  // Create a new integration run record
  const [run] = await db
    .insert(integrationRuns)
    .values({
      integrationType,
      runType,
      runStartTime: sql`(CURRENT_TIMESTAMP)`,
    })
    .returning();

  if (!run) {
    throw new Error('Failed to create integration run record');
  }

  console.log(`Created integration run with ID ${run.id}`);

  try {
    console.log('Executing integration function...');

    const entriesCreated = await fn(run.id);

    if (entriesCreated === 0) {
      console.log('No entries created');
    } else {
      console.log(`Successfully created ${entriesCreated} entries`);
    }

    console.log('Updating integration run status...');

    await db
      .update(integrationRuns)
      .set({
        status: IntegrationStatus.enum.success,
        runEndTime: sql`(CURRENT_TIMESTAMP)`,
        entriesCreated,
      })
      .where(eq(integrationRuns.id, run.id));

    console.log('Integration run completed successfully');
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error('Integration run failed:', errorMessage);

    await db
      .update(integrationRuns)
      .set({
        status: IntegrationStatus.enum.fail,
        runEndTime: sql`(CURRENT_TIMESTAMP)`,
        message: errorMessage,
      })
      .where(eq(integrationRuns.id, run.id));

    throw error;
  }
}
