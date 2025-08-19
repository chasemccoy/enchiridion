/* eslint-disable no-console */
import { syncReadwiseData } from '@integrations/readwise/sync';
import { Router } from 'express';

export const integrationRoutes = Router();

interface LogMessage {
  type: 'info' | 'error' | 'warn' | 'success';
  message: string;
  timestamp: string;
}

interface IntegrationResult {
  success: boolean;
  messages: LogMessage[];
  entriesCreated?: number;
  error?: string;
}

// ============================================================================
// POST
// ============================================================================

integrationRoutes.post('/sync/readwise', async (_, res, next) => {
  const messages: LogMessage[] = [];
  let entriesCreated = 0;

  const originalConsoleLog = console.log;
  const originalConsoleError = console.error;
  const originalConsoleWarn = console.warn;

  console.log = (...args: unknown[]) => {
    const message = args
      .map((arg) => (typeof arg === 'object' ? JSON.stringify(arg, null, 2) : String(arg)))
      .join(' ');

    const entryMatch = message.match(/Successfully created (\d+) entries/);

    if (entryMatch && entryMatch[1]) {
      entriesCreated = parseInt(entryMatch[1], 10);
    }

    messages.push({
      type: 'info',
      message,
      timestamp: new Date().toISOString(),
    });

    originalConsoleLog(...args);
  };

  console.error = (...args: unknown[]) => {
    const message = args
      .map((arg) => (typeof arg === 'object' ? JSON.stringify(arg, null, 2) : String(arg)))
      .join(' ');

    messages.push({
      type: 'error',
      message,
      timestamp: new Date().toISOString(),
    });

    originalConsoleError(...args);
  };

  console.warn = (...args: unknown[]) => {
    const message = args
      .map((arg) => (typeof arg === 'object' ? JSON.stringify(arg, null, 2) : String(arg)))
      .join(' ');

    messages.push({
      type: 'warn',
      message,
      timestamp: new Date().toISOString(),
    });

    originalConsoleWarn(...args);
  };

  try {
    await syncReadwiseData();

    messages.push({
      type: 'success',
      message: `Readwise sync completed successfully${entriesCreated > 0 ? `. Created ${entriesCreated} entries.` : '.'}`,
      timestamp: new Date().toISOString(),
    });

    res.json({
      success: true,
      messages,
      entriesCreated,
    });
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';

    messages.push({
      type: 'error',
      message: `Sync failed: ${errorMessage}`,
      timestamp: new Date().toISOString(),
    });

    next(error);
  } finally {
    console.log = originalConsoleLog;
    console.error = originalConsoleError;
    console.warn = originalConsoleWarn;
  }
});

export type SyncRunAPIResponse = IntegrationResult;
