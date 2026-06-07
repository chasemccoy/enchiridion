<template>
  <div
    v-if="record"
    class="V4"
  >
    <div class="V4__page">
      <div class="V4__strip">
        <UIcon
          class="V4__stripIcon"
          :name="getIconForRecordType(record.type)"
        />
        <span class="V4__stripType">{{ capitalize(record.type) }}</span>
        <span class="V4__stripDot">·</span>
        <a
          v-if="record.url"
          target="_blank"
          class="V4__stripUrl"
          :href="record.url"
        >
          {{ getHost(record.url) }}
          <UIcon
            name="i-lucide-arrow-up-right"
            class="V4__stripArrow"
          />
        </a>
        <span class="V4__stripDot">·</span>
        <span class="V4__stripDate">Captured {{ capturedAt }}</span>
        <button
          type="button"
          class="V4__stripDetails"
          @click="detailsOpen = !detailsOpen"
        >
          <UIcon
            class="V4__stripDetailsIcon"
            :name="detailsOpen ? 'i-lucide-chevron-up' : 'i-lucide-info'"
          />
          {{ detailsOpen ? 'Hide details' : 'Details' }}
        </button>
      </div>

      <Transition name="V4-fade">
        <div
          v-if="detailsOpen"
          class="V4__details"
        >
          <div class="V4__detailsGrid">
            <div class="V4__row">
              <span class="V4__rowLabel">Source</span>
              <span class="V4__rowValue">{{ record.source ? capitalize(record.source) : 'Manual' }}</span>
            </div>
            <div class="V4__row">
              <span class="V4__rowLabel">Published</span>
              <span class="V4__rowValue">{{ publishedAt || '—' }}</span>
            </div>
            <div class="V4__row">
              <span class="V4__rowLabel">Captured</span>
              <span class="V4__rowValue">{{ capturedAt }}</span>
            </div>
            <div class="V4__row">
              <span class="V4__rowLabel">Status</span>
              <span class="V4__rowValue">
                <USwitch
                  v-model="isCuratedDraft"
                  label="Curated"
                  size="xs"
                />
              </span>
            </div>
            <div class="V4__row V4__row--wide">
              <span class="V4__rowLabel">URL</span>
              <UInput
                v-model="urlDraft"
                size="xs"
                variant="outline"
                placeholder="example.com"
                class="V4__rowInput"
              />
            </div>
            <div class="V4__row V4__row--wide">
              <span class="V4__rowLabel">Notes</span>
              <UTextarea
                v-model="notesDraft"
                size="xs"
                variant="outline"
                placeholder="Why this is here"
                class="V4__rowInput"
                :rows="1"
                autoresize
              />
            </div>
            <div class="V4__row V4__row--id">
              <span class="V4__rowLabel">ID · Slug</span>
              <span class="V4__rowValue">
                <code>#{{ record.id }}</code>
                <code class="V4__slug">/{{ record.slug }}</code>
              </span>
            </div>
          </div>
        </div>
      </Transition>

      <h1 class="V4__title">{{ record.title }}</h1>

      <div class="V4__byline">
        <template v-if="creator">
          <span class="V4__bylineDim">by</span>
          <RouterLink
            class="V4__bylineLink"
            :to="`/${creator.slug}`"
          >
            {{ creator.title }}
          </RouterLink>
        </template>
        <span
          v-if="publishedAt"
          class="V4__bylineDim"
        >
          · {{ publishedAt }}
        </span>
        <span class="V4__bylineSpacer" />
        <RouterLink
          v-for="tag in tags"
          :key="tag.id"
          class="V4__tag"
          :to="`/${tag.slug}`"
        >
          #{{ tag.title || tag.slug }}
        </RouterLink>
      </div>

      <p
        v-if="record.summary"
        class="V4__lede"
      >
        {{ record.summary }}
      </p>

      <div class="V4__body">
        <MarkdownRender
          v-if="record.content"
          :source="record.content"
        />
        <div
          v-else
          class="V4__bodyEmpty"
        >
          <em>No body content yet.</em>
        </div>
      </div>
    </div>

    <div class="V4__linksDock">
      <div class="V4__linksDockInner">
        <div class="V4__linksTabRow">
          <button
            v-for="tab in linkTabs"
            :key="tab.key"
            type="button"
            class="V4__linksTab"
            :class="{ 'V4__linksTab--active': activeLinkTab === tab.key }"
            @click="activeLinkTab = tab.key"
          >
            <span class="V4__linksTabLabel">{{ tab.label }}</span>
            <span class="V4__linksTabCount">{{ tab.count }}</span>
          </button>
          <span class="V4__linksTabSep" />
          <UButton
            size="xs"
            color="neutral"
            variant="ghost"
            icon="i-lucide-plus"
            label="Add link"
          />
        </div>

        <ul class="V4__linksList">
          <li
            v-for="entry in activeEntries"
            :key="`${entry.kind}-${entry.id}`"
          >
            <RouterLink
              class="V4__linksItem"
              :to="`/${entry.slug}`"
            >
              <span class="V4__linksItemPred">{{ entry.predLabel }}</span>
              <span class="V4__linksItemTitle">{{ entry.title || entry.slug }}</span>
              <span
                v-if="entry.snippet"
                class="V4__linksItemSnip"
              >
                {{ entry.snippet }}
              </span>
              <span
                v-if="entry.host"
                class="V4__linksItemHost"
              >
                {{ entry.host }}
              </span>
            </RouterLink>
          </li>
          <li
            v-if="!activeEntries.length"
            class="V4__linksEmpty"
          >
            No links in this group yet.
          </li>
        </ul>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import MarkdownRender from '@app/components/MarkdownRender.vue';
