// Lab manifest — trail of explore/tune rounds for the homepage-browse brief.
// `seededFrom` points at the pick that spawned each round.

export interface SeededFrom {
  round: number;
  choice: number;
  action: 'variations' | 'tune' | 'choose';
  note?: string;
}

export interface VariantEntry {
  label: string;
  blurb?: string;
  file: string;
}

export interface RoundEntry {
  n: number;
  mode: 'grid' | 'tabs' | 'tune';
  seededFrom: SeededFrom | null;
  variants: VariantEntry[];
}

export const slug = 'homepage-browse-q8r3';
export const brief =
  'Reimagine the Enchiridion homepage for browsing & discovery (today: a 3-col month-grouped waterfall that collapses into split view)';

export const rounds: RoundEntry[] = [
  {
    n: 1,
    mode: 'tabs',
    seededFrom: null,
    variants: [
      {
        label: 'The Gazette',
        blurb:
          'The home as a personal periodical. Serif masthead, an asymmetric front page: one big lead story with image + deck, a ruled "Latest" rail, then secondary entries in editorial columns. Curated, visual discovery.',
        file: '1/Variant1.vue',
      },
      {
        label: 'Discovery shelves',
        blurb:
          'Streaming-style horizontal shelves — Recently added, Jump back in (older serendipity), Concepts to explore, People & sources, With media. Many entry points; re-encounter what you forgot you saved.',
        file: '1/Variant2.vue',
      },
      {
        label: 'The Handbook',
        blurb:
          'Leans into "Enchiridion" = a handbook. A sticky themed index rail (concepts A–Z by frequency) beside an encyclopedic directory grouped by type with counts and a band of most-connected hubs. Structural, reference-grade.',
        file: '1/Variant3.vue',
      },
      {
        label: 'Dense river',
        blurb:
          'Maximum-density power-browse. One tight row per record — type glyph, title, faint one-liner, host, date, thumbnail — under sticky month dividers. Built to scan 700+ items fast. Utilitarian and quick.',
        file: '1/Variant4.vue',
      },
    ],
  },
  {
    n: 2,
    mode: 'tabs',
    seededFrom: {
      round: 1,
      choice: 2,
      action: 'variations',
      note: 'Handbook concept sidebar (browse concepts by popularity) + Dense river record list. Drop the big "The Enchiridion" masthead — single-user tool. Show how each goes to split view on select, especially selecting a concept from the sidebar.',
    },
    variants: [
      {
        label: 'Triptych',
        blurb:
          'Concept rail is always present. Click a concept → it filters the river. Click a record → a 3-pane split opens (concepts · list rail · reading pane), so you can keep re-filtering by theme while you read. Interactive — click around.',
        file: '2/Variant1.vue',
      },
      {
        label: 'Focus',
        blurb:
          'Reading-first. Concept rail filters the river while browsing; the moment you open a record the rail yields so the reading pane gets full width (the app\'s current 2-pane split). A "Concepts" toggle pops the rail back when you want to re-filter mid-read.',
        file: '2/Variant2.vue',
      },
      {
        label: 'Concept as destination',
        blurb:
          'The sidebar is a true index. Clicking a concept opens it as a page in the reading pane — its description plus every record tagged with it. Open one of those and it becomes the list rail beside the record. Records and concepts are both first-class destinations.',
        file: '2/Variant3.vue',
      },
    ],
  },
];
