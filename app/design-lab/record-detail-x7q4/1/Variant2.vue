<template>
  <div
    v-if="record"
    class="V2"
  >
    <div class="V2__page">
      <div class="V2__titleRow">
        <h1 class="V2__title">{{ record.title }}</h1>
        <UButton
          size="xs"
          color="neutral"
          variant="ghost"
          icon="i-lucide-more-horizontal"
        />
      </div>
      <div class="V2__slug">/{{ record.slug }}</div>

      <section class="V2__dossier">
        <div class="V2__dossierGrid">
          <div class="V2__field">
            <span class="V2__label">Type</span>
            <span class="V2__value">
              <UBadge
                color="neutral"
                variant="soft"
                size="sm"
                :icon="getIconForRecordType(record.type)"
              >
                {{ capitalize(record.type) }}
              </UBadge>
            </span>
          </div>
          <div class="V2__field">
            <span class="V2__label">Source</span>
            <span
              v-if="record.source"
              class="V2__value"
            >
              <UIcon
                class="V2__valueIcon"
                :name="getIconForRecordSource(record.source)"
              />
              {{ capitalize(record.source) }}
            </span>
            <span
              v-else
              class="V2__value V2__value--muted"
            >
              Manual
            </span>
          </div>
          <div class="V2__field">
            <span class="V2__label">Published</span>
            <span class="V2__value">
              {{ publishedAt || '—' }}
            </span>
          </div>
          <div class="V2__field">
            <span class="V2__label">Captured</span>
            <span class="V2__value">{{ capturedAt }}</span>
          </div>

          <div class="V2__field V2__field--wide">
            <span class="V2__label">URL</span>
            <span class="V2__value V2__value--url">
              <LinkWithFavicon
                v-if="record.url"
                :modelValue="record.url"
              />
              <UButton
                v-if="record.url"
                size="xs"
                color="neutral"
                variant="ghost"
                icon="i-lucide-external-link"
                target="_blank"
                :to="record.url"
              />
            </span>
          </div>

          <div class="V2__field V2__field--wide">
            <span class="V2__label">Tags</span>
            <span class="V2__value V2__value--chips">
              <RouterLink
                v-for="tag in tags"
                :key="tag.id"
                class="V2__tag"
                :to="`/${tag.slug}`"
              >
                #{{ tag.title || tag.slug }}
              </RouterLink>
              <button
                type="button"
                class="V2__tagAdd"
              >
                + Add
              </button>
            </span>
          </div>

          <div class="V2__field V2__field--span2">
            <span class="V2__label">Notes</span>
            <UTextarea
              v-model="notesDraft"
              size="sm"
              variant="ghost"
              placeholder="Add a note"
              :rows="1"
              :ui="{ base: 'V2__notesInput' }"
              autoresize
            />
          </div>
        </div>

        <div class="V2__dossierFooter">
          <UButton
            size="xs"
            color="neutral"
            variant="ghost"
            icon="i-lucide-link-2"
            label="Add link"
          />
          <UButton
            size="xs"
            color="neutral"
            variant="ghost"
            icon="i-lucide-paperclip"
            label="Attach"
          />
          <USeparator
            orientation="vertical"
            class="V2__sep"
          />
          <USwitch
            v-model="isCuratedDraft"
            label="Curated"
            size="xs"
            class="V2__switch"
          />
          <span class="V2__id">#{{ record.id }}</span>
        </div>
      </section>

      <section class="V2__summary">
        <p>{{ record.summary }}</p>
      </section>

      <section class="V2__content">
        <MarkdownRender
          v-if="record.content"
          :source="record.content"
        />
        <div
          v-else
          class="V2__contentPlaceholder"
        >
          Tap to write more about this record…
        </div>
      </section>

      <section class="V2__links">
        <header class="V2__linksHeader">
          <h2>Links</h2>
          <UButton
            size="xs"
            color="neutral"
            variant="ghost"
            icon="i-lucide-plus"
            label="New link"
          />
        </header>

        <div class="V2__linkGroups">
          <div
            v-for="group in linkGroups"
            :key="group.predicate"
            class="V2__linkGroup"
          >
            <div class="V2__linkGroupLabel">
              <span>{{ capitalize(humanizePredicate(group.predicate)) }}</span>
              <span class="V2__linkGroupCount">{{ group.items.length }}</span>
            </div>
            <ul class="V2__linkRow">
              <li
                v-for="item in group.items"
                :key="item.id"
              >
                <RouterLink
                  class="V2__linkChip"
                  :to="`/${item.slug}`"
                >
                  <UIcon
                    v-if="item.icon"
                    class="V2__linkChipIcon"
                    :name="item.icon"
                  />
                  <span>{{ item.title || item.slug }}</span>
                  <span
                    v-if="item.url"
                    class="V2__linkChipUrl"
                  >
                    {{ getHost(item.url) }}
                  </span>
                </RouterLink>
              </li>
            </ul>
          </div>

          <div
            v-if="incomingChildren.length"
            class="V2__linkGroup"
          >
            <div class="V2__linkGroupLabel">
              <span>Mentioned in</span>
              <span class="V2__linkGroupCount">{{ incomingChildren.length }}</span>
            </div>
            <ul class="V2__incomingList">
              <li
                v-for="child in incomingChildren"
                :key="child.id"
              >
                <RouterLink
                  class="V2__incoming"
                  :to="`/${child.slug}`"
                >
                  <span class="V2__incomingTitle">
                    {{ child.title || `#${child.id}` }}
                  </span>
                  <span
                    v-if="child.summary"
                    class="V2__incomingSnip"
                  >
                    {{ child.summary }}
                  </span>
                </RouterLink>
              </li>
            </ul>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>