import { capitalize, formatDate } from '@shared/lib/formatting';
import { computed, ref } from 'vue';
import { getIconForRecordType } from '@app/utils';
import { humanizePredicate, useLabRecord } from '../useLabRecord';

const { record, links } = useLabRecord();

const detailsOpen = ref(false);
const isCuratedDraft = ref(true);
const urlDraft = ref('');
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

interface LinkEntry {
  kind: 'out' | 'in';
  id: number;
  slug: string;
  title: string | null;
  predicate: string;
  predLabel: string;
  snippet?: string;
  host?: string;
}

const allEntries = computed<LinkEntry[]>(() => {
  const out = outgoing.value
    .filter((l) => l.predicate !== 'tagged_with')
    .map<LinkEntry>((l) => ({
      kind: 'out',
      id: l.targetId,
      slug: l.target.slug,
      title: l.target.title,
      predicate: l.predicate,
      predLabel: capitalize(humanizePredicate(l.predicate)),
      host: (l.target as { url?: string }).url
        ? getHost((l.target as { url: string }).url)
        : undefined,
    }));
  const inc = incoming.value
    .filter((l) => l.source)
    .map<LinkEntry>((l) => ({
      kind: 'in',
      id: l.sourceId,
      slug: l.source.slug,
      title: l.source.title,
      predicate: l.predicate,
      predLabel: 'Mentioned in',
      snippet: (l.source as { summary?: string }).summary ?? undefined,
    }));
  return [...out, ...inc];
});

const linkTabs = computed(() => {
  const counts = new Map<string, number>();
  for (const e of allEntries.value) {
    const key = e.kind === 'in' ? 'mentioned_in' : e.predicate;
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  const tabs: Array<{ key: string; label: string; count: number }> = [
    { key: 'all', label: 'All', count: allEntries.value.length },
  ];
  for (const [key, count] of counts) {
    tabs.push({
      key,
      label: key === 'mentioned_in' ? 'Mentioned in' : capitalize(humanizePredicate(key)),
      count,
    });
  }
  return tabs;
});

const activeLinkTab = ref<string>('all');
const activeEntries = computed(() => {
  if (activeLinkTab.value === 'all') return allEntries.value;
  if (activeLinkTab.value === 'mentioned_in')
    return allEntries.value.filter((e) => e.kind === 'in');
  return allEntries.value.filter((e) => e.predicate === activeLinkTab.value);
});

function getHost(url: string): string {
  try {
    return new URL(url).host.replace(/^www\./, '');
  } catch {
    return url;
  }
}
</script>

<style scoped>
.V4 {
  display: grid;
  grid-template-rows: 1fr auto;
  min-height: 100%;
  position: relative;
}

.V4__page {
  max-width: 740px;
  margin: 0 auto;
  width: 100%;
  padding: 0 8px 32px;
  display: grid;
  gap: 14px;
}

.V4__strip {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 0.78rem;
  color: var(--ui-text-muted);
  padding: 6px 0;
  border-bottom: 1px solid var(--ui-border);
}

.V4__stripIcon {
  width: 14px;
  height: 14px;
  color: var(--ui-text-dimmed);
}

.V4__stripType {
  font-weight: 500;
  color: var(--ui-text);
}

.V4__stripDot {
  color: var(--ui-text-dimmed);
}

.V4__stripUrl {
  display: inline-flex;
  align-items: center;
  gap: 2px;
  color: var(--ui-text);
  text-decoration: underline;
  text-decoration-color: var(--ui-text-dimmed);

  &:hover {
    color: var(--ui-primary);
  }
}

.V4__stripArrow {
  width: 10px;
  height: 10px;
  color: var(--ui-text-dimmed);
}

.V4__stripDate {
  color: var(--ui-text-dimmed);
}

.V4__stripDetails {
  margin-left: auto;
  display: inline-flex;
  align-items: center;
  gap: 4px;
  background: transparent;
  border: 0;
  font-size: 0.75rem;
  color: var(--ui-text-muted);
  cursor: pointer;
  padding: 2px 6px;
  border-radius: 4px;

  &:hover {
    background: var(--ui-bg-elevated);
    color: var(--ui-text);
  }
}

.V4__stripDetailsIcon {
  width: 12px;
  height: 12px;
}

.V4-fade-enter-active,
.V4-fade-leave-active {
  transition: opacity 0.12s ease, max-height 0.18s ease;
  max-height: 320px;
  overflow: hidden;
}

.V4-fade-enter-from,
.V4-fade-leave-to {
  opacity: 0;
  max-height: 0;
}

.V4__details {
  background: var(--ui-bg-elevated);
  border: 1px solid var(--ui-border);
  border-radius: var(--radius-lg);
  padding: 10px 12px;
}

.V4__detailsGrid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px 16px;
}

