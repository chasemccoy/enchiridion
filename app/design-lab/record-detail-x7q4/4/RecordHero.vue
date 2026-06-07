<template>
  <div
    v-if="record"
    class="Hero"
  >
    <div class="Hero__strip">
      <span class="Hero__typeChip">
        <UIcon
          class="Hero__typeIcon"
          :name="getIconForRecordType(typeDraft)"
        />
        {{ capitalize(typeDraft) }}
      </span>

      <template v-if="showSource">
        <span class="Hero__dot">·</span>
        <span class="Hero__stripItem">
          <UIcon
            class="Hero__stripIcon"
            :name="getIconForRecordSource(record.source)"
          />
          {{ capitalize(record.source) }}
        </span>
      </template>

      <span class="Hero__dot">·</span>
      <span class="Hero__stripDate">Captured {{ capturedAt }}</span>
      <template v-if="publishedAt">
        <span class="Hero__dot">·</span>
        <span class="Hero__stripDate">published {{ publishedAt }}</span>
      </template>

      <button
        type="button"
        class="Hero__detailsBtn"
        :class="{ 'Hero__detailsBtn--active': detailsOpen }"
        @click="detailsOpen = !detailsOpen"
      >
        <UIcon
          class="Hero__detailsIcon"
          :name="detailsOpen ? 'i-lucide-chevron-up' : 'i-lucide-sliders-horizontal'"
        />
        {{ detailsOpen ? 'Done' : 'Edit details' }}
      </button>
    </div>

    <Transition name="Hero-fade">
      <div
        v-if="detailsOpen"
        class="Hero__panel"
      >
        <div class="Hero__panelGrid">
          <div class="Hero__field Hero__field--wide">
            <span class="Hero__fieldLabel">Type</span>
            <div class="Hero__typeSeg">
              <button
                v-for="opt in typeOptions"
                :key="opt.value"
                type="button"
                class="Hero__typeSegBtn"
                :class="{ 'Hero__typeSegBtn--active': typeDraft === opt.value }"
                @click="typeDraft = opt.value"
              >
                <UIcon
                  class="Hero__typeSegIcon"
                  :name="opt.icon"
                />
                {{ opt.label }}
              </button>
            </div>
          </div>

          <label class="Hero__field Hero__field--wide">
            <span class="Hero__fieldLabel">URL</span>
            <UInput
              v-model="urlDraft"
              size="xs"
              variant="outline"
              placeholder="example.com"
              icon="i-lucide-link"
              class="Hero__fieldInput"
            />
          </label>

          <label class="Hero__field">
            <span class="Hero__fieldLabel">Published</span>
            <UInput
              v-model="publishedDraft"
              size="xs"
              variant="outline"
              placeholder="May 4, 1995"
              class="Hero__fieldInput"
            />
          </label>
          <label class="Hero__field">
            <span class="Hero__fieldLabel">Slug</span>
            <UInput
              size="xs"
              variant="outline"
              class="Hero__fieldInput"
              :modelValue="record.slug"
            />
          </label>

          <label class="Hero__field Hero__field--wide">
            <span class="Hero__fieldLabel">Notes</span>
            <UTextarea
              v-model="notesDraft"
              size="xs"
              variant="outline"
              placeholder="Why this is here"
              class="Hero__fieldInput"
              :rows="1"
              autoresize
            />
          </label>

          <div class="Hero__panelFooter">
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
        <span
          v-if="record.url"
          class="Hero__dot"
        >
          ·
        </span>
      </template>
      <LinkWithFavicon
        v-if="record.url"
        class="Hero__bylineUrl"
        :modelValue="record.url"
      />
    </div>

    <div class="Hero__tags">
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
          :src="srcFor(att.url)"
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
import LinkWithFavicon from '@app/components/LinkWithFavicon.vue';
import { capitalize, formatDate } from '@shared/lib/formatting';
import { computed, ref, watch } from 'vue';
import { getIconForRecordSource, getIconForRecordType } from '@app/utils';
import { recordTypeEnum, type RecordType } from '@shared/types';
import useApiClient from '@app/composables/useApiClient';
import { useLabRecord } from '../useLabRecord';

const { record, links } = useLabRecord();
const { backendBaseUrl } = useApiClient();

