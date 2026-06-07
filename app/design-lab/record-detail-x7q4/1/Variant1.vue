<template>
  <div
    v-if="record"
    class="V1"
  >
    <div class="V1__column">
      <div class="V1__head">
        <div class="V1__crumb">
          <UIcon
            class="V1__crumbIcon"
            :name="getIconForRecordType(record.type)"
          />
          <span>{{ capitalize(record.type) }}</span>
          <span v-if="record.source && record.source !== 'manual'">
            · captured from {{ capitalize(record.source) }}
          </span>
          <span v-if="capturedAt"> · {{ capturedAt }}</span>
        </div>

        <h1 class="V1__title">{{ record.title }}</h1>

        <p
          v-if="record.summary"
          class="V1__deck"
        >
          {{ record.summary }}
        </p>

        <div class="V1__byline">
          <template v-if="creator">
            <RouterLink
              class="V1__bylineLink"
              :to="`/${creator.slug}`"
            >
              {{ creator.title }}
            </RouterLink>
          </template>
          <span
            v-if="record.url"
            class="V1__bylineUrl"
          >
            <LinkWithFavicon :modelValue="record.url" />
          </span>
          <span
            v-if="publishedAt"
            class="V1__byPublished"
          >
            · published {{ publishedAt }}
          </span>
        </div>
      </div>

      <div class="V1__content">
        <MarkdownRender
          v-if="record.content"
          :source="record.content"
        />
        <div
          v-else
          class="V1__empty"
        >
          No body content yet. Click to start writing.
        </div>
      </div>
    </div>

    <aside class="V1__rail">
      <section class="V1__panel">
        <header class="V1__panelHeader">
          <span>Details</span>
          <button
            type="button"
            class="V1__editToggle"
            @click="editMode = !editMode"
          >
            {{ editMode ? 'Done' : 'Edit' }}
          </button>
        </header>
        <dl class="V1__dl">
          <div class="V1__dlRow">
            <dt>Type</dt>
            <dd>
              <UBadge
                color="neutral"
                variant="soft"
                size="sm"
                :icon="getIconForRecordType(record.type)"
              >
                {{ capitalize(record.type) }}
              </UBadge>
            </dd>
          </div>
          <div
            v-if="record.source"
            class="V1__dlRow"
          >
            <dt>Source</dt>
            <dd>{{ capitalize(record.source) }}</dd>
          </div>
          <div class="V1__dlRow">
            <dt>Captured</dt>
            <dd>{{ capturedAt }}</dd>
          </div>
          <div
            v-if="publishedAt"
            class="V1__dlRow"
          >
            <dt>Published</dt>
            <dd>{{ publishedAt }}</dd>
          </div>
          <div class="V1__dlRow V1__dlRow--editable">
            <dt>URL</dt>
            <dd v-if="!editMode">
              <LinkWithFavicon
                v-if="record.url"
                :modelValue="record.url"
              />
              <span
                v-else
                class="V1__placeholder"
              >
                —
              </span>
            </dd>
            <dd v-else>
              <UInput
                v-model="urlDraft"
                size="xs"
                variant="outline"
                placeholder="example.com"
              />
            </dd>
          </div>
          <div class="V1__dlRow V1__dlRow--editable">
            <dt>Notes</dt>
            <dd v-if="!editMode">
              <span v-if="record.notes">{{ record.notes }}</span>
              <span
                v-else
                class="V1__placeholder"
              >
                —
              </span>
            </dd>
            <dd v-else>
              <UTextarea
                v-model="notesDraft"
                size="xs"
                variant="outline"
                placeholder="Additional notes"
                :rows="1"
                autoresize
              />
            </dd>
          </div>
          <div class="V1__dlRow">
            <dt>ID</dt>
            <dd class="V1__dlMono">#{{ record.id }}</dd>
          </div>
        </dl>
      </section>

      <section
        v-for="group in linkGroups"
        :key="group.predicate"
        class="V1__panel"
      >
        <header class="V1__panelHeader">
          <span>{{ capitalize(humanizePredicate(group.predicate)) }}</span>
          <span class="V1__panelCount">{{ group.items.length }}</span>
        </header>
        <ul class="V1__chipList">
          <li
            v-for="item in group.items"
            :key="item.id"
          >
            <RouterLink
              class="V1__chip"
              :to="`/${item.slug}`"
            >
              <UIcon
                v-if="item.type"
                class="V1__chipIcon"
                :name="getIconForRecordType(item.type)"
              />
              <span class="V1__chipLabel">{{ item.title || item.slug }}</span>
            </RouterLink>
          </li>
          <li>
            <button
              type="button"
              class="V1__chipAdd"
            >
              <UIcon name="i-lucide-plus" />
              <span>Add</span>
            </button>
          </li>
        </ul>
      </section>

      <section
        v-if="incomingChildren.length"
        class="V1__panel"
      >
        <header class="V1__panelHeader">
          <span>Mentioned in</span>
          <span class="V1__panelCount">{{ incomingChildren.length }}</span>
        </header>
        <ul class="V1__refList">
          <li
            v-for="child in incomingChildren"
            :key="child.id"
          >
            <RouterLink
              class="V1__ref"
              :to="`/${child.slug}`"
            >
              <span class="V1__refTitle">
                {{ child.title || `#${child.id}` }}
              </span>
              <span
                v-if="child.summary"
                class="V1__refSnip"
              >
                {{ child.summary }}
              </span>
            </RouterLink>
          </li>
        </ul>
      </section>
    </aside>
  </div>
