/* eslint-disable no-console */
import { styleText } from 'node:util';
import { report } from './progress';

function formatArgs(args: unknown[]): string {
  return args
    .map((arg) => {
      if (arg instanceof Error) return arg.message;
      if (typeof arg === 'object' && arg !== null) return JSON.stringify(arg);
      return String(arg);
    })
    .join(' ');
}

/**
 * Creates a logger with a specific prefix for integration processes
 *
 * Every line also goes to the active sync reporter (see ./progress.ts) as a
 * `log` event, so a UI driving the sync sees the same trail the terminal does.
 *
 * @param integration - The name of the integration (e.g., 'twitter', 'github')
 * @param process - The specific process being logged (e.g., 'sync', 'map')
 * @returns An object with logging methods
 */
export function createIntegrationLogger(integration: string, process: string) {
  const scope = `${integration}:${process}`;
  const prefix = `[${scope}]`;

  const mirror = (level: 'info' | 'warn' | 'error', message: string, args: unknown[]) => {
    const suffix = args.length > 0 ? ` ${formatArgs(args)}` : '';
    report({ type: 'log', level, scope, message: `${message}${suffix}` });
  };

  return {
    /**
     * Log an informational message
     */
    info: (message: string, ...args: unknown[]) => {
      console.log(`${prefix} ${message}`, ...args);
      mirror('info', message, args);
    },

    /**
     * Log a warning message
     */
    warn: (message: string, ...args: unknown[]) => {
      console.warn(styleText('yellow', `${prefix} ${message}`), ...args);
      mirror('warn', message, args);
    },

    /**
     * Log an error message
     */
    error: (message: string, error?: unknown, ...args: unknown[]) => {
      if (error instanceof Error) {
        console.error(styleText('red', `${prefix} ${message}:`), error.message, ...args);

        if (error.stack) {
          console.error(styleText('red', error.stack));
        }
        mirror('error', `${message}: ${error.message}`, args);
      } else if (error !== undefined) {
        console.error(styleText('red', `${prefix} ${message}:`), error, ...args);
        mirror('error', `${message}: ${formatArgs([error])}`, args);
      } else {
        console.error(styleText('red', `${prefix} ${message}`), ...args);
        mirror('error', message, args);
      }
    },

    /**
     * Log the start of a process
     */
    start: (message: string = 'Starting', ...args: unknown[]) => {
      console.log(styleText('green', `${prefix} ${message}`), ...args);
      mirror('info', message, args);
    },

    /**
     * Log the completion of a process
     */
    complete: (message: string = 'Completed', count?: number) => {
      const countStr = count !== undefined ? ` (${count} items)` : '';
      console.log(`${prefix} ${message}${countStr}`);
      mirror('info', `${message}${countStr}`, []);
    },

    /**
     * Log a skipped process
     */
    skip: (message: string = 'Skipped', reason?: string) => {
      const reasonStr = reason ? `: ${reason}` : '';
      console.log(`${prefix} ${message}${reasonStr}`);
      mirror('info', `${message}${reasonStr}`, []);
    },
  };
}