const detailsOpen = ref(false);
const typeDraft = ref<RecordType>('artifact');
const urlDraft = ref('');
const publishedDraft = ref('');
const notesDraft = ref('');
const isCuratedDraft = ref(true);

watch(
  record,
  (r) => {
    if (!r) return;
    typeDraft.value = r.type as RecordType;
    urlDraft.value = r.url ?? '';
  },
  { immediate: true },
);

const typeOptions = [...recordTypeEnum].sort().map((type) => ({
  value: type,
  label: capitalize(type),
  icon: getIconForRecordType(type),
}));

const capturedAt = computed(() =>
  record.value ? formatDate(record.value.recordCreatedAt) : null,
);
const publishedAt = computed(() =>
  record.value?.contentCreatedAt ? formatDate(record.value.contentCreatedAt) : null,
);

const showSource = computed(
  () => record.value?.source === 'readwise' || record.value?.source === 'twitter',
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

function srcFor(url: string) {
  if (url.startsWith('data:')) return url;
  return `${backendBaseUrl}${url}`;
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

.Hero__typeChip {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-weight: 500;
  color: var(--ui-text);
  font-size: 0.78rem;
}

.Hero__typeIcon {
  width: 14px;
  height: 14px;
  color: var(--ui-text-dimmed);
}

.Hero__dot {
  color: var(--ui-text-dimmed);
}

.Hero__stripItem {
  display: inline-flex;
  align-items: center;
  gap: 4px;
}

.Hero__stripIcon {
  width: 14px;
  height: 14px;
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
  padding: 2px 8px;
  border-radius: 999px;

  &:hover {
    background: var(--ui-bg-elevated);
    color: var(--ui-text);
  }
}

.Hero__detailsBtn--active {
  background: var(--ui-bg-elevated);
  color: var(--ui-text);
}

.Hero__detailsIcon {
  width: 12px;
  height: 12px;
}

.Hero-fade-enter-active,
.Hero-fade-leave-active {
  transition: opacity 0.12s ease, max-height 0.2s ease;
  max-height: 360px;
  overflow: hidden;
}

.Hero-fade-enter-from,
.Hero-fade-leave-to {
  opacity: 0;
  max-height: 0;
}

/* Lighter than a filled card — a bordered region with a faint accent edge so
   it reads as a temporary "edit" surface, not a heavy panel. */
.Hero__panel {
  background: transparent;
  border: 1px solid var(--ui-border);
  border-left: 2px solid var(--ui-border-accented);
  border-radius: var(--radius-lg);
  padding: 12px 14px;
}

.Hero__panelGrid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px 14px;
}

.Hero__field {
  display: grid;
  gap: 4px;
}

.Hero__field--wide {
  grid-column: 1 / -1;
}

.Hero__fieldLabel {
  font-size: 0.72rem;
  color: var(--ui-text-dimmed);
}

/* Compact segmented control — much smaller than the full UTabs. */
.Hero__typeSeg {
  display: inline-flex;
  gap: 2px;
  padding: 2px;
  background: var(--ui-bg-elevated);
  border: 1px solid var(--ui-border);
  border-radius: var(--radius-md);
  width: fit-content;
}

.Hero__typeSegBtn {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 3px 10px;
  border: 0;
  background: transparent;
  border-radius: calc(var(--radius-md) - 2px);
  font-size: 0.78rem;
  color: var(--ui-text-muted);
  cursor: pointer;
  transition: background 0.1s ease, color 0.1s ease;

  &:hover {
    color: var(--ui-text);
  }
}

.Hero__typeSegBtn--active {
  background: var(--ui-bg);
  color: var(--ui-text);
  font-weight: 500;
  box-shadow: var(--ui-shadow-sm, 0 1px 2px rgba(0, 0, 0, 0.06));
}

.Hero__typeSegIcon {
  width: 13px;
  height: 13px;
}

.Hero__panelFooter {
  grid-column: 1 / -1;
  display: inline-flex;
  align-items: center;
  gap: 12px;
  border-top: 1px dashed var(--ui-border);
  padding-top: 10px;
  margin-top: 2px;
}

.Hero__mono {
  font-family: var(--font-mono, ui-monospace, monospace);
  color: var(--ui-text-dimmed);
  font-size: 0.78rem;
}

.Hero__switch {
  margin-left: auto;
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

.Hero__bylineUrl {
  font-size: 0.85rem;
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
