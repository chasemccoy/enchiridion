<template>
  <div
    v-if="record"
    class="V3"
  >
    <article class="V3__article">
      <div class="V3__masthead">
        <span>{{ capitalize(record.type) }}</span>
        <span
          v-if="record.source && record.source !== 'manual'"
          class="V3__mastheadDot"
        >
          ·
        </span>
        <span v-if="record.source && record.source !== 'manual'">
          {{ capitalize(record.source) }}
        </span>
        <span class="V3__mastheadDot">·</span>
        <span>Captured {{ capturedAt }}</span>
        <span class="V3__mastheadId">№ {{ record.id }}</span>
      </div>

      <h1 class="V3__title">{{ record.title }}</h1>

      <p
        v-if="record.summary"
        class="V3__deck"
      >
        {{ record.summary }}
      </p>

      <div class="V3__byline">
        <template v-if="creator">
          <span class="V3__bylineLabel">By</span>
          <RouterLink
            class="V3__bylineLink"
            :to="`/${creator.slug}`"
          >
            {{ creator.title }}
          </RouterLink>
        </template>
        <span
          v-if="record.url"
          class="V3__bylineUrl"
        >
          <span class="V3__bylineLabel">·</span>
          <a
            target="_blank"
            :href="record.url"
          >
            {{ getHost(record.url) }}
          </a>
        </span>
        <span
          v-if="publishedAt"
          class="V3__bylineLabel"
        >
          · Published {{ publishedAt }}
        </span>
      </div>

      <div
        v-if="tags.length"
        class="V3__tagRow"
      >
        <RouterLink
          v-for="tag in tags"
          :key="tag.id"
          class="V3__tag"
          :to="`/${tag.slug}`"
        >
          {{ tag.title || tag.slug }}
        </RouterLink>
        <span
          v-for="(fmt, idx) in formats"
          :key="`fmt-${idx}`"
          class="V3__format"
        >
          {{ fmt.title }}
        </span>
      </div>

      <div class="V3__rule" />

      <div class="V3__body">
        <MarkdownRender
          v-if="record.content"
          :source="record.content"
        />
        <div
          v-else
          class="V3__empty"
        >
          <em>No body yet.</em> Tap anywhere here to start writing.
        </div>
      </div>

      <div class="V3__rule V3__rule--strong" />

      <section class="V3__notes">
        <span class="V3__notesLabel">Notes</span>
        <UTextarea
          v-model="notesDraft"
          variant="ghost"
          placeholder="Why this is here, what it ties to…"
          :rows="1"
          :ui="{ base: 'V3__notesInput' }"
          autoresize
        />
      </section>

      <div class="V3__rule" />

      <section class="V3__refs">
        <header class="V3__refsHead">
          <span class="V3__refsLabel">Linked records</span>
          <UButton
            size="xs"
            color="neutral"
            variant="ghost"
            icon="i-lucide-plus"
            label="Add"
          />
        </header>

        <div
          v-for="group in linkGroups"
          :key="group.predicate"
          class="V3__refGroup"
        >
          <div class="V3__refGroupLabel">
            <span class="V3__refSection">{{ capitalize(humanizePredicate(group.predicate)) }}</span>
            <span
              v-if="group.items.length > 3"
              class="V3__refCount"
            >
              {{ group.items.length }}
            </span>
          </div>
          <ul class="V3__refList">
            <li
              v-for="item in group.items"
              :key="item.id"
            >
              <RouterLink
                class="V3__refLine"
                :to="`/${item.slug}`"
              >
                <span class="V3__refTitle">{{ item.title || item.slug }}</span>
                <span
                  v-if="item.host"
                  class="V3__refHost"
                >
                  {{ item.host }}
                </span>
              </RouterLink>
            </li>
          </ul>
        </div>

        <div
          v-if="incomingChildren.length"
          class="V3__refGroup"
        >
          <div class="V3__refGroupLabel">
            <span class="V3__refSection">Mentioned in</span>
            <span class="V3__refCount">{{ incomingChildren.length }}</span>
          </div>
          <ul class="V3__refList">
            <li
              v-for="child in incomingChildren"
              :key="child.id"
            >
              <RouterLink
                class="V3__refLine V3__refLine--prose"
                :to="`/${child.slug}`"
              >
                <span class="V3__refTitle">{{ child.title || `#${child.id}` }}</span>
                <span
                  v-if="child.summary"
                  class="V3__refSnip"
                >
                  — {{ child.summary }}
                </span>
              </RouterLink>
            </li>
          </ul>
        </div>
      </section>
    </article>
  </div>
