// Lab manifest — trail of explore/tune rounds for this brief.
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

export const slug = 'record-detail-x7q4';
export const brief =
  'Explore layouts of the record detail page — metadata and links — that prioritize reading the content';

// Sample record used across all variants — picked for richness:
// 2 media attachments, 8 outgoing links spanning 4 predicates (created_by,
// about, tagged_with x3, related_to x3), real markdown body.
export const sampleSlug = 'paz-server';

export const rounds: RoundEntry[] = [
  {
    n: 1,
    mode: 'tabs',
    seededFrom: null,
    variants: [
      {
        label: 'Reading column + meta rail',
        blurb:
          'Content centered at readable width; a sticky right rail holds compact metadata and links grouped by predicate. Inline edit on click.',
        file: '1/Variant1.vue',
      },
      {
        label: 'Dossier header card',
        blurb:
          'A single bordered "dossier" at the top holds metadata as label/value rows. Title above, content below, links footer.',
        file: '1/Variant2.vue',
      },
      {
        label: 'Masthead, no chrome',
        blurb:
          'Newspaper masthead — tag-line, big title, deck, italic byline. Content flows. Links render as quiet sectioned lists with rule dividers, no card chrome.',
        file: '1/Variant3.vue',
      },
      {
        label: 'Hero content, tabbed links',
        blurb:
          'Slim metadata strip + disclosure for details. Content is the hero. Links collapse to a chip-tab strip — pick a predicate to scan that group.',
        file: '1/Variant4.vue',
      },
    ],
  },
  {
    n: 2,
    mode: 'tabs',
    seededFrom: {
      round: 1,
      choice: 3,
      action: 'variations',
      note:
        'Keep V4 hero + slim strip. Restore link metadata. Tags get own field. URL clickable on surface. Show media. Test in split-view width.',
    },
    variants: [
      {
        label: 'Grouped link cards',
        blurb:
          'Below content: each predicate is its own labeled section; links render as compact cards showing title, summary, and host. No filter UI — sectioned and scannable.',
        file: '2/Variant1.vue',
      },
      {
        label: 'Linked records table',
        blurb:
          'Below content: a single dense table with a predicate-badge column, title, summary preview, and host. Optional inline filter chips above. Editable on hover.',
        file: '2/Variant2.vue',
      },
      {
        label: 'Two-column RecordLink grid',
        blurb:
          'Below content: reuse the app\'s existing RecordLink cards in a 2-column grid grouped by predicate header. Same rich preview the rest of the app uses.',
        file: '2/Variant3.vue',
      },
      {
        label: 'Kicker rows + host rail',
        blurb:
          'Below content: each link is a row with a tiny predicate kicker, title, summary one-liner, and host pill on the right. Predicates separated by faint dividers.',
        file: '2/Variant4.vue',
      },
    ],
  },
  {
    n: 3,
    mode: 'tabs',
    seededFrom: {
      round: 2,
      choice: 3,
      action: 'variations',
      note:
        'Kicker rows, predicate label shown once per group. Host + tags back under each summary. No "Manual" source label. Two takes on how metadata editing (URL, record type) works.',
    },
    variants: [
      {
        label: 'Inline / on-surface editing',
        blurb:
          'Grouped kicker rows (label once). Type chip in the strip opens a menu to change type; URL is clickable with a hover pencil to edit in place. Edit where you read.',
        file: '3/Variant1.vue',
      },
      {
        label: 'Consolidated edit panel',
        blurb:
          'Same grouped kicker rows. Surface stays clean and clickable; a "Details / Edit" disclosure holds the type select, URL field, dates, and slug together in one place.',
        file: '3/Variant2.vue',
      },
    ],
  },
  {
    n: 4,
    mode: 'tune',
    seededFrom: {
      round: 3,
      choice: 1,
      action: 'tune',
      note:
        'Panel editing, tuned: RecordLink url/favicon style (LinkWithFavicon), no type icons in link rows, compact type segmented control, lighter (un-filled) edit panel.',
    },
    variants: [
      {
        label: 'Consolidated edit panel — tuned',
        blurb:
          'LinkWithFavicon for link URLs (no custom pill), no type icons on link rows, compact type segmented control, lighter bordered edit panel instead of a heavy gray fill.',
        file: '4/Variant.vue',
      },
    ],
  },
];
