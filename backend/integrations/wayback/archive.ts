/* eslint-disable no-console */

/**
 * Archives a URL to the Wayback Machine asynchronously.
 * Fires the request in the background without blocking execution.
 * Success/failure is logged but doesn't affect the caller.
 */
export function archiveUrlToWayback(url: string) {
  if (!url || url.trim() === '') return;

  // Fire off the request without awaiting - let it complete in the background
  fetch(`https://web.archive.org/save/${url}`)
    .then((response) => {
      if (response.ok) {
        console.log(`[Wayback] Archived: ${url}`);
      } else {
        console.error(
          `[Wayback] Failed to archive ${url}: ${response.status} ${response.statusText}`,
        );
      }
    })
    .catch((error) => {
      console.error(`[Wayback] Error archiving ${url}:`, (error as Error).message);
    });
}
