import { excerpt, highlightSegments, plainText } from '@shared/lib/search-preview';
import { describe, expect, it } from 'vitest';

describe('plainText', () => {
  it('drops Markdown syntax but keeps the words', () => {
    const markdown =
      '# Heading\n\nSome *emphasis*, `code` and a [link](https://example.com).\n\n> A quote\n- one\n2. two';
    expect(plainText(markdown)).toBe('Heading Some emphasis, code and a link. A quote one two');
  });

  it('is empty for nothing', () => {
    expect(plainText(null)).toBe('');
    expect(plainText('  \n ')).toBe('');
  });
});

describe('excerpt', () => {
  const text = `${'lorem ipsum '.repeat(40)}the servilleta was sewn with conductive thread ${'dolor sit '.repeat(20)}`;

  it('keeps short text whole', () => {
    expect(excerpt('short text', 'text')).toBe('short text');
  });

  it('starts at the beginning when nothing matches', () => {
    const result = excerpt(text, 'nowhere', 60);
    expect(result.startsWith('lorem ipsum')).toBe(true);
    expect(result.endsWith('…')).toBe(true);
  });

  it('centers on the first match deep in the text', () => {
    const result = excerpt(text, 'servilleta', 80);
    expect(result.startsWith('…')).toBe(true);
    expect(result).toContain('servilleta');
    expect(result.length).toBeLessThanOrEqual(84);
  });
});

describe('highlightSegments', () => {
  it('marks each searched word, case kept', () => {
    expect(highlightSegments('Hello Again, Seattle', 'hell seattle')).toEqual([
      { text: 'Hell', match: true },
      { text: 'o Again, ', match: false },
      { text: 'Seattle', match: true },
    ]);
  });

  it('treats the query as text, not a pattern', () => {
    expect(highlightSegments('a+b (c)', '(c)')).toEqual([
      { text: 'a+b ', match: false },
      { text: '(c)', match: true },
    ]);
  });

  it('returns the text whole for a blank query', () => {
    expect(highlightSegments('words', '  ')).toEqual([{ text: 'words', match: false }]);
  });
});