.V4__row {
  display: grid;
  grid-template-columns: 80px 1fr;
  align-items: baseline;
  gap: 8px;
  font-size: 0.8rem;
}

.V4__row--wide {
  grid-column: 1 / -1;
}

.V4__row--id {
  grid-column: 1 / -1;
  border-top: 1px dashed var(--ui-border);
  padding-top: 6px;
  margin-top: 2px;
}

.V4__rowLabel {
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--ui-text-dimmed);
}

.V4__rowValue {
  color: var(--ui-text);
  display: inline-flex;
  align-items: center;
  gap: 6px;
}

.V4__rowInput {
  font-size: 0.8rem;
}

.V4__slug {
  font-family: var(--font-mono, ui-monospace, monospace);
  color: var(--ui-text-dimmed);
  font-size: 0.7rem;
}

.V4__title {
  font-size: 2.5rem;
  line-height: 1.05;
  font-weight: 700;
  letter-spacing: -0.015em;
  text-wrap: balance;
  margin-top: 8px;
}

.V4__byline {
  display: inline-flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 6px;
  font-size: 0.85rem;
  color: var(--ui-text-muted);
}

.V4__bylineDim {
  color: var(--ui-text-dimmed);
}

.V4__bylineLink {
  font-weight: 500;
  color: var(--ui-text);

  &:hover {
    text-decoration: underline;
  }
}

.V4__bylineSpacer {
  flex: 0 0 8px;
}

.V4__tag {
  color: var(--ui-primary);
  font-size: 0.78rem;

  &:hover {
    text-decoration: underline;
  }
}

.V4__lede {
  font-size: 1.15rem;
  line-height: 1.5;
  color: var(--ui-text);
  margin: 8px 0 4px;
  font-weight: 400;
}

.V4__body {
  font-size: 1.05rem;
  line-height: 1.7;

  :deep(.MarkdownRender) {
    font-size: 1.05rem;
    line-height: 1.7;
  }
}

.V4__bodyEmpty {
  color: var(--ui-text-dimmed);
  padding: 8px 0;
}

.V4__linksDock {
  position: sticky;
  bottom: 0;
  background: var(--ui-bg-elevated);
  border-top: 1px solid var(--ui-border);
  margin-top: 24px;
  box-shadow: 0 -8px 24px rgba(0, 0, 0, 0.04);
}

.V4__linksDockInner {
  max-width: 880px;
  margin: 0 auto;
  padding: 8px 16px 16px;
  display: grid;
  gap: 6px;
}

.V4__linksTabRow {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  overflow-x: auto;
  padding-bottom: 2px;
}

.V4__linksTab {
  display: inline-flex;
  align-items: baseline;
  gap: 4px;
  background: transparent;
  border: 1px solid transparent;
  padding: 3px 10px;
  border-radius: 999px;
  font-size: 0.75rem;
  color: var(--ui-text-muted);
  cursor: pointer;
  white-space: nowrap;

  &:hover {
    background: var(--ui-bg);
    color: var(--ui-text);
  }
}

.V4__linksTab--active {
  background: var(--ui-bg);
  border-color: var(--ui-border);
  color: var(--ui-text);
  font-weight: 500;
}

.V4__linksTabCount {
  color: var(--ui-text-dimmed);
  font-size: 0.7rem;
}

.V4__linksTabSep {
  width: 1px;
  height: 16px;
  background: var(--ui-border);
  margin: 0 4px;
}

.V4__linksList {
  display: grid;
  gap: 1px;
  list-style: none;
  margin: 0;
  padding: 0;
  background: var(--ui-border);
  border-radius: var(--radius-lg);
  overflow: hidden;
  border: 1px solid var(--ui-border);
}

.V4__linksItem {
  display: grid;
  grid-template-columns: 110px 1fr auto;
  gap: 10px;
  align-items: baseline;
  padding: 8px 12px;
  background: var(--ui-bg);
  font-size: 0.85rem;
  color: var(--ui-text);
  position: relative;

  &:hover {
    background: var(--ui-bg-accented);
  }
}

.V4__linksItemPred {
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--ui-text-dimmed);
}

.V4__linksItemTitle {
  font-weight: 500;
}

.V4__linksItemSnip {
  grid-column: 2 / 3;
  font-size: 0.75rem;
  color: var(--ui-text-muted);
  display: -webkit-box;
  -webkit-line-clamp: 1;
  -webkit-box-orient: vertical;
  overflow: hidden;
  margin-top: 2px;
}

.V4__linksItemHost {
  font-size: 0.7rem;
  color: var(--ui-text-dimmed);
  font-family: var(--font-mono, ui-monospace, monospace);
}

.V4__linksEmpty {
  padding: 12px;
  background: var(--ui-bg);
  text-align: center;
  font-size: 0.8rem;
  color: var(--ui-text-dimmed);
  font-style: italic;
}
</style>
