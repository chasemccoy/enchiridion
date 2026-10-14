/**
 * Helpers for search result previews: a record's Markdown as one line of plain
 * text, an excerpt centered on what was searched for, and the text split into
 * matched and unmatched runs so a template can highlight matches without
 * `v-html`.
 */

/** Markdown as plain text on one line: block markers, inline marks and link syntax dropped (link text kept). */
export function plainText(markdown: string | null | undefined): string {
  if (!markdown) return '';
  return markdown
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/!\[[^\]]*\]\([^)]*\)/g, ' ')
    .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/^\s{0,3}(#{1,6}|>+|[-*+]|\d+[.)])\s+/gm, '')
    .replace(/^\s*([-*_]\s*){3,}$/gm, ' ')
    .replace(/(\*\*|__|==|~~|`)/g, '')
    .replace(/(^|\W)[*_](\S[^*_]*?)[*_](?=\W|$)/g, '$1$2')
    .replace(/\s+/g, ' ')
    .trim();
}

/** The words searched for, lowercased, longest first so overlapping matches prefer the longer one. */
function terms(query: string): string[] {
  return [
    ...new Set(
      query
        .toLowerCase()
        .split(/\s+/)
        .filter((term) => term.length > 0),
    ),
  ].sort((a, b) => b.length - a.length);
}

/**
 * About `length` characters of `text`: from the start when no term appears in
 * it (or in the opening stretch), otherwise around the first match, with an
 * ellipsis on whichever end was cut.
 */
export function excerpt(text: string, query: string, length = 220): string {
  if (text.length <= length) return text;
  const lower = text.toLowerCase();
  const positions = terms(query)
    .map((term) => lower.indexOf(term))
    .filter((index) => index >= 0);
  const first = positions.length > 0 ? Math.min(...positions) : -1;
  if (first < length * 0.6) return `${cut(text.slice(0, length), 'end')}…`;
  const start = Math.max(0, first - Math.round(length * 0.3));
  const end = Math.min(text.length, start + length);
  const body = cut(cut(text.slice(start, end), 'start'), end < text.length ? 'end' : 'none');
  return `…${body}${end < text.length ? '…' : ''}`;
}

/** Drops a partial word at one end, so an excerpt starts and stops on word boundaries. */
function cut(text: string, end: 'start' | 'end' | 'none'): string {
  if (end === 'start') return text.replace(/^\S*\s+/, '');
  if (end === 'end') return text.replace(/\s+\S*$/, '').replace(/[\s.,;:]+$/, '');
  return text;
}

export interface Segment {
  text: string;
  match: boolean;
}

/** `text` in runs, each a match of a searched word or not; case is kept as written. */
export function highlightSegments(text: string, query: string): Segment[] {
  const words = terms(query);
  if (!text || words.length === 0) return text ? [{ text, match: false }] : [];
  const pattern = new RegExp(`(${words.map(escapeRegExp).join('|')})`, 'gi');
  return text
    .split(pattern)
    .filter((part) => part.length > 0)
    .map((part) => ({ text: part, match: words.includes(part.toLowerCase()) }));
}

function escapeRegExp(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
