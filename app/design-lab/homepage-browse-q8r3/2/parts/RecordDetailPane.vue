<template>
  <article
    v-if="record"
    class="rd"
  >
    <header class="rd__head">
      <button
        type="button"
        class="rd__close"
        @click="$emit('close')"
      >
        <UIcon name="i-lucide-x" />
      </button>
      <span class="rd__kind">
        <UIcon
          class="rd__kindGlyph"
          :name="icon"
        />
        {{ capitalize(record.type) }}
      </span>
    </header>

    <h1 class="rd__title">{{ record.title }}</h1>

    <p
      v-if="byline"
      class="rd__byline"
    >
      {{ byline }}
    </p>

    <img
      v-if="image"
      class="rd__image"
      :src="image"
      :alt="record.title ?? ''"
    />

    <MarkdownRender
      v-if="record.content"
      class="rd__content"
      :source="record.content"
    />
    <p
      v-else-if="record.summary"
      class="rd__summary"
    >
      {{ record.summary }}
    </p>

    <div
      v-if="tags.length"
      class="rd__tags"
    >
      <button
        v-for="t in tags"
        :key="t!.slug"
        type="button"
        class="rd__tag"
        @click="$emit('selectConcept', t!.slug)"
      >
        #{{ t!.title }}
      </button>
    </div>

    <section
      v-if="links.length"
      class="rd__links"
    >
      <h2 class="rd__linksHead">Linked</h2>
      <button
        v-for="l in links"
        :key="`${l.predicate}-${l.target.slug}`"
        type="button"
        class="rd__link"
        @click="$emit('selectRecord', l.target.slug)"
      >
        <span class="rd__linkPred">{{ predicateLabel(l.predicate) }}</span>
        <span class="rd__linkTitle">{{ l.target.title ?? l.target.slug }}</span>
        <UIcon
          name="i-lucide-arrow-up-right"
          class="rd__linkGlyph"
        />
      </button>
    </section>
  </article>
</template>

<script setup lang="ts">
import MarkdownRender from '@app/components/MarkdownRender.vue';
import useApiClient from '@app/composables/useApiClient';
import { getIconForRecordType } from '@app/utils';
import { capitalize } from '@shared/lib/formatting';
import { computed } from 'vue';
import { bylineParts, firstImage, tagsOf, type LabRecord } from '../../useLabRecords';

defineEmits<{ close: []; selectConcept: [slug: string]; selectRecord: [slug: string] }>();
const props = defineProps<{ record: LabRecord | null }>();
const { backendBaseUrl } = useApiClient();

const icon = computed(() => (props.record ? getIconForRecordType(props.record.type) : ''));
const byline = computed(() => (props.record ? bylineParts(props.record).join(' · ') : ''));
const tags = computed(() => (props.record ? tagsOf(props.record) : []));
const image = computed(() => {
  if (!props.record) return null;
  const path = firstImage(props.record);
  return path ? `${backendBaseUrl}${path}` : null;
});
const links = computed(() =>
  (props.record?.outgoingLinks ?? []).filter((l) => l.target?.slug && l.target?.title),
);

function predicateLabel(slug: string) {
  return slug.replace(/_/g, ' ');
}
</script>

<style scoped>
.rd {
  max-width: 640px;
  margin: 0 auto;
  padding: 1.5rem 0.5rem 4rem;
}
.rd__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 1rem;
}
.rd__close {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border-radius: 999px;
  border: 1px solid var(--ui-border);
  background: var(--ui-bg);
  color: var(--ui-text-muted);
  cursor: pointer;
}
.rd__close:hover {
  background: var(--ui-bg-elevated);
  color: var(--ui-text);
}
.rd__kind {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 0.66rem;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  font-weight: 600;
  color: var(--ui-primary);
}
.rd__kindGlyph {
  width: 13px;
  height: 13px;
}
.rd__title {
  font-family: var(--font-serif);
  font-size: 1.9rem;
  font-weight: 600;
  line-height: 1.12;
  letter-spacing: -0.015em;
  color: var(--ui-text-highlighted);
}
.rd__byline {
  margin-top: 8px;
  font-size: 0.72rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--ui-text-muted);
}
.rd__image {
  width: 100%;
  max-height: 320px;
  object-fit: cover;
  object-position: 50% 30%;
  border-radius: var(--radius-md);
  margin-top: 1.25rem;
}
.rd__content,
.rd__summary {
  margin-top: 1.25rem;
  font-size: 0.95rem;
  line-height: 1.6;
  color: var(--ui-text-toned);
}
.rd__summary {
  white-space: pre-wrap;
}
.rd__tags {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin-top: 1.5rem;
}
.rd__tag {
  padding: 3px 10px;
  border-radius: 999px;
  border: 1px solid var(--ui-border);
  background: var(--ui-bg);
  font-size: 0.75rem;
  color: var(--ui-text-muted);
  cursor: pointer;
}
.rd__tag:hover {
  border-color: var(--ui-primary);
  color: var(--ui-primary);
}
.rd__links {
  margin-top: 2rem;
  border-top: 1px solid var(--ui-border);
  padding-top: 1rem;
  display: grid;
  gap: 2px;
}
.rd__linksHead {
  font-size: 0.66rem;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  color: var(--ui-text-dimmed);
  margin-bottom: 6px;
}
.rd__link {
  display: grid;
  grid-template-columns: 120px minmax(0, 1fr) auto;
  align-items: center;
  gap: 10px;
  padding: 6px 8px;
  border: 0;
  border-radius: var(--radius-md);
  background: transparent;
  cursor: pointer;
  text-align: left;
}
.rd__link:hover {
  background: var(--ui-bg-elevated);
}
.rd__linkPred {
  font-size: 0.64rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--ui-text-dimmed);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.rd__linkTitle {
  font-size: 0.82rem;
  color: var(--ui-text-toned);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.rd__link:hover .rd__linkTitle {
  color: var(--ui-primary);
}
.rd__linkGlyph {
  width: 13px;
  height: 13px;
  color: var(--ui-text-dimmed);
}
</style>
