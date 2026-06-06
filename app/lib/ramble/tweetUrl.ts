/**
 * Pure helpers for detecting Twitter/X status URLs in pasted content.
 * Kept separate from the URL-metadata path so the editor can decide which
 * preview to render without round-tripping through the OG endpoint first.
 */

const TWEET_HOSTS = new Set(['twitter.com', 'www.twitter.com', 'x.com', 'www.x.com', 'mobile.twitter.com']);

/** Extract the numeric tweet id from a status URL, or null. */
export function extractTweetId(url: string): string | null {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }
  if (!TWEET_HOSTS.has(parsed.hostname)) return null;
  const match = parsed.pathname.match(/\/status\/(\d+)/);
  return match?.[1] ?? null;
}

export function isTweetUrl(url: string): boolean {
  return extractTweetId(url) !== null;
}
