import type {
  DraftRecord,
  DraftReference,
  PredicateSlug,
  RecordType,
} from '@shared/types/ramble';

const TITLE_MAX_LENGTH = 80;

/**
 * Derive a {@link DraftRecord} from a contenteditable element. Pure with
 * respect to the input element — it does not mutate the DOM. The walker
 * consumes pill nodes by their `data-pill` attribute set, and treats every
 * other element as a wrapper to recurse into.
 *
 * Whitespace handling: pills are stripped from the textual content (they
 * live in the references/urls arrays instead). To avoid double-spaces and
 * orphaned punctuation, we emit a single-space marker for each stripped
 * pill, then run a cleanup pass that collapses runs of spaces and pulls
 * a stray space out from in front of `,.;:!?)]}` or after `([{`.
 */
export function draftFromEditor(root: HTMLElement | null): DraftRecord {
  if (!root) return emptyDraft();

  const segments: string[] = [];
  const urls: DraftRecord['urls'] = [];
  const references: DraftReference[] = [];

  for (const node of Array.from(root.childNodes)) walk(node);

  function walk(node: Node) {
    if (node.nodeType === Node.TEXT_NODE) {
      segments.push(node.textContent ?? '');
      return;
    }
    if (!(node instanceof HTMLElement)) return;

    const kind = node.dataset.pill;

    if (kind === 'link') {
      const url = node.dataset.url ?? '';
      if (url) urls.push({ url, predicate: 'references' });
      segments.push(' ');
      return;
    }
    if (kind === 'mention' || kind === 'concept') {
      const idRaw = node.dataset.recordId;
      const id = idRaw ? Number(idRaw) : NaN;
      const slug = node.dataset.slug;
      const label = node.dataset.label;
      const type = node.dataset.type as RecordType | undefined;
      const predicate = node.dataset.predicate as PredicateSlug | undefined;
      if (Number.isFinite(id) && slug && label && type && predicate) {
        references.push({ id, slug, label, type, predicate });
      }
      segments.push(' ');
      return;
    }

    if (node.tagName === 'BR') {
      segments.push('\n');
      return;
    }
    for (const child of Array.from(node.childNodes)) walk(child);
    if (node.tagName === 'DIV' || node.tagName === 'P') segments.push('\n');
  }

  const text = normalizeText(segments.join(''));
  const { title, body } = splitTitle(text);

  return {
    title,
    content: body,
    recordType: inferRecordType(urls, references),
    urls: dedupeUrls(urls),
    references: dedupeReferences(references),
  };
}

export function emptyDraft(): DraftRecord {
  return {
    title: null,
    content: '',
    recordType: 'artifact',
    urls: [],
    references: [],
  };
}

export function isUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === 'http:' || url.protocol === 'https:';
  } catch {
    return false;
  }
}

export function hostnameOf(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch {
    return url;
  }
}

/**
 * Count the populated draft fields. Used by the view to gate the preview
 * (≥2 signals → show). Exported so it's testable in isolation.
 */
export function countDraftSignals(draft: DraftRecord): number {
  let n = 0;
  if (draft.title) n += 1;
  if (draft.content.trim().length > 0) n += 1;
  if (draft.references.length > 0) n += 1;
  if (draft.urls.length > 0) n += 1;
  return n;
}

function normalizeText(raw: string): string {
  return raw
    .replace(/[ \t]+/g, ' ')
    .replace(/ ?\n ?/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .replace(/ ([,.;:!?)\]}])/g, '$1')
    .replace(/([(\[{]) /g, '$1')
    .trim();
}

function splitTitle(text: string): { title: string | null; body: string } {
  const lines = text.split('\n');
  const firstLine = lines[0]?.trim() ?? '';
  if (firstLine.length === 0) return { title: null, body: text };

  const remainingLines = lines.slice(1).join('\n').trim();

  // First line fits the title budget — use it whole.
  if (firstLine.length <= TITLE_MAX_LENGTH) {
    return { title: firstLine, body: remainingLines };
  }

  // First line overflows. Pull off the longest title-shaped prefix at a
  // word boundary, push the rest onto the body so the user doesn't lose
  // any of what they wrote.
  const head = firstLine.slice(0, TITLE_MAX_LENGTH);
  const lastSpace = head.lastIndexOf(' ');
  const splitAt = lastSpace > TITLE_MAX_LENGTH / 2 ? lastSpace : TITLE_MAX_LENGTH;
  const title = firstLine.slice(0, splitAt).trim();
  const overflow = firstLine.slice(splitAt).trim();
  const body = [overflow, remainingLines].filter(Boolean).join('\n\n');
  return { title, body };
}

function dedupeReferences(references: DraftReference[]): DraftReference[] {
  const seen = new Set<string>();
  return references.filter((ref) => {
    const key = `${ref.slug}:${ref.predicate}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function dedupeUrls(urls: DraftRecord['urls']): DraftRecord['urls'] {
  const seen = new Set<string>();
  return urls.filter((entry) => {
    if (seen.has(entry.url)) return false;
    seen.add(entry.url);
    return true;
  });
}

function inferRecordType(
  urls: DraftRecord['urls'],
  references: DraftReference[],
): RecordType {
  if (urls.length > 0) return 'artifact';
  if (references.length > 0 && references.every((r) => r.type === 'concept')) return 'concept';
  return 'artifact';
}