</template>

<script setup lang="ts">
import MarkdownRender from '@app/components/MarkdownRender.vue';
import { capitalize, formatDate } from '@shared/lib/formatting';
import { computed, ref } from 'vue';
import { humanizePredicate, useLabRecord } from '../useLabRecord';

const { record, links } = useLabRecord();

const notesDraft = ref('');

const capturedAt = computed(() =>
  record.value ? formatDate(record.value.recordCreatedAt) : null,
);
const publishedAt = computed(() =>
  record.value?.contentCreatedAt ? formatDate(record.value.contentCreatedAt) : null,
);

const outgoing = computed(() => links.value?.outgoingLinks ?? []);
const incoming = computed(() => links.value?.incomingLinks ?? []);

const creator = computed(
  () => outgoing.value.find((l) => l.predicate === 'created_by')?.target ?? null,
);

const tags = computed(() =>
  outgoing.value
    .filter((l) => l.predicate === 'tagged_with')
    .map((l) => ({ id: l.targetId, slug: l.target.slug, title: l.target.title })),
);

const formats = computed(() =>
  outgoing.value
    .filter((l) => l.predicate === 'has_format')
    .map((l) => ({ id: l.targetId, title: l.target.title })),
);

const skipPredicates = new Set(['tagged_with', 'has_format', 'created_by']);

const linkGroups = computed(() => {
  const filtered = outgoing.value.filter((l) => !skipPredicates.has(l.predicate));
  const groups = new Map<
    string,
    Array<{ id: number; slug: string; title: string | null; host?: string }>
  >();
  for (const link of filtered) {
    if (!groups.has(link.predicate)) groups.set(link.predicate, []);
    groups.get(link.predicate)!.push({
      id: link.targetId,
      slug: link.target.slug,
      title: link.target.title,
      host: (link.target as { url?: string }).url
        ? getHost((link.target as { url: string }).url)
        : undefined,
    });
  }
  return Array.from(groups.entries()).map(([predicate, items]) => ({ predicate, items }));
});

const incomingChildren = computed(() =>
  incoming.value
    .filter((l) => l.source)
    .map((l) => ({
      id: l.sourceId,
      slug: l.source.slug,
      title: l.source.title,
      summary: (l.source as { summary?: string }).summary ?? null,
    }))
    .slice(0, 8),
);

function getHost(url: string): string {
  try {
    return new URL(url).host.replace(/^www\./, '');
  } catch {
    return url;
  }
}
</script>

<style scoped>
.V3 {
  padding: 24px 24px 64px;
}

.V3__article {
  max-width: 680px;
  margin: 0 auto;
  display: grid;
  gap: 14px;
  font-family: 'Iowan Old Style', Georgia, 'Times New Roman', serif;
  color: var(--ui-text);
}

.V3__masthead {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-family: ui-sans-serif, system-ui, sans-serif;
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  color: var(--ui-text-dimmed);
}

.V3__mastheadDot {
  margin: 0 2px;
}

.V3__mastheadId {
  margin-left: auto;
  font-family: var(--font-mono, ui-monospace, monospace);
  letter-spacing: 0.04em;
}

.V3__title {
  font-size: 2.6rem;
  line-height: 1.05;
  font-weight: 700;
  letter-spacing: -0.015em;
  text-wrap: balance;
  margin-top: 4px;
}

.V3__deck {
  font-size: 1.25rem;
  line-height: 1.4;
  color: var(--ui-text-muted);
  text-wrap: pretty;
  font-weight: 400;
  font-style: italic;
  border-left: 3px solid var(--ui-border-accented);
  padding-left: 14px;
  margin-top: 4px;
}

