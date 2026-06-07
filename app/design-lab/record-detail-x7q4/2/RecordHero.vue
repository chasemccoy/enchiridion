<template>
  <div
    v-if="record"
    class="Hero"
  >
    <div class="Hero__strip">
      <span class="Hero__stripGroup">
        <UIcon
          class="Hero__stripIcon"
          :name="getIconForRecordType(record.type)"
        />
        <span class="Hero__stripType">{{ capitalize(record.type) }}</span>
      </span>
      <span class="Hero__stripDot">·</span>
      <span class="Hero__stripGroup">
        <UIcon
          v-if="record.source"
          class="Hero__stripIcon"
          :name="getIconForRecordSource(record.source)"
        />
        <span>{{ record.source ? capitalize(record.source) : 'Manual' }}</span>
      </span>
      <span class="Hero__stripDot">·</span>
      <span class="Hero__stripDate">Captured {{ capturedAt }}</span>
      <span
        v-if="publishedAt"
        class="Hero__stripDot"
      >
        ·
      </span>
      <span
        v-if="publishedAt"
        class="Hero__stripDate"
      >
        published {{ publishedAt }}
      </span>

      <button
        type="button"
        class="Hero__detailsBtn"
        @click="detailsOpen = !detailsOpen"
      >
        <UIcon
          class="Hero__detailsIcon"
          :name="detailsOpen ? 'i-lucide-chevron-up' : 'i-lucide-sliders-horizontal'"
        />
        {{ detailsOpen ? 'Hide details' : 'Details' }}
      </button>
    </div>

    <Transition name="Hero-fade">
      <div
        v-if="detailsOpen"
        class="Hero__details"
      >
        <div class="Hero__detailsGrid">
          <label class="Hero__row">
            <span class="Hero__label">Slug</span>
            <UInput
              v-model="slugDraft"
              size="xs"
              variant="outline"
              class="Hero__rowInput"
            />
          </label>
          <label class="Hero__row">
            <span class="Hero__label">Published</span>
            <UInput
              v-model="publishedDraft"
              size="xs"
              variant="outline"
              placeholder="May 4, 1995"
              class="Hero__rowInput"
            />
          </label>
          <label class="Hero__row Hero__row--wide">
            <span class="Hero__label">Notes</span>
            <UTextarea
              v-model="notesDraft"
              size="xs"
              variant="outline"
              placeholder="Why this is here"
              class="Hero__rowInput"
              :rows="1"
              autoresize
            />
          </label>
          <div class="Hero__row Hero__row--meta">
            <span class="Hero__label">ID</span>
            <span class="Hero__mono">#{{ record.id }}</span>
            <USwitch
              v-model="isCuratedDraft"
              label="Curated"
              size="xs"
              class="Hero__switch"
            />
            <UButton
              size="xs"
              color="error"
              variant="ghost"
              icon="i-lucide-trash"
              label="Delete record"
              class="Hero__deleteBtn"
            />
          </div>
        </div>
      </div>
    </Transition>

    <h1 class="Hero__title">{{ record.title }}</h1>

    <div class="Hero__byline">
      <template v-if="creator">
        <span class="Hero__bylineDim">by</span>
        <RouterLink
          class="Hero__bylineLink"
          :to="`/${creator.slug}`"
        >
          {{ creator.title }}
        </RouterLink>
      </template>
      <span
        v-if="record.url"
        class="Hero__bylineSep"
      >
        ·
      </span>
      <a
        v-if="record.url"
        class="Hero__bylineUrl"
        target="_blank"
        :href="record.url"
      >
        <img
          v-if="favicon"
          alt=""
          class="Hero__favicon"
          width="14"
          height="14"
          :src="favicon"
        />
        {{ getHost(record.url) }}
        <UIcon
          name="i-lucide-arrow-up-right"
          class="Hero__bylineUrlIcon"
        />
      </a>
    </div>

    <div
      v-if="tags.length"
      class="Hero__tags"
    >
      <span class="Hero__tagsLabel">Tags</span>
      <ul class="Hero__tagList">
        <li
          v-for="tag in tags"
          :key="tag.id"
        >
          <RouterLink
            class="Hero__tag"
            :to="`/${tag.slug}`"
          >
            {{ tag.title || tag.slug }}
          </RouterLink>
        </li>
        <li>
          <button
            type="button"
            class="Hero__tagAdd"
          >
            <UIcon name="i-lucide-plus" />
            Add tag
          </button>
        </li>
      </ul>
    </div>

    <p
      v-if="record.summary"
      class="Hero__lede"
    >
      {{ record.summary }}
    </p>

    <div
      v-if="media.length"
      class="Hero__media"
    >
      <figure
        v-for="(att, idx) in media"
        :key="att.id || idx"
        class="Hero__mediaItem"
        :class="{ 'Hero__mediaItem--single': media.length === 1 }"
      >
        <img
          v-if="att.type === 'image'"
          loading="lazy"
          :src="getSrcForAttachmentUrl(att.url)"
          :alt="att.caption || ''"
        />
      </figure>
      <button
        type="button"
        class="Hero__mediaAdd"
      >
        <UIcon name="i-lucide-upload" />
        Add
      </button>
    </div>

    <div class="Hero__body">
      <MarkdownRender
        v-if="record.content"
        :source="record.content"
      />
      <div
        v-else
        class="Hero__bodyEmpty"
      >
        <em>No body content yet.</em> Click to write.
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import MarkdownRender from '@app/components/MarkdownRender.vue';
import { capitalize, formatDate } from '@shared/lib/formatting';
import { computed, ref } from 'vue';
import { getIconForRecordSource, getIconForRecordType } from '@app/utils';
import useApiClient from '@app/composables/useApiClient';

