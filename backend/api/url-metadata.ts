import { Router } from 'express';

export const urlMetadataRoutes = Router();

const FETCH_TIMEOUT_MS = 6_000;
const MAX_HTML_BYTES = 512 * 1024;

export type UrlMetadata = {
  url: string;
  finalUrl: string;
  title: string | null;
  description: string | null;
  image: string | null;
  siteName: string | null;
};

// Lightweight OG/HTML metadata fetch. No external parser — we read only enough
// of the page to find the head-level tags we care about, which is plenty for a
// preview and stays under the timeout for slow targets.
urlMetadataRoutes.get('/url-metadata', async (req, res, next) => {
  try {
    const raw = typeof req.query.url === 'string' ? req.query.url : '';
    let url: URL;
    try {
      url = new URL(raw);
    } catch {
      res.status(400).json({ error: 'Invalid url parameter' });
      return;
    }
    if (url.protocol !== 'http:' && url.protocol !== 'https:') {
      res.status(400).json({ error: 'Only http(s) URLs are supported' });
      return;
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

    let response: Response;
    try {
      response = await fetch(url, {
        redirect: 'follow',
        signal: controller.signal,
        headers: {
          // Some sites gate metadata behind a UA check.
          'user-agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36',
          accept: 'text/html,application/xhtml+xml',
        },
      });
    } finally {
      clearTimeout(timer);
    }

    const contentType = response.headers.get('content-type') ?? '';
    if (!contentType.includes('html')) {
      res.json({
        url: url.toString(),
        finalUrl: response.url,
        title: null,
        description: null,
        image: null,
        siteName: null,
      } satisfies UrlMetadata);
      return;
    }

    const html = await readLimitedText(response, MAX_HTML_BYTES);
    const headBlock = html.slice(0, html.indexOf('</head>') + 7) || html;

    const metadata: UrlMetadata = {
      url: url.toString(),
      finalUrl: response.url,
      title:
        readMeta(headBlock, 'og:title') ??
        readMeta(headBlock, 'twitter:title') ??
        readTitleTag(headBlock),
      description:
        readMeta(headBlock, 'og:description') ??
        readMeta(headBlock, 'twitter:description') ??
        readMeta(headBlock, 'description'),
      image:
        absolutize(readMeta(headBlock, 'og:image'), response.url) ??
        absolutize(readMeta(headBlock, 'twitter:image'), response.url),
      siteName: readMeta(headBlock, 'og:site_name'),
    };

    res.json(metadata);
  } catch (error) {
    next(error);
  }
});

async function readLimitedText(response: Response, maxBytes: number): Promise<string> {
  if (!response.body) return '';
  const reader = response.body.getReader();
  const decoder = new TextDecoder('utf-8', { fatal: false });
  let received = 0;
  let html = '';
  // Streaming guards us against multi-megabyte pages that would otherwise stall
  // the request — once we hit the cap or see </head>, we cancel the rest.
  while (received < maxBytes) {
    const { value, done } = await reader.read();
    if (done) break;
    received += value.byteLength;
    html += decoder.decode(value, { stream: true });
    if (html.includes('</head>')) break;
  }
  html += decoder.decode();
  try {
    await reader.cancel();
  } catch {
    /* ignore */
  }
  return html;
}

function readMeta(html: string, name: string): string | null {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const patterns = [
    new RegExp(
      `<meta[^>]*?(?:property|name)\\s*=\\s*["']${escaped}["'][^>]*?content\\s*=\\s*["']([^"']*)["']`,
      'i',
    ),
    new RegExp(
      `<meta[^>]*?content\\s*=\\s*["']([^"']*)["'][^>]*?(?:property|name)\\s*=\\s*["']${escaped}["']`,
      'i',
    ),
  ];
  for (const pattern of patterns) {
    const match = pattern.exec(html);
    if (match && match[1]) return decodeEntities(match[1].trim());
  }
  return null;
}

function readTitleTag(html: string): string | null {
  const match = /<title[^>]*>([^<]*)<\/title>/i.exec(html);
  return match && match[1] ? decodeEntities(match[1].trim()) : null;
}

function absolutize(value: string | null, base: string): string | null {
  if (!value) return null;
  try {
    return new URL(value, base).toString();
  } catch {
    return null;
  }
}

function decodeEntities(value: string): string {
  return value
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .replace(/&#x([0-9a-f]+);/gi, (_, code) => String.fromCodePoint(parseInt(code, 16)))
    .replace(/&#(\d+);/g, (_, code) => String.fromCodePoint(parseInt(code, 10)));
}