</template>

<script setup lang="ts">
import LinkWithFavicon from '@app/components/LinkWithFavicon.vue';
import MarkdownRender from '@app/components/MarkdownRender.vue';
import { capitalize, formatDate } from '@shared/lib/formatting';
import { computed, ref } from 'vue';
import { getIconForRecordType } from '@app/utils';
import { humanizePredicate, useLabRecord } from '../useLabRecord';

const { record, links } = useLabRecord();

const editMode = ref(false);
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

const linkGroups = computed(() => {
  const groups = new Map<string, Array<{ id: number; slug: string; title: string | null; type?: string }>>();
  for (const link of outgoing.value) {
    if (!groups.has(link.predicate)) groups.set(link.predicate, []);
    groups.get(link.predicate)!.push({
      id: link.targetId,
      slug: link.target.slug,
      title: link.target.title,
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
</script>

<style scoped>
.V1 {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 320px;
  gap: 48px;
  max-width: 1200px;
  margin: 0 auto;
  padding: 8px 8px 48px;
}

.V1__column {
  display: grid;
  gap: 24px;
}

.V1__head {
  display: grid;
  gap: 12px;
}

.V1__crumb {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--ui-text-dimmed);
}

.V1__crumbIcon {
  width: 12px;
  height: 12px;
}

.V1__title {
  font-size: 2.25rem;
  line-height: 1.15;
  font-weight: 600;
  text-wrap: balance;
  letter-spacing: -0.01em;
}

.V1__deck {
  font-size: 1.05rem;
  line-height: 1.5;
  color: var(--ui-text-muted);
  max-width: 60ch;
  text-wrap: pretty;
}

.V1__byline {
  display: inline-flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  font-size: 0.85rem;
  color: var(--ui-text-muted);
}

.V1__bylineLink {
  font-weight: 500;
  color: var(--ui-text);

  &:hover {
    text-decoration: underline;
  }
}

.V1__byPublished {
  color: var(--ui-text-dimmed);
}

.V1__content {
  font-size: 1rem;
  line-height: 1.65;
  max-width: 68ch;

  :deep(.MarkdownRender) {
    font-size: 1.05rem;
    line-height: 1.65;
  }
}

.V1__empty {
  color: var(--ui-text-dimmed);
  font-style: italic;
  padding: 8px 0;
}

.V1__rail {
  display: grid;
  gap: 14px;
  position: sticky;
  top: 8px;
  align-self: start;
  max-height: calc(100vh - 16px);
  overflow-y: auto;
  padding: 4px;
}

.V1__panel {
  border: 1px solid var(--ui-border);
  border-radius: var(--radius-lg);
  background: var(--ui-bg);
  padding: 10px 12px 12px;
}

.V1__panelHeader {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--ui-text-dimmed);
  margin-bottom: 8px;
}

.V1__panelCount {
  color: var(--ui-text-dimmed);
  font-weight: 500;
}

.V1__editToggle {
  font-size: 0.65rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--ui-primary);
  background: none;
  border: 0;
  padding: 0;
  cursor: pointer;
}

.V1__dl {
  display: grid;
  gap: 6px;
}

.V1__dlRow {
  display: grid;
  grid-template-columns: 78px 1fr;
  gap: 8px;
  align-items: baseline;
  font-size: 0.8rem;
}

.V1__dlRow dt {
  color: var(--ui-text-dimmed);
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.V1__dlRow dd {
  color: var(--ui-text);
  min-width: 0;
  word-break: break-word;
}

.V1__dlRow--editable dd:hover {
  background: var(--ui-bg-elevated);
  border-radius: 4px;
  margin-inline: -4px;
  padding-inline: 4px;
}

.V1__placeholder {
  color: var(--ui-text-dimmed);
}

.V1__dlMono {
  font-family: var(--font-mono, ui-monospace, monospace);
  color: var(--ui-text-dimmed);
  font-size: 0.75rem;
}

.V1__chipList {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
  list-style: none;
  margin: 0;
  padding: 0;
}

.V1__chip {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 3px 8px;
  border-radius: 999px;
  background: var(--ui-bg-elevated);
  font-size: 0.75rem;
  color: var(--ui-text);
  border: 1px solid var(--ui-border);

  &:hover {
    background: var(--ui-bg-accented);
  }
}

.V1__chipIcon {
  width: 10px;
  height: 10px;
  color: var(--ui-text-dimmed);
}

.V1__chipAdd {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  padding: 3px 8px;
  border-radius: 999px;
  background: transparent;
  font-size: 0.7rem;
  color: var(--ui-text-dimmed);
  border: 1px dashed var(--ui-border);
  cursor: pointer;

  &:hover {
    color: var(--ui-text);
    border-color: var(--ui-border-accented);
  }
}

.V1__refList {
  display: grid;
  gap: 6px;
  list-style: none;
  margin: 0;
  padding: 0;
}

.V1__ref {
  display: grid;
  gap: 2px;
  padding: 6px 8px;
  border-radius: var(--radius-md);
  background: var(--ui-bg-elevated);

  &:hover {
    background: var(--ui-bg-accented);
  }
}

.V1__refTitle {
  font-size: 0.8rem;
  font-weight: 500;
  color: var(--ui-text);
}

.V1__refSnip {
  font-size: 0.7rem;
  color: var(--ui-text-muted);
  line-height: 1.3;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
</style>