.V3__byline {
  font-family: ui-sans-serif, system-ui, sans-serif;
  font-size: 0.85rem;
  color: var(--ui-text-muted);
  display: inline-flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px;
}

.V3__bylineLabel {
  color: var(--ui-text-dimmed);
}

.V3__bylineLink {
  font-weight: 500;
  color: var(--ui-text);

  &:hover {
    text-decoration: underline;
  }
}

.V3__bylineUrl a {
  color: var(--ui-text);
  text-decoration: underline;
  text-decoration-color: var(--ui-text-dimmed);
}

.V3__tagRow {
  display: inline-flex;
  flex-wrap: wrap;
  gap: 4px 12px;
  font-family: ui-sans-serif, system-ui, sans-serif;
  font-size: 0.75rem;
}

.V3__tag {
  color: var(--ui-primary);

  &::before {
    content: '#';
    color: var(--ui-text-dimmed);
  }

  &:hover {
    text-decoration: underline;
  }
}

.V3__format {
  color: var(--ui-text-dimmed);
  font-style: italic;

  &::before {
    content: '◊ ';
  }
}

.V3__rule {
  height: 1px;
  background: var(--ui-border);
  margin: 16px 0;
}

.V3__rule--strong {
  background: var(--ui-text);
  height: 2px;
  margin: 32px 0 24px;
}

.V3__body {
  font-size: 1.05rem;
  line-height: 1.7;

  :deep(.MarkdownRender) {
    font-family: inherit;
    font-size: 1.05rem;
    line-height: 1.7;
  }

  :deep(.MarkdownRender p) {
    margin-bottom: 1em;
  }
}

.V3__empty {
  color: var(--ui-text-dimmed);
  font-size: 1rem;
}

.V3__notes {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 14px;
  align-items: baseline;
  font-family: ui-sans-serif, system-ui, sans-serif;
}

.V3__notesLabel {
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  color: var(--ui-text-dimmed);
  padding-top: 6px;
}

:deep(.V3__notesInput) {
  background: transparent;
  border: 0;
  box-shadow: none;
  padding: 0;
  font-family: ui-sans-serif, system-ui, sans-serif;
  font-size: 0.95rem;
  line-height: 1.5;
}

.V3__refs {
  font-family: ui-sans-serif, system-ui, sans-serif;
  display: grid;
  gap: 18px;
}

.V3__refsHead {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
}

.V3__refsLabel {
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  color: var(--ui-text-dimmed);
}

.V3__refGroup {
  display: grid;
  grid-template-columns: 140px 1fr;
  gap: 14px;
  align-items: start;
}

.V3__refGroupLabel {
  display: inline-flex;
  align-items: baseline;
  gap: 6px;
  padding-top: 4px;
}

.V3__refSection {
  font-size: 0.8rem;
  font-weight: 500;
  color: var(--ui-text);
}

.V3__refCount {
  font-size: 0.7rem;
  color: var(--ui-text-dimmed);
}

.V3__refList {
  display: grid;
  list-style: none;
  margin: 0;
  padding: 0;
}

.V3__refList li {
  border-bottom: 1px solid var(--ui-border);
}

.V3__refList li:last-child {
  border-bottom: 0;
}

.V3__refLine {
  display: flex;
  align-items: baseline;
  gap: 8px;
  padding: 6px 0;
  font-size: 0.85rem;
  color: var(--ui-text);

  &:hover {
    color: var(--ui-primary);
  }
}

.V3__refTitle {
  font-weight: 500;
}

.V3__refHost {
  color: var(--ui-text-dimmed);
  font-size: 0.7rem;
  margin-left: auto;
  font-family: var(--font-mono, ui-monospace, monospace);
}

.V3__refLine--prose {
  display: block;
}

.V3__refSnip {
  color: var(--ui-text-muted);
  font-weight: 400;
  display: block;
  font-size: 0.78rem;
  line-height: 1.4;
  margin-top: 2px;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
</style>