<script setup lang="ts">
import LinkWithFavicon from '@app/components/LinkWithFavicon.vue';
import MarkdownRender from '@app/components/MarkdownRender.vue';
import { capitalize, formatDate } from '@shared/lib/formatting';
import { computed, ref } from 'vue';
import { getIconForRecordSource, getIconForRecordType } from '@app/utils';
import { humanizePredicate, useLabRecord } from '../useLabRecord';

const { record, links } = useLabRecord();

const notesDraft = ref('');
const isCuratedDraft = ref(true);

const capturedAt = computed(() =>
  record.value ? formatDate(record.value.recordCreatedAt) : null,
);
const publishedAt = computed(() =>
  record.value?.contentCreatedAt ? formatDate(record.value.contentCreatedAt) : null,
);

const outgoing = computed(() => links.value?.outgoingLinks ?? []);
const incoming = computed(() => links.value?.incomingLinks ?? []);

const tags = computed(() =>
  outgoing.value
    .filter((l) => l.predicate === 'tagged_with')
    .map((l) => ({ id: l.targetId, slug: l.target.slug, title: l.target.title })),
);

const linkGroups = computed(() => {
  // Skip tagged_with — surfaced separately in the tag chips row.
  const filtered = outgoing.value.filter((l) => l.predicate !== 'tagged_with');
  const groups = new Map<
    string,
    Array<{ id: number; slug: string; title: string | null; url?: string; icon?: string }>
  >();
  for (const link of filtered) {
    if (!groups.has(link.predicate)) groups.set(link.predicate, []);
    groups.get(link.predicate)!.push({
      id: link.targetId,
      slug: link.target.slug,
      title: link.target.title,
      url: (link.target as { url?: string }).url ?? undefined,
      icon: (link.target as { type?: string }).type
        ? getIconForRecordType((link.target as { type: string }).type)
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
.V2 {
  padding: 0 16px 48px;
}

.V2__page {
  max-width: 820px;
  margin: 0 auto;
  display: grid;
  gap: 24px;
}

.V2__titleRow {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: -8px;
}

.V2__title {
  font-size: 2rem;
  font-weight: 600;
  line-height: 1.15;
  letter-spacing: -0.01em;
  text-wrap: balance;
}

.V2__slug {
  font-family: var(--font-mono, ui-monospace, monospace);
  font-size: 0.7rem;
  color: var(--ui-text-dimmed);
}

.V2__dossier {
  border: 1px solid var(--ui-border);
  border-radius: var(--radius-xl);
  background: var(--ui-bg-elevated);
  overflow: hidden;
}

.V2__dossierGrid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0;
}

.V2__field {
  display: grid;
  grid-template-columns: 90px 1fr;
  gap: 12px;
  align-items: baseline;
  padding: 10px 14px;
  border-top: 1px solid var(--ui-border);
  border-right: 1px solid var(--ui-border);
  min-width: 0;
}

.V2__field:nth-child(-n + 2) {
  border-top: 0;
}

.V2__field:nth-child(even) {
  border-right: 0;
}

.V2__field--wide {
  grid-column: 1 / -1;
  border-right: 0;
}

.V2__field--span2 {
  grid-column: 1 / -1;
  border-right: 0;
  grid-template-columns: 90px 1fr;
}

.V2__label {
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--ui-text-dimmed);
}

.V2__value {
  font-size: 0.85rem;
  color: var(--ui-text);
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-width: 0;
  flex-wrap: wrap;
}

.V2__value--muted {
  color: var(--ui-text-dimmed);
}

.V2__valueIcon {
  width: 14px;
  height: 14px;
  color: var(--ui-text-muted);
}

.V2__value--url {
  font-size: 0.85rem;
}

.V2__value--chips {
  flex-wrap: wrap;
  gap: 4px;
}

.V2__tag {
  display: inline-flex;
  align-items: center;
  padding: 2px 8px;
  border-radius: 999px;
  background: var(--ui-bg);
  border: 1px solid var(--ui-border);
  font-size: 0.75rem;
  color: var(--ui-text);

  &:hover {
    background: var(--ui-bg-accented);
  }
}

.V2__tagAdd {
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

:deep(.V2__notesInput) {
  background: transparent;
  border: 0;
  box-shadow: none;
  padding: 0;
  font-size: 0.85rem;
}

.V2__dossierFooter {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 10px;
  background: var(--ui-bg);
  border-top: 1px solid var(--ui-border);
}

.V2__sep {
  height: 14px;
}

.V2__switch {
  margin-left: 4px;
}

.V2__id {
  margin-left: auto;
  font-family: var(--font-mono, ui-monospace, monospace);
  font-size: 0.7rem;
  color: var(--ui-text-dimmed);
}

.V2__summary p {
  font-size: 1.05rem;
  line-height: 1.55;
  color: var(--ui-text);
  margin: 0;
  padding-bottom: 4px;
  border-bottom: 1px solid var(--ui-border);
  max-width: 70ch;
}

.V2__content {
  font-size: 1rem;
  line-height: 1.65;

  :deep(.MarkdownRender) {
    font-size: 1rem;
    line-height: 1.65;
  }
}

.V2__contentPlaceholder {
  color: var(--ui-text-dimmed);
  font-style: italic;
}

.V2__links {
  display: grid;
  gap: 10px;
  margin-top: 16px;
}

.V2__linksHeader {
  display: flex;
  justify-content: space-between;
  align-items: baseline;

  & h2 {
    font-size: 0.85rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--ui-text-dimmed);
    font-weight: 600;
  }
}

.V2__linkGroups {
  display: grid;
  gap: 14px;
}

.V2__linkGroup {
  display: grid;
  grid-template-columns: 140px 1fr;
  gap: 14px;
  align-items: start;
  padding: 8px 0;
  border-top: 1px solid var(--ui-border);
}

.V2__linkGroupLabel {
  display: inline-flex;
  align-items: baseline;
  gap: 6px;
  font-size: 0.8rem;
  color: var(--ui-text);
  font-weight: 500;
  padding-top: 4px;
}

.V2__linkGroupCount {
  color: var(--ui-text-dimmed);
  font-size: 0.7rem;
}

.V2__linkRow {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
  list-style: none;
  margin: 0;
  padding: 0;
}

.V2__linkChip {
  display: inline-flex;
  align-items: baseline;
  gap: 6px;
  padding: 4px 10px;
  border-radius: var(--radius-md);
  background: var(--ui-bg);
  border: 1px solid var(--ui-border);
  font-size: 0.8rem;
  color: var(--ui-text);

  &:hover {
    background: var(--ui-bg-elevated);
  }
}

.V2__linkChipIcon {
  width: 12px;
  height: 12px;
  color: var(--ui-text-dimmed);
}

.V2__linkChipUrl {
  font-size: 0.7rem;
  color: var(--ui-text-dimmed);
}

.V2__incomingList {
  display: grid;
  gap: 4px;
  list-style: none;
  margin: 0;
  padding: 0;
}

.V2__incoming {
  display: grid;
  gap: 1px;
  padding: 5px 10px;
  border-radius: var(--radius-md);

  &:hover {
    background: var(--ui-bg-elevated);
  }
}

.V2__incomingTitle {
  font-size: 0.8rem;
  font-weight: 500;
  color: var(--ui-text);
}

.V2__incomingSnip {
  font-size: 0.7rem;
  color: var(--ui-text-muted);
  display: -webkit-box;
  -webkit-line-clamp: 1;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
</style>
