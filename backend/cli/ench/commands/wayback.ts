/**
 * Wayback Machine commands for the `ench` CLI.
 */

import { getRecord } from '@db/queries/records';
import { archiveUrlToWayback } from '@integrations/wayback/archive';
import { BaseOptionsSchema, parseId, parseOptions } from '../lib/args';
import { createError } from '../lib/errors';
import { success } from '../lib/output';
import type { CommandHandler } from '../lib/types';

function isProbablyUrl(value: string): boolean {
  return /^https?:\/\//i.test(value);
}

/**
 * Submit a URL (or a record's URL) to web.archive.org/save.
 *
 * The request is fire-and-forget by design; we get back the `web.archive.org`
 * snapshot URL by checking the availability API a moment later.
 *
 * Usage: ench wayback archive <url-or-record-id>
 */
export const archive: CommandHandler = async (args, options) => {
  parseOptions(BaseOptionsSchema, options);
  const target = args[0];
  if (!target) {
    throw createError('VALIDATION_ERROR', 'Usage: ench wayback archive <url-or-record-id>');
  }

  let url = target;
  let recordId: number | null = null;
  if (!isProbablyUrl(target)) {
    const id = parseId([target]);
    const record = await getRecord(id);
    if (!record) throw createError('NOT_FOUND', `Record ${id} not found`);
    if (!record.url) throw createError('VALIDATION_ERROR', `Record ${id} has no URL to archive`);
    url = record.url;
    recordId = id;
  }

  archiveUrlToWayback(url);
  // Probe the availability API right after queueing the save so we can return
  // the resulting snapshot URL if it landed in time. If not, the caller can
  // re-run `ench wayback status` shortly.
  await new Promise((resolve) => setTimeout(resolve, 1500));
  const snapshot = await fetchWaybackStatus(url);

  return success({
    url,
    recordId,
    submitted: true,
    snapshot,
  });
};

interface WaybackStatus {
  url: string | null;
  timestamp: string | null;
  available: boolean;
}

async function fetchWaybackStatus(url: string): Promise<WaybackStatus> {
  const apiUrl = `https://archive.org/wayback/available?url=${encodeURIComponent(url)}`;
  const response = await fetch(apiUrl, {
    headers: { Accept: 'application/json' },
  }).catch(() => null);
  if (!response?.ok) return { url: null, timestamp: null, available: false };
  const body = (await response.json().catch(() => null)) as {
    archived_snapshots?: { closest?: { url?: string; timestamp?: string; available?: boolean } };
  } | null;
  const closest = body?.archived_snapshots?.closest;
  return {
    url: closest?.url ?? null,
    timestamp: closest?.timestamp ?? null,
    available: closest?.available ?? false,
  };
}

/**
 * Look up the most recent Wayback snapshot for a URL.
 * Usage: ench wayback status <url>
 */
export const status: CommandHandler = async (args, options) => {
  parseOptions(BaseOptionsSchema, options);
  const url = args[0];
  if (!url) throw createError('VALIDATION_ERROR', 'Usage: ench wayback status <url>');
  const snapshot = await fetchWaybackStatus(url);
  return success({ url, snapshot });
};