const { backendBaseUrl } = useApiClient();

function getSrcForAttachmentUrl(url: string) {
  if (url.startsWith('data:')) return url;
  return `${backendBaseUrl}${url}`;
}
import { useLabRecord } from '../useLabRecord';

const { record, links } = useLabRecord();

const detailsOpen = ref(false);
const slugDraft = computed({
  get: () => record.value?.slug ?? '',
  set: () => {},
});
const publishedDraft = ref('');
const notesDraft = ref('');
const isCuratedDraft = ref(true);

const capturedAt = computed(() =>
  record.value ? formatDate(record.value.recordCreatedAt) : null,
);
const publishedAt = computed(() =>
  record.value?.contentCreatedAt ? formatDate(record.value.contentCreatedAt) : null,
);

const outgoing = computed(() => links.value?.outgoingLinks ?? []);

const creator = computed(
  () => outgoing.value.find((l) => l.predicate === 'created_by')?.target ?? null,
);

const tags = computed(() =>
  outgoing.value
    .filter((l) => l.predicate === 'tagged_with')
    .map((l) => ({ id: l.targetId, slug: l.target.slug, title: l.target.title })),
);

const media = computed(() => record.value?.media ?? []);

const favicon = computed(() => {
  if (!record.value?.url) return null;
  try {
    const host = new URL(record.value.url).host;
    return `https://www.google.com/s2/favicons?domain=${host}&sz=32`;
  } catch {
    return null;
  }
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
.Hero {
  display: grid;
  gap: 14px;
}

.Hero__strip {
  display: inline-flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 6px;
  font-size: 0.78rem;
  color: var(--ui-text-muted);
  padding: 6px 0;
  border-bottom: 1px solid var(--ui-border);
}

.Hero__stripGroup {
  display: inline-flex;
  align-items: center;
  gap: 4px;
}

.Hero__stripIcon {
  width: 14px;
  height: 14px;
  color: var(--ui-text-dimmed);
}

.Hero__stripType {
  font-weight: 500;
  color: var(--ui-text);
}

.Hero__stripDot {
  color: var(--ui-text-dimmed);
}

.Hero__stripDate {
  color: var(--ui-text-dimmed);
}

.Hero__detailsBtn {
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

.Hero__detailsIcon {
  width: 12px;
  height: 12px;
}

.Hero-fade-enter-active,
.Hero-fade-leave-active {
  transition: opacity 0.12s ease, max-height 0.18s ease;
  max-height: 320px;
  overflow: hidden;
}

.Hero-fade-enter-from,
.Hero-fade-leave-to {
  opacity: 0;
  max-height: 0;
}

.Hero__details {
  background: var(--ui-bg-elevated);
  border: 1px solid var(--ui-border);
  border-radius: var(--radius-lg);
  padding: 10px 12px;
}

.Hero__detailsGrid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px 14px;
}

.Hero__row {
  display: grid;
  grid-template-columns: 80px 1fr;
  align-items: center;
  gap: 8px;
  font-size: 0.8rem;
}

.Hero__row--wide {
  grid-column: 1 / -1;
}

.Hero__row--meta {
  grid-column: 1 / -1;
  border-top: 1px dashed var(--ui-border);
  padding-top: 8px;
  margin-top: 2px;
  display: inline-flex;
  align-items: center;
  gap: 12px;
}

.Hero__label {
  font-size: 0.72rem;
  color: var(--ui-text-dimmed);
}

.Hero__rowInput {
  font-size: 0.8rem;
}

.Hero__mono {
  font-family: var(--font-mono, ui-monospace, monospace);
  color: var(--ui-text-dimmed);
  font-size: 0.78rem;
}

.Hero__switch {
  margin-left: auto;
}

.Hero__deleteBtn {
  margin-left: 8px;
}

.Hero__title {
  font-size: 2.1rem;
  line-height: 1.1;
  font-weight: 700;
  letter-spacing: -0.015em;
  text-wrap: balance;
  margin-top: 6px;
}

.Hero__byline {
  display: inline-flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 6px;
  font-size: 0.85rem;
  color: var(--ui-text-muted);
}

.Hero__bylineDim {
  color: var(--ui-text-dimmed);
}

.Hero__bylineLink {
  font-weight: 500;
  color: var(--ui-text);

  &:hover {
    text-decoration: underline;
  }
}

.Hero__bylineSep {
  color: var(--ui-text-dimmed);
}

.Hero__bylineUrl {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  color: var(--ui-text);
  font-weight: 500;
  text-decoration: underline;
  text-decoration-color: var(--ui-text-dimmed);
  text-underline-offset: 2px;

  &:hover {
    color: var(--ui-primary);
    text-decoration-color: currentColor;
  }
}

.Hero__favicon {
  border-radius: 2px;
}

.Hero__bylineUrlIcon {
  width: 11px;
  height: 11px;
  color: var(--ui-text-dimmed);
}

.Hero__tags {
  display: inline-flex;
  align-items: baseline;
  gap: 8px;
  flex-wrap: wrap;
}

.Hero__tagsLabel {
  font-size: 0.72rem;
  color: var(--ui-text-dimmed);
}

.Hero__tagList {
  display: inline-flex;
  flex-wrap: wrap;
  gap: 4px;
  list-style: none;
  margin: 0;
  padding: 0;
}

.Hero__tag {
  display: inline-flex;
  align-items: center;
  padding: 2px 8px;
  border-radius: 999px;
  background: var(--ui-bg);
  border: 1px solid var(--ui-border);
  font-size: 0.75rem;
  color: var(--ui-text);

  &:hover {
    background: var(--ui-bg-elevated);
    color: var(--ui-primary);
  }
}

.Hero__tagAdd {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  background: transparent;
  border: 1px dashed var(--ui-border);
  padding: 2px 8px;
  border-radius: 999px;
  font-size: 0.7rem;
  color: var(--ui-text-dimmed);
  cursor: pointer;

  &:hover {
    color: var(--ui-text);
    border-color: var(--ui-border-accented);
  }
}

.Hero__lede {
  font-size: 1.05rem;
  line-height: 1.55;
  color: var(--ui-text);
  margin: 4px 0 0;
}

.Hero__media {
  display: flex;
  gap: 6px;
  margin: 8px 0 4px;
  flex-wrap: wrap;
}

.Hero__mediaItem {
  margin: 0;
  border-radius: var(--radius-md);
  overflow: hidden;
  background: var(--ui-bg-elevated);
  border: 1px solid var(--ui-border);
  flex: 1 1 240px;
  min-width: 220px;
  max-width: 360px;
}

.Hero__mediaItem img {
  display: block;
  width: 100%;
  height: 180px;
  object-fit: cover;
}

.Hero__mediaItem--single {
  flex-basis: 100%;
  max-width: 100%;
}

.Hero__mediaItem--single img {
  height: 280px;
}

.Hero__mediaAdd {
  display: inline-flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 4px;
  width: 96px;
  height: 96px;
  align-self: center;
  background: transparent;
  border: 1px dashed var(--ui-border);
  border-radius: var(--radius-md);
  color: var(--ui-text-dimmed);
  font-size: 0.7rem;
  cursor: pointer;

  &:hover {
    color: var(--ui-text);
    border-color: var(--ui-border-accented);
  }
}

.Hero__body {
  font-size: 1rem;
  line-height: 1.65;
  margin-top: 4px;

  :deep(.MarkdownRender) {
    font-size: 1rem;
    line-height: 1.65;
  }

  :deep(.MarkdownRender p) {
    margin-bottom: 0.8em;
  }
}

.Hero__bodyEmpty {
  color: var(--ui-text-dimmed);
  padding: 8px 0;
}
</style>
